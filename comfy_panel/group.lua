-- this script adds a group button to create groups for your players --

local Tabs = require 'comfy_panel.main'
local Global = require 'utils.global'
local SpamProtection = require 'utils.spam_protection'
local Token = require 'utils.token'
local GuiDispatcher = require 'utils.gui_dispatcher'

local module_name = 'Groups'

local this = {
    player_group = {},
    join_spam_protection = {},
    tag_groups = {},
    alphanumeric = true
}

Global.register(
    this,
    function(t)
        this = t
    end
)

local Public = {}

local function build_group_gui(data)
    local player = data.player
    local frame = data.frame
    local group_name_width = 150
    local description_width = 240
    local members_width = 90
    local member_columns = 3
    local actions_width = 80
    local total_height = 420

    frame.clear()

    local t = frame.add({type = 'table', column_count = 5})
    local headings = {
        {{'gui.group_title'}, group_name_width},
        {{'gui.group_description'}, description_width},
        {{'gui.group_members'}, members_width * member_columns},
        {'', actions_width}
    }
    for _, h in pairs(headings) do
        local l = t.add({type = 'label', caption = h[1]})
        l.style.font_color = {r = 0.98, g = 0.66, b = 0.22}
        l.style.font = 'default-listbox'
        l.style.top_padding = 6
        l.style.minimal_height = 40
        l.style.minimal_width = h[2]
        l.style.maximal_width = h[2]
    end

    local scroll_pane =
        frame.add(
        {
            type = 'scroll-pane',
            name = 'cp_grp_scroll_pane',
            direction = 'vertical',
            horizontal_scroll_policy = 'never',
            vertical_scroll_policy = 'auto'
        }
    )
    scroll_pane.style.maximal_height = total_height - 50
    scroll_pane.style.minimal_height = total_height - 50

    t = scroll_pane.add({type = 'table', name = 'cp_grp_groups_table', column_count = 4})
    for _, h in pairs(headings) do
        local l = t.add({type = 'label', caption = ''})
        l.style.minimal_width = h[2]
        l.style.maximal_width = h[2]
    end

    for _, group in pairs(this.tag_groups) do
        if (group.name and group.founder and group.description) then
            local l = t.add({type = 'label', caption = group.name})
            l.style.font = 'default-bold'
            l.style.top_padding = 16
            l.style.bottom_padding = 16
            l.style.minimal_width = group_name_width
            l.style.maximal_width = group_name_width
            local color
            if game.players[group.founder] and game.players[group.founder].color then
                color = game.players[group.founder].color
            else
                color = {r = 0.90, g = 0.90, b = 0.90}
            end
            color = {r = color.r * 0.6 + 0.4, g = color.g * 0.6 + 0.4, b = color.b * 0.6 + 0.4, a = 1}
            l.style.font_color = color
            l.style.single_line = false
            l = t.add({type = 'label', caption = group.description})
            l.style.top_padding = 16
            l.style.bottom_padding = 16
            l.style.minimal_width = description_width
            l.style.maximal_width = description_width
            l.style.font_color = {r = 0.90, g = 0.90, b = 0.90}
            l.style.single_line = false

            local tt = t.add({type = 'table', column_count = member_columns})
            for _, p in pairs(game.connected_players) do
                if group.name == this.player_group[p.name] then
                    l = tt.add({type = 'label', caption = p.name})
                    color = {
                        r = p.color.r * 0.6 + 0.4,
                        g = p.color.g * 0.6 + 0.4,
                        b = p.color.b * 0.6 + 0.4,
                        a = 1
                    }
                    l.style.font_color = color
                    --l.style.minimal_width = members_width
                    l.style.maximal_width = members_width * 2
                end
            end

            tt = t.add({type = 'table', name = group.name, column_count = 1})
            if group.name ~= this.player_group[player.name] then
                local b = tt.add({type = 'button', name = 'cp_grp_join', caption = {'gui.group_join'}})
                b.style.font = 'default-bold'
                b.style.minimal_width = actions_width
                b.style.maximal_width = actions_width
            else
                local b = tt.add({type = 'button', name = 'cp_grp_leave', caption = {'gui.group_leave'}})
                b.style.font = 'default-bold'
                b.style.minimal_width = actions_width
                b.style.maximal_width = actions_width
            end
            if player.admin == true or group.founder == player.name then
                local b = tt.add({type = 'button', name = 'cp_grp_delete', caption = {'gui.group_delete'}})
                b.style.font = 'default-bold'
                b.style.minimal_width = actions_width
                b.style.maximal_width = actions_width
            else
                l = tt.add({type = 'label', caption = ''})
                l.style.minimal_width = actions_width
                l.style.maximal_width = actions_width
            end
        end
    end

    local frame2 = frame.add({type = 'frame', name = 'cp_grp_frame2'})
    t = frame2.add({type = 'table', name = 'cp_grp_table', column_count = 5})
    t.add({type = 'label', caption = {'gui.group_name_placeholder'}})
    local textfield = t.add({type = 'textfield', name = 'cp_grp_new_name', text = ''})
    textfield.style.minimal_width = 200
    t.add({type = 'label', caption = {'gui.group_desc_placeholder'}})
    textfield = t.add({type = 'textfield', name = 'cp_grp_new_desc', text = ''})
    textfield.style.minimal_width = 400
    local b = t.add({type = 'button', name = 'cp_grp_create', caption = {'gui.group_create'}})
    b.style.minimal_width = 150
    b.style.font = 'default-bold'
end

local build_group_gui_token = Token.register(build_group_gui)

