local Public = {}

local WPT = require 'maps.amap.table'
local Event = require 'utils.event'
local Alert = require 'utils.alert'
local WD = require 'modules.wave_defense.table'
local RPG = require 'modules.rpg.table'
local Server = require 'utils.server'
local Factories = require 'maps.amap.production'
local diff = require 'maps.amap.diff'
local World = require 'maps.amap.world.framework'
local functions = require 'maps.amap.functions'
local round = math.round
local List = require 'maps.amap.production_list'
local MT = require "maps.amap.basic_markets"
local rpgtable = require 'modules.rpg.table'


local tianfu = require 'maps.amap.tianfu'
local EnemyArty = require 'maps.amap.enemy_arty'
local Dungeon = require 'maps.amap.dungeon'
local ICW = require 'maps.amap.ICW.functions'
local ICWT = require 'maps.amap.ICW.table'

function Public.protect(entity, operable)
    entity.minable_flag = false
    entity.destructible = false
    entity.operable = operable
end

----
-- 构建升级道具列表（不直接添加到市场，供 GUI 和市场共用）
local function build_upgrade_offers()
    local this = WPT.get()
    local price_mine = this.urgrad_mine * 3000 + 500
    local price_wall = this.health * 1000 + 5000
    local price_arty = this.arty * 9000 + 5000
    local price_biter_dam = this.biter_dam * 2000 + 1500
    local price_all_dam = this.urgrad_all_dam * 2000 + 5000

    local biter_nest = (this.max_nest_number - 1) * 2000 + 2500
    local biter_worm = (this.max_worm_number - 1) * 2000 + 2500

    local max_price = 100000

    if biter_worm >= max_price then
        biter_worm = max_price
    end

    if biter_nest >= max_price then
        biter_nest = max_price
    end

    if price_arty >= max_price then
        price_arty = max_price
    end
    if price_all_dam >= max_price then
        price_all_dam = max_price
    end
    if price_mine >= max_price then
        price_mine = max_price
    end

    if price_wall >= max_price then
        price_wall = max_price
    end

    if price_biter_dam >= max_price then
        price_biter_dam = max_price
    end

    -- offer_index 顺序按功能分类排列，必须与 apply_upgrade_effect/can_purchase_upgrade/on_market_item_purchased 中的索引一致
    -- 顺序：防御强化(1-2) → 伤害提升(3-4) → 敌方限制(5-6) → 天赋(7-9) → 特殊功能(10)
    -- 注：副本入口已从主市场移除，改由史诗木箱点击触发（见 instance.lua / world_main.lua）
    return {
        {  -- 1: 城墙加固 [防御强化]
            price = {{name = "coin", count = price_wall}},
            offer = {
                type = 'nothing',
                effect_description = {'amap.buy_health_wall', this.health * 0.1}
            }
        },
        {  -- 2: 地雷上限升级 [防御强化]
            price = {{name = "coin", count = price_mine}},
            offer = {
                type = 'nothing',
                effect_description = {'amap.urgrade_mine', this.urgrad_mine * 200 + 400}
            }
        },
        {  -- 3: 全伤害升级 [伤害提升]
            price = {{name = "coin", count = price_all_dam}},
            offer = {
                type = 'nothing',
                effect_description = {'amap.buy_all_dam', this.urgrad_all_dam * 0.01}
            }
        },
        {  -- 4: 重炮伤害升级 [伤害提升]
            price = {{name = "coin", count = price_arty}},
            offer = {
                type = 'nothing',
                effect_description = {'amap.buy_arty_dam', this.arty * 0.1}
            }
        },
        {  -- 5: 虫巢上限升级 [敌方限制]
            price = {{name = "coin", count = biter_nest}},
            offer = {
                type = 'nothing',
                effect_description = {'amap.biter_nest', this.max_nest_number}
            }
        },
        {  -- 6: 沙虫上限升级 [敌方限制]
            price = {{name = "coin", count = biter_worm}},
            offer = {
                type = 'nothing',
                effect_description = {'amap.biter_worm', this.max_worm_number}
            }
        },
        {  -- 7: 购买天赋（普通） [天赋]
            price = {{name = "coin", count = 65000}},
            offer = {
                type = 'nothing',
                effect_description = {'amap.buy_talent'}
            }
        },
        {  -- 8: 购买天赋（中级） [天赋]
            price = {{name = "coin", count = 90000}},
            offer = {
                type = 'nothing',
                effect_description = {'amap.buy_talent_mid'}
            }
        },
        {  -- 9: 购买天赋（高级） [天赋]
            price = {{name = "coin", count = 130000}},
            offer = {
                type = 'nothing',
                effect_description = {'amap.buy_talent_high'}
            }
        },
        {  -- 10: 捐赠粮草 [特殊功能]
            price = {{name = "coin", count = 1000}},
            offer = {
                type = 'nothing',
                effect_description = {'amap.buy_protectors', this.protectors_value * 10}
            }
        }
    }
