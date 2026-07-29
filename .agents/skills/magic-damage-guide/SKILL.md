---
name: magic-damage-guide
description: 坦克保卫战魔法伤害计算指南。规范魔法技能/天赋的伤害计算必须纳入科技加成和品质系数，以及作用范围上限 24 米。在编写、修改或审查任何魔法类伤害代码时使用。
---

# 坦克保卫战魔法伤害计算指南

## 适用范围

**所有「魔法术类」造成的直接伤害** —— 即魔法技能、魔法天赋、法术类伤害。

**不适用**：非魔法类的物理/爆炸等伤害。

## 强制要求

任何魔法伤害天赋/技能在计算伤害时，必须纳入以下二项影响，**缺一不可**：

### 1. 科技加成

使用玩家阵营的激光弹药伤害修正和射击速度修正：

```lua
local force = game.forces.player
local damage_modifier = force.get_ammo_damage_modifier("laser") + 1
local speed_modifier = force.get_gun_speed_modifier('laser') + 1
```

- `get_ammo_damage_modifier("laser")` 返回的是**增量**（如 0.5 表示 +50%），需要 +1 转为乘数
- `get_gun_speed_modifier('laser')` 同理

### 2. 品质系数

使用品质系数表，根据天赋/技能的品质等级取值：

```lua
local COEFF_REG = {1, 1.2, 1.4, 1.6, 1.8}
-- 索引：1=普通, 2=精良, 3=稀有, 4=史诗, 5=传说
```

品质等级获取方式取决于具体实现，通常通过天赋表的品质字段或 RPG 品质系统获取。

### 最终伤害公式

```lua
local final_damage = base_damage * damage_modifier / speed_modifier * quality_coeff
```

**注意**：`speed_modifier` 在分母位置——射速越快，单次伤害越低（与 Factorio 原版 DPS 计算一致）。

## 完整实现示例

### 单体魔法伤害

```lua
local COEFF_REG = {1, 1.2, 1.4, 1.6, 1.8}

local function calc_magic_damage(base_damage, quality_index)
    local force = game.forces.player
    local damage_modifier = force.get_ammo_damage_modifier("laser") + 1
    local speed_modifier = force.get_gun_speed_modifier('laser') + 1
    local quality_coeff = COEFF_REG[quality_index] or 1

    return base_damage * damage_modifier / speed_modifier * quality_coeff
end

local function apply_magic_damage(entity, base_damage, quality_index)
    if not entity or not entity.valid then return end

    local final_damage = calc_magic_damage(base_damage, quality_index)

    -- 作用范围上限 24 米（调用方应已确保，此处做防御性检查）
    -- 注意：此函数不处理范围检查，调用方负责

    entity.damage(final_damage, 'player', 'laser')
end
```

### AoE 魔法伤害

```lua
local COEFF_REG = {1, 1.2, 1.4, 1.6, 1.8}
local MAGIC_MAX_RANGE = 24

local function apply_aoe_magic(center, base_damage, quality_index, radius)
    -- 作用范围上限
    radius = math.min(radius, MAGIC_MAX_RANGE)

    local force = game.forces.player
    local damage_modifier = force.get_ammo_damage_modifier("laser") + 1
    local speed_modifier = force.get_gun_speed_modifier('laser') + 1
    local quality_coeff = COEFF_REG[quality_index] or 1

    local final_damage = base_damage * damage_modifier / speed_modifier * quality_coeff

    local surface = center.surface or game.surfaces.nauvis
    local enemies = surface.find_entities_filtered({
        position = center,
        radius = radius,
        force = 'enemy',
    })

    for _, enemy in ipairs(enemies) do
        if enemy.valid and enemy.health then
            enemy.damage(final_damage, 'player', 'laser')
        end
    end
end
```

### 魔法伤害浮动文本

```lua
local function show_damage_text(player, position, damage)
    player.create_local_flying_text({
        text = '✦' .. math.floor(damage),
        position = position,
        color = {r = 0.6, g = 0.2, b = 1.0},  -- 紫色，魔法伤害标识
        time_to_live = 60,
    })
end
```

## 作用范围上限 24 米

