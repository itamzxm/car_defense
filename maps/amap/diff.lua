local map = {}
local Public = {}

local Global = require 'utils.global'
local WD = require 'modules.wave_defense.table'
local WPT = require 'maps.amap.table'
local Difficulty = require 'modules.difficulty_vote_by_amount'
local Func = require 'maps.amap.functions'
local World = require 'maps.amap.world.framework'

local tianfu=require 'maps.amap.tianfu'

-- 终极奖励（开局天赋+1）新触发条件：玩家坐飞船抵达星系边缘。
-- 星系边缘在太空时代中的 space-location 原型名；若版本变动可在此处修正。
local SOLAR_SYSTEM_EDGE_NAME = 'solar-system-edge'


Global.register(
map,
function(tbl)
  map = tbl
end
)


local function calc_players()
  local players = game.connected_players
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

local set_diff = function()

  local this = WPT.get()

--make_game_mode()
--  if map.world==6 then
   -- this.max_flame=14
  --end
  local enemy = game.forces.enemy
  if  enemy.get_evolution_factor() >= 0.5 and this.max_flame == 20 then
    this.max_flame=16
  end
  if  enemy.get_evolution_factor() >= 0.9 and this.max_flame == 16 then
    this.max_flame=12
  end

  -- World 框架：max_flame 从各世界模块的 max_flame 字段查询
  local flame_from_framework = World.get_field(this.world_number, 'max_flame')
  if flame_from_framework ~= nil then
    this.max_flame = flame_from_framework
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

  if  this.enable_wild_factorio and wave_number>=1000 and map.world~=6  then
    local production = WPT.get_production_table()
    for key, factory in pairs(production.assemblers) do
      local entity = factory.entity
      if entity and entity.valid then
        entity.destructible = true
        entity.die()
      end
    end
    -- 组装机已摧毁，清除残留的地图标签
    for key, factory in pairs(production.assemblers) do
      if factory.tag then
        factory.tag.destroy()
      end
    end
    this.productionsphere.experience = {}
    this.productionsphere.assemblers = {}
    this.enable_wild_factorio =false
    game.print({"amap.biter_kill_factorio"})
  end


 -- if wave_number>=2000 and map.rocket_diff then
    --diff_k=diff_k-this.times*0.01 --暂且不做调整
 -- end
  if diff_k<=0.8 then diff_k =0.8 end

  if diff_k >= 3 then diff_k= 3  end

  local player_count = calc_players()
  local wave_defense_table = WD.get_table()
if wave_number< 500 then
player_count=1
  end


  local total_world_bonus_coefficient = 0
  for world_id, world_data in pairs(map.world_bonus) do
    if type(world_id) == 'number' and world_data and world_data.coefficient then
      total_world_bonus_coefficient = total_world_bonus_coefficient + world_data.coefficient
    end
  end
  local world_bonus_difficulty = total_world_bonus_coefficient / 100
  local max_threat = (1.3 + 0.1*player_count + world_bonus_difficulty)*diff_k
  wave_defense_table.threat_gain_multiplier =  math.min(max_threat,5)


  wave_defense_table.wave_interval = 2420/diff_k-player_count*20
  if  wave_defense_table.wave_interval <= 1380 then
    wave_defense_table.wave_interval=1380/diff_k
  end
  if  wave_defense_table.threat <= 0 then--or wave_defense_table.active_biter_count <= 10
  if wave_number>= 500 then
   wave_defense_table.wave_interval = 1080/diff_k
  else
      wave_defense_table.wave_interval = 1080/diff_k
   end

end

if map.world==6 then
  wave_defense_table.wave_interval=1080/diff_k
end

if wave_defense_table.wave_interval<=1080 then
  wave_defense_table.wave_interval=1080/diff_k
end

if wave_number>= 1300 and wave_number <=2005 then
  wave_defense_table.wave_interval = 1380/diff_k
end

-- if wave_number<= 800 then
--   wave_defense_table.wave_interval = wave_defense_table.wave_interval +600
-- end


  local damage_increase = wave_number * 0.001*diff_k
