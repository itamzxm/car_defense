-- maps/amap/world/worlds/world_14_grass_invasion.lua
-- 世界 14：草星入侵
--
-- 特点：默认堡垒模式（default）、火焰塔上限 10（默认）、
-- 解锁 gleba 星球、允许填海、解锁火箭发射井科技、
-- 基础星球为 gleba（surface.lua 中切换）。
-- 参考：原 world_table.lua / diff.lua / main.lua / enemy_arty.lua 中
-- world_number == 14 分支。

local World = require 'maps.amap.world.framework'
local world_function = require 'maps.amap.world.world_function'

--==============================================================================
-- 地形生成器（原 world_main.lua 第 1064-1068 行 world_generators[14]）
--==============================================================================

local function terrain_generator(surface, position, seed, get_tile, set_tiles, event, maxs, q, w, x, y, area)
    if maxs >= 64 then
        world_function.world14_quarter(event, x, y)
    end
end

--==============================================================================
-- 钩子函数实现（原 main.lua on_nth_tick 中 world_number==14 分支）
--==============================================================================

-- on_tick 钩子：每 30 秒自动填充火箭进度至 100%（原 main.lua 行 1268-1272）
local function on_tick(this, tick)
    if this.silo and this.silo.name == 'rocket-silo' then
        this.silo.rocket_parts = 100
    end
end

--==============================================================================
-- 注册到框架
--==============================================================================

World.register(14, {
    --==========================================================================
    -- 元数据
    --==========================================================================
    name_key = 'amap.world_name_14',
    desc_key = 'amap.world_name_info_14',

    --==========================================================================
    -- 时间与地形
    --==========================================================================
    -- 55 分钟（40 分钟游戏时间 + 15 分钟首波延迟）
    -- 来源：world_table.lua world_time[14]（第 28 行）
    time_limit = 60 * 60 * 40 + 60 * 60 * 15,

    -- 引用 framework 中注册的地表配置名
    -- 来源：world_table.lua world_surface_mapping[14]（第 223 行）
    surface_config_name = 'world14',

    -- 地图尺寸设置
    -- 来源：world_table.lua world_map_settings[14]（第 273-275 行）
    map_settings = {
        starting_area = 1
    },

    -- 区块地形生成函数
    terrain_generator = terrain_generator,

    -- 世界 14 独有字段：基础星球为 gleba
    -- 用于 surface.lua 中切换基础星球（原 main.lua create_planet_surface 第 188 行
    -- if world_number == 14 and planet_name == "gleba" then base_planet = "nauvis"）
    -- 此字段标识世界 14 的主题星球，供框架调度使用
    base_planet = 'gleba',

    --==========================================================================
    -- 战斗规则
    --==========================================================================
    -- 火焰塔上限
    -- 来源：diff.lua set_diff 中 world_number==14 不在 if 链中，用默认值 10
    max_flame = 10,

    -- 虫子生成方向规则
    -- 来源：world_table.lua biter_spawn_rules[14] 不存在（nil），用默认循环方向
    biter_spawn_rule = nil,

    -- 弹药伤害调整
    -- 来源：main.lua apply_ammo_damage_modifiers ammo_configs[14] 不存在，用默认（nil）
    ammo_damage_modifiers = nil,

    -- 虫族扩张参数
    -- 来源：main.lua apply_enemy_expansion_settings expansion_configs[14] 不存在，用默认（nil）
    enemy_expansion = nil,

    --==========================================================================
    -- 堡垒生成
    --==========================================================================
    -- 来源：enemy_arty.lua get_new_arty 中 world 14 不在特殊分支，走默认围一圈逻辑
    -- mode = 'default'：围一圈（默认）
    arty_settings = {
        mode = 'default',
    },

    --==========================================================================
    -- 星球与科技
    --==========================================================================
    -- 解锁哪些星球
    -- 来源：main.lua apply_planet_surface_settings planet_configs[14]（第 385-388 行）
    planet_surfaces = {'gleba'},
    -- 是否对特色资源翻倍
    -- 来源：main.lua create_planet_surface 中 7/8/13 分支（第 211 行），14 不在列表（nil）
    planet_resource_boost = nil,
    -- 是否解锁星球发现科技
    -- 来源：main.lua apply_planet_surface_settings planet_configs[14].unlock_technologies = true
    unlock_planet_technologies = true,

    -- 开局解锁的科技列表
    -- 来源：main.lua apply_technology_settings 中 world_number==14 分支（第 436-437 行）
    unlocked_technologies = {'rocket-silo'},
    -- 是否允许填海
    -- 来源：main.lua apply_technology_settings 中 landfill_worlds 列表（第 455 行 {3, 7, 8, 9, 13, 14}），14 在列表
    landfill_allowed = true,

    --==========================================================================
    -- 通关奖励
    --==========================================================================
    -- 通关奖励类型
    -- 来源：diff.lua world_bonus_types[14] 不存在（nil）
    world_bonus_type = nil,
    -- 是否参与终极奖励
    -- 来源：diff.lua edge_worlds 列表（第 914 行 fallback {1..14}），14 在列表中
    joins_solar_system_edge = true,

    --==========================================================================
    -- 专属玩法钩子（运行时按世界分发）
    --==========================================================================
    on_car_buff = nil,
    on_car_buff_player = nil,
    on_gain_xp = nil,
    on_gain_xp_global = nil,
    -- on_tick 钩子：每 30 秒自动填充火箭进度至 100%
    on_tick = on_tick,
})
