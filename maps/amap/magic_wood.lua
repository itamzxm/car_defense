----------------------------------------------------------------
-- 神奇木箱子系统
-- 木箱子放置 → 选择物品 → 每分钟生产该物品
-- 世界13奖励：达4000波后，任何世界放置汽车送传说木箱
----------------------------------------------------------------
local WPT = require 'maps.amap.table'
local Event = require 'utils.event'
local Gui = require 'utils.gui'
local GuiDispatcher = require 'utils.gui_dispatcher'
local World = require 'maps.amap.world.framework'

local Public = {}

----------------------------------------------------------------
-- GUI 元素 name：全部用固定字符串常量
--
-- 设计原则：
--   1. 不使用 Gui.uid_name()——它底层 Token.uid() 是模块级 local 计数器，
--      不在 global 中持久化，新连接客户端从初始值开始，会导致 name 不一致 → desync。
--   2. GUI 事件通过 GuiDispatcher 按元素名精确路由，
--      GuiDispatcher 在 control stage 统一注册 Event.add，handler 表为模块级 local，
--      所有客户端加载时一致，不会 desync。
--   3. 运行时状态（当前操作的箱子 unit_number 等）存 global（WPT.get()），
--      不通过闭包捕获。
----------------------------------------------------------------

-- frame name（同时作为 player.gui.screen 的 key）
local SELECTION_FRAME = "mw_selection_frame"
local UPGRADE_FRAME   = "mw_upgrade_frame"

-- button name（固定字符串，事件中直接按 name 匹配）
local BTN_PREFIX      = "mw_btn_"         -- + item_name
local BTN_UPGRADE_1K  = "mw_btn_upg_1k"
local BTN_UPGRADE_10K = "mw_btn_upg_10k"
local BTN_OPEN_INV    = "mw_btn_open_inv"
local BTN_CLOSE       = "mw_btn_close"

-- 生产力（total_value）上限：达到后不可继续升级
local MAX_TOTAL_VALUE = 10000

----------------------------------------------------------------
-- 支持的物品列表
----------------------------------------------------------------
local all_items = {
    -- 军事
    "firearm-magazine", "piercing-rounds-magazine", "uranium-rounds-magazine",
    "shotgun-shell", "piercing-shotgun-shell", "rocket", "explosive-rocket",
    "flamethrower-ammo", "grenade", "cluster-grenade", "poison-capsule",
    "slowdown-capsule", "land-mine", "defender-capsule", "distractor-capsule",
    "destroyer-capsule",
    "gun-turret", "laser-turret", "stone-wall",
    -- 工业
    "iron-plate", "steel-plate", "copper-plate", "solid-fuel", "plastic-bar",
    "sulfur", "battery", "explosives", "electronic-circuit", "advanced-circuit",
    "processing-unit", "engine-unit", "electric-engine-unit", "low-density-structure",
    "landfill",
    -- 资源
    "coal", "stone", "iron-ore", "copper-ore", "uranium-ore", "crude-oil-barrel",
    -- 科技
    "automation-science-pack", "logistic-science-pack", "military-science-pack",
    "chemical-science-pack", "production-science-pack", "utility-science-pack",
    -- 建筑
    "fast-transport-belt", "express-transport-belt", "long-handed-inserter",
    "fast-inserter","electric-furnace", "logistic-robot", "construction-robot", "fast-splitter",
    "express-splitter", "medium-electric-pole", "storage-chest", "steel-furnace",
    "electric-mining-drill", "assembling-machine-2", "stone-brick"
}

----------------------------------------------------------------
-- global 辅助：所有运行时状态都通过 WPT.get() 读写
-- WPT.get() 返回的表由 Global.register 持久化，自动同步到所有客户端
----------------------------------------------------------------
local function G()
    return WPT.get()
end

