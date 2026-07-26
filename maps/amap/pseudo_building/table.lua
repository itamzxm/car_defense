-- maps/amap/pseudo_building/table.lua
-- 伪建筑数据表：Global 框架管理的运行时状态
--
-- 设计原则（参照 world/world_table.lua）：
--   1. 所有需要跨 tick 持久化、需要多人存档同步的数据放这里
--   2. 通过 Public.get / Public.set 访问，不直接暴露内部表
--   3. reset_table 在 main.lua 的 reset_map 中调用
--   4. 渲染对象（LuaRenderObject）不可序列化，不放这里，由 functions.lua 运行期持有
--
-- 依赖：utils.global / utils.event

local Global = require 'utils.global'
local Event = require 'utils.event'

local this = {
    registry = {},          -- [unit_number] = entry，建筑注册表（核心数据）
}
local Public = {}

Global.register(
    this,
    function(tbl)
        this = tbl
    end
)

--==============================================================================
-- 访问器
--==============================================================================
function Public.get(key)
    if key then
        return this[key]
    else
        return this
    end
end

function Public.set(key, value)
    if key and (value or value == false) then
        this[key] = value
        return this[key]
    elseif key then
        return this[key]
    else
        return this
    end
end

-- registry 直接引用（供 main.lua / functions.lua 高频访问）
function Public.get_registry()
    return this.registry
end

--==============================================================================
-- 重置（由 main.lua 的 reset_map 调用）
--==============================================================================
function Public.reset_table()
    this.registry = {}
end

-- on_init 由 main.lua 统一注册，这里不重复

return Public
