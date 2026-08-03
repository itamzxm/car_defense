local WD = require 'modules.wave_defense.table'
local threat_values = require 'modules.wave_defense.threat_values'
local Event = require 'utils.event'
local BiterRolls = require 'modules.wave_defense.biter_rolls'
local math_random = math.random
local WPT = require 'maps.amap.table'
local Token = require 'utils.token'
local Task = require 'utils.task'
local BiterClass = require 'maps.amap.biter_class'

-- ============================================================
-- 更新2：过量杀虫惩罚系统
-- 玩家击杀巢穴过快（nest_kills_per_minute >= 25）时触发；每次巢穴生成事件触发一次，
-- 按固定顺序循环施加 5 种惩罚效果之一（fire-sticker→fire-flame→lightning→裂隙→烟雾）。
-- 详见 更新2_过量杀虫惩罚扩展.md
-- ============================================================
local PUNISH_EFFECTS = {
  'fire-sticker', -- 1 点燃贴纸（直接作用于玩家，一次性伤害）
  'fire-flame',   -- 2 火焰（直接作用于玩家，一次性伤害）
  'lightning',    -- 3 闪电雷阵雨（玩家 24m 内随机 K 个地点）
  'fissure',      -- 4 撼地虫裂隙（玩家 24m 内随机 K 个，原生伤害）
  'ash-cloud',    -- 5 撼地虫烟雾（玩家 24m 内随机 K 个，纯视觉）
}

-- 激光科技系数：与虫子科技挂钩（CLAUDE.md 魔法伤害规则）
-- final_damage = base_damage × (ammo_damage_modifier("laser")+1) / (gun_speed_modifier('laser')+1)
local function punish_laser_coeff()
  local enemy = game.forces.enemy
  local dmg = enemy.get_ammo_damage_modifier('laser') + 1
  local spd = enemy.get_gun_speed_modifier('laser') + 1
  if spd <= 0 then spd = 0.01 end -- 防御：避免激光射速被减到 <=0 时除零崩溃
  return dmg / spd
end

-- 确定受罚玩家：优先击杀者（event.cause），回退到生成点附近最近玩家
local function get_punish_target(surface, valid_position, cause)
  local char = nil
  if cause and cause.valid then
    if cause.type == 'character' then
      char = cause
    elseif cause.type == 'player' and cause.character and cause.character.valid then
      char = cause.character
    end
  end
  if not (char and char.valid) then
    local chars = surface.find_entities_filtered({
      position = valid_position, radius = 26, force = 'player', type = 'character'
    })
    if chars and chars[1] and chars[1].valid then
      char = chars[1]
    end
  end
  if not (char and char.valid) then
    return nil
  end
  return char
end

-- 火焰类（fire-sticker / fire-flame）：视觉 + 一次性伤害，直接作用于玩家
local function punish_fire(char, entity_name, base_damage, coeff)
  local surface = char.surface
  local pos = char.position
  if entity_name == 'fire-sticker' then
    surface.create_entity({name = entity_name, position = pos, source = char, target = char, force = 'enemy'})
  else
    surface.create_entity({name = entity_name, position = pos, force = 'enemy'})
  end
  char.damage(base_damage * coeff, 'enemy', 'fire')
end

-- 闪电单道劈击（延迟触发，避免闭包不可序列化）
local punish_lightning_strike_token = Token.register(function(data)
  local surface = game.surfaces[data.surface_index]
  if not surface then return end
  local pos = data.pos
  surface.create_entity({name = 'lightning', position = pos, force = 'enemy'})
  local victims = surface.find_entities_filtered({
    position = pos, radius = data.radius, force = 'player', type = 'character'
  })
  for _, v in pairs(victims) do
    if v.valid then
      v.damage(data.damage, 'enemy', 'electric')
    end
  end
end)

-- 闪电：玩家 24m 内随机 K 个地点，每地点 3s（180 tick）/6 道，每道自写伤害
local function punish_lightning(char, nk, coeff)
  local surface = char.surface
  local center = char.position
  local K = 1 + math.floor((nk - 25) / 25)
  local strike_damage = 150 * coeff
  local radius = 4 -- 单道劈击命中半径（可调）
  for i = 1, K do
    local angle = math_random() * 2 * math.pi
    local dist = math_random() * 24
    local pos = {x = center.x + math.cos(angle) * dist, y = center.y + math.sin(angle) * dist}
    for s = 1, 6 do
      Task.set_timeout_in_ticks((s - 1) * 30, punish_lightning_strike_token, {
        surface_index = surface.index,
        pos = pos,
        damage = strike_damage,
        radius = radius
      })
    end
  end
end

