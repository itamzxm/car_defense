-- maps/amap/instance/modules/stack.lua
-- 叠叠乐玩法模块（Stack Tower）
--
-- 玩法类型：stack
-- 玩法说明：移动方块对齐叠塔，错位部分被切掉
--   - 纯 GUI 面板玩法（参考 sudoku 骨架 + on_tick 移动条）
--   - 顶部方块在塔宽范围内左右往复移动（on_tick 驱动）
--   - 玩家点「落下」→ 方块停在当前位置
--   - 与下层重叠部分保留为新层；错开部分被切掉（新层宽度=重叠宽度）
--   - 完全无重叠 → 失败
--   - 叠到目标层数 → 胜利
--
-- 难度分级（仅目标层数差异，移动速度统一 1 格/帧，塔宽统一 10，奖励统一 1.0）：
--   easy   - 目标 10 层 - 5 分钟 - 奖励系数 1.0
--   normal - 目标 15 层 - 5 分钟 - 奖励系数 1.0
--   hard   - 目标 25 层 - 5 分钟 - 奖励系数 1.0
--
-- 钩子实现：
--   on_surface_init - 生成草地小房间 + 外围石墙 + 初始化底座
--   on_enter        - 隐藏框架金币 label + 创建主 GUI + 提示玩法
--   on_exit         - 销毁主 GUI + 停止移动
--   on_tick         - 驱动顶部方块左右往复移动（框架每 60 tick 调一次）
--   check_victory   - 返回 md.result
--   on_gui_click    - 落下按钮 → 计算重叠 → 切边 → 新层 → 胜负判定
--
-- 注：框架 on_tick 每 60 tick（1 秒）调用一次。
--     移动速度设计为「每 tick 走 1 格 × tick_divisor」，由于 tick=1s，
--     tick_divisor=12 表示每 12 秒走 1 格（太慢）→ 改为每次 on_tick 直接走 N 格

local Instance = require 'maps.amap.instance.instance'
local Token = require 'utils.token'
local Task = require 'utils.task'

local M = {}

--==============================================================================
-- 元数据
--==============================================================================

M.type = 'stack'
M.display_name_key = 'amap.instance_stack_name'
M.description_key = 'amap.instance_stack_desc'
M.gameplay_desc_key = 'amap.instance_stack_gameplay'
M.victory_condition_key = 'amap.instance_stack_victory'
M.icon = 'item/stone-brick'  -- 砖块近似塔
M.time_limit_default = 8 * 60 * 60

--==============================================================================
-- 难度设置
--==============================================================================

M.difficulty_settings = {
    easy = {
        name = "easy",
        recycling_efficiency = 1,
        max_coins = 0,
        display_name_key = "dungeon_difficulty_easy",
        target = 10,                     -- 10 层
        speed = 1,                       -- 每 on_fast_tick 走 1 格（全难度统一）
        tower_width = 10,                -- 塔初始满宽（全难度统一）
        time_limit = 8 * 60 * 60,
        reward_multiplier = 1.0
    },
    normal = {
        name = "normal",
        recycling_efficiency = 1,
        max_coins = 0,
        display_name_key = "dungeon_difficulty_normal",
        target = 15,
        speed = 1,
        tower_width = 10,
        time_limit = 8 * 60 * 60,
        reward_multiplier = 1.0
    },
    hard = {
        name = "hard",
        recycling_efficiency = 1,
        max_coins = 0,
        display_name_key = "dungeon_difficulty_hard",
        target = 25,
        speed = 1,
        tower_width = 10,
        time_limit = 8 * 60 * 60,
        reward_multiplier = 1.0
    }
}

--==============================================================================
-- GUI 元素名常量
--==============================================================================

local GUI_FRAME     = 'dungeon_module_stack_main_frame'
local GUI_STATUS    = 'dungeon_module_stack_status'
local GUI_TOWER     = 'dungeon_module_stack_tower'  -- table，每行一个横条
local GUI_DROP_BTN  = 'dungeon_module_stack_drop_btn'
local LAYER_PREFIX  = 'dungeon_module_stack_layer_'

--==============================================================================
-- 视觉参数
--==============================================================================

-- 塔用「格子列」表示，每层一个 row，每行用 button 表现该层的宽度与偏移
-- 塔宽（满宽）固定 20 格，宽度变窄时用空 button 占位

