-- maps/amap/world/worlds/world_21_lava_heart.lua
-- 世界 21：熔岩之心（2026-08 改版）
--
-- 地形（自下而上）：
--   主基地：288×288 方块（默认随机矿同四季 + 中心 4 块 40×40 矿各 4M），
--           可通过「基地扩张」机制向左/右/下生长（新机制1）；
--   防御通道：384 高（y ∈ [-528,-144]）、128 宽火山岩地形带 5% 岩浆小块，
--           两侧 40 格 out-of-map 黑暗带（64 < |x| ≤ 104）；
--   虫巢通道：防御通道上方 |x| ≤ 104（208 宽）无限延伸的地球草地地形，
--           两侧全岩浆；虫子/虫巢/沙虫生成规则与世界11失落之城完全一致
--           （逐格 1/90 虫巢+沙虫），区域更宽故整宽生效；
--   岩浆区（方块下方/左右、通道两侧）：按背水一战方式随机分布方块矿
--           （6% 概率、ore_sequence 轮流、32×32 单矿 2M / 油井每井 4M）
--           与市场块（4%，3×3 草地 + market）；虫巢通道内同样滚动，
--           但市场为品质市场（见下）；虫巢通道两侧岩浆不生成任何矿/市场块。
--
-- 战斗：单方向（固定上方，x 对齐 → 沿通道直线南下），火焰塔上限 0，
--       爆炸三件 -50%（单方向硬性要求）；
--       堡垒改山谷生成模式（only_below：只生成在 x 轴以下/y≥0 半圈螺旋搜索），
--       存活堡垒数 > 8 时创建敌方核弹发射井（每 3 分钟警告后发射 atomic-rocket）。
--
-- 专属机制：
--   1. 出生点传说大矿机 + 传说红箱（passive-provider-chest）：不可击毁/不可挖/不可移动，
--      打死任意敌方虫子 3/250 概率直接生成 1 个方解石到传说红箱。
--   2. 出生市场固定出售工程基座 foundation（永久 44 金币，不受波次影响）与
--      铸造机 foundry（5000 金币）、传说插件塔 beacon（阶梯价），并保证有机甲
--      mech-armor 出售（69000 金币）——由本模块每秒巡检改写（rock.lua 共享代码不动）。
--   3. 野外市场只生成于岩浆区市场块上；全市场价格恢复原价（无折扣）。
--      虫巢通道内的市场块与岩浆区普通市场完全一致（随机物品随机价格），
--      仅额外为每件在售商品追加一份「精良」品质条目（售价 = 普通售价 ×2）；
--      虫巢通道内禁止方块矿生成。
--   4. 天赋：45 级 +1（tianfu_jiange=45）；首次研究含各色科技瓶 → 发天赋（同世界19）；
--      本图任意玩家天赋 ≤ 60。
--   5. 科技倍率 ×1（默认）；开局解锁熔融铸造（foundry 科技）；黄瓶后解锁填海（全局机制）。
--   6. 通关奖励：通关（1500 波）后，新开图时 10% 概率全员得 1 个铸造机，
--      历史最高波数每多 500 波概率 +2%（如 2700 波 → 14%）。
--   7. 新机制1 基地扩张：每研发 1 个科技 → 左右各扩 2 列 + 向下扩 2 行；
--      任一玩家累计击杀 4444 只虫 → 同样扩张 2 格（播报）。
--      与方块矿（含油井）/市场/堡垒占地重叠的格子保持原样。
--   8. 新机制2 撼地虫：波次 ≥1 起每 20 分钟在「离玩家基地最近的敌方虫巢」再往北 96 格处
--      生成 1 条撼地虫（<1000 小型 / 1000~2000 中型 / >2000 大型），生成前把该点周边 ±96
--      预生成（保证分段身体落在已生成区块、避免被引擎回收）；
--      活动范围 = 虫巢通道：只有进入防御通道（y > -528）才清除，北/侧向越出预生成区
--      teleport 拉回出生点（不消失）；无超时自动消失，仅在下一条刷新时旧的一只让位；
--      击杀后基地扩张 5 格，全体玩家得金币与工程基座、击杀者得额外金币并广播。

local World = require 'maps.amap.world.framework'
local WPT = require 'maps.amap.table'
local WD = require 'modules.wave_defense.table'
local diff = require 'maps.amap.diff'
local tianfu = require 'maps.amap.tianfu'
local tianfu_table = require 'maps.amap.tianfu_table'
local Helpers = require 'maps.amap.world.world_helpers'
local MT = require 'maps.amap.basic_markets'
local enemy_arty = require 'maps.amap.enemy_arty'
local Task = require 'utils.task'
local Token = require 'utils.token'

--==============================================================================
-- 常量
--==============================================================================

local SQUARE_HALF = 144          -- 主基地 288 半宽
local CHANNEL_TOP = -528         -- 防御通道顶部（虫巢通道起点，负方向为"上"）
local CHANNEL_BOTTOM = -144      -- 防御通道底部（主基地上边）
local CHANNEL_HALF = 64          -- 防御通道半宽（128 / 2）
local DARK_HALF = 104            -- 黑暗带外缘（64 + 40）；也是虫巢通道半宽（208 / 2）
local TALENT_CAP = 60            -- 天赋上限
local CALCITE_ROLL = 250         -- 杀虫子 3/250 概率掉方解石（直接进传说红箱）
local ORE_TOTAL = 4000000        -- 油井每井储量（保持 4M 不变）
local ORE_CHUNK_TOTAL = 2000000  -- 方块矿储量 2M（原 4M）
local ORE_CHUNK_AMOUNT = math.floor(ORE_CHUNK_TOTAL / (32 * 32))  -- 32×32 每格含量
local ORE_ROLL = 6               -- 区块矿块概率 6%（原 7%）
local MARKET_ROLL = 4            -- 区块市场块概率 4%（不变）

