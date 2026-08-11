-- maps/amap/builder_arm_fx.lua
-- 建造师视觉反馈：黄色机械臂建造动画（辅助手天赋触发时播放）
--
-- 触发：辅助手（fuzhushou）自动复活幽灵后，调用 Public.spawn_builder_arm(player, pos)
-- 动画：两段式黄色机械臂从玩家身上伸出 → 抓取目标建筑 → 抬起 → 收回，伴随目标闪光
--
-- 实现：rendering 几何对象逐帧更新（与特效演示场景同模式），
--       每 tick 由本模块自注册的 Event.on_nth_tick(1) 驱动，TTL 自动销毁

local Event = require 'utils.event'
local FxBudget = require 'maps.amap.fx_budget'

local Public = {}

-- =============================================================================
-- 常量
-- =============================================================================

local ARM_TTL = 45            -- 动画总时长（tick）
local ARM_EXEC_TICK = 16      -- 前摇结束/抓取时刻（tick）：在此 tick 触发 on_exec 回调（真实建造）
local SEGMENT_LEN = 1.1       -- 单节臂长（格）
local SHOULDER = {x = 0, y = -0.3}  -- 肩部（相对角色）
local ARM_COLOR = {r = 1, g = 0.82, b = 0.25}
local ARM_COLOR_BRIGHT = {r = 1, g = 0.95, b = 0.5}
local HAND_GRAB = {r = 1, g = 1, b = 0.75}   -- 抓手亮色

-- 动画成本（对象数 × TTL，预算网关扣费用）：8 对象 × 45 tick = 360
local ARM_COST = 8 * ARM_TTL

-- =============================================================================
-- 调度器（进行中的机械臂动画实例）
-- =============================================================================

local arms = {}

