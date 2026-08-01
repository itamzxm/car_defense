-- maps/amap/world/word_grid_war.lua
-- 世界 17「网格战争」核心机制模块
--
-- 职责（本文件是纯机制层，不含 World.register，注册见 worlds/world_17_grid_war.lua）：
--   1. 确定性网格散布：纯 hash 计算，不依赖 storage，任何时刻任何机器结果一致
--   2. 单元几何查询：给定世界坐标，返回它属于哪个单元、在单元内的相对位置
--   3. 地砖铺设：供 world_17 的 terrain_generator 逐 tile 调用
--   4. 单元实体填充：延迟队列（等区块生成完再填虫巢/沙虫）
--   5. 清空判定 + 奖励兑现：虫巢全灭 → 按 kind 生成资源 + 外侧刷 4 虫巢
--   6. 堡垒避让：导出 fortress_position_valid 供 stronghold_generation_algorithm_v2 调用
--
-- 设计要点（实测依据，勿改）：
--   * terrain_generator 是「逐 tile」调用（每 chunk 1024 次），所以几何必须是
--     纯函数 + per-chunk 记忆化，禁止在里面做实体查询。
--   * 抖动上限 JITTER 保证单元完全落在自己的大区块内 →
--     一个 tile 只可能属于「它自己所在大区块」的单元，单次查表即可。
--   * LCG 乘数固定 1664525（1664525 × 2^32 ≈ 7.15e15 < 2^53），
--     禁用 1103515245（会超双精度整数范围，破坏跨机器确定性）。
--   * 浅水 water-shallow 碰撞层 = water_tile/resource/floor：
--     单位与载具（player/car/train 层）都能通过，但不能放资源和建筑。
--     深水 deepwater 全阻挡。所以「1 侧浅滩」= 单元唯一出入口，波次寻路可用。

local WPT = require 'maps.amap.table'
local diff = require 'maps.amap.diff'
local Event = require 'utils.event'

local Public = {}

--==============================================================================
-- 常量
--==============================================================================

local WORLD_ID = 17

-- 大区块尺寸：每个大区块内最多 1 个单元
-- 密度翻倍：384 -> 272（≈384/√2），单元面积密度 ×2（平均间距 500m -> ~367m），
-- JITTER + CELL_OUTER = 94+34 = 128 < BLOCK/2 = 136，仍保证单元不跨大区块。
local BLOCK = 272
-- 单元内净空半宽（与中央安全区 64×64 同尺寸）
local CELL_HALF = 32
-- 水环厚度
local WATER_W = 2
-- 单元外接半宽
local CELL_OUTER = CELL_HALF + WATER_W
-- 单元出现概率（百分比）
local DENSITY = 55
-- 中心抖动上限：保证 JITTER + CELL_OUTER < BLOCK/2，单元不跨大区块
local JITTER = BLOCK / 2 - CELL_OUTER - 8
-- 堡垒避让缓冲
local FORT_BUFFER = 16
-- 单元最小距离（小于此距离不生成单元，保护出生区）
local MIN_DIST = 300
-- 资源铺设半宽（留出与水环的空隙）
local ORE_HALF = 24
-- 实体填充时的内部安全半宽
local INNER_HALF = CELL_HALF - 4

local floor = math.floor
local sqrt = math.sqrt
local abs = math.abs

--==============================================================================
-- 确定性 hash（LCG）
--==============================================================================

local M = 4294967296 -- 2^32
local A = 1664525
local C = 1013904223

local function lcg(x)
    return (A * (x % M) + C) % M
end

-- 大区块主 hash：seed + 区块坐标
local function block_hash(seed, bx, by)
    local h = lcg((seed or 0) % M)
    h = lcg(h + (bx % 65536) * 65536)
    h = lcg(h + (by % 65536))
    return h
end

-- 取高位比特映射到 [0, n)（LCG 低位随机性差，必须取高位）
local function bits(h, n)
    return floor(h / 4096) % n
end

--==============================================================================
-- 单元类型（kind）表
--==============================================================================

