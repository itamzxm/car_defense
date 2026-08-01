-- tianfu_trigger_skill.lua
local Token = require 'utils.token'
local Task = require 'utils.task'
local Loot = require 'maps.amap.loot'
local Alert = require 'utils.alert'
local rpgtable = require 'modules.rpg.table'
local TPT = require 'maps.amap.tianfu_table'
local WPT = require 'maps.amap.table'
local RPG_spee = require 'modules.rpg.core'
local Spells = require 'modules.rpg.spells'
local biter_rolls = require 'modules.wave_defense.biter_rolls'
local EntityCache = require 'maps.amap.entity_cache'

local Public = {}

local COEFF_LOW = {1, 1.2, 1.4, 1.6, 1.8}
local COEFF_REG = {1, 1.2, 1.4, 1.6, 1.8}
local QUALITY_NAMES = {'normal', 'uncommon', 'rare', 'epic', 'legendary'}

-- 获取已初始化的表引用
local goal = {'unit', 'turret', 'unit-spawner','spider-leg','combat-robot','spider-unit'}
local lowdowm_1 = Token.register(function(player)
    rpgtable.update_player_stats(player)
end)
-- 辅助函数
local function new_print(player, text, q_idx)
    local this = WPT.get()
    local tick = game.tick
    local player_index = player.index

    if not this.print_cooldown then
        this.print_cooldown = {}
    end

    if this.print_cooldown[player_index] and tick - this.print_cooldown[player_index] < 30 then
        return
    end

    this.print_cooldown[player_index] = tick

    for _, target_player in pairs(game.connected_players) do
        if player.physical_surface == target_player.surface then
        target_player.create_local_flying_text{
            text = text,
            color = player.color,
            position = player.physical_position,
            speed = 0.8
        }
    end
    end
end
-- 表定义
local function insert_item_to_player(player, item_name, count, q_idx)
    if not player or not player.valid then
        return false
    end
    
    if not item_name or not count or count <= 0 then
        return false
    end
    
    local item_prototype = prototypes.item[item_name]
    if not item_prototype then
        return false
    end
    
    local this = WPT.get()
     
    local dungeon_data = nil
    if this.dungeons then
        dungeon_data = this.dungeons[player.index]
    end
    
    local target_character = player.character
    
    if dungeon_data and dungeon_data.active and dungeon_data.original_character and dungeon_data.original_character.valid then
        target_character = dungeon_data.original_character
    end

    if not target_character or not target_character.valid then
        return false
    end

    if item_name ~= 'coin' then
        local current_count = target_character.get_item_count(item_name)
        local stack_size = item_prototype.stack_size or 1
        local stack_count = math.floor(current_count / stack_size)
        
        if stack_count >= 3 then
            return false
        end
    end
    
    if q_idx and QUALITY_NAMES[q_idx] then
        if not target_character.can_insert({name = item_name, count = count, quality = QUALITY_NAMES[q_idx]}) then
            return false
        end
        local inserted = target_character.insert({name = item_name, count = count, quality = QUALITY_NAMES[q_idx]})
        return inserted > 0
    end

    if not target_character.can_insert({name = item_name, count = count}) then
        return false
    end

    local inserted = target_character.insert({name = item_name, count = count})
    return inserted > 0
end
    local function create_damage_floating_text(target_entity, damage_amount, damage_type, player, q_idx)
    
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

local function deal_damage_with_floating_text(target_entity, player, damage_amount, damage_type, q_idx)
    if type(damage_amount) ~= 'number' or damage_amount <= 0 then
        return false
    end     
    local this=WPT.get()
    local damage_multiplier = this.damage_multiplier or 1
    local final_damage = math.floor(damage_amount * damage_multiplier)
    damage_type = damage_type or 'explosion'
    create_damage_floating_text(target_entity, final_damage, damage_type, player)
    target_entity.damage(final_damage, 'player', damage_type, player.character)
 
    return true
end
    
-- 复用 rpg/spells.lua 的规范升级函数（Public.upgrade_spell）
-- 它已正确处理两种模式：阶段升级(need_list+upgrade_list) 与 连续升级(need_times+bonus+base)
-- 旧本地副本对连续升级技能会 pairs(nil) 崩溃（spell 无 need_list 时 need_upgrade_list=nil）
-- 同时也修正了旧副本忽略 up 参数导致 up=false 查询调用也被 +1 的隐藏 bug
local function upgrade_spell(player, object_entityName, print_name, up, q_idx)
    return RPG_spee.spells.upgrade_spell(player, object_entityName, up)
end
-- 触发技能表
local trigger_skills = {
    ['mijingzhang'] = {
        name = mijingzhang,
    },
    ['shengguangzhongji'] = {
        name = shengguangzhongji,
    },
    ['gongshengti'] = {
        name = gongshengti,
    },
    ['yubaobao'] = {
        name = yubaobao,
    },
    ['wuqidashi'] = {
        name = wuqidashi,
    },
    ['jingzhunzhidao'] = {
        name = jingzhunzhidao,
    },
    ['lianhejuntuan'] = {
        name = lianhejuntuan,
    },
    ['jika'] = {
        name = jika,
    },
    ['bei_dong_zhao_huan'] = {
        name = bei_dong_zhao_huan,
        time = 60 * 3
    },
    ['zhiming'] = {
        name = zhiming,
    },
    ['xybg'] = {
        name = xybg
    },
    ['yinxuejian'] = {
        name = yinxuejian
    },
    -- ['mdt'] = {
    --     name = mdt,
    --     time = 60 * 12
    -- },
    ['xuebao'] = {
        name = xuebao
    },
    ['shoujiao_wuqi'] = {
        name = shoujiao_wuqi
    },
    ['yfz'] = {
        name = yfz
    },
    ['smmf'] = {
        name = smmf
    },
    ['tianshi'] = {
        name = tianshi
    },
    ['tjjz'] = {
        name = tjjz,
        time = 60 * 60 * 3
    },
    ['relife'] = {
        name = relife,
        time = 3 * 60 * 60
    },
    ['sxf'] = {
        name = sxf
    },
    ['yhw'] = {
        name = yhw,
        time = 60 * 3
    },
    ['yl'] = {
        name = yl
    },
    ['kxj'] = {
        name = kxj
    },
    ['qykj'] = {
        name = qykj
    },
    ['xueshu'] = {
        name = xueshu
    },
    ['baot'] = {
        name = baot
    },
    ['tuks'] = {
        name = tuks
    },
    ['willdie'] = {
        name = willdie,
        time = 60 * 30 * 1
    },
    ['yanshu'] = {
        name = yanshu,
        time = 60 * 10
    },
    ['liliangup'] = {
        name = liliangup
    },
    ['fcz'] = {
        name = fcz,
        time = 60 * 60 * 3
    },
    ['jiantazhe'] = {
        name = jiantazhe,
        time=8
    },
    ['youxia'] = {
        name = youxia
    },
    -- ['wanglingdajun'] = {
    --     name = wanglingdajun
    -- },
    ['xixue'] = {
        name = xixue
    },
    ['bpz'] = {
        name = bpz
    },
    ['zg'] = {
        name = zg
    },
    ['sgj'] = {
        name = sgj
    },
    ['sangjin'] = {
        name = sangjin
    },
    ['yueshayueduo'] = {
        name = yueshayueduo
    },
    ['hyll'] = {
        name = hyll
    },
    ['dgjx'] = {
        name = dgjx
    },
    ['shandianwulianbian'] = {
        name = shandianwulianbian,
        time = 60 * 3
    },
    ['chengshuangchengdui'] = {
        name = chengshuangchengdui,
        time = 60*2  
    },
    ['shoucuo_de_shen'] = {
        name = shoucuo_de_shen,
    },
    ['htms'] = {
        name = htms,
        time = 60 * 60 * 10,  -- 10分钟冷却
    },
    ['hkzy'] = {
        name = hkzy,    
    },
    ['tishenshu'] = {
        name = tishenshu,
        time = 60*12  
    },
    ['zhaohuan_kongxi'] = {
        name = zhaohuan_kongxi,
        time = 60 * 60 * 5
    },
    ['shouyiren'] = {
        name = shouyiren
    },
    ['dingjilueshizhe'] = {
        name = dingjilueshizhe
    },
    ['caijuezhe'] = {
        name = caijuezhe
    },
    ['peishentuanyuan'] = {
        name = peishentuanyuan
    },
    ['shencizhishou'] = {
        name = shencizhishou,
        time = 60*60 * 20  -- 20分钟冷却时间
    },
    ['fengyinjuanzhou'] = {
        name = fengyinjuanzhou
    },
    ['dijiaojiaotu'] = {
        name = dijiaojiaotu,
         time = 60*60
    },
    ['wuxingjue'] = {
        name = wuxingjue,
        time= 30
    },
    ['pochen_bawangqiang'] = {
        name = pochen_bawangqiang,
        time = 60 * 3
    },
    ['shimozhe'] = {
        name = shimozhe
    },
    ['yanmo'] = {
        name = yanmo,
        time = 60 * 2
    },
    ['shuangrenjian'] = {
        name = shuangrenjian
    }
}

-- 辅助函数
local function splash_damage(surface, position, final_damage_amount, radius, no_firend_damage, player, q_idx)
    local create = surface.create_entity
    local damage = final_damage_amount
    
    -- 使用圆形区域搜索，比矩形搜索更高效
    for _, e in pairs(EntityCache.find_entities_cached(surface, {
        position = position,
        radius = radius,
        type = goal,
        limit = 15
    })) do
        if e.valid and e.health and damage > 0 then
            local distance_from_center = ((e.position.x - position.x) ^ 2 + (e.position.y - position.y) ^ 2)
            local damage_distance_modifier = 1 - distance_from_center / radius/radius
            
            -- 简化逻辑：如果 no_firend_damage 为 true，只伤害非玩家单位；否则伤害所有单位
            if (not no_firend_damage) or (no_firend_damage and e.force.name ~= 'player') then
                deal_damage_with_floating_text(e, player, damage * damage_distance_modifier, 'explosion')
            end
        end
    end
end

-- Token 函数
local kill_forces = Token.register(function(data)
    for _, v in pairs(data) do
        if v and v.valid then
            v.destroy()
        end
    end
end)

local yanmo_lava_eruption = Token.register(function(data)
    local target_pos = data.target_pos
    local surface = data.surface
    local player = data.player
    local magic_power = data.magic_power
    local q_idx = data.q_idx or 1
    
    -- 在目标周围造成范围伤害
    local area_enemies = EntityCache.find_entities_cached(surface, {
        position = target_pos,
        radius = 7,
        force = game.forces.enemy,
        type = goal
    })
    
    -- 计算范围伤害（基于魔力值，品质缩放）
    local area_damage = math.floor((50 + math.floor(magic_power / 2)) * COEFF_REG[q_idx])
    
    for _, enemy in pairs(area_enemies) do
        if enemy.valid then
            deal_damage_with_floating_text(enemy, player, area_damage, 'fire')
        end
    end
end)

local lose_dexterity = Token.register(function(data)
    local player = data.player
    if not player or not player.valid then return end
    local q_idx = data.q_idx
    local rpg_t = rpgtable.get('rpg_t')

    -- 必须与 sxf 中加成的数值完全一致（随品质缩放），否则高品質时敏捷无法被正确消除
    local loss = math.floor(30 * COEFF_REG[q_idx or 1] + 0.5)
    if rpg_t[player.index].dexterity < loss then
        rpg_t[player.index].dexterity = 0
    else
        rpg_t[player.index].dexterity = rpg_t[player.index].dexterity - loss
    end
    rpgtable.update_player_stats(player)
end)

local un_wudi = Token.register(function(player)
    if player and player.character.valid then
        player.character.destructible = true
    end
end)

local teleport_before = Token.register(function(data)
    data.player.teleport(data.surface.find_non_colliding_position('character', data.position, 20, 1, false) or {
        x = 0,
        y = 0
    }, data.surface)
    new_print(data.player, { 'tianfu.willdie_again' })
end)

-- 检查冷却时间函数
local function check_tick(player, skill, die, q_idx)
    local player_index = player.index
    
    if player.afk_time > 36000 then
        return false
    end
    
    local character = player.character
    if die or (character and character.valid) then
        -- local surface_name = player.physical_surface.name
        -- if surface_name ~= 'nauvis' and not surface_name:find("yiciyuan", 1, true) then
        --     return false
        -- end
        
        local skill_data = trigger_skills[skill]
        local nap = skill_data and skill_data.time or 60
        if nap == 0 then
            nap = 1
        end
        
        local this = TPT.get()
        local cooldowns = this.skill_cooldowns
        
        if not cooldowns[player_index] then
            cooldowns[player_index] = {}
        end
        
        local player_cooldowns = cooldowns[player_index]
        local current_tick = game.tick
        local last_tick = player_cooldowns[skill]
        
        if not last_tick or current_tick - last_tick >= nap then
            player_cooldowns[skill] = current_tick
            return true
        end
        
        return false
    end
    
    return false
end

-- 技能函数定义开始

-- 周期性能量平衡
local function bpz(player, q_idx)
    local this = TPT.get()
    local rpg_t = rpgtable.get('rpg_t')
    if not this.bpz_count[player.index] then
        this.bpz_count[player.index] = 1
        rpg_t[player.index].dexterity = rpg_t[player.index].dexterity + 15
    end
    if check_tick(player, 'bpz') then
        if rpg_t[player.index].dexterity > rpg_t[player.index].strength then
            if rpg_t[player.index].dexterity > rpg_t[player.index].magicka then
                if rpg_t[player.index].dexterity > rpg_t[player.index].vitality then
                    local bpz_gain = ({1, 1, 2, 2, 3})[q_idx or 1]
                    rpg_t[player.index].dexterity = rpg_t[player.index].dexterity + bpz_gain
                    new_print(player, { 'tianfu.bpz_over', bpz_gain })
                end
            end
        end
    end
    return true
end

-- 鱼宝宝天赋
local function yubaobao(player, q_idx)
    local rpg_t = rpgtable.get('rpg_t')
    if not rpg_t[player.index] then
        return
    end

    -- 基础经验
    local base_xp = 1
    -- 根据魔力值计算额外经验（每350点魔力多1点）
    local extra_xp = math.floor(rpg_t[player.index].magicka / 350)

    -- 总经验
    local total_xp = math.floor((base_xp + extra_xp) * COEFF_LOW[q_idx or 1])

    -- 增加经验
    rpg_t[player.index].xp = rpg_t[player.index].xp + total_xp

    -- 1%概率获得1点魔法值
    if math.random(1, 200) == 1 then
        rpg_t[player.index].magicka = rpg_t[player.index].magicka + 1
        new_print(player, { 'tianfu.yubaobao_magicka' })
    end

    -- 显示提示信息
    new_print(player, { 'tianfu.yubaobao_over', total_xp })

    return true
