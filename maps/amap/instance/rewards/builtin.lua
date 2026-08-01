-- maps/amap/instance/rewards/builtin.lua
-- 内置奖励定义（4 类奖励，按用户简化方案实现）
--
-- 奖励清单：
--   1. recipe_productivity (common/低档) - 随机 1 个已解锁非太空配方 +3% 产能（固定）
--   2. force_modifier     (rare/中档)   - 随机 1 项 force modifier 加成（百分比 +0.03 / 绝对值 +1，固定）
--   3. damage_bonus       (epic/高档)   - 随机 1 种弹药类型 +3% 伤害（固定）
--   4a. shop_pack_low     (common/低档) - 10K × multiplier 金币的随机商店物品，品质按宠物 low 权重
--   4b. shop_pack_mid     (rare/中档)   - 10K × multiplier 金币的随机商店物品，品质按宠物 mid 权重
--
-- 设计说明：
--   - 卡片 GUI 显示时通过 roll_preview 滚出具体参数（哪个配方/哪个 modifier/哪个弹药）
--     玩家在进入副本前就明确知道通关给什么（如"激光伤害加成 +3%"）
--   - grant_scaled 接收预抽的 params，用预抽参数发放，不再二次随机
--   - 配方产能/阵营加成/伤害加成：固定数值，multiplier 仅作为是否发放的门槛（>0 即发）
--   - 商店随机包：物品是发放时才随机（因为玩家表现决定总价值），预抽只显示档位描述

local Rewards = require 'maps.amap.instance.rewards'
local Pet = require 'modules.pet_system.table'
local WPT = require 'maps.amap.table'

-- 保卫战特殊奖励依赖
local RPG = require 'modules.rpg.table'
local Tianfu = require 'maps.amap.tianfu'

-- 品质名（Factorio 2.0+ 标准名，下标 1..5 对应宠物系统 roll_quality 返回值）
local QUALITY_NAMES = {'normal', 'uncommon', 'rare', 'epic', 'legendary'}

--==============================================================================
-- 阵营加成表（官方 17 项列表，按字段类型分类）
-- 字段命名对应 LuaForce 属性名
-- type: 'percentage' 表示 +0.03（百分比类），'absolute' 表示 +1（绝对值类）
--==============================================================================

local FORCE_MODIFIERS = {
    -- 百分比类：+0.03
    {key = 'worker_robots_speed_modifier',         type = 'percentage', name_key = 'amap.reward_force_mod_worker_robot_speed'},
    {key = 'worker_robots_battery_modifier',       type = 'percentage', name_key = 'amap.reward_force_mod_worker_robot_battery'},
    {key = 'worker_robots_storage_bonus',          type = 'percentage', name_key = 'amap.reward_force_mod_worker_robot_storage'},
    {key = 'laboratory_speed_modifier',            type = 'percentage', name_key = 'amap.reward_force_mod_lab_speed'},
    {key = 'laboratory_productivity_bonus',        type = 'percentage', name_key = 'amap.reward_force_mod_lab_productivity'},
    {key = 'following_robots_lifetime_modifier',   type = 'percentage', name_key = 'amap.reward_force_mod_follower_robot_lifetime'},
    {key = 'artillery_range_modifier',             type = 'percentage', name_key = 'amap.reward_force_mod_artillery_range'},
    {key = 'mining_drill_productivity_bonus',      type = 'percentage', name_key = 'amap.reward_force_mod_mining_drill'},
    {key = 'belt_stack_size_bonus',                type = 'percentage', name_key = 'amap.reward_force_mod_belt_stack_size'},
    {key = 'inserter_stack_size_bonus',            type = 'percentage', name_key = 'amap.reward_force_mod_inserter_stack_size'},
    -- 绝对值类：+1
    {key = 'bulk_inserter_capacity_bonus',         type = 'absolute', name_key = 'amap.reward_force_mod_bulk_inserter_capacity'},
    {key = 'maximum_following_robot_count',        type = 'absolute', name_key = 'amap.reward_force_mod_max_following_robots'},
}

--==============================================================================
-- 弹药类别表（官方列表，已移除 seismic）+ 对应伤害科技映射
-- 未映射科技的弹药类别（biological/melee/capsule）默认视为"已解锁"
--==============================================================================

