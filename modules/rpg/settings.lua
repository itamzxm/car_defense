local Public = require 'modules.rpg.table'
local Gui = require 'utils.gui'
local P = require 'player_modifiers'
local Session = require 'utils.datastore.session_data'

local settings_frame_name = Public.settings_frame_name
local save_button_name = Public.save_button_name
local discard_button_name = Public.discard_button_name
local spell_gui_button_name = Public.spell_gui_button_name
local spell_gui_frame_name = Public.spell_gui_frame_name
local enable_spawning_frame_name = Public.enable_spawning_frame_name
local spell1_button_name = Public.spell1_button_name
local spell2_button_name = Public.spell2_button_name
local spell3_button_name = Public.spell3_button_name
local spell_info_button_name = Public.spell_info_button_name
local spell_info_frame_name = Public.spell_info_frame_name

local settings_level = Public.gui_settings_levels

local function create_input_element(frame, type, value, items, index)
    if type == 'slider' then
        return frame.add({type = 'slider', value = value, minimum_value = 0, maximum_value = 1})
    end
    if type == 'boolean' then
        return frame.add({type = 'checkbox', state = value})
    end
    if type == 'dropdown' then
        return frame.add({type = 'drop-down', items = items, selected_index = index})
    end
    return frame.add({type = 'text-box', text = value})
end

function Public.update_spell_gui_indicator(player)
    local rpg_t = Public.get_value_from_player(player.index)
    local main_frame = player.gui.screen[spell_gui_frame_name]
    if not main_frame then
        return
    end
    local indicator = main_frame['spell_table']['indicator']
    indicator.sprite = 'virtual-signal/signal-' .. (rpg_t.auto_cast_enabled and 'blue' or 'red')
end

function Public.update_spell_gui(player, spell_index)
    local rpg_t = Public.get_value_from_player(player.index)
    local spells, names = Public.rebuild_spells()
    local main_frame = player.gui.screen[spell_gui_frame_name]
    if not main_frame then
        return
    end
    local spell_table = main_frame['spell_table']
    if spell_index then
        if spell_index == 1 then
            rpg_t.dropdown_select_index = rpg_t.dropdown_select_index1
        elseif spell_index == 2 then
            rpg_t.dropdown_select_index = rpg_t.dropdown_select_index2
        elseif spell_index == 3 then
            rpg_t.dropdown_select_index = rpg_t.dropdown_select_index3
        end
    end
    spell_table[spell1_button_name].tooltip = names[rpg_t.dropdown_select_index1] or '---'
    spell_table[spell1_button_name].sprite = spells[rpg_t.dropdown_select_index1].sprite
    spell_table[spell2_button_name].tooltip = names[rpg_t.dropdown_select_index2] or '---'
    spell_table[spell2_button_name].sprite = spells[rpg_t.dropdown_select_index2].sprite
    spell_table[spell3_button_name].tooltip = names[rpg_t.dropdown_select_index3] or '---'
    spell_table[spell3_button_name].sprite = spells[rpg_t.dropdown_select_index3].sprite
    if rpg_t.dropdown_select_index1 == rpg_t.dropdown_select_index then
        spell_table[spell1_button_name].enabled = false
        spell_table[spell1_button_name].number = 1
    else
        spell_table[spell1_button_name].enabled = true
        spell_table[spell1_button_name].number = nil
    end
    if rpg_t.dropdown_select_index2 == rpg_t.dropdown_select_index then
        spell_table[spell2_button_name].enabled = false
        spell_table[spell2_button_name].number = 1
    else
        spell_table[spell2_button_name].enabled = true
        spell_table[spell2_button_name].number = nil
    end
    if rpg_t.dropdown_select_index3 == rpg_t.dropdown_select_index then
        spell_table[spell3_button_name].enabled = false
        spell_table[spell3_button_name].number = 1
    else
        spell_table[spell3_button_name].enabled = true
        spell_table[spell3_button_name].number = nil
    end
    spell_table['mana-cost'].caption = spells[rpg_t.dropdown_select_index].mana_cost
    spell_table['mana'].caption = math.floor(rpg_t.mana)
    spell_table['maxmana'].caption = math.floor(rpg_t.mana_max)

    Public.update_spell_gui_indicator(player)
