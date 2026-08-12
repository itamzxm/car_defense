-- maps/amap/instance/modules/sudoku.lua
-- 数独玩法模块
--
-- 玩法类型：sudoku
-- 玩法说明：经典数独的 Factorio GUI 适配版
--   - 由于异星工厂地形不擅长表达数字，本玩法完全用 GUI 面板实现
--   - 玩家进入副本后看到一个小房间（草地+石墙围）和一块全屏数独主面板
--   - 点击空格选中 → 从面板底部固定九宫格选数字填入 → 填入后自动取消选中
--   - 冲突（同行/同列/同宫重复）的数字以红色显示
--   - 全部格子填满且无冲突 → 胜利
--
-- 难度分级：
--   easy   - 4x4 (2x2 宫) - 10 分钟 - 35% 挖空率 - 奖励系数 1.0
--   normal - 6x6 (2x3 宫) - 15 分钟 - 50% 挖空率 - 奖励系数 1.5
--   hard   - 9x9 (3x3 宫) - 20 分钟 - 60% 挖空率 - 奖励系数 2.0
--
-- 数独生成：模板法 + 随机置换（数字/行/列/band/stack）+ 按难度挖空
-- 冲突检测：行/列/宫三重扫描，标记冲突位置集合
--
-- 钩子实现：
--   on_surface_init - 生成草地小房间 + 外围石墙 + 生成数独 puzzle/solution
--   on_enter        - 隐藏框架金币 label + 创建数独主 GUI + 提示玩法
--   on_exit         - 销毁数独主 GUI
--   on_tick         - 静态游戏，无需操作（保留空实现以备扩展）
--   check_victory   - 所有格子非空 + 无冲突 → 胜利（设奖励系数）
--   on_gui_click    - 格子点击（选中/切换选中）+ 数字按钮填入 + 清除选中 + 清空所有

local Instance = require 'maps.amap.instance.instance'

local M = {}

--==============================================================================
-- 元数据
--==============================================================================

M.type = 'sudoku'
M.display_name_key = 'amap.instance_sudoku_name'
M.description_key = 'amap.instance_sudoku_desc'
M.gameplay_desc_key = 'amap.instance_sudoku_gameplay'
M.victory_condition_key = 'amap.instance_sudoku_victory'
M.icon = 'item/electronic-circuit'  -- 电路板图标（网格状，与数独网格呼应）
M.time_limit_default = 15 * 60 * 60  -- 默认 15 分钟（tick），各难度可覆盖

--==============================================================================
-- 难度设置
--==============================================================================
-- recycling_efficiency / max_coins 是框架必填字段（挖币遗留），对数独无意义，填 1 / 0 占位
-- 专属参数（grid_size / box_rows / box_cols / removal_rate / time_limit / reward_multiplier）
-- 放在扩展字段中，由模块自行读取

M.difficulty_settings = {
    easy = {
        name = "easy",
        recycling_efficiency = 1,
        max_coins = 0,
        display_name_key = "dungeon_difficulty_easy",
        grid_size = 4,             -- 4x4
        box_rows = 2,              -- 宫格 2 行
        box_cols = 2,              -- 宫格 2 列（2x2 宫）
        removal_rate = 0.35,       -- 35% 格子挖空
        time_limit = 10 * 60 * 60, -- 10 分钟
        reward_multiplier = 1.0    -- 奖励系数
    },
    normal = {
        name = "normal",
        recycling_efficiency = 1,
        max_coins = 0,
        display_name_key = "dungeon_difficulty_normal",
        grid_size = 6,             -- 6x6
        box_rows = 2,              -- 宫格 2 行
        box_cols = 3,              -- 宫格 3 列（2x3 宫）
        removal_rate = 0.50,       -- 50% 格子挖空
        time_limit = 15 * 60 * 60, -- 15 分钟
        reward_multiplier = 1.0
    },
    hard = {
        name = "hard",
        recycling_efficiency = 1,
        max_coins = 0,
        display_name_key = "dungeon_difficulty_hard",
        grid_size = 9,             -- 9x9 标准数独
        box_rows = 3,              -- 宫格 3 行
        box_cols = 3,              -- 宫格 3 列（3x3 宫）
        removal_rate = 0.60,       -- 60% 格子挖空
        time_limit = 20 * 60 * 60, -- 20 分钟
        reward_multiplier = 1.0
    }
}

