local Event = require 'utils.event'
local WPT = require 'maps.amap.table'
local RPG = require 'modules.rpg.table'
local diff = require 'maps.amap.diff'
local World = require 'maps.amap.world.framework'
local reduce_player_damage_over_time = require 'maps.amap.functions'.reduce_player_damage_over_time
local WD = require 'modules.wave_defense.table'
local game_info = require'maps.amap.diff'.game_info
local IC = require 'maps.amap.ic.table'
local ICWLinkChestGui = require 'maps.amap.ICW.link_chest_gui'
local ICWTable = require 'maps.amap.ICW.table'
local Alert = require 'utils.alert'
local Server = require 'utils.server'
local get_random_car = require"maps.amap.functions".get_random_car
local Task = require 'utils.task'
local Token = require 'utils.token'
local Dungeon = require 'maps.amap.dungeon'

local refresh_shop = require"maps.amap.rock".refresh_shop
local ft = require"maps.amap.rock".ft
local Collapse = require 'modules.collapse'

local Reset_map = require 'maps.amap.main'.reset_map

local car_name = {
    ["car"] = true,
    ["tank"] = true,
    ["spidertron"] = true,
    ["wood"] = true
}

local car_items = {
    -- ['defender-capsule'] = 100,
   --  ['power-armor-mk2'] = 1,
    ['gun-turret'] = 16,
    ['firearm-magazine'] = 240,
    ['stone-wall'] = 144,
    ['burner-mining-drill'] = 34,
    -- ['electric-mining-drill'] = 8,
    ['stone-furnace'] = 20,
    ['steam-engine'] = 2,
    ['boiler'] = 1,
    ['offshore-pump'] = 1,
    ['raw-fish'] = 10
}
local entities_that_earn_coins = {
    ['artillery-turret'] = true,
    ['gun-turret'] = true,
    ['laser-turret'] = true,
    ['flamethrower-turret'] = true
}

local function unstuck_player(index)
  local player = game.get_player(index)
  local surface = player.physical_surface
  if player.physical_surface.name ~= 'nauvis' then return end
  local position = surface.find_non_colliding_position('character', player.physical_position, 32, 0.5)
  if not position then
    return
  end
  player.teleport(position, surface)
end

local zysc = Token.register(function()
    local this = WPT.get()
    if this.shop and this.shop.valid then
        this.shop.destroy()
    end
    local surface = this.silo.surface
    local market = surface.create_entity {
        name = "market",
        position = {
            x = 0,
            y = this.silo.position.y - 5
        },
        force = game.forces.player
    }

    market.minable_flag = false
    market.destructible = false
    this.shop = market
    refresh_shop(market)

    for _, assemblers in pairs(this.productionsphere.train_assemblers) do
        local entity = assemblers.entity
        if entity and entity.valid then
            entity.destroy()
        end
    end
    this.productionsphere.train_assemblers = {}
    ft(surface, this.silo.position.y)

    for k, player in pairs(game.connected_players) do
        unstuck_player(player.index)
    end
end)

local give_car = Token.register(function(player)
    player.insert({
        name = 'car',
        count = 1
    })
end)
local new_biter = Token.register(function(data)

    local e = data.surface.create_entity({
        name = data.name,
        position = data.position,
        force = game.forces.enemy
    })
end)

