---
name: world-addition-guide
description: 坦克保卫战新世界添加指南。提供从零开始添加一个新世界的完整步骤，包括 World.register 注册、def 字段定义、地形生成器、事件注册、locale 同步、surface_config 配置等。在添加新世界或修改已有世界定义时使用。
---

# 坦克保卫战新世界添加指南

## 前置知识

- 世界系统使用**注册表模式**：`World.register(world_id, def)` 一次性定义所有配置
- 世界模块在 `require` 时自动注册（副作用模块）
- `World.get(world_id)` 查询世界定义，替代散落的 `if world_number == N` 分支

## 步骤 1：创建世界模块文件

在 `maps/amap/world/worlds/` 下创建文件：

```
world_XX_<name>.lua
```

- `XX` 为两位数编号，紧接已有最大编号（当前最大为 15）
- `<name>` 为英文简短描述，snake_case

示例：`world_16_snow_survival.lua`

## 步骤 2：编写世界定义

### 基本结构

```lua
local Event = require 'utils.event'
local World = require 'maps.amap.world.framework'
local WPT = require 'maps.amap.table'
local Diff = require 'maps.amap.diff'

local world16 = {}

-- 常量定义
local SOME_CONSTANT = 100

-- 地形生成器
local function terrain_generator(surface, left_top, map)
    -- 地形生成逻辑
end

-- Boss 生成函数（如需）
local function spawn_boss(surface, position)
    -- Boss 生成逻辑
end

-- 事件处理
local function on_chunk_generated(event)
    local surface = event.surface
    local area = event.area
    local left_top = area.left_top
    local map = WPT.get()

    if surface.name ~= 'nauvis' then return end
    if map.world ~= 16 then return end

    local world_def = World.get(16)
    if world_def and world_def.terrain_generator then
        world_def.terrain_generator(surface, left_top, map)
    end
end

Event.add(defines.events.on_chunk_generated, on_chunk_generated)

-- 注册世界定义
World.register(16, {
    display_name = '雪原生存',
    terrain_generator = terrain_generator,
    world_bonus_type = 'combat',
    spawn_boss = spawn_boss,
    boss_interval = 7200,  -- 每 2 分钟
    disabled_talents = {},  -- 禁用的天赋列表
    custom_on_tick = nil,   -- 自定义 on_tick 处理
})
```

### def 字段说明

| 字段 | 类型 | 必需 | 说明 |
|------|------|------|------|
| `display_name` | string | 是 | 世界显示名称（中文） |
| `terrain_generator` | function | 是 | 地形生成函数 `(surface, left_top, map)` |
| `world_bonus_type` | string | 否 | 世界奖励类型（`'combat'`, `'production'`, `'exploration'` 等） |
| `spawn_boss` | function | 否 | Boss 生成函数 `(surface, position)` |
| `boss_interval` | number | 否 | Boss 生成间隔（tick） |
| `disabled_talents` | table | 否 | 该世界禁用的天赋 ID 列表 |
| `custom_on_tick` | function | 否 | 自定义 on_tick 处理函数 |
| `on_nth_tick_interval` | number | 否 | 自定义 on_nth_tick 间隔 |
| `on_nth_tick_handler` | function | 否 | 自定义 on_nth_tick 处理函数 |

## 步骤 3：注册到 world_main.lua

在 `maps/amap/world/world_main.lua` 的 require 区域添加：

```lua
require 'maps.amap.world.worlds.world_16_snow_survival'
```

**位置**：在已有世界 require 语句之后，按编号顺序排列。

## 步骤 4：配置 surface_config（如需）

如果新世界需要自定义地表资源配置（资源频率/大小/丰富度），在 `maps/amap/world/world_table.lua` 中添加：

```lua
-- 在 on_init 函数中
this.surface_configs.world16 = {
    autoplace_controls = {
        ['iron-ore'] = { frequency = 1.5, size = 1.0, richness = 1.2 },
        ['copper-ore'] = { frequency = 1.5, size = 1.0, richness = 1.2 },
        ['coal'] = { frequency = 1.0, size = 0.8, richness = 1.0 },
        ['stone'] = { frequency = 1.0, size = 0.8, richness = 1.0 },
        ['uranium-ore'] = { frequency = 0.5, size = 0.5, richness = 0.8 },
        ['crude-oil'] = { frequency = 1.0, size = 1.0, richness = 1.5 },
    },
}
```

## 步骤 5：添加 locale 文本

