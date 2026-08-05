-- maps/amap/instance/instance.lua
-- 副本框架核心：注册/调度/生命周期/数据管理
--
-- 设计目标：
--   1. 任何玩法都可以通过 Instance.register 注册进框架
--   2. 玩法模块实现钩子函数，框架在生命周期对应时刻调用
--   3. 数据存储沿用 WPT.get().dungeons，向后兼容外部依赖
--   4. Public API 与内部状态严格分离
--
-- 依赖：
--   - WPT (maps.amap.table) - 全局数据存储
--   - Event (utils.event) - 事件注册
--   - Token/Task (utils.token/utils.task) - 延迟回滚
--   - rewards (maps.amap.instance.rewards) - 奖励池

local WPT = require 'maps.amap.table'
local Event = require 'utils.event'
local Token = require 'utils.token'
local Task = require 'utils.task'
local Rewards = require 'maps.amap.instance.rewards'

local Public = {}

--==============================================================================
-- 常量
--==============================================================================

-- 默认时间上限（30 分钟，单位 tick）
-- 玩法模块可在自己的 difficulty_settings 中覆盖
local DEFAULT_TIME_LIMIT = 30 * 60 * 60

-- 副本 surface 尺寸（与原 dungeon.lua 一致，保持挖币玩法地形不变）
local DUNGEON_HALF_SIZE = 50

-- 机器人科技黑名单（同步原角色科技时排除）
local ROBOT_TECH_BLACKLIST = {
    "robotics",
    "construction-robotics",
    "logistic-robotics",
    "personal-roboport",
    "personal-roboport-mk2",
    "auto-character-logistic-trash-slots",
    "worker-robots-speed-1",
    "worker-robots-speed-2",
    "worker-robots-speed-3",
    "worker-robots-speed-4",
    "worker-robots-speed-5",
    "worker-robots-speed-6",
    "worker-robots-storage-1",
    "worker-robots-storage-2",
    "worker-robots-storage-3"
}

-- 危险 recipe 黑名单（副本内禁用，与原 dungeon.lua 一致）
local DANGEROUS_RECIPES = {
    "grenade",
    "explosive-rocket",
    "firearm-magazine",
    "shotgun-shell",
    "piercing-rounds-magazine",
    "tank",
    "car"
}

--==============================================================================
-- 玩法注册表
--==============================================================================

-- type_name -> 玩法模块定义（local 表，不需要持久化）
-- 玩法定义是代码层面的，每次加载场景时通过 require 链路重新注册
local instance_registry = {}
-- 顺序记录（用于 GUI 显示稳定排序）
local instance_order = {}

--==============================================================================
-- GUI 元素名常量（与原 dungeon.lua 兼容）
--==============================================================================

local GUI_EXIT_BUTTON = 'dungeon_exit_button'
local GUI_TIMER = 'dungeon_timer'
local GUI_COINS = 'dungeon_coins'
local GUI_RECYCLING_PRICES_BUTTON = 'recycling_prices_button'
local GUI_DIFFICULTY_FRAME = 'difficulty_selection_frame'
local GUI_RECYCLING_PRICES_FRAME = 'recycling_prices_frame'
local GUI_INSTANCE_SELECTION_FRAME = 'instance_selection_frame'
local GUI_DIFFICULTY_CLOSE_BUTTON = 'dungeon_difficulty_close_button'

-- 史诗木箱全局上限（同时存在）
local EPIC_CHEST_MAX = 5
-- 史诗木箱总历史上限（本局累计生成数，重置地图时归零）
local EPIC_CHEST_TOTAL_MAX = 25

--==============================================================================
-- 数据管理
--==============================================================================

-- 获取/初始化玩家副本数据
-- 字段保留原 dungeon.lua 全部字段（向后兼容），新增框架字段
local function get_data(player_index)
    local this = WPT.get()
    if not this.dungeons then
        this.dungeons = {}
    end
    if not this.dungeons[player_index] then
        this.dungeons[player_index] = {
            -- === 既有字段（保持不变，外部依赖） ===
            active = false,
            surface_name = nil,
            original_surface = nil,
            original_character = nil,
            original_force = nil,
            original_position = nil,
            new_character = nil,
            dungeon_force = nil,
            start_tick = nil,
            time_limit = DEFAULT_TIME_LIMIT,
            player_index = nil,
            original_invincible = nil,
            coins_earned = 0,
            max_coins = 0,
            recycling_chest = nil,
            difficulty = "easy",
            recycling_efficiency = 1,

            -- === 框架新增字段 ===
            instance_type = nil,         -- 玩法类型（如 'coin_mine'）
            module_data = {},            -- 玩法私有数据（由模块自己管理）
            reward_multiplier = 0,       -- 副本提交的奖励系数（0=不给奖励，>0 按系数缩放）
            rewards_granted = {},        -- 已发放奖励记录
            victory_state = nil,         -- nil / 'ongoing' / 'victory' / 'defeat'
            epic_chest_unit_number = nil, -- 玩家从哪个史诗木箱进入副本（用于进入后删除该木箱）
        }
    end
    return this.dungeons[player_index]
end

Public.get_data = get_data

-- 判断 surface 是否为副本 surface（格式 dungeon_<digits>）
-- 供主世界模块未来做反向隔离使用（当前未启用反向隔离）
local function is_dungeon_surface(surface_name)
    if type(surface_name) ~= 'string' then return false end
    return string.find(surface_name, "^dungeon_%d+$") ~= nil
end

Public.is_dungeon_surface = is_dungeon_surface

-- 从副本 surface 名提取 player_index
local function parse_player_index_from_surface(surface_name)
    if not is_dungeon_surface(surface_name) then return nil end
    return tonumber(string.match(surface_name, "^dungeon_(%d+)$"))
end

--==============================================================================
-- Force / Surface / Character 管理
--==============================================================================

-- 清理副本 force：把已研究科技全部取消，然后 merge 到 player force
-- 与原 dungeon.lua cleanup_force 一致
local function cleanup_force(force_name)
    local force = game.forces[force_name]
    if not force then return end

    for tech_name, _ in pairs(force.technologies) do
        local tech = force.technologies[tech_name]
        if tech.researched then
            tech.researched = false
        end
    end

    game.merge_forces(force_name, "player")
end

-- 创建/复用副本 force，并与其他 force 建立友好关系
-- force_name = "dungeon_force_<player.name>"
local function setup_dungeon_force(force_name)
    local force = game.forces[force_name]
    if not force then
        force = game.create_force(force_name)
        force.set_friend("player", true)
        force.set_friend("enemy", false)
        force.set_cease_fire("enemy", true)

        for f_name, f in pairs(game.forces) do
            if f_name ~= force_name and f_name ~= "enemy" and f_name ~= "neutral" then
                force.set_friend(f_name, true)
                f.set_friend(force_name, true)
                force.share_chart = true
                f.share_chart = true
            end
        end
    end
    return force
end

-- 同步 player force 已研究科技到副本 force（排除机器人科技）
local function sync_technologies(force)
    for tech_name, tech in pairs(force.technologies) do
        local player_tech = game.forces["player"].technologies[tech_name]
        if player_tech and player_tech.researched then
            local is_robot_tech = false
            for _, robot_tech in ipairs(ROBOT_TECH_BLACKLIST) do
                if tech_name == robot_tech then
                    is_robot_tech = true
                    break
                end
            end
            if not is_robot_tech then
                tech.researched = true
            end
        end
    end
end

-- 禁用危险 recipe
local function disable_dangerous_recipes(force)
    for _, recipe_name in ipairs(DANGEROUS_RECIPES) do
        local recipe = force.recipes[recipe_name]
        if recipe then
            recipe.enabled = false
        end
    end
end

-- 创建副本 surface（与原 dungeon.lua 一致的 map_gen_settings）
local function create_dungeon_surface(surface_name)
    local surface = game.surfaces[surface_name]
    if surface then return surface end

    local map_gen_settings = {}
    if script.active_mods["space-age"] then
        map_gen_settings = game.planets["nauvis"].prototype.map_gen_settings
    end
    map_gen_settings['seed'] = math.random(1, 4294967295)
    map_gen_settings['starting_area'] = 1
    map_gen_settings['default_enable_all'] = true
    map_gen_settings['water'] = 0.4
    map_gen_settings['width'] = 100
    map_gen_settings['height'] = 100
    map_gen_settings['peaceful_mode'] = false

    -- 使用 autoplace_settings 全局禁用 entity/decorative 自动放置
    -- 避免 autoplace_controls 设 "0" 导致 2.1.x 噪声表达式编译 NaN
    map_gen_settings['autoplace_settings'] = {
        ['entity'] = {treat_missing_as_default = false},
        ['tile'] = {treat_missing_as_default = true},
        ['decorative'] = {treat_missing_as_default = false}
    }

    surface = game.create_surface(surface_name, map_gen_settings)
    surface.request_to_generate_chunks({0, 0}, 1)
    surface.force_generate_chunk_requests()

    return surface
end

--==============================================================================
-- GUI - 顶栏按钮（与原 dungeon.lua 兼容命名）
--==============================================================================

local function create_exit_button(player)
    local top = player.gui.top
    if not top[GUI_EXIT_BUTTON] then
        local button = top.add({
            type = 'button',
            name = GUI_EXIT_BUTTON,
            caption = {'amap.exit_dungeon'}
        })
        button.style.minimal_height = 38
        button.style.maximal_height = 38
        button.style.minimal_width = 100
    end
