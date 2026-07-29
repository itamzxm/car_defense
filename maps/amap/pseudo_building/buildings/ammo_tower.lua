-- maps/amap/pseudo_building/buildings/ammo_tower.lua
-- 弹药包：原型 passive-provider-chest，存活 30 分钟
-- 每 10 秒给 25m 内炮塔补满对应子弹（消耗箱内子弹）

local Framework = require 'maps.amap.pseudo_building.framework'
local Fns = require 'maps.amap.pseudo_building.functions'

local M = {}
M.type = 'ammo'
M.category = 'storage'

local AMMO_RANGE = 25

M.on_interval = function(e, data, ctx)
    if not e.valid then return end
    local chest_inv = e.get_inventory(defines.inventory.chest)
    if not chest_inv or chest_inv.is_empty() then return end
    local surface = e.surface
    -- 只补给己方炮塔：玩家侧补 player，虫子侧补 enemy
    local target_force = (ctx.side == 'enemy') and game.forces.enemy or game.forces.player
    local turrets = surface.find_entities_filtered{
        position = e.position,
        radius = AMMO_RANGE,
        type = 'turret',
        force = target_force,
    }
    for _, t in ipairs(turrets) do
        if t.valid then
            local ammo_inv = t.get_inventory(defines.inventory.turret_ammo)
            if ammo_inv and not ammo_inv.is_full() then
                for i = 1, #chest_inv do
                    local stack = chest_inv[i]
                    if stack and stack.valid_for_read then
                        if ammo_inv.can_insert{name = stack.name, count = stack.count} then
                            local moved = ammo_inv.insert{name = stack.name, count = stack.count}
                            if moved > 0 then
                                chest_inv.remove{name = stack.name, count = moved}
                            end
                        end
                    end
                end
            end
        end
    end
end

Framework.register('ammo', M)

Framework.add_building('ammo', function(player, surface, position, side)
    return Fns.create_storage(surface, position, {
        name = '弹药包',
        show_ring = true,
        ring_radius = AMMO_RANGE,
        ring_color = {1, 0.7, 0.2, 0.7},
        icon = 'entity/passive-provider-chest',
        lifespan = 60 * 30,                -- 30 分钟
        timed = true,
        interval = 600,                    -- 每 10 秒
        force_side = side,
        owner_player = player and player.index,
        module = 'ammo',
    })
end)

return M
