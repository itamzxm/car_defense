-- maps/amap/world/worlds/world_06_arena.lua
-- 世界 6：竞技场
--
-- 特点：小地图 1250×1250、max_flame=2、虫族扩张间隔缩短（10min/5min）、
-- 100 人 settlers、自定义经验奖励（custom_type='function'）。
-- 参考：原 world_table.lua 中 world_time[6] / world_surface_mapping[6] /
-- world_map_settings[6] / biter_spawn_rules[6]（无）+
-- main.lua 中 apply_ammo_damage_modifiers[6]（无）/ apply_enemy_expansion_settings[6] /
-- apply_planet_surface_settings[6]（无）/ apply_technology_settings 中 world_number==6 走 else 分支 +
-- diff.lua 中 set_diff world_number==6 → max_flame=2 / world_bonus_types[6] +
-- enemy_arty.lua 中 get_new_arty（默认模式，非 silo 世界）。

local World = require 'maps.amap.world.framework'
local world_function = require 'maps.amap.world.world_function'

--==============================================================================
-- 地形生成器（原 world_main.lua 第 568-572 行 world_generators[6]）
--==============================================================================

local function terrain_generator(surface, position, seed, get_tile, set_tiles, event, maxs, q, w, x, y)
    if maxs >= 64 then
        world_function.world_cave_buff(surface, position, seed, get_tile, set_tiles)
    end
end

--==============================================================================
-- 注册到框架
--==============================================================================

World.register(6, {
    --==========================================================================
    -- 元数据
    --==========================================================================
    name_key = 'amap.world_name_6',
    desc_key = 'amap.world_name_info_6',

    --==========================================================================
    -- 时间与地形
    --==========================================================================
    -- 30 分钟（15 分钟游戏时间 + 15 分钟首波延迟）
    -- 原文件：world_table.lua 第 20 行 world_time[6]
    time_limit = 60 * 60 * 15 + 60 * 60 * 15,

    -- 引用 framework 中注册的地表配置名
    -- 原文件：world_table.lua 第 215 行 world_surface_mapping[6]
    surface_config_name = 'jjc',

    -- 地图尺寸设置（原 world_table.lua 第 238-242 行 world_map_settings[6]）
    map_settings = {
        width = 1250,
        height = 1250,
        starting_area = 0.5
    },

    -- 区块地形生成函数
    terrain_generator = terrain_generator,

    --==========================================================================
    -- 战斗规则
    --==========================================================================
    -- 火焰塔上限（原 diff.lua set_diff 第 60-62 行 world_number==6 → max_flame=2）
    max_flame = 2,

    -- 天赋间隔：每 15 级 +1 天赋（竞技场；默认 35，由 tianfu.lua 经 World 配置表读取）
    tianfu_jiange = 15,

    -- 虫子生成方向规则（原 world_table.lua biter_spawn_rules[6] 无条目，使用默认循环方向）
    biter_spawn_rule = nil,

    -- 弹药伤害调整（原 main.lua apply_ammo_damage_modifiers ammo_configs[6] 无条目）
    ammo_damage_modifiers = nil,

    -- 虫族扩张参数（原 main.lua apply_enemy_expansion_settings 第 348-354 行 expansion_configs[6]）
    enemy_expansion = {
        max_expansion_cooldown = 60 * 60 * 10,
        min_expansion_cooldown = 60 * 60 * 5,
        max_expansion_distance = 20,
        settler_group_min_size = 5,
        settler_group_max_size = 100
    },

    --==========================================================================
    -- 堡垒生成（原 enemy_arty.lua get_new_arty，世界 6 为默认模式：围一圈）
    --==========================================================================
    arty_settings = {
        -- 模式：'default' 围一圈（默认）
        mode = 'default',
    },

    --==========================================================================
    -- 星球与科技
    --==========================================================================
    -- 解锁哪些星球（原 main.lua apply_planet_surface_settings planet_configs[6] 无条目）
    planet_surfaces = nil,
    -- 是否对特色资源翻倍（原 main.lua create_planet_surface 中无 6 分支）
    planet_resource_boost = nil,
    -- 是否解锁星球发现科技
    unlock_planet_technologies = nil,

    -- 开局解锁的科技列表（原 main.lua apply_technology_settings 中 world_number==6 走 else 分支）
    unlocked_technologies = {},
    -- 是否允许填海（原 main.lua apply_technology_settings 中 landfill_worlds = {3, 7, 8, 9, 13, 14}，世界 6 不在列表）
    landfill_allowed = false,

    --==========================================================================
    -- 通关奖励
    --==========================================================================
    -- 通关奖励类型（原 diff.lua world_bonus_types[6] 第 409-414 行）
    -- 经验加成走 custom_type='function'，由 diff.lua apply_world_bonuses 中 custom_bonus_map 处理
    world_bonus_type = {
        name = 'experience_bonus',
        custom_type = 'function',
        base_value = 0.03,
        max_value = 0.2
    },
    -- 是否参与终极奖励（默认 true）
    joins_solar_system_edge = true,

    --==========================================================================
    -- 专属玩法钩子（仍由旧代码处理，不在此注册）
    --==========================================================================
    on_car_buff = nil,
    on_gain_xp = nil,
    on_tick = nil,
})
