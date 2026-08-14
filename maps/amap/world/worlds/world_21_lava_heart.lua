-- maps/amap/world/worlds/world_21_lava_heart.lua
-- 世界 21：熔岩之心
--
-- 地形：中央 256×256 方块（默认随机矿同四季 + 中心 4 块 42×42 矿 4M），
--       周围全是岩浆；岩浆区（方块下方/左右、通道两侧）按背水一战方式
--       随机分布方块矿（7% 概率、ore_sequence 轮流、32×32 单矿 4M / 油井 5 步长 4M）
--       与市场块（4%，3×3 草地 + market）；上方 352×128 通道（火山岩），两侧 6 宽
--       out-of-map 黑暗带，再外全是岩浆；通道顶以上为无限火星地形（火山岩），
--       每 chunk 中心生成 1 块 2×2 矿（40% 方解石 10k/格 / 60% 废料 50k/格），
--       1/90 虫巢（同山谷密度），无撼地虫。
--
-- 战斗：单方向（固定上方，x 对齐 → 沿通道直线南下），火焰塔上限 0，
--       爆炸三件 -50%（单方向硬性要求），堡垒 silo_3_points 3 座仅限通道内。
--
-- 专属机制：
--   1. 出生点传说大矿机 + 传说红箱（passive-provider-chest）：不可击毁/不可挖/不可移动，
--      电力由玩家自行接入（场景不提供）；打死任意敌方虫子 3/250 概率
--      直接生成 1 个方解石到传说红箱。
--   2. 出生市场固定出售工程基座 foundation（500 波内 100 金币 / 500-1500 波 200 /
--      1500 波以上 500）与铸造机 foundry（5000 金币）。
--   3. 野外市场只生成于岩浆区的市场块上（3×3 最小承载面）；全市场价格 ×0.8（market_price_multiplier）。
--   4. 天赋：40 级 +1（tianfu_jiange=40）；首次研究含各色科技瓶 → 发天赋（同世界19）；
--      本图任意玩家天赋 ≤ 60。
--   5. 科技倍率 ×2（main.lua reset_map 在 on_world_start 之后才设回 1，
--      由每局首个 [60] tick 的 finish_reset 兜底覆盖）；开局解锁熔融铸造（foundry 科技）；
--      黄瓶后解锁填海（全局机制）。
--   6. 通关奖励：通关（2000 波）后，新开图时 10% 概率全员得 1 个铸造机，
--      历史最高波数每多 500 波概率 +2%（如 3200 波 → 14%）。

local World = require 'maps.amap.world.framework'
local WPT = require 'maps.amap.table'
local WD = require 'modules.wave_defense.table'
local diff = require 'maps.amap.diff'
local tianfu = require 'maps.amap.tianfu'
local tianfu_table = require 'maps.amap.tianfu_table'
local Helpers = require 'maps.amap.world.world_helpers'
local MT = require 'maps.amap.basic_markets'

--==============================================================================
-- 常量
--==============================================================================

local SQUARE_HALF = 128          -- 256 方块半宽
local CHANNEL_TOP = -480         -- 通道顶部（火星区起点，y 负方向为"上"）
local CHANNEL_BOTTOM = -128      -- 通道底部（方块上边）
local CHANNEL_HALF = 64          -- 通道半宽（128 / 2）
local DARK_HALF = 70             -- 黑暗带外缘（64 + 6）
local TALENT_CAP = 60            -- 天赋上限
local CALCITE_ROLL = 250         -- 杀虫子 3/250 概率掉方解石（直接进传说红箱）
local ORE_TOTAL = 4000000        -- 方块矿储量 4M
local ORE_CHUNK_AMOUNT = math.floor(ORE_TOTAL / (32 * 32))  -- 32×32 每格含量

-- 中心 4 方矿：四象限（参考世界 2 四季布局：左上煤 / 右上铁 / 左下铜 / 右下石）
local CENTER_ORES = {
    {cx = -64, cy = -64, ore = 'coal'},
    {cx = 64, cy = -64, ore = 'iron-ore'},
    {cx = -64, cy = 64, ore = 'copper-ore'},
    {cx = 64, cy = 64, ore = 'stone'},
}
local CENTER_ORE_HALF = 21       -- 中心矿块 42×42 半宽
local CENTER_ORE_AMOUNT = math.floor(ORE_TOTAL / (42 * 42))

-- 火山岩瓦片池（火星地形）
local VOLCANIC_TILES = {
    'volcanic-soil-light',
    'volcanic-soil-dark',
    'volcanic-smooth-stone',
    'volcanic-smooth-stone-warm',
    'volcanic-folds',
}

