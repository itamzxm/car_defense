-- maps/amap/world/world_helpers.lua
-- 世界共享辅助函数和常量
--
-- 从 world_main.lua 提取，供各世界模块的 terrain_generator 使用。
-- 包含：权重常量、虫巢价值表、宝箱/商店/工厂/虫巢生成函数、
-- 区域克隆函数、星球地表创建函数、世界 7/13 共用的地形配置表、
-- 世界 13 专属的定时检查函数。

local Public = {}

local WPT = require 'maps.amap.table'
local ICWF = require 'maps.amap.ICW.functions'
local WD = require 'modules.wave_defense.table'
local Loot = require "maps.amap.loot"
local BiterRolls = require 'modules.wave_defense.biter_rolls'
local MT = require "maps.amap.basic_markets"
local Factories = require 'maps.amap.production'
local diff = require 'maps.amap.diff'
local world_function = require 'maps.amap.world.world_function'
local enemy_arty = require 'maps.amap.enemy_arty'
local Instance = require 'maps.amap.instance.instance'
local jixianchengshi = require 'maps.amap.world.word__jixianchengshi'
local beishuiyizhan = require 'maps.amap.world.word_beishuiyizhan'

--==============================================================================
-- 常量
--==============================================================================

Public.weight_shop = 1
Public.weight_build = 3
Public.weight_box = 6
Public.weight_worm = 0
-- 史诗木箱权重：与野外宝箱权重一致，受世界1加成（与世界1宝箱一样×1.5）
-- 同时存在上限 5 个，累计生成上限 25 个（全局计数，reset_table 归零），spawn_epic_chest 内部判断
Public.weight_epic_box = 6

-- 虫巢价值表系统（参考enemy_arty.lua）
Public.enemy_base_value = {
  ["biter-spawner"] = {name = "biter-spawner", worth = 20, distance_threshold = 0},
  ["spitter-spawner"] = {name = "spitter-spawner", worth = 20, distance_threshold = 0},
  ["small-worm-turret"] = {name = "small-worm-turret", worth = 8, distance_threshold = 0},
  ["medium-worm-turret"] = {name = "medium-worm-turret", worth = 15, distance_threshold = 1408},
  ["big-worm-turret"] = {name = "big-worm-turret", worth = 25, distance_threshold = 2816},
  ["behemoth-worm-turret"] = {name = "behemoth-worm-turret", worth = 40, distance_threshold = 3220},
  ["gun-turret"] = {name = "gun-turret", worth = 5, distance_threshold = 1408},
  ["laser-turret"] = {name = "laser-turret", worth = 8, distance_threshold = 1408},
  ["flamethrower-turret"] = {name = "flamethrower-turret", worth = 10, distance_threshold = 2112},
  ["artillery-turret"] = {name = "artillery-turret", worth = 100, distance_threshold = 3535}
}

-- 生成器列表
Public.spawner = {'biter-spawner', 'spitter-spawner'}

--==============================================================================
-- 世界 7/13 共用的地形配置表（原 world_main.lua 第 60-96 行）
--==============================================================================

Public.world_7_terrain_config = {
  [0] = {
    generators = {
      function(surface, position, seed, get_tile)
        world_function.tree_cave(surface, position, seed, get_tile)
        world_function.water_dungle(surface, position, seed)
      end
    }
  },
  [1] = {
    clone_area_name = 'vulcanus',
    rock_generator = function(surface, position, seed, get_tile)
      world_function.vulcanus_rock_generator(surface, position, seed, get_tile)
    end
  },
  [2] = {
    clone_area_name = 'fulgora',
    rock_generator = function(surface, position, seed, get_tile)
      world_function.fulgora_rock_generator(surface, position, seed, get_tile)
    end
  },
  [3] = {
    generators = {
      function(surface, position, seed, get_tile)
        world_function.world_cave(surface, position, seed, get_tile)
      end
    }
  },
  [4] = {
    min_wave = 1250,
    clone_area_name = 'gleba',
    rock_generator = function(surface, position, seed, get_tile)
      world_function.gleba_rock_generator(surface, position, seed, get_tile)
    end
  }
}

--==============================================================================
-- 共享辅助函数
--==============================================================================

local math_abs = math.abs

