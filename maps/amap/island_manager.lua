local WPT = require 'maps.amap.table'
local Event = require 'utils.event'
local enemy_arty = require 'maps.amap.enemy_arty'
local rpgtable = require 'modules.rpg.table'
local MT = require 'maps.amap.basic_markets'
local functions = require 'maps.amap.functions'
local Dungeon = require 'maps.amap.dungeon'

local Public = {}

local function insert_coin_to_player(player, coin_count)
    if not player or not player.valid then
        return false
    end

    if not coin_count or coin_count <= 0 then
        return false
    end

    local this = WPT.get()
    local dungeon_data = nil
    if this.dungeons then
        dungeon_data = this.dungeons[player.index]
    end

    local target_character = player.character

    if dungeon_data and dungeon_data.active and dungeon_data.original_character and dungeon_data.original_character.valid then
        target_character = dungeon_data.original_character
    end

    if not target_character or not target_character.valid then
        return false
    end

    local inserted = target_character.insert({name = 'coin', count = coin_count})
    return inserted > 0
end

local function new_print(player, text)
    local this = WPT.get()
    local tick = game.tick
    local player_index = player.index

    if not this.print_cooldown then
        this.print_cooldown = {}
    end

    if this.print_cooldown[player_index] and tick - this.print_cooldown[player_index] < 30 then
        return
    end

    this.print_cooldown[player_index] = tick

    for _, target_player in pairs(game.connected_players) do
        if player.physical_surface == target_player.surface then
            target_player.create_local_flying_text{
                text = text,
                color = player.color,
                position = player.physical_position,
                speed = 0.8
            }
        end
    end
end

-- 主市场的商品列表
local market_items = {{
    price = {{name = "coin", count = 4}},
    offer = {
        type = 'give-item',
        item = "raw-fish",
        count = 1
    }
}, {
    price = {{name = "raw-fish", count = 1}},
    offer = {
        type = 'give-item',
        item = 'coin',
        count = 4
    }
}, {
    price = {{name = "coin", count = 1000}},
    offer = {
        type = 'give-item',
        item = 'car',
        count = 1
    }
}, {
    price = {{name = "coin", count = 6000}},
    offer = {
        type = 'give-item',
        item = 'tank',
        count = 1
    }
}, {
    price = {{name = "coin", count = 60000}},
    offer = {
        type = 'give-item',
        item = 'spidertron',
        count = 1
    }
}, {
    price = {{name = "coin", count = 25000}},
    offer = {
        type = 'give-item',
        item = 'tank-cannon',
        count = 1
    }
}, {
    price = {{name = "coin", count = 128}},
    offer = {
        type = 'give-item',
        item = 'loader',
        count = 1
    }
}, {
    price = {{name = "coin", count = 512}},
    offer = {
        type = 'give-item',
        item = 'fast-loader',
        count = 1
    }
}, {
    price = {{name = "coin", count = 4096}},
    offer = {
        type = 'give-item',
        item = 'express-loader',
        count = 1
    }
}, {
    price = {{name = "coin", count = 12288}},
    offer = {
        type = 'give-item',
        item = 'turbo-loader',
        count = 1
    }
}, {
    price = {{name = "coin", count = 400}},
    offer = {
        type = 'give-item',
        item = 'artillery-shell',
        count = 1
    }
}}

