local Global = require 'utils.global'
local Event = require 'utils.event'
local threat_values = require 'modules.wave_defense.threat_values'

local this = {}
local Public = {}

-- 虫子类型 -> 分类 的静态映射表（查表法，O(1)）
-- demolisher 不纳入本系统
local BiterCategoryMap = {
    -- biter类（近战撕咬虫）
    ['small-biter']       = 'biter',
    ['medium-biter']      = 'biter',
    ['big-biter']         = 'biter',
    ['behemoth-biter']    = 'biter',
    -- spitter类（远程喷吐虫）
    ['small-spitter']     = 'spitter',
    ['medium-spitter']    = 'spitter',
    ['big-spitter']       = 'spitter',
    ['behemoth-spitter']  = 'spitter',
    -- stomper类（撟地虫）
    ['small-stomper-pentapod']  = 'stomper',
    ['medium-stomper-pentapod'] = 'stomper',
    ['big-stomper-pentapod']    = 'stomper',
    -- strafer类（散兵虫）
    ['small-strafer-pentapod']  = 'strafer',
    ['medium-strafer-pentapod'] = 'strafer',
    ['big-strafer-pentapod']    = 'strafer',
    -- wriggler类（蠕动虫）
    ['small-wriggler-pentapod']  = 'wriggler',
    ['medium-wriggler-pentapod'] = 'wriggler',
    ['big-wriggler-pentapod']    = 'wriggler',
}

--- 获取虫子的分类
-- @param unit_name string 虫子名称
-- @return string|nil 分类key, nil表示不纳入本系统
function Public.get_biter_category(unit_name)
    return BiterCategoryMap[unit_name]
end

--- 获取虫子含品质加成的最大血量
-- @param unit_name string 虫子原型名称
-- @param quality_name string|nil 品质名称
-- @return number 最大血量
function Public.get_biter_max_health(unit_name, quality_name)
    local proto = prototypes.entity[unit_name]
    if not proto then
        return 0
    end
    -- Factorio 2.0: prototype:get_max_health(quality) 直接返回含品质加成的血量
    if quality_name and quality_name ~= 'normal' then
        return proto.get_max_health(quality_name)
    end
    return proto.get_max_health()
end

--- 自愈：统计 active_biters 中实际存活的五足虫数量，纠正泄漏的计数器
-- 每 30 秒才执行一次完整扫描，避免每帧遍历
function Public.reconcile_pentapod_counts()
    local last_reconcile = Public.get('_last_pentapod_reconcile_tick') or 0
    if game.tick - last_reconcile < 1800 then  -- 30秒 = 1800 ticks
        return
    end
    Public.set('_last_pentapod_reconcile_tick', game.tick)

    local active_biters = Public.get('active_biters')
    local stomper = 0
    local strafer = 0
    for _, biter in pairs(active_biters) do
        local entity = biter.entity
        if entity and entity.valid then
            local cat = BiterCategoryMap[entity.name]
            if cat == 'stomper' then
                stomper = stomper + 1
            elseif cat == 'strafer' then
                strafer = strafer + 1
            end
        end
    end

    local old_stomper = Public.get('stomper_count') or 0
    local old_strafer = Public.get('strafer_count') or 0

    if stomper ~= old_stomper then
        Public.set('stomper_count', stomper)
        log('[五足虫自愈] stomper_count: ' .. old_stomper .. ' -> ' .. stomper)
    end
    if strafer ~= old_strafer then
        Public.set('strafer_count', strafer)
        log('[五足虫自愈] strafer_count: ' .. old_strafer .. ' -> ' .. strafer)
    end
end

--- 检查是否可以生成虫子（使用 active_biter_count / max_active_biters，含五足虫独立上限）
-- @param unit_name string 虫子名称
-- @return boolean true=可以生成
-- @return string|nil category 当返回false时，表示超额的分类
function Public.try_register_biter_spawn(unit_name)
    local category = BiterCategoryMap[unit_name]
    if not category then
        -- 不在映射表中的虫子（如demolisher），不受本系统管理
        return true, nil
    end

    local active_biter_count = Public.get('active_biter_count')
    local max_active_biters = Public.get('max_active_biters')

    if active_biter_count >= max_active_biters then
        return false, category
    end

    -- 五足虫独立上限检查（带自愈：被拦截时先核实计数器是否准确）
    if category == 'stomper' then
        if Public.get('stomper_count') >= Public.get('max_pentapods_per_type') then
            Public.reconcile_pentapod_counts()
            if Public.get('stomper_count') >= Public.get('max_pentapods_per_type') then
                return false, category
            end
        end
    elseif category == 'strafer' then
        if Public.get('strafer_count') >= Public.get('max_pentapods_per_type') then
            Public.reconcile_pentapod_counts()
            if Public.get('strafer_count') >= Public.get('max_pentapods_per_type') then
                return false, category
            end
        end
    end

    return true, category
