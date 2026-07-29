---
name: lua-coding-style
description: 坦克保卫战 Lua 编码风格与工程规范指南。规范模块导出、命名、require、局部缓存、文件编码、注释等方面。在编写、修改或审查项目中任何 Lua 文件时使用。
---

# 坦克保卫战 Lua 编码风格指南

## 1. 模块导出模式

项目存在多种导出模式，按场景选择：

| 模式 | 适用场景 | 示例 |
|------|---------|------|
| `local Public = {} ... return Public` | **主流模式**，绝大多数模块 | `event_core.lua`, `tianfu.lua`, `balance.lua`, `common.lua` |
| `local M = {} ... Instance.register(M.type, M)` | **副本玩法模块**，自注册 | `arena_survival.lua`, `boss_hunt.lua` |
| `local <Module> = {} ... return <Module>` | **工具模块**，表名即模块名 | `Token`, `Global` |
| `local Public = require '子模块'` | **聚合层**，复用子模块的 Public | `rpg/core.lua` 复用 `rpg/table.lua` |
| 纯副作用模块，无 return | **入口/注册模块**，require 即生效 | `world_main.lua`, `dungeon.lua` |

### 主流模式模板

```lua
local Event = require 'utils.event'
local Global = require 'utils.global'

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
    this.some_field = {}
    this.some_counter = 0
end

Event.on_init(Public.reset_table)

return Public
```

### 副本自注册模式模板

```lua
local Instance = require 'maps.amap.instance.instance'

local M = {}

M.type = 'my_instance'
M.display_name_key = 'amap.instance_my_instance_name'
M.description_key = 'amap.instance_my_instance_desc'
M.gameplay_desc_key = 'amap.instance_my_instance_gameplay'
M.victory_condition_key = 'amap.instance_my_instance_victory'
M.icon = 'item/submachine-gun'
M.time_limit_default = 300

M.difficulty_settings = {
    easy = { half_size = 18, wave_count = 5 },
    normal = { half_size = 14, wave_count = 7 },
    hard = { half_size = 12, wave_count = 10 },
}

function M.on_surface_init(data) end
function M.on_enter(data, player) end
function M.on_tick(data) end
function M.check_victory(data) end
function M.on_entity_died(data, event) end
function M.on_player_died(data, event) end
function M.on_exit(data) end

Instance.register(M.type, M)
```

## 2. 命名规范

| 类别 | 风格 | 示例 |
|------|------|------|
| 模块级 local 表 | `this` / `map` / `M` / `Public` | `local this = {}`（数据表）, `local M = {}`（副本模块） |
| 常量 | `SCREAMING_SNAKE_CASE` | `DEFAULT_TIME_LIMIT`, `ROBOT_TECH_BLACKLIST`, `ARM_HALF_WIDTH` |
| GUI 元素名常量 | `SCREAMING_SNAKE_CASE` | `GUI_EXIT_BUTTON`, `GUI_TIMER`, `GUI_DIFFICULTY_FRAME` |
| 函数 | `snake_case` | `on_entity_died`, `spawn_wave`, `calc_side_count` |
| Public API 函数 | `Public.snake_case` | `Public.get()`, `Public.reset_table()`, `Public.is_learned()` |
| 天赋 ID | 中文拼音缩写（2~4字符），少数英文 | `'yl'`(鱼灵), `'mlzq'`(魔力之泉), `'hmds'`(黑魔导师), `'fish'`, `'wolf'` |
| 世界模块文件名 | `world_XX_<name>.lua`（XX 两位数编号） | `world_15_tower_defense.lua` |
| 副本模块文件名 | `<玩法名>.lua` | `arena_survival.lua`, `boss_hunt.lua` |
| GUI 元素名字符串 | `dungeon_<缩写>_<功能>` | `dungeon_exit_button`, `dungeon_as_wave`, `dungeon_bh_boss_hp` |
| 本地化键 | `amap.<功能域>_<描述>` | `amap.talent_category_mage`, `amap.instance_arena_survival_name` |

### 命名反面案例

```lua
-- 错误：常量用 camelCase
local defaultTimeLimit = 300

-- 正确：常量用 SCREAMING_SNAKE_CASE
local DEFAULT_TIME_LIMIT = 300

-- 错误：函数用 PascalCase
function Public.ResetTable() end

-- 正确：函数用 snake_case
function Public.reset_table() end
```

## 3. require 规则

### 路径格式

- **点分隔**，从场景根开始：`require 'maps.amap.tianfu_table'`
- **utils 层**：`require 'utils.event'`, `require 'utils.global'`, `require 'utils.token'`
- **modules 层**：`require 'modules.rpg.core'`, `require 'modules.wave_defense.table'`
- 单引号为主，双引号也可用：`require "maps.amap.rocks_yield_ore"`

### 限制

