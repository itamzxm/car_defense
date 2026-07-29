-- maps/amap/instance/modules/minesweeper.lua
-- 扫雷玩法模块
--
-- 玩法类型：minesweeper
-- 玩法说明：经典扫雷的 Factorio 适配版
--   - 未揭示格 = stone-path（灰色）
--   - 已揭示格 = grass-1（绿色，铺在 stone-path 之下）
--   - 数字 = rendering.draw_text 在 tile 中心
--   - 揭示 = 玩家挖 stone-path（on_player_mined_tile）
--   - 踩雷 = 挖到地雷格 → defeat
--   - 胜利 = 所有非雷格已揭示 → victory
--   - 0 数字格自动洪水填充周围 8 格（经典扫雷体验）
--   - 首挖安全保护：玩家第一次挖格子时才生成地雷，排除该格子和周围 8 格
--
-- 钩子实现：
--   on_surface_init - 生成地形（grass 底 + stone-path 网格 + stone-wall 外围）
--   on_enter        - 设置 manual_mining_speed_modifier + 创建顶栏"剩余雷数"label + 给初始 stone-brick + wooden-chest（插旗用）
--   on_exit         - 清理 rendering + 顶栏自定义 GUI
--   on_tick         - 更新顶栏"剩余雷数"label（总雷数 - 已插旗数）
--   check_victory  - mine_triggered → 'defeat'；revealed >= total_safe → 'victory'
--   on_player_mined_tile - 揭示格子（含洪水填充）/ 阻止挖已揭示格子
--   on_player_built_tile - 网格内不允许铺砖（玩家无混凝土），铺下一律撤销恢复 + 退还物品
--   on_built_entity     - 网格内放木箱 = 插旗（已揭示格禁止 + 退还物品）
--   on_player_mined_entity - 网格内挖木箱 = 取消插旗

local Instance = require 'maps.amap.instance.instance'
local Token = require 'utils.token'
local Task = require 'utils.task'

local M = {}

--==============================================================================
-- 元数据
--==============================================================================

M.type = 'minesweeper'
M.display_name_key = 'amap.instance_minesweeper_name'
M.description_key = 'amap.instance_minesweeper_desc'
M.gameplay_desc_key = 'amap.instance_minesweeper_gameplay'
M.victory_condition_key = 'amap.instance_minesweeper_victory'
M.icon = 'item/land-mine'
M.time_limit_default = 10 * 60 * 60  -- 默认 10 分钟（tick），所有难度统一

-- 难度设置
-- 注意：recycling_efficiency / max_coins 是框架必填字段（挖币遗留），对扫雷无意义，填 1 / 0 占位
-- 专属参数（grid_size / mine_count / time_limit）放在扩展字段中，由模块自行读取
M.difficulty_settings = {
    easy = {
        name = "easy",
        recycling_efficiency = 1,
        max_coins = 0,
        display_name_key = "dungeon_difficulty_easy",
        grid_size = 7,
        mine_count = 10,
        time_limit = 10 * 60 * 60  -- 10 分钟
    },
    normal = {
        name = "normal",
        recycling_efficiency = 1,
        max_coins = 0,
        display_name_key = "dungeon_difficulty_normal",
        grid_size = 9,
        mine_count = 15,
        time_limit = 10 * 60 * 60  -- 10 分钟
    },
    hard = {
        name = "hard",
        recycling_efficiency = 1,
        max_coins = 0,
        display_name_key = "dungeon_difficulty_hard",
        grid_size = 11,
        mine_count = 24,
        time_limit = 10 * 60 * 60  -- 10 分钟
    }
}

--==============================================================================
-- 顶栏 GUI 元素名常量
--==============================================================================

local GUI_MINES_LEFT = 'dungeon_module_ms_mines_left'

--==============================================================================
-- 数字颜色（经典扫雷）
--==============================================================================