-- 为岛屿市场添加升级选项（类似主市场）
local function add_upgrade_items(market_entity, island_id)
    local this = WPT.get()
    local island = this.islands[island_id]

    local price_mine = this.urgrad_mine * 4000 + 1000
    local price_wall = this.health * 2000 + 15000
    local price_arty = this.arty * 10000 + 20000
    local price_all_dam = this.urgrad_all_dam * 10000 + 10000

    local max_price = 65000

    if price_mine >= max_price then
        price_mine = max_price
    end
    if price_wall >= max_price then
        price_wall = max_price
    end
    if price_arty >= max_price then
        price_arty = max_price
    end
    if price_all_dam >= max_price then
        price_all_dam = max_price
    end

    local health_wall = {
        price = {{name = "coin", count = price_wall}},
        offer = {
            type = 'nothing',
            effect_description = {'amap.buy_health_wall', this.health * 0.1}
        }
    }

    local buy_urgrade_all_dam = {
        price = {{name = "coin", count = price_all_dam}},
        offer = {
            type = 'nothing',
            effect_description = {'amap.buy_all_dam', this.urgrad_all_dam * 0.01}
        }
    }

    local arty_dam = {
        price = {{name = "coin", count = price_arty}},
        offer = {
            type = 'nothing',
            effect_description = {'amap.buy_arty_dam', this.arty * 0.1}
        }
    }

    local urgrade_mine = {
        price = {{name = "coin", count = price_mine}},
        offer = {
            type = 'nothing',
            effect_description = {'amap.urgrade_mine', this.urgrad_mine * 200 + 400}
        }
    }

    local buy_tianfu = {
        price = {{name = "coin", count = 65000}},
        offer = {
            type = 'nothing',
            effect_description = {'amap.buy_talent'}
        }
    }

    local enter_dungeon = {
        price = {{name = "coin", count = 10000}},
        offer = {
            type = 'nothing',
            effect_description = {'amap.enter_dungeon'}
        }
    }

    market_entity.add_market_item(health_wall)
    market_entity.add_market_item(buy_urgrade_all_dam)
    market_entity.add_market_item(arty_dam)
    market_entity.add_market_item(urgrade_mine)
    market_entity.add_market_item(buy_tianfu)
    market_entity.add_market_item(enter_dungeon)
end

-- 军事岛可生产的物品列表（22种武器弹药）
local military_items = {
    "firearm-magazine", -- 普通子弹
    "piercing-rounds-magazine", -- 穿甲子弹
    "uranium-rounds-magazine", -- 铀弹
    "shotgun-shell", -- 霰弹
    "piercing-shotgun-shell", -- 穿甲霰弹
    "rocket", -- 普通火箭弹
    "explosive-rocket", -- 爆炸火箭弹
    "flamethrower-ammo", -- 火焰喷射器燃料
    "grenade", -- 手榴弹
    "cluster-grenade", -- 集束手榴弹
    "poison-capsule", -- 毒素胶囊
    "slowdown-capsule", -- 减速胶囊
    "land-mine", -- 地雷
    "defender-capsule", -- 防御无人机胶囊
    "distractor-capsule", -- 干扰无人机胶囊
    "gun-turret", -- 机枪塔
    "laser-turret", -- 激光塔
    "stone-wall" -- 石墙
}

-- 工业岛可生产的物品列表（14种工业产品）
local industrial_items = {
    "iron-plate", -- 铁板
    "steel-plate", -- 钢板
    "copper-plate", -- 铜板
    "solid-fuel", -- 固体燃料
    "plastic-bar", -- 塑料
    "sulfur", -- 硫
    "battery", -- 电池
    "explosives", -- 炸药
    "electronic-circuit", -- 电子电路
    "advanced-circuit", -- 高级电路
    "processing-unit", -- 处理单元
    "engine-unit", -- 引擎单元
    "electric-engine-unit", -- 电机单元
    "landfill" -- 填埋
}

-- 资源岛可生产的物品列表（5种基础资源）
local resource_items = {
    "coal", -- 煤炭
    "stone", -- 石头
    "iron-ore", -- 铁矿石
    "copper-ore", -- 铜矿石
    "uranium-ore", -- 铀矿石
    "crude-oil-barrel" -- 原油桶
}

-- 科技岛可生产的物品列表（6种科学包）
local technology_items = {
    "automation-science-pack",
    "logistic-science-pack",
    "military-science-pack",
    "chemical-science-pack",
    "production-science-pack",
    "utility-science-pack"
}

-- 建筑岛可生产的物品列表（15种物流自动化物品）
local construction_items = {
    "fast-transport-belt",      -- 快速传送带
    "express-transport-belt",   -- 极速传送带
    "long-handed-inserter",     -- 长臂机械臂
    "fast-inserter",            -- 快速机械臂
    "logistic-robot",           -- 物流机器人
    "construction-robot",       -- 建筑机器人
    "fast-splitter",            -- 快速分流器
    "express-splitter",         -- 极速分流器
    "medium-electric-pole",     -- 中型电力杆
    "storage-chest",            -- 存储箱
    "steel-furnace",            -- 钢铁熔炉
    "electric-mining-drill",    -- 电动采矿机
    "assembling-machine-2"      -- 组装机2
}

-- 计算物品的基础价值（基于配方递归计算所需原材料）
local function calculate_base_item_value(item_name, depth)
    local this=WPT.get()
    depth = depth or 0
    if depth > 10 then return 1 end

    if not this.time_cache then
        this.time_cache = {}
    end
    if this.time_cache[item_name] then
        return this.time_cache[item_name]
    end

    local recipe =prototypes.recipe[item_name]

    if not recipe then
        this.time_cache[item_name] = 1
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

    this.time_cache[item_name] = total_time
    return total_time
