local Utils = require 'utils.core'
local Color = require 'utils.color_presets'
local Alert = require 'utils.alert'
local Task = require 'utils.task'
local Token = require 'utils.token'
local IC = require 'maps.amap.ic.table'
local WPT = require 'maps.amap.table'

local Public = {}
local main_tile_name = 'black-refined-concrete'
local raise_event = script.raise_event
local floor = math.floor

local function validate_entity(entity)
    if not (entity and entity.valid ) then
        return false
    end
    if type(entity) == 'boolean' then
        return false
    end

    return true
end

local function log_err(err)
    local debug_mode = IC.get('debug_mode')
    if debug_mode then
        if type(err) == 'string' then
            log('IC: ' .. err)
        end
    end
end

local function get_trusted_system(player)
    local trust_system = IC.get('trust_system')
    if not trust_system[player.index] then
        trust_system[player.index] = {
            players = {
                [player.name] = true
            },
            allow_anyone = 'right'
        }
    end

    return trust_system[player.index]
end

local function upperCase(str)
    return (str:gsub('^%l', string.upper))
end

local function render_owner_text(renders, player, entity, new_owner)
    -- Check if required parameters are valid to prevent __index error
    if not entity or not player then
        return
    end
    
    local color = {
        r = player.color.r * 0.6 + 0.25,
        g = player.color.g * 0.6 + 0.25,
        b = player.color.b * 0.6 + 0.25,
        a = 1
    }
    if renders[player.index] and renders[player.index].valid then
        renders[player.index].destroy()
    end

    local ce_name = entity.name

    if ce_name == 'kr-advanced-tank' then
        ce_name = 'Tank'
    end

    if new_owner then
        renders[new_owner.index] =
            rendering.draw_text {
            text = '## - ' .. new_owner.name .. "'s " .. ce_name .. ' - ##',
            surface = entity.surface,
            target = entity,
            target_offset = {0, -2.6},
            color = color,
            scale = 1.05,
            font = 'default-large-semibold',
            alignment = 'center',
            scale_with_zoom = false
        }
    else
        renders[player.index] =
            rendering.draw_text {
            text = '## - ' .. player.name .. "'s " .. ce_name .. ' - ##',
            surface = entity.surface,
            target = entity,
            target_offset = {0, -2.6},
            color = color,
            scale = 1.05,
            font = 'default-large-semibold',
            alignment = 'center',
            scale_with_zoom = false
        }
    end
    entity.color = color
end

local function kill_doors(car)
    if not validate_entity(car.entity) then
        return
    end
    local doors = IC.get('doors')
    for k, e in pairs(car.doors) do
        if validate_entity(e) then
            doors[e.unit_number] = nil
            e.destroy()
            car.doors[k] = nil
        end
    end
end

local function get_owner_car_object(cars, player)
    for k, car in pairs(cars) do
        if car.owner == player.index then
            return k
        end
    end
    return false
end

local function get_entity_from_player_surface(cars, player)
    for k, car in pairs(cars) do
        if validate_entity(car.entity) then
            local surface_index = car.surface
            local surface = game.surfaces[surface_index]
            if validate_entity(surface) then
                if car.surface == player.physical_surface.index then
                    return car.entity
                end
            end
        end
    end
    return false
end

local function get_owner_car_surface(cars, player, target)
    for k, car in pairs(cars) do
        if car.owner == player.index then
            local surface_index = car.surface
            local surface = game.surfaces[surface_index]
            if validate_entity(surface) then
                if car.surface == target.surface.index then
                    return true
                else
                    return false
                end
            else
                return false
            end
        end
    end
    return false
end

local function get_player_surface(player)
    local surfaces = IC.get('surfaces')
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

local function get_player_entity(player)
    local cars = IC.get('cars')
    for k, car in pairs(cars) do
        if car.owner == player.index and type(car.entity) == 'boolean' then
            return car.name, true
        elseif car.owner == player.index then
            return car.name, false
        end
    end
    return false, false
end

local function get_owner_car_name(player)
    local cars = IC.get('cars')
    local saved_surfaces = IC.get('saved_surfaces')
    local index = saved_surfaces[player.index]
    for k, car in pairs(cars) do
        if not index then
            return false
        end
        if car.owner == player.index then
            return car.name
        end
    end
    return false
end

