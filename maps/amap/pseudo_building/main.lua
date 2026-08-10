-- maps/amap/pseudo_building/main.lua
-- 伪建筑框架门面（参照 world/world_main.lua）
--
-- 职责：
--   1. 顶层 require 5 个 buildings 子模块（触发 register 副作用）
--   2. 注册事件调度（on_nth_tick 主循环 60 + 巡检 900 + on_entity_died）
--   3. 暴露查询 API + 转发 create/destroy 等 API（兼容旧调用方）
--   4. on_load 按 module_name 重建 def（function 不进存档）
--   5. 调试命令 /pb
--   6. reset_table 入口（由 amap/main.lua 的 reset_map 调用）
--
-- 依赖：framework（注册中心）、table（数据表）、functions（工具库 + 创建 API）
-- 不依赖：任何 buildings 子模块（由本文件末尾 require 触发，单向依赖）

local Event = require 'utils.event'
local Framework = require 'maps.amap.pseudo_building.framework'
local Table = require 'maps.amap.pseudo_building.table'
local Fns = require 'maps.amap.pseudo_building.functions'

local Public = {}

--==============================================================================
-- 常量
--==============================================================================
local TICK_MAIN = 60      -- 1 秒主循环
local TICK_SWEEP = 900    -- 15 秒失效建筑巡检

--==============================================================================
-- 创建 API（转发到 functions）
--==============================================================================
Public.create_attack = Fns.create_attack
Public.create_storage = Fns.create_storage
Public.create_power = Fns.create_power
Public.destroy = Fns.destroy

--==============================================================================
-- 查询 API
--==============================================================================
function Public.get_count(side)
    if side then return Fns.count_side(side) end
    local n = 0
    for _ in pairs(Table.get_registry()) do n = n + 1 end
    return n
end

function Public.get_count_player(player_index)
    return Fns.count_owner(player_index)
end

function Public.get_entry(unit_number)
    return Table.get_registry()[unit_number]
end

