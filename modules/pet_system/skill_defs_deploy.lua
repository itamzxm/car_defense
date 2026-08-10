-- ============================================================
-- deploy 技能定义（从 skills.lua 拆分，逐字保留，勿手改逻辑）
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
                        text = {'amap.pet_label', player.name},
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
end
