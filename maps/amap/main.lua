local Public = {}

local floor = math.floor
--hi guy!
local reset_pos=require'stronghold_generation_algorithm_v2'.reset_table
local Factories = require 'maps.amap.production'
local RPG = require 'modules.rpg.main'
local PL = require 'comfy_panel.player_list'
local Functions = require 'maps.amap.functions'
local IC = require 'maps.amap.ic.table'
local CS = require 'maps.amap.surface'
local Balance = require 'maps.amap.balance'
local Event = require 'utils.event'
local ICMinimap = require 'maps.amap.ic.minimap'
local WD = require 'modules.wave_defense.table'
local Map = require 'modules.map_info'
local AntiGrief = require 'antigrief'.get()
local WPT = require 'maps.amap.table'
local Autostash = require 'modules.autostash'
local BottomFrame = require 'comfy_panel.bottom_frame'
local rock = require 'maps.amap.rock'
local Loot = require'maps.amap.loot'
local Modifiers = require 'player_modifiers'
local Difficulty = require 'modules.difficulty_vote_by_amount'
local arty = require "maps.amap.enemy_arty"
local BiterHealthBooster = require 'modules.biter_health_booster_v2'


local player_build = {
  'steam-turbine',
  'assembling-machine-1',
  'assembling-machine-2',
  'assembling-machine-3',
  'oil-refinery',
  'chemical-plant',
  'car',
  'spidertron',
  'tank',
  'character',
  'gun-turret',
  'electric-mining-drill',
  'laser-turret',
  'steam-engine',
  'roboport',
}

require 'maps.amap.mining'
require 'maps.amap.auto_put_turret'
require 'maps.amap.world.world_main'
require 'maps.amap.gui'
require 'maps.amap.biter_die'


require 'maps.amap.ic.main'
require 'maps.amap.biters_yield_coins'
require 'maps.amap.tank'

require 'modules.shotgun_buff'
require 'modules.no_deconstruction_of_neutral_entities'
require 'modules.wave_defense.main'
require 'modules.charging_station'


local init_new_force = function()
  local new_force = game.forces.protectors
  local enemy = game.forces.enemy
  if not new_force then
    new_force = game.create_force('protectors')
  end
  new_force.set_friend('enemy', true)
  enemy.set_friend('protectors', true)
end

local setting = function()
  AntiGrief.enabled=false
  game.forces.enemy.ghost_time_to_live = 5 * 60 * 60
  -- game.map_settings.enemy_evolution.destroy_factor = 0.002
  game.forces.enemy.technologies['construction-robotics'].researched = true
  game.forces.enemy.worker_robots_speed_modifier=3
  game.forces.enemy.stack_inserter_capacity_bonus=100
  game.map_settings.enemy_expansion.enabled = true
  -- game.map_settings.enemy_expansion.max_expansion_cooldown=216000
  -- game.map_settings.enemy_expansion.min_expansion_cooldown=14400
  -- game.map_settings.enemy_expansion.max_expansion_distance = 20
  -- game.map_settings.enemy_expansion.settler_group_min_size = 5
  -- game.map_settings.enemy_expansion.settler_group_max_size = 50
  game.forces.enemy.friendly_fire = false
--  game.forces.player.set_ammo_damage_modifier("artillery-shell", 0)
  --game.forces.player.set_ammo_damage_modifier("melee", 0)
--  game.forces.player.set_ammo_damage_modifier("biological", 0)
--game.forces.player.set_ammo_damage_modifier("rocket", 0)

end

function Public.reset_map()

  local this = WPT.get()
  local wave_defense_table = WD.get_table()

  this.active_surface_index = CS.create_surface()
  IC.reset()
  IC.allowed_surface(game.surfaces[this.active_surface_index].name)
  Autostash.insert_into_furnace(true)
  Autostash.bottom_button(true)

  BottomFrame.reset()
  BottomFrame.activate_custom_buttons(true)

  reset_pos()
  game.reset_time_played()
  WPT.reset_table()
  arty.reset_table()

  RPG.rpg_reset_all_players()
  RPG.set_surface_name(game.surfaces[this.active_surface_index].name)
  RPG.enable_health_and_mana_bars(true)
  RPG.enable_wave_defense(false)
  RPG.enable_mana(true)
  RPG.enable_flame_boots(true)
  RPG.personal_tax_rate(0.4)
  RPG.enable_stone_path(true)
  RPG.enable_one_punch(true)
  RPG.enable_one_punch_globally(false)
  RPG.enable_auto_allocate(true)
  RPG.disable_cooldowns_on_spells()
  RPG.enable_explosive_bullets_globally(true)
  RPG.enable_explosive_bullets(true)


  local Diff = Difficulty.get()
  Difficulty.reset_difficulty_poll({difficulty_poll_closing_timeout = game.tick + 36000})
  Diff.gui_width = 20

  local surface = game.surfaces[this.active_surface_index]
  game.forces.player.set_spawn_position({0, 0}, surface)

  rock.market(surface)
  rock.ft(surface)
  game.forces.player.set_spawn_position({0, 0}, surface)

  PL.show_roles_in_list(true)
  PL.rpg_enabled(true)

  local players = game.connected_players
  for i = 1, #players do
    local player = players[i]
    Modifiers.reset_player_modifiers(player)
    ICMinimap.kill_minimap(player)
  end



  WD.reset_wave_defense()

  wave_defense_table.surface_index = this.active_surface_index
  wave_defense_table.nest_building_density = 32
  wave_defense_table.game_lost = false

  WD.alert_boss_wave(true)
  WD.clear_corpses(false)
  WD.remove_entities(true)
  WD.enable_threat_log(false)
  WD.increase_damage_per_wave(false)
  WD.increase_health_per_wave(false)
  WD.increase_boss_health_per_wave(false)
  WD.set_disable_threat_below_zero(true)
  WD.set_biter_health_boost(1.4)
  WD.increase_boss_health_per_wave(false)
  WD.set().next_wave = game.tick +7200* 15*2



  BiterHealthBooster.reset_table()
  BiterHealthBooster.set_active_surface(tostring(surface.name))

  Balance.init_enemy_weapon_damage()
  Functions.disable_tech()

  init_new_force()
  setting()

  local world_number=require 'maps.amap.diff'.get("world")
  if world_number == 3 then
    game.forces.player.technologies['landfill'].enabled = true
  end
