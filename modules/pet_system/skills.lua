-- ============================================================
-- 虫子宠物技能系统框架
-- ============================================================
--
-- 设计原则：
-- - 每个技能分为 5 个品质（普通 / 稀有 / 精良 / 史诗 / 传说）。
-- - 品质仅影响系数（ATK 系数、HP 系数、数量等），
--   CD、持续时间、目标数、半径等参数均固定不变。
-- - 技能分类为内部设计（category: 'anytime' / 'combat'），不对玩家展示。
-- - 伤害归属：技能效果从宠物位置发出，但伤害来源必须归属玩家角色
--   （source = player.character），确保击杀经验和金币归属玩家。
--   参考 tianfu_time_skill.lua 的写法。
-- - 触发类型（trigger）：
--     'time'           — 随时间触发（anytime / combat）
--     'death'          — 宠物 unit 死亡时触发（combat）
--     'owner_damaged'  — 玩家受伤害时触发（combat）
-- - 添加新技能：在 skill_defs 表中注册即可，框架自动路由。
-- - 技能命名规范：技能 name 统一使用中文字符串，禁止使用英文或拼音。
--   所有 skill_defs key 均为中文字符串，确保与 pet.skills 存储一致。
--   异星工厂 Lua 环境要求中文 key 必须用 ['xxx'] 语法定义，禁止裸 key。
--
-- 【重要】magicka（魔力值） vs mana（施法能量）：
--   - magicka: RPG 属性，影响经验获取、伤害加成等，存储于 rpg_t.magicka
--   - mana:    施法消耗的能量条，存储于 rpg_t.mana，通过 RPG.functions.reward_mana() 恢复
--   - 宠物技能恢复的是 mana（施法能量），不要混淆！
--
-- ============================================================

local EntityCache = require 'maps.amap.entity_cache'
local Public = {}
local pet_table = require 'modules.pet_system.table'
local RPG = require 'modules.rpg.core'
local Task = require 'utils.task'
local Token = require 'utils.token'

-- Token to destroy a turret after delay
local destroy_turret_token = Token.register(function(turret)
    if turret and turret.valid then
        turret.destroy()
    end
end)

-- Token for 决死冲锋 delayed check
local juesi_check_token = Token.register(function(data)
    local player = game.players[data.player_index]
    if not player or not player.valid then return end
    local pet_data = pet_table.get_player_pet_data(player)
    local pet = pet_data.pets[data.pet_index]
    if not pet then return end
    if not pet.unit or not pet.unit.valid then return end
    if pet.unit.unit_number ~= data.unit_id then return end

    local enemies = player.physical_surface.find_entities_filtered({
        position = pet.unit.position,
        radius = 18,
        force = 'enemy',
        type = {'unit', 'turret', 'unit-spawner', 'spider-unit'},
        limit = 1,
    })
    if #enemies > 0 then
        pet.unit.destructible = true
        pet.unit.die('enemy', pet.unit)
    else
        pet.unit.destructible = true
    end
end)

-- Token to remove speed buff from a character
local remove_speed_buff_token = Token.register(function(char)
    if char and char.valid then
        char.character_running_speed_modifier = math.max(0, (char.character_running_speed_modifier or 0.3) - 0.3)
    end
end)

-- Token for delayed lava burst explosion
local active_lava_burst_token = Token.register(function(data)
    local surface = data.surface
    if not surface or not surface.valid then return end
    local enemies = surface.find_entities_filtered({
        position = data.pos,
        radius = 7,
        force = 'enemy',
    })
    for _, enemy in ipairs(enemies) do
        if enemy.valid then
            show_damage_text(data.player, enemy, data.damage)
            enemy.damage(data.damage, 'player', 'explosion', data.player.character)
        end
    end
end)

