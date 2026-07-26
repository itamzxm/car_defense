-- maps/amap/instance/modules/boss_hunt.lua
-- Boss 讨伐玩法模块（v2.0：场地变大 + 障碍物 + 道具系统，参考 arena_survival）
--
-- 玩法类型：boss_hunt
-- 玩法说明：闭竞技场内击杀单一强力 Boss
--   - 场地：30x30（easy）/ 24x24（normal）/ 20x20（hard）外围石墙
--   - 场内散布障碍物（big-rock 等）做掩体
--   - Boss 统一 big-biter，速度 0.3
--   - 每 12 秒随机刷新一个道具（5 种全齐）
--   - normal/hard：Boss 定时召唤 2 只 small-biter/spitter
--   - 难度设计：每次只改 2 条——场地 + 小虫召唤间隔
--   - Boss 死亡 → victory；玩家死亡 → defeat；超时 → defeat

local Instance = require 'maps.amap.instance.instance'

local M = {}

--==============================================================================
-- 元数据
--==============================================================================

M.type = 'boss_hunt'
M.display_name_key = 'amap.instance_boss_hunt_name'
M.description_key = 'amap.instance_boss_hunt_desc'
M.gameplay_desc_key = 'amap.instance_boss_hunt_gameplay'
M.victory_condition_key = 'amap.instance_boss_hunt_victory'
M.icon = 'entity/behemoth-biter'
M.time_limit_default = 5 * 60 * 60  -- 5 分钟

--==============================================================================
-- 难度设置（v2.1：统一 Boss / 统一参数，每次升级只改 2 条）
-- 设计哲学：easy(1.0) → normal(1.2) → hard(1.44)，逐级 20% 增量
-- 每次难度提升只改 2 个维度：场地大小 + 小虫召唤间隔
-- Boss 统一 big-biter，速度 0.3；弹药/道具/掩体全难度一致
--==============================================================================

M.difficulty_settings = {
    easy = {
        name = 'easy',
        recycling_efficiency = 1,
        max_coins = 0,
        display_name_key = 'dungeon_difficulty_easy',
        arena_half = 15,                -- 30×30 大场地，走位充裕
        boss_type = 'big-biter',        -- 三难度统一
        boss_speed = 0.30,              -- 适度速度
        weapon = 'shotgun',
        weapon_ammo = 'shotgun-shell',
        ammo_count = 50,                -- 统一弹药
        obstacle_count = 12,            -- 统一掩体
        powerup_interval = 12 * 60,     -- 统一 12s
        powerup_types = {'ammo', 'speed', 'shield', 'heal', 'rage'},
        add_interval = 0,               -- 简单不召小虫
        add_count = 0,
        add_types = {},
        time_limit = 5 * 60 * 60
    },
    normal = {
        name = 'normal',
        recycling_efficiency = 1,
        max_coins = 0,
        display_name_key = 'dungeon_difficulty_normal',
        arena_half = 12,                -- 24×24，场地缩小 ← 改动 1
        boss_type = 'big-biter',
        boss_speed = 0.30,
        weapon = 'shotgun',
        weapon_ammo = 'shotgun-shell',
        ammo_count = 50,
        obstacle_count = 12,
        powerup_interval = 12 * 60,
        powerup_types = {'ammo', 'speed', 'shield', 'heal', 'rage'},
        add_interval = 30 * 60,         -- 30s 召小虫 ← 改动 2
        add_count = 2,
        add_types = {'small-biter', 'small-spitter'},
        time_limit = 5 * 60 * 60
    },
    hard = {
        name = 'hard',
        recycling_efficiency = 1,
        max_coins = 0,
        display_name_key = 'dungeon_difficulty_hard',
        arena_half = 10,                -- 20×20，场地再缩小 ← 改动 1
        boss_type = 'big-biter',
        boss_speed = 0.30,
        weapon = 'shotgun',
        weapon_ammo = 'shotgun-shell',
        ammo_count = 50,
        obstacle_count = 12,
        powerup_interval = 12 * 60,
        powerup_types = {'ammo', 'speed', 'shield', 'heal', 'rage'},
        add_interval = 20 * 60,         -- 20s 更密集的小虫 ← 改动 2
        add_count = 2,
        add_types = {'small-biter', 'small-spitter'},
        time_limit = 5 * 60 * 60
    }
}

