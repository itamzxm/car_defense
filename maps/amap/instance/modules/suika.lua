-- maps/amap/instance/modules/suika.lua
-- 合成大西瓜玩法模块（Suika Merge）
--
-- 玩法类型：suika
-- 玩法说明：落子合并同类水果
--   - 纯 GUI 面板玩法（参考 sudoku / merge2048 骨架）
--   - 顶部显示「待落水果」，玩家点某列 → 水果落到该列最下方空位
--   - 落定后，与左右相邻同级水果合并为高一级水果（合并位置=落子格）
--   - 连锁合并：合并后新水果若与左右相邻同级 → 继续合并（上限 64 次）
--   - 棋盘出现 ≥ 目标等级水果 → 胜利
--   - 某列顶端被占且无合并空间 → 失败
--
-- 难度分级（仅目标等级差异，棋盘统一 8x12，时间统一 10 分钟，奖励统一 1.0）：
--   easy   - 8x12 - 目标 8 (哈密瓜)  - 10 分钟 - 奖励系数 1.0
--   normal - 8x12 - 目标 10 (西瓜)   - 10 分钟 - 奖励系数 1.0
--   hard   - 8x12 - 目标 11 (双西瓜) - 10 分钟 - 奖励系数 1.0
--
-- 钩子实现：
--   on_surface_init - 生成草地小房间 + 外围石墙 + 初始化空棋盘与待落水果
--   on_enter        - 隐藏框架金币 label + 创建主 GUI + 提示玩法
--   on_exit         - 销毁主 GUI
--   on_tick         - 静态游戏，无需操作
--   check_victory   - 返回 md.result（终局由 on_gui_click 经延迟退出设置）
--   on_gui_click    - 列点击 → 落子 → 合并连锁 → 刷新 → 判定胜负

local Instance = require 'maps.amap.instance.instance'
local Token = require 'utils.token'
local Task = require 'utils.task'

local M = {}

--==============================================================================
-- 元数据
--==============================================================================

M.type = 'suika'
M.display_name_key = 'amap.instance_suika_name'
M.description_key = 'amap.instance_suika_desc'
M.gameplay_desc_key = 'amap.instance_suika_gameplay'
M.victory_condition_key = 'amap.instance_suika_victory'
M.icon = 'item/water-barrel'  -- 水桶近似「水果」
M.time_limit_default = 12 * 60 * 60

--==============================================================================
-- 难度设置
--==============================================================================

M.difficulty_settings = {
    easy = {
        name = "easy",
        recycling_efficiency = 1,
        max_coins = 0,
        display_name_key = "dungeon_difficulty_easy",
        cols = 8,                        -- 8 列（全难度统一）
        rows = 12,                       -- 12 行（全难度统一）
        target = 8,                      -- 哈密瓜
        time_limit = 10 * 60 * 60,       -- 10 分钟（全难度统一）
        reward_multiplier = 1.0          -- 奖励系数（全难度统一）
    },
    normal = {
        name = "normal",
        recycling_efficiency = 1,
        max_coins = 0,
        display_name_key = "dungeon_difficulty_normal",
        cols = 8,
        rows = 12,
        target = 10,                     -- 西瓜
        time_limit = 10 * 60 * 60,
        reward_multiplier = 1.0
    },
    hard = {
        name = "hard",
        recycling_efficiency = 1,
        max_coins = 0,
        display_name_key = "dungeon_difficulty_hard",
        cols = 8,
        rows = 12,
        target = 11,                     -- 双西瓜
        time_limit = 10 * 60 * 60,
        reward_multiplier = 1.0
    }
}

--==============================================================================
-- GUI 元素名常量
--==============================================================================

local GUI_FRAME  = 'dungeon_module_suika_main_frame'
local GUI_STATUS = 'dungeon_module_suika_status'
local GUI_NEXT   = 'dungeon_module_suika_next'
local GUI_GRID   = 'dungeon_module_suika_grid'
local GUI_COL_PREFIX = 'dungeon_module_suika_col_'  -- 列头按钮（落子用）
local CELL_PREFIX    = 'dungeon_module_suika_cell_' -- 格子（仅显示）

