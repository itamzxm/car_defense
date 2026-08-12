-- maps/amap/instance/modules/merge2048.lua
-- 2048 数字合成玩法模块
--
-- 玩法类型：merge2048
-- 玩法说明：经典 2048 的 Factorio GUI 适配版（休闲拼合）
--   - 由于异星工厂地形不擅长表达数字，本玩法完全用 GUI 面板实现
--   - 玩家进入副本后看到一个小房间（草地+石墙围）和一块全屏 2048 主面板
--   - 点屏幕上的方向键（↑↓←→）滑动全部瓦片，相同数字合并翻倍
--   - 每次有效移动后随机生成一个新瓦片（90% 为 2，10% 为 4）
--   - 凑出目标瓦片即胜利；棋盘锁死（无空格且四向均无可合并相邻对）即失败
--
-- 难度分级（仅目标瓦片不同，时间统一 20 分钟，奖励系数统一 1.0）：
--   easy   - 目标 512
--   normal - 目标 1024
--   hard   - 目标 2048
--
-- 钩子实现：
--   on_surface_init - 生成草地小房间 + 外围石墙 + 初始化 4x4 棋盘（放 2 个初始瓦片）
--   on_enter        - 隐藏框架金币 label + 创建 2048 主 GUI + 提示玩法
--   on_exit         - 销毁 2048 主 GUI
--   on_tick         - 静态游戏，无需操作（保留空实现以备扩展）
--   check_victory   - 返回 md.result（终局由 on_gui_click 经延迟退出设置）
--   on_gui_click    - 方向键点击 → 移动 → 生成 → 刷新 → 判定胜负

local Instance = require 'maps.amap.instance.instance'
local Token = require 'utils.token'
local Task = require 'utils.task'

local M = {}

--==============================================================================
-- 元数据
--==============================================================================

M.type = 'merge2048'
M.display_name_key = 'amap.instance_merge2048_name'
M.description_key = 'amap.instance_merge2048_desc'
M.gameplay_desc_key = 'amap.instance_merge2048_gameplay'
M.victory_condition_key = 'amap.instance_merge2048_victory'
M.icon = 'item/electronic-circuit'  -- 电路板图标（网格状，与数字面板呼应）

-- 三档统一时间：20 分钟（tick）
local TIME_LIMIT = 20 * 60 * 60
M.time_limit_default = TIME_LIMIT

--==============================================================================
-- 难度设置
-- 仅目标瓦片不同；时间统一 20 分钟；奖励系数固定 1.0（不再做其他难度区分）
--==============================================================================

M.difficulty_settings = {
    easy = {
        name = "easy",
        recycling_efficiency = 1,
        max_coins = 0,
        display_name_key = "dungeon_difficulty_easy",
        target = 512,
        reward_multiplier = 1.0,
        time_limit = TIME_LIMIT,
    },
    normal = {
        name = "normal",
        recycling_efficiency = 1,
        max_coins = 0,
        display_name_key = "dungeon_difficulty_normal",
        target = 1024,
        reward_multiplier = 1.0,
        time_limit = TIME_LIMIT,
    },
    hard = {
        name = "hard",
        recycling_efficiency = 1,
        max_coins = 0,
        display_name_key = "dungeon_difficulty_hard",
        target = 2048,
        reward_multiplier = 1.0,
        time_limit = TIME_LIMIT,
    },
}

--==============================================================================
-- GUI 元素名常量（前缀 dungeon_module_ 防冲突，符合框架约定）
--==============================================================================

local SIZE = 4
local GUI_FRAME = 'dungeon_module_merge2048_main_frame'
local GUI_STATUS = 'dungeon_module_merge2048_status'
local GUI_GRID  = 'dungeon_module_merge2048_grid'
local CELL_PREFIX = 'dungeon_module_merge2048_cell_'
local DIR_PREFIX  = 'dungeon_module_merge2048_dir_'

--==============================================================================
-- 辅助函数：瓦片配色（单元格为纯黑背景，亮色数字保证高对比可读）
--==============================================================================

