local Public = require 'modules.rpg.table'
local Task = require 'utils.task'
local Gui = require 'utils.gui'
local Color = require 'utils.color_presets'
local Token = require 'utils.token'
local Alert = require 'utils.alert'
local WPT = require 'maps.amap.table'
local tianfu_table=require 'maps.amap.tianfu_table'
local BiterPets = require 'maps.amap.biter_pets'
local EntityCache = require 'maps.amap.entity_cache'

local level_up_floating_text_color = {0, 205, 0}
local visuals_delay = Public.visuals_delay
local xp_floating_text_color = Public.xp_floating_text_color
local experience_levels = Public.experience_levels
local points_per_level = Public.points_per_level
local settings_level = Public.gui_settings_levels
local floor = math.floor

local COEFF_REG = {1, 1.2, 1.4, 1.6, 1.8}

local round = math.round
local abs = math.abs

--RPG Frames
local main_frame_name = Public.main_frame_name
local spell_gui_frame_name = Public.spell_gui_frame_name


    local function create_damage_floating_text(target_entity, damage_amount, damage_type, player)
    

    -- 根据伤害类型选择颜色
    local color = {r = 1, g = 0.5, b = 0} -- 橙色

    
    -- 在目标位置上方显示伤害数值
    local text_position = {
        x = target_entity.position.x,
        y = target_entity.position.y - 1.5
    }
    
    -- 创建漂浮文本
    player.create_local_flying_text({
        text = tostring(math.floor(damage_amount)),
        position = text_position,
        color = color,
        time_to_live = 60, -- 1秒
        speed = 1.5
    })
end

local function deal_damage_with_floating_text(target_entity, player, damage_amount, damage_type)
    if type(damage_amount) ~= 'number' or damage_amount <= 0 then
        return false
    end
    if not target_entity or not target_entity.valid then
        return false
    end
    local this=WPT.get()
    local damage_multiplier = this.damage_multiplier or 1
    local final_damage = math.floor(damage_amount * damage_multiplier * 1.2)
    damage_type = damage_type or 'explosion'
    create_damage_floating_text(target_entity, final_damage, damage_type, player)
    target_entity.damage(final_damage, 'player', damage_type, player.character)
 
    return true
end
local car_name={
  ["car"]=true,
  ["tank"]=true,
  ["spidertron"]=true,
  ["wood"]=true,
}
 
local goal = {'unit', 'turret', 'unit-spawner','combat-robot','spider-leg','spider-unit'}
local t = {

  ['small-biter'] = 1,
  ['small-spitter'] = 2,
  ['small-worm-turret'] = 32,
  ['medium-biter'] = 8,
  ['medium-spitter'] = 8,
  ['medium-worm-turret'] = 64,
  ['big-biter'] = 32,
  ['big-spitter'] = 32,
      ['big-worm-turret'] = 128,
      ['behemoth-biter'] = 128,
      ['behemoth-spitter'] = 128,
      ['behemoth-worm-turret'] = 256,
      ['biter-spawner'] = 320,
  ['spitter-spawner'] = 320,
  }

local function unstuck_player(index)
  local player = game.get_player(index)
  local surface = player.physical_surface
  if player.physical_surface.name ~= 'nauvis' then return end
  local position = surface.find_non_colliding_position('character', player.physical_position, 32, 0.5)
  if not position then
    return
  end
  player.teleport(position, surface)
end

local lowdowm_1 =
Token.register(
function(player)
  Public.update_player_stats(player)
end
)

-- 以下技能函数已迁移至 spells.lua：jx、ssz、lyly、huo_dun、shui_long_dan、ufo、jgq、
-- lightning_chain、biter_special_forces、ch、advanced_fishing、wudi_turret、
-- xiao_jingling、cleanup_fairy_spirits、trigger_all_fairy_lightning、
-- huanxing_huoshan_penfa、leizhenyu、diankuang
-- 相关 Token（kill_forces/kill_turret/active_lava_burst_task/leizhenyu_work/
-- diankuang_self_loss_token/diankuang_burst_token）也已迁移至 spells.lua













local desync =
Token.register(
function(data)
  local entity = data.entity
  if not entity or not entity.valid then
    return
  end
  local surface = data.surface
  local fake_shooter = surface.create_entity({name = 'character', position = entity.position, force = 'enemy'})
  for i = 1, 3 do
    surface.create_entity(
    {
      name = 'explosive-rocket',
      position = entity.position,
      force = 'player',
      speed = 1,
      max_range = 1,
      target = entity,
      source = fake_shooter
    }
  )
end
if fake_shooter and fake_shooter.valid then
  fake_shooter.destroy()
end
end
)

local function create_healthbar(player, size)
  return rendering.draw_sprite(
  {
    sprite = 'virtual-signal/signal-white',
    tint = Color.green,
    x_scale = size * 8,
    y_scale = size - 0.2,
    render_layer = 'light-effect',
    target =
            {
                entity = player.character,
                offset = { 0, -2.5 },
            },
    surface = player.physical_surface
  }
)
end