local function get_saved_entity(entity, index)
    if index and index.name ~= entity.name then
        local msg =
            table.concat(
            {
                'The built entity is not the same as the saved one. ',
                'Saved entity is: ' .. upperCase(index.name) .. ' - Built entity is: ' .. upperCase(entity.name) .. '. '
            }
        )
        return false, msg
    end
    return true
end

local function replace_entity(cars, entity, index)
    --local has_upgraded_health_pool = WPT.get('has_upgraded_health_pool')
    local unit_number = entity.unit_number
--    local health = floor(2000 * entity.health * 0.002)
    for k, car in pairs(cars) do
        if car.saved_entity == index.saved_entity then
            local c = car
            cars[unit_number] = c
            cars[unit_number].entity = entity
            cars[unit_number].saved_entity = nil
            cars[unit_number].transfer_entities = car.transfer_entities
            --cars[unit_number].health_pool = {
              --  enabled = has_upgraded_health_pool or false,
              --  health = health,
              --  max = health
        --    }
            cars[k] = nil
        end
    end
end

local function replace_doors(doors, entity, index)
    if not validate_entity(entity) then
        return
    end
    for k, door in pairs(doors) do
        local unit_number = entity.unit_number
        if index.saved_entity == door then
            doors[k] = unit_number
        end
    end
end

local function replace_surface(surfaces, entity, index)
    if not validate_entity(entity) then
        return
    end
    for k, surface_index in pairs(surfaces) do
        local surface = game.surfaces[surface_index]
        local unit_number = entity.unit_number
        if tostring(index.saved_entity) == surface.name then
            if validate_entity(surface) then
                surface.name = tostring(unit_number)
                surfaces[unit_number] = surface.index
                surfaces[k] = nil
            end
        end
    end
end

local function replace_surface_entity(cars, entity, index)
    if not validate_entity(entity) then
        return
    end
    for _, car in pairs(cars) do
        local unit_number = entity.unit_number
        if index and index.saved_entity == car.saved_entity then
            local surface_index = car.surface
            local surface = game.surfaces[surface_index]
            if validate_entity(surface) then
                surface.name = tostring(unit_number)
            end
        end
    end
end
local function set_new_area(car)
    local car_areas = IC.get('car_areas')
    local new_area = car_areas
    local name = car.name
    local apply_area = new_area[name]
    car.area = apply_area
end

local function remove_logistics(car)
    local chests = car.transfer_entities
    local saved_items = {}
    local saved_logistics = {}

    for k, chest in pairs(chests) do
        if chest and chest.valid then
            -- 1. 保存物品
            local chest_inventory = chest.get_inventory(defines.inventory.chest)
            saved_items[k] = {}
            if chest_inventory then
                for i = 1, #chest_inventory do
                    local stack = chest_inventory[i]
                    if stack.valid_for_read then
                        saved_items[k][i] = {name = stack.name, count = stack.count, quality = stack.quality.name}
                    end
                end
            end

            -- 2. 保存物流设置 (修正部分)
            saved_logistics[k] = {}
            local lp = chest.get_logistic_point(defines.logistic_member_index.logistic_container)
            if lp and lp.sections then
                for _, section in ipairs(lp.sections) do
                    local section_data = {
                        group = section.group,
                        active = section.active,
                        filters = {}
                    }
                    
                    -- 直接遍历 filters 属性，它只包含已经设置了物品的槽位
                    local filters = section.filters
                    for i, filter in ipairs(filters) do
                        -- filter 的结构已经是 {value = SignalID, min = ..., max = ...}
                        table.insert(section_data.filters, filter)
                    end
                    
                    table.insert(saved_logistics[k], section_data)
                end
            end

            car.transfer_entities[k] = nil
            chest.destroy()
        end
    end
    
    car.saved_chest_items = saved_items
    car.saved_chest_logistics = saved_logistics
end



