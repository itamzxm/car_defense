local Antigrief = require 'antigrief'
local Event = require 'utils.event'
local Color = require 'utils.color_presets'
local SessionData = require 'utils.datastore.session_data'
local Utils = require 'utils.core'
local Tabs = require 'comfy_panel.main'
local SpamProtection = require 'utils.spam_protection'
local BottomFrame = require 'comfy_panel.bottom_frame'
local Token = require 'utils.token'
local Global = require 'utils.global'
local Gui = require 'utils.gui'
local Task = require 'utils.task_token'

local insert = table.insert

local module_name = 'Config'

local Public = {}

local this = {
    gui_config = {
        spaghett = {
            undo = {}
        },
        poll_trusted = false
    },
    scenario_registry = {}
}

Global.register(
    this,
    function(tbl)
        this = tbl
    end
)

local spaghett_entity_blacklist = {
    ['requester-chest'] = true,
    ['buffer-chest'] = true,
    ['active-provider-chest'] = true
}

function Public.register_scenario_module(data)
    assert(data.id, "Scenario module requires id")
    for i = 1, #this.scenario_registry do
        if this.scenario_registry[i].id == data.id then
            this.scenario_registry[i] = data
            return
        end
    end
    insert(this.scenario_registry, data)
end

local function handle_registered_event(event, player)
    for i = 1, #this.scenario_registry do
        local mod = this.scenario_registry[i]
        if mod.handlers and mod.handlers[event.element.name] then
            local handler = Task.get(mod.handlers[event.element.name])
            if handler then
                handler(player, event)
                return
            end
        end
    end
end

local function get_actor(event, prefix, msg, admins_only)
    local player = game.get_player(event.player_index)
    if not player or not player.valid then
        return
    end
    if admins_only then
        Utils.print_admins(msg, player.name)
    else
        Utils.action_warning(prefix, player.name .. ' ' .. msg)
    end
end

local function spaghett_deny_building(event)
    local spaghett = this.gui_config.spaghett
    if not spaghett.enabled then
        return
    end
    local entity = event.entity
    if not entity.valid then
        return
    end
    if not spaghett_entity_blacklist[event.entity.name] then
        return
    end

    if event.player_index then
        game.players[event.player_index].insert({name = entity.name, count = 1})
    else
        local inventory = event.robot.get_inventory(defines.inventory.robot_cargo)
        inventory.insert({name = entity.name, count = 1})
    end

    event.entity.surface.create_entity(
        {
            name = 'flying-text',
            position = entity.position,
            text = 'Spaghett Mode Active!',
            color = {r = 0.98, g = 0.66, b = 0.22}
        }
    )

    entity.destroy()
end

local function spaghett()
    local spaghetti = this.gui_config.spaghett
    if spaghetti.enabled then
        for _, f in pairs(game.forces) do
            if f.technologies['logistic-system'].researched then
                spaghetti.undo[f.index] = true
            end
            f.technologies['logistic-system'].enabled = false
            f.technologies['logistic-system'].researched = false
        end
    else
        for _, f in pairs(game.forces) do
            f.technologies['logistic-system'].enabled = true
            if spaghetti.undo[f.index] then
                f.technologies['logistic-system'].researched = true
                spaghetti.undo[f.index] = nil
            end
        end
    end
end

local function trust_connected_players()
    local trust = SessionData.get_trusted_table()
    local AG = Antigrief.get()
    local players = game.connected_players
    if not AG.enabled then
        for _, p in pairs(players) do
            trust[p.name] = true
        end
    else
        for _, p in pairs(players) do
            trust[p.name] = false
        end
    end
end

