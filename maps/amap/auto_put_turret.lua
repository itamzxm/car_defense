local Event = require("utils.event")
local WPT = require 'maps.amap.table'

local ammo={
  [1]={name='firearm-magazine'},
  [2]={name='piercing-rounds-magazine'},
  [3]={name='uranium-rounds-magazine'}
}

local on_built_entity = function (event)
  if not event.entity then return end
  if not event.entity.valid then return end
  if event.entity.name ~= "gun-turret" then return  end
  local this=WPT.get()
  local player = game.get_player(event.player_index)
  local index=player.index
  if not this.silo then 
  if not this.tank[index]
   then 
    return
   end
  end
 
  local magzine_count = 10
  local turret_inventory = event.entity.get_inventory(defines.inventory.turret_ammo)
  if not turret_inventory then return end
  
  for i=1,#ammo do
    local ammo_name = ammo[#ammo-i+1].name
    local ammo_in_bag = player.get_item_count(ammo_name)
    
    if ammo_in_bag >= magzine_count then
      turret_inventory.insert{name = ammo_name, count = magzine_count}
      player.remove_item{name = ammo_name, count = magzine_count}
      return
    end
  end
  
  -- 如果没有足够数量的高级弹药，尝试使用低级弹药
  for i=1,#ammo do
    local ammo_name = ammo[#ammo-i+1].name
    local ammo_in_bag = player.get_item_count(ammo_name)
    
    if ammo_in_bag > 0 then
      turret_inventory.insert{name = ammo_name, count = ammo_in_bag}
      player.remove_item{name = ammo_name, count = ammo_in_bag}
      return
    end
  end
end


Event.add(defines.events.on_built_entity,on_built_entity)