--==============================================================================
-- 水果等级配色与名称
--==============================================================================
-- 11 级路线：1 樱桃 → 2 草莓 → 3 葡萄 → 4 橘子 → 5 柿子 → 6 苹果
--          → 7 梨 → 8 哈密瓜 → 9 菠萝 → 10 西瓜 → 11 双西瓜

local TIER_COLOR = {
    [1]  = {1.00, 0.30, 0.30},  -- 樱桃 红
    [2]  = {1.00, 0.50, 0.60},  -- 草莓 粉红
    [3]  = {0.60, 0.30, 0.90},  -- 葡萄 紫
    [4]  = {1.00, 0.65, 0.20},  -- 橘子 橙
    [5]  = {1.00, 0.55, 0.30},  -- 柿子 橘红
    [6]  = {0.90, 0.30, 0.30},  -- 苹果 深红
    [7]  = {0.80, 0.90, 0.30},  -- 梨 黄绿
    [8]  = {0.90, 0.85, 0.40},  -- 哈密瓜 金黄
    [9]  = {0.70, 0.90, 0.30},  -- 菠萝 绿黄
    [10] = {0.20, 0.70, 0.30},  -- 西瓜 深绿
    [11] = {0.30, 0.40, 0.20},  -- 双西瓜 墨绿
}

local TIER_CHAR = {
    [1] = '樱', [2] = '莓', [3] = '葡', [4] = '橘', [5] = '柿', [6] = '苹',
    [7] = '梨', [8] = '哈', [9] = '菠', [10] = '西', [11] = '双',
}

-- 各等级产出得分
local SCORE = {0, 5, 10, 20, 40, 80, 160, 320, 640, 1280, 2560, 5120}

-- 待落水果权重（前 5 级，越高级越罕见）
local WEIGHTS = {
    {tier = 1, w = 40},
    {tier = 2, w = 30},
    {tier = 3, w = 18},
    {tier = 4, w = 8},
    {tier = 5, w = 4},
}
local WEIGHT_TOTAL = 100

--==============================================================================
-- 辅助函数
--==============================================================================

local function roll_next()
    local r = math.random(WEIGHT_TOTAL)
    local acc = 0
    for _, e in ipairs(WEIGHTS) do
        acc = acc + e.w
        if r <= acc then return e.tier end
    end
    return 1
end

local function cell_caption(v)
    if v == 0 then return '' end
    return TIER_CHAR[v] or '?'
end

local function cell_color(v)
    if v == 0 then return nil end
    return TIER_COLOR[v] or {1, 1, 1}
end

-- 列 c 的最下方空位行号（1=底，rows=顶），无空位返回 nil
local function find_drop_row(md, c)
    for r = 1, md.rows do
        if md.grid[r][c] == 0 then return r end
    end
    return nil
end

-- 当前棋盘最高等级
local function max_tier(md)
    local m = 0
    for r = 1, md.rows do
        for c = 1, md.cols do
            if md.grid[r][c] > m then m = md.grid[r][c] end
        end
    end
    return m
end

-- 棋盘是否有空位
local function has_empty(md)
    for c = 1, md.cols do
        if md.grid[md.rows][c] == 0 then return true end  -- 顶行有空位即有空位
    end
    return false
end

--==============================================================================
-- 合并连锁
--==============================================================================
-- 设计：落子后从落子格向左右延伸找同级连续段，长度 ≥ 2（即落子+左/右 1 个）
-- 即可合并。合并位置=落子格本身，新等级=旧+1。合并后新等级可能再与左右相邻同级
-- → 继续合并，形成连锁（天然收敛：等级有上限 11）。
--
-- 注：原版 Suika 是物理碰撞合并，本设计为「左右相邻同级」近似，体验接近且实现简单。

-- 从落子格 (r, c) 起反复结算合并
local function resolve_merges(md, r, c)
    for _ = 1, 64 do
        local tier = md.grid[r][c]
        if tier == 0 or tier >= 11 then return end
        -- 向左扫同级
        local left = c
        while left > 1 and md.grid[r][left - 1] == tier do
            left = left - 1
        end
        -- 向右扫同级
        local right = c
        while right < md.cols and md.grid[r][right + 1] == tier do
            right = right + 1
        end
        -- 连续段长度（含落子格）
        local span = right - left + 1
        if span < 2 then return end  -- 单独一格，不合并
        -- 清除段内所有格
        for cc = left, right do
            md.grid[r][cc] = 0
        end
        -- 落子格升一级
        md.grid[r][c] = tier + 1
        md.score = md.score + SCORE[tier + 1]
    end