-- 中心 4 方矿：四象限（参考世界 2 四季布局：左上煤 / 右上铁 / 左下铜 / 右下石）
local CENTER_ORES = {
    {cx = -64, cy = -64, ore = 'coal'},
    {cx = 64, cy = -64, ore = 'iron-ore'},
    {cx = -64, cy = 64, ore = 'copper-ore'},
    {cx = 64, cy = 64, ore = 'stone'},
}
local CENTER_ORE_HALF = 20       -- 中心矿块 40×40 半宽（原 42×42）
local CENTER_ORE_AMOUNT = math.floor(ORE_TOTAL / (CENTER_ORE_HALF * CENTER_ORE_HALF * 4))

-- 火山岩瓦片池（火星地形，防御通道用）
local VOLCANIC_TILES = {
    'volcanic-soil-light',
    'volcanic-soil-dark',
    'volcanic-smooth-stone',
    'volcanic-smooth-stone-warm',
    'volcanic-folds',
}

-- 地球草地瓦片池（虫巢通道用，加权随机）
local GRASS_TILES = {
    {'grass-1', 5},
    {'grass-2', 2},
    {'grass-3', 2},
    {'grass-4', 1},
}

-- 出生点设施（组装机组 y=-18/-12 上方；矿机朝北，输出口 (0,-27.85) ≈ 红箱 (0,-28)；
-- 电力由玩家自行接入，场景不提供电线杆/电力接口）
local MINER_POS = {x = 0, y = -25}
local CHEST_POS = {x = 0, y = -28}

-- 出生市场巡检：工程基座永久 44 金 / 机甲 69000 金（rock.lua 共享代码不改，
-- 由本模块每秒把 refresh_shop 生成的波次价改写回固定价）
local FOUNDATION_PRICE = 44
local MECH_ARMOR_PRICE = 69000

-- 新机制1：基地扩张
local KILL_EXPAND_THRESHOLD = 4444     -- 玩家累计击杀触发阈值（每 4444 重置积累）
local EXPAND_RESEARCH_TILES = 2        -- 每研发 1 个科技扩张格数（左右各 N 列 + 下 N 行）
local EXPAND_KILL_TILES = 2            -- 杀虫触发扩张格数
local EXPAND_DEMOLISHER_TILES = 5      -- 击杀撼地虫扩张格数

-- 新机制2：撼地虫
local DEMO_INTERVAL_TICKS = 20 * 60 * 60   -- 每 20 分钟生成 1 条
local DEMO_SPAWN_NORTH_OFFSET = 96         -- 生成点在「离基地最近虫巢」再往北偏移 96 格
local DEMO_PREGEN_RADIUS = 96              -- 生成点周边预生成半径（保证分段身体落在已生成区块）
local DEMOLISHER_NAMES = {
    ['small-demolisher'] = true,
    ['medium-demolisher'] = true,
    ['big-demolisher'] = true,
}
-- 击杀撼地虫奖励：{全员金币, 全员工程基座, 击杀者额外金币}（小/中/大）
local DEMOLISHER_REWARDS = {
    ['small-demolisher'] = {coin = 1000, foundation = 30, killer_coin = 5000},
    ['medium-demolisher'] = {coin = 3000, foundation = 90, killer_coin = 15000},
    ['big-demolisher'] = {coin = 5000, foundation = 150, killer_coin = 25000},
}-- 堡垒核弹井：存活堡垒数 > 8 时创建发射井；之后每 3 分钟警告并发射一枚核弹
local FORTRESS_NUKE_THRESHOLD = 8
local NUKE_INTERVAL_TICKS = 60 * 60 * 3

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
-- 小工具
--==============================================================================

