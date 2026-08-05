-- maps/amap/instance/modules/qiuheti.lua
-- 求合体玩法模块（Merge-3 / Sanlitun）
--
-- 玩法类型：qiuheti
-- 玩法说明：Triple Town 式放置合成解谜
--   - 纯 GUI 面板玩法（参考 sudoku / merge2048 骨架）
--   - 顶部显示「待放物品」（含偶发炸弹），玩家点一个空地格放下
--   - 放下后从落子格做 4 邻接同层级连通簇搜索：
--       * 簇大小 ≥ 3 → 全部清除，在落子格生成「层级+1」物品（可连锁合体）
--       * 斜向不算相邻（严格 4 邻接）
--   - 炸弹：只能作用于已有物品的格子（清除该格，腾出空间）
--   - 棋盘出现 ≥ 目标层级物品 → 胜利
--   - 棋盘填满且 next 不是炸弹 → 失败
--
-- 难度分级（仅目标层级差异，棋盘统一 6x6，时间分级递减）：
--   easy   - 6x6 - 目标 tier 4 (草屋)   - 18 分钟 - 奖励系数 1.0
--   normal - 6x6 - 目标 tier 5 (房子)   - 15 分钟 - 奖励系数 1.5
--   hard   - 6x6 - 目标 tier 6 (马戏团) - 12 分钟 - 奖励系数 2.0
--
-- 钩子实现：
--   on_surface_init - 生成草地小房间 + 外围石墙 + 初始化棋盘与待放队列
--   on_enter        - 隐藏框架金币 label + 创建主 GUI + 提示玩法
--   on_exit         - 销毁主 GUI
--   on_tick         - 静态游戏，无需操作
--   check_victory   - 返回 md.result（终局由 on_gui_click 经延迟退出设置）
--   on_gui_click    - 格子点击 → 放物品 / 放炸弹 → 刷新 → 判定胜负

local Instance = require 'maps.amap.instance.instance'
local Token = require 'utils.token'
local Task = require 'utils.task'

local M = {}

--==============================================================================
-- 元数据
--==============================================================================

M.type = 'qiuheti'
M.display_name_key = 'amap.instance_qiuheti_name'
M.description_key = 'amap.instance_qiuheti_desc'
M.gameplay_desc_key = 'amap.instance_qiuheti_gameplay'
M.victory_condition_key = 'amap.instance_qiuheti_victory'
M.icon = 'item/wood'  -- 木头图标（与草系合成起点呼应）
M.time_limit_default = 18 * 60 * 60

--==============================================================================
-- 难度设置
--==============================================================================

M.difficulty_settings = {
    easy = {
        name = "easy",
        recycling_efficiency = 1,
        max_coins = 0,
        display_name_key = "dungeon_difficulty_easy",
        size = 6,                        -- 6x6 棋盘
        target = 4,                      -- 草屋
        target_score_base = 800,         -- 表现缩放基准
        time_limit = 18 * 60 * 60,       -- 18 分钟
        reward_multiplier = 1.0
    },
    normal = {
        name = "normal",
        recycling_efficiency = 1,
        max_coins = 0,
        display_name_key = "dungeon_difficulty_normal",
        size = 6,
        target = 5,                      -- 房子
        target_score_base = 1800,
        time_limit = 15 * 60 * 60,
        reward_multiplier = 1.0
    },
    hard = {
        name = "hard",
        recycling_efficiency = 1,
        max_coins = 0,
        display_name_key = "dungeon_difficulty_hard",
        size = 6,                        -- 6x6 棋盘（全难度统一）
        target = 6,                      -- 马戏团
        target_score_base = 3600,
        time_limit = 12 * 60 * 60,
        reward_multiplier = 1.0
    }
}

--==============================================================================
-- GUI 元素名常量（前缀 dungeon_module_ 防冲突）
--==============================================================================

local GUI_FRAME      = 'dungeon_module_qiuheti_main_frame'
local GUI_STATUS     = 'dungeon_module_qiuheti_status'
local GUI_GRID       = 'dungeon_module_qiuheti_grid'
local GUI_NEXT_LABEL = 'dungeon_module_qiuheti_next_label'
local CELL_PREFIX    = 'dungeon_module_qiuheti_cell_'

--==============================================================================
-- 层级配色与名称
--==============================================================================
-- 10 级路线：1 草 → 2 灌木 → 3 大树 → 4 草屋 → 5 房子 → 6 马戏团
--          → 7 宫殿 → 8 金字塔 → 9 光之塔 → 10 神迹
-- 每级一种主色（黑底亮色），1 个中文字符作 sprite-button caption