local function create_manabar(player, size)
  return rendering.draw_sprite(
  {
    sprite = 'virtual-signal/signal-white',
    tint = Color.blue,
    x_scale = size * 8,
    y_scale = size - 0.2,
    render_layer = 'light-effect',
       target =
            {
                entity = player.character,
                offset = { 0, -2 },
            },
    surface = player.physical_surface
  }
)
end

local function set_bar(min, max, id, mana)
  if not id or not id.valid then
    return
  end
  local m = 0
  if max > 0 then
    m = min / max
  end
  if min >= max then min = max end
  local x_scale = id.y_scale * 8
  id.x_scale = x_scale * m
  if not mana then
    id.color = {math.floor(255 - 255 * m), math.floor(200 * m), 0}
  end
end

local function level_up(player)
  local rpg_t = Public.get_value_from_player(player.index)
  local names = Public.auto_allocate_nodes_func

  local distribute_points_gain = 0
  for i = rpg_t.level + 1, #experience_levels, 1 do
    if rpg_t.xp > experience_levels[i] then
      rpg_t.level = i
      distribute_points_gain = distribute_points_gain + points_per_level
    else
      break
    end
  end
  if distribute_points_gain == 0 then
    return
  end


  -- automatically enable one_punch and stone_path,
  -- but do so only once.
  if rpg_t.level >= settings_level['one_punch_label'] then
    if not rpg_t.auto_toggle_features.one_punch then
      rpg_t.auto_toggle_features.one_punch = true
      rpg_t.one_punch = true
    end
  end
  if rpg_t.level >= settings_level['stone_path_label'] then
    if not rpg_t.auto_toggle_features.stone_path then
      rpg_t.auto_toggle_features.stone_path = true
      rpg_t.stone_path = true
    end
  end

  Public.draw_level_text(player)
  rpg_t.points_left = rpg_t.points_left + distribute_points_gain
  if rpg_t.allocate_index ~= 1 then
    local node = rpg_t.allocate_index
    local index = names[node]:lower()
    rpg_t[index] = rpg_t[index] + distribute_points_gain
    rpg_t.points_left = rpg_t.points_left - distribute_points_gain
    if not rpg_t.reset then
      rpg_t.total = rpg_t.total + distribute_points_gain
    end
    Public.update_player_stats(player)
  else
    Public.update_char_button(player)
  end
  if player.gui.screen[main_frame_name] then
    Public.toggle(player, true)
  end

  Public.level_up_effects(player)
end

local function add_to_global_pool(amount, personal_tax)
  local rpg_extra = Public.get('rpg_extra')

  if not rpg_extra.global_pool then
    return
  end
  local fee
  if personal_tax then
    fee = amount * rpg_extra.personal_tax_rate
  else
    fee = amount * 0.3
  end

  rpg_extra.global_pool = round(rpg_extra.global_pool + fee, 8)
  return amount - fee
end

local repair_buildings =
Token.register(
function(data)
  local entity = data.entity
  if entity and entity.valid then
    local rng = 0.1
    if math.random(1, 5) == 1 then
      rng = 0.2
    elseif math.random(1, 8) == 1 then
      rng = 0.4
    end
    local to_heal = entity.max_health * rng
    if entity.health and to_heal then
      entity.health = entity.health + to_heal
    end
  end
end
)

function Public.repair_aoe(player, position)
  local entities = player.physical_surface.find_entities_filtered({force = player.force, area = {{position.x - 8, position.y - 8}, {position.x + 8, position.y + 8}}})
  local count = 0
  for i = 1, #entities do
    local e = entities[i]
    local car= false 
    if car_name[e.name] then
      car = true
    end
    if e.max_health ~= e.health and car==false  then
      count = count + 1
      Task.set_timeout_in_ticks(10, repair_buildings, {entity = e})
    end
  end
  return count
end
function Public.validate_player(player)
  if not player then
    return false
  end
  if not player.valid then
    return false
  end
  if not player.character then
    return false
  end
  if not player.connected then
    return false
  end
  if not game.players[player.index] then
    return false
  end
  return true
end

