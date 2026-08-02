---
name: utils-toolbox-guide
description: 坦克保卫C战工具箱速查。覆盖 PriorityQueue、TerrainGenerator、ColorPresets、Timers、Timestamp、ListUtils、Stats、Profiler 等工具模块的 API 与使用场景。在需要使用这些工具时查阅。
---

# 坦克保卫战工具箱速查

> 本 skill 记录 `utils/` 下未被其他 skill 覆盖的工具模块。Queue/Buckets/StateMachine/ErrorLogging/ScoreTracker/ActiveInterval/TemporaryModifiers/PlayerModifiers 见 [global-data-guide](../global-data-guide/SKILL.md)；Alert 见 [gui-development-guide](../gui-development-guide/SKILL.md)。

## PriorityQueue — 最小堆优先队列

小元素优先出队。适合任务调度、事件优先级排序等场景。

```lua
local PriorityQueue = require 'utils.priority_queue'

local queue = PriorityQueue.new()           -- 默认比较器 a < b
-- local queue = PriorityQueue.new(function(a, b) return a.priority < b.priority end)  -- 自定义比较器

PriorityQueue.push(queue, 4)
PriorityQueue.push(queue, 7)
PriorityQueue.push(queue, 2)

local top = PriorityQueue.peek(queue)       -- 2（不出队）
local val = PriorityQueue.pop(queue)         -- 2（出队）
local n = PriorityQueue.size(queue)          -- 2

-- 存档恢复：从已有表加载（保留元数据）
local queue = PriorityQueue.load(saved_table, comparator)
```

### 要点

- 纯表结构 + metatable，**可直接存 storage 持久化**（需用 `load` 恢复 metatable）
- 自定义比较器时，存档恢复必须传入同一比较器
- 空队 `pop` 返回 nil

## TerrainGenerator — 大批量铺 tile 分帧执行器

避免单帧 `set_tiles` 卡顿。队列持久化，存档后继续执行。

```lua
local TerrainGenerator = require 'utils.terrain_generator'

-- 将铺 tile 任务加入队列（默认每 tick 32 块）
local tiles = {}
for x = 1, 100 do
    for y = 1, 100 do
        tiles[#tiles + 1] = {position = {x = x, y = y}, name = 'concrete'}
    end
end
TerrainGenerator.enqueue(surface, tiles)          -- 默认每 tick 32 块
TerrainGenerator.enqueue(surface, tiles, 64)       -- 每 tick 64 块

-- 查询
local empty = TerrainGenerator.is_empty()
```

### 要点

- `enqueue` 后自动启动分帧处理，无需外部驱动
- 队列持久化（`this.queue` + `this.running` 通过 Global.register）
- 多个 enqueue 可排队，按顺序执行
- `per_tick` 越大越快但越卡，默认 32 是安全值

## ColorPresets — 颜色预设常量表

140+ 命名颜色 + 项目专用色，替代内联 RGB 散落各处。

```lua
local Color = require 'utils.color_presets'

-- 基础颜色
player.print('Hello', Color.red)
player.print('Warning', Color.gold)

-- 项目专用色（在文件末尾定义）
Color.comfy      -- comfy 面板主题色
Color.jailed     -- 监禁标记色
Color.trusted    -- 信任标记色
Color.success    -- 成功色（绿）
Color.fail       -- 失败色（红）
Color.warn       -- 警告色（黄）
Color.default    -- 默认色（白）
```

### 要点

- 所有颜色为 `{r, g, b}` 数组格式（非键值表）
- 值域 0~255（非 0~1），使用时需注意 Factorio API 有的接受 0~1 有的接受 0~255
- 与 `gui_styles.lua` 的 `COLORS`/`GUI_COLOR` 互补：ColorPresets 是纯数据表，gui_styles 含 apply_style 等工具函数

## Timers — 通用定时器管理

支持设置/启动/销毁定时器，到期执行回调，可附加每帧更新钩子。

