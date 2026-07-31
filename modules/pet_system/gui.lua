-- 虫子宠物系统 - GUI 绘制模块
local Gui = require 'utils.gui'
local Public = require 'modules.pet_system.table'
local Skills = require 'modules.pet_system.skills'
local TopBar = require 'utils.top_bar'

local draw_main_button_name = Public.draw_main_button_name
local main_frame_name = Public.main_frame_name
local detail_frame_name = Public.detail_frame_name
local confirm_frame_name = Public.confirm_frame_name
local exp_transfer_frame_name = Public.exp_transfer_frame_name
local help_frame_name = Public.help_frame_name
local skill_replace_frame_name = Public.skill_replace_frame_name
local rename_frame_name = Public.rename_frame_name
local card_button_prefix = Public.card_button_prefix

local floor = math.floor

-- ============================================================
-- 辅助函数
-- ============================================================

local function make_hunger_bar(current, max_val)
    local pct = current / max_val
    local filled = floor(pct * 10)
    local bar = ''
    for _ = 1, filled do bar = bar .. '█' end
    for _ = filled + 1, 10 do bar = bar .. '░' end
    return bar .. ' ' .. current .. '/' .. max_val
end

local function quality_color(quality_name)
    local c = Public.quality_colors[quality_name]
    if c then return c end
    return {r = 200, g = 200, b = 200}
end

local function add_label(parent, caption, font, color, width, align, tooltip)
    local e = parent.add({type = 'label', caption = caption})
    e.style.font = font or 'default'
    e.style.font_color = color or {200, 200, 200}
    e.style.single_line = true
    if width then
        e.style.minimal_width = width
        e.style.maximal_width = width
    end
    if align then
        e.style.horizontal_align = align
    end
    if tooltip then
        e.tooltip = tooltip
    end
    return e
end

local function add_stat_button(parent, caption, width, tooltip, name, color, sprite)
    local e = parent.add({
        type = 'sprite-button',
        name = name or nil,
        caption = caption,
        sprite = sprite or nil,
    })
    e.tooltip = tooltip or ''
    e.style.font = 'default-bold'
    e.style.font_color = color or {222, 222, 222}
    e.style.horizontal_align = 'center'
    e.style.vertical_align = 'center'
    if width then
        e.style.maximal_width = width
        e.style.minimal_width = width
    end
    e.style.maximal_height = 32
    e.style.minimal_height = 30
    return e
end

local function add_action_button(parent, caption, name, tooltip)
    local e = parent.add({
        type = 'button',
        name = name,
        caption = caption,
    })
    e.style.font = 'default-bold'
    e.style.font_color = {222, 222, 222}
    e.style.minimal_width = 130
    e.style.maximal_height = 32
    e.style.minimal_height = 30
    if tooltip then
        e.tooltip = tooltip
    end
    return e
end

local function add_separator(parent, width)
    local e = parent.add({type = 'line'})
    e.style.maximal_width = width or 600
    e.style.minimal_width = width or 600
    e.style.top_margin = 4
    e.style.bottom_margin = 4
    return e
end

-- ============================================================
-- 详情面板
-- ============================================================

