local Token = require 'utils.token'
local Event = require 'utils.event'
local Global = require 'utils.global'
local SpamProtection = require 'utils.spam_protection'
local mod_gui = require('__core__/lualib/mod-gui')

local tostring = tostring
local next = next

local Gui = {}

local data = {}
local element_map = {}
local settings = {}

Gui.token =
    Global.register(
    {data = data, element_map = element_map, settings = settings},
    function(tbl)
        data = tbl.data
        element_map = tbl.element_map
        settings = tbl.settings
    end
)

-- handler_factory 的 handlers 表——模块级 local，不存入 global（函数无法序列化）。
-- 使用 Gui.on_click 注册 handler 的代码必须确保：
-- 1. handler 在模块加载时注册（而非运行时），或
-- 2. handler 仅修改玩家本地 GUI 状态，不修改 global/shared 状态。
-- 违反此规则会在新玩家加入后触发 desync。
local gui_click_handlers = {}
local gui_custom_close_handlers = {}
local gui_checked_state_handlers = {}
local gui_elem_changed_handlers = {}
local gui_selection_state_handlers = {}
local gui_text_changed_handlers = {}
local gui_value_changed_handlers = {}

local on_visible_handlers = {}
local on_pre_hidden_handlers = {}

function Gui.uid_name()
    return tostring(Token.uid())
end

function Gui.uid()
    return Token.uid()
end

-- Associates data with the LuaGuiElement. If data is nil then removes the data
function Gui.set_data(element, value)
    local player_index = element.player_index
    local values = data[player_index]

    if value == nil then
        if not values then
            return
        end

        values[element.index] = nil

        if next(values) == nil then
            data[player_index] = nil
        end
    else
        if not values then
            values = {}
            data[player_index] = values
        end

        values[element.index] = value
    end
end
local set_data = Gui.set_data

-- Gets the Associated data with this LuaGuiElement if any.
function Gui.get_data(element)
    if not element then
        return
    end

    local player_index = element.player_index

    local values = data[player_index]
    if not values then
        return nil
    end

    return values[element.index]
end

local remove_data_recursively
-- Removes data associated with LuaGuiElement and its children recursively.
function Gui.remove_data_recursively(element)
    set_data(element, nil)

    local children = element.children

    if not children then
        return
    end

    for _, child in next, children do
        if child.valid then
            remove_data_recursively(child)
        end
    end
end
remove_data_recursively = Gui.remove_data_recursively

local remove_children_data
function Gui.remove_children_data(element)
    local children = element.children

    if not children then
        return
    end

    for _, child in next, children do
        if child.valid then
            set_data(child, nil)
            remove_children_data(child)
        end
    end
end
remove_children_data = Gui.remove_children_data

function Gui.destroy(element)
    remove_data_recursively(element)
    element.destroy()
end

function Gui.clear(element)
    remove_children_data(element)
    element.clear()
end

local function clear_invalid_data()
    if settings.disable_clear_invalid_data then
        return
    end

    for _, player in pairs(game.players) do
        local player_index = player.index
        local values = data[player_index]
        if values then
            for k, element in next, values do
                if type(element) == 'table' then
                    for key, obj in next, element do
                        if type(obj) == 'table' and obj.valid ~= nil then
                            if not obj.valid then
                                element[key] = nil
                            end
                        end
                    end
                    if type(element) == 'userdata' and not element.valid then
                        values[k] = nil
                    end
                end
            end
        end
    end
end
Event.on_nth_tick(300, clear_invalid_data)

local function handler_factory(event_id, handlers)
    -- handlers 表必须在 global 中持久化（见顶部 Global.register），
    -- 否则新连接客户端会丢失所有已注册的 GUI 回调，导致 desync。

    local function on_event(event)
        local element = event.element
        if not element or not element.valid then
            return
        end

        local handler = handlers[element.name]
        if type(handler) ~= 'function' then
            -- 新连接客户端：handler 函数无法序列化，表结构保留但值为 nil。
            -- 此时静默跳过——该 GUI 的注册流程会在下次相关事件触发时重新执行。
            return
        end

        local player = game.get_player(event.player_index)
        if not (player and player.valid) then
            return
        end

        if not event.text then
            local is_spamming = SpamProtection.is_spamming(player, nil, 'UtilsGUI Handler')
            if is_spamming then
                return
            end
        end

        event.player = player

        handler(event)
    end

    -- 在 control stage（模块加载时）注册，避免运行时惰性注册的 desync 风险
    Event.add(event_id, on_event)

    return function(element_name, handler)
        handlers[element_name] = handler
    end