end

local function create_timer_label(player)
    local top = player.gui.top
    if not top[GUI_TIMER] then
        local label = top.add({
            type = 'label',
            name = GUI_TIMER,
            caption = ''
        })
        label.style.font_color = {1, 1, 0}
        label.style.font = 'default-bold'
    end
end

local function create_coins_label(player)
    local top = player.gui.top
    if not top[GUI_COINS] then
        local label = top.add({
            type = 'label',
            name = GUI_COINS,
            caption = ''
        })
        label.style.font_color = {1, 0.84, 0}
        label.style.font = 'default-bold'
    end
end

-- 清理顶栏所有副本相关 GUI
local function cleanup_top_gui(player)
    local top = player.gui.top
    if top[GUI_EXIT_BUTTON] then top[GUI_EXIT_BUTTON].destroy() end
    if top[GUI_TIMER] then top[GUI_TIMER].destroy() end
    if top[GUI_COINS] then top[GUI_COINS].destroy() end

    -- 玩法模块自定义的顶栏按钮由模块 on_cleanup_gui 负责清理
    -- 框架只负责通用部分；模块自定义按钮命名建议加 'dungeon_module_' 前缀
end

--==============================================================================
-- GUI - 玩法选择（新框架特性）
--==============================================================================

-- 显示玩法选择 GUI（可选 initial_type：预选某个玩法直接跳到难度选择）
function Public.show_selection_gui(player, initial_type)
    if not player or not player.valid then return end

    -- 若指定了 initial_type 且注册表中存在，直接跳难度选择
    -- 这保留了原 island_manager/rock 入口的"直接弹难度选择"行为
    if initial_type and instance_registry[initial_type] then
        Public.show_difficulty_selection_gui(player, initial_type)
        return
    end

    local screen = player.gui.screen
    if screen[GUI_INSTANCE_SELECTION_FRAME] then
        screen[GUI_INSTANCE_SELECTION_FRAME].destroy()
        return
    end

    if #instance_order == 0 then
        player.print({'amap.instance_no_module'}, {r = 1, g = 0.5, b = 0})
        return
    end

    local frame = screen.add({
        type = 'frame',
        name = GUI_INSTANCE_SELECTION_FRAME,
        caption = {'amap.instance_selection_title'},
        direction = 'vertical'
    })
    frame.auto_center = true

    local scroll = frame.add({
        type = 'scroll-pane',
        vertical_scroll_policy = 'auto',
        horizontal_scroll_policy = 'never'
    })
    scroll.style.maximal_height = 400
    scroll.style.minimal_width = 320

    local tbl = scroll.add({type = 'table', column_count = 1})
    tbl.style.horizontal_spacing = 5
    tbl.style.vertical_spacing = 5

    for _, type_name in ipairs(instance_order) do
        local def = instance_registry[type_name]
        local flow = tbl.add({type = 'flow', direction = 'vertical'})

        local title = flow.add({
            type = 'label',
            caption = {def.display_name_key}
        })
        title.style.font = 'default-bold'
        title.style.font_color = {1, 0.84, 0}

        if def.description_key then
            local desc = flow.add({
                type = 'label',
                caption = {def.description_key}
            })
            desc.style.single_line = false
        end

        local btn = flow.add({
            type = 'button',
            name = 'instance_select_' .. type_name,
            caption = {'amap.instance_select'}
        })
        btn.style.minimal_width = 200
        btn.tags = {instance_type = type_name}
    end
end

--==============================================================================
-- GUI - 副本难度卡片选择（三张卡片：easy/normal/hard）
-- 每张卡片显示：副本名、难度、玩法、预抽奖励、通关条件
-- 模仿天赋卡片 choise_skill 排版
--==============================================================================

-- 难度颜色（与天赋品质颜色体系一致）
local DIFFICULTY_COLOR = {
    easy   = {r = 80/255,  g = 140/255, b = 255/255},  -- 蓝（与 rare 一致）
    normal = {r = 180/255, g = 80/255,  b = 255/255},  -- 紫（与 epic 一致）
    hard   = {r = 255/255, g = 180/255, b = 60/255},   -- 橙（与 legendary 一致）
}

-- 难度顺序（保证卡片固定按 easy→normal→hard 排列）
local DIFFICULTY_ORDER = {'easy', 'normal', 'hard'}

