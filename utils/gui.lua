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

function Gui.uid_name()
    return tostring(Token.uid())
end

function Gui.uid()
    return Token.uid()
end

local CONST_TOGGLE_BUTTON = Gui.uid_name()

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

--- 获取 toggle 按钮的元素名（供外部模块引用）
function Gui.get_toggle_button_name()
    return CONST_TOGGLE_BUTTON
end

--- 创建顶栏显隐切换按钮
-- 展开态 sprite: utility/preset（齿轮图标，暗示"面板/设置"）
-- 收起态 sprite: utility/expand_dots（三点图标，暗示"展开更多"）
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

end

--- toggle 按钮 click handler
-- 收起时：遍历 top_elements 注册表，隐藏注册元素；触发 on_pre_hidden 回调
-- 展开时：遍历 top_elements 注册表，显示注册元素；触发 on_visible 回调
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

        if is_expanded then
            element.sprite = 'utility/expand_dots'
            element.tooltip = {'amap.gui_toggle_top_buttons_expanded'}

            for element_name, _ in pairs(top_elements) do
                local child = flow[element_name]
                if child and child.valid then
                    custom_raise(on_pre_hidden_handlers, child, player)
                    child.visible = false
                end
            end
        else
            element.sprite = 'utility/preset'
            element.tooltip = {'amap.gui_toggle_top_buttons'}

            for element_name, _ in pairs(top_elements) do
                local child = flow[element_name]
                if child and child.valid then
                    child.visible = true
                    custom_raise(on_visible_handlers, child, player)
                end
            end
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

if _DEBUG then
    local concat = table.concat

    local names = {}
    Gui.names = names

    function Gui.uid_name()
        local info = debug.getinfo(2, 'Sl')
        local filepath = info.source:match('^.+/currently%-playing/(.+)$'):sub(1, -5)
        local line = info.currentline

        local token = tostring(Token.uid())

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
-- 对 frame 类型不做自动样式（与 RedMew 一致）
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
    end
    return flow.add(child)
end

return Gui
