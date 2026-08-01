local Event = require 'utils.event'
local Global = require 'utils.global'
local SpamProtection = require 'utils.spam_protection'
local Color = require 'utils.color_presets'
local TopBar = require 'utils.top_bar'
local GuiDispatcher = require 'utils.gui_dispatcher'
local GuiRebuild = require 'utils.gui_rebuild'
local BottomFrame = require 'comfy_panel.bottom_frame'

local Public = {}

local charging_station_name = 'charging_station'

local this = {
    bottom_button = false
}

Global.register(
    this,
    function(t)
        this = t
    end
)

local function create_gui_button(player, bottom_frame_data)
    bottom_frame_data = bottom_frame_data or BottomFrame.get_player_data(player)

    local flow = TopBar.get_button_flow(player)
    local button

    if not flow[charging_station_name] then
        button = TopBar.add_button(player, {
            type = 'sprite-button',
            sprite = 'item/battery-mk2-equipment',
            name = charging_station_name,
            tooltip = {'modules.charging_station_tooltip'}
        })
    else
        button = flow[charging_station_name]
    end

    if this.bottom_button then
        if bottom_frame_data and not bottom_frame_data.top then
            if button and button.valid then
                button.destroy()
            end
        end
    end
end

local function discharge_accumulators(surface, position, force, power_needs)
    local multiplier = storage.charging_station_multiplier or 1
    local accumulators = surface.find_entities_filtered({
        type = 'accumulator',
        force = force,
        position = position,
        radius = 13
    })
    local power_drained = 0
    power_needs = power_needs * multiplier
    for _, accu in pairs(accumulators) do
        if accu.valid then
            if accu.energy > 3000000 and power_needs > 0 then
                if power_needs >= 2000000 then
                    power_drained = power_drained + 2000000
                    accu.energy = accu.energy - 2000000
                    power_needs = power_needs - 2000000
                else
                    power_drained = power_drained + power_needs
                    accu.energy = accu.energy - power_needs
                end
            elseif power_needs <= 0 then
                break
            end
        end
    end
    return power_drained / multiplier
end

local function charge(player)
    if not player.character then
        return player.print({'modules.charging_station_not_living'}, {color = Color.warning})
    end
    if player.controller_type == defines.controllers.remote then
        return player.print({'modules.charging_station_not_living'}, {color = Color.warning})
    end

    local armor_inventory = player.get_inventory(defines.inventory.character_armor)
    if not armor_inventory or not armor_inventory.valid then
        return player.print({'modules.charging_station_no_armor'}, {color = Color.warning})
    end
    local armor = armor_inventory[1]
    if not armor.valid_for_read then
        return player.print({'modules.charging_station_no_armor'}, {color = Color.warning})
    end
    local grid = armor.grid
    if not grid or not grid.valid then
        return player.print({'modules.charging_station_no_armor'}, {color = Color.warning})
    end

    local ents = player.physical_surface.find_entities_filtered({
        type = 'accumulator',
        force = player.force,
        position = player.physical_position,
        radius = 13
    })
    if not ents or not next(ents) then
        return player.print({'modules.charging_station_no_accumulator'}, {color = Color.warning})
    end

    local equip = grid.equipment
    for _, piece in pairs(equip) do
        if piece.valid and piece.generator_power == 0 then
            local energy_needs = piece.max_energy - piece.energy
            if energy_needs > 0 then
                local energy = discharge_accumulators(player.physical_surface, player.physical_position, player.force, energy_needs)
                if energy > 0 then
                    if piece.energy + energy >= piece.max_energy then
                        piece.energy = piece.max_energy
                    else
                        piece.energy = piece.energy + energy
                    end
                end
            end
        end
    end

    -- 音效有意禁用：防止频繁点击时吵闹，改为聊天栏提示反馈
    -- player.play_sound({path = 'utility/armor_insert', position = player.position, volume_modifier = 1})
end

local function on_player_joined_game(event)
    local player = game.players[event.player_index]
    if not player or not player.valid then
        return
    end

    create_gui_button(player)

    if this.bottom_button then
        BottomFrame.add_inner_frame({
            player = player,
            element_name = charging_station_name,
            tooltip = {'modules.charging_station_tooltip'},
            sprite = 'item/battery-mk2-equipment'
        })
    end
end

local function on_charging_station_click(event)
    local player = game.players[event.player_index]
    local is_spamming = SpamProtection.is_spamming(player, nil, 'Charging Station Gui Click')
    if is_spamming then
        return
    end
    charge(player)
end

function Public.bottom_button(value)
    this.bottom_button = value or false
end

Event.on_init(function()
    storage.charging_station_multiplier = 1
end)

GuiDispatcher.register_click(charging_station_name, on_charging_station_click)

Event.add(defines.events.on_player_joined_game, on_player_joined_game)

Event.add(
    BottomFrame.events.bottom_quickbar_location_changed,
    function(event)
        local player_index = event.player_index
        if not player_index then
            return
        end
        local player = game.get_player(player_index)
        if not player or not player.valid then
            return
        end
        create_gui_button(player, event.data)
    end
)

GuiRebuild.register('charging_station', function(player)
    create_gui_button(player)
end)

return Public
