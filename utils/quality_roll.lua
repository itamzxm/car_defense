-- 品质抽取工具（原 modules/pet_system/table.lua 的 roll_quality 及其内部依赖，
-- 2026-09-12 宠物系统整体移除时原样迁出）。
-- 消费方：天赋品质系统 maps/amap/tianfu_quality.lua、副本商店随机包 maps/amap/instance/rewards/builtin.lua
-- 输入档位 'low' / 'mid' / 'high'，输出品质整数 1..5（1普通 2精良 3稀有 4史诗 5传说）。

local Public = {}

local quality_weights = {
    low  = {70, 18, 8,  3,  1}, -- 普通70 精良18 稀有8 史诗3 传说1
    mid  = {50, 27, 15, 6,  2},
    high = {30, 30, 25, 10, 5},
}

-- 按权重表抽取下标 1..#weights
local function raffle(weights)
    local total = 0
    for _, w in ipairs(weights) do
        total = total + w
    end
    local r = math.random(1, total)
    local cumulative = 0
    for idx, w in ipairs(weights) do
        cumulative = cumulative + w
        if r <= cumulative then
            return idx
        end
    end
    return 1
end

-- 公开的品质抽奖函数
function Public.roll_quality(tier)
    return raffle(quality_weights[tier])
end

return Public
