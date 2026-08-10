-- ============================================================
-- event 技能定义（从 skills.lua 拆分，逐字保留，勿手改逻辑）
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
end