--==============================================================================
-- 常量
--==============================================================================

local GUI_BOSS_HP = 'dungeon_bh_boss_hp'
local GUI_TIME = 'dungeon_bh_time'

-- 道具定义（与 arena_survival 完全一致）
local POWERUP_DEFS = {
    ammo = {
        item_name = 'firearm-magazine',
        count = 10,
        color = {r = 1, g = 0.45, b = 0},
        sprite = 'item.firearm-magazine',
        pickup_text_key = 'amap.arena_survival_pu_ammo',
        label_key = 'amap.arena_survival_pu_ammo_label'
    },
    speed = {
        effect = 'speed',
        duration_sec = 8,
        modifier = 0.6,
        color = {r = 0.4, g = 0.8, b = 1},
        sprite = 'item.exoskeleton-equipment',
        pickup_text_key = 'amap.arena_survival_pu_speed',
        label_key = 'amap.arena_survival_pu_speed_label'
    },
    shield = {
        effect = 'shield',
        duration_sec = 5,
        color = {r = 1, g = 0.85, b = 0},
        sprite = 'entity.stone-wall',
        pickup_text_key = 'amap.arena_survival_pu_shield',
        label_key = 'amap.arena_survival_pu_shield_label'
    },
    heal = {
        effect = 'heal',
        ratio = 0.5,
        color = {r = 0.4, g = 1, b = 0.4},
        sprite = 'item.raw-fish',
        pickup_text_key = 'amap.arena_survival_pu_heal',
        label_key = 'amap.arena_survival_pu_heal_label'
    },
    rage = {
        effect = 'rage',
        duration_sec = 8,
        modifier = 1.0,
        color = {r = 1, g = 0.2, b = 0.2},
        sprite = 'item.submachine-gun',
        pickup_text_key = 'amap.arena_survival_pu_rage',
        label_key = 'amap.arena_survival_pu_rage_label'
    }
}

-- 障碍物候选
local OBSTACLE_TYPES = {
    'big-rock', 'big-rock', 'huge-rock', 'huge-rock',
    'big-sand-rock', 'big-sand-rock',
    'tree-05', 'tree-05'
}

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

    local hp_text
    if md.boss and md.boss.valid then
        local hp = math.floor(md.boss.health or 0)
        local max_hp = math.floor(md.boss.max_health or 0)
        hp_text = {'amap.boss_hunt_hp', hp, max_hp}
    else
        hp_text = {'amap.boss_hunt_hp_dead'}
    end
    ensure(GUI_BOSS_HP).caption = hp_text

    local elapsed = game.tick - md.start_tick
    local remaining = math.max(0, md.time_limit - elapsed)
    local min = math.floor(remaining / 3600)
    local sec = math.floor((remaining % 3600) / 60)
    ensure(GUI_TIME).caption = {'amap.boss_hunt_time', min, sec}
end

local function cleanup_top_gui(player)
    local top = player.gui.top
    for _, name in ipairs({GUI_BOSS_HP, GUI_TIME}) do
        if top[name] then top[name].destroy() end
    end
end