end

local on_init = function()
  Public.reset_map()

  local tooltip = {
    [1] = ({'amap.easy'}),
    [2] = ({'amap.med'}),
    [3] = ({'amap.hard'})
  }
  Difficulty.set_tooltip(tooltip)

  -- local Diff = Difficulty.get()
  -- Diff.difficulties[1].name="宝宝模式-baby_mode"
  -- Diff.difficulties[2].name="简单模式_easy_mode"
  -- Diff.difficulties[3].name="团队合作_norml_mode"

  game.forces.player.research_queue_enabled = true
  local T = Map.Pop_info()
  T.localised_category = 'amap'
  T.main_caption_color = {r = 150, g = 150, b = 0}
  T.sub_caption_color = {r = 0, g = 150, b = 0}
end

local function no_point(player,k)

  local money = 1000+1000*k
  local can_remove=false
  local something = player.get_inventory(defines.inventory.chest)
  for k, v in pairs(something.get_contents()) do
    if k=='coin' and v >= money then
      can_remove=true
    end
  end
  if can_remove then
    player.print({'amap.nopoint',money})
    player.remove_item{name='coin', count = money}

  else
    local rpg_t = RPG.get('rpg_t')
    local get_xp = 100+k*50
    rpg_t[player.index].xp = rpg_t[player.index].xp -get_xp
    player.print({'amap.lost_xp',get_xp})
  end
end

local wheel = function(player,many)
  if not player.character or not player.character.valid then return end
  if many >= 500 then
    many = 500
  end
  local rpg_t = RPG.get('rpg_t')
  local q = math.random(1,18)
  local k = math.floor(many/100)
  local get_point = k*5+5
  if get_point >= 25 then
    get_point = 25
  end
  if q ==18 then
    local get_xp = 100+k*50
    rpg_t[player.index].xp = rpg_t[player.index].xp -get_xp
    player.print({'amap.lost_xp',get_xp})
    return
  end
  if q == 17 then
    if rpg_t[player.index].magicka < (get_point+10) then
      no_point(player,k)
      return
    else
      rpg_t[player.index].magicka =rpg_t[player.index].magicka -get_point
      player.print({'amap.nb16',get_point+10})
      return
    end
  end
  if q == 16 then
    if rpg_t[player.index].dexterity < (get_point+10) then
      no_point(player,k)
      return
    else
      rpg_t[player.index].dexterity = rpg_t[player.index].dexterity - get_point
      player.print({'amap.nb17',get_point})
      return
    end
  end
  if q == 15 then
    if rpg_t[player.index].vitality < (get_point+10) then
      no_point(player,k)
      return
    else
      rpg_t[player.index].vitality = rpg_t[player.index].vitality -get_point
      player.print({'amap.nb18',get_point})
      return
    end
  end
  if q == 14 then
    if rpg_t[player.index].strength < (get_point+10) then
      no_point(player,k)
      return
    else
      rpg_t[player.index].strength = rpg_t[player.index].strength -get_point
      player.print({'amap.nb15',get_point})
      return
    end
  end
  if q == 13 then
    local luck = 50*k+50
    if luck >= 400 then
      luck = 400
    end
    Loot.cool(player.surface, player.surface.find_non_colliding_position("steel-chest", player.position, 20, 1, true) or player.position, 'steel-chest', luck)
    player.print({'amap.nb14',luck})
    return
  elseif q == 12 then
    local get_xp = 100+k*50
    rpg_t[player.index].xp = rpg_t[player.index].xp +get_xp
    player.print({'amap.nb12',get_xp})
    return
  elseif q == 11 then
    local amount = 10+10*k
    player.insert{name='distractor-capsule', count = amount}
    player.print({'amap.nb11',amount})
    return
  elseif q == 10 then
    local amount = 100+100*k
    player.insert{name='raw-fish', count = amount}
    player.print({'amap.nb10',amount})
    return
  elseif q == 9 then
    player.insert{name='raw-fish', count = '1'}
    player.print({'amap.nb9'})
    return
  elseif q == 8 then
    rpg_t[player.index].strength = rpg_t[player.index].strength + get_point
    player.print({'amap.nb6',get_point})
    return
  elseif q == 7 then
    player.print({'amap.nb5',get_point})
    rpg_t[player.index].magicka =rpg_t[player.index].magicka +get_point
    return
  elseif q == 6 then
    player.print({'amap.nb4',get_point})
    rpg_t[player.index].dexterity = rpg_t[player.index].dexterity+get_point
    return
  elseif q == 5 then
    player.print({'amap.nb3',get_point})
    rpg_t[player.index].vitality = rpg_t[player.index].vitality+get_point
    return
  elseif q == 4 then
    player.print({'amap.nb2',get_point})
    rpg_t[player.index].points_left = rpg_t[player.index].points_left+get_point
    return
  elseif q == 3 then
    local money = 1000+1000*k
    player.print({'amap.nbone',money})
    player.insert{name='coin', count = money}
    return
  elseif q == 2 then
    local money = 1000+1000*k
    player.print({'amap.sorry',money})
    player.remove_item{name='coin', count = money}
    return
  elseif q == 1 then
    player.print({'amap.what'})
    return

  end
