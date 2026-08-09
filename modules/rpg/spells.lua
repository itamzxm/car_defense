-- spells.lua
-- 魔法技能模块：技能数据 + 升级系统 + 技能实现函数 + 调度 handlers
-- 添加新魔法技能只需修改本文件：
--   1. 在 conjure_items() 末尾添加技能数据
--   2. 在 itam_spell 表登记升级参数（连续升级可留空表 {}，用默认值）
--   3. 编写 Public.技能ID(position, surface, player, times) 函数
--   4. 在 handlers 表注册 handler
--   5. 同步 locale/zh-CN/rpg.cfg 和 locale/en/rpg.cfg

local Public = {}

-- 顶层 require（非 rpg 模块，无循环依赖）
local Task = require 'utils.task'
local Token = require 'utils.token'
local WPT = require 'maps.amap.table'
local BiterPets = require 'maps.amap.biter_pets'
local EntityCache = require 'maps.amap.entity_cache'
local P = require 'player_modifiers'

-- 因循环依赖（table.lua 顶层 require spells.lua），spells.lua 不能在顶层 require 'modules.rpg.table'
-- 使用懒加载：在使用 RPG 的函数内部首次调用时 require（require 会缓存，无性能问题）
local RPG

-- 辅助常量（为避免与 functions.lua 循环依赖，此处独立定义）
local COEFF_REG = {1, 1.2, 1.4, 1.6, 1.8}
local goal = {'unit', 'turret', 'unit-spawner', 'combat-robot', 'spider-leg', 'spider-unit'}

-- 虫子价值表（ch 函数用）
local t = {
    ['small-biter'] = 1,
    ['small-spitter'] = 2,
    ['small-worm-turret'] = 32,
    ['medium-biter'] = 8,
    ['medium-spitter'] = 8,
    ['medium-worm-turret'] = 64,
    ['big-biter'] = 32,
    ['big-spitter'] = 32,
    ['big-worm-turret'] = 128,
    ['behemoth-biter'] = 128,
    ['behemoth-spitter'] = 128,
    ['behemoth-worm-turret'] = 256,
    ['biter-spawner'] = 320,
    ['spitter-spawner'] = 320,
}

-- biter_special_forces 的虫子阶层映射
local biter_list = {
    ['1'] = 'small-biter',
    ['2'] = 'medium-biter',
    ['3'] = 'big-biter',
    ['4'] = 'behemoth-biter',
}
local spitter_list = {
    ['1'] = 'small-spitter',
    ['2'] = 'medium-spitter',
    ['3'] = 'big-spitter',
    ['4'] = 'behemoth-spitter',
}
local shachong_list = {
    ['1'] = 'small-worm-turret',
    ['2'] = 'medium-worm-turret',
    ['3'] = 'big-worm-turret',
    ['4'] = 'behemoth-worm-turret',
}

-- 辅助函数
local function create_damage_floating_text(target_entity, damage_amount, damage_type, player)
    local color = {r = 1, g = 0.5, b = 0}
    local text_position = {
        x = target_entity.position.x,
        y = target_entity.position.y - 1.5
    }
    player.create_local_flying_text({
        text = tostring(math.floor(damage_amount)),
        position = text_position,
        color = color,
        time_to_live = 60,
        speed = 1.5
    })
end

local function deal_damage_with_floating_text(target_entity, player, damage_amount, damage_type)
    if type(damage_amount) ~= 'number' or damage_amount <= 0 then
        return false
    end
    if not target_entity or not target_entity.valid then
        return false
    end
    local this = WPT.get()
    local damage_multiplier = this.damage_multiplier or 1
    local final_damage = math.floor(damage_amount * damage_multiplier * 1.2)
    damage_type = damage_type or 'explosion'
    create_damage_floating_text(target_entity, final_damage, damage_type, player)
    target_entity.damage(final_damage, 'player', damage_type, player.character)
    return true
end

local function unstuck_player(index)
    local player = game.get_player(index)
    local surface = player.physical_surface
    if player.physical_surface.name ~= 'nauvis' then return end
    local position = surface.find_non_colliding_position('character', player.physical_position, 32, 0.5)
    if not position then return end
    player.teleport(position, surface)
end

local function tame_unit_effects(player, entity)
    rendering.draw_text {
        text = {'amap.pet_label', player.name},
        surface = player.physical_surface,
        target = entity,
        target_offset = {0, -2.6},
        color = {
            r = player.color.r * 0.6 + 0.25,
            g = player.color.g * 0.6 + 0.25,
            b = player.color.b * 0.6 + 0.25,
            a = 1
        },
        scale = 1.05,
        font = 'default-large-semibold',
        alignment = 'center',
        scale_with_zoom = false
    }
end

-- Token 定义
-- 疾跑移速加成超时：精确移除 jx 分类加成并刷写 modifier
local jx_timeout = Token.register(function(player)
    P.update_single_modifier(player, 'character_running_speed_modifier', 'jx', 0)
    P.update_player_modifiers(player)
end)

local jgq_work = Token.register(function(player)
    local entities = EntityCache.find_entities_cached(player.physical_surface, {
        position = player.physical_position,
        type = goal,
        radius = 16,
        force = game.forces.enemy,
        limit = 20
    })
    for i = 1, 5, 1 do
        if #entities ~= 0 and i <= #entities then
            local e = player.physical_surface.create_entity({
                name = 'laser',
                position = player.physical_position,
                force = 'player',
                source = player.character,
                target = entities[i],
                speed = 1,
                player = player
            })
        end
    end
end)

local kill_forces = Token.register(function(data)
    for _, v in pairs(data) do
        if v and v.valid then
            v.destroy()
        end
    end
end)

local kill_turret = Token.register(function(data)
    local entity = data.entity
    if not entity or not entity.valid then return end
    entity.destroy()
end)

local active_lava_burst_task = Token.register(function(data)
    local surface = data.surface
    local pos = data.pos
    local player = data.player
    local damage = data.damage
    if surface and surface.valid then
        local area_enemies = surface.find_entities_filtered {
            position = pos,
            radius = 7,
            force = game.forces.enemy
        }
        for _, enemy in pairs(area_enemies) do
            if enemy.valid then
                deal_damage_with_floating_text(enemy, player, damage, 'explosion')
            end
        end
    end
end)

