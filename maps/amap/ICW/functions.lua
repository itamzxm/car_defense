local ICW = require 'maps.amap.ICW.table'
local WPT = require 'maps.amap.table'

local Public = {}
local main_tile_name = 'black-refined-concrete'
local hazard_tile_name = 'hazard-concrete-right'
local raise_event = script.raise_event

local function validate_entity(entity)
    if not (entity and entity.valid) then
        return false
    end
    if type(entity) == 'boolean' then
        return false
    end
    return true
end

------------------------------------------------------------
-- 火车内部 Surface 创建（所有车厢共用一个 surface）
------------------------------------------------------------
function Public.create_train_surface(unit_number)
    local surface_name = tostring(unit_number)
    if game.surfaces[surface_name] then
        return game.surfaces[surface_name].index
    end

    local map_gen_settings = {
        ['width'] = 4,
        ['height'] = 4,
        ['water'] = 0,
        ['starting_area'] = 1,
        ['cliff_settings'] = {cliff_elevation_interval = 0, cliff_elevation_0 = 0},
        ['default_enable_all_autoplace_controls'] = false,
        ['autoplace_settings'] = {
            ['entity'] = {treat_missing_as_default = false},
            ['tile'] = {treat_missing_as_default = false},
            ['decorative'] = {treat_missing_as_default = false}
        }
    }
    local surface = game.create_surface(surface_name, map_gen_settings)
    surface.freeze_daytime = true
    surface.daytime = 0.1
    surface.request_to_generate_chunks({0, 0}, 2)
    surface.force_generate_chunk_requests()

    -- 将所有生成的 tile 替换为 out-of-map，防止自动生成资源
    local tiles = {}
    for _, tile in pairs(surface.find_tiles_filtered({})) do
        tiles[#tiles + 1] = {name = 'out-of-map', position = tile.position}
    end
    if #tiles > 0 then
        surface.set_tiles(tiles, true)
    end

    return surface.index
end

------------------------------------------------------------
-- 铺设瓷砖
-- 所有车厢共用同一 surface，纵向拼接，车厢之间需要连通
-- 因此在车厢连接边界（上一节车厢的 right_bottom.y == 下一节的 left_top.y）
-- 铺上连接瓷砖，并用警示瓷砖标记连接处
------------------------------------------------------------
local function lay_tiles(surface, area, is_first, is_last)
    local tiles = {}

    -- 主区域铺设黑色精炼混凝土（铺满整个区域，确保车厢之间连通）
    for x = area.left_top.x, area.right_bottom.x - 1 do
        for y = area.left_top.y, area.right_bottom.y - 1 do
            tiles[#tiles + 1] = {name = main_tile_name, position = {x, y}}
        end
    end

    -- 入口区域铺设瓷砖
    for x = -3, 2 do
        for y = area.right_bottom.y - 4, area.right_bottom.y - 2 do
            tiles[#tiles + 1] = {name = main_tile_name, position = {x, y}}
        end
    end

    -- 车厢连接边界：用警示瓷砖标记（上一节车厢底部 = 下一节车厢顶部）
    -- 不是第一节车厢时，在顶部边界铺警示瓷砖
    if not is_first then
        for x = area.left_top.x, area.right_bottom.x - 1 do
            tiles[#tiles + 1] = {name = hazard_tile_name, position = {x, area.left_top.y}}
        end
    end

    -- 不是最后一节车厢时，在底部边界铺警示瓷砖
    if not is_last then
        for x = area.left_top.x, area.right_bottom.x - 1 do
            tiles[#tiles + 1] = {name = hazard_tile_name, position = {x, area.right_bottom.y - 1}}
        end
    end

    -- 如果是最后一节车厢，底部边界铺警示瓷砖（原来逻辑）
    if is_last then
        for x = area.left_top.x, area.right_bottom.x - 1 do
            tiles[#tiles + 1] = {name = hazard_tile_name, position = {x, area.right_bottom.y - 1}}
        end
    end

    surface.set_tiles(tiles, true)
end

------------------------------------------------------------
-- 构建门（进出传送点）
------------------------------------------------------------
local function construct_doors(wagon)
    local area = wagon.area
    local surface_index = wagon.surface
    local surface = game.surfaces[surface_index]
    if not surface or not surface.valid then
        return
    end

    local doors = ICW.get('doors')

    -- 清理旧门（防止重复重建）
    if wagon.doors and #wagon.doors > 0 then
        for _, door in pairs(wagon.doors) do
            if door and door.valid then
                doors[door.unit_number] = nil
                door.destroy()
            end
        end
        wagon.doors = {}
    end
    wagon.doors = {}

    -- 在车厢两侧各创建一个门（car 实体作为传送触发器）
    for _, x in pairs({area.left_top.x - 1.5, area.right_bottom.x + 1.5}) do
        local p = {x = x, y = area.left_top.y + ((area.right_bottom.y - area.left_top.y) * 0.5)}
        if p.x < 0 then
            surface.set_tiles({{name = main_tile_name, position = {x = p.x + 0.5, y = p.y}}}, true)
        else
            surface.set_tiles({{name = main_tile_name, position = {x = p.x - 1, y = p.y}}}, true)
        end
        local e =
            surface.create_entity(
            {
                name = 'car',
                position = {x, area.left_top.y + ((area.right_bottom.y - area.left_top.y) * 0.5)},
                force = 'neutral',
                create_build_effect_smoke = false
            }
        )
        e.destructible = false
        e.minable_flag = false
        e.operable = false
        e.get_inventory(defines.inventory.fuel).insert({name = 'coal', count = 1})
        if type(wagon.entity) == 'boolean' then
            return
        end
        doors[e.unit_number] = wagon.entity.unit_number
        wagon.doors[#wagon.doors + 1] = e
    end
end

------------------------------------------------------------
-- 创建车厢内部 linked-chest
------------------------------------------------------------
local function create_linked_chests(surface, area, wagon_unit_number)
    local chests = {}
    local half_w = math.floor((area.right_bottom.x - area.left_top.x) / 2)
    -- 在车厢四角各放 1 个 linked-chest，共 4 个
    -- 上排 2 个为输入箱，下排 2 个为输出箱
    local positions = {
        {area.left_top.x + 3, area.left_top.y + 5},
        {area.right_bottom.x - 4, area.left_top.y + 5},
        {area.left_top.x + 3, area.right_bottom.y - 6},
        {area.right_bottom.x - 4, area.right_bottom.y - 6}
    }

    for i, pos in ipairs(positions) do
        local e =
            surface.create_entity(
            {
                name = 'linked-chest',
                position = pos,
                force = 'player',
                create_build_effect_smoke = false
            }
        )
        e.destructible = false
        e.minable_flag = false
        -- linked_chest_link_id 用于跨车厢链接
        -- 使用 wagon 的 unit_number 作为 link_id 的一部分
        e.link_id = wagon_unit_number * 100 + i
        chests[#chests + 1] = e
    end

    return chests
end

------------------------------------------------------------
-- 创建商店（市场实体）
------------------------------------------------------------
local function create_market(surface, position)
    local market =
        surface.create_entity(
        {
            name = 'market',
            position = position,
            force = 'player',
            create_build_effect_smoke = false
        }
    )
    market.destructible = false
    market.minable_flag = false
    return market
end

------------------------------------------------------------
-- 创建单节车厢的内部房间
------------------------------------------------------------
function Public.create_wagon_room(wagon)
    local surface_index = wagon.surface
    local surface = game.surfaces[surface_index]
    local entity_name = wagon.name
    local area = wagon.area

    if not area then
        return
    end

    -- 确保该车厢区域的 chunk 已生成
    local center = {
        x = (area.left_top.x + area.right_bottom.x) / 2,
        y = (area.left_top.y + area.right_bottom.y) / 2
    }
    local radius = math.ceil(math.max(
        (area.right_bottom.x - area.left_top.x) / 64,
        (area.right_bottom.y - area.left_top.y) / 64
    )) + 1
    surface.request_to_generate_chunks(center, radius)
    surface.force_generate_chunk_requests()

    -- 将新区域的 tile 替换为 out-of-map
    local tiles = {}
    for _, tile in pairs(surface.find_tiles_filtered({area = area})) do
        tiles[#tiles + 1] = {name = 'out-of-map', position = tile.position}
    end
    if #tiles > 0 then
        surface.set_tiles(tiles, true)
    end

    -- 确定是否为第一节/最后一节车厢（用于 lay_tiles 的警示瓷砖逻辑）
    local wagons = ICW.get('wagons')
    local is_first = true
    local is_last = true
    for _, w in pairs(wagons) do
        if w.surface == surface_index and w.area and w ~= wagon then
            if w.area.left_top.y < wagon.area.left_top.y then
                is_first = false  -- 有车厢在上方，不是第一节
            end
            if w.area.left_top.y > wagon.area.left_top.y then
                is_last = false   -- 有车厢在下方，不是最后一节
            end
        end
    end

    -- 铺设瓷砖（传入 is_first / is_last 标记）
    lay_tiles(surface, area, is_first, is_last)

    -- 更新 surface 的 map_gen_settings
    local mgs = surface.map_gen_settings
    mgs.width = area.right_bottom.x * 2
    mgs.height = area.right_bottom.y * 2
    surface.map_gen_settings = mgs

    -- 构建门
    construct_doors(wagon)

    -- 创建 linked-chest（cargo-wagon 才有）
    if entity_name == 'cargo-wagon' then
        local chests = create_linked_chests(surface, area, wagon.entity.unit_number)
        wagon.chests = chests
        
        -- 添加输入/输出标签（上排为输入，下排为输出）
        -- 注意：当箱子销毁时，Factorio 会自动清理附着在其上的渲染对象
        for i, chest in ipairs(chests) do
            local is_input = (i <= 2)  -- 前两个是输入箱（上排）
            local label = is_input and '输入箱' or '输出箱'
            local color = is_input and {r=0.2, g=0.8, b=0.2, a=1} or {r=0.8, g=0.2, b=0.2, a=1}
            
            rendering.draw_text{
                text = label,
                surface = surface,
                target = chest,
                target_offset = {0, -1.5},
                color = color,
                scale = 1.5,
                font = "default-large-semibold",
                alignment = "center",
                scale_with_zoom = false
            }
        end
    end

    -- fluid-wagon（油罐车）不需要箱子，创建存储罐用于流体转移
    if entity_name == 'fluid-wagon' then
        local height = area.right_bottom.y - area.left_top.y
        local positions = {
            {area.right_bottom.x, area.left_top.y + height * 0.25},
            {area.right_bottom.x, area.left_top.y + height * 0.75},
            {area.left_top.x - 1, area.left_top.y + height * 0.25},
            {area.left_top.x - 1, area.left_top.y + height * 0.75}
        }
        table.shuffle_table(positions)
        local e = surface.create_entity{
            name = 'storage-tank',
            position = positions[1],
            force = 'neutral',
            create_build_effect_smoke = false
        }
        e.destructible = false
        e.minable_flag = false
        wagon.transfer_entities = {e}
    end
end

------------------------------------------------------------
-- 注册一节车厢到 ICW 系统
-- 所有车厢共用同一个 surface（以 locomotive 的 unit_number 命名）
-- 内部空间纵向拼接：locomotive 在 y=0~50，cargo-wagon 依次追加
------------------------------------------------------------
function Public.register_wagon(entity, owner_player_index)
    if not validate_entity(entity) then
        return nil
    end

    local un = entity.unit_number
    if not un then
        return nil
    end

    local wagons = ICW.get('wagons')

    -- 幂等性检查：如果车厢已注册，直接返回现有数据，不重复创建
    if wagons[un] then
        return wagons[un]
    end

    local wagon_areas = ICW.get('wagon_areas')
    local wagon_area = wagon_areas[entity.name]

    if not wagon_area then
        return nil
    end

    -- 确定 surface 和 y 偏移
    local surface_index
    local y_offset = 0
    local locomotive = ICW.get('locomotive')

    if entity.name == 'locomotive' then
        -- locomotive 创建共享 surface
        surface_index = Public.create_train_surface(un)
        ICW.set('train_surface', surface_index)
        ICW.set('train_surface_name', tostring(un))
    else
        -- cargo-wagon 使用共享 surface，计算 y 偏移
        if locomotive and locomotive.valid then
            local loco_wagon = wagons[locomotive.unit_number]
            if loco_wagon then
                surface_index = loco_wagon.surface
            end
        end
        if not surface_index then
            -- 如果没有 locomotive，自己创建
            surface_index = Public.create_train_surface(un)
        end

        -- 计算当前车厢的 y 偏移：已注册车厢的 right_bottom.y 最大值
        for _, w in pairs(wagons) do
            if w.surface == surface_index and w.area and w.area.right_bottom.y > y_offset then
                y_offset = w.area.right_bottom.y
            end
        end
    end

    wagons[un] = {
        entity = entity,
        area = {
            left_top = {x = wagon_area.left_top.x, y = wagon_area.left_top.y + y_offset},
            right_bottom = {x = wagon_area.right_bottom.x, y = wagon_area.right_bottom.y + y_offset}
        },
        doors = {},
        owner = owner_player_index,
        name = entity.name,
        type = entity.type,
        chests = {},
        market = nil,
        transfer_entities = {},
        surface = surface_index
    }

    local wagon = wagons[un]
    Public.create_wagon_room(wagon)

    return wagon
end

------------------------------------------------------------
-- 初始化火车（locomotive + 初始铁轨）
------------------------------------------------------------
function Public.spawn_train(surface, position, force)
    local icw = ICW.get()

    -- 预铺设铁轨
    local rail_positions = {}
    for i = -5, 20 do
        local rail_pos = {x = position.x, y = position.y + i}
        surface.create_entity(
            {
                name = 'straight-rail',
                position = rail_pos,
                direction = defines.direction.north,
                force = force,
                create_build_effect_smoke = false
            }
        )
    end

    -- 创建 locomotive
    local loco =
        surface.create_entity(
        {
            name = 'locomotive',
            position = position,
            direction = defines.direction.north,
            force = force,
            create_build_effect_smoke = false
        }
    )
    loco.minable_flag = false
    loco.get_inventory(defines.inventory.fuel).insert({name = 'coal', count = 50})

    -- 注册 locomotive 到 ICW
    local wagon = Public.register_wagon(loco, 0) -- owner=0 表示公共火车
    if wagon then
        icw.locomotive = loco
    end

    -- 创建火车光圈显示（半径70，仅Alt模式下可见，与汽车光圈风格一致）
    icw.train_circle = rendering.draw_circle {
        surface = loco.surface,
        target = loco,
        color = {r = 1, g = 0.6, b = 0.1},
        filled = false,
        radius = 70,
        players = game.forces.player.players,
        only_in_alt_mode = true
    }

    return loco
end

------------------------------------------------------------
-- 追加 cargo-wagon
------------------------------------------------------------
function Public.add_cargo_wagon()
    local icw = ICW.get()
    local loco = icw.locomotive
    if not validate_entity(loco) then
        return nil
    end

    local surface = loco.surface
    local force = loco.force
    local wagon_count = icw.wagon_count

    -- 每节 cargo-wagon 在 locomotive 后方间隔 7 格
    local wagon_y = loco.position.y + 7 * (wagon_count + 1)
    local wagon_pos = {x = loco.position.x, y = wagon_y}

    -- 铺设铁轨
    for i = 0, 6 do
        local rail_pos = {x = loco.position.x, y = wagon_y + i}
        surface.create_entity(
            {
                name = 'straight-rail',
                position = rail_pos,
                direction = defines.direction.north,
                force = force,
                create_build_effect_smoke = false
            }
        )
    end

    -- 创建 cargo-wagon
    local cargo =
        surface.create_entity(
        {
            name = 'cargo-wagon',
            position = wagon_pos,
            direction = defines.direction.north,
            force = force,
            create_build_effect_smoke = false
        }
    )
    cargo.minable_flag = false

    -- 注册到 ICW
    local wagon = Public.register_wagon(cargo, 0)
    if wagon then
        icw.cargo_wagons[cargo.unit_number] = cargo
        icw.wagon_count = wagon_count + 1
    end

    return cargo
end

------------------------------------------------------------
-- 重建所有车厢的内部空间（编组变化后调用）
------------------------------------------------------------
function Public.reconstruct_train()
    local icw = ICW.get()
    local wagons = ICW.get('wagons')

    for un, wagon in pairs(wagons) do
        if validate_entity(wagon.entity) then
            -- 重建内部房间
            Public.create_wagon_room(wagon)
        else
            -- 清理无效车厢
            wagons[un] = nil
        end
    end
end

------------------------------------------------------------
-- 玩家进出传送逻辑
------------------------------------------------------------
function Public.use_door_with_entity(player, door)
    if not validate_entity(door) then
        return
    end

    local doors = ICW.get('doors')
    local wagons = ICW.get('wagons')

    local wagon = false
    if doors[door.unit_number] then
        wagon = wagons[doors[door.unit_number]]
    end
    if wagons[door.unit_number] then
        wagon = wagons[door.unit_number]
    end
    if not wagon then
        return
    end

    if not validate_entity(wagon.entity) then
        return
    end

    local player_data = Public.get_player_data(player)

    if validate_entity(wagon.entity) and wagon.entity.surface.name == player.physical_surface.name then
        -- 从外部进入内部
        local surface_index = wagon.surface
        local surface = game.surfaces[surface_index]
        if not validate_entity(surface) then
            return
        end

        local area = wagon.area
        local x_vector = door.position.x - player.physical_position.x
        local position
        if x_vector > 0 then
            position = {area.left_top.x + 0.5, area.left_top.y + ((area.right_bottom.y - area.left_top.y) * 0.5)}
        else
            position = {area.right_bottom.x - 0.5, area.left_top.y + ((area.right_bottom.y - area.left_top.y) * 0.5)}
        end

        -- 距离检查
        local dist = math.sqrt(
            (player.physical_position.x - wagon.entity.position.x) ^ 2 +
            (player.physical_position.y - wagon.entity.position.y) ^ 2
        )
        if dist > 10 then
            return
        end

        local p = surface.find_non_colliding_position('character', position, 128, 0.5)
        if p then
            player.teleport(p, surface)
        else
            player.teleport(position, surface)
        end
        player_data.surface = surface.index
    else
        -- 从内部出去到外部
        local surface = wagon.entity.surface
        local x_vector = (door.position.x / math.abs(door.position.x)) * 2
        local position = {wagon.entity.position.x + x_vector, wagon.entity.position.y}
        local surface_position = surface.find_non_colliding_position('character', position, 128, 0.5)
        if surface_position then
            player.teleport(surface_position, surface)
        else
            player.teleport(position, surface)
        end
        -- locomotive: 恢复驾驶状态
        if wagon.entity.type == 'locomotive' then
            player_data.state = 2
            player.driving = true
        end
        player_data.surface = surface.index
    end
end

------------------------------------------------------------
-- 玩家数据管理
------------------------------------------------------------
function Public.get_player_data(player)
    local players = ICW.get('players')
    local player_data = players[player.index]
    if player_data then
        return player_data
    end
    local fallback = WPT.get('active_surface_index')
    if not fallback then
        fallback = 1
    end

    players[player.index] = {
        surface = 1,
        fallback_surface = tonumber(fallback),
        notified = false
    }
    return players[player.index]
end

------------------------------------------------------------
-- 将玩家踢出内部空间
------------------------------------------------------------
function Public.kick_players_from_wagon(wagon)
    local surface_index = wagon.surface
    local surface = game.surfaces[surface_index]
    local allowed_surface = ICW.get('allowed_surface')

    if not validate_entity(surface) then
        return
    end

    if not validate_entity(wagon.entity) then
        local main_surface = game.surfaces[allowed_surface]
        if validate_entity(main_surface) then
            for _, e in pairs(surface.find_entities_filtered({area = wagon.area})) do
                if validate_entity(e) and e.name == 'character' and e.player then
                    e.player.teleport(
                        main_surface.find_non_colliding_position(
                            'character',
                            game.forces.player.get_spawn_position(main_surface),
                            3, 0, 5
                        ),
                        main_surface
                    )
                end
            end
        end
        return
    end

    for _, e in pairs(surface.find_entities_filtered({area = wagon.area})) do
        if validate_entity(e) and e.name == 'character' and e.player then
            local p = wagon.entity.surface.find_non_colliding_position('character', wagon.entity.position, 128, 0.5)
            if p then
                e.player.teleport(p, wagon.entity.surface)
            else
                e.player.teleport(wagon.entity.position, wagon.entity.surface)
            end
        end
    end
end

------------------------------------------------------------
-- 清理单节车厢内部实体（门、箱子、transfer_entities、市场）
-- 不删除 surface，也不从 wagons 表移除（由调用者处理）
------------------------------------------------------------
local function destroy_wagon_contents(wagon)
    local doors = ICW.get('doors')

    -- 清理门
    for k, e in pairs(wagon.doors) do
        if validate_entity(e) then
            doors[e.unit_number] = nil
            e.destroy()
            wagon.doors[k] = nil
        end
    end

    -- 清理箱子
    if wagon.chests then
        for _, chest in pairs(wagon.chests) do
            if validate_entity(chest) then
                chest.destroy()
            end
        end
    end

    -- 清理 transfer_entities
    if wagon.transfer_entities then
        for _, e in pairs(wagon.transfer_entities) do
            if validate_entity(e) then
                e.destroy()
            end
        end
    end

    -- 清理市场（locomotive 才有）
    if wagon.market and validate_entity(wagon.market) then
        wagon.market.destroy()
    end

    -- 将车厢区域内的所有瓷砖替换为 out-of-map，消除内部空间痕迹
    local surface_index = wagon.surface
    if surface_index then
        local area = wagon.area
        local surface = game.surfaces[surface_index]
        if area and surface and surface.valid then
            -- 车厢主区域
            for _, tile in pairs(surface.find_tiles_filtered({ area = area })) do
                surface.set_tiles({ { name = 'out-of-map', position = tile.position } }, true)
            end
            -- 门周围区域
            for _, x in pairs({ area.left_top.x - 1.5, area.right_bottom.x + 1.5 }) do
                local p = { x = x, y = area.left_top.y + ((area.right_bottom.y - area.left_top.y) * 0.5) }
                surface.set_tiles({ { name = 'out-of-map', position = { x = p.x + 0.5, y = p.y } } }, true)
                surface.set_tiles({ { name = 'out-of-map', position = { x = p.x - 1, y = p.y } } }, true)
            end
            -- 更新小地图
            local chart_area = table.deepcopy(area)
            chart_area.left_top.x = chart_area.left_top.x - 5
            chart_area.right_bottom.x = chart_area.right_bottom.x + 5
            game.forces.player.chart(surface, chart_area)
        end
    end
end

------------------------------------------------------------
-- 完全清理所有车厢（火车头被摧毁时使用）
-- 清理所有车厢内部实体，删除 surface，清空数据表
------------------------------------------------------------
local function destroy_all()
    local wagons = ICW.get('wagons')
    local icw = ICW.get()

    -- 1. 清理每节车厢的内部实体
    for un, wagon in pairs(wagons) do
        Public.kick_players_from_wagon(wagon)
        destroy_wagon_contents(wagon)
        wagons[un] = nil
    end

    -- 2. 删除 surface
    local train_surface = icw.train_surface
    if train_surface then
        local surface = game.surfaces[train_surface]
        if surface and surface.valid then
            game.delete_surface(surface)
        end
        icw.train_surface = nil
    end

    -- 3. 清理其他数据引用
    icw.doors = {}
    icw.train_circle = nil
    icw.locomotive = nil
    icw.cargo_wagons = {}
    icw.train_health = 0
    icw.renders = {}
end

------------------------------------------------------------
-- 销毁单节车厢内部空间（车头被摧毁时调用 destroy_all）
------------------------------------------------------------
function Public.kill_wagon(entity)
    if not entity or not entity.valid then
        return
    end

    local un = entity.unit_number
    local wagons = ICW.get('wagons')
    local wagon = wagons[un]

    if not wagon then
        return
    end

    -- 如果被摧毁的是 LOCOMOTIVE → 摧毁所有车厢+surface
    if entity.type == 'locomotive' then
        destroy_all()
        return
    end

    -- 如果被摧毁的是 CARGO-WAGON → 只清理这一节

    -- 踢出车厢内玩家
    Public.kick_players_from_wagon(wagon)

    -- 清理内部实体 + 将瓷砖铺回 out-of-map + 更新小地图
    destroy_wagon_contents(wagon)

    -- 从 wagons 表移除
    wagons[un] = nil

    -- 检查 surface 是否仍被其他车厢使用
    local has_other = false
    local icw = ICW.get()
    for _, w in pairs(wagons) do
        if w.surface == wagon.surface then
            has_other = true
            break
        end
    end

    if not has_other then
        local surface = game.surfaces[wagon.surface]
        if surface and surface.valid then
            game.delete_surface(surface)
        end
        if icw.train_surface == wagon.surface then
            icw.train_surface = nil
        end
    end
end

------------------------------------------------------------
-- 清理无效车厢
------------------------------------------------------------
function Public.remove_invalid_wagons()
    local wagons = ICW.get('wagons')
    local to_remove = {}
    for un, wagon in pairs(wagons) do
        if not validate_entity(wagon.entity) then
            to_remove[#to_remove + 1] = un
        end
    end
    for _, un in ipairs(to_remove) do
        local wagon = wagons[un]
        if wagon then
            -- 踢出车厢内玩家，恢复瓷砖为 out-of-map，销毁内部实体
            Public.kick_players_from_wagon(wagon)
            destroy_wagon_contents(wagon)
            wagons[un] = nil
        end
    end

    -- 检查是否还有车厢，如果没有则删除 surface
    local has_wagons = false
    for _, _ in pairs(wagons) do
        has_wagons = true
        break
    end
    if not has_wagons then
        local train_surface = ICW.get('train_surface')
        if train_surface then
            local surface = game.surfaces[train_surface]
            if surface and surface.valid then
                game.delete_surface(surface)
            end
            ICW.set('train_surface', nil)
        end
    end
end

------------------------------------------------------------
-- 重新扫描火车编组，注册新连接的车厢
-- 当火车编组发生变化时（新车厢连接/创建），自动检测并注册
------------------------------------------------------------
function Public.rescan_train_wagons()
    local icw = ICW.get()
    local loco = icw.locomotive
    if not validate_entity(loco) then
        return false
    end

    local train = loco.train
    if not train then
        return false
    end

    local carriages = train.carriages
    if not carriages then
        return false
    end

    local wagons = ICW.get('wagons')
    local changed = false

    for _, carriage in ipairs(carriages) do
        if carriage.valid and (carriage.type == 'locomotive' or carriage.type == 'cargo-wagon' or carriage.type == 'fluid-wagon') then
            local un = carriage.unit_number
            if not wagons[un] then
                -- 新车厢未注册到 ICW，注册它
                Public.register_wagon(carriage, 0)
                changed = true
            end
        end
    end

    return changed
end

------------------------------------------------------------
-- 均分油罐车与存储罐之间的流体
------------------------------------------------------------
local function equal_fluid(wagon, storage_tank)
    if not validate_entity(wagon.entity) then
        return
    end
    if not storage_tank or not storage_tank.valid then
        return
    end

    local source_fluid = wagon.entity.get_fluid(1)
    if not source_fluid then
        return
    end

    local target_fluid = storage_tank.get_fluid(1)
    local source_amount = source_fluid.amount

    local amount
    if target_fluid then
        amount = source_amount - ((target_fluid.amount + source_amount) * 0.5)
    else
        amount = source_amount * 0.5
    end

    if amount <= 1 then
        return
    end

    if amount > 0 then
        local inserted = storage_tank.insert_fluid{
            name = source_fluid.name,
            amount = amount,
            temperature = source_fluid.temperature
        }
        if inserted > 0 then
            wagon.entity.extract_fluid({name = source_fluid.name, amount = inserted})
        end
    end
end

------------------------------------------------------------
-- 物品/流体转移调度
-- cargo-wagon: inventory <-> 内部 linked-chest
-- fluid-wagon: 流体 <-> 内部 storage-tank
------------------------------------------------------------
function Public.item_transfer()
    local wagons = ICW.get('wagons')
    for _, wagon in pairs(wagons) do
        if validate_entity(wagon.entity) and wagon.entity.active then
            -- fluid-wagon: 通过 transfer_entities 进行流体均分
            if wagon.name == 'fluid-wagon' and wagon.transfer_entities then
                for _, e in pairs(wagon.transfer_entities) do
                    if validate_entity(e) then
                        equal_fluid(wagon, e)
                    end
                end
            end

            -- cargo-wagon: 通过 linked-chest 进行物品转移
            if wagon.chests then
                local car_inv
                if wagon.name == 'cargo-wagon' then
                    car_inv = wagon.entity.get_inventory(defines.inventory.cargo_wagon)
                end
                if car_inv then
                    local area = wagon.area
                    if area then
                        local room_middle_y = (area.left_top.y + area.right_bottom.y) / 2
                        
                        for _, chest in pairs(wagon.chests) do
                            if validate_entity(chest) then
                                local chest_inv = chest.get_inventory(defines.inventory.chest)
                                if chest_inv then
                                    if chest.position.y >= room_middle_y then
                                        -- 下排箱子（输出箱）：把箱子里的物品转移到 cargo-wagon 库存
                                        for i = 1, #chest_inv do
                                            local stack = chest_inv[i]
                                            if stack.valid_for_read then
                                                local inserted = car_inv.insert({name = stack.name, count = stack.count})
                                                if inserted > 0 then
                                                    stack.count = stack.count - inserted
                                                end
                                            end
                                        end
                                    end
                                    -- 上排箱子（输入箱）不处理
                                    -- 物品通过 linked-chest 自动从车外同步到箱内，玩家可手动取用
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end

------------------------------------------------------------
-- 火车生命值系统
------------------------------------------------------------
function Public.get_train_health()
    return ICW.get('train_health') or 0
end

function Public.get_train_max_health()
    return ICW.get('train_max_health') or 10000
end

function Public.set_train_health(health)
    ICW.set('train_health', health)
end

function Public.damage_train(amount)
    local health = Public.get_train_health()
    health = health - amount
    if health < 0 then
        health = 0
    end
    Public.set_train_health(health)

    -- 同步所有车厢的健康比例
    local max_health = Public.get_train_max_health()
    local ratio = health / max_health
    local wagons = ICW.get('wagons')
    for _, wagon in pairs(wagons) do
        if validate_entity(wagon.entity) then
            wagon.entity.health = wagon.entity.max_health * ratio
        end
    end

    return health
end

function Public.heal_train(amount)
    local health = Public.get_train_health()
    local max_health = Public.get_train_max_health()
    health = math.min(health + amount, max_health)
    Public.set_train_health(health)

    -- 同步所有车厢的健康比例
    local ratio = health / max_health
    local wagons = ICW.get('wagons')
    for _, wagon in pairs(wagons) do
        if validate_entity(wagon.entity) then
            wagon.entity.health = wagon.entity.max_health * ratio
        end
    end

    return health
end

------------------------------------------------------------
-- 检查玩家是否在火车内部空间
------------------------------------------------------------
function Public.is_player_in_train(player)
    local surfaces = ICW.get('surfaces')
    for _, index in pairs(surfaces) do
        local surface = game.surfaces[index]
        if validate_entity(surface) then
            if surface.index == player.physical_surface.index then
                return true
            end
        end
    end
    return false
end

------------------------------------------------------------
-- 获取火车位置
------------------------------------------------------------
function Public.get_train_position()
    local loco = ICW.get('locomotive')
    if validate_entity(loco) then
        return loco.position
    end
    return nil
end

------------------------------------------------------------
-- 世界13 地面战利品车厢生成系统
------------------------------------------------------------

-- 获取玩家实际控制的车厢数量（ICW中已注册的有效车厢）
function Public.count_controlled_wagons()
    local wagons = ICW.get('wagons')
    local count = 0
    for _, wagon in pairs(wagons) do
        if validate_entity(wagon.entity) then
            count = count + 1
        end
    end
    return count
end

-- 在地面生成战利品车厢（每700米一个）
-- 返回 true 表示成功生成
function Public.spawn_loot_wagon_on_map(surface, position)
    local icw = ICW.get()
    local index = icw.loot_wagon_index or 0

    -- 条件1：玩家实际控制的车厢 ≤ 10
    if Public.count_controlled_wagons() > 10 then
        return false
    end

    -- 条件2：地图上未领取的车厢 < 3
    local map_count = 0
    for _, _ in pairs(icw.loot_wagons_on_map) do
        map_count = map_count + 1
    end
    if map_count >= 3 then
        return false
    end

    -- 确定车厢类型：
    -- 第一个 = cargo-wagon，第二个 = fluid-wagon，之后随机
    index = index + 1
    local wagon_type
    if index == 1 then
        wagon_type = 'cargo-wagon'
    elseif index == 2 then
        wagon_type = 'fluid-wagon'
    else
        wagon_type = math.random(2) == 1 and 'cargo-wagon' or 'fluid-wagon'
    end

    -- 铺设铁轨（3段：前后各1段让连接更顺畅）
    for dy = -1, 1 do
        local rail_pos = {x = position.x, y = position.y + dy}
        local existing = surface.find_entities_filtered{name = 'straight-rail', position = rail_pos}
        if #existing == 0 then
            surface.create_entity{
                name = 'straight-rail',
                position = rail_pos,
                direction = defines.direction.north,
                force = 'player',
                create_build_effect_smoke = false
            }
        end
    end

    -- 生成车厢实体
    local entity = surface.create_entity{
        name = wagon_type,
        position = position,
        direction = defines.direction.north,
        force = 'player',
        create_build_effect_smoke = false
    }
    if not entity or not entity.valid then
        return false
    end

    entity.minable_flag = false

    -- 注册到跟踪表
    icw.loot_wagon_index = index
    icw.loot_wagons_on_map[entity.unit_number] = {
        entity = entity,
        type = wagon_type,
        spawn_index = index
    }

    return true
end

-- 检查并清理失效/已被连入的战利品车厢
function Public.cleanup_loot_wagons()
    local icw = ICW.get()
    local loco = icw.locomotive
    local loco_train = loco and validate_entity(loco) and loco.train

    local to_remove = {}
    for un, data in pairs(icw.loot_wagons_on_map) do
        local entity = data.entity
        -- 实体已失效（被摧毁/消失）
        if not validate_entity(entity) then
            table.insert(to_remove, un)
        -- 已被连入玩家的火车
        elseif loco_train and entity.train and entity.train.id == loco_train.id then
            table.insert(to_remove, un)
        end
    end

    for _, un in ipairs(to_remove) do
        icw.loot_wagons_on_map[un] = nil
    end
end

------------------------------------------------------------
-- 设置玩家重生点在火车附近（每10秒调用）
-- 只在世界13生效，将每个玩家的重生点设到 locomotive 旁边
------------------------------------------------------------
function Public.set_respawn_near_train()
    local icw = ICW.get()
    local loco = icw.locomotive
    if not validate_entity(loco) then
        return
    end

    local surface = loco.surface
    local spawn_pos = surface.find_non_colliding_position(
        'character',
        {x = loco.position.x, y = loco.position.y + 3},
        10, 1
    )
    if not spawn_pos then
        spawn_pos = {x = loco.position.x, y = loco.position.y + 3}
    end

    for _, player in pairs(game.connected_players) do
        player.force.set_spawn_position(spawn_pos, surface)
    end
end

------------------------------------------------------------
-- 世界13 自动铺泥土系统
-- 当火车头进入清洁区时，自动将前方地形区域的
-- 不可通行 tile 替换为可通行地面
-- 实体（岩石、树木、虫巢等）保留不动，那是难度的一部分
-- 玩家需要自己处理实体障碍，自行铺设铁轨
------------------------------------------------------------
local ZONE_SIZE = 992          -- 每992米(31 chunks)一个地形区
local CLEAN_START = 32         -- 清洁区开始偏移（mod_w）
local CLEAN_END = 64           -- 清洁区结束偏移（mod_w）
local PAVE_HALF_WIDTH = 5      -- 铺泥土宽度：x=-5到5（共10格）
local PAVE_TILE = 'grass-1'    -- 铺设的可通行地面tile

-- 实体（岩石、树木、虫巢等）保留不动，那是难度的一部分

-- 检查火车头是否在清洁区中
-- 返回：nil（不在清洁区），或 zone_number（地形区编号，用于防重复铺设）
function Public.check_train_in_clean_zone()
    local icw = ICW.get()
    local loco = icw.locomotive
    if not validate_entity(loco) then
        return nil
    end

    local y = loco.position.y
    -- 世界13地形只在 y < -50 时生效
    if y > -50 then
        return nil
    end

    local abs_y = math.abs(y)
    local mod_w = abs_y % ZONE_SIZE

    -- 判定是否在清洁区范围
    if mod_w >= CLEAN_START and mod_w <= CLEAN_END then
        -- 计算当前所在的"地形区编号" = floor(abs_y / 992)
        local zone_number = math.floor(abs_y / ZONE_SIZE)
        return zone_number
    end

    return nil
end

-- 铺泥土：将指定范围的地形区域铺为可通行地面
-- 实体（岩石、虫巢等）不清除，保留作为高难度障碍
-- 参数：
--   surface - 地图surface
--   zone_number - 火车头当前所在的地形区编号（清洁区内）
-- 铺设范围：火车前方即将进入的地形区域（zone_number + 1）
--   即从下一个清洁区入口后方到下一个清洁区出口前方之间的区域
--   实际y坐标范围（火车朝负y方向前进）：
--     start_y = -((zone_number + 1) * ZONE_SIZE + CLEAN_END)  （前方清洁区出口）
--     end_y   = -((zone_number + 2) * ZONE_SIZE + CLEAN_START) （前方清洁区入口）
--   但如果前方chunk尚未生成，需要先确保chunk生成
--   同时也铺设当前zone后方清洁区出口到前方zone开始之间的短过渡段
function Public.pave_terrain_for_train(surface, zone_number)
    local icw = ICW.get()

    -- 防止重复铺设同一区域
    if icw.last_paved_zone >= zone_number then
        return
    end

    -- 火车朝负y方向前进，当火车在zone N的清洁区时
    -- 需要铺设的是前方zone (N+1) 的整个地形区
    -- 前方地形区范围：
    --   从 前方清洁区出口 y = -((N+1)*992 + CLEAN_END)
    --   到 前方清洁区入口 y = -((N+2)*992 + CLEAN_START)
    -- 但这样范围太大了，一次铺设670格×10格的地形可能卡顿
    -- 所以改为：铺设从当前清洁区出口到前方清洁区入口之间的区域
    -- 铺设范围：从当前清洁区出口到下一个清洁区出口
    -- 即从 y = -(zone_number * ZONE_SIZE + CLEAN_END)
    --   到 y = -((zone_number + 1) * ZONE_SIZE + CLEAN_END)
    -- 长度正好992格（约1000米，31 chunks）
    local start_y = -(zone_number * ZONE_SIZE + CLEAN_END)
    local end_y   = -((zone_number + 1) * ZONE_SIZE + CLEAN_END)

    -- 确保chunks已生成（否则无法铺设tile）
    -- end_y更负（更远），start_y更正（更近）
    -- chunk循环从 end_y 到 start_y
    for chunk_y = end_y - 64, start_y + 64, 32 do
        for chunk_x = -PAVE_HALF_WIDTH - 32, PAVE_HALF_WIDTH + 32, 32 do
            surface.request_to_generate_chunks({x = chunk_x, y = chunk_y}, 0)
        end
    end
    surface.force_generate_chunk_requests()

    -- 第1步：替换不可通行tile为可通行地面
    -- 在铺设范围内，查找所有不可通行tile并替换
    -- 注意：start_y > end_y（因为两者都是负数，start_y更接近0）
    -- Factorio的area要求 left_top.y < right_bottom.y
    -- 所以 left_top.y = end_y（更负），right_bottom.y = start_y（更正）
    local search_area = {
        left_top = {x = -PAVE_HALF_WIDTH, y = end_y},
        right_bottom = {x = PAVE_HALF_WIDTH + 1, y = start_y + 1}
    }

    -- 直接铺草地：范围内所有tile全部替换为grass-1，不判断不筛选
    local tiles_to_replace = {}
    for x = -PAVE_HALF_WIDTH, PAVE_HALF_WIDTH do
        for y = end_y, start_y do
            tiles_to_replace[#tiles_to_replace + 1] = {
                name = PAVE_TILE,
                position = {x = x, y = y},
            }
        end
    end
    surface.set_tiles(tiles_to_replace, true)

    -- 摧毁范围内的悬崖
    local cliffs = surface.find_entities_filtered{
        area = search_area,
        type = 'cliff',
    }
    for _, cliff in ipairs(cliffs) do
        if cliff.valid then
            cliff.destroy()
        end
    end

    -- 记录已铺设的区域编号
    icw.last_paved_zone = zone_number
end

-- 重置铺泥土追踪数据（用于新游戏/reset）
function Public.reset_pave_tracking()
    ICW.set('last_paved_zone', 0)
end

return Public
