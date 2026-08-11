local Global = require 'utils.global'
local Event = require 'utils.event'

local this = {
  players = {},
  traps = {}
}
local Public = {}

Global.register(
    this,
    function(tbl)
        this = tbl
    end
)

function Public.reset_table()
  -- @star
  -- these 3 are in case of stop/start/reloading the finstance
  this.car_reach={}
  this.more_biter=0
  this.can_reach={}
  this.jubing={}
  this.diff_roll=0
  this.protect_car_time={}
  this.editor=false
  this.diff_wave=0
  this.diff_change=0
  this.player_diff={}
  this.upgrade_spell={}
  this.turret_rpg={}
  this.gain={}
  this.gain_time=0
  this.water_arty={}
  this.nest_wegiht={}
  this.player_flame={}
  this.car_die_number = 0
  this.enable_wild_factorio=true
  this.last_sipder=nil
  this.last_car={}
  this.productionsphere={}
  this.player_fishing_vehicles={}
  this.productionsphere.experience = {}
  this.productionsphere.assemblers = {}
  this.productionsphere.train_assemblers = {}
  this.quality_chest_purchases = {}
  this.cache_values = {}
  this.cache_timeout = 60*10 -- 5秒缓存
  this.shop=nil
  this.silo=nil
  this.max_pos=nil

  this.biter_follow_number = 100
  this.biter_max=100
  this.biter_command={}
  this.biter_number={}
  this.biter_pets={}
  this.clay_bomb_marks={}
  this.car_pos={}
  this.time_weights={}
  this.had_sipder={}
  this.theta_times=0
  this.frist_target=false
  this.car_index=nil
  this.urgrad_all_dam=0
  this.urgrad_mine=0
  this.max_flame=20
  this.max_mine=400
  this.now_mine=0
  this.stop_wave=0
  this.stop_time=0
  this.first_build_car={}
  this.upgrade_car={}
  this.player_position={}
  this.reset_time=0
  this.car_wudi={}
  this.ore_record={}
  this.target_last=0
  this.start_game=2
  this.whos_tank={}
  this.tank={}
  this.have_been_put_tank={}
  this.scmcc_data={}
  this.base=false
  this.goal=1
  this.baolei = 1
  this.baolei_y=0
  this.biter_wudi={}
  this.biter_death_queue={}
  this.spawn_order_index=1
  this.biter_dam=0
  this.turret={}
  this.ciyuan_pos={}
  this.cap=2
  this.biter_health=0
  this.change_dist=false
  this.spider_health=0
  this.arty=0
  this.health = 0
  this.flame = 0
  this.roll = 1
  this.pass = false
  this.science = 0
  this.number = 0
  this.first = true
  this.times = 1
  this.tianfu_names_cache={}
  this.last = 0
  this.up_coin={}
  this.up_xp={}
  this.up_jijing={}
  this.jijing_k={}
  this.dist_index={}
  this.up_jijing_histroy={}
  this.draw_circle={}
  this.car_level_text={}
  this.allow_deconst_list={}
  this.qcdj={}
  this.die_time={}
  this.now_pos={}
  this.baolei_count=0
  this.fixed_wave_initial_done=false      -- fixed_wave 模式：开局堡垒是否已生成（世界16）
  this.fixed_wave_last_baolei_wave=0      -- fixed_wave 模式：上次按波数生成堡垒的波数节点
  this.fixed_wave_last_baolei_tick=0      -- fixed_wave 模式：上次生成堡垒的 tick（30分钟间隔计时起点）
this.baolei_silo=nil
this.gun_turret={}
  --tianyu引入代码
  this.skill={}
  this.skill_canchoise = {}
  this.tianfu_lengque = {}
  this.tianfu_enabled = {}  -- 存储玩家天赋启用状态：this.tianfu_enabled[player_index][skill_id] = true/false
  this.tianfu_islands = {}  -- 存储海景房天赋的岛屿信息：this.tianfu_islands[player_index] = {island_id = island_id, surface_index = surface_index}
  --引入结束
  
  -- 玩家手搓经验倍数
  this.crafting_exp_multiplier = {}
  this.need_chest=nil

  this.last_stop_time =0
  this.allow_deconst_list["cliff"] = true
  this.allow_deconst_list["item-entity"] = true
  this.allow_deconst_list["fish"] = true
  this.jjc=1
  this.max_nest_number = 8
  this.max_worm_number = 8
  this.nest={}
  this.worm={}
  this.tianfu_count={}
  this.djrc_count={}
  this.tianfu={}
  this.tianfu_buy_count={}
  this.link={}
  this.link_player={}
  this.world_number=0
  this.vote_map_number = nil
  this.huantu_choise={}
  this.vote_count={}
  this.more_tianfu={}
  this.special_accumulators_main_world ={}
  this.special_accumulators_yiciyuan =nil
  this.fishing_vehicles = {}
  this.change_world_index=0
  this.change_world_timer=0  -- 用于实现45分钟执行一次的功能
  this.chunk_layout_data={}
  this.all_energy= 0
    this.fishing_vehicles = {}
    this.rlfdz={}
    this.zhiye={}
    this.player_laser={}
    this.laser=0
    this.max_laser=1000
    this.tesla=0
    this.max_tesla=50
    this.railgun=0
    this.max_railgun=4
    this.silo_tag=nil
    this.protectors_value = 0  -- 联军价值，用于世界10的特殊市场功能
    this.build_buffer={}
    this.gongchengche_count={}
    this.gongchengche_index={}
    this.allied_missions={}
    this.bonus_multiplier_cache={}
  this.enemy_damage_modifier = 0
  this.damage_multiplier=1
  this.player_damage_modifiers = {}
  this.player_damage_reduction_count = 0
  this.treasure_chest_created = false
  this.initial_resources_created = false