end

--- 将虫子血量存入对应分类的池子
-- @param unit_name string 虫子名称
-- @param quality_name string|nil 品质
-- @param category string 分类
function Public.add_health_to_pool(unit_name, quality_name, category)
    local health = Public.get_biter_max_health(unit_name, quality_name)
    local pools = Public.get('biter_health_pools')
    pools[category].pending_health = pools[category].pending_health + health
    Public.set('biter_health_pools', pools)
end

--- 增加五足虫类型计数（实际生成虫时调用）
-- @param unit_name string 虫子名称
function Public.inc_type_counter(unit_name)
    local category = BiterCategoryMap[unit_name]
    if category == 'stomper' then
        Public.set('stomper_count', (Public.get('stomper_count') or 0) + 1)
    elseif category == 'strafer' then
        Public.set('strafer_count', (Public.get('strafer_count') or 0) + 1)
    end
end

--- 减少五足虫类型计数（虫死亡/超时/转化时调用）
-- @param unit_name string 虫子名称
function Public.dec_type_counter(unit_name)
    local category = BiterCategoryMap[unit_name]
    if category == 'stomper' then
        local c = Public.get('stomper_count') or 0
        if c > 0 then Public.set('stomper_count', c - 1) end
    elseif category == 'strafer' then
        local c = Public.get('strafer_count') or 0
        if c > 0 then Public.set('strafer_count', c - 1) end
    end
end

--- 虫子死亡时：血量池复活 / 威胁复活，两条独立路径
-- @param entity LuaEntity 死亡的虫子实体
-- @param is_managed boolean true=活跃管理虫（两条路径），false=野生虫（仅血量池路径）
function Public.on_managed_biter_death(entity, is_managed)
    local category = BiterCategoryMap[entity.name]
    if not category then
        return  -- 不受本系统管理的虫子
    end

    -- 活跃上限检查（仅受管理虫子需要）
    if is_managed then
        local active_biter_count = Public.get('active_biter_count')
        local max_active_biters = Public.get('max_active_biters')
        if active_biter_count >= max_active_biters then
            return
        end

        -- 五足虫独立上限检查（复活前，带自愈）
        if category == 'stomper' then
            if Public.get('stomper_count') >= Public.get('max_pentapods_per_type') then
                Public.reconcile_pentapod_counts()
                if Public.get('stomper_count') >= Public.get('max_pentapods_per_type') then
                    return
                end
            end
        end
        if category == 'strafer' then
            if Public.get('strafer_count') >= Public.get('max_pentapods_per_type') then
                Public.reconcile_pentapod_counts()
                if Public.get('strafer_count') >= Public.get('max_pentapods_per_type') then
                    return
                end
            end
        end
    end

    -- 读取死亡虫子的原型血量（含品质加成）
    local surface = entity.surface
    local position = entity.position
    local quality_name = nil
    if entity.quality and entity.quality.valid then
        quality_name = entity.quality.name
    end
    local unit_health = Public.get_biter_max_health(entity.name, quality_name)
    if unit_health <= 0 then
        return
    end

    local can_revive = false
    local from_health_pool = false
    local from_threat = false

    -- ===== 路径A：血量池复活（所有虫子共用） =====
    local pools = Public.get('biter_health_pools')
    local pool = pools[category]
    if pool and pool.pending_health >= unit_health then
        can_revive = true
        from_health_pool = true
        -- 立即扣除血量
        pool.pending_health = pool.pending_health - unit_health
        Public.set('biter_health_pools', pools)
    end

    -- ===== 路径B：威胁复活（仅受管理虫子，不扣血量池） =====
    if is_managed then
        local threat = Public.get('threat')
        local active_biter_threat = Public.get('active_biter_threat')
        if threat > 0 and active_biter_threat < threat then
            can_revive = true
            from_threat = true
        end
    end

    -- 两条路径都不满足，不复活
    if not can_revive then
        return
    end

    -- 复活虫子
    local entity_params = {
        name = entity.name,
        position = position,
        force = 'enemy',
    }
    if quality_name and quality_name ~= 'normal' then
        entity_params.quality = quality_name
    end

    local revived = surface.create_entity(entity_params)
    if revived and revived.valid then
        if is_managed then
            -- 受管理虫子：更新威胁计数，纳入 active_biters
            local biter_threat = threat_values[entity.name] or 0
            Public.set('active_biter_count', Public.get('active_biter_count') + 1)
            Public.set('active_biter_threat', Public.get('active_biter_threat') + biter_threat)
            -- 五足虫类型计数
            Public.inc_type_counter(entity.name)

            local active_biters = Public.get('active_biters')
            if active_biters then
                active_biters[revived.unit_number] = {
                    entity = revived,
                    spawn_tick = game.tick
                }
            end
        end
        -- 野生虫：复活后不纳入管理，自由存在
    end
