-- maps/amap/pseudo_building/buildings/repair_tower.lua
-- 维修塔：原型 laser-turret，存活 10 分钟
-- 每 10 秒修复 24m 内友军建筑，自身按"实际修复量"扣血；HP<=0 自毁

local Framework = require 'maps.amap.pseudo_building.framework'
local Fns = require 'maps.amap.pseudo_building.functions'

local M = {}
M.type = 'repair'
M.category = 'attack'

local REPAIR_RANGE = 24
local REPAIR_PER_UNIT = 200   -- 单个建筑每次最多恢复血量（可调）

M.on_interval = function(e, data, ctx)
    if not e.valid then return end
    local surface = e.surface
    -- 友军：玩家侧修 player + framework_player；虫子侧修 enemy
    local forces = (ctx.side == 'enemy')
        and {game.forces.enemy}
        or {game.forces.player, game.forces.framework_player}
    local healed_total = 0
    for _, frc in ipairs(forces) do
        local friends = surface.find_entities_filtered{
            position = e.position,
            radius = REPAIR_RANGE,
            force = frc,
        }
        for _, f in ipairs(friends) do
            if f.valid and f ~= e and f.health and f.prototype and f.prototype.max_health then
                if f.health < f.prototype.max_health then
                    local need = f.prototype.max_health - f.health
                    local heal = math.min(need, REPAIR_PER_UNIT)
                    f.health = f.health + heal
                    healed_total = healed_total + heal
                end
            end
        end
    end
    -- 按实际修复量扣自身血
    if healed_total > 0 then
        e.health = (e.health or 0) - healed_total
        if e.health <= 0 then
            Fns.destroy(e.unit_number)
        end
    end
end

Framework.register('repair', M)

Framework.add_building('repair', function(player, surface, position, side)
    return Fns.create_attack(surface, position, {
        name = '维修塔',
        show_ring = true,
        ring_radius = REPAIR_RANGE,
        ring_color = {0.3, 1, 0.4, 0.7},
        icon = 'entity/laser-turret',
        lifespan = 60 * 10,                -- 10 分钟
        timed = true,
        interval = 600,                    -- 每 10 秒
        force_side = side,
        owner_player = player and player.index,
        module = 'repair',
    })
end)

return M
