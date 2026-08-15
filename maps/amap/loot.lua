local LootRaffle = require 'functions.loot_raffle'

local Public = {}
local abs = math.abs
local floor = math.floor
local sqrt = math.sqrt

local blacklist = {
    ['atomic-bomb'] = true,
    ['car'] = true,
    ['tank'] = true,
    ['spidertron'] = true,
    ['artillery-wagon'] = true,
    ['artillery-turret'] = true,
    ['discharge-defense-equipment'] = true,
    ['discharge-defense-remote'] = true,
    ['flamethrower-turret'] = true,
    ['locomotive'] = true,
    ['cargo-wagon'] = true,
    ['fluid-wagon'] = true,
}

function Public.get_distance(position)
    local difficulty = sqrt(position.x ^ 2 + position.y ^ 2) * 0.0001
    return difficulty
end

function Public.add(surface, position, chest, mult)
  local x= position.x
  local y = position.y
  local dist = math.sqrt(x*x+y*y)
    local budget = 48 + dist*1.45
    budget = budget * math.random(25, 175) * 0.01

    -- 物品数量倍率（世界21 熔岩之心火星区 ×3 由调用方 rand_box 传入）
    if mult and mult > 1 then
      budget = budget * mult
    end

    if math.random(1, 128) == 1 then
        budget = budget * 4
        chest = 'crash-site-chest-' .. math.random(1, 2)
    end
    if math.random(1, 256) == 1 then
        budget = budget * 4
        chest = 'crash-site-chest-' .. math.random(1, 2)
    end

    budget = floor(budget) + 1

    local amount = math.random(1, 5)
    local base_amount = 12 * amount
    local distance_mod = Public.get_distance(position)

    local result = base_amount + budget + distance_mod

    local c = prototypes.entity[chest]
    local slots = c.get_inventory_size(defines.inventory.chest)

    local item_stacks = LootRaffle.roll(result, slots, blacklist)
    local container = surface.create_entity({name = chest, position = position, force = 'neutral'})
    for _, item_stack in pairs(item_stacks) do
        container.insert(item_stack)
    end


    if math.random(1, 8) == 1 then
        container.insert({name = 'coin', count = math.random(1, 32)})
    elseif math.random(1, 32) == 1 then
        container.insert({name = 'coin', count = math.random(1, 128)})
    elseif math.random(1, 128) == 1 then
        container.insert({name = 'coin', count = math.random(1, 256)})
    end

    for _ = 1, 3, 1 do
        if math.random(1, 8) == 1 then
            container.insert({name = 'explosives', count = math.random(25, 50)})
        else
            break
        end
    end
end

function Public.add_rare(surface, position, chest, magic)
    local budget = magic * 33
    budget = budget * math.random(25, 175) * 0.01

    if math.random(1, 128) == 1 then
        budget = budget * 6
        chest = 'crash-site-chest-' .. math.random(1, 2)
    end
    if math.random(1, 128) == 1 then
        budget = budget * 6
        chest = 'crash-site-chest-' .. math.random(1, 2)
    end

    local amount = math.random(1, 5)
    local base_amount = 12 * amount
    local distance_mod = Public.get_distance(position)

    budget = floor(budget) + 1

    local result = base_amount + budget + distance_mod

    local c = prototypes.entity[chest]
    local slots = c.get_inventory_size(defines.inventory.chest)

    local item_stacks = LootRaffle.roll(result, slots, blacklist)
    local container = surface.create_entity({name = chest, position = position, force = 'neutral'})
    for _, item_stack in pairs(item_stacks) do
        container.insert(item_stack)
    end
    container.minable_flag = false

    for _ = 1, 3, 1 do
        if math.random(1, 8) == 1 then
            container.insert({name = 'explosives', count = math.random(25, 50)})
        else
            break
        end
    end
end

