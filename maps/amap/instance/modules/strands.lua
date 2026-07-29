-- maps/amap/instance/modules/strands.lua
-- 线索词网玩法模块（中文版）
--
-- 玩法类型：strands
-- 来源：NYT Strands（2024）的中文适配版
-- 核心差异：原版网格是英文字母、连字母成英文词；本版网格是【汉字】，
--           连相邻汉字（上/下/左/右/斜）拼成中文词语，机制完全同构。
--           中文词本来就是"一串汉字"，与英文词是"一串字母"在结构上同构，
--           所以连接规则（相邻、不重复格）一字不改即可用。
--
-- 玩法：给定汉字网格 + 主题，玩家连选相邻汉字拼出属于该主题的词；
--       找全所有主题词 + 一个总词（spangram，串起主题的词）即胜。
--       无失败条件（仅超时），可用清空取消当前连线。
--
-- 难度分级：
--   easy   - 5x5 网格，4 个主题词 + 总词 - 10 分钟 - 奖励系数 1.0
--   normal - 6x6 网格，6 个主题词 + 总词 - 10 分钟 - 奖励系数 1.0
--   hard   - 7x7 网格，8 个主题词 + 总词 - 10 分钟 - 奖励系数 1.0
--   奖励系数固定为 1（不随难度变化）
--
-- 钩子实现：
--   on_surface_init - 草地小房间 + 外围石墙 + 生成汉字网格与题库
--   on_enter        - 隐藏框架金币 label + 创建主 GUI + 提示玩法
--   on_exit         - 销毁主 GUI
--   on_tick         - 静态游戏，空实现
--   check_victory   - 所有主题词 + 总词找到 → 胜利（设奖励系数）
--   on_gui_click    - 连格 / 提交 / 清空 → 比对词表 → 刷新 → 胜利判定

local Instance = require 'maps.amap.instance.instance'

local M = {}

--==============================================================================
-- 元数据
--==============================================================================

M.type = 'strands'
M.display_name_key = 'amap.instance_strands_name'
M.description_key = 'amap.instance_strands_desc'
M.gameplay_desc_key = 'amap.instance_strands_gameplay'
M.victory_condition_key = 'amap.instance_strands_victory'
M.icon = 'item/blueprint'  -- 原生 sprite（按项目规则用原生图标）
M.time_limit_default = 10 * 60 * 60  -- 10 分钟（tick）

--==============================================================================
-- 难度设置
--==============================================================================
-- recycling_efficiency / max_coins 是框架必填字段（挖币遗留），对解谜无意义，填 1 / 0 占位

M.difficulty_settings = {
    easy = {
        name = "easy",
        recycling_efficiency = 1, max_coins = 0,
        display_name_key = "dungeon_difficulty_easy",
        grid_size = 5,
        time_limit = 10 * 60 * 60,
        reward_multiplier = 1.0
    },
    normal = {
        name = "normal",
        recycling_efficiency = 1, max_coins = 0,
        display_name_key = "dungeon_difficulty_normal",
        grid_size = 6,
        time_limit = 10 * 60 * 60,
        reward_multiplier = 1.0
    },
    hard = {
        name = "hard",
        recycling_efficiency = 1, max_coins = 0,
        display_name_key = "dungeon_difficulty_hard",
        grid_size = 7,
        time_limit = 10 * 60 * 60,
        reward_multiplier = 1.0
    }
}

--==============================================================================
-- GUI 元素名常量（前缀 dungeon_module_ 防冲突）
--==============================================================================

local GUI_STRANDS_FRAME   = 'dungeon_module_strands_main_frame'
local GUI_STRANDS_STATUS  = 'dungeon_module_strands_status'
local GUI_STRANDS_GRID    = 'dungeon_module_strands_grid'
local GUI_STRANDS_PATH    = 'dungeon_module_strands_path'
local GUI_STRANDS_FOUND   = 'dungeon_module_strands_found'
local GUI_STRANDS_SUBMIT  = 'dungeon_module_strands_submit'
local GUI_STRANDS_CLEAR   = 'dungeon_module_strands_clear'

local CELL_PREFIX = 'dungeon_module_strands_cell_'

--==============================================================================
-- 题库（中文，按难度分组）
--==============================================================================
-- 每个主题：theme=主题名，spangram=总词（串起主题），words=主题词列表。
-- 网格生成器会把每个词沿随机相邻路径铺进网格（cell 不共享），
-- 剩余空格填干扰汉字。词均可在网格按路径连出，保证有解。

