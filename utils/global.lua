local Event = require 'utils.event_core'
local Token = require 'utils.token'

local Global = {}
local concat = table.concat

-- 记录每个 token 的 filepath，用于 on_load 时 token 错位检测与迁移
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

--- on_load 时执行 token 错位迁移
-- 遍历所有已注册 token，检查 storage.tokens 中的数据 keys 是否与期望一致
-- 如果不一致，在 storage.tokens 中找到匹配的数据并交换位置
local function migrate_misaligned_tokens()
    if not storage.tokens then
        return
    end

    -- 第一遍：找出所有错位的 token
    local misaligned = {}
    for token, expected_keys in pairs(token_expected_keys) do
        local stored = storage.tokens[token]
        if stored ~= nil then
            local stored_keys = get_keys(stored)
            if not keys_match(expected_keys, stored_keys) then
                misaligned[#misaligned + 1] = token
            end
        end
    end

    if #misaligned == 0 then
        return
    end

    -- 第二遍：为每个错位 token 找到正确的数据
    -- 构建 "key签名 -> token" 的映射，用于快速查找
    local expected_sig_to_token = {}
    for token, expected_keys in pairs(token_expected_keys) do
        local sig = concat(expected_keys, ',')
        expected_sig_to_token[sig] = token
    end

    -- 遍历 storage.tokens，按 key 签名找到正确的归属
    local remap = {}
    for stored_token, stored_data in pairs(storage.tokens) do
        if type(stored_data) == 'table' then
            local stored_keys = get_keys(stored_data)
            local sig = concat(stored_keys, ',')
            local target_token = expected_sig_to_token[sig]
            if target_token and target_token ~= stored_token then
                remap[target_token] = stored_data
            end
        end
    end

    -- 第三遍：应用重映射
    for target_token, correct_data in pairs(remap) do
        storage.tokens[target_token] = correct_data
    end
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

-- 标记 on_load 迁移是否已注册
local migration_registered = false

--- 注册 on_load 迁移回调（仅注册一次）
local function ensure_migration()
    if migration_registered then
        return
    end
    migration_registered = true
    Event.on_load(
        function()
            migrate_misaligned_tokens()
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

    -- on_load：先注册迁移回调，再恢复数据
    ensure_migration()
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

    -- on_load：先注册迁移回调，再恢复数据
    ensure_migration()
    Event.on_load(
        function()
            callback(Token.get_global(token))
        end
    )

    return token
end

return Global