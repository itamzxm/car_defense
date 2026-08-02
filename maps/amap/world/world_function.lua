local Public = {}
local simplex_noise = require 'utils.simplex_noise'.d2
local get_noise = require "utils.get_noise"
local IslandManager = require 'maps.amap.island_manager'


local rock_raffle = {"big-sand-rock","big-sand-rock", "big-rock","big-rock","big-rock","big-rock","big-rock","big-rock","big-rock","huge-rock"}
local size_of_rock_raffle = #rock_raffle
local ore_raffle = {	"iron-ore", "iron-ore", "iron-ore", "copper-ore", "copper-ore", "coal", "stone"}


local aquilo_rock_raffle =
{
    'lithium-iceberg-big',
    'lithium-iceberg-huge',
    'lithium-iceberg-big',
    'lithium-iceberg-huge',
}
local gleba_rock_raffle =
{
    'copper-stromatolite',
    'iron-stromatolite',
    'copper-stromatolite',
    'iron-stromatolite'
}
local vulcanus_rock_raffle =
{
    'big-volcanic-rock',
    'huge-volcanic-rock',
    'big-volcanic-rock',
    'huge-volcanic-rock',
}
local fulgora_rock_raffle =
{
    'fulgoran-ruin-small',
    'fulgoran-ruin-small',
    'fulgoran-ruin-medium',
    'fulgoran-ruin-medium',
    'fulgoran-ruin-big',


}
local noises = {
	["no_rocks"] = {{modifier = 0.0033, weight = 1}, {modifier = 0.01, weight = 0.22}, {modifier = 0.05, weight = 0.05}, {modifier = 0.1, weight = 0.04}},
	["no_rocks_2"] = {{modifier = 0.013, weight = 1}, {modifier = 0.1, weight = 0.1}},
	["large_caves"] = {{modifier = 0.0033, weight = 1}, {modifier = 0.01, weight = 0.22}, {modifier = 0.05, weight = 0.05}, {modifier = 0.1, weight = 0.04}},
	["small_caves"] = {{modifier = 0.008, weight = 1}, {modifier = 0.03, weight = 0.15}, {modifier = 0.25, weight = 0.05}},
	["small_caves_2"] = {{modifier = 0.009, weight = 1}, {modifier = 0.05, weight = 0.25}, {modifier = 0.25, weight = 0.05}},
	["cave_ponds"] = {{modifier = 0.01, weight = 1}, {modifier = 0.1, weight = 0.06}},
	["cave_rivers"] = {{modifier = 0.005, weight = 1}, {modifier = 0.01, weight = 0.25}, {modifier = 0.05, weight = 0.01}},
	["cave_rivers_2"] = {{modifier = 0.003, weight = 1}, {modifier = 0.01, weight = 0.21}, {modifier = 0.05, weight = 0.01}},
	["cave_rivers_3"] = {{modifier = 0.002, weight = 1}, {modifier = 0.01, weight = 0.15}, {modifier = 0.05, weight = 0.01}},
	["cave_rivers_4"] = {{modifier = 0.001, weight = 1}, {modifier = 0.01, weight = 0.11}, {modifier = 0.05, weight = 0.01}},
	["scrapyard"] = {{modifier = 0.005, weight = 1}, {modifier = 0.01, weight = 0.35}, {modifier = 0.05, weight = 0.23}, {modifier = 0.1, weight = 0.11}},
  ["forest_location"] = {{modifier = 0.006, weight = 1}, {modifier = 0.01, weight = 0.25}, {modifier = 0.05, weight = 0.15}, {modifier = 0.1, weight = 0.05}},
	["forest_density"] = {{modifier = 0.01, weight = 1}, {modifier = 0.05, weight = 0.5}, {modifier = 0.1, weight = 0.025}},
  ["ores"] = {{modifier = 0.05, weight = 1}, {modifier = 0.02, weight = 0.55}, {modifier = 0.05, weight = 0.05}},
  ["hedgemaze"] = {{modifier = 0.001, weight = 1}}
}


local function is_scrap_area(noise)
	if noise > 0.63 then return end
	if noise < -0.63 then return end
	if noise > 0.33 then return true end
	if noise < -0.33 then return true end
end

local function is_scrap_area_buff(noise)
	if noise > 0.8 then return end
	if noise < -0.8 then return end
	if noise > 0.2 then return true end
	if noise < -0.2 then return true end
