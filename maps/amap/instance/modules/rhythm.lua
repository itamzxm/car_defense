-- maps/amap/instance/modules/rhythm.lua
-- 节奏大师玩法模块
--
-- 玩法类型：rhythm
-- 玩法说明：4 轨道下落式音游
--   - GUI 中央 frame，4 列轨道 × 12 行格子（sprite button）
--   - 音符从顶部生成，每 tick 下移一格，到达底部判定线时玩家点击对应轨道按钮
--   - 判定窗口：±2 tick = Perfect（+10），±4 tick = Good（+5），超出 = Miss
--   - 60 秒内累计得分达标即可获胜
--   - 难度差异：音符生成间隔 / 目标分数
--
-- 重要：节奏大师自己注册 on_nth_tick(30) 独立调度，不依赖框架 60 tick on_tick
--   原因：框架 on_tick 每 60 tick 调一次，若 FALL_TICKS_PER_ROW=30 会一次跨 2 行
--   独立 30 tick 调度 + FALL_TICKS_PER_ROW=30 = 每次调度下落一格

local Instance = require 'maps.amap.instance.instance'
local Event = require 'utils.event'

local M = {}

--==============================================================================
-- 元数据
--==============================================================================

M.type = 'rhythm'
M.display_name_key = 'amap.instance_rhythm_name'
M.description_key = 'amap.instance_rhythm_desc'
M.gameplay_desc_key = 'amap.instance_rhythm_gameplay'
M.victory_condition_key = 'amap.instance_rhythm_victory'
M.icon = 'item/iron-plate'
M.time_limit_default = 5 * 60 * 60  -- 5 分钟

--==============================================================================
-- 难度
--==============================================================================

M.difficulty_settings = {
    easy = {
        name = 'easy',
        recycling_efficiency = 1,
        max_coins = 0,
        display_name_key = 'dungeon_difficulty_easy',
        note_interval = 180,          -- 每 3 秒生成一个音符（30 倍数，配合 30 tick 调度）
        target_score = 100,
        time_limit = 5 * 60 * 60
    },
    normal = {
        name = 'normal',
        recycling_efficiency = 1,
        max_coins = 0,
        display_name_key = 'dungeon_difficulty_normal',
        note_interval = 120,          -- 每 2 秒
        target_score = 200,
        time_limit = 5 * 60 * 60
    },
    hard = {
        name = 'hard',
        recycling_efficiency = 1,
        max_coins = 0,
        display_name_key = 'dungeon_difficulty_hard',
        note_interval = 90,           -- 每 1.5 秒（30 倍数）
        target_score = 300,
        time_limit = 5 * 60 * 60
    }
}

--==============================================================================
-- 常量
--==============================================================================

local LANES = 4                  -- 轨道数
local VISIBLE_ROWS = 12          -- 可见行数（音符下落显示的格子数）
-- 节奏大师独立注册 on_nth_tick(30)，每 30 tick 调度一次
-- FALL_TICKS_PER_ROW = 30：每次调度下落一格（用户要求"一下掉一格"）
local FALL_TICKS_PER_ROW = 30    -- 每下落一行需要 30 tick（0.5 秒）；12 行约 6 秒到判定线
local JUDGE_WINDOW_PERFECT = 60  -- ±1 秒 = Perfect
local JUDGE_WINDOW_GOOD = 120    -- ±2 秒 = Good
local JUDGE_WINDOW_MISS = 180    -- 3 秒未击打 = Miss

-- 扣分常量
local MISS_PENALTY = 5           -- 超时未击打 = -5 分
local WRONG_HIT_PENALTY = 3      -- 乱点 / 空击 = -3 分

-- GUI 元素名
local GUI_FRAME = 'dungeon_rhythm_frame'
local GUI_INFO = 'dungeon_rhythm_info'         -- 得分 / 连击 / 时间
local GUI_TRACKS = 'dungeon_rhythm_tracks'     -- 4 列 × 12 行 table
local GUI_BUTTONS = 'dungeon_rhythm_buttons'   -- 4 个判定按钮
local CELL_PREFIX = 'dungeon_rhythm_cell_'     -- cell_{lane}_{row}
local BTN_PREFIX = 'dungeon_rhythm_btn_'       -- btn_{lane}

-- 轨道颜色（4 列）— 仅用于判定按钮文字，不用于 cell（cell 用 sprite 切换避免共享 style 污染）
local LANE_COLORS = {
    {r = 1, g = 0.4, b = 0.4},    -- 红
    {r = 0.4, g = 1, b = 0.4},    -- 绿
    {r = 0.4, g = 0.6, b = 1},    -- 蓝
    {r = 1, g = 0.8, b = 0.2}     -- 黄
}

