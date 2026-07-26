local Public = {}
local market = {}

local random = math.random
local floor = math.floor
local WPT = require 'maps.amap.table'


local blacklist = {
  ['cargo-wagon'] = true,
  ['locomotive'] = true,
  ['fluid-wagon'] = true,
  ['artillery-wagon'] = true,
  ['artillery-turret'] = true,
  --  ['land-mine'] = true,
  ['discharge-defense-remote'] = true,
    ['discharge-defense-equipment'] = true,
   ['car'] = true,
   ['tank'] = true,
   ['spidertron'] = true,
   ['atomic-bomb'] = true,
   ['flamethrower-turret'] = true
}

market.weapons = {
    ['submachine-gun'] = {value = 50, rarity = 2},
    ['shotgun'] = {value = 40, rarity = 2},
    ['tank-machine-gun'] = {value = 600, rarity = 3},
    ['combat-shotgun'] = {value = 400, rarity = 5},
    ['rocket-launcher'] = {value = 500, rarity = 5},
    ['flamethrower-turret'] = {value = 2000, rarity = 5},
    ['land-mine'] = {value = 10, rarity = 4}
}

market.ammo = {
    ['firearm-magazine'] = {value = 3, rarity = 1},
    ['piercing-rounds-magazine'] = {value = 6, rarity = 4},
    ['uranium-rounds-magazine'] = {value = 20, rarity = 8},
    ['shotgun-shell'] = {value = 3, rarity = 1},
    ['piercing-shotgun-shell'] = {value = 8, rarity = 5},
    ['cannon-shell'] = {value = 8, rarity = 4},
    ['explosive-cannon-shell'] = {value = 12, rarity = 5},
    ['uranium-cannon-shell'] = {value = 16, rarity = 7},
    ['explosive-uranium-cannon-shell'] = {value = 20, rarity = 8},
    ['artillery-shell'] = {value = 64, rarity = 300},
    ['rocket'] = {value = 45, rarity = 7},
    ['explosive-rocket'] = {value = 50, rarity = 7},
    ['atomic-bomb'] = {value = 15000, rarity = 10},
    ['flamethrower-ammo'] = {value = 20, rarity = 6},
    ['explosives'] = {value = 3, rarity = 1}
}

market.caspules = {
    ['grenade'] = {value = 16, rarity = 2},
    ['cluster-grenade'] = {value = 90, rarity = 6},
    ['poison-capsule'] = {value = 50, rarity = 6},
    ['slowdown-capsule'] = {value = 8, rarity = 1},
    ['defender-capsule'] = {value = 10, rarity = 1},
    ['distractor-capsule'] = {value = 30, rarity = 3},
    ['destroyer-capsule'] = {value = 90, rarity = 5},
    ['discharge-defense-remote'] = {value = 7000, rarity = 8},
    ['raw-fish'] = {value = 7, rarity = 1},
    ['cliff-explosives'] = {value = 70, rarity = 5}
}

market.armor = {
    ['light-armor'] = {value = 25, rarity = 1},
    ['heavy-armor'] = {value = 250, rarity = 4},
    ['modular-armor'] = {value = 750, rarity = 5},
    ['power-armor'] = {value = 5000, rarity = 6},
    ['power-armor-mk2'] = {value = 35000, rarity = 10},
    ['mech-armor'] = {value = 55000, rarity = 12}
}

market.equipment = {
    ['solar-panel-equipment'] = {value = 240, rarity = 3},
    ['energy-shield-equipment'] = {value = 400, rarity = 6},
    ['energy-shield-mk2-equipment'] = {value = 4000, rarity = 8},
    ['battery-equipment'] = {value = 160, rarity = 2},
    ['battery-mk2-equipment'] = {value = 5000, rarity = 8},
    ['personal-laser-defense-equipment'] = {value = 4000, rarity = 7},
    ['discharge-defense-equipment'] = {value = 7000, rarity = 8},
    ['belt-immunity-equipment'] = {value = 200, rarity = 1},
    ['exoskeleton-equipment'] = {value = 1000, rarity = 3},
    ['personal-roboport-equipment'] = {value = 1000, rarity = 3},
    ['personal-roboport-mk2-equipment'] = {value = 5000, rarity = 8},
    ['night-vision-equipment'] = {value = 250, rarity = 1}
}