-- 击杀归属玩家（角色 / 战斗机器人 last_user / 载具司机与乘客，参考 modules/rpg/main.lua）
local function world21_get_kill_players(cause)
    if not cause or not cause.valid then return {} end
    local t = cause.type
    if t == 'character' then
        return cause.player and {cause.player} or {}
    elseif t == 'combat-robot' then
        local lu = cause.last_user
        if lu then
            local p = game.players[lu.index]
            return p and p.valid and {p} or {}
        end
        return {}
    elseif t == 'car' or t == 'spider-vehicle' then
        local players = {}
        local driver = cause.get_driver()
        if driver and driver.player then players[#players + 1] = driver.player end
        local passenger = cause.get_passenger()
        if passenger and passenger.player then players[#players + 1] = passenger.player end
        return players
    end
    return {}
end

-- 计入“虫”的受害者：敌方单位 / 蠕虫炮塔 / 撼地虫（虫巢与普通炮塔不算）
local function world21_is_worm_kill(entity)
    local t = entity.type
    if t == 'unit' or t == 'segmented-unit' then return true end
    if t == 'turret' and string.find(entity.name, '-worm-turret', 1, true) then return true end
    return false
end

-- 加权随机草地瓦片
local function pick_grass_tile()
    local r = math.random(1, 10)
    local acc = 0
    for _, gt in ipairs(GRASS_TILES) do
        acc = acc + gt[2]
        if r <= acc then
            return gt[1]
        end
    end
    return 'grass-1'
end

-- 确保目标区域所在区块已生成（扩张/补丁铺地前置）。
-- 本图逐格 Lua 生成器很重（单区块同步生成需数秒），force_generate_chunk_requests
-- 又是同步批量执行，大半径请求会冻结游戏数分钟 —— 因此逐个缺块小半径请求、
-- 多轮补齐（同 tick 内 request+force 有引擎时序竞争，靠多轮收敛）。
-- 实际游戏中扩张发生在基地周边，相关区块早已生成，此函数通常零开销。
-- 返回 true=目标区域全部已生成，false=仍缺块（调用方决定是否跳过本次操作）
local function ensure_area_generated(surface, min_x, min_y, max_x, max_y)
    for _ = 1, 3 do
        local pending = {}
        for cx = math.floor(min_x / 32), math.floor(max_x / 32) do
            for cy = math.floor(min_y / 32), math.floor(max_y / 32) do
                if not surface.is_chunk_generated({x = cx, y = cy}) then
                    pending[#pending + 1] = {x = cx, y = cy}
                end
            end
        end
        if #pending == 0 then return true end
        for _, c in ipairs(pending) do
            surface.request_to_generate_chunks({x = c.x * 32 + 16, y = c.y * 32 + 16}, 16)
            surface.force_generate_chunk_requests()
        end
    end
    return false
end

-- 扩张占地判定：与方块矿（含油井）/ 市场 / 堡垒地基重叠的格子不生成新土地
local function world21_tile_blocked(surface, x, y)
    local pos = {x = x, y = y}
    local res = surface.find_entities_filtered({type = 'resource', position = pos, limit = 1})
    if res and #res > 0 then
        return true
    end
    local mkt = surface.find_entities_filtered({name = 'market', position = pos, radius = 2, limit = 1})
    if mkt and #mkt > 0 then
        return true
    end
    local arty = enemy_arty.get('arty')
    if arty then
        for _, data in pairs(arty) do
            local rp = data and data.roboport
            if rp and rp.valid then
                local p = rp.position
                if math.abs(x - p.x) <= 22 and math.abs(y - p.y) <= 22 then
                    return true
                end
            end
        end
    end
    return false
end

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

-- 虫巢通道市场：与岩浆区普通市场完全一致（随机物品随机价格，全价无折扣），
-- 再为每个在售商品追加一份「精良」品质条目，售价为该商品普通售价的 2 倍。
-- 即每件商品都有 普通 + 精良 两档售卖；没有只卖普通或只卖精良的市场。
local function world21_build_quality_market(surface, position, rarity)
    local mrk = MT.mountain_market(surface, position, rarity)
    if not mrk or not mrk.valid then return nil end
    local base_items = mrk.get_market_items()
    if #base_items == 0 then return mrk end
    local out = {}
    for _, item in ipairs(base_items) do
        out[#out + 1] = item
        local offer = item.offer
        local base_price = item.price and item.price[1] and item.price[1].count
        if offer and offer.type == 'give-item' and base_price then
            local twin = table.deepcopy(item)
            twin.offer.quality = 'uncommon'
            twin.price[1].count = math.max(1, math.floor(base_price * 2 + 0.5))
            out[#out + 1] = twin
        end
    end
    mrk.clear_market_items()
    for _, entry in ipairs(out) do
        mrk.add_market_item(entry)
    end
    return mrk
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
                -- 油井：5 步长稀疏（同背水一战 world_main.lua：x=2,30,5 步长 5），每井 4M
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
                    if oc.quality_market then
                        -- 虫巢通道市场：普通市场 + 每件商品精良版（2 倍价）
                        world21_build_quality_market(surface, {x = mcx, y = mcy}, oc.rarity)
                    else
                        MT.mountain_market(surface, {x = mcx, y = mcy}, oc.rarity)
                    end
                end
                return
            end
            -- 3×3 外：落到区域判断（岩浆/草地）
        end
    end

    -- 区域判断
    if math.abs(px) <= SQUARE_HALF and math.abs(py) <= SQUARE_HALF then
        -- 主基地 288 方块：默认地形与随机矿（同四季 quarter 配置），不做处理
        return
    elseif math.abs(px) <= CHANNEL_HALF and py >= CHANNEL_TOP and py <= CHANNEL_BOTTOM then
        -- 防御通道：火山岩 + 岩浆小块（沿用旧火星区的稀疏岩浆风格），虫子南下通道
        if math.random(1, 100) <= 5 then
            set_tiles({{name = 'lava', position = position}})
        else
            set_tiles({{name = VOLCANIC_TILES[math.random(1, #VOLCANIC_TILES)], position = position}})
        end
    elseif math.abs(px) > CHANNEL_HALF and math.abs(px) <= DARK_HALF and py >= CHANNEL_TOP and py <= CHANNEL_BOTTOM then
        -- 黑暗带（40 格宽）：黑色虚空，不可穿越（若该格属于登记的矿块则已被上方分支铺 grass）
        set_tiles({{name = 'out-of-map', position = position}})
    elseif math.abs(px) <= DARK_HALF and py < CHANNEL_TOP then
        -- 虫巢通道（208 宽，无限向上）：地球草地地形；虫子/虫巢/沙虫与世界11失落之城完全一致
        set_tiles({{name = pick_grass_tile(), position = position}})
        if math.random(1, 90) == 1 then
            local spawner_name = Helpers.spawner[math.random(1, 2)]
            if Helpers.rand_worm(surface, position) then
                surface.create_entity({
                    name = spawner_name,
                    position = position,
                    force = game.forces.enemy,
                })
            end
        end
    else
        -- 岩浆区：全部岩浆（含虫巢通道两侧——不生成方块矿/市场块，见 on_chunk_generated 排除）
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

    -- 岩浆区方块矿：抄背水一战——每 chunk 6% 概率矿块（ore_sequence 轮流：
    -- 铁/煤/铜/石/油/铀，非油 2M）、4% 市场块；排除主基地/防御通道/黑暗带/
    -- 虫巢通道（矿与市场均不生成于两侧岩浆；虫巢通道内禁止方块矿、市场必为品质市场）
    local in_square = math.abs(c_cx) <= SQUARE_HALF and math.abs(c_cy) <= SQUARE_HALF
    local in_channel = math.abs(c_cx) <= CHANNEL_HALF and c_cy >= CHANNEL_TOP and c_cy <= CHANNEL_BOTTOM
    local nest_side_lava = c_cy < CHANNEL_TOP and math.abs(c_cx) > DARK_HALF
    -- 矿块（整 chunk 32×32）范围与黑暗带（|x| ∈ (64,104]，y ∈ [-528,-144]）相交判定
    local overlaps_dark = lt_y < CHANNEL_BOTTOM and lt_y + 32 > CHANNEL_TOP
        and ((lt_x + 32 > -DARK_HALF and lt_x < -CHANNEL_HALF) or (lt_x + 32 > CHANNEL_HALF and lt_x < DARK_HALF))
    -- 与当前主基地矩形相交的区块不再滚动矿/市场块（新机制1 扩张土地不被后期矿块覆盖）
    local b = this.world21_base_bounds
    local overlaps_base = b
        and lt_x < b.max_x + 1 and lt_x + 32 > b.min_x
        and lt_y < b.max_y + 1 and lt_y + 32 > b.min_y
    local in_nest = math.abs(c_cx) <= DARK_HALF and c_cy < CHANNEL_TOP
    if not in_square and not in_channel and not nest_side_lava and not overlaps_dark and not overlaps_base then
        local roll = math.random(1, 100)
        local kind
        if roll <= ORE_ROLL then
            kind = 'ore'
        elseif roll <= ORE_ROLL + MARKET_ROLL then
            kind = 'market'
        end
        -- 虫巢通道内禁止方块矿生成（只保留品质市场块）
        if kind == 'ore' and in_nest then
            kind = nil
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
                -- 虫巢通道内的市场块 → 品质市场（2/3/4/5 品）
                entry.quality_market = in_nest
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
    --   主基地：只清 autoplace 生成的 calcite/scrap（保留默认矿同四季）
    --   黑暗带：全清
    --   虫巢通道：清资源与 autoplace 虫巢（保留树木；敌人由地形生成器按失落之城规则手动放置）
    --   防御通道/岩浆区（含虫巢通道两侧）：清全部资源/树/虫巢/散兵
    local entities = surface.find_entities_filtered({area = area})
    for _, e in pairs(entities) do
        if e.valid then
            local px, py = e.position.x, e.position.y
            local in_square_e = math.abs(px) <= SQUARE_HALF and math.abs(py) <= SQUARE_HALF
            local in_dark_e = math.abs(px) > CHANNEL_HALF and math.abs(px) <= DARK_HALF
                and py >= CHANNEL_TOP and py <= CHANNEL_BOTTOM
            local in_nest_e = math.abs(px) <= DARK_HALF and py < CHANNEL_TOP
            if in_dark_e then
                e.destroy()
            elseif in_square_e then
                if e.type == 'resource' and (e.name == 'calcite' or e.name == 'scrap') then
                    e.destroy()
                end
            elseif in_nest_e then
                if e.type == 'resource' or e.type == 'unit-spawner' then
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
-- 新机制1：基地扩张（科研完成 / 玩家累计杀虫 4444 / 击杀撼地虫）
--   先左 N 列、再右 N 列（高度=当时基地高度），最后下 N 行（宽度=当时基地宽度，含新列）
--==============================================================================

local function world21_get_surface(this)
    return this.active_surface_index and game.surfaces[this.active_surface_index]
end

-- 在一列/一行上铺草地（跳过被矿/市场/堡垒占据的格子）
local function world21_place_land_line(surface, tiles, fixed, from_v, to_v, horizontal)
    for v = from_v, to_v do
        local x, y
        if horizontal then
            x, y = v, fixed
        else
            x, y = fixed, v
        end
        if not world21_tile_blocked(surface, x, y) then
            tiles[#tiles + 1] = {name = 'grass-1', position = {x = x, y = y}}
        end
    end
end

local function world21_expand_base(tiles_count, kill_player_name)
    local this = WPT.get()
    if (this and this.world_number or 0) ~= 21 then return end
    local surface = world21_get_surface(this)
    if not surface or not surface.valid then return end
    local b = this.world21_base_bounds
    if not b then return end
    local n = tiles_count or 1

    -- 三块新增区域整体预生成（避免未生成区块上 set_tiles / 后续矿块滚动竞争）
    ensure_area_generated(surface, b.min_x - n, b.min_y, b.max_x + n, b.max_y + 16)

    -- 先左 N 列、再右 N 列（每列高度=当时基地高度）
    local tiles = {}
    for i = 1, n do
        world21_place_land_line(surface, tiles, b.min_x - 1, b.min_y, b.max_y, false)
        b.min_x = b.min_x - 1
        world21_place_land_line(surface, tiles, b.max_x + 1, b.min_y, b.max_y, false)
        b.max_x = b.max_x + 1
    end
    -- 后下 N 行（每行宽度=当时基地宽度，已包含刚扩张的左右新列）
    for i = 1, n do
        world21_place_land_line(surface, tiles, b.max_y + 1, b.min_x, b.max_x, true)
        b.max_y = b.max_y + 1
    end

    if #tiles > 0 then
        surface.set_tiles(tiles)
    end

    -- 杀虫触发的扩张需要播报（科研/撼地虫触发由各自播报或静默处理）
    if kill_player_name then
        game.print({'amap.world21_expand_kill', kill_player_name}, {r = 0.4, g = 1, b = 0.4})
    end
end

--==============================================================================
-- 新机制2：撼地虫循环（虫巢通道内，离玩家基地最近的敌方虫巢处原地生成，
-- 活动范围限生成点往上 128 格）
--==============================================================================

-- 虫巢通道内离玩家基地最近的敌方虫巢（y 最大且 < CHANNEL_TOP 的 unit-spawner）
local NEST_SEARCH_MIN_Y = CHANNEL_TOP - 2600

local function world21_find_frontier_nest(surface)
    local area = {
        left_top = {x = -DARK_HALF, y = NEST_SEARCH_MIN_Y},
        right_bottom = {x = DARK_HALF, y = CHANNEL_TOP},
    }
    local nests = surface.find_entities_filtered({
        type = 'unit-spawner',
        force = game.forces.enemy,
        area = area,
    })
    local best, best_y
    for _, n in ipairs(nests) do
        if n and n.valid then
            local ny = n.position.y
            if ny < CHANNEL_TOP and (best_y == nil or ny > best_y) then
                best, best_y = n, ny
            end
        end
    end
    return best
end

-- 按波次选撼地虫型号：<1000 小型 / 1000~2000 中型 / >2000 大型
local function world21_demolisher_name(wave_number)
    if wave_number < 1000 then
        return 'small-demolisher'
    elseif wave_number <= 2000 then
        return 'medium-demolisher'
    end
    return 'big-demolisher'
end

local function world21_clear_demolisher_state(this)
    this.world21_demo_ref = nil
    this.world21_demo_spawn_tick = nil
    this.world21_demo_spawn_x = nil
    this.world21_demo_spawn_y = nil
end

local function world21_demolisher_monitor()
    local this = WPT.get()
    if (this and this.world_number or 0) ~= 21 then return end
    local surface = world21_get_surface(this)
    if not surface or not surface.valid then return end

    local wave_number = WD.get('wave_number') or 0

    -- 从波次 = 1 开始计时
    if wave_number >= 1 and not this.world21_demo_epoch then
        this.world21_demo_epoch = game.tick
        this.world21_demo_next = game.tick + DEMO_INTERVAL_TICKS
    end
    if not this.world21_demo_epoch then return end

    -- 先做存活管理（进入防御通道才清除；北/侧越出预生成区则拉回出生点，不消失），
    -- 再判断是否到点生成
    local demo = this.world21_demo_ref
    if demo then
        if not demo.valid then
            world21_clear_demolisher_state(this)
        else
            if not this.world21_demo_spawn_y then
                this.world21_demo_spawn_y = demo.position.y
                this.world21_demo_spawn_x = demo.position.x
            end
            local py = demo.position.y
            -- 活动范围 = 虫巢通道：只有进入防御通道（y > CHANNEL_TOP）才清除；
            -- 北向/横向越出预生成区（分段身体会探进未生成区块被引擎回收）→ teleport 拉回出生点
            local entered_defense = py > CHANNEL_TOP
            local too_far = py < (this.world21_demo_spawn_y - DEMO_PREGEN_RADIUS)
                or math.abs(demo.position.x) > DARK_HALF
            if entered_defense then
                demo.destroy()
                world21_clear_demolisher_state(this)
                game.print({'amap.world21_demolisher_despawn'}, {r = 1, g = 0.6, b = 0.3})
            elseif too_far then
                demo.teleport({x = this.world21_demo_spawn_x, y = this.world21_demo_spawn_y}, surface)
            end
        end
    end

    if game.tick >= (this.world21_demo_next or math.huge) then
        if demo and demo.valid then
            -- 下一只撼地虫刷新：旧的一只让位（销毁，不播报），再生成新的
            demo.destroy()
            world21_clear_demolisher_state(this)
        end
        local nest = world21_find_frontier_nest(surface)
        if not nest then
            -- 虫巢通道还没有虫巢：1 分钟后重试
            this.world21_demo_next = game.tick + 60 * 60
            return
        end
        local name = world21_demolisher_name(wave_number)
        -- 生成点 = 离玩家基地最近的虫巢位置再往北偏移 96 格（保证活动带全在虫巢通道内、
        -- 绝不进入防御通道）；生成前把该点周边 ±96 预生成，保证分段身体落在已生成区块。
        local spawn_pos = {x = nest.position.x, y = nest.position.y - DEMO_SPAWN_NORTH_OFFSET}
        local pregen_ok = ensure_area_generated(
            surface,
            spawn_pos.x - DEMO_PREGEN_RADIUS, spawn_pos.y - DEMO_PREGEN_RADIUS,
            spawn_pos.x + DEMO_PREGEN_RADIUS, spawn_pos.y + DEMO_PREGEN_RADIUS
        )
        if not pregen_ok then
            -- 预生成未完全落地：本轮跳过，1 分钟后重试（避免生成到未生成区块被回收）
            this.world21_demo_next = game.tick + 60 * 60
            return
        end
        local spawned = surface.create_entity({
            name = name,
            position = spawn_pos,
            force = game.forces.enemy,
            direction = 8,  -- 朝南（主基地方向）
            create_build_effect_smoke = false,
        })
        if not spawned then
            for _, radius in ipairs({6, 24, 64}) do
                local pos = surface.find_non_colliding_position(name, spawn_pos, radius, 1)
                if pos then
                    spawned = surface.create_entity({
                        name = name,
                        position = pos,
                        force = game.forces.enemy,
                        direction = 8,
                        create_build_effect_smoke = false,
                    })
                    if spawned then break end
                end
            end
        end
        if spawned and spawned.valid then
            this.world21_demo_ref = spawned
            this.world21_demo_spawn_tick = game.tick
            this.world21_demo_spawn_x = spawned.position.x
            this.world21_demo_spawn_y = spawned.position.y
            this.world21_demo_next = game.tick + DEMO_INTERVAL_TICKS
            game.print({'amap.world21_demolisher_spawn', name, spawned.position.x, spawned.position.y, surface.name}, {r = 1, g = 0.3, b = 0.3})
        else
            this.world21_demo_next = game.tick + 60 * 60
        end
    end
end

-- 撼地虫被击杀奖励：基地扩张 5 格（同科研/杀虫扩张）+ 全员金币/工程基座 + 击杀者金币，并广播
local function world21_demolisher_kill_reward(entity, cause)
    local this = WPT.get()
    world21_expand_base(EXPAND_DEMOLISHER_TILES, nil)

    local reward = DEMOLISHER_REWARDS[entity.name]
    if not reward then return end

    for _, player in pairs(game.connected_players) do
        if player and player.valid and player.force.name == 'player' then
            player.insert({name = 'coin', count = reward.coin})
            player.insert({name = 'foundation', count = reward.foundation})
        end
    end

    local killers = world21_get_kill_players(cause)
    local killer = killers[1]
    if killer and killer.valid and killer.force.name == 'player' then
        killer.insert({name = 'coin', count = reward.killer_coin})
        game.print({'amap.world21_demolisher_reward',
            {'amap.world21_demo_tier_' .. entity.name},
            EXPAND_DEMOLISHER_TILES,
            reward.coin,
            reward.foundation,
            killer.name,
            reward.killer_coin}, {r = 1, g = 0.8, b = 0.2})
    else
        game.print({'amap.world21_demolisher_reward_nk',
            {'amap.world21_demo_tier_' .. entity.name},
            EXPAND_DEMOLISHER_TILES,
            reward.coin,
            reward.foundation}, {r = 1, g = 0.8, b = 0.2})
    end
end

--==============================================================================
-- 堡垒山谷模式监视：存活堡垒数 > 8 → 创建敌方核弹发射井；此后每 3 分钟发射核弹
--==============================================================================

local fire_nuke_token
fire_nuke_token = Token.register(function(silo)
    if not silo or not silo.valid then return end
    local wave_defense_table = WD.get_table()
    local target = wave_defense_table.target
    if not target or not target.valid then return end
    silo.surface.create_entity({
        name = 'atomic-rocket',
        position = {x = target.position.x, y = target.position.y - 100},
        force = game.forces.enemy,
        source = {x = target.position.x, y = target.position.y - 100},
        target = target,
        speed = 1,
    })
    game.print({'amap.enemy_atomic_rocket', target.position.x, target.position.y, silo.surface.name})
    game.print('虫子已经发射核弹！', {255, 0, 0})
end)

local function world21_destroy_silo_tag(this)
    if this.world21_silo_tag and this.world21_silo_tag.valid then
        this.world21_silo_tag.destroy()
    end
    this.world21_silo_tag = nil
end

local function world21_fortress_monitor()
    local this = WPT.get()
    if (this and this.world_number or 0) ~= 21 then return end
    local surface = world21_get_surface(this)
    if not surface or not surface.valid then return end

    -- 发射井引用失效清理
    if this.world21_nuke_silo and not this.world21_nuke_silo.valid then
        this.world21_nuke_silo = nil
        world21_destroy_silo_tag(this)
    end

    -- 重统计存活堡垒数（同步 this.baolei_count）
    local count = enemy_arty.recount_baolei()

    -- 堡垒数 > 8 且尚无发射井 → 在随机存活堡垒旁创建（≤8 格，保证共享
    -- unprotect_nuke_silo 的半径 10 解锁搜索能命中；找不到位置放宽到 14 格）
    if count > FORTRESS_NUKE_THRESHOLD and not this.world21_nuke_silo then
        local positions = enemy_arty.get_valid_fortress_positions()
        if #positions > 0 then
            local anchor = positions[math.random(1, #positions)]
            local pos = surface.find_non_colliding_position('rocket-silo', anchor, 8, 1)
                or surface.find_non_colliding_position('rocket-silo', anchor, 14, 1)
            if pos then
                local silo = surface.create_entity({
                    name = 'rocket-silo',
                    position = pos,
                    force = game.forces.enemy,
                    create_build_effect_smoke = false,
                })
                if silo and silo.valid then
                    silo.destructible = false
                    this.world21_nuke_silo = silo
                    this.world21_silo_tag = game.forces.player.add_chart_tag(surface, {
                        position = pos,
                        icon = {type = 'entity', name = 'rocket-silo'},
                        text = '敌方核弹发射井',
                    })
                    this.world21_nuke_next_fire = game.tick + NUKE_INTERVAL_TICKS
                    game.print({'amap.enemy_rocket_silo', pos.x, pos.y, surface.name}, {255, 0, 0})
                    game.print('注意：你必须摧毁所有堡垒，才能对核弹发射井造成伤害！', {255, 0, 0})
                    game.print('注意：你必须摧毁所有堡垒，才能对核弹发射井造成伤害！！', {255, 0, 0})
                end
            end
        end
    end

    local silo = this.world21_nuke_silo
    if not silo or not silo.valid then return end

    -- 兜底保护解锁：所有堡垒被摧毁时解除无敌（正常路径由共享 unprotect_nuke_silo 处理）
    if count <= 0 and silo.destructible == false then
        silo.destructible = true
        game.print('敌方堡垒已被摧毁！核弹发射井失去保护！', {255, 255, 0})
    end

    -- 发射节奏与 silo 世界一致：每 3 分钟警告后发射一枚 atomic-rocket
    if game.tick >= (this.world21_nuke_next_fire or math.huge) then
        this.world21_nuke_next_fire = game.tick + NUKE_INTERVAL_TICKS
        local target = WD.get_table().target
        if target and target.valid then
            game.print('警告：敌方核弹发射井将在3分钟后发射核弹！', {255, 0, 0})
            game.print('警告：敌方核弹发射井将在3分钟后发射核弹！！', {255, 0, 0})
            game.print('警告：敌方核弹发射井将在3分钟后发射核弹！！！', {255, 0, 0})
            Task.set_timeout_in_ticks(NUKE_INTERVAL_TICKS, fire_nuke_token, silo)
        else
            -- 无有效目标则 1 分钟后重查
            this.world21_nuke_next_fire = game.tick + 60 * 60
        end
    end
end

--==============================================================================
-- 出生市场价格巡检：工程基座永久 44 金 / 机甲 69000 金
--（rock.lua 每次 refresh_shop 会按波次重建商品且共享代码不可改，这里每秒纠偏）
--==============================================================================

local function world21_enforce_shop_prices()
    local this = WPT.get()
    if (this and this.world_number or 0) ~= 21 then return end
    local shop = this.shop
    if not shop or not shop.valid then return end

    local items = shop.get_market_items()
    local changed = false
    local out = {}
    local mech_done = false
    for _, item in ipairs(items) do
        local offer = item.offer
        -- 注意：get_market_items 对无品质商品返回 quality='normal'（非 nil）
        local is_plain_item = offer and offer.type == 'give-item'
            and (offer.quality == nil or offer.quality == 'normal')
        if is_plain_item and offer.item == 'foundation' then
            if item.price[1] and item.price[1].count ~= FOUNDATION_PRICE then
                item.price[1].count = FOUNDATION_PRICE
                changed = true
            end
            out[#out + 1] = item
        elseif is_plain_item and offer.item == 'mech-armor' then
            -- 只保留一条机甲出售（69k）
            if not mech_done then
                if item.price[1] and item.price[1].count ~= MECH_ARMOR_PRICE then
                    item.price[1].count = MECH_ARMOR_PRICE
                    changed = true
                end
                out[#out + 1] = item
                mech_done = true
            else
                changed = true
            end
        else
            out[#out + 1] = item
        end
    end
    if not mech_done then
        out[#out + 1] = {
            price = {{name = 'coin', count = MECH_ARMOR_PRICE}},
            offer = {type = 'give-item', item = 'mech-armor', count = 1},
        }
        changed = true
    end

    if changed then
        shop.clear_market_items()
        for _, item in ipairs(out) do
            shop.add_market_item(item)
        end
    end
end

--==============================================================================
-- 方解石掉落 + 杀虫计数（打死任意敌方虫子 3/250 概率直接生成方解石到传说红箱；
-- 玩家累计击杀 4444 只虫 → 基地扩张）
--==============================================================================

local function on_entity_died(event)
    local this = WPT.get()
    if (this and this.world_number or 0) ~= 21 then return end
    local entity = event.entity
    if not entity or not entity.valid then return end
    if entity.force.name ~= 'enemy' then return end

    -- 撼地虫被击杀 → 基地扩张 5 格 + 金币/工程基座奖励 + 广播
    if DEMOLISHER_NAMES[entity.name] and this.world21_demo_ref == entity then
        world21_clear_demolisher_state(this)
        world21_demolisher_kill_reward(entity, event.cause)
    end

    -- 方解石掉落（原机制不变）
    if entity.type == 'unit' and math.random(1, CALCITE_ROLL) <= 3 then
        local chest = this.world21_calcite_chest
        if chest and chest.valid then
            local inv = chest.get_inventory(defines.inventory.chest)
            if inv then
                inv.insert({name = 'calcite', count = 1})
            end
        end
    end

    -- 杀虫计数（可归属玩家的击杀；每 9999 重置积累并扩张基地）
    if world21_is_worm_kill(entity) then
        local players = world21_get_kill_players(event.cause)
        for _, player in ipairs(players) do
            if player and player.valid and player.force.name == 'player' then
                if not this.world21_kill_accum then this.world21_kill_accum = {} end
                this.world21_kill_accum[player.name] = (this.world21_kill_accum[player.name] or 0) + 1
                if this.world21_kill_accum[player.name] >= KILL_EXPAND_THRESHOLD then
                    this.world21_kill_accum[player.name] = 0
                    world21_expand_base(EXPAND_KILL_TILES, player.name)
                end
            end
        end
    end
end

--==============================================================================
-- 天赋机制（同世界19）：科技瓶 → 天赋（90k 池 / 不计 20 限购 / 等同顶尖人才），上限 60
--==============================================================================

-- reset_map 期间脚本强制研究的科技（main.lua 开局直接 researched=true 会触发完成事件，
-- 并非玩家真实研究）→ 不触发科技瓶天赋，也不触发基地扩张：
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

    -- 新机制1：每研发 1 个科技 → 基地扩张 2 格（不播报）
    world21_expand_base(EXPAND_RESEARCH_TILES, nil)

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
local function world21_finish_reset()
    local this = WPT.get()
    if (this and this.world_number or 0) ~= 21 then return end
    if #game.connected_players == 0 then
        this.world21_science_granted = {}
        this.world21_talent_queue = {}
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

    -- 科技倍率：×1（不干预，main.lua reset_map 保持默认 1）

    -- 通关奖励（铸造机概率）已迁入 diff.apply_world_bonuses 统一路径
    --（custom_bonus_map['foundry_chance_bonus']：每个玩家独立判定，所有地图开图生效）

    -- 科技瓶天赋本局状态清零（脚本强制研究的科技已被 SCRIPT_RESEARCH_BLACKLIST 拦截，
    -- 重置期不会产生误标记，此处直接清空无时序竞争）。
    this.world21_science_granted = {}
    this.world21_talent_queue = {}
    this.world21_session_tick = game.tick

    -- 新机制状态复位：主基地 288×288（x∈[-144,143]，y∈[-144,143]）
    this.world21_base_bounds = {min_x = -SQUARE_HALF, max_x = SQUARE_HALF - 1, min_y = -SQUARE_HALF, max_y = SQUARE_HALF - 1}
    this.world21_kill_accum = {}
    this.world21_demo_epoch = nil
    this.world21_demo_next = nil
    world21_clear_demolisher_state(this)
    this.world21_nuke_silo = nil
    this.world21_nuke_next_fire = nil
    world21_destroy_silo_tag(this)

    -- 矿块/市场块登记表重置：杜绝场景 script.dat（或上一局）残留的旧条目
    --（旧条目无 quality_market 标记，会让虫巢通道市场退化为只卖普通品质；
    -- 登记表本就在区块生成时重新登记，清空零副作用）
    this.world21_ore_chunks = {}
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

    -- 主基地默认随机矿同四季（quarter 同款），禁自动虫巢（虫巢通道手动放置）
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

    -- 虫子固定从上方（防御通道）南下：k=4 左上方向 + 强制 x 对齐
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
    -- 堡垒生成：山谷模式（only_below：围绕目标螺旋搜索、只取 x 轴以下/y≥0 半圈），
    -- 可生成在方块矿上（冲突判定不过滤矿：玩家建筑 110 / 敌堡垒 48 / 铁路 48 照旧）。
    -- 存活堡垒数 > 8 时由本模块监视器创建核弹发射井（world21_fortress_monitor）。
    --==========================================================================
    arty_settings = {
        interval = 35,
        mode = 'only_below',
    },

    -- 波防仍不生成 demolisher（撼地虫由本模块新机制2 自管，仅限虫巢通道）
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
    -- 通关奖励：通关（1500 波）后新开图 10% 概率全员得 1 铸造机，每多 500 波 +2%
    --（发放逻辑在 on_world_start，此处仅用于 GUI 面板显示与记录）
    --==========================================================================
    world_bonus_type = {
        name = 'foundry_chance_bonus',
        custom_type = 'function',
        base_value = 0.1,
        growth_value = 0.02,
    },
    world_bonus_start_wave = 1500,
    world_bonus_interval = 500,
    joins_solar_system_edge = true,

    --==========================================================================
    -- 专属机制
    --==========================================================================
    -- 天赋间隔：45 级 +1（RPG 玩家等级，由 tianfu.lua 消费）
    tianfu_jiange = 45,

    -- 全市场价格恢复原价（不再声明 market_price_multiplier 8 折，
    -- basic_markets.mountain_market / rock.refresh_shop 查不到该字段即跳过打折）

    -- 岩浆瓦片跳过宝箱放置（world_helpers.rand_box 消费）
    chest_lava_skip = true,

    -- 虫巢通道（y ≤ -480）宝箱物品数量倍率（world_helpers.rand_box → Loot.add mult 消费）
    mars_chest_mult = 3,

    -- 世界进入钩子
    on_world_start = on_world_start,

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
            world21_enforce_talent_cap,
            world21_process_talent_queue,
            world21_enforce_shop_prices,
            world21_fortress_monitor,
            world21_demolisher_monitor,
        },
    },
})
