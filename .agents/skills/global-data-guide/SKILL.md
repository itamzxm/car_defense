---
name: global-data-guide
description: 坦克保卫战全局数据持久化指南。规范 Global.register 三步曲、主表访问、副本数据隔离、Token.register 闭包持久化、倒排索引、tick 分桶调度等模式。在编写、修改或审查任何需要持久化数据的模块时使用。
---

# 坦克保卫战全局数据持久化指南

## 核心机制：Global.register 三步曲

Factorio 场景的 `global`（现称 `storage`）表在存档保存/加载时自动持久化。但模块级 `local` 变量不会自动恢复。`Global.register` 解决此问题。

### 标准模式

```lua
local Global = require 'utils.global'
local Public = {}

-- 第一步：声明模块级 local 表
local this = {}

-- 第二步：注册到 Global 系统
Global.register(
    this,
    function(tbl)
        this = tbl
    end
)

-- 第三步：提供 get() 访问器
function Public.get()
    return this
end
```

### 工作原理

1. **on_init 时**：`this` 是空表 `{}`，`Global.register` 将其存入 `storage` 并记录 token
2. **on_load 时**：`Global.register` 的回调被触发，从 `storage` 取出持久化表赋值回 `this`——模块级 `local` 引用恢复
3. **运行时**：对 `this` 的修改直接修改 `storage` 中的数据，自动持久化

### ⚠ 回调只在 on_load 触发（on_init 用初始表本身）

`Global.register(tbl, callback)` 的 callback **只在 on_load 时执行**。on_init（新游戏）路径下 `this` 就是传入的 `tbl` 本身，callback 不会被调用。

**错误写法（on_init 下 `this.queue` 是 nil）**：

```lua
local this = {}  -- 初始空表

-- ⚠ 错误：初始值放在注册参数里，on_init 时回调不执行 → this 永远是 {}，this.queue = nil
Global.register(
    {queue = {}, running = false},
    function(tbl)
        this = tbl
    end
)
-- 症状：运行时 table.insert(this.queue, ...) 报 "table expected, got nil"
```

**正确写法一（初始值内嵌进 this 本身）**：

```lua
local this = {queue = {}, running = false}  -- 初始值直接放 this

Global.register(this, function(tbl)
    this = tbl
end)
```

**正确写法二（gui.lua 模式：初始表内嵌 local 引用）**：

```lua
local data = {}
local element_map = {}

Global.register(
    {data = data, element_map = element_map},
    function(tbl)
        data = tbl.data
        element_map = tbl.element_map
    end
)
```

### 使用示例

```lua
local Global = require 'utils.global'
local Event = require 'utils.event'
local Public = {}

local this = {}

Global.register(
    this,
    function(tbl)
        this = tbl
    end
)

function Public.get()
    return this
end

function Public.reset_table()
    this.player_data = {}
    this.wave_count = 0
    this.bosses = {}
end

Event.on_init(Public.reset_table)

-- 运行时修改
function Public.increment_wave()
    this.wave_count = this.wave_count + 1
end

-- 运行时读取
function Public.get_wave_count()
    return this.wave_count
end

return Public
```

### Global.register_init

如果需要在 on_init 时执行自定义初始化（而非简单的 reset_table）：

```lua
Global.register_init(
    this,
    function(tbl)
        this = tbl
    end,
    function()
        -- on_init 时执行的自定义初始化
        this.player_data = {}
        this.wave_count = 0
    end
)
```

## 主表访问

### WPT — 全局主表

```lua
local WPT = require 'maps.amap.table'

-- 读取
local map = WPT.get()
local world_id = map.world
local dungeons = map.dungeons

-- 写入
WPT.get().world15_registered_turrets = {}
```

`WPT.get()` 返回的是整个主世界的配置和数据表，包含：
- `world` — 当前世界编号
- `dungeons` — 玩家副本数据 `[player_index] = data`
- `tianfu_enabled` — 天赋启用状态
- `world15_*` — 世界15专用数据
- 其他世界/系统专用字段