local function upgrade_surface(player, entity)
    local ce = entity
    local saved_surfaces = IC.get('saved_surfaces')
    local cars = IC.get('cars')
    local doors = IC.get('doors')
    local surfaces = IC.get('surfaces')
    local index = saved_surfaces[player.index]
    if not index then
        return
    end

    if saved_surfaces[player.index] then
        local c = get_owner_car_object(cars, player)
        local car = cars[c]
        if ce.name == 'spidertron' then
            car.name = 'spidertron'
        elseif ce.name == 'tank' then
            car.name = 'tank'
        end
        set_new_area(car)
        remove_logistics(car)
        replace_entity(cars, ce, index)
        replace_doors(doors, ce, index)
        replace_surface(surfaces, ce, index)
        replace_surface_entity(cars, ce, index)
        kill_doors(car)
        Public.create_car_room(car)
        --恢复箱子中的物品和物流设置
        if car.saved_chest_items or car.saved_chest_logistics then
            for k, chest in pairs(car.transfer_entities) do
                if chest and chest.valid then
                    
                    -- --- 1. 恢复物流设置 (先恢复设置，防止物品被物流系统立刻运走) ---
                    if car.saved_chest_logistics and car.saved_chest_logistics[k] then
                        local lp = chest.get_logistic_point(defines.logistic_member_index.logistic_container)
                        if lp then
                            -- 清除所有默认栏目
                            for i = #lp.sections, 1, -1 do
                                lp.remove_section(i)
                            end
                            
                            -- 重新添加保存的栏目
                            for _, s_data in ipairs(car.saved_chest_logistics[k]) do
                                local new_section = lp.add_section(s_data.group)
                                new_section.active = s_data.active
                                -- 恢复过滤器
                                for i, f_data in ipairs(s_data.filters) do
                                    -- f_data 包含了 value(name, type, quality), min, max
                                    new_section.set_slot(i, f_data)
                                end
                            end
                        end
                    end

                    -- --- 2. 恢复物品 ---
                    if car.saved_chest_items and car.saved_chest_items[k] then
                        local chest_inventory = chest.get_inventory(defines.inventory.chest)
                        for _, item in pairs(car.saved_chest_items[k]) do
                            chest_inventory.insert(item)
                        end
                    end
                end
            end
            
            -- 清除临时保存的数据
            car.saved_chest_items = nil
            car.saved_chest_logistics = nil
        end

        
        saved_surfaces[player.index] = nil
        return true
    end
    return false
end

local function save_surface(entity, player)
    local cars = IC.get('cars')
    local saved_surfaces = IC.get('saved_surfaces')
    local car = cars[entity.unit_number]

    car.entity = false
    car.saved_entity = entity.unit_number

    saved_surfaces[player.index] = {saved_entity = entity.unit_number, name = entity.name}
end

local function kick_players_out_of_vehicles(car)
    for _, player in pairs(game.connected_players) do
        local character = player.character
        if validate_entity(character) and character.driving then
            if car.surface == player.physical_surface.index then
                character.driving = false
            end
        end
    end
end

local function check_if_players_are_in_nauvis()

    for _, player in pairs(game.connected_players) do
        local main_surface = game.surfaces['nauvis']
        if player.physical_surface.name ~= main_surface.name then
            local spawn_pos = game.forces.player.get_spawn_position(main_surface)
            local pos = main_surface.find_non_colliding_position('character', spawn_pos, 3, 0.5)
            if pos then
                player.teleport(pos, main_surface)
            else
                player.teleport(spawn_pos, main_surface)
            end
        end
    end
end

local function kick_players_from_surface(car)
    local surface_index = car.surface
    local surface = game.surfaces[surface_index]
    local allowed_surface = IC.get('allowed_surface')
    if not validate_entity(surface) then
        check_if_players_are_in_nauvis()
        return log_err('Car surface was not valid.')
    end
    if not car.entity or not car.entity.valid then
        local main_surface = game.surfaces[allowed_surface]
        if validate_entity(main_surface) then
            for _, e in pairs(surface.find_entities_filtered({area = car.area})) do
                if validate_entity(e) and e.name == 'character' and e.player then
                    e.player.teleport(main_surface.find_non_colliding_position('character', game.forces.player.get_spawn_position(main_surface), 3, 0, 5), main_surface)
                end
            end
            check_if_players_are_in_nauvis()
            return log_err('Car entity was not valid.')
        end
    end

    for _, e in pairs(surface.find_entities_filtered({area = car.area})) do
        if validate_entity(e) and e.name == 'character' and e.player then
            local p = car.entity.surface.find_non_colliding_position('character', car.entity.position, 128, 0.5)
            if p then
                e.player.teleport(p, car.entity.surface)
            else
                e.player.teleport(car.entity.position, car.entity.surface)
            end
        end
    end
end