local function draw_detail_panel(detail_frame, player, pet, pet_index)
    detail_frame.clear()

    local flow = detail_frame.add({type = 'flow', direction = 'vertical'})

    -- 标题行（名字 + 品质 + 等级）
    local title_table = flow.add({type = 'table', column_count = 4})
    add_label(title_table, pet.name, 'default-large-bold', quality_color(pet.quality), 120, 'left')
    add_label(title_table, ({'pet_system.quality_label', Public.quality_locale(pet.quality)}), 'default-bold', quality_color(pet.quality), 120, 'left')
    add_label(title_table, ({'pet_system.level_label', pet.level}), 'default-bold', {220, 220, 100}, 80, 'left')

    -- 关闭详情按钮
    local close_btn = title_table.add({
        type = 'sprite-button',
        name = detail_frame_name .. '_close_' .. pet_index,
        caption = 'X',
    })
    close_btn.style.font_color = {255, 100, 100}
    close_btn.style.maximal_width = 28
    close_btn.style.minimal_width = 28
    close_btn.style.maximal_height = 28
    close_btn.style.minimal_height = 28
    close_btn.style.font = 'default-bold'

    -- 饥饿值
    local hunger_text = ({'pet_system.hunger_label', make_hunger_bar(pet.hunger, pet.max_hunger)})
    local fish_needed = Public.fish_consumption[pet.type] or 1
    add_label(flow, hunger_text, 'default', {180, 230, 180}, 280, 'left')
    add_label(flow, ({'pet_system.fish_per_minute', fish_needed}), 'default', {150, 200, 150}, 200, 'left', ({'pet_system.fish_tooltip'}))

    -- HP / ATK / 经验
    local stats_table = flow.add({type = 'table', column_count = 6})
    add_label(stats_table, ({'pet_system.hp_label', pet.hp, pet.max_hp}), 'default', {220, 100, 100}, 180, 'left')
    add_label(stats_table, ({'pet_system.atk_label', pet.attack}), 'default', {255, 180, 80}, 120, 'left')
    local exp_cur = pet.exp
    local cur_threshold = Public.experience_levels[pet.level] or 0
    local next_threshold = Public.experience_levels[pet.level + 1] or cur_threshold
    local exp_needed = next_threshold - cur_threshold
    add_label(stats_table, ({'pet_system.exp_label', exp_cur, exp_needed}), 'default', {200, 200, 220}, 200, 'left')

    -- 技能展示
    add_separator(flow, 500)
    add_label(flow, ({'pet_system.skills_label'}), 'default-bold', {175, 175, 200}, 60, 'left')
    for i = 1, Public.get_skill_slots(pet) do
        local skill_data = pet.skills[i]
        if skill_data and type(skill_data) == 'table' then
            local qc = Public.quality_colors[skill_data.quality] or {150, 150, 150}
            -- 技能名称 + 品质（通过 locale 显示）
            local display_name = Skills.get_skill_display_name(skill_data.name)
            local name_label = flow.add({
                type = 'label',
                caption = {'', '  ', display_name, ' [', Public.quality_locale(skill_data.quality), ']'},
            })
            name_label.style.font = 'default-bold'
            name_label.style.font_color = qc
            name_label.style.single_line = true
            -- 技能描述（通过 locale 自然语言，含参数）
            local desc = Skills.get_skill_description(skill_data.name, pet, skill_data.quality, player)
            if desc then
                local desc_label = flow.add({type = 'label', caption = {'', '    ', desc}})
                desc_label.style.font = 'default'
                desc_label.style.font_color = {180, 180, 200}
                desc_label.style.single_line = false
                desc_label.style.maximal_width = 480
            end
        else
            local empty_label = flow.add({type = 'label', caption = '  [--]'})
            empty_label.style.font = 'default'
            empty_label.style.font_color = {128, 128, 128}
            empty_label.style.single_line = true
        end
    end

    add_separator(flow, 500)

    -- 操作按钮行
    local action_table = flow.add({type = 'table', column_count = 4})
    add_action_button(action_table, ({'pet_system.allocate_exp'}), detail_frame_name .. '_alloc_exp_' .. pet_index, ({'pet_system.allocate_exp_tip'}))
    add_action_button(action_table, ({'pet_system.reset_points'}), detail_frame_name .. '_reset_pts_' .. pet_index, ({'pet_system.reset_points_tip'}))
    add_action_button(action_table, ({'pet_system.eat_pet'}), detail_frame_name .. '_eat_pet_' .. pet_index, ({'pet_system.eat_pet_tip'}))

    -- 技能书使用（三个按钮）
    local pet_data = Public.get_player_pet_data(player)
    local books = pet_data.skill_books or {low = 0, mid = 0, high = 0}

    local book_table = flow.add({type = 'table', column_count = 4})
    add_label(book_table, ({'pet_system.skill_book_label'}), 'default-bold', {175, 175, 200}, 120, 'right')

    local tiers = {
        {key = 'low',  label = ({'pet_system.book_label'}),     price = '10K', locale_key = 'book_low'},
        {key = 'mid',  label = ({'pet_system.book_label_mid'}),  price = '30K', locale_key = 'book_mid'},
        {key = 'high', label = ({'pet_system.book_label_high'}), price = '60K', locale_key = 'book_high'},
    }
    for _, tier in ipairs(tiers) do
        local count = books[tier.key] or 0
        local btn_name = detail_frame_name .. '_book_' .. tier.key .. '_' .. pet_index
        local btn_caption
        if count > 0 then
            btn_caption = {'', tier.label, '（有', count, '个）'}
        else
            btn_caption = {'', tier.label, '（', tier.price, '）'}
        end
        add_action_button(book_table, btn_caption, btn_name, ({'pet_system.' .. tier.locale_key}))
    end

    add_separator(flow, 500)

    -- 属性加点区域
    add_label(flow, ({'pet_system.attr_allocation'}), 'default-bold', {255, 255, 150}, 200, 'left')

    -- 攻击力加点（左：名称/值/按钮 | 右：已分配点数）
    local atk_table = flow.add({type = 'table', column_count = 7})
    add_label(atk_table, ({'pet_system.attack_label_short'}), 'default-bold', {175, 175, 200}, 60, 'right')
    local atk_val = add_stat_button(atk_table, tostring(pet.attack), 80)
    atk_val.style.horizontal_align = 'center'

    local plus_atk = atk_table.add({
        type = 'sprite-button', name = detail_frame_name .. '_plus_atk_' .. pet_index,
        caption = '+', sprite = 'virtual-signal/signal-green',
    })
    plus_atk.style.maximal_width = 26; plus_atk.style.minimal_width = 26
    plus_atk.style.maximal_height = 26; plus_atk.style.minimal_height = 26
    plus_atk.style.font = 'default-bold'; plus_atk.style.font_color = {0, 0, 0}
    plus_atk.tooltip = ({'pet_system.allocate_info', 1})

    local minus_atk = atk_table.add({
        type = 'sprite-button', name = detail_frame_name .. '_minus_atk_' .. pet_index,
        caption = '-', sprite = 'virtual-signal/signal-red',
    })
    minus_atk.style.maximal_width = 26; minus_atk.style.minimal_width = 26
    minus_atk.style.maximal_height = 26; minus_atk.style.minimal_height = 26
    minus_atk.style.font = 'default-bold'; minus_atk.style.font_color = {0, 0, 0}
    minus_atk.tooltip = ({'pet_system.allocate_info', -1})

    add_label(atk_table, '|', 'default', {128, 128, 128}, 15, 'center')
    add_label(atk_table, ({'pet_system.allocated_label'}), 'default', {150, 150, 150}, 60, 'right')
    add_label(atk_table, ({'pet_system.allocated_points', pet.allocated_attack, '+2'}), 'default-bold', {200, 180, 100}, 130, 'left')

    -- 生命值加点
    local hp_table = flow.add({type = 'table', column_count = 7})
    add_label(hp_table, ({'pet_system.hp_label_short'}), 'default-bold', {175, 175, 200}, 60, 'right')
    local hp_val = add_stat_button(hp_table, tostring(pet.max_hp), 80)
    hp_val.style.horizontal_align = 'center'

    local plus_hp = hp_table.add({
        type = 'sprite-button', name = detail_frame_name .. '_plus_hp_' .. pet_index,
        caption = '+', sprite = 'virtual-signal/signal-green',
    })
    plus_hp.style.maximal_width = 26; plus_hp.style.minimal_width = 26
    plus_hp.style.maximal_height = 26; plus_hp.style.minimal_height = 26
    plus_hp.style.font = 'default-bold'; plus_hp.style.font_color = {0, 0, 0}
    plus_hp.tooltip = ({'pet_system.allocate_info', 1})

    local minus_hp = hp_table.add({
        type = 'sprite-button', name = detail_frame_name .. '_minus_hp_' .. pet_index,
        caption = '-', sprite = 'virtual-signal/signal-red',
    })
    minus_hp.style.maximal_width = 26; minus_hp.style.minimal_width = 26
    minus_hp.style.maximal_height = 26; minus_hp.style.minimal_height = 26
    minus_hp.style.font = 'default-bold'; minus_hp.style.font_color = {0, 0, 0}
    minus_hp.tooltip = ({'pet_system.allocate_info', -1})

    add_label(hp_table, '|', 'default', {128, 128, 128}, 15, 'center')
    add_label(hp_table, ({'pet_system.allocated_label'}), 'default', {150, 150, 150}, 60, 'right')
    add_label(hp_table, ({'pet_system.allocated_points', pet.allocated_hp, '+10'}), 'default-bold', {200, 180, 100}, 130, 'left')

    -- 剩余技能点
    add_label(flow, ({'pet_system.remaining_points', pet.skill_points}), 'default-bold', {255, 200, 50}, 200, 'left')

    return flow