this.laser_turrets = {}
this.bio_labs = {}
   this.energy_recyclers = {}
   this.energy_network = {
        active = true,
        energy = 10000,
        max_energy = 1000000,
        decay_rate = 1,
        last_update = 0
      }
  
  this.quality_raffle_cache = {}
  this.quality_raffle_cache_tick = 0
  this.quality_total_weight = 0
  this.quality_total_chance = 0
  
      this.laser_turrets_created=nil
  this.energy_recycler=nil
  this.registered_laser_turrets={}
  this.water_world_markets = {}
  this.artillery_charging = {
            active = false,
            energy = 0,
            last_fortress_count = 0,
            message_shown = false
        }
  this.entity_search_cache = {}
  -- 随机种子（用于确定性随机数生成），每个玩家独立种子
  this.random_seed = {}
  -- 异步生成虫子队列
  this.unit_spawn_queue = {}
  this.ore_sequence_index = 0
  this.strategic_points = 0
  this.port_discovered = false
  this.island_type_index=1
  this.ore_sequence = {"iron-ore", "coal", "copper-ore", "stone", "crude-oil", "uranium-ore","iron-ore", "copper-ore", "stone","iron-ore", "coal", "copper-ore"}
  -- 岛屿系统数据（世界3）
   this.islands = {}
   this.island_production_index = 1
  -- 副本系统数据
   this.dungeons = {}
   -- 神奇木箱系统数据
  this.magic_wood_chests = nil           -- 木箱子数据
  this.magic_wood_renders = nil          -- 等级标签渲染对象
  -- 史诗木箱系统数据（地形随机生成 + 200波后定时投递，同时存在上限5个）
  this.epic_chests = nil                 -- 数组形式：epic_chests[1..5] = entity（参考 magic_wood_chests 注册模式）
  this.epic_chest_total = 0              -- 累计生成总数（重置地图时归零，上限25）
  this.lounge_bindings = nil             -- 休息室绑定表：unit_number -> {surface_name, entity, tag, created_tick}（重置时清理，surface 随重置流程删除）
  this.mw_global_investments = nil       -- 玩家总投资金额（重置地图时必须清零，否则投资会累积到下一局）
  this.mw_player_gui = nil               -- 玩家当前打开的 GUI 状态（select/upgrade + chest_un）
  this.mw_allow_inventory = nil          -- 允许直接打开仓库标记（从"打开仓库"按钮过来时放行）
  this.mw_time_cache = nil               -- 物品价值计算缓存
  this.mw_print_cooldown = nil           -- 金币飞字冷却
  this.mw_last_gold_tick = nil           -- 上次金币产出 tick
  -- 以下为旧版残留字段，保留 nil 赋值以清理老存档数据
  this.mw_pending_selection = nil
  this.mw_upgrade_frames = nil
  this.mw_upgrade_target = nil
  this.mw_allow_inventory_open = nil

  -- 噩梦萦绕天赋：锁定目标相关
   this.emengyingrao_locked_player = nil  -- 被锁定的玩家角色
   this.emengyingrao_lock_end_tick = 0    -- 锁定结束时间
   for _, player in pairs(this.players) do
    player.died = false
  end

end
function Public.get(key)
  if key then
    return this[key]
  else
    return this
  end
end

function Public.set(key, value)
  if key and (value or value == false) then
    this[key] = value
    return this[key]
  elseif key then
    return this[key]
  else
    return this
  end
end

function Public.get_production_table()
  return this.productionsphere
end

local on_init = function()
  Public.reset_table()
end

Event.on_init(on_init)

return Public