market.defense = {
    ['stone-wall'] = {value = 4, rarity = 1},
    ['gate'] = {value = 8, rarity = 1},
    ['repair-pack'] = {value = 8, rarity = 1},
    ['gun-turret'] = {value = 64, rarity = 1},
    ['laser-turret'] = {value = 1024, rarity = 6},
    ['flamethrower-turret'] = {value = 2048, rarity = 6},
    ['artillery-turret'] = {value = 15192, rarity = 8}
}

market.logistic = {
    ['wooden-chest'] = {value = 3, rarity = 1},
    ['iron-chest'] = {value = 10, rarity = 2},
    ['steel-chest'] = {value = 24, rarity = 3},
    ['storage-tank'] = {value = 32, rarity = 4},
    ['transport-belt'] = {value = 4, rarity = 1},
    ['fast-transport-belt'] = {value = 8, rarity = 4},
    ['express-transport-belt'] = {value = 24, rarity = 7},
    ['underground-belt'] = {value = 8, rarity = 1},
    ['fast-underground-belt'] = {value = 32, rarity = 4},
    ['express-underground-belt'] = {value = 64, rarity = 7},
    ['splitter'] = {value = 16, rarity = 1},
    ['fast-splitter'] = {value = 48, rarity = 4},
    ['express-splitter'] = {value = 128, rarity = 7},
    ['loader'] = {value = 256, rarity = 2},
    ['fast-loader'] = {value = 512, rarity = 5},
    ['express-loader'] = {value = 768, rarity = 8},
    ['burner-inserter'] = {value = 4, rarity = 1},
    ['inserter'] = {value = 8, rarity = 1},
    ['long-handed-inserter'] = {value = 12, rarity = 2},
    ['fast-inserter'] = {value = 16, rarity = 4},
    ['bulk-inserter'] = {value = 32, rarity = 5},
    ['small-electric-pole'] = {value = 2, rarity = 1},
    ['medium-electric-pole'] = {value = 12, rarity = 4},
    ['big-electric-pole'] = {value = 24, rarity = 5},
    ['substation'] = {value = 96, rarity = 8},
    ['pipe'] = {value = 2, rarity = 1},
    ['pipe-to-ground'] = {value = 8, rarity = 1},
    ['pump'] = {value = 16, rarity = 4},
    ['logistic-robot'] = {value = 28, rarity = 5},
    ['construction-robot'] = {value = 28, rarity = 3},
    ['active-provider-chest'] = {value = 128, rarity = 7},
    ['passive-provider-chest'] = {value = 128, rarity = 6},
    ['storage-chest'] = {value = 128, rarity = 6},
    ['buffer-chest'] = {value = 128, rarity = 7},
    ['requester-chest'] = {value = 128, rarity = 7},
    ['roboport'] = {value = 4096, rarity = 8},
    ['beacon'] = {value = 5096, rarity = 8}
}

market.vehicles = {
    ['rail'] = {value = 4, rarity = 1},
    ['train-stop'] = {value = 32, rarity = 3},
    ['rail-signal'] = {value = 8, rarity = 5},
    ['rail-chain-signal'] = {value = 8, rarity = 5},
    ['locomotive'] = {value = 400, rarity = 4},
    ['cargo-wagon'] = {value = 200, rarity = 4},
    ['fluid-wagon'] = {value = 300, rarity = 5},
    ['artillery-wagon'] = {value = 8192, rarity = 8},
    ['car'] = {value = 80, rarity = 1},
    ['tank'] = {value = 1800, rarity = 5}
}

