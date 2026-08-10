-- maps/amap/pseudo_building/buildings/bullet_supply_tower.lua
-- 子弹补给塔（魔法技能「子弹补给塔」的虚拟建筑载体）
-- 原型 passive-provider-chest，不限时（lifespan=0 永久）
-- 每 3 秒（180 tick）用箱内子弹给半径 3 格内己方 gun-turret 补弹
-- 只自动填弹，不生成弹药：箱内无弹则跳过

local Framework = require 'maps.amap.pseudo_building.framework'
local Fns = require 'maps.amap.pseudo_building.functions'

local M = {}
M.type = 'bullet_supply'
M.category = 'storage'

local SUPPLY_RANGE = 3       -- 补弹半径（格）
local SUPPLY_INTERVAL = 180  -- 每 3 秒

M.on_interval = function(e, data, ctx)
    if not e.valid then return end
    local chest_inv = e.get_inventory(defines.inventory.chest)
    if not chest_inv or chest_inv.is_empty() then return end
    local surface = e.surface
    -- 只补己方机枪炮塔（gun-turret）
    local turrets = surface.find_entities_filtered{
        position = e.position,
        radius = SUPPLY_RANGE,
        name = 'gun-turret',
        force = game.forces.player,
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

Framework.register('bullet_supply', M)

Framework.add_building('bullet_supply', function(player, surface, position, side)
    return Fns.create_storage(surface, position, {
        name = '子弹补给塔',
        show_ring = true,
        ring_radius = SUPPLY_RANGE,
        ring_color = {0.3, 0.7, 1, 0.7},
        icon = 'entity/passive-provider-chest',
        lifespan = 0,                 -- 不限时（永久存在）
        timed = true,
        interval = SUPPLY_INTERVAL,   -- 每 3 秒补弹一次
        operable = true,              -- 玩家可打开箱子放入子弹
        force_side = side,
        owner_player = player and player.index,
        module = 'bullet_supply',
    })
end)

return M