end

Global.register(
    this,
    function(tbl)
        this = tbl
    end
)

function Public.debug_module()
    this.next_wave = 1000
    this.wave_interval = 500
    this.wave_enforced = true
    this.debug = true
end

function Public.reset_wave_defense()
    

    this.boss_wave = false
    this.boss_wave_warning = false
    this.nest_kills_per_minute = 0
    this.active_biters = {}
    this.active_biter_count = 0
    this.active_biter_threat = 0
    this.average_unit_group_size = 35
    this.biter_raffle = {
        ['small-biter'] = 825,
        ['medium-biter'] = 100,
        ['big-biter'] = 0,
        ['behemoth-biter'] = 0,
        ['small-wriggler-pentapod'] = 0,
        ['medium-wriggler-pentapod'] = 0,
        ['big-wriggler-pentapod'] = 0,
        ['small-stomper-pentapod'] = 0,
        ['medium-stomper-pentapod'] = 0,
        ['big-stomper-pentapod'] = 0
    }
    this.spitter_raffle = {
        ['small-spitter'] = 825,
        ['medium-spitter'] = 100,
        ['big-spitter'] = 0,
        ['behemoth-spitter'] = 0,
        ['small-strafer-pentapod'] = 0,
        ['medium-strafer-pentapod'] = 0,
        ['big-strafer-pentapod'] = 0
    }
    this.debug = false
    this.game_lost = false
    this.get_random_close_spawner_attempts = 5
    this.group_size = 4
    this.last_wave = game.tick
    this.max_active_biters = 96
    this.max_active_unit_groups = 32
    this.max_biter_age = 60 * 60*2
    this.nests = {}
    this.nest_building_density = 48
    this.next_wave = game.tick + 3600 * 15 + 3600 * 15
    this.simple_entity_shredding_cost_modifier = 0.009
    this.spawn_position = {x = 0, y = 64}
    this.surface_index = 1
    this.target = nil
    this.threat = 0
    this.threat_gain_multiplier = 2
    this.threat_log = {}
    this.threat_log_index = 0
    this.unit_groups = {}
    this.unit_group_pos = {
        positions = {}
    }
    this.index = 0
    this.random_group = nil
    this.unit_group_command_delay = 60 * 20
    this.unit_group_command_step_length = 15
    this.unit_group_last_command = {}
    this.wave_interval = 3600
    this.wave_enforced = false
    this.wave_number = 0
    this.worm_building_chance = 3
    this.worm_building_density = 16
    this.worm_raffle = {}
    this.clear_corpses = false
    this.biter_health_boost = 1
    this.alert_boss_wave = false
    this.remove_entities = true

    this.enable_threat_log = false
    this.disable_threat_below_zero = false
    this.check_collapse_position = true
    this.resolve_pathing = true
    this.increase_health_per_wave = false
    this.fill_tiles_so_biter_can_path = true

    this.unit_table = {}
    this.unit_table_time = 0

    this.main_unit_table = {}
    this.main_uunit_table_time = 0
    
    this.boss_unit_table = {}
    this.boss_unit_table_time = 0

    -- 撼地虫生成追踪
    this.last_demolisher_spawn_wave = 0

    -- ============================================
    -- 血量池系统（使用 active_biter_count / max_active_biters 做上限）
    -- ============================================
    -- 五足虫独立计数器（stomper和strafer各上限5只）
    this.stomper_count = 0
    this.strafer_count = 0
    this.max_pentapods_per_type = 3

    -- 5个血量池，按虫子类型分类，只存血量
    this.biter_health_pools = {
        biter    = { pending_health = 0 },
        spitter  = { pending_health = 0 },
        stomper  = { pending_health = 0 },
        strafer  = { pending_health = 0 },
        wriggler = { pending_health = 0 },
    }

    this.spawn_unit_spawner_count = 0
    this.spawn_unit_spawner_time = 0
    this.last_mine_check_time = 0

    this.modified_unit_health = {
        current_value = 1.02,
        limit_value = 30,
        health_increase_per_boss_wave = 0.04
    }