end

local function urgrade_item(market)
    local offers = build_upgrade_offers()
    for _, offer in ipairs(offers) do
        market.add_market_item(offer)
    end
end

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
}, -- {price = {{name = "coin", count = 500}}, offer = {type = 'give-item', item = 'spidertron-remote', count = 1}},
{
    price = {{name = "coin", count = 35000}},
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
} -- {price = {{name = "coin", count = 60000}}, offer = {type = 'give-item', item = 'rocket-silo', count = 1}}
}




local function get_rand_item()
    local rand_item = {}
    local wave_number = WD.get('wave_number') or 0

    local rarity = math.floor( (wave_number / 100))

    if rarity < 2 then
        rarity = 2
    end
    if rarity > 12 then
        rarity = 12
    end
    rand_item = MT.get_random_item(rarity, false, false)
    return rand_item
end

function Public.refresh_shop(market)
    if not market or not market.valid then
        return
    end
    local this = WPT.get()
    this.market_random_offers = {}

    market.clear_market_items()
    urgrade_item(market)

    -- 世界框架：部分世界（如世界15 纯塔防）屏蔽指定市场物品（载具/鱼↔币兑换/随机商品保留）
    local blocked = World.get_field(this.world_number, 'blocked_market_offers')
    for _, item in pairs(market_items) do
        if blocked and item.offer and blocked[item.offer.item] then
            -- 该世界屏蔽此物品
        else
            market.add_market_item(item)
        end
    end


    if this.world_number ~= 11 then
            local rand_item = get_rand_item()

    for _, item in pairs(rand_item) do
        item.price[1].count = math.floor(item.price[1].count * 1.1)
        market.add_market_item(item)
        table.insert(this.market_random_offers, item)
    end

    end


    if this.world_number == 8 or this.world_number == 7 then
        market.add_market_item({
            price = {{name = "coin", count = 300}},
            offer = {
                type = 'give-item',
                item = 'car',
                count = 1
            }
        })
    end
    if this.world_number == 13 then
        market.add_market_item({
            price = {{name = "coin", count = 500}},
            offer = {
                type = 'give-item',
                item = 'linked-chest',
                count = 1
            }
        })
        market.add_market_item({
            price = {{name = "coin", count = 500}},
            offer = {
                type = 'give-item',
                item = 'wooden-chest',
                count = 1,
                quality = 'legendary'
            }
        })
    end

    -- 世界框架：部分世界（如世界15）在岩石市场追加固定物品（按"所有物品价值表"定价）
    local extra_items = World.get_field(this.world_number, 'rock_shop_extra_items')
    if extra_items then
        for _, item in ipairs(extra_items) do
            market.add_market_item({
                price = {{name = "coin", count = item.gold}},
                offer = {type = 'give-item', item = item.name, count = 1}
            })
        end
    end

    game.print({'amap.refresh_shop'})

    -- 通知 GUI 刷新（如果 market_gui 模块已加载）
    if Public._on_shop_refreshed then
        Public._on_shop_refreshed()
    end
end

-- ============ 供 market_gui 模块调用的公共函数 ============

-- 获取升级道具列表（含当前价格）
function Public.get_upgrade_offers()
    return build_upgrade_offers()