end



-- 敌方建筑价值表（用于生成虫子）
-- worth: 建筑价值，distance_threshold: 距离基地的最小距离
local enemy_base_value = {
    ["biter-spawner"] = {name = "biter-spawner", worth = 80, distance_threshold = 0},
    ["spitter-spawner"] = {name = "spitter-spawner", worth = 80, distance_threshold = 0},
    ["small-worm-turret"] = {name = "small-worm-turret", worth = 10, distance_threshold = 0},
    ["medium-worm-turret"] = {name = "medium-worm-turret", worth = 20, distance_threshold = 700},
    ["big-worm-turret"] = {name = "big-worm-turret", worth = 50, distance_threshold = 800},
    ["behemoth-worm-turret"] = {name = "behemoth-worm-turret", worth = 75, distance_threshold = 1200},
    ["gun-turret"] = {name = "gun-turret", worth = 15, distance_threshold = 600},
    ["laser-turret"] = {name = "laser-turret", worth = 25, distance_threshold = 1000},
    ["flamethrower-turret"] = {name = "flamethrower-turret", worth = 30, distance_threshold = 1000},
}

-- 岛屿类型列表
local island_types = {
    "military",
    "industrial",
    "resource",
    "technology",
    "construction"
}

-- 随机获取岛屿类型
local function get_random_island_type()
    local this = WPT.get()

    if not this.island_type_index then
        this.island_type_index = 1
    end

    local island_type = island_types[this.island_type_index]

    this.island_type_index = this.island_type_index % #island_types + 1

    return island_type
end