function Public.cool(surface, position, chest, magic)
    local budget = magic * 48 + abs(position.y) * 1.75
    budget = budget * math.random(25, 175) * 0.01

    if math.random(1, 128) == 1 then
        budget = budget * 6
        chest = 'crash-site-chest-' .. math.random(1, 2)
    end
    if math.random(1, 128) == 1 then
        budget = budget * 6
        chest = 'crash-site-chest-' .. math.random(1, 2)
    end

    local amount = math.random(1, 5)
    local base_amount = 12 * amount
    local distance_mod = Public.get_distance(position)

    budget = floor(budget) + 1

    local result = base_amount + budget + distance_mod

    local c = prototypes.entity[chest]
    local slots = c.get_inventory_size(defines.inventory.chest)

    local item_stacks = LootRaffle.roll(result, slots, blacklist)
    local container = surface.create_entity({name = chest, position = position, force = 'neutral'})
    for _, item_stack in pairs(item_stacks) do
        container.insert(item_stack)
    end


    for _ = 1, 3, 1 do
        if math.random(1, 8) == 1 then
            container.insert({name = 'explosives', count = math.random(25, 50)})
        else
            break
        end
    end

    return container
end

function Public.cool_with_quality(surface, position, chest, magic)
    if not script.active_mods['quality'] then 
        return Public.cool(surface, position, chest, magic+100)
    end
    local budget = magic * 48 + abs(position.y) * 1.75
    budget = budget * math.random(25, 175) * 0.01

    if math.random(1, 128) == 1 then
        budget = budget * 6
        chest = 'crash-site-chest-' .. math.random(1, 2)
    end
    if math.random(1, 128) == 1 then
        budget = budget * 6
        chest = 'crash-site-chest-' .. math.random(1, 2)
    end

    local amount = math.random(1, 5)
    local base_amount = 12 * amount
    local distance_mod = Public.get_distance(position)

    budget = floor(budget) + 1

    local result = base_amount + budget + distance_mod

    local c = prototypes.entity[chest]
    local slots = c.get_inventory_size(defines.inventory.chest)

    local item_stacks = LootRaffle.roll(result, slots, blacklist)
    local container = surface.create_entity({name = chest, position = position, force = 'neutral'})
    
    -- 品质升级概率系统
    local quality_upgrades = {
        uncommon = 0.10,  -- 10% 概率升级为普通品质
        rare = 0.05,      -- 5% 概率升级为稀有品质
        epic = 0.03,      -- 3% 概率升级为史诗品质
        legendary = 0.01  -- 1% 概率升级为传说品质
    }
    
    for _, item_stack in pairs(item_stacks) do
        local upgraded = false
        
        -- 按顺序检查品质升级概率（从低到高）
        local roll = math.random()
        if roll <= quality_upgrades.legendary then
            -- 1% 概率升级为传说品质
            container.insert({name = item_stack.name, count = item_stack.count, quality = 'legendary'})
            upgraded = true
        elseif roll <= quality_upgrades.legendary + quality_upgrades.epic then
            -- 3% 概率升级为史诗品质
            container.insert({name = item_stack.name, count = item_stack.count, quality = 'epic'})
            upgraded = true
        elseif roll <= quality_upgrades.legendary + quality_upgrades.epic + quality_upgrades.rare then
            -- 5% 概率升级为稀有品质
            container.insert({name = item_stack.name, count = item_stack.count, quality = 'rare'})
            upgraded = true
        elseif roll <= quality_upgrades.legendary + quality_upgrades.epic + quality_upgrades.rare + quality_upgrades.uncommon then
            -- 10% 概率升级为普通品质
            container.insert({name = item_stack.name, count = item_stack.count, quality = 'uncommon'})
            upgraded = true
        end
        
        -- 如果没有升级，插入普通物品
        if not upgraded then
            container.insert(item_stack)
        end
    end

    for _ = 1, 3, 1 do
        if math.random(1, 8) == 1 then
            container.insert({name = 'explosives', count = math.random(25, 50)})
        else
            break
        end
    end

    return container
end

return Public