-- 撼地虫裂隙：按 nk 分档，原生裂隙伤害，无需自写
local function punish_fissure(char, nk)
  local surface = char.surface
  local center = char.position
  local K = 1 + math.floor((nk - 25) / 25)
  local name
  if nk <= 99 then
    name = 'small-demolisher-fissure'
  elseif nk <= 199 then
    name = 'medium-demolisher-fissure'
  else
    name = 'big-demolisher-fissure'
  end
  for i = 1, K do
    local angle = math_random() * 2 * math.pi
    local dist = math_random() * 24
    local pos = {x = center.x + math.cos(angle) * dist, y = center.y + math.sin(angle) * dist}
    surface.create_entity({name = name, position = pos, force = 'enemy'})
  end
end

-- 撼地虫烟雾：纯视觉，无伤害
local function punish_ash_cloud(char, nk)
  local surface = char.surface
  local center = char.position
  local K = 1 + math.floor((nk - 25) / 25)
  for i = 1, K do
    local angle = math_random() * 2 * math.pi
    local dist = math_random() * 24
    local pos = {x = center.x + math.cos(angle) * dist, y = center.y + math.sin(angle) * dist}
    surface.create_entity({name = 'small-demolisher-ash-cloud-trail', position = pos, force = 'enemy'})
  end
end

-- 触发惩罚：按固定顺序循环到下一个效果
local function trigger_nest_kill_punish(char, nk)
  local this = WPT.get()
  if not this.punish_cycle_index then
    this.punish_cycle_index = 1
  end
  local idx = this.punish_cycle_index
  this.punish_cycle_index = idx % #PUNISH_EFFECTS + 1

  local coeff = punish_laser_coeff()
  local base_damage = 100 * (1 + math.floor((nk - 25) / 25))
  local effect = PUNISH_EFFECTS[idx]

  if effect == 'fire-sticker' then
    punish_fire(char, 'fire-sticker', base_damage, coeff)
  elseif effect == 'fire-flame' then
    punish_fire(char, 'fire-flame', base_damage, coeff)
  elseif effect == 'lightning' then
    punish_lightning(char, nk, coeff)
  elseif effect == 'fissure' then
    punish_fissure(char, nk)
  elseif effect == 'ash-cloud' then
    punish_ash_cloud(char, nk)
  end
end

local Public = {}
local function more_biter()
  local wave_number = WD.get('wave_number')
  local k = game.forces.enemy.get_evolution_factor() * 1000
  if k > wave_number then
    wave_number = k
  end
  local count = math.floor((32 + math.floor(wave_number * 0.1)) * 0.8)
  if count > 51 then
    count = 51
  end
  -- 直接生成虫类型并加入血量池
  BiterRolls.wave_defense_set_unit_raffle(wave_number)
  for i = 1, count do
    local name = BiterRolls.wave_defense_roll_biter_name()
    if name then
      local category = WD.get_biter_category(name)
      if category then
        WD.add_health_to_pool(name, nil, category)
      end
    end
  end
end

local group_out_time =
Token.register(
function(group)
  if  group and  group.valid then
    for _, entity in pairs(group.members) do
      if entity and entity.valid then
        -- 超时虫子血量加入血量池
        local category = WD.get_biter_category(entity.name)
        if category then
          WD.add_health_to_pool(entity.name, nil, category)
        end
        entity.destroy()
      end
    end
    group.destroy()
  end
end
)

local spawn_batch_units_token

local function attack_nearby_enemies(group, position)
  if not group or not group.valid then
    return
  end
  local nearby_entities = group.surface.find_entities_filtered{position = position, radius = 20, force = game.forces.player, limit=10}
  if #nearby_entities == 0 then
    return
  end
  
  local valid_targets = {}
  for _, entity_obj in pairs(nearby_entities) do
    if entity_obj.valid and entity_obj.health and entity_obj.type ~= "projectile" then
      table.insert(valid_targets, entity_obj)
    end
  end
  
  if #valid_targets == 0 then
    return
  end
  
  local commands = {}
  

  commands[#commands + 1] = {
    type = defines.command.attack_area,
    destination = valid_targets[1].position,
    radius = 16,
    distraction = defines.distraction.by_anything
  }
  
  for i = 1, #valid_targets, 1 do
    commands[#commands + 1] = {
      type = defines.command.attack,
      target = valid_targets[i],
      distraction = defines.distraction.by_anything
    }
  end

  if #commands > 0 and group.valid then
    group.set_command({
      type = defines.command.compound,
      structure_type = defines.compound_command.return_last,
      commands = commands
    })
  end
end

