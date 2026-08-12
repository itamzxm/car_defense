-- maps/amap/instance/modules/mini_td.lua
-- 小小塔防玩法模块
--
-- 玩法类型：mini_td
-- 玩法说明：守护中心商店，抵御 N 波虫子攻击
--   - 场地：48x48 外围石墙（达到 24 米作用范围上限，给玩家足够空间放塔）
--   - 中心 (0, 2) 放置 market 实体作为商店（minable=false / destructible=true）
--   - 玩家进入副本后按秒获得金币（初始 1 coin/s，可购买"每秒收益"升级）
--   - 商店售卖：子弹、机枪、炮塔、石墙（give-item 类，游戏自动处理）
--                子弹伤害升级、子弹射速升级、每秒收益升级（nothing 类，本模块处理）
--   - 虫子从竞技场四个角落生成（避开玩家中心区域），用副本专属 enemy force
--     （不用主世界 'enemy' force，避免继承主世界虫子的强化属性）
--   - 用 unit_group 指挥 attack_area 攻击中心 market
--   - 每波分批生成（每批 5 个，每 30 tick 一批）
--   - 失败：中心 market 被毁 / 玩家死亡
--   - 胜利：击退所有波次
--
-- 难度波数（用户要求 easy = 20 波）：
--   easy   = 20 波
--   normal = 25 波
--   hard   = 30 波

local Instance = require 'maps.amap.instance.instance'
local Event = require 'utils.event'

local M = {}

--==============================================================================
-- 元数据
--==============================================================================

M.type = 'mini_td'
M.display_name_key = 'amap.instance_mini_td_name'
M.description_key = 'amap.instance_mini_td_desc'
M.gameplay_desc_key = 'amap.instance_mini_td_gameplay'
M.victory_condition_key = 'amap.instance_mini_td_victory'
M.icon = 'item/stone-wall'
M.time_limit_default = 30 * 60 * 60  -- 30 分钟上限（足够打完 30 波）

--==============================================================================
-- 难度
--==============================================================================

M.difficulty_settings = {
    easy = {
        name = 'easy',
        recycling_efficiency = 1,
        max_coins = 0,                -- 0 表示不限，模块自己管理金币 GUI
        display_name_key = 'dungeon_difficulty_easy',
        arena_half = 24,              -- 48x48（达到 24 米作用范围上限，给玩家足够空间放塔）
        wave_count = 20,              -- 用户要求 easy = 20 波
        wave_interval = 3 * 60,       -- 杀完一波后 3 秒休整即进下一波（tick）
        batch_size = 8,               -- 每批生成数
        batch_interval = 30,          -- 每批间隔 30 tick
        threat_multiplier = 5,        -- 每波威胁值 = 波数 × 此系数（控制总量与类型混合）
        melee_ratio = 0.6,            -- 60% 近战(biter) + 40% 远程(spitter)
        initial_coins = 80,           -- 初始金币
        initial_income = 2,           -- 初始每秒收益
    },
    normal = {
        name = 'normal',
        recycling_efficiency = 1,
        max_coins = 0,
        display_name_key = 'dungeon_difficulty_normal',
        arena_half = 24,              -- 48x48（达到 24 米上限）
        wave_count = 25,
        wave_interval = 3 * 60,
        batch_size = 10,
        batch_interval = 30,
        threat_multiplier = 8,
        melee_ratio = 0.6,
        initial_coins = 80,
        initial_income = 2,
    },
    hard = {
        name = 'hard',
        recycling_efficiency = 1,
        max_coins = 0,
        display_name_key = 'dungeon_difficulty_hard',
        arena_half = 24,              -- 48x48（达到 24 米上限，不再扩大）
        wave_count = 30,
        wave_interval = 3 * 60,
        batch_size = 12,
        batch_interval = 25,
        threat_multiplier = 12,
        melee_ratio = 0.6,
        initial_coins = 60,
        initial_income = 2,
    },
}

--==============================================================================
-- 常量
--==============================================================================