end

function Public.get(key)
    if key then
        
        return this[key]
    else
        return this
    end
end

function Public.set(key, value)
    if key and (value or value == false or value == 'nil') then
        if value == 'nil' then
            this[key] = nil
        else
            this[key] = value
        end
        return this[key]
    elseif key then
        return this[key]
    else
        return this
    end
end

Public.get_table = Public.get

function Public.clear_corpses(value)
    if (value or value == false) then
        this.clear_corpses = value
    end
    return this.clear_corpses
end

function Public.get_wave()
    return this.wave_number
end

function Public.get_disable_threat_below_zero()
    return this.disable_threat_below_zero
end

function Public.set_disable_threat_below_zero(boolean)
    if (boolean or boolean == false) then
        this.disable_threat_below_zero = boolean
    end
    return this.disable_threat_below_zero
end

function Public.get_alert_boss_wave()
    return this.alert_boss_wave
end

function Public.alert_boss_wave(boolean)
    if (boolean or boolean == false) then
        this.alert_boss_wave = boolean
    end
    return this.alert_boss_wave
end

function Public.set_spawn_position(tbl)
    if type(tbl) == 'table' then
        this.spawn_position = tbl
    else
        error('Tbl must be of type table.')
    end
    return this.spawn_position
end

function Public.remove_entities(boolean)
    if (boolean or boolean == false) then
        this.remove_entities = boolean
    end
    return this.remove_entities
end

function Public.increase_health_per_wave(boolean)
    if (boolean or boolean == false) then
        this.increase_health_per_wave = boolean
    end
    return this.increase_health_per_wave
end

function Public.enable_threat_log(boolean)
    if (boolean or boolean == false) then
        this.enable_threat_log = boolean
    end
    return this.enable_threat_log
end

function Public.check_collapse_position(boolean)
    if (boolean or boolean == false) then
        this.check_collapse_position = boolean
    end
    return this.check_collapse_position
end

function Public.increase_boss_health_per_wave(boolean)
    if (boolean or boolean == false) then
        this.increase_boss_health_per_wave = boolean
    end
    return this.increase_boss_health_per_wave
end

function Public.resolve_pathing(boolean)
    if (boolean or boolean == false) then
        this.resolve_pathing = boolean
    end
    return this.resolve_pathing
end

function Public.fill_tiles_so_biter_can_path(boolean)
    if (boolean or boolean == false) then
        this.fill_tiles_so_biter_can_path = boolean
    end
    return this.fill_tiles_so_biter_can_path
end

function Public.increase_damage_per_wave(boolean)
    if (boolean or boolean == false) then
        this.increase_damage_per_wave = boolean
    end
    return this.increase_damage_per_wave
end

function Public.set_biter_health_boost(number)
    if number and type(number) == 'number' then
        this.biter_health_boost = number
    else
        this.biter_health_boost = 1
    end
    return this.biter_health_boost
end

function Public.get_nest_kills_per_minute()
    return this.nest_kills_per_minute
end

function Public.set_nest_kills_per_minute(value)
    this.nest_kills_per_minute = value
    return this.nest_kills_per_minute
end

local on_init = function()
    Public.reset_wave_defense()
end

-- Event.on_nth_tick(30, Public.debug_module)

Event.on_init(on_init)

return Public
