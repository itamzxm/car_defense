---
name: instance-addition-guide
description: 坦克保卫战新副本/小游戏添加指南。提供从零开始添加一个新副本玩法的完整步骤，包括自注册模式、钩子函数定义、难度设计、道具系统、GUI 创建、locale 同步等。在添加新副本玩法或修改已有副本模块时使用。
---

# 坦克保卫战新副本/小游戏添加指南

## 前置知识

- 副本系统使用**自注册模式**：文件末尾 `Instance.register(M.type, M)`，require 即注册
- 副本模块在 `maps/amap/instance/modules/` 下
- 每个副本有独立的 `module_data` 隔离空间
- 难度设计遵循 **2~3 条参数改动原则**

## 步骤 1：创建副本模块文件

在 `maps/amap/instance/modules/` 下创建文件：

```
<玩法名>.lua
```

示例：`treasure_hunt.lua`

## 步骤 2：编写副本模块

### 完整模板

```lua
local Event = require 'utils.event'
local Instance = require 'maps.amap.instance.instance'
local WPT = require 'maps.amap.table'

local M = {}

-- ==================== 元数据 ====================

M.type = 'treasure_hunt'
M.display_name_key = 'amap.instance_treasure_hunt_name'
M.description_key = 'amap.instance_treasure_hunt_desc'
M.gameplay_desc_key = 'amap.instance_treasure_hunt_gameplay'
M.victory_condition_key = 'amap.instance_treasure_hunt_victory'
M.icon = 'item/steel-chest'
M.time_limit_default = 300

-- ==================== 常量 ====================

local DEFAULT_HALF_SIZE = 15
local CHEST_COUNT = 5
local GUI_CHESTS = 'dungeon_th_chests'

-- ==================== 难度设置 ====================

M.difficulty_settings = {
    easy = {
        half_size = 18,
        chest_count = 3,
    },
    normal = {
        half_size = 15,
        chest_count = 5,
    },
    hard = {
        half_size = 12,
        chest_count = 7,
    },
}

-- ==================== 钩子函数 ====================

function M.on_surface_init(data)
    -- 副本地表初始化（地形、装饰、初始实体）
    local surface = data.surface
    local settings = M.difficulty_settings[data.difficulty]
    local half = settings.half_size

    -- 生成围墙
    for x = -half, half do
        for y = -half, half do
            if math.abs(x) == half or math.abs(y) == half then
                surface.create_entity({
                    name = 'stone-wall',
                    position = {x = x, y = y},
                    force = 'player',
                })
            end
        end
    end

    -- 初始化 module_data
    data.module_data.chests_found = 0
    data.module_data.chest_total = settings.chest_count
    data.module_data.chest_positions = {}
end

function M.on_enter(data, player)
    -- 玩家进入副本
    -- 创建 GUI、给予装备等
end

function M.on_tick(data)
    -- 每 tick 逻辑（波次推进、计时器更新等）
    -- 注意：尽量轻量，避免每 tick 做大量计算
end

function M.check_victory(data)
    -- 检查胜利条件
    -- 返回 true 表示胜利
    return data.module_data.chests_found >= data.module_data.chest_total
end

function M.on_entity_died(data, event)
    -- 实体死亡处理
    local entity = event.entity
    if not entity or not entity.valid then return end
end

function M.on_player_died(data, event)
    -- 玩家死亡处理
    -- 可选择：复活玩家 / 标记失败 / 扣分
end

function M.on_exit(data)
    -- 副本退出清理
    -- 清理 GUI、回收实体等
end

-- ==================== 自注册 ====================

Instance.register(M.type, M)
```

### 必需钩子函数

| 钩子 | 调用时机 | 参数 | 用途 |
|------|---------|------|------|
| `M.on_surface_init(data)` | 副本地表创建后 | `data` = 副本实例数据 | 初始化地形、围墙、初始实体 |
| `M.on_enter(data, player)` | 玩家进入副本 | `data`, `player` | 给予装备、创建 GUI、传送 |
| `M.on_tick(data)` | 每 tick | `data` | 波次推进、计时器、周期逻辑 |
| `M.check_victory(data)` | 每 tick | `data` | 检查胜利条件，返回 `true` 表示胜利 |
| `M.on_entity_died(data, event)` | 实体死亡 | `data`, `event` | 处理击杀、掉落、Boss 死亡 |
| `M.on_player_died(data, event)` | 玩家死亡 | `data`, `event` | 复活、失败判定 |
| `M.on_exit(data)` | 副本退出 | `data` | 清理 GUI、回收资源 |

### 必需元数据字段

