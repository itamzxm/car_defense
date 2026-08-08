local Token = require 'utils.token'
local Event = require 'utils.event'
local Global = require 'utils.global'
local SpamProtection = require 'utils.spam_protection'
local mod_gui = require('__core__/lualib/mod-gui')

local tostring = tostring
local next = next

local Gui = {}

local data = {}
local element_map = {}
local settings = {}
-- 折叠状态（内存态）：fold_state[player_index] = {collapsed = bool, saved_visible = {element_name = bool}}
-- 注意：不放进 Global.register（避免改变 gui token 的字段签名导致旧存档错配），
-- 玩家重连后折叠状态重置为展开态，可接受
local fold_state = {}

Gui.token =
    Global.register(
    {data = data, element_map = element_map, settings = settings},
    function(tbl)
        data = tbl.data
        element_map = tbl.element_map
        settings = tbl.settings
    end
)

-- handler_factory 的 handlers 表——模块级 local，不存入 global（函数无法序列化）。
-- 使用 Gui.on_click 注册 handler 的代码必须确保：
-- 1. handler 在模块加载时注册（而非运行时），或
-- 2. handler 仅修改玩家本地 GUI 状态，不修改 global/shared 状态。
-- 违反此规则会在新玩家加入后触发 desync。
local gui_click_handlers = {}
local gui_custom_close_handlers = {}
local gui_checked_state_handlers = {}
local gui_elem_changed_handlers = {}
local gui_selection_state_handlers = {}
local gui_text_changed_handlers = {}
local gui_value_changed_handlers = {}

local on_visible_handlers = {}
local on_pre_hidden_handlers = {}

local top_elements = {}
-- 折叠时始终可见的顶栏元素（register_always_visible_top_element 注册）
local always_visible_top_elements = {}

-- uid 名登记表：模块加载期 Gui.uid_name() 调用登记，供玩家加入时清理
-- 存档 GUI 中残留的旧 uid 名元素（见 cleanup_legacy_top_gui 根因注释）
local known_uid_names = {}

function Gui.uid_name()
    local name = tostring(Token.uid())
    known_uid_names[name] = true
    return name
end

function Gui.uid()
    return Token.uid()
end

local CONST_TOGGLE_BUTTON = Gui.uid_name()

-- 顶栏按钮默认样式（参考经典实现）：
-- 内置 frame_button（深色 frame 底 40x40）+ 覆盖：浅灰字 heading-2、padding -2
-- 各模块创建按钮后的后置样式覆盖（font_color/font/padding）优先于本默认值
local STYLE_TOP_BUTTON = {
    font_color = {165, 165, 165},
    font = 'heading-2',
    minimal_height = 40,
    maximal_height = 40,
    minimal_width = 40,
    padding = -2,
}

-- Associates data with the LuaGuiElement. If data is nil then removes the data
function Gui.set_data(element, value)
    local player_index = element.player_index
    local values = data[player_index]

    if value == nil then
        if not values then
            return
        end

        values[element.index] = nil

        if next(values) == nil then
            data[player_index] = nil
        end
    else
        if not values then
            values = {}
            data[player_index] = values
        end

        values[element.index] = value
    end
end
local set_data = Gui.set_data

-- Gets the Associated data with this LuaGuiElement if any.
function Gui.get_data(element)
    if not element then
        return
    end

    local player_index = element.player_index

    local values = data[player_index]
    if not values then
        return nil
    end

    return values[element.index]
end

local remove_data_recursively
-- Removes data associated with LuaGuiElement and its children recursively.
function Gui.remove_data_recursively(element)
    set_data(element, nil)

    local children = element.children

    if not children then
        return
    end

    for _, child in next, children do
        if child.valid then
            remove_data_recursively(child)
        end
    end
end
remove_data_recursively = Gui.remove_data_recursively

local remove_children_data
function Gui.remove_children_data(element)
    local children = element.children

    if not children then
        return
    end

    for _, child in next, children do
        if child.valid then
            set_data(child, nil)
            remove_children_data(child)
        end
    end