end

-- 获取固定道具列表（market_items + 世界特定道具）
function Public.get_fixed_offers()
    local this = WPT.get()
    local offers = {}
    for _, item in ipairs(market_items) do
        table.insert(offers, item)
    end
    -- 世界特定道具
    if this.world_number == 8 or this.world_number == 7 then
        table.insert(offers, {
            price = {{name = "coin", count = 300}},
            offer = {type = 'give-item', item = 'car', count = 1}
        })
    end
    if this.world_number == 13 then
        table.insert(offers, {
            price = {{name = "coin", count = 500}},
            offer = {type = 'give-item', item = 'linked-chest', count = 1}
        })
        table.insert(offers, {
            price = {{name = "coin", count = 500}},
            offer = {type = 'give-item', item = 'wooden-chest', count = 1, quality = 'legendary'}
        })
    end
    return offers
end

-- 获取随机道具列表（refresh_shop 时缓存）
function Public.get_random_offers()
    local this = WPT.get()
    return this.market_random_offers or {}
end

-- 前置检查：玩家是否可以购买该升级
-- 返回 true 可以购买，false 不可购买（已向玩家打印原因）
function Public.can_purchase_upgrade(player, offer_index)
    local this = WPT.get()

    -- offer_index 3: 全伤害升级，伤害倍率达到上限时不可购买
    if offer_index == 3 then
        local damage_multiplier = this.damage_multiplier or 1
        if damage_multiplier > 3 then
            player.print({'amap.damage_multiplier_max', player.name})
            return false
        end
    end

    -- offer_index 7/8/9: 天赋购买上限检查
    if offer_index == 7 or offer_index == 8 or offer_index == 9 then
        if not this.tianfu_buy_count or type(this.tianfu_buy_count) ~= 'table' then
            this.tianfu_buy_count = {}
        end
        if not this.tianfu_buy_count[player.index] then
            this.tianfu_buy_count[player.index] = 0
        end
        if this.tianfu_buy_count[player.index] >= 25 then
            player.print({'amap.tianfu_limit_reached', player.name})
            return false
        end
    end

    return true
end

