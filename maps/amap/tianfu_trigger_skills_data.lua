-- tianfu_trigger_skills_data.lua
-- 触发技能冷却配置表（从 tianfu_trigger_skill.lua 抽取）：skill_id -> {time?}
-- name 字段为死代码（全库零读取）已移除；无 time 的技能在调度时走默认冷却

local Data = {}

Data.trigger_skills = {
    ['mijingzhang'] = {
    },
    ['shengguangzhongji'] = {
    },
    ['gongshengti'] = {
    },
    ['yubaobao'] = {
    },
    ['wuqidashi'] = {
    },
    ['jingzhunzhidao'] = {
    },
    ['lianhejuntuan'] = {
    },
    ['jika'] = {
    },
    ['bei_dong_zhao_huan'] = {
        time = 60 * 3
    },
    ['zhiming'] = {
    },
    ['xybg'] = {
    },
    ['yinxuejian'] = {
    },
    -- ['mdt'] = {
    --     name = mdt,
    --     time = 60 * 12
    -- },
    ['xuebao'] = {
    },
    ['shoujiao_wuqi'] = {
    },
    ['yfz'] = {
    },
    ['smmf'] = {
    },
    ['tianshi'] = {
    },
    ['tjjz'] = {
        time = 60 * 60 * 3
    },
    ['relife'] = {
        time = 3 * 60 * 60
    },
    ['sxf'] = {
    },
    ['yhw'] = {
        time = 60 * 3
    },
    ['yl'] = {
    },
    ['kxj'] = {
    },
    ['qykj'] = {
    },
    ['xueshu'] = {
    },
    ['baot'] = {
    },
    ['tuks'] = {
    },
    ['willdie'] = {
        time = 60 * 30 * 1
    },
    ['yanshu'] = {
        time = 60 * 10
    },
    ['liliangup'] = {
    },
    ['fcz'] = {
        time = 60 * 60 * 3
    },
    ['jiantazhe'] = {
        time=8
    },
    ['youxia'] = {
    },
    -- ['wanglingdajun'] = {
    --     name = wanglingdajun
    -- },
    ['xixue'] = {
    },
    ['bpz'] = {
    },
    ['zg'] = {
    },
    ['sgj'] = {
    },
    ['sangjin'] = {
    },
    ['yueshayueduo'] = {
    },
    ['hyll'] = {
    },
    ['dgjx'] = {
    },
    ['shandianwulianbian'] = {
        time = 60 * 3
    },
    ['chengshuangchengdui'] = {
        time = 60*2  
    },
    ['shoucuo_de_shen'] = {
    },
    ['htms'] = {
        time = 60 * 60 * 10,  -- 10分钟冷却
    },
    ['hkzy'] = {
    },
    ['tishenshu'] = {
        time = 60*12  
    },
    ['zhaohuan_kongxi'] = {
        time = 60 * 60 * 5
    },
    ['shouyiren'] = {
    },
    ['dingjilueshizhe'] = {
    },
    ['caijuezhe'] = {
    },
    ['peishentuanyuan'] = {
    },
    ['shencizhishou'] = {
        time = 60*60 * 20  -- 20分钟冷却时间
    },
    ['fengyinjuanzhou'] = {
    },
    ['dijiaojiaotu'] = {
         time = 60*60
    },
    ['wuxingjue'] = {
        time= 30
    },
    ['pochen_bawangqiang'] = {
        time = 60 * 3
    },
    ['shimozhe'] = {
    },
    ['yanmo'] = {
        time = 60 * 2
    },
    ['shuangrenjian'] = {
    }
}

return Data
