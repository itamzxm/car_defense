-- maps/amap/world/worlds/world_19_mechanical_canyon.lua
-- 世界 19：机械峡谷
--
-- 特点：长条狭谷。中间 192 格正常地型（同山谷），左右各 192 格极密集石头
--       （密度 = 山谷 5 倍，石下正常生成矿物；仅限距中心上下 1472 格内），
--       地图外为不可穿越的黑色虚空。虫子从上下两个方向进攻；沿长轴每隔
--       46 格自动生成不可摧毁/拆除的精良机器人指令塔（固定一条横向直线，
--       无自带电力，需玩家接电线杆供电），构成机器人连接骨架——
--       挖掘扩张与基地扩张绑定。

local World = require 'maps.amap.world.framework'
local WPT = require 'maps.amap.table'
local WD = require 'modules.wave_defense.table'
local diff = require 'maps.amap.diff'
local world_function = require 'maps.amap.world.world_function'
local tianfu = require 'maps.amap.tianfu'
local tianfu_table = require 'maps.amap.tianfu_table'

--==============================================================================
-- 常量
--==============================================================================

local MAP_HALF_WIDTH = 288              -- 地图半宽（横向宽 576 / 2）
local NORMAL_HALF_WIDTH = 96            -- 中间正常地型半宽（192 / 2）
local ROCK_BAND_HALF_LENGTH = 1472      -- 石头带纵向范围：距中心上下 1472 格内才生成
local TOWER_INTERVAL = 46               -- 指令塔间隔（格），从中心向左右延伸
local TOWER_Y = 0                       -- 指令塔固定横向直线（y 完全一致）
local WAVE_SPAWN_DISTANCE = 128         -- 波虫生成距离：上下 128 格外，可随建筑后移
local TALENT_CAP = 60                   -- 本图任意玩家天赋上限（到达后无论如何无法获取）

-- 科技瓶 → 天赋数（首次研究含该瓶的科技即发放；90k 金币池 / 不计 20 限购 / 等同顶尖人才）
-- 橙/粉/草/靛/黑瓶为 Factorio 2.1 Space Age 本体科技瓶（冶金/电磁/农业/低温/钷素）
local SCIENCE_PACK_TALENTS = {
    ['logistic-science-pack'] = 1,          -- 绿瓶 +1
    ['military-science-pack'] = 1,          -- 灰瓶 +1
    ['chemical-science-pack'] = 1,          -- 蓝瓶 +1
    ['production-science-pack'] = 1,        -- 紫瓶 +1
    ['utility-science-pack'] = 1,           -- 黄瓶 +1
    ['space-science-pack'] = 1,             -- 白瓶 +1
    ['metallurgic-science-pack'] = 2,       -- 橙瓶（冶金）+2
    ['electromagnetic-science-pack'] = 2,   -- 粉瓶（电磁）+2
    ['agricultural-science-pack'] = 2,      -- 草瓶（农业）+2
    ['cryogenic-science-pack'] = 3,         -- 靛瓶（低温）+3
    ['promethium-science-pack'] = 5,        -- 黑瓶（钷素）+5
}

-- 石头抽奖（与 world_function.rock_raffle 保持一致）
local ROCK_RAFFLE = {
    'big-sand-rock', 'big-sand-rock',
    'big-rock', 'big-rock', 'big-rock', 'big-rock', 'big-rock', 'big-rock', 'big-rock',
    'huge-rock',
}

-- 生成点避让用的玩家建筑列表（与 main.lua get_biter_point 的 player_build 一致）
local PLAYER_BUILD = {
    'steam-turbine', 'assembling-machine-1', 'assembling-machine-2', 'assembling-machine-3',
    'oil-refinery', 'chemical-plant', 'car', 'spidertron', 'tank', 'character', 'gun-turret',
    'electric-mining-drill', 'laser-turret', 'steam-engine', 'big-mining-drill', 'foundry',
    'recycler', 'electromagnetic-plant', 'heating-tower', 'rail-support',
}

--==============================================================================
-- 地形生成器
--==============================================================================

local function abs_y_in_band(y)
    return math.abs(y) <= ROCK_BAND_HALF_LENGTH
end

