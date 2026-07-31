local ComfyGui = require 'comfy_panel.main'
local Session = require 'utils.datastore.session_data'
local P = require 'player_modifiers'
local Gui = require 'utils.gui'
local GuiDispatcher = require 'utils.gui_dispatcher'
local Color = require 'utils.color_presets'
local TopBar = require 'utils.top_bar'

--RPG Modules
local Public = require 'modules.rpg.table'
local classes = Public.classes

--Tianfu Modules
local TPT = require 'maps.amap.tianfu_table'

--RPG Settings
local experience_levels = Public.experience_levels

--RPG Frames
local main_frame_name = Public.main_frame_name
local draw_main_frame_name = Public.draw_main_frame_name
local settings_button_name = Public.settings_button_name
local settings_frame_name = Public.settings_frame_name
local discard_button_name = Public.discard_button_name
local save_button_name = Public.save_button_name
local enable_spawning_frame_name = Public.enable_spawning_frame_name
local spell_gui_button_name = Public.spell_gui_button_name
local spell_gui_frame_name = Public.spell_gui_frame_name
local spell1_button_name = Public.spell1_button_name
local spell2_button_name = Public.spell2_button_name
local spell3_button_name = Public.spell3_button_name
local spell_info_button_name = Public.spell_info_button_name
local spell_info_frame_name = Public.spell_info_frame_name
local transfer_button_name = Public.transfer_button_name

local sub = string.sub
local round = math.round
local floor = math.floor

function Public.draw_gui_char_button(player)
    if TopBar.get_button_flow(player)[draw_main_frame_name] then
        return
    end
    local b = TopBar.add_button(player, {type = 'sprite-button', name = draw_main_frame_name, caption = '[RPG]', tooltip = 'RPG'})
    b.style.font_color = {0, 0, 0}
    b.style.left_padding = 4
    b.style.right_padding = 4
    b.style.padding = 0
    b.style.margin = 0
end

function Public.update_char_button(player)
    local rpg_t = Public.get_value_from_player(player.index)
    local flow = TopBar.get_button_flow(player)
    if not flow[draw_main_frame_name] then
        Public.draw_gui_char_button(player)
    end
    if rpg_t.points_left > 0 then
        flow[draw_main_frame_name].style.font_color = {245, 0, 0}
    else
        flow[draw_main_frame_name].style.font_color = {0, 0, 0}
    end
end

local function get_class(player)
    local rpg_t = Public.get_value_from_player(player.index)
    local average = (rpg_t.strength + rpg_t.magicka + rpg_t.dexterity + rpg_t.vitality) / 4
    local high_attribute = 0
    local high_attribute_name = ''
    for _, attribute in pairs({'strength', 'magicka', 'dexterity', 'vitality'}) do
        if rpg_t[attribute] > high_attribute then
            high_attribute = rpg_t[attribute]
            high_attribute_name = attribute
        end
    end
    if high_attribute < average + average * 0.25 then
        high_attribute_name = 'engineer'
    end
    return classes[high_attribute_name]
end

local function add_gui_description(element, value, width, tooltip, min_height, max_height)
    local e = element.add({type = 'label', caption = value})
    e.tooltip = tooltip or ''
    e.style.single_line = false
    e.style.maximal_width = width
    e.style.minimal_width = width
    e.style.maximal_height = max_height or 40
    e.style.minimal_height = min_height or 38
    e.style.font = 'default-bold'
    e.style.font_color = {175, 175, 200}
    e.style.horizontal_align = 'right'
    e.style.vertical_align = 'center'
    return e
end

local function add_gui_stat(element, value, width, tooltip, name, color)
    local e = element.add({type = 'sprite-button', name = name or nil, caption = value})
    e.tooltip = tooltip or ''
    e.style.maximal_width = width
    e.style.minimal_width = width
    e.style.maximal_height = 38
    e.style.minimal_height = 38
    e.style.font = 'default-bold'
    e.style.horizontal_align = 'center'
    e.style.vertical_align = 'center'
    e.style.font_color = color or {222, 222, 222}
    return e
end

local function add_elem_stat(element, value, width, height, font, tooltip, name, color)
    local e = element.add({type = 'sprite-button', name = name or nil, caption = value})
    e.tooltip = tooltip or ''
    e.style.maximal_width = width
    e.style.minimal_width = width
    e.style.maximal_height = height
    e.style.minimal_height = height
    e.style.font = font or 'default-bold'
    e.style.horizontal_align = 'center'
    e.style.vertical_align = 'center'
    e.style.font_color = color or {222, 222, 222}
    return e
end

