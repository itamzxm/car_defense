--RPG Modules
local Public = require 'modules.rpg.core'
local Spells = Public.spells
local Gui = require 'utils.gui'
local Event = require 'utils.event'
local Color = require 'utils.color_presets'
local SpamProtection = require 'utils.spam_protection'
-- BiterHealthBooster has been removed
--local Explosives = require 'modules.explosives'
local WPT = require 'maps.amap.table'
local WD = require 'modules.wave_defense.table'
local Math2D = require 'math2d'
local pet= require 'maps.amap.biter_pets'
local BiterRolls = require 'modules.wave_defense.biter_rolls'
local Tianfu = require 'maps.amap.tianfu'
local Instance = require 'maps.amap.instance.instance'

local player_loader = {
  'loader',
  'inserter'
}
local Task = require 'utils.task'
local Token = require 'utils.token'
--RPG Settings
local enemy_types = Public.enemy_types
local die_cause = Public.die_cause
local points_per_level = Public.points_per_level
local nth_tick = Public.nth_tick

--RPG Frames
local main_frame_name = Public.main_frame_name

local sub = string.sub
local round = math.round
local floor = math.floor

local sqrt = math.sqrt
local abs = math.abs


local function on_gui_click(event)
  if not event then
    return
  end
  local player = game.players[event.player_index]
  if not (player and player.valid) then
    return
  end

  if not event.element then
    return
  end
  if not event.element.valid then
    return
  end
  local element = event.element
  if player.gui.screen[main_frame_name] then
    local is_spamming = SpamProtection.is_spamming(player, nil, 'RPG Gui Click')
    if is_spamming then
      return
    end
  end

  local surface_name = Public.get('rpg_extra').surface_name


  if element.type ~= 'sprite-button' then
    return
  end

  local shift = event.shift

  if element.caption ~= '✚' then
    return
  end
  if element.sprite ~= 'virtual-signal/signal-red' then
    return
  end

  local rpg_t = Public.get_value_from_player(player.index)

  local index = element.name
  if not rpg_t[index] then
    return
  end
  if not player.character then
    return
  end

  if shift then
    if event.button == defines.mouse_button_type.left then
      local count = rpg_t.points_left
      if not count then
        return
      end
      rpg_t.points_left = 0
      rpg_t[index] = rpg_t[index] + count
      if not rpg_t.reset then
        rpg_t.total = rpg_t.total + count
      end
      Public.toggle(player, true)
      Public.update_player_stats(player)
    elseif event.button == defines.mouse_button_type.right then
      local left = rpg_t.points_left / 2
      if left > 2 then
        for _ = 1, left, 1 do
          if rpg_t.points_left <= 0 then
            Public.toggle(player, true)
            return
          end
          rpg_t.points_left = rpg_t.points_left - 1
          rpg_t[index] = rpg_t[index] + 1
          if not rpg_t.reset then
            rpg_t.total = rpg_t.total + 1
          end
          Public.update_player_stats(player)
        end
      end
      Public.toggle(player, true)
    end
  elseif event.button == defines.mouse_button_type.right then
    for _ = 1, points_per_level, 1 do
      if rpg_t.points_left <= 0 then
        Public.toggle(player, true)
        return
      end
      rpg_t.points_left = rpg_t.points_left - 1
      rpg_t[index] = rpg_t[index] + 1
      if not rpg_t.reset then
        rpg_t.total = rpg_t.total + 1
      end
      Public.update_player_stats(player)
    end
    Public.toggle(player, true)
    return
  end

  if rpg_t.points_left <= 0 then
    Public.toggle(player, true)
    return
  end
  rpg_t.points_left = rpg_t.points_left - 1
  rpg_t[index] = rpg_t[index] + 1
  if not rpg_t.reset then
    rpg_t.total = rpg_t.total + 1
  end
  Public.update_player_stats(player)
  Public.toggle(player, true)
end

