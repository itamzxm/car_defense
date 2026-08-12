-- maps/amap/instance/modules/coin_mine.lua
-- 挖币工厂玩法模块（从原 dungeon.lua 迁移）
--
-- 玩法类型：coin_mine
-- 玩法说明：玩家在 100×100 的副本内通过建石墙/挖矿/回收物品赚取金币
--           30 分钟内赚取的金币受难度上限限制，超时或主动退出后金币转到原角色
--
-- 钩子实现：
--   on_surface_init - 生成地形（grass + 矿脉 + 水 + 油 + 石墙包围 + 市场 + 回收箱）
--   on_enter        - 给 5000 起始 coin + force modifier + 创建回收箱价目表按钮
--   on_exit         - 由框架负责背包转移与 surface 销毁，模块仅清理自定义 GUI
--   on_tick         - 处理回收箱换币
--   on_gui_click    - 处理回收箱价目表按钮
--   on_built_entity / on_robot_built_entity - 建石墙给币
--   on_player_mined_entity / on_robot_pre_mined - 挖石墙扣币（不足回滚）
--   on_pre_player_mined_item - 挖矿扣币（不足回滚）
--
-- 不实现 check_victory：挖币玩法没有通关条件，靠时间限制

local Token = require 'utils.token'
local Task = require 'utils.task'
local Instance = require 'maps.amap.instance.instance'

local M = {}

--==============================================================================
-- 元数据
--==============================================================================

M.type = 'coin_mine'
M.display_name_key = 'amap.instance_coin_mine_name'
M.description_key = 'amap.instance_coin_mine_desc'
M.gameplay_desc_key = 'amap.instance_coin_mine_gameplay'
M.victory_condition_key = 'amap.instance_coin_mine_victory'
M.icon = 'item/coin'
M.time_limit_default = 30 * 60 * 60  -- 30 分钟（tick）

-- 挖币工厂需要玩家在副本里建厂挖币，故进入时把主世界「已研发科技」单向同步进副本 force
-- （其他副本禁止继承，避免满科技破坏平衡；详见 instance.lua Public.enter 中的 def.needs_tech_sync 判定）
M.needs_tech_sync = true

-- 难度设置（与原 dungeon.lua 完全一致）
M.difficulty_settings = {
    easy = {
        name = "easy",
        recycling_efficiency = 1,
        max_coins = 40000,
        display_name_key = "dungeon_difficulty_easy"
    },
    normal = {
        name = "normal",
        recycling_efficiency = 0.8,
        max_coins = 50000,
        display_name_key = "dungeon_difficulty_normal"
    },
    hard = {
        name = "hard",
        recycling_efficiency = 0.6,
        max_coins = 60000,
        display_name_key = "dungeon_difficulty_hard"
    }
}

--==============================================================================
-- 价格表（与原 dungeon.lua 完全一致）
--==============================================================================

local recycling_prices = {
    ["iron-gear-wheel"] = 10,
    ["electronic-circuit"] = 15,
    ["rocket"] = 150,
    ["solar-panel"] = 600,
    ["chemical-science-pack"] = 1500
}

local market_prices = {
    ["coal"] = 5,
    ["transport-belt"] = 5,
    ["underground-belt"] = 20,
    ["fast-transport-belt"] = 50,
    ["fast-underground-belt"] = 200,
    ["splitter"] = 25,
    ["fast-splitter"] = 50,
    ["burner-inserter"] = 10,
    ["inserter"] = 10,
    ["long-handed-inserter"] = 15,
    ["fast-inserter"] = 20,
    ["wooden-chest"] = 5,
    ["iron-chest"] = 10,
    ["stone-furnace"] = 10,
    ["steel-furnace"] = 50,
    ["electric-furnace"] = 70,
    ["offshore-pump"] = 10,
    ["pipe"] = 5,
    ["pipe-to-ground"] = 20,
    ["boiler"] = 15,
    ["steam-engine"] = 50,
    ["small-electric-pole"] = 10,
    ["medium-electric-pole"] = 50,
    ["big-electric-pole"] = 100,
    ["substation"] = 150,
    ["assembling-machine-1"] = 30,
    ["assembling-machine-2"] = 50,
    ["assembling-machine-3"] = 100,
    ["electric-mining-drill"] = 50,
    ["burner-mining-drill"] = 10,
    ["pump"] = 20,
    ["pumpjack"] = 50,
    ["oil-refinery"] = 100,
    ["chemical-plant"] = 50,
    ["storage-tank"] = 40
}

