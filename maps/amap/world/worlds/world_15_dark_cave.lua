-- maps/amap/world/worlds/world_15_dark_cave.lua
-- 世界 15：黑暗地穴
--
-- 设定（按用户需求逐条落实，全部只在世界 15 内生效）：
--  1. 全图永远黑夜 ~84% 黑（夜窗 0.001~0.999 几乎铺满昼夜周期 + min_brightness=0.16 + 亮度权重=1；
--     时间保持流动以便汽车大灯等夜控生效，任何相位都处于黑夜，灯光外可隐约看到地形/实体轮廓）；
--     所有品质夜视仪禁装（2.1.17 事件级弹出：放入瞬间被取出销毁，见规则 17）。
--  2. 黑暗出虫：玩家处于「无灯光覆盖」且出生圆（288 直径）外超过 5 秒（2026-09 用户 3s→5s）→ 按当前波次出「一整波」虫子
--     （单波数量 = floor((32 + floor(波次*0.1)) * 0.8)，公式自身封顶 51；DARK_SPAWN_CAP 仅作稳定性护栏）。
--  3. 地形：出生点 288 直径圆 = 正常山谷地形（无黑暗出虫）；圆外由「石头带 + 黑暗地块(不可通行)」
--     + 「大随机湖泊」组成，三者随机生成，共同限制路径；
--     黑暗地块 = 单低频噪声 + 扩张 2 格 → 大块连续、占比 ~50%；
--     湖面积 = 2800 × 随机倍数 4~10（11200~28000 格，老湖 4~10 倍）、水域 = 0.35~0.42×湖面积；
--     湖形 = 椭圆拉伸（长宽比 1.2~4.0、随机主轴）→ 不规则长条形 + 多频噪声扰动，星形单连通（一湖绝不分块）；
--     网格 330、2/3 概率出湖（2000×2000 约 22~24 个，为上一版 2/3），湖与湖不相交；
--     每湖必有 1 / 2 个（70% / 30%，2026-10 用户：原各 50%）「可购买的产矿市场」（资源岛），虫巢沿湖岸草地随机成团分布（疏密不均）；
--     野外精良市场可在石头带或湖岸草地上生成（与资源岛落点保持距离）。
--     全图取消悬崖（实体级：区块生成时摧毁 cliff；原 cliff_settings 归零写法会杀死石油，已弃用）。
--  4. 资源：除石油外无可开采矿物自动生成（挖掘石头产物除外）；石油 = 引擎 autoplace 自然生成
--     （3/2/4 = 频率/尺寸/丰度，2026-09 用户从 2/2/4 上调；与地图19的4/4/4同一机制，
--     配置见 WORLD15_SURFACE_CONFIG）；
--     2026-09 终版（用户指示「学习地图19，石头地下生成石油」）：石头带不覆盖任何瓦片
--     （旧版铺 dirt-7 属使错力——批量改瓦片既复杂又会被引擎连带摧毁相邻油田），保留原生地表，
--     岩石直接长在自然地表上（石头下/旁即天然油田），与地图19石头带同一机制；
--     出生区缩小 starting_area=0.5（油 has_starting_area_placement=false，原 1.4 把油全推在
--     240+ 格外——玩家看不到油的根因之一；0.5 后 ~64~96 格起就可见油）；
--     黑暗地块仍铺 out-of-map（本图招牌），其上的油田 + 8 邻域跳过铺地保留 3×3 原生孤岛
--     （见 is_near_retained_oil，dark/lake_water 分支共用）；
--     石头带岩石密度 = 山谷 3 倍 × 2 × 1.5 = 36%（2026-09 用户要求密度 ×1.5）；
--     除出生点/湖泊外不生成水域（2026-09 用户要求）：石头带引擎原生水塘就地转 grass-1；
--     挖石头掉落铁50/铜34/煤26/石20/铀4/钨2/废料3；挖石概率生成矿脉改为 1×1 储量 10M 单矿
--     （概率 1/768 → 1/99 → 1/74，2026-09 用户确认在原基础上增加 1/3）；木质宝箱概率 1/75 → 1/50 → 1/20
--     （挖石出木箱，不再换皮钢箱）；自带史诗好运连连（其钢箱为品质掉落，概率 1/200 → 1/50）。
--  5. （2026-10 已由规则 40① 取消）原：挖石头出产随在线人数 +10%/人 加成，并叠加采矿产能科技。
--  6. 建筑机器人禁止开采石头（红图石头无效），提示「黑暗地穴只能手动挖掘石头」。
--  7. 果冻果 / 玉马果草星地块（2026-09 用户两次修正后定稿）：取消湖岸生成，只在出生点圈内
--     随机生成，共 2 块（果冻果 ×1 + 玉马果 ×1）；每块 6×6 全铺对应草星土壤 + 种 4 棵草星树
--     （每树占地 3×3，2×2 阵列不重叠；原「每格种满」过密，用户要求 4 棵/块）。
--  8. 出生市场商品、市场照明（2026-09 逐字照搬本地存档「跃迁1」scripts/market.lua 设计）：
--     hidden-electric-energy-interface 与市场同格重叠（1GJ 缓冲 / 1MW 输出 / usage 0，不可见无碰撞），
--     市场左右 ±2 各 1 根木电线杆、四对角 (±2,±2) 各 1 盏灯，自动接线常亮；
--     卖矿得金币（1 组 2 金）、木制电线杆与灯永久售卖（2026-09 用户改价：各 20 金/个，
--     随机市场池同名商品被剔除避免双价并存）。
--  9. 雷神地宫废墟 / 大型火山岩 / 铁铜叠层石（可挖掘点亮科技）：不在出生圈固定放 4 个，
--     改在湖岸随机生成：火山岩/叠层石按 ~0.7% 岸格概率成团；地宫废墟（fulgoran-ruin-vault，
--     14×8 格，挖掉触发「回收」科技并掉大量废料/钢板）每湖 50% 概率放 1 个（开阔岸草选点，
--     避开水缘/市场/植物地块/油田）。按用户要求不再生成「中型雷神废墟」(fulgoran-ruin-medium)；
--     出生圆内唯一 1×1 10k 方解石矿不变。
-- 10. 出生市场卖矿得金币；失落之城式「矿物回收箱」每 6 秒回收矿物，1 组 = 1 金币分给所有人；
--     回收箱位于出生市场与发射井连线中点（两者都就绪才放，缺失持续重试并记诊断日志）；
--     回收成功只飘箱上文字，不再全图公告（用户要求）。
--     （2026-09 修正：原等 chunk(0,16) 生成——该区块永不生成，箱永不放置；改等 chunk(0,0)；
--     箱子本体由普通钢箱改为传说钢箱，见 world15_place_recycle_box。）
-- 11. 波虫间隔 ×1.5；不自动出波虫（只显示波次，供观看/其他功能调用）；波虫由黑暗出虫机制承担。
-- 12. 堡垒 250 波 → 500 波出现（enemy_arty start_wave 字段）；与山谷同款每次生成 1 个
--     （共享 default 模式随机搜索，fortress_count=1，无本模块包装，见规则 35）；
--     存活堡垒 ≥4 时创建敌方核弹发射井（每 3 分钟发射）（2026-10 用户：9 → 4）。
--     （2026-09 用户要求：堡垒生成无视黑暗地块——fortress_position_valid 只排除深水。）
--     堡垒生成间隔 ×2（2026-09 用户要求，arty_settings.interval 20 → 40）。
-- 12b. 堡垒生成间隔 = interval×60 秒（enemy_arty get_new_arty 每 60s 计一次）：
--     interval 20 → 40（约 20 分钟 → 40 分钟一座，2026-09 用户要求 ×2）。
-- 13. 野外白嫖建筑（二级组装机/电炉等生产球机制）恢复启用（enable_wild_factorio=true）；
--     野外市场每件商品出 普通/精良/稀有 三档，价 = 原价×1 / ×2 / ×5（卖矿换币条目不复制品质）。
-- 14. 开局等待 7200s；背包 +100；挖掘 +200%；除悬崖炸药外无解锁科技（开局强制研发的
--     高级星岩处理/星岩再处理在首个 [60] tick 撤销）；科技倍率 ×2（technology_price_multiplier，
--     2026-09 用户 ×2 → ×3 → 改回 ×2）。
-- 15. 天赋规则同世界 19：45 级 +1、科技瓶 → 天赋、上限 60；但自带天赋改为史诗好运连连。
-- 16. 汽车内买矿不生成水（disable_car_water_generation 字段）。
-- 17. 夜视仪禁装（用户确认方案A+销毁）：任意品质夜视仪放入装备格（角色/装甲/坦克/蜘蛛载具）
--     的同一 tick 即被 on_player_placed_equipment / on_equipment_inserted 事件取出并销毁；
--     [30]tick 扫描兜底处理跨世界已穿戴的夜视仪。火车（机车）在 2.x 无装备网格，本就装不了。
--     （旧「就地禁用」方案在 2.1.17 全面失效：LuaEquipmentGrid 无 child_grid、
--     LuaEquipment 无 enabled、intensity 只读——见用户游戏日志实证。）
-- 18. 箱子开荒（用户 2026-09 三次修正后定稿）：任意箱子（container 类）被任意武器/虫子打爆
--     （即死亡事件，不限死因；开采/拆除不触发）且箱内炸药 ≥250 时，炸药 ÷250 取整 = N，
--     转化 N 块 1×1 黑暗地块(out-of-map)为草地（逐块取距箱子 6 格平距内最近者，并列随机；
--     不足 N 块则转多少算多少）。damaged+died 双事件判定、unit_number 去重、失败记诊断日志。
--     背景：原版 2.1 爆炸不改变地形、填海材料 tile_condition 白名单只含六种水面，
--     均无法作用于 out-of-map；脚本 set_tiles 是唯一"游戏内"可行通道（世界21 扩张同源）。
--     通关达成后本存档不再统计吞噬/结算/公告（规则 24 补充）。
-- 19. 黑暗地块禁虫（用户要求）：黑暗出虫的每个落点强制校验非 out-of-map 瓦片
--     （find_non_colliding_position 会返回黑暗边缘格、旧版兜底更是直接贴脸盲生），
--     玩家四周 4 格内找不到合格落点的个体放弃生成；回收公告消息按实际生成数播报。
-- 20. 悬崖与石油（2026-09 根因修复）：原 cliff_settings 归零写法致全图高程=0，
--     autoplace 石油判定失败（=0）——map_settings 恢复 nauvis 默认 cliff_settings，
--     悬崖改在 on_chunk_generated 实体级摧毁（含出生圆），石油随高程恢复正常。
-- 21. 点亮黄瓶（utility-science-pack）→ 解除「新地星」气压限制（2026-09 用户两次修正后定稿）：
--     不创建任何星球地表、不点亮 planet-discovery 科技、不解其他星球/太空限制（遵循原版）；
--     只把本图主地表（nauvis=新地星）ignore_surface_conditions=true → 主地图建什么都不被限制。
--     火星（vulcanus）煤分布 -50% 跟随原版研究路径：玩家研究 planet-discovery-vulcanus 时
--     functions.lua 创建地表，随后本模块把其煤 autoplace 频率减半（pending + [60] tick 兜底）。
-- 22. 本图限制世界奖励传说木箱的使用（2026-09）：disable_legendary_wood_chest=true
--     （magic_wood.lua 消费：放置即降级为普通木箱）。
-- 23. 白嫖组装机/电炉产量翻倍（2026-09）：world15_double_production 在共享 [60] tick
--     再补一份 progress（=每秒 2 基础秒进度），覆盖 productionsphere.assemblers 与
--     train_assemblers 全部工厂（不碰共享 production.lua）。
-- 24. 通关回收箱（2026-09 两次修正后定稿）：照搬存档「黑暗1」12 箱布局——左右两组各
--     3 列 × 2 行传说钢箱，每列上下各 1 个绿色装载机（turbo-loader，方向与存档一致，
--     筛选 12 种科研瓶各对应 1 箱：上排红/绿/灰/蓝/紫/黄、下排草/橙/白/粉/靛/黑）；
--     瓶子进入即被吞噬（每分钟一次，记录数量）；每 10 分钟结算：每种瓶 12 箱合计
--     ≥140000 且 12 箱累计各 ≥140000 → 窗口达成；连续 3 次 → 公告通关。
--     箱子与装载机不可摧毁/不可开采/不可点击；左右组中间上方各 1 个「通关回收箱」名字。
-- 25. 开采玉玛果树/果冻茎株/方解石点亮对应科技（2026-09 两次修正后定稿）：实测映射
--     yumako-tree→yumako、jellystem→jellynut、calcite→calcite-processing。
--     第一次实现挂 on_player_mined_entity 实测完全不触发——该事件被 comfy_panel/score.lua
--     引擎级 filters 全局过滤（首个注册者，无 plant/resource）；改走 on_pre_player_mined_item
--     （全项目无 filters 注册、文档明示资源矿逐次触发），并保留 MINE_TECH_LIT_EXTRA 显式兜底。
-- 26. 天赋双倍价格（2026-09 用户曾要求 ×2，随后取消改回 1 倍）：出生市场与岛屿市场的
--     「购买天赋」条目维持原价（普通65000/中级90000/高级130000、岛屿 buy_tianfu 65000）。
-- 27. 科技倍率 ×2（研究成本 ×2；2026-09 曾 ×2→×3，本次用户改回 ×2）。
-- 28. 换图全黑修复（2026-09 用户反馈「15图打完切下张图全黑」）：world15_enforce_night 设置的
--     地表级光照属性（daytime_parameters/brightness_visual_weights/min_brightness/
--     solar_power_multiplier）在 soft_reset_map 换图时不会被 surface.clear() 重置，残留到下一张图
--     → 全黑 + 太阳能失效。进入世界15时保存原始光照，离开后由本模块自注册 [60]tick 一次性还原
--     （仅世界15文件内完成，不动共享代码；在世界15内该清理是 no-op，不影响全黑视野）。
-- 29. （2026-10 已由规则 40② 再调整）原：挖石木箱概率减半：wood_chest_chance 20 → 40（1/20 → 1/40）。
-- 30. 初始补给 + 灯价下调 + 禁照明灯配方/科技（2026-09 用户）：进入世界15每人送
--     10×small-lamp + 10×small-electric-pole（后加入补发，每次进入重置）；出生市场灯价
--     20→10 金币；禁用配方 small-lamp + 科技 lamp（无法选择配方/制造/研究）。
-- 31. 木箱开荒门槛放宽：炸药 ÷50 取整转化黑暗地块（原 ÷250）。
-- 32. 换图污染修复（2026-09 用户反馈「其它地图出生市场没了购买伤害栏」）：根因是共享
--     maps/amap/diff.lua reset_table 里遗留测试值 map.world=15（TEMP-TEST-REVERT-ME），
--     已还原为 1；本文件 hook（rock._on_shop_refreshed → world15_shop_refresh）另加
--     diff.get('world')==15 双保险，杜绝误伤其他世界的市场。
-- 33. 出生市场伤害两栏 ×4（2026-09 用户）：「削弱敌方虫子伤害」（buy_health_wall）与
--     「重炮伤害」（buy_arty_dam）售价改为该栏动态基础价的 4 倍（仅世界15 出生市场）。
-- 34. 玩家头顶探照灯自动开关（2026-09 用户）：无照明灯覆盖→自动 enable_flashlight（照亮
--     视野），进入照明灯范围→自动 disable；手电不是 lamp 实体、不参与黑暗判定→黑暗停留
--     满 5s 照样出虫。（汽车/坦克/蜘蛛的车载大灯由引擎按黑夜自动亮，脚本无开关 API，
--     用户确认该部分不做。）
-- 35. 堡垒生成 = 山谷同款「每次 1 座」（2026-10 用户：连续两版并列方案实测都出问题，放弃并列，
--     改回共享 default 模式）：enemy_arty 每事件用随机搜索 get_baolei_pos 生成 1 座
--     （fortress_count=1，落点由共享决定，本模块不改位置）。落点避让 = 共享 is_sh_conflict
--     （玩家建筑 110 格 / 既有 roboport 48 格）+ 本模块 fortress_position_valid 世界15 地形
--     约束（深水排除 + roboport 52 格兜底；黑暗地块允许——见规则 37 铺地修复）。
--     核弹阈值 ≥4（world15_fortress_monitor，2026-10 用户：9 → 4），每 3 分钟发射。
--     全程世界15 文件内，不改共享代码。
-- 37. 堡垒黑暗区半边空修复（2026-10 用户实测）：out-of-map 虚空瓦片 can_place_entity=false
--     （离线探针实证），共享堡垒只铺中心 ±22 sand，越过此范围的黑暗部分（外墙 ±24/地雷 ±27）
--     仍 out-of-map → 墙/炮塔建不出。本模块加薄包装 enemy_arty.baolei：仅世界15、不改落点，
--     在交共享建造前强制生成落点区块并把占地区（半径 30）内 out-of-map 铺成 sand-1 实地
--     → 黑暗区也能建全（保留规则 12「无视黑暗地块」）。只 out-of-map→sand，不碰水/油。
-- 38. 双层石墙说明（非 bug）：共享 enemy_arty `out_wall = wave_number >= 500` 才建外层墙。
--     世界15 start_wave=500 → 每座堡垒必 2 层墙；其他图 250~499 波出堡为单层。若需世界15 单层，
--     只能改共享 out_wall 判定（触共享代码），本图未做。
-- 39. 世界15残留视觉跨世界清理（2026-10 用户实测「通关回收箱两队红字溢出到别的图」后修复）：
--     rendering.draw_text（clear_tags 组名红字 / recycle_tag 回收箱红字）与 player.gui
--     （clear_progress 左侧通关进度红字）都不随 soft_reset 的 surface.clear()/chart_tag 清除，
--     原销毁只写在 on_world_start（进15才触发，框架无 on_world_exit）→ 离开15后残留。新增
--     world15_cleanup_visuals（自注册 [60]tick，规则28 world15_cleanup_surface_light 同模式）：
--     world_number~=15 且脏标记 world15_visuals_dirty 时一次性销毁三类残留并复位标记；创建处
--     （place_recycle_box/redraw_clear_labels/clear_refresh_progress）置脏，on_world_start 随新局复位。
-- 36. 黑暗出虫参数调整（2026-09 用户）：附近虫子暂停阈值 100 → 180；
--     黑暗停留触发时间 3s → 5s。
-- 40. 2026-10 用户五条批量（全部只在本文件，不改共享代码）：
--     ① 挖石头出矿与「采矿产能科技 / 在线玩家人数」脱钩：配置 disable_rock_ore=true 令共享
--        rocks_yield_ore handler 早退（其产能乘算无条件执行、无字段可关），由本文件
--        world15_on_player_mined_entity 自实现挖石头/树产出（数量公式/奖池/木头/粒子/
--        满包惩罚与共享一致，仅取消两项加成）；rock_ore_player_bonus 字段删除。
--     ② 挖石宝箱概率（用户指定「原来的2/5」，最终再定值）：木箱 1/40 → 1/90 → 1/70
--        （wood_chest_chance）；好运连连钢箱 1/75 → 1/120 → 1/90（hyll_steel_chest_chance）。
--     ③ 野外精良市场（不含湖资源岛）chunk 生成概率 3% → 6%（×2）；生成时布置与出生市场
--        一模一样的照明（world15_place_market_lighting 公共化：EEI 隐形电源+左右±2木电线杆+
--        四对角(±2,±2)灯，落点先清障岩石/树）；并以白嫖组装机同款 add_chart_tag 机制
--        挂 entity/market 图标（market 无物品原型，实测运行时接受 entity 类型图标），俯视地图可见。
--     ④ 湖泊资源岛 1 岛/2 岛概率 50%/50% → 70%/30%（lake_market_angles：h%2==1 → h%10>=7）。

local World = require 'maps.amap.world.framework'
local Event = require 'utils.event'
local WPT = require 'maps.amap.table'
local WD = require 'modules.wave_defense.table'
local diff = require 'maps.amap.diff'
local world_function = require 'maps.amap.world.world_function'
local WorldTable = require 'maps.amap.world.world_table'
local MT = require 'maps.amap.basic_markets'
local IslandManager = require 'maps.amap.island_manager'
local enemy_arty = require 'maps.amap.enemy_arty'
local BiterRolls = require 'modules.wave_defense.biter_rolls'
local tianfu = require 'maps.amap.tianfu'
local tianfu_table = require 'maps.amap.tianfu_table'
local tianfu_time_skill = require 'maps.amap.tianfu_time_skill'
local rpgtable = require 'modules.rpg.table'
local rock = require 'maps.amap.rock'
local Task = require 'utils.task'
local Token = require 'utils.token'
local simplex = require 'utils.simplex_noise'.d2

--==============================================================================
-- 常量
--==============================================================================

local SPAWN_RADIUS = 144              -- 出生点 288 直径圆半径
local SPAWN_RADIUS_SQ = SPAWN_RADIUS * SPAWN_RADIUS
local ROCK_DENSITY = 36               -- 石头带岩石密度：24%（山谷 3 倍 ×2）→ 36%（用户要求 ×1.5）
local LIGHT_RADIUS = 14               -- 灯光覆盖判定半径（小灯默认光照半径）
local DARKNESS_TICK_INTERVAL = 30     -- 黑暗检测间隔（0.5 秒）
local DARKNESS_TICKS_REQUIRED = 60 * 5  -- 5 秒（2026-09 用户：3s → 5s）
local DARK_SPAWN_CAP = 60             -- 单次黑暗出虫物理生成上限（稳定性保护，公式本身保留）
local DARK_BITER_LIMIT_COUNT = 180    -- 玩家附近（半径 30 格）虫子超过此数 → 暂停黑暗出虫
                                      -- （2026-09 用户：100 → 180）
