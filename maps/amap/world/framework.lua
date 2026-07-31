-- maps/amap/world/framework.lua
-- 世界框架核心
--
-- 设计目标：参照副本框架（instance.lua）的模式，把所有世界相关配置集中到
-- 一个框架里管理。每个世界在自己的模块文件（worlds/world_XX_<name>.lua）
-- 中调用 World.register(world_id, def) 一次性定义所有配置，框架提供查询 API
-- 供 diff.lua / main.lua / enemy_arty.lua / surface.lua / vote_choise_map.lua
-- 等调用方统一查表，消除散落的 if world_number == N 分支。
--
-- 新增世界流程见《世界添加说明-新框架版.md》（5 步，参照副本框架）。

local Event = require 'utils.event'
-- 必须在控制阶段 require：Factorio 运行期调用 require 会直接抛
-- "Require can't be used outside of control.lua parsing"。
-- 依赖方向安全：maps.amap.table 只依赖 utils.global / utils.event，不反向依赖本框架。
local WPT = require 'maps.amap.table'

local Public = {}

--==============================================================================
-- 内部数据
--==============================================================================

-- world_id -> def（世界完整定义）
local registered = {}

-- config_name -> surface_config（共享地表资源配置，多个世界可引用同一份）
local surface_configs = {}

--==============================================================================
-- 声明式事件分发（世界模块不得自行 Event.add / Event.on_nth_tick）
--
-- 世界模块只在 World.register 的 def 中声明 events / nth_tick 字段，框架为每个
-- 被声明过的事件/间隔建立"唯一分发器"，运行时按当前世界查表调用其 handler。
-- 非当前世界的 handler 一律不执行 → 世界间零串扰、世界模块零事件注册。
--
--   World.register(15, {
--       events = {
--           [defines.events.on_built_entity] = on_built_entity,               -- 单个
--           [defines.events.on_entity_died]  = {on_boss_died, on_turret_died},-- 多个（按序调用）
--       },
--       nth_tick = {
--           [60]  = {on_tick, enforce_techs},
--           [600] = boss_watchdog,
--       },
--   })
--==============================================================================

local event_dispatchers = {}     -- event_id -> true（已建分发器）
local nth_tick_dispatchers = {}  -- interval -> true（已建分发器）

--- 取当前世界的 def（世界号未就绪 / 未注册则返回 nil）
local function get_active_def()
    local this = WPT.get()
    local world_id = this and this.world_number
    if not world_id then
        return nil
    end
    return registered[world_id]
end

--- 调用一个"单函数或函数数组"形式的 handler 声明
local function invoke(handlers, arg)
    if not handlers then
        return
    end
    if type(handlers) == 'function' then
        handlers(arg)
        return
    end
    for i = 1, #handlers do
        handlers[i](arg)
    end
end

local function ensure_event_dispatcher(event_id)
    if event_dispatchers[event_id] then
        return
    end
    event_dispatchers[event_id] = true
    Event.add(
        event_id,
        function(event)
            local def = get_active_def()
            if not def or not def.events then
                return
            end
            invoke(def.events[event_id], event)
        end
    )
end

local function ensure_nth_tick_dispatcher(interval)
    if nth_tick_dispatchers[interval] then
        return
    end
    nth_tick_dispatchers[interval] = true
    Event.on_nth_tick(
        interval,
        function(event)
            local def = get_active_def()
            if not def or not def.nth_tick then
                return
            end
            invoke(def.nth_tick[interval], event)
        end
    )
end

--- 取 table 的数字键升序列表（保证分发器建立顺序确定，避免 pairs 顺序带来的不确定性）
local function sorted_keys(t)
    local keys = {}
    for k in pairs(t) do
        keys[#keys + 1] = k
    end
    table.sort(keys)
    return keys
end

--==============================================================================
-- 注册 API（世界模块调用）
--==============================================================================

--- 注册一个世界
-- @param world_id number 世界编号（如 7）
-- @param def table 世界定义，包含所有配置字段
function Public.register(world_id, def)
    registered[world_id] = def

    -- 声明式事件：为 def 中声明过的事件/间隔按需建立唯一分发器
    -- （必须在控制阶段完成，World.register 由世界模块在 require 时调用，满足该约束）
    if def.events then
        local ids = sorted_keys(def.events)
        for i = 1, #ids do
            ensure_event_dispatcher(ids[i])
        end
    end
    if def.nth_tick then
        local intervals = sorted_keys(def.nth_tick)
        for i = 1, #intervals do
            ensure_nth_tick_dispatcher(intervals[i])
        end
    end
end

--- 注册一份地表配置（共享资源，多个世界可引用同一份）
-- @param name string 配置名（如 "have_ore_no_biter"）
-- @param config table 配置内容（与原 world_table.lua surface_configs 同结构）
function Public.register_surface_config(name, config)
    surface_configs[name] = config
end

--==============================================================================
-- 查询 API（调用方使用）
--==============================================================================

--- 获取世界完整定义
-- @param world_id number
-- @return table|nil
function Public.get(world_id)
    return registered[world_id]
end

--- 获取世界某个字段
-- @param world_id number
-- @param field_name string
-- @return any|nil
function Public.get_field(world_id, field_name)
    local def = registered[world_id]
    return def and def[field_name]
end

--- 获取所有已注册世界 ID 列表（升序）
-- @return table<number>
function Public.get_registered_worlds()
    local list = {}
    for id in pairs(registered) do
        table.insert(list, id)
    end
    table.sort(list)
    return list
end

--- 查询满足条件的世界 ID 列表
-- @param field_name string 字段名
-- @param expected_value any 期望值；传 true 时表示"字段为真值"（非 nil/false）
-- @return table<number> 升序世界 ID 列表
function Public.query(field_name, expected_value)
    local result = {}
    for id, def in pairs(registered) do
        local v = def[field_name]
        if expected_value == true then
            if v ~= nil and v ~= false then
                table.insert(result, id)
            end
        elseif v == expected_value then
            table.insert(result, id)
        end
    end
    table.sort(result)
    return result
end

--- 获取地表配置
-- @param name string 配置名
-- @return table|nil
function Public.get_surface_config(name)
    return surface_configs[name]
end

return Public
