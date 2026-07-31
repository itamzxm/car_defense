-- 自定义市场 GUI 模块
-- 拦截官方市场 GUI，改为显示分三个标签页的自定义 GUI
-- 依赖 rock 模块提供的购买逻辑函数

local Event = require 'utils.event'
local GuiDispatcher = require 'utils.gui_dispatcher'
local WPT = require 'maps.amap.table'
local rock = require 'maps.amap.rock'
local GuiStyles = require 'maps.amap.gui_styles'

local Public = {}

local CONST = {
    -- GUI 元素标识
    MAIN_FRAME = 'amap_market_gui_frame',
    TABBED_PANE = 'amap_market_tabbed_pane',
    TAB_UPGRADES = 'amap_market_tab_upgrades',
    TAB_FIXED = 'amap_market_tab_fixed',
    TAB_RANDOM = 'amap_market_tab_random',
    CONTENT_UPGRADES = 'amap_market_content_upgrades',
    CONTENT_FIXED = 'amap_market_content_fixed',
    CONTENT_RANDOM = 'amap_market_content_random',
    COIN_LABEL = 'amap_mkt_coins',

    -- 按钮名称前缀（后接数字索引）
    UPGRADE_BUY_PREFIX = 'amap_mkt_upg_',
    FIXED_BUY_PREFIX = 'amap_mkt_fix_',
    RANDOM_BUY_PREFIX = 'amap_mkt_rnd_',
    CLOSE_BUTTON = 'amap_mkt_close',

    COLORS = GuiStyles.COLORS,

    -- 升级物品分类配置（按展示顺序排列）
    UPGRADE_CATEGORIES = {
        {key = 'defense', label = {'amap.mkt_cat_defense'}},
        {key = 'damage', label = {'amap.mkt_cat_damage'}},
        {key = 'enemy_limit', label = {'amap.mkt_cat_enemy_limit'}},
        {key = 'talent', label = {'amap.mkt_cat_talent'}},
        {key = 'special', label = {'amap.mkt_cat_special'}}
    },

    -- offer_index → category 映射
    -- 必须与 rock.lua build_upgrade_offers() 中的索引顺序保持一致
    -- 顺序：防御强化(1-2) → 伤害提升(3-4) → 敌方限制(5-6) → 天赋(7-9) → 特殊功能(10)
    -- 注：副本入口已从主市场移除，改由史诗木箱触发
    UPGRADE_CATEGORY_MAP = {
        [1] = 'defense',      -- 城墙加固
        [2] = 'defense',      -- 地雷上限升级
        [3] = 'damage',       -- 全伤害升级
        [4] = 'damage',       -- 重炮伤害升级
        [5] = 'enemy_limit',  -- 虫巢上限
        [6] = 'enemy_limit',  -- 沙虫上限
        [7] = 'talent',       -- 购买天赋（普通）
        [8] = 'talent',       -- 购买天赋（中级）
        [9] = 'talent',       -- 购买天赋（高级）
        [10] = 'special'      -- 捐赠粮草
    }
}

-- ============ 辅助函数 ============

-- 构建价格的本地化字符串（LocalisedString）
local function format_price_caption(price_list)
    if #price_list == 1 then
        local p = price_list[1]
        local proto = prototypes.item[p.name]
        local name = proto and proto.localised_name or p.name
        return {'', tostring(p.count), 'x ', name}
    end
    -- 多种价格物品（罕见）
    local parts = {''}
    for i, p in ipairs(price_list) do
        if i > 1 then
            table.insert(parts, ' + ')
        end
        local proto = prototypes.item[p.name]
        local name = proto and proto.localised_name or p.name
        table.insert(parts, tostring(p.count))
        table.insert(parts, 'x ')
        table.insert(parts, name)
    end
    return parts
end

-- 构建物品显示名称（含数量和品质）
local function get_item_display_name(item_name, count, quality)
    local proto = prototypes.item[item_name]
    local name = proto and proto.localised_name or item_name
    local parts = {''}
    table.insert(parts, name)
    if count and count > 1 then
        table.insert(parts, ' x' .. count)
    end
    if quality then
        table.insert(parts, ' [' .. quality .. ']')
    end
    return parts
end

