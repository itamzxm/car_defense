local Event = require 'utils.event'

local Global = require 'utils.global'
local Task = require 'utils.task'
local arty_count = {construction_queue = {}}
local Public = {}
local get_baolei_pos = require'stronghold_generation_algorithm_v2'.find_available_stronghold_position
local RPG = require 'modules.rpg.table'
local Token = require 'utils.token'
local WPT = require 'maps.amap.table'
local Loot = require 'maps.amap.loot'
local WD = require 'modules.wave_defense.table'
local World = require 'maps.amap.world.framework'
-- 敌人炮台配置表
local enemy_turret = {
    --  [1]={name='stone-wall',worth=1,wave_number=0},
    [2] = {
        name = 'biter-spawner',
        worth = 20,
        wave_number = 500,
        ban = true
    },
    [3] = {
        name = 'laser-turret',
        worth = 8,
        wave_number = 150
    },
    [4] = {
        name = 'gun-turret',
        worth = 5,
        wave_number = 100
    },
    [5] = {
        name = 'medium-worm-turret',
        worth = 10,
        wave_number = 300,
        ban = true
    },
    [6] = {
        name = 'flamethrower-turret',
        worth = 10,
        wave_number = 250
    },
    [7] = {
        name = 'big-worm-turret',
        worth = 20,
        wave_number = 500,
        ban = true
    },
    [8] = {
        name = 'behemoth-worm-turret',
        worth = 50,
        wave_number = 800,
        ban = true
    },
    [9] = {
        name = 'artillery-turret',
        worth = 100,
        wave_number = 1200
    },
    [10] = {
        name = 'tesla-turret',
        worth = 15,
        wave_number = 600
    },
    [11] = {
        name = 'rocket-turret',
        worth = 25,
        wave_number = 900
    }
}

-- 堡垒分批创建任务队列管理器
local construction_queue = arty_count.construction_queue

-- 初始化任务队列
function Public.init_construction_queue()
    construction_queue.tasks = {}
    construction_queue.current_index = 1
    construction_queue.active_constructions = {}
end