-- 确保 mw 子表存在
local function ensure_mw_tables()
    local this = G()
    if not this.magic_wood_chests      then this.magic_wood_chests = {} end
    if not this.magic_wood_renders     then this.magic_wood_renders = {} end
    if not this.mw_global_investments  then this.mw_global_investments = {} end
    if not this.mw_player_gui          then this.mw_player_gui = {} end       -- [pi] = {mode="select"|"upgrade", chest_un=...}
    if not this.mw_allow_inventory     then this.mw_allow_inventory = {} end  -- [pi] = true
    return this
end

----------------------------------------------------------------
-- 计算物品价值
----------------------------------------------------------------
function Public.calculate_item_value(item_name, depth)
    local this = G()
    depth = depth or 0
    if depth > 10 then return 1 end
    if not this.mw_time_cache then this.mw_time_cache = {} end
    if this.mw_time_cache[item_name] then return this.mw_time_cache[item_name] end

    local recipe = prototypes.recipe[item_name]
    if not recipe then
        this.mw_time_cache[item_name] = 1
        return 1
    end

    local total_time = recipe.energy
    local product_amount = 1
    for _, product in pairs(recipe.products) do
        if product.name == item_name then
            product_amount = product.amount or product.amount_min or 1
            break
        end
    end
    for _, ingredient in pairs(recipe.ingredients) do
        if ingredient.type == "item" then
            total_time = total_time + (Public.calculate_item_value(ingredient.name, depth + 1) * ingredient.amount / product_amount)
        end
    end
    this.mw_time_cache[item_name] = total_time
    return total_time
end

----------------------------------------------------------------
-- 表面检查
----------------------------------------------------------------
function Public.is_allowed_surface(entity_surface)
    if entity_surface.name == 'nauvis' then return true end
    local this = G()
    if this.shop and this.shop.valid and entity_surface == this.shop.surface then
        return true
    end
    return false
end

----------------------------------------------------------------
-- 木箱子数据管理
----------------------------------------------------------------
function Public.get_chest_data(entity)
    local this = G()
    if not this.magic_wood_chests then return nil end
    return this.magic_wood_chests[entity.unit_number]
end

function Public.register_chest(entity, player)
    local this = ensure_mw_tables()
    local un = entity.unit_number
    this.magic_wood_chests[un] = {
        entity = entity,
        owner_index = player.index,
        owner_name = player.name,
        level = 0,
        total_value = 100,
        selected_item = nil,
        last_production_tick = game.tick
    }
    this.mw_global_investments[player.index] = (this.mw_global_investments[player.index] or 0) + 100
end

function Public.upgrade_chest(entity, player_index, coin_amount)
    coin_amount = coin_amount or 1000
    local data = Public.get_chest_data(entity)
    if not data then return false end

    local value_increase = coin_amount / 5
    -- 生产力上限检查：升级后不得超过 MAX_TOTAL_VALUE
    if data.total_value + value_increase > MAX_TOTAL_VALUE then
        return false, "exceeds_limit"
    end

    data.level = data.level + coin_amount / 1000
    data.total_value = data.total_value + value_increase

    local this = G()
    this.mw_global_investments[player_index] = (this.mw_global_investments[player_index] or 0) + coin_amount

    Public.update_level_label(data)
    return true
end

function Public.update_level_label(data)
    if not data.entity or not data.entity.valid then return end
    local this = ensure_mw_tables()
    local un = data.entity.unit_number

    if this.magic_wood_renders[un] then
        local old = this.magic_wood_renders[un]
        if old and old.valid then old.destroy() end
        this.magic_wood_renders[un] = nil
    end

    this.magic_wood_renders[un] = rendering.draw_text {
        text = {"", "Lv." .. tostring(data.level)},
        surface = data.entity.surface,
        target = data.entity,
        target_offset = {0, -2.5},
        color = {r = 0.2, g = 1, b = 0.2, a = 1},
        scale = 0.75,
        font = "default-large-semibold",
        alignment = "center",
        scale_with_zoom = false
    }
end

function Public.remove_chest(entity)
    local this = G()
    if not this.magic_wood_chests then return end
    local un = entity.unit_number
    this.magic_wood_chests[un] = nil

    if this.magic_wood_renders and this.magic_wood_renders[un] then
        local r = this.magic_wood_renders[un]
        if r and r.valid then r.destroy() end
        this.magic_wood_renders[un] = nil
    end
