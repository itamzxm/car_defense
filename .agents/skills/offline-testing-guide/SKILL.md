---
name: offline-testing-guide
description: 坦克保卫战离线测试指南。提供无头 Factorio 加载测试和 RCON 命令执行测试的完整流程，包括启动命令、关键约束、能力边界等。在验证代码加载、纯逻辑正确性时使用。
---

# 坦克保卫战离线测试指南

## 概述

本地装有 Steam Factorio，无需进游戏即可验证「代码能否加载」以及「纯逻辑是否正确」。

## 开测前环境自检（必做）

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

两种测试方法：

| 方法 | 能力 | 耗时 |
|------|------|------|
| luacheck 静态检查 | 未定义全局 / 未用变量 / 拼写错误（无需启动游戏） | ~1 秒 |
| 无头加载测试 | 验证能否加载（语法、require、on_init） | ~12 秒 |
| RCON 命令执行 | 在真运行时执行 Lua 逻辑 | ~15 秒启动 + 执行时间 |
| 测试框架 | 断言级单元测试（需 `_DEBUG_TEST_FRAMEWORK=true`） | RCON 启动 + 执行时间 |

**推荐顺序**：先 luacheck（秒级抓低级错误）→ 再无头加载（验证加载）→ 需要时 RCON（验证纯逻辑）。

## 方法〇：luacheck 静态检查（前置快速门禁）

### 用途

产出/修改代码后的第一道门禁：抓「未定义全局变量（W111/W113）」「未用 local（W211/W542）」「拼写错误」等低级问题，无需启动游戏，秒级出结果。

### 命令

```powershell
# luacheck.exe 位于 %LOCALAPPDATA%\Programs\Lua\bin\（官方 v1.2.0 预编译，LuaRocks 版缺 gcc 编译不了）
# 若 PATH 未包含，用全路径
& "$env:LOCALAPPDATA\Programs\Lua\bin\luacheck.exe" <文件或目录>

# 示例：检查本次修改的文件
& "$env:LOCALAPPDATA\Programs\Lua\bin\luacheck.exe" utils/dump_env.lua utils/commands/misc.lua
```

### 判断标准

- `0 warnings / 0 errors` = 通过
- 有 W111/W113（未定义全局）= 拼写错或漏 require，必须修
- W211（定义了没用到）等 = 视情况修（死代码/注释掉的处理代码会触发，见 todo 步骤 3）
- **存量告警灰度策略**：先只对**新增/修改文件**跑，存量告警允许存在、逐步清零（见 todo 步骤 1）

### 能查

- 未定义全局变量（W111/W113，`game`/`defines` 等 std 配置由 `.luacheckrc` 提供）
- 拼写错误（把 `player.print` 写成 `player.pirnt` 直接报 113）
- 未使用的 local（W211/W542，死代码信号）

### 不能查

- 运行时行为 / 逻辑正确性（仍需无头加载 + RCON）
- 玩法逻辑（需真实实体/玩家/事件）

### 项目配置说明

- `.luacheckrc` 已按 Factorio 2.1.12 校订：`game`/`defines` 等用 `other_fields = false` 严格模式，新 API（如 `script.get_event_name`、`helpers.write_file`）已补齐
- `helpers`（LuaHelpers 全局）在 std 配置中可用，2.0 起的 `helpers.write_file` 等不会误报

## 方法一：无头加载测试

### 用途

验证全部 Lua 文件解析通过、所有 `require` 解析、模块级代码与 `on_init` 执行无错。

### 命令

```powershell
# 在 %APPDATA%/Factorio 下执行
# ⚠ 场景名必须用 car_defense（符号链接指向项目根），"坦克保卫战" 是旧副本（改代码不生效，checksum 不变）
& "C:/Program Files (x86)/Steam/steamapps/common/Factorio/bin/x64/factorio.exe" `
    --start-server-load-scenario car_defense `
    --no-log-rotation
```

### 判断标准

- 日志一路到 `Hosting game` / `InGame` 且**无 `Error` / Lua 报错** = 全部通过
- 出现 `Error` 或 Lua 报错 = 有语法错 / require 路径错 / on_init 报错
- 确认加载的是当前代码：日志 `Checksum for script __level__/control.lua` 变化（改了代码后 checksum 必变）

