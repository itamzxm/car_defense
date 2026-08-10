-- maps/amap/instance/modules/whack_a_mole.lua
-- 打地鼠玩法模块（v1）
--
-- 玩法类型：whack_a_mole
-- 玩法说明：经典打地鼠（纯 GUI，无实体）
--   - 玩家进入副本后看到一个小房间（草地+石墙围边）和一块打地鼠网格面板
--   - 老鼠会从随机洞里冒出并停留短暂时间，点击冒鼠的洞得分
--   - 普通鼠 +1 分，金色鼠（15% 概率）+5 分，点到空洞 -1 分
--   - 停留超时未点掉视为漏打：仅困难难度漏打计数，漏满 12 只立即失败
--   - 目标：倒计时结束前得分达到目标分
--
-- 难度分级：
--   easy   - 4×4 网格 - 出鼠间隔 1.2 秒 - 目标 30 分 - 90 秒 - 奖励系数 1.0
--   normal - 4×4 网格 - 出鼠间隔 0.8 秒 - 目标 60 分 - 60 秒 - 奖励系数 1.5
--   hard   - 5×5 网格 - 出鼠间隔 0.6 秒 - 目标 100 分 - 60 秒 - 奖励系数 2.0（漏打上限 12）
--
-- 玩法私有状态全部放在 data.module_data（holes 表 / score / missed / next_spawn_tick 等）
-- 场上同时最多 3 只老鼠，每次出鼠随机 1~2 只，停留时间随机 0.8~2 秒
-- GUI 更新只改变化格的 caption/style，不重建整个 GUI
--
-- 钩子实现：
--   on_surface_init - 生成草地小房间 + 外围石墙 + 玩家初始位置 + 初始化难度私有数据
--   on_enter        - 隐藏框架金币 label + 创建打地鼠 GUI + 提示玩法
--   on_exit         - 销毁打地鼠 GUI
--   on_fast_tick    - 冒鼠调度 + 停留超时消失（漏打计数）
--   on_gui_click    - 点洞判定：普通鼠 +1 / 金鼠 +5 / 空洞 -1
--   check_victory   - 倒计时结束达目标分 → 胜利（含溢出加分）；未达标 → 失败；hard 漏满 → 失败
--
-- 倒计时说明：框架仅在 remaining>0 时调用 check_victory，因此这里给 data.time_limit
-- 附加 3 秒（180 tick）宽限（参照 dodgeball.lua），玩法实际倒计时为 md.countdown_ticks，
-- 保证 check_victory 在 remaining>0 窗口内当帧返回 victory/defeat，不会被框架 timeout 抢先判负。

local Instance = require 'maps.amap.instance.instance'

local M = {}

--==============================================================================
-- 元数据
--==============================================================================

M.type = 'whack_a_mole'
M.display_name_key = 'amap.instance_whack_a_mole_name'
M.description_key = 'amap.instance_whack_a_mole_desc'
M.gameplay_desc_key = 'amap.instance_whack_a_mole_gameplay'
M.victory_condition_key = 'amap.instance_whack_a_mole_victory'
M.icon = 'item/steel-axe'
M.time_limit_default = 60 * 60

--==============================================================================
-- 难度设置
--==============================================================================
-- 私有字段（grid_size / target_score / spawn_interval / miss_limit）进入时从 data.difficulty 取
-- spawn_interval 单位 tick（60 tick = 1 秒）

M.difficulty_settings = {
    easy = {
        name = "easy",
        recycling_efficiency = 1, max_coins = 0,
        display_name_key = "dungeon_difficulty_easy",
        grid_size = 4,
        spawn_interval = 72,       -- 1.2 秒
        target_score = 30,
        time_limit = 5400,         -- 90 秒
        reward_multiplier = 1.0,
        miss_limit = nil,          -- 不计数漏打
    },
    normal = {
        name = "normal",
        recycling_efficiency = 1, max_coins = 0,
        display_name_key = "dungeon_difficulty_normal",
        grid_size = 4,
        spawn_interval = 48,       -- 0.8 秒
        target_score = 60,
        time_limit = 3600,         -- 60 秒
        reward_multiplier = 1.5,
        miss_limit = nil,          -- 不计数漏打
    },
    hard = {
        name = "hard",
        recycling_efficiency = 1, max_coins = 0,
        display_name_key = "dungeon_difficulty_hard",
        grid_size = 5,
        spawn_interval = 36,       -- 0.6 秒
        target_score = 100,
        time_limit = 3600,         -- 60 秒
        reward_multiplier = 2.0,
        miss_limit = 12,           -- 漏打上限：满 12 立即失败
    },
}

