-- maps/amap/instance/rewards.lua
-- 副本奖励池系统：注册/分类/按系数缩放发放
--
-- 设计目标：
--   1. 任何奖励都可以通过 Rewards.register 注册
--   2. 奖励按分类（common/rare/epic/legendary）划分，分类用于：
--      - 难度过滤池子（easy→common/rare, normal→rare/epic, hard→epic/legendary）
--      - UI 卡牌颜色区分
--   3. 副本提交奖励系数（multiplier，>=0）：
--      - 系数 = 0：不给任何奖励
--      - 系数 > 0：发放预抽奖励，数值按系数缩放
--   4. 奖励在进入副本前已预抽确定（由 instance.lua 的卡片 GUI 处理）
--   5. 通关时由 instance.lua 直接调用 Rewards.grant(player, reward_id, data, multiplier) 发放
--
-- 依赖：无（不再需要 Event，因为不再处理 GUI 事件）

local Public = {}

--==============================================================================
-- 奖励分类
--==============================================================================

local CATEGORY = {
    common = 1,
    rare = 2,
    epic = 3,
    legendary = 4
}

-- 分类对应的 UI 颜色（参考 tianfu.lua TianfuQuality.color）
-- 用 RGB 0-1 表示，可直接传给 font_color
local CATEGORY_COLOR = {
    common    = {r = 200/255, g = 200/255, b = 200/255},
    rare      = {r = 80/255,  g = 140/255, b = 255/255},
    epic      = {r = 180/255, g = 80/255,  b = 255/255},
    legendary = {r = 255/255, g = 180/255, b = 60/255}
}

-- 难度 → 可抽取的分类列表
-- 按用户新要求，每档难度严格对应一个奖励档位：
--   easy   → common（低档：配方产能 + 商店包low）
--   normal → rare   （中档：阵营加成 + 商店包mid）
--   hard   → epic/legendary（高档：伤害加成）
local DIFFICULTY_CATEGORIES = {
    easy   = {'common'},
    normal = {'rare'},
    hard   = {'epic', 'legendary'}
}

--==============================================================================
-- 奖励注册表
--==============================================================================

-- reward_id -> def
-- def 字段：
--   id (string): 与 key 一致
--   name_key (string): locale 键（奖励分类名，备用）
--   description_key (string): locale 键（奖励说明）
--   category (string): 'common' / 'rare' / 'epic' / 'legendary'
--   icon (string, 可选): sprite 路径（如 'item/raw-fish'）
--   weight (number|function, 可选): 抽取权重
--       - 若为数字：固定权重（默认 1）
--       - 若为函数 (player) -> number：动态权重，按玩家状态返回该奖励展开后的条目数
--         例如 recipe_productivity 有 9 个配方时返回 9，shop_pack 返回 1
--         实现"按实际条目抽取"而非"按 reward_id 抽取"
--   roll_preview (function(player, difficulty) -> table|nil, 可选): 预抽具体参数
--       返回 {display_key=locale键, display_args=locale参数列表, params=任意table}
--       display_key + display_args 用于卡片 GUI 显示具体奖励内容（如"激光伤害加成 +3%"）
--       params 会传给 grant_scaled，让发放时用预抽参数而非再次随机
--       若返回 nil，卡片 GUI 回退到显示 name_key
--   grant_scaled (function(player, data, multiplier, params)): 按预抽参数发放
--       - player: 玩家对象
--       - data: 副本数据（退出后为 nil）
--       - multiplier: 副本提交的奖励系数（>0）
--       - params: 预抽时 roll_preview 返回的 params（可能为 nil，grant 需兜底）
local reward_registry = {}
local reward_order = {}  -- 顺序记录，便于遍历

--==============================================================================
-- 注册接口
--==============================================================================

