local Event = require 'utils.event'
local WPT = require 'maps.amap.table'
local WD = require 'modules.wave_defense.table'
local BiterRolls = require 'modules.wave_defense.biter_rolls'
local Token = require 'utils.token'
local Task = require 'utils.task'

local BiterClass = require 'maps.amap.biter_class'
local Instance = require 'maps.amap.instance.instance'  -- 副本 surface 隔离
local arty = require 'maps.amap.enemy_arty'
local entity_types = {
  ['unit'] = true,
  ['turret'] = true,
  ['unit-spawner'] = true,
  ['land-mine'] = true,
  ['spider-unit'] = true
}

-- 数量增长系数 bonus：count = 1 + floor(min(wave,4000) / bonus)
-- 现存 8 个永驻亡语系数保持不变（800 波后行为不变）
-- 新增 5 个限时亡语按“市场价 × 5”推算（见 更新1_虫子亡语重构.md）
local spawn_bonus = {
  ['rocket'] = {bonus = 500},                 -- 未使用（保留以防引用）
  ['explosive-rocket'] = {bonus = 600},
  ['destroyer-capsule'] = {bonus = 900},
  ['gun-turret'] = {bonus = 700},

  ['shachong'] = {bonus = 700},
  ['distractor-capsule'] = {bonus = 150},     -- 新亡语：市场价 30 × 5
  ['laser-turret'] = {bonus = 550},
  ['land-mine'] = {bonus = 1500},
  -- 新增 5 个限时亡语（100-800 波区间，退场波次 = min(7×bonus, 800)）
  ['defender-capsule'] = {bonus = 50},        -- 锚点：市场价 10 × 5，退场 350
  ['poison-capsule'] = {bonus = 250},         -- 市场价 50 × 5，退场 800
  ['cluster-grenade'] = {bonus = 450},        -- 市场价 90 × 5（保持不调整），退场 800
}

local quality_upgrades = {
  { name = "legendary", base_chance = 0.005 },
  { name = "epic",      base_chance = 0.015 },
  { name = "rare",      base_chance = 0.025 },
  { name = "uncommon",  base_chance = 0.05 } 
}

local function select_random_quality(quality_raffle_cache, total_quality_weight, total_quality_chance)
    if script.active_mods['quality'] == nil or #quality_raffle_cache == 0 then
        return nil
    end
    
    if math.random() > total_quality_chance then
        return nil
    end
    
    if total_quality_weight <= 0 then
        return nil
    end
    
    local r = math.random() * total_quality_weight
    local current_weight = 0
    
    for _, item in ipairs(quality_raffle_cache) do
        current_weight = current_weight + item.weight
        if r <= current_weight then
            return item.name
        end
    end
    
    return #quality_raffle_cache > 0 and quality_raffle_cache[#quality_raffle_cache].name or nil
end

local function calculate_quality_raffle(wave_number)
    if wave_number < 300 then
        return {}, 0, 0
    end
    
    local this = WPT.get()
    local current_tick = game.tick
    
    if this.quality_raffle_cache_tick and current_tick - this.quality_raffle_cache_tick < 6000 then
        return this.quality_raffle_cache, this.quality_total_weight, this.quality_total_chance
    end
    
    local quality_upgrades = { 
        { name = "legendary", base_chance = 0.005 },
        { name = "epic",      base_chance = 0.015 },
        { name = "rare",      base_chance = 0.025 },
        { name = "uncommon",  base_chance = 0.05 } 
    }
    
    local progress = math.min((wave_number - 300) / (3000 - 300), 1)
    local total_quality_chance = progress * 1.0
    
    if total_quality_chance <= 0 then
        this.quality_raffle_cache = {}
        this.quality_total_weight = 0
        this.quality_total_chance = 0
        this.quality_raffle_cache_tick = current_tick
        return {}, 0, 0
    end
    
    local decay_progress = 0
    if wave_number >= 3000 then
        decay_progress = math.min((wave_number - 3000) / (6000 - 3000), 1)
    end
    
    local quality_raffle_cache = {}
    local total_quality_weight = 0
    local base_total = 0.005 + 0.015 + 0.025 + 0.05
    
    for _, item in ipairs(quality_upgrades) do
        local scaled_chance = (item.base_chance / base_total) * total_quality_chance
        quality_raffle_cache[item.name] = scaled_chance
    end
    
    if decay_progress > 0 then
        local transferable_qualities = {"epic", "rare", "uncommon"}
        local total_transfer = 0
        
        for _, name in ipairs(transferable_qualities) do
            local transfer_amount = quality_raffle_cache[name] * decay_progress
            quality_raffle_cache[name] = quality_raffle_cache[name] - transfer_amount
            total_transfer = total_transfer + transfer_amount
        end
        
        quality_raffle_cache["legendary"] = quality_raffle_cache["legendary"] + total_transfer
    end
    
    for name, chance in pairs(quality_raffle_cache) do
        table.insert(quality_raffle_cache, {name = name, weight = chance})
        total_quality_weight = total_quality_weight + chance
    end
    
    this.quality_raffle_cache = quality_raffle_cache
    this.quality_total_weight = total_quality_weight
    this.quality_total_chance = total_quality_chance
    this.quality_raffle_cache_tick = current_tick
    
    return quality_raffle_cache, total_quality_weight, total_quality_chance
