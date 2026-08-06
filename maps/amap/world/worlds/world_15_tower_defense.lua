-- maps/amap/world/worlds/world_15_tower_defense.lua
-- 世界 15：塔防·四面楚歌
--
-- 特点：十字海心地形，四路同时进攻，纯塔防金币经济Boss系统
-- 权威标准：当前代码实现即为世界15设计依据（原 世界15_设计文档.md 已废弃删除）

local World = require 'maps.amap.world.framework'
local WPT = require 'maps.amap.table'
local diff = require 'maps.amap.diff'
local WD = require 'modules.wave_defense.table'
-- 注：本模块不 require utils.event —— 事件订阅一律经 World.register 的 events / nth_tick
-- 声明字段交由 framework.lua 分发（世界模块不得自行注册事件，与世界 1-14 一致）

local world15 = {}

-- 注：世界15 不挂载独立商店模块。金币直接发放到玩家背包（coin），
-- 玩家在出生点市场（market 实体，含 4 种炮塔购买）直接消费。
-- 原 world15_shop.lua（/shop 命令 + 顶部按钮 + 虚拟金币转换桥）已移除。

--==============================================================================
-- 常量
--==============================================================================

-- 地形（单位：格/tile）
-- 中心正方形：256 × 256 tile，半宽 = 128 tile（保持不变）
-- 整十字（含中心 + 4 臂）全长：2560 tile，半长 = 1280 tile（通道为原 320 的 4 倍）
-- 每条臂：从中心边向外延伸 1152 tile（128→1280），宽 256 tile（半宽 128）
local ARM_HALF_WIDTH  = 128    -- 中心正方形 / 通道的半宽（256 tile / 2）
local ARM_HALF_LENGTH = 1280   -- 整十字条的半长（2560 tile / 2），即通道远端到中心的距离（×4）
local SPAWN_DISTANCE  = 200    -- 生怪距离：距中心 200 tile，距正方形边(128)约 72 缓冲，明显短于臂端 1280

-- 虫巢（通道中自然生成的敌方设施）
-- 禁止生成半径 = 中心半宽(128) + 缓冲带(256) = 384 tile，与中心正方形保持距离
local NEST_NO_SPAWN_RADIUS = 384
-- 注：worm-turret 在当前 mod 组合下不存在（create_entity 会抛 Unknown entity name、该格虫巢丢失），
-- 故仅保留 biter / spitter 两种 spawner。
local NEST_TYPES = {"biter-spawner", "spitter-spawner"}
-- 真实虫巢密度 = NEST_DENSITY / (NEST_SCAN_STEP^2)（受虫巢 3x3 占位影响）。
-- 单纯把概率 0.05→0.10 会因高密度下 spawner 互相重叠、find_non_colliding 大量失败而不到真实 2 倍；
-- 故把扫描步长放大到 8（虫巢互不重叠、成功率≈100%），概率设为 0.4：
--   等效密度比 = (0.4/64) ÷ (0.05/16) = 2，即真实虫巢数 ≈ 现状 2 倍。
local NEST_DENSITY = 0.4           -- 每候选格生成概率（真实虫巢密度 ≈ 现状 2 倍）
local NEST_SCAN_STEP = 8            -- 候选格扫描步长（tile），放大以消除虫巢互相重叠

-- 四通道清剿奖励：每 N 波检测一次「野外（四条通道，不含中心正方形）是否已无虫巢」
local W15_NEST_CHECK_INTERVAL  = 50    -- 检测间隔（波）
-- 重铺一次约 1.8 万个候选格 / 约 7 千座虫巢，单帧建完会造成秒级卡顿，
-- 故拆成每 tick 处理固定格数的批处理任务（约 2~3 秒铺完，帧耗时平摊）。
local W15_NEST_REFILL_PER_TICK = 120   -- 重铺时每 tick 处理的候选格上限

-- Boss
local BOSS_INTERVAL = 100              -- 每 100 波

--==============================================================================
-- 波次压力参数（Bug B：四路出兵只出两路 / 每波虫量不足 / 节奏不够激进）
--==============================================================================
-- 【根因】wave_defense 的 spawn_unit_group 按 spawn_positions 逐路生成，但 active_biter_count
-- 只在「每路循环结束后」批量累加，而每只虫的准入检查读的是这个尚未刷新的计数。
-- 世界15 四路各请求 floor(64/1)=64 只，通用上限 max_active_biters=96：
--   第1路 count 0→64 全出；第2路 count 仍读到 64<96 全出，出口 128；
--   第3、4路 count=128≥96 → 全部被拒进血量池。
-- 结果恒定只有两路出兵（场上有残留虫时更少），四路设计意图的 256 只实际只落地 128 只。
--
-- 【破格上限依据】新编制 4 路 × 3 小队 × 28 只 = 336 只必须能全部落地，否则同一 bug 换形式复现；
-- 336 × 1.19 ≈ 400，余下 64 只名额留给上一波残留虫与血量池复活。
-- 上界侧：活跃单位数对 UPS 的开销近似线性，500+ 单位在 unit_group 指令下开始明显掉帧，
-- 400 保留 20% 安全边际。实测阈值由 T2 压测复核，若掉帧则回退 320（=4×3×26 + 8 余量）。
local W15_MAX_ACTIVE_BITERS = 400

-- 每路并排小队编制（被 wave_defense 的 spawn_squad_config 框架字段消费）
--   squads_per_lane 3 ：用户需求「每路三波并排进攻」
--   lateral_spread 24 ：三小队横向占 48 tile，不越出十字通道；24 tile 正好是激光炮塔射程量级，
--                       使三队分别落进不同炮塔的火力覆盖，形成多点压力而非叠成一坨被逐个点掉
--   stagger_ticks  60 ：第2队 +1s、第3队 +2s，落在用户要求的「错峰 1~2 秒」区间；
--                       同时把 336 只的生成开销从单帧摊到三帧，消除生成瞬间的帧尖峰
--   group_size     28 ：旧「每路 64 只」是四路平分前的满编值，实际只有两路能用；
--                       改为 12 队 × 28 = 336 只，相对旧实际落地 128 只 +162%，相对旧设计意图 256 只 +31%。
--                       单队 28 而非 64：unit_group 成员越多，队形维持与路径求解越贵，
--                       28 属 Factorio 原生进攻队列的常见量级。
local W15_SQUAD_CONFIG = {
    squads_per_lane = 3,
    lateral_spread  = 24,
    stagger_ticks   = 60,
    group_size      = 28,
}

-- 世界15 专属波次间隔曲线（被 diff.lua 的 wave_interval_segments 框架字段消费）
-- 对照旧值：通用逻辑常态 1380/diff_k（23s），且 1300~2005 波被强制写死 1380/diff_k。
-- 新曲线在 2000 波区间给到 480 tick（8s），提速 2.9 倍，即「波次间隔动态更激进」的量化落地。
--
-- tail_interval=360（6s）的下限依据：虫子从 200 tile 外走到中心约需 1300 tick，
-- 间隔 360 时在途并存约 3.6 波 × 336 只 ≈ 1200 只的生成需求，早已被 400 活跃上限截断。
-- 再压间隔不会增加场上虫数，只增加 create_unit_group 与寻路开销 —— 360 是收益饱和点。
-- 同理 diff_k_cap=1.5：diff_k 超过 1.5 后的额外压缩同样被上限吃掉，无难度增益。
local W15_WAVE_INTERVAL_SEGMENTS = {
    {hi = 100,  interval = 1200},   -- 20s 开局建塔期（已比通用 2420 激进一倍）
    {hi = 500,  interval = 900},    -- 15s
    {hi = 1000, interval = 720},    -- 12s
    {hi = 2000, interval = 600},    -- 10s
    {hi = 3000, interval = 480},    -- 8s（对应难度锚点 D≈7）
    {hi = 4000, interval = 420},    -- 7s
    tail_interval = 360,            -- 6s
    diff_k_cap    = 1.5,
    min_interval  = 300,            -- 5s 硬下限
}

--==============================================================================
-- 十字地形生成器
--==============================================================================

local function terrain_generator(surface, position, seed, get_tile, set_tiles, event, maxs, q, w, x, y, area)
    -- 注意：x/y 是区块内 0..31 的偏移量；世界坐标必须用 position（绝对坐标），否则整图都会被判为陆地
    -- ⚠️ position 是瓦片整数坐标（左上角）。必须用瓦片中心(+0.5)判定，
    -- 与 is_on_cross_land / enforce_initial_terrain 保持同一约定；否则 y=128/x=128
    -- 边界行会被误判为陆地，海面多出一条草边（自测 sea_ban 捕获：grass-1@*,128）。
    local abs_x = math.abs(position.x + 0.5)
    local abs_y = math.abs(position.y + 0.5)

    local is_land = false
    -- 竖向条（上—下通道 + 中央正方形）：宽 ARM_HALF_WIDTH，长 ARM_HALF_LENGTH
    if abs_x <= ARM_HALF_WIDTH and abs_y <= ARM_HALF_LENGTH then
        is_land = true
    -- 横向条（左—右通道 + 中央正方形）：宽 ARM_HALF_WIDTH，长 ARM_HALF_LENGTH
    elseif abs_y <= ARM_HALF_WIDTH and abs_x <= ARM_HALF_LENGTH then
        is_land = true
    end

    if is_land then
        set_tiles({{name = "grass-1", position = position}})
    else
        set_tiles({{name = "water", position = position}})
    end
end

--==============================================================================
-- 通道虫巢生成（按区块，仅在十字陆地、且距中心 > NEST_NO_SPAWN_RADIUS）
--==============================================================================

-- 判断某点是否落在十字陆地（与地形生成器同判定，保证与海面/对角线海面一致）
local function is_on_cross_land(x, y)
    local abs_x = math.abs(x)
    local abs_y = math.abs(y)
    return (abs_x <= ARM_HALF_WIDTH and abs_y <= ARM_HALF_LENGTH)
        or (abs_y <= ARM_HALF_WIDTH and abs_x <= ARM_HALF_LENGTH)
end

-- 单个候选格的虫巢生成规则（区块生成 与 四通道重铺 共用同一份确定性规则，保证两者布局一致）
-- @param cx,cy 候选格中心的世界坐标；@param r2 中心禁生成半径的平方
-- @return boolean 是否真的建出了一座虫巢
local function try_spawn_nest_at(surface, cx, cy, r2)
    -- 仅限十字陆地（中心正方形 + 4 通道），海面 / 对角线海域禁止
    if not is_on_cross_land(cx, cy) then return false end

    -- 距中心半径内禁止（与中心正方形保持距离）
    if (cx * cx + cy * cy) <= r2 then return false end

    -- 确定性伪随机（坐标哈希），保证每次重开可复现
    local h = math.sin(cx * 12.9898 + cy * 78.233) * 43758.5453
    h = h - math.floor(h)
    if h >= NEST_DENSITY then return false end

    local t = NEST_TYPES[((math.floor(cx) + math.floor(cy)) % #NEST_TYPES) + 1]
    local pos = surface.find_non_colliding_position(t, {x = cx, y = cy}, 4, 1)
    if pos and is_on_cross_land(pos.x, pos.y) then
        surface.create_entity({name = t, position = pos, force = "enemy"})
        return true
    end
    return false
end

local function spawn_nests_in_chunk(event)
    local this = WPT.get()
    if (this and this.world_number or 0) ~= 15 then return end

    -- 用事件自带 surface，且只处理主战场表面（每局由 CS.create_surface 新建，不是 nauvis）
    local surface = event.surface
    if not surface or not surface.valid then return end
    if this.active_surface_index and surface.index ~= this.active_surface_index then return end

    local area = event.area
    local lt = area.left_top
    local rb = area.right_bottom
    local r2 = NEST_NO_SPAWN_RADIUS * NEST_NO_SPAWN_RADIUS

    for gx = lt.x, rb.x, NEST_SCAN_STEP do
        for gy = lt.y, rb.y, NEST_SCAN_STEP do
            try_spawn_nest_at(surface, gx + NEST_SCAN_STEP / 2, gy + NEST_SCAN_STEP / 2, r2)
        end
    end
end

--==============================================================================
-- 四通道清剿奖励
--
-- 每 W15_NEST_CHECK_INTERVAL 波检测一次「野外」（＝十字四条通道，不含中心正方形）：
--   四条通道均无敌方虫巢 → 全体玩家天赋 +1 → 重新把虫巢铺满四条通道（新一轮清剿）。
--==============================================================================

-- 野外 = 十字四臂（不含中心 256×256 正方形）；四个矩形互不重叠，并集即全部通道。
local W15_CHANNEL_AREAS = {
    -- 上通道（北）
    {left_top = {x = -ARM_HALF_WIDTH,  y = -ARM_HALF_LENGTH}, right_bottom = {x =  ARM_HALF_WIDTH,  y = -ARM_HALF_WIDTH}},
    -- 下通道（南）
    {left_top = {x = -ARM_HALF_WIDTH,  y =  ARM_HALF_WIDTH},  right_bottom = {x =  ARM_HALF_WIDTH,  y =  ARM_HALF_LENGTH}},
    -- 左通道（西）
    {left_top = {x = -ARM_HALF_LENGTH, y = -ARM_HALF_WIDTH},  right_bottom = {x = -ARM_HALF_WIDTH,  y =  ARM_HALF_WIDTH}},
    -- 右通道（东）
    {left_top = {x =  ARM_HALF_WIDTH,  y = -ARM_HALF_WIDTH},  right_bottom = {x =  ARM_HALF_LENGTH, y =  ARM_HALF_WIDTH}},
}

-- 判定单条通道是否「已清空」，两个条件缺一不可：
--   ① 该通道所有区块均已生成 —— 虫巢是在 on_chunk_generated 时才落地的，未生成的区块
--      天然查不到虫巢；若把它算作「已清空」，玩家不出门也能白拿奖励，故一律视为未清空；
--   ② 区域内敌方 unit-spawner 数为 0（limit=1 命中即中断，避免整条臂全量枚举）。
local function world15_channel_is_clear(surface, area)
    local cx0 = math.floor(area.left_top.x / 32)
    local cx1 = math.ceil(area.right_bottom.x / 32) - 1
    local cy0 = math.floor(area.left_top.y / 32)
    local cy1 = math.ceil(area.right_bottom.y / 32) - 1
    for cx = cx0, cx1 do
        for cy = cy0, cy1 do
            if not surface.is_chunk_generated({x = cx, y = cy}) then return false end
        end
    end
    return surface.count_entities_filtered({
        area = area, type = 'unit-spawner', force = 'enemy', limit = 1,
    }) == 0
end

-- 全体玩家天赋 +1。
-- tianfu.lua 的发放判定为 `math.floor(level / jiange) > tianfu_count - 1`，
-- 因此把 tianfu_count 减 1 就等于多给一次天赋选择配额（与 rock.lua 商店「购买天赋」同源写法）。
-- 相比直接弹选择界面的好处：不会在战斗/副本中强行弹窗打断，且配额写在存档里，
-- 离线玩家上线后由 tianfu.lua 的周期检查照常点亮顶部「天赋」按钮领取。
local function world15_grant_talent_all(this)
    this.tianfu_count = this.tianfu_count or {}
    local n = 0
    for _, p in pairs(game.players) do
        if p and p.valid then
            this.tianfu_count[p.index] = (this.tianfu_count[p.index] or 0) - 1
            n = n + 1
        end
    end
    return n
end

-- 启动「四通道虫巢重铺」批处理任务（本函数只建任务，实际建造由 world15_nest_refill_tick 分帧执行）
local function world15_start_nest_refill(this)
    local first = W15_CHANNEL_AREAS[1]
    this.world15_nest_refill = {
        arm = 1,
        -- 候选格中心与区块生成时用的是同一张网格（中心 ≡ 4 mod 8），保证重铺布局与开局完全一致
        cx = first.left_top.x + NEST_SCAN_STEP / 2,
        cy = first.left_top.y + NEST_SCAN_STEP / 2,
        created = 0,
    }
end

-- 分帧重铺：每 tick 最多处理 W15_NEST_REFILL_PER_TICK 个候选格；四条通道全部铺完后播报并清任务
local function world15_nest_refill_tick()
    local this = WPT.get()
    if (this and this.world_number or 0) ~= 15 then return end
    local job = this.world15_nest_refill
    if not job then return end

    local surface = this.active_surface_index and game.surfaces[this.active_surface_index]
    if not surface or not surface.valid then
        this.world15_nest_refill = nil
        return
    end

    local r2 = NEST_NO_SPAWN_RADIUS * NEST_NO_SPAWN_RADIUS
    local budget = W15_NEST_REFILL_PER_TICK
    while budget > 0 do
        local area = W15_CHANNEL_AREAS[job.arm]
        if not area then
            -- 四条通道全部铺完
            game.print({'amap.world15_nest_refilled', job.created}, {r = 1, g = 0.6, b = 0.2})
            this.world15_nest_refill = nil
            return
        end

        if try_spawn_nest_at(surface, job.cx, job.cy, r2) then
            job.created = job.created + 1
        end
        budget = budget - 1

        -- 推进游标：先沿 y 扫完一列，再进一列 x；一条通道扫完则换下一条
        job.cy = job.cy + NEST_SCAN_STEP
        if job.cy >= area.right_bottom.y then
            job.cy = area.left_top.y + NEST_SCAN_STEP / 2
            job.cx = job.cx + NEST_SCAN_STEP
            if job.cx >= area.right_bottom.x then
                job.arm = job.arm + 1
                local nxt = W15_CHANNEL_AREAS[job.arm]
                if nxt then
                    job.cx = nxt.left_top.x + NEST_SCAN_STEP / 2
                    job.cy = nxt.left_top.y + NEST_SCAN_STEP / 2
                end
            end
        end
    end
end

-- 每 W15_NEST_CHECK_INTERVAL 波检测一次四条通道的野外虫巢；全清则发奖 + 重铺
local function world15_nest_check_tick()
    local this = WPT.get()
    if (this and this.world_number or 0) ~= 15 then return end
    if this.world15_nest_refill then return end   -- 上一轮重铺尚未铺完，本次不检测

    local wave = WD.get('wave_number') or 0
    if wave <= 0 or wave % W15_NEST_CHECK_INTERVAL ~= 0 then return end
    if (this.world15_last_nest_check_wave or 0) == wave then return end   -- 同一波只检测一次
    this.world15_last_nest_check_wave = wave

    local surface = this.active_surface_index and game.surfaces[this.active_surface_index]
    if not surface or not surface.valid then return end

    for i = 1, #W15_CHANNEL_AREAS do
        if not world15_channel_is_clear(surface, W15_CHANNEL_AREAS[i]) then return end
    end

    -- 四条通道均无虫巢 → 全体玩家天赋 +1
    local granted = world15_grant_talent_all(this)
    game.print({'amap.world15_nest_cleared', wave, granted}, {r = 0.4, g = 1, b = 0.4})

    -- 奖励完成后重新刷新虫巢，重新覆盖四条通道
    world15_start_nest_refill(this)
end

-- 清理岩石：世界15 纯塔防设计，移除地图上所有岩石实体（simple-entity）
local function clear_rocks_in_chunk(event)
    local this = WPT.get()
    if (this and this.world_number or 0) ~= 15 then return end

    -- 用事件自带 surface，且只处理主战场表面（每局由 CS.create_surface 新建，不是 nauvis）
    local surface = event.surface
    if not surface or not surface.valid then return end
    if this.active_surface_index and surface.index ~= this.active_surface_index then return end

    -- 岩石在 Factorio 中 type 均为 simple-entity；世界15 无树（type=tree）、无其它合法 simple-entity
    local rocks = surface.find_entities_filtered {area = event.area, type = 'simple-entity'}
    for _, rock in pairs(rocks) do
        if rock.valid then
            rock.destroy()
        end
    end
end

--==============================================================================
-- 海面禁刷：禁止在海面（十字陆地之外）出现陆地方块与虫子
--==============================================================================
-- 说明：
--   1) 地形残留（海面陆地方块）——根因是开局 soft_reset 里 request_to_generate_chunks
--      在 active_surface_index 赋值前生成初始区块，那批区块跳过了 world_main 的
--      terrain_generator，保留了默认草地。用一次性全表面地形校正修复（只在开局跑一次，
--      在玩家填海之前，故不会破坏用户后续的合法填海——landfill_allowed=true 保留）。
--   2) 海面虫子——唯一能把敌人放到十字外的动态来源是 enemy_expansion（自然扩张）。
--      运行期只清怪、绝不改地块，从而保留玩家填海成果。