local function item_build_car(player)
    game.print({'amap.build_car', player.name})
    player.print({"", "[color=255, 100, 100]", {"amap.car_jingao"}, "[/color]"})
    local wave_number = WD.get('wave_number')

    local k = 1
    local map = diff.get()

    -- 世界14：额外太空物资（叠加在通用物资之上）
    if map.world == 14 then
      local world14_items = {
        {'solar-panel', 4},
        {'asteroid-collector', 2},
        {'crusher', 3},
        {'space-platform-foundation', 200},
        {'electric-furnace', 4},
      }
      for _, entry in ipairs(world14_items) do
        player.insert({name = entry[1], count = entry[2]})
      end
      -- 火箭平台启动包（太空平台）
      player.insert({name = 'space-platform-starter-pack', count = 1})
      player.print({"", "[color=255, 200, 0]", {"amap.world14_start_items"}, "[/color]"})
      
      -- 世界14通关加成：每通关2波，下次汽车物资多获得1金币
      local world14_record = map.map_record[14] or 0
      local bonus_coins = math.floor(world14_record / 2)
      if bonus_coins > 0 then
        player.insert({name = 'coin', count = bonus_coins})
        player.print({"", "[color=0, 255, 200]", {"amap.world14_coin_bonus", bonus_coins}, "[/color]"})
      end
      
      -- 不再 return，继续执行下方通用物资发放
    end

    -- 车载开局物资钩子：由世界框架按世界提供（如世界15 仅发战斗物资 + 金币）。
    -- 返回 true 表示已处理，跳过下方通用物资循环；其它世界保持原逻辑不变。
    local car_hook = World.get_field(map.world, 'on_car_placed')
    local car_handled = false
    if car_hook then
        car_handled = car_hook(player, wave_number, car_items)
    end

    if not car_handled then
        for item, amount in pairs(car_items) do
            if item == 'firearm-magazine' or item == 'gun-turret' or item == 'stone-wall' then
                if item == 'firearm-magazine' and wave_number >= 450 then
                    item = "piercing-rounds-magazine"
                end
                if item == 'piercing-rounds-magazine' and wave_number >= 1000 then
                    item = "uranium-rounds-magazine"
                end

                if k < 0 then
                    k = 1
                end
                if k >= 10 then
                    k = 10
                end
                player.insert({
                    name = item,
                    count = math.floor(amount * k)
                })
            end
            player.insert({
                name = item,
                count = math.floor(amount)
            })
        end
    end

    if map.world == 3 then
        player.insert({
            name = 'landfill',
            count = 256
        })
        -- 添加红色文字提示关于捕鱼车功能
        player.print({"", "[color=255, 0, 0]", {"amap.fishing_tank_info"}, "[/color]"})
    end

    if map.world == 10 then
        -- 添加红色文字提示关于赤壁之战玩法
        player.print({"", "[color=255, 0, 0]", {"amap.world10_info"}, "[/color]"})
    end

    if map.world == 7 then
        player.insert({
            name = 'linked-chest',
            count = 1
        })
        player.insert({
            name = 'landfill',
            count = 256
        })
        player.insert({
            name = 'tank',
            count = 1
        })
    end

    if map.world == 13 then
        player.insert({
            name = 'rail',
            count = 20
        })
    end
    
    -- 当this.jjc == 2时，额外给予5K金币
    local this = WPT.get()
    if this.jjc == 2 then
        player.insert({
            name = 'coin',
            count = 5000
        })
        player.print({"", "[color=255, 0, 0]", {"amap.jjc_coin_bonus"}, "[/color]"})
    end

    if map.world == 12 then
        this.tianfu_count[player.index] = (this.tianfu_count[player.index] or 0) -1
        player.print({"", "[color=255, 0, 0]", {"amap.world12_talent_bonus"}, "[/color]"})
    end

    if diff.has_all_worlds_3000_reward() then
        this.tianfu_count[player.index] = (this.tianfu_count[player.index] or 0) - 1
        player.print({"", "[color=255, 215, 0]", {"amap.all_worlds_3000_reward"}, "[/color]"})
    end

    if diff.has_world_13_4000_reward() then
        player.insert({name = 'wooden-chest', count = 1, quality = 'legendary'})
        player.print({"", "[color=255, 215, 0]", {"magic_wood.world_13_reward_chest"}, "[/color]"})
    end
end
local function kill_base_biter()
    local this = WPT.get()
    local main_surface = game.surfaces[this.active_surface_index]
    if not main_surface then
        return false
    end
    local entities = main_surface.find_entities_filtered {
        position = game.forces.player.get_spawn_position(main_surface),
        radius = 5,
        force = game.forces.enemy
    }

    if #entities ~= 0 then
        for k, v in pairs(entities) do
            v.die()
        end

    end
end

local function get_car_number()
    local this = WPT.get()
    local car_number = 0
    local map = diff.get()
    local active_surface_index = this.active_surface_index
    
    for k, player in pairs(game.connected_players) do
        if this.tank[player.index] and this.tank[player.index].valid then
            if this.tank[player.index].surface.index == game.surfaces[active_surface_index].index then
                car_number = car_number + 1
                this.tank[player.index].destructible = true
            end
        else
            this.tank[player.index] = nil
            this.whos_tank[player.index] = nil
            this.have_been_put_tank[player.index] = false
        end
    end
    return car_number
end

local function check_silo_and_car_status()
    local this = WPT.get()
    local map = diff.get()
    
    -- 如果火箭发射井存在，则不执行重开逻辑
    if this.silo and this.silo.valid then
        return false
    end
    
    -- 获取当前车子数量
    local car_number = get_car_number()
    
    -- 如果车子数量为0且游戏状态不是重开倒计时状态，则开始重开倒计时
    if car_number == 0 and this.start_game ~= 3 then
        this.reset_time = 600 * 3
        this.start_game = 3
        
        -- 判断是否是第一次游戏
        if map.sum == 0 then
            game.print({'amap.ready_to_reset_first', 30}, {255, 0, 0})
        else
            game.print({'amap.ready_to_reset'}, {255, 0, 0})
        end
        return true
    end
    
    return false
end