function Public.remove_mana(player, mana_to_remove)
  local rpg_extra = Public.get('rpg_extra')
  local rpg_t = Public.get_value_from_player(player.index)
  if not rpg_extra.enable_mana then
    return
  end

  if not mana_to_remove then
    return
  end

  mana_to_remove = floor(mana_to_remove)

  if not rpg_t then
    return
  end

  if rpg_t.debug_mode then
    rpg_t.mana = 9999
    return
  end

  if player.gui.screen[main_frame_name] then
    local f = player.gui.screen[main_frame_name]
    local data = Gui.get_data(f)
    if data.mana and data.mana.valid then
      data.mana.caption = rpg_t.mana
    end
  end

  rpg_t.mana = rpg_t.mana - mana_to_remove

  if rpg_t.mana < 0 then
    rpg_t.mana = 0
    return
  end

  if player.gui.screen[spell_gui_frame_name] then
    local f = player.gui.screen[spell_gui_frame_name]
    if f['spell_table'] then
      if f['spell_table']['mana'] then
        f['spell_table']['mana'].caption = math.floor(rpg_t.mana)
      end
      if f['spell_table']['maxmana'] then
        f['spell_table']['maxmana'].caption = math.floor(rpg_t.mana_max)
      end
    end
  end
end

function Public.update_mana(player)
  local rpg_extra = Public.get('rpg_extra')
  local rpg_t = Public.get_value_from_player(player.index)
  if not rpg_extra.enable_mana then
    return
  end

  if not rpg_t then
    return
  end

  if rpg_t.mana>= rpg_t.mana_max then 
    rpg_t.mana = rpg_t.mana_max
  end

  if player.gui.screen[main_frame_name] then
    local f = player.gui.screen[main_frame_name]
    local data = Gui.get_data(f)
    if data.mana and data.mana.valid then
      data.mana.caption = rpg_t.mana
    end
  end
  if player.gui.screen[spell_gui_frame_name] then
    local f = player.gui.screen[spell_gui_frame_name]
    if f['spell_table'] then
      if f['spell_table']['mana'] then
        f['spell_table']['mana'].caption = math.floor(rpg_t.mana)
      end
      if f['spell_table']['maxmana'] then
        f['spell_table']['maxmana'].caption = math.floor(rpg_t.mana_max)
      end
    end
  end

  if rpg_t.mana < 1 then
    return
  end
  if rpg_extra.enable_health_and_mana_bars then
    if rpg_t.show_bars then
      if player.character and player.character.valid then
        if not rpg_t.mana_bar or not rpg_t.mana_bar.valid then
          rpg_t.mana_bar = create_manabar(player, 0.5)
        end
        set_bar(rpg_t.mana, rpg_t.mana_max, rpg_t.mana_bar, true)
      end
    else
      if rpg_t.mana_bar and rpg_t.mana_bar.valid then
          rpg_t.mana_bar.destroy()
        end
    end
  end
end

function Public.reward_mana(player, mana_to_add)
  local rpg_extra = Public.get('rpg_extra')
  local rpg_t = Public.get_value_from_player(player.index)
  if not rpg_extra.enable_mana then
    return
  end

  if not mana_to_add then
    return
  end

  mana_to_add = floor(mana_to_add)

  if not rpg_t then
    return
  end

  if player.gui.screen[main_frame_name] then
    local f = player.gui.screen[main_frame_name]
    local data = Gui.get_data(f)
    if data.mana and data.mana.valid then
      data.mana.caption = rpg_t.mana
    end
  end
  if player.gui.screen[spell_gui_frame_name] then
    local f = player.gui.screen[spell_gui_frame_name]
    if f['spell_table'] then
      if f['spell_table']['mana'] then
        f['spell_table']['mana'].caption = math.floor(rpg_t.mana)
      end
      if f['spell_table']['maxmana'] then
        f['spell_table']['maxmana'].caption = math.floor(rpg_t.mana_max)
      end
    end
  end

  if rpg_t.mana_max < 1 then
    return
  end

  if rpg_t.mana >= rpg_t.mana_max then
    rpg_t.mana = rpg_t.mana_max
    return
  end

  rpg_t.mana = rpg_t.mana + mana_to_add
end

function Public.update_health(player)
  local rpg_extra = Public.get('rpg_extra')
  local rpg_t = Public.get_value_from_player(player.index)

  if not player or not player.valid then
    return
  end

  if not player.character or not player.character.valid then
    return
  end

  if not rpg_t then
    return
  end

  if player.gui.screen[main_frame_name] then
    local f = player.gui.screen[main_frame_name]
    local data = Gui.get_data(f)
    if data and data.health and data.health.valid then
      data.health.caption = (round(player.character.health * 10) / 10)
    end
    local shield_gui = player.character.get_inventory(defines.inventory.character_armor)
    if not shield_gui.is_empty() then
      if shield_gui[1].grid then
        local shield = math.floor(shield_gui[1].grid.shield)
        local shield_max = math.floor(shield_gui[1].grid.max_shield)
        if data and data.shield and data.shield.valid then
          data.shield.caption = shield
        end
        if data and data.shield_max and data.shield_max.valid then
          data.shield_max.caption = shield_max
        end
      end
    end
  end

  if rpg_extra.enable_health_and_mana_bars then
    if rpg_t.show_bars and player.character then
      -- Factorio 2.0中max_health已从prototype移至entity
      local max_life = math.floor( player.character.max_health)
      if not rpg_t.health_bar or not rpg_t.health_bar.valid then
        rpg_t.health_bar = create_healthbar(player, 0.5)
      end
      set_bar(player.character.health, max_life, rpg_t.health_bar)
    else
      if rpg_t.health_bar and rpg_t.health_bar.valid then
        rpg_t.health_bar.destroy()
      end
    end
  end
