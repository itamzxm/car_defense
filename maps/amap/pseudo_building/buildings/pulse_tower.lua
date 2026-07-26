-- maps/amap/pseudo_building/buildings/pulse_tower.lua
-- 脉冲塔：原型 laser-turret，存活 3 分钟
-- 仅脉冲攻击：每 1 秒找最近敌人 → electric-beam → laser 伤害（参考电击枪）
-- 抑制原生激光塔开火（energy 置 0）

local Framework = require 'maps.amap.pseudo_building.framework'
local Fns = require 'maps.amap.pseudo_building.functions'

local M = {}
M.type = 'pulse'
M.category = 'attack'

local PULSE_RANGE = 24
local PULSE_DAMAGE = 15

local function fire_pulse(entity, ctx)
    local surface = entity.surface
    -- 按阵营选目标：玩家侧打 enemy，虫子侧打 player
    local target_force = (ctx and ctx.side == 'enemy') and game.forces.player or game.forces.enemy
    local enemies = surface.find_entities_filtered{
        position = entity.position,
        radius = PULSE_RANGE,
        force = target_force,
    }
    if #enemies == 0 then return end
    -- 取最近敌人
    local best, best_d = nil, math.huge
    for _, en in ipairs(enemies) do
        if en.valid then
            local dx = en.position.x - entity.position.x
            local dy = en.position.y - entity.position.y
            local d = dx * dx + dy * dy
            if d < best_d then best_d = d; best = en end
        end
    end
    if not best or not best.valid then return end
    surface.create_entity{
        name = 'electric-beam',
        position = entity.position,
        target = best.position,
        source = entity.position,
        duration = 10,
    }
    local dmg = PULSE_DAMAGE * (entity.force:get_ammo_damage_modifier('laser') + 1)
    best.damage(dmg, entity.force.name, 'laser', entity)
    surface.create_local_flying_text{
        text = tostring(math.floor(dmg)),
        position = best.position,
        color = {0.6, 0.9, 1},
        time_to_live = 40,
        speed = 1.2,
    }
end

-- 每 1 秒（框架主循环 on_tick）触发
M.on_tick = function(e, data, ctx)
    if not e.valid then return end
    -- 抑制原生开火（仅保留脉冲）
    if e.energy then e.energy = 0 end
    pcall(fire_pulse, e, ctx)
end

Framework.register('pulse', M)

Framework.add_building('pulse', function(player, surface, position, side)
    return Fns.create_attack(surface, position, {
        name = '脉冲塔',
        show_ring = true,
        ring_radius = PULSE_RANGE,
        ring_color = {0.4, 0.9, 1, 0.7},
        icon = 'entity/laser-turret',
        lifespan = 60 * 3,                 -- 3 分钟
        force_side = side,
        owner_player = player and player.index,
        module = 'pulse',
    })
end)

return M