local THEME_BANK = {
    easy = {
        { theme = "水果", spangram = "水果", words = {"苹果", "香蕉", "葡萄", "西瓜"} },
        { theme = "动物", spangram = "动物", words = {"老虎", "兔子", "大象", "熊猫"} },
        { theme = "颜色", spangram = "颜色", words = {"红色", "蓝色", "绿色", "黄色"} },
    },
    normal = {
        { theme = "天气", spangram = "气象", words = {"雷暴", "台风", "冰雹", "霜冻", "彩虹", "雷电"} },
        { theme = "交通", spangram = "交通", words = {"汽车", "火车", "飞机", "轮船", "地铁", "单车"} },
        { theme = "文具", spangram = "文具", words = {"铅笔", "橡皮", "尺子", "书本", "钢笔", "圆规"} },
    },
    hard = {
        { theme = "蔬菜", spangram = "蔬菜", words = {"白菜", "萝卜", "番茄", "土豆", "黄瓜", "茄子", "辣椒", "洋葱"} },
        { theme = "乐器", spangram = "乐器", words = {"钢琴", "吉他", "提琴", "笛子", "铜鼓", "铜号", "铜锣", "铜钵"} },
        { theme = "运动", spangram = "运动", words = {"足球", "篮球", "乒乓", "羽毛球", "网球", "游泳", "跑步", "跳绳"} },
    },
}

-- 干扰汉字池（单个汉字，用于填充空格）
local DISTRACTOR_POOL = "天地人和日月星辰山水风云火金木土田力文武上下中大小多少东西南北前后高低方圆乾坤阴阳"

--==============================================================================
-- 辅助函数
--==============================================================================

