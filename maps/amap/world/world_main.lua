local WPT = require 'maps.amap.table'
local diff = require 'maps.amap.diff'
local world_function = require 'maps.amap.world.world_function'
local World = require 'maps.amap.world.framework'
local Helpers = require 'maps.amap.world.world_helpers'

-- 已迁移到框架的世界模块（按编号顺序追加）
require 'maps.amap.world.worlds.world_01_cave'
require 'maps.amap.world.worlds.world_02_quarter'
require 'maps.amap.world.worlds.world_03_water'
require 'maps.amap.world.worlds.world_06_arena'
require 'maps.amap.world.worlds.world_07_no_ore_no_biter'
require 'maps.amap.world.worlds.world_08_no_ore'
require 'maps.amap.world.worlds.world_09_no_ore_no_biter'
require 'maps.amap.world.worlds.world_10_special_rule'
require 'maps.amap.world.worlds.world_11_jixianchengshi'
require 'maps.amap.world.worlds.world_12_beishuiyizhan'
require 'maps.amap.world.worlds.world_13_train_escape'
require 'maps.amap.world.worlds.world_14_grass_invasion'
require 'maps.amap.world.worlds.world_15_tower_defense'  -- 重新启用（PR #4 合入：事件声明式分发/科技解锁修复/通关奖励等）
require 'maps.amap.world.worlds.world_16_pingfanzhiri'
require 'maps.amap.world.worlds.world_17_grid_war'
require 'maps.amap.world.worlds.world_19_mechanical_canyon'
require 'maps.amap.world.worlds.world_21_lava_heart'
-- 以下独立世界机制文件（粉丝新增，原未接线=孤儿文件）：直接挂在 world/ 下（非 worlds/ 子目录），
-- 需显式 require 才加载。挂载后 world3 钓鱼机制生效。
-- world8 异次元空间机制已随该世界删除而移除（2026-07-31），其 require 注释保留以便回退。
require 'maps.amap.world.word_water_world'
-- world17 网格战争机制（网格 hash 几何 / 填充队列 / 清空奖励 / 堡垒避让）
require 'maps.amap.world.word_grid_war'
-- require 'maps.amap.world.word_yiciyuankongjian'  -- 已禁用：异次元空间世界已删除，机制文件保留但不加载

-- rocks_yield_ore 系列模块（地形生成的依赖）
require "maps.amap.rocks_yield_ore"
require "modules.rocks_broken_paint_tiles"
require "modules.rocks_heal_over_time"
require "modules.rocks_yield_ore_veins"

local function on_chunk_generated(event)

  local surface = event.surface
  local this = WPT.get()
  if not this.active_surface_index or not game.surfaces[this.active_surface_index] then return end
  if surface.name ~= "nauvis" then return end
  if	not(surface.index == game.surfaces[this.active_surface_index].index) then return end

  local left_top_x = event.area.left_top.x
  local left_top_y = event.area.left_top.y

  local seed = surface.map_gen_settings.seed
  local area = event.area
  local set_tiles = surface.set_tiles
  local get_tile = surface.get_tile
  local position

  local map=diff.get()

  if map.world==2 or map.world==7 or map.world==8 or map.world==13 then
    local ziyuan = {}

    local planets = {"vulcanus", "fulgora", "gleba"}
    if map.world == 8 then
        table.insert(planets, "aquilo")
    end

    for _, planet_name in ipairs(planets) do
        Helpers.create_planet_surface(planet_name, this.active_surface_index, ziyuan, map.world)
    end
end

  if map.world == 12 and left_top_y/32 > 2 then
    local this = WPT.get()
    if not this.port_discovered then
      if math.random(1, 100) <= 7 then
        this.ore_sequence_index = this.ore_sequence_index % 6 + 1
        local ore_name = this.ore_sequence[this.ore_sequence_index]
        local ore_total = 750000
        local ore_per_cell = math.floor(ore_total / 1024)
        if ore_name == "crude-oil" then
          for x = 2, 30, 5 do
            for y = 2, 30, 5 do
              local pos = {x = left_top_x + x, y = left_top_y + y}
              if surface.can_place_entity({name = ore_name, position = pos, amount = ore_total}) then
                surface.create_entity({name = ore_name, position = pos, amount = ore_total})
              end
            end
          end
        else
          for x = 0, 31 do
            for y = 0, 31 do
              local pos = {x = left_top_x + x, y = left_top_y + y}
              if surface.can_place_entity({name = ore_name, position = pos, amount = ore_per_cell}) then
                surface.create_entity({name = ore_name, position = pos, amount = ore_per_cell})
              end
            end
          end
        end
        return
      else
        local tiles = {}
        for x = 0, 31 do
          for y = 0, 31 do
            table.insert(tiles, {name = "deepwater", position = {x = left_top_x + x, y = left_top_y + y}})
          end
        end
        surface.set_tiles(tiles)
        return
      end
    end
  end

  -- 野外建筑/石头（ywjz）开关：由世界定义字段 disable_default_rocks 决定，
  -- 取代原先散落在此处的 world ~= 3 and ~= 9 and ... 硬编码排除列表。
  -- 未声明该字段的世界默认生成（保持旧行为）。
  local rocks_disabled = World.get_field(map.world, 'disable_default_rocks')
  local ywjz_dense = (map.world == 6 or map.world == 8)

  for x = 0, 31, 1 do
    for y = 0, 31, 1 do
      position = {x = left_top_x + x, y = left_top_y + y}
      local q =position.x
      local w =position.y
      local maxs =math.abs(q+w)+math.abs(q-w)
      if maxs < 64 then
        Helpers.build_base(surface, maxs, event, position)
      end

      if maxs >= 170 then
        if ywjz_dense then
          Helpers.ywjz(surface, position, 5000, 9999)
        elseif not rocks_disabled then
          Helpers.ywjz(surface, position, 20000, maxs)
        end
      end
    end
  end

  if map.world == 3 then
    local chunk_area = {
      left_top = {x = left_top_x, y = left_top_y},
      right_bottom = {x = left_top_x + 32, y = left_top_y + 32}
    }
    local chunk_center_x = left_top_x + 16
    local chunk_center_y = left_top_y + 16
    local chunk_maxs = math.abs(chunk_center_x + chunk_center_y) + math.abs(chunk_center_x - chunk_center_y)

    if chunk_maxs >= 64  then
      world_function.water(surface, chunk_area, seed)
    end
  end

  if map.world ~= 3 then
    for x = 0, 31, 1 do
      for y = 0, 31, 1 do
        position = {x = left_top_x + x, y = left_top_y + y}
        local q =position.x
        local w =position.y
        local maxs =math.abs(q+w)+math.abs(q-w)

        if maxs >= 64 then
          if map.world == 7 and math.abs(q) >= 130 then
            return
          end
          if map.world == 13 and math.abs(q) >= 130 then
            return
          end

          -- 查询 World 框架（所有世界已注册 terrain_generator，世界 3 除外）
          local world_def = World.get(map.world)
          local generator = world_def and world_def.terrain_generator
          if generator then
            generator(surface, position, seed, get_tile, set_tiles, event, maxs, q, w, x, y,area)
          end
        end
      end
    end  end

  -- 史诗木箱生成已合并到 ywjz 权重体系（weight_epic_box = weight_box）
  -- 由 on_chunk_generated 调用 ywjz 时按权重随机生成，不再单独判断概率
