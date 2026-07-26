local Event = require 'utils.event'
local BiterHealthBooster = require 'maps.amap.biter_class'
local enemy_arty = require 'maps.amap.enemy_arty'
local BiterRolls = require 'modules.wave_defense.biter_rolls'
local ThreatEvent = require 'modules.wave_defense.threat_events'
local update_gui = require 'modules.wave_defense.gui'
local threat_values = require 'modules.wave_defense.threat_values'
local WD = require 'modules.wave_defense.table'
local Alert = require 'utils.alert'
local diff = require 'maps.amap.diff'
local WPT = require 'maps.amap.table'
local get_random_car = require"maps.amap.functions".get_random_car
local Public = {}
local math_random = math.random
local math_floor = math.floor
local table_insert = table.insert
local math_sqrt = math.sqrt
local Token = require 'utils.token'
local Task = require 'utils.task'
local math_round = math.round

local has_quality_mod = script.active_mods['quality'] ~= nil

local function parse_unit_quality(unit_key)
    if not has_quality_mod then
        return unit_key, nil
    end
    local underscore_pos = string.find(unit_key, "_", 1, true)
    if underscore_pos then
        return string.sub(unit_key, 1, underscore_pos - 1), string.sub(unit_key, underscore_pos + 1)
    end
    return unit_key, nil
end



local function create_biter_unit(surface, position, unit_name, force, quality_name, is_boss, boosted_health, tick)
    local entity_params = {
        name = unit_name,
        position = position,
        force = force
    }
    
    if quality_name then
        entity_params.quality = quality_name
    end

    local biter = surface.create_entity(entity_params)
    
    if not biter or not biter.valid then
        return nil
    end
    
    biter.ai_settings.allow_destroy_when_commands_fail = true
    biter.ai_settings.allow_try_return_to_spawner = true
    biter.ai_settings.do_separation = true
    
    return biter
end

local function valid(userdata)
    if not (userdata and userdata.valid) then
        return false
    end
    return true
end

local function find_initial_spot(surface, position)
    local spot = WD.get('spot')
    if not spot then
        local pos = surface.find_non_colliding_position('rocket-silo', position, 128, 1)
        if not pos then
            pos = surface.find_non_colliding_position('rocket-silo', position, 148, 1)
        end
        if not pos then
            pos = surface.find_non_colliding_position('rocket-silo', position, 164, 1)
        end
        if not pos then
            pos = position
        end

        WD.set('spot', pos)
        return pos
    else
        spot = WD.get('spot')
        return spot
    end
end

local function is_closer(pos1, pos2, pos)
    return ((pos1.x - pos.x) ^ 2 + (pos1.y - pos.y) ^ 2) < ((pos2.x - pos.x) ^ 2 + (pos2.y - pos.y) ^ 2)
end

local function shuffle_distance(tbl, position)
    local size = #tbl
    for i = size, 1, -1 do
        local rand = math_random(size)
        if is_closer(tbl[i].position, tbl[rand].position, position) and i > rand then
            tbl[i], tbl[rand] = tbl[rand], tbl[i]
        end
    end
    return tbl
end

local function is_position_near(pos, old_pos)
    return pos.x == old_pos.x and pos.y == old_pos.y
end

local function remove_trees(entity)
    if not valid(entity) then
        return
    end
    local surface = entity.surface
    local radius = 10
    local pos = entity.position
    local trees = surface.find_entities_filtered {
        position = pos,
        radius = radius,
        type = 'tree'
    }
    if #trees > 0 then
        for i, tree in pairs(trees) do
            if tree and tree.valid then
                tree.destroy()
            end
        end
    end
end

local function remove_rocks(entity)
    if not valid(entity) then
        return
    end
    local surface = entity.surface
    local radius = 10
    local pos = entity.position
    local rocks = surface.find_entities_filtered {
        position = pos,
        radius = radius,
        type = 'simple-entity'
    }
    if #rocks > 0 then
        for i, rock in pairs(rocks) do
            if rock and rock.valid then
                rock.destroy()
            end
        end
    end
end

local function fill_tiles(entity, size)
    if not valid(entity) then
        return
    end
    local surface = entity.surface
    local radius = size or 10
    local pos = entity.position
    local t = {'water', 'water-green', 'water-mud', 'water-shallow', 'deepwater', 
    'deepwater-green', 'lava-hot','lava','ammoniacal-ocean','ammoniacal-ocean-2'
}
    local area = {{pos.x - radius, pos.y - radius}, {pos.x + radius, pos.y + radius}}
    local tiles = surface.find_tiles_filtered {
        area = area,
        name = t
    }
    if #tiles > 0 then
        for _, tile in pairs(tiles) do
            surface.set_tiles({{
                name = 'sand-1',
                position = tile.position
            }}, true)
        end
    end

    local litter_radius = 10
    for _, e in pairs(surface.find_entities_filtered({
        type = {"cliff"},
        position = pos,
        radius = litter_radius
    })) do
        e.destroy()
    end

