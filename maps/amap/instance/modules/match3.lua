-- maps/amap/instance/modules/match3.lua
-- 三消乐玩法模块（Match-3 Blast）
--
-- 玩法类型：match3
-- 玩法说明：交换相邻元素，3+ 同色连线即消，连锁得分
--   - 纯 GUI 面板玩法（参考 sudoku / merge2048 骨架）
--   - 玩家点一个元素选中，再点相邻元素 → 交换
--   - 若交换后形成 ≥3 同色横/竖直线 → 消除，得分；否则交换回退
--   - 消除后上方元素下落，顶部随机补充新元素
--   - 下落可能引发新连锁（combo），combo 越高得分倍率越高
--   - 分数 ≥ 目标 → 胜利；时间耗尽未达标 → 失败（由框架超时处理）
--
-- 难度分级（仅目标分差异，颜色统一 6，无步数限制，时间统一 10 分钟，奖励统一 1.0）：
--   easy   - 8x8 - 6 色 - 目标 1000 - 无步数限制 - 10 分钟 - 奖励系数 1.0
--   normal - 8x8 - 6 色 - 目标 2500 - 无步数限制 - 10 分钟 - 奖励系数 1.0
--   hard   - 8x8 - 6 色 - 目标 5000 - 无步数限制 - 10 分钟 - 奖励系数 1.0
--
-- 钩子实现：
--   on_surface_init - 生成草地小房间 + 外围石墙 + 初始化无三连棋盘
--   on_enter        - 隐藏框架金币 label + 创建主 GUI + 提示玩法
--   on_exit         - 销毁主 GUI
--   on_tick         - 静态游戏，无需操作
--   check_victory   - 返回 md.result
--   on_gui_click    - 选格 → 交换 → 检测消除 → 下落补充 → 连锁 → 刷新 → 胜负判定

local Instance = require 'maps.amap.instance.instance'
local Token = require 'utils.token'
local Task = require 'utils.task'

local M = {}

--==============================================================================
-- 元数据
--==============================================================================

M.type = 'match3'
M.display_name_key = 'amap.instance_match3_name'
M.description_key = 'amap.instance_match3_desc'
M.gameplay_desc_key = 'amap.instance_match3_gameplay'
M.victory_condition_key = 'amap.instance_match3_victory'
M.icon = 'item/electronic-circuit'  -- 网格状
M.time_limit_default = 10 * 60 * 60

--==============================================================================
-- 难度设置
--==============================================================================

M.difficulty_settings = {
    easy = {
        name = "easy",
        recycling_efficiency = 1,
        max_coins = 0,
        display_name_key = "dungeon_difficulty_easy",
        size = 8,
        colors = 6,                      -- 6 色（全难度统一）
        target = 1000,                   -- 1000 分
        time_limit = 10 * 60 * 60,       -- 10 分钟（全难度统一）
        reward_multiplier = 1.0          -- 奖励系数（全难度统一）
    },
    normal = {
        name = "normal",
        recycling_efficiency = 1,
        max_coins = 0,
        display_name_key = "dungeon_difficulty_normal",
        size = 8,
        colors = 6,
        target = 2500,
        time_limit = 10 * 60 * 60,
        reward_multiplier = 1.0
    },
    hard = {
        name = "hard",
        recycling_efficiency = 1,
        max_coins = 0,
        display_name_key = "dungeon_difficulty_hard",
        size = 8,
        colors = 6,
        target = 5000,
        time_limit = 10 * 60 * 60,
        reward_multiplier = 1.0
    }
}

--==============================================================================
-- GUI 元素名常量
--==============================================================================

local GUI_FRAME  = 'dungeon_module_match3_main_frame'
local GUI_STATUS = 'dungeon_module_match3_status'
local GUI_GRID   = 'dungeon_module_match3_grid'
local CELL_PREFIX = 'dungeon_module_match3_cell_'

