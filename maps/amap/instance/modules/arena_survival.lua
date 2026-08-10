-- maps/amap/instance/modules/arena_survival.lua
-- 竞技场生存玩法模块 v3.0
--
-- v3.0 重新设计 — 解决三大核心问题：
--   1. 虫子方向单一 → 每波从 4 方向中随机抽取 N 个不同方向（修复 side 顺序固定 bug）
--   2. 玩法单一 → 引入波次类型 + 道具扩展 + 连击系统 + 难度梯度差异
--   3. 经验未隔离 → 主世界 on_entity_died / on_player_changed_position / gain_xp 加副本 surface 检查
--
-- 钩子实现：
--   on_surface_init  - 生成分级竞技场 + 围墙 + 随机障碍物
--   on_enter          - 初始化难度参数 + 配发武器 + 创建顶栏 GUI + 敌对阵营
--   on_tick           - 波次管理 + 虫子生成 + 道具刷新/拾取 + 连击/效果过期 + GUI
--   check_victory     - 判定胜利/失败
--   on_entity_died    - 清理死虫 + 击杀计数 + 连击
--   on_player_died    - 标记玩家死亡
--   on_exit           - 清理所有实体和 GUI 和渲染

local Instance = require 'maps.amap.instance.instance'

local M = {}

--==============================================================================
-- 元数据
--==============================================================================

M.type = 'arena_survival'
M.display_name_key = 'amap.instance_arena_survival_name'
M.description_key = 'amap.instance_arena_survival_desc'
M.gameplay_desc_key = 'amap.instance_arena_survival_gameplay'
M.victory_condition_key = 'amap.instance_arena_survival_victory'
M.icon = 'entity/small-biter'
local SURVIVAL_TIME = 2 * 60 * 60
M.time_limit_default = SURVIVAL_TIME + 60

--==============================================================================
-- 难度设置（v3.2：三难度统一霰弹枪 + 统一波间隔 13 秒 + 每波渐进增强）
-- 威胁值参考 wave_defense/threat_values.lua：
--   small-biter/spitter = 1, medium = 4, big = 16, behemoth = 64
-- 设计目标：
--   简单总威胁 ~25（5 波 small-biter，最大场地，多道具）
--   普通总威胁 ~80（7 波含 medium 精英 + big boss，中场地 18×18）
--   困难 = 普通配置 + 场地缩小到 14×14 + 10 波
-- wave_scaling: 每波额外增加的虫子数量（波1无加成，波2+N，波3+2N...）
--==============================================================================