end

function Public.spell_gui_settings(player)
    local rpg_t = Public.get_value_from_player(player.index)
    local spells, names = Public.rebuild_spells()
    local main_frame = player.gui.screen[spell_gui_frame_name]
    if not main_frame or not main_frame.valid then
        main_frame =
            player.gui.screen.add(
            {
                type = 'frame',
                name = spell_gui_frame_name,
                caption = ({'rpg_settings.spell_name'}),
                direction = 'vertical'
            }
        )
        main_frame.auto_center = true
        local table = main_frame.add({type = 'table', column_count = 4, name = 'spell_table'})
        table.add(
            {
                type = 'sprite-button',
                sprite = 'item/raw-fish',
                name = enable_spawning_frame_name,
                tooltip = ({'rpg_settings.toggle_cast_spell_label'})
            }
        )
        table.add(
            {
                type = 'sprite-button',
                sprite = spells[rpg_t.dropdown_select_index1].sprite,
                name = spell1_button_name,
                tooltip = names[rpg_t.dropdown_select_index1] or '---'
            }
        )
        table.add(
            {
                type = 'sprite-button',
                sprite = spells[rpg_t.dropdown_select_index2].sprite,
                name = spell2_button_name,
                tooltip = names[rpg_t.dropdown_select_index2] or '---'
            }
        )
        table.add(
            {
                type = 'sprite-button',
                sprite = spells[rpg_t.dropdown_select_index3].sprite,
                name = spell3_button_name,
                tooltip = names[rpg_t.dropdown_select_index3] or '---'
            }
        )

        table.add({type = 'sprite-button', name = 'indicator', enabled = false})
        local b1 = table.add({type = 'sprite-button', name = 'mana-cost', tooltip = {'rpg_settings.mana_cost'}, caption = 0})
        local b2 = table.add({type = 'sprite-button', name = 'mana', tooltip = {'rpg_settings.mana'}, caption = 0})
        local b3 = table.add({type = 'sprite-button', name = 'maxmana', tooltip = {'rpg_settings.mana_max'}, caption = 0})
        b1.style.font_color = {r = 0.98, g = 0.98, b = 0.98}
        b2.style.font_color = {r = 0.98, g = 0.98, b = 0.98}
        b3.style.font_color = {r = 0.98, g = 0.98, b = 0.98}
        Public.update_spell_gui(player, nil)
    else
        main_frame.destroy()
    end
end

function Public.spell_info_gui(player)
    local rpg_t = Public.get_value_from_player(player.index)
    local spells, names = Public.rebuild_spells()
    local main_frame = player.gui.screen[spell_info_frame_name]
    if not main_frame or not main_frame.valid then
        main_frame =
            player.gui.screen.add(
            {
                type = 'frame',
                name = spell_info_frame_name,
                caption = ({'rpg_settings.spell_info_title'}),
                direction = 'vertical'
            }
        )
        main_frame.auto_center = true
        
        local scroll_pane = main_frame.add({type = 'scroll-pane'})
        scroll_pane.style.maximal_height = 560
        scroll_pane.style.minimal_width = 500
        
        local table = scroll_pane.add({type = 'table', column_count = 4, name = 'spell_info_table'})
        for i = 1, #spells do
            local spell = spells[i]
            local sprite_button = table.add({type = 'sprite-button', sprite = spell.sprite})
            sprite_button.style.size = 48
            sprite_button.style.padding = 2
            
            local name_label = table.add({type = 'label', caption = spell.name})
            name_label.style.font = 'default-bold'
            name_label.style.vertical_align = 'center'
            name_label.style.padding = {2, 4}
            
            local level_label = table.add({type = 'label', caption = {'rpg_settings.level_label', spell.level}})
            level_label.style.font_color = {r = 1, g = 0.8, b = 0}
            level_label.style.vertical_align = 'center'
            level_label.style.padding = {2, 4}
            
            local mana_cost_label = table.add({type = 'label', caption = {'rpg_settings.mana_cost_label', spell.mana_cost}})
            mana_cost_label.style.font_color = {r = 0.3, g = 0.7, b = 1}
            mana_cost_label.style.vertical_align = 'center'
            mana_cost_label.style.padding = {2, 4}
        end
        
        local bottom_flow = main_frame.add({type = 'flow', name = 'bottom_flow', direction = 'horizontal'})
        bottom_flow.style.horizontal_align = 'center'
        bottom_flow.style.vertical_align = 'bottom'
        local close_button = bottom_flow.add({type = 'button', name = spell_info_frame_name .. '_close', caption = {'rpg_settings.close'}})
    else
        main_frame.destroy()
    end