end

-- ============================================================
-- 宠物卡片
-- ============================================================

local function draw_pet_card(parent, player, pet_data, pet, index, card_width)
    local card_frame = parent.add({
        type = 'frame',
        name = 'pet_card_frame_' .. index,
        direction = 'vertical',
    })
    card_frame.style.minimal_width = card_width
    card_frame.style.maximal_width = card_width
    card_frame.style.padding = 4

    if not pet then
        -- 空卡位
        local empty_btn = card_frame.add({
            type = 'sprite-button',
            name = card_button_prefix .. '_' .. index,
            caption = ({'pet_system.empty_slot'}),
            sprite = 'virtual-signal/signal-grey',
        })
        empty_btn.style.minimal_width = card_width - 8
        empty_btn.style.maximal_width = card_width - 8
        empty_btn.style.minimal_height = 160
        empty_btn.style.maximal_height = 160
        empty_btn.style.font = 'default-bold'
        empty_btn.style.font_color = {128, 128, 128}
        empty_btn.tooltip = ({'pet_system.empty_slot_tip'})
        return card_frame
    end

    -- 已拥有的宠物卡片（用 sprite-button 作为可点击的卡片背景）
    local card_btn = card_frame.add({
        type = 'sprite-button',
        name = card_button_prefix .. '_' .. index,
        caption = '',  -- 用内部 table 显示信息
        sprite = 'entity/' .. pet.type,
    })
    card_btn.style.minimal_width = card_width - 8
    card_btn.style.maximal_width = card_width - 8
    card_btn.style.minimal_height = 160
    card_btn.style.maximal_height = 160
    card_btn.style.padding = 2
    card_btn.tooltip = ({'pet_system.card_click_tip'})

    -- 在按钮内添加 table 显示信息（Factorio GUI 支持在 sprite-button 内添加子元素）
    -- 注：部分 Factorio 版本中 sprite-button 不直接支持子元素，改用独立的 frame+button 模式
    -- 这里我们采用另一种方式：在 card_frame 内但 card_btn 下方的 label 方式
    -- 实际改为：用 table 和 button 配合实现卡片

    return card_frame
