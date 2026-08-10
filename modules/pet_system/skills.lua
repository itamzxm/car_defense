-- ============================================================
-- 虫子宠物技能系统框架
-- ============================================================
--
-- 设计原则：
-- - 每个技能分为 5 个品质（普通 / 稀有 / 精良 / 史诗 / 传说）。
-- - 品质仅影响系数（ATK 系数、HP 系数、数量等），
--   CD、持续时间、目标数、半径等参数均固定不变。
-- - 技能分类为内部设计（category: 'anytime' / 'combat'），不对玩家展示。
-- - 伤害归属：技能效果从宠物位置发出，但伤害来源必须归属玩家角色
--   （source = player.character），确保击杀经验和金币归属玩家。
--   参考 tianfu_time_skill.lua 的写法。
-- - 触发类型（trigger）：
--     'time'           — 随时间触发（anytime / combat）
--     'death'          — 宠物 unit 死亡时触发（combat）
--     'owner_damaged'  — 玩家受伤害时触发（combat）
-- - 添加新技能：在 skill_defs 表中注册即可，框架自动路由。
-- - 技能命名规范：技能 name 统一使用中文字符串，禁止使用英文或拼音。
--   所有 skill_defs key 均为中文字符串，确保与 pet.skills 存储一致。
--   异星工厂 Lua 环境要求中文 key 必须用 ['xxx'] 语法定义，禁止裸 key。
--
-- 【重要】magicka（魔力值） vs mana（施法能量）：
--   - magicka: RPG 属性，影响经验获取、伤害加成等，存储于 rpg_t.magicka
--   - mana:    施法消耗的能量条，存储于 rpg_t.mana，通过 RPG.functions.reward_mana() 恢复
--   - 宠物技能恢复的是 mana（施法能量），不要混淆！
--
-- ============================================================

local Public = {}
local pet_table = require 'modules.pet_system.table'
local RPG = require 'modules.rpg.core'


-- ============================================================
-- 技能定义组装（已从本文件拆分为 skill_defs_*.lua 定义文件）
-- 共享同一个 skill_defs 表：各定义文件 return function(skill_defs) 填充
-- 添加新技能：到对应 trigger 分组的 skill_defs_*.lua 末尾追加
--   anytime/time → skill_defs_anytime.lua
--   combat/time → skill_defs_combat.lua（生产辅助函数也在此文件）
--   deploy → skill_defs_deploy.lua
--   death / owner_damaged / research → skill_defs_event.lua
-- 辅助（Token/文本函数）在 skill_helpers.lua
-- ============================================================
local skill_defs = {}

local FillAnytime = require 'modules.pet_system.skill_defs_anytime'
local FillCombat = require 'modules.pet_system.skill_defs_combat'
local FillDeploy = require 'modules.pet_system.skill_defs_deploy'
local FillEvent = require 'modules.pet_system.skill_defs_event'
FillAnytime(skill_defs)
FillCombat(skill_defs)
FillDeploy(skill_defs)
FillEvent(skill_defs)


-- ============================================================
-- 技能调度器（预分类索引，O(1) 直接调用，参考天赋系统模式）
-- ============================================================

-- 按 trigger × category 预建索引（模块加载时一次性完成）
local skills_by_trigger = {}

local function ensure_trigger_category(trigger, category)
    if not skills_by_trigger[trigger] then
        skills_by_trigger[trigger] = {}
    end
    if not skills_by_trigger[trigger][category] then
        skills_by_trigger[trigger][category] = {}
    end
    return skills_by_trigger[trigger][category]
end

-- 注册技能到索引
for name, def in pairs(skill_defs) do
    local category = def.category or 'anytime'
    local index = ensure_trigger_category(def.trigger, category)
    index[name] = def
end

