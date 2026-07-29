---
name: offline-testing-guide
description: 坦克保卫战离线测试指南。提供无头 Factorio 加载测试和 RCON 命令执行测试的完整流程，包括启动命令、关键约束、能力边界等。在验证代码加载、纯逻辑正确性时使用。
---

# 坦克保卫战离线测试指南

## 概述

本地装有 Steam Factorio，无需进游戏即可验证「代码能否加载」以及「纯逻辑是否正确」。

两种测试方法：

| 方法 | 能力 | 耗时 |
|------|------|------|
| 无头加载测试 | 验证能否加载（语法、require、on_init） | ~12 秒 |
| RCON 命令执行 | 在真运行时执行 Lua 逻辑 | ~15 秒启动 + 执行时间 |

## 方法一：无头加载测试

### 用途

验证全部 Lua 文件解析通过、所有 `require` 解析、模块级代码与 `on_init` 执行无错。

### 命令

```powershell
# 在 %APPDATA%/Factorio 下执行
& "C:/Program Files (x86)/Steam/steamapps/common/Factorio/bin/x64/factorio.exe" `
    --start-server-load-scenario 坦克保卫战 `
    --no-log-rotation
```

### 判断标准

- 日志一路到 `Hosting game` / `InGame` 且**无 `Error` / Lua 报错** = 全部通过
- 出现 `Error` 或 Lua 报错 = 有语法错 / require 路径错 / on_init 报错

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

### 启动与执行

```powershell
# 步骤 1：起服务器（建议用 timeout 包住避免常驻）
& "C:/Program Files (x86)/Steam/steamapps/common/Factorio/bin/x64/factorio.exe" `
    --start-server-load-scenario 坦克保卫战 `
    --rcon-port 27015 `
    --rcon-password testpw `
    --no-log-rotation

# 步骤 2：等进 InGame（约 12 秒）后，另一终端执行测试
python rcon_driver.py "_TEST.run_all()"
```

### 相关文件

| 文件 | 位置 | 说明 |
|------|------|------|
| `command_line.lua` | 场景根（不在同步目录） | 加载期 require 真实模块 + 注册测试到全局 `_TEST` |
| `control.lua` 末尾 | 场景根 | `pcall(require, 'command_line')`（生产缺文件时 pcall 静默跳过） |
| `rcon_driver.py` | 场景父目录（不被同步） | Source RCON 客户端，发命令并抓日志标记行 |

### 路径坑

- Python 参数用反斜杠 Windows 路径
- MSYS 会把 `/c/...` 传成 `c:\c\...` 导致找不到文件

### 临时验证

连文件都不用建，直接在真运行时跑任意 Lua：

```powershell
python rcon_driver.py "/c log(serpent.dump(game.forces.player.get_ammo_damage_modifier('laser')))"
```

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

- [ ] 无头加载是否通过（无 Error / Lua 报错）
- [ ] RCON 命令是否带 `/c` 前缀
- [ ] 测试代码是否用 `log()` 而非 `print()`
- [ ] 运行时测试是否通过 `_TEST` 全局调用（而非 require）
- [ ] RCON 响应是否持续 drain 收全
- [ ] 测试结果是否在 `factorio-current.log` 中确认

## 参考

- 场景入口：`control.lua`
- 测试入口：`command_line.lua`（场景根，不在同步目录）
- RCON 驱动：`rcon_driver.py`（场景父目录，不被同步）
- 事件系统：`utils/event_core.lua`（xpcall 诊断钩子）
- Factorio 日志：`%APPDATA%/Factorio/factorio-current.log`
