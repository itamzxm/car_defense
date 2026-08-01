# 坦克保卫战项目规则

## 副本难度设计哲学

**核心原则：每次难度提升只改 2~3 条参数，做 1.0 → 1.2 → 1.44 的线性增量。**

问题：旧版难度设计一次性改了 8~10 个维度（Boss 类型、场地、速度、弹药、掩体、道具种类/间隔、小虫类型/数量），多项乘法叠加导致难度陡升，easy 和 hard 完全不是同一个副本。

**规则：**
1. 每个副本的 easy/normal/hard 之间，只允许 2~3 个维度有差异
2. 其余参数全难度统一（同一 Boss、同一武器、同一弹药量、同一道具配置等）
3. 优先用「场地缩小 + 节奏加快（间隔缩短/波次增多）」这两个维度，它们天然产生梯度且玩家直觉上能理解
4. 不要通过换 Boss 类型、换虫子类型、砍道具种类来提难度——这些是"换了一个副本"，不是"同一个副本更难了"

**竞技场生存（arena_survival）示例：**
- easy → normal：场地 24→18 + 虫子加 spitter + 开始有精英波 + 波次 5→7（3 条）
- normal → hard：场地 18→14 + 波次 7→10（2 条）

**Boss 讨伐（boss_hunt）示例：**
- 全难度统一：Boss big-biter、速度 0.3、弹药 50、掩体 12、道具 12s/5 种、小虫 small
- easy → normal：场地 15→12 + 开始召小虫 30s 间隔（2 条）
- normal → hard：场地 12→10 + 小虫间隔 30s→20s（2 条）

## 核心约束（不可妥协）

- **错误不可掩盖**：禁止用过度 try-catch、默认值兜底、注释或 return 绕过错误。内部逻辑必须让错误正常暴露；仅允许在外部边界（网络请求、用户输入等）做必要容错。
- **改动数字需有依据**：不得随意调整配置数值、参数、版本号。调整前必须明确原因、目标值和依据，不确定时先查文档或询问。
- **改动已有代码前先汇报**：修改现有代码（非新增）前必须向用户说明文件、位置、内容及原因，经批准后方可执行。新增代码无需汇报。
- **求助阈值**：同一问题尝试 2 次仍未解决，必须主动向用户请求帮助。请求时需提供：问题描述、涉及文件路径、当前相关代码调用关系梳理。
- **作用范围上限 24 米**：任何魔法技能、天赋的作用范围，最大有效值就是 24 米。若计算或配置出的范围超过 24 米，一律按 24 米处理；代码中相关数值只能写 `24`，不得写更大的数。非魔法技能，或者天赋，不受这个限制约束。

## 事件过滤器禁止使用

**永远不要给 Event.add 传递 filters 参数。**

原因：异星工厂的 `script.on_event` 对同一事件 ID 只接受**唯一一组**过滤器。`utils/event_core.lua` 中多个模块注册同一事件时，只有**首次**注册的 filters 生效（`Event.add` 实现见 `utils/event_core.lua` `Public.add`：后续 handler 仅追加到 handlers 表，不重新调用 `script.on_event`）。

后果：
- 如果模块 A 先注册 `on_entity_died` 加 car 过滤器，模块 B 后注册同事件加 locomotive 过滤器，则 B 的过滤器会被丢弃且无法生效。
- 反过来，如果模块 B 先注册，A 后注册，则 A 的过滤器也会丢失，导致全局事件被错误过滤。

**正确做法：** 在 handler 函数内部做类型判断，例如：

```lua
-- ❌ 禁止：带过滤器
Event.add(defines.events.on_entity_died, on_entity_died, {
    {filter = 'type', type = {'locomotive', 'cargo-wagon'}}
})

-- ✅ 正确：无过滤器，handler 内 self-filter
Event.add(defines.events.on_entity_died, on_entity_died)

local function on_entity_died(event)
    local entity = event.entity
    if not entity or not entity.valid then return end
    if entity.type ~= 'locomotive' and entity.type ~= 'cargo-wagon' then return end
    -- ...处理逻辑
end
```

