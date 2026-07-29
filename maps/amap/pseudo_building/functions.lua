-- maps/amap/pseudo_building/functions.lua
-- 伪建筑共享工具函数库（参照 world/world_function.lua）
--
-- 设计原则：
--   1. 提供 force 管理 / 实体创建 / 渲染 / 清理 / 计数等纯工具函数
--   2. 不 require 任何 buildings 子模块
--   3. 所有状态访问都通过 table.lua 的 Public.get_registry()
--   4. 渲染对象（LuaRenderObject）不可序列化，运行期持有在本地 render_store
--
-- 依赖：framework（取常量/查 module）、table（取 registry）

local Framework = require 'maps.amap.pseudo_building.framework'
local Table = require 'maps.amap.pseudo_building.table'

local Public = {}

--==============================================================================
-- 渲染对象运行期持有（不进存档）
--==============================================================================
local render_store = {}  -- [unit_number] = { LuaRenderObject, ... }

--==============================================================================
-- Force 管理
--==============================================================================
local function ensure_forces()
    if game.forces[Framework.FORCE_PLAYER] then return end
    local fp = game.create_force(Framework.FORCE_PLAYER)
    -- 与所有非 enemy force 双向友善（玩家阵营不打框架建筑，反之亦然）
    for name, f in pairs(game.forces) do
        if name ~= Framework.FORCE_PLAYER and name ~= Framework.FORCE_ENEMY then
            fp.set_friend(f, true)
            f.set_friend(fp, true)
            fp.set_cease_fire(f, true)
            f.set_cease_fire(fp, true)
        end
    end
    -- 与 enemy 双向敌对（框架炮塔打虫子，虫子打框架建筑）
    local enemy = game.forces[Framework.FORCE_ENEMY]
    fp.set_friend(enemy, false)
    fp.set_cease_fire(enemy, false)
    enemy.set_friend(fp, false)
    enemy.set_cease_fire(fp, false)
end
Public.ensure_forces = ensure_forces

--==============================================================================
-- 计数
--==============================================================================
function Public.count_side(side)
    local n = 0
    local registry = Table.get_registry()
    for _, e in pairs(registry) do
        if e.side == side then n = n + 1 end
    end
    return n
end

function Public.count_owner(player_index)
    local n = 0
    local registry = Table.get_registry()
    for _, e in pairs(registry) do
        if e.owner == player_index then n = n + 1 end
    end
    return n
end

