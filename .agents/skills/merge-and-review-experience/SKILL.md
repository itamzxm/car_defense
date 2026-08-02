---
name: merge-and-review-experience
description: 坦克保卫战合并审查与踩坑经验总结。提炼自 commit 5f1fe56 以来 47 次提交的真实教训，覆盖上游合并审查、天赋系统修复、locale 规范、nil 安全、pcall 误用、底层基建冻结等。在合并外部代码、审查 PR、修复天赋/副本 bug 时使用。
---

# 坦克保卫战合并审查与踩坑经验

> 本文档提炼自 commit `5f1fe56` 以来 47 次提交的真实教训，按主题分类，供后续开发参考。

---

## 1. 上游合并审查（最易踩坑）

### 1.1 locale section 混入 amap.cfg

**事故**：上游将 `[icw]` 和 `[magic_wood]` section 追加到 `amap.cfg` 末尾，而项目已有独立文件 `icw.cfg` / `magic_wood.cfg`。

**违反规范**：一文件一 section（locale-i18n-guide）

**教训**：
- 合并上游后**必须检查 amap.cfg 是否混入了非 `[amap]` section**
- 发现后立即删除，独立文件已有则不保留重复
- Factorio 后加载者覆盖同名 section，重复 section 不会报错但语义混乱

### 1.2 locale 键名空格不一致

**事故**：`world15_boss_kill=玩家__1__ 击杀第__2__波` — `__1__` 后有空格但 `__2__` 后没有。

**教训**：
- 合并后逐条检查新增 locale 键的排版一致性
- 中英两文件中参数占位符周围的空格风格应统一

### 1.3 合并引入的代码必须过规范审查

**事故**：JIAOLH-GIT 合并引入了硬编码中文 `game.print`、内联 GUI 元素名、直接 `Event.add(on_gui_click)` 等违规代码。

**教训**：
- **合并 ≠ 信任**：合并后必须对引入代码做完整规范审查
- 审查清单：Event.add filters → GuiDispatcher → locale 引用 → GUI 元素名常量化 → nil 安全
- 修复提交单独做，不在合并提交中混修

### 1.4 撤回 PR 的残留代码

**事故**：PR #1 撤回时只移除了 `tianfu_jiange` 字段声明，但保留了查询代码，导致天赋间隔从 15 级回退为默认 35 级。

**教训**：
- 撤回/禁用功能时，**搜索所有引用点**，确认无残留
- 字段声明与查询代码必须同生同灭
- 重新启用时补回声明并注释说明原因

---

## 2. 天赋系统修复经验

### 2.1 副本天赋补偿 tianfu_count

**事故**：副本 `grant_tianfu` 调用 `get_new_tianfu` 后未做 `tianfu_count - 1` 补偿，导致副本天赋净增 `tianfu_count + 1`，吞掉升级天赋档位。

**教训**：
- `get_new_tianfu` 会自增 `tianfu_count`，外部调用后若不希望占用升级档位，**必须立即补偿 -1**
- 同模式参考：`rock.lua` / `diff.lua` 购买天赋均做了补偿

### 2.2 移速加成必须走 PlayerModifiers

**事故**：独狼/疾风步/疾跑直接对 `character_running_speed_modifier` 做加法，绕过 PlayerModifiers 系统，任何 `update_player_stats` 调用都会覆写该属性。

**教训**：
- **所有 modifier 加成必须通过 `PlayerModifiers.update_single_modifier` 注册**，由 `update_player_modifiers` 统一刷写
- 直接赋值 `character.xxx_modifier` 会被后续全量刷写覆盖，属静默 bug
- 移除时精确置 0 + 刷写对应分类，不做全量重算

### 2.3 属性变更后必须刷新 modifier

**事故**：失心疯/降敏捷修改 `rpg_t.dexterity` 后未调用 `update_player_stats`，敏捷变化不反映到实际 modifier。

**教训**：
- 修改 RPG 属性（力量/活力/敏捷/魔法/生命）后**必须调用 `update_player_stats`**
- 否则天赋效果"虚增"——数值变了但 modifier 没刷

### 2.4 locale 数值与代码不一致

**事故**：商店天赋 locale 写"最多购买 30 个"，代码实际限制 25；失心疯 locale 写"90 个虫子/45 秒"，代码实际 30/30。

**教训**：
- **locale 中的数值必须与代码实际限制一致**，修改代码时同步检查 locale
- 这是玩家可感知的 bug：提示说 30 但第 25 次就被拒

### 2.5 天赋上限静默无反馈

**事故**：顶尖人才达 24 上限后静默 return，玩家不知道天赋已停止生效；帝国卫队炮塔未创建仍提示"护卫来了！"。

