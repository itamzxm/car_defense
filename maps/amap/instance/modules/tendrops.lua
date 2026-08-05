-- maps/amap/instance/modules/tendrops.lua
-- 十滴水玩法模块（Ten Drops）
--
-- 玩法类型：tendrops
-- 玩法说明：水滴连锁爆破解谜
--   - 纯 GUI 面板玩法（参考 sudoku 骨架 + minesweeper 逐波处理）
--   - 方格阵上每格存水滴等级 0(空)..4(满级)
--   - 玩家点有水滴的格 → 该水滴升 1 级；消耗 1 滴水额度
--   - 若该格原已满级（4）被点 → 爆裂：该格变空，向上下左右 4 邻各溅 1 滴水
--   - 溅射命中邻格：
--       * 邻格为空 → 飞溅消失（无效果）
--       * 邻格 L<4 → 升为 L+1 级
--       * 邻格 4 → 连锁爆裂（同样向它的 4 邻溅射），加入本波处理队列
--   - 连锁以「波」为单位结算（on_tick 逐波推进，便于玩家观察）
--   - 本波爆裂总数 ≥3 → +1 滴水；≥6 → +2；≥9 → +3（上限 +3）
--   - 所有格变空 → 胜利；额度=0 且仍有水滴残留 → 失败
--
-- 难度分级（仅网格与额度差异，时间分级递减）：
--   easy   - 5x5 - 14 滴 - 18 分钟 - 奖励系数 1.0
--   normal - 6x6 - 10 滴 - 15 分钟 - 奖励系数 1.5
--   hard   - 7x7 -  8 滴 - 12 分钟 - 奖励系数 2.0
--
-- 钩子实现：
--   on_surface_init - 生成草地小房间 + 外围石墙 + 初始化随机 1-3 级水滴方格
--   on_enter        - 隐藏框架金币 label + 创建主 GUI + 提示玩法
--   on_exit         - 销毁主 GUI + 清空 burst_queue
--   on_tick         - 连锁波逐波推进（每波 ~6 tick 间隔），波空即空闲
--   check_victory   - 全空→胜利（设系数）；额度耗尽且无连锁→失败
--   on_gui_click    - 格子点击 → 扣额度 → click_drop 启动连锁

local Instance = require 'maps.amap.instance.instance'
local Token = require 'utils.token'
local Task = require 'utils.task'

local M = {}

--==============================================================================
-- 元数据
--==============================================================================

M.type = 'tendrops'
M.display_name_key = 'amap.instance_tendrops_name'
M.description_key = 'amap.instance_tendrops_desc'
M.gameplay_desc_key = 'amap.instance_tendrops_gameplay'
M.victory_condition_key = 'amap.instance_tendrops_victory'
M.icon = 'item/water-barrel'  -- 水桶图标
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
        size = 5,                        -- 5x5 网格
        drops = 14,                      -- 初始水滴额度
        time_limit = 18 * 60 * 60,
        reward_multiplier = 1.0
    },
    normal = {
        name = "normal",
        recycling_efficiency = 1,
        max_coins = 0,
        display_name_key = "dungeon_difficulty_normal",
        size = 6,                        -- 6x6 网格
        drops = 10,
        time_limit = 15 * 60 * 60,
        reward_multiplier = 1.0
    },
    hard = {
        name = "hard",
        recycling_efficiency = 1,
        max_coins = 0,
        display_name_key = "dungeon_difficulty_hard",
        size = 7,                        -- 7x7 网格
        drops = 8,
        time_limit = 12 * 60 * 60,
        reward_multiplier = 1.0
    }
}

--==============================================================================
-- GUI 元素名常量
--==============================================================================

local GUI_FRAME  = 'dungeon_module_tendrops_main_frame'
local GUI_STATUS = 'dungeon_module_tendrops_status'
local GUI_GRID   = 'dungeon_module_tendrops_grid'
local CELL_PREFIX = 'dungeon_module_tendrops_cell_'

--==============================================================================
-- 水滴等级配色与字符
--==============================================================================
-- 0=空 1-4=水滴等级（用圆形大小递增的字符 + 颜色表达）

local DROP_COLOR = {
    [1] = {0.40, 0.75, 1.00},  -- 浅蓝
    [2] = {0.25, 0.55, 1.00},  -- 中蓝
    [3] = {0.15, 0.35, 0.95},  -- 深蓝
    [4] = {0.85, 0.30, 1.00},  -- 紫红（满级，警告色）
}