local leizhenyu_work = Token.register(function(data)
    local surface = data.surface
    local position = data.position
    local player = data.player
    local damage = data.damage
    local radius = data.radius
    if not surface or not surface.valid then return end
    local enemies = surface.find_entities_filtered({
        position = position,
        radius = radius,
        force = 'enemy',
        type = goal
    })
    local strike_position
    if #enemies > 0 then
        local target = enemies[math.random(1, #enemies)]
        if target and target.valid then
            strike_position = target.position
            surface.create_entity({
                name = 'lightning',
                position = {x = strike_position.x, y = strike_position.y - 24},
                force = 'player',
                source = player.character,
                target = target,
                speed = 1.0
            })
            for _, enemy in pairs(enemies) do
                local distance_from_center = math.sqrt(
                    (enemy.position.x - strike_position.x)^2 + (enemy.position.y - strike_position.y)^2
                )
                local damage_distance_modifier = math.max(0.3, 1 - distance_from_center / radius)
                local final_damage = damage * damage_distance_modifier
                deal_damage_with_floating_text(enemy, player, final_damage, 'electric')
            end
        end
    else
        local angle = math.random() * math.pi * 2
        local distance = math.random() * radius
        strike_position = {
            x = position.x + math.cos(angle) * distance,
            y = position.y + math.sin(angle) * distance
        }
        surface.create_entity({
            name = 'lightning',
            position = {x = strike_position.x, y = strike_position.y - 24},
            force = 'player',
            source = player.character,
            speed = 1.0
        })
    end
end)

local diankuang_self_loss_token = Token.register(function(data)
    local player = data.player
    if not player or not player.valid then return end
    if not player.character or not player.character.valid then return end
    
    local rpg_t = RPG.get_value_from_player(player.index)
    if not rpg_t then return end
    local hp_loss = player.character.max_health * 0.05
    player.character.health = player.character.health - hp_loss
    local mana_loss = math.floor(rpg_t.mana_max * 0.05)
    RPG.remove_mana(player, mana_loss)
    RPG.update_health(player)
    RPG.update_mana(player)
end)

local diankuang_burst_token = Token.register(function(data)
    local player = data.player
    local surface = data.surface
    local position = data.position
    local max_health = data.max_health
    local mana_max = data.mana_max
    local times = data.times
    if not player or not player.valid then return end
    if not player.character or not player.character.valid then return end
    if not surface or not surface.valid then return end
    if not position then return end
    
    local rpg_t = RPG.get_value_from_player(player.index)
    if not rpg_t then return end
    local laser_bonus = game.forces.player.get_ammo_damage_modifier("laser") + 1
    local speed_bonus = game.forces.player.get_gun_speed_modifier('laser') + 1
    local magicka_bonus = rpg_t.magicka or 0
    local q_idx = 1
    local level = times or 1
    if level > 80 then level = 80 end
    local base_damage = 0.2 * (max_health + mana_max)
    local damage = math.floor(base_damage * level * laser_bonus * speed_bonus * COEFF_REG[q_idx] + magicka_bonus)
    local entities = EntityCache.find_entities_cached(surface, {
        position = position,
        radius = 8,
        force = 'enemy',
        type = goal
    })
    for _, entity in pairs(entities) do
        if entity and entity.valid then
            deal_damage_with_floating_text(entity, player, damage, 'laser')
        end
    end
    surface.create_entity({
        name = 'electric-beam',
        position = player.physical_position,
        source = player.physical_position,
        target = position,
        duration = 25
    })
end)

-- ============================================
-- 技能数据（conjure_items）
-- ============================================
function Public.conjure_items()
    local spells = {}

    spells[#spells + 1] = {
        name = {'entity-name.express-transport-belt'},
        entityName = 'express-transport-belt',
        level = 45,
        type = 'item',
        mana_cost = 150,
        tick = 300,
        enabled = true,
        sprite = 'recipe/express-transport-belt'
    }
    spells[#spells + 1] = {
        name = {'entity-name.express-underground-belt'},
        entityName = 'express-underground-belt',
        level = 40,
        type = 'item',
        mana_cost = 200,
        tick = 300,
        enabled = true,
        sprite = 'recipe/express-underground-belt'
    }
    spells[#spells + 1] = {
        name = {'entity-name.big-sand-rock'},
        entityName = 'big-sand-rock',
        level = 60,
        type = 'entity',
        mana_cost = 100,
        tick = 350,
        enabled = false,
        sprite = 'entity/big-sand-rock'
    }
    spells[#spells + 1] = {
        name = {'entity-name.small-biter'},
        entityName = 'small-biter',
        level = 10,
        biter = true,
        type = 'entity',
        mana_cost = 45,
        tick = 200,
        enabled = false,
        sprite = 'entity/small-biter'
    }
    spells[#spells + 1] = {
        name = {'entity-name.small-spitter'},
        entityName = 'small-spitter',
        level = 10,
        biter = true,
        type = 'entity',
        mana_cost = 45,
        tick = 200,
        enabled = false,
        sprite = 'entity/small-spitter'
    }
    spells[#spells + 1] = {
        name = {'entity-name.medium-biter'},
        entityName = 'medium-biter',
        level = 35,
        biter = true,
        type = 'entity',
        mana_cost = 75,
        tick = 300,
        enabled = false,
        sprite = 'entity/medium-biter'
    }
    spells[#spells + 1] = {
        name = {'entity-name.medium-spitter'},
        entityName = 'medium-spitter',
        level = 35,
        biter = true,
        type = 'entity',
        mana_cost = 75,
        tick = 300,
        enabled = false,
        sprite = 'entity/medium-spitter'
    }
    spells[#spells + 1] = {
        name = {'entity-name.big-biter'},
        entityName = 'big-biter',
        level = 50,
        biter = true,
        type = 'entity',
        mana_cost = 120,
        tick = 300,
        enabled = false,
        sprite = 'entity/big-biter'
    }
    spells[#spells + 1] = {
        name = {'entity-name.big-spitter'},
        entityName = 'big-spitter',
        level = 50,
        biter = true,
        type = 'entity',
        mana_cost = 120,
        tick = 300,
        enabled = false,
        sprite = 'entity/big-spitter'
    }
    spells[#spells + 1] = {
        name = {'entity-name.behemoth-biter'},
        entityName = 'behemoth-biter',
        level = 80,
        biter = true,
        type = 'entity',
        mana_cost = 200,
        tick = 300,
        enabled = false,
        sprite = 'entity/behemoth-biter'
    }
    spells[#spells + 1] = {
        name = {'entity-name.behemoth-spitter'},
        entityName = 'behemoth-spitter',
        level = 80,
        biter = true,
        type = 'entity',
        mana_cost = 200,
        tick = 300,
        enabled = false,
        sprite = 'entity/behemoth-spitter'
    }
    spells[#spells + 1] = {
        name = {'entity-name.small-worm-turret'},
        entityName = 'small-worm-turret',
        level = 35,
        biter = true,
        type = 'entity',
        mana_cost = 200,
        tick = 300,
        enabled = true,
        sprite = 'entity/small-worm-turret'
    }
    spells[#spells + 1] = {
        name = {'entity-name.medium-worm-turret'},
        entityName = 'medium-worm-turret',
        level = 50,
        biter = true,
        type = 'entity',
        mana_cost = 300,
        tick = 300,
        enabled = true,
        sprite = 'entity/medium-worm-turret'
    }
    spells[#spells + 1] = {
        name = {'entity-name.big-worm-turret'},
        entityName = 'big-worm-turret',
        level = 80,
        biter = true,
        type = 'entity',
        mana_cost = 450,
        tick = 300,
        enabled = true,
        sprite = 'entity/big-worm-turret'
    }
    spells[#spells + 1] = {
        name = {'entity-name.behemoth-worm-turret'},
        entityName = 'behemoth-worm-turret',
        level = 120,
        biter = true,
        type = 'entity',
        mana_cost = 700,
        tick = 300,
        enabled = true,
        sprite = 'entity/behemoth-worm-turret'
    }
    spells[#spells + 1] = {
        name = {'entity-name.biter-spawner'},
        entityName = 'biter-spawner',
        level = 90,
        biter = true,
        type = 'entity',
        mana_cost = 500,
        tick = 1420,
        enabled = true,
        sprite = 'entity/biter-spawner'
    }
    spells[#spells + 1] = {
        name = {'entity-name.spitter-spawner'},
        entityName = 'spitter-spawner',
        level = 90,
        biter = true,
        type = 'entity',
        mana_cost = 500,
        tick = 1420,
        enabled = true,
        sprite = 'entity/spitter-spawner'
    }

    spells[#spells + 1] = {
        name = {'item-name.slowdown-capsule'},
        entityName = 'slowdown-capsule',
        target = true,
        amount = 1,
        damage = true,
        force = 'player',
        level = 25,
        type = 'item',
        mana_cost = 175,
        tick = 150,
        enabled = true,
        sprite = 'recipe/slowdown-capsule'
    }
    spells[#spells + 1] = {
        name = {'item-name.grenade'},
        entityName = 'grenade',
        target = true,
        amount = 1,
        damage = true,
        force = 'player',
        level = 10,
        type = 'item',
        mana_cost = 50,
        tick = 50,
        enabled = true,
        sprite = 'recipe/grenade'
    }
    spells[#spells + 1] = {
        name = {'item-name.cluster-grenade'},
        entityName = 'cluster-grenade',
        target = true,
        amount = 2,
        damage = true,
        force = 'player',
        level = 30,
        type = 'item',
        mana_cost = 250,
        tick = 200,
        enabled = true,
        sprite = 'recipe/cluster-grenade'
    }
    spells[#spells + 1] = {
        name = {'spells.repair_aoe'},
        entityName = 'repair_aoe',
        target = true,
        amount = 1,
        range = 50,
        damage = false,
        force = 'player',
        level = 45,
        type = 'special',
        mana_cost = 150,
        tick = 100,
        enabled = true,
        sprite = 'recipe/repair-pack'
    }
    spells[#spells + 1] = {
        name = {'spells.raw_fish'},
        entityName = 'raw-fish',
        target = false,
        amount = 4,
        capsule = true,
        damage = false,
        range = 30,
        force = 'player',
        level = 10,
        type = 'special',
        mana_cost = 100,
        tick = 320,
        enabled = true,
        sprite = 'item/raw-fish'
    }

    spells[#spells + 1] = {
        name = {'spells.warp'},
        entityName = 'warp-gate',
        target = true,
        force = 'player',
        level = 45,
        type = 'special',
        mana_cost = 400,
        tick = 2000,
        enabled = true,
        sprite = 'virtual-signal/signal-W'
    }
    spells[#spells + 1] = {
        name = {'spells.wudi_turret'},
        itam_code=true,
        entityName = 'wudi_turret',
        insert='firearm-magazine',
        target = true,
        force = 'player',
        level = 35,
        type = 'special',
        mana_cost = 200,
        tick = 100,
        enabled = true,
        sprite = 'recipe/gun-turret'
    }
    spells[#spells + 1] = {
        name = {'spells.biter_special_forces'},
        itam_code=true,
        entityName = 'biter_special_forces',
        target = true,
        force = 'player',
        level = 50,
        type = 'special',
        mana_cost = 250,
        tick = 100,
        enabled = true,
        sprite = 'item/submachine-gun'
    }

    spells[#spells + 1] = {
        name = {'spells.jgq'},
        itam_code=true,
        entityName = 'jgq',
        target = true,
        force = 'player',
        level = 15,
        type = 'special',
        mana_cost = 100,
        tick = 100,
        enabled = true,
        sprite = 'virtual-signal/signal-B'
    }
    spells[#spells + 1] = {
        name = {'spells.ufo'},
        itam_code=true,
        entityName = 'ufo',
        target = true,
        force = 'player',
        level = 100,
        type = 'special',
        mana_cost = 750,
        tick = 100,
        enabled = true,
        sprite = 'virtual-signal/signal-C'
    }
    spells[#spells + 1] = {
        name = {'spells.lightning_chain'},
        itam_code=true,
        entityName = 'lightning_chain',
        target = true,
        force = 'player',
        level = 30,
        type = 'special',
        mana_cost = 200,
        tick = 100,
        enabled = true,
        sprite = 'virtual-signal/signal-L'
    }
    spells[#spells + 1] = {
        name = {'spells.jx'},
        itam_code=true,
        entityName = 'jx',
        target = true,
        force = 'player',
        level = 30,
        type = 'special',
        mana_cost = 350,
        tick = 100,
        enabled = true,
        sprite = 'item/exoskeleton-equipment'
    }
    spells[#spells + 1] = {
        name = {'spells.lyly'},
        itam_code=true,
        entityName = 'lyly',
        target = true,
        force = 'player',
        level = 35,
        type = 'special',
        mana_cost = 75,
        tick = 100,
        enabled = false,
        sprite = 'item/flamethrower-ammo'
    }
    spells[#spells + 1] = {
        name = {'spells.ssz'},
        itam_code=true,
        entityName = 'ssz',
        target = true,
        force = 'player',
        level = 30,
        type = 'special',
        mana_cost = 200,
        tick = 100,
        enabled = true,
        sprite = 'recipe/stone-wall'
    }
    spells[#spells + 1] = {
        name = {'spells.distractor'},
        entityName = 'distractor-capsule',
        target = true,
        amount = 1,
        damage = false,
        range = 30,
        force = 'player',
        level = 25,
        type = 'special',
        mana_cost = 125,
        tick = 320,
        enabled = true,
        sprite = 'recipe/distractor-capsule'
    }
    spells[#spells + 1] = {
        name = {'item-name.atomic-bomb'},
        entityName = 'atomic-bomb',
        range = 64,
        target = true,
        amount = 1,
        damage = true,
        force = 'enemy',
        level = 120,
        type = 'item',
        mana_cost = 1000,
        tick = 1500,
        enabled = true,
        sprite = 'recipe/atomic-bomb'
    }
    spells[#spells + 1] = {
        name = {'spells.ch'},
        itam_code = true,
        entityName = 'ch',
        target = true,
        force = 'player',
        level = 60,
        type = 'special',
        mana_cost = 800,
        tick = 100,
        enabled = true,
        sprite = 'entity/biter-spawner'
    }
    spells[#spells + 1] = {
        name = {'spells.huo_dun'},
        itam_code = true,
        entityName = 'huo_dun',
        target = true,
        force = 'player',
        level = 40,
        type = 'special',
        mana_cost = 250,
        tick = 100,
        enabled = true,
        sprite = 'item/flamethrower-ammo'
    }
    spells[#spells + 1] = {
        name = {'spells.advanced_fishing'},
        itam_code = true,
        entityName = 'advanced_fishing',
        target = false,
        force = 'player',
        level = 20,
        type = 'special',
        mana_cost = 80,
        tick = 320,
        enabled = true,
        sprite = 'item/raw-fish'
    }
    spells[#spells + 1] = {
        name = {'spells.shui_long_dan'},
        itam_code = true,
        entityName = 'shui_long_dan',
        target = true,
        force = 'player',
        level = 50,
        type = 'special',
        mana_cost = 300,
        tick = 100,
        enabled = true,
        sprite = 'item/offshore-pump'
    }
    spells[#spells + 1] = {
        name = {'spells.xiao_jingling'},
        itam_code = true,
        entityName = 'xiao_jingling',
        target = true,
        force = 'player',
        level = 80,
        type = 'special',
        mana_cost = 400,
        tick = 100,
        enabled = true,
        sprite = 'entity/behemoth-spitter'
    }
    spells[#spells + 1] = {
        name = {'spells.huanxing_huoshan_penfa'},
        itam_code = true,
        entityName = 'huanxing_huoshan_penfa',
        target = true,
        force = 'player',
        level = 70,
        type = 'special',
        mana_cost = 500,
        tick = 100,
        enabled = true,
        sprite = 'entity/small-demolisher-fissure'
    }
    spells[#spells + 1] = {
        name = {'spells.leizhenyu'},
        itam_code = true,
        entityName = 'leizhenyu',
        target = true,
        force = 'player',
        level = 60,
        type = 'special',
        mana_cost = 350,
        tick = 100,
        enabled = true,
        sprite = 'entity/lightning'
    }
    spells[#spells + 1] = {
        name = {'spells.diankuang'},
        itam_code = true,
        entityName = 'diankuang',
        target = true,
        force = 'player',
        level = 90,
        type = 'special',
        mana_cost = 600,
        tick = 100,
        enabled = true,
        sprite = 'virtual-signal/signal-Z'
    }

    return spells
end

-- ============================================
-- 升级参数表（itam_spell）
-- 标准化：默认 need_times=50, bonus=1, base=1（连续升级模式）
-- 例外：切换型技能（wudi_turret/biter_special_forces）保留 need_list+upgrade_list
-- ============================================
Public.itam_spell = {
    ['wudi_turret'] = {max_range = 36, tick_speed = 1, need_list = {1, 200, 1000}, upgrade_list = {'firearm-magazine', 'piercing-rounds-magazine', 'uranium-rounds-magazine'}},
    ['biter_special_forces'] = {max_range = 36, tick_speed = 1, need_list = {1, 300, 500, 1000}, upgrade_list = {'1', '2', '3', '4'}},
    ['ch'] = {max_range = 36, tick_speed = 1, need_times = 50, bonus = 1, base = 1},
    ['ssz'] = {max_range = 36, tick_speed = 1, need_times = 50, bonus = 1, base = 1},
    ['jx'] = {max_range = 36, tick_speed = 1, need_times = 50, bonus = 1, base = 1},
    ['lyly'] = {max_range = 36, tick_speed = 1, need_times = 50, bonus = 1, base = 1},
    ['jgq'] = {max_range = 36, tick_speed = 1, need_times = 50, bonus = 1, base = 1},
    ['ufo'] = {max_range = 36, tick_speed = 1, need_times = 50, bonus = 1, base = 1},
    ['lightning_chain'] = {max_range = 36, tick_speed = 1, need_times = 50, bonus = 1, base = 1},
    ['leizhenyu'] = {max_range = 36, tick_speed = 1, need_times = 50, bonus = 1, base = 1},
    ['huo_dun'] = {max_range = 36, tick_speed = 1, need_times = 50, bonus = 1, base = 1},
    ['shui_long_dan'] = {max_range = 36, tick_speed = 1, need_times = 50, bonus = 1, base = 1},
    ['advanced_fishing'] = {max_range = 36, tick_speed = 1, need_times = 50, bonus = 1, base = 1},
    ['xiao_jingling'] = {max_range = 36, tick_speed = 1, need_times = 50, bonus = 1, base = 1},
    ['huanxing_huoshan_penfa'] = {max_range = 36, tick_speed = 1, need_times = 50, bonus = 1, base = 1},
    ['diankuang'] = {max_range = 36, tick_speed = 1, need_times = 50, bonus = 1, base = 1},
}

-- ============================================
-- 投射物类型表
-- ============================================
Public.projectile_types = {
    ['distractor-capsule'] = {name = 'distractor-capsule', count = 1, max_range = 36, tick_speed = 1},
    ['grenade'] = {name = 'grenade', count = 1, max_range = 36, tick_speed = 1},
    ['cluster-grenade'] = {name = 'cluster-grenade', count = 1, max_range = 36, tick_speed = 1},
    ['slowdown-capsule'] = {name = 'slowdown-capsule', count = 1, max_range = 36, tick_speed = 1},
    ['atomic-bomb'] = {name = 'atomic-bomb', count = 1, max_range = 36, tick_speed = 1},
    ['warp-gate'] = {name = 'warp-gate', count = 1, max_range = 36, tick_speed = 1},
}

-- ============================================
-- 升级系统（从 main.lua 迁移）
-- 支持两种升级模式：
--   1. 连续升级（need_times+bonus+base 或 lianxu=true）
--   2. 阶段升级（need_list+upgrade_list）
-- 标准化后：默认走连续升级，need_times=50/bonus=1/base=1
-- ============================================
local function upgrade_lianxu(player, spell_name, up)
    local this = WPT.get()
    local index = player.index

    if not this.upgrade_spell[index] then
        this.upgrade_spell[index] = {}
    end
    if not this.upgrade_spell[index][spell_name] then
        this.upgrade_spell[index][spell_name] = 0
    end

    if up then
        this.upgrade_spell[index][spell_name] = this.upgrade_spell[index][spell_name] + 1
    end

    local times = this.upgrade_spell[index][spell_name]
    local cfg = Public.itam_spell[spell_name]
    -- 标准化默认值
    local base = cfg.base or 1
    local need_times = cfg.need_times or 50
    local bonus = cfg.bonus or 1

    local bonus_time = 0
    while times > need_times do
        bonus_time = bonus_time + 1
        times = times - need_times
    end
    return base + bonus_time * bonus
end

local function upgrade_stage(player, spell_name, up)
    local this = WPT.get()
    local index = player.index

    if not this.upgrade_spell[index] then
        this.upgrade_spell[index] = {}
    end
    if not this.upgrade_spell[index][spell_name] then
        this.upgrade_spell[index][spell_name] = 0
    end
    if up then
        this.upgrade_spell[index][spell_name] = this.upgrade_spell[index][spell_name] + 1
    end

    local times = this.upgrade_spell[index][spell_name]
    local cfg = Public.itam_spell[spell_name]
    local need_upgrade_list = cfg.need_list
    local get_upgrade_list = cfg.upgrade_list

    local spell_index = 1
    for k, v in pairs(need_upgrade_list) do
        if times > v then
            spell_index = k
        end
    end
    return get_upgrade_list[spell_index]
end

function Public.upgrade_spell(player, spell_name, up)
    local cfg = Public.itam_spell[spell_name]
    if not cfg then return 1 end
    -- 阶段升级模式（need_list+upgrade_list）
    if cfg.need_list and cfg.upgrade_list then
        return upgrade_stage(player, spell_name, up)
    end
    -- 默认：连续升级模式（标准化）
    return upgrade_lianxu(player, spell_name, up)
end

-- ============================================
-- 技能实现函数（从 functions.lua 迁移）
-- ============================================

-- 疾跑：8 秒移速 +50%
function Public.jx(position, surface, player, times)
    P.update_single_modifier(player, 'character_running_speed_modifier', 'jx', 0.5)
    P.update_player_modifiers(player)
    Task.set_timeout_in_ticks(60 * 8, jx_timeout, player)
    return true
end

-- 石墙阵：5x5 交错放置石墙
function Public.ssz(position, surface, player, times)
    for a = -2, 2 do
        for b = -2, 2 do
            if surface.can_place_entity{name = 'stone-wall', position = {position.x + a, position.y + b}, force = game.forces.player} then
                if (a + b) % 2 == 0 then
                    surface.create_entity({name = 'stone-wall', position = {position.x + a, position.y + b}, force = game.forces.player})
                end
            end
        end
    end
    return true
end

-- 火焰领域：5x5 火焰
function Public.lyly(position, surface, player, times)
    for a = -4, 4 do
        for b = -4, 4 do
            surface.create_entity({name = 'fire-flame', position = {position.x + a, position.y + b}, force = game.forces.player})
        end
    end
    return true
end

-- 火遁：路径火焰 + 范围伤害
function Public.huo_dun(position, surface, player, times)
    local level = times or 1
    if level > 80 then level = 80 end
    
    local rpg_t = RPG.get_value_from_player(player.index)
    local magicka_bonus = rpg_t.magicka or 0
    local damage_multiplier = magicka_bonus * 1
    if damage_multiplier > 3000 then
        damage_multiplier = 3000
    end
    local damage = 75 + (level - 1) * 30 + damage_multiplier
    local flame_radius = 4 + math.floor(level / 13)
    if flame_radius > 7 then
        flame_radius = 7
    end

    local player_pos = player.physical_position
    local distance = math.sqrt((position.x - player_pos.x)^2 + (position.y - player_pos.y)^2)

    local steps = math.floor(distance / 2) + 1
    for i = 1, steps do
        if i > 1 then
            local ratio = i / steps
            local path_x = player_pos.x + (position.x - player_pos.x) * ratio
            local path_y = player_pos.y + (position.y - player_pos.y) * ratio
            surface.create_entity({
                name = 'fire-flame',
                position = {path_x, path_y},
                force = game.forces.enemy
            })
        end
    end

    for i = 1, 24 do
        local angle = (i / 24) * math.pi * 2
        local effect_pos = {
            x = position.x + math.cos(angle) * flame_radius,
            y = position.y + math.sin(angle) * flame_radius
        }
        surface.create_entity({
            name = 'fire-flame',
            position = effect_pos,
            force = game.forces.enemy
        })
    end

    local entities = EntityCache.find_entities_cached(surface, {
        position = position,
        radius = flame_radius,
        force = 'enemy',
        type = goal
    })

    for _, entity in pairs(entities) do
        local dx = entity.position.x - position.x
        local dy = entity.position.y - position.y
        local distance_from_center = math.sqrt(dx * dx + dy * dy)
        local damage_distance_modifier = math.max(0.3, 1 - distance_from_center / flame_radius)
        local final_damage = damage * damage_distance_modifier
        if final_damage > 0 then
            deal_damage_with_floating_text(entity, player, final_damage, 'fire')
        end
    end
    return true
end

-- 水龙弹：水柱路径 + 击退 + 自身回血
function Public.shui_long_dan(position, surface, player, times)
    local level = times or 1
    if level > 80 then level = 80 end
    
    local rpg_t = RPG.get_value_from_player(player.index)
    local magicka_bonus = rpg_t.magicka or 0
    local damage_multiplier = magicka_bonus * 1
    if damage_multiplier > 3000 then
        damage_multiplier = 3000
    end
    local base_damage = 60 + (level - 1) * 20 + damage_multiplier
    local water_radius = 3 + math.floor(level / 15)
    if water_radius > 6 then
        water_radius = 6
    end

    local health_regen = player.character.max_health * 0.15
    if health_regen > 1000 then
        health_regen = 1000
    end
    player.character.health = player.character.health + health_regen

    local player_pos = player.physical_position
    local distance = math.sqrt((position.x - player_pos.x)^2 + (position.y - player_pos.y)^2)
    if distance > 32 then
        distance = 32
    end

    local steps = math.floor(distance * 2) + 1
    for i = 1, steps do
        local ratio = i / steps
        local path_x = player_pos.x + (position.x - player_pos.x) * ratio
        local path_y = player_pos.y + (position.y - player_pos.y) * ratio
        surface.create_entity({
            name = 'water-splash',
            position = {path_x, path_y},
            force = game.forces.player
        })
        if i % 3 == 1 then
            local enemies = surface.find_entities_filtered({
                position = {x = path_x, y = path_y},
                radius = 1.5,
                force = 'enemy',
                type = {'unit', 'spider-unit'}
            })
            for _, enemy in pairs(enemies) do
                if enemy.valid and enemy.health then
                    deal_damage_with_floating_text(enemy, player, base_damage, 'laser')
                end
            end
        end
    end
    return true
end

-- UFO：召唤诱饵弹（base=8 补偿：原 base=8，标准化后 base=1，函数内 +7 保证初始 8 次）
function Public.ufo(position, surface, player, times)
    local count = times + 7
    if count > 17 then count = 17 end
    for i = 1, count do
        local target = {x = position.x + math.random(-5, 5), y = position.y + math.random(-5, 5)}
        player.physical_surface.create_entity({
            name = 'distractor-capsule',
            position = player.physical_position,
            force = 'player',
            source = player.character,
            target = target,
            speed = 0.8,
            player = player
        })
    end
    return true
end

-- 激光枪（jgq）：5 次激光齐射（base=8 补偿：原 base=8，标准化后 base=1，函数内 +7 保证初始 8 次）
function Public.jgq(position, surface, player, times)
    local count = times + 7
    if count > 17 then count = 17 end
    for i = 1, count do
        Task.set_timeout_in_ticks(i * 15, jgq_work, player)
    end
    return true
end

-- 闪电链：玩家→目标→连锁
function Public.lightning_chain(position, surface, player, times)
    times = times or 1
    if times > 80 then times = 80 end

    local enemies = EntityCache.find_entities_cached(surface, {
        position = position,
        radius = 20,
        force = game.forces.enemy,
        type = goal
    })

    if #enemies == 0 then
        return false
    end

    
    local rpg_t = RPG.get_value_from_player(player.index)
    local magicka_bonus = rpg_t.magicka or 0
    local damage_multiplier = magicka_bonus * 1
    if damage_multiplier > 3000 then
        damage_multiplier = 3000
    end

    local max_targets = 10
    local total_damage = (200 + 50 * (times - 1)) + damage_multiplier
    local min_damage = total_damage * 0.2

    local targets = {}
    for i = 1, math.min(#enemies, max_targets) do
        table.insert(targets, enemies[i])
    end

    table.sort(targets, function(a, b)
        return a.health < b.health
    end)

    if #targets > 0 and targets[1] and targets[1].valid then
        surface.create_entity({
            name = 'electric-beam',
            position = player.physical_position,
            target = targets[1].position,
            source = player.physical_position,
            duration = 25
        })

        for i = 1, #targets - 1 do
            if targets[i] and targets[i].valid and targets[i + 1] and targets[i + 1].valid then
                surface.create_entity({
                    name = 'electric-beam',
                    position = targets[i].position,
                    target = targets[i + 1].position,
                    source = targets[i].position,
                    duration = 25
                })
            end
        end
    end

    local remaining_damage = total_damage
    for _, enemy in pairs(targets) do
        if remaining_damage > 0 and enemy and enemy.valid then
            remaining_damage = remaining_damage * 0.8
            deal_damage_with_floating_text(enemy, player, remaining_damage, 'electric')
            if remaining_damage < min_damage then
                remaining_damage = min_damage
            end
        end
    end
    return true
end

-- 虫族特种部队：召唤 1 沙虫 + 3 biter + 2 spitter（22 秒后清理）
-- 签名统一为 (position, surface, player, index)，index 为阶段升级返回的字符串阶层
function Public.biter_special_forces(position, surface, player, index)
    local biter_name = biter_list[index]
    local spitter_name = spitter_list[index]
    local shachong_name = shachong_list[index]

    if not surface.can_place_entity{name = biter_name, position = {x = position.x, y = position.y}, force = game.forces.player} then return false end
    local shachong = surface.create_entity{
        name = shachong_name,
        position = {x = position.x, y = position.y},
        force = game.forces.player,
    }
    if not shachong then
        return false
    end

    tame_unit_effects(player, shachong)
    local forces = {}
    forces[#forces + 1] = shachong
    local group = player.physical_surface.create_unit_group({position = position, force = player.force})
    for i = 1, 3 do
        local biter = surface.create_entity{
            name = biter_name,
            position = {x = position.x + 3, y = position.y + 3},
            force = game.forces.player,
        }
        biter.ai_settings.allow_try_return_to_spawner = false
        forces[#forces + 1] = biter
        tame_unit_effects(player, biter)
        group.add_member(biter)
    end

    for i = 1, 2 do
        local spitter = surface.create_entity{
            name = spitter_name,
            position = {x = position.x + 3, y = position.y + 3},
            force = game.forces.player,
        }
        spitter.ai_settings.allow_try_return_to_spawner = false
        forces[#forces + 1] = spitter
        tame_unit_effects(player, spitter)
        group.add_member(spitter)
    end

    Task.set_timeout_in_ticks(60 * 22, kill_forces, forces)
    return true
end

-- 虫海（ch）：消耗法力召唤随机虫群（12 秒后清理）
function Public.ch(position, surface, player, times)
    
    local rpg_t = RPG.get('rpg_t')
    local mana_max = math.floor(rpg_t[player.index].mana) * 1.2 + times
    local forces = {}
    local group = player.physical_surface.create_unit_group({position = position, force = player.force})
    if math.floor(rpg_t[player.index].mana) > 40 and mana_max > 20 then
        while mana_max > 20 do
            mana_max = mana_max - 1
            for name, worth in pairs(t) do
                if worth <= mana_max then
                    mana_max = mana_max - worth
                    local e = player.physical_surface.create_entity{
                        name = name,
                        position = {x = position.x + math.random(-18, 18), y = position.y + math.random(-18, 18)},
                        force = game.forces.player,
                    }
                    forces[#forces + 1] = e
                    tame_unit_effects(player, e)
                    if e and e.valid and (e.type == 'unit' or e.type == 'spider-unit') then
                        group.add_member(e)
                    end
                end
            end
        end

        Task.set_timeout_in_ticks(60 * 12, kill_forces, forces)
        unstuck_player(player.index)
        rpg_t[player.index].mana = 0
        return true
    end
end

-- 高级钓鱼：根据等级获得鱼（最多 30 条）
function Public.advanced_fishing(position, surface, player, times)
    local level = times or 1
    if level > 80 then level = 80 end
    local fish_count = 2 + level
    if fish_count >= 30 then
        fish_count = 30
    end
    player.insert({name = 'raw-fish', count = fish_count})

    player.create_local_flying_text({
        text = {'amap.rpg_fishing_got', fish_count},
        position = position,
        color = {r = 0.2, g = 0.8, b = 1.0},
        speed = 0.8
    })
    return true
end

-- 无敌炮塔（wudi_turret）：放置无敌炮塔 12 秒后销毁
-- 签名统一为 (position, surface, player, ammo_name)，ammo_name 为阶段升级返回的弹药字符串
function Public.wudi_turret(position, surface, player, ammo_name)
    if not surface.can_place_entity{name = 'gun-turret', position = {x = position.x, y = position.y}, force = game.forces.player} then return false end
    local turret = surface.create_entity{
        name = 'gun-turret',
        position = {x = position.x, y = position.y},
        force = game.forces.player
    }
    if not turret then
        return false
    end

    turret.destructible = false
    turret.minable_flag = false
    turret.operable = false
    turret.last_user = player
    turret.insert{name = ammo_name, count = 10}

    local this = WPT.get()
    this.turret_rpg[#this.turret_rpg + 1] = turret

    local data = {entity = turret}
    Task.set_timeout_in_ticks(720, kill_turret, data)
    return true
end

-- 小精灵召唤（xiao_jingling）：召唤 3-12 只 behemoth-spitter 作为法师宠物
function Public.xiao_jingling(position, surface, player, times)
    local level = times or 1
    
    local rpg_t = RPG.get_value_from_player(player.index)
    local this = WPT.get()
    local spirit_count = 3 + (level - 1)
    if spirit_count > 12 then
        spirit_count = 12
    end
    local summoned_spirits = 0
    for i = 1, spirit_count do
        local angle = (i - 1) * (360 / spirit_count) + math.random(-30, 30)
        local distance = 2 + math.random(-1, 1)
        local spirit_x = position.x + math.cos(math.rad(angle)) * distance
        local spirit_y = position.y + math.sin(math.rad(angle)) * distance

        local spirit_position = surface.find_non_colliding_position('character', {x = spirit_x, y = spirit_y}, 5, 0.5)
        if spirit_position then
            local spirit_entity = surface.create_entity({
                name = 'behemoth-spitter',
                position = spirit_position,
                force = 'player'
            })

            if spirit_entity and spirit_entity.valid then
                spirit_entity.ai_settings.allow_try_return_to_spawner = false
                BiterPets.biter_pets_tame_unit(player, spirit_entity)

                if spirit_entity and spirit_entity.valid then
                    rendering.draw_text {
                        text = {'amap.rpg_xiao_jingling_overhead'},
                        surface = player.physical_surface,
                        target = {
                            entity = spirit_entity,
                            offset = {0, -2.5},
                        },
                        color = {
                            r = player.color.r * 0.6 + 0.25,
                            g = player.color.g * 0.6 + 0.25,
                            b = player.color.b * 0.6 + 0.25,
                            a = 1
                        },
                        scale = 1.05,
                        font = 'default-large-semibold',
                        alignment = 'center',
                        scale_with_zoom = false
                    }
                end

                summoned_spirits = summoned_spirits + 1

                local spirit_data = {
                    entity = spirit_entity,
                    spawn_time = game.tick,
                    lifetime = 60 * 30,
                }

                if not this.fairy_spirits then
                    this.fairy_spirits = {}
                end
                if not this.fairy_spirits[player.index] then
                    this.fairy_spirits[player.index] = {}
                end
                this.fairy_spirits[player.index][#this.fairy_spirits[player.index] + 1] = spirit_data
            end
        end
    end
    return true
end

-- 清理过期精灵（由主循环定期调用）
function Public.cleanup_fairy_spirits()
    local this = WPT.get()
    if this.fairy_spirits then
        for player_index, spirits in pairs(this.fairy_spirits) do
            local valid_spirits = {}
            local valid_count = 1
            for _, spirit_data in pairs(spirits) do
                if spirit_data.entity and spirit_data.entity.valid and
                   game.tick - spirit_data.spawn_time <= spirit_data.lifetime then
                    valid_spirits[valid_count] = spirit_data
                    valid_count = valid_count + 1
                else
                    if spirit_data.entity and spirit_data.entity.valid then
                        spirit_data.entity.destroy()
                    end
                end
            end
            if #valid_spirits > 0 then
                this.fairy_spirits[player_index] = valid_spirits
            else
                this.fairy_spirits[player_index] = nil
            end
        end
    end
end

-- 触发所有精灵的闪电链攻击（由主循环定期调用）
function Public.trigger_all_fairy_lightning(players)
    local this = WPT.get()
    local spirits_by_player = this.fairy_spirits or {}

    for player_index, spirits in pairs(spirits_by_player) do
        local valid_spirits = {}
        local valid_count = 1
        for _, spirit in pairs(spirits) do
            if spirit.entity and spirit.entity.valid then
                valid_spirits[valid_count] = spirit
                valid_count = valid_count + 1
            end
        end
        spirits_by_player[player_index] = valid_spirits
    end

    for player_index, spirits in pairs(spirits_by_player) do
        local player = game.get_player(player_index)
        if player and player.character and player.character.valid then
            local sample_spirit = spirits[1]
            if sample_spirit then
                local laser_damage_bonus = game.forces.player.get_ammo_damage_modifier('laser') + 1
                local attack_speed_bonus = game.forces.player.get_gun_speed_modifier('laser') + 1
                local base_damage = 10 * laser_damage_bonus * attack_speed_bonus
                local chain_range = 16 + math.floor(#spirits / 6)
                local max_chains = 8 + math.floor(#spirits / 6)
                if max_chains > 24 then
                    max_chains = 24
                end
                if chain_range > 30 then
                    chain_range = 30
                end

                local player_position = player.character.position
                local enemies = EntityCache.find_entities_cached(player.physical_surface, {
                    position = player.physical_position,
                    radius = chain_range,
                    force = 'enemy',
                    type = goal,
                    limit = max_chains
                })

                if #enemies > 0 then
                    local lianjieshu = 0
                    for _, spirit in pairs(spirits) do
                        if spirit.entity and spirit.entity.valid then
                            player.physical_surface.create_entity({
                                name = 'electric-beam',
                                position = player_position,
                                source_position = player_position,
                                force = 'player',
                                target_position = spirit.entity.position,
                                duration = 25
                            })
                            lianjieshu = lianjieshu + 1
                        end
                        if lianjieshu >= 10 then
                            break
                        end
                    end

                    for _, enemy in pairs(enemies) do
                        if enemy.valid and enemy.health then
                            player.physical_surface.create_entity({
                                name = 'electric-beam',
                                position = player_position,
                                target = enemy.position,
                                source = player_position,
                                duration = 20
                            })
                            if enemy.valid and enemy.health then
                                deal_damage_with_floating_text(enemy, player, base_damage, 'electric')
                            end
                        end
                    end
                end
            end
        end
    end
end

-- 环形火山喷发（huanxing_huoshan_penfa）：搜索敌人→随机选 N 个→点燃→2 秒后爆发
function Public.huanxing_huoshan_penfa(position, surface, player, times)
    local enemies = EntityCache.find_entities_cached(surface, {
        position = position,
        radius = 18,
        force = 'enemy',
        type = goal,
    })

    if #enemies == 0 then
        return false
    end

    
    local rpg_t = RPG.get_value_from_player(player.index)
    local magicka_bonus = rpg_t.magicka or 0
    local damage_multiplier = magicka_bonus * 1
    if damage_multiplier > 3000 then
        damage_multiplier = 3000
    end

    times = math.min(times, 80)
    local base_val = 100 + 65 * (times - 1)
    local total_damage = base_val + damage_multiplier

    local minor_damage = total_damage * 0.2
    local major_damage = total_damage * 0.8

    local max_targets = math.min(10, 4 + math.floor(times / 5))

    for i = #enemies, 2, -1 do
        local j = math.random(i)
        enemies[i], enemies[j] = enemies[j], enemies[i]
    end

    local targets = {}
    local count = math.min(#enemies, max_targets)
    for i = 1, count do
        table.insert(targets, enemies[i])
    end

    for _, enemy in pairs(targets) do
        local lava_pos = enemy.position
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
        deal_damage_with_floating_text(enemy, player, minor_damage, 'fire')
        Task.set_timeout_in_ticks(100, active_lava_burst_task, {
            surface = surface,
            pos = lava_pos,
            player = player,
            damage = major_damage
        })
    end
    return true
end

-- 雷阵雨（leizhenyu）：3-8 次延迟闪电打击
function Public.leizhenyu(position, surface, player, times)
    local level = times or 1
    if level > 80 then level = 80 end

    
    local rpg_t = RPG.get_value_from_player(player.index)
    local magicka_bonus = rpg_t.magicka or 0
    local damage_multiplier = magicka_bonus * 1
    if damage_multiplier > 3000 then
        damage_multiplier = 3000
    end

    local damage = 60 + (level - 1) * 10 + damage_multiplier
    local radius = 6 + math.floor(level / 10)
    if radius > 8 then
        radius = 8
    end

    local total_strikes = 3 + math.floor(level / 8)
    if total_strikes > 8 then
        total_strikes = 8
    end

    for i = 1, total_strikes do
        Task.set_timeout_in_ticks(i * 60, leizhenyu_work, {
            surface = surface,
            position = position,
            player = player,
            damage = damage,
            radius = radius
        })
    end
    return true
end

-- 癫狂（diankuang）：自身持续掉血/掉蓝 4 秒，5 秒后对鼠标位置 8 米内虫子造成「两者损失之和」伤害
function Public.diankuang(position, surface, player, times)
    if not player or not player.valid then return false end
    if not player.character or not player.character.valid then return false end
    if not surface or not surface.valid then return false end
    if not position then return false end

    
    local rpg_t = RPG.get_value_from_player(player.index)
    if not rpg_t then return false end

    local max_health = player.character.max_health
    local mana_max = rpg_t.mana_max

    local self_data = {player = player}
    for i = 1, 4 do
        Task.set_timeout_in_ticks(60 * i, diankuang_self_loss_token, self_data)
    end

    local burst_data = {
        player = player,
        surface = surface,
        position = {x = position.x, y = position.y},
        max_health = max_health,
        mana_max = mana_max,
        times = times
    }
    Task.set_timeout_in_ticks(60 * 5, diankuang_burst_token, burst_data)

    return true
end

-- ============================================
-- handlers 表：special 技能调度（统一签名 position, surface, player, daoju）
-- main.lua 中 on_player_used_capsule 通过 Public.handlers[entityName] 调用
-- ============================================
Public.handlers = {
    ['wudi_turret'] = Public.wudi_turret,
    ['ch'] = Public.ch,
    ['ssz'] = Public.ssz,
    ['jx'] = Public.jx,
    ['lyly'] = Public.lyly,
    ['jgq'] = Public.jgq,
    ['ufo'] = Public.ufo,
    ['lightning_chain'] = Public.lightning_chain,
    ['leizhenyu'] = Public.leizhenyu,
    ['biter_special_forces'] = Public.biter_special_forces,
    ['huo_dun'] = Public.huo_dun,
    ['shui_long_dan'] = Public.shui_long_dan,
    ['advanced_fishing'] = Public.advanced_fishing,
    ['xiao_jingling'] = Public.xiao_jingling,
    ['huanxing_huoshan_penfa'] = Public.huanxing_huoshan_penfa,
    ['diankuang'] = Public.diankuang,
}

-- 延迟绑定：由 table.lua 在 require 后调用，解决循环依赖 + 运行时 require 限制
function Public.set_rpg_ref(ref)
    RPG = ref
end

return Public
