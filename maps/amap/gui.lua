-- 模块依赖声明
local Event = require 'utils.event'
local WPT = require 'maps.amap.table'
local TPT = require 'maps.amap.tianfu_table'
local Gui = require 'utils.gui'
local diff = require 'maps.amap.diff'
local World = require 'maps.amap.world.framework'
local format_number = require 'util'.format_number
local WD = require 'modules.wave_defense.table'
local tianfu = require 'maps.amap.tianfu'
local rpgtable = require 'modules.rpg.table'
local TianfuQuality = require 'maps.amap.tianfu_quality'  -- 天赋品质系统 helper（方案 D）
local World = require 'maps.amap.world.framework'  -- 世界框架（world_bonus_type 声明式查表）

-- 模块公开接口
local Public = {}

--[[
    常量定义区
    使用表结构组织常量，避免魔法字符串，提高代码可维护性
]]
local CONST = {
    -- GUI元素标识
    MAIN_BUTTON = Gui.uid_name(),
    MAIN_FRAME = Gui.uid_name(),
    SPELL_FRAME = 'tianfu_gui_frame',
    TALENT_FRAME_CONTAINER = 'tianfu_frame_table',
    BTN_TIANFU = 'tianfu',
    -- 标签页相关
    TABBED_PANE = 'tianfu_tabbed_pane',
    TAB_OCCUPATION_COOLDOWN = 'tab_occupation_cooldown',
    TAB_SKILL_UPGRADE = 'tab_skill_upgrade',
    TAB_OTHER_PLAYERS = 'tab_other_players',
    TAB_WORLD_BONUS = 'tab_world_bonus',
    TAB_TALENT_CATEGORIES = 'tab_talent_categories',
    CONTENT_OCCUPATION_COOLDOWN = 'content_occupation_cooldown',
    CONTENT_SKILL_UPGRADE = 'content_skill_upgrade',
    CONTENT_OTHER_PLAYERS = 'content_other_players',
    CONTENT_WORLD_BONUS = 'content_world_bonus',
    CONTENT_TALENT_CATEGORIES = 'content_talent_categories',
    
    -- 天赋开关相关
    TALENT_TOGGLE_BUTTON_PREFIX = 'tianfu_toggle_',
    TALENT_STATUS_LABEL_PREFIX = 'tianfu_status_',
    TALENT_ENABLE_ALL_BUTTON = 'tianfu_enable_all',
    TALENT_DISABLE_ALL_BUTTON = 'tianfu_disable_all',
    
    -- 天赋黑名单（不能被禁用的天赋）
    TALENT_BLACKLIST = {'hd', 'yanshu'},
    
    -- 天赋删除按钮前缀
    TALENT_DELETE_BUTTON_PREFIX = 'tianfu_delete_',
    
    -- 职业选项数据
    OCCUPATIONS = {
        {key = '随机', name = {'tianfu.random'}, tooltip = ''},
        {key = '战士', name = {'tianfu.zhiye_zhanshi'}, tooltip = {'tianfu.zhiye_zhanshi_tip'}},
        {key = '法师', name = {'tianfu.zhiye_fashi'}, tooltip = {'tianfu.zhiye_fashi_tip'}},
        {key = '建造者', name = {'tianfu.zhiye_builder'}, tooltip = {'tianfu.zhiye_builder_tip'}}
    },
    
    -- 颜色定义
    COLORS = {
        GREEN = {0, 255, 0},
        GREY = {175, 175, 175},
        CYAN = {0, 175, 175},
        YELLOW = {255, 255, 0},
        WHITE = {0.88, 0.88, 0.88},
        RED = {255, 0, 0},
        ORANGE = {255, 165, 0},
        BLACK = {0, 0, 0}
    },
    
    -- 其他常量
    UPDATE_INTERVAL_COOLING = 60,  -- 冷却更新频率（tick）
    UPDATE_INTERVAL_GUI = 600      -- GUI更新频率（tick）
}

-- 导出顶栏按钮名（供 utils/top_button_order.lua 排序使用）
Public.main_button_name = CONST.MAIN_BUTTON

Gui.allow_player_to_toggle_top_element_visibility(CONST.MAIN_BUTTON)
Gui.allow_player_to_toggle_top_element_visibility(CONST.BTN_TIANFU)
Gui.allow_player_to_toggle_top_element_visibility(CONST.MAIN_FRAME)
-- 天赋按钮游戏中高频使用，折叠时始终可见
Gui.register_always_visible_top_element(CONST.BTN_TIANFU)

--[[
    辅助函数区
    工具函数，用于简化主逻辑代码
]]

-- 验证玩家是否有效
local function validate_player(player)
    return player and 
           player.valid and 
           player.character and 
           player.connected and 
           game.players[player.name]
end

-- 获取技能冷却信息
local function get_skill_cooling_info(player, skill)
    if not (validate_player(player) and skill) then
        return 0, 0
    end
    
    local tianfu_table = TPT.get()
    local nap = tianfu_table.tianfu_cooldown[skill] or 0
    
    if nap <= 0 then
        return 0, 0
    end
    
    -- 使用优化的冷却时间表
    local player_index = player.index
    if not tianfu_table.skill_cooldowns[player_index] then
        tianfu_table.skill_cooldowns[player_index] = {}
    end
    local last_used = tianfu_table.skill_cooldowns[player_index][skill] or 0
    
    if last_used <= 0 then
        return nap, 0
    end
    
    local current_tick = game.tick
    local elapsed_time = current_tick - last_used
    local left_time = math.max(0, nap - elapsed_time)
    
    return nap, left_time
end

-- 检查天赋是否在黑名单中
local function is_talent_blacklisted(talent_id)
    for _, blacklisted_talent in ipairs(CONST.TALENT_BLACKLIST) do
        if talent_id == blacklisted_talent then
            return true
        end
    end
    return false
end

-- 获取天赋名称列表（带缓存）
local function tianfu_names(player)
    local this = WPT.get()
    local cache_key = player.name
    
    -- 检查缓存是否存在且有效
    if this.tianfu_names_cache and 
       this.tianfu_names_cache[cache_key] and 
       this.tianfu_names_cache[cache_key].version == this.version then
        return this.tianfu_names_cache[cache_key].data
    end
    
    -- 生成新的缓存
    local names = {}
    if this.skill and this.skill[player.name] then
        for skill_name, _ in pairs(this.skill[player.name]) do
            table.insert(names, {'tianfu.' .. skill_name})
        end
    end
    
    -- 初始化缓存结构
    if not this.tianfu_names_cache then
        this.tianfu_names_cache = {}
    end
    this.tianfu_names_cache[cache_key] = {
        data = names,
        version = this.version
    }
    
    return names
end

-- 获取天赋ID列表（带缓存）
local function tianfu_keys(player)
    local this = WPT.get()
    local cache_key = player.name
    
    -- 检查缓存是否存在且有效
    if this.tianfu_keys_cache and 
       this.tianfu_keys_cache[cache_key] and 
       this.tianfu_keys_cache[cache_key].version == this.version then
        return this.tianfu_keys_cache[cache_key].data
    end
    
    -- 生成新的缓存
    local keys = {}
    if this.skill and this.skill[player.name] then
        for skill_name, _ in pairs(this.skill[player.name]) do
            table.insert(keys, skill_name)
        end
    end
    
    -- 初始化缓存结构
    if not this.tianfu_keys_cache then
        this.tianfu_keys_cache = {}
    end
    this.tianfu_keys_cache[cache_key] = {
        data = keys,
        version = this.version
    }
    
    return keys
end

-- 清除天赋缓存
local function clear_tianfu_cache(player)
    local this = WPT.get()
    local cache_key = player.name
    
    if this.tianfu_names_cache then
        this.tianfu_names_cache[cache_key] = nil
    end
    if this.tianfu_keys_cache then
        this.tianfu_keys_cache[cache_key] = nil
    end
