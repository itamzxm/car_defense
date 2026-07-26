-- maps/amap/world/worlds/world_01_cave.lua
-- 世界 1：洞穴世界
--
-- 特点：洞穴地形、高资源频率、丰富矿产。max_flame 走通用进化逻辑。
-- 参考：原 world_table.lua 中 world_time[1] / world_surface_mapping[1] /
-- world_map_settings[1]（无）/ biter_spawn_rules[1]（无）+
-- main.lua 中 apply_ammo_damage_modifiers[1]（无）/ apply_enemy_expansion_settings[1]（无）/
-- apply_planet_surface_settings[1]（无）/ apply_technology_settings 中 world_number==1 走 else 分支 +
-- diff.lua 中 set_diff world_number==1（无，走通用逻辑）/ world_bonus_types[1] +
-- enemy_arty.lua 中 get_new_arty（默认模式，非 silo 世界）。

local World = require 'maps.amap.world.framework'
local world_function = require 'maps.amap.world.world_function'

--==============================================================================
-- 地形生成器（原 world_main.lua 第 454-458 行 world_generators[1]）
--==============================================================================

local function terrain_generator(surface, position, seed, get_tile, set_tiles, event, maxs, q, w, x, y)
    if maxs >= 64 then
        world_function.world_cave(surface, position, seed, get_tile)
    end
end

--==============================================================================
-- 注册到框架
--==============================================================================

World.register(1, {
    --==========================================================================
    -- 元数据
    --==========================================================================
    name_key = 'amap.world_name_1',
    desc_key = 'amap.world_name_info_1',

    --==========================================================================
    -- 时间与地形
    --==========================================================================
    -- 65 分钟（50 分钟游戏时间 + 15 分钟首波延迟）
    -- 原文件：world_table.lua 第 17 行 world_time[1]
    time_limit = 60 * 60 * 50 + 60 * 60 * 15,

    -- 引用 framework 中注册的地表配置名
    -- 原文件：world_table.lua 第 212 行 world_surface_mapping[1]
    surface_config_name = 'cave',

    -- 地图尺寸设置（原 world_table.lua world_map_settings[1] 无条目，使用默认）
    map_settings = nil,

    -- 区块地形生成函数
    terrain_generator = terrain_generator,

    --==========================================================================
    -- 战斗规则
    --==========================================================================
    -- 火焰塔上限（原 diff.lua set_diff 中无 world_number==1 分支，走通用逻辑 20→16→12）
    max_flame = nil,

    -- 虫子生成方向规则（原 world_table.lua biter_spawn_rules[1] 无条目，使用默认循环方向）
    biter_spawn_rule = nil,

    -- 弹药伤害调整（原 main.lua apply_ammo_damage_modifiers ammo_configs[1] 无条目）
    ammo_damage_modifiers = nil,

    -- 虫族扩张参数（原 main.lua apply_enemy_expansion_settings expansion_configs[1] 无条目）
    enemy_expansion = nil,

    --==========================================================================
    -- 堡垒生成（原 enemy_arty.lua get_new_arty，世界 1 为默认模式：围一圈）
    --==========================================================================
    arty_settings = {
        -- 模式：'default' 围一圈（默认）
        mode = 'default',
    },

    --==========================================================================
    -- 星球与科技
    --==========================================================================
    -- 解锁哪些星球（原 main.lua apply_planet_surface_settings planet_configs[1] 无条目）
    planet_surfaces = nil,
    -- 是否对特色资源翻倍（原 main.lua create_planet_surface 中无 1 分支）
    planet_resource_boost = nil,
    -- 是否解锁星球发现科技
    unlock_planet_technologies = nil,

    -- 开局解锁的科技列表（原 main.lua apply_technology_settings 中 world_number==1 走 else 分支）
    unlocked_technologies = {},
    -- 是否允许填海（原 main.lua apply_technology_settings 中 landfill_worlds = {3, 7, 8, 9, 13, 14}，世界 1 不在列表）
    landfill_allowed = false,

    --==========================================================================
    -- 通关奖励
    --==========================================================================
    -- 通关奖励类型（原 diff.lua world_bonus_types[1]）
    world_bonus_type = {
        name = 'mining_drill_productivity_bonus',
        force_modifier = 'mining_drill_productivity_bonus',
        base_value = 0.05,
        max_value = 0.3
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
