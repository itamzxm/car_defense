-- ============================================================
-- combat 技能定义（从 skills.lua 拆分，逐字保留，勿手改逻辑）
-- 填充共享 skill_defs 表；execute 闭包内自引用 skill_defs['技能名'] 保持有效
-- ============================================================

local EntityCache = require 'maps.amap.entity_cache'
local RPG = require 'modules.rpg.core'
local Task = require 'utils.task'
local pet_table = require 'modules.pet_system.table'
local Helpers = require 'modules.pet_system.skill_helpers'

local QSPRITE = Helpers.QSPRITE
local show_skill_text = Helpers.show_skill_text
local show_damage_text = Helpers.show_damage_text
local destroy_turret_token = Helpers.destroy_turret_token
local juesi_check_token = Helpers.juesi_check_token
local remove_speed_buff_token = Helpers.remove_speed_buff_token
local active_lava_burst_token = Helpers.active_lava_burst_token
local tesla_bounce_token = Helpers.tesla_bounce_token
local leizhenyu_strike_token = Helpers.leizhenyu_strike_token
local restore_yemu_token = Helpers.restore_yemu_token

return function(skill_defs)

-- ============================================================
-- 物品价值计算与生产技能辅助（原 skills.lua）
-- ============================================================
-- 军事岛物品列表
local military_items = {
    "firearm-magazine",
    "piercing-rounds-magazine",
    "uranium-rounds-magazine",
    "shotgun-shell",
    "piercing-shotgun-shell",
    "rocket",
    "explosive-rocket",
    "flamethrower-ammo",
    "grenade",
    "cluster-grenade",
    "poison-capsule",
    "slowdown-capsule",
    "land-mine",
    "defender-capsule",
    "distractor-capsule",
    "gun-turret",
    "laser-turret",
    "stone-wall"
}

-- 工业岛物品列表
local industrial_items = {
    "iron-plate",
    "steel-plate",
    "copper-plate",
    "solid-fuel",
    "plastic-bar",
    "sulfur",
    "battery",
    "explosives",
    "electronic-circuit",
    "advanced-circuit",
    "processing-unit",
    "engine-unit",
    "electric-engine-unit",
    "landfill"
}

-- 物品价值缓存（模块级，避免重复递归计算）
local item_value_cache = {}

-- 计算物品的基础价值（基于配方递归计算所需原材料时间）
local function calculate_base_item_value(item_name, depth)
    depth = depth or 0
    if depth > 10 then return 1 end

    if item_value_cache[item_name] then
        return item_value_cache[item_name]
    end

    local recipe = prototypes.recipe[item_name]

    if not recipe then
        item_value_cache[item_name] = 1
        return 1
    end

    local total_time = recipe.energy

    local product_amount = 1
    for _, product in pairs(recipe.products) do
        if product.name == item_name then
            product_amount = product.amount or product.amount_min or 1
            break
        end
    end

    for _, ingredient in pairs(recipe.ingredients) do
        if ingredient.type == "item" then
            local sub_time = calculate_base_item_value(ingredient.name, depth + 1)
            total_time = total_time + (sub_time * ingredient.amount / product_amount)
        end
    end

    item_value_cache[item_name] = total_time
    return total_time
end

