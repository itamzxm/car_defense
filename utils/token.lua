local Token = {}

local tokens = {}

local counter = 200

--- Assigns a unquie id for the given var.
-- This function cannot be called after on_init() or on_load() has run as that is a desync risk.
-- Typically this is used to register functions, so the id can be stored in the global table
-- instead of the function. This is becasue closures cannot be safely stored in the global table.
-- @param  var<any>
-- @return number the unique token for the variable.
function Token.register(var)
    if _LIFECYCLE == 8 then
        error('Calling Token.register after on_init() or on_load() has run is a desync risk.', 2)
    end

    counter = counter + 1

    tokens[counter] = var

    return counter
end

function Token.get(token_id)
    return tokens[token_id]
end

-- 独立计数器：token 分配不再依赖 storage.tokens 内容，
-- 避免 control stage 写入 storage 违反 Factorio 2.0 生命周期规范
local global_counter = 0

-- 注册表：记录每个 global token 的初始值，供 on_init 时批量写入 storage.tokens
local global_registry = {}

function Token.register_global(var)
    global_counter = global_counter + 1
    local c = global_counter

    global_registry[c] = var

    return c
end

--- on_init 时调用：将 global_registry 中的初始值写入 storage.tokens
-- Factorio 2.0 官方文档要求 storage 初始化在 on_init 中完成，
-- 不应在 control stage（模块加载期）写入 storage
function Token.init_globals()
    if not storage.tokens then
        storage.tokens = {}
    end
    for k, v in pairs(global_registry) do
        if storage.tokens[k] == nil then
            storage.tokens[k] = v
        end
    end
end

function Token.get_global(token_id)
    return storage.tokens[token_id]
end

function Token.set_global(token_id, var)
    storage.tokens[token_id] = var
end

local uid_counter = 100

function Token.uid()
    uid_counter = uid_counter + 1

    return uid_counter
end

return Token