local DARK_BITER_LIMIT_RADIUS = 30
-- 离散湖泊（大随机湖）：网格 330 + 2/3 概率（2000×2000 约 22~24 个，为上一版的 2/3）
-- 湖面积 = 基准 2800 × 随机倍数 k（k ∈ {4..10} 均匀）→ 面积 11200~28000（老湖的 4~10 倍），
--   湖半径 r0 = sqrt(2800k/π) ≈ 60~94；水域半径 = r0 × 随机比例 0.35~0.42（面积 ~0.12~0.18×湖）；
-- 形状：随机长宽比 aspect(1.2~4.0，随大小截断防重叠) + 随机主轴角 → 椭圆拉伸（不规则长条形）+ 多频噪声扰动 ±40%；
--   仍为「每个方向单一半径」的星形 → 天然单连通（一湖绝不分块），水域被湖形裁剪。
-- 湖心距最小 ~306 ≥ 两湖最远半径之和上限 → 湖与湖不相交。
local LAKE_GRID = 330                -- 湖泊网格步长（湖心候选点间距）
local LAKE_PROB_NUM = 2              -- 出湖概率分子（2/3：每 3 个网格点 2 个出湖）
local LAKE_PROB_DEN = 3
local LAKE_AREA_BASE = 2800          -- 湖基准面积（老湖 2463~3217 取中）
local LAKE_SCALE_MIN = 4             -- 面积倍数下限（4 倍）
local LAKE_SCALE_MAX = 10            -- 面积倍数上限（10 倍）
local WATER_RATIO_MIN = 0.35         -- 水域半径 / 湖半径 比例下限
local WATER_RATIO_MAX = 0.42
local LAKE_SHAPE_AMP = 0.40          -- 湖轮廓噪声扰动幅度（±40%）
local WATER_SHAPE_AMP = 0.35         -- 水域轮廓噪声扰动幅度（±35%）
local LAKE_ASPECT_MIN = 1.2          -- 长宽比下限（近圆）
local LAKE_ASPECT_MAX = 4.0          -- 长宽比上限（拉长条）
local LAKE_GRID_HALF = (LAKE_GRID - 24) / 2   -- 湖心最小间距的一半 → 用于按大小截断长宽比（防重叠）
-- 湖岸虫巢随机成团参数（旧实现 `hash2 % 32`：2 的幂取模且乘法哈希低位与坐标线性相关
-- → 虫巢沿岸等距/晶格排列，过整齐；biter/spitter 的 %2 更是严格棋盘格）。
-- 新实现：低频双层噪声选「巢区」段（连续不规则斑块，斑块间留空）+ 斑块内用高频逐格噪声抽样，
-- 虫巢疏密不均、随机聚团；biter/spitter 同样用噪声决定。整体密度较旧版略降（用户允许）。
local NEST_FIELD_THRESHOLD = 0.15    -- 巢区阈值：双层噪声(0.045+0.017)高于此值的岸段为巢区（约 30% 岸长）
local NEST_PICK_THRESHOLD = 0.72     -- 巢区内逐格抽样：高频噪声(0.9/格)高于此值才放巢（约 8% 区格）
                                     -- 综合密度 ≈ 30% × 8% ≈ 2.4% 岸格（旧版均匀 1/32 ≈ 3.1%）
local DARK_THRESHOLD = 0.17           -- 黑暗核心判定阈值（实测：单低频 0.02 + 阈值 0.17 → 暗区 ≈49.8%，目标 ~50%）
local DARK_DILATE = 2                 -- 暗区向外扩张 2 格（切比雪夫）→ 两片暗区之间的陆地最窄处 ≥4 格
local TALENT_CAP = 60                 -- 天赋上限（同世界19）
local EPIC_HYLL_Q = 4                 -- 史诗好运连连（品质档 4）

-- 科技瓶 → 天赋数（同世界19/21）
local SCIENCE_PACK_TALENTS = {
    ['logistic-science-pack'] = 1,
    ['military-science-pack'] = 1,
    ['chemical-science-pack'] = 1,
    ['production-science-pack'] = 1,
    ['utility-science-pack'] = 1,
    ['space-science-pack'] = 1,
    ['metallurgic-science-pack'] = 2,
    ['electromagnetic-science-pack'] = 2,
    ['agricultural-science-pack'] = 2,
    ['cryogenic-science-pack'] = 3,
    ['promethium-science-pack'] = 5,
}

-- reset_map 期间脚本强制研究的科技（不触发科技瓶天赋）
local SCRIPT_RESEARCH_BLACKLIST = {
    ['cliff-explosives'] = true,
    ['advanced-asteroid-processing'] = true,
    ['asteroid-reprocessing'] = true,
}

local MINE_TECH_LIT = nil   -- 控制阶段自动生成：开采实体 → 原版"开采触发"型科技列表

-- 石头抽奖（与 world_function.rock_raffle 一致）
local ROCK_RAFFLE = {
    'big-sand-rock', 'big-sand-rock',
    'big-rock', 'big-rock', 'big-rock', 'big-rock', 'big-rock', 'big-rock', 'big-rock',
    'huge-rock',
}

-- 出生市场可「卖矿得金币」的矿列表（1 组 = 2 金币）
local WORLD15_ORE_LIST = {
    'iron-ore', 'copper-ore', 'coal', 'stone', 'uranium-ore', 'tungsten-ore', 'scrap',
}

-- 矿物回收箱只回收矿物（矿石类）
local WORLD15_RECYCLE_ORES = {
    ['iron-ore'] = true, ['copper-ore'] = true, ['coal'] = true, ['stone'] = true,
    ['uranium-ore'] = true, ['tungsten-ore'] = true, ['scrap'] = true, ['calcite'] = true,
}

-- 挖石头出矿比例（权重）：铁50 / 铜34 / 煤26 / 石20 / 铀4 / 钨2 / 废料3
local WORLD15_ORE_WEIGHTS = {
    {'iron-ore', 50}, {'copper-ore', 34}, {'coal', 26}, {'stone', 20},
    {'uranium-ore', 4}, {'tungsten-ore', 2}, {'scrap', 3},
}