end

-- 获取在线玩家列表
local function get_online_players()
    local online_players = {}
    for _, player in pairs(game.players) do
        if validate_player(player) then
            table.insert(online_players, player)
        end
    end
    return online_players
end

--[[
    GUI创建函数区
    负责创建和更新界面元素
]]

-- 创建顶部按钮
local function create_button(player)
    local button = Gui.add_top_element(player, {
        type = 'sprite-button',
        name = CONST.MAIN_BUTTON,
        sprite = 'utility/map',
        tooltip = {'amap.show_map_info'}
    })

    local talent_button = Gui.add_top_element(player, {
        type = 'sprite-button',
        name = CONST.BTN_TIANFU,
        caption = {'amap.talent'}
    })
    -- 默认字体色 #8F8F8F，可学天赋时变绿（update_tianfu_button）
    talent_button.style.font_color = {143, 143, 143}
    -- 文字按钮宽度自适应内容；左右留 4px 空隙（默认继承 button 的 8px，收窄到 4px）
    talent_button.style.left_padding = 4
    talent_button.style.right_padding = 4
end

-- 创建统计项（带分隔线）
local function add_stat_item(frame, name)
    local label = frame.add({
        type = 'label', 
        caption = ' ', 
        name = name
    })
    label.style.font_color = CONST.COLORS.WHITE
    label.style.font = 'default-bold'
    label.style.right_padding = 4
    
    local line = frame.add({
        type = 'line', 
        direction = 'vertical'
    })
    line.style.left_padding = 4
    line.style.right_padding = 4
end

-- 创建主信息面板
local function create_main_frame(player)
    local frame = Gui.add_top_element(player, {
        type = 'frame', 
        name = CONST.MAIN_FRAME
    })
    frame.location = {x = 1, y = 40}
    -- 高度 40，与顶栏按钮（mod_gui_button 40 高）对齐
    frame.style.minimal_height = 40
    frame.style.maximal_height = 40

    local label = frame.add({
        type = 'label', 
        caption = ' ', 
        name = 'label'
    })
    label.style.font_color = CONST.COLORS.WHITE
    label.style.font = 'default-bold'

    -- 添加统计项
    add_stat_item(frame, 'best_record')
    add_stat_item(frame, 'biter_target')
    add_stat_item(frame, 'landmine')
    
    -- 最后一项（无分隔线）
    local flame = frame.add({
        type = 'label', 
        caption = ' ', 
        name = 'flame_turret'
    })
    flame.style.font_color = CONST.COLORS.WHITE
    flame.style.font = 'default-bold'
    flame.style.right_padding = 4
end

-- 更新天赋按钮状态
local function update_tianfu_button(player)
    if not Gui.get_button_flow(player)[CONST.BTN_TIANFU] then
        create_button(player)
    end
    
    local this = WPT.get()
    local button = Gui.get_button_flow(player)[CONST.BTN_TIANFU]
    local can_choose = this.skill_canchoise and (this.skill_canchoise[player.name] or 0) > 0
    
    if can_choose then
        button.style.font_color = CONST.COLORS.GREEN
        player.print({'amap.new_tianfu'}, {r = 255, b = 0, g = 255})
        clear_tianfu_cache(player)
    else
        -- 默认字体色 #8F8F8F
        button.style.font_color = {143, 143, 143}
    end
end

--[[
    标签页绘制函数区
    每个函数负责绘制一个特定的标签页内容
]]

-- 绘制天赋列表标签页
local function draw_talent_tab(player, frame)
    local this = WPT.get()
    
    if not this.skill[player.name] then
        frame.add({
            type = "label", 
            caption = {'amap.no_talent_selected'}
        })
        return
    end
    
    -- 一键开启/关闭全部天赋按钮组
    local btn_flow = frame.add({
        type = "flow",
        direction = "horizontal"
    })
    btn_flow.style.horizontal_spacing = 8
    btn_flow.style.maximal_width = 510

    local btn_enable_all = btn_flow.add({
        type = "button",
        name = CONST.TALENT_ENABLE_ALL_BUTTON,
        caption = {'amap.talent_enable_all'},
        tooltip = {'amap.talent_enable_all_tip'}
    })
    btn_enable_all.style.minimal_width = 110
    btn_enable_all.style.font_color = CONST.COLORS.BLACK

    local btn_disable_all = btn_flow.add({
        type = "button",
        name = CONST.TALENT_DISABLE_ALL_BUTTON,
        caption = {'amap.talent_disable_all'},
        tooltip = {'amap.talent_disable_all_tip'}
    })
    btn_disable_all.style.minimal_width = 110
    btn_disable_all.style.font_color = CONST.COLORS.BLACK
    
    local scroll = frame.add({
        type = "scroll-pane", 
        vertical_scroll_policy = 'auto',
        horizontal_scroll_policy = 'never'
    })
    scroll.style.height = 260
    scroll.style.maximal_width = 510

    for talent_id, talent_quality in pairs(this.skill[player.name]) do

        local flow = scroll.add({
            type = "flow", 
            direction = 'horizontal'
        })
        flow.style.maximal_width = 510
        
        -- 天赋名称（天赋品质系统：按品质染色）
        local lbl_name = flow.add({
            type = "label",
            caption = {'tianfu.' .. talent_id},
            tooltip = {'tianfu.' .. talent_id .. '_tip', table.unpack(TianfuQuality.tip_args(talent_id, talent_quality))}
        })
        lbl_name.style.horizontal_align = 'left'
        lbl_name.style.minimal_width = 120
        lbl_name.style.maximal_width = 120
        local q_color = TianfuQuality.color(talent_quality) or {r = 200, g = 200, b = 200}
        lbl_name.style.font_color = { r = q_color.r / 255, g = q_color.g / 255, b = q_color.b / 255 }

        -- 天赋品质（文字显示，与品质系统一致；避免描述里 __1__ 占位符显示原文）
        local q_label = flow.add({
            type = "label",
            caption = TianfuQuality.locale_name(talent_quality)
        })
        q_label.style.minimal_width = 56
        q_label.style.maximal_width = 56
        q_label.style.font_color = { r = q_color.r / 255, g = q_color.g / 255, b = q_color.b / 255 }

        -- 天赋状态
        local is_blacklisted = is_talent_blacklisted(talent_id)
        local is_enabled = not (this.tianfu_enabled[player.index] and 
                              this.tianfu_enabled[player.index][talent_id] == false)
        
        local status_text = is_blacklisted and {'amap.talent_important'} or 
                           (is_enabled and {'amap.talent_enabled'} or {'amap.talent_disabled'})
        local status_tooltip = is_blacklisted and {'amap.talent_blacklisted_tip'} or 
                              (is_enabled and {'amap.talent_enabled_tip'} or {'amap.talent_disabled_tip'})
        
        local status_label = flow.add({
            type = "label",
            caption = status_text,
            name = CONST.TALENT_STATUS_LABEL_PREFIX .. talent_id,
            tooltip = status_tooltip
        })
        status_label.style.minimal_width = 75
        status_label.style.maximal_width = 75
        status_label.style.font_color = is_blacklisted and CONST.COLORS.ORANGE or CONST.COLORS.WHITE
        status_label.style.font = 'default-bold'

        -- 开关按钮
        local toggle_button = flow.add({
            type = "button",
            name = CONST.TALENT_TOGGLE_BUTTON_PREFIX .. talent_id,
            caption = is_blacklisted and {'amap.talent_cannot_disable'} or 
                     (is_enabled and {'amap.talent_close'} or {'amap.talent_open'}),
            tooltip = is_blacklisted and {'amap.talent_blacklisted_tip'} or 
                     (is_enabled and {'amap.disable_talent'} or {'amap.enable_talent'})
        })
        toggle_button.style.minimal_width = 55
        toggle_button.style.maximal_width = 55
        toggle_button.style.minimal_height = 30
        toggle_button.style.font_color = CONST.COLORS.BLACK
        
        if is_blacklisted then
            toggle_button.enabled = false
            toggle_button.style.font_color = CONST.COLORS.GREY
        end

        -- 删除按钮
        local delete_button = flow.add({
            type = "button",
            name = CONST.TALENT_DELETE_BUTTON_PREFIX .. talent_id,
            caption = {'amap.delete_talent'},
            tooltip = {'amap.delete_talent_tip'}
        })
        delete_button.style.minimal_width = 55
        delete_button.style.maximal_width = 55
        delete_button.style.minimal_height = 30
        delete_button.style.font_color = CONST.COLORS.BLACK
    end
