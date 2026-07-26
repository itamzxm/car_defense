-- maps/amap/instance/modules/watersort.lua
-- 水排序玩法模块
--
-- 玩法类型：watersort
-- 玩法说明：把试管里的混合颜色液体倒来倒去，使每管纯色或空即胜
--   - 纯 GUI 面板玩法（参考 sudoku 骨架）
--   - 多个试管，每管 6 格，存颜色 ID（0=空，1..N=颜色）
--   - 点试管 A 选中（必须非空）→ 点试管 B 倒水：
--       * 仅倒 A 顶层连续同色段
--       * B 必须空 或 B 顶层同色 且有空位
--       * 倒数量 = min(A 顶层同色段长度, B 剩余空位数)
--   - 全部试管纯色或空即胜
--   - 无失败状态，提供「重置」按钮（按用户要求，无撤销）
--
-- 难度分级（颜色数+管数差异，时间全难度统一 5 分钟）：
--   easy   - 3 色 / 5 管  - 5 分钟 - 奖励系数 1.0
--   normal - 5 色 / 7 管  - 5 分钟 - 奖励系数 1.5
--   hard   - 7 色 / 9 管  - 5 分钟 - 奖励系数 2.0
--
-- 钩子实现：
--   on_surface_init - 生成草地小房间 + 外围石墙 + 生成试管布局（随机分配，2 空管保证可解）
--   on_enter        - 隐藏框架金币 label + 创建主 GUI + 提示玩法
--   on_exit         - 销毁主 GUI
--   on_tick         - 静态游戏，无需操作
--   check_victory   - 所有试管纯色或空 → 胜利（设奖励系数）
--   on_gui_click    - 试管点击（选中/倒水）+ 重置按钮

local Instance = require 'maps.amap.instance.instance'

local M = {}

--==============================================================================
-- 元数据
--==============================================================================

M.type = 'watersort'
M.display_name_key = 'amap.instance_watersort_name'
M.description_key = 'amap.instance_watersort_desc'
M.gameplay_desc_key = 'amap.instance_watersort_gameplay'
M.victory_condition_key = 'amap.instance_watersort_victory'
M.icon = 'item/water-barrel'
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
        colors = 3,                 -- 3 色 → 3 满管 + 2 空管 = 5 管
        time_limit = 5 * 60 * 60,   -- 5 分钟（全难度统一）
        reward_multiplier = 1.0
    },
    normal = {
        name = "normal",
        recycling_efficiency = 1,
        max_coins = 0,
        display_name_key = "dungeon_difficulty_normal",
        colors = 5,                 -- 5 色 → 5 满管 + 2 空管 = 7 管
        time_limit = 5 * 60 * 60,
        reward_multiplier = 1.0
    },
    hard = {
        name = "hard",
        recycling_efficiency = 1,
        max_coins = 0,
        display_name_key = "dungeon_difficulty_hard",
        colors = 7,                 -- 7 色 → 7 满管 + 2 空管 = 9 管
        time_limit = 5 * 60 * 60,
        reward_multiplier = 1.0
    }
}

--==============================================================================
-- GUI 元素名常量
--==============================================================================

local GUI_FRAME       = 'dungeon_module_watersort_main_frame'
local GUI_PROGRESS    = 'dungeon_module_watersort_progress'
local GUI_TUBE_TABLE  = 'dungeon_module_watersort_tube_table'
local GUI_RESET_BTN   = 'dungeon_module_watersort_reset_btn'

local TUBE_PREFIX = 'dungeon_module_watersort_tube_'

--==============================================================================
-- 试管容量与颜色显示
--==============================================================================

local CAPACITY = 6

-- 7 个颜色：A 红 / B 绿 / C 蓝 / D 黄 / E 紫 / F 橙 / G 青
-- 颜色规则（参照 merge2048 §5.8）：按钮默认浅色背景，故字母必须用深色高饱和色，
-- 不能用浅色（浅字+浅按钮=看不清）
local COLOR_LABEL = {'A', 'B', 'C', 'D', 'E', 'F', 'G'}
local COLOR_VALUE = {
    {0.78, 0.08, 0.08},   -- A 深红
    {0.04, 0.55, 0.22},   -- B 深绿
    {0.22, 0.28, 0.78},   -- C 深蓝
    {0.78, 0.55, 0.04},   -- D 深金（替代浅黄，浅黄在浅背景上看不清）
    {0.52, 0.18, 0.78},   -- E 深紫
    {0.80, 0.33, 0.04},   -- F 深橙
    {0.04, 0.50, 0.55}    -- G 深青
}

