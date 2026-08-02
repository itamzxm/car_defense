local WPT = require 'maps.amap.table'
local diff = require 'maps.amap.diff'
local Task = require 'utils.task'
local Event = require 'utils.event'
local Token = require 'utils.token'
local world_function = require 'maps.amap.world.world_function'
local enemy_arty = require 'maps.amap.enemy_arty'
local BiterRolls = require 'modules.wave_defense.biter_rolls'
local Factories = require 'maps.amap.production'
local MT = require 'maps.amap.basic_markets'
local Loot = require "maps.amap.loot"

local wushikuangshi = {}

local function rand_box(surface, position)
  local get_tile = surface.get_tile(position)
  if get_tile.valid and get_tile.name == 'out-of-map' then
  return
  end
  local chest = 'iron-chest'
  Loot.add(surface, position, chest)
end

local function rand_building(surface,maxs,position)

  local get_tile = surface.get_tile(position)
  if get_tile.valid and get_tile.name == 'out-of-map' then
  return
  end

  local wave_number = game.forces.player.get_ammo_damage_modifier("laser")
  if wave_number > 1300 then
    return
  end

  local factory = Factories.roll_random_assembler(maxs)
  if not factory then return end

  local entity = surface.create_entity({name = factory.entity, force = "neutral", position = position})
  entity.destructible = false
  entity.minable_flag = false
  entity.operable = false
  entity.disabled_by_script = true
  Factories.register_random_assembler(entity, factory.id, factory.tier)
end

local function rand_shop(surface,position,max)

  local get_tile = surface.get_tile(position)
  if get_tile.valid and get_tile.name == 'out-of-map' then
  return
  end
  local q =math.abs(position.x)/70
  local w =math.abs(position.y)/70


local maxs =math.floor(q+w)
if max then maxs=max end
MT.mountain_market(surface,position,maxs)
end

local function rand_worm(surface,position)
  local get_tile = surface.get_tile(position)
  if get_tile.valid and get_tile.name == 'out-of-map' then
  return false
  end
  BiterRolls.wave_defense_set_worm_raffle(math.sqrt(position.x ^ 2 + position.y ^ 2) * 0.19)
  surface.create_entity({name = BiterRolls.wave_defense_roll_worm_name(), position = position, force = 'enemy'})
  return true
end

local function get_chunk_distance(x1, y1, x2, y2)
    return math.sqrt((x1 - x2)^2 + (y1 - y2)^2)
end

