--[[
    gui_rebuild.lua — GUI 热更 / 存档兼容统一重建入口

    背景：本项目的 GUI 重构（GuiDispatcher + TopBar）把旧 GUI 的清理与重建只挂在了
    on_player_joined_game / on_player_created 上。当场景脚本被“原地热更”（开发者改完代码
    reload、或服务器不重启直接更新场景）时，旧代码构建的 GUI 元素不会消失，新代码又只在
    玩家“重新加入”时才清理重建，于是热更后首次开 GUI 会出现“旧帧残留 + 新帧叠加”的双帧
    冲突（现象：进 GUI 元素全炸 / 服务器存档兼容失败）。

    本模块提供统一注册表：各 GUI 模块把自己的“清理 + 创建”函数注册进来，统一在
    on_configuration_changed（场景脚本版本变化/热更时触发）对所有在线玩家重建。同时提供
    /reload-ui 调试命令，供开发者热更后手动重建。

    注意：本模块只销毁/重建“元素”，不调用 GuiDispatcher.register_*（事件注册必须在
    require 阶段完成，受 _LIFECYCLE==8 守卫保护），因此不会引入 desync 风险。
]]

local Event = require 'utils.event'
local Commands = require 'utils.commands'

local Public = {}

-- 各模块注册的重建函数：{ module_name = function(player) }
local rebuilders = {}

--- 注册一个模块的 GUI 重建函数（清理旧元素 + 创建新按钮/帧）
function Public.register(name, fn)
    rebuilders[name] = fn
end

--- 重建单个玩家的所有 GUI（直接调用，错误向上抛出）。
--- 供 /reload-ui 调试命令使用：开发者应立即看到 stack trace，而非翻日志。
function Public.rebuild_player(player)
    if not (player and player.valid) then
        return
    end
    for _, fn in pairs(rebuilders) do
        fn(player)
    end
end

--- 安全重建单个玩家的所有 GUI（pcall 隔离单模块失败）。
--- 供 on_configuration_changed 使用：避免一个模块出错导致其余重建被中断。
function Public.rebuild_player_safe(player)
    if not (player and player.valid) then
        return
    end
    for _, fn in pairs(rebuilders) do
        local ok, err = pcall(fn, player)
        if not ok then
            log('[gui_rebuild] ' .. tostring(err))
        end
    end
end

local function rebuild_everyone()
    for _, player in pairs(game.connected_players) do
        Public.rebuild_player_safe(player)
    end
end

-- 关键修复：场景脚本热更 / 服务器中途更新场景时，统一重建所有在线玩家的 GUI。
-- 各模块的 on_player_joined_game 仍负责“重新加入”时的重建，这里不重复（避免双跑）。
Event.on_configuration_changed(function()
    rebuild_everyone()
end)

-- 调试命令：开发者热更场景脚本后，手动重建自己的 GUI（需管理员）
Commands.new('reload-ui', 'Rebuild current player GUI (use after hot-reload of scenario script)')
    :require_admin()
    :callback(function(player)
        Public.rebuild_player(player)
        if player and player.valid then
            player.print('[GUI] All interfaces rebuilt')
        end
    end)

return Public