end

-- ============================================================
-- 宠物卡片（优化版 - 使用 table + button 组合）
-- ============================================================

local function draw_pet_card_v2(parent, pet, index, player)
    local card_width = 185

    local card = parent.add({
        type = 'frame',
        name = 'pet_card_' .. index,
        direction = 'vertical',
    })
    card.style.minimal_width = card_width
    card.style.maximal_width = card_width
    card.style.padding = 4
    card.style.margin = 2

    if not pet then
        -- 空卡位 → 宠物蛋购买区
        add_label(card, ({'pet_system.empty_slot_tip'}), 'default-bold', {180, 180, 100}, card_width - 12, 'center')

        local btn_low = add_action_button(card, ({'pet_system.low_egg', '10K'}), main_frame_name .. '_buy_low_egg', ({'pet_system.low_egg_tip'}))
        btn_low.style.minimal_width = card_width - 16
        btn_low.style.maximal_width = card_width - 16

        local btn_mid = add_action_button(card, ({'pet_system.mid_egg', '30K'}), main_frame_name .. '_buy_mid_egg', ({'pet_system.mid_egg_tip'}))
        btn_mid.style.minimal_width = card_width - 16
        btn_mid.style.maximal_width = card_width - 16

        local btn_high = add_action_button(card, ({'pet_system.high_egg', '60K'}), main_frame_name .. '_buy_high_egg', ({'pet_system.high_egg_tip'}))
        btn_high.style.minimal_width = card_width - 16
        btn_high.style.maximal_width = card_width - 16

        return card
    end

    -- 宠物名字（可双击改名）
    local name_btn = card.add({
        type = 'button',
        name = main_frame_name .. '_rename_' .. index,
        caption = pet.name,
    })
    name_btn.style.font = 'default-large-bold'
    name_btn.style.font_color = quality_color(pet.quality)
    name_btn.style.minimal_width = card_width - 12
    name_btn.style.maximal_width = card_width - 12
    name_btn.style.maximal_height = 26
    name_btn.style.minimal_height = 26
    name_btn.style.horizontal_align = 'center'
    name_btn.style.top_padding = 0
    name_btn.style.bottom_padding = 0
    name_btn.style.left_padding = 2
    name_btn.style.right_padding = 2
    name_btn.tooltip = ({'pet_system.rename_tooltip'})

    -- 宠物精灵图标
    local sprite_btn = card.add({
        type = 'sprite-button',
        name = card_button_prefix .. '_' .. index,
        sprite = 'entity/' .. pet.type,
        caption = '',
    })
    sprite_btn.style.minimal_width = card_width - 12
    sprite_btn.style.maximal_width = card_width - 12
    sprite_btn.style.minimal_height = 46
    sprite_btn.style.maximal_height = 46
    sprite_btn.style.padding = 0
    sprite_btn.tooltip = ({'pet_system.card_click_tip'})

    -- 品质
    add_label(card, ({'pet_system.quality_label', Public.quality_locale(pet.quality)}), 'default-bold', quality_color(pet.quality), card_width - 12, 'center')

    -- 等级
    add_label(card, ({'pet_system.level_short', pet.level}), 'default', {220, 220, 100}, card_width - 12, 'center')

    -- 饥饿条
    local hunger_text = make_hunger_bar(pet.hunger, pet.max_hunger)
    local fish_needed = Public.fish_consumption[pet.type] or 1
    add_label(card, hunger_text, 'default', {180, 230, 180}, card_width - 12, 'center',
        ({'pet_system.hunger_tooltip', fish_needed}))

    -- HP
    add_label(card, ({'pet_system.hp_short', pet.hp, pet.max_hp}), 'default', {220, 100, 100}, card_width - 12, 'center')

    -- ATK
    add_label(card, ({'pet_system.atk_label', pet.attack}), 'default', {255, 180, 80}, card_width - 12, 'center')

    -- 技能
    local skill_text = ''
    local slots = Public.get_skill_slots(pet)
    for i = 1, slots do
        local sd = pet.skills[i]
        if sd then
            local name = type(sd) == 'table' and sd.name or tostring(sd)
            skill_text = skill_text .. '[' .. name .. ']'
        else
            skill_text = skill_text .. '[空]'
        end
        if i < slots then skill_text = skill_text .. ' ' end
    end
    add_label(card, skill_text, 'default', {100, 200, 255}, card_width - 12, 'center', ({'pet_system.skills_tooltip'}))

    return card