--==============================================================================
-- 渲染层
--==============================================================================
local function apply_render(entity, opts)
    local ids = {}
    local surf = entity.surface

    if opts.show_ring then
        local id = rendering.draw_circle{
            target = entity,
            surface = surf,
            radius = opts.ring_radius or 2.5,
            color = opts.ring_color or {1, 0.85, 0.15, 0.7},
            width = 3,
            filled = false,
            draw_on_ground = true,
        }
        if id then ids[#ids + 1] = id end
    end

    if opts.name then
        local id = rendering.draw_text{
            text = opts.name,
            surface = surf,
            target = {entity = entity, offset = {0, -3}},
            color = {1, 1, 1},
            font = 'default-bold',
            scale = 0.85,
            scale_with_zoom = false,
            alignment = 'center',
        }
        if id then ids[#ids + 1] = id end
    end

    if opts.icon then
        local ok, id = pcall(rendering.draw_sprite, {
            sprite = opts.icon,
            surface = surf,
            target = {entity = entity, offset = {0, 1.3}},
            x_scale = 0.6,
            y_scale = 0.6,
        })
        if ok and id then ids[#ids + 1] = id end
    end

    return ids
end
Public.apply_render = apply_render

function Public.destroy_render(unit_number)
    local objs = render_store[unit_number]
    render_store[unit_number] = nil
    if not objs then return end
    for _, obj in ipairs(objs) do
        pcall(function() if obj and obj.destroy then obj:destroy() end end)
    end
end

-- 应用渲染 + 存入 render_store（create_common 调用）
function Public.attach_render(unit_number, entity, opts)
    render_store[unit_number] = apply_render(entity, opts)
end

-- 清空 render_store（reset_table 时调用）
function Public.reset_render_store()
    render_store = {}
end

--==============================================================================
-- 实体创建
--==============================================================================
function Public.spawn_entity(category, surface, position, side, opts)
    ensure_forces()
    local force = (side == 'enemy') and game.forces[Framework.FORCE_ENEMY] or game.forces[Framework.FORCE_PLAYER]
    local entity = surface.create_entity{
        name = Framework.PROTOTYPE[category],
        position = position,
        force = force,
        raise_built = false,
    }
    if not entity then return nil end
    entity.operable = not not (opts and opts.operable)  -- 默认禁 GUI；物资塔等需玩家设置时 opts.operable=true
    entity.minable_flag = false    -- 禁止挖掘拆除
    entity.destructible = true     -- 可被摧毁
    entity.rotatable = false
    return entity
end

--==============================================================================
-- 清理（on_destroy 钩子 + 渲染销毁 + 实体兜底销毁 + registry 移除）
--==============================================================================
function Public.cleanup(unit_number)
    local registry = Table.get_registry()
    local entry = registry[unit_number]
    if not entry then return end
    if entry.def and entry.def.on_destroy then
        local ctx = {owner = entry.owner, side = entry.side, opts = entry.opts, category = entry.category}
        pcall(entry.def.on_destroy, entry.entity, entry.data, ctx)
    end
    Public.destroy_render(unit_number)
    -- 真正移除实体（自毁/死亡兜底）
    pcall(function()
        if entry.entity and entry.entity.valid then
            entry.entity.destroy()
        end
    end)
    registry[unit_number] = nil
end

--==============================================================================
-- 子模块辅助：取玩家
--==============================================================================
function Public.get_player(owner_index)
    if not owner_index then return nil end
    local p = game.get_player(owner_index)
    if p and p.valid then return p end
    return nil
end

--==============================================================================
-- 子模块辅助：扣拥有者背包内的鱼；不足返回 false（不扣除）
--==============================================================================
function Public.take_fish(owner_index, count)
    if not owner_index or not count or count <= 0 then return false end
    local player = Public.get_player(owner_index)
    if not player or not player.character then return false end
    if player.get_item_count('raw-fish') < count then return false end
    player.remove_item{name = 'raw-fish', count = count}
    return true
end

--==============================================================================
-- 子模块辅助：物品"制作时间"（参考岛屿系统 prototypes.recipe[name].energy）
--==============================================================================
function Public.item_craft_time(item_name)
    local r = prototypes.recipe[item_name]
    local t = r and r.energy or 1
    return math.max(1, t)
end

--==============================================================================
-- 创建 API（供 buildings 子模块的 spawn_fn 调用）
--==============================================================================
local function create_common(category, surface, position, opts)
    opts = opts or {}
    local side = (opts.force_side == 'enemy') and 'enemy' or 'player'

    -- 上限检查
    if side == 'enemy' then
        if Public.count_side('enemy') >= Framework.ENEMY_LIMIT then
            return nil, 'enemy_limit'
        end
    else
        if opts.owner_player and Public.count_owner(opts.owner_player) >= Framework.PLAYER_LIMIT then
            return nil, 'player_limit'
        end
    end

    local entity = Public.spawn_entity(category, surface, position, side, opts)
    if not entity then return nil, 'spawn_failed' end

    -- 通过 module 字段查 def（function 不进存档，每次按 module_name 重建）
    local def = opts.module and Framework.get_module(opts.module) or nil
    local entry = {
        entity = entity,
        module_name = opts.module,    -- 存档可序列化；on_load 时按名重建 def
        def = def,                    -- 运行期持有，存档会跳过 function 字段
        category = category,
        side = side,
        owner = (side == 'player') and opts.owner_player or nil,
        pos = {x = position.x, y = position.y},
        created = game.tick,
        data = {},                    -- 子模块私有数据（经验/等级等）
        next_trigger = 0,
        opts = opts,
        active = true,
        lifespan = opts.lifespan or 0,
    }
    Table.get_registry()[entity.unit_number] = entry
    -- 渲染对象由本模块内部 render_store 持有（不可序列化，运行期重建）
    Public.attach_render(entity.unit_number, entity, opts)

    if def and def.on_create then
        local ctx = {owner = entry.owner, side = entry.side, opts = opts, category = category}
        pcall(def.on_create, entity, entry.data, ctx)
    end

    if opts.timed then
        entry.next_trigger = game.tick + (opts.interval or 1800)
    end

    return entry
end

function Public.create_attack(surface, position, opts)
    return create_common('attack', surface, position, opts)
end

function Public.create_storage(surface, position, opts)
    return create_common('storage', surface, position, opts)
end

function Public.create_power(surface, position, opts)
    return create_common('power', surface, position, opts)
end

--==============================================================================
-- 主动销毁
--==============================================================================
function Public.destroy(unit_number)
    local entry = Table.get_registry()[unit_number]
    if entry then
        Public.cleanup(unit_number)
        return true
    end
    return false
end

return Public