M.difficulty_settings = {
    easy = {
        name = 'easy',
        recycling_efficiency = 1,
        max_coins = 0,
        display_name_key = 'dungeon_difficulty_easy',
        arena_half = 24,                       -- 最大场地，宽松走位
        wave_count = 5,
        biters_per_wave = 4,                   -- 每波 4 只 small-biter
        biter_types = {'small-biter'},
        elite_biter_types = {'small-biter'},   -- 精英波也只用 small-biter（血量翻倍）
        boss_biter_type = 'medium-biter',      -- Boss 波 1 只 medium-biter（威胁 4）
        wave_interval = 13 * 60,               -- 统一 13 秒，节奏一致
        weapon = 'shotgun',
        weapon_ammo = 'shotgun-shell',
        ammo_count = 30,                       -- 30+10 = 40 发，弹药充足
        obstacle_count = 18,                   -- 多掩体
        powerup_interval = 9 * 60,             -- 道具刷新最快
        powerup_types = {'ammo', 'speed', 'shield', 'heal', 'rage', 'slow'},
        wave_types = {'normal', 'normal', 'swarm', 'normal', 'elite'},
        wave_scaling = 1                       -- 每波 +1 只（波1:4, 波2:5, 波3:6...）
    },
    normal = {
        name = 'normal',
        recycling_efficiency = 1,
        max_coins = 0,
        display_name_key = 'dungeon_difficulty_normal',
        arena_half = 18,
        wave_count = 7,
        biters_per_wave = 5,
        biter_types = {'small-biter', 'small-spitter'},
        elite_biter_types = {'medium-biter', 'medium-spitter'},
        boss_biter_type = 'big-biter',
        wave_interval = 13 * 60,
        weapon = 'shotgun',
        weapon_ammo = 'shotgun-shell',
        ammo_count = 20,                       -- 20+10 = 30 发
        obstacle_count = 12,
        powerup_interval = 12 * 60,
        powerup_types = {'ammo', 'speed', 'shield', 'heal', 'rage'},
        wave_types = {'normal', 'swarm', 'normal', 'elite', 'normal', 'boss', 'normal'},
        wave_scaling = 1                       -- 每波 +1 只（波1:5, 波2:6, 波3:7...）
    },
    hard = {
        name = 'hard',
        recycling_efficiency = 1,
        max_coins = 0,
        display_name_key = 'dungeon_difficulty_hard',
        arena_half = 14,                       -- 基于普通模式，仅缩小场地
        wave_count = 10,
        biters_per_wave = 5,
        biter_types = {'small-biter', 'small-spitter'},
        elite_biter_types = {'medium-biter', 'medium-spitter'},
        boss_biter_type = 'big-biter',
        wave_interval = 13 * 60,
        weapon = 'shotgun',
        weapon_ammo = 'shotgun-shell',
        ammo_count = 20,                       -- 20+10 = 30 发
        obstacle_count = 12,
        powerup_interval = 12 * 60,
        powerup_types = {'ammo', 'speed', 'shield', 'heal', 'rage'},
        wave_types = {'normal', 'swarm', 'elite', 'normal', 'swarm', 'elite', 'boss', 'swarm', 'elite', 'boss'},
        wave_scaling = 1                       -- 每波 +1 只（波1:5, 波2:6...波10:14）
    }
}

--==============================================================================
-- 常量
--==============================================================================

-- 道具定义（v3.0：新增 heal / rage / slow）
-- 每个道具有独立 sprite（精灵图标）+ 颜色 + 标签，玩家一眼就能识别种类
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
    },
    slow = {
        effect = 'slow',
        duration_sec = 8,
        modifier = 0.5,
        color = {r = 0.7, g = 0.5, b = 1},
        sprite = 'item.slowdown-capsule',
        pickup_text_key = 'amap.arena_survival_pu_slow',
        label_key = 'amap.arena_survival_pu_slow_label'
    }
}

-- 障碍物候选（来自本地 world_function.lua 已验证的实体名）
local OBSTACLE_TYPES = {
    'big-rock', 'big-rock', 'huge-rock', 'huge-rock',
    'big-sand-rock', 'big-sand-rock',
    'tree-05', 'tree-05'
}

-- 顶栏 GUI
local GUI_WAVE = 'dungeon_as_wave'
local GUI_BITER_COUNT = 'dungeon_as_biter_count'
local GUI_KILLS = 'dungeon_as_kills'
local GUI_AMMO = 'dungeon_as_ammo'
local GUI_COMBO = 'dungeon_as_combo'

-- 连击系统
local COMBO_TIMEOUT = 5 * 60  -- 5 秒不击杀则断
local COMBO_MILESTONES = {5, 10, 20}  -- 触发额外奖励的连击数

--==============================================================================
-- 辅助函数
--==============================================================================