-- 瓦片数字配色：单元格已改为**纯黑背景**（见 create_main_gui 的 frame + background_color），
-- 故数字用**高亮度**色，黑底+亮字对比拉满。亮度足够时非粗体也清晰；字体用 heading-1(18px 粗体)再补一层。
-- 空格返回 nil（label caption 为空，黑底即空格外观）。
local function cell_color(v)
    if v == 0 then return nil end
    if v <= 2 then return {1.00, 1.00, 1.00} end   -- 白
    if v <= 4 then return {1.00, 0.92, 0.30} end   -- 亮黄
    if v <= 8 then return {1.00, 0.60, 0.10} end   -- 亮橙
    if v <= 16 then return {1.00, 0.40, 0.35} end  -- 亮红
    if v <= 32 then return {1.00, 0.45, 0.85} end  -- 亮粉
    if v <= 64 then return {0.75, 0.55, 1.00} end  -- 亮紫
    if v <= 128 then return {0.50, 0.75, 1.00} end -- 亮蓝
    if v <= 256 then return {0.35, 0.90, 1.00} end -- 亮青
    if v <= 512 then return {0.45, 1.00, 0.55} end -- 亮绿
    if v <= 1024 then return {0.80, 1.00, 0.35} end-- 亮黄绿
    if v <= 2048 then return {1.00, 0.85, 0.20} end-- 亮金
    return {1.00, 1.00, 1.00}
end