-- 根据岛屿类型随机抽取6个生产物品
local function get_production_items(island_type)
    local items = {}
    local source_items

    if island_type == "military" then
        source_items = military_items
    elseif island_type == "industrial" then
        source_items = industrial_items
    elseif island_type == "resource" then
        source_items = resource_items
    elseif island_type == "technology" then
        source_items = technology_items
    elseif island_type == "construction" then
        source_items = construction_items
    else
        return items
    end

    local shuffled = {}
    for i, item in ipairs(source_items) do
        shuffled[i] = item
    end

    for i = #shuffled, 2, -1 do
        local j = math.random(1, i)
        shuffled[i], shuffled[j] = shuffled[j], shuffled[i]
    end

    local count = math.min(6, #shuffled)
    for i = 1, count do
        table.insert(items, shuffled[i])
    end

    return items
end

-- 在商店周围生成虫子
-- 根据距离基地的远近决定虫子强度和数量
local function generate_enemies_near_market(surface, market_position)
    local distance_from_base = math.sqrt(market_position.x ^ 2 + market_position.y ^ 2)
    local base_value = 70 + distance_from_base * 0.03

    local difficulty_multiplier = 1 + distance_from_base * 0.01
    local adjusted_value = base_value * difficulty_multiplier

    local can_build = {}
    for _, building in pairs(enemy_base_value) do
        if distance_from_base >= building.distance_threshold then
            table.insert(can_build, building)
        end
    end

    if #can_build == 0 then
        return
    end

    local buildings_to_spawn = {}
    local remaining_value = adjusted_value

    while remaining_value > 0 do
        local available_buildings = {}
        for _, building in ipairs(can_build) do
            if remaining_value >= building.worth then
                table.insert(available_buildings, building)
            end
        end

        if #available_buildings == 0 then
            break
        end

        local selected_building = available_buildings[math.random(1, #available_buildings)]
        table.insert(buildings_to_spawn, selected_building)
        remaining_value = remaining_value - selected_building.worth
    end

    for _, building in ipairs(buildings_to_spawn) do
        local spawn_position = surface.find_non_colliding_position(building.name, market_position, 50, 1)

        if spawn_position then
            local distance_from_market = math.sqrt((spawn_position.x - market_position.x) ^ 2 + (spawn_position.y - market_position.y) ^ 2)


                local entity_data = {
                    name = building.name,
                    position = spawn_position,
                    force = "enemy"
                }

                if building.name == 'flamethrower-turret' then
                    entity_data.direction = math.random(0, 3)*4
                end

                local entity = surface.create_entity(entity_data)

                if entity then
                    if entity.name == 'gun-turret' then
                        enemy_arty.add_gun(entity)
                    elseif entity.name == 'laser-turret' then
                        enemy_arty.add_laser(entity)
                    elseif entity.name == 'flamethrower-turret' then
                        enemy_arty.add_flame(entity)
                    elseif entity.name == 'artillery-turret' then
                        enemy_arty.add_arty(entity)
                    end
                end

        end
    end
end

-- 获取岛屿类型的翻译名称（用于商店按钮和玩家消息）
local function get_island_type_name(island_type)
    if island_type == "military" then
        return {'amap.military_island'}
    elseif island_type == "industrial" then
        return {'amap.industrial_island'}
    elseif island_type == "resource" then
        return {'amap.resource_island'}
    elseif island_type == "technology" then
        return {'amap.technology_island'}
    elseif island_type == "construction" then
        return {'amap.construction_island'}
    end
    return {'amap.unknown_island'}
end

-- 创建岛屿的6个存储箱子
-- surface: 地表
-- market_position: 商店位置
-- player_index: 玩家索引
-- island_level: 岛屿等级（可选，默认为1）
-- 返回: 箱子实体列表
local function create_storage_chests(surface, market_position, player_index, island_level)
    local chests = {}
    local player = game.players[player_index]
    local player_force = player and player.force or "player"

    local quality = "normal"
    if island_level and island_level >= 2 then
        if island_level == 2 then
            quality = "uncommon"
        elseif island_level == 3 then
            quality = "rare"
        elseif island_level == 4 then
            quality = "epic"
        elseif island_level >= 5 then
            quality = "legendary"
        end
    end

    local chest_positions = {
        {x = market_position.x - 1, y = market_position.y + 6},
        {x = market_position.x, y = market_position.y + 6},
        {x = market_position.x + 1, y = market_position.y + 6},
        {x = market_position.x - 1, y = market_position.y + 7},
        {x = market_position.x, y = market_position.y + 7},
        {x = market_position.x + 1, y = market_position.y + 7}
    }

    for _, pos in ipairs(chest_positions) do
        local chest = surface.create_entity({
            name = "steel-chest",
            position = pos,
            force = player_force,
            quality = quality,
            create_build_effect_smoke = false
        })

        if chest then
            chest.destructible = false
            chest.minable_flag = false
            table.insert(chests, chest)
        end
    end

    return chests
end

-- 更新岛屿存储箱子的品质
-- island_id: 岛屿ID
-- 更新岛屿存储箱子的品质
-- 更新岛屿存储箱子的品质（按原箱子索引还原物品）
local function update_chest_quality(island_id)
    local this = WPT.get()

    if not this.islands or not this.islands[island_id] then
        return
    end

    local island = this.islands[island_id]

    -- 如果箱子列表不存在，直接跳过
    if not island.storage_chests then
        return
    end

    local surface = island.market_entity.surface
    local market_pos = island.market_entity.position
    local owner = island.owner
    local level = island.level

    -- 1. 备份数据：按索引存储每个箱子的内容
    -- backup_data[1] 对应 1号箱子的内容，以此类推
    local backup_data = {}

    for i, chest in ipairs(island.storage_chests) do
        backup_data[i] = {} -- 默认为空
        if chest and chest.valid then
            local inventory = chest.get_inventory(defines.inventory.chest)
            if inventory then
                -- Factorio 2.0 中 get_contents 返回 [{name, count, quality}, ...] 格式的列表
                backup_data[i] = inventory.get_contents()
            end
            -- 备份完立刻销毁旧箱子
            chest.destroy()
        end
    end

    -- 2. 创建新品质的箱子
    -- 这个函数内部会生成新的 storage_chests 数组（同样是 1-6 个）
    island.storage_chests = create_storage_chests(surface, market_pos, owner, level)

    -- 3. 还原数据：将备份的内容按索引塞回新箱子
    for i, contents in ipairs(backup_data) do
        local new_chest = island.storage_chests[i]
        if new_chest and new_chest.valid then
            -- contents 是一个列表，里面装的是多个物品堆栈条目
            for _, item_stack in ipairs(contents) do
                -- item_stack 的格式刚好符合 insert 函数的参数要求 {name=..., count=..., quality=...}
                new_chest.insert(item_stack)
            end
        end
    end
end

-- 注册岛屿
-- surface: 地表
-- market_entity: 市场实体
-- island_type: 岛屿类型（可选，不指定则随机）
-- generate_enemies: 是否生成虫子（可选，默认为true）
-- 返回: 岛屿ID
function Public.register_island(surface, market_entity, island_type, generate_enemies)
    local this = WPT.get()

    if not this.islands then
        this.islands = {}
    end

    if not island_type then
        island_type = get_random_island_type()
    end

    if generate_enemies == nil then
        generate_enemies = true
    end

    local island_id = #this.islands + 1

    local tag_id = nil
    local tag_text = nil

    if island_type == "military" then
        tag_text = '军事岛'
    elseif island_type == "industrial" then
        tag_text = '工业岛'
    elseif island_type == "resource" then
        tag_text = '资源岛'
    elseif island_type == "technology" then
        tag_text = '科技岛'
    elseif island_type == "construction" then
        tag_text = '建筑岛'
    end

    if tag_text then
        tag_id = game.forces.player.add_chart_tag(surface, {
            position = market_entity.position,
            text = tag_text
        })
    end

    local island_data = {
        id = island_id,
        level = 0,
        type = island_type,
        owner = nil,
        owner_name = nil,
        market_entity = market_entity,
        production_items = {},
        production_capacity = 0,
        last_production_time = 0,
        text_id = nil,
        storage_chests = {},
        tag_id = tag_id,
        investments = {}
    }

    this.islands[island_id] = island_data

    if generate_enemies then
        generate_enemies_near_market(surface, market_entity.position)
    end

    return island_id
end

-- 设置岛屿商店（添加购买按钮）
-- market_entity: 市场实体
-- island_id: 岛屿ID
function Public.setup_island_market(market_entity, island_id)
    local this = WPT.get()

    if not this.islands or not this.islands[island_id] then
        return
    end

    local island = this.islands[island_id]

    if island.owner ~= nil then
        return
    end

    local island_type_name = get_island_type_name(island.type)

    local source_items_count = 0
    if island.type == "military" then
        source_items_count = #military_items
    elseif island.type == "industrial" then
        source_items_count = #industrial_items
    elseif island.type == "resource" then
        source_items_count = #resource_items
    elseif island.type == "technology" then
        source_items_count = #technology_items
    elseif island.type == "construction" then
        source_items_count = #construction_items
    end

    local buy_island_item = {
        price = {{name = "coin", count = 10000}},
        offer = {
            type = 'nothing',
            effect_description = {'amap.buy_island', island_type_name, source_items_count, '10000'}
        }
    }

    market_entity.add_market_item(buy_island_item)
end

-- 购买岛屿
-- player_index: 玩家索引
-- island_id: 岛屿ID
-- 返回: 是否购买成功
function Public.purchase_island(player_index, island_id)
    local this = WPT.get()
    local player = game.players[player_index]

    if not this.islands or not this.islands[island_id] then
        if player and player.valid then
            new_print(player, {'amap.island_not_found'})
        end
        return false
    end

    local island = this.islands[island_id]

    if island.owner ~= nil then
        if player and player.valid then
            new_print(player, {'amap.island_already_owned'})
        end
        return false
    end


    island.owner = player_index
    island.owner_name = player.name
    island.level = 1
    island.production_capacity = 7500
    island.production_items = get_production_items(island.type)
    island.last_production_time = game.tick

    if not island.investments then
        island.investments = {}
    end
    island.investments[player_index] = 10000

    island.storage_chests = create_storage_chests(island.market_entity.surface, island.market_entity.position, player_index)

    local surface = island.market_entity.surface
    local player_position = player.physical_position

    if player_position then
        local safe_position = surface.find_non_colliding_position('character', player_position, 10, 1)
        if safe_position then
            player.teleport(safe_position, surface)
        end
    end

    if island.text_id and island.text_id.valid then
        island.text_id.destroy()
    end

    island.text_id = rendering.draw_text {
        text = {'', player.name, {'amap.possessive_particle'}, get_island_type_name(island.type)},
        surface = island.market_entity.surface,
        target = {
            entity = island.market_entity,
            offset = {0, -3.5}
        },
        color = {
            r = 1,
            g = 1,
            b = 0,
            a = 1
        },
        scale = 1.5,
        font = 'default-large-semibold',
        alignment = 'center',
        scale_with_zoom = false
    }

    Public.refresh_island_market(island.market_entity, island_id)

    if player and player.valid then
        new_print(player, {'amap.island_purchased', get_island_type_name(island.type), 10000})
    end

    return true
end

-- 升级岛屿
-- player_index: 玩家索引
-- island_id: 岛屿ID
-- 返回: 是否升级成功
function Public.upgrade_island(player_index, island_id)
    local this = WPT.get()
    local player = game.players[player_index]

    if not this.islands or not this.islands[island_id] then
        if player and player.valid then
            new_print(player, {'amap.island_not_found'})
        end
        return false
    end

    local island = this.islands[island_id]

    if island.level >= 5 then
        if player and player.valid then
            new_print(player, {'amap.island_max_level'})
        end
        return false
    end

    island.level = island.level + 1
    island.production_capacity = island.level * 5000

    local upgrade_cost = island.level * 10000
    if not island.investments then
        island.investments = {}
    end
    island.investments[player_index] = (island.investments[player_index] or 0) + upgrade_cost

    if island.level == 5 then
        island.urgrad_mine = 0
        island.health = 0
        island.arty = 0
        island.urgrad_all_dam = 0
    end

    update_chest_quality(island_id)

    if island.text_id and island.text_id.valid then
        island.text_id.destroy()
    end

    island.text_id = rendering.draw_text {
        text = {'', island.owner_name, {'amap.possessive_particle'}, get_island_type_name(island.type), ' (Lv.', island.level, ')'},
        surface = island.market_entity.surface,
        target = {
            entity = island.market_entity,
            offset = {0, -3.5}
        },
        color = {
            r = 1,
            g = 1,
            b = 0,
            a = 1
        },
        scale = 1.5,
        font = 'default-large-semibold',
        alignment = 'center',
        scale_with_zoom = false
    }

    Public.refresh_island_market(island.market_entity, island_id)

    if player and player.valid then
        new_print(player, {'amap.island_upgraded', island.level, upgrade_cost})
    end

    return true
end

-- 刷新岛屿商店商品
-- market_entity: 市场实体
-- island_id: 岛屿ID
function Public.refresh_island_market(market_entity, island_id)
    local this = WPT.get()

    if not this.islands or not this.islands[island_id] then
        return
    end

    local island = this.islands[island_id]

    market_entity.clear_market_items()

    if island.owner == nil then
        Public.setup_island_market(market_entity, island_id)
    else
        if island.level >= 3 and island.level < 5 then
            local buy_fish_item = {
                price = {{name = "coin", count = 4}},
                offer = {
                    type = 'give-item',
                    item = "raw-fish",
                    count = 1
                }
            }
            market_entity.add_market_item(buy_fish_item)

            local sell_fish_item = {
                price = {{name = "raw-fish", count = 1}},
                offer = {
                    type = 'give-item',
                    item = "coin",
                    count = 4
                }
            }
            market_entity.add_market_item(sell_fish_item)
        end

        if island.level >= 5 then
            add_upgrade_items(market_entity, island_id)

            for _, item in pairs(market_items) do
                market_entity.add_market_item(item)
            end

            local rand_item = MT.get_random_item(6, false, false)
            for _, item in pairs(rand_item) do
                item.price[1].count = math.floor(item.price[1].count * 1.1)
                market_entity.add_market_item(item)
            end
        elseif island.level >= 4 then
            local loader_items = {
                {
                    price = {{name = "coin", count = 128}},
                    offer = {
                        type = 'give-item',
                        item = 'loader',
                        count = 1
                    }
                },
                {
                    price = {{name = "coin", count = 512}},
                    offer = {
                        type = 'give-item',
                        item = 'fast-loader',
                        count = 1
                    }
                },
                {
                    price = {{name = "coin", count = 4096}},
                    offer = {
                        type = 'give-item',
                        item = 'express-loader',
                        count = 1
                    }
                },
                {
                    price = {{name = "coin", count = 12288}},
                    offer = {
                        type = 'give-item',
                        item = 'turbo-loader',
                        count = 1
                    }
                }
            }

            for _, item in pairs(loader_items) do
                market_entity.add_market_item(item)
            end

            local rand_item = MT.get_random_item(6, false, false)
            for _, item in pairs(rand_item) do
                item.price[1].count = math.floor(item.price[1].count * 1.1)
                market_entity.add_market_item(item)
            end
        end

        if island.level < 5 then
            local cost = (island.level + 1) * 10000
            local upgrade_item = {
                price = {{name = "coin", count = cost}},
                offer = {
                    type = 'nothing',
                    effect_description = {'amap.upgrade_island', island.level + 1, (island.level + 1) * 10000}
                }
            }
            market_entity.add_market_item(upgrade_item)
        else
            local max_level_item = {
                price = {{name = "coin", count = 999999}},
                offer = {
                    type = 'nothing',
                    effect_description = {'amap.island_max_level'}
                }
            }
            market_entity.add_market_item(max_level_item)
        end
    end
end

-- 处理岛屿生产（每10 ticks处理1个岛屿）
-- 为所有已购买的岛屿生产资源、经验和金币
function Public.process_island_production()
    local this = WPT.get()

    if not this.islands then
        return
    end

    local island_list = {}
    for _, island in pairs(this.islands) do
        if island.owner ~= nil and island.market_entity and island.market_entity.valid then
            table.insert(island_list, island)
        end
    end

    if #island_list == 0 then
        return
    end

    this.island_production_index = this.island_production_index % #island_list + 1
    local island = island_list[this.island_production_index]

    local current_tick = game.tick
    local time_since_last_production = current_tick - island.last_production_time

    if time_since_last_production >= 60 * 60 then
        local total_value = island.production_capacity

        if island.type == "technology" then
             local set_cost = 0
            for _, item_name in ipairs(island.production_items) do
                set_cost = set_cost + calculate_base_item_value(item_name)
            end

            -- 防止除以0
            if set_cost <= 0 then set_cost = 1 end

            -- 计算能生产多少“套”
            local item_count = math.floor(total_value / set_cost)

            -- 如果产能太低不足以生产一套，至少生产1个（可选，或者保持0）
            if item_count < 1 and total_value > 0 then item_count = 1 end

            for i, item_name in ipairs(island.production_items) do
                if item_count > 0 and island.storage_chests and island.storage_chests[i] and island.storage_chests[i].valid then
                    island.storage_chests[i].insert({name = item_name, count = item_count})
                end
            end
        else
            for i, item_name in ipairs(island.production_items) do
                local item_value = calculate_base_item_value(item_name)
                local item_count = math.floor(total_value / item_value / #island.production_items)

                if item_count > 0 and island.storage_chests and island.storage_chests[i] and island.storage_chests[i].valid then
                    island.storage_chests[i].insert({name = item_name, count = item_count})
                end
            end
        end

        local total_xp = 0
        local total_coin = 0

        for i = 1, island.level do
            total_xp = total_xp + i * 4
            total_coin = total_coin + i * 40
        end

        local total_investment = 0
        if island.investments then
            for _, investment in pairs(island.investments) do
                total_investment = total_investment + investment
            end
        end

        if total_investment > 0 and island.investments then
            for player_index, investment in pairs(island.investments) do
                local player = game.players[player_index]
                if player and player.valid then
                    local share = investment / total_investment
                    local xp_gained = math.floor(total_xp * share)
                    local coin_gained = math.floor(total_coin * share)

                    if xp_gained > 0 then
                        local rpg_t = rpgtable.get('rpg_t')
                        rpg_t[player_index].xp = rpg_t[player_index].xp + xp_gained
                    end

                    if coin_gained > 0 then
                        insert_coin_to_player(player, coin_gained)
                    end

                    if player.connected and (xp_gained > 0 or coin_gained > 0) then
                        new_print(player, {'amap.island_production', island.level, coin_gained, xp_gained})
                    end
                end
            end
        end

        island.last_production_time = current_tick
    end
end

-- 获取岛屿信息
-- island_id: 岛屿ID
-- 返回: 岛屿信息表
function Public.get_island_info(island_id)
    local this = WPT.get()

    if not this.islands or not this.islands[island_id] then
        return nil
    end

    local island = this.islands[island_id]
    return {
        id = island.id,
        level = island.level,
        type = island.type,
        owner_name = island.owner_name,
        production_capacity = island.production_capacity,
        production_items = island.production_items
    }
end

-- 获取玩家拥有的所有岛屿
-- player_index: 玩家索引
-- 返回: 玩家拥有的岛屿列表
function Public.get_player_islands(player_index)
    local this = WPT.get()
    local player_islands = {}

    if not this.islands then
        return player_islands
    end

    for _, island in pairs(this.islands) do
        if island.owner == player_index then
            table.insert(player_islands, {
                id = island.id,
                level = island.level,
                type = island.type,
                production_capacity = island.production_capacity,
                production_items = island.production_items
            })
        end
    end

    return player_islands
end

-- 根据市场实体获取岛屿ID
-- market_entity: 市场实体
-- 返回: 岛屿ID
function Public.get_island_id_by_market(market_entity)
    local this = WPT.get()

    if not this.islands then
        return nil
    end

    for island_id, island in pairs(this.islands) do
        if island.market_entity == market_entity then
            return island_id
        end
    end

    return nil
end

-- 处理市场物品购买事件
-- event: 事件对象
local function on_market_item_purchased(event)
    local market = event.market
    local player_index = event.player_index
    local player = game.players[player_index]

    if not player or not player.valid then
        return
    end

    local this = WPT.get()

    local island_id = Public.get_island_id_by_market(market)
    if not island_id then
        return
    end


    local island = this.islands[island_id]
    if not island then
        return
    end

    -- 获取购买的物品信息
    local offers = market.get_market_items()
    local offer_data = offers[event.offer_index]

    if not offer_data or offer_data.offer.type ~= "nothing" then
        return
    end

    local bought_offer = offer_data.offer
    local offer_index = event.offer_index

    -------------------------------------------------------
    -- 逻辑分支处理
    -------------------------------------------------------

    -- 1. 如果岛屿没有主人，购买岛屿
    if island.owner == nil then
        Public.purchase_island(player_index, island_id)

    -- 2. 如果岛屿等级小于 5，进行升级
    elseif island.level < 5 then
        Public.upgrade_island(player_index, island_id)

    -- 3. 如果岛屿等级达到 5，执行特殊购买项
    else
        if offer_index == 1 then
            -- 增加基地血量，降低敌人伤害
            this.health = (this.health or 0) + 1
            functions.set_force_damage_modifier(game.forces.enemy, -0.1)
            game.print({'amap.buy_wall_over', player.name, this.health * 0.1})

        elseif offer_index == 2 then
            -- 升级全域伤害
            local damage_multiplier = this.damage_multiplier or 1
            if damage_multiplier > 0.98 then
                local price_all_dam = (this.urgrad_all_dam or 0) * 10000 + 10000
                local max_price = 65000
                if price_all_dam >= max_price then price_all_dam = max_price end

                player.insert({name = "coin", count = price_all_dam})
                game.print({'amap.damage_multiplier_max', player.name})
                return -- 达到上限，直接返回，不刷新市场
            end
            this.urgrad_all_dam = (this.urgrad_all_dam or 0) + 1
            functions.set_force_damage_modifier(game.forces.player, 0.01, true)
            game.print({'amap.urgrad_all_dam_over', player.name, this.urgrad_all_dam * 0.01})

        elseif offer_index == 3 then
            -- 升级火炮伤害
            this.arty = (this.arty or 0) + 1
            local e_old = game.forces.player.get_ammo_damage_modifier("artillery-shell")
            game.forces.player.set_ammo_damage_modifier("artillery-shell", e_old + 0.1)
            game.print({'amap.buy_arty_over', player.name, this.arty * 0.1 + 1})

        elseif offer_index == 4 then
            -- 升级矿容
            this.urgrad_mine = (this.urgrad_mine or 0) + 1
            this.max_mine = 400 + this.urgrad_mine * 200
            game.print({'amap.urgrad_mine_over', player.name, this.max_mine})

        elseif offer_index == 5 then
            if not this.tianfu_buy_count[player.index] then
                this.tianfu_buy_count[player.index] = 0
            end

            if this.tianfu_buy_count[player.index] >= 25 then
                player.insert({name = 'coin', count = 65000})
                player.print({'amap.tianfu_limit_reached', player.name})
                return
            end

            this.tianfu_count[player.index] = this.tianfu_count[player.index] - 1
            this.tianfu_buy_count[player.index] = this.tianfu_buy_count[player.index] + 1
            game.print(player.name .. '购买了1个天赋（已购买' .. this.tianfu_buy_count[player.index] .. '次）')

        elseif offer_index == 6 then
            -- 进入副本
            Dungeon.show_difficulty_selection_gui(player)
        end

        -- 等级>=5的购买项执行完后刷新市场内容
        Public.refresh_island_market(market, island_id)
    end

    -- 统一播放购买成功音效
    market.force.play_sound({
        path = 'utility/new_objective',
        volume_modifier = 0.75
    })
end

-- 注册事件监听器
Event.add(defines.events.on_market_item_purchased, on_market_item_purchased)
Event.on_nth_tick(10, Public.process_island_production)


return Public