end

local base_size = 96
local wall_thickness = 3

local function place_entity(surface, position)
	if math.random(1, 3) == 1 then
		surface.create_entity({name = rock_raffle[math.random(1, size_of_rock_raffle)], position = position, force = "neutral"})
	end
end

function Public.tree_cave(surface,position,seed,get_tile)
	if math.random(1, 2)==2 then
		if not get_tile(position).collides_with("resource") then
		local noise = get_noise("scrapyard", position, seed)
			if is_scrap_area(noise) then
				if math.random(1, 2) == 1 then
					surface.create_entity({name = 'tree-05', position = position, force = "neutral"})
				end
			end
		end
	end
end

function Public.crate_water(surface,position,abc)
	if not abc then abc = 1 end
	for i=1,3 do
	  for b=1,3 do
		local p ={x=position.x-b+2,y=position.y-i-2}
		  surface.set_tiles({{name = "water", position = p}})
	  end
	end
	local entities = surface.find_entities_filtered{position={x=position.x,y=position.y+4},name = "crude-oil", radius = 25 }
  if #entities==0 then
  local e= surface.create_entity({name = "crude-oil", position = {x=position.x,y=position.y+4},amount=300000*abc})

  end
  end

function Public.crate_uore(surface,position,abc,size)
	local ores = {'uranium-ore', 'uranium-ore', 'crude-oil', 'crude-oil'}
  local dist = 3
  local k =1
  if not size then size = 20 end

  if not abc then abc = 1 end
   for a=1,size do
	 for b=1,size do
	 local p = {position.x + a+dist, position.y + b+dist}
		   surface.create_entity({name = ores[k], position = p, amount = 250*abc})
	 end
   end
  k =2
	for a=1,size do
	  for b=1,size do
	  local p = {position.x - a-dist, position.y + b+dist}

			surface.create_entity({name = ores[k], position = p, amount = 250*abc})
	  end
	end
   k =3
	 for a=1,size,5 do
	   for b=1,size,5 do
	   local p = {position.x + a+dist, position.y - b-dist}

			 surface.create_entity({name = ores[k], position = p, amount = 300000*abc})

	   end
	 end
   k =4
	  for a=1,size,5 do
		for b=1,size,5 do
		local p = {position.x - a-dist, position.y - b-dist}

			  surface.create_entity({name = ores[k], position = p, amount = 300000*abc})

		end
	  end
  end

function Public.crate_ore(surface,position,abc,size)
	local ores = {'iron-ore', 'copper-ore', 'stone', 'coal'}
  local dist = 3
  local k =1
  if not size then size = 20 end

  if not abc then abc = 1 end
   for a=1,size do
	 for b=1,size do
	 local p = {position.x + a+dist, position.y + b+dist}
		   surface.create_entity({name = ores[k], position = p, amount = 250*abc})
	 end
   end
  k =2
	for a=1,size do
	  for b=1,size do
	  local p = {position.x - a-dist, position.y + b+dist}

			surface.create_entity({name = ores[k], position = p, amount = 250*abc})
	  end
	end
   k =3
	 for a=1,size do
	   for b=1,size do
	   local p = {position.x + a+dist, position.y - b-dist}

			 surface.create_entity({name = ores[k], position = p, amount = 250*abc})

	   end
	 end
   k =4
	  for a=1,size do
		for b=1,size do
		local p = {position.x - a-dist, position.y - b-dist}

			  surface.create_entity({name = ores[k], position = p, amount = 250*abc})

		end
	  end
  end

function Public.world_cave(surface,position,seed,get_tile)
	if math.random(1, 5)<=2 then
		if not get_tile(position).collides_with("resource") then
		local noise = get_noise("scrapyard", position, seed)
			if is_scrap_area(noise) then
				place_entity(surface, position)
			end
		end
	end
end

function Public.world_cave_buff(surface,position,seed,get_tile)
		local tile = get_tile(position)
		local can_place = true

		-- 检查是否可以放置资源
		if tile.collides_with then
			can_place = not tile.collides_with("resource")
		else
			-- 兼容旧版本的方式
			can_place = not tile.collision_mask or not tile.collision_mask["resource"]
		end

		if can_place then
			local noise = get_noise("scrapyard", position, seed)
			if is_scrap_area_buff(noise) then
				place_entity(surface, position)
			end
		end
