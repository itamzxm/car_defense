---
name: event-system-guide
description: 坦克保卫战事件系统使用指南。规范 Event.add 调用方式、filters 禁令、handler 内 self-filter 模式、生命周期变量、诊断钩子等。在编写、修改或审查任何事件注册代码时使用。
---

# 坦克保卫战事件系统使用指南

## 核心禁令：永远不要给 Event.add 传 filters 参数

**这是项目最重要的约束之一，违反会导致其他模块的事件过滤器被丢弃。**

### 原因

Factorio 的 `script.on_event` 对同一事件 ID 只接受**唯一一组**过滤器。`utils/event_core.lua` 中 `Event.add` 的实现：首次注册时调用 `script.on_event` 并设置 filters，后续 handler 仅 `table.insert` 追加到 handlers 表，**不重新调用 `script.on_event`**。

后果：
- 模块 A 先注册 `on_entity_died` 加 car 过滤器 → 生效
- 模块 B 后注册同事件加 locomotive 过滤器 → B 的过滤器被丢弃，**无法生效**
- 反过来也一样，后注册的过滤器总会丢失

### 正确做法：handler 内 self-filter

```lua
-- 错误：带过滤器（非 control.lua 中）
Event.add(defines.events.on_entity_died, on_entity_died, {
    {filter = 'type', type = {'locomotive', 'cargo-wagon'}}
})

-- 正确：无过滤器，handler 内 self-filter
Event.add(defines.events.on_entity_died, on_entity_died)

local function on_entity_died(event)
    local entity = event.entity
    if not entity or not entity.valid then return end
    if entity.type ~= 'locomotive' and entity.type ~= 'cargo-wagon' then return end
    -- ...处理逻辑
end
```

### 唯一例外：control.lua

`control.lua` 是**唯一可以包含过滤器**的地方。它在所有模块之前注册统一的 master filter，覆盖所有 handler 需要的 entity type。

修改 master filter 时**必须**确保包含所有 handler 用的类型。

### 检查点

`Event.add` 调用若出现第三个参数（filters），在非 `control.lua` 文件中即为**违规**。

## 事件注册 API

### Event.add — 注册事件 handler

```lua
Event.add(defines.events.on_entity_died, on_entity_died)
Event.add(defines.events.on_gui_click, on_gui_click)
Event.add(defines.events.on_player_changed_position, on_player_moved)
```

- 第一个参数：事件 ID（`defines.events.*`）
- 第二个参数：handler 函数
- **禁止第三个参数**（filters），见上

### Event.on_init — 初始化回调

```lua
Event.on_init(function()
    Public.reset_table()
end)
```

- 在新存档创建时执行一次
- 用于初始化 Global.register 的表、设置初始配置

### Event.on_load — 加载回调

```lua
Event.on_load(function()
    -- 恢复模块级 local 引用
    -- Global.register 已自动处理，通常不需要手动写
end)
```

- 在存档加载时执行
- 主要用于恢复模块级 local 变量引用（Global.register 已封装此逻辑）

### Event.on_nth_tick — 周期性任务

```lua
-- 每 54000 tick（约 15 分钟）执行一次
Event.on_nth_tick(54000, enemy_weapon_damage)

-- 每 300 tick（5 秒）执行一次
Event.on_nth_tick(300, check_world_boss)
```

- 比 `on_tick` + 计数器更简洁高效
- 适合周期性递增、定时检查等场景
- 常见间隔：`60`（1秒）、`300`（5秒）、`1800`（30秒）、`3600`（1分钟）、`54000`（15分钟）

## 生命周期变量

### `_LIFECYCLE` 全局变量

标记当前代码执行的生命周期阶段：

| 值 | 阶段 | 说明 |
|----|------|------|
| 5 | `on_init` | 新存档初始化 |
| 6 | `on_load` | 存档加载 |
| 7 | `config_change` | 模组配置变更 |
| 8 | Runtime | 游戏运行中 |

### 使用场景

- `Token.register` 在 `_LIFECYCLE == 8`（Runtime）时抛错，因为运行期注册会导致 ID 不同步
- `GuiDispatcher.register_*` / `Gui.uid_name` / `Gui.uid` 同样在 `_LIFECYCLE == 8` 时抛错（运行时注册 GUI handler 会导致新连接客户端丢失回调，引发 desync）
- `_LIFECYCLE` 检查确保某些操作只在加载期执行

### `_STAGE` 常量

定义在 `utils/data_stages.lua`：

