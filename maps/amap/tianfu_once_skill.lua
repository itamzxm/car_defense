local Token = require 'utils.token'
local Task = require 'utils.task'
local Loot = require 'maps.amap.loot'
local Alert = require 'utils.alert'
local rpgtable = require 'modules.rpg.table'
local TPT = require 'maps.amap.tianfu_table'
local WPT = require 'maps.amap.table'
local TianfuQuality = require 'maps.amap.tianfu_quality'  -- 天赋品质系统 helper（方案 D）

local Public = {}

-- 获取已初始化的表引用
local goal = {'unit', 'turret', 'unit-spawner','spider-leg','combat-robot','spider-unit'}

-- 品质系数表（Phase B 方案2）
-- 核心数值 ≤10 用 LOW（普通=基准×1，传说×1.8，普通档不削弱）；>10 用 REG（普通×0.8，传说×1.6）
local COEFF_LOW = {1, 1.2, 1.4, 1.6, 1.8}
local COEFF_REG = {1, 1.2, 1.4, 1.6, 1.8}
-- 成品类天赋：物品品质名（q_idx 1..5 → normal..legendary），用于 player.insert 的 quality 字段
local QUALITY_NAMES = {'normal', 'uncommon', 'rare', 'epic', 'legendary'}

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
        if player.surface == target_player.surface then
        target_player.create_local_flying_text{
            text = text,
            color = player.color,
            position = player.physical_position,
            speed = 0.8
        }
    end
    end

    -- player.create_local_flying_text{
    --     text = text,
    --     color = player.color,
    --     position = player.physical_position,
    --     speed = 0.8
    -- }
end



Public.once_skills = once_skills

-- 一次性技能函数定义
-- local function dgzg(player)
--     local k = 'bullet'
--     local e = game.forces.player
--     local e_old = e.get_ammo_damage_modifier(k)
--     e.set_ammo_damage_modifier(k, 0.1 + e_old)
--     new_print(player, {'tianfu.dgzg_over'})
--     return true
-- end


local function hc(player, q_idx)
    local index = player.index
    local main_table = WPT.get()
    if not main_table.qcdj[index] then
        main_table.qcdj[index] = 1
    end
    main_table.qcdj[index] = main_table.qcdj[index] + TianfuQuality.qround(5 * COEFF_LOW[q_idx or 1])
    new_print(player, {'tianfu.hc_over'})
    return true
end

local function rich_son(player, q_idx)
    player.insert({
        name = 'coin',
        count = math.floor(7000 * COEFF_REG[q_idx or 1])
    })
    new_print(player, {'tianfu.rich_son_over'})
    return true
end

local function shit_luck(player, q_idx)
    -- 随机决定抽奖次数（品质越高次数越多）
    local draw_count = ({2, 3, 4, 5, 6})[q_idx or 1]

    for i = 1, draw_count do
        local luck = math.floor(math.random(1, 150))
        new_print(player, {'amap.lucknb', luck})
        local magic = luck * 5 + 100
        local position = player.physical_surface.find_non_colliding_position("steel-chest", player.physical_position, 20, 1, true) or player.physical_position

        -- 50%概率升级为品质宝箱
        if math.random() <= 0.5 then
            -- 使用品质开箱函数
            Loot.cool_with_quality(
                player.physical_surface,
                position,
                'steel-chest',
                magic
            )
        else
            -- 使用普通开箱函数
            Loot.cool(player.physical_surface, position, 'steel-chest', magic)
        end
    end

    local msg = {'amap.whatopen'}
    Alert.alert_player(player, 5, msg)
    new_print(player, {'tianfu.shit_luck_over'})
    return true
end

local function tsxf(player, q_idx)
    local rpg_t = rpgtable.get('rpg_t')
    rpg_t[player.index].xp = rpg_t[player.index].xp + TianfuQuality.qround(4000 * COEFF_REG[q_idx or 1])
    return true
end

local function bulider(player, q_idx)
    local rpg_t = rpgtable.get('rpg_t')
    local c = q_idx or 1
    rpg_t[player.index].dexterity = rpg_t[player.index].dexterity + TianfuQuality.qround(15 * COEFF_REG[c])
    rpg_t[player.index].crafting_speed = rpg_t[player.index].crafting_speed + TianfuQuality.qround(1 * COEFF_LOW[c])
    -- 增加背包格子+10（低基础值，用 LOW 系数）
    if player.character and player.character.valid then
        player.character.character_inventory_slots_bonus = (player.character.character_inventory_slots_bonus or 0) + TianfuQuality.qround(10 * COEFF_LOW[c])
    end
    return true
end

