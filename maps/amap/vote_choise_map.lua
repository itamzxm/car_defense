local Event = require 'utils.event'
local Gui = require 'utils.gui'
local WPT = require 'maps.amap.table'
local World = require 'maps.amap.world.framework'  -- 世界框架

local main_button_name = "poll_button"
local main_frame_name = "poll_frame"

Gui.allow_player_to_toggle_top_element_visibility(main_button_name)

-- 获取表中的最大值对应的键
local function getKeyOfMaxValue(tbl)
    local maxValue = nil
    local maxKey = nil
    for key, value in pairs(tbl) do
        if not maxValue or value > maxValue then
            maxValue = value
            maxKey = key
        end
    end
    return maxKey
end

-- 创建主按钮的函数
local function create_main_button(event)
    local player = game.players[event.player_index]
    if not player or not player.valid then
        return
    end
    if Gui.get_button_flow(player)[main_button_name] then
        return
    end
    local b = Gui.add_top_element(player, {
        type = 'sprite-button',
        name = main_button_name,
        caption = {'amap.next_map'}
    })
    -- 地图名较长，宽度保持；高度由 mod_gui_button 统一样式控制
    b.style.minimal_width = 120
    -- 青绿文字（mod_gui_button 深色底上清晰），参考 archive/classic-changes 设计
    b.style.font_color = {0, 255, 255}
end

-- 更新主按钮的显示数据
local function updata_gui(player)
    local WPT = WPT.get()
    local button = Gui.get_button_flow(player)[main_button_name]
    
    if not button or not button.valid then return end

    -- 检查玩家是否已经投票 (现在 vote_count 存储的是投票的地图ID，如果没投则为 nil)
    local has_voted = WPT.vote_count[player.name]

    if has_voted then
        -- 需求3: 如果已经投票了，就显示当前领先的地图
        -- 并且鼠标移动上去(Tooltip)，能提示下一张地图是什么
        if WPT.vote_map_number ~= nil then
            button.caption = {'amap.world_name_' .. WPT.vote_map_number}
            button.tooltip = {'', {'amap.next_map'}, ': ', {'amap.world_name_' .. WPT.vote_map_number}}
        else
            button.caption = {'amap.next_map'}
            button.tooltip = nil
        end
    else
        -- 需求2: 如果还没有投票，按钮就显示投票下一张地图 (保持默认文案)
        button.caption = {'amap.next_map'}
        button.tooltip = "点击投票 / Click to vote"
    end
end

-- 打开投票界面的函数
local function gui_open(player)
    local WPT = WPT.get()
    
    -- 防止重复创建
    if player.gui.screen[main_frame_name] then
        player.gui.screen[main_frame_name].destroy()
    end

    local frame = player.gui.screen.add {
        type = 'frame',
        name = main_frame_name,
        caption = {'amap.next_map'},
        direction = 'vertical'
    }
    frame.location = {x = 255, y = 40}

    -- 添加投票选项
    -- World 框架优先：动态查询所有已注册世界；fallback：硬编码列表
    -- 排除 selectable==false 的已禁用世界（如世界7 异次元大逃杀）
    local all_worlds = World.get_registered_worlds()
    local valid_worlds = {}
    for _, id in ipairs(all_worlds) do
        if World.get_field(id, 'selectable') ~= false then
            table.insert(valid_worlds, id)
        end
    end
    if #valid_worlds == 0 then
        valid_worlds = {1, 2, 3, 6, 8, 9, 10,11,12,13,14}
    end
    for _, i in ipairs(valid_worlds) do
        local map_key = tostring(i)
        -- 获取当前票数，如果没有则为0
        local count = WPT.huantu_choise[map_key] or 0
        
        -- 需求4: 投票的时候显示每个地图的票数
        -- caption 格式示例: "世界1 (3)"
        local button_caption = {'', {'amap.world_name_' .. i}, ' (' .. count .. ')'}

        local button = frame.add {
            type = 'button',
            name = map_key, -- 按钮名称直接使用地图ID字符串
            caption = button_caption,
            tooltip = {'amap.world_name_info_' .. i}
        }
        button.style.minimal_width = 150
        button.style.minimal_height = 30
        button.style.font = 'default-bold'
        button.style.padding = 3
        
        -- 如果玩家当前选的是这个，高亮显示一下（可选优化）
        if WPT.vote_count[player.name] == map_key then
            button.style.font_color = {0, 255, 0} -- 绿色代表已选
        end
    end
    
    -- 添加一个关闭按钮
    local close_btn = frame.add {
        type = 'button',
        name = 'close_poll_frame',
        caption = 'Close / 关闭'
    }
    close_btn.style.minimal_width = 150