--==============================================================================
-- GUI 元素名常量（前缀 dungeon_module_wam_ 防冲突）
--==============================================================================

local GUI_WAM_FRAME = 'dungeon_module_wam_main_frame'
local GUI_WAM_STATUS = 'dungeon_module_wam_status'
local GUI_WAM_GOLD_HINT = 'dungeon_module_wam_gold_hint'
local GUI_WAM_BOARD = 'dungeon_module_wam_board'
local CELL_PREFIX = 'dungeon_module_wam_cell_'

-- 洞格按钮尺寸
local CELL_SIZE = 56

--==============================================================================
-- 玩法参数常量
--==============================================================================

local MAX_ACTIVE = 3        -- 场上同时最多 3 只老鼠
local GOLD_CHANCE = 0.15    -- 金鼠概率 15%
local STAY_MIN = 48         -- 停留 0.8 秒（tick）
local STAY_MAX = 120        -- 停留 2 秒（tick）
local TIMEOUT_GRACE = 180   -- 框架超时宽限 3 秒（参照 dodgeball.lua）

--==============================================================================
-- 洞格显示样式
--==============================================================================

local MOLE_COLOR = {0.85, 0.55, 0.3}    -- 普通鼠（棕橙色）
local GOLD_COLOR = {1, 0.84, 0}         -- 金鼠（金色）
local EMPTY_COLOR = {0.35, 0.35, 0.35}  -- 空洞

--==============================================================================
-- 辅助函数
--==============================================================================

-- 初始化 holes 表：grid_size × grid_size，key 为 "row_col"
local function holes_init(grid_size)
    local holes = {}
    for r = 1, grid_size do
        for c = 1, grid_size do
            holes[r .. '_' .. c] = {
                active = false,      -- 是否有鼠
                kind = 'normal',     -- 'normal' / 'gold'
                born_tick = 0,       -- 冒鼠时刻
                stay_ticks = 0,      -- 停留时长（tick）
                last_shown = 0,      -- 上次显示/消失时刻（信息用途）
            }
        end
    end
    return holes
end

