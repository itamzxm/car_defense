-- maps/amap/fx_budget.lua
-- 天赋特效预算网关：每秒绘制预算 + 按玩家配额，超限舍弃
--
-- 设计（用户决策 2026-08-11）：
--   不做常态驻留特效；采用"每秒可绘制动画量"预算制：
--   1. 全局池：每秒允许产生的 rendering 对象×tick 总量（≈ 同时存在对象数 × 60）
--   2. 每玩家池：每秒每人允许的量（防单人连发挤占他人）
--   3. 动画 spawn 前 try_spend(cost)，预算不足直接舍弃（静默）
--
-- 数值基准：常态 20 玩家 × 平均 15 对象 × 1 秒生命周期 ≈ 18000 对象·tick/秒
--   GLOBAL_BUDGET   = 24000（≈400 个对象同时存在，含 1.3 倍余量）
--   PLAYER_BUDGET   = 2400 （≈40 个对象同时，单人连发天花板）
--   实际量级按需调整这两个常量即可

local Public = {}

-- =============================================================================
-- 预算常量（对象·tick / 秒）
-- =============================================================================

local GLOBAL_BUDGET = 24000
local PLAYER_BUDGET = 2400

-- =============================================================================
-- 窗口状态（每秒滚动；存运行时表，无需持久化）
-- =============================================================================

local global_state = {bucket = -1, spent = 0}
local player_states = {}   -- player_index -> {bucket, spent}

-- 尝试支出 cost（对象×tick），预算充足则扣减并返回 true
-- 全局池与玩家池同时满足才放行；任一不足即舍弃（返回 false）
function Public.try_spend(player_index, cost)
    if type(cost) ~= 'number' or cost <= 0 then return true end

    local bucket = math.floor(game.tick / 60)

    -- 全局池滚动
    if global_state.bucket ~= bucket then
        global_state.bucket = bucket
        global_state.spent = 0
    end
    if global_state.spent + cost > GLOBAL_BUDGET then
        return false
    end

    -- 玩家池滚动
    local ps = player_states[player_index]
    if not ps then
        ps = {bucket = bucket, spent = 0}
        player_states[player_index] = ps
    end
    if ps.bucket ~= bucket then
        ps.bucket = bucket
        ps.spent = 0
    end
    if ps.spent + cost > PLAYER_BUDGET then
        return false
    end

    global_state.spent = global_state.spent + cost
    ps.spent = ps.spent + cost
    return true
end

-- 查询当前剩余预算（调试用）
function Public.get_budget_usage(player_index)
    local bucket = math.floor(game.tick / 60)
    local g = global_state
    if g.bucket ~= bucket then g.bucket = bucket; g.spent = 0 end
    local ps = player_states[player_index]
    local p_spent = 0
    if ps and ps.bucket == bucket then p_spent = ps.spent end
    return g.spent, GLOBAL_BUDGET, p_spent, PLAYER_BUDGET
end

return Public