local functions = {
    ['comfy_panel_spectator_switch'] = function(event)
        if event.element.switch_state == 'left' then
            game.players[event.player_index].spectator = true
        else
            game.players[event.player_index].spectator = false
        end
    end,
    ['comfy_panel_bottom_location'] = function(event)
        local player = game.get_player(event.player_index)
        if event.element.switch_state == 'left' then
            BottomFrame.set_location(player, 'bottom_left')
        else
            BottomFrame.set_location(player, 'bottom_right')
        end
    end,
    ['comfy_panel_top_location'] = function(event)
        local player = game.get_player(event.player_index)
        if event.element.switch_state == 'left' then
            BottomFrame.set_top(player, true)
        else
            BottomFrame.set_top(player, false)
        end
    end,
    ['comfy_panel_middle_location'] = function(event)
        local player = game.get_player(event.player_index)
        local data = BottomFrame.get_player_data(player)
        if event.element.switch_state == 'left' then
            data.above = true
            data.portable = false
        else
            data.above = false
            data.portable = false
        end
        if not data.bottom_state then
            data.bottom_state = 'bottom_right'
        end

        BottomFrame.set_location(player, data.bottom_state)
    end,
    ['comfy_panel_portable_button'] = function(event)
        local player = game.get_player(event.player_index)
        local data = BottomFrame.get_player_data(player)
        if event.element.switch_state == 'left' then
            data.above = false
            data.portable = true
        else
            data.portable = false
            data.above = false
        end

        if not data.bottom_state then
            data.bottom_state = 'bottom_right'
        end

        BottomFrame.set_location(player, data.bottom_state)
    end,
    ['comfy_panel_auto_hotbar_switch'] = function(event)
        if event.element.switch_state == 'left' then
            storage.auto_hotbar_enabled[event.player_index] = true
        else
            storage.auto_hotbar_enabled[event.player_index] = false
        end
    end,
    ['comfy_panel_blueprint_toggle'] = function(event)
        if event.element.switch_state == 'left' then
            game.permissions.get_group('Default').set_allows_action(defines.input_action.open_blueprint_library_gui, true)
            game.permissions.get_group('Default').set_allows_action(defines.input_action.import_blueprint_string, true)
            get_actor(event, '[Blueprints]', 'has enabled blueprints!')
        else
            game.permissions.get_group('Default').set_allows_action(defines.input_action.open_blueprint_library_gui, false)
            game.permissions.get_group('Default').set_allows_action(defines.input_action.import_blueprint_string, false)
            get_actor(event, '[Blueprints]', 'has disabled blueprints!')
        end
    end,
    ['comfy_panel_spaghett_toggle'] = function(event)
        if event.element.switch_state == 'left' then
            this.gui_config.spaghett.enabled = true
            get_actor(event, '[Spaghett]', 'has enabled spaghett mode!')
        else
            this.gui_config.spaghett.enabled = nil
            get_actor(event, '[Spaghett]', 'has disabled spaghett mode!')
        end
        spaghett()
    end,
    ['bb_team_balancing_toggle'] = function(event)
        if event.element.switch_state == 'left' then
            storage.bb_settings.team_balancing = true
            game.print('Team balancing has been enabled!')
        else
            storage.bb_settings.team_balancing = false
            game.print('Team balancing has been disabled!')
        end
    end,
    ['bb_only_admins_vote'] = function(event)
        if event.element.switch_state == 'left' then
            storage.bb_settings.only_admins_vote = true
            storage.difficulty_player_votes = {}
            game.print('Admin-only difficulty voting has been enabled!')
        else
            storage.bb_settings.only_admins_vote = false
            game.print('Admin-only difficulty voting has been disabled!')
        end
    end,
    ['disable_cleaning'] = function(event)
        if event.element.switch_state == 'left' then
            Gui.set_disable_clear_invalid_data(true)
        else
            Gui.set_disable_clear_invalid_data(false)
        end
    end
}

local antigrief_functions = {
    ['comfy_panel_disable_antigrief'] = function(event)
        local AG = Antigrief.get()
        if event.element.switch_state == 'left' then
            AG.enabled = true
            get_actor(event, '[Antigrief]', 'has enabled the antigrief function.', true)
        else
            AG.enabled = false
            get_actor(event, '[Antigrief]', 'has disabled the antigrief function.', true)
        end
        trust_connected_players()
    end
}