-- 移除区域内落在海面（非十字陆地）的敌方实体（Boss 除外，Boss 可能被 find_non_colliding 微调）
local function purge_sea_enemies_in_area(surface, area)
    local enemies = surface.find_entities_filtered({area = area, force = "enemy"})
    for _, e in pairs(enemies) do
        if e.valid and e.name ~= "big-stomper-pentapod"
            and not is_on_cross_land(e.position.x, e.position.y) then
            e.destroy()
        end
    end
end

-- 区块生成时：清除该区块内落在海面的敌方单位/虫巢/虫塔（廉价，仅清怪不改地块）
local function cleanup_sea_enemies_in_chunk(event)
    local this = WPT.get()
    if (this and this.world_number or 0) ~= 15 then return end
    local surface = event.surface
    if not surface or not surface.valid then return end
    if this.active_surface_index and surface.index ~= this.active_surface_index then return end
    purge_sea_enemies_in_area(surface, event.area)
end

-- 一次性开局地形校正：修复 active_surface_index 赋值前生成的初始区块（跳过了 terrain_generator）
-- 将十字陆地强制 grass-1、其余强制 water，并清除海面残留敌人。只跑一次（world15_terrain_fixed）。
local function enforce_initial_terrain()
    local this = WPT.get()
    if not this or this.world_number ~= 15 then return end
    if this.world15_terrain_fixed then return end
    if not this.active_surface_index then return end
    local surface = game.surfaces[this.active_surface_index]
    if not surface or not surface.valid then return end

    for chunk in surface.get_chunks() do
        local lt = {x = chunk.x * 32, y = chunk.y * 32}
        local tiles = {}
        local n = 0
        for dx = 0, 31 do
            for dy = 0, 31 do
                local px, py = lt.x + dx, lt.y + dy
                n = n + 1
                tiles[n] = {
                    name = is_on_cross_land(px + 0.5, py + 0.5) and "grass-1" or "water",
                    position = {x = px, y = py},
                }
            end
        end
        surface.set_tiles(tiles)
        purge_sea_enemies_in_area(surface,
            {left_top = lt, right_bottom = {x = lt.x + 32, y = lt.y + 32}})
    end

    this.world15_terrain_fixed = true
    game.print("[世界15] 已校正开局地形并清除海面残留陆地/虫子", {r = 0.5, g = 1, b = 0.5})
end

-- 运行期安全网：每 10 秒清除整表面海面上的敌人（Boss 除外）。绝不改地块，保留玩家填海。
local function cleanup_sea_enemies_periodic()
    local this = WPT.get()
    if not this or this.world_number ~= 15 then return end
    if not this.active_surface_index then return end
    local surface = game.surfaces[this.active_surface_index]
    if not surface or not surface.valid then return end
    -- 地图 2560×2560（±1280），留余量 ±1400 限定扫描范围
    purge_sea_enemies_in_area(surface,
        {left_top = {x = -1400, y = -1400}, right_bottom = {x = 1400, y = 1400}})
end

-- 注册炮塔到全局表（供 world15_supply_tick 每帧充能，覆盖全部 4 种炮塔）
local function register_turret(turret)
    if not turret or not turret.valid then return false end
    local name = turret.name
    if name ~= "gun-turret" and name ~= "laser-turret" and name ~= "rocket-turret" and name ~= "tesla-turret" then return false end

    local this = WPT.get()
    if not this.world15_registered_turrets then
        this.world15_registered_turrets = {}
    end

    local unit_number = turret.unit_number
    if not unit_number then return false end
    this.world15_registered_turrets[unit_number] = turret
    return true
end

-- 注销炮塔
local function unregister_turret(turret)
    if not turret or not turret.valid then return false end
    local this = WPT.get()
    if not this.world15_registered_turrets then return false end
    this.world15_registered_turrets[turret.unit_number] = nil
    return true
end

-- 波次选弹种（gun/rocket），被 charge_turret 与 world15_supply_tick 共用；自包含无依赖，前置定义以避免前向引用
local function get_ammo_for_wave(name, wave)
    if name == 'gun-turret' then
        if wave <= 100 then return 'firearm-magazine'
        elseif wave <= 300 then return 'piercing-rounds-magazine'
        else return 'uranium-rounds-magazine' end
    elseif name == 'rocket-turret' then
        if wave <= 300 then return 'rocket'
        else return 'explosive-rocket' end
    end
    return nil
end

-- 建造事件即时充能（登记同时补满，免等下一 tick）
local function charge_turret(turret)
    if not turret or not turret.valid then return end
    local n = turret.name
    if n == 'laser-turret' or n == 'tesla-turret' then
        if turret.electric_buffer_size then
            turret.energy = turret.electric_buffer_size
        end
    elseif n == 'gun-turret' or n == 'rocket-turret' then
        local inv = turret.get_inventory(defines.inventory.turret_ammo)
        local wave = WD.get('wave_number') or 0
        local ammo_name = get_ammo_for_wave(n, wave)
        if inv and ammo_name then
            inv.clear()
            inv.insert({name = ammo_name, count = 200})
        end
    end
end

--==============================================================================
-- 特斯拉炮塔放置上限（世界15 平衡：实测后期伤害过高，尤其传说）
--   全服总量上限（跨玩家共享）：普通 22 / 精良 8 / 稀有 10 / 史诗 6 / 传说 4
--   仅在玩家/机器人放下 tesla-turret 时校验；超限则销毁并退还同品质物品，避免玩家损失金币。
--==============================================================================
local W15_TESLA_QUALITY_LIMIT = {
    normal    = 22,
    uncommon  = 10,
    rare      = 8,
    epic      = 6,
    legendary = 4,
}
-- 品质中文名（自包含，不依赖 base locale 的 quality-name.*）
local W15_QUALITY_CN = {
    normal    = '普通',
    uncommon  = '精良',
    rare      = '稀有',
    epic      = '史诗',
    legendary = '传说',
}

-- 统计指定品质的特斯拉炮塔已放置数量（含刚放下的这尊）
local function world15_count_tesla_of_quality(surface, quality_name)
    local list = surface.find_entities_filtered{name = 'tesla-turret'}
    local n = 0
    for _, t in ipairs(list) do
        if t.valid and t.quality and t.quality.name == quality_name then
            n = n + 1
        end
    end
    return n
end

-- 特斯拉炮塔放置上限校验：超限则销毁新炮塔并退还物品（按品质）
local function world15_enforce_tesla_limit(entity, owner)
    if not entity or not entity.valid then return end
    if entity.name ~= 'tesla-turret' then return end
    local q = (entity.quality and entity.quality.name) or 'normal'
    local limit = W15_TESLA_QUALITY_LIMIT[q]
    if not limit then return end
    local surface = entity.surface
    if not surface or not surface.valid then return end
    -- 统计该品质已放置总数（含刚放下的这尊）
    local count = world15_count_tesla_of_quality(surface, q)
    if count <= limit then return end
    -- 超限：销毁并退还同品质物品，提示放置者
    entity.destroy()
    if owner and owner.valid then
        owner.insert({name = 'tesla-turret', count = 1, quality = q})
        owner.print({'amap.world15_tesla_limit', W15_QUALITY_CN[q] or q, limit},
            {r = 1, g = 0.6, b = 0.2})
    end
end

--==============================================================================
-- 火箭炮塔放置上限（世界15 平衡：火箭弹伤害/范围过高，按品质限制数量）
--   全服总量上限（跨玩家共享）：普通 40 / 精良 20 / 稀有 16 / 史诗 12 / 传说 8
--   仅在玩家/机器人放下 rocket-turret 时校验；超限则销毁并退还同品质物品。
--==============================================================================
local W15_ROCKET_QUALITY_LIMIT = {
    normal    = 40,
    uncommon  = 20,
    rare      = 16,
    epic      = 12,
    legendary = 8,
}

-- 统计指定品质的火箭炮塔已放置数量（含刚放下的这尊）
local function world15_count_rocket_of_quality(surface, quality_name)
    local list = surface.find_entities_filtered{name = 'rocket-turret'}
    local n = 0
    for _, t in ipairs(list) do
        if t.valid and t.quality and t.quality.name == quality_name then
            n = n + 1
        end
    end
    return n
end

-- 火箭炮塔放置上限校验：超限则销毁新炮塔并退还物品（按品质）
local function world15_enforce_rocket_limit(entity, owner)
    if not entity or not entity.valid then return end
    if entity.name ~= 'rocket-turret' then return end
    local q = (entity.quality and entity.quality.name) or 'normal'
    local limit = W15_ROCKET_QUALITY_LIMIT[q]
    if not limit then return end
    local surface = entity.surface
    if not surface or not surface.valid then return end
    -- 统计该品质已放置总数（含刚放下的这尊）
    local count = world15_count_rocket_of_quality(surface, q)
    if count <= limit then return end
    -- 超限：销毁并退还同品质物品，提示放置者
    entity.destroy()
    if owner and owner.valid then
        owner.insert({name = 'rocket-turret', count = 1, quality = q})
        owner.print({'amap.world15_rocket_limit', W15_QUALITY_CN[q] or q, limit},
            {r = 1, g = 0.6, b = 0.2})
    end
end

--==============================================================================
-- 建筑区域限制
--==============================================================================

local function on_built_entity(event)
    if (WPT.get() and WPT.get().world_number or 0) ~= 15 then return end

    local entity = event.entity
    if not entity or not entity.valid then return end
    if not event.player_index then return end

    local player = game.get_player(event.player_index)
    if not player then return end

    local pos = entity.position
    -- 建筑限制：仅中心正方形可建造（|x|<=ARM_HALF_WIDTH 且 |y|<=ARM_HALF_WIDTH），通道与海水均禁止
    local abs_x = math.abs(pos.x)
    local abs_y = math.abs(pos.y)
    local on_land = (abs_x <= ARM_HALF_WIDTH and abs_y <= ARM_HALF_WIDTH)
    if not on_land then
        -- 判断是否为玩家手动放置（非系统生成）
        if entity.last_user then
            entity.destroy()
            player.print({"amap.world15_build_restricted"}, {r = 1, g = 0.3, b = 0.3})
        end
    else
        -- 世界15：特斯拉炮塔按品质限制放置数量（超限销毁并退还物品）
        if entity.name == 'tesla-turret' then
            world15_enforce_tesla_limit(entity, player)
        end
        -- 世界15：火箭炮塔按品质限制放置数量（超限销毁并退还物品）
        if entity.valid and entity.name == 'rocket-turret' then
            world15_enforce_rocket_limit(entity, player)
        end
        if not entity.valid then return end  -- 超限已被销毁，跳过后续登记/充能
        -- N-01：中心正方形内 4 种炮塔 minable_flag=false 禁拆
        local name = entity.name
        if name == 'gun-turret' or name == 'laser-turret' or name == 'rocket-turret' or name == 'tesla-turret' then
            entity.minable_flag = false
            -- N-03/N-04: 建造即登记+即时充能（事件注册式，无区域扫描）
            register_turret(entity)
            charge_turret(entity)
        end
    end
end

