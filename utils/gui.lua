local Token = require 'utils.token'
local Event = require 'utils.event'
local Global = require 'utils.global'
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

function Gui.uid_name()
    if _LIFECYCLE == 8 then
        error('Calling Gui.uid_name after on_init() or on_load() has run is a desync risk.', 2)
    end
    return tostring(Token.uid())
end

function Gui.uid()
    if _LIFECYCLE == 8 then
        error('Calling Gui.uid after on_init() or on_load() has run is a desync risk.', 2)
    end
    return Token.uid()
end

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

function Gui.set_disable_clear_invalid_data(value)
    settings.disable_clear_invalid_data = value or false
end

function Gui.get_disable_clear_invalid_data()
    return settings.disable_clear_invalid_data
end

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

function Gui.add_main_frame_with_toolbar(player, align, main_frame_name, settings_button_name, close_button_name, name)
    local gui = player.gui[align]
    local main_frame = gui.add({type = 'frame', name = main_frame_name, direction = 'vertical'})

    local titlebar = main_frame.add({type = 'flow', name = 'titlebar', direction = 'horizontal'})
    titlebar.style = 'horizontal_flow'
    titlebar.style.horizontal_spacing = 8

    if align == 'screen' then
        titlebar.drag_target = main_frame
    end

    titlebar.add({type = 'label', name = 'main_label', style = 'frame_title', caption = name, ignored_by_interaction = true})

    local widget = titlebar.add({type = 'empty-widget', style = 'draggable_space', ignored_by_interaction = true})
    widget.style.left_margin = 4
    widget.style.right_margin = 4
    widget.style.height = 24
    widget.style.horizontally_stretchable = true

    if settings_button_name then
        titlebar.add({
            type = 'sprite-button',
            name = settings_button_name,
            style = 'frame_action_button',
            sprite = 'utility/settings',
            hovered_sprite = 'utility/settings_fat',
            clicked_sprite = 'utility/settings_fat',
            mouse_button_filter = {'left'},
            tooltip = {'gui.poll_settings'}
        })
    end

    local close_button
    if close_button_name then
        close_button =
            titlebar.add({
                type = 'sprite-button',
                name = close_button_name,
                style = 'frame_action_button',
                mouse_button_filter = {'left'},
                sprite = 'utility/close',
                hovered_sprite = 'utility/close_fat',
                clicked_sprite = 'utility/close_fat',
                tooltip = {'gui.close'}
            })
    end

    local inside_frame = main_frame.add({type = 'frame', style = 'inside_shallow_frame'})
    inside_frame.style = 'inside_shallow_frame_with_padding'
    local scroll_pane = inside_frame.add({type = 'scroll-pane', style = 'naked_scroll_pane'})
    scroll_pane.style.maximal_height = 480

    return main_frame, inside_frame, scroll_pane, close_button
end

return Gui
