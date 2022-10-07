local Public = {}

local Event = require 'utils.event'
local WPT = require 'maps.amap.table'
local Rand = require 'maps.amap.random'
local WD = require 'modules.wave_defense.table'
local RPG = require 'modules.rpg.table'
local diff=require 'maps.amap.diff'
local Alert = require 'utils.alert'
local refresh_shop=require 'maps.amap.rock'.refresh_shop

local car_weiht={
  ["car"]=10,
  ["tank"]=60,
  ["spidertron"]=300
}


local world_name ={
  [1]={'amap.world_name_1'},
  [2]={'amap.world_name_2'},
  [3]={'amap.world_name_3'},
  [4]={'amap.world_name_4'},
  [5]={'amap.world_name_5'},
  [6]={'amap.world_name_6'},
}

local starting_items = {
  ['submachine-gun'] = 1,
  ['firearm-magazine'] = 30,
  ['wood'] = 16,
  ['car']=1,
}

local steal_oil = {
  'assembling-machine-1',
  'assembling-machine-2',
  'assembling-machine-3',
  'oil-refinery',
  'chemical-plant',
  'pipe',
  'pipe-to-ground',
  'pump',
  'storage-tank',
  'flamethrower-turret',
}

local player_build = {
  ['steam-turbine']=true,
  ['assembling-machine-1']=true,
  ['assembling-machine-2']=true,
  ['assembling-machine-3']=true,
  ['oil-refinery']=true,
  ['chemical-plant']=true,
  ['gun-turret']=true,
  ['electric-mining-drill']=true,
  ['laser-turret']=true,
  ['steam-engine']=true,
  ['roboport']=true,
}

function Public.get_player_data(player, remove_user_data)
  local players = WPT.get('players')
  if remove_user_data then
    if players[player.index] then
      players[player.index] = nil
    end
  end
  if not players[player.index] then
    players[player.index] = {}
  end
  return players[player.index]
end

local get_player_data = Public.get_player_data


local function get_car_number()
  local this=WPT.get()
  local car_number=0

  for k, player in pairs(game.connected_players) do
    if  this.tank[player.index] and this.tank[player.index].valid then
      car_number=car_number+1
      this.tank[player.index].destructible=true
    else
      this.tank[player.index]=nil
      this.whos_tank[player.index]=nil
      this.have_been_put_tank[player.index]=false
    end
  end
  return car_number
end


local function clac_time_weights()
  local this=WPT.get()
  if this.start_game~=2 then return end
  for k, player in pairs(game.connected_players) do
    if  this.tank[player.index] and this.tank[player.index].valid then
      local index = player.index
      local car =this.tank[player.index]
      if  this.car_pos[index]==nil then
        this.car_pos[index]=car.position
        this.time_weights[index]=0

      else
        if  this.tank[player.index].name == "spidertron"then
          this.time_weights[index]=150
        else

          local x = this.car_pos[index].x-car.position.x
          local y = this.car_pos[index].y-car.position.y
          local dist =x*x+y*y

          if dist > 3025 then
            this.car_pos[index]=car.position
            this.time_weights[index]=0
          else
            this.time_weights[index]=this.time_weights[index]+15
            this.car_pos[index]=car.position

            if   this.time_weights[index] >= 150 then
              this.time_weights[index]=150
            end
          end

        end
      end
    end
  end
end


local function out_info(player)
  local map = diff.get()
  player.print({'amap.game_shuju',map.sum,map.win,map.gg,map.diff})
  player.print({'amap.map_shuju',world_name[map.world],map.final_wave_record[map.world],map.max_world,map.world_number})
  local best_record = map.map_record[map.world]
  if best_record == nil then best_record=0 end
  player.print({'amap.best_record',best_record})
  for i=1,map.record_number do
    player.print({'amap.game_record',map.record[i].wave_number,map.record[i].name,map.record[i].pass_number})
  end
end

function Public.game_info()
  for k, player in pairs(game.connected_players) do
    out_info(player)
  end
end

