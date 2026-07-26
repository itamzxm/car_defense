-- maps/amap/pseudo_building/buildings/supply_tower.lua
-- 物资塔：原型 assembling-machine-3，存活 3 分钟
-- 可操作：玩家自行在机器 GUI 选配方；产出第一个物品后 operable=false 锁死（继续生产）
-- 按选定配方脚本产成品，每轮耗鱼 = 商品价格/4 × 产量；鱼不足则塔自毁（敌人侧不耗鱼）

local Framework = require 'maps.amap.pseudo_building.framework'
local Fns = require 'maps.amap.pseudo_building.functions'
local BasicMarkets = require 'maps.amap.basic_markets'

local M = {}
M.type = 'supply'
M.category = 'power'

M.on_tick = function(e, data, ctx)
    if not e.valid then return end
    local recipe = e.get_recipe()
    if not recipe then
        data.next_produce = nil
        return
    end
    -- 首产之后禁止操作
    if not data.locked then
        local out = e.get_output_inventory()
        if out and out.get_item_count() > 0 then
            e.operable = false
            data.locked = true
        end
    end
    -- 生产周期（按配方 energy）
    local cycle = math.max(60, math.floor((recipe.energy or 1) * 60))
    if not data.next_produce then
        data.next_produce = game.tick + cycle
        return
    end
    if game.tick < data.next_produce then return end
    data.next_produce = game.tick + cycle

    local product = recipe.products[1]
    if not product or product.type ~= 'item' then return end
    local amount = product.amount or 1
    local value = BasicMarkets.get_item_value(product.name) or 1
    local fish_needed = math.max(1, math.floor(value / 4)) * amount

    -- 敌人侧不耗鱼
    if ctx.side ~= 'enemy' then
        if not Fns.take_fish(ctx.owner, fish_needed) then
            Fns.destroy(e.unit_number)
            return
        end
    end

    local out = e.get_output_inventory()
    if out then
        local inserted = out.insert{name = product.name, count = amount}
        if inserted < amount then
            local player = Fns.get_player(ctx.owner)
            if player and player.character then
                player.insert{name = product.name, count = amount - inserted}
            end
        end
    end
end

-- 电力型：连上电网且有电才工作（energy>0）；无电则不生产
M.check_active = function(e, ctx)
    return e.valid and e.energy > 0
end

Framework.register('supply', M)

Framework.add_building('supply', function(player, surface, position, side)
    return Fns.create_power(surface, position, {
        name = '物资塔',
        show_ring = true,
        ring_radius = 3,
        ring_color = {1, 0.5, 0.9, 0.7},
        icon = 'entity/assembling-machine-3',
        lifespan = 60 * 3,                 -- 3 分钟
        operable = true,                  -- 玩家自行设配方
        force_side = side,
        owner_player = player and player.index,
        module = 'supply',
    })
end)

return M
