local WPT = require 'maps.amap.table'
local diff = require 'maps.amap.diff'
local Task = require 'utils.task'
local Event = require 'utils.event'
local enemy_arty = require 'maps.amap.enemy_arty'
local WD = require 'modules.wave_defense.table'
local jixianchengshi = {}

local ENERGY_NETWORK_MAX = 1000000
local ENERGY_DECAY_RATE = 1
local ENERGY_UPDATE_INTERVAL = 60
local RECYCLER_EFFICIENCY = 3 -- 回收箱效率（原为4，下调1使该世界更难）

local function get_recycler_crafting_time(item_name, depth)
    local this = WPT.get()
    if not this.recycler_time_cache then
        this.recycler_time_cache = {}
    end


    depth = depth or 0
    if depth > 10 then return 1 end

    if this.recycler_time_cache[item_name] then
        return this.recycler_time_cache[item_name]
    end

    local recipe = prototypes.recipe[item_name]

    if not recipe then
        this.recycler_time_cache[item_name] = 0
        return 0
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
            local sub_time = get_recycler_crafting_time(ingredient.name, depth + 1)
            total_time = total_time + (sub_time * ingredient.amount / product_amount)
        end
    end

    this.recycler_time_cache[item_name] = total_time
    return total_time
end

local function update_laser_turrets()
    local this = WPT.get()
    local energy_network = this.energy_network

    if not energy_network then return end

    if not this.registered_laser_turrets then
        this.registered_laser_turrets = {}
    end

    for unit_number, turret in pairs(this.registered_laser_turrets) do
        if turret and turret.valid then
            if energy_network.active then
                turret.energy =99999999999
            end
        else
            this.registered_laser_turrets[unit_number] = nil
        end
    end
end

local function collect_energy_recyclers()
    local this = WPT.get()
    local energy_network = this.energy_network

    if not energy_network then return end

    local recycler_data = this.energy_recycler
    if not recycler_data then return end
    local quality_multipliers = {
        normal = 1,
        uncommon = 1.5,
        rare = 2,
        epic = 2.5,
        legendary = 3
    }
    local recycler = recycler_data.entity
    if recycler and recycler.valid then
        local inventory = recycler.get_inventory(defines.inventory.chest)
        if inventory then
            local items = inventory.get_contents()
            for _, item_data in pairs(items) do
                if energy_network.energy >= energy_network.max_energy then
                    return
                end
                local item_name = item_data.name
                local count = item_data.count
                local quality = item_data.quality

                local crafting_time = get_recycler_crafting_time(item_name)
                local quality_multiplier = quality_multipliers[quality] or 1
                local energy = crafting_time * count * RECYCLER_EFFICIENCY * quality_multiplier
                energy_network.energy = energy_network.energy + energy
                inventory.remove({name = item_name, count = count, quality = quality})
            end
        end
    end
end

local function update_recycler_display()
    local this = WPT.get()
    local energy_network = this.energy_network

    if not energy_network then return end

    local recycler_data = this.energy_recycler
    if not recycler_data then return end

    local recycler = recycler_data.entity
    if not recycler or not recycler.valid then return end

    local energy_percent = math.floor((energy_network.energy / energy_network.max_energy) * 100)
    local energy_text = string.format("能量网: %d/%d (%d%%)", energy_network.energy, energy_network.max_energy, energy_percent)

    recycler_data.render_id = rendering.draw_text{
        text = energy_text,
        surface = recycler.surface,
        target = recycler,
        target_offset = {0, -2.5},
        color = {0, 1, 0.5},
        scale = 1.2,
        alignment = "center",
        time_to_live = 61
    }
end

local function check_fortress_count()
    local this = WPT.get()
    return this.baolei_count or 0
end

