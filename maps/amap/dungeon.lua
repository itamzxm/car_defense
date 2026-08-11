-- maps/amap/dungeon.lua
-- 副本框架门面（facade）
--
-- 历史：本文件曾是 1288 行的挖币副本完整实现。已重构为副本框架，
--       玩法逻辑迁移至 maps/amap/instance/modules/coin_mine.lua，
--       框架核心位于 maps/amap/instance/instance.lua，
--       奖励池位于 maps/amap/instance/rewards.lua。
--
-- 职责：保留原 Public API 向后兼容，内部委托给 Instance 框架。
--       外部 require 'maps.amap.dungeon' 完全无感。
--       8 个外部依赖点（island_manager / rock / tank / biters_yield_coins /
--       main / tianfu_time_skill / tianfu_trigger_skill）零修改。
--
-- 详见 更新3-A_副本框架设计.md

-- 引入框架核心（require 触发 instance.lua 内的事件注册）
local Instance = require 'maps.amap.instance.instance'

-- 引入玩法模块（require 触发 Instance.register）
require 'maps.amap.instance.modules.coin_mine'
require 'maps.amap.instance.modules.minesweeper'
require 'maps.amap.instance.modules.sudoku'
require 'maps.amap.instance.modules.klotski'
require 'maps.amap.instance.modules.arena_survival'
require 'maps.amap.instance.modules.gold_digger'
require 'maps.amap.instance.modules.dodgeball'
require 'maps.amap.instance.modules.boss_hunt'
require 'maps.amap.instance.modules.rhythm'
require 'maps.amap.instance.modules.memory_corridor'
require 'maps.amap.instance.modules.mini_td'
require 'maps.amap.instance.modules.merge2048'
require 'maps.amap.instance.modules.watersort'
require 'maps.amap.instance.modules.strands'
require 'maps.amap.instance.modules.qiuheti'
require 'maps.amap.instance.modules.tendrops'
require 'maps.amap.instance.modules.suika'
require 'maps.amap.instance.modules.match3'
require 'maps.amap.instance.modules.stack'
require 'maps.amap.instance.modules.potato_survival'
-- 休息室特殊副本（2026-08-11 追加）
require 'maps.amap.instance.modules.lounge'
-- 休闲小游戏副本（2026-08-10 追加）
require 'maps.amap.instance.modules.whack_a_mole'
require 'maps.amap.instance.modules.farm'

-- 引入内置奖励（require 触发 Rewards.register）
require 'maps.amap.instance.rewards.builtin'

local Public = {}

--==============================================================================
-- Public API（与原 dungeon.lua 完全兼容）
--==============================================================================

-- 进入副本
-- 兼容旧签名：enter_dungeon(player, difficulty) → Instance.enter(player, 'coin_mine', difficulty)
function Public.enter_dungeon(player, difficulty)
    return Instance.enter(player, 'coin_mine', difficulty)
end

-- 退出副本
-- 兼容旧签名：exit_dungeon(player, reason) → Instance.exit(player, reason)
function Public.exit_dungeon(player, reason)
    return Instance.exit(player, reason)
end

-- 显示难度选择 GUI
-- 兼容旧入口：直接弹难度选择（玩法类型默认 coin_mine）
function Public.show_difficulty_selection_gui(player)
    return Instance.show_difficulty_selection_gui(player, 'coin_mine')
end

-- 获取玩家当前副本难度
-- 兼容旧签名：get_difficulty(player_index) → "easy" / "normal" / "hard"
function Public.get_difficulty(player_index)
    local data = Instance.get_data(player_index)
    return data.difficulty or "easy"
end

-- 获取难度设置表
-- 兼容旧签名：get_difficulty_settings() → coin_mine.difficulty_settings
function Public.get_difficulty_settings()
    local mod = Instance.get_module('coin_mine')
    return mod and mod.difficulty_settings or {}
end

return Public
