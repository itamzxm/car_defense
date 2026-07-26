local WD = require 'modules.wave_defense.table'
local diff=require 'maps.amap.diff'

local function create_gui(player)
    local frame = player.gui.top.add({type = 'frame', name = 'wave_defense'})
    frame.style.maximal_height = 37

    local label = frame.add({type = 'label', caption = ' ', name = 'label'})
    label.style.font_color = {r = 0.88, g = 0.88, b = 0.88}
    label.style.font = 'default-bold'
    label.style.font_color = {r = 0.33, g = 0.66, b = 0.9}

    local wave_number_label = frame.add({type = 'label', caption = ' ', name = 'wave_number'})
    wave_number_label.style.font_color = {r = 0.88, g = 0.88, b = 0.88}
    wave_number_label.style.font = 'default-bold'
    wave_number_label.style.right_padding = 4
    wave_number_label.style.font_color = {r = 0.33, g = 0.66, b = 0.9}

    local progressbar = frame.add({type = 'progressbar', name = 'progressbar', value = 0})
    progressbar.style = 'achievement_progressbar'
    progressbar.style.minimal_width = 96
    progressbar.style.maximal_width = 96
    progressbar.style.padding = -1
    progressbar.style.top_padding = 1
    progressbar.style.height = 20

    local line = frame.add({type = 'line', direction = 'vertical'})
    line.style.left_padding = 4
    line.style.right_padding = 4

    local threat_label = frame.add({type = 'label', caption = ' ', name = 'threat', tooltip = {'wave_defense.tooltip_1'}})
    threat_label.style.font = 'default-bold'
    threat_label.style.left_padding = 4
    threat_label.style.font_color = {r = 150, g = 0, b = 255}

    local threat_value_label = frame.add({type = 'label', caption = ' ', name = 'threat_value', tooltip = {'wave_defense.tooltip_1'}})
    threat_value_label.style.font = 'default-bold'
    threat_value_label.style.right_padding = 1
    threat_value_label.style.minimal_width = 10
    threat_value_label.style.font_color = {r = 150, g = 0, b = 255}

    local threat_gains_label = frame.add({type = 'label', caption = ' ', name = 'threat_gains', tooltip = {'wave_defense.tooltip_2'}})
    threat_gains_label.style.font = 'default'
    threat_gains_label.style.left_padding = 1
    threat_gains_label.style.right_padding = 1
end

--display threat gain/loss per minute during last 15 minutes
local function get_threat_gain()
    local threat_log_index = WD.get('threat_log_index') or 0
    local threat_log = WD.get('threat_log') or {}
    local past_index = threat_log_index - 900
    if past_index < 1 then
        past_index = 1
    end
    -- 确保索引在有效范围内
    local current_threat = threat_log[threat_log_index] or 0
    local past_threat = threat_log[past_index] or 0
    local gain = math.floor((current_threat - past_threat) / 15)
    return gain
end

local function update_gui(player)
    if not player.gui.top.wave_defense then
        create_gui(player)
    end
    local gui = player.gui.top.wave_defense
    local biter_health_boost = 1

    local wave_number = WD.get('wave_number')
    local next_wave = WD.get('next_wave')
    local last_wave = WD.get('last_wave')
    local max_active_biters = WD.get('max_active_biters')
    local threat = WD.get('threat') or 0
    local enable_threat_log = WD.get('enable_threat_log')

    -- 确保所有GUI元素都存在且有效
    if not gui.label or not gui.label.valid then return end
    if not gui.wave_number or not gui.wave_number.valid then return end
    if not gui.progressbar or not gui.progressbar.valid then return end
    if not gui.threat or not gui.threat.valid then return end
    if not gui.threat_value or not gui.threat_value.valid then return end

    gui.label.caption = {'wave_defense.gui_2'}
    gui.wave_number.caption = wave_number
    if wave_number == 0 then
        gui.label.caption = {'wave_defense.gui_1'}
        gui.wave_number.caption = math.floor((next_wave - game.tick) / 60) + 1
    end


    local interval = next_wave - last_wave
    local value = 0
    if interval > 0 then
        value = 1 - (next_wave - game.tick) / interval
        if value < 0 then
            value = 0
        elseif value > 1 then
            value = 1
        end
    end
    gui.progressbar.value = value

    gui.threat.caption = {'wave_defense.gui_3'}
    gui.threat.tooltip = {'wave_defense.tooltip_1', biter_health_boost * 100, max_active_biters}
    gui.threat_value.caption = math.floor(threat)
    gui.threat_value.tooltip = {
        'wave_defense.tooltip_1',
        biter_health_boost * 100,
        max_active_biters
    }

    if wave_number == 0 then
        gui.threat_gains.caption = ''
        return
    end
    if enable_threat_log then
        local gain = get_threat_gain()
        local d = wave_number / 75

        if gain >= 0 then
            gui.threat_gains.caption = ' (+' .. gain .. ')'
            local g = 255 - math.floor(gain / d)
            if g < 0 then
                g = 0
            end
            gui.threat_gains.style.font_color = {255, g, 0}
        else
            gui.threat_gains.caption = ' (' .. gain .. ')'
            local r = 255 - math.floor(math.abs(gain) / d)
            if r < 0 then
                r = 0
            end
            gui.threat_gains.style.font_color = {r, 255, 0}
        end
    end
end

return update_gui