local fortress_functions = {
    ['comfy_panel_disable_fullness'] = function(event)
        local Fullness = is_loaded('modules.check_fullness')
        local Module = Fullness.get()
        if event.element.switch_state == 'left' then
            Module.fullness_enabled = true
            get_actor(event, '[Fullness]', 'has enabled the inventory fullness function.')
        else
            Module.fullness_enabled = false
            get_actor(event, '[Fullness]', 'has disabled the inventory fullness function.')
        end
    end,
    ['comfy_panel_offline_players'] = function(event)
        local WPT = is_loaded('maps.mountain_fortress_v3.table')
        local Module = WPT.get()
        if event.element.switch_state == 'left' then
            Module.offline_players_enabled = true
            get_actor(event, '[Offline Players]', 'has enabled the offline player function.')
        else
            Module.offline_players_enabled = false
            get_actor(event, '[Offline Players]', 'has disabled the offline player function.')
        end
    end,
    ['comfy_panel_collapse_grace'] = function(event)
        local WPT = is_loaded('maps.mountain_fortress_v3.table')
        local Module = WPT.get()
        if event.element.switch_state == 'left' then
            Module.collapse_grace = true
            get_actor(event, '[Collapse]', 'has enabled the collapse function. Collapse will occur after wave 100!')
        else
            Module.collapse_grace = false
            get_actor(event, '[Collapse]', 'has disabled the collapse function. You must breach the first zone for collapse to occur!')
        end
    end,
    ['comfy_panel_spill_items_to_surface'] = function(event)
        local WPT = is_loaded('maps.mountain_fortress_v3.table')
        local Module = WPT.get()
        if event.element.switch_state == 'left' then
            Module.spill_items_to_surface = true
            get_actor(event, '[Item Spill]', 'has enabled the ore spillage function. Ores now drop to surface when mining.')
        else
            Module.spill_items_to_surface = false
            get_actor(event, '[Item Spill]', 'has disabled the item spillage function. Ores no longer drop to surface when mining.')
        end
    end,
    ['comfy_panel_void_or_tile'] = function(event)
        local WPT = is_loaded('maps.mountain_fortress_v3.table')
        local Module = WPT.get()
        if event.element.switch_state == 'left' then
            Module.void_or_tile = 'out-of-map'
            get_actor(event, '[Void]', 'has changes the tiles of the zones to: out-of-map (void)')
        else
            Module.void_or_tile = 'lab-dark-2'
            get_actor(event, '[Void]', 'has changes the tiles of the zones to: dark-tiles (flammable tiles)')
        end
    end,
    ['comfy_panel_trusted_only_car_tanks'] = function(event)
        local WPT = is_loaded('maps.mountain_fortress_v3.table')
        local Module = WPT.get()
        if event.element.switch_state == 'left' then
            Module.trusted_only_car_tanks = true
            get_actor(event, '[Market]', 'has changed so only trusted people can buy car/tanks.', true)
        else
            Module.trusted_only_car_tanks = false
            get_actor(event, '[Market]', 'has changed so everybody can buy car/tanks.', true)
        end
    end,
    ['comfy_panel_allow_decon'] = function(event)
        local WPT = is_loaded('maps.mountain_fortress_v3.table')
        if event.element.switch_state == 'left' then
            local limited_group = game.permissions.get_group('limited')
            if limited_group then
                limited_group.set_allows_action(defines.input_action.deconstruct, true)
            end
            WPT.set('allow_decon', true)
            get_actor(event, '[Decon]', 'has allowed decon on car/tanks/trains.', true)
        else
            local limited_group = game.permissions.get_group('limited')
            if limited_group then
                limited_group.set_allows_action(defines.input_action.deconstruct, false)
            end
            WPT.set('allow_decon', false)
            get_actor(event, '[Decon]', 'has disabled decon on car/tanks/trains.', true)
        end
    end,
    ['comfy_panel_christmas_mode'] = function(event)
        local WPT = is_loaded('maps.mountain_fortress_v3.table')
        if event.element.switch_state == 'left' then
            WPT.set('winter_mode', true)
            get_actor(event, '[WinteryMode]', 'has enabled wintery mode.', true)
        else
            WPT.set('winter_mode', false)
            get_actor(event, '[WinteryMode]', 'has disabled wintery mode.', true)
        end
    end
}

local function add_switch(element, switch_state, name, description_main, description)
    local t = element.add({type = 'table', column_count = 5})
    local on_label = t.add({type = 'label', caption = 'ON'})
    on_label.style.padding = 0
    on_label.style.left_padding = 10
    on_label.style.font_color = {0.77, 0.77, 0.77}
    local switch = t.add({type = 'switch', name = name})
    switch.switch_state = switch_state
    switch.style.padding = 0
    switch.style.margin = 0
    local off_label = t.add({type = 'label', caption = 'OFF'})
    off_label.style.padding = 0
    off_label.style.font_color = {0.70, 0.70, 0.70}

    local desc_main_label = t.add({type = 'label', caption = description_main})
    desc_main_label.style.padding = 2
    desc_main_label.style.left_padding = 10
    desc_main_label.style.minimal_width = 120
    desc_main_label.style.font = 'heading-2'
    desc_main_label.style.font_color = {0.88, 0.88, 0.99}

    local desc_label = t.add({type = 'label', caption = description})
    desc_label.style.padding = 2
    desc_label.style.left_padding = 10
    desc_label.style.single_line = false
    desc_label.style.font = 'heading-2'
    desc_label.style.font_color = {0.85, 0.85, 0.85}

    return switch