function Public.register(reward_id, def)
    if not reward_id or reward_id == "" then
        error("Rewards.register: reward_id 不能为空")
    end
    if not def then
        error("Rewards.register: def 不能为空 (id=" .. tostring(reward_id) .. ")")
    end
    if not def.name_key then
        error("Rewards.register: def.name_key 必填 (id=" .. reward_id .. ")")
    end
    if not def.category or not CATEGORY[def.category] then
        error("Rewards.register: def.category 必填且必须为 common/rare/epic/legendary (id=" .. reward_id .. ")")
    end
    if not def.grant_scaled or type(def.grant_scaled) ~= 'function' then
        error("Rewards.register: def.grant_scaled 必须是函数 (id=" .. reward_id .. ")")
    end

    def.id = reward_id
    reward_registry[reward_id] = def

    -- 顺序记录（去重）
    local already = false
    for _, id in ipairs(reward_order) do
        if id == reward_id then already = true break end
    end
    if not already then
        reward_order[#reward_order + 1] = reward_id
    end
end

function Public.get_registry()
    return reward_registry
end

function Public.get_reward(reward_id)
    return reward_registry[reward_id]
end

--==============================================================================
-- 池过滤与抽取
--==============================================================================

-- 按难度获取候选奖励池（返回 reward_id 列表）
function Public.get_pool(difficulty)
    local allowed_categories = DIFFICULTY_CATEGORIES[difficulty]
    if not allowed_categories then
        allowed_categories = DIFFICULTY_CATEGORIES.easy
    end

    local category_set = {}
    for _, cat in ipairs(allowed_categories) do
        category_set[cat] = true
    end

    local pool = {}
    for _, id in ipairs(reward_order) do
        local def = reward_registry[id]
        if def and category_set[def.category] then
            pool[#pool + 1] = id
        end
    end
    return pool
end

-- 按难度抽取 N 个候选（带权重、无重复）
-- 返回列表，每个元素 {id=reward_id, preview=roll_preview()返回值或nil}
-- preview 结构：{display_key=locale键, display_args=参数列表, params=任意table}
-- preview=nil 时卡片 GUI 回退到显示 def.name_key
function Public.roll_choices(difficulty, count, player)
    local pool = Public.get_pool(difficulty)
    if #pool == 0 then return {} end

    -- 复制可抽取列表，按权重随机
    -- weight 支持数字或函数：函数形式返回该奖励展开后的实际条目数
    -- 实现"按实际条目抽取"：9 个配方 + 1 个商店包 = 1:9 而非 1:1
    local candidates = {}
    for _, id in ipairs(pool) do
        local def = reward_registry[id]
        local w = def.weight or 1
        if type(w) == 'function' then
            local ok, dyn_w = pcall(w, player)
            w = (ok and type(dyn_w) == 'number') and dyn_w or 1
        end
        if w < 0 then w = 0 end
        candidates[#candidates + 1] = {
            id = id,
            weight = w
        }
    end

    local result = {}
    local remaining = math.min(count or 3, #candidates)

    for _ = 1, remaining do
        -- 计算总权重
        local total_weight = 0
        for _, c in ipairs(candidates) do
            total_weight = total_weight + c.weight
        end
        if total_weight <= 0 then break end

        -- 加权随机
        local r = math.random() * total_weight
        local picked_idx = nil
        local acc = 0
        for i, c in ipairs(candidates) do
            acc = acc + c.weight
            if r <= acc then
                picked_idx = i
                break
            end
        end

        if not picked_idx then picked_idx = #candidates end

        local picked_id = candidates[picked_idx].id
        local def = reward_registry[picked_id]

        -- 滚 preview（具体奖励参数）
        local preview = nil
        if def.roll_preview then
            local ok, pv = pcall(def.roll_preview, player, difficulty)
            if ok then preview = pv end
        end

        result[#result + 1] = {
            id = picked_id,
            preview = preview
        }
        table.remove(candidates, picked_idx)
    end

    return result
end

--==============================================================================
-- 奖励发放（按系数缩放）
--==============================================================================

-- 按系数发放奖励
-- multiplier: 副本提交的系数（必须 > 0，由调用方保证）
-- data: 副本数据（退出后为 nil）
-- params: 预抽的具体参数（由 roll_preview 返回，传给 grant_scaled 用）
function Public.grant(player, reward_id, data, multiplier, params)
    if not player or not player.valid then return false end
    local def = reward_registry[reward_id]
    if not def then
        player.print({'amap.instance_reward_unknown', tostring(reward_id)}, {r = 1, g = 0, b = 0})
        return false
    end

    -- 系数必须 > 0（防御性：若传入 0 或负数，视为 1 避免发不出东西）
    local mult = multiplier
    if not mult or mult <= 0 then
        mult = 1
    end

    local ok, err = pcall(def.grant_scaled, player, data, mult, params)
    if not ok then
        -- 不掩盖错误：log 出来并告知玩家
        log('Instance.Rewards.grant ERROR for ' .. tostring(reward_id) .. ': ' .. tostring(err))
        player.print({'amap.instance_reward_error', tostring(reward_id)}, {r = 1, g = 0, b = 0})
        return false
    end

    return true
end

--==============================================================================
-- 分类颜色（供外部 GUI 使用）
--==============================================================================

function Public.get_category_color(category)
    return CATEGORY_COLOR[category] or {r = 1, g = 1, b = 1}
end

return Public