end

-- ============================================================
-- 主面板
-- ============================================================

local function draw_main_frame(player, location)
    local screen = player.gui.screen

    -- 销毁已存在的
    local existing = screen[main_frame_name]
    if existing and existing.valid then
        Gui.remove_data_recursively(existing)
        existing.destroy()
    end

    local main_frame = screen.add({
        type = 'frame',
        name = main_frame_name,
        caption = ({'pet_system.main_title'}),
        direction = 'vertical',
    })
    main_frame.location = location or {x = 200, y = 40}
    main_frame.style.minimal_width = 620

    local data = {}
    local pet_data = Public.get_player_pet_data(player)
    local pets = pet_data.pets

    add_separator(main_frame, 600)

    add_separator(main_frame, 600)

    -- 帮助按钮
    local help_flow = main_frame.add({type = 'flow', direction = 'horizontal'})
    local help_btn = help_flow.add({
        type = 'sprite-button',
        name = main_frame_name .. '_help',
        caption = ({'pet_system.help_button'}),
    })
    help_btn.style.font = 'default-large-bold'
    help_btn.style.font_color = {100, 200, 255}
    help_btn.style.maximal_width = 64
    help_btn.style.minimal_width = 64
    help_btn.style.maximal_height = 32
    help_btn.style.minimal_height = 32
    help_btn.tooltip = ({'pet_system.help_button_tip'})

    add_separator(main_frame, 600)

    -- 三张宠物卡片
    local cards_table = main_frame.add({type = 'table', column_count = 3})
    cards_table.style.cell_padding = 2

    for i = 1, 3 do
        local pet = pets[i]
        draw_pet_card_v2(cards_table, pet, i, player)
    end

    data.main_frame = main_frame
    data.current_detail_pet_index = nil

    Gui.set_data(main_frame, data)

    return main_frame
end

-- ============================================================
-- 经验转移弹窗
-- ============================================================

function Public.draw_exp_transfer_popup(player, pet_index)
    local screen = player.gui.screen

    local existing = screen[exp_transfer_frame_name]
    if existing and existing.valid then
        Gui.remove_data_recursively(existing)
        existing.destroy()
    end

    local popup = screen.add({
        type = 'frame',
        name = exp_transfer_frame_name,
        caption = ({'pet_system.exp_transfer_title'}),
        direction = 'vertical',
    })
    popup.location = {x = 300, y = 200}
    popup.style.minimal_width = 350

    local pet_data = Public.get_player_pet_data(player)
    local pet = pet_data.pets[pet_index]
    if not pet then
        popup.destroy()
        return
    end

    add_label(popup, ({'pet_system.exp_transfer_desc'}), 'default', {200, 200, 200}, 300, 'left')

    local input_table = popup.add({type = 'table', column_count = 2})
    add_label(input_table, ({'pet_system.exp_amount'}), 'default-bold', {175, 175, 200}, 80, 'right')
    local textfield = input_table.add({
        type = 'textfield',
        name = exp_transfer_frame_name .. '_input',
        text = '0',
    })
    textfield.style.minimal_width = 120
    textfield.numeric = true

    add_separator(popup, 300)

    local btn_table = popup.add({type = 'table', column_count = 2})
    add_action_button(btn_table, ({'pet_system.confirm'}), exp_transfer_frame_name .. '_confirm_' .. pet_index)
    add_action_button(btn_table, ({'pet_system.cancel'}), exp_transfer_frame_name .. '_cancel')

    local data = {pet_index = pet_index}
    Gui.set_data(popup, data)
