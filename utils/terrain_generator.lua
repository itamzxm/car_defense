local Global = require 'utils.global'
local Task = require 'utils.task'
local Token = require 'utils.token'

local Public = {}

local this = {queue = {}, running = false}

Global.register(this, function(tbl)
    this = tbl
end)

local DEFAULT_PER_TICK = 32

local process_queue

--- 将大批量铺 tile 任务加入队列，按每 tick 一批的方式分帧执行，
-- 避免一次性 set_tiles 造成单帧卡顿。队列持久化，中途存档后继续执行。
-- @param surface 目标表面
-- @param tiles   tile 数组，元素形如 { position = {x=.., y=..}, name = 'tile-name' }
-- @param per_tick 每 tick 铺放数量（默认 32）
function Public.enqueue(surface, tiles, per_tick)
    if not tiles or #tiles == 0 then
        return
    end
    table.insert(this.queue, {surface_index = surface.index, tiles = tiles, cursor = 0, per_tick = per_tick})
    if not this.running then
        this.running = true
        Task.set_timeout_in_ticks(1, process_queue)
    end
end

--- 队列是否为空
function Public.is_empty()
    return next(this.queue) == nil
end

local function process_entry(entry)
    local surface = game.surfaces[entry.surface_index]
    if not surface then
        return true
    end
    local per_tick = entry.per_tick or DEFAULT_PER_TICK
    local tiles = entry.tiles
    local count = math.min(per_tick, #tiles - entry.cursor)
    local batch = {}
    for i = 1, count do
        local t = tiles[entry.cursor + i]
        batch[i] = {position = t.position, name = t.name}
    end
    surface.set_tiles(batch, true)
    entry.cursor = entry.cursor + count
    return entry.cursor >= #tiles
end

local function remove_entry(entries, index)
    for i = index, #entries - 1 do
        entries[i] = entries[i + 1]
    end
    entries[#entries] = nil
end

process_queue =
    Token.register(
    function()
        local queue = this.queue
        for i = #queue, 1, -1 do
            if process_entry(queue[i]) then
                remove_entry(queue, i)
            end
        end
        if next(queue) then
            Task.set_timeout_in_ticks(1, process_queue)
        else
            this.running = false
        end
    end
)

-- _DEBUG 时暴露内部 token，便于 RCON 诊断（生产无此字段，不影响使用）
if _DEBUG then
    Public._process_token = process_queue
end

return Public