local function get_active_fortresses()
    local arty_data = enemy_arty.get()
    local fortresses = {}

    if arty_data.arty then
        for baolei_id, data in pairs(arty_data.arty) do
            if data.roboport and data.roboport.valid then
                table.insert(fortresses, {
                    id = baolei_id,
                    roboport = data.roboport,
                    position = data.roboport.position,
                    surface = data.roboport.surface
                })
            end
        end
    end

    return fortresses
end

local function destroy_fortress_and_fire(fortress_data)
    local arty_data = enemy_arty.get()
    if not fortress_data or not fortress_data.id then return end
    local baolei_id = fortress_data.id


        -- 1. 使用专用的清理表杀死所有关联实体（包括墙、指令枢纽、箱子等）
    if arty_data.neet_to_kill and arty_data.neet_to_kill[baolei_id] then
        for _, entity in pairs(arty_data.neet_to_kill[baolei_id]) do
            if entity and entity.valid then
                -- 先取消不可摧毁状态（防止某些建筑设置了不可摧毁）
                entity.destructible = true
                entity.die()
            end
        end
        arty_data.neet_to_kill[baolei_id] = nil
    end

    -- 2. 单独摧毁机器人平台（roboport 不在 neet_to_kill 表中）
    if arty_data.arty and arty_data.arty[baolei_id] and arty_data.arty[baolei_id].roboport then
        local roboport = arty_data.arty[baolei_id].roboport
        if roboport and roboport.valid then
            roboport.destructible = true
            roboport.die()
        end
    end

    -- 3. 搜索区域内所有敌方实体并摧毁，防止残留
    local surface = fortress_data.surface
    local position = fortress_data.position

    local k = 30
    local area = {
        left_top = {x = position.x - k, y = position.y - k},
        right_bottom = {x = position.x + k, y = position.y + k}
    }
    local enemies = surface.find_entities_filtered({
        area = area,
        force = "enemy"
    })

    local this = WPT.get()
    local first_turret = nil
    if this.registered_laser_turrets then
        local unit_number, turret = next(this.registered_laser_turrets)
        first_turret = turret
    end

    for _, enemy in ipairs(enemies) do
        if enemy and enemy.valid and enemy.health and enemy.health > 0 then
            enemy.destructible = true
            if enemy.name == "land-mine" then
                enemy.destroy()
            else
                enemy.die(game.forces.player, first_turret)
            end
        end
    end

        -- 4. 清理单位映射表（防止 unit_number 残留）
    for unit_number, id in pairs(arty_data.unit) do
        if id == baolei_id then
            arty_data.unit[unit_number] = nil
        end
    end

    -- 5. 清理主数据表
    arty_data.arty[baolei_id] = nil

    -- 6. 额外查找并消灭堡垒附近的钢箱子
    local steel_chests = surface.find_entities_filtered({
        position = position,
        radius = 15,
        name = "steel-chest",
    })
    for _, chest in ipairs(steel_chests) do
        if chest and chest.valid then
            chest.destructible = true
            chest.die()
        end
    end

    -- 7. 查找并清理虫子的 entity-ghost 单位
    local entity_ghosts = surface.find_entities_filtered({
        position = position,
        radius = 30,
        name = "entity-ghost",
        force = "enemy"
    })
    for _, ghost in ipairs(entity_ghosts) do
        if ghost and ghost.valid then
            ghost.destroy()
        end
    end

    -- 9. 清理 roboport_wave 映射表
    if arty_data.roboport_wave then
        for unit_number, wave in pairs(arty_data.roboport_wave) do
            if wave == fortress_data.wave_number then
                arty_data.roboport_wave[unit_number] = nil
            end
        end
    end

    -- 10. 清理 baolei_creation_times 创建时间表
    if arty_data.baolei_creation_times then
        arty_data.baolei_creation_times[baolei_id] = nil
    end

    -- 11. 清理 construction_queue.active_constructions 活跃建造任务
    if arty_data.construction_queue and arty_data.construction_queue.active_constructions then
        arty_data.construction_queue.active_constructions[baolei_id] = nil
    end

    game.print({"amap.baolei_die"})
