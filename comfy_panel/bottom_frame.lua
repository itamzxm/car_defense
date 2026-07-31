local Event = require 'utils.event'
local Global = require 'utils.global'
local ComfyGui = require 'comfy_panel.main'
local GuiRebuild = require 'utils.gui_rebuild'
local Task = require 'utils.task_token'

local Public = {}

Public.events = {
    bottom_quickbar_location_changed = Event.generate_event_name('bottom_quickbar_location_changed')
}

local this = {
    players = {},
    storage = {},
    activate_custom_buttons = false,
    bottom_quickbar_button = {}
}

Global.register(
    this,
    function(t)
        this = t
    end
)

local bottom_guis_frame = 'cp_bf_bottom_guis_frame'
local bottom_quickbar_button_name = 'cp_bf_bottom_quickbar_button'

local sections = {
    [1] = 1,
    [2] = 1,
    [3] = 2,
    [4] = 2,
    [5] = 3,
    [6] = 3,
    [7] = 4,
    [8] = 4,
    [9] = 5,
    [10] = 5,
    [11] = 6,
    [12] = 6
}

local set_location
local destroy_frame

local check_bottom_buttons_token =
    Task.register(
        function(event)
            local player_index = event.player_index
            local player = game.get_player(player_index)
            if not player or not player.valid then
                return
            end

            local player_data = this.players[player_index]
            local storage_data = this.storage[player_index]
            if not player_data or not storage_data or not next(storage_data) then
                destroy_frame(player)
                this.players[player_index] = nil
                this.storage[player_index] = nil
                this.bottom_quickbar_button[player_index] = nil
                return
            end
        end
    )

function Public.get_player_data(player, remove_user_data)
    if remove_user_data then
        this.players[player.index] = nil
        this.storage[player.index] = nil
        return
    end
    if not this.players[player.index] then
        this.players[player.index] = {
            state = 'bottom_right',
            top = true,
            section = {},
            direction = 'vertical',
            row_index = 1,
            row_selection = 1,
            row_selection_added = 1
        }
        this.storage[player.index] = {}
    else
        local pd = this.players[player.index]
        if pd.state == nil then pd.state = 'bottom_right' end
        if pd.top == nil then pd.top = true end
        if pd.section == nil then pd.section = {} end
        if pd.direction == nil then pd.direction = 'vertical' end
        if pd.row_index == nil then pd.row_index = 1 end
        if pd.row_selection == nil then pd.row_selection = 1 end
        if pd.row_selection_added == nil then pd.row_selection_added = 1 end
        if not this.storage[player.index] then this.storage[player.index] = {} end
    end
    return this.players[player.index], this.storage[player.index]
end

function Public.get(key)
    if key then
        return this[key]
    else
        return this
    end
end

function Public.set(key, value)
    if key and (value or value == false) then
        this[key] = value
        return this[key]
    elseif key then
        return this[key]
    else
        return this
    end
end

function Public.clear_data(player)
    this.players[player.index] = nil
    this.storage[player.index] = nil
    this.bottom_quickbar_button[player.index] = nil
end

function Public.reset()
    local players = game.players
    for i = 1, #players do
        local player = players[i]
        if player and player.valid then
            if not player.connected then
                this.players[player.index] = nil
                this.storage[player.index] = nil
                this.bottom_quickbar_button[player.index] = nil
            end
        end
    end
end

----! Gui Functions ! ----