local wave_multiplier = 0.7 + math.floor(wave_number / 500) * 0.5
  local final_damage = (damage_increase + this.enemy_damage_modifier)*wave_multiplier
  if final_damage < 0 then
    final_damage = 0
  end

  game.forces.enemy.set_ammo_damage_modifier("artillery-shell", final_damage*3)
  game.forces.enemy.set_ammo_damage_modifier("melee", final_damage*1.5)
  game.forces.enemy.set_ammo_damage_modifier("biological", final_damage)
  wave_defense_table.average_unit_group_size=128--math.floor(728/(wave_defense_table.wave_interval/120))
  --wave_defense_table.wave_interval=600
end

function Public.reset_table()
  map.sum=0
  map.win=0
  map.gg=0

  map.diff=1

  map.pay_coin=8
  map.pay_xp=2

  map.world=1
  map.max_world=15
  map.world_number=15

  map.record_number=2
  map.record={}
  map.color={}
  map.text={}
  map.record[1]={}

  map.cunkuang={}
  map.record[1].name="aceshotter"
  map.record[1].pass_number=366
  map.record[1].wave_number=367

  map.record[2]={}
  map.record[2].name="noneofone"
  map.record[2].pass_number=1217
  map.record[2].wave_number=3000
  --

  map.record[3]={}
  map.record[3].name="shawnk"
  map.record[3].pass_number=1400
  map.record[3].wave_number=3000

  map.record[4]={}
  map.record[4].name="Wheneverlethe"
  map.record[4].pass_number=786
  map.record[4].wave_number=786

  map.record[5]={}
  map.record[5].name="xiaoyaoda"
  map.record[5].pass_number=635
  map.record[5].wave_number=635



  map.record[6]={}
  map.record[6].name="itam"

  map.record[7]={}
  map.record[7].name="liuhu66"

  map.record[8]={}
  map.record[8].name="mstsc"

  map.record[9]={}
  map.record[9].name="HY-1989"

  map.record[10]={}
  map.record[10].name="Prosics"

  map.record[11]={}
  map.record[11].name="wux2000"

  map.record[12]={}
  map.record[12].name="jiyang2017"

  map.record[13]={}
  map.record[13].name="Winnie_Bin"

  map.record[14]={}
  map.record[14].name="wows"


  map.record[15]={}
  map.record[15].name="stdioha"

  map.record[16]={}
  map.record[16].name="18833654531"

map.record[17]={}
  map.record[17].name="s695922378"

