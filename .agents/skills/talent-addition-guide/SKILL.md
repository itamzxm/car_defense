---
name: talent-addition-guide
description: 坦克保卫战新天赋添加指南。提供从零开始添加一个新天赋的完整步骤，包括4池分类、ID命名、图标映射、黑名单、魔法伤害规则、作用范围上限、品质系数等。在添加新天赋或修改已有天赋定义时使用。
---

# 坦克保卫战新天赋添加指南

## 前置知识

- 天赋系统有 **4 个天赋池**：战士（fighter）、建筑（builder）、法师（mage）、其他（other）
- 天赋 ID 主要使用**中文拼音缩写**
- 魔法类天赋必须纳入**科技加成 + 品质系数**
- 魔法类天赋作用范围上限 **24 米**

## 步骤 1：确定天赋分类

每个天赋**必须**归入以下 4 个天赋池中的一类：

| 池子 | 英文键 | 适用范围 |
|------|--------|---------|
| 战士 | `fighter` | 战斗/生存向，偏肉偏伤 |
| 建筑 | `builder` | 建造/生产/资源向 |
| 法师 | `mage` | 魔法术类伤害/法力向 |
| 其他 | `other` | 不属于以上三类 |

**强制要求**：若分析后无法清晰匹配到战士/建筑/法师中的任何一类，**默认归入「其他」**，不得强行塞入不合适的池子。

## 步骤 2：确定天赋 ID

### 命名规则

- 主要使用**中文拼音缩写**（2~4 字符）
- 少数可用英文（如 `'fish'`, `'wolf'`, `'boom_player'`）
- ID 必须全局唯一

### 示例

| 天赋名 | ID | 池子 |
|--------|-----|------|
| 鱼灵 | `'yl'` | fighter |
| 魔力之泉 | `'mlzq'` | mage |
| 黑魔导师 | `'hmds'` | mage |
| 雷霆万钧 | `'leitingwanjun'` | mage |
| 建造者 | `'builder'` | builder |
| 狼 | `'wolf'` | fighter |

## 步骤 3：在 tianfu.lua 中添加天赋定义

### 天赋分类注册

在 `maps/amap/tianfu.lua` 的 `tianfu_categories` 表中添加：

```lua
local tianfu_categories = {
    mage = {
        'mlzq', 'hmds', 'leitingwanjun', 'new_talent_id',
    },
    builder = {
        'builder',
    },
    fighter = {
        'yl', 'wolf', 'fish',
    },
    other = {
        -- 其他天赋
    },
}
```

### 图标映射

在 `tianfu_icons` 表中添加图标：

```lua
local tianfu_icons = {
    ['new_talent_id'] = 'item/submachine-gun',  -- 内置原型
    -- 或
    ['new_talent_id'] = 'file/png/tianfu/new_talent.png',  -- 本地 PNG
}
```

图标来源优先级：
1. Factorio 内置原型：`'item/xxx'`, `'entity/xxx'`, `'technology/xxx'`
2. 本地 PNG 文件：`'file/png/tianfu/xxx.png'`（放在 `png/tianfu/` 目录下）

## 步骤 4：实现天赋逻辑

根据天赋类型，在对应的子模块中实现：

| 天赋类型 | 实现文件 | 说明 |
|---------|---------|------|
| 触发型 | `tianfu_trigger_skill.lua` | 事件触发（击杀、受伤等） |
| 时间型 | `tianfu_time_skill.lua` | 周期性触发（on_tick / on_nth_tick） |
| 一次性 | `tianfu_once_skill.lua` | 学习时立即生效（属性加成等） |

### 魔法伤害天赋必须纳入的二项影响

**适用范围**：所有「魔法术类」造成的直接伤害。非魔法类的物理/爆炸等伤害不适用。

#### 1. 科技加成

```lua
local force = game.forces.player
local damage_modifier = force.get_ammo_damage_modifier("laser") + 1
local speed_modifier = force.get_gun_speed_modifier('laser') + 1
```

#### 2. 品质系数

```lua
local COEFF_REG = {1, 1.2, 1.4, 1.6, 1.8}  -- 普通/精良/稀有/史诗/传说
local q_idx = quality_index  -- 1=普通, 2=精良, 3=稀有, 4=史诗, 5=传说
local quality_coeff = COEFF_REG[q_idx]
```

#### 最终伤害公式

```lua
local final_damage = base_damage * damage_modifier / speed_modifier * quality_coeff
```