local function refresh_inner_frames(player)
    if not player or not player.valid then
        return
    end
    local player_data, storage_data = Public.get_player_data(player)
    if not player_data or not storage_data or not player_data.frame or not player_data.frame.valid then
        return
    end

    local main_frame = player_data.frame

    for _, child in pairs(main_frame.children) do
        child.destroy()
    end

    local horizontal_flow = main_frame.add({type = 'flow', direction = 'horizontal'})
    horizontal_flow.style.horizontal_spacing = 0

    for row_index, row_index_data in pairs(storage_data) do
        if row_index_data and type(row_index_data) == 'table' then
            local section_row_index = player_data.section[row_index]
            local vertical_flow = horizontal_flow.add({type = 'flow', direction = 'vertical'})
            vertical_flow.style.vertical_spacing = 0

            if not section_row_index then
                player_data.section[row_index] = {}
                section_row_index = player_data.section[row_index]
            end

            section_row_index.inner_frame = vertical_flow

            for row_selection, row_selection_data in pairs(row_index_data) do
                if section_row_index[row_selection] and section_row_index[row_selection].valid then
                    section_row_index[row_selection].destroy()
                end

                section_row_index[row_selection] =
                    section_row_index.inner_frame.add(
                        {
                            type = 'sprite-button',
                            sprite = row_selection_data.sprite,
                            name = row_selection_data.name,
                            tooltip = row_selection_data.tooltip or '',
                            style = 'quick_bar_page_button'
                        }
                    )
            end
        end
    end
end

local refresh_inner_frames_token =
    Task.register(
        function(event)
            local player_index = event.player_index
            local player = game.get_player(player_index)
            if not player or not player.valid then
                return
            end

            refresh_inner_frames(player)
        end
    )

function Public.add_inner_frame(data)
    if not data then
        return
    end
    local player = data.player
    local element_name = data.element_name
    local tooltip = data.tooltip
    local sprite = data.sprite
    if not player or not player.valid then
        return error('Given player was not valid', 2)
    end
    if not element_name then
        return error('Element name is missing', 2)
    end
    if not sprite then
        return error('Sprite is missing', 2)
    end

    local player_data, storage_data = Public.get_player_data(player)
    if not player_data or not storage_data then
        return
    end

    if player_data.row_index > 6 then
        return error('Having more than 6 rows is currently not supported.', 2)
    end

    local found = false
    for _, row_index_data in pairs(storage_data) do
        if row_index_data and type(row_index_data) == 'table' then
            for _, row_selection_data in pairs(row_index_data) do
                if row_selection_data and row_selection_data.name == element_name then
                    found = true
                end
            end
        end
    end

    if found then
        return
    end

    player_data.row_index = sections[player_data.row_selection_added]

    if not storage_data[player_data.row_index] then
        storage_data[player_data.row_index] = {}
    end

    local storage_data_section = storage_data[player_data.row_index]
    storage_data_section[player_data.row_selection] =
    {
        name = element_name,
        sprite = sprite,
        tooltip = tooltip
    }

    player_data.row_selection = player_data.row_selection + 1
    player_data.row_selection_added = player_data.row_selection_added + 1
    player_data.row_selection = player_data.row_selection > 2 and 1 or player_data.row_selection

    if player_data.frame and player_data.frame.valid then
        Task.priority_delay(2, refresh_inner_frames_token, {player_index = player.index})
    end
end

function Public.get_frame_by_element_name(player, element_name)
    local player_data, storage_data = Public.get_player_data(player)
    if not player_data or not storage_data or not player_data.frame or not player_data.frame.valid then
        return
    end

    for _, row_index_data in pairs(storage_data) do
        if row_index_data and type(row_index_data) == 'table' then
            for _, row_selection_data in pairs(row_index_data) do
                if row_selection_data and row_selection_data.name == element_name then
                    return row_selection_data
                end
            end
        end
    end
end

destroy_frame = function(player)
    local gui = player.gui
    local frame = gui.screen[bottom_guis_frame]
    if frame and frame.valid then
        frame.destroy()
    end
end

