local ICT = require 'maps.amap.ic.table'
local Functions = require 'maps.amap.ic.functions'
local Color = require 'utils.color_presets'
local Gui = require 'utils.gui'
local Tabs = require 'comfy_panel.main'
local Event = require 'utils.event'
local GuiDispatcher = require 'utils.gui_dispatcher'
local TopBar = require 'utils.top_bar'
local WD = require 'modules.wave_defense.table'
local diff = require 'maps.amap.diff'
local World = require 'maps.amap.world.framework'
local Public = {}
local insert = table.insert
local Collapse = require 'modules.collapse'

-- ! Gui Frames
local save_add_player_button_name = 'ic_save_add_player_button'
local save_transfer_car_button_name = 'ic_save_transfer_car_button'
local discard_add_player_button_name = 'ic_discard_add_player_button'
local transfer_player_select_name = 'ic_transfer_player_select'
local discard_transfer_car_button_name = 'ic_discard_transfer_car_button'
local main_frame_name = 'ic_main_frame'
local draw_add_player_frame_name = 'ic_draw_add_player_frame'
local draw_transfer_car_frame_name = 'ic_draw_transfer_car_frame'
local main_toolbar_name = 'ic_main_toolbar'
local add_player_name = 'ic_add_player'
local transfer_car_name = 'ic_transfer_car'
local allow_anyone_to_enter_name = 'ic_allow_anyone_to_enter'
local kick_player_name = 'ic_kick_player'

local rpgtable = require 'modules.rpg.table'
local Alert = require 'utils.alert'
local Loot = require 'maps.amap.loot'
local WPT = require 'maps.amap.table'
local TPT = require 'maps.amap.tianfu_table'

local cool = 'ic_cool'
local buyxp = 'ic_buyxp'
local stop_wave = 'ic_stop_wave'

local up_coin = 'ic_up_coin'
local up_xp = 'ic_up_xp'
local up_jijing = 'ic_up_jijing'

local integration_button_name = 'ic_integration_button'
local integration_frame_name = 'ic_integration_frame'

local raise_event = script.raise_event
local add_toolbar
local remove_toolbar

local function increment(t, k)
    t[k] = true
end

local function decrement(t, k)
    t[k] = nil
end

local function crate_water(surface, position)
    for i = 1, 3 do
        for b = 1, 3 do
            local p = {
                x = position.x - b + 2,
                y = position.y - i - 2
            }
            if surface.can_place_entity {
                name = 'iron-chest',
                position = p
            } then
                surface.set_tiles({{
                    name = "water",
                    position = p
                }})
            end
        end
    end
    local entities = surface.find_entities_filtered {
        position = {
            x = position.x,
            y = position.y + 4
        },
        name = "crude-oil",
        radius = 25
    }
    if #entities == 0 then
        surface.create_entity({
            name = "crude-oil",
            position = {
                x = position.x,
                y = position.y + 4
            }
        })
    end
end

local function crate_ore(surface, position)
    local ores = {'iron-ore', 'copper-ore', 'stone', 'coal'}
    local dist = 3
    local this = WPT.get()
    local abc = 1
    if this.world_number == 7 then
        abc = 6
    end
    local amount = 125
    
    -- 创建方向配置数组，每个配置包含x方向因子、y方向因子和对应的矿石索引
    local directions = {
        {x_dir = 1, y_dir = 1, ore_index = 1},  -- 右上
        {x_dir = -1, y_dir = 1, ore_index = 2}, -- 左上
        {x_dir = 1, y_dir = -1, ore_index = 3}, -- 右下
        {x_dir = -1, y_dir = -1, ore_index = 4} -- 左下
    }
    
    -- 使用单个循环处理所有方向
    for _, dir in pairs(directions) do
        for a = 1, 20 do
            for b = 1, 20 do
                -- 根据方向因子计算位置
                local p = {
                    x = position.x + (dir.x_dir * a) + (dir.x_dir * dist),
                    y = position.y + (dir.y_dir * b) + (dir.y_dir * dist)
                }
                -- 首先检测位置是否已有矿物
                local existing_entities = surface.find_entities_filtered{
                    position = p,
                    radius = 0.5,
                    type = 'resource'
                }
                
                if #existing_entities > 0 then
                    -- 已有矿物存在
                    local existing_entity = existing_entities[1]
                    if existing_entity.name == ores[dir.ore_index] then
                        -- 同名矿物，直接添加资源量
                        existing_entity.amount = existing_entity.amount + (amount * abc)
                    end
                    -- 不同矿物，跳过（不执行任何操作）
                else
                    -- 无矿物存在，检查位置是否可以放置矿物后创建新矿
                    if surface.can_place_entity{name=ores[dir.ore_index], position=p} then
                        surface.create_entity({
                            name = ores[dir.ore_index],
                            position = p,
                            amount = amount * abc
                        })
                    end
                end
            end
        end
    end
end

local function create_player_table(player)
    local trust_system = ICT.get('trust_system')
    if not trust_system[player.index] then
        trust_system[player.index] = {
            players = {
                [player.name] = true
            },
            allow_anyone = 'right'
        }
    end
    return trust_system[player.index]
end

local function does_player_table_exist(player)
    local trust_system = ICT.get('trust_system')
    if not trust_system[player.index] then
        return false
    else
        return true
    end
end

local function get_players(player, frame, all)
    local tbl = {}
    local players = game.connected_players
    local trust_system = create_player_table(player)

    for _, p in pairs(players) do
        if next(trust_system.players) and not all then
            if not trust_system.players[p.name] then
                insert(tbl, tostring(p.name))
            end
        else
            insert(tbl, tostring(p.name))
        end
    end
    insert(tbl, {'amap.ic_select_player'})

    local selected_index = #tbl

    local f = frame.add({
        type = 'drop-down',
        name = transfer_player_select_name,
        items = tbl,
        selected_index = selected_index
    })
    return f
end

