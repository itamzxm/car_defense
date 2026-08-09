local Public = {}

local Event = require 'utils.event'
local WPT = require 'maps.amap.table'
local Rand = require 'maps.amap.random'
local WD = require 'modules.wave_defense.table'
local RPG = require 'modules.rpg.table'
local Alert = require 'utils.alert'

local car_weiht = {
    ["car"] = 10,
    ["tank"] = 60,
    ["spidertron"] = 300
}


local starting_items = {
    ['submachine-gun'] = 1,
    ['firearm-magazine'] = 30,
    ['wood'] = 16,
    ['car'] = 1
}


local steal_oil = {'assembling-machine-1', 'assembling-machine-2', 'assembling-machine-3', 'oil-refinery',
                   'chemical-plant', 'pipe', 'pipe-to-ground', 'pump', 'storage-tank', 'flamethrower-turret'}

function Public.get_player_data(player, remove_user_data)
    local players = WPT.get('players')
    if remove_user_data then
        if players[player.index] then
            players[player.index] = nil
        end
    end
    if not players[player.index] then
        players[player.index] = {}
    end
    return players[player.index]
end

local get_player_data = Public.get_player_data

local function get_car_number()
    local this = WPT.get()
    local car_number = 0
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


local function get_car_index()
    local all_cars = {}
    local spider_cars = {}
    local rpg_t = RPG.get('rpg_t')
    local this = WPT.get()
    local active_surface_index = this.active_surface_index
    
    for k, player in pairs(game.connected_players) do

        if this.tank[player.index] and this.tank[player.index].valid then
            if this.tank[player.index].surface.index ~= game.surfaces[active_surface_index].index then
                goto continue
            end

            local car = this.tank[player.index]
            local base_weight = car_weiht[car.name]
            if this.had_sipder[player.index] == true then
                base_weight = 360
            end
            --   game.print("基础权重为: " .. base_weight .. '')
            if this.car_pos[player.index] and car then
                local x = this.car_pos[player.index].x - car.position.x
                local y = this.car_pos[player.index].y - car.position.y
                local dist = x * x + y * y

                if dist > 3025 then
                    this.car_pos[player.index] = car.position
                    this.time_weights[player.index] = 0
                end
            end

            local time_weight = 0
            if this.time_weights[player.index] then
                time_weight = this.time_weights[player.index]
            end

            if this.had_sipder[player.index] then
                time_weight = 150
            end

            if not this.nest_wegiht[player.index] then
                this.nest_wegiht[player.index] = 0
            end

            local rpg_weight = rpg_t[player.index].level * 2
            local nest_wegiht = this.nest_wegiht[player.index] * 2
            local all_weight = base_weight + time_weight + rpg_weight + nest_wegiht
            --   game.print("总权重为: " .. all_weight .. '')

            local id = #all_cars + 1
            all_cars[id] = {}
            all_cars[id].index = player.index
            all_cars[id].weight = all_weight
            local sipder_id = #spider_cars + 1
            if this.had_sipder[player.index] then
                spider_cars[sipder_id] = {}
                spider_cars[sipder_id].index = player.index
                spider_cars[sipder_id].weight = all_weight
            end
        end
        
        ::continue::
    end

    if #spider_cars ~= 0 then
        local k_rand
        k_rand = math.random(1, 3)
        if k_rand == 1 then
            all_cars = spider_cars
        end

    end

    local choices = {
        indexs = {},
        weights = {}
    }
    for _, car in pairs(all_cars) do
        table.insert(choices.indexs, car.index)
        table.insert(choices.weights, car.weight)
    end
    --  game.print("总随机成员 " .. #all_cars .. '')
    return Rand.raffle(choices.indexs, choices.weights)
end

function Public.get_random_car(print)

    local this = WPT.get()
    if this.silo and this.silo.valid then
        return this.silo
    end
    local index = get_car_index()
    --   game.print("随机结果为:" .. index .. '')
    if print then
        local name = game.players[index].name
        game.print(({'amap.car_will_attack', name}), {
            r = 255,
            b = 100,
            g = 100
        })
        this.car_index = index
        this.diff_change = 0
        this.diff_roll = 0
        if this.last_sipder then
            if this.tank[this.last_sipder] then
                if this.tank[this.last_sipder].name == "spidertron" then
                    this.tank[this.last_sipder].grid.inhibit_movement_bonus = false
                else
                    this.last_sipder = nil
                end
            end
        else
            this.last_sipder = nil
        end
        if this.tank[index].name == "spidertron" and get_car_number() <= 4 then

            this.tank[index].grid.inhibit_movement_bonus = true
            this.last_sipder = index
            game.players[index].print(({'amap.reduce_sipder_speed'}), {
                r = 0,
                b = 255,
                g = 255
            })
        end
    end

    if this.world_number == 7 or this.world_number == 8 then
        this.silo = this.tank[index]
        --禁止挖掘
        this.tank[index].minable_flag = false
        this.tank[index].destructible=true
    end
    return this.tank[index]
end




function Public.on_player_joined_game(event)
    local active_surface_index = WPT.get('active_surface_index')
    local player = game.players[event.player_index]
    if not active_surface_index or not game.surfaces[active_surface_index] then return end
    local surface = game.surfaces[active_surface_index]
    local player_data = get_player_data(player)
    if not player_data.first_join then

        for item, amount in pairs(starting_items) do
            player.insert({
                name = item,
                count = amount
            })
        end
        local rpg_t = RPG.get('rpg_t')
        local wave_number = WD.get('wave_number')
        local this = WPT.get()
        -- 限制循环次数，避免500波后this.science过大导致的性能问题
        local max_science_loops = 1000
        local loop_count = math.min(this.science, max_science_loops)
        
        for i = 1, loop_count do
            local point = math.random(1, 5)
            local coin = math.random(1, 100)

            rpg_t[player.index].points_left = rpg_t[player.index].points_left + point
            player.insert {
                name = 'coin',
                count = coin
            }
        end
        -- 如果有剩余的科学点数，一次性添加
        if this.science > max_science_loops then
            local remaining = this.science - max_science_loops
            -- 平均每次循环获得3点，所以剩余的点数乘以3
            rpg_t[player.index].points_left = rpg_t[player.index].points_left + remaining * 3
            -- 平均每次循环获得50金币，所以剩余的金币乘以50
            player.insert {
                name = 'coin',
                count = remaining * 50
            }
        end
        this.nest_wegiht[player.index] = 0
        rpg_t[player.index].xp = rpg_t[player.index].xp + wave_number * 20
        player_data.first_join = true
        
        local main_table = WPT.get()
        main_table.tianfu_enabled[player.index] = {}
        
        local guns = player.get_inventory(defines.inventory.character_guns)

          if guns[2] and guns[2].valid and guns[2].name then
    guns[1].set_stack(guns[2])
    guns[2].clear()
end
           
     
        
    end

    local this = WPT.get()
    local index = player.index
    local main_surface = player.physical_surface

    -- if player.physical_surface.index ~= active_surface_index then
    --     if this.shop and this.shop.valid then
    --         player.teleport(
    --             main_surface.find_non_colliding_position('character', this.shop.position, 20, 1, false) or {
    --                 x = 0,
    --                 y = 0
    --             }, main_surface)
    --     else
    --         if this.tank[index] and this.tank[index].valid then
    --             player.teleport(main_surface.find_non_colliding_position('character', this.tank[index].position,
    --                 20, 1, false) or {
    --                 x = 0,
    --                 y = 0
    --             }, main_surface)
    --         else
    --             player.teleport(surface.find_non_colliding_position('character',
    --                 game.forces.player.get_spawn_position(surface), 20, 1, false) or {
    --                 x = 0,
    --                 y = 0
    --             }, surface)
    --         end
    --     end
    -- end

    local get_tile = main_surface.get_tile(player.physical_position)
    if get_tile.valid and get_tile.name == 'out-of-map' then
        player.teleport(main_surface.find_non_colliding_position('character', this.silo.position, 20, 1, false) or {
            x = 0,
            y = 0
        }, main_surface)
    end

    -- 世界13：离线超过5分钟且与火车同图层的玩家，传送到出生点（火车系统会自动将出生点设在火车旁）
    if this.world_number == 13 then
        local last_leave = player_data.last_leave_tick or 0
        local ticks_offline = game.tick - last_leave
        if player.physical_surface.index == active_surface_index and ticks_offline > 60 * 60 * 5 and last_leave > 0 then
            local spawn_pos = player.force.get_spawn_position(main_surface)
            local teleport_pos = main_surface.find_non_colliding_position('character', spawn_pos, 20, 1, false) or spawn_pos
            player.teleport(teleport_pos, main_surface)
        end
    end
end

function Public.on_pre_player_left_game(event)
    local player_data = get_player_data(game.players[event.player_index])
    player_data.last_leave_tick = game.tick
end

local function on_player_mined_entity(event)
    if not event.entity then
        return
    end
    if not event.entity.valid then
        return
    end
    local this = WPT.get()
    if not this.active_surface_index or not game.surfaces[this.active_surface_index] or not event.entity.surface then return end
    if not (event.entity.surface.index == game.surfaces[this.active_surface_index].index) then
        return
    end
    local name = event.entity.name
    local force = event.entity.force

    if force.index == game.forces.player.index then

        if name == "artillery-wagon" or name == "artillery-turret" then
            local unit_number = event.entity.unit_number
            if not this.water_arty then
                this.water_arty = {}
            else
                if this.water_arty[unit_number] then
                    this.water_arty[unit_number] = nil
                end
            end
            return
        end

        if name == 'flamethrower-turret' then
            this.flame = this.flame - 1
            if this.flame <= 0 then
                this.flame = 0
            end
            return
        end

        if name == 'land-mine' then
            this.now_mine = this.now_mine - 1
            if this.now_mine <= 0 then
                this.now_mine = 0
            end
            return
        end
        
        -- 世界7和8的激光塔摧毁处理
        if name == 'laser-turret' and (this.world_number == 7 or this.world_number == 8) then
            this.laser = this.laser - 1
            if this.laser <= 0 then
                this.laser = 0
            end
            return
        end
        
        -- 世界7和8的特斯拉电塔摧毁处理
        if name == 'tesla-turret' and (this.world_number == 7 or this.world_number == 8) then
            this.tesla = this.tesla - 1
            if this.tesla <= 0 then
                this.tesla = 0
            end
            return
        end
        
        -- 世界7和8的轨道炮塔摧毁处理
        if name == 'railgun-turret' and (this.world_number == 7 or this.world_number == 8) then
            this.railgun = this.railgun - 1
            if this.railgun <= 0 then
                this.railgun = 0
            end
            return
        end
    end

end

local function clean_flame_table()
    local this = WPT.get()
    for k, v in pairs(this.player_flame) do
        for index, turret in pairs(v.turret) do
            if not turret.valid then
                this.player_flame[k].turret[index] = nil
                this.player_flame[k].number = this.player_flame[k].number - 1
                if this.player_flame[k].number == 0 then
                    this.player_flame[k] = nil
                end
            end
        end
    end 
end

local function clean_laser_table()
    local this = WPT.get()
    for k, v in pairs(this.player_laser) do
        for index, turret in pairs(v.turret) do
            if not turret.valid then
                this.player_laser[k].turret[index] = nil
                this.player_laser[k].number = this.player_laser[k].number - 1
                if this.player_laser[k].number == 0 then
                    this.player_laser[k] = nil
                end
            end
        end
    end
end

local function kill_turret(index, player)
    local this = WPT.get()
    local number_player = 0

    local max_number = 0
    for k, v in pairs(this.player_flame) do
        if v then
            if v.number > 0 then
                number_player = number_player + 1
                if v.number > max_number then
                    max_number = v.number
                end
            end
        end
    end

    local average = this.max_flame / number_player
    if this.player_flame[index] then
        if average <= this.player_flame[index].number and this.player_flame[index].number >= max_number then
            player.print({'amap.limit_flame'})
            return false
        end
    end

    if max_number > average then
        average = max_number - 1
    end

    if average <= 1 then
        player.print({'amap.limit_flame'})
        return false
    end

    local above_average = {}
    for k, v in pairs(this.player_flame) do
        if v.number > average then
            above_average[#above_average + 1] = v
        end
    end

    if #above_average == 0 then
        average = average - 1
        for k, v in pairs(this.player_flame) do
            if v.number > average then
                above_average[#above_average + 1] = v
            end
        end
    end

    if #above_average ~= 0 then

        local k = math.random(#above_average)
        local all_turret = above_average[k].turret

        for k, v in pairs(all_turret) do
            if v then
                game.print({'amap.kill_flame', v.position.x, v.position.y, v.surface.name})
                v.destroy()
                clean_flame_table()
                this.flame = this.flame - 1
                return true
            end
        end
    end

    if #above_average == 0 then
        local sum = 0
        for k, v in pairs(this.player_flame) do
            sum = sum + v.number
        end
        this.flame = sum
    end
    return false
end

local function kill_laser_turret(index, player)
    local this = WPT.get()
    local number_player = 0

    local max_number = 0
    for k, v in pairs(this.player_laser) do
        if v then
            if v.number > 0 then
                number_player = number_player + 1
                if v.number > max_number then
                    max_number = v.number
                end
            end
        end
    end

    local average = this.max_laser / number_player
    if this.player_laser[index] then
        if average <= this.player_laser[index].number and this.player_laser[index].number >= max_number then
            player.print({'amap.limit_laser'})
            return false
        end
    end

    if max_number > average then
        average = max_number - 1
    end

    if average <= 1 then
        player.print({'amap.limit_laser'})
        return false
    end

    local above_average = {}
    for k, v in pairs(this.player_laser) do
        if v.number > average then
            above_average[#above_average + 1] = v
        end
    end

    if #above_average == 0 then
        average = average - 1
        for k, v in pairs(this.player_laser) do
            if v.number > average then
                above_average[#above_average + 1] = v
            end
        end
    end

    if #above_average ~= 0 then

        local k = math.random(#above_average)
        local all_turret = above_average[k].turret

        for k, v in pairs(all_turret) do
            if v then
                v.destroy()
                clean_laser_table()
                this.laser = this.laser - 1
                return true
            end
        end
    end

    if #above_average == 0 then
        local sum = 0
        for k, v in pairs(this.player_laser) do
            sum = sum + v.number
        end
        this.laser = sum
    end
    return false
end

local function register_flame(index, turret)
    local this = WPT.get()
    if not this.player_flame[index] then
        this.player_flame[index] = {}
        this.player_flame[index].number = 0
        this.player_flame[index].turret = {}
    end

    this.player_flame[index].number = this.player_flame[index].number + 1

    local a = 0
    for k, v in pairs(this.player_flame[index].turret) do
        a = k
    end
    this.player_flame[index].turret[a + 1] = turret
    this.flame = this.flame + 1
    game.print({'amap.ok_many', this.flame, this.max_flame})
end

local function register_laser(index, turret)
    local this = WPT.get()
    if not this.player_laser[index] then
        this.player_laser[index] = {}
        this.player_laser[index].number = 0
        this.player_laser[index].turret = {}
    end

    this.player_laser[index].number = this.player_laser[index].number + 1

    local a = 0
    for k, v in pairs(this.player_laser[index].turret) do
        a = k
    end
    this.player_laser[index].turret[a + 1] = turret
    this.laser = this.laser + 1
    --当激光塔和最大激光塔的数量差距小于50时才提示
 
end

local function build_flame(player, turret)
    local this = WPT.get()
    local index = player.index
    clean_flame_table()
    if this.flame < this.max_flame then
        register_flame(index, turret)

    else
        if kill_turret(index, player) then
            register_flame(index, turret)
        else
            turret.destroy()
        end
    end
end

local function build_laser(player, turret)
    local this = WPT.get()
    local index = player.index
    clean_laser_table()
    if this.laser < this.max_laser then
        register_laser(index, turret)
    else
        if kill_laser_turret(index, player) then
            register_laser(index, turret)
        else
            turret.destroy()
        end
    end
end

local on_player_or_robot_built_entity = function(event)

    local entity = event.entity
    local this = WPT.get()

    if not this.active_surface_index or not game.surfaces[this.active_surface_index] or not entity.surface then return end
    if not (entity.surface.index == game.surfaces[this.active_surface_index].index) then
        return
    end
    local name = event.entity.name
    local force = event.entity.force
    if force.index ~= game.forces.player.index then
        return
    end

    local player = event.entity.last_user
    if not player then
        return
    end
    local index = player.index

    if name == 'flamethrower-turret' then
        if this.have_been_put_tank[index] or this.silo then
            build_flame(player, event.entity)
        else
            entity.destroy()
            player.print({'amap.no_car'})
        end
    end
    if name == 'land-mine' then
        if this.have_been_put_tank[index] or this.silo then
            if this.now_mine >= this.max_mine then
                game.print({'amap.too_many_mine'})
                entity.destroy()
            else
                this.now_mine = this.now_mine + 1
            end
        else
            entity.destroy()
        end
    end
    
    -- 世界7和8的激光塔限制
    if name == 'laser-turret' and (this.world_number == 7 or this.world_number == 8) then
        if this.have_been_put_tank[index] or this.silo then
            build_laser(player, event.entity)
        else
            entity.destroy()
            player.print({'amap.no_car'})
        end
    end
    
    -- 世界7和8的特斯拉电塔限制
    if name == 'tesla-turret' and (this.world_number == 7 or this.world_number == 8) then
        if this.have_been_put_tank[index] or this.silo then
            if this.tesla >= this.max_tesla then
                game.print({'amap.too_many_tesla', this.tesla, this.max_tesla})
                entity.destroy()
            else
                this.tesla = this.tesla + 1
            end
        else
            entity.destroy()
            player.print({'amap.no_car'})
        end
    end
    
    -- 世界7和8的轨道炮塔限制
    if name == 'railgun-turret' and (this.world_number == 7 or this.world_number == 8) then
        if this.have_been_put_tank[index] or this.silo then
            if this.railgun >= this.max_railgun then
                game.print({'amap.too_many_railgun', this.railgun, this.max_railgun})
                entity.destroy()
            else
                this.railgun = this.railgun + 1
            end
        else
            entity.destroy()
            player.print({'amap.no_car'})
        end
    end
end

local function count_down()
    local this = WPT.get()
    if this.stop_time == 0 then
        return
    end
    if this.stop_time % 36000 == 0 then
        game.print({'amap.wave_time' .. (this.world_number == 10 and '_world10' or ''), this.stop_time / 3600})
    end

    this.stop_time = this.stop_time - 60
    if this.stop_time == 0 then
        game.print({'amap.over_stop' .. (this.world_number == 10 and '_world10' or '')})
        local wave_defense_table = WD.get_table()
        wave_defense_table.game_lost = false
        if this.world_number == 7 and this.number >= 100 then
            Collapse.start_now(true)
            game.print('塌陷已开始！！！')
        end
        if get_car_number() ~= 0 then
            wave_defense_table.target = Public.get_random_car(true)
        end
    end
end

local disable_recipes = function()
    local force = game.forces.player
    force.recipes['car'].enabled = false
    force.recipes['tank'].enabled = false
    force.recipes['pistol'].enabled = false
  --  force.recipes['spidertron-remote'].enabled = false
    local this = WPT.get()
    if this.world_number == 13 then
        force.recipes['locomotive'].enabled = false
        force.recipes['cargo-wagon'].enabled = false
        force.recipes['fluid-wagon'].enabled = false
    end
end

function Public.disable_tech()
    local this = WPT.get()
    local world_number = this.world_number
    local landfill_worlds = {3, 7, 8, 9, 13, 14}
    local should_disable_landfill = true
    for _, world in ipairs(landfill_worlds) do
        if world_number == world then
            should_disable_landfill = false
            break
        end
    end
    if should_disable_landfill then
        game.forces.player.technologies['landfill'].enabled = false
    end
    game.forces.player.technologies['spidertron'].enabled = false
    game.forces.player.technologies['spidertron'].researched = false

    disable_recipes()
end

function Public.on_research_finished(event)
    if event.research.force.index ~= game.forces.player.index then
        return
    end
    local this = WPT.get()
    local research = event.research
    -- game.print(research.name)
    this.science = this.science + 1
    local rpg_t = RPG.get('rpg_t')

    local pay_player = {}
    local gain_player = {}
    local should_reward = {}
    local all_reward = {}
    all_reward.point = 0
    all_reward.coin = 0
    for k, player in pairs(game.connected_players) do
        local point = math.random(1, 3)
        local coin = math.random(1, 100)
        local index = player.index
        if this.tank[index] or this.silo then
            gain_player[#gain_player + 1] = player
            should_reward[index] = {}
            should_reward[index].point = point
            should_reward[index].coin = coin
        else
            all_reward.point = all_reward.point + point
            all_reward.coin = all_reward.coin + coin
            pay_player[#pay_player + 1] = player
        end
    end
    if all_reward.point <= 5 then
        all_reward.point = 5
    end

    local average_point = math.floor(all_reward.point / #gain_player)
    local average_coin = math.floor(all_reward.coin / #gain_player)

    if average_point < 2 then
        average_point = 1
    end
    if average_coin < 2 then
        average_coin = 1
    end

    for k, player in pairs(gain_player) do
        local index = player.index
        if should_reward[index] then
            local get_coin = should_reward[index].coin + average_coin
            local get_point = should_reward[index].point + average_point
            rpg_t[player.index].points_left = rpg_t[player.index].points_left + get_point
            player.insert {
                name = 'coin',
                count = get_coin
            }
            Alert.alert_player(player, 5, {'amap.science' .. (this.world_number == 10 and '_shiqi' or ''), get_point, get_coin})
        end
    end

    for k, player in pairs(pay_player) do
        Alert.alert_player(player, 5, {'amap.no_car_science'})
    end
    disable_recipes()
    Public.reapply_damage_multiplier()
   
    if "utility-science-pack" == research.name  then
        game.forces.player.technologies['landfill'].enabled = true
    
        if this.yiciyuan_surface and this.yiciyuan_surface.valid then
            this.yiciyuan_surface.ignore_surface_conditions = true
        end
        -- 设置标志，表示气候条件限制已被取消
        game.surfaces["nauvis"].ignore_surface_conditions = true
        this.climate_disabled = true
        game.print({'amap.already_unlock_by_research'})
    end

if research.name == "planet-discovery-vulcanus" then
    local planet = game.planets["vulcanus"]
    if planet and not planet.surface then
        -- 这种方式会自动关联行星的所有属性（重力、大气、预设等）
        planet.create_surface()
        -- 设置随机种子
        local settings = planet.surface.map_gen_settings
        settings.seed = math.random(1, 4294967295)
        planet.surface.map_gen_settings = settings
    end
end
if research.name == "planet-discovery-fulgora" then
    local planet = game.planets["fulgora"]
    if planet and not planet.surface then
        planet.create_surface()
        local settings = planet.surface.map_gen_settings
        settings.seed = math.random(1, 4294967295)
        planet.surface.map_gen_settings = settings
    end
end     
if research.name == "planet-discovery-gleba" then
    local planet = game.planets["gleba"]
    if planet and not planet.surface then
        planet.create_surface()
        local settings = planet.surface.map_gen_settings
        settings.seed = math.random(1, 4294967295)
        planet.surface.map_gen_settings = settings
    end
end
if research.name == "planet-discovery-aquilo" then
    local planet = game.planets["aquilo"]
    if planet and not planet.surface then
        planet.create_surface()
        local settings = planet.surface.map_gen_settings
        settings.seed = math.random(1, 4294967295)
        planet.surface.map_gen_settings = settings
    end
end

    -- 同步科技给qiche阵营
    local qiche = game.forces.qiche
    if qiche then
        local qiche_tech = qiche.technologies[research.name]
        if qiche_tech and not qiche_tech.researched then
            qiche_tech.researched = true
        end
    end

end


local function on_console_command(event)
    local cmd = event.command
    if not event.player_index then
        return
    end
    local this = WPT.get()
    if cmd ~= "debug" and cmd ~= "itam" and cmd ~= "tk" and cmd ~= "rpg" and cmd ~= "time" and cmd ~= "help" then
        this.editor = true
        local player = game.players[event.player_index]
        player.print('你已作弊，如果是挑战单通，则该存档已经作废！')
        player.print('你已作弊，如果是挑战单通，则该存档已经作废！！')
        player.print('你已作弊，如果是挑战单通，则该存档已经作废！！！')
        player.print('你已作弊，如果是挑战单通，则该存档已经作废！！！!')
        player.print('你已作弊，如果是挑战单通，则该存档已经作废！！！! !')
    end

end
 
local disable_tech = Public.disable_tech
local on_research_finished = Public.on_research_finished
local on_pre_player_left_game = Public.on_pre_player_left_game
local on_player_joined_game = Public.on_player_joined_game

Event.on_nth_tick(60, count_down)
Event.add(defines.events.on_console_command, on_console_command)
Event.add(defines.events.on_built_entity, on_player_or_robot_built_entity)
Event.add(defines.events.on_robot_built_entity, on_player_or_robot_built_entity)
Event.add(defines.events.on_research_finished, on_research_finished)
Event.add(defines.events.on_pre_player_left_game, on_pre_player_left_game)
Event.add(defines.events.on_player_joined_game, on_player_joined_game)
Event.add(defines.events.on_player_mined_entity, on_player_mined_entity,{
    {filter = "type", type = 'simple-entity'},
    {filter = "type", type = 'linked-chest'},
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

-- 设置阵营伤害加成的公共函数
function Public.set_force_damage_modifier(force, value,multiplier)
    
    local this = WPT.get()
       local data = {
       ['artillery-shell'] = 0.4,
       ['biological'] = 0.08,
        ['bullet'] = 0.4,
        ['electric'] = 0.16,
        ['flamethrower'] = 0.6,
        ['grenade'] = 0.5,
        ['landmine'] = 0.12,
        ['beam'] = 0.24,
        ['laser'] = 0.5,
        ['shotgun-shell'] = 0.08,
        ['cannon-shell'] = 0.6,
        ['melee'] = 0.14,
        ['rocket'] = 0.7,
        ['tesla'] = 0.4,      -- 特斯拉电塔、特斯拉枪、特斯拉弹药
        ['railgun'] = 0.5,    -- 电磁炮加成
    }
     if not multiplier then
        -- 敌人阵营保底机制：购买 health_wall 后检查所有伤害，
        -- 伤害乘数下限 = (1 + wave_number/1000) * 0.8，低于则重置到下限
        local is_enemy = (force == game.forces.enemy)
        local floor_modifier = nil
        if is_enemy then
            local wave_number = WD.get('wave_number') or 0
            local floor_multiplier = (1 + wave_number / 1000) * 0.8
            floor_modifier = floor_multiplier - 1
        end
        for k, v in pairs(data) do
             local e_old = force.get_ammo_damage_modifier(k)
             local new_modifier = value + e_old
             if is_enemy then
                 -- 敌人阵营：伤害低于保底下限则重置到下限
                 if new_modifier < floor_modifier then
                     force.set_ammo_damage_modifier(k, floor_modifier)
                 else
                     force.set_ammo_damage_modifier(k, new_modifier)
                 end
             elseif new_modifier >= -0.95 then
                 force.set_ammo_damage_modifier(k, new_modifier)
             end
        end
    end
    
    if  multiplier then
         local old_multiplier =this.damage_multiplier or 1
         local new_multiplier = old_multiplier * (1 + value)
         new_multiplier = math.floor(math.max(0.1, new_multiplier) * 1000) / 1000
            for k, v in pairs(data) do
              local e_old = (force.get_ammo_damage_modifier(k)+1)/old_multiplier
              force.set_ammo_damage_modifier(k, e_old*new_multiplier-1)
            end
            this.damage_multiplier = new_multiplier
            this.player_damage_modifiers = {}
            for k, v in pairs(data) do
                this.player_damage_modifiers[k] = force.get_ammo_damage_modifier(k)
            end
    end

    if force == game.forces.enemy then
       this.enemy_damage_modifier = this.enemy_damage_modifier+value
    end
    return true
end

function Public.reapply_damage_multiplier()
    local this = WPT.get()
    local multiplier = this.damage_multiplier
    
    if not multiplier or multiplier == 1 then
        return
    end
    
    local data = {
       ['artillery-shell'] = 0.4,
       ['biological'] = 0.08,
        ['bullet'] = 0.4,
        ['electric'] = 0.16,
        ['flamethrower'] = 0.6,
        ['grenade'] = 0.5,
        ['landmine'] = 0.12,
        ['beam'] = 0.24,
        ['laser'] = 0.5,
        ['shotgun-shell'] = 0.08,
        ['cannon-shell'] = 0.6,
        ['melee'] = 0.14,
        ['rocket'] = 0.7,
        ['tesla'] = 0.4,
        ['railgun'] = 0.5,
    }
    
    local force = game.forces.player
    for k, v in pairs(data) do
        local current_damage = force.get_ammo_damage_modifier(k)
        local stored_damage = this.player_damage_modifiers[k] or 0
        local damage_increase = current_damage - stored_damage
        
        if damage_increase > 0 then
            local adjusted_increase = damage_increase * multiplier
            force.set_ammo_damage_modifier(k, stored_damage + adjusted_increase)
            this.player_damage_modifiers[k] = stored_damage + adjusted_increase
        end
    end
end

local function calc_players()
  local players = game.connected_players
  local total = 0
  for i = 1, #players do
    local player = players[i]
    if player.afk_time < 36000 then
      total = total + 1
    end
  end
  if total <= 0 then
    total = 1
  end
  return total
end

-- 每20分钟削弱玩家阵营伤害的函数（根据玩家数量动态调整）
function Public.reduce_player_damage_over_time()
    local this = WPT.get()

    -- 增加削弱计数
    this.player_damage_reduction_count = this.player_damage_reduction_count + 1
    if  this.player_damage_reduction_count>=20 then 
        local wave_number = WD.get('wave_number')
        local player_count = calc_players()
        local wave_multiplier = 0.7 + math.floor(wave_number / 500) * 0.4
        local reduction_percent = (1 + math.floor((player_count - 1) / 2)) * wave_multiplier
        Public.set_force_damage_modifier(game.forces.player, -reduction_percent / 100,true)
        this.player_damage_reduction_count=0
    end

    return true
end



return Public