end

-- ============================================================
-- 确认弹窗（吞噬宠物）
-- ============================================================

function Public.draw_confirm_eat_popup(player, pet_index)
    local screen = player.gui.screen

    local pet_data = Public.get_player_pet_data(player)
    local pet = pet_data.pets[pet_index]
    if not pet then return end

    local existing = screen[confirm_frame_name]
    if existing and existing.valid then
        Gui.remove_data_recursively(existing)
        existing.destroy()
    end

    local popup = screen.add({
        type = 'frame',
        name = confirm_frame_name,
        caption = ({'pet_system.confirm_eat_title'}),
        direction = 'vertical',
    })
    popup.location = {x = 350, y = 250}
    popup.style.minimal_width = 320

    local type_name = Public.pet_type_names[pet.type] or pet.type
    local cumulative_xp = (Public.experience_levels[pet.level] or 0) + pet.exp
    local exp_return = floor(cumulative_xp * 0.8)
    add_label(popup, ({'pet_system.confirm_eat_desc', type_name, exp_return}), 'default-bold', {255, 150, 100}, 300, 'left')

    add_label(popup, ({'pet_system.confirm_eat_warning'}), 'default', {255, 80, 80}, 300, 'left')

    add_separator(popup, 280)

    local btn_table = popup.add({type = 'table', column_count = 2})
    add_action_button(btn_table, ({'pet_system.confirm_eat_yes'}), confirm_frame_name .. '_yes_' .. pet_index, ({'pet_system.confirm_eat_yes_tip'}))
    add_action_button(btn_table, ({'pet_system.cancel'}), confirm_frame_name .. '_cancel')

    local data = {pet_index = pet_index}
    Gui.set_data(popup, data)
end

-- ============================================================
-- 技能替换选择弹窗
-- ============================================================

function Public.draw_skill_replace_popup(player, pet, pet_index, new_skill)
    local screen = player.gui.screen

    local existing = screen[skill_replace_frame_name]
    if existing and existing.valid then
        Gui.remove_data_recursively(existing)
        existing.destroy()
    end

    local popup = screen.add({
        type = 'frame',
        name = skill_replace_frame_name,
        caption = ({'pet_system.skill_replace_title'}),
        direction = 'vertical',
    })
    popup.location = {x = 300, y = 350}
    popup.style.minimal_width = 420

    -- 新技能信息
    local new_skill_name = Skills.get_skill_display_name(new_skill.name)
    local new_skill_desc = Skills.get_skill_description(new_skill.name, pet, new_skill.quality, player) or ''
    add_label(popup, ({'pet_system.skill_replace_new_title'}), 'default-bold', {100, 200, 255}, 400, 'left')
    add_label(popup, {'', '  ', new_skill_name, ' [', Public.quality_locale(new_skill.quality), ']'}, 'default-bold', {200, 200, 255}, 400, 'left')
    if new_skill_desc ~= '' then
        local new_desc_label = popup.add({type = 'label', caption = {'', '    ', new_skill_desc}})
        new_desc_label.style.font = 'default'
        new_desc_label.style.font_color = {180, 180, 200}
        new_desc_label.style.single_line = false
        new_desc_label.style.maximal_width = 400
    end
    add_separator(popup, 400)
    add_label(popup, ({'pet_system.skill_replace_choose'}), 'default-bold', {255, 200, 100}, 400, 'left')

    for i = 1, Public.get_skill_slots(pet) do
        local existing_skill = pet.skills[i]
        local display_name
        local quality_text = ''
        local desc_text = ''
        if existing_skill and type(existing_skill) == 'table' then
            display_name = Skills.get_skill_display_name(existing_skill.name)
            quality_text = Public.quality_locale(existing_skill.quality)
            -- 获取技能描述
            local desc = Skills.get_skill_description(existing_skill.name, pet, existing_skill.quality, player)
            if desc then
                desc_text = desc
            end
        elseif existing_skill then
            display_name = tostring(existing_skill)
        else
            display_name = '--'
        end
        local btn = popup.add({
            type = 'button',
            name = skill_replace_frame_name .. '_pick_' .. i,
            caption = {'', i .. '. ', display_name, quality_text},
        })
        btn.style.font = 'default-bold'
        btn.style.font_color = {222, 222, 222}
        btn.style.minimal_width = 380
        btn.style.maximal_height = 30
        btn.style.minimal_height = 28
        btn.style.horizontal_align = 'left'
        -- 技能描述 tooltip
        if desc_text ~= '' then
            btn.tooltip = desc_text
        end
        -- 技能描述标签
        if desc_text ~= '' then
            local desc_label = popup.add({type = 'label', caption = {'', '      ', desc_text}})
            desc_label.style.font = 'default'
            desc_label.style.font_color = {160, 160, 180}
            desc_label.style.single_line = true
            desc_label.style.maximal_width = 380
        end
    end

    add_separator(popup, 380)
    local cancel = popup.add({
        type = 'button',
        name = skill_replace_frame_name .. '_cancel',
        caption = ({'pet_system.cancel'}),
    })
    cancel.style.font = 'default-bold'
    cancel.style.minimal_width = 100
    cancel.style.maximal_height = 30

    local data = {
        pet_index = pet_index,
        new_skill = new_skill,
    }
    Gui.set_data(popup, data)