end

function Public.level_limit_exceeded(player, value)
  local rpg_extra = Public.get('rpg_extra')
  local rpg_t = Public.get_value_from_player(player.index)
  if not rpg_extra.level_limit_enabled then
    return false
  end

  local limits = {
    [1] = 30,
    [2] = 50,
    [3] = 70,
    [4] = 90,
    [5] = 110,
    [6] = 130,
    [7] = 150,
    [8] = 170,
    [9] = 190,
    [10] = 210
  }

  local level = rpg_t.level
  local zone = rpg_extra.breached_walls
  if zone >= 11 then
    zone = 10
  end
  if value then
    return limits[zone]
  end

  if level >= limits[zone] then
    return true
  end
  return false
end

function Public.level_up_effects(player)
  local position = {x = player.physical_position.x - 0.75, y = player.physical_position.y - 1}
  player.create_local_flying_text({position = position, text = '+LVL ', color = level_up_floating_text_color})
  local b = 0.75
  for _ = 1, 5, 1 do
    local p = {
      (position.x + 0.4) + (b * -1 + math.random(0, b * 20) * 0.1),
      position.y + (b * -1 + math.random(0, b * 20) * 0.1)
    }
    player.create_local_flying_text({position = p, text = '✚', color = {1, math.random(0, 100)/255, 0}})
  end
  player.play_sound {path = 'utility/achievement_unlocked', volume_modifier = 0.40}
end

function Public.xp_effects(player)
  local position = {x = player.physical_position.x - 0.75, y = player.physical_position.y - 1}
  player.create_local_flying_text({position = position, text = '+XP', color = level_up_floating_text_color})
  local b = 0.75
  for _ = 1, 5, 1 do
    local p = {
      (position.x + 0.4) + (b * -1 + math.random(0, b * 20) * 0.1),
      position.y + (b * -1 + math.random(0, b * 20) * 0.1)
    }
    player.create_local_flying_text({position = p, text = '✚', color = {1, math.random(0, 100)/255, 0}})
  end
  player.play_sound {path = 'utility/achievement_unlocked', volume_modifier = 0.40}
end

function Public.get_melee_modifier(player)
  local rpg_t = Public.get_value_from_player(player.index)
  return (rpg_t.strength - 10) * 0.10
end

function Public.get_final_damage_modifier(player)
  local rpg_t = Public.get_value_from_player(player.index)
  local rng = math.random(10, 35) * 0.01
  return (rpg_t.strength - 10) * rng
end

function Public.get_final_damage(player, entity, original_damage_amount)
  local modifier = Public.get_final_damage_modifier(player)
  local damage = original_damage_amount + original_damage_amount * modifier
  if entity.prototype.resistances then
    if entity.prototype.resistances.physical then
      damage = damage - entity.prototype.resistances.physical.decrease
      damage = damage - damage * entity.prototype.resistances.physical.percent
    end
  end
  damage = round(damage, 3)
  if damage < 1 then
    damage = 1
  end
  return damage
end

function Public.get_heal_modifier(player)
  local rpg_t = Public.get_value_from_player(player.index)
  return (rpg_t.vitality - 10) * 0.06
end

function Public.get_heal_modifier_from_using_fish(player)
  local rpg_extra = Public.get('rpg_extra')
  if rpg_extra.disable_get_heal_modifier_from_using_fish then
    return
  end

  local base_amount = 80
  local rng = math.random(base_amount, base_amount * rpg_extra.heal_modifier)
  local char = player.character
  local position = player.physical_position
  if char and char.valid then
    local health = player.character_health_bonus + 250
    local color
    if char.health > (health * 0.50) then
      color = {b = 0.2, r = 0.1, g = 1, a = 0.8}
    elseif char.health > (health * 0.25) then
      color = {r = 1, g = 1, b = 0}
    else
      color = {b = 0.1, r = 1, g = 0, a = 0.8}
    end
    player.create_local_flying_text(
    {
      position = {position.x, position.y + 0.6},
      text = '+' .. rng,
      color = color
    }
  )
  char.health = char.health + rng
end
end

function Public.get_mana_modifier(player)
  local rpg_t = Public.get_value_from_player(player.index)
  local modifier
  if rpg_t.level <= 40 then
    modifier = (rpg_t.magicka - 10) * 0.02000
  elseif rpg_t.level <= 80 then
    modifier = (rpg_t.magicka - 10) * 0.01800
  elseif rpg_t.level <= 120 then
    modifier = (rpg_t.magicka - 10) * 0.01400
  elseif rpg_t.level <= 160 then
    modifier = (rpg_t.magicka - 10) * 0.01200
  else
    modifier = (rpg_t.magicka - 10) * 0.01000
  end
  return math.min(modifier, 30)
