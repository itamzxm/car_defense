local Global = require 'utils.global'
local Event = require 'utils.event'

local this = {}
Global.register(
    this,
    function(tbl)
        this = tbl
    end
)

local Public = {
    events = {
        on_player_kicked_from_surface = Event.generate_event_name('on_player_kicked_from_surface_icw'),
        used_train_door = Event.generate_event_name('used_train_door')
    }
}

-- 火车内部空间默认配置
-- 宽75（原50的1.5倍）、长150（需求文档）
local icw_width = 75
local icw_length = 150

function Public.reset()
    if this.surfaces then
        for k, index in pairs(this.surfaces) do
            local surface = game.surfaces[index]
            if surface and surface.valid then
                game.delete_surface(surface)
            end
        end
    end
    for k, _ in pairs(this) do
        this[k] = nil
    end

    this.doors = {}
    this.wagons = {}
    this.train_surfaces = {}
    this.renders = {}
    this.players = {}
    this.surfaces = {}
    this.allowed_surface = 'nauvis'
    this.locomotive = nil
    this.train_circle = nil
    this.cargo_wagons = {}
    this.train_health = 10000
    this.train_max_health = 10000
    this.wagon_count = 0
    this.icw_width = icw_width
    this.icw_length = icw_length

    -- 关联箱连接 GUI 的待处理数据
    this.pending_links = {}

    -- 世界13 地面车厢生成追踪
    this.loot_wagon_index = 0         -- 已生成的战利品车厢序号（决定类型）
    this.loot_wagons_on_map = {}       -- 地图上未被领取的战利品车厢 unit_number -> {entity, type, position}

    -- 世界13 自动铺泥土追踪
    this.last_paved_zone = 0           -- 上一次铺泥土的地形区编号（防止重复铺设）

    -- 每节车厢的内部空间 area 配置
    -- locomotive: 宽75, 长100（与cargo-wagon长度一致）
    -- cargo-wagon: 宽75, 长100
    -- fluid-wagon: 宽75, 长100
    this.wagon_areas = {
        ['locomotive'] = {
            left_top = {x = -math.floor(icw_width / 2), y = 0},
            right_bottom = {x = math.floor(icw_width / 2), y = 100}
        },
        ['cargo-wagon'] = {
            left_top = {x = -math.floor(icw_width / 2), y = 0},
            right_bottom = {x = math.floor(icw_width / 2), y = 100}
        },
        ['fluid-wagon'] = {
            left_top = {x = -math.floor(icw_width / 2), y = 0},
            right_bottom = {x = math.floor(icw_width / 2), y = 100}
        }
    }
end

function Public.get(key)
    if key then
        return this[key]
    else
        return this
    end
end

function Public.set(key, value)
    if key and (value or value == false) then
        this[key] = value
        return this[key]
    elseif key then
        return this[key]
    else
        return this
    end
end

function Public.set_wagon_areas(tbl)
    if not tbl then
        return
    end
    this.wagon_areas = tbl
end

function Public.allowed_surface(value)
    if value then
        this.allowed_surface = value
    end
    return this.allowed_surface
end

return Public
