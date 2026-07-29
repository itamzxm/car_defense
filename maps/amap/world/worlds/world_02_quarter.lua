-- maps/amap/world/worlds/world_02_quarter.lua
-- 世界 2：四分之一
--
-- 特点：四分之一资源、标准资源分布、解锁三星球（vulcanus/fulgora/gleba）。
-- 参考：原 world_table.lua 中 world_time[2] / world_surface_mapping[2] /
-- world_map_settings[2] / biter_spawn_rules[2]（无）+
-- main.lua 中 apply_ammo_damage_modifiers[2]（无）/ apply_enemy_expansion_settings[2]（无）/
-- apply_planet_surface_settings[2] / apply_technology_settings 中 world_number==2 走 else 分支 +
-- diff.lua 中 set_diff world_number==2（无，走通用逻辑）/ world_bonus_types[2] +
-- enemy_arty.lua 中 get_new_arty（默认模式，非 silo 世界）。

local World = require 'maps.amap.world.framework'
local Helpers = require 'maps.amap.world.world_helpers'
local world_function = require 'maps.amap.world.world_function'

--==============================================================================
-- 地形生成器（原 world_main.lua 第 461-562 行 world_generators[2]）
--==============================================================================

local function terrain_generator(surface, position, seed, get_tile, set_tiles, event, maxs, q, w, x, y, area)
    if maxs >= 64 then
        world_function.quarter(event, x, y)
    end

    if math.abs(q) < 1200 and math.abs(w) < 1200 and maxs >= 200 then
        Helpers.ywjz(surface, position, 20000, maxs)
    end

    if maxs >= 200 and q < 0 and w < 0 then
        world_function.world_cave(surface, position, seed, get_tile)
    end

    if maxs >= 200 and x == 0 and y == 0 then
        if q < 0 and w > 0 then
            Helpers.clone_area('gleba', position, area, true)
        end
        if q > 0 and w < 0 then
            Helpers.clone_area('vulcanus', position, area, true)
        end
        if q > 0 and w > 0 then
            Helpers.clone_area('fulgora', position, area, true)
        end

        if math.random(1, 8) == 1 then
            local spawner_name = Helpers.spawner[math.random(1, 2)]
            local spawn_count = math.floor(maxs / math.random(50, 200))

            for i = 1, spawn_count do
                local worm_position = surface.find_non_colliding_position(spawner_name, position, 32, 4)
                if worm_position then
                    Helpers.rand_worm(surface, worm_position)
                end
                local biter_position = surface.find_non_colliding_position(spawner_name, position, 32, 4)
                if biter_position then
                    surface.create_entity({
                        name = spawner_name,
                        position = biter_position,
                        force = game.forces.enemy,
                    })
                end
            end
        end
    end
end

--==============================================================================
-- 注册到框架
--==============================================================================

World.register(2, {
    --==========================================================================
    -- 元数据
    --==========================================================================
    name_key = 'amap.world_name_2',
    desc_key = 'amap.world_name_info_2',

    --==========================================================================
    -- 时间与地形
    --==========================================================================
    -- 55 分钟（40 分钟游戏时间 + 15 分钟首波延迟）
    -- 原文件：world_table.lua 第 18 行 world_time[2]
    time_limit = 60 * 60 * 40 + 60 * 60 * 15,

    -- 引用 framework 中注册的地表配置名
    -- 原文件：world_table.lua 第 213 行 world_surface_mapping[2]
    surface_config_name = 'quarter',

    -- 地图尺寸设置（原 world_table.lua 第 229-231 行 world_map_settings[2]）
    map_settings = {
        starting_area = 0.8
    },

    -- 区块地形生成函数
    terrain_generator = terrain_generator,

    --==========================================================================
    -- 战斗规则
    --==========================================================================
    -- 火焰塔上限（原 diff.lua set_diff 中无 world_number==2 分支，走通用逻辑 20→16→12）
    max_flame = nil,

    -- 虫子生成方向规则（原 world_table.lua biter_spawn_rules[2] 无条目，使用默认循环方向）
    biter_spawn_rule = nil,

    -- 弹药伤害调整（原 main.lua apply_ammo_damage_modifiers ammo_configs[2] 无条目）
    ammo_damage_modifiers = nil,

    -- 虫族扩张参数（原 main.lua apply_enemy_expansion_settings expansion_configs[2] 无条目）
    enemy_expansion = nil,

    --==========================================================================
    -- 堡垒生成（原 enemy_arty.lua get_new_arty，世界 2 为默认模式：围一圈）
    --==========================================================================
    arty_settings = {
        -- 模式：'default' 围一圈（默认）
        mode = 'default',
    },

    --==========================================================================
    -- 星球与科技
    --==========================================================================
    -- 解锁哪些星球（原 main.lua apply_planet_surface_settings planet_configs[2] 第 373-376 行）
    -- list 形式，与旧 planet_configs.planets 一致
    planet_surfaces = {'vulcanus', 'fulgora', 'gleba'},
    -- 是否对特色资源翻倍（原 main.lua create_planet_surface 中无 2 分支）
    planet_resource_boost = nil,
    -- 是否解锁星球发现科技（原 main.lua apply_planet_surface_settings.unlock_technologies=true）
    unlock_planet_technologies = true,

    -- 开局解锁的科技列表（原 main.lua apply_technology_settings 中 world_number==2 走 else 分支）
    unlocked_technologies = {},
    -- 是否允许填海（原 main.lua apply_technology_settings 中 landfill_worlds = {3, 7, 8, 9, 13, 14}，世界 2 不在列表）
    landfill_allowed = false,

    --==========================================================================
    -- 通关奖励
    --==========================================================================
    -- 通关奖励类型（原 diff.lua world_bonus_types[2] 第 397-402 行）
    world_bonus_type = {
        name = 'character_inventory_slots_bonus',
        force_modifier = 'character_inventory_slots_bonus',
        base_value = 10,
        max_value = 50
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