end

function Public.get_life_on_hit(player)
  local rpg_t = Public.get_value_from_player(player.index)
  return (rpg_t.vitality - 10) * 0.4
end

function Public.get_one_punch_chance(player)
  local rpg_t = Public.get_value_from_player(player.index)
  if rpg_t.strength < 100 then
    return 0
  end
  local chance = round(rpg_t.strength * 0.012, 1)
  if chance > 100 then
    chance = 100
  end
  return chance
end

function Public.get_extra_following_robots(player)
  local rpg_t = Public.get_value_from_player(player.index)
  local strength = rpg_t.strength
  local count = round(strength /35, 3)
  return count
end

function Public.get_magicka(player)
  local rpg_t = Public.get_value_from_player(player.index)
  return (rpg_t.magicka - 10) * 0.10
end

--- Gives connected player some bonus xp if the map was preemptively shut down.
-- amount (integer) -- 10 levels
-- local Public = require 'modules.rpg.table' Public.give_xp(512)
function Public.give_xp(amount)
  for _, player in pairs(game.connected_players) do
    if not Public.validate_player(player) then
      return
    end
    Public.gain_xp(player, amount)
  end
end

function Public.rpg_reset_player(player, one_time_reset)
  if not player.character then
    player.set_controller({type = defines.controllers.god})
    player.create_character()
  end
  local rpg_t = Public.get_value_from_player(player.index)
  local rpg_extra = Public.get('rpg_extra')
  if one_time_reset then
    local total = rpg_t.total
    if not total then
      total = 0
    end
    if rpg_t.text and rpg_t.text.valid then
      rpg_t.text.destroy()
      rpg_t.text = nil
    end
    local old_level = rpg_t.level
    local old_points_left = rpg_t.points_left
    local old_xp = rpg_t.xp
    rpg_t =
    Public.set_new_player_tbl(
    player.index,
    {
      level = 1,
      xp = 0,
      strength = 10,
      magicka = 10,
      dexterity = 10,
      vitality = 10,
      mana = 0,
      mana_max = 0,
      last_spawned = 0,
      last_cast_position = {x = 0, y = -5},  -- 使用特殊值表示未设置状态
      auto_cast_enabled = false,
      crafting_speed = 0,
      dropdown_select_index = 1,
      dropdown_select_index1 = 1,
      dropdown_select_index2 = 1,
      dropdown_select_index3 = 1,
      allocate_index = 1,
      flame_boots = false,
      explosive_bullets = false,
      enable_entity_spawn = false,
      health_bar = rpg_t.health_bar,
      mana_bar = rpg_t.mana_bar,
      points_left = 0,
      last_floaty_text = visuals_delay,
      xp_since_last_floaty_text = 0,
      reset = true,
      capped = false,
      bonus = rpg_extra.breached_walls or 1,
      rotated_entity_delay = 0,
      last_mined_entity_position = {x = 0, y = 0},
      show_bars = true,
      stone_path = false,
      one_punch = false,
      transfered_once = false,
      auto_toggle_features = {
        stone_path = false,
        one_punch = false
      }
    }
  )
  rpg_t.points_left = old_points_left + total
  rpg_t.xp = round(old_xp)
  rpg_t.level = old_level
else
  Public.set_new_player_tbl(
  player.index,
  {
    level = 1,
    xp = 0,
    strength = 10,
    magicka = 10,
    dexterity = 10,
    vitality = 10,
    mana = 0,
    mana_max = 0,
      last_spawned = 0,
      last_cast_position = {x = 0, y = -5},  -- 使用特殊值表示未设置状态
      auto_cast_enabled = false,
      crafting_speed = 0,
      dropdown_select_index = 1,
    dropdown_select_index1 = 1,
    dropdown_select_index2 = 1,
    dropdown_select_index3 = 1,
    allocate_index = 1,
    flame_boots = false,
    explosive_bullets = false,
    enable_entity_spawn = false,
    points_left = 0,
    last_floaty_text = visuals_delay,
    xp_since_last_floaty_text = 0,
    reset = false,
    capped = false,
    total = 0,
    bonus = 1,
    rotated_entity_delay = 0,
    last_mined_entity_position = {x = 0, y = 0},
    show_bars = true,
    stone_path = false,
    one_punch = false,
    transfered_once = false,
    auto_toggle_features = {
      stone_path = false,
      one_punch = false
    }
  }
)
end
Public.draw_gui_char_button(player)
Public.draw_level_text(player)
Public.update_char_button(player)
Public.update_player_stats(player)
end

