---
name: gui-development-guide
description: 坦克保卫战 GUI 开发指南。规范 GUI 元素名常量、本地化文本、颜色格式、样式设置、难度颜色体系等。在编写、修改或审查任何 Factorio GUI 代码时使用。
---

# 坦克保卫战 GUI 开发指南

## 1. GUI 元素名常量

**所有 GUI 元素名必须定义为局部常量**，禁止内联字符串。

```lua
-- 错误：内联字符串
parent.add({type = 'button', name = 'dungeon_exit_button', caption = '退出'})

-- 正确：局部常量
local GUI_EXIT_BUTTON = 'dungeon_exit_button'
parent.add({type = 'button', name = GUI_EXIT_BUTTON, caption = {'amap.exit_dungeon'}})
```

### 命名格式

| 位置 | 格式 | 示例 |
|------|------|------|
| 副本 GUI | `dungeon_<缩写>_<功能>` | `dungeon_exit_button`, `dungeon_as_wave`, `dungeon_bh_boss_hp` |
| 天赋 GUI | `tianfu_<功能>` | `tianfu_select_frame`, `tianfu_card_button` |
| RPG GUI | `rpg_<功能>` | `rpg_main_frame`, `rpg_level_label` |
| 通用 GUI | `<模块>_<功能>` | `player_list_frame`, `poll_vote_button` |

### 常量定义位置

在模块文件顶部，require 语句之后：

```lua
local Event = require 'utils.event'
local Instance = require 'maps.amap.instance.instance'

-- GUI 元素名常量
local GUI_EXIT_BUTTON = 'dungeon_th_exit'
local GUI_TIMER = 'dungeon_th_timer'
local GUI_CHESTS = 'dungeon_th_chests'
local GUI_DIFFICULTY_FRAME = 'dungeon_th_diff_frame'
```

## 2. 本地化文本

### 格式

Factorio 本地化文本使用**数组形式**：

```lua
-- 无参数
caption = {'amap.exit_dungeon'}

-- 有参数
caption = {'amap.boss_hunt_hp', current_hp, max_hp}

-- 多参数
caption = {'amap.arena_survival_wave', wave_number, total_waves}
```

**禁止**直接写中文/英文字符串：

```lua
-- 错误：硬编码文本
caption = '退出副本'

-- 正确：本地化键
caption = {'amap.exit_dungeon'}
```

### 参数占位

在 locale 文件中使用 `__1__`, `__2__` 等占位符：

```ini
; locale/zh-CN/amap.cfg
boss_hunt_hp=Boss 血量：__1__ / __2__
arena_survival_wave=波次 __1__ / __2__
```

### Rich Text

Factorio Rich Text 标签可直接嵌入 locale 文本：

```ini
; 颜色标签
boss_message=[color=orange]Boss 出现！[/color] 波次 __1__

; GPS 坐标
boss_location=Boss 位置：[gps=__1__,__2__,__3__]

; 物品图标
ammo_info=[item=submachine-gun] 弹药：__1__
```

## 3. 颜色格式

### RGB 表格式

```lua
-- 方式 1：键值表（推荐，可读性好）
local color = {r = 1.0, g = 0.84, b = 0}

-- 方式 2：数组表（简洁）
local color = {1, 0.84, 0}
```

### 预定义颜色

```lua
-- 项目常用颜色
local COLORS = {
    white = {r = 1, g = 1, b = 1},
    black = {r = 0, g = 0, b = 0},
    red = {r = 1, g = 0, b = 0},
    green = {r = 0, g = 1, b = 0},
    blue = {r = 0.3, g = 0.6, b = 1.0},
    purple = {r = 0.7, g = 0.3, b = 1.0},
    orange = {r = 1.0, g = 0.6, b = 0.2},
    gold = {r = 1, g = 0.84, b = 0},
    magenta = {r = 0.6, g = 0.2, b = 1.0},  -- 魔法伤害标识
}
```

### 难度颜色体系

| 难度 | 颜色 | RGB |
|------|------|-----|
| easy | 蓝色 | `{r = 0.3, g = 0.6, b = 1.0}` |
| normal | 紫色 | `{r = 0.7, g = 0.3, b = 1.0}` |
| hard | 橙色 | `{r = 1.0, g = 0.6, b = 0.2}` |

```lua
local DIFFICULTY_COLOR = {
    easy = {r = 0.3, g = 0.6, b = 1.0},
    normal = {r = 0.7, g = 0.3, b = 1.0},
    hard = {r = 1.0, g = 0.6, b = 0.2},
}
```

## 4. 样式设置

### 链式调用

```lua
local label = parent.add({type = 'label', caption = {'amap.wave_info'}})
label.style.font = 'default-bold'
label.style.font_color = {r = 1, g = 0.84, b = 0}
label.style.horizontal_align = 'center'
```

### 常用样式属性

