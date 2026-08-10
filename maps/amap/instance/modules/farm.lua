-- maps/amap/instance/modules/farm.lua
-- 农场小馆玩法模块（GUI 逻辑 + surface 装饰）
--
-- 玩法类型：farm
-- 玩法说明：限时种菜赚钱，累计收入达到目标即可通关
--   - 农田：8 列 × 5 行 = 40 块（dirt 色块模拟田，石墙围边）
--   - 初始按难度解锁若干块（easy/normal 8 块，hard 6 块），
--     其余可花 25 金币逐块解锁（行优先顺序：第 1 行 → 第 8 列）
--   - 作物：小麦 {5,12,30s} → 胡萝卜 {15,40,45s} → 番茄 {40,110,60s} → 南瓜 {100,300,90s}
--     （cost=种子成本，price=成熟收获价，grow=生长秒数）
--   - 生长：种子 → 幼苗 → 成株 → 成熟 4 阶段（各占生长时间 1/3，成熟即收获）
--   - 操作流：点下方种子按钮选中 → 点空地农田种植（扣成本）；
--     成熟农田点击收获（计入收入，若有金雨 ×2）；生长中农田点击选中后
--     可花 2 金币浇水（剩余时间 -25%）；解锁按钮花 25 金币解锁下一块
--   - 随机事件（每 30 秒 15% 概率）：金雨（下次收获 ×2 一次性）
--     或 虫害（随机一块生长中农田暂停 5 秒）
--   - 胜利：限时内累计收入 >= 目标收入
--
-- 难度表（target_income 目标收入 / time_limit 限时 tick / start_coins 起始金币
--            / initial_unlocked 初始解锁农田数 / reward_multiplier 奖励系数）：
--   easy   = 200 收入 / 21600 tick（6 分钟）/ 50 金币 / 8 块 / 1.0
--   normal = 500 收入 / 21600 tick（6 分钟）/ 30 金币 / 8 块 / 1.5
--   hard   = 1000 收入 / 25200 tick（7 分钟）/ 20 金币 / 6 块 / 2.0
-- 奖励系数加成：提前完成每剩余 30 秒 +1%，上限 +15%（mult = 基础系数 + 加成）

local Instance = require 'maps.amap.instance.instance'

local M = {}

--==============================================================================
-- 元数据
--==============================================================================

M.type = 'farm'
M.display_name_key = 'amap.instance_farm_name'
M.description_key = 'amap.instance_farm_desc'
M.gameplay_desc_key = 'amap.instance_farm_gameplay'
M.victory_condition_key = 'amap.instance_farm_victory'
M.icon = 'item/raw-fish'
M.time_limit_default = 6 * 60 * 60  -- 默认 6 分钟（各难度覆盖）

--==============================================================================
-- 难度
--==============================================================================

M.difficulty_settings = {
    easy = {
        name = 'easy',
        recycling_efficiency = 1,
        max_coins = 0,
        display_name_key = 'dungeon_difficulty_easy',
        target_income = 200,          -- 目标累计收入
        time_limit = 6 * 60 * 60,     -- 6 分钟
        start_coins = 50,             -- 起始金币
        initial_unlocked = 8,         -- 初始解锁农田块数
        reward_multiplier = 1.0,      -- 基础奖励系数
    },
    normal = {
        name = 'normal',
        recycling_efficiency = 1,
        max_coins = 0,
        display_name_key = 'dungeon_difficulty_normal',
        target_income = 500,
        time_limit = 6 * 60 * 60,     -- 6 分钟
        start_coins = 30,
        initial_unlocked = 8,
        reward_multiplier = 1.5,
    },
    hard = {
        name = 'hard',
        recycling_efficiency = 1,
        max_coins = 0,
        display_name_key = 'dungeon_difficulty_hard',
        target_income = 1000,
        time_limit = 7 * 60 * 60,     -- 7 分钟
        start_coins = 20,
        initial_unlocked = 6,
        reward_multiplier = 2.0,
    },
}

--==============================================================================
-- 常量
--==============================================================================

-- 农田布局：8 列 × 5 行 = 40 块
local FARM_COLS = 8
local FARM_ROWS = 5