end
remove_children_data = Gui.remove_children_data

function Gui.destroy(element)
    remove_data_recursively(element)
    element.destroy()
end

function Gui.clear(element)
    remove_children_data(element)
    element.clear()
end

local function clear_invalid_data()
    if settings.disable_clear_invalid_data then
        return
    end

    for _, player in pairs(game.players) do
        local player_index = player.index
        local values = data[player_index]
        if values then
            for k, element in next, values do
                if type(element) == 'table' then
                    for key, obj in next, element do
                        if type(obj) == 'table' and obj.valid ~= nil then
                            if not obj.valid then
                                element[key] = nil
                            end
                        end
                    end
                    if type(element) == 'userdata' and not element.valid then
                        values[k] = nil
                    end
                end
            end
        end
    end
end
Event.on_nth_tick(300, clear_invalid_data)

local function handler_factory(event_id, handlers)
    -- handlers 表必须在 global 中持久化（见顶部 Global.register），
    -- 否则新连接客户端会丢失所有已注册的 GUI 回调，导致 desync。

    local function on_event(event)
        local element = event.element
        if not element or not element.valid then
            return
        end

        local handler = handlers[element.name]
        if type(handler) ~= 'function' then
            -- 新连接客户端：handler 函数无法序列化，表结构保留但值为 nil。
            -- 此时静默跳过——该 GUI 的注册流程会在下次相关事件触发时重新执行。
            return
        end

        local player = game.get_player(event.player_index)
        if not (player and player.valid) then
            return
        end

        if not event.text then
            local is_spamming = SpamProtection.is_spamming(player, nil, 'UtilsGUI Handler')
            if is_spamming then
                return
            end
        end

        event.player = player

        handler(event)
    end

    -- 在 control stage（模块加载时）注册，避免运行时惰性注册的 desync 风险
    Event.add(event_id, on_event)

    return function(element_name, handler)
        handlers[element_name] = handler
    end
end

local function custom_handler_factory(handlers)
    return function(element_name, handler)
        handlers[element_name] = handler
    end
end

--luacheck: ignore custom_raise
local function custom_raise(handlers, element, player)
    local handler = handlers[element.name]
    if not handler then
        return
    end

    handler({element = element, player = player})
end

-- Disabled the handler so it does not clean then data table of invalid data.
function Gui.set_disable_clear_invalid_data(value)
    settings.disable_clear_invalid_data = value or false
end

-- Gets state if the cleaner handler is active or false
function Gui.get_disable_clear_invalid_data()
    return settings.disable_clear_invalid_data
end

-- Register a handler for the on_gui_checked_state_changed event for LuaGuiElements with element_name.
-- Can only have one handler per element name.
-- Guarantees that the element and the player are valid when calling the handler.
-- Adds a player field to the event table.
Gui.on_checked_state_changed = handler_factory(defines.events.on_gui_checked_state_changed, gui_checked_state_handlers)
Gui.on_click = handler_factory(defines.events.on_gui_click, gui_click_handlers)
Gui.on_custom_close = handler_factory(defines.events.on_gui_closed, gui_custom_close_handlers)
Gui.on_elem_changed = handler_factory(defines.events.on_gui_elem_changed, gui_elem_changed_handlers)
Gui.on_selection_state_changed = handler_factory(defines.events.on_gui_selection_state_changed, gui_selection_state_handlers)
Gui.on_text_changed = handler_factory(defines.events.on_gui_text_changed, gui_text_changed_handlers)
Gui.on_value_changed = handler_factory(defines.events.on_gui_value_changed, gui_value_changed_handlers)

-- Register a handler for when the player shows the top LuaGuiElements with element_name.
-- Assuming the element_name has been added with Gui.allow_player_to_toggle_top_element_visibility.
-- Can only have one handler per element name.
-- Guarantees that the element and the player are valid when calling the handler.
-- Adds a player field to the event table.
Gui.on_player_show_top = custom_handler_factory(on_visible_handlers)