**教训**：
- 天赋达到上限时**必须给玩家明确提示**（new_print + locale 键）
- 操作失败时打印失败消息，成功时打印成功消息，**不可混用**

### 2.6 Task.set_timeout_in_ticks 参数传反

**事故**：附魔/驯兽师从帝国卫队复制代码时，回调与数据参数传反，`{entity}` 作为回调、`forces`（nil）作为数据，timeout 到期时崩溃。

**教训**：
- **复制代码后必须逐参数核对**，特别是 Token 回调 vs 数据参数的顺序
- `Task.set_timeout_in_ticks(ticks, callback_token, data)` — 第二个是 Token 注册的函数，第三个是数据表
- `forces` 变量在原函数中有声明，复制到新函数后若未声明则为 nil

---

## 3. nil 安全与错误处理

### 3.1 rpg_t[player.index] nil 守卫

**事故**：顶尖人才/帝国卫队直接访问 `rpg_t[player.index]`，条目不存在时崩溃。

**教训**：
- 访问 `rpg_t[player.index]` 前**必须做 nil 检查**，返回 false
- 模式：`local stats = rpg_t[player.index]; if not stats then return false end`

### 3.2 create_entity 返回值必须检查

**事故**：magic_wood 降级传说木箱时 `create_entity` 返回 nil 未检查，玩家凭空丢失传说木箱。

**教训**：
- `surface.create_entity()` **可能返回 nil**（位置被占/条件不满足等）
- 返回值必须检查：`if not entity then log(...); return end`

### 3.3 pcall 空分支必须 log

**事故**：资深专家 pcall `set_recipe` 捕获错误后静默吞掉，违反"错误不可掩盖"规则。

**教训**：
- pcall 保留（预期场景如锅炉不支持配方），但**空分支必须 `log` 错误信息**
- 格式：`log("[模块名] pcall set_recipe failed: " .. tostring(err) .. " entity=" .. tostring(entity.name))`
- pcall 不等于掩盖，空分支 = 信息丢失

### 3.4 多余 pcall 移除

**事故**：world17 GUI 中 `World.get_field` 被 pcall 包裹，但该函数对未注册世界返回 nil 不报错，pcall 反而吞掉潜在错误。

**教训**：
- **函数本身不会报错时不需要 pcall**，pcall 只用于可能抛错的 API 调用
- 判断标准：该函数是否会在正常输入下抛出 Lua error？

---

## 4. GUI 与 locale 规范

### 4.1 GUI 元素名必须常量化

**事故**：world_15 使用内联字符串作为 GUI 元素名，与常量不一致导致天赋框无法销毁。

**教训**：
- **所有 GUI 元素名必须提取为局部常量**，格式 `dungeon_<缩写>_<功能>`
- 元素名在创建和销毁处必须引用同一常量，内联字符串极易拼写不一致

### 4.2 硬编码中文 → locale 引用

**事故**：world_15 中 4 处 `game.print('中文')` 硬编码文本。

**教训**：
- **禁止硬编码中文**，统一用 `{'amap.xxx'}` locale 引用
- 中英 locale 同步新增对应键

### 4.3 品质名硬编码字典 → Factorio 内置 locale

**事故**：world_15 用 `W15_QUALITY_CN = {普通, 精良, ...}` 硬编码中文品质名。

**教训**：
- 品质名/科技名等 Factorio 内置概念**使用内置 locale 键**：`quality-name.*` / `technology-name.*`
- 不自建中文映射表

---

## 5. 底层与架构

### 5.1 底层基建冻结

**事件**：底层基建终极维护完成，`utils/` 核心工具进入冻结状态。

**规则**：
- 新增/修改冻结对象需说明原因 + 目标值 + 依据，并经确认
- **禁止绕过确认直接改底层、另起炉灶重写**
- 业务层（`maps/amap`、`modules`）不受冻结限制

### 5.2 全局变量加项目前缀

**事故**：world17 RCON 全局入口 `_GRID` 可能与其他模块冲突。

**教训**：
- **RCON 全局入口必须加项目前缀**：`_CAR_DEFENSE_GRID` 而非 `_GRID`
- 避免命名空间污染

### 5.3 ChartTag 残留清理

**事故**：1000 波销毁组装机时直接清空表，但 `factory.tag` 对应的 ChartTag 未调用 `destroy()`，地图标签永久残留。

**教训**：
- **销毁实体关联的 ChartTag 时，必须先 `tag.destroy()` 再清表**
- 模式：遍历 → destroy → 清空表

---

## 6. 代码质量与格式

### 6.1 luacheck 格式警告批量消除

**事件**：67 文件 2055 处 W611/W612/W614 格式警告一次性清零。

**规则**：
- W611：仅含空白字符的行 → 清为空行
- W612：行尾多余空白 → 去除
- W614：注释行尾空白 → 去除
- **新代码提交前跑 luacheck**，格式警告应为 0