end

-- ============================================================
-- 改名弹窗
-- ============================================================

function Public.draw_rename_popup(player, pet, pet_index)
    local screen = player.gui.screen

    local existing = screen[rename_frame_name]
    if existing and existing.valid then
        Gui.remove_data_recursively(existing)
        existing.destroy()
    end

    local popup = screen.add({
        type = 'frame',
        name = rename_frame_name,
        caption = ({'pet_system.rename_title'}),
        direction = 'vertical',
    })
    popup.location = {x = 360, y = 200}
    popup.style.minimal_width = 300

    add_label(popup, ({'pet_system.rename_desc', pet.name}), 'default', {200, 200, 200}, 270, 'left')

    local input_table = popup.add({type = 'table', column_count = 2})
    add_label(input_table, ({'pet_system.rename_new_name'}), 'default-bold', {175, 175, 200}, 80, 'right')
    local textfield = input_table.add({
        type = 'textfield',
        name = rename_frame_name .. '_input',
        text = pet.name,
    })
    textfield.style.minimal_width = 160

    add_separator(popup, 260)

    local btn_table = popup.add({type = 'table', column_count = 2})
    add_action_button(btn_table, ({'pet_system.confirm'}), rename_frame_name .. '_confirm_' .. pet_index)
    add_action_button(btn_table, ({'pet_system.cancel'}), rename_frame_name .. '_cancel')

    local data = {pet_index = pet_index}
    Gui.set_data(popup, data)
end

function Public.hide_rename_popup(player)
    local screen = player.gui.screen
    local popup = screen[rename_frame_name]
    if popup and popup.valid then
        Gui.remove_data_recursively(popup)
        popup.destroy()
    end
end

-- ============================================================
-- 顶部按钮
-- ============================================================

function Public.draw_top_button(player)
    if TopBar.get_button_flow(player)[draw_main_button_name] then
        return
    end
    local b = TopBar.add_button(player, {
        type = 'sprite-button',
        name = draw_main_button_name,
        caption = ({'pet_system.top_button'}),
        tooltip = ({'pet_system.top_button_tip'}),
    })
    b.style.font_color = {100, 200, 255}
    b.style.left_padding = 4
    b.style.right_padding = 4
    b.style.padding = 0
    b.style.margin = 0
end

-- ============================================================
-- Toggle
-- ============================================================

function Public.toggle(player)
    local screen = player.gui.screen
    local main_frame = screen[main_frame_name]

    if main_frame and main_frame.valid then
        -- 关闭时同时清理子面板（通过主面板数据引用）
        local main_data = Gui.get_data(main_frame)
        if main_data then
            if main_data.detail_frame and main_data.detail_frame.valid then
                Gui.remove_data_recursively(main_data.detail_frame)
                main_data.detail_frame.destroy()
                main_data.detail_frame = nil
            end
        end
        -- 清理弹窗
        for _, popup_name in pairs({confirm_frame_name, exp_transfer_frame_name, help_frame_name, skill_replace_frame_name, rename_frame_name}) do
            local popup = screen[popup_name]
            if popup and popup.valid then
                Gui.remove_data_recursively(popup)
                popup.destroy()
            end
        end
        Gui.remove_data_recursively(main_frame)
        main_frame.destroy()
    else
        draw_main_frame(player)
    end