local ore_prices = {
    ["coal"] = 5,
    ["iron-ore"] = 5,
    ["copper-ore"] = 5
}

--==============================================================================
-- Token 注册（不足回滚用）
--==============================================================================

-- 玩家币不足时，恢复被挖的石墙
local function restore_stone_wall(params)
    local player = game.players[params.player_index]
    if not player or not player.valid then return end

    player.remove_item({name = "stone-wall", count = 1})
    player.surface.create_entity({
        name = "stone-wall",
        position = params.position,
        force = player.force
    })
end
local restore_stone_wall_token = Token.register(restore_stone_wall)

-- 玩家币不足时，移除已挖出的矿物（防止白嫖）
local function remove_mined_item(params)
    local player = game.players[params.player_index]
    if not player or not player.valid then return end

    player.remove_item({name = params.item_name, count = 1})
end
local remove_mined_item_token = Token.register(remove_mined_item)

--==============================================================================
-- 辅助函数
--==============================================================================

local function get_stone_wall_price(position)
    return math.abs(position.x) + math.abs(position.y)
end

local function is_position_on_resource(surface, position)
    local resources = surface.find_entities_filtered({
        position = position,
        radius = 0.5,
        type = 'resource'
    })
    return #resources > 0
end

-- 带上限地给玩家加 coin，返回实际加上的数量
-- 同步更新 data.coins_earned（与原 dungeon.lua add_coins_with_limit 一致）
local function add_coins_with_limit(player, data, amount)
    local can_add = data.max_coins - data.coins_earned
    if can_add <= 0 then return 0 end

    local actual_add = math.min(amount, can_add)
    player.insert({name = "coin", count = actual_add})
    data.coins_earned = data.coins_earned + actual_add
    return actual_add
end

--==============================================================================
-- 地形生成（与原 dungeon.lua 完全一致）
--==============================================================================

