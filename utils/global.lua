local Event = require 'utils.event_core'
local Token = require 'utils.token'

local Global = {}
local concat = table.concat

-- 记录每个 token 的 filepath
local token_filepaths = {}

-- 记录每个 token 期望的数据 keys（从注册时的 tbl 提取）
local token_expected_keys = {}

-- 辅助函数：安全获取 Global.names（存档持久化）
local function get_names()
    if not Global.names then
        Global.names = {}
    end
    return Global.names
end

--- 提取表的顶层 keys（用于错位检测时比较数据结构）
local function get_keys(tbl)
    local keys = {}
    for k in pairs(tbl) do
        keys[#keys + 1] = k
    end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    return keys
end

--- 比较两个 key 列表是否相同
local function keys_match(keys1, keys2)
    if #keys1 ~= #keys2 then
        return false
    end
    for i = 1, #keys1 do
        if keys1[i] ~= keys2[i] then
            return false
        end
    end
    return true
end

--- on_load 时为错位 token 查找正确的数据
-- 不修改 storage 表（Factorio 2.0 禁止 on_load 修改 storage），
-- 而是返回一个 "token -> 正确数据" 的查找表，供各 callback 使用
local function find_correct_data(token)
    local expected_keys = token_expected_keys[token]
    if not expected_keys then
        return nil
    end

    local stored = Token.get_global(token)
    if stored == nil then
        return nil
    end

    -- 检查当前 token 的数据是否匹配
    if type(stored) == 'table' then
        local stored_keys = get_keys(stored)
        if keys_match(expected_keys, stored_keys) then
            return stored
        end
    end

    -- 错位：在 storage.tokens 中搜索匹配的数据
    if not storage.tokens then
        return nil
    end

    local expected_sig = concat(expected_keys, ',')
    for _, data in pairs(storage.tokens) do
        if type(data) == 'table' then
            local data_keys = get_keys(data)
            local sig = concat(data_keys, ',')
            if sig == expected_sig then
                return data
            end
        end
    end

    -- 没找到匹配的，返回原始数据（让错误自然暴露）
    return stored
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

    -- 记录 token -> filepath 映射
    token_filepaths[token] = filepath

    -- 记录 token 期望的数据 keys（用于 on_load 错位检测）
    if type(tbl) == 'table' then
        token_expected_keys[token] = get_keys(tbl)
    end

    local names = get_names()
    names[token] = concat {token, ' - ', filepath}

    -- on_init：初始化 storage.tokens + 执行 callback
    ensure_init_globals()
    Event.on_init(
        function()
            callback(Token.get_global(token))
        end
    )

    -- on_load：检测错位，找到正确数据传给 callback
    -- 不修改 storage 表，避免触发 Factorio 2.0 的 CRC 校验
    Event.on_load(
        function()
            local correct_data = find_correct_data(token)
            callback(correct_data)
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

    if type(tbl) == 'table' then
        token_expected_keys[token] = get_keys(tbl)
    end

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

    -- on_load：检测错位，找到正确数据传给 callback
    Event.on_load(
        function()
            local correct_data = find_correct_data(token)
            callback(correct_data)
        end
    )

    return token
end

return Global