function Public.rpg_reset_all_players()
  local rpg_t = Public.get('rpg_t')
  local rpg_extra = Public.get('rpg_extra')
  for k, _ in pairs(rpg_t) do
    rpg_t[k] = nil
  end
  for _, p in pairs(game.connected_players) do
    Public.rpg_reset_player(p)
  end
  rpg_extra.breached_walls = 1
  rpg_extra.reward_new_players = 0
  rpg_extra.global_pool = 0
end

function Public.gain_xp(player, amount, added_to_pool, text)
  if not Public.validate_player(player) then
    return
  end
  local rpg_extra = Public.get('rpg_extra')
  local rpg_t = Public.get_value_from_player(player.index)

  if Public.level_limit_exceeded(player) then
    add_to_global_pool(amount, false)
    if not rpg_t.capped then
      rpg_t.capped = true
      local message = ({'rpg_functions.max_level'})
      Alert.alert_player_warning(player, 10, message)
    end
    return
  end

  local text_to_draw

  if rpg_t.capped then
    rpg_t.capped = false
  end

  if not added_to_pool then
    Public.debug_log('RPG - ' .. player.name .. ' got org xp: ' .. amount)
    local fee = amount - add_to_global_pool(amount, true)
    Public.debug_log('RPG - ' .. player.name .. ' got fee: ' .. fee)
    amount = round(amount, 3) - fee
    if rpg_extra.difficulty then
      amount = amount + rpg_extra.difficulty
    end
    local this = WPT.get()
    if this.experience_bonus then
      amount = amount * (1 + this.experience_bonus)
    end
    Public.debug_log('RPG - ' .. player.name .. ' got after fee: ' .. amount)
  else
    Public.debug_log('RPG - ' .. player.name .. ' got org xp: ' .. amount)
  end

  rpg_t.xp = round(rpg_t.xp + amount, 3)
  rpg_t.xp_since_last_floaty_text = round(rpg_t.xp_since_last_floaty_text + amount)

  if not experience_levels[rpg_t.level + 1] then
    return
  end

  local f = player.gui.screen[main_frame_name]
  if f and f.valid then
    local d = Gui.get_data(f)
    if d.exp_gui and d.exp_gui.valid then
      d.exp_gui.caption = math.floor(rpg_t.xp)
    end
  end

  if rpg_t.xp >= experience_levels[rpg_t.level + 1] then
    level_up(player)
  end

  if rpg_t.last_floaty_text > game.tick then
    if not text then
      return
    end
  end

  if text then
    text_to_draw = '+' .. math.floor(amount) .. ' xp'
  else
    text_to_draw = '+' .. math.floor(rpg_t.xp_since_last_floaty_text) .. ' xp'
  end

  player.create_local_flying_text {
    text = text_to_draw,
    position = player.physical_position,
    color = xp_floating_text_color,
    time_to_live = 340,
    speed = 2
  }

  rpg_t.xp_since_last_floaty_text = 0
  rpg_t.last_floaty_text = game.tick + visuals_delay
end

function Public.global_pool(players, count)
  local rpg_extra = Public.get('rpg_extra')

  if not rpg_extra.global_pool then
    return
  end

  local pool = math.floor(rpg_extra.global_pool)

  local random_amount = math.random(5000, 10000)

  if pool <= random_amount then
    return
  end

  if pool >= 20000 then
    pool = 20000
  end

  local share = pool / count

  Public.debug_log('RPG - Share per player:' .. share)

  for i = 1, #players do
    local p = players[i]
    if p.afk_time < 5000 then
      if not Public.level_limit_exceeded(p) then
        Public.gain_xp(p, share, false, true)
        Public.xp_effects(p)
      else
        share = share / 10
        rpg_extra.leftover_pool = rpg_extra.leftover_pool + share
        Public.debug_log('RPG - player capped: ' .. p.name .. '. Amount to pool:' .. share)
      end
    else
      local message = ({'rpg_functions.pool_reward', p.name})
      Alert.alert_player_warning(p, 10, message)
      share = share / 10
      rpg_extra.leftover_pool = rpg_extra.leftover_pool + share
      Public.debug_log('RPG - player AFK: ' .. p.name .. '. Amount to pool:' .. share)
    end
  end

  rpg_extra.global_pool = rpg_extra.leftover_pool or 0

  return
end

local damage_player_over_time_token =
Token.register(
function(data)
  local player = data.player
  if not player.character or not player.character.valid then
    return
  end
  player.character.health = player.character.health - (player.character.health * 0.05)
  player.character.surface.create_entity({name = 'water-splash', position = player.physical_position})
end
)

--- Damages a player over time.
function Public.damage_player_over_time(player, amount)
  if not player or not player.valid then
    return
  end

  amount = amount or 10
  local tick = 20
  for _ = 1, amount, 1 do
    Task.set_timeout_in_ticks(tick, damage_player_over_time_token, {player = player})
    tick = tick + 15
  end
end

