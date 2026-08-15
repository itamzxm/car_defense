local Event = require 'utils.event'
local Functions = require 'maps.amap.ic.functions'
local IC = require 'maps.amap.ic.table'
local Minimap = require 'maps.amap.ic.minimap'
local GuiIC = require 'maps.amap.ic.gui'
local Public = {}
local WPT = require 'maps.amap.table'

Public.reset = IC.reset
Public.get_table = IC.get

local function on_entity_died(event)
    local entity = event.entity
    if not entity or not entity.valid then
        return
    end

    local valid_types = IC.get_types()

    if (valid_types[entity.type] or valid_types[entity.name]) then
        Functions.kill_car(entity)
    end
end

local function on_player_mined_entity(event)
    local entity = event.entity
    if not entity or not entity.valid then
        return
    end

    local valid_types = IC.get_types()

    if (valid_types[entity.type] or valid_types[entity.name]) then
        Minimap.kill_minimap(game.players[event.player_index])
        Functions.save_car(event)
    end
end


-- 检测实体是否在汽车内空间（汽车内部空间的surface名称一定是数字）
local function is_in_car_surface(entity)
    local name = entity.surface.name
    return tonumber(name) ~= nil
end

local function on_built_entity(event)

 
    local ce = event.entity

    if not ce or not ce.valid then
        return
    end

    local this=WPT.get()

    -- 车内建筑保持玩家阵营（玩家可正常操作/施工/拆除）

    local valid_types = IC.get_types()

    if (valid_types[ce.type] or valid_types[ce.name]) ~= true then
        return
    end
    if this.world_number==8 and ce.name == 'car'  then 
        return
    end

    if this.world_number==7 and ce.name == 'car'  then 
        return
    end
    local player = game.get_player(event.player_index)
    if not player or not player.valid then
        return
    end

    Functions.create_car(event)
end

local function on_robot_built_entity(event)
    -- 车内建筑保持玩家阵营（on_built_entity 已统一处理，无需额外转换）
end

local function on_player_driving_changed_state(event)
    local player = game.players[event.player_index]

    Functions.use_door_with_entity(player, event.entity)
    Functions.validate_owner(player, event.entity)
end


local function on_tick()
    local tick = game.tick

    if tick % 60 == 1 then
        Functions.item_transfer()
    end

    if tick % 240 == 0 then
        Minimap.update_minimap()
    end

    if tick % (20 * 60) == 0 then
        Functions.remove_invalid_cars()
    end

end

local function on_gui_closed(event)
    local player = game.get_player(event.player_index)
    if not player or not player.valid then return end
    
    local screen = player.gui.screen
    local element = event.element
    
    local chaoshikongshangdian_frame = screen['chaoshikongshangdian_frame']
    local integration_frame = screen[GuiIC.integration_frame_name]
    
    if element and element.valid then
        if element.name == 'chaoshikongshangdian_frame' and chaoshikongshangdian_frame and chaoshikongshangdian_frame.valid then
            chaoshikongshangdian_frame.destroy()
        elseif element.name == GuiIC.integration_frame_name and integration_frame and integration_frame.valid then
            integration_frame.destroy()
        end
    end
    
    local entity = event.entity
    if not entity then
        return
    end
    if not entity.valid then
        return
    end
    if not entity.unit_number then
        return
    end
    local cars = IC.get('cars')
    if not cars[entity.unit_number] then
        return
    end
    Minimap.kill_minimap(game.players[event.player_index])
end

local function on_gui_opened(event)
    local entity = event.entity
    if not entity or not entity.valid then
        return
    end

    if not entity.unit_number then
        return
    end
    local cars = IC.get('cars')
    local car = cars[entity.unit_number]
    if not car then
        return
    end

    local surface_index = car.surface
    local surface = game.surfaces[surface_index]
    if not surface or not surface.valid then
        return
    end

    Minimap.minimap(
        game.players[event.player_index],
        surface,
        {
            car.area.left_top.x + (car.area.right_bottom.x - car.area.left_top.x) * 0.5,
            car.area.left_top.y + (car.area.right_bottom.y - car.area.left_top.y) * 0.5
        }
    )
end

local function on_gui_click(event)
    local element = event.element
    if not element or not element.valid then
        return
    end

    local player = game.get_player(event.player_index)
    if not player or not player.valid then
        return
    end

    if event.element.name == 'minimap_button' then
        Minimap.minimap(player, false)
    elseif event.element.name == 'minimap_frame' or event.element.name == 'minimap_toggle_frame' then
        Minimap.toggle_minimap(event)
    elseif event.element.name == 'switch_auto_map' then
        Minimap.toggle_auto(player)
    end
end

local function trigger_on_player_kicked_from_surface(data)
    local player = data.player
    local target = data.target
    Functions.kick_player_from_surface(player, target)
end

local function on_init()
    Public.reset()
end

local function on_gui_switch_state_changed(event)
    local element = event.element
    local player = game.players[event.player_index]
    if not (player and player.valid) then
        return
    end

    if not element.valid then
        return
    end

    if element.name == 'ic_auto_switch' then
        Minimap.toggle_auto(player)
    end
end




local changed_surface = Minimap.changed_surface

Event.on_init(on_init)
Event.add(defines.events.on_tick, on_tick)
Event.add(defines.events.on_gui_opened, on_gui_opened)
Event.add(defines.events.on_gui_closed, on_gui_closed)
Event.add(defines.events.on_player_driving_changed_state, on_player_driving_changed_state)
Event.add(defines.events.on_entity_died, on_entity_died)
Event.add(defines.events.on_built_entity, on_built_entity)
Event.add(defines.events.on_player_mined_entity, on_player_mined_entity,{
    {filter = "type", type = 'simple-entity'},
    {filter = "type", type = 'linked-chest'},
    {filter = "type", type = 'car'},
    {filter = "type", type = 'locomotive'},
    {filter = "type", type = 'cargo-wagon'},
    
    {filter = "type", type = 'artillery-wagon'},
    {filter = "type", type = 'artillery-turret'},
    {filter = "type", type = 'land-mine'},
    {filter = "type", type = 'spider-vehicle'},
    {filter = "type", type = 'ammo-turret'},
    {filter = "type", type = 'electric-turret'},
    {filter = "type", type = 'fluid-turret'},
	{filter = "type", type = 'tree'}
})
Event.add(defines.events.on_robot_mined_entity, on_player_mined_entity,{
    {filter = "type", type = 'simple-entity'},
    {filter = "type", type = 'linked-chest'},
    {filter = "type", type = 'car'},
    {filter = "type", type = 'locomotive'},
    {filter = "type", type = 'cargo-wagon'},
    
    {filter = "type", type = 'artillery-wagon'},
    {filter = "type", type = 'artillery-turret'},
    {filter = "type", type = 'land-mine'},
    {filter = "type", type = 'spider-vehicle'},
    {filter = "type", type = 'ammo-turret'},
    {filter = "type", type = 'electric-turret'},
    {filter = "type", type = 'fluid-turret'},
	{filter = "type", type = 'tree'}
})
Event.add(defines.events.on_gui_click, on_gui_click)
Event.add(defines.events.on_player_changed_surface, changed_surface)
Event.add(IC.events.on_player_kicked_from_surface, trigger_on_player_kicked_from_surface)
Event.add(defines.events.on_gui_switch_state_changed, on_gui_switch_state_changed)
Event.add(defines.events.on_robot_built_entity, on_robot_built_entity)

--Event.add(defines.events.on_player_repaired_entity, on_player_repaired_entity)

return Public