-- 顶栏 GUI 元素名
local GUI_WAVE = 'dungeon_mt_wave'
local GUI_CORE = 'dungeon_mt_core'
local GUI_COINS = 'dungeon_mt_coins'
local GUI_INCOME = 'dungeon_mt_income'

-- 商店 offer 索引（与 build_shop_offers 顺序一致）
-- 1-5: give-item 类（游戏自动处理）
-- 6:   子弹伤害升级
-- 7:   子弹射速升级
-- 8:   每秒收益升级
local OFFER_BULLET_DAMAGE = 6
local OFFER_BULLET_SPEED = 7
local OFFER_INCOME = 8

-- 升级价格（固定，不递增；玩家通过反复购买叠加效果）
local PRICE_BULLET_DAMAGE = 100
local PRICE_BULLET_SPEED = 100
local PRICE_INCOME = 150

-- 每次升级的效果增量
local INC_BULLET_DAMAGE = 0.1   -- +10% 子弹伤害
local INC_BULLET_SPEED = 0.1    -- +10% 子弹射速
local INC_INCOME = 1            -- +1 coin/s

-- 副本专属虫子演化（参考 wave_defense/biter_rolls.lua 的威胁值思路）
-- 把主世界 1000+ 波的演化压缩到 20-30 波内，每波按权重混合 size
-- 威胁值表（压缩后：small=1 / medium=3 / big=8 / behemoth=20，
-- 使 20-30 波既能出现大型虫子，又保持合理单位数量）
local THREAT_VALUES = {
    ['small-biter'] = 1, ['small-spitter'] = 1,
    ['medium-biter'] = 3, ['medium-spitter'] = 3,
    ['big-biter'] = 8, ['big-spitter'] = 8,
    ['behemoth-biter'] = 20, ['behemoth-spitter'] = 20,
}

-- 按波数返回 {size = 相对权重} 表
local function get_biter_mix(wave)
    if wave <= 3 then return {small = 1.0} end
    if wave <= 6 then return {small = 0.7, medium = 0.3} end
    if wave <= 10 then return {small = 0.4, medium = 0.6} end
    if wave <= 14 then return {small = 0.2, medium = 0.4, big = 0.4} end
    if wave <= 18 then return {medium = 0.3, big = 0.4, behemoth = 0.3} end
    return {medium = 0.2, big = 0.4, behemoth = 0.4}
end

-- 按权重随机选一个 size
local function roll_size(mix)
    local r = math.random()
    local cum = 0
    for size, w in pairs(mix) do
        cum = cum + w
        if r <= cum then return size end
    end
    return 'small'
end

