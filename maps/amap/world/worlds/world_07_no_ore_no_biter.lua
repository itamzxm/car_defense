-- maps/amap/world/worlds/world_07_no_ore_no_biter.lua
-- 世界 7：无矿石无虫子世界
--
-- 特点：单方向虫子进攻（k=2 左下方向）、silo 跟踪、崩落机制、
-- 每 992 米生成 3 个堡垒 + 火箭发射井、弹药减伤 50%。
-- 参考：原 world_table.lua 中 world_time[7] / world_surface_mapping[7] /
-- world_map_settings[7] / biter_spawn_rules[7] + world_main.lua 中
-- world_generators[7] + main.lua 中 apply_ammo_damage_modifiers[7] /
-- apply_planet_surface_settings[7] + enemy_arty.lua 中 get_new_arty 的 7/9/11/12 分支。

local World = require 'maps.amap.world.framework'
local Helpers = require 'maps.amap.world.world_helpers'
local world_function = require 'maps.amap.world.world_function'
local WD = require 'modules.wave_defense.table'
local enemy_arty = require 'maps.amap.enemy_arty'
local Collapse = require 'modules.collapse'

--==============================================================================
-- 地形生成器（原 world_main.lua 第 557-671 行 world_generators[7]）
-- 辅助函数与共享配置已迁至 world_helpers.lua
--==============================================================================

local function terrain_generator(surface, position, seed, get_tile, set_tiles, event, maxs, q, w, x, y, area)
    area.left_top = {x = -100, y = area.left_top.y}
    area.right_bottom = {x = 100, y = area.right_bottom.y}
    if maxs >= 64 then
        if w < -50 then
            local mod_w = math.abs(w) % 992
            if mod_w >= 32 and mod_w <= 64 then
                return
            end
            local nearest_base = math.floor((w + 496) / 992) * 992
            local base_y = nearest_base - 150
            local end_y = nearest_base + 150

            if not (q >= -100 and q <= 100 and w >= base_y and w <= end_y) then
                local y_range = math.floor((math.abs(w)) / 992) % 5
                local wave_number = WD.get('wave_number')
                local config = Helpers.world_7_terrain_config[y_range]

                if config then
                    if config.min_wave and wave_number < config.min_wave then
                        config = nil
                        local check_range = (y_range + 1) % 5
                        while check_range ~= y_range do
                            local check_config = Helpers.world_7_terrain_config[check_range]
                            if check_config and (not check_config.min_wave or wave_number >= check_config.min_wave) then
                                config = check_config
                                break
                            end
                            check_range = (check_range + 1) % 5
                        end
                    end

                    if config and config.generators then
                        for _, gen in ipairs(config.generators) do
                            gen(surface, position, seed, get_tile)
                        end
                    end

                    if config.clone_area_name and x == 0 and y == 0 then
                        local chunk_w_end = w + 31
                        if not (chunk_w_end >= base_y and w <= end_y) then
                            Helpers.clone_area(config.clone_area_name, position, area, false)
                        end
                    end

                    if config.rock_generator and math.random(1, 3) == 1 then
                        config.rock_generator(surface, position, seed, get_tile)
                    end
                end

                -- 虫巢随机生成（原 world_main.lua 第 607-617 行）
                local spawn_chance_7 = (wave_number >= 700) and 440 or 220
                if math.random(1, spawn_chance_7) == 1 then
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
        if w > 100 then
            surface.set_tiles({{name = "out-of-map", position = position}})
        end

        -- 火箭发射井 + 能量接口 + 堡垒生成（每 992 米）
        if w % 992 == 0 and q == 0 then
            world_function.crate_ore(surface, position, 2, 40)

            local accumulator = surface.create_entity({
                name = "electric-energy-interface",
                position = position,
                force = game.forces.player
            })
            if accumulator and accumulator.valid then
                accumulator.destructible = false
                accumulator.operable = false
                accumulator.minable_flag = false
                accumulator.energy = 1300000
            end

            local silo_position = {x = position.x, y = position.y + 10}
            local silo = surface.create_entity({
                name = "rocket-silo",
                position = silo_position,
                force = game.forces.player
            })
            if silo and silo.valid then
                silo.destructible = false
                silo.minable_flag = false
            end
        end

        -- 堡垒生成（火箭发射井下方 50 米处，3 个并排）
        if w % 992 == 0 and q == 0 and w <= -992 then
            local wave_number = WD.get('wave_number')
            local distance = math.abs(w)
            local tier = math.floor(distance / 992)
            local baolei_worth = 150 + (tier - 1) * 200
            if baolei_worth < 150 then baolei_worth = 150 end
            local baolei_y = (position.y + 10) + 50  -- silo_position.y + 50
            enemy_arty.baolei({x = -65, y = baolei_y}, baolei_worth, surface, true)
            enemy_arty.baolei({x = 0, y = baolei_y}, baolei_worth, surface, true)
            enemy_arty.baolei({x = 65, y = baolei_y}, baolei_worth, surface, true)
        end
    end