--==============================================================================
-- 纯逻辑函数
--==============================================================================

-- 生成试管布局：colors 种颜色，每色 CAPACITY 滴，前 colors 管满，后 2 管空
-- 随机分配 colors*CAPACITY 滴到前 colors 管
local function generate_layout(colors)
    local tube_count = colors + 2

    -- 生成颜色池：每色 CAPACITY 滴
    local pool = {}
    for c = 1, colors do
        for _ = 1, CAPACITY do
            pool[#pool + 1] = c
        end
    end

    -- 打乱颜色池
    for _ = 1, #pool * 3 do
        local a = math.random(1, #pool)
        local b = math.random(1, #pool)
        pool[a], pool[b] = pool[b], pool[a]
    end

    -- 分配到前 colors 管（每管 CAPACITY 滴），后 2 管空
    local tubes = {}
    local idx = 1
    for t = 1, tube_count do
        tubes[t] = {}
        if t <= colors then
            for i = 1, CAPACITY do
                tubes[t][i] = pool[idx]
                idx = idx + 1
            end
        else
            for i = 1, CAPACITY do
                tubes[t][i] = 0
            end
        end
    end

    return tubes
end

-- 获取试管的顶层颜色（0=空管）
local function top_color(tube)
    for i = CAPACITY, 1, -1 do
        if tube[i] ~= 0 then
            return tube[i]
        end
    end
    return 0
end

-- 获取试管顶层连续同色段长度
local function top_count(tube)
    local tc = top_color(tube)
    if tc == 0 then return 0 end
    local n = 0
    for i = CAPACITY, 1, -1 do
        if tube[i] == tc then
            n = n + 1
        elseif tube[i] ~= 0 then
            break
        end
    end
    return n
end

-- 获取试管空位数
local function empty_count(tube)
    local n = 0
    for i = 1, CAPACITY do
        if tube[i] == 0 then n = n + 1 end
    end
    return n
end

-- 倒水：从 src 倒到 dst
-- 返回 true 表示成功；false 表示不可倒
local function pour(tubes, src, dst)
    if src == dst then return false end

    local src_tube = tubes[src]
    local dst_tube = tubes[dst]

    local src_tc = top_color(src_tube)
    if src_tc == 0 then return false end  -- 源管空

    local src_top_n = top_count(src_tube)
    local dst_empty = empty_count(dst_tube)
    if dst_empty == 0 then return false end  -- 目标管满

    local dst_tc = top_color(dst_tube)
    if dst_tc ~= 0 and dst_tc ~= src_tc then return false end  -- 顶层不同色

    -- 倒数量 = min(src_top_n, dst_empty)
    local pour_n = math.min(src_top_n, dst_empty)

    -- 从源管顶部移除 pour_n 个滴（从尾部往前找非零）
    local removed = 0
    for i = CAPACITY, 1, -1 do
        if removed >= pour_n then break end
        if src_tube[i] ~= 0 then
            src_tube[i] = 0
            removed = removed + 1
        end
    end

    -- 添加到目标管（从前往后找空位填入，让液体沉在底部）
    local added = 0
    for i = 1, CAPACITY do
        if added >= pour_n then break end
        if dst_tube[i] == 0 then
            dst_tube[i] = src_tc
            added = added + 1
        end
    end

    return true
end

-- 检查试管是否纯色或空
local function is_pure_or_empty(tube)
    local c = 0
    for i = 1, CAPACITY do
        if tube[i] ~= 0 then
            if c == 0 then
                c = tube[i]
            elseif tube[i] ~= c then
                return false
            end
        end
    end
    return true
end

-- 检查胜利：所有试管纯色或空
local function is_victory(tubes)
    for _, tube in ipairs(tubes) do
        if not is_pure_or_empty(tube) then return false end
    end
    return true
end

--==============================================================================
-- GUI 创建/刷新
--==============================================================================

local function create_main_gui(player, data)
    local screen = player.gui.screen
    if screen[GUI_FRAME] then
        screen[GUI_FRAME].destroy()
    end

    local md = data.module_data
    local tube_count = #md.tubes

    local frame = screen.add({
        type = 'frame',
        name = GUI_FRAME,
        caption = {'amap.watersort_main_caption', {'amap.' .. md.difficulty_label_key}},
        direction = 'vertical'
    })
    frame.force_auto_center()
    frame.style.minimal_width = tube_count * 80 + 60
    frame.style.maximal_width = tube_count * 80 + 100

    local progress = frame.add({
        type = 'label',
        name = GUI_PROGRESS,
        caption = ''
    })
    progress.style.font = 'default-bold'
    progress.style.font_color = {1, 0.84, 0}

    -- 试管横向排列：每个试管是一个 table(1 列 4 行)
    local tube_table = frame.add({
        type = 'table',
        name = GUI_TUBE_TABLE,
        column_count = tube_count
    })
    tube_table.style.horizontal_spacing = 12
    tube_table.style.vertical_spacing = 4
    tube_table.style.top_padding = 6
    tube_table.style.bottom_padding = 6

    local cell_size = 60
    for t = 1, tube_count do
        -- 每管一个 inner table（4 行 1 列）
        local inner = tube_table.add({
            type = 'table',
            column_count = 1
        })
        inner.style.vertical_spacing = 0
        inner.style.horizontal_spacing = 0

        for i = CAPACITY, 1, -1 do  -- 顶部在上方，所以从顶到底
            local c = md.tubes[t][i]
            local btn = inner.add({
                type = 'button',
                name = TUBE_PREFIX .. t .. '_' .. i,
                caption = c == 0 and '' or COLOR_LABEL[c],
                tags = {watersort_tube = true, tube = t},
                mouse_button_filter = {'left'}
            })
            btn.style.minimal_width = cell_size
            btn.style.minimal_height = cell_size
            btn.style.maximal_width = cell_size
            btn.style.maximal_height = cell_size
            btn.style.font = 'default-large-bold'
            btn.style.top_padding = 0
            btn.style.bottom_padding = 0
            if c ~= 0 then
                btn.style.font_color = COLOR_VALUE[c]
            end
        end
    end

    -- 操作按钮：仅重置（按用户要求，无撤销）
    local btn_flow = frame.add({type = 'flow', direction = 'horizontal'})
    btn_flow.style.horizontal_align = 'center'
    btn_flow.style.horizontally_stretchable = true
    btn_flow.style.top_padding = 4

    local reset_btn = btn_flow.add({
        type = 'button',
        name = GUI_RESET_BTN,
        caption = {'amap.watersort_reset'},
        mouse_button_filter = {'left'}
    })
    reset_btn.style.minimal_width = 80

    local hint = frame.add({
        type = 'label',
        caption = {'amap.watersort_hint'}
    })
    hint.style.font = 'default'
    hint.style.font_color = {0.7, 0.7, 0.7}
    hint.style.single_line = false
    hint.style.maximal_width = tube_count * 80 + 60
end

local function refresh_main_gui(player, data)
    local screen = player.gui.screen
    local frame = screen[GUI_FRAME]
    if not frame or not frame.valid then return end

    local md = data.module_data

    local progress = frame[GUI_PROGRESS]
    if progress and progress.valid then
        progress.caption = {'amap.watersort_status', md.colors, md.steps}
    end

    local tube_table = frame[GUI_TUBE_TABLE]
    if not tube_table or not tube_table.valid then return end

    -- 遍历所有试管 inner table
    for _, inner in ipairs(tube_table.children) do
        if inner.valid and #inner.children > 0 then
            -- 从 button tags 找出该 inner 对应的 tube index
            local t = inner.children[1].tags.tube
            if t then
                local is_sel = (md.sel == t)
                -- inner.children 顺序是 CAPACITY→1（顶到底）
                for idx, btn in ipairs(inner.children) do
                    if btn.valid then
                        local i = CAPACITY - idx + 1  -- 实际格索引
                        local c = md.tubes[t][i]
                        -- 选中状态：字母前后加方括号 [A]（颜色不变，避免白字在浅背景上看不清）
                        if c == 0 then
                            btn.caption = ''
                        else
                            btn.caption = is_sel and ('[' .. COLOR_LABEL[c] .. ']') or COLOR_LABEL[c]
                            btn.style.font_color = COLOR_VALUE[c]
                        end
                    end
                end
            end
        end
    end
end

--==============================================================================
-- 钩子实现
--==============================================================================

function M.on_surface_init(surface, player, data, difficulty)
    local diff = M.difficulty_settings[difficulty] or M.difficulty_settings.easy

    local tubes = generate_layout(diff.colors)

    data.module_data = {
        colors = diff.colors,
        tubes = tubes,
        sel = nil,
        steps = 0,
        difficulty = difficulty,
        difficulty_label_key = diff.display_name_key,
        reward_multiplier = diff.reward_multiplier
    }

    data.time_limit = diff.time_limit or M.time_limit_default

    for x = -50, 50 do
        for y = -50, 50 do
            surface.set_tiles{{name = "grass-1", position = {x, y}}}
        end
    end

    local room_half = 5
    for x = -room_half - 1, room_half + 1 do
        for _, y in ipairs({-room_half - 1, room_half + 1}) do
            local e = surface.create_entity({
                name = "stone-wall",
                position = {x = x, y = y},
                force = player.force
            })
            if e then e.minable_flag = false; e.destructible = false end
        end
    end
    for y = -room_half, room_half do
        for _, x in ipairs({-room_half - 1, room_half + 1}) do
            local e = surface.create_entity({
                name = "stone-wall",
                position = {x = x, y = y},
                force = player.force
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
    local force = player.force
    force.manual_mining_speed_modifier = 0

    local top = player.gui.top
    if top['dungeon_coins'] then
        top['dungeon_coins'].destroy()
    end

    create_main_gui(player, data)
    refresh_main_gui(player, data)

    local md = data.module_data
    if md then
        player.print({'amap.watersort_enter', {'amap.' .. md.difficulty_label_key}}, {r = 0, g = 1, b = 0})
    end
    player.print({'amap.watersort_hint'}, {r = 1, g = 1, b = 0})
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

    if is_victory(md.tubes) then
        Instance.set_reward_multiplier(player, md.reward_multiplier or 1.0)
        return 'victory'
    end
    return nil
end

function M.on_gui_click(player, event)
    local element = event.element
    if not element or not element.valid then return end

    local data = Instance.get_data(player.index)
    if not data or not data.active then return end
    local md = data.module_data
    if not md then return end

    local tags = element.tags or {}
    local name = element.name

    -- 1. 试管点击：选中 / 倒水
    if tags.watersort_tube then
        local t = tags.tube

        if md.sel == nil then
            -- 第一次选中：必须非空
            if top_color(md.tubes[t]) == 0 then
                player.print({'amap.watersort_empty_tube'}, {r = 1, g = 1, b = 0})
                return
            end
            md.sel = t
        elseif md.sel == t then
            -- 再次点击同一管 → 取消选中
            md.sel = nil
        else
            -- 已选中 src，点击 dst → 倒水
            local src = md.sel
            local ok = pour(md.tubes, src, t)
            if ok then
                md.steps = md.steps + 1
            else
                player.print({'amap.watersort_cannot_pour'}, {r = 1, g = 0.5, b = 0})
            end
            md.sel = nil
        end
        refresh_main_gui(player, data)
        return
    end

    -- 2. 重置按钮
    if name == GUI_RESET_BTN then
        md.tubes = generate_layout(md.colors)
        md.sel = nil
        md.steps = 0
        create_main_gui(player, data)  -- 重建 GUI（试管数不变但内容全变）
        refresh_main_gui(player, data)
        player.print({'amap.watersort_reset_done'}, {r = 1, g = 1, b = 0})
        return
    end
end

--==============================================================================
-- 注册到框架
--==============================================================================

Instance.register(M.type, M)

--==============================================================================
-- 测试用内部 API 暴露
--==============================================================================

_WATERSORT_INTERNAL = {
    CAPACITY = CAPACITY,
    COLOR_LABEL = COLOR_LABEL,
    COLOR_VALUE = COLOR_VALUE,
    generate_layout = generate_layout,
    top_color = top_color,
    top_count = top_count,
    empty_count = empty_count,
    pour = pour,
    is_pure_or_empty = is_pure_or_empty,
    is_victory = is_victory,
    difficulty_settings = M.difficulty_settings
}

return M