-- 检查并扣除玩家物品（价格），返回是否成功
local function charge_player(player, price_list)
    for _, p in ipairs(price_list) do
        if player.get_item_count(p.name) < p.count then
            return false
        end
    end
    for _, p in ipairs(price_list) do
        player.remove_item({name = p.name, count = p.count})
    end
    return true
end

-- ============ GUI 绘制函数 ============

-- 绘制升级标签页（按功能分类分组展示）
local function draw_upgrades_tab(content_frame)
    -- 清空旧内容
    for _, child in ipairs(content_frame.children) do
        child.destroy()
    end

    local offers = rock.get_upgrade_offers()

    local scroll = content_frame.add({
        type = 'scroll-pane',
        vertical_scroll_policy = 'auto',
        horizontal_scroll_policy = 'never'
    })
    scroll.style.maximal_height = 420
    scroll.style.minimal_width = 660

    -- 按 category 分组，保留原始 offer_index（按钮 name 用它索引 offers 数组）
    local grouped = {}
    for i, offer in ipairs(offers) do
        local cat = CONST.UPGRADE_CATEGORY_MAP[i] or 'special'
        if not grouped[cat] then grouped[cat] = {} end
        table.insert(grouped[cat], {index = i, offer = offer})
    end

    -- 按 UPGRADE_CATEGORIES 预定义顺序遍历分类
    for _, cat_info in ipairs(CONST.UPGRADE_CATEGORIES) do
        local group = grouped[cat_info.key]
        if group and #group > 0 then
            -- 分类标题
            local title = scroll.add({
                type = 'label',
                caption = cat_info.label
            })
            title.style.font = 'default-bold'
            title.style.font_color = CONST.COLORS.CYAN
            title.style.minimal_width = 660
            title.style.maximal_width = 660
            title.style.top_margin = 6
            title.style.bottom_margin = 2

            local list = scroll.add({
                type = 'table',
                column_count = 3
            })
            list.style.column_alignments[1] = 'left'
            list.style.column_alignments[2] = 'right'
            list.style.column_alignments[3] = 'center'
            list.style.horizontal_spacing = 12
            list.style.vertical_spacing = 4

            -- 表头
            local hdr1 = list.add({type = 'label', caption = {'amap.mkt_header_upgrade'}})
            hdr1.style.font = 'default-bold'
            hdr1.style.font_color = CONST.COLORS.YELLOW
            local hdr2 = list.add({type = 'label', caption = {'amap.mkt_header_price'}})
            hdr2.style.font = 'default-bold'
            hdr2.style.font_color = CONST.COLORS.YELLOW
            list.add({type = 'label', caption = ''})

            for _, entry in ipairs(group) do
                local offer_index = entry.index
                local offer = entry.offer

                -- 升级描述（effect_description 已是本地化字符串）
                local desc_label = list.add({
                    type = 'label',
                    caption = offer.offer.effect_description
                })
                desc_label.style.minimal_width = 340
                desc_label.style.maximal_width = 340
                desc_label.style.font_color = CONST.COLORS.WHITE
                desc_label.style.single_line = false

                -- 价格
                local price_label = list.add({
                    type = 'label',
                    caption = format_price_caption(offer.price)
                })
                price_label.style.minimal_width = 130
                price_label.style.font_color = CONST.COLORS.YELLOW

                -- 购买按钮（文字按钮，name 用原始 offer_index）
                local buy_button = list.add({
                    type = 'button',
                    name = CONST.UPGRADE_BUY_PREFIX .. offer_index,
                    caption = {'amap.mkt_buy'}
                })
                buy_button.style.minimal_width = 60
                buy_button.style.font_color = CONST.COLORS.BLACK
            end
        end
    end
end