-- 从 4 个方向中随机抽取 N 个不同方向（修复 v2.0 顺序固定 bug）
local function pick_random_sides(n)
    n = math.max(1, math.min(4, n))
    local sides = {1, 2, 3, 4}
    -- Fisher-Yates shuffle
    for i = #sides, 2, -1 do
        local j = math.random(i)
        sides[i], sides[j] = sides[j], sides[i]
    end
    local picked = {}
    for i = 1, n do
        picked[#picked + 1] = sides[i]
    end
    return picked
end

-- 计算 side_count：波次越高方向越多
local function calc_side_count(current_wave)
    -- wave 0: 1 / wave 1: 1-2 / wave 2: 2 / wave 3: 2-3 / wave 4+: 3 / wave 6+: 4
    if current_wave <= 0 then return 1 end
    if current_wave <= 1 then return math.random(1, 2) end
    if current_wave <= 2 then return 2 end
    if current_wave <= 3 then return math.random(2, 3) end
    if current_wave <= 5 then return 3 end
    return 4
end

local function get_edge_spawn(arena_half, side)
    local max_r = arena_half - 1
    if side == 1 then return {x = math.random(-max_r, max_r), y = -max_r}
    elseif side == 2 then return {x = math.random(-max_r, max_r), y = max_r}
    elseif side == 3 then return {x = -max_r, y = math.random(-max_r, max_r)}
    else return {x = max_r, y = math.random(-max_r, max_r)}
    end
end

-- 创建一只虫子并加入攻击组
-- revives: 复活次数（精英=1 / Boss=3），死亡时原地复活继续战斗，等效血量翻倍/四倍
local function create_biter(surface, biter_type, pos, target, force_name, active_biters, biter_revives, revives)
    local pos_final = surface.find_non_colliding_position(biter_type, pos, 8, 1) or pos
    local biter = surface.create_entity({
        name = biter_type,
        position = pos_final,
        force = force_name
    })
    if not biter then return nil end

    local group = surface.create_unit_group({
        position = pos_final,
        force = force_name
    })
    if group then
        group.add_member(biter)
        group.set_command({
            type = defines.command.attack,
            target = target,
            distraction = defines.distraction.by_anything
        })
    end
    active_biters[#active_biters + 1] = biter

    -- 记录复活次数（用 unit_number 索引）
    if revives and revives > 0 and biter_revives then
        biter_revives[biter.unit_number] = {
            revives = revives,
            biter_type = biter_type,
            force_name = force_name
        }
    end
    return biter
end

-- 计算当前波次类型
local function get_wave_type(md)
    local types = md.wave_types
    if not types or #types == 0 then return 'normal' end
    local idx = ((md.current_wave - 1) % #types) + 1
    return types[idx]
end

-- 生成一波虫子（v3.2：支持波次类型 + 4 方向随机抽取 + 渐进增强）
-- wave_scaling: 每波额外增加的虫子数（波1无加成，波2+scaling，波3+2*scaling...）
local function spawn_wave(surface, player, md)
    local target = player.character
    if not target or not target.valid then return end

    local base_count = md.biters_per_wave
    local wave_type = get_wave_type(md)
    md.last_wave_type = wave_type

    -- 渐进增强：波次越高虫子越多
    local scaling = md.wave_scaling or 0
    local wave_bonus = scaling * (md.current_wave)  -- wave 0 → +0, wave 1 → +scaling, wave 2 → +2*scaling...

    -- 按波次类型决定虫子池和数量（在渐进加成基础上调整）
    -- revives: 复活次数，死亡时原地复活继续战斗（参考 wave_defense 复活机制）
    --   1 次复活 = 等效血量 ×2；3 次复活 = 等效血量 ×4
    --   （不能直接改 biter.health，Factorio 中 health 上限受原型 max_health 限制，会被截断）
    local biter_pool, count, revives
    if wave_type == 'swarm' then
        -- 潮汐波：数量翻倍，只用基础弱虫
        biter_pool = md.biter_types
        count = base_count * 2 + wave_bonus
        revives = 0
    elseif wave_type == 'elite' then
        -- 精英波：数量减半 + 渐进加成，复活 1 次（等效 2 倍血量），用精英虫
        biter_pool = md.elite_biter_types
        count = math.max(2, math.floor(base_count / 2) + math.floor(wave_bonus / 2))
        revives = 1
    elseif wave_type == 'boss' then
        -- Boss 波：1 只强力 Boss + 渐进加成（后期 Boss 波追加小怪护卫）
        biter_pool = {md.boss_biter_type}
        count = 1 + math.floor(wave_bonus / 3)  -- 后期 Boss 带小虫护卫
        revives = 3
    else
        -- 普通波
        biter_pool = md.biter_types
        count = base_count + wave_bonus
        revives = 0
    end

    local ah = md.arena_half
    local side_count = calc_side_count(md.current_wave)
    local sides = pick_random_sides(side_count)
    local per_side = math.max(1, math.floor(count / #sides))
    local rest = count - per_side * #sides

    for idx, side in ipairs(sides) do
        local n = per_side + (idx <= rest and 1 or 0)
        for _ = 1, n do
            local biter_type = biter_pool[math.random(#biter_pool)]
            local spawn_base = get_edge_spawn(ah, side)
            create_biter(surface, biter_type, spawn_base, target,
                md.dungeon_enemy_force, md.active_biters,
                md.biter_revives, revives)
        end
    end

    md.current_wave = md.current_wave + 1

    -- 预公告下一波类型
    if md.current_wave <= md.wave_count then
        local next_type = get_wave_type({wave_types = md.wave_types, current_wave = md.current_wave})
        md.next_wave_type = next_type
    else
        md.next_wave_type = nil
    end
end

-- 生成障碍物
local function place_obstacles(surface, arena_half, count)
    local obstacles = {}
    local exclude_min, exclude_max = -2, 2
    local placed = 0
    local max_attempts = count * 15

    for _ = 1, max_attempts do
        if placed >= count then break end
        local x = math.random(-arena_half + 2, arena_half - 2)
        local y = math.random(-arena_half + 2, arena_half - 2)
        if x >= exclude_min and x <= exclude_max and y >= exclude_min and y <= exclude_max then
            goto continue_obstacle
        end
        local too_close = false
        for _, existing in ipairs(obstacles) do
            if (x - existing.x) ^ 2 + (y - existing.y) ^ 2 < 9 then
                too_close = true
                break
            end
        end
        if too_close then goto continue_obstacle end

        local ent = surface.create_entity({
            name = OBSTACLE_TYPES[math.random(#OBSTACLE_TYPES)],
            position = {x, y},
            force = 'neutral'
        })
        if ent then
            ent.destructible = false
            placed = placed + 1
            obstacles[#obstacles + 1] = {x = x, y = y}
        end
        ::continue_obstacle::
    end
    return obstacles
end

-- 清理道具渲染对象
local function destroy_powerup_render(md)
    if md.powerup_circle then
        md.powerup_circle.destroy()
        md.powerup_circle = nil
    end
    if md.powerup_sprite then
        md.powerup_sprite.destroy()
        md.powerup_sprite = nil
    end
    if md.powerup_text then
        md.powerup_text.destroy()
        md.powerup_text = nil
    end
end

-- 道具刷新（使用 rendering API 显示可视化指示灯）
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

    -- 三层视觉指示：地面光圈 + 物品精灵 + 文本标签
    -- 颜色 + 图标双重视觉，玩家远处也能区分道具种类
    md.powerup_circle = rendering.draw_circle({
        surface = surface,
        target = {x = px, y = py},
        radius = 1.2,
        color = def.color,
        filled = true,
        players = {player},
        draw_on_ground = true
    })

    -- 物品精灵（核心识别）：每个道具用对应物品图标
    md.powerup_sprite = rendering.draw_sprite({
        sprite = def.sprite,
        surface = surface,
        target = {x = px, y = py},
        x_scale = 1.5,
        y_scale = 1.5,
        render_layer = 'object',
        players = {player}
    })

    md.powerup_text = rendering.draw_text({
        surface = surface,
        target = {x = px, y = py},
        target_offset = {0, -2},
        text = {def.label_key},
        color = def.color,
        scale = 1.0,
        font = 'default-large-semibold',
        alignment = 'center',
        scale_with_zoom = false,
        players = {player}
    })

    md.powerup_type = pu_type
    md.powerup_pos = {x = px, y = py}
end

-- 应用狂暴：玩家霰弹枪伤害 ×2（通过 ammo damage modifier）
-- 注意：三难度统一用霰弹枪，ammo_category 是 'shotgun-shell' 不是 'bullet'
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
    local old = md.rage_old_modifier or 0
    force.set_ammo_damage_modifier('shotgun-shell', old)
    md.rage_active = false
end

-- 应用减速场：副本内所有虫子减速
local function apply_slow(md, duration_sec)
    md.slow_active = true
    md.slow_expire_tick = game.tick + duration_sec * 60
    -- 实际减速通过 on_tick 持续修正虫子 speed modifier
end

local function remove_slow(md)
    if not md.slow_active then return end
    -- 重置所有活跃虫子的 speed modifier
    for _, b in ipairs(md.active_biters) do
        if b and b.valid then
            b.speed = 1  -- 1 = 默认速度（单位倍率）
        end
    end
    md.slow_active = false
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

    -- 应用道具
    if pu_type == 'ammo' then
        -- 根据难度使用对应弹药
        local ammo_name = md.weapon_ammo or 'firearm-magazine'
        local inv = player.get_main_inventory()
        if inv then
            inv.insert({name = ammo_name, count = def.count})
        end
    elseif pu_type == 'speed' then
        if char and char.valid then
            local old = char.character_running_speed_modifier or 0
            char.character_running_speed_modifier = old + def.modifier
            md.speed_active = true
            md.speed_expire_tick = game.tick + def.duration_sec * 60
        end
    elseif pu_type == 'shield' then
        md.shield_active = true
        md.shield_expire_tick = game.tick + def.duration_sec * 60
        md.shield_bonus_applied = false
    elseif pu_type == 'heal' then
        -- 回血：用实体属性 char.max_health（参考天赋系统 tianfu.lua:1485）
        -- 注意：prototype 不含 max_health 字段，会报 LuaEntityPrototype doesn't contain key max_health
        if char and char.valid then
            local max_hp = char.max_health or 100
            local new_hp = char.health + max_hp * def.ratio
            char.health = math.min(new_hp, max_hp)
        end
    elseif pu_type == 'rage' then
        apply_rage(player, md, def.duration_sec)
    elseif pu_type == 'slow' then
        apply_slow(md, def.duration_sec)
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

    ensure(GUI_WAVE).caption = {'amap.arena_survival_wave', md.current_wave, md.wave_count}
    ensure(GUI_BITER_COUNT).caption = {'amap.arena_survival_alive', #md.active_biters}
    ensure(GUI_KILLS).caption = {'amap.arena_survival_kills', md.kills or 0}

    local ammo_count = 0
    local ammo_inv = player.get_main_inventory()
    if ammo_inv then
        ammo_count = ammo_inv.get_item_count(md.weapon_ammo or 'firearm-magazine')
    end
    ensure(GUI_AMMO).caption = {'amap.arena_survival_ammo', ammo_count}

    -- 连击显示
    local combo_lbl = ensure(GUI_COMBO)
    if md.combo and md.combo >= 2 then
        combo_lbl.caption = {'amap.arena_survival_combo', md.combo}
    else
        combo_lbl.caption = ''
    end
end

local function cleanup_top_gui(player)
    local top = player.gui.top
    for _, name in ipairs({GUI_WAVE, GUI_BITER_COUNT, GUI_KILLS, GUI_AMMO, GUI_COMBO}) do
        if top[name] then top[name].destroy() end
    end
end

-- 连击系统：记录击杀并触发里程碑奖励
local function register_kill(player, md)
    local tick = game.tick
    -- 超时则重置连击
    if md.combo_last_tick and (tick - md.combo_last_tick) > COMBO_TIMEOUT then
        md.combo = 0
    end
    md.combo = (md.combo or 0) + 1
    md.combo_last_tick = tick

    -- 检查里程碑
    for _, milestone in ipairs(COMBO_MILESTONES) do
        if md.combo == milestone then
            -- 里程碑奖励：补充弹药（按武器对应弹药）
            local ammo_name = md.weapon_ammo or 'firearm-magazine'
            local bonus = math.floor(10 * (milestone / 5))  -- 5→10, 10→20, 20→40
            local inv = player.get_main_inventory()
            if inv then
                inv.insert({name = ammo_name, count = bonus})
            end
            player.create_local_flying_text({
                text = {'amap.arena_survival_combo_milestone', milestone, bonus},
                position = player.position,
                color = {1, 0.85, 0.2}
            })
            player.play_sound({path = 'utility/achievement_unlocked', volume_modifier = 0.8})
            break  -- 只触发一次最高里程碑
        end
    end
end

--==============================================================================
-- 框架钩子
--==============================================================================

-- on_surface_init：生成竞技场地形
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
            if wall then wall.destructible = false end
        end
    end
    for y = -ah - 1, ah + 1 do
        for _, x_offs in ipairs({-ah - 1, ah + 1}) do
            local wall = surface.create_entity({
                name = 'stone-wall', position = {x_offs, y},
                force = player.force, move_stuck_players = true
            })
            if wall then wall.destructible = false end
        end
    end

    -- 中央出生区
    for x = -2, 2 do
        for y = -2, 2 do
            surface.set_tiles({{name = 'hazard-concrete-left', position = {x, y}}})
        end
    end

    -- 随机障碍物
    place_obstacles(surface, ah, diff.obstacle_count)

    surface.always_day = true
end

-- on_enter：初始化难度参数 + 配发武器 + 创建顶栏 GUI + 敌对阵营
function M.on_enter(player, data, difficulty_key)
    local diff = M.difficulty_settings[difficulty_key]
    if not diff then diff = M.difficulty_settings.easy end

    -- 建立独立敌对阵营（不用主世界 enemy，主世界虫子进化等级太高会秒杀玩家）
    local dungeon_enemy = game.forces['dungeon_enemy']
    if not dungeon_enemy then
        dungeon_enemy = game.create_force('dungeon_enemy')
        dungeon_enemy.set_friend('player', false)
    end
    -- 副本 force 对 dungeon_enemy 解除停火 + 设为敌对
    local dungeon_force = game.forces[data.dungeon_force]
    if dungeon_force then
        dungeon_force.set_cease_fire('dungeon_enemy', false)
        dungeon_force.set_friend('dungeon_enemy', false)
        dungeon_enemy.set_friend(data.dungeon_force, false)
    end

    local md = {
        arena_half = diff.arena_half,
        wave_count = diff.wave_count,
        current_wave = 0,
        biters_per_wave = diff.biters_per_wave,
        biter_types = diff.biter_types,
        elite_biter_types = diff.elite_biter_types,
        boss_biter_type = diff.boss_biter_type,
        wave_types = diff.wave_types,
        wave_scaling = diff.wave_scaling or 0,    -- 渐进增强：每波额外 +N 只
        last_wave_type = nil,
        next_wave_type = nil,
        wave_interval = diff.wave_interval,
        next_wave_tick = game.tick + 15 * 60,
        active_biters = {},
        player_died = false,
        kills = 0,
        dungeon_enemy_force = 'dungeon_enemy',
        -- 复活次数表：unit_number -> {revives=N, biter_type=..., force_name=...}
        biter_revives = {},
        -- 武器配置
        weapon = diff.weapon,
        weapon_ammo = diff.weapon_ammo,
        -- 道具
        powerup_interval = diff.powerup_interval,
        powerup_types = diff.powerup_types,
        powerup_type = nil,
        powerup_pos = nil,
        powerup_circle = nil,
        powerup_text = nil,
        next_powerup_tick = game.tick + 8 * 60,
        -- 加速
        speed_active = false,
        speed_expire_tick = 0,
        -- 护盾
        shield_active = false,
        shield_expire_tick = 0,
        shield_bonus_applied = false,
        -- 狂暴
        rage_active = false,
        rage_expire_tick = 0,
        rage_old_modifier = 0,
        -- 减速场
        slow_active = false,
        slow_expire_tick = 0,
        -- 连击
        combo = 0,
        combo_last_tick = nil,
    }
    data.module_data = md

    -- 预公告第一波类型
    md.next_wave_type = get_wave_type(md)

    -- 配发武器：直接装入对应武器到武器栏（只装一次，避免双枪）
    local gun_inv = player.get_inventory(defines.inventory.character_guns)
    if gun_inv and gun_inv.get_item_count(diff.weapon) == 0 then
        gun_inv.insert({name = diff.weapon, count = 1})
    end

    -- 弹药装弹夹栏
    local ammo_inv = player.get_inventory(defines.inventory.character_ammo)
    if ammo_inv and ammo_inv.get_item_count(diff.weapon_ammo) == 0 then
        ammo_inv.insert({name = diff.weapon_ammo, count = 10})
    end

    -- 额外弹药放主背包
    local main_inv = player.get_main_inventory()
    if main_inv then
        main_inv.insert({name = diff.weapon_ammo, count = diff.ammo_count})
    end

    update_top_gui(player, md)
    player.print({'amap.arena_survival_enter'}, {r = 0, g = 1, b = 0})
    player.print({'amap.arena_survival_hint'}, {r = 1, g = 0.8, b = 0})
end

-- on_tick：波次 + 虫子 + 道具刷新/拾取 + 效果过期 + GUI
function M.on_tick(player, data)
    local md = data.module_data
    if not md or not md.active_biters then return end

    local surface = player.surface
    if not surface then return end
    local tick = game.tick

    -- 清理死虫
    for i = #md.active_biters, 1, -1 do
        if not md.active_biters[i] or not md.active_biters[i].valid then
            table.remove(md.active_biters, i)
        end
    end

    -- 波次生成
    if md.current_wave < md.wave_count and tick >= md.next_wave_tick then
        spawn_wave(surface, player, md)
        md.next_wave_tick = tick + md.wave_interval

        if md.current_wave <= md.wave_count then
            local wave_type_key = 'amap.arena_survival_wt_' .. (md.last_wave_type or 'normal')
            player.create_local_flying_text({
                text = {'amap.arena_survival_wave_start', md.current_wave, md.wave_count, {wave_type_key}},
                position = player.position,
                color = {1, 0.4, 0}
            })
        end
    end

    -- 道具刷新
    if tick >= md.next_powerup_tick then
        spawn_powerup(surface, player, md)
        md.next_powerup_tick = tick + md.powerup_interval
    end

    -- 道具拾取检测
    check_powerup_pickup(player, md)

    -- 加速过期
    if md.speed_active and tick >= md.speed_expire_tick then
        local char = player.character
        if char and char.valid then
            local old = char.character_running_speed_modifier or 0
            char.character_running_speed_modifier = math.max(0, old - POWERUP_DEFS.speed.modifier)
        end
        md.speed_active = false
    end

    -- 护盾管理：5 秒无敌（参考天赋系统 tianfu.lua:1485 用 char.max_health）
    if md.shield_active then
        local char = player.character
        if char and char.valid then
            -- 首次激活：加 character_health_bonus 翻倍最大血量上限
            -- 同时立即把当前血量拉满（否则只加上限不回血，护盾形同虚设）
            if not md.shield_bonus_applied then
                md.shield_original_max = char.max_health  -- 实体属性，不是 prototype
                char.character_health_bonus = (char.character_health_bonus or 0) + md.shield_original_max
                char.health = char.max_health  -- 立即拉满当前血量
                md.shield_bonus_applied = true
            end
            -- 持续保持满血（护盾期间不掉血）
            if char.health < char.max_health then
                char.health = char.max_health
            end
        end
    end

    -- 护盾过期
    if md.shield_active and tick >= md.shield_expire_tick then
        local char = player.character
        if char and char.valid and md.shield_bonus_applied then
            char.character_health_bonus = math.max(0, (char.character_health_bonus or md.shield_original_max) - md.shield_original_max)
            md.shield_bonus_applied = false
        end
        md.shield_active = false
    end

    -- 狂暴过期
    if md.rage_active and tick >= md.rage_expire_tick then
        remove_rage(player, md)
    end

    -- 减速场：持续把虫子速度设为 0.5（每 tick 检查）
    if md.slow_active then
        if tick >= md.slow_expire_tick then
            remove_slow(md)
        else
            for _, b in ipairs(md.active_biters) do
                if b and b.valid then
                    b.speed = 0.5
                end
            end
        end
    end

    -- 连击超时重置
    if md.combo and md.combo > 0 and md.combo_last_tick
        and (tick - md.combo_last_tick) > COMBO_TIMEOUT then
        md.combo = 0
    end

    update_top_gui(player, md)
end

-- check_victory：通关/失败判定
function M.check_victory(player, data)
    local md = data.module_data
    if not md then return nil end

    if md.player_died then return 'defeat' end

    if game.tick - data.start_tick >= SURVIVAL_TIME then
        -- 奖励系数固定 1.0（2026-08-10 用户决策）
        Instance.set_reward_multiplier(player, 1.0)
        return 'victory'
    end

    return nil
end

-- on_player_died
function M.on_player_died(player, data)
    local md = data.module_data
    if not md then return end
    md.player_died = true
end

-- on_entity_died：清理死虫 + 击杀计数 + 连击 + 复活处理
function M.on_entity_died(player, event)
    local entity = event.entity
    if not entity or not entity.valid then return end
    if entity.type ~= 'unit' then return end
    if not entity.force or entity.force.name ~= 'dungeon_enemy' then return end

    local data = Instance.get_data(player.index)
    if not data then return end
    local md = data.module_data
    if not md then return end

    -- 复活处理：精英/Boss 虫死亡时原地复活继续战斗（参考 wave_defense 复活机制）
    -- 不计击杀、不计连击，仅替换 active_biters 中的引用
    local revives_entry = md.biter_revives and md.biter_revives[entity.unit_number]
    if revives_entry and revives_entry.revives > 0 then
        local surface = entity.surface
        local pos = entity.position
        local target = player.character

        -- 原地复活（同类型、同 force）
        local revived = surface.create_entity({
            name = revives_entry.biter_type,
            position = pos,
            force = revives_entry.force_name
        })
        if revived and revived.valid then
            -- 重新设攻击命令
            if target and target.valid then
                local group = surface.create_unit_group({
                    position = pos,
                    force = revives_entry.force_name
                })
                if group then
                    group.add_member(revived)
                    group.set_command({
                        type = defines.command.attack,
                        target = target,
                        distraction = defines.distraction.by_anything
                    })
                end
            end

            -- 替换 active_biters 引用：移除死虫，加入新虫
            for i, b in ipairs(md.active_biters) do
                if b == entity then
                    md.active_biters[i] = revived
                    break
                end
            end

            -- 复活次数 -1，新虫记入表
            md.biter_revives[entity.unit_number] = nil
            if revives_entry.revives - 1 > 0 then
                md.biter_revives[revived.unit_number] = {
                    revives = revives_entry.revives - 1,
                    biter_type = revives_entry.biter_type,
                    force_name = revives_entry.force_name
                }
            end

            player.create_local_flying_text({
                text = {'amap.arena_survival_revive'},
                position = pos,
                color = {1, 0.5, 0.5}
            })
            return  -- 复活不计击杀
        end
        -- 复活失败（位置被占等），fallthrough 正常处理死亡
        md.biter_revives[entity.unit_number] = nil
    end

    -- 正常死亡：从 active_biters 移除 + 击杀计数 + 连击
    for i, biter in ipairs(md.active_biters) do
        if biter == entity then
            table.remove(md.active_biters, i)
            break
        end
    end

    md.kills = (md.kills or 0) + 1
    register_kill(player, md)

    player.create_local_flying_text({
        text = {'amap.arena_survival_kill', md.kills},
        position = entity.position,
        color = {0.2, 1, 0.2}
    })
end

-- on_exit：清理所有实体 + GUI + 渲染 + 效果
function M.on_exit(player, data, reason)
    local md = data.module_data
    if not md then return end

    -- 清理虫子
    local biters = md.active_biters
    md.active_biters = {}
    for _, b in ipairs(biters) do
        if b and b.valid then b.destroy() end
    end

    -- 清理复活表
    md.biter_revives = {}

    -- 清理道具渲染
    destroy_powerup_render(md)

    -- 清理加速
    if md.speed_active then
        local char = player.character
        if char and char.valid then
            local old = char.character_running_speed_modifier or 0
            char.character_running_speed_modifier = math.max(0, old - POWERUP_DEFS.speed.modifier)
        end
    end

    -- 清理护盾
    if md.shield_active and md.shield_bonus_applied then
        local char = player.character
        if char and char.valid then
            char.character_health_bonus = math.max(0, (char.character_health_bonus or md.shield_original_max) - md.shield_original_max)
        end
    end

    -- 清理狂暴（恢复 bullet modifier）
    if md.rage_active then
        remove_rage(player, md)
    end

    -- 清理减速场（无需操作，虫子已被销毁）

    cleanup_top_gui(player)
end

--==============================================================================
-- 注册
--==============================================================================

Instance.register(M.type, M)
return M