local function kick_player_from_surface(player, target)
    local cars = IC.get('cars')
    local allowed_surface = IC.get('allowed_surface')

    local main_surface = game.surfaces[allowed_surface]
    if not validate_entity(main_surface) then
        return
    end

    local c = get_owner_car_object(cars, player)
    local car = cars[c]

    if not validate_entity(car.entity) then
        return
    end
    
    if validate_entity(player) then
        if validate_entity(target) then
            local locate = get_owner_car_surface(cars, player, target)
            if locate then
                local p = car.entity.surface.find_non_colliding_position('character', car.entity.position, 128, 0.5)
                if p then
                    target.teleport(p, car.entity.surface)
                else
                    target.teleport(main_surface.find_non_colliding_position('character', game.forces.player.get_spawn_position(main_surface), 3, 0, 5), main_surface)
                end
                target.print('You were kicked out of ' .. player.name .. ' vehicle.', Color.warning)
            end
        end
    end
end

local function restore_surface(player, entity)
    local ce = entity
    local saved_surfaces = IC.get('saved_surfaces')
    local cars = IC.get('cars')
    local doors = IC.get('doors')
    local renders = IC.get('renders')
    local surfaces = IC.get('surfaces')
    local index = saved_surfaces[player.index]
    if not index then
        return
    end

    if saved_surfaces[player.index] then
        local success, msg = get_saved_entity(ce, index)
        if not success then
            player.print(msg, Color.warning)
            return true
        end
        replace_entity(cars, ce, index)
        replace_doors(doors, ce, index)
        replace_surface(surfaces, ce, index)
        replace_surface_entity(cars, ce, index)
        saved_surfaces[player.index] = nil
        render_owner_text(renders, player, ce)
        return true
    end
    return false
