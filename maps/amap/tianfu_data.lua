-- tianfu_data.lua
-- 天赋静态数据表（从 tianfu.lua 抽取）：tianfu_categories 职业分类表 + tianfu_icons 图标映射表

local Data = {}

Data.tianfu_categories = {
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
        'sxf',             -- 失心疯
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

Data.tianfu_icons = {
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
    ['sxf'] = 'item/exoskeleton-equipment',                     -- 失心疯（+敏捷）
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

return Data