-- 放置障碍物（参考 arena_survival place_obstacles）
local function place_obstacles(surface, arena_half, count)
    local placed = 0
    local max_attempts = count * 15
    for _ = 1, max_attempts do
        if placed >= count then break end
        local x = math.random(-arena_half + 2, arena_half - 2)
        local y = math.random(-arena_half + 2, arena_half - 2)
        -- 避开中心出生区
        if math.abs(x) <= 2 and math.abs(y) <= 2 then goto continue end
        local ent = surface.create_entity({
            name = OBSTACLE_TYPES[math.random(#OBSTACLE_TYPES)],
            position = {x, y},
            force = 'neutral'
        })
        if ent then
            ent.destructible = false
            placed = placed + 1
        end
        ::continue::
    end
    return placed
end

-- 清理道具渲染对象
local function destroy_powerup_render(md)
    if md.powerup_circle then md.powerup_circle.destroy(); md.powerup_circle = nil end
    if md.powerup_sprite then md.powerup_sprite.destroy(); md.powerup_sprite = nil end
    if md.powerup_text  then md.powerup_text.destroy();  md.powerup_text  = nil end
end

-- 道具刷新（参考 arena_survival spawn_powerup）
local function spawn_powerup(surface, player, md)
    local types = md.powerup_types
    if not types or #types == 0 then return end

    destroy_powerup_render(md)

    local pu_type = types[math.random(#types)]
    local def = POWERUP_DEFS[pu_type]
    if not def then return end

    local ah = md.arena_half
    local px, py
    for _ = 1, 50 do
        px = math.random(-ah + 3, ah - 3)
        py = math.random(-ah + 3, ah - 3)
        if math.abs(px) > 4 or math.abs(py) > 4 then break end
    end

    md.powerup_circle = rendering.draw_circle({
        surface = surface, target = {x = px, y = py}, radius = 1.2,
        color = def.color, filled = true, players = {player}, draw_on_ground = true
    })
    md.powerup_sprite = rendering.draw_sprite({
        sprite = def.sprite, surface = surface, target = {x = px, y = py},
        x_scale = 1.5, y_scale = 1.5, render_layer = 'object', players = {player}
    })
    md.powerup_text = rendering.draw_text({
        surface = surface, target = {x = px, y = py}, target_offset = {0, -2},
        text = {def.label_key}, color = def.color, scale = 1.0,
        font = 'default-large-semibold', alignment = 'center',
        scale_with_zoom = false, players = {player}
    })

    md.powerup_type = pu_type
    md.powerup_pos = {x = px, y = py}
end

-- 应用狂暴
local function apply_rage(player, md, duration_sec)
    local force = player.force
    md.rage_old_modifier = force.get_ammo_damage_modifier('shotgun-shell')
    force.set_ammo_damage_modifier('shotgun-shell', md.rage_old_modifier + 1.0)
    md.rage_active = true
    md.rage_expire_tick = game.tick + duration_sec * 60
end

local function remove_rage(player, md)
    if not md.rage_active then return end
    local force = player.force
    force.set_ammo_damage_modifier('shotgun-shell', md.rage_old_modifier or 0)
    md.rage_active = false
end

-- 检测道具拾取
local function check_powerup_pickup(player, md)
    if not md.powerup_type or not md.powerup_pos then return end
    local char = player.character
    if not char or not char.valid then return end

    local pp = md.powerup_pos
    local dx = char.position.x - pp.x
    local dy = char.position.y - pp.y
    if dx * dx + dy * dy > 2.25 then return end  -- 1.5 格

    local pu_type = md.powerup_type
    local def = POWERUP_DEFS[pu_type]
    if not def then return end

    if pu_type == 'ammo' then
        local ammo_name = md.weapon_ammo or 'firearm-magazine'
        local inv = player.get_main_inventory()
        if inv then inv.insert({name = ammo_name, count = def.count}) end
    elseif pu_type == 'speed' then
        local old = char.character_running_speed_modifier or 0
        char.character_running_speed_modifier = old + def.modifier
        md.speed_active = true
        md.speed_expire_tick = game.tick + def.duration_sec * 60
    elseif pu_type == 'shield' then
        md.shield_active = true
        md.shield_expire_tick = game.tick + def.duration_sec * 60
        md.shield_bonus_applied = false
    elseif pu_type == 'heal' then
        local max_hp = char.max_health or 100
        char.health = math.min(char.health + max_hp * def.ratio, max_hp)
    elseif pu_type == 'rage' then
        apply_rage(player, md, def.duration_sec)
    end

    destroy_powerup_render(md)
    player.create_local_flying_text({
        text = {def.pickup_text_key},
        position = char.position,
        color = def.color
    })
    player.play_sound({path = 'utility/achievement_unlocked', volume_modifier = 0.6})

    md.powerup_type = nil
    md.powerup_pos = nil
end

-- 召唤 Boss
local function spawn_boss(surface, player, md)
    local pos = {x = 0, y = md.arena_half - 2}
    local final_pos = surface.find_non_colliding_position(md.boss_type, pos, 8, 1) or pos

    local boss = surface.create_entity({
        name = md.boss_type,
        position = final_pos,
        force = md.dungeon_enemy_force
    })
    if not boss then return nil end

    if player.character and player.character.valid then
        local group = surface.create_unit_group({
            position = final_pos,
            force = md.dungeon_enemy_force
        })
        if group then
            group.add_member(boss)
            group.set_command({
                type = defines.command.attack,
                target = player.character,
                distraction = defines.distraction.by_anything
            })
        end
    end

    return boss
end

-- 召唤小虫子
local function spawn_adds(surface, player, md)
    if not md.add_types or #md.add_types == 0 then return end
    local boss = md.boss
    if not boss or not boss.valid then return end

    for _ = 1, md.add_count do
        local t = md.add_types[math.random(#md.add_types)]
        local angle = math.random() * 6.28
        local dist = 3
        local pos = {
            x = boss.position.x + math.cos(angle) * dist,
            y = boss.position.y + math.sin(angle) * dist
        }
        local final = surface.find_non_colliding_position(t, pos, 4, 1) or pos
        local add = surface.create_entity({
            name = t,
            position = final,
            force = md.dungeon_enemy_force
        })
        if add and player.character and player.character.valid then
            local group = surface.create_unit_group({
                position = final,
                force = md.dungeon_enemy_force
            })
            if group then
                group.add_member(add)
                group.set_command({
                    type = defines.command.attack,
                    target = player.character,
                    distraction = defines.distraction.by_anything
                })
            end
            md.active_adds[#md.active_adds + 1] = add
        end
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

    -- 障碍物
    place_obstacles(surface, ah, diff.obstacle_count)

    data.module_data = {
        arena_half = ah,
        boss_type = diff.boss_type,
        boss_speed = diff.boss_speed,
        weapon = diff.weapon,
        weapon_ammo = diff.weapon_ammo,
        ammo_count = diff.ammo_count,
        add_interval = diff.add_interval,
        add_count = diff.add_count,
        add_types = diff.add_types,
        obstacle_count = diff.obstacle_count,
        powerup_interval = diff.powerup_interval,
        powerup_types = diff.powerup_types,
        time_limit = diff.time_limit or M.time_limit_default,
        boss = nil,
        active_adds = {},
        next_add_tick = 0,
        start_tick = 0,
        boss_died = false,
        player_died = false,
        dungeon_enemy_force = 'dungeon_enemy',
        -- 道具状态
        powerup_type = nil,
        powerup_pos = nil,
        powerup_circle = nil,
        powerup_sprite = nil,
        powerup_text = nil,
        next_powerup_tick = 0,
        rage_active = false,
        rage_expire_tick = 0,
        rage_old_modifier = 0,
        speed_active = false,
        speed_expire_tick = 0,
        shield_active = false,
        shield_expire_tick = 0,
        shield_bonus_applied = false
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
    md.start_tick = game.tick
    md.next_add_tick = game.tick + (md.add_interval > 0 and md.add_interval or 999999)
    md.next_powerup_tick = game.tick + 8 * 60  -- 8 秒后首个道具

    -- 隐藏框架 coins label
    local top = player.gui.top
    if top['dungeon_coins'] then top['dungeon_coins'].destroy() end

    -- 召唤 Boss
    local boss = spawn_boss(player.surface, player, md)
    if boss then
        if md.boss_speed ~= 1 then boss.speed = md.boss_speed end
        md.boss = boss
    end

    -- 配发武器
    local gun_inv = player.get_inventory(defines.inventory.character_guns)
    if gun_inv and gun_inv.get_item_count(diff.weapon) == 0 then
        gun_inv.insert({name = diff.weapon, count = 1})
    end
    local ammo_inv = player.get_inventory(defines.inventory.character_ammo)
    if ammo_inv and ammo_inv.get_item_count(diff.weapon_ammo) == 0 then
        ammo_inv.insert({name = diff.weapon_ammo, count = 10})
    end
    local main_inv = player.get_main_inventory()
    if main_inv then
        main_inv.insert({name = diff.weapon_ammo, count = diff.ammo_count})
    end

    update_top_gui(player, md)
    player.print({'amap.boss_hunt_enter'}, {r = 0, g = 1, b = 0})
    player.print({'amap.boss_hunt_hint'}, {r = 1, g = 0.8, b = 0})
end

function M.on_tick(player, data)
    local md = data.module_data
    if not md then return end
    local tick = game.tick
    local surface = player.surface

    -- Boss 速度维持 + 持续追击
    if md.boss and md.boss.valid then
        if md.boss_speed ~= 1 then md.boss.speed = md.boss_speed end

        if tick % 60 == 0 then
            local char = player.character
            if char and char.valid then
                local group = surface.create_unit_group({
                    position = md.boss.position,
                    force = md.dungeon_enemy_force
                })
                if group then
                    group.add_member(md.boss)
                    group.set_command({
                        type = defines.command.attack,
                        target = char,
                        distraction = defines.distraction.by_anything
                    })
                end
            end
        end
    end

    -- 召唤小虫子
    if md.add_interval > 0 and tick >= md.next_add_tick then
        spawn_adds(surface, player, md)
        md.next_add_tick = tick + md.add_interval
    end

    -- 清理死小虫子
    for i = #md.active_adds, 1, -1 do
        if not md.active_adds[i] or not md.active_adds[i].valid then
            table.remove(md.active_adds, i)
        end
    end

    -- 道具刷新
    if tick >= md.next_powerup_tick then
        spawn_powerup(surface, player, md)
        md.next_powerup_tick = tick + md.powerup_interval
    end

    -- 道具拾取检测
    check_powerup_pickup(player, md)

    -- 效果过期处理
    if md.rage_active and tick >= md.rage_expire_tick then
        remove_rage(player, md)
    end
    if md.speed_active and tick >= md.speed_expire_tick then
        md.speed_active = false
        -- 速度 modifier 无法精确回退（可能叠加过），保守做法：恢复到 0
        local char = player.character
        if char and char.valid then
            char.character_running_speed_modifier = 0
        end
    end
    if md.shield_active and tick >= md.shield_expire_tick then
        md.shield_active = false
    end

    update_top_gui(player, md)
end

function M.check_victory(player, data)
    local md = data.module_data
    if not md then return nil end

    if md.player_died then return 'defeat' end

    if md.boss_died then
        local remaining = math.max(0, md.time_limit - (game.tick - md.start_tick))
        local ratio = remaining / md.time_limit
        local mult = 1.5 + ratio * 0.5
        Instance.set_reward_multiplier(player, mult)
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
    if entity.type ~= 'unit' then return end
    if not entity.force or entity.force.name ~= 'dungeon_enemy' then return end

    local data = Instance.get_data(player.index)
    if not data then return end
    local md = data.module_data
    if not md then return end

    -- Boss 死亡
    if md.boss and entity == md.boss then
        md.boss_died = true
        md.boss = nil
        player.create_local_flying_text({
            text = {'amap.boss_hunt_boss_down'},
            position = entity.position,
            color = {1, 0.85, 0.2}
        })
        player.play_sound({path = 'utility/achievement_unlocked', volume_modifier = 0.8})
        return
    end

    -- 小虫子死亡
    for i, add in ipairs(md.active_adds) do
        if add == entity then
            table.remove(md.active_adds, i)
            break
        end
    end
end

function M.on_exit(player, data, reason)
    local md = data.module_data
    if not md then return end

    -- 清理 Boss
    if md.boss and md.boss.valid then md.boss.destroy() end
    md.boss = nil

    -- 清理小虫子
    local adds = md.active_adds
    md.active_adds = {}
    for _, a in ipairs(adds) do
        if a and a.valid then a.destroy() end
    end

    -- 清理道具渲染
    destroy_powerup_render(md)

    -- 恢复狂暴 modifier（避免污染主世界）
    if md.rage_active then
        remove_rage(player, md)
    end

    -- 恢复速度 modifier
    if md.speed_active then
        local char = player.character
        if char and char.valid then
            char.character_running_speed_modifier = 0
        end
    end

    cleanup_top_gui(player)
end

--==============================================================================
-- 注册
--==============================================================================

Instance.register(M.type, M)
return M