### 6.2 函数末尾显式 return

**事故**：帝国卫队函数末尾无显式 return，调用方无法判断成功/失败。

**教训**：
- 天赋/技能函数**末尾必须有显式 `return false`**（成功路径 `return true`）
- 调用方可根据返回值做分支处理

### 6.3 循环内消息 → 循环外一次

**事故**：帝国卫队 `new_print` 在循环内调用 k 次（k 最高 15），虽有 30 tick 防刷屏仍应移到循环外。

**教训**：
- **消息打印移到循环外**，一次打印含实际数量
- 成功/失败分支分别打印不同 locale 键

---

## 7. 合并操作流程规范

### 7.1 合并前

1. `git fetch upstream`
2. `git log origin/master..upstream/master` 查看上游领先提交
3. 逐 commit 阅读 diff，预判冲突点

### 7.2 合并中

1. `git merge upstream/master`
2. 冲突解决原则：**以本地代码为主**，上游新增内容采纳但需过规范审查
3. 逐文件检查冲突标记是否清除

### 7.3 合并后（必做）

1. **规范审查**：对合并引入的所有变更逐项对照 AGENTS.md 审查
2. **locale 检查**：
   - amap.cfg 是否混入非 `[amap]` section
   - 新增键名格式是否为 `amap.<功能域>_<描述>`
   - 中英参数占位符数量/顺序是否一致
   - 空格排版是否统一
3. **代码检查**：
   - Event.add 是否有 filters 参数
   - GUI 事件是否走 GuiDispatcher
   - 元素名是否常量化
   - 是否有硬编码中文
   - nil 安全是否完备
4. **单独提交修复**，不在合并提交中混修

---

## 8. 提交信息规范

### 8.1 格式：Conventional Commits