local NUMBER_COLORS = {
    [1] = {0, 0, 1},         -- 蓝
    [2] = {0, 0.6, 0},       -- 绿
    [3] = {1, 0, 0},         -- 红
    [4] = {0, 0, 0.5},       -- 深蓝
    [5] = {0.5, 0, 0},       -- 暗红
    [6] = {0, 0.6, 0.6},     -- 青
    [7] = {0, 0, 0},         -- 黑
    [8] = {0.5, 0.5, 0.5}    -- 灰
}

-- 8 邻偏移量
local NEIGHBORS = {
    {-1, -1}, {0, -1}, {1, -1},
    {-1,  0},          {1,  0},
    {-1,  1}, {0,  1}, {1,  1}
}

--==============================================================================
-- 辅助函数
--==============================================================================

-- 延迟退出副本：避免在 on_player_mined_tile 事件 handler 中直接调用 Instance.exit
-- （直接调用会在事件处理过程中销毁 surface / character，导致退出流程中断）
-- 延迟 2 tick（≈33ms）后退出，事件 handler 已返回，玩家来不及再操作
local function delayed_exit(params)
    local player = game.players[params.player_index]
    if not player or not player.valid then return end
    Instance.exit(player, 'defeat')
end
local delayed_exit_token = Token.register(delayed_exit)

-- 计算 (x, y) 周围 8 格的地雷数
local function count_adjacent_mines(module_data, x, y)
    local count = 0
    for _, off in ipairs(NEIGHBORS) do
        local key = (x + off[1]) .. "_" .. (y + off[2])
        if module_data.mines[key] then
            count = count + 1
        end
    end
    return count
end

-- 判断 (x, y) 是否在网格内
local function is_in_grid(module_data, x, y)
    return x >= module_data.start_x
       and x < module_data.start_x + module_data.grid_size
       and y >= module_data.start_y
       and y < module_data.start_y + module_data.grid_size
end

--==============================================================================
-- 插旗用木箱（wooden-chest）
--==============================================================================
-- 经典扫雷用"放木箱"当旗子：
--   - 在可疑雷格（未揭示 stone-path）上放一个 wooden-chest 即标记 flagged
--   - 挖掉木箱 = 取消插旗
--   - 木箱盖在格子上时，左键会先挖木箱而非揭示格子，符合"插旗格不可误点开"的手感