-- 机器人建造（施工机器人）同样受"仅中心正方形可建"限制，否则会绕过玩家建造限制
local function on_robot_built_entity(event)
    if (WPT.get() and WPT.get().world_number or 0) ~= 15 then return end

    local entity = event.entity
    if not entity or not entity.valid then return end

    local pos = entity.position
    local abs_x = math.abs(pos.x)
    local abs_y = math.abs(pos.y)
    local on_land = (abs_x <= ARM_HALF_WIDTH and abs_y <= ARM_HALF_WIDTH)
    if not on_land then
        entity.destroy()
        local robot = event.robot
        local owner = robot and robot.valid and robot.last_user
        if owner and owner.valid then
            owner.print({"amap.world15_build_restricted"}, {r = 1, g = 0.3, b = 0.3})
        end
    else
        -- 机器人建造时取施工机器人的所有者作为退还/提示对象
        local owner = event.robot and event.robot.valid and event.robot.last_user
        -- 世界15：特斯拉炮塔按品质限制放置数量（超限销毁并退还物品）
        if entity.name == 'tesla-turret' then
            world15_enforce_tesla_limit(entity, owner)
        end
        -- 世界15：火箭炮塔按品质限制放置数量（超限销毁并退还物品）
        if entity.valid and entity.name == 'rocket-turret' then
            world15_enforce_rocket_limit(entity, owner)
        end
        if not entity.valid then return end  -- 超限已被销毁，跳过后续登记/充能
        -- N-01：中心正方形内 4 种炮塔 minable_flag=false 禁拆
        local name = entity.name
        if name == 'gun-turret' or name == 'laser-turret' or name == 'rocket-turret' or name == 'tesla-turret' then
            entity.minable_flag = false
            -- N-03/N-04: 建造即登记+即时充能（事件注册式，无区域扫描）
            register_turret(entity)
            charge_turret(entity)
        end
    end
end

-- N-01：炮塔锁定仅靠 minable_flag=false（引擎级禁拆）；挖掘后原地重建逻辑已移除。

--==============================================================================

-- 指挥 Boss（spider-unit 五足虫）主动进攻中心正方形最中心：
-- spider-unit 不支持 set_command（已实测验证会报错），必须用 unit_group + 组
-- command(attack_area) 才能驱动其移动，与普通 biters 冲中心机制一致。
local function command_boss_to_center(boss, center)
    if not boss or not boss.valid then return end
    local cmd = {
        type = defines.command.attack_area,
        destination = center,
        radius = 60,
        distraction = defines.distraction.by_anything,
    }
    -- 方案A（Factorio 2.0 正规接口）：LuaEntity.commandable → LuaCommandable:set_command
    -- 2.0 中单位命令已从 LuaEntity 移到 LuaCommandable（旧探针报 set_command 不存在即此原因）
    local ok_a, err_a = pcall(function()
        local c = boss.commandable
        if c and c.valid then
            c.set_command(cmd)
            return
        end
        error('commandable 不可用')
    end)
    if ok_a then return end
    -- 方案B（兜底）：unit_group + start_moving()
    -- 注意：单成员编组会停留在"集结(gathering)"状态原地不动，必须 start_moving() 强制开拔
    local ok_b, err_b = pcall(function()
        local surface = boss.surface
        local g = surface.create_unit_group({position = boss.position, force = boss.force})
        if not g then error('create_unit_group 返回 nil') end
        g.add_member(boss)
        g.set_command(cmd)
        if g.start_moving then g.start_moving() end
    end)
    if not ok_b then
        log('[world15] Boss 指挥失败 A:' .. tostring(err_a) .. ' B:' .. tostring(err_b))
        game.print('[world15] Boss 指挥失败: ' .. tostring(err_b), {r = 1, g = 0.4, b = 0.4})
    end
end

local function spawn_boss(wave_number)
    if (WPT.get() and WPT.get().world_number or 0) ~= 15 then return end
    if wave_number == 0 or wave_number % BOSS_INTERVAL ~= 0 then return end

    -- 关键：场景每局用 CS.create_surface() 新建自定义表面，游戏并不在 nauvis 上！
    -- 必须用 wave_defense 的 surface_index（普通刷虫也用它），否则 Boss 刷在玩家看不见的 nauvis。
    local surface_index = WD.get('surface_index')
    local surface = surface_index and game.surfaces[surface_index]
    if not surface or not surface.valid then return end

    -- Boss 为大型践踏五足虫（big-stomper-pentapod），血量固定原版 15000（清除原有动态血量设定）
    local boss_hp = 15000
    local tier = wave_number / BOSS_INTERVAL                 -- 100波=1, 200波=2 ...

    -- 中心正方形最中心（取波次 target，兜底 {0,0}），Boss 出生与进攻都以它为基准
    local target = WD.get('target')
    local center = (target and target.valid) and {x = target.position.x, y = target.position.y} or {x = 0, y = 0}

    -- 四个方向定义（已纠正上/下通道）：
    -- Factorio 坐标系中 y 正方向向下(南=下通道)，负方向向上(北=上通道)。
    -- 原代码把 -y 标成「下通道」、+y 标成「上通道」，正好反了，此处已修正。
    local directions = {
        {name = "下通道", offset = {x = 0, y =  SPAWN_DISTANCE}, perp = {x = 1, y = 0}},  -- 南
        {name = "右通道", offset = {x =  SPAWN_DISTANCE, y = 0}, perp = {x = 0, y = 1}},  -- 东
        {name = "上通道", offset = {x = 0, y = -SPAWN_DISTANCE}, perp = {x = 1, y = 0}},  -- 北
        {name = "左通道", offset = {x = -SPAWN_DISTANCE, y = 0}, perp = {x = 0, y = 1}},  -- 西
    }

    -- 决定本次 Boss 分布（数量/方向）：
    --   <1000 波：维持原「四通道轮流出一只」机制（每 100 波推进一个通道）
    --  >=1000 波：四个方向各出 1 只
    --  >=1500 波：四个方向各出 5 只
    -- 整波总奖励封顶不变（= 原单只 1000*tier），由本波所有 Boss 均分。
    local active_dirs, count_per_dir
    if wave_number >= 1500 then
        active_dirs, count_per_dir = {1, 2, 3, 4}, 5
    elseif wave_number >= 1000 then
        active_dirs, count_per_dir = {1, 2, 3, 4}, 1
    else
        local idx = ((tier - 1) % #directions) + 1
        active_dirs, count_per_dir = {idx}, 1
    end

    local total_bosses = #active_dirs * count_per_dir
    -- 整波总奖励封顶 = 原单只奖励(1000*tier)，均分给本波每只 Boss（无论几只总量不变）
    local per_boss_reward = math.floor((1000 * tier) / total_bosses)

    local spread = 7          -- 同方向多 Boss 沿垂直通道展开间距(tile)
    local spawned_channels = {}
    local this = WPT.get()
    if not this.world15_bosses then this.world15_bosses = {} end

    for _, di in ipairs(active_dirs) do
        local dir = directions[di]
        for k = 0, count_per_dir - 1 do
            -- 同方向多个 Boss 沿垂直方向等距展开，避免完全重叠
            local lateral = (k - (count_per_dir - 1) / 2) * spread
            local entry = {
                x = center.x + dir.offset.x + dir.perp.x * lateral,
                y = center.y + dir.offset.y + dir.perp.y * lateral,
            }

            -- 逐步扩大搜索半径找可生成位置（stomper 体型大，需确保不落水/不卡墙）
            local boss_pos = nil
            for _, radius in ipairs({5, 10, 20, 50}) do
                boss_pos = surface.find_non_colliding_position("big-stomper-pentapod", entry, radius, 1)
                if boss_pos then break end
            end
            if not boss_pos then
                boss_pos = entry  -- 兜底：直接在入口尝试
            end

            local boss = surface.create_entity({
                name = "big-stomper-pentapod",
                position = boss_pos,
                force = "enemy",
            })
            if boss then
                -- ⚠️ Factorio 2.x：LuaEntity.max_health 只读，赋值会抛错并中断本函数，
                -- 导致下面的进攻指令与 Boss 记录全部不执行（不进攻/不爆炸/不奖励的真根因，自测捕获）。
                -- health 赋值会被引擎钳制到原型上限，故用赋值后的实际血量作为 max_hp。
                boss.health = boss_hp
                boss_hp = boss.health

                -- spider-unit（五足虫）不支持 set_command，必须用 unit_group 指挥其主动进攻中心
                command_boss_to_center(boss, center)

                this.world15_bosses[boss.unit_number] = {
                    wave = wave_number,
                    reward = per_boss_reward,                     -- 整波总奖励封顶=1000*tier，均分至每只（不随 Boss 数量改变）
                    max_hp = boss_hp,
                    spawn_pos = boss_pos,
                    revives_left = tier - 1,                       -- 100波=0次, 200波=1次 ...
                    death_dmg_pct = tier >= 2 and (50 + (tier - 2) * 5) or 0,  -- 200波=50%, 300波=55% ...
                    entity = boss,                                 -- 看门狗重新下令用
                }
            end
        end
        spawned_channels[#spawned_channels + 1] = dir.name
    end

    game.print({"amap.world15_boss_spawn", wave_number, math.floor(boss_hp)},
        {r = 1, g = 0.3, b = 0})
    game.print("Boss 出生通道：" .. table.concat(spawned_channels, "、"), {r = 1, g = 0.6, b = 0})
end

-- 注：Boss 接口（spawn_boss / boss_interval / unlock_progressive_techs）已通过
-- World.register(15, {...}) 的 def 字段暴露，由 wave_defense 按世界查询调用，
-- 不再注册到 WD 表（避免 world_number == 15 之外的耦合与 rawget 时序坑）。

-- 在 Boss 记录表中匹配死亡实体。
-- ⚠️ big-stomper-pentapod 是分段单位(segmented-unit)，某些情况下 on_entity_died
-- 上报的 unit_number 会与 create_entity 时记录的不一致，导致 bosses[unit_number] 取空，
-- 三个分支（爆炸/复活/发奖）全部被跳过。故改为多策略匹配：
--   1) unit_number 直接命中
--   2) 遍历比对实体引用 / 存活实体的 unit_number
--   3) 同名 + 距离最近兜底（分段单位死亡实体引用可能已失效）
local function match_boss_record(this, entity)
    local bosses = this.world15_bosses
    if not bosses then return nil, nil end

    -- 策略1：unit_number 直接命中
    local key = entity.unit_number
    if key and bosses[key] then return key, bosses[key] end

    -- 策略2：实体引用 / unit_number 比对
    for k, bd in pairs(bosses) do
        if bd.entity and bd.entity.valid then
            if bd.entity == entity or (key and bd.entity.unit_number == key) then
                return k, bd
            end
        end
    end

    -- 策略3：同名 + 最近距离兜底
    if entity.name == "big-stomper-pentapod" then
        local best_k, best_bd, best_d
        local ex, ey = entity.position.x, entity.position.y
        for k, bd in pairs(bosses) do
            local rp = (bd.entity and bd.entity.valid and bd.entity.position) or bd.spawn_pos
            if rp then
                local dx, dy = rp.x - ex, rp.y - ey
                local d = dx * dx + dy * dy
                if not best_d or d < best_d then
                    best_d, best_k, best_bd = d, k, bd
                end
            end
        end
        return best_k, best_bd
    end

    return nil, nil
end

-- 识别击杀者归属玩家：支持 character / beam / turret / combat-robot 等常见致死来源。
-- 返回玩家索引（player.index），无法识别时返回 nil。
local function resolve_killer_owner(cause, this)
    if not cause or not cause.valid then return nil end
    local ctype = cause.type
    if ctype == 'character' then
        if cause.player and cause.player.valid then
            return cause.player.index
        end
        return nil
    elseif ctype == 'beam' then
        -- beam.source 是发射该 beam 的实体（通常是炮塔）
        local src = cause.source
        if src and src.valid then
            if src.type == 'character' then
                if src.player and src.player.valid then return src.player.index end
            elseif src.last_user and src.last_user.valid then
                return src.last_user.index
            end
        end
        return nil
    elseif ctype == 'turret' then
        if cause.last_user and cause.last_user.valid then
            return cause.last_user.index
        end
        return nil
    elseif ctype == 'combat-robot' then
        -- 战斗机器人归属：优先 last_user（部署者），其次 owner.player
        if cause.last_user and cause.last_user.valid then
            return cause.last_user.index
        end
        if cause.owner and cause.owner.valid and cause.owner.player and cause.owner.player.valid then
            return cause.owner.player.index
        end
        return nil
    end
    -- 其他来源（车/蜘蛛等）退化为 last_user
    if cause.last_user and cause.last_user.valid then
        return cause.last_user.index
    end
    return nil
end