-- Register a handler for when the player hides the top LuaGuiElements with element_name.
-- Assuming the element_name has been added with Gui.allow_player_to_toggle_top_element_visibility.
-- Can only have one handler per element name.
-- Guarantees that the element and the player are valid when calling the handler.
-- Adds a player field to the event table.
Gui.on_pre_player_hide_top = custom_handler_factory(on_pre_hidden_handlers)

--- 注册顶栏元素到显隐切换列表（control stage only）
-- 只有注册的元素才会被 toggle 按钮隐藏/显示
-- 波次信息条等需始终可见的元素不应注册
function Gui.allow_player_to_toggle_top_element_visibility(element_name)
    if _LIFECYCLE == 8 then
        error('allow_player_to_toggle_top_element_visibility can only be called during control stage', 2)
    end
    top_elements[element_name] = true
end

--- 注册"折叠时始终可见"的顶栏元素（control stage only）
-- 注册后的元素即使注册了显隐切换，点击折叠按钮时也不会被隐藏
-- 用于游戏中高频使用的按钮（RPG/宠物/天赋/波防进度条），折叠后仍需随时可点
function Gui.register_always_visible_top_element(element_name)
    if _LIFECYCLE == 8 then
        error('register_always_visible_top_element can only be called during control stage', 2)
    end
    always_visible_top_elements[element_name] = true
end

--- 获取 toggle 按钮的元素名（供外部模块引用）
function Gui.get_toggle_button_name()
    return CONST_TOGGLE_BUTTON
end

--- 创建顶栏显隐切换按钮
-- 展开态 sprite: utility/preset（齿轮图标，暗示"面板/设置"）
-- 收起态 sprite: utility/expand_dots（三点图标，暗示"展开更多"）
-- 窄条设计：18px 宽，与其他顶栏按钮区分开（参考 archive/classic-changes 的 top_bar.lua）
-- 样式与顶栏默认按钮统一：frame_button 底 + 宽 18、高 40、padding 全 0、default-small-bold
local function create_toggle_button(player)
    local flow = Gui.get_button_flow(player)
    if flow[CONST_TOGGLE_BUTTON] and flow[CONST_TOGGLE_BUTTON].valid then
        return
    end

    local old = player.gui.top[CONST_TOGGLE_BUTTON]
    if old and old.valid then
        Gui.remove_data_recursively(old)
        old.destroy()
    end

    local button =
        flow.add {
        type = 'sprite-button',
        name = CONST_TOGGLE_BUTTON,
        sprite = 'utility/preset',
        tooltip = {'amap.gui_toggle_top_buttons'},
        style = 'frame_button'
    }
    button.style.minimal_width = 18
    button.style.maximal_width = 18
    button.style.minimal_height = 40
    button.style.maximal_height = 40
    button.style.left_padding = 0
    button.style.top_padding = 0
    button.style.right_padding = 0
    button.style.bottom_padding = 0
    button.style.font = 'default-small-bold'

    -- 恢复持久化的折叠状态（玩家重连后保持折叠/展开）
    local state = fold_state[player.index]
    if state and state.collapsed then
        button.sprite = 'utility/expand_dots'
        button.tooltip = {'amap.gui_toggle_top_buttons_expanded'}
        for element_name, _ in pairs(top_elements) do
            if not always_visible_top_elements[element_name] then
                local child = flow[element_name]
                if child and child.valid then
                    child.visible = false
                end
            end
        end
    end

end

