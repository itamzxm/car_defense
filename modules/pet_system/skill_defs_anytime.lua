-- ============================================================
-- anytime 技能定义（从 skills.lua 拆分，逐字保留，勿手改逻辑）
-- 填充共享 skill_defs 表；execute 闭包内自引用 skill_defs['技能名'] 保持有效
-- ============================================================

local EntityCache = require 'maps.amap.entity_cache'
local RPG = require 'modules.rpg.core'
local Task = require 'utils.task'
local pet_table = require 'modules.pet_system.table'
local Helpers = require 'modules.pet_system.skill_helpers'

local QSPRITE = Helpers.QSPRITE
local show_skill_text = Helpers.show_skill_text
local show_damage_text = Helpers.show_damage_text
local destroy_turret_token = Helpers.destroy_turret_token
local juesi_check_token = Helpers.juesi_check_token
local remove_speed_buff_token = Helpers.remove_speed_buff_token
local active_lava_burst_token = Helpers.active_lava_burst_token
local tesla_bounce_token = Helpers.tesla_bounce_token
local leizhenyu_strike_token = Helpers.leizhenyu_strike_token
local restore_yemu_token = Helpers.restore_yemu_token

return function(skill_defs)

skill_defs['打工人'] = {
    name = '打工人',
    category = 'anytime',
    trigger = 'time',
    quality_values = {3, 4, 5, 6, 7},  -- 普通到传说
    execute = function(player, pet, q_idx)
        local amount = pet.level * skill_defs['打工人'].quality_values[q_idx]
        if player.character and player.character.valid then
            player.insert({name = 'coin', count = amount})
        end
    end,
}

skill_defs['金炼'] = {
    name = '金炼',
    category = 'anytime',
    trigger = 'time',
    quality_values = {1, 2, 3, 4, 5},  -- 经验系数（普通到传说）
    execute = function(player, pet, q_idx)
        local xp = pet.level * skill_defs['金炼'].quality_values[q_idx]
        RPG.gain_xp(player, xp)
    end,
}

skill_defs['疯长'] = {
    name = '疯长',
    category = 'anytime',
    trigger = 'time',
    quality_values = {0.6, 0.8, 1.0, 1.2, 1.4},
    execute = function(player, pet, q_idx)
        local mult = skill_defs['疯长'].quality_values[q_idx]
        local rpg_t = RPG.get_value_from_player(player.index)
        local magicka = (rpg_t and rpg_t.magicka) or 0
        local natural_xp = 5 + 10 * (magicka / 100)
        local bonus_xp = math.floor(natural_xp * mult)
        if bonus_xp > 0 then
            pet.exp = pet.exp + bonus_xp
        end
    end,
}

skill_defs['闭关修炼'] = {
    name = '闭关修炼',
    category = 'anytime',
    trigger = 'time',
    quality_values = {1, 2, 3, 4, 5},
    execute = function(player, pet, q_idx)
        -- 出战中的宠物不算"闭关修炼"，必须处于休战状态
        if pet.unit and pet.unit.valid then return end
        local points = skill_defs['闭关修炼'].quality_values[q_idx]
        -- 检查是否连续 3 分钟（10800 ticks）未出战
        -- last_recall_tick 为 nil 时（从未出战），用宠物创建时间 pet.created_tick 兜底
        local last_recall = pet.last_recall_tick or pet.created_tick or 0
        if game.tick - last_recall >= 10800 then
            pet.skill_points = pet.skill_points + points
        end
    end,
}

skill_defs['疗愈师'] = {
    name = '疗愈师',
    category = 'anytime',
    trigger = 'time',
    quality_values = {6, 10, 16, 20, 24},  -- 生命值百分比（普通到传说）
    execute = function(player, pet, q_idx)
        local pct = skill_defs['疗愈师'].quality_values[q_idx]
        local heal = math.ceil(pet.max_hp * pct / 100)
        pet.hp = math.min(pet.max_hp, pet.hp + heal)
    end,
}

skill_defs['自给自足'] = {
    name = '自给自足',
    category = 'anytime',
    trigger = 'time',
    quality_values = {1, 1, 2, 3, 4},  -- 鱼系数（普通到传说）
    execute = function(player, pet, q_idx)
        local fish = pet.level * skill_defs['自给自足'].quality_values[q_idx]
        if fish > 0 and player.character and player.character.valid then
            player.insert({name = 'raw-fish', count = fish})
        end
    end,
}