local function generate_ore_vein(surface, center_pos, ore_type, size)
    local vectors = {{0,-1},{-1,0},{1,0},{0,1}}
    local ore_positions = {}
    local ore_entities = {}

    local amount = 500 + math.random(0, 500)
    ore_entities[#ore_entities + 1] = {name = ore_type, position = center_pos, amount = amount}
    ore_positions[center_pos.x .. "_" .. center_pos.y] = true

    local count = size

    for _ = 1, 128 do
        local c = math.random(math.floor(size * 0.25) + 1, size)
        if count < c then c = count end

        local placed_ore_count = #ore_entities

        for _ = 1, c do
            if #ore_entities == 0 then break end

            local r = math.random(1, #ore_entities)
            local position = {x = ore_entities[r].position.x, y = ore_entities[r].position.y}

            table.shuffle_table(vectors)
            for i = 1, 4 do
                local p = {x = position.x + vectors[i][1], y = position.y + vectors[i][2]}
                if p.x >= -50 and p.x <= 50 and p.y >= -50 and p.y <= 50 then
                    if not ore_positions[p.x .. "_" .. p.y] then
                        position.x = p.x
                        position.y = p.y
                        ore_positions[p.x .. "_" .. p.y] = true
                        local new_amount = 500 + math.random(0, 500)
                        ore_entities[#ore_entities + 1] = {name = ore_type, position = p, amount = new_amount}
                        break
                    end
                end
            end
        end

        count = count - (#ore_entities - placed_ore_count)
        if count <= 0 then break end
    end

    for _, e in pairs(ore_entities) do
        surface.create_entity(e)
    end
end

local function generate_water_vein(surface, center_pos, size)
    local vectors = {{0,-1},{-1,0},{1,0},{0,1}}
    local water_positions = {}
    local water_tiles = {}

    water_tiles[#water_tiles + 1] = {name = "water", position = center_pos}
    water_positions[center_pos.x .. "_" .. center_pos.y] = true

    local count = size

    for _ = 1, 64 do
        local c = math.random(math.floor(size * 0.25) + 1, size)
        if count < c then c = count end

        local placed_water_count = #water_tiles

        for _ = 1, c do
            if #water_tiles == 0 then break end

            local r = math.random(1, #water_tiles)
            local position = {x = water_tiles[r].position.x, y = water_tiles[r].position.y}

            table.shuffle_table(vectors)
            for i = 1, 4 do
                local p = {x = position.x + vectors[i][1], y = position.y + vectors[i][2]}
                if p.x >= -50 and p.x <= 50 and p.y >= -50 and p.y <= 50 then
                    if not water_positions[p.x .. "_" .. p.y] then
                        position.x = p.x
                        position.y = p.y
                        water_positions[p.x .. "_" .. p.y] = true
                        water_tiles[#water_tiles + 1] = {name = "water", position = p}
                        break
                    end
                end
            end
        end

        count = count - (#water_tiles - placed_water_count)
        if count <= 0 then break end
    end

    surface.set_tiles(water_tiles)
end

local function generate_oil_patch(surface, center_pos, size)
    local vectors = {{0,-1},{-1,0},{1,0},{0,1},{-1,-1},{1,-1},{-1,1},{1,1}}
    local oil_positions = {}
    local oil_entities = {}

    local amount = 100000 + math.random(0, 66667)
    oil_entities[#oil_entities + 1] = {name = "crude-oil", position = center_pos, amount = amount}
    oil_positions[center_pos.x .. "_" .. center_pos.y] = true

    local count = size
    local max_oil_wells = 1

    for _ = 1, 16 do
        if #oil_entities >= max_oil_wells then break end

        local c = math.random(math.floor(size * 0.25) + 1, size)
        if count < c then c = count end

        local placed_oil_count = #oil_entities

        for _ = 1, c do
            if #oil_entities >= max_oil_wells then break end
            if #oil_entities == 0 then break end

            local r = math.random(1, #oil_entities)
            local position = {x = oil_entities[r].position.x, y = oil_entities[r].position.y}

            table.shuffle_table(vectors)
            for i = 1, 8 do
                local p = {x = position.x + vectors[i][1], y = position.y + vectors[i][2]}
                if p.x >= -50 and p.x <= 50 and p.y >= -50 and p.y <= 50 then
                    if not oil_positions[p.x .. "_" .. p.y] then
                        local tile = surface.get_tile(p.x, p.y)
                        if tile.name ~= "water" then
                            position.x = p.x
                            position.y = p.y
                            oil_positions[p.x .. "_" .. p.y] = true
                            local new_amount = 100000 + math.random(0, 66667)
                            oil_entities[#oil_entities + 1] = {name = "crude-oil", position = p, amount = new_amount}
                            break
                        end
                    end
                end
            end
        end

        count = count - (#oil_entities - placed_oil_count)
        if count <= 0 then break end
    end

    for _, e in pairs(oil_entities) do
        surface.create_entity(e)
    end
end

-- 创建市场 + 回收箱（与原 dungeon.lua create_dungeon_market 一致）
local function create_market_and_recycling(surface, player, data)
    local market = surface.create_entity({
        name = "market",
        position = {x = 0, y = 5},
        force = player.force
    })

    if market then
        market.destructible = false
        market.minable_flag = false

        local player_force = game.forces["player"]

        for item_name, price in pairs(market_prices) do
            local recipe = player_force.recipes[item_name]
            if (recipe and recipe.enabled) or item_name == 'coal' then
                market.add_market_item({
                    price = {{name = "coin", count = price}},
                    offer = {type = 'give-item', item = item_name, count = 1}
                })
            end
        end
    end

    local recycling_chest = surface.create_entity({
        name = "steel-chest",
        position = {x = -3, y = 5},
        force = player.force
    })

    if recycling_chest then
        recycling_chest.destructible = false
        recycling_chest.minable_flag = false
        rendering.draw_text({
            text = "回收箱",
            surface = surface,
            target = {
                entity = recycling_chest,
                offset = {0, -2.6}
            },
            color = {r = 1, g = 0.5, b = 0},
            scale = 1.05,
            font = "default-large-semibold",
            alignment = "center"
        })
        data.recycling_chest = recycling_chest
    end

    return market, recycling_chest
end

--==============================================================================
-- 回收箱价目表 GUI（与原 dungeon.lua 一致）
--==============================================================================

local function show_recycling_prices_gui(player)
    local screen = player.gui.screen

    if screen['recycling_prices_frame'] then
        screen['recycling_prices_frame'].destroy()
        return
    end

    local frame = screen.add({
        type = 'frame',
        name = 'recycling_prices_frame',
        caption = {'amap.recycling_prices'},
        direction = 'vertical'
    })
    frame.auto_center = true

    local scroll = frame.add({
        type = 'scroll-pane',
        vertical_scroll_policy = 'auto',
        horizontal_scroll_policy = 'never'
    })
    scroll.style.maximal_height = 400
    scroll.style.minimal_width = 300

    local tbl = scroll.add({type = 'table', column_count = 2})
    tbl.style.horizontal_spacing = 20
    tbl.style.vertical_spacing = 8

    tbl.add({type = 'label', caption = {'amap.item_name'}, style = 'caption_label'})
    tbl.add({type = 'label', caption = {'amap.price'}, style = 'caption_label'})

    for item_name, price in pairs(recycling_prices) do
        local item_label = tbl.add({
            type = 'label',
            caption = '[img=item/' .. item_name .. '] ' .. item_name
        })
        item_label.style.minimal_width = 150
        item_label.style.maximal_width = 150

        local price_label = tbl.add({
            type = 'label',
            caption = price .. ' [img=item/coin]'
        })
        price_label.style.font_color = {1, 0.84, 0}
        price_label.style.font = 'default-bold'
    end
end

--==============================================================================
-- 回收箱处理（每 60 tick 调用一次）
--==============================================================================

local function process_recycling_chest(player, data)
    if not data.active then return end

    local recycling_chest = data.recycling_chest
    if not recycling_chest or not recycling_chest.valid then return end

    local inventory = recycling_chest.get_inventory(defines.inventory.chest)
    if not inventory or inventory.is_empty() then return end

    local total_coins_to_add = 0
    local items_to_remove = {}

    for item_name, price in pairs(recycling_prices) do
        local item_count = inventory.get_item_count(item_name)
        if item_count > 0 then
            local value = price * item_count * (data.recycling_efficiency or 1)
            total_coins_to_add = total_coins_to_add + value
            items_to_remove[item_name] = item_count
        end
    end

    if total_coins_to_add > 0 then
        local can_add = data.max_coins - data.coins_earned

        if can_add > 0 then
            local coins_added = add_coins_with_limit(player, data, total_coins_to_add)

            for name, count in pairs(items_to_remove) do
                inventory.remove({name = name, count = count})
            end

            player.create_local_flying_text({
                text = "+" .. coins_added,
                position = recycling_chest.position,
                color = {r = 0, g = 1, b = 0},
                time_to_live = 120
            })

            if coins_added < total_coins_to_add then
                player.create_local_flying_text({
                    text = {'amap.dungeon_max_coins_reached_flying'},
                    position = recycling_chest.position,
                    color = {r = 1, g = 0.5, b = 0},
                    time_to_live = 120
                })
            else
                player.create_local_flying_text({
                    text = {'amap.dungeon_recycling_earned_flying', coins_added},
                    position = recycling_chest.position,
                    color = {r = 0, g = 1, b = 0},
                    time_to_live = 120
                })
            end
        else
            player.create_local_flying_text({
                text = {'amap.dungeon_max_coins_reached_flying'},
                position = recycling_chest.position,
                color = {r = 1, g = 0, b = 0},
                time_to_live = 120
            })
        end
    end
end

--==============================================================================
-- 钩子实现
--==============================================================================

-- surface 初始化：生成地形 + 市场 + 回收箱 + 石墙包围
-- 与原 dungeon.lua enter_dungeon 中 surface 创建段一致
function M.on_surface_init(surface, player, data, difficulty)
    -- 平铺 grass-1（资源格保留）
    for x = -50, 50 do
        for y = -50, 50 do
            if not surface.get_tile(x, y).collides_with("resource") then
                surface.set_tiles{{name = "grass-1", position = {x, y}}}
            end
        end
    end

    -- 3 类矿脉
    local ore_veins = {
        {type = "coal", count = 3},
        {type = "iron-ore", count = 3},
        {type = "copper-ore", count = 3}
    }
    for _, vein in pairs(ore_veins) do
        for i = 1, vein.count do
            local pos = {x = math.random(-40, 40), y = math.random(-40, 40)}
            local size = math.floor(math.random(10, 30) * 1.5)
            generate_ore_vein(surface, pos, vein.type, size)
        end
    end

    -- 2 处水
    for i = 1, 2 do
        local pos = {x = math.random(-40, 40), y = math.random(-40, 40)}
        local size = math.random(15, 25)
        generate_water_vein(surface, pos, size)
    end

    -- 3 处油井
    for i = 1, 3 do
        local pos = {x = math.random(-40, 40), y = math.random(-40, 40)}
        local size = math.random(8, 15)
        generate_oil_patch(surface, pos, size)
    end

    -- 市场 + 回收箱
    create_market_and_recycling(surface, player, data)

    -- 石墙包围（保留市场与回收箱位置空缺）
    for x = -50, 50 do
        for y = -50, 50 do
            local tile = surface.get_tile(x, y)
            if tile.name ~= "water" then
                local entities = surface.find_entities({{x, y}, {x + 1, y + 1}})
                local has_resource = false
                for _, entity in pairs(entities) do
                    if entity.type == "resource" then
                        has_resource = true
                        break
                    end
                end

                if not has_resource and (math.abs(x) > 3 or math.abs(y) > 3) then
                    local is_market_pos = (x == 0 and y == 5)
                    local is_recycling_chest_pos = (x == -3 and y == 5)

                    if not is_market_pos and not is_recycling_chest_pos then
                        surface.create_entity({
                            name = "stone-wall",
                            position = {x, y},
                            force = player.force
                        })
                    end
                end
            end
        end
    end
end

-- 进入副本：给初始 5000 coin + force modifier + 创建回收箱价目表按钮
-- 与原 dungeon.lua enter_dungeon 末尾段一致
function M.on_enter(player, data, difficulty)
    player.insert({name = "coin", count = 5000})
    data.coins_earned = 0

    local force = player.force
    force.manual_mining_speed_modifier = 10
    force.mining_drill_productivity_bonus = 0
    force.manual_crafting_speed_modifier = -1

    -- 创建回收箱价目表按钮
    local top = player.gui.top
    if not top['recycling_prices_button'] then
        local button = top.add({
            type = 'button',
            name = 'recycling_prices_button',
            caption = {'amap.recycling_prices'}
        })
        button.style.minimal_height = 38
        button.style.maximal_height = 38
        button.style.minimal_width = 100
    end
end

-- 退出副本：清理模块自定义 GUI（recycling_prices_button / recycling_prices_frame）
-- 背包转移由框架统一处理
function M.on_exit(player, data, reason)
    local top = player.gui.top
    if top['recycling_prices_button'] then
        top['recycling_prices_button'].destroy()
    end
    local screen = player.gui.screen
    if screen['recycling_prices_frame'] then
        screen['recycling_prices_frame'].destroy()
    end

    -- 设置奖励系数：按挖到的金币数 / 10000 计算，封顶 2.0
    -- 副本框架在 on_exit 之后会读取 data.reward_multiplier 发放预抽奖励
    -- 系数 = 0 → 不给奖励；系数 > 0 → 按系数缩放发放
    -- 对配方产能/阵营加成/伤害加成（固定 3%）：multiplier 仅作为门槛，>0 即发放
    -- 对商店随机包（10K × multiplier）：multiplier 直接缩放物品总值
    if reason ~= "defeat" and reason ~= "error" then
        local coins = data.coins_earned or 0
        if coins > 0 then
            local mult = coins / 10000
            if mult > 2.0 then mult = 2.0 end
            Instance.set_reward_multiplier(player, mult)
        end
    end
end

-- 每 60 tick：处理回收箱换币
function M.on_tick(player, data)
    process_recycling_chest(player, data)
end

-- GUI 点击：处理回收箱价目表按钮
function M.on_gui_click(player, event)
    local element = event.element
    if not element or not element.valid then return end

    if element.name == 'recycling_prices_button' then
        show_recycling_prices_gui(player)
        return
    end
end

-- 玩家建造实体：建石墙给币（与原 dungeon.lua on_built_entity 一致）
function M.on_built_entity(player, event)
    local entity = event.entity
    if not entity or not entity.valid then return end

    if entity.name == "stone-wall" then
        if is_position_on_resource(entity.surface, entity.position) then
            return
        end

        local price = get_stone_wall_price(entity.position)
        player.insert({name = "coin", count = price})
        player.create_local_flying_text{
            text = "+" .. price,
            position = entity.position,
            color = {g = 1},
            time_to_live = 150
        }
    end
end

-- 机器人建造实体：仅处理石墙给币
function M.on_robot_built_entity(player, event)
    local entity = event.entity
    if not entity or not entity.valid then return end

    if entity.name == "stone-wall" then
        if is_position_on_resource(entity.surface, entity.position) then
            return
        end

        local price = get_stone_wall_price(entity.position)
        player.insert({name = "coin", count = price})
        player.create_local_flying_text{
            text = "+" .. price,
            position = entity.position,
            color = {g = 1},
            time_to_live = 150
        }
    end
end

-- 玩家挖实体：挖石墙扣币（不足回滚）
function M.on_player_mined_entity(player, event)
    local entity = event.entity
    if not entity or not entity.valid then return end

    if entity.name == "stone-wall" then
        local current_coins = player.get_item_count("coin")
        local cost = get_stone_wall_price(entity.position)

        if current_coins >= cost then
            player.remove_item({name = "coin", count = cost})
            player.create_local_flying_text{
                text = "-" .. cost,
                position = entity.position,
                color = {r = 1},
                time_to_live = 150
            }
        else
            Task.set_timeout_in_ticks(2, restore_stone_wall_token, {
                player_index = player.index,
                position = entity.position
            })
        end
    end
end

-- 玩家挖资源：挖煤/铁/铜扣 5 币（不足回滚）
function M.on_pre_player_mined_item(player, event)
    local entity = event.entity
    if not entity or not entity.valid then return end

    local price = ore_prices[entity.name]
    if price then
        local current_coins = player.get_item_count("coin")

        if current_coins >= price then
            player.remove_item({name = "coin", count = price})
        else
            Task.set_timeout_in_ticks(2, remove_mined_item_token, {
                player_index = player.index,
                item_name = entity.name
            })
        end
    end
end

-- 机器人预挖：仅处理石墙扣币（不足回滚）
function M.on_robot_pre_mined(player, event)
    local entity = event.entity
    if not entity or not entity.valid then return end

    if entity.name == "stone-wall" then
        local current_coins = player.get_item_count("coin")
        local cost = get_stone_wall_price(entity.position)

        if current_coins >= cost then
            player.remove_item({name = "coin", count = cost})
            player.create_local_flying_text{
                text = "-" .. cost,
                position = entity.position,
                color = {r = 1},
                time_to_live = 150
            }
        else
            player.remove_item({name = "stone-wall", count = 1})
            Task.set_timeout_in_ticks(2, restore_stone_wall_token, {
                player_index = player.index,
                position = entity.position
            })
        end
    end
end

--==============================================================================
-- 注册到框架
--==============================================================================

Instance.register(M.type, M)

return M