-- 绘制道具列表（固定道具/随机道具共用）
local function draw_items_tab(content_frame, offers, prefix)
    -- 清空旧内容
    for _, child in ipairs(content_frame.children) do
        child.destroy()
    end

    if not offers or #offers == 0 then
        local empty = content_frame.add({
            type = 'label',
            caption = {'amap.mkt_no_items'}
        })
        empty.style.font_color = CONST.COLORS.GREY
        return
    end

    local scroll = content_frame.add({
        type = 'scroll-pane',
        vertical_scroll_policy = 'auto',
        horizontal_scroll_policy = 'never'
    })
    scroll.style.maximal_height = 420
    scroll.style.minimal_width = 660

    local list = scroll.add({
        type = 'table',
        column_count = 4
    })
    list.style.column_alignments[1] = 'center'
    list.style.column_alignments[2] = 'left'
    list.style.column_alignments[3] = 'right'
    list.style.column_alignments[4] = 'center'
    list.style.horizontal_spacing = 8
    list.style.vertical_spacing = 4

    -- 表头
    list.add({type = 'label', caption = ''})
    local hdr2 = list.add({type = 'label', caption = {'amap.mkt_header_item'}})
    hdr2.style.font = 'default-bold'
    hdr2.style.font_color = CONST.COLORS.YELLOW
    local hdr3 = list.add({type = 'label', caption = {'amap.mkt_header_price'}})
    hdr3.style.font = 'default-bold'
    hdr3.style.font_color = CONST.COLORS.YELLOW
    list.add({type = 'label', caption = ''})

    for i, offer in ipairs(offers) do
        local item_offer = offer.offer
        if item_offer.type ~= 'give-item' then
            goto continue
        end

        local item_name = item_offer.item
        local count = item_offer.count or 1
        local quality = item_offer.quality

        -- 图标
        local sprite = 'item/' .. item_name
        local sprite_button = list.add({
            type = 'sprite-button',
            sprite = sprite,
            tooltip = get_item_display_name(item_name, count, quality)
        })
        sprite_button.style.minimal_width = 36
        sprite_button.style.maximal_width = 36
        sprite_button.style.minimal_height = 36
        sprite_button.style.maximal_height = 36

        -- 名称 + 数量 + 品质
        local name_label = list.add({
            type = 'label',
            caption = get_item_display_name(item_name, count, quality)
        })
        name_label.style.minimal_width = 220
        name_label.style.maximal_width = 220
        name_label.style.font_color = CONST.COLORS.WHITE

        -- 价格
        local price_label = list.add({
            type = 'label',
            caption = format_price_caption(offer.price)
        })
        price_label.style.minimal_width = 130
        price_label.style.font_color = CONST.COLORS.YELLOW

        -- 购买按钮
        local buy_button = list.add({
            type = 'button',
            name = prefix .. i,
            caption = {'amap.mkt_buy'}
        })
        buy_button.style.minimal_width = 60
        buy_button.style.font_color = CONST.COLORS.BLACK

        ::continue::
    end
end

-- ============ GUI 创建与刷新 ============

-- 创建/切换主市场 GUI
local function create_market_gui(player)
    local screen = player.gui.screen

    -- 如果已打开，则关闭（切换效果）
    if screen[CONST.MAIN_FRAME] and screen[CONST.MAIN_FRAME].valid then
        screen[CONST.MAIN_FRAME].destroy()
        return
    end

    local frame = screen.add({
        type = 'frame',
        name = CONST.MAIN_FRAME,
        caption = {'amap.mkt_title'},
        direction = 'vertical'
    })
    frame.auto_center = true
    frame.style.minimal_width = 720
    frame.style.maximal_width = 820

    -- 玩家金币显示
    local coin_flow = frame.add({
        type = 'flow',
        direction = 'horizontal'
    })
    local coin_label = coin_flow.add({
        type = 'label',
        name = CONST.COIN_LABEL,
        caption = {'amap.mkt_your_coins', player.get_item_count('coin')}
    })
    coin_label.style.font = 'default-bold'
    coin_label.style.font_color = CONST.COLORS.YELLOW

    -- 标签页容器
    local tabbed_pane = frame.add({
        type = 'tabbed-pane',
        name = CONST.TABBED_PANE
    })

    -- Tab 1: 升级物品
    local tab1 = tabbed_pane.add({
        type = 'tab',
        caption = {'amap.mkt_tab_upgrades'},
        name = CONST.TAB_UPGRADES
    })
    local content1 = tabbed_pane.add({
        type = 'frame',
        name = CONST.CONTENT_UPGRADES,
        direction = 'vertical',
        style = 'inside_shallow_frame_with_padding'
    })
    tabbed_pane.add_tab(tab1, content1)
    draw_upgrades_tab(content1)

    -- Tab 2: 固定道具
    local tab2 = tabbed_pane.add({
        type = 'tab',
        caption = {'amap.mkt_tab_fixed'},
        name = CONST.TAB_FIXED
    })
    local content2 = tabbed_pane.add({
        type = 'frame',
        name = CONST.CONTENT_FIXED,
        direction = 'vertical',
        style = 'inside_shallow_frame_with_padding'
    })
    tabbed_pane.add_tab(tab2, content2)
    draw_items_tab(content2, rock.get_fixed_offers(), CONST.FIXED_BUY_PREFIX)

    -- Tab 3: 随机道具
    local tab3 = tabbed_pane.add({
        type = 'tab',
        caption = {'amap.mkt_tab_random'},
        name = CONST.TAB_RANDOM
    })
    local content3 = tabbed_pane.add({
        type = 'frame',
        name = CONST.CONTENT_RANDOM,
        direction = 'vertical',
        style = 'inside_shallow_frame_with_padding'
    })
    tabbed_pane.add_tab(tab3, content3)
    draw_items_tab(content3, rock.get_random_offers(), CONST.RANDOM_BUY_PREFIX)

    -- 关闭按钮
    local close_flow = frame.add({
        type = 'flow',
        direction = 'horizontal'
    })
    close_flow.style.horizontal_align = 'center'
    close_flow.style.horizontally_stretchable = true
    local close_button = close_flow.add({
        type = 'button',
        name = CONST.CLOSE_BUTTON,
        caption = {'amap.mkt_close'}
    })
    close_button.style.minimal_width = 120
    close_button.style.font_color = CONST.COLORS.BLACK

    -- 设置 opened 以支持 Escape 键关闭
    player.opened = frame