-- tier 1 = 地球基础矿；tier 2 = 地球高级；tier 3 = 外星
-- 权重为整数（避免浮点比较）
local KIND_POOLS = {
    [1] = {
        {name = 'iron-ore', weight = 25},
        {name = 'copper-ore', weight = 25},
        {name = 'coal', weight = 25},
        {name = 'stone', weight = 25}
    },
    [2] = {
        {name = 'uranium-ore', weight = 60},
        {name = 'crude-oil', weight = 40}
    },
    [3] = {
        {name = 'calcite', weight = 50},
        {name = 'tungsten-ore', weight = 40},
        {name = 'sulfuric-acid-geyser', weight = 30},
        {name = 'scrap', weight = 30},
        {name = 'yumako-tree', weight = 25},
        {name = 'jellystem', weight = 25}
    }
}

-- 距离分层：越远越可能出现高 tier（w = {tier1, tier2, tier3} 权重）
local TIER_BANDS = {
    {min = 300, w = {100, 0, 0}},
    {min = 750, w = {55, 45, 0}},
    {min = 1500, w = {30, 30, 40}},
    {min = 3000, w = {15, 25, 60}}
}

-- 每种 kind 的生成方式（solid=铺满矿层 / fluid=井点 / plant=种树）
local KIND_MODE = {
    ['iron-ore'] = 'solid',
    ['copper-ore'] = 'solid',
    ['coal'] = 'solid',
    ['stone'] = 'solid',
    ['uranium-ore'] = 'solid',
    ['calcite'] = 'solid',
    ['tungsten-ore'] = 'solid',
    ['scrap'] = 'solid',
    ['crude-oil'] = 'fluid',
    ['sulfuric-acid-geyser'] = 'fluid',
    ['yumako-tree'] = 'plant',
    ['jellystem'] = 'plant'
}

-- kind → 单元基底地砖组（供玩家一眼识别本格将产出什么）
-- 'earth' 普通 / 'volcanic' 火山系 / 'fulgoran' 电磁系 / 'yumako'、'jellynut' 草星系
local KIND_TILE_GROUP = {
    ['iron-ore'] = 'earth',
    ['copper-ore'] = 'earth',
    ['coal'] = 'earth',
    ['stone'] = 'earth',
    ['uranium-ore'] = 'earth',
    ['crude-oil'] = 'earth',
    ['calcite'] = 'volcanic',
    ['tungsten-ore'] = 'volcanic',
    ['sulfuric-acid-geyser'] = 'volcanic',
    ['scrap'] = 'fulgoran',
    ['yumako-tree'] = 'yumako',
    ['jellystem'] = 'jellynut'
}

--==============================================================================
-- 原型名容错解析（外星地砖/植物名猜错也不会崩，只降级 + 日志）
--==============================================================================

local TILE_CANDIDATES = {
    earth = {'grass-1', 'grass-3', 'dirt-3'},
    volcanic = {'volcanic-folds', 'volcanic-ash-soil', 'volcanic-cracks', 'volcanic-smooth-stone'},
    fulgoran = {'fulgoran-rock', 'fulgoran-dust', 'fulgoran-sand', 'fulgoran-paving'},
    yumako = {'natural-yumako-soil', 'yumako-soil'},
    jellynut = {'natural-jellynut-soil', 'jellynut-soil'},
    shallow = {'water-shallow', 'water-mud'},
    deep = {'deepwater'}
}

local TILE_FALLBACK = {
    earth = 'grass-1',
    volcanic = 'dirt-3',
    fulgoran = 'sand-1',
    yumako = 'grass-2',
    jellynut = 'grass-2',
    shallow = 'water',
    deep = 'water'
}

-- 运行期缓存（不入 storage，重载后自动重算，结果确定）
local tile_cache = {}
local entity_cache = {}

local function pick_from(pool_name, candidates, fallback, cache)
    local hit = cache[pool_name]
    if hit ~= nil then
        return hit
    end
    local pool = (cache == tile_cache) and prototypes.tile or prototypes.entity
    local result = nil
    for _, n in ipairs(candidates) do
        if pool[n] then
            result = n
            break
        end
    end
    if not result then
        result = fallback
        log('[grid_war] 原型缺失，降级：' .. tostring(pool_name) .. ' -> ' .. tostring(fallback))
    end
    cache[pool_name] = result
    return result