**注意**：二项影响的具体纳入方式（如魔力是叠加进基础伤害还是影响命中道数、目标选择是单体还是 AoE 等）由各天赋自身设计决定。

### 作用范围上限

```lua
-- 错误：魔法天赋范围超过 24
local range = calculated_range  -- 可能 > 24

-- 正确：魔法天赋范围上限 24
local range = math.min(calculated_range, 24)

-- 更正确：直接在配置中写 24
local MAGIC_MAX_RANGE = 24
local range = math.min(calculated_range, MAGIC_MAX_RANGE)
```

## 步骤 5：添加黑名单（如需）

### 全局黑名单

在 `maps/amap/tianfu_blacklist.json` 中添加（JSON 数组）：

```json
["new_talent_id"]
```

### 世界级禁用

在世界定义的 `disabled_talents` 字段中添加：

```lua
World.register(world_id, {
    -- ...
    disabled_talents = {'new_talent_id'},
})
```

## 步骤 6：添加 locale 文本

### 中文 locale（`locale/zh-CN/tianfu.cfg` 或 `amap.cfg`）

```ini
talent_new_talent_name=新天赋名
talent_new_talent_desc=新天赋的描述文本
talent_new_talent_tooltip=新天赋的详细说明
```

### 英文 locale（`locale/en/tianfu.cfg` 或 `amap.cfg`）

```ini
talent_new_talent_name=New Talent Name
talent_new_talent_desc=Description of the new talent
talent_new_talent_tooltip=Detailed explanation of the new talent
```

**键名格式**：`talent_<天赋ID>_<功能>` 或 `tianfu_<天赋ID>_<功能>`。

## 步骤 7：添加天赋数据表字段（如需）

如果天赋需要持久化数据，在 `maps/amap/tianfu_table.lua` 的 `reset_table` 中添加：

```lua
function Public.reset_table()
    -- 已有字段...
    this.new_talent_data = {}
end
```

并考虑是否需要倒排索引或 tick 分桶调度（参见 [global-data-guide](../global-data-guide/SKILL.md)）。

## 步骤 8：验证

1. **加载测试**：无头 Factorio 加载，确认无 Lua 报错
2. **游戏测试**：
   - 天赋在 GUI 中正确显示（名称、图标、分类）
   - 学习/启用逻辑正确
   - 天赋效果正确触发
   - 魔法伤害包含科技加成和品质系数
   - 作用范围不超过 24 米
   - 黑名单正确生效

## 天赋分类归属速查

| 天赋特征 | 归属池 |
|---------|--------|
| 增加生命/护甲/闪避 | fighter |
| 增加近战/远程物理伤害 | fighter |
| 击杀回血/吸血 | fighter |
| 增加建造速度/范围 | builder |
| 增加采矿/生产效率 | builder |
| 资源产出加成 | builder |
| 激光/魔力/法术伤害 | mage |
| 法力回复/法力上限 | mage |
| AoE 魔法效果 | mage |
| 移动速度加成 | other |
| 视野/雷达效果 | other |
| 特殊机制（非战斗/建造/魔法） | other |

## 审查清单

添加新天赋时，对照检查：

- [ ] 天赋已归入 4 池之一（无法匹配时默认 other）
- [ ] 天赋 ID 全局唯一，命名遵循拼音缩写规则
- [ ] 图标已添加到 `tianfu_icons`（内置原型或本地 PNG）
- [ ] 天赋逻辑在正确的子模块中实现（trigger/time/once）
- [ ] 魔法类天赋已纳入科技加成（laser modifier）+ 品质系数（COEFF_REG）
- [ ] 魔法类天赋作用范围 ≤ 24 米
- [ ] 黑名单已配置（全局或世界级，如需）
- [ ] 中英 locale 已同步添加
- [ ] 持久化数据已添加到 tianfu_table（如需）
- [ ] 已通过加载测试和游戏测试

## 参考

- 天赋系统主文件：`maps/amap/tianfu.lua`
- 天赋数据表：`maps/amap/tianfu_table.lua`
- 天赋触发技能：`maps/amap/tianfu_trigger_skill.lua`
- 天赋时间技能：`maps/amap/tianfu_time_skill.lua`
- 天赋一次性技能：`maps/amap/tianfu_once_skill.lua`
- 天赋品质系统：`maps/amap/tianfu_quality.lua`
- 天赋黑名单：`maps/amap/tianfu_blacklist.json`
- 魔法伤害指南：[magic-damage-guide](../magic-damage-guide/SKILL.md)
- 全局数据指南：[global-data-guide](../global-data-guide/SKILL.md)