end

----------------------------------------------------------------
-- 金币飞字
----------------------------------------------------------------
local function new_print(player, text)
    local this = G()
    local tick = game.tick
    if not this.mw_print_cooldown then this.mw_print_cooldown = {} end
    if this.mw_print_cooldown[player.index] and tick - this.mw_print_cooldown[player.index] < 30 then return end
    this.mw_print_cooldown[player.index] = tick
    for _, p in pairs(game.connected_players) do
        if player.physical_surface == p.surface then
            p.create_local_flying_text{
                text = text, color = player.color,
                position = player.physical_position, speed = 0.8
            }
        end
    end
end

----------------------------------------------------------------
-- GUI 关闭辅助
----------------------------------------------------------------
local function close_player_gui(player)
    local pi = player.index
    local this = G()
    if not this.mw_player_gui then this.mw_player_gui = {} end
    local g = this.mw_player_gui[pi]
    if g then
        local frame_name = g.mode == "select" and SELECTION_FRAME or UPGRADE_FRAME
        local frame = player.gui.screen[frame_name]
        if frame and frame.valid then
            Gui.destroy(frame)
        end
        this.mw_player_gui[pi] = nil
    end
end

----------------------------------------------------------------
-- 显示物品选择 GUI
----------------------------------------------------------------
function Public.show_selection_gui(player, chest_entity)
    if not chest_entity or not chest_entity.valid then return end
    local this = ensure_mw_tables()
    local pi = player.index

    -- 先关闭本玩家已有的任何 mw GUI
    close_player_gui(player)

    this.mw_player_gui[pi] = {mode = "select", chest_un = chest_entity.unit_number}

    local frame = player.gui.screen.add {
        type = 'frame', name = SELECTION_FRAME,
        caption = {'magic_wood.select_item_title'}, direction = 'vertical'
    }
    frame.auto_center = true
    frame.add {type = 'label', caption = {'magic_wood.select_item_prompt'}}

    local scroll = frame.add {
        type = 'scroll-pane', horizontal_scroll_policy = 'never', vertical_scroll_policy = 'auto'
    }
    scroll.style.maximal_height = 500
    scroll.style.maximal_width = 640

    local tbl = scroll.add {type = 'table', column_count = 5}
    tbl.style.horizontal_spacing = 8
    tbl.style.vertical_spacing = 4

    for _, item_name in ipairs(all_items) do
        if prototypes.item[item_name] then
            local cell = tbl.add {type = 'flow', direction = 'vertical'}
            cell.style.horizontal_align = 'center'
            cell.add {
                type = 'sprite-button',
                name = BTN_PREFIX .. item_name,       -- 固定 name，事件中解析
                sprite = 'item/' .. item_name,
                style = 'slot_button',
                tooltip = {'item-name.' .. item_name}
            }
        end
    end

    player.opened = frame
end