-- 从物品列表中随机抽取 n 个不重复物品
local function pick_random_items(source_items, n)
    local shuffled = {}
    for i, item in ipairs(source_items) do
        shuffled[i] = item
    end

    for i = #shuffled, 2, -1 do
        local j = math.random(1, i)
        shuffled[i], shuffled[j] = shuffled[j], shuffled[i]
    end

    local result = {}
    local count = math.min(n, #shuffled)
    for i = 1, count do
        table.insert(result, shuffled[i])
    end
    return result
end

-- ============================================================
-- 生产技能数值平衡（参考 island_manager.lua）
-- ============================================================
-- 岛屿初始生产力 7500，升级后 = level × 5000
-- 1级岛=5000, 2级岛=10000, 3级岛=15000, 4级岛=20000, 5级岛=25000
--
-- 技能生产价值公式：
--   初始价值 = 7500 × 5% = 375（攻击力0时）
--   400攻击力 = 1级岛价值 = 5000
--   每300攻击力升一级：700→10000, 1000→15000, 1300→20000, 1600→25000（上限）
--   品质系数：1.2 / 1.4 / 1.6 / 1.8 / 2.0（普通到传说）
--   最终价值 = 基础价值 × 品质系数

local ISLAND_INITIAL_CAPACITY = 7500
local ISLAND_LEVEL_CAPACITY = 5000
local MAX_ISLAND_LEVEL = 5
local INITIAL_VALUE_RATIO = 0.05
local SKILL_ATTACK_THRESHOLD = 400   -- 达到1级岛价值的攻击力阈值（提升100点）
local SKILL_ATTACK_PER_LEVEL = 300   -- 每级岛屿所需的攻击力增量（提升100点）

-- 计算生产技能的基础价值（不含品质系数）
local function calculate_production_base_value(attack)
    local initial_value = ISLAND_INITIAL_CAPACITY * INITIAL_VALUE_RATIO  -- 375

    if attack < SKILL_ATTACK_THRESHOLD then
        -- 0~400 攻击力：从初始价值线性插值到1级岛价值
        local ratio = attack / SKILL_ATTACK_THRESHOLD
        return initial_value + (ISLAND_LEVEL_CAPACITY - initial_value) * ratio
    else
        -- 400+ 攻击力：每300攻击力升一级，上限5级
        local level = math.floor((attack - SKILL_ATTACK_THRESHOLD) / SKILL_ATTACK_PER_LEVEL) + 1
        level = math.min(level, MAX_ISLAND_LEVEL)
        return ISLAND_LEVEL_CAPACITY * level
    end
end

skill_defs['有丝分裂'] = {
    name = '有丝分裂',
    category = 'combat',
    trigger = 'time',
    interval_ticks = 360,
    quality_values = {10, 20, 30, 40, 50},  -- 继承血量百分比
    execute = function(player, pet, q_idx)
        local surface = player.physical_surface
        local pct = skill_defs['有丝分裂'].quality_values[q_idx]
        local pos = pet.unit.position

        local spawn_pos = surface.find_non_colliding_position(
            pet.type, pos, 3, 1, false
        )
        if not spawn_pos then
            spawn_pos = pos
        end

        local clone = surface.create_entity({
            name = pet.type,
            position = spawn_pos,
            force = 'player',
        })
        if clone then
            local clone_hp = math.floor(pet.hp * pct / 100)
            if clone_hp < 1 then clone_hp = 1 end
            clone.health = math.min(clone_hp, clone.max_health or clone_hp)
            clone.ai_settings.allow_try_return_to_spawner = false
            clone.ai_settings.allow_destroy_when_commands_fail = true

            -- 加入攻击编组
            local group = surface.create_unit_group({
                position = spawn_pos,
                force = 'player',
            })
            if group then
                group.add_member(clone)
                group.set_command({
                    type = defines.command.attack_area,
                    destination = player.physical_position,
                    radius = 24,
                })
                group.start_moving()
            end

            show_skill_text(player, pet, ({'pet_system.skill_yousifenlie_text', pct, clone_hp}), {r = 0.5, g = 1, b = 0.3})
        end
    end,
}

skill_defs['弹幕投掷'] = {
    name = '弹幕投掷',
    category = 'combat',
    trigger = 'time',
    interval_ticks = 240,
    quality_values = {3, 4, 5, 6, 7},  -- 投掷数量
    execute = function(player, pet, q_idx)
        local surface = player.physical_surface
        local pos = pet.unit.position
        local throw_count = skill_defs['弹幕投掷'].quality_values[q_idx]

        local enemies = EntityCache.find_entities_cached(surface, {
            position = pos,
            radius = 20,
            force = 'enemy',
            type = {'unit', 'turret', 'unit-spawner', 'spider-unit'},
        })

        if #enemies == 0 then return end

        local projectiles = {
            'shotgun-pellet',
            'piercing-shotgun-pellet',
            'grenade',
            'cluster-grenade',
            'explosive-rocket',
            'cannon-projectile',
        }

        local thrown = 0
        for i = 1, throw_count do
            local target = enemies[math.random(1, #enemies)]
            if target and target.valid then
                local proj = projectiles[math.random(1, #projectiles)]
                surface.create_entity({
                    name = proj,
                    position = pos,
                    force = 'player',
                    source = pet.unit,
                    target = target,
                    speed = 1,
                })
                thrown = thrown + 1
            end
        end
        if thrown > 0 then
            show_skill_text(player, pet, ({'pet_system.skill_danmu_text', thrown}), {r = 0.8, g = 0.6, b = 0.1})
        end
    end,
}

skill_defs['火箭发射器'] = {
    name = '火箭发射器',
    category = 'combat',
    trigger = 'time',
    interval_ticks = 360,
    quality_values = {2, 3, 4, 5, 6},
    execute = function(player, pet, q_idx)
        local surface = player.physical_surface
        local pos = pet.unit.position
        local rocket_count = skill_defs['火箭发射器'].quality_values[q_idx]

        local enemies = EntityCache.find_entities_cached(surface, {
            position = pos,
            radius = 25,
            force = 'enemy',
            type = {'unit', 'turret', 'unit-spawner', 'spider-unit'},
        })

        if #enemies == 0 then return end

        local r_type = 'explosive-rocket'
        local fired = 0
        for i = 1, rocket_count do
            local target = enemies[math.random(1, #enemies)]
            if target and target.valid then
                surface.create_entity({
                    name = r_type,
                    position = pos,
                    force = 'player',
                    source = pos,
                    target = target.position,
                    speed = 0.3,
                    max_range = 30,
                })
                fired = fired + 1
            end
        end
        if fired > 0 then
            show_skill_text(player, pet, ({'pet_system.skill_huojianfashe_text', fired}), {r = 1, g = 0.4, b = 0.1})
        end
    end,
}

skill_defs['旋风斩'] = {
    name = '旋风斩',
    category = 'combat',
    trigger = 'time',
    interval_ticks = 360,
    quality_values = {0.5, 0.7, 0.9, 1.1, 1.3},
    execute = function(player, pet, q_idx)
        local surface = player.physical_surface
        local pos = pet.unit.position
        local mult = skill_defs['旋风斩'].quality_values[q_idx]

        local enemies = surface.find_entities_filtered({
            position = pos,
            radius = 5,
            force = 'enemy',
            type = {'unit', 'turret'},
        })

        local dmg = math.floor(pet.attack * mult)
        local hit_count = 0

        for _, enemy in ipairs(enemies) do
            if enemy and enemy.valid then
                -- 视觉特效（每个被击中的敌人都崩裂）
                surface.create_entity({
                    name = 'vulcanus-cliff-collapse',
                    position = enemy.position,
                    force = 'neutral',
                })
                show_damage_text(player, enemy, dmg)
                enemy.damage(dmg, 'player', 'physical', player.character)
                hit_count = hit_count + 1
            end
        end
        if hit_count > 0 then
            show_skill_text(player, pet, ({'pet_system.skill_xuanfeng_text', hit_count, dmg}), {r = 0.7, g = 0.7, b = 0.7})
        end
    end,
}

skill_defs['生命汲取'] = {
    name = '生命汲取',
    category = 'combat',
    trigger = 'time',
    interval_ticks = 60,
    quality_values = {0.8, 1.0, 1.2, 1.4, 1.6},
    execute = function(player, pet, q_idx)
        local surface = player.physical_surface
        local pos = pet.unit.position
        local mult = skill_defs['生命汲取'].quality_values[q_idx]

        local enemies = EntityCache.find_entities_cached(surface, {
            position = pos,
            radius = 8,
            force = 'enemy',
            type = {'unit', 'turret', 'unit-spawner', 'spider-unit'},
            limit = 1,
        })

        if #enemies == 0 then return end
        local target = enemies[1]
        if not target or not target.valid then return end

        local dmg = math.floor(pet.attack * mult)
        show_damage_text(player, target, dmg)
        target.damage(dmg, 'player', 'physical', player.character)

        local heal = math.ceil(dmg * 0.2)
        pet.hp = math.min(pet.max_hp, pet.hp + heal)
        show_skill_text(player, pet, ({'pet_system.skill_shengming_text', dmg}), {r = 0.7, g = 0.1, b = 0.7})
    end,
}

skill_defs['金刚狼'] = {
    name = '金刚狼',
    category = 'combat',
    trigger = 'time',
    interval_ticks = 180,
    quality_values = {10, 15, 20, 25, 30},
    execute = function(player, pet, q_idx)
        local pct = skill_defs['金刚狼'].quality_values[q_idx]
        local missing = pet.max_hp - pet.hp
        if missing <= 0 then return end
        local heal = math.ceil(missing * pct / 100)
        pet.hp = math.min(pet.max_hp, pet.hp + heal)
    end,
}

skill_defs['地裂'] = {
    name = '地裂',
    category = 'combat',
    trigger = 'time',
    interval_ticks = 720,
    quality_values = {0.6, 0.9, 1.2, 1.5, 1.8},
    execute = function(player, pet, q_idx)
        local surface = player.physical_surface
        local pos = pet.unit.position
        local mult = skill_defs['地裂'].quality_values[q_idx]

        local enemies = EntityCache.find_entities_cached(surface, {
            position = pos,
            radius = 15,
            force = 'enemy',
            type = {'unit', 'turret', 'unit-spawner', 'spider-unit'},
            limit = 1,
        })

        if #enemies == 0 then return end
        local target = enemies[1]
        if not target or not target.valid then return end

        -- 中心伤害
        local center_dmg = math.floor(pet.attack * mult)
        show_damage_text(player, target, center_dmg)
        target.damage(center_dmg, 'player', 'explosion', player.character)

        -- 周围溅射（5m，50% 伤害）
        local nearby = surface.find_entities_filtered({
            position = target.position,
            radius = 5,
            force = 'enemy',
            type = {'unit', 'turret'},
        })

        local splash_dmg = math.floor(center_dmg * 0.5)
        local hit_count = 1
        for _, e in ipairs(nearby) do
            if e.valid and e ~= target then
                show_damage_text(player, e, splash_dmg)
                e.damage(splash_dmg, 'player', 'explosion', player.character)
                hit_count = hit_count + 1
            end
        end

        -- 视觉特效
        surface.create_entity({
            name = 'ground-explosion',
            position = target.position,
        })

        show_skill_text(player, pet, ({'pet_system.skill_dilie_text', hit_count, center_dmg}), {r = 0.9, g = 0.4, b = 0.1})
    end,
}

skill_defs['火焰陷阱'] = {
    name = '火焰陷阱',
    category = 'combat',
    trigger = 'time',
    interval_ticks = 720,
    quality_values = {3, 5, 7, 9, 12},
    execute = function(player, pet, q_idx)
        local surface = player.physical_surface
        local pos = pet.unit.position
        local duration = skill_defs['火焰陷阱'].quality_values[q_idx] * 60
        local dmg_per_tick = math.floor(pet.attack * 0.3)

        local enemies = EntityCache.find_entities_cached(surface, {
            position = pos,
            radius = 15,
            force = 'enemy',
            type = {'unit', 'turret', 'unit-spawner', 'spider-unit'},
            limit = 1,
        })

        if #enemies == 0 then return end
        local target = enemies[1]
        if not target or not target.valid then return end

        local target_pos = target.position

        -- 创建视觉火焰效果
        for i = 1, 5 do
            surface.create_entity({
                name = 'fire-flame',
                position = {target_pos.x + (math.random() - 0.5) * 2, target_pos.y + (math.random() - 0.5) * 2},
                force = 'neutral',
            })
        end

        -- 注册熔岩池
        local this = pet_table.get()
        table.insert(this.lava_pools, {
            position = target_pos,
            surface = surface,
            damage = dmg_per_tick,
            remaining = duration,
            player_index = player.index,
        })

        show_skill_text(player, pet, ({'pet_system.skill_huoyanxianjing_text', math.floor(duration / 60)}), {r = 1, g = 0.3, b = 0})
    end,
}

skill_defs['地狱熔岩'] = {
    name = '地狱熔岩',
    category = 'combat',
    trigger = 'time',
    interval_ticks = 360,
    quality_values = {0.8, 1.0, 1.2, 1.4, 1.6},
    execute = function(player, pet, q_idx)
        local surface = player.physical_surface
        local pos = pet.unit.position
        local mult = skill_defs['地狱熔岩'].quality_values[q_idx]

        local enemies = surface.find_entities_filtered({
            position = pos,
            radius = 20,
            force = 'enemy',
            type = {'unit', 'spider-unit'},
        })
        if #enemies == 0 then return end

        -- 随机选择一个敌人
        local target = enemies[math.random(1, #enemies)]
        if not target or not target.valid then return end
        local target_pos = target.position

        -- 视觉特效（绑定玩家角色）
        surface.create_entity({
            name = 'small-demolisher-fissure',
            position = target_pos,
            force = player.force,
            source = player.character,
            player = player,
        })

        -- 立刻对目标周围 2m 内所有敌人造成伤害
        local immediate_dmg = math.floor(pet.attack * mult * 0.3)
        local immediate_enemies = surface.find_entities_filtered({
            position = target_pos,
            radius = 2,
            force = 'enemy',
            type = {'unit', 'spider-unit'},
        })
        for _, enemy in pairs(immediate_enemies) do
            if enemy and enemy.valid then
                show_damage_text(player, enemy, immediate_dmg)
                enemy.damage(immediate_dmg, 'player', 'fire', player.character)
            end
        end

        -- 延迟 2 秒爆发（大范围伤害）
        local delayed_dmg = math.floor(pet.attack * mult * 0.7)
        Task.set_timeout_in_ticks(120, active_lava_burst_token, {
            surface = surface,
            pos = target_pos,
            player = player,
            damage = delayed_dmg,
        })

        show_skill_text(player, pet, ({'pet_system.skill_diyurongyan_text'}), {r = 1, g = 0.3, b = 0})
    end,
}

skill_defs['爆裂法术'] = {
    name = '爆裂法术',
    category = 'combat',
    trigger = 'time',
    interval_ticks = 360,
    quality_values = {1, 2, 3, 4, 5},
    execute = function(player, pet, q_idx)
        local surface = player.physical_surface
        local pos = pet.unit.position
        local target_count = skill_defs['爆裂法术'].quality_values[q_idx]

        local enemies = EntityCache.find_entities_cached(surface, {
            position = pos,
            radius = 24,
            force = 'enemy',
            type = {'unit', 'turret', 'unit-spawner', 'spider-unit'},
            limit = target_count,
        })

        if #enemies == 0 then return end
        local dmg = math.floor(pet.attack * 0.6)
        local total_hit = 0

        for _, enemy in ipairs(enemies) do
            if enemy and enemy.valid then
                -- 中心伤害
                show_damage_text(player, enemy, dmg)
                enemy.damage(dmg, 'player', 'explosion', player.character)
                total_hit = total_hit + 1

                -- 周围 2m 溅射
                local splash = surface.find_entities_filtered({
                    position = enemy.position,
                    radius = 2,
                    force = 'enemy',
                    type = {'unit', 'turret'},
                })
                for _, e in ipairs(splash) do
                    if e.valid and e ~= enemy then
                        show_damage_text(player, e, dmg)
                        e.damage(dmg, 'player', 'explosion', player.character)
                    end
                end
            end
        end

        show_skill_text(player, pet, ({'pet_system.skill_baoliefashu_text', total_hit, dmg}), {r = 1, g = 0.5, b = 0})
    end,
}

skill_defs['天照'] = {
    name = '天照',
    category = 'combat',
    trigger = 'time',
    interval_ticks = 180,
    quality_values = {1, 2, 3, 4, 5},
    execute = function(player, pet, q_idx)
        local surface = player.physical_surface
        local pos = pet.unit.position
        local ignite_count = skill_defs['天照'].quality_values[q_idx]

        local enemies = surface.find_entities_filtered({
            position = pos,
            radius = 20,
            force = 'enemy',
            type = {'unit', 'spider-unit'},
        })
        if #enemies == 0 then return end

        -- 随机选取目标
        for i = #enemies, 2, -1 do
            local j = math.random(i)
            enemies[i], enemies[j] = enemies[j], enemies[i]
        end
        local count = math.min(#enemies, ignite_count)
        local ignited = 0

        for i = 1, count do
            local target = enemies[i]
            if target and target.valid then
                surface.create_entity({
                    name = 'fire-sticker',
                    position = pos,
                    source = player.character,
                    target = target,
                    force = 'player',
                    player = player,
                })
                ignited = ignited + 1
            end
        end

        if ignited > 0 then
            show_skill_text(player, pet, ({'pet_system.skill_tianzhao_text', ignited}), {r = 1, g = 0.3, b = 0})
        end
    end,
}

skill_defs['特斯拉蓄电池'] = {
    name = '特斯拉蓄电池',
    category = 'combat',
    trigger = 'time',
    interval_ticks = 540,
    quality_values = {2, 3, 4, 5, 6},
    execute = function(player, pet, q_idx)
        if not pet.unit or not pet.unit.valid then return end
        local surface = player.physical_surface
        local pos = pet.unit.position
        local start_targets = math.random(3, 5)

        local enemies = surface.find_entities_filtered({
            position = pos,
            radius = 27,
            force = 'enemy',
            type = {'unit', 'spider-unit'},
        })
        if #enemies == 0 then return end

        local count = math.min(#enemies, start_targets)
        local base_dmg = math.floor(pet.attack * skill_defs['特斯拉蓄电池'].quality_values[q_idx])

        -- 洗牌随机
        for i = #enemies, 2, -1 do
            local j = math.random(i)
            enemies[i], enemies[j] = enemies[j], enemies[i]
        end

        local hit_count = 0
        for i = 1, count do
            local target = enemies[i]
            if target and target.valid then
                -- 起始光束（从宠物位置射出）
                surface.create_entity({
                    name = 'chain-tesla-turret-beam-start',
                    position = pos,
                    force = 'enemy',
                    source = pet.unit,
                    target = target.position,
                    duration = 45,
                })
                surface.create_entity({
                    name = 'chain-tesla-turret-beam-start',
                    position = pos,
                    force = 'player',
                    source = pet.unit,
                    target = target,
                    duration = 45,
                })

                -- 初始伤害（先保存位置，damage 后实体可能已死亡）
                show_damage_text(player, target, base_dmg)
                local saved_pos = target.position
                target.damage(base_dmg, 'player', 'electric', player.character)
                hit_count = hit_count + 1

                -- 触发链式弹射
                local attacked = {target}
                Task.set_timeout_in_ticks(15, tesla_bounce_token, {
                    player = player,
                    source = saved_pos,
                    bounce_count = 1,
                    max_bounces = 10,
                    attacked = attacked,
                    base_dmg = base_dmg,
                })
            end
        end

        if hit_count > 0 then
            show_skill_text(player, pet, ({'pet_system.skill_tesila_text', hit_count}), {r = 0.2, g = 0.6, b = 1})
        end
    end,
}

skill_defs['雷阵雨'] = {
    name = '雷阵雨',
    category = 'combat',
    trigger = 'time',
    interval_ticks = 540,
    quality_values = {2, 3, 4, 5, 6},
    execute = function(player, pet, q_idx)
        local surface = player.physical_surface
        local pos = pet.unit.position
        local total_strikes = skill_defs['雷阵雨'].quality_values[q_idx]
        local radius = 6  -- 固定半径6格
        local dmg = math.floor(pet.attack * 1.2)

        for i = 1, total_strikes do
            Task.set_timeout_in_ticks(i * 60, leizhenyu_strike_token, {
                surface = surface,
                position = pos,
                player = player,
                damage = dmg,
                radius = radius,
            })
        end

        show_skill_text(player, pet, ({'pet_system.skill_leizhenyu_text', total_strikes}), {r = 0.2, g = 0.7, b = 1})
    end,
}

skill_defs['魔晶杖'] = {
    name = '魔晶杖',
    category = 'combat',
    trigger = 'time',
    interval_ticks = 180,
    quality_values = {1.0, 1.2, 1.4, 1.6, 1.8},
    execute = function(player, pet, q_idx)
        local surface = player.physical_surface
        local pos = pet.unit.position
        local mult = skill_defs['魔晶杖'].quality_values[q_idx]

        local enemies = surface.find_entities_filtered({
            position = pos,
            radius = 20,
            force = 'enemy',
            type = {'unit', 'spider-unit'},
        })
        if #enemies == 0 then return end

        -- 按距离排序
        local dists = {}
        for _, enemy in ipairs(enemies) do
            if enemy and enemy.valid then
                local dx = enemy.position.x - pos.x
                local dy = enemy.position.y - pos.y
                dists[enemy] = dx * dx + dy * dy
            end
        end
        table.sort(enemies, function(a, b)
            return (dists[a] or math.huge) < (dists[b] or math.huge)
        end)

        local nearest = enemies[1]
        local farthest = enemies[#enemies]
        if nearest == farthest then farthest = nil end  -- 只有一个敌人时不重复

        local dmg = math.floor(pet.attack * mult)
        local hit = 0

        if nearest and nearest.valid then
            surface.create_entity({
                name = 'electric-beam',
                position = pos,
                target = nearest,
                source = pet.unit,
            })
            show_damage_text(player, nearest, dmg)
            nearest.damage(dmg, 'player', 'laser', player.character)
            hit = hit + 1
        end
        if farthest and farthest.valid then
            surface.create_entity({
                name = 'electric-beam',
                position = pos,
                target = farthest,
                source = pet.unit,
            })
            show_damage_text(player, farthest, dmg)
            farthest.damage(dmg, 'player', 'laser', player.character)
            hit = hit + 1
        end

        if hit > 0 then
            show_skill_text(player, pet, ({'pet_system.skill_mojingzhang_text', hit}), {r = 0.5, g = 0.3, b = 1})
        end
    end,
}

skill_defs['灵魂一指'] = {
    name = '灵魂一指',
    category = 'combat',
    trigger = 'time',
    interval_ticks = 180,
    quality_values = {3.0, 4.0, 5.0, 6.0, 8.0},
    execute = function(player, pet, q_idx)
        local surface = player.physical_surface
        local pos = pet.unit.position
        local mult = skill_defs['灵魂一指'].quality_values[q_idx]

        local enemies = EntityCache.find_entities_cached(surface, {
            position = pos,
            radius = 24,
            force = 'enemy',
            type = {'unit', 'turret', 'unit-spawner', 'spider-unit'},
            limit = 1,
        })

        if #enemies == 0 then return end
        local target = enemies[1]
        if not target or not target.valid then return end

        local dmg = math.floor(pet.attack * mult)
        show_damage_text(player, target, dmg)
        target.damage(dmg, 'player', 'physical', player.character)

        show_skill_text(player, pet, ({'pet_system.skill_linghunyizhi_text', dmg}), {r = 0.6, g = 0.2, b = 1})
    end,
}

skill_defs['法力回流'] = {
    name = '法力回流',
    category = 'combat',
    trigger = 'time',
    interval_ticks = 360,
    quality_values = {0.3, 0.5, 0.7, 0.9, 1.2},
    execute = function(player, pet, q_idx)
        local mult = skill_defs['法力回流'].quality_values[q_idx]
        local mana_gain = math.floor(pet.attack * mult)

        RPG.functions.reward_mana(player, mana_gain)

        show_skill_text(player, pet, ({'pet_system.skill_falihuiliu_text', mana_gain}), {r = 0.3, g = 0.5, b = 1})
    end,
}

skill_defs['工兵'] = {
    name = '工兵',
    category = 'combat',
    trigger = 'time',
    interval_ticks = 360,
    quality_values = {1, 1, 2, 2, 3},
    execute = function(player, pet, q_idx)
        local surface = player.physical_surface
        local pos = pet.unit.position
        local count = skill_defs['工兵'].quality_values[q_idx]

        for i = 1, count do
            local angle = math.random() * math.pi * 2
            local dist = 4 + math.random() * 4
            local mine_pos = {
                x = pos.x + math.cos(angle) * dist,
                y = pos.y + math.sin(angle) * dist,
            }
            surface.create_entity({
                name = 'land-mine',
                position = mine_pos,
                force = player.force,
            })
        end

        show_skill_text(player, pet, ({'pet_system.skill_gongbing_text', count}), {r = 0.5, g = 0.5, b = 0.5})
    end,
}

skill_defs['愈战愈勇'] = {
    name = '愈战愈勇',
    category = 'combat',
    trigger = 'time',
    interval_ticks = 900,
    quality_values = {1, 1, 2, 2, 3},
    execute = function(player, pet, q_idx)
        local gain = skill_defs['愈战愈勇'].quality_values[q_idx]
        pet.attack = pet.attack + gain

        show_skill_text(player, pet, ({'pet_system.skill_yuzhanyuyong_text', gain, pet.attack}), {r = 1, g = 0.4, b = 0})
    end,
}

skill_defs['沙虫召唤'] = {
    name = '沙虫召唤',
    category = 'combat',
    trigger = 'time',
    interval_ticks = 420,
    quality_values = {1, 2, 3, 4, 5},
    execute = function(player, pet, q_idx)
        local surface = player.physical_surface
        -- 品质映射
        local quality_names = {'normal', 'uncommon', 'rare', 'epic', 'legendary'}
        local quality = quality_names[skill_defs['沙虫召唤'].quality_values[q_idx]] or 'normal'

        -- 根据宠物攻击力决定沙虫类型
        local worm_name
        if pet.attack < 50 then
            worm_name = 'small-worm-turret'
        elseif pet.attack < 100 then
            worm_name = 'medium-worm-turret'
        elseif pet.attack < 300 then
            worm_name = 'big-worm-turret'
        else
            worm_name = 'behemoth-worm-turret'
        end

        local pos = pet.unit.position
        local target_pos = surface.find_non_colliding_position(worm_name, pos, 3, 1, false)
        if not target_pos then return end

        local worm = surface.create_entity({
            name = worm_name,
            position = target_pos,
            force = player.force,
            quality = quality,
        })
        if worm then
            worm.destructible = false
            Task.set_timeout_in_ticks(1200, destroy_turret_token, worm)
        end

        show_skill_text(player, pet, ({'pet_system.skill_shachongzhaohuan_text', 1}), {r = 0.6, g = 0.4, b = 0.1})
    end,
}

skill_defs['战争红利'] = {
    name = '战争红利',
    category = 'combat',
    trigger = 'time',
    interval_ticks = 540,
    quality_values = {0.3, 0.4, 0.5, 0.6, 0.7},
    execute = function(player, pet, q_idx)
        local mult = skill_defs['战争红利'].quality_values[q_idx]
        local amount = math.floor(pet.attack * mult)
        if amount <= 0 then return end

        player.insert({name = 'coin', count = amount})
        show_skill_text(player, pet, ({'pet_system.skill_zhanzhenghongli_text', amount}), {r = 1, g = 0.8, b = 0.2})
    end,
}

skill_defs['无人机掩护'] = {
    name = '无人机掩护',
    category = 'combat',
    trigger = 'time',
    interval_ticks = 540,
    quality_values = {1, 1, 2, 2, 3},
    execute = function(player, pet, q_idx)
        local surface = player.physical_surface
        local count = skill_defs['无人机掩护'].quality_values[q_idx]

        local quality = QSPRITE[pet.quality] or 'normal'
        local pos = pet.unit.position

        local spawned = 0
        for i = 1, count do
            local target_pos = surface.find_non_colliding_position('distractor', pos, 5, 1, false)
            if target_pos then
                local drone = surface.create_entity({
                    name = 'distractor',
                    position = target_pos,
                    force = player.force,
                    quality = quality,
                })
                if drone then
                    spawned = spawned + 1
                end
            end
        end

        if spawned > 0 then
            show_skill_text(player, pet, ({'pet_system.skill_wurenjiyanhu_text', spawned}), {r = 0.4, g = 0.6, b = 1})
        end
    end,
}

skill_defs['再生'] = {
    name = '再生',
    category = 'combat',
    trigger = 'time',
    interval_ticks = 360,
    quality_values = {3, 4, 5, 6, 7},
    execute = function(player, pet, q_idx)
        local pct = skill_defs['再生'].quality_values[q_idx]
        local heal = math.ceil(pet.max_hp * pct / 100)
        pet.hp = math.min(pet.max_hp, pet.hp + heal)

        show_skill_text(player, pet, ({'pet_system.skill_zaisheng_text', heal}), {r = 0, g = 0.8, b = 0.2})
    end,
}

skill_defs['环形火山'] = {
    name = '环形火山',
    category = 'combat',
    trigger = 'time',
    interval_ticks = 720,
    quality_values = {3, 4, 5, 6, 7},
    execute = function(player, pet, q_idx)
        local surface = player.physical_surface
        local pos = pet.unit.position
        local max_targets = math.min(10, skill_defs['环形火山'].quality_values[q_idx])

        local enemies = surface.find_entities_filtered({
            position = pos,
            radius = 18,
            force = 'enemy',
            type = {'unit', 'spider-unit'},
        })
        if #enemies == 0 then return end

        -- 伤害计算
        local base_dmg = math.floor(pet.attack * 1.5)
        local minor_dmg = math.floor(base_dmg * 0.2)
        local major_dmg = base_dmg - minor_dmg

        -- 洗牌随机选取目标
        for i = #enemies, 2, -1 do
            local j = math.random(i)
            enemies[i], enemies[j] = enemies[j], enemies[i]
        end
        local count = math.min(#enemies, max_targets)

        for i = 1, count do
            local enemy = enemies[i]
            if enemy and enemy.valid then
                local lava_pos = enemy.position

                -- 视觉特效（双效果，对齐 RPG 版）
                surface.create_entity({
                    name = 'small-demolisher-fissure',
                    position = lava_pos,
                    force = player.force,
                })
                surface.create_entity({
                    name = 'fire-flame',
                    position = lava_pos,
                    force = game.forces.enemy,
                })

                -- 立即灼烧 20%
                show_damage_text(player, enemy, minor_dmg)
                enemy.damage(minor_dmg, 'player', 'fire', player.character)

                -- 延迟爆发 80%
                Task.set_timeout_in_ticks(100, active_lava_burst_token, {
                    surface = surface,
                    pos = lava_pos,
                    player = player,
                    damage = major_dmg,
                })
            end
        end

        show_skill_text(player, pet, ({'pet_system.skill_huanxinghuoshan_text', count}), {r = 1, g = 0.3, b = 0})
    end,
}

skill_defs['减速弹幕'] = {
    name = '减速弹幕',
    category = 'combat',
    trigger = 'time',
    interval_ticks = 360,
    quality_values = {2, 3, 4, 5, 6},
    execute = function(player, pet, q_idx)
        local surface = player.physical_surface
        local pos = pet.unit.position
        local count = skill_defs['减速弹幕'].quality_values[q_idx]

        for i = 1, count do
            local angle = math.random() * math.pi * 2
            local dist = math.random() * 24
            local target_pos = {
                x = pos.x + math.cos(angle) * dist,
                y = pos.y + math.sin(angle) * dist,
            }
            surface.create_entity({
                name = 'slowdown-capsule',
                position = target_pos,
                force = player.force,
            })
        end

        show_skill_text(player, pet, ({'pet_system.skill_jiansudanmu_text', count}), {r = 0.3, g = 0.5, b = 1})
    end,
}

skill_defs['分裂攻击'] = {
    name = '分裂攻击',
    category = 'combat',
    trigger = 'time',
    interval_ticks = 60,
    quality_values = {2, 3, 4, 5, 6},
    execute = function(player, pet, q_idx)
        local surface = player.physical_surface
        local pos = pet.unit.position
        local target_count = skill_defs['分裂攻击'].quality_values[q_idx]

        local enemies = EntityCache.find_entities_cached(surface, {
            position = pos,
            radius = 4,
            force = 'enemy',
            type = {'unit', 'turret', 'unit-spawner', 'spider-unit'},
            limit = target_count,
        })

        local dmg = math.floor(pet.attack * 0.5)
        local hit_count = 0
        for _, enemy in ipairs(enemies) do
            if enemy and enemy.valid then
                show_damage_text(player, enemy, dmg)
                enemy.damage(dmg, 'player', 'physical', player.character)
                hit_count = hit_count + 1
                if hit_count >= target_count then break end
            end
        end
        if hit_count > 0 then
            show_skill_text(player, pet, ({'pet_system.skill_fenlie_text', hit_count}), {r = 1, g = 0.6, b = 0.2})
        end
    end,
}

skill_defs['远程裂变'] = {
    name = '远程裂变',
    category = 'combat',
    trigger = 'time',
    interval_ticks = 180,
    quality_values = {3, 4, 5, 6, 7},
    execute = function(player, pet, q_idx)
        local surface = player.physical_surface
        local pos = pet.unit.position
        local target_count = skill_defs['远程裂变'].quality_values[q_idx]

        local enemies = EntityCache.find_entities_cached(surface, {
            position = pos,
            radius = 18,
            force = 'enemy',
            type = {'unit', 'turret', 'unit-spawner', 'spider-unit'},
            limit = target_count,
        })

        local dmg = math.floor(pet.attack * 0.5)
        local hit_count = 0
        for _, enemy in ipairs(enemies) do
            if enemy and enemy.valid then
                show_damage_text(player, enemy, dmg)
                enemy.damage(dmg, 'player', 'physical', player.character)
                hit_count = hit_count + 1
                if hit_count >= target_count then break end
            end
        end
        if hit_count > 0 then
            show_skill_text(player, pet, ({'pet_system.skill_yuanchengliebian_text', hit_count}), {r = 0.4, g = 0.5, b = 1})
        end
    end,
}

skill_defs['炎息'] = {
    name = '炎息',
    category = 'combat',
    trigger = 'time',
    interval_ticks = 300,
    quality_values = {3, 4, 5, 6, 7},
    execute = function(player, pet, q_idx)
        local surface = player.physical_surface
        local pos = pet.unit.position
        local target_count = skill_defs['炎息'].quality_values[q_idx]

        local enemies = EntityCache.find_entities_cached(surface, {
            position = pos,
            radius = 8,
            force = 'enemy',
            type = {'unit', 'turret', 'unit-spawner', 'spider-unit'},
            limit = target_count,
        })

        local dmg = math.floor(pet.attack * 0.4)
        local hit_count = 0
        for _, enemy in ipairs(enemies) do
            if enemy and enemy.valid then
                -- 火焰视觉特效
                surface.create_entity({
                    name = 'fire-flame',
                    position = enemy.position,
                    force = game.forces.enemy,
                })
                show_damage_text(player, enemy, dmg)
                enemy.damage(dmg, 'player', 'fire', player.character)
                hit_count = hit_count + 1
            end
        end
        if hit_count > 0 then
            show_skill_text(player, pet, ({'pet_system.skill_yanxi_text', hit_count}), {r = 1, g = 0.4, b = 0.1})
        end
    end,
}

skill_defs['蛮力冲撞'] = {
    name = '蛮力冲撞',
    category = 'combat',
    trigger = 'time',
    interval_ticks = 480,
    quality_values = {0.5, 0.7, 0.9, 1.1, 1.3},
    execute = function(player, pet, q_idx)
        local surface = player.physical_surface
        local pos = pet.unit.position
        local mult = skill_defs['蛮力冲撞'].quality_values[q_idx]

        local enemies = surface.find_entities_filtered({
            position = pos,
            radius = 4,
            force = 'enemy',
            type = {'unit', 'turret'},
        })

        local dmg = math.floor(pet.attack * mult)
        local hit_count = 0
        for _, enemy in ipairs(enemies) do
            if enemy and enemy.valid then
                show_damage_text(player, enemy, dmg)
                enemy.damage(dmg, 'player', 'physical', player.character)
                -- 击退：将敌人推离宠物，避开玩家位置
                local dx = enemy.position.x - pos.x
                local dy = enemy.position.y - pos.y
                local dist = math.sqrt(dx * dx + dy * dy)
                if dist > 0.01 then
                    local knockback = 4
                    local new_x = enemy.position.x + (dx / dist) * knockback
                    local new_y = enemy.position.y + (dy / dist) * knockback
                    -- 避开玩家位置，避免碰撞把玩家推开
                    local player_pos = player.physical_position
                    local px = new_x - player_pos.x
                    local py = new_y - player_pos.y
                    if px * px + py * py < 9 then  -- 目标在玩家 3m 内
                        new_x = player_pos.x + (px / math.sqrt(px * px + py * py)) * 3
                        new_y = player_pos.y + (py / math.sqrt(px * px + py * py)) * 3
                    end
                    local target_pos = surface.find_non_colliding_position(enemy.name, {x = new_x, y = new_y}, 2, 1, false)
                    if target_pos then
                        enemy.teleport(target_pos)
                    end
                end
                hit_count = hit_count + 1
            end
        end
        if hit_count > 0 then
            show_skill_text(player, pet, ({'pet_system.skill_chongzhuang_text', hit_count}), {r = 0.8, g = 0.5, b = 0.2})
        end
    end,
}

skill_defs['雷击'] = {
    name = '雷击',
    category = 'combat',
    trigger = 'time',
    interval_ticks = 240,
    quality_values = {3, 4, 5, 6, 7},
    execute = function(player, pet, q_idx)
        local surface = player.physical_surface
        local pos = pet.unit.position
        local chain_count = skill_defs['雷击'].quality_values[q_idx]

        local enemies = EntityCache.find_entities_cached(surface, {
            position = pos,
            radius = 15,
            force = 'enemy',
            type = {'unit', 'turret', 'unit-spawner', 'spider-unit'},
            limit = chain_count,
        })

        local hit_count = 0
        for i, enemy in ipairs(enemies) do
            if not enemy or not enemy.valid then goto next_enemy end
            local dmg
            if i == 1 then
                dmg = math.floor(pet.attack * 0.5)
            else
                dmg = math.floor(pet.attack * 0.3)
            end
            show_damage_text(player, enemy, dmg)
            enemy.damage(dmg, 'player', 'electric', player.character)
            hit_count = hit_count + 1
            ::next_enemy::
        end
        if hit_count > 0 then
            show_skill_text(player, pet, ({'pet_system.skill_leiji_text', hit_count}), {r = 0.3, g = 0.6, b = 1})
        end
    end,
}

skill_defs['吞噬'] = {
    name = '吞噬',
    category = 'combat',
    trigger = 'time',
    interval_ticks = 360,
    quality_values = {1, 2, 3, 4, 5},  -- 秒杀数量
    execute = function(player, pet, q_idx)
        local surface = player.physical_surface
        local pos = pet.unit.position
        local kill_count = skill_defs['吞噬'].quality_values[q_idx]

        local enemies = surface.find_entities_filtered({
            position = pos,
            radius = 8,
            force = 'enemy',
            type = {'unit', 'turret'},
        })

        if #enemies == 0 then return end

        local total_xp = 0
        local actual_kills = 0
        for _, enemy in ipairs(enemies) do
            if actual_kills >= kill_count then break end
            if not enemy or not enemy.valid then goto next_enemy end
            local hp = enemy.health or 0
            if hp <= 0 then goto next_enemy end
            -- 只有血量 < 20% 最大血量才可吞噬
            if enemy.max_health and hp >= enemy.max_health * 0.2 then
                goto next_enemy
            end
            local xp = math.floor(hp * 0.2)
            show_damage_text(player, enemy, hp)
            enemy.die('player', player.character)
            total_xp = total_xp + xp
            actual_kills = actual_kills + 1
            ::next_enemy::
        end

        if total_xp > 0 then
            RPG.gain_xp(player, total_xp)
        end
        if actual_kills > 0 then
            show_skill_text(player, pet, ({'pet_system.skill_tunshi_text', actual_kills, total_xp}), {r = 0.8, g = 0.2, b = 0.6})
        end
    end,
}

skill_defs['虫咬'] = {
    name = '虫咬',
    category = 'combat',
    trigger = 'time',
    interval_ticks = 60,  -- 1秒
    quality_values = {10, 12, 14, 16, 18},  -- 目标数量
    exclusive_type = 'biter',
    execute = function(player, pet, q_idx)
        local target_count = skill_defs['虫咬'].quality_values[q_idx]
        local enemies = player.physical_surface.find_entities_filtered({
            position = pet.unit.position,
            radius = 4,
            force = 'enemy',
            type = {'unit', 'spider-unit'},
            limit = target_count,
        })
        if #enemies == 0 then return end
        local dmg = math.floor(pet.max_hp * 0.05)
        if dmg < 1 then dmg = 1 end
        for _, enemy in ipairs(enemies) do
            if enemy.valid then
                show_damage_text(player, enemy, dmg)
                enemy.damage(dmg, 'player', 'physical', player.character)
            end
        end
    end,
}

skill_defs['吐口水'] = {
    name = '吐口水',
    category = 'combat',
    trigger = 'time',
    interval_ticks = 180,  -- 3秒
    quality_values = {1, 1, 1, 1, 1},  -- 品质仅影响口水伤害类型（通过quality传递）
    exclusive_type = 'spitter',
    execute = function(player, pet, q_idx)
        local enemies = player.physical_surface.find_entities_filtered({
            position = pet.unit.position,
            radius = 18,
            force = 'enemy',
            type = {'unit', 'spider-unit', 'turret', 'unit-spawner'},
            limit = 3,
        })
        for _, enemy in ipairs(enemies) do
            if enemy.valid then
                player.physical_surface.create_entity({
                    name = 'acid-splash-fire-worm-big',
                    position = enemy.position,
                    target = enemy.position,
                    source = player.character,
                    force = player.force,
                })
            end
        end
    end,
}

skill_defs['蠕虫能量'] = {
    name = '蠕虫能量',
    category = 'combat',
    trigger = 'time',
    interval_ticks = 60,  -- 1秒
    quality_values = {1, 2, 3, 4, 5},  -- 目标数量
    exclusive_type = 'wriggler',
    execute = function(player, pet, q_idx)
        local target_count = skill_defs['蠕虫能量'].quality_values[q_idx]
        local rpg_t = RPG.get_value_from_player(player.index)
        local mana_max = (rpg_t and rpg_t.mana_max) or 100
        local bonus_dmg = math.floor(mana_max * 0.1)
        if bonus_dmg < 1 then bonus_dmg = 1 end
        local enemies = player.physical_surface.find_entities_filtered({
            position = pet.unit.position,
            radius = 4,
            force = 'enemy',
            type = {'unit', 'spider-unit'},
            limit = target_count,
        })
        local hit_count = 0
        for _, enemy in ipairs(enemies) do
            if enemy.valid then
                show_damage_text(player, enemy, bonus_dmg)
                enemy.damage(bonus_dmg, 'player', 'physical', player.character)
                hit_count = hit_count + 1
            end
        end
        if hit_count > 0 then
            RPG.functions.reward_mana(player, 2 * hit_count)
            show_skill_text(player, pet, ({'pet_system.skill_ruchongnengliang_text', hit_count, bonus_dmg, 2 * hit_count}), {r = 0.3, g = 0.8, b = 0.8})
        end
    end,
}

skill_defs['支援光环'] = {
    name = '支援光环',
    category = 'combat',
    trigger = 'time',
    interval_ticks = 360,  -- 6秒
    quality_values = {15, 18, 21, 24, 27},  -- 恢复百分比
    exclusive_type = 'strafer',
    execute = function(player, pet, q_idx)
        local heal_pct = skill_defs['支援光环'].quality_values[q_idx]
        local rpg_t = RPG.get_value_from_player(player.index)
        local mana_max = (rpg_t and rpg_t.mana_max) or 100
        local heal = math.floor(mana_max * heal_pct / 100)
        -- 治疗玩家
        if player.character and player.character.valid then
            player.character.health = math.min(player.character.max_health or player.character.health, player.character.health + heal)
        end
        -- 治疗宠物
        if pet.unit and pet.unit.valid then
            pet.hp = math.min(pet.max_hp, pet.hp + heal)
            if pet.unit.health then
                pet.unit.health = math.min(pet.unit.max_health or pet.unit.health, pet.unit.health + heal)
            end
        end
        show_skill_text(player, pet, ({'pet_system.skill_zhiyuanguanghuan_text', heal_pct, heal}), {r = 0.2, g = 0.9, b = 0.4})
    end,
}

skill_defs['火遁'] = {
    name = '火遁',
    category = 'combat',
    trigger = 'time',
    interval_ticks = 720,
    quality_values = {0.8, 1.0, 1.2, 1.4, 1.6},  -- 伤害系数（普通到传说）
    execute = function(player, pet, q_idx)
        local surface = player.physical_surface
        if not pet.unit or not pet.unit.valid then return end
        local pos = pet.unit.position
        local mult = skill_defs['火遁'].quality_values[q_idx]

        -- 搜索最近敌人
        local enemies = surface.find_entities_filtered({
            position = pos,
            radius = 18,
            force = 'enemy',
            type = {'unit', 'turret', 'unit-spawner', 'spider-unit'},
        })
        if #enemies == 0 then return end

        -- 取最近的敌人作为目标
        local target = enemies[1]
        local min_dist = math.huge
        for _, enemy in ipairs(enemies) do
            local dx = enemy.position.x - pos.x
            local dy = enemy.position.y - pos.y
            local d = dx * dx + dy * dy
            if d < min_dist then min_dist = d; target = enemy end
        end
        if not target or not target.valid then return end
        local target_pos = target.position

        -- 基础伤害 = 攻击力 × 品质系数
        local base_dmg = math.floor(pet.attack * mult)

        -- 火焰路径（从宠物到目标，每 2 格一个火点）
        local dx = target_pos.x - pos.x
        local dy = target_pos.y - pos.y
        local distance = math.sqrt(dx * dx + dy * dy)
        local steps = math.floor(distance / 2) + 1
        for i = 1, steps do
            if i > 1 then
                local ratio = i / steps
                surface.create_entity({
                    name = 'fire-flame',
                    position = {pos.x + dx * ratio, pos.y + dy * ratio},
                    force = game.forces.enemy,
                })
            end
        end

        -- 火环（目标位置一圈火焰）
        local flame_radius = 4
        for i = 1, 24 do
            local angle = (i / 24) * math.pi * 2
            surface.create_entity({
                name = 'fire-flame',
                position = {
                    x = target_pos.x + math.cos(angle) * flame_radius,
                    y = target_pos.y + math.sin(angle) * flame_radius,
                },
                force = game.forces.enemy,
            })
        end

        -- AoE 伤害（距离衰减）
        local flame_radius_sq = flame_radius * flame_radius
        local hit_count = 0
        for _, enemy in ipairs(enemies) do
            if enemy and enemy.valid then
                local ex = enemy.position.x - target_pos.x
                local ey = enemy.position.y - target_pos.y
                local dist_sq = ex * ex + ey * ey
                if dist_sq <= flame_radius_sq then
                    local dist = math.sqrt(dist_sq)
                    local falloff = math.max(0.3, 1 - dist / flame_radius)
                    local final_dmg = math.floor(base_dmg * falloff)
                    if final_dmg > 0 then
                        show_damage_text(player, enemy, final_dmg)
                        enemy.damage(final_dmg, 'player', 'fire', player.character)
                        hit_count = hit_count + 1
                    end
                end
            end
        end

        if hit_count > 0 then
            show_skill_text(player, pet, ({'pet_system.skill_huodun_text', hit_count}), {r = 1, g = 0.3, b = 0})
        end
    end,
}
end
