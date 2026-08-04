local Event = require 'utils.event'
local session = require 'utils.datastore.session_data'
local Timestamp = require 'utils.timestamp'
local Server = require 'utils.server'
local Color = require 'utils.color_presets'

local font_color = Color.warning
local font = 'default-game'
local format = string.format

local brain = {
    [1] = {
        'Need an admin? Ask in chat or contact a server admin.',
        'If you have played for more than 5h in our maps then,',
        'you are eligible to run the command /jail and /free'
    },
    [2] = {},
    [3] = {
        'If you feel like the server is lagging, run the following command:',
        '/server-ups',
        'This will display the server UPS on your top right screen.'
    },
    [4] = {
        "If you're not trusted - ask a trusted player or an admin to trust you."
    }
}

local links = {
    ['admin'] = brain[1],
    ['administrator'] = brain[1],
    ['download'] = brain[2],
    ['github'] = brain[2],
    ['greifer'] = brain[1],
    ['grief'] = brain[1],
    ['griefer'] = brain[1],
    ['griefing'] = brain[1],
    ['mod'] = brain[1],
    ['moderator'] = brain[1],
    ['scenario'] = brain[2],
    ['stealing'] = brain[1],
    ['stole'] = brain[1],
    ['troll'] = brain[1],
    ['lag'] = brain[3],
    ['lagging'] = brain[3],
    ['trust'] = brain[4],
    ['trusted'] = brain[4],
    ['untrusted'] = brain[4]
}



commands.add_command(
    'trust',
    'Promotes a player to trusted!',
    function(cmd)
        local trusted = session.get_trusted_table()
        local player = game.player

        if player and player.valid then
            if not player.admin then
                player.print("You're not admin!", {r = 1, g = 0.5, b = 0.1})
                return
            end

            if cmd.parameter == nil then
                return
            end
            local target_player = game.players[cmd.parameter]
            if target_player then
                if trusted[target_player.name] then
                    game.print(target_player.name .. ' is already trusted!')
                    return
                end
                trusted[target_player.name] = true
                game.print(target_player.name .. ' is now a trusted player.', {r = 0.22, g = 0.99, b = 0.99})
                for _, a in pairs(game.connected_players) do
                    if a.admin and a.name ~= player.name then
                        a.print('[ADMIN]: ' .. player.name .. ' trusted ' .. target_player.name, {r = 1, g = 0.5, b = 0.1})
                    end
                end
            end
        else
            if cmd.parameter == nil then
                return
            end
            local target_player = game.players[cmd.parameter]
            if target_player then
                if trusted[target_player.name] == true then
                    game.print(target_player.name .. ' is already trusted!')
                    return
                end
                trusted[target_player.name] = true
                game.print(target_player.name .. ' is now a trusted player.', {r = 0.22, g = 0.99, b = 0.99})
            end
        end
    end
)

commands.add_command(
    'untrust',
    'Demotes a player from trusted!',
    function(cmd)
        local trusted = session.get_trusted_table()
        local player = game.player
        local p

        if player then
            if player ~= nil then
                p = player.print
                if not player.admin then
                    p("You're not admin!", {r = 1, g = 0.5, b = 0.1})
                    return
                end
            else
                p = log
            end

            if cmd.parameter == nil then
                return
            end
            local target_player = game.players[cmd.parameter]
            if target_player then
                if trusted[target_player.name] == false then
                    game.print(target_player.name .. ' is already untrusted!')
                    return
                end
                trusted[target_player.name] = false
                game.print(target_player.name .. ' is now untrusted.', {r = 0.22, g = 0.99, b = 0.99})
                for _, a in pairs(game.connected_players) do
                    if a.admin == true and a.name ~= player.name then
                        a.print('[ADMIN]: ' .. player.name .. ' untrusted ' .. target_player.name, {r = 1, g = 0.5, b = 0.1})
                    end
                end
            end
        else
            if cmd.parameter == nil then
                return
            end
            local target_player = game.players[cmd.parameter]
            if target_player then
                if trusted[target_player.name] == false then
                    game.print(target_player.name .. ' is already untrusted!')
                    return
                end
                trusted[target_player.name] = false
                game.print(target_player.name .. ' is now untrusted.', {r = 0.22, g = 0.99, b = 0.99})
            end
        end
    end
)

local function process_bot_answers(event)
    local player = game.players[event.player_index]
    if player.admin then
        return
    end
    local message = event.message
    message = string.lower(message)
    for word in string.gmatch(message, '%g+') do
        if links[word] then
            for _, bot_answer in pairs(links[word]) do
                player.print('[font=' .. font .. ']' .. bot_answer .. '[/font]', font_color)
            end
            return
        end
    end
end

local function on_console_chat(event)
    if not event.player_index then
        return
    end
    local secs = Server.get_current_time()
    if not secs then
        return
    end
    process_bot_answers(event)
end

--share vision of silent-commands with other admins
local function on_console_command(event)
    local cmd = event.command
    if not event.player_index then
        return
    end
    local player = game.players[event.player_index]
    local param = event.parameters

    if not player.admin then
        return
    end

    local server_time = Server.get_current_time()
    if server_time then
        server_time = format(' (Server time: %s)', Timestamp.to_string(server_time))
    else
        server_time = ' at tick: ' .. game.tick
    end

    if string.len(param) <= 0 then
        param = nil
    end

    local commands = {
        ['editor'] = true,
        ['silent-command'] = true,
        ['sc'] = true,
        ['debug'] = true
    }

    if not commands[cmd] then
        return
    end

    if player then
        for _, p in pairs(game.connected_players) do
            if p.admin == true and p.name ~= player.name then
                if param then
                    p.print(player.name .. ' ran: ' .. cmd .. ' "' .. param .. '" ' .. server_time, {r = 0.22, g = 0.99, b = 0.99})
                else
                    p.print(player.name .. ' ran: ' .. cmd .. server_time, {r = 0.22, g = 0.99, b = 0.99})
                end
            end
        end
        if param then
            print(player.name .. ' ran: ' .. cmd .. ' "' .. param .. '" ' .. server_time)
            return
        else
            print(player.name .. ' ran: ' .. cmd .. server_time)
            return
        end
    else
        if param then
            print('ran: ' .. cmd .. ' "' .. param .. '" ' .. server_time)
            return
        else
            print('ran: ' .. cmd .. server_time)
            return
        end
    end
end


Event.add(defines.events.on_console_chat, on_console_chat)
Event.add(defines.events.on_console_command, on_console_command)