-- 4 个轨道对应的音符 sprite（item 图标，颜色各异）
-- 用 sprite 切换显示，避免修改 cell.style.font_color 污染所有 cell
local LANE_SPRITES = {
    'item/iron-ore',    -- lane 1 灰白
    'item/copper-ore',  -- lane 2 橙
    'item/coal',        -- lane 3 黑
    'item/stone',       -- lane 4 棕
}

--==============================================================================
-- 辅助
--==============================================================================

-- 创建主 GUI
local function create_main_gui(player, md)
    local screen = player.gui.screen
    -- 已存在则销毁重建
    if screen[GUI_FRAME] then screen[GUI_FRAME].destroy() end

    local frame = screen.add({
        type = 'frame',
        name = GUI_FRAME,
        caption = {'amap.rhythm_title'},
        direction = 'vertical'
    })
    frame.force_auto_center()

    -- 信息行
    local info = frame.add({
        type = 'label',
        name = GUI_INFO,
        caption = ''
    })
    info.style.font = 'default-bold'
    info.style.font_color = {1, 0.85, 0}

    -- 轨道表（4 列）
    local tracks = frame.add({
        type = 'table',
        name = GUI_TRACKS,
        column_count = LANES
    })
    tracks.style.horizontal_spacing = 2
    tracks.style.vertical_spacing = 2

    -- 创建 4×12 个 sprite-button（用 sprite 切换显示，避免共享 style 污染）
    -- 空格子用 nil sprite（默认），有音符用对应颜色的 sprite
    -- 用 4 种 sprite path 表示 4 个轨道的音符颜色
    for row = 1, VISIBLE_ROWS do
        for lane = 1, LANES do
            local cell = tracks.add({
                type = 'sprite-button',
                name = CELL_PREFIX .. lane .. '_' .. row,
                sprite = '',
                hovered_sprite = '',
                clicked_sprite = '',
                -- 标记底部判定线（最后一行）
                tags = {rhythm_cell = true, lane = lane, row = row},
                mouse_button_filter = {'left'}
            })
            cell.style.minimal_width = 50
            cell.style.minimal_height = 30
            cell.style.maximal_width = 50
            cell.style.maximal_height = 30
            -- 判定线行：用不同底色标识
            if row == VISIBLE_ROWS then
                cell.style = 'slot_button_in_shallow_frame'
            end
        end
    end

    -- 判定按钮行（4 个，对应 4 轨道）
    local btn_flow = frame.add({
        type = 'flow',
        name = GUI_BUTTONS,
        direction = 'horizontal'
    })
    btn_flow.style.horizontal_align = 'center'
    btn_flow.style.horizontally_stretchable = true
    btn_flow.style.top_padding = 6

    for lane = 1, LANES do
        local btn = btn_flow.add({
            type = 'button',
            name = BTN_PREFIX .. lane,
            caption = {'amap.rhythm_lane_btn', lane},
            tags = {rhythm_btn = true, lane = lane},
            mouse_button_filter = {'left'}
        })
        btn.style.minimal_width = 50
        btn.style.maximal_height = 40
        btn.style.font_color = LANE_COLORS[lane]
    end

    -- 提示
    local hint = frame.add({
        type = 'label',
        caption = {'amap.rhythm_hint'}
    })
    hint.style.font = 'default'
    hint.style.font_color = {0.7, 0.7, 0.7}
end

-- 更新轨道显示：把音符按其当前行重绘
-- 关键：用 sprite 字段切换（每个 sprite-button 的 sprite 是独立字段，不共享 style）
local function render_tracks(player, md)
    local frame = player.gui.screen[GUI_FRAME]
    if not frame then return end
    local tracks = frame[GUI_TRACKS]
    if not tracks then return end

    -- 先清空所有 cell 的 sprite
    for row = 1, VISIBLE_ROWS do
        for lane = 1, LANES do
            local cell = tracks[CELL_PREFIX .. lane .. '_' .. row]
            if cell and cell.valid then
                cell.sprite = ''
            end
        end
    end

    -- 绘制每个活跃音符
    -- 音符字段：lane, spawn_tick, judge_tick, judged
    -- 当前行 = floor((tick - spawn_tick) / FALL_TICKS_PER_ROW) + 1
    -- 行号 1 = 顶部，VISIBLE_ROWS = 判定线
    local tick = game.tick
    for _, note in ipairs(md.active_notes) do
        if not note.judged then
            local elapsed = tick - note.spawn_tick
            if elapsed >= 0 then
                local row = math.floor(elapsed / FALL_TICKS_PER_ROW) + 1
                if row >= 1 and row <= VISIBLE_ROWS then
                    local cell = tracks[CELL_PREFIX .. note.lane .. '_' .. row]
                    if cell and cell.valid then
                        cell.sprite = LANE_SPRITES[note.lane]
                    end
                end
            end
        end
    end