----------------------------------------------------------------
-- 显示升级 GUI
----------------------------------------------------------------
function Public.show_upgrade_gui(player, chest_entity)
    local chest_data = Public.get_chest_data(chest_entity)
    if not chest_data then return end
    local this = ensure_mw_tables()
    local pi = player.index

    close_player_gui(player)

    this.mw_player_gui[pi] = {mode = "upgrade", chest_un = chest_entity.unit_number}

    local frame = player.gui.screen.add {
        type = 'frame', name = UPGRADE_FRAME,
        caption = {'magic_wood.upgrade_title', chest_data.level}, direction = 'vertical'
    }
    frame.auto_center = true

    -- 箱子信息
    local info = frame.add {type = 'flow', direction = 'vertical'}
    info.style.horizontal_align = 'center'
    info.add {type = 'label', caption = {'magic_wood.section_chest_info'}}

    frame.add {type = 'label', caption = {'magic_wood.current_level', chest_data.level}}
    frame.add {type = 'label', caption = {'magic_wood.total_value', chest_data.total_value}}
    frame.add {type = 'label', caption = {'magic_wood.value_limit', MAX_TOTAL_VALUE, chest_data.total_value}}

    if chest_data.selected_item then
        local proto = prototypes.item[chest_data.selected_item]
        frame.add {type = 'label', caption = {"", {'magic_wood.producing_item_label'}, " ", proto and proto.localised_name or chest_data.selected_item}}

        local item_val = Public.calculate_item_value(chest_data.selected_item)
        local count = math.floor(chest_data.total_value / item_val)
        frame.add {type = 'label', caption = {'magic_wood.current_production', count}}
        local next_count = math.floor((chest_data.total_value + 200) / item_val)
        if next_count > count then
            frame.add {type = 'label', caption = {'magic_wood.upgrade_production', next_count}}
        end
    else
        frame.add {type = 'label', caption = {'magic_wood.no_item_selected'}}
    end

    -- 升级按钮：根据生产力上限智能显示
    local upg_flow = frame.add {type = 'flow', direction = 'horizontal'}
    upg_flow.style.horizontal_align = 'center'
    local can_upgrade_1k  = chest_data.total_value + 200  <= MAX_TOTAL_VALUE
    local can_upgrade_10k = chest_data.total_value + 2000 <= MAX_TOTAL_VALUE
    if not can_upgrade_1k then
        -- 连 1K 升级都会超上限 → 已达上限
        upg_flow.add {type = 'label', caption = {'magic_wood.max_value_reached', MAX_TOTAL_VALUE}}
    else
        upg_flow.add {type = 'button', name = BTN_UPGRADE_1K,  caption = {'magic_wood.upgrade_button', 200, 1000}}
        if can_upgrade_10k then
            upg_flow.add {type = 'button', name = BTN_UPGRADE_10K, caption = {'magic_wood.upgrade_button', 2000, 10000}}
        end
    end

    frame.add {type = 'line'}

    -- 投资信息
    local inv_flow = frame.add {type = 'flow', direction = 'vertical'}
    inv_flow.style.horizontal_align = 'center'
    inv_flow.add {type = 'label', caption = {'magic_wood.section_investment_info'}}

    local gi = (this.mw_global_investments and this.mw_global_investments[pi]) or 0
    frame.add {type = 'label', caption = {'magic_wood.global_investment', gi}}
    frame.add {type = 'label', caption = {'magic_wood.your_income', math.floor(gi * 0.004)}}
    frame.add {type = 'label', caption = {'magic_wood.investment_roi'}}

    frame.add {type = 'line'}
    frame.add {type = 'button', name = BTN_OPEN_INV, caption = {'magic_wood.open_chest_inventory'}}
    frame.add {type = 'line'}
    frame.add {type = 'button', name = BTN_CLOSE,    caption = {'magic_wood.close_gui'}}

    player.opened = frame
end

----------------------------------------------------------------
-- GUI 事件处理（GuiDispatcher 按元素名路由）
-- handler 内通过 player index 查 global 状态，不依赖闭包捕获局部变量。
----------------------------------------------------------------

local function on_upgrade_click(event)
    local element = event.element
    local coin_cost = element.name == BTN_UPGRADE_1K and 1000 or 10000

    local player = game.get_player(event.player_index)
    if not (player and player.valid) then return end
    local this = G()
    local pi = player.index
    local gui_state = this.mw_player_gui and this.mw_player_gui[pi]
    if not gui_state then return end

    local chest_data = this.magic_wood_chests[gui_state.chest_un]
    if not chest_data or not chest_data.entity or not chest_data.entity.valid then
        player.print({'magic_wood.chest_disappeared'})
        return
    end
    if chest_data.total_value >= MAX_TOTAL_VALUE then
        player.print({'magic_wood.max_value_reached', MAX_TOTAL_VALUE})
        return
    end
    if player.get_item_count('coin') < coin_cost then
        player.print({'magic_wood.not_enough_coins', coin_cost})
        return
    end
    player.remove_item {name = 'coin', count = coin_cost}
    local ok = Public.upgrade_chest(chest_data.entity, pi, coin_cost)
    if ok then
        player.print({'magic_wood.upgrade_success', chest_data.level, chest_data.total_value})
        Public.show_upgrade_gui(player, chest_data.entity)
    else
        player.print({'magic_wood.upgrade_would_exceed', MAX_TOTAL_VALUE})
    end
