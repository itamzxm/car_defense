-- maps/amap/world/worlds/world_13_train_escape.lua
-- 世界 13：火车大逃亡
--
-- 特点：exclude 模式（不调 Public.baolei，由专属逻辑生成）、
-- 火焰塔上限 1、弹药减伤 50%、解锁三星球（vulcanus/fulgora/gleba）、
-- 崩落线出生点模式、允许填海、解锁铁路/铀/回收科技。
-- 参考：原 world_table.lua / diff.lua / main.lua / enemy_arty.lua 中
-- world_number == 13 分支。

local World = require 'maps.amap.world.framework'
local Helpers = require 'maps.amap.world.world_helpers'
local ICW = require 'maps.amap.ICW.table'
local Collapse = require 'modules.collapse'
local WPT = require 'maps.amap.table'
local WD = require 'modules.wave_defense.table'
local enemy_arty = require 'maps.amap.enemy_arty'

--==============================================================================
-- 地形生成器（原 world_main.lua 第 957-1061 行 world_generators[13]）
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
            local base_y = nearest_base - 30
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

                local spawn_chance_13 = (wave_number >= 700) and 440 or 220
                if math.random(1, spawn_chance_13) == 1 then
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

        -- 世界13：每992米生成3个堡垒；堡垒全部死亡后由轮询函数生成车厢+火箭发射井
        if q == 0 and w <= -992 and w % 992 == 0 then
            local wave_number = WD.get('wave_number')
            local baolei_worth
            if wave_number < 200 then
                local distance = math.abs(w)
                local tier = math.floor(distance / 992)
                baolei_worth = 150 + (tier - 1) * 200
                if baolei_worth < 150 then baolei_worth = 150 end
            else
                baolei_worth = wave_number
            end

            local this = WPT.get()
            if not this.world_13_pending_zones then
                this.world_13_pending_zones = {}
            end

            local arty_data = enemy_arty.get('arty')
            local baolei_id_start = #arty_data
            local baolei_y = w + 60
            enemy_arty.baolei({x = -65, y = baolei_y}, baolei_worth, surface, true)
            enemy_arty.baolei({x = 0, y = baolei_y}, baolei_worth, surface, true)
            enemy_arty.baolei({x = 65, y = baolei_y}, baolei_worth, surface, true)

            this.world_13_pending_zones[w] = {
                baolei_ids = {baolei_id_start + 1, baolei_id_start + 2, baolei_id_start + 3},
                surface = surface,
                w = w
            }
        end

        if w > 100 then
            surface.set_tiles({{name = "out-of-map", position = position}})
        end
    end
end

--==============================================================================
-- 钩子函数实现（原 main.lua car_buff/gain_xp 中 world_number==13 分支）
--==============================================================================

-- car_buff 全局钩子：设置火车头出生点（原 main.lua 行 904-909）
local function on_car_buff(this, rpg_t)
    local loco = ICW.get('locomotive')
    if loco and loco.valid then
        game.forces.player.set_spawn_position({x = loco.position.x - 5, y = loco.position.y}, loco.surface)
    end
end

-- car_buff 玩家级钩子：检查火车光圈（70 格半径，原 main.lua 行 955-972）
-- 返回 true 表示玩家在火车光圈内，应享受 buff
local function on_car_buff_player(this, player, rpg_t)
    local train_radius = 70
    local trains = player.physical_surface.find_entities_filtered({
        name = 'locomotive',
        area = {
            {player.physical_position.x - train_radius, player.physical_position.y - train_radius},
            {player.physical_position.x + train_radius, player.physical_position.y + train_radius}
        }
    })
    for _, train in pairs(trains) do
        local d2 = (player.physical_position.x - train.position.x) ^ 2 +
                   (player.physical_position.y - train.position.y) ^ 2
        if d2 <= train_radius * train_radius then
            return true
        end
    end
    return false
end

-- gain_xp 玩家级钩子：跟踪 max_pos 和 baolei_y（原 main.lua 行 1021-1029，与世界 7 共用逻辑）
local function on_gain_xp(this, player, wave_number)
    if not this.max_pos then
        this.max_pos = 0
    end
    if math.abs(player.physical_position.y) >= math.abs(this.max_pos) then
        this.max_pos = player.physical_position.y
        this.baolei_y = player.physical_position.y
    end
end

-- gain_xp 全局钩子：启动 Collapse + 调整速度（原 main.lua 行 1035-1059，与世界 7 共用逻辑）
local function on_gain_xp_global(this, wave_number)
    if wave_number >= 100 then
        Collapse.start_now(true)
    end

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

