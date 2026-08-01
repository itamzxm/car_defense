# 坦克保卫战 AI Agent 编码指南

欢迎参与坦克保卫战的开发！本指南旨在帮助 AI Agent 快速理解项目结构及编码规范，以提供更高质量的代码建议。

---

> [!CAUTION]
>
> 首要准则：**产出符合编码规范的代码**
>
> **`CLAUDE.md`（项目核心规则）+ `.agents/skills/`（开发规范 skill 文件）是代码产出的基准。AI 生成的代码必须符合规范，不应让用户事后纠正。**
>
> 1. **合规优先 + 主动提醒**：AI 应在用户指令可能违反规范时主动提醒，给出符合规范的替代方案，但不替代用户的最终判断。例如用户想"给 Event.add 加过滤器"→ 提醒 filters 禁令，改为 handler 内 self-filter；用户想"魔法天赋只写基础伤害"→ 提醒必须纳入科技加成 + 品质系数；用户想"难度设计一次改 8 个维度"→ 提醒 2~3 条参数改动原则。
> 2. **产出即合规**：AI 生成的 Lua 代码默认应能通过无头 Factorio 加载测试，不需要用户手动修正违规写法。
> 3. **信息不足时标注而非瞎编**：缺少 locale 键、天赋 ID、配置数值等上下文时，AI 应基于已有信息写出初稿，并明确标注不确定的占位部分，要求用户补充。
>
> **AI 的默认行为**
>
> | 用户意图 | AI 的默认做法 |
> | -------------------------------------- | ----------------------------------------------------------------------------------------------- |
> | 给 Event.add 加 filters | 提醒 filters 禁令（非 control.lua 一律违规），改为 handler 内 self-filter |
> | 魔法天赋只写基础伤害 | 提醒必须纳入科技加成（laser modifier）+ 品质系数（COEFF_REG），给出完整公式 |
> | 魔法技能范围写超过 24 | 提醒 24 米上限，改为 `math.min(range, 24)` |
> | 难度设计一次改多个维度 | 提醒 2~3 条参数改动原则，优先用场地缩小 + 节奏加快，给出合规示例 |
> | 新建独立函数/文件 | 先搜索已有同类代码，确认能否复用/扩展，而非直接新建 |
> | 用 PowerShell 写含中文 Lua | 提醒 Set-Content 乱码风险（事故记录 2026-07-05），改用 edit 工具 |
> | pcall 吞掉错误 | 提醒"错误不可掩盖"规则，让错误正常暴露，仅外部边界可容错 |
> | 随意调数字 | 提醒"改动数字需有依据"，要求说明原因 + 目标值 + 依据 |
> | 修改已有代码 | 先汇报文件/位置/内容/原因，经批准后执行（新增代码无需汇报） |
> | 同一问题尝试 2 次未解决 | 主动向用户请求帮助，提供问题描述 + 涉及文件 + 调用关系 |
> | 只改中文 locale 忘改英文 | 提醒所有文本修改必须同步中英文 locale 文件 |
> | 代码产出完成 | 主动告知可运行的验证：无头加载测试 + RCON 测试（见离线测试方法） |
>
> **核心原则：AI 产出的代码默认合规，用户无需事后纠正。**

---

## 项目概览

**坦克保卫战（Car Defense）** 是基于 Factorio 2.0 的 RPG 生存场景（v4.5.4）。

- **核心玩法**：保护载具 + RPG 成长 + 天赋系统 + 13 个异次元世界 + 20 个副本小游戏
- **主地图模块**：`maps/amap/`（地形、天赋、世界、副本、伪建筑、平衡、难度等）
- **功能模块**：`modules/`（RPG 属性/法术、宠物系统、波次防御等）
- **工具库**：`utils/`（事件系统核心、Global 持久化、Token 闭包、GuiDispatcher/TopBar/GuiRebuild 等）
- **本地化**：`locale/`（zh-CN + en，所有文本修改必须同步）
- **场景入口**：`control.lua`（加载所有模块，唯一可含事件 filters 的文件）

