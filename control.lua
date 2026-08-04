-- control.lua
-- 场景入口
--
-- 原则：
--   1. 本文件是唯一可含事件 filters 的文件
--   2. 可开关模块通过 config.lua 决定是否加载（替代注释开关）
--   3. 核心基础设施（utils/chatbot/commands）始终启用

-- 生命周期与调试开关
require 'utils.data_stages'
_LIFECYCLE = _STAGE.control -- Control stage
_DEBUG = false
_DUMP_ENV = false

-- 核心基础设施：事件系统、闭包持久化、全局持久化、服务器通信、通用工具
require 'utils.event_core'
require 'utils.token'
require 'utils.global'
require 'utils.server'
require 'utils.server_commands'
require 'utils.utils'
require 'utils.table'
require 'utils.freeplay'

-- 数据存储：UPS监控、玩家颜色、在线会话、监禁、快捷栏、入服消息、玩家标签
require 'utils.datastore.server_ups'
require 'utils.datastore.color_data'
require 'utils.datastore.session_data'
require 'utils.datastore.jail_data'
require 'utils.datastore.quickbar_data'
require 'utils.datastore.message_on_join_data'
require 'utils.datastore.player_tag_data'

-- 调试工具：性能分析器（/profile）、调试基础设施、调试面板（/debug，仅admin）
require 'utils.profiler'
require 'utils.debug'
require 'utils.event'
require 'utils.debug.command'

-- 聊天机器人：/trust /untrust 命令、关键词自动回复、admin 命令广播
require 'chatbot'
-- 玩家命令聚合：commands.misc + commands.where
require 'commands'

-- config.lua 加载
local config = require 'config'

-- =============================================================================
-- 功能模块（modules/）
-- =============================================================================
if config.modules.floaty_chat.enabled then
    require 'modules.floaty_chat'
end
if config.modules.show_inventory.enabled then
    require 'modules.show_inventory'
end

-- =============================================================================
-- 面板（comfy_panel/）
-- =============================================================================
if config.panel.main.enabled then
    require 'comfy_panel.main'
end
if config.panel.player_list.enabled then
    require 'comfy_panel.player_list'
end
if config.panel.admin.enabled then
    require 'comfy_panel.admin'
end
if config.panel.group.enabled then
    require 'comfy_panel.group'
end
if config.panel.poll.enabled then
    require 'comfy_panel.poll'
end
if config.panel.score.enabled then
    require 'comfy_panel.score'
end
if config.panel.config.enabled then
    require 'comfy_panel.config'
end

if config.modules.autostash.enabled then
    require 'modules.autostash'
end

-- =============================================================================
-- 地图系统（maps/）——同一时间只启用一个地图
-- =============================================================================
if config.map.amap_main.enabled then
    require 'maps.amap.main'
end
if config.map.amap_tank.enabled then
    require 'maps.amap.tank'
end

-- =============================================================================
-- 更多模块（RPG/宠物，需在地图后加载）
-- =============================================================================
if config.modules.rpg.enabled then
    require 'modules.rpg.main'
end
if config.modules.pet_system.enabled then
    require 'modules.pet_system.main'
end

-- =============================================================================
-- 顶栏按钮顺序（必须在所有按钮模块之后加载，否则玩家加入时按钮未创建完、
-- 重排会漏掉，按钮从末尾闪现到正确位置）
-- =============================================================================
if config.gui.top_button_order.enabled then
    require 'utils.top_button_order'
end

if _DUMP_ENV then
    require 'utils.dump_env'
end