-- 收集所有空洞 key
local function empty_holes(md)
    local out = {}
    for key, hole in pairs(md.holes) do
        if not hole.active then
            out[#out + 1] = key
        end
    end
    return out
end

-- 更新单个洞格的 caption/style（只改动变化格，不重建 GUI）
local function set_cell_display(board, key, hole)
    if not (board and board.valid) then return end
    local btn = board[CELL_PREFIX .. key]
    if not (btn and btn.valid) then return end
    if hole.active then
        btn.caption = '鼠'
        if hole.kind == 'gold' then
            btn.style.font = 'default-bold'
            btn.style.font_color = GOLD_COLOR
        else
            btn.style.font = 'default'
            btn.style.font_color = MOLE_COLOR
        end
    else
        btn.caption = ''
        btn.style.font = 'default'
        btn.style.font_color = EMPTY_COLOR
    end
end

-- 刷新顶部状态行（得分 / 目标 / 漏打数）
local function refresh_status(player, md)
    local frame = player.gui.screen[GUI_WAM_FRAME]
    if not (frame and frame.valid) then return end
    local status = frame[GUI_WAM_STATUS]
    if not (status and status.valid) then return end
    if md.miss_limit then
        status.caption = {'', {'amap.wam_score', md.score}, '    ',
                           {'amap.wam_target', md.target_score}, '    ',
                           {'amap.wam_missed', md.missed, md.miss_limit}}
    else
        status.caption = {'', {'amap.wam_score', md.score}, '    ',
                           {'amap.wam_target', md.target_score}}
    end
end

--==============================================================================
-- GUI 创建
--==============================================================================

local function create_main_gui(player, md)
    local screen = player.gui.screen
    if screen[GUI_WAM_FRAME] then
        screen[GUI_WAM_FRAME].destroy()
    end

    local frame = screen.add({
        type = 'frame',
        name = GUI_WAM_FRAME,
        caption = {'amap.wam_title', {'amap.' .. md.difficulty_label_key}},
        direction = 'vertical'
    })
    frame.force_auto_center()
    frame.style.minimal_width = md.grid_size * CELL_SIZE + 40
    frame.style.maximal_width = md.grid_size * CELL_SIZE + 80

    -- 顶部状态行：得分 / 目标 / 漏打数
    local status = frame.add({
        type = 'label',
        name = GUI_WAM_STATUS,
        caption = ''
    })
    status.style.font = 'default-bold'
    status.style.font_color = {1, 0.84, 0}

    -- 金鼠提示
    local gold_hint = frame.add({
        type = 'label',
        name = GUI_WAM_GOLD_HINT,
        caption = {'amap.wam_gold_hint'}
    })
    gold_hint.style.font = 'default'
    gold_hint.style.font_color = GOLD_COLOR

    -- 洞网格
    local board = frame.add({
        type = 'table',
        name = GUI_WAM_BOARD,
        column_count = md.grid_size
    })
    board.style.horizontal_spacing = 2
    board.style.vertical_spacing = 2
    board.style.top_padding = 4
    board.style.bottom_padding = 4

    for r = 1, md.grid_size do
        for c = 1, md.grid_size do
            local btn = board.add({
                type = 'button',
                name = CELL_PREFIX .. r .. '_' .. c,
                caption = '',
                mouse_button_filter = {'left'}
            })
            btn.style.minimal_width = CELL_SIZE
            btn.style.minimal_height = CELL_SIZE
            btn.style.maximal_width = CELL_SIZE
            btn.style.maximal_height = CELL_SIZE
            btn.style.font_color = EMPTY_COLOR
        end
    end

    -- 玩法提示
    local hint = frame.add({
        type = 'label',
        caption = {'amap.wam_hint'}
    })
    hint.style.font = 'default'
    hint.style.font_color = {0.7, 0.7, 0.7}
    hint.style.single_line = false
    hint.style.maximal_width = md.grid_size * CELL_SIZE + 40
end

--==============================================================================
-- 钩子实现
--==============================================================================

function M.on_surface_init(surface, player, data, difficulty)
    local diff = M.difficulty_settings[difficulty] or M.difficulty_settings.easy

    -- 玩法私有状态（全部放 data.module_data）
    data.module_data = {
        grid_size = diff.grid_size,
        spawn_interval = diff.spawn_interval,
        target_score = diff.target_score,
        miss_limit = diff.miss_limit,
        reward_multiplier = diff.reward_multiplier,
        countdown_ticks = diff.time_limit or M.time_limit_default,
        difficulty = difficulty,
        difficulty_label_key = diff.display_name_key,
        holes = holes_init(diff.grid_size),
        score = 0,
        missed = 0,
        next_spawn_tick = 0,
        failed = false,
    }

    -- 框架超时 = 玩法倒计时 + 3 秒宽限，保证 check_victory 在 remaining>0 窗口内判定
    data.time_limit = (diff.time_limit or M.time_limit_default) + TIMEOUT_GRACE

    -- 1. 全图铺 grass-1
    for x = -50, 50 do
        for y = -50, 50 do
            surface.set_tiles{{name = "grass-1", position = {x, y}}}
        end
    end

    -- 2. 外围石墙围成小房间
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

    surface.always_day = true
    player.force.chart(surface, {
        {-room_half - 2, -room_half - 2},
        {room_half + 2, room_half + 2}
    })
end

function M.on_enter(player, data, difficulty)
    player.force.manual_mining_speed_modifier = 0

    local top = player.gui.top
    if top['dungeon_coins'] then top['dungeon_coins'].destroy() end

    local md = data.module_data
    if md then
        md.next_spawn_tick = game.tick + md.spawn_interval
    end

    create_main_gui(player, md)
    refresh_status(player, md)

    if md then
        player.print({'amap.wam_enter', md.grid_size, md.target_score}, {r = 0, g = 1, b = 0})
    end
    player.print({'amap.wam_hint'}, {r = 1, g = 1, b = 0})
end

function M.on_exit(player, data, reason)
    local screen = player.gui.screen
    if screen[GUI_WAM_FRAME] then
        screen[GUI_WAM_FRAME].destroy()
    end
end

-- 每 5 tick：冒鼠调度 + 停留超时消失（漏打计数）
function M.on_fast_tick(player, data)
    local md = data.module_data
    if not md then return end
    local tick = game.tick

    local screen = player.gui.screen
    local frame = screen[GUI_WAM_FRAME]
    local board = nil
    if frame and frame.valid then
        board = frame[GUI_WAM_BOARD]
        if not (board and board.valid) then board = nil end
    end

    local countdown_over = tick - data.start_tick >= md.countdown_ticks

    -- 1. 冒鼠：间隔到且未到倒计时结束 → 随机 1~2 只（场上最多 3 只）
    if not countdown_over and tick >= md.next_spawn_tick then
        local active_count = 0
        local candidates = {}
        for _, hole in pairs(md.holes) do
            if hole.active then
                active_count = active_count + 1
            end
        end
        if active_count < MAX_ACTIVE then
            for key, hole in pairs(md.holes) do
                if not hole.active then
                    candidates[#candidates + 1] = key
                end
            end
            local to_spawn = math.min(math.random(1, 2), MAX_ACTIVE - active_count, #candidates)
            for _ = 1, to_spawn do
                if #candidates == 0 then break end
                local idx = math.random(#candidates)
                local key = candidates[idx]
                table.remove(candidates, idx)
                local hole = md.holes[key]
                hole.active = true
                hole.kind = (math.random() < GOLD_CHANCE) and 'gold' or 'normal'
                hole.born_tick = tick
                hole.stay_ticks = math.random(STAY_MIN, STAY_MAX)
                hole.last_shown = tick
                set_cell_display(board, key, hole)
            end
            md.next_spawn_tick = tick + md.spawn_interval
        end
    end

    -- 2. 停留超时 → 消失（漏打；hard 计数，>= 上限立即标记失败）
    local status_changed = false
    for key, hole in pairs(md.holes) do
        if hole.active and tick - hole.born_tick >= hole.stay_ticks then
            hole.active = false
            hole.last_shown = tick
            set_cell_display(board, key, hole)
            if md.miss_limit then
                md.missed = md.missed + 1
                status_changed = true
                if md.missed >= md.miss_limit then
                    md.failed = true
                end
            end
        end
    end
    if status_changed then
        refresh_status(player, md)
    end
end

function M.check_victory(player, data)
    local md = data.module_data
    if not md then return nil end

    -- hard 漏打满上限：立即失败
    if md.failed then return 'defeat' end

    -- 玩法倒计时结束（框架 data.time_limit 已含宽限，本分支在 remaining>0 窗口内执行）
    if game.tick - data.start_tick >= md.countdown_ticks then
        if md.score >= md.target_score then
            -- 奖励系数固定 1.0（2026-08-10 用户决策）
            Instance.set_reward_multiplier(player, 1.0)
            return 'victory'
        end
        return 'defeat'
    end

    return nil
end

function M.on_gui_click(player, event)
    local element = event.element
    if not element or not element.valid then return end

    local name = element.name
    if not name then return end
    if string.sub(name, 1, #CELL_PREFIX) ~= CELL_PREFIX then return end

    local data = Instance.get_data(player.index)
    if not data or not data.active then return end
    local md = data.module_data
    if not md then return end

    local row_str, col_str = string.match(name, CELL_PREFIX .. '(%d+)_(%d+)')
    if not row_str then return end
    local key = row_str .. '_' .. col_str
    local hole = md.holes[key]
    if not hole then return end

    -- 点洞判定：普通鼠 +1 / 金鼠 +5 / 空洞 -1
    if hole.active then
        if hole.kind == 'gold' then
            md.score = md.score + 5
            player.print({'amap.wam_hit_gold'}, {r = 1, g = 0.84, b = 0})
        else
            md.score = md.score + 1
        end
        hole.active = false
        hole.last_shown = game.tick
    else
        md.score = md.score - 1
        player.print({'amap.wam_empty'}, {r = 0.6, g = 0.6, b = 0.6})
    end

    -- 只更新被点击的洞格 + 刷新状态行
    local frame = player.gui.screen[GUI_WAM_FRAME]
    if frame and frame.valid then
        local board = frame[GUI_WAM_BOARD]
        if board and board.valid then
            set_cell_display(board, key, hole)
        end
    end
    refresh_status(player, md)
end

--==============================================================================
-- 注册到框架
--==============================================================================

Instance.register(M.type, M)

return M