--==============================================================================
-- GUI 元素名常量（前缀 dungeon_module_ 防冲突，符合框架约定）
--==============================================================================

local GUI_SUDOKU_FRAME     = 'dungeon_module_sudoku_main_frame'
local GUI_SUDOKU_PROGRESS  = 'dungeon_module_sudoku_progress'
local GUI_SUDOKU_GRID      = 'dungeon_module_sudoku_grid'
local GUI_SUDOKU_CLEAR_BTN = 'dungeon_module_sudoku_clear_btn'
local GUI_SUDOKU_SELECT_LBL = 'dungeon_module_sudoku_select_label'
local GUI_SUDOKU_CLEAR_SEL  = 'dungeon_module_sudoku_clear_sel_btn'
local GUI_SUDOKU_NUMPAD     = 'dungeon_module_sudoku_numpad'

-- 格子按钮 name 前缀：dungeon_module_sudoku_cell_<r>_<c>
local CELL_PREFIX = 'dungeon_module_sudoku_cell_'
-- 数字按钮 name 前缀：dungeon_module_sudoku_num_<n>
local NUM_PREFIX = 'dungeon_module_sudoku_num_'

--==============================================================================
-- 数独模板（完整解）
--==============================================================================
-- 每个尺寸至少 1 个模板，通过随机置换（数字/行/列/band/stack）产生大量变体
-- 模板已验证：每行/每列/每宫内 1..N 各出现一次

local SUDOKU_TEMPLATES = {
    [4] = {
        -- 4x4，2x2 宫
        {
            {1, 2, 3, 4},
            {3, 4, 1, 2},
            {2, 1, 4, 3},
            {4, 3, 2, 1}
        }
    },
    [6] = {
        -- 6x6，2x3 宫（box_rows=2, box_cols=3）
        {
            {1, 2, 3, 4, 5, 6},
            {4, 5, 6, 1, 2, 3},
            {2, 3, 1, 5, 6, 4},
            {5, 6, 4, 2, 3, 1},
            {3, 1, 2, 6, 4, 5},
            {6, 4, 5, 3, 1, 2}
        }
    },
    [9] = {
        -- 9x9 标准数独，3x3 宫
        {
            {1, 2, 3, 4, 5, 6, 7, 8, 9},
            {4, 5, 6, 7, 8, 9, 1, 2, 3},
            {7, 8, 9, 1, 2, 3, 4, 5, 6},
            {2, 3, 1, 5, 6, 4, 8, 9, 7},
            {5, 6, 4, 8, 9, 7, 2, 3, 1},
            {8, 9, 7, 2, 3, 1, 5, 6, 4},
            {3, 1, 2, 6, 4, 5, 9, 7, 8},
            {6, 4, 5, 9, 7, 8, 3, 1, 2},
            {9, 7, 8, 3, 1, 2, 6, 4, 5}
        }
    }
}

--==============================================================================
-- 辅助函数
--==============================================================================

-- Fisher-Yates 洗牌（in-place，返回原表）
local function shuffle(t)
    for i = #t, 2, -1 do
        local j = math.random(i)
        t[i], t[j] = t[j], t[i]
    end
    return t
end

-- 生成 1..n 的随机置换表（num_perm[x] = 该数字映射到的新数字）
local function random_permutation(n)
    local t = {}
    for i = 1, n do t[i] = i end
    return shuffle(t)
end

