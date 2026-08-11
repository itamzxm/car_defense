-- maps/amap/instance/modules/lounge.lua
-- 休息室玩法模块（特殊副本，2026-08-11 新增）
--
-- 玩法类型：lounge
-- 玩法说明：永久安全建设区域 + 物资传送副本
--   1. 绑定史诗木箱（选中休息室后木箱不删除、转为可摧毁，成为专属入口 + 传送目标）
--   2. 100×100 无围墙区域：1 个不规则水域 + 10M 煤矿（≤30 格）+ 100M 随机矿物（≤90 格）
--   3. 中心钢箱每 10 秒把箱内物品单向传送到主世界绑定木箱（只输出，不输入）
--   4. 无限时、无奖励；继承主世界全部科技（含机器人科技）；多玩家可共享同一休息室
--
-- 钩子实现：
--   on_surface_init   - 生成地形（grass + 水域 + 煤矿 + 随机矿 + 石头树木 + 中心钢箱）
--   on_enter          - 无初始物品
--   on_exit           - 无模块级清理（surface 保留由框架 lounge_binding 处理）
-- 阵营说明：休息室不切换阵营（保持玩家原 force），科技天然继承，无 on_force_created
-- 全局调度（不依赖玩家在线状态）：
--   Event.on_nth_tick(600) - 每 10 秒遍历绑定表传送钢箱物品到绑定木箱（无人在线也照常运行）

local WPT = require 'maps.amap.table'
local Instance = require 'maps.amap.instance.instance'
local Event = require 'utils.event'

local M = {}

--==============================================================================
-- 元数据
--==============================================================================

M.type = 'lounge'
M.display_name_key = 'amap.instance_lounge_name'
M.description_key = 'amap.instance_lounge_desc'
M.gameplay_desc_key = 'amap.instance_lounge_gameplay'
M.victory_condition_key = 'amap.instance_lounge_victory'
M.icon = 'item/steel-chest'
M.time_limit_default = 10 ^ 12  -- 无限时长（用大数而非 math.huge，避免 UI 计时崩溃）
-- 休息室不切换阵营（保持 player force，见 instance.lua enter 的 lounge_binding 分支）：
-- 玩家天然拥有主世界全部科技（含机器人科技），无需 tech_sync / on_force_created 补开

-- 特殊标记（仅休息室使用，框架据此调整进入/退出/GUI 行为）
M.lounge_binding = true        -- 进入不删木箱、转绑定（专属入口 + 传送目标）
M.persistent_surface = true    -- 退出不删 surface（副本空间常驻）
M.no_reward = true             -- 无奖励（卡片不预抽、不发奖励）
M.no_time_limit = true         -- 无限时（计时器显示「无限」）

-- 难度设置：仅 easy 一档（卡片难度标签用「永久」文案）
M.difficulty_settings = {
    easy = {
        name = "easy",
        recycling_efficiency = 1,
        max_coins = 0,
        display_name_key = "lounge_difficulty_forever"
    }
}

--==============================================================================
-- 常量
--==============================================================================

-- 中心禁区（钢箱区）：|x| < 8 且 |y| < 8 的格不生成水域/矿脉/装饰
local CENTER_EXCLUDE = 8

--==============================================================================
-- 辅助函数
--==============================================================================

local function is_center_zone(x, y)
    return math.abs(x) < CENTER_EXCLUDE and math.abs(y) < CENTER_EXCLUDE
end

-- 随机起点（避开中心禁区），最多重试 50 次
local function random_outside_center(margin)
    for _ = 1, 50 do
        local p = {x = math.random(-48, 48), y = math.random(-48, 48)}
        if math.abs(p.x) > margin or math.abs(p.y) > margin then
            return p
        end
    end
    return {x = math.random(-40, 40), y = math.random(-40, 40)}
end

-- 判断位置是否已有 resource 实体（防矿脉间重叠）
local function is_position_on_resource(surface, position)
    local resources = surface.find_entities_filtered({
        position = position,
        radius = 0.5,
        type = 'resource'
    })
    return #resources > 0