--- Distributes the global xp pool to every connected player.
function Public.distribute_pool()
  local count = #game.connected_players
  local players = game.connected_players
  Public.global_pool(players, count)
  print('Distributed the global XP pool')
end

Public.add_to_global_pool = add_to_global_pool

-- 创建属性点和天赋转移界面
function Public.create_transfer_gui(player)
  local rpg_t = Public.get_value_from_player(player.index)
  
  -- 检查玩家是否已经转移过属性
  if rpg_t.transfered_once then
    player.print("您已经转移过属性和天赋，每人仅可转移一次！", {r = 1, g = 0.5, b = 0.5})
    return
  end
  
  --检查玩家等级是否达到105级
  if rpg_t.level < 105 then
    player.print("您的等级还未达到105级，无法转移属性！", {r = 1, g = 0.5, b = 0.5})
    return
  end

  -- 检查玩家是否还有属性点或天赋点
  if rpg_t.points_left <= 0 and rpg_t.strength <= 10 and rpg_t.magicka <= 10 and rpg_t.dexterity <= 10 and rpg_t.vitality <= 10 then
    player.print("您没有任何属性点或天赋可以转移！", {r = 1, g = 0.5, b = 0.5})
    return
  end
  
  local frame = player.gui.screen.add({type = "frame", name = Public.transfer_frame_name, caption = {'amap.rpg_transfer_title'}, direction = "vertical"})
  frame.auto_center = true
  
  local scroll_pane = frame.add({type = "scroll-pane", direction = "vertical"})
  scroll_pane.style.maximal_height = 300
  
  -- 获取在线玩家列表（排除自己）
  local online_players = {}
  for _, p in pairs(game.connected_players) do
    if p.index ~= player.index then
      table.insert(online_players, p)
    end
  end
  
  -- 如果没有其他在线玩家
  if #online_players == 0 then
    frame.add({type = "label", caption = {'amap.rpg_transfer_no_player'}})
    local close_button = frame.add({type = "button", caption = {'amap.rpg_transfer_close'}})
    close_button.style.font = "default-bold"
    close_button.name = "transfer_cancel_button"
    Gui.on_click("transfer_cancel_button", function(event)
      if frame and frame.valid then
        frame.destroy()
      end
    end)
    return
  end
  
  -- 为每个在线玩家创建按钮
  for _, target_player in pairs(online_players) do
    local button = scroll_pane.add({
      type = "button", 
      caption = target_player.name,
      name = "transfer_to_" .. target_player.index
    })
    button.style.font = "default-bold"
    button.style.minimal_width = 200
    
    -- 添加点击事件
    Gui.on_click("transfer_to_" .. target_player.index, function(event)
      -- 执行转移操作
      Public.execute_transfer(player, target_player)
      
      -- 关闭界面
      if frame and frame.valid then
        frame.destroy()
      end
    end)
  end
  
  -- 添加关闭按钮
  local close_button = frame.add({type = "button", caption = {'amap.rpg_transfer_cancel'}})
  close_button.style.font = "default-bold"
  close_button.name = "transfer_cancel_button"
  Gui.on_click("transfer_cancel_button", function(event)
    if frame and frame.valid then
      frame.destroy()
    end
  end)
end