-- 深拷贝二维网格
local function copy_grid(template, grid_size)
    local grid = {}
    for r = 1, grid_size do
        grid[r] = {}
        for c = 1, grid_size do
            grid[r][c] = template[r][c]
        end
    end
    return grid
end

--==============================================================================
-- 数独生成
--==============================================================================

-- 对完整解做随机置换（保持数独性质）：
--   1. 数字置换（1..N 重新映射）
--   2. 同 band 内行互换 + band 间互换
--   3. 同 stack 内列互换 + stack 间互换
-- 参数：template=模板完整解, grid_size/box_rows/box_cols=网格与宫格参数
-- 返回：置换后的完整解（二维表）
local function permute_solution(template, grid_size, box_rows, box_cols)
    local grid = copy_grid(template, grid_size)

    -- 1. 数字置换
    local num_perm = random_permutation(grid_size)
    for r = 1, grid_size do
        for c = 1, grid_size do
            grid[r][c] = num_perm[grid[r][c]]
        end
    end

    -- 2. 行置换：同 band 内行互换 + band 间互换
    -- band = 行方向的一组宫格，每个 band 含 box_rows 行
    -- 例：9x9 box_rows=3，band 数 = 9/3 = 3，每个 band 3 行
    local num_bands = grid_size / box_rows
    -- 2a. 同 band 内行互换
    for b = 0, num_bands - 1 do
        -- 收集该 band 内的行号
        local row_indices = {}
        for i = 1, box_rows do
            row_indices[i] = b * box_rows + i
        end
        local perm = shuffle(row_indices)
        -- 临时拷贝该 band 的所有行（按原顺序）
        local temp_rows = {}
        for i = 1, box_rows do
            temp_rows[i] = grid[b * box_rows + i]
        end
        -- 按置换写回
        for i = 1, box_rows do
            grid[b * box_rows + i] = temp_rows[perm[i] - b * box_rows]
        end
    end
    -- 2b. band 间互换（整 band 单位）
    local band_indices = {}
    for b = 0, num_bands - 1 do
        band_indices[b + 1] = b
    end
    shuffle(band_indices)
    local new_grid_bands = {}
    for b = 0, num_bands - 1 do
        local src_b = band_indices[b + 1]
        for i = 1, box_rows do
            new_grid_bands[b * box_rows + i] = grid[src_b * box_rows + i]
        end
    end
    grid = new_grid_bands

    -- 3. 列置换：同 stack 内列互换 + stack 间互换
    -- stack = 列方向的一组宫格，每个 stack 含 box_cols 列
    local num_stacks = grid_size / box_cols
    -- 3a. 同 stack 内列互换
    for s = 0, num_stacks - 1 do
        local col_indices = {}
        for i = 1, box_cols do
            col_indices[i] = s * box_cols + i
        end
        local perm = shuffle(col_indices)
        -- 按列拷贝（per-column 跨所有行）
        local temp_cols = {}
        for i = 1, box_cols do
            local col_data = {}
            for r = 1, grid_size do
                col_data[r] = grid[r][s * box_cols + i]
            end
            temp_cols[i] = col_data
        end
        for i = 1, box_cols do
            local src_col = perm[i] - s * box_cols
            for r = 1, grid_size do
                grid[r][s * box_cols + i] = temp_cols[src_col][r]
            end
        end
    end
    -- 3b. stack 间互换
    local stack_indices = {}
    for s = 0, num_stacks - 1 do
        stack_indices[s + 1] = s
    end
    shuffle(stack_indices)
    local new_grid = {}
    for r = 1, grid_size do
        new_grid[r] = {}
        for s = 0, num_stacks - 1 do
            local src_s = stack_indices[s + 1]
            for i = 1, box_cols do
                new_grid[r][s * box_cols + i] = grid[r][src_s * box_cols + i]
            end
        end
    end
    grid = new_grid

    return grid
end

