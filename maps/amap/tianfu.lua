local Event = require 'utils.event'
local Loot = require 'maps.amap.loot'
local rpgtable = require 'modules.rpg.table'
local RPG = require 'modules.rpg.core'
local TPT = require 'maps.amap.tianfu_table'
local tianfu_once_skill = require 'maps.amap.tianfu_once_skill'
local tianfu_time_skill = require 'maps.amap.tianfu_time_skill'
local tianfu_trigger_skill = require 'maps.amap.tianfu_trigger_skill'
local Public = {}
local WPT = require 'maps.amap.table'
local WD = require 'modules.wave_defense.table'
local World = require 'maps.amap.world.framework'
local TianfuQuality = require 'maps.amap.tianfu_quality'
local GuiDispatcher = require 'utils.gui_dispatcher'

local TIANFU_SELECT_FRAME = 'tianfu_select_frame'
local TIANFU_ZHIYE_SELECT_FRAME = 'tianfu_zhiye_select_frame'
local TIANFU_FRAME = 'amap_tianfu_frame'
local TIANFU_CARD_BUTTON = 'tianfu_card_button'

-- ===== 天赋黑名单 =====
-- 黑名单中的天赋：①无法在天赋选择界面被选中；②不会在周期性天赋触发函数（on_tick）中生效。
-- 如需增删黑名单，请同步修改 maps/amap/tianfu_blacklist.json 与本表。
local tianfu_blacklist = {
    ['tls'] = '通灵术',
    ['hmds'] = '黑魔导师',
    ['zhs'] = '黑暗召唤',
    ['wlfs'] = '亡灵法师',
    ['wanglingdajun'] = '秽土转生'
}
local function is_tianfu_blacklisted(skill_name)
    if tianfu_blacklist[skill_name] then return true end
    -- 每个世界可在框架 def 的 disabled_talents 字段声明本世界禁用的天赋
    local world_number = (WPT.get() or {}).world_number
    if world_number then
        local disabled = World.get_field(world_number, 'disabled_talents')
        if disabled and disabled[skill_name] then
            return true
        end
    end
    return false
end

-- 获取已初始化的表引用

local t = {

    ['small-biter'] = 1,
    ['small-spitter'] = 2,
    ['small-worm-turret'] = 32,
    ['medium-biter'] = 8,
    ['medium-spitter'] = 8,
    ['medium-worm-turret'] = 64,
    ['big-biter'] = 32,
    ['big-spitter'] = 32,
    ['big-worm-turret'] = 128,
    ['behemoth-biter'] = 128,
    ['behemoth-spitter'] = 128,
    ['behemoth-worm-turret'] = 256,
    ['biter-spawner'] = 320,
    ['spitter-spawner'] = 320
}

-- 检查玩家是否学习了特定天赋（用于触发天赋判断）
function Public.is_learned(player, skill_id)
    local main_table = WPT.get()
    if not main_table.tianfu_enabled[player.index] then
        main_table.tianfu_enabled[player.index] = {}
    end
    return main_table.tianfu_enabled[player.index][skill_id] == true
end

-- 检查玩家是否学习过特定天赋（用于天赋选择判断，无论启用还是禁用）
function Public.has_learned(player, skill_id)
    local main_table = WPT.get()
    if not main_table.tianfu_enabled[player.index] then
        main_table.tianfu_enabled[player.index] = {}
    end
    return main_table.tianfu_enabled[player.index][skill_id] ~= nil
end


    local function create_damage_floating_text(target_entity, damage_amount, damage_type, player)
    
    -- 根据伤害类型选择颜色
    local color = {r = 1, g = 0.5, b = 0} -- 橙色

    
    -- 在目标位置上方显示伤害数值
    local text_position = {
        x = target_entity.position.x,
        y = target_entity.position.y - 1.5
    }
    
    -- 创建漂浮文本
    player.create_local_flying_text({
        text = tostring(math.floor(damage_amount)),
        position = text_position,
        color = color,
        time_to_live = 60, -- 1秒
        speed = 1.5
    })
end

local function deal_damage_with_floating_text(target_entity, player, damage_amount, damage_type)
    if type(damage_amount) ~= 'number' or damage_amount <= 0 then
        return false
    end     
    local this=WPT.get()
    local damage_multiplier = this.damage_multiplier or 1
    local final_damage = damage_amount * damage_multiplier
    damage_type = damage_type or 'explosion'
    create_damage_floating_text(target_entity, final_damage, damage_type, player)
    target_entity.damage(final_damage, 'player', damage_type, player.character)
 
    return true
end

local function is_gui_visible(element)
    if not element or not element.valid then
        return false
    end

    local screen = element.parent or element

    if screen.valid then
        local visible = screen.visible
        return visible
    end

    return false
end

local function random_k(player_index, k)
    if type(k) ~= 'number' or k < 1 then
        return 1
    end
    
    local main_table = WPT.get()
    
    -- 1. 获取或生成该玩家的随机种子
    if not main_table.random_seed then
        main_table.random_seed= {}
    end
    if not main_table.random_seed[player_index] then
        main_table.random_seed[player_index] = math.random(1, 999999)
    end
    
    -- 2. 获取连接游戏的人数
    local player_count = #game.connected_players
    
    -- 3. 获取当前地图种子
    local map_seed = game.surfaces['nauvis'].map_gen_settings.seed or 0
    
    -- 4. 获取玩家已学习的天赋数量
    local tianfu_count = main_table.tianfu_count[player_index] or 0
    
    -- 5. 根据参数计算确定性随机数
    -- 使用线性同余生成器 (LCG)
    local seed = main_table.random_seed[player_index] + player_index + player_count + map_seed + tianfu_count
    seed = (seed * 1103515245 + 12345) % 2147483648
    
    -- 生成1-k的随机数
    local result = (seed % k) + 1
    
    -- 更新该玩家的种子，使每次调用产生不同的结果
    main_table.random_seed[player_index] = (main_table.random_seed[player_index] * 1103515245 + 12345) % 2147483648
    
    return result
end


local time_skills = tianfu_time_skill.time_skills
local trigger_skills = tianfu_trigger_skill.trigger_skills