-- 出生点设施（组装机组 y=-18/-12 上方；矿机朝北，输出口 (0,-27.85) ≈ 红箱 (0,-28)；
-- 电力由玩家自行接入，场景不提供电线杆/电力接口）
local MINER_POS = {x = 0, y = -25}
local CHEST_POS = {x = 0, y = -28}

-- 科技瓶 → 天赋数（同世界19：绿/灰/蓝/紫/黄/白 +1，橙/粉/草 +2，靛 +3，黑 +5）
-- 橙/粉/草/靛/黑 = 冶金/电磁/农业/低温/钷素（Factorio 2.1 Space Age 本体科技瓶）
local SCIENCE_PACK_TALENTS = {
    ['logistic-science-pack'] = 1,
    ['military-science-pack'] = 1,
    ['chemical-science-pack'] = 1,
    ['production-science-pack'] = 1,
    ['utility-science-pack'] = 1,
    ['space-science-pack'] = 1,
    ['metallurgic-science-pack'] = 2,
    ['electromagnetic-science-pack'] = 2,
    ['agricultural-science-pack'] = 2,
    ['cryogenic-science-pack'] = 3,
    ['promethium-science-pack'] = 5,
}

--==============================================================================
-- 地形生成器（逐格）
--==============================================================================

-- 出生点设施：传说大矿机 + 传说红箱（passive-provider-chest，Factorio 标准红箱；
-- 幂等，参考背水一战生物实验室模式；由每 tick 轮询在目标 chunk 确认生成后落地；
-- 若建在"生成中"区块被引擎清理，retry 校验矿机引用失效后自动重建，直至稳定）
local SPAWN_ENTITY_NAMES = {'big-mining-drill', 'passive-provider-chest'}

local function clear_spawn_entities(surface)
    for _, pos in ipairs({MINER_POS, CHEST_POS}) do
        local list = surface.find_entities_filtered({position = pos, radius = 4, name = SPAWN_ENTITY_NAMES})
        for _, e in ipairs(list) do
            if e.valid then e.destroy() end
        end
    end
end

local function build_spawn_facilities(surface)
    local this = WPT.get()
    if this.world21_spawn_ready then return end
    if not surface or not surface.valid then return end

    -- 重建前清理旧设施实体（防重复堆叠）
    clear_spawn_entities(surface)

    -- 创建前清理 3 格内障碍（树/石），确保实体落地
    local function clear_blockers(pos)
        local blockers = surface.find_entities_filtered({
            area = {left_top = {x = pos.x - 3, y = pos.y - 3}, right_bottom = {x = pos.x + 3, y = pos.y + 3}},
            type = {'tree', 'simple-entity'},
        })
        for _, e in pairs(blockers) do
            if e.valid then e.destroy() end
        end
    end
    clear_blockers(MINER_POS)
    clear_blockers(CHEST_POS)

    local miner = surface.create_entity({
        name = 'big-mining-drill',
        position = MINER_POS,
        force = 'player',
        quality = 'legendary',
        create_build_effect_smoke = false,
    })
    if miner and miner.valid then
        miner.destructible = false
        miner.minable_flag = false
        this.world21_calcite_miner = miner
        this.world21_spawn_ready = true
    end
    if not this.world21_spawn_ready then
        -- 矿机创建失败：保持未完成，由轮询重试
        return
    end
    local chest = surface.create_entity({
        name = 'passive-provider-chest',
        position = CHEST_POS,
        force = 'player',
        quality = 'legendary',
        create_build_effect_smoke = false,
    })
    if chest and chest.valid then
        chest.destructible = false
        chest.minable_flag = false
        this.world21_calcite_chest = chest
    end
end

-- 每 tick 轮询：目标 chunk 未生成则请求生成；矿机引用失效（建在"生成中"区块被引擎清理）
-- 则重建，直至稳定（chunk 生成完成后不再清理，收敛 1~2 次）
local function world21_retry_spawn()
    local this = WPT.get()
    if (this and this.world_number or 0) ~= 21 then return end
    local miner = this.world21_calcite_miner
    if miner and miner.valid then
        this.world21_spawn_ready = true
        return
    end
    if this.world21_spawn_ready then
        this.world21_spawn_ready = nil
    end
    local surface = this.active_surface_index and game.surfaces[this.active_surface_index]
    if not surface or not surface.valid then return end
    local cx = math.floor(MINER_POS.x / 32)
    local cy = math.floor(MINER_POS.y / 32)
    if not surface.is_chunk_generated({x = cx, y = cy}) then
        surface.request_to_generate_chunks(MINER_POS, 0)
        return
    end
    build_spawn_facilities(surface)
end