map.record[18]={}
  map.record[18].name="youjing"

  map.record[19]={}
  map.record[19].name="tianyuyu"

  map.record[20]={}
  map.record[20].name="LymBAOBEI"

 map.record[21]={}
  map.record[21].name="daoting"


   map.record[22]={}
  map.record[22].name="2351472480"

  map.record[23]={}
  map.record[23].name="stevenand123"

  map.record[24]={}
  map.record[24].name="yys666888"

  map.record[25]={}
  map.record[25].name="goldlzh"

  map.record[26]={}
  map.record[26].name="jiaoziai"

  map.record[27]={}
  map.record[27].name="kissblades"

  map.record[28]={}
  map.record[28].name="SlouchyQuill507"

  map.record[29]={}
  map.record[29].name="smqdyxgc"

  map.record['mstsc']='赞助玩家'
  map.record['Wheneverlethe']='单通困难'
  map.record['xiaoyaoda']='单通简单'
  map.record['shawnk']='机械神教'
  map.record['itam']='宇智波鼬'
  map.record['noneofone']='单人永生'
  map.record['aceshotter']='群管理员'
  map.record['linhu66']='服主'
  map.record['HY-1989']='寂寞无敌'
  map.record['Prosics']='无敌骏马'
  map.record['wux2000']='要你命2000'
  map.record['jiyang2017']='神秘玩家'
  map.record['Winnie_Bin']='垃圾佬'
  map.record['wows']='BUG测试员'
  map.record['stdioha']='^^^^'
  map.record['18833654531']='p社玩家'
  map.record['s695922378']='赏金猎人'
  map.record['youjing']='只吃鱼'
  map.record['tianyuyu']='不想看报错'
  map.record['LymBAOBEI']='PK虎虎'
  map.record['daoting']='道兄'
  map.record['2351472480']='二次元'
  map.record['stevenand123']='机械核心'
  map.record['yys666888']='又菜又爱玩'
  map.record['goldlzh']='摸摸鱼鱼鱼'
  map.record['jiaoziai']='大方承认吧'
  map.record['kissblades']='雷火建'
  map.record['SlouchyQuill507']='电量满满'
  map.record['smqdyxgc']='我gaygay的'


  map.png={}
  map.png['daoting']=true
  map.png['shawnk']=true
  map.png['aceshotter']=true
  map.png['noneofone']=true
  map.png['wux2000']=true
  map.png['s695922378']=true
  map.png['tianyuyu']=true
  map.png['itam']=true
  map.png['Winnie_Bin']=true
  map.png['18833654531']=true
  map.png['HY-1989']=true
  map.png['yys666888']=true
  map.png['goldlzh']=true
  map.png['jiaoziai']=true
  map.png['kissblades']=true
  map.png['SlouchyQuill507']=true

  map.map_record={}
  map.edge_reached={}  -- 各世界「飞船抵达星系边缘」记录（集齐全部世界才发终极奖励）
  map.world_bonus={}
  map.all_worlds_3000_rewarded=false
  map.world_13_4000_rewarded=false
  map.world_bonus.start_wave=1500
  map.world_bonus.coefficient_interval=500
  map.world_bonus.max_coefficient=20
  map.world_bonus.base_coefficient=5
  -- World 框架：遍历所有已注册世界初始化 world_bonus
  -- （修复原 for i=1,12 bug：漏 13/14，且未来新世界也自动覆盖）
  local registered_worlds = World.get_registered_worlds()
  for _, world_id in ipairs(registered_worlds) do
    map.world_bonus[world_id] = {
      unlocked=false,
      coefficient=0,
      max_wave=0
    }
  end

  map.world_bonus_types={}
  map.world_bonus_types[1]={
    name='mining_drill_productivity_bonus',
    force_modifier='mining_drill_productivity_bonus',
    base_value=0.05,
    max_value=0.3
  }
  map.world_bonus_types[2]={
    name='character_inventory_slots_bonus',
    force_modifier='character_inventory_slots_bonus',
    base_value=10,
    max_value=50
  }
  map.world_bonus_types[3]={
    name='laboratory_productivity_bonus',
    force_modifier='laboratory_productivity_bonus',
    base_value=0.05,
    max_value=0.25
  }
  map.world_bonus_types[6]={
    name='experience_bonus',
    custom_type='function',
    base_value=0.03,
    max_value=0.2
  }
  -- world 7（异次元大逃杀）已禁用，其移动速度加成已转移到世界16，见 World 框架 world_bonus_type
  -- world 8（异次元空间）已禁用：selectable=false + joins_solar_system_edge=false，
  --   其跟随机器人数量加成（following_robot_count_modifier）一并作废、不转移（用户仅要求禁用该世界）
  -- map.world_bonus_types[8]={
  --   name='following_robot_count_modifier',
  --   force_modifier='following_robot_count_modifier',
  --   base_value=3,
  --   max_value=20
  -- }
  map.world_bonus_types[9]={
    name='laboratory_speed_bonus',
    force_modifier='laboratory_speed_modifier',
    base_value=0.1,
    max_value=0.4
  }
  map.world_bonus_types[10]={
    name='damage_bonus',
    custom_type='function',
    base_value=0.03,
    max_value=0.2
  }
  map.world_bonus_types[11]={
    name='worker_robot_speed_bonus',
    force_modifier='worker_robot_speed',
    base_value=0.05,
    max_value=0.40
  }
  map.world_bonus_types[12]={
    name='turret_attack_bonus',
    custom_type='function',
    base_value=0.05,
    max_value=0.25
  }

  map.rocket_diff=true
end

