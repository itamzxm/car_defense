-- maps/amap/instance/modules/klotski.lua
-- 华容道玩法模块（v2）
--
-- 玩法类型：klotski
-- 玩法说明：经典华容道（滑块拼图）
--   - 由于异星工厂地形不擅长表达数字/方块，本玩法完全用 GUI 面板实现
--   - 玩家进入副本后看到一个小房间（草地+石墙围）和一块全屏华容道棋盘
--   - 点击方块选中，所有可移动到的目标位置会以绿色"·"高亮显示
--   - 点击绿色目标位置，方块直接滑动过去（多格滑动算多步，按经典规则）
--   - 方块只能直线滑动（上下左右任一方向），路径必须全空
--   - 目标：让曹操（2x2 大方块）从棋盘顶部移到底部中央出口
--
-- 难度分级（每难度 5 个内置关卡，进入时随机抽取）：
--   easy   - 5 个简化布局关卡（9 方块）- 10 分钟 - 奖励系数 1.0
--   normal - 5 个横刀立马变体关卡（10 方块）- 15 分钟 - 奖励系数 1.5
--   hard   - 5 个横刀立马变体关卡（10 方块）+ 150 步限制 - 20 分钟 - 奖励系数 2.0
--
-- 关卡数据：15 个布局的 blocks 坐标直接写死在 PUZZLES 表中
--   - 关卡固定：每次进入同一关卡都是同一布局
--   - 关卡可解：所有布局均从已知可解的基础布局走若干步得到，保证有解
--
-- 钩子实现：
--   on_surface_init - 生成草地小房间 + 外围石墙 + 随机抽取关卡模板
--   on_enter        - 隐藏框架金币 label + 创建棋盘 GUI + 提示玩法
--   on_exit         - 销毁棋盘 GUI
--   on_tick         - 静态游戏，无操作
--   check_victory   - 曹操左上角到达出口 → 胜利；步数耗尽 → 失败
--   on_gui_click    - cell 点击：选方块 / 选目标移动 / 取消选中；重置按钮

local Instance = require 'maps.amap.instance.instance'

local M = {}

--==============================================================================
-- 元数据
--==============================================================================

M.type = 'klotski'
M.display_name_key = 'amap.instance_klotski_name'
M.description_key = 'amap.instance_klotski_desc'
M.gameplay_desc_key = 'amap.instance_klotski_gameplay'
M.victory_condition_key = 'amap.instance_klotski_victory'
M.icon = 'item/steel-plate'
M.time_limit_default = 15 * 60 * 60

--==============================================================================
-- 难度设置
--==============================================================================

M.difficulty_settings = {
    easy = {
        name = "easy",
        recycling_efficiency = 1, max_coins = 0,
        display_name_key = "dungeon_difficulty_easy",
        max_moves = nil,
        time_limit = 10 * 60 * 60,
        reward_multiplier = 1.0,
        puzzle_ids = {1, 2, 3, 4, 5}
    },
    normal = {
        name = "normal",
        recycling_efficiency = 1, max_coins = 0,
        display_name_key = "dungeon_difficulty_normal",
        max_moves = nil,
        time_limit = 15 * 60 * 60,
        reward_multiplier = 1.0,
        puzzle_ids = {6, 7, 8, 9, 10}
    },
    hard = {
        name = "hard",
        recycling_efficiency = 1, max_coins = 0,
        display_name_key = "dungeon_difficulty_hard",
        max_moves = 150,
        time_limit = 20 * 60 * 60,
        reward_multiplier = 1.0,
        puzzle_ids = {11, 12, 13, 14, 15}
    }
}

--==============================================================================
-- GUI 元素名常量（前缀 dungeon_module_ 防冲突）
--==============================================================================

local GUI_KL_FRAME = 'dungeon_module_klotski_main_frame'
local GUI_KL_PROGRESS = 'dungeon_module_klotski_progress'
local GUI_KL_BOARD = 'dungeon_module_klotski_board'
local GUI_KL_SELECTED = 'dungeon_module_klotski_selected'
local GUI_KL_RESET = 'dungeon_module_klotski_reset'
local CELL_PREFIX = 'dungeon_module_klotski_cell_'

-- cell 尺寸（v2 调大）
local CELL_SIZE = 65

