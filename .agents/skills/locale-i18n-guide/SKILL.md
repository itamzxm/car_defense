---
name: locale-i18n-guide
description: 坦克保卫战本地化/国际化指南。规范 locale 键命名、中英同步、参数占位、Rich text、文件编码等。在添加、修改或审查任何玩家可见文本时使用。
---

# 坦克保卫战本地化/国际化指南

## 核心规则

**所有文本修改必须同步中英文 locale 文件。**

## 1. 文件结构

```
locale/
├── en/                    -- 英文
│   ├── amap.cfg          -- 项目主文本（仅 [amap] section）
│   ├── icw.cfg            -- 关联箱系统（[icw]）
│   ├── magic_wood.cfg     -- 魔法木箱系统（[magic_wood]）
│   ├── commands.cfg      -- 命令文本
│   ├── gui.cfg            -- GUI 设置文本
│   ├── ic.cfg             -- 载具内部空间文本
│   ├── locale.cfg        -- Factorio 内置模块文本
│   ├── modules.cfg        -- 通用模块文本
│   ├── pet_system.cfg    -- 宠物系统文本
│   ├── rpg.cfg           -- RPG 系统文本
│   └── tianfu.cfg        -- 天赋系统文本
└── zh-CN/                -- 中文
    ├── amap.cfg          -- 项目主文本（仅 [amap] section）
    ├── icw.cfg            -- 关联箱系统（[icw]）
    ├── magic_wood.cfg     -- 魔法木箱系统（[magic_wood]）
    ├── commands.cfg      -- 命令文本
    ├── gui.cfg            -- GUI 设置文本
    ├── ic.cfg             -- 载具7内部空间文本
    ├── locale.cfg        -- Factorio 内置模块文本
    ├── modules.cfg        -- 通用模块文本
    ├── pet_system.cfg    -- 宠物系统文本
    ├── rpg.cfg           -- RPG 系统文本
    └── tianfu.cfg        -- 天赋系统文本
```

### 主要工作文件

- `locale/zh-CN/amap.cfg` — 中文项目文本
- `locale/en/amap.cfg` — 英文项目文本

## 文件组织原则

| 原则 | 说明 |
|------|------|
| **一文件一 section** | 文件名与 section 名对应，如 `icw.cfg` 只含 `[icw]` |
| **禁止多 section 混杂** | 不要把不相关的 section 塞在同一文件（`[icw]`、`[magic_wood]` 已从 `amap.cfg` 拆分） |
| **禁止追加到文件末尾** | 新增键必须放在对应 section 内，不能直接追加到文件末尾（会导致键名前缀错误） |
| **按功能域分组注释** | 新增键前用 `# ── 功能域名 ──` 注释标明分组 |
| **多 section 文件声明** | 若文件确需多 section，开头必须注释声明所有 section 名称 |

### 分组注释格式

```ini
[amap]
...
# ── 顶栏按钮 ──
top_bar_hide=点击折叠顶栏
top_bar_show=点击展开顶栏
# ── 小地图 ──
minimap_toggle=打开或关闭小地图。
minimap_frame_title=小地图
...
```

## 2. locale 文件格式

Factorio locale 文件使用 INI 风格格式：

```ini
[section_name]
key1=value1
key2=value2
key3=带参数的文本 __1__ 和 __2__
```

### 项目统一 section

项目自定义文本统一使用 `[amap]` section：

```ini
[amap]
exit_dungeon=退出副本
dungeon_difficulty_title=__1__ 难度
boss_hunt_hp=Boss 血量：__1__ / __2__
```

## 3. 键名命名规范

### 格式

```
amap.<功能域>_<描述>
```

### 功能域前缀

| 功能域 | 前缀 | 示例 |
|--------|------|------|
| 天赋 | `talent_` / `tianfu_` | `amap.talent_category_mage`, `amap.tianfu_select_title` |
| 副本 | `instance_` / `dungeon_` | `amap.instance_arena_survival_name`, `amap.dungeon_difficulty_title` |
| 副本玩法 | `<玩法名>_` | `amap.arena_survival_pu_ammo`, `amap.boss_hunt_hp` |
| 世界 | `world<数字>_` | `amap.world15_boss_spawn`, `amap.world15_build_restricted` |
| 道具 | `pu_<类型>` | `amap.arena_survival_pu_ammo`, `amap.arena_survival_pu_heal` |
| 通用 | 无特定前缀 | `amap.exit_dungeon`, `amap.time_remaining` |

### 命名规则

- 全部 `snake_case`
- 功能域前缀 + 描述性名称
- 同一功能的多个相关键使用相同前缀

```ini
; 好的命名：前缀一致
instance_arena_survival_name=竞技场生存
instance_arena_survival_desc=在封闭场地中生存指定波次
instance_arena_survival_gameplay=4方向随机出怪...
instance_arena_survival_victory=存活所有波次即可通关

; 坏的命名：前缀不一致
arena_name=竞技场生存
survival_desc=在封闭场地中生存指定波次
as_gameplay=4方向随机出怪...
```