end

local function on_robot_built_tile (event)

  local map=diff.get()
  if map.world ~=3 then return end

  local tile=event.tile

  if tile.name ~="landfill" then return end
  local surface=game.surfaces[event.surface_index]

  local this = WPT.get()
  if game.surfaces[this.active_surface_index]~=surface then return end
  local tiles=event.tiles
  for _,v in pairs(tiles) do
    surface.set_tiles({{name = 'water', position = v.position}}, true)
  end
  game.print({'amap.robot_cannot_landfill'})

  end

local function on_player_built_tile (event)
  local map = diff.get()
  if map.world ~= 3 then return end

  local tile = event.tile
  if tile.name ~= "landfill" then return end

  local surface = game.surfaces[event.surface_index]
  local this = WPT.get()
  if game.surfaces[this.active_surface_index] ~= surface then return end

  local tiles = event.tiles

  local min_x, max_x, min_y, max_y
  for _, v in pairs(tiles) do
    if not min_x then
      min_x, max_x = v.position.x, v.position.x
      min_y, max_y = v.position.y, v.position.y
    else
      min_x = math.min(min_x, v.position.x)
      max_x = math.max(max_x, v.position.x)
      min_y = math.min(min_y, v.position.y)
      max_y = math.max(max_y, v.position.y)
    end
  end

  local padding = 1
  min_x, max_x = min_x - padding, max_x + padding
  min_y, max_y = min_y - padding, max_y + padding

  local has_adjacent_land = false
  local test_entity = 'transport-belt'

  local sample_points = {
    {x = min_x, y = min_y},
    {x = max_x, y = min_y},
    {x = min_x, y = max_y},
    {x = max_x, y = max_y},
    {x = math.floor((min_x + max_x) / 2), y = min_y},
    {x = math.floor((min_x + max_x) / 2), y = max_y},
    {x = min_x, y = math.floor((min_y + max_y) / 2)},
    {x = max_x, y = math.floor((min_y + max_y) / 2)}
  }

  for _, point in ipairs(sample_points) do
    if surface.can_place_entity{name = test_entity, position = point, force = game.forces.neutral} then
      has_adjacent_land = true
      break
    end
  end

  if not has_adjacent_land then
    local player = game.players[event.player_index]
    player.print({'amap.cant_bulid_landfill'})

    for _, v in pairs(tiles) do
      if player.physical_position.x ~= v.position.x or player.physical_position.y ~= v.position.y then
        surface.set_tiles({{name = 'water', position = v.position}}, true)
        player.insert{name = 'landfill', count = 1}
      end
    end
  end
end

local function on_init()
  storage.rocks_yield_ore_maximum_amount = 999
  storage.rocks_yield_ore_base_amount = 100
  storage.rocks_yield_ore_distance_modifier = 0.020
  storage.watery_world_fishes = {}
  for _, prototype in pairs(prototypes.entity) do
    if prototype.type == "fish" then
      table.insert(storage.watery_world_fishes, prototype.name)
    end
  end
end


local Event = require 'utils.event'
Event.on_init(on_init)
Event.on_nth_tick(60 * 5, Helpers.check_world_13_zones)

--Event.add(defines.events.on_player_mined_entity, on_player_mined_entity)
Event.add(defines.events.on_chunk_generated, on_chunk_generated)
--Event.add(defines.events.on_player_built_tile , on_player_built_tile)
--Event.add(defines.events.on_robot_built_tile  , on_robot_built_tile )
Event.add(defines.events.on_built_entity, on_built_entity)