-- Boss 击杀处理：死亡爆炸（200波起）+ 复活（每100波+1次）+ 完全击杀发奖
local function on_boss_died(event)
    local entity = event.entity
    if not entity or not entity.valid then return end

    if (WPT.get() and WPT.get().world_number or 0) ~= 15 then return end

    local this = WPT.get()
    if not this.world15_bosses or not next(this.world15_bosses) then return end

    local key, bd = match_boss_record(this, entity)
    if not bd then
        -- 分段 Boss 死亡但未匹配到记录：打印诊断，便于定位 unit_number 漂移
        if entity.name == "big-stomper-pentapod" then
            local keys = {}
            for k in pairs(this.world15_bosses) do keys[#keys + 1] = tostring(k) end
            game.print("[世界15诊断] Boss 死亡但未匹配记录 died_un=" ..
                tostring(entity.unit_number) .. " 记录键=[" .. table.concat(keys, ",") .. "]",
                {r = 1, g = 0.3, b = 0.3})
        end
        return
    end

    -- 死亡爆炸：对范围内玩家阵营实体造成伤害（爆炸先于复活，且只伤 player 阵营，故不伤复活的自己）
    if bd.death_dmg_pct and bd.death_dmg_pct > 0 then
        local dmg = bd.max_hp * bd.death_dmg_pct / 100
        local targets = entity.surface.find_entities_filtered({
            position = entity.position, radius = 10, force = "player",
        })
        for _, t in pairs(targets) do
            if t.valid and t.health and t.health > 0 then
                t.damage(dmg, game.forces.enemy, "explosion")
            end
        end
        entity.surface.create_entity({
            name = "big-explosion", position = entity.position, force = game.forces.enemy,
        })
        game.print({"amap.world15_boss_death", math.floor(dmg)}, {r = 1, g = 0.5, b = 0})
    end

    -- 复活：在死亡点附近满血复活，继承剩余复活次数与伤害比例（本次不发奖）
    if bd.revives_left and bd.revives_left > 0 then
        local revive_pos = entity.surface.find_non_colliding_position(
            "big-stomper-pentapod", entity.position, 8, 1) or entity.position
        local revived = entity.surface.create_entity({
            name = "big-stomper-pentapod", position = revive_pos, force = "enemy",
        })
        if revived then
            -- max_health 只读（2.x），只设 health（引擎自动钳制到原型上限）
            revived.health = bd.max_hp
            -- 复活体同样主动进攻中心正方形最中心
            local tgt = WD.get('target')
            local ctr = (tgt and tgt.valid) and {x = tgt.position.x, y = tgt.position.y} or {x = 0, y = 0}
            command_boss_to_center(revived, ctr)
            this.world15_bosses[revived.unit_number] = {
                wave = bd.wave, reward = bd.reward, max_hp = bd.max_hp,
                spawn_pos = bd.spawn_pos,
                revives_left = bd.revives_left - 1,
                death_dmg_pct = bd.death_dmg_pct,
                entity = revived,                          -- 看门狗重新下令用
            }
            game.print({"amap.world15_boss_revive", bd.wave, bd.revives_left - 1},
                {r = 1, g = 0.7, b = 0})
        end
        this.world15_bosses[key] = nil
        return
    end

    -- 完全击杀：识别击杀者，全员发基础赏金（每在线玩家 1 份），击杀者额外 1 份（共 2 倍）
    if not this.world15_player_gold then this.world15_player_gold = {} end
    local killer_pidx = resolve_killer_owner(event.cause, this)

    for _, player in pairs(game.connected_players) do
        local pidx = player.index
        local amount = bd.reward
        if killer_pidx and pidx == killer_pidx then
            amount = amount * 2  -- 基础 1 份 + 额外悬赏 1 份
        end
        this.world15_player_gold[pidx] = (this.world15_player_gold[pidx] or 0) + amount
        player.print({"amap.world15_boss_reward", math.floor(amount)},
            {r = 1, g = 0.85, b = 0})
    end

    -- 极端情况兜底：击杀者不在 connected_players 列表中时，仍确保拿到悬赏
    if killer_pidx then
        local found = false
        for _, p in pairs(game.connected_players) do
            if p.index == killer_pidx then found = true; break end
        end
        if not found then
            this.world15_player_gold[killer_pidx] = (this.world15_player_gold[killer_pidx] or 0) + bd.reward * 2
        end
    end

    -- 全服播报：识别到击杀者则播报击杀者，否则播报"已被消灭"
    if killer_pidx then
        local killer = game.players[killer_pidx]
        local kname = (killer and killer.valid) and killer.name or ("#" .. killer_pidx)
        game.print({"amap.world15_boss_kill", kname, bd.wave, math.floor(bd.reward)},
            {r = 1, g = 0.85, b = 0})
    else
        game.print({"amap.world15_boss_cleared", math.floor(bd.reward)},
            {r = 1, g = 0.85, b = 0})
    end

    this.world15_bosses[key] = nil
end

-- Boss 看门狗：每 10 秒检查存活 Boss 是否原地卡住（命令被引擎丢弃/完成后进入 idle），
-- 卡住则重新下达攻中心命令。spider-unit 的组命令易失效，必须持续督战。
local function boss_watchdog()
    local this = WPT.get()
    if not this or this.world_number ~= 15 then return end
    local bosses = this.world15_bosses
    if not bosses or not next(bosses) then return end

    local tgt = WD.get('target')
    local center = (tgt and tgt.valid) and {x = tgt.position.x, y = tgt.position.y} or {x = 0, y = 0}

    for key, bd in pairs(bosses) do
        local boss = bd.entity
        if not (boss and boss.valid) then
            -- 实体已失效但没走死亡流程（如被脚本移除），清掉记录防止泄漏
            if not (boss and boss.valid) and bd.entity ~= nil then
                bosses[key] = nil
            end
        else
            local pos = boss.position
            local lp = bd.last_pos
            -- 距离中心 30 格内视为已到达，不再督战
            local dx, dy = pos.x - center.x, pos.y - center.y
            if dx * dx + dy * dy > 900 then
                if lp and math.abs(pos.x - lp.x) < 0.5 and math.abs(pos.y - lp.y) < 0.5 then
                    -- 10 秒没挪动 → 重新下令
                    command_boss_to_center(boss, center)
                end
            end
            bd.last_pos = {x = pos.x, y = pos.y}
        end
    end
end

--==============================================================================
-- 【世界15 统一科技节奏表】—— 单一数据源
--
-- 设计目标（Bug A 修复）：全部「武器伤害 / 射速 / 永久升级」类科技走【同一条等级
-- 曲线 L(wave)】，增速受控、与虫子成长动态匹配，杜绝「某族错名空转、某族无限膨胀」。
--
-- ── 三条实测铁律（Factorio 2.1.12 RCON 无头实证，改这段前必读）───────────────
-- 1) 无限科技 tech.researched 【恒读 false】，每写一次 researched = true 就 level + 1。
--    因此【绝不可】用 `not tech.researched` 判「尚未授予」——旧写法在 755 波后每 60 tick
--    重复授予一次，等级 / 伤害无限膨胀 + 刷屏。
-- 2) 无限科技 tech.level 【可读可写、可升可降】：写 level = 20 生效，再写 level = 6 会降回。
--    语义：已完成级数 = tech.level - 原型基准级。→ 直接写 level 天然幂等，无需登记表。
-- 3) 有限科技写 level 无效（researched 仍为 false），只能用 researched 控制。
--
-- ── 旧实现的三个坑（本次一并修掉）─────────────────────────────────────────
-- a) 手写禁用表出现 5 个【真实科技树中不存在】的名字：energy-weapons-damage /
--    gun-turret-speed / laser-turret-speed / worker-robot-speed / worker-robot-storage。
--    → 真名是 electric-weapons-damage / worker-robots-speed / worker-robots-storage，
--      两个 turret-speed 科技压根不存在。electric 族因此从未被禁用，开局即全解锁。
-- b) 禁用表写到 -8 级，而真实科技树最高只有 -6 / -7 级 → 第 8 级条目全是死数据。
-- c) init_technologies 的 50 轮定点迭代对无限科技每轮写一次 researched = true
--    → 未被 skip 的无限科技开局直接【+50 级】（实测 health level = 51、+2500 HP）。
--
-- → 本版改为【单一数据源 W15_TECH_FAMILIES】，禁用集与等级映射全部自动派生，
--    从结构上杜绝错名和「三表口径不一致」。
--==============================================================================

-- 各科技族的真实结构（全部经 RCON 读原型实测，勿凭记忆填写）
--   prefix     族名前缀（有限级科技名 = prefix .. '-' .. i）
--   finite_max 有限级最高后缀号（0 = 该族没有有限级科技，科技名即前缀本身）
--   inf_name   该族无限科技的完整名（nil = 该族无无限科技，等级封顶 finite_max）
--   inf_base   该无限科技的原型基准 level（已完成级数 = tech.level - inf_base）
--   cap        该族等级上限（nil = 跟随统一曲线，不封顶）
local W15_TECH_FAMILIES = {
    -- ① 武器伤害类 --------------------------------------------------------------
    {prefix = 'physical-projectile-damage', finite_max = 6, inf_name = 'physical-projectile-damage-7', inf_base = 7},
    {prefix = 'laser-weapons-damage',       finite_max = 6, inf_name = 'laser-weapons-damage-7',       inf_base = 7},
    {prefix = 'electric-weapons-damage',    finite_max = 3, inf_name = 'electric-weapons-damage-4',    inf_base = 4},
    {prefix = 'stronger-explosives',        finite_max = 6, inf_name = 'stronger-explosives-7',        inf_base = 7},
    {prefix = 'refined-flammables',         finite_max = 6, inf_name = 'refined-flammables-7',         inf_base = 7},
    {prefix = 'railgun-damage',             finite_max = 0, inf_name = 'railgun-damage-1',             inf_base = 1},
    {prefix = 'artillery-shell-damage',     finite_max = 0, inf_name = 'artillery-shell-damage-1',     inf_base = 1},
    -- ② 射速类 ------------------------------------------------------------------
    -- weapon-shooting-speed 只有 1~6 级、laser-shooting-speed 只有 1~7 级，二者【均无无限级】，
    -- 到顶后自然封顶（旧表写到 -8 是死数据）。
    {prefix = 'weapon-shooting-speed',      finite_max = 6},
    {prefix = 'laser-shooting-speed',       finite_max = 7},
    {prefix = 'railgun-shooting-speed',     finite_max = 0, inf_name = 'railgun-shooting-speed-1',     inf_base = 1},
    {prefix = 'artillery-shell-speed',      finite_max = 0, inf_name = 'artillery-shell-speed-1',      inf_base = 1},
    -- ③ 永久升级类 --------------------------------------------------------------
    {prefix = 'mining-productivity',        finite_max = 2, inf_name = 'mining-productivity-3',        inf_base = 3},
    {prefix = 'worker-robots-speed',        finite_max = 6, inf_name = 'worker-robots-speed-7',        inf_base = 7},
    {prefix = 'worker-robots-storage',      finite_max = 3},
    {prefix = 'artillery-shell-range',      finite_max = 0, inf_name = 'artillery-shell-range-1',      inf_base = 1},
    {prefix = 'inserter-capacity-bonus',    finite_max = 7},
    {prefix = 'braking-force',              finite_max = 7},
    -- 跟随机器人：【性能封顶 L10】（≈195 个跟随机器人）。
    -- 依据：base 5 + 前 4 级(5/10/10/20) = 45，之后每级 +25 → L10 = 195、L132 = 3245。
    -- 3245 个是真实实体（各自跑寻路 + 攻击判定），叠加本世界场上 400 只虫必然 UPS 崩溃。
    -- 这是纯性能约束，不是平衡约束。
    {prefix = 'follower-robot-count',       finite_max = 4, inf_name = 'follower-robot-count-5',       inf_base = 5, cap = 10},
    -- ④ 生产力类（无有限级，科技名即前缀，全部为无限研究）--------------------------
    {prefix = 'steel-plate-productivity',           finite_max = 0, inf_name = 'steel-plate-productivity',           inf_base = 1},
    {prefix = 'scrap-recycling-productivity',       finite_max = 0, inf_name = 'scrap-recycling-productivity',       inf_base = 1},
    {prefix = 'plastic-bar-productivity',           finite_max = 0, inf_name = 'plastic-bar-productivity',           inf_base = 1},
    {prefix = 'rocket-fuel-productivity',           finite_max = 0, inf_name = 'rocket-fuel-productivity',           inf_base = 1},
    {prefix = 'processing-unit-productivity',       finite_max = 0, inf_name = 'processing-unit-productivity',       inf_base = 1},
    {prefix = 'low-density-structure-productivity', finite_max = 0, inf_name = 'low-density-structure-productivity', inf_base = 1},
    {prefix = 'rocket-part-productivity',           finite_max = 0, inf_name = 'rocket-part-productivity',           inf_base = 1},
    {prefix = 'research-productivity',              finite_max = 0, inf_name = 'research-productivity',              inf_base = 1},
    {prefix = 'asteroid-productivity',              finite_max = 0, inf_name = 'asteroid-productivity',              inf_base = 1},
}

-- 固定完成级数的科技（【不跟随】统一节奏，开局设定后不再变动）
--   health（无限科技，每级 +50 角色生命）不入节奏的两条依据：
--   1) 生存能力已由框架 world_bonus 单独管理（diff.apply_world_bonuses →
--      character_health_bonus 线性增长）。纳入节奏 = 同一属性加两遍，双重膨胀。
--   2) health 既非武器伤害、也非射速、也不属于「永久升级类」，本就不在统一节奏范围内。
--   固定 1 级 = +50 HP。（旧版被 50 轮定点迭代顶到 level 51 → +2500 HP，即 Bug A 的一支。）
local W15_FIXED_TECH_LEVELS = {
    ['health'] = 1,
}

-- 由 W15_TECH_FAMILIES【自动派生】的「受统一节奏管理的科技名集合」。
-- 该集合同时承担旧 DISABLED_TECHNOLOGIES_LIST 的职责：开局这些科技一律锁定（L0），
-- 之后完全由 w15_apply_tech_level_for_force 按 L(wave) 驱动升降。
-- 手写清单已删除 —— 从结构上杜绝再写出不存在的科技名。
local W15_MANAGED_TECHS = {}
do
    for _, fam in ipairs(W15_TECH_FAMILIES) do
        for i = 1, fam.finite_max do
            W15_MANAGED_TECHS[fam.prefix .. '-' .. i] = true
        end
        if fam.inf_name then
            W15_MANAGED_TECHS[fam.inf_name] = true
        end
    end
end

--==============================================================================
-- 统一等级曲线 L(wave)
--
-- 由平衡模型 .workbuddy/w15_design_model.py 二分反解得出，对齐指定的难度锚点
-- （2000 波≈7.0 / 3000 波≈8.0 / 4000 波≈9.0 / 5000 波≈9.5，实测偏差 ≤0.04 全部 PASS）。
-- 模型口径：难度 D = 5 + 2 * log2(R / R0)，R = 敌方 HP 吞吐需求 / 玩家混合 DPS；
-- 玩家 DPS 按炮塔构成加权（laser 0.40 / physical 0.30 / explosives 0.15 /
-- electric 0.10 / flamethrower 0.05）并计入对应射速科技乘区。
--
--   波次 < 10        → L0（开局全锁，保持塔防前期的纯净手感）
--   10 ≤ 波次 < 1000 → L = 1 + floor(波次 / 100)，即每 100 波 +1 级，L(900..999) = 10
--   波次 ≥ 1000      → 分段线性，每段「每 step 波推进 1 级」：
--        ≤1500: 28 波/级   ≤2000: 50 波/级   ≤3000: 25 波/级
--        ≤4000: 36 波/级   >4000: 37 波/级（外推同斜率）
--   校验点：L(1000)=10  L(2000)=37  L(3000)=77  L(4000)=105  L(5000)=132
--==============================================================================
local W15_LEVEL_SEGMENTS = {
    {hi = 1500, step = 28},
    {hi = 2000, step = 50},
    {hi = 3000, step = 25},
    {hi = 4000, step = 36},
    {hi = 5000, step = 37},
}

-- 预计算每段起点的累计等级：用浮点保留小数，避免「逐段先取整再累加」造成的等级漂移
-- （模型侧同样是浮点累加后一次性取整，两边口径必须一致，否则实机曲线会偏离验收锚点）。
do
    local lvl, prev = 10.0, 1000
    for _, seg in ipairs(W15_LEVEL_SEGMENTS) do
        seg.base_wave = prev
        seg.base_level = lvl
        lvl = lvl + (seg.hi - prev) / seg.step
        prev = seg.hi
    end
end