### TPT — 天赋专用表

```lua
local TPT = require 'maps.amap.tianfu_table'

-- 读取
local tianfu_data = TPT.get()
local all_skills = tianfu_data.all_skill
local cooldowns = tianfu_data.tianfu_cooldown
```

### 其他专用表

| 模块 | require 路径 | 访问方式 |
|------|-------------|---------|
| 主表 | `maps.amap.table` | `WPT.get()` |
| 天赋表 | `maps.amap.tianfu_table` | `TPT.get()` |
| 难度/波次表 | `maps.amap.diff` | `Diff.get()` |
| RPG 表 | `modules.rpg.table` | `RPG.get()` |
| 波次防御表 | `modules.wave_defense.table` | `WD.get()` |

## 副本数据隔离

### module_data 机制

每个副本玩法模块的私有数据存在 `data.module_data` 中，框架不触碰：

```lua
function M.on_enter(data, player)
    -- data 是副本实例数据，由框架管理
    -- data.module_data 是本玩法的私有空间
    data.module_data.wave = 0
    data.module_data.kills = 0
    data.module_data.spawn_queue = {}
end

function M.on_tick(data)
    -- 直接访问 module_data
    data.module_data.wave = data.module_data.wave + 1
end
```

### 副本实例数据结构

```lua
data = {
    surface = surface,           -- 副本地表
    players = {player_index},    -- 参与玩家列表
    difficulty = 'normal',       -- 难度
    type = 'arena_survival',     -- 玩法类型
    time_limit = 300,            -- 时间限制
    module_data = {},            -- 玩法私有数据（框架不触碰）
    -- ... 框架管理的其他字段
}
```

## Token.register — 闭包持久化

Lua 闭包不能直接存入 `global`/`storage`（不可序列化）。`Token.register` 为闭包分配唯一 ID，使其可安全存入持久化表。

### 注册延迟回调

```lua
local Token = require 'utils.token'

-- 模块级注册（counter 从 200 起）
local kill_forces = Token.register(function(data)
    local entity = data.entity
    if not entity or not entity.valid then return end
    -- 延迟执行的逻辑
    entity.destroy()
end)

-- 存入持久化表
this.pending_destroy[token] = { entity = entity }

-- 运行时取出执行
local callback = Token.get(token)
callback(data)
```

### 双轨注册

| 方法 | 用途 | counter 起始 | 持久化 |
|------|------|-------------|--------|
| `Token.register(fn)` | 模块级注册 | 200 | 否（每次加载重建） |
| `Token.register_global(fn)` | 跨存档持久化 | 存入 `storage.tokens` | 是 |

### 运行时禁止注册

`Token.register` 在 `_LIFECYCLE == 8`（Runtime）时抛错，因为运行期注册会导致 ID 不同步。

### UID 生成器

`Token.uid()` 从 100 起自增，用于运行期唯一 ID（非持久化）。

## 性能优化模式

### 倒排索引替代全扫描

**问题**：每 tick 遍历所有玩家检查是否拥有某天赋/技能。

**解决**：维护倒排索引 `skill_owners[skill_id][player_index] = true`。

```lua
-- 学习天赋时更新索引
function learn_skill(player_index, skill_id)
    this.all_skill[player_index] = this.all_skill[player_index] or {}
    this.all_skill[player_index][skill_id] = true

    -- 更新倒排索引
    this.skill_owners = this.skill_owners or {}
    this.skill_owners[skill_id] = this.skill_owners[skill_id] or {}
    this.skill_owners[skill_id][player_index] = true
end

-- 使用倒排索引直接定位
function get_skill_owners(skill_id)
    return this.skill_owners[skill_id] or {}
end
```

### tick 分桶调度

**问题**：每 tick 遍历所有玩家检查冷却是否到期。

**解决**：到期时将任务放入对应 tick 的桶中，on_tick 只查当前 tick 的桶。