end

local function get_artillery_charge_max()

    local wave_number = WD.get('wave_number')
    local base_charge = 150000
    local additional_charge = math.floor(wave_number / 100) * 150000
    return base_charge + additional_charge
end

local function get_artillery_charge_rate()
    local wave_number = WD.get('wave_number')
    local base_rate = 300
    local additional_rate = math.floor(wave_number / 100) * 300
    return base_rate + additional_rate
end

local function update_artillery_charging()
    local this = WPT.get()
    local energy_network = this.energy_network
    local fortress_count = check_fortress_count()
    local artillery_charge_max = get_artillery_charge_max()
    local artillery_charge_rate = get_artillery_charge_rate()


    if not this.artillery_charging then
        this.artillery_charging = {
            active = false,
            energy = 0,
            last_fortress_count = 0,
            message_shown = false
        }
    end

    local artillery = this.artillery_charging

    if fortress_count > 0 and not artillery.active then
        artillery.active = true
        artillery.energy = 0
        artillery.message_shown = false
        game.print({"amap.artillery_charge_start", artillery_charge_max, artillery_charge_rate})
    elseif fortress_count == 0 and artillery.active then
        artillery.active = false
        artillery.energy = 0
        artillery.message_shown = false
    end

    if artillery.active then
        local charge_amount = math.min(artillery_charge_rate, artillery_charge_max - artillery.energy)

        if energy_network and energy_network.energy and energy_network.energy >= charge_amount then
            energy_network.energy = energy_network.energy - charge_amount
            artillery.energy = math.floor(artillery.energy + charge_amount)
        elseif energy_network and energy_network.energy and energy_network.energy > 0 then
            local available = energy_network.energy
            energy_network.energy = 0
            artillery.energy = math.floor(artillery.energy + available)
        end

        local recycler_data = this.energy_recycler
        if recycler_data and recycler_data.entity and recycler_data.entity.valid then
            local percent = math.floor((artillery.energy / artillery_charge_max) * 100)
            artillery.render_id = rendering.draw_text{
                text = {"amap.artillery_charge_progress", math.floor(artillery.energy), artillery_charge_max, percent},
                surface = recycler_data.entity.surface,
                target =
                {entity=recycler_data.entity,
                offset = {0, -1}},
                color = {1, 0.5, 0},
                scale = 1.2,
                alignment = "center",
                time_to_live = 61
            }
        end

        if artillery.energy >= artillery_charge_max and not artillery.message_shown then
            artillery.message_shown = true
            game.print({"amap.artillery_charge_complete"})

            local fortresses = get_active_fortresses()
            if #fortresses > 0 then
                local random_fortress = fortresses[math.random(1, #fortresses)]
                destroy_fortress_and_fire(random_fortress)
            end

            artillery.energy = 0
            artillery.message_shown = false
        end
    end
end

local function get_resistance(entity, damage_type)
    local this = WPT.get()
    if not this.resistance_cache then
        this.resistance_cache = {}
    end

    local entity_name = entity.name

    if this.resistance_cache[entity_name] then
        return this.resistance_cache[entity_name]
    end

    local resistances = entity.prototype.resistances
    if not resistances then
        this.resistance_cache[entity_name] = 0
        return 0
    end

    local resistance = resistances[damage_type]
    if not resistance then
        this.resistance_cache[entity_name] = 0
        return 0
    end

    local value = resistance.percent or 0
    this.resistance_cache[entity_name] = value
    return value
end

local function scan_and_kill_enemies_in_area()
    local map = diff.get()
    if map.world ~= 11 then return end

    local this = WPT.get()
    local energy_network = this.energy_network

    if not energy_network or not energy_network.active then return end

    local surface = game.surfaces["nauvis"]
    if not surface or not surface.valid then return end

    local area = {
        left_top = {x = -91, y = -51},
        right_bottom = {x = 91, y = -25}
    }

    local enemies = surface.find_entities_filtered({
        area = area,
        force = "enemy"
    })
    local laser_damage_bonus = game.forces.player.get_ammo_damage_modifier("laser")  or 0
    --local laser_speed_bonus = game.forces.player.get_gun_speed_modifier("laser") or 0

    local damage_multiplier = 1 + laser_damage_bonus--+laser_speed_bonus
    if #enemies == 0 then return end

    local first_unit_number, first_turret = next(this.registered_laser_turrets)
    if not first_turret or not first_turret.valid then return end

    for _, enemy in ipairs(enemies) do
        if enemy and enemy.valid and enemy.health and enemy.health > 10 and enemy.type ~= "spider-leg" then
            local resistance = get_resistance(enemy, "laser")
            local energy_needed = enemy.health / (1 - resistance) / damage_multiplier

            if energy_network.energy >= energy_needed then
                energy_network.energy = energy_network.energy - energy_needed
                enemy.die(game.forces.player, first_turret)
            end
        end
    end
end

local function on_tick(event)
    local map = diff.get()
    if map.world ~= 11 then return end

    local tick = event.tick
    local this = WPT.get()
    local energy_network = this.energy_network

    if not energy_network then return end

    if tick % ENERGY_UPDATE_INTERVAL == 0 then
        if energy_network.energy <= 0 then
            energy_network.energy = 0
            energy_network.active = false
        else
            energy_network.active = true
        end

        update_laser_turrets()
    end

    if tick % 30 == 0 then
        scan_and_kill_enemies_in_area()
    end

    if tick % 60 == 0 then
        collect_energy_recyclers()
        update_recycler_display()
        update_artillery_charging()
    end
end




local function on_entity_damaged(event)
    local map = diff.get()
    if map.world ~= 11 then return end

    local entity = event.entity
    if not entity or not entity.valid then return end

    local this = WPT.get()
    local energy_network = this.energy_network

    if not energy_network or not energy_network.active then return end
    local unit_number = entity.unit_number

    if this.registered_laser_turrets[unit_number] then
        local damage_amount = event.final_damage_amount or 0
        energy_network.energy = math.max(0, energy_network.energy - damage_amount)
        entity.health = entity.max_health
    end
end

function jixianchengshi.get_energy_network_status()
    local this = WPT.get()
    return this.energy_network or {
        active = false,
        energy = 0,
        max_energy = ENERGY_NETWORK_MAX,
        decay_rate = ENERGY_DECAY_RATE
    }
end

function jixianchengshi.add_energy(amount)
    local this = WPT.get()
    if not this.energy_network then
        this.energy_network = {
            active = true,
            energy = 0,
            max_energy = ENERGY_NETWORK_MAX,
            decay_rate = ENERGY_DECAY_RATE,
            last_update = 0
        }
    end
    this.energy_network.energy = math.min(this.energy_network.energy + amount, this.energy_network.max_energy)
    if this.energy_network.energy > 0 then
        this.energy_network.active = true
    end
end

function jixianchengshi.register_laser_turret(turret)
    if not turret or not turret.valid then return false end
    if turret.name ~= "laser-turret" then return false end

    local this = WPT.get()
    if not this.registered_laser_turrets then
        this.registered_laser_turrets = {}
    end

    local unit_number = turret.unit_number
    if not unit_number then return false end

    this.registered_laser_turrets[unit_number] = turret
    return true
end

function jixianchengshi.unregister_laser_turret(turret)
    if not turret or not turret.valid then return false end

    local this = WPT.get()
    if not this.registered_laser_turrets then return false end

    local unit_number = turret.unit_number
    if not unit_number then return false end

    this.registered_laser_turrets[unit_number] = nil
    return true
end

Event.add(defines.events.on_entity_damaged, on_entity_damaged, {
    {filter = "type", type = 'character'},
    {filter = "type", type = 'electric-turret'}
    })
Event.on_nth_tick(60, on_tick)

return jixianchengshi