end

-- 更新信息栏
local function update_info(player, md)
    local frame = player.gui.screen[GUI_FRAME]
    if not frame then return end
    local info = frame[GUI_INFO]
    if not info then return end

    local remaining_sec = math.max(0, math.floor((md.end_tick - game.tick) / 60))
    info.caption = {'amap.rhythm_info', md.score, md.combo, remaining_sec, md.target_score}
end

-- 生成一个音符
local function spawn_note(md, tick)
    -- 随机选轨道
    local lane = math.random(1, LANES)
    -- judge_tick = 当前 tick + 下落总 tick
    -- 总下落 = VISIBLE_ROWS * FALL_TICKS_PER_ROW（从顶部到判定线）
    local total_fall = (VISIBLE_ROWS - 1) * FALL_TICKS_PER_ROW
    local note = {
        lane = lane,
        spawn_tick = tick,
        judge_tick = tick + total_fall,
        judged = false
    }
    md.active_notes[#md.active_notes + 1] = note
end

-- 击打判定：玩家点击 lane 按钮
local function handle_hit(player, md, lane)
    local tick = game.tick
    -- 在活跃音符中找该 lane 且 judge_tick 最接近当前 tick 的未判定音符
    local best_note = nil
    local best_diff = 999999
    for _, note in ipairs(md.active_notes) do
        if not note.judged and note.lane == lane then
            local diff = math.abs(note.judge_tick - tick)
            if diff < best_diff then
                best_diff = diff
                best_note = note
            end
        end
    end

    if not best_note or best_diff > JUDGE_WINDOW_GOOD then
        -- 乱点 / 空击：连击清零 + 扣分（不低于 0）
        md.combo = 0
        md.score = math.max(0, md.score - WRONG_HIT_PENALTY)
        player.create_local_flying_text({
            text = {'amap.rhythm_miss', -WRONG_HIT_PENALTY},
            position = player.position,
            color = {0.9, 0.3, 0.3}
        })
        return
    end

    -- 命中
    best_note.judged = true
    local judgement, score_add, color
    if best_diff <= JUDGE_WINDOW_PERFECT then
        judgement = 'perfect'
        score_add = 10
        color = {1, 0.85, 0.2}
    else
        judgement = 'good'
        score_add = 5
        color = {0.4, 1, 0.4}
    end
    md.combo = md.combo + 1
    -- 连击加成：每 10 连击 +2 分
    local combo_bonus = math.floor(md.combo / 10) * 2
    score_add = score_add + combo_bonus
    md.score = md.score + score_add

    player.create_local_flying_text({
        text = {'amap.rhythm_' .. judgement, score_add},
        position = player.position,
        color = color
    })
end

-- 清理已判定 / 已 miss 的音符
local function cleanup_notes(md, tick, player)
    for i = #md.active_notes, 1, -1 do
        local note = md.active_notes[i]
        if not note.judged then
            -- 超过 miss 窗口仍未击打 = miss，扣分（不低于 0）
            if tick - note.judge_tick > JUDGE_WINDOW_MISS then
                note.judged = true
                md.combo = 0
                md.miss_count = md.miss_count + 1
                md.score = math.max(0, md.score - MISS_PENALTY)
                if player and player.valid then
                    player.create_local_flying_text({
                        text = {'amap.rhythm_miss', -MISS_PENALTY},
                        position = player.position,
                        color = {0.9, 0.3, 0.3}
                    })
                end
            end
        end
        -- 已判定且超过 judge_tick + 一定时间 → 移除
        if note.judged and tick > note.judge_tick + JUDGE_WINDOW_MISS + 10 then
            table.remove(md.active_notes, i)
        end
    end
end

--==============================================================================
-- 钩子
--==============================================================================

function M.on_surface_init(surface, player, data, difficulty_key)
    local diff = M.difficulty_settings[difficulty_key] or M.difficulty_settings.easy
    local ah = 8  -- 小场地，仅放玩家
    local tiles = {}
    for x = -ah - 1, ah + 1 do
        for y = -ah - 1, ah + 1 do
            tiles[#tiles + 1] = {name = 'grass-1', position = {x, y}}
        end
    end
    surface.set_tiles(tiles)

    -- 外围石墙
    for x = -ah, ah do
        for _, y_offs in ipairs({-ah - 1, ah + 1}) do
            local wall = surface.create_entity({
                name = 'stone-wall', position = {x, y_offs},
                force = player.force, move_stuck_players = true
            })
            if wall then wall.destructible = false; wall.minable_flag = false end
        end
    end
    for y = -ah - 1, ah + 1 do
        for _, x_offs in ipairs({-ah - 1, ah + 1}) do
            local wall = surface.create_entity({
                name = 'stone-wall', position = {x_offs, y},
                force = player.force, move_stuck_players = true
            })
            if wall then wall.destructible = false; wall.minable_flag = false end
        end
    end

    -- 中心出生区
    for x = -1, 1 do
        for y = -1, 1 do
            surface.set_tiles({{name = 'hazard-concrete-left', position = {x, y}}})
        end
    end

    data.module_data = {
        note_interval = diff.note_interval,
        target_score = diff.target_score,
        time_limit = diff.time_limit or M.time_limit_default,
        score = 0,
        combo = 0,
        max_combo = 0,
        miss_count = 0,
        active_notes = {},
        next_note_tick = 0,
        start_tick = 0,
        end_tick = 0,
        finished = false
    }

    data.time_limit = diff.time_limit or M.time_limit_default
    surface.always_day = true
end

function M.on_enter(player, data, difficulty_key)
    local diff = M.difficulty_settings[difficulty_key] or M.difficulty_settings.easy
    local md = data.module_data
    if not md then return end

    md.start_tick = game.tick
    md.end_tick = game.tick + (diff.time_limit or M.time_limit_default)
    -- 首个音符延迟 2 秒（让玩家看到 GUI）
    md.next_note_tick = game.tick + 120

    -- 隐藏框架 coins label
    local top = player.gui.top
    if top['dungeon_coins'] then top['dungeon_coins'].destroy() end

    create_main_gui(player, md)
    player.print({'amap.rhythm_enter', md.target_score}, {r = 0, g = 1, b = 0})
    player.print({'amap.rhythm_hint'}, {r = 1, g = 0.8, b = 0})
end

-- 框架 on_tick（每 60 tick）：节奏大师不在此处理逻辑，仅保留接口
-- 实际逻辑在 rhythm_tick（on_nth_tick 30）中处理
function M.on_tick(player, data)
    -- intentionally empty: 节奏大师用独立 30 tick 调度
end

-- 独立 30 tick 调度：生成音符 + 清理 miss + 渲染 + 达分检测
-- 遍历所有在 rhythm 副本中的玩家
local function rhythm_tick(event)
    local tick = game.tick
    for _, player in pairs(game.players) do
        if player.valid and player.character and player.character.valid then
            local data = Instance.get_data(player.index)
            if data and data.active and data.instance_type == 'rhythm' then
                local md = data.module_data
                if not md or md.finished then goto continue end

                -- 时间到 → 标记完成（check_victory 会处理退出）
                if tick >= md.end_tick then
                    md.finished = true
                    goto continue
                end

                -- 生成新音符
                if tick >= md.next_note_tick then
                    spawn_note(md, tick)
                    md.next_note_tick = tick + md.note_interval
                end

                -- 清理已判定 / miss 的音符
                cleanup_notes(md, tick, player)

                -- 更新最大连击
                if md.combo > md.max_combo then md.max_combo = md.combo end

                -- 达到目标分数 → 立即标记完成胜利
                if md.score >= md.target_score then
                    md.finished = true
                    md.victory = true
                    goto continue
                end

                -- 渲染
                render_tracks(player, md)
                update_info(player, md)

                ::continue::
            end
        end
    end
end

-- 注册独立 30 tick 调度（在模块加载时注册一次）
Event.on_nth_tick(30, rhythm_tick)

function M.check_victory(player, data)
    local md = data.module_data
    if not md then return nil end

    if md.finished then
        if md.score >= md.target_score then
            -- 奖励系数固定 1.0（2026-08-10 用户决策）
            Instance.set_reward_multiplier(player, 1.0)
            return 'victory'
        else
            return 'defeat'
        end
    end

    return nil
end

function M.on_gui_click(player, event)
    local element = event.element
    if not element or not element.valid then return end
    local tags = element.tags
    if not tags then return end

    if tags.rhythm_btn then
        local data = Instance.get_data(player.index)
        if not data or not data.active then return end
        local md = data.module_data
        if not md or md.finished then return end
        handle_hit(player, md, tags.lane)
    end
end

function M.on_exit(player, data, reason)
    local md = data.module_data
    if not md then return end
    local frame = player.gui.screen[GUI_FRAME]
    if frame then frame.destroy() end
end

--==============================================================================
-- 注册
--==============================================================================

Instance.register(M.type, M)
return M