skill_defs['军火商'] = {
    name = '军火商',
    category = 'anytime',
    trigger = 'time',
    quality_values = {1.2, 1.4, 1.6, 1.8, 2.0},  -- 品质系数（普通到传说）
    execute = function(player, pet, q_idx)
        local base_value = calculate_production_base_value(pet.attack)
        local total_value = math.floor(base_value * skill_defs['军火商'].quality_values[q_idx])
        if total_value <= 0 then return end

        local items = pick_random_items(military_items, 3)
        local item_count = #items
        if item_count == 0 then return end

        local char = player.character
        if not char or not char.valid then return end

        local total_inserted = 0
        for _, item_name in ipairs(items) do
            local item_value = calculate_base_item_value(item_name)
            local count = math.floor(total_value / item_value / item_count)
            if count > 0 then
                char.insert({name = item_name, count = count})
                total_inserted = total_inserted + count
            end
        end

        if total_inserted > 0 then
            show_skill_text(player, pet, ({'pet_system.skill_junhuoshang_text', total_inserted}), {r = 0.8, g = 0.4, b = 0.2})
        end
    end,
}

skill_defs['编织者'] = {
    name = '编织者',
    category = 'anytime',
    trigger = 'time',
    interval_ticks = 3600,
    quality_values = {3, 5, 7, 8, 10},
    execute = function(player, pet, q_idx)
        local pet_data = pet_table.get_player_pet_data(player)
        local item_name = pet_data.last_crafted_item
        if not item_name then
            -- 没有手搓物品，静默跳过（不显示文本，因为宠物可能未出战）
            return
        end
        
        local recipe = prototypes.recipe[item_name]
        if not recipe then
            show_skill_text(player, pet, ({'pet_system.skill_bianzhizhe_no_recipe'}), {r = 0.8, g = 0.4, b = 0.4})
            return
        end
        
        -- 计算合成数量 = floor(攻击力 × 0.1)，最小为1
        local count = math.floor(pet.attack * 0.1)
        if count < 1 then count = 1 end
        
        -- 计算配方单次产出量
        local product_amount = 1
        for _, product in pairs(recipe.products) do
            if product.name == item_name then
                product_amount = product.amount or product.amount_min or 1
                break
            end
        end
        
        -- 需要执行的配方次数（取整）
        local runs = math.ceil(count / product_amount)
        
        -- 检查材料是否充足
        for _, ingredient in pairs(recipe.ingredients) do
            if ingredient.type == 'item' then
                local required = runs * ingredient.amount
                local has = player.get_item_count(ingredient.name)
                if has < required then
                    -- 材料不足，进入冷却（由调度器自动设置冷却）
                    show_skill_text(player, pet, ({'pet_system.skill_bianzhizhe_no_material'}), {r = 0.9, g = 0.2, b = 0.4})
                    return
                end
            end
        end
        
        -- 消耗材料
        for _, ingredient in pairs(recipe.ingredients) do
            if ingredient.type == 'item' then
                player.remove_item({name = ingredient.name, count = runs * ingredient.amount})
            end
        end
        
        -- 给予产物（一次插入总量，避免重复调用）
        local total_products = runs * product_amount
        player.insert({name = item_name, count = total_products})
        
        -- 金币 = 最大Mana × 品质系数%
        local rpg_t = RPG.get_value_from_player(player.index)
        local mana_max = (rpg_t and rpg_t.mana_max) or 100
        local coins = math.floor(mana_max * skill_defs['编织者'].quality_values[q_idx] / 100)
        if coins > 0 then
            player.insert({name = 'coin', count = coins})
        end
        
        show_skill_text(player, pet, ({'pet_system.skill_bianzhizhe_text', total_products, coins}), {r = 0.3, g = 0.8, b = 0.2})
    end,
}

skill_defs['工业家'] = {
    name = '工业家',
    category = 'anytime',
    trigger = 'time',
    quality_values = {1.2, 1.4, 1.6, 1.8, 2.0},  -- 品质系数（普通到传说）
    execute = function(player, pet, q_idx)
        local base_value = calculate_production_base_value(pet.attack)
        local total_value = math.floor(base_value * skill_defs['工业家'].quality_values[q_idx])
        if total_value <= 0 then return end

        local items = pick_random_items(industrial_items, 3)
        local item_count = #items
        if item_count == 0 then return end

        local char = player.character
        if not char or not char.valid then return end

        local total_inserted = 0
        for _, item_name in ipairs(items) do
            local item_value = calculate_base_item_value(item_name)
            local count = math.floor(total_value / item_value / item_count)
            if count > 0 then
                char.insert({name = item_name, count = count})
                total_inserted = total_inserted + count
            end
        end

        if total_inserted > 0 then
            show_skill_text(player, pet, ({'pet_system.skill_gongyejia_text', total_inserted}), {r = 0.4, g = 0.6, b = 0.8})
        end
    end,
}
end