**例外：control.lua** 是唯一可以包含过滤器的地方。它在所有模块之前注册统一的 master filter，覆盖所有 handler 需要的 entity type。修改 master filter 时必须确保包含所有 handler 用的类型。

检查点：`Event.add` 调用若出现第三个参数（filters），在非 control.lua 文件中即为违规。

## 文件编码规则

**新建文件用 UTF-8；修改已有文件时先检测原编码并保持一致；出现乱码必须立即修复。**

**绝对不要用 PowerShell 的 `Set-Content` 写入含中文的 Lua 文件。**

`Set-Content` 默认编码不是 UTF-8，会用错误编码读取再写入，导致中文全部乱码（如 `'建造者'` 变成 `'寤洪€犺€?'`），游戏加载时报 `unfinished string` 错误。

**正确做法：**
- 使用 `edit` 工具做精确文本替换，不会改变文件编码
- 如果必须用脚本批量写入，用 `[System.IO.File]::WriteAllBytes()` 读写原始字节
- 备份文件位于 `C:\Users\cm146\AppData\Roaming\Factorio\scenarios\car_defenes_4.4.9\scenarios\car_defense`

**事故记录（2026-07-05）：** 用 `Set-Content` 批量删除事件过滤器，导致 13 个文件中文全部乱码，不得不从备份还原所有文件。教训：对含中文文件，只用 `edit` 工具逐个修改。

## 开发原则

- **追根究底**：遇到 bug 或报错，必须理解其产生原因和原有意图，从根本上解决，而非绕过。
- **按规划推进**：遵循 `开发规划.md` 的任务清单逐模块开发，完成一个并通过自测后再进入下一个，复杂模块可拆分。

## 添加功能前必须先探索

**不要凭局部理解直接写新代码。** 添加任何功能前，必须按以下顺序执行：

1. **搜索已有代码** — 在整个项目中搜索与需求相关的已有函数、变量、事件处理
2. **通读相关函数的完整流程** — 理解数据流、调用链、UI 结构，不要只看片段
3. **确认复用/扩展哪个已有结构，再动手** — 优先找功能类似的代码复制模式，而不是新建

具体场景：
- 需要加检查/奖励逻辑 → 先搜已有的检查/奖励函数，看能否合并进去，不要新建独立函数
- 需要加 GUI → 先看同页面的现有元素格式，保持一致，不要单独开 frame
- 需要加事件处理 → 先找已有的事件处理代码，看放在哪里最合适
- 修改函数后 → 必须验证编辑结果，确认改动生效

反面案例：
- 不要新建独立函数，如果已有同类函数可以合并
- 不要单独开 GUI frame，如果同页面已有列表可以加入
- 不要加 `game.print` 全局公告，除非确认不会重复执行且确实需要
- 不要在没通读完整函数流程前插入代码，容易插入到错误位置

## 其他已知规则

- 本地可离线验证加载/逻辑：用本地 Steam Factorio 无头加载场景 + RCON 执行 `/c` 命令（详见下方「离线测试方法」）。玩法逻辑（天赋触发实时效果）仍须在游戏中测试
- 所有文本修改必须同步中英文 locale 文件
- `require` 只能在文件顶层使用
- 错误日志路径：`factorio-current.log`

## 离线测试方法（本地无头 Factorio）

本地装有 Steam Factorio，其内嵌 Factorio 定制 Lua 5.2 运行时。无需进游戏即可验证「代码能否加载」以及「纯逻辑是否正确」。**多人协作环境差异大，开测前必须先做环境自检。**

### 开测前环境自检（必做）

> 目的：确认「被测场景」就是「项目根」，避免测到旧副本（现象：改了代码但日志 `Checksum for script` 不变）