--==============================================================================
-- 15 个内置关卡模板（blocks 坐标直接写死，不再程序化生成）
--==============================================================================
-- 坐标系：row 1..5（上到下），col 1..4（左到右）
-- block 字段：id（唯一）/ name（用于显示与识别曹操）/ row/col（左上角坐标）/ w/h（宽高）/ type（决定颜色）
-- 胜利条件：name='cao' 的 block 左上角 == (4, 2)
-- 关卡固定：每次进入同一 id 都是同一布局
-- 关卡可解：所有布局均从已知可解的基础布局走若干步得到，保证有解
--   easy   - 9 方块简化布局
--   normal - 10 方块横刀立马变体
--   hard   - 10 方块横刀立马变体（扰动更多）

local PUZZLES = {
    -- easy（5 个，9 方块简化布局）
    {id=1,  blocks={{id=1, name='cao', row=1, col=2, w=2, h=2, type='cao'}, {id=2, name='soldier', row=1, col=1, w=1, h=1, type='soldier'}, {id=3, name='soldier', row=1, col=4, w=1, h=1, type='soldier'}, {id=4, name='soldier', row=2, col=1, w=1, h=1, type='soldier'}, {id=5, name='soldier', row=2, col=4, w=1, h=1, type='soldier'}, {id=6, name='zhang', row=3, col=2, w=1, h=2, type='general_v'}, {id=7, name='zhao', row=3, col=4, w=1, h=2, type='general_v'}, {id=8, name='soldier', row=5, col=2, w=1, h=1, type='soldier'}, {id=9, name='soldier', row=5, col=3, w=1, h=1, type='soldier'}}},
    {id=2,  blocks={{id=1, name='cao', row=2, col=2, w=2, h=2, type='cao'}, {id=2, name='soldier', row=1, col=2, w=1, h=1, type='soldier'}, {id=3, name='soldier', row=1, col=4, w=1, h=1, type='soldier'}, {id=4, name='soldier', row=2, col=1, w=1, h=1, type='soldier'}, {id=5, name='soldier', row=2, col=4, w=1, h=1, type='soldier'}, {id=6, name='zhang', row=3, col=1, w=1, h=2, type='general_v'}, {id=7, name='zhao', row=3, col=4, w=1, h=2, type='general_v'}, {id=8, name='soldier', row=5, col=1, w=1, h=1, type='soldier'}, {id=9, name='soldier', row=5, col=3, w=1, h=1, type='soldier'}}},
    {id=3,  blocks={{id=1, name='cao', row=2, col=2, w=2, h=2, type='cao'}, {id=2, name='soldier', row=1, col=1, w=1, h=1, type='soldier'}, {id=3, name='soldier', row=1, col=4, w=1, h=1, type='soldier'}, {id=4, name='soldier', row=2, col=1, w=1, h=1, type='soldier'}, {id=5, name='soldier', row=2, col=4, w=1, h=1, type='soldier'}, {id=6, name='zhang', row=4, col=1, w=1, h=2, type='general_v'}, {id=7, name='zhao', row=3, col=4, w=1, h=2, type='general_v'}, {id=8, name='soldier', row=4, col=2, w=1, h=1, type='soldier'}, {id=9, name='soldier', row=4, col=3, w=1, h=1, type='soldier'}}},
    {id=4,  blocks={{id=1, name='cao', row=1, col=2, w=2, h=2, type='cao'}, {id=2, name='soldier', row=1, col=1, w=1, h=1, type='soldier'}, {id=3, name='soldier', row=1, col=4, w=1, h=1, type='soldier'}, {id=4, name='soldier', row=2, col=1, w=1, h=1, type='soldier'}, {id=5, name='soldier', row=2, col=4, w=1, h=1, type='soldier'}, {id=6, name='zhang', row=3, col=1, w=1, h=2, type='general_v'}, {id=7, name='zhao', row=4, col=4, w=1, h=2, type='general_v'}, {id=8, name='soldier', row=5, col=2, w=1, h=1, type='soldier'}, {id=9, name='soldier', row=3, col=2, w=1, h=1, type='soldier'}}},
    {id=5,  blocks={{id=1, name='cao', row=1, col=2, w=2, h=2, type='cao'}, {id=2, name='soldier', row=1, col=1, w=1, h=1, type='soldier'}, {id=3, name='soldier', row=1, col=4, w=1, h=1, type='soldier'}, {id=4, name='soldier', row=2, col=1, w=1, h=1, type='soldier'}, {id=5, name='soldier', row=2, col=4, w=1, h=1, type='soldier'}, {id=6, name='zhang', row=3, col=1, w=1, h=2, type='general_v'}, {id=7, name='zhao', row=3, col=4, w=1, h=2, type='general_v'}, {id=8, name='soldier', row=5, col=1, w=1, h=1, type='soldier'}, {id=9, name='soldier', row=5, col=4, w=1, h=1, type='soldier'}}},
    -- normal（5 个，10 方块横刀立马变体）
    {id=6,  blocks={{id=1, name='cao', row=1, col=2, w=2, h=2, type='cao'}, {id=2, name='zhang', row=1, col=1, w=1, h=2, type='general_v'}, {id=3, name='zhao', row=1, col=4, w=1, h=2, type='general_v'}, {id=4, name='ma', row=3, col=1, w=1, h=2, type='general_v'}, {id=5, name='huang', row=3, col=4, w=1, h=2, type='general_v'}, {id=6, name='guan', row=3, col=2, w=2, h=1, type='general_h'}, {id=7, name='soldier', row=4, col=2, w=1, h=1, type='soldier'}, {id=8, name='soldier', row=5, col=2, w=1, h=1, type='soldier'}, {id=9, name='soldier', row=5, col=1, w=1, h=1, type='soldier'}, {id=10, name='soldier', row=5, col=4, w=1, h=1, type='soldier'}}},
    {id=7,  blocks={{id=1, name='cao', row=1, col=2, w=2, h=2, type='cao'}, {id=2, name='zhang', row=1, col=1, w=1, h=2, type='general_v'}, {id=3, name='zhao', row=1, col=4, w=1, h=2, type='general_v'}, {id=4, name='ma', row=4, col=1, w=1, h=2, type='general_v'}, {id=5, name='huang', row=4, col=4, w=1, h=2, type='general_v'}, {id=6, name='guan', row=3, col=1, w=2, h=1, type='general_h'}, {id=7, name='soldier', row=4, col=2, w=1, h=1, type='soldier'}, {id=8, name='soldier', row=5, col=3, w=1, h=1, type='soldier'}, {id=9, name='soldier', row=5, col=2, w=1, h=1, type='soldier'}, {id=10, name='soldier', row=3, col=4, w=1, h=1, type='soldier'}}},
    {id=8,  blocks={{id=1, name='cao', row=1, col=2, w=2, h=2, type='cao'}, {id=2, name='zhang', row=1, col=1, w=1, h=2, type='general_v'}, {id=3, name='zhao', row=1, col=4, w=1, h=2, type='general_v'}, {id=4, name='ma', row=3, col=1, w=1, h=2, type='general_v'}, {id=5, name='huang', row=3, col=4, w=1, h=2, type='general_v'}, {id=6, name='guan', row=3, col=2, w=2, h=1, type='general_h'}, {id=7, name='soldier', row=4, col=2, w=1, h=1, type='soldier'}, {id=8, name='soldier', row=4, col=3, w=1, h=1, type='soldier'}, {id=9, name='soldier', row=5, col=2, w=1, h=1, type='soldier'}, {id=10, name='soldier', row=5, col=3, w=1, h=1, type='soldier'}}},
    {id=9,  blocks={{id=1, name='cao', row=1, col=2, w=2, h=2, type='cao'}, {id=2, name='zhang', row=1, col=1, w=1, h=2, type='general_v'}, {id=3, name='zhao', row=1, col=4, w=1, h=2, type='general_v'}, {id=4, name='ma', row=3, col=1, w=1, h=2, type='general_v'}, {id=5, name='huang', row=4, col=4, w=1, h=2, type='general_v'}, {id=6, name='guan', row=3, col=2, w=2, h=1, type='general_h'}, {id=7, name='soldier', row=5, col=3, w=1, h=1, type='soldier'}, {id=8, name='soldier', row=4, col=2, w=1, h=1, type='soldier'}, {id=9, name='soldier', row=5, col=1, w=1, h=1, type='soldier'}, {id=10, name='soldier', row=4, col=3, w=1, h=1, type='soldier'}}},
    {id=10, blocks={{id=1, name='cao', row=1, col=2, w=2, h=2, type='cao'}, {id=2, name='zhang', row=1, col=1, w=1, h=2, type='general_v'}, {id=3, name='zhao', row=1, col=4, w=1, h=2, type='general_v'}, {id=4, name='ma', row=4, col=1, w=1, h=2, type='general_v'}, {id=5, name='huang', row=4, col=4, w=1, h=2, type='general_v'}, {id=6, name='guan', row=3, col=1, w=2, h=1, type='general_h'}, {id=7, name='soldier', row=5, col=3, w=1, h=1, type='soldier'}, {id=8, name='soldier', row=4, col=2, w=1, h=1, type='soldier'}, {id=9, name='soldier', row=5, col=2, w=1, h=1, type='soldier'}, {id=10, name='soldier', row=3, col=3, w=1, h=1, type='soldier'}}},
    -- hard（5 个，10 方块横刀立马变体，扰动更多）
    {id=11, blocks={{id=1, name='cao', row=1, col=1, w=2, h=2, type='cao'}, {id=2, name='zhang', row=3, col=1, w=1, h=2, type='general_v'}, {id=3, name='zhao', row=1, col=4, w=1, h=2, type='general_v'}, {id=4, name='ma', row=3, col=2, w=1, h=2, type='general_v'}, {id=5, name='huang', row=4, col=4, w=1, h=2, type='general_v'}, {id=6, name='guan', row=3, col=3, w=2, h=1, type='general_h'}, {id=7, name='soldier', row=5, col=2, w=1, h=1, type='soldier'}, {id=8, name='soldier', row=4, col=3, w=1, h=1, type='soldier'}, {id=9, name='soldier', row=5, col=1, w=1, h=1, type='soldier'}, {id=10, name='soldier', row=5, col=3, w=1, h=1, type='soldier'}}},
    {id=12, blocks={{id=1, name='cao', row=1, col=2, w=2, h=2, type='cao'}, {id=2, name='zhang', row=1, col=1, w=1, h=2, type='general_v'}, {id=3, name='zhao', row=2, col=4, w=1, h=2, type='general_v'}, {id=4, name='ma', row=4, col=1, w=1, h=2, type='general_v'}, {id=5, name='huang', row=4, col=4, w=1, h=2, type='general_v'}, {id=6, name='guan', row=3, col=1, w=2, h=1, type='general_h'}, {id=7, name='soldier', row=4, col=2, w=1, h=1, type='soldier'}, {id=8, name='soldier', row=4, col=3, w=1, h=1, type='soldier'}, {id=9, name='soldier', row=5, col=2, w=1, h=1, type='soldier'}, {id=10, name='soldier', row=5, col=3, w=1, h=1, type='soldier'}}},
    {id=13, blocks={{id=1, name='cao', row=1, col=2, w=2, h=2, type='cao'}, {id=2, name='zhang', row=1, col=1, w=1, h=2, type='general_v'}, {id=3, name='zhao', row=1, col=4, w=1, h=2, type='general_v'}, {id=4, name='ma', row=4, col=1, w=1, h=2, type='general_v'}, {id=5, name='huang', row=3, col=4, w=1, h=2, type='general_v'}, {id=6, name='guan', row=3, col=1, w=2, h=1, type='general_h'}, {id=7, name='soldier', row=5, col=3, w=1, h=1, type='soldier'}, {id=8, name='soldier', row=4, col=2, w=1, h=1, type='soldier'}, {id=9, name='soldier', row=5, col=2, w=1, h=1, type='soldier'}, {id=10, name='soldier', row=5, col=4, w=1, h=1, type='soldier'}}},
    {id=14, blocks={{id=1, name='cao', row=1, col=2, w=2, h=2, type='cao'}, {id=2, name='zhang', row=1, col=1, w=1, h=2, type='general_v'}, {id=3, name='zhao', row=1, col=4, w=1, h=2, type='general_v'}, {id=4, name='ma', row=3, col=1, w=1, h=2, type='general_v'}, {id=5, name='huang', row=3, col=4, w=1, h=2, type='general_v'}, {id=6, name='guan', row=3, col=2, w=2, h=1, type='general_h'}, {id=7, name='soldier', row=4, col=3, w=1, h=1, type='soldier'}, {id=8, name='soldier', row=5, col=3, w=1, h=1, type='soldier'}, {id=9, name='soldier', row=5, col=2, w=1, h=1, type='soldier'}, {id=10, name='soldier', row=5, col=4, w=1, h=1, type='soldier'}}},
    {id=15, blocks={{id=1, name='cao', row=1, col=1, w=2, h=2, type='cao'}, {id=2, name='zhang', row=3, col=1, w=1, h=2, type='general_v'}, {id=3, name='zhao', row=1, col=4, w=1, h=2, type='general_v'}, {id=4, name='ma', row=4, col=2, w=1, h=2, type='general_v'}, {id=5, name='huang', row=4, col=4, w=1, h=2, type='general_v'}, {id=6, name='guan', row=3, col=3, w=2, h=1, type='general_h'}, {id=7, name='soldier', row=5, col=1, w=1, h=1, type='soldier'}, {id=8, name='soldier', row=4, col=3, w=1, h=1, type='soldier'}, {id=9, name='soldier', row=3, col=2, w=1, h=1, type='soldier'}, {id=10, name='soldier', row=5, col=3, w=1, h=1, type='soldier'}}},
}