--- toggle 按钮 click handler
-- 收起时：记录各元素折叠前的可见状态到 fold_state，隐藏注册元素（豁免除外）；触发 on_pre_hidden 回调
-- 展开时：恢复 fold_state 中记录的可见状态（而不是一律显示）；触发 on_visible 回调
-- 状态同步：地图信息条等元素折叠前隐藏的，展开后保持隐藏，需点各自按钮展开
Gui.on_click(
    CONST_TOGGLE_BUTTON,
    function(event)
        local player = event.player
        if not player or not player.valid then
            return
        end

        local element = event.element
        if not element or not element.valid then
            return
        end

        local flow = Gui.get_button_flow(player)
        local is_expanded = element.sprite == 'utility/preset'

        if not fold_state[player.index] then
            fold_state[player.index] = {}
        end
        local state = fold_state[player.index]

        if is_expanded then
            element.sprite = 'utility/expand_dots'
            element.tooltip = {'amap.gui_toggle_top_buttons_expanded'}

            state.collapsed = true
            state.saved_visible = state.saved_visible or {}

            for element_name, _ in pairs(top_elements) do
                -- 高频按钮（RPG/宠物/天赋/波防条）折叠时始终可见
                if always_visible_top_elements[element_name] then
                    goto continue_hide
                end
                local child = flow[element_name]
                if child and child.valid then
                    -- 记录折叠前的可见状态，展开时恢复
                    state.saved_visible[element_name] = child.visible
                    custom_raise(on_pre_hidden_handlers, child, player)
                    child.visible = false
                end
                ::continue_hide::
            end
        else
            element.sprite = 'utility/preset'
            element.tooltip = {'amap.gui_toggle_top_buttons'}

            state.collapsed = false
            local saved = state.saved_visible or {}

            for element_name, _ in pairs(top_elements) do
                if always_visible_top_elements[element_name] then
                    goto continue_show
                end
                local child = flow[element_name]
                if child and child.valid then
                    -- 恢复折叠前状态；无记录（首次展开）默认显示
                    if saved[element_name] ~= nil then
                        child.visible = saved[element_name]
                    else
                        child.visible = true
                    end
                    if child.visible then
                        custom_raise(on_visible_handlers, child, player)
                    end
                end
                ::continue_show::
            end
            state.saved_visible = nil
        end
    end
)

-- 旧存档 GUI 清理（玩家加入时执行）
-- 根因：Factorio 存档会保存玩家的 GUI 状态。testsave3 这类旧存档是老代码时代创建的，
-- 当时顶栏按钮直接挂在 gui.top 原生位置（gui.top.add），右下角也有旧版 bottom_frame 框。
-- 新代码把按钮迁移到 get_button_flow（mod_gui 大框）后，加载旧存档会恢复旧 GUI 结构，
-- 与新代码创建的大框按钮并存，造成"老按钮 + 大框"重复。
-- 清理策略：
--   1. gui.top：删除所有非 mod-gui 容器（mod_gui_top_frame / mod_gui_inner_frame / mod_gui_button_flow）的子元素
--   2. gui.screen：删除含"清理尸体"按钮（sprite = entity/behemoth-biter）的旧 bottom_frame 框
-- 清理后由新代码按 get_button_flow 重新创建，不会残留旧结构。
-- 注意：不能在 on_load 执行（该阶段 game 全局不可用），必须在玩家加入时执行。
-- 白名单保护：副本（instance）框架的退出按钮/计时器/金币等直接挂 gui.top 的元素
-- （dungeon_ 前缀）必须保留，否则副本内玩家掉线重连会被误删、困在副本出不来。
-- 维护：新增的非 get_button_flow 顶栏元素（直接挂 gui.top 的）需在此注册白名单。
-- 注意：波防条 wave_defense 不在白名单——旧存档残留实例必须被清理删除，
-- 由新代码在 on_tick 中重建到 mod_gui_top_frame 右侧（否则旧实例占位导致顺序错乱）。
local function is_protected_top_element(name)
    if not name then
        return true
    end
    -- 副本框架通用 GUI（退出按钮/计时器/金币）+ 各副本玩法 GUI（dungeon_ 前缀）
    if name:sub(1, 8) == 'dungeon_' then
        return true
    end
    -- coin_mine 副本的回收价格按钮（不带 dungeon_ 前缀）
    if name == 'recycling_prices_button' then
        return true
    end
    return false
end