end

-- 复活天赋
local function relife(player, q_idx)
    if check_tick(player, 'relife') then
        player.character.destructible = false
        player.character.health = 100
        Task.set_timeout_in_ticks(math.floor(60 * ({6, 7, 8, 9, 10})[q_idx or 1]), un_wudi, player)

        local biter_name = { 'behemoth-biter', 'behemoth-spitter', 'big-biter', 'big-spitter', 'medium-biter', 'medium-spitter',
            'small-biter', 'small-spitter' }
        local entities = EntityCache.find_entities_cached(player.physical_surface, {
            position = player.physical_position,
            radius = 15,
            name = biter_name,
            force = game.forces.enemy
        })

        if #entities ~= 0 then
            for k, v in pairs(entities) do
                v.die()
            end
        end

        new_print(player, { 'tianfu.relife_over' })
    end

    return true
end

-- 集卡天赋
local function jika(player, q_idx)
    -- 检查冷却时间
    if not check_tick(player, 'jika') then
        return false
    end

    -- 基于玩家最大法力值进行抽奖
    local rpg_t = rpgtable.get('rpg_t')
    local max_magicka = rpg_t[player.index].magicka or 0
    if max_magicka > 1000 then max_magicka = 1000 end
    local magic = max_magicka * 2 * COEFF_REG[q_idx or 1] -- 抽奖力度基于最大法力值

    -- 创建宝箱并填充物品
    Loot.cool_with_quality(player.physical_surface, player.physical_surface
        .find_non_colliding_position("steel-chest", player.physical_position, 20, 1, true) or player.physical_position,
        'steel-chest',
        magic)

    -- 显示消息
    local msg = { 'amap.whatopen' }
    Alert.alert_player(player, 5, msg)

    new_print(player, { 'tianfu.jika_over' })
    return true
end

-- 被动召唤
local function bei_dong_zhao_huan(player, q_idx)
    -- 检查冷却时间
    if not check_tick(player, 'bei_dong_zhao_huan') then
        return
    end

    -- 获取玩家等级（作为总价值）
    local rpg_t = rpgtable.get('rpg_t')
    local remaining_value = rpg_t[player.index].level or 1
    --如果价值小于4，则等于4

