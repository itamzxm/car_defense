local WD = require 'modules.wave_defense.table'
local threat_values = require 'modules.wave_defense.threat_values'
local Event = require 'utils.event'
local BiterRolls = require 'modules.wave_defense.biter_rolls'
local BiterHealthBooster = require 'modules.biter_health_booster_v2'
local math_random = math.random
local WPT = require 'maps.amap.table'

local Public = {}

local function remove_unit(entity)
  local active_biters = WD.get('active_biters')
  local unit_number = entity.unit_number
  if not active_biters[unit_number] then
    return
  end
  local m = 1
  local biter_health_boost_units = BiterHealthBooster.get('biter_health_boost_units')
  if biter_health_boost_units[unit_number] then
    m = 1 / biter_health_boost_units[unit_number][2]
  end
  local active_threat_loss = math.round(threat_values[entity.name] * m, 2)
  local active_biter_threat = WD.get('active_biter_threat')
  WD.set('active_biter_threat', active_biter_threat - active_threat_loss)
  local active_biter_count = WD.get('active_biter_count')
  WD.set('active_biter_count', active_biter_count - 1)
  active_biters[unit_number] = nil

  if active_biter_count <= 0 then
    WD.set('active_biter_count', 0)
  end
  if active_biter_threat <= 0 then
    WD.set('active_biter_threat', 0)
  end
end