market.wire = {
    ['small-lamp'] = {value = 4, rarity = 1},
    ['arithmetic-combinator'] = {value = 16, rarity = 1},
    ['decider-combinator'] = {value = 16, rarity = 1},
    ['constant-combinator'] = {value = 16, rarity = 1},
    ['power-switch'] = {value = 16, rarity = 1},
    ['programmable-speaker'] = {value = 24, rarity = 1},
    ['landfill'] = {value = 5, rarity = 3}
}
--2.0板块：
market.logistic_2_0 = {
    -- 堆叠机械臂 (Stack Inserter) 在 2.0 中是绿色的，负责在带子上堆叠物品
    ['stack-inserter'] = {value = 72, rarity = 6}, -- 堆叠机械臂
    -- 原 1.0 的白色堆叠机械臂现在改名为大容量机械臂 (Bulk Inserter)
    ['bulk-inserter'] = {value = 48, rarity = 5}, -- 大容量机械臂
    
    -- 涡轮传送带 (Turbo Belts - 绿色)
    ['turbo-transport-belt'] = {value = 120, rarity = 9}, -- 涡轮传送带
    ['turbo-underground-belt'] = {value = 480, rarity = 9}, -- 涡轮地下传送带
    ['turbo-splitter'] = {value = 960, rarity = 9}, -- 涡分流速器
    
    -- 轨道交通扩展 (Elevated Rails)
    ['rail-ramp'] = {value = 225, rarity = 5}, -- 铁路坡道
    ['rail-support'] = {value = 1000, rarity = 5}, -- 铁路支架
}
market.space_platform = {
    ['space-platform-foundation'] = {value = 150, rarity = 6}, -- 空间平台地基
    ['cargo-bay'] = {value = 600, rarity = 6}, -- 货舱
    ['asteroid-collector'] = {value = 1000, rarity = 6}, -- 小行星收集器
    ['crusher'] = {value = 525, rarity = 6}, -- 碎石机
    ['thruster'] = {value = 1800, rarity = 7} -- 推进器
}
market.planetary_buildings = {
    -- 熔岩星 (Vulcanus)
    ['foundry'] = {value = 15000, rarity = 7}, -- 大熔炉
    ['big-mining-drill'] = {value = 5000, rarity = 7}, -- 大矿机
    
    -- 闪电星 (Fulgora)
    ['lightning-rod'] = {value = 450, rarity = 6}, -- 避雷针
    ['electromagnetic-plant'] = {value = 25000, rarity = 7}, -- 电磁工厂
    ['recycler'] = {value = 1500, rarity = 6}, -- 回收机
    
    -- 沼泽星 (Gleba)
    ['heating-tower'] = {value = 900, rarity = 6}, -- 加热塔
    ['agricultural-tower'] = {value = 1200, rarity = 6}, -- 农业塔
    ['nutrients'] = {value = 6, rarity = 5}, -- 营养液
    ['bioflux'] = {value = 250, rarity = 5}, -- 生物流
    
    -- 草星 (Agricultura)
    ['artificial-yumako-soil'] = {value = 400, rarity = 6}, -- 人造土
    ['artificial-jellynut-soil'] = {value = 400, rarity = 6} -- 人造土2级
}

market.new_weapons = {
    ['railgun'] = {value = 20000, rarity = 9}, -- 电磁炮
    ['railgun-ammo'] = {value = 500, rarity = 8}, -- 电磁炮弹药
    ['tesla-turret'] = {value = 30750, rarity = 8}, -- 特斯拉炮塔
    ['tesla-ammo'] = {value = 170, rarity = 7}, -- 特斯拉弹药
    ['teslagun'] = {value = 6000, rarity = 8}, -- 特斯拉枪
    ['rocket-turret'] = {value = 10000, rarity = 8}, -- 火箭炮塔
    ['captive-biter-spawner'] = {value = 22500, rarity = 9} -- 捕获的虫巢
}
market.quality_modules = {
    ['quality-module'] = {value = 750, rarity = 5}, -- 品质模块
    ['quality-module-2'] = {value = 3750, rarity = 7}, -- 品质模块2级
    ['quality-module-3'] = {value = 18750, rarity = 9} -- 品质模块3级
}