function Public.get_by_owner(player_index)
    local out = {}
    for un, e in pairs(Table.get_registry()) do
        if e.owner == player_index then out[#out + 1] = e end
    end
    return out
end

--==============================================================================
-- 子模块辅助 API 转发（保持旧 API 兼容）
--==============================================================================
Public.get_player = Fns.get_player
Public.take_fish = Fns.take_fish
Public.item_craft_time = Fns.item_craft_time

-- 暴露常量
Public.PLAYER_LIMIT = Framework.PLAYER_LIMIT
Public.ENEMY_LIMIT = Framework.ENEMY_LIMIT
Public.FORCE_PLAYER = Framework.FORCE_PLAYER
Public.FORCE_ENEMY = Framework.FORCE_ENEMY
Public.PROTOTYPE = Framework.PROTOTYPE

-- register / add_building / get_module / get_buildings 转发（子模块 require framework 即可，
-- 但为兼容旧 require main 的代码也保留转发）
Public.register = Framework.register
Public.add_building = Framework.add_building
Public.get_module = Framework.get_module
Public.get_buildings = Framework.get_buildings
Public.get_building_spawn_fn = Framework.get_building_spawn_fn

--==============================================================================
-- 事件调度：主循环（1 秒）
--==============================================================================
local function on_main_tick(event)
    local now = event.tick
    local registry = Table.get_registry()
    for unit_number, entry in pairs(registry) do
        local e = entry.entity
        if not e or not e.valid then
            Fns.cleanup(unit_number)
        elseif entry.lifespan and entry.lifespan > 0 and (now - entry.created) >= entry.lifespan then
            Fns.cleanup(unit_number)
        else
            local def = entry.def
            local ctx = {owner = entry.owner, side = entry.side, opts = entry.opts, category = entry.category}
            -- check_active：判定能否工作
            local active = true
            if def and def.check_active then
                local ok, res = pcall(def.check_active, e, ctx)
                active = ok and (res ~= false)
            end
            entry.active = active
            if active and def and def.on_tick then
                pcall(def.on_tick, e, entry.data, ctx)
            end
            if active and entry.opts.timed and def and def.on_interval then
                if now >= entry.next_trigger then
                    pcall(def.on_interval, e, entry.data, ctx)
                    entry.next_trigger = now + (entry.opts.interval or 1800)
                end
            end
        end
    end
end

--==============================================================================
-- 事件：15 秒失效建筑巡检
--==============================================================================
local function on_sweep_tick(event)
    local registry = Table.get_registry()
    for unit_number, entry in pairs(registry) do
        local e = entry.entity
        if not e or not e.valid then
            Fns.cleanup(unit_number)
        end
    end
end

--==============================================================================
-- 事件：实体死亡清理
--==============================================================================
local function on_entity_died(event)
    local e = event.entity
    if e and e.valid and Table.get_registry()[e.unit_number] then
        Fns.cleanup(e.unit_number)
    end
end

--==============================================================================
-- 存档加载后：按 module_name 重建 def（function 字段不进存档）
--==============================================================================
Event.on_load(function()
    local registry = Table.get_registry()
    for _, entry in pairs(registry) do
        if entry.module_name and not entry.def then
            entry.def = Framework.get_module(entry.module_name)
        end
    end
end)

--==============================================================================
-- 重置（由 amap/main.lua 的 reset_map 调用）
--==============================================================================
function Public.reset_table()
    Table.reset_table()
    Fns.reset_render_store()
end

Event.on_nth_tick(TICK_MAIN, on_main_tick)
Event.on_nth_tick(TICK_SWEEP, on_sweep_tick)
Event.add(defines.events.on_entity_died, on_entity_died)

--==============================================================================
-- 加载 5 个内置 buildings 子模块（触发 register 副作用）
-- 必须放在所有 Public API 定义完之后，子模块 require 时会立即调用
-- Framework.register / Framework.add_building
-- 子模块只 require framework + functions，不 require main（避免循环依赖）
--==============================================================================
require 'maps.amap.pseudo_building.buildings.pulse_tower'
require 'maps.amap.pseudo_building.buildings.repair_tower'
require 'maps.amap.pseudo_building.buildings.build_tower'
require 'maps.amap.pseudo_building.buildings.supply_tower'
require 'maps.amap.pseudo_building.buildings.ammo_tower'
require 'maps.amap.pseudo_building.buildings.bullet_supply_tower'

--==============================================================================
-- 调试命令：/pb <类型> [side]   在玩家脚下创建对应伪建筑
-- 类型动态枚举：自动列出所有已注册的 buildings
--==============================================================================
local function cmd_pb(cmd)
    local player = game.get_player(cmd.player_index)
    if not player or not player.valid or not player.character then
        return
    end
    local arg = cmd.parameter
    if not arg or arg == '' then
        local types = Framework.get_buildings()
        player.print({'', '[伪建筑] 用法: /pb <' .. table.concat(types, '|') .. '> [enemy]'})
        return
    end
    local type_name, side = arg:match('^(%S+)%s*(%S*)$')
    side = (side == 'enemy') and 'enemy' or 'player'
    local spawn_fn = Framework.get_building_spawn_fn(type_name)
    if not spawn_fn then
        player.print({'', '[伪建筑] 未知类型: ' .. tostring(type_name)})
        return
    end
    local surface = player.physical_surface
    local pos = player.physical_position
    local ok, err = pcall(spawn_fn, player, surface, pos, side)
    if not ok then
        player.print({'', '[伪建筑] 创建失败: ' .. tostring(err)})
    else
        player.print({'', '[伪建筑] 已创建: ' .. type_name .. ' @ ' .. math.floor(pos.x) .. ',' .. math.floor(pos.y)})
    end
end

pcall(function()
    commands.add_command('pb', '创建伪建筑: /pb <类型> [enemy]', cmd_pb)
end)

-- 供 RCON 测试 / 外部调试访问
rawset(_G, 'PseudoBuilding', Public)

return Public
