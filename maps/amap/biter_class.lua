-- Biter class module for managing special biter types
local Event = require 'utils.event'
local Global = require 'utils.global'
local Token = require 'utils.token'
local Task = require 'utils.task'
local EntityCache = require 'maps.amap.entity_cache'


local Public = {}

local this = {
    boss_units = {},
    mage_biter_units = {},
    warrior_biter_units = {},
    suicide_biter_units = {}
}
 

local function get_opposite_force(force)
    if force == 'player' then
        return 'enemy'
    else
        return 'player'
    end
end

local function create_flying_text(entity, text)
    if not (entity and entity.valid) then return end

    for _, target_player in pairs(game.connected_players) do
        if entity.surface == target_player.physical_surface then
        target_player.create_local_flying_text{
            text = {text},
            color = { r = 1, g = 0.8, b = 0.2 },
            position = entity.position,
            speed = 0.8
        }
    end
    end
end

local kill_summoned_units = Token.register(function(data)
    for _, v in pairs(data) do
        if v and v.valid then
            v.destroy()
        end
    end
end)

local goal = {'unit', 'turret','combat-robot','character','spider-unit'}
local function find_nearby_entities(surface, position, radius, force)
    local entities = surface.find_entities_filtered({
        position = position,
        radius = 26,
        force = force,
        type = goal
    })
    
    local characters = {}
    for _, entity in pairs(entities) do
        if entity.type == 'character' then
            characters[#characters + 1] = entity
        end
    end
    
    if #characters > 0 then
        return characters
    end
    
    return entities
end



local function leitingwanjun(entity)
    local surface = entity.surface
    local position = entity.position
    local target_force = get_opposite_force(entity.force.name)
    
    local laser_damage_bonus = game.forces[entity.force.name].get_ammo_damage_modifier("laser") + 1
    local attack_speed_bonus = game.forces[entity.force.name].get_gun_speed_modifier('laser') + 1
    
    local base_damage = 500
    local damage = base_damage * laser_damage_bonus * attack_speed_bonus *2
    
    local nearby_enemies = find_nearby_entities(surface, position, 16, target_force)
    
    if #nearby_enemies <= 0 then
        return
    end
    
    create_flying_text(entity, 'amap.flying_text_leitingwanjun')
    
    local target_entity = nearby_enemies[1]
    
    if target_entity and target_entity.valid then
        surface.create_entity({
            name = 'lightning',
            position = target_entity.position,
            force = entity.force.name,
            source = entity,
            target = target_entity,
            speed = 1.0
        })
        

        if target_entity.type == 'unit' or target_entity.type == 'character' or target_entity.type == 'spider-unit' then
            surface.create_entity {
                name = 'tesla-turret-stun',
                position = position,
                target = target_entity,
                speed = 1,
                force = entity.force.name
            }
        end
        local radius = 7
        local target_position = target_entity.position
        
        for _, e in pairs(surface.find_entities_filtered({
            position = target_position,
            radius = radius,
            force = target_force,
            type = goal
        })) do
            if e.valid and e.health and damage > 0 then
                local distance_from_center = math.sqrt((e.position.x - target_position.x) ^ 2 + (e.position.y - target_position.y) ^ 2)
                local damage_distance_modifier = 1 - distance_from_center / radius
                
                if damage_distance_modifier > 0 then
                    e.damage(damage * damage_distance_modifier, entity.force.name, 'electric')
                end
            end
        end
    end
end

local function water_dragon_ball(entity)
    
    
    local surface = entity.surface
    local position = entity.position
    local base_damage = 600
    local laser_damage_bonus = game.forces[entity.force.name].get_gun_speed_modifier('laser') + 1
    local damage = base_damage * laser_damage_bonus *2
    local knockback_distance = 2
    local water_radius = 2

    local health_regen = entity.max_health * 0.4
    if health_regen > 1000 then
        health_regen = 1000
    end
    entity.health = entity.health + health_regen

    local target_force = get_opposite_force(entity.force.name)
    local players = find_nearby_entities(surface, position, 32, target_force)

    if #players == 0 then
        return
    end
    create_flying_text(entity, 'amap.flying_text_water_dragon_ball')

    local target = players[math.random(#players)]
    if not target or not target.valid then
        return
    end

    local target_pos = target.position
    local distance = math.sqrt((target_pos.x - position.x)^2 + (target_pos.y - position.y)^2)

    if distance > 32 then
        distance = 32
    end

    local steps = math.floor(distance * 2) + 1
    for i = 1, steps do
        local ratio = i / steps
        local path_x = position.x + (target_pos.x - position.x) * ratio
        local path_y = position.y + (target_pos.y - position.y) * ratio

        surface.create_entity({
            name = 'water-splash',
            position = {path_x, path_y},
            force = entity.force.name
        })

        local targets = surface.find_entities_filtered({
            area = {{path_x - water_radius, path_y - water_radius}, {path_x + water_radius, path_y + water_radius}},
            force = target_force
        })
    end
end

local function fire_shield(entity)
    
    
    local surface = entity.surface
    local position = entity.position
    local base_damage = 500
    local flame_damage_bonus = game.forces[entity.force.name].get_gun_speed_modifier('flamethrower') + 1
    local damage = base_damage * flame_damage_bonus *2
    local flame_radius = 4

    local target_force = get_opposite_force(entity.force.name)
    local players = find_nearby_entities(surface, position, 30, target_force)

    if #players == 0 then
        return
    end

    local target = players[math.random(#players)]
    if not target or not target.valid then
        return
    end
    create_flying_text(entity, 'amap.flying_text_fire_shield')
    local target_pos = target.position
    local distance = math.sqrt((target_pos.x - position.x)^2 + (target_pos.y - position.y)^2)

    local steps = math.floor(distance / 2) + 1
    for i = 1, steps do
        if i > 1 then
            local ratio = i / steps
            local path_x = position.x + (target_pos.x - position.x) * ratio
            local path_y = position.y + (target_pos.y - position.y) * ratio

            surface.create_entity({
                name = 'fire-flame',
                position = {path_x, path_y},
                force = entity.force.name
            })
        end
    end

    for i = 1, 24 do
        local angle = (i / 24) * math.pi * 2
        local effect_pos = {
            x = target_pos.x + math.cos(angle) * flame_radius,
            y = target_pos.y + math.sin(angle) * flame_radius
        }
        surface.create_entity({
            name = 'fire-flame',
            position = effect_pos,
            force = entity.force.name
        })
    end

    local entities = find_nearby_entities(surface, target_pos, flame_radius, target_force)

    for _, e in pairs(entities) do
        if e.valid and e.health then
            local distance_from_center = math.sqrt(
                (e.position.x - target_pos.x)^2 + (e.position.y - target_pos.y)^2
            )
            local damage_distance_modifier = math.max(0.3, 1 - distance_from_center / flame_radius)
            local final_damage = damage * damage_distance_modifier

            if e.valid and e.health and final_damage > 0 then
                e.damage(final_damage, entity.force.name, 'laser')
            end
        end
    end
end

local function throw_offensive_drone(entity)
    
    
    local surface = entity.surface
    local position = entity.position
    local target_force = get_opposite_force(entity.force.name)
    local players = find_nearby_entities(surface, position, 20, target_force)
    
    if #players > 0 then
    for _, player in pairs(players) do
        if player and player.valid then
            surface.create_entity {
                name = 'distractor-capsule',
                position = position,
                target = player,
                speed = 1,
                force = entity.force.name
            }
            break
        end
    end
    create_flying_text(entity, 'amap.flying_text_offensive_drone')
    end
end

local function throw_poison_capsule(entity)

    
    local surface = entity.surface
    local position = entity.position
    local target_force = get_opposite_force(entity.force.name)
    local players = find_nearby_entities(surface, position, 20, target_force)
    
    if #players > 0 then
    for _, player in pairs(players) do
        if player and player.valid then
            surface.create_entity {
                name = 'poison-capsule',
                position = position,
                target = player,
                speed = 1,
                force = entity.force.name
            }
            break
        end
    end
    create_flying_text(entity, 'amap.flying_text_poison_capsule')
end
end

local function ignite_target(entity)
    
    
    local surface = entity.surface
    local position = entity.position
    local target_force = get_opposite_force(entity.force.name)
    local players = find_nearby_entities(surface, position, 20, target_force)
    
    local valid_targets = {}
    for _, player in pairs(players) do
        if player and player.valid and (player.type == 'unit' or player.type == 'character' or player.type == 'spider-unit') then
            valid_targets[#valid_targets + 1] = player
        end
    end
    
    if #valid_targets > 0 then
        local target = valid_targets[math.random(#valid_targets)]
        surface.create_entity({
            name = "fire-sticker",
            position = position,
            source = entity,
            target = target,
            force = entity.force.name
        })
        create_flying_text(entity, 'amap.flying_text_ignite')
    end
end

local function speed_up_allies(entity)
    create_flying_text(entity, 'amap.flying_text_speed_up_allies')
    
    local surface = entity.surface
    local position = entity.position
    local radius = 20

    for _, ally in pairs(surface.find_entities_filtered({
        position = position,
        radius = radius,
        type = {'unit', 'spider-unit'},
        force = entity.force.name,
    })) do
        if ally.valid and ally ~= entity then
            surface.create_entity({
                name = "bioflux-speed-regen-sticker",
                position = position,
                source = entity,
                target = ally,
                force = entity.force.name
            })
        end
    end
end

local function electric_beam_attack(entity)

    
    local surface = entity.surface
    local position = entity.position
    local radius = 20

    local laser_damage_bonus = game.forces[entity.force.name].get_ammo_damage_modifier("laser") + 1
    local attack_speed_bonus = game.forces[entity.force.name].get_gun_speed_modifier('laser') + 1

    local base_damage = 10
    local final_damage = base_damage * laser_damage_bonus * attack_speed_bonus

    local target_force = get_opposite_force(entity.force.name)
    local players = find_nearby_entities(surface, position, radius, target_force)

    if #players > 0 then
        local target_count = math.min(10, #players)
        local selected_targets = {}
        
        for i = 1, target_count do
            local random_index = math.random(#players)
            selected_targets[i] = players[random_index]
            table.remove(players, random_index)
        end
        
        for _, target in pairs(selected_targets) do
            if target and target.valid then
                surface.create_entity({
                    name = 'electric-beam',
                    position = position,
                    target = target,
                    source = position,
                    duration = 20
                })

                target.damage(final_damage, entity.force.name, 'laser')
            end
        end
        create_flying_text(entity, 'amap.flying_text_electric_beam')
    end
end

local function revive_corpses(entity)
    
    
    local surface = entity.surface
    local position = entity.position
    local radius = 33

    local corpses = surface.find_entities_filtered({
        position = position,
        radius = radius,
        type = 'corpse'
    })

    if #corpses == 0 then
        return
    end

    create_flying_text(entity, 'amap.flying_text_revive_corpses')

    local summon_points = 0
    for _, corpse in pairs(corpses) do
      
            corpse.destroy()
            summon_points = summon_points + 5
       
    end

    if summon_points >= 2000 then
        summon_points = 2000
    end

    local biter_types = {
         ['biter-spawner'] = 128,
    ['spitter-spawner'] = 128,
    ['behemoth-biter'] = 64,
    ['behemoth-spitter'] = 64,

    ['small-stomper-pentapod'] = 350,
    ['medium-stomper-pentapod'] = 640,
    ['big-stomper-pentapod'] = 1280,
    

    ['small-strafer-pentapod'] = 160,
    ['medium-strafer-pentapod'] = 240,
    ['big-strafer-pentapod'] = 480,

    ['small-wriggler-pentapod'] = 2,
    ['medium-wriggler-pentapod'] = 8,
    ['big-wriggler-pentapod'] = 32,

    
    ['big-biter'] = 16,
    ['big-spitter'] = 16,
   
    ['medium-biter'] = 4,
    ['medium-spitter'] = 4,

    ['small-biter'] = 1,
    ['small-spitter'] = 1,
    }

    local summoner_cost = biter_types[entity.name] or 128

    local summonable_biters = {}
    for name, cost in pairs(biter_types) do
        if cost <= summoner_cost then
            table.insert(summonable_biters, {name = name, cost = cost})
        end
    end

    table.sort(summonable_biters, function(a, b)
        return a.cost > b.cost
    end)

    local attempts = 0
    local max_attempts = 100
    local summoned_count = 0
    local max_summoned = 20
    local summoned_units = {}

    while summon_points > 0 and attempts < max_attempts and summoned_count < max_summoned do
        local points_reduced = false
        for _, biter_data in ipairs(summonable_biters) do
            local name = biter_data.name
            local cost = biter_data.cost
            if summon_points >= cost and summoned_count < max_summoned then
                local pos = surface.find_non_colliding_position(name, position, 18, 1)
                if pos then
                    local new_unit = surface.create_entity {
                        name = name,
                        position = pos,
                        force = entity.force.name
                    }
                    table.insert(summoned_units, new_unit)
                    summon_points = summon_points - cost
                    points_reduced = true
                    summoned_count = summoned_count + 1
                end
            end
        end
        if not points_reduced then
            break
        end
        attempts = attempts + 1
    end

    if #summoned_units > 0 then
        Task.set_timeout_in_ticks(60 * 60, kill_summoned_units, summoned_units)
    end
end

local mage_spells = {
    spell_offensive_drone = function(entity)
        throw_offensive_drone(entity)
    end,
    spell_ignite = function(entity)
        ignite_target(entity)
    end,
    spell_speed_up_allies = function(entity)
        speed_up_allies(entity)
    end,
    spell_electric_beam = function(entity)
        electric_beam_attack(entity)
    end,
    spell_revive_corpses = function(entity)
        revive_corpses(entity)
    end,
    spell_fire_shield = function(entity)
        fire_shield(entity)
    end,
    spell_water_dragon_ball = function(entity)
        water_dragon_ball(entity)
    end,
    spell_leitingwanjun = function(entity)
        leitingwanjun(entity)
    end
}

local spell_keys = {
    'spell_offensive_drone',
    'spell_ignite',
    'spell_speed_up_allies',
    'spell_electric_beam',
    'spell_revive_corpses',
    'spell_fire_shield',
    'spell_water_dragon_ball',
    'spell_leitingwanjun'
}

Global.register(
    this,
    function(t)
        this = t
    end
)


local spawn_biter_batch_token

spawn_biter_batch_token =
Token.register(
function(data)
    local surface = data.surface
    local entity_name = data.entity_name
    local position = data.position
    local force = data.force
    local batch_index = data.batch_index
    local total_batches = data.total_batches
    local total_count = data.total_count
    local created_count = data.created_count
    local unit_number = data.unit_number
    
    local batch_size = 8
    local start_index = (batch_index - 1) * batch_size + 1
    local end_index = math.min(batch_index * batch_size, total_count)
    
    local created_this_batch = 0
    for i = start_index, end_index do
        local pos = surface.find_non_colliding_position(entity_name, position, 32, 4)
        if pos then
            surface.create_entity{name = entity_name, position = pos, force = force}
            created_this_batch = created_this_batch + 1
        end
    end
    
    local new_created_count = created_count + created_this_batch
    

    
    if batch_index < total_batches then
        data.batch_index = batch_index + 1
        data.created_count = new_created_count
        Task.set_timeout_in_ticks(4, spawn_biter_batch_token, data)
    else

        this.boss_units[unit_number] = nil
    end
end
)

local function spawn_biters_on_death(entity, total_count)
    local data = {
        surface = entity.surface,
        entity_name = entity.name,
        position = entity.position,
        force = entity.force.name,
        batch_index = 1,
        total_batches = math.ceil(total_count / 8),
        total_count = total_count,
        created_count = 0,
        unit_number = entity.unit_number
    }
    
    Task.set_timeout_in_ticks(0, spawn_biter_batch_token, data)
end

local function on_entity_died(event)
    local entity = event.entity
    if not (entity and entity.valid) then return end

    local unit_number = entity.unit_number
    if not unit_number then return end

    if this.boss_units[unit_number] then
        spawn_biters_on_death(entity, this.boss_units[unit_number])
    end

    if this.mage_biter_units[unit_number] then
        this.mage_biter_units[unit_number] = nil
    end

    if this.warrior_biter_units[unit_number] then
        this.warrior_biter_units[unit_number] = nil
    end
end

--- Use this function to retrieve a key from the global table.
---@param key <string>
function Public.get(key)
    if key then
        return this[key]
    else
        return this
    end
end

--- Using this function can set a new value to an exist key or create a new key with value
---@param key <string>
---@param value <string/boolean>
function Public.set(key, value)
    if key and (value or value == false) then
        this[key] = value
        return this[key]
    elseif key then
        return this[key]
    else
        return this
    end
end

function Public.if_boss(biter)
    local unit_number = biter.unit_number
    local boss = this.boss_units[unit_number]
    if boss then
       return true
       else
        return false
    end
end

--- Use this function to reset the global table to it's init values.
function Public.reset_table()
  this.boss_units = {}
  this.mage_biter_units = {}
  this.warrior_biter_units = {}
  this.suicide_biter_units = {}
end


--- Use this function to add a new boss unit (with healthbar)
---@param unit <LuaEntity>
---@param health_multiplier <number>
---@param health_bar_size <number>
function Public.add_boss_unit(unit,sum)
    this.boss_units[unit.unit_number] = sum
    Public.draw_text('BOSS', unit)
end

--- Use this function to add a mage biter unit
---@param unit <LuaEntity>
function Public.add_mage_biter(unit)
    this.mage_biter_units[unit.unit_number] = {
        entity = unit,
        cast_time = math.random(230, 290)
    }
    Public.draw_text('法师虫', unit)
end

--- Use this function to add a warrior biter unit
---@param unit <LuaEntity>
function Public.add_warrior_biter(unit)
    this.warrior_biter_units[unit.unit_number] = true
    Public.draw_text('战士虫', unit)
end

--- Use this function to add a suicide biter unit
---@param unit <LuaEntity>
---@param count <number>
function Public.add_suicide_biter(unit, count)
    this.suicide_biter_units[unit.unit_number] = count or 0
    Public.draw_text('自爆虫', unit)
end

--- Use this function to randomly assign a class to a biter
---@param unit <LuaEntity>
function Public.assign_random_class(unit)
    local rand = math.random(3)
    if rand == 1 then
        this.mage_biter_units[unit.unit_number] = {
            entity = unit,
            cast_time = math.random(230, 290)
        }
         Public.draw_text('法师虫', unit)
    elseif rand == 2 then
        this.warrior_biter_units[unit.unit_number] = true
         Public.draw_text('战士虫', unit)
    else
        this.suicide_biter_units[unit.unit_number] = 0
        Public.draw_text('亡语虫', unit)
    end
end

--- Use this function to draw text above an entity
---@param text <string>
---@param entity <LuaEntity>
---@param color <table>
---@param players <table>
function Public.draw_text(text, entity, color, players)
    rendering.draw_text {
        text = text,
        surface = entity.surface,
        target = {
            entity = entity,
            offset = { 0, -1.5 }
        },
        color = color or { r = 1, g = 0.2, b = 0.2, a = 1 },
        players = players or game.connected_players,
        scale = 1.00,
        font = 'default-large-semibold',
        alignment = 'center',
        scale_with_zoom = false
    }
end



local function process_mage_spells()

    if not this.mage_biter_units then 
    this.boss_units = {}
    this.mage_biter_units = {}
    this.warrior_biter_units = {}
    this.suicide_biter_units = {}
    
    end
    for unit_number, mage_data in pairs(this.mage_biter_units) do
        if mage_data and mage_data.entity and mage_data.entity.valid then
            mage_data.cast_time = mage_data.cast_time + 2
            
            if mage_data.cast_time >= 300 then
                local spell_key = spell_keys[math.random(#spell_keys)]
                local spell_func = mage_spells[spell_key]
                if spell_func then
                    spell_func(mage_data.entity)
                end
                mage_data.cast_time = 0
            end
        else
            this.mage_biter_units[unit_number] = nil
        end
    end
end

Event.on_init(
    function()
        Public.reset_table()
    end
)

Event.on_nth_tick(2, process_mage_spells)

local function warrior_pull(entity, cause, damage)
    create_flying_text(entity, 'amap.flying_text_pull')
    
    if not (cause and cause.valid) then return end

    local surface = entity.surface
    local entity_pos = entity.position
    local cause_pos = cause.position
    
    local pull_distance = 5
    local distance = math.sqrt((cause_pos.x - entity_pos.x)^2 + (cause_pos.y - entity_pos.y)^2)
    
    if distance <= pull_distance then
        return
    end
    
    local direction_x = (entity_pos.x - cause_pos.x) / distance
    local direction_y = (entity_pos.y - cause_pos.y) / distance
    
    local new_pos = {
        x = cause_pos.x + direction_x * pull_distance,
        y = cause_pos.y + direction_y * pull_distance
    }
    
    local safe_position = surface.find_non_colliding_position(cause.name, new_pos, 3, 0.5)
    if safe_position then
        cause.teleport(safe_position)
    end
end

local function warrior_heal(entity, damage)
    create_flying_text(entity, 'amap.flying_text_heal')
    
    local heal_amount = damage * 0.5
    entity.health = entity.health + heal_amount
end

local function warrior_reflect(entity, cause, damage)
    create_flying_text(entity, 'amap.flying_text_reflect')
    
    if not (cause and cause.valid) then return end

    local base_damage = 30
    local laser_damage_bonus = game.forces[entity.force.name].get_gun_speed_modifier('laser') + 1
    local damage = base_damage * laser_damage_bonus

    cause.damage(damage, entity.force.name, 'laser')
end

local function warrior_summon(entity, cause, damage)
    create_flying_text(entity, 'amap.flying_text_summon')
    
    local surface = entity.surface
    local position = entity.position

    local safe_position = surface.find_non_colliding_position(entity.name, position, 5, 0.5)
    if safe_position then
        for i = 1, 3 do
            surface.create_entity {
                name = entity.name,
                position = safe_position,
                force = entity.force.name
            }
        end
    end
end

local function warrior_aoe_damage(entity, cause, damage)
    create_flying_text(entity, 'amap.flying_text_aoe_damage')
    
    if not (cause and cause.valid) then return end

    local surface = entity.surface
    local position = cause.position
    local radius = 7

    local base_damage = 40
    local laser_damage_bonus = game.forces[entity.force.name].get_gun_speed_modifier('laser') + 1
    local damage = base_damage * laser_damage_bonus

    local target_force = get_opposite_force(entity.force.name)
    local players = find_nearby_entities(surface, position, radius, target_force)

    for _, player in pairs(players) do
        if player and player.valid then
            player.damage(damage, entity.force.name, 'laser')
        end
    end
end

local function warrior_tesla_stun(entity, cause, damage)
    
   
    if not (cause and cause.valid) then return end

    local surface = entity.surface
    local position = entity.position
    if cause.type == 'unit' or cause.type == 'character' or cause.type == 'spider-unit' then
        surface.create_entity {
            name = 'tesla-turret-stun',
            position = position,
            target = cause,
            speed = 1,
            force = entity.force.name
        }
         create_flying_text(entity, 'amap.flying_text_tesla_stun')
    end
end


local fire_missile_token = Token.register(function(data)
    if not data.surface.valid then
        return
    end

    local bomb_x = math.random(data.area.left_top.x, data.area.right_bottom.x)
    local bomb_y = math.random(data.area.left_top.y, data.area.right_bottom.y)
    local bomb_position = {x = bomb_x, y = bomb_y}

    local speed = math.random(8, 12) / 10

    data.surface.create_entity({
        name = 'explosive-rocket',
        position = data.source_position,
        force = data.force,
        source = data.entity and data.entity.valid and data.entity or nil,
        target = bomb_position,
        speed = speed
    })
end)

local function warrior_airstrike(entity, cause, damage)
    local surface = entity.surface
    local position = entity.position
    local radius = 10

    local target_position = position
    if cause and cause.valid then
        target_position = cause.position
    end

    local area = {
        left_top = {
            x = target_position.x - radius,
            y = target_position.y - radius
        },
        right_bottom = {
            x = target_position.x + radius,
            y = target_position.y + radius
        }
    }

    for i = 1, 10 do
        local delay = math.random(5, 30)
        Task.set_timeout_in_ticks(delay, fire_missile_token, {
            surface = surface,
            area = area,
            entity = entity,
            source_position = position,
            force = entity.force.name
        })
    end
     create_flying_text(entity, 'amap.flying_text_airstrike')
end


-- 先定义 Token
local warrior_rocket_token = Token.register(function(data)
    if not data.surface.valid then
        return
    end

    data.surface.create_entity({
        name = 'rocket',
        position = data.position,
        force = data.force,
        source = data.position,
        target = data.target_pos,
        speed = 1
    })
end)

-- 修改 warrior_rockets 函数
local function warrior_rockets(entity, cause, damage)
    local surface = entity.surface
    local position = entity.position
    local radius = 20

    local target = cause
    if not (target and target.valid) then
        local target_force = get_opposite_force(entity.force.name)
        local players = find_nearby_entities(surface, position, radius, target_force)

        if #players > 0 then
            target = players[math.random(#players)]
        end
    end

    if target and target.valid then
        create_flying_text(entity, 'amap.flying_text_rockets')
        for i = 1, 3 do
            local delay = i * 10
            Task.set_timeout_in_ticks(delay, warrior_rocket_token, {
                surface = entity.surface,
                position = entity.position,
                entity = entity,
                target_pos = target.position,
                force = entity.force.name
            })
        end
    end
end

local warrior_skills = {
    skill_pull = function(entity, cause, damage)
        warrior_pull(entity, cause, damage)
    end,
    skill_reflect = function(entity, cause, damage)
        warrior_reflect(entity, cause, damage)
    end,
    skill_summon = function(entity, cause, damage)
        warrior_summon(entity, cause, damage)
    end,
    skill_airstrike = function(entity, cause, damage)
        warrior_airstrike(entity, cause, damage)
    end,
   
}

local warrior_offensive_skills = {
    skill_tesla_stun = function(entity, target, damage)
        warrior_tesla_stun(entity, target, damage)
    end,
    skill_aoe_damage = function(entity, target, damage)
        warrior_aoe_damage(entity, target, damage)
    end,
    skill_heal = function(entity, cause, damage)
        warrior_heal(entity, damage)
    end, 
    skill_rockets = function(entity, cause, damage)
        warrior_rockets(entity, cause, damage)
    end
}

local warrior_skill_keys = {
    'skill_pull',
    'skill_reflect',
    'skill_summon',
    'skill_airstrike',
    'skill_tesla_stun',
    'skill_aoe_damage',
    'skill_heal',
    'skill_rockets'

}

local function on_entity_damaged(event)
    local entity = event.entity
    if not (entity and entity.valid) then return end

    local cause = event.cause
    if not (cause and cause.valid) then return end

    local unit_number = entity.unit_number
    if not unit_number then return end

    local cause_unit_number = cause.unit_number
    if cause_unit_number and this.warrior_biter_units[cause_unit_number] then
        if math.random(4) == 1 then
            local skill_key = warrior_skill_keys[math.random(#warrior_skill_keys)]
            local skill_func = warrior_skills[skill_key]
            if skill_func then
                skill_func(cause, entity, event.final_damage_amount)
            end
        end
    end
end

Event.add(defines.events.on_entity_damaged, on_entity_damaged, {
    {filter = "type", type = 'character'}, 
    {filter = "type", type = 'electric-turret'}
    })

-- 生成过滤器列表

Event.add(defines.events.on_entity_died, on_entity_died)

return Public
