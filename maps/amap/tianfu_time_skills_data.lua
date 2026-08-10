-- tianfu_time_skills_data.lua
-- 时间技能冷却配置表（从 tianfu_time_skill.lua 抽取）：skill_id -> {time}
-- name 字段为死代码（全库零读取）已移除

local Data = {}

Data.time_skills = {
    ['jiansheche'] = {
        time = 60 * 10
    },
    ['dianjiqiang'] = {
        time = 60  -- 1秒冷却（每秒触发一次）
    },
    ['wanlaotianlei'] = {
        time = 60 * 45  -- 每45秒触发一次（被动自动触发）
    },
    ['dcrg'] = {
        time = 60  -- 1秒冷却（每秒触发一次）
    },
    ['danmu_gongji'] = {
        time = 60 * 3  -- 3秒冷却
    },
    ['chongfengxianzhen'] = {
        time = 60 * 15  -- 15秒冷却
    },
     ['yanfayanjiuzhongxin'] = {
        time = 60 * 30  -- 30秒冷却
    },
    ['mlzq'] = {
        time = 30  -- 每 30 tick（0.5秒）一次：受伤时正常回蓝（原 60 秒一次几乎无效）
    },
    ['bujiwu'] = {
        time = 60 * 60
    },
    ['mzqz'] = {
        time = 60 * 30
    },
    ['yjjn'] = {
        time = 60 * 45
    },
    ['leitingwanjun'] = {
        time = 60 * 3  -- 每3秒触发一次
    },
    ['gcd'] = {
        time = 60 *60 * 30
    },
    ['cjs'] = {
        time = 60 * 60 * 3
    },
    ['beibaozhengli'] = {
        time = 60 * 2  -- 5秒冷却
    },
    ['wjjt'] = {
        time = 60 * 135
    },
    ['kls'] = {
        time = 60 * 60
    },
    ['whea'] = {
        time = 60 * 5
    },
    ['kytd'] = {
        time = 60 * 60 * 10
    },
    ['zhrm'] = {
        time = 60 * 60 * 10
    },
    ['scmcc'] = {
        time = 60 * 60  -- 每1分钟触发一次
    },
    ['kejigongsi'] = {
        time = 60 * 60  -- 每1分钟触发一次
    },
    ['mbz'] = {
        time = 60 * 60
    },
    ['tls'] = {
        time = 60 * 45
    },
    ['zsfs'] = {
        time = 60 * 60 * 10
    },
    ['djrc'] = {
        time = 60 * 60 * 60
    },
    ['pulu'] = {
        time = 60 * 60
    },
    ['dafs'] = {
        time = 60 * 10
    },
    ['ljss'] = {
        time = 60 * 12
    },
    ['mfxt'] = {
        time = 60 * 60
    },
    ['ylsgd'] = {
        time = 60 * 3
    },
    ['fuzhushou'] = {
        time = 60 * 3
    },
    ['tann'] = {
        time = 60 * 60 * 10
    },
    ['rsrl'] = {
        time = 60 * 5
    },
    ['xly'] = {
        time = 60 * 60
    },
    ['tzzj'] = {
        time = 60 * 60 * 10
    },

    ['hhc'] = {
        time = 60 * 7
    },
    ['jgq'] = {
        time = 60 * 10
    },

    ['xj'] = {
        time = 60 * 3
    },
    ['smlw'] = {
        time = 60 * 60 * 30
    },
    ['jndd'] = {
        time = 60 * 60
    },
    ['ycj'] = {
        time = 60 * 60
    },

    ['qns'] = {
        time = 60 * 3
    },
    ['falibiqu'] = {
        time = 60  -- 1秒冷却（每秒触发一次）
    },
    ['chuanqibaozang'] = {
        time = 60*45   -- 30秒冷却
    },
    ['dl'] = {
        time = 60 * 4
    },
    ['jifengbu'] = {
        time = 60 * 10  -- 10秒冷却
    },
    ['jxhx'] = {
        time = 60
    },
    ['wlfs'] = {
        time = 60 * 13
    },
    ['xxzb'] = {
        time = 60
    },
    ['xuyiyiquan'] = {
        time = 60 * 6  -- 6秒冷却
    },
    ['juemuren'] = {
        time = 60 * 15
    },
    ['lg'] = {
        time = 60 * 10
    },
    ['xxg'] = {
        time = 60 * 10
    },
    ['dgwd'] = {
        time = 60 * 22
    },
    ['honzha'] = {
        time = 60 * 60
    },
    ['chifu'] = {
        time = 60
    },
    ['touqian'] = {
        time = 60 * 60
    },
    ['fatiao'] = {
        time = 60 * 3
    },
    ['fkdda'] = {
        time = 60 * 3
    },
    ['fkddb'] = {
        time = 60 * 5
    },
    ['keyan'] = {
        time = 60 * 20
    },

    ['hmds'] = {
        time = 60 * 22
    },
    ['sglz'] = {
        time = 60 * 6
    },
    ['bpz'] = {
        time = 60 * 60
    },
    ['boom_player'] = {
        time = 60 * 3
    },
    ['small_buss'] = {
        time = 60 * 30
    },
    ['zrsc'] = {
        time = 60 * 60
    },
    ['zhs'] = {
        time = 60 * 15
    },
    ['wolf'] = {
        time = 60 * 3
    },
    ['dutu'] = {
        time = 60 * 10 * 6
    },
    ['wxs'] = {
        time = 60 * 2
    },
    ['junhuo'] = {
        time = 60 * 30
    },
    ['genben'] = {
        time = 60 * 8
    },
    ['fish'] = {
        time = 60 * 20
    },
    ['zdfs'] = {
        time = 60 * 3
    },
    ['zdfs2'] = {
        time = 60 * 6
    },
    ['jingong'] = {
        time = 60 * 75
    },
    ['hd'] = {
        time = 60 * 60 * 15
    },
    ['fali'] = {
        time = 60 * 3
    },
    ['juqichengjian'] = {
        time = 60
    },
    ['fumo'] = {
        time = 60 * 20  -- 30秒冷却
    },
    ['carxiu'] = {
        time = 60 * 5
    },
    ['ftlt'] = {
        time = 30 * 60
    },
    ['tdlx'] = {
        time = 60 * 60
    },
    ['fangshou'] = {
        time = 60 * 60
    },
    ['dianluban'] = {
        time = 60 * 3
    },
    ['xueqiu'] = {
        time = 60 * 3
    },
    ['jiguang'] = {
        time = 60 * 60 * 3
    },
    ['wudi'] = {
        time = 60 * 10
    },
    ['pailei'] = {
        time = 60 * 3
    },
    ['sansan'] = {
        time = 60*30
    },
    ['mlst'] = {
        time = 60 * 60 * 1
    },
    ['xxyd'] = {
        time = 60 * 60 * 1
    },
    ['morefali'] = {
        time = 60 * 30
    },
    ['rlfdz'] = {
        time = 60 * 60 *45
    },
    ['yuer'] = {
        time = 60 * 10
    },
    

    ['shen_fa'] = {
        time = 60 * 10 -- 30秒冷却时间
    },
    ['diyu_rongyan'] = {
        time = 60 * 10 -- 10秒冷却时间
    },
    ['lanhuangjiaonang'] = {
        time = 60 * 15 -- 15秒冷却
    },
    ['zishenzhuanjia'] = {
        time = 60 * 30 -- 30秒冷却
    },
    ['daodaoku'] = {
        time = 60 * 30 -- 30秒冷却
    },
    ['weilai'] = {
        time = 60 * 120 -- 120秒冷却
    },
    ['jidiche'] = {
        time = 60 * 10 -- 10秒冷却
    },
    ['hushenfu'] = {
        time = 60 * 10 -- 10秒冷却时间
    },
    ['zhuoshao'] = {
        time = 60 * 10  -- 10秒冷却
    },
    ['tieshenhuwei'] = {
        time = 60 * 22  -- 22秒冷却
    },
    ['shui_hu_fu'] = {
        time = 60 * 30  -- 30秒冷却，用于充能恢复
    },
    ['shui_dun'] = {
        time = 60 * 10  -- 10秒冷却，周期性释放劣化版水龙弹
    },
    ['lengdongyubaoxianshu'] = {
        time = 60 * 30  -- 30秒冷却
    },
    ['chaoshikongshangdian'] = {
        time = 60*60*45  -- 每45分钟触发一次
    },
    ['gycs'] = {
        time = 60 * 60  -- 每1分钟触发一次
    },
    ['gongchengche'] = {
        time = 60 * 12  -- 10秒冷却
    },
    ['yelianche'] = {
        time = 60 * 13  -- 10秒冷却
    },
    ['tianzhao'] = {
        time = 60*3  -- 3秒冷却
    },
    ['yuedui_gushou'] = {
        time = 60 * 10  -- 10秒冷却
    },
    ['xunshoushi'] = {
        time = 60 * 30  -- 每30秒触发一次
    },
    ['tesla_battery'] = {
        time = 60 * 5  -- 每5秒触发一次
    },
    ['lidazhuanfei'] = {
        time = 60 * 4  -- 每3秒触发一次
    },
    ['qiche_ren'] = {
        time = 60 * 1  -- 1秒冷却
    },
    ['xuyiyiquan'] = {
        time = 60 * 6  -- 6秒冷却
    },
    ['ailunisi'] = {
        time = 60 * 60  -- 被动天赋，在deal_damage_with_floating_text中触发
    },
    ['haiguanfang'] = {
        time = 60 * 60  -- 每1分钟触发一次
    },
    ['emengyingrao'] = {
        time = 60 * 60  -- 每1分钟触发一次
    },
    ['zhidanbing'] = {
        time = 60  -- 每秒触发一次
    },
    ['guajichengsheng'] = {
        time = 60 * 60 -- 每分钟检测一次（挂机触发）
    },
    ['yuediaoyuerou'] = {
        time = 60 * 60 -- 每分钟触发一次
    },
    ['linghang'] = {
        time = 60 * 60 -- 每分钟触发一次
    },
    ['duoduoyishan'] = {
        time = 30 * 60 -- 每30秒触发一次
    },
    ['zidongfanmai'] = {
        time = 5 * 60 -- 每5秒检测一次（自动贩卖机）
    },
    ['huoliyu'] = {
        time = 60 * 60 -- 每1分钟触发一次
    },
    ['njbomb'] = {
        time = 60 * 6 -- 每6秒触发一次（被动自动为友方虫子施加亡语）
    },
}

return Data
