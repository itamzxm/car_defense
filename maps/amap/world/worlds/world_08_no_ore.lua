-- maps/amap/world/worlds/world_08_no_ore.lua
-- 世界 8：无矿石
--
-- 特点：小地图 700×700、max_flame=0、虫族扩张极慢（60*60*60*60）、
-- 虫子出生边界处理（boundary_limit=300，超出时重置到目标位置）、
-- 解锁四星球（含 aquilo）、允许填海、跟随机器人数量奖励。
-- 参考：原 world_table.lua 中 world_time[8] / world_surface_mapping[8] /
-- world_map_settings[8] / biter_spawn_rules[8] +
-- main.lua 中 apply_ammo_damage_modifiers[8]（无）/ apply_enemy_expansion_settings[8] /
-- apply_planet_surface_settings[8] / apply_technology_settings 中 world_number==8 走 else 分支 +
-- diff.lua 中 set_diff world_number==8 → max_flame=0 / world_bonus_types[8] +
-- enemy_arty.lua 中 get_new_arty（默认模式 + 边界处理 300）。

local World = require 'maps.amap.world.framework'
local world_function = require 'maps.amap.world.world_function'

--==============================================================================
-- 地形生成器（原 world_main.lua 第 692-696 行 world_generators[8]）
--==============================================================================

local function terrain_generator(surface, position, seed, get_tile, set_tiles, event, maxs, q, w, x, y)
    if maxs >= 64 then
        world_function.world_cave(surface, position, seed, get_tile, set_tiles)
    end
end

--==============================================================================
-- 钩子函数实现（原 main.lua car_buff 中 world_number==8 分支）
--==============================================================================

-- car_buff 全局钩子：提示放车（原 main.lua 行 911-918）
local function on_car_buff(this, rpg_t)
    for _, player in pairs(game.connected_players) do
        local index = player.index
        if not this.ciyuan_pos[index] then
            player.print('你还没有放车，请及时放车,build a car', {0, 255, 255})
        end
    end
end

--==============================================================================
-- 注册到框架
--==============================================================================

World.register(8, {
    --==========================================================================
    -- 元数据
    --==========================================================================
    name_key = 'amap.world_name_8',
    desc_key = 'amap.world_name_info_8',

    -- 已禁用：从随机选世界池与投票界面排除
    -- （机制文件 word_yiciyuankongjian 仍被 require 加载，但内部全部以 map.world == 8 门控，世界 8 不可选即不触发，无需删除）
    selectable = false,

    --==========================================================================
    -- 时间与地形
    --==========================================================================
    -- 60 分钟（45 分钟游戏时间 + 15 分钟首波延迟）
    -- 原文件：world_table.lua 第 22 行 world_time[8]
    time_limit = 60 * 60 * 45 + 60 * 60 * 15,

    -- 引用 framework 中注册的地表配置名
    -- 原文件：world_table.lua 第 217 行 world_surface_mapping[8]
    surface_config_name = 'no_ore',

    -- 地图尺寸设置（原 world_table.lua 第 249-253 行 world_map_settings[8]）
    map_settings = {
        width = 700,
        height = 700,
        starting_area = 0.8
    },

    -- 区块地形生成函数
    terrain_generator = terrain_generator,

    --==========================================================================
    -- 战斗规则
    --==========================================================================
    -- 火焰塔上限（原 diff.lua set_diff 第 63-65 行 world_number==8 → max_flame=0）
    max_flame = 0,

    -- 虫子生成方向规则（原 world_table.lua 第 322-326 行 biter_spawn_rules[8]）
    -- 边界处理：超出 300 米时重置生成位置为目标位置
    biter_spawn_rule = {
        boundary_limit = 300,
        boundary_action = "reset_to_target"
    },

    -- 弹药伤害调整（原 main.lua apply_ammo_damage_modifiers ammo_configs[8] 无条目）
    ammo_damage_modifiers = nil,

    -- 虫族扩张参数（原 main.lua apply_enemy_expansion_settings 第 355-358 行 expansion_configs[8]）
    -- 极长冷却，相当于关闭扩张
    enemy_expansion = {
        max_expansion_cooldown = 60 * 60 * 60 * 60,
        min_expansion_cooldown = 60 * 60 * 60 * 60
    },

    --==========================================================================
    -- 堡垒生成（原 enemy_arty.lua get_new_arty，世界 8 为默认模式 + 边界处理）
    --==========================================================================
    -- 边界处理逻辑：原 enemy_arty.lua 第 1589-1593 行硬编码 300
    -- 此处 boundary_limit 字段为说明性占位，实际逻辑仍由旧代码处理
    arty_settings = {
        -- 模式：'default' 围一圈（默认）
        mode = 'default',
        -- 边界限制：超出 300 米时堡垒位置重置为 spawn_position
        -- （原 enemy_arty.lua 第 1589-1593 行硬编码 300）
        boundary_limit = 300,
    },

    --==========================================================================
    -- 星球与科技
    --==========================================================================
    -- 解锁哪些星球（原 main.lua apply_planet_surface_settings 第 389-393 行 planet_configs[8]）
    -- list 形式，与旧 planet_configs.planets 一致
    planet_surfaces = {'vulcanus', 'fulgora', 'gleba', 'aquilo'},
    -- 是否对特色资源翻倍（原 main.lua create_planet_surface 中 8 分支，第 211 行）
    planet_resource_boost = true,
    -- 是否解锁星球发现科技（原 main.lua apply_planet_surface_settings.unlock_technologies=true）
    unlock_planet_technologies = true,

    -- 开局解锁的科技列表（原 main.lua apply_technology_settings 中 world_number==8 走 else 分支）
    unlocked_technologies = {},
    -- 是否允许填海（原 main.lua apply_technology_settings 中 landfill_worlds = {3, 7, 8, 9, 13, 14}，世界 8 在列表）
    landfill_allowed = true,

    --==========================================================================
    -- 通关奖励
    --==========================================================================
    -- 通关奖励类型（原 diff.lua world_bonus_types[8] 第 421-426 行）
    world_bonus_type = {
        name = 'following_robot_count_modifier',
        force_modifier = 'following_robot_count_modifier',
        base_value = 3,
        max_value = 20
    },
    -- 是否参与终极奖励（默认 true）
    -- 已关闭：避免禁用后卡住终极奖励判定（World.query('joins_solar_system_edge', true) 仍会列出本世界，
    --         但 world 8 不可选、map.edge_reached[8] 永不为 true，会导致「征服全部世界」永不成达成。同世界7处理）
    joins_solar_system_edge = false,

    --==========================================================================
    -- 专属玩法钩子（运行时按世界分发）
    --==========================================================================
    -- car_buff 全局钩子：提示放车
    on_car_buff = on_car_buff,
    -- car_buff 玩家级钩子：世界 8 无特殊逻辑
    on_car_buff_player = nil,
    -- gain_xp 钩子：世界 8 无特殊逻辑
    on_gain_xp = nil,
    on_gain_xp_global = nil,
    -- on_tick 钩子：世界 8 无独立定时器
    on_tick = nil,
})