local function refresh_gui()
    for _, p in pairs(game.connected_players) do
        local frame = Tabs.comfy_panel_get_active_frame(p)
        if frame then
            if frame.name == module_name then
                local new_group_name = frame.cp_grp_frame2.cp_grp_table.cp_grp_new_name.text
                local new_group_description = frame.cp_grp_frame2.cp_grp_table.cp_grp_new_desc.text

                local data = {player = p, frame = frame}
                build_group_gui(data)

                frame = Tabs.comfy_panel_get_active_frame(p)
                frame.cp_grp_frame2.cp_grp_table.cp_grp_new_name.text = new_group_name
                frame.cp_grp_frame2.cp_grp_table.cp_grp_new_desc.text = new_group_description
            end
        end
    end
end

local function on_player_joined_game(event)
    local player = game.players[event.player_index]

    if not this.player_group[player.name] then
        this.player_group[player.name] = '[Group]'
    end

    if not this.join_spam_protection[player.name] then
        this.join_spam_protection[player.name] = game.tick
    end
end

local function alphanumeric(str)
    return (string.match(str, '[^%w%s%p]') ~= nil)
end

GuiDispatcher.register_click('cp_grp_create', function(event)
    local player = game.get_player(event.player_index)
    local frame = Tabs.comfy_panel_get_active_frame(player)
    if not frame then
        return
    end
    if frame.name ~= module_name then
        return
    end

    local is_spamming = SpamProtection.is_spamming(player, nil, 'Group Click')
    if is_spamming then
        return
    end

    local new_group_name = frame.cp_grp_frame2.cp_grp_table.cp_grp_new_name.text
    local new_group_description = frame.cp_grp_frame2.cp_grp_table.cp_grp_new_desc.text
    if new_group_name ~= '' and new_group_description ~= '' then
        if string.len(new_group_name) > 64 then
            player.print({'gui-description.group_name_too_long'}, {r = 0.90, g = 0.0, b = 0.0})
            return
        end

        if string.len(new_group_description) > 128 then
            player.print({'gui-description.group_desc_too_long'}, {r = 0.90, g = 0.0, b = 0.0})
            return
        end

        this.tag_groups[new_group_name] = {
            name = new_group_name,
            description = new_group_description,
            founder = player.name
        }
        local color = {
            r = player.color.r * 0.7 + 0.3,
            g = player.color.g * 0.7 + 0.3,
            b = player.color.b * 0.7 + 0.3,
            a = 1
        }
        game.print({'gui-description.group_founded', player.name}, color)
        game.print('>> ' .. new_group_name, {r = 0.98, g = 0.66, b = 0.22})
        game.print(new_group_description, {r = 0.85, g = 0.85, b = 0.85})

        frame.cp_grp_frame2.cp_grp_table.cp_grp_new_name.text = ''
        frame.cp_grp_frame2.cp_grp_table.cp_grp_new_desc.text = ''
        refresh_gui()
        return
    end
end)

local function on_gui_click(event)
    local element = event.element
    if not element or not element.valid then
        return
    end
    local player = game.get_player(event.player_index)

    local name = event.element.name

    if name == 'tab_Groups' then
        local is_spamming = SpamProtection.is_spamming(player, nil, 'Groups tab_Groups')
        if is_spamming then
            return
        end
    end

    local frame = Tabs.comfy_panel_get_active_frame(player)
    if not frame then
        return
    end
    if frame.name ~= module_name then
        return
    end

    local p = element.parent
    if p then
        p = p.parent
    end
    if p then
        if p.name == 'cp_grp_groups_table' then
            local is_spamming = SpamProtection.is_spamming(player, nil, 'Group Click')

            if is_spamming then
                return
            end

            if element.type == 'button' and element.name == 'cp_grp_join' then
                this.player_group[player.name] = element.parent.name
                local str = '[' .. element.parent.name
                str = str .. ']'
                player.tag = str
                if game.tick - this.join_spam_protection[player.name] > 600 then
                    local color = {
                        r = player.color.r * 0.7 + 0.3,
                        g = player.color.g * 0.7 + 0.3,
                        b = player.color.b * 0.7 + 0.3,
                        a = 1
                    }
                    game.print({'gui-description.group_joined', player.name, element.parent.name}, color)
                    this.join_spam_protection[player.name] = game.tick
                end
                refresh_gui()
                return
            end

            if element.type == 'button' and element.name == 'cp_grp_delete' then
                for _, players in pairs(game.players) do
                    if this.player_group[players.name] then
                        if this.player_group[players.name] == element.parent.name then
                            this.player_group[players.name] = '[Group]'
                            players.tag = ''
                        end
                    end
                end
                game.print({'gui-description.group_deleted_msg', player.name, element.parent.name})
                this.tag_groups[element.parent.name] = nil
                refresh_gui()
                return
            end

            if element.type == 'button' and element.name == 'cp_grp_leave' then
                this.player_group[player.name] = '[Group]'
                player.tag = ''
                refresh_gui()
                return
            end
        end
    end
end

function Public.alphanumeric_only(value)
    if value then
        this.alphanumeric = value
    else
        this.alphanumeric = false
    end
end

function Public.reset_groups()
    local players = game.connected_players
    for i = 1, #players do
        local player = players[i]
        this.player_group[player.name] = '[Group]'
        this.join_spam_protection[player.name] = game.tick
    end
    this.tag_groups = {}
end

Tabs.add_tab_to_gui({name = module_name, id = build_group_gui_token, admin = false})

local Event = require 'utils.event'
Event.add(defines.events.on_gui_click, on_gui_click)
Event.add(defines.events.on_player_joined_game, on_player_joined_game)

return Public