end

-- 处理界面点击事件的函数
local function on_gui_click(event)
    local player = game.players[event.player_index]
    if not player or not player.valid then return end
    if not event.element or not event.element.valid then return end
    
    -- 处理关闭按钮
    if event.element.name == 'close_poll_frame' then
        if event.element.parent then event.element.parent.destroy() end
        return
    end

    if not event.element.parent or not event.element.parent.valid then return end
    if event.element.parent.name ~= main_frame_name then return end

    local WPT = WPT.get()
    local choise = event.element.name -- 获取点击的地图ID (字符串)
    
    -- 简单的校验，确保点击的是地图按钮而不是其他东西
    if not tonumber(choise) then return end

    -- 需求1: 已经投票的还可以再投 (改票逻辑)
    local previous_vote = WPT.vote_count[player.name]

    -- 如果点击了自己已经投过的票，不做处理或者关闭窗口
    if previous_vote == choise then
        player.print({'amap.already_voted_for', {'amap.world_name_' .. choise}})
        local frame = player.gui.screen[main_frame_name]
        if frame then frame.destroy() end
        return
    end

    -- 1. 如果之前投过票，先减去旧的票数
    if previous_vote then
        if WPT.huantu_choise[previous_vote] and WPT.huantu_choise[previous_vote] > 0 then
            WPT.huantu_choise[previous_vote] = WPT.huantu_choise[previous_vote] - 1
        end
    end

    -- 2. 增加新选择的地图票数
    if not WPT.huantu_choise[choise] then
        WPT.huantu_choise[choise] = 0
    end
    WPT.huantu_choise[choise] = WPT.huantu_choise[choise] + 1

    -- 3. 记录玩家新的投票选择 (存储ID)
    WPT.vote_count[player.name] = choise

    -- 关闭投票窗口
    local frame = player.gui.screen[main_frame_name]
    if frame then frame.destroy() end

    -- 重新计算票数最高的地图（只统计在线人员）
    local online_votes = {}
    for _, p in pairs(game.connected_players) do
        local vote = WPT.vote_count[p.name]
        if vote then
            if not online_votes[vote] then
                online_votes[vote] = 0
            end
            online_votes[vote] = online_votes[vote] + 1
        end
    end
    WPT.vote_map_number = getKeyOfMaxValue(online_votes)

    -- 更新所有玩家的主按钮显示，并刷新打开的投票窗口(为了即时更新票数显示)
    for _, p in pairs(game.connected_players) do
        updata_gui(p)
        -- 如果其他玩家开着投票窗口，刷新它以显示最新票数
        if p.gui.screen[main_frame_name] then
            gui_open(p)
        end
    end
    
    player.print({'amap.vote_success', {'amap.world_name_' .. choise}})
end

Gui.on_click(
    main_button_name,
    function(event)
        local player = event.player
        local frame = player.gui.screen[main_frame_name]
        
        -- 如果窗口已打开则关闭
        if frame ~= nil then
            frame.destroy()
        else
            -- 需求1: 无论是否投过票，都可以打开窗口进行投票/改票
            gui_open(player)
        end
    end
)

Event.add(defines.events.on_player_joined_game, function(e)
    create_main_button(e)
    local player = game.players[e.player_index]
    if player then updata_gui(player) end
end)

Event.add(defines.events.on_gui_click, on_gui_click)