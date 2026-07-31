--[[
    legacy_gui_cleanup.lua — 旧 GUI 元素名 / 清理函数统一归档

    【过时标记】本文件收集的所有内容均为旧 GUI 残留，待兼容工作完毕后移除。
    当前保留原因：旧存档中仍可能存在这些元素，若不清理会导致名字冲突崩溃。

    迁移路线：
      1. 旧顶栏按钮 → TopBar.add_button()          （已完成）
      2. 旧事件分发   → GuiDispatcher.register_click()（部分完成）
      3. 旧数据绑定   → Gui.set_data / get_data       （待评估）
      4. 旧位置       → player.gui.center → screen    （部分完成）

    使用方式：
      local LegacyCleanup = require 'utils.legacy_gui_cleanup'
      LegacyCleanup.cleanup_legacy_gui(player)   -- 全面清理
      LegacyCleanup.migrate_top_buttons(player)  -- 顶栏按钮迁移

    各 GUI 模块（amap_gui / comfy_panel / top_bar）不再各自维护
    LEGACY 列表，统一从此模块读取。
]]

local mod_gui = require('__core__/lualib/mod-gui')

local Public = {}

-- ═══════════════════════════════════════════════════════════════
-- §1  旧天赋 GUI 元素名
-- 来源：maps/amap/gui.lua + comfy_panel/main.lua（两处曾各自维护相同列表）
-- ═══════════════════════════════════════════════════════════════

local LEGACY_TALENT_GUI_NAMES = {
    'tianfu_frame', 'tianfu_frame_table', 'tianfu_frame_button',
    'tianfu_table', 'tianfu_lengque_table',
    'zhiye_select', 'choise1', 'choise2', 'choise3',
    '选择你的天赋', 'choise_zhiye_frame',
}

local LEGACY_TALENT_GUI_PREFIXES = {
    'tianfu_name_',
    'choise',
}

-- ═══════════════════════════════════════════════════════════════
-- §2  旧 comfy_panel GUI 元素名
-- 来源：comfy_panel/main.lua
-- ═══════════════════════════════════════════════════════════════

local LEGACY_COMPFY_PANEL_GUI_NAMES = {
    'poll_button', 'poll_frame', 'close_poll_frame',
    'mini_camera', 'mini_cam_element',
    'player_list_panel_header_table', 'scroll_pane',
    'player_list_panel_table', 'score_scroll_pane',
    'groups_table', 'group_table', 'frame2',
    'new_group_name', 'new_group_description', 'create_new_group',
    'datalog', 'admin_player_select',
}

-- ═══════════════════════════════════════════════════════════════
-- §3  旧顶栏按钮名
-- 来源：utils/top_bar.lua
-- ═══════════════════════════════════════════════════════════════

local LEGACY_TOP_NAMES = {
    'poll_button',
    'main_button',
    'wave_defense',
    'difficulty_gui',
}

-- ═══════════════════════════════════════════════════════════════
-- §4  合并后的完整列表（供内部使用）
-- ═══════════════════════════════════════════════════════════════

local ALL_LEGACY_NAMES = {}
do
    local seen = {}
    for _, list in ipairs({LEGACY_TALENT_GUI_NAMES, LEGACY_COMPFY_PANEL_GUI_NAMES, LEGACY_TOP_NAMES}) do
        for _, name in ipairs(list) do
            if not seen[name] then
                seen[name] = true
                ALL_LEGACY_NAMES[#ALL_LEGACY_NAMES + 1] = name
            end
        end
    end
end

local ALL_LEGACY_PREFIXES = {}
do
    local seen = {}
    for _, list in ipairs({LEGACY_TALENT_GUI_PREFIXES}) do
        for _, prefix in ipairs(list) do
            if not seen[prefix] then
                seen[prefix] = true
                ALL_LEGACY_PREFIXES[#ALL_LEGACY_PREFIXES + 1] = prefix
            end
        end
    end
end

-- ═══════════════════════════════════════════════════════════════
-- §5  判断 / 清理函数
-- ═══════════════════════════════════════════════════════════════

function Public.is_legacy_name(name)
    for _, n in ipairs(ALL_LEGACY_NAMES) do
        if name == n then return true end
    end
    for _, p in ipairs(ALL_LEGACY_PREFIXES) do
        if name:sub(1, #p) == p then return true end
    end
    return false
end

local function destroy_legacy_in(location)
    if not (location and location.valid) then return end
    local to_kill = {}
    for _, child in pairs(location.children) do
        if child and child.valid and (tonumber(child.name) or Public.is_legacy_name(child.name)) then
            to_kill[#to_kill + 1] = child
        end
    end
    for _, child in ipairs(to_kill) do
        if child.valid then child.destroy() end
    end
end

--- 对玩家的 top / screen / left / center 四个位置全面清理旧元素
function Public.cleanup_legacy_gui(player)
    local top = player.gui.top
    local left = player.gui.left
    local screen = player.gui.screen
    local center = player.gui.center
    for _, location in ipairs({top, screen, left, center}) do
        for _, name in ipairs(ALL_LEGACY_NAMES) do
            if location[name] then location[name].destroy() end
        end
    end
    destroy_legacy_in(top)
    destroy_legacy_in(screen)
    destroy_legacy_in(left)
    destroy_legacy_in(center)
end

--- 将 player.gui.top 中的按钮迁移到 mod_gui button_flow，销毁旧按钮
function Public.migrate_top_buttons(player)
    local top = player.gui.top
    local flow = mod_gui.get_button_flow(player)

    local to_migrate = {}
    local to_destroy = {}
    for _, child in pairs(top.children) do
        if child and child.valid
            and child.name ~= 'mod_gui_top_frame'
            and child.name ~= 'mod_gui_button_flow' then
            if not flow[child.name] then
                to_migrate[#to_migrate + 1] = child
            else
                to_destroy[#to_destroy + 1] = child
            end
        end
    end

    for _, child in ipairs(to_migrate) do
        if child.valid then
            if tonumber(child.name) then
                child.destroy()
            else
                local is_legacy = false
                for _, legacy_name in ipairs(LEGACY_TOP_NAMES) do
                    if child.name == legacy_name then
                        is_legacy = true
                        break
                    end
                end
                if is_legacy then
                    child.destroy()
                else
                    child.parent = flow
                end
            end
        end
    end

    for _, child in ipairs(to_destroy) do
        if child.valid then
            child.destroy()
        end
    end

    for _, child in pairs(flow.children) do
        if child and child.valid then
            for _, legacy_name in ipairs(LEGACY_TOP_NAMES) do
                if child.name == legacy_name then
                    child.destroy()
                    break
                end
            end
        end
    end
end

-- ═══════════════════════════════════════════════════════════════
-- §6  公开列表（供外部模块按需引用，如只清理天赋相关旧元素）
-- ═══════════════════════════════════════════════════════════════

Public.LEGACY_TALENT_GUI_NAMES = LEGACY_TALENT_GUI_NAMES
Public.LEGACY_TALENT_GUI_PREFIXES = LEGACY_TALENT_GUI_PREFIXES
Public.LEGACY_COMPFY_PANEL_GUI_NAMES = LEGACY_COMPFY_PANEL_GUI_NAMES
Public.LEGACY_TOP_NAMES = LEGACY_TOP_NAMES
Public.ALL_LEGACY_NAMES = ALL_LEGACY_NAMES
Public.ALL_LEGACY_PREFIXES = ALL_LEGACY_PREFIXES

return Public
