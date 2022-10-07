
local WPT = require 'maps.amap.table'
local function on_marked_for_deconstruction(event)
	local this = WPT.get()
	local blacklist = this.allow_deconst_list
	
	local entity = event.entity
	if not entity.valid then return end
	if not event.player_index then return end
	if entity.force.name ~= "neutral" then return end
	if blacklist[entity.type] then return end
	entity.cancel_deconstruction(game.players[event.player_index].force.name)
	if entity.type == "tree" or entity.type =="simple-entity"  then 
		local player = game.players[event.player_index]
		player.print({'amap.try_to_deconst'})
 end
end

local Event = require 'utils.event' 
Event.add(defines.events.on_marked_for_deconstruction, on_marked_for_deconstruction)