| 字段 | 类型 | 说明 |
|------|------|------|
| `M.type` | string | 唯一标识符，snake_case |
| `M.display_name_key` | string | locale 键，显示名称 |
| `M.description_key` | string | locale 键，简短描述 |
| `M.gameplay_desc_key` | string | locale 键，玩法说明 |
| `M.victory_condition_key` | string | locale 键，通关条件 |
| `M.icon` | string | 图标，`'item/xxx'` 或 `'entity/xxx'` |
| `M.time_limit_default` | number | 默认时间限制（秒） |

## 步骤 3：设计难度设置

**核心原则：每次难度提升只改 2~3 条参数，做 1.0 → 1.2 → 1.44 的线性增量。**

### 规则

1. easy/normal/hard 之间，只允许 **2~3 个维度**有差异
2. 其余参数**全难度统一**（同一 Boss、同一武器、同一弹药量、同一道具配置等）
3. 优先用「**场地缩小 + 节奏加快**（间隔缩短/波次增多）」这两个维度
4. 不要通过换 Boss 类型、换虫子类型、砍道具种类来提难度

### 示例

```lua
-- 竞技场生存
M.difficulty_settings = {
    easy = {
        half_size = 18,      -- 场地较大
        wave_count = 5,      -- 波次较少
        has_spitter = false,  -- 无远程虫
        has_elite = false,    -- 无精英波
    },
    normal = {
        half_size = 14,      -- 场地缩小
        wave_count = 7,      -- 波次增多
        has_spitter = true,   -- 加远程虫
        has_elite = true,     -- 加精英波
    },
    hard = {
        half_size = 12,      -- 场地再缩小
        wave_count = 10,     -- 波次再增多
        has_spitter = true,   -- 同 normal
        has_elite = true,     -- 同 normal
    },
}
-- easy→normal：场地18→14 + spitter + 精英波 + 波次5→7（3条）
-- normal→hard：场地14→12 + 波次7→10（2条）
```

```lua
-- Boss 讨伐
M.difficulty_settings = {
    easy = {
        half_size = 15,       -- 场地
        minion_interval = 0,  -- 不召小虫
    },
    normal = {
        half_size = 12,       -- 场地缩小
        minion_interval = 30, -- 30秒召小虫
    },
    hard = {
        half_size = 10,       -- 场地再缩小
        minion_interval = 20, -- 20秒召小虫
    },
}
-- 全难度统一：Boss big-biter、速度 0.3、弹药 50、掩体 12、道具 12s/5 种、小虫 small
-- easy→normal：场地15→12 + 小虫间隔0→30s（2条）
-- normal→hard：场地12→10 + 小虫间隔30s→20s（2条）
```

## 步骤 4：注册到 dungeon.lua

在 `maps/amap/dungeon.lua` 的 require 区域添加：

```lua
require 'maps.amap.instance.modules.treasure_hunt'
```

**位置**：在已有玩法 require 语句之后，按字母顺序排列。

## 步骤 5：添加 locale 文本

### 中文 locale（`locale/zh-CN/amap.cfg`）

```ini
instance_treasure_hunt_name=寻宝猎人
instance_treasure_hunt_desc=在限定时间内找到所有宝箱
instance_treasure_hunt_gameplay=搜索副本场地，找到隐藏的宝箱。场地中有障碍物和敌人阻拦你的探索。
instance_treasure_hunt_victory=找到所有宝箱即可通关
treasure_hunt_chests_found=宝箱：__1__ / __2__
```

### 英文 locale（`locale/en/amap.cfg`）

```ini
instance_treasure_hunt_name=Treasure Hunt
instance_treasure_hunt_desc=Find all chests within the time limit
instance_treasure_hunt_gameplay=Search the dungeon for hidden chests. Obstacles and enemies block your path.
instance_treasure_hunt_victory=Find all chests to win
treasure_hunt_chests_found=Chests: __1__ / __2__
```

**键名格式**：`instance_<玩法>_<功能>` 或 `<玩法>_<功能>`。

## 步骤 6：道具系统（如需）

### 道具定义表

```lua
local POWERUP_DEFS = {
    ammo = {
        sprite = 'item/submachine-gun',
        color = {r = 0.8, g = 0.6, b = 0.2},
        label_key = 'amap.treasure_hunt_pu_ammo_label',
    },
    heal = {
        sprite = 'item/raw-fish',
        color = {r = 0.2, g = 0.8, b = 0.2},
        label_key = 'amap.treasure_hunt_pu_heal_label',
    },
    speed = {
        sprite = 'item/exoskeleton-equipment',
        color = {r = 0.2, g = 0.6, b = 0.8},
        label_key = 'amap.treasure_hunt_pu_speed_label',
    },
}
```

