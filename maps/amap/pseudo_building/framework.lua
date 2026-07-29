-- maps/amap/pseudo_building/framework.lua
-- 伪建筑框架核心：注册中心 + 查询 API（极简，零业务逻辑）
--
-- 设计原则（参照副本框架 world/framework.lua）：
--   1. 只暴露 register / get / get_registered_xxx / query 等查询 API
--   2. 绝不 require 任何子模块或 functions.lua（保持纯被动数据池）
--   3. 内部用两张 local 表：modules[type_name]=def + buildings[type_name]=spawn_fn
--   4. 子模块通过 register/add_building 顶层副作用注册
--
-- 依赖：utils.global（仅用于 main.lua on_load 时取 table.lua 引用，此处不直接依赖）

local Public = {}

--==============================================================================
-- 常量（暴露给外部模块使用）
--==============================================================================
Public.FORCE_PLAYER = 'framework_player'
Public.FORCE_ENEMY = 'enemy'
Public.PLAYER_LIMIT = 3
Public.ENEMY_LIMIT = 10

-- 三类底层原型
Public.PROTOTYPE = {
    attack = 'laser-turret',
    storage = 'passive-provider-chest',
    power = 'assembling-machine-3',
}

--==============================================================================
-- 注册中心（local，加载期静态数据，不进 storage）
--==============================================================================
local modules = {}       -- type_name -> def（钩子集合）
local buildings = {}     -- type_name -> spawn_fn(player, surface, position, side) -> entry

--==============================================================================
-- 注册 API（子模块用）
--==============================================================================
function Public.register(type_name, def)
    modules[type_name] = def
    return def
end

function Public.add_building(type_name, spawn_fn)
    buildings[type_name] = spawn_fn
    return spawn_fn
end

--==============================================================================
-- 查询 API（调用方用）
--==============================================================================
function Public.get_module(type_name)
    return modules[type_name]
end

function Public.get_buildings()
    -- 返回已注册 type_name 列表（升序，供调试命令等动态枚举）
    local out = {}
    for name in pairs(buildings) do out[#out + 1] = name end
    table.sort(out)
    return out
end

function Public.get_building_spawn_fn(type_name)
    return buildings[type_name]
end

function Public.get_registered_types()
    -- modules 表的所有 type_name（与 buildings 一致，但用于纯 register 校验）
    local out = {}
    for name in pairs(modules) do out[#out + 1] = name end
    table.sort(out)
    return out
end

return Public