local function chishang(player, q_idx)
    local amount = math.floor(3000 * COEFF_REG[q_idx or 1])
    for l, player1 in pairs(game.connected_players) do
        player1.insert({
            name = 'coin',
            count = amount
        })
        player1.print({'tianfu.chishang_over', player.name})
    end
    player.remove_item {
        name = 'coin',
        count = amount
    }

    return true
end

local function quanneng(player, q_idx)
    local rpg_t = rpgtable.get('rpg_t')
    local v = TianfuQuality.qround(15 * COEFF_REG[q_idx or 1])
    rpg_t[player.index].vitality = rpg_t[player.index].vitality + v
    rpg_t[player.index].magicka = rpg_t[player.index].magicka + v
    rpg_t[player.index].strength = rpg_t[player.index].strength + v
    rpg_t[player.index].dexterity = rpg_t[player.index].dexterity + v
    return true
end





local function mokuaizhuangjia(player, q_idx)
    -- 赠送模块装甲MK0和相关装备（成品类：物品品质 = 天赋品质）
    local q = QUALITY_NAMES[q_idx or 1]
    player.insert({
        name = 'modular-armor',
        count = 1,
        quality = q
    })
    player.insert({
        name = 'construction-robot',
        count = 10,
        quality = q
    })
    player.insert({
        name = 'personal-roboport-equipment',
        count = 1,
        quality = q
    })
    player.insert({
        name = 'battery-equipment',
        count = 2,
        quality = q
    })
    player.insert({
        name = 'solar-panel-equipment',
        count = 10,
        quality = q
    })
    new_print(player, {'tianfu.mokuaizhuangjia_over'})
    return true
end

local function rs(player, q_idx)
    local rpg_t = rpgtable.get('rpg_t')
    local rs_gain = TianfuQuality.qround(80 * COEFF_REG[q_idx or 1])
    rpg_t[player.index].vitality = rpg_t[player.index].vitality + rs_gain
    new_print(player, {'tianfu.rs_over', rs_gain})
    return true
end

local function xuetu(player, q_idx)
    local main_table = WPT.get()
    -- 手搓经验倍数+1.5（低基础值，用 LOW 系数）
    main_table.crafting_exp_multiplier[player.index] = main_table.crafting_exp_multiplier[player.index] + 1.5 * COEFF_LOW[q_idx or 1]
    new_print(player, {'tianfu.xuetu_over'})
    return true
end

local function waixinglaike(player, q_idx)
    -- 成品类：生物实验室品质 = 天赋品质
    player.insert({
        name = 'biolab',
        count = 1,
        quality = QUALITY_NAMES[q_idx or 1]
    })
    new_print(player, {'tianfu.waixinglaike_over'})
    return true
end

local function jqrpu(player, q_idx)
    -- 成品类：机器人指令塔/储物箱/建筑机器人 品质 = 天赋品质
    local q = QUALITY_NAMES[q_idx or 1]
    player.insert({
        name = 'roboport',
        count = 2,
        quality = q
    })
    player.insert({
        name = 'storage-chest',
        count = 1,
        quality = q
    })
    player.insert({
        name = 'construction-robot',
        count = 130,
        quality = q
    })
    new_print(player, {'tianfu.jqrpu_over'})
    return true
end

-- 一次性技能表
local once_skills = {
    -- ['dgzg'] = {
    --     name = dgzg
    -- },
    ['hc'] = {
        name = hc
    },
    ['rich_son'] = {
        name = rich_son
    },

    ['shit_luck'] = {
        name = shit_luck
    },
    ['rs'] = {
        name = rs
    },
    ['tsxf'] = {
        name = tsxf
    },
    ['bulider'] = {
        name = bulider
    },
    ['chishang'] = {
        name = chishang
    },
    ['quanneng'] = {
        name = quanneng
    },

    ['mokuaizhuangjia'] = {
        name = mokuaizhuangjia
    },
    ['xuetu'] = {
        name = xuetu
    },
    ['waixinglaike'] = {
        name = waixinglaike
    },
    ['jqrpu'] = {
        name = jqrpu
    }
}

-- 公共接口
Public.once_skills = once_skills
Public.dgzg = dgzg
Public.hc = hc
Public.rich_son = rich_son
Public.shit_luck = shit_luck
Public.rs = rs
Public.tsxf = tsxf
Public.bulider = bulider
Public.chishang = chishang
Public.quanneng = quanneng
-- Public.high_debt = high_debt
Public.mokuaizhuangjia = mokuaizhuangjia
Public.jqrpu = jqrpu
Public.xuetu = xuetu
Public.waixinglaike = waixinglaike

return Public