end

-- 刷新单个玩家的 GUI 内容
local function refresh_market_gui(player)
    local screen = player.gui.screen
    local frame = screen[CONST.MAIN_FRAME]
    if not frame or not frame.valid then
        return
    end

    -- 更新金币显示
    local coin_label = frame[CONST.COIN_LABEL]
    if coin_label and coin_label.valid then
        coin_label.caption = {'amap.mkt_your_coins', player.get_item_count('coin')}
    end

    -- 刷新各标签页内容
    local tabbed_pane = frame[CONST.TABBED_PANE]
    if not tabbed_pane or not tabbed_pane.valid then
        return
    end

    local content_upgrades = tabbed_pane[CONST.CONTENT_UPGRADES]
    if content_upgrades and content_upgrades.valid then
        draw_upgrades_tab(content_upgrades)
    end

    local content_fixed = tabbed_pane[CONST.CONTENT_FIXED]
    if content_fixed and content_fixed.valid then
        draw_items_tab(content_fixed, rock.get_fixed_offers(), CONST.FIXED_BUY_PREFIX)
    end

    local content_random = tabbed_pane[CONST.CONTENT_RANDOM]
    if content_random and content_random.valid then
        draw_items_tab(content_random, rock.get_random_offers(), CONST.RANDOM_BUY_PREFIX)
    end
end

-- 刷新所有在线玩家的市场 GUI（价格变化后调用）
local function refresh_all_market_guis()
    for _, player in pairs(game.connected_players) do
        refresh_market_gui(player)
    end
end

-- ============ 购买处理 ============

-- 处理升级购买
local function handle_upgrade_purchase(player, offer_index)
    local this = WPT.get()
    local market = this.shop
    if not market or not market.valid then
        player.print({'amap.mkt_shop_invalid'}, {r = 255, g = 0, b = 0})
        return
    end

    -- 前置检查（伤害上限、天赋购买上限等）
    if not rock.can_purchase_upgrade(player, offer_index) then
        return
    end

    -- 获取当前价格
    local offers = rock.get_upgrade_offers()
    local offer = offers[offer_index]
    if not offer then
        return
    end

    -- 检查并扣除金币
    if not charge_player(player, offer.price) then
        player.print({'amap.mkt_not_enough_coins'}, {r = 255, g = 0, b = 0})
        return
    end

    -- 应用升级效果（内部会刷新市场并触发 GUI 刷新回调）
    rock.apply_upgrade_effect(player, offer_index)
end