local function cleanup_legacy_top_gui(player)
    local keep = {
        ['mod_gui_top_frame'] = true,
        ['mod_gui_inner_frame'] = true,
        ['mod_gui_button_flow'] = true,
    }
    if not player or not player.valid then
        return
    end
    local top = player.gui.top
    if top then
        for _, child in pairs(top.children) do
            if not keep[child.name] and not is_protected_top_element(child.name) then
                Gui.remove_data_recursively(child)
                child.destroy()
            end
        end
    end

    -- 清理 mod_gui 大框（mod_gui_top_frame）内全部子元素：
    -- 根因：按钮名 = Token.uid() 数字，uid 序列依赖模块加载顺序（require 链）。
    -- 代码版本切换（模块增减 / require 顺序变化）后 uid 序列改变，存档恢复的旧 uid 按钮
    -- 无法被各模块"同名幂等检查"识别（旧数字名常与当前代码其他元素的 uid 名撞车），
    -- 玩家重连时新按钮追加，造成重复按钮（实测：宠物按钮 161+162、地图信息按钮 192+193 双份并存）。
    -- 策略：清空 mod_gui_top_frame（含 mod_gui_inner_frame 按钮流），mod-gui lualib 会在下次
    -- get_button_flow 调用时惰性重建按钮流容器；各模块 on_player_joined_game / on_player_created
    -- handler 按注册顺序幂等重建全部按钮（顶栏按钮模块均在玩家加入时重建；MAIN_FRAME 地图信息条
    -- 由点击地图信息按钮时重建）。固定名按钮（comfy_panel_top_button / poll_button / tianfu /
    -- charging_station / auto_stash / minimap_button 等）不受 uid 错位影响，同样由各自模块重建。
    -- legacy 结构：老版 mod-gui 的按钮流可能挂在 gui.top.mod_gui_button_flow（get_button_flow 的
    -- legacy 分支），一并删除，让 get_button_flow 回到 mod_gui_top_frame.mod_gui_inner_frame 主路径。
    local top_frame = player.gui.top.mod_gui_top_frame
    if top_frame then
        for _, child in pairs(top_frame.children) do
            Gui.remove_data_recursively(child)
            child.destroy()
        end
    end
    local legacy_flow = player.gui.top['mod_gui_button_flow']
    if legacy_flow and legacy_flow.valid then
        Gui.remove_data_recursively(legacy_flow)
        legacy_flow.destroy()
    end
    local screen = player.gui.screen
    if screen then
        for _, child in pairs(screen.children) do
            if child.type == 'frame' then
                local has_corpse_button = false
                for _, sub in pairs(child.children) do
                    if sub.type == 'frame' then
                        for _, btn in pairs(sub.children) do
                            if btn.type == 'sprite-button' and btn.sprite == 'entity/behemoth-biter' then
                                has_corpse_button = true
                                break
                            end
                        end
                    end
                    if has_corpse_button then
                        break
                    end
                end
                if has_corpse_button then
                    Gui.remove_data_recursively(child)
                    child.destroy()
                end
            end
        end
    end
end

--- 玩家加入时创建 toggle 按钮
Event.add(
    defines.events.on_player_joined_game,
    function(event)
        local player = game.get_player(event.player_index)
        if player and player.valid then
            cleanup_legacy_top_gui(player)
            create_toggle_button(player)
        end
    end
)

--- 玩家创建时也创建 toggle 按钮（覆盖首次加入）
Event.add(
    defines.events.on_player_created,
    function(event)
        local player = game.get_player(event.player_index)
        if player and player.valid then
            cleanup_legacy_top_gui(player)
            create_toggle_button(player)
        end
    end
)

--- 玩家离开时清理折叠状态（防内存泄漏）
Event.add(
    defines.events.on_player_left_game,
    function(event)
        fold_state[event.player_index] = nil
    end
)