end

local function tile_of(group)
    return pick_from(group, TILE_CANDIDATES[group] or {}, TILE_FALLBACK[group] or 'grass-1', tile_cache)
end

local function entity_exists(name)
    local hit = entity_cache[name]
    if hit == nil then
        hit = prototypes.entity[name] ~= nil
        entity_cache[name] = hit
    end
    return hit
end

--==============================================================================
-- 单元计算（纯函数）
--==============================================================================

local function pick_tier(dist, h)
    local band = TIER_BANDS[1]
    for i = 1, #TIER_BANDS do
        if dist >= TIER_BANDS[i].min then
            band = TIER_BANDS[i]
        end
    end
    local total = band.w[1] + band.w[2] + band.w[3]
    if total <= 0 then
        return 1
    end
    local roll = bits(h, total)
    if roll < band.w[1] then
        return 1
    elseif roll < band.w[1] + band.w[2] then
        return 2
    end
    return 3
end

local function pick_kind(tier, h)
    local pool = KIND_POOLS[tier] or KIND_POOLS[1]
    local total = 0
    for i = 1, #pool do
        total = total + pool[i].weight
    end
    local roll = bits(h, total)
    local acc = 0
    for i = 1, #pool do
        acc = acc + pool[i].weight
        if roll < acc then
            return pool[i].name
        end
    end
    return pool[1].name
end

-- 计算某个大区块内的单元；无单元返回 nil
local function compute_cell(seed, bx, by)
    local h1 = block_hash(seed, bx, by)
    if bits(h1, 100) >= DENSITY then
        return nil
    end

    local h2 = lcg(h1)
    local h3 = lcg(h2)
    local h4 = lcg(h3)
    local h5 = lcg(h4)
    local h6 = lcg(h5)

    local span = 2 * JITTER + 1
    local cx = bx * BLOCK + BLOCK / 2 + (bits(h2, span) - JITTER)
    local cy = by * BLOCK + BLOCK / 2 + (bits(h3, span) - JITTER)
    local dist = sqrt(cx * cx + cy * cy)
    if dist < MIN_DIST then
        return nil
    end

    local tier = pick_tier(dist, h5)
    local kind = pick_kind(tier, h6)

    return {
        bx = bx,
        by = by,
        cx = cx,
        cy = cy,
        dist = dist,
        dir = bits(h4, 4), -- 0=北 1=东 2=南 3=西：该侧铺浅滩（唯一出入口）
        tier = tier,
        kind = kind
    }
end

--==============================================================================
-- per-chunk 记忆化（避免逐 tile 重算 hash）
--==============================================================================

local memo = {}
local memo_seed = nil
local memo_count = 0

local function memo_key(bx, by)
    return (bx + 32768) * 65536 + (by + 32768)
end

local function get_cell(seed, bx, by)
    if memo_seed ~= seed then
        memo = {}
        memo_seed = seed
        memo_count = 0
    end
    local k = memo_key(bx, by)
    local v = memo[k]
    if v == nil then
        if memo_count > 20000 then
            memo = {}
            memo_count = 0
        end
        v = compute_cell(seed, bx, by) or false
        memo[k] = v
        memo_count = memo_count + 1
    end
    if v == false then
        return nil
    end
    return v
end

--==============================================================================
-- 查询 API
--==============================================================================

--- 家单元：中央安全区本身（中心 0,0），dir 由 seed 决定
function Public.home_cell(seed)
    return {
        bx = 0,
        by = 0,
        cx = 0,
        cy = 0,
        dist = 0,
        dir = bits(lcg(lcg((seed or 0) % M)), 4),
        tier = 0,
        kind = 'home',
        home = true
    }
end

--- 查询世界坐标 (wx, wy) 属于哪个单元
-- @return cell|nil, dx, dy （dx/dy 为相对单元中心的偏移）
function Public.cell_at(seed, wx, wy)
    -- 家单元优先（它不在 hash 池里）
    if abs(wx) <= CELL_OUTER and abs(wy) <= CELL_OUTER then
        return Public.home_cell(seed), wx, wy
    end
    local bx = floor(wx / BLOCK)
    local by = floor(wy / BLOCK)
    local cell = get_cell(seed, bx, by)
    if not cell then
        return nil
    end
    local dx = wx - cell.cx
    local dy = wy - cell.cy
    if dx < -CELL_OUTER or dx > CELL_OUTER or dy < -CELL_OUTER or dy > CELL_OUTER then
        return nil
    end
    return cell, dx, dy