end

local function build_config_gui(data)
    local player = data.player
    local frame = data.frame

    local AG = Antigrief.get()
    local switch_state
    local label

    local admin = player.admin
    frame.clear()

    local scroll_pane =
        frame.add {
        type = 'scroll-pane',
        horizontal_scroll_policy = 'never'
    }
    local scroll_style = scroll_pane.style
    scroll_style.vertically_squashable = true
    scroll_style.minimal_height = 350
    scroll_style.bottom_padding = 2
    scroll_style.left_padding = 2
    scroll_style.right_padding = 2
    scroll_style.top_padding = 2

    label = scroll_pane.add({type = 'label', caption = {'gui.player_settings'}})
    label.style.font = 'default-bold'
    label.style.padding = 0
    label.style.left_padding = 10
    label.style.horizontal_align = 'left'
    label.style.vertical_align = 'bottom'
    label.style.font_color = {0.55, 0.55, 0.99}

    scroll_pane.add({type = 'line'})

    switch_state = 'right'
    if player.spectator then
        switch_state = 'left'
    end
    add_switch(
        scroll_pane,
        switch_state,
        'comfy_panel_spectator_switch',
        {'gui.spectator_mode'},
        {'gui-description.spectator_mode'}
    )

    scroll_pane.add({type = 'line'})

    if storage.auto_hotbar_enabled then
        switch_state = 'right'
        if storage.auto_hotbar_enabled[player.index] then
            switch_state = 'left'
        end
        add_switch(scroll_pane, switch_state, 'comfy_panel_auto_hotbar_switch', {'gui.auto_hotbar'}, {'gui-description.auto_hotbar'})
        scroll_pane.add({type = 'line'})
    end

    for i = 1, #this.scenario_registry do
        local mod = this.scenario_registry[i]
        if mod.gui_rows and not mod.admin_only then
            local handler = Task.get(mod.gui_rows)
            if handler then
                handler(player, scroll_pane)
            end
        end
    end

    if BottomFrame.is_custom_buttons_enabled() then
        label = scroll_pane.add({type = 'label', caption = {'gui.bottom_buttons_settings'}})
        label.style.font = 'default-bold'
        label.style.padding = 0
        label.style.left_padding = 10
        label.style.top_padding = 10
        label.style.horizontal_align = 'left'
        label.style.vertical_align = 'bottom'
        label.style.font_color = Color.white_smoke

        scroll_pane.add({type = 'line'})

        switch_state = 'right'
        local bottom_frame = BottomFrame.get_player_data(player)
        if bottom_frame and bottom_frame.top then
            switch_state = 'left'
        end
        add_switch(
            scroll_pane,
            switch_state,
            'comfy_panel_top_location',
            {'gui.position_top'},
            {'gui-description.position_top'}
        )

        scroll_pane.add({type = 'line'})

        switch_state = 'right'
        if bottom_frame and bottom_frame.bottom_state == 'bottom_left' then
            switch_state = 'left'
        end
        add_switch(
            scroll_pane,
            switch_state,
            'comfy_panel_bottom_location',
            {'gui.position_bottom'},
            {'gui-description.position_bottom'}
        )

        scroll_pane.add({type = 'line'})

        switch_state = 'right'
        if bottom_frame and bottom_frame.above then
            switch_state = 'left'
        end
        add_switch(
            scroll_pane,
            switch_state,
            'comfy_panel_middle_location',
            {'gui.position_middle'},
            {'gui-description.position_middle'}
        )

        scroll_pane.add({type = 'line'})

        switch_state = 'right'
        if bottom_frame and bottom_frame.portable then
            switch_state = 'left'
        end
        add_switch(
            scroll_pane,
            switch_state,
            'comfy_panel_portable_button',
            {'gui.position_portable'},
            {'gui-description.position_portable'}
        )
        scroll_pane.add({type = 'line'})
    end

    if admin then
        label = scroll_pane.add({type = 'label', caption = {'gui.admin_settings'}})
        label.style.font = 'default-bold'
        label.style.padding = 0
        label.style.left_padding = 10
        label.style.top_padding = 10
        label.style.horizontal_align = 'left'
        label.style.vertical_align = 'bottom'
        label.style.font_color = {0.77, 0.11, 0.11}

        scroll_pane.add({type = 'line'})

        for i = 1, #this.scenario_registry do
            local mod = this.scenario_registry[i]
            if mod.gui_rows and mod.admin_only then
                local handler = Task.get(mod.gui_rows)
                if handler then
                    handler(player, scroll_pane)
                end
            end
        end

        switch_state = 'right'
        if game.permissions.get_group('Default').allows_action(defines.input_action.open_blueprint_library_gui) then
            switch_state = 'left'
        end
        add_switch(scroll_pane, switch_state, 'comfy_panel_blueprint_toggle', {'gui.blueprint_library'}, {'gui-description.blueprint_library'})

        scroll_pane.add({type = 'line'})

        switch_state = 'right'
        if Gui.get_disable_clear_invalid_data() then
            switch_state = 'left'
        end
        add_switch(scroll_pane, switch_state, 'disable_cleaning', {'gui.gui_data_cleaning'}, {'gui-description.gui_data_cleaning'})

        scroll_pane.add({type = 'line'})

        switch_state = 'right'
        if this.gui_config.spaghett.enabled then
            switch_state = 'left'
        end
        add_switch(
            scroll_pane,
            switch_state,
            'comfy_panel_spaghett_toggle',
            {'gui.spaghett_mode'},
            {'gui-description.spaghett_mode'}
        )

        scroll_pane.add({type = 'line'})

        label = scroll_pane.add({type = 'label', caption = {'gui.antigrief_settings'}})
        label.style.font = 'default-bold'
        label.style.padding = 0
        label.style.left_padding = 10
        label.style.top_padding = 10
        label.style.horizontal_align = 'left'
        label.style.vertical_align = 'bottom'
        label.style.font_color = Color.yellow

        switch_state = 'right'
        if AG.enabled then
            switch_state = 'left'
        end
        add_switch(scroll_pane, switch_state, 'comfy_panel_disable_antigrief', {'gui.antigrief'}, {'gui-description.antigrief'})
        scroll_pane.add({type = 'line'})

        if is_loaded('maps.biter_battles_v2.main') then
            label = scroll_pane.add({type = 'label', caption = {'gui.biter_battles_settings'}})
            label.style.font = 'default-bold'
            label.style.padding = 0
            label.style.left_padding = 10
            label.style.top_padding = 10
            label.style.horizontal_align = 'left'
            label.style.vertical_align = 'bottom'
            label.style.font_color = Color.green

            scroll_pane.add({type = 'line'})

            local team_balancing_state = 'right'
            if storage.bb_settings.team_balancing then
                team_balancing_state = 'left'
            end
            local switch =
                add_switch(
                scroll_pane,
                team_balancing_state,
                'bb_team_balancing_toggle',
                {'gui.team_balancing'},
                {'gui-description.team_balancing'}
            )
            if not admin then
                switch.ignored_by_interaction = true
            end

            scroll_pane.add({type = 'line'})

            local only_admins_vote_state = 'right'
            if storage.bb_settings.only_admins_vote then
                only_admins_vote_state = 'left'
            end
            local only_admins_vote_switch =
                add_switch(
                scroll_pane,
                only_admins_vote_state,
                'bb_only_admins_vote',
                {'gui.admin_vote'},
                {'gui-description.admin_vote'}
            )
            if not admin then
                only_admins_vote_switch.ignored_by_interaction = true
            end

            scroll_pane.add({type = 'line'})
        end

        if is_loaded('maps.mountain_fortress_v3.main') then
            label = scroll_pane.add({type = 'label', caption = {'gui.mountain_fortress_settings'}})
            label.style.font = 'default-bold'
            label.style.padding = 0
            label.style.left_padding = 10
            label.style.top_padding = 10
            label.style.horizontal_align = 'left'
            label.style.vertical_align = 'bottom'
            label.style.font_color = Color.green

            local Fullness = is_loaded('modules.check_fullness')
            local full = Fullness.get()
            switch_state = 'right'
            if full.fullness_enabled then
                switch_state = 'left'
            end
            add_switch(
                scroll_pane,
                switch_state,
                'comfy_panel_disable_fullness',
                {'gui.inventory_fullness'},
                {'gui-description.inventory_fullness'}
            )

            scroll_pane.add({type = 'line'})

            local WPT = is_loaded('maps.mountain_fortress_v3.table')
            local Module = WPT.get()
            switch_state = 'right'
            if Module.offline_players_enabled then
                switch_state = 'left'
            end
            add_switch(
                scroll_pane,
                switch_state,
                'comfy_panel_offline_players',
                {'gui.offline_players'},
                {'gui-description.offline_players'}
            )

            scroll_pane.add({type = 'line'})

            switch_state = 'right'
            if Module.collapse_grace then
                switch_state = 'left'
            end
            add_switch(
                scroll_pane,
                switch_state,
                'comfy_panel_collapse_grace',
                {'gui.collapse'},
                {'gui-description.collapse'}
            )

            scroll_pane.add({type = 'line'})

            switch_state = 'right'
            if Module.spill_items_to_surface then
                switch_state = 'left'
            end
            add_switch(
                scroll_pane,
                switch_state,
                'comfy_panel_spill_items_to_surface',
                {'gui.spill_ores'},
                {'gui-description.spill_ores'}
            )
            scroll_pane.add({type = 'line'})

            switch_state = 'right'
            if Module.void_or_tile then
                switch_state = 'left'
            end
            add_switch(
                scroll_pane,
                switch_state,
                'comfy_panel_void_or_tile',
                {'gui.void_tiles'},
                {'gui-description.void_tiles'}
            )
            scroll_pane.add({type = 'line'})

            switch_state = 'right'
            if Module.trusted_only_car_tanks then
                switch_state = 'left'
            end
            add_switch(
                scroll_pane,
                switch_state,
                'comfy_panel_trusted_only_car_tanks',
                {'gui.market_purchase'},
                {'gui-description.market_purchase'}
            )
            scroll_pane.add({type = 'line'})

            switch_state = 'right'
            if Module.allow_decon then
                switch_state = 'left'
            end
            add_switch(
                scroll_pane,
                switch_state,
                'comfy_panel_allow_decon',
                {'gui.deconstruct'},
                {'gui-description.deconstruct'}
            )
            scroll_pane.add({type = 'line'})
            if Module.christmas_mode then
                switch_state = 'left'
            end
            add_switch(scroll_pane, switch_state, 'comfy_panel_christmas_mode', {'gui.wintery_mode'}, {'gui-description.wintery_mode'})
            scroll_pane.add({type = 'line'})
        end
    end
    for _, e in pairs(scroll_pane.children) do
        if e.type == 'line' then
            e.style.padding = 0
            e.style.margin = 0
        end
    end