end

function Public.remove_all(player)
    local screen = player.gui.screen
    local main_frame = screen[main_frame_name]
    if main_frame and main_frame.valid then
        local main_data = Gui.get_data(main_frame)
        if main_data then
            if main_data.detail_frame and main_data.detail_frame.valid then
                Gui.remove_data_recursively(main_data.detail_frame)
                main_data.detail_frame.destroy()
                main_data.detail_frame = nil
            end
        end
        Gui.remove_data_recursively(main_frame)
        main_frame.destroy()
    end
    for _, name in pairs({confirm_frame_name, exp_transfer_frame_name, help_frame_name, skill_replace_frame_name, rename_frame_name}) do
        local f = screen[name]
        if f and f.valid then
            Gui.remove_data_recursively(f)
            f.destroy()
        end
    end
end

-- ============================================================
-- 展开/刷新详情面板
-- ============================================================

function Public.show_detail(player, pet_index)
    local screen = player.gui.screen
    local main_frame = screen[main_frame_name]
    if not main_frame or not main_frame.valid then return end

    local pet_data = Public.get_player_pet_data(player)
    local pet = pet_data.pets[pet_index]
    if not pet then
        -- 空卡位被点击 -> 提示去商店
        player.print({'pet_system.buy_from_shop'}, {r = 255, g = 200, b = 100})
        return
    end

    local main_data = Gui.get_data(main_frame)

    -- 销毁旧详情（直接查 GUI 树比缓存引用更可靠）
    local existing = main_frame[detail_frame_name]
    if existing and existing.valid then
        Gui.remove_data_recursively(existing)
        existing.destroy()
    end
    if main_data then
        main_data.detail_frame = nil
    end

    -- 在主面板底部添加详情框架
    local detail_frame = main_frame.add({
        type = 'frame',
        name = detail_frame_name,
        direction = 'vertical',
        style = 'deep_frame_in_shallow_frame',
    })
    detail_frame.style.padding = 8
    detail_frame.style.top_margin = 4

    draw_detail_panel(detail_frame, player, pet, pet_index)

    -- 更新主面板数据（保存引用以便关闭时直接定位）
    if main_data then
        main_data.current_detail_pet_index = pet_index
        main_data.detail_frame = detail_frame
    end
end

function Public.hide_detail(player)
    local main_frame = player.gui.screen[main_frame_name]
    if not main_frame or not main_frame.valid then return end

    local main_data = Gui.get_data(main_frame)
    local existing = main_frame[detail_frame_name]
    if existing and existing.valid then
        Gui.remove_data_recursively(existing)
        existing.destroy()
    end
    if main_data then
        main_data.current_detail_pet_index = nil
        main_data.detail_frame = nil
    end
end

-- ============================================================
-- 帮助弹窗
-- ============================================================

function Public.draw_help_popup(player)
    local screen = player.gui.screen

    -- 销毁旧弹窗
    local existing = screen[help_frame_name]
    if existing and existing.valid then
        Gui.remove_data_recursively(existing)
        existing.destroy()
    end

    local popup = screen.add({
        type = 'frame',
        name = help_frame_name,
        caption = ({'pet_system.help_title'}),
        direction = 'vertical',
    })
    popup.location = {x = 300, y = 80}
    popup.style.maximal_width = 500
    popup.style.minimal_width = 450

    local scroll = popup.add({
        type = 'scroll-pane',
        direction = 'vertical',
        vertical_scroll_policy = 'auto',
        horizontal_scroll_policy = 'never',
    })
    scroll.style.maximal_height = 450

    local help_label = scroll.add({
        type = 'label',
        caption = ({'pet_system.help_text'}),
    })
    help_label.style.font = 'default'
    help_label.style.font_color = {220, 220, 220}
    help_label.style.single_line = false
    help_label.style.maximal_width = 430

    -- 关闭按钮
    local close_btn = popup.add({
        type = 'button',
        name = help_frame_name .. '_close',
        caption = ({'pet_system.confirm'}),
    })
    close_btn.style.font = 'default-bold'
    close_btn.style.minimal_width = 100
end

function Public.hide_help(player)
    local screen = player.gui.screen
    local popup = screen[help_frame_name]
    if popup and popup.valid then
        Gui.remove_data_recursively(popup)
        popup.destroy()
    end
end

return Public