## 4. 参数占位

使用 `__N__` 格式（N 从 1 开始）：

```ini
; 单参数
time_remaining=剩余时间：__1__秒

; 双参数
boss_hunt_hp=Boss 血量：__1__ / __2__

; 三参数
boss_spawn=[color=orange]Boss 出现！[/color] 波次 __1__，血量 __2__，位置 [gps=__3__,__4__,nauvis]
```

### Lua 中传参

```lua
-- 单参数
caption = {'amap.time_remaining', seconds}

-- 双参数
caption = {'amap.boss_hunt_hp', current_hp, max_hp}

-- 多参数
caption = {'amap.boss_spawn', wave, hp, x, y}
```

## 5. Rich Text 标签

Factorio 支持的 Rich Text 标签：

| 标签 | 格式 | 示例 |
|------|------|------|
| 颜色 | `[color=R,G,B]...[/color]` 或 `[color=name]...[/color]` | `[color=orange]Boss[/color]` |
| 物品图标 | `[item=name]` | `[item=submachine-gun]` |
| 实体图标 | `[entity=name]` | `[entity/big-biter]` |
| 科技图标 | `[technology=name]` | `[technology=laser]` |
| GPS 坐标 | `[gps=x,y,surface]` | `[gps=100,200,nauvis]` |
| 控制标签 | `[img=name]` | `[img=utility/check_mark]` |

### 在 locale 中使用

```ini
boss_message=[color=orange]Boss 波次 __1__[/color] - - [color=red]__2__[/color]
ammo_info=[item=submachine-gun] 弹药：__1__
boss_location=Boss 位置：[gps=__1__,__2__,__3__]
```

## 6. 中英同步流程

### 添加新文本

1. 确定键属于哪个 section/文件（如 `[amap]`→`amap.cfg`、`[icw]`→`icw.cfg`、`[commands]`→`commands.cfg`）
2. 在对应文件的对应 section 内添加键值对（**禁止追加到文件末尾**）
3. 若为新功能域，在键前添加 `# ── 功能域名 ──` 分组注释
4. 在中英两个文件中同步添加
5. 确保键名完全一致
6. 确保参数占位符数量和顺序一致

### 修改已有文本

1. 修改中文 locale 中的值
2. **同步修改**英文 locale 中对应键的值
3. 确保参数占位符数量和顺序一致

### 删除文本

1. 从中文 locale 中删除键值对
2. **同步从**英文 locale 中删除对应键值对
3. 确认代码中不再引用该键

## 7. 文件编码

| 规则 | 说明 |
|------|------|
| 中文 locale 文件 | **必须 UTF-8 编码** |
| 英文 locale 文件 | UTF-8 或 ASCII |
| 禁止 PowerShell `Set-Content` | 会导致中文乱码 |
| 正确做法 | 使用 `edit` 工具逐行修改 |

### 编码验证

如果游戏中出现 `unfinished string` 错误，通常是 locale 文件编码问题：
1. 检查文件是否为 UTF-8
2. 检查是否有 BOM 标记（Factorio 不接受 BOM）
3. 检查是否有损坏的中文字符

## 8. 特殊情况

### 非项目文本

`locale/zh-CN/locale.cfg` 和 `locale/en/locale.cfg` 中包含 Factorio 内置模块的文本（biter_battles, cave_miner 等），这些**不是项目自定义文本**，修改时需谨慎。

### 独立模块 locale

某些模块有独立的 locale 文件：

| 文件 | 模块 |
|------|------|
| `rpg.cfg` | RPG 系统 |
| `pet_system.cfg` | 宠物系统 |
| `tianfu.cfg` | 天赋系统 |
| `commands.cfg` | 命令系统 |

这些文件的中英文也需要同步维护。

## 审查清单

添加或修改 locale 文本时，对照检查：

- [ ] 键名格式是否为 `amap.<功能域>_<描述>`（snake_case）
- [ ] 中文和英文 locale 是否已同步添加/修改
- [ ] 参数占位符 `__N__` 数量和顺序在中英文间是否一致
- [ ] Rich Text 标签语法是否正确
- [ ] 文件编码是否为 UTF-8（无 BOM）
- [ ] 是否使用 `edit` 工具修改（而非 PowerShell Set-Content）
- [ ] 代码中引用的 locale 键是否与文件中定义的一致
- [ ] 新键是否放在正确的 section 和文件中（而非文件末尾）
- [ ] 新功能域是否添加了 `# ── 功能域名 ──` 分组注释

## 参考

- 中文主 locale：`locale/zh-CN/amap.cfg`
- 英文主 locale：`locale/en/amap.cfg`
- 天赋 locale：`locale/zh-CN/tianfu.cfg` / `locale/en/tianfu.cfg`
- RPG locale：`locale/zh-CN/rpg.cfg` / `locale/en/rpg.cfg`
- Factorio Locale 文档：https://wiki.factorio.com/Locale
