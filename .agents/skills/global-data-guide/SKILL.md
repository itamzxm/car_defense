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

## 审查清单

编写或修改持久化数据代码时，对照检查：

- [ ] 是否使用了 Global.register 三步曲（`local this = {}` → `Global.register` → `Public.get()`）
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