- **require 只能在文件顶层使用**（Factorio 运行时 `/c` 命令中禁止 require）
- 运行时动态加载用 `Token.register` 注册闭包，而非 require

### require 顺序

按以下分组排列，组间空行分隔：

1. 标准库 / Factorio API（无 require，直接使用 `math`, `table`, `game`, `script` 等）
2. `utils.*` 工具模块
3. `modules.*` 功能模块
4. `maps.amap.*` 项目模块
5. 同目录子模块

```lua
local Event = require 'utils.event'
local Global = require 'utils.global'
local Token = require 'utils.token'

local RPG = require 'modules.rpg.main'
local WaveDefense = require 'modules.wave_defense.table'

local WPT = require 'maps.amap.table'
local Tianfu = require 'maps.amap.tianfu'
```

## 4. 局部缓存优化

热路径（每 tick 调用、高频事件处理）中，将全局函数缓存为局部变量：

```lua
local insert = table.insert
local remove = table.remove
local sqrt = math.sqrt
local floor = math.floor
local round = math.round
local sub = string.sub
```

**仅对热路径使用**，非热路径的普通函数不需要缓存。

## 5. 文件编码

| 规则 | 说明 |
|------|------|
| 新建文件 | **UTF-8** |
| 修改已有文件 | **先检测原编码并保持一致** |
| 禁止 PowerShell `Set-Content` | 写含中文的 Lua 文件会乱码（`Set-Content` 默认编码非 UTF-8） |
| 正确做法 | 使用 `edit` 工具做精确文本替换，不改变文件编码 |
| 批量写入 | 用 `[System.IO.File]::WriteAllBytes()` 读写原始字节 |

### 事故记录

2026-07-05：用 `Set-Content` 批量删除事件过滤器，导致 13 个文件中文全部乱码，不得不从备份还原。**教训：对含中文文件，只用 `edit` 工具逐个修改。**

## 6. 注释

- 代码注释使用**中文**或**英文**均可，但**单个文件内保持一致**
- 注释说明"为什么"（why），而非"是什么"（what）
- 文档注释风格：

```lua
--[[ rand_range - Return random integer within the range.
@param start - Start range.
@param stop - Stop range.
--]]
function Public.rand_range(start, stop)
    return math.random(start, stop)
end
```

## 7. 错误处理

- **错误不可掩盖**：禁止用过度 try-catch（pcall）、默认值兜底、注释或 return 绕过错误
- 内部逻辑必须让错误正常暴露
- 仅允许在外部边界（网络请求、用户输入等）做必要容错
- xpcall 仅用于事件 handler 诊断（`[AMAP-DIAG]` 模式），不用于静默吞错

```lua
-- 错误：掩盖错误
local ok, result = pcall(some_func)
if not ok then return default_value end

-- 正确：让错误正常暴露
local result = some_func()
```

## 8. 性能模式

### 倒排索引替代全扫描

```lua
-- 错误：每 tick 遍历所有玩家
for _, player in pairs(game.connected_players) do
    if has_learned(player, skill_id) then
        apply_effect(player)
    end
end

-- 正确：倒排索引直接定位
local owners = skill_owners[skill_id]
if owners then
    for player_index, _ in pairs(owners) do
        local player = game.get_player(player_index)
        if player and player.valid then
            apply_effect(player)
        end
    end
end
```

### tick 分桶调度

```lua
-- 错误：每 tick 遍历所有玩家检查冷却
for _, player in pairs(game.connected_players) do
    if cooldown_expired(player) then trigger(player) end
end

-- 正确：分桶，只处理到期玩家
local bucket = due_buckets[game.tick]
if bucket then
    for player_index, skills in pairs(bucket) do
        process_skills(player_index, skills)
    end
    due_buckets[game.tick] = nil
end
```

### 副本事件隔离

```lua
-- 副本 surface 上的事件不应触发主世界逻辑
local function on_entity_died(event)
    local entity = event.entity
    if not entity or not entity.valid then return end
    if Instance.is_dungeon_surface(entity.surface.name) then return end
    -- 主世界逻辑...
end
```

## 审查清单

修改 Lua 代码时，对照检查：

- [ ] 模块导出模式是否匹配场景（Public / M / 纯副作用）
- [ ] 命名风格是否符合上表（常量 SCREAMING_SNAKE_CASE、函数 snake_case）
- [ ] require 路径是否从场景根开始、是否仅在文件顶层
- [ ] 热路径是否做了局部缓存优化
- [ ] 文件编码是否为 UTF-8（修改已有文件时是否保持原编码）
- [ ] 是否用 `edit` 工具修改含中文文件（而非 PowerShell Set-Content）
- [ ] 是否掩盖了错误（过度 pcall / 默认值兜底）
- [ ] 高频遍历是否可用倒排索引 / tick 分桶优化
- [ ] 副本事件是否做了 surface 隔离