-- Token: 特斯拉链式闪电弹射
local tesla_bounce_token = Token.register(function(data)
    local player = data.player
    if not player or not player.valid then return end
    if data.bounce_count >= data.max_bounces then return end

    local enemies = player.physical_surface.find_entities_filtered({
        position = data.source,
        radius = 16,
        force = 'enemy',
        type = {'unit', 'spider-unit'},
    })
    -- 过滤已攻击过的敌人
    local fresh = {}
    for _, e in ipairs(enemies) do
        if e.valid and e.health > 0 then
            local already_hit = false
            for _, hit in ipairs(data.attacked) do
                if hit == e then already_hit = true; break end
            end
            if not already_hit then
                fresh[#fresh + 1] = e
            end
        end
    end
    if #fresh == 0 then return end

    -- 随机选 2-4 个新目标
    local count = math.min(#fresh, math.random(2, 4))
    for i = #fresh, 2, -1 do local j = math.random(i); fresh[i], fresh[j] = fresh[j], fresh[i] end

    for i = 1, count do
        local enemy = fresh[i]
        if enemy and enemy.valid then
            data.attacked[#data.attacked + 1] = enemy
            -- 视觉特效
            player.physical_surface.create_entity({
                name = 'chain-tesla-turret-beam-bounce',
                position = data.source,
                force = 'enemy',
                source = data.source,
                target = enemy.position,
                duration = 30,
            })
            player.physical_surface.create_entity({
                name = 'chain-tesla-turret-beam-bounce',
                position = data.source,
                force = 'player',
                source = data.source,
                target = enemy,
                duration = 30,
            })
            -- 伤害（弹射衰减）
            local bounce_dmg = math.floor(data.base_dmg * (1 - data.bounce_count * 0.04))
            local saved_pos = enemy.position
            if bounce_dmg > 0 then
                show_damage_text(player, enemy, bounce_dmg)
                enemy.damage(bounce_dmg, 'player', 'electric', player.character)
            end
            -- 递归弹射（使用保存的位置，damage 后实体可能已死亡）
            Task.set_timeout_in_ticks(15, tesla_bounce_token, {
                player = player,
                source = saved_pos,
                bounce_count = data.bounce_count + 1,
                max_bounces = data.max_bounces,
                attacked = data.attacked,
                base_dmg = data.base_dmg,
            })
        end
    end
end)

-- Token: 雷阵雨单次雷击
local leizhenyu_strike_token = Token.register(function(data)
    local surface = data.surface
    local pos = data.position
    local player = data.player
    local damage = data.damage
    local radius = data.radius
    if not surface or not surface.valid then return end

    local enemies = surface.find_entities_filtered({
        position = pos,
        radius = radius,
        force = 'enemy',
        type = {'unit', 'spider-unit'},
    })
    if #enemies == 0 then
        -- 无敌人时随机地面雷击
        local angle = math.random() * math.pi * 2
        local dist = math.random() * radius
        surface.create_entity({
            name = 'lightning',
            position = {pos.x + math.cos(angle) * dist, pos.y + math.sin(angle) * dist - 24},
            force = 'player',
            source = player.character,
        })
        return
    end

    local target = enemies[math.random(1, #enemies)]
    if not target or not target.valid then return end

    surface.create_entity({
        name = 'lightning',
        position = {target.position.x, target.position.y - 24},
        force = 'player',
        source = player.character,
        target = target,
    })

    -- 范围内所有敌人受到伤害（距离衰减）
    for _, enemy in ipairs(enemies) do
        if enemy and enemy.valid then
            local dx = enemy.position.x - target.position.x
            local dy = enemy.position.y - target.position.y
            local dist = math.sqrt(dx * dx + dy * dy)
            local falloff = math.max(0.3, 1 - dist / radius)
            local final_dmg = math.floor(damage * falloff)
            show_damage_text(player, enemy, final_dmg)
            enemy.damage(final_dmg, 'player', 'electric', player.character)
        end
    end
end)

-- 品质顺序索引（整数 1..5，官方对照：1普通 2精良 3稀有 4史诗 5传说）
local quality_order = {'普通', '精良', '稀有', '史诗', '传说'}
-- 品质整数 → Factorio 原生 quality sprite 名
local QSPRITE = {'normal', 'uncommon', 'rare', 'epic', 'legendary'}
local function quality_index(q)
    if type(q) == 'number' then return q end
    for i, n in ipairs(quality_order) do
        if n == q then return i end
    end
    return 1
end

-- 飞行文本（仅作战中显示，位置跟随宠物 unit）
local function show_skill_text(player, pet, text, color)
    if not pet.unit or not pet.unit.valid then return end
    local pos = pet.unit.position
    player.create_local_flying_text({
        text = text,
        position = {x = pos.x, y = pos.y - 1.5},
        color = color or {r = 1, g = 1, b = 1},
        time_to_live = 60,
        speed = 1.2,
    })
end

-- 伤害飞行文本（显示在敌方单位头上，参考 tianfu.lua）
local function show_damage_text(player, target_entity, damage_amount)
    if not target_entity or not target_entity.valid then return end
    local pos = target_entity.position
    player.create_local_flying_text({
        text = tostring(math.floor(damage_amount)),
        position = {x = pos.x, y = pos.y - 1.5},
        color = {r = 1, g = 0.5, b = 0},
        time_to_live = 60,
        speed = 1.5,
    })
end

-- ============================================================
-- 技能定义表（添加新技能只需在这里注册）
-- ============================================================

local skill_defs = {}

-- 技能 1：打工人（anytime / time）
-- 每分钟给予玩家宠物等级 × 系数 的金币
skill_defs['打工人'] = {
    name = '打工人',
    category = 'anytime',
    trigger = 'time',
    quality_values = {3, 4, 5, 6, 7},  -- 普通到传说
    execute = function(player, pet, q_idx)
        local amount = pet.level * skill_defs['打工人'].quality_values[q_idx]
        if player.character and player.character.valid then
            player.insert({name = 'coin', count = amount})
        end
    end,
}

-- 技能 5：金炼（anytime / time）
-- 每分钟给予玩家宠物等级 × 系数 的经验
skill_defs['金炼'] = {
    name = '金炼',
    category = 'anytime',
    trigger = 'time',
    quality_values = {1, 2, 3, 4, 5},  -- 经验系数（普通到传说）
    execute = function(player, pet, q_idx)
        local xp = pet.level * skill_defs['金炼'].quality_values[q_idx]
        RPG.gain_xp(player, xp)
    end,
}

-- 技能 14：疯长（anytime / time）
-- 每分钟获得额外经验 = 自然成长 × 系数
skill_defs['疯长'] = {
    name = '疯长',
    category = 'anytime',
    trigger = 'time',
    quality_values = {0.6, 0.8, 1.0, 1.2, 1.4},
    execute = function(player, pet, q_idx)
        local mult = skill_defs['疯长'].quality_values[q_idx]
        local rpg_t = RPG.get_value_from_player(player.index)
        local magicka = (rpg_t and rpg_t.magicka) or 0
        local natural_xp = 5 + 10 * (magicka / 100)
        local bonus_xp = math.floor(natural_xp * mult)
        if bonus_xp > 0 then
            pet.exp = pet.exp + bonus_xp
        end
    end,
}

-- 技能 15：好战者（combat / deploy）
-- 每次出战时永久增加宠物的基础攻击力和生命值
skill_defs['好战者'] = {
    name = '好战者',
    category = 'combat',
    trigger = 'deploy',
    quality_values = {1, 1, 2, 2, 3},
    execute = function(player, pet, q_idx)
        local points = skill_defs['好战者'].quality_values[q_idx]
        pet.base_attack = pet.base_attack + points
        pet.base_hp = pet.base_hp + points
        pet.attack = pet.base_attack + pet.allocated_attack * 2
        local hp_pct = pet.hp / pet.max_hp
        local old_max = pet.max_hp
        pet.max_hp = pet.base_hp + pet.allocated_hp * 5
        pet.hp = math.ceil(pet.max_hp * hp_pct)
        show_skill_text(player, pet, ({'pet_system.skill_haozhanzhe_text', points}), {r = 1, g = 0.4, b = 0.2})
    end,
}

-- 技能 16：狂热者（combat / deploy）
-- 出场时为附近友军增加移速和回血（参考乐队鼓手 + 五行诀·水）
skill_defs['狂热者'] = {
    name = '狂热者',
    category = 'combat',
    trigger = 'deploy',
    quality_values = {1, 2, 3, 4, 5},  -- 鼓舞友军数量
    execute = function(player, pet, q_idx)
        local target_count = skill_defs['狂热者'].quality_values[q_idx]
        local pos = pet.unit.position
        local heal_amount = pet.level * 15

        local allies = player.physical_surface.find_entities_filtered({
            position = pos,
            radius = 20,
            type = 'character',
            force = 'player',
        })

        local buffed = 0
        for _, ally_char in ipairs(allies) do
            if buffed >= target_count then break end
            if not ally_char.valid then goto next_ally end
            local ally_player = ally_char.player
            if not ally_player or not ally_player.valid then goto next_ally end

            -- 治疗
            if ally_char.health then
                ally_char.health = math.min(ally_char.max_health or ally_char.health, ally_char.health + heal_amount)
            end

            -- 移速加成（10秒后恢复）
            local old_speed = ally_char.character_running_speed_modifier or 0
            ally_char.character_running_speed_modifier = old_speed + 0.3
            Task.set_timeout_in_ticks(600, remove_speed_buff_token, ally_char)

            buffed = buffed + 1
            ::next_ally::
        end

        if buffed > 0 then
            show_skill_text(player, pet, ({'pet_system.skill_kuangrezhe_text', buffed}), {r = 0.3, g = 0.8, b = 0.4})
        end
    end,
}

-- 技能 17：有丝分裂（combat / time）
-- 每 6 秒分裂召唤同名虫子，继承当前血量百分比
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

-- 技能 19：血牛（combat / deploy）
-- 出战时后台血量乘以倍数，允许临时超过最大血量
skill_defs['血牛'] = {
    name = '血牛',
    category = 'combat',
    trigger = 'deploy',
    quality_values = {1.2, 1.4, 1.6, 1.8, 2.0},
    execute = function(player, pet, q_idx)
        local mult = skill_defs['血牛'].quality_values[q_idx]
        pet.hp = math.floor(pet.hp * mult)
        show_skill_text(player, pet, ({'pet_system.skill_xueniu_text', mult}), {r = 0.8, g = 0.1, b = 0.1})
    end,
}

-- 技能 20：愤怒收割者（combat / deploy）
-- 出战时临时提升攻击力（纯临时，不叠加）
skill_defs['愤怒收割者'] = {
    name = '愤怒收割者',
    category = 'combat',
    trigger = 'deploy',
    quality_values = {1.2, 1.4, 1.6, 1.8, 2.0},
    execute = function(player, pet, q_idx)
        -- 如果已有临时加成则先还原
        if pet.temp_attack_mult then
            pet.attack = math.floor(pet.attack / pet.temp_attack_mult)
        end
        local mult = skill_defs['愤怒收割者'].quality_values[q_idx]
        pet.temp_attack_mult = mult
        pet.attack = math.floor(pet.attack * mult)
        show_skill_text(player, pet, ({'pet_system.skill_fennu_text', mult}), {r = 1, g = 0.2, b = 0.2})
    end,
}

-- 技能 22：弹幕投掷（combat / time）
-- 每 4 秒向附近敌人投掷随机弹药（不消耗），参考天赋·弹幕攻击
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

-- 技能 23：火箭发射器（combat / time）
-- 每 6 秒投掷爆裂火箭弹
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

-- 技能 24：旋风斩（combat / time）
-- 每 6 秒对 5 米内敌人造成 ATK×系数 的 AoE 伤害
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

-- 技能 25：生命汲取（combat / time）
-- 每秒对 8 米内单个敌人造成 ATK×系数 伤害，回复伤害 20%
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

-- 技能 26：金刚狼（combat / time）
-- 每 3 秒恢复已损失生命值的百分比（参考天赋·金刚狼）
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

-- 技能 21：闭关修炼（anytime / time）
-- 连续3分钟未出战，每分钟获得可分配属性点
skill_defs['闭关修炼'] = {
    name = '闭关修炼',
    category = 'anytime',
    trigger = 'time',
    quality_values = {1, 2, 3, 4, 5},
    execute = function(player, pet, q_idx)
        -- 出战中的宠物不算"闭关修炼"，必须处于休战状态
        if pet.unit and pet.unit.valid then return end
        local points = skill_defs['闭关修炼'].quality_values[q_idx]
        -- 检查是否连续 3 分钟（10800 ticks）未出战
        -- last_recall_tick 为 nil 时（从未出战），用宠物创建时间 pet.created_tick 兜底
        local last_recall = pet.last_recall_tick or pet.created_tick or 0
        if game.tick - last_recall >= 10800 then
            pet.skill_points = pet.skill_points + points
        end
    end,
}

-- 技能 13：疗愈师（anytime / time）
-- 每分钟恢复宠物最大生命值的百分比
skill_defs['疗愈师'] = {
    name = '疗愈师',
    category = 'anytime',
    trigger = 'time',
    quality_values = {6, 10, 16, 20, 24},  -- 生命值百分比（普通到传说）
    execute = function(player, pet, q_idx)
        local pct = skill_defs['疗愈师'].quality_values[q_idx]
        local heal = math.ceil(pet.max_hp * pct / 100)
        pet.hp = math.min(pet.max_hp, pet.hp + heal)
    end,
}

-- 技能 6：自给自足（anytime / time）
-- 每分钟给予玩家宠物等级 × 系数 的鱼（1鱼≈4金币）
skill_defs['自给自足'] = {
    name = '自给自足',
    category = 'anytime',
    trigger = 'time',
    quality_values = {1, 1, 2, 3, 4},  -- 鱼系数（普通到传说）
    execute = function(player, pet, q_idx)
        local fish = pet.level * skill_defs['自给自足'].quality_values[q_idx]
        if fish > 0 and player.character and player.character.valid then
            player.insert({name = 'raw-fish', count = fish})
        end
    end,
}

-- 技能 12：炮塔手（combat / deploy）
-- 出战时一次性在宠物位置放置机枪炮塔
skill_defs['炮塔手'] = {
    name = '炮塔手',
    category = 'combat',
    trigger = 'deploy',
    quality_values = {1, 2, 3, 4, 5},  -- 炮塔数量
    execute = function(player, pet, q_idx)
        local surface = player.physical_surface
        local turret_count = skill_defs['炮塔手'].quality_values[q_idx]

        -- 根据宠物等级决定子弹类型
        local ammo_name
        if pet.level < 40 then
            ammo_name = 'firearm-magazine'
        elseif pet.level < 80 then
            ammo_name = 'piercing-rounds-magazine'
        elseif pet.level < 160 then
            ammo_name = 'uranium-rounds-magazine'
        else
            ammo_name = 'uranium-rounds-magazine'
        end

        local pos = pet.unit.position
        local placed = 0
        for i = 1, turret_count do
            local offset_x = (i % 3 - 1) * 3
            local offset_y = math.floor((i - 1) / 3) * 3
            local target_pos = surface.find_non_colliding_position(
                'gun-turret', {x = pos.x + offset_x, y = pos.y + offset_y}, 2, 1, false
            )
            if target_pos then
                local turret = surface.create_entity({
                    name = 'gun-turret',
                    position = target_pos,
                    force = 'player',
                })
                if turret then
                    turret.insert({name = ammo_name, count = 200})
                    turret.destructible = false   -- 无敌
                    turret.operable = false        -- 不可操作
                    -- 12 秒后自动删除
                    Task.set_timeout_in_ticks(720, destroy_turret_token, turret)
                    placed = placed + 1
                end
            end
        end
        if placed > 0 then
            show_skill_text(player, pet, ({'pet_system.skill_paotashou_text', placed}), {r = 0.5, g = 0.5, b = 1})
        end
    end,
}

-- 技能 13：地裂（combat / time）
-- 每 12 秒在敌人脚下造成范围伤害，中心高伤、周围减半
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

-- 技能：火焰陷阱（combat / time）
-- 每 12 秒在敌人脚下喷发熔岩，持续灼烧区域
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

-- 技能：地狱熔岩（combat / time）
-- 每 6 秒对单个敌人脚下喷发火山，立刻溅射 2m + 延迟 2 秒爆发
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

-- 技能：爆裂法术（combat / time）
-- 每 6 秒随机选中多个敌人，在周围 2m 范围造成爆炸伤害
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

-- 技能：天照（combat / time）
-- 每 3 秒随机点燃敌人（fire-sticker），持续灼烧直到死亡
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

-- 技能：特斯拉蓄电池（combat / time）
-- 每 3 秒发射特斯拉链式闪电，弹射最多 10 次，无金币奖励
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

-- 技能：雷阵雨（combat / time）
-- 每隔一定时间发起多次雷击，品质影响雷击数
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

-- 技能：魔晶杖（combat / time）
-- 每 3 秒发射两道光束，分别攻击最近和最远的敌人
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

-- 技能：灵魂一指（combat / time）
-- 每 3 秒对一个敌人造成极高单体伤害
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

-- 技能：法力回流（combat / time）
-- 每 6 秒为玩家恢复施法能量（mana），数值基于宠物攻击力 × 品质系数
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

-- 技能：工兵（combat / time）
-- 每 6 秒在附近随机摆放地雷，数量由品质决定（1/1/2/2/3）
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

-- 技能：愈战愈勇（combat / time）
-- 每 15 秒永久提升宠物攻击力，品质决定提升量（1/1/2/2/3）
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

-- Token: 夜幕技能——恢复玩家可被伤害
local restore_yemu_token = Token.register(function(char)
    if char and char.valid then
        char.destructible = true
    end
end)

-- 技能：夜幕（combat / deploy）
-- 出战时为玩家施加无敌效果，持续 3/4/5/6/7 秒
skill_defs['夜幕'] = {
    name = '夜幕',
    category = 'combat',
    trigger = 'deploy',
    quality_values = {3, 4, 5, 6, 7},
    execute = function(player, pet, q_idx)
        local duration = skill_defs['夜幕'].quality_values[q_idx]
        local char = player.character
        if not char or not char.valid then return end

        -- 应用无敌
        char.destructible = false

        -- 定时恢复（使用预注册的 Token，避免运行时 Token.register 导致的错误）
        Task.set_timeout_in_ticks(duration * 60, restore_yemu_token, char)

        show_skill_text(player, pet, ({'pet_system.skill_yemu_text', duration}), {r = 0.4, g = 0.2, b = 0.6})
    end,
}

-- 技能：沙虫炮塔（combat / deploy）
-- 出战时召唤沙虫炮塔，等级与攻击力挂钩，品质决定数量（1~5）
skill_defs['沙虫炮塔'] = {
    name = '沙虫炮塔',
    category = 'combat',
    trigger = 'deploy',
    quality_values = {1, 2, 3, 4, 5},
    execute = function(player, pet, q_idx)
        local surface = player.physical_surface
        local count = skill_defs['沙虫炮塔'].quality_values[q_idx]

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
        local placed = 0
        for i = 1, count do
            local target_pos = surface.find_non_colliding_position(
                worm_name, {x = pos.x + (i - 2) * 3, y = pos.y - 3}, 3, 1, false
            )
            if target_pos then
                local worm = surface.create_entity({
                    name = worm_name,
                    position = target_pos,
                    force = player.force,
                })
                if worm then
                    worm.destructible = false
                    Task.set_timeout_in_ticks(1200, destroy_turret_token, worm)
                    placed = placed + 1
                end
            end
        end

        show_skill_text(player, pet, ({'pet_system.skill_shachongpaota_text', placed}), {r = 0.6, g = 0.4, b = 0.1})
    end,
}

-- 技能：沙虫召唤（combat / time）
-- 每 7 秒召唤一个沙虫，等级与攻击力挂钩，品质决定沙虫品质（普通~传说）
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


-- 技能：成群结队（combat / deploy）
-- 出战时召唤同名满血虫子，数量 3/4/5/6/7
skill_defs['成群结队'] = {
    name = '成群结队',
    category = 'combat',
    trigger = 'deploy',
    quality_values = {3, 4, 5, 6, 7},
    execute = function(player, pet, q_idx)
        local surface = player.physical_surface
        local count = skill_defs['成群结队'].quality_values[q_idx]

        local quality = QSPRITE[pet.quality] or 'normal'
        local pos = pet.unit.position

        local spawned = 0
        for i = 1, count do
            local target_pos = surface.find_non_colliding_position(pet.type, pos, 5, 1, false)
            if target_pos then
                local unit = surface.create_entity({
                    name = pet.type,
                    position = target_pos,
                    force = 'player',
                    quality = quality,
                })
                if unit then
                    unit.health = unit.max_health  -- 满血
                    spawned = spawned + 1
                end
            end
        end

        show_skill_text(player, pet, ({'pet_system.skill_chengqunjiedui_text', spawned}), {r = 0.8, g = 0.6, b = 0.1})
    end,
}

-- 技能：战争红利（combat / time）
-- 每 9 秒获得金币，数量基于攻击力 × 品质系数
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

-- 技能：无人机掩护（combat / time）
-- 每 9 秒召唤掩护无人机，品质与宠物相同，数量 1~3
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

-- 技能：决死冲锋（combat / deploy）
-- 出战无敌 N 秒，结束后若 18m 内有敌人则自毁，复活后重复直至 HP 归零
skill_defs['决死冲锋'] = {
    name = '决死冲锋',
    category = 'combat',
    trigger = 'deploy',
    quality_values = {3, 3.5, 4, 4.5, 5},
    execute = function(player, pet, q_idx)
        local duration = skill_defs['决死冲锋'].quality_values[q_idx]
        local unit = pet.unit
        if not unit or not unit.valid then return end

        -- 施加无敌
        unit.destructible = false
        local unit_id = unit.unit_number

        -- 找到 pet 在数组中的索引
        local pet_data = pet_table.get_player_pet_data(player)
        local pet_index = nil
        for i, p in ipairs(pet_data.pets) do
            if p == pet then pet_index = i; break end
        end
        if not pet_index then return end

        -- 定时检测（使用预注册 Token）
        Task.set_timeout_in_ticks(math.floor(duration * 60), juesi_check_token, {
            player_index = player.index,
            pet_index = pet_index,
            unit_id = unit_id,
        })

        show_skill_text(player, pet, ({'pet_system.skill_juesichongfeng_text', duration}), {r = 1, g = 0.1, b = 0})
    end,
}

-- 技能：再生（combat / time）
-- 每 6 秒恢复百分比最大生命值
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

-- 技能：荆棘（combat / owner_damaged）
-- 主人受伤时反弹攻击力百分比伤害给攻击者
skill_defs['荆棘'] = {
    name = '荆棘',
    category = 'combat',
    trigger = 'owner_damaged',
    quality_values = {10, 12.5, 15, 17.5, 20},
    execute = function(player, pet, q_idx, damage_amount, cause)
        if not cause or not cause.valid then return end
        if cause.force.name == 'player' then return end  -- 不反击友军

        local pct = skill_defs['荆棘'].quality_values[q_idx]
        local dmg = math.floor(pet.attack * pct / 100)
        if dmg <= 0 then return end

        show_damage_text(player, cause, dmg)
        cause.damage(dmg, 'player', 'physical', player.character)

        show_skill_text(player, pet, ({'pet_system.skill_jingji_text', dmg}), {r = 0.8, g = 0.2, b = 0})
    end,
}

-- 技能：环形火山（combat / time）
-- 每 12 秒在多个敌人脚下喷发火山，20% 立即灼烧 + 80% 延迟爆发
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

-- 技能：减速弹幕（combat / time）
-- 每 6 秒向 24m 内随机抛射减速胶囊，数量 2~6
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

-- 技能 2：分裂攻击（combat / time）
-- 每秒扫描 4 米内敌人，造成 atk*0.5 伤害，目标数 2~6
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

-- 技能：远程裂变（combat / time）
-- 每 3 秒扫描 18 米内敌人，造成 atk*0.5 伤害，目标数 3~7
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

-- 技能 7：炎息（combat / time）
-- 每 5 秒对 8 米内敌人造成 ATK×0.4 伤害
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

-- 技能 8：蛮力冲撞（combat / time）
-- 每 8 秒对 4 米内敌人造成 ATK×系数 伤害并击退
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

-- 技能 9：雷击（combat / time）
-- 每 4 秒连锁闪电攻击敌人，首目标 ATK×0.5，后续 ATK×0.3
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

-- 技能 10：吞噬（combat / time）
-- 每 6 秒秒杀范围内 HP<20% 的敌人，获得其当前血量×0.2 的经验
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

-- 技能 3：爆炸虫（combat / death）
-- 宠物 unit 死亡时，对 4 米内敌人造成 atk*2 伤害
skill_defs['爆炸虫'] = {
    name = '爆炸虫',
    category = 'combat',
    trigger = 'death',
    quality_values = {0.4, 0.8, 1.2, 1.6, 2.0},  -- ATK 倍数
    execute = function(player, pet, q_idx, death_position, death_surface)
        local surface = death_surface or player.physical_surface
        local pos = death_position or player.physical_position
        local mult = skill_defs['爆炸虫'].quality_values[q_idx]
        local dmg = math.floor(pet.attack * mult)

        local enemies = surface.find_entities_filtered({
            position = pos,
            radius = 4,
            force = 'enemy',
            type = {'unit', 'turret', 'unit-spawner', 'spider-unit'},
        })

        local hit_count = 0
        for _, enemy in ipairs(enemies) do
            if enemy and enemy.valid then
                show_damage_text(player, enemy, dmg)
                enemy.damage(dmg, 'player', 'explosion', player.character)
                hit_count = hit_count + 1
            end
        end
        if hit_count > 0 then
            show_skill_text(player, pet, ({'pet_system.skill_baozha_text', mult}), {r = 1, g = 0.3, b = 0.1})
        end
    end,
}

-- 技能 18：火箭弹幕（combat / death）
-- 死亡时向附近敌人发射爆裂火箭弹
skill_defs['火箭弹幕'] = {
    name = '火箭弹幕',
    category = 'combat',
    trigger = 'death',
    quality_values = {2, 4, 6, 8, 10},  -- 火箭弹数量
    execute = function(player, pet, q_idx, death_position, death_surface)
        local surface = death_surface or player.physical_surface
        local pos = death_position or player.physical_position
        local rocket_count = skill_defs['火箭弹幕'].quality_values[q_idx]

        local enemies = surface.find_entities_filtered({
            position = pos,
            radius = 18,
            force = 'enemy',
            type = {'unit', 'turret', 'unit-spawner', 'spider-unit'},
        })

        if #enemies == 0 then return end

        local fired = 0
        for i = 1, rocket_count do
            local target = enemies[math.random(1, #enemies)]
            if target and target.valid then
                surface.create_entity({
                    name = 'explosive-rocket',
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
            show_skill_text(player, pet, ({'pet_system.skill_huojiandanmu_text', fired}), {r = 1, g = 0.5, b = 0.1})
        end
    end,
}

-- 技能 4：护卫（combat / owner_damaged）
-- 玩家受伤时，宠物承担伤害 × 减免率
skill_defs['护卫'] = {
    name = '护卫',
    category = 'combat',
    trigger = 'owner_damaged',
    quality_values = {0.6, 0.7, 0.8, 0.9, 1.0},  -- 伤害吸收率
    execute = function(player, pet, q_idx, damage_amount)
        local absorb_rate = skill_defs['护卫'].quality_values[q_idx]
        local absorb = math.ceil(damage_amount * absorb_rate)
        local absorbed = math.min(absorb, pet.hp)
        pet.hp = pet.hp - absorbed
        -- 返还玩家减伤
        if player.character and player.character.valid then
            player.character.health = player.character.health + absorbed
        end
        if absorbed > 0 then
            show_skill_text(player, pet, ({'pet_system.skill_huwei_text', absorbed}), {r = 0.3, g = 0.6, b = 1})
        end
    end,
}

-- ============================================================
-- 物品价值计算与生产技能（参考 island_manager.lua）
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

-- 技能：军火商（anytime / time）
-- 每分钟随机生产3种军事岛物品，总价值由宠物攻击力×品质系数决定
-- 总价值平均分配到3个物品上（参考 island_manager 生产逻辑）
skill_defs['军火商'] = {
    name = '军火商',
    category = 'anytime',
    trigger = 'time',
    quality_values = {1.2, 1.4, 1.6, 1.8, 2.0},  -- 品质系数（普通到传说）
    execute = function(player, pet, q_idx)
        local base_value = calculate_production_base_value(pet.attack)
        local total_value = math.floor(base_value * skill_defs['军火商'].quality_values[q_idx])
        if total_value <= 0 then return end

        local items = pick_random_items(military_items, 3)
        local item_count = #items
        if item_count == 0 then return end

        local char = player.character
        if not char or not char.valid then return end

        local total_inserted = 0
        for _, item_name in ipairs(items) do
            local item_value = calculate_base_item_value(item_name)
            local count = math.floor(total_value / item_value / item_count)
            if count > 0 then
                char.insert({name = item_name, count = count})
                total_inserted = total_inserted + count
            end
        end

        if total_inserted > 0 then
            show_skill_text(player, pet, ({'pet_system.skill_junhuoshang_text', total_inserted}), {r = 0.8, g = 0.4, b = 0.2})
        end
    end,
}

-- 技能：工业家（anytime / time）
-- 每分钟随机生产3种工业岛物品，总价值由宠物攻击力×品质系数决定
-- 总价值平均分配到3个物品上（参考 island_manager 生产逻辑）
skill_defs['编织者'] = {
    name = '编织者',
    category = 'anytime',
    trigger = 'time',
    interval_ticks = 3600,
    quality_values = {3, 5, 7, 8, 10},
    execute = function(player, pet, q_idx)
        local pet_data = pet_table.get_player_pet_data(player)
        local item_name = pet_data.last_crafted_item
        if not item_name then
            -- 没有手搓物品，静默跳过（不显示文本，因为宠物可能未出战）
            return
        end

        local recipe = prototypes.recipe[item_name]
        if not recipe then
            show_skill_text(player, pet, ({'pet_system.skill_bianzhizhe_no_recipe'}), {r = 0.8, g = 0.4, b = 0.4})
            return
        end

        -- 计算合成数量 = floor(攻击力 × 0.1)，最小为1
        local count = math.floor(pet.attack * 0.1)
        if count < 1 then count = 1 end

        -- 计算配方单次产出量
        local product_amount = 1
        for _, product in pairs(recipe.products) do
            if product.name == item_name then
                product_amount = product.amount or product.amount_min or 1
                break
            end
        end

        -- 需要执行的配方次数（取整）
        local runs = math.ceil(count / product_amount)

        -- 检查材料是否充足
        for _, ingredient in pairs(recipe.ingredients) do
            if ingredient.type == 'item' then
                local required = runs * ingredient.amount
                local has = player.get_item_count(ingredient.name)
                if has < required then
                    -- 材料不足，进入冷却（由调度器自动设置冷却）
                    show_skill_text(player, pet, ({'pet_system.skill_bianzhizhe_no_material'}), {r = 0.9, g = 0.2, b = 0.4})
                    return
                end
            end
        end

        -- 消耗材料
        for _, ingredient in pairs(recipe.ingredients) do
            if ingredient.type == 'item' then
                player.remove_item({name = ingredient.name, count = runs * ingredient.amount})
            end
        end

        -- 给予产物（一次插入总量，避免重复调用）
        local total_products = runs * product_amount
        player.insert({name = item_name, count = total_products})

        -- 金币 = 最大Mana × 品质系数%
        local rpg_t = RPG.get_value_from_player(player.index)
        local mana_max = (rpg_t and rpg_t.mana_max) or 100
        local coins = math.floor(mana_max * skill_defs['编织者'].quality_values[q_idx] / 100)
        if coins > 0 then
            player.insert({name = 'coin', count = coins})
        end

        show_skill_text(player, pet, ({'pet_system.skill_bianzhizhe_text', total_products, coins}), {r = 0.3, g = 0.8, b = 0.2})
    end,
}

skill_defs['工业家'] = {
    name = '工业家',
    category = 'anytime',
    trigger = 'time',
    quality_values = {1.2, 1.4, 1.6, 1.8, 2.0},  -- 品质系数（普通到传说）
    execute = function(player, pet, q_idx)
        local base_value = calculate_production_base_value(pet.attack)
        local total_value = math.floor(base_value * skill_defs['工业家'].quality_values[q_idx])
        if total_value <= 0 then return end

        local items = pick_random_items(industrial_items, 3)
        local item_count = #items
        if item_count == 0 then return end

        local char = player.character
        if not char or not char.valid then return end

        local total_inserted = 0
        for _, item_name in ipairs(items) do
            local item_value = calculate_base_item_value(item_name)
            local count = math.floor(total_value / item_value / item_count)
            if count > 0 then
                char.insert({name = item_name, count = count})
                total_inserted = total_inserted + count
            end
        end

        if total_inserted > 0 then
            show_skill_text(player, pet, ({'pet_system.skill_gongyejia_text', total_inserted}), {r = 0.4, g = 0.6, b = 0.8})
        end
    end,
}

-- ============================================================
-- 建造者主题宠物技能（参考 tianfu.lua 建造者天赋设计）
-- ============================================================


-- 技能：科研助手（anytime / research）
-- 每次研发科技成功后，宠物获得可分配的属性点，品质决定数值（参考天赋·科研人员，但改为属性点奖励）
skill_defs['科研助手'] = {
    name = '科研助手',
    category = 'anytime',
    trigger = 'research',
    quality_values = {1, 2, 3, 4, 5},  -- 每次研发成功获得的属性点
    execute = function(player, pet, q_idx)
        local points = skill_defs['科研助手'].quality_values[q_idx]
        pet.skill_points = pet.skill_points + points
        show_skill_text(player, pet, ({'pet_system.skill_keyanzhushou_text', points}), {r = 0.3, g = 0.7, b = 1})
    end,
}

-- ============================================================
-- 宠物专属技能（不可通过技能书学习，宠物出生时自动获得）
-- exclusive_type 字段标记归属的宠物家族
-- ============================================================

-- 专属技能：虫咬（Biter 家族专属）
-- 每秒对周围4米内最多 N 个敌人造成最大生命值的5%伤害
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

-- 专属技能：吐口水（Spitter 家族专属）
-- 每3秒对附近18米内3个敌人吐口水（参考天赋·吐口水）
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

-- 专属技能：蠕虫能量（Wriggler 家族专属）
-- 每秒对附近4米内 N 个敌人造成玩家最大mana的10%附加伤害，并回复2点mana（每次命中）
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

-- 专属技能：支援光环（Strafer 家族专属）
-- 每6秒为玩家和宠物恢复最大mana的N%生命值
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

-- 专属技能：虫群召唤（Stomper 家族专属）
-- 出战时召唤15个绿虫子，品质由技能品质决定
skill_defs['虫群召唤'] = {
    name = '虫群召唤',
    category = 'combat',
    trigger = 'deploy',
    quality_values = {1, 1, 1, 1, 1},  -- 占位（实际通过 pet.quality 传品质）
    exclusive_type = 'stomper',
    execute = function(player, pet, q_idx)
        local factorio_quality = QSPRITE[q_idx] or 'normal'
        local surface = player.physical_surface
        local pos = pet.unit.position
        local summoned = 0
        for i = 1, 15 do
            local offset_x = math.random(-5, 5) * 1.0
            local offset_y = math.random(-5, 5) * 1.0
            local spawn_pos = surface.find_non_colliding_position('small-biter', {x = pos.x + offset_x, y = pos.y + offset_y}, 8, 1, false)
            if spawn_pos then
                local biter = surface.create_entity({
                    name = 'small-biter',
                    position = spawn_pos,
                    force = 'player',
                    quality = factorio_quality,
                })
                if biter then
                    biter.ai_settings.allow_try_return_to_spawner = false
                    biter.ai_settings.allow_destroy_when_commands_fail = true
                    rendering.draw_text({
                        text = '~' .. player.name .. "'s pet~",
                        surface = surface,
                        target = biter,
                        target_offset = {0, -2.6},
                        color = {r = player.color.r * 0.6 + 0.25, g = player.color.g * 0.6 + 0.25, b = player.color.b * 0.6 + 0.25, a = 1},
                        scale = 1.05,
                        font = 'default-large-semibold',
                        alignment = 'center',
                        scale_with_zoom = false,
                    })
                    summoned = summoned + 1
                end
            end
        end
        if summoned > 0 then
            show_skill_text(player, pet, ({'pet_system.skill_chongqunzhaohuan_text', summoned}), {r = 0.2, g = 1, b = 0.2})
        end
    end,
}

-- 技能：火遁（combat / time）
-- 每 12 秒从宠物位置向最近敌人喷发火焰路径 + 火环，范围火伤递减（参考 RPG 火遁术）
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

-- ============================================================
-- 技能调度器（预分类索引，O(1) 直接调用，参考天赋系统模式）
-- ============================================================

-- 按 trigger × category 预建索引（模块加载时一次性完成）
local skills_by_trigger = {}

local function ensure_trigger_category(trigger, category)
    if not skills_by_trigger[trigger] then
        skills_by_trigger[trigger] = {}
    end
    if not skills_by_trigger[trigger][category] then
        skills_by_trigger[trigger][category] = {}
    end
    return skills_by_trigger[trigger][category]
end

-- 注册技能到索引
for name, def in pairs(skill_defs) do
    local category = def.category or 'anytime'
    local index = ensure_trigger_category(def.trigger, category)
    index[name] = def
end

-- 获取宠物的可执行技能列表（返回 {name, execute=fn, q_idx=..., interval_ticks=...} 数组）
local function get_pet_skills(pet)
    local result = {}
    for _, skill_data in ipairs(pet.skills) do
        if not skill_data then goto continue end
        local skill_name, skill_quality
        if type(skill_data) == 'table' then
            skill_name = skill_data.name
            skill_quality = skill_data.quality
        else
            skill_name = skill_data
            skill_quality = 1
        end
        local def = skill_defs[skill_name]
        if def then
            result[#result + 1] = {
                name = skill_name,
                category = def.category,
                trigger = def.trigger,
                execute = def.execute,
                q_idx = quality_index(skill_quality),
                interval_ticks = def.interval_ticks or 0,
            }
        end
        ::continue::
    end
    return result
end

-- 获取所有可用技能名（全部，包括专属）
function Public.get_all_skill_names()
    local names = {}
    for name, _ in pairs(skill_defs) do
        names[#names + 1] = name
    end
    return names
end

-- 获取可通过技能书学习的技能名（排除宠物专属技能）
function Public.get_learnable_skill_names()
    local names = {}
    for name, def in pairs(skill_defs) do
        if not def.exclusive_type then
            names[#names + 1] = name
        end
    end
    return names
end

-- 从技能书随机获得一个技能（排除专属技能）
function Public.roll_skill_from_book(book_type)
    local quality = pet_table.roll_quality(book_type)
    local names = Public.get_learnable_skill_names()
    if #names == 0 then return nil end
    local skill_name = names[math.random(1, #names)]
    return {name = skill_name, quality = quality}
end

-- 调度 anytime 时间触发技能（在 on_tick 中调用，每分钟）
function Public.dispatch_anytime_time(player)
    local pet_data = pet_table.get_player_pet_data(player)

    if not pet_data.skill_cooldowns then
        pet_data.skill_cooldowns = {}
    end

    for _, pet in ipairs(pet_data.pets) do
        if pet.hp <= 0 then goto continue end
        if pet.hunger < 60 then goto continue end

        if not pet_data.skill_cooldowns[pet] then
            pet_data.skill_cooldowns[pet] = {}
        end
        local pet_cooldowns = pet_data.skill_cooldowns[pet]

        local skills = get_pet_skills(pet)
        for _, s in ipairs(skills) do
            if s.category ~= 'anytime' or s.trigger ~= 'time' then goto skip_skill end
            local last = pet_cooldowns[s.name] or 0
            if s.interval_ticks > 0 and game.tick - last < s.interval_ticks then
                goto skip_skill
            end
            s.execute(player, pet, s.q_idx)
            pet_cooldowns[s.name] = game.tick
            ::skip_skill::
        end
        ::continue::
    end
end


-- 调度 combat 时间触发技能（在 on_combat_tick 中调用，每 3 秒）
-- 通过独立冷却表保证每名玩家的技能时间精度，不受其他玩家影响
function Public.dispatch_combat_time(player)
    local pet_data = pet_table.get_player_pet_data(player)

    if not pet_data.skill_cooldowns then
        pet_data.skill_cooldowns = {}
    end

    for _, pet in ipairs(pet_data.pets) do
        if not pet.unit or not pet.unit.valid then goto continue end
        if pet.hunger < 60 then goto continue end

        if not pet_data.skill_cooldowns[pet] then
            pet_data.skill_cooldowns[pet] = {}
        end
        local pet_cooldowns = pet_data.skill_cooldowns[pet]

        local skills = get_pet_skills(pet)
        for _, s in ipairs(skills) do
            if s.category ~= 'combat' or s.trigger ~= 'time' then goto skip_skill end
            -- 检查冷却
            local last = pet_cooldowns[s.name] or 0
            if s.interval_ticks > 0 and game.tick - last < s.interval_ticks then
                goto skip_skill
            end
            -- 执行前再次检查 pet.unit 有效性
            -- （前一个技能的副作用可能导致宠物实体被销毁）
            if not pet.unit or not pet.unit.valid then goto continue end
            s.execute(player, pet, s.q_idx)
            pet_cooldowns[s.name] = game.tick
            ::skip_skill::
        end
        ::continue::
    end
end

-- 调度 combat death 触发技能（在 on_entity_died 中调用）
function Public.dispatch_death(player, pet, death_position, death_surface)
    if pet.hunger < 60 then return end
    local skills = get_pet_skills(pet)
    for _, s in ipairs(skills) do
        if s.trigger ~= 'death' then goto skip_skill end
        s.execute(player, pet, s.q_idx, death_position, death_surface)
        ::skip_skill::
    end
end

-- 调度 deploy 触发技能（宠物出战时一次性触发）
function Public.dispatch_deploy(player, pet)
    local skills = get_pet_skills(pet)
    for _, s in ipairs(skills) do
        if s.trigger ~= 'deploy' then goto skip_skill end
        s.execute(player, pet, s.q_idx)
        ::skip_skill::
    end
end

-- 调度 owner_damaged 触发技能（在 on_entity_damaged 中调用）
function Public.dispatch_owner_damaged(player, damage_amount, cause)
    local pet_data = pet_table.get_player_pet_data(player)

    if not pet_data.skill_cooldowns then
        pet_data.skill_cooldowns = {}
    end

    for _, pet in ipairs(pet_data.pets) do
        if not pet.unit or not pet.unit.valid then goto continue end
        if pet.hp <= 0 then goto continue end
        if pet.hunger < 60 then goto continue end

        if not pet_data.skill_cooldowns[pet] then
            pet_data.skill_cooldowns[pet] = {}
        end
        local pet_cooldowns = pet_data.skill_cooldowns[pet]

        local skills = get_pet_skills(pet)
        for _, s in ipairs(skills) do
            if s.trigger ~= 'owner_damaged' then goto skip_skill end
            local last = pet_cooldowns[s.name] or 0
            if s.interval_ticks > 0 and game.tick - last < s.interval_ticks then
                goto skip_skill
            end
            s.execute(player, pet, s.q_idx, damage_amount, cause)
            pet_cooldowns[s.name] = game.tick
            ::skip_skill::
        end
        ::continue::
    end
end

-- 调度 research 触发技能（在 on_research_finished 中调用）
-- 科研助手是 anytime 类别，宠物未出战时也应触发（与 dispatch_anytime_time 一致）
function Public.dispatch_research(player)
    local pet_data = pet_table.get_player_pet_data(player)
    if not pet_data or not pet_data.pets then return end

    for _, pet in ipairs(pet_data.pets) do
        if pet.hp <= 0 then goto continue end
        if pet.hunger < 60 then goto continue end

        local skills = get_pet_skills(pet)
        for _, s in ipairs(skills) do
            if s.trigger ~= 'research' then goto skip_skill end
            s.execute(player, pet, s.q_idx)
            ::skip_skill::
        end
        ::continue::
    end
end

-- 检查宠物是否有指定触发类型的技能（通过预分类索引）
function Public.has_death_skill(pet)
    for _, skill_data in ipairs(pet.skills) do
        if not skill_data then goto continue end
        local skill_name = type(skill_data) == 'table' and skill_data.name or skill_data
        if skill_name and skills_by_trigger['death'] and skills_by_trigger['death']['combat'] then
            if skills_by_trigger['death']['combat'][skill_name] then
                return true
            end
        end
        ::continue::
    end
    return false
end

-- 获取技能定义（供外部查看）
function Public.get_skill_def(name)
    return skill_defs[name]
end

-- 技能名 → locale key 后缀映射
local skill_locale_keys = {
    ['打工人']   = 'dagongren',
    ['分裂攻击'] = 'fenlie_gongji',
    ['远程裂变'] = 'yuanchengliebian',
    ['爆炸虫']   = 'baozha_chong',
    ['护卫']     = 'huwei',
    ['金炼']     = 'jinlian',
    ['自给自足'] = 'zigeizizu',
    ['炎息']     = 'yanxi',
    ['蛮力冲撞'] = 'manlichongzhuang',
    ['雷击']     = 'leiji',
    ['吞噬']     = 'tunshi',
    ['地裂']     = 'dilie',
    ['炮塔手']   = 'paotashou',
    ['疗愈师']   = 'liaoyushi',
    ['疯长']     = 'fengzhang',
    ['好战者']   = 'haozhanzhe',
    ['狂热者']   = 'kuangrezhe',
    ['有丝分裂'] = 'yousifenlie',
    ['火箭弹幕'] = 'huojiandanmu',
    ['血牛']     = 'xueniu',
    ['愤怒收割者'] = 'fennushougezhe',
    ['闭关修炼']   = 'biguanxiulian',
    ['弹幕投掷']   = 'danmutouzhi',
    ['火箭发射器'] = 'huojianfasheqi',
    ['旋风斩']     = 'xuanfengzhan',
    ['生命汲取']   = 'shengmingjiqu',
    ['金刚狼']     = 'jinganglang',
    ['火焰陷阱']     = 'huoyanxianjing',
    ['地狱熔岩']     = 'diyurongyan',
    ['爆裂法术']   = 'baoliefashu',
    ['天照']       = 'tianzhao',
    ['特斯拉蓄电池'] = 'tesila',
    ['雷阵雨']     = 'leizhenyu',
    ['魔晶杖']     = 'mojingzhang',
    ['灵魂一指']   = 'linghunyizhi',
    ['法力回流']   = 'falihuiliu',
    ['工兵']       = 'gongbing',
    ['愈战愈勇']   = 'yuzhanyuyong',
    ['夜幕']       = 'yemu',
    ['沙虫炮塔']   = 'shachongpaota',
    ['沙虫召唤']   = 'shachongzhaohuan',
    ['成群结队']   = 'chengqunjiedui',
    ['战争红利']   = 'zhanzhenghongli',
    ['无人机掩护'] = 'wurenjiyanhu',
    ['决死冲锋']   = 'juesichongfeng',
    ['再生']       = 'zaisheng',
    ['荆棘']       = 'jingji',
    ['环形火山']   = 'huanxinghuoshan',
    ['减速弹幕']   = 'jiansudanmu',
    ['军火商']     = 'junhuoshang',
    ['工业家']     = 'gongyejia',
    ['科研助手']   = 'keyanzhushou',
    ['虫咬']       = 'chongyao',
    ['吐口水']     = 'tukoushui',
    ['蠕虫能量']   = 'ruchongnengliang',
    ['支援光环']   = 'zhiyuanguanghuan',
    ['虫群召唤']   = 'chongqunzhaohuan',
    ['火遁']       = 'huodun',
    ['编织者']     = 'bianzhizhe',
}

-- 获取技能描述（返回 LocalisedString，计算实际数值）
function Public.get_skill_description(skill_name, pet, skill_quality, player)
    player = player or {index = 0}
    local def = skill_defs[skill_name]
    if not def then return nil end
    local key = skill_locale_keys[skill_name]
    if not key then return nil end

    local q_idx = quality_index(skill_quality)

    if skill_name == '打工人' then
        local coins = pet.level * def.quality_values[q_idx]
        return {'pet_system.skill_' .. key .. '_desc', coins}
    elseif skill_name == '分裂攻击' then
        local target_count = def.quality_values[q_idx]
        local dmg = math.floor(pet.attack * 0.5)
        return {'pet_system.skill_' .. key .. '_desc', target_count, dmg}
    elseif skill_name == '远程裂变' then
        local target_count = def.quality_values[q_idx]
        local dmg = math.floor(pet.attack * 0.5)
        return {'pet_system.skill_' .. key .. '_desc', target_count, dmg}
    elseif skill_name == '爆炸虫' then
        local dmg = math.floor(pet.attack * def.quality_values[q_idx])
        return {'pet_system.skill_' .. key .. '_desc', dmg}
    elseif skill_name == '护卫' then
        local absorb = def.quality_values[q_idx] * 100
        return {'pet_system.skill_' .. key .. '_desc', absorb}
    elseif skill_name == '金炼' then
        local xp = pet.level * def.quality_values[q_idx]
        return {'pet_system.skill_' .. key .. '_desc', xp}
    elseif skill_name == '自给自足' then
        local fish = pet.level * def.quality_values[q_idx]
        return {'pet_system.skill_' .. key .. '_desc', fish}
    elseif skill_name == '炎息' then
        local targets = def.quality_values[q_idx]
        local dmg = math.floor(pet.attack * 0.4)
        return {'pet_system.skill_' .. key .. '_desc', targets, dmg}
    elseif skill_name == '蛮力冲撞' then
        local dmg = math.floor(pet.attack * def.quality_values[q_idx])
        return {'pet_system.skill_' .. key .. '_desc', dmg}
    elseif skill_name == '雷击' then
        local chains = def.quality_values[q_idx]
        local dmg = math.floor(pet.attack * 0.5)
        return {'pet_system.skill_' .. key .. '_desc', chains, dmg}
    elseif skill_name == '吞噬' then
        local kills = def.quality_values[q_idx]
        return {'pet_system.skill_' .. key .. '_desc', kills}
    elseif skill_name == '地裂' then
        local dmg = math.floor(pet.attack * def.quality_values[q_idx])
        return {'pet_system.skill_' .. key .. '_desc', dmg}
    elseif skill_name == '炮塔手' then
        local turrets = def.quality_values[q_idx]
        return {'pet_system.skill_' .. key .. '_desc', turrets}
    elseif skill_name == '疗愈师' then
        local pct = def.quality_values[q_idx]
        local heal = math.ceil(pet.max_hp * pct / 100)
        return {'pet_system.skill_' .. key .. '_desc', heal}
    elseif skill_name == '疯长' then
        local rpg_t = RPG.get_value_from_player(player.index)
        local magicka = (rpg_t and rpg_t.magicka) or 0
        local natural_xp = 5 + 10 * (magicka / 100)
        local bonus_xp = math.floor(natural_xp * def.quality_values[q_idx])
        return {'pet_system.skill_' .. key .. '_desc', bonus_xp}
    elseif skill_name == '好战者' then
        local points = def.quality_values[q_idx]
        return {'pet_system.skill_' .. key .. '_desc', points}
    elseif skill_name == '狂热者' then
        local allies = def.quality_values[q_idx]
        local heal = pet.level * 9
        return {'pet_system.skill_' .. key .. '_desc', allies, heal}
    elseif skill_name == '有丝分裂' then
        local pct = def.quality_values[q_idx]
        local hp = math.floor(pet.hp * pct / 100)
        return {'pet_system.skill_' .. key .. '_desc', pct, hp}
    elseif skill_name == '火箭弹幕' then
        local rockets = def.quality_values[q_idx]
        return {'pet_system.skill_' .. key .. '_desc', rockets}
    elseif skill_name == '血牛' then
        local mult = def.quality_values[q_idx]
        local new_hp = math.floor(pet.hp * mult)
        return {'pet_system.skill_' .. key .. '_desc', mult, new_hp}
    elseif skill_name == '愤怒收割者' then
        local mult = def.quality_values[q_idx]
        local new_atk = math.floor(pet.attack * mult)
        return {'pet_system.skill_' .. key .. '_desc', mult, new_atk}
    elseif skill_name == '闭关修炼' then
        local points = def.quality_values[q_idx]
        return {'pet_system.skill_' .. key .. '_desc', points}
    elseif skill_name == '弹幕投掷' then
        local throws = def.quality_values[q_idx]
        return {'pet_system.skill_' .. key .. '_desc', throws}
    elseif skill_name == '火箭发射器' then
        local rockets = def.quality_values[q_idx]
        return {'pet_system.skill_' .. key .. '_desc', rockets}
    elseif skill_name == '旋风斩' then
        local dmg = math.floor(pet.attack * def.quality_values[q_idx])
        return {'pet_system.skill_' .. key .. '_desc', dmg}
    elseif skill_name == '生命汲取' then
        local dmg = math.floor(pet.attack * def.quality_values[q_idx])
        local heal = math.ceil(dmg * 0.2)
        return {'pet_system.skill_' .. key .. '_desc', dmg, heal}
    elseif skill_name == '金刚狼' then
        local pct = def.quality_values[q_idx]
        local heal = math.ceil((pet.max_hp - pet.hp) * pct / 100)
        return {'pet_system.skill_' .. key .. '_desc', pct, heal}
    elseif skill_name == '火焰陷阱' then
        local duration = def.quality_values[q_idx]
        local dmg = math.floor(pet.attack * 0.3)
        return {'pet_system.skill_' .. key .. '_desc', duration, dmg}
    elseif skill_name == '地狱熔岩' then
        local dmg = math.floor(pet.attack * def.quality_values[q_idx] * 0.3)
        return {'pet_system.skill_' .. key .. '_desc', dmg}
    elseif skill_name == '爆裂法术' then
        local targets = def.quality_values[q_idx]
        local dmg = math.floor(pet.attack * 0.6)
        return {'pet_system.skill_' .. key .. '_desc', targets, dmg}
    elseif skill_name == '天照' then
        local count = def.quality_values[q_idx]
        return {'pet_system.skill_' .. key .. '_desc', count}
    elseif skill_name == '特斯拉蓄电池' then
        local dmg = math.floor(pet.attack * def.quality_values[q_idx])
        return {'pet_system.skill_' .. key .. '_desc', dmg}
    elseif skill_name == '雷阵雨' then
        local strikes = def.quality_values[q_idx]
        local dmg = math.floor(pet.attack * 1.2)
        return {'pet_system.skill_' .. key .. '_desc', strikes, dmg, 6 + math.floor(q_idx * 0.5)}
    elseif skill_name == '魔晶杖' then
        local dmg = math.floor(pet.attack * def.quality_values[q_idx])
        return {'pet_system.skill_' .. key .. '_desc', dmg}
    elseif skill_name == '灵魂一指' then
        local dmg = math.floor(pet.attack * def.quality_values[q_idx])
        return {'pet_system.skill_' .. key .. '_desc', dmg}
    elseif skill_name == '法力回流' then
        local mana = math.floor(pet.attack * def.quality_values[q_idx])
        return {'pet_system.skill_' .. key .. '_desc', mana}
    elseif skill_name == '工兵' then
        local count = def.quality_values[q_idx]
        return {'pet_system.skill_' .. key .. '_desc', count}
    elseif skill_name == '愈战愈勇' then
        local gain = def.quality_values[q_idx]
        return {'pet_system.skill_' .. key .. '_desc', gain}
    elseif skill_name == '夜幕' then
        local duration = def.quality_values[q_idx]
        return {'pet_system.skill_' .. key .. '_desc', duration}
    elseif skill_name == '沙虫炮塔' then
        local count = def.quality_values[q_idx]
        return {'pet_system.skill_' .. key .. '_desc', count}
    elseif skill_name == '沙虫召唤' then
        local q_val = def.quality_values[q_idx]
        return {'pet_system.skill_' .. key .. '_desc', {'pet_system.quality_' .. (q_val or 1)}}
    elseif skill_name == '成群结队' then
        local count = def.quality_values[q_idx]
        return {'pet_system.skill_' .. key .. '_desc', count}
    elseif skill_name == '战争红利' then
        local coins = math.floor(pet.attack * def.quality_values[q_idx])
        return {'pet_system.skill_' .. key .. '_desc', coins}
    elseif skill_name == '无人机掩护' then
        local count = def.quality_values[q_idx]
        return {'pet_system.skill_' .. key .. '_desc', count}
    elseif skill_name == '决死冲锋' then
        local duration = def.quality_values[q_idx]
        return {'pet_system.skill_' .. key .. '_desc', duration}
    elseif skill_name == '再生' then
        local pct = def.quality_values[q_idx]
        local heal = math.ceil(pet.max_hp * pct / 100)
        return {'pet_system.skill_' .. key .. '_desc', pct, heal}
    elseif skill_name == '荆棘' then
        local pct = def.quality_values[q_idx]
        local dmg = math.floor(pet.attack * pct / 100)
        return {'pet_system.skill_' .. key .. '_desc', pct, dmg}
    elseif skill_name == '环形火山' then
        local target_count = def.quality_values[q_idx]
        local dmg = math.floor(pet.attack * 1.5 * 0.2)
        return {'pet_system.skill_' .. key .. '_desc', target_count, dmg}
    elseif skill_name == '减速弹幕' then
        local count = def.quality_values[q_idx]
        return {'pet_system.skill_' .. key .. '_desc', count}
    elseif skill_name == '军火商' then
        local mult = def.quality_values[q_idx]
        return {'pet_system.skill_' .. key .. '_desc', mult}
    elseif skill_name == '工业家' then
        local mult = def.quality_values[q_idx]
        return {'pet_system.skill_' .. key .. '_desc', mult}
    elseif skill_name == '科研助手' then
        local points = def.quality_values[q_idx]
        return {'pet_system.skill_' .. key .. '_desc', points}
    elseif skill_name == '虫咬' then
        local targets = def.quality_values[q_idx]
        local dmg_pct = 5
        return {'pet_system.skill_' .. key .. '_desc', targets, dmg_pct}
    elseif skill_name == '吐口水' then
        return {'pet_system.skill_' .. key .. '_desc'}
    elseif skill_name == '蠕虫能量' then
        local targets = def.quality_values[q_idx]
        return {'pet_system.skill_' .. key .. '_desc', targets, 10}
    elseif skill_name == '支援光环' then
        local pct = def.quality_values[q_idx]
        return {'pet_system.skill_' .. key .. '_desc', pct}
    elseif skill_name == '虫群召唤' then
        return {'pet_system.skill_' .. key .. '_desc'}
    elseif skill_name == '火遁' then
        local dmg = math.floor(pet.attack * def.quality_values[q_idx])
        local min_dmg = math.floor(dmg * 0.3)
        return {'pet_system.skill_' .. key .. '_desc', dmg, min_dmg}
    elseif skill_name == '编织者' then
        local rpg_t = RPG.get_value_from_player(player.index)
        local mana_max = (rpg_t and rpg_t.mana_max) or 100
        local coins = math.floor(mana_max * def.quality_values[q_idx] / 100)
        local count = math.floor(pet.attack * 0.1)
        if count < 1 then count = 1 end
        local pct = def.quality_values[q_idx]
        return {'pet_system.skill_' .. key .. '_desc', count, coins, pct}
    end
    return nil
end

-- 获取技能显示名称（返回 LocalisedString）
function Public.get_skill_display_name(name)
    local key = skill_locale_keys[name]
    if not key then return name end
    return {'pet_system.skill_' .. key}
end

-- ============================================================
-- 宠物专属技能分配
-- ============================================================

-- 根据宠物类型名判断所属家族
-- 返回: 'biter' / 'spitter' / 'wriggler' / 'strafer' / 'stomper' 或 nil
local function get_pet_family(type_name)
    if type_name:find('biter') and not type_name:find('pentapod') then
        return 'biter'
    elseif type_name:find('spitter') then
        return 'spitter'
    elseif type_name:find('wriggler') then
        return 'wriggler'
    elseif type_name:find('strafer') then
        return 'strafer'
    elseif type_name:find('stomper') then
        return 'stomper'
    end
    return nil
end

-- 专属技能名映射（family → skill_name）
local exclusive_skill_map = {
    biter    = '虫咬',
    spitter  = '吐口水',
    wriggler = '蠕虫能量',
    strafer  = '支援光环',
    stomper  = '虫群召唤',
}

-- 给宠物分配专属技能（在宠物创建时调用）
-- 将专属技能放在技能槽第1位，品质等于宠物品质
function Public.assign_exclusive_skill(pet)
    local family = get_pet_family(pet.type)
    if not family then return false end
    local skill_name = exclusive_skill_map[family]
    if not skill_name then return false end
    pet.skills[1] = {name = skill_name, quality = pet.quality}
    return true
end

return Public