### 能查

- 语法错
- `require` 路径错
- 加载期运行时报错
- `on_init` 执行报错

### 不能查

- 玩法逻辑（需要真实实体/玩家/事件）
- GUI 交互
- 天赋触发实时效果

## 方法二：RCON 命令执行测试

### 原理

本地无头起服务器 + 开 RCON → RCON 发 `/c <Lua>` → 在真·Factorio 运行时执行 → `log()` 写进 `factorio-current.log` 被读取。

### 关键约束（踩坑结论）

#### 1. 运行时禁止 require

```lua
-- 错误：运行时(/c)中 require 会报错
/c require 'maps.amap.tianfu'

-- 报错：Require can't be used outside of control.lua parsing
```

**解决**：测试代码必须在**加载阶段**由 `control.lua` 顶层 `pcall(require, 'command_line')` 载入并注册成全局（如 `_TEST`），`/c` 只调全局、不再 require。

#### 2. RCON 执行 Lua 必须带 `/c` 前缀

```powershell
# 错误：无 /c 前缀，被当普通命令忽略
python rcon_driver.py "some_lua_code"

# 正确：带 /c 前缀
python rcon_driver.py "/c some_lua_code"
```

#### 3. 用 `log()` 而非 `print()`

```lua
-- 错误：print() 在无头 /c 不写日志
/c print("test result")

-- 正确：log() 写入 factorio-current.log
/c log("test result")
```

日志格式：`Script <expr>:<line>: <msg>`

#### 4. RCON 响应分多包到达

客户端要持续 drain 若干秒才收全（见 `rcon_driver.py`）。

#### 5. `/c` 里访问 `game.commands` 会静默失败

```lua
-- 错误：命令不执行、无错误响应、日志无输出（排查极费时）
/c log(tostring(game.commands['sp_debug_text'] ~= nil))

-- 正确：命令注册表在全局 commands 模块下（Factorio 无 game.commands 成员）
/c log(tostring(commands.commands.sp_debug_text ~= nil))
```

> 实测（2026-08-01）：`game.commands ~= nil` 与 `game.commands.x` 均使整条命令静默失败（AUTH OK 但无 Script 日志、无 RESP）；换成 `commands.commands.<name>` 立即成功。

#### 6. `/c` 环境里模块局部名不是全局

```lua
-- 错误：Token/Task/Event 等模块名在 /c 环境是 nil → 命令报错，AUTH OK 但无 RESP、无日志（极难排查）
/c log(tostring(Token.get(325)))

-- 正确：/c 只调全局（如 _TEST.*）；模块内逻辑在 _TEST 函数里用 upvalue 访问
/c _TEST.some_test()
```

#### 7. `/c` 的 pcall 多返回值不显示 → 用 `log()` 捕获错误

```lua
-- 错误：显示 NO RESPONSE，拿不到错误信息，无法定位
/c pcall(_TEST.tool_temp_mod_test)

-- 正确：/c 里捕获错误后 log() 落日志
/c local ok, err = pcall(_TEST.tool_temp_mod_test); log('[TMP] ' .. tostring(ok) .. ' | ' .. tostring(err))
```

#### 8. `Task.set_timeout_in_ticks` 的 params 是**单个参数**

```lua
-- 错误：多余参数被丢弃，回调只拿到第一个
Task.set_timeout_in_ticks(10, token, force.name, method, kind, bonus)

-- 正确：打包成表，回调内解包
Task.set_timeout_in_ticks(10, token, {force.name, method, kind, bonus})
-- 回调：local force_name, method, kind, bonus = params[1], params[2], params[3], params[4]
```

#### 9. Force modifier 是**点调用**（不传 self）

```lua
-- 错误：get(force, kind) → "Arguments count error for 'get': Expected 1 argument but 2 were given"
local get = force['get_' .. method]; get(force, kind)

-- 正确：点调用只传 kind（对齐 balance.lua:67 先例 `e.get_ammo_damage_modifier(k)`）
local get = force['get_' .. method]; get(kind)
```

#### 10. `set_tiles` / `get_tile` 需要 chunk 已生成

