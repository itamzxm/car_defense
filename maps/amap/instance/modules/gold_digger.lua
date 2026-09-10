-- maps/amap/instance/modules/gold_digger.lua
-- 黄金矿工玩法模块（v2.0：寻宝玩法）
--
-- 玩法类型：gold_digger
-- 玩法说明：限时挖矿寻宝
--   - 场地：30x30（easy）/ 25x25（normal）/ 20x20（hard）外围石墙
--   - 场内散布大量普通岩石（干扰物）
--   - 在场内随机位置埋藏 4 个宝藏坐标：1 真 + 3 假
--   - 玩家挖普通岩石：根据距离最近宝藏（真+假）发出距离提示：
--       < 2 格："我觉得他就在我旁边"  (very_close)
--       < 4 格："我感觉我离他很近"   (close)
--       < 7 格："这附近好像有好东西" (near)
--       >= 7 格："这看起来什么也没有" (far)
--   - 玩家挖到宝藏位置的岩石：
--       真宝藏 → 胜利
--       假宝藏 → 飞字"这只是个空箱子"，假宝藏作废，玩家继续找
--   - 屏蔽主世界事件：只在副本 surface 上处理挖掘事件
--   - 超时 → 失败
--
-- 钩子：
--   on_surface_init - 生成地形 + 围墙 + 散布岩石 + 埋藏 4 个宝藏坐标
--   on_enter        - 提示玩法 + 创建顶栏 GUI
--   on_exit         - 清理 GUI + 恢复挖掘速度
--   on_tick         - 更新顶栏 GUI
--   check_victory   - 找到真宝藏 → 胜利；超时由框架判 defeat
--   on_pre_player_mined_item - 挖岩石判定（距离提示 / 宝藏触发）

local Instance = require 'maps.amap.instance.instance'

local M = {}

--==============================================================================
-- 元数据
--==============================================================================

M.type = 'gold_digger'
M.display_name_key = 'amap.instance_gold_digger_name'
M.description_key = 'amap.instance_gold_digger_desc'
M.gameplay_desc_key = 'amap.instance_gold_digger_gameplay'
M.victory_condition_key = 'amap.instance_gold_digger_victory'
M.icon = 'item/coin'
M.time_limit_default = 5 * 60 * 60  -- 5 分钟

--==============================================================================
-- 难度
--==============================================================================

M.difficulty_settings = {
    easy = {
        name = 'easy',
        recycling_efficiency = 1,
        max_coins = 0,
        display_name_key = 'dungeon_difficulty_easy',
        arena_half = 22,            -- 44x44（原 15 → 22，扩大 1.5x）
        rock_count = 300,           -- 大量密集岩石
        fake_count = 3,             -- 3 个假宝藏
        time_limit = 5 * 60 * 60
    },
    normal = {
        name = 'normal',
        recycling_efficiency = 1,
        max_coins = 0,
        display_name_key = 'dungeon_difficulty_normal',
        arena_half = 24,            -- 48x48
        rock_count = 420,
        fake_count = 5,
        time_limit = 5 * 60 * 60
    },
    hard = {
        name = 'hard',
        recycling_efficiency = 1,
        max_coins = 0,
        display_name_key = 'dungeon_difficulty_hard',
        arena_half = 26,            -- 52x52
        rock_count = 550,
        fake_count = 7,
        time_limit = 5 * 60 * 60
    }
}

--==============================================================================
-- 常量
--==============================================================================

-- 岩石原型
local ROCK_TYPES = {'big-rock', 'huge-rock', 'big-sand-rock'}

-- 距离提示阈值（格）
local DIST_VERY_CLOSE = 2
local DIST_CLOSE = 4
local DIST_NEAR = 7

-- 顶栏 GUI
local GUI_HINT = 'dungeon_gd_hint'
local GUI_TIME = 'dungeon_gd_time'

--==============================================================================
-- 辅助函数
--==============================================================================

