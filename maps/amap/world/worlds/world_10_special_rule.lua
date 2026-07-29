-- maps/amap/world/worlds/world_10_special_rule.lua
-- 世界 10：特殊规则世界（曹营）
--
-- 特点：堡垒只生成在下方（only_below 模式）、火焰塔上限 3、
-- 伤害加成奖励（damage_bonus）、有 silo 时虫子方向随机 3 或 4。
-- 参考：原 world_table.lua / diff.lua / main.lua / enemy_arty.lua 中
-- world_number == 10 分支。

local World = require 'maps.amap.world.framework'
local Helpers = require 'maps.amap.world.world_helpers'

--==============================================================================
-- 地形生成器（原 world_main.lua 第 732-761 行 world_generators[10]）
--==============================================================================

local function terrain_generator(surface, position, seed, get_tile, set_tiles, event, maxs, q, w, x, y)
    if maxs >= 64 then
        if w > 0 then
            if math.abs(q) < 1000 and math.abs(w) < 1000 then
                if math.random(1, 2) == 1 then
                    Helpers.ywjz(surface, position, 20000, maxs)
                end
            end
        end

        if w >= -165 and w <= -125 then
            surface.set_tiles({{name = "water-shallow", position = position}})
        end

        if w <= -180 then
            if math.random(1, 60) == 1 then
                local spawner_name = Helpers.spawner[math.random(1, 2)]
                if surface.can_place_entity({name = spawner_name, position = position, force = game.forces.enemy}) then
                    if Helpers.rand_worm(surface, position) then
                        surface.create_entity({
                            name = spawner_name,
                            position = position,
                            force = game.forces.enemy,
                        })
                    end
                end
            end
        end
    end
end

--==============================================================================
-- 注册到框架
--==============================================================================

World.register(10, {
    --==========================================================================
    -- 元数据
    --==========================================================================
    name_key = 'amap.world_name_10',
    desc_key = 'amap.world_name_info_10',

    --==========================================================================
    -- 时间与地形
    --==========================================================================
    -- 55 分钟（40 分钟游戏时间 + 15 分钟首波延迟）
    -- 来源：world_table.lua world_time[10]（第 24 行）
    time_limit = 60 * 60 * 40 + 60 * 60 * 15,

    -- 引用 framework 中注册的地表配置名
    -- 来源：world_table.lua world_surface_mapping[10]（第 219 行）
    surface_config_name = 'have_ore_no_biter',

    -- 地图尺寸设置
    -- 来源：world_table.lua world_map_settings[10] 不存在，用默认（nil）
    map_settings = nil,

    -- 区块地形生成函数
    terrain_generator = terrain_generator,

    --==========================================================================
    -- 战斗规则
    --==========================================================================
    -- 火焰塔上限
    -- 来源：diff.lua set_diff 中 world_number==10 分支（第 66-68 行）
    max_flame = 3,

    -- 虫子生成方向规则
    -- 来源：world_table.lua biter_spawn_rules[10]（第 302-305 行）
    biter_spawn_rule = {
        k_value = 'silo_random_3_4_or_roll',  -- 有 silo 时随机 k=3 或 4，否则循环
        force_x_align = 'random_1_3_silo',    -- 1/3 概率强制 x 对齐（需 silo）
    },

    -- 弹药伤害调整
    -- 来源：main.lua apply_ammo_damage_modifiers ammo_configs[10] 不存在，用默认（nil）
    ammo_damage_modifiers = nil,

    -- 虫族扩张参数
    -- 来源：main.lua apply_enemy_expansion_settings expansion_configs[10] 不存在，用默认（nil）
    enemy_expansion = nil,

    --==========================================================================
    -- 堡垒生成
    --==========================================================================
    -- 来源：enemy_arty.lua get_new_arty 中 world 10 分支
    --（第 1585 行 only_below = (arty_settings.mode == 'only_below') or (this.world_number == 10)）
    -- mode = 'only_below'：堡垒只生成在下方半圈
    arty_settings = {
        mode = 'only_below',
    },

    --==========================================================================
    -- 星球与科技
    --==========================================================================
    -- 解锁哪些星球
    -- 来源：main.lua apply_planet_surface_settings planet_configs[10] 不存在（nil）
    planet_surfaces = nil,
    -- 是否对特色资源翻倍
    -- 来源：main.lua create_planet_surface 中 7/8/13 分支（第 211 行），10 不在列表（nil）
    planet_resource_boost = nil,
    -- 是否解锁星球发现科技（默认 true，仅在 planet_surfaces 非空时生效）
    unlock_planet_technologies = true,

    -- 开局解锁的科技列表
    -- 来源：main.lua apply_technology_settings 中 world_number==10 不在 if/elseif 分支（空列表）
    unlocked_technologies = {},
    -- 是否允许填海
    -- 来源：main.lua apply_technology_settings 中 landfill_worlds 列表（第 455 行 {3, 7, 8, 9, 13, 14}），10 不在列表
    landfill_allowed = false,

    --==========================================================================
    -- 通关奖励
    --==========================================================================
    -- 通关奖励类型
    -- 来源：diff.lua world_bonus_types[10]（第 433-438 行）
    world_bonus_type = {
        name = 'damage_bonus',
        custom_type = 'function',
        base_value = 0.03,
        max_value = 0.2
    },
    -- 是否参与终极奖励
    -- 来源：diff.lua edge_worlds 列表（第 914 行 fallback {1..14}），10 在列表中
    joins_solar_system_edge = true,

    --==========================================================================
    -- 专属玩法钩子（运行时按世界分发，由旧代码处理）
    --==========================================================================
    -- 玩家汽车 buff 钩子（原 main.lua car_buff 中 world_number==10 无特殊分支）
    on_car_buff = nil,
    -- 经验获取钩子（原 main.lua gain_xp 中 world_number==10 无特殊分支）
    on_gain_xp = nil,
    -- 定时器钩子（原 main.lua on_tick 中 world_number==10 无独立定时器）
    on_tick = nil,
})