local TIER_COLOR = {
    [1]  = {0.30, 0.85, 0.30},  -- 草 绿
    [2]  = {0.20, 0.60, 0.20},  -- 灌木 深绿
    [3]  = {0.50, 0.40, 0.20},  -- 大树 棕
    [4]  = {0.80, 0.60, 0.30},  -- 草屋 黄褐
    [5]  = {0.95, 0.55, 0.20},  -- 房子 橙
    [6]  = {0.95, 0.30, 0.50},  -- 马戏团 粉红
    [7]  = {0.75, 0.30, 0.95},  -- 宫殿 紫
    [8]  = {0.95, 0.85, 0.20},  -- 金字塔 金黄
    [9]  = {0.30, 0.85, 0.95},  -- 光之塔 青蓝
    [10] = {1.00, 1.00, 1.00},  -- 神迹 白
}

local TIER_CHAR = {
    [1]  = '草', [2]  = '灌', [3]  = '树', [4]  = '屋',
    [5]  = '房', [6]  = '戏', [7]  = '宫', [8]  = '塔',
    [9]  = '光', [10] = '神',
}

local BOMB_CHAR = '炸'
local BOMB_COLOR = {1, 0.2, 0.2}

-- 各层级产出得分（×3 递增，对应 tier 索引）
local SCORE = {0, 10, 30, 90, 270, 810, 2430, 7290, 21870, 65610, 196830}

-- 物品刷新权重（草 70% / 灌木 20% / 大树 8% / 炸弹 2%）
local WEIGHTS = {
    {tier = 1,    w = 70},
    {tier = 2,    w = 20},
    {tier = 3,    w = 8},
    {tier = 'bomb', w = 2},
}
local WEIGHT_TOTAL = 100

--==============================================================================
-- 辅助函数
--==============================================================================

-- 按权重随机生成下一个物品（tier 数字 或 'bomb'）
local function roll_next()
    local r = math.random(WEIGHT_TOTAL)
    local acc = 0
    for _, e in ipairs(WEIGHTS) do
        acc = acc + e.w
        if r <= acc then return e.tier end
    end
    return 1  -- 兜底
end

-- 4 邻接偏移（上下左右，严格不含斜向）
local NEIGHBOR4 = {{0, -1}, {0, 1}, {-1, 0}, {1, 0}}