local function transfer_player_table(player, new_player)
    local trust_system = ICT.get('trust_system')
    if not trust_system[player.index] then
        return false
    end

    if player.index == new_player.index then
        return false
    end

    if not trust_system[new_player.index] then
        trust_system[new_player.index] = trust_system[player.index]
        local name = new_player.name

        if not trust_system[new_player.index].players[name] then
            increment(trust_system[new_player.index].players, name)
        end

        local cars = ICT.get('cars')
        local renders = ICT.get('renders')
        local c = Functions.get_owner_car_object(cars, player)
        local car = cars[c]
        car.owner = new_player.index

        Functions.render_owner_text(renders, player, car.entity, new_player)

        remove_toolbar(player)
        add_toolbar(new_player)

        local old_index = player.index
        local new_index = new_player.index

        local this = WPT.get()

        this.tank[new_index] = this.tank[old_index]
        this.tank[old_index] = nil
        this.have_been_put_tank[new_index] = true
        this.have_been_put_tank[old_index] = false
        this.whos_tank[new_index] = this.whos_tank[old_index]
        this.whos_tank[old_index] = nil

        if this.time_weights[old_index] then
            this.time_weights[new_index] = this.time_weights[old_index]
            this.time_weights[old_index] = 0
        end

        if this.car_pos[old_index] then
            this.car_pos[new_index] = this.car_pos[old_index]
            this.car_pos[old_index] = nil
        end

        if this.spidertron[old_index] then
            if not this.spidertron[new_index] then
                this.spidertron[new_index] = true
                this.spidertron[old_index] = false
            end
        end

        trust_system[player.index] = nil
    else
        return false
    end

    return trust_system[new_player.index]
end

local function remove_main_frame(main_frame)
    if not main_frame or not main_frame.valid then
        return
    end

    Gui.remove_data_recursively(main_frame)
    main_frame.destroy()
end

local function draw_add_player(player, frame)
    local main_frame = frame.add({
        type = 'frame',
        name = draw_add_player_frame_name,
        caption = {'amap.ic_add_player'},
        direction = 'vertical'
    })
    local main_frame_style = main_frame.style
    main_frame_style.width = 370
    main_frame_style.use_header_filler = true

    local inside_frame = main_frame.add {
        type = 'frame',
        style = 'inside_shallow_frame'
    }
    local inside_frame_style = inside_frame.style
    inside_frame_style.padding = 0
    local inside_table = inside_frame.add {
        type = 'table',
        column_count = 1
    }
    local inside_table_style = inside_table.style
    inside_table_style.vertical_spacing = 5
    inside_table_style.top_padding = 10
    inside_table_style.left_padding = 10
    inside_table_style.right_padding = 0
    inside_table_style.bottom_padding = 10
    inside_table_style.width = 325

    local add_player_frame = get_players(player, main_frame)

    local bottom_flow = main_frame.add({
        type = 'flow',
        direction = 'horizontal'
    })

    local left_flow = bottom_flow.add({
        type = 'flow'
    })
    left_flow.style.horizontal_align = 'left'
    left_flow.style.horizontally_stretchable = true

    local close_button = left_flow.add({
        type = 'button',
        name = discard_add_player_button_name,
        caption = {'amap.ic_discard'}
    })
    close_button.style = 'back_button'
    close_button.style.maximal_width = 100

    local right_flow = bottom_flow.add({
        type = 'flow'
    })
    right_flow.style.horizontal_align = 'right'

    local save_button = right_flow.add({
        type = 'button',
        name = save_add_player_button_name,
        caption = {'amap.ic_save'}
    })
    save_button.style = 'confirm_button'
    save_button.style.maximal_width = 100

    Gui.set_data(save_button, add_player_frame)
end

local function draw_transfer_car(player, frame)
    local main_frame = frame.add({
        type = 'frame',
        name = draw_transfer_car_frame_name,
        caption = {'amap.ic_transfer_car'},
        direction = 'vertical'
    })
    local main_frame_style = main_frame.style
    main_frame_style.width = 370
    main_frame_style.use_header_filler = true

    local inside_frame = main_frame.add {
        type = 'frame',
        style = 'inside_shallow_frame'
    }
    local inside_frame_style = inside_frame.style
    inside_frame_style.padding = 0
    local inside_table = inside_frame.add {
        type = 'table',
        column_count = 1
    }
    local inside_table_style = inside_table.style
    inside_table_style.vertical_spacing = 5
    inside_table_style.top_padding = 10
    inside_table_style.left_padding = 10
    inside_table_style.right_padding = 0
    inside_table_style.bottom_padding = 10
    inside_table_style.width = 325

    local transfer_car_alert_frame = main_frame.add({
        type = 'label',
        caption = {'ic.warning'}
    })
    transfer_car_alert_frame.style.font_color = {
        r = 255,
        g = 0,
        b = 0
    }
    local transfer_car_frame = get_players(player, main_frame, true)

    local bottom_flow = main_frame.add({
        type = 'flow',
        direction = 'horizontal'
    })

    local left_flow = bottom_flow.add({
        type = 'flow'
    })
    left_flow.style.horizontal_align = 'left'
    left_flow.style.horizontally_stretchable = true

    local close_button = left_flow.add({
        type = 'button',
        name = discard_transfer_car_button_name,
        caption = {'amap.ic_discard'}
    })
    close_button.style = 'back_button'
    close_button.style.maximal_width = 100

    local right_flow = bottom_flow.add({
        type = 'flow'
    })
    right_flow.style.horizontal_align = 'right'

    local save_button = right_flow.add({
        type = 'button',
        name = save_transfer_car_button_name,
        caption = {'amap.ic_save'}
    })
    save_button.style = 'confirm_button'
    save_button.style.maximal_width = 100

    Gui.set_data(save_button, transfer_car_frame)
end