World.register(13, {
    --==========================================================================
    -- 元数据
    --==========================================================================
    name_key = 'amap.world_name_13',
    desc_key = 'amap.world_name_info_13',

    --==========================================================================
    -- 时间与地形
    --==========================================================================
    -- 60 分钟（45 分钟游戏时间 + 15 分钟首波延迟）
    -- 来源：world_table.lua world_time[13]（第 27 行）
    time_limit = 60 * 60 * 45 + 60 * 60 * 15,

    -- 引用 framework 中注册的地表配置名
    -- 来源：world_table.lua world_surface_mapping[13]（第 222 行）
    surface_config_name = 'have_ore_no_biter',

    -- 地图尺寸设置
    -- 来源：world_table.lua world_map_settings[13]（第 267-271 行）
    map_settings = {
        width = 200,
        starting_area = 0.6
    },

    -- 区块地形生成函数
    terrain_generator = terrain_generator,

    --==========================================================================
    -- 战斗规则
    --==========================================================================
    -- 火焰塔上限
    -- 来源：diff.lua set_diff 中 world_number==13 分支（第 75-77 行）
    max_flame = 1,

    -- 虫子生成方向规则
    -- 来源：world_table.lua biter_spawn_rules[13]（第 317-321 行）
    -- 崩落线出生点模式：x=0 固定，y 跟随崩落线偏移；虫子离火车最远 150 米
    biter_spawn_rule = {
        collapse_spawn = true,              -- 启用崩落线出生点模式
        collapse_spawn_offset = -25,        -- 崩落线上方 25 格
        train_max_behind_distance = 150,    -- 虫子离火车最远 150 米
    },

    -- 弹药伤害调整
    -- 来源：main.lua apply_ammo_damage_modifiers ammo_configs[13]（第 312-317 行）
    ammo_damage_modifiers = {
        ['grenade'] = -0.5,
        ['landmine'] = -0.5,
        ['flamethrower'] = -0.6,
        ['artillery-shell'] = -0.5
    },

    -- 虫族扩张参数
    -- 来源：main.lua apply_enemy_expansion_settings expansion_configs[13] 不存在，用默认（nil）
    enemy_expansion = nil,

    --==========================================================================
    -- 堡垒生成
    --==========================================================================
    -- 来源：enemy_arty.lua get_new_arty 中 world 13 分支
    --（第 1598 行 if not is_silo_world and this.world_number ~= 13 then Public.baolei(...)）
    -- mode = 'exclude'：不调 Public.baolei，由世界模块自己生成（world_main.lua 中每 992 米生成 3 个堡垒）
    arty_settings = {
        mode = 'exclude',
    },

    --==========================================================================
    -- 星球与科技
    --==========================================================================
    -- 解锁哪些星球
    -- 来源：main.lua apply_planet_surface_settings planet_configs[13]（第 381-384 行）
    planet_surfaces = {'vulcanus', 'fulgora', 'gleba'},
    -- 是否对特色资源翻倍
    -- 来源：main.lua create_planet_surface 中 7/8/13 分支（第 211 行），13 在列表
    planet_resource_boost = true,
    -- 是否解锁星球发现科技
    -- 来源：main.lua apply_planet_surface_settings planet_configs[13].unlock_technologies = true
    unlock_planet_technologies = true,

    -- 开局解锁的科技列表
    -- 来源：main.lua apply_technology_settings 中 world_number==13 分支（第 438-439 行）
    unlocked_technologies = {'elevated-rail', 'uranium-processing', 'recycling'},
    -- 是否允许填海
    -- 来源：main.lua apply_technology_settings 中 landfill_worlds 列表（第 455 行 {3, 7, 8, 9, 13, 14}），13 在列表
    landfill_allowed = true,

    --==========================================================================
    -- 通关奖励
    --==========================================================================
    -- 通关奖励类型
    -- 来源：diff.lua world_bonus_types[13] 不存在（nil）
    world_bonus_type = nil,
    -- 是否参与终极奖励
    -- 来源：diff.lua edge_worlds 列表（第 914 行 fallback {1..14}），13 在列表中
    joins_solar_system_edge = true,

    --==========================================================================
    -- 专属玩法钩子（运行时按世界分发）
    --==========================================================================
    -- car_buff 全局钩子：设置火车头出生点
    on_car_buff = on_car_buff,
    -- car_buff 玩家级钩子：检查火车光圈（70 格半径）
    on_car_buff_player = on_car_buff_player,
    -- gain_xp 玩家级钩子：跟踪 max_pos 和 baolei_y
    on_gain_xp = on_gain_xp,
    -- gain_xp 全局钩子：启动 Collapse + 调整速度
    on_gain_xp_global = on_gain_xp_global,
    -- on_tick 钩子：世界 13 无独立定时器
    on_tick = nil,
})
