local map = {}
local Public = {}

local Global = require 'utils.global'
local WD = require 'modules.wave_defense.table'
local WPT = require 'maps.amap.table'
local Difficulty = require 'modules.difficulty_vote_by_amount'


Global.register(
map,
function(tbl)
  map = tbl
end
)

local function get_car_number()
  local this=WPT.get()
  local car_number=0

  for k, player in pairs(game.connected_players) do
    if  this.tank[player.index] and this.tank[player.index].valid then
      car_number=car_number+1
    end
  end
  return car_number
end

local function calc_players()
  local players = game.connected_players
  local check_afk_players = WPT.get('check_afk_players')
  if not check_afk_players then
    return #players
  end
  local total = 0
  for i = 1, #players do
    local player = players[i]
    if player.afk_time < 36000 then
      total = total + 1
    end
  end
  if total <= 0 then
    total = 1
  end
  return total
end

local function goal()
  local this = WPT.get()
  local wave_number = WD.get('wave_number')
  local goal=this.goal
  if goal == 2 and wave_number >=2000 then
    this.goal=3
    game.print({'amap.goal_2'})
    game.print({'amap.off_final_wave'})
    game.print({'amap.off_rocket_diff'})
  end
  if goal==3 and wave_number>=2605 and map.final_wave and  map.rocket_diff then
    this.goal=5
    map.final_wave=false
    map.final_wave_record[map.world]=true
    game.map_settings.enemy_expansion.settler_group_min_size =5
    game.map_settings.enemy_expansion.max_expansion_cooldown=216000
    game.map_settings.enemy_expansion.min_expansion_cooldown=14400
    game.print({'amap.finsh_world'})
  end

end

local final_wave = function()
  local wave_defense_table = WD.get_table()
  game.map_settings.enemy_expansion.settler_group_min_size = 50
  game.map_settings.enemy_expansion.min_expansion_cooldown=3600
  game.map_settings.enemy_expansion.max_expansion_cooldown=game.map_settings.enemy_expansion.min_expansion_cooldown
  wave_defense_table.wave_interval = 1200
end

