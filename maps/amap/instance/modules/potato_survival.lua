-- maps/amap/instance/modules/potato_survival.lua
-- 土豆兄弟 (Brotato-like) 波次生存 + 商店升级系统
--
-- 核心循环: 波次战斗 → 杀光敌人 → 商店升级 → 下一波 → ... → 胜利
-- 金币: 击杀直接入账，无需拾取
--
-- 钩子实现:
--   on_surface_init  - 生成竞技场 + 围墙 + 障碍物
--   on_enter          - 初始化参数 + 配发武器 + GUI + 敌对阵营
--   on_tick           - 波次管理 + 虫子生成 + 效果过期 + 商店重显检测
--   on_gui_click      - 商店购买 / 下一波
--   check_victory     - 判定胜利/失败
--   on_entity_died    - 清理死虫 + 击杀计数 + 金币 + 吸血
--   on_player_died    - 标记玩家死亡
--   on_exit           - 清理实体 + GUI + 渲染

local Instance = require 'maps.amap.instance.instance'

local M = {}

--==============================================================================
-- 元数据
--==============================================================================

M.type = 'potato_survival'
M.display_name_key = 'amap.instance_potato_survival_name'
M.description_key = 'amap.instance_potato_survival_desc'
M.gameplay_desc_key = 'amap.instance_potato_survival_gameplay'
M.victory_condition_key = 'amap.instance_potato_survival_victory'
M.icon = 'item/raw-fish'
M.time_limit_default = 30 * 60 * 60  -- 30 分钟硬上限

--==============================================================================
-- 难度设置
--   arena_half: 半边长（场地 = (ah*2+1)^2）
--   wave_count: 总波次
--   biters_per_wave: 首波基础敌人数量
--   wave_scaling: 每波额外增加数量
--   wave_duration: 每波持续时间（仅显示用, 不影响结算; 杀光即进商店）
--==============================================================================

M.difficulty_settings = {
    easy = {
        name = 'easy',
        recycling_efficiency = 1,
        max_coins = 0,
        display_name_key = 'dungeon_difficulty_easy',
        arena_half = 22,
        wave_count = 6,
        biters_per_wave = 4,
        wave_scaling = 1,
        biter_types = {'small-biter'},
        elite_biter_types = {'small-biter'},
        boss_biter_type = 'medium-biter',
        obstacle_count = 20,
        start_ammo = 40,
        coin_mult = 1.0,
    },
    normal = {
        name = 'normal',
        recycling_efficiency = 1,
        max_coins = 0,
        display_name_key = 'dungeon_difficulty_normal',
        arena_half = 18,
        wave_count = 10,
        biters_per_wave = 6,
        wave_scaling = 2,
        biter_types = {'small-biter', 'small-spitter'},
        elite_biter_types = {'medium-biter', 'medium-spitter'},
        boss_biter_type = 'big-biter',
        obstacle_count = 14,
        start_ammo = 30,
        coin_mult = 1.0,
    },
    hard = {
        name = 'hard',
        recycling_efficiency = 1,
        max_coins = 0,
        display_name_key = 'dungeon_difficulty_hard',
        arena_half = 14,
        wave_count = 15,
        biters_per_wave = 6,
        wave_scaling = 2,
        biter_types = {'small-biter', 'small-spitter'},
        elite_biter_types = {'medium-biter', 'medium-spitter', 'big-biter'},
        boss_biter_type = 'behemoth-biter',
        obstacle_count = 10,
        start_ammo = 25,
        coin_mult = 1.0,
    }
}

--==============================================================================
-- 常量
--==============================================================================

-- 武器定义
local WEAPON_DEFS = {
    ['submachine-gun'] = {
        ammo_item = 'firearm-magazine',
        ammo_category = 'bullet',
        icon = 'item/submachine-gun',
        name_key = 'amap.potato_weapon_smg',
        desc_key = 'amap.potato_weapon_smg_desc',
    },
    ['shotgun'] = {
        ammo_item = 'shotgun-shell',
        ammo_category = 'shotgun-shell',
        icon = 'item/shotgun',
        name_key = 'amap.potato_weapon_shotgun',
        desc_key = 'amap.potato_weapon_shotgun_desc',
    },
    ['rocket-launcher'] = {
        ammo_item = 'rocket',
        ammo_category = 'rocket',
        icon = 'item/rocket-launcher',
        name_key = 'amap.potato_weapon_rocket',
        desc_key = 'amap.potato_weapon_rocket_desc',
    },
    ['flamethrower'] = {
        ammo_item = 'flamethrower-ammo',
        ammo_category = 'flamethrower',
        icon = 'item/flamethrower',
        name_key = 'amap.potato_weapon_flame',
        desc_key = 'amap.potato_weapon_flame_desc',
    },
}