end

--- 单元存档键
function Public.cell_key(cell)
    if cell.home then
        return 'home'
    end
    return cell.bx .. ',' .. cell.by
end

--- 环形层判定：返回 'inner' | 'ring' | nil
local function ring_layer(dx, dy)
    local m = abs(dx)
    if abs(dy) > m then
        m = abs(dy)
    end
    if m <= CELL_HALF then
        return 'inner', m
    end
    if m <= CELL_OUTER then
        return 'ring', m
    end
    return nil, m
end

--- 判断 ring tile 位于哪一侧（0=北 1=东 2=南 3=西）
local function ring_side(dx, dy)
    if abs(dx) > abs(dy) then
        if dx > 0 then
            return 1
        end
        return 3
    end
    if dy > 0 then
        return 2
    end
    return 0
end

--==============================================================================
-- 地砖铺设（供 world_17 terrain_generator 逐 tile 调用）
--==============================================================================

--- 已知 cell 与相对坐标时直接铺砖（terrain_generator 走这个，避免重复 hash 查询）
-- @return boolean 是否铺了砖
function Public.paint_cell_tile(surface, position, cell, dx, dy)
    if not cell then
        return false
    end

    local layer = ring_layer(dx, dy)
    if not layer then
        return false
    end

    if layer == 'inner' then
        -- 家单元内部保持原貌（出生基地由 build_base 负责），不覆盖
        if cell.home then
            return false
        end
        local group = KIND_TILE_GROUP[cell.kind] or 'earth'
        surface.set_tiles({{name = tile_of(group), position = position}})
        return true
    end

    -- 水环：dir 侧铺浅滩（可通行），其余深水
    local side = ring_side(dx, dy)
    local name = (side == cell.dir) and tile_of('shallow') or tile_of('deep')
    surface.set_tiles({{name = name, position = position}})
    return true
end

--- 便捷入口：自行查询单元后铺砖（RCON 验收 / 补漆用）
function Public.paint_tile(surface, position, seed)
    local cell, dx, dy = Public.cell_at(seed, position.x, position.y)
    if not cell then
        return false
    end
    return Public.paint_cell_tile(surface, position, cell, dx, dy)
end

--==============================================================================
-- 堡垒避让（导出给 stronghold_generation_algorithm_v2.is_sh_conflict）
--==============================================================================

--- @return boolean true=该点可用；false=落在网格单元（含缓冲）内，禁止建堡垒
function Public.fortress_position_valid(position, surface)
    if not position then
        return true
    end
    local seed = 0
    if surface and surface.valid then
        seed = surface.map_gen_settings.seed or 0
    end
    local reach = CELL_OUTER + FORT_BUFFER
    local wx, wy = position.x, position.y

    -- 家单元
    if abs(wx) <= reach and abs(wy) <= reach then
        return false
    end

    -- 抖动 + 缓冲可能跨大区块边界，检查 3×3
    local bx0 = floor(wx / BLOCK)
    local by0 = floor(wy / BLOCK)
    for ix = -1, 1 do
        for iy = -1, 1 do
            local cell = get_cell(seed, bx0 + ix, by0 + iy)
            if cell then
                if abs(wx - cell.cx) <= reach and abs(wy - cell.cy) <= reach then
                    return false
                end
            end
        end
    end
    return true
end

--==============================================================================
-- storage 结构
--==============================================================================

-- this.grid_war = {
--   cells         = { [key] = {cx, cy, tier, kind, dir, dist, filled, cleared, alive} },
--   spawner_index = { [unit_number] = key },
--   pending       = { {key, cx, cy, ...}, ... },
--   home_done     = bool,
-- }
local function gw_get()
    local this = WPT.get()
    if not this.grid_war then
        this.grid_war = {
            cells = {},
            spawner_index = {},
            pending = {},
            home_done = false
        }
    end
    return this.grid_war
