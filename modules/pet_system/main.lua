-- 虫子宠物系统 - 主入口，事件处理
local Event = require 'utils.event'
local GuiDispatcher = require 'utils.gui_dispatcher'
local Gui = require 'utils.gui'
local SpamProtection = require 'utils.spam_protection'
local GuiRebuild = require 'utils.gui_rebuild'

local GuiDraw = require 'modules.pet_system.gui'
local Public = require 'modules.pet_system.table'
local RPG = require 'modules.rpg.core'
local EntityCache = require 'maps.amap.entity_cache'
local Skills = require 'modules.pet_system.skills'

local draw_main_button_name = Public.draw_main_button_name
local main_frame_name = Public.main_frame_name
local detail_frame_name = Public.detail_frame_name
local confirm_frame_name = Public.confirm_frame_name
local exp_transfer_frame_name = Public.exp_transfer_frame_name
local skill_replace_frame_name = Public.skill_replace_frame_name
local help_frame_name = Public.help_frame_name
local rename_frame_name = Public.rename_frame_name
local card_button_prefix = Public.card_button_prefix

local floor = math.floor

-- 品质整数 → Factorio 原生 quality sprite 名
local QSPRITE = {'normal', 'uncommon', 'rare', 'epic', 'legendary'}

-- ============================================================
-- 属性分配处理
-- ============================================================

local function handle_stat_change(player, pet_index, stat, delta, shift, button)
    local pet_data = Public.get_player_pet_data(player)
    local pet = pet_data.pets[pet_index]
    if not pet then return end

    -- 出战中的宠物不能调整属性
    if pet.unit and pet.unit.valid then
        player.print({'pet_system.cannot_modify_in_combat'}, {r = 255, g = 150, b = 100})
        return
    end

    local amount = 1
    if shift then
        if button == defines.mouse_button_type.left then
            -- Shift+左键：全加
            amount = pet.skill_points
        elseif button == defines.mouse_button_type.right then
            -- Shift+右键：加一半
            amount = floor(pet.skill_points / 2)
        end
    elseif button == defines.mouse_button_type.right then
        -- 右键：加5点
        amount = 5
    end

    if delta < 0 then
        -- 减少（重置）
        if stat == 'atk' then
            amount = math.min(amount, pet.allocated_attack)
        else
            amount = math.min(amount, pet.allocated_hp)
        end
    else
        amount = math.min(amount, pet.skill_points)
    end

    if amount <= 0 then
        player.print({'pet_system.no_points'}, {r = 255, g = 150, b = 100})
        return
    end

    if stat == 'atk' then
        if delta > 0 then
            pet.allocated_attack = pet.allocated_attack + amount
            pet.skill_points = pet.skill_points - amount
            pet.attack = pet.base_attack + pet.allocated_attack * 2
        else
            pet.allocated_attack = pet.allocated_attack - amount
            pet.skill_points = pet.skill_points + amount
            pet.attack = pet.base_attack + pet.allocated_attack * 2
        end
    elseif stat == 'hp' then
        if delta > 0 then
            pet.allocated_hp = pet.allocated_hp + amount
            pet.skill_points = pet.skill_points - amount
            local hp_pct = pet.hp / pet.max_hp
            local new_max = pet.base_hp + pet.allocated_hp * 10
            pet.hp = math.ceil(new_max * hp_pct)
            pet.max_hp = new_max
        else
            pet.allocated_hp = pet.allocated_hp - amount
            pet.skill_points = pet.skill_points + amount
            local hp_pct = pet.hp / pet.max_hp
            local new_max = pet.base_hp + pet.allocated_hp * 10
            pet.hp = math.ceil(new_max * hp_pct)
            pet.max_hp = new_max
        end
    end

    -- 刷新详情面板
    GuiDraw.show_detail(player, pet_index)
end

-- ============================================================
-- 购买宠物蛋
-- ============================================================

local egg_names = {low = {'pet_system.egg_low'}, mid = {'pet_system.egg_mid'}, high = {'pet_system.egg_high'}}