-- 解锁下一块农田的价格
local UNLOCK_PRICE = 25
-- 浇水价格
local WATER_PRICE = 2
-- 浇水效果：剩余生长时间 -25%
local WATER_REDUCE = 0.25
-- 虫害暂停秒数
local PEST_PAUSE_SECONDS = 5
-- 随机事件周期（秒）与概率
local EVENT_INTERVAL = 30
local EVENT_CHANCE = 0.15
-- 框架超时宽限 3 秒（参照 whack_a_mole.lua）：框架 remaining<=0 时直接 timeout 传送，
-- 不再调用 check_victory；data.time_limit 加宽限后，胜负在宽限窗口内由 check_victory
-- 用实际限时（md.diff.time_limit / md.end_tick）结算
local TIMEOUT_GRACE = 180

-- 作物表（写死常量）：cost=种子成本 / price=收获价 / grow=生长秒数
local CROPS = {
    wheat =   {cost = 5,   price = 12,   grow = 30},
    carrot =  {cost = 15,  price = 40,   grow = 45},
    tomato =  {cost = 40,  price = 110,  grow = 60},
    pumpkin = {cost = 100, price = 300,  grow = 90},
}

-- 种子按钮渲染顺序（从小到大，与作物解锁节奏一致）
local CROPS_ORDER = {'wheat', 'carrot', 'tomato', 'pumpkin'}

-- 阶段（stage 值：1 种子 / 2 幼苗 / 3 成株 / 4 成熟）
local STAGE_KEYS = {
    [1] = 'farm_stage_seed',
    [2] = 'farm_stage_seedling',
    [3] = 'farm_stage_plant',
    [4] = 'farm_stage_mature',
}

-- 阶段颜色
local STAGE_COLOR = {
    [1] = {0.7, 0.7, 0.5},   -- 种子：暗黄
    [2] = {0.4, 0.8, 0.4},   -- 幼苗：绿
    [3] = {0.2, 0.7, 0.25},  -- 成株：深绿
    [4] = {1, 0.84, 0},      -- 成熟：金黄
}

-- GUI 元素名（前缀 dungeon_module_farm_ 防冲突）
local GUI_FRAME = 'dungeon_module_farm_frame'
local GUI_STATUS = 'dungeon_module_farm_status'
local GUI_SHOP = 'dungeon_module_farm_shop'
local GUI_BOARD = 'dungeon_module_farm_board'
local GUI_OP_FLOW = 'dungeon_module_farm_op_flow'
local GUI_UNLOCK = 'dungeon_module_farm_unlock'
local GUI_WATER = 'dungeon_module_farm_water'
local GUI_HINT = 'dungeon_module_farm_hint'
local SEED_PREFIX = 'dungeon_module_farm_seed_'
local CELL_PREFIX = 'dungeon_module_farm_cell_'

-- 农田格按钮尺寸
local CELL_W = 96
local CELL_H = 42

-- 农田格在 surface 上的绘制参数（每个格子 2×2 tile，间距 3）
local PLOT_PITCH = 3
local PLOT_SIZE = 2
local PLOT_X0 = -11
local PLOT_Y0 = -6

-- 石墙范围
local WALL_X_MIN = -13
local WALL_X_MAX = 12
local WALL_Y_MIN = -8
local WALL_Y_MAX = 8
-- 玩家出生点（农田南侧空地，坐标与 on_surface_init 布局一致；
-- 传送由框架处理，模块不要在 on_surface_init 里 teleport——此时角色还在主世界 surface）
-- 出生坐标 = {x = 0, y = 7}

--==============================================================================
-- 辅助函数
--==============================================================================

-- 格子索引（行优先）：idx = (r - 1) * FARM_COLS + c
local function cell_index(r, c)
    return (r - 1) * FARM_COLS + c
end

-- 由索引反算行/列
local function cell_pos(idx)
    return {
        row = math.floor((idx - 1) / FARM_COLS) + 1,
        col = (idx - 1) % FARM_COLS + 1,
    }
end

-- 计算指定农田的当前阶段（1..4），elapsed_tick = 已生长 tick
local function calc_stage(cell, elapsed_tick)
    local total = cell.grow_seconds * 60
    if elapsed_tick >= total then return 4 end
    local q = elapsed_tick / total
    if q < 1 / 3 then return 1 end
    if q < 2 / 3 then return 2 end
    return 3