local function terrain_generator(surface, position, seed, get_tile, set_tiles, event, maxs, q, w, x, y, area)
    local px, py = position.x, position.y
    local this = WPT.get()

    -- 中心 4 矿（方块区内，覆盖默认随机矿区域时以 4M 矿为准）
    for _, co in ipairs(CENTER_ORES) do
        if math.abs(px - co.cx) <= CENTER_ORE_HALF and math.abs(py - co.cy) <= CENTER_ORE_HALF then
            return
        end
    end

    -- 岩浆区方块矿登记表查询（抄背水一战：32×32 矿块 / 油井 5 步长 / 市场 3×3 最小承载）
    local key = math.floor(px / 32) * 32 .. ',' .. math.floor(py / 32) * 32
    local oc = this.world21_ore_chunks and this.world21_ore_chunks[key]
    if oc then
        if oc.kind == 'ore' then
            set_tiles({{name = 'grass-1', position = position}})
            if oc.ore == 'crude-oil' then
                -- 油井：5 步长稀疏（同背水一战 world_main.lua：x=2,30,5 步长 5）
                if (px - area.left_top.x) % 5 == 2 and (py - area.left_top.y) % 5 == 2 then
                    surface.create_entity({name = 'crude-oil', position = position, amount = ORE_TOTAL})
                end
            else
                surface.create_entity({name = oc.ore, position = position, amount = oc.amount})
            end
            return
        elseif oc.kind == 'market' then
            -- 市场：不铺整块草地，仅 3×3 最小承载面（market 碰撞框 ±1.4 需 3 格地面），
            -- 由中心格一次性铺 9 格 + 创建市场；其余格直接 return 避免铺岩浆
            local mcx, mcy = area.left_top.x + 16, area.left_top.y + 16
            if math.abs(px - mcx) <= 1 and math.abs(py - mcy) <= 1 then
                if px == mcx and py == mcy then
                    local tiles = {}
                    for dx = -1, 1 do
                        for dy = -1, 1 do
                            tiles[#tiles + 1] = {name = 'grass-1', position = {x = mcx + dx, y = mcy + dy}}
                        end
                    end
                    surface.set_tiles(tiles)
                    MT.mountain_market(surface, {x = mcx, y = mcy}, oc.rarity)
                end
                return
            end
            -- 3×3 外：落到区域判断（岩浆）
        end
    end

    -- 区域判断
    if math.abs(px) <= SQUARE_HALF and math.abs(py) <= SQUARE_HALF then
        -- 256 方块：默认地形与随机矿（同四季 quarter 配置），不做处理
        return
    elseif math.abs(px) <= CHANNEL_HALF and py >= CHANNEL_TOP and py <= CHANNEL_BOTTOM then
        -- 通道：火山岩（可行走可建造，虫子南下通道）
        set_tiles({{name = VOLCANIC_TILES[math.random(1, #VOLCANIC_TILES)], position = position}})
    elseif math.abs(px) > CHANNEL_HALF and math.abs(px) <= DARK_HALF and py >= CHANNEL_TOP and py <= CHANNEL_BOTTOM then
        -- 黑暗带：黑色虚空，不可穿越（若该格属于登记的矿块则已被上方分支铺 grass）
        set_tiles({{name = 'out-of-map', position = position}})
    elseif py <= CHANNEL_TOP then
        -- 火星地形：火山岩为主 + 稀疏岩浆分布（5%，点状岩浆流淌感；
        -- 方解石/废料由 on_chunk_generated 每 chunk 中心生成 2×2 矿）+ 虫巢（1/90，同山谷密度）
        if math.random(1, 100) <= 5 then
            set_tiles({{name = 'lava', position = position}})
        else
            set_tiles({{name = VOLCANIC_TILES[math.random(1, #VOLCANIC_TILES)], position = position}})
        end
        if math.random(1, 90) == 1 then
            local spawner_name = Helpers.spawner[math.random(1, 2)]
            if Helpers.rand_worm(surface, position) then
                surface.create_entity({name = spawner_name, position = position, force = game.forces.enemy})
            end
        end
    else
        -- 岩浆区：全部岩浆
        set_tiles({{name = 'lava', position = position}})
    end
end

--==============================================================================
-- 区块生成：出生点设施 / 中心矿 / 岛屿登记与清理 / 默认资源清理
--==============================================================================

-- 中心矿块所属锚点 chunk 一次性铺矿（destroy 该块默认矿后逐格铺 4M 矿）
local function build_center_ore(surface, co)
    local min_x, max_x = co.cx - CENTER_ORE_HALF, co.cx + CENTER_ORE_HALF
    local min_y, max_y = co.cy - CENTER_ORE_HALF, co.cy + CENTER_ORE_HALF
    local res = surface.find_entities_filtered({
        area = {left_top = {x = min_x, y = min_y}, right_bottom = {x = max_x + 1, y = max_y + 1}},
        type = 'resource',
    })
    for _, e in pairs(res) do
        if e.valid then e.destroy() end
    end
    for ox = min_x, max_x do
        for oy = min_y, max_y do
            surface.create_entity({name = co.ore, position = {x = ox, y = oy}, amount = CENTER_ORE_AMOUNT})
        end
    end
end

-- 区块生成：中心矿 / 岛屿登记与清理 / 默认资源清理
--（出生点设施由 world21_retry_spawn 每 tick 轮询创建，不依赖 chunk 事件时序）
local function on_chunk_generated(event)
    local this = WPT.get()
    if (this and this.world_number or 0) ~= 21 then return end
    local surface = event.surface
    if not surface or not surface.valid then return end
    if this.active_surface_index and surface.index ~= this.active_surface_index then return end

    local area = event.area
    local lt_x, lt_y = area.left_top.x, area.left_top.y
    local c_cx, c_cy = lt_x + 16, lt_y + 16

    -- 中心 4 矿：各矿块由所属锚点 chunk 一次性铺矿（本 chunk 与矿块相交但不锚点则跳过）
    for _, co in ipairs(CENTER_ORES) do
        local anchor_x = math.floor(co.cx / 32) * 32
        local anchor_y = math.floor(co.cy / 32) * 32
        if lt_x == anchor_x and lt_y == anchor_y then
            build_center_ore(surface, co)
        end
    end

    -- 火星区：每 chunk 中心生成 1 块 2×2 矿（40% 方解石总含量 5k / 60% 废料总含量 20k，
    -- 即每格 1250 / 5000）
    if c_cy <= CHANNEL_TOP then
        local ore_name = 'scrap'
        if math.random(1, 100) <= 40 then
            ore_name = 'calcite'
        end
        local amount = ore_name == 'calcite' and 1250 or 5000
        for dx = 0, 1 do
            for dy = 0, 1 do
                surface.create_entity({
                    name = ore_name,
                    position = {x = lt_x + 15 + dx, y = lt_y + 15 + dy},
                    amount = amount,
                })
            end
        end
    end

    -- 岩浆区方块矿：抄背水一战（world_main.lua 70-109 行）——每 chunk 7% 概率矿块
    --（ore_sequence 轮流：铁/煤/铜/石/油/铀），4% 市场块；仅限岩浆区
    --（方块下方/左右、通道两侧），排除方块区/通道/火星区/通道两侧 6 宽黑暗带
    local in_square = math.abs(c_cx) <= SQUARE_HALF and math.abs(c_cy) <= SQUARE_HALF
    local in_channel = math.abs(c_cx) <= CHANNEL_HALF and c_cy >= CHANNEL_TOP and c_cy <= CHANNEL_BOTTOM
    local in_mars = c_cy <= CHANNEL_TOP
    -- 矿块（整 chunk 32×32）范围与黑暗带（|x| ∈ (64,70]，y ∈ [-480,-128]）相交判定
    local overlaps_dark = lt_y < CHANNEL_BOTTOM and lt_y + 32 > CHANNEL_TOP
        and ((lt_x + 32 > -70 and lt_x < -64) or (lt_x + 32 > 64 and lt_x < 70))
    if not in_square and not in_channel and not in_mars and not overlaps_dark then
        local roll = math.random(1, 100)
        local kind
        if roll <= 7 then
            kind = 'ore'
        elseif roll <= 11 then
            kind = 'market'
        end
        if kind then
            if not this.world21_ore_chunks then this.world21_ore_chunks = {} end
            local entry = {kind = kind, cx = lt_x, cy = lt_y}
            if kind == 'ore' then
                this.ore_sequence_index = this.ore_sequence_index % 6 + 1
                entry.ore = this.ore_sequence[this.ore_sequence_index]
                if entry.ore ~= 'crude-oil' then
                    entry.amount = ORE_CHUNK_AMOUNT
                end
            elseif kind == 'market' then
                entry.rarity = math.floor((math.abs(c_cx) + math.abs(c_cy)) / 70)
            end
            this.world21_ore_chunks[lt_x .. ',' .. lt_y] = entry
        end
    end

    -- 已登记矿块/市场块区域清理默认资源（保证「纯单一矿」，含延伸进方块区边缘的部分）
    if this.world21_ore_chunks then
        for _, oc in pairs(this.world21_ore_chunks) do
            local oc_area = {
                left_top = {x = oc.cx, y = oc.cy},
                right_bottom = {x = oc.cx + 32, y = oc.cy + 32},
            }
            -- 与本 chunk 相交才处理
            if oc_area.right_bottom.x > lt_x and oc_area.left_top.x < lt_x + 32
                and oc_area.right_bottom.y > lt_y and oc_area.left_top.y < lt_y + 32 then
                local res = surface.find_entities_filtered({area = oc_area, type = 'resource'})
                for _, e in pairs(res) do
                    if e.valid then e.destroy() end
                end
            end
        end
    end

    -- 默认资源/树/自动虫巢分区清理：
    --   方块区：只清 autoplace 生成的 calcite/scrap（保留默认矿同四季）
    --   火星区：保留 calcite/scrap（autoplace 17%），清其它默认资源/树/虫巢
    --   岩浆区/通道：清全部资源/树/虫巢/散兵；黑暗带：全清
    local entities = surface.find_entities_filtered({area = area})
    for _, e in pairs(entities) do
        if e.valid then
            local px, py = e.position.x, e.position.y
            local in_square_e = math.abs(px) <= SQUARE_HALF and math.abs(py) <= SQUARE_HALF
            local in_mars_e = py <= CHANNEL_TOP
            local in_dark = math.abs(px) > CHANNEL_HALF and math.abs(px) <= DARK_HALF
                and py >= CHANNEL_TOP and py <= CHANNEL_BOTTOM
            if in_dark then
                e.destroy()
            elseif in_square_e then
                if e.type == 'resource' and (e.name == 'calcite' or e.name == 'scrap') then
                    e.destroy()
                end
            elseif in_mars_e then
                if e.type == 'resource' then
                    if e.name ~= 'calcite' and e.name ~= 'scrap' then
                        e.destroy()
                    end
                elseif e.type == 'tree' or e.type == 'unit-spawner' or e.type == 'unit' then
                    e.destroy()
                end
            else
                if e.type == 'resource' or e.type == 'tree' or e.type == 'unit-spawner' or e.type == 'unit' then
                    e.destroy()
                end
            end
        end
    end
end

--==============================================================================
-- 方解石掉落：打死任意敌方虫子 3/250 概率直接生成 1 个方解石到传说红箱
--==============================================================================

local function on_entity_died(event)
    local this = WPT.get()
    if (this and this.world_number or 0) ~= 21 then return end
    local entity = event.entity
    if not entity or not entity.valid then return end
    if entity.force.name ~= 'enemy' then return end
    if entity.type ~= 'unit' then return end
    if math.random(1, CALCITE_ROLL) > 3 then return end
    local chest = this.world21_calcite_chest
    if not chest or not chest.valid then return end
    local inv = chest.get_inventory(defines.inventory.chest)
    if inv then
        inv.insert({name = 'calcite', count = 1})
    end
end

--==============================================================================
-- 天赋机制（同世界19）：科技瓶 → 天赋（90k 池 / 不计 20 限购 / 等同顶尖人才），上限 60
--==============================================================================

-- reset_map 期间脚本强制研究的科技（main.lua 开局直接 researched=true 会触发完成事件，
-- 并非玩家真实研究）→ 不触发科技瓶天赋：
--   悬崖炸药 / 高级星岩处理 / 星岩再处理
local SCRIPT_RESEARCH_BLACKLIST = {
    ['cliff-explosives'] = true,
    ['advanced-asteroid-processing'] = true,
    ['asteroid-reprocessing'] = true,
}

local function count_player_talents(player)
    local main_table = WPT.get()
    local skills = main_table.skill and main_table.skill[player.name]
    if not skills then return 0 end
    local n = 0
    for _ in pairs(skills) do
        n = n + 1
    end
    return n
end

local function world21_enqueue_talent(player_index, count)
    local this = WPT.get()
    if not this.world21_talent_queue then
        this.world21_talent_queue = {}
    end
    local e = this.world21_talent_queue[player_index]
    if not e then
        e = {remaining = 0, total = 0}
        this.world21_talent_queue[player_index] = e
    end
    e.remaining = e.remaining + count
    e.total = e.total + count
end

local function world21_process_talent_queue()
    local this = WPT.get()
    if (this and this.world_number or 0) ~= 21 then return end
    local queue = this.world21_talent_queue
    if not queue then return end

    for pidx, e in pairs(queue) do
        local player = game.players[pidx]
        if not player or not player.valid or player.force.name ~= 'player' then
            queue[pidx] = nil
        elseif count_player_talents(player) >= TALENT_CAP then
            queue[pidx] = nil
            player.print({'amap.world19_talent_cap'}, {r = 1, g = 0.4, b = 0.4})
        elseif not player.gui.screen['选择你的天赋'] then
            tianfu.get_new_tianfu(player, 'mid')
            this.tianfu_count[player.index] = (this.tianfu_count[player.index] or 0) - 1
            e.remaining = e.remaining - 1
            if e.remaining <= 0 then
                player.print({'amap.world19_talent_grant', e.total}, {r = 0.4, g = 1, b = 0.4})
                queue[pidx] = nil
            end
        end
    end
end

-- 首次研究含某色科技瓶 → 给「本局还没拿过该瓶天赋」的在线玩家发天赋（按玩家记录，
-- 不再全局按瓶标记）。玩家中途加入 / 离线期间错过 → on_player_joined_game 补发。
local function world21_grant_science_talent(pack, count)
    local this = WPT.get()
    if not this.world21_science_granted then
        this.world21_science_granted = {}
    end
    local pack_tbl = this.world21_science_granted[pack]
    -- 兼容旧存档：旧代码存的是布尔标记（science_granted[pack] = true），按表索引会崩溃，
    -- 遇到非表值重建为玩家记录表（旧标记作废，视为本局重新获得资格）
    if type(pack_tbl) ~= 'table' then
        pack_tbl = {}
        this.world21_science_granted[pack] = pack_tbl
    end
    for _, player in pairs(game.connected_players) do
        if player and player.valid and player.force.name == 'player' then
            if not pack_tbl[player.name] then
                pack_tbl[player.name] = true
                world21_enqueue_talent(player.index, count)
            end
        end
    end
end

local function on_research_finished(event)
    local this = WPT.get()
    if (this and this.world_number or 0) ~= 21 then return end

    local tech = event.research
    if not tech or not tech.valid then return end
    if tech.force.index ~= game.forces.player.index then return end

    if SCRIPT_RESEARCH_BLACKLIST[tech.name] then return end

    local proto = tech.prototype
    local ingredients = proto and proto.research_unit_ingredients
    if not ingredients then return end

    for _, ing in ipairs(ingredients) do
        local pack = ing.name
        local count = SCIENCE_PACK_TALENTS[pack]
        if count then
            world21_grant_science_talent(pack, count)
        end
    end
end

-- 补发：本局已研究过的科技瓶，玩家此前（离线 / 中途加入）没拿过的立即入队
local function world21_grant_missing_science_talents(player)
    if not player or not player.valid or player.force.name ~= 'player' then return end
    local this = WPT.get()
    local granted = this.world21_science_granted
    if not granted then return end
    for pack, pack_tbl in pairs(granted) do
        if type(pack_tbl) == 'table' and not pack_tbl[player.name] then
            local count = SCIENCE_PACK_TALENTS[pack]
            if count then
                pack_tbl[player.name] = true
                world21_enqueue_talent(player.index, count)
            end
        end
    end
end

local function world21_remove_excess_talent(player)
    local main_table = WPT.get()
    local skills = main_table.skill and main_table.skill[player.name]
    if not skills then return end
    local victim = nil
    for k in pairs(skills) do
        victim = k
        break
    end
    if not victim then return end

    skills[victim] = nil
    if main_table.tianfu_enabled and main_table.tianfu_enabled[player.index] then
        main_table.tianfu_enabled[player.index][victim] = nil
    end
    local tpt = tianfu_table.get()
    if tpt.skill_owners and tpt.skill_owners[victim] then
        tpt.skill_owners[victim][player.index] = nil
    end
    if tpt.player_time_skills and tpt.player_time_skills[player.name] then
        tpt.player_time_skills[player.name][victim] = nil
    end
    player.print({'amap.world19_talent_cap'}, {r = 1, g = 0.4, b = 0.4})
end

local function world21_enforce_talent_cap()
    local this = WPT.get()
    if (this and this.world_number or 0) ~= 21 then return end

    for _, player in pairs(game.connected_players) do
        if player and player.valid and player.force and player.force.name == 'player' then
            local n = count_player_talents(player)
            if n >= TALENT_CAP then
                this.tianfu_count[player.index] = 9999
                this.skill_canchoise[player.name] = 0
                this.tianfu_buy_count[player.index] = 25
                this.xuanze[player.index] = 0
                if this.tianfu_enabled and this.tianfu_enabled[player.index] then
                    this.tianfu_enabled[player.index].djrc = false
                end
                local frame = player.gui.screen['选择你的天赋']
                if frame and frame.valid then
                    frame.destroy()
                end
                if n > TALENT_CAP then
                    world21_remove_excess_talent(player)
                end
            end
        end
    end
end

-- 首个 [60] tick 执行：读档清理（同世界19）。服务器刚读档时无玩家在线（客户端加入时
-- 必有玩家），此时清空上一局残留的科技瓶天赋记录（含发放队列）；
-- 重置（reset_map）路径已由 on_world_start 清空，客户端加入后与服务器基于同一
-- game.connected_players 判断（全局同步数据），不会多清 → 无 desync 风险。
-- 并兜底科技倍率 ×2——main.lua reset_map 在 on_world_start 之后才把
-- technology_price_multiplier 设回 1，on_world_start 里设的 2 会被覆盖，
-- 此处每局首个 [60] tick 重设为 2（reset_map 只在本时机前执行一次）
local function world21_finish_reset()
    local this = WPT.get()
    if (this and this.world_number or 0) ~= 21 then return end
    game.difficulty_settings.technology_price_multiplier = 2
    if #game.connected_players == 0 then
        this.world21_science_granted = {}
        this.world21_talent_queue = {}
    end
end

--==============================================================================
-- 通关奖励记录（world_bonus 面板：2000 波解锁，之后每 500 波 +1 档）
--==============================================================================

local function world21_update_bonus_record(wave_number)
    local map = diff.get()
    if not map or not map.world_bonus then return end
    if map.world_bonus[21] == nil then
        map.world_bonus[21] = {unlocked = false, coefficient = 0, max_wave = 0}
    end
    local record = map.world_bonus[21]
    if wave_number <= record.max_wave then return end

    local old_unlocked = record.unlocked
    local old_value = diff.get_world_bonus_value(21, record)
    record.max_wave = wave_number

    local start_wave = World.get_field(21, 'world_bonus_start_wave') or map.world_bonus.start_wave
    local interval = World.get_field(21, 'world_bonus_interval') or map.world_bonus.coefficient_interval
    if wave_number < start_wave then return end
    record.unlocked = true
    local coefficient_increase = math.floor((wave_number - start_wave) / interval)
    record.coefficient = math.min(
        map.world_bonus.base_coefficient + coefficient_increase,
        map.world_bonus.max_coefficient
    )

    local new_value = diff.get_world_bonus_value(21, record)
    if not old_unlocked then
        game.print({'amap.world_bonus_unlocked', 21}, {r = 255, g = 255, b = 0})
    elseif new_value and old_value and new_value > old_value then
        game.print({'amap.world_bonus_increased_value', 21, new_value}, {r = 0, g = 255, b = 0})
    end
end

local function on_tick_bonus()
    local this = WPT.get()
    if (this and this.world_number or 0) ~= 21 then return end
    local wave_number = WD.get('wave_number') or 0
    if wave_number >= 2000 then
        world21_update_bonus_record(wave_number)
    end
end

--==============================================================================
-- 世界进入钩子
--==============================================================================

local function on_world_start(world_number)
    local this = WPT.get()
    if not this then return end

    -- 除出生点外无白嫖组装机（出生点「组装机组」保留）
    this.enable_wild_factorio = false

    -- 科技倍率 ×2（此处会被 main.lua reset_map 稍后设回 1 覆盖，
    -- 真正的兜底在每局首个 [60] tick 的 world21_finish_reset）
    game.difficulty_settings.technology_price_multiplier = 2

    -- baolei_y 由 on_gain_xp / enemy_arty 通道夹逼兜底，此处归零即可

    -- 通关奖励：新开图 10% 概率全员得 1 个铸造机，历史最高波数每多 500 波 +2%
    --（历史最高波数由 tank.lua 写入 map.map_record[21]）
    local map = diff.get()
    local record = map.map_record and map.map_record[21] or 0
    local p = 0
    if record >= 2000 then
        p = 10 + 2 * math.floor((record - 2000) / 500)
    end
    if p > 0 and math.random(1, 100) <= p then
        local granted = false
        for _, player in pairs(game.connected_players) do
            if player and player.valid and player.character and player.character.valid then
                player.insert({name = 'foundry', count = 1})
                granted = true
            end
        end
        if granted then
            game.print({'amap.world21_foundry_reward', p}, {r = 0.4, g = 1, b = 0.4})
        end
    end

    -- 科技瓶天赋本局状态清零（脚本强制研究的科技已被 SCRIPT_RESEARCH_BLACKLIST 拦截，
    -- 重置期不会产生误标记，此处直接清空无时序竞争）。
    this.world21_science_granted = {}
    this.world21_talent_queue = {}
    this.world21_session_tick = game.tick
end

-- 世界内玩家加入：补发此前研究完成但该玩家未领取的科技瓶天赋
local function on_player_joined_game(event)
    local this = WPT.get()
    if (this and this.world_number or 0) ~= 21 then return end
    local player = game.players[event.player_index]
    if player then
        world21_grant_missing_science_talents(player)
    end
end

--==============================================================================
-- gain_xp 钩子：baolei_y 跟踪并夹逼在通道内（堡垒只生成在 256 通道内）
--==============================================================================

local function on_gain_xp(this, player, wave_number)
    if player.physical_surface ~= this.shop.surface then return end
    local y = player.physical_position.y
    if y < this.baolei_y then
        this.baolei_y = y
    end
    if this.baolei_y > CHANNEL_BOTTOM then
        this.baolei_y = CHANNEL_BOTTOM
    end
    if this.baolei_y < CHANNEL_TOP then
        this.baolei_y = CHANNEL_TOP
    end
end

--==============================================================================
-- 注册到框架
--==============================================================================

World.register(21, {
    --==========================================================================
    -- 元数据
    --==========================================================================
    name_key = 'amap.world_name_21',
    desc_key = 'amap.world_name_info_21',
    selectable = true,

    --==========================================================================
    -- 时间与地形
    --==========================================================================
    -- 首波虫子延迟：3600 秒（60 刻/秒）
    time_limit = 3600 * 60,

    -- 方块区默认随机矿同四季（quarter 同款），禁自动虫巢（火星区手动放置）
    surface_config_name = 'world21',

    -- 地图尺寸：默认（无限），区域边界由 terrain_generator 铺 lava/out-of-map 实现
    map_settings = nil,

    terrain_generator = terrain_generator,

    -- 不生成默认野外建筑/石头？否：保留宝箱/史诗木箱（市场/组装机分支由其它开关禁用）
    --（注意：ywjz 的市场分支 weight_shop=0 与 rand_box 岩浆检查见 world_helpers.lua）

    --==========================================================================
    -- 战斗规则
    --==========================================================================
    -- 单方向世界：火焰塔上限 0
    max_flame = 0,

    -- 虫子固定从上方（通道）南下：k=4 左上方向 + 强制 x 对齐
    biter_spawn_rule = {
        k_value = 4,
        force_x_align = true,
    },

    -- 单方向硬性要求：爆炸类伤害 -50%
    ammo_damage_modifiers = {
        ['grenade'] = -0.5,
        ['landmine'] = -0.5,
        ['artillery-shell'] = -0.5,
    },

    -- 污染与虫巢成长同山谷（默认参数）
    enemy_expansion = nil,

    --==========================================================================
    -- 堡垒生成：单方向 3 座，只生成在 256 通道内；核弹发射井同单方向规则
    --==========================================================================
    arty_settings = {
        interval = 35,
        mode = 'silo_3_points',
        -- 通道 y 区间（[上, 下]）：堡垒 y 夹逼在通道内
        channel_y = {CHANNEL_TOP, CHANNEL_BOTTOM},
        -- 三点堡垒 x 坐标（通道半宽 64，避开两侧 6 宽黑暗带）
        three_points_x = {-56, 0, 56},
    },

    -- 无撼地虫（波防不生成 demolisher，由 wave_defense/main.lua 消费）
    spawn_demolisher = false,

    --==========================================================================
    -- 星球与科技
    --==========================================================================
    -- 不解锁星球（表面解锁：黄瓶后仅解锁填海，见 landfill_allowed 与 functions.lua 全局机制）
    planet_surfaces = nil,
    unlock_planet_technologies = false,
    planet_resource_boost = false,

    -- 开局解锁熔融铸造（foundry 科技：铸造厂 + 熔融铁/铜配方）
    unlocked_technologies = {'foundry'},

    -- 填海：不在此开局启用，黄瓶（utility-science-pack）研究后由全局机制解锁
    landfill_allowed = false,

    -- 传说木箱可用（不声明 disable_legendary_wood_chest）

    --==========================================================================
    -- 通关奖励：通关（2000 波）后新开图 10% 概率全员得 1 铸造机，每多 500 波 +2%
    --（发放逻辑在 on_world_start，此处仅用于 GUI 面板显示与记录）
    --==========================================================================
    world_bonus_type = {
        name = 'foundry_chance_bonus',
        custom_type = 'function',
        base_value = 10,
        growth_value = 2,
    },
    world_bonus_start_wave = 2000,
    world_bonus_interval = 500,
    joins_solar_system_edge = true,

    --==========================================================================
    -- 专属机制
    --==========================================================================
    -- 天赋间隔：40 级 +1（RPG 玩家等级，由 tianfu.lua 消费）
    tianfu_jiange = 40,

    -- 全市场价格 ×0.8（rock.lua refresh_shop / basic_markets.lua mountain_market 消费）
    market_price_multiplier = 0.8,

    -- 世界进入钩子
    on_world_start = on_world_start,

    -- gain_xp 钩子：baolei_y 跟踪（夹逼通道）
    on_gain_xp = on_gain_xp,

    --==========================================================================
    -- 声明式事件订阅（framework.lua 统一分发）
    --==========================================================================
    events = {
        [defines.events.on_chunk_generated] = on_chunk_generated,
        [defines.events.on_entity_died] = on_entity_died,
        [defines.events.on_research_finished] = on_research_finished,
        [defines.events.on_player_joined_game] = on_player_joined_game,
    },

    nth_tick = {
        [1] = {
            world21_retry_spawn,
        },
        [60] = {
            world21_finish_reset,
            on_tick_bonus,
            world21_enforce_talent_cap,
            world21_process_talent_queue,
        },
    },
})