local set_diff = function()

  local this = WPT.get()
  if this.start_game~=2 then
    return
  end

  local enemy = game.forces.enemy
  if  enemy.evolution_factor >= 0.5 and this.max_flame == 28 then
    this.max_flame=24
  end
  if  enemy.evolution_factor >= 0.9 and this.max_flame == 24 then
    this.max_flame=18
  end




  local diff_k=1
  local diff= Difficulty.get()
  if diff.difficulty_vote_index == 1 then
    diff_k=1
  end
  if diff.difficulty_vote_index == 2 then
    diff_k=1.2
  end
  if diff.difficulty_vote_index == 3 then
    diff_k=1.5
  end
  diff_k=diff_k+map.diff-1

  local wave_number = WD.get('wave_number')

  if  this.enable_wild_factorio and wave_number>=1300 then
    local production = WPT.get_production_table()
    for key, factory in pairs(production.assemblers) do
      local entity = factory.entity
      if entity and entity.valid then
        entity.destructible = true
        entity.die()
      end
    end
    this.productionsphere.experience = {}
    this.productionsphere.assemblers = {}
    this.enable_wild_factorio =false
    game.print({"amap.biter_kill_factorio"})
  end

  local car_number=get_car_number()
  local allow_car_number = math.floor(#game.connected_players/3)+1
  local allow_die_number = math.floor(wave_number*0.03)+3

    if allow_car_number>4 then allow_car_number=4 end

  if this.car_die_number>=allow_die_number and car_number <=allow_car_number then

    diff_k=this.car_die_number*0.2+diff_k
    local k =game.forces.enemy.evolution_factor*1000
    if k >wave_number then
      wave_number=k
    end
  end

  if wave_number>=2000 and map.rocket_diff then
    diff_k=diff_k+this.times*0.015
  end
  goal()

  local player_count = calc_players()
  local wave_defense_table = WD.get_table()

  wave_defense_table.max_active_biters = 768 + player_count * 180*diff_k

  if wave_defense_table.max_active_biters >= 4000*diff_k then
    wave_defense_table.max_active_biters = 4000*diff_k
  end

  local max_threat = 1 + player_count * 0.1*diff_k
  if max_threat >= 4*diff_k then
    max_threat = 4*diff_k
  end

  max_threat = max_threat + wave_number * 0.0013*diff_k

  WD.set_biter_health_boost(wave_number * 0.002*diff_k+1*diff_k)
  wave_defense_table.threat_gain_multiplier =  max_threat

  wave_defense_table.wave_interval = 4200/diff_k - player_count * 50*diff_k
  if wave_defense_table.wave_interval < 1800/diff_k or wave_defense_table.threat <= 0 then
    wave_defense_table.wave_interval = 1800/diff_k
  end



  local  damage_increase = wave_number * 0.001*diff_k*1.3
  game.forces.enemy.set_ammo_damage_modifier("artillery-shell", damage_increase)
  game.forces.enemy.set_ammo_damage_modifier("melee", damage_increase)
  game.forces.enemy.set_ammo_damage_modifier("biological", damage_increase)
  if  map.final_wave and wave_number>2000 then final_wave() end
end

function Public.reset_table()
  map.sum=0
  map.win=0
  map.gg=0

  map.diff=1

  map.world=1
  map.max_world=1
  map.world_number=4

  map.record_number=2
  map.record={}
  map.color={}
  map.text={}
  map.record[1]={}

  map.record[1].name="aceshotter"
  map.record[1].pass_number=366
  map.record[1].wave_number=367

  map.record[2]={}
  map.record[2].name="noneofone"
  map.record[2].pass_number=1217
  map.record[2].wave_number=2605
  --
  -- map.record[3]={}
  --   map.record[3].name="itam"
  --   map.record[3].pass_number=0
  --   map.record[3].wave_number=500


  map.map_record={}

  map.final_wave=true
  map.final_wave_record={
    [1]=false,
    [2]=false,
    [3]=false,
    [4]=false,
    [5]=false,
    [6]=false,
  }

  map.rocket_diff=true
end


commands.add_command(
'off_final_wave',
'off_final_wave,if you affid biter',
function()
  local player = game.player
  if player then
    if player ~= nil then
      p = player.print
      if not player.admin then
        p({'amap.no_amdin'})
        return
      end
      map.final_wave=false
      game.map_settings.enemy_expansion.settler_group_min_size =5
      game.map_settings.enemy_expansion.max_expansion_cooldown=104000
      p({'amap.off_final_wave_over'})
    end
  end
end
)


commands.add_command(
'off_rocket_diff',
'off_rocket_diff,to adoive the game too hard',
function()
  local player = game.player
  if player then
    if player ~= nil then
      p = player.print
      if not player.admin then
        p({'amap.no_amdin'})
        return
      end
      map.rocket_diff=false
      p({'amap.off_rocket_diff_over'})
    end
  end
end
)

local on_init = function()
  Public.reset_table()
end

function Public.get(key)
  if key then
    return map[key]
  else
    return map
  end
end

local function changer_color()
  for k,player in pairs(map.color) do
    if  player.character and  player.character.valid then
      if not map.text[player.index] then
        map.text[player.index] =
        rendering.draw_text {
          text = '[ 单通玩家 ]',
          surface = player.surface,
          target = player.character,
          target_offset = {0, -3.65},
          color = {
            r = player.color.r * 0.6 + 0.25,
            g = player.color.g * 0.6 + 0.25,
            b = player.color.b * 0.6 + 0.25,
            a = 1
          },
          players = players,
          scale = 1.00,
          font = 'default-large-semibold',
          alignment = 'center',
          scale_with_zoom = false
        }
      end
      if not rendering.is_valid(map.text[player.index]) then
        rendering.destroy(map.text[player.index])
        map.text[player.index]=nil
      end
    end
  end
end

local function on_player_joined_game(event)
  local player = game.players[event.player_index]
  for k,v in pairs(map.record) do
    if  player.name==v.name then
      map.color[#map.color+1]=player
      game.print({'amap.dalao_join',player.name},{math.random(0,255),math.random(0,255),math.random(0,255)})
    end
  end
  changer_color()
end

local function on_pre_player_left_game(event)
  local player = game.players[event.player_index]
  for k, p in pairs(map.color) do
    if player.name == p.name then
      map.color[k]=nil
    end
  end
end

-- local function on_player_respawned(event)
--    changer_color()
-- end

local Event = require 'utils.event'
Event.on_init(on_init)
Event.on_nth_tick(600, set_diff)
Event.on_nth_tick(600, changer_color)
--Event.add(defines.events.on_player_respawned, on_player_respawned)
Event.add(defines.events.on_player_joined_game, on_player_joined_game)
Event.add(defines.events.on_pre_player_left_game, on_pre_player_left_game)
return Public