local function get_car_index()
  local all_cars={}
  local spider_cars={}
  local rpg_t = RPG.get('rpg_t')
  local this= WPT.get()
  for k, player in pairs(game.connected_players) do
    if  this.tank[player.index] and this.tank[player.index].valid then

      local car = this.tank[player.index]
      local base_weight=car_weiht[car.name]
      if this.had_sipder[player.index]==true then
        base_weight=360
      end
      --   game.print("基础权重为: " .. base_weight .. '')
      if this.car_pos[player.index] and car then
        local x = this.car_pos[player.index].x-car.position.x
        local y = this.car_pos[player.index].y-car.position.y
        local dist =x*x+y*y

        if dist > 3025 then
          this.car_pos[player.index]=car.position
          this.time_weights[player.index]=0
        end
      end

      local time_weight=0
      if this.time_weights[player.index] then
        time_weight=this.time_weights[player.index]
      end

      if this.had_sipder[player.index] then
        time_weight=150
      end

      if not this.nest_wegiht[player.index] then
        this.nest_wegiht[player.index]=0
      end

      local rpg_weight = rpg_t[player.index].level*2
      local nest_wegiht= this.nest_wegiht[player.index]*2
      local all_weight = base_weight+time_weight+rpg_weight+nest_wegiht
      --   game.print("总权重为: " .. all_weight .. '')

      local id = #all_cars+1
      all_cars[id]={}
      all_cars[id].index=player.index
      all_cars[id].weight=all_weight
      local sipder_id=#spider_cars+1
      if this.had_sipder[player.index] then
        spider_cars[sipder_id]={}
        spider_cars[sipder_id].index=player.index
        spider_cars[sipder_id].weight=all_weight
      end
    end
  end

  if #spider_cars~=0 then
    local k_rand
    k_rand=math.random(1, 3)
    if k_rand ==1 then
      all_cars=spider_cars
    end

  end

  local choices = {indexs = {}, weights = {}}
  for _, car in pairs(all_cars) do
    table.insert(choices.indexs, car.index)
    table.insert(choices.weights, car.weight)
  end
  --  game.print("总随机成员 " .. #all_cars .. '')
  return Rand.raffle(choices.indexs, choices.weights)
end



function Public.get_random_car(print)

  local this=WPT.get()
  local index = get_car_index()
  --   game.print("随机结果为:" .. index .. '')
  if print then
    local name=game.players[index].name
    game.print(({'amap.car_will_attack',name}),{r=255,b=100,g=100})
    this.car_index=index
    this.diff_change=0
    this.diff_roll=0
    if this.last_sipder then
      if this.tank[this.last_sipder] then
        if this.tank[this.last_sipder].name  =="spidertron" then
          this.tank[this.last_sipder].grid.inhibit_movement_bonus=false
        else
          this.last_sipder =nil
        end
      end
    else
      this.last_sipder =nil
    end
    if this.tank[index].name=="spidertron" and get_car_number()<=3 then

      this.tank[index].grid.inhibit_movement_bonus=true
      this.last_sipder=index
      game.players[index].print(({'amap.reduce_sipder_speed'}),{r=0,b=255,g=255})
    end
  end
  return this.tank[index]
end


function Public.protect_car(index)
  local this=WPT.get()
  local name=game.players[index].name
  if not this.protect_car_time[index] then this.protect_car_time[index] =0 end

  local tick = game.tick

  if tick - this.protect_car_time[index]  > 108000*2 then


    local wave_defense_table = WD.get_table()
    wave_defense_table.game_lost = true

    this.stop_time=this.stop_time+108000*0.5
    game.print({'amap.buy_stop_wave',name,this.stop_time/3600})

    if not wave_defense_table.target  then return end
    if not wave_defense_table.target.valid  then return end

    local target= wave_defense_table.target
    local surface=target.surface

    for i=1,20 do
      surface.create_entity(
      {
        name ='destroyer-capsule' ,
        position = target.position,
        force = 'player',
        source = target,
        target = target,
        speed = 1
      }
)
    end

    game.print(({'amap.protect_car',name}),{r=255,b=100,g=100})
    this.protect_car_time[index]=tick
  end
end



function Public.get_player_diff()
  local this=WPT.get()
  local wave_number = WD.get('wave_number')
  
  if this.start_game~=2 then return end
  if not this.player_diff[this.car_index] then
    this.player_diff[this.car_index]=0
  end

  local allow_desy

  if wave_number <10 then
    allow_desy = 200
  else
    allow_desy=math.floor(wave_number)
  end

  if allow_desy>1000 then
    allow_desy=1000
  end

  --game.print("允许破坏zhi为"..allow_desy)


  if this.diff_wave<wave_number then

  if this.diff_roll==3 then
     this.diff_change=0
  end

  this.diff_roll=this.diff_roll+1
  this.diff_wave=wave_number
  this.player_diff[this.car_index]=  this.player_diff[this.car_index]+0.0015

  if  this.player_diff[this.car_index] >=2.5 then
    this.player_diff[this.car_index]=2.5
  end
  end

  --game.print("破坏zhi为".. this.diff_change )
  if this.diff_change > allow_desy then
    this.player_diff[this.car_index]=this.player_diff[this.car_index]-0.3
    Public.protect_car(this.car_index)
    Public.get_random_car(true)
    this.diff_change=0
      this.diff_roll=0

  end
end

local function get_base_biter()
  local this=WPT.get()
  local main_surface= game.surfaces[this.active_surface_index]
  if not main_surface then return false end
  local entities = main_surface.find_entities_filtered{position=game.forces.player.get_spawn_position(main_surface), radius = 50 , force = game.forces.enemy}
  if #entities == 0 then
    return false
  else
    return true
  end
end

function Public.on_player_joined_game(event)
  local active_surface_index = WPT.get('active_surface_index')
  local player = game.players[event.player_index]
  local surface = game.surfaces[active_surface_index]
  local player_data = get_player_data(player)
  if not player_data.first_join then

    for item, amount in pairs(starting_items) do
      player.insert({name = item, count = amount})
    end
    local rpg_t = RPG.get('rpg_t')
    local wave_number = WD.get('wave_number')
    local this = WPT.get()

    for i=1,this.science do
      local point = math.random(1,5)
      local coin = math.random(1,100)

      rpg_t[player.index].points_left = rpg_t[player.index].points_left+point
      player.insert{name='coin', count = coin}
    end
    this.nest_wegiht[player.index]=0
    rpg_t[player.index].xp = rpg_t[player.index].xp + wave_number*10
    player_data.first_join = true
    --    player.print({'amap.joingame'})
    out_info(player)
  end

  local this=WPT.get()
  local index = player.index
  local main_surface = game.surfaces[this.active_surface_index]
  if player.surface.index ~= active_surface_index then
    if  this.tank[index] and this.tank[index].valid then
      player.teleport(main_surface.find_non_colliding_position('character', this.tank[player.index].position, 20, 1, false) or {x=0,y=0}, main_surface)
    else
      player.teleport(surface.find_non_colliding_position('character', game.forces.player.get_spawn_position(surface), 20, 1, false) or {x=0,y=0}, surface)
    end

  end
end


local function on_player_mined_entity(event)
  if not event.entity then return end
  if not event.entity.valid then return end
  local this = WPT.get()
  if	not(event.entity.surface.index == game.surfaces[this.active_surface_index].index) then return end
  local name = event.entity.name
  local force = event.entity.force

  if force.index == game.forces.player.index then

    if name =="artillery-wagon" or name =="artillery-turret" then
      local unit_number=event.entity.unit_number
      if not this.water_arty then
        this.water_arty={}
      else
        if this.water_arty[unit_number] then
          this.water_arty[unit_number] =nil
        end
      end
      return
    end

    if name == 'flamethrower-turret' then
      this.flame = this.flame - 1
      if this.flame <= 0 then
        this.flame = 0
      end
      return
    end

    if name == 'land-mine' then
      this.now_mine = this.now_mine - 1
      if this.now_mine <= 0 then
        this.now_mine = 0
      end
      return
    end
  end

end



local function clean_flame_table ()
  local this = WPT.get()
  for k,v in pairs(this.player_flame) do
    for index,turret in pairs(v.turret) do
      if not turret.valid then
        this.player_flame[k].turret[index]=nil
        this.player_flame[k].number = this.player_flame[k].number-1
        if this.player_flame[k].number==0 then
          this.player_flame[k]=nil
        end
      end
    end
  end
end

local function kill_turret (index,player)
  local this = WPT.get()
  local number_player=0

  local max_number = 0
  for k,v in pairs(this.player_flame) do
    if v then
      if v.number > 0 then
        number_player=number_player+1
        if v.number >max_number then
          max_number=v.number
        end
      end
    end
  end

  local average=this.max_flame/number_player
  if this.player_flame[index] then
    if average <= this.player_flame[index].number and this.player_flame[index].number >=max_number then
      player.print({'amap.limit_flame'})
      return false
    end
  end

  if max_number>average then
    average=max_number-1
  end

  if average <=1 then
    player.print({'amap.limit_flame'})
    return false
  end

  local above_average={}
  for k,v in pairs(this.player_flame) do
    if v.number > average then
      above_average[#above_average+1]=v
    end
  end

  if #above_average==0 then
    average=average-1
    for k,v in pairs(this.player_flame) do
      if v.number > average then
        above_average[#above_average+1]=v
      end
    end
  end

  if #above_average~=0 then

    local k = math.random(#above_average)
    local all_turret=above_average[k].turret

    for k,v in pairs(all_turret) do
      if v then
        game.print({'amap.kill_flame',v.position.x,v.position.y,v.surface.name})
        v.destroy()
        clean_flame_table ()
        this.flame = this.flame - 1
        return true
      end
    end
  end

  if #above_average==0 then
    local sum = 0
    for k,v in pairs(this.player_flame) do
      sum= sum+v.number
    end
    this.flame=sum
  end
  return false
end

local function register_flame(index,turret)
  local this = WPT.get()
  if not this.player_flame[index] then
    this.player_flame[index]={}
    this.player_flame[index].number=0
    this.player_flame[index].turret={}
  end

  this.player_flame[index].number=this.player_flame[index].number+1

  local a=0
  for k,v in pairs(this.player_flame[index].turret) do
    a=k
  end
  this.player_flame[index].turret[a+1]=turret
  this.flame = this.flame + 1
  game.print({'amap.ok_many',this.flame,this.max_flame})
end

local function build_flame (player,turret)
  local this = WPT.get()
  local index = player.index
  clean_flame_table ()
  if this.flame < this.max_flame then
    register_flame(index,turret)

  else
    if  kill_turret(index,player) then
      register_flame(index,turret)
    else
      turret.destroy()
    end
  end
end

local on_player_or_robot_built_entity = function(event)

  local entity = event.created_entity
  local this = WPT.get()

  if	not(entity.surface.index == game.surfaces[this.active_surface_index].index) then return end
  local name = event.created_entity.name
  local force = event.created_entity.force
  if force.index ~= game.forces.player.index then return end
  for i,v in ipairs(steal_oil) do
    if name == v  then
      local main_surface = game.surfaces[this.active_surface_index]
      local entities = main_surface.find_entities_filtered{position = entity.position, radius = 5, name = 'flamethrower-turret'  , force = game.forces.enemy}
      if #entities~=0 then
        entity.die()
      end
    end
  end

  local player=event.created_entity.last_user
  if not player then return  end
  local index=player.index


  if name == 'flamethrower-turret' then
    if this.have_been_put_tank[index] then
      build_flame (player,event.created_entity)
    else
      entity.destroy()
    end
  end
  if name == 'land-mine'  then
    if this.have_been_put_tank[index] then
      if this.now_mine >= this.max_mine then
        game.print({'amap.too_many_mine'})
        entity.destroy()
      else
        this.now_mine = this.now_mine + 1
      end
    else
      entity.destroy()
    end
  end
end

local function count_down()
  local this = WPT.get()
  if this.stop_time==0 then return end
  if this.stop_time % 36000 == 0 then
    game.print({'amap.wave_time',this.stop_time/3600})
  end

  this.stop_time=this.stop_time-60
  if this.stop_time==0 then
    game.print({'amap.over_stop'})
    local wave_defense_table = WD.get_table()
    wave_defense_table.game_lost = false
    if get_car_number()~=0 then
      wave_defense_table.target=Public.get_random_car(true)
    end
  end
end



local disable_recipes = function()
  local force = game.forces.player
  force.recipes['car'].enabled = false
  force.recipes['tank'].enabled = false
  force.recipes['pistol'].enabled = false
  force.recipes['spidertron-remote'].enabled = false
  if is_mod_loaded('Krastorio2') then
    force.recipes['kr-advanced-tank'].enabled = false
  end
end


function Public.disable_tech()
  game.forces.player.technologies['landfill'].enabled = false
  game.forces.player.technologies['spidertron'].enabled = false
  game.forces.player.technologies['spidertron'].researched = false
  local force = game.forces.player
  if is_mod_loaded('Krastorio2') then
    force.technologies['kr-advanced-tank'].enabled = false
    force.technologies['kr-advanced-tank'].researched = false
  end
  disable_recipes()
end


function Public.on_research_finished(event)
  if event.research.force.index~=game.forces.player.index then return end
  local this = WPT.get()
  local research=event.research

  this.science=this.science+1
  local rpg_t = RPG.get('rpg_t')

  local pay_player={}
  local gain_player={}
  local should_reward={}
  local all_reward={}
  all_reward.point=0
  all_reward.coin=0
  for k, player in pairs(game.connected_players) do
    local point = math.random(1,5)
    local coin = math.random(1,100)
    local index = player.index
    if  this.tank[index]  then
      gain_player[#gain_player+1]=player
      should_reward[index]={}
      should_reward[index].point=point
      should_reward[index].coin=coin
    else
      all_reward.point=all_reward.point+point
      all_reward.coin=all_reward.coin+coin
      pay_player[#pay_player+1]=player
    end
  end
  if all_reward.point<=10 then all_reward.point = 10 end 

  local average_point=math.floor(all_reward.point/#gain_player)
  local average_coin=math.floor(all_reward.coin/#gain_player)

  if average_point<2 then average_point=1 end
  if average_coin<2 then average_coin=1 end

  for k, player in pairs(gain_player) do
    local index=player.index
    if should_reward[index] then
      local get_coin=should_reward[index].coin+average_coin
      local get_point=should_reward[index].point+average_point
      rpg_t[player.index].points_left = rpg_t[player.index].points_left+get_point
      player.insert{name='coin', count = get_coin}
      Alert.alert_player(player, 5, {'amap.science',get_point,get_coin})
    end
  end


  for k, player in pairs(pay_player) do
    Alert.alert_player(player, 5, {'amap.no_car_science'})
  end
  disable_recipes()
  refresh_shop(this.shop)
  if "utility-science-pack"==research.name and not this.allow_deconst_list["tree"] then
    this.allow_deconst_list["tree"] = true
    this.allow_deconst_list["simple-entity"] = true
    game.print({'amap.already_unlock_by_research'}) 
  end

end

local turret_tpye={
  ['ammo-turret']=true,
  ['fluid-turret']=true,
  ['electric-turretradar']=true,
  ['artillery-turret']=true,
  ['artillery-wagon']=true
}

local function on_entity_died (event)

  local entity = event.entity
  if not (entity and entity.valid) then

      --game.print("无效实体")
    return
  end
  if entity.force.index ~= game.forces.player.index then

    --  game.print("不是玩家阵营")
    return
  end

  local cause = event.cause
  if not cause then return end
  if  cause.force == game.forces.player then
--  game.print("玩家击杀的")
     return
   end

  local this= WPT.get()
local main_surface= game.surfaces[this.active_surface_index]
  if entity.surface.index ~=main_surface.index then
--  game.print("图层不一致")
     return

   end
  local wave_number = WD.get('wave_number')
  if wave_number<=10 then return end

  if not player_build[entity.name] then
  --  game.print("无效建筑物")
    return
  end

--  game.print("一个有效建筑物被摧毁")
  local ok = false
  if not entity.valid then return end
  if entity.status ==1 or entity.status==2 then
    ok = true
  --    game.print("有效状态")
   end
   if not turret_tpye[entity.type]  then  return end
  if entity.kills then
    if entity.kills >1000 then
    ok =true
    --  game.print("杀敌达标")
  end
end

--game.print(entity.status)

if not ok then return end

  if wave_number > 500 then
      local wave_defense_table = WD.get_table()
      local car=  wave_defense_table.target

        local pos_car =car.position
        local position=entity.position

        local dist_x = math.abs(position.x)-math.abs(pos_car.x)
        local dist_y = math.abs(position.y)-math.abs(pos_car.y)
        local sum = math.abs(dist_x)+math.abs(dist_y)

        if sum <450 then
          this.diff_change=this.diff_change+8
        end

  else
    this.diff_change=this.diff_change+8
  end

end

local function on_console_command(event)
  local cmd = event.command
  if not event.player_index then
    return
  end
  local this = WPT.get()
  if cmd~= "debug" then
    this.editor=true
  end

end

local disable_tech = Public.disable_tech
local on_research_finished = Public.on_research_finished
local on_player_joined_game = Public.on_player_joined_game



Event.on_nth_tick(60, count_down)
Event.on_nth_tick(600, Public.get_player_diff)

Event.add(defines.events.on_entity_died, on_entity_died)
Event.add(defines.events.on_console_command, on_console_command)
Event.add(defines.events.on_built_entity, on_player_or_robot_built_entity)
Event.add(defines.events.on_robot_built_entity, on_player_or_robot_built_entity)
Event.add(defines.events.on_research_finished, on_research_finished)
Event.add(defines.events.on_player_joined_game, on_player_joined_game)
Event.add(defines.events.on_player_mined_entity, on_player_mined_entity)
Event.add(defines.events.on_robot_mined_entity, on_player_mined_entity)


Event.on_nth_tick(108000, clac_time_weights)

return Public
