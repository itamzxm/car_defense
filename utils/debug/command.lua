local DebugView = require 'utils.debug.main_view'

commands.add_command(
    'debug',
    'Opens the debugger',
    function(_)
        local player = game.player
        if not player or not player.valid then
            return
        end

        if not player.admin then
            player.print('Only admins can use this command.')
            return
        end

        -- if (player.name ~= 'Gerkiz' and not _DEBUG) then
        --     return
        -- end

        DebugView.open_debug(player)
    end
)

if _DEBUG then
    local Model = require 'model'

    local loadstring = loadstring
    local pcall = pcall
    local dump = Model.dump
    local log = log

    commands.add_command(
        'dump-log',
        'Dumps value to log',
        function(args)
            local player = game.player
            local p
            if player then
                p = player.print
                if not player.admin then
                    p('Only admins can use this command.')
                    return
                end
            else
                p = player.print
            end
            if args.parameter == nil then
                return
            end
            local func, err = loadstring('return ' .. args.parameter)

            if not func then
                p(err)
                return
            end

            local suc, value = pcall(func)

            if not suc then
                p(value)
                return
            end

            log(dump(value))
        end
    )

    commands.add_command(
        'dump-file',
        'Dumps value to dump.lua',
        function(args)
            local player = game.player
            local p
            if player then
                p = player.print
                if not player.admin then
                    p('Only admins can use this command.')
                    return
                end
            else
                p = player.print
            end
            if args.parameter == nil then
                return
            end
            local func, err = loadstring('return ' .. args.parameter)

            if not func then
                p(err)
                return
            end

            local suc, value = pcall(func)

            if not suc then
                p(value)
                return
            end

            value = dump(value)
            game.write_file('dump.lua', value, false)
        end
    )
end