```lua
local Timers = require 'utils.timers'

-- 创建定时器（time_left 为 tick 数，hook 为到期回调）
local id = Timers.set_timer(3600, function()
    game.print('1 分钟到了！')
end)

-- 每帧更新钩子（如倒计时显示）
Timers.set_timer_on_update(id, function(timer)
    local seconds_left = math.floor(timer.time_left / 60)
    label.caption = '剩余 ' .. seconds_left .. ' 秒'
end)

-- 附加依赖数据
Timers.set_timer_dependency(id, {player_index = player.index, boss_name = 'Dragon'})

-- 启动 / 销毁
Timers.set_timer_start(id)
Timers.kill_timer(id)

-- 驱动（需外部每 tick 调用）
Timers.do_job()
```

### 要点

- 持久化：`this.timers` 通过 Global.register
- **需外部每 tick 调用 `do_job()`**（不像 Task 系统自动驱动）
- `id` 基于 `game.tick` 生成，同一 tick 创建多个定时器 id 相同（后创建覆盖前一个）
- 适合需要「每帧更新 UI」的倒计时场景

## Timestamp — Unix 时间戳互转

源自 luatz/timetable，用于服务器时间显示、存档时间戳等。

```lua
local Timestamp = require 'utils.timestamp'

-- Unix 时间戳 → 时间表
local tt = Timestamp.to_timetable(os.time())
-- tt = {year=2026, month=8, day=1, hour=18, min=30, sec=0}

-- 时间表 → Unix 时间戳
local secs = Timestamp.from_timetable({year=2026, month=8, day=1, hour=0, min=0, sec=0})

-- Unix 时间戳 → 人类可读字符串
local str = Timestamp.to_string(os.time())
-- str = "2026-08-01 18:30:00"
```

### 要点

- 无持久化、无事件注册，纯计算工具
- 基于 Unix epoch（1970-01-01 00:00:00 UTC）

## ListUtils — table 扩展工具

扩展 `table` 命名空间的列表操作函数。

```lua
-- 加载后自动挂载到 table 上，无需 require 即可使用（但建议 require 确保加载）
require 'utils.list_utils'

local t = {3, 1, 4, 1, 5}

table.remove_element(t, 4)    -- 按值删除第一个 4 → {3, 1, 1, 5}
local n = table.size(t)       -- 4
local i = table.index_of(t, 1) -- 2（第一个匹配）
local b = table.contains(t, 5)  -- true

local t2 = {9, 8}
table.add_all(t, t2)          -- 合并 → {3, 1, 1, 5, 9, 8}

-- 二分搜索（升序列表）
local sorted = {1, 3, 5, 7, 9}
local pos = table.binary_search(sorted, 5)  -- 3
```

### 要点

- 全部挂载到全局 `table` 上，加载一次即可全局使用
- `binary_search` 要求列表已升序排列
- `remove_element` 只删除第一个匹配项

## Stats — 基础统计计算

纯函数，无状态。

```lua
local Stats = require 'utils.stats'

local data = {10, 20, 30, 40, 50}

local avg = Stats.mean(data)                    -- 30
local med = Stats.median(data)                   -- 30
local modes = Stats.mode(data)                   -- {10, 20, 30, 40, 50}（无重复则全部为众数）
local sd = Stats.standardDeviation(data)         -- 14.14...
local max_val, min_val = Stats.maxmin(data)      -- 50, 10
```

### 要点

- 无持久化、无事件注册，纯计算
- `mode` 返回表（可能有多个众数）
- `standardDeviation` 为总体标准差（除以 N）

## Profiler — Lua 性能分析器

基于 `debug.sethook` 采集调用树，输出耗时统计到日志。调试专用。

```lua
local Profiler = require 'utils.profiler'

-- 启动分析
Profiler.Start()                    -- 可选传入 excludeCalled4Ms 阈值
Profiler.Start(0.5)                 -- 排除耗时 < 0.5ms 的节点

-- 停止分析并输出到日志
Profiler.Stop()                     -- 默认输出
Profiler.Stop(true, 'My Profile')   -- averageMs=true, 自定义标题

-- 查询状态
local running = Profiler.IsRunning
local tree = Profiler.CallTree      -- 当前调用树
```

