local Gui = require 'utils.gui'
local Color = require 'utils.color_presets'

local Public = {}

local pages = {
    require 'utils.debug.public_global_view',
    require 'utils.debug.global_view'
}

if _DEBUG then
    pages[#pages + 1] = require 'utils.debug.gui_data_view'
    pages[#pages + 1] = require 'utils.debug.package_view'
    pages[#pages + 1] = require 'utils.debug._g_view'
    pages[#pages + 1] = require 'utils.debug.event_view'
end

local main_frame_name = Gui.uid_name()
local close_name = Gui.uid_name()
local tab_name = Gui.uid_name()

function Public.open_debug(player)
    for i = 1, #pages do
        local page = pages[i]
        local callback = page.on_open_debug
        if callback then
            callback()
        end
    end

    local screen = player.gui.screen
    local frame = screen[main_frame_name]
    if frame then
        return
    end

    frame = screen.add {type = 'frame', name = main_frame_name, caption = 'Debuggertron 3003', direction = 'vertical'}
    frame.auto_center = true
    local frame_style = frame.style
    frame_style.height = 600
    frame_style.width = 900

    local tab_flow = frame.add {type = 'flow', direction = 'horizontal'}
    local container = frame.add {type = 'flow'}
    container.style.vertically_stretchable = true

    local data = {}

    for i = 1, #pages do
        local page = pages[i]
        local tab_button = tab_flow.add({type = 'flow'}).add {type = 'button', name = tab_name, caption = page.name}
        local tab_button_style = tab_button.style

        Gui.set_data(tab_button, {index = i, frame_data = data})

        if i == 1 then
            tab_button_style.font_color = Color.orange

            data.selected_index = i
            data.selected_tab_button = tab_button
            data.container = container

            Gui.set_data(frame, data)
            page.show(container)
        end
    end

    frame.add {type = 'button', name = close_name, caption = 'Close'}
end

Gui.on_click(
    tab_name,
    function(event)
        local element = event.element
        local data = Gui.get_data(element)

        local index = data.index
        local frame_data = data.frame_data
        local selected_index = frame_data.selected_index

        if selected_index == index then
            return
        end

        local selected_tab_button = frame_data.selected_tab_button
        selected_tab_button.style.font_color = Color.black

        frame_data.selected_tab_button = element
        frame_data.selected_index = index
        element.style.font_color = Color.orange

        local container = frame_data.container
        Gui.clear(container)
        pages[index].show(container)
    end
)

Gui.on_click(
    close_name,
    function(event)
        local frame = event.player.gui.screen[main_frame_name]
        if frame then
            Gui.destroy(frame)
        end
    end
)

return Public