end

Public.get_storage = gw_get

--- terrain_generator 在单元中心 tile 上调用一次，把单元登记进队列
function Public.register_cell(cell)
    if cell.home then
        return
    end
    local gw = gw_get()
    local key = Public.cell_key(cell)
    if gw.cells[key] then
        return
    end
    gw.cells[key] = {
        cx = cell.cx,
        cy = cell.cy,
        dist = cell.dist,
        tier = cell.tier,
        kind = cell.kind,
        dir = cell.dir,
        filled = false,
        cleared = false,
        alive = 0
    }
    gw.pending[#gw.pending + 1] = key
end

--==============================================================================
-- 单元实体填充
--==============================================================================

local SPAWNERS = {'biter-spawner', 'spitter-spawner'}

local function worm_for_distance(dist)
    local pool
    if dist >= 3220 then
        pool = {'big-worm-turret', 'behemoth-worm-turret', 'behemoth-worm-turret'}
    elseif dist >= 2816 then
        pool = {'medium-worm-turret', 'big-worm-turret', 'big-worm-turret'}
    elseif dist >= 1408 then
        pool = {'small-worm-turret', 'medium-worm-turret', 'medium-worm-turret'}
    else
        pool = {'small-worm-turret', 'small-worm-turret', 'medium-worm-turret'}
    end
    local name = pool[math.random(1, #pool)]
    if entity_exists(name) then
        return name
    end
    return 'small-worm-turret'
end

local function chunks_ready(surface, cx, cy)
    local offsets = {-CELL_OUTER, 0, CELL_OUTER}
    for i = 1, 3 do
        for j = 1, 3 do
            local px = cx + offsets[i]
            local py = cy + offsets[j]
            if not surface.is_chunk_generated({x = floor(px / 32), y = floor(py / 32)}) then
                return false
            end
        end
    end
    return true
end

local function random_inner_pos(cx, cy)
    return {
        x = cx + math.random(-INNER_HALF, INNER_HALF),
        y = cy + math.random(-INNER_HALF, INNER_HALF)
    }
end

local function fill_cell(surface, gw, key)
    local data = gw.cells[key]
    if not data or data.filled then
        return
    end
    data.filled = true
    data.alive = 0

    -- 15 个虫巢（决定清空条件，基数 ×5）
    for _ = 1, 15 do
        local name = SPAWNERS[math.random(1, #SPAWNERS)]
        local pos = surface.find_non_colliding_position(name, random_inner_pos(data.cx, data.cy), 20, 1)
        if pos then
            local e = surface.create_entity({name = name, position = pos, force = game.forces.enemy})
            if e and e.valid then
                e.destructible = true
                gw.spawner_index[e.unit_number] = key
                data.alive = data.alive + 1
            end
        end
    end

    -- 30 座沙虫（worm turret，按距离升级；不计入清空判定，基数 ×5）
    for _ = 1, 30 do
        local name = worm_for_distance(data.dist)
        local pos = surface.find_non_colliding_position(name, random_inner_pos(data.cx, data.cy), 20, 1)
        if pos then
            surface.create_entity({name = name, position = pos, force = game.forces.enemy})
        end
    end

    -- 极端情况：一个虫巢都没放下 → 直接判定为已清空并发奖，避免死格
    if data.alive == 0 then
        Public.grant_reward(surface, key)
    end
end

--==============================================================================
-- 家单元：4 基础矿各 500k（总量 2M）
--==============================================================================

local HOME_ORES = {
    {name = 'iron-ore', sx = -30, sy = -30},
    {name = 'copper-ore', sx = 12, sy = -30},
    {name = 'coal', sx = -30, sy = 12},
    {name = 'stone', sx = 12, sy = 12}
}

local function fill_home(surface)
    local per_patch = 500000
    for _, ore in ipairs(HOME_ORES) do
        local spots = {}
        for x = ore.sx, ore.sx + 18 do
            for y = ore.sy, ore.sy + 18 do
                if surface.can_place_entity({name = ore.name, position = {x = x, y = y}, amount = 1}) then
                    spots[#spots + 1] = {x = x, y = y}
                end
            end
        end
        if #spots > 0 then
            local per = floor(per_patch / #spots)
            if per < 1 then
                per = 1
            end
            for _, p in ipairs(spots) do
                surface.create_entity({name = ore.name, position = p, amount = per})
            end
        end
    end
end

--==============================================================================
-- 奖励兑现
--==============================================================================

local function spawn_solid(surface, cx, cy, name, total)
    if not entity_exists(name) then
        log('[grid_war] 资源原型缺失，跳过：' .. tostring(name))
        return 0
    end
    local spots = {}
    for x = cx - ORE_HALF, cx + ORE_HALF do
        for y = cy - ORE_HALF, cy + ORE_HALF do
            if surface.can_place_entity({name = name, position = {x = x, y = y}, amount = 1}) then
                spots[#spots + 1] = {x = x, y = y}
            end
        end
    end
    if #spots == 0 then
        return 0
    end
    local per = floor(total / #spots)
    if per < 1 then
        per = 1
    end
    for _, p in ipairs(spots) do
        surface.create_entity({name = name, position = p, amount = per})
    end
    return #spots
end

-- 流体矿：按「井数 × 单井产量」计
local FLUID_PLAN = {
    ['crude-oil'] = {wells = 4, per_well = 300000},
    ['sulfuric-acid-geyser'] = {wells = 6, per_well = 300000}
}

local function spawn_fluid(surface, cx, cy, name, dist)
    if not entity_exists(name) then
        log('[grid_war] 流体矿原型缺失，跳过：' .. tostring(name))
        return 0
    end
    local plan = FLUID_PLAN[name] or {wells = 4, per_well = 300000}
    -- 距离加成：每 1000m +20%，上限 +100%
    local bonus = 0.2 * floor(dist / 1000)
    if bonus > 1.0 then
        bonus = 1.0
    end
    local amount = floor(plan.per_well * (1 + bonus))

    local placed = 0
    local ring = 14
    for i = 1, plan.wells do
        local angle = (i - 1) * (2 * math.pi / plan.wells) + math.random() * 0.4
        local base = {
            x = cx + floor(math.cos(angle) * ring),
            y = cy + floor(math.sin(angle) * ring)
        }
        local pos = surface.find_non_colliding_position(name, base, 16, 1)
        if pos and surface.can_place_entity({name = name, position = pos, amount = amount}) then
            local e = surface.create_entity({name = name, position = pos, amount = amount})
            if e and e.valid then
                placed = placed + 1
            end
        end
    end
    return placed
end

local function spawn_plants(surface, cx, cy, name)
    if not entity_exists(name) then
        log('[grid_war] 植物原型缺失，跳过：' .. tostring(name))
        return 0
    end
    local target = math.random(200, 300)
    local placed = 0
    local tries = 0
    -- 尝试预算 8 倍：干净单元里成功率很高（实测 287/250），
    -- 但若格内被沙虫/残骸占位，4 倍预算会提前耗尽导致数量不足。
    while placed < target and tries < target * 8 do
        tries = tries + 1
        local pos = {
            x = cx + math.random(-ORE_HALF, ORE_HALF) + math.random(),
            y = cy + math.random(-ORE_HALF, ORE_HALF) + math.random()
        }
        if surface.can_place_entity({name = name, position = pos}) then
            local ok, e = pcall(surface.create_entity, {name = name, position = pos, force = game.forces.neutral})
            if ok and e and e.valid then
                placed = placed + 1
            end
        end
    end
    return placed
end

-- 清空后在单元外侧（远离原点方向）补刷 4 个虫巢
local function spawn_outer_nests(surface, cx, cy)
    local base_angle = math.atan2(cy, cx)
    local placed = 0
    for _ = 1, 4 do
        local angle = base_angle + (math.random() - 0.5) * (2 * math.pi / 3)
        local radius = math.random(100, 180)
        local target = {
            x = cx + math.cos(angle) * radius,
            y = cy + math.sin(angle) * radius
        }
        local name = SPAWNERS[math.random(1, #SPAWNERS)]
        local pos = surface.find_non_colliding_position(name, target, 48, 2)
        if pos then
            local occupied = surface.count_entities_filtered({
                position = pos,
                radius = 64,
                force = game.forces.player,
                limit = 1
            })
            if occupied == 0 then
                local e = surface.create_entity({name = name, position = pos, force = game.forces.enemy})
                if e and e.valid then
                    placed = placed + 1
                end
            end
        end
    end
    return placed
end

--- 兑现某个单元的奖励（虫巢全灭时调用）
function Public.grant_reward(surface, key)
    local gw = gw_get()
    local data = gw.cells[key]
    if not data or data.cleared then
        return
    end
    data.cleared = true

    local mode = KIND_MODE[data.kind] or 'solid'
    if mode == 'solid' then
        -- 基础 2M，随距离增加：每 1000m +20%，≥5km 封顶 ×2 = 4M
        local dfactor = 1 + math.min(1.0, 0.2 * floor(data.dist / 1000))
        spawn_solid(surface, data.cx, data.cy, data.kind, floor(2000000 * dfactor))
    elseif mode == 'fluid' then
        spawn_fluid(surface, data.cx, data.cy, data.kind, data.dist)
    else
        spawn_plants(surface, data.cx, data.cy, data.kind)
    end

    spawn_outer_nests(surface, data.cx, data.cy)

    game.print({
        'amap.grid_war_cell_cleared',
        floor(data.cx),
        floor(data.cy),
        {'entity-name.' .. data.kind}
    })
end

--==============================================================================
-- 事件
--==============================================================================

local function is_grid_world()
    local map = diff.get()
    return map and map.world == WORLD_ID
end

local function active_surface()
    local this = WPT.get()
    if not this.active_surface_index then
        return nil
    end
    local surface = game.surfaces[this.active_surface_index]
    if surface and surface.valid then
        return surface
    end
    return nil
end

--- 每 2 秒处理一批待填充单元（避免一次性卡顿）
local function process_pending()
    if not is_grid_world() then
        return
    end
    local surface = active_surface()
    if not surface then
        return
    end
    local gw = gw_get()

    if not gw.home_done then
        if chunks_ready(surface, 0, 0) then
            fill_home(surface)
            gw.home_done = true
        end
    end

    local budget = 2
    local i = 1
    while i <= #gw.pending and budget > 0 do
        local key = gw.pending[i]
        local data = gw.cells[key]
        if not data then
            table.remove(gw.pending, i)
        elseif chunks_ready(surface, data.cx, data.cy) then
            fill_cell(surface, gw, key)
            table.remove(gw.pending, i)
            budget = budget - 1
        else
            i = i + 1
        end
    end
end

local function on_entity_died(event)
    local entity = event.entity
    if not entity or not entity.valid then
        return
    end
    if entity.type ~= 'unit-spawner' then
        return
    end
    if not is_grid_world() then
        return
    end
    local gw = gw_get()
    local un = entity.unit_number
    if not un then
        return
    end
    local key = gw.spawner_index[un]
    if not key then
        return
    end
    gw.spawner_index[un] = nil
    local data = gw.cells[key]
    if not data then
        return
    end
    data.alive = data.alive - 1
    if data.alive <= 0 and not data.cleared then
        Public.grant_reward(entity.surface, key)
    end
end

Event.on_nth_tick(120, process_pending)
Event.add(defines.events.on_entity_died, on_entity_died)

--==============================================================================
-- 常量导出（供 world_17 与 RCON 验收脚本使用）
--==============================================================================

Public.BLOCK = BLOCK
Public.CELL_HALF = CELL_HALF
Public.CELL_OUTER = CELL_OUTER
Public.DENSITY = DENSITY
Public.JITTER = JITTER
Public.MIN_DIST = MIN_DIST
Public.WORLD_ID = WORLD_ID
Public.compute_cell = compute_cell
Public.get_cell = get_cell
Public.ring_layer = ring_layer
Public.ring_side = ring_side
-- 手动驱动填充队列（无头服无玩家时 tick 暂停，on_nth_tick 不触发，验收脚本用）
Public.process_pending = process_pending
Public.fill_home = fill_home

-- RCON 验收探测入口（/c 内禁止 require，必须走全局）
_GRID = Public

return Public
