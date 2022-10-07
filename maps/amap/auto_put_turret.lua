local Event = require("utils.event")
local WPT = require 'maps.amap.table'

local ammo={}
ammo={
  [1]={name='firearm-magazine'},
  [2]={name='piercing-rounds-magazine'},
  [3]={name='uranium-rounds-magazine'}
}

local on_built_entity = function (event)
  if not event.created_entity then return end
  if not event.created_entity.valid then return end
  if event.created_entity.name ~= "gun-turret" then return  end
  local this=WPT.get()
  local player = game.get_player(event.player_index)
  local index=player.index
  if not this.tank[index] then return end
  local magzine_count = 10
  if not(event.item == nil) then
    for i=1,#ammo do
      local ammoInYourBag = player.get_item_count(ammo[#ammo-i+1].name)
      if ammoInYourBag ~= 0 then
        if ammoInYourBag >= magzine_count then
          event.created_entity.insert{name = ammo[#ammo-i+1].name,count = magzine_count}
          player.remove_item{name = ammo[#ammo-i+1].name,count = magzine_count}
          goto workflow
        end
      end
    end
    ::workflow::
  end
end


Event.add(defines.events.on_built_entity,on_built_entity)