local function add_gui_increase_stat(element, name, player)
    local rpg_t = Public.get_value_from_player(player.index)
    local sprite = 'virtual-signal/signal-red'
    local symbol = '✚'
    if rpg_t.points_left <= 0 then
        sprite = 'virtual-signal/signal-black'
    end
    local e = element.add({type = 'sprite-button', name = name, caption = symbol, sprite = sprite})
    e.style.maximal_height = 38
    e.style.minimal_height = 38
    e.style.maximal_width = 38
    e.style.minimal_width = 38
    e.style.font = 'default-large-semibold'
    e.style.font_color = {0, 0, 0}
    e.style.horizontal_align = 'center'
    e.style.vertical_align = 'center'
    e.style.padding = 0
    e.style.margin = 0
    e.tooltip = ({'rpg_gui.allocate_info', tostring(Public.points_per_level)})

    return e
end

local function add_separator(element, width)
    local e = element.add({type = 'line'})
    e.style.maximal_width = width
    e.style.minimal_width = width
    e.style.minimal_height = 12
    return e
end

local function remove_settings_frame(settings_frame)
    Gui.remove_data_recursively(settings_frame)
    settings_frame.destroy()
end

local function remove_main_frame(main_frame, screen)
    Gui.remove_data_recursively(main_frame)
    main_frame.destroy()

    local settings_frame = screen[settings_frame_name]
    if settings_frame and settings_frame.valid then
        remove_settings_frame(settings_frame)
    end
end

