local ComfyGui = require 'comfy_panel.main'
local Session = require 'utils.datastore.session_data'
local P = require 'player_modifiers'
local Gui = require 'utils.gui'
local Color = require 'utils.color_presets'

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
local spell_info_close_button_name = Public.spell_info_close_button_name
local transfer_button_name = Public.transfer_button_name

-- D6 v2：主面板法术槽按钮（独立 uid 名，勿与法术小窗 spell1/2/3 共用——
-- 那些handler 以 spell_gui_frame_name 有效为门，小窗关闭时直接 return，复用必失效）
local panel_spell1_button_name = Gui.uid_name()
local panel_spell2_button_name = Gui.uid_name()
local panel_spell3_button_name = Gui.uid_name()
local panel_spell_button_names = {panel_spell1_button_name, panel_spell2_button_name, panel_spell3_button_name}
-- D6 v3：主面板槽位下拉框（items 与设置面板下拉框同源 = rebuild_spells() names，同索引基准）
local panel_spell1_dropdown_name = Gui.uid_name()
local panel_spell2_dropdown_name = Gui.uid_name()
local panel_spell3_dropdown_name = Gui.uid_name()
local panel_spell_dropdown_names = {panel_spell1_dropdown_name, panel_spell2_dropdown_name, panel_spell3_dropdown_name}
-- D6 v3：法术区自动施法开关（中文文字两态按钮，toggle auto_cast_enabled，不承担开弹窗副作用）
local panel_cast_toggle_name = Gui.uid_name()
-- D6 v3.2：法术区「施法面板」按钮（只 toggle spell_gui_settings 弹窗，不写任何 rpg_t 状态）
local panel_spell_gui_button_name = Gui.uid_name()
-- 属性分配（回退移植基线加点 UI）：四属性 ✚ 增点钮 uid（点击语义 = 花 points_left，见文件尾 handler）
local alloc_strength_button_name = Gui.uid_name()
local alloc_magicka_button_name = Gui.uid_name()
local alloc_dexterity_button_name = Gui.uid_name()
local alloc_vitality_button_name = Gui.uid_name()
local alloc_button_names = {
    strength = alloc_strength_button_name,
    magicka = alloc_magicka_button_name,
    dexterity = alloc_dexterity_button_name,
    vitality = alloc_vitality_button_name
}

Gui.allow_player_to_toggle_top_element_visibility(draw_main_frame_name)
-- RPG 按钮游戏中高频使用，折叠时始终可见
Gui.register_always_visible_top_element(draw_main_frame_name)

local sub = string.sub
local round = math.round
local floor = math.floor
local strformat = string.format

function Public.draw_gui_char_button(player)
    if Gui.get_button_flow(player)[draw_main_frame_name] then
        return
    end
    local b = Gui.add_top_element(player, {type = 'sprite-button', name = draw_main_frame_name, caption = '[RPG]', tooltip = 'RPG'})
    -- 默认浅灰白字；有未分配技能点时 update_char_button 变红提示
    b.style.font_color = {165, 165, 165}
    -- 文字按钮宽度自适应内容；左右留 4px 空隙（默认继承 button 的 8px，收窄到 4px）
    b.style.left_padding = 4
    b.style.right_padding = 4
end

function Public.update_char_button(player)
    local rpg_t = Public.get_value_from_player(player.index)
    if not Gui.get_button_flow(player)[draw_main_frame_name] then
        Public.draw_gui_char_button(player)
    end
    local button = Gui.get_button_flow(player)[draw_main_frame_name]
    if rpg_t.points_left > 0 then
        -- 有未分配技能点：红色提示（保持）
        button.style.font_color = {245, 0, 0}
        button.tooltip = 'RPG'
    else
        -- 默认浅灰白字
        button.style.font_color = {165, 165, 165}
        button.tooltip = 'RPG'
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

local function add_separator(element, width)
    local e = element.add({type = 'line'})
    e.style.maximal_width = width
    e.style.minimal_width = width
    e.style.minimal_height = 12
    return e
end

-- ── D6 真相面板辅助（回退后：纯属性数据源，成长角标/来源行随 growth 数据源移除）──

-- 最终伤害区间（与 get_final_damage_modifier 同源：rng 两端取 0.10/0.35；
-- growth 回退后第二参恒传 0，保留签名兼容纯函数自检）
local function final_damage_range(strength, g_final)
    return round(((strength - 10) * 0.10 + g_final) * 100), round(((strength - 10) * 0.35 + g_final) * 100)
end

-- 经验进度比例（clamp 0~1：xp 可能越级溢出；缺级/除零兜底 0）
local function exp_progress_ratio(xp, next_level)
    if next_level and next_level > 0 then
        return math.max(0, math.min(1, xp / next_level))
    end
    return 0
end

-- 纯函数暴露（qa/d6_panel_selfcheck.lua 消费；无 GUI 依赖）
Public.final_damage_range = final_damage_range
Public.exp_progress_ratio = exp_progress_ratio

-- D6 v2 法术区纯逻辑：槽位解析（idx 非法/越界 → nil = 未配置或被禁用；
-- 数据源为 rebuild_spells() 的 enabled 过滤表，与设置下拉框/施法链同索引基准）
function Public.resolve_spell_slot(spells, idx)
    if type(idx) == 'number' and spells and spells[idx] then
        return spells[idx]
    end
    return nil
end

-- D6 v2 法术区纯逻辑：槽位 n 的切换目标值（settings.lua:54-58 同语义：
-- dropdown_select_index = dropdown_select_indexN；N 未配置时为 nil，施法链 nil-check 兜底）
function Public.panel_spell_target_index(rpg_t, n)
    return rpg_t and rpg_t['dropdown_select_index' .. n] or nil
