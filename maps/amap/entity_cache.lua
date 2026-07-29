local Public = {}
local Table = require 'maps.amap.table'

local SEARCH_RADIUS = 35
local CACHE_EXPIRE_TIME = 180
local NEARBY_DISTANCE_THRESHOLD = 10
local INTERESTING_TYPES =  {'unit', 'turret', 'unit-spawner','combat-robot','spider-leg','spider-unit'}

local function cleanup_expired_cache()
    local current_tick = game.tick
    if not Table.get().entity_search_cache then
        return
    end
    
    local cache = Table.get().entity_search_cache
    for key, cache_entry in pairs(cache) do
        if current_tick - cache_entry.tick >= CACHE_EXPIRE_TIME then
            cache[key] = nil
        end
    end
end

script.on_nth_tick(180, cleanup_expired_cache)


--只支持搜索敌方阵营
--并且类型必须完全相同！
local function get_position(source)
    if not source then
        return nil
    end
    
    if type(source) == 'table' and source.x and source.y then
        return {x = source.x, y = source.y}
    end
    
    if type(source) == 'userdata' and source.valid and source.position then
        return {x = source.position.x, y = source.position.y}
    end
    
    return nil
end

local function get_position_key(surface, position)
    local grid_x = math.floor(position.x / NEARBY_DISTANCE_THRESHOLD)
    local grid_y = math.floor(position.y / NEARBY_DISTANCE_THRESHOLD)
    return surface.name .. '_' .. grid_x .. '_' .. grid_y
end

local function build_lookup_table(array)
    local lookup = {}
    for _, value in ipairs(array) do
        lookup[value] = true
    end
    return lookup
end

local function matches_value(value, target)
    if type(target) == 'table' then
        return target[value] == true
    end
    return value == target
end

local function filter_entities(entities, filters, position)
    local result = {}
    local radius = filters.radius or SEARCH_RADIUS
    local min_x = position.x - radius
    local max_x = position.x + radius
    local min_y = position.y - radius
    local max_y = position.y + radius
    local insert = table.insert
    
    for _, entity in pairs(entities) do
        if entity and entity.valid and entity.health and entity.health > 0 then
            local pos = entity.position
            local px = pos.x
            local py = pos.y
            
            if px >= min_x and px <= max_x and py >= min_y and py <= max_y then
                insert(result, entity)
            end
        end
    end
    return result
end

function Public.find_entities_cached(surface, filters)
    if filters.area then
        return surface.find_entities_filtered(filters)
    end
    
    local position = get_position(filters.position)
    
    if not position then
        game.print("没有位置，拒绝搜索")
        return {}
    end

    if not filters.radius then
        game.print("没有半径，拒绝搜索")
        return {}
    end

    local pos_key = get_position_key(surface, position)
    local cache_key = pos_key
    local current_tick = game.tick
    if not Table.get().entity_search_cache then
        Table.get().entity_search_cache = {}
    end
    
    local cache = Table.get().entity_search_cache
    if Table.get().entity_search_cache[cache_key] then
        local cache_entry = Table.get().entity_search_cache[cache_key]
        local result = filter_entities(cache_entry.entities, filters, position)
        
        if filters.limit and #result > filters.limit then
            local limited_result = {}
            for i = 1, filters.limit do
                limited_result[i] = result[i]
            end
            return limited_result
        end
        return result
    end

    local search_filters = {
        position = position,
        radius = SEARCH_RADIUS,
        type = INTERESTING_TYPES,
        force = 'enemy'
    }

    local entity_count = surface.count_entities_filtered(search_filters)

    if entity_count == 0 then
        Table.get().entity_search_cache[cache_key] = {
            entities = {},
            tick = current_tick
        }
        return {}
    end

    local entities = surface.find_entities_filtered(search_filters)
    local all_entities = {}
    local search_radius = filters.radius or SEARCH_RADIUS
    local min_x = position.x - search_radius
    local max_x = position.x + search_radius
    local min_y = position.y - search_radius
    local max_y = position.y + search_radius
    local insert = table.insert

    for _, entity in pairs(entities) do
        if entity and entity.valid then
            local pos = entity.position
            local px = pos.x
            local py = pos.y
            
            if px >= min_x and px <= max_x and py >= min_y and py <= max_y then
                insert(all_entities, entity)
            end
        end
    end

    Table.get().entity_search_cache[cache_key] = {
        entities = all_entities,
        tick = current_tick
    }

    local result = filter_entities(all_entities, filters, position)
    
    if filters.limit and #result > filters.limit then
        local limited_result = {}
        for i = 1, filters.limit do
            limited_result[i] = result[i]
        end
        return limited_result
    end

    return result
end

function Public.clear_cache()
    Table.get().entity_search_cache = {}
end

function Public.get_cache_size()
    local count = 0
    for _ in pairs(Table.get().entity_search_cache) do
        count = count + 1
    end
    return count
end

return Public