end

-- 随机矿池：跟随主世界星球解锁进度
--   - 基础三矿恒定可选：iron-ore / stone / copper-ore
--   - 已解锁火山星（planet-discovery-vulcanus）→ 加入 calcite
--   - 已解锁废土星（planet-discovery-fulgora）→ 加入 scrap
-- 判定必须查 game.forces.player（主世界玩家 force）：
--   星球解锁科技属于主世界进度（与 maps/amap/functions.lua 星球创建判定同源），
--   休息室保持玩家原阵营（player force），且 surface 仅首次创建时生成随机矿，按当时主世界进度决定即可
local function get_unlocked_ore_pool()
    local pool = {"iron-ore", "stone", "copper-ore"}

    local player_force = game.forces.player
    if player_force then
        local vulcanus_tech = player_force.technologies["planet-discovery-vulcanus"]
        if vulcanus_tech and vulcanus_tech.researched then
            pool[#pool + 1] = "calcite"
        end

        local fulgora_tech = player_force.technologies["planet-discovery-fulgora"]
        if fulgora_tech and fulgora_tech.researched then
            pool[#pool + 1] = "scrap"
        end
    end

    return pool
end

-- 随机游走收集矿脉格子（参考 coin_mine generate_ore_vein，但不立即创建实体）
-- 区别：
--   - 目标格已有 resource 实体 / 已被占用 / 在中心禁区 / 水域 → 跳过（防脉间重叠）
--   - 格数达上限立即停止，返回实际收集的格子数组 [{position = {...}}, ...]
--   - 每格 amount 由调用方按总储量均摊（先收集完再统一创建，保证总量精确）
local function collect_ore_vein(surface, center_pos, size, max_tiles, occupied)
    local vectors = {{0,-1},{-1,0},{1,0},{0,1}}
    local entities = {}

    local start = {x = center_pos.x, y = center_pos.y}
    if is_center_zone(start.x, start.y) then
        start = random_outside_center(CENTER_EXCLUDE)
    end

    local start_key = start.x .. "_" .. start.y
    if not occupied[start_key] and not is_center_zone(start.x, start.y)
       and not is_position_on_resource(surface, start)
       and surface.get_tile(start).name ~= "water" then
        occupied[start_key] = true
        entities[#entities + 1] = {position = start}
    end

    local count = size
    local max = max_tiles - #entities

    for _ = 1, 128 do
        if max <= 0 then break end

        local c = math.random(math.floor(size * 0.25) + 1, size)
        if c > max then c = max end

        local placed_count = #entities

        for _ = 1, c do
            if #entities == 0 or max <= 0 then break end

            local r = math.random(1, #entities)
            local position = {x = entities[r].position.x, y = entities[r].position.y}

            table.shuffle_table(vectors)
            for i = 1, 4 do
                local p = {x = position.x + vectors[i][1], y = position.y + vectors[i][2]}
                if p.x >= -50 and p.x <= 50 and p.y >= -50 and p.y <= 50 then
                    local pk = p.x .. "_" .. p.y
                    if not occupied[pk] and not is_center_zone(p.x, p.y)
                       and not is_position_on_resource(surface, p)
                       and surface.get_tile(p).name ~= "water" then
                        position.x = p.x
                        position.y = p.y
                        occupied[pk] = true
                        entities[#entities + 1] = {position = p}
                        break
                    end
                end
            end
        end

        local added = #entities - placed_count
        max = max - added
        count = count - added
        if count <= 0 then break end
    end

    return entities
end

-- 不规则水域（参考 coin_mine generate_water_vein，避开中心禁区）
local function generate_water_vein(surface, center_pos, size)
    local vectors = {{0,-1},{-1,0},{1,0},{0,1}}
    local water_positions = {}
    local water_tiles = {}

    if not is_center_zone(center_pos.x, center_pos.y) then
        water_tiles[#water_tiles + 1] = {name = "water", position = center_pos}
        water_positions[center_pos.x .. "_" .. center_pos.y] = true
    end

    local count = size

    for _ = 1, 64 do
        if #water_tiles == 0 then break end

        local c = math.random(math.floor(size * 0.25) + 1, size)
        if count < c then c = count end

        local placed_water_count = #water_tiles

        for _ = 1, c do
            if #water_tiles == 0 then break end

            local r = math.random(1, #water_tiles)
            local position = {x = water_tiles[r].position.x, y = water_tiles[r].position.y}

            table.shuffle_table(vectors)
            for i = 1, 4 do
                local p = {x = position.x + vectors[i][1], y = position.y + vectors[i][2]}
                if p.x >= -50 and p.x <= 50 and p.y >= -50 and p.y <= 50 then
                    local pk = p.x .. "_" .. p.y
                    if not water_positions[pk] and not is_center_zone(p.x, p.y) then
                        position.x = p.x
                        position.y = p.y
                        water_positions[pk] = true
                        water_tiles[#water_tiles + 1] = {name = "water", position = p}
                        break
                    end
                end
            end
        end

        count = count - (#water_tiles - placed_water_count)
        if count <= 0 then break end
    end

    if #water_tiles > 0 then
        surface.set_tiles(water_tiles)
    end
end

--==============================================================================
-- 地形生成
--==============================================================================

function M.on_surface_init(surface, player, data, difficulty)
    -- 平铺 grass-1（资源格保留）
    for x = -50, 50 do
        for y = -50, 50 do
            if not surface.get_tile(x, y).collides_with("resource") then
                surface.set_tiles{{name = "grass-1", position = {x, y}}}
            end
        end
    end

    -- 跨矿脉防重叠标记（key = "x_y"）
    local occupied = {}

    -- 1 个水域：不规则形状，面积随机 25-45 格，中心随机（避开中心禁区与钢箱）
    generate_water_vein(surface, random_outside_center(CENTER_EXCLUDE), math.random(25, 45))

    -- 煤矿：2-3 条不规则矿脉，总格数 ≤ 30，总储量精确 10M（按实际格数均摊）
    local coal_vein_count = math.random(2, 3)
    local coal_max_tiles = 30
    local coal_entities = {}
    for _ = 1, coal_vein_count do
        if coal_max_tiles <= 0 then break end
        local vein = collect_ore_vein(surface, random_outside_center(10), math.random(8, 15), coal_max_tiles, occupied)
        coal_max_tiles = coal_max_tiles - #vein
        for _, e in ipairs(vein) do
            coal_entities[#coal_entities + 1] = e
        end
    end
    if #coal_entities > 0 then
        local per_tile = math.floor(10000000 / #coal_entities)
        for _, e in ipairs(coal_entities) do
            surface.create_entity({name = "coal", position = e.position, amount = per_tile})
        end
    end

    -- 随机矿物：按主世界星球解锁进度取矿池（基础三矿 + 已解锁星球的特殊矿），
    -- 先过滤不存在的原型再随机选一种（理论上前述科技判定已隐含 SA 环境，过滤作防御）；
    -- 3-4 条不规则矿脉，总格数 ≤ 90，总储量精确 100M（按实际格数均摊）
    local random_ores = {}
    for _, ore_name in ipairs(get_unlocked_ore_pool()) do
        if prototypes.entity[ore_name] then
            random_ores[#random_ores + 1] = ore_name
        end
    end
    if #random_ores > 0 then
        local ore_type = random_ores[math.random(#random_ores)]
        local ore_vein_count = math.random(3, 4)
        local ore_max_tiles = 90
        local ore_entities = {}
        for _ = 1, ore_vein_count do
            if ore_max_tiles <= 0 then break end
            local vein = collect_ore_vein(surface, random_outside_center(10), math.random(20, 35), ore_max_tiles, occupied)
            ore_max_tiles = ore_max_tiles - #vein
            for _, e in ipairs(vein) do
                ore_entities[#ore_entities + 1] = e
            end
        end
        if #ore_entities > 0 then
            local per_tile = math.floor(100000000 / #ore_entities)
            for _, e in ipairs(ore_entities) do
                surface.create_entity({name = ore_type, position = e.position, amount = per_tile})
            end
        end
    end

    -- 装饰：岩石（40-60 个）+ 树木（60-100 棵），随机分布，避开中心禁区、水域与已有实体
    -- 岩石名与主世界生成同源（world_function.lua rock_raffle：big-sand-rock/big-rock/huge-rock）
    local rock_pool = {}
    for _, rn in ipairs({"big-rock", "big-sand-rock", "huge-rock"}) do
        if prototypes.entity[rn] then
            rock_pool[#rock_pool + 1] = rn
        end
    end
    local tree_pool = {}
    for i = 1, 9 do
        local tname = "tree-0" .. i
        if prototypes.entity[tname] then
            tree_pool[#tree_pool + 1] = tname
        end
    end
    if prototypes.entity["dry-tree"] then
        tree_pool[#tree_pool + 1] = "dry-tree"
    end

    local function place_decorations(pool, count)
        if #pool == 0 then return end
        local placed = 0
        for _ = 1, 200 do
            if placed >= count then break end
            local p = {x = math.random(-48, 48), y = math.random(-48, 48)}
            if not is_center_zone(p.x, p.y) then
                local tile = surface.get_tile(p)
                if tile.valid and tile.name ~= "water"
                   and not is_position_on_resource(surface, p) then
                    -- pcall 防御：实体名缺失/放置失败不中断地形生成（world_15 同因注释）
                    local ent = nil
                    local ok = pcall(function()
                        ent = surface.create_entity({name = pool[math.random(#pool)], position = p})
                    end)
                    if ok and ent and ent.valid then
                        placed = placed + 1
                    end
                end
            end
        end
    end
    place_decorations(rock_pool, math.random(40, 60))
    place_decorations(tree_pool, math.random(60, 100))

    -- 中心钢箱：休息室传送箱（不可摧毁/不可挖掘、玩家可打开放入物品）
    -- 每 10 秒把箱内物品单向传送到主世界绑定木箱（只输出，不输入）
    local steel_chest = surface.create_entity({
        name = "steel-chest",
        position = {0, 0},
        force = player.force
    })
    if steel_chest and steel_chest.valid then
        steel_chest.destructible = false
        steel_chest.minable_flag = false
        -- operable 默认 true：玩家可打开放入物品
        data.module_data.steel_chest = steel_chest

        -- 写回绑定表：全局传送调度（无人在线也照常运行）以绑定表为数据源
        -- （绑定表已由框架 enter 在 on_surface_init 之前写入，此处仅补 steel_chest 字段）
        local bindings = WPT.get().lounge_bindings
        if bindings and data.lounge_unit_number and bindings[data.lounge_unit_number] then
            bindings[data.lounge_unit_number].steel_chest = steel_chest
        end

        rendering.draw_text({
            text = {'amap.lounge_steel_chest_tag'},
            surface = surface,
            target = {
                entity = steel_chest,
                offset = {0, -2.6}
            },
            color = {r = 1, g = 0.5, b = 0},
            scale = 1.05,
            font = "default-large-semibold",
            alignment = "center"
        })
    end

    -- 地图标签标注中心（参考史诗木箱 tag 创建；Factorio 2.x add_chart_tag 只接受纯字符串文本）
    game.forces.player.add_chart_tag(surface, {
        position = {0, 0},
        icon = {type = 'item', name = 'steel-chest'},
        text = '休息室传送箱'
    })
end

--==============================================================================
-- 传送（全局 600 tick：钢箱物品 → 绑定木箱）
-- 以绑定表为数据源，独立于玩家在线状态运行（休息室是永久传送通道）
--==============================================================================

-- 执行一次传送：遍历钢箱 inventory，把每格物品插入绑定木箱
-- 绑定木箱满 → 剩余留箱（下次再传）；绑定木箱失效（被摧毁）→ destroy_lounge 强制清理整个休息室
local function transfer_from_binding(unit_number, binding)
    local surface = game.surfaces[binding.surface_name]
    if not surface then return end

    -- 中心钢箱（绑定表缓存引用，失效则 position 精确重找并写回）
    -- position 精确查找：中心钢箱实体中心在 (0,0)，半径 0.75 只覆盖 (0,0) 一格，
    -- 不会误命中玩家放在邻格的钢箱
    local steel_chest = binding.steel_chest
    if not steel_chest or not steel_chest.valid then
        local chests = surface.find_entities_filtered({name = 'steel-chest', position = {0, 0}, radius = 0.75})
        steel_chest = chests[1] or nil
        binding.steel_chest = steel_chest
    end
    if not steel_chest or not steel_chest.valid then return end

    -- 绑定木箱（失效 → 木箱没了，休息室副本该删除）
    local chest = binding.entity
    if not chest or not chest.valid then
        Instance.destroy_lounge(unit_number)
        return
    end

    -- 箱内物品全量插入绑定木箱（目标满则剩余留箱，下次再传）
    local source_inv = steel_chest.get_inventory(defines.inventory.chest)
    local target_inv = chest.get_inventory(defines.inventory.chest)
    if not source_inv or not target_inv then return end

    local transferred = 0
    for i = 1, #source_inv do
        local item = source_inv[i]
        if item.valid_for_read then
            local inserted = target_inv.insert({
                name = item.name,
                count = item.count,
                quality = item.quality
            })
            if inserted > 0 then
                source_inv.remove({name = item.name, count = inserted, quality = item.quality})
                transferred = transferred + inserted
            end
        end
    end

    -- 传送成功且有物品：给该 surface 上所有在线玩家飞字提示（无人在线则静默，不影响传送本身）
    if transferred > 0 then
        local this = WPT.get()
        if this.dungeons then
            for p_index, d in pairs(this.dungeons) do
                if d.active and d.surface_name == binding.surface_name then
                    local p = game.players[p_index]
                    if p and p.valid and p.connected then
                        p.create_local_flying_text({
                            text = {'amap.lounge_transferred'},
                            position = steel_chest.position,
                            color = {r = 0, g = 1, b = 0},
                            time_to_live = 90
                        })
                    end
                end
            end
        end
    end
end

-- 全局传送调度：每 600 tick（10 秒）遍历所有休息室绑定，surface 存在即传送
-- 不依赖任何玩家在线状态；绑定木箱存在 → 传送通道常开
local function global_transfer_tick()
    local bindings = WPT.get().lounge_bindings
    if not bindings then return end

    for unit_number, binding in pairs(bindings) do
        -- surface 随绑定记录常驻；异常缺失（如未重建）时跳过本次
        if binding.surface_name and game.surfaces[binding.surface_name] then
            transfer_from_binding(unit_number, binding)
        end
    end
end

--==============================================================================
-- 钩子实现
--==============================================================================

-- 进入副本：无初始物品（物资需玩家自带；中心钢箱传送只输出）
function M.on_enter(player, data, difficulty)
    -- 无初始物品；科技天然继承（保持玩家原阵营）
end

-- 退出副本：无模块级 GUI 清理；surface 保留由框架 lounge_binding 处理
-- 不调用 set_reward_multiplier（休息室无奖励，reward_multiplier 保持 0）
function M.on_exit(player, data, reason)
    -- 无清理内容
end

--==============================================================================
-- 注册到框架
--==============================================================================

Instance.register(M.type, M)

-- 全局传送调度：每 600 tick（10 秒）一次，独立于玩家在线状态
-- （场景加载链 require 时注册，早于 on_init，满足 utils/event.lua 的 desync 保护断言）
Event.on_nth_tick(600, global_transfer_tick)

return M