-- 单行左滑合并：line 为长度 SIZE 的数值数组（0=空），返回 {新行, 本步得分}
local function slide_line(line)
    local non_zero, out, score = {}, {}, 0
    for i = 1, SIZE do
        if line[i] > 0 then non_zero[#non_zero + 1] = line[i] end
    end
    local i = 1
    while i <= #non_zero do
        if i < #non_zero and non_zero[i] == non_zero[i + 1] then
            local v = non_zero[i] * 2
            out[#out + 1] = v
            score = score + v
            i = i + 2
        else
            out[#out + 1] = non_zero[i]
            i = i + 1
        end
    end
    while #out < SIZE do out[#out + 1] = 0 end
    return out, score
end

-- 棋盘序列化（用于判断移动是否改变棋盘）
local function serialize(g)
    local s = ''
    for r = 1, SIZE do
        for c = 1, SIZE do
            s = s .. ':' .. g[r][c]
        end
    end
    return s
end

-- 朝 dir 移动；返回棋盘是否发生变化（仅变化时计步数）
local function apply_move(md, dir)
    local g = md.grid
    local before = serialize(g)
    if dir == 'left' then
        for r = 1, SIZE do
            local row = {}
            for c = 1, SIZE do row[c] = g[r][c] end
            local nl, sc = slide_line(row)
            for c = 1, SIZE do g[r][c] = nl[c] end
            md.score = md.score + sc
        end
    elseif dir == 'right' then
        for r = 1, SIZE do
            local row = {}
            for c = 1, SIZE do row[c] = g[r][SIZE + 1 - c] end
            local nl, sc = slide_line(row)
            for c = 1, SIZE do g[r][SIZE + 1 - c] = nl[c] end
            md.score = md.score + sc
        end
    elseif dir == 'up' then
        for c = 1, SIZE do
            local col = {}
            for r = 1, SIZE do col[r] = g[r][c] end
            local nl, sc = slide_line(col)
            for r = 1, SIZE do g[r][c] = nl[r] end
            md.score = md.score + sc
        end
    elseif dir == 'down' then
        for c = 1, SIZE do
            local col = {}
            for r = 1, SIZE do col[r] = g[SIZE + 1 - r][c] end
            local nl, sc = slide_line(col)
            for r = 1, SIZE do g[SIZE + 1 - r][c] = nl[r] end
            md.score = md.score + sc
        end
    else
        return false
    end
    local changed = serialize(g) ~= before
    if changed then md.moves = md.moves + 1 end
    return changed
end

-- 随机空格生成新瓦片：90% 为 2，10% 为 4
local function spawn_tile(md)
    local empties = {}
    for r = 1, SIZE do
        for c = 1, SIZE do
            if md.grid[r][c] == 0 then empties[#empties + 1] = {r, c} end
        end
    end
    if #empties == 0 then return end
    local cell = empties[math.random(#empties)]
    md.grid[cell[1]][cell[2]] = math.random() < 0.9 and 2 or 4
end

-- 是否还有可行移动
local function has_moves(md)
    local g = md.grid
    for r = 1, SIZE do
        for c = 1, SIZE do
            if g[r][c] == 0 then return true end
            if c < SIZE and g[r][c] == g[r][c + 1] then return true end
            if r < SIZE and g[r][c] == g[r + 1][c] then return true end
        end
    end
    return false
end

-- 是否胜利（出现 >= 目标瓦片）
local function is_win(md)
    local g = md.grid
    for r = 1, SIZE do
        for c = 1, SIZE do
            if g[r][c] >= md.target then return true end
        end
    end
    return false
end

-- 当前最高瓦片（用于展示）
local function best_tile(md)
    local b = 0
    for r = 1, SIZE do
        for c = 1, SIZE do
            if md.grid[r][c] > b then b = md.grid[r][c] end
        end
    end
    return b
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
        caption = {'amap.merge2048_main_caption', {'amap.' .. md.difficulty_label_key}},
        direction = 'vertical'
    })
    frame.force_auto_center()
    frame.style.minimal_width = SIZE * 100 + 60

    local status = frame.add({type = 'label', name = GUI_STATUS, caption = ''})
    status.style.font = 'heading-2'
    status.style.font_color = {1, 0.84, 0}
    status.style.top_padding = 4
    status.style.bottom_padding = 4

    local grid_table = frame.add({
        type = 'table',
        name = GUI_GRID,
        column_count = SIZE
    })
    grid_table.style.horizontal_spacing = 6
    grid_table.style.vertical_spacing = 6
    grid_table.style.top_padding = 6
    grid_table.style.bottom_padding = 6

    local cell_size = 72
    for r = 1, SIZE do
        for c = 1, SIZE do
            local v = md.grid[r][c]
            -- 单元格用 frame：frame 支持 background_color 设纯黑底（button 只能浅色皮肤、无法改背景）。
            -- 数字用亮色 label 居中置于黑底之上，对比最强；frame 自带边框即格子线。
            -- 不加 merge2048_dir tag，点击无效（on_gui_click 仅处理方向键）。
            local cell = grid_table.add({
                type = 'frame',
                name = CELL_PREFIX .. r .. '_' .. c,
                direction = 'vertical'
            })
            cell.style.minimal_width = cell_size
            cell.style.minimal_height = cell_size
            cell.style.maximal_width = cell_size
            cell.style.maximal_height = cell_size
            -- frame 默认即为深色底（来自 graphical_set，非 background_color）。
            -- background_color 在本版本仅 textbox/graph 样式可设，frame 不设此属性会抛错；
            -- 故用 pcall 探试：设得上=纯黑，设不上=保持默认深色（仍满足黑底亮字高对比），绝不因样式差异崩 GUI。
            pcall(function() cell.style.background_color = {0, 0, 0, 1} end)
            cell.style.horizontal_align = 'center'
            cell.style.vertical_align = 'center'
            cell.style.left_padding = 0
            cell.style.right_padding = 0
            cell.style.top_padding = 0
            cell.style.bottom_padding = 0

            local num = cell.add({
                type = 'label',
                name = CELL_PREFIX .. r .. '_' .. c .. '_num',
                caption = v == 0 and '' or tostring(v)
            })
            num.style.font = 'heading-1'   -- 粗体(18px)，黑底亮字足够清晰
            num.style.font_color = cell_color(v) or {1, 1, 1}
            num.style.horizontal_align = 'center'
            num.style.vertical_align = 'center'
        end
    end

    -- 方向控制 D-pad（Factorio GUI 无法捕获方向键，用屏幕按钮触发）
    local pad = frame.add({type = 'flow', direction = 'vertical'})
    pad.style.horizontal_align = 'center'
    pad.style.top_padding = 6

    local function dir_btn(name, caption, dir)
        local b = pad.add({
            type = 'button',
            name = name,
            caption = caption,
            tags = {merge2048_dir = dir},
            mouse_button_filter = {'left'}
        })
        b.style.minimal_width = 90
        b.style.minimal_height = 48
        b.style.font = 'heading-1'
        return b
    end

    dir_btn(DIR_PREFIX .. 'up', '↑', 'up')
    local mid = pad.add({type = 'flow', direction = 'horizontal'})
    mid.style.horizontal_align = 'center'
    -- 临时挂到 mid 上：复用 dir_btn 会加到 pad，故直接建
    local left = mid.add({type = 'button', name = DIR_PREFIX .. 'left', caption = '←',
                          tags = {merge2048_dir = 'left'}, mouse_button_filter = {'left'}})
    left.style.minimal_width = 90; left.style.minimal_height = 48; left.style.font = 'heading-1'
    local right = mid.add({type = 'button', name = DIR_PREFIX .. 'right', caption = '→',
                           tags = {merge2048_dir = 'right'}, mouse_button_filter = {'left'}})
    right.style.minimal_width = 90; right.style.minimal_height = 48; right.style.font = 'heading-1'
    dir_btn(DIR_PREFIX .. 'down', '↓', 'down')

    local hint = frame.add({type = 'label', caption = {'amap.merge2048_hint'}})
    hint.style.font = 'default'
    hint.style.font_color = {0.7, 0.7, 0.7}
    hint.style.single_line = false
    hint.style.maximal_width = SIZE * 100 + 40
end

local function refresh_gui(player, data)
    local screen = player.gui.screen
    local frame = screen[GUI_FRAME]
    if not frame or not frame.valid then return end
    local md = data.module_data

    local status = frame[GUI_STATUS]
    if status and status.valid then
        status.caption = {'amap.merge2048_status', best_tile(md), md.moves, md.target}
    end

    local grid_table = frame[GUI_GRID]
    if not grid_table or not grid_table.valid then return end
    for r = 1, SIZE do
        for c = 1, SIZE do
            local cell = grid_table[CELL_PREFIX .. r .. '_' .. c]
            if cell and cell.valid then
                local num = cell[CELL_PREFIX .. r .. '_' .. c .. '_num']
                if num and num.valid then
                    local v = md.grid[r][c]
                    num.caption = v == 0 and '' or tostring(v)
                    num.style.font_color = cell_color(v) or {1, 1, 1}
                end
            end
        end
    end
end

--==============================================================================
-- 钩子实现
--==============================================================================

-- surface 初始化：生成草地小房间 + 外围石墙 + 初始化 4x4 棋盘（2 个初始瓦片）
function M.on_surface_init(surface, player, data, difficulty)
    local diff = M.difficulty_settings[difficulty] or M.difficulty_settings.easy

    local grid = {}
    for r = 1, SIZE do
        grid[r] = {}
        for c = 1, SIZE do grid[r][c] = 0 end
    end

    data.module_data = {
        grid = grid,
        target = diff.target,
        reward_base = diff.reward_multiplier,
        score = 0,
        moves = 0,
        result = nil,
        difficulty_label_key = diff.display_name_key,
    }
    data.time_limit = TIME_LIMIT

    -- 初始放 2 个瓦片
    spawn_tile(data.module_data)
    spawn_tile(data.module_data)

    -- 1. 全图铺 grass-1（视觉清爽）
    for x = -50, 50 do
        for y = -50, 50 do
            surface.set_tiles{{name = "grass-1", position = {x, y}}}
        end
    end

    -- 2. 外围石墙围成一个小房间（玩家在房间内操作 GUI，不需要大空间）
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

    -- 4. 让副本 force chart 房间区域（玩家立即可见小房间）
    player.force.chart(surface, {
        {-room_half - 2, -room_half - 2},
        {room_half + 2, room_half + 2}
    })
end

-- 进入副本：隐藏框架金币 label + 创建 2048 主 GUI + 提示玩法
function M.on_enter(player, data, difficulty)
    player.force.manual_mining_speed_modifier = 0

    local top = player.gui.top
    -- 本玩法无金币概念，隐藏框架的 coins label
    if top['dungeon_coins'] then
        top['dungeon_coins'].destroy()
    end

    create_main_gui(player, data)
    refresh_gui(player, data)

    local md = data.module_data
    if md then
        player.print({'amap.merge2048_enter', md.target, {'amap.' .. md.difficulty_label_key}}, {r = 0, g = 1, b = 0})
    end
end

-- 退出副本：销毁 2048 主 GUI
function M.on_exit(player, data, reason)
    local screen = player.gui.screen
    if screen[GUI_FRAME] then
        screen[GUI_FRAME].destroy()
    end
end

-- 每 60 tick：静态游戏，无需操作
function M.on_tick(player, data)
    -- no-op
end

-- 通关检测：终局由 on_gui_click 经延迟退出设置 md.result，这里返回它作兜底
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

-- GUI 点击事件
function M.on_gui_click(player, event)
    local element = event.element
    if not element or not element.valid then return end

    local data = Instance.get_data(player.index)
    if not data or not data.active then return end
    local md = data.module_data
    if not md then return end

    local tags = element.tags or {}
    if not tags.merge2048_dir then return end  -- 仅处理方向键
    if md.result then return end              -- 终局后忽略点击

    local dir = tags.merge2048_dir
    local moved = apply_move(md, dir)
    if not moved then return end              -- 无效移动（棋盘未变），忽略

    spawn_tile(md)
    refresh_gui(player, data)

    if is_win(md) then
        player.print({'amap.merge2048_win', best_tile(md)}, {r = 0, g = 1, b = 0})
        Instance.set_reward_multiplier(player, md.reward_base or 1.0)
        md.result = 'victory'
        Task.set_timeout_in_ticks(2, delayed_exit_token, {player_index = player.index, reason = 'victory'})
    elseif not has_moves(md) then
        player.print({'amap.merge2048_lose'}, {r = 1, g = 0, b = 0})
        md.result = 'defeat'
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
-- 这里把内部纯逻辑函数暴露为全局 _MERGE2048_TEST，供 RCON 测试调用，
-- 验证滑动合并 / 生成 / 胜负判定等纯逻辑是否正确（参考 副本添加说明.md §10）。
-- 生产环境无副作用（无人调用即不执行）。

_MERGE2048_TEST = {
    SIZE = SIZE,
    slide_line = slide_line,
    apply_move = apply_move,
    spawn_tile = spawn_tile,
    has_moves = has_moves,
    is_win = is_win,
    best_tile = best_tile,
    difficulty_settings = M.difficulty_settings,
}

return M