end

-- D6 v3 纯逻辑：槽位下拉框写入（与设置面板下拉框同语义：仅接受有效正序号，
-- nil/非法序号不写回 rpg_t——"未配置"语义由按钮灰化承担）
function Public.panel_spell_dropdown_write(rpg_t, n, selected_index)
    if rpg_t and type(selected_index) == 'number' and selected_index >= 1 and selected_index % 1 == 0 then
        rpg_t['dropdown_select_index' .. n] = selected_index
    end
    return Public.panel_spell_target_index(rpg_t, n)
end

-- D6 v3 纯逻辑：自动施法开关翻转（单一真值源 auto_cast_enabled；只做取反不做分支副作用）
function Public.panel_cast_toggle_state(state)
    return not state
end

-- C 区组标题（原生 table 无 colspan：标题独立于组表之外，垂直堆叠）
-- caption 构造为纯函数（QA headless 断言用）：LocalisedString 必须用 {'', 前缀, 翻译} 组合，
-- 严禁 '前缀' .. {'key'} 字符串拼接（table 不可拼接 → 打开面板必崩，BUG-7 根因）。
function Public.group_title_caption(locale_key)
    return {'', '▍', {'rpg_gui.' .. locale_key}}
end

-- A5 方案二第四列：每属性「每点收益率」caption/tooltip 键构造（纯函数，QA headless 断言用，
-- 同 group_title_caption 的 BUG-7 守卫模式：LocalisedString 走组合构造，严禁字符串拼接）。
-- 数值出处（零发明）：functions.lua:608 / 673 / 688、gui.lua:924、table.lua:44（points_per_level）。
function Public.alloc_rate_caption(attribute)
    return {'rpg_gui.alloc_rate_' .. attribute}
end

function Public.alloc_rate_tooltip(attribute)
    return {'rpg_gui.alloc_rate_' .. attribute .. '_tooltip'}
end

-- A5 方案二 v2 第四列（制作人迭代）：可见描述复用既有属性 tooltip 文案键——与悬停数值框同一段文案，
-- 拉到卡面直读；每点收益率互换进悬停。键构造纯函数供 QA 同源断言。
function Public.alloc_desc_caption(attribute)
    return {'rpg_gui.' .. (attribute == 'magicka' and 'magic_tooltip' or (attribute .. '_tooltip'))}
end

local function add_group_title(flow, locale_key)
    local e = flow.add({type = 'label', caption = Public.group_title_caption(locale_key)})
    e.style.font = 'default-bold'
    e.style.font_color = {175, 175, 200}
    e.style.minimal_height = 22
    return e
end

-- C/B 区组表（回退后 2 列：标签 / 主值）
local function add_stat_table(flow)
    local t = flow.add({type = 'table', column_count = 2})
    t.style.cell_padding = 1
    return t
end

local function add_gui_row_label(table, caption, tooltip, width)
    local e = table.add({type = 'label', caption = caption})
    e.tooltip = tooltip or ''
    e.style.minimal_width = width or 80
    e.style.maximal_width = width or 80
    e.style.minimal_height = 26
    e.style.font = 'default-bold'
    e.style.font_color = {175, 175, 200}
    e.style.horizontal_align = 'right'
    e.style.vertical_align = 'center'
    return e
end

local function add_gui_row_value(table, caption, tooltip, width)
    local e = table.add({type = 'label', caption = caption})
    e.tooltip = tooltip or ''
    e.style.minimal_width = width or 74
    e.style.maximal_width = width or 74
    e.style.minimal_height = 26
    e.style.font = 'default-bold'
    e.style.font_color = {222, 222, 222}
    e.style.horizontal_align = 'center'
    e.style.vertical_align = 'center'
    return e
end

-- B 区状态行（D6-T10）：4 列「标签 | 当前 | / | 上限」——当前右对齐、上限左对齐夹住 "/"，
-- 数字贴合成一组读作 "780 / 1000"（替换 v3.2 两格 150px 分离式）。
-- 当前/上限两格按 data 契约原样返回（health/shield/shield_max/mana/mana_max 由调用方挂载，
-- functions.lua 增量刷新只覆写 caption 纯数字，故 "/" 必须是独立不受契约约束的第三格）。
-- has_value=false（无护甲护盾）：当前/上限显示占位、"/" 隐去。
local function add_vital_row(table, label, label_tip, cur_caption, cur_tip, has_value, max_caption, max_tip)
    add_gui_row_label(table, label, label_tip, 60)
    local cur = table.add({type = 'label', caption = cur_caption})
    cur.tooltip = cur_tip or ''
    cur.style.minimal_width = 64
    cur.style.maximal_width = 64
    cur.style.minimal_height = 26
    cur.style.font = 'default-bold'
    cur.style.font_color = {222, 222, 222}
    cur.style.horizontal_align = 'right'
    cur.style.vertical_align = 'center'
    local slash = table.add({type = 'label', caption = has_value and '/' or ''})
    slash.style.minimal_width = 16
    slash.style.maximal_width = 16
    slash.style.minimal_height = 26
    slash.style.font = 'default'
    slash.style.font_color = {120, 120, 135}
    slash.style.horizontal_align = 'center'
    slash.style.vertical_align = 'center'
    local max_e = table.add({type = 'label', caption = max_caption})
    max_e.tooltip = max_tip or ''
    max_e.style.minimal_width = 64
    max_e.style.maximal_width = 64
    max_e.style.minimal_height = 26
    max_e.style.font = 'default-bold'
    max_e.style.font_color = {168, 165, 160}
    max_e.style.horizontal_align = 'left'
    max_e.style.vertical_align = 'center'
    return cur, max_e
end