end

--==============================================================================
-- 钩子函数实现（原 main.lua car_buff/gain_xp 中 world_number==7 分支）
--==============================================================================

-- car_buff 全局钩子：设置 silo 出生点 + 提示放车
local function on_car_buff(this, rpg_t)
    -- 原 main.lua 行 900-902：世界 7 把出生点设到 silo 位置
    if this.silo and this.silo.valid then
        game.forces.player.set_spawn_position(this.silo.position, this.silo.surface)
    end

    -- 原 main.lua 行 911-918：世界 7/8 提示放车
    for _, player in pairs(game.connected_players) do
        local index = player.index
        if not this.ciyuan_pos[index] then
            player.print('你还没有放车，请及时放车,build a car', {0, 255, 255})
        end
    end
end

-- gain_xp 玩家级钩子：跟踪 max_pos 和 baolei_y
local function on_gain_xp(this, player, wave_number)
    -- 原 main.lua 行 1021-1029：世界 7/13 跟踪 max_pos
    if not this.max_pos then
        this.max_pos = 0
    end
    if math.abs(player.physical_position.y) >= math.abs(this.max_pos) then
        this.max_pos = player.physical_position.y
        this.baolei_y = player.physical_position.y
    end
end

-- gain_xp 全局钩子：启动 Collapse + 调整速度
local function on_gain_xp_global(this, wave_number)
    -- 原 main.lua 行 1035-1037：100 波后启动崩落
    if wave_number >= 100 then
        Collapse.start_now(true)
    end

    -- 原 main.lua 行 1039-1059：根据玩家位置动态调整 Collapse 速度
    local now_pos = Collapse.get_position()
    local speed = math.abs(this.max_pos) - math.abs(now_pos.y)
    speed = math.floor(speed / 350)
    if speed < 2 then
        speed = 2
    end
    Collapse.set_amount(speed)

    for _, player in pairs(game.connected_players) do
        local index = player.index

        if not this.now_pos[index] then
            this.now_pos[index] = this.shop.position
        end

        if this.now_pos[index].y > now_pos.y then
            this.now_pos[index] = this.shop.position
        end
    end
end

--==============================================================================
-- 注册到框架
--==============================================================================