function Public.reset_table()
    -- 使用 tianfu_table.lua 中的重置功能
    TPT.reset_table()

    -- 重新获取表引用（虽然不应该改变，但为了安全起见）
    local this = TPT.get()

    -- 重新初始化技能相关数据
    -- 注：this[_] = {} 已删除（真正的死字段：无消费者）
    -- tianfu_cooldown[_] = v.time 保留：gui.lua 冷却条读取此字段
    for _, v in pairs(time_skills) do
        if v.time then this.tianfu_cooldown[_] = v.time end
        this.all_skill[#this.all_skill + 1] = _
    end
    for _ in pairs(tianfu_once_skill.once_skills) do
        this.all_skill[#this.all_skill + 1] = _
    end
    for _, v in pairs(trigger_skills) do
        if v.time then this.tianfu_cooldown[_] = v.time end
        this.all_skill[#this.all_skill + 1] = _
    end

    for k, player in pairs(game.connected_players) do
        local screen = player.gui.screen
        local frame = screen['选择你的天赋']

        if frame and frame.valid then
            frame.destroy()
        end
    end
end

-- 4类天赋分类表
local tianfu_categories = {
    mage = {                                    -- 法师类天赋（通过虫子，召唤物战斗，魔法相关）
       'yl',                                   -- 鱼灵
        'mlzq',                                 -- 魔力之泉
        'yubaobao',                             -- 鱼宝宝
        'smmf',                                 -- 魔法盾
        'kls',                                  -- 傀儡师
        'mfxt',                                 -- 魔法学徒
        'wlfs',                                 -- 亡灵法师
        'juemuren',                             -- 掘墓人
        'hmds',                                 -- 黑魔导师
        'zhs',                                   -- 黑暗召唤
       --  'jgq',                                  -- 微型法术激光枪
        'mzqz',                                 -- 魔杖窃贼
        'mijingzhang',                          -- 魔晶杖
        'juqichengjian',                        -- 聚气成剑
        'fali',                                 -- 法力光环
       -- 'fumo',                                 -- 附魔
        'jifengbu',                             -- 疾风步
        'morefali',                             -- 备用法力瓶
        'xxzb',                                 -- 鲜血之杯
        'yjjn',                                 -- 应急胶囊
        'leitingwanjun',                        -- 雷霆万钧
        'tls',                                  -- 通灵术
        'cjs',                                  -- 传教士
        'fish',                                 -- 钓鱼佬
        'yfz',                                  --鱼贩子
        'yuer',                                 -- 鱼饵
        'bei_dong_zhao_huan',                   -- 被动召唤
        --'wanglingdajun',                        -- 亡灵大军
        'shen_fa',                              -- 神罚
        'dianjiqiang',                          --电击枪
        'xxyd',                                 -- 鲜血涌动
        'mlst',                                 -- 魔力升腾
        'smlw',                                 -- 神秘礼物
        'xybg',                                 -- 小鱼饼干
        'hyll',                                 -- 好运连连
        'jika',                                  --集卡
        'zhuoshao',                             --灼烧
        'tianzhao',                             --天照
        'tieshenhuwei',                         --贴身护卫
          'chuanqibaozang',                    --传说宝藏
        'falibiqu',  -- 法力汲取
        'wanlaotianlei',  -- 万牢天雷引
        'shandianwulianbian',  -- 闪电五连鞭
        'diyu_rongyan',        -- 地狱熔岩
        'shui_hu_fu',  -- 水护符
        'shui_dun',  -- 水遁
        'htms',  -- 红图抹杀
        'tishenshu',  -- 替身术
        'fengyinjuanzhou',  -- 封印卷轴
        'dijiaojiaotu',  -- 低阶教徒
        'wuxingjue',  -- 五行诀
       -- 'weiyang',  -- 喂养
        --'xunshoushi',  -- 驯兽师
        'shimozhe',  -- 噬魔者
        'mdt',  -- 魔盗团
        'shalujingyan', -- 杀戮经验
        'yanmo',  -- 炎魔
        'yuediaoyuerou', -- 越钓越肉
        'zidongfanmai',  -- 自动贩卖机
        'huoliyu',        -- 活力鱼
        'njbomb',          -- 黏土炸弹
    },
    builder = {      -- 建造者类天赋（建设基地，敏捷相关，资源经济）
        'rsrl',      -- 肉身熔炉
        'fuzhushou', -- 辅助手
       -- 'wuqidashi', -- 武器大师
        'scmcc',     -- 深层采矿车
       -- 'rlfdz',     -- 人力发电站
        'ylsgd',     -- 幽灵施工队
        'gcd',       -- 工程队
        'keyan',     -- 科研人员
        'bpz',       -- 奔跑者
        'fangshou',  -- 城防建设者
        'dianluban', -- 芯片工人
        'jiguang',   -- 激光炮塔生产线
        'sansan',    -- 三三合成
        'bujiwu',    -- 布吉舞者
        'kytd',      -- 科研团队
        'djrc',      -- 顶尖人才
        'tann',      -- 探囊
        'jndd',      -- 江南大盗
        'bulider',   -- 建筑师
        'ycj',       -- 印钞机
        'jxhx',      -- 机械核心
        'touqian',   -- 机敏的小偷
        'ftlt',      -- 垃圾佬
        'kxj',       -- 科学家
        'xueshu',    -- 学术剽窃
        'junhuo',    -- 子弹工厂,
        'dgjx',      -- 帝国军饷
        'yanfayanjiuzhongxin',--研发中心
        'kejigongsi', -- 科技公司
        'chuanqibaozang',--传说宝藏
        'zishenzhuanjia',--资深专家
        'mokuaizhuangjia',--模块装甲
        'gycs',       -- 工业城市
        'shoucuo_de_shen', -- 手搓的神
        'dcrg',       -- 电磁干扰
        'shouyiren',   -- 手艺人
        'xuetu',       -- 学徒
        'gongchengche', -- 工程车
        'jiansheche',   -- 建设车
        'yelianche',    -- 冶炼车
        'jidiche',      -- 基地车
        'beibaozhengli', -- 虚空物流协议
        'waixinglaike', -- 外星来客
        'tesla_battery', -- 特斯拉蓄电池
        'hd',           -- 皇帝
        'small_buss', -- 小商人
        'qiche_ren', -- 汽车人
        'haiguanfang',
        'jqrpu',       -- 机器人仆从
    },
    fighter = {          -- 战斗者类天赋（通过增强自身能力战斗，力量和活力相关）
        'shengguangzhongji', -- 圣光重击
        'gongshengti', -- 共生体
        'hushenfu',      -- 护身符
        'chongfengxianzhen', -- 冲锋陷阵
        'jingzhunzhidao', -- 精准制导
        'lianhejuntuan', -- 联合军团
        'rsrl',          -- 肉身熔炉
        'xly',           -- 新兵训练营
        'mbz',           -- 漫步者
         'yhw',           -- 复制指环
        'zdfs2',         -- 自动导弹发射器2
        'daodaoku',      -- 导弹库
      --  'fkdda',         -- 疯狂导弹A型
        --'fkddb',         -- 疯狂导弹B型
        'zdfs',          -- 自动导弹发射器
        'xxyd',          -- 鲜血涌动
        'jingong',       -- 进攻！战斗!
        'genben',        -- 小跟班
        'sglz',            -- 圣光礼赞
        'xuebao',          -- 血爆
        'shoujiao_wuqi',   -- 收缴武器
        'danmu_gongji',    -- 弹幕攻击
        'boom_player',     -- 炸弹人
        'qns',             -- 全能神
        'wjjt',            -- 无尽军团
        'sgj',             -- 赏金猎人
        'baot',            -- 暴徒
        'xixue',           -- 蠕虫

        'fatiao',          -- 发条
        'wolf',            -- 狼人
       -- 'jiantazhe',       -- 践踏者
        'youxia',          -- 游侠
        'caijuezhe',       -- 裁决者
        'peishentuanyuan', -- 陪审团
        'rs',              -- 热血
        'honzha',          -- 轰炸
        'chifu',           -- 赤服
        'tianshi',         -- 天使
        'relife',          -- 复活
        'sxf',             -- 嗜血
        'whea',            -- 我好饿
        'zrsc',            -- 自然生涨
        'zg',              -- 宰割
        'xj',         -- 献祭
        'yinxuejian',      -- 饮血剑
        'lg',              -- 炼金师
        'sangjin',         -- 赏金猎人,
        'xxg',             -- 食尸鬼
        'dgwd',            -- 帝国卫队
        'yueshayueduo',    -- 越杀越多
        'hkzy',            -- 活力护盾：活力值>1200且为全属性最高时，受伤害有10%概率恢复血量并反弹伤害
       -- 'zhiming',         -- 致命一击：你的火箭弹在造成伤害的时候，有15%的概率翻倍伤害
        'zhaohuan_kongxi', -- 召唤空袭
        'pochen_bawangqiang', -- 破阵霸王枪
        'lidazhuanfei',    -- 力大砖飞
        'xuyiyiquan',      -- 蓄意一拳
        'shuangrenjian',   -- 双刃剑
        'dingjilueshizhe', -- 顶级掠食者
        'emengyingrao',    -- 噩梦萦绕
        'duoduoyishan',    -- 多多益善
    },
    other = {         -- 其他类天赋（无法归类到以上三类的天赋）
              'wudi',       -- 隐形斗篷
              'wxs',       -- 维修师
                      'tuks',            -- 吐口水
         'hhc',                                  -- 滑滑虫
          'yanshu',                               -- 鼹鼠
                  'tzzj',      -- 投资专家
        'carxiu',     -- 汽修工
       -- 'shiyou',     -- 石油大亨
        'sansan',     -- 三三合成
        'xueqiu',     -- 雪球
        'tdlx',       -- 团队领袖
        'xly',        -- 新兵训练营
        'pulu',      -- 铺路机
        'dl',         -- 独狼
        'pailei',        -- 工兵
        'hc',        -- 豪车党
        'rich_son',  -- 富二代
        'shit_luck', -- 狗屎运
        'tsxf',      -- 天神下凡
        'chishang',  -- 发钱
        'quanneng',  -- 全能
        'tjjz',      -- 机械装置
        'willdie',    -- 必死无疑
        'fcz',        -- 复仇者
        'zsfs',       -- 忠实粉丝
               -- 皇帝
     
        'dutu',       -- 赌徒
        'chengshuangchengdui', -- 成双成对
        'weilai',     -- 未来战士
        'shencizhishou', -- 神赐之手
        'yuedui_gushou', -- 乐队鼓手
        'lengdongyubaoxianshu', -- 冷冻鱼保鲜术
        'chaoshikongshangdian', -- 超时空商店
        'lanhuangjiaonang', -- 蓝黄胶囊
        'ailunisi', -- 艾露尼斯
        'zhidanbing', -- 掷弹兵
        'guajichengsheng', -- 挂机成圣
        'linghang', -- 领航
    }
}

-- 天赋图标映射表：天赋ID -> sprite路径
-- 未配置的天赋使用默认图标 item/raw-fish
--
-- ===== sprite 路径写法 =====
-- 内置原型图标：'item/物品名'   如 'item/raw-fish'
--                'entity/实体名'  如 'entity/small-biter'
--                'utility/xxx'    游戏内置UI图标
-- 本地自定义PNG：'file/相对场景根目录的路径'  如 'file/png/tianfu/yl.png'
--
-- ===== 添加本地自定义图标步骤 =====
-- 1. 制作 PNG 图标文件
--    - 分辨率：必须是 2 的幂次方正方形，推荐 64×64 或 128×128
--      （可选尺寸：32×32 / 64×64 / 128×128 / 256×256）
--    - 非 2 的幂次方（如 60×60、100×100）会导致加载失败或渲染异常
--    - 背景透明（PNG 支持 alpha 通道），图标主体居中
--    - 格式：标准 PNG，不要用渐进式 PNG
-- 2. 放置文件：建议放到 png/tianfu/ 子目录，用技能ID命名
--    路径示例：c:\...\坦克保卫战\png\tianfu\yl.png
-- 3. 在下方映射表中添加条目：
--    ['技能ID'] = 'file/png/tianfu/技能ID.png',
-- 4. 无需重启游戏，重新触发天赋选择即可看到新图标
--
-- ===== 安全保证 =====
-- is_valid_sprite() 会用 Factorio 原生 API helpers.is_valid_sprite_path 校验
-- 路径无效（文件不存在、尺寸不符等）会自动降级为默认鱼图标 item/raw-fish
-- 不会导致界面卡死，最多显示成默认图标
local tianfu_icons = {
    -- 法师类（mage）
    ['yl'] = 'entity/fish',                  -- 鱼灵
    ['yubaobao'] = 'item/raw-fish',                -- 鱼宝宝
    ['fish'] = 'item/raw-fish',                    -- 钓鱼佬
    ['yuer'] = 'item/raw-fish',                    -- 鱼饵
    ['xybg'] = 'item/raw-fish',                    -- 小鱼饼干
    ['mijingzhang'] = 'item/iron-stick',             -- 魔晶杖
    ['juqichengjian'] = 'item/steel-axe',           -- 聚气成剑
    ['smmf'] = 'item/energy-shield-equipment',     -- 魔法盾
    ['mlzq'] = 'item/battery',                      -- 魔力之泉
    ['morefali'] = 'item/battery',                  -- 备用法力瓶
    ['mlst'] = 'item/accumulator',                      -- 魔力升腾
    ['kls'] = 'entity/defender',                    -- 傀儡师
    ['mfxt'] = 'entity/defender',                   -- 魔法学徒
    ['wlfs'] = 'entity/small-biter',                   -- 亡灵法师
    ['zhs'] = 'entity/biter-spawner',                    -- 黑暗召唤
    ['bei_dong_zhao_huan'] = 'entity/small-biter', -- 被动召唤（召唤虫子宠物）
    ['tieshenhuwei'] = 'entity/defender',           -- 贴身护卫
    ['tls'] = 'entity/biter-spawner',               -- 通灵术
    ['dijiaojiaotu'] = 'entity/small-biter',      -- 低阶教徒
    ['mzqz'] = 'item/iron-stick',                   -- 魔杖窃贼
    ['fali'] = 'item/battery',                  -- 法力光环（回法力）
    ['jifengbu'] = 'item/exoskeleton-equipment',    -- 疾风步
    ['yjjn'] = 'item/poison-capsule',    -- 应急胶囊
    ['leitingwanjun'] = 'item/discharge-defense-equipment', -- 雷霆万钧
    ['shandianwulianbian'] = 'item/discharge-defense-equipment', -- 闪电五连鞭（闪电链）
    ['cjs'] = 'item/battery',                      -- 传教士（给魔力）
    ['yfz'] = 'item/coin',                          -- 鱼贩子
    ['hyll'] = 'item/coin',                         -- 好运连连
    ['jika'] = 'item/coin',                         -- 集卡
    ['smlw'] = 'item/wooden-chest',                         -- 神秘礼物
    ['zhuoshao'] = 'item/flamethrower-ammo',        -- 灼烧
    ['tianzhao'] = 'item/artillery-shell',          -- 天照
    ['diyu_rongyan'] = 'entity/flamethrower-turret',    -- 地狱熔岩
    ['yanmo'] = 'item/flamethrower',           -- 炎魔
    ['chuanqibaozang'] = 'item/steel-chest',        -- 传说宝藏
    ['shen_fa'] = 'item/artillery-targeting-remote', -- 神罚
    ['shimozhe'] = 'item/iron-stick',               -- 噬魔者
    ['mdt'] = 'entity/distractor',               -- 魔盗团
    ['shalujingyan'] = 'entity/small-biter',     -- 杀戮经验
    ['falibiqu'] = 'item/iron-stick',               -- 法力汲取
    ['xxyd'] = 'item/steel-axe',                    -- 鲜血涌动
    ['xxzb'] = 'item/battery',                  -- 鲜血之杯（回法力）
    ['shui_hu_fu'] = 'item/pipe',                   -- 水护符
    ['shui_dun'] = 'item/pipe-to-ground',                      -- 水遁
    ['tishenshu'] = 'item/energy-shield-equipment', -- 替身术
    ['fengyinjuanzhou'] = 'item/blueprint',        -- 封印卷轴
    ['wuxingjue'] = 'item/steel-axe',               -- 五行诀
    ['htms'] = 'item/deconstruction-planner',       -- 红图抹杀

    -- 建造者类（builder）
    ['fuzhushou'] = 'entity/inserter',      -- 辅助手（自动建设机械臂等）
    ['gcd'] = 'item/construction-robot',                -- 工程队
    ['keyan'] = 'entity/lab',                       -- 科研人员
    ['kytd'] = 'item/automation-science-pack',                        -- 科研团队
    ['kxj'] = 'item/chemical-science-pack',                         -- 科学家
    ['yanfayanjiuzhongxin'] = 'item/production-science-pack',         -- 研发中心
    ['bpz'] = 'item/exoskeleton-equipment',        -- 奔跑者
    ['fangshou'] = 'entity/gun-turret',             -- 城防建设者
    ['jiguang'] = 'entity/laser-turret',            -- 激光炮塔生产线
    ['dianluban'] = 'item/processing-unit',        -- 芯片工人
    ['djrc'] = 'item/advanced-circuit',              -- 顶尖人才
    ['zishenzhuanjia'] = 'item/electronic-circuit',    -- 资深专家
    ['kejigongsi'] = 'item/productivity-module',        -- 科技公司
    ['jxhx'] = 'item/engine-unit',              -- 机械核心
    ['dcrg'] = 'item/copper-cable',              -- 电磁干扰
    ['tjjz'] = 'entity/inserter',              -- 机械装置
    ['bulider'] = 'item/construction-robot',        -- 建筑师
    ['ycj'] = 'item/coin',                          -- 印钞机
    ['ftlt'] = 'item/wooden-chest',                 -- 垃圾佬
    ['tann'] = 'item/wooden-chest',                 -- 探囊
    ['jndd'] = 'item/coin',                   -- 江南大盗（偷金币）
    ['touqian'] = 'item/coin',                -- 机敏的小偷（偷金币）
    ['shoucuo_de_shen'] = 'item/iron-plate',        -- 手搓的神
    ['shouyiren'] = 'item/iron-plate',              -- 手艺人
    ['xuetu'] = 'item/iron-plate',                  -- 学徒
    ['xueshu'] = 'item/copy-paste-tool',            -- 学术剽窃
    ['junhuo'] = 'item/firearm-magazine',           -- 子弹工厂
    ['dgjx'] = 'item/coin',             -- 帝国军饷（炮塔击杀得金币）
    ['mokuaizhuangjia'] = 'item/modular-armor',     -- 模块装甲
    ['jqrpu'] = 'item/roboport',                    -- 机器人仆从
    ['gycs'] = 'entity/assembling-machine-2',       -- 工业城市
    ['scmcc'] = 'entity/electric-mining-drill',       -- 深层采矿车
    ['gongchengche'] = 'item/car',                  -- 工程车
    ['jiansheche'] = 'item/car',                    -- 建设车（汽车自动建造）
    ['yelianche'] = 'item/car',                     -- 冶炼车（汽车冶炼）
    ['jidiche'] = 'item/car',                      -- 基地车
    ['beibaozhengli'] = 'item/steel-chest',         -- 虚空物流协议
    ['haiguanfang'] = 'entity/market',           -- 海关方（资源岛/市场）
    ['tesla_battery'] = 'item/accumulator',         -- 特斯拉蓄电池
    ['small_buss'] = 'entity/market',                   -- 小商人
    ['qiche_ren'] = 'item/car',                     -- 汽车人
    ['rsrl'] = 'entity/steel-furnace',                  -- 肉身熔炉
    ['sansan'] = 'entity/assembling-machine-1',                -- 三三合成

    -- 战士类（fighter）
    ['shengguangzhongji'] = 'item/steel-axe',       -- 圣光重击
    ['gongshengti'] = 'entity/small-biter',               -- 共生体
    ['hushenfu'] = 'item/energy-shield-equipment',  -- 护身符
    ['chongfengxianzhen'] = 'item/exoskeleton-equipment', -- 冲锋陷阵
    ['jingzhunzhidao'] = 'item/rocket-launcher', -- 精准制导（导弹）
    ['lianhejuntuan'] = 'entity/distractor',          -- 联合军团
    ['xly'] = 'entity/gun-turret',                  -- 新兵训练营
    ['mbz'] = 'item/exoskeleton-equipment',         -- 漫步者
    ['zdfs'] = 'item/rocket-launcher',                 -- 自动导弹发射器
    ['zdfs2'] = 'item/explosive-rocket',                -- 自动导弹发射器2
    ['daodaoku'] = 'item/explosive-rocket',          -- 导弹库
    ['jingong'] = 'item/tank-cannon',                 -- 进攻！战斗!
    ['genben'] = 'entity/defender',                 -- 小跟班
    ['sglz'] = 'item/energy-shield-mk2-equipment',      -- 圣光礼赞
    ['xuebao'] = 'item/grenade',                  -- 血爆
    ['shoujiao_wuqi'] = 'item/pistol',             -- 收缴武器
    ['danmu_gongji'] = 'item/submachine-gun',       -- 弹幕攻击
    ['boom_player'] = 'item/cluster-grenade',               -- 炸弹人
    ['wjjt'] = 'entity/distractor',                   -- 无尽军团
    ['sgj'] = 'item/pistol',                          -- 赏金猎人
    ['baot'] = 'item/combat-shotgun',                    -- 暴徒
    ['xixue'] = 'entity/medium-biter',                   -- 蠕虫
    ['fatiao'] = 'item/iron-gear-wheel',                  -- 发条
    ['wolf'] = 'entity/big-biter',                     -- 狼人
    ['youxia'] = 'item/shotgun',                     -- 游侠
    ['caijuezhe'] = 'item/destroyer-capsule',               -- 裁决者（召唤进攻无人机）
    ['peishentuanyuan'] = 'item/destroyer-capsule',        -- 陪审团
    ['rs'] = 'item/repair-pack',                      -- 热血（+生命）
    ['honzha'] = 'item/artillery-shell',                    -- 轰炸
    ['chifu'] = 'item/heavy-armor',                   -- 赤服
    ['tianshi'] = 'item/power-armor',   -- 天使
    ['relife'] = 'item/repair-pack',               -- 复活
    ['sxf'] = 'item/exoskeleton-equipment',                     -- 嗜血（+敏捷）
    ['whea'] = 'item/raw-fish',                     -- 我好饿
    ['zg'] = 'item/coin',                      -- 宰割（击杀掉金币）
    ['xj'] = 'item/raw-fish',                     -- 献祭（祭品）
    ['yinxuejian'] = 'item/repair-pack',              -- 饮血剑（吸血回血）
    ['sangjin'] = 'item/coin',                      -- 赏金猎人
    ['xxg'] = 'entity/behemoth-biter',                       -- 食尸鬼
    ['dgwd'] = 'entity/gun-turret',                   -- 帝国卫队（机枪炮塔）
    ['yueshayueduo'] = 'item/cluster-grenade',              -- 越杀越多
    ['hkzy'] = 'item/energy-shield-mk2-equipment',      -- 活力护盾
    ['zhaohuan_kongxi'] = 'entity/artillery-wagon', -- 召唤空袭
    ['zhidanbing'] = 'item/grenade',                 -- 掷弹兵
    ['pochen_bawangqiang'] = 'item/iron-stick',      -- 破阵霸王枪（长枪）
    ['lidazhuanfei'] = 'item/stone-brick',            -- 力大砖飞
    ['xuyiyiquan'] = 'item/steel-axe',              -- 蓄意一拳（近战）
    ['shuangrenjian'] = 'item/iron-stick',           -- 双刃剑
    ['dingjilueshizhe'] = 'entity/behemoth-biter',           -- 顶级掠食者
    ['emengyingrao'] = 'entity/medium-spitter',              -- 噩梦萦绕

    -- 其他类（other）
    ['wudi'] = 'item/night-vision-equipment',      -- 隐形斗篷
    ['wxs'] = 'item/repair-pack',                   -- 维修师
    ['tuks'] = 'entity/small-spitter',               -- 吐口水
    ['hhc'] = 'item/slowdown-capsule',                       -- 滑滑虫（减速胶囊）
    ['yanshu'] = 'entity/underground-belt',                    -- 鼹鼠
    ['tzzj'] = 'item/coin',                         -- 投资专家
    ['carxiu'] = 'item/car',                -- 汽修工
    ['xueqiu'] = 'item/automation-science-pack',                      -- 雪球（经验）
    ['tdlx'] = 'item/automation-science-pack',                   -- 团队领袖（经验）
    ['pulu'] = 'item/stone-brick',                  -- 铺路机（石砖）
    ['dl'] = 'entity/big-biter',                      -- 独狼
    ['pailei'] = 'item/land-mine',                -- 工兵
    ['hc'] = 'item/car',                           -- 豪车党
    ['rich_son'] = 'item/coin',                     -- 富二代
    ['shit_luck'] = 'item/steel-chest',                    -- 狗屎运（宝箱）
    ['tsxf'] = 'item/power-armor',                    -- 天神下凡
    ['chishang'] = 'item/coin',                     -- 发钱
    ['quanneng'] = 'item/power-armor-mk2',                -- 全能
    ['willdie'] = 'item/atomic-bomb',                -- 必死无疑
    ['fcz'] = 'item/destroyer-capsule',                     -- 复仇者
    ['zsfs'] = 'item/coin',                         -- 忠实粉丝
    ['dutu'] = 'item/coin',                         -- 赌徒
    ['chengshuangchengdui'] = 'item/blueprint-book', -- 成双成对
    ['weilai'] = 'item/spidertron',                  -- 未来战士
    ['shencizhishou'] = 'item/repair-pack', -- 神赐之手
    ['chaoshikongshangdian'] = 'entity/market',     -- 超时空商店
    ['lanhuangjiaonang'] = 'item/poison-capsule',      -- 蓝黄胶囊
    ['lengdongyubaoxianshu'] = 'item/raw-fish',     -- 冷冻鱼保鲜术（鱼）
    ['ailunisi'] = 'item/spidertron',                -- 艾露尼斯
    ['hd'] = 'item/steel-chest',                     -- 皇帝
    ['guajichengsheng'] = 'item/coin',                -- 挂机成圣
    ['yuediaoyuerou'] = 'item/raw-fish',             -- 越钓越肉
    ['linghang'] = 'utility/heart',                    -- 领航
    ['duoduoyishan'] = 'entity/small-biter',            -- 多多益善（敌方虫子）
    ['zidongfanmai'] = 'entity/market',                 -- 自动贩卖机（市场）
    ['huoliyu'] = 'item/raw-fish',                    -- 活力鱼（鱼）
    ['njbomb'] = 'item/land-mine',                     -- 黏土炸弹（炸弹意象）

    -- 补充：技能表中存在（可在游戏中学习）但未在分类或原映射中配置的图标
    ['zhrm'] = 'item/battery',                  -- 走火入魔（法力）
    ['ljss'] = 'entity/small-biter',            -- 我方虫子（杀友方虫子换经验）
    ['dafs'] = 'item/iron-stick',               -- 大法师
    ['jgq'] = 'entity/laser-turret',            -- 微型法术激光枪
    ['fumo'] = 'entity/small-biter',            -- 附魔虫
    ['xunshoushi'] = 'entity/small-biter',      -- 驯兽师
    ['rlfdz'] = 'item/accumulator',             -- 人力发电站
    ['wuqidashi'] = 'item/personal-laser-defense-equipment', -- 武器大师
    ['jiantazhe'] = 'item/stone-brick',         -- 践踏者（踩踏）
    ['liliangup'] = 'item/stone',               -- 力量训练（挖石头）
    ['qykj'] = 'item/automation-science-pack',  -- 前沿科技
    ['weiyang'] = 'item/raw-fish',              -- 喂养（鱼）
    ['waixinglaike'] = 'entity/biolab',         -- 外星来客（生物实验室）

    -- 补充2：技能表存在（可学习）但原 tianfu_icons 缺失，逐个读函数按实际效果补齐
    ['bujiwu'] = 'item/coin',                    -- 补给物（按在线人数+敏捷给金币）
    ['dianjiqiang'] = 'entity/laser-turret',     -- 电击枪（发射 electric-beam，激光伤害）
    ['wanlaotianlei'] = 'entity/laser-turret',    -- 万牢天雷引（范围天雷魔法伤害，激光伤害类型）
    ['fkdda'] = 'item/rocket',                   -- 防空导弹A（制造 rocket 抛射物）
    ['fkddb'] = 'item/rocket',                   -- 防空导弹B（制造 rocket 抛射物）
    ['hmds'] = 'entity/small-biter',             -- 毁灭之矢（耗蓝召唤虫子）
    ['juemuren'] = 'entity/small-biter',         -- 掘墓人（尸体复活虫子）
    ['lg'] = 'entity/small-biter',               -- 炼骨（吞食虫子尸体换力量）
    ['qns'] = 'item/explosive-rocket',           -- 全能射线（发射 explosive-rocket 弹幕）
    ['yhw'] = 'item/rocket',                     -- 反弹（将拾取的敌方抛射物打回）
    ['ylsgd'] = 'item/construction-robot',       -- 幽灵自动建造（自动补全 ghost 建筑）
    ['yuedui_gushou'] = 'item/jellynut',         -- 乐队鼓手（施加 jellynut 加速贴纸）
    ['zhiming'] = 'item/grenade',                -- 致命一击（15%爆炸暴击）
    ['zrsc'] = 'item/repair-pack',               -- 自然人（活力回复）
}

-- 校验sprite路径是否有效，避免sprite-button创建时抛错导致整个GUI中断
-- 使用Factorio原生API helpers.is_valid_sprite_path，覆盖所有sprite类型
-- （item/entity/file/utility等），比手写prototype校验更可靠
local function is_valid_sprite(sprite_path)
    if not sprite_path or type(sprite_path) ~= 'string' then
        return false
    end
    -- helpers.is_valid_sprite_path 是Factorio原生API，runtime可用
    -- 能校验 item/ entity/ file/ utility/ 等所有SpritePath类型
    return helpers.is_valid_sprite_path(sprite_path)
end

-- 获取天赋对应的图标sprite，未配置或无效的返回默认图标item/raw-fish
local function get_tianfu_icon(skill_id)
    local icon = tianfu_icons[skill_id]
    if icon and is_valid_sprite(icon) then
        return icon
    end
    return 'item/raw-fish'
end


-- 职业选择GUI函数
local function choise_zhiye(player)
    -- 移除可能存在的天赋选择框
    if player.gui.screen[TIANFU_SELECT_FRAME] then
        player.gui.screen[TIANFU_SELECT_FRAME].destroy()
    end

    -- 移除可能已存在的职业选择框
    if player.gui.screen[TIANFU_ZHIYE_SELECT_FRAME] then
        player.gui.screen[TIANFU_ZHIYE_SELECT_FRAME].destroy()
    end

    -- 显示职业选择界面
    local frame = player.gui.screen.add {
        type = 'frame',
        caption = { 'tianfu.choise_zhiye' },
        name = TIANFU_ZHIYE_SELECT_FRAME,
        direction = 'vertical'
    }
    frame.force_auto_center()

    -- 添加说明文本
    local label = frame.add({
        type = 'label',
        caption = { 'tianfu.choise_zhiye' }
    })
    label.style.font = 'heading-2'
    label.style.font_color = { r = 0.0, g = 0.5, b = 1.0 }
    -- 添加职业选择按钮
    -- 为每个职业选项添加一个键，用于创建按钮名称
    local zhiye_with_keys = { {
        key = '随机',
        name = { 'tianfu.random' },
        tooltip = ''
    }, {
        key = '战士',
        name = { 'tianfu.zhiye_zhanshi' },
        tooltip = { 'tianfu.zhiye_zhanshi_tip' }
    }, {
        key = '法师',
        name = { 'tianfu.zhiye_fashi' },
        tooltip = { 'tianfu.zhiye_fashi_tip' }
    }, {
        key = '建造者',
        name = { 'tianfu.zhiye_builder' },
        tooltip = { 'tianfu.zhiye_builder_tip' }
    } }

    for _, zhiye_data in pairs(zhiye_with_keys) do
        local button = frame.add({
            type = 'button',
            name = 'tianfu_zhiye_' .. zhiye_data.key,
            tooltip = zhiye_data.tooltip,
            caption = zhiye_data.name
        })
        button.style.font = 'heading-2'
        button.style.minimal_width = 160
        --button.style.font_color = {r = 0.0, g = 0.7, b = 0.0}
    end
end

-- tier: 品质档位 'low'(默认) / 'mid' / 'high'，仅透传给候选卡片 roll，不落 global。
-- 只有商店"中级/高级购买天赋"会传 mid/high；其余调用(进游戏/选职业/重开)不传→默认 low。
local function choise_skill(player, tier)
    local this = TPT.get()
    -- 获取main_table
    local main_table = WPT.get()
if not main_table.crafting_exp_multiplier[player.index] then
  main_table.crafting_exp_multiplier[player.index] = 1
end
    -- 检查玩家是否已选择职业
    if not main_table.zhiye[player.name] then
        -- 玩家未选择职业，显示职业选择界面
        choise_zhiye(player)
        return
    end

    local selected = {}
    -- 确保表已初始化后再访问
    if this and this.xuanze then
        if this.xuanze[player.index] == 1 then
            return
        end
        this.xuanze[player.index] = 1
    end

    -- 移除可能已存在的天赋选择框
    if player.gui.screen[TIANFU_SELECT_FRAME] then
        player.gui.screen[TIANFU_SELECT_FRAME].destroy()
    end

    local frame = player.gui.screen.add {
        type = 'frame',
        caption = { 'tianfu.choise_skill' },
        name = TIANFU_SELECT_FRAME,
        direction = 'vertical'
    }
    frame.force_auto_center()

    -- 获取玩家职业
    local zhiye = main_table.zhiye[player.name]

    -- 准备天赋选项列表
    local skill_options = {}

    -- 判断是否为第一次选择天赋
    local is_first_selection = false
    if not main_table.tianfu_count[player.index] or main_table.tianfu_count[player.index] == 0 then
        is_first_selection = true
    end

    -- 定义第一次选择时的固定天赋
    local fixed_skill = nil
    if is_first_selection then
        if zhiye == '建造者' and not is_tianfu_blacklisted('fuzhushou') then
            fixed_skill = 'fuzhushou'  -- 辅助手（世界15 该天赋被禁用，则不再作为固定天赋）
        elseif zhiye == '战士' then
            fixed_skill = 'genben'  -- 小跟班
        elseif zhiye == '法师' then
            fixed_skill = 'mijingzhang'  -- 魔晶杖
        end
    end

    -- 根据职业确定天赋选择逻辑
    if zhiye == '随机' then
        -- 随机职业：从所有天赋中选择5个未学习的天赋
        local all_unlearned = {}
        for _, skill_name in ipairs(this.all_skill) do
            if not is_tianfu_blacklisted(skill_name) and not Public.has_learned(player, skill_name) then
                all_unlearned[#all_unlearned + 1] = skill_name
            end
        end

        -- 从所有未学习的天赋中随机选择5个
        local temp_unlearned = {}
        for _, skill_name in ipairs(all_unlearned) do
            temp_unlearned[#temp_unlearned + 1] = skill_name
        end
        for i = 1, math.min(5, #temp_unlearned), 1 do
            local num = random_k(player.index, #temp_unlearned)
            skill_options[#skill_options + 1] = temp_unlearned[num]
            table.remove(temp_unlearned, num)
        end
    else
        -- 特定职业：根据职业获取对应分类
        local zhiye_key = ''
        if zhiye == '法师' then
            zhiye_key = 'mage'
        elseif zhiye == '战士' then
            zhiye_key = 'fighter'
        elseif zhiye == '建造者' then
            zhiye_key = 'builder'
        end

        -- 获取对应职业分类的天赋（3个）
        if zhiye_key ~= '' and tianfu_categories[zhiye_key] then
            -- 筛选该分类中未学习的天赋
            local class_unlearned = {}
            for _, skill_name in ipairs(tianfu_categories[zhiye_key]) do
                if not is_tianfu_blacklisted(skill_name) and not Public.has_learned(player, skill_name) then
                    -- 如果有固定天赋，则跳过它（因为固定天赋会放在第4个位置）
                    if fixed_skill and skill_name == fixed_skill then
                    else
                        class_unlearned[#class_unlearned + 1] = skill_name
                    end
                end
            end

            -- 随机选择3个职业天赋
            local temp_class = {}
            for _, skill_name in ipairs(class_unlearned) do
                temp_class[#temp_class + 1] = skill_name
            end
            for i = 1, math.min(3, #temp_class), 1 do
                local num = random_k(player.index, #temp_class)
                skill_options[#skill_options + 1] = temp_class[num]
                table.remove(temp_class, num)
            end
        end

        -- 获取其他分类的天赋（2个）
        local other_unlearned = {}
        for category_key, category_skills in pairs(tianfu_categories) do
            -- 跳过当前职业的分类
            if category_key ~= zhiye_key then
                for _, skill_name in ipairs(category_skills) do
                    -- 确保天赋未被学习且不在已选择的列表中
                    if not is_tianfu_blacklisted(skill_name) and not Public.has_learned(player, skill_name) then
                        local already_selected = false
                        for _, selected_skill in ipairs(skill_options) do
                            if selected_skill == skill_name then
                                already_selected = true
                                break
                            end
                        end
                        if not already_selected then
                            -- 如果有固定天赋，则跳过它
                            if fixed_skill and skill_name == fixed_skill then
                            else
                                other_unlearned[#other_unlearned + 1] = skill_name
                            end
                        end
                    end
                end
            end
        end

        -- 如果有固定天赋，则选择1个其他天赋；否则选择2个其他天赋
        local other_count = fixed_skill and 1 or 2
        local temp_other = {}
        for _, skill_name in ipairs(other_unlearned) do
            temp_other[#temp_other + 1] = skill_name
        end
        for i = 1, math.min(other_count, #temp_other), 1 do
            local num = random_k(player.index, #temp_other)
            skill_options[#skill_options + 1] = temp_other[num]
            table.remove(temp_other, num)
        end

        -- 如果有固定天赋，将其添加到第4个位置（兜底再次校验黑名单）
        if fixed_skill and not is_tianfu_blacklisted(fixed_skill) then
            skill_options[4] = fixed_skill
        end
    end

    -- 如果通过上述方式没有足够的天赋，从所有未学习的天赋中补充
    if #skill_options < 5 then
        local all_unlearned = {}
        for _, skill_name in ipairs(this.all_skill) do
            if not is_tianfu_blacklisted(skill_name) and not Public.has_learned(player, skill_name) then
                -- 检查是否已在选项列表中
                local already_in_list = false
                for _, selected_skill in ipairs(skill_options) do
                    if selected_skill == skill_name then
                        already_in_list = true
                        break
                    end
                end
                if not already_in_list then
                    all_unlearned[#all_unlearned + 1] = skill_name
                end
            end
        end

        -- 随机选择补充的天赋
        local temp_unlearned2 = {}
        for _, skill_name in ipairs(all_unlearned) do
            temp_unlearned2[#temp_unlearned2 + 1] = skill_name
        end
        for i = 1, math.min(5 - #skill_options, #temp_unlearned2), 1 do
            local num = random_k(player.index, #temp_unlearned2)
            skill_options[#skill_options + 1] = temp_unlearned2[num]
            table.remove(temp_unlearned2, num)
        end
    end

    -- 创建天赋选择按钮（确保没有重复的技能）
    local unique_skills = {}
    local seen_skills = {}

    -- 过滤出唯一的技能
    for _, skill_name in ipairs(skill_options) do
        if not seen_skills[skill_name] then
            seen_skills[skill_name] = true
            unique_skills[#unique_skills + 1] = skill_name
        end
    end

    -- 使用唯一的技能列表创建卡片式天赋选择界面
    -- 横向5张卡片，每张从上到下：天赋名称、物品图标(点击即选取)、天赋介绍
    local cards_flow = frame.add({
        type = 'flow',
        name = 'tianfu_cards_flow',
        direction = 'horizontal'
    })
    cards_flow.style.horizontal_spacing = 8
    cards_flow.style.vertical_align = 'top'

    for _, skill_name in ipairs(unique_skills) do
        -- ★ 天赋品质：每个候选卡片独立 roll 一次，显示与最终学习共用
        -- tier 决定档位（中级/高级购买传 mid/high，高概率出高品质；默认 low）
        local q_idx = TianfuQuality.roll(tier)
        local q_color = TianfuQuality.color(q_idx) or {r = 200, g = 200, b = 200}
        local q_color_ui = {r = q_color.r / 255, g = q_color.g / 255, b = q_color.b / 255}

        -- 卡片容器（用frame做边框，更像"卡片"）
        -- vertically_stretchable=true 让卡片等高，配合底部按钮对齐
        local card = cards_flow.add({
            type = 'frame',
            name = 'tianfu_card_' .. skill_name,
            direction = 'vertical'
        })
        card.style.minimal_width = 160
        card.style.maximal_width = 160
        card.style.padding = 8
        card.style.vertically_stretchable = true

        -- 1. 天赋名称（居中、字号、颜色按品质变化）
        local name_flow = card.add({
            type = 'flow',
            direction = 'horizontal'
        })
        name_flow.style.horizontally_stretchable = true
        name_flow.style.horizontal_align = 'center'
        name_flow.style.minimal_height = 36  -- 给两行名称留空间
        name_flow.style.vertical_align = 'center'
        local name_label = name_flow.add({
            type = 'label',
            caption = { 'tianfu.' .. skill_name }
        })
        name_label.style.font = 'heading-1'
        name_label.style.font_color = q_color_ui
        name_label.style.single_line = false
        name_label.style.maximal_width = 140

        -- 2. 天赋品质（标题下方，颜色与品质一致）
        local quality_flow = card.add({
            type = 'flow',
            direction = 'horizontal'
        })
        quality_flow.style.horizontally_stretchable = true
        quality_flow.style.horizontal_align = 'center'
        local quality_label = quality_flow.add({
            type = 'label',
            caption = { 'tianfu.quality_label', TianfuQuality.locale_name(q_idx) }
        })
        quality_label.style.font = 'default-bold'
        quality_label.style.font_color = q_color_ui

        -- 3. 物品图标 + 品质角标（图标本身可点击 = 选取该天赋）
        local icon_flow = card.add({
            type = 'flow',
            direction = 'horizontal'
        })
        icon_flow.style.horizontally_stretchable = true
        icon_flow.style.horizontal_align = 'center'
        icon_flow.style.vertical_align = 'top'
        icon_flow.style.top_padding = 4
        icon_flow.style.bottom_padding = 4
        local icon_btn = icon_flow.add({
            type = 'sprite-button',
            name = TIANFU_CARD_BUTTON,
            sprite = get_tianfu_icon(skill_name),
            tooltip = { 'tianfu.' .. skill_name .. '_tip', table.unpack(TianfuQuality.tip_args(skill_name, q_idx)) },
            tags = { tianfu_card = true, quality = q_idx, skill_name = skill_name },
            mouse_button_filter = { 'left' }
        })
        icon_btn.style.minimal_width = 80
        icon_btn.style.minimal_height = 80
        icon_btn.style.maximal_width = 80
        icon_btn.style.maximal_height = 80

        -- 品质角标（覆盖在图标右上角，若 quality 图标不存在则回退不显示）
        local quality_sprite_path = TianfuQuality.icon(q_idx)
        if is_valid_sprite(quality_sprite_path) then
            local badge = icon_flow.add({
                type = 'sprite',
                sprite = quality_sprite_path,
                tooltip = TianfuQuality.locale_name(q_idx)
            })
            badge.ignored_by_interaction = true
            badge.style.minimal_width = 28
            badge.style.minimal_height = 28
            badge.style.maximal_width = 28
            badge.style.maximal_height = 28
            badge.style.left_margin = -28
        end

        -- 4. 天赋介绍（居中、自动换行、撑开高度让5张卡片等高、按钮自然落底）
        local desc_flow = card.add({
            type = 'flow',
            direction = 'horizontal'
        })
        desc_flow.style.horizontally_stretchable = true
        desc_flow.style.horizontal_align = 'center'
        desc_flow.style.vertically_stretchable = true
        desc_flow.style.top_padding = 4
        local desc_label = desc_flow.add({
            type = 'label',
            caption = { 'tianfu.' .. skill_name .. '_tip', table.unpack(TianfuQuality.tip_args(skill_name, q_idx)) }
        })
        desc_label.style.font = 'default'
        desc_label.style.single_line = false
        desc_label.style.maximal_width = 140
        desc_label.style.horizontal_align = 'center'

        -- 选取按钮已移除：点击图标即视为选取该天赋（见上方 icon_btn 的 tags）
    end

    if not main_table.tianfu_count[player.index] then
        main_table.tianfu_count[player.index] = 0
    end
    main_table.tianfu_count[player.index] = main_table.tianfu_count[player.index] + 1
end

-- tier: 'low'(默认) / 'mid' / 'high'，由商店购买入口传入，透传给 choise_skill 决定 roll 档位
function Public.get_new_tianfu(player, tier)
    choise_skill(player, tier)
end

local function on_player_joined_game(event)
    local this = TPT.get()
    local player = game.players[event.player_index]
    -- 确保表已初始化后再访问
    if this and this.choise_skill then
        if not this.choise_skill[player.name] then
            choise_skill(player)
        end
        this.choise_skill[player.name] = true
    else
        -- 如果表未初始化，则先初始化再执行操作
        choise_skill(player)
    end
end

function Public.get(key)
    local this = TPT.get()
    if key then
        return this[key]
    else
        return this
    end
end

function Public.set(key, value)
    local this = TPT.get()
    if key and (value or value == false) then
        this[key] = value
        return this[key]
    elseif key then
        return this[key]
    else
        return this
    end
end

function Public.get_tianfu_categories()
    return tianfu_categories
end

local function on_zhiye_click(event)
    local this = TPT.get()
    local main_table = WPT.get()
    local player = game.players[event.element.player_index]
    if main_table.tianfu_enabled[player.index] == nil then
        main_table.tianfu_enabled[player.index] = {}
    end
    local element_name = event.element.name
    local zhiye_name = string.sub(element_name, 14)
    if zhiye_name == '随机' then
        local zhiye_options = { '战士', '法师', '建造者' }
        zhiye_name = zhiye_options[random_k(player.index, #zhiye_options)]
    end
    main_table.zhiye[player.name] = zhiye_name
    game.print({ 'tianfu.choise_zhiye_msg', player.name, zhiye_name })
    event.element.parent.destroy()
    this.xuanze[player.index] = 0
    choise_skill(player)
end

local function on_tianfu_card_click(event)
    local this = TPT.get()
    local main_table = WPT.get()
    local player = game.players[event.element.player_index]
    if main_table.tianfu_enabled[player.index] == nil then
        main_table.tianfu_enabled[player.index] = {}
    end
    this.xuanze[player.index] = 2
    local main_table = WPT.get()
    if main_table.skill[player.name] == nil then
        main_table.skill[player.name] = {}
    end
    local skill_name = event.element.tags.skill_name
    local q_idx = event.element.tags.quality or TianfuQuality.roll()
    main_table.skill[player.name][skill_name] = q_idx
    main_table.tianfu_enabled[player.index][skill_name] = true
    main_table.skill_canchoise[player.name] = 0
    game.print({ 'tianfu.choise_skill_msg', player.name, { 'tianfu.' .. skill_name }, TianfuQuality.locale_name(q_idx) })
    local q_color = TianfuQuality.color(q_idx) or {r = 200, g = 200, b = 200}
    player.print({ 'tianfu.learn_q', { 'tianfu.' .. skill_name }, TianfuQuality.locale_name(q_idx) },
        { r = q_color.r / 255, g = q_color.g / 255, b = q_color.b / 255 })
    this.choise_skill[player.name] = true
    if not tianfu_once_skill.once_skills[skill_name] then
        if time_skills[skill_name] then
            if not this.player_time_skills[player.name] then
                this.player_time_skills[player.name] = {}
            end
            this.player_time_skills[player.name][skill_name] = true
            local cooldown = time_skills[skill_name].time or 60
            if cooldown <= 0 then cooldown = 1 end
            local next_tick = game.tick + cooldown
            if not this.due_buckets then this.due_buckets = {} end
            local next_bucket = this.due_buckets[next_tick]
            if not next_bucket then
                next_bucket = {}
                this.due_buckets[next_tick] = next_bucket
            end
            local next_player_skills = next_bucket[player.index]
            if not next_player_skills then
                next_player_skills = {}
                next_bucket[player.index] = next_player_skills
            end
            next_player_skills[#next_player_skills + 1] = skill_name
        end
    else
        tianfu_once_skill.once_skills[skill_name].name(player, q_idx)
    end
    if not this.skill_owners then this.skill_owners = {} end
    if not this.skill_owners[skill_name] then this.skill_owners[skill_name] = {} end
    this.skill_owners[skill_name][player.index] = true
    player.gui.screen[TIANFU_SELECT_FRAME].destroy()
    local this = WPT.get()
    local rpg_t = rpgtable.get('rpg_t')
    local jiange = World.get_field(this.world_number, 'tianfu_jiange') or 35
    if rpg_t[player.index] and rpg_t[player.index].level and this.tianfu_count and this.tianfu_count[player.index] and this.skill_canchoise and this.skill_canchoise[player.name] == 0 then
        if math.floor(rpg_t[player.index].level / jiange) > this.tianfu_count[player.index] - 1 and is_gui_visible(frame) == false then
            this.skill_canchoise[player.name] = 1
        end
    end
    if player.gui.left[TIANFU_FRAME] then
        player.gui.left[TIANFU_FRAME].destroy()
    end
    local main_table = WPT.get()
    local cache_key = player.name
    if main_table.tianfu_names_cache then
        main_table.tianfu_names_cache[cache_key] = nil
    end
    if main_table.tianfu_keys_cache then
        main_table.tianfu_keys_cache[cache_key] = nil
    end
end

GuiDispatcher.register_click('tianfu_zhiye_随机', on_zhiye_click)
GuiDispatcher.register_click('tianfu_zhiye_战士', on_zhiye_click)
GuiDispatcher.register_click('tianfu_zhiye_法师', on_zhiye_click)
GuiDispatcher.register_click('tianfu_zhiye_建造者', on_zhiye_click)
GuiDispatcher.register_click(TIANFU_CARD_BUTTON, on_tianfu_card_click)

-- 扳机类代码
local function have_learn(player, skill)
    return Public.is_learned(player, skill)
end

local function on_tick()
    local this = TPT.get()
    local current_tick = game.tick

    -- 确保必要的表已初始化（兼容旧存档）
    if not this.player_time_skills then
        this.player_time_skills = {}
    end
    if not this.due_buckets then
        this.due_buckets = {}
    end
    if not this.batch_player_index then
        this.batch_player_index = 1
    end

    -- ===== 方案 C：旧存档迁移 =====
    -- 旧存档的 due_buckets 是空的，但玩家已经学了 time_skill
    -- 需要做一次全量迁移：遍历所有 player_time_skills，登记到 due_buckets
    if not this.due_buckets_migrated then
        for player_name, skills in pairs(this.player_time_skills) do
            -- 通过 player_name 找 player_index（玩家可能不在线，用 game.players 遍历）
            local player_index = nil
            for idx, p in pairs(game.players) do
                if p.name == player_name then
                    player_index = idx
                    break
                end
            end
            if player_index then
                for skill_name, _ in pairs(skills) do
                    local cooldown = (time_skills[skill_name] or {}).time or 60
                    if cooldown <= 0 then cooldown = 1 end
                    local next_tick = current_tick + cooldown
                    local next_bucket = this.due_buckets[next_tick]
                    if not next_bucket then
                        next_bucket = {}
                        this.due_buckets[next_tick] = next_bucket
                    end
                    local next_player_skills = next_bucket[player_index]
                    if not next_player_skills then
                        next_player_skills = {}
                        next_bucket[player_index] = next_player_skills
                    end
                    next_player_skills[#next_player_skills + 1] = skill_name
                end
            end
        end
        this.due_buckets_migrated = true
    end

    -- ===== 方案 C：tick 分桶调度 =====
    -- 查当前 tick 的到期桶，桶里只放当前 tick 到期的 time_skill
    -- 无桶立即返回（每 tick O(1) 查表，无函数调用开销）
    local bucket = this.due_buckets[current_tick]
    if bucket then
        local main_table = WPT.get()
        local enabled_all = main_table.tianfu_enabled
        local q_all = main_table.skill
        local player_time_skills = this.player_time_skills
        local time_skill_funcs = tianfu_time_skill
        -- time_skills 已是顶部 local（tianfu_time_skill.time_skills 的引用）

        for player_index, skills in pairs(bucket) do
            local player = game.players[player_index]
            -- 只在玩家对象本身无效时才跳过整个玩家（保证"登记下一次到期"不被跳过）
            if not player or not player.valid then
                goto next_player
            end
            -- can_call 控制是否真正调用天赋：断线/副本内/AFK 时仍登记下一次到期，保持桶调度链不断
            -- character 有效性不在此判断，由各 time_skill 函数内部自检兜底
            local can_call = player.connected
                             and player.force.name == 'player'
                             and player.afk_time <= 36000
            local enabled = enabled_all[player_index] or {}
            local q_table = q_all[player.name] or {}
            local p_time_skills = player_time_skills[player.name]
            -- GUI 冷却条读取 skill_cooldowns[player_index][skill] 计算 last_used
            -- 方案 C 简化 check_tick 后，由桶调度调用时同步写入此字段
            local cooldowns_all = this.skill_cooldowns
            local player_cooldowns = cooldowns_all[player_index]
            if not player_cooldowns then
                player_cooldowns = {}
                cooldowns_all[player_index] = player_cooldowns
            end

            for _, skill_name in ipairs(skills) do
                -- ★ 无条件优先登记下一次到期（只要技能未删除），与是否调用/触发成功完全解耦
                -- 这样玩家死亡/进副本/断线/AFK 时链都不会断，恢复可调用状态后自动恢复触发
                local skill_still_learned = p_time_skills and p_time_skills[skill_name]
                if skill_still_learned then
                    local cooldown = (time_skills[skill_name] or {}).time or 60
                    if cooldown <= 0 then cooldown = 1 end
                    local next_tick = current_tick + cooldown
                    local next_bucket = this.due_buckets[next_tick]
                    if not next_bucket then
                        next_bucket = {}
                        this.due_buckets[next_tick] = next_bucket
                    end
                    local next_player_skills = next_bucket[player_index]
                    if not next_player_skills then
                        next_player_skills = {}
                        next_bucket[player_index] = next_player_skills
                    end
                    next_player_skills[#next_player_skills + 1] = skill_name
                end

                -- 调用天赋（仅在可调用且未黑名单且启用时）
                if can_call and skill_still_learned
                   and not is_tianfu_blacklisted(skill_name)
                   and enabled[skill_name] ~= false then
                    local skill_func = time_skill_funcs[skill_name]
                    if skill_func then
                        -- 调用前先记录触发时刻，供 GUI 冷却条计算剩余时间
                        player_cooldowns[skill_name] = current_tick
                        -- ★ check_tick 已退化为恒 true（桶调度保证到期，check_tick 会通过）
                        skill_func(player, q_table[skill_name] or 1)
                    end
                end
            end
            ::next_player::
        end

        -- 清理当前 tick 的桶（已处理完毕）
        this.due_buckets[current_tick] = nil
    end

    -- 定期清理过期的桶（防内存泄漏：玩家退出/删除天赋后 due_buckets 残留条目）
    -- 每 3600 tick（约 1 分钟）清理一次
    if current_tick - (this.last_bucket_clean or 0) > 3600 then
        for tick, _ in pairs(this.due_buckets) do
            if tick < current_tick then
                this.due_buckets[tick] = nil
            end
        end
        this.last_bucket_clean = current_tick
    end

    -- ===== choise_skill 逻辑：每 3 tick 跑一次（保留原 batch_player_index 轮询） =====
    if current_tick % 3 ~= 0 then
        return
    end

    -- 获取当前连接的玩家列表（过滤副本玩家：force='dungeon_force_*'，天赋不进副本）
    local connected_players = {}
    for _, player in pairs(game.players) do
        if player.valid and player.connected and player.force.name == 'player' then
            table.insert(connected_players, player)
        end
    end

    -- 如果没有玩家，重置索引
    if #connected_players == 0 then
        this.batch_player_index = 1
        return
    end

    -- 确保索引在有效范围内
    if this.batch_player_index > #connected_players then
        this.batch_player_index = 1
    end

    -- 处理当前批次的玩家（只处理一个玩家）
    local current_player = connected_players[this.batch_player_index]
    if current_player and current_player.valid and current_player.connected then
        if not this.choise_skill[current_player.name] then
            choise_skill(current_player)
        end
        this.choise_skill[current_player.name] = true
    end

    -- 移动到下一个玩家
    this.batch_player_index = this.batch_player_index + 1
end

-- 独立的学习新天赋时钟事件（每30秒执行一次）
local function on_tick_learn_skill()
    -- 获取当前连接的玩家列表（过滤副本玩家）
    local connected_players = {}
    for _, player in pairs(game.players) do
        if player.valid and player.connected and player.force.name == 'player' then
            table.insert(connected_players, player)
        end
    end

    -- 如果没有玩家，直接返回
    if #connected_players == 0 then
        return
    end

    -- 学习新天赋逻辑
    for _, player in pairs(connected_players) do
        local rpg_t = rpgtable.get('rpg_t')
        local main_table = WPT.get()

        local frame = player.gui.screen[TIANFU_SELECT_FRAME]
        -- 天赋间隔经 World 框架配置表按世界查询：默认 35；竞技场/世界15 等声明 tianfu_jiange=15
        local jiange = World.get_field(main_table.world_number, 'tianfu_jiange') or 35
        -- 检查必要的变量是否存在
        if rpg_t[player.index] and rpg_t[player.index].level and main_table.tianfu_count and main_table.tianfu_count[player.index] then
            if math.floor(rpg_t[player.index].level / jiange) > main_table.tianfu_count[player.index] - 1 and
                is_gui_visible(frame) == false then
                -- 转移至gui更新天赋颜色显示，再引用天赋选择
                main_table.skill_canchoise[player.name] = 1
            end
        end
        -- ★ 方案 A：local 缓存（只取一次）
        local learned = main_table.tianfu_enabled[player.index] or {}
        if learned.yanshu == true then
            rpg_t[player.index].vitality = 10
            rpg_t[player.index].strength = 10
        end
    end
end







local function yinxuejian_shield(event)
    local this = TPT.get()
    -- 检查实体是否有效且是玩家角色
    local entity = event.entity
    if not entity or not entity.valid or entity.name ~= 'character' then
        return
    end

    -- 获取玩家对象
    local player = entity.player
    if not player or not player.valid then
        return
    end

    -- 获取伤害值
    local damage = event.final_damage_amount
    if not this.yinxuejian_shield[player.index] then 
        this.yinxuejian_shield[player.index] = 0
    end
    -- 如果玩家受到了伤害且护盾量>0，直接给玩家加血。
    if damage > 0 and this.yinxuejian_shield[player.index] > 0 then
        if this.yinxuejian_shield[player.index] > damage then
            this.yinxuejian_shield[player.index] = this.yinxuejian_shield[player.index] - damage
        else
            player.character.health = player.character.health + this.yinxuejian_shield[player.index]
            this.yinxuejian_shield[player.index] = 0
        end
    end
end

local function hushenfu_shield(event)
    local this = TPT.get()
    -- 检查实体是否有效且是玩家角色
    local entity = event.entity
    if not entity or not entity.valid or entity.name ~= 'character' then
        return
    end

    -- 获取玩家对象
    local player = entity.player
    if not player or not player.valid then
        return
    end

    -- 获取伤害值
    local damage = event.final_damage_amount
    if not this.hushenfu_shield[player.index] then
        this.hushenfu_shield[player.index] = 0
    end

    -- 如果玩家受到了伤害且护盾量>0，直接给玩家加血。
    if damage > 0 and this.hushenfu_shield[player.index] > 0 then
        if this.hushenfu_shield[player.index] > damage then
            this.hushenfu_shield[player.index] = this.hushenfu_shield[player.index] - damage + 1
            --给玩家恢复生命值
            player.character.health = player.character.health + this.hushenfu_shield[player.index]
            player.character.health = player.character.health - 1
        else
            player.character.health = player.character.health + this.hushenfu_shield[player.index]
            this.hushenfu_shield[player.index] = 0
        end
    end
end

local function on_pre_player_died(event)
    local this = TPT.get()
    local dying_player = game.players[event.player_index]
    if not dying_player then return end

    -- 副本隔离：副本玩家死亡不触发主世界天赋（天使、relife、willdie、yanshu 等）
    -- 同时主世界的天使也不会救副本里的玩家
    if dying_player.force.name ~= 'player' then return end

    -- ★ 方案 B：倒排索引遍历学过 tianshi 的玩家，替代全玩家扫描
    local owners = this.skill_owners and this.skill_owners['tianshi']
    if owners then
        local main_table = WPT.get()
        local q_all = main_table.skill
        local enabled_all = main_table.tianfu_enabled
        for player_index, _ in pairs(owners) do
            local player1 = game.players[player_index]
            if player1 and player1.valid and player1.connected and player1.force.name == 'player' then
                local learned = enabled_all[player_index] or {}
                if learned.tianshi == true then
                    local q = (q_all[player1.name] or {}).tianshi or 1
                    if tianfu_trigger_skill.tianshi(player1, dying_player, q) then
                        goto abc
                    end
                end
            end
        end
    end

    local player = dying_player

    -- ★ 方案 A：local 缓存 learned / q_table
    local main_table = WPT.get()
    local learned = main_table.tianfu_enabled[player.index] or {}
    local q_table = main_table.skill[player.name] or {}

    if learned.relife == true then
        tianfu_trigger_skill.relife(player, q_table.relife or 1)
    end

    if learned.willdie == true then
        tianfu_trigger_skill.willdie(player, q_table.willdie or 1)
    end
    if learned.yanshu == true then
        tianfu_trigger_skill.yanshu(player, q_table.yanshu or 1)
    end

    if event.cause and event.cause.name == 'character' then
        local attacker = event.cause.player
        if attacker and attacker.valid and attacker.force == player.force then
            if player.character and player.character.valid then
                local surface = player.character.surface
                local enemies = surface.count_entities_filtered({
                    position = player.character.position,
                    radius = 12,
                    force = 'enemy'
                })
                if enemies == 0 then
                    local coin_count = attacker.get_item_count('coin')
                    if coin_count > 0 then
                        attacker.remove_item({name = 'coin', count = coin_count})
                        player.insert({name = 'coin', count = coin_count})
                    end
                    if attacker.character and attacker.character.valid then
                        attacker.character.die()
                    end
                    if player.character and player.character.valid then
                        player.character.health = player.character.max_health
                    end
                end
            end
        end
    end

    ::abc::
end

local function on_player_mined_entity(event)
    local player = game.players[event.player_index]

    local entity = event.entity

    if not entity.valid then
        return
    end

    if entity.type ~= "simple-entity" then
        return
    end

    -- 副本隔离：副本玩家挖矿不触发主世界天赋
    if player.force.name ~= 'player' then return end

    -- ★ 方案 A：local 缓存
    local main_table = WPT.get()
    local learned = main_table.tianfu_enabled[player.index] or {}
    local q_table = main_table.skill[player.name] or {}

    if learned.liliangup == true then
        tianfu_trigger_skill.liliangup(player, q_table.liliangup or 1)
    end
    if learned.hyll == true then
        tianfu_trigger_skill.hyll(player, q_table.hyll or 1)
    end

    -- 检查是否学习了皇帝天赋，如果是，清除武器库存
    if learned.hd == true then
        local gun_inventory = player.get_inventory(defines.inventory.character_guns)
        if gun_inventory then
            for _, item_data in pairs(gun_inventory.get_contents()) do
                player.remove_item {
                    name = item_data.name,
                    count = item_data.count,
                    quality = item_data.quality
                }
            end
        end
    end
end

function Public.on_player_used_capsule(event)
    local this = TPT.get()
    local player = game.players[event.player_index]
    local item = event.item

    -- 副本隔离：副本玩家用胶囊不触发主世界天赋
    if player.force.name ~= 'player' then return end

    -- ★ 方案 A：local 缓存
    local main_table = WPT.get()
    local learned = main_table.tianfu_enabled[player.index] or {}
    local q_table = main_table.skill[player.name] or {}

    if learned.yhw == true and item.name ~= 'discharge-defense-remote' then
        local position = event.position
        tianfu_trigger_skill.yhw(player, position, item.name, q_table.yhw or 1)
    end

    if learned.hd == true and item.name ~= 'raw-fish' then
        for quality_name, _ in pairs(prototypes.quality) do
            player.remove_item {
                name = item.name,
                count = 999999999,
                quality = quality_name
            }
        end
    end
    if learned.xybg == true and item.name == 'raw-fish' then
        tianfu_trigger_skill.xybg(player, q_table.xybg or 1)
    end
    if learned.mdt == true and item.name == 'raw-fish' then
        tianfu_trigger_skill.mdt(player, q_table.mdt or 1)
    end
    if learned.yl == true and item.name == 'raw-fish' then
        tianfu_trigger_skill.yl(player, event.position, q_table.yl or 1)
    end
    if learned.bei_dong_zhao_huan == true and item.name == 'raw-fish' then
        tianfu_trigger_skill.bei_dong_zhao_huan(player, q_table.bei_dong_zhao_huan or 1)
    end

    -- ★ 方案 B：yfz 改倒排索引遍历（原全玩家扫描）
    if item.name == 'raw-fish' then
        local owners = this.skill_owners and this.skill_owners['yfz']
        if owners then
            local q_all = main_table.skill
            local enabled_all = main_table.tianfu_enabled
            for player_index, _ in pairs(owners) do
                local player1 = game.players[player_index]
                if player1 and player1.valid and player1.connected and player1.force.name == 'player' then
                    local learned1 = enabled_all[player_index] or {}
                    if learned1.yfz == true then
                        local q = (q_all[player1.name] or {}).yfz or 1
                        tianfu_trigger_skill.yfz(player1, player, q)
                    end
                end
            end
        end
    end

    -- 处理集卡天赋的鱼计数
    if item.name == 'raw-fish' and learned.jika == true then
        -- 初始化玩家的鱼计数
        if not this.fish_count[player.index] then
            this.fish_count[player.index] = 0
        end
        -- 增加鱼使用计数
        this.fish_count[player.index] = this.fish_count[player.index] + 1

        -- 检查是否达到抽奖条件（每1200条鱼）
        if this.fish_count[player.index] >= 1200 then
                -- 执行抽奖
                tianfu_trigger_skill.jika(player, q_table.jika or 1)
                -- 重置计数
                this.fish_count[player.index] = 0
            end
    end

    -- 检查是否学习了鱼宝宝天赋
    if item.name == 'raw-fish' and learned.yubaobao == true then
        tianfu_trigger_skill.yubaobao(player, q_table.yubaobao or 1)
    end

    -- 检查是否学习了喂养天赋
    if item.name == 'raw-fish' and learned.weiyang == true then
        tianfu_trigger_skill.weiyang(event,player, q_table.weiyang or 1)
    end

    -- 检查是否学习了闪电五连鞭天赋
    if item.name == 'raw-fish' and learned.shandianwulianbian == true then
        tianfu_trigger_skill.shandianwulianbian(player, q_table.shandianwulianbian or 1)
    end

    -- 检查是否学习了成双成对天赋
    if learned.chengshuangchengdui == true then
        -- 检查是否是剧毒胶囊或减速胶囊
        if item.name == 'poison-capsule' or item.name == 'slowdown-capsule' then
            tianfu_trigger_skill.chengshuangchengdui(player, event.position, item.name, q_table.chengshuangchengdui or 1)
        end
    end
end

local function on_player_died(event)
    local player = game.players[event.player_index]
    local cause = event.cause
    if cause then
        if cause.valid then

        end
    end

    -- 副本隔离：副本玩家死亡不触发其他玩家的复仇类天赋（fcz/tjjz/dijiaojiaotu）
    -- 仅主世界玩家才会响应主世界玩家的死亡事件
    if player.force.name ~= 'player' then return end

    -- ★ 方案 B：3 个天赋分别倒排索引遍历（原全玩家扫描 + 每玩家 3 次 have_learn）
    local this = TPT.get()
    local main_table = WPT.get()
    local q_all = main_table.skill
    local enabled_all = main_table.tianfu_enabled
    local owners_all = this.skill_owners or {}

    -- fcz
    local owners_fcz = owners_all.fcz
    if owners_fcz then
        for player_index, _ in pairs(owners_fcz) do
            local player1 = game.players[player_index]
            if player1 and player1.valid and player1.connected and player1.force.name == 'player' then
                local learned1 = enabled_all[player_index] or {}
                if learned1.fcz == true then
                    local q = (q_all[player1.name] or {}).fcz or 1
                    tianfu_trigger_skill.fcz(player1, q)
                end
            end
        end
    end

    -- tjjz
    local owners_tjjz = owners_all.tjjz
    if owners_tjjz then
        for player_index, _ in pairs(owners_tjjz) do
            local player1 = game.players[player_index]
            if player1 and player1.valid and player1.connected and player1.force.name == 'player' then
                local learned1 = enabled_all[player_index] or {}
                if learned1.tjjz == true then
                    local q = (q_all[player1.name] or {}).tjjz or 1
                    tianfu_trigger_skill.tjjz(player1, q)
                end
            end
        end
    end

    -- dijiaojiaotu
    local owners_djjt = owners_all.dijiaojiaotu
    if owners_djjt then
        for player_index, _ in pairs(owners_djjt) do
            local player1 = game.players[player_index]
            if player1 and player1.valid and player1.connected and player1.force.name == 'player' then
                local learned1 = enabled_all[player_index] or {}
                if learned1.dijiaojiaotu == true then
                    local q = (q_all[player1.name] or {}).dijiaojiaotu or 1
                    tianfu_trigger_skill.dijiaojiaotu(player1, { player = player }, q)
                end
            end
        end
    end
end

local function on_player_built_entity(event)
    local entity = event.entity

    if not entity then
        return
    end
    if not entity.valid then
        return
    end

    local player = game.players[event.player_index]

    if not player then
        return
    end
end

local function on_entity_died(event)
    local this = TPT.get()
    if not event.entity then
        return
    end
    if not event.entity.valid then
        return
    end
    -- 注：gun-turret 空循环已删除（原 for 循环体为空，纯死代码）
    if event.entity.name == 'gun-turret' and event.entity.force == game.forces.player then
        return
    end

    if not event.cause then
        return
    end
    if not event.cause.valid then
        return
    end

    if not event.entity.valid then
        return
    end
    if event.entity.force ~= game.forces.enemy then
        return
    end

    -- 1000波以后特殊的DEBUFF处理
    local wave_number = WD.get('wave_number')
    if wave_number >= 1000 and event.cause.name == 'character' then
        local player = event.cause.player
        if player and player.valid then
            -- 检查是否击杀了虫巢或沙虫
            local spawner_names = {
                ['biter-spawner'] = true,
                ['spitter-spawner'] = true,
                ['small-worm-turret'] = true,
                ['medium-worm-turret'] = true,
                ['big-worm-turret'] = true,
                ['behemoth-worm-turret'] = true
            }

            if spawner_names[event.entity.name] then
                -- 减速贴纸：source(虫巢) 与 target(玩家角色) 必须在同一表面，
                -- 否则 create_entity 会报 "belongs to surface X but surface Y was expected" 崩溃。
                -- 以虫巢所在表面为创建表面，并校验玩家角色在同一表面后才施加。
                local spawner = event.entity
                if player.character and player.character.valid and player.character.surface == spawner.surface then
                    local surface = spawner.surface
                    if surface and surface.valid then
                        surface.create_entity({
                            name = 'demolisher-ash-sticker',
                            position = spawner.position,
                            source = spawner,
                            target = player.character,
                            force = 'enemy',
                        })
                    end
                end
            end


        end
    end

    -- 检查是否是战斗无人机杀死的敌人
    if event.cause.type == 'combat-robot' and event.cause.force == game.forces.player then
        local player = event.cause.last_user
        if player then
            -- ★ 方案 A：local 缓存
            local main_table = WPT.get()
            local learned = main_table.tianfu_enabled[player.index] or {}
            local q_table = main_table.skill[player.name] or {}

            if learned.jingzhunzhidao == true then
                -- 5%的概率触发天赋
                if math.random(1, 100) <= 5 then
                    tianfu_trigger_skill.jingzhunzhidao(player, event.cause, q_table.jingzhunzhidao or 1)
                end
            end

            if learned.lianhejuntuan == true then
                -- 2%的概率触发联合军团天赋
                if math.random(1, 100) <= 2 then
                    tianfu_trigger_skill.lianhejuntuan(player, q_table.lianhejuntuan or 1)
                end
            end

            if learned.peishentuanyuan == true then
                -- 0.5%的概率触发陪审团天赋
                if math.random(1, 200) <= 1 then
                    tianfu_trigger_skill.peishentuanyuan(player, event.entity, q_table.peishentuanyuan or 1)
                end
            end
        end
    end

    local turret_types = {
        ['ammo-turret'] = true,
        ['electric-turret'] = true,
        ['fluid-turret'] = true
    }

    if turret_types[event.cause.type] and event.cause.force == game.forces.player then
        -- ★ 方案 B：dgjx 倒排索引遍历（原全玩家扫描）
        local main_table = WPT.get()
        local q_all = main_table.skill
        local enabled_all = main_table.tianfu_enabled
        local owners = this.skill_owners and this.skill_owners['dgjx']
        if owners then
            for player_index, _ in pairs(owners) do
                local player1 = game.players[player_index]
                if player1 and player1.valid and player1.connected and player1.force.name == 'player' then
                    local learned1 = enabled_all[player_index] or {}
                    if learned1.dgjx == true then
                        local q = (q_all[player1.name] or {}).dgjx or 1
                        tianfu_trigger_skill.dgjx(player1, q)
                    end
                end
            end
        end

        return
    end

    --如果是玩家杀死的敌人
    if event.cause.name == 'character' then
        local player = event.cause.player
        local entity = event.entity

        if player and player.valid then
            -- ★ 方案 A：local 缓存
            local main_table = WPT.get()
            local learned = main_table.tianfu_enabled[player.index] or {}
            local q_table = main_table.skill[player.name] or {}

            if learned.youxia == true then
                tianfu_trigger_skill.youxia(player, entity, q_table.youxia or 1)
            end

            if event.damage_type then
                if learned.yinxuejian == true and event.damage_type.name == 'physical' then
                    tianfu_trigger_skill.yinxuejian(player, q_table.yinxuejian or 1)
                end
                if learned.baot == true and event.damage_type.name == 'physical' then
                    tianfu_trigger_skill.baot(player, entity, q_table.baot or 1)
                end
                -- 破阵霸王枪天赋触发：物理伤害击杀
                if learned.pochen_bawangqiang == true and event.damage_type.name == 'physical' then
                    tianfu_trigger_skill.pochen_bawangqiang(player, entity, q_table.pochen_bawangqiang or 1)
                end
            end
            if learned.sangjin == true then
                tianfu_trigger_skill.sangjin(player, entity, q_table.sangjin or 1)
            end
            if learned.zg == true then
                tianfu_trigger_skill.zg(player, q_table.zg or 1)
            end
            if learned.xixue == true then
                tianfu_trigger_skill.xixue(player, q_table.xixue or 1)
            end
            if learned.shalujingyan == true then
                tianfu_trigger_skill.shalujingyan(player, entity, q_table.shalujingyan or 1)
            end
            if learned.sgj == true then
                tianfu_trigger_skill.sgj(player, q_table.sgj or 1)
            end
            if learned.sxf == true then
                tianfu_trigger_skill.sxf(player, q_table.sxf or 1)
            end

            if learned.tuks == true then
                tianfu_trigger_skill.tuks(player, entity, q_table.tuks or 1)
            end

            -- 顶级掠食者天赋触发
            if learned.dingjilueshizhe == true then
                tianfu_trigger_skill.dingjilueshizhe(player, entity, q_table.dingjilueshizhe or 1)
            end

            -- 噬魔者天赋触发
            if learned.shimozhe == true then
                tianfu_trigger_skill.shimozhe(player, q_table.shimozhe or 1)
            end

            -- 炎魔天赋触发
            if learned.yanmo == true then
                tianfu_trigger_skill.yanmo(player, entity, q_table.yanmo or 1)
            end

            -- 裁决者天赋触发
            if learned.caijuezhe == true then
                tianfu_trigger_skill.caijuezhe(player, entity, q_table.caijuezhe or 1)
            end

            -- 越杀越多天赋
            if learned.yueshayueduo == true then
                tianfu_trigger_skill.yueshayueduo(player, entity, q_table.yueshayueduo or 1)
            end

            -- 亡灵大军天赋触发
            -- if learned.wanglingdajun == true then
            --     tianfu_trigger_skill.wanglingdajun(player, entity)
            -- end

            -- 五行诀天赋触发
            if learned.wuxingjue == true then
                tianfu_trigger_skill.wuxingjue(player, {entity = entity}, q_table.wuxingjue or 1)
            end

            -- 封印卷轴天赋触发
            if learned.fengyinjuanzhou == true then
                tianfu_trigger_skill.fengyinjuanzhou(player, {entity = entity}, q_table.fengyinjuanzhou or 1)
            end

            -- 收缴武器天赋
            if learned.shoujiao_wuqi == true then
                -- 1.5%的概率触发收缴武器天赋
                if math.random(1, 200) <= 3 then
                    tianfu_trigger_skill.shoujiao_wuqi(player, event.entity, q_table.shoujiao_wuqi or 1)
                end
            end

        end

        return
    end
end


-- 附魔虫子的攻击逻辑
local function fumo_biter_attack_logic(event)    
    local this = TPT.get()
    local attacker = event.cause
    
    -- 检查攻击者是否有效
    if not attacker or not attacker.valid then
        return
    end
    
    -- 检查攻击者是否是附魔虫子
    local owner_player_index = this.fumo_biter_to_player[attacker.unit_number]
    if not owner_player_index then
        return
    end
    
    local owner_player = game.players[owner_player_index]
    
    if not owner_player then
        return
    end
    
    -- 获取玩家当前法力值
    local rpg_t = rpgtable.get('rpg_t')
    local current_mana = rpg_t[owner_player.index].mana or 0
    
    if current_mana <= 0 then
        return
    end
    
    -- 计算要消耗的法力值（10%当前法力）
    local mana_consumption = math.floor(current_mana * 0.1)
    
    if mana_consumption <= 0 then
        return
    end
    
    -- 消耗法力值
    rpg_t[owner_player.index].mana = current_mana - mana_consumption
    
    -- 计算伤害（消耗法力 * 5）
    local area_damage = mana_consumption * 4
    
    -- 造成范围伤害
    local surface = event.entity.surface
    local position = event.entity.position
    local radius = 3  -- 小范围伤害
    
    local goal = {'unit', 'turret', 'unit-spawner','spider-leg','combat-robot','spider-unit'}
    
    for _, target in pairs(surface.find_entities_filtered({
        area = { { position.x - radius, position.y - radius }, { position.x + radius, position.y + radius } },
        force = game.forces.enemy,
        type = goal
    })) do
        if target.valid and target.health then
            local distance = math.sqrt((target.position.x - position.x) ^ 2 + (target.position.y - position.y) ^ 2)
            if distance <= radius then
                local damage_multiplier = 1 - distance / radius
                local final_damage = area_damage * damage_multiplier
               
                if final_damage > 0 then
                    target.damage(final_damage, 'player', 'explosion', owner_player.character)
                end
            end
        end
    end
    
    -- 显示法力消耗的飞行文本
    if owner_player.valid then
        owner_player.create_local_flying_text({
            text = '-' .. mana_consumption .. ' Mana',
            position = { x = owner_player.physical_position.x, y = owner_player.physical_position.y - 2 },
            color = { r = 0.3, g = 0.5, b = 1.0 },
            time_to_live = 120,
            speed = 0.8
        })
    end
end

local function on_tick_shengguangzhongji()
    local rpg_t = rpgtable.get('rpg_t')
    local this = TPT.get()
    local main_table = WPT.get()
    local owners = this.skill_owners or {}

    -- ★ 方案 D：4 个相关天赋的 owner 集合（local 引用，避免循环内重复查表）
    local gongshengti_owners = owners.gongshengti
    local mijingzhang_owners = owners.mijingzhang
    local shengguangzhongji_owners = owners.shengguangzhongji
    local shuangrenjian_owners = owners.shuangrenjian

    -- ★ 全服短路：4 个天赋都没人学 → 直接返回，0 次 find_entities_filtered
    if not gongshengti_owners and not mijingzhang_owners
       and not shengguangzhongji_owners and not shuangrenjian_owners then
        return
    end

    local q_all = main_table.skill
    local enabled_all = main_table.tianfu_enabled

    for _, player in pairs(game.connected_players) do
        if not player.valid or not player.character or not player.character.valid
           or player.force.name ~= 'player' then
            goto continue
        end

        local pidx = player.index

        -- ★ 玩家级快速过滤：4 个天赋都没学 → 直接跳过
        local has_gst = gongshengti_owners and gongshengti_owners[pidx]
        local has_mjz = mijingzhang_owners and mijingzhang_owners[pidx]
        local has_sgzj = shengguangzhongji_owners and shengguangzhongji_owners[pidx]
        local has_srj = shuangrenjian_owners and shuangrenjian_owners[pidx]
        if not (has_gst or has_mjz or has_sgzj or has_srj) then
            goto continue
        end

        local q_table = q_all[player.name] or {}
        local learned = enabled_all[pidx] or {}
        -- 再次校验"启用"状态（owners 只表示学过，不区分启用/禁用）
        if has_gst and learned.gongshengti ~= true then has_gst = false end
        if has_mjz and learned.mijingzhang ~= true then has_mjz = false end
        if has_sgzj and learned.shengguangzhongji ~= true then has_sgzj = false end
        if has_srj and learned.shuangrenjian ~= true then has_srj = false end
        if not (has_gst or has_mjz or has_sgzj or has_srj) then
            goto continue
        end

        local cause = player.character
        local inv_ammo = cause.get_inventory(defines.inventory.character_ammo)
        local inv_gun = cause.get_inventory(defines.inventory.character_guns)
        local idx = cause.selected_gun_index
        local surface = cause.surface
        local position = cause.position
        local goal = {'unit', 'turret', 'unit-spawner', 'spider-leg', 'combat-robot', 'spider-unit'}

        local enemies
        local sousuo = false

        -- 共生体分支（只在玩家学过时才搜敌军）
        if has_gst then
            local gq = q_table.gongshengti or 1
            local eff = ({0.5, 0.6, 0.7, 0.8, 0.9})[gq]  -- 品质5=90%效率
            enemies = surface.find_entities_filtered({
                area = { { position.x - 2, position.y - 2 }, { position.x + 2, position.y + 2 } },
                force = game.forces.enemy,
                type = goal
            })
            sousuo = true
            if #enemies > 0 then
                local random_index = math.random(1, #enemies)
                local target_entity = enemies[random_index]

                if target_entity.valid and target_entity.health then
                    local strength = rpg_t[cause.player.index].strength
                    deal_damage_with_floating_text(target_entity, player, (strength/2) * eff, 'physical')
                end
            end

            cause.health = cause.health + (rpg_t[cause.player.index].vitality - 10) * 0.3 * eff
        end

        if has_mjz then
            tianfu_trigger_skill.mijingzhang(player, q_table.mijingzhang or 1)
        end

        if inv_ammo[idx].valid_for_read and inv_gun[idx].valid_for_read then
            goto continue
        end

        if not sousuo and (has_sgzj or has_srj) then
            enemies = surface.find_entities_filtered({
                area = { { position.x - 2, position.y - 2 }, { position.x + 2, position.y + 2 } },
                force = game.forces.enemy,
                type = goal
            })
        end

        if has_sgzj then
            tianfu_trigger_skill.shengguangzhongji(player, q_table.shengguangzhongji or 1)
        end

        if not enemies or #enemies == 0 then
            goto continue
        end

        if has_srj and #enemies >= 2 then
            if tianfu_trigger_skill.shuangrenjian(player, enemies, q_table.shuangrenjian or 1) then
                goto continue
            end
        end

        cause.health = cause.health + (rpg_t[cause.player.index].vitality - 10) * 0.3

        local random_index = math.random(1, #enemies)
        local target_entity = enemies[random_index]

        if not target_entity.valid or not target_entity.health then
            goto continue
        end

        if target_entity.valid then
            local strength = rpg_t[cause.player.index].strength
            deal_damage_with_floating_text(target_entity, player, strength/2-10, 'physical')
        end

        ::continue::
    end
end

local function on_entity_damaged(event)
    -- 1. 极其快速的初步过滤

    local entity = event.entity
    if not entity or not entity.valid then return end
    local cause = event.cause
    local entity_force = entity.force
    local player_force = game.forces.player -- 预置引用提高效率

    
    
    -- 2. 处理阵营保护逻辑 (神赐之手)
    -- 仅当受伤者是玩家阵营时才遍历激活状态，减少 90% 的无效循环
    if entity_force == player_force then
        local this = TPT.get()
        local active_skills = this.shencizhishou_active
        if active_skills then
            local current_tick = game.tick
            for _, data in pairs(active_skills) do
                if data and data.end_tick and current_tick < data.end_tick then
                    entity.health = entity.max_health
                    return -- 如果已经无敌，直接返回，不再计算后续受伤逻辑
                end
            end
        end
    end



    -- 3. 受伤者逻辑 (玩家受击)
    local entity_name = entity.name
    if entity_name ~= 'character' then
return
     end
        local player = entity.player
        if player then
            -- 副本隔离：副本玩家受伤不触发主世界防御类天赋
            if player.force.name ~= 'player' then return end
            -- ★ 方案 A：local 缓存
            local main_table = WPT.get()
            local learned = main_table.tianfu_enabled[player.index] or {}
            local q_table = main_table.skill[player.name] or {}

            if learned.yinxuejian == true then yinxuejian_shield(event) end
            if learned.hushenfu == true then hushenfu_shield(event) end
            if learned.smmf == true then tianfu_trigger_skill.smmf(player, event, q_table.smmf or 1) end
            if learned.shui_hu_fu == true then tianfu_trigger_skill.shui_hu_fu(player, nil, q_table.shui_hu_fu or 1) end
            if learned.hkzy == true then tianfu_trigger_skill.hkzy(player, event, q_table.hkzy or 1) end
            if learned.tishenshu == true then tianfu_trigger_skill.tishenshu(player, event, q_table.tishenshu or 1) end
            if learned.xuebao == true then tianfu_trigger_skill.xuebao(player, event, q_table.xuebao or 1) end
        end

end



local function on_player_gun_inventory_changed(event)
    local player = game.players[event.player_index]
    -- 副本隔离：副本玩家枪栏变化不触发皇帝天赋
    if player.force.name ~= 'player' then return end
    -- ★ 方案 A：local 缓存
    local main_table = WPT.get()
    local learned = main_table.tianfu_enabled[player.index] or {}
    if learned.hd == true then
        local something = player.get_inventory(defines.inventory.character_guns)
        -- 检查inventory是否存在且有效
        if not something then
            return
        end
        for _, item_data in pairs(something.get_contents()) do
            player.remove_item {
                name = item_data.name,
                count = item_data.count,
                quality = item_data.quality
            }
        end
    end
end

local function on_research_finished(event)
    if event.research.force.index ~= game.forces.player.index then
        return
    end
    -- ★ 方案 B：3 个天赋分别倒排索引遍历（原全玩家扫描 + 每玩家 3 次 have_learn）
    local this = TPT.get()
    local main_table = WPT.get()
    local q_all = main_table.skill
    local enabled_all = main_table.tianfu_enabled
    local owners_all = this.skill_owners or {}

    -- xueshu
    local owners_xueshu = owners_all.xueshu
    if owners_xueshu then
        for player_index, _ in pairs(owners_xueshu) do
            local player = game.players[player_index]
            if player and player.valid and player.connected and player.force.name == 'player' then
                local learned = enabled_all[player_index] or {}
                if learned.xueshu == true then
                    local q = (q_all[player.name] or {}).xueshu or 1
                    tianfu_trigger_skill.xueshu(player, q)
                end
            end
        end
    end

    -- kxj
    local owners_kxj = owners_all.kxj
    if owners_kxj then
        for player_index, _ in pairs(owners_kxj) do
            local player = game.players[player_index]
            if player and player.valid and player.connected and player.force.name == 'player' then
                local learned = enabled_all[player_index] or {}
                if learned.kxj == true then
                    local q = (q_all[player.name] or {}).kxj or 1
                    tianfu_trigger_skill.kxj(player, q)
                end
            end
        end
    end

    -- qykj
    local owners_qykj = owners_all.qykj
    if owners_qykj then
        for player_index, _ in pairs(owners_qykj) do
            local player = game.players[player_index]
            if player and player.valid and player.connected and player.force.name == 'player' then
                local learned = enabled_all[player_index] or {}
                if learned.qykj == true then
                    local q = (q_all[player.name] or {}).qykj or 1
                    tianfu_trigger_skill.qykj(player, q)
                end
            end
        end
    end
end

-- ★ 方案 C：on_nth_tick(3) → on_nth_tick(1)
-- 每 tick 查 due_buckets[current_tick]，无桶立即返回（O(1) 查表，无函数调用开销）
-- choise_skill 逻辑内部仍每 3 tick 跑一次（用 current_tick % 3 == 0 控制）
Event.on_nth_tick(1, on_tick)
Event.on_nth_tick(40, on_tick_shengguangzhongji)
Event.on_nth_tick(60*10, on_tick_learn_skill)  -- 每30秒执行一次学习新天赋逻辑
Event.add(defines.events.on_player_joined_game, on_player_joined_game)
Event.add(defines.events.on_pre_player_died, on_pre_player_died)
Event.add(defines.events.on_player_mined_entity, on_player_mined_entity,{
    {filter = "type", type = 'simple-entity'},
    {filter = "type", type = 'linked-chest'},
    {filter = "type", type = 'container'},
    {filter = "type", type = 'logistic-container'},
    {filter = "type", type = 'car'},
    
    {filter = "type", type = 'artillery-wagon'},
    {filter = "type", type = 'artillery-turret'},
    {filter = "type", type = 'land-mine'},
    {filter = "type", type = 'spider-vehicle'},
    {filter = "type", type = 'ammo-turret'},
    {filter = "type", type = 'electric-turret'},
    {filter = "type", type = 'fluid-turret'},
	{filter = "type", type = 'tree'}
})
Event.add(defines.events.on_player_used_capsule, Public.on_player_used_capsule)
Event.add(defines.events.on_research_finished, on_research_finished)
Event.add(defines.events.on_player_gun_inventory_changed, on_player_gun_inventory_changed)
Event.add(defines.events.on_player_died, on_player_died)
Event.add(defines.events.on_entity_damaged, on_entity_damaged, {
    {filter = "type", type = 'character'}, 
    {filter = "type", type = 'electric-turret'}
    })
Event.add(defines.events.on_entity_died, on_entity_died)

-- 添加testzhiye命令，用于检查天赋分类情况
commands.add_command('testzhiye', '检查未分类的天赋', function(event)
    if not event.player_index then
        return
    end

    local player = game.players[event.player_index]
    local unclassified_skills = {}

    -- 创建已分类天赋的查找表
    local classified_skills = {}
    for category_name, skills in pairs(tianfu_categories) do
        for _, skill_id in pairs(skills) do
            classified_skills[skill_id] = true
        end
    end

    -- 检查time_skills中的天赋
    for skill_id, _ in pairs(tianfu_time_skill.time_skills) do
        if not classified_skills[skill_id] then
            table.insert(unclassified_skills, skill_id)
        end
    end

    -- 检查once_skills中的天赋
    for skill_id, _ in pairs(tianfu_once_skill.once_skills) do
        if not classified_skills[skill_id] then
            table.insert(unclassified_skills, skill_id)
        end
    end

    -- 检查trigger_skills中的天赋
    for skill_id, _ in pairs(trigger_skills) do
        if not classified_skills[skill_id] then
            table.insert(unclassified_skills, skill_id)
        end
    end

    -- 输出结果
    if #unclassified_skills > 0 then
        player.print('未分类的天赋:')
        for _, skill_id in pairs(unclassified_skills) do
            player.print('- ' .. skill_id)
        end
        player.print('总共找到 ' .. #unclassified_skills .. ' 个未分类的天赋')
    else
        player.print('所有天赋都已正确分类！')
    end
end)

-- 添加check_missing_skills命令，用于查找在分类表中存在但实际天赋表中不存在的天赋
commands.add_command('check_missing_skills', '查找在分类表中存在但实际天赋表中不存在的天赋', function(event)
    if not event.player_index then
        return
    end

    local player = game.players[event.player_index]
    local missing_skills = {}

    -- 创建实际天赋表的查找表
    local actual_skills = {}
    -- 添加time_skills中的天赋
    for skill_id, _ in pairs(tianfu_time_skill.time_skills) do
        actual_skills[skill_id] = true
    end
    -- 添加once_skills中的天赋
    for skill_id, _ in pairs(tianfu_once_skill.once_skills) do
        actual_skills[skill_id] = true
    end
    -- 添加trigger_skills中的天赋
    for skill_id, _ in pairs(trigger_skills) do
        actual_skills[skill_id] = true
    end

    -- 检查分类表中的天赋是否存在于实际天赋表中
    for category_name, skills in pairs(tianfu_categories) do
        for _, skill_id in pairs(skills) do
            if not actual_skills[skill_id] then
                table.insert(missing_skills, { id = skill_id, category = category_name })
            end
        end
    end

    -- 输出结果
    if #missing_skills > 0 then
        player.print('在分类表中存在但实际天赋表中不存在的天赋:')
        for _, skill_info in pairs(missing_skills) do
            player.print('- ' .. skill_info.id .. ' (分类: ' .. skill_info.category .. ')')
        end
        player.print('总共找到 ' .. #missing_skills .. ' 个不存在的天赋')
    else
        player.print('所有分类表中的天赋都存在于实际天赋表中！')
    end
end)


local function on_player_crafted_item(event)
    local player = game.players[event.player_index]
    if not player or not player.valid then
        return
    end

    -- 副本隔离：副本玩家手搓物品不触发主世界天赋
    if player.force.name ~= 'player' then return end

    -- ★ 方案 A：local 缓存
    local main_table = WPT.get()
    local learned = main_table.tianfu_enabled[player.index] or {}
    local q_table = main_table.skill[player.name] or {}

    -- 检查是否学习了手搓的神天赋
    if learned.shoucuo_de_shen == true then
        tianfu_trigger_skill.shoucuo_de_shen(player, event, q_table.shoucuo_de_shen or 1)
    end

    -- 检查是否学习了手艺人天赋
    if learned.shouyiren == true then
        tianfu_trigger_skill.shouyiren(player, event, q_table.shouyiren or 1)
    end


end


Event.add(defines.events.on_player_crafted_item, on_player_crafted_item)

local function on_player_deconstructed_area(event)
    local player = game.players[event.player_index]
    if not player or not player.valid then
        return
    end

    -- 副本隔离：副本玩家红图操作不触发主世界天赋
    if player.force.name ~= 'player' then return end

    -- ★ 方案 A：local 缓存
    local main_table = WPT.get()
    local learned = main_table.tianfu_enabled[player.index] or {}
    local q_table = main_table.skill[player.name] or {}

    -- 检查是否学习了红图抹杀天赋
    if learned.htms == true then
        tianfu_trigger_skill.htms(player,event, q_table.htms or 1)

    end

    -- 检查是否学习了召唤空袭天赋
    if learned.zhaohuan_kongxi == true then
        tianfu_trigger_skill.zhaohuan_kongxi(player,event, q_table.zhaohuan_kongxi or 1)

    end

    -- 检查是否学习了神赐之手天赋
    if learned.shencizhishou == true then
        tianfu_trigger_skill.shencizhishou(player, event, q_table.shencizhishou or 1)
    end

end

Event.add(defines.events.on_player_deconstructed_area, on_player_deconstructed_area)

return Public