--==============================================================================
-- 元素配色与字符
--==============================================================================
-- 用 7 种颜色 + 单字符表现 1..7 号元素

local TILE_COLOR = {
    [1] = {1.00, 0.30, 0.30},  -- 红
    [2] = {0.30, 0.70, 1.00},  -- 蓝
    [3] = {0.30, 0.85, 0.30},  -- 绿
    [4] = {1.00, 0.85, 0.20},  -- 黄
    [5] = {0.85, 0.40, 1.00},  -- 紫
    [6] = {1.00, 0.55, 0.20},  -- 橙
    [7] = {0.30, 0.85, 0.85},  -- 青
}

local TILE_CHAR = {
    [1] = '★', [2] = '◆', [3] = '▲', [4] = '●',
    [5] = '■', [6] = '♥', [7] = '♦',
}

--==============================================================================
-- 辅助函数
--==============================================================================

local function cell_caption(v)
    if v == 0 then return '' end
    return TILE_CHAR[v] or '?'
end

local function cell_color(v)
    if v == 0 then return nil end
    return TILE_COLOR[v] or {1, 1, 1}
end

-- 4 邻接
local NEIGHBOR4 = {{0, -1}, {0, 1}, {-1, 0}, {1, 0}}

-- 判断两点是否相邻
local function is_adjacent(r1, c1, r2, c2)
    return math.abs(r1 - r2) + math.abs(c1 - c2) == 1
end

-- 生成无三连棋盘（反复置换法）
local function generate_grid(size, colors)
    local grid = {}
    for r = 1, size do
        grid[r] = {}
        for c = 1, size do
            -- 随机一个不立即成三连的颜色
            local tries = 0
            local v
            while tries < 20 do
                v = math.random(1, colors)
                -- 检查左边两个是否同色（成三连）
                if c >= 3 and grid[r][c - 1] == v and grid[r][c - 2] == v then
                    tries = tries + 1
                -- 检查上面两个是否同色
                elseif r >= 3 and grid[r - 1][c] == v and grid[r - 2][c] == v then
                    tries = tries + 1
                else
                    break
                end
            end
            grid[r][c] = v
        end
    end
    return grid
end

-- 扫描所有 ≥3 同色横/竖直线，返回待消除格集合 {r_c = true}
local function find_matches(grid, size)
    local matches = {}
    -- 横向
    for r = 1, size do
        local c = 1
        while c <= size do
            local v = grid[r][c]
            if v ~= 0 then
                local c2 = c + 1
                while c2 <= size and grid[r][c2] == v do c2 = c2 + 1 end
                if c2 - c >= 3 then
                    for cc = c, c2 - 1 do matches[r .. '_' .. cc] = true end
                end
                c = c2
            else
                c = c + 1
            end
        end
    end
    -- 纵向
    for c = 1, size do
        local r = 1
        while r <= size do
            local v = grid[r][c]
            if v ~= 0 then
                local r2 = r + 1
                while r2 <= size and grid[r2][c] == v do r2 = r2 + 1 end
                if r2 - r >= 3 then
                    for rr = r, r2 - 1 do matches[rr .. '_' .. c] = true end
                end
                r = r2
            else
                r = r + 1
            end
        end
    end
    return matches
end

-- 统计 matches 集合大小
local function count_matches(matches)
    local n = 0
    for _ in pairs(matches) do n = n + 1 end
    return n
end

-- 应用消除：把 matches 中的格置 0，返回消除数
local function apply_matches(grid, matches)
    local n = 0
    for key in pairs(matches) do
        local r, c = string.match(key, '^(%d+)_(%d+)$')
        r, c = tonumber(r), tonumber(c)
        if grid[r][c] ~= 0 then
            grid[r][c] = 0
            n = n + 1
        end
    end
    return n
end