end

local function get_spawn_pos()
    local surface_index = WD.get('surface_index')
    local surface = game.surfaces[surface_index]
    if not surface then

    end

    local c = 0

    ::retry::

    local initial_position = WD.get('spawn_position')

    local located_position = find_initial_spot(surface, initial_position)
    local valid_position = surface.find_non_colliding_position('behemoth-biter', located_position, 32, 1)

    if not valid_position then
        local remove_entities = WD.get('remove_entities')
        if remove_entities then
            c = c + 1
            valid_position = WD.get('spawn_position')

            remove_trees({
                surface = surface,
                position = valid_position,
                valid = true
            })
            remove_rocks({
                surface = surface,
                position = valid_position,
                valid = true
            })
            fill_tiles({
                surface = surface,
                position = valid_position,
                valid = true
            })
            WD.set('spot', 'nil')
            if c == 5 then
                return
            end
            goto retry
        else
            return
        end
    end

    return valid_position
end

local function is_unit_valid(biter)
    local max_biter_age = WD.get('max_biter_age')
    if not biter.entity then
        -- game.print('no entity')
        return false
    end
    if not biter.entity.valid then
        -- game.print('not valid')
        return false
    end
    if biter.spawn_tick + max_biter_age < game.tick then
        -- game.print('too old')
        return false
    end
    return true
end

local function process_active_biters(check_timeout)
    local active_biters = WD.get('active_biters')
    local max_biter_age = WD.get('max_biter_age')
    
    local biter_threat = 0
    local count = 0
    local timeout_threat_loss = 0
    
    for k, biter in pairs(active_biters) do
        local is_valid = false
        local entity = biter.entity
        
        if entity and entity.valid then
            if check_timeout then
                if biter.spawn_tick + max_biter_age >= game.tick then
                    is_valid = true
                    biter_threat = biter_threat + threat_values[entity.name]
                    count = count + 1
                else
                    timeout_threat_loss = timeout_threat_loss +threat_values[entity.name]
                    if entity.force.index == 2 then
                        WD.dec_type_counter(entity.name)
                        active_biters[k] = nil  -- 先移出追踪，避免 destroy 触发 on_entity_died → remove_unit 重复减计数+复活
                        entity.destroy()
                    end
                    active_biters[k] = nil
                end
            else
                is_valid = true
                biter_threat = biter_threat + threat_values[entity.name]
                count = count + 1
            end
        end
        
        if not is_valid then
            active_biters[k] = nil
        end
    end
    
    if timeout_threat_loss > 0 then
        local current_threat = WD.get('active_biter_threat')
        WD.set('active_biter_threat', math.max(0, current_threat - timeout_threat_loss))
    end
    
    if count == 0 then
        WD.set('active_biter_threat', 0)
        WD.set('active_biter_count', 0)
    else
        WD.set('active_biter_threat', math_round(biter_threat, 2))
        WD.set('active_biter_count', count)
    end
end

local function refresh_active_unit_threat()
    process_active_biters(false)
end

local function time_out_biters()
    process_active_biters(false)
end