-- 每 tick 更新所有进行中的机械臂动画
local function update_arms()
    for i = #arms, 1, -1 do
        local arm = arms[i]
        arm.age = arm.age + 1

        -- 前摇结束（抓取时刻）：触发真实建造回调（此时手已到目标位置）
        if arm.age == ARM_EXEC_TICK and arm.on_exec then
            local ok, err = pcall(arm.on_exec)
            if not ok then
                log('[BuilderArm] on_exec error: ' .. tostring(err))
            end
        end

        local t = arm.age / ARM_TTL

        -- 目标点每 tick 锚定世界坐标（玩家走动时自动补偿偏移，手臂钉在目标上）
        -- 肩部 offset 相对角色（跟随玩家），目标 offset = 世界坐标 - 角色当前位置
        local cx, cy = arm.character.position.x, arm.character.position.y
        local tx = arm.wx - cx
        local ty = arm.wy - cy

        -- ---- 手部位置（4 阶段：伸出→抓取→抬起→收回）----
        local hx, hy
        local grab_angle   -- 抓手开合角（弧度）
        local alpha = 1

        if t < 0.35 then
            -- 伸出（ease-out）
            local p = t / 0.35
            local e = 1 - (1 - p) * (1 - p)
            hx = arm.sx + (tx - arm.sx) * e
            hy = arm.sy + (ty - arm.sy) * e
            grab_angle = 0.5
        elseif t < 0.45 then
            -- 抓取（抓手闭合）
            hx, hy = tx, ty
            local p = (t - 0.35) / 0.10
            grab_angle = 0.5 - 0.42 * p
        elseif t < 0.55 then
            -- 抬起（带着"建筑"上提）
            local p = (t - 0.45) / 0.10
            hx = tx
            hy = ty - 0.5 * p
            grab_angle = 0.08
        else
            -- 收回（ease-in + 淡出）
            local p = (t - 0.55) / 0.45
            local e = p * p
            hx = tx + (arm.sx - tx) * e
            hy = ty - 0.5 + (arm.sy + 0.5 - ty) * e
            grab_angle = 0.08
            alpha = 1 - p
        end

        -- ---- 肘部（两段臂折角：中点 + 垂直偏移）----
        local mx, my = (arm.sx + hx) / 2, (arm.sy + hy) / 2
        local dx, dy = hx - arm.sx, hy - arm.sy
        local dl = math.max(0.001, math.sqrt(dx * dx + dy * dy))
        local nx, ny = -dy / dl, dx / dl
        local ex, ey = mx + nx * 0.35, my + ny * 0.35

        -- ---- 抓手端点（开合角）----
        local gdx, gdy = dx / dl, dy / dl          -- 手伸出方向
        local gpx, gpy = -gdy, gdx                  -- 垂直方向
        local g1x = hx + gdx * 0.3 + gpx * math.sin(grab_angle) * 0.35
        local g1y = hy + gdy * 0.3 + gpy * math.sin(grab_angle) * 0.35
        local g2x = hx + gdx * 0.3 - gpx * math.sin(grab_angle) * 0.35
        local g2y = hy + gdy * 0.3 - gpy * math.sin(grab_angle) * 0.35

        -- ---- 更新绘制对象 ----
        local o = arm.objects
        o[1].from = {entity = arm.character, offset = {arm.sx, arm.sy}}
        o[1].to = {entity = arm.character, offset = {ex, ey}}
        o[2].from = {entity = arm.character, offset = {ex, ey}}
        o[2].to = {entity = arm.character, offset = {hx, hy}}
        o[3].target = {entity = arm.character, offset = {ex, ey}}
        o[4].from = {entity = arm.character, offset = {hx, hy}}
        o[4].to = {entity = arm.character, offset = {g1x, g1y}}
        o[5].from = {entity = arm.character, offset = {hx, hy}}
        o[5].to = {entity = arm.character, offset = {g2x, g2y}}
        o[6].target = {entity = arm.character, offset = {hx, hy}}

        -- 淡出
        if alpha < 1 then
            local a1 = 0.9 * alpha
            local a2 = 0.85 * alpha
            o[1].color = {r = ARM_COLOR.r, g = ARM_COLOR.g, b = ARM_COLOR.b, a = a1}
            o[2].color = {r = ARM_COLOR.r, g = ARM_COLOR.g, b = ARM_COLOR.b, a = a2}
            o[3].color = {r = ARM_COLOR_BRIGHT.r, g = ARM_COLOR_BRIGHT.g, b = ARM_COLOR_BRIGHT.b, a = 0.9 * alpha}
            o[4].color = {r = HAND_GRAB.r, g = HAND_GRAB.g, b = HAND_GRAB.b, a = 0.95 * alpha}
            o[5].color = {r = HAND_GRAB.r, g = HAND_GRAB.g, b = HAND_GRAB.b, a = 0.95 * alpha}
            o[6].color = {r = ARM_COLOR_BRIGHT.r, g = ARM_COLOR_BRIGHT.g, b = ARM_COLOR_BRIGHT.b, a = alpha}
        end

        -- 目标闪光环（扩散 + 淡出，锚定世界坐标补偿玩家移动）
        if arm.flash and arm.flash.valid then
            arm.flash.target = {entity = arm.character, offset = {tx, ty}}
            local fp = arm.age / 20
            if fp <= 1 then
                arm.flash.radius = 0.3 + fp * 0.9
                arm.flash.color = {r = 1, g = 0.85, b = 0.4, a = 0.8 * (1 - fp)}
            else
                arm.flash.visible = false
            end
        end

        -- 到期销毁
        if arm.age >= ARM_TTL then
            for _, d in ipairs(arm.objects) do
                if d.valid then d.destroy() end
            end
            if arm.flash and arm.flash.valid then arm.flash.destroy() end
            table.remove(arms, i)
        end
    end
end

-- =============================================================================
-- 生成机械臂动画
-- =============================================================================

