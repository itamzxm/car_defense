local Event = require 'utils.event'

local Public = {}

local click_handlers = {}
local text_changed_handlers = {}
local selection_state_changed_handlers = {}
local checked_state_changed_handlers = {}
local closed_handlers = {}
local value_changed_handlers = {}
local elem_changed_handlers = {}

-- _DEBUG 时记录「元素名 → 注册文件:行号」，回答「这个按钮是哪注册的」（生产零开销）
local registered_map = {}

local function record_registration(element_name)
    if not _DEBUG then
        return
    end
    local info = debug.getinfo(2, 'S')
    registered_map[element_name] = (info.source or '?') .. ':' .. info.currentline
end

function Public.register_click(element_name, handler)
    if _LIFECYCLE == 8 then
        error('Calling GuiDispatcher.register_click after on_init() or on_load() has run is a desync risk.', 2)
    end
    record_registration(element_name)
    click_handlers[element_name] = handler
end

function Public.register_text_changed(element_name, handler)
    if _LIFECYCLE == 8 then
        error('Calling GuiDispatcher.register_text_changed after on_init() or on_load() has run is a desync risk.', 2)
    end
    record_registration(element_name)
    text_changed_handlers[element_name] = handler
end

function Public.register_selection_state_changed(element_name, handler)
    if _LIFECYCLE == 8 then
        error('Calling GuiDispatcher.register_selection_state_changed after on_init() or on_load() has run is a desync risk.', 2)
    end
    record_registration(element_name)
    selection_state_changed_handlers[element_name] = handler
end

function Public.register_checked_state_changed(element_name, handler)
    if _LIFECYCLE == 8 then
        error('Calling GuiDispatcher.register_checked_state_changed after on_init() or on_load() has run is a desync risk.', 2)
    end
    record_registration(element_name)
    checked_state_changed_handlers[element_name] = handler
end

function Public.register_closed(element_name, handler)
    if _LIFECYCLE == 8 then
        error('Calling GuiDispatcher.register_closed after on_init() or on_load() has run is a desync risk.', 2)
    end
    record_registration(element_name)
    closed_handlers[element_name] = handler
end

function Public.register_value_changed(element_name, handler)
    if _LIFECYCLE == 8 then
        error('Calling GuiDispatcher.register_value_changed after on_init() or on_load() has run is a desync risk.', 2)
    end
    record_registration(element_name)
    value_changed_handlers[element_name] = handler
end

function Public.register_elem_changed(element_name, handler)
    if _LIFECYCLE == 8 then
        error('Calling GuiDispatcher.register_elem_changed after on_init() or on_load() has run is a desync risk.', 2)
    end
    record_registration(element_name)
    elem_changed_handlers[element_name] = handler
end

--- _DEBUG 时返回元素注册位置（'文件:行号'）；未注册或非调试返回 nil
function Public.get_registration(element_name)
    if not _DEBUG then
        return nil
    end
    return registered_map[element_name]
end

local function on_gui_click(event)
    local element = event.element
    if not element or not element.valid then return end
    local handler = click_handlers[element.name]
    if not handler then return end
    local player = game.get_player(event.player_index)
    if not (player and player.valid) then return end
    event.player = player
    handler(event)
end

local function on_gui_text_changed(event)
    local element = event.element
    if not element or not element.valid then return end
    local handler = text_changed_handlers[element.name]
    if not handler then return end
    local player = game.get_player(event.player_index)
    if not (player and player.valid) then return end
    event.player = player
    handler(event)
end

local function on_gui_selection_state_changed(event)
    local element = event.element
    if not element or not element.valid then return end
    local handler = selection_state_changed_handlers[element.name]
    if not handler then return end
    local player = game.get_player(event.player_index)
    if not (player and player.valid) then return end
    event.player = player
    handler(event)
end

local function on_gui_checked_state_changed(event)
    local element = event.element
    if not element or not element.valid then return end
    local handler = checked_state_changed_handlers[element.name]
    if not handler then return end
    local player = game.get_player(event.player_index)
    if not (player and player.valid) then return end
    event.player = player
    handler(event)
end

local function on_gui_closed(event)
    local element = event.element
    if not element or not element.valid then return end
    local handler = closed_handlers[element.name]
    if not handler then return end
    local player = game.get_player(event.player_index)
    if not (player and player.valid) then return end
    event.player = player
    handler(event)
end

local function on_gui_value_changed(event)
    local element = event.element
    if not element or not element.valid then return end
    local handler = value_changed_handlers[element.name]
    if not handler then return end
    local player = game.get_player(event.player_index)
    if not (player and player.valid) then return end
    event.player = player
    handler(event)
end

local function on_gui_elem_changed(event)
    local element = event.element
    if not element or not element.valid then return end
    local handler = elem_changed_handlers[element.name]
    if not handler then return end
    local player = game.get_player(event.player_index)
    if not (player and player.valid) then return end
    event.player = player
    handler(event)
end

Event.add(defines.events.on_gui_click, on_gui_click)
Event.add(defines.events.on_gui_text_changed, on_gui_text_changed)
Event.add(defines.events.on_gui_selection_state_changed, on_gui_selection_state_changed)
Event.add(defines.events.on_gui_checked_state_changed, on_gui_checked_state_changed)
Event.add(defines.events.on_gui_closed, on_gui_closed)
Event.add(defines.events.on_gui_value_changed, on_gui_value_changed)
Event.add(defines.events.on_gui_elem_changed, on_gui_elem_changed)

return Public
