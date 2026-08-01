local Task = require 'utils.task'
local Token = require 'utils.token'

local Public = {}

-- 临时修改 Force 数值类 modifier 并在到期后还原的模板。
-- 还原用「当前值 - bonus」的差值写法（与 balance.lua 先例一致）：
-- 即使期间有其他逻辑再改该字段，本模板只归还自己加上的部分，不覆盖他人改动。
-- 支持 method：Force 的 get_<method>/set_<method> 成对方法，
-- 如 'ammo_damage_modifier'、'gun_speed_modifier'（对应 get_ammo_damage_modifier(kind) 等）。

local function revert_modifier(params)
    local force_name, method, kind, bonus = params[1], params[2], params[3], params[4]
    local force = game.forces[force_name]
    if not force then
        return
    end
    local get = force['get_' .. method]
    local set = force['set_' .. method]
    if not get or not set then
        return
    end
    set(kind, get(kind) - bonus)
end

local revert = Token.register(revert_modifier)

--- 对 force 的 method 字段临时加 bonus，duration_ticks 后差值还原。
-- @param force  Force 对象（运行时调用，勿持久化引用）
-- @param method 如 'ammo_damage_modifier' / 'gun_speed_modifier'
-- @param kind   如 'laser' / 'artillery'（modifier 的种类参数）
-- @param bonus  临时增加量（可为负）
-- @param duration_ticks 持续时间，到期后自动还原
function Public.apply(force, method, kind, bonus, duration_ticks)
    local get = force['get_' .. method]
    local set = force['set_' .. method]
    if not get or not set then
        error('force 不支持 modifier 方法: ' .. method, 2)
    end
    set(kind, get(kind) + bonus)
    Task.set_timeout_in_ticks(duration_ticks, revert, {force.name, method, kind, bonus})
end
return Public
