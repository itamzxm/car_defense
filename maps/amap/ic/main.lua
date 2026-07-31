local Event = require 'utils.event'
local Functions = require 'maps.amap.ic.functions'
local IC = require 'maps.amap.ic.table'
local Minimap = require 'maps.amap.ic.minimap'
local GuiIC = require 'maps.amap.ic.gui'
local GuiDispatcher = require 'utils.gui_dispatcher'
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

-- 将汽车内生产类建筑改为qiche阵营
-- 注意：蓝图（entity-ghost / tile-ghost）不在此处转换阵营，保持玩家阵营。
-- 否则玩家摆放蓝图时，蓝图 ghost 会被强制改为 qiche 阵营，
-- 导致只有 qiche 阵营建设机器人能施工，且蓝图本身被归入汽车阵营。
local function apply_qiche_force(entity)
    local t = entity.type
    if t == 'entity-ghost' or t == 'tile-ghost' then
        return
    end
    entity.force = game.forces.qiche
end

-- 物流机器人 / 建设机器人由机器人指令中心(roboport)部署，不会触发 on_built_entity / on_robot_built_entity，
-- 因此不会经过上面的 qiche 阵营转换。这里定期扫描所有汽车内部空间，把其中的机器人也归入 qiche 阵营。
local function apply_qiche_force_to_robots()
    local cars = IC.get('cars')
    if not cars then
        return
    end
    local qiche = game.forces.qiche
    for _, car in pairs(cars) do
        if car.surface then
            local surface = game.surfaces[car.surface]
            if surface and surface.valid then
                local robots =
                    surface.find_entities_filtered(
                    {
                        type = {'logistic-robot', 'construction-robot'}
                    }
                )
                for _, robot in pairs(robots) do
                    if robot.valid and robot.force ~= qiche then
                        robot.force = qiche
                    end
                end
            end
        end
    end
end

-- 玩家在汽车内部空间使用红图（拆除规划器）时，红图默认把拆除任务按“玩家”阵营记录，
-- 而汽车内的机器人已被归入 qiche 阵营，qiche 机器人只执行“自己阵营”的拆除任务，
-- 因此这里在红图使用事件里即时处理：扫描红图区域内的 qiche 阵营建筑，改为 qiche 阵营标记，
-- 让 qiche 机器人来拆除。无需周期性同步，也不会误伤主世界。
local function on_player_deconstructed_area(event)
    local surface = event.surface
    if not surface or not surface.valid then
        return
    end
    -- 仅处理汽车内部空间（surface 名称为数字）
    if tonumber(surface.name) == nil then
        return
    end

    local qiche = game.forces.qiche
    local area = event.area

    -- 扫描红图区域内的 qiche 阵营建筑（汽车内玩家放置的建筑都已被转为 qiche 阵营）
    local targets = surface.find_entities_filtered({
        area = area,
        force = qiche
    })

    for _, e in pairs(targets) do
        if e.valid and e.minable
            and e.type ~= 'logistic-robot' and e.type ~= 'construction-robot'
            and not e.to_be_deconstructed(qiche) then
            -- 实体本身属 qiche 阵营，必须以 qiche 权限操作（用 player 调用会报错）。
            -- 直接以 qiche 阵营登记拆除标记即可，qiche 机器人会来执行拆除；无需取消其它标记。
            e.order_deconstruction(qiche)
        end
    end
end


local function on_built_entity(event)

 
    local ce = event.entity

    if not ce or not ce.valid then
        return
    end

    local this=WPT.get()

    -- 检查是否在汽车内空间，是则改为qiche阵营；火车内空间不归入汽车阵营
    -- 如果实体所在图层与商店相同，则不转化阵营（避免污染主世界层）
    if is_in_car_surface(ce) and ce.surface ~= this.shop.surface then
        apply_qiche_force(ce)
    end

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
    local ce = event.entity
    if not ce or not ce.valid then
        return
    end
    local this=WPT.get()
    -- 如果实体所在图层与商店相同，则不转化阵营（避免污染主世界层）
    if is_in_car_surface(ce) and ce.surface ~= this.shop.surface then
        apply_qiche_force(ce)
    end
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

    -- 每隔 2 秒把汽车内部空间的机器人归入 qiche 阵营（机器人由 roboport 部署，不会触发建造事件）
    if tick % 120 == 0 then
        apply_qiche_force_to_robots()
    end

end

GuiDispatcher.register_closed('chaoshikongshangdian_frame', function(event)
    local player = game.get_player(event.player_index)
    if not player or not player.valid then return end
    local screen = player.gui.screen
    local frame = screen['chaoshikongshangdian_frame']
    if frame and frame.valid then
        frame.destroy()
    end
end)

GuiDispatcher.register_closed(GuiIC.integration_frame_name, function(event)
    local player = game.get_player(event.player_index)
    if not player or not player.valid then return end
    local screen = player.gui.screen
    local frame = screen[GuiIC.integration_frame_name]
    if frame and frame.valid then
        frame.destroy()
    end
end)

local function on_gui_closed_entity(event)
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

GuiDispatcher.register_click('minimap_button', function(event)
    local player = game.get_player(event.player_index)
    if not player or not player.valid then return end
    Minimap.minimap(player, false)
end)

GuiDispatcher.register_click('minimap_frame', function(event)
    Minimap.toggle_minimap(event)
end)

GuiDispatcher.register_click('minimap_toggle_frame', function(event)
    Minimap.toggle_minimap(event)
end)

GuiDispatcher.register_click('switch_auto_map', function(event)
    local player = game.get_player(event.player_index)
    if not player or not player.valid then return end
    Minimap.toggle_auto(player)
end)

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
Event.add(defines.events.on_gui_closed, on_gui_closed_entity)
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
Event.add(defines.events.on_player_changed_surface, changed_surface)
Event.add(IC.events.on_player_kicked_from_surface, trigger_on_player_kicked_from_surface)
Event.add(defines.events.on_gui_switch_state_changed, on_gui_switch_state_changed)
Event.add(defines.events.on_robot_built_entity, on_robot_built_entity)
Event.add(defines.events.on_player_deconstructed_area, on_player_deconstructed_area)

--Event.add(defines.events.on_player_repaired_entity, on_player_repaired_entity)

return Public
