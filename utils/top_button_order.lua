local Event = require 'utils.event'
local TopBar = require 'utils.top_bar'
local BottomFrame = require 'comfy_panel.bottom_frame'
local Task = require 'utils.task_token'

local Public = {}

local TOP_BUTTON_ORDER = {
    TopBar.get_toggle_button_name(),
    'comfy_panel_top_button',
    'cp_poll_main_button',
    'rpg_draw_main_frame',
    'pet_draw_main_button',
    'tianfu',
    -- 'difficulty_gui',
    'amap_vote_poll_button',
    'amap_main_button',
    'charging_station',
    'cmd_misc_clear_corpse_button',
    'auto_stash',
    'amap_main_frame',
    'ic_integration_button',
    'minimap_button',
}

local function reorder_top_buttons(player)
    local flow = TopBar.get_button_flow(player)
    local children = flow.children
    if #children <= 1 then return end

    local name_to_order = {}
    for i, name in ipairs(TOP_BUTTON_ORDER) do
        name_to_order[name] = i
    end
    local default_order = #TOP_BUTTON_ORDER + 1

    local function get_order(elem)
        return name_to_order[elem.name] or default_order
    end

    for i = 1, #children do
        local min_idx = i
        local min_val = get_order(children[min_idx])
        for j = i + 1, #children do
            local val = get_order(children[j])
            if val < min_val then
                min_val = val
                min_idx = j
            end
        end
        if min_idx ~= i then
            flow.swap_children(i, min_idx)
            children = flow.children
        end
    end
end

local reorder_token =
    Task.register(
        function(event)
            local player_index = event.player_index
            local player = game.get_player(player_index)
            if not player or not player.valid then
                return
            end
            reorder_top_buttons(player)
        end
    )

Event.add(defines.events.on_player_joined_game, function(event)
    local player = game.players[event.player_index]
    if player and player.valid then
        reorder_top_buttons(player)
    end
end)

Event.add(
    BottomFrame.events.bottom_quickbar_location_changed,
    function(event)
        local player_index = event.player_index
        if not player_index then
            return
        end
        Task.priority_delay(1, reorder_token, {player_index = player_index})
    end
)

Public.reorder_top_buttons = reorder_top_buttons

return Public