end

-- 生成雪地石头
function Public.snowy_rock_generator(surface,position,seed,get_tile)
	local tile = get_tile(position)
	local can_place = true

	-- 检查是否可以放置资源
	if tile.collides_with then
		can_place = not tile.collides_with("resource")
	else
		-- 兼容旧版本的方式
		can_place = not tile.collision_mask or not tile.collision_mask["resource"]
	end

	if can_place then
		local noise = get_noise("scrapyard", position, seed)
		if is_scrap_area_buff(noise) then
			if math.random(1, 3) == 1 then
				surface.create_entity({
					name = aquilo_rock_raffle[math.random(1, #aquilo_rock_raffle)],
					position = position,
					force = "neutral"
				})
			end
		end
	end
end

-- 生成冰山石头
function Public.aquilo_rock_generator(surface,position,seed,get_tile)
	local tile = get_tile(position)
	local can_place = true

	-- 检查是否可以放置资源
	if tile.collides_with then
		can_place = not tile.collides_with("resource")
	else
		-- 兼容旧版本的方式
		can_place = not tile.collision_mask or not tile.collision_mask["resource"]
	end

	if can_place then
		local noise = get_noise("scrapyard", position, seed)
		if is_scrap_area_buff(noise) then
			if math.random(1, 3) == 1 then
				surface.create_entity({
					name = aquilo_rock_raffle[math.random(1, #aquilo_rock_raffle)],
					position = position,
					force = "neutral"
				})
			end
		end
	end
end

-- 生成生物层石头
function Public.gleba_rock_generator(surface,position,seed,get_tile)
	local tile = get_tile(position)
	local can_place = true

	-- 检查是否可以放置资源
	if tile.collides_with then
		can_place = not tile.collides_with("resource")
	else
		-- 兼容旧版本的方式
		can_place = not tile.collision_mask or not tile.collision_mask["resource"]
	end

	if can_place then
		local noise = get_noise("scrapyard", position, seed)
		if is_scrap_area_buff(noise) then
			if math.random(1, 3) == 1 then
				surface.create_entity({
					name = gleba_rock_raffle[math.random(1, #gleba_rock_raffle)],
					position = position,
					force = "neutral"
				})
			end
		end
	end
end

-- 生成火山石头
function Public.vulcanus_rock_generator(surface,position,seed,get_tile)
	local tile = get_tile(position)
	local can_place = true

	-- 检查是否可以放置资源
	if tile.collides_with then
		can_place = not tile.collides_with("resource")
	else
		-- 兼容旧版本的方式
		can_place = not tile.collision_mask or not tile.collision_mask["resource"]
	end

	if can_place then
		local noise = get_noise("scrapyard", position, seed)
		if is_scrap_area_buff(noise) then
			if math.random(1, 3) == 1 then
				surface.create_entity({
					name = vulcanus_rock_raffle[math.random(1, #vulcanus_rock_raffle)],
					position = position,
					force = "neutral"
				})
			end
		end
	end
end

-- 生成废墟石头
function Public.fulgora_rock_generator(surface,position,seed,get_tile)
	local tile = get_tile(position)
	local can_place = true

	-- 检查是否可以放置资源
	if tile.collides_with then
		can_place = not tile.collides_with("resource")
	else
		-- 兼容旧版本的方式
		can_place = not tile.collision_mask or not tile.collision_mask["resource"]
	end

	if can_place then
		local noise = get_noise("scrapyard", position, seed)
		if is_scrap_area_buff(noise) then
			if math.random(1, 3) == 1 then
				surface.create_entity({
					name = fulgora_rock_raffle[math.random(1, #fulgora_rock_raffle)],
					position = position,
					force = "neutral"
				})
			end
		end
	end
end

-- 复制版本：直接生成石头，不加判断
function Public.aquilo_rock_generator2(surface,position,seed,get_tile)
	surface.create_entity({
		name = aquilo_rock_raffle[math.random(1, #aquilo_rock_raffle)],
		position = position,
		force = "neutral"
	})
end

-- 复制版本：直接生成石头，不加判断
function Public.gleba_rock_generator2(surface,position,seed,get_tile)
	surface.create_entity({
		name = gleba_rock_raffle[math.random(1, #gleba_rock_raffle)],
		position = position,
		force = "neutral"
	})
end

-- 复制版本：直接生成石头，不加判断
function Public.vulcanus_rock_generator2(surface,position,seed,get_tile)
	surface.create_entity({
		name = vulcanus_rock_raffle[math.random(1, #vulcanus_rock_raffle)],
		position = position,
		force = "neutral"
	})
end

-- 复制版本：直接生成石头，不加判断
function Public.fulgora_rock_generator2(surface,position,seed,get_tile)
	surface.create_entity({
		name = fulgora_rock_raffle[math.random(1, #fulgora_rock_raffle)],
		position = position,
		force = "neutral"
	})
end


local function is_spawn_wall(p)
	if p.x >= base_size - wall_thickness then return true end
	if p.x < base_size * -1 + wall_thickness then return true end
	if p.y >= base_size - wall_thickness then return true end
	if p.y < base_size * -1 + wall_thickness then return true end
	return false
end

function Public.quarter(event,x,y)
	local left_top = event.area.left_top
	if left_top.x < base_size and left_top.y < base_size and left_top.x >= base_size * -1 and left_top.y >= base_size * -1 then

		--建设墙
		local p = {x = left_top.x + x, y = left_top.y + y}
		event.surface.set_tiles({{name = "stone-path", position = p}})
		if is_spawn_wall(p) then
			event.surface.create_entity({name = "stone-wall", position = p, force = "player"})
		end
		--生成矿物
		local ore = false
		if left_top.x == -64 and left_top.y == -64 then ore = "coal" end
		if left_top.x == 32 and left_top.y == 32 then ore = "stone" end
		if left_top.x == 32 and left_top.y == -64 then ore = "iron-ore" end
		if left_top.x == -64 and left_top.y == 32 then ore = "copper-ore" end


		if not ore then return end
	local p = {x = left_top.x + x, y = left_top.y + y}
		event.surface.create_entity({name = ore, position = p, amount = 1000})
	end

	--切割水域
	local pos = {left_top.x + x, left_top.y + y}
	local area=event.area
	local surface=event.surface
	if left_top.x == 0 or left_top.x == -32 then
		surface.set_tiles({{name = "deepwater", position = pos}})
		surface.destroy_decoratives({area = area})

	end
	if left_top.y == 0 or left_top.y == -32 then
		surface.set_tiles({{name = "deepwater", position = pos}})
		surface.destroy_decoratives({area = area})
	end
end

-- 世界14专用：quarter的独立副本，修改不影响世界2
local w14_base_size = 96
local w14_wall_thickness = 3

local function w14_is_spawn_wall(p)
	if p.x >= w14_base_size - w14_wall_thickness then return true end
	if p.x < w14_base_size * -1 + w14_wall_thickness then return true end
	if p.y >= w14_base_size - w14_wall_thickness then return true end
	if p.y < w14_base_size * -1 + w14_wall_thickness then return true end
	return false
end

function Public.world14_quarter(event, x, y)
	local left_top = event.area.left_top
	if left_top.x < w14_base_size and left_top.y < w14_base_size and left_top.x >= w14_base_size * -1 and left_top.y >= w14_base_size * -1 then

		--建设墙
		local p = {x = left_top.x + x, y = left_top.y + y}
		event.surface.set_tiles({{name = "stone-path", position = p}})
		if w14_is_spawn_wall(p) then
			event.surface.create_entity({name = "stone-wall", position = p, force = "player"})
		end
		--生成矿物（世界14：减半）
		local ore = false
		if left_top.x == -64 and left_top.y == -64 then ore = "coal" end
		if left_top.x == 32 and left_top.y == 32 then ore = "stone" end
		if left_top.x == 32 and left_top.y == -64 then ore = "iron-ore" end
		if left_top.x == -64 and left_top.y == 32 then ore = "copper-ore" end

		if not ore then return end
		local p = {x = left_top.x + x, y = left_top.y + y}
		event.surface.create_entity({name = ore, position = p, amount = 500})
	end
end


function Public.crossing(surface,position,left_top)

local noise_1 =1
if left_top.x < 64 and left_top.x > -64 then
	if position.x > -80 + (noise_1 * 8) and position.x < 80 + (noise_1 * 8) then
		local tile = surface.get_tile(position)
		if tile.name == "water" or tile.name == "deepwater" then
			surface.set_tiles({{name = "grass-2", position = position}})
		end

		if position.x > -26  and position.x < 28  then
			if position.y > 0 then
				surface.create_entity({name = "stone", position = position, amount = 1 + position.y * 0.5})
			else
				surface.create_entity({name = "coal", position = position, amount = 1 + position.y * -1 * 0.5})
			end
		end
	end
end

	if left_top.y < 64 and left_top.y > -64 then
		if position.y > -80 + (noise_1 * 8) and position.y < 80 + (noise_1 * 8) then
			local tile = surface.get_tile(position)
			if tile.name == "water" or tile.name == "deepwater" then
				surface.set_tiles({{name = "grass-2", position = position}})
			end
		end

		if position.y > -26  and position.y < 28  then
			if position.x > 0 then
				surface.create_entity({name = "copper-ore", position = position, amount = 1 + position.x * 0.5})
			else
				surface.create_entity({name = "iron-ore", position = position, amount = 1 + position.x * -1 * 0.5})
			end
		end
	end
end
local spawn_size = 160
local spawn_check = spawn_size + 96
--blue-refined-concrete
local waters = {"water-shallow","water"}

local function is_water(position, noise, seed)
	if math.abs(position.y) <= spawn_check or math.abs(position.x) <= spawn_check then
		local border_noise = get_noise("cave_ponds", position, seed)
		if math.abs(position.x) + border_noise * 10 < spawn_size and math.abs(position.y) + border_noise * 10 < spawn_size then return false end
		if math.abs(position.x) + border_noise * 10 < spawn_size + 32 and math.abs(position.y) + border_noise * 10 < spawn_size + 32 then return true end
	end
	if noise > 0.55 then return end
	if noise < -0.55 then return end
	if noise > 0.55 then return true end
	if noise < -0.55 then return true end
	return true
end

function Public.water(surface, area, seed)
	-- 1. 本地化性能优化
	local insert = table.insert
	local floor = math.floor
	local random = math.random

	-- 2. 参数调整 (针对 modifier 0.002 的平滑地形)
	-- GRID_SIZE: 160 (5个区块宽)。
	-- 这比之前的 320 小一半，能捕获更多岛屿，但通过限制搜索半径防止重叠。
	local GRID_SIZE = 160

	-- SEARCH_RADIUS: 64。
	-- 如果锚点落在水里，允许向周围 64 格内寻找陆地。
	-- 关键点：64 < (160 / 2)，保证了相邻网格的搜索区互不接触。
	local SEARCH_RADIUS = 64

	-- SEARCH_STEP: 16。
	-- 搜索时的步长，越小越精准但计算量稍大。16 是半个区块，足够应付平滑地形。
	local SEARCH_STEP = 16

	local water_tiles = {}
	local fish_entities = {}

	-- 3. 地形与鱼生成 (标准流程)
	for x = area.left_top.x, area.right_bottom.x - 1 do
		for y = area.left_top.y, area.right_bottom.y - 1 do
			local position = {x = x, y = y}
			local noise = get_noise("watery_world", position, seed)

			if is_water(position, noise, seed) then
				insert(water_tiles, {name = "water", position = position})
				if random(1, 200) == 1 then
					insert(fish_entities, position)
				end
			end
		end
	end

	-- 4. 批量修改地砖
	if #water_tiles > 0 then
		surface.set_tiles(water_tiles, true)
	end

	-- 5. 生成鱼
	local fish_types = storage.watery_world_fishes or {"fish"}
	local num_fish_types = #fish_types
	for _, fish_pos in ipairs(fish_entities) do
		surface.create_entity({
			name = fish_types[random(1, num_fish_types)],
			position = fish_pos
		})
	end

	-- 6. 市场生成算法 (搜寻优化版)
	local min_grid_x = floor(area.left_top.x / GRID_SIZE)
	local max_grid_x = floor((area.right_bottom.x - 1) / GRID_SIZE)
	local min_grid_y = floor(area.left_top.y / GRID_SIZE)
	local max_grid_y = floor((area.right_bottom.y - 1) / GRID_SIZE)

	for gx = min_grid_x, max_grid_x do
		for gy = min_grid_y, max_grid_y do

			-- 计算该 Grid 的绝对中心点
			local base_center_x = gx * GRID_SIZE + (GRID_SIZE / 2)
			local base_center_y = gy * GRID_SIZE + (GRID_SIZE / 2)

			-- 增加一点确定性的随机抖动 (Jitter)，让市场看起来不那么像棋盘
			-- 使用 hash 保证跨区块一致性
			local hash = (gx * 5147 + gy * 3499 + seed) % 2147483647
			local jitter_x = (hash % 32) - 16 -- +/- 16 格微调
			local jitter_y = (floor(hash / 32) % 32) - 16

			local center_x = base_center_x + jitter_x
			local center_y = base_center_y + jitter_y

			-- 确定市场位置的搜索逻辑
			local valid_market_pos = nil

			-- 优化：只有当中心点在当前生成的 Chunk 附近时才计算，避免重复计算
			-- 我们只在负责该中心点的那个 Chunk 触发搜索
			if center_x >= area.left_top.x and center_x < area.right_bottom.x and
			   center_y >= area.left_top.y and center_y < area.right_bottom.y then

				-- 开始搜索：先看中心点
				local center_pos = {x = center_x, y = center_y}
				local noise = get_noise("watery_world", center_pos, seed)

				if not is_water(center_pos, noise, seed) then
					valid_market_pos = center_pos
				else
					-- 如果中心点是水，向四周扩散搜索陆地 (十字型或螺旋型)
					-- 这种方式极大增加了命中岛屿边缘的概率
					local found = false
					for r = SEARCH_STEP, SEARCH_RADIUS, SEARCH_STEP do
						-- 检查 上下左右 四个方向
						local offsets = {
							{0, r}, {0, -r}, {r, 0}, {-r, 0},
							{r, r}, {r, -r}, {-r, r}, {-r, -r} -- 八向搜索，提高命中率
						}

						for _, offset in ipairs(offsets) do
							local check_pos = {x = center_x + offset[1], y = center_y + offset[2]}
							local check_noise = get_noise("watery_world", check_pos, seed)

							if not is_water(check_pos, check_noise, seed) then
								valid_market_pos = check_pos
								found = true
								break
							end
						end
						if found then break end
					end
				end

				-- 如果找到了有效的陆地点，生成市场
				if valid_market_pos then
					-- 检查周围60米内是否已有市场
					local market_count = surface.count_entities_filtered({
						name = "market",
						position = valid_market_pos,
						radius = 60
					})

					-- 如果附近没有市场，才生成新市场
					if market_count == 0 then
						-- 最后确认该点允许放置实体 (非必要，但为了保险)
						if surface.can_place_entity({name = "market", position = valid_market_pos}) then
							local market = surface.create_entity({
								name = "market",
								position = valid_market_pos,
								force = "neutral"
							})
							if market and market.valid then
								market.destructible = false
								market.minable_flag = false

								local island_id = IslandManager.register_island(surface, market)
								IslandManager.setup_island_market(market, island_id)
							end
						end
					end
				end
			end
		end
	end

	return nil

end

local function get_noise_2(name, pos, seed)
	local noise = 0
	local d = 0
	for _, n in pairs(noises[name]) do
		noise = noise + simplex_noise(pos.x * n.modifier, pos.y * n.modifier, seed) * n.weight
		d = d + n.weight
		seed = seed + 10000
	end
	noise = noise / d
	return noise
end

function Public.water_dungle(surface,position,seed)

	if not surface.get_tile(position).collides_with("resource") then
		local noise1 = get_noise_2("large_caves", position, seed)
		local noise2 = get_noise_2("cave_rivers", position, seed)
		local	noise = get_noise("watery_world", position, seed)
	if noise1 > -0.05 and noise1 < 0.05 and noise2 < 0.25 then
			surface.set_tiles({{name = waters[math.floor(noise * 10 % 2 + 1)], position = position}}, true)
			if math.random(1, 128) == 1 then
				surface.create_entity({name = storage.watery_world_fishes[math.random(1, #storage.watery_world_fishes)], position = position})
			end
		end
	end

end

function Public.winter(surface,event,seed)

	local ores = surface.find_entities_filtered({area = event.area, name = {"iron-ore", "copper-ore", "coal", "stone"}})
	for _, ore in pairs(ores) do
		local pos = ore.position
		local noise = simplex_noise(pos.x * 0.005, pos.y * 0.005, seed) + simplex_noise(pos.x * 0.01, pos.y * 0.01, seed) * 0.3 + simplex_noise(pos.x * 0.05, pos.y * 0.05, seed) * 0.2

		local i = (math.floor(noise * 100) % 7) + 1
		surface.create_entity({name = ore_raffle[i], position = ore.position, amount = ore.amount})
		ore.destroy()
	end

end

function Public.chaos_rock_generator(surface,position,seed,get_tile)
	if math.random(1, 5)<=2 then
		if not get_tile(position).collides_with("resource") then
			local noise = get_noise("scrapyard", position, seed)
			if is_scrap_area(noise) then
				local rock_type = math.random(1, 5)
				local selected_raffle
				if rock_type == 1 then
					selected_raffle = rock_raffle
				elseif rock_type == 2 then
					selected_raffle = aquilo_rock_raffle
				elseif rock_type == 3 then
					selected_raffle = fulgora_rock_raffle
				elseif rock_type == 4 then
					selected_raffle = gleba_rock_raffle
				else
					selected_raffle = vulcanus_rock_raffle
				end
				if math.random(1, 3) == 1 then
					surface.create_entity({
						name = selected_raffle[math.random(1, #selected_raffle)],
						position = position,
						force = "neutral"
					})
				end
			end
		end
	end
end

function Public.find_island_centers(seed, area, grid_size, water_threshold)
	if not area then
		area = {
			left_top = {x = -1000, y = -1000},
			right_bottom = {x = 1000, y = 1000}
		}
	end

	if not grid_size then
		grid_size = 5
	end

	if not water_threshold then
		water_threshold = 0.55
	end

	local island_centers = {}
	local checked_positions = {}

	for x = area.left_top.x, area.right_bottom.x, grid_size do
		for y = area.left_top.y, area.right_bottom.y, grid_size do
			local position = {x = x, y = y}
			local noise = get_noise("watery_world", position, seed)

			if math.abs(noise) < water_threshold then
				local is_local_min = true

				for dx = -grid_size, grid_size, grid_size do
					for dy = -grid_size, grid_size, grid_size do
						if dx ~= 0 or dy ~= 0 then
							local neighbor_pos = {x = x + dx, y = y + dy}
							local neighbor_noise = get_noise("watery_world", neighbor_pos, seed)

							if math.abs(neighbor_noise) < math.abs(noise) then
								is_local_min = false
								break
							end
						end
					end
					if not is_local_min then
						break
					end
				end

				if is_local_min then
					table.insert(island_centers, {
						x = x,
						y = y,
						noise = noise
					})
				end
			end
		end
	end

	return island_centers
end

function Public.find_island_center_in_chunk(chunk_position, seed, water_threshold)
	if not water_threshold then
		water_threshold = 0.55
	end

	local chunk_x = chunk_position.x
	local chunk_y = chunk_position.y

	local chunk_left_top = {x = chunk_x * 32, y = chunk_y * 32}
	local chunk_right_bottom = {x = (chunk_x + 1) * 32, y = (chunk_y + 1) * 32}

	local has_land = false
	for x = chunk_left_top.x, chunk_right_bottom.x, 8 do
		for y = chunk_left_top.y, chunk_right_bottom.y, 8 do
			local position = {x = x, y = y}
			local noise = get_noise("watery_world", position, seed)

			if math.abs(noise) < water_threshold then
				has_land = true
				break
			end
		end
		if has_land then
			break
		end
	end

	if not has_land then
		return nil
	end

	local island_center = nil
	local min_noise_abs = water_threshold
	local scan_step = 4

	for x = chunk_left_top.x, chunk_right_bottom.x, scan_step do
		for y = chunk_left_top.y, chunk_right_bottom.y, scan_step do
			local position = {x = x, y = y}
			local noise = get_noise("watery_world", position, seed)
			local noise_abs = math.abs(noise)

			if noise_abs < water_threshold then
				local is_local_min = true

				for dx = -scan_step, scan_step, scan_step do
					for dy = -scan_step, scan_step, scan_step do
						if dx ~= 0 or dy ~= 0 then
							local neighbor_pos = {x = x + dx, y = y + dy}
							local neighbor_noise = get_noise("watery_world", neighbor_pos, seed)

							if math.abs(neighbor_noise) < noise_abs then
								is_local_min = false
								break
							end
						end
					end
					if not is_local_min then
						break
					end
				end

				if is_local_min and noise_abs < min_noise_abs then
					min_noise_abs = noise_abs
					island_center = {
						x = x,
						y = y,
						noise = noise
					}
				end
			end
		end
	end

	return island_center
end

return Public