### 中文 locale

在 `locale/zh-CN/amap.cfg` 的 `[amap]` section 中添加：

```ini
world16_display_name=雪原生存
world16_boss_spawn=Boss 出现！波次 __1__，血量 __2__
world16_build_restricted=此区域禁止建造！
```

### 英文 locale

在 `locale/en/amap.cfg` 的 `[amap]` section 中同步添加：

```ini
world16_display_name=Snow Survival
world16_boss_spawn=Boss spawned! Wave __1__, HP __2__
world16_build_restricted=Building restricted in this area!
```

**键名格式**：`world<数字>_<功能描述>`，参数占位用 `__1__`, `__2__`。

## 步骤 6：注册难度/波次配置（如需）

在 `maps/amap/diff.lua` 中，如果新世界有特殊的波次间隔或奖励配置：

```lua
-- 使用 World 框架 API 替代硬编码
local world_id = map.world
local world_def = World.get(world_id)
if world_def then
    local bonus_type = world_def.world_bonus_type
    -- 应用奖励逻辑
end
```

**优先使用 `World.get_field()` 和 `World.query()` API**，而非 `if world_id == N` 分支。

## 步骤 7：验证

1. **加载测试**：用无头 Factorio 加载场景，确认无 Lua 报错
2. **RCON 测试**：`python rcon_driver.py "_TEST.run_all()"` 确认模块加载成功
3. **游戏测试**：进游戏选择新世界，确认地形生成、Boss 刷新、locale 显示正常

## 地形生成器编写模式

### 标准模式

```lua
local function terrain_generator(surface, left_top, map)
    for x = left_top.x, left_top.x + 31 do
        for y = left_top.y, left_top.y + 31 do
            local pos = {x = x, y = y}

            -- 确定性伪随机（保证每次重开可复现）
            local seed = math.sin(x * 12.9898 + y * 78.233) * 43758.5453
            seed = seed - math.floor(seed)

            -- 根据位置和种子决定地形
            if is_water(pos, seed) then
                surface.set_tiles({{position = pos, name = 'water'}})
            else
                surface.set_tiles({{position = pos, name = 'grass-1'}})
            end
        end
    end
end
```

### 确定性伪随机

使用坐标哈希保证可复现：

```lua
local function hash_position(x, y)
    local seed = math.sin(x * 12.9898 + y * 78.233) * 43758.5453
    return seed - math.floor(seed)
end
```

### 海面禁刷多层防御

```lua
-- 1. 地形生成器中标记海面
-- 2. on_chunk_generated 中清怪
-- 3. 一次性开局地形校正
-- 4. 运行期周期清怪（on_nth_tick）
```

## World 框架 API

| API | 用途 | 示例 |
|-----|------|------|
| `World.register(id, def)` | 注册世界定义 | `World.register(16, def)` |
| `World.get(id)` | 获取世界定义 | `World.get(16)` |
| `World.get_field(id, field)` | 获取单个字段 | `World.get_field(16, 'boss_interval')` |
| `World.get_registered_worlds()` | 获取所有已注册世界列表 | 用于遍历 |
| `World.query(field, value)` | 按字段条件筛选世界 | `World.query('world_bonus_type', 'combat')` |
| `World.get_surface_config(id)` | 获取地表配置 | `World.get_surface_config(16)` |

## 审查清单

添加新世界时，对照检查：

- [ ] 文件名格式为 `world_XX_<name>.lua`，编号连续
- [ ] `World.register` 调用包含所有必需字段
- [ ] `terrain_generator` 使用确定性伪随机（可复现）
- [ ] 事件注册无 filters 参数（handler 内 self-filter）
- [ ] 已在 `world_main.lua` 中添加 require
- [ ] surface_config 已配置（如需自定义资源）
- [ ] 中英 locale 已同步添加，键名格式 `world<数字>_<功能>`
- [ ] 无 `if world_id == N` 硬编码分支（使用 World 框架 API）
- [ ] 已通过无头加载测试

## 参考

- 世界框架实现：`maps/amap/world/framework.lua`
- 世界系统入口：`maps/amap/world/world_main.lua`
- 世界数据表：`maps/amap/world/world_table.lua`
- 世界定义示例：`maps/amap/world/worlds/world_15_tower_defense.lua`
- 世界添加说明文档：`世界添加说明.md`
- Locale 指南：[locale-i18n-guide](../locale-i18n-guide/SKILL.md)