local function find_puzzle(id)
    for _, p in ipairs(PUZZLES) do
        if p.id == id then return p end
    end
    return nil
end

--==============================================================================
-- 方块显示样式
--==============================================================================

local BLOCK_DISPLAY = {
    cao = '曹',
    zhang = '张',
    zhao = '赵',
    ma = '马',
    huang = '黄',
    guan = '关',
    soldier = '兵',
}

local BLOCK_COLOR = {
    cao = {1, 0.84, 0},          -- 金色（曹操特殊）
    general_v = {0.4, 0.4, 1},    -- 蓝色（竖将）
    general_h = {0.4, 1, 0.4},    -- 绿色（横将关羽）
    soldier = {0.7, 0.7, 0.7},   -- 灰色（兵）
}

local BLOCK_FONT = {
    cao = 'default-large-bold',
    general_v = 'default-bold',
    general_h = 'default-bold',
    soldier = 'default',
}

-- 可达目标的标记（绿色"·"，提示玩家点这里）
local TARGET_MARKER = '·'
local TARGET_COLOR = {0.2, 1, 0.2}

--==============================================================================
-- 辅助函数
--==============================================================================

local function find_block(blocks, id)
    for _, b in ipairs(blocks) do
        if b.id == id then return b end
    end
    return nil