end

--==============================================================================
-- GUI 创建 / 刷新
--==============================================================================

local function create_main_gui(player, data)
    local screen = player.gui.screen
    if screen[GUI_FRAME] then screen[GUI_FRAME].destroy() end
    local md = data.module_data
    local cols = md.cols
    local rows = md.rows

    local frame = screen.add({
        type = 'frame',
        name = GUI_FRAME,
        caption = {'amap.suika_main_caption', {'amap.' .. md.difficulty_label_key}},
        direction = 'vertical'
    })
    frame.force_auto_center()
    frame.style.minimal_width = cols * 48 + 40

    -- 顶栏状态
    local status = frame.add({type = 'label', name = GUI_STATUS, caption = ''})
    status.style.font = 'heading-2'
    status.style.font_color = {1, 0.84, 0}
    status.style.top_padding = 4
    status.style.bottom_padding = 4

    -- 待落区
    local next_label = frame.add({type = 'label', name = GUI_NEXT, caption = ''})
    next_label.style.font = 'heading-2'
    next_label.style.font_color = {0, 0, 0}
    next_label.style.top_padding = 4
    next_label.style.bottom_padding = 4

    -- 列头按钮（点列即落子）
    local col_bar = frame.add({type = 'table', name = GUI_GRID .. '_colbar', column_count = cols})
    col_bar.style.horizontal_spacing = 2
    col_bar.style.vertical_spacing = 2
    for c = 1, cols do
        local btn = col_bar.add({
            type = 'button',
            name = GUI_COL_PREFIX .. c,
            caption = '↓',
            tags = {suika_drop_col = true, c = c},
            mouse_button_filter = {'left'}
        })
        btn.style.minimal_width = 44
        btn.style.minimal_height = 28
        btn.style.maximal_width = 44
        btn.style.maximal_height = 28
        btn.style.font = 'default-bold'
        btn.style.font_color = {0, 0, 0}
    end

    -- 棋盘网格：行 1 在底部，行 rows 在顶部，GUI 从上往下显示要倒序
    local grid_table = frame.add({
        type = 'table',
        name = GUI_GRID,
        column_count = cols
    })
    grid_table.style.horizontal_spacing = 2
    grid_table.style.vertical_spacing = 2
    grid_table.style.top_padding = 4
    grid_table.style.bottom_padding = 4

    local cell_size = 44
    for r = rows, 1, -1 do  -- 顶行先显示
        for c = 1, cols do
            local v = md.grid[r][c]
            local btn = grid_table.add({
                type = 'button',
                name = CELL_PREFIX .. r .. '_' .. c,
                caption = cell_caption(v),
                mouse_button_filter = {'left'}  -- 格子本身可点也落子（按列）
            })
            btn.tags = {suika_drop_col = true, c = c}  -- 点格子=点该列
            btn.style.minimal_width = cell_size
            btn.style.minimal_height = cell_size
            btn.style.maximal_width = cell_size
            btn.style.maximal_height = cell_size
            btn.style.font = 'heading-2'
            btn.style.font_color = {0, 0, 0}  -- 统一黑色字体
            btn.style.horizontal_align = 'center'
            btn.style.vertical_align = 'center'
            btn.style.top_padding = 0
            btn.style.bottom_padding = 0
            btn.style.left_padding = 0
            btn.style.right_padding = 0
        end
    end

    -- 提示
    local hint = frame.add({type = 'label', caption = {'amap.suika_hint'}})
    hint.style.font = 'default'
    hint.style.font_color = {0.7, 0.7, 0.7}
    hint.style.single_line = false
    hint.style.maximal_width = cols * 48 + 40
end

