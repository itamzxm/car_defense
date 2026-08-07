-- 顶栏按钮顺序管理（参考 archive/classic-changes 的 top_button_order.lua）
-- 玩家加入时按 TOP_BUTTON_ORDER 重排 mod_gui 大框（mod_gui_inner_frame）内的按钮。
-- 目标顺序：折叠开关恒第一，然后 鱼、投票、RPG、宠物、天赋、难度、选图、地图信息、蓄电池。
-- 说明：
--   - 难度按钮（difficulty_gui）当前隐藏（HIDE_DIFFICULTY_BUTTON=true），不显示也不影响顺序；
--   - 未列入顺序的按钮（如 minimap_button）排在最后；
--   - 波防条（wave_defense）在 mod_gui_top_frame 外（gui.top 右侧），不参与本排序。
-- 无延迟重排：本模块在 control.lua 最后加载（位于所有按钮创建模块之后），玩家加入时全部按钮
-- 已由各模块 on_player_joined_game / on_player_created handler 创建完毕，立即重排即可生效。
-- （旧版曾用 120 tick 延迟重排兜底，已移除：延迟回调在按钮可能被清理/重建的时间窗口外执行，
--   且玩家加入后即时重排已覆盖全部按钮，无需兜底。）
local Event = require 'utils.event'
local Gui = require 'utils.gui'
local Poll = require 'comfy_panel.poll'
local RPG = require 'modules.rpg.table'
local Pet = require 'modules.pet_system.table'
local AmapGui = require 'maps.amap.gui'

local Public = {}

local TOP_BUTTON_ORDER = {
    Gui.get_toggle_button_name(),   -- 折叠开关恒第一
    'comfy_panel_top_button',       -- 鱼
    Poll.main_button_name,          -- 投票
    RPG.draw_main_frame_name,       -- RPG
    Pet.draw_main_button_name,      -- 宠物
    'tianfu',                       -- 天赋
    'difficulty_gui',               -- 难度（当前隐藏，保留位置）
    'poll_button',                  -- 选图
    AmapGui.main_button_name,       -- 地图信息
    'charging_station',             -- 蓄电池
}

local function reorder_top_buttons(player)
    local flow = Gui.get_button_flow(player)
    local children = flow.children
    if #children <= 1 then
        return
    end

    local name_to_order = {}
    for i, name in ipairs(TOP_BUTTON_ORDER) do
        name_to_order[name] = i
    end
    local default_order = #TOP_BUTTON_ORDER + 1

    local function get_order(elem)
        return name_to_order[elem.name] or default_order
    end

    -- 选择排序（与 archive 分支一致）
    for i = 1, #children do
        local min_idx = i
        local min_val = get_order(children[min_idx])
        for j = i + 1, #children do
            local val = get_order(children[j])
            if val < min_val then
                min_val = val
                min_idx = j
            end
        end
        if min_idx ~= i then
            flow.swap_children(i, min_idx)
            children = flow.children
        end
    end
end

Event.add(defines.events.on_player_joined_game, function(event)
    local player = game.players[event.player_index]
    if player and player.valid then
        reorder_top_buttons(player)
    end
end)

Event.add(defines.events.on_player_created, function(event)
    local player = game.players[event.player_index]
    if player and player.valid then
        reorder_top_buttons(player)
    end
end)

Public.reorder_top_buttons = reorder_top_buttons

return Public