end

local function find_block_by_name(blocks, name)
    for _, b in ipairs(blocks) do
        if b.name == name then return b end
    end
    return nil
end

-- 矩形重叠检测（AABB）
local function rects_overlap(r1, c1, w1, h1, r2, c2, w2, h2)
    return r1 < r2 + h2 and r1 + h1 > r2 and c1 < c2 + w2 and c1 + w1 > c2
end

-- 找覆盖 (r, c) 的 block
local function get_cell_block(blocks, r, c)
    for _, b in ipairs(blocks) do
        if r >= b.row and r < b.row + b.h and c >= b.col and c < b.col + b.w then
            return b
        end
    end
    return nil
end

-- 检查 block_id 在 (dr, dc) 方向滑动 1 格是否可移动
local function can_move(blocks, block_id, dr, dc, rows, cols)
    local block = find_block(blocks, block_id)
    if not block then return false end
    local new_row = block.row + dr
    local new_col = block.col + dc
    if new_row < 1 then return false end
    if new_col < 1 then return false end
    if new_row + block.h - 1 > rows then return false end
    if new_col + block.w - 1 > cols then return false end
    for _, other in ipairs(blocks) do
        if other.id ~= block_id then
            if rects_overlap(new_row, new_col, block.w, block.h,
                             other.row, other.col, other.w, other.h) then
                return false
            end
        end
    end
    return true
