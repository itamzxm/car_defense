local Global = require 'utils.global'
local surface_name = 'amap'
local Reset = require 'maps.amap.soft_reset'
local diff=require 'maps.amap.diff'
local Event = require 'utils.event'
local WorldTable = require 'maps.amap.world.world_table'
local World = require 'maps.amap.world.framework'  -- 世界框架
local Public = {}

local this = {
    active_surface_index = nil,
    surface_name = surface_name,
}

Global.register(
    this,
    function(tbl)
        this = tbl
    end
)

local starting_items = {
  ['submachine-gun'] = 1,
  ['firearm-magazine'] = 30,
  ['wood'] = 16,
  ['car']=1,
}


function Public.create_yiciyuan_surface()
   local map_gen_settings
  if script.active_mods["space-age"] then
    map_gen_settings = game.planets["nauvis"].prototype.map_gen_settings
  end
        map_gen_settings['seed'] = math.random(10000, 99999)
        map_gen_settings['starting_area'] = 1
        map_gen_settings['default_enable_all'] = true
        map_gen_settings['water'] = 1


  local no_biter={
    ["coal"] = {frequency = "1", size = "1", richness = "1"},
    ["stone"] = {frequency = "1", size = "1", richness = "1"},
    ["copper-ore"] = {frequency = "1", size = "1",richness = "1"},
    ["iron-ore"] = {frequency ="1", size = "1", richness = "1"},
    ["uranium-ore"] = {frequency ="1", size = "1", richness = "1"},
    ["crude-oil"] = {frequency = "1", size = "1", richness = "1"},
    ["trees"] = {frequency = "1", size = "1", richness = "1"},
    ["enemy-base"] = {frequency = "0", size = "0", richness = "0"},
}

 
map_gen_settings.autoplace_controls =no_biter

if not this.yiciyuan_count then
  this.yiciyuan_count = 0
end
if not this.old_name then
  this.old_name = 'yiciyuan'
end
this.yiciyuan_count = this.yiciyuan_count + 1

local new_surface = game.create_surface(this.old_name .. '_' .. tostring(this.yiciyuan_count), map_gen_settings)

 return new_surface
end
 
 
function Public.create_surface()
  local map=diff.get()
  local surface_configs = WorldTable.get('surface_configs')
  local map_gen_settings={}
  --检测是否加载了太空时代mod

   if script.active_mods["space-age"] then
    -- World 框架优先：查 base_planet；fallback：world 14 硬编码 gleba
    local base_planet = World.get_field(map.world, 'base_planet')
    if base_planet == nil and map.world == 14 then
      base_planet = 'gleba'
    end
    if base_planet and base_planet ~= 'nauvis' then
      map_gen_settings = game.planets[base_planet].prototype.map_gen_settings
    else
      map_gen_settings = game.planets["nauvis"].prototype.map_gen_settings
    end
  end
        map_gen_settings['seed'] = math.random(1, 4294967295)
        map_gen_settings['starting_area'] = 1.4
        map_gen_settings['default_enable_all'] = true
        map_gen_settings['water'] = 0.4


    -- 应用世界特定的地图生成设置
    local world_specific_settings = World.get_field(map.world, 'map_settings')
    if world_specific_settings then
      for key, value in pairs(world_specific_settings) do
        map_gen_settings[key] = value
      end
    end


	-- 从world_table获取对应世界的地表配置（合并而非替换，保留星球默认设置）
	local world_config_name = World.get_field(map.world, 'surface_config_name')
	local config_to_apply = nil
	if world_config_name and surface_configs[world_config_name] then
		config_to_apply = surface_configs[world_config_name]
	else
		config_to_apply = surface_configs.cave
	end
	for resource, settings in pairs(config_to_apply) do
		map_gen_settings.autoplace_controls[resource] = settings
	end

    
  this.active_surface_index = Reset.soft_reset_map(game.surfaces['nauvis'], map_gen_settings, starting_items).index

    return this.active_surface_index
end

function Public.get_surface_name()
    return this.surface_name
end

function Public.get(key)
    if key then
        return this[key]
    else
        return this
    end
end

return Public