local DROP_CHAR = {
    [1] = '•',   -- 小点
    [2] = '●',   -- 中圆
    [3] = '◉',   -- 大圆带核
    [4] = '★',   -- 满级（爆裂前）
}

-- 4 邻接偏移（上下左右）
local NEIGHBOR4 = {{0, -1}, {0, 1}, {-1, 0}, {1, 0}}

-- 注意：框架 on_tick 每 60 tick（1 秒）调用一次。
-- 连锁波策略：第一波在 on_gui_click 中立即处理（即时反馈），
-- 后续波由 on_tick 推进（每波间隔 1 秒，便于玩家观察连锁动画）。

--==============================================================================
-- 辅助函数
--==============================================================================

local function cell_caption(v)
    if v == 0 then return '' end
    return DROP_CHAR[v] or ''
end

local function cell_color(v)
    if v == 0 then return nil end
    return DROP_COLOR[v] or {1, 1, 1}
end

-- 全网格是否为空
local function grid_empty(md)
    for r = 1, md.size do
        for c = 1, md.size do
            if md.grid[r][c] ~= 0 then return false end
        end
    end
    return true
end

-- 处理一波爆裂（由 on_gui_click 立即调用第一波，on_tick 推进后续波）
-- 把当前 burst_queue 全部处理：每个爆裂点的 4 邻受溅射
-- - 邻格 L<4 → 升 1 级
-- - 邻格 L=4 → 该邻格连锁爆裂（清 0 + 入下一波队列）
-- - 邻格 L=0 → 飞溅消失
-- 本波爆裂数 ≥3 → 奖励水滴（+1/+2/+3）
local function step_wave(md)
    local wave = {}
    for _, b in ipairs(md.burst_queue) do wave[#wave + 1] = b end
    md.burst_queue = {}
    local burst_count = #wave

    for _, b in ipairs(wave) do
        for _, d in ipairs(NEIGHBOR4) do
            local nr, nc = b.r + d[1], b.c + d[2]
            if nr >= 1 and nr <= md.size and nc >= 1 and nc <= md.size then
                local t = md.grid[nr][nc]
                if t > 0 and t < 4 then
                    md.grid[nr][nc] = t + 1
                elseif t == 4 then
                    md.grid[nr][nc] = 0
                    md.burst_queue[#md.burst_queue + 1] = {r = nr, c = nc}  -- 连锁入下一波
                end
                -- t == 0：飞溅消失
            end
        end
    end

    -- 连锁奖励：本波爆裂数 ≥3 → +水滴
    if burst_count >= 3 then
        local bonus = burst_count >= 9 and 3 or (burst_count >= 6 and 2 or 1)
        md.drops = md.drops + bonus
        md.combo_max = math.max(md.combo_max, burst_count)
        md.last_combo = burst_count
        md.last_bonus = bonus
    end

    -- 若队列还有，下一波继续（由 on_tick 推进）；否则连锁结束
    if #md.burst_queue == 0 then
        md.waves_running = 0
    end

    return burst_count
end

-- 点 (r,c)：升级或爆裂，启动连锁
-- 注意：本函数仅处理「点击」的瞬时效果（升 1 级 或 直接爆裂+处理第一波），
--       后续连锁波由 on_tick 逐步结算（每波间隔 1 秒）
local function click_drop(md, r, c)
    local lv = md.grid[r][c]
    if lv == 0 then return false end  -- 空格不可点
    if lv < 4 then
        md.grid[r][c] = lv + 1
        return true
    end
    -- 满级 → 爆裂
    md.grid[r][c] = 0
    md.burst_queue[#md.burst_queue + 1] = {r = r, c = c}
    md.waves_running = 1
    -- 立即处理第一波（即时反馈，玩家点下去立刻看到爆裂）
    step_wave(md)
    return true
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
        caption = {'amap.tendrops_main_caption', {'amap.' .. md.difficulty_label_key}},
        direction = 'vertical'
    })
    frame.force_auto_center()
    frame.style.minimal_width = size * 56 + 60

    local status = frame.add({type = 'label', name = GUI_STATUS, caption = ''})
    status.style.font = 'heading-2'
    status.style.font_color = {1, 0.84, 0}
    status.style.top_padding = 4
    status.style.bottom_padding = 4

    -- 合成顺序（从小到大，全名）
    local order = {''}
    for v = 1, #DROP_CHAR do
        order[#order + 1] = {'amap.tendrops_tier_' .. v}
        if v < #DROP_CHAR then order[#order + 1] = '→' end
    end
    local chain = frame.add({type = 'label', name = GUI_GRID .. '_chain',
        caption = {'amap.tendrops_chain_label', order}})
    chain.style.font = 'heading-2'
    chain.style.font_color = {0, 0, 0}
    chain.style.top_padding = 4
    chain.style.bottom_padding = 4

    local grid_table = frame.add({
        type = 'table',
        name = GUI_GRID,
        column_count = size
    })
    grid_table.style.horizontal_spacing = 4
    grid_table.style.vertical_spacing = 4
    grid_table.style.top_padding = 4
    grid_table.style.bottom_padding = 4

    local cell_size = 52
    for r = 1, size do
        for c = 1, size do
            local v = md.grid[r][c]
            local btn = grid_table.add({
                type = 'button',
                name = CELL_PREFIX .. r .. '_' .. c,
                caption = cell_caption(v),
                tags = {tendrops_cell = true, r = r, c = c},
                mouse_button_filter = {'left'}
            })
            btn.style.minimal_width = cell_size
            btn.style.minimal_height = cell_size
            btn.style.maximal_width = cell_size
            btn.style.maximal_height = cell_size
            btn.style.font = 'heading-1'
            btn.style.font_color = cell_color(v) or {1, 1, 1}
            btn.style.horizontal_align = 'center'
            btn.style.vertical_align = 'center'
            btn.style.top_padding = 0
            btn.style.bottom_padding = 0
            btn.style.left_padding = 0
            btn.style.right_padding = 0
        end
    end

    local hint = frame.add({type = 'label', caption = {'amap.tendrops_hint'}})
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

    local status = frame[GUI_STATUS]
    if status and status.valid then
        status.caption = {'amap.tendrops_status', md.drops, md.combo_max}
    end

    local grid_table = frame[GUI_GRID]
    if not grid_table or not grid_table.valid then return end
    for r = 1, size do
        for c = 1, size do
            local btn = grid_table[CELL_PREFIX .. r .. '_' .. c]
            if btn and btn.valid then
                local v = md.grid[r][c]
                btn.caption = cell_caption(v)
                btn.style.font_color = cell_color(v) or {1, 1, 1}
            end
        end
    end
end

--==============================================================================
-- 钩子实现
--==============================================================================

-- 延迟退出（避免在 GUI 事件 handler / on_tick 内直接销毁 surface/character）
local function delayed_exit(params)
    local player = game.players[params.player_index]
    if not player or not player.valid then return end
    Instance.exit(player, params.reason)
end
local delayed_exit_token = Token.register(delayed_exit)

function M.on_surface_init(surface, player, data, difficulty)
    local diff = M.difficulty_settings[difficulty] or M.difficulty_settings.easy
    local size = diff.size

    -- 初始 grid：每格随机 1-3 级（不会出现满级开局，避免误点即连锁）
    local grid = {}
    for r = 1, size do
        grid[r] = {}
        for c = 1, size do
            grid[r][c] = math.random(1, 3)
        end
    end

    data.module_data = {
        size = size,
        grid = grid,
        drops = diff.drops,
        combo_max = 0,
        burst_queue = {},     -- 待处理爆裂队列
        waves_running = 0,    -- >0 表示连锁未结束
        last_combo = 0,
        last_bonus = 0,
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
        player.print({'amap.tendrops_enter', {'amap.' .. md.difficulty_label_key}}, {r = 0, g = 1, b = 0})
    end
end

function M.on_exit(player, data, reason)
    local screen = player.gui.screen
    if screen[GUI_FRAME] then
        screen[GUI_FRAME].destroy()
    end
    -- 清空爆裂队列（防止 on_tick 残留触发）
    local md = data.module_data
    if md then
        md.burst_queue = {}
        md.waves_running = 0
    end
end

-- 框架每 60 tick（1 秒）调用一次：推进连锁后续波
function M.on_tick(player, data)
    local md = data.module_data
    if not md then return end
    if md.result then return end

    -- 没有正在进行的连锁 → 跳过
    if md.waves_running <= 0 then return end

    -- 处理下一波
    local burst_count = step_wave(md)
    refresh_gui(player, data)

    -- 提示连锁奖励（仅在本波触发了奖励时）
    if burst_count >= 3 then
        local bonus = burst_count >= 9 and 3 or (burst_count >= 6 and 2 or 1)
        player.print({'amap.tendrops_combo', burst_count, bonus}, {r = 0, g = 1, b = 0})
    end

    -- 连锁结束（waves_running 已被 step_wave 置 0）→ 判胜负
    if md.waves_running == 0 then
        if grid_empty(md) then
            local mult = md.reward_base * (md.drops > 0 and 1.2 or 1.0)
            Instance.set_reward_multiplier(player, mult)
            md.result = 'victory'
            player.print({'amap.tendrops_win'}, {r = 0, g = 1, b = 0})
            Task.set_timeout_in_ticks(2, delayed_exit_token, {player_index = player.index, reason = 'victory'})
        elseif md.drops <= 0 then
            md.result = 'defeat'
            player.print({'amap.tendrops_lose'}, {r = 1, g = 0, b = 0})
            Task.set_timeout_in_ticks(2, delayed_exit_token, {player_index = player.index, reason = 'defeat'})
        end
    end
end

function M.check_victory(player, data)
    local md = data.module_data
    if not md then return nil end
    if md.result then return md.result end

    -- 兜底：若玩家点击后未连锁（仅升级），且额度耗尽仍有水滴 → 失败
    -- （连锁中的判负由 on_tick 处理，此处仅判非连锁状态）
    if md.waves_running == 0 then
        if grid_empty(md) then
            local mult = md.reward_base * (md.drops > 0 and 1.2 or 1.0)
            Instance.set_reward_multiplier(player, mult)
            md.result = 'victory'
            player.print({'amap.tendrops_win'}, {r = 0, g = 1, b = 0})
            Task.set_timeout_in_ticks(2, delayed_exit_token, {player_index = player.index, reason = 'victory'})
            return 'victory'
        end
        if md.drops <= 0 then
            md.result = 'defeat'
            player.print({'amap.tendrops_lose'}, {r = 1, g = 0, b = 0})
            Task.set_timeout_in_ticks(2, delayed_exit_token, {player_index = player.index, reason = 'defeat'})
            return 'defeat'
        end
    end
    return nil
end

-- 延迟退出 token 已在文件钩子实现段开头声明

function M.on_gui_click(player, event)
    local element = event.element
    if not element or not element.valid then return end

    local data = Instance.get_data(player.index)
    if not data or not data.active then return end
    local md = data.module_data
    if not md then return end
    if md.result then return end

    local tags = element.tags or {}
    if not tags.tendrops_cell then return end
    local r = tags.r
    local c = tags.c
    if type(r) ~= 'number' or type(c) ~= 'number' then return end
    if r < 1 or r > md.size or c < 1 or c > md.size then return end

    -- 连锁进行中锁输入（防止玩家在动画期间乱点）
    if md.waves_running > 0 then return end

    -- 空格不可点
    if md.grid[r][c] == 0 then return end

    -- 额度耗尽不可点
    if md.drops <= 0 then return end

    md.drops = md.drops - 1
    click_drop(md, r, c)
    refresh_gui(player, data)

    -- 立即判胜负（非爆裂点击后可能直接胜利：升级到 4 但未爆，且全空不可能；
    -- 爆裂点击会启动连锁，胜负由 on_tick 在连锁结束后判）
    if md.waves_running == 0 then
        if grid_empty(md) then
            local mult = md.reward_base * (md.drops > 0 and 1.2 or 1.0)
            Instance.set_reward_multiplier(player, mult)
            md.result = 'victory'
            player.print({'amap.tendrops_win'}, {r = 0, g = 1, b = 0})
            Task.set_timeout_in_ticks(2, delayed_exit_token, {player_index = player.index, reason = 'victory'})
        elseif md.drops <= 0 then
            md.result = 'defeat'
            player.print({'amap.tendrops_lose'}, {r = 1, g = 0, b = 0})
            Task.set_timeout_in_ticks(2, delayed_exit_token, {player_index = player.index, reason = 'defeat'})
        end
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
-- 这里把内部纯逻辑函数暴露为全局 _TENDROPS_TEST，供 RCON 测试调用，
-- 验证点击 / 爆裂 / 连锁 / 胜负判定等纯逻辑是否正确（参考 副本添加说明.md §10）。
-- 生产环境无副作用（无人调用即不执行）。

_TENDROPS_TEST = {
    NEIGHBOR4 = NEIGHBOR4,
    cell_caption = cell_caption,
    cell_color = cell_color,
    grid_empty = grid_empty,
    click_drop = click_drop,
    step_wave = step_wave,
    difficulty_settings = M.difficulty_settings,
}

return M