-- 把 UTF-8 字符串拆成"每个汉字/字符"的数组（不依赖 utf8 库，手写扫描）
local function chars_of(s)
    local out = {}
    local i = 1
    local n = #s
    while i <= n do
        local b = string.byte(s, i)
        local len = 1
        if b >= 0xF0 then len = 4
        elseif b >= 0xE0 then len = 3
        elseif b >= 0xC0 then len = 2 end
        out[#out + 1] = string.sub(s, i, i + len - 1)
        i = i + len
    end
    return out
end

-- 拷贝并洗牌（返回新表，不改动入参）
local function shuffle_copy(t)
    local c = {}
    for i = 1, #t do c[i] = t[i] end
    for i = #c, 2, -1 do
        local j = math.random(i)
        c[i], c[j] = c[j], c[i]
    end
    return c
end

-- 8 方向相邻偏移
local DIRS = { {-1, -1}, {-1, 0}, {-1, 1}, {0, -1}, {0, 1}, {1, -1}, {1, 0}, {1, 1} }

-- 在网格上随机找一条长度为 len 的自回避相邻路径（所有格为空且在界内）
-- 成功返回路径数组（{{r=,c=}, ...}），失败返回 nil
local function find_path(grid, size, len)
    for _ = 1, 400 do
        local sr = math.random(size)
        local sc = math.random(size)
        if grid[sr][sc] == nil then
            local path = { {r = sr, c = sc} }
            local visited = {}
            visited[sr .. "_" .. sc] = true
            local function dfs(r, c, depth)
                if depth == len then return true end
                local dirs = shuffle_copy(DIRS)
                for _, d in ipairs(dirs) do
                    local nr, nc = r + d[1], c + d[2]
                    if nr >= 1 and nr <= size and nc >= 1 and nc <= size then
                        if grid[nr][nc] == nil and not visited[nr .. "_" .. nc] then
                            visited[nr .. "_" .. nc] = true
                            path[#path + 1] = { r = nr, c = nc }
                            if dfs(nr, nc, depth + 1) then return true end
                            path[#path] = nil
                            visited[nr .. "_" .. nc] = nil
                        end
                    end
                end
                return false
            end
            if dfs(sr, sc, 1) then return path end
        end
    end
    return nil
end

-- 生成一个谜题：返回 grid(2D汉字) / word_paths(词->路径) / theme_set
local function generate_puzzle(difficulty)
    local bank = THEME_BANK[difficulty] or THEME_BANK.easy
    local theme_set = bank[math.random(#bank)]
    local size = (M.difficulty_settings[difficulty] or M.difficulty_settings.easy).grid_size

    -- 干扰池拆成单字数组
    local pool = chars_of(DISTRACTOR_POOL)

    -- 整体重试若干次（网格拥挤时偶发失败，重试即可）
    local attempts = 0
    while attempts < 300 do
        attempts = attempts + 1
        local grid = {}
        for r = 1, size do grid[r] = {} end

        local word_paths = {}
        local ok = true

        -- 先放总词，再放主题词（总词较长，先占路径更易成功）
        local order = { theme_set.spangram }
        for _, w in ipairs(theme_set.words) do order[#order + 1] = w end

        for _, w in ipairs(order) do
            local wchars = chars_of(w)
            local path = find_path(grid, size, #wchars)
            if not path then ok = false; break end
            for i = 1, #path do
                grid[path[i].r][path[i].c] = wchars[i]
            end
            word_paths[w] = path
        end

        if not ok then
            -- 本局铺字失败，重试
        else
            -- 填充干扰汉字
            for r = 1, size do
                for c = 1, size do
                    if grid[r][c] == nil then
                        grid[r][c] = pool[math.random(#pool)]
                    end
                end
            end

            return grid, word_paths, theme_set
        end
    end

    return nil, nil, nil
end

-- 判断两格是否 8 方向相邻
local function is_adjacent(a, b)
    local dr = math.abs(a.r - b.r)
    local dc = math.abs(a.c - b.c)
    return dr <= 1 and dc <= 1 and not (dr == 0 and dc == 0)
end

-- 路径中是否含某格，返回其下标（无则 nil）
local function path_index(path, r, c)
    for i = 1, #path do
        if path[i].r == r and path[i].c == c then return i end
    end
    return nil
end

-- 把一条路径的格子写入 found_cells 集合（用于高亮锁定）
local function mark_found_cells(found_cells, path)
    for _, p in ipairs(path) do
        found_cells[p.r .. "_" .. p.c] = true
    end
end

--==============================================================================
-- GUI 创建 / 刷新
--==============================================================================

local function create_main_gui(player, data)
    local screen = player.gui.screen
    if screen[GUI_STRANDS_FRAME] then
        screen[GUI_STRANDS_FRAME].destroy()
    end

    local md = data.module_data
    local size = md.grid_size

    local frame = screen.add({
        type = 'frame',
        name = GUI_STRANDS_FRAME,
        caption = { 'amap.strands_main_caption', md.theme },
        direction = 'vertical'
    })
    frame.force_auto_center()
    frame.style.minimal_width = size * 42 + 40

    -- 状态栏：主题 · 已找 X/Y
    local status = frame.add({
        type = 'label',
        name = GUI_STRANDS_STATUS,
        caption = { 'amap.strands_status', md.theme, 0, md.total }
    })
    status.style.font = 'default-bold'
    status.style.font_color = {1, 0.84, 0}

    -- 汉字网格
    local grid_table = frame.add({
        type = 'table',
        name = GUI_STRANDS_GRID,
        column_count = size
    })
    grid_table.style.horizontal_spacing = 2
    grid_table.style.vertical_spacing = 2
    grid_table.style.top_padding = 4
    grid_table.style.bottom_padding = 4

    local cell_size = size >= 7 and 38 or (size >= 6 and 42 or 48)
    for r = 1, size do
        for c = 1, size do
            local btn = grid_table.add({
                type = 'button',
                name = CELL_PREFIX .. r .. "_" .. c,
                caption = md.grid[r][c],
                tags = { strands_cell = true, r = r, c = c },
                mouse_button_filter = { 'left' }
            })
            btn.style.minimal_width = cell_size
            btn.style.minimal_height = cell_size
            btn.style.maximal_width = cell_size
            btn.style.maximal_height = cell_size
            btn.style.font = 'default-large'
        end
    end

    -- 当前连线预览
    local path_lbl = frame.add({
        type = 'label',
        name = GUI_STRANDS_PATH,
        caption = ' '
    })
    path_lbl.style.font = 'default'
    path_lbl.style.font_color = {0, 0.8, 0}
    path_lbl.style.top_padding = 4

    -- 操作按钮行
    local btn_flow = frame.add({ type = 'flow', direction = 'horizontal' })
    btn_flow.style.horizontal_align = 'center'
    btn_flow.style.horizontally_stretchable = true
    btn_flow.style.top_padding = 6

    local submit_btn = btn_flow.add({
        type = 'button',
        name = GUI_STRANDS_SUBMIT,
        caption = { 'amap.strands_submit' },
        mouse_button_filter = { 'left' }
    })
    submit_btn.style.minimal_width = 70

    local clear_btn = btn_flow.add({
        type = 'button',
        name = GUI_STRANDS_CLEAR,
        caption = { 'amap.strands_clear' },
        mouse_button_filter = { 'left' }
    })
    clear_btn.style.minimal_width = 70

    -- 已找到的词列表
    local found_lbl = frame.add({
        type = 'label',
        name = GUI_STRANDS_FOUND,
        caption = { 'amap.strands_found' }
    })
    found_lbl.style.font = 'default'
    found_lbl.style.font_color = {0.7, 0.7, 0.7}
    found_lbl.style.top_padding = 4
    found_lbl.style.single_line = false
    found_lbl.style.maximal_width = size * 42 + 40

    -- 玩法说明
    local hint = frame.add({
        type = 'label',
        caption = { 'amap.strands_hint_tip', md.theme }
    })
    hint.style.font = 'default'
    hint.style.font_color = {0.7, 0.7, 0.7}
    hint.style.single_line = false
    hint.style.maximal_width = size * 42 + 40
end

local function refresh_main_gui(player, data)
    local screen = player.gui.screen
    local frame = screen[GUI_STRANDS_FRAME]
    if not frame or not frame.valid then return end

    local md = data.module_data
    local size = md.grid_size

    -- 统计已找词数
    local found_count = 0
    for _, w in ipairs(md.words) do
        if md.found[w] then found_count = found_count + 1 end
    end
    if md.found[md.spangram] then found_count = found_count + 1 end

    local status = frame[GUI_STRANDS_STATUS]
    if status and status.valid then
        status.caption = { 'amap.strands_status', md.theme, found_count, md.total }
    end

    -- 当前连线字符串
    local cand_parts = {}
    for _, p in ipairs(md.path) do
        cand_parts[#cand_parts + 1] = md.grid[p.r][p.c]
    end
    local path_lbl = frame[GUI_STRANDS_PATH]
    if path_lbl and path_lbl.valid then
        path_lbl.caption = { 'amap.strands_path', table.concat(cand_parts) }
    end

    -- 已找到的词
    local found_list = {}
    for _, w in ipairs(md.words) do
        if md.found[w] then found_list[#found_list + 1] = w end
    end
    if md.found[md.spangram] then found_list[#found_list + 1] = "(" .. md.spangram .. ")" end
    local found_lbl = frame[GUI_STRANDS_FOUND]
    if found_lbl and found_lbl.valid then
        found_lbl.caption = { 'amap.strands_found_list', table.concat(found_list, "  ") }
    end

    -- 刷新每个格子颜色
    local grid_table = frame[GUI_STRANDS_GRID]
    if not grid_table or not grid_table.valid then return end

    for r = 1, size do
        for c = 1, size do
            local key = r .. "_" .. c
            local btn = grid_table[CELL_PREFIX .. key]
            if btn and btn.valid then
                local locked = md.found_cells[key]
                local in_path = path_index(md.path, r, c) ~= nil
                if locked then
                    btn.style.font_color = {0, 0.7, 0}        -- 已找：绿
                elseif in_path then
                    btn.style.font_color = {0.9, 0.9, 0}      -- 连线中：黄
                else
                    btn.style.font_color = {0, 0, 0}          -- 默认：黑
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
    local size = diff.grid_size

    local grid, word_paths, theme_set = generate_puzzle(difficulty)
    if not grid or not word_paths or not theme_set then
        error("[STRANDS] puzzle generation failed for difficulty=" .. tostring(difficulty))
    end

    -- 词集合（O(1) 查表）
    local word_set = {}
    for _, w in ipairs(theme_set.words) do word_set[w] = true end
    word_set[theme_set.spangram] = true

    data.module_data = {
        grid_size = size,
        difficulty = difficulty,
        difficulty_label_key = diff.display_name_key,
        theme = theme_set.theme,
        spangram = theme_set.spangram,
        words = theme_set.words,
        word_set = word_set,
        word_paths = word_paths,
        total = #theme_set.words + 1,
        grid = grid,
        found = {},
        found_cells = {},
        path = {},
        reward_multiplier = diff.reward_multiplier
    }

    -- 覆盖框架默认 time_limit
    data.time_limit = diff.time_limit or M.time_limit_default

    -- 1. 全图铺 grass-1
    for x = -50, 50 do
        for y = -50, 50 do
            surface.set_tiles { { name = "grass-1", position = { x, y } } }
        end
    end

    -- 2. 外围石墙围小房间
    local room_half = 5
    for x = -room_half - 1, room_half + 1 do
        for _, y in ipairs({ -room_half - 1, room_half + 1 }) do
            local e = surface.create_entity({
                name = "stone-wall",
                position = { x = x, y = y },
                force = player.force
            })
            if e then e.minable_flag = false; e.destructible = false end
        end
    end
    for y = -room_half, room_half do
        for _, x in ipairs({ -room_half - 1, room_half + 1 }) do
            local e = surface.create_entity({
                name = "stone-wall",
                position = { x = x, y = y },
                force = player.force
            })
            if e then e.minable_flag = false; e.destructible = false end
        end
    end

    -- 3. 常昼
    surface.always_day = true

    -- 4. chart 房间
    player.force.chart(surface, {
        { -room_half - 2, -room_half - 2 },
        { room_half + 2, room_half + 2 }
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
        player.print({ 'amap.strands_enter', md.theme }, { r = 0, g = 1, b = 0 })
    end
end

function M.on_exit(player, data, reason)
    local screen = player.gui.screen
    if screen[GUI_STRANDS_FRAME] then
        screen[GUI_STRANDS_FRAME].destroy()
    end
end

function M.on_tick(player, data)
    -- 静态游戏，空实现
end

function M.check_victory(player, data)
    local md = data.module_data
    if not md then return nil end

    local found_count = 0
    for _, w in ipairs(md.words) do
        if md.found[w] then found_count = found_count + 1 end
    end
    if md.found[md.spangram] then found_count = found_count + 1 end

    if found_count >= md.total then
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

    -- 1. 汉字格子点击 → 构建/调整连线
    if tags.strands_cell then
        local r, c = tags.r, tags.c
        local path = md.path

        if #path == 0 then
            path[1] = { r = r, c = c }
        else
            local last = path[#path]
            if last.r == r and last.c == c then
                path[#path] = nil                       -- 点最后一格 → 退一步
            else
                local idx = path_index(path, r, c)
                if idx then
                    -- 点路径中已有格 → 截断到该格
                    for i = #path, idx + 1, -1 do path[i] = nil end
                elseif is_adjacent(last, { r = r, c = c }) then
                    path[#path + 1] = { r = r, c = c }  -- 相邻空格 → 延伸
                end
                -- 不相邻且不在路径中 → 忽略
            end
        end
        refresh_main_gui(player, data)
        return
    end

    -- 2. 提交 → 比对词表
    if name == GUI_STRANDS_SUBMIT then
        if #md.path == 0 then return end
        local cand_parts = {}
        for _, p in ipairs(md.path) do
            cand_parts[#cand_parts + 1] = md.grid[p.r][p.c]
        end
        local cand = table.concat(cand_parts)

        if md.word_set[cand] and not md.found[cand] then
            md.found[cand] = true
            mark_found_cells(md.found_cells, md.word_paths[cand])
            if cand == md.spangram then
                player.print({ 'amap.strands_spangram_found', cand }, { r = 1, g = 0.8, b = 0 })
            else
                player.print({ 'amap.strands_word_found', cand }, { r = 0, g = 1, b = 0 })
            end
        else
            player.print({ 'amap.strands_invalid' }, { r = 1, g = 0.3, b = 0.3 })
        end

        md.path = {}
        refresh_main_gui(player, data)
        return
    end

    -- 3. 清空 → 清空当前连线
    if name == GUI_STRANDS_CLEAR then
        md.path = {}
        refresh_main_gui(player, data)
        return
    end
end

--==============================================================================
-- 注册到框架
--==============================================================================

Instance.register(M.type, M)

--==============================================================================
-- 测试用内部 API 暴露（供 RCON /c 验证纯逻辑，生产无副作用）
--==============================================================================

_STRANDS_INTERNAL = {
    THEME_BANK = THEME_BANK,
    DISTRACTOR_POOL = DISTRACTOR_POOL,
    chars_of = chars_of,
    shuffle_copy = shuffle_copy,
    find_path = find_path,
    generate_puzzle = generate_puzzle,
    is_adjacent = is_adjacent,
    path_index = path_index,
    difficulty_settings = M.difficulty_settings
}

return M
