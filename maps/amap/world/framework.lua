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

local Public = {}

--==============================================================================
-- 内部数据
--==============================================================================

-- world_id -> def（世界完整定义）
local registered = {}

-- config_name -> surface_config（共享地表资源配置，多个世界可引用同一份）
local surface_configs = {}

--==============================================================================
-- 注册 API（世界模块调用）
--==============================================================================

--- 注册一个世界
-- @param world_id number 世界编号（如 7）
-- @param def table 世界定义，包含所有配置字段
function Public.register(world_id, def)
    registered[world_id] = def
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