-- 获取宠物的可执行技能列表（返回 {name, execute=fn, q_idx=..., interval_ticks=...} 数组）
local function get_pet_skills(pet)
    local result = {}
    for _, skill_data in ipairs(pet.skills) do
        if not skill_data then goto continue end
        local skill_name, skill_quality
        if type(skill_data) == 'table' then
            skill_name = skill_data.name
            skill_quality = skill_data.quality
        else
            skill_name = skill_data
            skill_quality = 1
        end
        local def = skill_defs[skill_name]
        if def then
            result[#result + 1] = {
                name = skill_name,
                category = def.category,
                trigger = def.trigger,
                execute = def.execute,
                q_idx = quality_index(skill_quality),
                interval_ticks = def.interval_ticks or 0,
            }
        end
        ::continue::
    end
    return result
end

-- 获取所有可用技能名（全部，包括专属）
function Public.get_all_skill_names()
    local names = {}
    for name, _ in pairs(skill_defs) do
        names[#names + 1] = name
    end
    return names
end

-- 获取可通过技能书学习的技能名（排除宠物专属技能）
function Public.get_learnable_skill_names()
    local names = {}
    for name, def in pairs(skill_defs) do
        if not def.exclusive_type then
            names[#names + 1] = name
        end
    end
    return names
end

-- 从技能书随机获得一个技能（排除专属技能）
function Public.roll_skill_from_book(book_type)
    local quality = pet_table.roll_quality(book_type)
    local names = Public.get_learnable_skill_names()
    if #names == 0 then return nil end
    local skill_name = names[math.random(1, #names)]
    return {name = skill_name, quality = quality}
end

-- 调度 anytime 时间触发技能（在 on_tick 中调用，每分钟）
function Public.dispatch_anytime_time(player)
    local pet_data = pet_table.get_player_pet_data(player)

    if not pet_data.skill_cooldowns then
        pet_data.skill_cooldowns = {}
    end

    for _, pet in ipairs(pet_data.pets) do
        if pet.hp <= 0 then goto continue end
        if pet.hunger < 60 then goto continue end

        if not pet_data.skill_cooldowns[pet] then
            pet_data.skill_cooldowns[pet] = {}
        end
        local pet_cooldowns = pet_data.skill_cooldowns[pet]

        local skills = get_pet_skills(pet)
        for _, s in ipairs(skills) do
            if s.category ~= 'anytime' or s.trigger ~= 'time' then goto skip_skill end
            local last = pet_cooldowns[s.name] or 0
            if s.interval_ticks > 0 and game.tick - last < s.interval_ticks then
                goto skip_skill
            end
            s.execute(player, pet, s.q_idx)
            pet_cooldowns[s.name] = game.tick
            ::skip_skill::
        end
        ::continue::
    end
end


-- 调度 combat 时间触发技能（在 on_combat_tick 中调用，每 3 秒）
-- 通过独立冷却表保证每名玩家的技能时间精度，不受其他玩家影响
function Public.dispatch_combat_time(player)
    local pet_data = pet_table.get_player_pet_data(player)

    if not pet_data.skill_cooldowns then
        pet_data.skill_cooldowns = {}
    end

    for _, pet in ipairs(pet_data.pets) do
        if not pet.unit or not pet.unit.valid then goto continue end
        if pet.hunger < 60 then goto continue end

        if not pet_data.skill_cooldowns[pet] then
            pet_data.skill_cooldowns[pet] = {}
        end
        local pet_cooldowns = pet_data.skill_cooldowns[pet]

        local skills = get_pet_skills(pet)
        for _, s in ipairs(skills) do
            if s.category ~= 'combat' or s.trigger ~= 'time' then goto skip_skill end
            -- 检查冷却
            local last = pet_cooldowns[s.name] or 0
            if s.interval_ticks > 0 and game.tick - last < s.interval_ticks then
                goto skip_skill
            end
            -- 执行前再次检查 pet.unit 有效性
            -- （前一个技能的副作用可能导致宠物实体被销毁）
            if not pet.unit or not pet.unit.valid then goto continue end
            s.execute(player, pet, s.q_idx)
            pet_cooldowns[s.name] = game.tick
            ::skip_skill::
        end
        ::continue::
    end
end

-- 调度 combat death 触发技能（在 on_entity_died 中调用）
function Public.dispatch_death(player, pet, death_position, death_surface)
    if pet.hunger < 60 then return end
    local skills = get_pet_skills(pet)
    for _, s in ipairs(skills) do
        if s.trigger ~= 'death' then goto skip_skill end
        s.execute(player, pet, s.q_idx, death_position, death_surface)
        ::skip_skill::
    end
end

-- 调度 deploy 触发技能（宠物出战时一次性触发）
function Public.dispatch_deploy(player, pet)
    local skills = get_pet_skills(pet)
    for _, s in ipairs(skills) do
        if s.trigger ~= 'deploy' then goto skip_skill end
        s.execute(player, pet, s.q_idx)
        ::skip_skill::
    end
end

-- 调度 owner_damaged 触发技能（在 on_entity_damaged 中调用）
function Public.dispatch_owner_damaged(player, damage_amount, cause)
    local pet_data = pet_table.get_player_pet_data(player)

    if not pet_data.skill_cooldowns then
        pet_data.skill_cooldowns = {}
    end

    for _, pet in ipairs(pet_data.pets) do
        if not pet.unit or not pet.unit.valid then goto continue end
        if pet.hp <= 0 then goto continue end
        if pet.hunger < 60 then goto continue end

        if not pet_data.skill_cooldowns[pet] then
            pet_data.skill_cooldowns[pet] = {}
        end
        local pet_cooldowns = pet_data.skill_cooldowns[pet]

        local skills = get_pet_skills(pet)
        for _, s in ipairs(skills) do
            if s.trigger ~= 'owner_damaged' then goto skip_skill end
            local last = pet_cooldowns[s.name] or 0
            if s.interval_ticks > 0 and game.tick - last < s.interval_ticks then
                goto skip_skill
            end
            s.execute(player, pet, s.q_idx, damage_amount, cause)
            pet_cooldowns[s.name] = game.tick
            ::skip_skill::
        end
        ::continue::
    end
end

-- 调度 research 触发技能（在 on_research_finished 中调用）
-- 科研助手是 anytime 类别，宠物未出战时也应触发（与 dispatch_anytime_time 一致）
function Public.dispatch_research(player)
    local pet_data = pet_table.get_player_pet_data(player)
    if not pet_data or not pet_data.pets then return end

    for _, pet in ipairs(pet_data.pets) do
        if pet.hp <= 0 then goto continue end
        if pet.hunger < 60 then goto continue end

        local skills = get_pet_skills(pet)
        for _, s in ipairs(skills) do
            if s.trigger ~= 'research' then goto skip_skill end
            s.execute(player, pet, s.q_idx)
            ::skip_skill::
        end
        ::continue::
    end
end

-- 检查宠物是否有指定触发类型的技能（通过预分类索引）
function Public.has_death_skill(pet)
    for _, skill_data in ipairs(pet.skills) do
        if not skill_data then goto continue end
        local skill_name = type(skill_data) == 'table' and skill_data.name or skill_data
        if skill_name and skills_by_trigger['death'] and skills_by_trigger['death']['combat'] then
            if skills_by_trigger['death']['combat'][skill_name] then
                return true
            end
        end
        ::continue::
    end
    return false
end

-- 获取技能定义（供外部查看）
function Public.get_skill_def(name)
    return skill_defs[name]
end

-- 技能名 → locale key 后缀映射
local skill_locale_keys = {
    ['打工人']   = 'dagongren',
    ['分裂攻击'] = 'fenlie_gongji',
    ['远程裂变'] = 'yuanchengliebian',
    ['爆炸虫']   = 'baozha_chong',
    ['护卫']     = 'huwei',
    ['金炼']     = 'jinlian',
    ['自给自足'] = 'zigeizizu',
    ['炎息']     = 'yanxi',
    ['蛮力冲撞'] = 'manlichongzhuang',
    ['雷击']     = 'leiji',
    ['吞噬']     = 'tunshi',
    ['地裂']     = 'dilie',
    ['炮塔手']   = 'paotashou',
    ['疗愈师']   = 'liaoyushi',
    ['疯长']     = 'fengzhang',
    ['好战者']   = 'haozhanzhe',
    ['狂热者']   = 'kuangrezhe',
    ['有丝分裂'] = 'yousifenlie',
    ['火箭弹幕'] = 'huojiandanmu',
    ['血牛']     = 'xueniu',
    ['愤怒收割者'] = 'fennushougezhe',
    ['闭关修炼']   = 'biguanxiulian',
    ['弹幕投掷']   = 'danmutouzhi',
    ['火箭发射器'] = 'huojianfasheqi',
    ['旋风斩']     = 'xuanfengzhan',
    ['生命汲取']   = 'shengmingjiqu',
    ['金刚狼']     = 'jinganglang',
    ['火焰陷阱']     = 'huoyanxianjing',
    ['地狱熔岩']     = 'diyurongyan',
    ['爆裂法术']   = 'baoliefashu',
    ['天照']       = 'tianzhao',
    ['特斯拉蓄电池'] = 'tesila',
    ['雷阵雨']     = 'leizhenyu',
    ['魔晶杖']     = 'mojingzhang',
    ['灵魂一指']   = 'linghunyizhi',
    ['法力回流']   = 'falihuiliu',
    ['工兵']       = 'gongbing',
    ['愈战愈勇']   = 'yuzhanyuyong',
    ['夜幕']       = 'yemu',
    ['沙虫炮塔']   = 'shachongpaota',
    ['沙虫召唤']   = 'shachongzhaohuan',
    ['成群结队']   = 'chengqunjiedui',
    ['战争红利']   = 'zhanzhenghongli',
    ['无人机掩护'] = 'wurenjiyanhu',
    ['决死冲锋']   = 'juesichongfeng',
    ['再生']       = 'zaisheng',
    ['荆棘']       = 'jingji',
    ['环形火山']   = 'huanxinghuoshan',
    ['减速弹幕']   = 'jiansudanmu',
    ['军火商']     = 'junhuoshang',
    ['工业家']     = 'gongyejia',
    ['科研助手']   = 'keyanzhushou',
    ['虫咬']       = 'chongyao',
    ['吐口水']     = 'tukoushui',
    ['蠕虫能量']   = 'ruchongnengliang',
    ['支援光环']   = 'zhiyuanguanghuan',
    ['虫群召唤']   = 'chongqunzhaohuan',
    ['火遁']       = 'huodun',
    ['编织者']     = 'bianzhizhe',
}

-- 获取技能描述（返回 LocalisedString，计算实际数值）
function Public.get_skill_description(skill_name, pet, skill_quality, player)
    player = player or {index = 0}
    local def = skill_defs[skill_name]
    if not def then return nil end
    local key = skill_locale_keys[skill_name]
    if not key then return nil end

    local q_idx = quality_index(skill_quality)

    if skill_name == '打工人' then
        local coins = pet.level * def.quality_values[q_idx]
        return {'pet_system.skill_' .. key .. '_desc', coins}
    elseif skill_name == '分裂攻击' then
        local target_count = def.quality_values[q_idx]
        local dmg = math.floor(pet.attack * 0.5)
        return {'pet_system.skill_' .. key .. '_desc', target_count, dmg}
    elseif skill_name == '远程裂变' then
        local target_count = def.quality_values[q_idx]
        local dmg = math.floor(pet.attack * 0.5)
        return {'pet_system.skill_' .. key .. '_desc', target_count, dmg}
    elseif skill_name == '爆炸虫' then
        local dmg = math.floor(pet.attack * def.quality_values[q_idx])
        return {'pet_system.skill_' .. key .. '_desc', dmg}
    elseif skill_name == '护卫' then
        local absorb = def.quality_values[q_idx] * 100
        return {'pet_system.skill_' .. key .. '_desc', absorb}
    elseif skill_name == '金炼' then
        local xp = pet.level * def.quality_values[q_idx]
        return {'pet_system.skill_' .. key .. '_desc', xp}
    elseif skill_name == '自给自足' then
        local fish = pet.level * def.quality_values[q_idx]
        return {'pet_system.skill_' .. key .. '_desc', fish}
    elseif skill_name == '炎息' then
        local targets = def.quality_values[q_idx]
        local dmg = math.floor(pet.attack * 0.4)
        return {'pet_system.skill_' .. key .. '_desc', targets, dmg}
    elseif skill_name == '蛮力冲撞' then
        local dmg = math.floor(pet.attack * def.quality_values[q_idx])
        return {'pet_system.skill_' .. key .. '_desc', dmg}
    elseif skill_name == '雷击' then
        local chains = def.quality_values[q_idx]
        local dmg = math.floor(pet.attack * 0.5)
        return {'pet_system.skill_' .. key .. '_desc', chains, dmg}
    elseif skill_name == '吞噬' then
        local kills = def.quality_values[q_idx]
        return {'pet_system.skill_' .. key .. '_desc', kills}
    elseif skill_name == '地裂' then
        local dmg = math.floor(pet.attack * def.quality_values[q_idx])
        return {'pet_system.skill_' .. key .. '_desc', dmg}
    elseif skill_name == '炮塔手' then
        local turrets = def.quality_values[q_idx]
        return {'pet_system.skill_' .. key .. '_desc', turrets}
    elseif skill_name == '疗愈师' then
        local pct = def.quality_values[q_idx]
        local heal = math.ceil(pet.max_hp * pct / 100)
        return {'pet_system.skill_' .. key .. '_desc', heal}
    elseif skill_name == '疯长' then
        local rpg_t = RPG.get_value_from_player(player.index)
        local magicka = (rpg_t and rpg_t.magicka) or 0
        local natural_xp = 5 + 10 * (magicka / 100)
        local bonus_xp = math.floor(natural_xp * def.quality_values[q_idx])
        return {'pet_system.skill_' .. key .. '_desc', bonus_xp}
    elseif skill_name == '好战者' then
        local points = def.quality_values[q_idx]
        return {'pet_system.skill_' .. key .. '_desc', points}
    elseif skill_name == '狂热者' then
        local allies = def.quality_values[q_idx]
        local heal = pet.level * 9
        return {'pet_system.skill_' .. key .. '_desc', allies, heal}
    elseif skill_name == '有丝分裂' then
        local pct = def.quality_values[q_idx]
        local hp = math.floor(pet.hp * pct / 100)
        return {'pet_system.skill_' .. key .. '_desc', pct, hp}
    elseif skill_name == '火箭弹幕' then
        local rockets = def.quality_values[q_idx]
        return {'pet_system.skill_' .. key .. '_desc', rockets}
    elseif skill_name == '血牛' then
        local mult = def.quality_values[q_idx]
        local new_hp = math.floor(pet.hp * mult)
        return {'pet_system.skill_' .. key .. '_desc', mult, new_hp}
    elseif skill_name == '愤怒收割者' then
        local mult = def.quality_values[q_idx]
        local new_atk = math.floor(pet.attack * mult)
        return {'pet_system.skill_' .. key .. '_desc', mult, new_atk}
    elseif skill_name == '闭关修炼' then
        local points = def.quality_values[q_idx]
        return {'pet_system.skill_' .. key .. '_desc', points}
    elseif skill_name == '弹幕投掷' then
        local throws = def.quality_values[q_idx]
        return {'pet_system.skill_' .. key .. '_desc', throws}
    elseif skill_name == '火箭发射器' then
        local rockets = def.quality_values[q_idx]
        return {'pet_system.skill_' .. key .. '_desc', rockets}
    elseif skill_name == '旋风斩' then
        local dmg = math.floor(pet.attack * def.quality_values[q_idx])
        return {'pet_system.skill_' .. key .. '_desc', dmg}
    elseif skill_name == '生命汲取' then
        local dmg = math.floor(pet.attack * def.quality_values[q_idx])
        local heal = math.ceil(dmg * 0.2)
        return {'pet_system.skill_' .. key .. '_desc', dmg, heal}
    elseif skill_name == '金刚狼' then
        local pct = def.quality_values[q_idx]
        local heal = math.ceil((pet.max_hp - pet.hp) * pct / 100)
        return {'pet_system.skill_' .. key .. '_desc', pct, heal}
    elseif skill_name == '火焰陷阱' then
        local duration = def.quality_values[q_idx]
        local dmg = math.floor(pet.attack * 0.3)
        return {'pet_system.skill_' .. key .. '_desc', duration, dmg}
    elseif skill_name == '地狱熔岩' then
        local dmg = math.floor(pet.attack * def.quality_values[q_idx] * 0.3)
        return {'pet_system.skill_' .. key .. '_desc', dmg}
    elseif skill_name == '爆裂法术' then
        local targets = def.quality_values[q_idx]
        local dmg = math.floor(pet.attack * 0.6)
        return {'pet_system.skill_' .. key .. '_desc', targets, dmg}
    elseif skill_name == '天照' then
        local count = def.quality_values[q_idx]
        return {'pet_system.skill_' .. key .. '_desc', count}
    elseif skill_name == '特斯拉蓄电池' then
        local dmg = math.floor(pet.attack * def.quality_values[q_idx])
        return {'pet_system.skill_' .. key .. '_desc', dmg}
    elseif skill_name == '雷阵雨' then
        local strikes = def.quality_values[q_idx]
        local dmg = math.floor(pet.attack * 1.2)
        return {'pet_system.skill_' .. key .. '_desc', strikes, dmg, 6 + math.floor(q_idx * 0.5)}
    elseif skill_name == '魔晶杖' then
        local dmg = math.floor(pet.attack * def.quality_values[q_idx])
        return {'pet_system.skill_' .. key .. '_desc', dmg}
    elseif skill_name == '灵魂一指' then
        local dmg = math.floor(pet.attack * def.quality_values[q_idx])
        return {'pet_system.skill_' .. key .. '_desc', dmg}
    elseif skill_name == '法力回流' then
        local mana = math.floor(pet.attack * def.quality_values[q_idx])
        return {'pet_system.skill_' .. key .. '_desc', mana}
    elseif skill_name == '工兵' then
        local count = def.quality_values[q_idx]
        return {'pet_system.skill_' .. key .. '_desc', count}
    elseif skill_name == '愈战愈勇' then
        local gain = def.quality_values[q_idx]
        return {'pet_system.skill_' .. key .. '_desc', gain}
    elseif skill_name == '夜幕' then
        local duration = def.quality_values[q_idx]
        return {'pet_system.skill_' .. key .. '_desc', duration}
    elseif skill_name == '沙虫炮塔' then
        local count = def.quality_values[q_idx]
        return {'pet_system.skill_' .. key .. '_desc', count}
    elseif skill_name == '沙虫召唤' then
        local q_val = def.quality_values[q_idx]
        return {'pet_system.skill_' .. key .. '_desc', {'pet_system.quality_' .. (q_val or 1)}}
    elseif skill_name == '成群结队' then
        local count = def.quality_values[q_idx]
        return {'pet_system.skill_' .. key .. '_desc', count}
    elseif skill_name == '战争红利' then
        local coins = math.floor(pet.attack * def.quality_values[q_idx])
        return {'pet_system.skill_' .. key .. '_desc', coins}
    elseif skill_name == '无人机掩护' then
        local count = def.quality_values[q_idx]
        return {'pet_system.skill_' .. key .. '_desc', count}
    elseif skill_name == '决死冲锋' then
        local duration = def.quality_values[q_idx]
        return {'pet_system.skill_' .. key .. '_desc', duration}
    elseif skill_name == '再生' then
        local pct = def.quality_values[q_idx]
        local heal = math.ceil(pet.max_hp * pct / 100)
        return {'pet_system.skill_' .. key .. '_desc', pct, heal}
    elseif skill_name == '荆棘' then
        local pct = def.quality_values[q_idx]
        local dmg = math.floor(pet.attack * pct / 100)
        return {'pet_system.skill_' .. key .. '_desc', pct, dmg}
    elseif skill_name == '环形火山' then
        local target_count = def.quality_values[q_idx]
        local dmg = math.floor(pet.attack * 1.5 * 0.2)
        return {'pet_system.skill_' .. key .. '_desc', target_count, dmg}
    elseif skill_name == '减速弹幕' then
        local count = def.quality_values[q_idx]
        return {'pet_system.skill_' .. key .. '_desc', count}
    elseif skill_name == '军火商' then
        local mult = def.quality_values[q_idx]
        return {'pet_system.skill_' .. key .. '_desc', mult}
    elseif skill_name == '工业家' then
        local mult = def.quality_values[q_idx]
        return {'pet_system.skill_' .. key .. '_desc', mult}
    elseif skill_name == '科研助手' then
        local points = def.quality_values[q_idx]
        return {'pet_system.skill_' .. key .. '_desc', points}
    elseif skill_name == '虫咬' then
        local targets = def.quality_values[q_idx]
        local dmg_pct = 5
        return {'pet_system.skill_' .. key .. '_desc', targets, dmg_pct}
    elseif skill_name == '吐口水' then
        return {'pet_system.skill_' .. key .. '_desc'}
    elseif skill_name == '蠕虫能量' then
        local targets = def.quality_values[q_idx]
        return {'pet_system.skill_' .. key .. '_desc', targets, 10}
    elseif skill_name == '支援光环' then
        local pct = def.quality_values[q_idx]
        return {'pet_system.skill_' .. key .. '_desc', pct}
    elseif skill_name == '虫群召唤' then
        return {'pet_system.skill_' .. key .. '_desc'}
    elseif skill_name == '火遁' then
        local dmg = math.floor(pet.attack * def.quality_values[q_idx])
        local min_dmg = math.floor(dmg * 0.3)
        return {'pet_system.skill_' .. key .. '_desc', dmg, min_dmg}
    elseif skill_name == '编织者' then
        local rpg_t = RPG.get_value_from_player(player.index)
        local mana_max = (rpg_t and rpg_t.mana_max) or 100
        local coins = math.floor(mana_max * def.quality_values[q_idx] / 100)
        local count = math.floor(pet.attack * 0.1)
        if count < 1 then count = 1 end
        local pct = def.quality_values[q_idx]
        return {'pet_system.skill_' .. key .. '_desc', count, coins, pct}
    end
    return nil
end

-- 获取技能显示名称（返回 LocalisedString）
function Public.get_skill_display_name(name)
    local key = skill_locale_keys[name]
    if not key then return name end
    return {'pet_system.skill_' .. key}
end

-- ============================================================
-- 宠物专属技能分配
-- ============================================================

-- 根据宠物类型名判断所属家族
-- 返回: 'biter' / 'spitter' / 'wriggler' / 'strafer' / 'stomper' 或 nil
local function get_pet_family(type_name)
    if type_name:find('biter') and not type_name:find('pentapod') then
        return 'biter'
    elseif type_name:find('spitter') then
        return 'spitter'
    elseif type_name:find('wriggler') then
        return 'wriggler'
    elseif type_name:find('strafer') then
        return 'strafer'
    elseif type_name:find('stomper') then
        return 'stomper'
    end
    return nil
end

-- 专属技能名映射（family → skill_name）
local exclusive_skill_map = {
    biter    = '虫咬',
    spitter  = '吐口水',
    wriggler = '蠕虫能量',
    strafer  = '支援光环',
    stomper  = '虫群召唤',
}

-- 给宠物分配专属技能（在宠物创建时调用）
-- 将专属技能放在技能槽第1位，品质等于宠物品质
function Public.assign_exclusive_skill(pet)
    local family = get_pet_family(pet.type)
    if not family then return false end
    local skill_name = exclusive_skill_map[family]
    if not skill_name then return false end
    pet.skills[1] = {name = skill_name, quality = pet.quality}
    return true
end

return Public