market.equipment_2_0 = {
    ['battery-mk3-equipment'] = {value = 17500, rarity = 10}, -- 电池MK3装备（冰星解锁）
    ['fission-reactor-equipment'] = {value = 9500, rarity = 8}, -- 裂变反应堆装备（原1.0聚变反应堆）
    ['fusion-reactor-equipment'] = {value = 27500, rarity = 12}, -- 聚变反应堆装备（顶级）
    ['toolbelt-equipment'] = {value = 3000, rarity = 7} -- 工具栏装备
}


local function get_types()
    local types = {}
    for k, _ in pairs(market) do
        types[#types + 1] = k
    end
    return types
end

local function get_resource_market_sells()
    local sells = {
        {price = {{name = 'coin', count = random(5, 10)}}, offer = {type = 'give-item', item = 'wood', count = 50}},
        {price = {{name = 'coin', count = random(5, 10)}}, offer = {type = 'give-item', item = 'iron-ore', count = 50}},
        {price = {{name = 'coin', count = random(5, 10)}}, offer = {type = 'give-item', item = 'copper-ore', count = 50}},
        {price = {{name = 'coin', count = random(5, 10)}}, offer = {type = 'give-item', item = 'stone', count = 50}},
        {price = {{name = 'coin', count = random(5, 10)}}, offer = {type = 'give-item', item = 'coal', count = 50}},
        {price = {{name = 'coin', count = random(8, 16)}}, offer = {type = 'give-item', item = 'uranium-ore', count = 50}},
        {price = {{name = 'coin', count = random(2, 4)}}, offer = {type = 'give-item', item = 'crude-oil-barrel', count = 1}}
    }
    table.shuffle_table(sells)
    return sells
end

local function get_resource_market_buys()
    local buys = {
        {price = {{name = 'wood', count = random(10, 12)}}, offer = {type = 'give-item', item = 'coin'}},
        {price = {{name = 'iron-ore', count = random(10, 12)}}, offer = {type = 'give-item', item = 'coin'}},
        {price = {{name = 'copper-ore', count = random(10, 12)}}, offer = {type = 'give-item', item = 'coin'}},
        {price = {{name = 'stone', count = random(10, 12)}}, offer = {type = 'give-item', item = 'coin'}},
        {price = {{name = 'coal', count = random(10, 12)}}, offer = {type = 'give-item', item = 'coin'}},
        {price = {{name = 'uranium-ore', count = random(8, 10)}}, offer = {type = 'give-item', item = 'coin'}},
        {price = {{name = 'water-barrel', count = 1}}, offer = {type = 'give-item', item = 'coin', count = random(1, 2)}},
        {price = {{name = 'lubricant-barrel', count = 1}}, offer = {type = 'give-item', item = 'coin', count = random(3, 6)}},
        {price = {{name = 'sulfuric-acid-barrel', count = 1}}, offer = {type = 'give-item', item = 'coin', count = random(4, 8)}},
        {price = {{name = 'light-oil-barrel', count = 1}}, offer = {type = 'give-item', item = 'coin', count = random(2, 4)}},
        {price = {{name = 'heavy-oil-barrel', count = 1}}, offer = {type = 'give-item', item = 'coin', count = random(2, 4)}},
        {price = {{name = 'petroleum-gas-barrel', count = 1}}, offer = {type = 'give-item', item = 'coin', count = random(3, 5)}}
    }
    table.shuffle_table(buys)
    return buys
end

local function get_market_item_list(rarity, min_rarity)
    if rarity < 1 then
        rarity = 1
    end
    if rarity > 12 then
        rarity = 12
    end
    
    if not min_rarity then
        min_rarity = 1
    end
    
    -- 获取当前世界编号
    local this = WPT.get()
    local world_number = this.world_number or 1
    local disable_atomic_bomb = (world_number == 2 or world_number == 7 or world_number == 8)
    
    local types = get_types()
    local list = {}
    for i = 1, #types do
        local branch = market[types[i]]
        for k, item in pairs(branch) do
            if item.rarity <= rarity and item.rarity >= min_rarity then
                -- 如果是世界2、7或8，且是核弹，则跳过
                if disable_atomic_bomb and k == 'atomic-bomb' then
                    goto continue
                end
                
                local price = random(floor(item.value * 0.8), floor(item.value * 1.2))
                if price < 1 then
                    price = 1
                end
                if price > 64000 then
                    price = 64000
                end
                list[#list + 1] = {price = {{name = 'coin', count = price}}, offer = {type = 'give-item', item = k}}
            end
            ::continue::
        end
    end
    if #list == 0 then
        return false
    end
    return list
end

function Public.get_random_item(rarity, sell, buy, min_rarity)
    rarity = rarity or 0
    local items = get_market_item_list(rarity, min_rarity)
    if not items then
        return
    end
    if #items > 0 then
        table.shuffle_table(items)
    end

    -- 获取当前世界编号
    local this = WPT.get()
    local world_number = this.world_number or 1
    local disable_atomic_bomb = (world_number == 2 or world_number == 7 or world_number == 8)

    local items_return = {}
    for i = 1, 25, 1 do
        local item = items[i]
        if not item then
            break
        end
        -- 如果是世界2、7或8，且是核弹，则跳过
        if disable_atomic_bomb and item.offer.item == 'atomic-bomb' then
            goto continue
        end
        if not blacklist[item.offer.item]   then
                items_return[#items_return + 1] = items[i]
        end
        ::continue::
    end

    if sell then
        local sells = get_resource_market_sells()
        for i = 1, random(1, 25), 1 do
            items_return[#items_return + 1] = sells[i]
        end
    end

    if buy then
        local buys = get_resource_market_buys()
        for i = 1, random(1, 25), 1 do
            items_return[#items_return + 1] = buys[i]
        end
    end

    return items_return
end

function Public.mountain_market(surface, position, rarity, buy)
    if (rarity <= 1)
	then
	rarity = 1
	end
	
    -- 获取当前世界编号
    local this = WPT.get()
    local world_number = this.world_number or 1
    local disable_atomic_bomb = (world_number == 2 or world_number == 7 or world_number == 8)
    
--  game.print(rarity)
    local types = get_types()
    table.shuffle_table(types)
    local items = get_market_item_list(rarity)
    if not items then
        return
    end
    if #items > 0 then
        table.shuffle_table(items)
    end
    local mrk = surface.create_entity({name = 'market', position = position, force = 'neutral'})
    mrk.destructible = false
    for i = 1, random(5, 10), 1 do
        local item = items[i]
        if not item then
            break
        end
        -- 如果是世界2、7或8，且是核弹，则跳过
        if disable_atomic_bomb and item.offer.item == 'atomic-bomb' then
            goto continue
        end
        if not blacklist[item.offer.item]  then
            mrk.add_market_item(items[i])
        end
        ::continue::
    end

    local sells = get_resource_market_sells()
    for i = 1, random(1, 3), 1 do
        mrk.add_market_item(sells[i])
    end

    if buy then
        local buys = get_resource_market_buys()
        for i = 1, random(1, 3), 1 do
            mrk.add_market_item(buys[i])
        end
    end

    return mrk
end

-- 取物品的基准市场价值（供伪建筑等按"商品价格"计费）
function Public.get_item_value(name)
    if not name then return nil end
    for _, tbl in pairs(market) do
        if type(tbl) == 'table' and tbl[name] and type(tbl[name]) == 'table' then
            return tbl[name].value
        end
    end
    return nil
end

return Public