-- 基于价值系统生成虫巢（参考enemy_arty.lua的baolei函数）
function Public.generate_enemy_base_by_value(surface, area, total_value, distance_from_base)
  local difficulty_multiplier = 1 + distance_from_base * 0.01
  local adjusted_value = total_value * difficulty_multiplier

  local can_build = {}
  for _, building in pairs(Public.enemy_base_value) do
    if distance_from_base >= building.distance_threshold then
      table.insert(can_build, building)
    end
  end

  if #can_build == 0 then
    return {}
  end

  local remaining_value = adjusted_value
  local all_things = {}
  local attempt_count = 0
  local max_attempts = 200

  while remaining_value > 0 and attempt_count < max_attempts do
    attempt_count = attempt_count + 1

    local available_buildings = {}
    for _, building in ipairs(can_build) do
      if remaining_value >= building.worth then
        table.insert(available_buildings, building)
      end
    end

    if #available_buildings == 0 then
      break
    end

    local selected_building = available_buildings[math.random(1, #available_buildings)]

    local width = area.right_bottom.x - area.left_top.x
    local height = area.right_bottom.y - area.left_top.y

    if width <= 0 or height <= 0 then
        attempt_count = attempt_count - 1
        break
    end

    local random_x = area.left_top.x + math.random(0, width)
    local random_y = area.left_top.y + math.random(0, height)
    local random_position = {x = random_x, y = random_y}

    if surface.can_place_entity{name = selected_building.name, position = random_position} then
      local entity_data = {
        name = selected_building.name,
        position = random_position,
        force = "enemy"
      }

      if selected_building.name == 'flamethrower-turret' then
        entity_data.direction = 9
      end

      local entity = surface.create_entity(entity_data)

      if entity then
        table.insert(all_things, entity)
        remaining_value = remaining_value - selected_building.worth

        if entity.name == 'gun-turret' then
          enemy_arty.add_gun(entity)
        elseif entity.name == 'laser-turret' then
          enemy_arty.add_laser(entity)
        elseif entity.name == 'flamethrower-turret' then
          enemy_arty.add_flame(entity)
        elseif entity.name == 'artillery-turret' then
          enemy_arty.add_arty(entity)
        end
      end
    end

    if #all_things >= 200 then
      break
    end
  end

  return all_things
end

function Public.move_away_things(surface, area)
  for _, e in pairs(surface.find_entities_filtered({type = {"unit-spawner",  "unit", "tree"}, area = area})) do
    local position = surface.find_non_colliding_position(e.name, e.position, 128, 4)
    if position then
      surface.create_entity({name = e.name, position = position, force = "enemy"})
      e.destroy()
    end
  end
end

function Public.build_base(surface, maxs, event, position)
  local map = diff.get()
  if map.world ~= 13 then
    if position.x>-4 and position.x<4 then
      if position.y>1 and position.y<5 then
        surface.set_tiles({{name = "water", position = position}})
      end
    end
  end
  if maxs <= 65 then
    if maxs == 56 then
      Public.move_away_things(surface, event.area)
    end
  end
end

function Public.rand_box(surface, position)
  local get_tile = surface.get_tile(position)
  if get_tile.valid and get_tile.name == 'out-of-map' then
  return
  end
  local chest = 'iron-chest'
  Loot.add(surface, position, chest)
end

function Public.rand_building(surface, maxs, position)
  local get_tile = surface.get_tile(position)
  if get_tile.valid and get_tile.name == 'out-of-map' then
  return
  end

  local wave_number = WD.get('wave_number')
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

function Public.rand_shop(surface, position, max)
  local get_tile = surface.get_tile(position)
  if get_tile.valid and get_tile.name == 'out-of-map' then
  return
  end
  local q = math_abs(position.x)/70
  local w = math_abs(position.y)/70

  local maxs = math.floor(q+w)
  if max then maxs = max end
  MT.mountain_market(surface, position, maxs)
end

function Public.rand_worm(surface, position)
  local get_tile = surface.get_tile(position)
  if get_tile.valid and get_tile.name == 'out-of-map' then
  return false
  end
  BiterRolls.wave_defense_set_worm_raffle(math.sqrt(position.x ^ 2 + position.y ^ 2) * 0.19)
  surface.create_entity({name = BiterRolls.wave_defense_roll_worm_name(), position = position, force = 'enemy'})
  return true
end

-- 史诗木箱生成委托给 instance.lua 的 Public.spawn_epic_chest
-- （统一管理：同时上限 5 / 累计上限 25，注册到 this.epic_chests 数组、不可摧毁/不可操作）
function Public.try_spawn_epic_chest(surface, position)
  return Instance.spawn_epic_chest(surface, position) ~= nil
end

function Public.ywjz(surface, position, maxs, shop)
  local this = WPT.get()
  local rand_k = math.random(1, maxs)
  local map = diff.get()
  local current_weight_box = Public.weight_box
  local current_weight_shop = Public.weight_shop
  local current_weight_build = Public.weight_build
  local current_weight_epic_box = Public.weight_epic_box

  if map and map.world == 1 then
    current_weight_box = Public.weight_box * 1.5
    current_weight_epic_box = Public.weight_epic_box * 1.5  -- 史诗木箱与世界1宝箱一样受1.5倍加成
  end

  if map and map.world == 2 then
    current_weight_build = Public.weight_build * 2
  end

  if map and map.world == 6 then
    current_weight_shop = Public.weight_shop * 1.5
  end

  if map and map.world == 11 then
    current_weight_shop = 0
  end

  if rand_k <= current_weight_shop then
    Public.rand_shop(surface, position)
  end
  if current_weight_shop < rand_k and rand_k <= current_weight_shop + current_weight_build then
    if this.enable_wild_factorio then
      Public.rand_building(surface, shop, position)
    end
  end
  if current_weight_shop + current_weight_build < rand_k and rand_k <= current_weight_shop + current_weight_build + current_weight_box then
    Public.rand_box(surface, position)
  end
  -- 史诗木箱分支：与 rand_box 互斥，权重 = weight_epic_box（与野外宝箱一致）
  -- 同时上限 5 / 累计上限 25，spawn_epic_chest 内部判断已达上限返回 nil（不生成）
  if current_weight_shop + current_weight_build + current_weight_box < rand_k and rand_k <= current_weight_shop + current_weight_build + current_weight_box + current_weight_epic_box then
    Public.try_spawn_epic_chest(surface, position)
  end
  if current_weight_shop + current_weight_build + current_weight_box + current_weight_epic_box < rand_k and rand_k <= current_weight_shop + current_weight_build + current_weight_box + current_weight_epic_box + Public.weight_worm then
    Public.rand_worm(surface, position)
  end
end

function Public.clone_area(surface_name, position, area, clear_destination_entities)
  if not game.surfaces[surface_name].is_chunk_generated(position) then
    game.surfaces[surface_name].request_to_generate_chunks(position, 0)
    game.surfaces[surface_name].force_generate_chunk_requests()
  end
  if game.surfaces[surface_name] then
    game.surfaces[surface_name].clone_area({
      source_area = area,
      destination_area = area,
      destination_surface = game.surfaces['nauvis'],
      clone_tiles = true,
      clone_entities = true,
      clone_decoratives = true,
      clear_destination_entities = clear_destination_entities,
      clear_destination_decoratives = true,
      expand_map = true,
      create_build_effect_smoke = false
    })
  end
end

function Public.create_planet_surface(planet_name, active_surface_index, ziyuan, world_type)
  if game.planets[planet_name] and not game.surfaces[planet_name] then
    local map_gen_settings = table.deepcopy(game.planets[planet_name].prototype.map_gen_settings)
    map_gen_settings.seed = math.random(10000, 99999)

    map_gen_settings.autoplace_controls = map_gen_settings.autoplace_controls or {}

    if world_type == 7 or world_type == 8 then
      local planet_specials = {
        ["vulcanus"] = {"tungsten_ore", "calcite", "sulfuric_acid_geyser"},
        ["fulgora"] = {"scrap"},
        ["aquilo"] = {"lithium_brine", "fluorine_vent"}
      }

      local specials = planet_specials[planet_name]
      if specials then
        for _, res_name in ipairs(specials) do
          local base_freq = 1.0
          if ziyuan[res_name] then
            base_freq = tonumber(ziyuan[res_name].frequency) or 1.0
          end

          map_gen_settings.autoplace_controls[res_name] = {
            frequency = tostring(base_freq * 3),
            size = "1.2",
            richness = "1.2"
          }
        end
      end

      if planet_name == "gleba" and ziyuan["gleba_enemy_base"] then
        map_gen_settings.autoplace_controls["gleba_enemy_base"] = table.deepcopy(ziyuan["gleba_enemy_base"])
        local freq = tonumber(ziyuan["gleba_enemy_base"].frequency) or 3
        map_gen_settings.autoplace_controls["gleba_enemy_base"].frequency = tostring(freq * 1.5)
      end
    end

    game.create_surface(planet_name, map_gen_settings)
    return true
  end
  return false
end

--==============================================================================
-- 世界 13 专属：每 5 秒轮询——当某个检查点的 3 个堡垒全部死亡后，生成战利品车厢 + 火箭发射井
--==============================================================================

function Public.check_world_13_zones()
  local this = WPT.get()
  local map = diff.get()
  if map.world ~= 13 then return end
  if not this.world_13_pending_zones then return end

  local arty_data = enemy_arty.get('arty')
  local zones_to_remove = {}

  for zone_key, zone in pairs(this.world_13_pending_zones) do
    local all_dead = true
    for _, baolei_id in ipairs(zone.baolei_ids) do
      if arty_data[baolei_id] then
        all_dead = false
        break
      end
    end
    if all_dead then
      zones_to_remove[#zones_to_remove + 1] = zone_key
      local surface = zone.surface
      local w = zone.w
      if surface and surface.valid then
        ICWF.cleanup_loot_wagons()
        ICWF.spawn_loot_wagon_on_map(surface, {x = 15, y = w + 20})
        local silo_pos = {x = 0, y = w + 20}
        if surface.can_place_entity{name = 'rocket-silo', position = silo_pos} then
          local silo = surface.create_entity{
            name = 'rocket-silo',
            position = silo_pos,
            force = game.forces.player,
            create_build_effect_smoke = false
          }
          if silo and silo.valid then
            silo.destructible = false
            silo.minable_flag = false
          end
        end
      end
    end
  end

  for _, zone_key in ipairs(zones_to_remove) do
    this.world_13_pending_zones[zone_key] = nil
  end
end

-- 暴露 jixianchengshi / beishuiyizhan 模块给世界模块用
Public.jixianchengshi = jixianchengshi
Public.beishuiyizhan = beishuiyizhan

return Public