项目采用 [Conventional Commits](https://www.conventionalcommits.org/) 规范，格式：

```
type(scope): 简述
```

#### type（必填）

| type | 用途 | 示例 |
|------|------|------|
| `feat` | 新功能/新内容 | `feat(wave_defense): 威胁 tooltip 分行显示敌方 5 种伤害加成` |
| `fix` | Bug 修复 | `fix(tianfu): 失心疯 locale 数值纠正 + 敏捷变更后刷新 modifier` |
| `perf` | 性能优化 | `perf(diff): 倒排索引替代全扫描查找世界加成` |
| `refactor` | 重构（不改行为） | `refactor(gui): 世界奖励面板提取为独立函数` |
| `style` | 格式修改（不影响逻辑） | `style: 批量消除全项目W611/W612/W614格式警告（67文件2055处）` |
| `docs` | 文档更新 | `docs: 更新 AGENTS.md 底层冻结宣言` |
| `test` | 测试相关 | `test(queue): 添加环形队列边界用例` |
| `chore` | 构建/工具/杂务 | `chore: 更新 .luacheckrc 忽略规则` |

#### scope（推荐填写）

用中文拼音缩写或模块名，标明影响范围：

| scope | 含义 | 示例 |
|-------|------|------|
| `tianfu` | 天赋系统 | `fix(tianfu): 独狼移速改用 PlayerModifiers` |
| `djrc` | 顶尖人才 | `fix(djrc): 上限反馈 + nil安全` |
| `dgwd` | 帝国卫队 | `fix(dgwd): 炮塔未创建仍提示成功` |
| `fumo` | 附魔 | `fix(fumo): Task.set_timeout_in_ticks 参数传反` |
| `xunshoushi` | 驯兽师 | `fix(xunshoushi): Task.set_timeout_in_ticks 参数传反` |
| `tishenshu` | 替身术 | `fix(tishenshu): 传送失败添加提示并扩大搜索重试` |
| `duoduoyishan` | 多多益善 | `feat(duoduoyishan): 添加属性门槛与家附近不触发限制` |
| `zishenzhuanjia` | 资深专家 | `fix(zishenzhuanjia): pcall空分支添加log` |
| `locale` | 本地化文件 | `fix(locale): 商店天赋购买上限描述与代码一致（30→25）` |
| `diff` | 难度/加成 | `fix(diff): 1000波摧毁组装机时清除残留的 chart tag` |
| `world` | 世界通用 | `fix(world): 补回 tianfu_jiange=15 声明` |
| `world15` | 世界15（塔防） | `feat(world15): 投票系统升级` |
| `world17` | 世界17（网格战争） | `fix(world17): 移除多余pcall` |
| `instance` | 副本框架 | `fix(instance): 副本奖励天赋补偿 tianfu_count` |
| `wave_defense` | 波次防御 | `feat(wave_defense): 威胁 tooltip 分行显示` |
| `gui` | GUI 系统 | `refactor(gui): 元素名常量化` |
| `utils` | 工具库 | `feat(utils): 底层基建终极维护` |

多个 scope 用逗号分隔：`fix(fumo,xunshoushi): Task.set_timeout_in_ticks 参数传反导致崩溃`

### 8.2 简述要求

1. **中文撰写**，简明扼要（一行内，不超过 72 字符）
2. **动词开头**：修复/添加/移除/改用/补回/纠正/刷新/消除/提取/重构
3. **多改动用 `+` 连接**：`fix(djrc): 上限反馈 + 消息增强 + nil安全 + 返回值修正`
4. **禁止混合 type**：同一提交同时含 fix 和 style 时，**拆分为两个提交**而非写 `fix+style`。先提交 fix，再提交 style
5. **关键数值/文件数放括号内**：`style: 批量消除全项目W611/W612/W614格式警告（67文件2055处）`

### 8.3 提交 body（可选但推荐）

复杂修复应在 body 中说明：

```
fix(tianfu): 魔力之泉改为在 regen_mana_player 中放行战斗回蓝，修复触发间隔过长问题

魔力之泉描述"受伤时正常回蓝×2倍"，但原实现为 time_skill 每60秒触发一次，
60秒内加魔力量仅为正常回蓝(每30tick)的 1/120，几乎无效。

修复方案：
- regen_mana_player 中检测 mlzq 天赋，战斗中放行回蓝并乘 2×品质系数
- 原 mlzq time_skill 函数退化为 no-op，保留注册以兼容存档/GUI
```

### 8.4 禁止的提交信息

| 禁止 | 原因 | 正确做法 |
|------|------|----------|
| `car_defense auto sync` | 无 type/scope，无法分类 | 拆分为具体 type(scope): 描述 |
| `update xxx.lua` | 无 type，描述模糊 | `fix(world15): 具体修复内容` |
| `fix: 修复bug` | 描述无信息量 | `fix(dgwd): 炮塔未创建仍提示成功` |
| `wip` / `tmp` | 不得提交半成品 | 完成后再提交 |
| `fix+style` 混合 type | CC 规范只允许一个 type | 拆分为 fix 提交 + style 提交 |
| 合并提交中混修 | 合并与修复职责不同 | 合并提交 + 单独修复提交 |

### 8.5 合并提交信息

合并提交**不遵循 Conventional Commits**，使用 git 默认格式即可：

```
Merge remote-tracking branch 'upstream/master'
```

这是例外：合并是跨分支操作，无法归入单一 type(scope)。合并后的规范修复必须**单独提交**（遵循 CC），不在合并提交信息中描述修复内容。

---

## 提交历史索引（5f1fe56 以来）

| 提交 | 类型 | 关键教训 |
|------|------|----------|
| `e9b5dba` | feat | 底层基建终极维护，6 工具模块 + 测试框架 + 冻结宣言 |
| `ae7f539` | fix | 副本天赋补偿 tianfu_count，不占升级档位 |
| `f3c1524` | fix | 撤回 PR 残留：补回 tianfu_jiange=15 声明 |
| `ee5fb58` | fix | 魔力之泉：time_skill 60s 间隔几乎无效，改 regen_mana 放行 |
| `a953fbb` | fix | world17：移除多余 pcall + 全局变量加前缀 |
| `89838f3` | fix | 合并后审查：元素名常量化 + 硬编码中文→locale + GuiDispatcher |
| `dccc567` | fix | ChartTag 残留：destroy() 再清表 |
| `ce5d1df` | fix | 移速加成改用 PlayerModifiers，直接赋值会被覆写 |
| `96e63c8` | fix | 属性变更后必须 update_player_stats + locale 数值纠正 |
| `b35249c` | fix | locale 数值与代码不一致（30→25） |
| `3dce8aa` | fix | 替身术：搜索失败扩大重试 + 远程视图守卫 |
| `972612f` | feat | 多多益善：属性门槛 + 家附近不触发 |
| `1018900` | feat | 威胁 tooltip 分行显示 5 种伤害加成 |
| `c360879` | fix | 顶尖人才：上限反馈 + nil 安全 + 返回值修正 |
| `7b2fe0a` | fix | 帝国卫队：炮塔未创建仍提示成功 + nil 安全 + 消息防刷屏 |
| `f0d6fb7` | fix | Task.set_timeout_in_ticks 参数传反导致崩溃 |
| `c6c2e5e` | fix→style | pcall空分支添加 log（fix）+ 批量消除格式警告（style，应拆分） |
| `5e729e8` | style | 全项目 67 文件 2055 处格式警告清零 |
| `d3a11e2` | fix | 移除 amap.cfg 重复 section + locale 空格修复 |