--==============================================================================
-- 通关奖励数值计算（所有世界通用，声明式二选一）
--
--   A) 插值模式（默认）：base_value → max_value 在 coefficient 5→20 之间线性插值，
--      天然封顶 max_value。世界 1-12 沿用，行为不变。
--   B) 线性增长模式（world_bonus_type 声明 growth_value 时启用）：
--          bonus = base_value + growth_value * 档数
--          档数  = floor((历史最高波数 - 解锁波数) / 增档间隔)
--      档数直接由 max_wave 推导，不受 coefficient 上限（20）截断；
--      若同时声明 max_value 则以其封顶，**未声明 max_value 即不设上限**。
--
-- 两种模式都只按「历史最高波数」计算，取最高值而非累加，绝不跨局叠加。
-- 返回：bonus_value（未解锁时为 nil）, bonus_type
--==============================================================================
function Public.get_world_bonus_value(world_id, world_data)
    local bonus_type = World.get_field(world_id, 'world_bonus_type') or map.world_bonus_types[world_id]
    if not bonus_type or type(world_data) ~= 'table' or not world_data.unlocked then
        return nil, bonus_type
    end

    local bonus_value
    if bonus_type.growth_value then
        local start_wave = World.get_field(world_id, 'world_bonus_start_wave') or map.world_bonus.start_wave
        local interval = World.get_field(world_id, 'world_bonus_interval') or map.world_bonus.coefficient_interval or 500
        local steps = 0
        if interval and interval > 0 then
            steps = math.floor(math.max(0, (world_data.max_wave or 0) - start_wave) / interval)
        end
        bonus_value = (bonus_type.base_value or 0) + bonus_type.growth_value * steps
        if bonus_type.max_value then
            bonus_value = math.min(bonus_value, bonus_type.max_value)
        end
    else
        if not bonus_type.max_value then
            return nil, bonus_type
        end
        bonus_value = bonus_type.base_value + (bonus_type.max_value - bonus_type.base_value) *
            ((world_data.coefficient - map.world_bonus.base_coefficient) /
             (map.world_bonus.max_coefficient - map.world_bonus.base_coefficient))
    end

    return math.floor(bonus_value * 100 + 0.5) / 100, bonus_type
end

function Public.apply_world_bonuses()
    local this = WPT.get()
    local force = game.forces.player

    -- 重置自定义加成（force修饰符已被f.reset()清零，但this中的自定义字段需要手动重置）
    this.experience_bonus = 0

    local modifier_map = {
        character_health_bonus = function(value) force.character_health_bonus = force.character_health_bonus + value end,
        character_inventory_slots_bonus = function(value) force.character_inventory_slots_bonus = force.character_inventory_slots_bonus + value end,
        character_running_speed_modifier = function(value) force.character_running_speed_modifier = force.character_running_speed_modifier + value end,
        mining_drill_productivity_bonus = function(value) force.mining_drill_productivity_bonus = force.mining_drill_productivity_bonus + value end,
        laboratory_productivity_bonus = function(value) force.laboratory_productivity_bonus = force.laboratory_productivity_bonus + value end,
        laboratory_speed_modifier = function(value) force.laboratory_speed_modifier = force.laboratory_speed_modifier + value end,
        -- 跟随机器人数量上限（原世界8「异次元空间」，现世界17「网格战争」通关奖励）。
        -- 2.1.12 真实属性是整数 force.maximum_following_robot_count；
        -- 旧写法 force.follower_robot_count_modifier 属性根本不存在，会崩（RCON 实测）。
        following_robot_count_modifier = function(value) force.maximum_following_robot_count = force.maximum_following_robot_count + math.floor(value + 0.5) end,
        worker_robot_speed = function(value) force.worker_robots_speed_modifier = force.worker_robots_speed_modifier + value end,
        turret_attack_bonus = function(value) force.set_turret_attack_modifier('gun-turret', force.get_turret_attack_modifier('gun-turret') + value) end,
        laser_turret_damage_modifier = function(value) force.set_turret_attack_modifier('laser-turret', force.get_turret_attack_modifier('laser-turret') + value) end,
    }

    local custom_bonus_map = {
        experience_bonus = function(value) this.experience_bonus = (this.experience_bonus or 0) + value end,
        damage_bonus = function(value) Func.set_force_damage_modifier(force, value) end,
        turret_attack_bonus = function(value) force.set_turret_attack_modifier('gun-turret', force.get_turret_attack_modifier('gun-turret') + value) end
    }

    for world_id, world_data in pairs(map.world_bonus) do
        if type(world_data) == "table" and world_data.unlocked and world_data.coefficient > 0 then
            -- 数值统一由 get_world_bonus_value 计算（插值模式 / 线性增长模式二选一）
            local bonus_value, bonus_type = Public.get_world_bonus_value(world_id, world_data)

            if bonus_type and bonus_value then
                if bonus_type.force_modifier and modifier_map[bonus_type.force_modifier] then
                    modifier_map[bonus_type.force_modifier](bonus_value)
                elseif bonus_type.custom_type == 'function' and custom_bonus_map[bonus_type.name] then
                    custom_bonus_map[bonus_type.name](bonus_value)
                end
            end
        end
    end