World.register(7, {
    --==========================================================================
    -- 元数据
    --==========================================================================
    name_key = 'amap.world_name_7',
    desc_key = 'amap.world_name_info_7',

    --==========================================================================
    -- 时间与地形
    --==========================================================================
    -- 60 分钟（45 分钟游戏时间 + 15 分钟首波延迟）
    time_limit = 60 * 60 * 45 + 60 * 60 * 15,

    -- 引用 framework 中注册的地表配置名（原 world_surface_mapping[7]）
    surface_config_name = 'have_ore_no_biter',

    -- 地图尺寸设置（原 world_map_settings[7]）
    map_settings = {
        width = 200,
        starting_area = 0.6
    },

    -- 区块地形生成函数（原 world_generators[7]）
    terrain_generator = terrain_generator,

    --==========================================================================
    -- 战斗规则
    --==========================================================================
    -- 火焰塔上限（原 diff.lua set_diff 中 world_number==7 分支）
    -- 注意：世界 7 是单方向世界（k_value=2），按 CLAUDE.md 规则应为 0；
    -- 此处保留原值 1，待用户决策是否修复。
    max_flame = 1,

    -- 虫子生成方向规则（原 world_table.lua biter_spawn_rules[7]）
    biter_spawn_rule = {
        k_value = 2,                -- 固定左下方向
        force_x_align = true,       -- 强制 x 坐标对齐目标
        transfer_pollution = true,  -- 整图污染转移到 silo 位置
    },

    -- 弹药伤害调整（原 main.lua apply_ammo_damage_modifiers[7]）
    -- 单方向世界必须降低爆炸类伤害 ≥50%
    ammo_damage_modifiers = {
        ['grenade'] = -0.5,
        ['landmine'] = -0.5,
        ['flamethrower'] = -0.6,
        ['artillery-shell'] = -0.5
    },

    -- 虫族扩张参数（原 main.lua apply_enemy_expansion_settings，世界 7 用默认值）
    enemy_expansion = nil,

    --==========================================================================
    -- 堡垒生成（原 enemy_arty.lua get_new_arty 中 7/9/11/12 分支）
    --==========================================================================
    arty_settings = {
        -- 生成间隔（默认 20，世界 7 为 35）
        interval = 35,
        -- 起始波数（默认 250，世界 7 独有为 150）
        start_wave = 150,
        -- 模式：
        --   'default'         围一圈（默认）
        --   'only_below'      下半圈（世界 10）
        --   'silo_3_points'   silo 模式：baolei_count>1 时生成核弹发射井，否则 3 点堡垒
        --   'exclude'         排除默认堡垒生成（由世界模块自己生成）
        mode = 'silo_3_points',
        -- 是否在 baolei_count > 1 时生成核弹发射井
        enable_nuke_silo = true,
        -- 是否在 baolei_count == 1 时生成 3 个固定点堡垒（x=-65/0/65）
        use_3_points_layout = true,
        -- 用 target.position.y 还是 baolei_y 计算堡垒 y 坐标
        use_target_y = true,
    },

    --==========================================================================
    -- 星球与科技
    --==========================================================================
    -- 解锁哪些星球（原 main.lua apply_planet_surface_settings[7]）
    -- list 形式，与旧 planet_configs.planets 一致
    planet_surfaces = {'vulcanus', 'fulgora', 'gleba'},
    -- 是否对特色资源翻倍（原 main.lua create_planet_surface 中 7/8/13 分支）
    planet_resource_boost = true,
    -- 是否解锁星球发现科技（原 main.lua apply_planet_surface_settings.unlock_technologies）
    unlock_planet_technologies = true,

    -- 开局解锁的科技列表（原 main.lua apply_technology_settings 中 world_number==N 分支）
    -- 世界 7 无特殊科技解锁
    unlocked_technologies = {},
    -- 是否允许填海（原 main.lua apply_technology_settings 中 landfill_worlds 列表）
    landfill_allowed = true,

    --==========================================================================
    -- 通关奖励
    --==========================================================================
    -- 通关奖励类型（原 diff.lua world_bonus_types[7]）
    world_bonus_type = {
        name = 'character_running_speed_bonus',
        force_modifier = 'character_running_speed_modifier',
        base_value = 0.03,
        max_value = 0.2
    },
    -- 是否参与终极奖励（原 diff.lua edge_worlds 列表）
    joins_solar_system_edge = true,

    --==========================================================================
    -- 专属玩法钩子（运行时按世界分发）
    --==========================================================================
    -- car_buff 全局钩子：设置 silo 出生点 + 提示放车
    on_car_buff = on_car_buff,
    -- car_buff 玩家级钩子：世界 7 无特殊逻辑（用 nil）
    on_car_buff_player = nil,
    -- gain_xp 玩家级钩子：跟踪 max_pos 和 baolei_y
    on_gain_xp = on_gain_xp,
    -- gain_xp 全局钩子：启动 Collapse + 调整速度
    on_gain_xp_global = on_gain_xp_global,
    -- on_tick 定时器钩子：世界 7 无独立定时器
    on_tick = nil,
})