### 道具三层视觉指示

1. **地面光圈**：`rendering.draw_circle` 在道具位置画光圈
2. **物品精灵**：`surface.create_entity({name='item-on-ground', ...})` 放置可见物品
3. **文本标签**：`rendering.draw_text` 显示道具名称

## 步骤 6.5：大批量地形生成（可选）

> 新副本/新世界的 **on_surface_init 里铺大量 tile** 时，用 `utils/terrain_generator.lua` 分帧执行，避免一次性 `set_tiles` 单帧卡顿。

```lua
local TerrainGenerator = require 'utils.terrain_generator'

function M.on_surface_init(data)
    -- 一次性生成 tile 数组（如圆形场地：半径 60 约 1 万块）
    local tiles = {}
    for x = -60, 60 do
        for y = -60, 60 do
            if x * x + y * y <= 60 * 60 then
                tiles[#tiles + 1] = { position = {x = x, y = y}, name = 'grass-1' }
            end
        end
    end
    -- 入队分帧铺放（默认每 tick 32 块），队列持久化，中途存档后继续执行
    TerrainGenerator.enqueue(data.surface, tiles)
end
```

要点：

- `enqueue(surface, tiles, per_tick)`：tile 数组元素形如 `{position = {x = .., y = ..}, name = 'tile-name'}`，per_tick 默认 32
- `is_empty()`：查询队列是否处理完毕（如需在铺完后放实体，可轮询或延迟若干 tick 后判断）
- **注意**：`set_tiles` 要求 chunk 已生成——若目标区域未生成 chunk，需先 `surface.set_chunk_generated_status({x, y}, defines.chunk_generated_status.entities)`（Factorio 2.0 无 `ensure_chunk_generated`）
- 依赖此队列的后续逻辑（围墙/实体/装饰）应在铺放完成后执行

## 步骤 7：验证

1. **加载测试**：无头 Factorio 加载，确认无 Lua 报错
2. **RCON 测试**：`python rcon_driver.py "_TEST.run_all()"`
3. **游戏测试**：进游戏选择新副本，确认：
   - 难度选择 GUI 正常显示
   - 进入后地形、装备正确
   - 胜利/失败条件正确触发
   - 退出后资源正确清理

## 副本实例数据结构

```lua
data = {
    surface = surface,              -- 副本地表
    players = {player_index},       -- 参与玩家列表
    difficulty = 'normal',          -- 难度：easy/normal/hard
    type = 'treasure_hunt',         -- 玩法类型
    time_limit = 300,               -- 时间限制（秒）
    start_tick = game.tick,         -- 开始 tick
    module_data = {},               -- 玩法私有数据（框架不触碰）
    exit_button = LuaGuiElement,    -- 退出按钮
    timer_label = LuaGuiElement,    -- 计时器标签
}
```

## 难度颜色体系

| 难度 | 颜色 | RGB |
|------|------|-----|
| easy | 蓝色 | `{r=0.3, g=0.6, b=1.0}` |
| normal | 紫色 | `{r=0.7, g=0.3, b=1.0}` |
| hard | 橙色 | `{r=1.0, g=0.6, b=0.2}` |

## 审查清单

添加新副本时，对照检查：

- [ ] 文件位于 `maps/amap/instance/modules/` 下
- [ ] 自注册模式：`local M = {}` ... `Instance.register(M.type, M)`
- [ ] 所有必需钩子函数已实现
- [ ] 所有必需元数据字段已定义
- [ ] 难度设置遵循 2~3 条参数改动原则
- [ ] 难度间全难度统一的参数已标注
- [ ] 已在 `dungeon.lua` 中添加 require
- [ ] 中英 locale 已同步添加
- [ ] `module_data` 用于私有数据（非主表）
- [ ] GUI 元素名格式 `dungeon_<缩写>_<功能>`
- [ ] 道具系统三层视觉指示完整（光圈+精灵+标签）
- [ ] 已通过无头加载测试

## 参考

- 副本框架实现：`maps/amap/instance/instance.lua`
- 副本门面：`maps/amap/dungeon.lua`
- 副本奖励：`maps/amap/instance/rewards/builtin.lua`
- 竞技场生存示例：`maps/amap/instance/modules/arena_survival.lua`
- Boss 讨伐示例：`maps/amap/instance/modules/boss_hunt.lua`
- 难度设计指南：[difficulty-design-guide](../difficulty-design-guide/SKILL.md)
- GUI 开发指南：[gui-development-guide](../gui-development-guide/SKILL.md)