end

function Public.check_all_worlds_3000()
    -- 世界13达4000波奖励：首次建车送传说木箱（独立于终极奖励，条件不变）
    if not map.world_13_4000_rewarded then
        if map.map_record[13] and map.map_record[13] >= 4000 then
            map.world_13_4000_rewarded = true
        end
    end
    -- 终极奖励「开局天赋+1」的触发条件已从「所有世界达4000波」改为
    -- 「每个世界各用飞船抵达一次星系边缘」，由 on_space_platform_changed_state 事件
    -- 逐世界记入 map.edge_reached，集齐全部世界后设置 map.all_worlds_3000_rewarded
    -- （见本文件底部 on_solar_system_edge_reached）。
end

function Public.has_all_worlds_3000_reward()
    return map.all_worlds_3000_rewarded
end

function Public.has_world_13_4000_reward()
    return map.world_13_4000_rewarded
end



commands.add_command(
    'tk',
    '从你的火箭账户中提款',
    function(cmd)
        local player = game.player

        if not player or not player.valid or not player.character then
            return
        end
        if not map.cunkuang[player.name] then
          player.print({'amap.no_coins_deposited'})
         return
       end

        local param = cmd.parameter
        if not param then
          if map.cunkuang[player.name] then
             player.print({'amap.deposit_balance', map.cunkuang[player.name]})
          end
             return
         end

         if param == '' then
           if map.cunkuang[player.name] then
             player.print({'amap.deposit_balance', map.cunkuang[player.name]})
         end
            return
        end

        local data = {
            player = player,
            target = target
        }
            local coin = tonumber(param)
            if not coin then
              player.print({'amap.invalid_number_input'})
              return
            end
            if  coin <= 1 then
              player.print({'amap.deposit_balance', map.cunkuang[player.name]})
              return
            end
            coin = math.floor(coin)


            local index=player.index
            if not map.cunkuang[player.name] then
               player.print({'amap.no_coins_deposited'})
              return
            end
            if map.cunkuang[player.name]>=coin then
              player.insert{name='coin',count=coin}
              map.cunkuang[player.name]=map.cunkuang[player.name]-coin
              player.print({'amap.withdraw_success', coin, map.cunkuang[player.name]})

            else
 player.print({'amap.insufficient_funds', map.cunkuang[player.name]})

            end
           -- player.play_sound {path = 'utility/scenario_message', volume_modifier = 1}

    end
)

