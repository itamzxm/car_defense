
local WPT = require 'maps.amap.table'

-- 石头（world_19 石头带 / 各世界地形石）始终可红图拆除，供建造机器人挖掘
local deconstructable_rocks = {
	['big-rock'] = true,
	['huge-rock'] = true,
	['big-sand-rock'] = true,
}

-- 树 / 普通实体（simple-entity，含石头）红图始终可用。
-- main.lua reset_map 每局已无条件把 tree/simple-entity 写入 allow_deconst_list，
-- 此处兜底旧存档缺失该键的情况（读档后 reset_map 前被拦截并弹解锁提示）。
local deconstructable_types = {
	['tree'] = true,
	['simple-entity'] = true,
}

local function on_marked_for_deconstruction(event)
	local this = WPT.get()
	local blacklist = this.allow_deconst_list
	
	local entity = event.entity
	if not entity.valid then return end
	if not event.player_index then return end
	if entity.force.name ~= "neutral" then return end
	if deconstructable_types[entity.type] then return end
	if deconstructable_rocks[entity.name] then return end
	if blacklist[entity.type] then return end
	entity.cancel_deconstruction(game.players[event.player_index].force.name)
	if entity.type == "tree" or entity.type =="simple-entity"  then 
		local player = game.players[event.player_index]
		player.print({'amap.try_to_deconst'})
 end
end

local Event = require 'utils.event' 
Event.add(defines.events.on_marked_for_deconstruction, on_marked_for_deconstruction)