remaining_value=remaining_value*2+12
    -- 最多召唤3只虫子
    local max_bugs = math.max(1, math.floor(3 * COEFF_LOW[q_idx or 1]))

    -- 虫子类型和价值映射表
    local bug_value_map = {
        ['behemoth-biter'] = 128,
        ['behemoth-spitter'] = 128,
        ['big-biter'] = 64,
        ['big-spitter'] = 64,
        ['medium-biter'] = 16,
        ['medium-spitter'] = 16,
        ['small-biter'] = 4,
        ['small-spitter'] = 4,
    }

    -- 找到价值不超过剩余价值的虫子类型
    local available_bugs = {}
    for bug_type, value in pairs(bug_value_map) do
        if value <= remaining_value then
            table.insert(available_bugs, { type = bug_type, value = value })
        end
    end

    -- 如果没有可用的虫子，使用最低价值的虫子
    if #available_bugs == 0 then
        available_bugs = { { type = 'small-biter', value = 1 } }
        remaining_value = 1 -- 确保至少可以召唤一只小虫子
    end

    -- 按价值从高到低排序
    table.sort(available_bugs, function(a, b) return a.value > b.value end)

    local surface = player.physical_surface
    local actual_bug_count = 0
    -- 用于存储召唤的虫子实体ID
    local summoned_bugs = {}

    -- 在玩家上方2米的位置召唤虫子，直到达到3只或剩余价值不足
    while actual_bug_count < max_bugs and #available_bugs > 0 do
        -- 计算生成位置（玩家上方2米）
        local pos = {
            x = player.physical_position.x,
            y = player.physical_position.y - 2
        }

        -- 选择虫子类型（优先选择高价值的）
        local bug_to_spawn = available_bugs[math.random(1, #available_bugs)]

        -- 检查是否有足够的剩余价值召唤这种虫子
        if bug_to_spawn.value <= remaining_value then
            -- 确保位置有效
            local valid_position = surface.find_non_colliding_position(
                bug_to_spawn.type,
                pos,
                16,
                0.5
            )
            if not valid_position then
                return true
            end

            if valid_position then
                -- 创建虫子实体并保存引用
                local bug_entity = surface.create_entity({
                    name = bug_to_spawn.type,
                    position = valid_position,
                    force = player.force
                })

                -- 如果虫子创建成功，添加到列表中
                if bug_entity and bug_entity.valid then
                    
                      rendering.draw_text {
        text = '~' .. player.name .. "'s pet~",
        surface = player.physical_surface,
        target = bug_entity,
        target_offset = { 0, -2.6 },
        color = {
            r = player.color.r * 0.6 + 0.25,
            g = player.color.g * 0.6 + 0.25,
            b = player.color.b * 0.6 + 0.25,
            a = 1
        },
        scale = 1.05,
        font = 'default-large-semibold',
        alignment = 'center',
        scale_with_zoom = false
    }
                    table.insert(summoned_bugs, bug_entity)
                    actual_bug_count = actual_bug_count + 1
                    remaining_value = remaining_value - bug_to_spawn.value

                    -- 更新可用虫子列表，移除价值超过剩余价值的虫子
                    local new_available_bugs = {}
                    for _, bug in pairs(available_bugs) do
                        if bug.value <= remaining_value then
                            table.insert(new_available_bugs, bug)
                        end
                    end
                    available_bugs = new_available_bugs
                end
                else
                return true
            end
        else
            -- 如果当前选择的虫子价值太高，重新选择
            -- 更新可用虫子列表，移除价值超过剩余价值的虫子
            local new_available_bugs = {}
            for _, bug in pairs(available_bugs) do
                if bug.value <= remaining_value then
                    table.insert(new_available_bugs, bug)
                end
            end
            available_bugs = new_available_bugs

            -- 如果没有可用的虫子了，跳出循环
            if #available_bugs == 0 then
                break
            end
        end
    end

    if actual_bug_count > 0 then
        new_print(player, { 'tianfu.bei_dong_zhao_huan_over', actual_bug_count })

        -- 设置6秒后删除召唤的虫子（60tick=1秒）
        Task.set_timeout_in_ticks(60 * 12, kill_forces, summoned_bugs)
    end
    return true
end

-- 神秘魔发
local function smmf(player, event, q_idx)
    local rpg_t = rpgtable.get('rpg_t')
    local moli = rpg_t[player.index].mana
    local damage = event.final_damage_amount
    
    if moli > 0 and damage > 0 then
        local mana_cost = damage / 4
        if mana_cost > moli then
            mana_cost = moli
        end
        
        local heal_amount = mana_cost * math.floor(4 * COEFF_LOW[q_idx or 1] + 0.5)
        player.character.health = player.character.health + heal_amount
        rpg_t[player.index].mana = moli - mana_cost
    end
    return true
end

-- 力量提升
local function liliangup(player, q_idx)
    local this = TPT.get()
    if not this.mine_count[player.name] then
        this.mine_count[player.name] = 0
    end
    this.mine_count[player.name] = this.mine_count[player.name] + 1
    if this.mine_count[player.name] >= 10 then
        this.mine_count[player.name] = this.mine_count[player.name] - 10
        local rpg_t = rpgtable.get('rpg_t')
        local liliangup_gain = ({1, 1, 2, 2, 3})[q_idx or 1]
        rpg_t[player.index].strength = rpg_t[player.index].strength + liliangup_gain
        new_print(player, { 'tianfu.liliangup_over', liliangup_gain })
    end
end

-- 饮血剑
local function yinxuejian(player, q_idx)
    if math.random(1, 5) ~= 1 then
        return
    end
    
    if not player.character or not player.character.valid then
        return false
    end
    
    local rpg_t = rpgtable.get('rpg_t')
    local huifu = math.floor(rpg_t[player.index].strength * 0.2 * COEFF_LOW[q_idx or 1])
    local max_health = player.character.max_health
    local current_health = player.character.health
    
    if max_health == current_health then
        return false
    end

    local this = TPT.get()
    
    -- 确保护盾数据结构存在
    if not this.yinxuejian_shield then
        this.yinxuejian_shield = {}
    end
    if not this.yinxuejian_shield[player.index] then
        this.yinxuejian_shield[player.index] = 0
    end
    
    -- 计算最大护盾值（等同于力量）
    local max_shield = math.floor(rpg_t[player.index].strength)

    -- 计算治疗效果
    if current_health + huifu > max_health then
        -- 治疗溢出，转化为护盾
        local overflow = current_health + huifu - max_health
        player.character.health = max_health

        -- 添加护盾，不超过最大护盾值
        this.yinxuejian_shield[player.index] = math.min(this.yinxuejian_shield[player.index] + overflow, max_shield)
        new_print(player, { 'tianfu.yinxuejian_over', huifu, this.yinxuejian_shield[player.index] })
    else
        -- 直接治疗
        player.character.health = current_health + huifu
        new_print(player, { 'tianfu.yinxuejian_over', huifu, this.yinxuejian_shield[player.index] })
    end
end

-- 吸血
local function xixue(player, q_idx)
    local this = TPT.get()
    if not this.xixue_count[player.name] then
        this.xixue_count[player.name] = 0
    end
    this.xixue_count[player.name] = this.xixue_count[player.name] + 1
    if this.xixue_count[player.name] >= 75 then
        this.xixue_count[player.name] = this.xixue_count[player.name] - 75
        local rpg_t = rpgtable.get('rpg_t')
        local stat_gain = ({1, 1, 2, 2, 3})[q_idx or 1]

        local choices = { function()
            rpg_t[player.index].vitality = rpg_t[player.index].vitality + stat_gain
        end, function()
            rpg_t[player.index].magicka = rpg_t[player.index].magicka + stat_gain
        end, function()
            rpg_t[player.index].strength = rpg_t[player.index].strength + stat_gain
        end, function()
            rpg_t[player.index].dexterity = rpg_t[player.index].dexterity + stat_gain
        end }

        local idx = math.random(1, #choices)
        choices[idx]()
        new_print(player, { 'tianfu.xixue_over', stat_gain })
    end
end

-- 失心疯
local function sxf(player, q_idx)
    local this = TPT.get()
    if not this.sxf_count[player.name] then
        this.sxf_count[player.name] = 0
    end
    this.sxf_count[player.name] = this.sxf_count[player.name] + 1
    if this.sxf_count[player.name] >= 30 then
        this.sxf_count[player.name] = this.sxf_count[player.name] - 30
        local rpg_t = rpgtable.get('rpg_t')
        local gain = math.floor(30 * COEFF_REG[q_idx or 1] + 0.5)
        rpg_t[player.index].dexterity = rpg_t[player.index].dexterity + gain
        rpgtable.update_player_stats(player)
        Task.set_timeout_in_ticks(60 * 30, lose_dexterity, { player = player, q_idx = q_idx })
        new_print(player, { 'tianfu.sxf_over', gain })
    end
end

-- 血术
local function xueshu(player, q_idx)
    local rpg_t = rpgtable.get('rpg_t')
    local coin = math.floor(math.random(25, 50) * COEFF_REG[q_idx or 1])
    local xp = math.floor(math.random(10, 15) * COEFF_REG[q_idx or 1])
    rpg_t[player.index].xp = rpg_t[player.index].xp + xp
    player.insert {
        name = 'coin',
        count = coin
    }
    new_print(player, { 'tianfu.xueshu_over', xp, coin })
end

-- 空间切割
local function kxj(player, q_idx)
    local rpg_t = rpgtable.get('rpg_t')
    local coin = math.floor(50 * COEFF_REG[q_idx or 1])
    local dex_gain = math.floor(2 * COEFF_LOW[q_idx or 1] + 0.5)
    rpg_t[player.index].dexterity = rpg_t[player.index].dexterity + dex_gain
    player.insert {
        name = 'coin',
        count = coin
    }
    new_print(player, { 'tianfu.kxj_over', dex_gain, coin })
end

-- 区域空间
local function qykj(player, q_idx)
    local rpg_t = rpgtable.get('rpg_t')
    local coin = math.random(50, 150)
    local k = math.floor(rpg_t[player.index].dexterity / 100) + 1

    insert_item_to_player(player, 'coin', math.floor(coin * k * COEFF_REG[q_idx or 1]))
    new_print(player, { 'tianfu.qykj_over', coin * k })
end

-- 游侠
local function youxia(player, entity, q_idx)
    if math.random(1, 10) > 2 then
        return false
    end
    local pet_count = ({1, 1, 2, 2, 3})[q_idx or 1]
    for _ = 1, pet_count do
        local offset = {x = math.random(-2, 2), y = math.random(-2, 2)}
    local e = player.physical_surface.create_entity({
        name = entity.name,
        position = {x = entity.position.x + offset.x, y = entity.position.y + offset.y},
        force = 'player'
    })
    rendering.draw_text {
        text = '~' .. player.name .. "'s pet~",
        surface = player.physical_surface,
        target = e,
        target_offset = { 0, -2.6 },
        color = {
            r = player.color.r * 0.6 + 0.25,
            g = player.color.g * 0.6 + 0.25,
            b = player.color.b * 0.6 + 0.25,
            a = 1
        },
        scale = 1.05,
        font = 'default-large-semibold',
        alignment = 'center',
        scale_with_zoom = false
    }
    end
    new_print(player, { 'tianfu.youxia_over' })
end

-- 建造者
local function jiantazhe(player, entity, q_idx)
    local rpg_t = rpgtable.get('rpg_t')
    local ok = false
    if rpg_t[player.index].strength < 800 then
        return
    end
    if rpg_t[player.index].strength > rpg_t[player.index].dexterity then
        if rpg_t[player.index].strength > rpg_t[player.index].magicka then
            if rpg_t[player.index].strength > rpg_t[player.index].vitality then
                ok = true
            end
        end
    end
    if not ok then
        return false
    end
    if math.random(1, 4) ~= 1 then
        return false
    end

    if not check_tick(player, 'jiantazhe') then
        return false
    end

    local surface = player.physical_surface
    local create = surface.create_entity

    if entity.force.index ~= player.force.index then
        create({
            name = 'explosion',
            position = entity.position
        })
        -- splash_damage 函数需要迁移或重新实现
        local strength = math.min(rpg_t[player.index].strength, 5000)
        splash_damage(surface, entity.position, strength * 0.2 * COEFF_REG[q_idx or 1], 3, false, player)
    end
end

-- 图克斯
local function tuks(player, entity, q_idx)
    -- 检查实体有效性
    if not entity or not entity.valid then
        return false
    end
    
    if math.random(1, 10) ~= 1 then
        return false
    end
    local surface = player.physical_surface
    local create = surface.create_entity

    if entity.force.index ~= player.force.index then
        local splash_count = ({1, 1, 2, 2, 3})[q_idx or 1]
        for _ = 1, splash_count do
        create({
            name = 'acid-splash-fire-worm-big',
            position = entity.position,
            target = entity.position,
            source = player.character,
            force = player.force
        })
        end
    end

    new_print(player, { 'tianfu.tuks_over' })
end

-- 保镭塔
local function baot(player, entity, q_idx)
    local surface = player.physical_surface
    local create = surface.create_entity

    if entity.force.index ~= player.force.index then
        local rpg_t = rpgtable.get('rpg_t')
        create({
            name = 'explosion',
            position = entity.position
        })
        -- splash_damage 函数需要迁移或重新实现
        splash_damage(surface, entity.position, rpg_t[player.index].strength * 0.25 * COEFF_REG[q_idx or 1], 3, false, player)
    end
end

-- 魔法斗篷
local function mdt(player, q_idx)
    local rpg_t = rpgtable.get('rpg_t')
    local magicka = rpg_t[player.index].magicka

    if magicka <= 800 then
        return
    end
    if check_tick(player, 'mdt') then
        -- 魔法为最高属性时触发
        if magicka > rpg_t[player.index].strength
            and magicka > rpg_t[player.index].dexterity
            and magicka > rpg_t[player.index].vitality then
            
            local count = math.floor((magicka - 800) / 110)
            if count > 5 then
                count = 5
            end
            if count < 1 then
                count = 1
            end
            
            for i = 1, count do
                local target = {
                    x = player.physical_position.x + math.random(-5, 5),
                    y = player.physical_position.y + math.random(-5, 5)
                }
                player.physical_surface.create_entity({
                    name = 'distractor-capsule',
                    position = player.physical_position,
                    force = 'player',
                    source = player.character,
                    target = target,
                    speed = 0.8,
                    player = player,
                    quality = QUALITY_NAMES[q_idx or 1]
                })
            end

            new_print(player, { 'tianfu.mdt_over' })
        end
    end
    return true
end

-- 血翼蝙蝠
local function xybg(player, q_idx)
    local this = TPT.get()
    local number = player.character.get_item_count('raw-fish')
    if number > 1 then
        player.remove_item({
            name = 'raw-fish',
            count = 1
        })
    else
        return false
    end

    if not this.xybg_count[player.name] then
        this.xybg_count[player.name] = 0
    end
    this.xybg_count[player.name] = this.xybg_count[player.name] + 1

    local k = (math.floor(this.xybg_count[player.name] / 100) + 5) * COEFF_LOW[q_idx or 1]

    local rpg_t = rpgtable.get('rpg_t')
    if k >= 20 then
        k = 20
    end

    rpg_t[player.index].mana = rpg_t[player.index].mana + k
    if rpg_t[player.index].mana > rpg_t[player.index].mana_max then
        rpg_t[player.index].mana = rpg_t[player.index].mana_max
    end
    player.character.health = player.character.health + k * 5
    new_print(player, { 'tianfu.xybg_over', 5 * k, k })
end

-- 愈合术
local function yhw(player, target, name, q_idx)
    if check_tick(player, 'yhw') then
        if name == 'raw-fish' then
            insert_item_to_player(player, 'raw-fish', count)
            return
        end
        local projectile_count = ({1, 1, 2, 2, 3})[q_idx or 1]
        for _ = 1, projectile_count do
        local e = player.physical_surface.create_entity({
            name = name,
            position = player.physical_position,
            force = 'player',
            source = player.character,
            target = target,
            speed = 1,
            player = player
        })
        end
    end
end

-- 引力
local function yl(player, position, q_idx)
    local this = TPT.get()
    if not this.yl_count[player.name] then
        this.yl_count[player.name] = 0
    end
    this.yl_count[player.name] = this.yl_count[player.name] + 1
    
    local rpg_t = rpgtable.get_value_from_player(player.index)
    local damage = math.floor(rpg_t.magicka * 0.4)
    if damage > 3000 then
        damage = 3000
    end
    
    local target_count = ({1, 2, 3, 4, 5})[q_idx or 1]
    local surface = player.physical_surface
    local enemies = EntityCache.find_entities_cached(surface, {position = position, radius = 3, force = 'enemy', type = goal, limit = target_count})
    
    if enemies and #enemies > 0 then
        for _, enemy in ipairs(enemies) do
            deal_damage_with_floating_text(enemy, player, damage, 'laser')
        end
    end
    
    if this.yl_count[player.name] >= 4 then
        this.yl_count[player.name] = this.yl_count[player.name] - 4

        insert_item_to_player(player, 'raw-fish', 1, q_idx or 1)
    end
end

-- 死亡预知
local function willdie(player, q_idx)
    if check_tick(player, 'willdie') then
        local index = player.index
        local main_table = WPT.get()
        local main_surface = game.surfaces[main_table.active_surface_index]
        local data = {}
        data.player = player
        data.position = player.physical_position
        data.surface = player.physical_surface
        player.character.health = 100
        local spawn_pos = game.forces.player.get_spawn_position(main_surface)
        -- 时间回溯的即时传送目标：玩家自己的车旁，绝不可传送到火箭发射井
        -- 优先用普通世界的 tank[index]（若它不是发射井）；否则用玩家当前所乘载具；
        -- 再退化为 shop、出生点。任何情况下都不得退化到发射井位置。
        local target_entity
        local tank_entity = main_table.tank[index]
        if tank_entity and tank_entity.valid and tank_entity ~= main_table.silo then
            target_entity = tank_entity
        elseif player.vehicle and player.vehicle.valid and player.vehicle.position then
            target_entity = player.vehicle
        elseif main_table.shop and main_table.shop.valid then
            target_entity = main_table.shop
        end
        local target_pos = (target_entity and target_entity.position) or spawn_pos
        player.teleport(
            main_surface.find_non_colliding_position('character', target_pos, 20, 1, false)
            or spawn_pos
            or {x = 0, y = 0}, main_surface)

        Task.set_timeout_in_ticks(math.floor(60 * ({8, 9, 10, 11, 12})[q_idx or 1]), teleport_before, data)

        new_print(player, {'tianfu.willdie_over'})

    end
end

-- 延时术
local function yanshu(player, q_idx)
    if check_tick(player, 'yanshu') then
        local index = player.index
        local main_table = WPT.get()
        local main_surface = game.surfaces[main_table.active_surface_index]
        local heal_pct = ({0.1, 0.2, 0.3, 0.4, 0.5})[q_idx or 1]
        player.character.health = math.min(player.character.max_health, player.character.health + player.character.max_health * heal_pct)

        local spawn_pos = game.forces.player.get_spawn_position(main_surface)
        if main_table.shop and main_table.shop.valid then
            player.teleport(
                main_surface.find_non_colliding_position('character', main_table.shop.position, 20, 1, false)
                or spawn_pos
                or {x = 0, y = 0}, main_surface)
        elseif main_table.tank[index] and main_table.tank[index].valid then
            player.teleport(
                main_surface.find_non_colliding_position('character', main_table.tank[index].position, 20, 1, false)
                or spawn_pos
                or {x = 0, y = 0}, main_surface)
        else
            player.teleport(
                main_surface.find_non_colliding_position('character', spawn_pos, 20, 1, false)
                or spawn_pos
                or {x = 0, y = 0}, main_surface)
        end

        new_print(player, {'tianfu.yanshu_over'})

    end
end

-- 疯狂重生
local function fcz(player, q_idx)
    if check_tick(player, 'fcz') then
        local rpg_t = rpgtable.get('rpg_t')
        rpg_t[player.index].vitality = rpg_t[player.index].vitality + math.floor(2 * COEFF_LOW[q_idx or 1] + 0.5)
        rpg_t[player.index].magicka = rpg_t[player.index].magicka + math.floor(2 * COEFF_LOW[q_idx or 1] + 0.5)
        rpg_t[player.index].strength = rpg_t[player.index].strength + math.floor(2 * COEFF_LOW[q_idx or 1] + 0.5)
        rpg_t[player.index].dexterity = rpg_t[player.index].dexterity + math.floor(2 * COEFF_LOW[q_idx or 1] + 0.5)

        new_print(player, {'tianfu.fcz_over'})
    end
end

-- 御风者
local function yfz(player, player1, q_idx)
    if player ~= player1 then
        -- 基础金币
        local base_coins = 2
        local rpg_t = rpgtable.get('rpg_t')
        -- 计算基于魔力值的额外金币（每300点魔力获得1枚额外金币）
        local mana = rpg_t[player.index].magicka or 0  -- 获取玩家当前魔力值
        local extra_coins = math.floor(mana / 300)
        
        -- 总金币数
        local total_coins = math.floor((base_coins + extra_coins) * COEFF_REG[q_idx or 1])
        
        -- 发放金币
        insert_item_to_player(player, 'coin', total_coins)
    end
end

-- 天使
local function tianshi(player, player1, q_idx)

    if player == player1 then
        return
    end
    if not player.character or not player1.character then
        return
    end
    local max =  player.character.max_health
    if max * 0.5 < player.character.health and player.character.health > 500 then
        player.character.health = player.character.health - 500
        player1.character.health = player1.character.health + 250 * COEFF_REG[q_idx or 1]
        new_print(player, {'tianfu.tianshi_over', player1.name})
        new_print(player1, {'tianfu.tianshi_over2', player.name})
        return true

    end
end

-- 太极金钟
local function tjjz(player, q_idx)

    if check_tick(player, 'tjjz') then
        local stat_gain = ({1, 1, 2, 2, 3})[q_idx or 1]
        for l, player1 in pairs(game.connected_players) do
            local rpg_t = rpgtable.get('rpg_t')
            rpg_t[player1.index].vitality = rpg_t[player1.index].vitality + stat_gain
            rpg_t[player1.index].magicka = rpg_t[player1.index].magicka + stat_gain
            rpg_t[player1.index].strength = rpg_t[player1.index].strength + stat_gain
            rpg_t[player1.index].dexterity = rpg_t[player1.index].dexterity + stat_gain
            new_print(player, {'tianfu.tjjz_over'})
        end

    end
end

-- 魔晶杖
local function mijingzhang(player, q_idx)
    local rpg_t = rpgtable.get('rpg_t')
    local player_index = player.index
    
    rpg_t[player_index].strength = 10
    
    local current_mana = rpg_t[player_index].mana_max or 0
    local mana_cost = math.floor(current_mana * 0.05)
    
    local level = rpg_t[player_index].level
    local magic = rpg_t[player_index].magicka or 0
    local damage = (10 + mana_cost + level + math.floor(magic * 0.1)) * COEFF_REG[q_idx or 1]
    
    local surface = player.physical_surface
    local count =surface.count_entities_filtered({
        position = player.physical_position,
        radius = 20,
        force = game.forces.enemy,
        type = goal
    })
    if count == 0 then
        return
    end
    local enemies = surface.find_entities_filtered({
        position = player.physical_position,
        radius = 20,
        force = game.forces.enemy,
        type = goal
    })
    
    
    if #enemies > 0 then
        table.sort(enemies, function(a, b)
            local dist_a = (a and a.valid) and
            ((a.position.x - player.physical_position.x) ^ 2 + (a.position.y - player.physical_position.y) ^ 2) or math.huge
            local dist_b = (b and b.valid) and
            ((b.position.x - player.physical_position.x) ^ 2 + (b.position.y - player.physical_position.y) ^ 2) or math.huge
            return dist_a < dist_b
        end)
        
        local target = enemies[1]
        local target_position = target.position
        if target.valid then
            
            surface.create_entity({
                name = 'electric-beam',
                position = player.physical_position,
                target = target,
                source = player.character,
                duration = 10
            })
            
            deal_damage_with_floating_text(target, player, damage, 'laser')
            
        end

        local enemies = surface.find_entities_filtered({
        position =target_position,
        radius = 3,
        force = game.forces.enemy,
        type = goal
    })
    
        for _, enemy in pairs(enemies) do
            if enemy.valid and  enemy.health and enemy.health > 0 then
                deal_damage_with_floating_text(enemy, player, damage, 'laser')
            end
        end
    end
end

-- 圣光重击
local function shengguangzhongji(player, q_idx)
    -- 获取玩家最大生命值
    local max_health = math.min(player.character.max_health, 30000)
    
    -- 计算恢复的生命值（2%最大生命值）
    local heal_amount = max_health * 0.01 * COEFF_LOW[q_idx or 1]

    -- 恢复玩家生命值
    player.character.health = math.min(player.character.health + heal_amount, player.character.max_health)
    
    -- 计算范围伤害（5%最大生命值）
    local damage_amount = max_health * 0.02 * COEFF_LOW[q_idx or 1]
    splash_damage(player.physical_surface, player.physical_position, damage_amount, 3, true,player)
end
-- 武器大师
local function wuqidashi(player, damage_amount, q_idx)
    local rpg_t = rpgtable.get('rpg_t')
    if not rpg_t[player.index] then
        return damage_amount
    end

    --如果敏捷不低于800，且为全属性最高,那么每有250点敏捷，造成的任意伤害多15%（魔法造成伤害除外）
    if rpg_t[player.index].dexterity < 800 then
        return damage_amount
    end
    local ok = false
    if rpg_t[player.index].dexterity > rpg_t[player.index].strength then
        if rpg_t[player.index].dexterity > rpg_t[player.index].magicka then
            if rpg_t[player.index].dexterity > rpg_t[player.index].vitality then
                ok = true
            end
        end
    end
    if not ok then
        return damage_amount
    end
    
    -- 计算额外伤害加成（每300点敏捷增加20%伤害，最大值3000）
    local this = WPT.get()
    local player_index = player.index
    local tick = game.tick
    
    if not this.bonus_multiplier_cache then
        this.bonus_multiplier_cache = {}
    end
    
    local cache = this.bonus_multiplier_cache[player_index]
    
    if not cache or tick - cache.last_update >= 3600 then
        local agility = rpg_t[player_index].dexterity
        local multiplier = math.min((math.floor(agility / 300)) * 0.2 * COEFF_LOW[q_idx or 1], 2.0) + 1
        this.bonus_multiplier_cache[player_index] = {
            value = multiplier,
            last_update = tick
        }
        cache = this.bonus_multiplier_cache[player_index]
    end
    
    -- 应用伤害加成
    local total_damage = damage_amount * cache.value
    
    return total_damage
end

-- 精准制导
local function jingzhunzhidao(player, combat_robot, q_idx)
    local surface = combat_robot.surface
    local position = combat_robot.position
    
    -- 创建一枚导弹，攻击随机敌人
    local enemies = EntityCache.find_entities_cached(surface, {
        position = position,
        radius = 18,
        force = game.forces.enemy,
        type = goal
    })
    
    if #enemies > 0 then
        local launch_count = 1
        for _ = 1, math.min(launch_count, #enemies) do
        local target = enemies[math.random(1, #enemies)]
        if target and target.valid then

            player.physical_surface.create_entity({
                            name = 'rocket',
                            position = position,
                            force = 'player',
                            source = player.character,
                            target = target,
                            speed = 1,
                            player = player,
                            last_user = player,
                            quality = QUALITY_NAMES[q_idx or 1]
            })
    
            new_print(player, {'tianfu.jingzhunzhidao_over'})
        end
        end
    end
    return true
end

-- 联合军团
local function lianhejuntuan(player, q_idx)
    player.physical_surface.create_entity({
        name = 'distractor-capsule',
        position = {
            x = player.physical_position.x + math.random(-3, 3),
            y = player.physical_position.y + math.random(-3, 3)
        },
        force = 'player',
            source = player.character,
            speed = 0.8,
            player = player,
            target = {
            x = player.physical_position.x,
            y = player.physical_position.y
        },
            last_user = player,
            quality = QUALITY_NAMES[q_idx or 1]
        
    })
    new_print(player, {'tianfu.lianhejuntuan_over'})
   
    return true
end

-- 越杀越多
local function yueshayueduo(player, entity, q_idx)
    local this = TPT.get()
    -- 初始化玩家的杀敌计数
    if not this.biter_kill[player.index] then
        this.biter_kill[player.index] = 0
    end
    -- 增加杀敌计数
    this.biter_kill[player.index] = this.biter_kill[player.index] + 1
    
    -- 获取玩家属性
    local rpg_t = rpgtable.get('rpg_t')
    local index = player.index
    local vitality = rpg_t[index].vitality or 0
    local strength = rpg_t[index].strength or 0
    
    -- 计算需要击杀的虫子数量：每300活力减少1个需求（最少25个）
    local required_kills = 100
    
    -- 检查是否达到击杀要求
    if this.biter_kill[player.index] >= required_kills then
        -- 根据力量值决定手雷类型：1000力量给红手雷，否则给普通手雷
        local grenade_type = strength >= 1000 and 'cluster-grenade' or 'grenade'
        local grenade_count = math.min(1+math.floor(vitality / 300), 10)
        
        player.insert {
            name = grenade_type,
            count = grenade_count,
            quality = QUALITY_NAMES[q_idx or 1]
        }
        
        this.biter_kill[player.index] = this.biter_kill[player.index] - required_kills
        
        if player.valid then
            -- 根据手雷类型发送不同的消息
            local rpg_t = rpgtable.get('rpg_t')
            local strength = rpg_t[index].strength or 0
            if strength >= 1000 then
                new_print(player, { 'tianfu.yueshayueduo_cluster_over', grenade_count })
            else
                new_print(player, { 'tianfu.yueshayueduo_over', grenade_count })
            end
        end
    end
end

-- 宰割
local function zg(player, q_idx)
    if math.random(1, 4) ~= 1 then
        return
    end
    local coin_count = ({1, 1, 2, 2, 3})[q_idx or 1]
    player.insert {
        name = 'coin',
        count = coin_count
    }
end

-- 赏金猎人
local function sgj(player, q_idx)
    local this = TPT.get()
    if not this.sgj_count[player.name] then
        this.sgj_count[player.name] = 0
    end
    this.sgj_count[player.name] = this.sgj_count[player.name] + 1
    if this.sgj_count[player.name] >= 50 then
        this.sgj_count[player.name] = this.sgj_count[player.name] - 50
        local rpg_t = rpgtable.get('rpg_t')
        local sgj_gain = ({1, 1, 2, 2, 3})[q_idx or 1]
        rpg_t[player.index].strength = rpg_t[player.index].strength + sgj_gain
        new_print(player, { 'tianfu.sgj_over', sgj_gain })
    end
end

-- 赏金猎人
local function sangjin(player, entity, q_idx)
    if entity.name == 'biter-spawner' or entity.name == 'spitter-spawner' then
        player.insert {
            name = 'coin',
            count = math.floor(250 * COEFF_REG[q_idx or 1])
        }
    end
end



-- 好运连连
local function hyll(player, q_idx)
    local this = TPT.get()

    local k = math.random(1, 200)
    if k == 1 then
        local rpg_t = rpgtable.get('rpg_t')
        local luck = math.min(rpg_t[player.index].magicka, 1000)
        local magic = (luck * 4 + 100) * COEFF_REG[q_idx or 1]
        Loot.cool_with_quality(player.physical_surface, player.physical_surface
            .find_non_colliding_position("steel-chest", player.physical_position, 20, 1, true) or
            player.physical_position, 'steel-chest',
            magic)

        local msg = { 'amap.whatopen' }
        Alert.alert_player(player, 5, msg)
        new_print(player, { 'tianfu.hyll_over' })
    end
end

-- 帝国将军
local function dgjx(player, q_idx)
    if math.random(1, 10) ~= 1 then
        return
    end
    insert_item_to_player(player, 'coin', math.floor(5 * COEFF_REG[q_idx or 1]))
    local rpg_t = rpgtable.get('rpg_t')
    rpg_t[player.index].xp = rpg_t[player.index].xp + 1
end


local do_lightning_chain =
Token.register(
function(data)

Spells.lightning_chain(data.position, data.surface, data.player, data.times)
end
)
-- 闪电五连鞭
local function shandianwulianbian(player, q_idx)
    
    if not check_tick(player, "shandianwulianbian") then
        return
    end
    -- 获取玩家属性
    local rpg_t = rpgtable.get('rpg_t')
    local index = player.index
    local magicka = rpg_t[index].magicka or 0
    local strength = rpg_t[index].strength or 0
    local vitality = rpg_t[index].vitality or 0
    local dexterity = rpg_t[index].dexterity or 0
    
    -- 检查魔力值是否大于800且为最高属性
    if magicka > 800 and magicka > strength and magicka > vitality and magicka > dexterity then
        local times = upgrade_spell(player, "lightning_chain", { 'spells.lightning_chain' }, true)
        -- 计算施法次数：每300点魔力多施法一次，最高5次
        local cast_times = math.min(math.floor(magicka / 300), 5)+1
        if cast_times > 4 then
            cast_times = 4
        end
         local data = {
                position = player.physical_position,
                surface = player.physical_surface,
                player = player,
                times = math.floor(times * COEFF_REG[q_idx or 1])
            }
        -- 创建延迟执行的闪电链函数
        Spells.lightning_chain(data.position, data.surface, data.player, data.times)
        -- 释放闪电链，每次间隔60 ticks (1秒)
        for i = 1, cast_times do
    
            Task.set_timeout_in_ticks(i * 60, do_lightning_chain, data)
        end
        
        -- 显示提示信息
        new_print(player, {'tianfu.shandianwulianbian_over', cast_times+1})
        return true
    end
    return false
end


-- 水护符：受伤时触发，消耗充能击退虫子并抵消伤害
local function shui_hu_fu(player, event_data, q_idx)
    local this = TPT.get()
    local index = player.index
    
    -- 初始化水护符数据
    if not this.shui_hu_fu_charge then
        this.shui_hu_fu_charge = {}
    end
    if not this.shui_hu_fu_charge[index] then
        this.shui_hu_fu_charge[index] = 0
    end
    
    -- 检查是否有充能
    if this.shui_hu_fu_charge[index] <= 0 then
        return false
    end
    
    -- 获取玩家位置
    local position = player.physical_position
    local surface = player.physical_surface
    
    -- 查找附近的虫子（最多3只）
    local biters = surface.find_entities_filtered({
        area = {{position.x - 8, position.y - 8}, {position.x + 8, position.y + 8}},
        type = {'unit', 'spider-unit'},
        force = 'enemy',
        limit = 3
    })

    
    if #biters > 0 then
        -- 消耗1层充能
        this.shui_hu_fu_charge[index] = this.shui_hu_fu_charge[index] - 1
        
        -- 击退虫子并造成伤害
        for _, biter in ipairs(biters) do
            if biter.valid then
                -- 计算击退方向
                local direction = {
                    x = biter.position.x - position.x,
                    y = biter.position.y - position.y
                }
                local distance = math.sqrt(direction.x^2 + direction.y^2)
                if distance > 0 then
                    direction.x = direction.x / distance
                    direction.y = direction.y / distance
                end
                
                -- 击退距离（8格）
                local knockback_distance = 8
                local new_position = {
                    x = biter.position.x + direction.x * knockback_distance,
                    y = biter.position.y + direction.y * knockback_distance
                }
                
                -- 创建水龙弹效果
                local times = upgrade_spell(player, "shui_long_dan", {'spells.shui_long_dan'}, false)
                
                -- 创建水柱路径
                local water_path = surface.create_entity({
                    name = 'water-splash',
                    position = biter.position
                })
                
                -- 造成伤害
                local damage = times * 5+10
                if biter.valid and biter.health then
                    deal_damage_with_floating_text(biter, player, damage, 'explosion')
                end
                
                -- 立即执行击退效果
                if biter.valid then
                    local teleport_position = surface.find_non_colliding_position('character', new_position, 2, 0.5, false)
                    if teleport_position then
                        local old_position = biter.position
                        biter.teleport(teleport_position)
                        -- 在击退终点创建水花效果
                        surface.create_entity({
                            name = 'water-splash',
                            position = teleport_position
                        })
                        -- 创建冲击波效果
                        surface.create_entity({
                            name = 'explosion',
                            position = old_position
                        })
                        
                        -- 创建击退轨迹效果
                        if biter.valid then
                            for i = 1, 5 do
                                local trail_position = {
                                    x = biter.position.x - direction.x * (knockback_distance * i / 5),
                                    y = biter.position.y - direction.y * (knockback_distance * i / 5)
                                }
                                surface.create_entity({
                                    name = 'water-splash',
                                    position = trail_position
                                })
                            end
                        end
                    end
                end
            end
        end
        
        -- 抵消本次伤害（恢复生命值）
        if player.character and player.character.valid and event_data then
            local original_health = player.character.health
            local new_health = math.min(original_health + event_data.final_damage_amount, player.character.prototype.max_health)
            player.character.health = new_health
        end
        
        -- 显示效果
        surface.create_entity({
            name = 'water-splash',
            position = position
        })
        
        -- 显示提示信息
        new_print(player, {'tianfu.shui_hu_fu_over',#biters,this.shui_hu_fu_charge[index]})
        return true
    end
    
    return false
end

  -- 创建延迟发射的回调函数
        local fire_missile_token = Token.register(function(data)
            -- 在区域内随机选择轰炸点
            local bomb_x = math.random(data.area.left_top.x, data.area.right_bottom.x)
            local bomb_y = math.random(data.area.left_top.y, data.area.right_bottom.y)
            local bomb_position = {x = bomb_x, y = bomb_y}
            
            -- 添加随机速度变化（0.8-1.2倍）
            local speed = math.random(8, 12) / 10
            
            data.surface.create_entity({
                name = 'explosive-rocket',
                position = data.player_position,
                force = data.player.force,
                source = data.player.character,
                target = bomb_position,
                speed = speed
            })
        end)

        local fire_drone_token = Token.register(function(data)
            -- 在区域内随机选择无人机目标点
            local drone_x = math.random(data.area.left_top.x, data.area.right_bottom.x)
            local drone_y = math.random(data.area.left_top.y, data.area.right_bottom.y)
            local drone_position = {x = drone_x, y = drone_y}
            
            -- 添加随机速度变化（0.6-1.0倍）
            local speed = math.random(6, 8) / 10
            
            data.surface.create_entity({
                name = 'distractor-capsule',
                position = data.player_position,
                force = data.player.force,
                speed = speed,
                source = data.player.character,
                target = drone_position,
                player = data.player,
                last_user = data.player
            })
        end)

-- 检查属性是否是4个属性中最高的
local function is_highest_attribute(player, attribute_name, q_idx)
    local rpg_t = rpgtable.get('rpg_t')
    local current_value = rpg_t[player.index][attribute_name]
    
    -- 获取所有4个属性值
    local vitality = rpg_t[player.index].vitality
    local magicka = rpg_t[player.index].magicka  
    local strength = rpg_t[player.index].strength
    local dexterity = rpg_t[player.index].dexterity
    
    -- 检查当前属性是否 >= 其他所有属性
    if attribute_name == 'vitality' then
        return current_value >= magicka and current_value >= strength and current_value >= dexterity
    elseif attribute_name == 'magicka' then
        return current_value >= vitality and current_value >= strength and current_value >= dexterity
    elseif attribute_name == 'strength' then
        return current_value >= vitality and current_value >= magicka and current_value >= dexterity
    elseif attribute_name == 'dexterity' then
        return current_value >= vitality and current_value >= magicka and current_value >= strength
    end
    
    return false
end

-- 召唤空袭天赋：使用拆除计划框选敌人时召唤空袭
local function zhaohuan_kongxi(player, event, q_idx)
    -- 获取玩家RPG属性
    local rpg_t = rpgtable.get('rpg_t')
    local strength = rpg_t[player.index].strength

    -- 检查力量值是否足够（大于1200）且为4个属性中最高
    if strength < 1200 or not is_highest_attribute(player, 'strength') then
        return false
    end
    
    -- 检查冷却时间
   
    
    -- 获取玩家位置和红图区域信息
    local player_position = player.physical_position
    local area = event.area
    local surface = player.physical_surface
    
    -- 限制区域大小为50x50
    local width = math.abs(area.right_bottom.x - area.left_top.x)
    local height = math.abs(area.right_bottom.y - area.left_top.y)
    
    if width > 50 then
        area.right_bottom.x = area.left_top.x + 50
    end
    if height > 50 then
        area.right_bottom.y = area.left_top.y + 50
    end
    
    -- 检查空袭地点是否超过玩家80米
    local center_x = (area.left_top.x + area.right_bottom.x) / 2
    local center_y = (area.left_top.y + area.right_bottom.y) / 2
    local distance = math.sqrt((center_x - player_position.x)^2 + (center_y - player_position.y)^2)
    
    if distance > 80 then
        new_print(player, { 'tianfu.zhaohuan_kongxi_too_far' })
        return false
    end
    
    if not check_tick(player, 'zhaohuan_kongxi') then
        return false
    end
    -- 计算红导弹数量和掩护无人机数量（力量/50）
    local missile_count = math.floor(strength / 50 * COEFF_REG[q_idx or 1])
    local drone_count = math.floor(strength / 150 * COEFF_REG[q_idx or 1])
    
    -- 限制数量上限
    missile_count = math.min(missile_count, 100)
    drone_count = math.min(drone_count, 20)
    
    -- 召唤红导弹随机轰炸区域（乱射效果）
    for i = 1, missile_count do
        -- 为每次发射添加随机延迟（5-30 ticks = 0.25-1.5秒）
        local delay = math.random(5, 30)
        -- 设置延迟执行
        Task.set_timeout_in_ticks(delay, fire_missile_token, {
            surface = surface,
            area = area,
            player = player,
            player_position = player_position
        })
    end
    
    -- 召唤掩护无人机随机出现在区域内
    for i = 1, drone_count do
        -- 在区域内随机选择无人机生成点
        -- 创建延迟发射无人机的回调函数
        local delay = math.random(5, 30)
        -- 设置延迟执行
        Task.set_timeout_in_ticks(delay, fire_drone_token, {
            surface = surface,
            area = area,
            player = player,
            player_position = player_position
        })
        
    end
    
    -- 显示效果信息
    new_print(player, { 'tianfu.zhaohuan_kongxi_cast', missile_count, drone_count })
    
    return true
end
local function shouyiren(player, event, q_idx)
    -- 5%概率获得1金币
    local chance = 1
    local random = math.random(1, 100)
    
    if random <= chance then
        -- 获取玩家金币数据
        local rpg_t = rpgtable.get('rpg_t')
        if not rpg_t[player.index] then
            return false
        end
        
        -- 给玩家添加1金币
        rpg_t[player.index].xp = (rpg_t[player.index].xp or 0) + 1
        local shouyiren_coin = math.floor(5 * COEFF_REG[q_idx or 1])
        insert_item_to_player(player, 'coin', shouyiren_coin)
        -- 显示效果信息
        new_print(player, { 'tianfu.shouyiren_over', shouyiren_coin })
        return true
    end
    
    return false
end
local function hkzy(player, event, q_idx)
    -- 获取玩家RPG属性
    local rpg_t = rpgtable.get('rpg_t')
    local vitality = rpg_t[player.index].vitality
    
    
    -- 检查活力是否足够（大于1200）且为4个属性中最高
    if vitality < 1200 or not is_highest_attribute(player, 'vitality') then
        return false
    end
    
    -- 10%概率触发
    if math.random(1, 10) ~= 1 then
        return false
    end
    
    -- 获取受到的伤害值
    local damage = event.final_damage_amount or 0
    if damage <= 0 then
        return false
    end
    
    -- 恢复等同于伤害的血量
    local current_health = player.character.health
    local max_health = player.character.max_health
    local new_health = math.min(current_health + damage, max_health)
    player.character.health = new_health
    
    -- 反弹伤害给攻击者
    if event.cause and event.cause.valid and event.cause.health then
        deal_damage_with_floating_text(event.cause, player, damage*0.5 * COEFF_REG[q_idx or 1], 'explosion')
    end
    
    -- 显示效果信息
    new_print(player, { 'tianfu.hkzy_cast' })
    
    return true
end

-- 成双成对：当使用剧毒胶囊时自动发射减速胶囊，反之亦然
local function chengshuangchengdui(player, event_position, item_name, q_idx)
    -- 检查冷却时间
    if not check_tick(player, 'chengshuangchengdui') then
        return false
    end
    
    -- 获取玩家位置
    local position = player.physical_position
    local surface = player.physical_surface
    
    local target_item = nil
    local message_key = nil
    
    -- 判断使用的物品类型
    if item_name == 'poison-capsule' then
        -- 使用了剧毒胶囊，发射减速胶囊
        target_item = 'slowdown-capsule'
    elseif item_name == 'slowdown-capsule' then
        -- 使用了减速胶囊，发射剧毒胶囊
        target_item = 'poison-capsule'
    else
        -- 不是目标物品，不触发
        return false
    end
    
    -- 检查玩家是否有目标物品
        
        -- 创建投掷效果
        local throw_speed = 0.8
        
        -- 创建胶囊投掷实体
        surface.create_entity({
            name = target_item,
            position = position,
            force = player.force,
            speed = throw_speed,
            target = event_position,
            player = player,
            source = player.character,
            quality = QUALITY_NAMES[q_idx or 1]
        })
        
       
            -- 显示提示消息
        new_print(player, {'tianfu.chengshuangchengdui_over', target_item})
        return true
    
  
    
    
end



-- 手搓的神天赋：手搓物品有概率额外获得1个
local function shoucuo_de_shen(player, event, q_idx)
    -- 获取玩家RPG属性
    local rpg_t = rpgtable.get('rpg_t')
    local dexterity = rpg_t[player.index].dexterity
    
    -- 基础概率5%，每200敏捷增加1%，上限10%
    local base_chance = 5
    local agility_bonus = math.floor(dexterity / 200)
    local total_chance = math.min(base_chance + agility_bonus, 10)
    
    -- 生成随机数判断是否触发
    local random = math.random(1, 100)
    if random <= total_chance then
        -- 获取事件中的物品栈
        local item_stack = event.item_stack
        if item_stack and item_stack.valid_for_read then
            local item_name = item_stack.name
            local item_count = item_stack.count
            
            -- 获取玩家背包
            local main_inventory = player.get_main_inventory()
            if main_inventory and main_inventory.valid then
                -- 插入额外物品
                insert_item_to_player(player, item_name, ({1, 2, 3, 4, 5})[q_idx or 1])
            end
        end
    end
    
    return true
end
local function htms(player,event, q_idx)
    -- 获取玩家RPG属性
    local rpg_t = rpgtable.get('rpg_t')
    local magicka = rpg_t[player.index].magicka
    
    -- 检查法力值是否足够（大于1200）且为4个属性中最高
    if magicka < 1200 or not is_highest_attribute(player, 'magicka') then
        return false
    end
    
    -- 检查冷却时间
    if not check_tick(player, 'htms') then
        return false
    end
    

    local mana=rpg_t[player.index].mana
 
    -- 计算总伤害：500 + (法力 * 50)
    local total_damage = (500 + mana * 300) * COEFF_REG[q_idx or 1]
    
    
    -- 获取区域信息
    local area = event.area
    local surface = event.surface
    
    -- 限制区域大小为50x50
    local width = math.abs(area.right_bottom.x - area.left_top.x)
    local height = math.abs(area.right_bottom.y - area.left_top.y)
    
    if width > 50 then
        area.right_bottom.x = area.left_top.x + 50
    end
    if height > 50 then
        area.right_bottom.y = area.left_top.y + 50
    end
    
    -- 查找区域内的敌人
    local entities = surface.find_entities_filtered({
        area = area,
        force = 'enemy',
        type = {'unit', 'turret', 'unit-spawner', 'spider-unit'},
        limit=100
    })
    
    -- 限制最多100个敌人
    if #entities > 100 then
        -- 只保留前100个
        local limited_entities = {}
        for i = 1, math.min(100, #entities) do
            table.insert(limited_entities, entities[i])
        end
        entities = limited_entities
    end
    
    -- 计算每个敌人受到的伤害
    local damage_per_enemy = total_damage / math.max(#entities, 1)
    
    -- 对区域内敌人造成伤害
    local damaged_count = 0
    for _, entity in pairs(entities) do
        if entity.valid and entity.health then
            deal_damage_with_floating_text(entity, player, damage_per_enemy, 'explosion')
            damaged_count = damaged_count + 1
        end
    end
    
    -- 显示效果
    --限制50个敌人
    if damaged_count > 35 then
        damaged_count = 35
    end
    
    if damaged_count > 0 then
        -- 在区域中心创建爆炸效果
        local center_x = (area.left_top.x + area.right_bottom.x) / 2
        local center_y = (area.left_top.y + area.right_bottom.y) / 2
        surface.create_entity({
            name = 'explosion',
            position = {x = center_x, y = center_y}
        })
    end


    -- 消耗所有法力值
    rpg_t[player.index].mana = 0
    
    -- 显示消耗信息
    new_print(player, { 'tianfu.htms_cast', magicka })
end


-- 公共接口
Public.trigger_skills = trigger_skills

-- 导出所有技能函数
Public.bpz = bpz
Public.yubaobao = yubaobao
Public.relife = relife
Public.jika = jika
Public.bei_dong_zhao_huan = bei_dong_zhao_huan
Public.mijingzhang = mijingzhang
Public.shengguangzhongji = shengguangzhongji
Public.wuqidashi = wuqidashi
Public.jingzhunzhidao = jingzhunzhidao
Public.xybg = xybg
Public.yinxuejian = yinxuejian
Public.mdt = mdt
Public.yfz = yfz
Public.smmf = smmf
Public.tianshi = tianshi
Public.tjjz = tjjz
Public.sxf = sxf
Public.yhw = yhw
Public.yl = yl
Public.kxj = kxj
Public.qykj = qykj
Public.xueshu = xueshu
Public.baot = baot
Public.tuks = tuks
Public.willdie = willdie
Public.yanshu = yanshu
Public.liliangup = liliangup
Public.fcz = fcz
Public.jiantazhe = jiantazhe
Public.youxia = youxia
Public.xixue = xixue
Public.zg = zg
Public.sgj = sgj
Public.sangjin = sangjin
Public.yueshayueduo = yueshayueduo
Public.hyll = hyll
Public.dgjx = dgjx
Public.shandianwulianbian = shandianwulianbian
Public.shui_hu_fu = shui_hu_fu
Public.shoucuo_de_shen = shoucuo_de_shen
-- 红图抹杀天赋：使用拆除计划框选敌人时直接造成伤害
Public.chengshuangchengdui = chengshuangchengdui
Public.htms = htms
Public.zhaohuan_kongxi = zhaohuan_kongxi
Public.hkzy = hkzy

Public.shouyiren = shouyiren
Public.lianhejuntuan = lianhejuntuan

-- 顶级掠食者天赋
local function dingjilueshizhe(player, event_data, q_idx)
    -- 初始化击杀计数
    local this = TPT.get()
    local player_index = player.index
    
    
    if not this.dingjilueshizhe_kills[player_index] then
        this.dingjilueshizhe_kills[player_index] = 0
    end
    
    -- 增加击杀计数
    this.dingjilueshizhe_kills[player_index] = this.dingjilueshizhe_kills[player_index] + 1
    
    -- 检查是否达到2000只虫子
    if this.dingjilueshizhe_kills[player_index] >= 2000 then
        -- 重置计数
        this.dingjilueshizhe_kills[player_index] = 0
        
        -- 获取所有在线玩家
        local rpg_t = rpgtable.get('rpg_t')
        
        -- 为所有玩家增加力量和活力
        local stat_gain = ({1, 1, 2, 2, 3})[q_idx or 1]
        for _, p in pairs(game.connected_players) do
            if rpg_t[p.index] then
                rpg_t[p.index].strength = (rpg_t[p.index].strength or 0) + stat_gain
                rpg_t[p.index].vitality = (rpg_t[p.index].vitality or 0) + stat_gain
                
                -- 显示消息给所有玩家
                new_print(p, { 'tianfu.dingjilueshizhe_over', player.name })
            end
        end
        
        -- 特别消息给触发天赋的玩家
        new_print(player, { 'tianfu.dingjilueshizhe_trigger' })
    end
end

Public.dingjilueshizhe = dingjilueshizhe

-- 致命一击天赋：火箭弹伤害有15%概率翻倍
local function zhiming(player, event_data, q_idx)
    -- 检查是否是实体受伤事件
    if not event_data or not event_data.entity then
        return false
    end
    
    
    -- 检查是否有15%概率触发（1-20中随机到1表示触发）
    if math.random(1, 100) > 15 then
        return false
    end
    
    -- 触发致命一击：造成额外伤害
    local extra_damage = event_data.final_damage_amount or 0
    if extra_damage > 0 and event_data.entity.valid and event_data.entity.health then
        -- 造成等同于原伤害的额外伤害（翻倍效果）
        deal_damage_with_floating_text(event_data.entity, player, extra_damage * COEFF_REG[q_idx or 1], 'explosion')
        
        
        return true
    end
    
    return false
end

Public.zhiming = zhiming

-- 注册神赐之手效果结束的Token
local remove_shencizhishou_effect = Token.register(function(player_index)
    local this = TPT.get()
    if this.shencizhishou_active and this.shencizhishou_active[player_index] then
        this.shencizhishou_active[player_index] = nil
        local player = game.players[player_index]
        if player and player.valid then
            game.print({ 'tianfu.shencizhishou_deactivated' })
        end
    end
end)
-- 倒计时显示函数
local countdown_tick = Token.register(function(params)
    local seconds_left = params.seconds_left
    local player_index = params.player_index
    
    -- 如果时间到了，停止
    if seconds_left <= 0 then return end
    
    -- 获取触发天赋的玩家
    local player = game.get_player(player_index)
    
    -- 基础合法性检查：如果玩家不存在或角色失效，则不显示（或者改在固定位置显示）
    if not player or not player.valid or not player.character or not player.character.valid then
        return
    end
    
    -- 显示倒计时文字
    rendering.draw_text{
        text = "神赐之手: " .. seconds_left .. "s", -- 显示文字，增加单位s
        surface = player.surface,
        target = player.character,           -- 绑定在触发者角色身上
        target_offset = {0, -2.5},          -- 偏移量：显示在头顶上方
        color = {1, 0.85, 0.2},             -- 颜色：金黄色
        scale = 1.4,                        -- 稍微加大一点字体
        alignment = "center",               -- 居中对齐
        time_to_live = 61,                  -- 存在61 tick，略大于1秒，防止闪烁
        -- players = {player}               -- 【修改点】删掉这一行，或者设为 nil
        -- 此时默认对该 surface 的所有玩家可见
    }
end)

-- 神赐之手天赋：使用红图后10秒内（此处代码设定为16秒），我方所有单位受伤后立即回复所有血量
local function shencizhishou(player, event_data, q_idx)
    local this = TPT.get()
    local player_index = player.index
    
    -- 1. 检查冷却时间
    if not check_tick(player, 'shencizhishou') then
        return false
    end
    
    -- 2. 初始化/激活状态
    if not this.shencizhishou_active then
        this.shencizhishou_active = {}
    end
    
    local duration_seconds = ({16, 17, 18, 19, 20})[q_idx or 1] -- 持续秒数随品质(11223类)
    
    this.shencizhishou_active[player_index] = {
        end_tick = game.tick + 60 * duration_seconds,
        player_name = player.name
    }
    
    -- 3. 全局广播激活消息
    game.print({ 'tianfu.shencizhishou_activated' })
    
    -- 4. 延迟移除效果
    Task.set_timeout_in_ticks(60 * duration_seconds, remove_shencizhishou_effect, player_index)
   
    -- 5. 循环设置每秒的倒计时渲染
    -- 修改：从 duration_seconds 开始倒数到 1
    for i = 0, duration_seconds - 1 do
        Task.set_timeout_in_ticks(i * 60, countdown_tick, {
            seconds_left = duration_seconds - i, 
            player_index = player_index
        })
    end
    
    return true
end

Public.shencizhishou = shencizhishou

-- 裁决者天赋：在杀死虫子后，有概率召唤进攻无人机
local function caijuezhe(player, entity, q_idx)
    -- 检查实体有效性
    -- 获取玩家RPG属性
   
    local rpg_t = rpgtable.get('rpg_t')
    
    -- 0.5%概率召唤进攻无人机
    if math.random(1, 200) <= 1 then
        -- 获取玩家位置和表面
      
        local position = player.physical_position
        local surface = player.physical_surface
        
        -- 召唤进攻无人机
        local drone_count = ({1, 1, 2, 2, 3})[q_idx or 1]
        
        for i = 1, drone_count do
            -- 在玩家周围随机位置生成无人机
            local offset_x = math.random(-5, 5)
            local offset_y = math.random(-5, 5)
            local drone_position = {
                x = position.x + offset_x,
                y = position.y + offset_y
            }
            
            local e = player.physical_surface.create_entity({
                name = 'destroyer-capsule',
                position = drone_position,
                force = 'player',
                source = player.character,
                target =drone_position,
                speed = 1
            })
            
        end
      
        -- 显示效果信息
        new_print(player, { 'tianfu.caijuezhe_over', drone_count })
    end
end

Public.caijuezhe = caijuezhe

-- 陪审团天赋：当你的无人机杀死一个虫子，你有0.5%的概率，获得+1力量
local function peishentuanyuan(player, entity, q_idx)
    -- 生成随机数判断是否触发
 
        -- 获取玩家RPG属性
        local rpg_t = rpgtable.get('rpg_t')
        
        -- 增加力量
        rpg_t[player.index].strength = rpg_t[player.index].strength + ({1, 1, 2, 2, 3})[q_idx or 1]
        
        -- 显示效果信息
        new_print(player, { 'tianfu.peishentuanyuan_over' })

end

--- 收缴武器天赋：当你的无人机杀死敌方虫子时，有2%的概率获得子弹，霰弹，火箭弹中的一种
-- 300力量解锁红子弹，1200力量解锁贫铀弹，800力量解锁穿甲霰弹，600力量解锁爆裂导弹
local function shoujiao_wuqi(player, entity, q_idx)
    -- 检查玩家有效性
    if not player or not player.valid then
        return false
    end

    if not player.character or not player.character.valid then
          return false
    end 
    
    -- 获取玩家RPG属性
    local rpg_t = rpgtable.get('rpg_t')
    local player_strength = rpg_t[player.index].strength
    
    -- 根据力量确定可获得的物品列表
    local available_items = {}
    
    -- 子弹类（根据力量解锁不同类型）
    if player_strength >= 1200 then
        -- 贫铀弹（1200力量解锁）
        table.insert(available_items, 'uranium-rounds-magazine')
    elseif player_strength >= 300 then
        -- 红子弹（300力量解锁）
        table.insert(available_items, 'firearm-magazine')
    end
    
    -- 霰弹类（根据力量解锁不同类型）
    if player_strength >= 800 then
        -- 穿甲霰弹（800力量解锁）
        table.insert(available_items, 'piercing-shotgun-shell')
    else
        -- 基础霰弹
        table.insert(available_items, 'shotgun-shell')
    end
    
    -- 火箭弹类（根据力量解锁不同类型）
    if player_strength >= 600 then
        -- 爆裂导弹（600力量解锁）
        table.insert(available_items, 'explosive-rocket')
    else
        -- 基础火箭弹
        table.insert(available_items, 'rocket')
    end
    
    -- 检查是否有可获得的物品
    if #available_items == 0 then
        return false
    end
    
    -- 随机选择一个物品
    local selected_item = available_items[math.random(1, #available_items)]
    
    -- 随机生成数量（根据物品类型调整）
    local item_count = 1
    -- 向玩家添加物品
    insert_item_to_player(player, selected_item, item_count, q_idx or 1)
    
    -- 提示玩家获得物品
    local item_names = {
        ['firearm-magazine'] = '红子弹',
        ['uranium-rounds-magazine'] = '贫铀弹',
        ['shotgun-shell'] = '霰弹',
        ['piercing-shotgun-shell'] = '穿甲霰弹',
        ['rocket'] = '火箭弹',
        ['explosive-rocket'] = '爆裂导弹'
    }
    
    new_print(player, { 'tianfu.shoujiao_wuqi_over', item_count, item_names[selected_item] })
    
    return true
end

-- 替身术：受到伤害时，向远离伤害的一侧移动，并在原地留下1个小虫子，获得1秒无敌
local function tishenshu(player, event, q_idx)
    if not check_tick(player, 'tishenshu') then
        return false
    end
    if not player or not player.valid or not player.character then
        return
    end
    
    -- 获取伤害来源
    local cause = event.cause
    if not cause or not cause.valid then
        return
    end
    
    -- 计算远离伤害来源的方向
    local player_pos = player.physical_position
    local cause_pos = cause.position
    local direction_vector = {
        x = player_pos.x - cause_pos.x,
        y = player_pos.y - cause_pos.y
    }
    
    -- 归一化方向向量并设置移动距离（5格）
    local length = math.sqrt(direction_vector.x^2 + direction_vector.y^2)
    if length > 0 then
        direction_vector.x = direction_vector.x / length * 5
        direction_vector.y = direction_vector.y / length * 5
    else
        -- 如果伤害来源和玩家在同一位置，向{0,0}方向移动
        local to_origin = {
            x = -player_pos.x,
            y = -player_pos.y
        }
        local to_origin_length = math.sqrt(to_origin.x^2 + to_origin.y^2)
        if to_origin_length > 0 then
            direction_vector.x = to_origin.x / to_origin_length * 5
            direction_vector.y = to_origin.y / to_origin_length * 5
        else
            -- 如果玩家已经在原点，默认向右移动
            direction_vector.x = 5
            direction_vector.y = 0
        end
    end
    
    -- 计算目标位置
    local target_position = {
        x = player_pos.x + direction_vector.x,
        y = player_pos.y + direction_vector.y
    }
    
    -- 查找目标位置附近的无障碍点
    local safe_position = player.physical_surface.find_non_colliding_position('character', target_position, 16, 1, false)
    if not safe_position then
        -- 如果找不到无障碍点，尝试扩大搜索范围
       return
    end
    

    
    -- 传送玩家到安全位置
    player.teleport(safe_position, player.physical_surface)
    
    -- 在原地创建一个小虫子
    local biter = player.physical_surface.create_entity({
        name = 'small-biter',
        position = player_pos,
        force = 'player'
    })
    
    -- 设置虫子的生命值较低，让它更像一个诱饵
    if biter and biter.valid then
        -- 设置3秒后删除虫子（60tick=1秒）
        Task.set_timeout_in_ticks(60 * 3, kill_forces, {biter})
    end
    
    -- 给玩家1秒无敌效果
    player.character.destructible = false
    Task.set_timeout_in_ticks(math.floor(60 * 1 * COEFF_REG[q_idx or 1]), un_wudi, player)
    -- 显示提示信息
    new_print(player, { 'tianfu.tishenshu_over' })
end

Public.peishentuanyuan = peishentuanyuan
Public.tishenshu = tishenshu
Public.shoujiao_wuqi = shoujiao_wuqi

---- 弹幕攻击辅助函数：发射弹药
local function fire_barrage_ammo(player, target, q_idx)
    -- 检查玩家和目标的有效性
    if not player or not player.valid or not player.character then
        return false
    end
    
    if not target or not target.valid then
        return false
    end
    
    -- 获取玩家背包中的弹药
    local character = player.character
    local ammo_inventory = character.get_inventory(defines.inventory.character_main)
    
    -- 支持的弹药类型列表
    local supported_ammo = {
        'firearm-magazine',           -- 黄子弹
        'piercing-rounds-magazine',   -- 红子弹
        'uranium-rounds-magazine',    -- 贫铀弹
        'shotgun-shell',              -- 霰弹
        'piercing-shotgun-shell',     -- 穿甲霰弹
        'rocket',                     -- 火箭弹
        'explosive-rocket',           -- 爆裂导弹
        'flamethrower-ammo',          -- 火焰喷射器弹药
        'cannon-shell',               -- 加农炮炮弹
        'explosive-cannon-shell',     -- 爆炸加农炮炮弹
        'uranium-cannon-shell',       -- 贫铀加农炮炮弹
        'explosive-uranium-cannon-shell', -- 爆炸贫铀加农炮炮弹
        'artillery-shell',            -- 炮弹
        'grenade',                    -- 手榴弹
        'cluster-grenade',            -- 集束手榴弹
      
    }
    
    -- 找到背包中支持的弹药
    local available_ammo = {}
    for _, ammo_name in pairs(supported_ammo) do
        local count = ammo_inventory.get_item_count(ammo_name)
        if count > 0 then
  
            table.insert(available_ammo, {name = ammo_name, count = count})
        end
    end
     
    -- 如果没有支持的弹药，返回false
    if #available_ammo == 0 then
        return false
    end
    
    -- 随机选择一个弹药类型
    local selected_ammo = available_ammo[math.random(1, #available_ammo)]
    
    
    -- 消耗一发弹药
    character.remove_item({name = selected_ammo.name, count = 1})
    
    -- 根据弹药类型发射相应的投射物
    local surface = player.physical_surface
    local position = player.physical_position
    local projectile_data = {
        ['firearm-magazine'] = {name = 'shotgun-pellet', count = 1, speed = 1},
        ['piercing-rounds-magazine'] = {name = 'piercing-shotgun-pellet', count = 1, speed = 1},
        ['uranium-rounds-magazine'] = {name = 'piercing-shotgun-pellet', count = 1, speed = 1},
        ['shotgun-shell'] = {name = 'shotgun-pellet', count = 1, speed = 1},
        ['piercing-shotgun-shell'] = {name = 'piercing-shotgun-pellet', count = 1, speed = 1},
        ['rocket'] = {name = 'rocket', count = 1, speed = 1},
        ['explosive-rocket'] = {name = 'explosive-rocket', count = 1, speed = 1},
        ['flamethrower-ammo'] = {name = 'flamethrower-fire-stream', count = 1, speed = 1},
        ['cannon-shell'] = {name = 'cannon-projectile', count = 1, speed = 1},
        ['explosive-cannon-shell'] = {name = 'explosive-cannon-projectile', count = 1, speed = 1},
        ['uranium-cannon-shell'] = {name = 'uranium-cannon-projectile', count = 1, speed = 1},
        ['explosive-uranium-cannon-shell'] = {name = 'explosive-uranium-cannon-projectile', count = 1, speed = 1},
        ['artillery-shell'] = {name = 'artillery-projectile', count = 1, speed = 1},
        ['grenade'] = {name = 'grenade', count = 1, speed = 1},
        ['cluster-grenade'] = {name = 'cluster-grenade', count = 1, speed = 1},
        ['atomic-bomb'] = {name = 'atomic-rocket', count = 1, speed = 1}
    }
    
    local ammo_info = projectile_data[selected_ammo.name]
    if not ammo_info then
        return false
    end
    
    -- 发射投射物
    for i = 1, ammo_info.count do
        surface.create_entity({
            name = ammo_info.name,
            position = position,
            force = player.force,
            source = character,
            target = target,
            speed = ammo_info.speed
        })
    end
    
    return true
end

--- 亡灵大军天赋：在击杀虫子的时候，有30%的概率封印其灵魂，封印到64个的时候，合并放出这些灵魂（召唤虫子）
local function wanglingdajun(player, entity, q_idx)
    -- 检查是否是虫子单位
    if not entity or not entity.valid then
        return false
    end
    
    -- 只对敌人生物单位生效
    if entity.force ~= game.forces.enemy then
        return false
    end
    
    if not (entity.type == 'unit' or entity.type == 'spider-unit') then
        return false
    end
    
    -- 30%概率封印灵魂
    if math.random(1, 100) > 30 then
        return false
    end
    
    -- 获取玩家数据表
    local this = TPT.get()
    local player_index = player.index
    
    -- 初始化玩家的灵魂计数器和存储的虫子类型
    if not this.wanglingdajun_souls then
        this.wanglingdajun_souls = {}
    end
    if not this.wanglingdajun_stored_biters then
        this.wanglingdajun_stored_biters = {}
    end
    if not this.wanglingdajun_souls[player_index] then
        this.wanglingdajun_souls[player_index] = 0
    end
    if not this.wanglingdajun_stored_biters[player_index] then
        this.wanglingdajun_stored_biters[player_index] = {}
    end
    
    -- 增加灵魂计数，并存储被击杀虫子的类型
    this.wanglingdajun_souls[player_index] = this.wanglingdajun_souls[player_index] + 1
    table.insert(this.wanglingdajun_stored_biters[player_index], entity.name)
    local current_souls = this.wanglingdajun_souls[player_index]
    
    -- 显示封印提示
    new_print(player, { 'tianfu.wanglingdajun_seal', current_souls })
    
    -- 检查是否达到64个灵魂，可以召唤
    if current_souls >= 32 then
        -- 重置灵魂计数器和存储的虫子类型
        this.wanglingdajun_souls[player_index] = 0
        local stored_biters = this.wanglingdajun_stored_biters[player_index]
        this.wanglingdajun_stored_biters[player_index] = {}
        
        -- 获取存储的虫子类型列表
        local summoned_count = 0
        local summoned_entities = {}
        local surface = player.physical_surface
        local player_pos = player.physical_position
        
        -- 召唤64只虫子，使用存储的虫子类型
        local stored_biter_count = #stored_biters
        
        -- 如果没有存储任何虫子类型，使用默认的小型虫子
        if stored_biter_count == 0 then
            stored_biters = {'small-biter'}
            stored_biter_count = 1
        end
        
        for i = 1, 32 do
            -- 循环使用存储的虫子类型
            local bug_index = ((i - 1) % stored_biter_count) + 1
            local bug_type = stored_biters[bug_index]
            
            -- 在玩家周围寻找有效位置
            local offset = {
                x = player_pos.x + math.random(-5, 5),
                y = player_pos.y + math.random(-5, 5)
            }
            local valid_position = surface.find_non_colliding_position(bug_type, offset, 10, 0.5)
            
            if valid_position then
                local summoned_biter = surface.create_entity({
                    name = bug_type,
                    position = valid_position,
                    force = 'player'
                })
                
                if summoned_biter and summoned_biter.valid then
                    table.insert(summoned_entities, summoned_biter)
                    summoned_count = summoned_count + 1
                end
            end
        end
        
        if summoned_count > 0 then
            -- 显示召唤提示
            new_print(player, { 'tianfu.wanglingdajun_summon', summoned_count })
            
            -- 设置10秒后删除召唤的虫子（60tick=1秒）
            Task.set_timeout_in_ticks(60 * 60, kill_forces, summoned_entities)
        end
    end
    
    return true
end

Public.wanglingdajun = wanglingdajun

-- 虫母天赋：在杀死一只敌方虫子后，在原地生成1个无敌的虫巢和1个沙虫，虫巢和沙虫持续10秒，期间虫巢每秒都会召唤3只虫子

-- 封印卷轴天赋：每杀死1只虫子，有10%的概率封印灵魂，每封印50只虫子，最大法力值提升20点
local function fengyinjuanzhou(player, event_data, q_idx)
    local this = TPT.get()
    local rpg_t = rpgtable.get('rpg_t')
    
    -- 10%概率封印灵魂
    if math.random(1, 100) <= 5 then
        -- 初始化玩家的封印计数
        if not this.fengyinjuanzhou_count[player.index] then
            this.fengyinjuanzhou_count[player.index] = 0
        end
        
        -- 增加封印计数
        this.fengyinjuanzhou_count[player.index] = this.fengyinjuanzhou_count[player.index] + 1
        
        -- 显示封印提示
        new_print(player, { 'tianfu.fengyinjuanzhou_seal', this.fengyinjuanzhou_count[player.index] })
        
        -- 检查是否达到50个封印
        if this.fengyinjuanzhou_count[player.index] % 50 == 0 then
            -- 每封印50只虫子，增加20点最大法力值
            this.fengyinjuanzhou_extra_mana[player.index] = (this.fengyinjuanzhou_extra_mana[player.index] or 0) + 10 * COEFF_LOW[q_idx or 1]
            
            -- 显示提升提示
            new_print(player, { 'tianfu.fengyinjuanzhou_upgrade', 10, this.fengyinjuanzhou_extra_mana[player.index] })
            
        end
    end
    
    return true
end

Public.fengyinjuanzhou = fengyinjuanzhou

-- 低阶教徒天赋实现
local function dijiaojiaotu(player, event_data, q_idx)
    if not check_tick(player, 'dijiaojiaotu') then
        return false
    end
    local rpg_t = rpgtable.get('rpg_t')
    local this = TPT.get()
    
    -- 获得死亡玩家的引用
    local deceased_player = event_data and event_data.player
    if not deceased_player or not deceased_player.valid then
        return false
    end
    
    -- 给死亡玩家5点经验
    rpg_t[deceased_player.index].xp = rpg_t[deceased_player.index].xp + 5 * COEFF_LOW[q_idx or 1]
    new_print(deceased_player, { 'tianfu.dijiaojiaotu_exp', 5 })
    
    -- 给拥有低阶教徒天赋的玩家增加2点最大法力值
    this.fengyinjuanzhou_extra_mana[player.index] = (this.fengyinjuanzhou_extra_mana[player.index] or 0) + 2 * COEFF_LOW[q_idx or 1]
    new_print(player, { 'tianfu.dijiaojiaotu_mana', 2 })
    
    return true
end

Public.dijiaojiaotu = dijiaojiaotu

-- 五行诀天赋：如果魔法是最高属性，击杀虫子有5%概率触发随机元素效果
local function wuxingjue(player, event_data, q_idx)
   
    -- 获取玩家RPG属性
    local rpg_t = rpgtable.get('rpg_t')
    local index = player.index
    
    -- 检查魔法是否是最高属性
    local magicka = rpg_t[index].magicka or 0
    local strength = rpg_t[index].strength or 0
    local vitality = rpg_t[index].vitality or 0
    local dexterity = rpg_t[index].dexterity or 0
    
    -- 如果魔法不是最高属性，直接返回
    if magicka <= math.max(strength, vitality, dexterity) then
        return false
    end
    
    -- 计算概率：5点初始概率 + 每300魔法增加1%概率
    local probability = math.min(5 + math.floor(magicka / 300),10)
    if math.random(1, 100) > probability then
       return false
    end

     if not check_tick(player, 'wuxingjue') then
        return false
    end
    
    
    -- 获取击杀的虫子实体
    local entity = event_data and event_data.entity
    if not entity or not entity.valid then
        return false
    end
    
    -- 随机选择一种元素效果
    local elements = {'fire', 'water', 'lightning', 'wind', 'dark'}
    local selected_element = elements[math.random(1, #elements)]
 
    -- 根据选择的元素执行不同效果
    if selected_element == 'fire' then
        -- 火效果：提供AOE伤害和经验
        local position = entity.position
        local surface = entity.surface
        
        -- 计算AOE伤害（基于魔法值，受品质加成）
        local aoe_damage = magicka * COEFF_REG[q_idx or 1]
        local aoe_radius = math.min(4 + math.floor(magicka / 200), 7)  -- 限定最大半径为8
        
        -- 对周围敌人造成AOE伤害
        local enemies = EntityCache.find_entities_cached(surface, {
            position = position,
            radius = aoe_radius,
            force = 'enemy',
            type = goal
        })
        
        local damage_count = 0
        for _, enemy in pairs(enemies) do
            if enemy.valid and enemy.health then
                deal_damage_with_floating_text(enemy, player, aoe_damage, 'fire')
                damage_count = damage_count + 1
            end
        end
        -- 创建火焰特效
        for i = 1, 24 do
            local angle = (i / 24) * math.pi * 2
            local effect_pos = {
                x = position.x + math.cos(angle) * aoe_radius * 0.7,
                y = position.y + math.sin(angle) * aoe_radius * 0.7
            }
            surface.create_entity({
                name = 'fire-flame',
                position = effect_pos,
                force = 'enemy'
            })
        end
        -- 给予经验奖励（受品质加成）
        local exp_bonus = math.floor((10 + math.floor(magicka / 20)) * COEFF_LOW[q_idx or 1])
        rpg_t[index].xp = rpg_t[index].xp + exp_bonus
        
        -- 创建范围火焰特效
         -- 在目标位置创建大范围火焰效果

        new_print(player, { 'tianfu.wuxingjue_fire', damage_count, exp_bonus })
        
    elseif selected_element == 'water' then
        -- 水效果：范围治疗区域内的友军并击退敌人
        local position = player.physical_position
        local surface = player.physical_surface
        
        -- 计算治疗量（基于魔法值，受品质加成）
        local heal_amount = magicka * 0.2 * COEFF_LOW[q_idx or 1]
        local heal_radius = math.min(4 + math.floor(magicka / 150), 8)  -- 限定最大半径为8
        
        -- 查找范围内的友军单位
        local allies = surface.find_entities_filtered({
            position = position,
            radius = heal_radius,
            force = 'player',
            type = {'character', 'combat-robot', 'car', 'tank', 'spider-vehicle', 'unit', 'turret','wall','spider-unit'}
        })
        
        local healed_count = 0
        local total_heal = 0
        
        for _, ally in pairs(allies) do
            if ally.valid and ally.health then
                local max_health = ally.max_health 
                local current_health = ally.health
                local heal_to_apply = math.min(heal_amount, max_health - current_health)
                
                if heal_to_apply > 0 then
                    ally.health = current_health + heal_to_apply
                    healed_count = healed_count + 1
                    total_heal = total_heal + heal_to_apply
                    
                    -- 创建治疗特效
                    surface.create_entity({
                        name = 'water-splash',
                        position = ally.position
                    })
                end
            end
        end
        
        -- 击退效果
        local knockback_radius = math.min(4 + math.floor(magicka / 150), 8)  -- 限定最大半径为8
        local knockback_force = 1 +  math.floor(magicka / 250) -- 基于魔法值的击退力度
        
        -- 查找范围内的敌人
        local enemies = EntityCache.find_entities_cached(surface, {
            position = position,
            radius = knockback_radius,
            force = 'enemy',
            type = goal
        })
        
        local knocked_back_count = 0
        for _, enemy in pairs(enemies) do
            if enemy.valid and enemy.health then
                -- 计算击退方向
                local dx = enemy.position.x - position.x
                local dy = enemy.position.y - position.y
                local distance = math.sqrt(dx * dx + dy * dy)
                
                if distance > 0 then
                    -- 标准化方向向量
                    dx = dx / distance
                    dy = dy / distance
                    
                    -- 计算击退距离
                    local knockback_distance = knockback_force * (1 - distance / knockback_radius)
                    
                    -- 执行击退
                    local new_x = enemy.position.x + dx * knockback_distance
                    local new_y = enemy.position.y + dy * knockback_distance
                    
                    -- 寻找有效位置
                    local valid_position = surface.find_non_colliding_position(enemy.name, {x = new_x, y = new_y}, 2, 0.5)
                    if valid_position then
                        enemy.teleport(valid_position)
                        knocked_back_count = knocked_back_count + 1
                    end
                end
            end
        end
        
        -- 创建水波纹特效
        for i = 1, 24 do
            local angle = (i / 24) * math.pi * 2
            local effect_pos = {
                x = position.x + math.cos(angle) * heal_radius * 0.7,
                y = position.y + math.sin(angle) * heal_radius * 0.7
            }
            surface.create_entity({
                name = 'water-splash',
                position = effect_pos
            })
        end
        
        new_print(player, { 'tianfu.wuxingjue_water', healed_count, math.floor(total_heal), knocked_back_count })
        
    elseif selected_element == 'lightning' then
        -- 闪电效果：提供金币和单体伤害
        local position = entity.position
        local surface = entity.surface
        
        -- 计算金币奖励（基于魔法值，受品质加成）
        local coin_reward = math.floor((5 + math.floor(magicka / 10)) * COEFF_LOW[q_idx or 1])
        local limit = 5+ math.floor(magicka / 300)
        -- 计算闪电伤害（基于魔法值，受品质加成）
        local lightning_damage = magicka * 2 * COEFF_REG[q_idx or 1]
        
        -- 寻找附近的敌人进行闪电链攻击
        local enemies = EntityCache.find_entities_cached(surface, {
            position = position,
            radius = 18,
            force = 'enemy',
            type = goal,
            limit = limit  -- 最多攻击5个目标
        })
        
        local chain_count = 0
        for i, enemy in pairs(enemies) do
            if enemy.valid and enemy.health then
                -- 创建闪电特效
                surface.create_entity({
                    name = 'electric-beam',
                    position = position,
                    target = enemy,
                    source = player.character,
                    duration = 15
                })
                
                -- 造成伤害
                deal_damage_with_floating_text(enemy, player, lightning_damage / i, 'electric')
                chain_count = chain_count + 1
            end
        end
        
        -- 给予金币奖励
        insert_item_to_player(player, 'coin', coin_reward)
        
        new_print(player, { 'tianfu.wuxingjue_lightning', coin_reward, chain_count })
        
    elseif selected_element == 'wind' then
        -- 风效果：提供移速和掩护无人机
        local position = entity.position
        local surface = entity.surface
        
        -- 计算移速加成（基于魔法值，受品质加成）
        local speed_bonus = 0.03 * COEFF_LOW[q_idx or 1]
        local speed_duration = 60*3 + 60*math.floor(magicka / 200)  -- 持续时间（秒）
        
        -- 应用移速加成
        if not player.character_running_speed_modifier then
            player.character_running_speed_modifier = 0
        end
        local original_speed = player.character_running_speed_modifier
        player.character_running_speed_modifier = original_speed + speed_bonus
        
        -- 创建掩护无人机（受品质加成）
        local drone_count = ({1, 1, 2, 2, 3})[q_idx or 1]
        for i = 1, drone_count do
            local offset_x = math.random(-5, 5)
            local offset_y = math.random(-5, 5)
            local drone_position = {
                x = position.x + offset_x,
                y = position.y + offset_y
            }
            
            local drone = surface.create_entity({
                name = 'distractor-capsule',
                position = drone_position,
                force = 'player',
                source = player.character,
                target = drone_position,
                speed = 1,
                last_user = player
            })
        end
        
        -- 设置持续时间后恢复移速
        Task.set_timeout_in_ticks(speed_duration, lowdowm_1, player)  -- 10秒后取消效果
       
        
        new_print(player, { 'tianfu.wuxingjue_wind', math.floor(speed_bonus * 100) .. '%', drone_count, speed_duration })
        
    elseif selected_element == 'dark' then
        -- 暗效果：召唤巨型沙虫并获得1秒无敌
        local position = entity.position
        local surface = entity.surface
        
        -- 计算沙虫存活时间（基于魔法值，受品质加成）
        local base_duration = 10  -- 基础10秒
        local extra_duration = math.floor(magicka / 200)  -- 每100魔法多1秒
        local total_duration = math.floor((base_duration + extra_duration) * COEFF_REG[q_idx or 1])
        
        -- 在击杀点召唤巨型沙虫
        local worm_position = position
        local valid_position = surface.find_non_colliding_position('behemoth-worm-turret', worm_position, 10, 0.5)
        if not valid_position then
            valid_position = worm_position
        end
        
        local giant_worm = surface.create_entity({
            name = 'behemoth-worm-turret',
            position = valid_position,
            force = 'player'
        })
        
        if giant_worm and giant_worm.valid then
            
            -- 设置持续时间后删除沙虫
            Task.set_timeout_in_ticks(60 * total_duration, kill_forces, {giant_worm})
            
            -- 给予玩家1秒无敌
            if player.character and player.character.valid then
                player.character.destructible = false
                Task.set_timeout_in_ticks(60 , un_wudi, player)
            end
            
            new_print(player, { 'tianfu.wuxingjue_dark', total_duration, math.floor(magicka / 150)+1 })
        end
    end
    
    return true
end

Public.wuxingjue = wuxingjue

-- 破阵霸王枪天赋：如果力量超过800且为全属性最高，当使用物理伤害杀死虫子后，击退面前的虫子4格，并对这些虫子造成力量的50%的爆炸伤害，回复25%力量的血量，每次触发伤害永久+10，冷却3秒
local function pochen_bawangqiang(player, entity, q_idx)
    if not player or not player.valid or not player.character then
        return false
    end
    
    local this = TPT.get()
    local player_index = player.index
    
    -- 获取玩家RPG属性
    local rpg_t = rpgtable.get('rpg_t')
    
    -- 获取玩家属性
    local strength = rpg_t[player_index].strength or 0
    local vitality = rpg_t[player_index].vitality or 0
    local dexterity = rpg_t[player_index].dexterity or 0
    local magicka = rpg_t[player_index].magicka or 0

    -- 属性门槛检查
    if strength <= 800 then return false end
    if strength <= math.max(vitality, dexterity, magicka) then return false end
    
    -- 初始化伤害加成
    if not this.pochen_bawangqiang_bonus then this.pochen_bawangqiang_bonus = {} end
    if not this.pochen_bawangqiang_bonus[player_index] then this.pochen_bawangqiang_bonus[player_index] = 0 end
    
    -- --- 优化开始：扇形索敌逻辑 ---
    
    local player_position = player.physical_position
    local surface = player.physical_surface
    local search_radius = 15
    
    -- 1. 先获取半径内的所有潜在目标（圆形搜索）
    local candidates = surface.find_entities_filtered({
        position = player_position,
        radius = search_radius,
        force = 'enemy',
        type = {'unit', 'spider-unit'}
    })
    
    if #candidates == 0 then return false end

    -- 2. 准备向量计算数据
    local player_direction = player.character.direction
    -- 定义方向对应的单位向量表 (Factorio中: 北=0, 东北=1, 东=2, ...)
    -- y轴向下为正，北是(0, -1)
    local dir_vectors = {
        [defines.direction.north]     = {x = 0, y = -1},
        [defines.direction.northeast] = {x = 0.707, y = -0.707}, -- 1/√2
        [defines.direction.east]      = {x = 1, y = 0},
        [defines.direction.southeast] = {x = 0.707, y = 0.707},
        [defines.direction.south]     = {x = 0, y = 1},
        [defines.direction.southwest] = {x = -0.707, y = 0.707},
        [defines.direction.west]      = {x = -1, y = 0},
        [defines.direction.northwest] = {x = -0.707, y = -0.707}
    }
    
    local facing_vector = dir_vectors[player_direction] or {x = 0, y = -1} -- 默认北
    
    -- 设定角度阈值：160度扇形 = 左右各80度
    -- 使用点积公式：A·B = |A||B|cosθ
    -- 因为A和B都归一化了，所以 点积 = cosθ
    -- 我们需要 θ < 80度，即 cosθ > cos(80度)
    -- math.cos接弧度，80度 ≈ 1.396弧度
    local angle_threshold = math.cos(math.rad(80)) -- 约为 0.1736
    
    local enemies = {}
    
    -- 3. 筛选在扇形区域内的敌人
    for _, target in pairs(candidates) do
        if target.valid then
            local dx = target.position.x - player_position.x
            local dy = target.position.y - player_position.y
            
            -- 计算距离以进行归一化
            local distance = math.sqrt(dx^2 + dy^2)
            
            if distance > 0 then
                -- 归一化目标向量
                local nx = dx / distance
                local ny = dy / distance
                
                -- 计算点积
                local dot_product = facing_vector.x * nx + facing_vector.y * ny
                
                -- 如果点积大于阈值，说明在角度范围内
                if dot_product >= angle_threshold then
                    table.insert(enemies, target)
                end
            elseif distance == 0 then
                -- 就在脚下的敌人直接算入
                table.insert(enemies, target)
            end
        end
    end
    
    -- 如果筛选后没有敌人，退出
    if #enemies == 0 then return false end
    
    -- --- 优化结束 ---

    -- 检查冷却时间 (建议放在索敌之后，避免空挥浪费CD，或者放在最前面节省性能，看需求。原代码逻辑是索敌后)
    if not check_tick(player, 'pochen_bawangqiang') then
        return false
    end
    
    -- 计算伤害
    local base_damage = strength * 0.5 * COEFF_REG[q_idx or 1]
    local bonus_damage = this.pochen_bawangqiang_bonus[player_index]
    local total_damage = base_damage + bonus_damage
    
    -- 攻击循环
    for _, enemy in pairs(enemies) do
        if enemy.valid and enemy.health > 0 then
            
            
            -- 创建攻击特效
            surface.create_entity({
                name = 'vulcanus-cliff-collapse',
                position = enemy.position,
                force = game.forces.player
            })
            deal_damage_with_floating_text(enemy, player, total_damage, 'physical')
             if enemy.valid and enemy.health > 0 then
            -- 击退计算 (向量归一化已经在上面做过了，但为了代码解耦还是重新算一遍或复用)
            local k_dx = enemy.position.x - player_position.x
            local k_dy = enemy.position.y - player_position.y
            local k_dist = math.sqrt(k_dx^2 + k_dy^2)
            
            if k_dist > 0 then
                k_dx = k_dx / k_dist
                k_dy = k_dy / k_dist
                
                local knockback_dist = 3
                local new_pos = {
                    x = enemy.position.x + k_dx * knockback_dist,
                    y = enemy.position.y + k_dy * knockback_dist
                }
                
                local teleport_pos = surface.find_non_colliding_position(enemy.name, new_pos, 2, 0.5)
                if teleport_pos then
                    enemy.teleport(teleport_pos)
                end
            end
            end
        end
    end
    
    -- 回血逻辑
    local heal_amount = strength * 0.25 * COEFF_REG[q_idx or 1]
    if player.character and player.character.valid then
        player.character.health = math.min(player.character.health + heal_amount, player.character.max_health)
    end
    
    -- 永久加成成长
    this.pochen_bawangqiang_bonus[player_index] = this.pochen_bawangqiang_bonus[player_index] + 10 * COEFF_LOW[q_idx or 1]
    
    new_print(player, { 'tianfu.pochen_bawangqiang_over', #enemies, math.floor(total_damage), math.floor(heal_amount), this.pochen_bawangqiang_bonus[player_index] })
    
    return true
end

Public.pochen_bawangqiang = pochen_bawangqiang

--- 噬魔者天赋：杀死虫子的时候有20%的概率，恢复1点法力值
local function shimozhe(player, q_idx)
    -- 20%概率触发
    if math.random(1, 100) <= 20 then
    local rpg_t = rpgtable.get('rpg_t')
    local player_index = player.index
        local shimozhe_gain = ({1, 1, 2, 2, 3})[q_idx or 1]
        rpg_t[player_index].mana = rpg_t[player_index].mana + shimozhe_gain
        if rpg_t[player_index].mana > rpg_t[player_index].mana_max then
            rpg_t[player_index].mana = rpg_t[player_index].mana_max
        end
        new_print(player, { 'tianfu.shimozhe_over', shimozhe_gain })
    end
    
    return true
end

Public.shimozhe = shimozhe

--- 炎魔天赋：杀死虫子时，有5%的概率触发地狱熔岩，冷却2秒
local function yanmo(player, entity, q_idx)
    
    -- 5%概率触发
    if math.random(1, 100) > 5 then
        return true
    end
        -- 检查冷却时间
        if not check_tick(player, 'yanmo') then
            return false
        end
        
        -- 获取目标位置
        local target_pos = entity.position
        local surface = entity.surface
        
        -- 创建熔岩效果（使用火焰云效果）
        surface.create_entity({
            name = 'small-demolisher-fissure',
            position = target_pos,
            force = player.force,
            source = player.character,
            player = player,
            quality = QUALITY_NAMES[q_idx or 1]
        })
        
        -- 获取玩家魔力值
        local rpg_t = rpgtable.get('rpg_t')
        local magic_power = rpg_t[player.index].magicka or 0
        
        -- 对目标周围2米内所有虫子造成微量伤害（基于魔力值）
        local enemies = EntityCache.find_entities_cached(surface, {
            position = target_pos,
            radius = 2,
            force = game.forces.enemy,
            type = goal
        })
        
        local damage = (10 + math.floor(magic_power / 10)) * COEFF_REG[q_idx or 1]
        
        for _, enemy in pairs(enemies) do
            deal_damage_with_floating_text(enemy, player, damage, 'fire')
        end
        
        -- 2秒后执行范围伤害（100 ticks）
        Task.set_timeout_in_ticks(100, yanmo_lava_eruption, {
            target = entity,
            target_pos = target_pos,
            surface = surface,
            player = player,
            magic_power = magic_power,
            q_idx = q_idx or 1
        })
        
        new_print(player, { 'tianfu.yanmo_over' })

    
    return true
end

Public.yanmo = yanmo

--- 双刃剑天赋：自动攻击可以同时攻击两名敌人，但攻击力下降40%
local function shuangrenjian(player, enemies, q_idx)
    
    local rpg_t = rpgtable.get('rpg_t')
    local player_index = player.index
    
    -- 获取基础攻击力
    local strength = rpg_t[player_index].strength
    local base_damage = strength / 2 - 10
    
    -- 攻击力下降40%
    local reduced_damage = base_damage * 0.6 * COEFF_REG[q_idx or 1]
    
    -- 随机选择2个敌人
    local selected_enemies = {}
    local available_indices = {}
    for i = 1, #enemies do
        table.insert(available_indices, i)
    end
    
    -- 随机选择2个不同的索引
    for i = 1, 2 do
        local random_pos = math.random(1, #available_indices)
        local index = available_indices[random_pos]
        table.insert(selected_enemies, enemies[index])
        table.remove(available_indices, random_pos)
    end
    
    -- 对选中的2个敌人造成伤害
    for _, enemy in pairs(selected_enemies) do
        if enemy.valid and enemy.health then
            deal_damage_with_floating_text(enemy, player, reduced_damage, 'physical')
        end
    end
    
    -- 攻击回血
    local vitality = rpg_t[player_index].vitality
    local heal_amount = (vitality - 10) * 0.4
    if player.character and player.character.valid then
        player.character.health = player.character.health + heal_amount
    end
    
    return true
end

Public.shuangrenjian = shuangrenjian

--- 血爆天赋：受到伤害有20%的概率存储伤害，当伤害达到10%的最大生命值时，释放这些伤害，平均分配给附近（5米）的所有虫子
local function xuebao(player, event, q_idx)
    if not player or not player.valid or not player.character then
        return false
    end
    
    local this = TPT.get()
    local player_index = player.index
    
    -- 初始化玩家的血爆数据
    if not this.xuebao_damage then
        this.xuebao_damage = {}
    end
    if not this.xuebao_damage[player_index] then
        this.xuebao_damage[player_index] = 0
    end
    
    -- 获取事件伤害值
    local damage = event.original_damage_amount or 0
    if damage <= 0 then
        return false
    end
    
    -- 20%概率存储伤害
    if math.random(1, 100) <= 20 then
        this.xuebao_damage[player_index] = this.xuebao_damage[player_index] + damage
        
    
        local max_health = player.character.max_health
        local trigger_threshold = max_health * 0.1  -- 10%的最大生命值
        
        -- 检查是否达到触发阈值
        if this.xuebao_damage[player_index] >= trigger_threshold then
            local stored_damage = this.xuebao_damage[player_index]
            this.xuebao_damage[player_index] = 0  -- 重置存储的伤害
            
            -- 查找玩家附近5米内的所有虫子
            local enemies = EntityCache.find_entities_cached(player.physical_surface, {
                position = player.physical_position,
                radius = 5,
                type = goal,
                force = 'enemy',
                limit = 15
            })
            
            if #enemies > 0 then
                -- 计算每个敌人应受到的伤害
                local damage_per_enemy = math.floor(stored_damage / #enemies * COEFF_REG[q_idx or 1])
                
                -- 对每个敌人造成伤害
                for _, enemy in pairs(enemies) do
                    if enemy.valid and enemy.health > 0 then
                        deal_damage_with_floating_text(enemy, player, damage_per_enemy, 'explosion')
                    end
                end
                
                -- 显示提示信息
                new_print(player, { 'tianfu.xuebao_cast', #enemies, damage_per_enemy })
            end
        end
    end
    
    return true
end

Public.xuebao = xuebao

local function weiyang(event,player, q_idx)


    local fish_count = player.get_item_count('raw-fish')
    if fish_count < 2 then
        return false
    end

    player.remove_item({ name = 'raw-fish', count = 1 })

    local position = event.position
    local surface = player.physical_surface

    local enemies = surface.find_entities_filtered({
        position = position,
        radius = 3,
        force = game.forces.player,
        type = {'unit', 'character','spider-unit'}
    })

    if #enemies > 0 then
        local biter = enemies[math.random(#enemies)]
        surface.create_entity({
            name = 'bioflux-speed-regen-sticker',
            position = biter.position,
            target = biter,
            force = 'player'
        })
        new_print(player, { 'tianfu.weiyang_over' })
    end

    return true
end

Public.weiyang = weiyang

-- 杀戮经验：杀虫获得额外经验（原经验×0.2×品质系数）
local function shalujingyan(player, entity, q_idx)
    if not entity or not entity.valid then
        return false
    end
    
    local rpg_extra = rpgtable.get('rpg_extra')
    if not rpg_extra or not rpg_extra.rpg_xp_yield then
        return false
    end
    
    local base_xp = rpg_extra.rpg_xp_yield[entity.name]
    if not base_xp then
        return false
    end
    
    local bonus_xp = math.floor(base_xp * 0.2 * COEFF_LOW[q_idx or 1])
    if bonus_xp <= 0 then
        bonus_xp = 1
    end
    
    local rpg_t = rpgtable.get('rpg_t')
    rpg_t[player.index].xp = rpg_t[player.index].xp + bonus_xp
    
    return true
end

Public.shalujingyan = shalujingyan

return Public