local Event = require 'utils.event'
local Token = require 'utils.token'

local Public = {}

--- 创建「按需启停」的周期任务句柄。
-- 用法：加载期 Public.create(interval, func) 一次；运行时 handle.enable() / handle.disable()。
-- func 在加载期被 Token.register 包装持久化，因此 enable/disable 可在运行时安全调用
-- （Event.add_removable_nth_tick 允许运行时增删，见 event.lua 顶部说明）。
-- 适用场景：有活动才需要跑、无活动应注销的周期逻辑（避免常驻空转每 tick 空扫描）。
function Public.create(interval, func)
    if _LIFECYCLE == 8 then
        error('Calling ActiveInterval.create after on_init() or on_load() has run is a desync risk.', 2)
    end
    local token = Token.register(func)
    local state = {interval = interval, token = token, active = false}

    return {
        enable = function()
            if state.active then
                return
            end
            Event.add_removable_nth_tick(state.interval, state.token)
            state.active = true
        end,
        disable = function()
            if not state.active then
                return
            end
            Event.remove_removable_nth_tick(state.interval, state.token)
            state.active = false
        end,
        is_active = function()
            return state.active
        end
    }
end

return Public