-- 升级池
-- cost_scale: 每级价格增幅 (cost = base * (1 + level * cost_scale))
-- max_level: 最大可购买等级 (nil = 无限)
-- apply: function(player, level, md) -- level 是购买后的等级
local UPGRADE_POOL = {
    {
        id = 'power',
        name_key = 'amap.potato_up_power',
        desc_key = 'amap.potato_up_power_desc',
        icon = 'item/uranium-rounds-magazine',
        base_cost = 5,
        cost_scale = 0.3,
        max_level = 10,
    },
    {
        id = 'speed',
        name_key = 'amap.potato_up_speed',
        desc_key = 'amap.potato_up_speed_desc',
        icon = 'item/exoskeleton-equipment',
        base_cost = 5,
        cost_scale = 0.3,
        max_level = 8,
    },
    {
        id = 'vitality',
        name_key = 'amap.potato_up_vitality',
        desc_key = 'amap.potato_up_vitality_desc',
        icon = 'item/raw-fish',
        base_cost = 5,
        cost_scale = 0.3,
        max_level = 10,
    },
    {
        id = 'attack_speed',
        name_key = 'amap.potato_up_atk_spd',
        desc_key = 'amap.potato_up_atk_spd_desc',
        icon = 'item/fast-transport-belt',
        base_cost = 5,
        cost_scale = 0.3,
        max_level = 10,
    },
    {
        id = 'armor',
        name_key = 'amap.potato_up_armor',
        desc_key = 'amap.potato_up_armor_desc',
        icon = 'item/heavy-armor',
        base_cost = 6,
        cost_scale = 0.3,
        max_level = 8,
    },
    {
        id = 'lifesteal',
        name_key = 'amap.potato_up_lifesteal',
        desc_key = 'amap.potato_up_lifesteal_desc',
        icon = 'item/destroyer-capsule',  -- 原 item.blood-bag 非 2.0 合法物品；life-steal 主题用 destroyer-capsule（红色攻击性，合法）
        base_cost = 8,
        cost_scale = 0.4,
        max_level = 5,
    },
    {
        id = 'regen',
        name_key = 'amap.potato_up_regen',
        desc_key = 'amap.potato_up_regen_desc',
        icon = 'item/repair-pack',
        base_cost = 6,
        cost_scale = 0.3,
        max_level = 5,
    },
    {
        id = 'ammo_refill',
        name_key = 'amap.potato_up_ammo',
        desc_key = 'amap.potato_up_ammo_desc',
        icon = 'item/firearm-magazine',
        base_cost = 3,
        cost_scale = 0,
        max_level = 1,  -- 每局商店最多出现 1 次
    },
    {
        id = 'weapon_smg',
        name_key = 'amap.potato_weapon_smg',
        desc_key = 'amap.potato_weapon_smg_desc',
        icon = 'item/submachine-gun',
        base_cost = 0,     -- 拿冲锋枪"免费"（默认武器）
        cost_scale = 0,
        max_level = 1,
        weapon_name = 'submachine-gun',
    },
    {
        id = 'weapon_shotgun',
        name_key = 'amap.potato_weapon_shotgun',
        desc_key = 'amap.potato_weapon_shotgun_desc',
        icon = 'item/shotgun',
        base_cost = 10,
        cost_scale = 0,
        max_level = 1,
        weapon_name = 'shotgun',
    },
    {
        id = 'weapon_rocket',
        name_key = 'amap.potato_weapon_rocket',
        desc_key = 'amap.potato_weapon_rocket_desc',
        icon = 'item/rocket-launcher',
        base_cost = 15,
        cost_scale = 0,
        max_level = 1,
        weapon_name = 'rocket-launcher',
    },
    {
        id = 'weapon_flame',
        name_key = 'amap.potato_weapon_flame',
        desc_key = 'amap.potato_weapon_flame_desc',
        icon = 'item/flamethrower',
        base_cost = 40,
        cost_scale = 0,
        max_level = 1,
        weapon_name = 'flamethrower',
    },
}

-- 障碍物候选
local OBSTACLE_TYPES = {
    'big-rock', 'big-rock', 'huge-rock', 'huge-rock',
    'big-sand-rock', 'big-sand-rock', 'tree-05', 'tree-05'
}

-- 顶栏 GUI 元素名
local GUI_WAVE = 'dungeon_ps_wave'
local GUI_ALIVE = 'dungeon_ps_alive'
local GUI_KILLS = 'dungeon_ps_kills'
local GUI_COINS = 'dungeon_ps_coins'
local GUI_AMMO = 'dungeon_ps_ammo'

-- 商店 GUI 元素名
local SHOP_FRAME = 'dungeon_module_ps_shop'