local function train_type_cause(cause)
  local players = {}
  if cause.train.passengers then
    for _, player in pairs(cause.train.passengers) do
      players[#players + 1] = player
    end
  end
  return players
end

local get_cause_player = {
  ['character'] = function(cause)
    if not cause.player then
      return
    end
    return {cause.player}
  end,
  ['combat-robot'] = function(cause)
    if not cause.last_user then
      return
    end
    if not game.players[cause.last_user.index] then
      return
    end
    return {game.players[cause.last_user.index]}
  end,
  ['car'] = function(cause)
    local players = {}
    local driver = cause.get_driver()
    if driver then
      if driver.player then
        players[#players + 1] = driver.player
      end
    end
    local passenger = cause.get_passenger()
    if passenger then
      if passenger.player then
        players[#players + 1] = passenger.player
      end
    end
    return players
  end,
  ['spider-vehicle'] = function(cause)
    local players = {}
    local driver = cause.get_driver()
    if driver then
      if driver.player then
        players[#players + 1] = driver.player
      end
    end
    local passenger = cause.get_passenger()
    if passenger then
      if passenger.player then
        players[#players + 1] = passenger.player
      end
    end
    return players
  end,
  ['locomotive'] = train_type_cause,
  ['cargo-wagon'] = train_type_cause,
  ['artillery-wagon'] = train_type_cause,
  ['fluid-wagon'] = train_type_cause
}
local kill_forces =
Token.register(
function(data)
  for _,v in pairs(data) do
  if  v and  v.valid then
    v.destroy()
  end
end

end
)



local function on_entity_died(event)
  if not event.entity or not event.entity.valid then
    return
  end

  local entity = event.entity

  -- 副本隔离：副本 surface 上的击杀不触发主世界 RPG 经验（避免竞技场等副本刷经验）
  if entity.surface and Instance.is_dungeon_surface(entity.surface.name) then
    return
  end

  --Grant XP for hand placed land mines
  if entity.last_user then
    if entity.type == 'land-mine' then
      if event.cause then
        if event.cause.valid then
          if event.cause.force.index == entity.force.index then
            return
          end
        end
      end
      Public.gain_xp(entity.last_user, 1)
      return
    end
  end

  local rpg_extra = Public.get('rpg_extra')

  if rpg_extra.enable_wave_defense then
    if rpg_extra.rpg_xp_yield['big-biter'] <= 16 then
      local wave_number = WD.get_wave()
      if wave_number >= 1000 then
        rpg_extra.rpg_xp_yield['big-biter'] = 16
        rpg_extra.rpg_xp_yield['behemoth-biter'] = 64
      end
    end
  end

  if not event.cause or not event.cause.valid then
    return
  end

  local cause = event.cause
  local type = cause.type
  if not type then
    goto continue
  end

  if cause.force.index == 1 then
    if die_cause[type] then
      if rpg_extra.rpg_xp_yield[entity.name] then
        local amount = rpg_extra.rpg_xp_yield[entity.name]
        amount = amount / 5
        
        -- 尝试给放置炮塔的玩家经验
        local this = WPT.get()
        if this.gun_turret and this.gun_turret[cause.unit_number] then
          local player = game.players[this.gun_turret[cause.unit_number]]
          if player and player.valid and player.character and player.character.valid then
            Public.gain_xp(player, amount)
          else
            -- 如果找不到玩家，尝试使用last_user
            if cause.last_user and cause.last_user.valid then
              Public.gain_xp(cause.last_user, amount)
            else
              -- 如果没有last_user，则放入全局经验池
              Public.add_to_global_pool(amount, false)
            end
          end
        else
          -- 如果找不到炮塔所有者，尝试使用last_user
          if cause.last_user and cause.last_user.valid then
            Public.gain_xp(cause.last_user, amount)
          else
            -- 如果没有last_user，则放入全局经验池
            Public.add_to_global_pool(amount, false)
          end
        end
      else
        Public.add_to_global_pool(0.5, false)
      end
      return
    end
  end

  ::continue::

  if cause.force.index == entity.force.index then
    return
  end

  if not get_cause_player[cause.type] then
    return
  end

  local players = get_cause_player[cause.type](cause)
  if not players then
    return
  end
  if not players[1] then
    return
  end

  local this=WPT.get()
 
  --Grant normal XP
  -- 检查是否是炮塔击杀
  if die_cause[cause.type] then
    -- 炮塔击杀普通敌人，直接给炮塔所有者经验
    if rpg_extra.rpg_xp_yield[entity.name] then
      local amount = rpg_extra.rpg_xp_yield[entity.name]
      
      -- 尝试给放置炮塔的玩家经验
      if this.gun_turret and this.gun_turret[cause.unit_number] then
        local player = game.players[this.gun_turret[cause.unit_number]]
        if player and player.valid and player.character and player.character.valid then
          Public.gain_xp(player, amount)
          -- 炮塔击杀不再给玩家回蓝
        else
          -- 如果找不到玩家，尝试使用last_user
          if cause.last_user and cause.last_user.valid then
            Public.gain_xp(cause.last_user, amount)
          else
            -- 如果没有last_user，则放入全局经验池
            local inserted = Public.add_to_global_pool(amount, true)
            for _, p in pairs(players) do
              Public.gain_xp(p, inserted, true)
            end
          end
        end
      else
        -- 如果找不到炮塔所有者，尝试使用last_user
        if cause.last_user and cause.last_user.valid then
          Public.gain_xp(cause.last_user, amount)
        else
          -- 如果没有last_user，则放入全局经验池
          local inserted = Public.add_to_global_pool(amount, true)
          for _, p in pairs(players) do
            Public.gain_xp(p, inserted, true)
          end
        end
      end
    else
      local inserted = Public.add_to_global_pool(0.5, true)
      for _, p in pairs(players) do
        Public.gain_xp(p, inserted, true)
      end
    end
  else
    -- 非炮塔击杀，按原逻辑处理
    for _, player in pairs(players) do
      if game.forces.enemy.get_evolution_factor() >= 0.2 then
        local index = player.index
      end

      if rpg_extra.rpg_xp_yield[entity.name] then
        local amount = rpg_extra.rpg_xp_yield[entity.name]
        if rpg_extra.turret_kills_to_global_pool then
          local inserted = Public.add_to_global_pool(amount, true)
          Public.gain_xp(player, inserted, true)
        else
          Public.gain_xp(player, amount)
        end
      else
        Public.gain_xp(player, 0.5)
      end
    end
  end
end

local function regen_health_player(players)
  for i = 1, #players do
    local player = players[i]
    local heal_per_tick = Public.get_heal_modifier(player)
    if heal_per_tick <= 0 then
      goto continue
    end
    heal_per_tick = round(heal_per_tick)
    if player and player.valid and not player.in_combat then
      if player.character and player.character.valid then
        player.character.health = player.character.health + heal_per_tick
      end
    end

    ::continue::

    Public.update_health(player)
  end
end

local function regen_mana_player(players)
  for i = 1, #players do
    local player = players[i]
    local mana_per_tick = Public.get_mana_modifier(player)
    local rpg_extra = Public.get('rpg_extra')
    local rpg_t = Public.get_value_from_player(player.index)
    if mana_per_tick <= 0.1 then
      mana_per_tick = rpg_extra.mana_per_tick
    end

    if rpg_extra.force_mana_per_tick then
      mana_per_tick = 1
    end

    if player and player.valid and not player.in_combat then
      if player.character and player.character.valid then
        if rpg_t.mana < 0 then
          rpg_t.mana = 0
        end
        if rpg_t.mana >= rpg_t.mana_max then
          goto continue
        end
        rpg_t.mana = rpg_t.mana + mana_per_tick
        if rpg_t.mana >= rpg_t.mana_max then
          rpg_t.mana = rpg_t.mana_max
        end
        rpg_t.mana = (round(rpg_t.mana * 10) / 10)
      end
    end

    ::continue::

    Public.update_mana(player)
  end
end


local function has_health_boost(entity, damage, final_damage_amount, cause)
  local get_health_pool = nil -- Always nil as BiterHealthBooster is removed

  --Handle vanilla damage.
  entity.health = entity.health + final_damage_amount
  entity.health = entity.health - damage
  if entity.health <= 0 then
      entity.die(cause.force.name, cause)
  end

  return get_health_pool
end


local function is_position_near(area, entity)
  local status = false

  local function inside(pos)
    local lt = area.left_top
    local rb = area.right_bottom

    return pos.x >= lt.x and pos.y >= lt.y and pos.x <= rb.x and pos.y <= rb.y
  end

  if inside(entity, area) then
    status = true
  end

  return status
end

local function on_player_repaired_entity(event)
  if math.random(1, 4) ~= 1 then
    return
  end

  local entity = event.entity

  if not entity then
    return
  end

  if not entity.valid then
    return
  end

  if not entity.health then
    return
  end

  local player = game.players[event.player_index]

  if not player or not player.valid or not player.character then
    return
  end

  Public.gain_xp(player, 0.05)

  local repair_speed = Public.get_magicka(player)
  if repair_speed <= 0 then
    return
  end
  entity.health = entity.health + repair_speed
end

local function on_player_rotated_entity(event)
  local player = game.players[event.player_index]

  if not player or not player.valid then
    return
  end
  if not player.character then
    return
  end

  local rpg_t = Public.get_value_from_player(player.index)
  if rpg_t.rotated_entity_delay > game.tick then
    return
  end
  rpg_t.rotated_entity_delay = game.tick + 20
  Public.gain_xp(player, 0.20)
end

local function on_player_changed_position(event)
  local player = game.players[event.player_index]
  if not player or not player.valid then
    return
  end

  -- 副本隔离：副本内移动不获得主世界 RPG 移动经验
  if player.surface and Instance.is_dungeon_surface(player.surface.name) then
    return
  end

  if math.random(1, 64) ~= 1 then
    return
  end
  if not player.character then
    return
  end
  if player.character.driving then
    return
  end
  Public.gain_xp(player, 1.0)
end

local building_and_mining_blacklist = {
  ['tile-ghost'] = true,
  ['entity-ghost'] = true,
  ['item-entity'] = true
}

local function on_player_died(event)
  local player = game.players[event.player_index]

  if not player or not player.valid then
    return
  end

  Public.remove_frame(player)
end

local function on_pre_player_left_game(event)
  local player = game.players[event.player_index]

  if not player or not player.valid then
    return
  end

  Public.remove_frame(player)
end

local function on_pre_player_mined_item(event)
  local entity = event.entity
  if not entity.valid then
    return
  end
  if building_and_mining_blacklist[entity.type] then
    return
  end
  if entity.force.index ~= 3 then
    return
  end
  local player = game.players[event.player_index]

  if not player or not player.valid then
    return
  end

  local surface_name = Public.get('rpg_extra').surface_name


  local rpg_t = Public.get_value_from_player(player.index)
  if rpg_t.last_mined_entity_position.x == entity.position.x and rpg_t.last_mined_entity_position.y == entity.position.y then
    return
  end
  rpg_t.last_mined_entity_position.x = entity.position.x
  rpg_t.last_mined_entity_position.y = entity.position.y

  local distance_multiplier = floor(sqrt(entity.position.x ^ 2 + entity.position.y ^ 2)) * 0.0005 + 1

  local xp_modifier_when_mining = Public.get('rpg_extra').xp_modifier_when_mining

  local xp_amount
  if entity.type == 'resource' then
    xp_amount = 0.9 * distance_multiplier
  else
    xp_amount = (1.5 + entity.max_health * xp_modifier_when_mining) * distance_multiplier/2
  end

  if player.gui.screen[main_frame_name] then
    local f = player.gui.screen[main_frame_name]
    local data = Gui.get_data(f)
    if data.exp_gui and data.exp_gui.valid then
      data.exp_gui.caption = floor(rpg_t.xp)
    end
  end

  Public.gain_xp(player, xp_amount)
end

local function on_player_crafted_item(event)
  if not event.recipe.energy then
    return
  end
  local player = game.players[event.player_index]
  if not player or not player.valid then
    return
  end

  if player.cheat_mode then
    return
  end

  local rpg_extra = Public.get('rpg_extra')
  local is_blacklisted = rpg_extra.tweaked_crafting_items
  local tweaked_crafting_items_enabled = rpg_extra.tweaked_crafting_items_enabled

  local item = event.item_stack

  local amount = 0.40 * math.random(1, 2)
  local recipe = event.recipe

  if tweaked_crafting_items_enabled then
    if item and item.valid then
      if is_blacklisted[item.name] then
        amount = 0.2
      end
    end
  end

  local final_xp = recipe.energy * amount

  -- 应用手搓经验倍数（来自学徒天赋等）
  local main_table = WPT.get()
  if main_table.crafting_exp_multiplier and main_table.crafting_exp_multiplier[player.index] then
    final_xp = final_xp * math.min(main_table.crafting_exp_multiplier[player.index],1)
  end

  Public.gain_xp(player, final_xp)
end

local function on_player_respawned(event)
  local player = game.players[event.player_index]
  local rpg_t = Public.get_value_from_player(player.index)
  if not rpg_t then
    Public.rpg_reset_player(player)
    return
  end
  Public.update_player_stats(player)
  Public.draw_level_text(player)
  Public.update_health(player)
  Public.update_mana(player)
end

local function on_player_joined_game(event)
  local player = game.players[event.player_index]
  local rpg_t = Public.get_value_from_player(player.index)
  local rpg_extra = Public.get('rpg_extra')
  if not rpg_t then
    Public.rpg_reset_player(player)
    if rpg_extra.reward_new_players > 10 then
      Public.gain_xp(player, rpg_extra.reward_new_players)
    end
  end
  for _, p in pairs(game.connected_players) do
    Public.draw_level_text(p)
  end
  Public.draw_gui_char_button(player)
  if not player.character then
    return
  end
  Public.update_player_stats(player)
end

local function create_projectile(surface, name, position, force, target, max_range,player)
  if max_range then
    surface.create_entity(
    {
      name = name,
      position = position,
      force = force,
      source = position,
      target = target,
      max_range = max_range,
      speed = 0.4
    }
  )
else
  surface.create_entity(
  {
    name = name,
    position = position,
    force = force,
    source = player.character,
    target = target,
    speed = 0.4
  }
)
end
end

local function get_near_coord_modifier(range)
  local coord = {x = (range * -1) + math.random(0, range * 2), y = (range * -1) + math.random(0, range * 2)}
  for i = 1, 5, 1 do
    local new_coord = {x = (range * -1) + math.random(0, range * 2), y = (range * -1) + math.random(0, range * 2)}
    if new_coord.x ^ 2 + new_coord.y ^ 2 < coord.x ^ 2 + coord.y ^ 2 then
      coord = new_coord
    end
  end
  return coord
end

local function damage_entity(e)
  if not e or not e.valid then
    return
  end

  if not e.health then
    return
  end

  if e.force.name == 'player' then
    return
  end

  if not e.destructible then
    return
  end

  e.surface.create_entity({name = 'ground-explosion', position = e.position})

  if e.type == 'entity-ghost' then
    e.destroy()
    return
  end

  e.health = e.health - math.random(30, 90)
  if e.health <= 0 then
    e.die()
  end
end

local function floaty_hearts(entity, c)
  local position = {x = entity.position.x - 0.75, y = entity.position.y - 1}
  local b = 1.35
  for _ = 1, c, 1 do
    local p = {
      (position.x + 0.4) + (b * -1 + math.random(0, b * 20) * 0.1),
      position.y + (b * -1 + math.random(0, b * 20) * 0.1)
    }
    -- 创建一个带有动画效果的爱心文本
    local text_id = rendering.draw_text({
      text = '♥',
      surface = entity.surface,
      position = p,
      color = {math.random(150, 255)/255, 0, 1},
      scale = 1,
      font = 'default-large',
      alignment = 'center',
      scale_with_zoom = false
    })
    rendering.set_animation(text_id, {fadeout = 30, y_scale_from = 1, y_scale_to = 1.5, x_scale_from = 1, x_scale_to = 1.5})
    rendering.set_time_to_live(text_id, 30)
  end
end


local function on_player_used_capsule(event)
  local enable_mana = Public.get('rpg_extra').enable_mana
  local surface_name = Public.get('rpg_extra').surface_name
  if not enable_mana then
    return
  end

  local conjure_items = Public.rebuild_spells()
  local projectile_types = Public.get_projectiles
  local itam_spell = Public.get_itam_spell

  local player = game.players[event.player_index]
  if not player or not player.valid then
    return
  end

  if not player.character or not player.character.valid then
    return
  end

  if player.force.name ~= "player" then
    return
  end

  local item = event.item

  if not item then
    return
  end

  local name = item.name


  -- if player.physical_surface ~= game.surfaces['nauvis'] and not string.find(player.physical_surface.name, "yiciyuan") then
  --   return
  -- end

  if name ~= 'raw-fish' then
    return
  end

  Public.get_heal_modifier_from_using_fish(player)

  local rpg_t = Public.get_value_from_player(player.index)

  if not rpg_t.enable_entity_spawn then
    return
  end

  local p = player.print

  if rpg_t.last_spawned >= game.tick then
    return p(({'rpg_main.mana_casting_too_fast', player.name}), Color.warning)
  end

  local mana = rpg_t.mana
  local surface = player.physical_surface

  local object = conjure_items[rpg_t.dropdown_select_index]
  if not object then
    return
  end

  local position = event.position
  if not position then
    return
  end

  local  dist_bonus
  if projectile_types[object.entityName] then
    dist_bonus= player.character_reach_distance_bonus*3+15

    local dist=projectile_types[object.entityName].max_range
    if dist_bonus>= dist then
      dist_bonus=dist
    end
  end

  if object.itam_code then
    dist_bonus= player.character_reach_distance_bonus*3+15

    local dist=itam_spell[object.entityName].max_range
    if dist_bonus>= dist then
      dist_bonus=dist
    end

  end

  local radius = 15
  if dist_bonus then
    radius=dist_bonus
  end
  local area = {
    left_top = {x = position.x - radius, y = position.y - radius},
    right_bottom = {x = position.x + radius, y = position.y + radius}
  }

  if rpg_t.level < object.level then
    return p(({'rpg_main.low_level'}), Color.fail)
  end

  if not object.enabled then
    return
  end

  if not Math2D.bounding_box.contains_point(area, player.physical_position) then
    player.print(({'rpg_main.not_inside_pos'}), Color.fail)
    return
  end

  if mana < object.mana_cost then
    return p(({'rpg_main.no_mana'}), Color.fail)
  end

  local target_pos
  if object.target then
    target_pos = {position.x, position.y}
  elseif projectile_types[object.entityName] then
    local coord_modifier = get_near_coord_modifier(projectile_types[object.entityName].max_range)
    target_pos = {position.x + coord_modifier.x, position.y + coord_modifier.y}
  end

  local range
  if object.range then
    range = object.range
  else
    range = 0
  end

  local force
  if object.force then
    force = object.force
  else
    force = 'player'
  end


  if object.itam_code then
    local spell_success=false
    local spell_daoju=Spells.upgrade_spell(player, object.entityName, false)

    -- 通用 handler 调度：从 spells.lua 的 handlers 表查找对应函数
    local handler = Spells.handlers[object.entityName]
    if handler then
      if handler(position, surface, player, spell_daoju) then
        spell_success=true
      end
    end

    --重构位置
    if spell_success then
      Public.remove_mana(player, object.mana_cost)
      player.create_local_flying_text{
        text = {'rpg_main.object_spawned', object.name},
        color = Color.success,
        position = position,
        speed = 0.8
      }
      --p(({'rpg_main.object_spawned', object.name}), Color.success)
      Spells.upgrade_spell(player, object.entityName, true)

      -- 保存偏移
    else
      player.create_local_flying_text{
        text = {'itam_spells.fail'},
        color = Color.fail,
        position = position,
        speed = 0.8
      }
      --p(({'itam_spells.fail'}), Color.fail)
    end


    local msg = player.name .. ' casted ' .. object.entityName .. '. '

    rpg_t.last_spawned = game.tick + object.tick
    -- 保存相对于玩家的偏移量，而不是绝对位置
    local player_pos = player.physical_position
    local offset = {
      x = position.x - player_pos.x,
      y = position.y - player_pos.y
    }
    rpg_t.last_cast_position = offset
  Public.update_mana(player)

  return
  end

  if object.entityName == 'suicidal_comfylatron' then
    Public.suicidal_comfylatron(position, surface)
    p(({'rpg_main.suicidal_comfylatron', 'Suicidal Comfylatron'}), Color.success)
    Public.remove_mana(player, object.mana_cost)
  elseif object.entityName == 'repair_aoe' then
    local ents = Public.repair_aoe(player, position)
    p(({'rpg_main.repair_aoe', ents}), Color.success)
    Public.remove_mana(player, object.mana_cost)
  elseif object.entityName == 'pointy_explosives' then
    local entities =
    player.physical_surface.find_entities_filtered {
      force = player.force,
      type = 'container',
      area = {{position.x - 1, position.y - 1}, {position.x + 1, position.y + 1}}
    }

    local detonate_chest
    for i = 1, #entities do
      local e = entities[i]
      detonate_chest = e
    end
    if detonate_chest and detonate_chest.valid then
      local success = Explosives.detonate_chest(detonate_chest)
      if success then
        player.print(({'rpg_main.detonate_chest'}), Color.success)
        Public.remove_mana(player, object.mana_cost)
      else
        player.print(({'rpg_main.detonate_chest_failed'}), Color.fail)
      end
    end
  elseif object.entityName == 'warp-gate' then
    local this=WPT.get()
    local main_surface = game.surfaces[this.active_surface_index]
    local index = player.index
    local spawn_pos = game.forces.player.get_spawn_position(player.physical_surface)
    if player.physical_surface.index == main_surface.index then
     if this.silo and this.silo.valid then 
      player.teleport(main_surface.find_non_colliding_position('character',this.shop.position, 20, 1, false) or spawn_pos)
    end
    end
   
    if this.tank[index] and this.tank[index].valid and this.tank[index].surface==player.physical_surface then
      player.teleport(player.physical_surface.find_non_colliding_position('character', this.tank[player.index].position, 20, 1, false))
    else
      player.teleport(player.physical_surface.find_non_colliding_position('character', spawn_pos, 20, 1, false))
    end
  
    Public.remove_mana(player, 999999)
    Public.damage_player_over_time(player, math.random(8, 16))
    player.play_sound {path = 'utility/armor_insert', volume_modifier = 1}
    p(({'rpg_main.warped_ok'}), Color.info)
  elseif object.capsule then -- spawn in capsules i.e objects that are usable with mouse-click
    player.insert({name = object.entityName, count = object.amount})
    p(({'rpg_main.object_spawned', object.name}), Color.success)
    Public.remove_mana(player, object.mana_cost)
  elseif projectile_types[object.entityName] then -- projectiles
    for i = 1, object.amount do
      local damage_area = {
        left_top = {x = position.x - 2, y = position.y - 2},
        right_bottom = {x = position.x + 2, y = position.y + 2}
      }
      create_projectile(surface, projectile_types[object.entityName].name, position, force, target_pos, range,player)
      if object.damage then
        for _, e in pairs(surface.find_entities_filtered({area = damage_area})) do
          damage_entity(e)
        end
      end
    end
    p(({'rpg_main.object_spawned', object.name}), Color.success)
    Public.remove_mana(player, object.mana_cost)
  else
    if object.target then -- rockets and such
      surface.create_entity({name = object.entityName, position = position, force = force, target = target_pos, speed = 1})
      p(({'rpg_main.object_spawned', object.name}), Color.success)
      Public.remove_mana(player, object.mana_cost)
    elseif surface.can_place_entity {name = object.entityName, position = position} then
      if object.biter then
        local unit = surface.create_entity({name = object.entityName, position = position, force = force})
        pet.biter_pets_tame_unit(player, unit)
        Public.remove_mana(player, object.mana_cost)
        if object.entityName =='biter-spawner' or object.entityName =='spitter-spawner' then 
          local this=WPT.get()
          if not this.nest then this.nest ={} end
          --整理生成新的数组
          local new_nest={}
          for i ,v in pairs(this.nest) do 
            if v.valid then 
              new_nest[#new_nest+1]=v
            end
          end
          this.nest=new_nest
          if #this.nest >= this.max_nest_number then 
            this.nest[1].destroy()
            this.nest[1]=nil
          end 
          this.nest[#this.nest+1]=unit
        end

      local worm_name={
        ['small-worm-turret'] = true,
        ['medium-worm-turret'] = true,
        ['big-worm-turret'] = true,
        ['behemoth-worm-turret'] = true
      }
      if worm_name[object.entityName] then 
        local this=WPT.get()
        if not this.worm then this.worm ={} end
        --整理生成新的数组
        local new_nest={}
        for i ,v in pairs(this.worm) do 
          if v.valid then 
            new_nest[#new_nest+1]=v
          end
        end
        this.worm=new_nest
        if #this.worm >= this.max_worm_number then 
          this.worm[1].destroy()
          this.worm[1]=nil
        end 
        this.worm[#this.worm+1]=unit
      end


      elseif object.aoe then
        for x = 1, -1, -1 do
          for y = 1, -1, -1 do
            local pos = {x = position.x + x, y = position.y + y}
            if surface.can_place_entity {name = object.entityName, position = pos} then
              if object.mana_cost > rpg_t.mana then
                break
              end
              local e = surface.create_entity({name = object.entityName, position = pos, force = force})
              e.direction = player.character.direction
              Public.remove_mana(player, object.mana_cost)
            end
          end
        end
      else
        local e = surface.create_entity({name = object.entityName, position = position, force = force})
        e.direction = player.character.direction
        Public.remove_mana(player, object.mana_cost)
      end
      p(({'rpg_main.object_spawned', object.name}), Color.success)
    else
      p(({'rpg_main.out_of_reach'}), Color.fail)
      return
    end
  end

  local msg = player.name .. ' casted ' .. object.entityName .. '. '

  rpg_t.last_spawned = game.tick + object.tick
  -- 保存相对于玩家的偏移量，而不是绝对位置
  local player_pos = player.physical_position
  local offset = {
    x = position.x - player_pos.x,
    y = position.y - player_pos.y
  }
 
  rpg_t.last_cast_position = offset

  Public.update_mana(player)

  return
end



local function on_player_changed_surface(event)
  local player = game.get_player(event.player_index)
  Public.draw_level_text(player)
end

local function on_player_removed(event)
  Public.remove_player(event.player_index)
end

local function add_bullet()
  local this=WPT.get()

  for index,turret in pairs(this.turret_rpg) do
    if not turret.valid then
      this.turret_rpg[index]=nil
      break
    end

    local position=turret.position
    local count_all = turret.surface.count_entities_filtered{type=player_loader,position = position, radius = 5, force = "player"}

    if count_all ~=0 then
      turret.destroy()
      this.turret_rpg[index]=nil
    else
      local something = turret.get_inventory(defines.inventory.chest)
      local ammo_name
      for _, item_data in pairs(something.get_contents()) do
        ammo_name=item_data.name
      end
      if ammo_name then 
      turret.insert{name=ammo_name, count = 30}
      end

    end

  end
end

local function auto_skill(player)
  local use_event = {}
  
  local rpg_t = Public.get_value_from_player(player.index)
  if not rpg_t then
    return
  end
  
  -- 检测是否开启了魔法技能
  local enable_mana = Public.get('rpg_extra').enable_mana
  if not enable_mana then
    return
  end
  
  -- 检查是否开启了自动施法
  if not rpg_t.auto_cast_enabled then
    return
  end

    if not rpg_t.enable_entity_spawn then
    return
  end
  
  --检测是否在有效表面,并且不在异次元
 -- if player.physical_surface ~= game.surfaces['nauvis'] and not string.find(player.physical_surface.name, "yiciyuan") then
  --  return
  --end

  -- 获取当前选中的技能
  local conjure_items = Public.rebuild_spells()
  local object = conjure_items[rpg_t.dropdown_select_index]
  if not object then
    return
  end
  
  -- 检查魔力值是否足够
  if rpg_t.mana < object.mana_cost then
    return
  end
  
  -- 检查背包中是否有鱼
  local fish_count = player.get_item_count('raw-fish')
  if fish_count <= 0 then
    return
  end
  
  -- 消耗一条鱼
  player.remove_item({name = 'raw-fish', count = 1})
  
  -- 计算相对于玩家当前位置的绝对位置
  local player_pos = player.physical_position
  local relative_pos = {
    x = player_pos.x + rpg_t.last_cast_position.x,
    y = player_pos.y + rpg_t.last_cast_position.y
  }

  
  use_event.item = {name = 'raw-fish'}
  use_event.position = relative_pos
  use_event.player_index = player.index


  on_player_used_capsule(use_event)
  
  -- 调用天赋系统的on_player_used_capsule函数
  Tianfu.on_player_used_capsule(use_event)
  
end


local function tick()
  local ticker = game.tick
  local players = game.connected_players
  local count = #players
  local enable_mana = Public.get('rpg_extra').enable_mana

  if ticker % nth_tick == 0 then
    Public.global_pool(players, count)
  end

  if ticker % 30 == 0 then
    regen_health_player(players)
    if enable_mana then
      regen_mana_player(players)
    end
  end

  if ticker % 60 == 0 then
    add_bullet()
    --遍历所有在线玩家
    for _, player in pairs(players) do
      auto_skill(player)
    end
    -- 清理过期的小精灵
    Spells.cleanup_fairy_spirits()
    -- 在主循环中直接触发精灵闪电链
    Spells.trigger_all_fairy_lightning(players)
  end
end

Event.add(defines.events.on_pre_player_left_game, on_pre_player_left_game)
Event.add(defines.events.on_player_died, on_player_died)
Event.add(defines.events.on_entity_died, on_entity_died)
Event.add(defines.events.on_gui_click, on_gui_click)
Event.add(defines.events.on_player_changed_position, on_player_changed_position)
Event.add(defines.events.on_player_crafted_item, on_player_crafted_item)
Event.add(defines.events.on_player_joined_game, on_player_joined_game)
Event.add(defines.events.on_player_created, on_player_joined_game)
Event.add(defines.events.on_player_repaired_entity, on_player_repaired_entity)
Event.add(defines.events.on_player_respawned, on_player_respawned)
Event.add(defines.events.on_player_rotated_entity, on_player_rotated_entity)
Event.add(defines.events.on_pre_player_mined_item, on_pre_player_mined_item)
Event.add(defines.events.on_player_used_capsule, on_player_used_capsule)
Event.add(defines.events.on_player_changed_surface, on_player_changed_surface)
Event.add(defines.events.on_player_removed, on_player_removed)
Event.on_nth_tick(10, tick)



return Public