local function w15_level_for_wave(wave)
    if not wave or wave < 10 then return 0 end
    if wave < 1000 then
        return 1 + math.floor(wave / 100)
    end
    for _, seg in ipairs(W15_LEVEL_SEGMENTS) do
        if wave <= seg.hi then
            return math.floor(seg.base_level + (wave - seg.base_wave) / seg.step)
        end
    end
    -- 超出最后一段（>5000 波）：按最后一段的斜率外推，保持连续无断崖
    local last = W15_LEVEL_SEGMENTS[#W15_LEVEL_SEGMENTS]
    return math.floor(last.base_level
        + (last.hi - last.base_wave) / last.step
        + (wave - last.hi) / last.step)
end

-- 世界15 玩家实际势力可能不是默认 game.forces.player（RPG/角色系统或框架会给玩家分配
-- 队伍势力——与「金币按 player.index 发放」同源）。科技解锁/锁回必须作用到玩家真实势力，
-- 否则只会动默认 player 势力、玩家真实势力的科技仍被提前解锁（即「开局科技提前解锁」真凶）。
-- 返回去重后的玩家势力列表（遍历在线玩家）。
local function world15_get_player_forces()
    local forces = {}
    for _, p in pairs(game.connected_players) do
        if p and p.valid and p.force and p.force.valid then
            forces[p.force.index] = p.force
        end
    end
    -- 无在线玩家时（开局瞬间 / 无头自测）fallback 到默认 player 势力，
    -- 保证科技锁回逻辑仍会执行，避免「无人时全部科技敞开」，并让无头自测可执行。
    if not next(forces) then
        local pf = game.forces.player
        if pf and pf.valid then forces[pf.index] = pf end
    end
    return forces
end

-- 无限研究科技的 max_level 读数（uint 上限）
local W15_INFINITE_MAX_LEVEL = 4294967295

-- 等级变更日志开关：true = 每次统一等级发生变化写一行 log()，便于排查。
-- 【仅影响日志输出，不参与任何解锁判定】。
local W15_TECH_LOG = true

local function w15_is_infinite_tech(tech)
    local proto = tech.prototype
    return proto ~= nil and proto.max_level >= W15_INFINITE_MAX_LEVEL
end

-- 把单个科技族精确设定到 target_level（可升【也可降】，自愈式、天然幂等）。
--
-- 分两种写入通道，缺一不可（见文件上方「三条实测铁律」）：
--   · 有限级（prefix-1 .. prefix-finite_max）：只能用 researched 控制，写 level 无效。
--   · 无限级（inf_name）：直接写 level = inf_base + 超出有限段的级数。
--
-- 有限段必须先【降序锁回】再【升序解锁】：
--   升序锁回会失败 —— 低等级科技在「更高等级仍处于已研究」时无法置回 false，
--   导致整族残留（真实 bug：框架默认把整族 1..N 全解锁，只升序回锁则 level1 锁不掉）。
local function w15_apply_family(force, fam, target_level)
    local fin_cap = fam.finite_max
    local fin_target = target_level
    if fin_target > fin_cap then fin_target = fin_cap end
    if fin_target < 0 then fin_target = 0 end

    for i = fin_cap, fin_target + 1, -1 do
        local tech = force.technologies[fam.prefix .. '-' .. i]
        if tech and tech.researched then
            pcall(function() tech.researched = false end)
        end
    end
    for i = 1, fin_target do
        local tech = force.technologies[fam.prefix .. '-' .. i]
        if tech and not tech.researched then
            pcall(function() tech.researched = true end)
        end
    end

    if fam.inf_name then
        local tech = force.technologies[fam.inf_name]
        if tech then
            local extra = target_level - fin_cap
            if extra < 0 then extra = 0 end
            local want = fam.inf_base + extra
            -- 只在不相等时写：level 写入本身是幂等的，但避免无谓的引擎调用
            if tech.level ~= want then
                pcall(function() tech.level = want end)
            end
        end
    end
end

-- 把【全部族】推到统一等级 level。
-- 自愈：无论读档、框架误解锁、还是玩家手动研究，下一次调用即纠正回目标等级。
local function w15_apply_tech_level_for_force(force, level)
    for _, fam in ipairs(W15_TECH_FAMILIES) do
        local target = level
        if fam.cap and target > fam.cap then target = fam.cap end
        w15_apply_family(force, fam, target)
    end
end

-- 框架扩展点 unlock_progressive_techs 的实现：按当前波次施加统一等级。
-- 返回本次施加的等级，供调用方做「等级提升播报」的节流判定。
local function unlock_progressive_weapon_techs(current_wave)
    local level = w15_level_for_wave(current_wave)
    -- 对每个在线玩家的真实势力执行（玩家势力可能不是默认 game.forces.player）
    for _, force in pairs(world15_get_player_forces()) do
        w15_apply_tech_level_for_force(force, level)
    end
    return level
end

-- 对单个势力执行开局初始化：
--   ① 解锁全部「不受统一节奏管理」的有限科技（定点迭代，满足前置依赖链）
--   ② 族外无限科技统一给 1 级
--   ③ 固定级科技（health）按 W15_FIXED_TECH_LEVELS 写死
--   ④ 受统一节奏管理的科技全部归零（L0），之后交给 enforce_world15_techs 按波次驱动
local function init_technologies_for_force(force)
    -- ① 定点迭代解锁：每轮解锁当前无前置阻碍的科技，下一轮再解锁依赖它们的科技。
    -- 用 pcall 包裹 researched = true，避免「前置未满足」抛错中断整轮。
    --
    -- ⚠️【必须跳过全部无限科技】—— 这是旧版科技膨胀最大的一支：
    -- 无限科技 researched 恒读 false → while 循环每轮都判定它「还没研究」并写一次，
    -- 每写一次 level + 1，50 轮下来直接 +50 级（实测 health level = 51、+2500 HP，
    -- electric-weapons-damage-4 level = 54、电力伤害 +35.0）。
    -- 无限科技一律走下方 ②③④ 的 level 写入通道。
    local changed = true
    local guard = 0
    while changed and guard < 50 do
        changed = false
        guard = guard + 1
        for name, tech in pairs(force.technologies) do
            if not W15_MANAGED_TECHS[name]
                and not W15_FIXED_TECH_LEVELS[name]
                and tech.enabled
                and not tech.researched
                and not w15_is_infinite_tech(tech)
            then
                local ok = pcall(function() tech.researched = true end)
                if ok then changed = true end
            end
        end
    end

    -- ② 族外无限科技（既不受统一节奏管理、也不在固定表里）：统一给 1 级。
    -- 既不让它们停在 0 级（玩家会觉得少了东西），也不让它们被迭代顶到 50 级。
    for name, tech in pairs(force.technologies) do
        if not W15_MANAGED_TECHS[name]
            and not W15_FIXED_TECH_LEVELS[name]
            and tech.enabled
            and w15_is_infinite_tech(tech)
        then
            local base = (tech.prototype and tech.prototype.level) or 1
            if tech.level ~= base + 1 then
                pcall(function() tech.level = base + 1 end)
            end
        end
    end

    -- ③ 固定级科技（health）：写死完成级数，不跟随统一节奏。
    for name, lv in pairs(W15_FIXED_TECH_LEVELS) do
        local tech = force.technologies[name]
        if tech then
            local base = (tech.prototype and tech.prototype.level) or 1
            local want = base + lv
            if tech.level ~= want then
                pcall(function() tech.level = want end)
            end
        end
    end

    -- ④ 受统一节奏管理的科技：开局一律归零（L0）。
    -- 之后由 enforce_world15_techs 每 60 tick 按 L(wave) 推进 / 回收（可升可降、自愈）。
    w15_apply_tech_level_for_force(force, 0)
end

local function init_technologies()
    -- 由框架 main.lua reset_map 的 on_world_start 钩子调用：
    -- 每次「进入 / 重进」世界15 都会执行（含火箭发射井爆炸后重进），
    -- 不再依赖 on_nth_tick / give_starter_items 的自驱动，避免重进世界科技不解锁。
    -- 对每个在线玩家的真实势力执行初始化（幂等，per-force），避免只动默认 player 势力。
    for _, force in pairs(world15_get_player_forces()) do
        init_technologies_for_force(force)
    end
end

--==============================================================================
-- 小地图渲染：绘制可建区（整条十字）边界并揭示地图
--==============================================================================

local function render_buildable_area()
    -- 主战场表面每局由 CS.create_surface 新建（不是 nauvis），从 WPT 取当前局表面
    local this = WPT.get()
    local surface = this and this.active_surface_index and game.surfaces[this.active_surface_index]
    if not surface or not surface.valid then return end

    local color = {r = 0.2, g = 1, b = 0.4, a = 0.9}  -- 绿色可建区边界
    local width = 10

    -- 中心正方形可建区边界（|x|<=ARM_HALF_WIDTH, |y|<=ARM_HALF_WIDTH）
    rendering.draw_rectangle {
        surface = surface,
        left_top = {-ARM_HALF_WIDTH, -ARM_HALF_WIDTH},
        right_bottom = {ARM_HALF_WIDTH, ARM_HALF_WIDTH},
        filled = false,
        width = width,
        color = color,
        only_in_alt_mode = false,
        draw_on_ground = true,
    }

    -- 揭示中心正方形区域，确保边界在小地图立即可见
    game.forces.player.chart(surface, {
        left_top = {-ARM_HALF_WIDTH, -ARM_HALF_WIDTH},
        right_bottom = {ARM_HALF_WIDTH, ARM_HALF_WIDTH},
    })
end

--==============================================================================
-- 开局赠送
--==============================================================================

local function give_starter_items()
    -- 双重判断：world_number 或 diff.get().world 任一为 15 即放行（与 init_technologies 一致），
    -- 避免「加入游戏事件在选世界前触发」时因 world_number/world 尚未就绪而提前 return。
    local this = WPT.get()
    local map = diff.get()
    if not this or (this.world_number ~= 15 and (not map or map.world ~= 15)) then return end

    -- ===== 世界级一次性初始化（科技 / 边界）=====
        if not this.world15_started then
            this.world15_started = true

            -- 科技解锁已移至框架 main.lua reset_map 的 on_world_start 钩子（每次进入/重进世界15 均执行）

            -- 绘制可建区边界到小地图（仅一次）
            render_buildable_area()

        -- N-05：在出生点 (0,-5) 创建市场 market（供玩家直接交易，4 种炮塔购买挂在主市场 rock.lua）。
        -- 金币不再挂钩任何商店：开局放车由 item_build_car 直发 1000 coin，击杀/Boss 奖励每 tick 回灌背包。
        local sf = game.surfaces[this.active_surface_index]
        if sf then
            pcall(function()
                if not sf.find_entity('market', {x = 0, y = -5}) then
                    sf.create_entity({name = 'market', position = {x = 0, y = -5}, force = 'neutral'})
                end
            end)
        end

        -- N-04：炮塔供能分两层（均为事件注册式，无区域扫描）。
        --   ① 建造即补满：charge_turret 在建造事件里给 laser/tesla 充满能量、给 gun/rocket 装弹。
        --   ② 周期维护：world15_supply_tick（nth_tick[10]，6 次/秒）遍历已登记炮塔表补能/补弹。
        -- 世界15 为「无真实电网」设计（不铺 roboport/solar/电线杆，避免额外耗电实体），
        -- laser/tesla 靠脚本直接写 energy 供能。已实测：引擎不会每 tick 清零未联网电力实体的能量
        -- （静置 2.5s 仍保留约 83%），故 6 次/秒的补能节奏足以让炮塔常驻满电。
        -- 注：曾尝试用 electric-energy-interface + connect_neighbour 建「隐藏无限电源」消除未接电图标，
        -- 实测该 API 在 electric-energy-interface / laser-turret 上均不存在（LuaEntity doesn't contain key），
        -- 方案不可行，相关代码已于 2026-08-06 移除。玩家如需建设/维修机器人网络，可在市场购买 roboport。
    end

    if not this.world15_player_gold then
        this.world15_player_gold = {}
    end

    for _, player in pairs(game.connected_players) do
        -- 注意：世界15走 world 框架（主 surface 共享），玩家势力不一定是默认 game.forces.player
        -- （RPG/角色系统或框架会给玩家分配队伍势力）。故不能用 force==player 作为发放前提，
        -- 否则所有玩家都会被永久跳过、金币永不发放。改以「世界15 + 每人幂等」作为唯一前提。

        -- N-05 重写：金币直接进背包（不再挂钩商店/虚拟金币）。
        -- world15_player_gold 仅作「离线累积器」：Boss 奖励（world15 自有，110% 发放）先累加到这里，
        -- 玩家在线时每 tick 回灌背包 coin，确保金币永不丢失、随时可在市场消费。
        -- 提示节流：金币照常每 tick 无声入账；「获得金币」提示每 5 秒（300 tick）最多播报一次，
        -- 累计这段时间内的金额，避免击杀密集时刷屏（原实现每 tick 都 print → 极吵）。
        if not this.world15_unannounced then this.world15_unannounced = {} end
        if not this.world15_last_coin_print then this.world15_last_coin_print = {} end
        if this.world15_player_gold[player.index] and this.world15_player_gold[player.index] > 0 then
            local pending = this.world15_player_gold[player.index]
            local inserted = player.insert({name = "coin", count = pending})
            if inserted > 0 then
                this.world15_player_gold[player.index] = pending - inserted
                this.world15_unannounced[player.index] = (this.world15_unannounced[player.index] or 0) + inserted
                if this.world15_player_gold[player.index] <= 0 then
                    this.world15_player_gold[player.index] = nil
                end
            end
        end
        -- 节流播报：每 tick 检查，但每个玩家每 5 秒最多提示一次
        local unannounced = this.world15_unannounced[player.index] or 0
        local last_print = this.world15_last_coin_print[player.index] or 0
        if unannounced > 0 and game.tick - last_print >= 300 then
            player.print(string.format("击杀/Boss 奖励：获得 %d 金币（已存入背包）", unannounced),
                {r = 1, g = 0.85, b = 0})
            this.world15_unannounced[player.index] = 0
            this.world15_last_coin_print[player.index] = game.tick
        end
    end
end

--==============================================================================
-- 通关奖励（框架 world_bonus 机制）
-- 与其他世界同款：记录历史最高波数 → 折算 coefficient → 每次开图 reset 时
-- 由 diff.apply_world_bonuses() 统一施加 force 级 modifier（所有世界通用）。
-- 世界15 参数经 World.register 声明式覆写：解锁波数 2000、增档间隔 100、
-- 线性增长模式（base 100 + 每档 10，不设上限）。
-- 「只按最高计算、不叠加」由框架天然保证（加成值由 max_wave 单调推导，
-- 每次 reset 从零重新施加，绝无跨局叠加）。
--==============================================================================

-- 胜利瞬间/坚守推进时即时更新 world_bonus 记录（与 tank.lua game_over 同款规则；
-- game_over 在最终失败时也会兜底更新，此处保证 2000 波胜利当刻即入账）
local function world15_update_bonus_record(wave_number)
    local map = diff.get()
    if not map or not map.world_bonus then return end
    if map.world_bonus[15] == nil then
        map.world_bonus[15] = {unlocked = false, coefficient = 0, max_wave = 0}
    end
    local record = map.world_bonus[15]
    if wave_number <= record.max_wave then return end
    local old_unlocked = record.unlocked
    local old_value = diff.get_world_bonus_value(15, record)
    record.max_wave = wave_number
    local start_wave = World.get_field(15, 'world_bonus_start_wave') or map.world_bonus.start_wave
    local interval = World.get_field(15, 'world_bonus_interval') or map.world_bonus.coefficient_interval
    if wave_number < start_wave then return end
    record.unlocked = true
    local coefficient_increase = math.floor((wave_number - start_wave) / interval)
    -- coefficient 仅供难度系数与旧插值模式使用（仍受 20 封顶）；生命值加成走线性增长模式，
    -- 由 max_wave 直接推导，不受此封顶影响。
    record.coefficient = math.min(
        map.world_bonus.base_coefficient + coefficient_increase,
        map.world_bonus.max_coefficient
    )
    local new_value = diff.get_world_bonus_value(15, record)
    if not old_unlocked then
        game.print({'amap.world_bonus_unlocked', 15}, {r = 255, g = 255, b = 0})
    elseif new_value and old_value and new_value > old_value then
        game.print({'amap.world_bonus_increased_value', 15, new_value}, {r = 0, g = 255, b = 0})
    end
end

-- 进入/重进世界15 钩子：解锁科技（通关奖励改走框架 world_bonus，无需按玩家补发）
local function world15_on_world_start(world_number)
    -- 已播报等级必须与 init_technologies 的归零同步复位：
    -- init_technologies_for_force 会把全部受管科技降到 L0，
    -- 若不清 world15_tech_level，重进世界后新一局要爬到旧等级才会再播报一次。
    local this = WPT.get()
    if this then
        this.world15_tech_level = nil
        -- 波次提速段位同步复位：新一局波数从 0 开始，段位不清会漏播第 2 段以后的提速提示
        this.world15_pace_stage = nil
        -- 旧版遗留字段清理（登记表 / 永久升级节点已随统一节奏表一起废弃）
        this.world15_tech_granted = nil
        this.world15_last_permanent_wave = nil
    end
    init_technologies()
end

--==============================================================================
-- on_tick 主循环
--==============================================================================

local function on_tick(event)
    if (WPT.get() and WPT.get().world_number or 0) ~= 15 then return end
    local this = WPT.get()

    -- 一次性清理出生点(0,0)可能残留的框架瞬态钢箱：main.lua 在区块(0,0)生成时创建 steel-chest 后立即 destroy，
    -- 但世界切换/重生时可能残留；该实体无任何功能作用（世界15商店靠命令打开的 market，不依赖此箱），故清除。
    if not this.world15_chest_cleaned then
        this.world15_chest_cleaned = true
        local surface = game.surfaces[this.active_surface_index]
        if surface then
            local chests = surface.find_entities_filtered{name = 'steel-chest', position = {x = 0, y = 0}, radius = 1}
            for _, c in pairs(chests) do
                if c.valid then c.destroy() end
            end
        end
    end

    give_starter_items()

    -- 兼容两种调用签名：框架 nth_tick 分发器传标准 event 对象（含 .tick），也兼容直接传 tick 数字
    local tick = type(event) == 'table' and event.tick or (type(event) == 'number' and event)
    if not tick then return end


    -- 胜利条件：坚守 2000 波
    local wave_number = WD.get('wave_number') or 0

    -- 【已移除】旧的「300 波后 wave_interval 减半（仅一次）」。
    -- 移除原因：它是一次性写 WD 字段，而 diff.lua 的 set_diff 每 60 tick 会按难度重算并覆盖
    -- wave_interval（1300~2005 波区间甚至强制写死 1380/diff_k），减半结果活不过 1 秒。
    -- 世界15 的波次节奏改由专属间隔曲线接管（见 Step4 / World.register 的 wave_interval_curve）。

    if wave_number >= 2000 then
        -- 通关奖励：框架 world_bonus（初始生命值 +100，2000 波起每坚守 100 波再 +10、不设上限，
        -- 只按历史最高记录、不叠加；下次开图 reset 时统一施加，所有世界通用）
        world15_update_bonus_record(wave_number)
        -- 胜利公告仅一次（can_continue 后 on_tick 每 tick 重入）
        if not this.world15_victory_announced then
            this.world15_victory_announced = true
            game.print({"amap.world15_victory"}, {r = 1, g = 0.85, b = 0})
            game.print({"amap.world15_victory_hp"}, {r = 0.4, g = 1, b = 0.4})
        end
        game.set_game_state({game_finished = true, player_won = true, can_continue = true})
        return
    end


end

--==============================================================================
-- 科技策略：独立于 on_tick，每 60 tick 自愈执行
--==============================================================================
-- 独立 on_nth_tick 触发，不依赖 on_tick 内其它逻辑，
-- 避免任何异常中断科技策略，保证「未到波次的禁用科技一定被锁回」每帧生效。
local function enforce_world15_techs()
    if (WPT.get() and WPT.get().world_number or 0) ~= 15 then return end
    local this = WPT.get()
    if not this then return end

    -- 一次性科技解锁已移至框架 main.lua reset_map 的 on_world_start 钩子（每次进入/重进世界均执行）

    local wave_number = WD.get('wave_number') or 0

    -- 武器伤害 / 射速 / 永久升级：全部走同一条统一等级曲线 L(wave)，可升可降、自愈幂等。
    local level = unlock_progressive_weapon_techs(wave_number)

    -- 等级提升播报（每级一次）。降级（读档 / 重进世界）时只静默同步记录，不播报。
    local last = this.world15_tech_level or 0
    if level > last then
        this.world15_tech_level = level
        if W15_TECH_LOG then
            log('[world15] tech level -> ' .. level .. ' (wave ' .. wave_number .. ')')
        end
        game.print({'amap.world15_tech_unlock', level}, {r = 1, g = 0.7, b = 0.2})
    elseif level < last then
        this.world15_tech_level = level
    end
end

--==============================================================================
-- 波次压力自愈：每 60 tick 幂等重申世界15 的活跃虫上限
--==============================================================================
-- max_active_biters 是 wave_defense 的通用初值（96），reset_wave_defense 每次开图都会把它写回 96。
-- 世界15 需要 400 才能让「四路 × 三小队 = 336 只」全部落地（详见文件顶部 W15_MAX_ACTIVE_BITERS 依据）。
-- 这里每秒幂等重申：无论中途被谁重置（开新图 / 重进世界 / 读档），下一秒自愈；
-- 写入前先比较，值一致时不写，常态零开销。
-- 放在世界模块内而不是改 wave_defense 的读取点，是为了不给通用文件引入任何世界号相关分支。
-- 当前波次落在间隔曲线的第几段（1 起）。返回段序号，供「跨段即播报提速」使用。
local function w15_pace_stage_for_wave(wave)
    for i, seg in ipairs(W15_WAVE_INTERVAL_SEGMENTS) do
        if wave < seg.hi then
            return i
        end
    end
    return #W15_WAVE_INTERVAL_SEGMENTS + 1
end

local function enforce_world15_wave_params()
    local this = WPT.get()
    if (this and this.world_number or 0) ~= 15 then return end

    if WD.get('max_active_biters') ~= W15_MAX_ACTIVE_BITERS then
        WD.set('max_active_biters', W15_MAX_ACTIVE_BITERS)
    end

    -- 跨段提速播报：每段只播一次。播报的秒数取 wave_interval 的实际生效值
    -- （已含 diff.lua 的 diff_k 折算），而不是曲线基准值，保证与玩家实际体感一致。
    local wave = WD.get('wave_number') or 0
    local stage = w15_pace_stage_for_wave(wave)
    local last_stage = this.world15_pace_stage or 0
    if stage > last_stage then
        this.world15_pace_stage = stage
        -- last_stage==0 是开图后的首次同步（第 1 段），不算「提速」，静默记录即可
        if last_stage > 0 then
            local seconds = math.floor((WD.get('wave_interval') or 0) / 60 + 0.5)
            game.print({'amap.world15_wave_speedup', wave, seconds}, {r = 1, g = 0.5, b = 0.2})
        end
    elseif stage < last_stage then
        this.world15_pace_stage = stage
    end
end

-- N-03/N-04：事件注册式供能（laser/tesla 补电 + gun/rocket 补弹，免费）
-- 炮塔在建造事件中登记进 world15_registered_turrets（玩家/机器人建造均覆盖），
-- 此处每 tick 遍历该表补满：laser/tesla 充满电、gun/rocket 空仓补 200 弹药（按波次选弹种）。
-- 不调用 find_entities_filtered，范围=已登记炮塔表，开销恒定、无区域扫描。
local function world15_supply_tick()
    local this = WPT.get()
    if (this and this.world_number or 0) ~= 15 then return end

    if not this.world15_registered_turrets then return end
    local wave = WD.get('wave_number') or 0
    for unit_number, turret in pairs(this.world15_registered_turrets) do
        if turret and turret.valid then
            local n = turret.name
            if n == 'laser-turret' or n == 'tesla-turret' then
                -- 实测：未联网 electric-turret 能量不会每 tick 被引擎清零（静置 2.5s 仍保留 ~83%），
                -- 故供能循环已降到 nth_tick[10]；此处仅在未满时补满，避免冗余 engine write。
                if turret.electric_buffer_size and turret.energy < turret.electric_buffer_size then
                    turret.energy = turret.electric_buffer_size
                end
            elseif n == 'gun-turret' or n == 'rocket-turret' then
                local inv = turret.get_inventory(defines.inventory.turret_ammo)
                if inv and inv.is_empty() then
                    local ammo_name = get_ammo_for_wave(n, wave)
                    if ammo_name then
                        inv.clear()
                        inv.insert({name = ammo_name, count = 200})
                    end
                end
            end
        else
            this.world15_registered_turrets[unit_number] = nil
        end
    end
end



--==============================================================================
-- 卡片1 全服强化投票：每 20 波直接弹窗，3 个选项供全体玩家投票，得票最多者全服生效
-- 机制：参考天赋选择界面（卡片式）。每 20 波从 8 张升级卡池抽 3 张，向所有在线玩家
--       弹出投票框；玩家点击卡片即投票，窗口立即消失；倒计时结束或全员投票后，
--       得票最多者全服生效。平票/超时：随机选定。永久类记账进 WPT 供幂等重申。
--==============================================================================
local W15_VOTE_FRAME = 'world15_vote_frame'
local W15_VOTE_CARDS = 'world15_vote_cards'
local W15_VOTE_TIMER = 'world15_vote_timer'
local W15_VOTE_BTN_PREFIX = 'world15_vote_pick_'
local W15_VOTE_CLOSE = 'world15_vote_close'
local W15_VOTE_SECONDS = 30          -- 投票限时（秒）
local W15_VOTE_TICKS = W15_VOTE_SECONDS * 60

-- 前置声明：world15_apply_upgrade 定义在下方（世界15 模块内），
-- 但 world15_resolve_vote 需要调用它。若不前置声明，resolve 内引用到的是
-- 全局 nil（Lua 词法作用域），调用报错又被 pcall 吞掉 → 投票通过但效果不生效。
local world15_apply_upgrade

-- 升级卡池（8 张）。永久类（bullet_dmg/laser_dmg/fire_rate/rocket_dmg/tesla_dmg/coin）记账进 this.w15_upgrade_counts / w15_coin_mult。
local W15_UPGRADE_KEYS = {'bullet_dmg', 'laser_dmg', 'fire_rate', 'rocket_dmg', 'tesla_dmg', 'coin', 'repair', 'instant_coin'}

-- 伤害/射速/炮塔攻击：可无限叠加，不再封顶（= 选取次数 ×5% 持续累加）。
-- 金币：+1% 可叠加，上限 +10%（倍率上限 1.10）；达上限后仍可被随机抽中（抽奖池无排除逻辑）。
local W15_COIN_BONUS = 0.01   -- 每次「金币收入」卡 +1%
local W15_COIN_CAP   = 1.10   -- 金币倍率上限（= +10%）

-- 升级卡图标（用于投票卡片，点击即投票）
local W15_UPGRADE_ICON = {
    bullet_dmg   = 'item/firearm-magazine',
    laser_dmg    = 'item/laser-turret',
    fire_rate    = 'item/speed-module',
    rocket_dmg   = 'item/rocket-turret',
    tesla_dmg    = 'item/tesla-turret',
    coin         = 'item/coin',
    repair       = 'item/repair-pack',
    instant_coin = 'item/coin',
}

-- 取世界15 主 surface
local function world15_get_surface()
    local this = WPT.get()
    local idx = this and this.active_surface_index
    return idx and game.surfaces[idx] or nil
end

-- 判断玩家是否正在副本中（副本 surface 隔离；active=true 表示已进入）
-- 副本内玩家不弹强化投票窗，避免干扰副本玩法
local function world15_is_player_in_dungeon(player)
    if not player or not player.valid then return false end
    local this = WPT.get()
    if not this or not this.dungeons then return false end
    local d = this.dungeons[player.index]
    return d and d.active or false
end

-- 抽 3 张升级卡（从 8 张池随机不重复）
local function world15_draw_three()
    local pool = {}
    for _, k in ipairs(W15_UPGRADE_KEYS) do pool[#pool + 1] = k end
    local picks = {}
    for _ = 1, 3 do
        local idx = math.random(#pool)
        picks[#picks + 1] = table.remove(pool, idx)
    end
    return picks
end

-- 统计当前各选项票数（仅计入在线玩家）
local function world15_tally_votes(vote)
    local counts = {}
    for _, k in ipairs(vote.options) do counts[k] = 0 end
    for _, p in pairs(game.connected_players) do
        if p.valid then
            local v = vote.votes[p.name]
            if v and counts[v] then counts[v] = counts[v] + 1 end
        end
    end
    return counts
end

-- 打开/刷新投票 GUI（卡片式，参考天赋选择界面）
local function world15_open_vote_gui(player, vote)
    if world15_is_player_in_dungeon(player) then return end  -- 副本内玩家不弹投票窗
    local screen = player.gui.screen
    local old = screen[W15_VOTE_FRAME]
    if old then old.destroy() end

    local frame = screen.add{type = 'frame', name = W15_VOTE_FRAME, direction = 'vertical', caption = {'amap.world15_up_title'}}
    frame.auto_center = true

    local remain = math.max(0, math.ceil((vote.end_tick - game.tick) / 60))
    frame.add{type = 'label', name = W15_VOTE_TIMER, caption = {'amap.world15_vote_timer', remain}}

    local counts = world15_tally_votes(vote)
    local my_vote = vote.votes[player.name]

    local cards = frame.add{type = 'flow', name = W15_VOTE_CARDS, direction = 'horizontal'}
    cards.style.horizontal_spacing = 8
    cards.style.vertical_align = 'top'

    for _, key in ipairs(vote.options) do
        local card = cards.add{type = 'frame', name = 'w15_card_' .. key, direction = 'vertical'}
        card.style.minimal_width = 170
        card.style.maximal_width = 170
        card.style.padding = 8
        card.style.vertically_stretchable = true

        -- 名称（已选高亮为绿色）
        local name_flow = card.add{type = 'flow', direction = 'horizontal'}
        name_flow.style.horizontally_stretchable = true
        name_flow.style.horizontal_align = 'center'
        local picked = (my_vote == key)
        local name_label = name_flow.add{type = 'label', caption = {'amap.world15_up_' .. key}}
        name_label.style.font = 'heading-2'
        name_label.style.single_line = false
        name_label.style.maximal_width = 150
        if picked then name_label.style.font_color = {r = 0.2, g = 1, b = 0.2} end

        -- 图标（点即投票）
        local icon_flow = card.add{type = 'flow', direction = 'horizontal'}
        icon_flow.style.horizontally_stretchable = true
        icon_flow.style.horizontal_align = 'center'
        icon_flow.style.top_padding = 4
        icon_flow.style.bottom_padding = 4
        local icon = icon_flow.add{type = 'sprite-button', name = W15_VOTE_BTN_PREFIX .. key, sprite = W15_UPGRADE_ICON[key],
            tooltip = {'amap.world15_up_' .. key}}
        icon.style.minimal_width = 72
        icon.style.minimal_height = 72
        icon.style.maximal_width = 72
        icon.style.maximal_height = 72
        if picked then icon.style.font_color = {r = 0.2, g = 1, b = 0.2} end

        -- 当前票数
        local cnt_flow = card.add{type = 'flow', direction = 'horizontal'}
        cnt_flow.style.horizontally_stretchable = true
        cnt_flow.style.horizontal_align = 'center'
        cnt_flow.add{type = 'label', name = 'w15_cnt_' .. key, caption = {'amap.world15_vote_count', counts[key] or 0}}
    end

    if my_vote then
        frame.add{type = 'label', caption = {'amap.world15_vote_you', {'amap.world15_up_' .. my_vote}}}
    end
    frame.add{type = 'button', name = W15_VOTE_CLOSE, caption = {'amap.world15_up_close'}}
end

-- 发起投票：抽 3 张，弹给所有在线玩家，设定倒计时
local function world15_start_vote()
    local this = WPT.get()
    if not this or this.w15_vote then return end
    local options = world15_draw_three()
    this.w15_vote = {
        options = options,
        votes = {},
        end_tick = game.tick + W15_VOTE_TICKS,
        wave = WD.get('wave_number') or 0,
    }
    for _, p in pairs(game.connected_players) do
        if p.valid then world15_open_vote_gui(p, this.w15_vote) end
    end
    game.print({'amap.world15_vote_start'}, {r = 1, g = 0.85, b = 0.2})
end

-- 结算投票：得票最多者全服生效；平票/超时随机
local function world15_resolve_vote()
    local this = WPT.get()
    if not this or not this.w15_vote then return end
    local vote = this.w15_vote
    local counts = world15_tally_votes(vote)
    local maxc = -1
    local winners = {}
    for _, k in ipairs(vote.options) do
        local c = counts[k] or 0
        if c > maxc then maxc = c; winners = {k} end
        if c == maxc then winners[#winners + 1] = k end
    end
    if maxc <= 0 then
        -- 无人投票：本轮跳过，不随机施加强化（得票多者当选才有意义）
        game.print({'amap.world15_vote_skip'}, {r = 1, g = 0.85, b = 0.2})
    else
        local chosen
        if #winners > 1 then
            chosen = winners[math.random(#winners)]   -- 平票随机
        else
            chosen = winners[1]
        end
        local ok, err = pcall(function() world15_apply_upgrade(chosen, nil) end)
        if not ok then log('[world15] apply_upgrade failed: ' .. tostring(err)) end
        game.print({'amap.world15_vote_result', {'amap.world15_up_' .. chosen}, maxc}, {r = 0.4, g = 1, b = 0.4})
    end
    for _, p in pairs(game.connected_players) do
        if p.valid then
            local f = p.gui.screen[W15_VOTE_FRAME]
            if f then pcall(function() f.destroy() end) end
        end
    end
    this.w15_vote = nil
end

-- 投票点击：点卡片=投票（窗口立即消失）；点关闭=收起窗口（保留已投）
local function on_world15_vote_click(event)
    if (WPT.get() and WPT.get().world_number or 0) ~= 15 then return end
    local element = event.element
    if not element or not element.valid then return end
    local name = element.name
    local this = WPT.get()
    local vote = this and this.w15_vote
    if not vote then return end

    if name == W15_VOTE_CLOSE then
        local f = game.get_player(event.player_index).gui.screen[W15_VOTE_FRAME]
        if f then pcall(function() f.destroy() end) end
        return
    end
    if name:sub(1, #W15_VOTE_BTN_PREFIX) == W15_VOTE_BTN_PREFIX then
        local player = game.get_player(event.player_index)
        if not player or not player.valid then return end
        local key = name:sub(#W15_VOTE_BTN_PREFIX + 1)
        local ok = false
        for _, k in ipairs(vote.options) do if k == key then ok = true; break end end
        if not ok then return end
        vote.votes[player.name] = key
        player.print({'amap.world15_vote_you', {'amap.world15_up_' .. key}})  -- 非阻塞确认：已记录你的投票
        -- 点击即投票，窗口立即消失，不再停留影响操作；最终结果待投票倒计时结束统一公布
        local f = player.gui.screen[W15_VOTE_FRAME]
        if f then pcall(function() f.destroy() end) end
    end
end

-- 每 20 波发起投票；进行中刷新倒计时；到点结算
local function world15_vote_tick()
    if (WPT.get() and WPT.get().world_number or 0) ~= 15 then return end
    local this = WPT.get()
    if not this then return end
    if not this.w15_vote then
        local wave = WD.get('wave_number') or 0
        if wave > 0 and wave % 20 == 0 and (this.w15_last_vote_wave or 0) ~= wave then
            this.w15_last_vote_wave = wave
            world15_start_vote()
        end
        return
    end
    local vote = this.w15_vote
    local remain = math.ceil((vote.end_tick - game.tick) / 60)
    for _, p in pairs(game.connected_players) do
        if p.valid then
            local f = p.gui.screen[W15_VOTE_FRAME]
            if f then
                if world15_is_player_in_dungeon(p) then
                    pcall(function() f.destroy() end)   -- 投票期间进入副本者立即关闭窗口
                else
                    local t = f[W15_VOTE_TIMER]
                    if t and t.valid then t.caption = {'amap.world15_vote_timer', math.max(0, remain)} end
                end
            end
        end
    end
    if game.tick >= vote.end_tick then world15_resolve_vote() end
end

-- 幂等重申：由记账的 counts 推导 force modifier 并每帧设置，防框架覆盖
local function world15_reassert_modifiers()
    local this = WPT.get()
    if (this and this.world_number or 0) ~= 15 then return end
    local counts = this.w15_upgrade_counts
    if not counts then return end
    local force = game.forces.player
    if not force then return end
    force.set_ammo_damage_modifier('bullet', (counts.bullet_dmg or 0) * 0.05)
    force.set_ammo_damage_modifier('laser',  (counts.laser_dmg  or 0) * 0.05)
    for _, k in ipairs({'bullet', 'laser', 'flamethrower'}) do
        force.set_gun_speed_modifier(k, (counts.fire_rate or 0) * 0.05)
    end
    -- 火箭/特斯拉炮塔攻击加成（set_turret_attack_modifier，与框架 ammo modifier 不冲突；均不再封顶）
    force.set_turret_attack_modifier('rocket-turret', (counts.rocket_dmg or 0) * 0.05)
    force.set_turret_attack_modifier('tesla-turret',  (counts.tesla_dmg  or 0) * 0.05)
end

-- 应用一张升级卡（对应上方前置声明，勿改回 local function —— 会重新引入前向引用 bug）
world15_apply_upgrade = function(key, player)
    local this = WPT.get()
    local force = game.forces.player
    local fname = force and force.name
    if key == 'bullet_dmg' then
        this.w15_upgrade_counts = this.w15_upgrade_counts or {}
        this.w15_upgrade_counts.bullet_dmg = (this.w15_upgrade_counts.bullet_dmg or 0) + 1
    elseif key == 'laser_dmg' then
        this.w15_upgrade_counts = this.w15_upgrade_counts or {}
        this.w15_upgrade_counts.laser_dmg = (this.w15_upgrade_counts.laser_dmg or 0) + 1
    elseif key == 'fire_rate' then
        this.w15_upgrade_counts = this.w15_upgrade_counts or {}
        this.w15_upgrade_counts.fire_rate = (this.w15_upgrade_counts.fire_rate or 0) + 1
    elseif key == 'rocket_dmg' then
        this.w15_upgrade_counts = this.w15_upgrade_counts or {}
        this.w15_upgrade_counts.rocket_dmg = (this.w15_upgrade_counts.rocket_dmg or 0) + 1
    elseif key == 'tesla_dmg' then
        this.w15_upgrade_counts = this.w15_upgrade_counts or {}
        this.w15_upgrade_counts.tesla_dmg = (this.w15_upgrade_counts.tesla_dmg or 0) + 1
    elseif key == 'coin' then
        -- 金币收入 +1%，可叠加；上限 +10%（达上限后本次不追加，但仍可被随机抽中）
        this.w15_coin_mult = (this.w15_coin_mult or 1) + W15_COIN_BONUS
        if this.w15_coin_mult > W15_COIN_CAP then this.w15_coin_mult = W15_COIN_CAP end
    elseif key == 'repair' then
        -- 全场修复：优先遍历已登记炮塔表（与供能系统一致，直接持有实体引用，
        -- 不依赖 surface/force 匹配，可靠覆盖全部 4 种炮塔），再补充扫描全场 player 势力实体。
        local this = WPT.get()
        if this and this.world15_registered_turrets then
            for _, turret in pairs(this.world15_registered_turrets) do
                if turret and turret.valid and turret.health and turret.max_health and turret.health < turret.max_health then
                    turret.health = turret.max_health
                end
            end
        end
        local surface = world15_get_surface()
        if surface then
            for _, ent in pairs(surface.find_entities_filtered{force = 'player'}) do
                -- 用 health 赋值修复，避免 ent.repair() 对无 repair 字段的实体抛错
                if ent.valid and ent.health and ent.max_health and ent.health < ent.max_health then
                    ent.health = ent.max_health
                end
            end
        end
        for _, p in pairs(game.players) do
            if p.valid and p.character and p.character.valid and p.character.max_health then
                p.character.health = p.character.max_health
            end
        end
    elseif key == 'instant_coin' then
        local amt = math.floor(1000 * (this.w15_coin_mult or 1))
        for _, p in pairs(game.connected_players) do
            if p.valid and p.force.name == fname then p.insert({name = 'coin', count = amt}) end
        end
    end
    world15_reassert_modifiers()
end

-- 卡片1 旧实现（精良木箱点击触发 + 每20波投放 + per-player 点选）已移除。
-- 现改为直接投票弹窗，相关函数见上方 world15_start_vote / world15_vote_tick / on_world15_vote_click。

--==============================================================================
-- 卡片7：完美波挑战 + 成就（世界15 自包含，零框架改动，world_number==15 自守）
-- 范围：核心完美波 + M1 速通连击 + M6 个人击杀里程碑。M2/M3/M4/M5 本轮挂起。
-- 关键事实：WD.get('active_biters') 只含波防刷怪（spawn_unit_group 入表），
--          野生虫巢刷出的怪不在此表 → 完美波判定天然不含野怪。
--==============================================================================

-- —— 配置（集中，便于调参）——
local W15_PERFECT_SECONDS = 10
local W15_PERFECT_TICKS   = W15_PERFECT_SECONDS * 60   -- 600 tick
local W15_PERFECT_MULT    = 5     -- 完美波奖励 = 5 × 当前波次编号（金币/人）；Boss 波跳过
local W15_BOSS_WAVE_MOD   = 100   -- 每 100 波为 Boss 波，跳过完美波挑战

-- M1 速通连击：连续完美波达阈值 → 额外金币（= 当次完美奖励 × 倍率），一次性去重
local W15_COMBO_TIERS = { { n = 10, mult = 2 }, { n = 20, mult = 3 }, { n = 30, mult = 5 } }
-- M6 个人击杀里程碑：按击杀者个人累计击杀达阈值 → 一次性金币（仅统计玩家方击杀；野生虫互殴不计入个人成就）
local W15_TOTALKILL_TIERS = {
    { n = 10000, gold = 1000 },
    { n = 50000, gold = 5000 },
    { n = 100000, gold = 15000 },
    { n = 1000000, gold = 50000 },    -- 百万击杀：奖励 50k（给击杀个人）
    { n = 10000000, gold = 100000 },  -- 千万击杀：奖励 100k（给击杀个人）
}

-- 确保世界15 成就/统计状态存在（幂等）
local function world15_ach_ensure(this)
    this.world15_ach_claimed = this.world15_ach_claimed or {}
    this.world15_kill_stats  = this.world15_kill_stats or
        { players = {}, total = 0, consecutive = 0, perfect_total = 0 }
    if not this.world15_kill_stats.players then this.world15_kill_stats.players = {} end
    this.world15_perfect     = this.world15_perfect or
        { last_wave = 0, active = false, start_tick = 0, peak = 0, reached_zero = false }
    return this
end

-- 全体在线玩家发放金币 + 可选全服播报（locale_key 可带最多 2 个 __N__ 参数）
local function world15_give_all(amount, locale_key, p1, p2)
    for _, p in pairs(game.connected_players) do
        if p.valid then p.insert({ name = 'coin', count = amount }) end
    end
    if locale_key then
        local color = { r = 1, g = 0.85, b = 0.2 }
        if p2 ~= nil then
            game.print({ locale_key, p1, p2 }, color)
        elseif p1 ~= nil then
            game.print({ locale_key, p1 }, color)
        else
            game.print({ locale_key }, color)
        end
    end
end

-- 完美波达成：发奖 + 推进 M1 连击
local function world15_award_perfect(this, wave)
    world15_ach_ensure(this)
    local reward = W15_PERFECT_MULT * wave
    world15_give_all(reward, 'amap.world15_perfect_clear', wave, reward)

    local ks = this.world15_kill_stats
    ks.consecutive  = (ks.consecutive or 0) + 1
    ks.perfect_total = (ks.perfect_total or 0) + 1

    local claimed = this.world15_ach_claimed
    for _, t in ipairs(W15_COMBO_TIERS) do
        if ks.consecutive >= t.n and not claimed['combo_' .. t.n] then
            claimed['combo_' .. t.n] = true
            world15_give_all(reward * t.mult, 'amap.world15_ach_combo', ks.consecutive, reward * t.mult)
        end
    end
end

-- 击杀计数钩子（on_entity_died）：按击杀者个人累计击杀 → 个人击杀里程碑（奖励给击杀个人）
local function world15_on_enemy_died(event)
    if (WPT.get() and WPT.get().world_number or 0) ~= 15 then return end
    local entity = event.entity
    if not entity or not entity.valid then return end
    if not entity.force or entity.force.name ~= 'enemy' then return end
    local wpt = WPT.get()
    if not wpt then return end
    -- 仅统计「玩家方」造成的击杀（野生虫互殴不计入个人成就）
    local killer_index = resolve_killer_owner(event.cause, wpt)
    if not killer_index then return end
    world15_ach_ensure(wpt)
    local stats = wpt.world15_kill_stats
    stats.players[killer_index] = (stats.players[killer_index] or 0) + 1
    local claimed = wpt.world15_ach_claimed
    for _, t in ipairs(W15_TOTALKILL_TIERS) do
        local key = 'totalkill_' .. t.n .. '_' .. killer_index
        if stats.players[killer_index] >= t.n and not claimed[key] then
            claimed[key] = true
            -- 全服播报（含玩家名 + 个人累计击杀数 + 奖励金币）
            local p = game.get_player(killer_index)
            local pname = (p and p.valid) and p.name or ('#' .. killer_index)
            game.print({ 'amap.world15_ach_totalkill', pname, t.n, t.gold }, { r = 1, g = 0.85, b = 0.2 })
            -- 奖励给击杀个人：在线即时进背包，否则挂账 world15_player_gold（复用现有回灌机制）
            local given = 0
            if p and p.valid and p.connected and p.character then
                given = p.insert({ name = 'coin', count = t.gold })
            end
            if given < t.gold then
                wpt.world15_player_gold = wpt.world15_player_gold or {}
                wpt.world15_player_gold[killer_index] = (wpt.world15_player_gold[killer_index] or 0) + (t.gold - given)
            end
        end
    end
end

-- 主循环（每 60 tick）：检测波次递增 → 启动/结算 10 秒完美波挑战
local function world15_perfect_tick(event)
    local wpt = WPT.get()
    if not wpt or (wpt.world_number or 0) ~= 15 then return end
    local this = wpt
    world15_ach_ensure(this)

    local wave = WD.get('wave_number') or 0
    if wave <= 0 then return end

    local pf = this.world15_perfect

    -- 检测波次递增 → 新波开始
    if pf.last_wave ~= wave then
        pf.last_wave = wave
        if wave % W15_BOSS_WAVE_MOD == 0 then
            -- Boss 波：跳过挑战（跳过≠失败，不重置连击）
            pf.active = false
        else
            pf.active = true
            pf.start_tick = game.tick
            pf.peak = 0
            pf.reached_zero = false
        end
        return
    end

    if not pf.active then return end

    local elapsed = game.tick - pf.start_tick
    local count = WD.get('active_biter_count') or 0
    if count > pf.peak then pf.peak = count end
    if count == 0 then pf.reached_zero = true end

    if elapsed >= W15_PERFECT_TICKS then
        pf.active = false
        if pf.peak > 0 and pf.reached_zero then
            -- 完美：窗口内波防虫曾全部清空
            world15_award_perfect(this, wave)
        else
            -- 失败：重置 M1 连击
            this.world15_kill_stats.consecutive = 0
        end
    end
end

--==============================================================================
-- 事件 handler（仅定义，不在此注册）
--
-- 本模块不调用任何 Event.add / Event.on_nth_tick：所有事件订阅统一在文件末尾的
-- World.register 中以 events / nth_tick 声明，由 framework.lua 按当前世界分发。
-- 与世界 1-14 保持一致：世界模块 = 纯声明，事件调度权归框架。
--==============================================================================

-- 玩家加入游戏：发放开局物资；若投票进行中，给新加入玩家补弹投票框
local function on_player_joined_game(event)
    if (WPT.get() and WPT.get().world_number or 0) ~= 15 then return end
    give_starter_items()
    -- 世界15：投票进行中，给新加入玩家也弹投票框
    local this = WPT.get()
    if this and this.w15_vote then
        local p = game.get_player(event.player_index)
        if p and p.valid then world15_open_vote_gui(p, this.w15_vote) end
    end
    -- （通关生命奖励已改走框架 world_bonus：force 级 modifier 对全员自动生效，无需按玩家补发/重生重发）
end

-- 炮塔死亡：从补给登记表注销（避免 supply_tick 遍历失效实体）
local function on_turret_died(event)
    if (WPT.get() and WPT.get().world_number or 0) ~= 15 then return end
    local entity = event.entity
    if entity and entity.valid then
        unregister_turret(entity)
    end
end

-- 炮塔锁定：建造时设 minable_flag=false（引擎级禁拆）。已移除挖掘后原地重建逻辑。

--==============================================================================
-- 注册到框架
--==============================================================================

-- 车载开局物资钩子：世界15 仅发放战斗类物品（gun-turret / 弹药 / stone-wall）+ 1000 金币 + 20 个传说机枪炮塔。
-- 由 tank.lua 在放置汽车时通过 World.get_field(world, 'on_car_placed') 调用。
-- 返回 true 表示已处理（tank.lua 据此跳过通用物资循环），保持其它世界逻辑不变。
local function on_car_placed(player, wave_number, car_items)
    local combat = {['gun-turret'] = true, ['firearm-magazine'] = true, ['stone-wall'] = true}
    for item, amount in pairs(car_items) do
        if combat[item] then
            local give = item
            if item == 'firearm-magazine' then
                if wave_number >= 450 then give = 'piercing-rounds-magazine' end
                if wave_number >= 1000 then give = 'uranium-rounds-magazine' end
            end
            player.insert({name = give, count = math.floor(amount)})
        end
    end
    player.insert({name = 'coin', count = 1000})
    player.print({"", "[color=255, 215, 0]", "世界15：开局赠送 1000 金币（已存入背包，可在出生点市场购买炮塔）", "[/color]"})
    -- 开局额外赠送：20 个传说机枪炮塔（原理参考上方 1000 金币赠送，同在此放车钩子发放）
    player.insert({name = 'gun-turret', count = 20, quality = 'legendary'})
    player.print({"", "[color=255, 215, 0]", "世界15：开局赠送 20 个传说机枪炮塔（已存入背包）", "[/color]"})
    return true
end

World.register(15, {
    -- 元数据
    name_key = 'amap.world_name_15',
    desc_key = 'amap.world_name_info_15',

    -- 时间：第1波次倒计时 5 分钟（18000 tick）；后续波次由 wave_defense 按 wave_interval 推进
    -- 注意：time_limit 仅用于首波延迟（main.lua:583 设置 next_wave），不影响 2000 波胜利条件
    time_limit = 60 * 60 * 5,

    -- 地表配置：世界15专用（无矿 / 无树木 / 无 map-gen 野外虫巢；虫巢由通道生成器手动放置）
    surface_config_name = 'world15',

    -- 不生成默认野外建筑/石头（原 world_main.lua ywjz 硬编码排除列表）
    disable_default_rocks = true,

    -- 地图尺寸：十字，总 2560 × 2560 tile（80 × 80 chunk），容纳 4 倍长度通道
    map_settings = {
        width = 2560,
        height = 2560,
        starting_area = 0.6,
        -- 十字海心为纯塔防平地：禁用悬崖，避免 cliff 实体盖在十字地形上
        cliff_settings = {cliff_elevation_interval = 0, cliff_elevation_0 = 0},
        -- 自然进化系统：开启（time / destruction / pollution 三因子）
        -- 注意：wave_defense 每 90 tick 会用 wave_number*0.001 覆盖 evolution_factor，
        -- 故实际生效的是“波次驱动进化”；此处确保底层自然进化系统处于启用状态。
        enemy_evolution = {
            enabled = true,
            time_factor = 0.000003,
            destruction_factor = 0.002,
            pollution_factor = 0.00001,
        },
    },

    -- 自然扩张：显式开启（覆盖 global 默认，防止被重置）
    -- 虫巢会主动向玩家基地（中心）扩张，与四路波次进攻叠加
    enemy_expansion = {
        enabled = true,
        max_expansion_cooldown = 60 * 60 * 30,
        min_expansion_cooldown = 60 * 60 * 5,
        max_expansion_distance = 20,
        settler_group_min_size = 5,
        settler_group_max_size = 50,
    },

    -- 十字地形生成器
    terrain_generator = terrain_generator,

    -- 火焰塔禁止
    max_flame = 0,

    -- 四路同时进攻：由 main.lua get_biter_point 读取本配置生成四个通道远端出生点
    biter_spawn_rule = {
        four_way = {
            {0, -200},   -- 下通道
            {200, 0},    -- 右通道
            {0, 200},    -- 上通道
            {-200, 0},   -- 左通道
        },
    },

    -- 弹药减伤
    ammo_damage_modifiers = {
        ['grenade'] = -0.5,
        ['landmine'] = -0.5,
        ['flamethrower'] = -0.6,
        ['artillery-shell'] = -0.5,
    },

    -- 堡垒生成：四通道远端(±500)各一个，轮流放置（custom_4way 模式，见 enemy_arty.lua）
    arty_settings = {
        interval = 20,
        start_wave = 250,
        mode = 'custom_4way',
    },

    -- 无星球解锁
    planet_surfaces = nil,
    unlock_planet_technologies = false,
    planet_resource_boost = false,

    -- 开局解锁科技统一由框架 main.lua reset_map 经 on_world_start 钩子调用 init_technologies 处理（见下方 on_world_start 字段）
    unlocked_technologies = {},

    -- 填海：允许（用户要求不限制）
    landfill_allowed = true,

    -- 通关奖励（框架 world_bonus·线性增长模式）：初始生命值。
    -- 2000 波通关解锁 +100；之后每坚守 100 波再 +10，**不设上限**（不声明 max_value）。
    -- 只按历史最高波数计算、取最高值不叠加；force 级 modifier，所有世界通用。
    world_bonus_type = {
        name = 'character_health_bonus',
        force_modifier = 'character_health_bonus',
        base_value = 100,
        growth_value = 10
        -- 不声明 max_value = 不封顶
    },
    -- 通关奖励按世界覆写（tank.lua / gui.lua / diff.lua 经 World.get_field 查表；未声明的世界用全局默认 1500/500）
    world_bonus_start_wave = 2000,
    world_bonus_interval = 100,

    -- 参与终极奖励
    joins_solar_system_edge = true,

    -- ===== 以下字段供框架外模块（main/tank/rock/ic/gui/tianfu/...）按世界查询，
    --        消除散落的 world_number == 15 判断（验收：框架外不得出现 world_number == XX）=====

    -- 免费弹药系统：禁用 auto_put_turret 的扣背包弹逻辑（世界15 由 world15_supply_tick 持续补弹）
    free_turret_ammo = true,

    -- 天赋间隔：每 15 级 +1 天赋（与竞技场一致；默认 35，由 tianfu.lua 经 World 配置表读取）
    tianfu_jiange = 15,


    -- 汽车内禁止生成矿物 / 禁止暂停波防（纯塔防无矿设计）
    disable_car_resource_generation = true,
    disable_stop_wave = true,

    -- 禁用传说木箱
    disable_legendary_wood_chest = true,

    -- 挖岩石 / 矿脉不掉落任何矿石（纯塔防无矿）
    disable_rock_ore = true,

    -- 岩石市场屏蔽列表（不进入市场）
    blocked_market_offers = {
        ['loader'] = true, ['fast-loader'] = true,
        ['express-loader'] = true, ['turbo-loader'] = true,
        ['artillery-shell'] = true,
    },

    -- 岩石市场固定物品（按“所有物品价值表”定价，round(v)）
    -- 炮塔：4 种 × 5 品质。
    --   普通(normal)价格不变；精良=普通+现精良；稀有=普通+现精良+现稀有；
    --   史诗=普通+现精良+现稀有+现史诗；传说=普通+现精良+现稀有+现史诗+现传说。
    --   （即除普通外各品质价格 = 普通价 + 从精良到自身当前价累加）
    rock_shop_extra_items = {
        {name = 'gun-turret',    quality = 'normal',   gold = 223},
        {name = 'gun-turret',    quality = 'uncommon', gold = 513},
        {name = 'gun-turret',    quality = 'rare',     gold = 870},
        {name = 'gun-turret',    quality = 'epic',     gold = 1294},
        {name = 'gun-turret',    quality = 'legendary',gold = 1852},
        {name = 'laser-turret',  quality = 'normal',   gold = 1159},
        {name = 'laser-turret',  quality = 'uncommon', gold = 2666},
        {name = 'laser-turret',  quality = 'rare',     gold = 4520},
        {name = 'laser-turret',  quality = 'epic',     gold = 6722},
        {name = 'laser-turret',  quality = 'legendary',gold = 9620},
        {name = 'rocket-turret', quality = 'normal',   gold = 3235},
        {name = 'rocket-turret', quality = 'uncommon', gold = 7441},
        {name = 'rocket-turret', quality = 'rare',     gold = 12617},
        {name = 'rocket-turret', quality = 'epic',     gold = 18764},
        {name = 'rocket-turret', quality = 'legendary',gold = 26852},
        {name = 'tesla-turret',  quality = 'normal',   gold = 5015},
        {name = 'tesla-turret',  quality = 'uncommon', gold = 11535},
        {name = 'tesla-turret',  quality = 'rare',     gold = 19559},
        {name = 'tesla-turret',  quality = 'epic',     gold = 29088},
        {name = 'tesla-turret',  quality = 'legendary',gold = 41626},
        {name = 'land-mine',            gold = 17},
        {name = 'construction-robot',   gold = 245},
        {name = 'passive-provider-chest', gold = 379},
        {name = 'mech-armor',                      gold = 130393},
        {name = 'fusion-reactor-equipment',        gold = 203995},
        {name = 'battery-mk3-equipment',           gold = 53744},
        {name = 'energy-shield-mk2-equipment',     gold = 8677},
        {name = 'exoskeleton-equipment',           gold = 7247},
        {name = 'personal-laser-defense-equipment', gold = 13683},
        {name = 'personal-roboport-mk2-equipment', gold = 28418},
    },

    -- 车载开局物资钩子：仅发战斗类物品 + 1000 金币 + 20 个传说机枪炮塔（函数定义在下方）
    on_car_placed = on_car_placed,

    -- 天赋黑名单（世界15 禁用建造 / 生产 / 科技类天赋）
    disabled_talents = {
        fuzhushou = true, ylsgd = true, gongchengche = true, jiansheche = true,
        jidiche = true, gcd = true, zishenzhuanjia = true, shoucuo_de_shen = true,
        shouyiren = true, xuetu = true, bulider = true, rsrl = true,
        scmcc = true, yelianche = true, dianluban = true, ftlt = true,
        keyan = true, kejigongsi = true, xueshu = true, kxj = true,
        qiche_ren = true, haiguanfang = true, beibaozhengli = true,
        waixinglaike = true, gycs = true, jndd = true, kytd = true,
    },

    -- 放行游戏原生自然进化（不覆盖 evolution_factor）
    use_native_evolution = true,

    -- Boss 接口（由 wave_defense 按世界查询调用）
    spawn_boss = spawn_boss,
    boss_interval = BOSS_INTERVAL,
    unlock_progressive_techs = unlock_progressive_weapon_techs,

    -- 开局科技解锁钩子：每次「进入 / 重进」世界15 时由框架 main.lua reset_map 调用。
    -- 修复「火箭发射井爆炸后重进世界15，科技无法正常解锁」——此前解锁仅靠世界模块 on_nth_tick
    -- 自驱动且受持久化标志保护，重进世界时不重新触发。现统一在框架重进入口执行，稳定可靠。
    on_world_start = world15_on_world_start,

    -- 四路同时进攻：每路按整波压力生成（不平分威胁）
    spawn_threat_divisor = 1,

    -- 每路并排小队编制（wave_defense/main.lua spawn_unit_group 查表消费）
    -- 定义即生效：每个生成点派 3 支小队、横向铺开 24 tile、相邻队错峰 60 tick、每队 28 只。
    -- 其他世界不定义此字段 → 退化为「一个生成点一支满编队伍、当场落地」，行为与改动前一致。
    spawn_squad_config = W15_SQUAD_CONFIG,

    -- 世界15 专属波次间隔曲线（diff.lua set_diff 查表消费）
    -- 定义即接管：通用的 2420 / 1380 / 1080 / 1300~2005 强制段对世界15 全部作废。
    wave_interval_segments = W15_WAVE_INTERVAL_SEGMENTS,

    -- 波次强度重映射（框架扩展点，wave_defense 按世界查询）：
    -- 1000 波后按 2.25 倍斜率线性加速虫子成长，让后期强度跟得上科技节奏。
    --   有效强度波数 = 1000 + (波数 - 1000) * 2.25
    --   校验点：w1000=1000  w2000=3250  w3000=5500  w4000=7750  w5000=10000
    -- 影响：兵种池、威胁值增长、品质虫概率、撼地虫出场时机。
    -- 仅影响强度计算，不改变真实 wave_number（GUI 波次显示 / Boss 间隔 / 科技等级 / 2000 波胜利判定均不受影响）。
    --
    -- ⚠️ 相比旧式 `2000 + (wave-1000)*2` 的关键修正：旧式在 w1000→w1001 处从 1000 直接跳到 2002，
    -- 一波之内强度翻倍 —— 玩家在 1000 波整点会遭遇断崖式团灭。新式在 w1000 处连续（1000→1002.25），
    -- 且终点 w5000 仍等于 10000，后期强度总量不变，只是把断崖摊平成斜坡。
    wave_strength_remap = function(wave_number)
        if wave_number > 1000 then
            return 1000 + (wave_number - 1000) * 2.25
        end
        return wave_number
    end,

    -- 该世界参与随机选世界池
    selectable = true,

    --==========================================================================
    -- 声明式事件订阅（框架 framework.lua 统一分发，本模块不自行 Event.add）
    --
    -- 分发规则：框架为每个被声明过的事件建立唯一分发器，运行时查
    -- WPT.get().world_number 命中本 def 才调用；非世界15 时不会执行任何 handler。
    -- handler 内部保留的 world_number ~= 15 自守为双保险（重进/边界态）。
    --==========================================================================
    events = {
        -- Boss 死亡奖励 → 卡片7 击杀统计 → 炮塔注销（按序调用，顺序即数组顺序）
        [defines.events.on_entity_died] = {on_boss_died, world15_on_enemy_died, on_turret_died},
        -- 建筑限制：仅中心正方形（玩家 / 施工机器人同规则）
        [defines.events.on_built_entity] = on_built_entity,
        [defines.events.on_robot_built_entity] = on_robot_built_entity,
        -- 区块加载：通道虫巢生成（仅十字陆地、距中心 > 384 tile）+ 清岩石 + 清海面怪
        [defines.events.on_chunk_generated] = {spawn_nests_in_chunk, clear_rocks_in_chunk, cleanup_sea_enemies_in_chunk},
        -- 卡片1 全服强化投票：卡片点击
        [defines.events.on_gui_click] = on_world15_vote_click,
        -- 加入游戏：开局物资 + 补弹投票框
        [defines.events.on_player_joined_game] = on_player_joined_game,
    },

    nth_tick = {
        [1] = {
            -- 四通道清剿奖励：虫巢重铺的分帧批处理（无任务时首行即返回，常态零开销）
            world15_nest_refill_tick,
        },
        [10] = {
            -- N-03/N-04：遍历已登记炮塔表补电/补弹。原 nth_tick[1]=每 tick 60/s，炮塔多时成为 tick 海啸；
            -- 实测未联网 electric-turret 能量不会每 tick 被引擎清零（静置 2.5s 仍保留 ~83%），
            -- 降到 [10]=6/s 即可维持炮塔满电，遍历频率降至 1/10（60/s → 6/s）。
            world15_supply_tick,
        },
        [60] = {
            on_tick,                    -- 主循环：胜利检测 / 通关记录 / world_bonus
            enforce_world15_techs,      -- 按波次分段解锁 + 自愈锁回科技
            enforce_world15_wave_params,-- 活跃虫上限 400 幂等重申（四路×三队全落地的前提）
            enforce_initial_terrain,    -- 开局一次性十字地形校正（跑一次后自锁）
            world15_vote_tick,          -- 卡片1：每 20 波发起投票 + 30s 倒计时结算
            world15_reassert_modifiers, -- 卡片1：永久 modifier 幂等重申
            world15_perfect_tick,       -- 卡片7：完美波挑战 + 连击统计
            world15_nest_check_tick,    -- 四通道清剿奖励：每 50 波检测通道虫巢是否清空
        },
        [600] = {
            boss_watchdog,               -- Boss 卡住检测 + 重新下令攻中心（每10秒）
            cleanup_sea_enemies_periodic,-- 海面禁刷：清除海面上的敌人（Boss除外）
        },
    },
})

return world15