end

-- 胜利检测：曹操（name='cao'）左上角是否到达出口位置
local function check_victory_state(blocks, exit_row, exit_col)
    local cao = find_block_by_name(blocks, 'cao')
    if not cao then return false end
    return cao.row == exit_row and cao.col == exit_col
end

-- 深拷贝 blocks
local function copy_blocks(blocks)
    local out = {}
    for i, b in ipairs(blocks) do
        out[i] = {id=b.id, name=b.name, row=b.row, col=b.col, w=b.w, h=b.h, type=b.type}
    end
    return out
end

-- 计算选中方块的所有可移动目标 cells
-- 返回 {["r_c"] = {new_row=, new_col=, steps=}} 表
-- 对每个方向（上下左右），尝试滑动 1..N 格，若 can_move 返回 true，把该位置 block 覆盖的所有 cell 加入 targets
local function compute_reachable_targets(blocks, block_id, rows, cols)
    local targets = {}
    local block = find_block(blocks, block_id)
    if not block then return targets end

    local dirs = {{-1, 0}, {1, 0}, {0, -1}, {0, 1}}
    for _, d in ipairs(dirs) do
        local dr, dc = d[1], d[2]
        for steps = 1, math.max(rows, cols) do
            local new_row = block.row + dr * steps
            local new_col = block.col + dc * steps
            -- 边界检查
            if new_row < 1 or new_col < 1 then break end
            if new_row + block.h - 1 > rows or new_col + block.w - 1 > cols then break end
            -- 与其他 block 重叠检查
            local blocked = false
            for _, other in ipairs(blocks) do
                if other.id ~= block_id then
                    if rects_overlap(new_row, new_col, block.w, block.h,
                                     other.row, other.col, other.w, other.h) then
                        blocked = true
                        break
                    end
                end
            end
            if blocked then break end
            -- 该 steps 可达，把 block 覆盖的所有 cell 加入 targets
            -- 只保留每个 cell 的最小 steps（先到先得），让玩家点近 cell 时方块滑最少格数
            for r = new_row, new_row + block.h - 1 do
                for c = new_col, new_col + block.w - 1 do
                    local key = r .. '_' .. c
                    if not targets[key] then
                        targets[key] = {new_row = new_row, new_col = new_col, steps = steps}
                    end
                end
            end
        end
    end
    return targets