local function purchase_egg(player, egg_type)
    if not player or not player.valid then return end
    if not player.character or not player.character.valid then return end

    local pet_data = Public.get_player_pet_data(player)

    -- 检查宠物数量上限
    if #pet_data.pets >= 3 then
        player.print({'pet_system.pet_full'}, {r = 255, g = 100, b = 100})
        return
    end

    -- 检查金币
    local price = Public.egg_prices[egg_type]
    local coin_count = player.character.get_item_count('coin')
    if coin_count < price then
        player.print({'pet_system.not_enough_coin', price, coin_count}, {r = 255, g = 100, b = 100})
        return
    end

    -- 扣金币
    player.remove_item({name = 'coin', count = price})

    -- 获取玩家当前等级
    local rpg_t = RPG.get_value_from_player(player.index)
    local player_level = (rpg_t and rpg_t.level) or 1

    -- 生成宠物
    local pet = Public.generate_pet(player, egg_type, player_level)

    -- 添加到宠物列表
    pet_data.pets[#pet_data.pets + 1] = pet

    -- 分配专属技能（根据宠物类型自动获得）
    Skills.assign_exclusive_skill(pet)

    -- 自带一个低级技能（非专属，放在槽位2）
    local born_skill = Skills.roll_skill_from_book('low')
    if born_skill then
        pet.skills[2] = born_skill
    end

    -- 反馈
    local type_name = Public.pet_type_names[pet.type] or pet.type
    player.print({'pet_system.egg_open', type_name, Public.quality_locale(pet.quality), pet.level, egg_names[egg_type], pet.name}, {r = 100, g = 255, b = 100})
    if born_skill then
        player.print({'pet_system.born_skill', pet.name, born_skill.name, Public.quality_locale(born_skill.quality)}, {r = 100, g = 200, b = 255})
    end

    -- 刷新 GUI
    GuiDraw.toggle(player)
    GuiDraw.toggle(player)
end

-- ============================================================
-- 购买技能书
-- ============================================================

local book_names = {low = {'pet_system.book_low'}, mid = {'pet_system.book_mid'}, high = {'pet_system.book_high'}}

local function purchase_skill_book(player, book_type)
    if not player or not player.valid then return end
    if not player.character or not player.character.valid then return end

    local pet_data = Public.get_player_pet_data(player)

    -- 检查金币
    local price = Public.skill_book_prices[book_type]
    local coin_count = player.character.get_item_count('coin')
    if coin_count < price then
        player.print({'pet_system.not_enough_coin', price, coin_count}, {r = 255, g = 100, b = 100})
        return
    end

    -- 扣金币
    player.remove_item({name = 'coin', count = price})

    -- 添加技能书
    if not pet_data.skill_books then
        pet_data.skill_books = {low = 0, mid = 0, high = 0}
    end
    pet_data.skill_books[book_type] = pet_data.skill_books[book_type] + 1

    local total = pet_data.skill_books[book_type]
    player.print({'pet_system.book_bought', book_names[book_type], total}, {r = 100, g = 200, b = 255})

    -- 购买成功
end

-- ============================================================
-- 经验转移
-- ============================================================

local function allocate_exp_to_pet(player, pet_index, amount)
    if amount <= 0 then return end

    local pet_data = Public.get_player_pet_data(player)
    local pet = pet_data.pets[pet_index]
    if not pet then return end

    -- 获取玩家 RPG 数据（必须用 RPG.get('rpg_t') 拿整个表再按下标取，
    -- 这样修改 xp 才会真正写回全局表；get_value_from_player 只能读不能写）
    local rpg_t_all = RPG.get('rpg_t')
    local rpg_t = rpg_t_all and rpg_t_all[player.index]
    if not rpg_t then
        player.print({'pet_system.no_rpg_data'}, {r = 255, g = 100, b = 100})
        return
    end

    -- 检查玩家经验是否足够
    if rpg_t.xp < amount then
        player.print({'pet_system.not_enough_exp', rpg_t.xp, amount}, {r = 255, g = 100, b = 100})
        return
    end

    -- 计算宠物等级上限（至少为1）
    local max_level = math.max(1, math.floor(rpg_t.level / 2))
    if pet.level >= max_level then
        player.print({'pet_system.pet_level_cap', pet.level, max_level}, {r = 255, g = 150, b = 100})
        return
    end

    -- 计算当前宠物累计经验
    local current_total = (Public.experience_levels[pet.level] or 0) + pet.exp
    -- 到达等级上限需要的总经验
    local xp_at_cap = Public.experience_levels[max_level] or 0
    -- 到达上限还需要的经验
    local xp_needed = xp_at_cap - current_total

    local actual_amount = amount
    local refund = 0

    if amount > xp_needed then
        -- 超出了上限，只用到上限所需的经验，退回多余
        actual_amount = xp_needed
        refund = amount - xp_needed
    end

    -- 先扣除玩家输入的全部经验量
    rpg_t.xp = rpg_t.xp - amount

    -- 超出等级上限的部分直接退回 rpg_t.xp（不调用 gain_xp，避免税收/加成/升级等副作用）
    if refund > 0 then
        rpg_t.xp = rpg_t.xp + refund
        player.print({'pet_system.exp_refund', refund}, {r = 255, g = 200, b = 100})
    end

    -- 计算宠物总经验
    local total_xp = current_total + actual_amount

    -- 计算新等级
    local new_level = pet.level
    local levels_gained = 0
    for lvl = pet.level + 1, max_level do
        if total_xp >= (Public.experience_levels[lvl] or 0) then
            new_level = lvl
            levels_gained = levels_gained + 1
        else
            break
        end
    end

    -- 更新宠物数据
    local remaining_xp = total_xp - (Public.experience_levels[new_level] or 0)
    pet.level = new_level
    pet.exp = remaining_xp

    -- 每升一级增加技能点
    if levels_gained > 0 then
        local points_per_level = Public.quality_skill_points[pet.quality] or 5
        pet.skill_points = pet.skill_points + levels_gained * points_per_level
        player.print({'pet_system.exp_transfer_level_up', levels_gained, new_level}, {r = 100, g = 255, b = 100})
    end

    -- 检查进化
    local evolved, new_type = Public.check_evolution(pet)
    if evolved then
        local type_name = Public.pet_type_names[new_type] or new_type
        player.print({'pet_system.pet_evolved', type_name}, {r = 100, g = 255, b = 150})
        replace_deployed_unit(player, pet, pet_index)
    end

    player.print({'pet_system.exp_transfer_done', actual_amount, pet.level}, {r = 100, g = 255, b = 100})
end

-- ============================================================
-- 使用技能书
-- ============================================================

local function apply_skill_book(player, pet_index, book_type)
    local pet_data = Public.get_player_pet_data(player)
    local pet = pet_data.pets[pet_index]
    if not pet then return end

    local books = pet_data.skill_books or {low = 0, mid = 0, high = 0}
    if (books[book_type] or 0) <= 0 then
        player.print({'pet_system.no_skill_books'}, {r = 255, g = 150, b = 100})
        return
    end

    -- 消耗技能书
    books[book_type] = books[book_type] - 1

    -- 从技能书获得随机技能
    local new_skill = Skills.roll_skill_from_book(book_type)
    if not new_skill then
        player.print({'pet_system.not_implemented'}, {r = 255, g = 200, b = 100})
        return
    end

    -- 找空位或随机替换
    local empty_slot = nil
    local max_slots = Public.get_skill_slots(pet)
    for i = 1, max_slots do
        if not pet.skills[i] then
            empty_slot = i
            break
        end
    end

    if empty_slot then
        pet.skills[empty_slot] = new_skill
        player.print({'pet_system.skill_learned', pet.name, new_skill.name, Public.quality_locale(new_skill.quality)}, {r = 100, g = 200, b = 255})
        -- 刷新详情面板显示新技能
        GuiDraw.show_detail(player, pet_index)
    else
        -- 已满，弹出选择弹窗（弹窗内部会处理后续刷新）
        GuiDraw.draw_skill_replace_popup(player, pet, pet_index, new_skill)
    end
end

-- ============================================================
-- GuiDispatcher 注册（精确匹配的元素名）
-- ============================================================

local function on_toggle_main_panel(event)
    local player = game.players[event.player_index]
    local is_spam = SpamProtection.is_spamming(player, nil, 'Pet System Toggle')
    if is_spam then return end

    local pet_data = Public.get_player_pet_data(player)
    if not pet_data.free_pet_given and #pet_data.pets < 3 then
        local rpg_t = RPG.get_value_from_player(player.index)
        if rpg_t and (rpg_t.magicka or 0) >= 50 then
            pet_data.free_pet_given = true
            local free_pet = {
                name = Public.generate_pet_name(),
                type = 'small-biter',
                quality = 1,
                level = 1,
                hunger = 100,
                max_hunger = 100,
                hp = 5,
                max_hp = 5,
                attack = 5,
                base_attack = 5,
                base_hp = 5,
                exp = 0,
                skill_points = 3,
                allocated_attack = 0,
                allocated_hp = 0,
                skills = {nil, nil, nil, nil},
                created_tick = game.tick,
            }
            pet_data.pets[#pet_data.pets + 1] = free_pet

            Skills.assign_exclusive_skill(free_pet)

            local born_skill = Skills.roll_skill_from_book('low')
            if born_skill then
                free_pet.skills[2] = born_skill
            end

            player.print({'pet_system.free_pet_received', free_pet.name}, {r = 100, g = 255, b = 100})
            if born_skill then
                player.print({'pet_system.born_skill', free_pet.name, born_skill.name, Public.quality_locale(born_skill.quality)}, {r = 100, g = 200, b = 255})
            end
        end
    end

    GuiDraw.toggle(player)
end

GuiDispatcher.register_click(draw_main_button_name, on_toggle_main_panel)

local function on_help_toggle(event)
    local player = game.players[event.player_index]
    if player.gui.screen[help_frame_name] then
        GuiDraw.hide_help(player)
    else
        GuiDraw.draw_help_popup(player)
    end
end

GuiDispatcher.register_click(main_frame_name .. '_help', on_help_toggle)

local function on_help_close(event)
    local player = game.players[event.player_index]
    GuiDraw.hide_help(player)
end

GuiDispatcher.register_click(help_frame_name .. '_close', on_help_close)

local function on_buy_low_egg(event)
    purchase_egg(game.players[event.player_index], 'low')
end

GuiDispatcher.register_click(main_frame_name .. '_buy_low_egg', on_buy_low_egg)

local function on_buy_mid_egg(event)
    purchase_egg(game.players[event.player_index], 'mid')
end

GuiDispatcher.register_click(main_frame_name .. '_buy_mid_egg', on_buy_mid_egg)

local function on_buy_high_egg(event)
    purchase_egg(game.players[event.player_index], 'high')
end

GuiDispatcher.register_click(main_frame_name .. '_buy_high_egg', on_buy_high_egg)

local function on_exp_transfer_cancel(event)
    local player = game.players[event.player_index]
    local popup = player.gui.screen[exp_transfer_frame_name]
    if popup and popup.valid then
        Gui.remove_data_recursively(popup)
        popup.destroy()
    end
end

GuiDispatcher.register_click(exp_transfer_frame_name .. '_cancel', on_exp_transfer_cancel)

local function on_confirm_eat_cancel(event)
    local player = game.players[event.player_index]
    local popup = player.gui.screen[confirm_frame_name]
    if popup and popup.valid then
        Gui.remove_data_recursively(popup)
        popup.destroy()
    end
end

GuiDispatcher.register_click(confirm_frame_name .. '_cancel', on_confirm_eat_cancel)

local function on_skill_replace_cancel(event)
    local player = game.players[event.player_index]
    local popup = player.gui.screen[skill_replace_frame_name]
    if popup and popup.valid then
        Gui.remove_data_recursively(popup)
        popup.destroy()
    end
end

GuiDispatcher.register_click(skill_replace_frame_name .. '_cancel', on_skill_replace_cancel)

local function on_rename_cancel(event)
    local player = game.players[event.player_index]
    GuiDraw.hide_rename_popup(player)
end

GuiDispatcher.register_click(rename_frame_name .. '_cancel', on_rename_cancel)

-- ============================================================
-- GUI 点击事件处理（模式匹配分支）
-- ============================================================

local function recall_pet(player, pet)
    pet.name_tag = nil
    local old_unit_number = pet.unit_number
    if pet.unit and pet.unit.valid then
        -- 回收实体剩余血量到后台
        pet.hp = pet.hp + math.floor(pet.unit.health)
        pet.unit.destroy()
    end
    -- 清理反向索引
    if old_unit_number then
        local this = Public.get()
        this.unit_to_owner[old_unit_number] = nil
    end
    -- 清除临时攻击加成（愤怒收割者）
    if pet.temp_attack_mult then
        pet.attack = math.floor(pet.attack / pet.temp_attack_mult)
        pet.temp_attack_mult = nil
    end
    -- 记录召回时间（用于闭关修炼等技能）
    pet.last_recall_tick = game.tick
    -- 从出战列表移除（通过 unit_number 匹配）
    if old_unit_number then
        local this = Public.get()
        for i, entry in ipairs(this.deployed_pets) do
            local entry_pet = Public.get_player_pet_data(player).pets[entry.pet_index]
            if entry_pet and entry_pet.unit_number == old_unit_number then
                table.remove(this.deployed_pets, i)
                break
            end
        end
    end
    pet.unit = nil
    pet.unit_number = nil
end

local function on_gui_click(event)
    local element = event.element
    if not element or not element.valid then return end

    local player = game.players[event.player_index]
    if not player or not player.valid then return end

    local name = element.name

    -- 点击宠物卡片
    if name and string.find(name, '^' .. card_button_prefix .. '_') then
        local pet_index = tonumber(string.match(name, '_(%d+)$'))
        if pet_index then
            local main_frame = player.gui.screen[main_frame_name]
            if main_frame and main_frame.valid then
                local data = Gui.get_data(main_frame)
                -- 同一个卡片再次点击 → 收起详情
                if data and data.current_detail_pet_index == pet_index then
                    GuiDraw.hide_detail(player)
                else
                    GuiDraw.show_detail(player, pet_index)
                end
            else
                GuiDraw.show_detail(player, pet_index)
            end
        end
        return
    end

    -- 关闭详情面板
    if name and string.find(name, '^' .. detail_frame_name .. '_close_') then
        GuiDraw.hide_detail(player)
        return
    end

    -- 属性加点
    if name and string.find(name, '^' .. detail_frame_name .. '_plus_') then
        local stat, pet_index
        if string.find(name, '_atk_') then
            stat = 'atk'
        elseif string.find(name, '_hp_') then
            stat = 'hp'
        end
        pet_index = tonumber(string.match(name, '_(%d+)$'))
        if stat and pet_index then
            handle_stat_change(player, pet_index, stat, 1, event.shift, event.button)
        end
        return
    end

    if name and string.find(name, '^' .. detail_frame_name .. '_minus_') then
        local stat, pet_index
        if string.find(name, '_atk_') then
            stat = 'atk'
        elseif string.find(name, '_hp_') then
            stat = 'hp'
        end
        pet_index = tonumber(string.match(name, '_(%d+)$'))
        if stat and pet_index then
            handle_stat_change(player, pet_index, stat, -1, event.shift, event.button)
        end
        return
    end

    -- 分配经验按钮
    if name and string.find(name, '^' .. detail_frame_name .. '_alloc_exp_') then
        local pet_index = tonumber(string.match(name, '_(%d+)$'))
        if pet_index then
            GuiDraw.draw_exp_transfer_popup(player, pet_index)
        end
        return
    end

    -- 使用技能书按钮（低级/中级/高级）→ 有书用书，没书买书
    if name and string.find(name, '^' .. detail_frame_name .. '_book_') then
        local book_type = string.match(name, '_book_([a-z]+)_')
        local pet_index = tonumber(string.match(name, '_(%d+)$'))
        if book_type and pet_index then
            local pet_data = Public.get_player_pet_data(player)
            local books = pet_data.skill_books or {low = 0, mid = 0, high = 0}
            if (books[book_type] or 0) <= 0 then
                -- 没有技能书 → 直接购买并使用
                purchase_skill_book(player, book_type)
                apply_skill_book(player, pet_index, book_type)
                -- 面板已在 apply_skill_book 中刷新
            else
                apply_skill_book(player, pet_index, book_type)
            end
        end
        return
    end

    -- 重置加点按钮
    if name and string.find(name, '^' .. detail_frame_name .. '_reset_pts_') then
        local pet_index = tonumber(string.match(name, '_(%d+)$'))
        if pet_index then
            local pet_data = Public.get_player_pet_data(player)
            local pet = pet_data.pets[pet_index]
            if pet then
                -- 出战中的宠物不能重置属性
                if pet.unit and pet.unit.valid then
                    player.print({'pet_system.cannot_modify_in_combat'}, {r = 255, g = 150, b = 100})
                    return
                end
                local returned = pet.allocated_attack + pet.allocated_hp
                pet.skill_points = pet.skill_points + returned
                pet.allocated_attack = 0
                pet.allocated_hp = 0
                pet.attack = pet.base_attack
                local hp_pct = pet.hp / pet.max_hp
                pet.max_hp = pet.base_hp
                pet.hp = math.ceil(pet.max_hp * hp_pct)
                player.print({'pet_system.reset_done', returned}, {r = 100, g = 255, b = 100})
                GuiDraw.show_detail(player, pet_index)
            end
        end
        return
    end

    -- 吞噬宠物按钮
    if name and string.find(name, '^' .. detail_frame_name .. '_eat_pet_') then
        local pet_index = tonumber(string.match(name, '_(%d+)$'))
        if pet_index then
            local pet_data = Public.get_player_pet_data(player)
            local pet = pet_data.pets[pet_index]
            if pet and pet.unit then
                player.print({'pet_system.cannot_eat_in_combat'}, {r = 255, g = 150, b = 100})
                return
            end
            GuiDraw.draw_confirm_eat_popup(player, pet_index)
        end
        return
    end

    -- 宠物名字单击改名
    if name and string.find(name, '^' .. main_frame_name .. '_rename_') then
        local pet_index = tonumber(string.match(name, '_(%d+)$'))
        if pet_index then
            local pet_data = Public.get_player_pet_data(player)
            local pet = pet_data.pets[pet_index]
            if not pet then return end
            GuiDraw.draw_rename_popup(player, pet, pet_index)
        end
        return
    end


    -- ============= 经验转移弹窗 =============

    if name and string.find(name, '^' .. exp_transfer_frame_name .. '_confirm_') then
        local pet_index = tonumber(string.match(name, '_(%d+)$'))
        local popup = player.gui.screen[exp_transfer_frame_name]
        if popup and popup.valid then
            local data = Gui.get_data(popup)
            local input_field
            -- 查找 textfield 元素
            local children = popup.children
            for _, child in pairs(children) do
                if child.type == 'table' then
                    for _, sub in pairs(child.children) do
                        if sub.type == 'textfield' then
                            input_field = sub
                            break
                        end
                    end
                end
            end
            local amount = 0
            if input_field and input_field.valid then
                amount = tonumber(input_field.text) or 0
            end
            Gui.remove_data_recursively(popup)
            popup.destroy()
            if amount > 0 and pet_index then
                allocate_exp_to_pet(player, pet_index, amount)
                GuiDraw.show_detail(player, pet_index)
            end
        end
        return
    end

    -- ============= 吞噬确认弹窗 =============

    if name and string.find(name, '^' .. confirm_frame_name .. '_yes_') then
        local pet_index = tonumber(string.match(name, '_(%d+)$'))
        local popup = player.gui.screen[confirm_frame_name]
        if popup and popup.valid then
            Gui.remove_data_recursively(popup)
            popup.destroy()
        end
        -- 吞噬宠物，80% 经验返还玩家
        if pet_index then
            local pet_data = Public.get_player_pet_data(player)
            local pet = pet_data.pets[pet_index]
            if pet then
                local type_name = Public.pet_type_names[pet.type] or pet.type
                -- 计算总经验：到当前等级的累积经验 + 当前等级进度
                local cumulative_xp = (Public.experience_levels[pet.level] or 0) + pet.exp
                local exp_return = floor(cumulative_xp * 0.8)
                recall_pet(player, pet)
                table.remove(pet_data.pets, pet_index)
                -- 给予玩家 RPG 经验
                if exp_return > 0 then
                    RPG.gain_xp(player, exp_return)
                end
                -- 返还技能书：技能数 - 1 本低级技能书
                local book_count = 0
                for _, skill in ipairs(pet.skills) do
                    if skill then book_count = book_count + 1 end
                end
                book_count = math.max(0, book_count - 1)
                if book_count > 0 then
                    if not pet_data.skill_books then
                        pet_data.skill_books = {low = 0, mid = 0, high = 0}
                    end
                    pet_data.skill_books.low = pet_data.skill_books.low + book_count
                end
                player.print({'pet_system.eat_done', type_name, exp_return, book_count}, {r = 255, g = 150, b = 100})
                -- 关闭详情，刷新主面板
                GuiDraw.hide_detail(player)
                GuiDraw.toggle(player)
                GuiDraw.toggle(player)
            end
        end
        return
    end

    -- ============= 技能替换选择弹窗 =============

    if name and string.find(name, '^' .. skill_replace_frame_name .. '_pick_') then
        local slot = tonumber(string.match(name, '_(%d+)$'))
        local popup = player.gui.screen[skill_replace_frame_name]
        if popup and popup.valid then
            local data = Gui.get_data(popup)
            Gui.remove_data_recursively(popup)
            popup.destroy()
            if data and slot and data.pet_index and data.new_skill then
                local pet_data = Public.get_player_pet_data(player)
                local pet = pet_data.pets[data.pet_index]
                if pet and pet.skills[slot] then
                    local old_skill = pet.skills[slot]
                    local old_name = type(old_skill) == 'table' and old_skill.name or tostring(old_skill)
                    pet.skills[slot] = data.new_skill
                    player.print({'pet_system.skill_replaced', old_name, data.new_skill.name, Public.quality_locale(data.new_skill.quality)}, {r = 255, g = 200, b = 100})
                    -- 刷新详情
                    GuiDraw.show_detail(player, data.pet_index)
                end
            end
        end
        return
    end


    if name and string.find(name, '^' .. rename_frame_name .. '_confirm_') then
        local pet_index = tonumber(string.match(name, '_(%d+)$'))
        local popup = player.gui.screen[rename_frame_name]
        if popup and popup.valid then
            local data = Gui.get_data(popup)
            local input_field
            local children = popup.children
            for _, child in pairs(children) do
                if child.type == 'table' then
                    for _, sub in pairs(child.children) do
                        if sub.type == 'textfield' then
                            input_field = sub
                            break
                        end
                    end
                end
            end
            local new_name = nil
            if input_field and input_field.valid then
                new_name = input_field.text
            end
            Gui.remove_data_recursively(popup)
            popup.destroy()
            if new_name and new_name ~= '' and pet_index then
                local pet_data = Public.get_player_pet_data(player)
                local pet = pet_data.pets[pet_index]
                if pet then
                    -- 截断过长名字（最多 10 个中文字符 = 30 字节）
                    if #new_name > 30 then
                        new_name = new_name:sub(1, 30)
                    end
                    local old_name = pet.name
                    pet.name = new_name
                    -- 更新出战标签
                    if pet.name_tag and rendering.is_valid(pet.name_tag) then
                        rendering.set_text(pet.name_tag, new_name)
                    end
                    player.print({'pet_system.rename_done', old_name, new_name}, {r = 100, g = 255, b = 100})
                    -- 刷新 GUI
                    GuiDraw.toggle(player)
                    GuiDraw.toggle(player)
                end
            end
        end
        return
    end

end

-- ============================================================
-- 进化时替换出战单位（仅改变实体类型，其他不变）
-- ============================================================
local function replace_deployed_unit(player, pet, pet_index)
    if not pet.unit or not pet.unit.valid then return end

    local this = Public.get()
    local surface = pet.unit.surface
    local pos = pet.unit.position
    local old_unit_health = math.floor(pet.unit.health)

    -- 回收后台血量
    pet.hp = pet.hp + old_unit_health

    -- 清理旧单位
    if pet.name_tag and rendering.is_valid(pet.name_tag) then
        rendering.destroy(pet.name_tag)
    end
    this.unit_to_owner[pet.unit_number] = nil
    pet.unit.destroy()
    pet.unit = nil
    pet.unit_number = nil
    pet.name_tag = nil

    -- 创建新单位
    local factorio_quality = QSPRITE[pet.quality] or 'normal'

    local unit = surface.create_entity({
        name = pet.type,
        position = pos,
        force = 'player',
        quality = factorio_quality,
    })

    if unit then
        pet.unit = unit
        pet.unit_number = unit.unit_number
        this.unit_to_owner[unit.unit_number] = {
            player_index = player.index,
            pet_index = pet_index,
        }

        -- 同步血量
        local sync_hp = math.min(pet.hp, math.floor(unit.health))
        unit.health = sync_hp
        pet.hp = pet.hp - sync_hp

        unit.ai_settings.allow_try_return_to_spawner = false
        unit.ai_settings.allow_destroy_when_commands_fail = true

        -- 重建 unit_group
        local group = surface.create_unit_group({
            position = pos,
            force = 'player',
        })
        if group then
            group.add_member(unit)
            group.set_command({
                type = defines.command.attack_area,
                destination = player.physical_position,
                radius = 28,
            })
            group.start_moving()
        end

        -- 重建名字标签（进化后）
        pet.name_tag = rendering.draw_text({
            text = pet.name,
            surface = surface,
            target = unit,
            target_offset = {0, -2.5},
            color = {r = player.color.r, g = player.color.g, b = player.color.b, a = 1},
            scale = 0.9,
            font = 'default-game',
            alignment = 'center',
            scale_with_zoom = false,
        })
    end
end

-- ============================================================
-- 自动升级
-- ============================================================

local function auto_level_pet(player, pet, pet_index)
    if not pet then return end

    -- 饥饿值 ≥ 60% 才获得经验
    if pet.hunger < 60 then return end

    local rpg_t = RPG.get_value_from_player(player.index)
    if not rpg_t then return end

    -- 等级上限：玩家等级 / 2（至少为1）
    local max_level = math.max(1, math.floor((rpg_t.level or 1) / 2))
    if pet.level >= max_level then return end

    -- 经验公式：10 + 5% × magicka
    local magicka = rpg_t.magicka or 0
    local xp_per_minute = 10 + magicka * 0.05

    -- 计算到达上限所需经验，限制本次获得的经验
    local current_total = (Public.experience_levels[pet.level] or 0) + pet.exp
    local xp_at_cap = Public.experience_levels[max_level] or 0
    local xp_needed = xp_at_cap - current_total
    local xp_gain = math.min(math.floor(xp_per_minute + 0.5), xp_needed)
    if xp_gain <= 0 then return end

    -- 加经验
    local total_xp = current_total + xp_gain

    -- 计算新等级
    local new_level = pet.level
    local levels_gained = 0
    for lvl = pet.level + 1, max_level do
        if total_xp >= (Public.experience_levels[lvl] or 0) then
            new_level = lvl
            levels_gained = levels_gained + 1
        else
            break
        end
    end

    local remaining_xp = total_xp - (Public.experience_levels[new_level] or 0)
    pet.level = new_level
    pet.exp = remaining_xp

    -- 升级了
    if levels_gained > 0 then
        local points_per_level = Public.quality_skill_points[pet.quality] or 5
        pet.skill_points = pet.skill_points + levels_gained * points_per_level

        player.print({'pet_system.pet_auto_level_up', levels_gained, new_level}, {r = 150, g = 220, b = 150})
    end

    -- 检查进化
    local evolved, new_type = Public.check_evolution(pet)
    if evolved then
        local type_name = Public.pet_type_names[new_type] or new_type
        player.print({'pet_system.pet_evolved', type_name}, {r = 100, g = 255, b = 150})
        replace_deployed_unit(player, pet, pet_index)
    end
end

-- 检查玩家是否在副本中（地表名以 "dungeon_" 开头）
-- 副本中新角色的背包没有 raw-fish，继续扣饥饿会导致宠物饿死
local function is_in_dungeon(player)
    if not player or not player.valid then return false end
    local surface = player.surface
    return surface and surface.valid and surface.name:find("^dungeon_") ~= nil
end

local function process_hunger(player, pet)
    local old_hunger = pet.hunger
    local base_fish = Public.fish_consumption[pet.type] or 1
    local mult = Public.quality_fish_multiplier[pet.quality] or 1.0
    local fish_needed = math.floor(base_fish * mult + 0.5)  -- 四舍五入
    local decay = Public.HUNGER_CHANGE

    local fish_count = player.get_item_count('raw-fish')
    if fish_count >= fish_needed then
        player.remove_item({name = 'raw-fish', count = fish_needed})
        pet.hunger = math.min(100, pet.hunger + decay)
    else
        pet.hunger = math.max(0, pet.hunger - decay)
        local actual_decay = old_hunger - pet.hunger
        if actual_decay > 0 then
            local pet_name = pet.name or (Public.pet_type_names[pet.type] or pet.type)
            player.print({'pet_system.hunger_decay_msg', pet_name, actual_decay}, {r = 255, g = 150, b = 80})
        end
    end
end

-- ============================================================
-- 批处理 on_tick（每分钟触发，每次处理 1 个玩家，参考天赋系统）
-- ============================================================
local function on_tick()
    local this = Public.get()

    -- 收集在线玩家
    local players_list = {}
    for _, player in pairs(game.connected_players) do
        if player and player.valid then
            players_list[#players_list + 1] = player
        end
    end

    if #players_list == 0 then
        this.batch_player_index = 1
        return
    end

    -- 索引回绕
    if this.batch_player_index > #players_list then
        this.batch_player_index = 1
    end

    local player = players_list[this.batch_player_index]
    this.batch_player_index = this.batch_player_index + 1

    if not player or not player.valid then return end

    -- 副本中不处理饥饿（新角色背包无鱼）
    if is_in_dungeon(player) then return end

    local pet_data = Public.get_player_pet_data(player)
    local pets = pet_data.pets
    if #pets == 0 then return end

    -- 每名玩家每分钟只处理一次（通过独立冷却保证）
    if pet_data.last_tick_processed and game.tick - pet_data.last_tick_processed < 3600 then
        return
    end
    pet_data.last_tick_processed = game.tick

    local dead_indices = {}
    for i, pet in ipairs(pets) do
        process_hunger(player, pet)

        -- 战后恢复
        if not pet.unit and pet.hp < pet.max_hp and pet.hunger >= 60 then
            local regen = math.ceil(pet.max_hp * 0.2)
            pet.hp = math.min(pet.max_hp, pet.hp + regen)
        end

        -- 饥饿值 0 → 扣血
        if pet.hunger <= 0 then
            local hp_loss = math.floor(pet.max_hp * 0.1)
            if hp_loss < 1 then hp_loss = 1 end
            pet.hp = pet.hp - hp_loss
            if pet.hp <= 0 then
                dead_indices[#dead_indices + 1] = i
            end
        end

        if pet.hp > 0 then
            auto_level_pet(player, pet, i)
        end
    end

    for i = #dead_indices, 1, -1 do
        local idx = dead_indices[i]
        local dead_pet = pets[idx]
        recall_pet(player, dead_pet)
        local type_name = Public.pet_type_names[dead_pet.type] or dead_pet.type
        player.print({'pet_system.pet_died_starve', type_name}, {r = 255, g = 80, b = 80})
        table.remove(pets, idx)
    end

    Skills.dispatch_anytime_time(player)
end

-- ============================================================
-- 战斗系统 - 出战扫描
-- ============================================================

-- 检查宠物是否符合出战条件
local function can_deploy(pet)
    return pet.hunger >= 60
        and pet.hp >= pet.max_hp * 0.8
        and (not pet.unit or not pet.unit.valid)
end

local function deploy_pet(player, pet, pet_index)
    if not player.character or not player.character.valid then return end

    -- 清理无效引用
    if pet.unit and not pet.unit.valid then
        pet.unit = nil
        pet.name_tag = nil
    end
    if pet.unit then return end  -- 已部署

    local surface = player.physical_surface
    local pos = surface.find_non_colliding_position(
        pet.type, player.physical_position, 5, 1, false
    )
    if not pos then
        pos = player.physical_position
    end

    -- 品质映射
    local factorio_quality = QSPRITE[pet.quality] or 'normal'

    local unit = surface.create_entity({
        name = pet.type,
        position = pos,
        force = 'player',
        quality = factorio_quality,
    })

    if unit then
        pet.unit = unit
        pet.unit_number = unit.unit_number

        -- 注册 unit_number → owner 反向索引
        local this = Public.get()
        this.unit_to_owner[unit.unit_number] = {
            player_index = player.index,
            pet_index = pet_index,
        }
        -- 加入出战列表
        this.deployed_pets[#this.deployed_pets + 1] = {
            player_index = player.index,
            pet_index = pet_index,
        }

        -- 将后台血量同步到实体：实体血量 = min(后台血量, 实体最大血量)
        local sync_hp = math.min(pet.hp, math.floor(unit.health))
        unit.health = sync_hp
        pet.hp = pet.hp - sync_hp
        -- 关闭返回虫巢的 AI
        unit.ai_settings.allow_try_return_to_spawner = false
        unit.ai_settings.allow_destroy_when_commands_fail = true

        -- 创建 unit_group 并设置攻击命令
        local group = surface.create_unit_group({
            position = pos,
            force = 'player',
        })
        if group then
            group.add_member(unit)
            group.set_command({
                type = defines.command.attack_area,
                destination = player.physical_position,
                radius = 28,
            })
            group.start_moving()
        end

        -- 头顶显示文本：宠物名字
        pet.name_tag = rendering.draw_text({
            text = pet.name,
            surface = surface,
            target = unit,
            target_offset = {0, -2.5},
            color = {r = player.color.r, g = player.color.g, b = player.color.b, a = 1},
            scale = 0.9,
            font = 'default-game',
            alignment = 'center',
            scale_with_zoom = false,
        })
    end
end

-- ============================================================
-- on_combat_tick（每 2 tick 处理 1 玩家，独立冷却保证每人每 3 秒扫描一次）
-- ============================================================
local function on_combat_tick()
    local this = Public.get()

    -- 收集在线玩家
    local players_list = {}
    for _, player in pairs(game.connected_players) do
        if player and player.valid then
            players_list[#players_list + 1] = player
        end
    end

    if #players_list == 0 then
        this.batch_combat_index = 1
        return
    end

    if not this.batch_combat_index or this.batch_combat_index > #players_list then
        this.batch_combat_index = 1
    end

    local player = players_list[this.batch_combat_index]
    this.batch_combat_index = this.batch_combat_index + 1

    if not player or not player.valid then return end
    if not player.character or not player.character.valid then return end

    -- 副本中不出战宠物
    if is_in_dungeon(player) then return end

    local pet_data = Public.get_player_pet_data(player)
    local pets = pet_data.pets
    if #pets == 0 then return end

    -- 每人每 180 tick（3秒）只扫描一次
    if pet_data.last_combat_scan_tick and game.tick - pet_data.last_combat_scan_tick < 180 then
        return
    end
    pet_data.last_combat_scan_tick = game.tick

    if not pet_data.combat then
        pet_data.combat = {last_combat_tick = 0, deployed = false}
    end
    local combat = pet_data.combat

    local enemies = EntityCache.find_entities_cached(player.physical_surface, {
        position = player.physical_position,
        radius = 28,
        force = 'enemy',
        type = {'unit', 'turret', 'unit-spawner', 'spider-unit'},
    })

    if #enemies > 0 then
        combat.last_combat_tick = game.tick

        if not combat.deployed then
            local deployed_count = 0
            for i, pet in ipairs(pets) do
                if can_deploy(pet) then
                    deploy_pet(player, pet, i)
                    deployed_count = deployed_count + 1
                    Skills.dispatch_deploy(player, pet)
                end
            end
            if deployed_count > 0 then
                combat.deployed = true
            end
        end
    else
        -- 脱战超过 10 秒 → 召回
        if combat.deployed and game.tick - combat.last_combat_tick > 600 then
            for _, pet in ipairs(pets) do
                recall_pet(player, pet)
            end
            combat.deployed = false
        end
    end
end

-- ============================================================
-- 战斗系统 - 血量与复活
-- ============================================================

local function on_entity_died(event)
    local entity = event.entity
    if not entity or not entity.valid then return end
    local dead_unit_number = entity.unit_number
    if not dead_unit_number then return end

    -- 通过反向索引 O(1) 定位主人
    local this = Public.get()
    local owner_info = this.unit_to_owner[dead_unit_number]
    if not owner_info then return end

    local player = game.players[owner_info.player_index]
    if not player or not player.valid then
        this.unit_to_owner[dead_unit_number] = nil
        return
    end

    local pet_data = Public.get_player_pet_data(player)
    local pet = pet_data.pets[owner_info.pet_index]
    if not pet then
        this.unit_to_owner[dead_unit_number] = nil
        return
    end

    -- 清理死亡 unit 的引用
    pet.unit = nil
    pet.unit_number = nil
    pet.name_tag = nil
    this.unit_to_owner[dead_unit_number] = nil

    -- 触发死亡技能（复活前）
    Skills.dispatch_death(player, pet, entity.position, entity.surface)

    if pet.hp > 0 then
        -- 复活：在死亡位置重新召唤
        local surface = entity.surface
        local pos = entity.position

        local factorio_quality = QSPRITE[pet.quality] or 'normal'

        local unit = surface.create_entity({
            name = pet.type,
            position = pos,
            force = 'player',
            quality = factorio_quality,
        })

        if unit then
            pet.unit = unit
            pet.unit_number = unit.unit_number

            -- 更新反向索引
            this.unit_to_owner[unit.unit_number] = owner_info

                        -- 复活：同步后台血量到新实体
                        local sync_hp = math.min(pet.hp, unit.health)
                        unit.health = sync_hp
                        pet.hp = pet.hp - sync_hp

                        unit.ai_settings.allow_try_return_to_spawner = false
                        unit.ai_settings.allow_destroy_when_commands_fail = true

                        local group = surface.create_unit_group({
                            position = pos,
                            force = 'player',
                        })
                        if group then
                            group.add_member(unit)
                            group.set_command({
                                type = defines.command.attack_area,
                                destination = player.physical_position,
                                radius = 28,
                            })
                            group.start_moving()
                        end

                        pet.name_tag = rendering.draw_text({
                            text = pet.name,
                            surface = surface,
                            target = unit,
                            target_offset = {0, -2.5},
                            color = {r = player.color.r, g = player.color.g, b = player.color.b, a = 1},
                            scale = 0.9,
                            font = 'default-game',
                            alignment = 'center',
                            scale_with_zoom = false,
                        })

            if pet.hp > 0 then
                player.create_local_flying_text({
                    text = ({'pet_system.respawn_text'}),
                    position = {x = pos.x, y = pos.y - 2},
                    color = {r = 0.4, g = 0.8, b = 1},
                    time_to_live = 90,
                    speed = 1.0,
                })
            end
        end

        -- 只有血量和饥饿值同时为 0 才真正死亡
        if pet.hp <= 0 and pet.hunger <= 0 and not pet.unit then
            local type_name = Public.pet_type_names[pet.type] or pet.type
            table.remove(pet_data.pets, owner_info.pet_index)
            player.print({'pet_system.pet_died_combat', type_name}, {r = 255, g = 80, b = 80})
        end
    end
end

-- ============================================================
-- 战斗系统 - 主人受伤触发（护卫技能）
-- ============================================================

local function on_entity_damaged(event)
    local entity = event.entity
    if not entity or not entity.valid then return end
    if entity.type ~= 'character' then return end

    local player = entity.player
    if not player or not player.valid then return end

    local final_damage = event.final_damage_amount
    if final_damage <= 0 then return end

    Skills.dispatch_owner_damaged(player, final_damage, event.cause)
end

-- ============================================================
-- 技能独立调度（每 60 tick = 1s，仅扫描出战列表）
-- ============================================================
local function on_skill_tick()
    local this = Public.get()
    local deployed = this.deployed_pets

    -- 处理熔岩池
    if this.lava_pools and #this.lava_pools > 0 then
        for i = #this.lava_pools, 1, -1 do
            local pool = this.lava_pools[i]
            pool.remaining = pool.remaining - 60
            if pool.remaining <= 0 then
                table.remove(this.lava_pools, i)
                goto next_pool
            end
            -- 对熔岩池范围内敌人造成伤害
            if pool.surface and pool.surface.valid then
                local victims = pool.surface.find_entities_filtered({
                    position = pool.position,
                    radius = 5,
                    force = 'enemy',
                    type = {'unit', 'turret', 'unit-spawner', 'spider-unit'},
                })
                for _, enemy in ipairs(victims) do
                    if enemy.valid then
                        enemy.damage(pool.damage, 'player', 'fire', nil)
                    end
                end
            else
                table.remove(this.lava_pools, i)
            end
            ::next_pool::
        end
    end

    if #deployed == 0 then return end

    local processed = {}
    for i = #deployed, 1, -1 do
        local entry = deployed[i]
        local player = game.players[entry.player_index]
        if not player or not player.valid then
            table.remove(deployed, i)
            goto next_entry
        end
        -- 副本中不调度技能
        if is_in_dungeon(player) then
            goto next_entry
        end
        local pet_data = Public.get_player_pet_data(player)
        local pet = pet_data.pets[entry.pet_index]
        if not pet or not pet.unit or not pet.unit.valid then
            table.remove(deployed, i)
            goto next_entry
        end
        -- 同一 tick 内每人只调度一次
        if not processed[entry.player_index] then
            Skills.dispatch_combat_time(player)
            processed[entry.player_index] = true
        end
        ::next_entry::
    end
end

-- ============================================================
-- 生命周期事件
-- ============================================================

local function on_player_joined_game(event)
    local player = game.players[event.player_index]
    if not player or not player.valid then return end

    GuiDraw.draw_top_button(player)
end

local function on_player_died(event)
    local player = game.players[event.player_index]
    if not player or not player.valid then return end
    local pet_data = Public.get_player_pet_data(player)
    for _, pet in ipairs(pet_data.pets) do
        recall_pet(player, pet)
    end
    if pet_data.combat then
        pet_data.combat.deployed = false
    end
    GuiDraw.remove_all(player)
end

local function on_pre_player_left_game(event)
    local player = game.players[event.player_index]
    if not player or not player.valid then return end
    local pet_data = Public.get_player_pet_data(player)
    for _, pet in ipairs(pet_data.pets) do
        recall_pet(player, pet)
    end
    if pet_data.combat then
        pet_data.combat.deployed = false
    end
    GuiDraw.remove_all(player)
end

-- ============================================================
-- 科研完成触发（科研助手技能）
-- ============================================================

local function on_research_finished(event)
    local research = event.research
    if not research or not research.valid then return end
    local force = research.force
    if not force or force.name ~= 'player' then return end

    -- 为所有在线的玩家触发科研助手技能
    for _, player in pairs(force.players) do
        if player.valid and player.connected then
            Skills.dispatch_research(player)
        end
    end
end

-- ============================================================
-- 手搓物品追踪（编织者技能）
-- ============================================================

local function on_player_crafted_item(event)
    local player = game.players[event.player_index]
    if not player or not player.valid then return end
    local item_stack = event.item_stack
    if not item_stack or not item_stack.valid_for_read then return end
    local pet_data = Public.get_player_pet_data(player)
    pet_data.last_crafted_item = item_stack.name
end

-- ============================================================
-- 注册事件
-- ============================================================

Event.add(defines.events.on_gui_click, on_gui_click)
Event.add(defines.events.on_player_joined_game, on_player_joined_game)
Event.add(defines.events.on_player_created, on_player_joined_game)
Event.add(defines.events.on_player_died, on_player_died)
Event.add(defines.events.on_pre_player_left_game, on_pre_player_left_game)
Event.on_nth_tick(2, on_tick)     -- 每2tick处理1玩家，通过last_tick_processed保证每人每分钟只处理一次
Event.on_nth_tick(2, on_combat_tick)  -- 每2tick处理1玩家，通过last_combat_scan_tick保证每人每3秒扫描一次
Event.on_nth_tick(60, on_skill_tick)  -- 每1秒全员调度技能，各技能独立冷却保证精度
Event.add(defines.events.on_entity_died, on_entity_died)
Event.add(defines.events.on_entity_damaged, on_entity_damaged)
Event.add(defines.events.on_research_finished, on_research_finished)
Event.add(defines.events.on_player_crafted_item, on_player_crafted_item)

GuiRebuild.register('pet_system', function(player)
    GuiDraw.draw_top_button(player)
end)

return Public