-- player: 玩家（动画锚定其 character）；target_position: 建造位置（角色相对坐标）
-- on_exec: 可选回调，在机械臂"抓取"时刻（ARM_EXEC_TICK tick）调用一次，
--          用于执行真实建造（create/revive）——动画与实体出现严格同步（前摇→执行→后摇）
function Public.spawn_builder_arm(player, target_position, on_exec)
    if not player or not player.valid then return end
    if not target_position then return end
    local character = player.character
    if not character or not character.valid then return end

    -- 预算网关：预算不足（动画过密/全服过载）直接舍弃，不播放
    if not FxBudget.try_spend(player.index, ARM_COST) then
        return
    end

    local surface = player.surface
    local objects = {}

    -- 目标位置：保存世界绝对坐标（播放中每 tick 补偿玩家移动，手臂钉在目标上）
    local wx, wy = target_position.x, target_position.y
    -- 限制距离：太远不播（臂长有限）
    local dist = math.sqrt((wx - character.position.x) ^ 2 + (wy - character.position.y) ^ 2)
    if dist > 12 then return end

    local sx, sy = SHOULDER.x, SHOULDER.y

    -- 1/2. 两段臂
    objects[1] = rendering.draw_line({
        surface = surface,
        from = {entity = character, offset = {sx, sy}},
        to = {entity = character, offset = {sx, sy}},
        color = {r = ARM_COLOR.r, g = ARM_COLOR.g, b = ARM_COLOR.b, a = 0.9},
        width = 3.0,
    })
    objects[2] = rendering.draw_line({
        surface = surface,
        from = {entity = character, offset = {sx, sy}},
        to = {entity = character, offset = {sx, sy}},
        color = {r = ARM_COLOR.r, g = ARM_COLOR.g, b = ARM_COLOR.b, a = 0.85},
        width = 2.4,
    })
    -- 3. 肘关节
    objects[3] = rendering.draw_circle({
        surface = surface,
        target = character,
        radius = 0.14,
        color = {r = ARM_COLOR_BRIGHT.r, g = ARM_COLOR_BRIGHT.g, b = ARM_COLOR_BRIGHT.b, a = 0.9},
        filled = true,
    })
    -- 4/5. 抓手（双钳）
    objects[4] = rendering.draw_line({
        surface = surface,
        from = {entity = character, offset = {sx, sy}},
        to = {entity = character, offset = {sx, sy}},
        color = {r = HAND_GRAB.r, g = HAND_GRAB.g, b = HAND_GRAB.b, a = 0.95},
        width = 1.6,
    })
    objects[5] = rendering.draw_line({
        surface = surface,
        from = {entity = character, offset = {sx, sy}},
        to = {entity = character, offset = {sx, sy}},
        color = {r = HAND_GRAB.r, g = HAND_GRAB.g, b = HAND_GRAB.b, a = 0.95},
        width = 1.6,
    })
    -- 6. 手部光点
    objects[6] = rendering.draw_circle({
        surface = surface,
        target = character,
        radius = 0.12,
        color = {r = ARM_COLOR_BRIGHT.r, g = ARM_COLOR_BRIGHT.g, b = ARM_COLOR_BRIGHT.b, a = 1},
        filled = true,
    })

    -- 目标建造闪光（扩散环）
    local flash = rendering.draw_circle({
        surface = surface,
        target = character,
        radius = 0.3,
        color = {r = 1, g = 0.85, b = 0.4, a = 0.8},
        width = 1.6,
        filled = false,
    })

    local arm = {
        character = character,
        age = 0,
        sx = sx,
        sy = sy,
        wx = wx,          -- 目标世界坐标（每 tick 补偿玩家移动）
        wy = wy,
        objects = objects,
        flash = flash,
        on_exec = on_exec,
    }
    arms[#arms + 1] = arm
    return arm
end

-- 每 tick 驱动（模块 require 时注册，早于 on_init，无 desync 风险）
Event.on_nth_tick(1, update_arms)

return Public