function Public.show_difficulty_selection_gui(player, type_name, cache_key)
    if not player or not player.valid then return end

    -- type_name 参数仅为向后兼容，新版每张卡片单独随机副本类型，不再使用统一 type_name
    -- 但若 instance_order 为空则提前返回
    if not instance_order or #instance_order == 0 then
        player.print({'amap.instance_no_module'}, {r = 1, g = 0.5, b = 0})
        return
    end

    local screen = player.gui.screen

    -- 若之前打开了玩法选择框，先关闭
    if screen[GUI_INSTANCE_SELECTION_FRAME] then
        screen[GUI_INSTANCE_SELECTION_FRAME].destroy()
    end

    if screen[GUI_DIFFICULTY_FRAME] then
        screen[GUI_DIFFICULTY_FRAME].destroy()
        return
    end

    local frame = screen.add({
        type = 'frame',
        name = GUI_DIFFICULTY_FRAME,
        caption = {'amap.dungeon_difficulty_title'},
        direction = 'vertical'
    })
    frame.force_auto_center()

    local hint = frame.add({
        type = 'label',
        caption = {'amap.instance_card_hint'}
    })
    hint.style.font = 'default-bold'
    hint.style.font_color = {1, 0.84, 0}

    -- 关闭按钮：玩家可放弃进入副本（不扣任何东西，对应史诗木箱不会被删除）
    local close_flow = frame.add({type = 'flow', direction = 'horizontal'})
    close_flow.style.horizontal_align = 'right'
    close_flow.style.horizontally_stretchable = true
    local close_btn = close_flow.add({
        type = 'button',
        name = GUI_DIFFICULTY_CLOSE_BUTTON,
        caption = {'amap.instance_close_btn'}
    })
    close_btn.style.minimal_width = 80

    -- 横向卡片布局（参考 tianfu.lua choise_skill 第 943-949 行）
    local cards_flow = frame.add({
        type = 'flow',
        name = 'dungeon_cards_flow',
        direction = 'horizontal'
    })
    cards_flow.style.horizontal_spacing = 8
    cards_flow.style.vertical_align = 'top'

    local player_data = Public.get_data(player.index)
    -- 选项缓存机制：同个木箱（cache_key = unit_number）重复点开时复用上次生成的选项，
    -- 防止玩家关掉 GUI 重新刷选项；玩家点 enter 进入副本后会删除木箱，缓存也跟着失效
    if not player_data.epic_chest_options_cache then
        player_data.epic_chest_options_cache = {}
    end

    local cached_options = cache_key and player_data.epic_chest_options_cache[cache_key] or nil
    local options  -- 三张卡片的预抽结果数组

    if cached_options then
        -- 复用缓存：用上次生成的选项渲染卡片（玩家无法通过关掉 GUI 重开来刷新选项）
        options = cached_options
    else
        -- 首次点开此木箱：生成 3 张卡片选项，每张独立随机副本 + 难度 + 奖励
        options = {}
        for _ = 1, 3 do
            -- 1. 随机副本类型
            local random_type = instance_order[math.random(#instance_order)]
            local def = instance_registry[random_type]
            if not def then goto continue end

            -- 2. 随机难度（从该副本支持的难度中随机选一个）
            local diff_settings = def.difficulty_settings or {}
            local available_diffs = {}
            for _, dk in ipairs(DIFFICULTY_ORDER) do
                if diff_settings[dk] then
                    table.insert(available_diffs, dk)
                end
            end
            if #available_diffs == 0 then goto continue end
            local difficulty_key = available_diffs[math.random(#available_diffs)]

            -- 3. 按该难度从对应奖励池随机 1 个奖励
            local choices = Rewards.roll_choices(difficulty_key, 1, player)
            local preview_reward_id = nil
            local preview_info = nil
            if choices and #choices > 0 then
                preview_reward_id = choices[1].id
                preview_info = choices[1].preview
            end

            options[#options + 1] = {
                instance_type = random_type,
                difficulty = difficulty_key,
                reward_id = preview_reward_id,
                params = preview_info and preview_info.params or nil,
                -- 缓存 preview_info 用于卡片渲染（display_key/display_args 不参与 enter 流程）
                preview_info = preview_info
            }
            ::continue::
        end

        -- 缓存到玩家数据（若提供了 cache_key）
        if cache_key then
            player_data.epic_chest_options_cache[cache_key] = options
        end
    end

    -- 把 options 同步到 previewed_rewards（on_gui_click 按 card_index 取出）
    player_data.previewed_rewards = {}
    for i, opt in ipairs(options) do
        player_data.previewed_rewards[i] = opt
    end

    -- 渲染三张卡片
    for card_index, opt in ipairs(options) do
        local def = instance_registry[opt.instance_type]
        if not def then goto continue end

        local diff_settings = def.difficulty_settings or {}
        local difficulty_data = diff_settings[opt.difficulty]
        if not difficulty_data then goto continue end
        local color = DIFFICULTY_COLOR[opt.difficulty] or {r = 1, g = 1, b = 1}

        local preview_reward_def = opt.reward_id and Rewards.get_reward(opt.reward_id) or nil
        local preview_info = opt.preview_info

        -- 卡片容器
        local card = cards_flow.add({
            type = 'frame',
            name = 'dungeon_card_' .. card_index,
            direction = 'vertical'
        })
        card.style.minimal_width = 200
        card.style.maximal_width = 200
        card.style.padding = 8
        card.style.vertically_stretchable = true

        -- 1. 副本名（居中、heading-1）
        local name_flow = card.add({type = 'flow', direction = 'horizontal'})
        name_flow.style.horizontally_stretchable = true
        name_flow.style.horizontal_align = 'center'
        name_flow.style.minimal_height = 36
        name_flow.style.vertical_align = 'center'
        local name_label = name_flow.add({
            type = 'label',
            caption = {def.display_name_key or 'amap.instance_unknown'}
        })
        name_label.style.font = 'heading-1'
        name_label.style.font_color = color
        name_label.style.single_line = false
        name_label.style.maximal_width = 180

        -- 2. 难度标签（颜色按难度）
        local diff_flow = card.add({type = 'flow', direction = 'horizontal'})
        diff_flow.style.horizontally_stretchable = true
        diff_flow.style.horizontal_align = 'center'
        local diff_label = diff_flow.add({
            type = 'label',
            caption = {'amap.dungeon_difficulty_label', {'amap.' .. (difficulty_data.display_name_key or opt.difficulty)}}
        })
        diff_label.style.font = 'default-bold'
        diff_label.style.font_color = color

        -- 3. 副本图标（点击即选取该卡片）
        local icon_flow = card.add({type = 'flow', direction = 'horizontal'})
        icon_flow.style.horizontally_stretchable = true
        icon_flow.style.horizontal_align = 'center'
        icon_flow.style.vertical_align = 'top'
        icon_flow.style.top_padding = 4
        icon_flow.style.bottom_padding = 4
        local icon_btn = icon_flow.add({
            type = 'sprite-button',
            name = 'dungeon_card_icon_' .. card_index,  -- 用卡片索引，不再用 difficulty
            sprite = def.icon or 'item/coin',
            tooltip = {'amap.instance_card_enter_tip'},
            tags = {
                card_index = card_index  -- 点击时按索引取出 instance_type + difficulty + reward
            },
            mouse_button_filter = {'left'}
        })
        icon_btn.style.minimal_width = 80
        icon_btn.style.minimal_height = 80
        icon_btn.style.maximal_width = 80
        icon_btn.style.maximal_height = 80

        -- 4. 玩法描述
        local gameplay_flow = card.add({type = 'flow', direction = 'horizontal'})
        gameplay_flow.style.horizontally_stretchable = true
        gameplay_flow.style.horizontal_align = 'center'
        gameplay_flow.style.top_padding = 4
        local gameplay_label = gameplay_flow.add({
            type = 'label',
            caption = {'amap.instance_card_gameplay', {def.gameplay_desc_key or 'amap.instance_unknown'}}
        })
        gameplay_label.style.font = 'default'
        gameplay_label.style.single_line = false
        gameplay_label.style.maximal_width = 180

        -- 5. 通关条件
        local victory_flow = card.add({type = 'flow', direction = 'horizontal'})
        victory_flow.style.horizontally_stretchable = true
        victory_flow.style.horizontal_align = 'center'
        victory_flow.style.top_padding = 4
        local victory_label = victory_flow.add({
            type = 'label',
            caption = {'amap.instance_card_victory', {def.victory_condition_key or 'amap.instance_unknown'}}
        })
        victory_label.style.font = 'default'
        victory_label.style.single_line = false
        victory_label.style.maximal_width = 180

        -- 6. 预抽奖励（显示具体内容，如"激光伤害加成 +3%"而非分类名"伤害加成"）
        local reward_flow = card.add({type = 'flow', direction = 'horizontal'})
        reward_flow.style.horizontally_stretchable = true
        reward_flow.style.horizontal_align = 'center'
        reward_flow.style.top_padding = 4
        local reward_caption
        if preview_info and preview_info.display_key then
            -- 有 preview：显示具体奖励内容（如"激光伤害加成 +3%"）
            -- 关键：本地化串数组首元素 '' = 拼接模式，其中"普通字符串会被当字面文本"输出。
            --   · display_key 是 locale 键字符串（如 'amap.reward_force_modifier_preview'），
            --     绝不能平级追加——否则键名被当字面文本原样打印（曾出现 "amap.reward_..." 泄漏）；
            --     必须包成 {display_key, 参数...} 作为单个嵌套本地化串放进去（仅一层嵌套）。
            --   · display_key == '' 表示奖励侧已自行扁平化：display_args 各元素直接拼接，
            --     用于 recipe 这类参数本身深层嵌套（recipe.localised_name 是 {'?',...} 多层结构）、
            --     需尽量压平以避免"参数N"的场景。
            if preview_info.display_key == '' then
                reward_caption = {'', {'amap.instance_card_reward_label'}}
                if preview_info.display_args then
                    for _, arg in ipairs(preview_info.display_args) do
                        reward_caption[#reward_caption + 1] = arg
                    end
                end
            else
                local preview_str = {preview_info.display_key}
                if preview_info.display_args then
                    for _, arg in ipairs(preview_info.display_args) do
                        preview_str[#preview_str + 1] = arg
                    end
                end
                reward_caption = {'', {'amap.instance_card_reward_label'}, preview_str}
            end
        elseif preview_reward_def then
            -- 无 preview：回退到显示分类名
            reward_caption = {'', {'amap.instance_card_reward_label'}, {preview_reward_def.name_key}}
        else
            reward_caption = {'', {'amap.instance_card_reward_label'}, {'amap.instance_no_reward'}}
        end
        local reward_label = reward_flow.add({
            type = 'label',
            caption = reward_caption
        })
        reward_label.style.font = 'default-bold'
        reward_label.style.single_line = false
        reward_label.style.maximal_width = 180

        ::continue::
    end
end

--==============================================================================
-- 进入副本
--==============================================================================

-- 前向声明：clean_epic_chests / find_epic_chest_by_unit_number 是 local function，
-- 但 Public.enter 在它们定义之前就要调用，所以先声明 local 变量，定义在后面赋值
local clean_epic_chests
local find_epic_chest_by_unit_number

-- 玩家选好难度后调用：真正进入副本
-- type_name: 玩法类型；difficulty: easy/normal/hard
-- previewed_reward_id: 可选，预抽的奖励 ID（由卡片 GUI 传入，通关时直接发放此奖励 × multiplier）
-- previewed_reward_params: 可选，预抽的具体参数（如 {ammo_category='laser'}），由卡片 GUI 传入
function Public.enter(player, type_name, difficulty, previewed_reward_id, previewed_reward_params)
    if not player or not player.valid then return end
    if not type_name then type_name = 'coin_mine' end

    local player_index = player.index
    local data = get_data(player_index)

    -- 玩家通过史诗木箱进入副本 → 立即删除对应木箱（不看玩家是否通关）
    -- 放在所有 return 之前，保证只要 enter 被调用就一定删箱子
    -- 同时支持两种史诗木箱：
    --   1. 系统生成（在 epic_chests 数组中）→ 调用 remove_epic_chest 同步销毁地图标签
    --   2. 玩家手动放（不在数组中）→ 直接 entity.destroy()
    if data.epic_chest_entity then
        local ent = data.epic_chest_entity
        if ent and ent.valid then
            -- 先尝试 remove_epic_chest（同步销毁地图标签 + 从数组移除）
            -- 如果不在数组中（玩家手动放），remove_epic_chest 会无操作，再直接 destroy
            Public.remove_epic_chest(ent)
            if ent.valid then
                -- remove_epic_chest 没匹配到（玩家手动放的木箱），直接销毁
                ent.destroy()
            end
        end
        data.epic_chest_entity = nil
        data.epic_chest_unit_number = nil
    end

    local def = instance_registry[type_name]
    if not def then
        player.print({'amap.instance_unknown_type', tostring(type_name)}, {r = 1, g = 0, b = 0})
        return
    end

    if data.active then
        player.print({'amap.dungeon_already_active'}, {r = 1, g = 0, b = 0})
        return
    end

    -- 难度校验
    local difficulty_key = difficulty or "easy"
    local diff_settings = def.difficulty_settings or {}
    local difficulty_data = diff_settings[difficulty_key]
    if not difficulty_data then
        difficulty_key = "easy"
        difficulty_data = diff_settings.easy
    end
    if not difficulty_data then
        player.print({'amap.instance_no_difficulty'}, {r = 1, g = 0, b = 0})
        return
    end

    -- 写入副本数据
    data.instance_type = type_name
    data.difficulty = difficulty_key
    data.recycling_efficiency = difficulty_data.recycling_efficiency or 1
    data.max_coins = difficulty_data.max_coins or 0
    data.coins_earned = 0
    data.time_limit = def.time_limit_default or DEFAULT_TIME_LIMIT
    data.module_data = {}
    data.reward_multiplier = 0
    data.previewed_reward_id = previewed_reward_id  -- 预抽的奖励 ID（进入副本时已确定）
    data.previewed_reward_params = previewed_reward_params  -- 预抽的具体参数（如 {ammo_category='laser'}）
    data.rewards_granted = {}
    data.victory_state = 'ongoing'

    -- 框架级钩子：on_difficulty_selected
    -- 让玩法模块在 surface 创建前知道难度，便于在 on_surface_init 时根据难度调整地形
    if def.on_difficulty_selected then
        def.on_difficulty_selected(player, data, difficulty_key)
    end

    player.print({'amap.dungeon_difficulty_selected',
                  {'amap.' .. difficulty_data.display_name_key}},
                 {r = 0, g = 1, b = 0})

    -- 保存原状态
    data.original_surface = player.surface.name
    data.original_character = player.character
    data.original_force = player.force.name
    data.original_position = {x = player.position.x, y = player.position.y}
    data.player_index = player_index
    data.active = true
    data.start_tick = game.tick

    if data.original_character then
        data.original_character.destructible = false
        data.original_invincible = true
        -- Factorio 2.1：物流备份改用 saved_logistic_filters（SavedLogisticFilters 读写）
        data.backup_logistic_filters = player.saved_logistic_filters
    end

    -- 创建/复用副本 force
    local force_name = "dungeon_force_" .. player.name
    local force = setup_dungeon_force(force_name)
    data.dungeon_force = force_name
    player.force = force

    -- 同步科技（仅挖币工厂等「需要主世界科技」的副本开启）
    -- 其他副本（竞技/解谜/战斗类）一律不继承主世界科技，否则满科技会破坏副本平衡
    if def.needs_tech_sync then
        sync_technologies(force)
    end
    -- 禁用危险 recipe（与科技同步无关，所有副本统一禁用，防止副本内手工搓武器/载具）
    disable_dangerous_recipes(force)

    -- 框架级钩子：on_force_created
    -- 在科技同步 + 危险 recipe 禁用之后、surface 创建之前
    -- 让玩法模块可以设置 force 属性（如禁用特定科技、设置 modifier）
    if def.on_force_created then
        def.on_force_created(player, data, force)
    end

    -- 创建 surface
    local surface_name = "dungeon_" .. player_index
    local surface = create_dungeon_surface(surface_name)
    force.set_spawn_position({0, 0}, surface)

    data.surface_name = surface_name

    -- 调用玩法的 on_surface_init（生成地形、矿脉、市场、回收箱等）
    if def.on_surface_init then
        def.on_surface_init(surface, player, data, difficulty_key)
    end

    -- 让 player force 在副本 surface 上 chart 一块区域（与原 dungeon.lua 一致）
    local player_force = game.forces["player"]
    player_force.chart(surface, {{-DUNGEON_HALF_SIZE, -DUNGEON_HALF_SIZE},
                                  {DUNGEON_HALF_SIZE,  DUNGEON_HALF_SIZE}})

    -- 创建新 character，切换 controller
    local new_character = surface.create_entity({
        name = "character",
        position = {0, 0},
        force = force
    })

    if not new_character or not new_character.valid then
        player.print({'amap.dungeon_creation_failed'}, {r = 1, g = 0, b = 0})
        Public.exit(player, "error")
        return
    end

    data.new_character = new_character

    player.set_controller({type = defines.controllers.ghost})
    player.teleport({0, 0}, surface)
    player.set_controller({
        type = defines.controllers.character,
        character = new_character
    })

    -- 创建通用顶栏 GUI（exit/timer/coins）
    create_exit_button(player)
    create_timer_label(player)
    create_coins_label(player)

    -- 调用玩法的 on_enter（给初始物品、设置 force modifier、创建模块自定义 GUI 等）
    if def.on_enter then
        def.on_enter(player, data, difficulty_key)
    end

    player.print({'amap.dungeon_enter_msg'}, {r = 0, g = 1, b = 0})
    game.print({'amap.player_entered_dungeon', player.name,
                {def.display_name_key},
                {'amap.' .. difficulty_data.display_name_key}},
               {r = 0, g = 1, b = 0})
end

--==============================================================================
-- 退出副本
--==============================================================================

-- 转移新角色背包到原角色，coin 受 max_coins 限制
-- 与原 dungeon.lua 逻辑一致，但抽离为独立函数
local function transfer_inventory_to_original(data)
    if not (data.new_character and data.new_character.valid) then return end
    if not (data.original_character and data.original_character.valid) then return end

    local new_character = data.new_character
    local old_character = data.original_character

    -- coin 直接转（已通过 coins_earned 跟踪，不算入新角色转移）
    local coins = new_character.get_item_count("coin")
    if coins > 0 then
        old_character.insert({name = "coin", count = coins})
    end

    local inventories = {
        defines.inventory.character_main,
        defines.inventory.character_trash,
        defines.inventory.character_ammo,
        defines.inventory.character_armor,
        defines.inventory.character_guns
    }

    for _, inv_type in ipairs(inventories) do
        local inv = new_character.get_inventory(inv_type)
        if inv then
            for i = 1, #inv do
                local item = inv[i]
                if item.valid_for_read and item.name ~= "coin" then
                    old_character.insert({name = item.name, count = item.count})
                end
            end
        end
    end
end

-- 退出副本主流程
-- reason: "manual" / "timeout" / "error" / "victory" / "defeat"
function Public.exit(player, reason)
    if not player or not player.valid then return end

    local player_index = player.index
    local data = get_data(player_index)

    if not data.active then return end

    -- [DIAG] 记录进入 exit 时的 force 状态
    log('[Instance.exit DIAG] player=' .. player.name
        .. ' player_force=' .. (player.force and player.force.name or 'nil')
        .. ' original_force=' .. tostring(data.original_force)
        .. ' orig_char_valid=' .. tostring(data.original_character and data.original_character.valid)
        .. ' reason=' .. tostring(reason))

    -- 通知玩法模块：我要退出了（让模块先清理 surface 上的实体、自定义 GUI 等）
    local def = instance_registry[data.instance_type]
    if def and def.on_exit then
        def.on_exit(player, data, reason)
    end

    -- 转移背包到原角色
    transfer_inventory_to_original(data)

    -- 销毁新角色
    if data.new_character and data.new_character.valid then
        data.new_character.destroy()
    end

    -- 切回原角色
    if data.original_character and data.original_character.valid then
        data.original_character.destructible = true

        if data.original_surface then
            local original_surface = game.surfaces[data.original_surface]
            if original_surface then
                player.set_controller({type = defines.controllers.ghost})
                player.teleport(data.original_position, original_surface)

                player.set_controller({
                    type = defines.controllers.character,
                    character = data.original_character
                })

                -- 恢复原角色的个人物流设置（与 enter 中的 backup_logistic_filters 配对）
                if data.backup_logistic_filters then
                    player.saved_logistic_filters = data.backup_logistic_filters
                    data.backup_logistic_filters = nil
                end
            end
        end
    end

    -- 无条件还原阵营：不依赖原角色/原表面/原 force 是否有效。
    -- 原实现把 force 还原嵌套在 4 层 if 内（original_character.valid 等），
    -- 玩家在副本期间主世界原角色被虫子击杀 → 还原被跳过 → force 残留
    -- dungeon_force_* → 天赋（force=='player' 过滤）全失效 + 伤害加成丢失。
    if data.original_force then
        local original_force = game.forces[data.original_force]
        if original_force and original_force.valid then
            player.force = original_force
        else
            player.force = game.forces.player
        end
    end

    -- 清理 force
    if data.dungeon_force then
        cleanup_force(data.dungeon_force)
    end

    -- 框架级钩子：on_surface_about_to_delete
    -- 在 surface 删除前触发，让玩法模块抢救数据（如统计产出、记录成就）
    -- 注意：此时玩家已切回原角色，但 surface 和 data 仍然可用
    local def = instance_registry[data.instance_type]
    if def and def.on_surface_about_to_delete then
        local surface = game.surfaces[data.surface_name]
        if surface then
            def.on_surface_about_to_delete(player, data, surface)
        end
    end

    -- 删除 surface
    if data.surface_name then
        local surface = game.surfaces[data.surface_name]
        if surface then
            game.delete_surface(data.surface_name)
        end
    end

    -- 清理通用 GUI
    cleanup_top_gui(player)
    local screen = player.gui.screen
    if screen[GUI_RECYCLING_PRICES_FRAME] then
        screen[GUI_RECYCLING_PRICES_FRAME].destroy()
    end

    -- 处理奖励发放（仅胜利时）
    local earned_coins = data.coins_earned or 0

    -- 记录副本信息（data 即将被清空，先把公告需要的字段取出）
    local victory_state = data.victory_state
    local instance_name_key = def and def.display_name_key or 'amap.instance_unknown'
    local difficulty_name_key = 'amap.' .. ((def and def.difficulty_settings
                                            and def.difficulty_settings[data.difficulty]
                                            and def.difficulty_settings[data.difficulty].display_name_key)
                                           or data.difficulty or 'easy')
    local previewed_reward_id = data.previewed_reward_id

    -- 清空 dungeons[idx]
    local this = WPT.get()
    this.dungeons[player_index] = nil

    -- 消息提示（玩家私人消息）
    if reason == "timeout" then
        player.print({'amap.dungeon_timeout_msg'}, {r = 1, g = 0.5, b = 0})
    elseif reason == "manual" then
        player.print({'amap.dungeon_exit_msg'}, {r = 1, g = 1, b = 0})
    elseif reason == "error" then
        player.print({'amap.dungeon_error_msg'}, {r = 1, g = 0, b = 0})
    elseif reason == "victory" then
        player.print({'amap.dungeon_victory_msg'}, {r = 0, g = 1, b = 0})
    elseif reason == "defeat" then
        player.print({'amap.dungeon_defeat_msg'}, {r = 1, g = 0.3, b = 0.3})
    else
        player.print({'amap.dungeon_success_msg', earned_coins}, {r = 0, g = 1, b = 0})
    end

    if earned_coins > 0 then
        game.print({'amap.dungeon_earned_coins_msg', player.name, earned_coins},
                   {r = 0.2, g = 0.8, b = 0.2})
    end

    -- 奖励发放：非 defeat/error 退出且 multiplier > 0 时发放预抽奖励
    -- 系数 = 0 → 不给任何奖励
    -- 系数 > 0 → 发放 data.previewed_reward_id 奖励，数值按系数缩放
    -- 奖励在进入副本前已预抽确定（含具体参数如"激光"），玩家表现只影响系数
    -- 注：coin_mine 等无胜利条件的玩法，靠 on_exit 设置 multiplier 来发放奖励
    local reward_granted = false
    if reason ~= "defeat" and reason ~= "error" then
        local multiplier = data.reward_multiplier or 0

        -- [DIAG] 记录发奖前的 force 状态
        log('[Instance.exit DIAG] before grant player=' .. player.name
            .. ' player_force=' .. (player.force and player.force.name or 'nil')
            .. ' previewed_reward_id=' .. tostring(previewed_reward_id)
            .. ' multiplier=' .. tostring(multiplier))

        if multiplier > 0 and previewed_reward_id then
            Rewards.grant(player, previewed_reward_id, data, multiplier, data.previewed_reward_params)

            -- 记录已发放
            data.rewards_granted[#data.rewards_granted + 1] = {
                reward_id = previewed_reward_id,
                multiplier = multiplier,
                granted_tick = game.tick
            }

            -- 触发玩法模块的 on_reward_selected 钩子
            local def_hook = instance_registry[data.instance_type]
            if def_hook and def_hook.on_reward_selected then
                def_hook.on_reward_selected(player, previewed_reward_id)
            end

            reward_granted = true
        end
    end

    -- 全局公告：副本结果（成功/失败 + 奖励）
    -- manual 退出不广播（玩家自己放弃）；error 不广播（异常，避免噪音）
    if reason == "victory" then
        if reward_granted then
            local reward_def = Rewards.get_reward(previewed_reward_id)
            local reward_name_key = reward_def and reward_def.name_key or 'amap.instance_no_reward'
            game.print({'amap.dungeon_result_victory_with_reward',
                        player.name, {instance_name_key}, {difficulty_name_key}, {reward_name_key}},
                       {r = 0, g = 1, b = 0})
        else
            game.print({'amap.dungeon_result_victory_no_reward',
                        player.name, {instance_name_key}, {difficulty_name_key}},
                       {r = 0, g = 1, b = 0})
        end
    elseif reason == "defeat" or reason == "timeout" then
        game.print({'amap.dungeon_result_defeat',
                    player.name, {instance_name_key}, {difficulty_name_key}},
                   {r = 1, g = 0.3, b = 0.3})
    end
end

--==============================================================================
-- 副本模块接口：设置奖励系数
--==============================================================================

-- 副本模块在 check_victory 返回 'victory' 前（或 on_exit 里 reason=='victory' 时）调用
-- multiplier: 奖励系数
--   - 0：不给任何奖励
--   - >0：弹 3 选 1 GUI，奖励内容不变，数值按系数缩放
-- 副本不调用此接口时，默认系数为 0（不给奖励）
function Public.set_reward_multiplier(player, multiplier)
    if not player or not player.valid then return end
    local this = WPT.get()
    if not this.dungeons or not this.dungeons[player.index] then return end
    local data = this.dungeons[player.index]
    if not data.active then return end

    local mult = tonumber(multiplier) or 0
    if mult < 0 then mult = 0 end
    data.reward_multiplier = mult
end

--==============================================================================
-- 注册接口
--==============================================================================

-- 注册玩法模块
-- def 必须包含：
--   type (string): 玩法类型唯一标识，如 'coin_mine'
--   display_name_key (string): locale 键
--   description_key (string, 可选): locale 键
--   time_limit_default (number, 可选): 默认时间上限（tick）
--   difficulty_settings (table): { easy={...}, normal={...}, hard={...} }
--       每档难度字段：display_name_key / recycling_efficiency / max_coins
--       （字段名沿用原 dungeon.lua，挖币玩法需要；其他玩法可在 module_data 中扩展）
--   钩子函数（详见项目设计文档 2.4）：
--       on_surface_init / on_enter / on_exit / on_tick / on_player_died
--       check_victory / get_rewards / on_create_gui / on_cleanup_gui
function Public.register(type_name, def)
    if not type_name or type_name == "" then
        error("Instance.register: type_name 不能为空")
    end
    if not def then
        error("Instance.register: def 不能为空 (type=" .. tostring(type_name) .. ")")
    end
    if not def.display_name_key then
        error("Instance.register: def.display_name_key 必填 (type=" .. type_name .. ")")
    end
    if not def.difficulty_settings then
        error("Instance.register: def.difficulty_settings 必填 (type=" .. type_name .. ")")
    end

    instance_registry[type_name] = def

    -- 记录顺序（避免重复）
    local already = false
    for _, t in ipairs(instance_order) do
        if t == type_name then already = true break end
    end
    if not already then
        instance_order[#instance_order + 1] = type_name
    end
end

-- 获取玩法注册信息
function Public.get_registry()
    return instance_registry
end

function Public.get_module(type_name)
    return instance_registry[type_name]
end

-- 获取玩法顺序表（数组，用于随机选副本）
function Public.get_instance_order()
    return instance_order
end

--==============================================================================
-- 史诗木箱管理 API
--==============================================================================

-- 清理失效项 + 返回当前列表（数组）
-- 列表项结构：{entity = LuaEntity, tag = ChartTag|nil}
-- 注意 Factorio 2.x：add_chart_tag 返回 ChartTag 对象，销毁用 tag.destroy()
-- 已在文件开头前向声明为 local，这里赋值
clean_epic_chests = function()
    local this = WPT.get()
    if not this.epic_chests then this.epic_chests = {} end
    for i = #this.epic_chests, 1, -1 do
        local entry = this.epic_chests[i]
        local ent = entry and entry.entity
        if not ent or not ent.valid then
            -- 实体失效时同步销毁地图标签（避免孤儿 tag）
            if entry and entry.tag and entry.tag.valid then
                entry.tag.destroy()
            end
            table.remove(this.epic_chests, i)
        end
    end
    return this.epic_chests
end

-- 在指定位置生成一个史诗木箱（不可摧毁/不可挖掘/不可操作）
-- 返回生成的 entity，若已达上限或位置不合法返回 nil
function Public.spawn_epic_chest(surface, position)
    if not surface or not surface.valid then return nil end
    local this = WPT.get()
    if not this.epic_chest_total then this.epic_chest_total = 0 end
    if this.epic_chest_total >= EPIC_CHEST_TOTAL_MAX then return nil end
    local chests = clean_epic_chests()
    if #chests >= EPIC_CHEST_MAX then return nil end

    -- 'out-of-map' tile 上不能生成
    local get_tile = surface.get_tile(position)
    if get_tile.valid and get_tile.name == 'out-of-map' then return nil end

    -- 找一个非冲突位置（半径 4，精度 1）
    local pos = surface.find_non_colliding_position('wooden-chest', position, 4, 1, true)
    if not pos then return nil end

    local entity = surface.create_entity({name = 'wooden-chest', position = pos, force = 'neutral', quality = 'epic'})
    if not entity or not entity.valid then return nil end
    entity.destructible = false      -- 不可摧毁
    entity.minable_flag = false      -- 不可挖掘
    -- operable 必须为 true：否则 on_gui_opened 不会触发（Factorio 行为）
    -- 改为在 on_gui_opened handler 内立刻 player.opened = nil 关闭官方箱子 GUI
    entity.operable = true

    -- 添加地图标签（参考瓶子组装机 production.lua register_random_assembler 的实现）
    -- 用 add_chart_tag 而非 rendering.draw_text：前者在远程地图上可见，玩家可远距离定位
    -- Factorio 2.x：add_chart_tag 的 text 参数接受纯字符串，不支持 LocalisedString table
    -- 用 locale key 字符串形式传递（如 "amap.epic_chest_marker" 或其他已注册 locale 键名）
    -- 但此处直接写明文以兼容：
    local tag = game.forces.player.add_chart_tag(surface, {
        position = entity.position,
        icon = {type = 'item', name = 'wooden-chest'},
        text = 'Epic Dungeon'
    })

    chests[#chests + 1] = {entity = entity, tag = tag}
    this.epic_chest_total = this.epic_chest_total + 1
    return entity
end

-- 判断指定 entity 是否为史诗木箱
-- 识别依据：wooden-chest + quality='epic'
--   - 普通木箱：quality='normal' → 不匹配
--   - 传说木箱（magic_wood）：quality='legendary' → 不匹配
--   - 史诗木箱（系统生成或玩家手动放）：quality='epic' → 匹配
-- 用品质识别而非注册数组，让玩家手动放的史诗品质木箱也能触发副本面板
function Public.is_epic_chest(entity)
    if not entity or not entity.valid then return false end
    if entity.name ~= 'wooden-chest' then return false end
    local quality = entity.quality
    if not quality or quality.name ~= 'epic' then return false end
    return true
end

-- 按 unit_number 在已注册列表中查找对应 entry {entity, text_id}
-- 已在文件开头前向声明为 local，这里赋值
find_epic_chest_by_unit_number = function(unit_number)
    if not unit_number then return nil end
    local chests = clean_epic_chests()
    for _, entry in ipairs(chests) do
        if entry.entity and entry.entity.unit_number == unit_number then return entry end
    end
    return nil
end

-- 删除指定史诗木箱（按 entity 引用）并从注册表中移除
-- 同时销毁对应的地图标签（ChartTag）
function Public.remove_epic_chest(entity)
    if not entity or not entity.valid then return end
    local this = WPT.get()
    if not this.epic_chests then return end
    for i = #this.epic_chests, 1, -1 do
        local entry = this.epic_chests[i]
        if entry.entity == entity then
            -- 先销毁地图标签（ChartTag.destroy）
            if entry.tag and entry.tag.valid then
                entry.tag.destroy()
            end
            if entry.entity.valid then entry.entity.destroy() end
            table.remove(this.epic_chests, i)
            return
        end
    end
end

--==============================================================================
-- 事件分发
--==============================================================================

-- 把事件转发给当前玩家副本对应的玩法模块
-- 仅当玩家在副本中且玩法模块定义了对应钩子时调用
local function dispatch_to_module(player_index, hook_name, ...)
    local this = WPT.get()
    if not this.dungeons or not this.dungeons[player_index] then return end
    local data = this.dungeons[player_index]
    if not data.active then return end

    local def = instance_registry[data.instance_type]
    if not def then return end

    local hook = def[hook_name]
    if hook then
        hook(...)
    end
end

--==============================================================================
-- nth_tick 调度
--==============================================================================

-- 每 600 tick（10 秒）：超时检测 + 超时预警
local function on_nth_tick_timeout()
    local this = WPT.get()
    if not this.dungeons then return end

    for player_index, data in pairs(this.dungeons) do
        if data.active then
            local elapsed = game.tick - data.start_tick
            local remaining = (data.time_limit or DEFAULT_TIME_LIMIT) - elapsed

            -- 框架级钩子：on_timeout_warning
            -- 在剩余时间 <= 60 秒（3600 tick）/ 30 秒（1800 tick）/ 10 秒（600 tick）时触发
            -- 每个阈值只触发一次，通过 data.timeout_warning_sent 标记
            if remaining > 0 then
                local def = instance_registry[data.instance_type]
                if def and def.on_timeout_warning then
                    data.timeout_warning_sent = data.timeout_warning_sent or {}
                    if remaining <= 600 and not data.timeout_warning_sent[600] then
                        data.timeout_warning_sent[600] = true
                        local player = game.players[player_index]
                        if player and player.valid then
                            def.on_timeout_warning(player, data, 10)
                        end
                    elseif remaining <= 1800 and not data.timeout_warning_sent[1800] then
                        data.timeout_warning_sent[1800] = true
                        local player = game.players[player_index]
                        if player and player.valid then
                            def.on_timeout_warning(player, data, 30)
                        end
                    elseif remaining <= 3600 and not data.timeout_warning_sent[3600] then
                        data.timeout_warning_sent[3600] = true
                        local player = game.players[player_index]
                        if player and player.valid then
                            def.on_timeout_warning(player, data, 60)
                        end
                    end
                end
            end

            if remaining <= 0 then
                local player = game.players[player_index]
                if player and player.valid then
                    Public.exit(player, "timeout")
                else
                    -- 玩家不在线，强制清理
                    -- 先还原离线玩家 force（对象仍有效），避免重连后 force 残留 dungeon_force_*，
                    -- 与 Public.exit 的无条件还原保持一致
                    if player and data.original_force then
                        local original_force = game.forces[data.original_force]
                        if original_force and original_force.valid then
                            player.force = original_force
                        else
                            player.force = game.forces.player
                        end
                    end
                    if data.dungeon_force then
                        cleanup_force(data.dungeon_force)
                    end
                    if data.surface_name then
                        game.delete_surface(data.surface_name)
                    end
                    this.dungeons[player_index] = nil
                end
            end
        end
    end
end

-- 每 60 tick（1 秒）：UI 更新 + 玩法 on_tick + 通关检测
local function on_nth_tick()
    local this = WPT.get()
    if not this.dungeons then return end

    for player_index, data in pairs(this.dungeons) do
        if data.active then
            local player = game.players[player_index]
            if not (player and player.valid and player.connected) then
                goto continue
            end

            local elapsed = game.tick - data.start_tick
            local remaining = (data.time_limit or DEFAULT_TIME_LIMIT) - elapsed

            if remaining > 0 then
                -- 通用计时器更新
                local timer_label = player.gui.top[GUI_TIMER]
                if timer_label then
                    local minutes = math.floor(remaining / 3600)
                    local seconds = math.floor((remaining % 3600) / 60)
                    timer_label.caption = {'amap.dungeon_time_remaining', minutes, seconds}
                end

                -- 通用金币显示更新
                local coins_label = player.gui.top[GUI_COINS]
                if coins_label then
                    local coins = data.coins_earned or 0
                    local max_coins = data.max_coins or 0
                    coins_label.caption = {'amap.dungeon_coins_earned', coins, max_coins}
                end

                -- 玩法 on_tick
                dispatch_to_module(player_index, 'on_tick', player, data)

                -- 通关检测
                local def = instance_registry[data.instance_type]
                if def and def.check_victory then
                    local result = def.check_victory(player, data)
                    if result == 'victory' then
                        data.victory_state = 'victory'
                        Public.exit(player, 'victory')
                    elseif result == 'defeat' then
                        data.victory_state = 'defeat'
                        Public.exit(player, 'defeat')
                    end
                end
            end

            ::continue::
        end
    end
end

-- 每 5 tick（~0.083 秒）：高频钩子，供需要快速刷新的玩法模块使用
-- 模块未定义 on_fast_tick 时自动跳过（dispatch_to_module 内 if hook then 判定）
-- 仅调度玩法钩子，不重复做计时器/金币/胜负判定（保留在 60 tick 内）
local function on_nth_tick_fast()
    local this = WPT.get()
    if not this.dungeons then return end

    for player_index, data in pairs(this.dungeons) do
        if data.active then
            local player = game.players[player_index]
            if not (player and player.valid and player.connected) then
                goto continue
            end

            local elapsed = game.tick - data.start_tick
            local remaining = (data.time_limit or DEFAULT_TIME_LIMIT) - elapsed
            if remaining > 0 then
                dispatch_to_module(player_index, 'on_fast_tick', player, data)
            end

            ::continue::
        end
    end
end

--==============================================================================
-- 通用事件处理（GUI click / 玩家死亡 / 实体建造等）
--==============================================================================

-- 通用 on_gui_click：处理框架自身 GUI + 分发到玩法模块
local function on_gui_click(event)
    local element = event.element
    if not element or not element.valid then return end

    local player = game.players[event.player_index]
    if not player or not player.valid then return end

    local name = element.name

    -- 1. 退出按钮
    if name == GUI_EXIT_BUTTON then
        Public.exit(player, "manual")
        return
    end

    -- 1.5 难度选择面板关闭按钮：玩家放弃进入副本
    if name == GUI_DIFFICULTY_CLOSE_BUTTON then
        if player.gui.screen[GUI_DIFFICULTY_FRAME] then
            player.gui.screen[GUI_DIFFICULTY_FRAME].destroy()
        end
        -- 清空待处理史诗木箱标记（玩家放弃，木箱不删除）
        local player_data = Public.get_data(player.index)
        player_data.epic_chest_unit_number = nil
        player_data.epic_chest_entity = nil
        return
    end

    -- 2. 副本难度卡片图标点击 'dungeon_card_icon_<card_index>'
    -- 新版每张卡片单独随机 instance_type + difficulty + reward，按 card_index 取出
    local card_index_str = name:match('^dungeon_card_icon_(%d+)$')
    if card_index_str then
        local card_index = tonumber(card_index_str)

        -- 从玩家副本数据读取此卡片的预抽结果（含 instance_type + difficulty + reward）
        local player_data = Public.get_data(player.index)
        local preview = player_data.previewed_rewards and player_data.previewed_rewards[card_index]
        if not preview then
            player.print({'amap.instance_unknown_type', 'card_index=' .. tostring(card_index)}, {r = 1, g = 0, b = 0})
            return
        end

        local type_name = preview.instance_type or 'coin_mine'
        local difficulty_key = preview.difficulty or 'easy'
        local preview_reward_id = preview.reward_id
        local preview_reward_params = preview.params

        -- 清理预抽缓存（已使用）
        if player_data.previewed_rewards then
            player_data.previewed_rewards[card_index] = nil
        end

        if player.gui.screen[GUI_DIFFICULTY_FRAME] then
            player.gui.screen[GUI_DIFFICULTY_FRAME].destroy()
        end
        Public.enter(player, type_name, difficulty_key, preview_reward_id, preview_reward_params)
        return
    end

    -- 3. 其他 GUI click 分发给玩法模块（如回收箱价目表按钮）
    dispatch_to_module(event.player_index, 'on_gui_click', player, event)
end

-- 玩家死亡：通知玩法模块
local function on_player_died(event)
    local player_index = event.player_index
    local player = game.players[player_index]
    if not player or not player.valid then return end

    local this = WPT.get()
    if not this.dungeons or not this.dungeons[player_index] then return end
    local data = this.dungeons[player_index]
    if not data.active then return end

    -- 死亡在副本 surface 才算
    if not data.surface_name then return end
    if not player.surface or player.surface.name ~= data.surface_name then return end

    dispatch_to_module(player_index, 'on_player_died', player, data)
end

-- 实体建造：玩家在副本里建实体，先框架无操作，再分发到玩法模块
-- （挖币玩法用此事件实现"建石墙给币"）
local function on_built_entity(event)
    local player = game.players[event.player_index]
    if not player or not player.valid then return end

    local this = WPT.get()
    if not this.dungeons or not this.dungeons[player.index] then return end
    local data = this.dungeons[player.index]
    if not data.active then return end
    if not data.surface_name then return end
    if player.surface.name ~= data.surface_name then return end

    dispatch_to_module(event.player_index, 'on_built_entity', player, event)
end

-- 机器人建造实体：仅当实体在副本 surface 上时分发
local function on_robot_built_entity(event)
    local entity = event.entity
    if not entity or not entity.valid then return end

    local surface_name = entity.surface.name
    if not string.find(surface_name, "^dungeon_%d+$") then return end

    local player_index = tonumber(string.match(surface_name, "^dungeon_(%d+)$"))
    if not player_index then return end

    local this = WPT.get()
    if not this.dungeons or not this.dungeons[player_index] then return end
    local data = this.dungeons[player_index]
    if not data.active then return end

    local player = game.players[player_index]
    if not (player and player.valid) then return end

    dispatch_to_module(player_index, 'on_robot_built_entity', player, event)
end

-- 玩家挖实体：仅当玩家在副本里时分发
local function on_player_mined_entity(event)
    local player = game.players[event.player_index]
    if not player or not player.valid then return end

    local this = WPT.get()
    if not this.dungeons or not this.dungeons[player.index] then return end
    local data = this.dungeons[player.index]
    if not data.active then return end
    if not data.surface_name then return end
    if player.surface.name ~= data.surface_name then return end

    dispatch_to_module(event.player_index, 'on_player_mined_entity', player, event)
end

-- 玩家挖资源：仅当玩家在副本里时分发
local function on_pre_player_mined_item(event)
    local player = game.players[event.player_index]
    if not player or not player.valid then return end

    local this = WPT.get()
    if not this.dungeons or not this.dungeons[player.index] then return end
    local data = this.dungeons[player.index]
    if not data.active then return end
    if not data.surface_name then return end
    if player.surface.name ~= data.surface_name then return end

    dispatch_to_module(event.player_index, 'on_pre_player_mined_item', player, event)
end

-- 机器人预挖：仅当实体在副本 surface 上时分发
local function on_robot_pre_mined(event)
    local entity = event.entity
    if not entity or not entity.valid then return end

    local surface_name = entity.surface.name
    if not string.find(surface_name, "^dungeon_%d+$") then return end

    local player_index = tonumber(string.match(surface_name, "^dungeon_(%d+)$"))
    if not player_index then return end

    local this = WPT.get()
    if not this.dungeons or not this.dungeons[player_index] then return end
    local data = this.dungeons[player_index]
    if not data.active then return end

    local player = game.players[player_index]
    if not (player and player.valid) then return end

    dispatch_to_module(player_index, 'on_robot_pre_mined', player, event)
end

--==============================================================================
-- 扩展事件 handler（第一批：玩法常用）
--==============================================================================

-- 框架强制行为：禁止副本内使用蓝图
-- 拦截 on_player_setup_blueprint，若玩家在副本 surface 上则清空光标蓝图
local function on_player_setup_blueprint(event)
    local player = game.players[event.player_index]
    if not player or not player.valid then return end

    local this = WPT.get()
    if not this.dungeons or not this.dungeons[player.index] then return end
    local data = this.dungeons[player.index]
    if not data.active then return end
    if not data.surface_name then return end
    if player.surface.name ~= data.surface_name then return end

    -- 副本内禁止蓝图：清空光标中的蓝图物品
    if player.cursor_stack and player.cursor_stack.valid_for_read then
        local item_name = player.cursor_stack.name
        if item_name == 'blueprint' or item_name == 'blueprint-book' or item_name == 'upgrade-planner' or item_name == 'deconstruction-planner' then
            player.cursor_stack.set_stack(nil)
            player.print({'amap.dungeon_no_blueprint'}, {r = 1, g = 0.5, b = 0})
        end
    end
end

-- 实体死亡：仅当实体在副本 surface 上时分发
local function on_entity_died(event)
    local entity = event.entity
    if not entity or not entity.valid then return end

    local surface_name = entity.surface.name
    if not is_dungeon_surface(surface_name) then return end

    local player_index = parse_player_index_from_surface(surface_name)
    if not player_index then return end

    local this = WPT.get()
    if not this.dungeons or not this.dungeons[player_index] then return end
    local data = this.dungeons[player_index]
    if not data.active then return end

    local player = game.players[player_index]
    if not (player and player.valid) then return end

    dispatch_to_module(player_index, 'on_entity_died', player, event)
end

-- 玩家复活：仅当玩家有 active 副本时分发
local function on_player_respawned(event)
    local player = game.players[event.player_index]
    if not player or not player.valid then return end

    local this = WPT.get()
    if not this.dungeons or not this.dungeons[player.index] then return end
    local data = this.dungeons[player.index]
    if not data.active then return end

    dispatch_to_module(event.player_index, 'on_player_respawned', player, event)
end

-- 雷达扫描：仅当实体在副本 surface 上时分发
local function on_sector_scanned(event)
    if not event.surface then return end
    local surface_name = event.surface.name
    if not is_dungeon_surface(surface_name) then return end

    local player_index = parse_player_index_from_surface(surface_name)
    if not player_index then return end

    local this = WPT.get()
    if not this.dungeons or not this.dungeons[player_index] then return end
    local data = this.dungeons[player_index]
    if not data.active then return end

    local player = game.players[player_index]
    if not (player and player.valid) then return end

    dispatch_to_module(player_index, 'on_sector_scanned', player, event)
end

-- 科技研发完成：仅当副本 force 研发完成时分发
local function on_research_finished(event)
    local research = event.research
    if not research or not research.valid then return end

    local force = research.force
    if not force then return end

    -- 检查是否为副本 force（格式 dungeon_force_<name>）
    if not string.find(force.name, "^dungeon_force_") then return end

    -- 找到对应的玩家副本
    local this = WPT.get()
    if not this.dungeons then return end
    for player_index, data in pairs(this.dungeons) do
        if data.active and data.dungeon_force == force.name then
            local player = game.players[player_index]
            if player and player.valid then
                dispatch_to_module(player_index, 'on_research_finished', player, event)
            end
            return
        end
    end
end

-- 玩家手工制作：仅当玩家在副本里时分发
local function on_player_crafted_item(event)
    local player = game.players[event.player_index]
    if not player or not player.valid then return end

    local this = WPT.get()
    if not this.dungeons or not this.dungeons[player.index] then return end
    local data = this.dungeons[player.index]
    if not data.active then return end
    if not data.surface_name then return end
    if player.surface.name ~= data.surface_name then return end

    dispatch_to_module(event.player_index, 'on_player_crafted_item', player, event)
end

-- 玩家加入游戏：仅当玩家有 active 副本时分发（断线重连场景）
local function on_player_joined_game(event)
    local player = game.players[event.player_index]
    if not player or not player.valid then return end

    local this = WPT.get()
    if not this.dungeons or not this.dungeons[player.index] then return end
    local data = this.dungeons[player.index]
    if not data.active then return end

    dispatch_to_module(event.player_index, 'on_player_joined_game', player, event)
end

-- 玩家离开游戏：仅当玩家有 active 副本时分发（断线场景）
local function on_player_left_game(event)
    local player = game.players[event.player_index]
    if not player or not player.valid then return end

    local this = WPT.get()
    if not this.dungeons or not this.dungeons[player.index] then return end
    local data = this.dungeons[player.index]
    if not data.active then return end

    dispatch_to_module(event.player_index, 'on_player_left_game', player, event)
end

--==============================================================================
-- 扩展事件 handler（第二批：扩展性强）
--==============================================================================

-- 玩家移动：仅当玩家在副本里时分发
local function on_player_changed_position(event)
    local player = game.players[event.player_index]
    if not player or not player.valid then return end

    local this = WPT.get()
    if not this.dungeons or not this.dungeons[player.index] then return end
    local data = this.dungeons[player.index]
    if not data.active then return end
    if not data.surface_name then return end
    if player.surface.name ~= data.surface_name then return end

    dispatch_to_module(event.player_index, 'on_player_changed_position', player, event)
end

-- 玩家使用胶囊：仅当玩家在副本里时分发
local function on_player_used_capsule(event)
    local player = game.players[event.player_index]
    if not player or not player.valid then return end

    local this = WPT.get()
    if not this.dungeons or not this.dungeons[player.index] then return end
    local data = this.dungeons[player.index]
    if not data.active then return end
    if not data.surface_name then return end
    if player.surface.name ~= data.surface_name then return end

    dispatch_to_module(event.player_index, 'on_player_used_capsule', player, event)
end

-- 玩家弹药变化：仅当玩家在副本里时分发
local function on_player_ammo_inventory_changed(event)
    local player = game.players[event.player_index]
    if not player or not player.valid then return end

    local this = WPT.get()
    if not this.dungeons or not this.dungeons[player.index] then return end
    local data = this.dungeons[player.index]
    if not data.active then return end
    if not data.surface_name then return end
    if player.surface.name ~= data.surface_name then return end

    dispatch_to_module(event.player_index, 'on_player_ammo_inventory_changed', player, event)
end

-- 玩家旋转实体：仅当实体在副本 surface 上时分发
local function on_player_rotated_entity(event)
    local entity = event.entity
    if not entity or not entity.valid then return end

    local surface_name = entity.surface.name
    if not is_dungeon_surface(surface_name) then return end

    local player_index = parse_player_index_from_surface(surface_name)
    if not player_index then return end

    local this = WPT.get()
    if not this.dungeons or not this.dungeons[player_index] then return end
    local data = this.dungeons[player_index]
    if not data.active then return end

    local player = game.players[event.player_index]
    if not (player and player.valid) then return end

    dispatch_to_module(event.player_index, 'on_player_rotated_entity', player, event)
end

-- 玩家切换 force：若切到/切出副本 force，通知玩法模块
local function on_player_changed_force(event)
    local player = game.players[event.player_index]
    if not player or not player.valid then return end

    local this = WPT.get()
    if not this.dungeons or not this.dungeons[player.index] then return end
    local data = this.dungeons[player.index]
    if not data.active then return end

    dispatch_to_module(event.player_index, 'on_player_changed_force', player, event)
end

-- 模组设置变更：直接转发（不常见，供高级玩法使用）
local function on_runtime_mod_setting_changed(event)
    local player_index = event.player_index
    if not player_index then return end

    local player = game.players[player_index]
    if not player or not player.valid then return end

    local this = WPT.get()
    if not this.dungeons or not this.dungeons[player_index] then return end
    local data = this.dungeons[player_index]
    if not data.active then return end

    dispatch_to_module(player_index, 'on_runtime_mod_setting_changed', player, event)
end

--==============================================================================
-- 扩展事件 handler（第三批：特殊玩法用）
--==============================================================================

-- 玩家铺砖：仅当玩家在副本里时分发
local function on_player_built_tile(event)
    local player = game.players[event.player_index]
    if not player or not player.valid then return end

    local this = WPT.get()
    if not this.dungeons or not this.dungeons[player.index] then return end
    local data = this.dungeons[player.index]
    if not data.active then return end
    if not data.surface_name then return end
    if player.surface.name ~= data.surface_name then return end

    dispatch_to_module(event.player_index, 'on_player_built_tile', player, event)
end

-- 玩家挖砖：仅当玩家在副本里时分发
local function on_player_mined_tile(event)
    local player = game.players[event.player_index]
    if not player or not player.valid then return end

    local this = WPT.get()
    if not this.dungeons or not this.dungeons[player.index] then return end
    local data = this.dungeons[player.index]
    if not data.active then return end
    if not data.surface_name then return end
    if player.surface.name ~= data.surface_name then return end

    dispatch_to_module(event.player_index, 'on_player_mined_tile', player, event)
end

-- GUI 关闭：仅当玩家在副本里时分发
local function on_gui_closed(event)
    local player = game.players[event.player_index]
    if not player or not player.valid then return end

    local this = WPT.get()
    if not this.dungeons or not this.dungeons[player.index] then return end
    local data = this.dungeons[player.index]
    if not data.active then return end
    if not data.surface_name then return end
    if player.surface.name ~= data.surface_name then return end

    dispatch_to_module(event.player_index, 'on_gui_closed', player, event)
end

-- 玩家点击史诗木箱：弹出副本选择面板（随机副本，预抽随机奖励）
-- 由 on_gui_opened 拦截后调用（gui_type == entity 且 entity 为已注册的史诗木箱）
local function on_entity_clicked(event)
    local entity = event.entity
    if not entity or not entity.valid then return end

    local player = game.players[event.player_index]
    if not player or not player.valid then return end

    -- 仅处理史诗木箱（双重保险，on_gui_opened 已预判过）
    if not Public.is_epic_chest(entity) then return end

    -- 玩家与史诗箱子不在同一图层 → 不弹面板
    if player.surface.index ~= entity.surface.index then return end

    -- 玩家已在副本中或副本面板已开 → 不重复弹
    local this = WPT.get()
    if this.dungeons and this.dungeons[player.index] and this.dungeons[player.index].active then
        player.print({'amap.dungeon_already_active'}, {r = 1, g = 0.5, b = 0})
        return
    end
    if player.gui.screen[GUI_DIFFICULTY_FRAME] then
        return
    end

    -- 副本注册表非空校验（每张卡片单独随机副本，不再预选）
    local order = instance_order
    if not order or #order == 0 then
        player.print({'amap.instance_no_module'}, {r = 1, g = 0.5, b = 0})
        return
    end

    -- 记录玩家从哪个木箱点开，Public.enter 成功后删除该木箱
    -- 同时保存 entity 引用：玩家手动放的史诗木箱不在 epic_chests 注册数组中，
    -- 不能靠 find_epic_chest_by_unit_number 查找；直接用保存的引用 destroy 更可靠
    local player_data = Public.get_data(player.index)
    player_data.epic_chest_unit_number = entity.unit_number
    player_data.epic_chest_entity = entity

    -- 弹出副本选择面板：3 张卡片，每张单独随机副本 + 难度 + 奖励
    -- 用 unit_number 作为 cache_key，同个木箱重复点开时复用上次选项（防止玩家关掉 GUI 刷选项）
    Public.show_difficulty_selection_gui(player, nil, entity.unit_number)
    player.print({'amap.epic_chest_opened'}, {r = 0.84, g = 0.6, b = 0.2})
end

-- GUI 打开：
--   1. 若打开的是史诗木箱 → 拦截，关闭官方箱子 GUI，转入副本难度选择流程
--   2. 否则按"玩家在副本里"分发给玩法模块
local function on_gui_opened(event)
    local player = game.players[event.player_index]
    if not player or not player.valid then return end

    -- 史诗木箱拦截（gui_type == entity 时才可能）
    if event.gui_type == defines.gui_type.entity then
        local entity = event.entity
        if entity and entity.valid and Public.is_epic_chest(entity) then
            -- 先创建难度面板，再关闭官方箱子 GUI
            -- （若先 player.opened = nil 会同步触发 on_gui_closed，可能干扰后续 GUI 创建）
            on_entity_clicked(event)
            player.opened = nil
            return
        end
    end

    local this = WPT.get()
    if not this.dungeons or not this.dungeons[player.index] then return end
    local data = this.dungeons[player.index]
    if not data.active then return end
    if not data.surface_name then return end
    if player.surface.name ~= data.surface_name then return end

    dispatch_to_module(event.player_index, 'on_gui_opened', player, event)
end

--==============================================================================
-- 注册事件
--==============================================================================

Event.on_nth_tick(600, on_nth_tick_timeout)
Event.on_nth_tick(60, on_nth_tick)
Event.on_nth_tick(5, on_nth_tick_fast)

-- 原有事件
Event.add(defines.events.on_gui_click, on_gui_click)
Event.add(defines.events.on_player_died, on_player_died)
Event.add(defines.events.on_built_entity, on_built_entity)
Event.add(defines.events.on_robot_built_entity, on_robot_built_entity)
Event.add(defines.events.on_player_mined_entity, on_player_mined_entity)
Event.add(defines.events.on_pre_player_mined_item, on_pre_player_mined_item)
Event.add(defines.events.on_robot_pre_mined, on_robot_pre_mined)

-- 框架强制行为
Event.add(defines.events.on_player_setup_blueprint, on_player_setup_blueprint)

-- 第一批扩展事件
Event.add(defines.events.on_entity_died, on_entity_died)
Event.add(defines.events.on_player_respawned, on_player_respawned)
Event.add(defines.events.on_sector_scanned, on_sector_scanned)
Event.add(defines.events.on_research_finished, on_research_finished)
Event.add(defines.events.on_player_crafted_item, on_player_crafted_item)
Event.add(defines.events.on_player_joined_game, on_player_joined_game)
Event.add(defines.events.on_player_left_game, on_player_left_game)

-- 第二批扩展事件
Event.add(defines.events.on_player_changed_position, on_player_changed_position)
Event.add(defines.events.on_player_used_capsule, on_player_used_capsule)
Event.add(defines.events.on_player_ammo_inventory_changed, on_player_ammo_inventory_changed)
Event.add(defines.events.on_player_rotated_entity, on_player_rotated_entity)
Event.add(defines.events.on_player_changed_force, on_player_changed_force)
Event.add(defines.events.on_runtime_mod_setting_changed, on_runtime_mod_setting_changed)

-- 第三批扩展事件
Event.add(defines.events.on_player_built_tile, on_player_built_tile)
Event.add(defines.events.on_player_mined_tile, on_player_mined_tile)
Event.add(defines.events.on_gui_closed, on_gui_closed)
Event.add(defines.events.on_gui_opened, on_gui_opened)

return Public
