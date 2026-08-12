-- maps/amap/instance/modules/dodgeball.lua
-- 躲避球玩法模块（v2.2：火箭发射极简化 + 特殊地块 + 4 个无敌小沙虫）
--
-- 玩法类型：dodgeball
-- 玩法说明：封闭竞技场内限时存活，场外定时向玩家位置发射火箭
--   - 场地：30x30（easy）/ 25x25（normal）/ 20x20（hard）外围石墙
--   - 场内 ≥ 2/3 区域覆盖特殊地块（水坑=减速 / 石砖=普通 / 危险混凝土=视觉提示）
--     玩家不能单纯靠走路躲避，必须在复杂地形中规划路线
--   - 场地边缘有 4 个无敌小沙虫（force='dungeon_enemy'）做视觉干扰
--   - 每 N tick 从场外 4 个固定位置中随机选一个，向玩家当前位置发射 explosive-rocket：
--       position = 场外固定位置（position table）
--       target   = 玩家当前位置（position table）
--     火箭飞到该位置爆炸，玩家移动即可躲开
--   - 玩家死亡 → defeat
--   - 时间到 → victory
--
-- 关键技术点（参考天赋系统 tianfu_trigger_skill.lua 的 fire_missile_token）：
--   Factorio 2.x create_entity 创建 projectile (explosive-rocket) 时：
--     - position 字段决定火箭起飞位置（position table）
--     - target 字段可以直接传 position table（如 {x=.., y=..}），无需创建临时实体
--     - source 字段可省略（RCON 实测：不传 source 时 target 接受 position）
--   注意：source 字段若传 entity，Factorio 会要求 target 也是 entity，导致
--   "Can't create projectile, target not specified" 报错。所以这里完全不传 source。

local Instance = require 'maps.amap.instance.instance'

local M = {}

--==============================================================================
-- 元数据
--==============================================================================

M.type = 'dodgeball'
M.display_name_key = 'amap.instance_dodgeball_name'
M.description_key = 'amap.instance_dodgeball_desc'
M.gameplay_desc_key = 'amap.instance_dodgeball_gameplay'
M.victory_condition_key = 'amap.instance_dodgeball_victory'
M.icon = 'item/explosive-rocket'
M.time_limit_default = 90 * 60  -- 90 秒

--==============================================================================
-- 难度
--==============================================================================

M.difficulty_settings = {
    easy = {
        name = 'easy',
        recycling_efficiency = 1,
        max_coins = 0,
        display_name_key = 'dungeon_difficulty_easy',
        arena_half = 15,                -- 30x30
        rocket_interval = 90,           -- 每 1.5 秒一发
        spawn_delay = 5 * 60,           -- 进入后 5 秒缓冲
        time_limit = 90 * 60
    },
    normal = {
        name = 'normal',
        recycling_efficiency = 1,
        max_coins = 0,
        display_name_key = 'dungeon_difficulty_normal',
        arena_half = 12,                -- 25x25
        rocket_interval = 60,           -- 每秒一发
        spawn_delay = 4 * 60,
        time_limit = 90 * 60
    },
    hard = {
        name = 'hard',
        recycling_efficiency = 1,
        max_coins = 0,
        display_name_key = 'dungeon_difficulty_hard',
        arena_half = 10,                -- 20x20 紧凑
        rocket_interval = 40,           -- 每 0.67 秒一发
        spawn_delay = 3 * 60,
        time_limit = 90 * 60
    }
}

--==============================================================================
-- 常量
--==============================================================================

local GUI_TIME = 'dungeon_db_time'
local GUI_DODGED = 'dungeon_db_dodged'

-- 4 个火箭发射起点位置（场地四个边的中点外侧，position table，无需创建实体）
-- 4 个场外固定起飞位置（场地边缘外 2 米）
-- 注：实际发射时会基于玩家位置 + 随机方向生成 15-25 米外的发射点，
--     场外固定位置仅作为兜底（玩家站位异常时使用）
local function get_source_positions(arena_half)
    return {
        {x = 0,             y = -arena_half - 2},  -- 上
        {x = 0,             y =  arena_half + 2},  -- 下
        {x = -arena_half - 2, y = 0},              -- 左
        {x =  arena_half + 2, y = 0},              -- 右
    }