1. **询问用户游戏目录**（不要假设路径，如 Steam 版可能在 `C:/Program Files (x86)/Steam/...`，本机实测为 `E:\Game\Factorio`），定位 `factorio.exe`（`<游戏根>/bin/x64/factorio.exe`）
2. **检查本项目场景在哪**：`<游戏根>/scenarios/` 下可能同时存在符号链接（实时指向项目根，正确被测对象）与旧副本目录（改代码不生效，**不要用**）
3. **确认符号链接指向项目根**：`Get-Item "<游戏根>\scenarios\<场景目录名>" | Select-Object Name,LinkType,Target` → `LinkType=SymbolicLink` 且 `Target=项目根` 才正确
4. **场景加载名 = 场景目录名**（如符号链接名 `car_defense`），不是项目显示名（旧副本名「坦克保卫战」是坑）
5. **验证加载的是当前代码**：改过代码后日志 `Checksum for script __level__/control.lua` 必须变化；不变 = 加载了旧副本

### 方法一：无头加载测试（验证能否加载）
```
& "<factorio.exe 路径>" --start-server-load-scenario <场景名> --no-log-rotation
```
- 日志一路到 `Hosting game` / `InGame` 且无 `Error` / Lua 报错 = 全部 Lua 文件解析通过、所有 `require` 解析、模块级代码与 `on_init` 执行无错。
- 能查：语法错、`require` 路径错、加载期运行时报错。不能查：玩法逻辑。

### 方法二：RCON 命令执行测试（在真运行时跑逻辑）
原理：本地无头起服务器 + 开 RCON → RCON 发 `/c <Lua>` → 在真·Factorio 运行时执行 → `log()` 写进 `factorio-current.log` 被读取。

**关键约束（踩坑结论）：**
1. **运行时(`/c`)禁止 `require`**（报错 `Require can't be used outside of control.lua parsing`）。测试代码必须在**加载阶段**由 `control.lua` 顶层 `pcall(require, 'command_line')` 载入并注册成全局（如 `_TEST`），`/c` 只调全局、不再 require。
2. **RCON 执行的是控制台命令，跑 Lua 必须带 `/c` 前缀**，否则被当普通命令忽略（无输出无报错）。
3. **`print()` 在无头 `/c` 不写日志**；用 `log()`（日志格式 `Script <expr>:<line>: <msg>`）才进 `factorio-current.log`。
4. RCON 响应分多包到达，客户端要持续 drain 若干秒才收全（见 `rcon_driver.py`）。
5. **Factorio RCON 包体后需 2 个 null 字节**（标准实现只发 1 个会认证失败 id=-1）。
6. **无玩家时 tick 暂停**：默认 `auto_pause=true`，每次 RCON 命令只触发 1 tick 更新，任务逻辑测不准；必须 `--server-settings` 传 `auto_pause: false`。

**相关文件：**
- `command_line.lua`（场景根，git 白名单外不跟踪）：加载期 `require` 真实模块 + 注册测试到全局 `_TEST`；`/c _TEST.run_all()` 执行。
- `control.lua` 末尾：`local ok, err = pcall(require, 'command_line')`（生产缺文件时静默跳过；err 非 not-found 时 log 暴露，不掩盖）。
- `scenarios/rcon_driver.py`（场景父目录，不被同步）：Source RCON 客户端，发命令并抓日志标记行。
- `scenarios/test-server-settings.json`（不被同步）：测试用服务器配置，`auto_pause: false` 为关键项。

**启动与执行：**
```
# 起服务器（建议用 timeout 包住避免常驻；⚠ 必须带 --server-settings）
& "<factorio.exe 路径>" --start-server-load-scenario <场景名> `
    --server-settings "<游戏根>\scenarios\test-server-settings.json" `
    --rcon-port 27015 --rcon-password 123 --no-log-rotation
# 进 InGame(~12s) 后，另一终端：
python rcon_driver.py "/c _TEST.run_all()" 127.0.0.1 27015 123
```
> 路径坑：Python 参数用反斜杠 Windows 路径；MSYS 会把 `/c/...` 传成 `c:\c\...` 导致找不到文件。

**能力边界：**
- 能测（占多数 bug）：纯逻辑——品质映射、`roll` 概率、`qround`/`fmt2` 数学、经验曲线、宠物解锁等级、locale 拼装、模块加载是否成功。
- 不能测：需真实实体/地表/玩家/事件的玩法逻辑（天赋触发实时数值），仍须进游戏 + `game.print` 断点。
- 临时验证连文件都不用建：直接 `python rcon_driver.py "/c <粘贴的代码片段>"` 在真运行时跑任意 Lua。