-- 商店冷却 (wave_state = 'cooldown' 持续的 tick)
local SHOP_COOLDOWN_TICKS = 2 * 60  -- 2 秒

--==============================================================================
-- 辅助函数
--==============================================================================

-- 从 4 个方向中随机抽取 N 个不同方向
local function pick_random_sides(n)
    n = math.max(1, math.min(4, n))
    local sides = {1, 2, 3, 4}
    for i = #sides, 2, -1 do
        local j = math.random(i)
        sides[i], sides[j] = sides[j], sides[i]
    end
    local picked = {}
    for i = 1, n do
        picked[#picked + 1] = sides[i]
    end
    return picked
end

-- 计算方向数量
local function calc_side_count(wave)
    if wave <= 1 then return 1
    elseif wave <= 2 then return math.random(1, 2)
    elseif wave <= 3 then return 2
    elseif wave <= 4 then return math.random(2, 3)
    elseif wave <= 6 then return 3
    else return 4 end
end

-- 计算边缘出生点
local function get_edge_spawn(arena_half, side)
    local max_r = arena_half - 1
    if side == 1 then return {x = math.random(-max_r, max_r), y = -max_r}
    elseif side == 2 then return {x = math.random(-max_r, max_r), y = max_r}
    elseif side == 3 then return {x = -max_r, y = math.random(-max_r, max_r)}
    else return {x = max_r, y = math.random(-max_r, max_r)} end
end

-- 创建虫子并加入追踪
local function create_biter(surface, biter_type, pos, target, force_name, active_biters, biter_revives, revives)
    local pos_final = surface.find_non_colliding_position(biter_type, pos, 8, 1) or pos
    local biter = surface.create_entity({
        name = biter_type,
        position = pos_final,
        force = force_name
    })
    if not biter then return nil end

    local group = surface.create_unit_group({
        position = pos_final,
        force = force_name
    })
    if group then
        group.add_member(biter)
        group.set_command({
            type = defines.command.attack,
            target = target,
            distraction = defines.distraction.by_anything
        })
    end
    active_biters[#active_biters + 1] = biter

    -- 记录复活次数
    if revives and revives > 0 and biter_revives then
        biter_revives[biter.unit_number] = {
            revives = revives,
            biter_type = biter_type,
            force_name = force_name
        }
    end
    return biter
end

-- 获取波次类型和参数
local function get_wave_params(md)
    local wave = md.current_wave
    -- 每 5 波 boss 波, 每 3 波 swarm 波
    if wave % 5 == 0 then
        return 'boss'
    elseif wave % 3 == 0 then
        return 'swarm'
    else
        return 'normal'
    end
end

-- 生成一波敌人
local function spawn_wave(surface, player, md)
    local target = player.character
    if not target or not target.valid then return end

    local base_count = md.biters_per_wave
    local scaling = md.wave_scaling
    local wave_bonus = scaling * (md.current_wave - 1)
    local wave_type = get_wave_params(md)
    md.last_wave_type = wave_type

    local biter_pool, count, revives
    if wave_type == 'swarm' then
        biter_pool = md.biter_types
        count = base_count * 2 + wave_bonus
        revives = 0
    elseif wave_type == 'boss' then
        biter_pool = {md.boss_biter_type}
        count = 1 + math.floor(wave_bonus / 3)
        revives = 3
    else
        biter_pool = md.biter_types
        count = base_count + wave_bonus
        revives = 0
    end

    local ah = md.arena_half
    local side_count = calc_side_count(md.current_wave)
    local sides = pick_random_sides(side_count)
    local per_side = math.max(1, math.floor(count / #sides))
    local rest = count - per_side * #sides

    for idx, side in ipairs(sides) do
        local n = per_side + (idx <= rest and 1 or 0)
        for _ = 1, n do
            local biter_type = biter_pool[math.random(#biter_pool)]
            local spawn_base = get_edge_spawn(ah, side)
            create_biter(surface, biter_type, spawn_base, target,
                md.dungeon_enemy_force, md.active_biters,
                md.biter_revives, revives)
        end
    end

    -- 下一波预告
    if md.current_wave < md.wave_count then
        md.next_wave_type = get_wave_params({current_wave = md.current_wave + 1})
    else
        md.next_wave_type = nil
    end

    -- 播报
    local wave_type_key = 'amap.potato_wt_' .. wave_type
    player.create_local_flying_text({
        text = {'amap.potato_wave_start', md.current_wave, md.wave_count, {wave_type_key}},
        position = player.position,
        color = {1, 0.4, 0}
    })
end

-- 放置障碍物
local function place_obstacles(surface, arena_half, count)
    local obstacles = {}
    local exclude_min, exclude_max = -2, 2
    local placed = 0
    local max_attempts = count * 15

    for _ = 1, max_attempts do
        if placed >= count then break end
        local x = math.random(-arena_half + 2, arena_half - 2)
        local y = math.random(-arena_half + 2, arena_half - 2)
        if x >= exclude_min and x <= exclude_max and y >= exclude_min and y <= exclude_max then
            goto continue_obs
        end
        local too_close = false
        for _, existing in ipairs(obstacles) do
            if (x - existing.x) ^ 2 + (y - existing.y) ^ 2 < 9 then
                too_close = true
                break
            end
        end
        if too_close then goto continue_obs end

        local ent = surface.create_entity({
            name = OBSTACLE_TYPES[math.random(#OBSTACLE_TYPES)],
            position = {x, y},
            force = 'neutral'
        })
        if ent then
            ent.destructible = false
            placed = placed + 1
            obstacles[#obstacles + 1] = {x = x, y = y}
        end
        ::continue_obs::
    end
    return obstacles
end

--==============================================================================
-- 属性系统
--==============================================================================

-- 应用全部已升级的属性
local function apply_all_stats(player, md)
    local force = player.force
    local def = md.current_weapon_def
    local cat = def.ammo_category
    local stats = md.stats

    -- 伤害
    force.set_ammo_damage_modifier(cat, (stats.power or 0) * 0.2)
    -- 攻速
    force.set_gun_speed_modifier(cat, (stats.attack_speed or 0) * 0.15)

    -- 移速
    local char = player.character
    if char and char.valid then
        char.character_running_speed_modifier = (stats.speed or 0) * 0.15
        -- 生命值
        char.character_health_bonus = (stats.vitality or 0) * 30
        -- 护甲 (物理抗性)
        local armor_pct = math.min(80, (stats.armor or 0) * 10)
        pcall(function()
            char.set_resistance(defines.resistance_type.physical, {decrease = 0, percent = armor_pct})
        end)
    end
end

-- 切换武器
local function switch_weapon(player, md, weapon_name)
    local force = player.force
    local old_cat = md.current_weapon_def.ammo_category

    -- 清除旧武器 modifiers
    force.set_ammo_damage_modifier(old_cat, 0)
    force.set_gun_speed_modifier(old_cat, 0)

    -- 移除旧武器和弹药
    local gun_inv = player.get_inventory(defines.inventory.character_guns)
    if gun_inv then gun_inv.clear() end
    local ammo_inv = player.get_inventory(defines.inventory.character_ammo)
    if ammo_inv then ammo_inv.clear() end

    -- 装入新武器
    if gun_inv then gun_inv.insert({name = weapon_name, count = 1}) end

    -- 更新武器数据
    md.current_weapon = weapon_name
    md.current_weapon_def = WEAPON_DEFS[weapon_name]

    -- 给弹药
    if ammo_inv then
        ammo_inv.insert({name = md.current_weapon_def.ammo_item, count = 10})
    end
    local main_inv = player.get_main_inventory()
    if main_inv then
        main_inv.insert({name = md.current_weapon_def.ammo_item, count = 20})
    end

    -- 重新应用属性
    apply_all_stats(player, md)
end

-- 应用单个升级
local function apply_upgrade(player, md, upgrade_def)
    local stats = md.stats
    local id = upgrade_def.id

    if id == 'power' then
        stats.power = (stats.power or 0) + 1
        local cat = md.current_weapon_def.ammo_category
        player.force.set_ammo_damage_modifier(cat, stats.power * 0.2)
    elseif id == 'speed' then
        stats.speed = (stats.speed or 0) + 1
        local char = player.character
        if char and char.valid then
            char.character_running_speed_modifier = stats.speed * 0.15
        end
    elseif id == 'vitality' then
        stats.vitality = (stats.vitality or 0) + 1
        local char = player.character
        if char and char.valid then
            char.character_health_bonus = stats.vitality * 30
            -- 升级时同步拉满当前血量
            local max_hp = char.max_health or 100
            if char.health < max_hp then
                char.health = max_hp
            end
        end
    elseif id == 'attack_speed' then
        stats.attack_speed = (stats.attack_speed or 0) + 1
        local cat = md.current_weapon_def.ammo_category
        player.force.set_gun_speed_modifier(cat, stats.attack_speed * 0.15)
    elseif id == 'armor' then
        stats.armor = (stats.armor or 0) + 1
        local char = player.character
        if char and char.valid then
            local armor_pct = math.min(80, stats.armor * 10)
            pcall(function()
                char.set_resistance(defines.resistance_type.physical, {decrease = 0, percent = armor_pct})
            end)
        end
    elseif id == 'lifesteal' then
        stats.lifesteal = (stats.lifesteal or 0) + 1
    elseif id == 'regen' then
        stats.regen = (stats.regen or 0) + 1
    elseif id == 'ammo_refill' then
        local main_inv = player.get_main_inventory()
        if main_inv then
            main_inv.insert({name = md.current_weapon_def.ammo_item, count = 30})
        end
        stats.ammo_refill_used = true
    elseif string.sub(id, 1, 7) == 'weapon_' then
        switch_weapon(player, md, upgrade_def.weapon_name)
    end
end

-- 计算升级价格
local function calc_upgrade_cost(upgrade_def, current_level)
    local base = upgrade_def.base_cost
    local scale = upgrade_def.cost_scale or 0
    return math.floor(base * (1 + current_level * scale))
end

-- 检查升级是否可购买
local function can_buy_upgrade(upgrade_def, md)
    local id = upgrade_def.id
    local stats = md.stats
    local cur = stats[id] or 0
    local max_lv = upgrade_def.max_level
    if max_lv and cur >= max_lv then return false end
    if id == 'ammo_refill' and stats.ammo_refill_used then return false end
    if string.sub(id, 1, 7) == 'weapon_' then
        return md.current_weapon ~= upgrade_def.weapon_name
    end
    return true
end

--==============================================================================
-- 顶栏 HUD
--==============================================================================

local function update_top_gui(player, md)
    local top = player.gui.top
    local function ensure(name)
        local lbl = top[name]
        if not lbl then
            lbl = top.add({type = 'label', name = name, caption = ''})
        end
        return lbl
    end

    ensure(GUI_WAVE).caption = {'amap.potato_hud_wave', md.current_wave, md.wave_count}
    ensure(GUI_ALIVE).caption = {'amap.potato_hud_alive', #md.active_biters}
    ensure(GUI_KILLS).caption = {'amap.potato_hud_kills', md.kills or 0}

    local ammo_count = 0
    local ammo_inv = player.get_main_inventory()
    if ammo_inv and md.current_weapon_def then
        ammo_count = ammo_inv.get_item_count(md.current_weapon_def.ammo_item)
    end
    ensure(GUI_AMMO).caption = {'amap.potato_hud_ammo', ammo_count}
    ensure(GUI_COINS).caption = {'amap.potato_hud_coins', md.coins or 0}
end

local function cleanup_top_gui(player)
    local top = player.gui.top
    for _, name in ipairs({GUI_WAVE, GUI_ALIVE, GUI_KILLS, GUI_COINS, GUI_AMMO}) do
        if top[name] then top[name].destroy() end
    end
end

--==============================================================================
-- 商店 GUI
--==============================================================================

-- 构建商店卡片池 (随机 4 张)
local function build_shop_cards(md)
    -- 过滤可购买的升级
    local available = {}
    for _, upg in ipairs(UPGRADE_POOL) do
        if can_buy_upgrade(upg, md) then
            available[#available + 1] = upg
        end
    end

    -- Fisher-Yates 洗牌
    for i = #available, 2, -1 do
        local j = math.random(i)
        available[i], available[j] = available[j], available[i]
    end

    -- 取前 4 张 (不足 4 张就全取)
    local count = math.min(4, #available)
    local cards = {}
    for i = 1, count do
        local upg = available[i]
        local cur_level = md.stats[upg.id] or 0
        cards[i] = {
            upgrade = upg,
            cost = calc_upgrade_cost(upg, cur_level),
        }
    end
    return cards
end

-- 显示商店
local function show_shop(player, md)
    hide_shop(player)

    md.shop_cards = build_shop_cards(md)
    local screen = player.gui.screen
    local frame = screen.add({
        type = 'frame',
        name = SHOP_FRAME,
        direction = 'vertical',
        caption = {'amap.potato_shop_title', md.current_wave, md.wave_count}
    })
    frame.location = {x = 150, y = 80}

    -- 卡片横向排列
    local cards_flow = frame.add({
        type = 'flow',
        name = 'dungeon_module_ps_cards_flow',
        direction = 'horizontal'
    })

    for i, card in ipairs(md.shop_cards) do
        local upg = card.upgrade
        local card_frame = cards_flow.add({
            type = 'frame',
            name = 'dungeon_module_ps_card_' .. i,
            direction = 'vertical'
        })
        card_frame.style.minimal_width = 160
        card_frame.style.minimal_height = 180
        card_frame.style.padding = 6

        -- 图标
        local sprite_btn = card_frame.add({
            type = 'sprite-button',
            name = 'dungeon_module_ps_sprite_' .. i,
            sprite = upg.icon,
            style = 'transparent_slot'
        })
        sprite_btn.style.width = 48
        sprite_btn.style.height = 48

        -- 名称
        card_frame.add({
            type = 'label',
            name = 'dungeon_module_ps_name_' .. i,
            caption = {upg.name_key},
            tooltip = {upg.desc_key}
        }).style.font_color = {0.85, 0.85, 0.3}
        card_frame.add({
            type = 'label',
            name = 'dungeon_module_ps_desc_' .. i,
            caption = {upg.desc_key}
        }).style.single_line = false

        -- 价格
        local cur_lv = md.stats[upg.id] or 0
        local lv_text = (upg.max_level and cur_lv > 0) and (' Lv.' .. cur_lv) or ''
        card_frame.add({
            type = 'label',
            name = 'dungeon_module_ps_price_' .. i,
            caption = {'amap.potato_shop_price', card.cost, lv_text}
        }).style.font_color = {1, 0.85, 0.3}

        -- 购买按钮
        local buy_btn = card_frame.add({
            type = 'button',
            name = 'dungeon_module_ps_buy_' .. i,
            caption = {'amap.potato_shop_buy'},
            enabled = md.coins >= card.cost
        })
        buy_btn.style.font = 'default-bold'
        buy_btn.style.font_color = {0.22, 0.28, 0.78}
        if md.coins < card.cost then
            buy_btn.style.font_color = {0.5, 0.5, 0.5}
        end
    end

    -- 金币显示
    frame.add({
        type = 'label',
        name = 'dungeon_module_ps_coins_label',
        caption = {'amap.potato_shop_coins', md.coins}
    }).style.font = 'default-bold'

    -- 进入下一波按钮
    local next_btn = frame.add({
        type = 'button',
        name = 'dungeon_module_ps_next',
        caption = {'amap.potato_shop_next'}
    })
    next_btn.style.font = 'default-bold'
    next_btn.style.font_color = {0.78, 0.08, 0.08}
    next_btn.style.minimal_width = 200
end

-- 隐藏商店
local function hide_shop(player)
    local screen = player.gui.screen
    if screen[SHOP_FRAME] then
        screen[SHOP_FRAME].destroy()
    end
end

-- 商店购买处理
local function on_shop_buy(player, md, card_index)
    local card = md.shop_cards[card_index]
    if not card then return end
    if md.coins < card.cost then
        player.play_sound({path = 'utility/cannot_build', volume_modifier = 0.5})
        return
    end

    md.coins = md.coins - card.cost
    apply_upgrade(player, md, card.upgrade)

    player.play_sound({path = 'utility/achievement_unlocked', volume_modifier = 0.6})
    player.create_local_flying_text({
        text = {card.upgrade.name_key},
        position = player.position,
        color = {0.2, 1, 0.2}
    })

    -- 刷新商店 (价格更新、已购买的移除)
    show_shop(player, md)
end

-- 进入下一波
local function on_next_wave(player, md)
    hide_shop(player)
    md.shop_cards = {}

    if md.current_wave >= md.wave_count then
        -- 最后一波结束，标记胜利
        md.victory_ready = true
        return
    end

    md.wave_state = 'cooldown'
    md.cooldown_end_tick = game.tick + SHOP_COOLDOWN_TICKS
end

--==============================================================================
-- 框架钩子
--==============================================================================

-- on_surface_init: 生成竞技场地形
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

    -- 外围不可破坏石墙
    for x = -ah, ah do
        for _, y_offs in ipairs({-ah - 1, ah + 1}) do
            local wall = surface.create_entity({
                name = 'stone-wall', position = {x, y_offs},
                force = player.force, move_stuck_players = true
            })
            if wall then wall.destructible = false end
        end
    end
    for y = -ah - 1, ah + 1 do
        for _, x_offs in ipairs({-ah - 1, ah + 1}) do
            local wall = surface.create_entity({
                name = 'stone-wall', position = {x_offs, y},
                force = player.force, move_stuck_players = true
            })
            if wall then wall.destructible = false end
        end
    end

    -- 中央出生区
    for x = -2, 2 do
        for y = -2, 2 do
            surface.set_tiles({{name = 'hazard-concrete-left', position = {x, y}}})
        end
    end

    -- 障碍物
    place_obstacles(surface, ah, diff.obstacle_count)

    surface.always_day = true

    -- 设置时间限制: 给足时间
    local est_time = diff.wave_count * 60 * 60  -- 估算每波+商店共 60s
    data.time_limit = est_time + 120 * 60       -- +2 分钟缓冲
end

-- on_enter: 初始化
function M.on_enter(player, data, difficulty_key)
    local diff = M.difficulty_settings[difficulty_key]
    if not diff then diff = M.difficulty_settings.easy end

    -- 建立独立敌对阵营
    local dungeon_enemy = game.forces['dungeon_enemy']
    if not dungeon_enemy then
        dungeon_enemy = game.create_force('dungeon_enemy')
        dungeon_enemy.set_friend('player', false)
    end
    local dungeon_force = game.forces[data.dungeon_force]
    if dungeon_force then
        dungeon_force.set_cease_fire('dungeon_enemy', false)
        dungeon_force.set_friend('dungeon_enemy', false)
        dungeon_enemy.set_friend(data.dungeon_force, false)
    end

    -- 修正时钟错位
    data.time_limit = data.time_limit + 60 * 60

    -- 模块数据
    local default_weapon = 'submachine-gun'
    local md = {
        -- 场地
        arena_half = diff.arena_half,
        -- 波次
        wave_count = diff.wave_count,
        current_wave = 1,
        wave_state = 'cooldown',  -- 'fighting' | 'shop' | 'cooldown'
        cooldown_end_tick = game.tick + SHOP_COOLDOWN_TICKS,
        biters_per_wave = diff.biters_per_wave,
        wave_scaling = diff.wave_scaling,
        biter_types = diff.biter_types,
        elite_biter_types = diff.elite_biter_types,
        boss_biter_type = diff.boss_biter_type,
        last_wave_type = nil,
        next_wave_type = nil,
        -- 敌人
        active_biters = {},
        biter_revives = {},
        player_died = false,
        kills = 0,
        dungeon_enemy_force = 'dungeon_enemy',
        -- 金币
        coins = 0,
        coin_mult = diff.coin_mult,
        -- 武器
        current_weapon = default_weapon,
        current_weapon_def = WEAPON_DEFS[default_weapon],
        start_ammo = diff.start_ammo,
        -- 属性
        stats = {},
        -- 商店
        shop_cards = {},
        -- 胜利标记
        victory_ready = false,
        -- 障碍物数量
        obstacle_count = diff.obstacle_count,
    }
    data.module_data = md

    -- 预告第一波类型
    md.next_wave_type = get_wave_params(md)

    -- 配发默认武器
    local gun_inv = player.get_inventory(defines.inventory.character_guns)
    if gun_inv and gun_inv.get_item_count(default_weapon) == 0 then
        gun_inv.insert({name = default_weapon, count = 1})
    end
    local ammo_inv = player.get_inventory(defines.inventory.character_ammo)
    if ammo_inv and ammo_inv.get_item_count('firearm-magazine') == 0 then
        ammo_inv.insert({name = 'firearm-magazine', count = 10})
    end
    local main_inv = player.get_main_inventory()
    if main_inv then
        main_inv.insert({name = 'firearm-magazine', count = diff.start_ammo})
    end

    update_top_gui(player, md)
    player.print({'amap.potato_enter'}, {r = 0, g = 1, b = 0})
    player.print({'amap.potato_hint'}, {r = 1, g = 0.8, b = 0})
end

-- on_tick: 波次管理 + 敌人清理 + 效果 + 商店重显
function M.on_tick(player, data)
    local md = data.module_data
    if not md or not md.active_biters then return end

    local surface = player.surface
    if not surface then return end
    local tick = game.tick

    -- 清理死虫
    for i = #md.active_biters, 1, -1 do
        if not md.active_biters[i] or not md.active_biters[i].valid then
            table.remove(md.active_biters, i)
        end
    end

    -- 冷却 → 开始战斗
    if md.wave_state == 'cooldown' and tick >= md.cooldown_end_tick then
        md.wave_state = 'fighting'
        spawn_wave(surface, player, md)
    end

    -- 战斗结束检测: 所有敌人被杀 → 进入商店
    if md.wave_state == 'fighting' and #md.active_biters == 0 then
        if md.current_wave >= md.wave_count then
            -- 最后一波，最后一次商店
            md.wave_state = 'shop'
            md.current_wave = md.current_wave + 1  -- 标记完成
            show_shop(player, md)
        else
            -- 速度奖励: 快速清场给额外金币
            local speed_bonus = math.floor(md.current_wave * 2 * (md.coin_mult or 1))
            md.coins = md.coins + speed_bonus
            if speed_bonus > 0 then
                player.create_local_flying_text({
                    text = {'amap.potato_speed_bonus', speed_bonus},
                    position = player.position,
                    color = {1, 0.85, 0}
                })
            end
            md.current_wave = md.current_wave + 1
            md.wave_state = 'shop'
            show_shop(player, md)
        end
    end

    -- 如果处于商店状态但 GUI 被关闭了，重新显示
    if md.wave_state == 'shop' and not player.gui.screen[SHOP_FRAME] then
        show_shop(player, md)
    end

    -- 生命恢复 (每 tick 2 HP per regen level, on_tick 每 60 tick 一次)
    if md.stats.regen and md.stats.regen > 0 then
        local char = player.character
        if char and char.valid then
            local max_hp = char.max_health or 100
            local heal = md.stats.regen * 2
            char.health = math.min(char.health + heal, max_hp)
        end
    end

    update_top_gui(player, md)
end

-- check_victory: 胜利/失败判定
function M.check_victory(player, data)
    local md = data.module_data
    if not md then return nil end

    if md.player_died then return 'defeat' end

    if md.victory_ready then
        Instance.set_reward_multiplier(player, 1.0)
        return 'victory'
    end

    return nil
end

-- on_entity_died: 清理死虫 + 击杀 + 金币 + 吸血 + 复活
function M.on_entity_died(player, event)
    local entity = event.entity
    if not entity or not entity.valid then return end
    if entity.type ~= 'unit' then return end
    if not entity.force or entity.force.name ~= 'dungeon_enemy' then return end

    local data = Instance.get_data(player.index)
    if not data then return end
    local md = data.module_data
    if not md then return end

    -- 复活处理
    local revives_entry = md.biter_revives and md.biter_revives[entity.unit_number]
    if revives_entry and revives_entry.revives > 0 then
        local surface = entity.surface
        local pos = entity.position
        local target = player.character

        local revived = surface.create_entity({
            name = revives_entry.biter_type,
            position = pos,
            force = revives_entry.force_name
        })
        if revived and revived.valid then
            if target and target.valid then
                local group = surface.create_unit_group({
                    position = pos,
                    force = revives_entry.force_name
                })
                if group then
                    group.add_member(revived)
                    group.set_command({
                        type = defines.command.attack,
                        target = target,
                        distraction = defines.distraction.by_anything
                    })
                end
            end

            for i, b in ipairs(md.active_biters) do
                if b == entity then
                    md.active_biters[i] = revived
                    break
                end
            end

            md.biter_revives[entity.unit_number] = nil
            if revives_entry.revives - 1 > 0 then
                md.biter_revives[revived.unit_number] = {
                    revives = revives_entry.revives - 1,
                    biter_type = revives_entry.biter_type,
                    force_name = revives_entry.force_name
                }
            end

            player.create_local_flying_text({
                text = {'amap.arena_survival_revive'},
                position = pos,
                color = {1, 0.5, 0.5}
            })
            return
        end
        md.biter_revives[entity.unit_number] = nil
    end

    -- 正常击杀: 移除追踪
    for i, biter in ipairs(md.active_biters) do
        if biter == entity then
            table.remove(md.active_biters, i)
            break
        end
    end

    md.kills = (md.kills or 0) + 1

    -- 金币奖励 (按虫子类型)
    local ename = entity.name
    local coin_val = 1
    if string.find(ename, 'medium') then coin_val = 2
    elseif string.find(ename, 'big') then coin_val = 3
    elseif string.find(ename, 'behemoth') then coin_val = 5
    end
    md.coins = md.coins + coin_val

    -- 吸血
    if md.stats.lifesteal and md.stats.lifesteal > 0 then
        local char = player.character
        if char and char.valid then
            local max_hp = char.max_health or 100
            local heal = max_hp * (md.stats.lifesteal * 0.05)
            char.health = math.min(char.health + heal, max_hp)
        end
    end

    player.create_local_flying_text({
        text = {'amap.potato_kill', md.kills, coin_val},
        position = entity.position,
        color = {0.2, 1, 0.2}
    })
end

-- on_player_died
function M.on_player_died(player, data)
    local md = data.module_data
    if not md then return end
    md.player_died = true
end

-- on_gui_click: 商店购买 / 下一波
function M.on_gui_click(player, event)
    if not event.element or not event.element.valid then return end

    local data = Instance.get_data(player.index)
    if not data then return end
    local md = data.module_data
    if not md then return end

    local ename = event.element.name

    -- 购买卡片按钮: dungeon_module_ps_buy_N
    local buy_idx = string.match(ename, '^dungeon_module_ps_buy_(%d+)$')
    if buy_idx then
        on_shop_buy(player, md, tonumber(buy_idx))
        return
    end

    -- 下一波按钮
    if ename == 'dungeon_module_ps_next' then
        on_next_wave(player, md)
        return
    end
end

-- on_gui_closed: 商店被意外关闭时重开 (由框架 on_tick 处理)
function M.on_gui_closed(player, event)
    -- 不需要额外处理，on_tick 会检测并重开
end

-- on_exit: 清理
function M.on_exit(player, data, reason)
    local md = data.module_data
    if not md then return end

    -- 清理虫子
    local biters = md.active_biters
    md.active_biters = {}
    for _, b in ipairs(biters) do
        if b and b.valid then b.destroy() end
    end
    md.biter_revives = {}

    -- 隐藏商店
    hide_shop(player)

    -- 清理顶栏
    cleanup_top_gui(player)
end

--==============================================================================
-- 注册
--==============================================================================

Instance.register(M.type, M)
return M