end

local function custom_handler_factory(handlers)
    return function(element_name, handler)
        handlers[element_name] = handler
    end
end

--luacheck: ignore custom_raise
local function custom_raise(handlers, element, player)
    local handler = handlers[element.name]
    if not handler then
        return
    end

    handler({element = element, player = player})
end

-- Disabled the handler so it does not clean then data table of invalid data.
function Gui.set_disable_clear_invalid_data(value)
    settings.disable_clear_invalid_data = value or false
end

-- Gets state if the cleaner handler is active or false
function Gui.get_disable_clear_invalid_data()
    return settings.disable_clear_invalid_data
end

-- Register a handler for the on_gui_checked_state_changed event for LuaGuiElements with element_name.
-- Can only have one handler per element name.
-- Guarantees that the element and the player are valid when calling the handler.
-- Adds a player field to the event table.
Gui.on_checked_state_changed = handler_factory(defines.events.on_gui_checked_state_changed, gui_checked_state_handlers)
Gui.on_click = handler_factory(defines.events.on_gui_click, gui_click_handlers)
Gui.on_custom_close = handler_factory(defines.events.on_gui_closed, gui_custom_close_handlers)
Gui.on_elem_changed = handler_factory(defines.events.on_gui_elem_changed, gui_elem_changed_handlers)
Gui.on_selection_state_changed = handler_factory(defines.events.on_gui_selection_state_changed, gui_selection_state_handlers)
Gui.on_text_changed = handler_factory(defines.events.on_gui_text_changed, gui_text_changed_handlers)
Gui.on_value_changed = handler_factory(defines.events.on_gui_value_changed, gui_value_changed_handlers)

-- Register a handler for when the player shows the top LuaGuiElements with element_name.
-- Assuming the element_name has been added with Gui.allow_player_to_toggle_top_element_visibility.
-- Can only have one handler per element name.
-- Guarantees that the element and the player are valid when calling the handler.
-- Adds a player field to the event table.
Gui.on_player_show_top = custom_handler_factory(on_visible_handlers)

-- Register a handler for when the player hides the top LuaGuiElements with element_name.
-- Assuming the element_name has been added with Gui.allow_player_to_toggle_top_element_visibility.
-- Can only have one handler per element name.
-- Guarantees that the element and the player are valid when calling the handler.
-- Adds a player field to the event table.
Gui.on_pre_player_hide_top = custom_handler_factory(on_pre_hidden_handlers)

if _DEBUG then
    local concat = table.concat

    local names = {}
    Gui.names = names

    function Gui.uid_name()
        local info = debug.getinfo(2, 'Sl')
        local filepath = info.source:match('^.+/currently%-playing/(.+)$'):sub(1, -5)
        local line = info.currentline

        local token = tostring(Token.uid())

        local name = concat {token, ' - ', filepath, ':line:', line}
        names[token] = name

        return token
    end

    function Gui.set_data(element, value)
        local player_index = element.player_index
        local values = data[player_index]

        if value == nil then
            if not values then
                return
            end

            local index = element.index
            values[index] = nil
            element_map[index] = nil

            if next(values) == nil then
                data[player_index] = nil
            end
        else
            if not values then
                values = {}
                data[player_index] = values
            end

            local index = element.index
            values[index] = value
            element_map[index] = element
        end
    end
    set_data = Gui.set_data

    function Gui.data()
        return data
    end

    function Gui.element_map()
        return element_map
    end
end

Gui.get_button_flow = mod_gui.get_button_flow
Gui.mod_button = mod_gui.get_button_flow

return Gui
