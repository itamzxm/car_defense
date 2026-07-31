---
name: gui-development-guide
description: 坦克保卫战 GUI 开发指南。规范 GuiDispatcher 事件派发、TopBar 顶栏按钮、GuiRebuild 热更重建、gui_styles 颜色样式集中定义、GUI 元素名常量、本地化文本、add_main_frame_with_toolbar 工具函数等。在编写、修改或审查任何 Factorio GUI 代码时使用。
---

# 坦克保卫战 GUI 开发指南

## 1. GUI 事件派发（GuiDispatcher）

**所有 GUI 事件通过 `utils/gui_dispatcher.lua` 注册，取代旧的 `Gui.on_click` / `Event.add(on_gui_*)`。**

### 注册 API

```lua
local GuiDispatcher = require 'utils.gui_dispatcher'

-- 按元素名注册 handler：该元素被点击时自动派发
GuiDispatcher.register_click(element_name, handler)

-- 其他事件类型
GuiDispatcher.register_text_changed(element_name, handler)
GuiDispatcher.register_selection_state_changed(element_name, handler)
GuiDispatcher.register_checked_state_changed(element_name, handler)
GuiDispatcher.register_closed(element_name, handler)
GuiDispatcher.register_value_changed(element_name, handler)
GuiDispatcher.register_elem_changed(element_name, handler)
```

### 运行时禁止注册（desync 防护）

所有 `register_*` 函数在 `_LIFECYCLE == 8`（Runtime）时抛错。**必须在模块加载期（顶层 require 阶段）注册，不能在 on_init / 运行时注册。**

```lua
-- ❌ 禁止：运行时注册（desync 风险）
Event.add(defines.events.on_player_joined_game, function(event)
    GuiDispatcher.register_click('my_button', handler)  -- 运行时调用，会抛错
end)

-- ✅ 正确：模块加载期注册
GuiDispatcher.register_click(GUI_MY_BUTTON, function(event)
    local player = event.player
    -- handler 逻辑
end)
```

### 派发原理

GuiDispatcher 内部维护 `handlers[element_name] = handler` 表，统一注册一个 `on_gui_click` handler，按 `event.element.name` 查表派发。handler 内无需再做元素名 if-elseif 分派，也无需做 player/element valid 检查（派发器已处理）。

```lua
-- 旧模式（已废弃）：手写 on_gui_click + 元素名分派
local function on_gui_click(event)
    local player = game.get_player(event.player_index)
    if not player or not player.valid then return end
    local element = event.element
    if not element or not element.valid then return end
    if element.name == GUI_EXIT_BUTTON then
        handle_exit(player)
    elseif element.name == GUI_DIFF_BUTTON then
        handle_diff(player)
    end
end
Event.add(defines.events.on_gui_click, on_gui_click)

-- 新模式（推荐）：GuiDispatcher 按元素名注册
GuiDispatcher.register_click(GUI_EXIT_BUTTON, function(event)
    handle_exit(event.player)
end)
GuiDispatcher.register_click(GUI_DIFF_BUTTON, function(event)
    handle_diff(event.player)
end)
```

## 2. 顶栏按钮（TopBar）

**顶栏按钮通过 `utils/top_bar.lua` 统一管理，使用 `mod_gui.get_button_flow`，禁止直接 `player.gui.top.add`。**

### 添加按钮

```lua
local TopBar = require 'utils.top_bar'

local element = TopBar.add_button(player, {
    type = 'sprite-button',
    name = GUI_MY_BUTTON,
    sprite = 'item/submachine-gun',
    tooltip = {'amap.my_button_tooltip'},
})
```

- `TopBar.add_button` 自动应用统一样式（`mod_gui_button`，高 36）
- 若折叠状态下且按钮不在 `ALWAYS_VISIBLE_BUTTONS` 中，自动隐藏
- 已存在同名按钮会先销毁再创建

### 折叠/展开

顶栏提供折叠开关按钮（`top_bar_toggle_button`），点击切换所有非始终可见按钮的显隐。`ALWAYS_VISIBLE_BUTTONS`（如 RPG/宠物/天赋主按钮）不受折叠影响。

### 按钮排序（TOP_BUTTON_ORDER）

按钮顺序由 `utils/top_button_order.lua` 的 `TOP_BUTTON_ORDER` 顺序表统一管理。新增顶栏按钮时**必须**在此表中登记顺序：

```lua
-- utils/top_button_order.lua
local TOP_BUTTON_ORDER = {
    TopBar.get_toggle_button_name(),
    'comfy_panel_top_button',
    'cp_poll_main_button',
    'rpg_draw_main_frame',
    'pet_draw_main_button',
    'tianfu',
    'amap_vote_poll_button',
    'amap_main_button',
    'charging_station',
    'cmd_misc_clear_corpse_button',
    'auto_stash',
    'amap_main_frame',
    'ic_integration_button',
    'minimap_button',
}
```