local function build_raffle(weights)
    local r = {}
    for _, w in ipairs(weights) do
        for i = 1, w[2], 1 do
            r[#r + 1] = w[1]
        end
    end
    return r
end
local WORLD15_RAFFLE = build_raffle(WORLD15_ORE_WEIGHTS)

-- 世界15 弹药伤害还原类型表（与 maps/amap/functions.lua set_force_damage_modifier
-- multiplier 通道同表）：用于把伤害削减/加成还原到进入世界15时的水平
local WORLD15_DAMAGE_TYPES = {
    'artillery-shell', 'biological', 'bullet', 'electric', 'flamethrower',
    'grenade', 'landmine', 'beam', 'laser', 'shotgun-shell',
    'cannon-shell', 'melee', 'rocket', 'tesla', 'railgun',
}

-- 方案A（用户确认）：挖到原版"开采触发(mine-entity)"型科技的触发实体时，直接为该势力
-- researched=true 点亮该科技（绕过 planet-discovery 等前置）。只影响开采触发型科技。
-- 用属性赋值而非 force.add_technology：不触发 on_research_finished，
-- 因此不占用/不影响本图「每种科研包首次完成研究送天赋」的计数（该机会留给正常研究）。
-- 映射在控制阶段从原型表自动生成，无手工对照表、不漏项。
MINE_TECH_LIT = {}
for tname, tech in pairs(prototypes.technology) do
    local rt = tech.research_trigger
    if rt and rt.type == 'mine-entity' then
        for _, ename in pairs(rt.entities or {}) do
            MINE_TECH_LIT[ename] = MINE_TECH_LIT[ename] or {}
            MINE_TECH_LIT[ename][#MINE_TECH_LIT[ename] + 1] = tname
        end
    end
end

-- 用户 2026-09 明确要求：开采玉玛果树(yumako-tree)/果冻茎株(jellystem)/方解石(calcite)
-- 也点亮对应科技（与开采火星岩石 big-volcanic-rock 同理）。上述自动扫描本已覆盖
-- （2.1.17 实测：yumako-tree→yumako、jellystem→jellynut、calcite→calcite-processing、
-- big-volcanic-rock→tungsten-carbide），此处显式兜底：万一原型扫描漏项也保证这三个
-- 实体必有点亮映射（幂等，不覆盖自动结果；科技名已按运行时原型实测核对）。
local MINE_TECH_LIT_EXTRA = {
    ['yumako-tree'] = {'yumako'},
    ['jellystem'] = {'jellynut'},
    ['calcite'] = {'calcite-processing'},
}
for ename, techs in pairs(MINE_TECH_LIT_EXTRA) do
    if not MINE_TECH_LIT[ename] then
        MINE_TECH_LIT[ename] = techs
    end
end

-- 世界 19 地表配置包装：只影响 world15 键
local WORLD15_SURFACE_CONFIG = {
    ['water'] = {frequency = 1, size = 0, richness = 1},
    ['coal'] = {frequency = 1, size = 0, richness = 1},
    ['stone'] = {frequency = 1, size = 0, richness = 1},
    ['copper-ore'] = {frequency = 1, size = 0, richness = 1},
    ['iron-ore'] = {frequency = 1, size = 0, richness = 1},
    ['uranium-ore'] = {frequency = 1, size = 0, richness = 1},
    ['tungsten_ore'] = {frequency = 1, size = 0, richness = 1},   -- autoplace 控制名是下划线 tungsten_ore（引擎实测 'tungsten-ore' 报 not a valid autoplace control name，reset_map 崩 → game_over 循环报警）
    ['calcite'] = {frequency = 1, size = 0, richness = 1},
    ['scrap'] = {frequency = 1, size = 0, richness = 1},
    ['crude-oil'] = {frequency = 3, size = 2, richness = 4},   -- 石油自然生成 3/2/4（2026-09 用户从 2/2/4 上调；与地图19同机制）
    ['trees'] = {frequency = 1, size = 0, richness = 1},
    ['enemy-base'] = {frequency = 1, size = 0, richness = 1},
}

local world15_table_orig_reset = WorldTable.reset_table
WorldTable.reset_table = function()
    world15_table_orig_reset()
    local sc = WorldTable.get('surface_configs')
    if sc then
        sc['world15'] = WORLD15_SURFACE_CONFIG
    end
end

--==============================================================================
-- 噪声 / 哈希工具（世界15 自用，不污染 utils/get_noise.lua）
--==============================================================================

local function layered_noise(pos, layers, seed)
    local n = 0
    local d = 0
    for i = 1, #layers, 1 do
        local mod = layers[i]
        n = n + simplex(pos.x * mod[1], pos.y * mod[1], seed) * mod[2]
        d = d + mod[2]
        seed = seed + 10000
    end
    if d == 0 then return 0 end
    return n / d
end

-- 确定性整数哈希：与区块生成顺序/随机种子无关，保证跨 chunk 判定一致。
-- 各乘数控制在 2^53 内避免双精度丢位（坐标取模 2^20，周期 100 万格远大于实际探索范围）。
local function hash2(x, y, salt, seed)
    local n = (x % 1048576) * 73856093
    n = (n + (y % 1048576) * 19349663) % 2147483647
    n = (n + (salt % 65536) * 83492791) % 2147483647
    n = (n + seed % 2147483647) % 2147483647
    if n < 0 then n = n + 2147483647 end
    return n
end

-- 离散湖泊：返回覆盖 (x,y) 的湖（中心/基准半径/水域基准半径/长宽比/主轴角），无则 nil。
-- 2/3 概率出湖；参数由哈希决定，跨 chunk 一致。
local function lake_cover(x, y, seed)
    local gx = math.floor(x / LAKE_GRID)
    local gy = math.floor(y / LAKE_GRID)
    local h = hash2(gx, gy, 1, seed)
    if h % LAKE_PROB_DEN >= LAKE_PROB_NUM then return nil end
    local jx = (hash2(gx, gy, 2, seed) % 25) - 12
    local jy = (hash2(gx, gy, 3, seed) % 25) - 12
    local cx = gx * LAKE_GRID + LAKE_GRID / 2 + jx
    local cy = gy * LAKE_GRID + LAKE_GRID / 2 + jy
    local max_r = math.sqrt(LAKE_AREA_BASE * LAKE_SCALE_MAX / math.pi)
    if cx * cx + cy * cy <= (SPAWN_RADIUS + math.floor(max_r * 1.4) + 20) * (SPAWN_RADIUS + math.floor(max_r * 1.4) + 20) then
        return nil
    end
    local k = LAKE_SCALE_MIN + (hash2(gx, gy, 4, seed) % (LAKE_SCALE_MAX - LAKE_SCALE_MIN + 1))  -- 4..10 倍
    local r = math.sqrt(LAKE_AREA_BASE * k / math.pi)
    local ratio = WATER_RATIO_MIN + (hash2(gx, gy, 5, seed) % 8) / 100
    local rw = r * ratio
    -- 长宽比：随机 1.2~4.0，但受「最远半径 ≤ 湖心距一半」约束截断（防相邻大湖长轴重叠）
    local aspect = LAKE_ASPECT_MIN + (hash2(gx, gy, 9, seed) % 29) / 10
    local a_max = (LAKE_GRID_HALF / (r * 1.4)) ^ 2
    if aspect > a_max then aspect = a_max end
    if aspect < LAKE_ASPECT_MIN then aspect = LAKE_ASPECT_MIN end
    local phi = (hash2(gx, gy, 10, seed) % 628) / 100   -- 主轴方向 0..6.27 弧度
    return {x = cx, y = cy, r = r, rw = rw, aspect = aspect, phi = phi, gx = gx, gy = gy}
end

-- 湖形/水域边界：椭圆拉伸（长宽比 aspect、主轴角 phi）× 多频噪声扰动（不规则）。
-- 每方向单一半径 → 星形单连通（连续、不分块）；水域被湖形裁剪。
local function lake_radii(pos, lake, seed)
    local dx = pos.x - lake.x
    local dy = pos.y - lake.y
    local delta = math.atan2(dy, dx) - lake.phi
    local A = lake.aspect
    local cd, sd = math.cos(delta), math.sin(delta)
    local ell = 1 / math.sqrt(cd * cd / A + A * sd * sd)
    local rx = lake.r * ell * (1 + LAKE_SHAPE_AMP * layered_noise(pos, {{0.008, 1}, {0.02, 0.5}, {0.04, 0.25}}, seed + 300000))
    local rw = lake.rw * ell * (1 + WATER_SHAPE_AMP * layered_noise(pos, {{0.012, 1}, {0.03, 0.5}}, seed + 400000))
    if rw > rx then rw = rx end
    return rx, rw
end

-- 湖岸资源岛（产矿市场）角度：70% 1 个 / 30% 2 个（2026-10 用户：50/50 → 70/30；2 个在对侧）。
local function lake_market_angles(lake, seed)
    local h = hash2(lake.gx, lake.gy, 5, seed)
    local a1 = (hash2(lake.gx, lake.gy, 6, seed) % 628) / 100   -- 0..6.27 弧度
    local angles = {a1}
    if h % 10 >= 7 then
        angles[#angles + 1] = a1 + math.pi
    end
    return angles
end

-- 湖资源岛精确落点：沿预定角从湖心向外逐格扫描，取第一个「草地环」格（水外 ≥2 格、湖内 ≥2 格边距）。
-- 按湖缓存一次（纯确定性计算：同一湖任何时刻重算结果一致 → 缓存不破坏跨客户端同步）。
-- 返回 {spot1, spot2或nil}；极端湖形下某角度可能无草地格（该格为 nil）。
local function lake_market_spots(this, lake, seed)
    if not this.world15_lake_spot_cache then
        this.world15_lake_spot_cache = {}
    end
    local key = lake.gx .. ',' .. lake.gy
    local cached = this.world15_lake_spot_cache[key]
    if cached ~= nil then return cached end
    local angles = lake_market_angles(lake, seed)
    local spots = {}
    for i = 1, #angles do
        local ux, uy = math.cos(angles[i]), math.sin(angles[i])
        local spot = nil
        for s = 1, 220 do
            local x = lake.x + math.floor(ux * s + 0.5)
            local y = lake.y + math.floor(uy * s + 0.5)
            local rx, rw = lake_radii({x = x, y = y}, lake, seed)
            local dx = x - lake.x
            local dy = y - lake.y
            local d = math.sqrt(dx * dx + dy * dy)
            if d > rw + 4 and d < rx - 4 then
                spot = {x = x, y = y}
                break
            end
            if d > rx + 80 then break end   -- 防御：超出湖形最远扰动仍无草地格 → 放弃
        end
        spots[i] = spot
    end
    this.world15_lake_spot_cache[key] = spots
    return spots
end

-- 草星地块已按用户要求（2026-09）取消湖岸生成，改在出生点圈内随机 6×6 生成
--（见 build_spawn_facilities → world15_spawn_plots；lake_plot_spots 已删除）。

-- 湖岸可挖掘点亮科技实体（用户要求：原出生圈内固定 4 个太少 → 移到湖岸成量出现）：
-- 大型火山岩 / 铁、铜叠层石；高频噪声逐格抽样（无晶格）。
-- 按用户要求（2026-09）：不再生成「中型雷神废墟」(fulgoran-ruin-medium)，
-- 「雷神地宫废墟」(fulgoran-ruin-vault，14×8 格) 由 lake_vault_spot 每湖独立选点。
local SHORE_SPECIAL_RAFFLE = {
    'big-volcanic-rock', 'iron-stromatolite', 'copper-stromatolite',
}
local SHORE_SPECIAL_THRESHOLD = 0.85   -- 噪声阈值（阈值越低越密；0.88→实测0.74%，0.85→约1.2%岸格）
local function try_place_shore_special(surface, pos, lake, seed, spots)
    for i = 1, #spots do
        local sp = spots[i]
        if sp and math.abs(sp.x - pos.x) <= 3 and math.abs(sp.y - pos.y) <= 3 then
            return
        end
    end
    local pick = simplex(pos.x * 0.9 + 13.7, pos.y * 0.9 + 7.1, seed + 640000)
    if pick < SHORE_SPECIAL_THRESHOLD then return end
    local kd = simplex(pos.x * 1.3 + 91.7, pos.y * 1.3 + 37.3, seed + 650000)
    local idx = math.floor((kd + 1) * 0.5 * #SHORE_SPECIAL_RAFFLE) + 1
    if idx > #SHORE_SPECIAL_RAFFLE then idx = #SHORE_SPECIAL_RAFFLE end
    local name = SHORE_SPECIAL_RAFFLE[idx]
    -- 实测 can_place_entity 对叠层石/火山岩在草上返回 false 但 create_entity 可放，
    -- 故直接 pcall 创建（与虫巢同款外部边界容错），失败仅记日志。
    -- 2026-10 用户要求：湖岸科技实体可被摧毁（去掉原「不可摧毁」设置，恢复默认可摧毁）。
    local ok, e = pcall(function()
        surface.create_entity({name = name, position = pos, force = 'neutral'})
    end)
    if not ok then
        log('[world15] 湖岸科技实体放置失败 ' .. tostring(name) .. ' @ ' .. tostring(pos.x) .. ',' .. tostring(pos.y) .. ' err=' .. tostring(e))
    end
end

-- 黑暗地块：单低频噪声判定（大块连续暗区，占比 ~50%）+ 向外扩张 DARK_DILATE 格。
-- 去掉 0.08 高频 octave → 暗区是大块连通区域而非碎块；扩张后两片暗区之间的陆地最窄 ≥4 格。
local function dark_core(x, y, seed)
    local dark = layered_noise({x = x, y = y}, {{0.02, 1}}, seed + 50000)
    return dark > DARK_THRESHOLD
end

local function is_dark(x, y, seed)
    -- 中心 + 8 个 ±DARK_DILATE 邻点任一为暗核即暗（5×5 切比雪夫扩张的骨架采样；噪声低频，误差可忽略）
    if dark_core(x, y, seed) then return true end
    for dx = -DARK_DILATE, DARK_DILATE, DARK_DILATE do
        for dy = -DARK_DILATE, DARK_DILATE, DARK_DILATE do
            if dx ~= 0 or dy ~= 0 then
                if dark_core(x + dx, y + dy, seed) then
                    return true
                end
            end
        end
    end
    return false
end

-- 地形分类：spawn / lake_water / lake_grass / dark / belt
local function tile_class(pos, seed)
    local d2 = pos.x * pos.x + pos.y * pos.y
    if d2 <= SPAWN_RADIUS_SQ then
        return 'spawn'
    end
    local lake = lake_cover(pos.x, pos.y, seed)
    if lake then
        local dx = pos.x - lake.x
        local dy = pos.y - lake.y
        local d = math.sqrt(dx * dx + dy * dy)
        local rx, rw = lake_radii(pos, lake, seed)
        if d <= rx then
            if d <= rw then
                return 'lake_water'
            end
            return 'lake_grass'
        end
    end
    if is_dark(pos.x, pos.y, seed) then
        return 'dark'
    end
    return 'belt'
end

-- 天然油田保护表（用户要求：油田按引擎 autoplace 自然生成，同地图19）：
-- on_chunk_generated 把陆地/湖岸/出生圆内的 autoplace 原油格登记进
-- this.world15_oil_keep[chunkLT.x,chunkLT.y]，terrain_generator 各分支读到即
-- 跳过铺地/长石/放虫巢等，让油田保持可放抽油机的原状；黑暗/水里油田直接删除。
local function is_retained_oil(this, x, y)
    if not this.world15_oil_keep then return false end
    local ckx = math.floor(x / 32) * 32
    local cky = math.floor(y / 32) * 32
    local tbl = this.world15_oil_keep[ckx .. ',' .. cky]
    return tbl ~= nil and tbl[x .. ',' .. y] ~= nil
end

-- 油田 1 格保护带（2026-09 实测根因修复，勿删）：
-- 2.1.17 引擎实测：把油田周边大范围瓦片批量改为 out-of-map / deepwater 时，
-- 会连带摧毁油田实体（即使油田自身格子未动，set_tiles 单格改不会触发、批量改会触发）；
-- 改 dirt-7 / grass-1 则无此问题。因此 dark（铺 out-of-map）与 lake_water（铺 deepwater）
-- 两个分支必须对「油田格 + 其 8 邻域格」一律跳过铺地，保留 3×3 原生孤岛。
-- 邻域跨区块查表：相邻 chunk 可能先/后生成，这里双向都实时查当前 keep 表（已生成的
-- chunk 入口在 chunk 顶部完成登记，先于 terrain_generator 逐格处理，顺序安全）。
local function is_near_retained_oil(this, x, y)
    if not this.world15_oil_keep then return false end
    for dx = -1, 1 do
        for dy = -1, 1 do
            if dx ~= 0 or dy ~= 0 then
                local nx, ny = x + dx, y + dy
                local ckx = math.floor(nx / 32) * 32
                local cky = math.floor(ny / 32) * 32
                local tbl = this.world15_oil_keep[ckx .. ',' .. cky]
                if tbl and tbl[nx .. ',' .. ny] then
                    return true
                end
            end
        end
    end
    return false
end

-- 湖岸雷神地宫废墟（fulgoran-ruin-vault）：每湖 50% 概率、至多 1 个。
-- 占地约 14×8 格（碰撞 ±6.88×±4）：12 个哈希方向沿径向外推，取第一个
-- 「整盒全 lake_grass、不压市场/植物地块/受保护油田」的落点；按湖缓存
-- （纯确定性，跨 chunk 一致）。找不到开阔点则该湖不放。
local VAULT_HALF_X = 7              -- 覆盖列 [cx-7, cx+6]
local VAULT_HALF_Y = 4              -- 覆盖行 [cy-4, cy+3]
local function vault_box_clear(this, cx, cy, seed, markets)
    for tx = cx - VAULT_HALF_X, cx + VAULT_HALF_X - 1, 1 do
        for ty = cy - VAULT_HALF_Y, cy + VAULT_HALF_Y - 1, 1 do
            if tile_class({x = tx, y = ty}, seed) ~= 'lake_grass' then
                return false
            end
            if is_retained_oil(this, tx, ty) then
                return false
            end
        end
    end
    for j = 1, #markets do
        local m = markets[j]
        if m and math.abs(m.x - cx) <= 10 and math.abs(m.y - cy) <= 8 then
            return false
        end
    end
    return true
end

local function lake_vault_spot(this, lake, seed)
    if not this.world15_lake_vault_cache then
        this.world15_lake_vault_cache = {}
    end
    local key = lake.gx .. ',' .. lake.gy
    local cached = this.world15_lake_vault_cache[key]
    if cached ~= nil then
        if cached == false then return nil end
        return cached
    end
    local spot = false
    if hash2(lake.gx, lake.gy, 41, seed) % 10 < 5 then
        local markets = lake_market_spots(this, lake, seed)
        local base_angle = (hash2(lake.gx, lake.gy, 42, seed) % 628) / 100
        local d_min = math.floor(lake.rw + VAULT_HALF_X + 1)
        local d_max = math.floor(lake.r - VAULT_HALF_X - 1)
        for a = 0, 11 do
            if d_max >= d_min then
                local ang = base_angle + a * (math.pi / 6)
                local ux, uy = math.cos(ang), math.sin(ang)
                local jitter = hash2(lake.gx, lake.gy, 43 + a, seed) % 5
                for d = d_min + jitter, d_max, 2 do
                    local cx = lake.x + math.floor(ux * d + 0.5)
                    local cy = lake.y + math.floor(uy * d + 0.5)
                    if vault_box_clear(this, cx, cy, seed, markets) then
                        spot = {x = cx, y = cy}
                        break
                    end
                end
            end
            if spot ~= false then break end
        end
    end
    this.world15_lake_vault_cache[key] = spot
    if spot == false then return nil end
    return spot
end

--==============================================================================
-- 地表资源配置包装（world15 键）
--==============================================================================

--（见上方 WorldTable.reset_table 包装）

--==============================================================================
-- 野外市场三档质量：每件在售商品给 普通 / 精良(uncommon) / 稀有(rare) 三个条目，
--   价格 = 原价×1 / ×2 / ×5（用户指定）。卖矿换币条目（offer 为 coin）不参与
--   品质复制（否则金币会多出品质条目）。
--==============================================================================

local function world15_build_quality_market(surface, position, rarity)
    local mrk = MT.mountain_market(surface, position, rarity)
    if not mrk or not mrk.valid then return nil end
    local base_items = mrk.get_market_items()
    if #base_items == 0 then return mrk end
    local out = {}
    for _, item in ipairs(base_items) do
        local offer = item.offer
        local base_price = item.price and item.price[1] and item.price[1].count
        if offer and offer.type == 'give-item' and offer.item ~= 'coin' and base_price then
            local normal = table.deepcopy(item)
            normal.offer.quality = 'normal'
            out[#out + 1] = normal
            local up = table.deepcopy(item)
            up.offer.quality = 'uncommon'
            up.price[1].count = math.max(1, math.floor(base_price * 2 + 0.5))
            out[#out + 1] = up
            local rp = table.deepcopy(item)
            rp.offer.quality = 'rare'
            rp.price[1].count = math.max(1, math.floor(base_price * 5 + 0.5))
            out[#out + 1] = rp
        else
            out[#out + 1] = item
        end
    end
    mrk.clear_market_items()
    for _, entry in ipairs(out) do
        mrk.add_market_item(entry)
    end
    return mrk
end

--==============================================================================
-- 湖泊可购买的产矿市场（资源岛）
--==============================================================================

local function build_lake_market(surface, position)
    local market = surface.create_entity({name = 'market', position = position, force = 'neutral'})
    if not market or not market.valid then return nil end
    market.destructible = false
    local island_id = IslandManager.register_island(surface, market, 'resource', false)
    IslandManager.setup_island_market(market, island_id)
    return market
end

-- 湖岸虫巢：随机成团分布。低频双层噪声圈出「巢区」斑块（斑块内才可能放巢），
-- 斑块再用高频逐格噪声抽样 → 虫巢疏密不均、自然聚团，不再沿岸等距整齐。
-- 全部由坐标+seed 确定性计算，跨 chunk 一致；资源岛落点 3×3 周边 2 格内不放虫巢（保持市场干净）。
local function try_place_shore_spawner(surface, pos, lake, rx, rw, seed, spots)
    for i = 1, #spots do
        local sp = spots[i]
        if sp and math.abs(sp.x - pos.x) <= 2 and math.abs(sp.y - pos.y) <= 2 then
            return
        end
    end
    local dx = pos.x - lake.x
    local dy = pos.y - lake.y
    local d = math.sqrt(dx * dx + dy * dy)
    if not (d > rw + 1 and d < rx - 1) then return end
    -- 巢区斑块：低频噪声场，> 阈值的连续区域才可能成巢（疏密不均）
    local field = layered_noise(pos, {{0.045, 1}, {0.017, 0.6}}, seed + 610000)
    if field < NEST_FIELD_THRESHOLD then return end
    -- 巢区内逐格抽样：高频噪声（相邻格近乎去相关）→ 随机点缀，非晶格
    local pick = simplex(pos.x * 0.9, pos.y * 0.9, seed + 620000)
    if pick < NEST_PICK_THRESHOLD then return end
    -- biter/spitter 种类也用噪声（旧 %2 → 严格棋盘格，同样太整齐）
    local kind = simplex(pos.x * 1.3 + 91.7, pos.y * 1.3 + 37.3, seed + 630000)
    local name = kind > 0 and 'spitter-spawner' or 'biter-spawner'
    -- 直接创建（can_place_entity 对 unit-spawner 在草地环上会误报不可放置，实测 create_entity 可放）；
    -- pcall 隔离水边/角落的个别放不下场景（与 safe_create 同款外部边界容错）。
    -- 2026-10 用户要求：湖岸虫巢可被摧毁（去掉原「不可摧毁」设置，恢复默认可摧毁）。
    local ok, e = pcall(function()
        surface.create_entity({name = name, position = pos, force = game.forces.enemy})
    end)
    if not ok then
        log('[world15] 湖岸虫巢放置失败 ' .. tostring(name) .. ' @ ' .. tostring(pos.x) .. ',' .. tostring(pos.y) .. ' err=' .. tostring(e))
    end
end

--==============================================================================
-- 区块生成：野外精良市场 / 湖泊产矿市场注册 / 出生圆外默认树石清理
--==============================================================================

local function on_chunk_generated(event)
    local this = WPT.get()
    if (this and this.world_number or 0) ~= 15 then return end
    local surface = event.surface
    if not surface or not surface.valid then return end
    if this.active_surface_index and surface.index ~= this.active_surface_index then return end

    local area = event.area
    local lt_x, lt_y = area.left_top.x, area.left_top.y
    local seed = surface.map_gen_settings.seed

    if not this.world15_market_spots then this.world15_market_spots = {} end
    local chunk_key = lt_x .. ',' .. lt_y
    local chunk_spots = this.world15_market_spots[chunk_key]
    if not chunk_spots then
        chunk_spots = {}
        this.world15_market_spots[chunk_key] = chunk_spots
    end

    -- 0) 天然油田处理（用户要求油田按引擎 autoplace 自然生成，同地图19；2026-09 用户追加：
    --    黑暗区里的油田不要、别让我看见 → 黑暗/水中油田一律销毁，只在亮区石头带生成）：
    --    引擎在区块生成阶段已铺好 autoplace 原油格，这里在逐格铺地之前分类：
    --    黑暗(dark)/深水(lake_water)油田 → 直接删除；
    --    石头带/湖岸/出生圆内油田 → 登记保护表，terrain_generator 各分支跳过这些格
    --    （不铺 deepwater、不长岩石、不扔虫巢），保持可建抽油机。
    if not this.world15_oil_keep then this.world15_oil_keep = {} end
    local oils = surface.find_entities_filtered({area = area, name = 'crude-oil'})
    if #oils > 0 then
        local oil_tbl = this.world15_oil_keep[chunk_key]
        if not oil_tbl then
            oil_tbl = {}
            this.world15_oil_keep[chunk_key] = oil_tbl
        end
        for _, o in ipairs(oils) do
            if o and o.valid then
                local p = o.position
                local ox, oy = math.floor(p.x), math.floor(p.y)
                local cls = tile_class({x = ox, y = oy}, seed)
                if cls == 'lake_water' or cls == 'dark' then
                    o.destroy()
                else
                    oil_tbl[ox .. ',' .. oy] = true
                end
            end
        end
    end

    -- 1) 野外精良市场：每 chunk 6% 概率（2026-10 用户要求 ×2：3% → 6%；湖泊资源岛不在此列）；
    --    可在石头带或湖岸草地上生成（与资源岛落点保持距离）
    if math.random(1, 100) <= 6 then
        local px = lt_x + math.random(0, 28)
        local py = lt_y + math.random(0, 28)
        if px * px + py * py > 250 * 250 and not is_retained_oil(this, px, py) then
            local cls = tile_class({x = px, y = py}, seed)
            local ok = false
            if cls == 'belt' then
                ok = true
            elseif cls == 'lake_grass' then
                local lake = lake_cover(px, py, seed)
                if lake then
                    local spots = lake_market_spots(this, lake, seed)
                    ok = true
                    for i = 1, #spots do
                        if spots[i] and math.abs(spots[i].x - px) <= 2 and math.abs(spots[i].y - py) <= 2 then
                            ok = false
                            break
                        end
                    end
                end
            end
            if ok then
                chunk_spots[#chunk_spots + 1] = {x = px, y = py, kind = 'quality'}
            end
        end
    end

    -- 2) 湖泊产矿市场 / 岸线虫巢：改由 terrain_generator 按离散湖泊确定性生成
    --   （market 落点与虫巢均为哈希决定，跨 chunk 一致，无需本处注册）。

    -- 3) 清理出生圆外默认树/石（石头带/湖泊/黑暗地块只保留脚本放置的内容）
    local entities = surface.find_entities_filtered({area = area, type = {'tree', 'simple-entity'}})
    for _, e in pairs(entities) do
        if e and e.valid then
            local p = e.position
            if p.x * p.x + p.y * p.y > SPAWN_RADIUS_SQ then
                e.destroy()
            end
        end
    end

    -- 4) 全图取消悬崖（实体级，替代原 cliff_settings 归零写法——后者会连高程一起清零、
    --    杀死 autoplace 石油）。悬崖不参与本图任何机制，出生圆内也一并清除。
    local cliffs = surface.find_entities_filtered({area = area, type = 'cliff'})
    for _, c in pairs(cliffs) do
        if c and c.valid then
            c.destroy()
        end
    end
end

--==============================================================================
-- 地形生成器
--==============================================================================

-- 前向声明：实现在 safe_create 之后定义（市场照明，出生/野外共用，见下方赋值处）
local world15_place_market_lighting

local function terrain_generator(surface, position, seed, get_tile, set_tiles, event, maxs, q, w, x, y, area)
    local this = WPT.get()
    local px, py = position.x, position.y

    -- 已注册的市场点（按 chunk 索引）：铺 3×3 草地并创建市场（中心格），其余 8 格 return
    local spots = this.world15_market_spots and this.world15_market_spots[area.left_top.x .. ',' .. area.left_top.y]
    if spots then
        for i = 1, #spots do
            local m = spots[i]
            if math.abs(px - m.x) <= 1 and math.abs(py - m.y) <= 1 then
                if px == m.x and py == m.y then
                    local tiles = {}
                    for dx = -1, 1 do
                        for dy = -1, 1 do
                            tiles[#tiles + 1] = {name = 'grass-1', position = {x = m.x + dx, y = m.y + dy}}
                        end
                    end
                    surface.set_tiles(tiles)
                    local rarity = 2 + math.floor((math.abs(px) + math.abs(py)) / 220)
                    if rarity > 10 then rarity = 10 end
                    local mrk = world15_build_quality_market(surface, {x = m.x, y = m.y}, rarity)
                    if mrk and mrk.valid then
                        -- 野外市场照明（2026-10 用户）：与出生市场一模一样（EEI+木电线杆+四角灯）
                        world15_place_market_lighting(surface, mrk.position.x, mrk.position.y)
                        -- 俯视地图图标（2026-10 用户）：同白嫖组装机 production.lua 的
                        -- add_chart_tag(图标标签) 机制。market 无物品原型（原版不可制造），
                        -- 实测运行时 icon 接受 entity 类型 → 用市场实体自身图标
                        game.forces.player.add_chart_tag(surface, {
                            position = mrk.position,
                            icon = { type = 'entity', name = 'market' },
                            text = '',
                        })
                    end
                end
                return
            end
        end
    end

    local class = tile_class(position, seed)
    if class == 'spawn' then
        -- 出生圆内：正常山谷地形（world_cave 自带的大水域保留）；
        -- 原「远离中心的噪声小水塘」已按用户要求取消（细碎水面不好看）。
        world_function.world_cave(surface, position, seed, get_tile)
        return
    elseif class == 'lake_water' then
        -- 湖心深水：油田保护带——邻接油田的岸边格不铺 deepwater
        --（批量铺 deepwater 会连带摧毁油田实体，实测见 is_near_retained_oil 注释）
        if is_near_retained_oil(this, px, py) then return end
        set_tiles({{name = 'deepwater', position = position}})
        return
    elseif class == 'lake_grass' then
        set_tiles({{name = 'grass-1', position = position}})
        -- 超大随机湖：资源岛（产矿市场）在草地环上精确落点；其余紧贴水域的岸线带铺密集虫巢
        --（草星地块已取消湖岸生成，改在出生圈随机 6×6，见 world15_spawn_plots）
        local lake = lake_cover(px, py, seed)
        if lake then
            local rx, rw = lake_radii(position, lake, seed)
            local spots = lake_market_spots(this, lake, seed)
            local is_market = false
            for i = 1, #spots do
                if spots[i] and spots[i].x == px and spots[i].y == py then
                    is_market = true
                    break
                end
            end
            if is_market then
                local tiles = {}
                for dx = -1, 1 do
                    for dy = -1, 1 do
                        tiles[#tiles + 1] = {name = 'grass-1', position = {x = px + dx, y = py + dy}}
                    end
                end
                surface.set_tiles(tiles)
                build_lake_market(surface, {x = px, y = py})
            else
                -- 雷神地宫废墟（用户要求：湖岸生成，替代原中型雷神废墟）：
                -- 中心格创建 vault；占地 14×8 内的其余格不放虫巢/科技实体（废墟为固体障碍）。
                local vault = lake_vault_spot(this, lake, seed)
                if vault then
                    if px == vault.x and py == vault.y then
                        local okv, ev = pcall(function()
                            local ent = surface.create_entity({name = 'fulgoran-ruin-vault', position = position, force = 'neutral'})
                            if ent and ent.valid then
                                ent.destructible = false
                            end
                        end)
                        if not okv then
                            log('[world15] 湖岸地宫废墟放置失败 @ ' .. tostring(px) .. ',' .. tostring(py) .. ' err=' .. tostring(ev))
                        end
                        return
                    end
                    if px >= vault.x - VAULT_HALF_X and px <= vault.x + VAULT_HALF_X - 1
                        and py >= vault.y - VAULT_HALF_Y and py <= vault.y + VAULT_HALF_Y - 1 then
                        return
                    end
                end
                -- 天然油田格：不扔虫巢/科技实体，保持可建抽油机（草地已在分支顶部铺好）
                if is_retained_oil(this, px, py) then return end
                try_place_shore_spawner(surface, position, lake, rx, rw, seed, spots)
                try_place_shore_special(surface, position, lake, seed, spots)
            end
        end
        return
    elseif class == 'dark' then
        -- 黑暗地块：整块铺 out-of-map（2026-09 用户追加「黑暗区油田不要、别让我看见」后：
        -- 黑暗区原油已在 on_chunk_generated 直接销毁，这里不再留任何油田孤岛；
        -- is_retained_oil/is_near_retained_oil 检查仅服务于「骑在明暗边界上的油田」——
        -- 其亮侧格子已登记保护，黑暗侧 8 邻域跳过铺地以免批量 out-of-map 连带摧毁亮侧油田）。
        if is_retained_oil(this, px, py) or is_near_retained_oil(this, px, py) then return end
        set_tiles({{name = 'out-of-map', position = position}})
        return
    else
        -- 石头带（2026-09 改地图19同机制，用户指示「学习地图19石头地下生成石油」）：
        -- 不再覆盖任何瓦片（旧版铺 dirt-7 属「使错力」——批量改瓦片不仅复杂，
        -- 2.1.17 引擎还会连带摧毁相邻油田），保留引擎原生地表——石油由 autoplace
        -- 在自然地表上生成（crude-oil=3/2/4），石头直接长在油上/油旁，与地图19
        -- 石头带完全一致；省掉整套油田保护表在石头带的分支判断。
        -- 用户要求（2026-09）：除出生点/湖泊外不生成水域——引擎原生水塘就地转草地
        --（出生圆与湖泊的水保留；黑暗区由 out-of-map 覆盖，水面同样被吞掉）。
        local belt_tile = get_tile(position)
        if belt_tile and (belt_tile.name == 'water' or belt_tile.name == 'deepwater') then
            set_tiles({{name = 'grass-1', position = position}})
        end
        world_function.world_cave(surface, position, seed, get_tile)
        if math.random(1, 100) <= ROCK_DENSITY then
            surface.create_entity({
                name = ROCK_RAFFLE[math.random(1, #ROCK_RAFFLE)],
                position = position,
                force = 'neutral',
            })
        end
        return
    end
end

--==============================================================================
-- 出生设施（市场灯光 / 方解石；回收箱见 world15_place_recycle_box，
-- 果树地块与科技实体已移到湖岸 terrain_generator 生成）
--==============================================================================

-- 出生设施是装饰性基础设施：单个实体放置失败（撞树/岩石/地形）不应拖垮整个出生点建设。
-- 用 pcall 隔离并 log 记录（外部边界容错，不掩盖内部逻辑错误）。
local function safe_create(surface, entity_name, position, params)
    params = params or {}
    local ok, e = pcall(function()
        return surface.create_entity({
            name = entity_name,
            position = position,
            force = params.force or 'neutral',
            amount = params.amount,
            quality = params.quality,
        })
    end)
    if not ok or not e or not e.valid then
        log('[world15] 出生设施放置失败 ' .. tostring(entity_name) .. ' @ ' .. tostring(position and position.x) .. ',' .. tostring(position and position.y) .. ' err=' .. tostring(e))
        return nil
    end
    return e
end

-- 市场照明布置（出生市场 / 野外市场共用，2026-10 用户要求野外「一模一样」）：
--   · hidden-electric-energy-interface 与市场同格重叠（无碰撞/不可选/小图隐藏），
--     electric_buffer_size=1e9(1GJ)、power_production=1e6/60(1MW，运行时单位 J/tick)、power_usage=0
--   · 市场左右 ±2 各 1 根木制电线杆 small-electric-pole
--   · 市场四对角 (±2,±2) 各 1 盏 small-lamp
--   · 全部 destructible=false / minable_flag=false；放置顺序 EEI→杆→灯，
--     2.x 放置时自动就近接线 → 灯/杆/市场全连进 EEI 电网，常亮。
-- 以市场实体真实 position 作锚点（create_entity 会吸附包围盒，不能想当然用整数坐标）。
-- 杆/灯落点先清掉挡格岩石/树（野外石头带密度 36%，不清障会常放失败）。
-- EEI 创建成功返回 true（出生市场以此落定 world15_lamps_done）。
world15_place_market_lighting = function(surface, mx, my)
    local eei = safe_create(surface, 'hidden-electric-energy-interface', {x = mx, y = my}, {force = 'player'})
    if not eei then return false end
    eei.electric_buffer_size = 1e9
    eei.power_production = 1e6 / 60
    eei.power_usage = 0
    eei.destructible = false
    eei.minable_flag = false
    local function clear_spot(x, y)
        local blockers = surface.find_entities_filtered({
            area = {{x - 0.5, y - 0.5}, {x + 0.5, y + 0.5}},
            type = {'tree', 'simple-entity'},
        })
        for _, e in ipairs(blockers) do
            if e and e.valid then e.destroy() end
        end
    end
    for _, ox in ipairs({-2, 2}) do
        clear_spot(mx + ox, my)
        local pole = safe_create(surface, 'small-electric-pole', {x = mx + ox, y = my}, {force = 'player'})
        if pole then
            pole.destructible = false
            pole.minable_flag = false
        end
    end
    for _, off in ipairs({{-2, -2}, {2, -2}, {-2, 2}, {2, 2}}) do
        clear_spot(mx + off[1], my + off[2])
        local lamp = safe_create(surface, 'small-lamp', {x = mx + off[1], y = my + off[2]}, {force = 'player'})
        if lamp then
            lamp.destructible = false
            lamp.minable_flag = false
        end
    end
    return true
end

-- 出生市场照明（逐字照搬「跃迁1」scripts/market.lua 169-197 的灯光设计，用户要求完全一样）。
-- shop 未就绪时静默等下个 [60] tick 重试；EEI 创建成功才落定 world15_lamps_done。
local function world15_spawn_market_lamps(surface)
    local this = WPT.get()
    if this.world15_lamps_done then return end
    local shop = this.shop
    if not shop or not shop.valid then return end
    if world15_place_market_lighting(surface, shop.position.x, shop.position.y) then
        this.world15_lamps_done = true
    end
end

local function world15_retry_market_lamps()
    local this = WPT.get()
    if (this and this.world_number or 0) ~= 15 then return end
    if this.world15_lamps_done then return end
    local surface = this.active_surface_index and game.surfaces[this.active_surface_index]
    if not surface or not surface.valid then return end
    world15_spawn_market_lamps(surface)
end

-- 出生圈草星 6×6 地块（2026-09 用户两次修正后定稿）：
-- 取消湖岸生成，只在出生点圈内随机生成，共 2 块（果冻果 ×1 + 玉马果 ×1）；
-- 每块 6×6：36 格全铺对应草星土壤；每颗草星树占地 3×3 → 一块地只种 4 棵
--（2×2 阵列，格点间距 3：中心位于 (1.5,1.5)/(1.5,4.5)/(4.5,1.5)/(4.5,4.5)），
-- 不再每格种满（原实现过密，用户要求 4 棵/块）。
-- 落点 = 随机角度 + 半径 25~125（出生圆半径 144，留边距；25 起步避开中央市场/发射井/宝箱区），
-- 6×6 必须整块在圆内且不含水面。失败仅记日志，不中断出生设施。
local WORLD15_SPAWN_PLOTS = {
    {plant = 'jellystem', soil = 'natural-jellynut-soil'},
    {plant = 'yumako-tree', soil = 'natural-yumako-soil'},
}

local function world15_spawn_plots(surface)
    local placed = 0
    for i = 1, #WORLD15_SPAWN_PLOTS do
        local pl = WORLD15_SPAWN_PLOTS[i]
        local spot = nil
        for attempt = 1, 60 do
            local angle = math.random() * 2 * math.pi
            local dist = 25 + math.random() * 100
            local cx = math.floor(math.cos(angle) * dist + 0.5)
            local cy = math.floor(math.sin(angle) * dist + 0.5)
            local ok = true
            for dx = 0, 5 do
                for dy = 0, 5 do
                    local x, y = cx + dx, cy + dy
                    if x * x + y * y > SPAWN_RADIUS_SQ then
                        ok = false
                        break
                    end
                    local t = surface.get_tile(x, y)
                    if t and t.name and (t.name == 'water' or t.name == 'deepwater') then
                        ok = false
                        break
                    end
                end
                if not ok then break end
            end
            if ok then
                spot = {x = cx, y = cy}
                break
            end
        end
        if not spot then
            log('[world15] 出生圈草星地块落点未找到（' .. pl.plant .. '），跳过')
        else
            -- 6×6 土壤
            for dx = 0, 5 do
                for dy = 0, 5 do
                    surface.set_tiles({{name = pl.soil, position = {x = spot.x + dx, y = spot.y + dy}}})
                end
            end
            -- 4 棵草星树（2×2 阵列，3×3 占地不重叠）
            for tx = 0, 1 do
                for ty = 0, 1 do
                    pcall(function()
                        local ent = surface.create_entity({
                            name = pl.plant,
                            position = {x = spot.x + 1.5 + tx * 3, y = spot.y + 1.5 + ty * 3},
                            force = 'neutral',
                        })
                        if ent and ent.valid then
                            ent.destructible = false
                        end
                    end)
                end
            end
            placed = placed + 1
        end
    end
    log('[world15] 出生圈草星地块放置完成 ' .. placed .. '/' .. #WORLD15_SPAWN_PLOTS)
end

local function build_spawn_facilities(surface)
    local this = WPT.get()
    if this.world15_spawn_done then return end
    this.world15_spawn_done = true

    -- 出生市场照明（2026-09 逐字照搬本地存档「跃迁1」scripts/market.lua 的建市场灯光设计，
    -- 用户要求「完全一样」；市场本身不抄——本图市场=主商店 this.shop，作锚点用其实际落点）。
    -- 见 world15_spawn_market_lamps：EEI 与市场同格重叠 + 左右 ±2 木电线杆 + 四对角 (±2,±2) 灯。
    world15_spawn_market_lamps(surface)
    -- 草星植物地块（果冻果/玉马果 6×6）：出生圈内随机生成（用户 2026-09 指示，
    -- 取消湖岸生成）。四种可挖掘点亮科技实体（雷神废墟/大型火山岩/铁铜叠层石）
    -- 仍在湖岸成团生成；出生圆内仅保留方解石（用户要求方解石不动）。
    world15_spawn_plots(surface)

    -- 出生圆内唯一 1×1 10k 方解石矿（特例，不算违反全图无可开采矿物）
    local cpos = surface.find_non_colliding_position('calcite', {x = 30, y = -80}, 60, 1)
    if cpos then
        safe_create(surface, 'calcite', cpos, {amount = 10000})
    end
end

local function world15_retry_spawn()
    local this = WPT.get()
    if (this and this.world_number or 0) ~= 15 then return end
    if this.world15_spawn_done then return end
    local surface = this.active_surface_index and game.surfaces[this.active_surface_index]
    if not surface or not surface.valid then return end
    if not surface.is_chunk_generated({x = 0, y = 0}) then
        surface.request_to_generate_chunks({x = 0, y = 0}, 6)
        surface.force_generate_chunk_requests()
        return
    end
    build_spawn_facilities(surface)
end

-- 矿物回收箱（失落之城式：矿物 → 金币，其他物资 → 销毁不给金币）。
-- 位置（用户调整 2026-09）：出生市场与火箭发射井连线的中点（两者都就绪才放置；
-- 任一缺失每 [60] tick 重试，超 10 秒未就绪记一次诊断日志——上一版箱子的位置写死在
-- 发射井顶缘上方 3 格，若发射井未被搜索区命中会静默不放置且无任何痕迹）。
local function world15_place_recycle_box()
    local this = WPT.get()
    if (this and this.world_number or 0) ~= 15 then return end
    if this.world15_recycle and this.world15_recycle.valid then return end
    local surface = this.active_surface_index and game.surfaces[this.active_surface_index]
    if not surface or not surface.valid then return end
    -- 修正（2026-09）：原检查 chunk (0,16)（y∈[512,544)）——出生区半径仅 144 格，
    -- 该区块永远不会生成 → 回收箱静默永不放置（用户「回收箱怎么没了」的根因）。
    -- 出生市场/发射井都在 chunk (0,0)（y∈[0,32)）内，改查该区块。
    if not surface.is_chunk_generated({x = 0, y = 0}) then return end
    local shop = this.shop
    local silos = surface.find_entities_filtered({
        area = {{x = -140, y = -140}, {x = 140, y = 180}},
        name = 'rocket-silo', force = 'player',
    })
    local silo = nil
    for _, s in pairs(silos) do
        if s and s.valid then silo = s break end
    end
    if not shop or not shop.valid or not silo then
        if not this.world15_recycle_warned then
            this.world15_recycle_first_tick = this.world15_recycle_first_tick or game.tick
            if game.tick - this.world15_recycle_first_tick > 600 then
                this.world15_recycle_warned = true
                log('[world15] 回收箱未放置：出生市场'
                    .. ((shop and shop.valid) and '就绪' or '缺失')
                    .. '、发射井' .. (silo and '就绪' or '未在搜索区内找到') .. '（持续重试中）')
            end
        end
        return
    end
    -- 中点；发射井/市场大小不同，中点即「两者之间」的空地
    local target = {
        x = math.floor((shop.position.x + silo.position.x) / 2),
        y = math.floor((shop.position.y + silo.position.y) / 2),
    }
    local pos = surface.find_non_colliding_position('steel-chest', target, 5, 0.5) or target
    -- 2026-09 用户要求：回收箱改为传说钢箱（quality = 'legendary'）
    local box = safe_create(surface, 'steel-chest', pos, {force = 'player', quality = 'legendary'})
    if not box then return end
    box.minable_flag = false
    box.destructible = false
    this.world15_recycle = box
    this.world15_recycle_tag = rendering.draw_text{
        text = {'amap.world15_recycle'},
        surface = surface,
        target = {entity = box, offset = {0, -2.6}},
        color = {r = 1, g = 0, b = 0, a = 1},
        scale = 1.05,
        font = 'default-large-semibold',
        alignment = 'center',
        scale_with_zoom = false,
    }
    this.world15_visuals_dirty = true
end

--（市场灯供电已改隐藏电源+变电站自动入网，原每 tick 手动充能的 world15_power_market_lamps 移除）

--==============================================================================
-- 出生市场追加商品 + 卖矿得金币（hook rock._on_shop_refreshed，幂等）
--==============================================================================

local function world15_shop_refresh()
    local this = WPT.get()
    if (this and this.world_number or 0) ~= 15 then return end
    -- 双保险（2026-09 换图污染排查）：map.world 与 world_number 必须同时为 15 才动市场，
    -- 防止任一字段在换图时序中滞后导致本 hook 误伤其它世界的出生市场。
    if diff.get('world') ~= 15 then return end
    local market = this.shop
    if not market or not market.valid then return end
    -- 灯 / 木制电线杆：全市场只保留本模块的固定价条目（2026-09 用户改价 20 金/个）。
    -- 随机市场池（basic_markets market.wire/power 分支）也会刷出同商品 → 先剔除同名
    -- 商品再按固定价重加，避免同一商品出现两个价格。
    local items = market.get_market_items()
    local keep = {}
    for _, item in ipairs(items) do
        local offer = item.offer
        local ed = offer and offer.effect_description
        -- 全伤害加成购买栏「禁用」方式（2026-10 修复错位）：不得剔除该条目（rock.lua 购买
        -- 回调按 offer_index 序号判定功能，删掉第3条会让天赋 7/8/9 前移成 6/7/8，点 65k 天赋
        -- 实际按沙虫处理——用户实测「买到沙虫、天赋没生效」）。改为保留 + 价格永久 100 万
        -- 买不起 = 等效禁用，索引不漂移；重炮伤害栏（amap.buy_arty_dam）保留原价逻辑。
        if ed and ed[1] == 'amap.buy_all_dam' then
            if item.price and item.price[1] then
                item.price[1].count = 1000000
            end
            keep[#keep + 1] = item
        elseif offer and offer.type == 'give-item'
            and (offer.item == 'small-lamp' or offer.item == 'small-electric-pole') then
            -- 丢弃：由下方固定价重新添加
        else
            keep[#keep + 1] = item
        end
    end
    market.clear_market_items()
    -- 「削弱敌方虫子伤害」（amap.buy_health_wall）与「重炮伤害」（amap.buy_arty_dam）
    -- 两栏价格 ×2（2026-09 用户要求 ×4；2026-10 用户 ×4 → ×2，仅出生市场）。
    -- refresh_shop 每次以基础价重建，这里统一乘 2，幂等。
    local price_x2 = {['amap.buy_health_wall'] = true, ['amap.buy_arty_dam'] = true}
    for _, item in ipairs(keep) do
        local ed = item.offer and item.offer.effect_description
        if ed and price_x2[ed[1]] and item.price and item.price[1] and item.price[1].count then
            item.price[1].count = item.price[1].count * 2
        end
        market.add_market_item(item)
    end
    -- 方解石 1 组(50) 2k / 灯 10 金（2026-09 用户改价：20→10）/ 木(50 个 8 金) /
    -- 木制电线杆 20 金（原 2 金，用户改价；定价依据：合成成本 1 木 + 1 铜缆，同灯价档）
    market.add_market_item({price = {{name = 'coin', count = 2000}}, offer = {type = 'give-item', item = 'calcite', count = 50}})
    market.add_market_item({price = {{name = 'coin', count = 10}}, offer = {type = 'give-item', item = 'small-lamp', count = 1}})
    market.add_market_item({price = {{name = 'coin', count = 8}}, offer = {type = 'give-item', item = 'wood', count = 50}})
    market.add_market_item({price = {{name = 'coin', count = 20}}, offer = {type = 'give-item', item = 'small-electric-pole', count = 1}})
    -- 卖矿得金币：1 组(50) 任意矿 → 2 金币
    for i = 1, #WORLD15_ORE_LIST do
        local ore = WORLD15_ORE_LIST[i]
        market.add_market_item({price = {{name = ore, count = 50}}, offer = {type = 'give-item', item = 'coin', count = 2}})
    end
end

rock._on_shop_refreshed = world15_shop_refresh

--==============================================================================
-- 岛屿市场剔除全伤害加成栏（海景房天赋岛屿 + 湖岸资源岛）
--   island_manager.add_upgrade_items 在岛屿 Lv5 时把「全伤害+1%」（amap.buy_all_dam）
--   加进市场。世界15 要求玩家伤害只由默认+科技构成，定期移除该条目；
--   其余条目（购买岛屿 / 生产物品 / 矿容 / 天赋 / 副本入口 / 重炮伤害）全部保留。
--   幂等：已移除则跳过，不清不重加。
--==============================================================================

local function world15_purge_island_all_dam()
    local this = WPT.get()
    if (this and this.world_number or 0) ~= 15 then return end
    if not this.islands then return end
    for _, island in pairs(this.islands) do
        local m = island and island.market_entity
        if m and m.valid then
            local items = m.get_market_items()
            local keep = {}
            local removed = false
            for _, item in ipairs(items) do
                local ed = item.offer and item.offer.effect_description
                if ed and ed[1] == 'amap.buy_all_dam' then
                    removed = true
                else
                    keep[#keep + 1] = item
                end
            end
            if removed then
                m.clear_market_items()
                for _, item in ipairs(keep) do
                    m.add_market_item(item)
                end
            end
        end
    end
end

--==============================================================================
-- 永久不削减（世界15）：还原 reduce_player_damage_over_time 造成的伤害削减
--   tank.lua 波数>1200 后每 20 分钟对玩家阵营施加负向 multiplier。世界15
--   在 on_world_start 记录进入时的 multiplier（玩家从其它世界带入的合法加成），
--   此后只要 this.damage_multiplier 偏离该值（被削减 / 漏网的伤害加成），
--   就按 multiplier 反算把 WORLD15_DAMAGE_TYPES 全部还原到 enter 水平 →
--   永不削减、也不允许世界15内任何 multiplier 型伤害加成立足。
--   科技（加法分量）不受影响；还原对科技无副作用。
--==============================================================================

local function world15_normalize_damage()
    local this = WPT.get()
    if (this and this.world_number or 0) ~= 15 then return end
    local enter = this.world15_dmg_enter or 1
    local m = this.damage_multiplier or 1
    if m == enter then return end
    local force = game.forces.player
    for _, k in ipairs(WORLD15_DAMAGE_TYPES) do
        local cur = force.get_ammo_damage_modifier(k)
        force.set_ammo_damage_modifier(k, (cur + 1) / m * enter - 1)
    end
    this.damage_multiplier = enter
    this.player_damage_modifiers = {}
    this.player_damage_reduction_count = 0
end

--==============================================================================
-- 矿物回收箱：每 6 秒回收。矿物（矿石类）1 组 = 1 金币分给所有人；
-- 其他物资一律销毁（不给金币）。
--==============================================================================

-- 回收成功飘字：3 秒后清除（重复成功时旧文字先销毁再重画）
local recycle_gain_clear_token
recycle_gain_clear_token = Token.register(function()
    local this = WPT.get()
    if this.world15_recycle_gain and this.world15_recycle_gain.valid then
        this.world15_recycle_gain.destroy()
    end
    this.world15_recycle_gain = nil
end)

local function world15_recycle_tick()
    local this = WPT.get()
    if (this and this.world_number or 0) ~= 15 then return end
    local box = this.world15_recycle
    if not box or not box.valid then return end
    local inv = box.get_inventory(defines.inventory.chest)
    if not inv then return end
    local contents = inv.get_contents()
    if next(contents) == nil then return end
    local coins = 0
    for _, item in pairs(contents) do
        if WORLD15_RECYCLE_ORES[item.name] then
            local stack_size = prototypes.item[item.name] and prototypes.item[item.name].stack_size or 50
            local full = math.floor(item.count / stack_size)
            if full > 0 then
                coins = coins + full
                inv.remove({name = item.name, count = full * stack_size, quality = item.quality})
            end
        else
            -- 非矿物物资：直接销毁，不给金币
            inv.remove({name = item.name, count = item.count, quality = item.quality})
        end
    end
    if coins <= 0 then return end
    local players = {}
    for _, p in pairs(game.connected_players) do
        if p and p.valid and p.force.name == 'player' then
            players[#players + 1] = p
        end
    end
    if #players == 0 then return end
    local each = math.floor(coins / #players)
    if each >= 1 then
        for i = 1, #players do
            players[i].insert({name = 'coin', count = each})
        end
        -- 不再全图公告（用户要求）：只在回收箱上方飘字提醒，3 秒后消失
        if this.world15_recycle_gain and this.world15_recycle_gain.valid then
            this.world15_recycle_gain.destroy()
        end
        this.world15_recycle_gain = rendering.draw_text{
            text = {'amap.world15_recycle_gain', coins, #players, each},
            surface = box.surface,
            target = {entity = box, offset = {0, -3.9}},
            color = {r = 0.4, g = 1, b = 0.4, a = 1},
            scale = 1.0,
            font = 'default-large',
            alignment = 'center',
            scale_with_zoom = false,
        }
        Task.set_timeout_in_ticks(180, recycle_gain_clear_token)
    end
end

--==============================================================================
-- 通关回收箱（2026-09 用户需求：照搬存档「黑暗1」12 箱布局 + 瓶子吞噬计数 + 通关判定）
--
-- 布局（实体中心坐标，以出生点 (0,0) 为基准，与存档「黑暗1」完全一致）：
--   左组 3 列 × 2 行：x=-5.5/-4.5/-3.5，y=-4.5/-3.5；右组 x=4.5/5.5/6.5 同 y
--   每列上下各 1 个 turbo-loader（绿色装载机，Space Age 绿带装载机）：
--   上排 y=-6 朝南、下排 y=-2 朝北，全部 input 型（方向与存档一致）；
--   筛选按用户指定：上排 红/绿/灰/蓝/紫/黄瓶、下排 草/橙/白/粉/靛/黑瓶（12 瓶各对应 1 箱）；
--   箱子存档为普通钢箱 → 本图按用户要求改传说钢箱。主市场位于两组之间（(0,-5)），无碰撞。
-- 机制：12 种科研瓶进入箱子即被吞噬（每分钟 3600 tick 一次，与矿物回收箱同理），
--   吞噬量记录进 storage（持久化）。每 10 分钟（10 次吞噬）结算一次窗口：
--   ① 每种瓶窗口内合计（12 箱相加）≥140000（「10m 统计一次总数量，12 个瓶子各 ≥140000」）；
--   ② 12 个箱子累计吞噬（任意瓶合计）均 ≥140000（「所有箱子即 12 个箱子都达成」）。
--   窗口达成 → 连续计数 +1；第 1 次公告「已完成10m通关进度，还剩20m」、第 2 次
--   「已完成20m通关进度，还剩10m」、连续 3 次 → 公告「黑暗地穴已通关！」。
--   窗口未达成 → 连续计数清零并记日志（真正的「持续 3 次」语义）。
-- 箱子与绿色装载机均不可摧毁 / 不可开采 / 不可点击（operable=false，只能由装载机喂入）。
-- 组名标注：左右两组中间列上方各 1 个「通关回收箱」名字（共 2 个，样式同矿物回收箱）。
--==============================================================================
local CLEAR_BOTTLE_TYPES = {
    'automation-science-pack', 'logistic-science-pack', 'military-science-pack',
    'chemical-science-pack', 'production-science-pack', 'utility-science-pack',
    'space-science-pack', 'metallurgic-science-pack', 'electromagnetic-science-pack',
    'agricultural-science-pack', 'cryogenic-science-pack', 'promethium-science-pack',
}
local CLEAR_BOTTLE_TYPE_SET = {}
for i = 1, #CLEAR_BOTTLE_TYPES do
    CLEAR_BOTTLE_TYPE_SET[CLEAR_BOTTLE_TYPES[i]] = true
end
local CLEAR_WINDOW_SWALLOWS = 10       -- 窗口 = 10 次吞噬 = 10 分钟
local CLEAR_TYPE_TARGET = 140000       -- 每窗口每种瓶 ≥140000（12 箱合计）
local CLEAR_CHEST_TARGET = 140000      -- 每箱累计吞噬 ≥140000（12 箱都达成）
local CLEAR_WINDOWS_NEEDED = 3         -- 连续 3 个窗口 → 通关

local CLEAR_CHEST_POSITIONS = {
    {x = -5.5, y = -4.5}, {x = -4.5, y = -4.5}, {x = -3.5, y = -4.5},
    {x = -5.5, y = -3.5}, {x = -4.5, y = -3.5}, {x = -3.5, y = -3.5},
    {x = 4.5, y = -4.5}, {x = 5.5, y = -4.5}, {x = 6.5, y = -4.5},
    {x = 4.5, y = -3.5}, {x = 5.5, y = -3.5}, {x = 6.5, y = -3.5},
}
-- 装载机：{x, y, dir, filter}；dir 8=南（上排，从北侧皮带吸入、向下喂入上排箱子）、
-- 0=北（下排，从南侧皮带吸入、向上喂入下排箱子）；与存档方向一致。
-- 筛选（用户 2026-09 指定，12 瓶各对应 1 箱）：
--   上排从左到右：红/绿/灰/蓝/紫/黄瓶（automation/logistic/military/chemical/production/utility）
--   下排从左到右：草/橙/白/粉/靛/黑瓶（agricultural/metallurgic/space/electromagnetic/cryogenic/promethium）
local CLEAR_LOADER_POSITIONS = {
    {x = -5.5, y = -6, dir = 8, filter = 'automation-science-pack'},
    {x = -4.5, y = -6, dir = 8, filter = 'logistic-science-pack'},
    {x = -3.5, y = -6, dir = 8, filter = 'military-science-pack'},
    {x = -5.5, y = -2, dir = 0, filter = 'agricultural-science-pack'},
    {x = -4.5, y = -2, dir = 0, filter = 'metallurgic-science-pack'},
    {x = -3.5, y = -2, dir = 0, filter = 'space-science-pack'},
    {x = 4.5, y = -6, dir = 8, filter = 'chemical-science-pack'},
    {x = 5.5, y = -6, dir = 8, filter = 'production-science-pack'},
    {x = 6.5, y = -6, dir = 8, filter = 'utility-science-pack'},
    {x = 4.5, y = -2, dir = 0, filter = 'electromagnetic-science-pack'},
    {x = 5.5, y = -2, dir = 0, filter = 'cryogenic-science-pack'},
    {x = 6.5, y = -2, dir = 0, filter = 'promethium-science-pack'},
}
-- 组名标签：每组中间列上方各 1 个（左右共 2 个名字，样式同矿物回收箱标注）
local CLEAR_GROUP_LABELS = {
    {x = -4.5, y = -8.2},
    {x = 5.5, y = -8.2},
}

-- 组名标注重画（rendering 不跨存档，缺失时由 [60] tick 兜底重画）
local function world15_redraw_clear_labels(surface)
    local this = WPT.get()
    if not surface or not surface.valid then return end
    if this.world15_clear_tags then
        for _, t in ipairs(this.world15_clear_tags) do
            if t and t.valid then
                t.destroy()
            end
        end
    end
    local tags = {}
    for i = 1, #CLEAR_GROUP_LABELS do
        local lp = CLEAR_GROUP_LABELS[i]
        tags[i] = rendering.draw_text{
            text = {'amap.world15_clear_chest'},
            surface = surface,
            target = {x = lp.x, y = lp.y},
            color = {r = 1, g = 0, b = 0, a = 1},
            scale = 1.05,
            font = 'default-large-semibold',
            alignment = 'center',
            scale_with_zoom = false,
        }
    end
    this.world15_clear_tags = tags
    this.world15_visuals_dirty = true
end

-- 通关回收箱放置（[60] tick 重试）：等出生圈 4 个 chunk 全部生成后一次性摆放。
-- 幂等：已放好的箱子/装载机直接复用，失败项每 tick 补齐（不重复创建）。
local function world15_place_clear_chests()
    local this = WPT.get()
    if (this and this.world_number or 0) ~= 15 then return end
    if this.world15_clear_done then return end
    local surface = this.active_surface_index and game.surfaces[this.active_surface_index]
    if not surface or not surface.valid then return end
    -- 布局横跨 chunk (-1,-1)~(0,0)，全部生成后才可放置
    for _, c in ipairs({{-1, -1}, {0, -1}, {-1, 0}, {0, 0}}) do
        if not surface.is_chunk_generated({x = c[1], y = c[2]}) then
            surface.request_to_generate_chunks({x = 0, y = 0}, 1)
            surface.force_generate_chunk_requests()
            return
        end
    end
    -- 清理自然障碍（树/岩石/植物/非石油资源；不碰玩家建筑与油田）
    local blockers = surface.find_entities_filtered({
        area = {{-7.5, -7.5}, {7.5, -0.5}},
        type = {'tree', 'simple-entity', 'plant', 'resource'},
    })
    for _, e in pairs(blockers) do
        if e and e.valid and e.name ~= 'crude-oil' then
            e.destroy()
        end
    end
    local chests = {}
    local ok_all = true
    for i = 1, #CLEAR_CHEST_POSITIONS do
        local pos = CLEAR_CHEST_POSITIONS[i]
        local box = nil
        local existing = surface.find_entities_filtered({
            area = {{pos.x - 0.4, pos.y - 0.4}, {pos.x + 0.4, pos.y + 0.4}},
            name = 'steel-chest',
        })
        for _, e in pairs(existing) do
            if e and e.valid then
                box = e
                break
            end
        end
        if not box then
            box = safe_create(surface, 'steel-chest', pos, {force = 'player', quality = 'legendary'})
        end
        if box and box.valid then
            box.minable_flag = false
            box.destructible = false
            box.operable = false
            chests[i] = box
        else
            ok_all = false
            log('[world15] 通关回收箱放置失败 @ ' .. tostring(pos.x) .. ',' .. tostring(pos.y))
        end
    end
    local loaders = {}
    for i = 1, #CLEAR_LOADER_POSITIONS do
        local lp = CLEAR_LOADER_POSITIONS[i]
        local l = nil
        local existing = surface.find_entities_filtered({
            area = {{lp.x - 0.4, lp.y - 0.6}, {lp.x + 0.4, lp.y + 0.6}},
            name = 'turbo-loader',
        })
        for _, e in pairs(existing) do
            if e and e.valid then
                l = e
                break
            end
        end
        if not l then
            l = safe_create(surface, 'turbo-loader', {x = lp.x, y = lp.y}, {force = 'player'})
        end
        if l and l.valid then
            -- 顺序有讲究（实测 2.1.17）：设 loader_type='input' 时引擎会把朝向自动翻转 180°；
            -- 必须先设 input 再设 direction（后设 direction 不会翻转），才能得到期望朝向
            pcall(function() l.loader_type = 'input' end)
            l.direction = lp.dir
            -- 筛选（用户指定）：每台装载机只放行对应的 1 种科研瓶
            l.set_filter(1, lp.filter)
            l.minable_flag = false
            l.destructible = false
            l.operable = false
            loaders[i] = l
        else
            ok_all = false
            log('[world15] 绿色装载机放置失败 @ ' .. tostring(lp.x) .. ',' .. tostring(lp.y))
        end
    end
    if not ok_all then
        log('[world15] 通关回收箱未完整放置，下个 [60] tick 补齐缺口')
        return
    end
    this.world15_clear_chests = chests
    this.world15_clear_loaders = loaders
    this.world15_clear_done = true
    this.world15_clear_swallows = 0
    this.world15_clear_window = {}
    this.world15_clear_chest_total = {}
    this.world15_clear_streak = 0
    world15_redraw_clear_labels(surface)
    game.print({'amap.world15_clear_ready'}, {r = 0.4, g = 1, b = 0.4})
    log('[world15] 通关回收箱放置完成（12 传说钢箱 + 12 绿色装载机）')
end

-- 标签兜底：rendering 不跨存档，存档重载后缺失即重画
local function world15_retry_clear_labels()
    local this = WPT.get()
    if (this and this.world_number or 0) ~= 15 then return end
    if not this.world15_clear_done then return end
    local surface = this.active_surface_index and game.surfaces[this.active_surface_index]
    if not surface or not surface.valid then return end
    local need = false
    for _, t in ipairs(this.world15_clear_tags or {}) do
        if not t or not t.valid then
            need = true
            break
        end
    end
    if need then
        world15_redraw_clear_labels(surface)
    end
end

-- 通关进度：左侧红字标签（用户要求：10m/20m 播报用红字在左侧显示，取代不明显的中缝白字）。
-- 每窗口结算后刷新 caption；通关后销毁。跨存档 GUI 会持久化，由 on_world_start 清理。
local function world15_clear_refresh_progress(streak)
    local this = WPT.get()
    this.world15_visuals_dirty = true
    for _, player in pairs(game.connected_players) do
        if player and player.valid and player.force.name == 'player' then
            local lbl = player.gui.left['world15_clear_progress']
            if not lbl or not lbl.valid then
                lbl = player.gui.left.add{type = 'label', name = 'world15_clear_progress', style = 'bold_label'}
            end
            lbl.style.font_color = {r = 1, g = 0.15, b = 0.15}
            if streak <= 0 then
                lbl.caption = {'amap.world15_clear_progress_none'}
            elseif streak == 1 then
                lbl.caption = {'amap.world15_clear_progress1'}
            elseif streak == 2 then
                lbl.caption = {'amap.world15_clear_progress2'}
            else
                lbl.caption = {'amap.world15_clear_progress3'}
            end
        end
    end
end

-- 清除左侧进度标签（通关后 / 新局）
local function world15_clear_remove_progress()
    for _, player in pairs(game.connected_players) do
        if player and player.valid then
            local lbl = player.gui.left['world15_clear_progress']
            if lbl and lbl.valid then
                lbl.destroy()
            end
        end
    end
end

-- 通关全屏公告（参考本地「跃迁1」warp_fx.lua 红色大字倒计时）：
-- 逐玩家 rendering.draw_text、target 挂角色（跟随）、players={player} 只该玩家可见、
-- time_to_live=1800（30 秒）自动销毁、逐玩家 pcall（单个玩家瞬态异常不影响其他人）。
-- 大字「恭喜：黑暗地穴已通关！」红字居中；下方小字白字列出参与本图玩家 id，分左右两列居中。
local CLEAR_WIN_TTL = 1800              -- 30 秒
local CLEAR_WIN_BIG_SCALE = 12          -- 大字 scale（跃迁参考：12~14）
local CLEAR_WIN_SMALL_SCALE = 3.2       -- 玩家 id 小字 scale
local CLEAR_WIN_COL_OFFSET = 10         -- 两列相对角色左右偏移（格）
local CLEAR_WIN_ROW_STEP = 1.9          -- 同列每行 id 的纵向步长（格）

local function world15_clear_win_display()
    -- 收集参与本图的玩家（世界15 在线玩家），排序后分左右两列
    local names = {}
    for _, p in pairs(game.connected_players) do
        if p and p.valid and p.force.name == 'player' then
            names[#names + 1] = p.name
        end
    end
    table.sort(names)
    local half = math.ceil(#names / 2)
    for _, player in pairs(game.connected_players) do
        if player and player.valid and player.force.name == 'player' then
            local char = player.character
            if char and not char.valid then char = nil end
            local surface = char and char.surface or player.surface
            local big_target = char or player.position
            -- 小字挂点：有角色用 entity+offset（跟随），否则固定坐标
            local function col_target(ox, oy)
                if char then
                    return {entity = char, offset = {ox, oy}}
                end
                return {x = big_target.x + ox, y = big_target.y + oy}
            end
            -- 大字：红字居中，30 秒
            pcall(rendering.draw_text, {
                text = {'amap.world15_clear_win_full'},
                surface = surface,
                target = big_target,
                color = {r = 1, g = 0.15, b = 0.15},
                scale = CLEAR_WIN_BIG_SCALE,
                font = 'default-large-bold',
                alignment = 'center',
                vertical_alignment = 'middle',
                players = {player},
                time_to_live = CLEAR_WIN_TTL,
            })
            -- 下方小字：第一行左列标题「通关玩家：」，第二行起两列玩家 id（右列标题行留空）
            local title_y = 14
            local row_y = title_y + CLEAR_WIN_ROW_STEP
            pcall(rendering.draw_text, {
                text = {'amap.world15_clear_win_players'},
                surface = surface,
                target = col_target(-CLEAR_WIN_COL_OFFSET, title_y),
                color = {r = 1, g = 1, b = 1, a = 1},
                scale = CLEAR_WIN_SMALL_SCALE,
                alignment = 'center',
                vertical_alignment = 'middle',
                players = {player},
                time_to_live = CLEAR_WIN_TTL,
            })
            for i = 1, half do
                pcall(rendering.draw_text, {
                    text = names[i],
                    surface = surface,
                    target = col_target(-CLEAR_WIN_COL_OFFSET, row_y + (i - 1) * CLEAR_WIN_ROW_STEP),
                    color = {r = 1, g = 1, b = 1, a = 1},
                    scale = CLEAR_WIN_SMALL_SCALE,
                    alignment = 'center',
                    vertical_alignment = 'middle',
                    players = {player},
                    time_to_live = CLEAR_WIN_TTL,
                })
            end
            for i = half + 1, #names do
                pcall(rendering.draw_text, {
                    text = names[i],
                    surface = surface,
                    target = col_target(CLEAR_WIN_COL_OFFSET, row_y + (i - half - 1) * CLEAR_WIN_ROW_STEP),
                    color = {r = 1, g = 1, b = 1, a = 1},
                    scale = CLEAR_WIN_SMALL_SCALE,
                    alignment = 'center',
                    vertical_alignment = 'middle',
                    players = {player},
                    time_to_live = CLEAR_WIN_TTL,
                })
            end
        end
    end
end

-- 10 分钟窗口结算：12 种瓶窗口合计均 ≥140000（12 箱相加）+ 12 箱累计各 ≥140000
-- → 窗口达成；连续 3 次 → 通关。未达成 → 连续计数清零并记日志。
-- 注意：必须声明在吞噬函数之前（Lua 局部变量作用域规则——函数体内引用需先于定义处可见）。
local function world15_clear_eval_window()
    local this = WPT.get()
    local window = this.world15_clear_window
    local chest_total = this.world15_clear_chest_total
    local missing = {}
    for i = 1, #CLEAR_BOTTLE_TYPES do
        local t = CLEAR_BOTTLE_TYPES[i]
        if (window[t] or 0) < CLEAR_TYPE_TARGET then
            missing[#missing + 1] = t .. '=' .. (window[t] or 0)
        end
    end
    local low_chests = {}
    for i = 1, #CLEAR_CHEST_POSITIONS do
        if (chest_total[i] or 0) < CLEAR_CHEST_TARGET then
            low_chests[#low_chests + 1] = i
        end
    end
    this.world15_clear_window = {}
    if #missing > 0 or #low_chests > 0 then
        this.world15_clear_streak = 0
        world15_clear_refresh_progress(0)
        log('[world15] 通关窗口未达成：不足瓶种[' .. table.concat(missing, ',')
            .. '] 不足箱子[' .. table.concat(low_chests, ',') .. ']，连续进度清零')
        return
    end
    this.world15_clear_streak = this.world15_clear_streak + 1
    local streak = this.world15_clear_streak
    world15_clear_refresh_progress(streak)
    if streak == 1 then
        game.print({'amap.world15_clear_win1'}, {r = 1, g = 0.15, b = 0.15})
    elseif streak == 2 then
        game.print({'amap.world15_clear_win2'}, {r = 1, g = 0.15, b = 0.15})
    elseif streak >= CLEAR_WINDOWS_NEEDED then
        if not this.world15_clear_done_win then
            this.world15_clear_done_win = true
            game.print({'amap.world15_clear_win'}, {r = 1, g = 0.15, b = 0.15})
            world15_clear_remove_progress()
            world15_clear_win_display()
        end
        log('[world15] 黑暗地穴已通关！（12 瓶 ×140000 × 连续 3 窗口，且 12 箱累计各 ≥140000）')
    end
    log('[world15] 通关窗口达成（第 ' .. streak .. ' 次连续）')
end

-- 每分钟吞噬一次（与矿物回收箱同机制）：12 种科研瓶销毁并记录数量；
-- 其他物资一并销毁（防堵箱，与矿物回收箱销毁非矿物同理）。
local function world15_clear_swallow_tick()
    local this = WPT.get()
    if (this and this.world_number or 0) ~= 15 then return end
    if not this.world15_clear_done then return end
    -- 通关达成后：该存档不再统计吞噬、不再结算窗口、不再公告（2026-09 用户要求）
    if this.world15_clear_done_win then return end
    local chests = this.world15_clear_chests
    if not chests then return end
    local window = this.world15_clear_window
    local chest_total = this.world15_clear_chest_total
    local total_swallowed = 0
    for i = 1, #chests do
        local box = chests[i]
        if not box or not box.valid then
            log('[world15] 通关回收箱缺失（index=' .. i .. '），本分钟跳过')
            return
        end
        local inv = box.get_inventory(defines.inventory.chest)
        if inv then
            local contents = inv.get_contents()
            for _, item in pairs(contents) do
                local t = item.name
                if CLEAR_BOTTLE_TYPE_SET[t] then
                    inv.remove({name = t, count = item.count, quality = item.quality})
                    window[t] = (window[t] or 0) + item.count
                    chest_total[i] = (chest_total[i] or 0) + item.count
                    total_swallowed = total_swallowed + item.count
                else
                    inv.remove({name = t, count = item.count, quality = item.quality})
                end
            end
        end
    end
    this.world15_clear_swallows = this.world15_clear_swallows + 1
    if total_swallowed > 0 then
        log('[world15] 通关回收箱吞噬 ' .. total_swallowed .. ' 瓶（累计第 ' .. this.world15_clear_swallows .. ' 分钟）')
    end
    if this.world15_clear_swallows % CLEAR_WINDOW_SWALLOWS == 0 then
        world15_clear_eval_window()
    end
end

--==============================================================================
-- 黑暗出虫
--==============================================================================

-- 灯光覆盖判定（只认 lamp 实体：能量>25 且半径 LIGHT_RADIUS 内）。
-- 夜视仪/手电（flashlight）不是 lamp 实体 → 不计入，探照灯亮着照样算黑暗。
local function lamp_covers(player)
    local surface = player.physical_surface
    if not surface or not surface.valid then return false end
    local this = WPT.get()
    if surface.index ~= this.active_surface_index then return false end
    local pos = player.physical_position
    local lamps = surface.find_entities_filtered({
        area = {{pos.x - 20, pos.y - 20}, {pos.x + 20, pos.y + 20}},
        type = 'lamp',
    })
    for _, lamp in pairs(lamps) do
        if lamp and lamp.valid and lamp.energy > 25 then
            local lx, ly = lamp.position.x, lamp.position.y
            if (pos.x - lx) * (pos.x - lx) + (pos.y - ly) * (pos.y - ly) <= LIGHT_RADIUS * LIGHT_RADIUS then
                return true
            end
        end
    end
    return false
end

local function is_in_darkness(player)
    local pos = player.physical_position
    local d2 = pos.x * pos.x + pos.y * pos.y
    if d2 <= SPAWN_RADIUS_SQ then return false end
    return not lamp_covers(player)
end

-- 黑暗地块（out-of-map）瓦片判定：虫类不能生成在这种不可通行格上（用户要求：禁止黑暗区块生成虫子）。
local function tile_is_dark_at(surface, x, y)
    return surface.get_tile(math.floor(x), math.floor(y)).name == 'out-of-map'
end

-- 在候选点附近找一个「非黑暗瓦片 + 无实体碰撞」的落点（先原候选，再 0~4 格方环），找不到返回 nil。
local function find_dark_free_spawn_position(surface, name, pos)
    if not tile_is_dark_at(surface, pos.x, pos.y) then
        local p = surface.find_non_colliding_position(name, pos, 3, 1)
        if p and not tile_is_dark_at(surface, p.x, p.y) then
            return p
        end
    end
    local cx, cy = math.floor(pos.x), math.floor(pos.y)
    for r = 1, 4 do
        for dx = -r, r do
            for dy = -r, r do
                if math.max(math.abs(dx), math.abs(dy)) == r then
                    local tx, ty = cx + dx, cy + dy
                    if not tile_is_dark_at(surface, tx + 0.5, ty + 0.5) then
                        local np = surface.find_non_colliding_position(name, {x = tx + 0.5, y = ty + 0.5}, 2, 1)
                        if np and not tile_is_dark_at(surface, np.x, np.y) then
                            return np
                        end
                    end
                end
            end
        end
    end
    return nil
end

local function world15_spawn_dark_biters(player, count)
    local surface = player.physical_surface
    if not surface or not surface.valid then return end
    local pos = player.physical_position
    local spawned = 0
    for i = 1, count do
        local name
        if math.random(1, 3) == 1 then
            name = BiterRolls.wave_defense_roll_spitter_name()
        else
            name = BiterRolls.wave_defense_roll_biter_name()
        end
        if name then
            -- 选离玩家最近的可生成点（小偏移 + 小搜索半径），虫子贴脸出现；
            -- 落点强制避开黑暗地块（无合格落点的个体直接放弃，不再生成到 out-of-map 上）
            local p = find_dark_free_spawn_position(surface, name, {
                x = pos.x + math.random(-2, 2),
                y = pos.y + math.random(-2, 2),
            })
            local e = p and surface.create_entity({name = name, position = p, force = game.forces.enemy})
            if e and e.valid then
                spawned = spawned + 1
                e.ai_settings.allow_try_return_to_spawner = false
                e.ai_settings.allow_destroy_when_commands_fail = false
            end
        end
    end
    if spawned > 0 then
        player.print({'amap.world15_dark_spawn', spawned}, {r = 1, g = 0.3, b = 0.3})
    end
end

-- 夜视仪禁装（用户确认：方案A 事件秒退 + 直接销毁）：
-- 旧「就地禁用」在 2.1.17 三通道全失效（intensity 只读 / LuaEquipment 无 enabled /
-- LuaEquipmentGrid 无 child_grid，见用户游戏日志实证），整块替换为「装入即被取出销毁」：
--   1) on_player_placed_equipment / on_equipment_inserted 事件：同一 tick take 出夜视仪，
--      效果上等于「装不进去」；
--   2) [30]tick dark_tick 兜底扫描：处理跨世界穿着的装甲自带夜视（穿戴不产生放置事件）。
-- 覆盖网格：角色 grid（2.x 角色/装甲装备格合一）、玩家驾驶载具 grid（坦克/蜘蛛）；
-- 火车（机车）在 2.1 无装备网格，本就装不了夜视，无需处理。
-- take 只返回 {name,quality,count} 描述表，取出物会回流背包/地面两处，一律清除 = 销毁。
local function destroy_taken_night_vision(grid, by_player, removed)
    if not removed then return end
    local owner = nil
    local ok_own, o = pcall(function() return grid.entity_owner end)
    if ok_own then owner = o end
    local character = nil
    if by_player and by_player.valid then character = by_player.character end
    if not character and owner and owner.valid and owner.character then
        character = owner.character
    end
    if character and character.valid then
        pcall(function()
            local inv = character.get_inventory(defines.inventory.character_main)
            if inv then
                inv.remove({name = removed.name, quality = removed.quality, count = removed.count})
            end
        end)
    end
    if owner and owner.valid and owner.surface and owner.surface.valid then
        local p = owner.position
        local drops = owner.surface.find_entities_filtered({
            area = {{p.x - 3, p.y - 3}, {p.x + 3, p.y + 3}},
            type = 'item-on-ground',
        })
        for _, ent in pairs(drops) do
            if ent and ent.valid then
                local st = ent.stack
                if st and st.valid_for_read and st.name == 'night-vision-equipment' then
                    ent.destroy()
                end
            end
        end
    end
end

-- 从单个装备格弹出全部夜视仪（任意品质），返回弹出数量
local function eject_night_vision_grid(grid, by_player)
    if not grid or not grid.valid then return 0 end
    local eqs = grid.equipment
    if not eqs then return 0 end
    local count = 0
    for i = #eqs, 1, -1 do
        local eq = eqs[i]
        if eq and eq.valid and eq.name == 'night-vision-equipment' then
            local removed = nil
            local ok = pcall(function() removed = grid.take({equipment = eq}) end)
            if ok then
                count = count + 1
                destroy_taken_night_vision(grid, by_player, removed)
            end
        end
    end
    return count
end

-- [30]tick 兜底：角色/装甲自带 + 当前驾驶载具
local function eject_night_vision(player)
    local ok, err = pcall(function()
        local character = player.character
        if character and character.valid and character.grid then
            eject_night_vision_grid(character.grid, player)
        end
        local veh = player.physical_vehicle
        if veh and veh.valid and veh.grid then
            eject_night_vision_grid(veh.grid, player)
        end
    end)
    if not ok then
        log('[world15] 夜视仪兜底扫描异常(仅一次可见): ' .. tostring(err))
    end
end

-- 事件秒退：放置瞬间取出销毁
local function world15_on_placed_equipment(event)
    local this = WPT.get()
    if (this and this.world_number or 0) ~= 15 then return end
    local eq = event.equipment
    if not eq or not eq.valid or eq.name ~= 'night-vision-equipment' then return end
    local grid = event.grid
    if not grid or not grid.valid then return end
    local player = event.player_index and game.players[event.player_index] or nil
    local removed = nil
    local ok = pcall(function() removed = grid.take({equipment = eq}) end)
    if ok then
        destroy_taken_night_vision(grid, player, removed)
        if player and player.valid then
            player.print({'amap.world15_nv_destroyed'}, {r = 1, g = 0.35, b = 0.2})
        end
    end
end

local function world15_dark_tick()
    local this = WPT.get()
    if (this and this.world_number or 0) ~= 15 then return end
    local wave = WD.get('wave_number') or 0
    -- 黑暗出虫改为「一整波」：沿用威胁事件 more_biter 的单波数量公式
    -- （floor((32 + floor(波次*0.1)) * 0.8)，公式自身封顶 51；DARK_SPAWN_CAP 仅作稳定性护栏）
    local spawn_count = math.floor((32 + math.floor(math.max(wave, 1) * 0.1)) * 0.8)
    if spawn_count > DARK_SPAWN_CAP then spawn_count = DARK_SPAWN_CAP end

    for _, player in pairs(game.connected_players) do
        if player and player.valid and player.force.name == 'player' then
            local character = player.character
            if character and character.valid then
                -- 夜视仪兜底扫描（事件秒退为主，这里处理跨世界穿着带进来的存量）
                eject_night_vision(player)
            end
            if character and character.valid and not character.driving and character.health and character.health > 0 then
                -- 头顶探照灯自动开关（2026-09 用户）：无照明灯覆盖→自动开手电照亮视野，
                -- 进入照明灯范围→自动关（原「恒禁用」会连玩家手动开的灯一并打掉，导致黑夜视野
                -- 下头顶灯永远打不开）。手电不是 lamp 实体，不参与黑暗判定 → 停留满 5s 照样出虫。
                if lamp_covers(player) then
                    character.disable_flashlight()
                else
                    character.enable_flashlight()
                end
            end
            if is_in_darkness(player) then
                if not this.world15_dark_ticks then this.world15_dark_ticks = {} end
                -- 附近虫子上限保护（用户 2026-09）：玩家附近（半径 30 格）虫子 >180 时
                -- 暂停黑暗出虫（计时冻结不累计，防止越打越多）；降到 180 以下恢复累计触发。
                -- 出生地依旧不触发（is_in_darkness 已含出生圆判定）。
                local near = player.physical_surface.count_entities_filtered({
                    position = player.physical_position,
                    radius = DARK_BITER_LIMIT_RADIUS,
                    force = 'enemy',
                    type = 'unit',
                })
                if near > DARK_BITER_LIMIT_COUNT then
                    this.world15_dark_ticks[player.index] = 0
                else
                    this.world15_dark_ticks[player.index] = (this.world15_dark_ticks[player.index] or 0) + DARKNESS_TICK_INTERVAL
                    if this.world15_dark_ticks[player.index] >= DARKNESS_TICKS_REQUIRED then
                        this.world15_dark_ticks[player.index] = 0
                        world15_spawn_dark_biters(player, spawn_count)
                    end
                end
            elseif this.world15_dark_ticks then
                this.world15_dark_ticks[player.index] = 0
            end
        end
    end
end

--==============================================================================
-- 开采点亮科技（2026-09 两次实测后最终版，三通道全覆盖）：
--   原挂 on_player_mined_entity——该事件被 comfy_panel/score.lua 的**引擎级 filters**
--   全局过滤（首个注册该事件即带 filters：simple-entity/linked-chest/car/wall/.../tree，
--   无 plant/resource；utils/event_core 对后续注册不再重调 script.on_event，且引擎文档明确
--   同一事件后续注册的 filters 会覆盖前次），导致 yumako-tree/jellystem（plant 类型）与
--   calcite（resource 类型）被引擎直接丢弃、事件根本不触发——火星岩石（simple-entity）能点亮
--   即此原因。改走后三通道（全部无引擎 filters，grep 实证）：
--   ① on_pre_player_mined_item：实体通道。官方文档明示「每次采矿动作完成都会调用，即使
--      实体最终未被移除」→ 资源矿逐次触发、植物收获（采矿机制，wiki 实证）触发。
--   ② on_player_mined_item：道具通道（item_stack）。全项目无任何注册 → 引擎无过滤；
--      玩家手动开采获得 yumako/jellynut/calcite 道具即点亮（植物收获、资源逐铲均可靠）。
--   ③ on_entity_died：实体死亡/枯竭通道。全项目无 filters（实测死亡事件可达）；
--      方解石挖到枯竭、植物被摧毁等场景兜底。
--   三通道共享 world15_light_mine_techs（tech.researched 幂等守卫），MINE_TECH_LIT
--   自动扫描 + MINE_TECH_LIT_EXTRA 显式兜底不变。
--==============================================================================

-- 道具名 → 科技（与 mine-entity 触发实体对应；科技名已按运行时原型实测核对）
local MINE_ITEM_TECH = {
    ['yumako'] = 'yumako',
    ['jellynut'] = 'jellynut',
    ['calcite'] = 'calcite-processing',
}

-- 点亮一组科技（幂等：已研究跳过；可打印提示）
local function world15_light_mine_techs(techs, disp_name, lplayer)
    if not techs then return end
    if lplayer and (not lplayer.valid or lplayer.force.name ~= 'player') then
        lplayer = nil
    end
    for _, tname in ipairs(techs) do
        local tech = game.forces.player.technologies[tname]
        if tech and tech.valid and not tech.researched then
            tech.enabled = true
            tech.researched = true
            if lplayer then
                lplayer.print({'amap.world15_mine_tech_lit', disp_name, tech.localised_name},
                    {r = 0.4, g = 1, b = 0.4})
            end
        end
    end
end

-- ① 实体通道：采矿动作完成（实体仍在场）
local function world15_on_pre_mined_item(event)
    local this = WPT.get()
    if (this and this.world_number or 0) ~= 15 then return end
    local entity = event.entity
    if not entity or not entity.valid then return end
    world15_light_mine_techs(
        MINE_TECH_LIT and MINE_TECH_LIT[entity.name],
        entity.localised_name,
        game.players[event.player_index]
    )
end

-- ② 道具通道：玩家采矿获得对应道具（item_stack 为 ItemWithQualityCount 普通表）
local function world15_on_player_mined_item(event)
    local this = WPT.get()
    if (this and this.world_number or 0) ~= 15 then return end
    local stack = event.item_stack
    if not stack or type(stack) ~= 'table' or not stack.name then return end
    local tname = MINE_ITEM_TECH[stack.name]
    if not tname then return end
    local item_proto = prototypes.item[stack.name]
    world15_light_mine_techs(
        {tname},
        item_proto and item_proto.localised_name or stack.name,
        game.players[event.player_index]
    )
end

-- ③ 死亡/枯竭通道：玉马果树/果冻茎株/方解石实体被摧毁或资源挖尽
local function world15_on_entity_died_mine_tech(event)
    local this = WPT.get()
    if (this and this.world_number or 0) ~= 15 then return end
    local entity = event.entity
    if not entity or not entity.valid then return end
    if entity.name ~= 'yumako-tree' and entity.name ~= 'jellystem' and entity.name ~= 'calcite' then
        return
    end
    world15_light_mine_techs(MINE_TECH_LIT and MINE_TECH_LIT[entity.name], entity.localised_name, nil)
end

--==============================================================================
-- 挖石头出矿接管（2026-10 用户要求：出矿与采矿产能科技、在线玩家人数脱钩）
--   共享 rocks_yield_ore.lua 的产能乘算无条件执行，故世界15 用 disable_rock_ore=true
--   让共享 handler 早退，由本函数自实现挖石头/树产出：数量公式、奖池、树木出木、
--   粒子、拾取提示、满包惩罚、destroy 与共享逐条一致，仅不乘
--   mining_drill_productivity_bonus、不按在线人数加成。
--   事件顺序：tianfu(钢箱)/mining(木箱+金币) handler 注册在本框架分发器之前，
--   此处 destroy 不影响它们；数量参数复用共享 on_init 初始化的
--   storage.rocks_yield_ore_base_amount / _distance_modifier / _maximum_amount。
-- 挖石头概率生成 1×1 储量 10M 单矿（替代带状矿，1/768 → 1/99 → 1/74）
-- 共享配置按世界字段消费（vein_chance），切世界无需恢复
--==============================================================================

-- 岩石/树挖出产物系数（照搬共享 rocks_yield_ore.rock_yield，本图除石头带/出生圈树外无其他可挖实体）
local W15_ROCK_YIELD = {
    ['big-rock'] = 1,
    ['huge-rock'] = 2,
    ['big-sand-rock'] = 1,
    ['tree-01'] = 0.3,
    ['tree-02'] = 0.3,
    ['tree-02-red'] = 0.3,
    ['tree-03'] = 0.3,
    ['tree-04'] = 0.3,
    ['tree-05'] = 0.3,
    ['tree-06'] = 0.3,
    ['tree-06-brown'] = 0.3,
    ['tree-07'] = 0.3,
    ['tree-08'] = 0.3,
    ['tree-08-brown'] = 0.3,
    ['tree-08-red'] = 0.3,
    ['tree-09'] = 0.3,
    ['tree-09-brown'] = 0.3,
    ['tree-09-red'] = 0.3,
}
-- 纯岩石（不出木头的名单，同共享 no_tree）
local W15_ROCK_NO_WOOD = { ['big-rock'] = 1, ['huge-rock'] = 1, ['big-sand-rock'] = 1 }
-- 矿物 → 粒子（同共享 particles 表；钨/废料无专属粒子回退铁粒）
local W15_ORE_PARTICLES = {
    ['iron-ore'] = 'iron-ore-particle',
    ['copper-ore'] = 'copper-ore-particle',
    ['uranium-ore'] = 'coal-particle',
    ['coal'] = 'coal-particle',
    ['stone'] = 'stone-particle',
}

local function w15_create_particles(surface, name, position, amount, cause_position)
    local direction_mod = (-100 + math.random(0, 200)) * 0.0004
    local direction_mod_2 = (-100 + math.random(0, 200)) * 0.0004
    if cause_position then
        direction_mod = (cause_position.x - position.x) * 0.025
        direction_mod_2 = (cause_position.y - position.y) * 0.025
    end
    for i = 1, amount, 1 do
        local m = math.random(4, 10)
        local m2 = m * 0.005
        surface.create_particle({
            name = name,
            position = position,
            frame_speed = 1,
            vertical_speed = 0.130,
            height = 0,
            movement = {
                (m2 - (math.random(0, m) * 0.01)) + direction_mod,
                (m2 - (math.random(0, m) * 0.01)) + direction_mod_2,
            },
        })
    end
end

local function w15_rock_yield_amount(entity)
    local distance_to_center = math.floor(math.sqrt(entity.position.x ^ 2 + entity.position.y ^ 2))
    local amount = storage.rocks_yield_ore_base_amount + (distance_to_center * storage.rocks_yield_ore_distance_modifier)
    if amount > storage.rocks_yield_ore_maximum_amount then amount = storage.rocks_yield_ore_maximum_amount end
    local m = (70 + math.random(0, 60)) * 0.01
    amount = math.floor(amount * W15_ROCK_YIELD[entity.name] * m)
    if amount < 1 then amount = 1 end
    return amount
end

-- 与共享 rocks_yield_ore.on_player_mined_entity 等价，但不乘采矿产能、不按在线人数加成
local function w15_mine_rock_yield(player, entity, event)
    event.buffer.clear()
    local ore = WORLD15_RAFFLE[math.random(1, #WORLD15_RAFFLE)]
    local count = w15_rock_yield_amount(entity)

    storage.rocks_yield_ore['ores_mined'] = storage.rocks_yield_ore['ores_mined'] + count
    storage.rocks_yield_ore['rocks_broken'] = storage.rocks_yield_ore['rocks_broken'] + 1

    local position = { x = entity.position.x, y = entity.position.y }
    local ore_amount = math.floor(count * 0.85) + 1
    player.create_local_flying_text({ text = '+' .. ore_amount .. ' [img=item/' .. ore .. ']', position = position, color = { r = 200/255, g = 160/255, b = 30/255 } })
    if W15_ROCK_NO_WOOD[entity.name] ~= 1 then
        player.insert({ name = 'wood', count = 4 })
        player.create_local_flying_text({ text = '+' .. 4 .. ' [img=item/wood]', position = { x = position.x + 0.4, y = position.y + 0.4 }, color = { r = 200/255, g = 160/255, b = 30/255 } })
    end
    local particle_name = W15_ORE_PARTICLES[ore] or 'iron-ore-particle'
    w15_create_particles(player.physical_surface, particle_name, position, 64, { x = player.physical_position.x, y = player.physical_position.y })
    entity.destroy()

    local k = player.insert({ name = ore, count = ore_amount })
    ore_amount = ore_amount - k
    if ore_amount > 0 then
        player.character.health = player.character.health - player.character.health * 0.2 - 100
        player.print({ 'amap.bag_isfull' }, { r = 200, g = 0, b = 30 })
    end
end

local function world15_on_player_mined_entity(event)
    local this = WPT.get()
    if (this and this.world_number or 0) ~= 15 then return end
    local entity = event.entity
    if not entity or not entity.valid then return end
    local player = game.players[event.player_index]
    if not player or not player.valid or player.force.name ~= 'player' then return end
    if player.physical_surface ~= game.surfaces['nauvis'] then return end

    -- 1) 挖石头/树出矿（接管共享；destroy 前先行捕获类型与位置，供矿脉判定用）
    local entity_type = entity.type
    local pos = { x = entity.position.x, y = entity.position.y }
    local surface = entity.surface
    if W15_ROCK_YIELD[entity.name] then
        w15_mine_rock_yield(player, entity, event)
    end

    -- 2) 概率 1/74 生成 1×1 10M 单矿（用户 2026-09 确认：原 1/99 基础上增加 1/3 = 4/297 ≈ 1/74.25，取整 74）
    if entity_type ~= 'simple-entity' then return end
    if math.random(1, 74) ~= 1 then return end

    local raffle = storage.rocks_yield_ore_veins and storage.rocks_yield_ore_veins.raffle
    local ore = raffle and raffle[math.random(1, #raffle)] or 'iron-ore'
    if ore == 'mixed' then
        local mixed = storage.rocks_yield_ore_veins.mixed_ores
        ore = mixed and mixed[math.random(1, #mixed)] or 'iron-ore'
    end
    if not prototypes.entity[ore] then ore = 'iron-ore' end
    if surface.can_place_entity({name = ore, position = pos, amount = 10000000}) then
        surface.create_entity({name = ore, position = pos, amount = 10000000})
    end
end

--==============================================================================
-- 建筑机器人禁止开采石头（红图石头无效）
--==============================================================================

local function on_marked_for_deconstruction(event)
    local this = WPT.get()
    if (this and this.world_number or 0) ~= 15 then return end
    local entity = event.entity
    if not entity or not entity.valid then return end
    if entity.type ~= 'simple-entity' then return end
    if entity.surface ~= game.surfaces['nauvis'] then return end
    entity.cancel_deconstruction(game.forces.player, game.players[event.player_index])
    local player = game.players[event.player_index]
    if player and player.valid then
        player.print({'amap.world15_robot_mine_block'}, {r = 1, g = 0.6, b = 0.2})
    end
end

--==============================================================================
-- 波次：间隔 ×1.5（在 diff.set_diff 之后乘，不累乘）
--==============================================================================

local function world15_apply_wave_interval()
    local this = WPT.get()
    if (this and this.world_number or 0) ~= 15 then return end
    local wd = WD.get_table()
    wd.wave_interval = math.floor(wd.wave_interval * 1.5 + 0.5)
end

-- 波次威胁闸（2026 用户）：本图不自动出波虫（wave_attack_settings.every 极大），
-- 但共享 set_next_wave 每波无条件给 threat 入账 → 威胁只涨不花。
-- 解法：diff.set_diff 每 60 tick 重算 threat_gain_multiplier，故紧随其后每 60 tick 归零，
-- 使每波入账 = 波次 × 0 × … = 0。只改本文件数据字段，不动共享代码。
local function world15_zero_wave_threat_gain()
    local this = WPT.get()
    if (this and this.world_number or 0) ~= 15 then return end
    local wd = WD.get_table()
    wd.threat_gain_multiplier = 0
    if wd.threat and wd.threat < 0 then
        wd.threat = 0
    end
end

-- 堡垒位置校验（用户 2026-09 要求：堡垒生成无视黑暗地块——只排除深水，黑暗不再拦截）。
-- 用噪声分类判断（不依赖区块是否已生成，未生成区块也能确定性判定）。
-- 2026-10 起：堡垒按山谷同款「每次 1 座」由共享 default 模式随机搜索生成（fortress_count=1，
-- 无本模块包装），共享搜索自带玩家建筑/既有 roboport 避让；本函数只补世界15 的地形约束
-- （深水排除）与 roboport 兜底（距现存敌方指令塔 < 52 格拒绝）。
local function world15_fortress_position_valid(position)
    local this = WPT.get()
    local surface = this.active_surface_index and game.surfaces[this.active_surface_index]
    if not surface or not surface.valid then return true end
    local class = tile_class(position, surface.map_gen_settings.seed)
    if class == 'lake_water' then
        return false
    end
    -- 兜底：距任一现存敌方指令塔(roboport) < 52 格也拒绝（外壁 ±24×2=48，52 留约 4 格缝）
    local nearby = surface.find_entities_filtered({
        area = {{position.x - 51, position.y - 51}, {position.x + 51, position.y + 51}},
        name = 'roboport', force = 'enemy', limit = 1,
    })
    if #nearby > 0 then
        return false
    end
    return true
end

-- 堡垒生成（2026-10 用户最终拍板）：与山谷(世界1)同款——共享 default 模式每事件随机搜索
-- 生成 1 座（fortress_count=1），不做任何本模块包装/并列。落点避让由共享 is_sh_conflict
-- （玩家建筑 110 格、既有 roboport 48 格）+ 本模块 fortress_position_valid（深水 + roboport
-- 52 格兜底）双重保证。核弹阈值 ≥4 见 world15_fortress_monitor。

-- 堡垒落在黑暗区却「半边没内容」修复（2026-10 用户实测，仅世界15，不改共享代码）：
-- 黑暗地块=out-of-map 虚空瓦片，实体 cannot_place_entity 在其上（离线探针实测
-- can_place_entity(stone-wall,out-of-map)=false）。堡垒自带 create_terrain_tasks 只把
-- 中心 ±22 格铺成 sand-1，但内墙 ±18、外墙 ±23~24、地雷撒到 ±27，且远点未生成区块时
-- out-of-map 铺设还会与区块生成竞态 → 越过铺设范围的黑暗部分瓦片仍是 out-of-map，
-- 墙/炮塔建不出 → 用户所见「落在黑暗区的部分啥都没生成」。
-- 修复：共享每事件仍随机选点（fortress_count=1，不改位置，规避此前并列叠堡雷区）；
-- 本包装仅在该点交共享建造【之前】，强制生成落点周边区块、并把整个占地区（半径
-- FORTRESS_PAVE_RADIUS 覆盖外墙+地雷）内的 out-of-map 铺成 sand-1 实地，使共享的清理/
-- 铺地/建墙/建炮塔全部落在可行走地面上、黑暗区也能建全。只改 out-of-map→sand，不碰水/油。
local FORTRESS_PAVE_RADIUS = 30   -- 覆盖最外地雷(±27)与外墙(±24)，留余量
local art_baolei_orig = enemy_arty.baolei

local function world15_pave_fortress_ground(position, surface)
    surface.request_to_generate_chunks(position, 2)
    surface.force_generate_chunk_requests()
    local cx = math.floor(position.x)
    local cy = math.floor(position.y)
    local tiles = {}
    for tx = cx - FORTRESS_PAVE_RADIUS, cx + FORTRESS_PAVE_RADIUS, 1 do
        for ty = cy - FORTRESS_PAVE_RADIUS, cy + FORTRESS_PAVE_RADIUS, 1 do
            if surface.get_tile(tx, ty).name == 'out-of-map' then
                tiles[#tiles + 1] = {name = 'sand-1', position = {x = tx, y = ty}}
            end
        end
    end
    if #tiles > 0 then
        surface.set_tiles(tiles)
    end
end

enemy_arty.baolei = function(position, wave_number, surface, cleanup_terrain, skip_count)
    local this = WPT.get()
    if (this and this.world_number or 0) == 15 and position
        and surface and surface.valid then
        world15_pave_fortress_ground(position, surface)
    end
    return art_baolei_orig(position, wave_number, surface, cleanup_terrain, skip_count)
end

--==============================================================================
-- 堡垒：≥4 座时创建敌方核弹发射井（每 3 分钟发射）（2026-10 用户：9 → 4）
--==============================================================================

local F_NUKE_THRESHOLD = 4
local F_NUKE_INTERVAL_TICKS = 60 * 60 * 3

local fire_nuke_token
fire_nuke_token = Token.register(function(silo)
    if not silo or not silo.valid then return end
    local target = WD.get_table().target
    if not target or not target.valid then return end
    silo.surface.create_entity({
        name = 'atomic-rocket',
        position = {x = target.position.x, y = target.position.y - 100},
        force = game.forces.enemy,
        source = {x = target.position.x, y = target.position.y - 100},
        target = target,
        speed = 1,
    })
    game.print({'amap.enemy_atomic_rocket', target.position.x, target.position.y, silo.surface.name})
    game.print('虫子已经发射核弹！', {255, 0, 0})
end)

local function world15_fortress_monitor()
    local this = WPT.get()
    if (this and this.world_number or 0) ~= 15 then return end
    local surface = this.active_surface_index and game.surfaces[this.active_surface_index]
    if not surface or not surface.valid then return end

    if this.world15_nuke_silo and not this.world15_nuke_silo.valid then
        this.world15_nuke_silo = nil
        if this.world15_silo_tag and this.world15_silo_tag.valid then
            this.world15_silo_tag.destroy()
        end
        this.world15_silo_tag = nil
    end

    local count = enemy_arty.recount_baolei()

    if count >= F_NUKE_THRESHOLD and not this.world15_nuke_silo then
        local positions = enemy_arty.get_valid_fortress_positions()
        if #positions > 0 then
            local anchor = positions[math.random(1, #positions)]
            local pos = surface.find_non_colliding_position('rocket-silo', anchor, 8, 1)
                or surface.find_non_colliding_position('rocket-silo', anchor, 14, 1)
            if pos then
                local silo = surface.create_entity({
                    name = 'rocket-silo',
                    position = pos,
                    force = game.forces.enemy,
                    create_build_effect_smoke = false,
                })
                if silo and silo.valid then
                    silo.destructible = false
                    this.world15_nuke_silo = silo
                    this.world15_silo_tag = game.forces.player.add_chart_tag(surface, {
                        position = pos,
                        icon = {type = 'entity', name = 'rocket-silo'},
                        text = '敌方核弹发射井',
                    })
                    this.world15_nuke_next_fire = game.tick + F_NUKE_INTERVAL_TICKS
                    game.print({'amap.enemy_rocket_silo', pos.x, pos.y, surface.name}, {255, 0, 0})
                    game.print('注意：你必须摧毁所有堡垒，才能对核弹发射井造成伤害！', {255, 0, 0})
                end
            end
        end
    end

    local silo = this.world15_nuke_silo
    if not silo or not silo.valid then return end

    if count <= 0 and silo.destructible == false then
        silo.destructible = true
        game.print('敌方堡垒已被摧毁！核弹发射井失去保护！', {255, 255, 0})
    end

    if game.tick >= (this.world15_nuke_next_fire or math.huge) then
        this.world15_nuke_next_fire = game.tick + F_NUKE_INTERVAL_TICKS
        local target = WD.get_table().target
        if target and target.valid then
            game.print('警告：敌方核弹发射井将在3分钟后发射核弹！', {255, 0, 0})
            Task.set_timeout_in_ticks(F_NUKE_INTERVAL_TICKS, fire_nuke_token, silo)
        else
            this.world15_nuke_next_fire = game.tick + 60 * 60
        end
    end
end

--==============================================================================
-- 天赋（同世界19/21）：史诗好运连连 / 科技瓶 → 天赋 / 上限 60
--==============================================================================

local function count_player_talents(player)
    local main_table = WPT.get()
    local skills = main_table.skill and main_table.skill[player.name]
    if not skills then return 0 end
    local n = 0
    for _ in pairs(skills) do
        n = n + 1
    end
    return n
end

local function world15_grant_hyll(player)
    if not player or not player.valid or player.force.name ~= 'player' then return end
    local main_table = WPT.get()
    if not main_table.skill[player.name] then
        main_table.skill[player.name] = {}
    end
    if main_table.skill[player.name].hyll then return end
    main_table.skill[player.name].hyll = EPIC_HYLL_Q
    if not main_table.tianfu_enabled[player.index] then
        main_table.tianfu_enabled[player.index] = {}
    end
    main_table.tianfu_enabled[player.index].hyll = true
    local tpt = tianfu_table.get()
    if not tpt.skill_owners then tpt.skill_owners = {} end
    if not tpt.skill_owners.hyll then tpt.skill_owners.hyll = {} end
    tpt.skill_owners.hyll[player.index] = true
end

local function world15_enqueue_talent(player_index, count)
    local this = WPT.get()
    if not this.world15_talent_queue then
        this.world15_talent_queue = {}
    end
    local e = this.world15_talent_queue[player_index]
    if not e then
        e = {remaining = 0, total = 0}
        this.world15_talent_queue[player_index] = e
    end
    e.remaining = e.remaining + count
    e.total = e.total + count
end

local function world15_process_talent_queue()
    local this = WPT.get()
    if (this and this.world_number or 0) ~= 15 then return end
    local queue = this.world15_talent_queue
    if not queue then return end
    for pidx, e in pairs(queue) do
        local player = game.players[pidx]
        if not player or not player.valid or player.force.name ~= 'player' then
            queue[pidx] = nil
        elseif count_player_talents(player) >= TALENT_CAP then
            queue[pidx] = nil
            player.print({'amap.world19_talent_cap'}, {r = 1, g = 0.4, b = 0.4})
        elseif not player.gui.screen['选择你的天赋'] then
            tianfu.get_new_tianfu(player, 'mid')
            this.tianfu_count[player.index] = (this.tianfu_count[player.index] or 0) - 1
            e.remaining = e.remaining - 1
            if e.remaining <= 0 then
                player.print({'amap.world19_talent_grant', e.total}, {r = 0.4, g = 1, b = 0.4})
                queue[pidx] = nil
            end
        end
    end
end

local function world15_grant_science_talent(pack, count)
    local this = WPT.get()
    if not this.world15_science_granted then
        this.world15_science_granted = {}
    end
    local pack_tbl = this.world15_science_granted[pack]
    if type(pack_tbl) ~= 'table' then
        pack_tbl = {}
        this.world15_science_granted[pack] = pack_tbl
    end
    for _, player in pairs(game.connected_players) do
        if player and player.valid and player.force.name == 'player' then
            if not pack_tbl[player.name] then
                pack_tbl[player.name] = true
                world15_enqueue_talent(player.index, count)
            end
        end
    end
end

-- 黄瓶解锁新地星气压限制（用户 2026-09 修正：不创建任何星球地表、不点亮 planet-discovery
-- 科技、不解除其他星球/太空限制——其他星球遵循原版；只解除「新地星」= 本图主地表 nauvis
-- 的气压限制：ignore_surface_conditions=true → 主地图上建什么都不会被限制）。
-- 每局一次（world15_climate_unlocked 守卫）。研究含黄瓶（utility-science-pack）即触发。
local function world15_unlock_climate()
    local this = WPT.get()
    if (this and this.world_number or 0) ~= 15 then return end
    if this.world15_climate_unlocked then return end
    this.world15_climate_unlocked = true
    local surface = this.active_surface_index and game.surfaces[this.active_surface_index]
    if surface and surface.valid then
        surface.ignore_surface_conditions = true
    end
    game.print({'amap.world15_climate_unlocked'}, {r = 0.4, g = 1, b = 0.4})
end

-- 火星资源煤分布 -50%（用户 2026-09；跟随原版研究路径：玩家研究 planet-discovery-vulcanus
-- 时 functions.lua 会创建 vulcanus 地表，本函数在该研究完成后把其煤 autoplace 频率减半；
-- 地表可能晚于事件创建（或已创建），用 pending 标记 + [60] tick 兜底应用一次）。
local function world15_halve_vulcanus_coal()
    local this = WPT.get()
    if (this and this.world_number or 0) ~= 15 then return end
    local surface = game.surfaces['vulcanus']
    if not surface or not surface.valid then
        -- 地表尚未创建（functions.lua 可能后于本事件执行）：留待 [60] tick 兜底
        this.world15_pending_vulcanus_coal = true
        return
    end
    if this.world15_vulcanus_coal_done then return end
    local settings = surface.map_gen_settings
    local ac = settings.autoplace_controls or {}
    local base = ac['coal']
    if base then
        ac['coal'] = {
            frequency = (tonumber(base.frequency) or 1) * 0.5,
            size = base.size,
            richness = base.richness,
        }
    else
        ac['coal'] = {frequency = 0.5, size = 1, richness = 1}
    end
    surface.map_gen_settings = settings
    this.world15_vulcanus_coal_done = true
    this.world15_pending_vulcanus_coal = nil
    log('[world15] 火星（vulcanus）煤分布已减半')
end

local function world15_retry_vulcanus_coal()
    local this = WPT.get()
    if (this and this.world_number or 0) ~= 15 then return end
    if this.world15_pending_vulcanus_coal then
        world15_halve_vulcanus_coal()
    end
end

local function on_research_finished(event)
    local this = WPT.get()
    if (this and this.world_number or 0) ~= 15 then return end
    local tech = event.research
    if not tech or not tech.valid then return end
    if tech.force.index ~= game.forces.player.index then return end
    if SCRIPT_RESEARCH_BLACKLIST[tech.name] then return end
    -- 火星（vulcanus）研究完成：functions.lua 同事件创建地表（先于/后于本 handler 均可，
    -- 由 pending + [60] tick 兜底），随后应用煤 -50%
    if tech.name == 'planet-discovery-vulcanus' then
        world15_halve_vulcanus_coal()
    end
    local proto = tech.prototype
    local ingredients = proto and proto.research_unit_ingredients
    if not ingredients then return end
    for _, ing in ipairs(ingredients) do
        local pack = ing.name
        local count = SCIENCE_PACK_TALENTS[pack]
        if count then
            world15_grant_science_talent(pack, count)
        end
        -- 点亮黄瓶（utility-science-pack）→ 解除新地星（本图主地表）气压限制，每局一次
        if pack == 'utility-science-pack' then
            world15_unlock_climate()
        end
    end
end

local function world15_grant_missing_science_talents(player)
    if not player or not player.valid or player.force.name ~= 'player' then return end
    local this = WPT.get()
    local granted = this.world15_science_granted
    if not granted then return end
    for pack, pack_tbl in pairs(granted) do
        if type(pack_tbl) == 'table' and not pack_tbl[player.name] then
            local count = SCIENCE_PACK_TALENTS[pack]
            if count then
                pack_tbl[player.name] = true
                world15_enqueue_talent(player.index, count)
            end
        end
    end
end

local function world15_remove_excess_talent(player)
    local main_table = WPT.get()
    local skills = main_table.skill and main_table.skill[player.name]
    if not skills then return end
    local victim = nil
    for k in pairs(skills) do
        victim = k
        break
    end
    if not victim then return end
    skills[victim] = nil
    if main_table.tianfu_enabled and main_table.tianfu_enabled[player.index] then
        main_table.tianfu_enabled[player.index][victim] = nil
    end
    local tpt = tianfu_table.get()
    if tpt.skill_owners and tpt.skill_owners[victim] then
        tpt.skill_owners[victim][player.index] = nil
    end
    if tpt.player_time_skills and tpt.player_time_skills[player.name] then
        tpt.player_time_skills[player.name][victim] = nil
    end
    player.print({'amap.world19_talent_cap'}, {r = 1, g = 0.4, b = 0.4})
end

local function world15_enforce_talent_cap()
    local this = WPT.get()
    if (this and this.world_number or 0) ~= 15 then return end
    for _, player in pairs(game.connected_players) do
        if player and player.valid and player.force and player.force.name == 'player' then
            local n = count_player_talents(player)
            if n >= TALENT_CAP then
                this.tianfu_count[player.index] = 9999
                this.skill_canchoise[player.name] = 0
                this.tianfu_buy_count[player.index] = 25
                this.xuanze[player.index] = 0
                if this.tianfu_enabled and this.tianfu_enabled[player.index] then
                    this.tianfu_enabled[player.index].djrc = false
                end
                local frame = player.gui.screen['选择你的天赋']
                if frame and frame.valid then
                    frame.destroy()
                end
                if n > TALENT_CAP then
                    world15_remove_excess_talent(player)
                end
            end
        end
    end
end

-- 全图永远黑夜 + 完全漆黑。
-- Space Age 关键：决定「黑不黑」的是 surface.daytime_parameters（dusk/evening/morning/dawn 四个相位边界）。
-- 本地 2.1.17 无头 + RCON 实测结论：
--   1) 引擎默认 dp = 0.25/0.45/0.55/0.75（夜窗只占周期中间 10%），夜窗外亮度回升 → 旧「冻结 0.5」
--      一旦 freeze 被冲掉就不再全黑；实测「写 always_day = false 会把已设的 freeze_daytime 冲掉」。
--   2) 因此把夜窗铺满整个周期（dusk=0、dawn=1，evening/morning 取 0.001/0.999 防边界等值），
--      无论时间如何流动，引擎任何时刻都按 min_brightness 渲染；min_brightness = 0 → 全黑。
--   3) freeze_daytime + daytime = 0.5 仅作双保险，且 always_day 必须先于 freeze 写。
local function world15_enforce_night()
    local this = WPT.get()
    if (this and this.world_number or 0) ~= 15 then return end
    local surface = this.active_surface_index and game.surfaces[this.active_surface_index]
    if not surface or not surface.valid then return end
    -- 首次铺夜前保存地表原始光照（供离开世界15后还原——地表级光照属性跨图残留是
    -- 「下张图全黑」的根因，见 world15_cleanup_surface_light）。
    if not this.world15_night_applied then
        this.world15_saved_daytime = table.deepcopy(surface.daytime_parameters)
        this.world15_saved_min_brightness = surface.min_brightness
        this.world15_saved_brightness_weights = table.deepcopy(surface.brightness_visual_weights)
        this.world15_saved_solar = surface.solar_power_multiplier
        this.world15_night_applied = true
    end
    surface.daytime_parameters = { dusk = 0, evening = 0.001, morning = 0.999, dawn = 1 }
    surface.min_brightness = 0.16
    -- ★ 纯黑核心开关（本地无尽跃迁存档 scripts/surface.lua 实测机制）：
    --   引擎公式 LUT ×= (1-w) + brightness×w，本场景 nauvis 的 brightness_visual_weights
    --   默认为 0（无头 RCON 实测读回 r=g=b=0）→ 昼夜亮度对画面完全无效，min_brightness
    --   设成什么都不会黑。权重设为 1 后画面完全跟随昼夜亮度。
    -- 黑度档位（用户调参历程）：0=全黑看不见 → 0.1 90%黑仍无轮廓 → 0.16：约84%黑，
    --   能隐约看到地形与实体轮廓、灯光外不至于完全盲飞。
    surface.brightness_visual_weights = { r = 1, g = 1, b = 1 }
    surface.always_day = false
    -- 时间保持流动（不冻结）：冻结会让引擎按"白天"处理光源（汽车大灯不自动点亮）；
    -- 夜窗 [0.001,0.999] 铺满整个周期（两端各留 0.001 防边界等值被引擎拒绝）→
    -- 无论时间走到哪个相位几乎都是黑夜，仅极小相位处于晨昏渐变。
    surface.freeze_daytime = false
    surface.daytime = 0.5
    surface.solar_power_multiplier = 0
end

-- 离开世界15后一次性还原地表光照（防止夜间属性污染下一张图）：
-- world15_enforce_night 设置的地表级属性（daytime_parameters / brightness_visual_weights /
-- min_brightness / solar_power_multiplier）在 soft_reset_map 换图时不会被 surface.clear()
-- 重置、共享代码也无还原逻辑，会残留到下一张图（全黑 + 太阳能失效）。
-- 框架无 on_world_exit 钩子、又不得改共享代码，故在本世界模块内自注册一个轻量 [60]tick：
-- 仅在「已离开世界15 且 本模块曾铺过夜」时执行一次还原，只撤销世界15自己的污染。
-- 世界15内该函数恒 no-op（world_number==15 直接 return），不影响本图全黑视野。
local function world15_cleanup_surface_light()
    local this = WPT.get()
    if not this or not this.world15_night_applied then return end
    if (this and this.world_number or 0) == 15 then return end
    local surface = this.active_surface_index and game.surfaces[this.active_surface_index]
    if not surface or not surface.valid then return end
    surface.daytime_parameters = this.world15_saved_daytime or { dusk = 0.25, evening = 0.45, morning = 0.55, dawn = 0.75 }
    surface.min_brightness = this.world15_saved_min_brightness or 0.2
    surface.brightness_visual_weights = this.world15_saved_brightness_weights or { r = 0, g = 0, b = 0 }
    surface.solar_power_multiplier = this.world15_saved_solar or 1
    this.world15_night_applied = nil
    log('[world15] 已离开世界15，地表光照还原为进入前状态（避免污染下一张图）')
end
Event.on_nth_tick(60, world15_cleanup_surface_light)

-- 离开世界15后清理世界15专属的「跨世界持久视觉」（2026-10 用户实测：通关回收箱两队红字
-- 溢出到别的图）。根因：rendering.draw_text 对象与 player.gui 标签都不随 soft_reset 的
-- surface.clear()/remove_all_chart_tags 清除，而世界15 对它们的销毁只写在 on_world_start
-- （进15才触发，框架无 on_world_exit）→ 离开15后残留继续画在复用的 nauvis 地表 / 挂在玩家
-- GUI 上。照 world15_cleanup_surface_light 模式自注册 [60]tick：仅「world_number~=15 且
-- world15_visuals_dirty」时一次性销毁三类残留（clear_tags 组名红字 / recycle_tag 回收箱红字 /
-- clear_progress 左侧通关进度红字 GUI），清完置脏标记 false，不在别的图空转。全程世界15文件内。
local function world15_cleanup_visuals()
    local this = WPT.get()
    if not this or not this.world15_visuals_dirty then return end
    if (this.world_number or 0) == 15 then return end
    if this.world15_clear_tags then
        for _, t in ipairs(this.world15_clear_tags) do
            if t and t.valid then t.destroy() end
        end
        this.world15_clear_tags = nil
    end
    if this.world15_recycle_tag and this.world15_recycle_tag.valid then
        this.world15_recycle_tag.destroy()
    end
    this.world15_recycle_tag = nil
    for _, player in pairs(game.connected_players) do
        if player and player.valid then
            local lbl = player.gui.left['world15_clear_progress']
            if lbl and lbl.valid then lbl.destroy() end
        end
    end
    this.world15_visuals_dirty = nil
    log('[world15] 已离开世界15，清理世界15残留视觉（回收箱/通关进度红字）')
end
Event.on_nth_tick(60, world15_cleanup_visuals)

local function world15_finish_reset()
    local this = WPT.get()
    if (this and this.world_number or 0) ~= 15 then return end
    if #game.connected_players == 0 then
        this.world15_science_granted = {}
        this.world15_talent_queue = {}
    end
    -- 科技倍率 ×2（研究成本 ×2；2026-09 用户 ×2→×3→改回×2；main.lua 在 on_world_start 之后又重置为 1，此处每 tick 兜底）
    game.difficulty_settings.technology_price_multiplier = 2
    -- 永远黑夜 + 全员史诗好运连连（幂等）——保证即使 on_world_start 时序异常也能生效
    world15_enforce_night()
    for _, player in pairs(game.connected_players) do
        world15_grant_hyll(player)
    end
end

--==============================================================================
-- 撤销开局自动研发的「高级星岩处理 / 星岩再处理」（main.lua reset_map 末尾对非 14/21
-- 世界强制把这两个科技 researched=true，on_world_start 早于此设置，须在进入世界15 后的
-- 首个 [60] tick 一次性撤销；开局 1 秒内不可能完成这些科技，不会误伤玩家手动研究）。
-- 本图允许的开局科技只有悬崖炸药（科举/脚本强制研究只认 cliff-explosives）。
-- 注：Factorio 2.x 的 LuaTechnology 无 research_progress 属性（会抛
-- "LuaTechnology doesn't contain key research_progress"），只复位 researched。
local function world15_unresearch_tech(name)
    local tech = game.forces.player.technologies[name]
    if tech and tech.valid then
        tech.researched = false
    end
end

local function world15_unresearch_advanced_asteroid()
    local this = WPT.get()
    if (this and this.world_number or 0) ~= 15 then return end
    if not this.world15_pending_unresearch then return end
    this.world15_pending_unresearch = nil
    world15_unresearch_tech('advanced-asteroid-processing')
    world15_unresearch_tech('asteroid-reprocessing')
end

--==============================================================================
-- 箱子开荒（用户 2026-09 定稿）：主地表**任意箱子**（container 类：木箱/铁箱/钢箱等）
-- 被任意武器/虫子打爆（死亡事件即触发，不限死因）时，箱内炸药数 ÷250 取整 = N，
-- N > 0 则转化 N 块 1×1 黑暗地块（out-of-map）为草地：逐块取「距箱子 6 格（平距）内最近」
-- 的黑暗地块（平距并列则随机），转化一块后继续找下一块最近；6 格内不足则转多少算多少。
-- 背景（仅查询结论）：原版 2.1 爆炸不改变任何瓦片；填海材料 tile_condition
-- 白名单只含六种水面，无法作用于 out-of-map —— 脚本 set_tiles 是唯一可行通道
-- （黑暗本就是 set_tiles 铺出来的，世界21 扩张机制同源）。
-- 判定走三重保障（2026-09 用户实测第一版未触发后的加固版）：
--   1) on_entity_damaged（致命一击时箱内容物必定完整：掉落物在死亡流程之后才产生）
--   2) on_entity_died + 箱内计数（实体此时仍有效）
--   3) on_entity_died + 尸体半径 4 格内掉落地上的炸药计数（若事件时已先弹出）
-- 两事件按 unit_number 去重（this.world15_reclaimed_crates）；6 格内无黑暗地块或数量不足记日志。
--==============================================================================
local WOODCHEST_EXPLOSIVES_DIV = 50      -- 炸药 ÷50 取整 = 转化块数（2026-09 用户 250 → 50）
local WOODCHEST_RECLAIM_RADIUS = 6

-- 箱内炸药数（优先背包；背包已空则数尸体附近掉落地面的炸药物品）
local function crate_explosive_count(crate, surface)
    local count = 0
    local inv = crate.get_inventory(defines.inventory.chest)
    if inv then
        count = inv.get_item_count('explosives')
    end
    if count >= WOODCHEST_EXPLOSIVES_DIV then
        return count, 'chest'
    end
    local ground = 0
    local p = crate.position
    local drops = surface.find_entities_filtered({
        area = {{p.x - 4, p.y - 4}, {p.x + 4, p.y + 4}},
        type = 'item-on-ground',
    })
    for _, d in pairs(drops) do
        if d and d.valid then
            local st = d.stack
            if st and st.valid_for_read and st.name == 'explosives' then
                ground = ground + st.count
            end
        end
    end
    return math.max(count, ground), (count > 0 and 'chest' or 'ground')
end

-- 取距 (cx,cy) 平距 ≤6 格内最近的一块黑暗地块（平距并列随机）；无则 nil
local function find_nearest_dark_tile(surface, cx, cy)
    local min_d2 = WOODCHEST_RECLAIM_RADIUS * WOODCHEST_RECLAIM_RADIUS
    local best = {}
    for tx = math.floor(cx) - WOODCHEST_RECLAIM_RADIUS, math.floor(cx) + WOODCHEST_RECLAIM_RADIUS, 1 do
        for ty = math.floor(cy) - WOODCHEST_RECLAIM_RADIUS, math.floor(cy) + WOODCHEST_RECLAIM_RADIUS, 1 do
            local dx = (tx + 0.5) - cx
            local dy = (ty + 0.5) - cy
            local d2 = dx * dx + dy * dy
            if d2 <= min_d2 and surface.get_tile(tx, ty).name == 'out-of-map' then
                if d2 < min_d2 then
                    min_d2 = d2
                    best = {}
                end
                best[#best + 1] = {x = tx, y = ty}
            end
        end
    end
    if #best == 0 then return nil end
    return best[math.random(1, #best)]
end

-- 主判定：crate 须为世界15主地表 container 类箱子；source='damaged'/'died' 仅用于日志。
-- 任意死因（武器/虫子/爆炸等）触发；炸药 ÷250 取整 = 转化块数，逐块找最近黑暗地块。
local function world15_try_woodchest_reclaim(event, source)
    local this = WPT.get()
    if (this and this.world_number or 0) ~= 15 then return end
    local crate = event.entity
    if not crate or not crate.valid or crate.type ~= 'container' then return end
    local surface = this.active_surface_index and game.surfaces[this.active_surface_index]
    if not surface or crate.surface ~= surface then return end
    if not this.world15_reclaimed_crates then this.world15_reclaimed_crates = {} end
    if this.world15_reclaimed_crates[crate.unit_number] then return end

    local count, where = crate_explosive_count(crate, surface)
    local blocks = math.floor(count / WOODCHEST_EXPLOSIVES_DIV)
    if blocks <= 0 then return end
    -- 到这里：箱子（将）死且炸药 ÷250 ≥ 1 —— 无需死因过滤（用户要求任意武器/虫子打爆均触发）
    this.world15_reclaimed_crates[crate.unit_number] = true
    local cx = crate.position.x
    local cy = crate.position.y
    local converted = 0
    local first = nil
    for _ = 1, blocks do
        local pick = find_nearest_dark_tile(surface, cx, cy)
        if not pick then break end
        surface.set_tiles({{name = 'grass-1', position = {x = pick.x, y = pick.y}}})
        converted = converted + 1
        if not first then first = pick end
        log('[world15] 箱子开荒(' .. source .. ')：炸药=' .. count .. '(' .. where .. ') 转化黑暗格 (' .. pick.x .. ',' .. pick.y .. ')')
    end
    if converted == 0 then
        log('[world15] 箱子开荒：' .. WOODCHEST_RECLAIM_RADIUS .. ' 格内未找到黑暗地块，未转化')
        return
    end
    game.print({'amap.world15_dark_reclaim', converted, first.x, first.y}, {r = 0.4, g = 1, b = 0.4})
    if converted < blocks then
        log('[world15] 箱子开荒：' .. WOODCHEST_RECLAIM_RADIUS .. ' 格内黑暗地块不足，实际转化 ' .. converted .. '/' .. blocks)
    end
end

local function world15_woodchest_damaged(event)
    -- 高频事件（所有实体受伤都走这里）：先做两个最廉价的过滤再进主判定
    local this = WPT.get()
    if (this and this.world_number or 0) ~= 15 then return end
    local entity = event.entity
    if not entity or entity.type ~= 'container' then return end
    if not (event.final_health and event.final_health <= 0) then return end
    world15_try_woodchest_reclaim(event, 'damaged')
end

local function world15_woodchest_died(event)
    world15_try_woodchest_reclaim(event, 'died')
end

-- 白嫖组装机/电炉产量翻倍（用户 2026-09）：共享 produce() 每个 [60] tick 给
-- 每个工厂 progress += 60×(1+(tier-1)/24)（=每秒 1 基础秒进度）。本图在同一个
-- [60] tick 再补一份同额 progress → 每秒 2 基础秒进度 = 产量 ×2。
-- 覆盖两类：productionsphere.assemblers（野外白嫖机）与 train_assemblers（出生组装机）。
-- 纯世界15 代码，不碰共享 production.lua。
local function world15_double_production()
    local this = WPT.get()
    if (this and this.world_number or 0) ~= 15 then return end
    local ps = this.productionsphere
    if not ps then return end
    local function add_bonus(factory)
        if factory and factory.active and factory.entity and factory.entity.valid then
            local tier = factory.tier or 0
            factory.progress = factory.progress + 60 * (1 + (tier - 1) / 24)
        end
    end
    for _, factory in pairs(ps.assemblers or {}) do
        add_bonus(factory)
    end
    for _, factory in pairs(ps.train_assemblers or {}) do
        add_bonus(factory)
    end
end

--==============================================================================
-- 初始补给 + 禁照明灯配方/科技（2026-09 用户要求，仅世界15生效）
--   · 进入世界15：每人送 10×small-lamp + 10×small-electric-pole（后加入补发，每次进入重置）
--   · 出生市场灯价 10 金币（world15_shop_refresh 内）
--   · 禁用配方 small-lamp + 科技 lamp（无法选择配方/制造/研究；实测科技名 lamp 解锁配方 small-lamp）
--     main.lua reset_map 的 force.reset() 会重置为默认启用，故每 [60]tick 兜底 + on_world_start 即禁。
--==============================================================================

local function world15_disable_lamp()
    local this = WPT.get()
    if (this and this.world_number or 0) ~= 15 then return end
    local force = game.forces.player
    local tech = force.technologies['lamp']
    if tech and tech.valid and tech.enabled then
        tech.enabled = false
    end
    if tech and tech.valid and tech.researched then
        tech.researched = false
    end
    local recipe = force.recipes['small-lamp']
    if recipe and recipe.enabled then
        recipe.enabled = false
    end
end

local function world15_grant_start_gift(player)
    if not player or not player.valid or player.force.name ~= 'player' then return end
    local this = WPT.get()
    if not this.world15_gift_granted then this.world15_gift_granted = {} end
    if this.world15_gift_granted[player.name] then return end
    this.world15_gift_granted[player.name] = true
    player.insert({name = 'small-lamp', count = 10})
    player.insert({name = 'small-electric-pole', count = 10})
    player.print({'amap.world15_start_gift'}, {r = 0.4, g = 1, b = 0.4})
end

-- 汽车内买矿「恢复油田」：改为共享 ic/gui.lua crate_water 的 oil_only 路径（世界字段
-- disable_car_water_generation 门控：只出油田不铺水），不再需要本模块轮询（2026-10 移除）。

-- 禁止史诗木箱（2026-10 用户要求：效果同传说木箱——放置即变为普通）。仅世界15文件内用框架
-- 事件实现（不改共享 magic_wood.lua，符合「改动只对世界15」约束）：玩家/机器人放史诗
-- wooden-chest → 原地降级为普通木箱。world_number==15 门控，其他世界不受影响。
local function world15_downgrade_epic_chest(entity)
    local surface = entity.surface
    local position = entity.position
    local force = entity.force
    entity.destroy()
    surface.create_entity({
        name = 'wooden-chest',
        position = position,
        force = force,
        quality = 'normal',
        fast_replace = true,
    })
end

local function world15_on_built_epic_chest(event)
    local this = WPT.get()
    if (this and this.world_number or 0) ~= 15 then return end
    local entity = event.entity
    if not entity or not entity.valid then return end
    if entity.name ~= 'wooden-chest' then return end
    local q = entity.quality
    if q and q.name == 'epic' then
        world15_downgrade_epic_chest(entity)
    end
end

--==============================================================================
-- 世界进入钩子
--==============================================================================

local function on_world_start(world_number)
    local this = WPT.get()
    if not this then return end

    -- 恢复保卫战特色：启用野外白嫖建筑（随机电力熔炉/1~3级组装机，不可拆不可摧毁、
    -- 随生产球经验升级解锁产物），由 world_main.on_chunk_generated 的 ywjz→rand_building 生成。
    this.enable_wild_factorio = true

    -- 玩家强化：挖掘 +200%、背包 +100
    local force = game.forces.player
    force.manual_mining_speed_modifier = force.manual_mining_speed_modifier + 2
    force.character_inventory_slots_bonus = force.character_inventory_slots_bonus + 100

    -- 全图永远黑夜（先设时刻再冻结；亮度由 world15_enforce_night 每 tick 兜底保证）
    world15_enforce_night()

    -- 全员史诗好运连连（幂等）
    for _, player in pairs(game.connected_players) do
        world15_grant_hyll(player)
    end

    -- 科技瓶天赋本局状态清零
    this.world15_science_granted = {}
    this.world15_talent_queue = {}
    this.world15_session_tick = game.tick

    -- 初始补给每次进入世界15重置（每人 10 灯 + 10 木制电线杆，后加入者由 on_player_joined_game 补发）
    this.world15_gift_granted = {}

    -- 记录进入世界15时的伤害 multiplier（玩家带入的合法加成），
    -- 供 [60]tick 归一化把削减/加成还原到该水平（永久不削减）
    this.world15_dmg_enter = this.damage_multiplier or 1

    -- 撤销开局自动研发的高级星岩处理/星岩再处理（main.lua 在其后执行，须等下个 [60] tick）
    this.world15_pending_unresearch = true

    -- 本局状态复位
    this.world15_spawn_done = nil
    this.world15_lamps_done = nil
    this.world15_dark_ticks = {}
    this.world15_market_spots = {}
    this.world15_lake_spot_cache = {}
    this.world15_lake_vault_cache = {}
    this.world15_oil_keep = {}
    this.world15_climate_unlocked = nil  -- 黄瓶新地星气压解除每局一次（2026-09）
    this.world15_pending_vulcanus_coal = nil  -- 火星煤 -50% 待应用标记（2026-09）
    this.world15_vulcanus_coal_done = nil
    this.world15_reclaimed_crates = {}
    this.world15_recycle = nil
    this.world15_recycle_warned = nil
    this.world15_recycle_first_tick = nil
    if this.world15_recycle_tag and this.world15_recycle_tag.valid then
        this.world15_recycle_tag.destroy()
    end
    this.world15_recycle_tag = nil
    if this.world15_recycle_gain and this.world15_recycle_gain.valid then
        this.world15_recycle_gain.destroy()
    end
    this.world15_recycle_gain = nil
    -- 通关回收箱（新一局重放；旧实体随旧地表销毁）
    this.world15_clear_done = nil
    this.world15_clear_done_win = nil
    this.world15_clear_chests = nil
    this.world15_clear_loaders = nil
    this.world15_clear_swallows = nil
    this.world15_clear_window = nil
    this.world15_clear_chest_total = nil
    this.world15_clear_streak = nil
    if this.world15_clear_tags then
        for _, t in ipairs(this.world15_clear_tags) do
            if t and t.valid then
                t.destroy()
            end
        end
    end
    this.world15_clear_tags = nil
    this.world15_visuals_dirty = nil   -- 残留视觉脏标记随新局复位（新视觉创建时再置真）
    -- 清除左侧通关进度标签（GUI 会跨存档持久化，新局必须移除）
    for _, player in pairs(game.connected_players) do
        if player and player.valid then
            local lbl = player.gui.left['world15_clear_progress']
            if lbl and lbl.valid then
                lbl.destroy()
            end
        end
    end
    this.world15_nuke_silo = nil
    this.world15_nuke_next_fire = nil
    if this.world15_silo_tag and this.world15_silo_tag.valid then
        this.world15_silo_tag.destroy()
    end
    this.world15_silo_tag = nil

    -- 初始补给发放 + 禁照明灯配方/科技（世界15内立即生效，[60]tick 兜底）
    for _, player in pairs(game.connected_players) do
        world15_grant_start_gift(player)
    end
    world15_disable_lamp()
end

-- 世界内玩家加入：补发史诗好运连连 + 科技瓶天赋 + 初始补给
local function on_player_joined_game(event)
    local this = WPT.get()
    if (this and this.world_number or 0) ~= 15 then return end
    local player = game.players[event.player_index]
    if player then
        world15_grant_hyll(player)
        world15_grant_missing_science_talents(player)
        world15_grant_start_gift(player)
    end
end

--==============================================================================
-- 世界15专属修复：幽灵施工队 ylsgd 实体名≠物品名崩溃
-- （共享 tianfu_time_skill.lua:2092 用幽灵实体名 straight-rail/curved-rail-a/b 直接
--  get_item_count → Unknown item name 每 3 秒刷屏崩溃；共享代码不许改，故本文件
--  复刻一份修复版 ylsgd，并在加载期覆盖 tianfu_time_skill.ylsgd：
--  仅世界15生效，其余世界仍走共享原函数。修复点 = 实体名→物品名映射。）
--==============================================================================
local w15_ban_build = {
    ['gun-turret'] = true,
    ['flamethrower-turret'] = true,
    ['tank'] = true,
    ['car'] = true,
}

local function w15_get_total_crafting_time(item_name, depth, q_idx)
    local this = WPT.get()
    depth = depth or 0
    if depth > 10 then return 1 end
    if not this.time_cache then this.time_cache = {} end
    if this.time_cache[item_name] then return this.time_cache[item_name] end
    local recipe = prototypes.recipe[item_name]
    if not recipe then
        this.time_cache[item_name] = 1
        return 1
    end
    local total_time = recipe.energy
    local product_amount = 1
    for _, product in pairs(recipe.products) do
        if product.name == item_name then
            product_amount = product.amount or product.amount_min or 1
            break
        end
    end
    for _, ingredient in pairs(recipe.ingredients) do
        if ingredient.type == "item" then
            local sub_time = w15_get_total_crafting_time(ingredient.name, depth + 1)
            total_time = total_time + (sub_time * ingredient.amount / product_amount)
        end
    end
    this.time_cache[item_name] = total_time
    return total_time
end

local function w15_validate_ghost(ghost, item_name, q_idx)
    if w15_ban_build[item_name] then
        return false
    end
    if ghost.quality and ghost.quality.name ~= "normal" then
        return false
    end
    local item_prototype = prototypes.item[item_name]
    if item_prototype and item_prototype.group and item_prototype.group.name == "other" then
        return false
    end
    local force_recipes = game.forces.player.recipes
    if force_recipes[item_name] and not force_recipes[item_name].enabled then
        return false
    end
    local time_cost = w15_get_total_crafting_time(item_name)
    if time_cost > 6000 then
        return false
    end
    return true, time_cost
end

-- 幽灵实体名 → 对应物品名（straight-rail/curved-rail-a/b → rail 等）
local function w15_ghost_item_name(ghost)
    local gproto = ghost.ghost_prototype
    if gproto and gproto.items_to_place_this then
        local items = gproto.items_to_place_this
        for _, it in pairs(items) do
            if it.name then
                return it.name
            end
        end
    end
    return ghost.ghost_name
end

local function w15_ylsgd(player, q_idx)
    if player.force.name ~= "player" then
        return
    end
    local base_buildings = 6
    local rpg_t = rpgtable.get('rpg_t')
    local attribute_val = rpg_t[player.index].dexterity or 0
    local extra_buildings = math.floor(attribute_val / 200) * 3
    local max_buildings = math.floor((base_buildings + extra_buildings) * ({1, 1.2, 1.4, 1.6, 1.8})[q_idx or 1])
    local count = 0
    local surface = player.physical_surface
    local ghost_count = surface.count_entities_filtered({
        position = player.physical_position,
        name = 'entity-ghost',
        radius = 13,
        force = game.forces.player,
    })
    if ghost_count == 0 then
        return
    end
    local ghosts = surface.find_entities_filtered({
        position = player.physical_position,
        name = 'entity-ghost',
        radius = 13,
        force = game.forces.player,
    })
    for _, ghost in pairs(ghosts) do
        if count >= max_buildings then
            break
        end
        if ghost.valid then
            local ghost_name = ghost.ghost_name
            if not w15_ban_build[ghost_name] then
                local item_name = w15_ghost_item_name(ghost)
                local player_have = player.get_item_count(item_name)
                if player_have > 0 then
                    if w15_validate_ghost(ghost, item_name) then
                        local success, _ = ghost.revive({raise_revive = true})
                        if success then
                            player.remove_item({name = item_name, count = 1})
                            count = count + 1
                        end
                    end
                end
            end
        end
    end
end

-- 覆盖共享 ylsgd：仅世界15走修复版，其余世界走共享原函数
local w15_orig_ylsgd = tianfu_time_skill.ylsgd
tianfu_time_skill.ylsgd = function(player, q_idx)
    local this = WPT.get()
    if (this and this.world_number or 0) == 15 then
        w15_ylsgd(player, q_idx)
    else
        w15_orig_ylsgd(player, q_idx)
    end
end

--==============================================================================
-- 注册到框架
--==============================================================================

World.register(15, {
    --==========================================================================
    -- 元数据
    --==========================================================================
    name_key = 'amap.world_name_15',
    desc_key = 'amap.world_name_info_15',
    selectable = true,

    --==========================================================================
    -- 时间与地形
    --==========================================================================
    -- 首波等待 7200 秒
    time_limit = 7200 * 60,

    -- 资源：仅石油自动生成（2/2/4），其余矿物全 0（挖掘石头产物除外）
    surface_config_name = 'world15',

    map_settings = {
        -- 【2026-09 修正】旧写法 {cliff_elevation_interval=0, cliff_elevation_0=0} 会把整图高程
        -- 清零，杀死 autoplace 石油（高程=海面时陆地判定失败；本文件历史注释「实测 autoplace
        -- 油为 0」即此因，与 surface.lua 共享 prototype 写入叠加后还会污染后续世界）。
        -- 现恢复 nauvis 行星默认 cliff_settings（缺省字段取引擎默认），全图取消悬崖改由
        -- on_chunk_generated 实体级摧毁 cliff 实现（不碰高程，石油正常生成）。
        ['cliff_settings'] = {name = 'cliff', control = 'nauvis_cliff', cliff_smoothing = 0},
        -- 出生区缩小（2026-09 用户「石油还是没有生成」根因之一：油 has_starting_area_placement=false，
        -- 1.4 出生区把油全推在 240+ 格外，玩家在石头带里怎么走都看不到油）。
        -- 0.5 → 油在 ~64~96 格起就能生成，走出出生圈就可见。
        ['starting_area'] = 0.5,
    },

    terrain_generator = terrain_generator,

    --==========================================================================
    -- 战斗规则
    --==========================================================================
    max_flame = nil,
    biter_spawn_rule = nil,
    ammo_damage_modifiers = nil,
    enemy_expansion = nil,

    --==========================================================================
    -- 不自动出波虫（只显示波次）：every 极大 → can_units_spawn 恒 false
    --==========================================================================
    wave_attack_settings = {
        every = 100000000,
    },

    -- 堡垒：500 波出现。与山谷(世界1)同款「每次 1 座」：共享 get_new_arty 每事件随机搜索
    -- 生成 1 座（fortress_count=1，无本模块包装；落点避让 = 共享 is_sh_conflict 玩家建筑
    -- 110 格/roboport 48 格 + 本模块 fortress_position_valid 深水排除/roboport 52 格兜底）。
    -- 存活堡垒 ≥4 座由 world15_fortress_monitor 建核弹发射井（每 3 分钟发射）。
    -- 堡垒生成间隔 ×2（2026-09 用户要求）：interval 20 → 40（get_new_arty 每 60s 计一次，
    -- 实际约 20 分钟 → 40 分钟一座；enemy_arty 内部还有按人数/速建奖励的加减档）。
    --==========================================================================
    arty_settings = {
        interval = 40,
        mode = 'default',
        start_wave = 500,
        fortress_count = 1,
    },
    fortress_position_valid = world15_fortress_position_valid,

    --==========================================================================
    -- 星球与科技
    --==========================================================================
    planet_surfaces = nil,
    unlock_planet_technologies = false,
    planet_resource_boost = false,
    unlocked_technologies = {},
    landfill_allowed = false,

    --==========================================================================
    -- 专属机制
    --==========================================================================
    -- 天赋间隔：40 级 = 1 天赋（2026-10 用户：45 → 40）
    tianfu_jiange = 40,

    -- 禁止地图副本投递史诗木箱（2026-10 用户要求，main.lua 消费）：世界15 不再生成副本入口箱
    disable_epic_chest_delivery = true,

    -- 出生市场追加固定商品（五足虫卵 / 机甲 / 生物室 / 农业塔 / 果冻果 / 玉马果种子）
    rock_shop_extra_items = {
        {name = 'mech-armor', gold = 99000},
        {name = 'pentapod-egg', gold = 20000},
        {name = 'biochamber', gold = 20000},
        {name = 'agricultural-tower', gold = 10000},
        -- 果冻果改售果冻果种子（2026-09 用户要求：种子可种植，果实不能）
        {name = 'jellynut-seed', gold = 1000},
        {name = 'yumako-seed', gold = 1000},
    },

    -- 汽车内买矿禁止生成水（ic/gui.lua 消费）
    disable_car_water_generation = true,

    -- 野外随机市场禁用（市场由本模块在 terrain_generator 按精良市场生成）
    wild_market_disabled = true,

    -- 挖石头出矿接管（2026-10 用户要求：出矿与采矿产能科技、在线人数一律脱钩）：
    -- 共享 rocks_yield_ore.lua 的产能乘算（count*(1+mining_drill_productivity_bonus)）无条件执行、
    -- 无框架字段可关，故置 disable_rock_ore=true 令共享 handler 早退，由本文件
    -- world15_on_player_mined_entity 自实现挖石头产出（公式/奖池/木头/粒子与共享一致，
    -- 仅取消两项加成）。原 rock_ore_player_bonus=0.1 随之删除（共享处不再消费）。
    disable_rock_ore = true,

    -- 挖石头出矿权重池（原 rocks_yield_ore.lua 消费）：2026-10 起本图共享 handler 已由
    -- disable_rock_ore 早退，奖池改由本文件 world15_on_player_mined_entity 直接使用
    -- WORLD15_RAFFLE（铁50/铜34/煤26/石20/铀4/钨2/废料3），本字段不再需要。

    -- 共享矿脉概率（rocks_yield_ore_veins.lua 消费）：本图改为世界模块自生成 1×1 单矿
    vein_chance = 999999999,

    -- 挖石头木质宝箱概率（mining.lua 消费）：1/70（2026-10 用户再指定；
    -- 历史：最初设计 1/20 → 减半 1/40 → 1/90 → 1/70；其他世界维持 1/150）
    wood_chest_chance = 70,

    -- 挖石头宝箱类型（mining.lua 消费）：显式 wooden-chest，与「好运连连钢箱」并存——
    --   挖石头 → 1/70 出木箱（本字段，Loot.add_rare 木箱物资）；
    --   玩家持好运连连 → 另 roll hyll_steel_chest_chance 出钢箱（品质掉落，见下）。
    -- 历史坑：第二轮反馈曾把本字段设为 steel-chest（换皮木箱），用户看到的「只有钢箱没木箱」
    --   即来自那个版本；已改回木箱。改动务必重新创建游戏（旧存档内嵌 __level__ 旧脚本）。
    rock_chest_name = 'wooden-chest',

    -- 好运连连钢箱概率（tianfu_trigger_skill.lua 消费）：1/90（2026-10 用户再指定；
    --   历史：最初设计 1/50 → 砍到 2/3 即 1/75 → 1/120 → 1/90）
    hyll_steel_chest_chance = 90,

    -- 限制世界奖励传说木箱的使用（2026-09 用户要求）：传说木箱放置/机器人放置时
    -- 自动降级为普通木箱（magic_wood.lua 消费，世界19 同款）
    disable_legendary_wood_chest = true,

    -- 世界进入钩子
    on_world_start = on_world_start,

    --==========================================================================
    -- 声明式事件订阅（framework.lua 统一分发）
    --==========================================================================
    events = {
        [defines.events.on_chunk_generated] = on_chunk_generated,
        -- 开采点亮科技三通道（均无引擎 filters；on_player_mined_entity 被 comfy_panel/score.lua
        -- 的引擎级 filters 过滤 plant/resource，故只保留挖石抽奖，见函数注释）
        [defines.events.on_pre_player_mined_item] = world15_on_pre_mined_item,
        [defines.events.on_player_mined_item] = world15_on_player_mined_item,
        [defines.events.on_player_mined_entity] = world15_on_player_mined_entity,
        [defines.events.on_marked_for_deconstruction] = on_marked_for_deconstruction,
        [defines.events.on_research_finished] = on_research_finished,
        [defines.events.on_player_joined_game] = on_player_joined_game,
        -- 夜视仪禁装（事件秒退）：玩家放置 + 通用插入（脚本/搬运入格）双通道
        [defines.events.on_player_placed_equipment] = world15_on_placed_equipment,
        [defines.events.on_equipment_inserted] = world15_on_placed_equipment,
        -- 禁止史诗木箱：玩家/机器人放置史诗 wooden-chest 原地降级为普通（内部 world_number==15 门控）
        [defines.events.on_built_entity] = world15_on_built_epic_chest,
        [defines.events.on_robot_built_entity] = world15_on_built_epic_chest,
        -- 木箱开荒：带 ≥250 炸药的木箱被摧毁 → 就近 1×1 黑暗变草地
        -- （damaged=致命一击时内容物必完整，died=兜底；unit_number 去重）
        [defines.events.on_entity_damaged] = world15_woodchest_damaged,
        -- 木箱开荒 died 兜底 + 开采点亮科技死亡/枯竭通道（均无 filters）
        [defines.events.on_entity_died] = {world15_woodchest_died, world15_on_entity_died_mine_tech},
    },

    nth_tick = {
        [30] = {
            world15_dark_tick,
        },
        [60] = {
            -- 顺序有讲究：科技×2 / 撤销星岩科技 / 永远黑夜 / 史诗好运连连 是最高优先级，必须最先执行；
            -- 出生设施（retry_spawn）放在后面，万一单个设施放置失败也不影响上面的关键逻辑。
            world15_unresearch_advanced_asteroid,
            world15_normalize_damage,
            world15_purge_island_all_dam,
            world15_finish_reset,
            world15_disable_lamp,
            world15_apply_wave_interval,
            world15_zero_wave_threat_gain,
            world15_enforce_talent_cap,
            world15_process_talent_queue,
            world15_retry_spawn,
            world15_retry_market_lamps,
            world15_place_recycle_box,
            world15_place_clear_chests,
            world15_retry_clear_labels,
            world15_fortress_monitor,
            -- 火星煤 -50% 兜底（vulcanus 地表晚于研究事件创建时应用）
            world15_retry_vulcanus_coal,
            -- 白嫖组装机/电炉产量翻倍（与共享 produce() 同一 [60] tick 各补一份进度）
            world15_double_production,
        },
        [360] = {
            world15_recycle_tick,
        },
        [3600] = {
            world15_clear_swallow_tick,
        },
    },
})