---

## 关键文件与目录

| 路径 | 说明 |
|------|------|
| `control.lua` | 场景入口，加载所有模块；**唯一可含事件 filters 的文件** |
| `CLAUDE.md` | 项目核心规则（难度设计哲学、核心约束、filters 禁令、编码规则等） |
| `maps/amap/` | 核心地图模块（43 个条目） |
| `maps/amap/tianfu*.lua` | 天赋系统（5 个文件：主逻辑、数据表、品质、触发技能、时间技能、一次性技能） |
| `maps/amap/world/worlds/` | 13 个世界定义（world_01_cave ~ world_15_tower_defense） |
| `maps/amap/world/framework.lua` | 世界框架核心（World.register 注册表模式） |
| `maps/amap/instance/modules/` | 20 个副本玩法模块（arena_survival, boss_hunt, coin_mine 等） |
| `maps/amap/instance/instance.lua` | 副本框架核心（Instance.register 自注册模式） |
| `maps/amap/diff.lua` | 难度/波次/世界加成管理 |
| `maps/amap/balance.lua` | 敌方武器伤害初始化与周期性递增 |
| `utils/event_core.lua` | 事件系统核心（Event.add 实现，filters 禁令的根源） |
| `utils/global.lua` | 全局数据持久化（Global.register 三步曲） |
| `utils/token.lua` | 闭包持久化（Token.register，运行时禁止 require） |
| `utils/gui_dispatcher.lua` | GUI 事件派发器（按元素名注册 handler，取代 Gui.on_click） |
| `utils/top_bar.lua` | 顶栏管理（mod_gui button_flow、折叠/展开、统一按钮样式） |
| `utils/top_button_order.lua` | 顶栏按钮排序（TOP_BUTTON_ORDER 顺序表） |
| `utils/gui_rebuild.lua` | GUI 热更/存档兼容统一重建入口（GuiRebuild.register） |
| `utils/legacy_gui_cleanup.lua` | 旧 GUI 元素名/清理归档（过时标记，待移除） |
| `maps/amap/gui_styles.lua` | GUI 颜色/样式集中定义（COLORS/DIFFICULTY_COLOR/apply_style） |
| `comfy_panel/` | GUI 面板实现（取代旧 utils/gui/*，含 poll/player_list/admin 等） |
| `locale/zh-CN/amap.cfg` | 中文项目文本（UTF-8 编码） |
| `locale/en/amap.cfg` | 英文项目文本（必须与中文同步） |
| `.agents/skills/` | 12 个开发规范 skill 文件 |

---

## 不可妥协的约束速查

> 以下规则违反即视为 bug，AI 必须主动遵守并提醒用户。

### 事件过滤器禁令

**永远不要给 Event.add 传 filters 参数**（非 control.lua）。handler 内做类型判断（self-filter）。

```lua
-- ❌ 禁止
Event.add(defines.events.on_entity_died, handler, {{filter='type', type={'locomotive'}}})

-- ✅ 正确
Event.add(defines.events.on_entity_died, handler)
-- handler 内：if entity.type ~= 'locomotive' then return end
```

### 错误不可掩盖

禁止过度 pcall、默认值兜底、注释绕过、return 提前退出绕过异常。内部逻辑必须让错误正常暴露。

### 改动数字需有依据

不得随意调整配置数值。调整前必须明确：**原因 + 目标值 + 依据**。

### 改动已有代码前先汇报

修改现有代码（非新增）前必须向用户说明文件、位置、内容、原因，经批准后执行。

### 求助阈值

同一问题尝试 2 次仍未解决，必须主动向用户请求帮助（附问题描述 + 涉及文件 + 调用关系）。

### 作用范围上限 24 米

魔法技能/天赋的作用范围最大 24 米。代码中只能写 `24`，不得写更大的数。非魔法技能不受此限。

### 添加功能前必须先探索

搜索已有代码 → 通读完整流程 → 确认复用/扩展点，再动手。不要凭局部理解直接写新代码。

### 文件编码

新建文件 UTF-8；修改已有文件先检测原编码并保持一致；**绝对不要用 PowerShell 的 Set-Content 写入含中文的 Lua 文件**。

---

## 编码规范

### 1. Lua 编码风格

> 详见 [lua-coding-style](.agents/skills/lua-coding-style/SKILL.md)

- **模块导出**：主流 `local Public = {} ... return Public`；副本用 `local M = {} ... Instance.register(M.type, M)`；工具模块表名即模块名（`Token`, `Global`）
- **命名**：常量 `SCREAMING_SNAKE_CASE`、函数 `snake_case`、天赋ID 中文拼音缩写、世界文件 `world_XX_<name>.lua`、GUI元素名 `dungeon_<缩写>_<功能>`
- **require**：点分隔从场景根开始（`require 'maps.amap.tianfu_table'`）；只能在文件顶层使用
- **局部缓存**：热路径 `local insert = table.insert; local sqrt = math.sqrt`

### 2. 事件系统

> 详见 [event-system-guide](.agents/skills/event-system-guide/SKILL.md)

- **禁止 filters**：`Event.add(event_id, handler)` 不传第三个参数；handler 内 self-filter
- **注册方式**：`Event.add` / `Event.on_init` / `Event.on_load` / `Event.on_nth_tick`
- **GUI 事件**：通过 `GuiDispatcher.register_click(name, handler)` 注册，不直接 `Event.add(on_gui_click)`；运行时（`_LIFECYCLE==8`）禁止注册
- **handler 结构**：实体验证 → 类型过滤 → 副本隔离 → 业务逻辑
- **cause 分派**：用表替代 if-elseif 链

### 3. 全局数据持久化

> 详见 [global-data-guide](.agents/skills/global-data-guide/SKILL.md)

- **标准三步曲**：`local this = {}` → `Global.register(this, function(tbl) this = tbl end)` → `Public.get() return this end`
- **主表访问**：`WPT.get()` 全局主表、`TPT.get()` 天赋专用表
- **副本隔离**：私有数据存 `data.module_data`，框架不触碰
- **Token.register**：闭包持久化；运行时禁止注册（`_LIFECYCLE == 8` 时抛错）
- **性能优化**：倒排索引替代全扫描、tick 分桶调度替代每 tick 遍历

### 4. 难度设计

> 详见 [difficulty-design-guide](.agents/skills/difficulty-design-guide/SKILL.md)

- **核心原则**：每次难度提升只改 2~3 条参数，做 1.0 → 1.2 → 1.44 线性增量
- **优先维度**：场地缩小 + 节奏加快（间隔缩短/波次增多）
- **禁止维度**：不换 Boss 类型、不换虫子类型、不砍道具种类
- **难度颜色**：easy=蓝 `{0.3,0.6,1.0}` / normal=紫 `{0.7,0.3,1.0}` / hard=橙 `{1.0,0.6,0.2}`

### 5. 魔法伤害计算

> 详见 [magic-damage-guide](.agents/skills/magic-damage-guide/SKILL.md)

- **适用范围**：所有魔法术类直接伤害（非物理/爆炸）
- **科技加成**：`get_ammo_damage_modifier("laser") + 1` 和 `get_gun_speed_modifier('laser') + 1`
- **品质系数**：`COEFF_REG = {1, 1.2, 1.4, 1.6, 1.8}`（普通/精良/稀有/史诗/传说）
- **最终公式**：`base_damage * damage_modifier / speed_modifier * quality_coeff`
- **范围上限**：魔法技能/天赋最大 24 米

### 6. 本地化

> 详见 [locale-i18n-guide](.agents/skills/locale-i18n-guide/SKILL.md)

- **中英同步**：所有文本修改必须同步 `locale/zh-CN/` 和 `locale/en/`
- **一文件一 section**：文件名与 section 名对应（`amap.cfg`→`[amap]`、`icw.cfg`→`[icw]`），禁止追加到文件末尾
- **键名格式**：`amap.<功能域>_<描述>`，按功能域加 `# ── 功能域名 ──` 分组注释
- **参数占位**：`__1__`, `__2__`
- **禁止硬编码文本**：用 `{'amap.xxx'}` 而非 `'中文文本'`

### 7. GUI 开发

> 详见 [gui-development-guide](.agents/skills/gui-development-guide/SKILL.md)

- **事件派发**：`GuiDispatcher.register_click(name, handler)` 按元素名注册（取代旧 `Gui.on_click`），运行时禁止注册
- **顶栏按钮**：`TopBar.add_button(player, definition)` 添加按钮，顺序由 `TOP_BUTTON_ORDER` 统一排
- **热更重建**：各模块通过 `GuiRebuild.register(name, fn)` 注册清理+重建函数，`on_configuration_changed` 时统一重建
- **颜色/样式**：集中定义在 `maps/amap/gui_styles.lua`（`COLORS`/`DIFFICULTY_COLOR`/`QUALITY_COLOR`/`apply_style`）
- **元素名常量**：局部常量（非内联字符串），格式 `dungeon_<缩写>_<功能>`
- **旧 GUI 清理**：`utils/legacy_gui_cleanup.lua` 归档旧元素名（过时标记，待移除）

### 8. 底层工具规范（Queue/Buckets/StateMachine/ErrorLogging + 业务工具层）

> 详见 [global-data-guide](.agents/skills/global-data-guide/SKILL.md) 及 [utils-toolbox-guide](.agents/skills/utils-toolbox-guide/SKILL.md)

- **Queue（`utils/queue.lua`）**：环形队列，适合波次刷怪/事件序列。`Queue.new()` → `push`（尾部）/ `pop`（头部，空返 nil）/ `peek` / `size` / `pairs`；**纯表结构可直接存入 storage 持久化**（无闭包）
- **Buckets（`utils/buckets.lua`）**：tick 分桶调度规范实现。`Buckets.new(interval)` → `add(bucket, id, data)` / `get` / `remove` / `reallocate` / `migrate`；到期任务放对应 tick 桶，on_tick 只查当前桶；**所有延迟/周期调度优先用 Buckets 而非手写 bucket 表**
- **StateMachine（`utils/state_machine.lua`）**：有限状态机。`StateMachine.new(init_state)` → `transition(state)` / `in_state(state)` / `machine_tick()`（每 tick 驱动）+ `register_state_tick_callback(state, fn)` / `register_transition_callback(old, new, fn)`；适合 Boss AI / 波次阶段机
- **ErrorLogging（`utils/error_logging.lua`）**：错误归档。`generate_error_report(str)` 生成报告、`error_handler(err)` 统一错误处理；写入 `script-output/car_defense_errors.log`；**handler 崩溃由事件系统诊断钩子自动归档，不得自行 pcall 掩盖**
- **ScoreTracker（`utils/score_tracker.lua`）**：登记制统计框架。`register(name, locale, icon)` 加载期登记 → `change_for_player/change_for_global` 增减 → `set_for_player/set_for_global` 赋值 → `get_for_player/get_for_global` 读取；变更触发自定义事件；**杜绝拼错键名静默创建新统计**
- **ActiveInterval（`utils/active_interval.lua`）**：按需启停周期任务。`create(interval, func)` 加载期创建句柄 → `handle.enable()/disable()/is_active()` 运行时启停；**替代常驻 on_nth_tick 空扫描**
- **TemporaryModifiers（`utils/temporary_modifiers.lua`）**：Force modifier 临时加成。`apply(force, method, kind, bonus, duration_ticks)` 临时加 bonus，到期差值还原（不覆盖他人改动）
- **PlayerModifiers（`utils/player_modifiers.lua`）**：玩家 modifier 多来源叠加管理。`update_single_modifier(player, modifier, category, value)` 按类别叠加 → `update_player_modifiers(player)` 统一刷写到角色
- **Alert（`utils/alert.lua`）**：带进度条可关闭弹窗通知。`alert_player/alert_force/alert_all_players` 支持 locale 模板、音效、位置跳转
- **PriorityQueue / TerrainGenerator / ColorPresets / Timers / Timestamp / ListUtils / Stats / Profiler / SpamProtection**：详见 [utils-toolbox-guide](.agents/skills/utils-toolbox-guide/SKILL.md)

---

## 底层冻结宣言

> 2026-08-01 底层基建终极维护，完成后，以下核心底层进入冻结状态：**新增/修改需说明原因 + 目标值 + 依据，并经协作者/创作者确认。**

- **冻结对象**：`utils/` 下的基建工具（queue / buckets / state_machine / error_logging / global / token / event_core / event / gui_dispatcher / top_bar / gui_rebuild 等）与 `control.lua` 的模块加载结构
- **禁止**：绕过确认直接改底层、另起炉灶重写（如手写新队列替代 Queue、手写桶替代 Buckets、新事件分发替代 GuiDispatcher）
- **业务层**（`maps/amap`、`modules`）不受冻结限制，按常规规范开发

---

## 天赋 4 池分类速查

每个天赋**必须**归入以下 4 个天赋池之一：

| 池子 | 英文键 | 适用范围 | 示例 |
|------|--------|---------|------|
| 战士 | `fighter` | 战斗/生存向，偏肉偏伤 | 鱼灵、狼、击杀回血 |
| 建筑 | `builder` | 建造/生产/资源向 | 建造者、采矿加成 |
| 法师 | `mage` | 魔法术类伤害/法力向 | 魔力之泉、黑魔导师、雷霆万钧 |
| 其他 | `other` | 不属于以上三类 | 移动速度、视野效果 |

**无法清晰匹配时，默认归入「其他」**，不得强行塞入不合适的池子。

> 详见 [talent-addition-guide](.agents/skills/talent-addition-guide/SKILL.md)

---

## 品质系数表

项目约定，不得自行定义其他数值：

| 品质 | 索引 | 系数 |
|------|------|------|
| 普通 | 1 | 1.0 |
| 精良 | 2 | 1.2 |
| 稀有 | 3 | 1.4 |
| 史诗 | 4 | 1.6 |
| 传说 | 5 | 1.8 |

```lua
local COEFF_REG = {1, 1.2, 1.4, 1.6, 1.8}
```

---

## 离线测试方法

本地装有 Steam Factorio，无需进游戏即可验证代码加载和纯逻辑。多人协作环境差异大，**开测前必须先做环境自检**。

### 开测前环境自检（必做）

> 目的：确认「被测场景」就是「项目根」，避免测到旧副本（现象：改了代码但日志 `Checksum for script` 不变）

1. **询问用户游戏目录**（不要假设路径，如 Steam 版可能在 `C:/Program Files (x86)/Steam/...`，用户本机实测为 `E:\Game\Factorio`），并定位 `factorio.exe`（`<游戏根>/bin/x64/factorio.exe`）
2. **检查本项目场景在哪**：`<游戏根>/scenarios/` 下找项目目录，可能同时存在：
   - 符号链接（推荐，实时指向项目根）——正确被测对象
   - 旧副本目录（普通文件夹，改代码不生效）——**不要用**
3. **确认符号链接指向项目根**（PowerShell）：
   ```powershell
   Get-Item "<游戏根>\scenarios\<场景目录名>" | Select-Object Name,LinkType,Target
   # LinkType=SymbolicLink 且 Target=项目根 = 正确
   ```
4. **场景加载名 = 场景目录名**（如符号链接名 `car_defense`），不是项目显示名（旧副本名「坦克保卫战」是坑）
5. **验证加载的是当前代码**：改过代码后日志 `Checksum for script __level__/control.lua` 必须变化；不变 = 加载了旧副本

### 无头加载测试（验证能否加载）

```powershell
# 用自检得到的 <factorio.exe 路径> 与 <场景名>
& "<factorio.exe 路径>" `
    --start-server-load-scenario <场景名> --no-log-rotation
```

日志到 `Hosting game` / `InGame` 且无 `Error` / Lua 报错 = 全部通过。

### RCON 命令执行测试（在真运行时跑逻辑）

```powershell
# 步骤 1：起服务器（⚠ 必须带 --server-settings：默认 auto_pause=true，无玩家时模拟暂停，每次 RCON 命令只触发 1 tick，任务逻辑测不准）
& "<factorio.exe 路径>" `
    --start-server-load-scenario <场景名> `
    --server-settings "<游戏根>\scenarios\test-server-settings.json" `
    --rcon-port 27015 --rcon-password 123 --no-log-rotation

# 步骤 2：进 InGame（~12s）后执行测试
python rcon_driver.py "/c _TEST.run_all()" 127.0.0.1 27015 123
```

### 测试框架（断言级单元测试）

- **开关**：`control.lua` 顶部 `_DEBUG_TEST_FRAMEWORK = false`（默认关闭，测试时临时改 true 后还原）
- **测试文件**：`utils/test/`（runner / viewer / command / discovery）+ `utils/*_tests.lua`（如 queue_tests、event_tests）
- **跑法**：
  - 无玩家（RCON）：`python rcon_driver.py "/c _TEST.run_test_framework()" 127.0.0.1 27015 123`
  - 有玩家（游戏内）：`/test-runner` 命令打开测试 GUI
- **结果**：无玩家时 Passed/Failed + summary 写日志；有玩家时 GUI 展示
- **调用约定**：`run_module(module, player, options)` 无 self，pcall 传参不能带模块表

### 关键约束

- **运行时（/c）禁止 require**：测试代码由 `command_line.lua` 加载期注册为全局 `_TEST`
- **RCON 执行 Lua 必须带 `/c` 前缀**
- **用 `log()` 而非 `print()`**：print() 在无头模式不写日志
- **RCON 响应分多包到达**：客户端需持续 drain
- **Factorio RCON 包体后需 2 个 null 字节**（标准实现只发 1 个会认证失败 id=-1）
- **无玩家时 tick 暂停**：`--server-settings` 的 `auto_pause: false` 是 RCON 逻辑测试的前提

### 能力边界

- **能测**：纯逻辑（品质映射、概率计算、数学函数、经验曲线、模块加载）
- **不能测**：需真实实体/玩家/事件的玩法逻辑（天赋触发实时数值）

> 详见 [offline-testing-guide](.agents/skills/offline-testing-guide/SKILL.md)

---

## 审查重点

审查代码时，请重点关注以下事项：

- **Event.add filters**：非 control.lua 中出现第三个参数即违规
- **魔法伤害完整性**：是否纳入科技加成 + 品质系数（缺一不可）
- **魔法范围上限**：是否 ≤ 24 米
- **难度设计**：easy/normal/hard 间是否只改 2~3 个维度，其余全难度统一
- **错误掩盖**：是否过度 pcall / 默认值兜底 / 注释绕过
- **代码复用**：新增代码是否复用了已有结构（而非新建独立函数/文件）
- **locale 同步**：中英 locale 是否同步修改，键名格式是否为 `amap.<功能域>_<描述>`
- **GUI 事件注册**：是否通过 `GuiDispatcher.register_*` 而非直接 `Event.add(on_gui_*)`
- **GUI 元素名**：是否为局部常量（非内联字符串），格式是否为 `dungeon_<缩写>_<功能>`
- **GUI 热更重建**：新增 GUI 模块是否注册了 `GuiRebuild.register` 重建函数
- **GUI 颜色**：是否引用 `gui_styles.lua` 集中定义（而非内联 RGB）
- **文本本地化**：是否用 `{'amap.xxx'}` 而非硬编码字符串
- **副本数据隔离**：私有数据是否在 `data.module_data` 中
- **require 位置**：是否仅在文件顶层
- **文件编码**：是否 UTF-8，是否用 edit 工具修改（非 PowerShell Set-Content）
- **天赋分类**：是否归入 4 池之一，法师池天赋是否适用魔法伤害规则
- **数值依据**：调整的数字是否有明确原因 + 目标值 + 依据

---

## 已过时文档（禁止参考）

以下文件很可能已失效，内容与当前代码不一致，**AI 开发时不要参考**：

- `可升级技能添加方法.md`
- `数值平衡参考.md`

如需相关信息，以实际代码为准。

---

## 可参考文档

- `世界添加说明.md` — 新世界框架的字段定义与添加流程
- `魔法技能增加说明.md` — 新魔法技能设计的字段定义与升级模式说明

---

## 开发规范 Skill 文件索引

| Skill | 说明 |
|-------|------|
| [lua-coding-style](.agents/skills/lua-coding-style/SKILL.md) | Lua 编码风格（模块导出、命名、require、缓存、编码） |
| [event-system-guide](.agents/skills/event-system-guide/SKILL.md) | 事件系统（filters 禁令、self-filter、生命周期、诊断） |
| [core-constraints-guide](.agents/skills/core-constraints-guide/SKILL.md) | 核心约束速查（错误不可掩盖、数值依据、求助阈值等） |
| [global-data-guide](.agents/skills/global-data-guide/SKILL.md) | 全局数据持久化（Global.register、Token、倒排索引、tick分桶、ScoreTracker、ActiveInterval、TemporaryModifiers、PlayerModifiers） |
| [utils-toolbox-guide](.agents/skills/utils-toolbox-guide/SKILL.md) | 工具箱速查（PriorityQueue、TerrainGenerator、ColorPresets、Timers、Timestamp、ListUtils、Stats、Profiler、SpamProtection） |
| [world-addition-guide](.agents/skills/world-addition-guide/SKILL.md) | 新世界添加（World.register、地形生成器、locale） |
| [instance-addition-guide](.agents/skills/instance-addition-guide/SKILL.md) | 新副本添加（自注册、钩子函数、难度设计、道具系统） |
| [talent-addition-guide](.agents/skills/talent-addition-guide/SKILL.md) | 新天赋添加（4池分类、魔法伤害、品质系数、黑名单） |
| [difficulty-design-guide](.agents/skills/difficulty-design-guide/SKILL.md) | 难度设计（2~3条参数改动、首选/禁止维度、梯度分析） |
| [magic-damage-guide](.agents/skills/magic-damage-guide/SKILL.md) | 魔法伤害计算（科技加成、品质系数、24米上限） |
| [gui-development-guide](.agents/skills/gui-development-guide/SKILL.md) | GUI 开发（GuiDispatcher 派发、TopBar 顶栏、GuiRebuild 热更、Alert 弹窗通知、元素名常量、颜色样式） |
| [locale-i18n-guide](.agents/skills/locale-i18n-guide/SKILL.md) | 本地化（键名格式、中英同步、参数占位、Rich text） |
| [offline-testing-guide](.agents/skills/offline-testing-guide/SKILL.md) | 离线测试（无头加载、RCON、能力边界） |

---

## 相关文档链接

- 项目核心规则：`CLAUDE.md`
- Factorio Lua API：https://lua-api.factorio.com/latest/
- Factorio Modding Wiki：https://wiki.factorio.com/Modding
- Factorio Locale 文档：https://wiki.factorio.com/Locale
- Factorio Rich Text：https://wiki.factorio.com/Rich_text