end

-- 农田格按钮显示文本：生长中 "小麦 幼苗 12s"；成熟 "小麦 成熟"
-- 注意：LocalisedString 不能与字符串 `..` 拼接，必须用 {'', ...} 数组形式（参照 whack_a_mole.lua）
local function cell_caption(cell)
    if not cell.crop then
        return cell.unlocked and {'amap.farm_cell_empty'} or {'amap.farm_cell_locked'}
    end
    local crop_name = {'amap.farm_crop_' .. cell.crop}
    if cell.stage >= 4 then
        return {'', crop_name, ' ', {'amap.farm_stage_mature'}}
    end
    local elapsed = game.tick - cell.plant_tick
    local remaining = cell.grow_seconds * 60 - elapsed
    if remaining < 0 then remaining = 0 end
    local secs = math.ceil(remaining / 60)
    return {'', crop_name, ' ', {'amap.' .. STAGE_KEYS[cell.stage]}, ' ', tostring(secs), 's'}
end

-- 重绘单个农田格按钮
local function refresh_cell(player, md, idx)
    local frame = player.gui.screen[GUI_FRAME]
    if not frame or not frame.valid then return end
    local cell = md.farmlands[idx]
    if not cell then return end
    local pos = cell_pos(idx)
    -- 农田格是 board（frame 的子 table）的子元素，必须两级查找
    local board = frame[GUI_BOARD]
    local btn = board and board[CELL_PREFIX .. pos.row .. '_' .. pos.col]
    if not btn or not btn.valid then return end

    btn.caption = cell_caption(cell)
    if not cell.unlocked then
        btn.style.font_color = {0.45, 0.45, 0.45}
    elseif not cell.crop then
        btn.style.font_color = {0.62, 0.62, 0.62}
    else
        btn.style.font_color = STAGE_COLOR[cell.stage] or {1, 1, 1}
    end
end

-- 更新状态栏 + 解锁/浇水按钮可用性
local function refresh_status(player, md)
    local frame = player.gui.screen[GUI_FRAME]
    if not frame or not frame.valid then return end

    local status = frame[GUI_STATUS]
    if status and status.valid then
        local remaining = math.max(0, math.floor((md.end_tick - game.tick) / 60))
        status.caption = {
            'amap.farm_status', md.coins, md.income, md.diff.target_income, remaining
        }
    end

    -- 解锁/浇水按钮是 op_flow（frame 的子 flow）的子元素，必须两级查找
    local op_flow = frame[GUI_OP_FLOW]
    local unlock = op_flow and op_flow[GUI_UNLOCK]
    if unlock and unlock.valid then
        unlock.enabled = md.coins >= UNLOCK_PRICE and md.next_locked_index <= #md.farmlands
    end

    local water = op_flow and op_flow[GUI_WATER]
    if water and water.valid then
        water.enabled = md.coins >= WATER_PRICE and md.watered_cell ~= nil
    end
end

--==============================================================================
-- GUI 创建/销毁
--==============================================================================

