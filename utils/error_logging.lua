--[[
    This module writes trapped lua errors to a dedicated file (script-output/car_defense_errors.log),
    separate from the game log. It is possible that this module misses errors, therefore users
    should also verify their server/game logs.
    This module must stay dependency-free (no requires) because it is required from utils.event_core,
    which loads first; requiring utils.server here would create a require cycle.
]]

local floor = math.floor
local insert = table.insert
local concat = table.concat
local xpcall = xpcall
local trace = debug.traceback

local minutes_to_ticks = 60 * 60
local hours_to_ticks = 60 * 60 * 60
local ticks_to_minutes = 1 / minutes_to_ticks
local ticks_to_hours = 1 / hours_to_ticks
local warning = '\n\n\n\nTHIS LOG IS NOT ALL-INCLUSIVE AND CAN MISS ERRORS. IF THERE ARE ANY SUSPICIONS OF ERRORS CHECK THE LOGS.\n\n\n\n'

local Public = {}
local first_error = true

--- Turns ticks into a human-readable time.
local function format_time(ticks)
    if type(ticks) ~= 'number' then
        return 'unknown time'
    end

    local result = {}

    local hours = floor(ticks * ticks_to_hours)
    if hours > 0 then
        ticks = ticks - hours * hours_to_ticks
        insert(result, hours)
        if hours == 1 then
            insert(result, 'hour')
        else
            insert(result, 'hours')
        end
    end

    local minutes = floor(ticks * ticks_to_minutes)
    insert(result, minutes)
    if minutes == 1 then
        insert(result, 'minute')
    else
        insert(result, 'minutes')
    end

    return concat(result, ' ')
end

local function try_generate_report(str)
    if not game then
        return
    end

    if first_error then
        str = warning .. str
        first_error = nil
    end

    local tick = 'Time of error: ' .. format_time(game.tick)

    local version = storage.car_defense_version or 'Unknown'
    version = 'Car Defense version: ' .. version

    local output = concat({tick, version, str, '\n'}, '\n')

    helpers.write_file('car_defense_errors.log', output, true, 0)
end

--- Takes the given string and appends an entry to the error file.
function Public.generate_error_report(str)
    local success, result = xpcall(try_generate_report, Public.error_handler, str)
    if not success then
        log(result)
    end
end

function Public.error_handler(err)
    return trace(err)
end

return Public
