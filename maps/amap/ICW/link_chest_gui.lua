----------------------------------------------------------------
-- 世界13 - 关联箱连接 GUI
-- 玩家放置 linked-chest 时自动连接到第一个车厢输入箱A
-- 再次点击关联箱时弹出选择窗口，让玩家修改连接目标
----------------------------------------------------------------
-- 设计原则：
--   1. 不使用 Gui.uid_name()——它底层 Token.uid() 是模块级 local 计数器，
--      不在 global 中持久化，新连接客户端从初始值开始，会导致 name 不一致 → desync。
--   2. 不使用 Gui.on_click / Gui.on_custom_close——它们的 handler 表是模块级
--      local，函数闭包无法序列化到 global，新连接客户端为空 → desync。
--   3. 使用 GuiDispatcher 按 element.name 字符串路由 GUI 事件，
--      handler 内通过 player_index 查 global 状态，不依赖闭包捕获局部变量。
--   4. 运行时状态存 global（ICW.get()），不通过闭包捕获。
----------------------------------------------------------------
local ICW = require 'maps.amap.ICW.table'
local Gui = require 'utils.gui'
local GuiDispatcher = require 'utils.gui_dispatcher'
local WPT = require 'maps.amap.table'

local Public = {}

----------------------------------------------------------------
-- GUI 元素 name：全部用固定字符串常量
----------------------------------------------------------------
local LINK_CHEST_FRAME   = "lc_link_chest_frame"
local LINK_CHEST_DROPDOWN = "lc_link_chest_dropdown"
local LINK_CHEST_CONFIRM  = "lc_link_chest_confirm"
local LINK_CHEST_CANCEL   = "lc_link_chest_cancel"

----------------------------------------------------------------
-- 获取第一个 cargo-wagon 的输入箱A的 link_id
-- @return link_id (number) 或 nil
-- @return wagon_num (number) 或 nil
----------------------------------------------------------------
function Public.get_default_link_id()
    local wagons = ICW.get('wagons')
    local wagon_num = 0
    for un, wagon in pairs(wagons) do
        if wagon.name == 'cargo-wagon' and wagon.chests then
            wagon_num = wagon_num + 1
            if wagon.chests[1] and wagon.chests[1].valid then
                return wagon.chests[1].link_id, wagon_num
            end
        end
    end
    return nil, nil
end

----------------------------------------------------------------
-- 根据 link_id 获取车厢描述文本（如 "车厢1-输入箱A"）
-- @param link_id: number
-- @return string 描述文本
----------------------------------------------------------------
function Public.get_link_description(link_id)
    if not link_id then
        return '未连接'
    end
    local wagons = ICW.get('wagons')
    local wagon_num = 0
    for un, wagon in pairs(wagons) do
        if wagon.name == 'cargo-wagon' and wagon.chests then
            wagon_num = wagon_num + 1
            for i, chest in ipairs(wagon.chests) do
                if i <= 2 and chest.valid and chest.link_id == link_id then
                    local suffix = (i == 1) and '输入箱A' or '输入箱B'
                    return '车厢' .. wagon_num .. '-' .. suffix
                end
            end
        end
    end
    return '未连接'
end

----------------------------------------------------------------
-- 更新关联箱上的漂浮文字，显示连接的车厢信息
-- @param entity: linked-chest 实体
-- @param link_id: 当前 link_id
----------------------------------------------------------------
function Public.update_link_chest_label(entity, link_id)
    local icw = ICW.get()
    local un = entity.unit_number
    -- 销毁旧的渲染对象
    if icw.link_chest_renders and icw.link_chest_renders[un] then
        local old_render = icw.link_chest_renders[un]
        if old_render and old_render.valid then
            old_render.destroy()
        end
    end
    local desc = Public.get_link_description(link_id)
    local render_obj = rendering.draw_text {
        text = desc,
        surface = entity.surface,
        target = entity,
        target_offset = {0, -1},
        color = {r = 0.85, g = 0.85, b = 0.3, a = 1},
        scale = 1.05,
        font = 'default-large-semibold',
        alignment = 'center',
        scale_with_zoom = false
    }
    if not icw.link_chest_renders then
        icw.link_chest_renders = {}
    end
    icw.link_chest_renders[un] = render_obj
end