end

--==============================================================================
-- GUI 创建/刷新
--==============================================================================

local function create_main_gui(player, data)
    local screen = player.gui.screen
    if screen[GUI_KL_FRAME] then
        screen[GUI_KL_FRAME].destroy()
    end

    local md = data.module_data
    local rows = md.rows
    local cols = md.cols

    local frame = screen.add({
        type = 'frame',
        name = GUI_KL_FRAME,
        caption = {'amap.klotski_main_caption', {'amap.' .. md.difficulty_label_key}, md.puzzle_id},
        direction = 'vertical'
    })
    frame.force_auto_center()
    frame.style.minimal_width = cols * CELL_SIZE + 40
    frame.style.maximal_width = cols * CELL_SIZE + 80

    -- 进度（步数 / 限制 / 关卡 id）
    local progress = frame.add({
        type = 'label',
        name = GUI_KL_PROGRESS,
        caption = ''
    })
    progress.style.font = 'default-bold'
    progress.style.font_color = {1, 0.84, 0}

    -- 已选中提示
    local selected_label = frame.add({
        type = 'label',
        name = GUI_KL_SELECTED,
        caption = ''
    })
    selected_label.style.font = 'default'

    -- 棋盘 table
    local board = frame.add({
        type = 'table',
        name = GUI_KL_BOARD,
        column_count = cols
    })
    board.style.horizontal_spacing = 2
    board.style.vertical_spacing = 2
    board.style.top_padding = 4
    board.style.bottom_padding = 4

    for r = 1, rows do
        for c = 1, cols do
            local btn = board.add({
                type = 'button',
                name = CELL_PREFIX .. r .. '_' .. c,
                caption = '',
                tags = {klotski_cell = true, r = r, c = c},
                mouse_button_filter = {'left'}
            })
            btn.style.minimal_width = CELL_SIZE
            btn.style.minimal_height = CELL_SIZE
            btn.style.maximal_width = CELL_SIZE
            btn.style.maximal_height = CELL_SIZE
        end
    end

    -- 重置按钮（去掉方向键，只保留重置）
    local btn_flow = frame.add({type = 'flow', direction = 'horizontal'})
    btn_flow.style.horizontal_align = 'center'
    btn_flow.style.horizontally_stretchable = true
    btn_flow.style.top_padding = 6

    local reset_btn = btn_flow.add({
        type = 'button', name = GUI_KL_RESET,
        caption = {'amap.klotski_reset'},
        tags = {klotski_reset = true},
        mouse_button_filter = {'left'}
    })
    reset_btn.style.minimal_width = 120

    -- 提示
    local hint = frame.add({
        type = 'label',
        caption = {'amap.klotski_hint'}
    })
    hint.style.font = 'default'
    hint.style.font_color = {0.7, 0.7, 0.7}
    hint.style.single_line = false
    hint.style.maximal_width = cols * CELL_SIZE + 40
