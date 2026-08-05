local WD = require 'modules.wave_defense.table'
local Event = require 'utils.event'
local math_round = math.round
local threat_values = require 'modules.wave_defense.threat_values'
local Public = {}

-- 按升序返回表键：pairs 哈希遍历顺序在服务器/客户端可能不同（反序列化后哈希布局不一致），
-- 抽奖区间的累积权重列表依赖遍历顺序 → 同一随机数会选中不同单位/品质 → 波次生成分歧 → 反同步。
-- 凡涉及"遍历权重表并构建累积区间"的代码必须用本函数保证两侧顺序一致。
local function sorted_keys(tbl)
    local keys = {}
    for k in pairs(tbl) do
        keys[#keys + 1] = k
    end
    table.sort(keys)
    return keys
end



local CACHE_UPDATE_INTERVAL = 6000

function Public.roll_from_raffle(raffle_key)
    local raffle = WD.get(raffle_key)
    local max_chance = 0
    for _, k in ipairs(sorted_keys(raffle)) do
        max_chance = max_chance + raffle[k]
    end
    local r = math.random(0, math.floor(max_chance))
    local current_chance = 0
    for _, k in ipairs(sorted_keys(raffle)) do
        current_chance = current_chance + raffle[k]
        if r <= current_chance then
            return k
        end
    end
end

function Public.wave_defense_roll_biter_name()
    return Public.roll_from_raffle('biter_raffle')
end

function Public.wave_defense_roll_spitter_name()
    return Public.roll_from_raffle('spitter_raffle')
end


-- ===================================================================
-- 最终极简单位演化配置表
-- ===================================================================
-- 描述了单位的生命周期和强度。计算函数会根据提供的参数自动选择模型。
--
-- 模型 1: 上升-下降 (如果提供了 start_level, end_level, K)
--         - 权重从 start_level 的 0 开始，线性增长到生命周期中点。
--         - 达到峰值后，线性下降，到 end_level 时归 0。
--         - K 是增长/下降的速率。
--
-- 模型 2: 无限增长 (如果只提供了 start_level, K)
--         - 权重从 start_level 的 0 开始，随 K 永久线性增长。
--
-- 模型 3: 线性方程 (如果提供了 C, K)
--         - 权重 = (K * level) + C。用于处理特殊的初始单位。
-- ===================================================================

local EnemyEvolutionConfig = {
    -- 基础单位 (模型3: 线性/常数) - 统一格式：{名称, 类型, 起始, 结束, K, C, 是否基础}
    {names = {'small-biter', 'small-spitter'}, types = {'biter', 'spitter'}, s=1, e=600, k=-1.75, c=1050, base=true},

    -- 基础单位 (模型1: 三角形) - 这里的 e 就是整个生命周期的终点
    {names = {'medium-biter', 'medium-spitter'}, types = {'biter', 'spitter'}, s=100, e=900, k=1, base=true},
    {names = {'big-biter', 'big-spitter'},       types = {'biter', 'spitter'}, s=500, e=1400, k=1, base=true},

    -- Behemoth (分段线性)
    {names = {'behemoth-biter', 'behemoth-spitter'}, types = {'biter', 'spitter'}, s=800, e=1e6,  k=1,  base=true},

    -- 额外单位 (三角形模式)
    {names = {'small-wriggler-pentapod'},  types = {'biter'}, s=150,  e=600,  k=1},
    {names = {'medium-wriggler-pentapod'}, types = {'biter'}, s=400,  e=850, k=1},
    {names = {'big-wriggler-pentapod'},    types = {'biter'}, s=650,  e=1550, k=1},


    {names = {'small-strafer-pentapod'},   types = {'spitter'}, s=1250, e=1850, k=1},
    {names = {'medium-strafer-pentapod'},  types = {'spitter'}, s=1650, e=2250, k=1},
    {names = {'big-strafer-pentapod'}, types = {'spitter'}, s=2050, e=1e6, k=1},

    {names = {'small-stomper-pentapod'},   types = {'biter'}, s=1350, e=1950, k=1},
    {names = {'medium-stomper-pentapod'},  types = {'biter'}, s=1750, e=2450, k=1},
    {names = {'big-stomper-pentapod'},  types = {'biter'},   s=2250, e=1e6, k=1},

}

--- 根据单位演化配置表和当前等级，计算单位的抽奖权重
-- @param level number 当前的波次等级
-- @param config table 单位演化配置表 (EnemyEvolutionConfig)
-- @return table biter_raffle, table spitter_raffle
local function calculate_unit_raffles(level, config)
    local raffles = { biter = {}, spitter = {} }
    
    for _, cfg in ipairs(config) do
        if level >= cfg.s and level < (cfg.e or 1e8) then
            local weight = 0
            if cfg.c then 
                -- 模型 3: 线性 (y = kx + c)
                weight = cfg.k * level + cfg.c
            elseif cfg.e and cfg.e < 1e6 then
                -- 模型 1: 三角形 (上升-下降合并为一行)
                -- 公式：K * (半径 - |当前等级 - 中心点| + 0.5)
                -- +0.5 确保在 s 和 e 边界处权重 > 0（否则边界波次单位不进抽奖池）
                weight = cfg.k * ((cfg.e - cfg.s) / 2 - math.abs(level - (cfg.s + cfg.e) / 2) + 0.5)
            else
                -- 模型 2: 无限增长
                weight = cfg.k * (level - cfg.s)
            end

            if weight > 0 then
                for i, name in ipairs(cfg.names) do
                    local t = cfg.types[i] or cfg.types[1]
                    local final_weight = weight
                    if name:find('pentapod') and not name:find('wriggler') then
                        final_weight = weight * 0.7
                    end
                    raffles[t][name] = (raffles[t][name] or 0) + final_weight
                end
            end
        end
    end
    return raffles.biter, raffles.spitter
end
function Public.wave_defense_set_unit_raffle(level)
    local biter_raffle, spitter_raffle = calculate_unit_raffles(level, EnemyEvolutionConfig)

    WD.set('biter_raffle', biter_raffle)
    WD.set('spitter_raffle', spitter_raffle)
end

function Public.wave_defense_roll_worm_name()
    return Public.roll_from_raffle('worm_raffle')
end

function Public.wave_defense_set_worm_raffle(level)
    local worm_raffle = {
        ['small-worm-turret'] = 1000 - level * 1.75,
        ['medium-worm-turret'] = level,
        ['big-worm-turret'] = 0,
        ['behemoth-worm-turret'] = 0
    }

    if level > 500 then
        worm_raffle['medium-worm-turret'] = 500 - (level - 500)
        worm_raffle['big-worm-turret'] = (level - 500) * 2
    end
    if level > 800 then
        worm_raffle['behemoth-worm-turret'] = (level - 800) * 3
    end
    
    for k, v in pairs(worm_raffle) do
        if v < 0 then
            worm_raffle[k] = 0
        end
    end
    
    WD.set('worm_raffle', worm_raffle)
end



local function calculate_quality_raffle(wave_number)
    local quality_raffle_cache = WD.get('quality_raffle_cache') or {
        wave_number = 0,
        last_update_tick = 0,
        raffle = {},
        total_weight = 0,
        total_chance = 0
    }
    
    local current_tick = game.ticks_played
    
    if quality_raffle_cache.wave_number == wave_number and 
       (current_tick - quality_raffle_cache.last_update_tick) < CACHE_UPDATE_INTERVAL then
        return quality_raffle_cache.raffle, quality_raffle_cache.total_weight, quality_raffle_cache.total_chance
    end
    
    if wave_number < 300 then
        quality_raffle_cache.wave_number = wave_number
        quality_raffle_cache.last_update_tick = current_tick
        quality_raffle_cache.raffle = {}
        quality_raffle_cache.total_weight = 0
        quality_raffle_cache.total_chance = 0
        WD.set('quality_raffle_cache', quality_raffle_cache)
        return {}, 0, 0
    end
    
    local quality_upgrades = { 
        { name = "legendary", base_chance = 0.005 },
        { name = "epic",      base_chance = 0.015 },
        { name = "rare",      base_chance = 0.025 },
        { name = "uncommon",  base_chance = 0.05 } 
    }
    
    local progress = math.min((wave_number - 300) / (3000 - 300), 1)
    local total_quality_chance = progress * 1.0
    
    if total_quality_chance <= 0 then
        quality_raffle_cache.wave_number = wave_number
        quality_raffle_cache.last_update_tick = current_tick
        quality_raffle_cache.raffle = {}
        quality_raffle_cache.total_weight = 0
        quality_raffle_cache.total_chance = 0
        WD.set('quality_raffle_cache', quality_raffle_cache)
        return {}, 0, 0
    end
    
    local decay_progress = 0
    if wave_number >= 3000 then
        decay_progress = math.min((wave_number - 3000) / (6000 - 3000), 1)
    end
    
    local quality_raffle_cache_temp = {}
    local total_quality_weight = 0
    local base_total = 0.005 + 0.015 + 0.025 + 0.05
    
    for _, item in ipairs(quality_upgrades) do
        local scaled_chance = (item.base_chance / base_total) * total_quality_chance
        quality_raffle_cache_temp[item.name] = scaled_chance
    end
    
    if decay_progress > 0 then
        local transferable_qualities = {"epic", "rare", "uncommon"}
        local total_transfer = 0
        
        for _, name in ipairs(transferable_qualities) do
            local transfer_amount = quality_raffle_cache_temp[name] * decay_progress
            quality_raffle_cache_temp[name] = quality_raffle_cache_temp[name] - transfer_amount
            total_transfer = total_transfer + transfer_amount
        end
        
        quality_raffle_cache_temp["legendary"] = quality_raffle_cache_temp["legendary"] + total_transfer
    end
    
    local result_raffle = {}
    -- 排序遍历：result_raffle 会写入同步的 quality_raffle_cache，列表顺序必须两侧一致
    for _, name in ipairs(sorted_keys(quality_raffle_cache_temp)) do
        local chance = quality_raffle_cache_temp[name]
        table.insert(result_raffle, {name = name, weight = chance})
        total_quality_weight = total_quality_weight + chance
    end
    
    quality_raffle_cache.wave_number = wave_number
    quality_raffle_cache.last_update_tick = current_tick
    quality_raffle_cache.raffle = result_raffle
    quality_raffle_cache.total_weight = total_quality_weight
    quality_raffle_cache.total_chance = total_quality_chance
    
    WD.set('quality_raffle_cache', quality_raffle_cache)
    
    return result_raffle, total_quality_weight, total_quality_chance
end

local function select_random_quality(quality_raffle_cache, total_quality_weight, total_quality_chance)
    if script.active_mods['quality'] == nil or #quality_raffle_cache == 0 then
        return nil
    end
    
    if math.random() > total_quality_chance then
        return nil
    end
    
    if total_quality_weight <= 0 then
        return nil
    end
    
    local r = math.random() * total_quality_weight
    local current_weight = 0
    
    for _, item in ipairs(quality_raffle_cache) do
        current_weight = current_weight + item.weight
        if r <= current_weight then
            return item.name
        end
    end
    
    return #quality_raffle_cache > 0 and quality_raffle_cache[#quality_raffle_cache].name or nil
end

local function build_raffle_cache(raffle)
    local cache = {}
    local total_weight = 0
    local current_weight = 0
    
    -- 排序遍历：累积权重列表顺序必须两侧一致（见 sorted_keys 注释），否则二分选中单位分歧
    for _, k in ipairs(sorted_keys(raffle)) do
        local v = raffle[k]
        current_weight = current_weight + v
        table.insert(cache, {unit = k, weight = current_weight})
        total_weight = total_weight + v
    end
    
    return cache, total_weight
end

local function generate_units_from_raffles(total_units, melee_ratio, melee_cache, melee_weight, ranged_cache, ranged_weight, max_threat, quality_raffle_cache, total_quality_weight, total_quality_chance)
    local unit_table = {}
    local total_threat = 0
    local total_generated = 0
    
    local melee_count = math.floor(total_units * melee_ratio)
    local ranged_count = total_units - melee_count
    
    local function select_unit_by_binary_search(cache, total_weight)
        if total_weight <= 0 then
            return nil
        end
        
        -- 用浮点随机数避免 floor 截断导致小数权重（如五足虫 0.7）永远选不到
        local r = math.random() * total_weight
        local low, high = 1, #cache
        
        while low <= high do
            local mid = math.floor((low + high) / 2)
            if r <= cache[mid].weight then
                high = mid - 1
            else
                low = mid + 1
            end
        end
        
        return cache[low] and cache[low].unit or nil
    end
    
    local function generate_units(cache, total_weight, count)
        for i = 1, count do
            if max_threat and max_threat > 0 and total_threat >= max_threat then
                break
            end
            
            local selected_unit = select_unit_by_binary_search(cache, total_weight)
            
            if selected_unit then
                local unit_threat = math_round((threat_values[selected_unit] or 1) * 1, 2)
                
                if max_threat and max_threat > 0 and (total_threat + unit_threat) > max_threat then
                    break
                end
                
                local quality_name = select_random_quality(quality_raffle_cache, total_quality_weight, total_quality_chance) or "normal"
                unit_table[#unit_table + 1] = {
                    unit_name = selected_unit,
                    quality_name = quality_name
                }
                total_threat = total_threat + unit_threat
                total_generated = total_generated + 1
            end
        end
    end
    
    generate_units(melee_cache, melee_weight, melee_count)
    generate_units(ranged_cache, ranged_weight, ranged_count)
    
    return unit_table
end

local function calculate_demolisher_chance(wave_number)
    if wave_number < 2500 then
        return nil, 0
    end
    
    local unit_name
    local range_start
    
    if wave_number < 3000 then
        unit_name = 'small-demolisher'
        range_start = 2500
    elseif wave_number < 3500 then
        unit_name = 'medium-demolisher'
        range_start = 3000
    else
        unit_name = 'big-demolisher'
        range_start = 3500
    end
    
    local progress = math.min((wave_number - range_start) / 500, 1)
    local probability = 0.10 + progress * 0.10
    
    return unit_name, probability
end

--- 单独判断并生成撼地虫(demolisher)。仅设置出生方向朝向主目标，不进编队、不设 ai_settings、不追踪威胁。
function Public.try_spawn_demolisher(surface, position, target)
    if not surface or not position then return nil end
    local wave_number = WD.get('wave_number')
    local name, chance = calculate_demolisher_chance(wave_number)
    if not name then return nil end
    local last_spawn = WD.get('last_demolisher_spawn_wave')
    if wave_number == last_spawn then return nil end

    local direction
    if target and target.valid then
        local sp = WD.get('spawn_position')
        local dx = target.position.x - sp.x
        local dy = target.position.y - sp.y
        local angle = math.atan2(dy, dx)
        local orientation_cont = (angle / (2 * math.pi) + 0.25 + 1) % 1
        local dir_index = math.floor(orientation_cont * 4 + 0.5) % 4
        local dirs = {0, 4, 8, 12}
        direction = dirs[dir_index + 1]
    end

    if math.random() < chance then
        local params = { name = name, position = position, force = 'enemy' }
        if direction then params.direction = direction end
        local demo = surface.create_entity(params)
        if demo then
            WD.set('last_demolisher_spawn_wave', wave_number)
            return demo
        end
    end
    return nil
end

function Public.wave_defense_generate_unit_table(total_units, melee_ratio, ranged_ratio, max_threat)
    if not melee_ratio or not ranged_ratio then
        melee_ratio = 0.6
        ranged_ratio = 0.4
    end
    
    local total_ratio = melee_ratio + ranged_ratio
    if total_ratio ~= 1 then
        melee_ratio = melee_ratio / total_ratio
        ranged_ratio = ranged_ratio / total_ratio
    end
    
    local biter_raffle = WD.get('biter_raffle')
    local spitter_raffle = WD.get('spitter_raffle')
    local wave_number = WD.get('wave_number')
    
    local quality_raffle_cache, total_quality_weight, total_quality_chance = calculate_quality_raffle(wave_number)
    
    local melee_cache, melee_weight = build_raffle_cache(biter_raffle)
    local ranged_cache, ranged_weight = build_raffle_cache(spitter_raffle)
    
    if melee_weight <= 0 and ranged_weight <= 0 then
        table.insert(melee_cache, {unit = "small-biter", weight = 1})
        melee_weight = 1
    end
    
    local unit_table = generate_units_from_raffles(total_units, melee_ratio, melee_cache, melee_weight, ranged_cache, ranged_weight, max_threat, quality_raffle_cache, total_quality_weight, total_quality_chance)

    return unit_table
end


local on_init = function()
  -- biter_raffle 和 spitter_raffle 已在 table.lua 的 reset_wave_defense() 中初始化
  
  Public.wave_defense_set_worm_raffle(100)
  Public.wave_defense_set_unit_raffle(100)

end

Event.on_init(on_init)

return Public