local function draw_integration_frame(player)
    local main_frame = player.gui.screen.add({
        type = 'frame',
        name = integration_frame_name,
        caption = {'amap.ic_car_functions'},
        direction = 'vertical'
    })

    main_frame.auto_center = false
    main_frame.location = {x = 475, y = 50}
    local main_frame_style = main_frame.style
    main_frame_style.width = 450
    main_frame_style.use_header_filler = false

    local inside_frame = main_frame.add {
        type = 'frame',
        style = 'inside_shallow_frame'
    }
    inside_frame.style.padding = 0

    -- 【修改点1】改为单列布局，避免列宽相互影响
    local inside_table = inside_frame.add {
        type = 'table',
        column_count = 1  
    }
    local inside_table_style = inside_table.style
    inside_table_style.vertical_spacing = 10
    inside_table_style.top_padding = 15
    inside_table_style.left_padding = 15 -- 稍微增加左边距，整体更美观
    inside_table_style.right_padding = 15
    inside_table_style.bottom_padding = 15
    inside_table_style.width = 440 -- 稍微调整适应 Frame 宽度

    -- 【修改点2】创建一个总的按钮容器，让两组按钮在同一行紧挨着显示
    local all_buttons_flow = inside_table.add {
        type = 'flow',
        direction = 'horizontal'
    }
    all_buttons_flow.style.horizontal_spacing = 10 -- 两组按钮之间的间距

    -- 第一组按钮（左侧）
    local main_functions_flow = all_buttons_flow.add {
        type = 'flow',
        direction = 'horizontal'
    }
    main_functions_flow.style.horizontal_spacing = 10

    -- 汽车设置按钮
    local car_settings_btn = main_functions_flow.add({
        type = 'sprite-button',
        sprite = 'item/spidertron',
        name = 'integration_car_settings',
        tooltip = {'ic.car_settings_tooltip'}
    })
    car_settings_btn.style.minimal_width = 100
    car_settings_btn.style.font = 'default-bold'

    -- 存储箱按钮
    local chest_btn = main_functions_flow.add({
        type = 'sprite-button',
        sprite = 'item/storage-chest',
        name = 'integration_chest',
        tooltip = {'ic.chest_tooltip'}
    })
    chest_btn.style.minimal_width = 40

    -- 品质开箱按钮
    local quality_chest_btn = main_functions_flow.add({
        type = 'sprite-button',
        sprite = 'item/steel-chest',
        name = 'integration_chest_quality',
        tooltip = {'ic.chest_quality_tooltip'}
    })
    quality_chest_btn.style.minimal_width = 40

    -- 超时空商店按钮
    local tianfu_this = TPT.get()
    local index = player.index
    local has_chaoshikongshangdian = false
    local shop_items = nil
    
    if tianfu_this.chaoshikongshangdian_items and tianfu_this.chaoshikongshangdian_items[index] then
        has_chaoshikongshangdian = true
        shop_items = tianfu_this.chaoshikongshangdian_items[index]
    end
    
    if has_chaoshikongshangdian and shop_items and #shop_items > 0 then
        local spent = tianfu_this.chaoshikongshangdian_spent[index] or 0
        local remaining = 10000 - spent
        local chaoshikongshangdian_btn = main_functions_flow.add({
            type = 'sprite-button',
            sprite = 'entity/market',
            name = 'integration_chaoshikongshangdian',
            tooltip = {'tianfu.chaoshikongshangdian_open_tooltip', #shop_items, remaining}
        })
        chaoshikongshangdian_btn.style.minimal_width = 40
    end

    -- 第二组按钮（右侧）直接加到同一个父容器中
    local upgrade_flow = all_buttons_flow.add {
        type = 'flow',
        direction = 'horizontal'
    }
    upgrade_flow.style.horizontal_spacing = 10

    -- 购买经验按钮
    local buy_xp_btn = upgrade_flow.add({
        type = 'sprite-button',
        sprite = 'item/rocket-part',
        name = 'integration_buy_xp',
        tooltip = {'ic.buy_xp_tooltip'}
    })
    buy_xp_btn.style.minimal_width = 40

    -- 购买资源按钮
    local buy_resources_btn = upgrade_flow.add({
        type = 'sprite-button',
        sprite = 'item/iron-ore',
        name = 'integration_buy_resources',
        tooltip = {'ic.buy_resources_tooltip'}
    })
    buy_resources_btn.style.minimal_width = 40

    -- 暂停波次按钮
    local this = WPT.get()
    local current_stop_wave = this.stop_wave or 0
    local price = current_stop_wave * 3000 + 1
    local stop_wave_btn = upgrade_flow.add({
        type = 'sprite-button',
        sprite = 'entity/behemoth-biter',
        name = 'integration_stop_wave',
        tooltip = {'amap.ic_pause_wave_price', price}
    })
    stop_wave_btn.style.minimal_width = 40

    -- 信息显示区域 (现在它在第2行，因为 column_count=1)
    local info_flow = inside_table.add {
        type = 'flow',
        direction = 'vertical'
    }
    info_flow.style.vertical_spacing = 1
    
    local this = WPT.get()
    local index = player.index
    
    -- 显示当前等级信息
    if this.qcdj[index] then
        local xp = 2 + (this.qcdj[index] - 1) * 2
        local coin = 10 + (this.qcdj[index] - 1) * 4
        local level_label = info_flow.add({
            type = 'label',
            caption = {'ic.current_level', this.qcdj[index], xp, coin}
        })
        level_label.style.font = 'default-bold'
    end

    -- 品质宝箱免费进度
    local quality_chest_purchases = this.quality_chest_purchases[index] or 0
    if quality_chest_purchases >= 0 then
        local remaining_quality = 10 - quality_chest_purchases

        if remaining_quality == 0 then
                local quality_progress_label = info_flow.add({
            type = 'label',
            caption = {'ic.quality_chest_free'}
        })
        
         quality_progress_label.style.font = 'default-bold'
        quality_progress_label.style.font_color = {r = 1, g = 0.8, b = 0.2}

            else
                    local quality_progress_label = info_flow.add({
            type = 'label',
            caption = {'ic.quality_chest_progress', quality_chest_purchases, remaining_quality}
        })
         quality_progress_label.style.font = 'default-bold'
        quality_progress_label.style.font_color = {r = 1, g = 0.8, b = 0.2}
        end
    
       
    end

    -- 显示资源信息
    local ore_record = this.ore_record[index] or 0
    if ore_record >= 0 then
        info_flow.add({
            type = 'label',
            caption = {'amap.ic_ore_purchase_count', ore_record}
        })
    end

    -- 显示暂停波次信息
    local stop_wave = this.stop_wave or 0
    if stop_wave >= 0 then
        info_flow.add({
            type = 'label',
            caption = {'amap.ic_pause_wave_count', stop_wave}
        })
    end

    -- 底部关闭按钮区域
    local close_flow = inside_table.add {
        type = 'flow',
        direction = 'horizontal'
    }
    close_flow.style.horizontal_align = 'center'
    close_flow.style.horizontally_stretchable = true
    close_flow.style.top_padding = 10

    -- 关闭按钮
    local clear_btn = close_flow.add({
        type = 'button',
        caption = {'ic.close'},
        name = 'integration_close',
        tooltip = {'ic.close'}
    })
    clear_btn.style.minimal_width = 80
    clear_btn.style.font = 'default-bold'

    player.opened = main_frame
end

local function draw_chaoshikongshangdian_frame(player)
    local tianfu_this = TPT.get()
    local index = player.index
    
    if not tianfu_this.chaoshikongshangdian_items or not tianfu_this.chaoshikongshangdian_items[index] then
        return
    end
    
    local shop_items = tianfu_this.chaoshikongshangdian_items[index]
    if #shop_items == 0 then
        return
    end

    local screen = player.gui.screen
    local existing_frame = screen['chaoshikongshangdian_frame']
    if existing_frame and existing_frame.valid then
        existing_frame.destroy()
    end

    local main_frame = player.gui.screen.add({
        type = 'frame',
        name = 'chaoshikongshangdian_frame',
        caption = {'tianfu.chaoshikongshangdian_title'},
        direction = 'vertical'
    })

    main_frame.auto_center = false
    main_frame.location = {x = 500, y = 100}
    local main_frame_style = main_frame.style
    main_frame_style.width = 600
    main_frame_style.use_header_filler = false

    local inside_frame = main_frame.add {
        type = 'frame',
        style = 'inside_shallow_frame'
    }
    inside_frame.style.padding = 0

    local scroll_pane = inside_frame.add {
        type = 'scroll-pane',
        direction = 'vertical'
    }
    scroll_pane.style.maximal_height = 350

    local items_table = scroll_pane.add {
        type = 'table',
        column_count = 6
    }
    items_table.style.horizontal_spacing = 5
    items_table.style.vertical_spacing = 5
    items_table.style.top_padding = 5
    items_table.style.left_padding = 5
    items_table.style.right_padding = 5
    items_table.style.bottom_padding = 5

    for i, item in ipairs(shop_items) do
        local item_prototype = prototypes.item[item.item_name]
        if item_prototype then
            local item_flow = items_table.add {
                type = 'flow',
                direction = 'vertical'
            }
            item_flow.style.horizontal_align = 'center'
            item_flow.style.minimal_width = 80

            local item_btn = item_flow.add({
                type = 'sprite-button',
                sprite = 'item/' .. item.item_name,
                name = 'chaoshikongshangdian_purchase_btn',
                tooltip = {'tianfu.chaoshikongshangdian_item_tooltip', item_prototype.localised_name or item.item_name, item.price}
            })
            item_btn.style.minimal_width = 60
            item_btn.style.minimal_height = 60
            
            Gui.set_data(item_btn, item.item_name)

            local price_label = item_flow.add({
                type = 'label',
                caption = {'ic.chaoshikongshangdian_price', item.price}
            })
            price_label.style.font = 'default'
            price_label.style.font_color = {r = 1, g = 0.8, b = 0.2}
        end
    end

    local close_flow = main_frame.add {
        type = 'flow',
        direction = 'horizontal'
    }
    close_flow.style.horizontal_align = 'center'
    close_flow.style.horizontally_stretchable = true
    close_flow.style.top_padding = 10

    local close_btn = close_flow.add({
        type = 'button',
        caption = {'ic.close'},
        name = 'chaoshikongshangdian_close',
        tooltip = {'ic.close'}
    })
    close_btn.style.minimal_width = 80
    close_btn.style.font = 'default-bold'

    player.opened = main_frame
end

local function draw_players(data)
    local player_table = data.player_table
    local add_player_frame = data.add_player_frame
    local player = data.player
    local player_list = create_player_table(player)

    for p, _ in pairs(player_list.players) do
        Gui.set_data(add_player_frame, p)
        local t_label = player_table.add({
            type = 'label',
            caption = p
        })
        t_label.style.minimal_width = 75
        t_label.style.horizontal_align = 'center'

        local a_label = player_table.add({
            type = 'label',
            caption = '✔️'
        })
        a_label.style.minimal_width = 75
        a_label.style.horizontal_align = 'center'
        a_label.style.font = 'default-large-bold'

        local kick_flow = player_table.add {
            type = 'flow'
        }
        local kick_player_button = kick_flow.add({
            type = 'button',
            caption = {'amap.ic_remove_player', p},
            name = kick_player_name
        })
        if player.name == t_label.caption then
            kick_player_button.enabled = false
        end
        kick_player_button.style.minimal_width = 75
        Gui.set_data(kick_player_button, p)
    end
end

local function draw_main_frame(player)
    local main_frame = player.gui.screen.add({
        type = 'frame',
        name = main_frame_name,
        caption = {'ic.car_settings_title'},
        direction = 'vertical'
    })

    main_frame.auto_center = true
    local main_frame_style = main_frame.style
    main_frame_style.width = 400
    main_frame_style.use_header_filler = true

    local inside_frame = main_frame.add {
        type = 'frame',
        style = 'inside_shallow_frame'
    }
    local inside_frame_style = inside_frame.style
    inside_frame_style.padding = 0

    local inside_table = inside_frame.add {
        type = 'table',
        column_count = 1
    }
    local inside_table_style = inside_table.style
    inside_table_style.vertical_spacing = 5
    inside_table_style.top_padding = 10
    inside_table_style.left_padding = 10
    inside_table_style.right_padding = 0
    inside_table_style.bottom_padding = 10
    inside_table_style.width = 350

    local player_list = create_player_table(player)

    local add_player_frame = inside_table.add({
        type = 'button',
        caption = {'amap.ic_add_player'},
        name = add_player_name
    })
    local transfer_car_frame = inside_table.add({
        type = 'button',
        caption = {'amap.ic_transfer_car'},
        name = transfer_car_name
    })
    local allow_anyone_to_enter = inside_table.add({
        type = 'switch',
        name = allow_anyone_to_enter_name,
        switch_state = player_list.allow_anyone,
        allow_none_state = false,
        left_label_caption = {'ic.allow_all'},
        right_label_caption = {'ic.click_toggle'}
    })

    local player_table = inside_table.add {
        type = 'table',
        column_count = 3,
        draw_horizontal_lines = true,
        draw_vertical_lines = true,
        vertical_centering = true
    }
    local player_table_style = player_table.style
    player_table_style.vertical_spacing = 10
    player_table_style.width = 350
    player_table_style.horizontal_spacing = 30

    local name_label = player_table.add({
        type = 'label',
        caption = {'ic.name'},
        tooltip = ''
    })
    name_label.style.minimal_width = 75
    name_label.style.horizontal_align = 'center'

    local trusted_label = player_table.add({
        type = 'label',
        caption = {'ic.allowed'},
        tooltip = ''
    })
    trusted_label.style.minimal_width = 75
    trusted_label.style.horizontal_align = 'center'

    local operations_label = player_table.add({
        type = 'label',
        caption = {'amap.ic_operation'},
        tooltip = ''
    })
    operations_label.style.minimal_width = 75
    operations_label.style.horizontal_align = 'center'

    local data = {
        player_table = player_table,
        add_player_frame = add_player_frame,
        transfer_car_frame = transfer_car_frame,
        allow_anyone_to_enter = allow_anyone_to_enter,
        player = player
    }
    draw_players(data)

    player.opened = main_frame
end

local function add_stop_botton(player)
    local this = WPT.get()
    local pirce_wave = this.stop_wave * 3000 + 1
    local stop_function = true
    if this.stop_wave >= 12 then
        stop_function = false
    end

    if pirce_wave >= 100000 then
        pirce_wave = 100000
    end
    if stop_function then
        TopBar.add_button(player, {
            type = 'sprite-button',
            sprite = 'entity/behemoth-biter',
            name = stop_wave,
            tooltip = {'ic.ic_pause_wave_price', pirce_wave}
        })
    end
end

local function toggle(player, recreate)
    local screen = player.gui.screen
    local main_frame = screen[main_frame_name]

    if recreate and main_frame then
      
        remove_main_frame(main_frame)
        draw_main_frame(player)
        return
    end
    if main_frame then
        remove_main_frame(main_frame)
        Tabs.comfy_panel_restore_left_gui(player)
    else
        Tabs.comfy_panel_clear_left_gui(player)
        draw_main_frame(player)
    end
end

add_toolbar = function(player, remove)
    local flow = TopBar.get_button_flow(player)
    if remove then
        if flow[integration_button_name] then
            flow[integration_button_name].destroy()
            return
        end
    end
    if flow[integration_button_name] then
        return
    end
    
    TopBar.add_button(player, {
        type = 'sprite-button',
        sprite = 'item/rocket-silo',
        name = integration_button_name,
        tooltip = {'ic.integration_tooltip'}
    })
end

remove_toolbar = function(player)
    local screen = player.gui.screen
    local main_frame = screen[main_frame_name]

    if main_frame and main_frame.valid then
        remove_main_frame(main_frame)
    end

    if TopBar.get_button_flow(player)[integration_button_name] then
        TopBar.get_button_flow(player)[integration_button_name].destroy()
        

         
    local chaoshikongshangdian_frame = screen['chaoshikongshangdian_frame']
    if chaoshikongshangdian_frame and chaoshikongshangdian_frame.valid then
        chaoshikongshangdian_frame.destroy()
    end
    
    local integration_frame = screen[integration_frame_name]
    if integration_frame and integration_frame.valid then
        integration_frame.destroy()
    end
        -- 销毁整合面板
        local frame = screen[integration_frame_name]
        if frame and frame.valid then
            frame.destroy()
        end
        
        return
    end
end

local function trigger_on_used_car_door(data)
    local state = data.state
    local player = data.player

    if state == 'add' then
        add_toolbar(player)
    elseif state == 'remove' then
        remove_toolbar(player)
    end
end


GuiDispatcher.register_click(cool, function(event)

    local player = event.player
    local can_buy = false
    local need_coin = 3000

    if player.character.get_item_count('coin') >= need_coin then
        local luck = math.floor(math.random(1, 150))
        player.print({'amap.lucknb', luck})

        local magic = luck * 5 + 100
        local msg = {'amap.whatopen'}
        Loot.cool(player.physical_surface, player.physical_surface
  .find_non_colliding_position("steel-chest", player.physical_position, 20, 1, true) or player.physical_position, 'steel-chest',
            magic)
        Alert.alert_player(player, 5, msg)
        player.remove_item {
            name = 'coin',
            count = need_coin
        }
    else
        player.print({'amap.noenough'})
    end
end)

-- 品质开箱按钮点击处理
GuiDispatcher.register_click('integration_chest_quality', function(event)
    local player = event.player
    if not player or not player.valid then return end
    
    local need_coin = 5000
    local this = WPT.get()
    
    -- 初始化玩家购买计数器
    if not this.quality_chest_purchases then
        this.quality_chest_purchases = {}
    end
    if not this.quality_chest_purchases[player.index] then
        this.quality_chest_purchases[player.index] = 0
    end
    
    local purchase_count = this.quality_chest_purchases[player.index]
    local is_free = (purchase_count >= 10)
    local actual_cost = is_free and 0 or need_coin
    
    -- 检查玩家是否有足够的硬币（如果不是免费的）
    if player.character.get_item_count('coin') >= actual_cost then
        local luck = math.floor(math.random(1, 150))
        player.print({'amap.lucknb', luck})
        
        local magic = luck * 5 + 100
        local msg = {'amap.whatopen'}
        
        -- 如果是免费的，显示特殊消息
        if is_free then
            player.print({'amap.quality_chest_free'})
            this.quality_chest_purchases[player.index] = 0  -- 重置计数器
        else
            this.quality_chest_purchases[player.index] = purchase_count + 1  -- 增加计数器
            player.remove_item {
                name = 'coin',
                count = need_coin
            }
        end
        
        -- 显示购买进度
        local remaining_for_free = 10 - this.quality_chest_purchases[player.index]
        if remaining_for_free > 0 then
            player.print({'amap.quality_chest_purchases_left', remaining_for_free})
        end
        
        -- 调用品质开箱函数
        Loot.cool_with_quality(
            player.physical_surface, 
            player.physical_surface.find_non_colliding_position("steel-chest", player.physical_position, 20, 1, true) or player.physical_position, 
            'steel-chest',
            magic
        )
        
        Alert.alert_player(player, 5, msg)
    else
        player.print({'amap.noenough'})
    end
end)

-- 整合面板内的按钮处理
GuiDispatcher.register_click('integration_car_settings', function(event)
    local player = event.player
    if not player or not player.valid then return end
    
    -- 关闭整合面板
    local screen = player.gui.screen
    local frame = screen[integration_frame_name]
    if frame and frame.valid then
        frame.destroy()
    end
    
    -- 打开汽车设置面板
    draw_main_frame(player)
end)

GuiDispatcher.register_click('integration_chest', function(event)
    local player = event.player
    if not player or not player.valid then return end
    
    -- 执行存储箱功能
    local can_buy = false
    local need_coin = 3000
    
    if player.character.get_item_count('coin') >= need_coin then
        local luck = math.floor(math.random(1, 150))
        player.print({'amap.lucknb', luck})

        local magic = luck * 5 + 100
        local msg = {'amap.whatopen'}
        
        player.remove_item {
            name = 'coin',
            count = need_coin
        }
        
        Loot.cool(player.physical_surface, player.physical_surface
            .find_non_colliding_position("steel-chest", player.physical_position, 20, 1, true) or player.physical_position, 'steel-chest',
            magic)
        Alert.alert_player(player, 5, msg)
    else
        player.print({'amap.noenough'})
    end
end)

GuiDispatcher.register_click('integration_buy_xp', function(event)
    local player = event.player
    if not player or not player.valid then return end
    
    -- 执行购买经验功能
    local can_buy = false
    local need_coin = 5000
    if player.character.get_item_count('coin') >= need_coin then
        local rpg_t = rpgtable.get('rpg_t')
        local msg = {'amap.buyover'}
        Alert.alert_player(player, 5, msg)
        rpg_t[player.index].xp = rpg_t[player.index].xp + 1000
        player.remove_item {
            name = 'coin',
            count = need_coin
        }
    else
        player.print({'amap.noenough'})
    end
end)

GuiDispatcher.register_click('integration_buy_resources', function(event)
    local player = event.player
    if not player or not player.valid then return end

    -- 当前世界禁用汽车内生成矿物（纯塔防无矿设计）
    local map = diff.get()
    if World.get_field(map.world, 'disable_car_resource_generation') then
        player.print({'amap.td_world_no_resource_gen'}, {r=1, g=0.3, b=0.3})
        return
    end

    -- 执行购买资源功能
    local index = player.index
    local can_buy = false
    local this = WPT.get()

    if not this.ore_record[index] then
        this.ore_record[index] = 0
    end

       if this.ore_record[index] == 0 then
        player.insert {
            name = 'coin',
            count = 10000
        }
    end
    local need_coin = math.floor(this.ore_record[index] / 2) * 10000 + 10000

 

    if player.character.get_item_count('coin') >= need_coin then
        player.print({'amap.over_ore'})
        player.remove_item {
            name = 'coin',
            count = need_coin
        }
        local entity = this.tank[player.index]
        local position = entity.position
        local surface = entity.surface
        
        crate_ore(surface, position)
        crate_water(surface, position)
        this.ore_record[index] = this.ore_record[index] + 1
    else
        player.print({'amap.noenough'})
    end
end)

GuiDispatcher.register_click('integration_stop_wave', function(event)
    local player = event.player
    if not player or not player.valid then return end
    
    -- 执行暂停波次功能
    local this = WPT.get()

    -- 当前世界禁用暂停波防
    local map = diff.get()
    if World.get_field(map.world, 'disable_stop_wave') then
        player.print({'amap.td_world_no_pause_wave'}, {r=1, g=0.3, b=0.3})
        return false
    end

    if this.stop_wave >= 12 then
        player.print({'amap.stop_wave_max_reached'})
        return false
    end

    local wave_number = WD.get('wave_number')
    if wave_number <=0 then
        player.print({'amap.stop_wave_wave_too_low'})
        return false
    end
    if wave_number >= 2600 and wave_number <= 3005  then
        player.print({'amap.stop_wave_wave_too_low'})
        return false
    end
    local pirce_stop_wave = this.stop_wave * 3000 + 1
    local can_buy = false
    if this.last_stop_time + 60 * 60 * 30 >= game.tick and this.last_stop_time>0 then
        player.print({'amap.stop_wave_cooldown'})
        return
    end
    if player.character.get_item_count('coin') >= pirce_stop_wave then
        wave_defense_table = WD.get_table()
        wave_defense_table.game_lost = true
        this.stop_time = this.stop_time + 60 * 60 * 15
        this.stop_wave = this.stop_wave + 1
        game.print({'amap.buy_stop_wave' .. (this.world_number == 10 and '_world10' or ''), player.name, this.stop_time / 3600})
        player.remove_item {
            name = 'coin',
            count = pirce_stop_wave
        }
        this.last_stop_time = game.tick
        Collapse.start_now(false)
        if TopBar.get_button_flow(player)[stop_wave] then
            TopBar.get_button_flow(player)[stop_wave].destroy()
            add_stop_botton(player)
        end
    else
        player.print({'amap.noenough'})
    end
end)

GuiDispatcher.register_click('integration_chaoshikongshangdian', function(event)
    local player = event.player
    if not player or not player.valid then return end
    
    local tianfu_this = TPT.get()
    local index = player.index
    
    if not tianfu_this.chaoshikongshangdian_items or not tianfu_this.chaoshikongshangdian_items[index] then
        player.print({'tianfu.chaoshikongshangdian_no_item'})
        return
    end
    
    local shop_items = tianfu_this.chaoshikongshangdian_items[index]
    if #shop_items == 0 then
        player.print({'tianfu.chaoshikongshangdian_no_item'})
        return
    end
    
    draw_chaoshikongshangdian_frame(player)
end)

GuiDispatcher.register_click('integration_close', function(event)
    local player = event.player
    if not player or not player.valid then return end
    
    -- 关闭整合面板
    local screen = player.gui.screen
    local frame = screen[integration_frame_name]
    if frame and frame.valid then
        frame.destroy()
    end
end)

GuiDispatcher.register_click('chaoshikongshangdian_close', function(event)
    local player = event.player
    if not player or not player.valid then return end
    
    -- 关闭超时空商店面板
    local screen = player.gui.screen
    local frame = screen['chaoshikongshangdian_frame']
    if frame and frame.valid then
        frame.destroy()
    end
end)

GuiDispatcher.register_click('chaoshikongshangdian_purchase_btn', function(event)
    local player = event.player
    if not player or not player.valid then return end
    
    local element = event.element
    local item_name = Gui.get_data(element)
    
    if not item_name then return end
    
    local tianfu_this = TPT.get()
    local index = player.index
    
    if not tianfu_this.chaoshikongshangdian_items or not tianfu_this.chaoshikongshangdian_items[index] then
        player.print({'tianfu.chaoshikongshangdian_no_item'})
        return
    end
    
    local shop_items = tianfu_this.chaoshikongshangdian_items[index]
    
    local item_index = nil
    for i, item in ipairs(shop_items) do
        if item.item_name == item_name then
            item_index = i
            break
        end
    end
    
    if not item_index then return end
    
    local item = shop_items[item_index]
    local price = item.price
    local item_count = item.item_count
    
    local spent = tianfu_this.chaoshikongshangdian_spent[index] or 0
    local max_spent = 10000
    
    if spent + price > max_spent then
        player.print({'tianfu.chaoshikongshangdian_limit_reached', max_spent})
        return
    end
    
    if player.character.get_item_count('coin') >= price then
        player.remove_item {
            name = 'coin',
            count = price
        }

        player.insert {
            name = item_name,
            count = item_count
        }

        local item_prototype = prototypes.item[item_name]
        local item_localised_name = item_prototype and item_prototype.localised_name or item_name
        player.print({'tianfu.chaoshikongshangdian_purchase_success', item_localised_name, price})

        tianfu_this.chaoshikongshangdian_spent[index] = spent + price

        local screen = player.gui.screen
        local frame = screen['chaoshikongshangdian_frame']
        if frame and frame.valid then
            frame.destroy()
            draw_chaoshikongshangdian_frame(player)
        end
    else
        player.print({'amap.noenough'})
    end
end)

-- 整合按钮点击处理
GuiDispatcher.register_click(integration_button_name, function(event)
    local player = event.player
    if not player or not player.valid or not player.character then
        return
    end

    local screen = player.gui.screen
    local frame = screen[integration_frame_name]

    if frame and frame.valid then
        frame.destroy()
    else
        draw_integration_frame(player)
    end
end)

GuiDispatcher.register_click(buyxp, function(event)
    local player = event.player
    local can_buy = false
    local need_coin = 5000
    if player.character.get_item_count('coin') >= need_coin then
        local rpg_t = rpgtable.get('rpg_t')
        local msg = {'amap.buyover'}
        Alert.alert_player(player, 5, msg)
        rpg_t[player.index].xp = rpg_t[player.index].xp + 1000
        player.remove_item {
            name = 'coin',
            count = need_coin
        }
    else
        player.print({'amap.noenough'})
    end

end)

GuiDispatcher.register_click(up_coin, function(event)
    local player = event.player
    local can_buy = false
    local this = WPT.get()
    local index = player.index
    local need_coin = this.up_coin[index] * 360 + 360

    if player.character.get_item_count('coin') + this.up_jijing[index] >= need_coin then

        this.up_coin[index] = this.up_coin[index] + 1

        player.play_sound({
            path = 'utility/new_objective',
            volume_modifier = 0.75
        })

        if this.up_jijing[index] < need_coin then
            player.remove_item {
                name = 'coin',
                count = need_coin - this.up_jijing[index]
            }
            player.print({'amap.buy_up', this.up_jijing[index]})
            this.up_jijing[index] = 0

        else
            this.up_jijing[index] = this.up_jijing[index] - need_coin
            player.print({'amap.buy_up', need_coin})
        end
    else
        player.print({'amap.noenough'})
    end

end)

GuiDispatcher.register_click(up_xp, function(event)
    local player = event.player
    local can_buy = false
    local index = player.index
    local this = WPT.get()
    local need_coin = this.up_xp[index] * 720 + 720

    if player.character.get_item_count('coin') + this.up_jijing[index] >= need_coin then
        this.up_xp[index] = this.up_xp[index] + 1

        player.play_sound({
            path = 'utility/new_objective',
            volume_modifier = 0.75
        })
        if this.up_jijing[index] < need_coin then
            player.remove_item {
                name = 'coin',
                count = need_coin - this.up_jijing[index]
            }
            player.print({'amap.buy_up', this.up_jijing[index]})
            this.up_jijing[index] = 0
        else
            this.up_jijing[index] = this.up_jijing[index] - need_coin
            player.print({'amap.buy_up', need_coin})

        end
    else
        player.print({'amap.noenough'})
    end

end)

GuiDispatcher.register_click(up_jijing, function(event)
    local player = event.player
    local can_buy = false
    local index = player.index
    local this = WPT.get()
    local need_coin = this.jijing_k[index] * 240 + 240

    if player.character.get_item_count('coin') + this.up_jijing[index] >= need_coin then
        this.jijing_k[index] = this.jijing_k[index] + 1
        player.play_sound({
            path = 'utility/new_objective',
            volume_modifier = 0.75
        })
        if this.up_jijing[index] < need_coin then
            player.remove_item {
                name = 'coin',
                count = need_coin - this.up_jijing[index]
            }
            player.print({'amap.buy_up', this.up_jijing[index]})
            this.up_jijing[index] = 0
        else
            this.up_jijing[index] = this.up_jijing[index] - need_coin
            player.print({'amap.buy_up', need_coin})

        end
    else
        player.print({'amap.noenough'})
    end

end)

GuiDispatcher.register_click(stop_wave, function(event)
    local player = event.player

    -- 当前世界禁用暂停波防
    local map = diff.get()
    if World.get_field(map.world, 'disable_stop_wave') then
        player.print({'amap.td_world_no_pause_wave'}, {r=1, g=0.3, b=0.3})
        return false
    end

    local this = WPT.get()

    if this.stop_wave >= 12 then
        player.print({'amap.stop_wave_max_reached'})
        return false
    end

    local wave_number = WD.get('wave_number')
    if wave_number <=0 then
        player.print({'amap.stop_wave_wave_too_low'})
        return false
    end
    if wave_number >= 2600 and wave_number <= 3005  then
        player.print({'amap.stop_wave_wave_too_low'})
        return false
    end
    local pirce_stop_wave = this.stop_wave * 3000 + 1
    local can_buy = false
    if this.last_stop_time + 60 * 60 * 30 >= game.tick and this.last_stop_time>0 then
        player.print({'amap.stop_wave_cooldown'})
        return
    end
    if player.character.get_item_count('coin') >= pirce_stop_wave then
        wave_defense_table = WD.get_table()
        wave_defense_table.game_lost = true
        this.stop_time = this.stop_time + 60 * 60 * 15
        this.stop_wave = this.stop_wave + 1
        game.print({'amap.buy_stop_wave', player.name, this.stop_time / 3600})
        player.remove_item {
            name = 'coin',
            count = pirce_stop_wave
        }
        this.last_stop_time = game.tick
        Collapse.start_now(false)
        if TopBar.get_button_flow(player)[stop_wave] then
            TopBar.get_button_flow(player)[stop_wave].destroy()
            add_stop_botton(player)
        end
    else
        player.print({'amap.noenough'})
    end
end)

GuiDispatcher.register_click(add_player_name, function(event)
    local player = event.player
    if not player or not player.valid or not player.character then
        return
    end

    local screen = player.gui.screen
    local frame = screen[main_frame_name]
    if not frame or not frame.valid then
        return
    end
    local player_frame = frame[draw_add_player_frame_name]
    if not player_frame or not player_frame.valid then
        draw_add_player(player, frame)
    else
        player_frame.destroy()
    end
end)

GuiDispatcher.register_click(transfer_car_name, function(event)
    local player = event.player
    if not player or not player.valid or not player.character then
        return
    end

    local screen = player.gui.screen
    local frame = screen[main_frame_name]
    if not frame or not frame.valid then
        return
    end
    local player_frame = frame[draw_transfer_car_frame_name]
    if not player_frame or not player_frame.valid then
        draw_transfer_car(player, frame)
    else
        player_frame.destroy()
    end
end)

GuiDispatcher.register_click(allow_anyone_to_enter_name, function(event)
    local player = event.player

    if not player or not player.valid or not player.character then
        return
    end

    local player_list = create_player_table(player)

    local screen = player.gui.screen
    local frame = screen[main_frame_name]

    if frame and frame.valid then
        if player_list.allow_anyone == 'right' then
            player_list.allow_anyone = 'left'
            player.print({'ic.everyone_can_enter'}, Color.warning)

        else
            player_list.allow_anyone = 'right'
            player.print({'ic.only_allowed_can_enter'}, Color.warning)

        end

        if player.gui.screen[main_frame_name] then
            toggle(player, true)
        end
    end
end)

GuiDispatcher.register_click(save_add_player_button_name, function(event)
    local player = event.player
    if not player or not player.valid or not player.character then
        return
    end

    local player_list = create_player_table(player)

    local screen = player.gui.screen
    local frame = screen[main_frame_name]
    local add_player_frame = Gui.get_data(event.element)

    if frame and frame.valid then
        if add_player_frame and add_player_frame.valid and add_player_frame then
            local player_gui_data = ICT.get('player_gui_data')
            local fetched_name = player_gui_data[player.name]
            if not fetched_name then
                return
            end

            local player_to_add = game.get_player(fetched_name)
            if not player_to_add or not player_to_add.valid then
                return player.print({'ic.invalid_player'}, Color.warning)
            end

            local name = player_to_add.name

            if not player_list.players[name] then
                player.print({'ic.player_allowed', name}, Color.info)
                player_to_add.print({'ic.player_allowed_notify', player.name}, Color.info)
                increment(player_list.players, name)
            else
                return player.print({'amap.ic_player_already_trusted'}, Color.warning)
            end

            remove_main_frame(event.element)

            if player.gui.screen[main_frame_name] then
                toggle(player, true)
            end
        end
    end
end)

GuiDispatcher.register_click(save_transfer_car_button_name, function(event)
    local player = event.player
    if not player or not player.valid or not player.character then
        return
    end

    local screen = player.gui.screen
    local frame = screen[main_frame_name]
    local transfer_car_frame = Gui.get_data(event.element)

    if frame and frame.valid then
        if transfer_car_frame and transfer_car_frame.valid then
            local player_gui_data = ICT.get('player_gui_data')
            local fetched_name = player_gui_data[player.name]
            if not fetched_name then
                return
            end

            local player_to_add = game.get_player(fetched_name)
            if not player_to_add or not player_to_add.valid then
                return player.print({'ic.invalid_player'}, Color.warning)
            end
            local name = player_to_add.name

            local does_player_have_a_car = does_player_table_exist(player_to_add)
            if does_player_have_a_car then
                return player.print({'ic.player_has_car', name}, Color.warning)
            end

            local success = transfer_player_table(player, player_to_add)
            if not success then
                player.print({'ic.please_retry'}, Color.warning)
            else
                player.print({'amap.ic_vehicle_sent_successfully', name}, Color.success)
                player_to_add.print({'amap.ic_received_vehicle', player.name}, Color.success)
            end

            remove_main_frame(event.element)

            if player.gui.screen[main_frame_name] then
                player.gui.screen[main_frame_name].destroy()
            end
        end
    end
end)

GuiDispatcher.register_click(kick_player_name, function(event)
    local player = event.player
    if not player or not player.valid or not player.character then
        return
    end

    local player_list = create_player_table(player)

    local screen = player.gui.screen
    local frame = screen[main_frame_name]
    local player_name = Gui.get_data(event.element)

    if frame and frame.valid then
        if not player_name then
            return
        end
        local target = game.get_player(player_name)
        if not target or not target.valid then
            player.print({'ic.invalid_player'}, Color.warning)
            return
        end
        local name = target.name

        if player_list.players[name] then
            player.print({'ic.player_removed', name}, Color.info)
            decrement(player_list.players, name)
            raise_event(ICT.events.on_player_kicked_from_surface, {
                player = player,
                target = target
            })
        end

        remove_main_frame(event.element)

        if player.gui.screen[main_frame_name] then
            toggle(player, true)
        end
    end
end)

GuiDispatcher.register_click(discard_add_player_button_name, function(event)
    local player = event.player
    if not player or not player.valid or not player.character then
        return
    end

    local screen = player.gui.screen
    local frame = screen[main_frame_name]
    if not frame or not frame.valid then
        return
    end
    local player_frame = frame[draw_add_player_frame_name]

    if player_frame and player_frame.valid then
        player_frame.destroy()
    end
end)

GuiDispatcher.register_click(discard_transfer_car_button_name, function(event)
    local player = event.player
    if not player or not player.valid or not player.character then
        return
    end

    local screen = player.gui.screen
    local frame = screen[main_frame_name]
    if not frame or not frame.valid then
        return
    end
    local player_frame = frame[draw_transfer_car_frame_name]

    if player_frame and player_frame.valid then
        player_frame.destroy()
    end
end)

GuiDispatcher.register_click(main_toolbar_name, function(event)
    local player = event.player
    if not player or not player.valid or not player.character then
        return
    end

    local screen = player.gui.screen
    local frame = screen[main_frame_name]

    if frame and frame.valid then
        frame.destroy()
    else
        draw_main_frame(player)
    end
end)

GuiDispatcher.register_selection_state_changed(transfer_player_select_name, function(event)
    local player = event.player
    if not player or not player.valid or not player.character then
        return
    end

    local screen = player.gui.screen
    local frame = screen[main_frame_name]
    if not frame or not frame.valid then
        return
    end

    local element = event.element
    if not element or not element.valid then
        return
    end

    local player_gui_data = ICT.get('player_gui_data')
    local selected = element.items[element.selected_index]
    if not selected then
        return
    end

    if selected == 'Select Player' then
        player.print({'ic.no_player_selected'}, Color.warning)
        player_gui_data[player.name] = nil
        return
    end

    if selected == player.name then
        player.print({'ic.cannot_select_self'}, Color.warning)
        player_gui_data[player.name] = nil
        return
    end

    player_gui_data[player.name] = selected
end)



Public.draw_main_frame = draw_main_frame
Public.toggle = toggle
Public.add_toolbar = add_toolbar
Public.remove_toolbar = remove_toolbar
Public.integration_frame_name = integration_frame_name

GuiDispatcher.register_closed(main_frame_name, function(event)
    local player = game.get_player(event.player_index)
    if not player or not player.valid or not player.character then
        return
    end

    local screen = player.gui.screen
    local frame = screen[main_frame_name]
    if frame and frame.valid then
        frame.destroy()
    end
end)

Event.add(ICT.events.used_car_door, trigger_on_used_car_door)

return Public
