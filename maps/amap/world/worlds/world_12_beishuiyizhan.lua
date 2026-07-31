-- maps/amap/world/worlds/world_12_beishuiyizhan.lua
-- 世界 12：背水一战
--
-- 特点：silo 模式（silo_3_points）、火焰塔上限 0、
-- 弹药减伤（grenade/landmine -75%，artillery-shell -90%，无 flamethrower）、
-- 炮塔攻击奖励（turret_attack_bonus）、开局解锁基础科技。
-- 参考：原 world_table.lua / diff.lua / main.lua / enemy_arty.lua 中
-- world_number == 12 分支。

local World = require 'maps.amap.world.framework'
local Helpers = require 'maps.amap.world.world_helpers'
local WPT = require 'maps.amap.table'
local beishuiyizhan = require 'maps.amap.world.word_beishuiyizhan'

--==============================================================================
-- 地形生成器（原 world_main.lua 第 893-954 行 world_generators[12]）
--==============================================================================

local function terrain_generator(surface, position, seed, get_tile, set_tiles, event, maxs, q, w, x, y)
    if maxs <= 64 then
        beishuiyizhan.create_initial_bio_lab(surface)

        local this = WPT.get()
        if not this.initial_resources_created then
            local coal_total = 750000
            local stone_total = 750000

            local coal_area = {x_min = -60, x_max = -30, y_min = -15, y_max = 15}
            local stone_area = {x_min = 30, x_max = 60, y_min = -15, y_max = 15}

            local coal_cells = (coal_area.x_max - coal_area.x_min) * (coal_area.y_max - coal_area.y_min)
            local stone_cells = (stone_area.x_max - stone_area.x_min) * (stone_area.y_max - stone_area.y_min)

            local coal_per_cell = math.floor(coal_total / coal_cells)
            local stone_per_cell = math.floor(stone_total / stone_cells)

            for cx = coal_area.x_min, coal_area.x_max do
                for cy = coal_area.y_min, coal_area.y_max do
                    local pos = {x = cx, y = cy}
                    if surface.can_place_entity({name = "coal", position = pos, amount = coal_per_cell}) then
                        surface.create_entity({name = "coal", position = pos, amount = coal_per_cell})
                    end
                end
            end

            for sx = stone_area.x_min, stone_area.x_max do
                for sy = stone_area.y_min, stone_area.y_max do
                    local pos = {x = sx, y = sy}
                    if surface.can_place_entity({name = "stone", position = pos, amount = stone_per_cell}) then
                        surface.create_entity({name = "stone", position = pos, amount = stone_per_cell})
                    end
                end
            end

            this.initial_resources_created = true
        end
    end

    if maxs >= 64 then
        if w <= 96 then
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
-- 钩子函数实现（原 main.lua gain_xp 中 world_number==12 分支）
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

World.register(12, {
    --==========================================================================
    -- 元数据
    --==========================================================================
    name_key = 'amap.world_name_12',
    desc_key = 'amap.world_name_info_12',

    --==========================================================================
    -- 时间与地形
    --==========================================================================
    -- 25 分钟（10 分钟游戏时间 + 15 分钟首波延迟）
    -- 来源：world_table.lua world_time[12]（第 26 行）
    time_limit = 60 * 60 * 10 + 60 * 60 * 15,

    -- 引用 framework 中注册的地表配置名
    -- 来源：world_table.lua world_surface_mapping[12]（第 221 行）
    surface_config_name = 'beishuiyizhan',

    -- 不生成默认野外建筑/石头（原 world_main.lua ywjz 硬编码排除列表）
    disable_default_rocks = true,

    -- 地图尺寸设置
    -- 来源：world_table.lua world_map_settings[12]（第 263-265 行）
    map_settings = {
        starting_area = 0.6
    },

    -- 区块地形生成函数
    terrain_generator = terrain_generator,

    --==========================================================================
    -- 战斗规则
    --==========================================================================
    -- 火焰塔上限
    -- 来源：diff.lua set_diff 中 world_number==12 分支（第 72-74 行）
    max_flame = 0,

    -- 虫子生成方向规则
    -- 来源：world_table.lua biter_spawn_rules[12]（第 312-315 行）
    biter_spawn_rule = {
        k_value = 'silo_3_or_roll',  -- 有 silo 时用 k=3，否则循环
        force_x_align = true,        -- 始终强制 x 对齐
    },

    -- 弹药伤害调整
    -- 来源：main.lua apply_ammo_damage_modifiers ammo_configs[12]（第 329-333 行）
    -- 注意：没有 flamethrower 项
    ammo_damage_modifiers = {
        ['grenade'] = -0.75,
        ['landmine'] = -0.75,
        ['artillery-shell'] = -0.9
    },

    -- 虫族扩张参数
    -- 来源：main.lua apply_enemy_expansion_settings expansion_configs[12] 不存在，用默认（nil）
    enemy_expansion = nil,

    --==========================================================================
    -- 堡垒生成
    --==========================================================================
    -- 来源：enemy_arty.lua get_new_arty 中 world 12 分支
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
    -- 来源：main.lua apply_planet_surface_settings planet_configs[12] 不存在（nil）
    planet_surfaces = nil,
    -- 是否对特色资源翻倍
    -- 来源：main.lua create_planet_surface 中 7/8/13 分支（第 211 行），12 不在列表（nil）
    planet_resource_boost = nil,
    -- 是否解锁星球发现科技（默认 true，仅在 planet_surfaces 非空时生效）
    unlock_planet_technologies = true,

    -- 开局解锁的科技列表
    -- 来源：main.lua apply_technology_settings 中 world_number==12 分支（第 434-435 行）
    unlocked_technologies = {'steam-power', 'electronics', 'automation-science-pack', 'oil-processing', 'landfill'},
    -- 是否允许填海
    -- 来源：main.lua apply_technology_settings 中 landfill_worlds 列表（第 455 行 {3, 7, 8, 9, 13, 14}），12 不在列表
    -- 注意：unlocked_technologies 中含 'landfill' 会直接 researched=true，但 landfill_allowed=false
    -- 表示不通过 landfill_worlds 列表额外启用（enabled=true）。两者机制不同，以原代码为准。
    landfill_allowed = false,

    --==========================================================================
    -- 通关奖励
    --==========================================================================
    -- 通关奖励类型
    -- 来源：diff.lua world_bonus_types[12]（第 445-450 行）
    world_bonus_type = {
        name = 'turret_attack_bonus',
        custom_type = 'function',
        base_value = 0.05,
        max_value = 0.25
    },
    -- 是否参与终极奖励
    -- 来源：diff.lua edge_worlds 列表（第 914 行 fallback {1..14}），12 在列表中
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