----------------------------------------------------------------
-- 打开关联箱连接选择 GUI
-- @param player: LuaPlayer
-- @param linked_chest_entity: 刚放置的 linked-chest 实体
----------------------------------------------------------------
function Public.show_link_chest_gui(player, linked_chest_entity)
    local this = ICW.get()
    local wagons = ICW.get('wagons')
    local player_index = player.index

    -- 构建下拉列表：列出所有 cargo-wagon 的输入箱
    local items = {}
    local link_ids = {}
    local wagon_num = 0

    for un, wagon in pairs(wagons) do
        if wagon.name == 'cargo-wagon' and wagon.chests then
            wagon_num = wagon_num + 1
            for i, chest in ipairs(wagon.chests) do
                if i <= 2 then  -- 只列出输入箱（上排）
                    local label
                    if i == 1 then
                        label = {'icw.link_chest_wagon_a', wagon_num}
                    else
                        label = {'icw.link_chest_wagon_b', wagon_num}
                    end
                    table.insert(items, label)
                    table.insert(link_ids, chest.link_id)
                end
            end
        end
    end

    if #items == 0 then
        player.print({'icw.link_chest_no_wagons'})
        return
    end

    -- 关闭玩家已有的关联箱 GUI（如果有）
    local old_frame = player.gui.screen[LINK_CHEST_FRAME]
    if old_frame and old_frame.valid then
        Gui.destroy(old_frame)
    end

    -- 存储待连接数据（全部存 global，不通过闭包捕获）
    this.pending_links[player_index] = {
        entity = linked_chest_entity,
        link_ids = link_ids,
        surface_index = linked_chest_entity.surface.index,
        entity_unit_number = linked_chest_entity.unit_number,
        entity_position = {x = linked_chest_entity.position.x, y = linked_chest_entity.position.y}
    }

    -- 创建主 Frame
    local frame = player.gui.screen.add({
        type = 'frame',
        name = LINK_CHEST_FRAME,
        caption = {'icw.link_chest_title'},
        direction = 'vertical'
    })
    frame.auto_center = true

    -- 描述文本
    frame.add({
        type = 'label',
        caption = {'icw.link_chest_desc'},
        style = 'caption_label'
    })

    -- 分割线
    frame.add({
        type = 'line'
    })

    -- 下拉框
    local dropdown = frame.add({
        type = 'drop-down',
        name = LINK_CHEST_DROPDOWN,
        items = items,
        selected_index = 1
    })

    -- 提示说明
    frame.add({
        type = 'label',
        caption = {'icw.link_chest_info'},
        style = 'caption_label'
    })

    -- 按钮区域
    local button_flow = frame.add({
        type = 'flow',
        direction = 'horizontal',
        style = 'dialog_buttons_horizontal_flow'
    })

    -- 确认按钮
    local confirm_btn = button_flow.add({
        type = 'button',
        name = LINK_CHEST_CONFIRM,
        caption = {'icw.link_chest_confirm'}
    })
    confirm_btn.style.minimal_width = 100

    -- 取消按钮
    local cancel_btn = button_flow.add({
        type = 'button',
        name = LINK_CHEST_CANCEL,
        caption = {'icw.link_chest_cancel'}
    })
    cancel_btn.style.minimal_width = 100

    -- 将 frame 设为玩家打开的 GUI（支持 E 键关闭）
    player.opened = frame
end

----------------------------------------------------------------
-- GUI 事件处理
-- GuiDispatcher 按 element.name 自动路由，handler 只含业务逻辑。
-- 运行时状态通过 player_index 查 global（ICW.get()），不依赖闭包。
----------------------------------------------------------------

local function on_confirm_click(event)
    local p = game.get_player(event.player_index)
    if not p or not p.valid then return end
    local pi = p.index

    local icw = ICW.get()
    local data = icw.pending_links and icw.pending_links[pi]
    if not data then return end

    local frame_elem = p.gui.screen[LINK_CHEST_FRAME]
    if not frame_elem or not frame_elem.valid then
        icw.pending_links[pi] = nil
        return
    end

    local dropdown_elem = frame_elem[LINK_CHEST_DROPDOWN]
    if not dropdown_elem or not dropdown_elem.valid then
        icw.pending_links[pi] = nil
        Gui.destroy(frame_elem)
        return
    end

    local selected_index = dropdown_elem.selected_index
    if selected_index < 1 or selected_index > #data.link_ids then
        p.print({'icw.link_chest_invalid_selection'})
        return
    end

    local entity = data.entity
    if not entity or not entity.valid then
        local surface = game.surfaces[data.surface_index]
        if surface and surface.valid then
            local entities = surface.find_entities_filtered({
                name = 'linked-chest',
                position = data.entity_position,
                radius = 0.5
            })
            if #entities > 0 then
                entity = entities[1]
            end
        end
    end
    if not entity or not entity.valid then
        p.print({'icw.link_chest_entity_lost'})
        Gui.destroy(frame_elem)
        icw.pending_links[pi] = nil
        return
    end

    local target_link_id = data.link_ids[selected_index]
    entity.link_id = target_link_id

    Public.update_link_chest_label(entity, target_link_id)

    local selected_text = dropdown_elem.items[selected_index]
    p.print({'icw.link_chest_success', selected_text})

    Gui.destroy(frame_elem)
    icw.pending_links[pi] = nil
end

local function on_cancel_click(event)
    local p = game.get_player(event.player_index)
    if not p or not p.valid then return end
    local pi = p.index

    local icw = ICW.get()
    local data = icw.pending_links and icw.pending_links[pi]
    if not data then return end

    local frame_elem = p.gui.screen[LINK_CHEST_FRAME]
    if frame_elem and frame_elem.valid then
        if p.opened == frame_elem then
            p.opened = nil
        end
        Gui.destroy(frame_elem)
    end

    icw.pending_links[pi] = nil
    p.print({'icw.link_chest_cancelled'})
end

local function on_frame_closed(event)
    local pi = event.player_index
    local icw = ICW.get()
    if icw.pending_links and icw.pending_links[pi] then
        icw.pending_links[pi] = nil
    end
    Gui.destroy(event.element)
end

GuiDispatcher.register_click(LINK_CHEST_CONFIRM, on_confirm_click)
GuiDispatcher.register_click(LINK_CHEST_CANCEL, on_cancel_click)
GuiDispatcher.register_closed(LINK_CHEST_FRAME, on_frame_closed)

return Public
