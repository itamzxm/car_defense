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

local function make_game_mode()

  local diff= Difficulty.get()
    if diff.difficulty_vote_index~=1 then return end

    local wave_defense_table = WD.get_table()

    wave_defense_table.wave_number=math.floor(game.forces.enemy.evolution_factor*1000)

    if game.forces.enemy.evolution_factor >0.9 then

      diff.difficulty_vote_index=2
      wave_defense_table.game_lost = false
      wave_defense_table.wave_number=900

      local this = WPT.get()
      this.stop_time=60

      game.map_settings.enemy_expansion.max_expansion_cooldown=216000
      game.map_settings.enemy_expansion.min_expansion_cooldown=14400
      game.map_settings.enemy_expansion.max_expansion_distance = 20
      game.map_settings.enemy_expansion.settler_group_min_size = 5
      game.map_settings.enemy_expansion.settler_group_max_size = 50

    end

  if game.tick < diff.difficulty_poll_closing_timeout then return end
  if diff.difficulty_vote_index~=1 then return end
    wave_defense_table.game_lost = true

    game.map_settings.enemy_expansion.max_expansion_cooldown=14400
    game.map_settings.enemy_expansion.min_expansion_cooldown=14400
    game.map_settings.enemy_expansion.max_expansion_distance = 20
    game.map_settings.enemy_expansion.settler_group_min_size = 20
    game.map_settings.enemy_expansion.settler_group_max_size = 50

  end



local set_diff = function()

  local this = WPT.get()

  --make_game_mode()

  local enemy = game.forces.enemy
  if  enemy.evolution_factor >= 0.5 and this.max_flame == 32 then
    this.max_flame=28
  end
  if  enemy.evolution_factor >= 0.9 and this.max_flame == 28 then
    this.max_flame=24
  end

  local diff_k=1
  local diff= Difficulty.get()
  if diff.difficulty_vote_index == 1 then
    diff_k=1
  end
  if diff.difficulty_vote_index == 2 then
    diff_k=1.3
  end
  if diff.difficulty_vote_index == 3 then
    diff_k=1.6
  end

 --if not this.player_diff[this.car_index] then return  end
 -- diff_k=diff_k+this.player_diff[this.car_index]

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


  if wave_number>=2000 and map.rocket_diff then
    diff_k=diff_k+this.times*0.015
  end
  goal()

  local player_count = calc_players()
  local wave_defense_table = WD.get_table()

  wave_defense_table.max_active_biters = 768 + player_count * 180*diff_k

  if wave_defense_table.max_active_biters >= 6000*diff_k then
    wave_defense_table.max_active_biters = 6000*diff_k
  end

  local max_threat = 1 + player_count * 0.1*diff_k
  if max_threat >= 4*diff_k then
    max_threat = 4*diff_k
  end

--限制总最大值
  if wave_number>5000 then wave_number = 5000 end

  max_threat = max_threat + wave_number * 0.0013*diff_k
  WD.set_biter_health_boost(wave_number * 0.002*diff_k+1*diff_k)
  wave_defense_table.threat_gain_multiplier =  max_threat

  wave_defense_table.wave_interval = 4200/diff_k - player_count * 60
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

  map.pay_coin=8
  map.pay_xp=2

  map.world=1
  map.max_world=5
  map.world_number=5

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
  map.record[2].wave_number=3000
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
    if player.connected then
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
    else
      player=nil
      map.color[k]=nil
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



local Event = require 'utils.event'
Event.on_init(on_init)
Event.on_nth_tick(600, set_diff)
Event.on_nth_tick(600, changer_color)
--Event.add(defines.events.on_player_respawned, on_player_respawned)
Event.add(defines.events.on_player_joined_game, on_player_joined_game)

return Public
