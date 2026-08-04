-- 顶栏按钮顺序管理（参考 archive/classic-changes 的 top_button_order.lua）
-- 玩家加入时按 TOP_BUTTON_ORDER 重排 mod_gui 大框（mod_gui_inner_frame）内的按钮。
-- 目标顺序：折叠开关恒第一，然后 鱼、投票、RPG、宠物、天赋、难度、选图、地图信息、蓄电池。
-- 说明：
--   - 难度按钮（difficulty_gui）当前隐藏（HIDE_DIFFICULTY_BUTTON=true），不显示也不影响顺序；
--   - 未列入顺序的按钮（如 minimap_button）排在最后；
--   - 波防条（wave_defense）在 mod_gui_top_frame 外（gui.top 右侧），不参与本排序。
local Event = require 'utils.event'
local Gui = require 'utils.gui'
local Token = require 'utils.token'
local Task = require 'utils.task'
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

-- 延迟重排：部分按钮（宠物等）在玩家加入后才创建，立即重排会漏掉，
-- 延迟 120 tick（2 秒）等所有按钮创建完再重排
local delayed_reorder = Token.register(function(event)
    local player = game.get_player(event.player_index)
    if player and player.valid then
        reorder_top_buttons(player)
    end
end)

Event.add(defines.events.on_player_joined_game, function(event)
    local player = game.players[event.player_index]
    if player and player.valid then
        reorder_top_buttons(player)
        Task.set_timeout_in_ticks(120, delayed_reorder, {player_index = player.index})
    end
end)

Event.add(defines.events.on_player_created, function(event)
    local player = game.players[event.player_index]
    if player and player.valid then
        reorder_top_buttons(player)
        Task.set_timeout_in_ticks(120, delayed_reorder, {player_index = player.index})
    end
end)

Public.reorder_top_buttons = reorder_top_buttons

return Public