-- 处理道具购买（固定/随机共用）
local function handle_item_purchase(player, category, index)
    local this = WPT.get()
    local market = this.shop
    if not market or not market.valid then
        player.print({'amap.mkt_shop_invalid'}, {r = 255, g = 0, b = 0})
        return
    end

    local offers
    if category == 'fixed' then
        offers = rock.get_fixed_offers()
    else
        offers = rock.get_random_offers()
    end

    local offer = offers[index]
    if not offer then
        return
    end

    local item_offer = offer.offer
    if item_offer.type ~= 'give-item' then
        return
    end

    -- 检查并扣除金币
    if not charge_player(player, offer.price) then
        player.print({'amap.mkt_not_enough_coins'}, {r = 255, g = 0, b = 0})
        return
    end

    -- 给予物品
    local insert_data = {name = item_offer.item, count = item_offer.count or 1}
    if item_offer.quality then
        insert_data.quality = item_offer.quality
    end
    local inserted = player.insert(insert_data)

    if inserted > 0 then
        -- 播放音效
        market.force.play_sound({
            path = 'utility/new_objective',
            volume_modifier = 0.75
        })
        -- 刷新金币显示（价格已扣除）
        refresh_market_gui(player)
    else
        -- 背包满了，退还金币
        for _, p in ipairs(offer.price) do
            player.insert({name = p.name, count = p.count})
        end
        player.print({'amap.mkt_inventory_full'}, {r = 255, g = 0, b = 0})
    end
end

-- ============ 事件处理 ============

-- on_gui_opened: 拦截主市场点击，关闭官方 GUI，打开自定义 GUI
local function on_gui_opened(event)
    if event.gui_type ~= defines.gui_type.entity then
        return
    end

    local entity = event.entity
    if not entity or not entity.valid then
        return
    end
    if entity.type ~= 'market' then
        return
    end

    local this = WPT.get()
    -- 只拦截主商店；其他市场（如 basic_markets 创建的）仍用官方 GUI
    if entity ~= this.shop then
        return
    end

    local player = game.players[event.player_index]
    -- 关闭官方市场 GUI
    player.opened = nil
    -- 打开/切换自定义 GUI
    create_market_gui(player)
end

-- on_gui_click: 处理前缀匹配的购买按钮点击
local function on_gui_click(event)
    local element = event.element
    if not element or not element.valid then
        return
    end

    local name = element.name
    local player = game.players[event.player_index]

    -- 升级购买
    if string.sub(name, 1, #CONST.UPGRADE_BUY_PREFIX) == CONST.UPGRADE_BUY_PREFIX then
        local idx_str = string.sub(name, #CONST.UPGRADE_BUY_PREFIX + 1)
        local offer_index = tonumber(idx_str)
        if offer_index then
            handle_upgrade_purchase(player, offer_index)
        end
        return
    end

    -- 固定道具购买
    if string.sub(name, 1, #CONST.FIXED_BUY_PREFIX) == CONST.FIXED_BUY_PREFIX then
        local idx_str = string.sub(name, #CONST.FIXED_BUY_PREFIX + 1)
        local index = tonumber(idx_str)
        if index then
            handle_item_purchase(player, 'fixed', index)
        end
        return
    end

    -- 随机道具购买
    if string.sub(name, 1, #CONST.RANDOM_BUY_PREFIX) == CONST.RANDOM_BUY_PREFIX then
        local idx_str = string.sub(name, #CONST.RANDOM_BUY_PREFIX + 1)
        local index = tonumber(idx_str)
        if index then
            handle_item_purchase(player, 'random', index)
        end
        return
    end
end

-- ============ 事件注册 ============

Event.add(defines.events.on_gui_opened, on_gui_opened)
Event.add(defines.events.on_gui_click, on_gui_click)

GuiDispatcher.register_click(CONST.CLOSE_BUTTON, function(event)
    local player = game.players[event.player_index]
    local frame = player.gui.screen[CONST.MAIN_FRAME]
    if frame and frame.valid then
        frame.destroy()
    end
end)

GuiDispatcher.register_closed(CONST.MAIN_FRAME, function(event)
    event.element.destroy()
end)

-- 注册刷新回调到 rock 模块（在商店刷新时同步刷新所有玩家的 GUI）
rock._on_shop_refreshed = refresh_all_market_guis

return Public