-- 按难度挖空：返回 puzzle（0 表示空格）和 solution（完整解）
local function make_puzzle(solution, grid_size, removal_rate)
    local puzzle = {}
    for r = 1, grid_size do
        puzzle[r] = {}
        for c = 1, grid_size do
            puzzle[r][c] = solution[r][c]
        end
    end

    local total = grid_size * grid_size
    local to_remove = math.floor(total * removal_rate)

    -- 生成所有位置索引并洗牌，取前 to_remove 个挖空
    local positions = {}
    for i = 1, total do positions[i] = i end
    shuffle(positions)

    for i = 1, to_remove do
        local pos = positions[i]
        local r = math.ceil(pos / grid_size)
        local c = (pos - 1) % grid_size + 1
        puzzle[r][c] = 0
    end

    return puzzle
end

-- 生成完整数独（含挖空）
-- 返回 puzzle, solution；若模板缺失返回 nil, nil
local function generate_sudoku(grid_size, box_rows, box_cols, removal_rate)
    local templates = SUDOKU_TEMPLATES[grid_size]
    if not templates then return nil, nil end
    local template = templates[math.random(#templates)]
    local solution = permute_solution(template, grid_size, box_rows, box_cols)
    local puzzle = make_puzzle(solution, grid_size, removal_rate)
    return puzzle, solution
end

--==============================================================================
-- 冲突检测
--==============================================================================
-- 输入：puzzle（预填，0=空）/ user_grid（玩家填入，0=空）/ 网格与宫格参数
-- 返回：冲突位置集合 {["r_c"] = true}

local function get_cell_value(puzzle, user_grid, r, c)
    if puzzle[r][c] ~= 0 then
        return puzzle[r][c], true  -- 预填值，is_pre=true
    end
    return user_grid[r] and user_grid[r][c] or 0, false
end

local function find_conflicts(puzzle, user_grid, grid_size, box_rows, box_cols)
    local conflicts = {}

    -- 行检查：每行内若同一数字出现 ≥2 次，所有出现位置都标冲突
    for r = 1, grid_size do
        local seen = {}  -- seen[v] = c（首次出现的列）
        for c = 1, grid_size do
            local v = get_cell_value(puzzle, user_grid, r, c)
            if v ~= 0 then
                if seen[v] then
                    conflicts[r .. "_" .. c] = true
                    conflicts[r .. "_" .. seen[v]] = true
                else
                    seen[v] = c
                end
            end
        end
    end

    -- 列检查：每列内若同一数字出现 ≥2 次，所有出现位置都标冲突
    for c = 1, grid_size do
        local seen = {}  -- seen[v] = r
        for r = 1, grid_size do
            local v = get_cell_value(puzzle, user_grid, r, c)
            if v ~= 0 then
                if seen[v] then
                    conflicts[r .. "_" .. c] = true
                    conflicts[seen[v] .. "_" .. c] = true
                else
                    seen[v] = r
                end
            end
        end
    end

    -- 宫检查：每个宫格内若同一数字出现 ≥2 次，所有出现位置都标冲突
    local num_band = grid_size / box_rows
    local num_stack = grid_size / box_cols
    for br = 0, num_band - 1 do
        for bc = 0, num_stack - 1 do
            local seen = {}  -- seen[v] = "r_c"
            for r = 1, box_rows do
                for c = 1, box_cols do
                    local gr = br * box_rows + r
                    local gc = bc * box_cols + c
                    local v = get_cell_value(puzzle, user_grid, gr, gc)
                    if v ~= 0 then
                        if seen[v] then
                            conflicts[gr .. "_" .. gc] = true
                            conflicts[seen[v]] = true
                        else
                            seen[v] = gr .. "_" .. gc
                        end
                    end
                end
            end
        end
    end

    return conflicts
end

-- 统计已填格数（预填 + 玩家填入）
local function count_filled(puzzle, user_grid, grid_size)
    local count = 0
    for r = 1, grid_size do
        for c = 1, grid_size do
            local v = get_cell_value(puzzle, user_grid, r, c)
            if v ~= 0 then count = count + 1 end
        end
    end
    return count
end

-- 统计冲突数
local function count_conflicts(conflicts)
    local n = 0
    for _ in pairs(conflicts) do n = n + 1 end
    return n
end

--==============================================================================
-- GUI 创建/刷新
--==============================================================================

-- 创建数独主面板（全屏 frame）
local function create_main_gui(player, data)
    local screen = player.gui.screen
    -- 已存在则先销毁（幂等）
    if screen[GUI_SUDOKU_FRAME] then
        screen[GUI_SUDOKU_FRAME].destroy()
    end

    local md = data.module_data
    local grid_size = md.grid_size

    local frame = screen.add({
        type = 'frame',
        name = GUI_SUDOKU_FRAME,
        caption = {'amap.sudoku_main_caption', grid_size, {'amap.' .. md.difficulty_label_key}},
        direction = 'vertical'
    })
    frame.force_auto_center()
    frame.style.minimal_width = grid_size * 40 + 40
    frame.style.maximal_width = grid_size * 40 + 80

    -- 进度显示
    local progress = frame.add({
        type = 'label',
        name = GUI_SUDOKU_PROGRESS,
        caption = ''
    })
    progress.style.font = 'default-bold'
    progress.style.font_color = {1, 0.84, 0}

    -- 数独网格（用 table 元素，column_count = grid_size 让按钮自动按行排列）
    local grid_table = frame.add({
        type = 'table',
        name = GUI_SUDOKU_GRID,
        column_count = grid_size
    })
    grid_table.style.horizontal_spacing = 2
    grid_table.style.vertical_spacing = 2
    grid_table.style.top_padding = 4
    grid_table.style.bottom_padding = 4

    -- 计算冲突（首次创建时也会刷新颜色）
    local conflicts = find_conflicts(md.puzzle, md.user_grid, grid_size, md.box_rows, md.box_cols)
    md.conflicts = conflicts

    -- 格子尺寸：9x9 用 36px，6x6 用 44px，4x4 用 52px（小网格用大格子更好看）
    local cell_size = grid_size >= 9 and 36 or (grid_size >= 6 and 44 or 52)

    for r = 1, grid_size do
        for c = 1, grid_size do
            local is_pre = md.puzzle[r][c] ~= 0
            local val = is_pre and md.puzzle[r][c] or (md.user_grid[r][c] or 0)
            local key = r .. "_" .. c
            local is_conflict = conflicts[key]

            local btn = grid_table.add({
                type = 'button',
                name = CELL_PREFIX .. key,
                caption = val == 0 and '' or tostring(val),
                tags = {sudoku_cell = true, r = r, c = c},
                mouse_button_filter = {'left'}
            })
            btn.style.minimal_width = cell_size
            btn.style.minimal_height = cell_size
            btn.style.maximal_width = cell_size
            btn.style.maximal_height = cell_size
            btn.style.font = is_pre and 'default-bold' or 'default-large'

            -- 颜色：冲突=红，预填=黑，玩家填=蓝
            if is_conflict then
                btn.style.font_color = {1, 0, 0}
            elseif is_pre then
                btn.style.font_color = {0, 0, 0}
            else
                btn.style.font_color = {0, 0, 1}
            end
        end
    end

    -- 初始化选中状态
    md.selected_r = nil
    md.selected_c = nil

    -- 选中格子提示
    local sel_label = frame.add({
        type = 'label',
        name = GUI_SUDOKU_SELECT_LBL,
        caption = ''
    })
    sel_label.style.font = 'default'
    sel_label.style.font_color = {0, 0.6, 0}
    sel_label.style.top_padding = 4
    sel_label.style.bottom_padding = 2

    -- 固定数字九宫格（3 列，数字位置固定不变，形成肌肉记忆）
    local num_table = frame.add({
        type = 'table',
        name = GUI_SUDOKU_NUMPAD,
        column_count = 3
    })
    num_table.style.horizontal_spacing = 4
    num_table.style.vertical_spacing = 4
    num_table.style.top_padding = 4

    local num_btn_size = 40
    for n = 1, grid_size do
        local btn = num_table.add({
            type = 'button',
            name = NUM_PREFIX .. n,
            caption = tostring(n),
            tags = {sudoku_num = true, n = n},
            mouse_button_filter = {'left'}
        })
        btn.style.minimal_width = num_btn_size
        btn.style.minimal_height = num_btn_size
        btn.style.maximal_width = num_btn_size
        btn.style.maximal_height = num_btn_size
        btn.style.font = 'default-bold'
    end

    -- 操作按钮行：清除选中 + 清空所有
    local btn_flow = frame.add({type = 'flow', direction = 'horizontal'})
    btn_flow.style.horizontal_align = 'center'
    btn_flow.style.horizontally_stretchable = true
    btn_flow.style.top_padding = 6

    local clear_sel_btn = btn_flow.add({
        type = 'button',
        name = GUI_SUDOKU_CLEAR_SEL,
        caption = {'amap.sudoku_clear_sel'},
        mouse_button_filter = {'left'}
    })
    clear_sel_btn.style.minimal_width = 80

    local clear_btn = btn_flow.add({
        type = 'button',
        name = GUI_SUDOKU_CLEAR_BTN,
        caption = {'amap.sudoku_clear_btn'},
        mouse_button_filter = {'left'}
    })
    clear_btn.style.minimal_width = 80

    -- 提示
    local hint = frame.add({
        type = 'label',
        caption = {'amap.sudoku_hint'}
    })
    hint.style.font = 'default'
    hint.style.font_color = {0.7, 0.7, 0.7}
    hint.style.single_line = false
    hint.style.maximal_width = grid_size * 40 + 40
end

-- 刷新数独主面板（进度 + 每个格子的 caption/颜色 + 选中指示）
local function refresh_main_gui(player, data)
    local screen = player.gui.screen
    local frame = screen[GUI_SUDOKU_FRAME]
    if not frame or not frame.valid then return end

    local md = data.module_data
    local grid_size = md.grid_size

    -- 重新计算冲突
    local conflicts = find_conflicts(md.puzzle, md.user_grid, grid_size, md.box_rows, md.box_cols)
    md.conflicts = conflicts

    -- 更新进度 label
    local progress = frame[GUI_SUDOKU_PROGRESS]
    if progress and progress.valid then
        local filled = count_filled(md.puzzle, md.user_grid, grid_size)
        local total = grid_size * grid_size
        local conflict_count = count_conflicts(conflicts)
        progress.caption = {'amap.sudoku_progress', filled, total, conflict_count}
    end

    -- 更新选中指示 label
    local sel_label = frame[GUI_SUDOKU_SELECT_LBL]
    if sel_label and sel_label.valid then
        if md.selected_r and md.selected_c then
            sel_label.caption = {'amap.sudoku_select_label', md.selected_r, md.selected_c}
        else
            sel_label.caption = ''
        end
    end

    -- 更新每个格子
    local grid_table = frame[GUI_SUDOKU_GRID]
    if not grid_table or not grid_table.valid then return end

    local sel_r = md.selected_r
    local sel_c = md.selected_c

    for r = 1, grid_size do
        for c = 1, grid_size do
            local key = r .. "_" .. c
            local btn = grid_table[CELL_PREFIX .. key]
            if btn and btn.valid then
                local is_pre = md.puzzle[r][c] ~= 0
                local val = is_pre and md.puzzle[r][c] or (md.user_grid[r][c] or 0)
                btn.caption = val == 0 and '' or tostring(val)

                local is_conflict = conflicts[key]
                local is_sel = (r == sel_r and c == sel_c)

                if is_conflict then
                    btn.style.font_color = {1, 0, 0}
                elseif is_pre then
                    btn.style.font_color = is_sel and {0, 0.8, 0} or {0, 0, 0}
                elseif is_sel then
                    btn.style.font_color = {0, 0.8, 0}
                else
                    btn.style.font_color = {0, 0, 1}
                end
            end
        end
    end
end

--==============================================================================
-- 钩子实现
--==============================================================================

-- surface 初始化：生成草地小房间 + 外围石墙 + 生成数独 puzzle/solution
function M.on_surface_init(surface, player, data, difficulty)
    local diff = M.difficulty_settings[difficulty] or M.difficulty_settings.easy
    local grid_size = diff.grid_size
    local box_rows = diff.box_rows
    local box_cols = diff.box_cols

    -- 生成数独
    local puzzle, solution = generate_sudoku(grid_size, box_rows, box_cols, diff.removal_rate)
    -- 若模板缺失，至少给个空网格（不应该发生；若发生则 check_victory 会立即判定无空格胜利——故加保护）
    if not puzzle or not solution then
        error("[SUDOKU] No template for grid_size=" .. tostring(grid_size))
    end

    data.module_data = {
        grid_size = grid_size,
        box_rows = box_rows,
        box_cols = box_cols,
        difficulty = difficulty,
        difficulty_label_key = diff.display_name_key,
        puzzle = puzzle,
        solution = solution,
        user_grid = {},
        conflicts = {},
        reward_multiplier = diff.reward_multiplier
    }

    -- 初始化 user_grid 为全 0
    local md = data.module_data
    for r = 1, grid_size do
        md.user_grid[r] = {}
        for c = 1, grid_size do
            md.user_grid[r][c] = 0
        end
    end

    -- 覆盖框架默认 time_limit（用难度专属值）
    data.time_limit = diff.time_limit or M.time_limit_default

    -- 1. 全图铺 grass-1（视觉清爽）
    for x = -50, 50 do
        for y = -50, 50 do
            surface.set_tiles{{name = "grass-1", position = {x, y}}}
        end
    end

    -- 2. 外围石墙围成一个小房间（玩家在房间内操作 GUI，不需要大空间）
    local room_half = 5  -- 11x11 房间
    -- 上下边
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
    -- 左右边
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

    -- 3. 副本常昼，视野清晰
    surface.always_day = true

    -- 4. 让副本 force chart 房间区域（玩家立即可见小房间）
    player.force.chart(surface, {
        {-room_half - 2, -room_half - 2},
        {room_half + 2, room_half + 2}
    })
end

-- 进入副本：隐藏框架金币 label + 创建数独主 GUI + 提示玩法
function M.on_enter(player, data, difficulty)
    local force = player.force
    -- 数独不需要采矿，但保留默认值（不显式设 0，避免覆盖框架其他设置）
    -- 这里仅清空 mining_speed_modifier 防止扫雷残留（实际框架已切 force）
    force.manual_mining_speed_modifier = 0

    local top = player.gui.top

    -- 数独无金币概念，隐藏框架的 coins label
    if top['dungeon_coins'] then
        top['dungeon_coins'].destroy()
    end

    -- 创建数独主面板
    create_main_gui(player, data)

    -- 首次刷新进度显示
    refresh_main_gui(player, data)

    -- 提示玩法说明
    local md = data.module_data
    if md then
        player.print({'amap.sudoku_enter',
                      md.grid_size,
                      {'amap.' .. md.difficulty_label_key}}, {r = 0, g = 1, b = 0})
    end
    player.print({'amap.sudoku_hint'}, {r = 1, g = 1, b = 0})
end

-- 退出副本：销毁数独主 GUI
function M.on_exit(player, data, reason)
    local screen = player.gui.screen
    if screen[GUI_SUDOKU_FRAME] then
        screen[GUI_SUDOKU_FRAME].destroy()
    end
end

-- 每 60 tick：静态游戏，无需操作
-- 保留空实现以备扩展（如未来加计时器刷新、玩家提示等）
function M.on_tick(player, data)
    -- no-op
end

-- 通关检测
function M.check_victory(player, data)
    local md = data.module_data
    if not md then return nil end

    local grid_size = md.grid_size

    -- 1. 检查是否所有格子都填了（预填 + 玩家填）
    for r = 1, grid_size do
        for c = 1, grid_size do
            local v = get_cell_value(md.puzzle, md.user_grid, r, c)
            if v == 0 then
                return nil  -- 还有空格，未完成
            end
        end
    end

    -- 2. 检查是否有冲突
    local conflicts = find_conflicts(md.puzzle, md.user_grid, grid_size, md.box_rows, md.box_cols)
    if count_conflicts(conflicts) > 0 then
        return nil  -- 有冲突，未完成
    end

    -- 3. 完成！设置奖励系数（按难度）
    Instance.set_reward_multiplier(player, md.reward_multiplier or 1.0)
    return 'victory'
end

-- GUI 点击事件
function M.on_gui_click(player, event)
    local element = event.element
    if not element or not element.valid then return end

    local data = Instance.get_data(player.index)
    if not data or not data.active then return end
    local md = data.module_data
    if not md then return end

    local tags = element.tags or {}
    local name = element.name

    -- 1. 数独格子点击 → 选中该格（切换选中 / 取消选中）
    if tags.sudoku_cell then
        local r = tags.r
        local c = tags.c
        -- 预填格不允许选中
        if md.puzzle[r][c] ~= 0 then
            player.print({'amap.sudoku_cell_fixed'}, {r = 1, g = 1, b = 0})
            return
        end
        -- 点击已选中的格子 → 取消选中；否则切换选中
        if md.selected_r == r and md.selected_c == c then
            md.selected_r = nil
            md.selected_c = nil
        else
            md.selected_r = r
            md.selected_c = c
        end
        refresh_main_gui(player, data)
        return
    end

    -- 2. 固定数字按钮点击 → 填入选中格并取消选中
    if tags.sudoku_num then
        local n = tags.n
        if md.selected_r and md.selected_c then
            md.user_grid[md.selected_r][md.selected_c] = n
            md.selected_r = nil
            md.selected_c = nil
            refresh_main_gui(player, data)
        end
        return
    end

    -- 3. "清除选中"按钮 → 清空当前选中格
    if name == GUI_SUDOKU_CLEAR_SEL then
        if md.selected_r and md.selected_c then
            md.user_grid[md.selected_r][md.selected_c] = 0
            md.selected_r = nil
            md.selected_c = nil
            refresh_main_gui(player, data)
        end
        return
    end

    -- 4. "清空所有"按钮 → 清空所有玩家填入的数字 + 取消选中
    if name == GUI_SUDOKU_CLEAR_BTN then
        local grid_size = md.grid_size
        for r = 1, grid_size do
            for c = 1, grid_size do
                md.user_grid[r][c] = 0
            end
        end
        md.selected_r = nil
        md.selected_c = nil
        refresh_main_gui(player, data)
        player.print({'amap.sudoku_cleared'}, {r = 1, g = 1, b = 0})
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
-- Factorio 运行时 (/c 命令) 禁止 require，但可以访问全局变量。
-- 这里把内部纯逻辑函数暴露为全局 _SUDOKU_INTERNAL，供 RCON 测试调用，
-- 验证数独生成、置换、冲突检测等纯逻辑是否正确。
-- 生产环境无副作用（无人调用即不执行）。

_SUDOKU_INTERNAL = {
    SUDOKU_TEMPLATES = SUDOKU_TEMPLATES,
    shuffle = shuffle,
    random_permutation = random_permutation,
    copy_grid = copy_grid,
    permute_solution = permute_solution,
    make_puzzle = make_puzzle,
    generate_sudoku = generate_sudoku,
    get_cell_value = get_cell_value,
    find_conflicts = find_conflicts,
    count_filled = count_filled,
    count_conflicts = count_conflicts,
    difficulty_settings = M.difficulty_settings
}

return M