end

function Public.extra_settings(player)
    local rpg_extra = Public.get('rpg_extra')
    local rpg_t = Public.get_value_from_player(player.index)
    local trusted = Session.get_trusted_table()
    local main_frame =
        player.gui.screen.add(
        {
            type = 'frame',
            name = settings_frame_name,
            caption = ({'rpg_settings.name'}),
            direction = 'vertical'
        }
    )
    main_frame.auto_center = true
    local main_frame_style = main_frame.style
    main_frame_style.width = 500

    local inside_frame = main_frame.add {type = 'frame', style = 'inside_shallow_frame'}
    local inside_frame_style = inside_frame.style
    inside_frame_style.padding = 0
    local inside_table = inside_frame.add {type = 'table', column_count = 1}
    local inside_table_style = inside_table.style
    inside_table_style.vertical_spacing = 0

    inside_table.add({type = 'line'})

    local info_text = inside_table.add({type = 'label', caption = ({'rpg_settings.info_text_label'})})
    local info_text_style = info_text.style
    info_text_style.font = 'default-bold'
    info_text_style.padding = 0
    info_text_style.left_padding = 10
    info_text_style.horizontal_align = 'left'
    info_text_style.vertical_align = 'bottom'
    info_text_style.font_color = {0.55, 0.55, 0.99}

    inside_table.add({type = 'line'})

    local scroll_pane = inside_table.add({type = 'scroll-pane'})
    local scroll_style = scroll_pane.style
    scroll_style.vertically_squashable = true
    scroll_style.maximal_height = 800
    scroll_style.bottom_padding = 5
    scroll_style.left_padding = 5
    scroll_style.right_padding = 5
    scroll_style.top_padding = 5

    local setting_grid = scroll_pane.add({type = 'table', column_count = 2})

    local health_bar_gui_input
    if rpg_extra.enable_health_and_mana_bars then
        local health_bar_label =
            setting_grid.add(
            {
                type = 'label',
                caption = ({'rpg_settings.health_text_label'})
            }
        )

        local style = health_bar_label.style
        style.horizontally_stretchable = true
        style.height = 35
        style.vertical_align = 'center'

        local health_bar_input = setting_grid.add({type = 'flow'})
        local input_style = health_bar_input.style
        input_style.height = 35
        input_style.vertical_align = 'center'
        health_bar_gui_input = create_input_element(health_bar_input, 'boolean', rpg_t.show_bars)
        health_bar_gui_input.tooltip = ({'rpg_settings.tooltip_check'})
        if not rpg_extra.enable_mana then
            health_bar_label.caption = ({'rpg_settings.health_only_text_label'})
        end
    end

    -- local reset_label =
    --     setting_grid.add(
    --     {
    --         type = 'label',
    --         caption = ({'rpg_settings.reset_text_label'}),
    --         tooltip = ''
    --     }
    -- )

    -- local reset_label_style = reset_label.style
    -- reset_label_style.horizontally_stretchable = true
    -- reset_label_style.height = 35
    -- reset_label_style.vertical_align = 'center'

    -- local reset_input = setting_grid.add({type = 'flow'})
    -- local reset_input_style = reset_input.style
    -- reset_input_style.height = 35
    -- reset_input_style.vertical_align = 'center'
    -- local reset_gui_input = create_input_element(reset_input, 'boolean', false)

    -- if not rpg_t.reset then
    --     if rpg_t.level < settings_level['reset_text_label'] then
    --         reset_gui_input.enabled = false
    --         reset_gui_input.tooltip = ({'rpg_settings.low_level', 50})
    --         reset_label.tooltip = ({'rpg_settings.low_level', 50})
    --     else
    --         reset_gui_input.enabled = true
    --         reset_gui_input.tooltip = ({'rpg_settings.reset_tooltip'})
    --         reset_label.tooltip = ({'rpg_settings.reset_tooltip'})
    --     end
    -- else
    --     reset_gui_input.enabled = false
    --     reset_gui_input.tooltip = ({'rpg_settings.used_up'})
    -- end

    ::continue::
    local magic_pickup_label =
        setting_grid.add(
        {
            type = 'label',
            caption = ({'rpg_settings.reach_text_label'}),
            tooltip = ({'rpg_settings.reach_text_tooltip'})
        }
    )

    local magic_pickup_label_style = magic_pickup_label.style
    magic_pickup_label_style.horizontally_stretchable = true
    magic_pickup_label_style.height = 35
    magic_pickup_label_style.vertical_align = 'center'

    local magic_pickup_input = setting_grid.add({type = 'flow'})
    local magic_pickup_input_style = magic_pickup_input.style
    magic_pickup_input_style.height = 35
    magic_pickup_input_style.vertical_align = 'center'
    local reach_mod
    local character_item_pickup_distance_bonus = P.get_single_disabled_modifier(player, 'character_item_pickup_distance_bonus')
    if character_item_pickup_distance_bonus then
        reach_mod = false
    else
        reach_mod = true
    end
    local magic_pickup_gui_input = create_input_element(magic_pickup_input, 'boolean', reach_mod)
    magic_pickup_gui_input.tooltip = ({'rpg_settings.tooltip_check'})

    local movement_speed_label =
        setting_grid.add(
        {
            type = 'label',
            caption = ({'rpg_settings.movement_text_label'}),
            tooltip = ({'rpg_settings.movement_text_tooltip'})
        }
    )

    local movement_speed_label_style = movement_speed_label.style
    movement_speed_label_style.horizontally_stretchable = true
    movement_speed_label_style.height = 35
    movement_speed_label_style.vertical_align = 'center'

    local movement_speed_input = setting_grid.add({type = 'flow'})
    local movement_speed_input_style = movement_speed_input.style
    movement_speed_input_style.height = 35
    movement_speed_input_style.vertical_align = 'center'
    local speed_mod
    local character_running_speed_modifier = P.get_single_disabled_modifier(player, 'character_running_speed_modifier')
    if character_running_speed_modifier then
        speed_mod = false
    else
        speed_mod = true
    end
    local movement_speed_gui_input = create_input_element(movement_speed_input, 'boolean', speed_mod)
    movement_speed_gui_input.tooltip = ({'rpg_settings.tooltip_check'})

    local spell_gui_input1
    local spell_gui_input2
    local spell_gui_input3
    local flame_boots_gui_input
    local explosive_bullets_gui_input
    local stone_path_gui_input
    local one_punch_gui_input
    local auto_allocate_gui_input
    local auto_cast_gui_input

    if rpg_extra.enable_stone_path then
        local stone_path_label =
            setting_grid.add(
            {
                type = 'label',
                caption = ({'rpg_settings.stone_path_label'}),
                tooltip = ({'rpg_settings.stone_path_tooltip'})
            }
        )

        local stone_path_label_style = stone_path_label.style
        stone_path_label_style.horizontally_stretchable = true
        stone_path_label_style.height = 35
        stone_path_label_style.vertical_align = 'center'

        local stone_path_input = setting_grid.add({type = 'flow'})
        local stone_path_input_style = stone_path_input.style
        stone_path_input_style.height = 35
        stone_path_input_style.vertical_align = 'center'
        local stone_path
        if rpg_t.stone_path then
            stone_path = rpg_t.stone_path
        else
            stone_path = false
        end
        stone_path_gui_input = create_input_element(stone_path_input, 'boolean', stone_path)

        if rpg_t.level < settings_level['stone_path_label'] then
            stone_path_gui_input.enabled = false
            stone_path_gui_input.tooltip = ({'rpg_settings.low_level', 20})
            stone_path_label.tooltip = ({'rpg_settings.low_level', 20})
        else
            stone_path_gui_input.enabled = true
            stone_path_gui_input.tooltip = ({'rpg_settings.tooltip_check'})
        end
    end

    if rpg_extra.enable_mana then
        local mana_frame = inside_table.add({type = 'scroll-pane'})
        local mana_style = mana_frame.style
        mana_style.vertically_squashable = true
        mana_style.bottom_padding = 5
        mana_style.left_padding = 5
        mana_style.right_padding = 5
        mana_style.top_padding = 5

        mana_frame.add({type = 'line'})

        local label = mana_frame.add({type = 'label', caption = ({'rpg_settings.mana_label'})})
        label.style.font = 'default-bold'
        label.style.padding = 0
        label.style.left_padding = 10
        label.style.horizontal_align = 'left'
        label.style.vertical_align = 'bottom'
        label.style.font_color = {0.55, 0.55, 0.99}

        mana_frame.add({type = 'line'})

        local setting_grid_2 = mana_frame.add({type = 'table', column_count = 2})

        local mana_grid = mana_frame.add({type = 'table', column_count = 2})

        local spells, names = Public.rebuild_spells()
        if not spells[rpg_t.dropdown_select_index1] then
            rpg_t.dropdown_select_index1 = 1
        end
        if not spells[rpg_t.dropdown_select_index2] then
            rpg_t.dropdown_select_index2 = 1
        end
        if not spells[rpg_t.dropdown_select_index3] then
            rpg_t.dropdown_select_index3 = 1
        end

        mana_frame.add({type = 'label', caption = {'rpg_settings.spell_gui_setup'}})
        mana_frame.add({type = 'label', caption = {'rpg_settings.spell_gui_tooltip'}})
        local spell_grid = mana_frame.add({type = 'table', column_count = 4, name = 'spell_grid_table'})
        spell_gui_input1 = create_input_element(spell_grid, 'dropdown', false, names, rpg_t.dropdown_select_index1)
        spell_gui_input1.style.maximal_width = 135
        spell_gui_input2 = create_input_element(spell_grid, 'dropdown', false, names, rpg_t.dropdown_select_index2)
        spell_gui_input2.style.maximal_width = 135
        spell_gui_input3 = create_input_element(spell_grid, 'dropdown', false, names, rpg_t.dropdown_select_index3)
        spell_gui_input3.style.maximal_width = 135
        spell_grid.add({type = 'sprite-button', name = spell_gui_button_name, sprite = 'item/raw-fish'})
        
        mana_frame.add({type = 'button', name = spell_info_button_name, caption = {'rpg_settings.spell_info_button_label'}})
        
        -- 添加自动施法设置
        local auto_cast_label =
            setting_grid_2.add(
            {
                type = 'label',
                caption = ({'rpg_settings.auto_cast_label'}),
                tooltip = ({'rpg_settings.auto_cast_tooltip'})
            }
        )

        local auto_cast_label_style = auto_cast_label.style
        auto_cast_label_style.horizontally_stretchable = true
        auto_cast_label_style.height = 35
        auto_cast_label_style.vertical_align = 'center'

        local auto_cast_input = setting_grid_2.add({type = 'flow'})
        local auto_cast_input_style = auto_cast_input.style
        auto_cast_input_style.height = 35
        auto_cast_input_style.vertical_align = 'center'
        auto_cast_input_style.horizontal_align = 'right'
        local auto_cast_mod
        if rpg_t.auto_cast_enabled then
            auto_cast_mod = rpg_t.auto_cast_enabled
        else
            auto_cast_mod = false
        end
        auto_cast_gui_input = create_input_element(auto_cast_input, 'boolean', auto_cast_mod)
        auto_cast_gui_input.tooltip = ({'rpg_settings.tooltip_check'})
        
        -- 暂时不设置到data表中，等到data表定义后再设置
    end

    -- 提前定义data表，避免后续访问时出现nil值错误
    local data = {
        reset_gui_input = reset_gui_input,
        magic_pickup_gui_input = magic_pickup_gui_input,
        movement_speed_gui_input = movement_speed_gui_input
    }

    if rpg_extra.enable_auto_allocate then
        local allocate_frame = inside_table.add({type = 'scroll-pane'})
        local allocate_style = allocate_frame.style
        allocate_style.vertically_squashable = true
        allocate_style.bottom_padding = 5
        allocate_style.left_padding = 5
        allocate_style.right_padding = 5
        allocate_style.top_padding = 5

        allocate_frame.add({type = 'line'})

        local a_label = allocate_frame.add({type = 'label', caption = ({'rpg_settings.allocation_settings_label'})})
        a_label.style.font = 'default-bold'
        a_label.style.padding = 0
        a_label.style.left_padding = 10
        a_label.style.horizontal_align = 'left'
        a_label.style.vertical_align = 'bottom'
        a_label.style.font_color = {0.55, 0.55, 0.99}

        allocate_frame.add({type = 'line'})

        local allocate_grid = allocate_frame.add({type = 'table', column_count = 2})

        local allocate_label =
            allocate_grid.add(
            {
                type = 'label',
                caption = ({'rpg_settings.allocation_label'}),
                tooltip = ''
            }
        )
        allocate_label.tooltip = ({'rpg_settings.allocation_tooltip'})

        local names = Public.auto_allocate_nodes

        local allocate_label_style = allocate_label.style
        allocate_label_style.horizontally_stretchable = true
        allocate_label_style.height = 35
        allocate_label_style.vertical_align = 'center'

        local name_input = allocate_grid.add({type = 'flow'})
        local name_input_style = name_input.style
        name_input_style.height = 35
        name_input_style.vertical_align = 'center'
        auto_allocate_gui_input = create_input_element(name_input, 'dropdown', false, names, rpg_t.allocate_index)
        
        data.auto_allocate_gui_input = auto_allocate_gui_input
    end

    if rpg_extra.enable_health_and_mana_bars then
        data.health_bar_gui_input = health_bar_gui_input
    end

    if rpg_extra.enable_mana then
        data.spell_gui_input1 = spell_gui_input1
        data.spell_gui_input2 = spell_gui_input2
        data.spell_gui_input3 = spell_gui_input3
        data.auto_cast_gui_input = auto_cast_gui_input
    end
    
    -- 确保auto_cast_gui_input被正确设置到data表中
    if auto_cast_gui_input then
        data.auto_cast_gui_input = auto_cast_gui_input
    end

    if rpg_extra.enable_flame_boots then
        data.flame_boots_gui_input = flame_boots_gui_input
    end

    if rpg_extra.enable_explosive_bullets_globally then
        data.explosive_bullets_gui_input = explosive_bullets_gui_input
    end

    if rpg_extra.enable_stone_path then
        data.stone_path_gui_input = stone_path_gui_input
    end

    if rpg_extra.enable_one_punch then
        data.one_punch_gui_input = one_punch_gui_input
    end

    if rpg_extra.enable_auto_allocate then
        data.auto_allocate_gui_input = auto_allocate_gui_input
    end

    local bottom_flow = main_frame.add({type = 'flow', direction = 'horizontal'})

    local left_flow = bottom_flow.add({type = 'flow'})
    left_flow.style.horizontal_align = 'left'
    left_flow.style.horizontally_stretchable = true

    local close_button = left_flow.add({type = 'button', name = discard_button_name, caption = ({'rpg_settings.discard_changes'})})
    close_button.style = 'back_button'

    local right_flow = bottom_flow.add({type = 'flow'})
    right_flow.style.horizontal_align = 'right'

    local save_button = right_flow.add({type = 'button', name = save_button_name, caption = ({'rpg_settings.save_changes'})})
    save_button.style = 'confirm_button'

    Gui.set_data(save_button, data)

    player.opened = main_frame
end

return Public