### 要点

- **仅调试用**，生产环境不要调用
- 通过控制台命令 `/startProfiler` / `/stopProfiler` 操作（仅允许特定管理员）
- `Start` 会设置 `debug.sethook`，有性能开销
- 输出格式为缩进调用树 + 每节点耗时/调用次数

## SpamProtection — GUI 按钮防刷

按 tick 间隔判断玩家是否在刷按钮，防止快速重复点击导致异常。

```lua
local SpamProtection = require 'utils.spam_protection'

-- 在 GUI handler 中使用
GuiDispatcher.register_click(GUI_MY_BUTTON, function(event)
    local player = event.player
    if SpamProtection.is_spamming(player, nil, 'my_button') then
        return
    end
    -- 正常逻辑
end)

-- 自定义间隔（默认 50 tick）
SpamProtection.set_new_value(player)  -- 更新玩家最后操作 tick

-- 重置
SpamProtection.reset_spam_table()

-- 内部状态读写
local val = SpamProtection.get('prevent_spam')
SpamProtection.set('default_tick', 30)
```

### 要点

- 持久化：`prevent_spam` + `default_tick` 通过 Global.register
- `is_spamming` 第二个参数 `value_to_compare` 可传 nil（使用内部默认间隔）
- 管理命令：`/sp-debug-text`、`/sp-debug-spam`、`/sp-print-text`（调试用）

## 工具选型速查

| 需求 | 推荐工具 | 替代 |
|------|---------|------|
| 先进先出队列 | Queue | — |
| 优先级出队 | PriorityQueue | — |
| tick 分桶调度 | Buckets | — |
| 按需启停周期任务 | ActiveInterval | 常驻 on_nth_tick + 守卫 |
| 有限状态机 | StateMachine | — |
| 临时 Force 加成 | TemporaryModifiers | 手写 set + Task 还原 |
| 玩家 modifier 叠加 | PlayerModifiers | 直接写 player[modifier] |
| 统计项读写 | ScoreTracker | 直接 storage 读写 |
| 大批量铺 tile | TerrainGenerator | 直接 set_tiles |
| 弹窗通知 | Alert | game.print |
| 防刷按钮 | SpamProtection | 手写 tick 判断 |
| 倒计时 UI | Timers | Task + 手写更新 |
| 时间戳显示 | Timestamp | os.date |
| 列表操作 | ListUtils | 手写循环 |
| 统计计算 | Stats | 手写公式 |
| 性能分析 | Profiler | — |
| 颜色常量 | ColorPresets /@ gui_styles | 内联 RGB |

## 审查清单

使用工具模块时，对照检查：

- [ ] 是否优先使用项目已有工具（而非手写同类逻辑）
- [ ] 持久化工具是否通过 Global.register 正确注册
- [ ] 加载期专用 API（ScoreTracker.register、ActiveInterval.create）是否不在运行时调用
- [ ] PriorityQueue 存档恢复是否用了 `load` 恢复 metatable
- [ ] TerrainGenerator 的 per_tick 是否合理（默认 32，过大可能卡顿）
- [ ] Timers 是否有外部每 tick 调用 `do_job()`
- [ ] Profiler 是否仅调试用（非生产代码）

## 参考

- PriorityQueue 实现：`utils/priority_queue.lua`
- TerrainGenerator 实现：`utils/terrain_generator.lua`
- ColorPresets 实现：`utils/color_presets.lua`
- Timers 实现：`utils/timers.lua`
- Timestamp 实现：`utils/timestamp.lua`
- ListUtils 实现：`utils/list_utils.lua`
- Stats 实现：`utils/stats.lua`
- Profiler 实现：`utils/profiler.lua`
- SpamProtection 实现：`utils/spam_protection.lua`