-- 生成地雷位置
-- exclude_positions: 可选，{["x_y"] = true}，这些位置不放雷（用于 first_click 保护）
local function generate_mines(module_data, exclude_positions)
    local mines = {}
    local grid_size = module_data.grid_size
    local target_mine_count = module_data.mine_count

    -- 收集所有可用位置：除中心格 (0,0) 和 exclude_positions
    local available = {}
    for x = module_data.start_x, module_data.start_x + grid_size - 1 do
        for y = module_data.start_y, module_data.start_y + grid_size - 1 do
            if not (x == 0 and y == 0) then
                local key = x .. "_" .. y
                if not (exclude_positions and exclude_positions[key]) then
                    available[#available + 1] = {x = x, y = y, key = key}
                end
            end
        end
    end

    -- 防御：若雷数超过可用格子数，截断
    local actual_count = math.min(target_mine_count, #available)

    -- Fisher-Yates 完整洗牌，取前 actual_count 个作为雷
    for i = #available, 2, -1 do
        local j = math.random(i)
        available[i], available[j] = available[j], available[i]
    end

    for i = 1, actual_count do
        local pos = available[i]
        mines[pos.key] = true
    end

    module_data.mines = mines
    module_data.total_safe = grid_size * grid_size - actual_count

    -- 诊断日志：方便排查"雷数不对"问题
    log("[MINESWEEPER] grid=" .. grid_size .. "x" .. grid_size
        .. " target_mines=" .. target_mine_count
        .. " available=" .. #available
        .. " actual_mines=" .. actual_count
        .. " total_safe=" .. module_data.total_safe)
end

--==============================================================================
-- 揭示逻辑（含洪水填充）
--==============================================================================

-- 揭示单个格子（不递归）。返回是否成功揭示。
-- 已揭示 / 是雷 / 已插旗 → 不揭示
local function reveal_single(surface, module_data, x, y)
    local key = x .. "_" .. y
    if module_data.revealed[key] then return false end
    if module_data.mines[key] then return false end
    if module_data.flagged[key] then return false end  -- 洪水填充跳过插旗格子

    module_data.revealed[key] = true
    -- 揭示 = 把 stone-path 替换为 grass-1
    surface.set_tiles{{name = "grass-1", position = {x, y}}}

    -- 绘制周围地雷数（若 > 0）
    -- target = tile 中心 {x+0.5, y+0.5}
    -- vertical_alignment = "middle"：让文字垂直中心对齐到 target（默认 "top" 会导致文字向下延伸，不在 tile 中心）
    --   VerticalTextAlign 合法值：top / middle / baseline / bottom（注意：不是 "center"）
    -- alignment = "center"：水平居中（TextAlign 合法值：left / center / right）
    local count = count_adjacent_mines(module_data, x, y)
    if count > 0 then
        local obj = rendering.draw_text({
            text = tostring(count),
            surface = surface,
            target = {x + 0.5, y + 0.5},
            color = NUMBER_COLORS[count] or {1, 1, 1},
            scale = 1.5,
            font = 'default-bold',
            alignment = 'center',
            vertical_alignment = 'middle'
        })
        module_data.rendering_ids[key] = obj
    end

    return true
end

-- 揭示格子（含洪水填充：0 数字格递归揭示 8 邻）
-- 用显式栈代替递归，避免 Lua 栈深度限制（最坏 121 格）
local function reveal_tile(surface, module_data, x, y)
    local stack = {{x = x, y = y}}
    while #stack > 0 do
        local cell = table.remove(stack)
        local cx, cy = cell.x, cell.y

        if is_in_grid(module_data, cx, cy) then
            local key = cx .. "_" .. cy
            if not module_data.revealed[key]
               and not module_data.mines[key] then
                local revealed = reveal_single(surface, module_data, cx, cy)
                if revealed then
                    -- 若该格周围 0 雷，把 8 邻入栈（洪水填充）
                    local count = count_adjacent_mines(module_data, cx, cy)
                    if count == 0 then
                        for _, off in ipairs(NEIGHBORS) do
                            stack[#stack + 1] = {x = cx + off[1], y = cy + off[2]}
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

-- surface 初始化：生成地形 + 网格 + 外围石墙
function M.on_surface_init(surface, player, data, difficulty)
    local diff_settings = M.difficulty_settings[difficulty] or M.difficulty_settings.easy
    local grid_size = diff_settings.grid_size
    local mine_count = diff_settings.mine_count

    -- 网格居中放置（grid_size 为奇数时中心格为 (0,0)）
    local start_x = -math.floor(grid_size / 2)
    local start_y = -math.floor(grid_size / 2)

    -- 写入 module_data
    data.module_data = {
        grid_size = grid_size,
        start_x = start_x,
        start_y = start_y,
        mine_count = mine_count,
        mines = {},
        revealed = {},
        flagged = {},          -- 已插旗位置集合（玩家放木箱标记）
        rendering_ids = {},
        total_safe = grid_size * grid_size - mine_count,
        mine_triggered = false,
        mines_generated = false  -- 延迟生成：玩家第一次挖格子时才生成（保证首挖安全）
    }
    local module_data = data.module_data

    -- 覆盖框架默认 time_limit（用难度专属值）
    data.time_limit = diff_settings.time_limit or M.time_limit_default

    -- 1. 全图铺 grass-1（揭示后的底层 tile）
    for x = -50, 50 do
        for y = -50, 50 do
            surface.set_tiles{{name = "grass-1", position = {x, y}}}
        end
    end

    -- 2. 网格区域铺 stone-path（未揭示状态）
    for x = start_x, start_x + grid_size - 1 do
        for y = start_y, start_y + grid_size - 1 do
            surface.set_tiles{{name = "stone-path", position = {x, y}}}
        end
    end

    -- 3. 外围石墙包围网格（防止玩家走出），minable=false / destructible=false
    -- 上边
    for x = start_x - 1, start_x + grid_size do
        local e = surface.create_entity({
            name = "stone-wall",
            position = {x = x, y = start_y - 1},
            force = player.force
        })
        if e then e.minable_flag = false; e.destructible = false end
    end
    -- 下边
    for x = start_x - 1, start_x + grid_size do
        local e = surface.create_entity({
            name = "stone-wall",
            position = {x = x, y = start_y + grid_size},
            force = player.force
        })
        if e then e.minable_flag = false; e.destructible = false end
    end
    -- 左边
    for y = start_y, start_y + grid_size - 1 do
        local e = surface.create_entity({
            name = "stone-wall",
            position = {x = start_x - 1, y = y},
            force = player.force
        })
        if e then e.minable_flag = false; e.destructible = false end
    end
    -- 右边
    for y = start_y, start_y + grid_size - 1 do
        local e = surface.create_entity({
            name = "stone-wall",
            position = {x = start_x + grid_size, y = y},
            force = player.force
        })
        if e then e.minable_flag = false; e.destructible = false end
    end

    -- 4. 地雷延迟生成：玩家第一次挖格子时才生成（保证首挖安全，排除该格子和周围 8 格）

    -- 5. 副本常昼，视野清晰
    surface.always_day = true

    -- 6. 让副本 force chart 网格区域（玩家立即可见全网格）
    player.force.chart(surface, {
        {start_x - 2, start_y - 2},
        {start_x + grid_size + 1, start_y + grid_size + 1}
    })
end

-- 进入副本：设 manual_mining_speed_modifier + 隐藏金币 label + 给初始物品 + 创建顶栏"剩余雷数"label
function M.on_enter(player, data, difficulty)
    local force = player.force
    force.manual_mining_speed_modifier = 10  -- 秒挖，避免等待

    local top = player.gui.top

    -- 扫雷无金币概念，隐藏框架的 coins label
    if top['dungeon_coins'] then
        top['dungeon_coins'].destroy()
    end

    -- 创建顶栏"剩余雷数"label
    if not top[GUI_MINES_LEFT] then
        local label = top.add({
            type = 'label',
            name = GUI_MINES_LEFT,
            caption = ''
        })
        label.style.font_color = {1, 0.3, 0.3}
        label.style.font = 'default-bold'
    end

    -- 给玩家初始物品：
    -- - stone-brick：手持挖 stone-path（挖 tile 不消耗物品，但手持石砖能避免游戏某些边界情况）
    -- - wooden-chest：插旗用（在未揭示格上放木箱标记可疑雷格，挖掉木箱取消插旗）
    player.insert({name = "stone-brick", count = 50})
    player.insert({name = "wooden-chest", count = 50})

    -- 提示玩法说明
    local module_data = data.module_data
    if module_data then
        player.print({'amap.minesweeper_enter',
                      module_data.grid_size,
                      module_data.mine_count}, {r = 0, g = 1, b = 0})
    end
    player.print({'amap.minesweeper_hint'}, {r = 1, g = 1, b = 0})
end

-- 退出副本：清理 rendering + 顶栏自定义 GUI
function M.on_exit(player, data, reason)
    -- 清理所有 rendering（Factorio 2.x: draw_text 返回 LuaRenderObject，用 :destroy() 方法）
    -- on_exit 在退出主流程开头调用，若此处报错会导致玩家卡在副本无法退出，用 pcall 保护
    local module_data = data.module_data
    if module_data and module_data.rendering_ids then
        for key, obj in pairs(module_data.rendering_ids) do
            pcall(function()
                if obj and obj.valid then
                    obj.destroy()
                end
            end)
        end
        module_data.rendering_ids = {}
    end

    -- 清理顶栏 GUI
    local top = player.gui.top
    if top[GUI_MINES_LEFT] then
        top[GUI_MINES_LEFT].destroy()
    end
end

-- 每 60 tick：更新顶栏"剩余雷数"label
function M.on_tick(player, data)
    local module_data = data.module_data
    if not module_data then return end

    local label = player.gui.top[GUI_MINES_LEFT]
    if not label then return end

    -- 剩余雷数 = 总雷数 - 已插旗数（玩家可能插错旗，所以可能为负，显示 0 即可）
    local flagged_count = 0
    for _ in pairs(module_data.flagged) do
        flagged_count = flagged_count + 1
    end
    local mines_left = module_data.mine_count - flagged_count
    if mines_left < 0 then mines_left = 0 end
    label.caption = {'amap.minesweeper_mines_left', mines_left}
end

-- 通关检测
function M.check_victory(player, data)
    local module_data = data.module_data
    if not module_data then return nil end

    if module_data.mine_triggered then
        return 'defeat'
    end

    -- 已揭示数 >= 非雷格总数 → 胜利
    local revealed_count = 0
    for _ in pairs(module_data.revealed) do
        revealed_count = revealed_count + 1
    end
    if revealed_count >= module_data.total_safe then
        -- 胜利时设置奖励系数 = 1.0
        -- 副本框架在 exit 时会读取 data.reward_multiplier 发放预抽奖励
        Instance.set_reward_multiplier(player, 1.0)
        return 'victory'
    end

    return nil
end

-- 玩家挖砖：揭示格子 / 阻止挖已揭示格子
function M.on_player_mined_tile(player, event)
    local data = Instance.get_data(player.index)
    if not data or not data.active then return end
    local module_data = data.module_data
    if not module_data then return end

    -- 已踩雷，阻止继续操作（防止玩家在 defeat 退出前继续挖）
    if module_data.mine_triggered then return end

    local surface = event.surface_index and game.surfaces[event.surface_index]
    if not surface then
        surface = player.surface
    end

    -- 遍历被挖的 tile
    for _, tile in ipairs(event.tiles) do
        local x = tile.position.x
        local y = tile.position.y
        local old_name = tile.old_tile and tile.old_tile.name

        if not is_in_grid(module_data, x, y) then
            -- 网格外：不处理
        elseif old_name == "stone-path" then
            local key = x .. "_" .. y

            -- 已插旗的格子：木箱盖在格子上，正常左键会先挖木箱而非揭示格子，
            -- 一般不会走到这里；此为防御性判断，若 flagged 存在则撤销挖掘
            if module_data.flagged[key] then
                surface.set_tiles{{name = "stone-path", position = {x, y}}}
                player.remove_item({name = "stone-brick", count = 1})
                player.print({'amap.minesweeper_flagged'}, {r = 1, g = 1, b = 0})
            else
                -- 首挖安全保护：玩家第一次挖格子时才生成地雷，排除该格子和周围 8 格
                -- 保证玩家第一发不会踩雷，且周围 8 格也无雷（有落脚点可继续推断）
                if not module_data.mines_generated then
                    local exclude = {[key] = true}
                    for _, off in ipairs(NEIGHBORS) do
                        local nx, ny = x + off[1], y + off[2]
                        if is_in_grid(module_data, nx, ny) then
                            exclude[nx .. "_" .. ny] = true
                        end
                    end
                    generate_mines(module_data, exclude)
                    module_data.mines_generated = true
                end

                if module_data.mines[key] then
                    -- 踩雷！设标记 + 爆炸特效 + 延迟退出
                    -- 不能在事件 handler 中直接调用 Instance.exit（会销毁 surface/character 导致冲突）
                    -- 用 Task.set_timeout_in_ticks 延迟 2 tick 退出，事件 handler 已返回，玩家来不及再操作
                    module_data.mine_triggered = true
                    surface.create_entity({
                        name = "explosion",
                        position = {x + 0.5, y + 0.5}
                    })
                    player.print({'amap.minesweeper_boom'}, {r = 1, g = 0, b = 0})
                    -- 收回挖出的 stone-brick（防止玩家把雷格放回去再挖）
                    player.remove_item({name = "stone-brick", count = 1})
                    Task.set_timeout_in_ticks(2, delayed_exit_token, {player_index = player.index})
                    return
                else
                    -- 正常揭示（含洪水填充）
                    reveal_tile(surface, module_data, x, y)
                    -- 收回挖出的 stone-brick：防止玩家用 stone-brick 把已揭示格子盖回去
                    player.remove_item({name = "stone-brick", count = 1})
                end
            end
        end
    end
end

-- 玩家铺砖：网格内不允许铺任何砖（玩家无混凝土），铺下一律撤销恢复 + 退还物品
-- 防止玩家用 stone-brick 把已揭示格子盖回去（再挖触发雷或取消揭示）
function M.on_player_built_tile(player, event)
    local data = Instance.get_data(player.index)
    if not data or not data.active then return end
    local module_data = data.module_data
    if not module_data then return end

    local surface = event.surface_index and game.surfaces[event.surface_index]
    if not surface then
        surface = player.surface
    end

    for _, tile in ipairs(event.tiles) do
        local x = tile.position.x
        local y = tile.position.y
        local new_name = tile.new_tile and tile.new_tile.name

        if not is_in_grid(module_data, x, y) then
            -- 网格外：不处理
        else
            -- 其它砖（stone-brick / concrete / refined-concrete 等）：撤销恢复 + 退还物品
            local key = x .. "_" .. y
            local original_tile
            if module_data.revealed[key] then
                original_tile = "grass-1"
            else
                original_tile = "stone-path"
            end
            surface.set_tiles{{name = original_tile, position = {x, y}}}

            -- 退还玩家消耗的物品（根据铺下的 tile 名反推物品名）
            local refund_item
            if new_name == "stone-path" then
                refund_item = "stone-brick"
            elseif new_name == "concrete" then
                refund_item = "concrete"
            elseif new_name == "refined-concrete" then
                refund_item = "refined-concrete"
            end
            if refund_item then
                player.insert({name = refund_item, count = 1})
            end
        end
    end
end

-- 玩家放实体（木箱插旗）：网格内放 wooden-chest = 插旗
-- - 未揭示格：标记 flagged（木箱本身就是旗子，留在格子上）
-- - 已揭示格：禁止插旗，销毁木箱并退还物品
function M.on_built_entity(player, event)
    local data = Instance.get_data(player.index)
    if not data or not data.active then return end
    local module_data = data.module_data
    if not module_data then return end

    local entity = event.entity
    if not entity or not entity.valid then return end
    if entity.name ~= "wooden-chest" then return end

    local x = math.floor(entity.position.x)
    local y = math.floor(entity.position.y)

    if not is_in_grid(module_data, x, y) then
        -- 网格外：不处理（玩家被石墙挡住，正常放不进来）
        return
    end

    local key = x .. "_" .. y
    if module_data.revealed[key] then
        -- 已揭示格子不允许插旗（经典扫雷：插旗只在未揭示格上）
        -- 销毁木箱并退还物品
        entity.destroy()
        player.insert({name = "wooden-chest", count = 1})
        player.print({'amap.minesweeper_flagged'}, {r = 1, g = 1, b = 0})
    else
        -- 未揭示格子：允许插旗，标记 flagged
        module_data.flagged[key] = true
    end
end

-- 玩家挖实体（木箱）：网格内挖掉 wooden-chest = 取消插旗
function M.on_player_mined_entity(player, event)
    local data = Instance.get_data(player.index)
    if not data or not data.active then return end
    local module_data = data.module_data
    if not module_data then return end

    local entity = event.entity
    if not entity or not entity.valid then return end
    if entity.name ~= "wooden-chest" then return end

    local x = math.floor(entity.position.x)
    local y = math.floor(entity.position.y)

    if not is_in_grid(module_data, x, y) then return end

    -- 取消插旗：清除 flag（挖掉木箱后玩家会自动得到 wooden-chest 物品，无需额外退还）
    local key = x .. "_" .. y
    module_data.flagged[key] = nil
end

--==============================================================================
-- 注册到框架
--==============================================================================

Instance.register(M.type, M)

return M