**任何魔法技能、天赋的作用范围，最大有效值就是 24 米。**

### 规则

- 若计算或配置出的范围超过 24 米，一律按 24 米处理
- 代码中相关数值只能写 `24`，不得写更大的数
- **非魔法技能，或者天赋，不受这个限制约束**

```lua
-- 错误：魔法技能范围超过 24
local MAGIC_RANGE = 30

-- 正确：魔法技能范围上限 24
local MAGIC_MAX_RANGE = 24
local effective_range = math.min(calculated_range, MAGIC_MAX_RANGE)

-- 正确：非魔法技能不受此限
local PHYSICAL_RANGE = 50  -- 物理技能可以超过 24
```

## 品质系数表

| 品质 | 索引 | 系数 | 说明 |
|------|------|------|------|
| 普通 | 1 | 1.0 | 基础伤害 |
| 精良 | 2 | 1.2 | +20% |
| 稀有 | 3 | 1.4 | +40% |
| 史诗 | 4 | 1.6 | +60% |
| 传说 | 5 | 1.8 | +80% |

**注意**：品质系数表 `COEFF_REG = {1, 1.2, 1.4, 1.6, 1.8}` 是项目约定，不得自行定义其他数值。

## 二项影响的纳入方式

二项影响的具体纳入方式由各天赋自身设计决定，例如：

| 设计选择 | 说明 |
|---------|------|
| 科技加成影响基础伤害 | `damage_modifier / speed_modifier` 直接乘进每道伤害 |
| 科技加成影响命中道数 | 总道数 = 基础道数 × damage_modifier，每道伤害不变 |
| 品质系数影响基础伤害 | `quality_coeff` 直接乘进每道伤害 |
| 品质系数影响范围 | 范围 = 基础范围 × quality_coeff（仍受 24 米上限） |
| 品质系数影响持续时间 | 持续时间 = 基础时间 × quality_coeff |

**无论选择哪种纳入方式，两项都必须存在**，不能只纳入一项。

## 常见错误

### 错误 1：遗漏科技加成

```lua
-- 错误：直接用基础伤害
entity.damage(base_damage * quality_coeff, 'player', 'laser')

-- 正确：纳入科技加成
local damage_modifier = game.forces.player.get_ammo_damage_modifier("laser") + 1
local speed_modifier = game.forces.player.get_gun_speed_modifier('laser') + 1
entity.damage(base_damage * damage_modifier / speed_modifier * quality_coeff, 'player', 'laser')
```

### 错误 2：遗漏品质系数

```lua
-- 错误：只用了科技加成
local final = base_damage * damage_modifier / speed_modifier

-- 正确：同时纳入品质系数
local final = base_damage * damage_modifier / speed_modifier * quality_coeff
```

### 错误 3：范围超过 24 米

```lua
-- 错误：范围无上限
local radius = base_radius * quality_coeff  -- 可能 > 24

-- 正确：范围上限 24
local MAGIC_MAX_RANGE = 24
local radius = math.min(base_radius * quality_coeff, MAGIC_MAX_RANGE)
```

## 审查清单

编写或审查魔法伤害代码时，对照检查：

- [ ] 伤害计算是否纳入了科技加成（`get_ammo_damage_modifier("laser")` + `get_gun_speed_modifier('laser')`）
- [ ] 伤害计算是否纳入了品质系数（`COEFF_REG[q_idx]`）
- [ ] 品质系数表是否使用项目约定 `{1, 1.2, 1.4, 1.6, 1.8}`
- [ ] 魔法作用范围是否 ≤ 24 米（`math.min(range, 24)`）
- [ ] 代码中范围相关数值是否只写 `24`（不写更大的数）
- [ ] 非魔法伤害是否未误用本规则
- [ ] 伤害浮动文本是否使用 `player.create_local_flying_text()`

## 参考

- 天赋系统：`maps/amap/tianfu.lua`
- 天赋触发技能：`maps/amap/tianfu_trigger_skill.lua`
- 天赋品质系统：`maps/amap/tianfu_quality.lua`
- 魔法技能增加说明：`魔法技能增加说明.md`
- 项目核心规则：`CLAUDE.md`（魔法技能/天赋伤害规则章节）