end

-- 绘制职业选择标签页内容
local function draw_occupation_tab(player, frame)
    local this = WPT.get()
    local zhiye_flow = frame.add({
        type = "flow", 
        direction = "horizontal"
    })
    zhiye_flow.add({
        type = "label", 
        caption = {'amap.select_occupation'}
    })

    if not this.zhiye[player.name] then 
        this.zhiye[player.name] = "随机" 
    end
    
    local items = {}
    local selected_index = 1
    for i, occupation in ipairs(CONST.OCCUPATIONS) do
        items[i] = occupation.name
        if occupation.key == this.zhiye[player.name] then 
            selected_index = i 
        end
    end
    
    if selected_index < 1 or selected_index > #items then
        selected_index = 1
    end
    
    local dropdown = zhiye_flow.add({
        type = "drop-down",
        name = "zhiye_select",
        items = items,
        selected_index = selected_index
    })
    dropdown.style.minimal_width = 120
end

-- 绘制技能升级标签页
local function draw_skill_tab(player, frame)
    local this = WPT.get()
    local p_index = player.index
    local item_spell = rpgtable.get_itam_spell
    
    -- 添加滚动面板
    local scroll = frame.add({
        type = "scroll-pane", 
        vertical_scroll_policy = 'auto',
        horizontal_scroll_policy = 'never'
    })
    scroll.style.height = 400
    scroll.style.maximal_width = 510
    
    local skill_flow = scroll.add({
        type = "flow", 
        direction = 'vertical'
    })
    
    if not (this.upgrade_spell[p_index] and next(this.upgrade_spell[p_index])) then
        local empty = skill_flow.add({
            type = "label", 
            caption = {'amap.skill_no_data'}
        })
        empty.style.font_color = {150, 150, 150}
        return
    end
    
    for skill_name, current_exp in pairs(this.upgrade_spell[p_index]) do
        local spell_cfg = item_spell[skill_name]
        if not spell_cfg then goto continue end
        
        local row = skill_flow.add({
            type = "flow", 
            direction = 'horizontal'
        })
        row.style.maximal_width = 510
        
        -- 技能名称
        local lbl = row.add({
            type = "label", 
            caption = {'spells.' .. skill_name}
        })
        lbl.style.horizontal_align = 'left'
        lbl.style.minimal_width = 115
        lbl.style.maximal_width = 115
        lbl.style.font_color = CONST.COLORS.YELLOW

        -- 计算等级和进度
        local level, progress_str, bonus_desc

        if spell_cfg.need_times then
            -- 连续升级模式（need_times+bonus+base）
            -- 与 spells.lua upgrade_lianxu 逻辑保持一致：times > need_times 才升级
            local need = spell_cfg.need_times
            local base = spell_cfg.base or 1
            local bonus = spell_cfg.bonus or 1
            local times = current_exp
            local bonus_time = 0
            while times > need do
                bonus_time = bonus_time + 1
                times = times - need
            end
            level = base + bonus_time * bonus
            progress_str = times .. "/" .. need
            bonus_desc = 'Lv' .. level
        elseif spell_cfg.need_list then
            -- 阶段升级模式（need_list+upgrade_list）
            local list = spell_cfg.need_list
            local need = 1
            level = 1

            for k, v in ipairs(list) do
                if current_exp > v then
                    level = k
                    need = list[k + 1] or list[k]
                end
            end
            progress_str = current_exp .. "/" .. need
            bonus_desc = 'Lv' .. level
        else
            -- 未知配置，跳过
            goto continue
        end

        local lbl_prog = row.add({
            type = "label", 
            caption = '(' .. progress_str .. ')'
        })
        lbl_prog.style.minimal_width = 70
        lbl_prog.style.maximal_width = 70
        
        local lbl_bonus = row.add({
            type = "label", 
            caption = bonus_desc
        })
        lbl_bonus.style.minimal_width = 50
        lbl_bonus.style.maximal_width = 50
        
        ::continue::
    end
end

-- 绘制冷却配置标签页
local function draw_cooldown_tab(player, frame)
    local this = WPT.get()
    
    if not this.skill[player.name] then
        frame.add({
            type = "label", 
            caption = {'amap.no_talent_selected'}
        })
        return
    end
    
    -- 初始化数据
    this.tianfu_lengque[player.name] = this.tianfu_lengque[player.name] or {
        dropdown_select_index1 = 1,
        dropdown_select_index2 = 1,
        dropdown_select_index3 = 1
    }
    
    local settings = this.tianfu_lengque[player.name]
    local names = tianfu_names(player)
    
    if #names == 0 then
        frame.add({
            type = "label", 
            caption = {'amap.no_talent_selected'}
        })
        return
    end
    
    -- 越界修正
    for i = 1, 3 do
        local key = 'dropdown_select_index' .. i
        if settings[key] < 1 or settings[key] > #names then 
            settings[key] = 1 
        end
    end

    local table = frame.add({
        type = 'table', 
        column_count = 4, 
        name = 'tianfu_lengque_table'
    })
    
    for i = 1, 3 do
        local dropdown = table.add({
            type = 'drop-down', 
            name = 'choise' .. i, 
            items = names, 
            selected_index = settings['dropdown_select_index' .. i]
        })
        dropdown.style.maximal_width = 120
    end
    
    table.add({
        type = 'sprite-button', 
        name = 'tianfu_frame_button', 
        sprite = 'item/heat-interface', 
        tooltip = {'amap.cooldown_window_toggle'}
    })
end