```lua
-- 注册到期任务
function schedule_skill(player_index, skill_id, due_tick)
    this.due_buckets = this.due_buckets or {}
    this.due_buckets[due_tick] = this.due_buckets[due_tick] or {}
    this.due_buckets[due_tick][player_index] = this.due_buckets[due_tick][player_index] or {}
    table.insert(this.due_buckets[due_tick][player_index], skill_id)
end

-- on_tick 只处理当前 tick 的桶
local function on_tick()
    local bucket = this.due_buckets[game.tick]
    if not bucket then return end

    for player_index, skills in pairs(bucket) do
        for _, skill_id in ipairs(skills) do
            trigger_skill(player_index, skill_id)
        end
    end

    this.due_buckets[game.tick] = nil  -- 清理已处理的桶
end
```

### Buckets — tick 分桶调度的规范实现

> 底层冻结对象之一（见 AGENTS.md「底层冻结宣言」）。**所有延迟/周期调度优先用 `utils/buckets.lua`，不要手写 bucket 表**（手写版是上面示例的旧形态）。

```lua
local Buckets = require 'utils.buckets'
local Global = require 'utils.global'

local this = {bucket = Buckets.new(60)}  -- 60 tick 一轮
Global.register(this, function(tbl)
    this = tbl
end)

-- 调度：id 在 (tick / interval) 轮次到期
Buckets.add(this.bucket, id, data)
local bucket = Buckets.get(this.bucket, id)   -- 到期轮次号
Buckets.get_bucket(this.bucket, bucket)       -- 该轮次的所有条目

-- 每 tick：只查当前轮次
local due = this.bucket[math.floor(game.tick / 60)]
if due then
    for id, data in pairs(due) do
        -- 处理到期任务
        Buckets.remove(this.bucket, id)
    end
end

-- 其他接口：remove / reallocate(新间隔，自动迁移) / migrate(旧手写表迁移)
```

要点：

- `Buckets.new(interval)` 返回桶表，**纯表结构可直接存 storage 持久化**
- 到期轮次 = `floor(tick / interval)`；interval 变化时用 `reallocate` 自动迁移，不要手写搬
- 桶条目结构 `bucket[轮次][id] = data`，同一轮次可存多个不同任务

### 分批处理

**问题**：单 tick 遍历所有玩家造成卡顿。

**解决**：使用 `batch_player_index` 分批处理。

```lua
local BATCH_SIZE = 20  -- 每 tick 最多处理 20 个玩家

local function on_tick()
    local players = game.connected_players
    local start = this.batch_player_index or 1
    local finish = math.min(start + BATCH_SIZE - 1, #players)

    for i = start, finish do
        process_player(players[i])
    end

    if finish >= #players then
        this.batch_player_index = 1
    else
        this.batch_player_index = finish + 1
    end
end
```

## GUI 热更重建（GuiRebuild）

GUI 元素不持久化，场景热更 / 存档兼容时旧元素残留会导致"双帧冲突"。各 GUI 模块通过 `GuiRebuild.register` 注册"清理 + 重建"函数，统一在 `on_configuration_changed` 时对所有在线玩家重建。

```lua
local GuiRebuild = require 'utils.gui_rebuild'

GuiRebuild.register('my_module_gui', function(player)
    -- 1. 清理旧元素
    local flow = TopBar.get_button_flow(player)
    if flow[GUI_MY_BUTTON] then flow[GUI_MY_BUTTON].destroy() end
    -- 2. 重新创建
    TopBar.add_button(player, {type = 'sprite-button', name = GUI_MY_BUTTON, ...})
end)
```

- `on_configuration_changed` 自动调用所有已注册重建函数（pcall 隔离单模块失败）
- `/reload-ui` 调试命令手动重建（需管理员，错误直接抛出）
- 只重建元素，不重新注册事件（事件注册在 require 阶段完成）

> 详见 [gui-development-guide](../gui-development-guide/SKILL.md)

