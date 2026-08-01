-- maps/amap/world/worlds/world_15_tower_defense.lua
-- 世界 15：塔防·四面楚歌
--
-- 特点：十字海心地形，四路同时进攻，纯塔防金币经济Boss系统
-- 权威标准：当前代码实现即为世界15设计依据（原 世界15_设计文档.md 已废弃删除）

local World = require 'maps.amap.world.framework'
local WPT = require 'maps.amap.table'
local diff = require 'maps.amap.diff'
local Event = require 'utils.event'
local WD = require 'modules.wave_defense.table'

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


-- Boss
local BOSS_INTERVAL = 100              -- 每 100 波

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
            local cx = gx + NEST_SCAN_STEP / 2
            local cy = gy + NEST_SCAN_STEP / 2

            -- 仅限十字陆地（中心正方形 + 4 通道），海面 / 对角线海域禁止
            if not is_on_cross_land(cx, cy) then goto next_cell end

            -- 距中心半径内禁止（与中心正方形保持距离）
            if (cx * cx + cy * cy) <= r2 then goto next_cell end

            -- 确定性伪随机（坐标哈希），保证每次重开可复现
            local h = math.sin(cx * 12.9898 + cy * 78.233) * 43758.5453
            h = h - math.floor(h)
            if h < NEST_DENSITY then
                local t = NEST_TYPES[((math.floor(cx) + math.floor(cy)) % #NEST_TYPES) + 1]
                local pos = surface.find_non_colliding_position(t, {x = cx, y = cy}, 4, 1)
                if pos and is_on_cross_land(pos.x, pos.y) then
                    surface.create_entity({name = t, position = pos, force = "enemy"})
                end
            end
            ::next_cell::
        end
    end
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
    game.print({'amap.world15_terrain_fixed'}, {r = 0.5, g = 1, b = 0.5})
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
        game.print({'amap.world15_boss_command_failed', tostring(err_b)}, {r = 1, g = 0.4, b = 0.4})
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

    -- 四个通道按波次轮流：下 → 右 → 上 → 左（每 100 波推进一个通道）
    local channel_names = {"下通道", "右通道", "上通道", "左通道"}
    local channel_offsets = {
        {x = 0, y = -SPAWN_DISTANCE},    -- 下通道
        {x = SPAWN_DISTANCE, y = 0},     -- 右通道
        {x = 0, y = SPAWN_DISTANCE},     -- 上通道
        {x = -SPAWN_DISTANCE, y = 0},    -- 左通道
    }
    local channel_index = ((tier - 1) % #channel_offsets) + 1
    local channel_name = channel_names[channel_index]
    local entry = {
        x = center.x + channel_offsets[channel_index].x,
        y = center.y + channel_offsets[channel_index].y,
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

        local this = WPT.get()
        if not this.world15_bosses then this.world15_bosses = {} end
        this.world15_bosses[boss.unit_number] = {
            wave = wave_number,
            reward = 1000 * tier,                          -- 每 100 波 +1000 金币
            max_hp = boss_hp,
            spawn_pos = boss_pos,
            revives_left = tier - 1,                       -- 100波=0次, 200波=1次 ...
            death_dmg_pct = tier >= 2 and (50 + (tier - 2) * 5) or 0,  -- 200波=50%, 300波=55% ...
            entity = boss,                                 -- 看门狗重新下令用
        }
        game.print({"amap.world15_boss_spawn", wave_number, math.floor(boss_hp)},
            {r = 1, g = 0.3, b = 0})
        game.print({'amap.world15_boss_channel', channel_name}, {r = 1, g = 0.6, b = 0})
    end
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
            game.print({'amap.world15_boss_diagnostic', tostring(entity.unit_number), table.concat(keys, ",")},
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

    -- 完全击杀：全员发放金币（每个在线玩家，不卡势力）
    if not this.world15_player_gold then this.world15_player_gold = {} end
    for _, player in pairs(game.connected_players) do
        local pidx = player.index
        this.world15_player_gold[pidx] = (this.world15_player_gold[pidx] or 0) + bd.reward
        player.print({"amap.world15_boss_reward", math.floor(bd.reward)},
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
-- 科技初始化：开局解锁全部科技，以下三类除外（开局不解锁）
--   1) 武器伤害类：physical-projectile-damage / stronger-explosives / refined-flammables / energy-weapons-damage / laser-weapons-damage
--   2) 射速类（通用武器射速 + 炮台专属射速 + 武器射速）：weapon-shooting-speed / gun-turret-speed / laser-turret-speed / laser-shooting-speed —— 以上两类在 1000 波前分段解锁
--   3) 永久升级类：采矿/机器人/火炮/机械臂/刹车/生产力等 —— 1000 波后每 100 波实际推进一级（免资源）
--==============================================================================

local DISABLED_TECHNOLOGIES_LIST = {
    "physical-projectile-damage-1", "physical-projectile-damage-2", "physical-projectile-damage-3",
    "physical-projectile-damage-4", "physical-projectile-damage-5", "physical-projectile-damage-6",
    "physical-projectile-damage-7", "physical-projectile-damage-8",
    "stronger-explosives-1", "stronger-explosives-2", "stronger-explosives-3",
    "stronger-explosives-4", "stronger-explosives-5", "stronger-explosives-6",
    "stronger-explosives-7", "stronger-explosives-8",
    "refined-flammables-1", "refined-flammables-2", "refined-flammables-3",
    "refined-flammables-4", "refined-flammables-5", "refined-flammables-6",
    "refined-flammables-7", "refined-flammables-8",
    "energy-weapons-damage-1", "energy-weapons-damage-2", "energy-weapons-damage-3",
    "energy-weapons-damage-4", "energy-weapons-damage-5", "energy-weapons-damage-6",
    "energy-weapons-damage-7", "energy-weapons-damage-8",
    "laser-weapons-damage-1", "laser-weapons-damage-2", "laser-weapons-damage-3",
    "laser-weapons-damage-4", "laser-weapons-damage-5", "laser-weapons-damage-6",
    "laser-weapons-damage-7", "laser-weapons-damage-8",
    "gun-turret-speed-1", "gun-turret-speed-2", "gun-turret-speed-3",
    "gun-turret-speed-4", "gun-turret-speed-5", "gun-turret-speed-6",
    "gun-turret-speed-7", "gun-turret-speed-8",
    "laser-turret-speed-1", "laser-turret-speed-2", "laser-turret-speed-3",
    "laser-turret-speed-4", "laser-turret-speed-5", "laser-turret-speed-6",
    "laser-turret-speed-7", "laser-turret-speed-8",
    "weapon-shooting-speed-1", "weapon-shooting-speed-2", "weapon-shooting-speed-3",
    "weapon-shooting-speed-4", "weapon-shooting-speed-5", "weapon-shooting-speed-6",
    "weapon-shooting-speed-7", "weapon-shooting-speed-8",
    "laser-shooting-speed-1", "laser-shooting-speed-2", "laser-shooting-speed-3",
    "laser-shooting-speed-4", "laser-shooting-speed-5", "laser-shooting-speed-6",
    "laser-shooting-speed-7", "laser-shooting-speed-8",
    "mining-productivity-1", "mining-productivity-2", "mining-productivity-3",
    "mining-productivity-4", "mining-productivity-5",
    "worker-robot-speed-1", "worker-robot-speed-2", "worker-robot-speed-3",
    "worker-robot-speed-4", "worker-robot-speed-5", "worker-robot-speed-6",
    "worker-robot-speed-7", "worker-robot-speed-8",
    "worker-robot-storage-1", "worker-robot-storage-2", "worker-robot-storage-3",
    "follower-robot-count-1", "follower-robot-count-2", "follower-robot-count-3",
    "follower-robot-count-4", "follower-robot-count-5", "follower-robot-count-6",
    "follower-robot-count-7", "follower-robot-count-8",
    "artillery-shell-range-1", "artillery-shell-range-2", "artillery-shell-range-3",
    "artillery-shell-range-4", "artillery-shell-range-5", "artillery-shell-range-6",
    "artillery-shell-range-7", "artillery-shell-range-8",
    "artillery-shell-speed-1", "artillery-shell-speed-2", "artillery-shell-speed-3",
    "artillery-shell-speed-4", "artillery-shell-speed-5", "artillery-shell-speed-6",
    "artillery-shell-speed-7", "artillery-shell-speed-8",
    "inserter-capacity-bonus-1", "inserter-capacity-bonus-2", "inserter-capacity-bonus-3",
    "inserter-capacity-bonus-4", "inserter-capacity-bonus-5", "inserter-capacity-bonus-6",
    "inserter-capacity-bonus-7", "inserter-capacity-bonus-8",
    "steel-plate-productivity", "scrap-recycling-productivity",
    "plastic-bar-productivity", "rocket-fuel-productivity",
    "processing-unit-productivity", "low-density-structure-productivity",
    "rocket-part-productivity",
    "braking-force-2", "braking-force-3", "braking-force-4",
    "braking-force-5", "braking-force-6", "braking-force-7", "braking-force-8",
}

--==============================================================================
-- 武器伤害类 + 射速类科技：1000 波前分段全部解锁
--==============================================================================

-- 需要按波次进度解锁的武器伤害 / 射速科技（9 类 × 8 级 = 72 项）
-- 世界 15 开局不解锁这些科技，而是随波次推进自动研究，全部在 1000 波前完成。
-- 其余被禁用科技（永久升级类）保持锁定，直到 1000 波后才分阶段开放。
local WEAPON_DAMAGE_CATEGORIES = {
    {id = "physical-projectile-damage", cn = "物理弹道伤害"},  -- 机枪 / 子弹伤害
    {id = "stronger-explosives",        cn = "爆炸伤害"},       -- 火箭 / 爆破伤害
    {id = "refined-flammables",         cn = "火焰伤害"},        -- 火焰伤害（备用）
    {id = "energy-weapons-damage",      cn = "电力武器伤害"},   -- 电力 / 特斯拉能量伤害
    {id = "laser-weapons-damage",       cn = "激光武器伤害"},   -- 激光武器专属伤害（独立于 energy-weapons-damage）
    -- 射速类：通用武器射速 + 炮台专属射速科技（机枪炮塔 / 激光炮塔）
    {id = "weapon-shooting-speed",      cn = "武器射速"},        -- 通用射击速度
    {id = "gun-turret-speed",           cn = "机枪炮塔射速"},
    {id = "laser-turret-speed",         cn = "激光炮塔射速"},
    {id = "laser-shooting-speed",       cn = "激光武器射速"},
}

-- 生成解锁时间表（交错排列：先逐类解锁第 1 级，再进第 2 级……保证各类型均衡成长）
-- 分布范围：首级 ≈ 第 10 波，末级 ≈ 第 990 波（1000 波前全部完成）
local WEAPON_TECH_SCHEDULE = {}
do
    local LEVELS = 8
    local FIRST_WAVE = 10
    local LAST_WAVE = 990
    local total = #WEAPON_DAMAGE_CATEGORIES * LEVELS  -- 64
    local idx = 0
    for lvl = 1, LEVELS do
        for _, cat in ipairs(WEAPON_DAMAGE_CATEGORIES) do
            idx = idx + 1
            local wave = FIRST_WAVE + math.floor((idx - 1) * (LAST_WAVE - FIRST_WAVE) / (total - 1))
            WEAPON_TECH_SCHEDULE[idx] = {
                tech = cat.id .. "-" .. lvl,
                cat_cn = cat.cn,
                lvl = lvl,
                wave = wave,
            }
        end
    end
end

-- 根据当前波次，逐条核对进度表科技（【自愈式】，不再依赖持久化波次做节流）：
--   · 已到解锁波次（entry.wave <= current_wave）→ 确保解锁（仅首次解锁时提示）
--   · 尚未到解锁波次 → 强制保持锁定（即便读档 / 框架误解锁，下一波次立即纠正）
-- 旧写法用「区间增量 + last_wave 持久化」节流，读档后 last_wave 重置为 0、current_wave 已是存档内高波次，
-- 首帧就把进度表内全部科技一次性解锁 —— 即“开局三类被提前解锁”的根因。
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

local function unlock_progressive_weapon_techs_for_force(force, current_wave)
    -- 第一遍（升序）：按波次解锁。低级先于高级处理，保证依赖链满足。
    for _, entry in ipairs(WEAPON_TECH_SCHEDULE) do
        local tech = force.technologies[entry.tech]
        if tech and entry.wave <= current_wave and not tech.researched then
            tech.researched = true
            game.print({"amap.world15_tech_unlock", entry.cat_cn .. " Lv" .. entry.lvl},
                {r = 1, g = 0.7, b = 0.2})
        end
    end
    -- 第二遍（降序）：未到解锁波次 → 强制锁回（自愈）。
    -- 高等级先于低等级处理：避免「低等级因高等级仍被研究而无法回锁」导致整族残留
    -- （真实 bug：框架默认把整族 1..N 级全部解锁，若只升序回锁，level1 回锁会因 level2 已研究而失败）。
    for i = #WEAPON_TECH_SCHEDULE, 1, -1 do
        local entry = WEAPON_TECH_SCHEDULE[i]
        local tech = force.technologies[entry.tech]
        if tech and entry.wave > current_wave and tech.researched then
            pcall(function() tech.researched = false end)
        end
    end
end

local function unlock_progressive_weapon_techs(current_wave)
    -- 对每个在线玩家的真实势力执行（玩家势力可能不是默认 game.forces.player）
    for _, force in pairs(world15_get_player_forces()) do
        unlock_progressive_weapon_techs_for_force(force, current_wave)
    end
end

--==============================================================================
-- 永久升级类科技：1000 波后、2000 波前，每 100 波（1100/.../1900）实际推进一级
--   推进方式：force.add_research 排队 + 直接置 researched=true，完全免消耗科研资源
--==============================================================================

-- 永久升级类科技前缀（无限研究 / 永久加成）：开局不解锁，留待后期分阶段开放
local PERMANENT_UPGRADE_PREFIXES = {
    "mining-productivity",          -- 采矿生产力（无限）
    "worker-robot-speed",           -- 施工机器人速度
    "worker-robot-storage",         -- 施工机器人储物
    "follower-robot-count",         -- 跟随机器人数量
    "artillery-shell-range",        -- 火炮射程
    "artillery-shell-speed",        -- 火炮弹速
    "inserter-capacity-bonus",      -- 机械臂吞吐
    "braking-force",                -- 刹车力
    "steel-plate-productivity", "scrap-recycling-productivity", "plastic-bar-productivity",
    "rocket-fuel-productivity", "processing-unit-productivity", "low-density-structure-productivity",
    "rocket-part-productivity",     -- 各类生产力（无限）
}

-- 永久升级类科技：1000 波后、2000 波前，每 100 波（1100/1200/.../1900）实际推进一级
-- 推进方式：force.add_research 排队当前等级 + 直接置 researched=true，完全免消耗任何科研资源
-- （Factorio 标准免资源即时研究手法：infinite 科技每完成一次研究即等级 +1）
local function unlock_permanent_upgrades_for_force(force, current_wave)
    -- 1000 波前：强制锁住全部永久升级类（【自愈】：读档或任何误解锁后下一波次立即纠正）
    if current_wave <= 1000 then
        for _, tech in pairs(force.technologies) do
            repeat
                if not tech.enabled then break end
                local matched = false
                for _, prefix in ipairs(PERMANENT_UPGRADE_PREFIXES) do
                    if tech.name == prefix or tech.name:find("^" .. prefix .. "%-") then
                        matched = true
                        break
                    end
                end
                if not matched then break end
                if tech.researched then
                    pcall(function() tech.researched = false end)
                end
            until true
        end
        return false
    end

    -- 仅在第 1100~1900 波、且为 100 的整数倍时推进一级（与 on_tick 调用保持一致）
    if current_wave >= 2000 or (current_wave % 100 ~= 0) then return false end

    for name, tech in pairs(force.technologies) do
        repeat
            if not tech.enabled then break end

            -- 前缀匹配永久升级类
            local matched = false
            for _, prefix in ipairs(PERMANENT_UPGRADE_PREFIXES) do
                if name == prefix or name:find("^" .. prefix .. "%-") then
                    matched = true
                    break
                end
            end
            if not matched then break end

            -- 已满级则跳过（max_level == 0 表示无限研究）

            local proto = tech.prototype
            local max_level = (proto and proto.max_level) or 1
            if max_level == 0 then max_level = 1e9 end
            if tech.level >= max_level then break end

            if not tech.researched then
                -- 首次触发（第 1100 波）：开放至第 1 级
                tech.researched = true
            else
                -- 已开放：免资源推进一级
                -- 仅当当前没有其它研究在进行时推进，避免干扰玩家手动研究队列
                if force.current_research == nil then
                    local ok = pcall(function() force.add_research(name) end)
                    if ok then
                        local cr = force.current_research
                        if cr and cr.name == name then
                            cr.researched = true  -- 直接完成当前等级研究，不消耗科技包
                        end
                    end
                end
            end
        until true
    end

    return true
end

local function unlock_permanent_upgrades(current_wave)
    local this = WPT.get()
    -- 同一 100 波节点只推进一次（避免读档/多势力重复升级）
    if this then
        local last_perm = this.world15_last_permanent_wave or 0
        if current_wave <= last_perm then return false end
    end
    -- 对每个在线玩家的真实势力执行（玩家势力可能不是默认 game.forces.player）
    local promoted = false
    for _, force in pairs(world15_get_player_forces()) do
        if unlock_permanent_upgrades_for_force(force, current_wave) then
            promoted = true
        end
    end
    -- 持久化已处理的 100 波节点
    if promoted and this then this.world15_last_permanent_wave = current_wave end
    return promoted
end

-- 世界15 玩家实际势力可能不是默认 game.forces.player（RPG/角色系统或框架会给玩家分配
-- 队伍势力——与「金币按 player.index 发放」同源）。科技解锁/锁回必须作用到玩家真实势力，
-- 否则只会动默认 player 势力、玩家真实势力的科技仍被提前解锁（即「开局科技提前解锁」真凶）。
-- 该 helper 的定义见文件前部（unlock_progressive_weapon_techs 之前），供三处科技函数遍历调用。

-- 对单个势力执行：开局解锁全部非禁用科技，并兜底锁回三类暂不解锁科技。
local function init_technologies_for_force(force)
    -- 预计算需要跳过的科技名：禁用项本身 + 其无限研究派生系列（如 gun-turret-speed-* / laser-turret-speed-*）
    local skip = {}
    for _, dname in ipairs(DISABLED_TECHNOLOGIES_LIST) do
        skip[dname] = true
    end
    for name, _ in pairs(force.technologies) do
        for _, dname in ipairs(DISABLED_TECHNOLOGIES_LIST) do
            local base = dname:gsub("%-%d+$", "")
            if name ~= dname and name:find("^" .. base .. "%-") then
                skip[name] = true
                break
            end
        end
    end

    -- 定点迭代解锁：每轮解锁当前无前置阻碍的科技，下一轮再解锁依赖它们的科技。
    -- 用 pcall 包裹 researched=true，避免「前置未满足」抛错中断整轮（部分科技有前置依赖链）。
    local changed = true
    local guard = 0
    while changed and guard < 50 do
        changed = false
        guard = guard + 1
        for name, tech in pairs(force.technologies) do
            if not skip[name] and tech.enabled and not tech.researched then
                local ok = pcall(function() tech.researched = true end)
                if ok then changed = true end
            end
        end
    end

    -- 兜底：强制把「暂不解锁」科技重置为未研究，确保开局一定锁着。
    -- （即便框架层或其它逻辑提前开放了它们，这里也会纠正；后续由分段解锁函数按波次逐渐开放。）
    -- 按禁用表【逆序】（高等级先于低等级）回锁，避免「低等级因高等级已研究而无法回锁」的级联失败。
    for i = #DISABLED_TECHNOLOGIES_LIST, 1, -1 do
        local name = DISABLED_TECHNOLOGIES_LIST[i]
        local tech = force.technologies[name]
        if tech then pcall(function() tech.researched = false end) end
    end
end

local function init_technologies()
    -- 双重判断：world_number 或 diff.get().world 任一为 15 即放行。
    -- world_number 在 reset_map 中赋值、diff.get().world 在选世界后更新，两者时机不同；
    -- 用「或」避免任一方尚未就绪时过早 return（曾导致开局科技永不解锁）。
    local this = WPT.get()
    local map = diff.get()
    if not this or (this.world_number ~= 15 and (not map or map.world ~= 15)) then return end

    this.world15_techs_unlocked = this.world15_techs_unlocked or {}
    -- 对每个在线玩家的真实势力执行初始化（幂等，per-force），避免只动默认 player 势力。
    for _, force in pairs(world15_get_player_forces()) do
        if not this.world15_techs_unlocked[force.index] then
            init_technologies_for_force(force)
            this.world15_techs_unlocked[force.index] = true
        end
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

        -- 先解锁科技
        init_technologies()

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

        -- N-04：供电由 world15_supply_tick 每 tick 遍历已登记炮塔表强制设能量（事件注册式，无区域扫描），
        -- 不依赖任何真实电网实体（无 roboport / solar / 电线杆）。故世界15不铺设 roboport，
        -- 避免引入额外耗电实体；玩家如需建设/维修机器人网络，可在市场购买 roboport。
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

    -- 兼容两种调用签名：Event.on_nth_tick 传标准 event 对象，框架可能传 (this, tick)
    local tick = type(event) == 'table' and event.tick or (type(event) == 'number' and event)
    if not tick then return end


    -- 胜利条件：坚守 2000 波
    local wave_number = WD.get('wave_number') or 0

    if wave_number >= 2000 then
        for _, player in pairs(game.connected_players) do
            if player.force == game.forces.player then
                player.print({"amap.world15_victory"}, {r = 1, g = 0.85, b = 0})
            end
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

    -- 一次性解锁非禁用科技（受 world15_techs_unlocked 标志保护，仅首次真正执行）
    init_technologies()

    local wave_number = WD.get('wave_number') or 0

    -- 武器伤害 / 射速：1000 波前分段解锁；未到波次「自愈锁回」
    unlock_progressive_weapon_techs(wave_number)
    -- 永久升级类：1000 波前锁住；1100~1900 每 100 波实际推进一级（免资源，推进受持久化守卫保护）
    if unlock_permanent_upgrades(wave_number) then
        local stage = math.floor((wave_number - 1000) / 100)
        game.print({"amap.world15_permanent_unlock", stage}, {r = 1, g = 0.7, b = 0.2})
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
                if turret.electric_buffer_size then
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
-- 事件注册
--==============================================================================

Event.add(defines.events.on_entity_died, on_boss_died)
Event.add(defines.events.on_built_entity, on_built_entity)
Event.on_nth_tick(60, on_tick)
Event.on_nth_tick(60, enforce_world15_techs)
Event.on_nth_tick(60, enforce_initial_terrain)       -- 开局一次性地形校正（跑一次后自锁）
Event.on_nth_tick(600, boss_watchdog)                -- Boss 卡住检测 + 重新下令攻中心（每10秒）
Event.on_nth_tick(600, cleanup_sea_enemies_periodic) -- 海面禁刷：每10秒清除海面上的敌人（Boss除外）
Event.on_nth_tick(1, world15_supply_tick)   -- N-03/N-04: 每 tick 遍历已登记炮塔表，laser/tesla 补电、gun/rocket 补弹（事件注册式，无区域扫描）

-- 区块加载时：通道虫巢生成（仅十字陆地、距中心 > 384 tile）+ 清理岩石（纯塔防无岩石）+ 清海面怪
Event.add(defines.events.on_chunk_generated, spawn_nests_in_chunk)
Event.add(defines.events.on_chunk_generated, clear_rocks_in_chunk)
Event.add(defines.events.on_chunk_generated, cleanup_sea_enemies_in_chunk)

Event.add(defines.events.on_player_joined_game, function(event)
    give_starter_items()
end)

-- 施工机器人建造同样受“仅中心正方形”限制
Event.add(defines.events.on_robot_built_entity, on_robot_built_entity)

Event.add(defines.events.on_entity_died, function(event)
    local entity = event.entity
    if entity and entity.valid then
        unregister_turret(entity)
    end
end)

-- 炮塔锁定：建造时设 minable_flag=false（引擎级禁拆）。已移除挖掘后原地重建逻辑。

--==============================================================================
-- 注册到框架
--==============================================================================

-- 车载开局物资钩子：世界15 仅发放战斗类物品（gun-turret / 弹药 / stone-wall）+ 1000 金币。
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

    -- 开局解锁科技（在 give_starter_items 中通过 init_technologies 处理）
    unlocked_technologies = {},

    -- 填海：允许（用户要求不限制）
    landfill_allowed = true,

    -- 通关奖励：激光炮塔伤害
    world_bonus_type = {
        name = 'character_laser_turret_damage_bonus',
        force_modifier = 'laser_turret_damage_modifier',
        base_value = 0.03,
        max_value = 0.20,
    },

    -- 参与终极奖励
    joins_solar_system_edge = true,

    -- ===== 以下字段供框架外模块（main/tank/rock/ic/gui/tianfu/...）按世界查询，
    --        消除散落的 world_number == 15 判断（验收：框架外不得出现 world_number == XX）=====

    -- 免费弹药系统：禁用 auto_put_turret 的扣背包弹逻辑（世界15 由 world15_supply_tick 持续补弹）
    free_turret_ammo = true,

    -- 天赋间隔：每 15 级 +1 天赋（竞技场一致；默认 35，由 tianfu.lua 经 World 配置表读取）
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

    -- 岩石市场固定物品（14 项，按“所有物品价值表”定价，round(v)）
    rock_shop_extra_items = {
        {name = 'gun-turret',           gold = 223},
        {name = 'laser-turret',         gold = 1159},
        {name = 'rocket-turret',        gold = 3235},
        {name = 'tesla-turret',         gold = 15000},
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

    -- 车载开局物资钩子：仅发战斗类物品 + 1000 金币（函数定义在下方）
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

    -- 四路同时进攻：每路按整波压力生成（不平分威胁）
    spawn_threat_divisor = 1,

    -- 该世界参与随机选世界池
    selectable = true,

    -- 注意：on_tick 通过 Event.on_nth_tick(60) 独立注册，不在此处挂载
    -- 框架的 on_tick 钩子签名为 (this, tick)，与标准 event 不兼容
})

return world15