| 属性 | 类型 | 示例 |
|------|------|------|
| `font` | string | `'default-bold'`, `'default-large-bold'`, `'heading-1'` |
| `font_color` | table | `{r = 1, g = 0.84, b = 0}` |
| `horizontal_align` | string | `'left'`, `'center'`, `'right'` |
| `vertical_align` | string | `'top'`, `'center'`, `'bottom'` |
| `width` | number | `200` |
| `height` | number | `40` |
| `minimal_width` | number | `100` |
| `maximal_width` | number | `400` |
| `padding` | number | `4` |
| `left_padding` | number | `8` |
| `right_padding` | number | `8` |

## 5. GUI 创建模式

### 副本顶栏

```lua
local function create_top_bar(player, data)
    local screen = player.gui.screen
    local name = 'dungeon_top_frame'

    -- 清理已有
    if screen[name] then screen[name].destroy() end

    local frame = screen.add({
        type = 'frame',
        name = name,
        direction = 'horizontal',
    })
    frame.style.padding = 4

    -- 退出按钮
    frame.add({
        type = 'button',
        name = GUI_EXIT_BUTTON,
        caption = {'amap.exit_dungeon'},
        style = 'back_button',
    })

    -- 计时器
    local timer = frame.add({
        type = 'label',
        name = GUI_TIMER,
        caption = {'amap.time_remaining', data.time_limit},
    })
    timer.style.font = 'default-bold'
    timer.style.font_color = {r = 1, g = 1, b = 1}

    -- 保存引用到 data
    data.timer_label = timer

    return frame
end
```

### 难度选择卡片

```lua
local function create_difficulty_card(parent, difficulty, instance_type)
    local color = DIFFICULTY_COLOR[difficulty]
    local card = parent.add({type = 'frame', direction = 'vertical'})
    card.style.padding = 8

    -- 标题
    local title = card.add({
        type = 'label',
        caption = {'amap.dungeon_difficulty_title', {'amap.' .. difficulty}},
    })
    title.style.font = 'default-bold'
    title.style.font_color = color

    -- 图标按钮
    card.add({
        type = 'button',
        name = 'dungeon_diff_' .. difficulty .. '_' .. instance_type,
        caption = {'amap.enter_dungeon'},
        style = 'confirm_button',
    })

    -- 玩法描述
    card.add({
        type = 'label',
        caption = {'amap.' .. instance_type .. '_gameplay'},
        style = 'description_label',
    })

    return card
end
```

### 选项缓存

玩家关掉 GUI 重开时，选项应保持不变：

```lua
-- 使用缓存表
local epic_chest_options_cache = {}

local function get_options(player_index, cache_key)
    if epic_chest_options_cache[cache_key] then
        return epic_chest_options_cache[cache_key]
    end
    -- 生成选项...
    epic_chest_options_cache[cache_key] = options
    return options
end
```

## 6. GUI 事件处理

### 标准模式

```lua
local function on_gui_click(event)
    local player = game.get_player(event.player_index)
    if not player or not player.valid then return end

    local element = event.element
    if not element or not element.valid then return end

    local name = element.name

    -- 元素名分派
    if name == GUI_EXIT_BUTTON then
        handle_exit(player)
    elseif name == GUI_DIFFICULTY_EASY then
        handle_difficulty_select(player, 'easy')
    elseif name == GUI_DIFFICULTY_NORMAL then
        handle_difficulty_select(player, 'normal')
    elseif name == GUI_DIFFICULTY_HARD then
        handle_difficulty_select(player, 'hard')
    end
end
Event.add(defines.events.on_gui_click, on_gui_click)
```

### GUI 清理

```lua
local function destroy_gui(player)
    local screen = player.gui.screen
    if screen['dungeon_top_frame'] then
        screen['dungeon_top_frame'].destroy()
    end
end
```

**注意**：玩家离开副本、重置场景时必须清理 GUI，否则残留 GUI 会导致报错。

## 审查清单

编写或修改 GUI 代码时，对照检查：

- [ ] GUI 元素名是否定义为局部常量（非内联字符串）
- [ ] 元素名格式是否遵循 `dungeon_<缩写>_<功能>` 等约定
- [ ] 文本是否使用本地化键（`{'amap.xxx'}`）而非硬编码字符串
- [ ] 颜色是否使用标准 RGB 格式
- [ ] 难度颜色是否使用统一体系（蓝/紫/橙）
- [ ] GUI 事件处理是否做了 player/element valid 检查
- [ ] GUI 事件处理是否做了元素名分派
- [ ] 副本退出时是否清理了 GUI
- [ ] 选项缓存是否正确实现（防止重开刷新）

## 参考

- 副本框架 GUI：`maps/amap/instance/instance.lua`
- 天赋 GUI：`maps/amap/tianfu.lua`
- RPG GUI：`modules/rpg/gui.lua`
- 商店 GUI：`maps/amap/market_gui.lua`
- Locale 指南：[locale-i18n-guide](../locale-i18n-guide/SKILL.md)