## 直接 storage 访问

某些简单数据可以直接读写 `storage`，无需 Global.register：

```lua
-- 直接写入
storage.rocks_yield_ore_maximum_amount = 500

-- 直接读取
local max_amount = storage.rocks_yield_ore_maximum_amount or 100
```

**注意**：仅用于简单场景。复杂数据结构推荐使用 Global.register 三步曲，确保 on_load 后引用正确恢复。

## ScoreTracker — 登记制统计框架

> 底层冻结对象之一。统计项必须先 `register` 才能读写，杜绝拼错键名静默创建新统计。

```lua
local ScoreTracker = require 'utils.score_tracker'

-- 加载期登记（仅 control 阶段，运行时调用会报错）
ScoreTracker.register('kill_count', {'amap.kill_count'}, 'item/submachine-gun')
ScoreTracker.register('death_count', {'amap.death_count'}, 'entity-character')

-- 运行时读写
ScoreTracker.change_for_player(player_index, 'kill_count', 1)   -- 玩家统计 +1
ScoreTracker.change_for_global('total_boss_kills', 1)            -- 全局统计 +1
ScoreTracker.set_for_player(player_index, 'kill_count', 100)     -- 赋值（值不变跳过）
local kills = ScoreTracker.get_for_player(player_index, 'kill_count')
local total = ScoreTracker.get_for_global('total_boss_kills')

-- GUI 展示用：统计值 + 元数据合并
local data = ScoreTracker.get_player_scores_with_metadata(player_index, {'kill_count', 'death_count'})

-- 重置
ScoreTracker.reset()
```

### 自定义事件

变更时触发事件通知，可用于 GUI 刷新等：

```lua
Event.add(ScoreTracker.events.on_player_score_changed, function(event)
    -- event.score_name, event.player_index
end)
Event.add(ScoreTracker.events.on_global_score_changed, function(event)
    -- event.score_name
end)
```

### 要点

- `register` 仅加载期调用，运行时调用报错
- 重复登记同名统计项报错
- `set_for_player/set_for_global` 值不变时跳过（避免无意义事件触发）
- 玩家离开时自动清理该玩家数据（`on_player_removed`）

## ActiveInterval — 按需启停周期任务

> 避免「常驻 on_nth_tick 空扫描」的性能浪费。有活动才 enable，无活动 disable。

```lua
local ActiveInterval = require 'utils.active_interval'

-- 加载期创建句柄（func 在加载期被 Token.register 持久化）
local handle = ActiveInterval.create(60, function()
    -- 每 60 tick 执行一次的逻辑
    -- 例如：检查 Boss 是否存活，存活则扣血
end)

-- 运行时按需启停
handle.enable()    -- 注册 on_nth_tick，开始执行
handle.disable()   -- 移除 on_nth_tick，停止执行
handle.is_active() -- 当前是否激活
```

### 要点

- `create` 仅加载期调用（运行时调用报错，desync 风险）
- 内部用 `Event.add_removable_nth_tick` / `Event.remove_removable_nth_tick` 动态增删
- 适合「有 Boss 才需要每 tick 扣血」「有玩家在副本才需要每 tick 计时」等场景
- 替代方案：常驻 `Event.on_nth_tick` + `if not active then return end` 守卫（浪费每 tick 函数调用开销）

## TemporaryModifiers — Force modifier 临时加成

> 对 Force 数值类 modifier 临时加 bonus，到期后差值还原（不覆盖他人改动）。

```lua
local TemporaryModifiers = require 'utils.temporary_modifiers'

-- 临时给 enemy force 的 laser 伤害加 0.5，持续 3600 tick（1 分钟）
TemporaryModifiers.apply(game.forces.enemy, 'ammo_damage_modifier', 'laser', 0.5, 3600)

-- 临时给 player force 的 laser 射速加 0.2，持续 1800 tick
TemporaryModifiers.apply(game.forces.player, 'gun_speed_modifier', 'laser', 0.2, 1800)
```

