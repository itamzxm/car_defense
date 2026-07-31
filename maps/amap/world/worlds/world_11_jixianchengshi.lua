-- maps/amap/world/worlds/world_11_jixianchengshi.lua
-- 世界 11：机械城市
--
-- 特点：silo 模式（silo_3_points）、火焰塔上限 0、
-- 弹药减伤（grenade/landmine -75%，artillery-shell -90%，无 flamethrower）、
-- 机器人速度奖励（worker_robot_speed_bonus）。
-- 参考：原 world_table.lua / diff.lua / main.lua / enemy_arty.lua 中
-- world_number == 11 分支。

local World = require 'maps.amap.world.framework'
local Helpers = require 'maps.amap.world.world_helpers'
local WPT = require 'maps.amap.table'
local jixianchengshi = require 'maps.amap.world.word__jixianchengshi'

--==============================================================================
-- 地形生成器（原 world_main.lua 第 764-890 行 world_generators[11]）
--==============================================================================

local function terrain_generator(surface, position, seed, get_tile, set_tiles, event, maxs, q, w, x, y)
    if maxs <= 64 then
        local this = WPT.get()
        if not this.energy_recycler then
            local spawn_pos = {x = 0, y = 8}
            local recycler_pos = surface.find_non_colliding_position("steel-chest", spawn_pos, 10, 1)
            if recycler_pos then
                local recycler = surface.create_entity({
                    name = "steel-chest",
                    position = recycler_pos,
                    force = "player",
                    quality = 'legendary'
                })
                if recycler and recycler.valid then
                    local text_id = rendering.draw_text {
                        text = "回收箱",
                        surface = surface,
                        target = {
                            entity = recycler,
                            offset = {0, -2.6}
                        },
                        color = {
                            r = 1,
                            g = 0,
                            b = 0,
                            a = 1
                        },
                        scale = 1.05,
                        font = "default-large-semibold",
                        alignment = "center",
                        scale_with_zoom = false
                    }
                    recycler.minable_flag = false
                    recycler.destructible = false
                    this.energy_recycler = {entity = recycler, text_id = text_id}
                end
            end
        end

        if not this.laser_turrets_created then
            local turret_count = 0
            local turret_y = -28
            local turret_x_start = -68.25
            local turret_spacing = 3.5

            for i = 0, 39 do
                local turret_pos = {x = turret_x_start + i * turret_spacing, y = turret_y}
                local turret = surface.create_entity({
                    name = "laser-turret",
                    position = turret_pos,
                    force = "player",
                    minable = false,
                    destructible = false
                })
                if turret and turret.valid then
                    jixianchengshi.register_laser_turret(turret)
                    turret_count = turret_count + 1
                    turret.minable_flag = false
                end
            end

            for i = 0, 39 do
                local turret_pos = {x = turret_x_start + i * turret_spacing, y = -25}
                local turret = surface.create_entity({
                    name = "laser-turret",
                    position = turret_pos,
                    force = "player",
                    minable = false,
                    destructible = false
                })
                if turret and turret.valid then
                    jixianchengshi.register_laser_turret(turret)
                    turret_count = turret_count + 1
                    turret.minable_flag = false
                end
            end

            local wall_x_start = -68.25
            for i = 0, 136 do
                local wall_pos = {x = wall_x_start + i, y = -30}
                surface.create_entity({
                    name = "stone-wall",
                    position = wall_pos,
                    force = game.forces.player
                })
            end

            for i = 0, 136 do
                local wall_pos = {x = wall_x_start + i, y = -31}
                surface.create_entity({
                    name = "stone-wall",
                    position = wall_pos,
                    force = game.forces.player
                })
            end

            if turret_count > 0 then
                this.laser_turrets_created = true
            end
        end
    end

    if maxs >= 64 then
        if w < 0 then
            if math.abs(q) > 107 then
                surface.set_tiles({{name = "out-of-map", position = position}})
            else
                if w <= -150 then
                    Helpers.ywjz(surface, position, 5000, maxs * 2)
                    if math.random(1, 90) == 1 then
                        local spawner_name = Helpers.spawner[math.random(1, 2)]
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
end

--==============================================================================
-- 钩子函数实现（原 main.lua gain_xp 中 world_number==11 分支）
--==============================================================================

-- gain_xp 玩家级钩子：跟踪 baolei_y（原 main.lua 行 1013-1017）
local function on_gain_xp(this, player, wave_number)
    if player.physical_position.y < this.baolei_y and player.physical_surface == this.shop.surface then
        this.baolei_y = player.physical_position.y
    end