-- 应用升级效果（假设金币已扣除）
-- 此函数从 on_market_item_purchased 中提取，供 GUI 和事件共用
function Public.apply_upgrade_effect(player, offer_index)
    local this = WPT.get()
    local market = this.shop
    if not market or not market.valid then
        return
    end

    if offer_index == 1 then
        this.health = this.health + 1
        functions.set_force_damage_modifier(game.forces.enemy, -0.1)
        game.print({'amap.buy_wall_over', player.name, this.health * 0.1})

    elseif offer_index == 2 then
        this.urgrad_mine = this.urgrad_mine + 1
        this.max_mine = 400 + this.urgrad_mine * 200
        game.print({'amap.urgrad_mine_over', player.name, this.max_mine})

    elseif offer_index == 3 then
        this.urgrad_all_dam = this.urgrad_all_dam + 1
        functions.set_force_damage_modifier(game.forces.player, 0.01, true)
        game.print({'amap.urgrad_all_dam_over', player.name, this.urgrad_all_dam * 0.01})

    elseif offer_index == 4 then
        this.arty = this.arty + 1
        local e_old = game.forces.player.get_ammo_damage_modifier("artillery-shell")
        game.forces.player.set_ammo_damage_modifier("artillery-shell", e_old + 0.1)
        game.print({'amap.buy_arty_over', player.name, this.arty * 0.1 + 1})

    elseif offer_index == 5 then
        this.max_nest_number = this.max_nest_number + 1
        game.print({'amap.buy_biter_nest', player.name, this.max_nest_number})

    elseif offer_index == 6 then
        this.max_worm_number = this.max_worm_number + 1
        game.print({'amap.buy_biter_worm', player.name, this.max_worm_number})

    elseif offer_index == 7 then
        if not this.tianfu_buy_count or type(this.tianfu_buy_count) ~= 'table' then
            this.tianfu_buy_count = {}
        end
        if not this.tianfu_buy_count[player.index] then
            this.tianfu_buy_count[player.index] = 0
        end
        if not this.tianfu_count then this.tianfu_count = {} end
        if not this.tianfu_count[player.index] then this.tianfu_count[player.index] = 0 end
        tianfu.get_new_tianfu(player)
        this.tianfu_count[player.index] = this.tianfu_count[player.index] - 1
        this.tianfu_buy_count[player.index] = this.tianfu_buy_count[player.index] + 1
        game.print(player.name .. '购买了1个天赋（已购买' .. this.tianfu_buy_count[player.index] .. '次）')

    elseif offer_index == 8 then
        if not this.tianfu_buy_count or type(this.tianfu_buy_count) ~= 'table' then
            this.tianfu_buy_count = {}
        end
        if not this.tianfu_buy_count[player.index] then
            this.tianfu_buy_count[player.index] = 0
        end
        if not this.tianfu_count then this.tianfu_count = {} end
        if not this.tianfu_count[player.index] then this.tianfu_count[player.index] = 0 end
        tianfu.get_new_tianfu(player, 'mid')
        this.tianfu_count[player.index] = this.tianfu_count[player.index] - 1
        this.tianfu_buy_count[player.index] = this.tianfu_buy_count[player.index] + 1
        game.print(player.name .. '购买了1个中级天赋（已购买' .. this.tianfu_buy_count[player.index] .. '次）')

    elseif offer_index == 9 then
        if not this.tianfu_buy_count or type(this.tianfu_buy_count) ~= 'table' then
            this.tianfu_buy_count = {}
        end
        if not this.tianfu_buy_count[player.index] then
            this.tianfu_buy_count[player.index] = 0
        end
        if not this.tianfu_count then this.tianfu_count = {} end
        if not this.tianfu_count[player.index] then this.tianfu_count[player.index] = 0 end
        tianfu.get_new_tianfu(player, 'high')
        this.tianfu_count[player.index] = this.tianfu_count[player.index] - 1
        this.tianfu_buy_count[player.index] = this.tianfu_buy_count[player.index] + 1
        game.print(player.name .. '购买了1个高级天赋（已购买' .. this.tianfu_buy_count[player.index] .. '次）')

    elseif offer_index == 10 then
        this.protectors_value = this.protectors_value + 1
        game.print({'amap.protectors_value_over', player.name, 1000, this.protectors_value * 10})

    else
        return  -- 未知 offer_index，不做处理
    end

    -- 播放音效并刷新市场
    market.force.play_sound({
        path = 'utility/new_objective',
        volume_modifier = 0.75
    })
    Public.refresh_shop(market)
end

function Public.ft(surface, y)
    local this = WPT.get()
    if this.world_number == 13 then
        return
    end
    local factory = "assembling-machine-2"
    for key = 1, 20, 1 do
        if List[key].kind == "furnace" then
            factory = "electric-furnace"
        else
            factory = "assembling-machine-2"
        end
        local position = {
            x = -16 + key * 3,
            y = -18 + y
        }
        if (key >= 11) then
            position = {
                x = -46 + key * 3,
                y = -12 + y
            }
        end
        local e = surface.create_entity({
            name = factory,
            force = "player",
            position = position
        })
        e.disabled_by_script = true
        Public.protect(e, false)
        e.rotatable = false
        Factories.register_train_assembler(e, key)
        if List[key].kind == "assembler" or List[key].kind == "fluid-assembler" then
            e.set_recipe(List[key].recipe_override or List[key].name)
            e.recipe_locked = true
            e.direction = defines.direction.south
        end
    end
end