-- 绘制RPG主界面框架
-- @param player 玩家对象
-- @param location 可选的位置参数，用于指定窗口位置
local function draw_main_frame(player, location)
    -- 检查玩家是否有角色实体，如果没有则返回
    if not player.character then
        return
    end

    -- 创建主框架窗口
    local main_frame =
        player.gui.screen.add(
        {
            type = 'frame',
            name = main_frame_name,
            caption = 'RPG',
            direction = 'vertical'
        }
    )
    -- 设置窗口位置，如果提供了位置参数则使用，否则使用默认位置
    if location then
        main_frame.location = location
    else
        main_frame.location = {x = 1, y = 40}
    end

    -- 初始化数据表，用于存储GUI元素的引用
    local data = {}
    -- 获取RPG全局配置数据
    local rpg_extra = Public.get('rpg_extra')
    -- 获取当前玩家的RPG数据
    local rpg_t = Public.get_value_from_player(player.index)

    -- 创建内部框架，用于容纳主要内容
    local inside_frame =
        main_frame.add {
        type = 'frame',
        style = 'deep_frame_in_shallow_frame'
    }
    -- 设置内部框架样式：无边框内边距，最大高度800
    local inside_frame_style = inside_frame.style
    inside_frame_style.padding = 0
    inside_frame_style.maximal_height = 800

    -- 创建内部表格容器
    local inside_table =
        inside_frame.add {
        type = 'table',
        column_count = 1
    }

    -- 创建滚动面板，用于显示超出范围的内容
    local scroll_pane =
        inside_table.add {
        type = 'scroll-pane',
        vertical_scroll_policy = 'never',
        horizontal_scroll_policy = 'never'
    }
    -- 设置滚动面板样式
    local scroll_style = scroll_pane.style
    scroll_style.vertically_squashable = true
    scroll_style.bottom_padding = 2
    scroll_style.left_padding = 2
    scroll_style.right_padding = 2
    scroll_style.top_padding = 2

    --!top table
    -- 创建顶部表格，显示玩家基本信息和操作按钮
    local main_table = scroll_pane.add({type = 'table', column_count = 2})
    -- 添加玩家名称显示，使用玩家聊天颜色和大号粗体字体
    local player_name = add_gui_stat(main_table, player.name, 200, ({'rpg_gui.player_name', player.name}))
    player_name.style.font_color = player.chat_color
    player_name.style.font = 'default-large-bold'
    -- 添加职业等级显示，使用大号粗体字体
    local rank = add_gui_stat(main_table, get_class(player), 200, ({'rpg_gui.class_info', get_class(player)}))
    rank.style.font = 'default-large-bold'

    -- 添加设置按钮，用于打开RPG设置面板
    add_elem_stat(main_table, ({'rpg_gui.settings_name'}), 200, 35, nil, ({'rpg_gui.settings_frame'}), settings_button_name)
    -- 添加转移按钮，用于属性点转移功能
    add_elem_stat(main_table, ({'rpg_gui.transfer_name'}), 200, 35, nil, ({'rpg_gui.transfer_frame'}), transfer_button_name)

    -- 添加分隔线
    add_separator(scroll_pane, 400)

    --!sub top table
    -- 创建次级顶部表格，显示等级、经验等信息
    local scroll_table = scroll_pane.add({type = 'table', column_count = 4})
    scroll_table.style.cell_padding = 1

    -- 添加等级标签
    add_gui_description(scroll_table, ({'rpg_gui.level_name'}), 80)
    -- 根据是否启用等级限制，显示不同的等级信息
    if rpg_extra.level_limit_enabled then
        local level_tooltip = ({'rpg_gui.level_limit', Public.level_limit_exceeded(player, true)})
        add_gui_stat(scroll_table, rpg_t.level, 80, level_tooltip)
    else
        add_gui_stat(scroll_table, rpg_t.level, 80)
    end

    -- 添加经验值标签和数值
    add_gui_description(scroll_table, ({'rpg_gui.experience_name'}), 100)
    local exp_gui = add_gui_stat(scroll_table, floor(rpg_t.xp), 125, ({'rpg_gui.gain_info_tooltip'}))
    data.exp_gui = exp_gui  -- 保存经验值GUI引用，用于后续更新

    -- 添加两个空白占位符，用于布局对齐
    add_gui_description(scroll_table, ' ', 75)
    add_gui_description(scroll_table, ' ', 75)

    -- 添加下一等级所需经验值标签和数值
    add_gui_description(scroll_table, ({'rpg_gui.next_level_name'}), 100)
    add_gui_stat(scroll_table, experience_levels[rpg_t.level + 1], 125, ({'rpg_gui.gain_info_tooltip'}))

    add_separator(scroll_pane, 400)

    --!bottom table
    -- 创建底部表格，分为左右两部分显示属性信息
    local bottom_table = scroll_pane.add({type = 'table', column_count = 2})
    -- 创建左下角表格，显示主要属性
    local left_bottom_table = bottom_table.add({type = 'table', column_count = 3})
    left_bottom_table.style.cell_padding = 1
    -- 定义列宽度常量
    local w0 = 2    -- 最小宽度列
    local w1 = 85   -- 标签列宽度
    local w2 = 63   -- 数值列宽度

    -- 力量属性显示：标签、数值、增加按钮
    add_gui_description(left_bottom_table, ({'rpg_gui.strength_name'}), w1, ({'rpg_gui.strength_tooltip'}))
    add_gui_stat(left_bottom_table, rpg_t.strength, w2, ({'rpg_gui.strength_tooltip'}))
    add_gui_increase_stat(left_bottom_table, 'strength', player)

    -- 魔法属性显示：标签、数值、增加按钮
    add_gui_description(left_bottom_table, ({'rpg_gui.magic_name'}), w1, ({'rpg_gui.magic_tooltip'}))
    add_gui_stat(left_bottom_table, rpg_t.magicka, w2, ({'rpg_gui.magic_tooltip'}))
    add_gui_increase_stat(left_bottom_table, 'magicka', player)

    -- 敏捷属性显示：标签、数值、增加按钮
    add_gui_description(left_bottom_table, ({'rpg_gui.dexterity_name'}), w1, ({'rpg_gui.dexterity_tooltip'}))
    add_gui_stat(left_bottom_table, rpg_t.dexterity, w2, ({'rpg_gui.dexterity_tooltip'}))
    add_gui_increase_stat(left_bottom_table, 'dexterity', player)

    -- 活力属性显示：标签、数值、增加按钮
    add_gui_description(left_bottom_table, ({'rpg_gui.vitality_name'}), w1, ({'rpg_gui.vitality_tooltip'}))
    add_gui_stat(left_bottom_table, rpg_t.vitality, w2, ({'rpg_gui.vitality_tooltip'}))
    add_gui_increase_stat(left_bottom_table, 'vitality', player)

    -- 剩余属性点显示：标签、数值（红色显示）
    add_gui_description(left_bottom_table, ({'rpg_gui.points_to_dist'}), w1)
    add_gui_stat(left_bottom_table, rpg_t.points_left, w2, nil, nil, {200, 0, 0})
    add_gui_description(left_bottom_table, ' ', w2)

    -- 添加三个空白行，用于布局间隔
    add_gui_description(left_bottom_table, ' ', 40)
    add_gui_description(left_bottom_table, ' ', 40)
    add_gui_description(left_bottom_table, ' ', 40)

    -- 生命值显示：当前生命值和最大生命值
    add_gui_description(left_bottom_table, ({'rpg_gui.life_name'}), w1, ({'rpg_gui.life_tooltip'}))
    local health_gui = add_gui_stat(left_bottom_table, floor(player.character.health), w2, ({'rpg_gui.life_increase'}))
    data.health = health_gui  -- 保存生命值GUI引用，用于后续更新
    -- Factorio 2.0中max_health已从prototype移至entity
    if player.character then
        add_gui_stat(
            left_bottom_table,
            floor( player.character.max_health),
            w2,
            ({'rpg_gui.life_maximum'})
        )
    end

    -- 护盾相关变量初始化
    local shield = 0
    local shield_max = 0
    local shield_desc_tip = ({'rpg_gui.shield_no_shield'})
    local shield_tip = ({'rpg_gui.shield_no_armor'})
    local shield_max_tip = shield_tip

    -- 获取玩家护甲物品栏
    local i = player.character.get_inventory(defines.inventory.character_armor)
    -- 检查护甲物品栏是否为空
    if not i.is_empty() then
        -- 检查护甲是否有能量护盾网格
        if i[1].grid then
            -- 获取当前护盾值和最大护盾值
            shield = floor(i[1].grid.shield)
            shield_max = floor(i[1].grid.max_shield)
            -- 更新提示文本
            shield_desc_tip = ({'rpg_gui.shield_tooltip'})
            shield_tip = ({'rpg_gui.shield_current'})
            shield_max_tip = ({'rpg_gui.shield_max'})
            -- 添加护盾显示
            add_gui_description(left_bottom_table, ({'rpg_gui.shield_name'}), w1, shield_desc_tip)
            local shield_gui = add_gui_stat(left_bottom_table, shield, w2, shield_tip)
            local shield_max_gui = add_gui_stat(left_bottom_table, shield_max, w2, shield_max_tip)

            data.shield = shield_gui      -- 保存护盾GUI引用
            data.shield_max = shield_max_gui  -- 保存最大护盾GUI引用
        end
    else
        -- 没有护甲时的护盾显示
        add_gui_description(left_bottom_table, ({'rpg_gui.shield_name'}), w1, shield_desc_tip)
        add_gui_stat(left_bottom_table, shield, w2, shield_tip)
        add_gui_stat(left_bottom_table, shield_max, w2, shield_max_tip)
    end

    -- 如果启用了法力系统，显示法力相关信息
    if rpg_extra.enable_mana then
        local mana = rpg_t.mana
        local mana_max = rpg_t.mana_max

        local mana_tip = ({'rpg_gui.mana_tooltip'})
        add_gui_description(left_bottom_table, ({'rpg_gui.mana_name'}), w1, mana_tip)
        local mana_regen_tip = ({'rpg_gui.mana_regen_current'})
        local mana_max_regen_tip = ({'rpg_gui.mana_max'})
        
        -- 添加法力值和最大法力值显示
        local mana_gui = add_gui_stat(left_bottom_table, mana, w2, mana_regen_tip)
        local mana_max_gui = add_gui_stat(left_bottom_table, mana_max, w2, mana_max_regen_tip)
        data.mana = mana_gui      -- 保存法力值GUI引用
        data.mana_max = mana_max_gui  -- 保存最大法力值GUI引用
    end

    -- 创建右下角表格，显示各种加成信息
    local right_bottom_table = bottom_table.add({type = 'table', column_count = 3})
    right_bottom_table.style.cell_padding = 1

    -- 采矿速度显示
    add_gui_description(right_bottom_table, ' ', w0)
    add_gui_description(right_bottom_table, ({'rpg_gui.mining_name'}), w1)
    local mining_speed_value = round((player.force.manual_mining_speed_modifier + player.character_mining_speed_modifier + 1) * 100) .. '%'
    add_gui_stat(right_bottom_table, mining_speed_value, w2)

    -- 物品栏槽位加成显示
    add_gui_description(right_bottom_table, ' ', w0)
    add_gui_description(right_bottom_table, ({'rpg_gui.slot_name'}), w1)
    local slot_bonus_value = '+ ' .. round(player.force.character_inventory_slots_bonus + player.character_inventory_slots_bonus)
    add_gui_stat(right_bottom_table, slot_bonus_value, w2)
    
    -- 机器人伤害加成显示（基于力量属性）
    add_gui_description(right_bottom_table, ' ', w0)
    add_gui_description(right_bottom_table, ({"rpg_gui.damge_robot"}), w1)
    local damage_robot = '+ ' .. round((rpg_t.strength-10)/25,2)
    add_gui_stat(right_bottom_table, damage_robot, w2)

    -- 近战伤害显示
    add_gui_description(right_bottom_table, ' ', w0)
    add_gui_description(right_bottom_table, ({'rpg_gui.melee_name'}), w1)

    -- 计算近战伤害值和提示信息
    local melee_damage_value = round(100 * (1 + Public.get_melee_modifier(player))) .. '%'
    local melee_damage_tooltip
    if rpg_extra.enable_one_punch then
        -- 如果启用了一击必杀功能，显示相关统计信息
        melee_damage_tooltip = ({
            'rpg_gui.one_punch_chance',
            Public.get_life_on_hit(player),
            Public.get_one_punch_chance(player),
            Public.get_extra_following_robots(player)
        })
    else
        -- 未启用时显示禁用提示
        melee_damage_tooltip = ({'rpg_gui.one_punch_disabled'})
    end
    add_gui_stat(right_bottom_table, melee_damage_value, w2, melee_damage_tooltip)

    -- 添加三个空白行，用于布局间隔
    add_gui_description(right_bottom_table, '', w0, '', nil, 5)
    add_gui_description(right_bottom_table, '', w0, '', nil, 5)
    add_gui_description(right_bottom_table, '', w0, '', nil, 5)

    -- 计算并显示交互距离加成
    local reach_distance_value = '+ ' .. (player.force.character_reach_distance_bonus + player.character_reach_distance_bonus)
    local reach_bonus_tooltip = ({
        'rpg_gui.bonus_tooltip',
        player.character_reach_distance_bonus,
        player.character_build_distance_bonus,
        player.character_item_drop_distance_bonus,
        player.character_loot_pickup_distance_bonus,
        player.character_item_pickup_distance_bonus,
        player.character_resource_reach_distance_bonus,
        Public.get_magicka(player)
    })

    add_gui_description(right_bottom_table, ' ', w0)
    add_gui_description(right_bottom_table, ({'rpg_gui.reach_distance'}), w1)
    add_gui_stat(right_bottom_table, reach_distance_value, w2, reach_bonus_tooltip)

    -- 添加三个空白行，用于布局间隔
    add_gui_description(right_bottom_table, '', w0, '', nil, 10)
    add_gui_description(right_bottom_table, '', w0, '', nil, 10)
    add_gui_description(right_bottom_table, '', w0, '', nil, 10)

    -- 制作速度显示
    add_gui_description(right_bottom_table, ' ', w0)
    add_gui_description(right_bottom_table, ({'rpg_gui.crafting_speed'}), w1)
    local crafting_speed_value = round((player.force.manual_crafting_speed_modifier + player.character_crafting_speed_modifier + 1+rpg_t.crafting_speed) * 100) .. '%'
    add_gui_stat(right_bottom_table, crafting_speed_value, w2)

    -- 移动速度显示
    add_gui_description(right_bottom_table, ' ', w0)
    add_gui_description(right_bottom_table, ({'rpg_gui.running_speed'}), w1)
    local running_speed_value = round((player.force.character_running_speed_modifier + player.character_running_speed_modifier + 1) * 100) .. '%'
    add_gui_stat(right_bottom_table, running_speed_value, w2)

    -- 生命值加成显示
    add_gui_description(right_bottom_table, ' ', w0)
    add_gui_description(right_bottom_table, ({'rpg_gui.health_bonus_name'}), w1)
    local health_bonus_value = '+ ' .. round((player.force.character_health_bonus + player.character_health_bonus))
    local health_tooltip = ({'rpg_gui.health_tooltip', Public.get_heal_modifier(player)})
    add_gui_stat(right_bottom_table, health_bonus_value, w2, health_tooltip)

    add_gui_description(right_bottom_table, ' ', w0)

    -- 如果启用了法力系统，显示法力加成
    if rpg_extra.enable_mana then
        add_gui_description(right_bottom_table, ({'rpg_gui.mana_bonus'}), w1)
        local mana_bonus_value = '+ ' .. (floor(Public.get_mana_modifier(player) * 10) / 10)
        local mana_bonus_tooltip = ({
            'rpg_gui.mana_regen_bonus',
            (floor(Public.get_mana_modifier(player) * 10) / 10)
        })
        add_gui_stat(right_bottom_table, mana_bonus_value, w2, mana_bonus_tooltip)
    end

    -- 添加分隔线
    add_separator(scroll_pane, 400)

    -- 更新角色按钮状态
    Public.update_char_button(player)
    -- 保存主框架引用到数据表中
    data.frame = main_frame

    -- 将数据表与GUI框架关联，便于后续访问和更新
    Gui.set_data(main_frame, data)
