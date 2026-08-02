--destroying and mining rocks yields ore -- load as last module
local max_spill = 60
local math_floor = math.floor
local math_sqrt = math.sqrt
local diff = require 'maps.amap.diff'
local World = require 'maps.amap.world.framework'

local no_tree={
	["big-rock"] = 1,
	["huge-rock"] = 1,
	["big-sand-rock"] =1,
}

local rock_yield = {
	["big-rock"] = 1,
	["huge-rock"] = 2,
	["big-sand-rock"] = 1,
	["tree-01"] = 0.3,
	["tree-02"] =0.3,
	["tree-02-red"] = 0.3,
	["tree-03"] = 0.3,
	["tree-04"] = 0.3,
	["tree-05"] =0.3,
	["tree-06"] = 0.3,
	["tree-06-brown"] =0.3,
	["tree-07"] = 0.3,
	["tree-08"] = 0.3,
	["tree-08-brown"] = 0.3,
	["tree-08-red"] = 0.3,
	["tree-09"] = 0.3,
	["tree-09-brown"] = 0.3,
	["tree-09-red"] =0.3,
}


local particles = {
	["iron-ore"] = "iron-ore-particle",
	["copper-ore"] = "copper-ore-particle",
	["uranium-ore"] = "coal-particle",
	["coal"] = "coal-particle",
	["stone"] = "stone-particle",
	["angels-ore1"] = "iron-ore-particle",
	["angels-ore2"] = "copper-ore-particle",
	["angels-ore3"] = "coal-particle",
	["angels-ore4"] = "iron-ore-particle",
	["angels-ore5"] = "iron-ore-particle",
	["angels-ore6"] = "iron-ore-particle",
}

local function get_chances()
	local chances = {}

	if prototypes.entity["angels-ore1"] then
		for i = 1, 6, 1 do
			table.insert(chances, {"angels-ore" .. i, 1})
		end
		table.insert(chances, {"coal", 2})
		return chances
	end

	table.insert(chances, {"iron-ore", 25})
	table.insert(chances, {"copper-ore",17})
	table.insert(chances, {"coal",13})
	table.insert(chances, {"uranium-ore",2})
  table.insert(chances, {"stone",10})

	-- if is_mod_loaded('Krastorio2') then
	-- 	table.insert(chances, {"tiberium-ore",1})
	-- 	table.insert(chances, {"raw-rare-metals",1})
	-- end
	return chances
end

local function set_raffle()
	storage.rocks_yield_ore["raffle"] = {}
	for _, t in pairs(get_chances()) do
		for x = 1, t[2], 1 do
			table.insert(storage.rocks_yield_ore["raffle"], t[1])
		end
	end
	storage.rocks_yield_ore["size_of_raffle"] = #storage.rocks_yield_ore["raffle"]
end

local function create_particles(surface, name, position, amount, cause_position)
	local direction_mod = (-100 + math.random(0,200)) * 0.0004
	local direction_mod_2 = (-100 + math.random(0,200)) * 0.0004

	if cause_position then
		direction_mod = (cause_position.x - position.x) * 0.025
		direction_mod_2 = (cause_position.y - position.y) * 0.025
	end

	for i = 1, amount, 1 do
		local m = math.random(4, 10)
		local m2 = m * 0.005

		surface.create_particle({
			name = name,
			position = position,
			frame_speed = 1,
			vertical_speed = 0.130,
			height = 0,
			movement = {
				(m2 - (math.random(0, m) * 0.01)) + direction_mod,
	(m2 - (math.random(0, m) * 0.01)) + direction_mod_2
			}
		})
	end
end

local function get_amount(entity)
	local distance_to_center = math_floor(math_sqrt(entity.position.x ^ 2 + entity.position.y ^ 2))

	local amount = storage.rocks_yield_ore_base_amount + (distance_to_center * storage.rocks_yield_ore_distance_modifier)
	if amount > storage.rocks_yield_ore_maximum_amount then amount = storage.rocks_yield_ore_maximum_amount end

	local m = (70 + math.random(0, 60)) * 0.01

	amount = math_floor(amount * rock_yield[entity.name] * m)
	if amount < 1 then amount = 1 end

	return amount
