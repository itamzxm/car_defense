-- maps/amap/instance/modules/memory_corridor.lua
-- 记忆回廊玩法模块
--
-- 玩法类型：memory_corridor
-- 玩法说明：方框内有一条从起点到终点的路径。
--           系统演示路径 2 次，玩家需完美复刻该路径。
--
-- 路径生成策略（v2，按要求重写）：
--   不要求遍历所有格子，但路径要有"拐弯"，玩家需要记忆拐弯位置。
--   难度对应最少拐弯次数：easy 4 / normal 5 / hard 6
--   路径长度 = grid_size + 1（够长，演示足够，又不会太冗长）
--   路径每段在直走到撞墙或随机概率时拐弯，保证拐弯次数 >= 难度要求
--
-- 流程：
--   1. 生成 N×N 网格 + 一条带足够拐弯的随机路径
--   2. 演示阶段：路径上的格子按顺序高亮，每个 0.4 秒，演示 2 次
--   3. 玩家阶段：玩家依次点击格子，必须按路径顺序
--      - 点击正确 → 该格子永久高亮绿色
--      - 点击错误 → 飞字提示 + 计错一次，但路径不重置（继续点下一个）
--   4. 全部点完 → 胜利
--   5. 错误次数超上限 或 超时 → 失败
--
-- 难度：网格大小 / 允许错误次数 / 演示速度 / 最少拐弯次数

local Instance = require 'maps.amap.instance.instance'

local M = {}

--==============================================================================
-- 元数据
--==============================================================================

M.type = 'memory_corridor'
M.display_name_key = 'amap.instance_memory_corridor_name'
M.description_key = 'amap.instance_memory_corridor_desc'
M.gameplay_desc_key = 'amap.instance_memory_corridor_gameplay'
M.victory_condition_key = 'amap.instance_memory_corridor_victory'
M.icon = 'item/wooden-chest'
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
        grid_size = 7,                -- 7×7
        max_errors = 1,               -- 允许错 1 次
        demo_step_ticks = 30,         -- 演示每格 0.5 秒
        min_turns = 4,                -- 最少拐弯 4 次
        time_limit = 5 * 60 * 60
    },
    normal = {
        name = 'normal',
        recycling_efficiency = 1,
        max_coins = 0,
        display_name_key = 'dungeon_difficulty_normal',
        grid_size = 8,                -- 8×8
        max_errors = 1,               -- 允许错 1 次
        demo_step_ticks = 24,         -- 0.4 秒
        min_turns = 5,                -- 最少拐弯 5 次
        time_limit = 5 * 60 * 60
    },
    hard = {
        name = 'hard',
        recycling_efficiency = 1,
        max_coins = 0,
        display_name_key = 'dungeon_difficulty_hard',
        grid_size = 9,                -- 9×9
        max_errors = 1,               -- 允许错 1 次
        demo_step_ticks = 18,         -- 0.3 秒
        min_turns = 6,                -- 最少拐弯 6 次
        time_limit = 5 * 60 * 60
    }
}

--==============================================================================
-- 常量
--==============================================================================

local GUI_FRAME = 'dungeon_mc_frame'
local GUI_INFO = 'dungeon_mc_info'
local GUI_GRID = 'dungeon_mc_grid'
local CELL_PREFIX = 'dungeon_mc_cell_'

-- 4 邻偏移（上下左右）：dx, dy
local NEIGHBORS = {{0, -1}, {0, 1}, {-1, 0}, {1, 0}}

--==============================================================================
-- 随机拐弯路径生成
--==============================================================================