-- 添加分批任务到队列
function Public.add_batch_task(task_data)
    if not construction_queue.tasks then
        construction_queue.tasks = {}
        construction_queue.current_index = 1
        construction_queue.active_constructions = {}
    end
    construction_queue.tasks[#construction_queue.tasks + 1] = task_data
end

-- 获取下一个待执行的任务
function Public.get_next_task()
    if construction_queue.current_index <= #construction_queue.tasks then
        local task = construction_queue.tasks[construction_queue.current_index]
        construction_queue.current_index = construction_queue.current_index + 1
        
        -- 更新对应建设任务的当前索引
        if task.baolei_id and construction_queue.active_constructions[task.baolei_id] then
            construction_queue.active_constructions[task.baolei_id].current_index = construction_queue.current_index
        end
        
        return task
    end
    return nil
end

-- 检查是否还有待执行的任务
function Public.has_pending_tasks()
    return construction_queue.tasks and construction_queue.current_index <= #construction_queue.tasks
end

-- 获取当前队列长度
function Public.get_queue_length()
    return construction_queue.tasks and #construction_queue.tasks or 0
end

-- 执行单个分批任务
function Public.execute_batch_task(task)
    local success, result = pcall(task.func, unpack(task.params))
    if not success then
        game.print({'amap.stronghold_batch_failed', tostring(result)})
        game.print({'amap.task_type', task.type})
    end
    return success
end

-- 启动新的堡垒分批创建
function Public.start_baolei_construction(position, wave_number, surface, robot_number, fix_number, out_wall, something, baolei_id, cleanup_terrain, skip_count)
    if cleanup_terrain == nil then
        cleanup_terrain = true
    end
    if skip_count == nil then
        skip_count = false
    end
    if not construction_queue.tasks then
        construction_queue.tasks = {}
        construction_queue.current_index = 1
        construction_queue.active_constructions = {}
    end
    
    local construction_id = baolei_id
    local start_index = #construction_queue.tasks + 1
    
    construction_queue.active_constructions[construction_id] = {
        position = position,
        wave_number = wave_number,
        surface = surface,
        robot_number = robot_number,
        fix_number = fix_number,
        out_wall = out_wall,
        something = something,
        baolei_id = baolei_id,
        skip_count = skip_count,
        current_stage = 1,
        all_thing = {},
        roboport = nil,
        task_start_index = start_index,
        task_end_index = start_index - 1,  -- 还没有添加任务
        current_index = start_index  -- 初始化当前索引
    }
    
    -- 清理附近旧奖励箱
    Public.cleanup_nearby_reward_chests(position, surface)
    
    -- 创建清理任务
    if cleanup_terrain then
        Public.create_cleanup_tasks(position, surface, baolei_id)
    end
    
    -- 创建地形设置任务
    if cleanup_terrain then
        Public.create_terrain_tasks(position, surface, baolei_id)
    end
    
    -- 创建核心建筑任务
    Public.create_core_building_tasks(position, surface, robot_number, fix_number, something, baolei_id)
    
    -- 创建炮台任务
    Public.create_turret_tasks(position, surface, wave_number, baolei_id)
    
    -- 创建内层墙壁任务
    Public.create_inner_wall_tasks(position, surface, baolei_id)
    
    -- 创建外层墙壁任务（如果需要）
    if out_wall then
        Public.create_outer_wall_tasks(position, surface, baolei_id)
    end
    
    -- 更新任务结束索引
    construction_queue.active_constructions[construction_id].task_end_index = #construction_queue.tasks
    
    return construction_id
end

local ammo = {}
ammo = {
    [1] = {
        name = 'firearm-magazine'
    },
    [2] = {
        name = 'piercing-rounds-magazine'
    },
    [3] = {
        name = 'uranium-rounds-magazine'
    }
}

-- 堡垒守军品质配置（参考波防系统 modules/wave_defense/biter_rolls.lua 的 calculate_quality_raffle）
-- 品质概率随波数递增：
--   * 起始波 QUALITY_START_WAVE 时「获得任意品质」概率为 0；
--   * 线性增长到 QUALITY_FULL_WAVE 时达到 QUALITY_MAX_CHANCE（默认满额 1.0，即此波后所有守军炮台必带品质）；
--   * 超过 QUALITY_DECAY_START 波后，精良/稀有/史诗的一部分概率逐步转移给传说（与波防 decay 一致）。
-- 各品质之间的相对比例由 quality_base_chances 决定（与波防一致）。
local QUALITY_START_WAVE    = 300
local QUALITY_FULL_WAVE     = 3000
local QUALITY_DECAY_START   = 3000
local QUALITY_DECAY_END     = 6000
local QUALITY_MAX_CHANCE    = 1.0   -- 高波时「获得任意品质」的上限概率，可调小（如 0.6）以削弱

local quality_base_chances = {
    { name = "legendary", base_chance = 0.005 },
    { name = "epic",      base_chance = 0.015 },
    { name = "rare",      base_chance = 0.025 },
    { name = "uncommon",  base_chance = 0.05  }
}
local quality_base_total = 0.005 + 0.015 + 0.025 + 0.05

-- 根据波数计算各品质权重与「获得任意品质」的总概率
local function compute_quality_raffle(wave_number)
    if wave_number < QUALITY_START_WAVE then
        return 0, {}
    end

    local progress = math.min((wave_number - QUALITY_START_WAVE) / (QUALITY_FULL_WAVE - QUALITY_START_WAVE), 1)
    local total_quality_chance = progress * QUALITY_MAX_CHANCE

    if total_quality_chance <= 0 then
        return 0, {}
    end

    local weights = {}
    for _, item in ipairs(quality_base_chances) do
        weights[item.name] = (item.base_chance / quality_base_total) * total_quality_chance
    end

    -- 超过衰减起始波后，将 精良/稀有/史诗 的一部分概率转移给 传说
    local decay_progress = 0
    if wave_number >= QUALITY_DECAY_START then
        decay_progress = math.min((wave_number - QUALITY_DECAY_START) / (QUALITY_DECAY_END - QUALITY_DECAY_START), 1)
    end

    if decay_progress > 0 then
        local transferable = { "epic", "rare", "uncommon" }
        local total_transfer = 0
        for _, name in ipairs(transferable) do
            local transfer_amount = weights[name] * decay_progress
            weights[name] = weights[name] - transfer_amount
            total_transfer = total_transfer + transfer_amount
        end
        weights["legendary"] = weights["legendary"] + total_transfer
    end

    return total_quality_chance, weights
end

-- 根据波数随机选择品质（参考波防 select_random_quality 的两步判定）
local function select_quality_by_chance(wave_number)
    -- 检查是否启用了品质mod
    if script.active_mods['quality'] == nil then
        return nil
    end

    local total_quality_chance, weights = compute_quality_raffle(wave_number)

    -- 第一步：本次是否获得品质
    if math.random() > total_quality_chance then
        return nil
    end

    -- 第二步：在已获得品质的前提下，加权抽取具体品质
    local total_weight = 0
    for _, w in pairs(weights) do
        total_weight = total_weight + w
    end
    if total_weight <= 0 then
        return nil
    end

    local r = math.random() * total_weight
    local current = 0
    for _, item in ipairs(quality_base_chances) do
        current = current + weights[item.name]
        if r <= current then
            return item.name
        end
    end

    return nil
end

local player_build = {'rocket-silo', 'steam-turbine', 'assembling-machine-1', 'assembling-machine-2',
                      'assembling-machine-3', 'oil-refinery', 'chemical-plant', 'car', 'spidertron', 'tank',
                      'character', 'gun-turret', 'electric-mining-drill', 'laser-turret', 'steam-engine', 'roboport', 'big-mining-drill'    ,'foundry','rail-support'
                        
  ,'recycler'
  ,'electromagnetic-plant'
  ,'heating-tower'}
local artillery_target_entities = {
    'character',
    'radar',
    'roboport',
    'artillery-wagon',
    'artillery-turret',
    'flamethrower-turret',
    'spidertron',
    'tesla-turret',
    'railgun-turret',
    'small-worm-turret',
    'medium-worm-turret',
    'big-worm-turret',
    'behemoth-worm-turret',
    'biter-spawner',
    'spitter-spawner'
}

Global.register(arty_count, function(tbl)
    arty_count = tbl
end)

function Public.reset_table()
    arty_count.unit = {}
    arty_count.neet_to_kill = {}
    arty_count.pace = 1.5
    arty_count.radius = 105
    arty_count.surface = {}
    arty_count.index = 1
    arty_count.fire = {}
    arty_count.arty = {}
    arty_count.roboport_wave = {}
    arty_count.all = {}
    arty_count.gun = {}
    arty_count.laser = {}
    arty_count.flame = {}
    arty_count.tesla = {}
    arty_count.rocket = {}
    arty_count.last = {}
    arty_count.attack_table={}
    arty_count.can_attack_table={}
    arty_count.ammo_index = 1
    arty_count.count = 0
    arty_count.arty_check_count = 0
    arty_count.construction_queue = {
        tasks = {},
        current_index = 1,
        active_constructions = {}
    }
    arty_count.baolei_creation_times = {}
    arty_count.next_baolei_speed_bonus = 0
end

local on_init = function()
    Public.reset_table()
    Public.init_construction_queue()
end

local shot_hd = Token.register(function(entity)

    if not entity or not entity.valid then
        return
    end
    local wave_defense_table = WD.get_table()
    if not wave_defense_table.target then
        return
    end
    if not wave_defense_table.target.valid then
        return
    end
    local target = wave_defense_table.target
    local e = entity.surface.create_entity({
        name = 'atomic-rocket',
        position = {
            x = target.position.x,
            y = target.position.y - 100
        },

        force = game.forces.enemy,
        source = {
            x = target.position.x,
            y = target.position.y - 100
        },
        target = target,
        speed = 1
    })
    game.print({'amap.nuke_fired_reloading'}, {255, 0, 0})
end)
function Public.add_laser(k)
    arty_count.laser[#arty_count.laser + 1] = k
end
function Public.add_gun(k)
    arty_count.gun[#arty_count.gun + 1] = k
end
function Public.add_flame(k)
    arty_count.flame[#arty_count.flame + 1] = k
end
function Public.add_tesla(k)
    arty_count.tesla[#arty_count.tesla + 1] = k
end
function Public.add_rocket(k)
    arty_count.rocket[#arty_count.rocket + 1] = k
end

function Public.add_arty(k)
    arty_count.arty[#arty_count.arty + 1] = k
end


function Public.get_ammo()
    local index = arty_count.ammo_index
    local ammo_name = ammo[index].name
    return ammo_name
end


function Public.get(key)
  if key then
    return arty_count[key]
  else
    return arty_count
  end
end

function Public.check_and_add_to_attack_table(entity)
  if not entity or not entity.valid then return end
  -- [RISK] 无 surface 检查：若传入的 entity 与重炮不在同一 surface，
  -- 会被加入 can_attack_table 并在 do_artillery_turrets_targets 中被选为目标，
  -- 导致 artillery_target_callback 在目标 surface 的错误坐标创建弹药（跨 surface 攻击）。
  -- 当前调用路径均来自同一 surface 的 find_entities_filtered，暂无实际触发，
  -- 但新增调用点时必须确保 entity 与重炮在同一 surface。
  if #arty_count.all == 0 then return end
  
  local entity_pos = entity.position
  for _, artillery in pairs(arty_count.all) do
    if artillery and artillery.valid then
      local artillery_pos = artillery.position
      local distance_squared = 
        (artillery_pos.x - entity_pos.x)^2 + 
        (artillery_pos.y - entity_pos.y)^2
      if distance_squared <= arty_count.radius * arty_count.radius then
        local already_exists = false
        for _, existing in pairs(arty_count.can_attack_table) do
          if existing == entity then
            already_exists = true
            break
          end
        end
        if not already_exists then
          arty_count.can_attack_table[#arty_count.can_attack_table + 1] = entity
        end
        return
      end
    end
  end
end


local function fast_remove(tbl, index)
    local count = #tbl
    if index > count then
        return
    elseif index < count then
        tbl[index] = tbl[count]
    end

    tbl[count] = nil
end

local function gun_bullet()
    for index = 1, #arty_count.gun do
        local turret = arty_count.gun[index]
        if not (turret and turret.valid) then
            fast_remove(arty_count.gun, index)
            return
        end
        local index = arty_count.ammo_index
        local ammo_name = ammo[index].name
        turret.insert {
            name = ammo_name,
            count = 200
        }
    end
end

local function flame_bullet()
    for index = 1, #arty_count.flame do
        local turret = arty_count.flame[index]
        if not (turret and turret.valid) then
            fast_remove(arty_count.flame, index)
            return
        end

        turret.set_fluid(1, {name='light-oil', amount=100})

    end
end

local function energy_bullet()

    for index = 1, #arty_count.laser do
        local turret = arty_count.laser[index]
        if not (turret and turret.valid) then
            fast_remove(arty_count.laser, index)
            return
        end
        turret.energy = 99999999
    end
end

-- 特斯拉炮塔弹药补给（tesla-ammo + 能量充电）
local function tesla_bullet()
    for index = 1, #arty_count.tesla do
        local turret = arty_count.tesla[index]
        if not (turret and turret.valid) then
            fast_remove(arty_count.tesla, index)
            return
        end
        turret.insert { name = 'tesla-ammo', count = 200 }
        turret.energy = 99999999
    end
end

-- 火箭炮塔弹药补给
-- 检测当前弹药：若有则按当前弹药名补给；若空则随机选 rocket 或 explosive-rocket
local function rocket_bullet()
    for index = 1, #arty_count.rocket do
        local turret = arty_count.rocket[index]
        if not (turret and turret.valid) then
            fast_remove(arty_count.rocket, index)
            return
        end
        local inv = turret.get_inventory(defines.inventory.turret_ammo)
        local current_ammo = nil
        if inv and inv.valid then
            -- Factorio 2.0: get_contents() 返回数组 { {name=..., count=..., quality=...}, ... }
            local contents = inv.get_contents()
            local first = contents and contents[1]
            if first and first.name then
                current_ammo = first.name
            end
        end
        if not current_ammo then
            current_ammo = math.random(1, 2) == 1 and 'rocket' or 'explosive-rocket'
        end
        turret.insert { name = current_ammo, count = 200 }
    end
end

-- 清理附近旧奖励箱
function Public.cleanup_nearby_reward_chests(position, surface)
    local search_radius = 30
    local area = {
        left_top = {position.x - search_radius, position.y - search_radius},
        right_bottom = {position.x + search_radius, position.y + search_radius}
    }
    
    local chests_to_remove = surface.find_entities_filtered({
        name = {"steel-chest", "crash-site-chest-1", "crash-site-chest-2"},
        area = area
    })
    
    for _, chest in pairs(chests_to_remove) do
        if chest and chest.valid then
            if not (chest.destructible == false and chest.minable == false) then
                chest.destroy()
            end
        end
    end
end

-- 创建清理任务（分批处理）
function Public.create_cleanup_tasks(position, surface, baolei_id)
    local k = 30
    local area = {
        left_top = {position.x - k, position.y - k},
        right_bottom = {position.x + k, position.y + k}
    }
    
    -- 分批查找实体以避免一次性加载过多数据
    local entity_types = {"unit", "tree", "simple-entity", "cliff", "land-mine", "cargo-wagon", "fluid-wagon", "chest"}
    for _, entity_type in pairs(entity_types) do
        local entities_to_remove = surface.find_entities_filtered({
            type = entity_type,
            area = area
        })
        
        -- 将清理工作分批处理
        local batch_size = 20  -- 每批处理20个实体
        for i = 1, #entities_to_remove, batch_size do
            local batch = {}
            for j = i, math.min(i + batch_size - 1, #entities_to_remove) do
                batch[#batch + 1] = entities_to_remove[j]
            end
            
            Public.add_batch_task({
                type = "cleanup_entities",
                baolei_id = baolei_id,
                func = function(batch_entities)
                    for _, e in pairs(batch_entities) do
                        if e and e.valid then
                            if e.name == "land-mine" then
                                if e.force and e.force.name == "player" then
                                    e.destroy()
                                end
                            else
                                e.destroy()
                            end
                        end
                    end
                end,
                params = {batch}
            })
        end
    end
end

-- 创建地形设置任务（分批处理）
function Public.create_terrain_tasks(position, surface, baolei_id)
    local dis = 44
    local positions_to_set = {}
    
    -- 收集所有需要设置的地形位置
    for a = 1, dis do
        for b = 1, dis do
            positions_to_set[#positions_to_set + 1] = {
                name = "sand-1",
                position = {position.x - dis * 0.5 + a, position.y - dis * 0.5 + b}
            }
        end
    end
    
    -- 分批设置地形
    local batch_size = 50  -- 每批设置50个地块
    for i = 1, #positions_to_set, batch_size do
        local batch = {}
        for j = i, math.min(i + batch_size - 1, #positions_to_set) do
            batch[#batch + 1] = positions_to_set[j]
        end
        
        Public.add_batch_task({
            type = "set_terrain",
            baolei_id = baolei_id,
            func = function(terrain_batch)
                surface.set_tiles(terrain_batch)
            end,
            params = {batch}
        })
    end
end

-- 创建核心建筑任务
function Public.create_core_building_tasks(position, surface, robot_number, fix_number, something, baolei_id)
    Public.add_batch_task({
        type = "create_roboport",
        baolei_id = baolei_id,
        func = function()
            local roboport = surface.create_entity({
                name = "roboport",
                position = position,
                force = "enemy"
            })
            
            if roboport and roboport.valid then
                if construction_queue.active_constructions and construction_queue.active_constructions[baolei_id] then
                    construction_queue.active_constructions[baolei_id].roboport = roboport
                    construction_queue.active_constructions[baolei_id].all_thing[#construction_queue.active_constructions[baolei_id].all_thing + 1] = roboport
                    arty_count.roboport_wave[roboport.unit_number] = construction_queue.active_constructions[baolei_id].wave_number
                end
                if arty_count.arty and arty_count.arty[baolei_id] then
                    arty_count.arty[baolei_id].roboport = roboport
                    arty_count.arty[baolei_id].baolei_id = baolei_id
                end

                -- 不再向机器人平台塞维修包和建设机器人
                -- 原价值已折算到 baolei() 的 fix_worth，转移到黄箱战利品
                roboport.destructible = false

                arty_count.laser[#arty_count.laser + 1] = roboport
            end
        end,
        params = {}
    })
    
    Public.add_batch_task({
        type = "create_chest_and_inserter",
        baolei_id = baolei_id,
        func = function()
            if not construction_queue.active_constructions or not construction_queue.active_constructions[baolei_id] then
                return
            end
            local construction = construction_queue.active_constructions[baolei_id]
            local position = construction.position
            local surface = construction.surface
            local something = construction.something
            
            local chest = surface.create_entity({
                name = "storage-chest",
                position = { x = position.x, y = position.y - 3 },
                force = "enemy"
            })
            
            local inserter = surface.create_entity({
                name = "bulk-inserter",
                position = { x = position.x, y = position.y - 2 },
                force = "enemy"
            })
            
            if chest and chest.valid then
                chest.destructible = false
                construction.all_thing[#construction.all_thing + 1] = chest

                -- 记录黄箱引用到堡垒数据，供 on_entity_died 时重建炮塔使用
                if arty_count.arty and arty_count.arty[baolei_id] then
                    arty_count.arty[baolei_id].chest = chest
                end

                if something ~= nil then
                    for _, v in pairs(something) do
                        if v.number ~= 0 then
                            chest.insert({ name = v.name, count = v.number })
                        end
                    end
                end
            end
            
            if inserter and inserter.valid then
                inserter.destructible = false
                construction.all_thing[#construction.all_thing + 1] = inserter
                arty_count.all[#arty_count.all + 1] = inserter
                arty_count.laser[#arty_count.laser + 1] = inserter
            end
        end,
        params = {}
    })
end

-- 创建内层墙壁任务（分批处理）
function Public.create_inner_wall_tasks(position, surface, baolei_id)
    local wall_batches = {}
    
    -- 收集所有内层墙壁位置
    local wall_positions = {}
    
    -- 上侧墙壁 (14个)
    for i = 1, 14 do
        wall_positions[#wall_positions + 1] = { position.x - 19 + i, position.y - 18 }
    end
    
    -- 右上侧墙壁 (18个)
    for i = 1, 18 do
        wall_positions[#wall_positions + 1] = { position.x + i, position.y - 18 }
    end
    
    -- 下侧墙壁 (36个)
    for i = 1, 36 do
        wall_positions[#wall_positions + 1] = { position.x - 18 + i, position.y + 18 }
    end
    
    -- 左侧墙壁 (36个)
    for i = 1, 36 do
        wall_positions[#wall_positions + 1] = { position.x - 18, position.y - 18 + i }
    end
    
    -- 右侧墙壁 (36个)
    for i = 1, 36 do
        wall_positions[#wall_positions + 1] = { position.x + 18, position.y - 18 + i }
    end
    
    -- 分批创建墙壁
    local batch_size = 10  -- 每批创建10个墙壁
    for i = 1, #wall_positions, batch_size do
        local batch = {}
        for j = i, math.min(i + batch_size - 1, #wall_positions) do
            batch[#batch + 1] = wall_positions[j]
        end
        
        Public.add_batch_task({
            type = "create_inner_walls",
            baolei_id = baolei_id,
            func = function(wall_batch)
                if not construction_queue.active_constructions or not construction_queue.active_constructions[baolei_id] then
                    return
                end
                local construction = construction_queue.active_constructions[baolei_id]
                local surface = construction.surface
                
                for _, wall_pos in pairs(wall_batch) do
                    if surface.can_place_entity({
                        name = "stone-wall",
                        position = wall_pos,
                        force = game.forces.neutral
                    }) then
                        local e = surface.create_entity({
                            name = "stone-wall",
                            position = wall_pos,
                            force = game.forces.neutral
                        })
                        if e and e.valid then
                            construction.all_thing[#construction.all_thing + 1] = e
                            -- 只有需要击败的单位才注册到arty_count.unit表
                            if e.name ~= "stone-wall" then
                                arty_count.unit[e.unit_number] = baolei_id
                            end
                        end
                    end
                end
            end,
            params = {batch}
        })
    end
end

-- 创建炮台任务（根据价值点系统）
function Public.create_turret_tasks(position, surface, wave_number, baolei_id)
    local this = WPT.get()

    local all_worth = wave_number  * 0.84
    local fix_function = wave_number - 500
    if fix_function < 0 then fix_function = 0 end
    if fix_function > 1000 then fix_function = 1000 end
    
    local fix_worth = 0
    if all_worth <= 20 then all_worth = 20 end
    if all_worth >= 1200 then
        fix_worth = all_worth - 1200
        all_worth = 1000
    end
    
    local can_build_turret = {}
    for i, building in pairs(enemy_turret) do
        if wave_number >= building.wave_number then
            if this.world_number ~= 8 then
                can_build_turret[#can_build_turret + 1] = building
            else
                if not building.ban then
                    can_build_turret[#can_build_turret + 1] = building
                end
            end
        end
    end

    local something = {
        [1] = { name = 'laser-turret', worth = 10, wave_number = 150, index = 4, number = 0 },
        [2] = { name = 'gun-turret', worth = 5, wave_number = 100, index = 5, number = 0 },
        [3] = { name = 'flamethrower-turret', worth = 10, wave_number = 250, index = 6, number = 0 },
        [4] = { name = 'land-mine', worth = 1, wave_number = 100, index = 1, number = 0 }
    }

    if wave_number >= 1200 then
        something[5] = {
            name = 'artillery-turret',
            worth = 100,
            wave_number = 1200,
            index = 7,
            number = 0
        }
    end

    -- 价值平衡算法：跟踪每种类型累计价值，候选 = 累计价值 ≤ 最小值 + 阈值
    -- 阈值取池中最大单次价值，保证单次选择不会让某类型领先超过一轮
    -- 防止高价值建筑（如 artillery）独大、低价值建筑堆爆
    local type_values = {}
    for _, b in pairs(can_build_turret) do
        type_values[b.name] = 0
    end
    local threshold = 0
    for _, b in pairs(can_build_turret) do
        if b.worth > threshold then
            threshold = b.worth
        end
    end

    -- 根据价值点分配炮台数量
    while all_worth > 0 do
        -- 找最小累计价值
        local min_val = nil
        for _, b in pairs(can_build_turret) do
            if min_val == nil or type_values[b.name] < min_val then
                min_val = type_values[b.name]
            end
        end
        -- 候选 = 累计价值 ≤ min + threshold 的类型
        local eligible = {}
        for _, b in pairs(can_build_turret) do
            if type_values[b.name] <= min_val + threshold then
                eligible[#eligible + 1] = b
            end
        end
        if #eligible == 0 then
            eligible = can_build_turret
        end

        local turret_data = eligible[math.random(1, #eligible)]
        local turret_name = turret_data.name
        local worth = turret_data.worth

        Public.add_batch_task({
            type = "create_single_turret",
            baolei_id = baolei_id,
            func = function()
                if not construction_queue.active_constructions or not construction_queue.active_constructions[baolei_id] then
                    return
                end
                local construction = construction_queue.active_constructions[baolei_id]
                local position = construction.position
                local surface = construction.surface

                -- 获取随机品质（随波数递增，参考波防系统）
                local quality = select_quality_by_chance(wave_number)

                local turret_pos = {
                    x = position.x + math.random(-18, 18),
                    y = position.y + math.random(-18, 18)
                }


                    local e = surface.create_entity({
                        name = turret_name,
                        position = turret_pos,
                        force = game.forces.enemy,
                        quality = quality,
                        direction = math.random(0, 3)*4
                    })

                    -- if turret_name == 'flamethrower-turret' then
                    --     e.direction = math.random(1, 7)
                    -- end

                    if e and e.valid then
                        construction.all_thing[#construction.all_thing + 1] = e

                        if e.name == 'gun-turret' then
                            arty_count.gun[#arty_count.gun + 1] = e
                        end
                        if e.name == 'laser-turret' then
                            arty_count.laser[#arty_count.laser + 1] = e
                        end
                        if e.name == 'flamethrower-turret' then
                            arty_count.flame[#arty_count.flame + 1] = e
                        end
                        if e.name == 'artillery-turret' then
                            arty_count.all[#arty_count.all + 1] = e
                            arty_count.fire[#arty_count.fire + 1] = 0
                            arty_count.count = arty_count.count + 1
                        end
                        if e.name == 'tesla-turret' then
                            arty_count.tesla[#arty_count.tesla + 1] = e
                        end
                        if e.name == 'rocket-turret' then
                            arty_count.rocket[#arty_count.rocket + 1] = e
                        end

                        -- 只有需要击败的单位才注册到arty_count.unit表并增加计数
                        if e.name ~= "stone-wall" then
                            arty_count.unit[e.unit_number] = baolei_id
                            arty_count.arty[baolei_id].number = arty_count.arty[baolei_id].number + 1
                        end
                    end

            end,
            params = {}
        })

        type_values[turret_name] = type_values[turret_name] + worth
        all_worth = all_worth - worth
    end
    
    -- 处理修复包价值点
    while fix_worth > 0 do
        local index = math.random(1, #something)
        local worth = something[index].worth
        fix_worth = fix_worth - worth
        something[index].number = something[index].number + 1
    end
end

-- 创建外层墙壁任务（分批处理）
function Public.create_outer_wall_tasks(position, surface, baolei_id)
    local wall_positions = {}
    
    -- 上侧外层墙壁 (18个)
    for i = 1, 18 do
        wall_positions[#wall_positions + 1] = { position.x - 24 + i, position.y - 23 }
    end
    
    -- 右上侧外层墙壁 (23个)
    for i = 1, 23 do
        wall_positions[#wall_positions + 1] = { position.x + i, position.y - 23 }
    end
    
    -- 下侧外层墙壁 (46个)
    for i = 1, 46 do
        wall_positions[#wall_positions + 1] = { position.x - 23 + i, position.y + 23 }
    end
    
    -- 左侧外层墙壁 (46个)
    for i = 1, 46 do
        wall_positions[#wall_positions + 1] = { position.x - 23, position.y - 23 + i }
    end
    
    -- 右侧外层墙壁 (46个)
    for i = 1, 46 do
        wall_positions[#wall_positions + 1] = { position.x + 23, position.y - 23 + i }
    end
    
    -- 分批创建外层墙壁
    local batch_size = 8  -- 每批创建8个外层墙壁（因为外层墙壁更多）
    for i = 1, #wall_positions, batch_size do
        local batch = {}
        for j = i, math.min(i + batch_size - 1, #wall_positions) do
            batch[#batch + 1] = wall_positions[j]
        end
        
        Public.add_batch_task({
            type = "create_outer_walls",
            baolei_id = baolei_id,
            func = function(wall_batch)
                if not construction_queue.active_constructions or not construction_queue.active_constructions[baolei_id] then
                    return
                end
                local construction = construction_queue.active_constructions[baolei_id]
                local surface = construction.surface
                
                for _, wall_pos in pairs(wall_batch) do
                    if surface.can_place_entity({
                        name = "stone-wall",
                        position = wall_pos,
                        force = game.forces.neutral
                    }) then
                        local e = surface.create_entity({
                            name = "stone-wall",
                            position = wall_pos,
                            force = game.forces.neutral
                        })
                        if e and e.valid then
                            construction.all_thing[#construction.all_thing + 1] = e
                           
                            
                            -- 只有需要击败的单位才注册到arty_count.unit表
                            if e.name ~= "stone-wall" then
                                arty_count.unit[e.unit_number] = baolei_id
                            end
                        end
                    end
                end
            end,
            params = {batch}
        })
    end
end

-- 销毁堡垒的所有墙
local function kill_wall(baolei_id)
    if arty_count.neet_to_kill[baolei_id] then
        for i, v in pairs(arty_count.neet_to_kill[baolei_id]) do
            if v and v.valid and v.name ~= '' and v.name ~= 'roboport' then
                v.destructible = true
                v.die()
            end
        end
    end
end

local function check_roboport_destructible()
    if not arty_count.arty then
        return
    end
    
    local turret_types = {
        "gun-turret",
        "laser-turret", 
        "flamethrower-turret",
        "artillery-turret",
        "small-worm-turret",
        "medium-worm-turret",
        "big-worm-turret",
        "behemoth-worm-turret"
    }
    
    for baolei_id, baolei_data in pairs(arty_count.arty) do
        if baolei_data and baolei_data.roboport and baolei_data.roboport.valid then
            if not baolei_data.roboport.destructible then
                local actual_turret_count = 0
                
                if arty_count.neet_to_kill[baolei_id] then
                    for _, entity in pairs(arty_count.neet_to_kill[baolei_id]) do
                        if entity and entity.valid then
                            for _, turret_name in ipairs(turret_types) do
                                if entity.name == turret_name then
                                    actual_turret_count = actual_turret_count + 1
                                    break
                                end
                            end
                        end
                    end
                end
                
                if actual_turret_count == 0 then
                    baolei_data.roboport.destructible = true
                    baolei_data.number = 0
                    kill_wall(baolei_id)
                end
            end
        end
    end
end
-- 检测堡垒有效性并重新统计堡垒数量
function Public.recount_baolei()
    local this = WPT.get()
    local valid_count = 0
    
    -- 遍历所有堡垒，只检查机器人平台是否有效
    if arty_count.arty then
        for baolei_id, baolei_data in pairs(arty_count.arty) do
            local baolei_valid = false
            
            -- 只检查堡垒对应的机器人平台是否有效
            if baolei_data and baolei_data.roboport and baolei_data.roboport.valid then
                baolei_valid = true
            end
            
            -- 如果机器人平台有效，则计数
            if baolei_valid then
                valid_count = valid_count + 1
            else
                -- 清理无效的堡垒记录
                arty_count.arty[baolei_id] = nil
                if arty_count.neet_to_kill then
                    arty_count.neet_to_kill[baolei_id] = nil
                end
                if arty_count.baolei_creation_times then
                    arty_count.baolei_creation_times[baolei_id] = nil
                end
                if construction_queue.active_constructions then
                    construction_queue.active_constructions[baolei_id] = nil
                end
            end
        end
    end
    
    -- 更新堡垒数量
    this.baolei_count = valid_count
    
    return valid_count
end
-- 返回所有存活堡垒（机器人平台有效）的位置列表
-- 供 World 框架 biter_spawn_rule.from_fortress 出生规则查询（main.lua get_biter_point）
function Public.get_valid_fortress_positions()
    local positions = {}
    if arty_count.arty then
        for _, baolei_data in pairs(arty_count.arty) do
            if baolei_data and baolei_data.roboport and baolei_data.roboport.valid then
                positions[#positions + 1] = baolei_data.roboport.position
            end
        end
    end
    return positions
end

-- 完成堡垒创建的收尾工作
function Public.finish_baolei_construction(baolei_id)
    if not construction_queue.active_constructions then
        return
    end
    local construction = construction_queue.active_constructions[baolei_id]
    if construction and construction.all_thing then
        arty_count.neet_to_kill[baolei_id] = construction.all_thing
        
        -- 增加堡垒计数（静态堡垒不计入 dynamic_count，世界7/13用）
        local this = WPT.get()
        if not construction.skip_count then
            this.baolei_count = this.baolei_count + 1
        end
        
        -- 先清理arty_count.attack_table中无效的物体
        for i = #arty_count.attack_table, 1, -1 do
            local e = arty_count.attack_table[i]
            if not e or not e.valid then
                table.remove(arty_count.attack_table, i)
            end
        end

        -- 检测重炮目标
        local function check_artillery_targets()
            for _, artillery in pairs(arty_count.all) do
                if artillery and artillery.valid then
                    local artillery_pos = artillery.position
                    for _, entity_name in pairs(artillery_target_entities) do
                        for _, target_entity in pairs(construction.surface.find_entities_filtered({
                            name = entity_name,
                            position = artillery_pos,
                            radius = arty_count.radius,
                            force = game.forces.player
                        })) do
                            if target_entity and target_entity.valid then
                                -- 如果不在攻击表中，则添加
                                local already_exists = false
                                    for _, existing in pairs(arty_count.can_attack_table) do
                                        if existing == target_entity then
                                            already_exists = true
                                            break
                                        end
                                    end
                                    if not already_exists then
                                        arty_count.can_attack_table[#arty_count.can_attack_table + 1] = target_entity
                                    end
                            end
                        end
                    end
                end
            end
        end
        
        -- 如果有重炮，则检测目标
        if #arty_count.all > 0 then
            check_artillery_targets()
        end

        -- 添加地雷
        local mind_number = construction.wave_number * 0.01
        for i = 1, 14 + mind_number do
            construction.surface.create_entity({
                name = "land-mine",
                position = {
                    x = construction.position.x + math.random(-18, 18) * 1.5,
                    y = construction.position.y + math.random(-18, 18) * 1.5
                },
                force = game.forces.enemy
            })
        end

        -- 生成宝箱
        local many_baozhang = math.floor(construction.wave_number * 0.008)
        if many_baozhang > 10 then many_baozhang = 10 end
        
        local max_luck = construction.wave_number * 0.2 + 100
        local min_luck = construction.wave_number * 0.1 + 50
        if max_luck >= 800 then max_luck = 800 end
        if min_luck >= 500 then min_luck = 500 end

        for i = 1, many_baozhang do
            local magic = math.random(min_luck, max_luck)
            local chest_position = construction.surface.find_non_colliding_position("steel-chest", construction.position, 20, 1, true)
             
            -- 只有找到有效位置才创建宝箱
            if chest_position then
                local container
                -- 15%的概率生成品质宝箱
                if math.random(1, 100) <= 15 then
                    container = Loot.cool_with_quality(construction.surface, chest_position, 'steel-chest', magic)
                else
                    container = Loot.cool(construction.surface, chest_position, 'steel-chest', magic)
                end
                -- 设置宝箱不可摧毁
                if container and container.valid then
                    container.destructible = false
                end
            end
        end

        -- 在世界10和世界11时添加"曹营"文字标签
        if this.world_number == 10  and construction.roboport and construction.roboport.valid then
            rendering.draw_text({ 
                text = "曹营", 
                surface = construction.surface, 
                target = { 
                    entity = construction.roboport, 
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
            })
        end
    end
    
    -- 清理已完成的建设任务
    construction_queue.active_constructions[baolei_id] = nil
end

local function urgrade_ammo(wave_number)
    if wave_number > 500 and arty_count.ammo_index == 1 then
        arty_count.ammo_index = 2
    end

    if wave_number > 800 and arty_count.ammo_index == 2 then
        arty_count.ammo_index = 3
    end
end

function Public.baolei(position, wave_number, surface, cleanup_terrain, skip_count)
    if cleanup_terrain == nil then
        cleanup_terrain = true
    end
    if skip_count == nil then
        skip_count = false
    end
    local this = WPT.get()
    game.print({'amap.biter_build' .. (this.world_number == 10 and '_world10' or ''), position.x, position.y, surface.name})
    urgrade_ammo(wave_number)

    local all_worth = wave_number  * 0.84
    local fix_function = wave_number - 500
    if fix_function < 0 then
        fix_function = 0
    end
    if fix_function > 1000 then
        fix_function = 1000
    end
    local robot_number = 1 + math.floor(fix_function * 0.28)
    local fix_number = 1 + math.floor(fix_function * 0.56)
    local out_wall = false
    if wave_number >= 500 then
        out_wall = true
    end

    local fix_worth = 0
    if all_worth <= 20 then
        all_worth = 20
    end
    if all_worth >= 1200 then
        fix_worth = all_worth - 1200
        all_worth = 1000
    end

    -- 取消机器人平台维修包/建设机器人后，将这部分价值折算成 fix_worth
    -- 转移到黄箱战利品（something 表），由玩家获取
    -- 维修包单价 5（类似 gun-turret worth），建设机器人单价 10（类似 laser-turret worth）
    -- 折算系数 0.5：保留部分价值作为战利品补偿，避免直接等额转移导致黄箱爆满
    fix_worth = fix_worth + math.floor((fix_number * 0.5 + robot_number * 1) * 0.5)

    local baolei_id = #arty_count.arty + 1
    arty_count.arty[baolei_id] = {}
    arty_count.arty[baolei_id].number = 0
    arty_count.arty[baolei_id].roboport = nil
    arty_count.arty[baolei_id].skip_count = skip_count

    local something = {
        [1] = {
            name = 'laser-turret',
            worth = 10,
            wave_number = 100,
            index = 4,
            number = 0
        },
        [2] = {
            name = 'gun-turret',
            worth = 5,
            wave_number = 100,
            index = 5,
            number = 0
        },
        [3] = {
            name = 'flamethrower-turret',
            worth = 10,
            wave_number = 150,
            index = 6,
            number = 0
        },
        [4] = {
            name = 'land-mine',
            worth = 1,
            wave_number = 100,
            index = 1,
            number = 0
        }
    }

    if wave_number >= 600 then
        something[#something + 1] = {
            name = 'tesla-turret',
            worth = 15,
            wave_number = 600,
            index = 10,
            number = 0
        }
    end
    if wave_number >= 900 then
        something[#something + 1] = {
            name = 'rocket-turret',
            worth = 25,
            wave_number = 900,
            index = 11,
            number = 0
        }
    end
    if wave_number >= 1300 then
        something[#something + 1] = {
            name = 'artillery-turret',
            worth = 100,
            wave_number = 1300,
            index = 9,
            number = 0
        }
    end

    while fix_worth > 0 do
        local index = math.random(1, #something)
        local worth = something[index].worth
        fix_worth = fix_worth - worth
        something[index].number = something[index].number + 1
    end

    Public.start_baolei_construction(position, wave_number, surface, robot_number, fix_number, out_wall, something, baolei_id, cleanup_terrain, skip_count)
    
    -- 记录堡垒创建时间
    if not arty_count.baolei_creation_times then
        arty_count.baolei_creation_times = {}
    end
    arty_count.baolei_creation_times[baolei_id] = game.tick

    if wave_number >= 2000  then
        -- 获取随机品质（随波数递增，参考波防系统）
        local quality = select_quality_by_chance(wave_number)
        
        local e = surface.create_entity({
            name = 'artillery-turret',
            position = {
                x = position.x,
                y = position.y
            },
            force = game.forces.enemy,
            direction = math.random(0, 3)*4,
            quality = quality
        })
        arty_count.all[#arty_count.all + 1] = e
        arty_count.fire[#arty_count.fire + 1] = 0
        arty_count.count = arty_count.count + 1
        
        -- 将重炮添加到 all_thing 表中，以便秒杀时能正确销毁
        if construction_queue.active_constructions and construction_queue.active_constructions[baolei_id] then
            construction_queue.active_constructions[baolei_id].all_thing[#construction_queue.active_constructions[baolei_id].all_thing + 1] = e
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

-- 世界16「平凡之日」：fixed_wave 模式下堡垒生成的硬性间隔下限
-- 至少每 30 分钟（60*60*30 tick）生成一座；100 波那次生成也计入这个间隔（共用同一时钟）
local FIXED_WAVE_MIN_INTERVAL_TICKS = 60 * 60 * 30

-- World 框架：fixed_wave 模式（arty_settings.mode == 'fixed_wave'，世界16「平凡之日」等使用）
-- 1) initial_spawn：开局在出生点(0,0)外 min_distance 米随机点生成一个堡垒（强度 wave_strength 波）
-- 2) 之后：每 interval_waves 波（默认100）生成一个堡垒；同时硬性保证至少每 30 分钟一座。
--    二者共用同一个 30 分钟间隔时钟（fixed_wave_last_baolei_tick），任一种方式生成都会重置它，
--    即「100 波那次生成也算到间隔里」，不会在 100 波与 30 分钟兜底之间重复生成。
local function handle_fixed_wave_mode(this, arty_settings)
    local surface = this.active_surface_index and game.surfaces[this.active_surface_index]
    if not surface or not surface.valid then
        return
    end

    -- 开局堡垒：只生成一次（fixed_wave_initial_done 随每局在 table.lua 重置）
    local init_cfg = arty_settings.initial_spawn
    if init_cfg and not this.fixed_wave_initial_done then
        local min_distance = init_cfg.min_distance or 150
        local strength = init_cfg.wave_strength or 100
        -- 随机化螺旋搜索起始角度 → 满足「随机取一个点」
        this.theta_times = math.random(0, 15)
        -- 复用堡垒选点算法：以出生点(0,0)为圆心、min_distance 为初始半径螺旋搜索无冲突点
        local position = get_baolei_pos({x = 0, y = 0}, min_distance, surface, nil, false)
        if position then
            -- 开局远处区块可能尚未生成：先同步生成目标点周边区块，确保建筑落地
            surface.request_to_generate_chunks(position, 3)
            surface.force_generate_chunk_requests()
            Public.baolei(position, strength, surface)
            this.fixed_wave_initial_done = true
            this.fixed_wave_last_baolei_wave = 0
            this.fixed_wave_last_baolei_tick = game.tick   -- 30 分钟间隔计时起点
        end
        return
    end

    -- 硬性间隔下限：距上次生成未满 30 分钟则不生成（100 波若在 30 分钟内也不生成）
    local since_last = game.tick - (this.fixed_wave_last_baolei_tick or 0)
    if since_last < FIXED_WAVE_MIN_INTERVAL_TICKS then
        return
    end

    -- 满 30 分钟：判断是否踩中 100 波边界（按波数节点去重，读档/慢波安全）
    local interval_waves = arty_settings.interval_waves or 100
    local wave_number = WD.get('wave_number') or 0
    local wave_boundary = false
    if wave_number >= 100 then
        local due = math.floor(wave_number / interval_waves) * interval_waves
        if due > (this.fixed_wave_last_baolei_wave or 0) then
            wave_boundary = true
        end
    end

    -- 满 30 分钟就生成一座（保证最少每 30 分钟一座）；
    -- 100 波边界触发时同样生成并重置间隔时钟 →「100 波生成也算到间隔里」
    local wave_defense_table = WD.get_table()
    local target = wave_defense_table.target
    if not target or not target.valid then
        return
    end
    local position = get_baolei_pos(target.position, 120, surface, target, false)
    if position then
        -- 堡垒强度下限：与开局堡垒同档（默认 100 波）
        -- enemy_turret 表最低门槛就是 gun-turret 的 100 波，若用 <100 的真实波数生成，
        -- create_turret_tasks 里可选炮台列表会是空表 → math.random(1, 0) 崩溃
        local strength = math.max(wave_number, (init_cfg and init_cfg.wave_strength) or 100)
        Public.baolei(position, strength, surface)
        this.fixed_wave_last_baolei_tick = game.tick   -- 重置 30 分钟间隔（含 100 波那次）
        if wave_boundary then
            local due = math.floor(wave_number / interval_waves) * interval_waves
            this.fixed_wave_last_baolei_wave = due
        end
    end
end

local function get_new_arty()
    -- 增加检查次数计数器
    arty_count.arty_check_count = arty_count.arty_check_count + 1

    local this = WPT.get()

    -- World 框架：查询 arty_settings（所有世界均已注册）
    local arty_settings = World.get_field(this.world_number, 'arty_settings') or {}

    -- fixed_wave 模式：按固定波数生成堡垒（含开局堡垒），与默认「按时间间隔」调度互斥
    if arty_settings.mode == 'fixed_wave' then
        handle_fixed_wave_mode(this, arty_settings)
        return
    end

    -- 判断是否为 silo 世界（mode == 'silo_3_points'）
    local is_silo_world = (arty_settings.mode == 'silo_3_points')

    -- 根据世界类型决定基础生成间隔（silo 世界均已明示 interval = 35）
    local base_interval = arty_settings.interval or 20
    
    -- 根据玩家数量和堡垒数量调整生成间隔
    local player_count = calc_players()
    local generate_interval = base_interval
    
    -- 应用加速奖励（如果上一个堡垒在3分钟内被摧毁）
    if arty_count.next_baolei_speed_bonus > 0 then
        generate_interval = generate_interval - arty_count.next_baolei_speed_bonus
        arty_count.next_baolei_speed_bonus = 0  -- 重置奖励
    end
    
    if this.baolei_count <= 0 then
        generate_interval = generate_interval - 5
    else
        if player_count == 1 then
            generate_interval = generate_interval + 5
        elseif player_count >= 3 then
            local extra_players = player_count - 1
            local speed_up = math.floor(extra_players / 2)
            generate_interval = generate_interval + 5 - speed_up
        end
    end
    
    if generate_interval < 5 then
        generate_interval = 5
    end
    
    if arty_count.arty_check_count < generate_interval then
        return
    end
    
    arty_count.arty_check_count = 0

    local wave_number = WD.get('wave_number')
    local start_nuamber = 250
    --如果没有火箭发射井，但是标签存在，则移除标签
    if not this.baolei_silo or not this.baolei_silo.valid then
         if this.silo_tag  then
        this.silo_tag.destroy()
        this.silo_tag = nil
    end

    end

    if is_silo_world then
        start_nuamber = arty_settings.start_wave or 250
        if not this.baolei_silo or not this.baolei_silo.valid then
            this.baolei_silo = nil
        end
    end
    if wave_number < start_nuamber then
        return
    end
    if is_silo_world and this.baolei_count > 1 then
        if this.baolei_silo and this.baolei_silo.valid then
            game.print({'amap.rocket_silo_nuke_warning'}, {255, 0, 0})

            for abcd = 1, 10 do
                Task.set_timeout_in_ticks(60 * 60 * 3 * abcd, shot_hd, this.baolei_silo)
            end
            return
        end
    end

    local wave_defense_table = WD.get_table()
    if not wave_defense_table.target then
        return
    end
    if not wave_defense_table.target.valid then
        return
    end
    local target = wave_defense_table.target
    local surface = target.surface

    local temp_pos
    local position
    if is_silo_world then
        temp_pos = target.position
        if this.baolei_y ~= 0 then
            temp_pos.y = this.baolei_y
        end
        local juli = 65
        local entities = surface.count_entities_filtered {
            position = temp_pos,
            radius = juli,
            name = player_build,
            force = game.forces.player,
            limit = 1
        }
        while entities ~= 0 do
            temp_pos = {
                x = 0,
                y = temp_pos.y - 115
            }
            entities = surface.count_entities_filtered {
                position = temp_pos,
                radius = juli,
                name = player_build,
                force = game.forces.player,
                limit = 1
            }
        end

        this.baolei_y = temp_pos.y
        position = wave_defense_table.spawn_position
    elseif arty_settings.mode == 'custom_4way' then
        -- 世界15：四个通道远端各生成一个堡垒，轮流放置
        local channel_ends = {
            {0, -500},   -- 下
            {500, 0},    -- 右
            {0, 500},    -- 上
            {-500, 0},   -- 左
        }
        if not this.world15_fortress_index then
            this.world15_fortress_index = 0
        end
        this.world15_fortress_index = (this.world15_fortress_index % 4) + 1
        local dir_pos = channel_ends[this.world15_fortress_index]
        local target_pos = target.position
        position = {
            x = target_pos.x + dir_pos[1],
            y = target_pos.y + dir_pos[2]
        }
    else
        -- World 框架：mode == 'only_below' 决定堡垒只生成在下方半圈
        local only_below = (arty_settings.mode == 'only_below')
        position = get_baolei_pos(target.position, 120, surface, target,only_below)

    end
    -- World 框架：boundary_limit 超出时堡垒位置重置为 spawn_position
    local boundary_limit = arty_settings.boundary_limit
    if boundary_limit ~= nil and (math.abs(position.x) >= boundary_limit or math.abs(position.y) >= boundary_limit) then
        position = wave_defense_table.spawn_position
    end
    if position == nil then
        return
    end
    -- 排除 silo 世界和世界 13（由专属逻辑生成堡垒）
    if not is_silo_world and this.world_number ~= 13 then
        Public.baolei(position, wave_number, surface)
    end

    if is_silo_world then
           Public.recount_baolei()
        if this.baolei_count > 1 then
            this.baolei_silo = surface.create_entity({
                name = "rocket-silo",
                position = {
                    x = 0,
                    y = this.baolei_y - 50
                },
                force = "enemy"
            })

                        this.silo_tag=game.forces.player.add_chart_tag(surface, {
        position =  this.baolei_silo.position,
        icon = { type = "entity", name = "rocket-silo" },
        text = '敌方核弹发射井',
    })
            this.baolei_silo.destructible = false
            game.print({'amap.biter_build_hd', 0, this.baolei_y - 50, surface.name}, {255, 0, 0})
            game.print({'amap.must_destroy_strongholds'}, {255, 0, 0})
            return
        else
            Public.baolei({
                x = -65,
                y = this.baolei_y
            }, wave_number, surface)
            Public.baolei({
                x = 65,
                y = this.baolei_y
            }, wave_number, surface)
            Public.baolei({
                x = 0,
                y = this.baolei_y
            }, wave_number, surface)
        end

    end

end

local artillery_target_callback = Token.register(function(data)
    local position = data.position
    local entity = data.entity

    if not entity.valid then
        return
    end

    local tx, ty = position.x, position.y
    local pos = entity.position
    local x, y = pos.x, pos.y
    local dx, dy = tx - x, ty - y
    local d = dx * dx + dy * dy
    if d <= arty_count.radius*arty_count.radius then
        local use_rocket = false
        
        if entity.name == 'spidertron' then
            use_rocket = true
        elseif entity.type == 'character' then
            local player = entity.player
            if player and player.valid then
                local armor_inv = player.get_inventory(defines.inventory.character_armor)
                if armor_inv and armor_inv[1] and armor_inv[1].valid_for_read then
                    local armor_name = armor_inv[1].name
                    if armor_name == 'mech-armor' then
                        use_rocket = true
                    end
                end
            end
        end
        
        if use_rocket then
            entity.surface.create_entity({
                name = 'rocket',
                position = position,
                target = entity,
                force = 'enemy',
                speed = arty_count.pace
            })
        else
            entity.surface.create_entity({
                name = 'artillery-projectile',
                position = position,
                target = entity,
                force = 'enemy',
                speed = arty_count.pace
            })
        end
    end
end)

local remove_steel_chests_callback = Token.register(function(data)
    local position = data.position
    local surface = data.surface
    local k = 8
    local area_1 = {
        left_top = {position.x - k, position.y - k},
        right_bottom = {position.x + k, position.y + k}
    }
    for _, e in pairs(surface.find_entities_filtered({
        name = {"steel-chest", "crash-site-chest-1", "crash-site-chest-2"},
        area = area_1
    })) do
        e.destroy()
    end
    for unit_number, _ in pairs(arty_count.roboport_wave) do
        arty_count.roboport_wave[unit_number] = 1
    end
end)

local function add_bullet()
    flame_bullet()
end
local function energy()
    energy_bullet()
end

local function do_artillery_turrets_targets()


    if arty_count.count <= 0 then
        return
    end
    
    -- 清理can_attack_table中的无效实体
    for i = #arty_count.can_attack_table, 1, -1 do
        local e = arty_count.can_attack_table[i]
        if not e or not e.valid then
            table.remove(arty_count.can_attack_table, i)
        end
    end
    
    if not arty_count.can_attack_table then
        arty_count.can_attack_table = {}
    end
    if not arty_count.attack_table then
        arty_count.attack_table = {}
    end


    arty_count.index = arty_count.index + 1
    if arty_count.index > arty_count.count then
        arty_count.index = 1
    end

    local index = arty_count.index
    local turret = arty_count.all[index]

    if not (turret and turret.valid) then
        fast_remove(arty_count.all, index)
        fast_remove(arty_count.fire, index)
        arty_count.count = arty_count.count - 1
        return
    end

    local now = game.tick
    if not arty_count.fire[index] then
        arty_count.fire[index] = 0
    end
    if (now - arty_count.fire[index]) < 360 then
        return
    end
    arty_count.fire[index] = now

    local position = arty_count.all[index].position

    local this = WPT.get()
    if not this.active_surface_index or not game.surfaces[this.active_surface_index] then return end

    -- Create a combined list of targets: online players + can_attack_table entities
    local entities = {}
    
    -- Add all online players
    local arty_surface = arty_count.all[index].surface
    for _, player in pairs(game.connected_players) do
        if player and player.valid and player.character and player.character.valid then
            if player.physical_surface ~= arty_surface then
                goto continue
            end
            local player_pos = player.character.position
            -- Check if player is within radius of the artillery (compare squares instead of sqrt)
            local distance_squared =
                (position.x - player_pos.x)^2 +
                (position.y - player_pos.y)^2
            if distance_squared <= arty_count.radius * arty_count.radius then
                entities[#entities + 1] = player.character
            end
            ::continue::
        end
    end
    
    -- Add entities from can_attack_table that are valid and within radius
    for _, target_entity in pairs(arty_count.can_attack_table) do
        if target_entity and target_entity.valid then
            local target_pos = target_entity.position
            local distance_squared = 
                (position.x - target_pos.x)^2 + 
                (position.y - target_pos.y)^2
            if distance_squared <= arty_count.radius * arty_count.radius then
                entities[#entities + 1] = target_entity
            end
        end
    end

    if #entities == 0 then
        return
    end


    local count = 1
    if arty_count.count > 4 then
        count = math.floor(arty_count.count * 0.5)
    else
        count = arty_count.count
    end
    

    -- 开火
    for i = 1, count do
        local entity = entities[math.random(#entities)]
        if entity and entity.valid then
            local data = {
                position = position,
                entity = entity
            }
            Task.set_timeout_in_ticks(i * 60, artillery_target_callback, data)
        end
    end
end

-- 可重建的炮塔类型（不含墙、地雷）
local REBUILDABLE_TURRETS = {
    ['gun-turret'] = true,
    ['laser-turret'] = true,
    ['flamethrower-turret'] = true,
    ['artillery-turret'] = true,
    ['tesla-turret'] = true,
    ['rocket-turret'] = true
}

-- 炮塔死亡后尝试从黄箱补给重建
-- 保留原建筑品质（dead_entity.quality），从堡垒黄箱扣 1 个同名物品，
-- 在堡垒中心附近找无碰撞点（半径 5）创建新建筑并注册回堡垒
local function try_rebuild_turret(dead_entity, baolei_id)
    if not dead_entity or not dead_entity.valid then
        log('[REBUILD] dead_entity invalid')
        return
    end
    local data = arty_count.arty[baolei_id]
    if not data then
        log('[REBUILD] no arty data baolei_id=' .. tostring(baolei_id) .. ' name=' .. tostring(dead_entity.name))
        return
    end
    local chest = data.chest
    if not chest or not chest.valid then
        log('[REBUILD] chest invalid baolei_id=' .. tostring(baolei_id) .. ' chest=' .. tostring(chest))
        return
    end
    local roboport = data.roboport
    if not roboport or not roboport.valid then
        log('[REBUILD] roboport invalid baolei_id=' .. tostring(baolei_id) .. ' roboport=' .. tostring(roboport))
        return
    end

    local item_name = dead_entity.name
    local inv = chest.get_inventory(defines.inventory.chest)
    if not inv then
        log('[REBUILD] chest inventory nil baolei_id=' .. tostring(baolei_id))
        return
    end
    local item_count = inv.get_item_count(item_name)
    if item_count <= 0 then
        log('[REBUILD] no item in chest baolei_id=' .. tostring(baolei_id) .. ' item=' .. tostring(item_name) .. ' count=' .. tostring(item_count))
        return
    end

    -- 保留原品质（Factorio 2.0 entity.quality 返回 quality 对象）
    local original_quality = dead_entity.quality

    local surface = roboport.surface
    -- 用户指定半径 5：仅在堡垒中心 5 格内找无碰撞点
    local pos = surface.find_non_colliding_position(item_name, roboport.position, 5, 1, true)
    if not pos then
        log('[REBUILD] no non-colliding pos baolei_id=' .. tostring(baolei_id) .. ' item=' .. tostring(item_name) .. ' center=(' .. roboport.position.x .. ',' .. roboport.position.y .. ')')
        return
    end

    inv.remove({ name = item_name, count = 1 })
    local create_params = {
        name = item_name,
        position = pos,
        force = game.forces.enemy,
        direction = math.random(0, 3) * 4
    }
    if original_quality then
        create_params.quality = original_quality
    end
    local new_e = surface.create_entity(create_params)
    if not new_e or not new_e.valid then
        log('[REBUILD] create_entity failed baolei_id=' .. tostring(baolei_id) .. ' item=' .. tostring(item_name) .. ' pos=(' .. pos.x .. ',' .. pos.y .. ')')
        return
    end
    log('[REBUILD] OK baolei_id=' .. tostring(baolei_id) .. ' item=' .. tostring(item_name) .. ' pos=(' .. pos.x .. ',' .. pos.y .. ')')

    -- 注册回堡垒
    arty_count.unit[new_e.unit_number] = baolei_id
    data.number = data.number + 1
    if arty_count.neet_to_kill[baolei_id] then
        arty_count.neet_to_kill[baolei_id][#arty_count.neet_to_kill[baolei_id] + 1] = new_e
    end
    -- 注册到对应炮台类型表（与 create_turret_tasks 一致）
    if new_e.name == 'gun-turret' then
        arty_count.gun[#arty_count.gun + 1] = new_e
    elseif new_e.name == 'laser-turret' then
        arty_count.laser[#arty_count.laser + 1] = new_e
    elseif new_e.name == 'flamethrower-turret' then
        arty_count.flame[#arty_count.flame + 1] = new_e
    elseif new_e.name == 'artillery-turret' then
        arty_count.all[#arty_count.all + 1] = new_e
        arty_count.fire[#arty_count.fire + 1] = 0
        arty_count.count = arty_count.count + 1
    elseif new_e.name == 'tesla-turret' then
        arty_count.tesla[#arty_count.tesla + 1] = new_e
    elseif new_e.name == 'rocket-turret' then
        arty_count.rocket[#arty_count.rocket + 1] = new_e
    end
end

local function on_entity_died(event)
    local entity = event.entity

    if not entity.valid or not entity then
        return
    end

    local surface = entity.surface

    if entity.name== 'nuclear-reactor' then

   

    local position = entity.position
    
    -- Factorio 一个区块是 32x32 格
    -- 计算中心点所在的区块坐标
    local chunk_x = math.floor(position.x / 32)
    local chunk_y = math.floor(position.y / 32)
    
    -- 为了防止反应堆正好压在区块边缘，建议覆盖反应堆可能接触到的周围区块
    -- 反应堆大小是 5x5。这里为了保险，我们处理中心区块以及相邻的区块
    -- 如果你想“狠一点”，可以扩大半径，比如 radius = 1 (3x3个区块)
    local radius = 1
    
    game.print({'amap.reactor_meltdown_warning'})

    -- 遍历需要重置的区块
    for x = chunk_x - radius, chunk_x + radius do
        for y = chunk_y - radius, chunk_y + radius do
            local current_chunk_pos = {x = x, y = y}
            
            -- 1. 删除区块：这将移除该区域内所有玩家建筑、地形修改、掉落物
            surface.delete_chunk(current_chunk_pos)
        end
    end

    -- 2. 请求重新生成：游戏会根据原始地图种子重新生成地形
    -- 这会将地形恢复为“出厂设置”（例如：原本是草地的地方变回草地，人工岩浆消失）
    surface.request_to_generate_chunks(position, radius)
    
    -- 强制立即执行生成请求（可选，防止出现黑色虚空等待加载）
    surface.force_generate_chunk_requests()

    -- 太空平台（space platform）上的核电站被摧毁时不生成堡垒
    -- 判据沿用项目规范：entity.surface.platform 为真即处于太空图层
    if not (entity.surface and entity.surface.platform) then
        local wave_number = WD.get('wave_number')
        if wave_number <= 500 then
            wave_number = 500
        end
        Public.baolei(position, wave_number, surface, false)
    end

    local remove_data = {
        position = position,
        surface = surface
    }
    Task.set_timeout_in_ticks(600, remove_steel_chests_callback, remove_data)

    
    end

    local force = event.entity.force
    if force ~= game.forces.enemy then
        return
    end
    local name = event.entity.name
    if arty_count.unit[entity.unit_number] then
        local unit_number = entity.unit_number
        local baolei_id = arty_count.unit[unit_number]

        -- 炮塔死亡时尝试从黄箱补给重建（保留原品质）
        -- 必须在 decrement 之前调用：若重建成功 number+1，紧接着 decrement-1，净变化 0
        -- 若先 decrement 导致 number=0 触发 roboport.destructible=true，会与重建矛盾
        if REBUILDABLE_TURRETS[name] then
            try_rebuild_turret(entity, baolei_id)
        end

        arty_count.arty[baolei_id].number = arty_count.arty[baolei_id].number - 1
        if arty_count.arty[baolei_id].number <= 0 then
            arty_count.arty[baolei_id].roboport.destructible = true
            kill_wall(baolei_id)
        end
        arty_count.unit[unit_number] = nil

    end

    if name ~= "roboport" then

        return
    end

    local position = entity.position
    local surface = entity.surface

    local k = 8
    local area_1 = {
        left_top = {position.x - k, position.y - k},
        right_bottom = {position.x + k, position.y + k}
    }

    for _, e in pairs(surface.find_entities_filtered({
        name = {"steel-chest", "crash-site-chest-1", "crash-site-chest-2"},
        area = area_1
    })) do
        e.operable = true
        e.minable_flag = true
        e.force = game.forces.player
    end

    local unit_number = entity.unit_number
    local wave_number = arty_count.roboport_wave[unit_number]
    arty_count.roboport_wave[unit_number] = nil

    local baolei_id
    for i, v in pairs(arty_count.arty) do
        local id = i  -- 直接使用循环索引
        if v.roboport == entity then
            baolei_id = id
            break
        end
    end
    
    -- 检查堡垒是否在4分钟内被销毁
    if baolei_id and arty_count.baolei_creation_times and arty_count.baolei_creation_times[baolei_id] then
        local creation_tick = arty_count.baolei_creation_times[baolei_id]
        local current_tick = game.tick
        local ticks_alive = current_tick - creation_tick
        local three_minutes_ticks = 60 * 60 * 4  -- 3分钟 = 180秒 = 10800 ticks
        
        if ticks_alive < three_minutes_ticks then
            -- 堡垒在4分钟内被销毁，下一个堡垒建设时间加快5分钟
            arty_count.next_baolei_speed_bonus = 5
        end
        
        -- 清理创建时间记录
        arty_count.baolei_creation_times[baolei_id] = nil
    end
    
    if baolei_id then
        arty_count.arty[baolei_id] = nil
    end
    
 
    
    -- 批量清理arty_count.unit表中属于该堡垒的所有单位索引，避免内存泄漏
    if baolei_id then
        for unit_number, associated_baolei_id in pairs(arty_count.unit) do
            if associated_baolei_id == baolei_id then
                arty_count.unit[unit_number] = nil
            end
        end
    end
    local this = WPT.get()
    -- 静态堡垒（skip_count=true）不参与动态计数，避免干扰核弹发射井状态
    if not (baolei_id and arty_count.arty[baolei_id] and arty_count.arty[baolei_id].skip_count) then
        this.baolei_count = this.baolei_count - 1
    
        if this.world_number == 9 or this.world_number == 11 or this.world_number == 12 then
            if this.baolei_silo and not this.baolei_silo.valid then
                this.baolei_silo = nil
            end
            if this.baolei_count <= 0 then
                if this.baolei_silo and this.baolei_silo.valid then
                    this.baolei_silo.destructible = true
                end

                this.baolei_count = 0
            end
        end
    end

    game.print({'amap.baolei_die' .. (this.world_number == 10 and '_world10' or '')})

    if not event.cause then
        return
    end
    if not event.cause.valid then
        return
    end


    if event.cause.name ~= 'character' then
        return
    end

    if not event.cause.player then
        return
    end

    local player = event.cause.player
    local rpg_t = RPG.get('rpg_t')

    player.insert {
        name = "coin",
        count = wave_number * 5 * 2.5
    }
    rpg_t[player.index].xp = rpg_t[player.index].xp + wave_number
    game.print({'amap.kill_baolei' .. (this.world_number == 10 and '_world10' or ''), player.name, wave_number, wave_number * 5 * 2.5})

end

local function on_robot_built_entity(event)
 
    local e = event.entity
    if not e or not e.valid then
        return
    end
    -- [BUG] 硬编码 nauvis 检查：在世界14（base_planet=gleba）等非 nauvis 星球上，
    -- 玩机建造的炮塔会被此检查跳过，不会加入 attack_table / can_attack_table，
    -- 导致重炮不会攻击 gleba 上的玩家炮塔。应改为 active_surface_index 检查。
    if e.surface.name ~= 'nauvis' then
        return
    end
    if e.force == game.forces.player then
        --如果e的名字在，artillery_target_entities表，则添加到arty_count.targets表中
        if table.contains(artillery_target_entities, e.name) then
            table.insert(arty_count.attack_table, e)
             --如果重炮数量不为0，则判断是否可以加入can_attack_table表中
        if #arty_count.all > 0 then
            -- 立即检查这个新建实体是否在重炮攻击范围内
            if e and e.valid then
                local entity_pos = e.position
                for _, artillery in pairs(arty_count.all) do
                    if artillery and artillery.valid then
                        local artillery_pos = artillery.position
                        local distance_squared = 
                            (artillery_pos.x - entity_pos.x)^2 + 
                            (artillery_pos.y - entity_pos.y)^2
                        if distance_squared <= arty_count.radius * arty_count.radius then
                            -- 检查是否已经在can_attack_table中
                
                                arty_count.can_attack_table[#arty_count.can_attack_table + 1] = e
                            
                            break
                        end
                    end
                end
            end
        end
        end
       
    end

    if e.force ~= game.forces.enemy then
        return
    end

    if e then
        if e.name == 'gun-turret' then
            arty_count.gun[#arty_count.gun + 1] = e
        end
        if e.name == 'laser-turret' then
            arty_count.laser[#arty_count.laser + 1] = e
        end
        if e.name == 'flamethrower-turret' then
            arty_count.flame[#arty_count.flame + 1] = e
        end
        if e.name == 'tesla-turret' then
            arty_count.tesla[#arty_count.tesla + 1] = e
        end
        if e.name == 'rocket-turret' then
            arty_count.rocket[#arty_count.rocket + 1] = e
        end
        if e.name == 'artillery-turret' then
            arty_count.all[#arty_count.all + 1] = e
            arty_count.fire[#arty_count.fire + 1] = 0
            arty_count.count = arty_count.count + 1
            -- 立即搜索攻击范围内的目标
            local artillery_pos = e.position
            for _, entity_name in pairs(artillery_target_entities) do
                for _, target_entity in pairs(e.surface.find_entities_filtered({
                    name = entity_name,
                    position = artillery_pos,
                    radius = arty_count.radius,
                    force = game.forces.player
                })) do
                    if target_entity and target_entity.valid then
                        local already_exists = false
                        for _, existing in pairs(arty_count.can_attack_table) do
                            if existing == target_entity then
                                already_exists = true
                                break
                            end
                        end
                        if not already_exists then
                            arty_count.can_attack_table[#arty_count.can_attack_table + 1] = target_entity
                        end
                    end
                end
            end
        end

        if e.name ~= "land-mine" then
            for i, v in pairs(arty_count.arty) do
                if v.roboport and v.roboport.valid then
                    local pos = v.roboport.position
                    local x = pos.x
                    local y = pos.y
                    local dist_squared = x * x + y * y
                    if dist_squared <= 24 * 24 then
                        local baolei_id = v.baolei_id
                        arty_count.arty[baolei_id].number = arty_count.arty[baolei_id].number + 1
                        arty_count.unit[e.unit_number] = baolei_id

                        return
                    end
                end
            end
        end
    end
end

--Event.on_nth_tick(60*3, get_new_arty)
Event.on_nth_tick(60 * 60, get_new_arty)
--Event.on_nth_tick(60 * 3, get_new_arty)
Event.on_nth_tick(2000, gun_bullet)
Event.on_nth_tick(2000, tesla_bullet)
Event.on_nth_tick(2000, rocket_bullet)
Event.on_nth_tick(120, add_bullet)
Event.on_nth_tick(5, energy)
Event.on_nth_tick(10, do_artillery_turrets_targets)

-- 分批任务队列处理器
local function process_construction_queue()
    if not construction_queue.tasks then
        return
    end
    if not Public.has_pending_tasks() then
        return
    end
    
    -- 每tick执行最多5个任务，避免性能问题
    local max_tasks_per_tick = 5
    local executed_count = 0
    
    while Public.has_pending_tasks() and executed_count < max_tasks_per_tick do
        local task = Public.get_next_task()
        if task then
            local success = Public.execute_batch_task(task)
            if success then
                executed_count = executed_count + 1
            else
                -- 任务失败时记录错误，但继续处理其他任务
                game.print({'amap.batch_task_failed', task.type})
            end
        else
            break
        end
    end
end

-- 检查是否需要完成堡垒建设
local function check_finish_construction()
    -- 检查所有活跃的建设任务
    if construction_queue.active_constructions then
        for baolei_id, construction in pairs(construction_queue.active_constructions) do
            -- 检查该堡垒的所有任务是否都已执行完成
            if construction.current_index > construction.task_end_index then
                -- 所有任务都已完成，进行收尾工作
                Public.finish_baolei_construction(baolei_id)
                
            end
        end
    end
end

-- 添加事件处理器
Event.on_nth_tick(2, process_construction_queue)  -- 每tick检查并执行任务
Event.on_nth_tick(60, check_finish_construction)   -- 每秒检查建设完成情况
Event.on_nth_tick(1800, check_roboport_destructible)  -- 每30秒检查机器人平台是否应该可被摧毁

Event.add(defines.events.on_robot_built_entity, on_robot_built_entity)
Event.add(defines.events.on_built_entity, on_robot_built_entity)
Event.add(defines.events.on_entity_died, on_entity_died)
Event.on_init(on_init)

return Public
