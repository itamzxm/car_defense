-- ============================================================
-- 宠物技能辅助（从 skills.lua 拆分）：Token + 文本显示函数
-- 供 skill_defs_*.lua 定义文件引用（Helpers.QSPRITE 等）
-- 注意：quality_index 实际定义在 skills.lua（调度器 get_pet_skills 与
-- get_skill_description 均在本文件之外调用），本文件下方同名函数为
-- 历史残留（local，无引用），请勿在新增代码中依赖。
-- ============================================================

local Token = require 'utils.token'
local Task = require 'utils.task'
local pet_table = require 'modules.pet_system.table'
local Public = {}

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

-- Token: 夜幕技能——恢复玩家可被伤害
local restore_yemu_token = Token.register(function(char)
    if char and char.valid then
        char.destructible = true
    end
end)

Public.destroy_turret_token = destroy_turret_token
Public.juesi_check_token = juesi_check_token
Public.remove_speed_buff_token = remove_speed_buff_token
Public.active_lava_burst_token = active_lava_burst_token
Public.tesla_bounce_token = tesla_bounce_token
Public.leizhenyu_strike_token = leizhenyu_strike_token
Public.restore_yemu_token = restore_yemu_token
Public.QSPRITE = QSPRITE
Public.show_skill_text = show_skill_text
Public.show_damage_text = show_damage_text

return Public
