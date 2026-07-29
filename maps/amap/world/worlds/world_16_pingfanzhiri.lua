-- maps/amap/world/worlds/world_16_pingfanzhiri.lua
-- 世界 16：平凡之日
--
-- 特殊地形：无（默认地形）
-- 特殊机制：
--   1) 开局在出生点(0,0)外 150 米随机取一点，按 100 波强度生成堡垒
--      （enemy_arty.lua fixed_wave 模式 initial_spawn，选点复用堡垒冲突检测螺旋搜索）
--   2) 堡垒每 100 波生成 1 次，位置由堡垒选点算法自行计算
--      （enemy_arty.lua fixed_wave 模式 interval_waves）
--   3) 虫子固定从存活堡垒出生，多个堡垒时每次随机挑一个
--      （main.lua get_biter_point 的 biter_spawn_rule.from_fortress）
--   4) 每 50 波集中进攻一次（仅波数为 50 整数倍的那一波刷虫，下一波即停），
--      其余波只正常囤积威胁不刷虫；无存活堡垒则不进攻
--      （modules/wave_defense/main.lua can_units_spawn 的 wave_attack_settings）
-- 通关奖励：无（world_bonus_type = nil），且不纳入世界通关挑战
--   （joins_solar_system_edge = false，不进终极奖励检查列表）

local World = require 'maps.amap.world.framework'

local world16 = {}

World.register(16, {
    --==========================================================================
    -- 元数据
    --==========================================================================
    name_key = 'amap.world_name_16',
    desc_key = 'amap.world_name_info_16',

    --==========================================================================
    -- 时间与地形
    --==========================================================================
    -- 首波延迟 15 分钟（main.lua:583 用 time_limit 设置首波 next_wave，必填）
    time_limit = 60 * 60 * 15,

    -- 无特殊地形：不注册 terrain_generator / surface_config_name / map_settings，
    -- 全部走默认地形与默认地表配置

    --==========================================================================
    -- 战斗规则
    --==========================================================================
    -- 虫子出生规则：固定从存活堡垒出生（无堡垒时不更新出生点）
    biter_spawn_rule = {
        from_fortress = true,
    },

    -- 进攻时机：每 50 波集中进攻一次；无存活堡垒不进攻。
    -- 非进攻波威胁照常囤积（set_next_wave 不受拦截），只是不刷虫。
    wave_attack_settings = {
        every = 50,
        require_fortress = true,
    },

    --==========================================================================
    -- 堡垒生成：fixed_wave 模式（按固定波数生成，与默认按时间调度互斥）
    --==========================================================================
    arty_settings = {
        mode = 'fixed_wave',
        -- 每 100 波生成 1 次（wave 100/200/300...，位置由堡垒选点算法自行计算）
        interval_waves = 100,
        -- 开局堡垒：出生点(0,0)外 150 米随机点，按 100 波强度生成
        initial_spawn = {
            min_distance = 150,
            wave_strength = 100,
        },
    },

    --==========================================================================
    -- 星球与科技（无特殊设定）
    --==========================================================================
    planet_surfaces = nil,
    unlock_planet_technologies = false,
    planet_resource_boost = false,
    unlocked_technologies = {},

    --==========================================================================
    -- 通关奖励（继承自原世界7「异次元大逃杀」的移动速度加成）
    --==========================================================================
    -- 通关奖励类型：移动速度加成（原世界7 world_bonus_types[7]）
    world_bonus_type = {
        name = 'character_running_speed_bonus',
        force_modifier = 'character_running_speed_modifier',
        base_value = 0.03,
        max_value = 0.2
    },
    -- 纳入世界通关挑战（终极奖励检查列表，替代原世界7席位）
    joins_solar_system_edge = true,

    -- 参与随机选世界池
    selectable = true,
})

return world16
