-- tianfu_clay_bomb.lua
-- 黏土炸弹亡语系统（从 tianfu_time_skill.lua 抽取）
-- 独立事件闭环：njbomb 打标记（写 WPT.clay_bomb_marks）+ on_entity_died 读标记→范围激光伤害
-- 自带事件注册，与其它技能零交互

local Public = {}
local Event = require 'utils.event'
local WPT = require 'maps.amap.table'
local rpgtable = require 'modules.rpg.table'
local EntityCache = require 'maps.amap.entity_cache'

local COEFF_REG = {1, 1.2, 1.4, 1.6, 1.8}
local goal = {'unit', 'turret', 'unit-spawner','spider-leg','combat-robot','spider-unit'}

local function new_print(player, text, q_idx)
    local this = WPT.get()
    local tick = game.tick
    local player_index = player.index

    if not this.print_cooldown then
        this.print_cooldown = {}
    end

    if this.print_cooldown[player_index] and tick - this.print_cooldown[player_index] < 30 then
        return
    end

    this.print_cooldown[player_index] = tick

    for _, target_player in pairs(game.connected_players) do
        if player.physical_surface == target_player.surface then
        target_player.create_local_flying_text{
            text = text,
            color = player.color,
            position = player.physical_position,
            speed = 0.8
    }
    end
    end
end

-- AFK 检查、character 检查、冷却检查都由 on_tick 桶调度提前做了（与 tianfu_time_skill 一致）
local function check_tick(player, skill, die, q_idx)
    return true
end

-- 黏土炸弹（#55）：法师被动 time-skill
-- 每6秒为玩家周围20米内随机一只友方虫子打上「亡语」标记；
-- 该虫子死亡时，对死亡点5米内所有敌方单位造成相当于持有者当前法力值×品质系数的伤害。
-- 标记仅记录于 WPT（this.clay_bomb_marks），不修改虫子本身属性；后一次打标覆盖前一次。
function Public.njbomb(player, q_idx)
    if not check_tick(player, 'njbomb') then
        return false
    end
    if not player or not player.valid or not player.character or not player.character.valid then
        return false
    end

    local surface = player.physical_surface
    if not surface then
        return false
    end

    -- 枚举玩家周围20米内、force=player 的友方虫子（unit 类实体，含驯服的虫子）
    local friends = surface.find_entities_filtered({
        position = player.physical_position,
        radius = 20,
        type = 'unit',
        force = game.forces.player
    })

    if not friends or #friends == 0 then
        return false
    end

    -- 随机选一只
    local target = friends[math.random(#friends)]
    if not target or not target.valid then
        return false
    end

    -- 打标记（覆盖式：后一次覆盖前一次，持有者=当前玩家）
    local this = WPT.get()
    if not this.clay_bomb_marks then
        this.clay_bomb_marks = {}
    end
    this.clay_bomb_marks[target.unit_number] = {
        player_index = player.index,
        q_idx = q_idx or 1
    }

    new_print(player, { 'tianfu.njbomb_over' })
    return true
end

-- 黏土炸弹亡语：独立 on_entity_died handler（不带 filters，内部自过滤）
-- 仅对带黏土炸弹标记的「友方虫子(unit)」生效，不改动 biter_die.lua 的既有 handler。
local on_clay_bomb_died = function(event)
    local entity = event.entity
    if not (entity and entity.valid) then
        return
    end
    if entity.type ~= 'unit' then
        return
    end

    local unit_number = entity.unit_number
    local this = WPT.get()
    if not this.clay_bomb_marks then
        return
    end

    local data = this.clay_bomb_marks[unit_number]
    if not data then
        return
    end

    -- 取出持有者与品质后立即清除标记（防重复触发与内存泄漏）
    this.clay_bomb_marks[unit_number] = nil

    local player = game.get_player(data.player_index)
    if not (player and player.valid) then
        return
    end

    -- 副本隔离：副本玩家不触发主世界黏土炸弹亡语
    if player.force.name ~= 'player' then return end

    local rpg_t = rpgtable.get('rpg_t')
    local pt = rpg_t[player.index]
    if not pt then
        return
    end
    local magicka = pt.magicka or 0
    local q_idx = data.q_idx or 1

    -- 最终伤害 = 当前法力值 × 品质系数（字面直读：不额外硬塞激光加成）
    local damage = magicka * COEFF_REG[q_idx]

    if damage <= 0 then
        return
    end

    local surface = entity.surface
    local position = entity.position
    if not (surface and position) then
        return
    end

    -- 对死亡点5米内所有敌方单位造成伤害（5 ≤ 24）
    -- 用项目统一的 EntityCache 缓存搜索：仅返回敌方 unit/turret/spawner 等带血小类，
    -- 内部已按 health>0 过滤，不会捞回尸体/烟雾/装饰物等无血量实体，
    -- 从根本上规避 "Entity is not entity-with-health" 崩溃。
    local enemies = EntityCache.find_entities_cached(surface, {
        position = position,
        radius = 5,
        force = game.forces.enemy,
        type = goal
    })

    local dealer = (player.character and player.character.valid) and player.character or nil

    for _, enemy in pairs(enemies) do
        if enemy and enemy.valid and enemy.health and enemy.health > 0 then
            enemy.damage(damage, game.forces.player, 'laser', dealer)
        end
    end
end
Event.add(defines.events.on_entity_died, on_clay_bomb_died)

return Public