function Public.market(surface)
    local this = WPT.get()

    local silo
    if this.world_number == 13 then
        local position = {x = 0, y = 10}
        -- 预架设铁轨
        for y = -6, 20, 2 do
            surface.create_entity({
                name = "straight-rail",
                position = {x = position.x, y = position.y + y},
                force = game.forces.player,
                direction = 0
            })
        end
        -- 创建火车头作为 silo（放在铁轨中心 y=8）
        silo = surface.create_entity({
            name = "locomotive",
            position = {x = position.x, y = 8},
            force = game.forces.player,
            create_build_effect_smoke = false
        })
        silo.minable_flag = false
        silo.get_inventory(defines.inventory.fuel).insert({name = 'coal', count = 50})
        -- 注册 locomotive 到 ICW 内部空间
        ICW.register_wagon(silo, 0)
        ICWT.set('locomotive', silo)

        -- 在火车头后方连接一节初始 cargo-wagon（放在铁轨中心 y=14）
        local cargo = surface.create_entity({
            name = "cargo-wagon",
            position = {x = position.x, y = 14},
            force = game.forces.player,
            create_build_effect_smoke = false
        })
        if cargo and cargo.valid then
            cargo.minable_flag = false
            -- 注册 cargo-wagon 到 ICW 内部空间
            ICW.register_wagon(cargo, 0)
            ICWT.get('cargo_wagons')[cargo.unit_number] = cargo
            ICWT.set('wagon_count', 1)

            -- 往火车车厢里放4个传说木箱子
            local cargo_inv = cargo.get_inventory(defines.inventory.cargo_wagon)
            if cargo_inv then
                cargo_inv.insert({name = 'wooden-chest', count = 4, quality = 'legendary'})
            end
        end
    elseif this.world_number ~= 8 then
        if this.world_number == 7 then
            silo = surface.create_entity {
                name = "spidertron",
                position = {
                    x = 0,
                    y = 10
                },
                force = game.forces.player
            }
            silo.grid.inhibit_movement_bonus = true

            -- 在世界7的主世界创建不可被挖掘不可被破坏的蓄电池
            local accumulator = surface.create_entity({
                name = 'electric-energy-interface',
                position = {
                    x = 0,
                    y = 6
                },
                force = 'player',
                create_build_effect_smoke = false
            })
         accumulator.destructible = false
                --设置为不可操作
                accumulator.operable = false
                accumulator.minable_flag = false
                 --设置发电量为130MW

         local silo_position = {x = 0, y =   16}
      local silo = surface.create_entity({
        name = "rocket-silo",
        position = silo_position,
        force = game.forces.player
      })

      if silo and silo.valid then
        silo.destructible = false
        silo.minable_flag = false
      end
            -- 在世界7的异世界创建不可被挖掘不可被破坏的蓄电池
        else
            silo = surface.create_entity {
                name = "rocket-silo",
                position = {
                    x = 0,
                    y = 16
                },
                force = game.forces.player
            }
        end
        if this.world_number == 10 then
          rendering.draw_text {
            text = "司令部",
            surface = silo.surface,
            target = {
              entity = silo,
              offset = {0, -2.5}
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

          --生成曹军的3个堡垒
          --坐标分别为：{100，-350}，{0，-350}，{-100，-350}
          local baolei_positions = {
            {x = 100, y = -350},
            {x = 0, y = -350},
            {x = -100, y = -350}
          }

          for _, pos in pairs(baolei_positions) do
            EnemyArty.baolei(pos, 650, surface)
          end
        end
    else
        silo = surface.create_entity {
            name = "spidertron",
            position = {
                x = 0,
                y = 10
            },
            force = game.forces.player
        }
        silo.grid.inhibit_movement_bonus = true
        -- Task.set_timeout_in_ticks(60*5, zhizhu, silo)
        local e3 = surface.create_entity({
            name = 'linked-chest',
            position = {
                x = 0,
                y = 9
            },
            force = 'player',
            create_build_effect_smoke = false
        })

        e3.destructible = false
        e3.minable_flag = false

        -- 在世界8的主世界创建不可被挖掘不可被破坏的蓄电池
        local accumulator = surface.create_entity({
            name = 'electric-energy-interface',
            position = {
                x = 0,
                y = 6
            },
            force = 'player',
            create_build_effect_smoke = false
        })
        accumulator.destructible = false
        accumulator.minable_flag = false
        accumulator.operable = false

                 local silo_position = {x = 0, y =  16}
      local silo = surface.create_entity({
        name = "rocket-silo",
        position = silo_position,
        force = game.forces.player
      })

      if silo and silo.valid then
        silo.destructible = false
        silo.minable_flag = false
      end
    end


    if this.world_number ~= 13 then
        local market = surface.create_entity {
            name = "market",
            position = {
                x = 0,
                y = -5
            },
            force = game.forces.player
        }
        this.shop = market
        market.destructible = false
        Public.refresh_shop(market)
    else
        -- 世界13：在火车内部空间创建商店、原油井、组装机
        local loco = ICWT.get('locomotive')
        if loco and loco.valid then
            local wagons = ICWT.get('wagons')
            -- locomotive 内部：水坑 + 商店 + 原油井
            local wagon = wagons[loco.unit_number]
            if wagon then
                local wagon_surface = game.surfaces[wagon.surface]
                if wagon_surface and wagon_surface.valid then
                    local area = wagon.area
                    -- 参考世界1布局：组装机在上 → 商店在中 → 水坑在下
                    -- 世界1相对位置（相对于y=0）：组装机 y=-18/-12，商店 y=-5，水坑 y=-2~1
                    -- 锚点：商店放在 area.left_top.y + 30（车头中间偏上）

                    -- 组装机（只在车头内部创建一次，位于商店上方）
                    local factory = "assembling-machine-2"
                    for key = 1, 20, 1 do
                        if List[key].kind == "furnace" then
                            factory = "electric-furnace"
                        else
                            factory = "assembling-machine-2"
                        end
                        -- 世界1：上排 y=-18，下排 y=-12（相对于商店 y=-5）
                        -- 换算：上排在商店上方 13 格，下排在商店上方 7 格
                        local position = {
                            x = -16 + key * 3,
                            y = area.left_top.y + 17  -- 商店上方13格 (30-13=17)
                        }
                        if (key >= 11) then
                            position = {
                                x = -46 + key * 3,
                                y = area.left_top.y + 23  -- 商店上方7格 (30-7=23)
                            }
                        end
                        local e = wagon_surface.create_entity({
                            name = factory,
                            force = "player",
                            position = position
                        })
                        if e and e.valid then
                            e.disabled_by_script = true
                            Public.protect(e, false)
                            e.rotatable = false
                            Factories.register_train_assembler(e, key)
                            if List[key].kind == "assembler" or List[key].kind == "fluid-assembler" then
                                e.set_recipe(List[key].recipe_override or List[key].name)
                                e.recipe_locked = true
                                e.direction = defines.direction.south
                            end
                        end
                    end

                    -- 商店（中间）
                    local market = wagon_surface.create_entity({
                        name = "market",
                        position = {x = 0, y = area.left_top.y + 30},
                        force = game.forces.player
                    })
                    this.shop = market
                    market.destructible = false
                    Public.refresh_shop(market)

                    -- 水坑（9x9，商店下方，原3x3的3倍）
                    local water_pos = {x = 0, y = area.left_top.y + 44}
                    for i = 1, 9 do
                        for b = 1, 9 do
                            local p = {
                                x = water_pos.x + b - 5,
                                y = water_pos.y - i - 4
                            }
                            if wagon_surface.can_place_entity({name = "steel-chest", position = p}) then
                                wagon_surface.set_tiles({{name = "water", position = p}})
                            end
                        end
                    end
                end
            end
        end
    end



    this.silo = silo
    silo.minable_flag = false

    if this.world_number == 14 then
        local chest_position = surface.find_non_colliding_position('wooden-chest', {x = silo.position.x + 7, y = silo.position.y}, 32, 1)
        if chest_position then
            local chest = surface.create_entity({
                name = 'wooden-chest',
                position = chest_position,
                force = game.forces.player
            })
            if chest and chest.valid then
                chest.minable_flag = true
                chest.destructible = true
                local chest_inv = chest.get_inventory(defines.inventory.chest)
                if chest_inv then
                    chest_inv.insert({name = 'cargo-landing-pad', count = 1})
                end
            end
        end
    end
end

local function on_rocket_launched(event)
    if true then return end
      if event.rocket_silo.surface.name ~= 'nauvis' then return end
    local this = WPT.get()
    local rpg_t = RPG.get('rpg_t')
    local money = 1000
    local point = 0
    local map = diff.get()
    if map.rocket_diff then
        money = money + this.times * 1000
    end

    if money >= 500 then
        money = 500
    end
    if this.goal == 1 and this.times == 2 then
        game.print {'amap.goal_1'}
          game.print({'amap.reward', this.times, point, money}, {
            r = 0.22,
            g = 0.88,
            b = 0.22
        })
    end

    for k, player in pairs(game.connected_players) do
        rpg_t[player.index].points_left = rpg_t[player.index].points_left + point
        player.insert {
            name = 'coin',
            count = money
        }



        -- if not map.cunkuang[player.name] then
        --     map.cunkuang[player.name] = 0
        -- end
        -- local coin = 100 * (this.times - 1)
        -- coin = 50
        -- if coin >= 1000 then
        --     coin = 1000
        -- end
        -- map.cunkuang[player.name] = map.cunkuang[player.name] + coin
        -- if map.cunkuang[player.name] >= 10000 then
        --     map.cunkuang[player.name] = 10000
        -- end

        -- player.print('你的账户已存入' .. coin ..
        --                  '金币，之后的对局中，你可以输入/tk [金币数]，来取出你的金币,存款上限为10K')
    end
    if not this.pass then
        local wave_number = WD.get('wave_number')
        local msg = {'amap.pass', wave_number}
        for k, player in pairs(game.connected_players) do
            Alert.alert_player(player, 25, msg)
        end
        Server.to_discord_embed(table.concat({'** we win the game ! Record is ', wave_number}))
        this.pass = true
    end
    this.times = this.times + 1
end


-- 市场购买事件（回退用途：自定义 GUI 被绕过时仍能正常工作）
-- 注意：官方 GUI 被拦截后此事件一般不会触发，但保留以兼容
local function on_market_item_purchased(event)
    local this = WPT.get()
    local market = event.market
    if market ~= this.shop then
        return
    end
    local player = game.players[event.player_index]

    local offer_index = event.offer_index
    local offers = market.get_market_items()
    local bought_offer = offers[offer_index].offer

    -- give-item 类型由游戏自动处理，无需干预
    if bought_offer.type ~= "nothing" then
        return
    end

    -- 退款场景：游戏已扣款，但购买条件不满足，需退还金币
    if offer_index == 3 then
        local damage_multiplier = this.damage_multiplier or 1
        if damage_multiplier > 3 then
            local price_all_dam = this.urgrad_all_dam * 2000 + 5000
            local max_price = 100000
            if price_all_dam >= max_price then
                price_all_dam = max_price
            end
            player.insert({name = "coin", count = price_all_dam})
            player.print({'amap.damage_multiplier_max', player.name})
            return
        end
    end

    if offer_index == 7 or offer_index == 8 or offer_index == 9 then
        if not this.tianfu_buy_count or type(this.tianfu_buy_count) ~= 'table' then
            this.tianfu_buy_count = {}
        end
        if not this.tianfu_buy_count[player.index] then
            this.tianfu_buy_count[player.index] = 0
        end
        if this.tianfu_buy_count[player.index] >= 25 then
            local refund = 65000
            if offer_index == 8 then refund = 90000 end
            if offer_index == 9 then refund = 130000 end
            player.insert({name = 'coin', count = refund})
            player.print({'amap.tianfu_limit_reached', player.name})
            return
        end
    end

    -- 正常升级：应用效果（内部会刷新市场）
    Public.apply_upgrade_effect(player, offer_index)
end

Event.add(defines.events.on_rocket_launched, on_rocket_launched)
Event.add(defines.events.on_market_item_purchased, on_market_item_purchased)


local function on_research_finished(event)
    local this = WPT.get()
    if this.shop and this.shop.valid then
        Public.refresh_shop(this.shop)
    end
end
Event.add(defines.events.on_research_finished, on_research_finished)
return Public