-- 散布岩石：避开中心 3x3 出生区，密集分布
-- 用 find_non_colliding_position 提高放置成功率，max_attempts 设大保证达到目标数量
local function place_rocks(surface, arena_half, count)
    local placed = 0
    local max_attempts = count * 30
    for _ = 1, max_attempts do
        if placed >= count then break end
        local x = math.random(-arena_half + 2, arena_half - 2)
        local y = math.random(-arena_half + 2, arena_half - 2)
        if math.abs(x) <= 1 and math.abs(y) <= 1 then goto continue end
        local rock_type = ROCK_TYPES[math.random(#ROCK_TYPES)]
        local pos = surface.find_non_colliding_position(rock_type, {x, y}, 4, 1)
        if not pos then goto continue end
        local ent = surface.create_entity({
            name = rock_type,
            position = pos,
            force = 'neutral'
        })
        if ent then placed = placed + 1 end
        ::continue::
    end
    return placed
end

-- 埋藏宝藏坐标：1 真 + N 假，避开中心出生区和岩石过近
-- 关键：宝藏坐标上强制生成一块岩石，保证玩家一定能挖到
local function bury_treasures(surface, arena_half, fake_count)
    local treasures = {}
    local min_pos = -arena_half + 3
    local max_pos = arena_half - 3

    local function random_pos()
        return {
            x = math.random(min_pos, max_pos),
            y = math.random(min_pos, max_pos)
        }
    end

    -- 在坐标上强制生成岩石，并把宝藏 pos 设为岩石实际 position
    local function place_treasure_rock(p)
        local rock_type = ROCK_TYPES[math.random(#ROCK_TYPES)]
        local ent = surface.create_entity({
            name = rock_type,
            position = p,
            force = 'neutral'
        })
        if ent then
            return {x = ent.position.x, y = ent.position.y}
        end
        return p  -- 极端情况下实体创建失败，退回原始坐标
    end

    -- 真宝藏
    local p = random_pos()
    local real_pos = place_treasure_rock(p)
    treasures[1] = {pos = real_pos, is_real = true, found = false}

    -- 假宝藏
    for i = 1, fake_count do
        -- 假宝藏之间互相距离 >= 4 格
        local p
        for _ = 1, 50 do
            p = random_pos()
            local ok = true
            for _, t in ipairs(treasures) do
                local dx = p.x - t.pos.x
                local dy = p.y - t.pos.y
                if dx * dx + dy * dy < 16 then ok = false break end
            end
            if ok then break end
        end
        local fake_pos = place_treasure_rock(p)
        treasures[#treasures + 1] = {pos = fake_pos, is_real = false, found = false}
    end

    return treasures
end

-- 计算位置到最近未找到宝藏的距离
local function distance_to_nearest_treasure(pos, treasures)
    local min_dist_sq = 999999
    for _, t in ipairs(treasures) do
        if not t.found then
            local dx = pos.x - t.pos.x
            local dy = pos.y - t.pos.y
            local d_sq = dx * dx + dy * dy
            if d_sq < min_dist_sq then
                min_dist_sq = d_sq
            end
        end
    end
    return math.sqrt(min_dist_sq)
end

-- 距离提示分级
local function get_hint_key(dist)
    if dist < DIST_VERY_CLOSE then return 'amap.gold_digger_hint_very_close'
    elseif dist < DIST_CLOSE then return 'amap.gold_digger_hint_close'
    elseif dist < DIST_NEAR then return 'amap.gold_digger_hint_near'
    else return 'amap.gold_digger_hint_far'
    end
end

-- 顶栏 GUI
local function update_top_gui(player, md)
    local top = player.gui.top
    local function ensure(name)
        local lbl = top[name]
        if not lbl then
            lbl = top.add({type = 'label', name = name, caption = ''})
        end
        return lbl
    end

    local remaining_sec = math.max(0, math.floor((md.end_tick - game.tick) / 60))
    local min = math.floor(remaining_sec / 60)
    local sec = remaining_sec % 60
    ensure(GUI_TIME).caption = {'amap.gold_digger_time', min, sec}

    local found_count = 0
    local total_fake = 0
    for _, t in ipairs(md.treasures) do
        if t.found then
            found_count = found_count + 1
            if not t.is_real then total_fake = total_fake + 1 end
        end
    end
    ensure(GUI_HINT).caption = {'amap.gold_digger_status', total_fake, #md.treasures - 1}
end

local function cleanup_top_gui(player)
    local top = player.gui.top
    for _, name in ipairs({GUI_HINT, GUI_TIME}) do
        if top[name] then top[name].destroy() end
    end
end

--==============================================================================
-- 钩子
--==============================================================================

function M.on_surface_init(surface, player, data, difficulty_key)
    local diff = M.difficulty_settings[difficulty_key] or M.difficulty_settings.easy
    local ah = diff.arena_half

    -- 全图草地
    local tiles = {}
    for x = -ah - 1, ah + 1 do
        for y = -ah - 1, ah + 1 do
            tiles[#tiles + 1] = {name = 'grass-1', position = {x, y}}
        end
    end
    surface.set_tiles(tiles)

    -- 外围不可破坏石墙
    for x = -ah, ah do
        for _, y_offs in ipairs({-ah - 1, ah + 1}) do
            local wall = surface.create_entity({
                name = 'stone-wall', position = {x, y_offs},
                force = player.force, move_stuck_players = true
            })
            if wall then wall.destructible = false; wall.minable_flag = false end
        end
    end
    for y = -ah - 1, ah + 1 do
        for _, x_offs in ipairs({-ah - 1, ah + 1}) do
            local wall = surface.create_entity({
                name = 'stone-wall', position = {x_offs, y},
                force = player.force, move_stuck_players = true
            })
            if wall then wall.destructible = false; wall.minable_flag = false end
        end
    end

    -- 中心出生区
    for x = -1, 1 do
        for y = -1, 1 do
            surface.set_tiles({{name = 'hazard-concrete-left', position = {x, y}}})
        end
    end

    -- 散布岩石
    place_rocks(surface, ah, diff.rock_count)

    -- 埋藏宝藏（在坐标上强制生成岩石）
    local treasures = bury_treasures(surface, ah, diff.fake_count)

    data.module_data = {
        arena_half = ah,
        treasures = treasures,
        end_tick = 0,
        start_tick = 0,
        victory = false,
        finished = false
    }

    data.time_limit = diff.time_limit or M.time_limit_default
    surface.always_day = true
end

function M.on_enter(player, data, difficulty_key)
    local diff = M.difficulty_settings[difficulty_key] or M.difficulty_settings.easy
    local md = data.module_data
    if not md then return end

    -- 提升挖矿速度（rock mining_time 较长）
    player.force.manual_mining_speed_modifier = 5

    md.start_tick = game.tick
    md.end_tick = game.tick + (diff.time_limit or M.time_limit_default)

    -- 隐藏框架 coins label
    local top = player.gui.top
    if top['dungeon_coins'] then top['dungeon_coins'].destroy() end

    update_top_gui(player, md)
    player.print({'amap.gold_digger_enter'}, {r = 0, g = 1, b = 0})
    player.print({'amap.gold_digger_hint_intro'}, {r = 1, g = 0.8, b = 0})
end

function M.on_tick(player, data)
    local md = data.module_data
    if not md or md.finished then return end

    -- 超时
    if game.tick >= md.end_tick then
        md.finished = true
        md.victory = false
        return
    end

    update_top_gui(player, md)
end

function M.check_victory(player, data)
    local md = data.module_data
    if not md then return nil end

    if md.finished then
        if md.victory then
            -- 奖励系数固定 1.0（2026-08-10 用户决策）
            Instance.set_reward_multiplier(player, 1.0)
            return 'victory'
        else
            return 'defeat'
        end
    end

    return nil
end

-- on_pre_player_mined_item：挖岩石判定
-- 关键：严格 surface 判断，避免污染主世界
-- 关键：清空 event.buffer 屏蔽主世界产物（铁矿石、煤矿等），副本里挖岩石不得产出任何物品
function M.on_pre_player_mined_item(player, event)
    local entity = event.entity
    if not entity or not entity.valid then return end
    local name = entity.name
    if name ~= 'big-rock' and name ~= 'huge-rock' and name ~= 'big-sand-rock' then return end

    -- 关键：必须确认玩家在副本中 + 实体在副本 surface 上
    local data = Instance.get_data(player.index)
    if not data or not data.active then return end
    -- 双重校验：实体 surface 必须是玩家的 surface
    if entity.surface ~= player.surface then return end
    local md = data.module_data
    if not md then return end

    -- 屏蔽主世界产物：清空 buffer，玩家不会获得石头/铁矿/煤矿等任何掉落物
    -- 副本内挖岩石只为寻宝，不应有产物
    if event.buffer and event.buffer.valid then
        event.buffer.clear()
    end

    local pos = entity.position

    -- 检查是否挖到宝藏位置（距离 < 1.5 格）
    local hit_treasure = nil
    for _, t in ipairs(md.treasures) do
        if not t.found then
            local dx = pos.x - t.pos.x
            local dy = pos.y - t.pos.y
            if dx * dx + dy * dy < 2.25 then  -- 1.5 格
                hit_treasure = t
                break
            end
        end
    end

    if hit_treasure then
        -- 挖到宝藏
        hit_treasure.found = true
        if hit_treasure.is_real then
            -- 真宝藏 → 胜利
            md.finished = true
            md.victory = true
            player.create_local_flying_text({
                text = {'amap.gold_digger_found_real'},
                position = pos,
                color = {1, 0.85, 0.2}
            })
            player.play_sound({path = 'utility/achievement_unlocked', volume_modifier = 0.8})
        else
            -- 假宝藏 → 飞字提示，继续找
            player.create_local_flying_text({
                text = {'amap.gold_digger_found_fake'},
                position = pos,
                color = {0.6, 0.6, 0.6}
            })
            player.play_sound({path = 'utility/cannot_build', volume_modifier = 0.6})
        end
        return
    end

    -- 没挖到宝藏：距离提示
    local dist = distance_to_nearest_treasure(pos, md.treasures)
    local hint_key = get_hint_key(dist)
    player.create_local_flying_text({
        text = {hint_key},
        position = pos,
        color = {0.9, 0.8, 0.4}
    })
end

function M.on_exit(player, data, reason)
    local md = data.module_data
    if not md then return end

    -- 恢复挖矿速度（避免污染主世界）
    if player.force then
        player.force.manual_mining_speed_modifier = 0
    end

    cleanup_top_gui(player)
end

--==============================================================================
-- 注册
--==============================================================================

Instance.register(M.type, M)
return M