local TOWER_MAX_WIDTH = 20  -- 满宽
local CELL_SIZE = 24        -- 每格 24px

-- 层配色（按层数循环）
local LAYER_COLOR = {
    {0.95, 0.40, 0.40},
    {0.95, 0.65, 0.30},
    {0.95, 0.90, 0.30},
    {0.50, 0.90, 0.40},
    {0.40, 0.80, 0.95},
    {0.60, 0.50, 0.95},
    {0.90, 0.50, 0.85},
}

--==============================================================================
-- 辅助函数
--==============================================================================

local function layer_color(layer_idx)
    return LAYER_COLOR[((layer_idx - 1) % #LAYER_COLOR) + 1]
end

--==============================================================================
-- GUI 创建 / 刷新
--==============================================================================

local function create_main_gui(player, data)
    local screen = player.gui.screen
    if screen[GUI_FRAME] then screen[GUI_FRAME].destroy() end
    local md = data.module_data

    local frame = screen.add({
        type = 'frame',
        name = GUI_FRAME,
        caption = {'amap.stack_main_caption', {'amap.' .. md.difficulty_label_key}},
        direction = 'vertical'
    })
    frame.force_auto_center()
    frame.style.minimal_width = TOWER_MAX_WIDTH * CELL_SIZE + 40

    -- 状态
    local status = frame.add({type = 'label', name = GUI_STATUS, caption = ''})
    status.style.font = 'heading-2'
    status.style.font_color = {1, 0.84, 0}
    status.style.top_padding = 4
    status.style.bottom_padding = 4

    -- 塔视图（每层一行；行 1 在底部，行 N 在顶部，GUI 从上往下显示要倒序）
    local tower = frame.add({
        type = 'table',
        name = GUI_TOWER,
        column_count = 1
    })
    tower.style.horizontal_spacing = 0
    tower.style.vertical_spacing = 1
    tower.style.top_padding = 4
    tower.style.bottom_padding = 4

    -- 落下按钮
    local drop_btn = frame.add({
        type = 'button',
        name = GUI_DROP_BTN,
        caption = {'amap.stack_drop'},
        tags = {stack_drop = true},
        mouse_button_filter = {'left'}
    })
    drop_btn.style.minimal_width = 120
    drop_btn.style.minimal_height = 36
    drop_btn.style.font = 'heading-2'
    drop_btn.style.font_color = {0, 0, 0}
    drop_btn.style.top_padding = 4

    -- 提示
    local hint = frame.add({type = 'label', caption = {'amap.stack_hint'}})
    hint.style.font = 'default'
    hint.style.font_color = {0.7, 0.7, 0.7}
    hint.style.single_line = false
    hint.style.maximal_width = TOWER_MAX_WIDTH * CELL_SIZE + 40
end

-- 刷新塔视图：从顶层（移动块）到底座逐行显示
-- md.layers = list of {width, offset}，索引 1 = 底座，索引 N = 最顶层
-- md.moving = {width, pos}（pos = 左边界格坐标，0..TOWER_MAX_WIDTH-width）
local function refresh_gui(player, data)
    local screen = player.gui.screen
    local frame = screen[GUI_FRAME]
    if not frame or not frame.valid then return end
    local md = data.module_data

    -- 状态
    local status = frame[GUI_STATUS]
    if status and status.valid then
        local cur_w = md.moving and md.moving.width or 0
        status.caption = {'amap.stack_status', #md.layers, md.target, cur_w}
    end

    -- 重建塔视图（先销毁旧的）
    local tower = frame[GUI_TOWER]
    if tower and tower.valid then tower.destroy() end

    tower = frame.add({
        type = 'table',
        name = GUI_TOWER,
        column_count = 1
    })
    tower.style.horizontal_spacing = 0
    tower.style.vertical_spacing = 1
    tower.style.top_padding = 4
    tower.style.bottom_padding = 4

    -- 从顶到底显示：先移动块（若在），再已落下的层（倒序）
    -- 每层用一个 table(column_count=TOWER_MAX_WIDTH) 表现
    -- 该层范围内用彩色 button，范围外用空 button（透明）

    -- 移动块（若 moving=true）
    if md.moving then
        local mv = md.moving
        local row = tower.add({type = 'table', column_count = TOWER_MAX_WIDTH})
        row.style.horizontal_spacing = 0
        row.style.vertical_spacing = 0
        for i = 0, TOWER_MAX_WIDTH - 1 do
            local btn = row.add({
                type = 'button',
                name = LAYER_PREFIX .. 'moving_' .. i,
                caption = '',
                mouse_button_filter = {'left'}
            })
            btn.style.minimal_width = CELL_SIZE
            btn.style.minimal_height = CELL_SIZE
            btn.style.maximal_width = CELL_SIZE
            btn.style.maximal_height = CELL_SIZE
            btn.style.top_padding = 0
            btn.style.bottom_padding = 0
            btn.style.left_padding = 0
            btn.style.right_padding = 0
            if i >= mv.pos and i < mv.pos + mv.width then
                btn.style.font_color = {1, 1, 1}
                -- 用 caption '■' 表现实体
                btn.caption = '■'
                btn.style.font_color = layer_color(#md.layers + 1)
            else
                btn.caption = ''
            end
        end
    end

    -- 已落下的层（倒序：从最顶层到底座）
    for i = #md.layers, 1, -1 do
        local layer = md.layers[i]
        local row = tower.add({type = 'table', column_count = TOWER_MAX_WIDTH})
        row.style.horizontal_spacing = 0
        row.style.vertical_spacing = 0
        for k = 0, TOWER_MAX_WIDTH - 1 do
            local btn = row.add({
                type = 'button',
                name = LAYER_PREFIX .. i .. '_' .. k,
                caption = '',
                mouse_button_filter = {'left'}
            })
            btn.style.minimal_width = CELL_SIZE
            btn.style.minimal_height = CELL_SIZE
            btn.style.maximal_width = CELL_SIZE
            btn.style.maximal_height = CELL_SIZE
            btn.style.top_padding = 0
            btn.style.bottom_padding = 0
            btn.style.left_padding = 0
            btn.style.right_padding = 0
            if k >= layer.offset and k < layer.offset + layer.width then
                btn.caption = '■'
                btn.style.font_color = layer_color(i)
            else
                btn.caption = ''
            end
        end
    end
end

--==============================================================================
-- 钩子实现
--==============================================================================

local function delayed_exit(params)
    local player = game.players[params.player_index]
    if not player or not player.valid then return end
    Instance.exit(player, params.reason)
end
local delayed_exit_token = Token.register(delayed_exit)

function M.on_surface_init(surface, player, data, difficulty)
    local diff = M.difficulty_settings[difficulty] or M.difficulty_settings.easy
    local tw = diff.tower_width

    -- 底座：留出移动空间，不铺满（否则首块移动块无移动范围）
    -- 底座宽度 = 满宽 - 4，居中放置
    local base_w = tw - 4
    local base_offset = 2  -- 居中：偏移 = (tw - base_w) / 2 = 2
    local base = {width = base_w, offset = base_offset}

    -- 移动块：与底座同宽，从左侧开始
    local moving = {width = base_w, pos = 0, dir = 1}

    data.module_data = {
        target = diff.target,
        speed = diff.speed,
        tower_width = tw,
        layers = {base},      -- 索引 1 = 底座
        moving = moving,
        moving_active = true,
        reward_base = diff.reward_multiplier,
        result = nil,
        difficulty_label_key = diff.display_name_key,
    }
    data.time_limit = diff.time_limit or M.time_limit_default

    -- 1. 全图铺 grass-1
    for x = -50, 50 do
        for y = -50, 50 do
            surface.set_tiles{{name = "grass-1", position = {x, y}}}
        end
    end

    -- 2. 外围石墙围成一个小房间
    local room_half = 5
    for x = -room_half - 1, room_half + 1 do
        for _, y in ipairs({-room_half - 1, room_half + 1}) do
            local e = surface.create_entity({
                name = "stone-wall", position = {x = x, y = y}, force = player.force
            })
            if e then e.minable_flag = false; e.destructible = false end
        end
    end
    for y = -room_half, room_half do
        for _, x in ipairs({-room_half - 1, room_half + 1}) do
            local e = surface.create_entity({
                name = "stone-wall", position = {x = x, y = y}, force = player.force
            })
            if e then e.minable_flag = false; e.destructible = false end
        end
    end

    -- 3. 副本常昼
    surface.always_day = true

    -- 4. chart
    player.force.chart(surface, {
        {-room_half - 2, -room_half - 2},
        {room_half + 2, room_half + 2}
    })
end

function M.on_enter(player, data, difficulty)
    player.force.manual_mining_speed_modifier = 0

    local top = player.gui.top
    if top['dungeon_coins'] then
        top['dungeon_coins'].destroy()
    end

    create_main_gui(player, data)
    refresh_gui(player, data)

    local md = data.module_data
    if md then
        player.print({'amap.stack_enter', md.target, {'amap.' .. md.difficulty_label_key}}, {r = 0, g = 1, b = 0})
    end
end

function M.on_exit(player, data, reason)
    local screen = player.gui.screen
    if screen[GUI_FRAME] then
        screen[GUI_FRAME].destroy()
    end
    local md = data.module_data
    if md then
        md.moving_active = false
    end
end

-- 框架每 20 tick（~0.33 秒）调用 on_fast_tick：驱动顶部方块左右往复移动
-- （on_tick 60 tick=1s 太慢，改用 on_fast_tick 让方块移动更流畅）
function M.on_fast_tick(player, data)
    local md = data.module_data
    if not md then return end
    if md.result then return end
    if not md.moving_active then return end
    if not md.moving then return end

    local mv = md.moving
    local max_pos = md.tower_width - mv.width
    if max_pos < 0 then max_pos = 0 end

    -- 按 speed 移动
    for _ = 1, md.speed do
        mv.pos = mv.pos + mv.dir
        if mv.pos >= max_pos then
            mv.pos = max_pos
            mv.dir = -1
        elseif mv.pos <= 0 then
            mv.pos = 0
            mv.dir = 1
        end
    end

    refresh_gui(player, data)
end

function M.check_victory(player, data)
    local md = data.module_data
    if not md then return nil end
    if md.result then return md.result end
    return nil
end

function M.on_gui_click(player, event)
    local element = event.element
    if not element or not element.valid then return end

    local data = Instance.get_data(player.index)
    if not data or not data.active then return end
    local md = data.module_data
    if not md then return end
    if md.result then return end

    local tags = element.tags or {}
    local name = element.name

    -- 只响应「落下」按钮
    if not tags.stack_drop and name ~= GUI_DROP_BTN then return end

    if not md.moving or not md.moving_active then return end

    -- 取下层（最顶已落下层）
    local lower = md.layers[#md.layers]
    local mv = md.moving

    -- 计算重叠区间
    local l_left = lower.offset
    local l_right = lower.offset + lower.width  -- exclusive
    local m_left = mv.pos
    local m_right = mv.pos + mv.width           -- exclusive

    local ov_left = math.max(l_left, m_left)
    local ov_right = math.min(l_right, m_right)
    local ov_width = ov_right - ov_left

    if ov_width <= 0 then
        -- 完全无重叠 → 失败
        md.moving_active = false
        md.moving = nil
        md.result = 'defeat'
        player.print({'amap.stack_lose'}, {r = 1, g = 0, b = 0})
        Task.set_timeout_in_ticks(2, delayed_exit_token, {player_index = player.index, reason = 'defeat'})
        return
    end

    -- 新层落下
    md.layers[#md.layers + 1] = {width = ov_width, offset = ov_left}

    -- 判定胜利
    if #md.layers >= md.target then
        md.moving_active = false
        md.moving = nil
        -- 计算平均宽度比，决定奖励
        local total_w = 0
        for _, layer in ipairs(md.layers) do
            total_w = total_w + layer.width
        end
        local avg_ratio = (total_w / #md.layers) / md.tower_width
        local mul = md.reward_base * (avg_ratio >= 0.6 and 1.3 or 1.0)
        Instance.set_reward_multiplier(player, mul)
        md.result = 'victory'
        player.print({'amap.stack_win', #md.layers}, {r = 0, g = 1, b = 0})
        Task.set_timeout_in_ticks(2, delayed_exit_token, {player_index = player.index, reason = 'victory'})
        return
    end

    -- 准备下一块移动块（与刚落下的新层同宽，从最左开始）
    md.moving = {width = ov_width, pos = 0, dir = 1}
    refresh_gui(player, data)
end

--==============================================================================
-- 注册到框架
--==============================================================================

Instance.register(M.type, M)

--==============================================================================
-- 测试用内部 API 暴露
--==============================================================================

_STACK_TEST = {
    TOWER_MAX_WIDTH = TOWER_MAX_WIDTH,
    LAYER_COLOR = LAYER_COLOR,
    layer_color = layer_color,
    difficulty_settings = M.difficulty_settings,
}

return M
