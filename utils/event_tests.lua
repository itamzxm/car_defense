local Declare = require 'utils.test.declare'
local Assert = require 'utils.test.assert'
local Event = require 'utils.event'
local EventFactory = require 'utils.test.event_factory'
local GuiDispatcher = require 'utils.gui_dispatcher'
local Helper = require 'utils.test.helper'

Declare.module(
    {'utils', 'Event'},
    function()
        local built_count = 0
        local destroyed_count = 0
        local gui_click_count = 0
        local TEST_GUI_BUTTON = 'test_runner_gui_button'

        GuiDispatcher.register_click(TEST_GUI_BUTTON, function()
            gui_click_count = gui_click_count + 1
        end)

        Event.on_built(function()
            built_count = built_count + 1
        end)

        Event.on_destroyed(function()
            destroyed_count = destroyed_count + 1
        end)

        Declare.test(
            'on_built factory fires for build variants',
            function()
                local before = built_count
                EventFactory.raise {name = defines.events.on_built_entity, tick = 1}
                EventFactory.raise {name = defines.events.on_robot_built_entity, tick = 1}
                EventFactory.raise {name = defines.events.script_raised_built, tick = 1}
                EventFactory.raise {name = defines.events.on_entity_cloned, tick = 1}
                Assert.equal(before + 4, built_count)
            end
        )

        Declare.test(
            'on_destroyed factory fires for destroy variants',
            function()
                local before = destroyed_count
                EventFactory.raise {name = defines.events.on_entity_died, tick = 1}
                EventFactory.raise {name = defines.events.on_player_mined_entity, tick = 1}
                EventFactory.raise {name = defines.events.script_raised_destroy, tick = 1}
                Assert.equal(before + 3, destroyed_count)
            end
        )

        Declare.test(
            'factory does not fire for unrelated events',
            function()
                local before_built = built_count
                local before_destroyed = destroyed_count
                EventFactory.raise {name = defines.events.on_player_joined_game, tick = 1, player_index = 1}
                Assert.equal(before_built, built_count)
                Assert.equal(before_destroyed, destroyed_count)
            end
        )

        Declare.test(
            'GuiDispatcher fires for registered button name',
            function(context)
                local before = gui_click_count
                -- 派发器守卫要求元素 valid + 玩家存在；无玩家环境用 fake game.get_player 打通全链路
                Helper.modify_global(context, 'game', {get_player = function()
                    return {valid = true, index = 1}
                end, players = {}})

                local fake_element = {name = TEST_GUI_BUTTON, valid = true}
                EventFactory.raise {name = defines.events.on_gui_click, tick = 1, element = fake_element, player_index = 1}
                Assert.equal(before + 1, gui_click_count)

                local unregistered_element = {name = 'no_such_button', valid = true}
                EventFactory.raise {name = defines.events.on_gui_click, tick = 1, element = unregistered_element, player_index = 1}
                Assert.equal(before + 1, gui_click_count)
            end
        )
    end
)