## 已过时文档（不建议参考）

以下两个文件很可能已失效，内容与当前代码不一致，**AI 开发时不要参考、不要据其做判断**（如需相关信息，以实际代码为准）：

- `可升级技能添加方法.md`
- `数值平衡参考.md`

## 可参考文档（已更新，内容与当前代码一致）

以下文件已更新至最新状态，**AI 开发时可参考**：

- `世界添加说明.md` —— 新世界框架（参照副本框架设计）的字段定义与添加流程
- `魔法技能增加说明.md` —— 新魔法技能设计的字段定义与升级模式说明

## 天赋分类归属规则

**制作任何天赋时，必须将其归入以下 4 个天赋池中的一类：**

1. **战士**（战斗/生存向，偏肉偏伤）
2. **建筑**（建造/生产/资源向）
3. **法师**（魔法术类伤害/法力向）
4. **其他**（不属于以上三类）

**强制要求**：每个天赋在定义时须明确指定其所属池子。若分析后无法清晰匹配到战士/建筑/法师中的任何一类，**默认归入「其他」**，不得强行塞入不合适的池子。

（该归属用于天赋解锁、GUI 分类、技能池划分等逻辑；与「魔法技能/天赋伤害规则」正交——法师池的天赋适用激光/魔力四项影响，其他池不强制。）

## 魔法技能/天赋伤害规则

**适用范围**：所有「魔法术类」造成的直接伤害 —— 即魔法技能、魔法天赋、法术类伤害。非魔法类的物理/爆炸等伤害不适用本规则。

**强制要求**：任何魔法伤害天赋/技能在计算伤害时，必须纳入以下二项影响，缺一不可：

1. **科技加成**：`game.forces.player.get_ammo_damage_modifier("laser") + 1` 和 `game.forces.player.get_gun_speed_modifier('laser') + 1` →最终伤害=伤害*damage_modifier("laser")/speed_modifier('laser')
3. **品质系数**：`COEFF_REG[q_idx]`（普通 1 / 精良 1.2 / 稀有 1.4 / 史诗 1.6 / 传说 1.8）→ 乘进每道/每次伤害

四项的具体纳入方式（如魔力是叠加进基础伤害还是影响命中道数、目标选择是单体还是 AoE 等）由各天赋自身设计决定，按设计实现即可。

## AI 自主决策规则（无拍板环节）

在自主执行模式（如 aios）下，不存在"落地前拍板 / 等你确认"的环节。所有设计歧义由 AI 自行决策并给出可辩护的默认选择，**禁止用"待拍板"式反问把决策推回给用户**。

决策总原则：

1. **字面歧义按最直白解读**：需求中的措辞若有字面含义，直接采用字面解读，不复用其他功能的近似写法脑补。例：需求写"敌方虫子"即 `force='enemy'`，不改成友方宠物写法。
2. **性能 / 稳定性风险主动加保护上限，但保留用户的收益意图**：若按字面实现会导致瞬死、卡顿、实体堆积（DoS）等破坏游戏的问题，实现方有责任主动加安全闸（如刷怪数量封顶），但**不得擅自砍掉用户明确指定的"收益随等级 / 品质缩放"等核心数值意图**。收益与稳定性解耦处理——收益公式全量保留，仅物理生成 / 执行加帽。
3. **细项一律沿用既有项目规则，不自己发明**：取整（如 `qround=math.floor`）、品质系数表（如 `COEFF_REG={1,1.2,1.4,1.6,1.8}`）、定时器 / 冷却机制等，直接复用项目已有约定，不另起一套。
4. **描述文本维持用户原措辞**：保护上限、内部解耦等技术处理只记在代码注释里，不污染玩家可见的 locale 文案。

适用边界：以上规则用于"需求明确但存在实现歧义 / 风险"的场景。若需求本身矛盾、缺失关键前提、或触及上方"核心约束"，仍按对应规则处理（如改动已有代码前先汇报、求助阈值等）。