if _DEBUG then
    local concat = table.concat

    local names = {}
    Gui.names = names

    function Gui.uid_name()
        local info = debug.getinfo(2, 'Sl')
        local filepath = info.source:match('^.+/currently%-playing/(.+)$'):sub(1, -5)
        local line = info.currentline

        local token = tostring(Token.uid())
        known_uid_names[token] = true

        local name = concat {token, ' - ', filepath, ':line:', line}
        names[token] = name

        return token
    end

    function Gui.set_data(element, value)
        local player_index = element.player_index
        local values = data[player_index]

        if value == nil then
            if not values then
                return
            end

            local index = element.index
            values[index] = nil
            element_map[index] = nil

            if next(values) == nil then
                data[player_index] = nil
            end
        else
            if not values then
                values = {}
                data[player_index] = values
            end

            local index = element.index
            values[index] = value
            element_map[index] = element
        end
    end
    set_data = Gui.set_data

    function Gui.data()
        return data
    end

    function Gui.element_map()
        return element_map
    end
end

Gui.get_button_flow = mod_gui.get_button_flow
Gui.mod_button = mod_gui.get_button_flow

--- 统一的顶栏元素创建函数（幂等 + 热重载旧实例清理 + 默认样式兜底）
-- 热重载安全：自动清理 gui.top 上的旧实例（旧存档按钮在 gui.top 直接子元素位置）
-- 幂等：同名元素已存在于 get_button_flow 中则直接返回
-- 默认样式：未指定 style 的 button/sprite-button 自动应用 frame_button
--   （Factorio 内置样式，深色 frame 底 40x40 + 浅灰字 heading-2）
-- 对 frame 类型不做自动样式
function Gui.add_top_element(player, child)
    local old = player.gui.top[child.name]
    if old and old.valid then
        Gui.remove_data_recursively(old)
        old.destroy()
    end

    local flow = Gui.get_button_flow(player)
    local element = flow[child.name]
    if element and element.valid then
        return element
    end

    if (child.type == 'button' or child.type == 'sprite-button') and child.style == nil then
        child.style = 'frame_button'
        local e = flow.add(child)
        local s = e.style
        for k, v in pairs(STYLE_TOP_BUTTON) do
            s[k] = v
        end
        return e
    end
    return flow.add(child)
end

--- 创建带标题栏的面板（标题 + 拖拽区 + 关闭按钮）
-- 标题栏由原生构件组装（flow + label + empty-widget + sprite-button），
-- 所有 style/sprite 均为 Factorio 核心自带：
--   frame_action_button / frame_title / draggable_space / utility/close / utility/close_fat
-- @param player 玩家
-- @param align 对齐位置（'left' / 'screen'；screen 时启用拖动）
-- @param frame_name 面板名（模块 uid_name）
-- @param close_button_name 关闭按钮名（模块 uid_name，点击由模块自己处理）
-- @param title 标题文本
-- @return main_frame, close_button
function Gui.add_main_frame_with_toolbar(player, align, frame_name, close_button_name, title)
    local gui = player.gui[align]
    local main_frame = gui.add({type = 'frame', name = frame_name, direction = 'vertical'})

    local titlebar = main_frame.add({type = 'flow', name = 'titlebar', direction = 'horizontal'})
    titlebar.style = 'horizontal_flow'
    titlebar.style.horizontal_spacing = 8

    if align == 'screen' then
        titlebar.drag_target = main_frame
    end

    titlebar.add({type = 'label', name = 'main_label', style = 'frame_title', caption = title, ignored_by_interaction = true})

    local widget = titlebar.add({type = 'empty-widget', style = 'draggable_space', ignored_by_interaction = true})
    widget.style.left_margin = 4
    widget.style.right_margin = 4
    widget.style.height = 24
    widget.style.horizontally_stretchable = true

    local close_button
    if close_button_name then
        close_button =
            titlebar.add(
            {
                type = 'sprite-button',
                name = close_button_name,
                style = 'frame_action_button',
                mouse_button_filter = {'left'},
                sprite = 'utility/close',
                hovered_sprite = 'utility/close_fat',
                clicked_sprite = 'utility/close_fat',
                tooltip = {'amap.comfy_toolbar_close'}
            }
        )
    end

    return main_frame, close_button
end

return Gui
