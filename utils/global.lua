local Event = require 'utils.event_core'
local Token = require 'utils.token'

local Global = {} -- 这是模块表，函数应该定义在这里，而不是 storage 里
local concat = table.concat

-- 辅助函数：安全获取 storage.names
local function get_names()
    if not Global.names then
        Global.names = {}
    end
    return Global.names
end

-- 【修改点1】将 storage.register 改为 Global.register
function Global.register(tbl, callback)
    if _LIFECYCLE and _LIFECYCLE ~= _STAGE.control then
        error('can only be called during the control stage', 2)
    end

    -- If _LIFECYCLE is not defined yet, we'll register it later
    if not _LIFECYCLE then
        Event.on_load(
            function()
                Global.register(tbl, callback) -- 注意这里递归调用也要改名
            end
        )
        return
    end

    local source = debug.getinfo(2, 'S').source
    local filepath = source:match('^.+/currently%-playing/(.+)$') or source:match('^.+scenarios/坦克保卫战/(.+)$')
    if filepath then
        filepath = filepath:sub(1, -5)
    else
        filepath = source
    end
    local token = Token.register_global(tbl)

    -- 【修改点2】使用 get_names() 确保读写的是存档数据，而不是本地临时变量
    local names = get_names()
    names[token] = concat {token, ' - ', filepath}

    Event.on_load(
        function()
            callback(Token.get_global(token))
        end
    )

    return token
end

-- 【修改点3】将 storage.register_init 改为 Global.register_init
function Global.register_init(tbl, init_handler, callback)
    if _LIFECYCLE and _LIFECYCLE ~= _STAGE.control then
        error('can only be called during the control stage', 2)
    end

    -- If _LIFECYCLE is not defined yet, we'll register it later
    if not _LIFECYCLE then
        Event.on_load(
            function()
                Global.register_init(tbl, init_handler, callback) -- 注意递归调用也要改名
            end
        )
        return
    end

    local source = debug.getinfo(2, 'S').source
    local filepath = source:match('^.+/currently%-playing/(.+)$') or source:match('^.+scenarios/坦克保卫战/(.+)$')
    if filepath then
        filepath = filepath:sub(1, -5)
    else
        filepath = source
    end
    local token = Token.register_global(tbl)

    -- 使用 get_names()
    local names = get_names()
    names[token] = concat {token, ' - ', filepath}

    Event.on_init(
        function()
            init_handler(tbl)
            callback(tbl)
        end
    )

    Event.on_load(
        function()
            callback(Token.get_global(token))
        end
    )

    return token
end

return Global