end

function Public.draw_level_text(player)
    if not player.character then
        return
    end

    local rpg_t = Public.get_value_from_player(player.index)

    if not rpg_t then
        return
    end

    if rpg_t.text and rpg_t.text.valid then
        rpg_t.text.destroy()
        rpg_t.text = nil
    end

    local players = {}
    for _, p in pairs(game.players) do
        if p.index ~= player.index then
            players[#players + 1] = p.index
        end
    end
    if #players == 0 then
        return
    end

    rpg_t.text =
        rendering.draw_text {
        text = 'lvl ' .. rpg_t.level,
        surface = player.physical_surface,
        target = player.character,
        target_offset = {0, -3.25},
        color = {
            r = player.color.r * 0.6 + 0.25,
            g = player.color.g * 0.6 + 0.25,
            b = player.color.b * 0.6 + 0.25,
            a = 1
        },
        players = players,
        scale = 1.00,
        font = 'default-large-semibold',
        alignment = 'center',
        scale_with_zoom = false
    }
end

function Public.update_player_stats(player)
    if player.force.name ~= 'player' then
        return
    end
    local rpg_extra = Public.get('rpg_extra')
    local rpg_t = Public.get_value_from_player(player.index)
    local strength = rpg_t.strength - 10
    P.update_single_modifier(player, 'character_inventory_slots_bonus', 'rpg', round(strength * 0.2, 3))
    P.update_single_modifier(player, 'character_mining_speed_modifier', 'rpg', round(strength * 0.007, 3)+2)
    P.update_single_modifier(player, 'character_maximum_following_robot_count_bonus', 'rpg', round(strength /35, 3))

    local magic = rpg_t.magicka - 10
    local v = magic * 0.22

    P.update_single_modifier(player, 'character_reach_distance_bonus', 'rpg', math.min(60, round(v * 0.12, 3)))
    P.update_single_modifier(player, 'character_build_distance_bonus', 'rpg', math.min(60, round(v * 0.12, 3)))

    if v >=25 then v = 25 end
    P.update_single_modifier(player, 'character_item_drop_distance_bonus', 'rpg', math.min(60, round(v * 0.05, 3)))
  
    P.update_single_modifier(player, 'character_loot_pickup_distance_bonus', 'rpg', math.min(20, round(v * 0.12, 3)))
    P.update_single_modifier(player, 'character_item_pickup_distance_bonus', 'rpg', math.min(20, round(v * 0.12, 3)))
    P.update_single_modifier(player, 'character_resource_reach_distance_bonus', 'rpg', math.min(20, round(v * 0.05, 3)))
   
    -- 计算基础最大法力值（限制在1500以内）
    local base_mana_max = math.min(round((magic) * 2, 3), 1500)
    
    -- 获取封印卷轴提供的额外法力值
    local this = TPT.get()
    local extra_mana_from_fengyinjuanzhou = this.fengyinjuanzhou_extra_mana[player.index] or 0
    
    -- 计算总最大法力值（基础法力值 + 额外法力值，可以超过1500）
    local total_mana_max = base_mana_max + extra_mana_from_fengyinjuanzhou
    
    rpg_t.mana_max = total_mana_max

    local dexterity = rpg_t.dexterity - 10
    P.update_single_modifier(player, 'character_running_speed_modifier', 'rpg', math.min(3, round(dexterity * 0.0010, 3))) -- reduced since too high speed kills UPS.
    P.update_single_modifier(player, 'character_crafting_speed_modifier', 'rpg', round(dexterity * 0.015, 3)+rpg_t.crafting_speed)
    P.update_single_modifier(player, 'character_health_bonus', 'rpg', round((rpg_t.vitality - 10) * 6, 3))
    P.update_player_modifiers(player)
end

function Public.toggle(player, recreate)
    local screen = player.gui.screen
    local main_frame = screen[main_frame_name]

    if recreate and main_frame then
        local location = main_frame.location
        remove_main_frame(main_frame, screen)
        draw_main_frame(player, location)
        return
    end
    if main_frame then
        remove_main_frame(main_frame, screen)
       -- ComfyGui.comfy_panel_restore_left_gui(player)
    else
      --  ComfyGui.comfy_panel_clear_left_gui(player)
        draw_main_frame(player)
    end
end

function Public.remove_frame(player)
    local screen = player.gui.screen
    local main_frame = screen[main_frame_name]

    if main_frame then
        remove_main_frame(main_frame, screen)
       -- ComfyGui.comfy_panel_restore_left_gui(player)
    end
end

local toggle = Public.toggle
Public.remove_main_frame = remove_main_frame

GuiDispatcher.register_click(draw_main_frame_name, function(event)
    local player = event.player
    if not player or not player.valid or not player.character then
        return
    end

    toggle(player)
end)

GuiDispatcher.register_click(save_button_name, function(event)
    local player = event.player
    if not player or not player.valid or not player.character then
        return
    end

    local screen = player.gui.screen
    local frame = screen[settings_frame_name]
    local data = Gui.get_data(event.element)
    local health_bar_gui_input = data.health_bar_gui_input
    local reset_gui_input = data.reset_gui_input
    local spell_gui_input1 = data.spell_gui_input1
    local spell_gui_input2 = data.spell_gui_input2
    local spell_gui_input3 = data.spell_gui_input3
    local magic_pickup_gui_input = data.magic_pickup_gui_input
    local movement_speed_gui_input = data.movement_speed_gui_input
    local flame_boots_gui_input = data.flame_boots_gui_input
    local explosive_bullets_gui_input = data.explosive_bullets_gui_input
    local stone_path_gui_input = data.stone_path_gui_input
    local one_punch_gui_input = data.one_punch_gui_input
    local auto_allocate_gui_input = data.auto_allocate_gui_input
    local auto_cast_gui_input = data.auto_cast_gui_input

    local rpg_t = Public.get_value_from_player(player.index)

    if frame and frame.valid then
        if auto_allocate_gui_input and auto_allocate_gui_input.valid and auto_allocate_gui_input.selected_index then
            rpg_t.allocate_index = auto_allocate_gui_input.selected_index
        end

        if auto_cast_gui_input and auto_cast_gui_input.valid then
            rpg_t.auto_cast_enabled = auto_cast_gui_input.state
        end

        if one_punch_gui_input and one_punch_gui_input.valid then
            if not one_punch_gui_input.state then
                rpg_t.one_punch = false
            elseif one_punch_gui_input.state then
                rpg_t.one_punch = true
            end
        end

        if stone_path_gui_input and stone_path_gui_input.valid then
            if not stone_path_gui_input.state then
                rpg_t.stone_path = false
            elseif stone_path_gui_input.state then
                rpg_t.stone_path = true
            end
        end

        if flame_boots_gui_input and flame_boots_gui_input.valid then
            if not flame_boots_gui_input.state then
                rpg_t.flame_boots = false
            elseif flame_boots_gui_input.state then
                rpg_t.flame_boots = true
            end
        end

        if explosive_bullets_gui_input and explosive_bullets_gui_input.valid then
            if not explosive_bullets_gui_input.state then
                rpg_t.explosive_bullets = false
            elseif explosive_bullets_gui_input.state then
                rpg_t.explosive_bullets = true
            end
        end

        if movement_speed_gui_input and movement_speed_gui_input.valid then
            if not movement_speed_gui_input.state then
                P.disable_single_modifier(player, 'character_running_speed_modifier', true)
                P.update_player_modifiers(player)
            elseif movement_speed_gui_input.state then
                P.disable_single_modifier(player, 'character_running_speed_modifier', false)
                P.update_player_modifiers(player)
            end
        end

        if magic_pickup_gui_input and magic_pickup_gui_input.valid then
            if not magic_pickup_gui_input.state then
                P.disable_single_modifier(player, 'character_item_pickup_distance_bonus', true)
                P.disable_single_modifier(player, 'character_build_distance_bonus', true)
                P.disable_single_modifier(player, 'character_item_drop_distance_bonus', true)
                P.disable_single_modifier(player, 'character_reach_distance_bonus', true)
                P.disable_single_modifier(player, 'character_loot_pickup_distance_bonus', true)
                P.disable_single_modifier(player, 'character_resource_reach_distance_bonus', true)
                P.update_player_modifiers(player)
            elseif magic_pickup_gui_input.state then
                P.disable_single_modifier(player, 'character_item_pickup_distance_bonus', false)
                P.disable_single_modifier(player, 'character_build_distance_bonus', false)
                P.disable_single_modifier(player, 'character_item_drop_distance_bonus', false)
                P.disable_single_modifier(player, 'character_reach_distance_bonus', false)
                P.disable_single_modifier(player, 'character_loot_pickup_distance_bonus', false)
                P.disable_single_modifier(player, 'character_resource_reach_distance_bonus', false)
                P.update_player_modifiers(player)
            end
        end
        if spell_gui_input1 and spell_gui_input1.valid and spell_gui_input1.selected_index then
            rpg_t.dropdown_select_index1 = spell_gui_input1.selected_index
        end
        if spell_gui_input2 and spell_gui_input2.valid and spell_gui_input2.selected_index then
            rpg_t.dropdown_select_index2 = spell_gui_input2.selected_index
        end
        if spell_gui_input3 and spell_gui_input3.valid and spell_gui_input3.selected_index then
            rpg_t.dropdown_select_index3 = spell_gui_input3.selected_index
        end
        if player.gui.screen[spell_gui_frame_name] then
            Public.update_spell_gui(player, nil)
        end

        if reset_gui_input and reset_gui_input.valid and reset_gui_input.state then
            if not rpg_t.reset then
                rpg_t.allocate_index = 1
                rpg_t.reset = true
                Public.rpg_reset_player(player, true)
            end
        end
        if health_bar_gui_input and health_bar_gui_input.valid then
            if not health_bar_gui_input.state then
                rpg_t.show_bars = false
                Public.update_health(player)
                Public.update_mana(player)
            elseif health_bar_gui_input.state then
                rpg_t.show_bars = true
                Public.update_health(player)
                Public.update_mana(player)
            end
        end

        remove_settings_frame(event.element)

        if player.gui.screen[main_frame_name] then
            toggle(player, true)
        end
    end
end)

GuiDispatcher.register_click(discard_button_name, function(event)
    local player = event.player
    local screen = player.gui.screen
    local frame = screen[settings_frame_name]
    if not player or not player.valid or not player.character then
        return
    end
    if frame and frame.valid then
        Gui.remove_data_recursively(frame)
        frame.destroy()
    end
end)

GuiDispatcher.register_click(settings_button_name, function(event)
    local player = event.player
    local screen = player.gui.screen
    local frame = screen[settings_frame_name]
    if not player or not player.valid or not player.character then
        return
    end

    if frame and frame.valid then
        Gui.remove_data_recursively(frame)
        frame.destroy()
    else
        Public.extra_settings(player)
    end
end)

GuiDispatcher.register_click(transfer_button_name, function(event)
    local player = event.player
    if not player or not player.valid or not player.character then
        return
    end

    local transfer_frame = player.gui.screen[Public.transfer_frame_name]
    if transfer_frame and transfer_frame.valid then
        Gui.remove_data_recursively(transfer_frame)
        transfer_frame.destroy()
    else
        Public.create_transfer_gui(player)
    end
end)

GuiDispatcher.register_click(enable_spawning_frame_name, function(event)
    local player = event.player
    local screen = player.gui.screen
    local frame = screen[spell_gui_frame_name]
    if not player or not player.valid or not player.character then
        return
    end

    if frame and frame.valid then
        local rpg_t = Public.get_value_from_player(player.index)
        if not rpg_t.auto_cast_enabled then
            player.print({'rpg_settings.auto_cast_enabled_label'}, Color.success)
            player.play_sound({path = 'utility/armor_insert', volume_modifier = 0.75})
            rpg_t.auto_cast_enabled = true
        else
            player.print({'rpg_settings.auto_cast_disabled_label'}, Color.warning)
            player.play_sound({path = 'utility/cannot_build', volume_modifier = 0.75})
            rpg_t.auto_cast_enabled = false
        end
        Public.update_spell_gui_indicator(player)
    end
end)

GuiDispatcher.register_click(spell_gui_button_name, function(event)
    local player = event.player
    local screen = player.gui.screen
    local frame = screen[spell_gui_frame_name]
    if not player or not player.valid or not player.character then
        return
    end

    local rpg_t = Public.get_value_from_player(player.index)

    if frame and frame.valid then
        Gui.remove_data_recursively(frame)
        frame.destroy()
        player.print({'rpg_settings.cast_spell_disabled_label'}, Color.warning)
        player.play_sound({path = 'utility/cannot_build', volume_modifier = 0.75})
        rpg_t.enable_entity_spawn = false
    else
        Public.spell_gui_settings(player)
        Public.update_spell_gui_indicator(player)
        player.print({'rpg_settings.cast_spell_enabled_label'}, Color.success)
        player.play_sound({path = 'utility/armor_insert', volume_modifier = 0.75})
        rpg_t.enable_entity_spawn = true
    end
end)

GuiDispatcher.register_click(spell1_button_name, function(event)
    local player = event.player
    local screen = player.gui.screen
    local frame = screen[spell_gui_frame_name]
    if not player or not player.valid or not player.character then
        return
    end

    if frame and frame.valid then
        Public.update_spell_gui(player, 1)
    end
end)

GuiDispatcher.register_click(spell2_button_name, function(event)
    local player = event.player
    local screen = player.gui.screen
    local frame = screen[spell_gui_frame_name]
    if not player or not player.valid or not player.character then
        return
    end

    if frame and frame.valid then
        Public.update_spell_gui(player, 2)
    end
end)

GuiDispatcher.register_click(spell3_button_name, function(event)
    local player = event.player
    local screen = player.gui.screen
    local frame = screen[spell_gui_frame_name]
    if not player or not player.valid or not player.character then
        return
    end

    if frame and frame.valid then
        Public.update_spell_gui(player, 3)
    end
end)

GuiDispatcher.register_click(spell_info_button_name, function(event)
    local player = event.player
    if not player or not player.valid or not player.character then
        return
    end
    Public.spell_info_gui(player)
end)

GuiDispatcher.register_click(spell_info_frame_name .. '_close', function(event)
    local player = event.player
    if not player or not player.valid then
        return
    end
    local frame = player.gui.screen[spell_info_frame_name]
    if frame and frame.valid then
        frame.destroy()
    end
end)

--ComfyGui.screen_to_bypass(spell_gui_frame_name)
--ComfyGui.screen_to_bypass(spell_info_frame_name)
