local Event = require 'utils.event'
local Global = require 'utils.global'
local WPT = require 'maps.amap.table'

-- C3 硬帽（需求 §5 原文，常量名即契约名）
local MAX_DESTROY_PER_TICK = 1000
-- C8 批量日志边界（60-tick 窗口 = 每秒一批）
local BATCH_LOG_INTERVAL = 60
-- 区块配额（用户拍板 2026-08-05）：每 tick 固定清 N 个区块（区块内实体全清），30 秒（1800 tick）均分。
-- 计算：total_chunks / 1800，至少 1；由 force_init 快照后算好存 per_tick_chunks。
local COUNTDOWN_TICKS = 1800
-- C7 最小集（键名连字符，与实体 name 精确匹配；direction-3 审计无增补，decision-log「其他决策」已闭环）
local SKIP = { character = true, ['linked-chest'] = true }

local Public = {}

-- C1 初始字段基集 + 状态机扩展字段（见关键决策 K1）
local initial_state = {
    state = 'idle',                    -- 'idle' | 'cleaning' | 'stopped'（唯一状态机真值）
    stop_reason = nil,                 -- 'cancel'（终态 idle）| 'done'（终态 stopped）| force_stop 传入（归一 'done'）
    active = false,                    -- 派生字段 = (state == 'cleaning')，C9 get_state 返回
    chunk_list = {},                   -- 环形排序后的区块快照 [{x=,y=}, ...]
    cursor = 1,                        -- 下一个待处理区块下标（1-based）
    ring_index = 0,                    -- 当前 ring 序号（日志/断言用）
    batch_id = 0,                      -- 批次号（每秒 +1，C8）
    batch_destroyed = 0,               -- 本批销毁计数（C3 口径：destroy() 调用次数）
    total_destroyed = 0,               -- 累计销毁计数
    next_batch_log_tick = 0,           -- 批量日志边界（真实 tick；force_step 用虚拟 tick）
    per_tick_chunks = 1,               -- 每 tick 区块配额（总区块/1800，force_init 计算；老存档兜底 1）
}

local cleaner = initial_state

-- K2 旧存档兼容：storage.tokens 无本 token → callback 收到 nil → 绑定初始表；
-- 就地字段归一化（or 默认值）+ 残缺 cleaning 态（cleaning 且 chunk_list 空）回退 idle
Global.register(initial_state, function(tbl)
    cleaner = tbl or initial_state                    -- 旧存档 storage.tokens 无本 token → nil
    if cleaner ~= initial_state then                  -- 就地补默认值（C1：老存档加载即 idle）
        cleaner.state = cleaner.state or 'idle'
        cleaner.stop_reason = cleaner.stop_reason
        cleaner.active = cleaner.active or false
        cleaner.chunk_list = cleaner.chunk_list or {}
        cleaner.cursor = cleaner.cursor or 1
        cleaner.ring_index = cleaner.ring_index or 0
        cleaner.batch_id = cleaner.batch_id or 0
        cleaner.batch_destroyed = cleaner.batch_destroyed or 0
        cleaner.total_destroyed = cleaner.total_destroyed or 0
        cleaner.per_tick_chunks = cleaner.per_tick_chunks or 1
        if cleaner.state == 'cleaning' and #cleaner.chunk_list == 0 then
            cleaner.state = 'idle'                    -- 残缺状态回退，由下次 start_game==3 重新快照
        end
    end
end)

-- C6 取消判定：start_game ~= 3（摆车/silo 复活/重置均置 2）或 silo 有效即停
local function should_stop()
    return WPT.get().start_game ~= 3 or (WPT.get().silo and WPT.get().silo.valid)
end

-- C2 终态语义（decision-log #3）：
--   reason='cancel'（should_stop 命中）→ state='idle'（取消回 idle，下次 start_game==3 重新快照）
--   reason='done'（全部清完）→ state='stopped'；force_stop → stopped（测试硬停）
local function stop(reason)
    cleaner.state = reason == 'cancel' and 'idle' or 'stopped'
    cleaner.active = false
    cleaner.stop_reason = reason
    log('[CLEANER] stopped reason=' .. reason)           -- C8 状态转换行（行名固定 'stopped'）
    local surface = game.surfaces['nauvis']
    local remaining = 0
    if surface and surface.valid then
        remaining = surface.count_entities_filtered({})  -- C8：仅终态一次
    end
    log('[CLEANER] summary total_destroyed=' .. cleaner.total_destroyed
        .. ' chunks_done=' .. (cleaner.cursor - 1) .. '/' .. #cleaner.chunk_list
        .. ' remaining=' .. remaining)
    cleaner.chunk_list = {}                              -- C2 状态清理（取消/完成均清）
    cleaner.cursor = 1
