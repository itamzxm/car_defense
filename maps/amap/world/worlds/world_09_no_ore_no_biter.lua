-- maps/amap/world/worlds/world_09_no_ore_no_biter.lua
-- 世界 9：无矿石无虫子
--
-- 特点：超小地图 214 宽、max_flame=0、silo 模式（k=silo_3_or_roll，强 x 对齐）、
-- 弹药减伤 75~90%、允许填海、实验室速度奖励。
-- 参考：原 world_table.lua 中 world_time[9] / world_surface_mapping[9] /
-- world_map_settings[9] / biter_spawn_rules[9] +
-- main.lua 中 apply_ammo_damage_modifiers[9] / apply_enemy_expansion_settings[9]（无）/
-- apply_planet_surface_settings[9]（无）/ apply_technology_settings 中 world_number==9 走 else 分支 +
-- diff.lua 中 set_diff world_number==9 → max_flame=0 / world_bonus_types[9] +
-- enemy_arty.lua 中 get_new_arty（silo 模式 7/9/11/12 之一，interval=35）。

local World = require 'maps.amap.world.framework'
local Helpers = require 'maps.amap.world.world_helpers'
local world_function = require 'maps.amap.world.world_function'

--==============================================================================
-- 地形生成器（原 world_main.lua 第 699-729 行 world_generators[9]）
--==============================================================================

local function terrain_generator(surface, position, seed, get_tile, set_tiles, event, maxs, q, w, x, y)
    if maxs >= 64 then
        if w > 0 then
            if q == 0 then
                if w % 200 == 0 and w % 1000 ~= 0 then
                    local abc = math.floor(w / 200)
                    if abc >= 3 then abc = 3 end
                    world_function.crate_ore(surface, position, abc, 40)
                    world_function.crate_water(surface, position, abc * 2)
                end
                if w % 1000 == 0 then
                    world_function.crate_uore(surface, position, abc, 40)
                end
            end
        else
            if w <= -100 then
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

--==============================================================================
-- 钩子函数实现（原 main.lua gain_xp 中 world_number==9 分支）
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

World.register(9, {
    --==========================================================================
    -- 元数据
    --==========================================================================
    name_key = 'amap.world_name_9',
    desc_key = 'amap.world_name_info_9',

    --==========================================================================
    -- 时间与地形
    --==========================================================================
    -- 60 分钟（45 分钟游戏时间 + 15 分钟首波延迟）
    -- 原文件：world_table.lua 第 23 行 world_time[9]
    time_limit = 60 * 60 * 45 + 60 * 60 * 15,

    -- 引用 framework 中注册的地表配置名
    -- 原文件：world_table.lua 第 218 行 world_surface_mapping[9]
    surface_config_name = 'no_ore_no_biter',

    -- 不生成默认野外建筑/石头（原 world_main.lua ywjz 硬编码排除列表）
    disable_default_rocks = true,

    -- 地图尺寸设置（原 world_table.lua 第 255-258 行 world_map_settings[9]）
    map_settings = {
        width = 214,
        starting_area = 0.6
    },

    -- 区块地形生成函数
    terrain_generator = terrain_generator,

    --==========================================================================
    -- 战斗规则
    --==========================================================================
    -- 火焰塔上限（原 diff.lua set_diff 第 63-65 行 world_number==9 → max_flame=0）
    max_flame = 0,

    -- 虫子生成方向规则（原 world_table.lua 第 297-300 行 biter_spawn_rules[9]）
    -- 有 silo 时 k=3（右上方向），否则循环；强制 x 对齐
    biter_spawn_rule = {
        k_value = "silo_3_or_roll",
        force_x_align = true,
    },

    -- 弹药伤害调整（原 main.lua apply_ammo_damage_modifiers 第 318-323 行 ammo_configs[9]）
    -- silo 世界必须降低爆炸类伤害 ≥75%
    ammo_damage_modifiers = {
        ['grenade'] = -0.75,
        ['landmine'] = -0.75,
        ['flamethrower'] = -0.8,
        ['artillery-shell'] = -0.9
    },

    -- 虫族扩张参数（原 main.lua apply_enemy_expansion_settings expansion_configs[9] 无条目）
    enemy_expansion = nil,

    --==========================================================================
    -- 堡垒生成（原 enemy_arty.lua get_new_arty 中 7/9/11/12 分支）
    --==========================================================================
    arty_settings = {
        -- 生成间隔（默认 20，silo 世界为 35）
        interval = 35,
        -- 模式：
        --   'silo_3_points'   silo 模式：baolei_count>1 时生成核弹发射井，否则 3 点堡垒
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
    -- 解锁哪些星球（原 main.lua apply_planet_surface_settings planet_configs[9] 无条目）
    planet_surfaces = nil,
    -- 是否对特色资源翻倍（原 main.lua create_planet_surface 中无 9 分支）
    planet_resource_boost = nil,
    -- 是否解锁星球发现科技
    unlock_planet_technologies = nil,

    -- 开局解锁的科技列表（原 main.lua apply_technology_settings 中 world_number==9 走 else 分支）
    unlocked_technologies = {},
    -- 是否允许填海（原 main.lua apply_technology_settings 中 landfill_worlds = {3, 7, 8, 9, 13, 14}，世界 9 在列表）
    landfill_allowed = true,

    --==========================================================================
    -- 通关奖励
    --==========================================================================
    -- 通关奖励类型（原 diff.lua world_bonus_types[9] 第 427-432 行）
    world_bonus_type = {
        name = 'laboratory_speed_bonus',
        force_modifier = 'laboratory_speed_modifier',
        base_value = 0.1,
        max_value = 0.4
    },
    -- 是否参与终极奖励（默认 true）
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