end


   local function get_filters(points)
        local filters = {}
        for _, section in pairs(points.sections) do
            for _, filter in pairs(section.filters) do
                if filter and filter.value and filter.value.name then
                    filters[#filters + 1] = filter
                end
            end
        end
        return filters
    end

local function input_filtered(car_inv, chest, chest_inv, free_slots)
    local request_goals = {}

    -- 1. 获取物流点
    local logistics = chest.get_logistic_point(defines.logistic_member_index.logistic_container)
    if logistics then
        -- 假设 get_filters 是你定义的工具函数，它应该返回物流过滤器的列表
        -- 在 2.0 中，建议直接遍历 sections 以获得准确的请求数
        local filters = get_filters(logistics)
        for _, filter in pairs(filters) do
            if filter.value.name then
                -- 修改点：获取实际设置的请求数量 (filter.min)，而不是固定的10组
                -- 如果是 2.0 的 API，通常请求值在 filter.min 中
                local count = filter.min or filter.count or 0
                request_goals[filter.value.name] = (request_goals[filter.value.name] or 0) + count
            end
        end
    end

    -- 2. 遍历车辆库存进行转移
    for i = 1, #car_inv do
        local stack = car_inv[i]
        if stack.valid_for_read then
            local goal = request_goals[stack.name]
            
            if goal then
                -- 计算箱子里已经有多少了
                local current_in_chest = chest_inv.get_item_count(stack.name)
                local need_amount = goal - current_in_chest

                if need_amount > 0 then
                    -- 确定实际要转移的数量：取"车里有的"和"箱子需要的"最小值
                    local transfer_count = math.min(stack.count, need_amount)
                    
                    -- 插入到箱子（使用表结构而不是直接传stack对象，这样更安全）
                    local inserted_count = chest_inv.insert({name = stack.name, count = transfer_count})
                    
                    -- 从车中扣除实际成功转移的数量
                    if inserted_count > 0 then
                        stack.count = stack.count - inserted_count
                    end
                end
            end
        end
    end
end
 

local function input_cargo(car, chest)
    if not chest.request_from_buffers then
        goto continue
    end

    local car_entity = car.entity
    if not validate_entity(car_entity) then
        car.transfer_entities = nil
        goto continue
    end

    local car_inventory = car_entity.get_inventory(defines.inventory.car_trunk)
    if car_inventory.is_empty() then
        goto continue
    end

    local chest_inventory = chest.get_inventory(defines.inventory.chest)
    local free_slots = 0
    for i = 1, chest_inventory.get_bar() - 1, 1 do
        if not chest_inventory[i].valid_for_read then
            free_slots = free_slots + 1
        end
    end
    

    local has_request_slot = false
    local logistics = chest.get_logistic_point(defines.logistic_member_index.logistic_container)
    if logistics then
        local filters = get_filters(logistics)
        for _, filter in pairs(filters) do
            if filter.value.name then
                has_request_slot = true
            end
        end
    end

    if has_request_slot then
        input_filtered(car_inventory, chest, chest_inventory, free_slots)
        goto continue
    end

    for i = 1, #car_inventory - 1, 1 do
        if free_slots <= 0 then
            goto continue
        end
        if car_inventory[i].valid_for_read then
            chest_inventory.insert(car_inventory[i])
            car_inventory[i].clear()
            free_slots = free_slots - 1
        end
    end

    ::continue::
end

local function output_cargo(car, passive_chest)
    if not validate_entity(car.entity) then
        goto continue
    end

    if not passive_chest.valid then
        goto continue
    end
    local chest1 = passive_chest.get_inventory(defines.inventory.chest)
    local chest2 = car.entity.get_inventory(defines.inventory.car_trunk)
    for i = 1, #chest1 do
        local t = chest1[i]
        if t and t.valid then
            local c = chest2.insert(t)
            if (c > 0) then
                chest1[i].count = chest1[i].count - c
            end
        end
    end
    ::continue::
end

local transfer_functions = {
    ['requester-chest'] = input_cargo,
    ['passive-provider-chest'] = output_cargo
}

local function construct_doors(car)
    local area = car.area
    local surface_index = car.surface
    local surface = game.surfaces[surface_index]
    if not surface or not surface.valid then
        return
    end

    local doors = IC.get('doors')

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
        if type(car.entity) == 'boolean' then
            return
        end
        doors[e.unit_number] = car.entity.unit_number
        car.doors[#car.doors + 1] = e
    end
end

local function get_player_data(player)
    local players = IC.get('players')
    local player_data = players[player.index]
    if players[player.index] then
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

local remove_car =
    Token.register(
    function(data)
        local player = data.player
        local car = data.car
        player.remove_item({name = car.name, count = 1})
    end
)

local find_remove_car =
    Token.register(
    function(data)
        local index = data.index
        local types = data.types
        local position = data.position

        local surface = game.get_surface(index)
        if not surface or not surface.valid then
            return
        end

        for _, dropped_ent in pairs(surface.find_entities_filtered {type = 'item-entity', area = {{position.x - 10, position.y - 10}, {position.x + 10, position.y + 10}}}) do
            if dropped_ent and dropped_ent.valid and dropped_ent.stack then
                if types[dropped_ent.stack.name] then
                    dropped_ent.destroy()
                end
            end
        end
    end
)

function Public.save_car(event)
    local entity = event.entity
    local player = game.players[event.player_index]

    local cars = IC.get('cars')
    local car = cars[entity.unit_number]
    local restore_on_theft = IC.get('restore_on_theft')
    local entity_type = IC.get('entity_type')
    local types = entity_type
    local players = IC.get('players')

    if not car then
        log_err('Car was not valid.')
        return
    end

    local position = entity.position
    local health = entity.health

    kick_players_out_of_vehicles(car)
    kick_players_from_surface(car)
    get_player_data(player)

    if car.owner == player.index then
        save_surface(entity, player)
        if not players[player.index].notified then
            player.print(player.name .. ', the ' .. car.name .. ' surface has been saved.', Color.success)
            players[player.index].notified = true
        end
    else
        local p = game.players[car.owner]
        if not p then
            return
        end

        local find_remove_car_args = {
            index = p.surface.index,
            types = types,
            position = p.position
        }

        Task.set_timeout_in_ticks(1, find_remove_car, find_remove_car_args)
        Task.set_timeout_in_ticks(2, find_remove_car, find_remove_car_args)
        Task.set_timeout_in_ticks(3, find_remove_car, find_remove_car_args)

        log_err('Owner of this vehicle is: ' .. p.name)
        save_surface(entity, p)
        Utils.action_warning('[Car]', player.name .. ' has looted ' .. p.name .. '´s car.')
        player.print('This car was not yours to keep.', Color.warning)
        local params = {
            player = player,
            car = car
        }
        Task.set_timeout_in_ticks(10, remove_car, params)
        if restore_on_theft then
            local e = player.physical_surface.create_entity({name = car.name, position = position, force = player.force, create_build_effect_smoke = false})
          --  e.health = health
            restore_surface(p, e)
        elseif p.can_insert({name = car.name, count = 1}) then
            p.insert({name = car.name, count = 1, health = health})
            p.print('Your car was stolen from you - the gods foresaw this and granted you a new one.', Color.info)
        end
    end
end

function Public.kill_car(entity)
    if not validate_entity(entity) then
        return
    end

    local entity_type = IC.get('entity_type')

    if not entity_type[entity.type] then
        return
    end

    local surfaces = IC.get('surfaces')
    local cars = IC.get('cars')
    local car = cars[entity.unit_number]
    if not car then
        return
    end

    kick_players_out_of_vehicles(car)
    kick_players_from_surface(car)

    local trust_system = IC.get('trust_system')
    local owner = car.owner

    if owner then
        owner = game.get_player(owner)
        if owner and owner.valid then
            if trust_system[owner.index] then
                trust_system[owner.index] = nil
            end
        end
    end

    local surface_index = car.surface
    local surface = game.surfaces[surface_index]
    kill_doors(car)
    for _, tile in pairs(surface.find_tiles_filtered({area = car.area})) do
        surface.set_tiles({{name = 'out-of-map', position = tile.position}}, true)
    end
    for _, x in pairs({car.area.left_top.x - 1.5, car.area.right_bottom.x + 1.5}) do
        local p = {x = x, y = car.area.left_top.y + ((car.area.right_bottom.y - car.area.left_top.y) * 0.5)}
        surface.set_tiles({{name = 'out-of-map', position = {x = p.x + 0.5, y = p.y}}}, true)
        surface.set_tiles({{name = 'out-of-map', position = {x = p.x - 1, y = p.y}}}, true)
    end
    car.entity.force.chart(surface, car.area)
    game.delete_surface(surface)
    surfaces[entity.unit_number] = nil
    cars[entity.unit_number] = nil
end

function Public.validate_owner(player, entity)
    if validate_entity(entity) then
        local cars = IC.get('cars')
        local unit_number = entity.unit_number
        local car = cars[unit_number]
        if not car then
            return
        end
        if validate_entity(car.entity) then
            local p = game.players[car.owner]
            local list = get_trusted_system(p)
            if p and p.valid and p.connected then
                if list.players[player.name] then
                    return
                end
            end
            if p then
                if car.owner ~= player.index and player.driving then
                    player.driving = false
                    if not player.admin then
                        return Utils.print_to(nil, '[Car] ' .. player.name .. ' tried to drive ' .. p.name .. '´s car.')
                    end
                end
            end
        end
        return false
    end
    return false
end

function Public.create_room_surface(unit_number)
    if game.surfaces[tostring(unit_number)] then
        return game.surfaces[tostring(unit_number)]
    end

    local map_gen_settings = {
        ['width'] = 2,
        ['height'] = 2,
        ['water'] = 0,
        ['starting_area'] = 1,
        ['cliff_settings'] = {cliff_elevation_interval = 0, cliff_elevation_0 = 0},
        ['default_enable_all_autoplace_controls'] = true,
        ['autoplace_settings'] = {
            ['entity'] = {treat_missing_as_default = false},
            ['tile'] = {treat_missing_as_default = true},
            ['decorative'] = {treat_missing_as_default = false}
        }
    }
    local surface = game.create_surface(tostring(unit_number), map_gen_settings)
    surface.freeze_daytime = true
    surface.daytime = 0.1
    surface.request_to_generate_chunks({16, 16}, 1)
    surface.force_generate_chunk_requests()
    for _, tile in pairs(surface.find_tiles_filtered({area = {{-2, -2}, {2, 2}}})) do
        surface.set_tiles({{name = 'out-of-map', position = tile.position}}, true)
    end
    local surfaces = IC.get('surfaces')
    surfaces[unit_number] = surface.index
    return surface.index
end

function Public.create_car_room(car)
    local surface_index = car.surface
    local surface = game.surfaces[surface_index]
    local car_areas = IC.get('car_areas')
    local entity_name = car.name
    local entity_type = car.type
    local area = car_areas[entity_name]
    local tiles = {}

    if not area then
        area = car_areas[entity_type]
    end

    for x = area.left_top.x, area.right_bottom.x - 1, 1 do
        for y = area.left_top.y + 2, area.right_bottom.y - 3, 1 do
            tiles[#tiles + 1] = {name = main_tile_name, position = {x, y}}
        end
    end
    for x = -3, 2, 1 do
        for y = area.right_bottom.y - 4, area.right_bottom.y - 2, 1 do
            tiles[#tiles + 1] = {name = main_tile_name, position = {x, y}}
        end
    end


    for x = area.left_top.x, area.right_bottom.x - 1, 1 do
        for y = -2, 1, 1 do
            tiles[#tiles + 1] = {name = 'water', position = {x, y}}

        end
    end

    surface.set_tiles(tiles, true)

    construct_doors(car)
    local mgs = surface.map_gen_settings
    mgs.width = area.right_bottom.x * 2
    mgs.height = area.right_bottom.y * 2
    surface.map_gen_settings = mgs

    local lx, ly, rx, ry = 4, 1, 5, 1

    local position1 = {area.left_top.x + lx, area.left_top.y + ly}
    local position2 = {area.right_bottom.x - rx, area.left_top.y + ry}

    local e1 =
        surface.create_entity(
        {
            name = 'requester-chest',
            position = position1,
            force = 'neutral',
            create_build_effect_smoke = false
        }
    )

    local this= WPT.get()
    if this .world_number== 7 or this .world_number== 6 then 
        local e3 = surface.create_entity(
            {
                name = 'linked-chest',
                position =  {0, area.left_top.y + ly},
                force = 'player',
                create_build_effect_smoke = false
            })

            e3.destructible = false
            e3.minable_flag = false
    end
    e1.destructible = false
    e1.minable_flag = false

    local e2 =
        surface.create_entity(
        {
            name = 'passive-provider-chest',
            position = position2,
            force = 'neutral',
            create_build_effect_smoke = false
        }
    )
    e2.destructible = false
    e2.minable_flag= false
    car.transfer_entities = {e1, e2}
    return
end

function Public.create_car(event)
    local ce = event.entity
    if not ce then
        return
    end

    local player = game.get_player(event.player_index)

    local allowed_surface = IC.get('allowed_surface')
    local map_name = allowed_surface

    local entity_type = IC.get('entity_type')
    local un = ce.unit_number

    if not un then
        return
    end

    if not entity_type[ce.type] then
        return
    end

    local renders = IC.get('renders')
    --local has_upgraded_health_pool = WPT.get('has_upgraded_health_pool')

    local name, mined = get_player_entity(player)

    if entity_type[name] and not mined then
        return player.print('Multiple vehicles are not supported at the moment.', Color.warning)
    end
    local this=WPT.get()
    local yiciyuan=false
    if this.world_number == 8 or this.world_number == 7 then
    if  ce.surface.name==this.yiciyuan_surface.name then 
        yiciyuan =true
    end
end
 
    -- 检查是否在火车内部空间，允许在火车内使用汽车内部空间系统
    -- 使用 this.shop.surface 判断图层：商店实体所在的 surface 即为玩家当前所在的合法图层
    local shop_surface = this.shop and this.shop.valid and this.shop.surface

    local is_allowed_planet = string.sub(ce.surface.name, 0, #map_name) == map_name or
                              ce.surface.name == 'aquilo' or
                              ce.surface.name == 'gleba' or
                              ce.surface.name == 'fulgora' or
                              ce.surface.name == 'vulcanus'or
                              ce.surface.name == 'aquilo-1' or
                              ce.surface.name == 'gleba-1' or
                              ce.surface.name == 'fulgora-1' or
                              ce.surface.name == 'vulcanus-1' or
                              (shop_surface and ce.surface == shop_surface)
    
    
    if not is_allowed_planet and yiciyuan==false then
        return player.print('Multi-surface is not supported at the moment.', Color.warning)
   
    end

    if
        get_owner_car_name(player) == 'car' and ce.name == 'tank' or get_owner_car_name(player) == 'car' and ce.name == 'spidertron' or
            get_owner_car_name(player) == 'tank' and ce.name == 'spidertron'
     then
        upgrade_surface(player, ce)
        render_owner_text(renders, player, ce)
        player.print('Your car-surface has been upgraded!', Color.success)
        return
    end

    if type(ce) == 'boolean' then
        return
    end

    local saved_surface = restore_surface(player, ce)
    if saved_surface then
        return
    end

    local car_areas = IC.get('car_areas')
    local cars = IC.get('cars')
    local car_area = car_areas[ce.name]
    if not car_area then
        car_area = car_areas[ce.type]
    end


    cars[un] = {
        entity = ce,
        area = {
            left_top = {x = car_area.left_top.x, y = car_area.left_top.y},
            right_bottom = {x = car_area.right_bottom.x, y = car_area.right_bottom.y}
        },
        doors = {},
        owner = player.index,
        name = ce.name,
        type = ce.type
    }

    -- 立即渲染车主信息，确保在任何表面操作之前完成
    render_owner_text(renders, player, ce)

    local car = cars[un]

    car.surface = Public.create_room_surface(un)
    Public.create_car_room(car)

    return car
end

function Public.remove_invalid_cars()
    local cars = IC.get('cars')
    local doors = IC.get('doors')
    local surfaces = IC.get('surfaces')
    for k, car in pairs(cars) do
        if type(car.entity) ~= 'boolean' then
            if not validate_entity(car.entity) then
                cars[k] = nil
                for key, value in pairs(doors) do
                    if k == value then
                        doors[key] = nil
                    end
                end
               -- kick_players_from_surface(car)
            end
        end
    end
    for k, index in pairs(surfaces) do
        local surface = game.surfaces[index]
        if surface and surface.valid and not cars[tonumber(surface.name)] then
            game.delete_surface(surface)
            surfaces[k] = nil
        end
    end
end

function Public.use_door_with_entity(player, door)
    local player_data = get_player_data(player)
    if player_data.state then
        player_data.state = player_data.state - 1
        if player_data.state == 0 then
            player_data.state = nil
        end
        return
    end

    if not validate_entity(door) then
        return
    end
    local doors = IC.get('doors')
    local cars = IC.get('cars')

    local car = false
    if doors[door.unit_number] then
        car = cars[doors[door.unit_number]]
    end
    if cars[door.unit_number] then
        car = cars[door.unit_number]
    end
    if not car then
        return
    end

    if not validate_entity(car.entity) then
        return
    end
    
    local owner = game.players[car.owner]
    local list = get_trusted_system(owner)
    if owner and owner.valid and owner.index ~= player.index and player.connected then
        if list.allow_anyone == 'right' then
            if not list.players[player.name] and not player.admin then
                player.driving = false
                return player.print('You have not been approved by ' .. owner.name .. ' to enter their vehicle.', Color.warning)
            end
        end
    end

    if validate_entity(car.entity) then
        player_data.fallback_surface = car.entity.surface
        player_data.fallback_position = {car.entity.position.x, car.entity.position.y}
    end

    if validate_entity(car.entity) and car.entity.surface.name == player.physical_surface.name then
        local surface_index = car.surface
        local surface = game.surfaces[surface_index]
        if validate_entity(car.entity) and car.owner == player.index then
            raise_event(
                IC.events.used_car_door,
                {
                    player = player,
                    state = 'add'
                }
            )
        end

        if not validate_entity(surface) then
            return
        end

        local area = car.area
        local x_vector = door.position.x - player.physical_position.x
        local position
        if x_vector > 0 then
            position = {area.left_top.x + 0.5, area.left_top.y + ((area.right_bottom.y - area.left_top.y) * 0.5)}
        else
            position = {area.right_bottom.x - 0.5, area.left_top.y + ((area.right_bottom.y - area.left_top.y) * 0.5)}
        end
        local dist = math.sqrt((player.physical_position.x - car.entity.position.x)^2 + (player.physical_position.y - car.entity.position.y)^2)
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
        if validate_entity(car.entity) and car.owner == player.index then
            raise_event(
                IC.events.used_car_door,
                {
                    player = player,
                    state = 'remove'
                }
            )
        end
        local surface = car.entity.surface
        local x_vector = (door.position.x / math.abs(door.position.x)) * 2
        local position = {car.entity.position.x + x_vector, car.entity.position.y}
        local surface_position = surface.find_non_colliding_position('character', position, 128, 0.5)
        if car.entity.type == 'car' or car.entity.name == 'spidertron' then
            player.teleport(surface_position, surface)
            player_data.state = 2
            player.driving = true
         
        else
            
            player.teleport(surface_position, surface)
        end
        player_data.surface = surface.index
    end

    
end

function Public.item_transfer()
    local cars = IC.get('cars')
    for _, car in pairs(cars) do
        if validate_entity(car.entity) then
          if car.entity.active then
            if car.transfer_entities then
                for k, e in pairs(car.transfer_entities) do
                    if validate_entity(e) then
                        transfer_functions[e.name](car, e)
                    end
                end
            end
          end
        end
    end
end


Public.kick_player_from_surface = kick_player_from_surface
Public.get_player_surface = get_player_surface
Public.get_entity_from_player_surface = get_entity_from_player_surface
Public.get_owner_car_object = get_owner_car_object
Public.render_owner_text = render_owner_text

return Public