local restore_chunk_task = Token.register(function(data)
    local map = diff.get()

    if map.world ~= 8 then return end
    local dest_surface = game.surfaces[data.dest_name]
    local area = data.area
    local source_name = data.source_name
    local saved_data = data.saved_data

    if not dest_surface or not dest_surface.valid then return end

    local spawner_types = {"biter-spawner", "spitter-spawner"}
    for i = 1, saved_data.spawners do
        local pos = dest_surface.find_non_colliding_position('biter-spawner', {x = (area.left_top.x + 8 + math.random(-8, 8)), y = (area.left_top.y + 8 + math.random(-8, 8))}, 32, 4)
        if pos then
            dest_surface.create_entity{name = spawner_types[math.random(1, #spawner_types)], position = pos, force = "enemy"}
        end
    end

    for i = 1, saved_data.worms do
        local pos = dest_surface.find_non_colliding_position('behemoth-spitter', {x = (area.left_top.x + 8 + math.random(-8, 8)), y = (area.left_top.y + 8 + math.random(-8, 8))}, 32, 2)
        if pos  then
            dest_surface.create_entity{name = BiterRolls.wave_defense_roll_worm_name(), position = pos, force = "enemy"}
        end
    end

    for i = 1, saved_data.assemblers do
        local pos = dest_surface.find_non_colliding_position('behemoth-spitter', {x = (area.left_top.x + 8 + math.random(-8, 8)), y = (area.left_top.y + 8 + math.random(-8, 8))}, 16, 2)
        if pos  then
            rand_building(dest_surface, 999999, pos)
        end
    end

    for i = 1, saved_data.markets do
        local pos = dest_surface.find_non_colliding_position('behemoth-spitter', {x = (area.left_top.x + 8 + math.random(-8, 8)), y = (area.left_top.y + 8 + math.random(-8, 8))}, 16, 2)
        if pos  then
            rand_shop(dest_surface, pos, 999999)
        end
    end

    for i = 1, math.random(10, 20) do
        local rock_pos = dest_surface.find_non_colliding_position('behemoth-spitter', {x = (area.left_top.x + 8 + math.random(-8, 8)), y = (area.left_top.y + 8 + math.random(-8, 8))}, 16, 2)
        if rock_pos then
            if source_name == 'vulcanus' then
                world_function.vulcanus_rock_generator2(dest_surface, rock_pos, dest_surface.map_gen_settings.seed)
            elseif source_name == 'fulgora' then
                world_function.fulgora_rock_generator2(dest_surface, rock_pos, dest_surface.map_gen_settings.seed)
            elseif source_name == 'gleba' then
                world_function.gleba_rock_generator2(dest_surface, rock_pos, dest_surface.map_gen_settings.seed)
            elseif source_name == 'aquilo' then
                world_function.snowy_rock_generator2(dest_surface, rock_pos, dest_surface.map_gen_settings.seed)
            end
        end
    end
end)


local process_single_chunk_swap = Token.register(function(args)
  local map = diff.get()

    if map.world == 8 then
  local cx = args.cx
  local cy = args.cy
  local source_surface = game.surfaces[args.source_name]
  local dest_surface = game.surfaces[args.dest_name]
   local area = {
        left_top = {x = cx * 32, y = cy * 32},
        right_bottom = {x = (cx + 1) * 32, y = (cy + 1) * 32}
    }


    local this = WPT.get()
    if not source_surface or not dest_surface then
      return end
    local chunk_key = cx .. "_" .. cy
    local saved_data = this.chunk_layout_data[chunk_key]

    if not saved_data then
        saved_data = {
            spawners = dest_surface.count_entities_filtered{area = area, type = "unit-spawner", force = "enemy"},
            worms = dest_surface.count_entities_filtered{area = area, type = "turret", force = "enemy"},
            markets = dest_surface.count_entities_filtered{area = area, name = "market", force = "neutral"},
            assemblers = dest_surface.count_entities_filtered{area = area, type = {"assembling-machine", "furnace"}, force = "neutral"}
        }
        this.chunk_layout_data[chunk_key] = saved_data
    end

    local arty_table = enemy_arty.get()

    if arty_table.all then
        for _, baolei_entity in pairs(arty_table.all) do
            if baolei_entity and baolei_entity.valid then
                local entity_pos = baolei_entity.position
                if entity_pos.x >= area.left_top.x and entity_pos.x < area.right_bottom.x and
                   entity_pos.y >= area.left_top.y and entity_pos.y < area.right_bottom.y then
                    return
                end
            end
        end
    end

    local entities_to_destroy = dest_surface.find_entities_filtered{area = area}
    for _, entity in ipairs(entities_to_destroy) do
        if entity.valid and entity.type ~= "character" and entity.type ~= "unit" then
            entity.destroy()
        end
    end

        source_surface.clone_area({
        source_area = area,
        destination_area = area,
        destination_surface = dest_surface,
        clone_tiles = true,
        clone_entities = true,
        clone_decoratives = true,
        clear_destination_entities = false,
        clear_destination_decoratives = true,
        expand_map = false,
        create_build_effect_smoke = false})

   local restore_payload = {
        dest_name = args.dest_name,
        source_name = args.source_name,
        area = area,
        saved_data = saved_data
    }

    Task.set_timeout_in_ticks(15, restore_chunk_task, restore_payload)
end
end)

local function change_world()
    local this = WPT.get()
    local map = diff.get()

    this.change_world_timer = this.change_world_timer + 1

    if this.change_world_timer < 90 then
        return
    end

    this.change_world_timer = 0

    if map.world == 8 then
        this.change_world_index = this.change_world_index + 1
        local surface_name_table = {'vulcanus', 'fulgora', 'gleba', 'aquilo'}

        if this.change_world_index > #surface_name_table then
            this.change_world_index = 1
        end
game.print({'amap.world_phase_shift_warning'}, {r=1, g=0.5, b=0})
        local surface_name = surface_name_table[this.change_world_index]
        local source_surface = game.surfaces[surface_name]


         local radius = 11
          local center_position = {x = 0, y = 0}
          source_surface.request_to_generate_chunks(center_position, radius)
          source_surface.force_generate_chunk_requests()


    local delay_counter = 0
    local center_safe_radius = 3

    for x = -radius, radius do
        for y = -radius, radius do
           local dist = get_chunk_distance(x, y, 0, 0)
           if dist > center_safe_radius then
                delay_counter = delay_counter + 1
                local task_args = {
                    cx = x,
                    cy = y,
                    source_name = surface_name,
                    dest_name = 'nauvis'
                }
                Task.set_timeout_in_ticks(delay_counter*15, process_single_chunk_swap, task_args)
            end
        end
    end


    end
end

Event.on_nth_tick(60*60, change_world)

return wushikuangshi
