local event = require 'utils.event'

local coin_yield = {
	["big-rock"] = 3,
	["huge-rock"] = 6,
	["big-sand-rock"] = 3
}

local function on_player_mined_entity(event)
	local player = game.players[event.player_index]
	-- 隔离副本：副本玩家 force 是 'dungeon_force_*'，不参与主世界金币掉落
	if not player or not player.valid then return end
	if player.force.name ~= 'player' then return end

	if coin_yield[event.entity.name] then
		event.entity.surface.spill_item_stack(event.entity.position,{name = "coin", count = math.random(math.ceil(coin_yield[event.entity.name] * 0.5), math.ceil(coin_yield[event.entity.name] * 2))}, true)
	end
end

event.add(defines.events.on_player_mined_entity, on_player_mined_entity)