end

local function on_open_inv_click(event)
    local player = game.get_player(event.player_index)
    if not (player and player.valid) then return end
    local this = G()
    local pi = player.index
    local gui_state = this.mw_player_gui and this.mw_player_gui[pi]
    if not gui_state then return end

    local chest_data = this.magic_wood_chests[gui_state.chest_un]
    if chest_data and chest_data.entity and chest_data.entity.valid then
        close_player_gui(player)
        if not this.mw_allow_inventory then this.mw_allow_inventory = {} end
        this.mw_allow_inventory[pi] = true
        player.opened = chest_data.entity
    end
end

local function on_close_click(event)
    local player = game.get_player(event.player_index)
    if not (player and player.valid) then return end
    close_player_gui(player)
end

local function on_item_select_click(event)
    local item_name = event.element.name:sub(#BTN_PREFIX + 1)

    local player = game.get_player(event.player_index)
    if not (player and player.valid) then return end
    local this = G()
    local pi = player.index
    local gui_state = this.mw_player_gui and this.mw_player_gui[pi]
    if not gui_state then return end

    close_player_gui(player)

    local chest_data = this.magic_wood_chests[gui_state.chest_un]
    if not chest_data or not chest_data.entity or not chest_data.entity.valid then
        player.print({'magic_wood.chest_disappeared'})
        return
    end
    chest_data.selected_item = item_name
    chest_data.last_production_tick = game.tick
    Public.update_level_label(chest_data)

    local proto = prototypes.item[item_name]
    player.print({'magic_wood.item_selected', proto and proto.localised_name or item_name})
end

local function on_frame_closed(event)
    local this = G()
    local pi = event.player_index
    if this.mw_player_gui then
        this.mw_player_gui[pi] = nil
    end
    Gui.destroy(event.element)
end

GuiDispatcher.register_click(BTN_UPGRADE_1K, on_upgrade_click)
GuiDispatcher.register_click(BTN_UPGRADE_10K, on_upgrade_click)
GuiDispatcher.register_click(BTN_OPEN_INV, on_open_inv_click)
GuiDispatcher.register_click(BTN_CLOSE, on_close_click)
for _, item_name in ipairs(all_items) do
    GuiDispatcher.register_click(BTN_PREFIX .. item_name, on_item_select_click)
end

GuiDispatcher.register_closed(SELECTION_FRAME, on_frame_closed)
GuiDispatcher.register_closed(UPGRADE_FRAME, on_frame_closed)

----------------------------------------------------------------
-- on_gui_opened：右键点击木箱子 → 拦截，显示升级/选择 GUI
----------------------------------------------------------------
Event.add(defines.events.on_gui_opened, function(event)
    if event.gui_type ~= defines.gui_type.entity then return end
    local entity = event.entity
    if not entity or not entity.valid then return end
    if entity.name ~= 'wooden-chest' then return end

    local player = game.get_player(event.player_index)
    if not player or not player.valid then return end

    local data = Public.get_chest_data(entity)
    if not data then return end  -- 普通木箱，放行

    local this = G()
    -- 从"打开仓库"按钮过来的，放行
    if this.mw_allow_inventory and this.mw_allow_inventory[event.player_index] then
        this.mw_allow_inventory[event.player_index] = nil
        return
    end

    -- 拦截：已选物品 → 升级界面；未选 → 选择界面
    player.opened = nil
    if data.selected_item then
        Public.show_upgrade_gui(player, entity)
    else
        Public.show_selection_gui(player, entity)
    end
end)

----------------------------------------------------------------
-- 生产逻辑（每 3600 ticks = 1 分钟）
----------------------------------------------------------------
function Public.process_production()
    local this = G()
    if not this.magic_wood_chests then return end
    local tick = game.tick

    for _, data in pairs(this.magic_wood_chests) do
        if data.entity and data.entity.valid and data.selected_item then
            if tick - data.last_production_tick >= 3600 then
                local item_val = Public.calculate_item_value(data.selected_item)
                if item_val > 0 then
                    local count = math.floor(data.total_value / item_val)
                    if count > 0 then
                        local inv = data.entity.get_inventory(defines.inventory.chest)
                        if inv then inv.insert {name = data.selected_item, count = count} end
                    end
                end
                data.last_production_tick = tick
            end
        end
    end

    -- 金币产出
    if this.mw_global_investments then
        if not this.mw_last_gold_tick then this.mw_last_gold_tick = 0 end
        if tick - this.mw_last_gold_tick >= 3600 then
            this.mw_last_gold_tick = tick
            for pi, investment in pairs(this.mw_global_investments) do
                local coins = math.floor(investment * 0.004)
                if coins > 0 then
                    local p = game.players[pi]
                    if p and p.valid and p.character and p.character.valid then
                        p.character.insert {name = 'coin', count = coins}
                        if p.connected then new_print(p, {'', '+', coins, ' 🪙'}) end
                    end
                end
            end
        end
    end
end

----------------------------------------------------------------
-- 实体事件
----------------------------------------------------------------
Event.add(defines.events.on_built_entity, function(event)
    local entity = event.entity
    if not entity or not entity.valid then return end
    if entity.name ~= 'wooden-chest' then return end

    local player = game.players[event.player_index]
    if not player or not player.valid then return end

    if not Public.is_allowed_surface(entity.surface) then
        player.print {'magic_wood.invalid_surface'}
        return
    end

    if entity.quality.name == 'legendary' then
        -- 限制：非火车大逃亡世界，每人最多只能放1个传说木箱
        -- 超出则替换为普通木箱，不触发传说木箱特殊功能
        local this = G()
        local world_number = this.world_number or 1

        -- 框架内禁用：世界15 不发放传说木箱奖励（def 中 disable_legendary_wood_chest = true）
        if World.get_field(world_number, 'disable_legendary_wood_chest') then
            local surface = entity.surface
            local position = entity.position
            local force = entity.force
            entity.destroy()
            surface.create_entity{
                name = 'wooden-chest',
                position = position,
                force = force,
                quality = 'normal',
                fast_replace = true,
            }
            return
        end

        if world_number ~= 13 then
            local count = 0
            if this.magic_wood_chests then
                for _, data in pairs(this.magic_wood_chests) do
                    if data.owner_index == player.index
                       and data.entity and data.entity.valid
                       and data.entity.quality.name == 'legendary' then
                        count = count + 1
                    end
                end
            end
            if count >= 1 then
                local surface = entity.surface
                local position = entity.position
                local force = entity.force
                entity.destroy()
                surface.create_entity{
                    name = 'wooden-chest',
                    position = position,
                    force = force,
                    quality = 'normal',
                    fast_replace = true,
                }
                player.print {'magic_wood.legendary_limit'}
                return
            end
        end

        entity.destructible = true
        entity.minable_flag = false
        Public.register_chest(entity, player)
        Public.show_selection_gui(player, entity)
    end
end)

Event.add(defines.events.on_player_mined_entity, function(event)
    local e = event.entity
    if e and e.valid and e.name == 'wooden-chest' then Public.remove_chest(e) end
end)

Event.add(defines.events.on_robot_mined_entity, function(event)
    local e = event.entity
    if e and e.valid and e.name == 'wooden-chest' then Public.remove_chest(e) end
end)

Event.add(defines.events.on_entity_died, function(event)
    local e = event.entity
    if e and e.valid and e.name == 'wooden-chest' then Public.remove_chest(e) end
end)

----------------------------------------------------------------
-- 每分钟生产 tick
----------------------------------------------------------------
Event.add(defines.events.on_tick, function()
    if game.tick % 60 ~= 0 then return end
    Public.process_production()
end)

return Public