end

local function select_quality_by_chance()
  if not script.active_mods['quality'] then
    return nil
  end
  
  local wave_number = WD.get('wave_number')
  if wave_number < 300 then
    return nil
  end
  
  local quality_raffle_cache, total_quality_weight, total_quality_chance = calculate_quality_raffle(wave_number)
  
  if total_quality_chance <= 0 then
    return nil
  end
  
  return select_random_quality(quality_raffle_cache, total_quality_weight, total_quality_chance)
end

local function get_worm_name(wave_number)
  if wave_number >= 800 then return 'behemoth-worm-turret' end
  if wave_number >= 400 then return 'big-worm-turret' end
  if wave_number >= 200 then return 'medium-worm-turret' end
  return 'small-worm-turret'
end

local function create_entity_params(name, position, surface, target, quality)
  return {
    name = name,
    position = position,
    force = 'enemy',
    source = position,
    target = target,
    speed = 0.3,
    move_stuck_players = true,
    quality = quality
  }
end

local do_die = Token.register(
  function(data)
    local position = data.position
    local surface = data.surface
    local source = data.source
    local name = data.name
    local should_offset = data.change
    local this = WPT.get()
    
    if should_offset and name ~= 'biter-spawner' then
      source = {
        x = source.x + math.random(-5, 5),
        y = source.y + math.random(-5, 5)
      }
    end
    
    local spawn_multiple_biters = false
    
    if name == 'shachong' then
      local wave_number = WD.get('wave_number')
      name = get_worm_name(wave_number)
    end
    
    local selected_quality = select_quality_by_chance()
    local e
    
    if not spawn_multiple_biters then
      e = surface.create_entity(create_entity_params(name, source, surface, position, selected_quality))
    else
      for i = 1, 32 do
        local quality = (selected_quality and i == 1) and selected_quality or nil
        e = surface.create_entity(create_entity_params('behemoth-biter', source, surface, position, quality))
      end
    end
    
    if e.name == 'gun-turret' then
      local ammo_name = arty.get_ammo()
      e.insert { name = ammo_name, count = 200 }
    end
    
    if e.name == 'laser-turret' then
      arty.add_laser(e)
    end
    
    if e.name == 'biter-spawner' then
      e.destructible = false
      this.biter_wudi[#this.biter_wudi + 1] = e
    end
  end
)

-- 亡语定义表（顺序即轮转顺序）。
-- [1]=名称, [2]=是否建筑(影响落点逻辑), [3]=出场波次, [4]=退场波次(math.huge=永驻)
-- 现存 8 个永驻亡语出场/退场/bonus 行为完全不变；新增 4 个限时亡语保持原有出场退场波次
local death_rattles = {
  {'biter-spawner',     true,  800, math.huge},
  {'shachong',          true,  800, math.huge},
  {'land-mine',         true,  800, math.huge},
  {'gun-turret',        true,  800, math.huge},
  {'laser-turret',      true,  800, math.huge},
  {'explosive-rocket',  false, 800, math.huge},
  {'destroyer-capsule', false, 800, math.huge},
  {'slowdown-capsule',  false, 800, math.huge},
  -- 新增 4 个限时亡语（朝击杀者方向丢出）
  {'defender-capsule',  false, 100, 350},   -- 市场价10×5=bonus50，7×50=350 达峰值8提前退场
  {'distractor-capsule',false, 250, 800},   -- 市场价30×5=bonus150，受800上限退场
  {'poison-capsule',    false, 400, 800},   -- 市场价50×5=bonus250，受800上限退场
  {'cluster-grenade',   false, 600, 800},   -- 市场价90×5=bonus450，受800上限退场
}

local function get_random_spawn_category()
  local this = WPT.get()
  if not this.spawn_order_index then
    this.spawn_order_index = 1
  end

  local wave_number = WD.get('wave_number')
  local total = #death_rattles
  local idx = this.spawn_order_index
  local scanned = 0

  -- 在轮转顺序中向前扫描，跳过当前波次窗口外（未出场/已退场）的亡语
  while scanned < total do
    local def = death_rattles[idx]
    local next_idx = idx % total + 1

    if wave_number >= def[3] and wave_number <= def[4] then
      this.spawn_order_index = next_idx
      return {def[1]}, def[2]
    end

    idx = next_idx
    scanned = scanned + 1
  end

  -- 兜底：理论上永驻亡语始终在场，不会走到这里
  local def = death_rattles[1]
  this.spawn_order_index = 2
  return {def[1]}, def[2]
end

local function loaded_biters(entity, cause, count)

  if not entity or not entity.valid then
    return
  end


  local position
  
  if cause and cause.valid then
    position = cause.position
  else
    position = {
      x = entity.position.x + math.random(-5, 5),
      y = entity.position.y + math.random(-5, 5)
    }
  end

  local category_list, is_building = get_random_spawn_category()
  local name = category_list[1]
  
  if is_building then
    if cause and cause.valid then
      local dx = cause.position.x - entity.position.x
      local dy = cause.position.y - entity.position.y
      local distance = math.sqrt(dx * dx + dy * dy)
      
      if distance > 18 then
        local offset = math.min(distance, 3)
        position = {
          x = entity.position.x + (dx / distance) * offset,
          y = entity.position.y + (dy / distance) * offset
        }
      else
        position = entity.position
      end
    else
      position = entity.position
    end
  end

  if not count or count ==0  then
    local wave_number = math.min(WD.get('wave_number'), 4000)
    count = 1
    if spawn_bonus[name] then
      count = 1 + math.floor(wave_number / spawn_bonus[name].bonus)
    end
  end

  local this = WPT.get()
  for i = 1, count do
    this.biter_death_queue[#this.biter_death_queue + 1] = {
      position = position,
      surface = entity.surface,
      source = entity.position,
      name = name,
      change = is_building
    }
  end
end

local function process_death_queue()
  local this = WPT.get()
  if #this.biter_death_queue == 0 then
    return
  end

  local data = this.biter_death_queue[1]
  table.remove(this.biter_death_queue, 1)
  
  local position = data.position
  local surface = data.surface
  local source = data.source
  local name = data.name
  local should_offset = data.change
  local this_local = this
  
  if should_offset and name ~= 'biter-spawner' then
    source = {
      x = source.x + math.random(-5, 5),
      y = source.y + math.random(-5, 5)
    }
  end
  
  local spawn_multiple_biters = false
  
  if name == 'shachong' then
    local wave_number = WD.get('wave_number')
    name = get_worm_name(wave_number)
  end
  
  local selected_quality = select_quality_by_chance()
  local e
  
  if not spawn_multiple_biters then
    e = surface.create_entity(create_entity_params(name, source, surface, position, selected_quality))
  else
    for i = 1, 32 do
      local quality = (selected_quality and i == 1) and selected_quality or nil
      e = surface.create_entity(create_entity_params('behemoth-biter', source, surface, position, quality))
    end
  end
  
  if e and e.valid then
    if e.name == 'gun-turret' then
      local ammo_name = arty.get_ammo()
      e.insert { name = ammo_name, count = 200 }
    end
    
    if e.name == 'laser-turret' then
      arty.add_laser(e)
    end
    
    if e.name == 'biter-spawner' then
      e.destructible = false
      this_local.biter_wudi[#this_local.biter_wudi + 1] = e
    end
  end
end

local on_entity_died = function(event)
  local entity = event.entity
  if not (entity and entity.valid) then
    return
  end

  -- 副本隔离：副本 surface 上的虫子死亡不触发主世界亡语刷怪逻辑
  -- （否则高波时会在 30x30 的竞技场内刷出 behemoth-biter / cluster-grenade 等强怪秒杀玩家）
  if entity.surface and Instance.is_dungeon_surface(entity.surface.name) then
    return
  end

  local unit_number = entity.unit_number
    local biter_class_data = BiterClass.get()
    if biter_class_data.suicide_biter_units[unit_number] then
      loaded_biters(entity, event.cause, biter_class_data.suicide_biter_units[unit_number])
      biter_class_data.suicide_biter_units[unit_number] = nil
      return
    end
  
  if entity.force.index == game.forces.player.index then
    return
  end

  if not entity_types[entity.type] then
    return
  end

  if entity.name == 'land-mine' then

    loaded_biters(entity, event.cause)
    return
  end

  local wave_number = WD.get('wave_number')
  if wave_number < 800 then return end
  
  local k = wave_number * 0.002 - 1
  if k >= 3 then k = 3 end
  k = 1
  if wave_number >= 1600 then
    k = 2
  end
  
  if math.random(1, 100) <= k then
    loaded_biters(entity, event.cause)
  end
end

local no_wudi = function()
  local this = WPT.get()
  local i = 1
  while i <= #this.biter_wudi do
    local e = this.biter_wudi[i]
    if e and e.valid then
      e.destructible = true
      table.remove(this.biter_wudi, i)
    else
      i = i + 1
    end
  end
end
    
Event.on_nth_tick(480, no_wudi)
Event.on_nth_tick(1, process_death_queue)
Event.add(defines.events.on_entity_died, on_entity_died)