end

--==============================================================================
-- 注册到框架
--==============================================================================

World.register(11, {
    --==========================================================================
    -- 元数据
    --==========================================================================
    name_key = 'amap.world_name_11',
    desc_key = 'amap.world_name_info_11',

    --==========================================================================
    -- 时间与地形
    --==========================================================================
    -- 65 分钟（50 分钟游戏时间 + 15 分钟首波延迟）
    -- 来源：world_table.lua world_time[11]（第 25 行）
    time_limit = 60 * 60 * 50 + 60 * 60 * 15,

    -- 引用 framework 中注册的地表配置名
    -- 来源：world_table.lua world_surface_mapping[11]（第 220 行）
    surface_config_name = 'jixianchengshi',

    -- 不生成默认野外建筑/石头（原 world_main.lua ywjz 硬编码排除列表）
    disable_default_rocks = true,

    -- 地图尺寸设置
    -- 来源：world_table.lua world_map_settings[11]（第 260-262 行）
    map_settings = {
        starting_area = 0.6
    },

    -- 区块地形生成函数
    terrain_generator = terrain_generator,

    --==========================================================================
    -- 战斗规则
    --==========================================================================
    -- 火焰塔上限
    -- 来源：diff.lua set_diff 中 world_number==11 分支（第 69-71 行）
    max_flame = 0,

    -- 虫子生成方向规则
    -- 来源：world_table.lua biter_spawn_rules[11]（第 307-310 行）
    biter_spawn_rule = {
        k_value = 'silo_3_or_roll',  -- 有 silo 时用 k=3，否则循环
        force_x_align = true,        -- 始终强制 x 对齐
    },

    -- 弹药伤害调整
    -- 来源：main.lua apply_ammo_damage_modifiers ammo_configs[11]（第 324-328 行）
    -- 注意：没有 flamethrower 项
    ammo_damage_modifiers = {
        ['grenade'] = -0.75,
        ['landmine'] = -0.75,
        ['artillery-shell'] = -0.9
    },

    -- 虫族扩张参数
    -- 来源：main.lua apply_enemy_expansion_settings expansion_configs[11] 不存在，用默认（nil）
    enemy_expansion = nil,

    --==========================================================================
    -- 堡垒生成
    --==========================================================================
    -- 来源：enemy_arty.lua get_new_arty 中 world 11 分支
    --（第 1463 行 is_silo_world = (this.world_number == 7 or 9 or 11 or 12)）
    -- mode = 'silo_3_points'：baolei_count>1 时生成核弹发射井，否则 3 点堡垒
    -- interval = 35：silo 世界基础生成间隔（原 fallback 硬编码 35）
    arty_settings = {
        interval = 35,
        mode = 'silo_3_points',
    },

    --==========================================================================
    -- 星球与科技
    --==========================================================================
    -- 解锁哪些星球
    -- 来源：main.lua apply_planet_surface_settings planet_configs[11] 不存在（nil）
    planet_surfaces = nil,
    -- 是否对特色资源翻倍
    -- 来源：main.lua create_planet_surface 中 7/8/13 分支（第 211 行），11 不在列表（nil）
    planet_resource_boost = nil,
    -- 是否解锁星球发现科技（默认 true，仅在 planet_surfaces 非空时生效）
    unlock_planet_technologies = true,

    -- 开局解锁的科技列表
    -- 来源：main.lua apply_technology_settings 中 world_number==11 不在 if/elseif 分支（空列表）
    unlocked_technologies = {},
    -- 是否允许填海
    -- 来源：main.lua apply_technology_settings 中 landfill_worlds 列表（第 455 行 {3, 7, 8, 9, 13, 14}），11 不在列表
    landfill_allowed = false,

    --==========================================================================
    -- 通关奖励
    --==========================================================================
    -- 通关奖励类型
    -- 来源：diff.lua world_bonus_types[11]（第 439-444 行）
    world_bonus_type = {
        name = 'worker_robot_speed_bonus',
        force_modifier = 'worker_robot_speed',
        base_value = 0.05,
        max_value = 0.40
    },
    -- 是否参与终极奖励
    -- 来源：diff.lua edge_worlds 列表（第 914 行 fallback {1..14}），11 在列表中
    joins_solar_system_edge = true,

    --==========================================================================
    -- 专属玩法钩子（运行时按世界分发）
    --==========================================================================
    on_car_buff = nil,
    on_car_buff_player = nil,
    on_gain_xp = on_gain_xp,
    on_gain_xp_global = nil,
    on_tick = nil,
})
