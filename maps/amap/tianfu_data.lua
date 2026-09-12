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
        -- T3-B 新卡（法师）
        'wangzhezhengmu',  -- 亡者征募
        'fenshenmifa',     -- 焚身秘法
        'yuxunqi',         -- 渔汛期
        'lianjinpeidui',   -- 炼金配对
        'shifutilian',     -- 食腐提炼
        'guzhuyizhi',      -- 孤注一掷
        'huixiang',        -- 回响
        'chaopindianwang', -- 超频电网
        'qiling',          -- 起灵
        'zhuanyun',        -- 转运
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
        -- T3-B 新卡（建造者）
        'chezaiduannpeng', -- 车载暖棚
        'xuefuwuche',      -- 学富五车
        'qianchuanguihai', -- 千川归海
        'tianshitouzi',    -- 天使投资
        'zhuleishu',       -- 筑垒术
        'gongbingcanmou',  -- 工兵参谋
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
        -- T3-B 新卡（战士）
        'xuexijinjie',     -- 学习进阶
        'luoduozhexuemai', -- 掠夺者血脉
        'bujiezhiqu',      -- 不竭之躯
        'juntuanhaoling',  -- 军团号令
        'yinglingwange',   -- 英灵挽歌
        'shoujijigong',    -- 首级记功
        'lianzhanlianjie', -- 连战连捷
        'xiechoubaoku',    -- 血酬宝库
        'yichanzhixingren',-- 遗产执行人
        'zhandibilei',     -- 战地壁垒
        'taitanzhiqu',     -- 泰坦之躯
        'huoshuidongyin',  -- 祸水东引
        'jixieshi',        -- 机械师
        'zhandibuju',      -- 战地补给
        'liansuofanying',  -- 连锁反应
        'faxinri',         -- 发薪日
        'qiushengbenneng', -- 求生本能
        'dgzg',            -- 帝国战歌（T3-B1 补注册）
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
    ['yl'] = 'file/png/tianfu/yl.png',                  -- 鱼灵
    ['yubaobao'] = 'file/png/tianfu/yubaobao.png',                -- 鱼宝宝
    ['fish'] = 'file/png/tianfu/fish.png',                    -- 钓鱼佬
    ['yuer'] = 'file/png/tianfu/yuer.png',                    -- 鱼饵
    ['xybg'] = 'file/png/tianfu/xybg.png',                    -- 小鱼饼干
    ['mijingzhang'] = 'file/png/tianfu/mijingzhang.png',             -- 魔晶杖
    -- T3F-1：原 'item/steel-axe' 已失效——2.0 移除钢斧物品（真实客户端 Unknown sprite），
    -- 近战/攻击卡统一改用有效战斗图标（与抽卡卡面 get_tianfu_icon 同源呈现）。
    ['juqichengjian'] = 'file/png/tianfu/juqichengjian.png',             -- 聚气成剑
    ['smmf'] = 'file/png/tianfu/smmf.png',     -- 魔法盾
    ['mlzq'] = 'file/png/tianfu/mlzq.png',                      -- 魔力之泉
    ['morefali'] = 'file/png/tianfu/morefali.png',                  -- 备用法力瓶
    ['mlst'] = 'file/png/tianfu/mlst.png',                      -- 魔力升腾
    ['kls'] = 'file/png/tianfu/kls.png',                    -- 傀儡师
    ['mfxt'] = 'file/png/tianfu/mfxt.png',                   -- 魔法学徒
    ['wlfs'] = 'file/png/tianfu/wlfs.png',                   -- 亡灵法师
    ['zhs'] = 'file/png/tianfu/zhs.png',                    -- 黑暗召唤
    ['bei_dong_zhao_huan'] = 'file/png/tianfu/bei_dong_zhao_huan.png', -- 被动召唤（召唤虫子宠物）
    ['tieshenhuwei'] = 'file/png/tianfu/tieshenhuwei.png',           -- 贴身护卫
    ['tls'] = 'file/png/tianfu/tls.png',               -- 通灵术
    ['dijiaojiaotu'] = 'file/png/tianfu/dijiaojiaotu.png',      -- 低阶教徒
    ['mzqz'] = 'file/png/tianfu/mzqz.png',                   -- 魔杖窃贼
    ['fali'] = 'file/png/tianfu/fali.png',                  -- 法力光环（回法力）
    ['jifengbu'] = 'file/png/tianfu/jifengbu.png',    -- 疾风步
    ['yjjn'] = 'file/png/tianfu/yjjn.png',    -- 应急胶囊
    ['leitingwanjun'] = 'file/png/tianfu/leitingwanjun.png', -- 雷霆万钧
    ['shandianwulianbian'] = 'file/png/tianfu/shandianwulianbian.png', -- 闪电五连鞭（闪电链）
    ['cjs'] = 'file/png/tianfu/cjs.png',                      -- 传教士（给魔力）
    ['yfz'] = 'file/png/tianfu/yfz.png',                          -- 鱼贩子
    ['hyll'] = 'file/png/tianfu/hyll.png',                         -- 好运连连
    ['jika'] = 'file/png/tianfu/jika.png',                         -- 集卡
    ['smlw'] = 'file/png/tianfu/smlw.png',                         -- 神秘礼物
    ['zhuoshao'] = 'file/png/tianfu/zhuoshao.png',        -- 灼烧
    ['tianzhao'] = 'file/png/tianfu/tianzhao.png',          -- 天照
    ['diyu_rongyan'] = 'file/png/tianfu/diyu_rongyan.png',    -- 地狱熔岩
    ['yanmo'] = 'file/png/tianfu/yanmo.png',           -- 炎魔
    ['chuanqibaozang'] = 'file/png/tianfu/chuanqibaozang.png',        -- 传说宝藏
    ['shen_fa'] = 'file/png/tianfu/shen_fa.png', -- 神罚
    ['shimozhe'] = 'file/png/tianfu/shimozhe.png',               -- 噬魔者
    ['mdt'] = 'file/png/tianfu/mdt.png',               -- 魔盗团
    ['shalujingyan'] = 'file/png/tianfu/shalujingyan.png',     -- 杀戮经验
    ['falibiqu'] = 'file/png/tianfu/falibiqu.png',               -- 法力汲取
    ['xxyd'] = 'file/png/tianfu/xxyd.png',                      -- 鲜血涌动
    ['xxzb'] = 'file/png/tianfu/xxzb.png',                  -- 鲜血之杯（回法力）
    ['shui_hu_fu'] = 'file/png/tianfu/shui_hu_fu.png',                   -- 水护符
    ['shui_dun'] = 'file/png/tianfu/shui_dun.png',                      -- 水遁
    ['tishenshu'] = 'file/png/tianfu/tishenshu.png', -- 替身术
    ['fengyinjuanzhou'] = 'file/png/tianfu/fengyinjuanzhou.png',        -- 封印卷轴
    ['wuxingjue'] = 'file/png/tianfu/wuxingjue.png',          -- 五行诀
    ['htms'] = 'file/png/tianfu/htms.png',       -- 红图抹杀

    -- 建造者类（builder）
    ['fuzhushou'] = 'file/png/tianfu/fuzhushou.png',      -- 辅助手（自动建设机械臂等）
    ['gcd'] = 'file/png/tianfu/gcd.png',                -- 工程队
    ['keyan'] = 'file/png/tianfu/keyan.png',                       -- 科研人员
    ['kytd'] = 'file/png/tianfu/kytd.png',                        -- 科研团队
    ['kxj'] = 'file/png/tianfu/kxj.png',                         -- 科学家
    ['yanfayanjiuzhongxin'] = 'file/png/tianfu/yanfayanjiuzhongxin.png',         -- 研发中心
    ['bpz'] = 'file/png/tianfu/bpz.png',        -- 奔跑者
    ['fangshou'] = 'file/png/tianfu/fangshou.png',             -- 城防建设者
    ['jiguang'] = 'file/png/tianfu/jiguang.png',            -- 激光炮塔生产线
    ['dianluban'] = 'file/png/tianfu/dianluban.png',        -- 芯片工人
    ['djrc'] = 'file/png/tianfu/djrc.png',              -- 顶尖人才
    ['zishenzhuanjia'] = 'file/png/tianfu/zishenzhuanjia.png',    -- 资深专家
    ['kejigongsi'] = 'file/png/tianfu/kejigongsi.png',        -- 科技公司
    ['jxhx'] = 'file/png/tianfu/jxhx.png',              -- 机械核心
    ['dcrg'] = 'file/png/tianfu/dcrg.png',              -- 电磁干扰
    ['tjjz'] = 'file/png/tianfu/tjjz.png',              -- 机械装置
    ['bulider'] = 'file/png/tianfu/bulider.png',        -- 建筑师
    ['ycj'] = 'file/png/tianfu/ycj.png',                          -- 印钞机
    ['ftlt'] = 'file/png/tianfu/ftlt.png',                 -- 垃圾佬
    ['tann'] = 'file/png/tianfu/tann.png',                 -- 探囊
    ['jndd'] = 'file/png/tianfu/jndd.png',                   -- 江南大盗（偷金币）
    ['touqian'] = 'file/png/tianfu/touqian.png',                -- 机敏的小偷（偷金币）
    ['shoucuo_de_shen'] = 'file/png/tianfu/shoucuo_de_shen.png',        -- 手搓的神
    ['shouyiren'] = 'file/png/tianfu/shouyiren.png',              -- 手艺人
    ['xuetu'] = 'file/png/tianfu/xuetu.png',                  -- 学徒
    ['xueshu'] = 'file/png/tianfu/xueshu.png',            -- 学术剽窃
    ['junhuo'] = 'file/png/tianfu/junhuo.png',           -- 子弹工厂
    ['dgjx'] = 'file/png/tianfu/dgjx.png',             -- 帝国军饷（炮塔击杀得金币）
    ['mokuaizhuangjia'] = 'file/png/tianfu/mokuaizhuangjia.png',     -- 模块装甲
    ['jqrpu'] = 'file/png/tianfu/jqrpu.png',                    -- 机器人仆从
    ['gycs'] = 'file/png/tianfu/gycs.png',       -- 工业城市
    ['scmcc'] = 'file/png/tianfu/scmcc.png',       -- 深层采矿车
    ['gongchengche'] = 'file/png/tianfu/gongchengche.png',                  -- 工程车
    ['jiansheche'] = 'file/png/tianfu/jiansheche.png',                    -- 建设车（汽车自动建造）
    ['yelianche'] = 'file/png/tianfu/yelianche.png',                     -- 冶炼车（汽车冶炼）
    ['jidiche'] = 'file/png/tianfu/jidiche.png',                      -- 基地车
    ['beibaozhengli'] = 'file/png/tianfu/beibaozhengli.png',         -- 虚空物流协议
    ['haiguanfang'] = 'file/png/tianfu/haiguanfang.png',           -- 海关方（资源岛/市场）
    ['tesla_battery'] = 'file/png/tianfu/tesla_battery.png',         -- 特斯拉蓄电池
    ['small_buss'] = 'file/png/tianfu/small_buss.png',                   -- 小商人
    ['qiche_ren'] = 'file/png/tianfu/qiche_ren.png',                     -- 汽车人
    ['rsrl'] = 'file/png/tianfu/rsrl.png',                  -- 肉身熔炉
    ['sansan'] = 'file/png/tianfu/sansan.png',                -- 三三合成

    -- 战士类（fighter）
    ['shengguangzhongji'] = 'file/png/tianfu/shengguangzhongji.png',         -- 圣光重击
    ['gongshengti'] = 'file/png/tianfu/gongshengti.png',               -- 共生体
    ['hushenfu'] = 'file/png/tianfu/hushenfu.png',  -- 护身符
    ['chongfengxianzhen'] = 'file/png/tianfu/chongfengxianzhen.png', -- 冲锋陷阵
    ['jingzhunzhidao'] = 'file/png/tianfu/jingzhunzhidao.png', -- 精准制导（导弹）
    ['lianhejuntuan'] = 'file/png/tianfu/lianhejuntuan.png',          -- 联合军团
    ['xly'] = 'file/png/tianfu/xly.png',                  -- 新兵训练营
    ['mbz'] = 'file/png/tianfu/mbz.png',         -- 漫步者
    ['zdfs'] = 'file/png/tianfu/zdfs.png',                 -- 自动导弹发射器
    ['zdfs2'] = 'file/png/tianfu/zdfs2.png',                -- 自动导弹发射器2
    ['daodaoku'] = 'file/png/tianfu/daodaoku.png',          -- 导弹库
    ['jingong'] = 'file/png/tianfu/jingong.png',                 -- 进攻！战斗!
    ['genben'] = 'file/png/tianfu/genben.png',                 -- 小跟班
    ['sglz'] = 'file/png/tianfu/sglz.png',      -- 圣光礼赞
    ['xuebao'] = 'file/png/tianfu/xuebao.png',                  -- 血爆
    ['shoujiao_wuqi'] = 'file/png/tianfu/shoujiao_wuqi.png',             -- 收缴武器
    ['danmu_gongji'] = 'file/png/tianfu/danmu_gongji.png',       -- 弹幕攻击
    ['boom_player'] = 'file/png/tianfu/boom_player.png',               -- 炸弹人
    ['wjjt'] = 'file/png/tianfu/wjjt.png',                   -- 无尽军团
    ['sgj'] = 'file/png/tianfu/sgj.png',                          -- 赏金猎人
    ['baot'] = 'file/png/tianfu/baot.png',                    -- 暴徒
    ['xixue'] = 'file/png/tianfu/xixue.png',                   -- 蠕虫
    ['fatiao'] = 'file/png/tianfu/fatiao.png',                  -- 发条
    ['wolf'] = 'file/png/tianfu/wolf.png',                     -- 狼人
    ['youxia'] = 'file/png/tianfu/youxia.png',                     -- 游侠
    ['caijuezhe'] = 'file/png/tianfu/caijuezhe.png',               -- 裁决者（召唤进攻无人机）
    ['peishentuanyuan'] = 'file/png/tianfu/peishentuanyuan.png',        -- 陪审团
    ['rs'] = 'file/png/tianfu/rs.png',                      -- 热血（+生命）
    ['honzha'] = 'file/png/tianfu/honzha.png',                    -- 轰炸
    ['chifu'] = 'file/png/tianfu/chifu.png',                   -- 赤服
    ['tianshi'] = 'file/png/tianfu/tianshi.png',   -- 天使
    ['relife'] = 'file/png/tianfu/relife.png',               -- 复活
    ['sxf'] = 'file/png/tianfu/sxf.png',                     -- 失心疯（+敏捷）
    ['whea'] = 'file/png/tianfu/whea.png',                     -- 我好饿
    ['zg'] = 'file/png/tianfu/zg.png',                      -- 宰割（击杀掉金币）
    ['xj'] = 'file/png/tianfu/xj.png',                     -- 献祭（祭品）
    ['yinxuejian'] = 'file/png/tianfu/yinxuejian.png',              -- 饮血剑（吸血回血）
    ['sangjin'] = 'file/png/tianfu/sangjin.png',                      -- 赏金猎人
    ['xxg'] = 'file/png/tianfu/xxg.png',                       -- 食尸鬼
    ['dgwd'] = 'file/png/tianfu/dgwd.png',                   -- 帝国卫队（机枪炮塔）
    ['yueshayueduo'] = 'file/png/tianfu/yueshayueduo.png',              -- 越杀越多
    ['hkzy'] = 'file/png/tianfu/hkzy.png',      -- 活力护盾
    ['zhaohuan_kongxi'] = 'file/png/tianfu/zhaohuan_kongxi.png', -- 召唤空袭
    ['zhidanbing'] = 'file/png/tianfu/zhidanbing.png',                 -- 掷弹兵
    ['pochen_bawangqiang'] = 'file/png/tianfu/pochen_bawangqiang.png',      -- 破阵霸王枪（长枪）
    ['lidazhuanfei'] = 'file/png/tianfu/lidazhuanfei.png',            -- 力大砖飞
    ['xuyiyiquan'] = 'file/png/tianfu/xuyiyiquan.png',                -- 蓄意一拳（近战）
    ['shuangrenjian'] = 'file/png/tianfu/shuangrenjian.png',           -- 双刃剑
    ['dingjilueshizhe'] = 'file/png/tianfu/dingjilueshizhe.png',           -- 顶级掠食者
    ['emengyingrao'] = 'file/png/tianfu/emengyingrao.png',              -- 噩梦萦绕

    -- 其他类（other）
    ['wudi'] = 'file/png/tianfu/wudi.png',      -- 隐形斗篷
    ['wxs'] = 'file/png/tianfu/wxs.png',                   -- 维修师
    ['tuks'] = 'file/png/tianfu/tuks.png',               -- 吐口水
    ['hhc'] = 'file/png/tianfu/hhc.png',                       -- 滑滑虫（减速胶囊）
    ['yanshu'] = 'file/png/tianfu/yanshu.png',                    -- 鼹鼠
    ['tzzj'] = 'file/png/tianfu/tzzj.png',                         -- 投资专家
    ['carxiu'] = 'file/png/tianfu/carxiu.png',                -- 汽修工
    ['xueqiu'] = 'file/png/tianfu/xueqiu.png',                      -- 雪球（经验）
    ['tdlx'] = 'file/png/tianfu/tdlx.png',                   -- 团队领袖（经验）
    ['pulu'] = 'file/png/tianfu/pulu.png',                  -- 铺路机（石砖）
    ['dl'] = 'file/png/tianfu/dl.png',                      -- 独狼
    ['pailei'] = 'file/png/tianfu/pailei.png',                -- 工兵
    ['hc'] = 'file/png/tianfu/hc.png',                           -- 豪车党
    ['rich_son'] = 'file/png/tianfu/rich_son.png',                     -- 富二代
    ['shit_luck'] = 'file/png/tianfu/shit_luck.png',                    -- 狗屎运（宝箱）
    ['tsxf'] = 'file/png/tianfu/tsxf.png',                    -- 天神下凡
    ['chishang'] = 'file/png/tianfu/chishang.png',                     -- 发钱
    ['quanneng'] = 'file/png/tianfu/quanneng.png',                -- 全能
    ['willdie'] = 'file/png/tianfu/willdie.png',                -- 必死无疑
    ['fcz'] = 'file/png/tianfu/fcz.png',                     -- 复仇者
    ['zsfs'] = 'file/png/tianfu/zsfs.png',                         -- 忠实粉丝
    ['dutu'] = 'file/png/tianfu/dutu.png',                         -- 赌徒
    ['chengshuangchengdui'] = 'file/png/tianfu/chengshuangchengdui.png', -- 成双成对
    ['weilai'] = 'file/png/tianfu/weilai.png',                  -- 未来战士
    ['shencizhishou'] = 'file/png/tianfu/shencizhishou.png', -- 神赐之手
    ['chaoshikongshangdian'] = 'file/png/tianfu/chaoshikongshangdian.png',     -- 超时空商店
    ['lanhuangjiaonang'] = 'file/png/tianfu/lanhuangjiaonang.png',      -- 蓝黄胶囊
    ['lengdongyubaoxianshu'] = 'file/png/tianfu/lengdongyubaoxianshu.png',     -- 冷冻鱼保鲜术（鱼）
    ['ailunisi'] = 'file/png/tianfu/ailunisi.png',                -- 艾露尼斯
    ['hd'] = 'file/png/tianfu/hd.png',                     -- 皇帝
    ['guajichengsheng'] = 'file/png/tianfu/guajichengsheng.png',                -- 挂机成圣
    ['yuediaoyuerou'] = 'file/png/tianfu/yuediaoyuerou.png',             -- 越钓越肉
    ['linghang'] = 'file/png/tianfu/linghang.png',             -- 领航（T3F-1：原 utility/heart 在 core 中无此 sprite 定义，真实客户端报 Unknown sprite，按导航语义换 utility/gps_map_icon）
    ['duoduoyishan'] = 'file/png/tianfu/duoduoyishan.png',            -- 多多益善（敌方虫子）
    ['zidongfanmai'] = 'file/png/tianfu/zidongfanmai.png',                 -- 自动贩卖机（市场）
    ['huoliyu'] = 'file/png/tianfu/huoliyu.png',                    -- 活力鱼（鱼）
    ['njbomb'] = 'file/png/tianfu/njbomb.png',                     -- 黏土炸弹（炸弹意象）

    -- 补充：技能表中存在（可在游戏中学习）但未在分类或原映射中配置的图标
    ['zhrm'] = 'file/png/tianfu/zhrm.png',                  -- 走火入魔（法力）
    ['ljss'] = 'file/png/tianfu/ljss.png',            -- 我方虫子（杀友方虫子换经验）
    ['dafs'] = 'file/png/tianfu/dafs.png',               -- 大法师
    ['jgq'] = 'file/png/tianfu/jgq.png',            -- 微型法术激光枪
    ['fumo'] = 'file/png/tianfu/fumo.png',            -- 附魔虫
    ['xunshoushi'] = 'file/png/tianfu/xunshoushi.png',      -- 驯兽师
    ['rlfdz'] = 'file/png/tianfu/rlfdz.png',             -- 人力发电站
    ['wuqidashi'] = 'file/png/tianfu/wuqidashi.png', -- 武器大师
    ['jiantazhe'] = 'file/png/tianfu/jiantazhe.png',         -- 践踏者（踩踏）
    ['liliangup'] = 'file/png/tianfu/liliangup.png',               -- 力量训练（挖石头）
    ['qykj'] = 'file/png/tianfu/qykj.png',  -- 前沿科技
    ['weiyang'] = 'file/png/tianfu/weiyang.png',              -- 喂养（鱼）
    ['waixinglaike'] = 'file/png/tianfu/waixinglaike.png',         -- 外星来客（生物实验室）

    -- 补充2：技能表存在（可学习）但原 tianfu_icons 缺失，逐个读函数按实际效果补齐
    ['bujiwu'] = 'file/png/tianfu/bujiwu.png',                    -- 补给物（按在线人数+敏捷给金币）
    ['dianjiqiang'] = 'file/png/tianfu/dianjiqiang.png',     -- 电击枪（发射 electric-beam，激光伤害）
    ['wanlaotianlei'] = 'file/png/tianfu/wanlaotianlei.png',    -- 万牢天雷引（范围天雷魔法伤害，激光伤害类型）
    ['fkdda'] = 'file/png/tianfu/fkdda.png',                   -- 防空导弹A（制造 rocket 抛射物）
    ['fkddb'] = 'file/png/tianfu/fkddb.png',                   -- 防空导弹B（制造 rocket 抛射物）
    ['hmds'] = 'file/png/tianfu/hmds.png',             -- 毁灭之矢（耗蓝召唤虫子）
    ['juemuren'] = 'file/png/tianfu/juemuren.png',         -- 掘墓人（尸体复活虫子）
    ['lg'] = 'file/png/tianfu/lg.png',               -- 炼骨（吞食虫子尸体换力量）
    ['qns'] = 'file/png/tianfu/qns.png',           -- 全能射线（发射 explosive-rocket 弹幕）
    ['yhw'] = 'file/png/tianfu/yhw.png',                     -- 反弹（将拾取的敌方抛射物打回）
    ['ylsgd'] = 'file/png/tianfu/ylsgd.png',       -- 幽灵自动建造（自动补全 ghost 建筑）
    ['yuedui_gushou'] = 'file/png/tianfu/yuedui_gushou.png',         -- 乐队鼓手（施加 jellynut 加速贴纸）
    ['zhiming'] = 'file/png/tianfu/zhiming.png',                -- 致命一击（15%爆炸暴击）
    ['zrsc'] = 'file/png/tianfu/zrsc.png',               -- 自然人（活力回复）

    -- ===== T3-B 新卡图标 =====
    ['xuexijinjie'] = 'file/png/tianfu/xuexijinjie.png',  -- 学习进阶（受击感悟）
    ['luoduozhexuemai'] = 'file/png/tianfu/luoduozhexuemai.png',              -- 掠夺者血脉（掠夺生机）
    ['bujiezhiqu'] = 'file/png/tianfu/bujiezhiqu.png',               -- 不竭之躯（死亡否决）
    ['juntuanhaoling'] = 'file/png/tianfu/juntuanhaoling.png', -- 军团号令（红图指挥）
    ['yinglingwange'] = 'file/png/tianfu/yinglingwange.png',                -- 英灵挽歌（死亡清算）
    ['wangzhezhengmu'] = 'file/png/tianfu/wangzhezhengmu.png',         -- 亡者征募（亡灵化）
    ['fenshenmifa'] = 'file/png/tianfu/fenshenmifa.png',             -- 焚身秘法（烧血）
    ['shoujijigong'] = 'file/png/tianfu/shoujijigong.png',                    -- 首级记功（赏金）
    ['lianzhanlianjie'] = 'file/png/tianfu/lianzhanlianjie.png',       -- 连战连捷（战意）
    ['xiechoubaoku'] = 'file/png/tianfu/xiechoubaoku.png',             -- 血酬宝库（宝库）
    ['yichanzhixingren'] = 'file/png/tianfu/yichanzhixingren.png',                -- 遗产执行人（抚恤）
    ['zhandibilei'] = 'file/png/tianfu/zhandibilei.png',               -- 战地壁垒（壁垒）
    ['taitanzhiqu'] = 'file/png/tianfu/taitanzhiqu.png',              -- 泰坦之躯（巨躯）
    ['huoshuidongyin'] = 'file/png/tianfu/huoshuidongyin.png',                  -- 祸水东引（转嫁）
    ['yuxunqi'] = 'file/png/tianfu/yuxunqi.png',                     -- 渔汛期（收网）
    ['lianjinpeidui'] = 'file/png/tianfu/lianjinpeidui.png',         -- 炼金配对（融合）
    ['shifutilian'] = 'file/png/tianfu/shifutilian.png',               -- 食腐提炼（提炼）
    ['guzhuyizhi'] = 'file/png/tianfu/guzhuyizhi.png',                      -- 孤注一掷（豪赌）
    ['huixiang'] = 'file/png/tianfu/huixiang.png',                  -- 回响（复读）
    ['chezaiduannpeng'] = 'file/png/tianfu/chezaiduannpeng.png',                  -- 车载暖棚（车内暖棚）
    ['xuefuwuche'] = 'file/png/tianfu/xuefuwuche.png',   -- 学富五车（科研）
    ['qianchuanguihai'] = 'file/png/tianfu/qianchuanguihai.png', -- 千川归海（凝峰）
    ['tianshitouzi'] = 'file/png/tianfu/tianshitouzi.png',                    -- 天使投资（投资）
    ['zhuleishu'] = 'file/png/tianfu/zhuleishu.png',                     -- 筑垒术（工事）
    ['jixieshi'] = 'file/png/tianfu/jixieshi.png',                 -- 机械师（维修）
    ['zhandibuju'] = 'file/png/tianfu/zhandibuju.png',          -- 战地补给（弹药）
    ['liansuofanying'] = 'file/png/tianfu/liansuofanying.png',      -- 连锁反应（连环爆炸）
    ['faxinri'] = 'file/png/tianfu/faxinri.png',                         -- 发薪日（定期结算）
    ['chaopindianwang'] = 'file/png/tianfu/chaopindianwang.png',         -- 超频电网（并网）
    ['qiling'] = 'file/png/tianfu/qiling.png',                -- 起灵（唤起残骸）
    ['zhuanyun'] = 'file/png/tianfu/zhuanyun.png',                    -- 转运（保底；T3F-1：原 utility/heart 在 core 中无此 sprite 定义，真实客户端报 Unknown sprite，改用图标缺省语义同源）
    ['gongbingcanmou'] = 'file/png/tianfu/gongbingcanmou.png',             -- 工兵参谋（按图施工）
    ['qiushengbenneng'] = 'file/png/tianfu/qiushengbenneng.png', -- 求生本能（绝境回涌）
}

return Data