end

local build_config_gui_token = Token.register(build_config_gui)

local function on_gui_switch_state_changed(event)
    local player = game.players[event.player_index]
    if not (player and player.valid) then
        return
    end

    if not event.element then
        return
    end
    if not event.element.valid then
        return
    end

    if functions[event.element.name] then
        local is_spamming = SpamProtection.is_spamming(player, nil, 'Config Functions Elem')
        if is_spamming then
            return
        end
        functions[event.element.name](event)
        return
    elseif antigrief_functions[event.element.name] then
        local is_spamming = SpamProtection.is_spamming(player, nil, 'Config AntiGrief Elem')
        if is_spamming then
            return
        end
        antigrief_functions[event.element.name](event)
        return
    elseif fortress_functions[event.element.name] then
        local is_spamming = SpamProtection.is_spamming(player, nil, 'Config Fortress Elem')
        if is_spamming then
            return
        end
        fortress_functions[event.element.name](event)
        return
    end

    handle_registered_event(event, player)
end

local function on_force_created()
    spaghett()
end

local function on_built_entity(event)
    spaghett_deny_building(event)
end

local function on_robot_built_entity(event)
    spaghett_deny_building(event)
end

Tabs.add_tab_to_gui({name = module_name, id = build_config_gui_token, admin = false})

Event.add(defines.events.on_gui_switch_state_changed, on_gui_switch_state_changed)
Event.add(defines.events.on_force_created, on_force_created)
Event.add(defines.events.on_built_entity, on_built_entity)
Event.add(defines.events.on_robot_built_entity, on_robot_built_entity)

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

Public.add_switch = add_switch
Public.get_actor = get_actor
Public.register_token = Task.register

return Public