-- 生成一条带足够拐弯的随机路径
-- 策略：
--   1. 从起点 (1,1) 出发，初始方向随机
--   2. 沿当前方向直走若干步（随机 2~3 步），然后拐弯（90度转）
--   3. 拐弯时随机选左/右 90 度方向（不回头）
--   4. 若沿当前方向无法继续（出界或已访问），尝试拐弯
--   5. 若两个方向都无法继续，结束路径
--   6. 保证拐弯次数 >= min_turns；若不足，重新生成（最多重试 50 次）
local function generate_random_turn_path(grid_size, start_x, start_y, min_turns)
    local function attempt()
        local visited = {}
        for x = 1, grid_size do
            visited[x] = {}
            for y = 1, grid_size do
                visited[x][y] = false
            end
        end

        local path = {}
        local turns = 0
        -- 初始方向：随机选一个
        local dir_idx = math.random(1, 4)
        local dir = NEIGHBORS[dir_idx]
        local cx, cy = start_x, start_y
        visited[cx][cy] = true
        path[1] = {x = cx, y = cy}

        -- 目标路径长度：grid_size + 1 步（约 8/9/10 步）
        local target_length = grid_size + 1

        -- 拐弯函数：随机选左/右 90 度方向（不回头）
        -- NEIGHBORS 顺序: 1=上(0,-1) 2=下(0,1) 3=左(-1,0) 4=右(1,0)
        -- 上↔下 是对头；左↔右 是对头
        -- 左转 90: 上→左, 左→下, 下→右, 右→上
        -- 右转 90: 上→右, 右→下, 下→左, 左→上
        local function turn_left(d)
            if d == 1 then return 3
            elseif d == 3 then return 2
            elseif d == 2 then return 4
            elseif d == 4 then return 1 end
        end
        local function turn_right(d)
            if d == 1 then return 4
            elseif d == 4 then return 2
            elseif d == 2 then return 3
            elseif d == 3 then return 1 end
        end

        -- 直走步数：每段 2~3 步后再拐弯（增加随机性）
        local straight_remaining = math.random(2, 3)

        for _ = 1, target_length * 4 do  -- 安全上限
            if #path >= target_length and turns >= min_turns then
                break
            end

            -- 尝试沿当前方向走
            local nx, ny = cx + dir[1], cy + dir[2]
            local can_go = (nx >= 1 and nx <= grid_size and ny >= 1 and ny <= grid_size
                           and not visited[nx][ny])

            -- 直走步数耗尽 或 无法继续：尝试拐弯
            if (straight_remaining <= 0 or not can_go) then
                -- 随机选左/右转
                local new_dir_idx
                if math.random() < 0.5 then
                    new_dir_idx = turn_left(dir_idx)
                else
                    new_dir_idx = turn_right(dir_idx)
                end
                local new_dir = NEIGHBORS[new_dir_idx]
                local tnx, tny = cx + new_dir[1], cy + new_dir[2]
                local can_turn = (tnx >= 1 and tnx <= grid_size and tny >= 1 and tny <= grid_size
                                  and not visited[tnx][tny])

                if can_turn then
                    -- 拐弯成功
                    dir_idx = new_dir_idx
                    dir = new_dir
                    turns = turns + 1
                    straight_remaining = math.random(2, 3)
                    -- 这次走的是拐弯后的方向
                    cx, cy = tnx, tny
                    visited[cx][cy] = true
                    path[#path + 1] = {x = cx, y = cy}
                    straight_remaining = straight_remaining - 1
                else
                    -- 第一个拐弯方向不行，试另一个
                    local other_dir_idx
                    if new_dir_idx == turn_left(dir_idx) then
                        other_dir_idx = turn_right(dir_idx)
                    else
                        other_dir_idx = turn_left(dir_idx)
                    end
                    local other_dir = NEIGHBORS[other_dir_idx]
                    local onx, ony = cx + other_dir[1], cy + other_dir[2]
                    local can_other = (onx >= 1 and onx <= grid_size and ony >= 1 and ony <= grid_size
                                       and not visited[onx][ony])
                    if can_other then
                        dir_idx = other_dir_idx
                        dir = other_dir
                        turns = turns + 1
                        straight_remaining = math.random(2, 3)
                        cx, cy = onx, ony
                        visited[cx][cy] = true
                        path[#path + 1] = {x = cx, y = cy}
                        straight_remaining = straight_remaining - 1
                    else
                        -- 两个拐弯方向都不行，结束
                        break
                    end
                end
            else
                -- 直走
                cx, cy = nx, ny
                visited[cx][cy] = true
                path[#path + 1] = {x = cx, y = cy}
                straight_remaining = straight_remaining - 1
            end
        end

        return path, turns
    end

    -- 重试最多 50 次，直到满足 min_turns 和最小长度
    for _ = 1, 50 do
        local path, turns = attempt()
        if path and #path >= grid_size and turns >= min_turns then
            return path
        end
    end
    -- 兜底：返回最后一次结果
    local path = attempt()
    return path
end

--==============================================================================
-- GUI
--==============================================================================

local function create_main_gui(player, md)
    local screen = player.gui.screen
    if screen[GUI_FRAME] then screen[GUI_FRAME].destroy() end

    local frame = screen.add({
        type = 'frame',
        name = GUI_FRAME,
        caption = {'amap.mc_title'},
        direction = 'vertical'
    })
    frame.force_auto_center()

    local info = frame.add({
        type = 'label',
        name = GUI_INFO,
        caption = ''
    })
    info.style.font = 'default-bold'
    info.style.font_color = {1, 0.85, 0}

    local grid = frame.add({
        type = 'table',
        name = GUI_GRID,
        column_count = md.grid_size
    })
    grid.style.horizontal_spacing = 2
    grid.style.vertical_spacing = 2

    -- 格子大小：按用户要求放大 1.5 倍（原 38/44/50 → 57/66/75）
    local cell_size = md.grid_size >= 9 and 60 or (md.grid_size >= 8 and 66 or 57)

    for y = 1, md.grid_size do
        for x = 1, md.grid_size do
            local cell = grid.add({
                type = 'button',
                name = CELL_PREFIX .. x .. '_' .. y,
                caption = '',
                tags = {mc_cell = true, x = x, y = y},
                mouse_button_filter = {'left'}
            })
            cell.style.minimal_width = cell_size
            cell.style.minimal_height = cell_size
            cell.style.maximal_width = cell_size
            cell.style.maximal_height = cell_size
            cell.style.font = 'default-bold'

            -- 起点（蓝色）/ 终点（红色）标记
            if x == md.path[1].x and y == md.path[1].y then
                cell.caption = 'S'
                cell.style.font_color = {0.4, 0.6, 1}
            elseif x == md.path[#md.path].x and y == md.path[#md.path].y then
                cell.caption = 'E'
                cell.style.font_color = {1, 0.4, 0.4}
            end
        end
    end

    local hint = frame.add({
        type = 'label',
        caption = {'amap.mc_hint'}
    })
    hint.style.font = 'default'
    hint.style.font_color = {0.7, 0.7, 0.7}
end

-- 高亮演示路径中的第 idx 个格子
local function highlight_demo_cell(player, md, idx)
    local frame = player.gui.screen[GUI_FRAME]
    if not frame then return end
    local grid = frame[GUI_GRID]
    if not grid then return end

    -- 先清掉所有非起点/终点的标记（保留 S/E 字符和颜色）
    for y = 1, md.grid_size do
        for x = 1, md.grid_size do
            local cell = grid[CELL_PREFIX .. x .. '_' .. y]
            if cell then
                local is_start = (x == md.path[1].x and y == md.path[1].y)
                local is_end = (x == md.path[#md.path].x and y == md.path[#md.path].y)
                if is_start then
                    cell.caption = 'S'
                    cell.style.font_color = {0.4, 0.6, 1}
                elseif is_end then
                    cell.caption = 'E'
                    cell.style.font_color = {1, 0.4, 0.4}
                else
                    cell.caption = ''
                end
            end
        end
    end

    -- 高亮当前演示格
    if idx >= 1 and idx <= #md.path then
        local p = md.path[idx]
        local cell = grid[CELL_PREFIX .. p.x .. '_' .. p.y]
        if cell then
            cell.caption = tostring(idx)
            cell.style.font_color = {1, 0.85, 0.2}  -- 黄色演示色
        end
    end
end

-- 标记玩家已正确点过的格子（绿色 + 序号）
local function mark_player_progress(player, md)
    local frame = player.gui.screen[GUI_FRAME]
    if not frame then return end
    local grid = frame[GUI_GRID]
    if not grid then return end

    for idx = 1, md.player_progress do
        local p = md.path[idx]
        local cell = grid[CELL_PREFIX .. p.x .. '_' .. p.y]
        if cell then
            if idx == 1 then
                cell.caption = 'S'
                cell.style.font_color = {0.2, 0.8, 0.2}  -- 已点过的起点 = 绿
            elseif idx == #md.path then
                cell.caption = 'E'
                cell.style.font_color = {0.2, 0.8, 0.2}
            else
                cell.caption = tostring(idx)
                cell.style.font_color = {0.2, 0.8, 0.2}
            end
        end
    end
end

local function update_info(player, md)
    local frame = player.gui.screen[GUI_FRAME]
    if not frame then return end
    local info = frame[GUI_INFO]
    if not info then return end

    local remaining_sec = math.max(0, math.floor((md.end_tick - game.tick) / 60))
    local phase_text
    if md.phase == 'demo' then
        phase_text = {'amap.mc_phase_demo', md.demo_round, md.player_progress}
    else
        phase_text = {'amap.mc_phase_play', md.player_progress, #md.path, md.errors, md.max_errors}
    end
    info.caption = {'amap.mc_info', phase_text, remaining_sec}
end

--==============================================================================
-- 钩子
--==============================================================================

function M.on_surface_init(surface, player, data, difficulty_key)
    local diff = M.difficulty_settings[difficulty_key] or M.difficulty_settings.easy
    local ah = 8
    local tiles = {}
    for x = -ah - 1, ah + 1 do
        for y = -ah - 1, ah + 1 do
            tiles[#tiles + 1] = {name = 'grass-1', position = {x, y}}
        end
    end
    surface.set_tiles(tiles)

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

    for x = -1, 1 do
        for y = -1, 1 do
            surface.set_tiles({{name = 'hazard-concrete-left', position = {x, y}}})
        end
    end

    -- 生成随机拐弯路径：起点 (1,1)，不要求遍历所有格子，但拐弯次数 >= min_turns
    local path = generate_random_turn_path(diff.grid_size, 1, 1, diff.min_turns)
    if not path or #path < 2 then
        -- 兜底：最简单的两步路径
        path = {{x = 1, y = 1}, {x = 2, y = 1}}
    end

    data.module_data = {
        grid_size = diff.grid_size,
        path = path,
        max_errors = diff.max_errors,
        demo_step_ticks = diff.demo_step_ticks,
        time_limit = diff.time_limit or M.time_limit_default,
        -- 阶段控制
        phase = 'demo',                  -- 'demo' / 'play' / 'done'
        demo_round = 1,                  -- 当前演示轮次（1 或 2）
        demo_idx = 0,                    -- 当前演示到的 path 索引
        next_demo_tick = 0,              -- 下一个演示格的 tick
        player_progress = 0,             -- 玩家已正确点的格子数
        errors = 0,
        end_tick = 0,
        start_tick = 0,
        finished = false,
        victory = false
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
    md.next_demo_tick = game.tick + 60  -- 1 秒后开始演示

    -- 隐藏框架 coins label
    local top = player.gui.top
    if top['dungeon_coins'] then top['dungeon_coins'].destroy() end

    create_main_gui(player, md)
    player.print({'amap.mc_enter'}, {r = 0, g = 1, b = 0})
    player.print({'amap.mc_hint'}, {r = 1, g = 0.8, b = 0})
end

function M.on_tick(player, data)
    local md = data.module_data
    if not md or md.finished then return end
    local tick = game.tick

    -- 超时
    if tick >= md.end_tick then
        md.finished = true
        md.victory = false
        return
    end

    if md.phase == 'demo' then
        if tick >= md.next_demo_tick then
            md.demo_idx = md.demo_idx + 1
            if md.demo_idx > #md.path then
                -- 一轮演示完成
                if md.demo_round >= 2 then
                    -- 进入玩家阶段
                    md.phase = 'play'
                    md.player_progress = 0
                    md.demo_idx = 0
                    highlight_demo_cell(player, md, 0)  -- 清掉演示高亮
                    player.print({'amap.mc_play_start'}, {r = 0, g = 1, b = 0})
                else
                    -- 进入第二轮演示
                    md.demo_round = 2
                    md.demo_idx = 0
                    md.next_demo_tick = tick + 60  -- 间隔 1 秒
                end
            else
                highlight_demo_cell(player, md, md.demo_idx)
                md.next_demo_tick = tick + md.demo_step_ticks
            end
        end
    end

    update_info(player, md)
end

function M.check_victory(player, data)
    local md = data.module_data
    if not md then return nil end

    if md.finished then
        if md.victory then
            -- 奖励：错误越少奖励越高
            local err_ratio = md.errors / md.max_errors
            local mult = 1.5 + (1 - err_ratio) * 0.5
            Instance.set_reward_multiplier(player, mult)
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
    if not tags or not tags.mc_cell then return end

    local data = Instance.get_data(player.index)
    if not data or not data.active then return end
    local md = data.module_data
    if not md or md.finished then return end

    -- 仅玩家阶段响应点击
    if md.phase ~= 'play' then return end

    local expected = md.path[md.player_progress + 1]
    if not expected then return end

    if tags.x == expected.x and tags.y == expected.y then
        -- 正确
        md.player_progress = md.player_progress + 1
        mark_player_progress(player, md)
        player.create_local_flying_text({
            text = {'amap.mc_correct', md.player_progress},
            position = player.position,
            color = {0.2, 1, 0.2}
        })
        player.play_sound({path = 'utility/achievement_unlocked', volume_modifier = 0.4})

        -- 全部点完 → 胜利
        if md.player_progress >= #md.path then
            md.finished = true
            md.victory = true
        end
    else
        -- 错误
        md.errors = md.errors + 1
        player.create_local_flying_text({
            text = {'amap.mc_wrong', md.errors, md.max_errors},
            position = player.position,
            color = {1, 0.3, 0.3}
        })
        player.play_sound({path = 'utility/cannot_build', volume_modifier = 0.6})

        if md.errors >= md.max_errors then
            md.finished = true
            md.victory = false
        end
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