local function refresh_gui(player, data)
    local screen = player.gui.screen
    local frame = screen[GUI_FRAME]
    if not frame or not frame.valid then return end
    local md = data.module_data
    local cols = md.cols
    local rows = md.rows

    -- 状态
    local status = frame[GUI_STATUS]
    if status and status.valid then
        local best = max_tier(md)
        local next_str = TIER_CHAR[md.next] or '?'
        local target_str = TIER_CHAR[md.target] or '?'
        status.caption = {'amap.suika_status', target_str, next_str, best, md.score}
    end

    -- 待落
    local next_label = frame[GUI_NEXT]
    if next_label and next_label.valid then
        next_label.caption = {'amap.suika_next_label', cell_caption(md.next)}
        next_label.style.font_color = {0, 0, 0}
    end

    -- 棋盘
    local grid_table = frame[GUI_GRID]
    if not grid_table or not grid_table.valid then return end
    for r = 1, rows do
        for c = 1, cols do
            local btn = grid_table[CELL_PREFIX .. r .. '_' .. c]
            if btn and btn.valid then
                local v = md.grid[r][c]
                btn.caption = cell_caption(v)
                btn.style.font_color = {0, 0, 0}  -- 统一黑色字体
            end
        end
    end
end

--==============================================================================
-- 钩子实现
--==============================================================================

-- 延迟退出（避免在 GUI 事件 handler 内直接销毁 surface/character）
local function delayed_exit(params)
    local player = game.players[params.player_index]
    if not player or not player.valid then return end
    Instance.exit(player, params.reason)
end
local delayed_exit_token = Token.register(delayed_exit)

function M.on_surface_init(surface, player, data, difficulty)
    local diff = M.difficulty_settings[difficulty] or M.difficulty_settings.easy
    local cols = diff.cols
    local rows = diff.rows

    local grid = {}
    for r = 1, rows do
        grid[r] = {}
        for c = 1, cols do grid[r][c] = 0 end
    end

    data.module_data = {
        cols = cols,
        rows = rows,
        grid = grid,
        next = roll_next(),
        score = 0,
        target = diff.target,
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

    -- 3. 副本常昼，视野清晰
    surface.always_day = true

    -- 4. 让副本 force chart 房间区域
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
        local target_name = TIER_CHAR[md.target] or '?'
        player.print({'amap.suika_enter', target_name, {'amap.' .. md.difficulty_label_key}}, {r = 0, g = 1, b = 0})
    end
end

function M.on_exit(player, data, reason)
    local screen = player.gui.screen
    if screen[GUI_FRAME] then
        screen[GUI_FRAME].destroy()
    end
end

function M.on_tick(player, data)
    -- no-op
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
    if not tags.suika_drop_col then return end
    local c = tags.c
    if type(c) ~= 'number' then return end
    if c < 1 or c > md.cols then return end

    -- 找落子行
    local r = find_drop_row(md, c)
    if not r then
        player.print({'amap.suika_invalid'}, {r = 1, g = 1, b = 0})
        return
    end

    -- 落子
    md.grid[r][c] = md.next
    md.next = roll_next()
    resolve_merges(md, r, c)
    refresh_gui(player, data)

    -- 判定胜负
    if max_tier(md) >= md.target then
        local mul = md.reward_base
        Instance.set_reward_multiplier(player, mul)
        md.result = 'victory'
        local target_name = TIER_CHAR[md.target] or '?'
        player.print({'amap.suika_win', target_name}, {r = 0, g = 1, b = 0})
        Task.set_timeout_in_ticks(2, delayed_exit_token, {player_index = player.index, reason = 'victory'})
    elseif not has_empty(md) then
        -- 所有列顶端被占（无法再落子）→ 失败
        md.result = 'defeat'
        player.print({'amap.suika_lose'}, {r = 1, g = 0, b = 0})
        Task.set_timeout_in_ticks(2, delayed_exit_token, {player_index = player.index, reason = 'defeat'})
    end
end

--==============================================================================
-- 注册到框架
--==============================================================================

Instance.register(M.type, M)

--==============================================================================
-- 测试用内部 API 暴露
--==============================================================================

_SUIKA_TEST = {
    SCORE = SCORE,
    WEIGHTS = WEIGHTS,
    TIER_CHAR = TIER_CHAR,
    roll_next = roll_next,
    find_drop_row = find_drop_row,
    resolve_merges = resolve_merges,
    max_tier = max_tier,
    has_empty = has_empty,
    difficulty_settings = M.difficulty_settings,
}

return M
