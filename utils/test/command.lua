local Commands = require 'utils.commands'
local Runner = require 'utils.test.runner'
local Viewer = require 'utils.test.viewer'

Commands.new('test-runner', 'Runs tests and opens the test runner, use flag open to skip running tests first.')
    :add_parameter('open', true)
    :set_default({open = false})
    :callback(function(player, open)
        if open == 'open' or open == 'o' then
            Viewer.open(player)
        else
            Runner.run_module(nil, player)
        end
    end)