local function on_player_build_entity(event)
    local this = WPT.get()
    local entity = event.entity
    if not entity then
        return
    end
    if not entity.valid then
        return
    end
   
    local player = game.players[event.player_index]
    local index = player.index

    if entity.name == 'gun-turret' then
        entity.kills = 0
    end

    if entities_that_earn_coins[entity.name] then
        if not this.gun_turret then
            this.gun_turret = {}
        end
        if not this.gun_turret[entity.unit_number] then
            this.gun_turret[entity.unit_number] = index
        end
    end

    if entity.type == 'entity-ghost' and entity.ghost_name == 'linked-chest' then
        entity.destroy()
    end

    if entity.name == 'linked-chest' then
        -- 非 nauvis 表面不允许放置关联箱，直接收回背包
        if entity.surface.name ~= 'nauvis' then
            entity.destroy()
            player.insert({name = 'linked-chest', count = 1})
            return
        end

        if this.world_number ~= 13 then
            entity.destructible = false
        end
        this.link[index] = entity.unit_number
        this.link_player[entity.unit_number] = player

        -- 世界13：自动连接到第一个车厢输入箱A，漂浮文字显示连接信息
        if this.world_number == 13 and entity.surface.name == ICWTable.get('allowed_surface') then
            local default_link_id = ICWLinkChestGui.get_default_link_id()
            if default_link_id then
                entity.link_id = default_link_id
            end
            ICWLinkChestGui.update_link_chest_label(entity, entity.link_id)
        else
            rendering.draw_text {
                text = player.name .. '的箱子',
                surface = player.physical_surface,
                target = entity,
                target_offset = {0, -1},
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
    end


    if entity.name == 'car' then
        if this.world_number == 7 or this.world_number == 8 then
            if player.physical_surface ~= this.yiciyuan_surface then
                if not this.ciyuan_pos[index] then
                    this.ciyuan_pos[index] = {
                        x = 0,
                        y = 0
                    }
                    item_build_car(player)
                end

                this.now_pos[index] = player.physical_position
                player.teleport(this.yiciyuan_surface.find_non_colliding_position('character', this.ciyuan_pos[index],
                    10, 1, true) or {
                    x = 0,
                    y = 0
                }, this.yiciyuan_surface)
                entity.destroy()
                Task.set_timeout_in_ticks(60, give_car, player)

            else
                local main_surface = game.surfaces[this.active_surface_index]
                this.ciyuan_pos[index] = player.physical_position
                local get_tile = main_surface.get_tile(this.now_pos[index])
                if get_tile.valid and get_tile.name == 'out-of-map' then
                    player.teleport(main_surface.find_non_colliding_position('character', this.silo.position, 20, 1,
                        false) or {
                        x = 0,
                        y = 0
                    }, main_surface)
                else
                    player.teleport(this.now_pos[index], game.surfaces[this.active_surface_index])
                    unstuck_player(player.index)
                end

                Task.set_timeout_in_ticks(60, give_car, player)

                entity.destroy()

            end

            return
        end
    end

    if (entity.name == 'tank' or entity.name == 'spidertron') and (this.world_number == 7 or this.world_number == 8) then
        if player.physical_surface == this.yiciyuan_surface then
            if not this.first_build_car[index] then
                item_build_car(player)
                this.first_build_car[index] = true
                if not this.qcdj[index] then
                    this.qcdj[index] = 1
                end
                if not this.dist_index[index] then
                    this.dist_index[index] = 1
                end
            end
            if not this.have_been_put_tank[index] then
                this.have_been_put_tank[index] = true
            end
            if this.whos_tank[index] == nil then
                this.whos_tank[index] = entity.unit_number
            end
            if this.tank[index] == nil then
                this.tank[index] = entity
                player.print({'amap.car_info'}, {
                    r = 100,
                    b = 200,
                    g = 200
                })
                all_dist = {100, 150, 999}
            end
            return
        end
    end

    if this.die_time[index] and car_name[entity.name] then
        if this.die_time[index] + 60 * 60 * 5 > game.tick then
            player.insert {
                name = entity.name,
                count = 1,
                health = entity.health
            }
            entity.destroy()
            player.print({'amap.die_time'})
            return
        end
    end

    local surface = entity.surface

    -- if not (surface.index == game.surfaces[this.active_surface_index].index) then
    --     return
    -- end

    if car_name[entity.name] then
        if this.tank[index] and not this.tank[index].valid then
            this.tank[index] = nil

        end

        if not this.first_build_car[index] then
            if this.world_number ~= 8 and this.world_number ~= 7 then
                item_build_car(player)
            end
            this.first_build_car[index] = true
            if not this.qcdj[index] then
                this.qcdj[index] = 1
            end
            if not this.dist_index[index] then
                this.dist_index[index] = 1
            end
            -- 世界13：提示商店可购买关联箱和自动生产物资的箱子
            if this.world_number == 13 then
                player.print({'icw.world13_shop_tip'})
            end
        end
        if not this.have_been_put_tank[index] then
            this.have_been_put_tank[index] = true
        end
        if this.whos_tank[index] == nil then
            this.whos_tank[index] = entity.unit_number
        end
        if this.tank[index] == nil then
            this.tank[index] = entity
            if not this.silo or not this.silo.valid then
                entity.minable_flag = false
            end
            player.print({'amap.car_info'}, {
                r = 100,
                b = 200,
                g = 200
            })
            all_dist = {100, 150, 999}
            this.draw_circle[index] = (rendering.draw_circle {
                surface = entity.surface,
                target = entity,
                color = entity.color,
                filled = false,
                radius = 140,
                players = {player},
                only_in_alt_mode = true
            })
            this.car_level_text[index] = rendering.draw_text {
                surface = entity.surface,
                target = {
                entity = entity,
                offset = { 0, -1.5 },
            },
                text = 'LV' .. tostring(this.qcdj[index] or 1),
                color = entity.color,
                scale = 1.2,
                font = 'default-large-semibold',
                alignment = 'center',
                scale_with_zoom = false
            }
            if this.start_game ~= 2 then
                this.start_game = 2
            end
        end

        local unit_number = entity.unit_number
        local position = entity.position
        -- 如果放的是坦克，并且没有放过坦克
        if car_name[entity.name] then
            if entity.name == "spidertron" then
                this.had_sipder[index] = true
            end

            if entity.name ~= "car" or this.had_sipder[index] then
                local wave_defense_table = WD.get_table()
                wave_defense_table.target = get_random_car(true)
                wave_defense_table.target.destructible = true
            end
        end
        -- 如果没有放过坦克
    end
    if not this.have_been_put_tank[index] then
        if not this.silo or not this.silo.valid then
            if entity.type ~= 'entity-ghost' and entity.name ~= 'tile-ghost' then

                local health = entity.health
                local name = entity.name

                if name == "straight-rail" or name == "curved-rail" then
                    name = "rail"
                end
                player.insert {
                    name = name,
                    count = 1,
                    health = health
                }
            end
            entity.destroy()

            player.print({'amap.no_put_tank'})
            return
        end
    end
    if this.silo and this.silo.valid then
        return
    end
    -- 如果试图放蜘蛛
    if entity.name == "spidertron" and this.tank[index].name == "tank" then
        local surface = entity.surface
        local entities = surface.find_entities_filtered {
            position = player.physical_position,
            radius = 7,
            name = "tank",
            force = game.forces.player
        }
        local old_car_is_hear = false
        for i, car in ipairs(entities) do
            if car == this.tank[index] then
                old_car_is_hear = true
            end
        end
        if old_car_is_hear then
            this.player_position[index] = player.physical_position
            this.tank[index].minable_flag = true
            player.print({'amap.try_to_put_zhizhu'})
        else
            player.print({'amap.old_car_is_hear'})
        end
    end
    if entity.name == "tank" and this.tank[index].name == "car" then
        local surface = entity.surface
        --    local entities = surface.find_entities_filtered{position=player.physical_position, radius = 15 , force = game.forces.enemy}
        local entities = surface.find_entities_filtered {
            position = player.physical_position,
            radius = 7,
            name = "car",
            force = game.forces.player
        }
        local old_car_is_hear = false
        for i, car in ipairs(entities) do
            if car == this.tank[index] then
                old_car_is_hear = true
            end
        end
        if old_car_is_hear then
            this.player_position[index] = player.physical_position
            this.tank[index].minable_flag = true
            player.print({'amap.try_to_put_zhizhu'})
        else
            player.print({'amap.old_car_is_hear'})
        end
    end
    if entity.name == "spidertron" and this.tank[index].name == "car" then
        local surface = entity.surface
        local entities = surface.find_entities_filtered {
            position = player.physical_position,
            radius = 7,
            name = "car",
            force = game.forces.player
        }
        local old_car_is_hear = false
        for i, car in ipairs(entities) do
            if car == this.tank[index] then
                old_car_is_hear = true
            end
        end
        if old_car_is_hear then
            this.player_position[index] = player.physical_position
            this.tank[index].minable_flag = true
            player.print({'amap.try_to_put_zhizhu'})
        else
            player.print({'amap.old_car_is_hear'})
        end
    end

end

local function game_over()
    local this = WPT.get()
    local map = diff.get()

    local wave_defense_table = WD.get_table()
    local wave_number = WD.get('wave_number')
    local msg = {'amap.lost', wave_number}
    for _, p in pairs(game.connected_players) do
        Alert.alert_player(p, 25, msg)
    end
    Server.to_discord_embed(table.concat({'** we lost the game ! Record is ', wave_number}))

    wave_defense_table.game_lost = true
    wave_defense_table.target = nil

    local rpg_t = RPG.get('rpg_t')

    for k, player in pairs(game.connected_players) do
        local index = player.index
        this.have_been_put_tank[index] = false
    end
    if map.map_record[map.world] == nil then
        map.map_record[map.world] = 0
    end
    if wave_number > map.map_record[map.world] then
        map.map_record[map.world] = wave_number
        diff.check_all_worlds_3000()
    end
    if map.world_bonus[map.world] == nil then
        map.world_bonus[map.world]={
            unlocked=false,
            coefficient=0,
            max_wave=0
        }
    end
    if wave_number > map.world_bonus[map.world].max_wave then
        local record = map.world_bonus[map.world]
        local old_unlocked = record.unlocked
        local old_value = diff.get_world_bonus_value(map.world, record)
        record.max_wave = wave_number
        -- World 框架：世界可经 World.register 覆写解锁波数/增档间隔（如世界15=2000/100），未声明用全局默认
        local bonus_start_wave = World.get_field(map.world, 'world_bonus_start_wave') or map.world_bonus.start_wave
        local bonus_interval = World.get_field(map.world, 'world_bonus_interval') or map.world_bonus.coefficient_interval
        if wave_number >= bonus_start_wave then
            record.unlocked = true
            local extra_waves = wave_number - bonus_start_wave
            local coefficient_increase = math.floor(extra_waves / bonus_interval)
            record.coefficient = math.min(
                map.world_bonus.base_coefficient + coefficient_increase,
                map.world_bonus.max_coefficient
            )

            local new_value, bonus_type = diff.get_world_bonus_value(map.world, record)
            if not old_unlocked then
                for _, player in pairs(game.connected_players) do
                    player.print({'amap.world_bonus_unlocked', map.world}, {r = 255, g = 255, b = 0})
                end
            elseif new_value and old_value and new_value > old_value then
                -- 线性增长模式播报实际加成值（coefficient 封顶后加成仍在涨）；插值模式沿用系数播报
                local msg = (bonus_type and bonus_type.growth_value)
                    and {'amap.world_bonus_increased_value', map.world, new_value}
                    or {'amap.world_bonus_increased', map.world, record.coefficient}
                for _, player in pairs(game.connected_players) do
                    player.print(msg, {r = 0, g = 255, b = 0})
                end
            end
        end
    end

    map.sum = map.sum + 1

    -- 保存投票结果，防止Reset_map清空
    local saved_vote_map_number = this.vote_map_number

    if this.pass == true then
        map.win = map.win + 1
    else
        map.gg = map.gg + 1
    end

    if saved_vote_map_number ~= nil then
        map.world = tonumber(saved_vote_map_number)
    else
        -- 随机选择世界：从框架已注册世界中筛选（selectable ~= false 即参与，未注册的世界如 4/5 自然排除）
        local valid_worlds = {}
        for _, id in ipairs(World.get_registered_worlds()) do
            if World.get_field(id, 'selectable') ~= false then
                table.insert(valid_worlds, id)
            end
        end
        if #valid_worlds == 0 then
            valid_worlds = World.get_registered_worlds()
        end
        map.world = valid_worlds[math.random(1, #valid_worlds)]
    end
    -- map.world=math.random(1, 9)
    -- map.world=8
    map.rocket_diff = true
    
    for _, player in pairs(game.connected_players) do
        local index = player.index
        local this = WPT.get()
        if this.dungeons and this.dungeons[index] and this.dungeons[index].active then
            Dungeon.exit_dungeon(player, "manual")
        end
    end
    
    local saved_auto_cast_settings = {}
    for _, player in pairs(game.connected_players) do
        local index = player.index
        if rpg_t[index] then
            saved_auto_cast_settings[index] = {
                dropdown_select_index = rpg_t[index].dropdown_select_index,
                dropdown_select_index1 = rpg_t[index].dropdown_select_index1,
                dropdown_select_index2 = rpg_t[index].dropdown_select_index2,
                dropdown_select_index3 = rpg_t[index].dropdown_select_index3,
                
            }
        end
  
    end
    
    Reset_map()

    -- 恢复投票结果
    this.vote_map_number = saved_vote_map_number
    
    rpg_t = RPG.get('rpg_t')
    for index, settings in pairs(saved_auto_cast_settings) do
        if rpg_t[index] then
            rpg_t[index].dropdown_select_index = settings.dropdown_select_index
            rpg_t[index].dropdown_select_index1 = settings.dropdown_select_index1
            rpg_t[index].dropdown_select_index2 = settings.dropdown_select_index2
            rpg_t[index].dropdown_select_index3 = settings.dropdown_select_index3
            
        end
    end
    
    for _, player in pairs(game.connected_players) do
        player.play_sound {
            path = 'utility/game_lost',
            volume_modifier = 0.75
        }
    end
    game_info()

    for k, player in pairs(game.connected_players) do
        local index = player.index
        this.have_been_put_tank[index] = false
    end
end

local function on_player_mined_entity(event)

    local entity = event.entity

    if not entity then
        return
    end
    if not entity.valid then
        return
    end
    local this = WPT.get()
    -- if entities_that_earn_coins[entity.name] then
    --     if not this.gun_turret then
    --         this.gun_turret = {}
    --     end
    --     this.gun_turret[entity.unit_number] = nil
    -- end

    if event.player_index then
        local player = game.players[event.player_index]
        local index = player.index
        if entity.name == 'linked-chest' then
            if this.link_player[entity.unit_number].name ~= player.name then

                -- game.print(player.name..'试图抢'..this.link_player[entity.unit_number].name..'的关联箱，已被扣除1000经验')
                player.remove_item {
                    name = 'linked-chest',
                    count = 1
                }
                local rpg_t = RPG.get('rpg_t')
                -- rpg_t[player.index].xp = rpg_t[player.index].xp -1000
                this.link_player[entity.unit_number].insert {
                    name = 'linked-chest',
                    count = 1
                }

            end
        end
    end

    if entities_that_earn_coins[entity.name] then
        if this.gun_turret and this.gun_turret[entity.unit_number] then
            this.gun_turret[entity.unit_number] = nil
        end
    end



    if not car_name[entity.name] then
        return
    end

    get_car_number()

    local player = game.players[event.player_index]
    local index = player.index
    if entity == this.upgrade_car[index] then
        this.upgrade_car[index] = nil
        this.player_position[index] = nil
    end

    local index = 0
    for k, player in pairs(game.connected_players) do
        if this.whos_tank[player.index] == entity.unit_number then
            index = player.index
        end
    end
    this.upgrade_car[index] = nil
    this.player_position[index] = nil
    this.tank[index] = nil
    this.have_been_put_tank[index] = false
    this.whos_tank[index] = nil

    if this.draw_circle[index] then
        this.draw_circle[index].destroy()
        this.draw_circle[index] = nil
    end

    if this.car_level_text[index] then
        this.car_level_text[index].destroy()
        this.car_level_text[index] = nil
    end

end

local function on_entity_died(event)

    local entity = event.entity
    if not (entity and entity.valid) then
        return
    end

    local surface = entity.surface
    local this = WPT.get()

    if surface.name ~= "nauvis" then return end



    if entities_that_earn_coins[entity.name] then
        if not this.gun_turret then
            this.gun_turret = {}
        end
        this.gun_turret[entity.unit_number] = nil
    end
    if this.world_number == 8 and event.cause and event.cause.valid then
        if entity.force == game.forces.enemy then
            local distance_from_origin =(entity.position.x ^ 2 + entity.position.y ^ 2)
            if distance_from_origin >= 120 * 120 then
            if entity.type == 'unit-spawner' or entity.type == 'turret' then
                -- 计算区块ke
                
                -- 检查是否已被世界8机制保存过
                if not this.chunk_layout_data then
                    local data = {}
                    data.surface = entity.surface
                    data.position = entity.position
                    data.name = entity.name
                    if entity.type == 'turret' then
                        local wave_number = WD.get('wave_number')
                        if wave_number >= 100 then
                            data.name = 'medium-worm-turret'
                        end
                        if wave_number >= 500 then
                            data.name = 'big-worm-turret'
                        end
                        if wave_number >= 800 then
                            data.name = 'behemoth-worm-turret'
                        end
                    end

                    Task.set_timeout_in_ticks(60 * 60 * 8, new_biter, data)
                end
            end
            end
        end
    end

    if entity == this.silo then
        this.silo = nil
        for k, player in pairs(game.connected_players) do
            if this.tank[player.index] and this.tank[player.index].valid then
                this.tank[player.index].minable_flag = false
            end
        end
        game.print({'amap.rocket_silo_destroyed'}, {255, 0, 0})
        local wave_defense_table = WD.get_table()
        local car_number = get_car_number()
        if car_number ~= 0 then
            wave_defense_table.target = get_random_car(true)
            wave_defense_table.target.destructible = true
        end

        -- 检查是否需要重开
        check_silo_and_car_status()
    end

    if this.silo and this.silo.valid then
        return
    end
    if car_name[entity.name] then

        local unit_number = entity.unit_number
        local wave_defense_table = WD.get_table()
        local this = WPT.get()
        this.car_die_number = this.car_die_number + 1
        -- 如果是载具，就循环找出是谁的载具
        local index = 0
        for k, player in pairs(game.connected_players) do
            if this.whos_tank[player.index] == unit_number then
                index = player.index
            end
            if this.tank[index] and not this.tank[index].valid then
                this.tank[index] = nil
            end

        end

        if index ~= 0 then
            this.die_time[index] = game.tick

            game.players[index].print({'amap.lost_jijin'})
            if this.tank[index].name == "spidertron" then
                this.had_sipder[index] = false
            end
            this.tank[index] = nil
            this.whos_tank[index] = nil
            this.have_been_put_tank[index] = false
            
            -- 销毁渲染对象（Factorio 2.0新方式）
            if this.draw_circle[index] then
                 this.draw_circle[index].destroy()
                this.draw_circle[index] = nil
            end

            if this.car_level_text[index] then
                this.car_level_text[index].destroy()
                this.car_level_text[index] = nil
            end

            if this.time_weights[index] then
                if this.time_weights[index] >= 45 then
                    this.time_weights[index] = 0
                end
            end

            local car_number = get_car_number()
            game.print({'amap.tank_die', game.players[index].name, car_number})
        end

        local car_number = get_car_number()
        
        -- 检查是否需要重开
        check_silo_and_car_status()

        if car_number ~= 0 then
            if this.tank[index] == wave_defense_table.target then
                wave_defense_table.target = get_random_car(true)
                wave_defense_table.target.destructible = true
            end

            if not wave_defense_table.target then
                wave_defense_table.target = get_random_car(true)
                wave_defense_table.target.destructible = true
            end

            if not wave_defense_table.target.valid then
                wave_defense_table.target = get_random_car(true)
                wave_defense_table.target.destructible = true
            end
        end

    end
end
local tpshop = function()
    local this = WPT.get()
    if this.world_number == 7 and this.silo and this.silo.valid then
        game.print('一分钟后市场将转移到蜘蛛所在位置!')
        Task.set_timeout_in_ticks(60 * 60, zysc)
    end
end

local choois_target = function()
    local this = WPT.get()
    for i, v in ipairs(this.car_wudi) do
        if v and v.valid then
            v.destructible = false
            this.car_wudi[i] = nil
        else
            this.car_wudi[i] = nil
        end
    end

    if this.silo and this.silo.valid then
        local wave_defense_table = WD.get_table()
        wave_defense_table.target = this.silo
        wave_defense_table.target.destructible = true
        return
    end
    if this.start_game ~= 2 then
        return
    end
    
    -- 检查是否需要重开
    check_silo_and_car_status()

    local wave_defense_table = WD.get_table()
    wave_defense_table.target = get_random_car(true)
    wave_defense_table.target.destructible = true
end

local function on_player_joined_game(event)
    local player = game.players[event.player_index]
    local this = WPT.get()
    local index = player.index

    if this.have_been_put_tank[index] == nil then
        this.have_been_put_tank[index] = false
    end

    if this.tank[index] and this.tank[index].valid then
        this.tank[index].destructible = true
        this.tank[index].operable = true
        this.tank[index].disabled_by_script = false
        this.start_game = 2
    end

end

local function on_pre_player_left_game(event)

    local player = game.players[event.player_index]
    local this = WPT.get()
    local index = player.index
        -- 销毁渲染对象（Factorio 2.0兼容性）
    
    
    if player.online_time <= 60 * 60 * 30 then
        if not this.tank[index] then
            return
        end
        local car = this.tank[index]
        if not car.valid then
            return
        end
        car.die()
        player.insert {
            name = 'car',
            count = 1
        }
        return
    end
    if not this.tank[index] then
        return
    end
    local car = this.tank[index]
    if not car.valid then
        return
    end
    this.car_wudi[#this.car_wudi + 1] = car
    car.operable = false
    car.disabled_by_script = true

end
-- 这里可能要把无敌设置改为每35波一次
-- 上面的要检验有效性！

local function clean_invalid_car()
    get_car_number()
end

local function on_entity_damaged(event)
local entity=event.entity
    if not entity.valid then
        return
    end
    if car_name[entity.name] ~= true then
        return
    end
    local cause = event.cause
    -- if (cause and cause.force == game.forces.player ) and event.damage_type.name=='explosion' then 

    -- entity.health=event.final_damage_amount+event.final_health 
    -- game.print('[gps=' .. entity.position.x .. ',' .. entity.position.y .. ',' .. entity.surface.name .. ']'..'检测到有人在试图炸车！')
    -- return 

    -- end
    if cause then
        if cause.valid then
            if (cause and cause.force == game.forces.player) then

                if cause.name == 'character' then
                    local player = cause.player
                    local index = player.index
                    local this = WPT.get()
                    if this.tank[index] == entity then
                        return
                    end
                end
                entity.health = event.final_damage_amount + event.final_health
            end
        end
    end
end

local function car_pollute()
    local this = WPT.get()
    local wave_number = WD.get('wave_number')

    if this.world_number == 8 or this.world_number == 7 then
        if this.silo and this.silo.valid then
            local mian_surface = game.surfaces[this.active_surface_index]
            local surface = this.yiciyuan_surface
            if not surface then
                return
            end
            local pollution = surface.get_total_pollution()
            mian_surface.pollute(this.silo.position, pollution)
            surface.clear_pollution()
        end
    end

    -- 世界13：将火车内部ICW空间的污染转移到火车位置
    if this.world_number == 13 then
        if this.silo and this.silo.valid then
            local train_surface_index = ICWTable.get('train_surface')
            if train_surface_index then
                local train_surface = game.surfaces[train_surface_index]
                if train_surface and train_surface.valid then
                    local mian_surface = game.surfaces[this.active_surface_index]
                    local pollution = train_surface.get_total_pollution()
                    mian_surface.pollute(this.silo.position, pollution)
                    train_surface.clear_pollution()
                end
            end
        end
    end

    local ic = IC.get()

    for k, player in pairs(game.connected_players) do
        local index = player.index
        local unit_number = this.whos_tank[index]

        if unit_number then
            local entity = this.tank[index]
            local mian_surface = game.surfaces[this.active_surface_index]
            local car = ic.cars[unit_number]
            if car then
                local surface_index = car.surface
                local surface = game.surfaces[surface_index]
                if not surface then
                    return
                end
                local pollution = surface.get_total_pollution() * 2
                if this.world_number == 8 or this.world_number == 7 then
                    mian_surface.pollute(this.shop.position, pollution)
                    else
                        mian_surface.pollute(entity.position, pollution)
                    end
         
                surface.clear_pollution()
            end
        end

    end

    if this.silo and this.silo.valid then
        return
    end
    
    -- 检查是否需要重开
    check_silo_and_car_status()

    if this.start_game == 2 then
        if wave_number == 1 and this.frist_target == false then
            local wave_defense_table = WD.get_table()
            wave_defense_table.target = get_random_car(true)
            wave_defense_table.target.destructible = true
            this.frist_target = true
        end
    end

end

local function on_player_respawned(event)
    local player = game.get_player(event.player_index)
    local this = WPT.get()
    local index = player.index
    local player_surface = player.physical_surface
    local target_position = {x = 0, y = 0}
    local should_teleport = false

    if this.tank[index] and this.tank[index].valid then
        local tank_surface = this.tank[index].surface
        if tank_surface == player_surface then
            target_position = this.tank[player.index].position
            should_teleport = true
        end
    else
        if this.shop and this.shop.valid then
            local shop_surface = this.shop.surface
            if shop_surface == player_surface then
                target_position = this.shop.position
                should_teleport = true
            end
        else
            if player_surface.name == 'nauvis' or player_surface.name:find("yiciyuan", 1, true) then
                local spawn = game.forces.player.get_spawn_position(player_surface)
                target_position = {x = spawn.x or 0, y = spawn.y or 0}
                should_teleport = true
            end
        end
    end

    if should_teleport then
        player.teleport(player_surface.find_non_colliding_position('character', target_position, 20, 1, false) or target_position, player_surface)
    end

    -- 移除重生后装备栏中的所有物品
    if player.character and player.character.valid then
        -- 清空主背包
        
        -- 清空武器栏
        local guns_inv = player.get_inventory(defines.inventory.character_guns)
        if guns_inv then
            guns_inv.clear()
        end
        
        -- 清空弹药栏
        local ammo_inv = player.get_inventory(defines.inventory.character_ammo)
        if ammo_inv then
            ammo_inv.clear()
        end
    end

    -- player.character.destructible=false
    -- Task.set_timeout_in_ticks(60*6, no_wudi, player)
end

local function on_marked_for_deconstruction(event)
    local entity = event.entity
    if not entity.valid then
        return
    end
    if entity.name == 'linked-chest' then
        entity.cancel_deconstruction(game.players[event.player_index].force.name)
    end
end

local function daojishi()
    local this = WPT.get()
    local map = diff.get()
    
    if this.world_number == 7 and this.silo and this.silo.valid then
        local goal = {'turret', 'unit-spawner'}

        local count = this.silo.surface.count_entities_filtered {
            position = this.silo.position,
            type = goal,
            radius = 20,
            force = "enemy"
        }
        if count > 0 then
            this.silo.teleport({
                x = this.silo.position.x,
                y = this.silo.position.y + 10
            }, this.silo.surface)
            local player = this.silo.get_driver()
            local passenger = this.silo.get_passenger()
            if player and player.player then
                player.player.print('蜘蛛正处于危险位置', {255, 0, 0})
            end
            if passenger and passenger.player then
                passenger.player.print('蜘蛛正处于危险位置', {255, 0, 0})
            end
        end

        local now_Pos = Collapse.get_position()
        if this.silo.position.y > now_Pos.y - 20 then
            this.silo.teleport({
                x = this.silo.position.x,
                y = now_Pos.y - 20
            }, this.silo.surface)
        end

    end

    if this.start_game ~= 3 then
        return
    end

    -- 如果火箭发射井存在，则不执行重开
    if this.silo and this.silo.valid then
        this.start_game = 2
        this.reset_time = 0
        return
    end

    -- 创建控制投票地图窗口
    if this.reset_time <= 0 then
        game_over()
    end
    if this.reset_time % 600 == 0 then
        -- 判断是否是第一次游戏
        if map.sum == 0 then
            game.print({'amap.reset_time_first', this.reset_time / 60})
        else
            game.print({'amap.reset_time', this.reset_time / 60})
        end
    end
    this.reset_time = this.reset_time - 60
end



-- 定期检查火箭发射井和车子状态
local function check_reset_conditions()
    local this = WPT.get()
    
    -- 只有在游戏进行中才检查
    if this.start_game ~= 2 then
        return
    end
    
    -- 检查是否需要重开
    check_silo_and_car_status()
end

------------------------------------------------------------
-- 世界13：玩家打开关联箱时弹出连接选择 GUI
------------------------------------------------------------
------------------------------------------------------------
-- 世界14：禁止在太空平台建造石墙
------------------------------------------------------------
local function on_space_platform_built_entity(event)
    local this = WPT.get()
    if this.world_number ~= 14 then
        return
    end

    local entity = event.entity
    if not entity or not entity.valid then
        return
    end

    if entity.name == 'stone-wall' then
        entity.destroy()
    end
end

local function on_gui_opened(event)
    local this = WPT.get()
    if this.world_number ~= 13 then
        return
    end

    local entity = event.entity
    if not entity or not entity.valid then
        return
    end

    if entity.name ~= 'linked-chest' then
        return
    end

    -- 只在主世界表面触发
    if entity.surface.name ~= ICWTable.get('allowed_surface') then
        return
    end

    local player = game.get_player(event.player_index)
    if not player or not player.valid then
        return
    end

    -- 弹出连接选择 GUI
    ICWLinkChestGui.show_link_chest_gui(player, entity)
end

Event.on_nth_tick(60 * 60 * 5, tpshop)
Event.on_nth_tick(72000, choois_target)
Event.on_nth_tick(900, clean_invalid_car)
Event.on_nth_tick(900, car_pollute)
Event.on_nth_tick(60, daojishi)
Event.on_nth_tick(300, check_reset_conditions) -- 每5秒检查一次重开条件
Event.on_nth_tick(60 * 60, function() 
    local wave_number = WD.get('wave_number') or 0
    local this = WPT.get()
    local start_number =1200
    if this.world_number == 1 then
        start_number=2100
    end
    -- 如果波数小于等于10，则不执行伤害削弱
    if wave_number <= start_number then
        return
    end
    
    
    reduce_player_damage_over_time()
end) -- 每分钟检查一次，如果波数大于10则削弱玩家阵营5%伤害
-- Event.add(defines.events.on_equipment_inserted, on_equipment_inserted)
Event.add(defines.events.on_player_respawned, on_player_respawned)
--Event.add(defines.events.on_entity_damaged, on_entity_damaged)
Event.add(defines.events.on_player_mined_entity, on_player_mined_entity,{
    {filter = "type", type = 'simple-entity'},
    {filter = "type", type = 'linked-chest'},
    {filter = "type", type = 'container'},
    {filter = "type", type = 'car'},
    
    {filter = "type", type = 'artillery-wagon'},
    {filter = "type", type = 'artillery-turret'},
    {filter = "type", type = 'land-mine'},
    {filter = "type", type = 'spider-vehicle'},
    {filter = "type", type = 'ammo-turret'},
    {filter = "type", type = 'electric-turret'},
    {filter = "type", type = 'fluid-turret'},
	{filter = "type", type = 'tree'}
})
Event.add(defines.events.on_robot_mined_entity, on_player_mined_entity,{
    {filter = "type", type = 'simple-entity'},
    {filter = "type", type = 'linked-chest'},
    {filter = "type", type = 'container'},
    {filter = "type", type = 'car'},
    
    {filter = "type", type = 'artillery-wagon'},
    {filter = "type", type = 'artillery-turret'},
    {filter = "type", type = 'land-mine'},
    {filter = "type", type = 'spider-vehicle'},
    {filter = "type", type = 'ammo-turret'},
    {filter = "type", type = 'electric-turret'},
    {filter = "type", type = 'fluid-turret'},
	{filter = "type", type = 'tree'}
})
Event.add(defines.events.on_entity_died, on_entity_died)
Event.add(defines.events.on_built_entity, on_player_build_entity)
Event.add(defines.events.on_pre_player_left_game, on_pre_player_left_game)
Event.add(defines.events.on_player_joined_game, on_player_joined_game)
Event.add(defines.events.on_marked_for_deconstruction, on_marked_for_deconstruction)
Event.add(defines.events.on_space_platform_built_entity, on_space_platform_built_entity)
Event.add(defines.events.on_gui_opened, on_gui_opened)