end

-- 刷新棋盘显示（步数 + 选中提示 + 每个 cell 的 caption/颜色 + 可达目标高亮）
local function refresh_main_gui(player, data)
    local screen = player.gui.screen
    local frame = screen[GUI_KL_FRAME]
    if not frame or not frame.valid then return end

    local md = data.module_data
    local rows = md.rows
    local cols = md.cols

    -- 计算选中方块的可移动目标 cells
    local targets = {}
    if md.selected_block_id then
        targets = compute_reachable_targets(md.blocks, md.selected_block_id, rows, cols)
    end
    md.reachable_targets = targets

    -- 更新步数
    local progress = frame[GUI_KL_PROGRESS]
    if progress and progress.valid then
        local moves = md.move_count or 0
        local max_moves = md.max_moves
        if max_moves then
            progress.caption = {'amap.klotski_moves_limit', moves, max_moves}
        else
            progress.caption = {'amap.klotski_moves', moves}
        end
    end

    -- 更新选中提示
    local sel_label = frame[GUI_KL_SELECTED]
    if sel_label and sel_label.valid then
        if md.selected_block_id then
            local block = find_block(md.blocks, md.selected_block_id)
            if block then
                local display_name = BLOCK_DISPLAY[block.name] or '?'
                sel_label.caption = {'amap.klotski_selected', display_name}
                sel_label.style.font_color = {1, 0.84, 0}
            else
                md.selected_block_id = nil
                sel_label.caption = {'amap.klotski_no_selection'}
                sel_label.style.font_color = {0.7, 0.7, 0.7}
            end
        else
            sel_label.caption = {'amap.klotski_no_selection'}
            sel_label.style.font_color = {0.7, 0.7, 0.7}
        end
    end

    -- 更新每个 cell
    local board = frame[GUI_KL_BOARD]
    if not board or not board.valid then return end

    for r = 1, rows do
        for c = 1, cols do
            local btn = board[CELL_PREFIX .. r .. '_' .. c]
            if btn and btn.valid then
                local key = r .. '_' .. c
                local block = get_cell_block(md.blocks, r, c)
                if block then
                    -- 该 cell 是某个 block 的一部分
                    btn.caption = BLOCK_DISPLAY[block.name] or '?'
                    btn.style.font = BLOCK_FONT[block.type] or 'default'
                    -- 选中方块：白色字
                    if md.selected_block_id == block.id then
                        btn.style.font_color = {1, 1, 1}
                    else
                        btn.style.font_color = BLOCK_COLOR[block.type] or {1, 1, 1}
                    end
                elseif targets[key] then
                    -- 该 cell 是选中方块的可移动目标位置
                    btn.caption = TARGET_MARKER
                    btn.style.font = 'default-large-bold'
                    btn.style.font_color = TARGET_COLOR
                else
                    -- 空格（非目标）
                    btn.caption = ''
                    btn.style.font = 'default'
                    btn.style.font_color = {0.3, 0.3, 0.3}
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

    -- 从该难度的关卡列表中随机抽取一个 puzzle_id
    local puzzle_ids = diff.puzzle_ids or {1}
    local puzzle_id = puzzle_ids[math.random(#puzzle_ids)]
    local puzzle = find_puzzle(puzzle_id)
    if not puzzle then
        puzzle = PUZZLES[1]
        puzzle_id = puzzle.id
    end

    -- 直接使用写死的 blocks 坐标（深拷贝，避免重置时污染原模板）
    local blocks = copy_blocks(puzzle.blocks)

    data.module_data = {
        rows = 5,
        cols = 4,
        exit_row = 4,
        exit_col = 2,
        blocks = blocks,
        selected_block_id = nil,
        reachable_targets = {},
        move_count = 0,
        max_moves = diff.max_moves,
        difficulty = difficulty,
        difficulty_label_key = diff.display_name_key,
        reward_multiplier = diff.reward_multiplier,
        puzzle_id = puzzle_id
    }

    data.time_limit = diff.time_limit or M.time_limit_default

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
    local force = player.force
    force.manual_mining_speed_modifier = 0

    local top = player.gui.top
    if top['dungeon_coins'] then top['dungeon_coins'].destroy() end

    create_main_gui(player, data)
    refresh_main_gui(player, data)

    local md = data.module_data
    if md then
        player.print({'amap.klotski_enter',
                      {'amap.' .. md.difficulty_label_key},
                      md.puzzle_id}, {r = 0, g = 1, b = 0})
    end
    player.print({'amap.klotski_hint'}, {r = 1, g = 1, b = 0})
end

function M.on_exit(player, data, reason)
    local screen = player.gui.screen
    if screen[GUI_KL_FRAME] then
        screen[GUI_KL_FRAME].destroy()
    end
end

function M.on_tick(player, data)
    -- 静态游戏，无操作
end

function M.check_victory(player, data)
    local md = data.module_data
    if not md then return nil end

    -- 步数限制：步数耗尽 → 失败
    if md.max_moves and md.move_count >= md.max_moves then
        if not check_victory_state(md.blocks, md.exit_row, md.exit_col) then
            return 'defeat'
        end
    end

    -- 胜利检测
    if check_victory_state(md.blocks, md.exit_row, md.exit_col) then
        -- 奖励系数固定 1.0（2026-08-10 用户决策）
        Instance.set_reward_multiplier(player, 1.0)
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

    -- 1. 棋盘 cell 点击
    if tags.klotski_cell then
        local r = tags.r
        local c = tags.c
        local key = r .. '_' .. c
        local clicked_block = get_cell_block(md.blocks, r, c)

        -- 情况 A：点击的是选中方块自己 → 取消选中
        if md.selected_block_id and clicked_block and clicked_block.id == md.selected_block_id then
            md.selected_block_id = nil
            refresh_main_gui(player, data)
            return
        end

        -- 情况 B：已选中方块，且点击的是可达目标 cell → 移动方块到目标
        if md.selected_block_id and md.reachable_targets and md.reachable_targets[key] then
            local target = md.reachable_targets[key]
            local block = find_block(md.blocks, md.selected_block_id)
            if block then
                -- 计算实际移动格数（按经典规则每格 1 步）
                local dr = target.new_row - block.row
                local dc = target.new_col - block.col
                local steps = math.abs(dr) + math.abs(dc)
                -- 更新位置
                block.row = target.new_row
                block.col = target.new_col
                md.move_count = md.move_count + steps
                md.selected_block_id = nil
                refresh_main_gui(player, data)
                return
            end
        end

        -- 情况 C：点击的是另一个方块 → 选中该方块
        if clicked_block then
            md.selected_block_id = clicked_block.id
            refresh_main_gui(player, data)
            return
        end

        -- 情况 D：点击的是空格但不是可达目标 → 提示无法到达
        if md.selected_block_id then
            player.print({'amap.klotski_unreachable'}, {r = 1, g = 0.5, b = 0})
            return
        end

        -- 情况 E：未选中方块且点击空格 → 无操作（或提示）
        return
    end

    -- 2. 重置按钮：恢复当前关卡到初始布局（用同一 puzzle_id）
    if tags.klotski_reset then
        local puzzle = find_puzzle(md.puzzle_id)
        if puzzle then
            md.blocks = copy_blocks(puzzle.blocks)
            md.selected_block_id = nil
            md.move_count = 0
            refresh_main_gui(player, data)
            player.print({'amap.klotski_reset_done'}, {r = 1, g = 1, b = 0})
        end
        return
    end
end

--==============================================================================
-- 注册到框架
--==============================================================================

Instance.register(M.type, M)

--==============================================================================
-- 测试用内部 API 暴露（供 RCON /c 访问）
--==============================================================================

_KLOTSKI_INTERNAL = {
    PUZZLES = PUZZLES,
    BLOCK_DISPLAY = BLOCK_DISPLAY,
    BLOCK_COLOR = BLOCK_COLOR,
    BLOCK_FONT = BLOCK_FONT,
    find_block = find_block,
    find_block_by_name = find_block_by_name,
    rects_overlap = rects_overlap,
    get_cell_block = get_cell_block,
    can_move = can_move,
    check_victory_state = check_victory_state,
    copy_blocks = copy_blocks,
    compute_reachable_targets = compute_reachable_targets,
    difficulty_settings = M.difficulty_settings,
    CELL_SIZE = CELL_SIZE
}

return M