local AMMO_CATEGORIES = {
    'artillery-shell', 'beam', 'bullet', 'cannon-shell', 'capsule',
    'electric', 'flamethrower', 'grenade', 'landmine', 'laser',
    'railgun', 'rocket', 'shotgun-shell', 'tesla',
    'biological', 'melee'
}

-- 弹药类别 → 解锁该伤害科技的第一级科技名（用于扫描玩家是否解锁）
-- key 用下划线替换连字符作为表 key
local AMMO_TECH_MAP = {
    artillery_shell = 'artillery-shell-damage-1',
    beam            = 'beam-weapons-damage-1',  -- Space Age
    bullet          = 'bullet-damage-1',
    cannon_shell    = 'cannon-shell-damage-1',
    -- capsule 无直接伤害科技
    electric        = 'electric-weapons-damage-1',
    flamethrower    = 'flamethrower-damage-1',
    grenade         = 'grenade-damage-1',
    landmine        = 'landmine-damage-1',
    laser           = 'laser-weapons-damage-1',
    railgun         = 'railgun-damage-1',  -- Space Age
    rocket          = 'rocket-damage-1',
    shotgun_shell   = 'shotgun-shell-damage-1',
    tesla           = 'tesla-weapons-damage-1',  -- Space Age
    -- biological / melee / seismic 无直接伤害科技，默认视为已解锁
}

local function get_ammo_tech(ammo_category)
    local tech = AMMO_TECH_MAP[ammo_category:gsub('-', '_')]
    return tech
end