end

-- C8 批量日志（§2.5）：batch_id+1 → batch 行（ring 取当前片 ring_index）→ batch_destroyed 清零
local function log_batch()
    cleaner.batch_id = cleaner.batch_id + 1
    log('[CLEANER] batch=' .. cleaner.batch_id
        .. ' ring=' .. cleaner.ring_index
        .. ' destroyed=' .. cleaner.batch_destroyed
        .. ' chunks_done=' .. (cleaner.cursor - 1) .. '/' .. #cleaner.chunk_list)
    cleaner.batch_destroyed = 0
end

-- C4 主键：环序号 = max(|x|, |y|)（§2.2）
local function ring_of(c)
    return math.max(math.abs(c.x), math.abs(c.y))
end

-- K5 区块面积手算（先例 world_15_tower_defense.lua:340-355）：32 格 = 1 区块
local function chunk_area(c)
    return {left_top = {x = c.x * 32, y = c.y * 32}, right_bottom = {x = c.x * 32 + 32, y = c.y * 32 + 32}}
end

-- C4 快照 + 环形排序（§2.2）
local function snapshot_chunks()
    local chunks = {}
    local surface = game.surfaces['nauvis']             -- §0.1：active_surface 恒为 nauvis
    for chunk in surface.get_chunks() do                -- 先例 commands/misc.lua:325
        chunks[#chunks + 1] = {x = chunk.x, y = chunk.y}
    end
    table.sort(chunks, function(a, b)                   -- 降序 = 边缘→中心（decision-log #1）
        local ra, rb = ring_of(a), ring_of(b)           -- 主键：ring（环序号），大→小 = 远→近
        if ra ~= rb then return ra > rb end
        local da, db = a.x * a.x + a.y * a.y, b.x * b.x + b.y * b.y
        if da ~= db then return da > db end             -- 次键：dist2 降序（同环确定性）
        return a.x > b.x or (a.x == b.x and a.y > b.y)  -- 三级：坐标字典序降序（完全确定）
    end)
    return chunks
end

-- work_slice(tick)：每 tick 预算切片主体（C3/C5/C6；函数尾 = C8 step 行 + 批量边界，T5）
-- 逻辑（用户拍板 2026-08-05）：按区块配额遍历——每 tick 固定清 PER_TICK_CHUNKS 个区块，
-- 区块内实体全部 destroy（不看数量），30 秒（1800 tick）正好清完全部区块。
-- 保留 MAX_DESTROY_PER_TICK 作为单 tick 安全阀（防中心密集区块单 tick 爆炸，K7 跨 tick 续清）。
local function work_slice(tick)
    if cleaner.state ~= 'cleaning' then return end
    if should_stop() then stop('cancel'); return end             -- C6 每片首行
    local surface = game.surfaces['nauvis']
    local destroyed = 0                                          -- 本片 destroy 计数（T5 step 行 remaining 推导用）
    local chunk_quota = cleaner.per_tick_chunks or 1              -- 本片区块配额（force_init 计算：总区块/1800）
    local entity_budget = MAX_DESTROY_PER_TICK                   -- 单 tick 实体安全阀
    while chunk_quota > 0 do
        local chunk = cleaner.chunk_list[cleaner.cursor]
        if not chunk then stop('done'); return end              -- 全部区块处理完
        cleaner.ring_index = ring_of(chunk)
        local entities = surface.find_entities(chunk_area(chunk))  -- C5：find_entities 直接收 BoundingBox
        for i = 1, #entities do
            if should_stop() then stop('cancel'); return end    -- C6 每实体
            local e = entities[i]
            if e.valid then                                     -- K4 计数口径前置（无效跳过不计数）
                if not SKIP[e.type] and not SKIP[e.name] then   -- C7/Q6 双键查（命中跳过：不销毁、不计数）
                    e.destroy()                                 -- C5：destroy() 无参数无 raise
                    destroyed = destroyed + 1
                    cleaner.batch_destroyed = cleaner.batch_destroyed + 1
                    cleaner.total_destroyed = cleaner.total_destroyed + 1
                    entity_budget = entity_budget - 1
                    if entity_budget <= 0 then break end        -- 安全阀耗尽提前结束本片（本区块跨 tick 续清，K7）
                end
            end
        end
        if entity_budget <= 0 then break end                    -- 安全阀耗尽，本区块未清完，下 tick 从同 cursor 继续（K7）
        cleaner.cursor = cleaner.cursor + 1                     -- 区块清完才推进
        chunk_quota = chunk_quota - 1
    end
    -- C8 step 行（decision-log #4）：每 tick 工作片结束（区块配额耗尽或安全阀耗尽）输出
    log('[CLEANER] step tick=' .. tick .. ' destroyed=' .. destroyed
        .. ' remaining=' .. (MAX_DESTROY_PER_TICK - destroyed))
    if tick >= cleaner.next_batch_log_tick then          -- C8 批量日志边界
        log_batch()
        cleaner.next_batch_log_tick = tick + BATCH_LOG_INTERVAL
    end
end

function Public.get_state()
    return {
        active = cleaner.active,
        cursor = cleaner.cursor,
        ring_index = cleaner.ring_index,
        batch_destroyed = cleaner.batch_destroyed,
        total_destroyed = cleaner.total_destroyed,
        state = cleaner.state,                            -- 附加字段（K6，C9 超集）
        stop_reason = cleaner.stop_reason,                -- 附加字段（K6）
    }
end

function Public.force_init()                              -- 无视 start_game 快照+排序（测试用）
    cleaner.state = 'cleaning'
    cleaner.active = true
    cleaner.stop_reason = nil
    cleaner.chunk_list = snapshot_chunks()
    cleaner.cursor = 1
    cleaner.ring_index = 0
    cleaner.batch_id = 0
    cleaner.batch_destroyed = 0
    cleaner.total_destroyed = 0
    cleaner.next_batch_log_tick = game.tick + BATCH_LOG_INTERVAL
    -- 区块配额（用户拍板）：总区块 / 1800 tick（30 秒），至少 1 → 每 tick 固定清 N 个区块，30 秒均分清完
    cleaner.per_tick_chunks = math.max(1, math.floor(#cleaner.chunk_list / COUNTDOWN_TICKS))
    -- 降序（C4/decision-log #1）：chunk_list[1] = 最大 ring（边缘，最先清）
    local max_ring = #cleaner.chunk_list > 0 and ring_of(cleaner.chunk_list[1]) or 0
    log('[CLEANER] init total_chunks=' .. #cleaner.chunk_list .. ' max_ring=' .. max_ring
        .. ' per_tick_chunks=' .. cleaner.per_tick_chunks)  -- C8
    if #cleaner.chunk_list == 0 then
        stop('done')                                      -- 空表面（首次游戏）：直接完成
    end
end

function Public.force_step(n)                             -- 手动执行 n 个工作片（模拟 n tick）
    n = n or 1
    if cleaner.state ~= 'cleaning' then return 0 end
    local base = game.tick
    local before = cleaner.total_destroyed
    for i = 1, n do
        if cleaner.state ~= 'cleaning' then break end
        work_slice(base + i)                              -- 虚拟 tick：批量日志边界与真实路径同构
    end
    return cleaner.total_destroyed - before               -- 返回本批销毁数，供方向2 断言
end

function Public.force_stop(reason)                        -- 强制停止（测试用）
    reason = reason or 'done'
    if reason == 'cancel' then reason = 'done' end        -- C2：force_stop 终态恒 stopped；'cancel'→idle 仅属 should_stop 取消路径（裁决 #3）
    stop(reason)
end

function Public.dry_run()                                 -- 只枚举统计不销毁，可重复调用
    local surface = game.surfaces['nauvis']
    local chunks = snapshot_chunks()                      -- 与真实路径同一排序
    local total = 0
    for i = 1, #chunks do
        local c = chunks[i]
        local n = surface.count_entities_filtered({area = chunk_area(c)})
        total = total + n
        log('[CLEANER] dry ' .. ring_of(c) .. ' chunk=(' .. c.x .. ',' .. c.y .. ') entities=' .. n)  -- C8
    end
    log('[CLEANER] dry total_chunks=' .. #chunks .. ' total_entities=' .. total)
    return {total_chunks = #chunks, total_entities = total}   -- 方向2 回填需求 §7
end

function Public.on_tick()                                -- Event.on_nth_tick(1, Public.on_tick)
    if cleaner.state == 'idle' then
        if WPT.get().start_game == 3 then
            Public.force_init()                           -- C2 首次触发
        end
        return
    end
    if cleaner.state == 'cleaning' then
        work_slice(game.tick)                             -- 每 tick 一个工作片
        return
    end
    -- 'stopped'：K3 重武装（C2 增补，decision-log #3）——观测 start_game ~= 3
    --（game_over 后 WPT.reset_table() 已复位 start_game=2，main.lua:525）→ 静默回 idle，
    -- 下一局 start_game == 3 可再次触发
    if WPT.get().start_game ~= 3 then
        cleaner.state = 'idle'
    end
end

Event.on_nth_tick(1, Public.on_tick)

return Public