end

local wheel_destiny = function()
  local this = WPT.get()
  local last = this.last
  local wave_number = WD.get('wave_number')
  if last < wave_number then
    if wave_number % 25 == 0 then
      game.print({'amap.roll'},{r = 0.22, g = 0.88, b = 0.22})
      for k, player in pairs(game.connected_players) do
        wheel(player,wave_number)
        k=k+1
      end
      this.last = wave_number
    end
  end
end


local gain_xp = function()
  local this = WPT.get()
  local wave_number = WD.get('wave_number')
  if wave_number > this.number then
    local rpg_t = RPG.get('rpg_t')
    for k, player in pairs(game.connected_players) do
      rpg_t[player.index].xp = rpg_t[player.index].xp + 15
    end
    this.number = wave_number
  end
end

local function get_biter_point ()
  local this = WPT.get()

  local wave_defense_table = WD.get_table()
  if this.roll >= 5 then
    this.roll = 1
  end
  local roll = this.roll
  this.roll=this.roll+1
  if not wave_defense_table.target  then return end
  if not wave_defense_table.target.valid  then return end
  local entity= wave_defense_table.target
  local position=entity.position
  local surface=entity.surface
  local temp_pos
  local k = roll
  local juli = 40
  if k==1 then
    temp_pos={x=position.x+juli,y=position.y+juli}
  end
  if k==2 then
    temp_pos={x=position.x-juli,y=position.y+juli}
  end
  if k==3 then
    temp_pos={x=position.x+juli,y=position.y-juli}
  end
  if k==4 then
    temp_pos={x=position.x-juli,y=position.y-juli}
  end

  local entities = surface.find_entities_filtered{position = temp_pos, radius = juli, name = player_build , force = game.forces.player,limit =1}
  while #entities ~=0  do
    if k==1 then
      temp_pos={x=temp_pos.x+juli,y=temp_pos.y+juli}
    end
    if k==2 then
      temp_pos={x=temp_pos.x-juli,y=temp_pos.y+juli}
    end
    if k==3 then
      temp_pos={x=temp_pos.x+juli,y=temp_pos.y-juli}
    end
    if k==4 then
      temp_pos={x=temp_pos.x-juli,y=temp_pos.y-juli}
    end
    entities=surface.find_entities_filtered{position = temp_pos, radius = juli, name = player_build , force = game.forces.player,limit =1}
  end
  wave_defense_table.spawn_position = temp_pos
end


local on_tick = function()
  local tick = game.tick
  local this = WPT.get()
  if tick % 60 == 0 then
    Factories.produce_assemblers()
    if this.start_game ==2 then
      wheel_destiny()
      gain_xp()
    end
  end

  if tick % 600 == 0 then
    if this.enable_wild_factorio then
      Factories.check_activity()
    end
    get_biter_point()
  end
  if tick % 54000 == 0 then
    if this.start_game~=2 then return end
    local wave_number = WD.get('wave_number')
    if wave_number<1 then return end
    if this.enable_wild_factorio then
      Factories.jump_procedure()
    end
  end

end



Event.add_event_filter(defines.events.on_entity_damaged, {filter = 'final-damage-amount', comparison = '>', value = 0})
Event.on_init(on_init)
Event.on_nth_tick(60, on_tick)

return Public