local function create_main_gui(player, data)
    local screen = player.gui.screen
    if screen[GUI_FRAME] then
        screen[GUI_FRAME].destroy()
    end

    local md = data.module_data

    local frame = screen.add({
        type = 'frame',
        name = GUI_FRAME,
        caption = {'amap.instance_farm_name'},
        direction = 'vertical'
    })
    frame.force_auto_center()
    frame.style.minimal_width = FARM_COLS * CELL_W + 40
    frame.style.maximal_width = FARM_COLS * CELL_W + 80

    -- 状态栏（金币 / 累计收入 / 目标 / 剩余时间）
    local status = frame.add({
        type = 'label',
        name = GUI_STATUS,
        caption = ''
    })
    status.style.font = 'default-bold'
    status.style.font_color = {1, 0.84, 0}

    -- 种子商店（4 种作物购买按钮）
    local shop = frame.add({
        type = 'flow',
        name = GUI_SHOP,
        direction = 'horizontal'
    })
    shop.style.top_padding = 4
    local shop_label = shop.add({
        type = 'label',
        caption = {'', {'amap.farm_shop_label'}, '：'}
    })
    shop_label.style.font = 'default-bold'
    for _, crop in ipairs(CROPS_ORDER) do
        local def = CROPS[crop]
        local btn = shop.add({
            type = 'button',
            name = SEED_PREFIX .. crop,
            caption = {'', {'amap.farm_crop_' .. crop}, '  ', tostring(def.cost), '金'},
            mouse_button_filter = {'left'}
        })
        btn.style.minimal_width = 96
    end

    -- 农田 table（8 列 × 5 行）
    local board = frame.add({
        type = 'table',
        name = GUI_BOARD,
        column_count = FARM_COLS
    })
    board.style.horizontal_spacing = 2
    board.style.vertical_spacing = 2
    board.style.top_padding = 4
    board.style.bottom_padding = 4

    for r = 1, FARM_ROWS do
        for c = 1, FARM_COLS do
            local btn = board.add({
                type = 'button',
                name = CELL_PREFIX .. r .. '_' .. c,
                caption = '',
                mouse_button_filter = {'left'}
            })
            btn.style.minimal_width = CELL_W
            btn.style.minimal_height = CELL_H
            btn.style.maximal_width = CELL_W
            btn.style.maximal_height = CELL_H
        end
    end

    -- 操作按钮：解锁农田 / 浇水
    local op_flow = frame.add({
        type = 'flow',
        name = GUI_OP_FLOW,
        direction = 'horizontal'
    })
    op_flow.style.top_padding = 4
    local unlock = op_flow.add({
        type = 'button',
        name = GUI_UNLOCK,
        caption = {'amap.farm_unlock_btn'},
        mouse_button_filter = {'left'}
    })
    unlock.style.minimal_width = 180
    local water = op_flow.add({
        type = 'button',
        name = GUI_WATER,
        caption = {'amap.farm_water_btn'},
        mouse_button_filter = {'left'}
    })
    water.style.minimal_width = 140

    -- 玩法提示
    local hint = frame.add({
        type = 'label',
        name = GUI_HINT,
        caption = {'amap.farm_hint'}
    })
    hint.style.font = 'default'
    hint.style.font_color = {0.7, 0.7, 0.7}
    hint.style.single_line = false
    hint.style.maximal_width = FARM_COLS * CELL_W + 40

    -- 初次绘制全部格子
    for idx = 1, #md.farmlands do
        refresh_cell(player, md, idx)
    end
    refresh_status(player, md)
end

local function destroy_main_gui(player)
    local screen = player.gui.screen
    if screen[GUI_FRAME] then
        screen[GUI_FRAME].destroy()
    end
end

--==============================================================================
-- 钩子实现
--==============================================================================