-- 重力下落 + 顶部补充（行 1=底，行 size=顶）
-- 注：本设计 row 1 为顶部（与 sudoku 一致），故重力向「行号大」方向落
local function apply_gravity(grid, size, colors)
    for c = 1, size do
        -- 从底（行 size）向顶（行 1）收集非空
        local stack = {}
        for r = size, 1, -1 do
            if grid[r][c] ~= 0 then
                stack[#stack + 1] = grid[r][c]
            end
        end
        -- 从底向上填回
        for r = size, 1, -1 do
            local idx = size - r + 1
            if idx <= #stack then
                grid[r][c] = stack[idx]
            else
                grid[r][c] = math.random(1, colors)
            end
        end
    end
end

-- 完整连锁结算：返回总消除数、combo 数
local function resolve_chain(grid, size, colors)
    local total_cleared = 0
    local combo = 0
    for _ = 1, 32 do  -- 连锁上限 32
        local matches = find_matches(grid, size)
        local n = count_matches(matches)
        if n == 0 then break end
        apply_matches(grid, matches)
        total_cleared = total_cleared + n
        combo = combo + 1
        apply_gravity(grid, size, colors)
    end
    return total_cleared, combo
end

--==============================================================================
-- GUI 创建 / 刷新
--==============================================================================

local function create_main_gui(player, data)
    local screen = player.gui.screen
    if screen[GUI_FRAME] then screen[GUI_FRAME].destroy() end
    local md = data.module_data
    local size = md.size

    local frame = screen.add({
        type = 'frame',
        name = GUI_FRAME,
        caption = {'amap.match3_main_caption', {'amap.' .. md.difficulty_label_key}},
        direction = 'vertical'
    })
    frame.force_auto_center()
    frame.style.minimal_width = size * 44 + 40

    -- 状态
    local status = frame.add({type = 'label', name = GUI_STATUS, caption = ''})
    status.style.font = 'heading-2'
    status.style.font_color = {1, 0.84, 0}
    status.style.top_padding = 4
    status.style.bottom_padding = 4

    -- 网格
    local grid_table = frame.add({
        type = 'table',
        name = GUI_GRID,
        column_count = size
    })
    grid_table.style.horizontal_spacing = 2
    grid_table.style.vertical_spacing = 2
    grid_table.style.top_padding = 4
    grid_table.style.bottom_padding = 4

    local cell_size = 40
    for r = 1, size do
        for c = 1, size do
            local v = md.grid[r][c]
            local btn = grid_table.add({
                type = 'button',
                name = CELL_PREFIX .. r .. '_' .. c,
                caption = cell_caption(v),
                tags = {match3_cell = true, r = r, c = c},
                mouse_button_filter = {'left'}
            })
            btn.style.minimal_width = cell_size
            btn.style.minimal_height = cell_size
            btn.style.maximal_width = cell_size
            btn.style.maximal_height = cell_size
            btn.style.font = 'heading-2'
            btn.style.font_color = cell_color(v) or {1, 1, 1}
            btn.style.horizontal_align = 'center'
            btn.style.vertical_align = 'center'
            btn.style.top_padding = 0
            btn.style.bottom_padding = 0
            btn.style.left_padding = 0
            btn.style.right_padding = 0
        end
    end

    -- 提示
    local hint = frame.add({type = 'label', caption = {'amap.match3_hint'}})
    hint.style.font = 'default'
    hint.style.font_color = {0.7, 0.7, 0.7}
    hint.style.single_line = false
    hint.style.maximal_width = size * 44 + 40
end

local function refresh_gui(player, data)
    local screen = player.gui.screen
    local frame = screen[GUI_FRAME]
    if not frame or not frame.valid then return end
    local md = data.module_data
    local size = md.size

    -- 状态
    local status = frame[GUI_STATUS]
    if status and status.valid then
        status.caption = {'amap.match3_status', md.score, md.target, md.combo_max}
    end

    -- 棋盘
    local grid_table = frame[GUI_GRID]
    if not grid_table or not grid_table.valid then return end
    for r = 1, size do
        for c = 1, size do
            local btn = grid_table[CELL_PREFIX .. r .. '_' .. c]
            if btn and btn.valid then
                local v = md.grid[r][c]
                btn.caption = cell_caption(v)
                -- 选中高亮：用绿色字体标记
                if md.sel_r == r and md.sel_c == c then
                    btn.style.font_color = {0, 1, 0}
                else
                    btn.style.font_color = cell_color(v) or {1, 1, 1}
                end
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
    local size = diff.size

    local grid = generate_grid(size, diff.colors)

    data.module_data = {
        size = size,
        colors = diff.colors,
        grid = grid,
        score = 0,
        target = diff.target,
        combo_max = 0,
        sel_r = nil,
        sel_c = nil,
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
        player.print({'amap.match3_enter', md.target, {'amap.' .. md.difficulty_label_key}}, {r = 0, g = 1, b = 0})
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
    if not tags.match3_cell then return end
    local r = tags.r
    local c = tags.c
    if type(r) ~= 'number' or type(c) ~= 'number' then return end
    if r < 1 or r > md.size or c < 1 or c > md.size then return end

    -- 首次选中
    if not md.sel_r then
        md.sel_r = r
        md.sel_c = c
        refresh_gui(player, data)
        return
    end

    -- 同格点击 → 取消选中
    if md.sel_r == r and md.sel_c == c then
        md.sel_r = nil
        md.sel_c = nil
        refresh_gui(player, data)
        return
    end

    -- 非相邻 → 切换选中
    if not is_adjacent(md.sel_r, md.sel_c, r, c) then
        md.sel_r = r
        md.sel_c = c
        refresh_gui(player, data)
        return
    end

    -- 相邻交换
    local r1, c1 = md.sel_r, md.sel_c
    md.grid[r1][c1], md.grid[r][c] = md.grid[r][c], md.grid[r1][c1]
    md.sel_r = nil
    md.sel_c = nil

    -- 检查是否产生消除
    local matches = find_matches(md.grid, md.size)
    if count_matches(matches) == 0 then
        -- 无消除 → 回退交换
        md.grid[r1][c1], md.grid[r][c] = md.grid[r][c], md.grid[r1][c1]
        player.print({'amap.match3_invalid'}, {r = 1, g = 1, b = 0})
        refresh_gui(player, data)
        return
    end

    -- 有消除 → 连锁结算
    local cleared, combo = resolve_chain(md.grid, md.size, md.colors)
    -- 得分：每消 1 个 10 分 × combo 倍率
    md.score = md.score + cleared * 10 * combo
    if combo > md.combo_max then md.combo_max = combo end
    refresh_gui(player, data)

    if combo >= 2 then
        player.print({'amap.match3_combo', combo}, {r = 0, g = 1, b = 0})
    end

    -- 胜利判定（失败由框架时间到处理）
    if md.score >= md.target then
        local mul = md.reward_base * (md.score >= md.target * 1.5 and 1.3 or 1.0)
        Instance.set_reward_multiplier(player, mul)
        md.result = 'victory'
        player.print({'amap.match3_win'}, {r = 0, g = 1, b = 0})
        Task.set_timeout_in_ticks(2, delayed_exit_token, {player_index = player.index, reason = 'victory'})
    end
end

--==============================================================================
-- 注册到框架
--==============================================================================

Instance.register(M.type, M)

--==============================================================================
-- 测试用内部 API 暴露
--==============================================================================

_MATCH3_TEST = {
    TILE_CHAR = TILE_CHAR,
    generate_grid = generate_grid,
    find_matches = find_matches,
    count_matches = count_matches,
    apply_matches = apply_matches,
    apply_gravity = apply_gravity,
    resolve_chain = resolve_chain,
    is_adjacent = is_adjacent,
    difficulty_settings = M.difficulty_settings,
}

return M
