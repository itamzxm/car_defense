local Global = require 'utils.global'
local Event = require 'utils.event'
local this = {}

local Public = {}

Global.register(
    this,
    function(tbl)
        this = tbl
    end
)


-- 初始化所有天赋相关的表

-- 重置所有表
function Public.reset_table()
    -- 清空所有表，但保持全局存储引用不变
    for k in pairs(this) do
        this[k] = nil
    end
    
    -- 重新初始化所有字段
    this.all_skill = {}
    this.wanglingdajun_souls = {}
    this.wanglingdajun_stored_biters = {}
    this.dingjilueshizhe_kills = {}
    this.tick_skill = {}
    this.choise_skill = {}
    this.shencizhishou_active={}
    this.bpz_count = {}
    this.qiankuang = {}
    this.mine_count = {}
    this.xixue_count = {}
    this.xybg_count = {}
    this.qns_true = false
    this.sgj_count = {}
    this.whea_count = {}
    this.sxf_count = {}
    this.yl_count = {}
    this.xuanze = {}
    this.yjjn_count = {}
    this.yjjn_cn = {}
    this.leitingwanjun_charges = {}  -- 雷霆万钧充能数
    this.leitingwanjun_magic_bonus = {}  -- 雷霆万钧魔法加成
    this.tesla_battery_charges = {}  -- 特斯拉蓄电池充能数
    this.tesla_battery_charge_counter = {}  -- 特斯拉蓄电池充能计数器
    this.fish_count = {}
    this.boom_player_count = {}
    this.boom_player_charges = {}
    this.yanfa_count = {}
    this.biter_kill = {}
    this.fumo_biters = {}  -- 附魔虫子表，存储玩家ID和对应的附魔虫子列表
    this.fumo_biter_to_player = {}  -- 附魔虫子到玩家的映射表，使用unit_number作为键
    this.hushenfu_shield = {}
    this.yinxuejian_shield = {}
    this.fengyinjuanzhou_extra_mana = {}  -- 存储玩家通过封印卷轴获得的额外最大法力值
    this.fengyinjuanzhou_count = {}       -- 存储玩家封印灵魂的计数
    this.xuebao_damage = {}          -- 存储玩家血爆伤害
    this.tianfu_cooldown = {}        -- 存储有冷却时间的天赋，格式：天赋名=冷却时间（tick）；gui.lua 冷却条读取此字段
    this.skill_cooldowns = {}        -- 优化的冷却时间表，按玩家索引组织
    this.batch_player_index = 1      -- 分批处理时的玩家索引跟踪器
    this.player_time_skills = {}     -- 玩家时间技能索引：this.player_time_skills[player_name] = {skill_name = true}
    -- 注：player_skill_batch 已删除（死字段：定义后从未被读写）
    -- 方案 B：倒排索引 [skill_id][player_index] = true，仅收录 trigger_skill 和 once_skill
    -- 用于替换事件 handler 中的"全玩家扫描 + have_learn"模式
    this.skill_owners = {}
    -- 方案 C：tick 分桶调度表 [due_tick][player_index] = {skill_name1, skill_name2, ...}
    -- on_tick 每 tick 查 due_buckets[game.tick]，桶里只放当前 tick 到期的 time_skill
    -- 学习 time_skill 时登记第一次到期；调用后自动登记下一次到期
    this.due_buckets = {}
    this.last_bucket_clean = 0  -- 上次清理过期桶的 tick（防内存泄漏）
    this.pochen_bawangqiang_damage_bonus = {}  -- 破阵霸王枪伤害加成
    this.chaoshikongshangdian_items = {}  -- 超时空商店物品列表：this.chaoshikongshangdian_items[player_index] = {item_name, price}
    this.chaoshikongshangdian_last_refresh = {}  -- 超时空商店上次刷新时间：this.chaoshikongshangdian_last_refresh[player_index] = tick
    this.chaoshikongshangdian_spent = {}  -- 超时空商店已花费金币：this.chaoshikongshangdian_spent[player_index] = amount
end

-- 在模块加载时注册初始化函数
local on_init = function()
    Public.reset_table()
end

Event.on_init(on_init)
-- 获取表数据
function Public.get()
    return this
end

return Public