-- 执行属性点和天赋转移
function Public.execute_transfer(source_player, target_player)
  local source_rpg = Public.get_value_from_player(source_player.index)
  local target_rpg = Public.get_value_from_player(target_player.index)
  
  -- 检查玩家是否已经转移过属性
  if source_rpg.transfered_once then
    source_player.print("您已经转移过属性和天赋，每人仅可转移一次！", {r = 1, g = 0.5, b = 0.5})
    return
  end
  
  -- 计算要转移的属性点（一半）
  local strength_to_transfer = math.floor((source_rpg.strength - 10) / 2)
  local magicka_to_transfer = math.floor((source_rpg.magicka - 10) / 2)
  local dexterity_to_transfer = math.floor((source_rpg.dexterity - 10) / 2)
  local vitality_to_transfer = math.floor((source_rpg.vitality - 10) / 2)
  
  -- 转移属性点
  if strength_to_transfer > 0 then
    source_rpg.strength = 10
    target_rpg.strength = target_rpg.strength + strength_to_transfer
  end
  
  if magicka_to_transfer > 0 then
    source_rpg.magicka = 10
    target_rpg.magicka = target_rpg.magicka + magicka_to_transfer
  end
  
  if dexterity_to_transfer > 0 then
    source_rpg.dexterity = 10
    target_rpg.dexterity = target_rpg.dexterity + dexterity_to_transfer
  end
  
  if vitality_to_transfer > 0 then
    source_rpg.vitality = 10
    target_rpg.vitality = target_rpg.vitality + vitality_to_transfer
  end
  
  -- 转移未分配的属性点
  local points_to_transfer = math.floor(source_rpg.points_left / 2)
  if points_to_transfer > 0 then
    source_rpg.points_left = 0
    target_rpg.points_left = target_rpg.points_left + points_to_transfer
  end
  
  -- 转移天赋
   local main_table = WPT.get()
   local tianfu = tianfu_table.get()
   local source_skills = main_table.skill and main_table.skill[source_player.name]
   -- ★ 方案 D 简化版：字典存储 skill_name -> q_idx，用 next 判断非空（# 对字典恒为 0）
   if source_skills and next(source_skills) then
     -- 确保目标玩家的skill表存在
     if not main_table.skill[target_player.name] then
       main_table.skill[target_player.name] = {}
     end

     -- 收集源玩家天赋 key 列表（用于随机抽取一半）
     local source_keys = {}
     for k, _ in pairs(source_skills) do
       table.insert(source_keys, k)
     end

     -- 计算要转移的天赋数量（一半）
     local skills_to_transfer = math.floor(#source_keys / 2)

     if skills_to_transfer > 0 then
       local transferred_skills = {}  -- set：skill_id -> true
       local skipped_skills = {}      -- set：skill_id -> true

       -- 随机选择天赋进行转移
       for i = 1, skills_to_transfer do
         if #source_keys > 0 then
           -- 从源玩家剩余天赋里随机抽一个
           local r = math.random(1, #source_keys)
           local skill_id = source_keys[r]
           local quality = source_skills[skill_id]

           -- 从待抽列表中移除，避免重复抽取
           table.remove(source_keys, r)

           -- 检查目标玩家是否已经学习了这个天赋
           local already_learned = (main_table.skill[target_player.name][skill_id] ~= nil)

           -- 无论转移还是跳过，都从源玩家学习表中移除（原逻辑：被抽中的天赋即消耗）
           source_skills[skill_id] = nil

           if already_learned then
             skipped_skills[skill_id] = true
           else
             -- 转移天赋学习表（含品质 q_idx）
             main_table.skill[target_player.name][skill_id] = quality
             transferred_skills[skill_id] = true

             -- 转移天赋启用状态表 tianfu_enabled
             local source_enabled = main_table.tianfu_enabled[source_player.index]
             local target_enabled = main_table.tianfu_enabled[target_player.index]

             if source_enabled and source_enabled[skill_id] ~= nil then
               if not target_enabled then
                 main_table.tianfu_enabled[target_player.index] = {}
                 target_enabled = main_table.tianfu_enabled[target_player.index]
               end
               target_enabled[skill_id] = source_enabled[skill_id]
             end

             if source_enabled then
               source_enabled[skill_id] = nil
             end

             -- 转移天赋执行表（tianfu[skill_id] = {玩家名...}）
             if tianfu[skill_id] then
               for idx, player_name in pairs(tianfu[skill_id]) do
                 if player_name == source_player.name then
                   table.remove(tianfu[skill_id], idx)
                   break
                 end
               end
             end

             if not tianfu[skill_id] then
               tianfu[skill_id] = {}
             end
             table.insert(tianfu[skill_id], target_player.name)
           end
         end
       end

       -- 统计数量并通知
       local transfer_count = 0
       for _ in pairs(transferred_skills) do transfer_count = transfer_count + 1 end
       local skip_count = 0
       for _ in pairs(skipped_skills) do skip_count = skip_count + 1 end

       if transfer_count > 0 or skip_count > 0 then
         if transfer_count > 0 then
           source_player.print("成功向玩家 " .. target_player.name .. " 转移了 " .. transfer_count .. " 个天赋！", {r = 0.5, g = 1, b = 0.5})
           target_player.print("从玩家 " .. source_player.name .. " 处获得了 " .. transfer_count .. " 个天赋！", {r = 0.5, g = 1, b = 0.5})
         end

         if skip_count > 0 then
           source_player.print("跳过了 " .. skip_count .. " 个天赋，因为目标玩家已经学习了这些天赋。", {r = 1, g = 0.8, b = 0.2})
         end
       end
     end
   end
  
  -- 标记源玩家已经转移过
  source_rpg.transfered_once = true
  
  -- 更新玩家状态
  Public.update_player_stats(source_player)
  Public.update_player_stats(target_player)
  
  -- 发送通知消息
  source_player.print("成功向玩家 " .. target_player.name .. " 转移了一半的属性点和天赋！您已无法再次转移。", {r = 0.5, g = 1, b = 0.5})
  target_player.print("从玩家 " .. source_player.name .. " 处获得了属性点和天赋！", {r = 0.5, g = 1, b = 0.5})
end


-- 注意：原fairy_lightning_trigger函数已被移除，闪电链现在在主循环中直接触发

-- 以下函数（xiao_jingling、cleanup_fairy_spirits、trigger_all_fairy_lightning、
-- huanxing_huoshan_penfa、leizhenyu、diankuang 及相关 Token）已迁移至 spells.lua。
-- 这里保留迁移说明占位，实际删除从下方开始。

return Public