function M.on_surface_init(surface, player, data, difficulty_key)
    local diff = M.difficulty_settings[difficulty_key] or M.difficulty_settings.easy

    -- 1. 全图草地
    local tiles = {}
    for x = WALL_X_MIN - 1, WALL_X_MAX + 1 do
        for y = WALL_Y_MIN - 1, WALL_Y_MAX + 1 do
            tiles[#tiles + 1] = {name = 'grass-1', position = {x, y}}
        end
    end
    surface.set_tiles(tiles)

    -- 2. 农田色块（不同 tile 颜色块模拟田）：已解锁 dirt-5，未解锁 dirt-7
    local field_tiles = {}
    for r = 1, FARM_ROWS do
        for c = 1, FARM_COLS do
            local unlocked = cell_index(r, c) <= diff.initial_unlocked
            local tile_name = unlocked and 'dirt-5' or 'dirt-7'
            local x0 = PLOT_X0 + (c - 1) * PLOT_PITCH
            local y0 = PLOT_Y0 + (r - 1) * PLOT_PITCH
            for dx = 0, PLOT_SIZE - 1 do
                for dy = 0, PLOT_SIZE - 1 do
                    field_tiles[#field_tiles + 1] = {name = tile_name, position = {x0 + dx, y0 + dy}}
                end
            end
        end
    end
    surface.set_tiles(field_tiles)

    -- 3. 石墙围边（不可破坏/不可挖）
    for x = WALL_X_MIN, WALL_X_MAX do
        for _, y in ipairs({WALL_Y_MIN - 1, WALL_Y_MAX + 1}) do
            local wall = surface.create_entity({
                name = 'stone-wall', position = {x, y}, force = player.force
            })
            if wall then wall.minable_flag = false; wall.destructible = false end
        end
    end
    for y = WALL_Y_MIN - 1, WALL_Y_MAX + 1 do
        for _, x in ipairs({WALL_X_MIN - 1, WALL_X_MAX + 1}) do
            local wall = surface.create_entity({
                name = 'stone-wall', position = {x, y}, force = player.force
            })
            if wall then wall.minable_flag = false; wall.destructible = false end
        end
    end

    -- 玩家初始位置：不做 teleport（此时角色还在主世界 surface，
    -- 传送/切控制器由框架处理，避免把主世界角色挪位）

    -- 玩法私有状态（全放 data.module_data）
    local farmlands = {}
    for idx = 1, FARM_COLS * FARM_ROWS do
        farmlands[idx] = {
            unlocked = idx <= diff.initial_unlocked,
            crop = nil,              -- 当前作物类型（wheat/carrot/tomato/pumpkin），空则 nil
            plant_tick = 0,          -- 种植时的 game.tick
            grow_seconds = 0,        -- 作物生长秒数
            stage = 0,               -- 1 种子 / 2 幼苗 / 3 成株 / 4 成熟（0=空地）
            paused_ticks = 0,        -- 虫害暂停剩余 tick（>0 时生长暂停）
        }
    end

    data.module_data = {
        diff = diff,
        difficulty = difficulty_key,
        difficulty_label_key = diff.display_name_key,
        reward_multiplier = diff.reward_multiplier,
        farmlands = farmlands,
        next_locked_index = diff.initial_unlocked + 1,  -- 下一个待解锁格子（行优先）
        coins = 0,                  -- 当前金币（on_enter 初始化为 start_coins）
        income = 0,                 -- 累计收入（胜负判定用）
        selected_crop = nil,        -- 当前选中的种子
        watered_cell = nil,         -- 当前选中的生长中农田索引（用于浇水）
        gold_rain_pending = false,  -- 金雨待生效（下次收获 ×2 一次性）
        event_cycle = 0,            -- 随机事件周期计时（秒）
        end_tick = game.tick + diff.time_limit,
    }

    -- 框架超时上限 = 实际限时 + 3 秒宽限；实际限时一律用 md.diff.time_limit / md.end_tick
    data.time_limit = diff.time_limit + TIMEOUT_GRACE
    surface.always_day = true
    player.force.chart(surface, {
        {WALL_X_MIN - 2, WALL_Y_MIN - 2},
        {WALL_X_MAX + 2, WALL_Y_MAX + 2}
    })
end

function M.on_enter(player, data, difficulty_key)
    local md = data.module_data
    if not md then return end

    -- 初始化金币 / 累计收入
    md.coins = md.diff.start_coins
    md.income = 0
    -- 用框架的 start_tick 校准结束 tick（倒计时显示与 check_victory 一致，不含宽限）
    if data.start_tick then
        md.end_tick = data.start_tick + md.diff.time_limit
    end

    -- 隐藏框架的 coins label（模块自己管理金币 GUI）
    local top = player.gui.top
    if top['dungeon_coins'] then top['dungeon_coins'].destroy() end

    create_main_gui(player, data)

    player.print({
        'amap.farm_enter',
        md.diff.target_income,
        math.floor(md.diff.time_limit / 60)
    }, {r = 0, g = 1, b = 0})
    player.print({'amap.farm_hint'}, {r = 1, g = 1, b = 0})
end

function M.on_exit(player, data, reason)
    destroy_main_gui(player)

    -- 通关/失败消息
    if data.victory_state == 'victory' then
        player.print({'amap.farm_victory_msg'}, {r = 0, g = 1, b = 0})
    elseif data.victory_state == 'defeat' then
        player.print({'amap.farm_defeat_msg'}, {r = 1, g = 0.3, b = 0.3})
    end
end

function M.on_tick(player, data)
    local md = data.module_data
    if not md then return end

    -- 每 tick（1 秒，框架每 60 tick 调用一次）：推进各农田生长
    local changed = {}
    for idx, cell in ipairs(md.farmlands) do
        if cell.crop and cell.stage < 4 then
            if cell.paused_ticks > 0 then
                -- 虫害暂停：不推进生长（plant_tick 同步前移保持 elapsed 不变）
                cell.paused_ticks = cell.paused_ticks - 1
                cell.plant_tick = cell.plant_tick + 60
            else
                local stage = calc_stage(cell, game.tick - cell.plant_tick)
                if stage ~= cell.stage then
                    cell.stage = stage
                    changed[#changed + 1] = idx
                end
            end
        end
    end

    -- 随机事件（每 30 秒 15% 概率）
    md.event_cycle = md.event_cycle + 1
    if md.event_cycle >= EVENT_INTERVAL then
        md.event_cycle = 0
        if math.random() < EVENT_CHANCE then
            if math.random(2) == 1 then
                -- 金雨：下次收获 ×2（一次性）
                md.gold_rain_pending = true
                player.print({'amap.farm_gold_rain'}, {r = 1, g = 0.85, b = 0})
            else
                -- 虫害：随机一块生长中（未成熟）农田暂停 5 秒
                local growing = {}
                for idx, cell in ipairs(md.farmlands) do
                    if cell.crop and cell.stage < 4 then
                        growing[#growing + 1] = idx
                    end
                end
                if #growing > 0 then
                    local idx = growing[math.random(#growing)]
                    local cell = md.farmlands[idx]
                    cell.paused_ticks = PEST_PAUSE_SECONDS * 60
                    local pos = cell_pos(idx)
                    player.print({
                        'amap.farm_pest', pos.row, pos.col
                    }, {r = 1, g = 0.4, b = 0.4})
                end
            end
        end
    end

    -- 重绘仅改变化格 + 刷新状态栏
    for _, idx in ipairs(changed) do
        refresh_cell(player, md, idx)
    end
    refresh_status(player, md)
end

function M.check_victory(player, data)
    local md = data.module_data
    if not md then return nil end

    -- 1. 达标即胜：收入达到目标立即结算（优先于限时判定）
    if md.income >= md.diff.target_income then
        -- 奖励系数固定 1.0（2026-08-10 用户决策）
        Instance.set_reward_multiplier(player, 1.0)
        return 'victory'
    end

    -- 2. 实际限时到（不含宽限）且未达标 → 失败
    if game.tick - data.start_tick >= md.diff.time_limit then
        return 'defeat'
    end

    -- 3. 进行中
    return nil
end

function M.on_gui_click(player, event)
    local element = event.element
    if not element or not element.valid then return end

    local data = Instance.get_data(player.index)
    if not data or not data.active then return end
    local md = data.module_data
    if not md then return end

    local name = element.name
    if not name then return end

    -- 1. 种子购买按钮 dungeon_module_farm_seed_<crop>：点击选中种子态（再点取消）
    local crop = name:match('^' .. SEED_PREFIX .. '(%w+)$')
    if crop then
        if md.selected_crop == crop then
            md.selected_crop = nil
        else
            md.selected_crop = crop
            player.print({'amap.farm_seed_selected', {'amap.farm_crop_' .. crop}}, {r = 1, g = 0.85, b = 0})
        end
        return
    end

    -- 2. 农田格 dungeon_module_farm_cell_<row>_<col>
    local row, col = name:match('^' .. CELL_PREFIX .. '(%d+)_(%d+)$')
    if row and col then
        local idx = cell_index(tonumber(row), tonumber(col))
        local cell = md.farmlands[idx]
        if not cell then return end

        if not cell.unlocked then
            player.print({'amap.farm_cell_locked'}, {r = 1, g = 0.5, b = 0})
            return
        end

        if not cell.crop then
            -- 空地 + 种子选中 → 种植（扣成本）
            if not md.selected_crop then
                player.print({'amap.farm_no_crop_selected'}, {r = 1, g = 0.5, b = 0})
                return
            end
            local crop_def = CROPS[md.selected_crop]
            if not crop_def then return end
            if md.coins < crop_def.cost then
                player.print({'amap.farm_not_enough_coins'}, {r = 1, g = 0.3, b = 0.3})
                return
            end
            md.coins = md.coins - crop_def.cost
            cell.crop = md.selected_crop
            cell.plant_tick = game.tick
            cell.grow_seconds = crop_def.grow
            cell.stage = 1
            cell.paused_ticks = 0
            md.watered_cell = nil
            player.print({'amap.farm_planted', {'amap.farm_crop_' .. cell.crop}}, {r = 0.4, g = 1, b = 0.4})
        elseif cell.stage >= 4 then
            -- 成熟 → 收获计收入（金雨 ×2 一次性）
            local crop_def = CROPS[cell.crop]
            local gain = crop_def.price
            local double = md.gold_rain_pending
            if double then
                gain = gain * 2
                md.gold_rain_pending = false
            end
            md.income = md.income + gain
            md.coins = md.coins + gain
            local crop_name = {'amap.farm_crop_' .. cell.crop}
            if double then
                player.print({'amap.farm_gold_rain_harvest', crop_name, gain}, {r = 1, g = 0.85, b = 0})
            else
                player.print({'amap.farm_harvested', crop_name, gain}, {r = 0.4, g = 1, b = 0.4})
            end
            cell.crop = nil
            cell.plant_tick = 0
            cell.grow_seconds = 0
            cell.stage = 0
            cell.paused_ticks = 0
            if md.watered_cell == idx then md.watered_cell = nil end
        else
            -- 生长中 → 选中用于浇水（再点取消）
            if md.watered_cell == idx then
                md.watered_cell = nil
            else
                md.watered_cell = idx
            end
        end

        refresh_cell(player, md, idx)
        refresh_status(player, md)
        return
    end

    -- 3. 解锁按钮 dungeon_module_farm_unlock：花 25 金币解锁下一块（行优先）
    if name == GUI_UNLOCK then
        if md.next_locked_index > #md.farmlands then
            player.print({'amap.farm_unlock_no_more'}, {r = 1, g = 0.5, b = 0})
            return
        end
        if md.coins < UNLOCK_PRICE then
            player.print({'amap.farm_not_enough_coins'}, {r = 1, g = 0.3, b = 0.3})
            return
        end
        md.coins = md.coins - UNLOCK_PRICE
        local idx = md.next_locked_index
        md.farmlands[idx].unlocked = true
        md.next_locked_index = idx + 1
        refresh_cell(player, md, idx)
        refresh_status(player, md)
        player.print({'amap.farm_unlock_done', idx}, {r = 0.4, g = 1, b = 0.4})
        return
    end

    -- 4. 浇水按钮 dungeon_module_farm_water：花 2 金币，选中田剩余时间 -25%
    if name == GUI_WATER then
        if not md.watered_cell then
            player.print({'amap.farm_water_no_cell'}, {r = 1, g = 0.5, b = 0})
            return
        end
        local cell = md.farmlands[md.watered_cell]
        if not cell or not cell.crop or cell.stage >= 4 then
            md.watered_cell = nil
            player.print({'amap.farm_water_no_cell'}, {r = 1, g = 0.5, b = 0})
            return
        end
        if md.coins < WATER_PRICE then
            player.print({'amap.farm_not_enough_coins'}, {r = 1, g = 0.3, b = 0.3})
            return
        end
        md.coins = md.coins - WATER_PRICE
        -- 剩余时间 -25%：等价于把 plant_tick 前移剩余时间的 25%
        local elapsed = game.tick - cell.plant_tick
        local remaining = cell.grow_seconds * 60 - elapsed
        if remaining > 0 then
            cell.plant_tick = cell.plant_tick - math.floor(remaining * WATER_REDUCE)
        end
        local idx = md.watered_cell
        local stage = calc_stage(cell, game.tick - cell.plant_tick)
        if stage ~= cell.stage then cell.stage = stage end
        md.watered_cell = nil
        refresh_cell(player, md, idx)
        refresh_status(player, md)
        player.print({'amap.farm_water_done'}, {r = 0.4, g = 1, b = 0.4})
        return
    end
end

--==============================================================================
-- 注册到框架
--==============================================================================

Instance.register(M.type, M)
return M