local function place_nest_near_unit_group()
  local unit_groups = WD.get('unit_groups')
  local random_group = WD.get('random_group')
  local group = unit_groups[random_group]
  if not group then
    return
  end
  if not group.valid then
    return
  end
  if not group.members then
    return
  end
  if not group.members[1] then
    return
  end
  local unit = group.members[math_random(1, #group.members)]
  if not unit.valid then
    return
  end
  local name = 'biter-spawner'
  if math_random(1, 3) == 1 then
    name = 'spitter-spawner'
  end
  local position = unit.surface.find_non_colliding_position(name, unit.position, 12, 1)
  if not position then
    return
  end
  local r = WD.get('nest_building_density')
  if
  unit.surface.count_entities_filtered(
  {
    type = 'unit-spawner',
    force = unit.force,
    area = {{position.x - r, position.y - r}, {position.x + r, position.y + r}}
  }
) > 0
then
  return
end
local spawner = unit.surface.create_entity({name = name, position = position, force = unit.force})
local nests = WD.get('nests')
nests[#nests + 1] = spawner
unit.surface.create_entity({name = 'blood-explosion-huge', position = position})
unit.surface.create_entity({name = 'blood-explosion-huge', position = unit.position})
remove_unit(unit)
unit.destroy()
local threat = WD.get('threat')
WD.set('threat', threat - threat_values[name])
return true
end

function Public.build_nest()
  local threat = WD.get('threat')
  if threat < 1024 then
    return
  end
  local index = WD.get('index')
  if index == 0 then
    return
  end
  for _ = 1, 2, 1 do
    if place_nest_near_unit_group() then
      return
    end
  end
end

function Public.build_worm()
  local threat = WD.get('threat')
  if threat < 512 then
    return
  end
  local worm_building_chance = WD.get('worm_building_chance')
  if math_random(1, worm_building_chance) ~= 1 then
    return
  end

  local index = WD.get('index')
  if index == 0 then
    return
  end

  local random_group = WD.get('random_group')
  local unit_groups = WD.get('unit_groups')
  local group = unit_groups[random_group]
  if not group then
    return
  end
  if not group.valid then
    return
  end
  if not group.members then
    return
  end
  if not group.members[1] then
    return
  end
  local unit = group.members[math_random(1, #group.members)]
  if not unit.valid then
    return
  end

  local wave_number = WD.get('wave_number')

  local k =game.forces.enemy.evolution_factor*1000
  if k >wave_number then
    wave_number=k
  end
  local position = unit.surface.find_non_colliding_position('assembling-machine-1', unit.position, 8, 1)
  BiterRolls.wave_defense_set_worm_raffle(wave_number)
  local worm = BiterRolls.wave_defense_roll_worm_name()
  if not position then
    return
  end

  local worm_building_density = WD.get('worm_building_density')
  local r = worm_building_density
  if
  unit.surface.count_entities_filtered(
  {
    type = 'turret',
    force = unit.force,
    area = {{position.x - r, position.y - r}, {position.x + r, position.y + r}}
  }
) > 0
then
  return
end
unit.surface.create_entity({name = worm, position = position, force = unit.force})
unit.surface.create_entity({name = 'blood-explosion-huge', position = position})
unit.surface.create_entity({name = 'blood-explosion-huge', position = unit.position})
remove_unit(unit)
unit.destroy()
WD.set('threat', threat - threat_values[worm])
end

local function shred_simple_entities(entity)
  local threat = WD.get('threat')
  if threat < 25000 then
    return
  end
  local simple_entities =
  entity.surface.find_entities_filtered(
  {
    type = 'simple-entity',
    area = {{entity.position.x - 3, entity.position.y - 3}, {entity.position.x + 3, entity.position.y + 3}}
  }
)
if #simple_entities == 0 then
  return
end
if #simple_entities > 1 then
  table.shuffle_table(simple_entities)
end
local r = math.floor(threat * 0.00004)
if r < 1 then
  r = 1
end
local count = math.random(1, r)
--local count = 1
local damage_dealt = 0
for i = 1, count, 1 do
  if not simple_entities[i] then
    break
  end
  if simple_entities[i].valid then
    if simple_entities[i].health then
      damage_dealt = damage_dealt + simple_entities[i].health
      simple_entities[i].die('neutral', simple_entities[i])
    end
  end
end
if damage_dealt == 0 then
  return
end
local simple_entity_shredding_cost_modifier = WD.get('simple_entity_shredding_cost_modifier')
local threat_cost = math.floor(damage_dealt * simple_entity_shredding_cost_modifier)
if threat_cost < 1 then
  threat_cost = 1
end
WD.set('threat', threat - threat_cost)
end

local function spawn_unit_spawner_inhabitants(entity)
  if entity.type ~= 'unit-spawner' then
    return
  end
  local wave_number = WD.get('wave_number')
  local k =game.forces.enemy.evolution_factor*1000
  if k >wave_number then
    wave_number=k
  end
  local count = 32 + math.floor(wave_number * 0.1)
  if count > 64 then
    count = 64
  end

  BiterRolls.wave_defense_set_unit_raffle(wave_number)
--  local unit_group = entity.surface.create_unit_group({position = entity.position, force = 'enemy'})
  for _ = 1, count, 1 do
    local position = {entity.position.x + (-4 + math.random(0, 8)), entity.position.y + (-4 + math.random(0, 8))}
    local biter
    if math.random(1, 4) == 1 then
      biter=entity.surface.create_entity({name = BiterRolls.wave_defense_roll_spitter_name(), position = position, force = 'enemy'})
    else
      biter=  entity.surface.create_entity({name = BiterRolls.wave_defense_roll_biter_name(), position = position, force = 'enemy'})
    end
  --  if biter then
    --  unit_group.add_member(biter)
  --  end
  end

end

local function kill_master(entity)
  if entity.type ~= 'unit-spawner' then
    return
  end
  local wave_number = WD.get('wave_number')
  local k =game.forces.enemy.evolution_factor*1000
  if k >wave_number then
    wave_number=k
  end
  local count = 32 + math.floor(wave_number * 0.1)
  if count > 64 then
    count = 64
  end
  BiterRolls.wave_defense_set_unit_raffle(wave_number)

  local unit_group = entity.surface.create_unit_group({position = entity.position, force = 'enemy'})
  for _ = 1, count, 1 do
    local position = {entity.position.x + (-4 + math.random(0, 8)), entity.position.y + (-4 + math.random(0, 8))}
    local biter
    if math.random(1, 4) == 1 then
      biter=entity.surface.create_entity({name = BiterRolls.wave_defense_roll_spitter_name(), position = position, force = 'enemy'})
    else
      biter=entity.surface.create_entity({name = BiterRolls.wave_defense_roll_biter_name(), position = position, force = 'enemy'})
    end
    if biter then
      biter.ai_settings.allow_destroy_when_commands_fail = true
      biter.ai_settings.allow_try_return_to_spawner = true
      --biter.ai_settings.do_separation = true
      unit_group.add_member(biter)

    end
  end

  if #unit_group.members == 0 then return end
  local target
  local entities = entity.surface.find_entities_filtered{position = entity.position, radius =25, name = "character", force = game.forces.player}

  if #entities == 0 then
    local this=WPT.get()
    if this.tank[this.car_index] then
      target=this.tank[this.car_index]
      --game.print("攻击主车")
    else
      local characters = {}
      local p = game.connected_players
      for _, player in pairs(p) do
        if player.character then
          if player.character.valid then
            if player.character.surface== entity.surface then
              characters[#characters + 1] = player.character
            end
          end
        end
      end
      if #characters ~=0 then
        target=math_random(1, #characters)
        --  game.print("随机全体玩家")
      else
        for k,v in pairs(unit_group.members) do
          v.destroy()
        end
        unit_group.destroy()
        --game.print("摧毁组织")
        return
      end
    end
  else
    target=entities[math.random(#entities)]
  end

  unit_group.set_command(
  {
    type = defines.command.attack_area,
    destination = target.position,
    radius = 8,
    distraction = defines.distraction.by_anything
  }
)

end

local function on_entity_died(event)
  local entity = event.entity

  if not entity.valid then
    return
  end

  local disable_threat_below_zero = WD.get('disable_threat_below_zero')
  local biter_health_boost = BiterHealthBooster.get('biter_health_boost')

  if entity.type == 'unit' then
    --acid_nova(entity)
    if not threat_values[entity.name] then
      return
    end
    if disable_threat_below_zero then
      local threat = WD.get('threat')
      if threat <= 0 then
        WD.set('threat', 0)
        remove_unit(entity)
        return
      end
      WD.set('threat', math.round(threat - threat_values[entity.name] * biter_health_boost, 2))
      remove_unit(entity)
    else
      local threat = WD.get('threat')
      WD.set('threat', math.round(threat - threat_values[entity.name] * biter_health_boost, 2))
      remove_unit(entity)
    end
  else
    if entity.force.index == 2 then
      if entity.health then
        if threat_values[entity.name] then
          local threat = WD.get('threat')
          WD.set('threat', math.round(threat - threat_values[entity.name] * biter_health_boost, 2))
        end
        local cause = event.cause
        if not cause then
          kill_master(entity)
        else
          if cause.last_user then
            local this=WPT.get()
            local  player = cause.last_user
            local index =player.index
            if not this.nest_wegiht[index] then
              this.nest_wegiht[index]=0
            end
            this.nest_wegiht[index]=this.nest_wegiht[index]+1
          end
          if cause.name =="artillery-turret" or cause.name =="artillery-wagon"  then
            local this=WPT.get()
            local unit_number=cause.unit_number
            if not this.water_arty[unit_number] then
              local water_count =entity.surface.count_tiles_filtered{position=cause.position, radius=30, name='water'}
              --game.print(water_count)
              if water_count == 0 then
                this.water_arty[unit_number]=1
              else
                this.water_arty[unit_number]=2
              end
            end

            if this.water_arty[unit_number]==2 then

              kill_master(entity)
            else
              spawn_unit_spawner_inhabitants(entity)

            end
          end


          if cause.name ~="artillery-turret" and cause.name ~="artillery-wagon" then
        if cause.destructible==false then
          kill_master(entity)
        else
            spawn_unit_spawner_inhabitants(entity)
          end
            if cause.valid then
              local this=WPT.get()
              if (cause.name == 'character' and cause.player) then
                local  player = cause.player
                local index =player.index
                if not this.nest_wegiht[index] then
                  this.nest_wegiht[index]=0
                end
                this.nest_wegiht[index]=this.nest_wegiht[index]+1
              end
            end
          end

        end
      end
    end
  end

  if entity.force.index == 3 then
    if event.cause then
      if event.cause.valid then
        if event.cause.force.index == 2 then
          shred_simple_entities(entity)
        end
      end
    end
  end
end

Event.add(defines.events.on_entity_died, on_entity_died)

return Public