end

local function on_player_mined_entity(event)
	-- 世界框架：部分世界（如世界15 纯塔防）禁用矿物生成，挖岩石不掉落任何矿石物品
	if World.get_field(diff.get().world, 'disable_rock_ore') then return end

	local entity = event.entity
	if not entity.valid then return end
	if not rock_yield[entity.name] then return end
	local player = game.players[event.player_index]
    if not player or not player.valid then
        return
    end

	-- 隔离副本：副本玩家 force 是 'dungeon_force_*'，不参与主世界矿石掉落
	if player.force.name ~= 'player' then return end

	event.buffer.clear()

	local ore = storage.rocks_yield_ore["raffle"][math.random(1, storage.rocks_yield_ore["size_of_raffle"])]
	local count = get_amount(entity)
	count = math_floor(count * (1 + player.force.mining_drill_productivity_bonus))

	storage.rocks_yield_ore["ores_mined"] = storage.rocks_yield_ore["ores_mined"] + count
	storage.rocks_yield_ore["rocks_broken"] = storage.rocks_yield_ore["rocks_broken"] + 1

	local position = {x = entity.position.x, y = entity.position.y}

	local ore_amount = math_floor(count * 0.85) + 1

	player.create_local_flying_text({text = "+" .. ore_amount .. " [img=item/" .. ore .. "]", position = position, color = {r = 200/255, g = 160/255, b = 30/255}})
if  no_tree[entity.name]~=1 then
   player.insert({name = 'wood', count = 4})
	 player.create_local_flying_text({text = "+" .. 4 .. " [img=item/" .. 'wood' .. "]", position = {x=position.x+0.4,y=position.y+0.4}, color = {r = 200/255, g = 160/255, b = 30/255}})

	 end
	create_particles(player.physical_surface, particles[ore], position, 64, {x = player.physical_position.x, y = player.physical_position.y})

	entity.destroy()

	if ore_amount > 0 then
		local k = player.insert({name = ore, count = ore_amount})
		ore_amount = ore_amount - k
		if ore_amount > 0 then
		--	player.physical_surface.spill_item_stack(position,{name = ore, count = ore_amount}, true)
		player.character.health = player.character.health - player.character.health*0.2 - 100
		player.print({'amap.bag_isfull'},{r = 200, g = 0, b = 30})
		end
	else
		player.physical_surface.spill_item_stack(position,{name = ore, count = ore_amount}, true)
	end

end


local function on_init()
	storage.rocks_yield_ore = {}
	storage.rocks_yield_ore["rocks_broken"] = 0
	storage.rocks_yield_ore["ores_mined"] = 0
	set_raffle()

	if not storage.rocks_yield_ore_distance_modifier then storage.rocks_yield_ore_distance_modifier = 0.25 end
	if not storage.rocks_yield_ore_base_amount then storage.rocks_yield_ore_base_amount = 35 end
	if not storage.rocks_yield_ore_maximum_amount then storage.rocks_yield_ore_maximum_amount = 150 end
end

local Event = require 'utils.event'
Event.on_init(on_init)
Event.add(defines.events.on_player_mined_entity, on_player_mined_entity,{
    {filter = "type", type = 'simple-entity'},
    {filter = "type", type = 'linked-chest'},
    {filter = "type", type = 'car'},

    {filter = "type", type = 'artillery-wagon'},
    {filter = "type", type = 'artillery-turret'},
    {filter = "type", type = 'land-mine'},
    {filter = "type", type = 'spider-vehicle'},
    {filter = "type", type = 'ammo-turret'},
    {filter = "type", type = 'electric-turret'},
    {filter = "type", type = 'fluid-turret'},
	{filter = "type", type = 'tree'}
})
