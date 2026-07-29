local WPT = require 'maps.amap.table'
local diff = require 'maps.amap.diff'
local Event = require 'utils.event'

local Public = {}

local function has_deep_water_nearby(surface, position, radius)
  if math.abs(position.x)+math.abs(position.y) < 100 then
    return false
  end
  radius = radius or 3
  local area = {
    left_top = {x = position.x - radius, y = position.y - radius},
    right_bottom = {x = position.x + radius, y = position.y + radius}
  }
  local water_tiles = surface.count_tiles_filtered{name = {"water"}, area = area}

  if water_tiles == 0 then
    return false
  else
    return true
  end
end

local function has_other_player_vehicles_nearby(surface, position, player_vehicle, radius)
  radius = radius or 10
  local area = {
    left_top = {x = position.x - radius, y = position.y - radius},
    right_bottom = {x = position.x + radius, y = position.y + radius}
  }
  local vehicles = surface.count_entities_filtered{type = {"car", "tank"}, area = area, force = "player"}
  
  if vehicles > 1 then
    return true
  end
  return false
end

local function on_built_entity(event)
  local entity = event.entity
  if not entity or not entity.valid then return end
  
  if entity.type ~= "car" and entity.type ~= "tank" then return end
  
  local map = diff.get()
  if map.world ~= 3 then return end
  
  local this = WPT.get()
  if not this.player_fishing_vehicles then
    this.player_fishing_vehicles = {}
  end
  
  local player_index = event.player_index
  local player = game.players[player_index]
  
  local position = entity.position
  if has_deep_water_nearby(entity.surface, position) and 
     not has_other_player_vehicles_nearby(entity.surface, position, entity) then
    
    if this.player_fishing_vehicles[player_index] then
      local old_vehicle_data = this.player_fishing_vehicles[player_index]
      if old_vehicle_data.text_id then
        old_vehicle_data.text_id.destroy()
      end
      for i, v_data in ipairs(this.fishing_vehicles or {}) do
        if v_data.entity == old_vehicle_data.entity then
          table.remove(this.fishing_vehicles, i)
          break
        end
      end
    end
    
    local vehicle_data = {
      entity = entity,
      last_fish_time = game.tick,
      player_index = player_index
    }
    
    this.player_fishing_vehicles[player_index] = vehicle_data
    
    if not this.fishing_vehicles then
      this.fishing_vehicles = {}
    end
    table.insert(this.fishing_vehicles, vehicle_data)
    
    vehicle_data.text_id = rendering.draw_text {
      text = '~捕鱼中~',
      surface = entity.surface,
      target =
      {
          entity = entity,
          offset = {0, -2.6},
      },
      color = {
        r = 0,
        g = 1,
        b = 1,
        a = 1
      },
      scale = 1.05,
      font = 'default-large-semibold',
      alignment = 'center',
      scale_with_zoom = false
    }
    
    if player and player.valid then
      player.print({'amap.fishing'}, {r=255, g=0, b=0})
    end
  end
end

local function fishing_task()
  local map = diff.get()
  if map.world ~= 3 then return end
  
  local this = WPT.get()
  
  if not this.fishing_vehicles then return end
  
  local valid_fishing_vehicles = {}
  
  for _, vehicle_data in pairs(this.fishing_vehicles) do
    local vehicle = vehicle_data.entity
    
    if vehicle and vehicle.valid then
      local position = vehicle.position
      local surface = vehicle.surface
      
      if has_deep_water_nearby(surface, position)  then
        local area = {
          left_top = {x = position.x - 3, y = position.y - 3},
          right_bottom = {x = position.x + 3, y = position.y + 3}
        }
        local water_tiles = surface.find_tiles_filtered{name = {"water"}, area = area}
        
        if #water_tiles > 0 then
          local fish_position = water_tiles[math.random(1, #water_tiles)].position
          
          if storage.watery_world_fishes and #storage.watery_world_fishes > 0 then
            local fish_name = storage.watery_world_fishes[math.random(1, #storage.watery_world_fishes)]
            surface.create_entity{name = fish_name, position = fish_position}
          end
        end
        
        if vehicle.get_inventory(defines.inventory.car_trunk) then
          vehicle.get_inventory(defines.inventory.car_trunk).insert{name = "raw-fish", count = 2}
        end
        
        vehicle_data.last_fish_time = game.tick
        
        table.insert(valid_fishing_vehicles, vehicle_data)
      end
    end
  end
  
  for _, vehicle_data in pairs(this.fishing_vehicles) do
    local still_valid = false
    for _, valid_data in pairs(valid_fishing_vehicles) do
      if vehicle_data.entity == valid_data.entity then
        still_valid = true
        break
      end
    end
    if not still_valid then
      if vehicle_data.text_id then
        vehicle_data.text_id.destroy()
        vehicle_data.text_id = nil
      end
      if vehicle_data.player_index and this.player_fishing_vehicles then
        local old_data = this.player_fishing_vehicles[vehicle_data.player_index]
        if old_data and old_data.entity == vehicle_data.entity then
          this.player_fishing_vehicles[vehicle_data.player_index] = nil
        end
      end
    end
  end
  
  this.fishing_vehicles = valid_fishing_vehicles
end

Event.add(defines.events.on_built_entity, on_built_entity)
Event.on_nth_tick(60*30, fishing_task)

return Public