```lua
_STAGE = {
    data = 2,
    settings = 3,
    migration = 4,
    control = 5,
    on_init = 5,
    on_load = 6,
    config_change = 7,
    runtime = 8,
}
```

## 诊断钩子

### xpcall 错误定位

非 `_DEBUG` 模式下，`event_core.lua` 用 `xpcall` 包裹每个 handler，出错时打印：

```
[AMAP-DIAG] handler error in @maps/amap/tianfu_trigger_skill.lua:123: ...
```

- 精确定位崩溃 handler 的**文件:行号**
- 使用 `debug.getinfo(handler, 'S').source` 提取源文件路径
- `_DEBUG` 模式下不包裹，让错误直接抛出（便于调试器捕获）

### 自定义诊断

在 handler 中添加诊断日志时，使用 `log()` 而非 `print()`：

```lua
-- 错误：print() 在无头模式不写日志
print("debug info")

-- 正确：log() 写入 factorio-current.log
log("[MY-MODULE] debug info: " .. serpent.dump(data))
```

## handler 编写模式

### 标准事件 handler 结构

```lua
local function on_entity_died(event)
    -- 1. 实体验证
    local entity = event.entity
    if not entity or not entity.valid then return end

    -- 2. 类型过滤（self-filter 替代 filters 参数）
    if entity.type ~= 'locomotive' and entity.type ~= 'cargo-wagon' then return end

    -- 3. 副本隔离
    if Instance.is_dungeon_surface(entity.surface.name) then return end

    -- 4. 业务逻辑
    -- ...
end
Event.add(defines.events.on_entity_died, on_entity_died)
```

### GUI 事件 handler 结构

> **优先使用 GuiDispatcher**：GUI 事件应通过 `GuiDispatcher.register_click(element_name, handler)` 按元素名注册（见 [gui-development-guide](../gui-development-guide/SKILL.md)），而非手写 `Event.add(on_gui_click)` + 元素名分派。GuiDispatcher 已处理 player/element valid 检查与派发，handler 内只需写业务逻辑。
>
> 下方手写模式仅用于理解原理或特殊场景（如需在一个 handler 内处理大量动态元素名）。

```lua
local function on_gui_click(event)
    -- 1. 玩家验证
    local player = game.get_player(event.player_index)
    if not player or not player.valid then return end

    -- 2. 元素验证
    local element = event.element
    if not element or not element.valid then return end

    -- 3. 元素名分派
    local name = element.name
    if name == GUI_EXIT_BUTTON then
        handle_exit(player)
    elseif name == GUI_DIFFICULTY_BUTTON then
        handle_difficulty(player, element)
    end
end
Event.add(defines.events.on_gui_click, on_gui_click)
```

### cause 类型分派表

对于 `on_entity_died` 等有 `cause` 字段的事件，使用分派表替代 if-elseif 链：

```lua
local get_cause_player = {
    ['character'] = function(cause)
        return cause.player
    end,
    ['car'] = function(cause)
        local driver = cause.get_driver()
        if driver and driver.valid then return driver.player end
    end,
    ['locomotive'] = function(cause)
        local passengers = cause.train.passengers
        if passengers and #passengers > 0 then return passengers[1] end
    end,
}

local function on_entity_died(event)
    local cause = event.cause
    if not cause or not cause.valid then return end
    local fn = get_cause_player[cause.type]
    if not fn then return end
    local player = fn(cause)
    if not player or not player.valid then return end
    -- ...
end
```

## 审查清单

编写或修改事件注册代码时，对照检查：

- [ ] `Event.add` 是否**没有**第三个参数（filters）—— 非 control.lua 中一律违规
- [ ] handler 内是否做了 entity/player/element 的 valid 检查
- [ ] handler 内是否做了类型 self-filter（替代 filters 参数）
- [ ] 副本相关事件是否做了 `Instance.is_dungeon_surface` 隔离
- [ ] 周期性任务是否用了 `Event.on_nth_tick` 而非 `on_tick` + 计数器
- [ ] GUI 事件是否优先用 `GuiDispatcher.register_*` 注册（而非手写 `Event.add(on_gui_click)` + 元素名分派）
- [ ] 诊断日志是否用 `log()` 而非 `print()`
- [ ] cause 类型分派是否用了表而非 if-elseif 链

## 参考

- 事件系统核心实现：`utils/event_core.lua`
- 事件封装层：`utils/event.lua`
- 全局变量管理：`utils/global.lua`
- 令牌系统：`utils/token.lua`
- control.lua master filter：`control.lua`