### 要点

- 还原用「当前值 - bonus」差值写法：即使期间有其他逻辑再改该字段，只归还自己加上的部分，不覆盖他人改动
- `method` 对应 Force 的 `get_<method>` / `set_<method>` 成对方法
- `kind` 是 modifier 的种类参数（如 `'laser'`、`'artillery'`）
- `bonus` 可为负数（临时削弱）
- 依赖 `Task.set_timeout_in_ticks` 定时还原，存档后还原任务由 Task 系统恢复

## PlayerModifiers — 玩家 modifier 多来源叠加

> 集中管理玩家角色 modifier（建造距离/移动速度/拾取距离等），多来源按类别叠加，统一刷写到角色。

```lua
local PlayerModifiers = require 'utils.player_modifiers'

-- 更新某个 modifier 的某个类别值（如天赋加的移动速度）
PlayerModifiers.update_single_modifier(player, 'character_running_speed_modifier', 'tianfu', 0.3)

-- 禁用某个 modifier（如冰冻效果）
PlayerModifiers.disable_single_modifier(player, 'character_running_speed_modifier', 1)

-- 读取
local val = PlayerModifiers.get_single_modifier(player, 'character_running_speed_modifier', 'tianfu')

-- 刷写所有 modifier 到角色（通常在 on_player_joined_game / on_player_respawned 自动触发）
PlayerModifiers.update_player_modifiers(player)

-- 重置玩家所有 modifier
PlayerModifiers.reset_player_modifiers(player)
```

### 支持的 modifier 列表

| 索引 | modifier 名 |
|------|-------------|
| 1 | `character_build_distance_bonus` |
| 2 | `character_crafting_speed_modifier` |
| 3 | `character_health_bonus` |
| 4 | `character_inventory_slots_bonus` |
| 5 | `character_item_drop_distance_bonus` |
| 6 | `character_item_pickup_distance_bonus` |
| 7 | `character_loot_pickup_distance_bonus` |
| 8 | `character_mining_speed_modifier` |
| 9 | `character_reach_distance_bonus` |
| 10 | `character_resource_reach_distance_bonus` |
| 11 | `character_maximum_following_robot_count_bonus` |
| 12 | `character_running_speed_modifier` |

### 要点

- 多来源叠加：天赋加 0.3 + RPG 加 0.2 → 最终 0.5 刷写到角色
- 类别（category）字符串由调用方自定，如 `'tianfu'`、`'rpg'`、`'buff'`
- `update_player_modifiers` 自动在 `on_player_joined_game` / `on_player_respawned` 时触发
- 库存栏上限保护：`rpg_inventory_slot_limit = 320`（防止超大背包卡服）

## 审查清单

编写或修改持久化数据代码时，对照检查：

- [ ] 是否使用了 Global.register 三步曲（`local this = {}` → `Global.register` → `Public.get()`）
- [ ] 初始字段是否内嵌在 this/注册表里（回调只在 on_load 触发，on_init 不执行）
- [ ] on_init 中是否调用了 `reset_table()` 初始化所有字段
- [ ] 副本模块数据是否存在 `data.module_data` 中（而非主表）
- [ ] 闭包是否通过 Token.register 持久化（而非直接存入 storage）
- [ ] Token.register 是否仅在加载期调用（非 Runtime）
- [ ] 高频遍历是否可用倒推索引 / tick 分桶优化
- [ ] 分批处理是否用于玩家遍历（防止单 tick 卡顿）
- [ ] 直接 storage 访问是否仅用于简单场景
- [ ] 新增 GUI 模块是否注册了 `GuiRebuild.register` 重建函数

## 参考

- Global 系统实现：`utils/global.lua`
- Token 系统实现：`utils/token.lua`
- 主表定义：`maps/amap/table.lua`
- 天赋表定义：`maps/amap/tianfu_table.lua`
- 副本框架：`maps/amap/instance/instance.lua`