-- 扫描玩家已解锁的弹药类别
-- 规则：有对应伤害科技的，检查科技是否研究；无对应科技的（biological/melee/seismic/capsule），视为已解锁
-- 兜底：如果一个都没解锁，返回 {'bullet'}
local function get_unlocked_ammo_categories(force)
    local unlocked = {}
    for _, ammo in ipairs(AMMO_CATEGORIES) do
        local tech = get_ammo_tech(ammo)
        if not tech then
            -- 无对应科技，视为已解锁
            unlocked[#unlocked + 1] = ammo
        elseif force.technologies[tech] and force.technologies[tech].researched then
            unlocked[#unlocked + 1] = ammo
        end
    end
    if #unlocked == 0 then
        return {'bullet'}
    end
    return unlocked
end

--==============================================================================
-- 炮塔类型表（官方 12 项，排除 4 种虫子炮塔后剩 8 种玩家可用炮塔）
--==============================================================================

-- 玩家可用炮塔 → 解锁该炮塔的科技名（gun-turret 无需科技，默认解锁）
local TURRET_TECH_MAP = {
    ['gun-turret']          = nil,  -- 基础炮塔，无需科技
    ['laser-turret']        = 'laser-turrets',
    ['flamethrower-turret'] = 'flamethrower',
    ['artillery-turret']    = 'artillery',
    ['artillery-wagon']     = 'artillery',
    ['rocket-turret']       = 'rocket-turret',         -- Space Age
    ['tesla-turret']        = 'tesla-turret',          -- Space Age
    ['railgun-turret']      = 'railgun-turret',        -- Space Age
}

-- 扫描玩家已解锁的炮塔类型
-- 规则：gun-turret 默认解锁；其他炮塔检查对应科技是否研究
-- 兜底：如果一个都没解锁，返回 {'gun-turret'}
local function get_unlocked_turrets(force)
    local unlocked = {}
    for turret, tech in pairs(TURRET_TECH_MAP) do
        if not tech then
            -- 无需科技，默认解锁
            unlocked[#unlocked + 1] = turret
        elseif force.technologies[tech] and force.technologies[tech].researched then
            unlocked[#unlocked + 1] = turret
        end
    end
    if #unlocked == 0 then
        return {'gun-turret'}
    end
    return unlocked
end

--==============================================================================
-- 奖励 1：配方产能加成（common/低档，固定 +3%）
--==============================================================================

-- 判断配方是否为太空配方（在太空平台/其他星球专属，不在普通行星制作）
-- Factorio 2.0 / Space Age 中，太空配方通过 prototype.surface_conditions 标识
-- 普通行星配方通常没有 surface_conditions，有则视为太空配方
local function is_space_recipe(recipe)
    local proto = recipe.prototype
    if proto and proto.surface_conditions and #proto.surface_conditions > 0 then
        return true
    end
    return false
end

-- 收集玩家已解锁的非太空配方
local function collect_unlocked_ground_recipes(force)
    local recipes = {}
    for _, recipe in pairs(force.recipes) do
        if recipe.enabled and not recipe.hidden and not is_space_recipe(recipe) then
            recipes[#recipes + 1] = recipe.name
        end
    end
    return recipes
end

local function recipe_roll_preview(player, difficulty)
    if not player or not player.valid then return nil end
    local force = player.force
    local recipes = collect_unlocked_ground_recipes(force)
    if #recipes == 0 then
        return {
            display_key = 'amap.reward_recipe_productivity_no_recipe',
            display_args = {},
            params = {recipe_name = nil}
        }
    end
    local picked_name = recipes[math.random(1, #recipes)]
    local recipe = force.recipes[picked_name]
    return {
        display_key = 'amap.reward_recipe_productivity_preview',
        display_args = {recipe.localised_name},
        params = {recipe_name = picked_name}
    }
end

local function grant_recipe_productivity(player, data, multiplier, params)
    local force = data and data.original_force and game.forces[data.original_force] or player.force
    local recipe_name = params and params.recipe_name
    if not recipe_name then
        -- 兜底：无预抽参数时随机一个（不应发生）
        local recipes = collect_unlocked_ground_recipes(force)
        if #recipes == 0 then
            player.print({'amap.reward_recipe_productivity_no_recipe'}, {r = 1, g = 0.5, b = 0})
            return
        end
        local picked_name = recipes[math.random(1, #recipes)]
        local picked = force.recipes[picked_name]
        picked.productivity_bonus = picked.productivity_bonus + 0.03
        player.print({'amap.reward_recipe_productivity_granted', picked.localised_name},
                     {r = 0, g = 1, b = 0})
        return
    end
    local recipe = force.recipes[recipe_name]
    if not recipe then
        player.print({'amap.reward_recipe_productivity_no_recipe'}, {r = 1, g = 0.5, b = 0})
        return
    end

    -- [DIAG] 记录 recipe productivity 写入的 force
    log('[grant_recipe_productivity DIAG] player=' .. player.name
        .. ' force=' .. force.name
        .. ' recipe=' .. recipe_name
        .. ' productivity_before=' .. tostring(recipe.productivity_bonus))

    recipe.productivity_bonus = recipe.productivity_bonus + 0.03
    player.print({'amap.reward_recipe_productivity_granted', recipe.localised_name},
                 {r = 0, g = 1, b = 0})
end

--==============================================================================
-- 奖励 2：阵营加成（rare/中档，按字段类型 +0.03 或 +1）
--==============================================================================

-- 格式化阵营加成的显示值：percentage → "+3%"，absolute → "+1"
-- value 是 API 实际写入的数值（0.03 / 1），display_value 是给玩家看的字符串
local function format_force_mod_display(mod_type, value)
    if mod_type == 'percentage' then
        return string.format('+%d%%', math.floor(value * 100 + 0.5))
    else
        return string.format('+%d', value)
    end
end

local function force_mod_roll_preview(player, difficulty)
    local picked = FORCE_MODIFIERS[math.random(1, #FORCE_MODIFIERS)]
    local value = picked.value or (picked.type == 'percentage' and 0.03 or 1)
    local display_value = format_force_mod_display(picked.type, value)
    return {
        display_key = 'amap.reward_force_modifier_preview',
        display_args = {{picked.name_key}, display_value},
        params = {modifier_key = picked.key, modifier_type = picked.type, modifier_name_key = picked.name_key, modifier_value = value}
    }
end

local function grant_force_modifier(player, data, multiplier, params)
    local force = data and data.original_force and game.forces[data.original_force] or player.force
    local key = params and params.modifier_key
    local mod_type = params and params.modifier_type
    local name_key = params and params.modifier_name_key
    local value = params and params.modifier_value
    if not key or not mod_type then
        -- 兜底：无预抽参数时随机一个（不应发生）
        local picked = FORCE_MODIFIERS[math.random(1, #FORCE_MODIFIERS)]
        key = picked.key
        mod_type = picked.type
        name_key = picked.name_key
        value = picked.value or (mod_type == 'percentage' and 0.03 or 1)
    end
    if not value then
        value = mod_type == 'percentage' and 0.03 or 1
    end
    force[key] = force[key] + value
    local display_value = format_force_mod_display(mod_type, value)
    player.print({'amap.reward_force_modifier_granted', {name_key}, display_value},
                 {r = 0, g = 1, b = 0})
end

--==============================================================================
-- 奖励 3：伤害加成（epic/高档，固定 +3%）
-- 弹药伤害加成（set_ammo_damage_modifier）和炮塔攻击加成（set_turret_attack_modifier）
-- 二选一：50% 概率加弹药伤害，50% 概率加炮塔攻击
-- 弹药从玩家已解锁的弹药类别中选，炮塔从玩家已解锁的炮塔类型中选
--==============================================================================

local function damage_roll_preview(player, difficulty)
    local force = player.force
    local use_ammo = math.random() < 0.5  -- 50% 概率走弹药，50% 走炮塔
    if use_ammo then
        local unlocked_ammo = get_unlocked_ammo_categories(force)
        local picked_ammo = unlocked_ammo[math.random(1, #unlocked_ammo)]
        return {
            display_key = 'amap.reward_damage_bonus_ammo_preview',
            display_args = {{'amap.reward_ammo_' .. picked_ammo}},
            params = {kind = 'ammo', ammo_category = picked_ammo}
        }
    else
        local unlocked_turrets = get_unlocked_turrets(force)
        local picked_turret = unlocked_turrets[math.random(1, #unlocked_turrets)]
        return {
            display_key = 'amap.reward_damage_bonus_turret_preview',
            display_args = {{'amap.reward_turret_' .. picked_turret}},
            params = {kind = 'turret', turret = picked_turret}
        }
    end
end

local function grant_damage_bonus(player, data, multiplier, params)
    local force = data and data.original_force and game.forces[data.original_force] or player.force
    local kind = params and params.kind

    if not kind then
        -- 兜底：无预抽参数时随机一种（不应发生）
        if math.random() < 0.5 then
            local unlocked_ammo = get_unlocked_ammo_categories(force)
            local picked_ammo = unlocked_ammo[math.random(1, #unlocked_ammo)]
            params = {kind = 'ammo', ammo_category = picked_ammo}
        else
            local unlocked_turrets = get_unlocked_turrets(force)
            local picked_turret = unlocked_turrets[math.random(1, #unlocked_turrets)]
            params = {kind = 'turret', turret = picked_turret}
        end
        kind = params.kind
    end

    if kind == 'ammo' then
        local ammo = params.ammo_category
        local current = force.get_ammo_damage_modifier(ammo)
        force.set_ammo_damage_modifier(ammo, current + 0.03)
        player.print({'amap.reward_damage_bonus_ammo_granted', {'amap.reward_ammo_' .. ammo}},
                     {r = 0, g = 1, b = 0})
    else  -- 'turret'
        local turret = params.turret
        local current = force.get_turret_attack_modifier(turret)
        force.set_turret_attack_modifier(turret, current + 0.03)
        player.print({'amap.reward_damage_bonus_turret_granted', {'amap.reward_turret_' .. turret}},
                     {r = 0, g = 1, b = 0})
    end
end

--==============================================================================
-- 奖励 4：商店随机包（common/rare，10K × multiplier）
--==============================================================================

local function shop_pack_low_roll_preview(player, difficulty)
    return {
        display_key = 'amap.reward_shop_pack_low_preview',
        display_args = {},
        params = {}
    }
end

local function shop_pack_mid_roll_preview(player, difficulty)
    return {
        display_key = 'amap.reward_shop_pack_mid_preview',
        display_args = {},
        params = {}
    }
end

-- quality_tier: 'low' 或 'mid'（对应宠物 quality_weights）
local function grant_shop_pack(player, data, multiplier, quality_tier)
    local total_value = math.floor(10000 * multiplier)
    if total_value <= 0 then return end

    -- 从 WPT 读取商店随机物品（由 rock.lua refresh_shop 时缓存）
    -- 不直接 require rock.lua 以避免循环依赖：builtin → rock → dungeon → builtin
    local this = WPT.get()
    local raw_offers = this.market_random_offers or {}

    -- 过滤可用 offer：price[1].name == 'coin' 且 offer.type == 'give-item' 且 offer.item ~= 'coin'
    local offers = {}
    for _, offer in ipairs(raw_offers) do
        if offer.price and offer.price[1] and offer.price[1].name == 'coin'
           and offer.offer and offer.offer.type == 'give-item'
           and offer.offer.item and offer.offer.item ~= 'coin' then
            offers[#offers + 1] = offer
        end
    end

    if #offers == 0 then
        -- 商店尚未刷新或无可用物品，直接给 coin 兜底
        player.insert({name = 'coin', count = total_value})
        player.print({'amap.reward_shop_pack_coins_fallback', total_value},
                     {r = 0, g = 1, b = 0})
        return
    end

    local remaining = total_value
    local max_iterations = 50  -- 防止无限循环
    local items_granted_count = 0

    for _ = 1, max_iterations do
        if remaining <= 0 then break end

        local offer = offers[math.random(1, #offers)]
        local price = offer.price[1].count
        if price > remaining then goto continue end

        -- 滚品质（1..5）
        local q_idx = Pet.roll_quality(quality_tier)
        local quality = QUALITY_NAMES[q_idx]

        local item_name = offer.offer.item
        local item_count = offer.offer.count or 1
        local inserted = player.insert({name = item_name, count = item_count, quality = quality})
        if inserted > 0 then
            remaining = remaining - price
            items_granted_count = items_granted_count + 1
        end

        ::continue::
    end

    -- 剩余价值用 coin 补足（找不到足够便宜的物品时）
    if remaining > 0 then
        player.insert({name = 'coin', count = remaining})
    end

    player.print({'amap.reward_shop_pack_granted', total_value, items_granted_count},
                 {r = 0, g = 1, b = 0})
end

--==============================================================================
-- 保卫战特殊奖励 1：宠物技能书（3 档分别归入 common/rare/epic）
-- 发放方式：pet_data.skill_books[book_type] += 1（玩家之后可在宠物 GUI 使用）
-- 不直接弹 GUI，避免在副本退出瞬间打断玩家
--==============================================================================

local function pet_skill_book_roll_preview(player, difficulty, book_type)
    return {
        display_key = 'amap.reward_pet_skill_book_preview',
        display_args = {{'amap.reward_pet_skill_book_tier_' .. book_type}},
        params = {book_type = book_type}
    }
end

local function grant_pet_skill_book(player, data, multiplier, params)
    local book_type = params and params.book_type or 'low'
    -- 直接增加技能书计数器（参考 modules/pet_system/main.lua:170-197 的 purchase_skill_book 内部逻辑）
    -- Pet.get_player_pet_data 在 modules/pet_system/table.lua:353 定义
    local pet_data = Pet.get_player_pet_data(player)
    if not pet_data then
        player.print({'amap.reward_pet_skill_book_no_pet'}, {r = 1, g = 0.5, b = 0})
        return
    end
    if not pet_data.skill_books then
        pet_data.skill_books = {low = 0, mid = 0, high = 0}
    end
    pet_data.skill_books[book_type] = pet_data.skill_books[book_type] + 1
    player.print({'amap.reward_pet_skill_book_granted', {'amap.reward_pet_skill_book_tier_' .. book_type}},
                 {r = 0, g = 1, b = 0})
end

--==============================================================================
-- 保卫战特殊奖励 2：RPG 四属性点（rare/中档，4 选 1 加 20 点）
--==============================================================================

local RPG_ATTRS = {
    {key = 'strength',  name_key = 'amap.reward_rpg_strength'},
    {key = 'magicka',   name_key = 'amap.reward_rpg_magicka'},
    {key = 'dexterity', name_key = 'amap.reward_rpg_dexterity'},
    {key = 'vitality',  name_key = 'amap.reward_rpg_vitality'},
}

local function rpg_attr_roll_preview(player, difficulty)
    local picked = RPG_ATTRS[math.random(1, #RPG_ATTRS)]
    return {
        display_key = 'amap.reward_rpg_attr_preview',
        display_args = {{picked.name_key}, 20},
        params = {attr_key = picked.key, attr_name_key = picked.name_key}
    }
end

local function grant_rpg_attr(player, data, multiplier, params)
    local attr_key = params and params.attr_key
    local name_key = params and params.attr_name_key
    if not attr_key then
        -- 兜底：无预抽参数时随机选一个（不应发生）
        local picked = RPG_ATTRS[math.random(1, #RPG_ATTRS)]
        attr_key = picked.key
        name_key = picked.name_key
    end
    local rpg_t = RPG.get('rpg_t')
    local entry = rpg_t and rpg_t[player.index]
    if not entry then
        player.print({'amap.reward_rpg_attr_failed'}, {r = 1, g = 0.5, b = 0})
        return
    end
    entry[attr_key] = (entry[attr_key] or 0) + 20
    player.print({'amap.reward_rpg_attr_granted', {name_key}, 20},
                 {r = 0, g = 1, b = 0})
end

--==============================================================================
-- 保卫战特殊奖励 3：随机天赋（epic/高档，low 品质概率）
-- 调用 tianfu.get_new_tianfu(player, 'low') 弹 5 选 1 GUI
--==============================================================================

local function tianfu_roll_preview(player, difficulty)
    return {
        display_key = 'amap.reward_tianfu_preview',
        display_args = {},
        params = {tier = 'low'}
    }
end

local function grant_tianfu(player, data, multiplier, params)
    local tier = params and params.tier or 'low'
    -- 调用天赋系统弹 5 选 1 GUI（参考 rock.lua:441-481 购买天赋的实现）
    if not Tianfu or not Tianfu.get_new_tianfu then
        player.print({'amap.reward_tianfu_failed'}, {r = 1, g = 0.5, b = 0})
        return
    end
    Tianfu.get_new_tianfu(player, tier)
    -- 补偿：副本奖励天赋不占用升级天赋档位（与 rock.lua/diff.lua 同模式）
    local this = WPT.get()
    if not this.tianfu_count[player.index] then this.tianfu_count[player.index] = 0 end
    this.tianfu_count[player.index] = this.tianfu_count[player.index] - 1
    player.print({'amap.reward_tianfu_granted'},
                 {r = 0, g = 1, b = 0})
end

--==============================================================================
-- 保卫战特殊奖励 4：金币 15K（rare/中档，固定 15000，不受 multiplier 影响）
-- 注：副本奖励属于"任务奖励"性质，不违反"魔法技能不得直接产出金币"规则
--==============================================================================

local COIN_REWARD_AMOUNT = 15000

local function coin_roll_preview(player, difficulty)
    return {
        display_key = 'amap.reward_coin_preview',
        display_args = {COIN_REWARD_AMOUNT},
        params = {amount = COIN_REWARD_AMOUNT}
    }
end

local function grant_coin(player, data, multiplier, params)
    local amount = (params and params.amount) or COIN_REWARD_AMOUNT
    if not player.character or not player.character.valid then
        player.print({'amap.reward_coin_failed'}, {r = 1, g = 0.5, b = 0})
        return
    end
    player.insert({name = 'coin', count = amount})
    player.print({'amap.reward_coin_granted', amount},
                 {r = 0, g = 1, b = 0})
end

--==============================================================================
-- 注册
--==============================================================================

-- 产能加成：动态权重 = 玩家已解锁非太空配方数（让每个配方都算独立条目）
Rewards.register('recipe_productivity', {
    name_key = 'amap.reward_recipe_productivity_name',
    description_key = 'amap.reward_recipe_productivity_desc',
    category = 'common',
    icon = 'recipe/productivity-module',
    weight = function(player)
        if not player or not player.valid then return 1 end
        local recipes = collect_unlocked_ground_recipes(player.force)
        return math.max(1, #recipes)
    end,
    roll_preview = recipe_roll_preview,
    grant_scaled = grant_recipe_productivity
})

Rewards.register('force_modifier', {
    name_key = 'amap.reward_force_modifier_name',
    description_key = 'amap.reward_force_modifier_desc',
    category = 'rare',
    icon = 'item/speed-module',
    weight = #FORCE_MODIFIERS,  -- 12 项，每项算 1 个独立条目
    roll_preview = force_mod_roll_preview,
    grant_scaled = grant_force_modifier
})

-- 伤害加成：动态权重 = 已解锁弹药数 + 已解锁炮塔数（弹药/炮塔每个算 1 个独立条目）
Rewards.register('damage_bonus', {
    name_key = 'amap.reward_damage_bonus_name',
    description_key = 'amap.reward_damage_bonus_desc',
    category = 'epic',
    icon = 'item/distractor-cannon-shell',
    weight = function(player)
        if not player or not player.valid then return 1 end
        local ammo_count = #get_unlocked_ammo_categories(player.force)
        local turret_count = #get_unlocked_turrets(player.force)
        return math.max(1, ammo_count + turret_count)
    end,
    roll_preview = damage_roll_preview,
    grant_scaled = grant_damage_bonus
})

Rewards.register('shop_pack_low', {
    name_key = 'amap.reward_shop_pack_low_name',
    description_key = 'amap.reward_shop_pack_desc',
    category = 'common',
    icon = 'item/wooden-chest',
    weight = 1,  -- 商店包算 1 个条目
    roll_preview = shop_pack_low_roll_preview,
    grant_scaled = function(player, data, multiplier, params)
        grant_shop_pack(player, data, multiplier, 'low')
    end
})

Rewards.register('shop_pack_mid', {
    name_key = 'amap.reward_shop_pack_mid_name',
    description_key = 'amap.reward_shop_pack_desc',
    category = 'rare',
    icon = 'item/iron-chest',
    weight = 1,  -- 商店包算 1 个条目
    roll_preview = shop_pack_mid_roll_preview,
    grant_scaled = function(player, data, multiplier, params)
        grant_shop_pack(player, data, multiplier, 'mid')
    end
})

-- 保卫战特殊奖励：宠物技能书（3 档分别归入 common/rare/epic）
Rewards.register('pet_skill_book_low', {
    name_key = 'amap.reward_pet_skill_book_name',
    description_key = 'amap.reward_pet_skill_book_desc',
    category = 'common',
    icon = 'item/book',
    weight = 1,
    roll_preview = function(player, difficulty)
        return pet_skill_book_roll_preview(player, difficulty, 'low')
    end,
    grant_scaled = grant_pet_skill_book
})

Rewards.register('pet_skill_book_mid', {
    name_key = 'amap.reward_pet_skill_book_name',
    description_key = 'amap.reward_pet_skill_book_desc',
    category = 'rare',
    icon = 'item/book',
    weight = 1,
    roll_preview = function(player, difficulty)
        return pet_skill_book_roll_preview(player, difficulty, 'mid')
    end,
    grant_scaled = grant_pet_skill_book
})

Rewards.register('pet_skill_book_high', {
    name_key = 'amap.reward_pet_skill_book_name',
    description_key = 'amap.reward_pet_skill_book_desc',
    category = 'epic',
    icon = 'item/book',
    weight = 1,
    roll_preview = function(player, difficulty)
        return pet_skill_book_roll_preview(player, difficulty, 'high')
    end,
    grant_scaled = grant_pet_skill_book
})

-- 保卫战特殊奖励：RPG 四属性点（rare/中档，4 选 1 加 20 点）
Rewards.register('rpg_attr', {
    name_key = 'amap.reward_rpg_attr_name',
    description_key = 'amap.reward_rpg_attr_desc',
    category = 'rare',
    icon = 'item/efficiency-module',
    weight = #RPG_ATTRS,  -- 4 项，每项算 1 个独立条目
    roll_preview = rpg_attr_roll_preview,
    grant_scaled = grant_rpg_attr
})

-- 保卫战特殊奖励：随机天赋（epic/高档，low 品质概率）
Rewards.register('tianfu', {
    name_key = 'amap.reward_tianfu_name',
    description_key = 'amap.reward_tianfu_desc',
    category = 'epic',
    icon = 'item/processor',
    weight = 1,
    roll_preview = tianfu_roll_preview,
    grant_scaled = grant_tianfu
})

-- 保卫战特殊奖励：金币 15K（rare/中档）
Rewards.register('coin', {
    name_key = 'amap.reward_coin_name',
    description_key = 'amap.reward_coin_desc',
    category = 'rare',
    icon = 'item/coin',
    weight = 1,
    roll_preview = coin_roll_preview,
    grant_scaled = grant_coin
})

return true