未登记的按钮排到末尾。排序在 `on_player_joined_game` 和底栏快捷栏位置变更时触发。

## 3. GUI 热更重建（GuiRebuild）

**各 GUI 模块通过 `utils/gui_rebuild.lua` 注册"清理 + 重建"函数，场景热更 / 存档兼容时统一重建所有在线玩家 GUI。**

### 背景

旧 GUI 的清理与重建只挂在 `on_player_joined_game`。场景脚本热更（开发者改完代码 reload、服务器不重启直接更新场景）时，旧代码构建的 GUI 元素不会消失，新代码又只在玩家"重新加入"时才清理重建，导致热更后首次开 GUI 出现"旧帧残留 + 新帧叠加"双帧冲突。

### 注册重建函数

```lua
local GuiRebuild = require 'utils.gui_rebuild'

-- 在模块加载期注册：清理旧元素 + 创建新按钮/帧
GuiRebuild.register('my_module_gui', function(player)
    -- 1. 清理旧元素
    local flow = TopBar.get_button_flow(player)
    if flow[GUI_MY_BUTTON] then flow[GUI_MY_BUTTON].destroy() end
    -- 2. 重新创建
    TopBar.add_button(player, {type = 'sprite-button', name = GUI_MY_BUTTON, ...})
end)
```

- `on_configuration_changed` 时自动对所有在线玩家调用所有已注册重建函数（pcall 隔离单模块失败）
- `/reload-ui` 调试命令：开发者热更后手动重建自己的 GUI（需管理员，错误直接抛出便于定位）

### 注意

GuiRebuild 只销毁/重建**元素**，不调用 `GuiDispatcher.register_*`（事件注册必须在 require 阶段完成，受 `_LIFECYCLE==8` 守卫保护）。

## 4. GUI 元素名常量

**所有 GUI 元素名必须定义为局部常量**，禁止内联字符串。

```lua
-- ❌ 错误：内联字符串
parent.add({type = 'button', name = 'dungeon_exit_button', caption = '退出'})

-- ✅ 正确：局部常量
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

## 5. 颜色与样式（gui_styles.lua）

**颜色/样式集中定义在 `maps/amap/gui_styles.lua`，禁止内联 RGB 散落各处。**

### 引用集中定义

```lua
local Styles = require 'maps.amap.gui_styles'

-- 难度颜色
local color = Styles.DIFFICULTY_COLOR[difficulty]  -- easy/normal/hard

-- 品质颜色
local q_color = Styles.QUALITY_COLOR[quality_index]  -- 1~5

-- 通用颜色
local red = Styles.COLORS.RED
local gold = Styles.GUI_COLOR.GOLD

-- 批量应用样式
Styles.apply_style(label, {font = 'default-bold', font_color = Styles.GUI_COLOR.GOLD})
```

### 已有定义

| 表 | 用途 | 示例键 |
|------|------|------|
| `COLORS` | 基础颜色（数组式 RGB） | `GREEN`, `RED`, `WHITE`, `ORANGE`, `BLACK` |
| `QUALITY_COLOR` | 品质颜色（1~5 索引） | 普通/精良/稀有/史诗/传说 |
| `DIFFICULTY_COLOR` | 难度颜色 | `easy`(蓝), `normal`(紫), `hard`(橙) |
| `GUI_COLOR` | UI 专用颜色 | `COMFY`, `GOLD`, `HINT_GREY`, `LABEL_BLUE`, `DARK_RED`, `LINK_BLUE` |
| `apply_style` | 批量应用样式工具函数 | `apply_style(elem, {font=..., font_color=...})` |

### 难度颜色体系

| 难度 | 颜色 | RGB |
|------|------|-----|
| easy | 蓝色 | `{r = 0.3, g = 0.6, b = 1.0}` |
| normal | 紫色 | `{r = 0.7, g = 0.3, b = 1.0}` |
| hard | 橙色 | `{r = 1.0, g = 0.6, b = 0.2}` |

### RGB 表格式

```lua
-- 方式 1：键值表（推荐，可读性好）
local color = {r = 1.0, g = 0.84, b = 0}

-- 方式 2：数组表（简洁）
local color = {1, 0.84, 0}
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

## 6. 本地化文本

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
-- ❌ 错误：硬编码文本
caption = '退出副本'

-- ✅ 正确：本地化键
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

> locale 文件组织（一文件一 section、分组注释等）详见 [locale-i18n-guide](../locale-i18n-guide/SKILL.md)

## 7. GUI 创建模式

### 带工具栏的主帧（add_main_frame_with_toolbar）

`utils/gui.lua` 提供 `Gui.add_main_frame_with_toolbar` 工具函数，统一带标题栏 + 拖拽 + 设置/关闭按钮 + inside_frame + scroll_pane 的主帧结构：