-- 从 (sr, sc) 出发做 4 邻接同层级连通簇（BFS），返回簇内格列表
local function connected_component(md, sr, sc, tier)
    local seen, comp, q = {}, {}, {{r = sr, c = sc}}
    seen[sr .. '_' .. sc] = true
    while #q > 0 do
        local cur = table.remove(q, 1)
        comp[#comp + 1] = cur
        for _, d in ipairs(NEIGHBOR4) do
            local nr, nc = cur.r + d[1], cur.c + d[2]
            local key = nr .. '_' .. nc
            if nr >= 1 and nr <= md.size
               and nc >= 1 and nc <= md.size
               and not seen[key]
               and md.grid[nr][nc] == tier then
                seen[key] = true
                q[#q + 1] = {r = nr, c = nc}
            end
        end
    end
    return comp
end

-- 从落子格 (r,c) 起反复结算合体（连锁）
-- 每次只升 1 级并在同一格落下，天然收敛（层级有上限 10）
local function resolve_merges(md, r, c)
    -- 连锁上限保护（10 级 × 一次升 1 级 = 最多 10 次连锁，留余量到 64）
    for _ = 1, 64 do
        local tier = md.grid[r][c]
        if tier == 0 or tier >= 10 then return end
        local comp = connected_component(md, r, c, tier)
        if #comp < 3 then return end
        for _, cell in ipairs(comp) do
            md.grid[cell.r][cell.c] = 0
        end
        md.grid[r][c] = tier + 1
        md.score = md.score + SCORE[tier + 1]
    end
end

-- 从队列补一个新物品到 next
local function pop_queue(md)
    if #md.queue > 0 then
        return table.remove(md.queue, 1)
    end
    return roll_next()
end

-- 放普通物品（仅空地）
local function place(md, r, c)
    if md.grid[r][c] ~= 0 then return false end
    md.grid[r][c] = md.next
    md.next = pop_queue(md)
    resolve_merges(md, r, c)
    return true
end

-- 放炸弹（仅作用于有物格，清除该格）
local function place_bomb(md, r, c)
    if md.grid[r][c] == 0 then return false end
    md.grid[r][c] = 0
    md.next = pop_queue(md)
    return true
end

-- 当前棋盘最高层级
local function max_tier(md)
    local m = 0
    for r = 1, md.size do
        for c = 1, md.size do
            if md.grid[r][c] > m then m = md.grid[r][c] end
        end
    end
    return m
end

-- 棋盘是否有空格
local function has_empty(md)
    for r = 1, md.size do
        for c = 1, md.size do
            if md.grid[r][c] == 0 then return true end
        end
    end
    return false
end

--==============================================================================
-- GUI 创建 / 刷新
--==============================================================================

local function cell_caption(v)
    if v == 0 then return '' end
    if v == 'bomb' then return BOMB_CHAR end
    return TIER_CHAR[v] or '?'
end

local function cell_color(v)
    if v == 0 then return nil end
    if v == 'bomb' then return BOMB_COLOR end
    return TIER_COLOR[v] or {1, 1, 1}
end

local function create_main_gui(player, data)
    local screen = player.gui.screen
    if screen[GUI_FRAME] then screen[GUI_FRAME].destroy() end
    local md = data.module_data
    local size = md.size

    local frame = screen.add({
        type = 'frame',
        name = GUI_FRAME,
        caption = {'amap.qiuheti_main_caption', {'amap.' .. md.difficulty_label_key}},
        direction = 'vertical'
    })
    frame.force_auto_center()
    frame.style.minimal_width = size * 56 + 60

    -- 顶栏状态 label
    local status = frame.add({type = 'label', name = GUI_STATUS, caption = ''})
    status.style.font = 'heading-2'
    status.style.font_color = {1, 0.84, 0}
    status.style.top_padding = 4
    status.style.bottom_padding = 4

    -- 合成顺序（从小到大，全名；静态 chain_tiers 键，避免嵌套数组超 20 参数限制）
    local chain = frame.add({type = 'label', name = GUI_GRID .. '_chain',
        caption = {'amap.qiuheti_chain_label', {'amap.qiuheti_tier_' .. md.target}, {'amap.qiuheti_chain_tiers'}}})
    chain.style.font = 'heading-2'
    chain.style.font_color = {0.702, 0.702, 0.702}  -- #B3B3B3，弱化合成顺序提示
    chain.style.top_padding = 4
    chain.style.bottom_padding = 4

    -- 棋盘网格
    local grid_table = frame.add({
        type = 'table',
        name = GUI_GRID,
        column_count = size
    })
    grid_table.style.horizontal_spacing = 4
    grid_table.style.vertical_spacing = 4
    grid_table.style.top_padding = 4
    grid_table.style.bottom_padding = 4

    local cell_size = 48
    for r = 1, size do
        for c = 1, size do
            local v = md.grid[r][c]
            local btn = grid_table.add({
                type = 'button',
                name = CELL_PREFIX .. r .. '_' .. c,
                caption = cell_caption(v),
                tags = {qiuheti_cell = true, r = r, c = c},
                mouse_button_filter = {'left'}
            })
            btn.style.minimal_width = cell_size
            btn.style.minimal_height = cell_size
            btn.style.maximal_width = cell_size
            btn.style.maximal_height = cell_size
            btn.style.font = 'heading-1'
            btn.style.font_color = {0, 0, 0}  -- 统一黑色字体
            btn.style.horizontal_align = 'center'
            btn.style.vertical_align = 'center'
            btn.style.top_padding = 0
            btn.style.bottom_padding = 0
            btn.style.left_padding = 0
            btn.style.right_padding = 0
        end
    end

    -- 待放区
    local next_label = frame.add({type = 'label', name = GUI_NEXT_LABEL, caption = ''})
    next_label.style.font = 'heading-2'
    next_label.style.font_color = {0.702, 0.702, 0.702}  -- #B3B3B3，弱化待放提示
    next_label.style.top_padding = 6

    -- 提示
    local hint = frame.add({type = 'label', caption = {'amap.qiuheti_hint'}})
    hint.style.font = 'default'
    hint.style.font_color = {0.7, 0.7, 0.7}
    hint.style.single_line = false
    hint.style.maximal_width = size * 56 + 40
end

local function refresh_gui(player, data)
    local screen = player.gui.screen
    local frame = screen[GUI_FRAME]
    if not frame or not frame.valid then return end
    local md = data.module_data
    local size = md.size

    -- 状态 label：得分 · 目标 · 下一个
    local status = frame[GUI_STATUS]
    if status and status.valid then
        local next_str
        if md.next == 'bomb' then
            next_str = {'amap.qiuheti_bomb'}
        else
            next_str = TIER_CHAR[md.next] or '?'
        end
        status.caption = {'amap.qiuheti_status', md.score, md.target, next_str}
    end

    -- 待放区
    local next_label = frame[GUI_NEXT_LABEL]
    if next_label and next_label.valid then
        local v = md.next
        next_label.caption = {'amap.qiuheti_next_label', cell_caption(v)}
        next_label.style.font_color = {0.702, 0.702, 0.702}  -- #B3B3B3，弱化待放提示
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
                btn.style.font_color = {0, 0, 0}  -- 统一黑色字体
            end
        end
    end
end

--==============================================================================
-- 钩子实现
--==============================================================================

function M.on_surface_init(surface, player, data, difficulty)
    local diff = M.difficulty_settings[difficulty] or M.difficulty_settings.easy
    local size = diff.size

    local grid = {}
    for r = 1, size do
        grid[r] = {}
        for c = 1, size do grid[r][c] = 0 end
    end

    data.module_data = {
        size = size,
        grid = grid,
        next = roll_next(),
        queue = {roll_next(), roll_next(), roll_next()},  -- 预览队列 3 个
        score = 0,
        target = diff.target,
        target_score_base = diff.target_score_base,
        reward_base = diff.reward_multiplier,
        result = nil,
        difficulty_label_key = diff.display_name_key,
    }
    data.time_limit = diff.time_limit or M.time_limit_default

    -- 1. 全图铺 grass-1（视觉清爽）
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
        player.print({'amap.qiuheti_enter', target_name, {'amap.' .. md.difficulty_label_key}}, {r = 0, g = 1, b = 0})
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

-- 延迟退出（避免在 GUI 事件 handler 内直接销毁 surface/character）
local function delayed_exit(params)
    local player = game.players[params.player_index]
    if not player or not player.valid then return end
    Instance.exit(player, params.reason)
end
local delayed_exit_token = Token.register(delayed_exit)

function M.on_gui_click(player, event)
    local element = event.element
    if not element or not element.valid then return end

    local data = Instance.get_data(player.index)
    if not data or not data.active then return end
    local md = data.module_data
    if not md then return end
    if md.result then return end

    local tags = element.tags or {}
    if not tags.qiuheti_cell then return end
    local r = tags.r
    local c = tags.c
    if type(r) ~= 'number' or type(c) ~= 'number' then return end
    if r < 1 or r > md.size or c < 1 or c > md.size then return end

    local ok
    if md.next == 'bomb' then
        ok = place_bomb(md, r, c)
    else
        ok = place(md, r, c)
    end
    if not ok then
        player.print({'amap.qiuheti_invalid'}, {r = 1, g = 1, b = 0})
        return
    end
    refresh_gui(player, data)

    -- 判定胜负
    if max_tier(md) >= md.target then
        local mult = md.reward_base * (md.score > md.target_score_base * 1.5 and 1.2 or 1.0)
        Instance.set_reward_multiplier(player, mult)
        md.result = 'victory'
        local target_name = TIER_CHAR[md.target] or '?'
        player.print({'amap.qiuheti_win', target_name}, {r = 0, g = 1, b = 0})
        Task.set_timeout_in_ticks(2, delayed_exit_token, {player_index = player.index, reason = 'victory'})
    elseif not has_empty(md) and md.next ~= 'bomb' then
        md.result = 'defeat'
        player.print({'amap.qiuheti_lose'}, {r = 1, g = 0, b = 0})
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
-- Factorio 运行时 (/c 命令) 禁止 require，但可以访问全局变量。
-- 这里把内部纯逻辑函数暴露为全局 _QIUHETI_TEST，供 RCON 测试调用，
-- 验证连通簇搜索 / 合体 / 炸弹 / 胜负判定等纯逻辑是否正确（参考 副本添加说明.md §10）。
-- 生产环境无副作用（无人调用即不执行）。

_QIUHETI_TEST = {
    SCORE = SCORE,
    WEIGHTS = WEIGHTS,
    roll_next = roll_next,
    connected_component = connected_component,
    resolve_merges = resolve_merges,
    pop_queue = pop_queue,
    place = place,
    place_bomb = place_bomb,
    max_tier = max_tier,
    has_empty = has_empty,
    difficulty_settings = M.difficulty_settings,
}

return M