local function terrain_generator(surface, position, seed, get_tile, set_tiles, event, maxs, q, w, x, y, area)
    local abs_x = math.abs(position.x)
    if abs_x > MAP_HALF_WIDTH then
        -- 地图外：无地型黑色区块，不可穿越
        set_tiles({{name = 'out-of-map', position = position}})
    elseif abs_y_in_band(position.y) and abs_x > NORMAL_HALF_WIDTH then
        -- 左右石头带（96 < |x| ≤ 288，且距中心上下 ≤ 960）：
        -- 密度 = 山谷 5 倍。山谷实测平均 ≈4%/格，本带取均匀 20%/格（固定比例）；
        -- 不设 can_place 检查——岩石直接叠放在矿上，即「石头下面正常生成矿物」
        -- （挖掉石头后露出矿脉，挖矿与扩张绑定）。
        if math.random(1, 100) <= 20 then
            surface.create_entity({
                name = ROCK_RAFFLE[math.random(1, #ROCK_RAFFLE)],
                position = position,
                force = 'neutral',
            })
        end
    else
        -- 中间 192 格与石头带纵向外（|y| > 960）：正常地型（同山谷）
        world_function.world_cave(surface, position, seed, get_tile)
    end
end

--==============================================================================
-- 精良机器人指令塔（不可摧毁/拆除，固定横向直线，无自带电力）
--==============================================================================

-- 固定 y = TOWER_Y，x 沿基准点 ±6 格微调直到放下（保证整行在同一条横线上）。
-- 放置前清掉占位 4×4 内的树/石；矿在占位内则 can_place 失败，自动换 x 偏移。
local function place_tower(surface, x0)
    for dx = -6, 6, 2 do
        local pos = {x = x0 + dx, y = TOWER_Y}
        local r = 2
        local blockers = surface.find_entities_filtered({
            area = {
                left_top = {x = pos.x - r, y = pos.y - r},
                right_bottom = {x = pos.x + r, y = pos.y + r},
            },
            type = {'tree', 'simple-entity'},
        })
        for _, e in pairs(blockers) do
            if e.valid then
                e.destroy()
            end
        end
        if surface.can_place_entity({name = 'roboport', position = pos}) then
            local roboport = surface.create_entity({
                name = 'roboport',
                position = pos,
                force = 'player',
                quality = 'uncommon',
                create_build_effect_smoke = false,
            })
            if roboport and roboport.valid then
                roboport.destructible = false
                roboport.minable_flag = false
            end
            return
        end
    end
end

-- 判断基准点附近是否已有指令塔（塔 x 可能微调，用区域查询）
local function tower_exists_near(surface, x0)
    local list = surface.find_entities_filtered({
        name = 'roboport',
        force = 'player',
        area = {
            left_top = {x = x0 - 8, y = TOWER_Y - 8},
            right_bottom = {x = x0 + 8, y = TOWER_Y + 8},
        },
        limit = 1,
    })
    return #list > 0
end

-- 区块生成：放置指令塔（y=0 行所在区块）+ 清理石头带树木 / 虚空带实体
local function on_chunk_generated(event)
    local this = WPT.get()
    if (this and this.world_number or 0) ~= 19 then return end

    local surface = event.surface
    if not surface or not surface.valid then return end
    if this.active_surface_index and surface.index ~= this.active_surface_index then return end

    local area = event.area
    local lt_x, lt_y = area.left_top.x, area.left_top.y

    -- 指令塔：仅 TOWER_Y 行所在的区块放置 x=±46k（≤ 地图边缘）的塔
    if lt_y == TOWER_Y then
        for tx = TOWER_INTERVAL, MAP_HALF_WIDTH, TOWER_INTERVAL do
            for _, sign in ipairs({1, -1}) do
                local x = tx * sign
                if x >= lt_x and x < lt_x + 32 then
                    place_tower(surface, x)
                end
            end
        end
    end

    -- 清理（先于 world_main 的 terrain_generator 执行，清出空地供石头落地）：
    --   石头带（96 < |x| ≤ 288 且 |y| ≤ 960）：清除树木，保留矿石（石下藏矿）
    --   虚空带（|x| > 288）：清除全部实体（矿/树/石/野外虫巢）
    local entities = surface.find_entities_filtered({area = area})
    for _, e in pairs(entities) do
        if e.valid then
            local ax = math.abs(e.position.x)
            if ax > MAP_HALF_WIDTH then
                e.destroy()
            elseif ax > NORMAL_HALF_WIDTH and math.abs(e.position.y) <= ROCK_BAND_HALF_LENGTH
                and e.type == 'tree' then
                e.destroy()
            end
        end
    end
end

--==============================================================================
-- 波虫：上下双向出波，生成点可随建筑后移
--==============================================================================

-- 基础规则 four_way = {{0,-128},{0,128}}（main.lua get_biter_point 消费）。
-- 本函数在 wave_defense 每 30 tick 刷虫前重申生成点，并把生成点沿 y 向外推
-- 到远离玩家建筑的位置（「可随建筑往后移」）。
local function world19_refresh_spawn_positions()
    local this = WPT.get()
    if (this and this.world_number or 0) ~= 19 then return end

    local target = WD.get('target')
    if not target or not target.valid then return end
    local surface = target.surface
    if not surface or not surface.valid then return end

    local tx = math.floor(target.position.x)
    local ty = math.floor(target.position.y)
    local positions = {}
    for _, dir in ipairs({-1, 1}) do
        local y = ty + dir * WAVE_SPAWN_DISTANCE
        local guard = 0
        while guard < 40 do
            local n = surface.count_entities_filtered({
                position = {x = tx, y = y},
                radius = 24,
                name = PLAYER_BUILD,
                force = 'player',
                limit = 1,
            })
            if n == 0 then break end
            y = y + dir * 32
            guard = guard + 1
        end
        positions[#positions + 1] = {x = tx, y = y}
    end
    WD.set('spawn_positions', positions)
end

--==============================================================================
-- 波次节奏：2000 波后每 100 波间隔 +2%，上限 +30%（3500 波封顶，波次降至 0.769×）
--==============================================================================

-- set_diff 每 60 tick 从零重算基础间隔，本函数在其后乘上放大系数（不累乘）。
local function world19_apply_wave_interval()
    local this = WPT.get()
    if (this and this.world_number or 0) ~= 19 then return end

    local wave = WD.get('wave_number') or 0
    if wave < 2000 then return end
    local steps = math.floor((wave - 2000) / 100)
    local mult = 1 + math.min(steps, 15) * 0.02
    if mult <= 1.000001 then return end
    local wd = WD.get_table()
    wd.wave_interval = math.floor(wd.wave_interval * mult + 0.5)
end

--==============================================================================
-- 天赋机制
--   · 50 级 +1 天赋（RPG 玩家等级）：tianfu_jiange = 50，由 tianfu.lua 消费
--   · 首次研究含各色科技瓶 → 发天赋（90k 金币池 / 不计 20 限购 / 等同顶尖人才）
--   · 本图任意玩家天赋 ≤ 60
--   · 每个玩家自动获得精良好运连连（hyll，品质精良 = q_idx 2）
--==============================================================================

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

-- 自动授予精良好运连连（触发天赋，品质精良 = q_idx 2，幂等）
local function world19_grant_hyll(player)
    if not player or not player.valid or player.force.name ~= 'player' then return end
    local main_table = WPT.get()
    if not main_table.skill[player.name] then
        main_table.skill[player.name] = {}
    end
    if main_table.skill[player.name].hyll then return end

    main_table.skill[player.name].hyll = 2
    if not main_table.tianfu_enabled[player.index] then
        main_table.tianfu_enabled[player.index] = {}
    end
    main_table.tianfu_enabled[player.index].hyll = true
    -- 倒排索引登记（与 tianfu.lua 方案 B 一致，供事件遍历/删除同步）
    local tpt = tianfu_table.get()
    if not tpt.skill_owners then tpt.skill_owners = {} end
    if not tpt.skill_owners.hyll then tpt.skill_owners.hyll = {} end
    tpt.skill_owners.hyll[player.index] = true
end

-- 入队一次科技瓶天赋发放（逐次弹窗，保证每个都走 90k 池且不叠弹窗）
local function world19_enqueue_talent(player_index, count)
    local this = WPT.get()
    if not this.world19_talent_queue then
        this.world19_talent_queue = {}
    end
    local e = this.world19_talent_queue[player_index]
    if not e then
        e = {remaining = 0, total = 0}
        this.world19_talent_queue[player_index] = e
    end
    e.remaining = e.remaining + count
    e.total = e.total + count
end

-- 逐次发放队列：玩家无打开的选择界面时弹一次（90k 池 = get_new_tianfu 'mid'）
local function world19_process_talent_queue()
    local this = WPT.get()
    if (this and this.world_number or 0) ~= 19 then return end
    local queue = this.world19_talent_queue
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
                -- 整条入队发放完毕：播报一次（总数量）
                player.print({'amap.world19_talent_grant', e.total}, {r = 0.4, g = 1, b = 0.4})
                queue[pidx] = nil
            end
        end
    end
end

-- reset_map 期间脚本强制研究的科技（main.lua 开局直接 researched=true 会触发完成事件，
-- 并非玩家真实研究）→ 不触发科技瓶天赋：
--   悬崖炸药 / 高级星岩处理 / 星岩再处理
local SCRIPT_RESEARCH_BLACKLIST = {
    ['cliff-explosives'] = true,
    ['advanced-asteroid-processing'] = true,
    ['asteroid-reprocessing'] = true,
}

-- 首次研究含某色科技瓶 → 给「本局还没拿过该瓶天赋」的在线玩家发天赋（按玩家记录，
-- 不再全局按瓶标记）。玩家中途加入 / 离线期间错过 → on_player_joined_game 补发。
local function world19_grant_science_talent(pack, count)
    local this = WPT.get()
    if not this.world19_science_granted then
        this.world19_science_granted = {}
    end
    local pack_tbl = this.world19_science_granted[pack]
    -- 兼容旧存档：旧代码存的是布尔标记（science_granted[pack] = true），按表索引会崩溃，
    -- 遇到非表值重建为玩家记录表（旧标记作废，视为本局重新获得资格）
    if type(pack_tbl) ~= 'table' then
        pack_tbl = {}
        this.world19_science_granted[pack] = pack_tbl
    end
    for _, player in pairs(game.connected_players) do
        if player and player.valid and player.force.name == 'player' then
            if not pack_tbl[player.name] then
                pack_tbl[player.name] = true
                world19_enqueue_talent(player.index, count)
            end
        end
    end
end

-- 首次研究含各色科技瓶 → 发天赋（每玩家每瓶每局只发一次）。
-- 脚本强制研究的科技（悬崖炸药/小行星处理等）在此拦截，不会误触发。
local function on_research_finished(event)
    local this = WPT.get()
    if (this and this.world_number or 0) ~= 19 then return end

    local tech = event.research
    if not tech or not tech.valid then return end
    if tech.force.index ~= game.forces.player.index then return end

    if SCRIPT_RESEARCH_BLACKLIST[tech.name] then return end

    local proto = tech.prototype
    -- 2.1.x 科技配方入口：LuaTechnologyPrototype.research_unit_ingredients
    -- （原型上无 ingredients/unit 字段，误用会在事件里抛错）
    local ingredients = proto and proto.research_unit_ingredients
    if not ingredients then return end

    for _, ing in ipairs(ingredients) do
        local pack = ing.name
        local count = SCIENCE_PACK_TALENTS[pack]
        if count then
            world19_grant_science_talent(pack, count)
        end
    end
end

-- 补发：本局已研究过的科技瓶，玩家此前（离线 / 中途加入）没拿过的立即入队
local function world19_grant_missing_science_talents(player)
    if not player or not player.valid or player.force.name ~= 'player' then return end
    local this = WPT.get()
    local granted = this.world19_science_granted
    if not granted then return end
    for pack, pack_tbl in pairs(granted) do
        if type(pack_tbl) == 'table' and not pack_tbl[player.name] then
            local count = SCIENCE_PACK_TALENTS[pack]
            if count then
                pack_tbl[player.name] = true
                world19_enqueue_talent(player.index, count)
            end
        end
    end
end

-- 天赋 ≤60 强制：封锁所有获取途径（等级/购买/顶尖人才/命令/科技瓶）
local function world19_remove_excess_talent(player)
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

local function world19_enforce_talent_cap()
    local this = WPT.get()
    if (this and this.world_number or 0) ~= 19 then return end

    for _, player in pairs(game.connected_players) do
        if player and player.valid and player.force and player.force.name == 'player' then
            local n = count_player_talents(player)
            if n >= TALENT_CAP then
                -- tianfu_count 顶高：等级发放判定 floor(level/80) >= count 永假；
                -- 顶尖人才每次 -1~3，24 次累计最多 -72，9999 足够。
                this.tianfu_count[player.index] = 9999
                this.skill_canchoise[player.name] = 0
                -- 购买判定 tianfu_buy_count >= 25 拦截（岩石市场 / 岛屿市场共用）
                this.tianfu_buy_count[player.index] = 25
                this.xuanze[player.index] = 0
                -- 顶尖人才（时间天赋）停触发，防刷屏与防越限
                if this.tianfu_enabled and this.tianfu_enabled[player.index] then
                    this.tianfu_enabled[player.index].djrc = false
                end
                local frame = player.gui.screen['选择你的天赋']
                if frame and frame.valid then
                    frame.destroy()
                end
                if n > TALENT_CAP then
                    world19_remove_excess_talent(player)
                end
            end
        end
    end
end

--==============================================================================
-- 堡垒：标准生成（同山谷），但生成范围限定在 256高 × 576宽 带状区域外
--==============================================================================

-- 供 stronghold_generation_algorithm_v2.is_sh_conflict 查询（返回 false = 该点不可用）
local function fortress_position_valid(position)
    local x, y = position.x, position.y
    if x < -MAP_HALF_WIDTH or x > MAP_HALF_WIDTH then return false end
    if y >= -128 and y <= 128 then return false end
    return true
end

--==============================================================================
-- 通关奖励：通关（1500 波）后，每局游戏每个玩家起始物资 +5 传说建造机器人，
-- 且从 1500 波算起每多 500 波再多 +1（如 2300~2799 波结束 = 7 个），
-- 范围为所有地图（记录由 game_over 通用结算，实际发放由 diff.apply_world_bonuses 完成）
--==============================================================================

--==============================================================================
-- 世界进入钩子
--==============================================================================

-- 首个 [60] tick 执行：读档清理。服务器刚读档时无玩家在线（客户端加入时必有玩家），
-- 此时清空上一局残留的科技瓶天赋记录（含发放队列）。
--   · 重置（reset_map）路径：on_world_start 已直接清空，此处有玩家在线不重复清理；
--   · 客户端加入后：与服务器基于同一 game.connected_players 判断（全局同步数据），
--     加入的客户端不会多清一次已标记的记录 → 无 desync 风险。
local function world19_finish_reset()
    local this = WPT.get()
    if (this and this.world_number or 0) ~= 19 then return end
    if #game.connected_players == 0 then
        this.world19_science_granted = {}
        this.world19_talent_queue = {}
    end
end

local function on_world_start(world_number)
    local this = WPT.get()
    if not this then return end

    -- 除出生点外无白嫖组装机（出生点「最后的防线」组装机保留）
    this.enable_wild_factorio = false

    -- 本图玩家强化：挖掘速度 +200%、背包 +20
    -- （force modifier 在 soft_reset 的 f.reset() 中清零，此处每次进入重新施加；
    --   挖掘速度走 force.manual_mining_speed_modifier——LuaForce 无
    --   character_mining_speed_modifier 属性，那是 LuaPlayer 级）
    local force = game.forces.player
    force.manual_mining_speed_modifier = force.manual_mining_speed_modifier + 2
    force.character_inventory_slots_bonus = force.character_inventory_slots_bonus + 20

    -- 自动获得精良好运连连（全员，幂等）
    for _, player in pairs(game.connected_players) do
        world19_grant_hyll(player)
    end

    -- 科技瓶天赋本局状态清零（脚本强制研究的科技已被 SCRIPT_RESEARCH_BLACKLIST 拦截，
    -- 重置期不会产生误标记，此处直接清空无时序竞争）。
    this.world19_science_granted = {}
    this.world19_talent_queue = {}
    this.world19_session_tick = game.tick

    -- 补齐初始区块内的指令塔：soft_reset 在 active_surface_index 赋值前生成
    -- 的初始区块（x ∈ [-64, 63]）跳过了 on_chunk_generated，塔需在此补建
    local surface = this.active_surface_index and game.surfaces[this.active_surface_index]
    if surface and surface.valid then
        for cx = -1, 1 do
            if surface.is_chunk_generated({x = cx, y = 0}) then
                local lt_x = cx * 32
                for tx = TOWER_INTERVAL, MAP_HALF_WIDTH, TOWER_INTERVAL do
                    for _, sign in ipairs({1, -1}) do
                        local x = tx * sign
                        if x >= lt_x and x < lt_x + 32 then
                            if not tower_exists_near(surface, x) then
                                place_tower(surface, x)
                            end
                        end
                    end
                end
            end
        end
    end
end

-- 世界内玩家加入：自动获得精良好运连连；并补发此前研究完成但该玩家未领取的科技瓶天赋
local function on_player_joined_game(event)
    local this = WPT.get()
    if (this and this.world_number or 0) ~= 19 then return end
    local player = game.players[event.player_index]
    if player then
        world19_grant_hyll(player)
        world19_grant_missing_science_talents(player)
    end
end

--==============================================================================
-- 注册到框架
--==============================================================================

World.register(19, {
    --==========================================================================
    -- 元数据
    --==========================================================================
    name_key = 'amap.world_name_19',
    desc_key = 'amap.world_name_info_19',
    selectable = true,

    --==========================================================================
    -- 时间与地形
    --==========================================================================
    -- 首波虫子延迟：3900 秒（60 刻/秒）
    time_limit = 3900 * 60,

    -- 资源：铁/铜/石/煤/铀 400% 丰度/分布/大小，石油 200%，污染与虫巢成长同山谷
    surface_config_name = 'world19',

    -- 地图尺寸：横向宽 576、高无限制。不设 map_settings 的宽高（引擎宽高必须成对），
    -- 边界由 terrain_generator 铺 out-of-map 实现（|x| > 288 全部为黑色虚空）
    map_settings = nil,

    -- 区块地形生成器：中间正常地型 / 两侧石头带（|y|≤960，5 倍密度）/ 外部虚空
    terrain_generator = terrain_generator,

    --==========================================================================
    -- 战斗规则
    --==========================================================================
    -- 本局火焰塔数量：1
    max_flame = 1,

    -- 虫子生成方向：上下两个方向（双向出波），128 格外（随建筑后移见模块逻辑）
    biter_spawn_rule = {
        four_way = {
            {0, -WAVE_SPAWN_DISTANCE},
            {0, WAVE_SPAWN_DISTANCE},
        },
    },

    -- 伤害削减同山谷（无减伤）
    ammo_damage_modifiers = nil,

    -- 污染与虫巢成长同山谷（自然扩张默认参数）
    enemy_expansion = nil,

    --==========================================================================
    -- 堡垒生成：标准生成（同山谷，围一圈），但限定在 256高 × 576宽 带状区域外
    --==========================================================================
    arty_settings = {
        mode = 'default',
    },
    fortress_position_valid = fortress_position_valid,

    --==========================================================================
    -- 星球与科技
    --==========================================================================
    -- 表面气压不可解锁（其他星体默认不解锁）
    planet_surfaces = nil,
    unlock_planet_technologies = false,
    planet_resource_boost = false,

    -- 开局科技解锁：默认无
    unlocked_technologies = {},

    -- 填海科技：黄瓶科技后仅解锁「填海」（functions.lua 全局机制，不在此开局启用）
    landfill_allowed = false,

    -- 传说木箱不可用
    disable_legendary_wood_chest = true,

    --==========================================================================
    -- 通关奖励：通关（1500 波）后，每局游戏每个玩家起始物资 +5 传说建造机器人，
    -- 且从 1500 波算起每多 500 波再多 +1（如 2300~2799 波结束 = 7 个），
    -- 范围为所有地图（由 diff.apply_world_bonuses 统一施加）
    --==========================================================================
    world_bonus_type = {
        name = 'starting_legendary_robot',
        custom_type = 'function',
        base_value = 5,
        growth_value = 1,
    },
    world_bonus_start_wave = 1500,
    world_bonus_interval = 500,
    joins_solar_system_edge = true,

    --==========================================================================
    -- 专属机制
    --==========================================================================
    -- 天赋间隔：50 级 +1 天赋（RPG 玩家等级，由 tianfu.lua 消费）
    tianfu_jiange = 50,

    -- 世界进入钩子：本图强化 / 自动天赋 / 禁用野外组装机 / 重置每局状态 / 补齐初始区块指令塔
    on_world_start = on_world_start,

    --==========================================================================
    -- 声明式事件订阅（framework.lua 统一分发）
    --==========================================================================
    events = {
        [defines.events.on_chunk_generated] = on_chunk_generated,
        [defines.events.on_research_finished] = on_research_finished,
        [defines.events.on_player_joined_game] = on_player_joined_game,
    },

    nth_tick = {
        [30] = {
            world19_refresh_spawn_positions,
        },
        [60] = {
            world19_finish_reset,        -- 开局首个 tick 清空重置期脚本研究的科技瓶天赋
            world19_enforce_talent_cap,  -- 天赋 ≤60 封锁
            world19_process_talent_queue,-- 科技瓶天赋逐次发放
            world19_apply_wave_interval, -- 2000 波后波次间隔 +2%/100波（≤+30%）
        },
    },
})