local function get_random_character()
    local characters = {}
    local surface_index = WD.get('surface_index')
    local p = game.connected_players
    for _, player in pairs(p) do
        if player.character then
            if player.character.valid then
                if player.character.surface.index == surface_index then
                    characters[#characters + 1] = player.character
                end
            end
        end
    end
    if #characters == 0 then
        return nil
    end
    return characters[math.random(#characters)]
end

local function get_car_number()
    local this = WPT.get()
    local car_number = 0
    local active_surface_index = this.active_surface_index

    for k, player in pairs(game.connected_players) do
        if this.tank[player.index] and this.tank[player.index].valid then
            if this.tank[player.index].surface.index == game.surfaces[active_surface_index].index then
                car_number = car_number + 1
            end
        end
    end
    return car_number
end

local function set_main_target()
    local this = WPT.get()
    if not this.active_surface_index or not game.surfaces[this.active_surface_index] then return end
    local target = WD.get('target')
    local main_surface = game.surfaces[this.active_surface_index]
    if target then
        if target.valid and target.destructible and target.surface == main_surface then
            return
        end
    end

    local sec_target
    local number = get_car_number()
    if number ~= 0 then
        sec_target = get_random_car(true)
    else
        sec_target = get_random_character()
    end

    WD.set('target', sec_target)

end

local function set_enemy_evolution()
    local wave_number = WD.get('wave_number')
    local evolution_factor = wave_number * 0.001
    local enemy = game.forces.enemy

    if evolution_factor > 1 then
        evolution_factor = 1
    end
    local surface_index = WD.get('surface_index')
    if enemy.get_evolution_factor(surface_index) == 1 and evolution_factor == 1 then
        return
    end
    -- if evolution_factor <= enemy.evolution_factor then return end
    enemy.set_evolution_factor(evolution_factor, surface_index)
    
end

local function can_units_spawn()
    local threat = WD.get('threat')

    if threat <= 0 then
        return false
    end

    local active_biter_count = WD.get('active_biter_count')
    local max_active_biters = WD.get('max_active_biters')
    if active_biter_count >= max_active_biters then

        return false
    end

    local active_biter_threat = WD.get('active_biter_threat')
    if active_biter_threat >= threat then

        return false
    end
    return true
end

local function get_active_unit_groups_count()
    local unit_groups = WD.get('unit_groups')
    local count = 0

    for k, g in pairs(unit_groups) do
        if g.valid then
            if #g.members > 0 then
                count = count + 1
            else
                g.destroy()
            end
        else
            unit_groups[k] = nil
            local unit_group_last_command = WD.get('unit_group_last_command')
            if unit_group_last_command[k] then
                unit_group_last_command[k] = nil
            end
        end
    end

    return count
end

local function set_next_wave()
    local wave_number = WD.get('wave_number')
    local active_biter_count = WD.get('active_biter_count')
    local max_active_biters = WD.get('max_active_biters')
    local suo = false
    local this = WPT.get()

    if not suo then
        WD.set('wave_number', wave_number + 1)
    end

    wave_number = WD.get('wave_number')

    BiterRolls.wave_defense_set_unit_raffle(wave_number)
    local threat_gain_multiplier = WD.get('threat_gain_multiplier')
    -- 取消获得威胁的难度上限：有效波数不再封顶（原 math.min(wave_number, 4000)）
    local effective_wave_number = wave_number
    local threat_gain = effective_wave_number * threat_gain_multiplier
   
    -- 整体虫子生成量减少20%
    threat_gain = threat_gain * 0.8

    -- 世界10堡垒数量对威胁值的影响
  
    if this.world_number == 10 then
        local arty_num = this.baolei_count
        
        if arty_num < 3 then
            -- 每少1个堡垒，威胁减少15%
            local reduction = (3 - arty_num) * 0.15
            threat_gain = threat_gain * (1 - reduction)
        elseif arty_num > 6 then
            -- 每多1个堡垒，威胁增加15%
            local increase = (arty_num - 6) * 0.15
            threat_gain = threat_gain * (1 + increase)
        end
    end

    local active_biters = WD.get('active_biters')
    local count = 0
    local threat_loss = 0
    
    for k, biter in pairs(active_biters) do
        if biter.entity and biter.entity.valid then
            count = count + 1
        else
            -- 计算无效虫子的威胁值损失
            if biter.entity then
                if biter.entity.valid then
                    threat_loss = threat_loss + math_round(threat_values[biter.entity.name], 2)
                end
            end
            active_biters[k] = nil
        end
    end
    
    -- 如果有威胁值损失，更新总威胁值
    if threat_loss > 0 then
        local current_threat = WD.get('active_biter_threat')
        WD.set('active_biter_threat', math.max(0, current_threat - threat_loss))
    end
    
    -- 如果没有活跃虫子，确保威胁值为0
    if count == 0 then
        WD.set('active_biter_threat', 0)
    end

    WD.set('active_biter_count', count)

    -- 取消获得威胁的难度上限：1000波后的额外难度加成不再封顶（原 wave_number <= 4000）
    if wave_number > 1000 then
        threat_gain = threat_gain * (wave_number * 0.001)
    end

    local threat = WD.get('threat')
    WD.set('threat', threat + math_floor(threat_gain))
    local wave_enforced = WD.get('wave_enforced')
    local next_wave = WD.get('next_wave')
    local wave_interval = WD.get('wave_interval')
    if not wave_enforced then
        WD.set('last_wave', next_wave)
        WD.set('next_wave', game.tick + wave_interval)
    end
end

--- 生成虫子单位组的主要攻击命令序列
-- 该函数生成一个复合命令，包含路径清理、区域攻击和直接攻击三个阶段
-- @param group 单位组对象，包含位置和表面信息
-- @return commands 命令数组，将作为复合命令的子命令执行
local function get_main_command(group)
    local unit_group_command_step_length = WD.get('unit_group_command_step_length')
    local commands = {}
    
    local group_position = {
        x = group.position.x,
        y = group.position.y
    }
    
    local step_length = unit_group_command_step_length
    local target = WD.get('target')
    
    if not valid(target) then
        return
    end

    local target_position = target.position
    local distance_to_target = math_floor(math_sqrt((target_position.x - group_position.x) ^ 2 +
                                                        (target_position.y - group_position.y) ^ 2))
    
    local steps = math_floor(distance_to_target / step_length) + 1
    
    local vector = {math_round((target_position.x - group_position.x) / steps, 3),
                    math_round((target_position.y - group_position.y) / steps, 3)}

    local search_interval = 3
    local search_radius = step_length * 1.5
    
    for i = 1, steps, 1 do
        local old_position = group_position
        
        group_position.x = group_position.x + vector[1]
        group_position.y = group_position.y + vector[2]
        
        if i % search_interval == 0 or i == steps then
            local obstacles = group.surface.find_entities_filtered {
                position = old_position,
                radius = search_radius,
                type = {'simple-entity', 'tree', "wall", "inserter", "loader"},
                limit = 30
            }
            
            if obstacles and #obstacles > 0 then
                shuffle_distance(obstacles, old_position)
                
                for j = 1, #obstacles, 1 do
                    if obstacles[j].valid then
                        commands[#commands + 1] = {
                            type = defines.command.attack,
                            target = obstacles[j],
                            distraction = defines.distraction.by_anything
                        }
                    end
                end
            end
        end
    end

    commands[#commands + 1] = {
        type = defines.command.attack_area,
        destination = {
            x = target_position.x,
            y = target_position.y
        },
        radius = 8,
        distraction = defines.distraction.by_anything
    }

    commands[#commands + 1] = {
        type = defines.command.attack,
        target = target,
        distraction = defines.distraction.by_anything
    }

    return commands
end

local function reform_group(group)
    if not valid(group) then return nil end
    local step_length = WD.get('unit_group_command_step_length')
    local group_position = { x = group.position.x, y = group.position.y }
    local position = group.surface.find_non_colliding_position('biter-spawner', group_position, step_length, 4)
    if position then
        local new_group = group.surface.create_unit_group { position = position, force = group.force }
        for _, biter in pairs(group.members) do
            new_group.add_member(biter)
        end
        local unit_groups = WD.get('unit_groups')
        unit_groups[new_group.unique_id] = new_group
        WD.get('unit_group_pos').positions[new_group.unique_id] = { position = new_group.position, index = 0 }
        return new_group
    else
        local unit_groups = WD.get('unit_groups')
        unit_groups[group.unique_id] = nil
        WD.get('unit_group_pos').positions[group.unique_id] = nil
        local unit_group_last_command = WD.get('unit_group_last_command')
        if unit_group_last_command[group.unique_id] then
            unit_group_last_command[group.unique_id] = nil
        end
        group.destroy()
    end
    return nil
end

local function command_to_main_target(group, bypass)
    if not valid(group) then
        return
    end
    local unit_group_last_command = WD.get('unit_group_last_command')
    local unit_group_command_delay = WD.get('unit_group_command_delay')
    if not bypass then
        if not unit_group_last_command[group.unique_id] then
            unit_group_last_command[group.unique_id] = game.tick - (unit_group_command_delay + 1)
        end

        if unit_group_last_command[group.unique_id] then
            if unit_group_last_command[group.unique_id] + unit_group_command_delay > game.tick then
                return
            end
        end
    end

    local fill_tiles_so_biter_can_path = WD.get('fill_tiles_so_biter_can_path')
    if fill_tiles_so_biter_can_path then
        fill_tiles(group, 12)
    end

    if not valid(group) then
        return
    end

    local commands = get_main_command(group)

    local surface_index = WD.get('surface_index')

    if group.surface.index ~= surface_index then
        return
    end

    group.set_command({
        type = defines.command.compound,
        structure_type = defines.compound_command.return_last,
        commands = commands
    })

    if valid(group) then
        unit_group_last_command[group.unique_id] = game.tick
        
        local this = WPT.get()
        if not this.enemy_missions then
            this.enemy_missions = {}
        end
        
        local target = WD.get('target')
        if valid(target) then
            this.enemy_missions[group.unique_id] = {
                target_pos = target.position,
                retry_count = 0,
                active = true
            }
        end
    end
end

local function spawn_unit_group()
    if not can_units_spawn() then
        return
    end
    local target = WD.get('target')
    if not valid(target) then
        return
    end

    -- local max_active_unit_groups = WD.get('max_active_unit_groups')
    -- if get_active_unit_groups_count() >= max_active_unit_groups then
    --     return
    -- end
    local surface_index = WD.get('surface_index')

    local surface = game.surfaces[surface_index]

    local spawn_position = get_spawn_pos()
    if not spawn_position then
        return
    end

    local current_time = game.tick
    local last_mine_check_time = WD.get('last_mine_check_time')
    local need_check_mine = (current_time - last_mine_check_time) >= 1200

    if need_check_mine then
        local radius = 10
        for k, v in pairs(surface.find_entities_filtered {
            position = spawn_position,
            radius = radius,
            name = 'land-mine'
        }) do
            if v and v.valid then
                v.die()
            end
        end
        WD.set('last_mine_check_time', current_time)
    end

    -- 生怪前清场：清树、清石头、填水（与 MFv3 对齐）
    local remove_entities = WD.get('remove_entities')
    if remove_entities then
        remove_trees({ surface = surface, position = spawn_position, valid = true })
        remove_rocks({ surface = surface, position = spawn_position, valid = true })
        fill_tiles({ surface = surface, position = spawn_position, valid = true })
    end

    local wave_number = WD.get('wave_number')
    local position = spawn_position

    local unit_group = surface.create_unit_group({
        position = position,
        force = 'enemy'
    })

    local group_size = 64
    local tick = game.tick
    local max_threat = WD.get('threat') - WD.get('active_biter_threat')

    local unit_table = BiterRolls.wave_defense_generate_unit_table(group_size, 0.73, 0.27, max_threat)
     
    local spawned_biters = {}
    for _, unit_info in ipairs(unit_table) do
        local unit_name = unit_info.unit_name
        local quality_name = unit_info.quality_name

        -- 共享计数器检查
        local can_spawn, category = WD.try_register_biter_spawn(unit_name)
        if can_spawn then
            local biter = create_biter_unit(surface, position, unit_name, 'enemy', quality_name, false, 1, tick)
            if biter then
                unit_group.add_member(biter)
                spawned_biters[#spawned_biters + 1] = biter
            end
        else
            -- 超额，存入血量池
            WD.add_health_to_pool(unit_name, quality_name, category)
        end
    end
    
    if #spawned_biters > 0 then
        local active_biters = WD.get('active_biters')
        local active_biter_count = WD.get('active_biter_count')
        local active_biter_threat = WD.get('active_biter_threat')
        
        for _, biter in pairs(spawned_biters) do
            active_biters[biter.unit_number] = {
                entity = biter,
                spawn_tick = tick
            }
            active_biter_count = active_biter_count + 1
            active_biter_threat = active_biter_threat + math_round(threat_values[biter.name], 2)
            WD.inc_type_counter(biter.name)
        end
        
        WD.set('active_biters', active_biters)
        WD.set('active_biter_count', active_biter_count)
        WD.set('active_biter_threat', active_biter_threat)
    end

    local unit_groups = WD.get('unit_groups')
    unit_groups[unit_group.unique_id] = unit_group
    WD.get('unit_group_pos').positions[unit_group.unique_id] = { position = unit_group.position, index = 0 }
    if math_random(1, 2) == 1 then
        WD.set('random_group', unit_group.unique_id)
    end
    WD.set('spot', 'nil')
    
    command_to_main_target(unit_group, true)

    -- 单独判断并生成撼地虫（不进编队、不做特殊设置，仅单纯生成并朝向主目标）
    BiterRolls.try_spawn_demolisher(surface, position, target)

    return true
end



local cleanup_mission_task = Token.register(function(data)
    local group = data.group
    
    -- 检查队伍是否存在
    if group and group.valid then
        -- 遍历所有成员并销毁（防止队伍解散后虫子变成野生并在原地发呆）
        for _, member in pairs(group.members) do
            if member.valid then
                member.destroy() -- 直接销毁，不留尸体
                -- 或者用 member.die() 让它们原地暴毙留尸体
            end
        end
        
        -- 销毁队伍对象
        group.destroy()
    else
        game.print('队伍不存在或已被销毁')
    end
end)
-- 【新增】尝试重组并重启命令
local function attempt_regroup_and_restart(surface, search_position, target_position, retry_count)
    if retry_count > 5 then
        -- 如果重试超过5次，说明这个地方地形太恶心，彻底放弃，销毁附近的单位以防堆积
        local units = surface.find_entities_filtered({
            position = search_position,
            radius = 20,
            type = "unit",
            force = "player"
        })
        for _, unit in pairs(units) do
            if unit.valid then unit.die() end
        end
        return
    end

    -- 搜索附近的空闲联军单位（没有队伍的，或者队伍已经失效的）
    local nearby_units = surface.find_entities_filtered({
        position = search_position,
        radius = 30, -- 搜索半径
        type = "unit",
        force = "player"
    })

    local candidates = {}
    for _, unit in pairs(nearby_units) do
        if unit.valid then
            -- 只有当单位没有组，或者它所在的组已经没有任何命令时（认为是失效组），才吸纳进来
            if not unit.unit_group or not unit.unit_group.valid then
                table.insert(candidates, unit)
            end
        end
    end

    if #candidates == 0 then return end -- 没人了，不用重组

    -- 创建新组
    local new_group = surface.create_unit_group({
        position = search_position,
        force = "player"
    })

    -- 将散兵加入新组
    for _, unit in pairs(candidates) do
        new_group.add_member(unit)
    end

    -- 重新下达攻击指令
    new_group.set_command({
        type = defines.command.attack_area,
        destination = target_position,
        radius = 16,
        distraction = defines.distraction.by_enemy
    })

    -- 【关键】更新全局注册表
    local this = WPT.get()
    if not this.allied_missions then this.allied_missions = {} end
    
    -- 记录新组的信息，继承之前的重试次数+1
    this.allied_missions[new_group.unique_id] = {
        target_pos = target_position,
        retry_count = retry_count + 1,
        active = true
    }
end

local function attempt_enemy_regroup_and_restart(surface, search_position, target_position, retry_count)
    if retry_count > 5 then
        local units = surface.find_entities_filtered({
            position = search_position,
            radius = 20,
            type = "unit",
            force = "enemy"
        })
        for _, unit in pairs(units) do
            if unit.valid then unit.die() end
        end
        return
    end

    local nearby_units = surface.find_entities_filtered({
        position = search_position,
        radius = 30,
        type = "unit",
        force = "enemy"
    })

    local candidates = {}
    for _, unit in pairs(nearby_units) do
        if unit.valid then
            if not unit.unit_group or not unit.unit_group.valid then
                table.insert(candidates, unit)
            end
        end
    end

    if #candidates == 0 then return end

    local new_group = surface.create_unit_group({
        position = search_position,
        force = "enemy"
    })

    for _, unit in pairs(candidates) do
        new_group.add_member(unit)
    end

    local commands = {}
    local group_position = {
        x = new_group.position.x,
        y = new_group.position.y
    }
    
    local unit_group_command_step_length = WD.get('unit_group_command_step_length')
    local step_length = unit_group_command_step_length
    local target_position_vec = target_position
    local distance_to_target = math_floor(math_sqrt((target_position_vec.x - group_position.x) ^ 2 +
                                                        (target_position_vec.y - group_position.y) ^ 2))
    
    local steps = math_floor(distance_to_target / step_length) + 1
    
    local vector = {math_round((target_position_vec.x - group_position.x) / steps, 3),
                    math_round((target_position_vec.y - group_position.y) / steps, 3)}

    local search_interval = 6
    local search_radius = step_length * 1.5
    
    for i = 1, steps, 1 do
        local old_position = group_position
        
        group_position.x = group_position.x + vector[1]
        group_position.y = group_position.y + vector[2]
        
        if i % search_interval == 0 or i == steps then
            local obstacles = new_group.surface.find_entities_filtered {
                position = old_position,
                radius = search_radius,
                type = {'simple-entity', 'tree', "wall", "inserter", "loader"},
                limit = 10
            }
            
            if obstacles and #obstacles > 0 then
                shuffle_distance(obstacles, old_position)
                
                for j = 1, #obstacles, 1 do
                    if obstacles[j].valid then
                        commands[#commands + 1] = {
                            type = defines.command.attack,
                            target = obstacles[j],
                            distraction = defines.distraction.by_anything
                        }
                    end
                end
            end
        end
    end

    commands[#commands + 1] = {
        type = defines.command.attack_area,
        destination = {
            x = target_position_vec.x,
            y = target_position_vec.y
        },
        radius = 8,
        distraction = defines.distraction.by_anything
    }

    new_group.set_command({
        type = defines.command.compound,
        structure_type = defines.compound_command.return_last,
        commands = commands
    })

    local this = WPT.get()
    if not this.enemy_missions then this.enemy_missions = {} end
    
    this.enemy_missions[new_group.unique_id] = {
        target_pos = target_position,
        retry_count = retry_count + 1,
        active = true
    }
end
local kill_forces = Token.register(function(data)
    for _, v in pairs(data) do
        if v and v.valid then
            v.destroy()
        end
    end
end)
-- 世界10特殊功能：为玩家生产虫子攻击敌方机器人平台
local function spawn_player_biters_against_enemy_roboport()
    -- 检查是否为世界10
  
    local this = WPT.get()
    if this.world_number ~= 10 then
        return
    end
    
    -- 检查玩家是否有火箭发射井
 
    if not this.silo or not this.silo.valid then
        return
    end
    
    -- 检查敌方堡垒是否有机器人平台

    local arty_data = enemy_arty.get()
    local has_enemy_roboport = false
    local roboport_position = nil
    
    for _, baolei in pairs(arty_data.arty) do
        if baolei.roboport and baolei.roboport.valid then
            has_enemy_roboport = true
            roboport_position = baolei.roboport.position
            break
        end
    end
    
    -- 如果敌方有机器人平台，则为玩家生产虫子攻击敌方机器人平台附近区域
    if has_enemy_roboport and roboport_position then
        local surface = game.surfaces['nauvis']
        
        -- 查找火箭发射井位置
        local rocket_silo_position = this.silo.position
        local group={}
        -- 如果找到火箭发射井，则在其附近生成虫子
        if rocket_silo_position then
            local wave_number = WD.get('wave_number')
            local values= 50+1*wave_number+this.science*2+this.protectors_value*10
            -- 使用wave_defense_generate_unit_table函数生成虫子表
            
            local unit_table = BiterRolls.wave_defense_generate_unit_table(64, 0.6, 0.4, values)
            
            -- 检测是否启用了品质mod
            local has_quality_mod = script.active_mods['quality'] ~= nil
            
            -- 创建玩家虫子组
            local unit_group = surface.create_unit_group({
                position = rocket_silo_position,
                force = 'player'
            })
            
            -- biter_rolls 生成的虫子表已抽离 demolisher，联军无需再对其特殊处理
            -- 同时限制「单次召唤」放进去的五足虫（pentapod）不超过 5 只（不查场上存量、不跨次累计）
            local MAX_PENTAPODS_PER_SUMMON = 5
            local pentapod_count = 0

            local allied_unit_table = {}
            for _, unit_info in ipairs(unit_table) do
                local unit_name = unit_info.unit_name
                if string.find(unit_name, 'pentapod', 1, true) then
                    if pentapod_count < MAX_PENTAPODS_PER_SUMMON then
                        pentapod_count = pentapod_count + 1
                        allied_unit_table[#allied_unit_table + 1] = unit_info
                    end
                else
                    allied_unit_table[#allied_unit_table + 1] = unit_info
                end
            end

            -- 根据生成的虫子表创建虫子并加入组
            for _, unit_info in ipairs(allied_unit_table) do
                local unit_name = unit_info.unit_name
                local quality_name = unit_info.quality_name
                
                local random_offset = {
                        x = rocket_silo_position.x ,
                        y = rocket_silo_position.y 
                    }
                    
                    -- 在火箭发射井附近随机位置生成虫子
                     local valid_position = surface.find_non_colliding_position(
                        unit_name,
                        random_offset,
                        10,
                        1
                    )
                    if valid_position then
                        local unit
                        if has_quality_mod and quality_name then
                            -- 创建带品质的虫子
                            unit = surface.create_entity({
                                name = unit_name,
                                position = valid_position,
                                force = 'player',
                                quality = quality_name
                            })
                        else
                            -- 创建普通虫子
                            unit = surface.create_entity({
                                name = unit_name,
                                position = valid_position,
                                force = 'player'
                            })
                        end
                        
                        if unit and unit.valid then
                            -- 将虫子加入组
                         group[#group + 1] = unit  
    unit.ai_settings.allow_try_return_to_spawner = false
                            unit_group.add_member(unit)
                                rendering.draw_text {
        text = '联军',
        surface = unit.surface,
        target = unit,
        target_offset = {0, -2.6},
        color = {
            r =  0.6 + 0.25,
            g = 0.6 + 0.25,
            b = 0.6 + 0.25,
            a = 1
        },
        scale = 1.05,
        font = 'default-large-semibold',
        alignment = 'center',
        scale_with_zoom = false
    }
                       
                    end
                end
            end
            
            -- 为虫子组设置攻击命令
            if unit_group.valid then
                -- 1. 确保AI设置正确，防止寻路失败直接自杀（这步依然很重要）
                for _, member in pairs(unit_group.members) do
                    member.ai_settings.allow_destroy_when_commands_fail = false
                    member.ai_settings.allow_try_return_to_spawner = false
                end

                -- 2. 下达命令
                unit_group.set_command({
                    type = defines.command.attack_area,
                    destination = roboport_position, 
                    radius = 16,                     
                    distraction = defines.distraction.by_enemy 
                })
               
               -- 【修改】不再使用 Task.set_timeout，改为注册到任务表
               local this = WPT.get()
              
               
               -- 注册这个组的任务信息
               this.allied_missions[unit_group.unique_id] = {
                   target_pos = roboport_position, -- 记录目标
                   retry_count = 0,                -- 初始重试次数
                   active = true
               }
                Task.set_timeout_in_ticks(60 * 60*2, kill_forces, group)
            end
            
        end
    else
        -- 如果敌方没有机器人平台但我方有火箭发射井，则将values转化为金币并平均分给在线玩家
        if this.silo and this.silo.valid then
            local wave_number = WD.get('wave_number')
            local values= 50+1*wave_number+this.science*2+this.protectors_value*8
            
            -- 获取在线玩家
            local online_players = {}
            for _, player in pairs(game.connected_players) do
                if player.afk_time < 36000 then -- 非挂机玩家
                    table.insert(online_players, player)
                end
            end
            
            -- 如果有在线玩家，则分配金币
            if #online_players > 0 then
                local gold_per_player = math.floor(values / #online_players)
                for _, player in pairs(online_players) do
                    -- 增加玩家金币
                    if player.character and player.character.valid then
                player.insert({name = "coin", count = gold_per_player})
                    end
                
                end
                game.print("联军：如今胜利在即，军粮有余，每名将领获得" .. gold_per_player .. " 金币")
            end
        end
    end
end

local function check_group_positions()
    local resolve_pathing = WD.get('resolve_pathing')
    if not resolve_pathing then return end

    local unit_groups = WD.get('unit_groups')
    local target = WD.get('target')
    if not valid(target) then return end

    local unit_group_pos = WD.get('unit_group_pos')

    for id, group in pairs(unit_groups) do
        if not group.valid then
            unit_groups[id] = nil
            unit_group_pos.positions[id] = nil
            goto skip
        end

        if group.state == defines.group_state.finished then
            command_to_main_target(group, true)
            goto skip
        end

        local ugp = unit_group_pos.positions[id]
        if not ugp then
            unit_group_pos.positions[group.unique_id] = { position = group.position, index = 0 }
            goto skip
        end

        if is_position_near(group.position, ugp.position) then
            ugp.index = ugp.index + 1
            if ugp.index >= 2 then
                command_to_main_target(group, true)
                fill_tiles(group, 30)
                remove_rocks(group)
                remove_trees(group)
                if group.valid and ugp.index >= 4 then
                    unit_group_pos.positions[id] = nil
                    reform_group(group)
                end
            end
        else
            ugp.position = group.position
            ugp.index = 0
        end

        ::skip::
    end
end

local function on_tick()
    local tick = game.tick
    local game_lost = WD.get('game_lost')

    if tick % 60 == 0 then
        local players = game.connected_players
        for _, player in pairs(players) do
            update_gui(player)
        end
        
        -- 每秒执行一次的任务
        set_main_target()
        spawn_unit_group()
    end

    if game_lost then
        return
    end

    local next_wave = WD.get('next_wave')
    if tick > next_wave then
        set_next_wave()
    end

    -- 优化任务调度，直接检查 tick
    if tick % 90 == 0 then set_enemy_evolution() end
    if tick % 120 == 0 then check_group_positions() end
    if tick % 150 == 0 then ThreatEvent.build_nest() end
    if tick % 180 == 0 then ThreatEvent.build_worm() end
    
    if tick % 1800 == 0 then
        spawn_player_biters_against_enemy_roboport()
    end
    
    if tick % 3600 == 0 then time_out_biters() end
    if tick % 1800 == 0 then WD.reconcile_pentapod_counts() end
    if tick % 7200 == 0 then refresh_active_unit_threat() end

    -- 每5分钟清理一次无效的任务记录
    if tick % 18000 == 0 then
        local this = WPT.get()
        if this.allied_missions then
            local current_time = game.tick
            for id, mission in pairs(this.allied_missions) do
                if current_time - id > 36000 then
                    this.allied_missions[id] = nil
                end
            end
        end
        if this.enemy_missions then
            local current_time = game.tick
            for id, mission in pairs(this.enemy_missions) do
                if current_time - id > 36000 then
                    this.enemy_missions[id] = nil
                end
            end
        end
    end
end

Event.on_nth_tick(30, on_tick)

local function on_ai_command_completed(event)
    local unit_number = event.unit_number
    local result = event.result
    
    local this = WPT.get()
    
    if not this.allied_missions then
        this.allied_missions = {}
    end
    
    if not this.enemy_missions then
        this.enemy_missions = {}
    end

    local mission = this.allied_missions[unit_number]
    local enemy_mission = this.enemy_missions[unit_number]
    
    if not mission and not enemy_mission then
        return
    end

    local group = event.unit_group
    local search_pos = nil
    
    if group and group.valid then
        search_pos = group.position
    else
        return
    end
    
    if mission then
        this.allied_missions[unit_number] = nil

        if result == defines.behavior_result.fail or result == defines.behavior_result.fail_destroy then
            attempt_regroup_and_restart(group.surface, search_pos, mission.target_pos, mission.retry_count)
        end
    end
    
    if enemy_mission then
        this.enemy_missions[unit_number] = nil

        if result == defines.behavior_result.fail or result == defines.behavior_result.fail_destroy then
            attempt_enemy_regroup_and_restart(group.surface, search_pos, enemy_mission.target_pos, enemy_mission.retry_count)
        end
    end
end

-- 注册事件
Event.add(defines.events.on_ai_command_completed, on_ai_command_completed)

return Public