local function create_frame(player, alignment, location, data)
    local gui = player.gui
    local frame = gui.screen[bottom_guis_frame]
    if frame and frame.valid then
        destroy_frame(player)
    end

    alignment = alignment or 'vertical'

    frame =
        player.gui.screen.add(
            {
                type = 'frame',
                name = bottom_guis_frame,
                direction = alignment
            }
        )

    frame.style.padding = 3
    frame.style.top_padding = 4
    if alignment == 'vertical' then
        frame.style.minimal_height = 96
    end

    local inner_frame =
        frame.add(
            {
                type = 'frame',
                direction = alignment
            }
        )
    inner_frame.style = 'quick_bar_inner_panel'

    frame.location = location
    if data.portable then
        frame.caption = '•'
    end

    if data.top then
        frame.visible = false
    else
        frame.visible = true
    end

    data.frame = inner_frame
    data.parent = frame
    data.section = data.section or {}
    data.section_data = data.section_data or {}
    data.alignment = alignment

    this.bottom_quickbar_button[player.index] = {name = bottom_quickbar_button_name}

    Task.priority_delay(5, check_bottom_buttons_token, {player_index = player.index})

    return frame
end

set_location = function(player, state)
    local data = Public.get_player_data(player)
    local alignment = 'vertical'

    local location
    local resolution = player.display_resolution
    local scale = player.display_scale

    state = state or data.state

    if state == 'bottom_left' then
        if data.above then
            location = {
                x = (resolution.width / 2) - ((259) * scale),
                y = (resolution.height - (-12 + (40 * 5) * scale))
            }
            alignment = 'horizontal'
        else
            location = {
                x = (resolution.width / 2) - ((455 + (data.row_index * 40)) * scale),
                y = (resolution.height - (96 * scale))
            }
        end
        data.bottom_state = 'bottom_left'
    elseif state == 'bottom_right' then
        if data.above then
            location = {
                x = (resolution.width / 2) - ((-460 + (data.row_index * 40)) * scale),
                y = (resolution.height - (-12 + (40 * 5) * scale))
            }
            alignment = 'horizontal'
        else
            location = {
                x = (resolution.width / 2) - ((54 + -689) * scale),
                y = (resolution.height - (96 * scale))
            }
        end
        data.bottom_state = 'bottom_right'
    else
        location = {
            x = (resolution.width / 2) - ((54 + -528) * scale),
            y = (resolution.height - (96 * scale))
        }
    end

    create_frame(player, alignment, location, data)
    refresh_inner_frames(player)

    script.raise_event(
        Public.events.bottom_quickbar_location_changed,
        {player_index = player.index, data = data}
    )

    data.state = state
end

function Public.set_top(player, value)
    local data = Public.get_player_data(player)
    data.top = value or false
    Public.set_location(player, data.bottom_state or 'bottom_right')
end

function Public.activate_custom_buttons(value)
    if value then
        this.activate_custom_buttons = value
    else
        this.activate_custom_buttons = false
    end
end

function Public.is_custom_buttons_enabled()
    return this.activate_custom_buttons
end

Event.add(
    defines.events.on_player_joined_game,
    function(event)
        local player = game.players[event.player_index]
        if this.activate_custom_buttons then
            local data = Public.get_player_data(player)
            if data.top then
                destroy_frame(player)
            else
                set_location(player)
            end
        end
    end
)

Event.add(
    defines.events.on_player_display_resolution_changed,
    function(event)
        local player = game.get_player(event.player_index)
        if this.activate_custom_buttons then
            set_location(player)
        end
    end
)

Event.add(
    defines.events.on_player_respawned,
    function(event)
        local player = game.get_player(event.player_index)
        if this.activate_custom_buttons then
            set_location(player)
        end
    end
)

Event.add(
    defines.events.on_player_display_scale_changed,
    function(event)
        local player = game.get_player(event.player_index)
        if this.activate_custom_buttons then
            set_location(player)
        end
    end
)

Event.add(
    defines.events.on_pre_player_left_game,
    function(event)
        local player = game.get_player(event.player_index)
        destroy_frame(player)
        Public.clear_data(player)
    end
)

Public.bottom_guis_frame = bottom_guis_frame
Public.set_location = set_location
Public.refresh_inner_frames = refresh_inner_frames
ComfyGui.screen_to_bypass(bottom_guis_frame)

GuiRebuild.register('bottom_frame', function(player)
end)

return Public