spawn_batch_units_token =
Token.register(
function(data)
  local surface = data.surface
  local valid_position = data.valid_position
  local force = data.force
  local unit_table = data.unit_table
  local group = data.group
  local batch_index = data.batch_index
  local total_batches = data.total_batches
  local wave_number = data.wave_number
  local total_count = data.total_count
  local created_count = data.created_count
  
  if not group or not group.valid then
    return
  end
  
  local batch_size = 12
  local start_index = (batch_index - 1) * batch_size + 1
  local end_index = math.min(batch_index * batch_size, #unit_table)
  
  local created_units = {}
  for i = start_index, end_index do
    if unit_table[i] then
      -- 共享计数器检查
      local can_spawn, category = WD.try_register_biter_spawn(unit_table[i].name)
      if can_spawn then
        local biter = surface.create_entity({
          name = unit_table[i].name,
          position = valid_position,
          force = force,
          quality = unit_table[i].quality
        })
        if biter then
          table.insert(created_units, biter)
        end
      else
        -- 超额，存入血量池
        WD.add_health_to_pool(unit_table[i].name, unit_table[i].quality, category)
      end
    end
  end
  
  local active_biter_count = WD.get('active_biter_count')
  local active_biter_threat = WD.get('active_biter_threat')
  local active_biters = WD.get('active_biters')
  local tick = game.tick

  for _, biter in ipairs(created_units) do
    local nest_kills = WD.get('nest_kills_per_minute')
    if nest_kills >= 25 then
      biter.surface.create_entity({
        name = 'bioflux-speed-regen-sticker',
        position = biter.position,
        target = biter,
        force = force,
        quality="legendary"})
        if math_random(1, 500) <= nest_kills and wave_number < 1250 then
          -- BiterClass.assign_random_class(biter)
        end
    end

    if group and group.valid then
      group.add_member(biter)
    end

    -- 加入 active_biters 管理
    active_biters[biter.unit_number] = {
      entity = biter,
      spawn_tick = tick
    }
    active_biter_count = active_biter_count + 1
    active_biter_threat = active_biter_threat + (threat_values[biter.name] or 0)
    WD.inc_type_counter(biter.name)
  end

  WD.set('active_biters', active_biters)
  WD.set('active_biter_count', active_biter_count)
  WD.set('active_biter_threat', active_biter_threat)
  
  local new_created_count = created_count + #created_units
  
  if batch_index == 1 then
  end
  
  if batch_index < total_batches then
    data.batch_index = batch_index + 1
    data.created_count = new_created_count
    Task.set_timeout_in_ticks(2, spawn_batch_units_token, data)
  else
    if group and group.valid then
      attack_nearby_enemies(group, valid_position)
      Task.set_timeout_in_ticks(60 * 75, group_out_time, group)
    end
  end
end
)
local function remove_unit(entity, skip_revive)
  local active_biters = WD.get('active_biters')
  local unit_number = entity.unit_number
  if not active_biters[unit_number] then
    -- 野生虫：仅血量池复活，不消耗威胁
    if not skip_revive then
      WD.on_managed_biter_death(entity, false)
    end
    return
  end
  
  local active_threat_loss = threat_values[entity.name]
  local active_biter_threat = WD.get('active_biter_threat')
  local active_biter_count = WD.get('active_biter_count')
  
  local new_active_biter_count = active_biter_count - 1
  local new_active_biter_threat = active_biter_threat - active_threat_loss
  
  if new_active_biter_count <= 0 then
    new_active_biter_count = 0
    new_active_biter_threat = 0
  elseif new_active_biter_threat <= 0 then
    new_active_biter_threat = 0
  end
  
  WD.set('active_biter_threat', new_active_biter_threat)
  WD.set('active_biter_count', new_active_biter_count)
  WD.dec_type_counter(entity.name)
  active_biters[unit_number] = nil
  
  -- 受管理虫子：两条复活路径均可
  if not skip_revive then
    WD.on_managed_biter_death(entity, true)
  end
  
  if active_threat_loss>= 64 then 
    if math_random(1, 20) == 1 then
    local position=entity.position
    local entities = entity.surface.find_entities_filtered{position = position, radius = 5,type = 'corpse'}
    if #entities == 0 then return false end
    for _, entity in pairs(entities) do
      
            entity.destroy()
   
    end
  end
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
remove_unit(unit, true)
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

  local k =game.forces.enemy.get_evolution_factor()*1000
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
remove_unit(unit, true)
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
    position = entity.position,
    radius = 3
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
      simple_entities[i].die()
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



local function check_and_update_spawn_throttle()
  local current_time = game.tick
  local spawn_count = WD.get('spawn_unit_spawner_count')
  local spawn_time = WD.get('spawn_unit_spawner_time')
  
  if current_time - spawn_time >= 120 then
    spawn_count = 0
    spawn_time = current_time
  end
  
  if spawn_count >= 10 then
    more_biter()
    return false
  end
  
  spawn_count = spawn_count + 1
  WD.set('spawn_unit_spawner_count', spawn_count)
  WD.set('spawn_unit_spawner_time', spawn_time)
  return true
end

local function get_or_generate_unit_table(count, current_time)
  local cached_unit_table = WD.get('unit_table')
  local cached_time = WD.get('unit_table_time')
  
  if cached_unit_table and next(cached_unit_table) and cached_time and (current_time - cached_time) < 600 then
    return cached_unit_table
  end
  
  local unit_table = BiterRolls.wave_defense_generate_unit_table(count, 0.75, 0.25, 6500)
  WD.set('unit_table', unit_table)
  WD.set('unit_table_time', current_time)
  return unit_table
end


local function spawn_unit_spawner_inhabitants(entity, cause)
  if entity.type ~= 'unit-spawner' then
    return
  end

  if not check_and_update_spawn_throttle() then
    return
  end
  
  local current_time = game.tick
  local wave_number = WD.get('wave_number')
  local k = game.forces.enemy.get_evolution_factor() * 1000
  if k > wave_number then
    wave_number = k
  end
  
  local count = math.floor((32 + math.floor(wave_number * 0.1)) * 0.8)
  if count > 51 then
    count = 51
  end
  
  BiterRolls.wave_defense_set_unit_raffle(wave_number)
  
  local valid_position = entity.surface.find_non_colliding_position('behemoth-biter', entity.position, 15, 1)
  if not valid_position then
    valid_position = entity.position
  end
  
  local group = entity.surface.create_unit_group({position = entity.position, force = entity.force})
  local unit_table = get_or_generate_unit_table(count, current_time)
  
  local batch_size = 12
  local total_batches = math.ceil(count / batch_size)
  
  local flat_unit_table = {}
  local has_quality_mod = script.active_mods['quality'] ~= nil

  for _, unit_info in ipairs(unit_table) do
    table.insert(flat_unit_table, {name = unit_info.unit_name, quality = unit_info.quality_name})
  end
  
  local data = {
    surface = entity.surface,
    valid_position = valid_position,
    force = 'enemy',
    unit_table = flat_unit_table,
    group = group,
    batch_index = 1,
    total_batches = total_batches,
    wave_number = wave_number,
    total_count = #flat_unit_table,
    created_count = 0
  }
  
  -- 过量杀虫惩罚（更新2）：每次巢穴生成事件触发一次
  local nk = WD.get('nest_kills_per_minute')
  if nk >= 25 then
    -- 初始 20%，每多杀 1 个虫巢 +1%，nk=80 时封顶 100%
    local over = nk - 25
    local chance = 0.2 + over * 0.01
    if chance > 1 then chance = 1 end
    if math_random() <= chance then
      local target = get_punish_target(entity.surface, valid_position, cause)
      if target then
        trigger_nest_kill_punish(target, nk)
      end
    end
  end

  Task.set_timeout_in_ticks(0, spawn_batch_units_token, data)
end



local function on_entity_died(event)
    local entity = event.entity

    if not entity.valid then
        return
    end

    if entity.force ~= game.forces.enemy then
        return
    end

    if entity.surface ~= game.surfaces['nauvis'] then
        return
    end
    
    local disable_threat_below_zero = WD.get('disable_threat_below_zero')

    if entity.type == 'unit' or entity.type == 'spider-unit' then
        -- 处理普通虫子死亡
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
            WD.set('threat', threat - threat_values[entity.name])
            remove_unit(entity)
        else
            local threat = WD.get('threat')
            WD.set('threat', threat - threat_values[entity.name])
            remove_unit(entity)
        end
    else
        -- 处理非 unit 实体（如巢穴 Spawner）
        if entity.health and entity.type == 'unit-spawner' then
             local nest_kills = WD.get('nest_kills_per_minute')
              WD.set('nest_kills_per_minute', nest_kills + 1)
            if threat_values[entity.name] then
                local threat = WD.get('threat')
                WD.set('threat', threat - threat_values[entity.name])
            end
            
            local cause = event.cause
            if not cause then
                more_biter()
            else
                local dx = entity.position.x - cause.position.x
                local dy = entity.position.y - cause.position.y
                local dist = dx * dx + dy * dy
                if dist <= 62500 then 
                    spawn_unit_spawner_inhabitants(entity, cause)
                 
                else 
                    more_biter()
                end
            end
        end

        -- 处理特殊 force 的逻辑
        if entity.force.index == 3 then
            if event.cause then
                if event.cause.valid then
                    if event.cause.force.index == 2 then
                        shred_simple_entities(entity)
                    end
                end
            end
        end
    end -- 这里闭合了 if entity.type == 'unit' 的 else
end -- 这里闭合了 function on_entity_died



Event.add(defines.events.on_entity_died, on_entity_died)

local function reset_nest_kills_timer()
    local nest_kills = WD.get('nest_kills_per_minute')
    local new_value = nest_kills - 4
    if new_value < 0 then new_value = 0 end
    WD.set('nest_kills_per_minute', new_value)
end

Event.on_nth_tick(600, reset_nest_kills_timer)

return Public