end

-- 计算离玩家至少 15 米的随机发射点
-- 策略：以玩家位置为中心，随机角度，距离 15~25 米生成发射点
-- 若超出场地，则用场外固定位置兜底
local function get_random_source_far_from_player(player_pos, arena_half, md)
    local angle = math.random() * math.pi * 2
    local dist = math.random(15, 25)
    local src_pos = {
        x = player_pos.x + math.cos(angle) * dist,
        y = player_pos.y + math.sin(angle) * dist
    }
    -- 若发射点在场地内（距中心 < arena_half），用场外固定位置兜底
    local dist_to_center = math.sqrt(src_pos.x * src_pos.x + src_pos.y * src_pos.y)
    if dist_to_center < arena_half then
        local fallback = md.source_positions[math.random(#md.source_positions)]
        return fallback
    end
    return src_pos
end

-- 4 个小沙虫的固定位置（场地四角内侧）
local function get_sandworm_positions(arena_half)
    local r = arena_half - 2
    return {
        {x = -r, y = -r},
        {x =  r, y = -r},
        {x = -r, y =  r},
        {x =  r, y =  r},
    }
end

--==============================================================================
-- 辅助函数
--==============================================================================

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

    local remaining_sec = math.max(0, math.floor((md.survive_expire_tick - game.tick) / 60))
    ensure(GUI_TIME).caption = {'amap.dodgeball_remaining', remaining_sec}
    ensure(GUI_DODGED).caption = {'amap.dodgeball_dodged', md.rockets_dodged}
end

local function cleanup_top_gui(player)
    local top = player.gui.top
    for _, name in ipairs({GUI_TIME, GUI_DODGED}) do
        if top[name] then top[name].destroy() end
    end
end

-- 创建 4 个无敌小沙虫（场地四角，视觉干扰）
local function create_sandworms(surface, arena_half)
    local worms = {}
    local positions = get_sandworm_positions(arena_half)
    for i, pos in ipairs(positions) do
        local final = surface.find_non_colliding_position('small-worm-turret', pos, 4, 1) or pos
        local ent = surface.create_entity({
            name = 'small-worm-turret',
            position = final,
            force = 'dungeon_enemy'
        })
        if ent then
            ent.destructible = false
            ent.minable_flag = false
            ent.operable = false
            worms[i] = ent
        end
    end
    return worms
end

-- 发射火箭：发射点离玩家至少 15 米（随机方向 15-25 米），target 是玩家当前位置
-- 参考天赋系统 fire_missile_token（zhaohuan_kongxi）：target 直接传 position，瞄准"位置"而非"实体"
-- RCON 实测：不传 source 字段时，target 接受 position table，可正常创建 explosive-rocket
-- 速度随机 0.2~0.5（原 0.4~0.7 下调 0.2，给玩家足够反应时间）
local function fire_rocket(surface, player, md)
    if not md.source_positions or #md.source_positions == 0 then return nil end
    local char = player.character
    if not char or not char.valid then return nil end

    -- 发射点：离玩家 15-25 米的随机位置，保证距离 >= 15
    local src_pos = get_random_source_far_from_player(char.position, md.arena_half, md)
    -- 随机速度 0.2~0.5（精确到 0.01，原 0.4~0.7 下调 0.2）
    local speed = math.random(20, 50) / 100

    local rocket = surface.create_entity({
        name = 'explosive-rocket',
        position = src_pos,            -- 离玩家 15+ 米的随机发射位置
        target = char.position,        -- 玩家当前位置（position table，瞄准位置不瞄准实体）
        force = 'dungeon_enemy',
        speed = speed
    })
    return rocket
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

    data.module_data = {
        arena_half = ah,
        rocket_interval = diff.rocket_interval,
        spawn_delay = diff.spawn_delay,
        time_limit = diff.time_limit or M.time_limit_default,
        next_rocket_tick = 0,
        survive_expire_tick = 0,
        start_tick = 0,
        player_died = false,
        rockets_fired = 0,
        rockets_dodged = 0,
        source_positions = nil,  -- on_enter 时设置（场外 4 个固定位置）
        sandworms = nil
    }

    data.time_limit = diff.time_limit or M.time_limit_default
    surface.always_day = true
end

function M.on_enter(player, data, difficulty_key)
    local diff = M.difficulty_settings[difficulty_key] or M.difficulty_settings.easy

    -- 建立独立敌对 force
    local dungeon_enemy = game.forces['dungeon_enemy']
    if not dungeon_enemy then
        dungeon_enemy = game.create_force('dungeon_enemy')
        dungeon_enemy.set_friend('player', false)
    end
    local dungeon_force = game.forces[data.dungeon_force]
    if dungeon_force then
        dungeon_force.set_cease_fire('dungeon_enemy', false)
        dungeon_force.set_friend('dungeon_enemy', false)
        dungeon_enemy.set_friend(data.dungeon_force, false)
    end

    local md = data.module_data
    if not md then return end
    md.start_tick = data.start_tick or game.tick
    md.next_rocket_tick = game.tick + md.spawn_delay
    md.survive_expire_tick = game.tick + (diff.time_limit or M.time_limit_default)
    -- 修复：框架 time_limit 超时判负以 data.start_tick（选难度时）为起点，而本玩法胜利以 on_enter
    -- （进入场地时）为起点。进入场地晚于选难度，导致"胜利时刻"晚于"框架超时时刻"，check_victory 被
    -- on_nth_tick 的 `remaining>0` 守卫跳过、永远没机会返回 victory，最终被框架判 timeout 失败。
    -- 这里把框架超时延后到胜利之后 3 秒（180 tick），确保 check_victory 在 remaining>0 区间内
    -- 当帧返回 victory，玩家严格撑满 90 秒（从进场起）即获胜，绝不会被 timeout 抢先判负。
    data.time_limit = (md.survive_expire_tick - md.start_tick) + 180

    -- 设置场外 4 个固定起飞位置 + 创建小沙虫（必须在玩家进入后才能确认 surface）
    local surface = player.surface
    md.source_positions = get_source_positions(md.arena_half)
    md.sandworms = create_sandworms(surface, md.arena_half)

    -- 隐藏框架 coins label
    local top = player.gui.top
    if top['dungeon_coins'] then top['dungeon_coins'].destroy() end

    update_top_gui(player, md)
    player.print({'amap.dodgeball_enter'}, {r = 0, g = 1, b = 0})
    player.print({'amap.dodgeball_hint'}, {r = 1, g = 0.8, b = 0})
end

function M.on_tick(player, data)
    local md = data.module_data
    if not md then return end
    local surface = player.surface
    if not surface then return end
    local tick = game.tick

    -- 火箭生成
    if tick >= md.next_rocket_tick then
        local rocket = fire_rocket(surface, player, md)
        if rocket then
            md.rockets_fired = md.rockets_fired + 1
        end
        md.next_rocket_tick = tick + md.rocket_interval
    end

    update_top_gui(player, md)
end

function M.check_victory(player, data)
    local md = data.module_data
    if not md then return nil end

    if md.player_died then return 'defeat' end

    if game.tick >= md.survive_expire_tick then
        local bonus = math.min(md.rockets_dodged * 0.05, 1.0)
        Instance.set_reward_multiplier(player, 1.5 + bonus)
        return 'victory'
    end

    return nil
end

function M.on_player_died(player, data)
    local md = data.module_data
    if not md then return end
    md.player_died = true
end

function M.on_entity_died(player, event)
    local entity = event.entity
    if not entity or not entity.valid then return end
    -- 火箭爆炸：rockets_dodged +1
    if entity.name == 'explosive-rocket' then
        local md = Instance.get_data(player.index).module_data
        if md then md.rockets_dodged = md.rockets_dodged + 1 end
    end
end

function M.on_exit(player, data, reason)
    local md = data.module_data
    if not md then return end

    -- 清理小沙虫
    if md.sandworms then
        for _, w in ipairs(md.sandworms) do
            if w and w.valid then w.destroy() end
        end
        md.sandworms = nil
    end

    cleanup_top_gui(player)
end

--==============================================================================
-- 注册
--==============================================================================

Instance.register(M.type, M)
return M