-- 按波数与威胁值上限生成整波虫子表（参考 wave_defense 的威胁出怪方式）
-- 累计威胁值达到 max_threat 即停止；melee_ratio 比例近战(biter) + 远程(spitter)
local function generate_wave_unit_table(wave, max_threat, melee_ratio)
    local mix = get_biter_mix(wave)
    local units = {}
    local total = 0
    local guard = 0
    while total < max_threat and guard < 1000 do
        guard = guard + 1
        local is_melee = math.random() < melee_ratio
        local size = roll_size(mix)
        local name = is_melee and (size .. '-biter') or (size .. '-spitter')
        local tv = THREAT_VALUES[name] or 1
        if total + tv > max_threat then
            -- 剩余威胁值不够放当前类型，用 small 填满（保证整波打满 max_threat）
            if total + 1 <= max_threat then
                units[#units + 1] = 'small-biter'
                total = total + 1
            else
                break
            end
        else
            units[#units + 1] = name
            total = total + tv
        end
    end
    return units
end

-- 4 个生成位置（竞技场四个角落，避开玩家中心区域）
-- 用函数返回，因为依赖 arena_half
local function get_corner_positions(ah)
    -- ah-1 留出墙的位置
    local e = ah - 1
    return {
        {x = -e, y = -e},  -- 左上
        {x =  e, y = -e},  -- 右上
        {x = -e, y =  e},  -- 左下
        {x =  e, y =  e},  -- 右下
    }
end

--==============================================================================
-- 辅助函数
--==============================================================================

-- 构建商店 offer 列表（顺序固定，offer_index 与常量一致）
local function build_shop_offers()
    return {
        {  -- 1: 普通子弹
            price = {{name = "coin", count = 2}},
            offer = {type = 'give-item', item = 'firearm-magazine', count = 10}
        },
        {  -- 2: 穿甲子弹
            price = {{name = "coin", count = 5}},
            offer = {type = 'give-item', item = 'piercing-rounds-magazine', count = 10}
        },
        {  -- 3: 冲锋枪
            price = {{name = "coin", count = 30}},
            offer = {type = 'give-item', item = 'submachine-gun', count = 1}
        },
        {  -- 4: 机枪炮塔
            price = {{name = "coin", count = 25}},
            offer = {type = 'give-item', item = 'gun-turret', count = 1}
        },
        {  -- 5: 石墙
            price = {{name = "coin", count = 3}},
            offer = {type = 'give-item', item = 'stone-wall', count = 10}
        },
        {  -- 6: 子弹伤害升级
            price = {{name = "coin", count = PRICE_BULLET_DAMAGE}},
            offer = {
                type = 'nothing',
                effect_description = {'amap.mini_td_buy_bullet_damage'}
            }
        },
        {  -- 7: 子弹射速升级
            price = {{name = "coin", count = PRICE_BULLET_SPEED}},
            offer = {
                type = 'nothing',
                effect_description = {'amap.mini_td_buy_bullet_speed'}
            }
        },
        {  -- 8: 每秒收益升级
            price = {{name = "coin", count = PRICE_INCOME}},
            offer = {
                type = 'nothing',
                effect_description = {'amap.mini_td_buy_income'}
            }
        },
    }
end

-- 在中心创建 market 商店
local function create_center_market(surface, force)
    local market = surface.create_entity({
        name = 'market',
        position = {0, 2},
        force = force,
    })
    if not market or not market.valid then
        return nil
    end
    market.minable_flag = false
    market.destructible = true  -- 可被虫子攻击，玩家需保护

    -- 添加商店道具
    for _, offer in ipairs(build_shop_offers()) do
        market.add_market_item(offer)
    end

    return market
end

-- 生成竞技场外围石墙（不可破坏）
local function build_arena_walls(surface, ah, force)
    for x = -ah, ah do
        for _, y_off in ipairs({-ah - 1, ah + 1}) do
            local wall = surface.create_entity({
                name = 'stone-wall', position = {x, y_off}, force = force,
                move_stuck_players = true
            })
            if wall then
                wall.destructible = false
                wall.minable_flag = false
            end
        end
    end
    for y = -ah - 1, ah + 1 do
        for _, x_off in ipairs({-ah - 1, ah + 1}) do
            local wall = surface.create_entity({
                name = 'stone-wall', position = {x_off, y}, force = force,
                move_stuck_players = true
            })
            if wall then
                wall.destructible = false
                wall.minable_flag = false
            end
        end
    end
end

-- 顶栏 GUI 创建/更新
local function update_top_gui(player, md)
    local top = player.gui.top
    local function ensure(name)
        local lbl = top[name]
        if not lbl then
            lbl = top.add({type = 'label', name = name, caption = ''})
        end
        return lbl
    end

    -- 波次信息
    local wave_text
    if md.wave_state == 'idle' then
        local sec = math.max(0, math.floor((md.next_wave_tick - game.tick) / 60))
        wave_text = {'amap.mini_td_wave_countdown', md.current_wave, md.wave_count, sec}
    else
        wave_text = {'amap.mini_td_wave_info', md.current_wave, md.wave_count}
    end
    ensure(GUI_WAVE).caption = wave_text

    -- 核心血量
    local core_hp = 0
    if md.market and md.market.valid then
        core_hp = math.floor(md.market.health)
    end
    ensure(GUI_CORE).caption = {'amap.mini_td_core_hp', core_hp}

    -- 金币数
    local coins = 0
    if player.character and player.character.valid then
        coins = player.character.get_item_count('coin')
    end
    ensure(GUI_COINS).caption = {'amap.mini_td_coins', coins}

    -- 每秒收益
    ensure(GUI_INCOME).caption = {'amap.mini_td_income', md.coins_per_sec}
end

local function cleanup_top_gui(player)
    local top = player.gui.top
    for _, name in ipairs({GUI_WAVE, GUI_CORE, GUI_COINS, GUI_INCOME}) do
        if top[name] then top[name].destroy() end
    end
end

-- 在竞技场四个角落之一生成一批虫子，编入 unit_group 攻击中心 market
-- 使用副本专属 enemy force（不用主世界 'enemy' force，避免继承主世界虫子的强化属性）
local function spawn_biter_batch(surface, ah, market, units_slice, enemy_force)
    if not market or not market.valid then return 0 end
    if not enemy_force then return 0 end

    -- 随机选一个角落
    local corners = get_corner_positions(ah)
    local spawn_pos = corners[math.random(#corners)]

    local unit_group = surface.create_unit_group({
        position = spawn_pos,
        force = enemy_force,
    })

    local spawned = 0

    for _, biter_name in ipairs(units_slice) do
        -- 在 spawn_pos 附近找可放置位置
        local pos = surface.find_non_colliding_position(biter_name, spawn_pos, 8, 1)
        if not pos then pos = spawn_pos end
        local biter = surface.create_entity({
            name = biter_name,
            position = pos,
            force = enemy_force,
        })
        if biter and biter.valid then
            biter.ai_settings.allow_destroy_when_commands_fail = true
            biter.ai_settings.do_separation = true
            unit_group.add_member(biter)
            spawned = spawned + 1
        end
    end

    -- 指挥虫子攻击中心 market 区域（attack_area 会攻击范围内的所有敌方实体）
    if spawned > 0 then
        unit_group.set_command({
            type = defines.command.attack_area,
            destination = market.position,
            radius = 10,
            distraction = defines.distraction.by_enemy,
        })
    end

    -- unit_group 不需要手动销毁，成员死后自动清理
    return spawned
end

-- 清完一波后推进：打印提示并切到 idle（短暂休整后进下一波）或 finished（通关）
local function advance_after_clear(player, md)
    player.print({'amap.mini_td_wave_cleared', md.current_wave}, {r = 0.4, g = 1, b = 0.4})
    if md.current_wave >= md.wave_count then
        md.wave_state = 'finished'
        md.finished = true
        md.victory = true
    else
        md.wave_state = 'idle'
        md.next_wave_tick = game.tick + md.diff.wave_interval
    end
end

-- 创建副本专属 enemy force（不用主世界 'enemy' force，避免继承主世界虫子的强化属性）
-- force 名格式：dungeon_enemy_<player.name>
local function setup_dungeon_enemy_force(player, player_force)
    local force_name = "dungeon_enemy_" .. player.name
    local force = game.forces[force_name]
    if not force then
        force = game.create_force(force_name)
    end

    -- 与玩家 force 互相敌对（cease_fire=false, friend=false）
    force.set_cease_fire(player_force, false)
    force.set_friend(player_force, false)
    player_force.set_cease_fire(force, false)
    player_force.set_friend(force, false)

    -- 与主世界 player force 也敌对（避免虫子跑到主世界）
    local main_player = game.forces['player']
    if main_player then
        force.set_cease_fire(main_player, false)
        force.set_friend(main_player, false)
        main_player.set_cease_fire(force, false)
        main_player.set_friend(force, false)
    end

    -- 与主世界 enemy force 友好（避免互相攻击）
    local main_enemy = game.forces['enemy']
    if main_enemy then
        force.set_cease_fire(main_enemy, true)
        force.set_friend(main_enemy, true)
        main_enemy.set_cease_fire(force, true)
        main_enemy.set_friend(force, true)
    end

    -- 注意：evolution_factor 是 enemy force 专属属性，不能在自定义 force 上设置
    -- （Factorio 2.x 会报 "LuaForce doesn't contain key evolution_factor"）
    -- 而且我们用 create_entity 指定具体虫子类型，evolution_factor 不影响生成结果

    return force, force_name
end

-- 清理副本 enemy force
local function cleanup_dungeon_enemy_force(force_name)
    if not force_name then return end
    local force = game.forces[force_name]
    if not force then return end
    -- merge 到 enemy force（统一清理）
    game.merge_forces(force_name, 'enemy')
end

--==============================================================================
-- 钩子
--==============================================================================

function M.on_surface_init(surface, player, data, difficulty_key)
    local diff = M.difficulty_settings[difficulty_key] or M.difficulty_settings.easy
    local ah = diff.arena_half

    -- 全图草地
    local tiles = {}
    for x = -ah - 1, ah + 1 do
        for y = -ah - 1, ah + 1 do
            tiles[#tiles + 1] = {name = 'grass-1', position = {x, y}}
        end
    end
    surface.set_tiles(tiles)

    -- 中心出生区标记
    for x = -1, 1 do
        for y = -1, 1 do
            surface.set_tiles({{name = 'hazard-concrete-left', position = {x, y}}})
        end
    end

    -- 外围石墙
    build_arena_walls(surface, ah, player.force)

    -- 中心 market 商店
    local market = create_center_market(surface, player.force)

    -- 创建副本专属 enemy force（不用主世界 'enemy'，避免继承主世界虫子的强化属性）
    local enemy_force, enemy_force_name = setup_dungeon_enemy_force(player, player.force)

    data.module_data = {
        arena_half = ah,
        market = market,
        diff = diff,
        enemy_force = enemy_force,
        enemy_force_name = enemy_force_name,
        wave_count = diff.wave_count,
        current_wave = 0,
        wave_state = 'idle',         -- idle / spawning / fighting / finished
        next_wave_tick = game.tick + 15 * 60,  -- 进入后 15 秒开始第 1 波
        next_batch_tick = 0,
        wave_units = {},               -- 当前波待生成的虫子名列表
        last_count_check_tick = game.tick,
        batch_size = diff.batch_size,
        batch_interval = diff.batch_interval,
        biters_alive = 0,
        coins_per_sec = diff.initial_income,
        last_coin_tick = game.tick,
        damage_level = 0,
        speed_level = 0,
        income_level = 0,
        finished = false,
        victory = false,
    }

    data.time_limit = M.time_limit_default
    surface.always_day = true
end

function M.on_enter(player, data, difficulty_key)
    local md = data.module_data
    if not md then return end

    -- 给玩家初始装备
    local inv = player.get_main_inventory()
    if inv then
        inv.insert({name = 'submachine-gun', count = 1})
        inv.insert({name = 'firearm-magazine', count = 100})
        inv.insert({name = 'piercing-rounds-magazine', count = 50})
        inv.insert({name = 'gun-turret', count = 5})
        inv.insert({name = 'stone-wall', count = 20})
    end

    -- 初始金币
    local diff = md.diff
    if player.character and player.character.valid then
        player.character.insert({name = 'coin', count = diff.initial_coins})
    end

    -- 初始每秒收益已设为 diff.initial_income（在 on_surface_init 中）
    -- 初始子弹伤害/射速 modifier 保持 0（玩家 force 默认）

    -- 隐藏框架的 coins label（模块自己管理金币 GUI）
    local top = player.gui.top
    if top['dungeon_coins'] then top['dungeon_coins'].destroy() end

    update_top_gui(player, md)
    player.print({'amap.mini_td_enter'}, {r = 0, g = 1, b = 0})
    player.print({'amap.mini_td_hint'}, {r = 1, g = 0.8, b = 0})
end

function M.on_tick(player, data)
    local md = data.module_data
    if not md or md.finished then return end

    -- 按秒给金币（每 60 tick 一次，加 coins_per_sec 个）
    if game.tick - md.last_coin_tick >= 60 then
        local elapsed = math.floor((game.tick - md.last_coin_tick) / 60)
        local coins_to_add = elapsed * md.coins_per_sec
        if coins_to_add > 0 and player.character and player.character.valid then
            player.character.insert({name = 'coin', count = coins_to_add})
        end
        md.last_coin_tick = md.last_coin_tick + elapsed * 60
    end

    -- 波次管理
    if md.wave_state == 'idle' then
        -- 等待下一波开始
        if game.tick >= md.next_wave_tick then
            md.current_wave = md.current_wave + 1
            if md.current_wave > md.wave_count then
                -- 不应该到这里，check_victory 会提前判胜利
                md.wave_state = 'finished'
            else
                -- 开始新波：按威胁值生成整波虫子表（参考 wave_defense 威胁出怪方式）
                local diff = md.diff
                local max_threat = md.current_wave * diff.threat_multiplier
                md.wave_units = generate_wave_unit_table(md.current_wave, max_threat, diff.melee_ratio)
                md.next_batch_tick = game.tick
                md.wave_state = 'spawning'
                md.biters_alive = 0  -- 重新计数本波存活虫子
                player.print({'amap.mini_td_wave_start', md.current_wave}, {r = 1, g = 0.4, b = 0.4})
            end
        end

    elseif md.wave_state == 'spawning' then
        -- 分批生成（从 wave_units 表头取一批）
        if game.tick >= md.next_batch_tick then
            local this_batch = math.min(md.batch_size, #md.wave_units)
            if this_batch > 0 and md.market and md.market.valid then
                local slice = {}
                for i = 1, this_batch do slice[i] = md.wave_units[i] end
                for i = 1, this_batch do table.remove(md.wave_units, 1) end
                local spawned = spawn_biter_batch(
                    player.surface, md.arena_half, md.market, slice, md.enemy_force
                )
                md.biters_alive = md.biters_alive + spawned
            end

            if #md.wave_units <= 0 then
                md.wave_state = 'fighting'
            else
                md.next_batch_tick = game.tick + md.batch_interval
            end
        end

    elseif md.wave_state == 'fighting' then
        -- 兜底：周期性用 surface 统计副本 enemy force 的 unit 数，
        -- 处理虫子因寻路失败被 destroy（不触发 on_entity_died）而漏计的情况
        if not md.last_count_check_tick or game.tick - md.last_count_check_tick >= 30 then
            md.last_count_check_tick = game.tick
            local surface = player.surface
            if surface and md.enemy_force then
                local alive = surface.count_entities_filtered({
                    area = {{-md.arena_half - 3, -md.arena_half - 3}, {md.arena_half + 3, md.arena_half + 3}},
                    force = md.enemy_force,
                    type = 'unit',
                })
                if alive == 0 and md.biters_alive > 0 then
                    md.biters_alive = 0
                end
            end
        end
        -- 杀完一波（虫子全部清空）立即进入下一波
        if md.biters_alive <= 0 then
            advance_after_clear(player, md)
        end
    end

    -- 检测 market 是否被毁（on_entity_died 也会处理，这里做兜底）
    if md.market and not md.market.valid then
        md.market = nil
        if not md.finished then
            md.finished = true
            md.victory = false
        end
    end

    update_top_gui(player, md)
end

function M.check_victory(player, data)
    local md = data.module_data
    if not md then return nil end

    if md.finished then
        if md.victory then
            -- 通关奖励：根据通关波数和剩余时间给奖励系数
            local waves_ratio = md.current_wave / md.wave_count
            local mult = 1.0 + waves_ratio * 0.5
            Instance.set_reward_multiplier(player, mult)
            return 'victory'
        else
            return 'defeat'
        end
    end

    return nil
end

function M.on_player_died(player, data)
    -- 用户要求：玩家死亡立马退出游戏（这里走 defeat 流程，框架会自动 exit）
    local md = data.module_data
    if not md then return end
    if md.finished then return end
    md.finished = true
    md.victory = false
end

function M.on_entity_died(player, event)
    local data = Instance.get_data(player.index)
    if not data then return end
    local md = data.module_data
    if not md then return end

    local entity = event.entity
    if not entity or not entity.valid then return end

    -- 中心 market 被毁 → 失败
    if md.market and entity == md.market then
        md.market = nil
        if not md.finished then
            md.finished = true
            md.victory = false
        end
        return
    end

    -- 虫子死亡 → 计数 - 1（必须是本副本 enemy force 的虫子，含 biter/spitter 两类）
    local name = entity.name
    if THREAT_VALUES[name] and md.enemy_force and entity.force == md.enemy_force then
        if md.biters_alive > 0 then
            md.biters_alive = md.biters_alive - 1
        end
        -- 杀完一波（最后一只虫子死亡）立即进入下一波
        if md.wave_state == 'fighting' and md.biters_alive <= 0 then
            advance_after_clear(player, md)
        end
    end
end

function M.on_exit(player, data, reason)
    local md = data.module_data
    if not md then return end

    -- 清理模块 GUI
    pcall(cleanup_top_gui, player)

    -- 恢复 force modifier（避免污染主世界，虽然 force 会被 cleanup，但保险起见）
    if player.force then
        pcall(function()
            player.force.set_ammo_damage_modifier('bullet', 0)
            player.force.set_gun_speed_modifier('bullet', 0)
        end)
    end

    -- 清理副本专属 enemy force
    pcall(cleanup_dungeon_enemy_force, md.enemy_force_name)

    -- 通关/失败消息
    if md.victory then
        player.print({'amap.mini_td_victory_msg', md.wave_count}, {r = 0, g = 1, b = 0})
    else
        player.print({'amap.mini_td_defeat_msg', md.current_wave}, {r = 1, g = 0.3, b = 0.3})
    end
end

--==============================================================================
-- 市场购买事件（处理 nothing 类升级）
--==============================================================================

-- 注意：rock.lua 已注册 on_market_item_purchased，但只处理主世界 this.shop
-- 这里再注册一个 handler，追加到 handlers 列表，专门处理副本 market
-- 两个 handler 都会被调用，rock.lua 的会在 market ~= this.shop 时 return
local function on_market_item_purchased(event)
    local market = event.market
    if not market or not market.valid then return end

    local player = game.players[event.player_index]
    if not player or not player.valid then return end

    -- 通过 Instance.get_data 判断玩家是否在 mini_td 副本中
    local data = Instance.get_data(player.index)
    if not data or not data.active then return end
    if data.instance_type ~= M.type then return end

    local md = data.module_data
    if not md then return end

    -- 必须是本玩家副本的 market
    if not md.market or md.market ~= market then return end

    local offer_index = event.offer_index
    local offers = market.get_market_items()
    if not offers or not offers[offer_index] then return end
    local bought_offer = offers[offer_index].offer

    -- give-item 类由游戏自动处理
    if bought_offer.type ~= 'nothing' then return end

    local force = player.force
    if not force then return end

    -- 应用升级效果（金币已由游戏扣除）
    if offer_index == OFFER_BULLET_DAMAGE then
        local old = force.get_ammo_damage_modifier('bullet') or 0
        force.set_ammo_damage_modifier('bullet', old + INC_BULLET_DAMAGE)
        md.damage_level = md.damage_level + 1
        player.print({'amap.mini_td_upgrade_done', {'amap.mini_td_buy_bullet_damage'}, md.damage_level},
                     {r = 0.4, g = 1, b = 0.4})

    elseif offer_index == OFFER_BULLET_SPEED then
        local old = force.get_gun_speed_modifier('bullet') or 0
        force.set_gun_speed_modifier('bullet', old + INC_BULLET_SPEED)
        md.speed_level = md.speed_level + 1
        player.print({'amap.mini_td_upgrade_done', {'amap.mini_td_buy_bullet_speed'}, md.speed_level},
                     {r = 0.4, g = 1, b = 0.4})

    elseif offer_index == OFFER_INCOME then
        md.coins_per_sec = md.coins_per_sec + INC_INCOME
        md.income_level = md.income_level + 1
        player.print({'amap.mini_td_upgrade_done', {'amap.mini_td_buy_income'}, md.coins_per_sec},
                     {r = 1, g = 0.85, b = 0.2})
    end
end

Event.add(defines.events.on_market_item_purchased, on_market_item_purchased)

--==============================================================================
-- 注册
--==============================================================================

Instance.register(M.type, M)
return M