-- 绘制其他玩家天赋列表
local function draw_other_players_tab(player, frame)
    local online_players = get_online_players()
    
    -- 创建滚动面板
    local scroll = frame.add({
        type = "scroll-pane", 
        vertical_scroll_policy = 'auto',
        horizontal_scroll_policy = 'auto'
    })
    scroll.style.height = 435
    scroll.style.maximal_width = 510
    
    -- 创建垂直流布局
    local players_flow = scroll.add({
        type = "flow", 
        direction = "vertical"
    })
    players_flow.style.vertical_spacing = 12
    
    for _, online_player in ipairs(online_players) do
        -- 创建玩家条目框架
        local player_frame = players_flow.add({
            type = "frame",
            direction = "vertical"
        })
        player_frame.style.maximal_width = 510
        player_frame.style.padding = 8
        
        -- 玩家信息行：名字 + 天赋数量
        local info_flow = player_frame.add({
            type = "flow",
            direction = "horizontal"
        })
        info_flow.style.horizontal_spacing = 8
        
        -- 玩家名字
        local player_label = info_flow.add({
            type = "label", 
            caption = online_player.name
        })
        player_label.style.font_color = CONST.COLORS.YELLOW
        player_label.style.font = "default-bold"
        
        -- 天赋数量
        local talents = tianfu_names(online_player)
        local count_label = info_flow.add({
            type = "label", 
            caption = {'amap.talent_count', #talents}
        })
        count_label.style.font_color = CONST.COLORS.GREY
        
        -- 天赋列表（Table 网格布局，4列等宽）
        if #talents == 0 then
            local empty_label = player_frame.add({
                type = "label", 
                caption = {'amap.no_talent_selected'}
            })
            empty_label.style.font_color = CONST.COLORS.GREY
        else
            local column_count = 5
            local talents_table = player_frame.add({
                type = "table",
                column_count = column_count
            })
            talents_table.style.horizontal_spacing = 12
            talents_table.style.vertical_spacing = 4
            talents_table.style.maximal_width = 510

            for i = 1, #talents do
                local talent = talents[i]
                local skill_id = talent[1]:sub(8)
                local q = TianfuQuality.idx(online_player, skill_id)
                local talent_label = talents_table.add({
                    type = "label", 
                    caption = talent, 
                    tooltip = {'tianfu.' .. skill_id .. '_tip', table.unpack(TianfuQuality.tip_args(skill_id, q))}
                })
                local q_color = TianfuQuality.color(q)
                if q_color then
                    talent_label.style.font_color = { r = q_color.r / 255, g = q_color.g / 255, b = q_color.b / 255 }
                else
                    talent_label.style.font_color = CONST.COLORS.CYAN
                end
            end

            local remainder = #talents % column_count
            if remainder ~= 0 then
                for _ = 1, column_count - remainder do
                    talents_table.add({ type = "label", caption = "" })
                end
            end
        end
    end
end

-- 绘制世界加成标签页
local function draw_world_bonus_tab(player, frame)
    local this = WPT.get()
    local map_data = diff.get()
    
    if not map_data.world_bonus then
        frame.add({
            type = "label",
            caption = {'amap.world_bonus_not_initialized'}
        })
        return
    end
        -- 添加系统信息
    frame.add({
        type = "label",
        caption = {'amap.world_bonus_info'},
        style = "caption_label"
    })
    frame.add({
        type = "label",
        caption = {'amap.world_bonus_info_desc'}
    })
    
    local info_table = frame.add({
        type = "table",
        column_count = 2
    })
    info_table.style.horizontal_spacing = 20
    info_table.style.vertical_spacing = 8
    
    info_table.add({
        type = "label",
        caption = {'amap.world_bonus_start_wave', map_data.world_bonus.start_wave or 1500}
    })
    info_table.add({
        type = "label",
        caption = {'amap.world_bonus_coefficient_interval', map_data.world_bonus.coefficient_interval or 500}
    })
    
    frame.add({type = "line"})
    -- 终极挑战：每个世界各用飞船抵达一次星系边缘（奖励开局天赋+1）
    local reward_status_frame = frame.add({
        type = "frame",
        direction = "vertical",
        style = "deep_frame_in_shallow_frame"
    })
    reward_status_frame.style.maximal_width = 510
    reward_status_frame.style.padding = 8

    local reward_title = reward_status_frame.add({
        type = "label",
        caption = {'amap.all_worlds_3000_challenge'},
        style = "caption_label"
    })
    reward_title.style.font_color = CONST.COLORS.YELLOW

    -- 统计已抵达星系边缘的世界数量
    local edge_worlds = {1, 2, 3, 6, 7, 8, 9, 10, 11, 12, 13, 14}
    local edge_count = 0
    for _, world_id in ipairs(edge_worlds) do
        if map_data.edge_reached[world_id] then
            edge_count = edge_count + 1
        end
    end

    local progress_label = reward_status_frame.add({
        type = "label",
        caption = {'amap.all_worlds_3000_progress', edge_count, #edge_worlds}
    })

    if map_data.all_worlds_3000_rewarded then
        local reward_status = reward_status_frame.add({
            type = "label",
            caption = {'amap.all_worlds_3000_rewarded'},
            style = "label"
        })
        reward_status.style.font_color = CONST.COLORS.GREEN
        reward_status.style.font = "default-bold"
    else
        local reward_status = reward_status_frame.add({
            type = "label",
            caption = {'amap.all_worlds_3000_not_rewarded'},
            style = "label"
        })
        reward_status.style.font_color = CONST.COLORS.GREY
    end
    
    -- 添加世界加成列表
    frame.add({
        type = "label",
        caption = {'amap.world_bonus_list'},
        style = "caption_label"
    })
    
    local scroll = frame.add({
        type = "scroll-pane",
        vertical_scroll_policy = 'auto',
        horizontal_scroll_policy = 'auto'
    })
    scroll.style.height = 250
    scroll.style.maximal_width = 510
    
    local worlds_table = scroll.add({
        type = "table",
        column_count = 1
    })
    worlds_table.style.horizontal_spacing = 10
    worlds_table.style.vertical_spacing = 10
    
    -- 合并奖励类型表：旧表 map.world_bonus_types + 框架各世界 def.world_bonus_type，
    -- 框架优先（与 diff.apply_world_bonuses 的取值顺序一致）。
    -- 否则 world_bonus_type 只在框架 def 里声明的世界（如16平凡之日、17网格战争）
    -- 不会出现在旧表里，奖励面板永远不显示它们。
    local bonus_types_merged = {}
    for world_id, bt in pairs(map_data.world_bonus_types) do
        bonus_types_merged[world_id] = bt
    end
    for _, world_id in ipairs(World.get_registered_worlds()) do
        local bt = World.get_field(world_id, 'world_bonus_type')
        if bt then
            bonus_types_merged[world_id] = bt
        end
    end
    -- 剔除不可选世界（如 world 8 异次元空间 selectable=false，但 def 仍注册，
    -- 会混入面板）。pcall 包裹以防非注册世界报错。
    for wid, _ in pairs(bonus_types_merged) do
        local ok, sel = pcall(World.get_field, wid, 'selectable')
        if ok and sel == false then
            bonus_types_merged[wid] = nil
        end
    end

    local world_names = {}
    for world_id, _ in pairs(bonus_types_merged) do
        world_names[world_id] = {'amap.world_name_' .. world_id}
    end
    
    for world_id, world_name in pairs(world_names) do
        local world_data = map_data.world_bonus[world_id]
        local bonus_type = bonus_types_merged[world_id]
        
        if world_data and bonus_type then
            local world_frame = worlds_table.add({
                type = "frame",
                direction = "horizontal"
            })
            world_frame.style.maximal_width = 510
            
            -- 世界名称
            world_frame.add({
                type = "label",
                caption = world_name,
                style = "caption_label"
            })
            world_frame.children[1].style.minimal_width = 70
            world_frame.children[1].style.maximal_width = 70
            
            -- 加成类型（World 框架优先，旧表 fallback；间隔波数支持按世界覆写）
            local bonus_name_key = 'amap.world_bonus_type_' .. world_id .. '_name'
            local bonus_type_data = bonus_types_merged[world_id]
            local tooltip_text
            
            if bonus_type_data then
                local base_value = bonus_type_data.base_value or 0
                local growth_value
                if bonus_type_data.growth_value then
                    -- 线性增长模式：每档增量由世界直接声明（无 max_value 即不设上限）
                    growth_value = string.format('%.2f', bonus_type_data.growth_value)
                else
                    local max_value = bonus_type_data.max_value or 0
                    growth_value = string.format('%.2f', (max_value - base_value) / (map_data.world_bonus.max_coefficient - map_data.world_bonus.base_coefficient))
                end
                local bonus_interval = World.get_field(world_id, 'world_bonus_interval') or map_data.world_bonus.coefficient_interval or 500
                tooltip_text = {'amap.world_bonus_tooltip', base_value, growth_value, bonus_interval}
            end
            
            world_frame.add({
                type = "label",
                caption = {bonus_name_key},
                tooltip = tooltip_text
            })
            world_frame.children[2].style.minimal_width = 130
            world_frame.children[2].style.maximal_width = 130
            world_frame.children[2].style.font_color = CONST.COLORS.YELLOW
            
            -- 当前加成状态
            local status_text
            local status_color
            if world_data.unlocked then
                local bonus_desc_key = 'amap.world_bonus_type_' .. world_id .. '_desc'
                -- 数值与实际施加逻辑同源（插值模式 / 线性增长模式由 diff 统一判定）
                local bonus_value = diff.get_world_bonus_value(world_id, world_data) or 0
                status_text = {bonus_desc_key, bonus_value }
                status_color = CONST.COLORS.GREEN
            else
                status_text = {'amap.world_locked'}
                status_color = CONST.COLORS.GREY
            end
            
            world_frame.add({
                type = "label",
                caption = status_text
            })
            world_frame.children[3].style.minimal_width = 70
            world_frame.children[3].style.maximal_width = 70
            world_frame.children[3].style.font_color = status_color
            
            -- 最大存活波数
            world_frame.add({
                type = "label",
                caption = ({'amap.max_wave', world_data.max_wave })
            })
            world_frame.children[4].style.minimal_width = 120
            world_frame.children[4].style.maximal_width = 120
        end
    end
    
    -- 世界13特殊奖励行（4000波送传说木箱，非渐进加成）
    do
        local w13_record = map_data.map_record[13] or 0
        local w13_frame = worlds_table.add({
            type = "frame",
            direction = "horizontal"
        })
        w13_frame.style.maximal_width = 510

        -- 世界名称
        local w13_name = w13_frame.add({
            type = "label",
            caption = {'amap.world_name_13'},
            style = "caption_label"
        })
        w13_name.style.minimal_width = 70
        w13_name.style.maximal_width = 70

        -- 加成类型
        local w13_bonus = w13_frame.add({
            type = "label",
            caption = {'amap.world_bonus_type_13_name'},
            tooltip = {'amap.world_bonus_type_13_tip'}
        })
        w13_bonus.style.minimal_width = 130
        w13_bonus.style.maximal_width = 130
        w13_bonus.style.font_color = CONST.COLORS.YELLOW

        -- 状态
        local w13_status = w13_frame.add({
            type = "label",
            caption = map_data.world_13_4000_rewarded and {'amap.world_13_4000_rewarded'} or {'amap.world_13_4000_not_rewarded'}
        })
        w13_status.style.minimal_width = 70
        w13_status.style.maximal_width = 70
        w13_status.style.font_color = map_data.world_13_4000_rewarded and CONST.COLORS.GREEN or CONST.COLORS.GREY

        -- 最大波数
        local w13_wave = w13_frame.add({
            type = "label",
            caption = {'amap.max_wave', w13_record}
        })
        w13_wave.style.minimal_width = 120
        w13_wave.style.maximal_width = 120
    end

    -- 世界14特殊奖励行（每通关2波多1金币，非渐进加成）
    do
        local w14_record = map_data.map_record[14] or 0
        local w14_bonus_coins = math.floor(w14_record / 2)
        local w14_frame = worlds_table.add({
            type = "frame",
            direction = "horizontal"
        })
        w14_frame.style.maximal_width = 510

        -- 世界名称
        local w14_name = w14_frame.add({
            type = "label",
            caption = {'amap.world_name_14'},
            style = "caption_label"
        })
        w14_name.style.minimal_width = 70
        w14_name.style.maximal_width = 70

        -- 加成类型
        local w14_bonus = w14_frame.add({
            type = "label",
            caption = {'amap.world_bonus_type_14_name'},
            tooltip = {'amap.world_bonus_type_14_tip'}
        })
        w14_bonus.style.minimal_width = 130
        w14_bonus.style.maximal_width = 130
        w14_bonus.style.font_color = CONST.COLORS.YELLOW

        -- 状态
        local w14_status = w14_frame.add({
            type = "label",
            caption = {'amap.world14_current_bonus', w14_bonus_coins}
        })
        w14_status.style.minimal_width = 70
        w14_status.style.maximal_width = 70
        w14_status.style.font_color = w14_bonus_coins > 0 and CONST.COLORS.GREEN or CONST.COLORS.GREY

        -- 最大波数
        local w14_wave = w14_frame.add({
            type = "label",
            caption = {'amap.max_wave', w14_record}
        })
        w14_wave.style.minimal_width = 120
        w14_wave.style.maximal_width = 120
    end
end

-- 绘制天赋分类标签页
local function draw_talent_categories_tab(player, frame)
    local this = WPT.get()
    local tianfu_categories = tianfu.get_tianfu_categories()
    
    -- 获取玩家已学习的天赋ID列表
    local player_talents = {}
    if this.skill and this.skill[player.name] then
        for talent_id, _ in pairs(this.skill[player.name]) do
            player_talents[talent_id] = true
        end
    end
    
    -- 分类显示名称映射
    local category_names = {
        mage = {'amap.talent_category_mage'},
        builder = {'amap.talent_category_builder'},
        fighter = {'amap.talent_category_fighter'},
        other = {'amap.talent_category_other'}
    }
    
    -- 创建滚动面板
    local scroll = frame.add({
        type = "scroll-pane", 
        vertical_scroll_policy = 'auto',
        horizontal_scroll_policy = 'auto'
    })
    scroll.style.height = 435
    scroll.style.maximal_width = 510
    
    -- 遍历每个分类
    for category_key, category_talents in pairs(tianfu_categories) do
        -- 创建分类框架
        local category_frame = scroll.add({
            type = "frame",
            direction = "vertical"
        })
        category_frame.style.maximal_width = 510
        category_frame.style.padding = 12

        -- 分类标题行：分类名称 + 天赋数量
        local header_flow = category_frame.add({
            type = "flow",
            direction = "horizontal"
        })
        header_flow.style.horizontal_spacing = 8
        
        -- 分类名称
        local category_name = category_names[category_key] or category_key
        local category_label = header_flow.add({
            type = "label", 
            caption = category_name
        })
        category_label.style.font_color = CONST.COLORS.YELLOW
        category_label.style.font = "default-bold"
        
        -- 天赋数量
        local count_label = header_flow.add({
            type = "label", 
            caption = " (" .. #category_talents .. ")"
        })
        count_label.style.font_color = CONST.COLORS.GREY
        
        -- 显示该分类中的所有天赋（Table 网格布局，4列等宽）
        local column_count = 5
        local talents_table = category_frame.add({
            type = "table",
            column_count = column_count
        })
        talents_table.style.horizontal_spacing = 12
        talents_table.style.vertical_spacing = 4
        talents_table.style.maximal_width = 510

        for i = 1, #category_talents do
            local talent_id = category_talents[i]
            local is_learned = player_talents[talent_id]

            local talent_label = talents_table.add({
                type = "label", 
                caption = {'tianfu.' .. talent_id}, 
                tooltip = {'tianfu.' .. talent_id .. '_tip', table.unpack(TianfuQuality.tip_args(talent_id, is_learned and TianfuQuality.idx(player, talent_id) or 1))}
            })

            if is_learned then
                talent_label.style.font_color = CONST.COLORS.CYAN
            else
                talent_label.style.font_color = CONST.COLORS.GREY
            end
        end

        -- 末行补空格，确保 table 列对齐
        local remainder = #category_talents % column_count
        if remainder ~= 0 then
            for _ = 1, column_count - remainder do
                talents_table.add({ type = "label", caption = "" })
            end
        end
    end
end

--[[
    主要GUI构建函数
]]

-- 构建天赋主界面
local function tianfu_gui(player)
    local parent = player.gui.left
    if not parent.valid then return end
    
    -- 清理旧内容
    if parent.tianfu_frame then 
        parent.tianfu_frame.destroy() 
    end

    local main_frame = parent.add({
        type = "frame",
        name = "tianfu_frame",
        direction = "vertical"
    })
    main_frame.style.width = 550

    -- 创建标签页容器
    local tabbed_pane = main_frame.add({
        type = "tabbed-pane",
        name = CONST.TABBED_PANE
    })

    -- 标签页1：职业、冷却与天赋
    local tab1 = tabbed_pane.add({
        type = "tab", 
        caption = {'amap.occupation_and_cooldown'}, 
        name = CONST.TAB_OCCUPATION_COOLDOWN
    })
    local content1 = tabbed_pane.add({
        type = "frame", 
        name = CONST.CONTENT_OCCUPATION_COOLDOWN, 
        direction = "vertical"
    })
    content1.style.height = 450
    content1.style.minimal_width = 510
    tabbed_pane.add_tab(tab1, content1)
    
    -- 职业选择部分
    content1.add({type = "line"})
    content1.add({
        type = "label", 
        caption = {'amap.occupation'}, 
        style = "caption_label"
    })
    draw_occupation_tab(player, content1)
    
    -- 冷却配置部分
    content1.add({type = "line"})
    content1.add({
        type = "label", 
        caption = {'amap.talent_cooldown'}, 
        style = "caption_label"
    })
    draw_cooldown_tab(player, content1)
    
    -- 已选天赋部分
    content1.add({type = "line"})
    content1.add({
        type = "label", 
        caption = {'amap.talent'}, 
        style = "caption_label"
    })
    draw_talent_tab(player, content1)

    -- 标签页2：技能升级
    local tab2 = tabbed_pane.add({
        type = "tab", 
        caption = {'amap.skillupgrade'}, 
        name = CONST.TAB_SKILL_UPGRADE
    })
    local content2 = tabbed_pane.add({
        type = "frame", 
        name = CONST.CONTENT_SKILL_UPGRADE, 
        direction = "vertical"
    })
    content2.style.height = 450
    content2.style.minimal_width = 510
    tabbed_pane.add_tab(tab2, content2)
    
    -- 技能升级部分
    content2.add({
        type = "label", 
        caption = {'amap.skillupgrade'}, 
        style = "caption_label"
    })
    draw_skill_tab(player, content2)

    -- 标签页3：其他玩家的天赋
    local tab3 = tabbed_pane.add({
        type = "tab", 
        caption = {'amap.other_players_talents'}, 
        name = CONST.TAB_OTHER_PLAYERS
    })
    local content3 = tabbed_pane.add({
        type = "frame", 
        name = CONST.CONTENT_OTHER_PLAYERS, 
        direction = "vertical"
    })
    content3.style.height = 450
    content3.style.minimal_width = 510
    tabbed_pane.add_tab(tab3, content3)
    
    draw_other_players_tab(player, content3)

    -- 标签页4：世界加成
    local tab4 = tabbed_pane.add({
        type = "tab", 
        caption = {'amap.world_bonus_tab'}, 
        name = CONST.TAB_WORLD_BONUS
    })
    local content4 = tabbed_pane.add({
        type = "frame", 
        name = CONST.CONTENT_WORLD_BONUS, 
        direction = "vertical"
    })
    content4.style.height = 450
    content4.style.minimal_width = 510
    tabbed_pane.add_tab(tab4, content4)
    
    draw_world_bonus_tab(player, content4)

    -- 标签页5：天赋分类
    local tab5 = tabbed_pane.add({
        type = "tab", 
        caption = {'amap.talent_categories'}, 
        name = CONST.TAB_TALENT_CATEGORIES
    })
    local content5 = tabbed_pane.add({
        type = "frame", 
        name = CONST.CONTENT_TALENT_CATEGORIES, 
        direction = "vertical"
    })
    content5.style.height = 450
    content5.style.minimal_width = 510
    tabbed_pane.add_tab(tab5, content5)
    
    draw_talent_categories_tab(player, content5)
end

--[[
    冷却监控窗口相关函数
]]

-- 更新单个天赋的冷却显示
-- 更新单个天赋的冷却显示
local function update_single_tianfu_cooling(player, index, skill, nap, left_time)
    if not (validate_player(player) and skill) then 
        return 
    end
    
    local frame = player.gui.screen[CONST.SPELL_FRAME]
    if not (frame and frame.valid) then 
        return 
    end
    
    local table_element = frame.tianfu_table
    if not (table_element and table_element.valid) then 
        return 
    end
    
    local row_index = (index - 1) * 3 + 1
    
    -- 更新天赋名称
    local name_label = table_element.children[row_index]
    if name_label and name_label.valid then
        name_label.caption = {'tianfu.' .. skill}
        name_label.tooltip = {'tianfu.' .. skill .. '_tip', table.unpack(TianfuQuality.tip_args(skill, TianfuQuality.idx(player, skill)))}
    end
    
    -- 更新进度条
    local progress_container = table_element.children[row_index + 1]
    if progress_container and progress_container.valid then
        local bar = progress_container['progressbar' .. index]
        if bar and bar.valid then
            local ratio = 0
            if nap and nap > 0 then
                ratio = left_time / nap
                ratio = math.max(0, math.min(1, ratio))
            end
            
            bar.value = 1 - ratio  -- 反转比例，从左到右加载
            
            -- 简单工具提示
            if ratio <= 0 then
                bar.tooltip = {'amap.cooldown_ready'}
            else
                local remain_sec = math.floor(left_time / 60 + 0.5)
                local total_sec = math.floor(nap / 60 + 0.5)
                bar.tooltip = {'amap.cooldown_in_progress', remain_sec, total_sec}
            end
        end
    end
    
    -- 更新百分比
    local percentage_label = table_element.children[row_index + 2]
    if percentage_label and percentage_label.valid then
        local ratio = (nap and nap > 0) and (left_time / nap) or 0
        local percentage = math.floor((1 - ratio) * 100)
        percentage_label.caption = percentage .. '%'
    end
end

-- 更新所有天赋的冷却显示
local function update_all_tianfu_cooling(player)
    if not validate_player(player) then 
        return 
    end
    
    local this = WPT.get()
    local settings = this.tianfu_lengque and this.tianfu_lengque[player.name]
    if not settings then 
        return 
    end
    
    local keys = tianfu_keys(player)

    for i = 1, 3 do
        local selected_idx = settings['dropdown_select_index' .. i]
        if selected_idx and selected_idx >= 1 and selected_idx <= #keys then
            local skill = keys[selected_idx]
            if skill then
                local nap, left_time = get_skill_cooling_info(player, skill)
                update_single_tianfu_cooling(player, i, skill, nap, left_time)
            end
        end
    end
end

-- 更新冷却条（可指定特定技能）
local function update_tianfu_lengque_gui(player, skill)
    if not validate_player(player) then 
        return 
    end
    
    local this = WPT.get()
    local settings = this.tianfu_lengque and this.tianfu_lengque[player.name]
    if not settings then 
        return 
    end
    
    local keys = tianfu_keys(player)
    
    -- 如果指定了特定技能，只更新该技能
    if skill then
        for i = 1, 3 do
            local selected_idx = settings['dropdown_select_index' .. i]
            if selected_idx and selected_idx >= 1 and selected_idx <= #keys and keys[selected_idx] == skill then
                local nap, left_time = get_skill_cooling_info(player, skill)
                update_single_tianfu_cooling(player, i, skill, nap, left_time)
                break
            end
        end
    else
        -- 更新所有天赋
        update_all_tianfu_cooling(player)
    end
end

-- 创建冷却监控窗口
-- 创建冷却监控窗口
local function tianfu_lengque_gui(player)
    local screen = player.gui.screen
    
    -- 如果窗口已存在，则关闭
    if screen[CONST.SPELL_FRAME] then
        screen[CONST.SPELL_FRAME].destroy()
        return
    end

    local frame = screen.add({
        type = 'frame',
        name = CONST.SPELL_FRAME,
        caption = {'amap.talent_cooldown'},
        direction = 'vertical'
    })
    frame.auto_center = true
    frame.style.minimal_width = 320  -- 减小宽度
    frame.style.maximal_width = 320

    -- 创建紧凑表格
    local table_element = frame.add({
        type = 'table',
        name = 'tianfu_table',
        column_count = 3,
        style = 'bordered_table'  -- 使用带边框的样式
    })
    table_element.style.horizontal_spacing = 2  -- 减小水平间距
    table_element.style.vertical_spacing = 2    -- 减小垂直间距
    table_element.draw_horizontal_lines = false   -- 不绘制水平线（行分割线）
    table_element.draw_vertical_lines = true     -- 绘制垂直线（列分割线）
    
    -- 设置列宽
    table_element.style.column_alignments[1] = 'left'
    table_element.style.column_alignments[2] = 'center'
    table_element.style.column_alignments[3] = 'right'

    local this = WPT.get()
    local settings = this.tianfu_lengque[player.name] or {}
    local keys = tianfu_keys(player)
    
    -- 为每个天赋创建一行
    for i = 1, 3 do
        local talent_idx = settings['dropdown_select_index' .. i] or 1
        if talent_idx < 1 or talent_idx > #keys then
            talent_idx = 1
        end
        local talent_key = keys[talent_idx] or ""
        local talent_name = talent_key ~= "" and {'tianfu.' .. talent_key} or {'amap.cooldown_not_selected'}
        
        -- 天赋名称列（白色字体，带工具提示，字体缩小）
        local name_label = table_element.add({
            type = 'label',
            name = 'tianfu_name_' .. i,
            caption = talent_name,
            tooltip = talent_key ~= "" and {'tianfu.' .. talent_key .. '_tip', table.unpack(TianfuQuality.tip_args(talent_key, 1))} or {'amap.cooldown_not_selected_tip'}
        })
        name_label.style.minimal_width = 80
        name_label.style.maximal_width = 80
        name_label.style.horizontal_align = 'left'
        name_label.style.font_color = CONST.COLORS.WHITE  -- 白色字体
        name_label.style.font = 'default-semibold'  -- 使用半粗体，看起来更清晰
        name_label.style.top_padding = 0
        name_label.style.bottom_padding = 0

        -- 进度条列
        local progress_container = table_element.add({
            type = 'flow',
            direction = 'horizontal'
        })
        progress_container.style.horizontally_stretchable = true
        progress_container.style.vertical_align = 'center'
        progress_container.style.top_padding = 0
        progress_container.style.bottom_padding = 0
        progress_container.style.height = 20
        
        local bar = progress_container.add({
            type = 'progressbar',
            name = 'progressbar' .. i,
            value = 0,
        })
        bar.style.minimal_width = 100
        bar.style.maximal_width = 100
        bar.style.height = 12  -- 减小高度
        bar.style.top_margin = 0
        bar.style.bottom_margin = 0
        bar.style.left_margin = 0
        bar.style.right_margin = 0

        -- 百分比列（亮黄色字体）
        local percentage_label = table_element.add({
            type = 'label',
            name = 'percentage' .. i,
            caption = '0%'
        })
        percentage_label.style.minimal_width = 40
        percentage_label.style.maximal_width = 40
        percentage_label.style.horizontal_align = 'left'
        percentage_label.style.font_color = CONST.COLORS.YELLOW  -- 亮黄色
        percentage_label.style.font = 'default-semibold'
        percentage_label.style.top_padding = 0
        percentage_label.style.bottom_padding = 0
    end
    
    -- 立即刷新数据
    update_all_tianfu_cooling(player)
end

--[[
    天赋状态管理函数
]]

-- 刷新天赋列表显示
local function refresh_talent_list(player)
    local parent = player.gui.left
    if not parent.tianfu_frame then 
        return 
    end
    
    local frame = parent.tianfu_frame
    local tabbed_pane = frame[CONST.TABBED_PANE]
    if not tabbed_pane then 
        return 
    end
    
    local tab_content = tabbed_pane[CONST.CONTENT_OCCUPATION_COOLDOWN]
    if not tab_content then 
        return 
    end
    
    local children = tab_content.children
    local talent_section_start = nil
    
    -- 找到天赋部分的开始位置
    for i = #children, 1, -1 do
        local child = children[i]
        if child.type == 'line' and i > 1 then
            local prev_child = children[i - 1]
            if prev_child.caption == {'amap.talent'} then
                talent_section_start = i + 1
                break
            end
        end
    end
    
    if not talent_section_start then 
        return 
    end
    
    -- 清除旧的天赋显示内容
    for i = #children, talent_section_start, -1 do
        children[i].destroy()
    end
    
    -- 重新绘制天赋部分
    draw_talent_tab(player, tab_content)
end

-- 切换天赋状态
local function toggle_talent_state(player, skill_id)
    local this = WPT.get()
    
    -- 检查天赋是否在黑名单中
    if is_talent_blacklisted(skill_id) then
        player.print({'amap.talent_blacklisted_tip'}, {r = 255, g = 165, b = 0})
        return
    end
    
    -- 确保数据结构存在
    if not this.tianfu_enabled[player.index] then
        this.tianfu_enabled[player.index] = {}
    end
    
    -- 获取当前值并切换状态
    local current_val = this.tianfu_enabled[player.index][skill_id]
    local new_state = (current_val == false) and true or false
    
    -- 保存新状态
    this.tianfu_enabled[player.index][skill_id] = new_state
    
    -- 刷新天赋列表显示
    refresh_talent_list(player)
    
    -- 通知玩家
    local talent_name = {'tianfu.' .. skill_id}
    if new_state then
        player.print({"", talent_name, " ", {'amap.talent_enabled_msg'}}, 
                     {r = 0, g = 255, b = 0})
    else
        player.print({"", talent_name, " ", {'amap.talent_disabled_msg'}}, 
                     {r = 255, g = 0, b = 0})
    end
    
    -- 清除缓存
    clear_tianfu_cache(player)
end

-- 一键开启/关闭所有已学习天赋（跳过重要天赋黑名单）
local function set_all_talents_state(player, enable)
    local this = WPT.get()
    
    if not this.skill[player.name] then
        player.print({'amap.no_talent_selected'}, {r = 255, g = 0, b = 0})
        return
    end
    
    if not this.tianfu_enabled[player.index] then
        this.tianfu_enabled[player.index] = {}
    end
    
    local count = 0
    for talent_id, _ in pairs(this.skill[player.name]) do
        if not is_talent_blacklisted(talent_id) then
            this.tianfu_enabled[player.index][talent_id] = enable
            count = count + 1
        end
    end
    
    refresh_talent_list(player)
    clear_tianfu_cache(player)
    
    if enable then
        player.print({'amap.talent_enable_all_msg', count}, {r = 0, g = 255, b = 0})
    else
        player.print({'amap.talent_disable_all_msg', count}, {r = 255, g = 165, b = 0})
    end
end

-- 删除天赋
local function delete_talent(player, talent_id)
    local this = WPT.get()
    local tpt = TPT.get()
    local DELETE_COST = 20000
    
    if not this.skill[player.name] then
        player.print({'amap.no_talent_selected'}, {r = 255, g = 0, b = 0})
        return
    end
    
    local player_coin_count = player.get_item_count('coin')
    if player_coin_count < DELETE_COST then
        player.print({'amap.delete_talent_no_coins', DELETE_COST}, {r = 255, g = 0, b = 0})
        return
    end
    
    -- ★ 方案 D 简化版：字典存储 skill_name -> q_idx，直接置 nil 删除（quality 随键一起消失）
    local found = (this.skill[player.name][talent_id] ~= nil)
    if found then
        this.skill[player.name][talent_id] = nil
    end

    if not found then
        player.print({'amap.talent_not_found'}, {r = 255, g = 0, b = 0})
        return
    end
    
    player.remove_item({name = 'coin', count = DELETE_COST})
    
    this.tianfu_buy_count[player.index] = (this.tianfu_buy_count[player.index] or 0) - 1
    
    if tpt.player_time_skills and tpt.player_time_skills[player.name] then
        tpt.player_time_skills[player.name][talent_id] = nil
    end

    -- ★ 方案 B：同步清理倒排索引，避免删除后仍被事件 handler 遍历到
    if tpt.skill_owners and tpt.skill_owners[talent_id] then
        tpt.skill_owners[talent_id][player.index] = nil
    end

    if this.tianfu_enabled and this.tianfu_enabled[player.index] then
        this.tianfu_enabled[player.index][talent_id] = nil
    end
    
    refresh_talent_list(player)
    
    clear_tianfu_cache(player)
    
    local talent_name = {'tianfu.' .. talent_id}
    player.print({"", talent_name, " ", {'amap.delete_talent_success'}, " ", DELETE_COST, " ", {'amap.coins'}}, 
                 {r = 255, g = 165, b = 0})
end

--[[
    GUI更新函数
]]

-- 更新主信息面板
local function update_gui(player)
    if not validate_player(player) then 
        return 
    end
    
    local frame = Gui.get_button_flow(player)[CONST.MAIN_FRAME]
    if not (frame and frame.visible) then 
        return 
    end

    local map = diff.get()
    local this = WPT.get()
    local wave_number = WD.get('wave_number') or 0
    
    -- 数据准备
    local best_record = math.max(map.map_record[map.world] or 0, wave_number)
    
    local car_name = "  "
    if this.silo and this.silo.valid then
        car_name = this.silo.name
    elseif this.start_game == 2 and this.car_index and game.players[this.car_index] then
        car_name = game.players[this.car_index].name
    end

    -- 更新UI元素
    frame.best_record.caption = ' [img=item.submachine-gun]: ' .. best_record
    frame.best_record.tooltip = {'amap.best_record', best_record}

    frame.biter_target.caption = ' [img=entity.car]: ' .. car_name
    frame.biter_target.tooltip = {'amap.biter_target'}

    frame.landmine.caption = ' [img=entity.land-mine]: ' .. 
                             format_number(this.now_mine, true) .. ' / ' .. 
                             format_number(this.max_mine, true)
    frame.landmine.tooltip = {'amap.land_mine_placed'}

    frame.flame_turret.caption = ' [img=entity.flamethrower-turret]: ' .. 
                                 format_number(this.flame, true) .. ' / ' .. 
                                 format_number(this.max_flame, true)
    frame.flame_turret.tooltip = {'amap.flamethrowers_placed'}
end

-- 定期更新所有玩家的GUI
local function update_gui_loop()
    for _, player in pairs(game.connected_players) do
        update_gui(player)
        update_tianfu_button(player)
    end
end

-- 更新冷却时间面板
local function update_cooling_panel()
    for _, player in pairs(game.connected_players) do
        local frame = player.gui.screen[CONST.SPELL_FRAME]
        if frame and frame.valid then
            update_all_tianfu_cooling(player)
        end
    end
end

--[[
    事件处理函数
]]

-- 玩家加入游戏事件
local function on_player_joined_game(event)
    local player = game.players[event.player_index]
    if validate_player(player) then
        create_button(player)
    end
end

-- GUI点击事件处理
local function on_gui_click(event)
    local element = event.element
    if not element.valid then 
        return 
    end

    local name = element.name
    local player = game.players[event.player_index]
    local this = WPT.get()

    -- 处理天赋开关按钮点击
    if string.sub(name, 1, #CONST.TALENT_TOGGLE_BUTTON_PREFIX) == CONST.TALENT_TOGGLE_BUTTON_PREFIX then
        local skill_id = string.sub(name, #CONST.TALENT_TOGGLE_BUTTON_PREFIX + 1)
        toggle_talent_state(player, skill_id)
        return
    end

    -- 处理一键开启/关闭全部天赋
    if name == CONST.TALENT_ENABLE_ALL_BUTTON then
        set_all_talents_state(player, true)
        return
    end
    if name == CONST.TALENT_DISABLE_ALL_BUTTON then
        set_all_talents_state(player, false)
        return
    end

    -- 处理天赋删除按钮点击
    if string.sub(name, 1, #CONST.TALENT_DELETE_BUTTON_PREFIX) == CONST.TALENT_DELETE_BUTTON_PREFIX then
        local talent_id = string.sub(name, #CONST.TALENT_DELETE_BUTTON_PREFIX + 1)
        delete_talent(player, talent_id)
        return
    end

    -- 处理冷却监控按钮
    if name == 'tianfu_frame_button' then
        tianfu_lengque_gui(player)
        return
    end

    -- 处理天赋主界面按钮
    if name == CONST.BTN_TIANFU then
        -- 初始化
        this.skill_canchoise[player.name] = this.skill_canchoise[player.name] or 0

        if this.skill_canchoise[player.name] > 0 then
            tianfu.get_new_tianfu(player)
        end

        if player.gui.left.tianfu_frame then
            player.gui.left.tianfu_frame.destroy()
        elseif not this.skill[player.name] then
            player.print({'amap.no_talent_selected'}, {r = 255, b = 0, g = 0})
        else
            tianfu_gui(player)
        end
        return
    end

    -- 处理主按钮（切换统计条）
    if name == CONST.MAIN_BUTTON then
        if not validate_player(player) then 
            return 
        end
        
        local top = Gui.get_button_flow(player)
        if top[CONST.MAIN_FRAME] then
            local info = top[CONST.MAIN_FRAME]
            if info.visible then
                info.visible = false
            else
                -- 显示前清理左侧无关GUI（保护天赋窗口）
                for _, child in pairs(player.gui.left.children) do
                    if child.name ~= 'tianfu_frame' then
                        child.destroy()
                    end
                end
                info.visible = true
                update_gui(player)
            end
        else
            create_main_frame(player)
            update_gui(player)
        end
    end
end

-- GUI选择状态改变事件处理
local function on_gui_selection_state_changed(event)
    local element = event.element
    if not element.valid then 
        return 
    end
    
    local player = game.players[event.player_index]
    local this = WPT.get()
    local name = element.name

    -- 处理冷却监控下拉框
    if name:match('^choise[1-3]$') then
        local idx = tonumber(name:sub(-1))
        local names = tianfu_names(player)
        if element.selected_index >= 1 and element.selected_index <= #names then
            this.tianfu_lengque[player.name]['dropdown_select_index' .. idx] = element.selected_index
            update_tianfu_lengque_gui(player)
        end
        return
    end

    -- 处理职业选择
    if name == 'zhiye_select' then
        if element.selected_index >= 1 and element.selected_index <= #CONST.OCCUPATIONS then
            local selected_key = CONST.OCCUPATIONS[element.selected_index].key or '随机'
            this.zhiye[player.name] = selected_key
            player.print({'amap.occupation_changed', selected_key}, {r = 0, g = 255, b = 0})
        end
        return
    end
end

Event.add(defines.events.on_player_joined_game, on_player_joined_game)
Event.add(defines.events.on_gui_click, on_gui_click)
Event.add(defines.events.on_gui_selection_state_changed, on_gui_selection_state_changed)
Event.on_nth_tick(CONST.UPDATE_INTERVAL_COOLING, update_cooling_panel)
Event.on_nth_tick(CONST.UPDATE_INTERVAL_GUI, update_gui_loop)

return Public