- 未生成 chunk 上 `get_tile` 返回 invalid tile：`LuaTile API call when LuaTile was invalid`
- Factorio 2.0 **没有** `surface.ensure_chunk_generated`，改用：
  ```lua
  surface.set_chunk_generated_status({x = 0, y = 0}, defines.chunk_generated_status.entities)
  ```

### 启动与执行

```powershell
# 步骤 1：起服务器（建议用 timeout 包住避免常驻）
# ⚠ 必须带 --server-settings（test-server-settings.json 已设 auto_pause: false）：
#    Factorio 默认 auto_pause=true，无玩家时模拟暂停，每次 RCON 命令只触发 1 tick 更新（延迟任务要等下一次 RCON 才走，坑）
& "C:/Program Files (x86)/Steam/steamapps/common/Factorio/bin/x64/factorio.exe" `
    --start-server-load-scenario car_defense `
    --server-settings "E:/Game/Factorio/scenarios/test-server-settings.json" `
    --rcon-port 27015 `
    --rcon-password 123 `
    --no-log-rotation

# 步骤 2：等进 InGame（约 12 秒）后，另一终端执行测试
python rcon_driver.py "/c _TEST.run_all()" 127.0.0.1 27015 123
```

> 本机实测路径：`E:\Game\Factorio\bin\x64\factorio.exe`、场景 `E:\Game\Factorio\scenarios\car_defense`（符号链接）、日志 `E:\Game\Factorio\factorio-current.log`

### 进程清理（必做，防测到旧进程）

- **现象**：改了代码、重启了服务器，但日志里 `log()` 的行号/内容仍是旧版（如 `command_line.lua:170` 是旧文件行号）→ RCON 连的是**未杀干净的旧进程**
- **原因**：旧 factorio 进程仍在跑、占用 RCON 端口；`Start-Process` 的新进程起不来或不起作用
- **处置**：
  1. `Get-Process factorio | Select Id,StartTime` 查**全部** factorio 进程（可能多个）
  2. 全部 `Stop-Process -Force`（先杀 pid 文件里的，再核对进程列表为空）
  3. 重启后**验证**：日志出现**新的加载特征**（新行号 / 新增的 log 标记 / 新日志时间）
- **补充**：`Checksum for script __level__/control.lua` **不是只反映 control.lua 本身**——实测（2026-08-01）：仅改 require 的模块（world_14_grass_invasion.lua 加一行 valid 守卫）后 checksum 从 `2328230409` 变为 `4038150381`。**任何代码改动后 checksum 都应变化**；判断模块是否加载了新代码，可靠信号是日志里的**行号与新增 log 标记**

### 相关文件

| 文件 | 位置 | 说明 |
|------|------|------|
| `command_line.lua` | 场景根（git 白名单外，不跟踪） | 加载期 require 真实模块 + 注册测试到全局 `_TEST`；`control.lua` 末尾 `pcall(require, 'command_line')` 载入，生产缺文件时静默跳过（非 not-found 错误会 log） |
| `control.lua` 末尾 | 场景根 | `local ok, err = pcall(require, 'command_line')`，err 非 not-found 时 log 暴露 |
| `rcon_driver.py` | `E:\Game\Factorio\scenarios\`（场景父目录，不被同步） | Source RCON 客户端（⚠ Factorio 包体后需 **2 个** null 字节，body 编码 UTF-8；认证成功 `AUTH OK`，命令执行后空响应 `NO RESPONSE` 属正常） |
| `test-server-settings.json` | `E:\Game\Factorio\scenarios\`（不被同步） | 测试用服务器配置：`auto_pause: false`（关键）、autosave 关闭、`allow_commands: admins-only` |

### 路径坑

- Python 参数用反斜杠 Windows 路径
- MSYS 会把 `/c/...` 传成 `c:\c\...` 导致找不到文件

### 临时验证

连文件都不用建，直接在真运行时跑任意 Lua：

```powershell
python rcon_driver.py "/c log(serpent.dump(game.forces.player.get_ammo_damage_modifier('laser')))"
```

## 方法三：测试框架（断言级单元测试）

### 用途

在真运行时做**断言级**单元测试（数值比对、状态验证），结果可落日志（无玩家）或 GUI 展示（有玩家）。适合验证 queue/buckets/state_machine/event 等纯逻辑工具与数学函数。

### 开关与加载

```lua
-- control.lua 顶部（默认关闭，测试时临时改 true，测完还原 false）
_DEBUG_TEST_FRAMEWORK = false
-- 打开后 control.lua 末尾 require 'utils.test.main'
```

### 测试文件结构

| 文件 | 说明 |
|------|------|
| `utils/test/main.lua` | 入口，include runner/viewer/command/discovery |
| `utils/test/runner.lua` | 执行器：`Public.run_module(module, player, options)` / `Public.run_test(test, player, options)` |
| `utils/test/viewer.lua` | 结果 GUI 展示（有玩家） |
| `utils/test/command.lua` | `/test-runner` 命令注册 |
| `utils/test/discovery.lua` | 自动发现 `utils/*_tests.lua` 测试文件 |
| `utils/*_tests.lua` | 测试用例（如 queue_tests.lua、event_tests.lua、tianfu_quality_tests.lua） |

### 跑法

```powershell
# 无玩家（RCON）：结果 Passed/Failed + summary 写日志
python rcon_driver.py "/c _TEST.run_test_framework()" 127.0.0.1 27015 123

# 有玩家（游戏内）：/test-runner 打开测试 GUI 运行
```

### 关键约束（调用约定坑）

- `run_module(module, player, options)` **无 self**——pcall 传参不能带模块表：`pcall(runner.run_module, module, player)` 而非 `pcall(runner.run_module, runner, module, player)`
- 测试代码由 `command_line.lua` 加载期 require 注册为全局 `_TEST`，运行时 `/c` 只调全局、禁止 require
- 断言失败需通过框架的事件/返回机制暴露，不要在测试文件里 print 了事

### 相关文件

| 文件 | 位置 | 说明 |
|------|------|------|
| `command_line.lua` | 场景根（git 白名单外，不跟踪） | `_TEST.run_test_framework()` 桥接入口（require runner + 顶层 pcall 封装） |

## 能力边界

### 能测（占多数 bug）

- 纯逻辑正确性
- 品质映射（`COEFF_REG` 索引是否正确）
- `roll` 概率计算
- `qround` / `fmt2` 数学函数
- 经验曲线计算
- 宠物解锁等级
- locale 键拼装
- 模块加载是否成功
- Global.register 引用恢复

### 不能测

- 需真实实体/地表/玩家/事件的玩法逻辑
- 天赋触发实时数值效果
- GUI 交互
- 地形生成视觉效果
- Boss AI 行为

这些仍须进游戏 + `game.print` 断点测试。

## 日志文件

- 日志路径：`%APPDATA%/Factorio/factorio-current.log`
- 诊断标记：`[AMAP-DIAG]`（事件 handler 崩溃定位）
- 自定义标记：在 `log()` 中使用前缀便于搜索，如 `log("[MY-MODULE] result: " .. value)`

## 审查清单

进行离线测试时，对照检查：

- [ ] 是否先跑了 luacheck 静态检查（0 warnings / 0 errors）
- [ ] 无头加载是否通过（无 Error / Lua 报错）
- [ ] RCON 命令是否带 `/c` 前缀
- [ ] 测试代码是否用 `log()` 而非 `print()`
- [ ] 运行时测试是否通过 `_TEST` 全局调用（而非 require）
- [ ] RCON 响应是否持续 drain 收全
- [ ] 测试结果是否在 `factorio-current.log` 中确认
- [ ] `/c` 是否只引用全局（模块局部名 Token/Task 不是全局）
- [ ] pcall 测试是否用 `log()` 捕获错误（而非依赖响应文本）
- [ ] 重启后日志是否出现新行号/新 log 标记（确认不是旧进程）

## 参考

- 场景入口：`control.lua`
- 静态检查配置：`.luacheckrc`（2.1.12 API 校订版）+ `.editorconfig`
- 测试入口：`command_line.lua`（场景根，不在同步目录）
- RCON 驱动：`rcon_driver.py`（场景父目录，不被同步）
- 事件系统：`utils/event_core.lua`（xpcall 诊断钩子）
- Factorio 日志：`%APPDATA%/Factorio/factorio-current.log`