```lua
local Gui = require 'utils.gui'

local main_frame, inside_frame, scroll_pane, close_button =
    Gui.add_main_frame_with_toolbar(
        player,
        'screen',              -- align: 'screen' / 'center' / 'left'
        GUI_MAIN_FRAME,        -- 主帧元素名
        GUI_SETTINGS_BUTTON,   -- 设置按钮名（可传 nil 省略）
        GUI_CLOSE_BUTTON,      -- 关闭按钮名（可传 nil 省略）
        {'amap.my_frame_title'} -- 标题
    )
```

- `align == 'screen'` 时自动设置 `drag_target` 支持拖拽
- 返回 `main_frame, inside_frame, scroll_pane, close_button` 四个引用
- 关闭按钮通过 `GuiDispatcher.register_closed` 或 `register_click` 绑定

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
    local Styles = require 'maps.amap.gui_styles'
    local color = Styles.DIFFICULTY_COLOR[difficulty]
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

    return card
end
```

### 选项缓存

玩家关掉 GUI 重开时，选项应保持不变：

```lua
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

## 8. 旧 GUI 迁移与清理

### legacy_gui_cleanup.lua

`utils/legacy_gui_cleanup.lua` 统一归档旧 GUI 元素名与清理函数（过时标记，待兼容完毕后移除）。

```lua
local LegacyCleanup = require 'utils.legacy_gui_cleanup'

LegacyCleanup.cleanup_legacy_gui(player)    -- 全面清理 top/screen/left/center 四处旧元素
LegacyCleanup.migrate_top_buttons(player)   -- 旧 player.gui.top 按钮迁移到 mod_gui button_flow
```

- 各 GUI 模块不再各自维护 LEGACY 列表，统一从此模块读取
- 新代码**不要**往此文件添加内容；新元素名直接用 GuiDispatcher 注册

### 已废弃的 API

| 旧 API（已移除） | 新 API |
|------------------|--------|
| `Gui.on_click(name, handler)` | `GuiDispatcher.register_click(name, handler)` |
| `Gui.on_text_changed(...)` | `GuiDispatcher.register_text_changed(...)` |
| `Gui.on_checked_state_changed(...)` | `GuiDispatcher.register_checked_state_changed(...)` |
| `Gui.on_selection_state_changed(...)` | `GuiDispatcher.register_selection_state_changed(...)` |
| `Gui.on_custom_close(...)` | `GuiDispatcher.register_closed(...)` |
| `Gui.on_elem_changed(...)` | `GuiDispatcher.register_elem_changed(...)` |
| `Gui.on_value_changed(...)` | `GuiDispatcher.register_value_changed(...)` |
| `player.gui.top.add(...)` | `TopBar.add_button(player, ...)` |
| `utils/gui/*` 目录 | `comfy_panel/*` |

## 审查清单

编写或修改 GUI 代码时，对照检查：

- [ ] GUI 事件是否通过 `GuiDispatcher.register_*` 注册（而非直接 `Event.add(on_gui_*)` 或旧 `Gui.on_click`）
- [ ] 事件注册是否在模块加载期完成（非运行时，`_LIFECYCLE==8` 会抛错）
- [ ] 顶栏按钮是否通过 `TopBar.add_button` 添加（而非直接 `player.gui.top.add`）
- [ ] 新增顶栏按钮是否在 `TOP_BUTTON_ORDER` 登记顺序
- [ ] 新增 GUI 模块是否注册了 `GuiRebuild.register` 重建函数
- [ ] GUI 元素名是否定义为局部常量（非内联字符串）
- [ ] 元素名格式是否遵循 `dungeon_<缩写>_<功能>` 等约定
- [ ] 文本是否使用本地化键（`{'amap.xxx'}`）而非硬编码字符串
- [ ] 颜色是否引用 `gui_styles.lua` 集中定义（而非内联 RGB）
- [ ] 难度颜色是否使用统一体系（蓝/紫/橙）
- [ ] 副本退出时是否清理了 GUI
- [ ] 选项缓存是否正确实现（防止重开刷新）

## 参考

- GUI 事件派发器：`utils/gui_dispatcher.lua`
- 顶栏管理：`utils/top_bar.lua`
- 顶栏按钮排序：`utils/top_button_order.lua`
- GUI 热更重建：`utils/gui_rebuild.lua`
- 颜色/样式集中定义：`maps/amap/gui_styles.lua`
- 旧 GUI 清理归档：`utils/legacy_gui_cleanup.lua`
- GUI 面板实现：`comfy_panel/`
- 带工具栏主帧工具：`utils/gui.lua`（`Gui.add_main_frame_with_toolbar`）
- 副本框架 GUI：`maps/amap/instance/instance.lua`
- 天赋 GUI：`maps/amap/tianfu.lua`
- RPG GUI：`modules/rpg/gui.lua`
- 商店 GUI：`maps/amap/market_gui.lua`
- Locale 指南：[locale-i18n-guide](../locale-i18n-guide/SKILL.md)
- 事件系统指南：[event-system-guide](../event-system-guide/SKILL.md)