-- C 区一行：标签 | 主值（回退：成长角标列随 growth 数据源移除，T3-C 行级 trace 路由同撤）
local function add_stat_row(table, label, label_tooltip, value)
    add_gui_row_label(table, label, label_tooltip)
    add_gui_row_value(table, value)
end

-- 属性分配 ✚ 增点钮（回退移植基线 gui.lua 同名函数；name 改用 uid 路由，点击语义见文件尾 handler）
local function add_gui_increase_stat(element, attribute, player)
    local rpg_t = Public.get_value_from_player(player.index)
    local sprite = 'virtual-signal/signal-red'
    if rpg_t.points_left <= 0 then
        sprite = 'virtual-signal/signal-black'
    end
    local e =
        element.add(
        {type = 'sprite-button', name = alloc_button_names[attribute], caption = '✚', sprite = sprite}
    )
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
        main_frame.location = {x = 1, y = 80}
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

    -- 创建滚动面板，用于显示超出范围的内容（D6：超高内容纵向滚动兜底）
    local scroll_pane =
        inside_frame.add {
        type = 'scroll-pane',
        vertical_scroll_policy = 'auto',
        horizontal_scroll_policy = 'never'
    }
    -- 设置滚动面板样式
    local scroll_style = scroll_pane.style
    scroll_style.vertically_squashable = true
    scroll_style.bottom_padding = 2
    scroll_style.left_padding = 2
    scroll_style.right_padding = 2
    scroll_style.top_padding = 2

    --!A 身份区（D6-T10 收紧为 4 行：名 / 职业+等级同行 / 经验条 / 按钮行；
    -- 既有元素与 tooltip 全保留，data.exp_gui 刷新契约不变）
    local head_left = scroll_pane.add({type = 'flow', direction = 'vertical'})

    -- A1 玩家名（聊天色，扫读锚点）
    local player_name = head_left.add({type = 'label', caption = player.name})
    player_name.tooltip = ({'rpg_gui.player_name', player.name})
    player_name.style.font = 'default-large-bold'
    player_name.style.font_color = player.chat_color
    player_name.style.minimal_height = 24

    -- A2 职业 + 等级同行（D6-T10：职业橙固定 110px 起点保证多行节奏，等级灰标签 + 暖白数字顺排；
    -- level_limit_enabled 时 tooltip 提示上限，挂标签与数字两处）
    local class_caption = get_class(player)
    local id_row = head_left.add({type = 'flow', direction = 'horizontal'})
    local rank = id_row.add({type = 'label', caption = class_caption})
    rank.tooltip = ({'rpg_gui.class_info', class_caption})
    rank.style.font = 'default-bold'
    rank.style.font_color = {255, 184, 77}
    rank.style.minimal_width = 110
    rank.style.maximal_width = 110
    rank.style.vertical_align = 'center'
    local level_tooltip
    if rpg_extra.level_limit_enabled then
        level_tooltip = ({'rpg_gui.level_limit', Public.level_limit_exceeded(player, true)})
    end
    local level_label = id_row.add({type = 'label', caption = ({'rpg_gui.level_name'})})
    level_label.tooltip = level_tooltip or ''
    level_label.style.font = 'default'
    level_label.style.font_color = {168, 165, 160}
    level_label.style.vertical_align = 'center'
    local level_value = id_row.add({type = 'label', caption = rpg_t.level})
    level_value.tooltip = level_tooltip or ''
    level_value.style.font = 'default-bold'
    level_value.style.font_color = {255, 230, 179}
    level_value.style.vertical_align = 'center'

    -- A3 经验进度条 + "当前 / 下一级"（原型 .xpbar：条与数字同行；
    -- exp_gui 格被 main.lua 增量刷新覆写为纯数字（契约），"/ 下一级" 独立成不受契约约束的尾格；
    -- xp=0 时条空但宽度固定布局稳定）
    local exp_next = experience_levels[rpg_t.level + 1] or experience_levels[#experience_levels]
    local xp_table = head_left.add({type = 'table', column_count = 3})
    xp_table.style.cell_padding = 1
    local exp_bar = xp_table.add({type = 'progressbar', value = exp_progress_ratio(rpg_t.xp, exp_next)})
    exp_bar.tooltip = ({'rpg_gui.exp_progress_tooltip', floor(rpg_t.xp), exp_next})
    exp_bar.style.minimal_width = 276
    exp_bar.style.maximal_width = 276
    local exp_gui = xp_table.add({type = 'label', caption = floor(rpg_t.xp)})
    exp_gui.tooltip = ({'rpg_gui.gain_info_tooltip'})
    exp_gui.style.font = 'default-small'
    exp_gui.style.font_color = {150, 150, 160}
    exp_gui.style.minimal_width = 64
    exp_gui.style.maximal_width = 64
    exp_gui.style.horizontal_align = 'right'
    exp_gui.style.vertical_align = 'center'
    local exp_next_gui = xp_table.add({type = 'label', caption = '/ ' .. exp_next})
    exp_next_gui.tooltip = ({'rpg_gui.exp_progress_tooltip', floor(rpg_t.xp), exp_next})
    exp_next_gui.style.font = 'default-small'
    exp_next_gui.style.font_color = {120, 120, 135}
    exp_next_gui.style.minimal_width = 64
    exp_next_gui.style.maximal_width = 64
    data.exp_gui = exp_gui

    -- A4 设置/转移入口（两颗等宽 150×30；「转移」文案见 locale transfer_name）
    local id_btn_table = head_left.add({type = 'table', column_count = 2})
    id_btn_table.style.cell_padding = 1
    add_elem_stat(id_btn_table, ({'rpg_gui.settings_name'}), 150, 30, nil, ({'rpg_gui.settings_frame'}), settings_button_name)
    add_elem_stat(id_btn_table, ({'rpg_gui.transfer_name'}), 150, 30, nil, ({'rpg_gui.transfer_frame'}), transfer_button_name)

    --!A5 属性分配（回退移植基线加点区：每属性 ✚ 增点钮 + 剩余属性点；点击语义见文件尾 Gui.on_click；
    -- 自动分配下拉在设置面板（settings.lua allocate_index），升级自动分配走 functions.lua level_up，双模式兼容。
    -- 方案二 v2（制作人迭代实装）：3 列 → 4 列，第四列 = 属性描述可见文本（复用既有 *_tooltip 文案键、
    -- 白字 {222,222,222} 与状态行同色、允许多行、限宽 220 不溢出）；每点收益率互换进第四列悬停
    -- （描述为主、收益率为 tooltip 补充）；「每级 +5 点」收进剩余点数两格 tooltip；
    -- ✚ 四钮 uid/name/handler 与点击语义（左+1/右+5/Shift+左全投/Shift+右半投）零改动）
    add_separator(scroll_pane, 410)
    local alloc_title_flow = scroll_pane.add({type = 'flow', direction = 'horizontal'})
    add_group_title(alloc_title_flow, 'alloc_group_title')
    local alloc_table = scroll_pane.add({type = 'table', column_count = 4})
    alloc_table.style.cell_padding = 1
    local alloc_w1 = 85
    local alloc_w2 = 63
    for _, attribute in ipairs({'strength', 'magicka', 'dexterity', 'vitality'}) do
        local label_key = attribute == 'magicka' and 'magic_name' or (attribute .. '_name')
        local tip_key = attribute == 'magicka' and 'magic_tooltip' or (attribute .. '_tooltip')
        add_gui_description(alloc_table, ({'rpg_gui.' .. label_key}), alloc_w1, ({'rpg_gui.' .. tip_key}))
        add_gui_stat(alloc_table, rpg_t[attribute], alloc_w2, ({'rpg_gui.' .. tip_key}))
        add_gui_increase_stat(alloc_table, attribute, player)
        -- 第四列：描述可见 + 收益率进悬停（键构造单一真值源 Public.alloc_desc_caption /
        -- alloc_rate_caption/tooltip，QA 同源断言）
        local rate = alloc_table.add({type = 'label', caption = Public.alloc_desc_caption(attribute)})
        rate.tooltip = {'', Public.alloc_rate_caption(attribute), '\n', Public.alloc_rate_tooltip(attribute)}
        rate.style.font = 'default-small'
        rate.style.font_color = {222, 222, 222}
        rate.style.single_line = false
        rate.style.maximal_width = 220
        rate.style.left_padding = 8
        rate.style.vertical_align = 'center'
    end
    -- 剩余点数行：「每级 +5 点」收进两格 tooltip（Public.points_per_level 同源，table.lua:44）
    add_gui_description(alloc_table, ({'rpg_gui.points_to_dist'}), alloc_w1, {'rpg_gui.alloc_rate_per_level'})
    add_gui_stat(alloc_table, rpg_t.points_left, alloc_w2, {'rpg_gui.alloc_rate_per_level'}, nil, {200, 0, 0})

    --!B 当下状态：生命/护盾/法力（D6-T10：4 列贴合行「标签|当前|/|上限」，数字读作一组；
    -- data 引用契约与原面板一致；无护甲/无网格 → — 、空、— 交代）
    add_separator(scroll_pane, 410)
    local status_table = scroll_pane.add({type = 'table', column_count = 4})
    status_table.style.cell_padding = 1

    -- B1 生命（上限格无 data 契约：刷新链只增量覆写当前值）
    local health_gui =
        add_vital_row(
        status_table,
        ({'rpg_gui.life_name'}),
        ({'rpg_gui.life_tooltip'}),
        floor(player.character.health),
        ({'rpg_gui.life_increase'}),
        true,
        floor(player.character.max_health),
        ({'rpg_gui.life_maximum'})
    )
    data.health = health_gui

    -- B2 护盾（无护甲或无网格 → — —，不用 0/0 表达"无数据"；"/" 隐去）
    local shield = 0
    local shield_max = 0
    local has_shield_grid = false
    local shield_desc_tip = ({'rpg_gui.shield_no_shield'})
    local shield_tip = ({'rpg_gui.shield_no_armor'})
    local shield_max_tip = shield_tip
    local armor_inventory = player.character.get_inventory(defines.inventory.character_armor)
    if not armor_inventory.is_empty() and armor_inventory[1].grid then
        has_shield_grid = true
        shield = floor(armor_inventory[1].grid.shield)
        shield_max = floor(armor_inventory[1].grid.max_shield)
        shield_desc_tip = ({'rpg_gui.shield_tooltip'})
        shield_tip = ({'rpg_gui.shield_current'})
        shield_max_tip = ({'rpg_gui.shield_max'})
    end
    local shield_gui, shield_max_gui =
        add_vital_row(
        status_table,
        ({'rpg_gui.shield_name'}),
        shield_desc_tip,
        has_shield_grid and shield or '—',
        shield_tip,
        has_shield_grid,
        has_shield_grid and shield_max or '—',
        shield_max_tip
    )
    data.shield = shield_gui
    data.shield_max = shield_max_gui

    -- B3 法力（enable_mana 条件行）
    if rpg_extra.enable_mana then
        local mana_gui, mana_max_gui =
            add_vital_row(
            status_table,
            ({'rpg_gui.mana_name'}),
            ({'rpg_gui.mana_tooltip'}),
            rpg_t.mana,
            ({'rpg_gui.mana_regen_current'}),
            true,
            rpg_t.mana_max,
            ({'rpg_gui.mana_max'})
        )
        data.mana = mana_gui
        data.mana_max = mana_max_gui
    end

    --!D 区：法术（状态行之下；enable_mana 条件；D6-T10 三行结构：标题行[▍法术|自动施法两态|施法面板] +
    -- 3 槽[图标钮+▼角标+下拉框] + 当前法术状态行，施法机制零改动）
    if rpg_extra.enable_mana then
        -- 现读 enabled 过滤表（不缓存旧引用）：disable_spell 等运行时变化在下次重建自动生效；
        -- names 为第二返回值（enabled 过滤名单），与设置面板下拉框/施法链同索引基准
        local spells, spell_names = Public.rebuild_spells()
        local active_idx = rpg_t.dropdown_select_index

        -- 区标题行（D6-T10 三列一行：▍法术 | 「自动施法」两态开关 | 「施法面板」入口——
        -- 原 v3.2 的全宽「施法面板」按钮行撤销，法术区 4 行收紧为 3 行）
        local spell_title_row = scroll_pane.add({type = 'table', column_count = 3})
        spell_title_row.style.cell_padding = 0
        local title_cell = spell_title_row.add({type = 'flow', direction = 'horizontal'})
        add_group_title(title_cell, 'spell_zone_title')
        local cast_on = rpg_t.auto_cast_enabled == true
        -- v3.2 中文化：文字按钮替鱼形图标——caption 直接表达两态（开绿/关灰，沿 font_color 两态实证范式）
        local cast_btn =
            spell_title_row.add(
            {
                type = 'button',
                name = panel_cast_toggle_name,
                caption = cast_on and {'rpg_gui.spell_cast_btn_on'} or {'rpg_gui.spell_cast_btn_off'},
                tooltip = cast_on and {'rpg_gui.spell_cast_toggle_tooltip_on'} or {'rpg_gui.spell_cast_toggle_tooltip_off'}
            }
        )
        cast_btn.style.minimal_width = 112
        cast_btn.style.maximal_width = 124
        cast_btn.style.minimal_height = 30
        cast_btn.style.maximal_height = 32
        cast_btn.style.font = 'default-bold'
        -- D6-T9 对比度：关闭态近白浅灰（原 {150,150,160} 深底上几乎不可读），开启态绿——判据为截图级可读
        cast_btn.style.font_color = cast_on and {168, 227, 154} or {235, 232, 225}
        -- v3.2「施法面板」按钮（D6-T10 移入标题行）：toggle spell_gui_settings 弹窗
        -- （settings.lua 既有函数零改动复用；只开关弹窗不写任何 rpg_t 状态——弹窗内自带开关，单一真值源不变）
        local spell_panel_btn =
            spell_title_row.add(
            {
                type = 'button',
                name = panel_spell_gui_button_name,
                caption = {'rpg_gui.spell_panel_btn'},
                tooltip = {'rpg_gui.spell_panel_btn_tooltip'}
            }
        )
        spell_panel_btn.style.minimal_width = 84
        spell_panel_btn.style.maximal_width = 96
        spell_panel_btn.style.minimal_height = 30
        spell_panel_btn.style.maximal_height = 32
        spell_panel_btn.style.font = 'default-bold'

        local spell_row = scroll_pane.add({type = 'table', column_count = 3})
        spell_row.style.cell_padding = 2

        for n = 1, 3 do
            local idx = Public.panel_spell_target_index(rpg_t, n)
            local spell = Public.resolve_spell_slot(spells, idx)
            local slot_flow = spell_row.add({type = 'flow', direction = 'vertical'})
            local spell_btn
            if spell then
                -- D6-T9 纯图标槽（v3.1 既定形态落地）：40×40 方钮无 caption，法术名进 tooltip
                -- （原 caption=spell.name 横排宽钮废弃——名称由本 tooltip 与槽下下拉框承担）
                spell_btn =
                    slot_flow.add(
                    {
                        type = 'sprite-button',
                        name = panel_spell_button_names[n],
                        sprite = spell.sprite,
                        tooltip = {'rpg_gui.spell_zone_tooltip', spell.name, spell.mana_cost}
                    }
                )
            else
                -- 空槽/被禁用槽：灰「＋」占位（原型空槽符号），配置入口 = 本槽下方下拉框
                spell_btn =
                    slot_flow.add(
                    {
                        type = 'sprite-button',
                        name = panel_spell_button_names[n],
                        caption = '＋',
                        tooltip = {'rpg_gui.spell_zone_unset_tooltip'}
                    }
                )
                spell_btn.style.font = 'default-bold'
                spell_btn.style.font_color = {120, 120, 135}
            end
            spell_btn.style.minimal_width = 40
            spell_btn.style.maximal_width = 40
            spell_btn.style.minimal_height = 40
            spell_btn.style.maximal_height = 40

            -- 当前施法 ▼ 角标（caption 删除后原字色高亮失效；恒定占位行保三列对齐不跳动，
            -- 识别机制不变 = dropdown_select_index 与槽 idx 比对）
            local badge = slot_flow.add({type = 'label', caption = (spell and idx == active_idx) and '▼' or ''})
            badge.style.font = 'default-bold'
            badge.style.font_color = {120, 200, 120}
            badge.style.minimal_width = 40
            badge.style.maximal_width = 40
            badge.style.minimal_height = 12
            badge.style.horizontal_align = 'center'

            -- v3 槽位下拉框：改配本槽装备（items 与设置面板下拉框同源同基准；
            -- selected_index nil 时原生回落第 1 项，不硬写回 rpg_t）
            local slot_dropdown =
                slot_flow.add(
                {
                    type = 'drop-down',
                    name = panel_spell_dropdown_names[n],
                    items = spell_names,
                    selected_index = idx,
                    tooltip = {'rpg_gui.spell_zone_slot_tooltip'}
                }
            )
            slot_dropdown.style.minimal_width = 120
            slot_dropdown.style.maximal_width = 120
        end

        -- 当前法术状态行（施法未开启时尾追加提示；开关/面板入口均在区标题行，单一真值源）
        local active_spell = Public.resolve_spell_slot(spells, active_idx)
        local status_caption
        if active_spell then
            status_caption = {'rpg_gui.spell_zone_active', active_spell.name, active_spell.mana_cost}
        else
            status_caption = {'rpg_gui.spell_zone_unset'}
        end
        if not rpg_t.auto_cast_enabled then
            status_caption = {'', status_caption, ' ', {'rpg_gui.spell_zone_cast_off'}}
        end
        local spell_status = scroll_pane.add({type = 'label', caption = status_caption})
        spell_status.style.font = 'default-small'
        spell_status.style.font_color = {150, 150, 160}
        spell_status.style.minimal_height = 20
    end

    --!C 区：能力真相（回退后 2 列行 = 标签 | 真实生效值；数据源 = 纯属性 + 天赋自身经 player_modifiers/
    -- update_player_stats 的贡献；成长角标与 T3-C 行级溯源随 growth 数据源一并移除）
    add_separator(scroll_pane, 410)
    local ability_table = scroll_pane.add({type = 'table', column_count = 2})
    local left_column = ability_table.add({type = 'flow', direction = 'vertical'})
    local right_column = ability_table.add({type = 'flow', direction = 'vertical'})

    -- 组一：战斗
    add_group_title(left_column, 'stat_group_combat')
    local combat_table = add_stat_table(left_column)

    -- C1 近战伤害
    add_stat_row(
        combat_table,
        ({'rpg_gui.melee_name'}),
        ({'rpg_gui.melee_tooltip'}),
        round((1 + Public.get_melee_modifier(player)) * 100) .. '%'
    )

    -- C2 最终伤害（随机系数区间式：公式两端取 rng=0.10/0.35，与 get_final_damage_modifier 一致；
    -- v3.2 一击必杀并入 tooltip——它是伤害的推论不是独立数值）
    local final_lo, final_hi = final_damage_range(rpg_t.strength, 0)
    local one_punch_part
    if rpg_extra.enable_one_punch then
        one_punch_part = {'rpg_gui.final_one_punch_line', Public.get_one_punch_chance(player)}
    else
        one_punch_part = ({'rpg_gui.one_punch_disabled'})
    end
    add_stat_row(
        combat_table,
        ({'rpg_gui.final_damage_name'}),
        {'', ({'rpg_gui.final_damage_tooltip', final_lo, final_hi}), '\n', one_punch_part},
        ({'rpg_gui.final_damage_value', final_lo, final_hi})
    )

    -- C3 一击必杀独立行已撤销（v3.2：get_one_punch_chance 收进 C2 tooltip；locale 键 one_punch_name 保留停渲染）

    -- C4 命中回血
    add_stat_row(
        combat_table,
        ({'rpg_gui.life_on_hit_name'}),
        ({'rpg_gui.life_on_hit_tooltip'}),
        strformat('+%.1f', Public.get_life_on_hit(player))
    )

    -- C5 随身机器人（LuaPlayer 专属键只读 player；'rpg' 分类口径 = (s-10)/35）
    add_stat_row(
        combat_table,
        ({'rpg_gui.damge_robot'}),
        ({'rpg_gui.robot_tooltip'}),
        '+ ' .. round(player.character_maximum_following_robot_count_bonus or 0, 2)
    )

    -- 组二：生产
    add_group_title(left_column, 'stat_group_production')
    local production_table = add_stat_table(left_column)

    -- C6 采矿速度（force + player + 1 照抄原公式防双计）
    add_stat_row(
        production_table,
        ({'rpg_gui.mining_name'}),
        ({'rpg_gui.mining_tooltip'}),
        round((player.force.manual_mining_speed_modifier + player.character_mining_speed_modifier + 1) * 100) .. '%'
    )

    -- C7 制作速度（rpg_t.crafting_speed 已并入 modifier，不二次叠加）
    add_stat_row(
        production_table,
        ({'rpg_gui.crafting_speed'}),
        ({'rpg_gui.crafting_tooltip'}),
        round((player.force.manual_crafting_speed_modifier + player.character_crafting_speed_modifier + 1) * 100) .. '%'
    )

    -- C8 修复速度
    add_stat_row(
        production_table,
        ({'rpg_gui.repair_name'}),
        ({'rpg_gui.repair_tooltip'}),
        round(Public.get_magicka(player) * 100) .. '%'
    )

    -- 组三：行动（v3.2 组名精简，原「行动与身体」）
    add_group_title(right_column, 'stat_group_body')
    local body_table = add_stat_table(right_column)

    -- C9 移动速度
    add_stat_row(
        body_table,
        ({'rpg_gui.running_speed'}),
        ({'rpg_gui.running_speed_tooltip'}),
        round((player.force.character_running_speed_modifier + player.character_running_speed_modifier + 1) * 100) .. '%'
    )

    -- C10 背包槽位
    add_stat_row(
        body_table,
        ({'rpg_gui.slot_name'}),
        ({'rpg_gui.slot_tooltip'}),
        '+ ' .. round(player.force.character_inventory_slots_bonus + player.character_inventory_slots_bonus)
    )

    -- C11 交互距离（v3.2 合并行：到达+建造——主值恒取到达值，tooltip 拆分两项不说谎）
    local reach_val = player.force.character_reach_distance_bonus + player.character_reach_distance_bonus
    local build_val = player.force.character_build_distance_bonus + player.character_build_distance_bonus
    add_stat_row(
        body_table,
        ({'rpg_gui.interact_distance_name'}),
        ({'rpg_gui.interact_distance_tooltip', '+ ' .. reach_val, '+ ' .. build_val}),
        '+ ' .. reach_val
    )

    -- C12 生命上限（上限侧真相在 B 区 max_health）
    add_stat_row(
        body_table,
        ({'rpg_gui.health_bonus_name'}),
        ({'rpg_gui.health_bonus_tooltip'}),
        '+ ' .. round(player.force.character_health_bonus + player.character_health_bonus)
    )

    -- C13 生命回复
    add_stat_row(
        body_table,
        ({'rpg_gui.health_regen_name'}),
        ({'rpg_gui.health_regen_tooltip'}),
        strformat('%.1f', Public.get_heal_modifier(player))
    )

    -- 组四：法力（enable_mana 条件组）
    if rpg_extra.enable_mana then
        add_group_title(right_column, 'stat_group_mana')
        local mana_group_table = add_stat_table(right_column)
        local mana_regen_value = floor(Public.get_mana_modifier(player) * 10) / 10
        add_stat_row(
            mana_group_table,
            ({'rpg_gui.mana_bonus'}),
            ({'rpg_gui.mana_regen_bonus', mana_regen_value}),
            '+ ' .. mana_regen_value
        )
    end

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
-- T3F-1 修复：本键曾直挂帧级内部函数 remove_main_frame(main_frame, screen)（首参是 LuaGuiElement），
-- 而对外调用方（trees_gui.open、真相面板 Z3 溯源）按玩家级语义传 player 单参——真实客户端在
-- Gui.set_data 内读 element.player_index 抛 "LuaPlayer doesn't contain key player_index"
-- （mock 普通表读缺失键只静默返回 nil，故仅真实客户端崩）。对外契约收敛为玩家级 API：
-- 等价 Public.remove_frame（真相面板未开时 no-op）；帧级清理仍走本文件局部双参函数，内部调用方不受影响。
Public.remove_main_frame = function(player)
    Public.remove_frame(player)
end

-- 刷新入口（D4-T6 / ④-5 刷新链末环，供 D2 选卡成功后调用）
-- 面板开着 → toggle(player, true) 全量重建（remove+draw），数值当场更新；面板未开 → no-op 不报错。
function Public.refresh_panel(player)
    if not player or not player.valid then
        return
    end
    local screen = player.gui.screen
    if screen and screen[main_frame_name] then
        toggle(player, true)
    end
end

Gui.on_click(
    draw_main_frame_name,
    function(event)
        local player = event.player
        if not player or not player.valid or not player.character then
            return
        end

        toggle(player)
    end
)

Gui.on_click(
    save_button_name,
    function(event)
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
        local auto_cast_gui_input = data.auto_cast_gui_input
        local auto_allocate_gui_input = data.auto_allocate_gui_input

        local rpg_t = Public.get_value_from_player(player.index)

        if frame and frame.valid then
            -- 处理自动施法设置
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
            if auto_allocate_gui_input and auto_allocate_gui_input.valid and auto_allocate_gui_input.selected_index then
                rpg_t.allocate_index = auto_allocate_gui_input.selected_index
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
    end
)

Gui.on_click(
    discard_button_name,
    function(event)
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
    end
)

Gui.on_click(
    settings_button_name,
    function(event)
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
    end
)

Gui.on_click(
    transfer_button_name,
    function(event)
        local player = event.player
        if not player or not player.valid or not player.character then
            return
        end

        -- 检查转移界面是否已经存在
        local transfer_frame = player.gui.screen[Public.transfer_frame_name]
        if transfer_frame and transfer_frame.valid then
            -- 如果存在则关闭
            Gui.remove_data_recursively(transfer_frame)
            transfer_frame.destroy()
        else
            -- 如果不存在则创建
            Public.create_transfer_gui(player)
        end
    end
)

Gui.on_click(
    enable_spawning_frame_name,
    function(event)
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
    end
)

Gui.on_click(
    spell_gui_button_name,
    function(event)
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
    end
)

Gui.on_click(
    spell1_button_name,
    function(event)
        local player = event.player
        local screen = player.gui.screen
        local frame = screen[spell_gui_frame_name]
        if not player or not player.valid or not player.character then
            return
        end

      

        if frame and frame.valid then
            Public.update_spell_gui(player, 1)
        end
    end
)

Gui.on_click(
    spell2_button_name,
    function(event)
        local player = event.player
        local screen = player.gui.screen
        local frame = screen[spell_gui_frame_name]
        if not player or not player.valid or not player.character then
            return
        end

   

        if frame and frame.valid then
            Public.update_spell_gui(player, 2)
        end
    end
)

Gui.on_click(
    spell3_button_name,
    function(event)
        local player = event.player
        local screen = player.gui.screen
        local frame = screen[spell_gui_frame_name]
        if not player or not player.valid or not player.character then
            return
        end

    

        if frame and frame.valid then
            Public.update_spell_gui(player, 3)
        end
    end
)

-- D6 v2：主面板法术槽点击 = 切换当前法术（写法与 settings.lua:54-58 同款；
-- 体内只写索引 + 全量重建，不调用 update_spell_gui / 不碰施法链）
local function panel_spell_click(event, n)
    local player = event.player
    if not player or not player.valid or not player.character then
        return
    end
    local rpg_t = Public.get_value_from_player(player.index)
    if not rpg_t then
        return
    end
    rpg_t.dropdown_select_index = Public.panel_spell_target_index(rpg_t, n)
    Public.refresh_panel(player)
end

for n = 1, 3 do
    Gui.on_click(
        panel_spell_button_names[n],
        function(event)
            panel_spell_click(event, n)
        end
    )
end

-- D6 v3：槽位下拉框变更 = 改配本槽装备（Gui.on_selection_state_changed，设置面板下拉框同款写法；
-- 体内只写 dropdown_select_indexN + 全量重建，不碰施法链/不调 update_spell_gui）
for n = 1, 3 do
    Gui.on_selection_state_changed(
        panel_spell_dropdown_names[n],
        function(event)
            local player = event.player
            if not player or not player.valid or not player.character then
                return
            end
            local rpg_t = Public.get_value_from_player(player.index)
            if not rpg_t then
                return
            end
            Public.panel_spell_dropdown_write(rpg_t, n, event.element.selected_index)
            Public.refresh_panel(player)
        end
    )
end

-- D6 v3：主面板鱼形按钮 = 自动施法开关（与 spell_gui_button_name 处理器 toggle 同语义：
-- 开启时连带补齐 enable_entity_spawn 总开关；不打开/关闭法术弹窗——弹窗配置职责已被主面板槽位下拉框覆盖）
Gui.on_click(
    panel_cast_toggle_name,
    function(event)
        local player = event.player
        if not player or not player.valid or not player.character then
            return
        end
        local rpg_t = Public.get_value_from_player(player.index)
        if not rpg_t then
            return
        end
        local new_state = Public.panel_cast_toggle_state(rpg_t.auto_cast_enabled)
        rpg_t.auto_cast_enabled = new_state
        if new_state then
            -- auto_skill 引擎的前置总开关必须同时补齐，否则按钮是假的（BUG-P1：只开 auto_cast_enabled 会在 main.lua auto_skill 的 enable_entity_spawn 检查处静默返回）
            rpg_t.enable_entity_spawn = true
            player.print({'rpg_settings.auto_cast_enabled_label'}, Color.success)
            player.play_sound({path = 'utility/armor_insert', volume_modifier = 0.75})
        else
            player.print({'rpg_settings.auto_cast_disabled_label'}, Color.warning)
            player.play_sound({path = 'utility/cannot_build', volume_modifier = 0.75})
        end
        Public.refresh_panel(player)
    end
)

-- D6 v3.2：主面板「施法面板」按钮 = toggle spell_gui_settings 弹窗（settings.lua 既有函数零改动复用：
-- 弹窗不存在则创建、存在则销毁；本 handler 只开关弹窗，不写 rpg_t 状态、不打印消息不播音效）
Gui.on_click(
    panel_spell_gui_button_name,
    function(event)
        local player = event.player
        if not player or not player.valid or not player.character then
            return
        end
        Public.spell_gui_settings(player)
    end
)

-- T3-C Z1/Z3 蓝图入口与行级溯源 handler 已随真树/蓝图面板回退移除（trees_gui.lua / tianfu_trees_data.lua 已删）

Gui.on_click(
    spell_info_button_name,
    function(event)
        local player = event.player
        if not player or not player.valid or not player.character then
            return
        end
        Public.spell_info_gui(player)
    end
)

Gui.on_click(
    spell_info_close_button_name,
    function(event)
        local player = event.player
        if not player or not player.valid then
            return
        end
        local frame = player.gui.screen[spell_info_frame_name]
        if frame and frame.valid then
            frame.destroy()
        end
    end
)

-- ── 属性分配（回退移植：基线 main.lua on_gui_click 的 ✚ 分配语义，改走 Gui.on_click uid 路由）──
-- 语义：左键 +1；右键 +points_per_level；Shift+左键 全部；Shift+右键 一半（>2 才生效，基线同款）。
-- 每点消耗 points_left、属性 +1，非重置态累计 total；随后 update_player_stats + 面板重建刷新。

-- 纯函数出口（qa/d6_panel_selfcheck.lua 消费）：本次点击实际可加点数 = min(剩余点, 请求数)，剩余点非正 → 0
function Public.alloc_points_to_apply(points_left, requested)
    return math.max(0, math.min(points_left or 0, requested or 0))
end

local function apply_allocation(player, attribute, requested)
    local rpg_t = Public.get_value_from_player(player.index)
    if not rpg_t or not rpg_t[attribute] then
        return
    end
    local applied = Public.alloc_points_to_apply(rpg_t.points_left, requested)
    for _ = 1, applied do
        rpg_t.points_left = rpg_t.points_left - 1
        rpg_t[attribute] = rpg_t[attribute] + 1
        if not rpg_t.reset then
            rpg_t.total = rpg_t.total + 1
        end
    end
    Public.update_player_stats(player)
    Public.toggle(player, true)
end

local function on_allocate_click(event, attribute)
    local player = event.player
    if not player or not player.valid or not player.character then
        return
    end
    local rpg_t = Public.get_value_from_player(player.index)
    if not rpg_t then
        return
    end
    local shift = event.shift
    local button = event.button
    if shift then
        if button == defines.mouse_button_type.left then
            apply_allocation(player, attribute, rpg_t.points_left or 0)
        elseif button == defines.mouse_button_type.right then
            local half = floor((rpg_t.points_left or 0) / 2)
            if half > 2 then
                apply_allocation(player, attribute, half)
            else
                Public.toggle(player, true)
            end
        end
    elseif button == defines.mouse_button_type.right then
        apply_allocation(player, attribute, Public.points_per_level)
    else
        apply_allocation(player, attribute, 1)
    end
end

for attribute, uid in pairs(alloc_button_names) do
    Gui.on_click(
        uid,
        function(event)
            on_allocate_click(event, attribute)
        end
    )
end

--ComfyGui.screen_to_bypass(spell_gui_frame_name)
--ComfyGui.screen_to_bypass(spell_info_frame_name)
