local Event = require 'utils.event_core'
local Token = require 'utils.token'

local Global = {}
local concat = table.concat

-- 记录每个 token 的 filepath，用于 on_load 时 token 错位检测与迁移
local token_filepaths = {}

-- 辅助函数：安全获取 Global.names（存档持久化）
local function get_names()
    if not Global.names then
        Global.names = {}
    end
    return Global.names
end

-- 标记 on_init 是否已注册过 Token.init_globals
local init_globals_registered = false

--- 注册 Token.init_globals 到 on_init（仅注册一次）
-- 所有 Global.register / Global.register_init 共享同一个 on_init 回调，
-- 确保 storage.tokens 在新游戏时被正确初始化
local function ensure_init_globals()
    if init_globals_registered then
        return
    end
    init_globals_registered = true
    Event.on_init(
        function()
            Token.init_globals()
        end
    )
end

function Global.register(tbl, callback)
    if _LIFECYCLE and _LIFECYCLE ~= _STAGE.control then
        error('can only be called during the control stage', 2)
    end

    if not _LIFECYCLE then
        Event.on_load(
            function()
                Global.register(tbl, callback)
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

    -- 记录 token -> filepath 映射，用于 on_load 时错位检测
    token_filepaths[token] = filepath

    local names = get_names()
    names[token] = concat {token, ' - ', filepath}

    -- on_init：初始化 storage.tokens + 执行 callback
    ensure_init_globals()
    Event.on_init(
        function()
            callback(Token.get_global(token))
        end
    )

    -- on_load：从 storage.tokens 恢复数据
    Event.on_load(
        function()
            callback(Token.get_global(token))
        end
    )

    return token
end

function Global.register_init(tbl, init_handler, callback)
    if _LIFECYCLE and _LIFECYCLE ~= _STAGE.control then
        error('can only be called during the control stage', 2)
    end

    if not _LIFECYCLE then
        Event.on_load(
            function()
                Global.register_init(tbl, init_handler, callback)
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

    token_filepaths[token] = filepath

    local names = get_names()
    names[token] = concat {token, ' - ', filepath}

    -- on_init：初始化 storage.tokens + init_handler + callback
    ensure_init_globals()
    Event.on_init(
        function()
            init_handler(tbl)
            callback(tbl)
        end
    )

    -- on_load：从 storage.tokens 恢复数据
    Event.on_load(
        function()
            callback(Token.get_global(token))
        end
    )

    return token
end

return Global