commands.add_command(
'itam',
'如果你需要，可以再多选1个天赋',
function()
  local player = game.player
  if player then
    if player ~= nil then
      p = player.print
      local player_name =player.name
      for key, value in pairs(map.record) do
          if key == player_name then
            local this = WPT.get()
            -- 检查玩家当前天赋次数是否为0
            if not this.tianfu_count[player.index] or this.tianfu_count[player.index] <= 0 then
              p({'amap.no_talent_charges_available'}, {r = 1, g = 0.5, b = 0})
              return
            end
            if not this.tianfu[player.name] then
              this.tianfu[player.name]= 1
              tianfu.get_new_tianfu(player)
              this.tianfu_count[player.index]=this.tianfu_count[player.index]-1
              p({'amap.extra_talent_success', this.tianfu_count[player.index]}, {r = 0.5, g = 1, b = 0.5})
            end
          end
      end
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


local function rainbow_text(str)
  local len = #str;
  local left = len;
  local cnt = 0;
  local arr={0,0xc0,0xe0,0xf0,0xf8,0xfc};
  local indx = -left;
  local newstr = "";
  local colors_count = 36

  local colors={
    'E99696','E9A296','E9AF96','E9BB96','E9C896','E9D496','E9E096','E5E996','D8E996','CCE996','BFE996','B3E996','A6E996','9AE996','96E99E','96E9AB','96E9B7','96E9C3','96E9D0','96E9DC','96E9E9','96DCE9','96D0E9','96C3E9','96B7E9','96ABE9','969EE9','9A96E9','A696E9','B396E9','BF96E9','CC96E9','D896E9','E596E9','E996E0','E996D4','E996C8','E996BB','E996AF','E996A2',
  }
  while left ~= 0 do
      local tmp=string.byte(str,-left);
      local i=#arr;
      while i > 0 do
          if tmp>=arr[i] then
              left=left-i;
              break;
          end
          i=i-1;
      end
      if i == 0 then
          left = left - 1
      end
      local substr = string.sub(str,indx,-left - 1);
      local color_index = (cnt % colors_count) + 1
      local color=colors[color_index]
      newstr = newstr .. '[color=#' .. color ..']' .. substr.. '[/color]';
      indx = -left;
      cnt=cnt+1;
  end
newstr = '[font=heading-1]' .. newstr .. '[/font]'
  return newstr;
end

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

local function out_info(player)
    local map_data = Public.get()
    player.print({'amap.game_shuju', map_data.sum, map_data.win, map_data.gg, map_data.diff})
    player.print({'amap.map_shuju', {'amap.world_name_' .. map_data.world}})
    local best_record = map_data.map_record[map_data.world]
    if best_record == nil then
        best_record = 0
    end
    player.print({'amap.best_record', best_record})
end

function Public.game_info()
    for k, player in pairs(game.connected_players) do
        out_info(player)
    end
end


local function changer_color()
  for k,player in pairs(map.color) do
    if player.valid then
    if player.connected then
      if  player.character and  player.character.valid then
        if not map.text[player.name] then
          map.text[player.name] =
          rendering.draw_text {
            text = '[' .. map.record[player.name] .. ']',
            surface = player.physical_surface,
               target =
            {
                entity = player.character,
                offset = { 0, -3.5 },
            },
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


         if map.png[player.name] and player.name ~= 'jiyang2017' then
          rendering.draw_sprite {
            sprite = 'file/png/' .. player.name.. '.png',
            surface = player.physical_surface,
            target = player.character,
            x_scale = 0.6,
            y_scale = 0.6,
            render_layer = "resource"
          }
        end

        if player.name == 'jiyang2017' then
          rendering.draw_text {
            text = '难顶',
            surface = player.physical_surface,
            target = {
                entity = player.character,
                offset = { -1.5, -2.5 },
            },
            color = {
              r = 1,
              g = 1,
              b = 1,
              a = 1
            },
            outline_color = {
              r = 0,
              g = 0,
              b = 0,
              a = 1
            },
            players = players,
            scale = 1.2,
            font = 'default-large-semibold',
            alignment = 'center',
            scale_with_zoom = false
          }

          rendering.draw_text {
            text = '无敌',
            surface = player.physical_surface,
            target = {
                entity = player.character,
                offset = { 1.5, -2.5 },
            },
            color = {
              r = 1,
              g = 1,
              b = 1,
              a = 1
            },
            outline_color = {
              r = 0,
              g = 0,
              b = 0,
              a = 1
            },
            players = players,
            scale = 1.2,
            font = 'default-large-semibold',
            alignment = 'center',
            scale_with_zoom = false
          }

          rendering.draw_text {
            text = '完美',
            surface = player.physical_surface,
            target = {
                entity = player.character,
                offset = { 0, 1 },
            },
            color = {
              r = 1,
              g = 1,
              b = 1,
              a = 1
            },
            outline_color = {
              r = 0,
              g = 0,
              b = 0,
              a = 1
            },
            players = players,
            scale = 1.2,
            font = 'default-large-semibold',
            alignment = 'center',
            scale_with_zoom = false
          }
        end


        end
        if not map.text[player.name].valid then
          map.text[player.name].destroy()
          map.text[player.name]=nil
        end
      end
    else
      player=nil
      map.color[k]=nil
    end
  end
  end
end


-- ⚠️ 勿动此函数！彩名加入提示按 commit a2a47d3 原样还原：
-- 曾重构为 locale 拆行导致提示变白字 / unknown key，修复即还原为单行彩虹，保持原样。
local function on_player_joined_game(event)
  local player = game.players[event.player_index]
  for k,v in pairs(map.record) do
    if  player.name==v.name then
      map.color[#map.color+1]=player
      text=player.name .. ' ' .. map.record[player.name] .. ' 加入了游戏，你可以输入/itam，多选择1个天赋'
      eng_text='super player ' .. player.name .. " join the game"
      game.print(rainbow_text(text))
      game.print(rainbow_text(eng_text))
    end
  end
  changer_color()


end

local function on_player_changed_position(event)

  local player = game.players[event.player_index]
    if player.character == nil then
    return
   end

--  if  map.text[player.name] then
   -- local random = math.random(1, 5)
   --    if random == 1 then
  -- local surface=player.physical_surface
 -- player.physical_surface.create_entity({name = "water-splash", position = player.physical_position})
     --  end
  --end
   -- if not map.text[player.name] then return false end
        --  local random = math.random(1, 5)
        --  if random == 1 then

      --  end
end

-- 终极奖励触发：每个世界各用飞船抵达一次星系边缘（集齐全部世界才发奖励）
local function on_solar_system_edge_reached(event)
    -- 已达成则跳过，避免重复触发/打印
    if map.all_worlds_3000_rewarded then
        return
    end

    local platform = event.platform
    if not platform or not platform.valid then
        return
    end

    -- 仅当平台停靠在「星系边缘」时才算数
    local loc = platform.space_location
    if not loc or loc.name ~= SOLAR_SYSTEM_EDGE_NAME then
        return
    end

    -- 必须确认有玩家正乘坐该平台抵达（而非无人货运平台）
    local player_aboard = false
    for _, p in pairs(game.players) do
        if p.valid and p.connected and p.surface and p.surface.platform == platform then
            player_aboard = true
            break
        end
    end
    if not player_aboard then
        return
    end

    -- 记入当前世界（与 map.map_record[map.world] 的归属规则一致）
    map.edge_reached[map.world] = true

    -- 检查是否全部世界都已抵达过星系边缘
    -- World 框架：动态查询所有 joins_solar_system_edge=true 的世界
    local edge_worlds = World.query('joins_solar_system_edge', true)
    local all_reached = true
    for _, world_id in ipairs(edge_worlds) do
        if not map.edge_reached[world_id] then
            all_reached = false
            break
        end
    end

    if all_reached then
        map.all_worlds_3000_rewarded = true
        game.print({'amap.all_worlds_3000_announce'})
    end
end

local Event = require 'utils.event'
Event.on_init(on_init)
Event.on_nth_tick(60, set_diff)
Event.on_nth_tick(600, changer_color)
--Event.add(defines.events.on_player_respawned, on_player_respawned)
Event.add(defines.events.on_player_joined_game, on_player_joined_game)
--Event.add(defines.events.on_player_changed_position, on_player_changed_position)

-- 仅当太空时代 DLC 提供该事件时才注册（本场景已依赖太空时代，此处为安全保护）
if defines.events.on_space_platform_changed_state then
    Event.add(defines.events.on_space_platform_changed_state, on_solar_system_edge_reached)
end

return Public
