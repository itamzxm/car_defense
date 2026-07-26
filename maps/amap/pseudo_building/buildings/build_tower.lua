-- maps/amap/pseudo_building/buildings/build_tower.lua
-- 建设塔：原型 assembling-machine-3，存活 5 分钟
-- 每 10 秒 revive 附近 <=3 个 ghost（凭空建造，不耗真实材料），每条耗鱼 = 制作时间/10
-- 鱼不足则塔自毁（敌人侧不耗鱼）

local Framework = require 'maps.amap.pseudo_building.framework'
local Fns = require 'maps.amap.pseudo_building.functions'

local M = {}
M.type = 'build'
M.category = 'power'

local BUILD_RANGE = 30
local MAX_PER_TICK = 3

M.on_interval = function(e, data, ctx)
    if not e.valid then return end
    local surface = e.surface
    local ghosts = surface.find_entities_filtered{
        position = e.position,
        radius = BUILD_RANGE,
        type = 'entity-ghost',
    }
    local built = 0
    for _, g in ipairs(ghosts) do
        if built >= MAX_PER_TICK then break end
        if g.valid then
            local name = g.ghost_name
            local fish_cost = math.max(1, math.floor(Fns.item_craft_time(name) / 10))
            -- 敌人侧不耗鱼
            if ctx.side ~= 'enemy' then
                if not Fns.take_fish(ctx.owner, fish_cost) then
                    Fns.destroy(e.unit_number)
                    return
                end
            end
            local ok, built_entity = pcall(surface.create_entity, {
                name = name,
                position = g.position,
                direction = g.direction or 0,
                force = g.force,
                raise_built = false,
            })
            if ok and built_entity then
                pcall(function() g.destroy() end)
                built = built + 1
            elseif ctx.side ~= 'enemy' then
                -- 建不成则退还鱼
                local player = Fns.get_player(ctx.owner)
                if player and player.character then
                    player.insert{name = 'raw-fish', count = fish_cost}
                end
            end
        end
    end
end

-- 电力型：连上电网且有电才工作（energy>0）；无电则不触发 on_interval
M.check_active = function(e, ctx)
    return e.valid and e.energy > 0
end

Framework.register('build', M)

Framework.add_building('build', function(player, surface, position, side)
    return Fns.create_power(surface, position, {
        name = '建设塔',
        show_ring = true,
        ring_radius = BUILD_RANGE,
        ring_color = {1, 0.8, 0.2, 0.7},
        icon = 'entity/assembling-machine-3',
        lifespan = 60 * 5,                 -- 5 分钟
        timed = true,
        interval = 600,                    -- 每 10 秒
        force_side = side,
        owner_player = player and player.index,
        module = 'build',
    })
end)

return M
