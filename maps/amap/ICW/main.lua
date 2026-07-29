local Event = require 'utils.event'
local Functions = require 'maps.amap.ICW.functions'
local ICW = require 'maps.amap.ICW.table'
local WPT = require 'maps.amap.table'

local Public = {}

Public.reset = ICW.reset
Public.get_table = ICW.get

------------------------------------------------------------
-- 玩家驾驶状态变化（进出火车）
-- 仅在世界13时处理
-- locomotive/cargo-wagon: 从外部进入内部空间
-- car (门): 从内部出去到外部
------------------------------------------------------------
local function on_player_driving_changed_state(event)
    local this = WPT.get()
    if this.world_number ~= 13 then
        return
    end

    local player = game.players[event.player_index]
    local entity = event.entity

    if not entity or not entity.valid then
        return
    end

    -- state 计数器：防止从内部出去后立即重新触发（参考IC逻辑）
    local player_data = Functions.get_player_data(player)
    if player_data.state then
        player_data.state = player_data.state - 1
        if player_data.state == 0 then
            player_data.state = nil
        end
        return
    end

    -- 情况1：玩家从外部进入火车车厢（locomotive/cargo-wagon/fluid-wagon）
    if entity.type == 'locomotive' or entity.type == 'cargo-wagon' or entity.type == 'fluid-wagon' then
        local wagons = ICW.get('wagons')
        local wagon = wagons[entity.unit_number]
        if not wagon then
            return
        end

        local surface_index = wagon.surface
        local surface = game.surfaces[surface_index]
        if not surface or not surface.valid then
            return
        end

        local area = wagon.area
        local entity_surface = entity.surface

        if entity_surface.name == player.physical_surface.name then
            -- 玩家在外部 -> 传送到内部空间
            local x_vector = entity.position.x - player.physical_position.x
            local position
            if x_vector > 0 then
                position = {area.left_top.x + 0.5, area.left_top.y + ((area.right_bottom.y - area.left_top.y) * 0.5)}
            else
                position = {area.right_bottom.x - 0.5, area.left_top.y + ((area.right_bottom.y - area.left_top.y) * 0.5)}
            end
            local p = surface.find_non_colliding_position('character', position, 128, 0.5)
            if p then
                player.teleport(p, surface)
            else
                player.teleport(position, surface)
            end
            -- 取消驾驶状态，让玩家进入内部空间
            if player.character and player.character.valid then
                player.character.driving = false
            end
        else
            -- 玩家在内部 -> 传送到外部
            if entity.type == 'locomotive' then
                local x_vector = (entity.position.x / math.abs(entity.position.x)) * 2
                if entity.position.x == 0 then
                    x_vector = 2
                end
                local position = {entity.position.x + x_vector, entity.position.y}
                local p = entity_surface.find_non_colliding_position('character', position, 128, 0.5)
                if p then
                    player.teleport(p, entity_surface)
                else
                    player.teleport(position, entity_surface)
                end
                -- 恢复驾驶状态
                if player.character and player.character.valid then
                    player.character.driving = true
                end
            else
                -- cargo-wagon：传送到外部，不驾驶
                local x_vector = (entity.position.x / math.abs(entity.position.x)) * 2
                if entity.position.x == 0 then
                    x_vector = 2
                end
                local position = {entity.position.x + x_vector, entity.position.y}
                local p = entity_surface.find_non_colliding_position('character', position, 128, 0.5)
                if p then
                    player.teleport(p, entity_surface)
                else
                    player.teleport(position, entity_surface)
                end
            end
        end
        return
    end

    -- 情况2：玩家在内部空间进入门（car 实体）-> 传送到外部
    if entity.type == 'car' then
        Functions.use_door_with_entity(player, entity)
    end
end

------------------------------------------------------------
-- 实体被摧毁 - 仅处理火车相关
------------------------------------------------------------
local function on_entity_died(event)
    local this = WPT.get()
    if this.world_number ~= 13 then
        return
    end

    local entity = event.entity
    if not entity or not entity.valid then
        return
    end

    if entity.type ~= 'locomotive' and entity.type ~= 'cargo-wagon' and entity.type ~= 'fluid-wagon' then
        return
    end

    local wagons = ICW.get('wagons')
    if wagons[entity.unit_number] then
        Functions.kill_wagon(entity)
    end

    -- 火车头被摧毁 = 游戏结束
    if entity.type == 'locomotive' then
        local icw = ICW.get()
        if icw.locomotive and icw.locomotive.valid and icw.locomotive.unit_number == entity.unit_number then
        end
    end
end

------------------------------------------------------------
-- 定时逻辑
------------------------------------------------------------
local function on_tick()
    local this = WPT.get()
    if this.world_number ~= 13 then
        return
    end

    local tick = game.tick

    -- 每秒执行物品转移
    if tick % 60 == 1 then
        Functions.item_transfer()
    end

    -- 每 20 秒清理无效车厢
    if tick % (20 * 60) == 0 then
        Functions.remove_invalid_wagons()
    end

    -- 每 5 秒检查一次战利品车厢状态
    if tick % (5 * 60) == 0 then
        Functions.cleanup_loot_wagons()
    end

    -- 每 10 秒设置玩家重生点在火车附近
    if tick % (10 * 60) == 0 then
        Functions.set_respawn_near_train()
    end

    -- 每 2 秒检测火车是否进入清洁区，触发自动铺泥土
    if tick % (2 * 60) == 0 then
        local zone_number = Functions.check_train_in_clean_zone()
        if zone_number then
            local icw = ICW.get()
            local loco = icw.locomotive
            if loco and loco.valid then
                local surface = loco.surface
                Functions.pave_terrain_for_train(surface, zone_number)
            end
        end
    end
end

------------------------------------------------------------
-- 初始化
------------------------------------------------------------
local function on_init()
    Public.reset()
end

------------------------------------------------------------
-- 实体被挖掘（玩家/机器人）- 清理内部空间
------------------------------------------------------------
local function on_mined_entity(event)
    local this = WPT.get()
    if this.world_number ~= 13 then
        return
    end

    local entity = event.entity
    if not entity or not entity.valid then
        return
    end

    if entity.type ~= 'locomotive' and entity.type ~= 'cargo-wagon' and entity.type ~= 'fluid-wagon' then
        return
    end

    local wagons = ICW.get('wagons')
    if wagons[entity.unit_number] then
        Functions.kill_wagon(entity)
    end

    -- 火车头被挖掘 = 游戏结束
    if entity.type == 'locomotive' then
        local icw = ICW.get()
        if icw.locomotive and icw.locomotive.valid and icw.locomotive.unit_number == entity.unit_number then

        end
    end
end

------------------------------------------------------------
-- 新车厢被建造 - 检测是否连接到我们的火车
------------------------------------------------------------
local function on_built_entity(event)
    local this = WPT.get()
    if this.world_number ~= 13 then
        return
    end

    local entity = event.entity
    if not entity or not entity.valid then
        return
    end

    if entity.type ~= 'locomotive' and entity.type ~= 'cargo-wagon' and entity.type ~= 'fluid-wagon' then
        return
    end

    -- 检查这个实体是否连接到我们世界13的火车
    local loco = ICW.get('locomotive')
    if loco and loco.valid and entity.train and loco.train then
        if entity.train.id == loco.train.id then
            -- 连接到我们的火车了，重新扫描编组
            Functions.rescan_train_wagons()
        end
    end
end

------------------------------------------------------------
-- 火车编组创建/变化 - 重新扫描编组
------------------------------------------------------------
local function on_train_created(event)
    local this = WPT.get()
    if this.world_number ~= 13 then
        return
    end

    Functions.rescan_train_wagons()
end

------------------------------------------------------------
-- 事件注册
------------------------------------------------------------
Event.on_init(on_init)
Event.add(defines.events.on_tick, on_tick)
Event.add(defines.events.on_player_driving_changed_state, on_player_driving_changed_state)
Event.add(defines.events.on_entity_died, on_entity_died)
Event.add(defines.events.on_player_mined_entity, on_mined_entity)
Event.add(defines.events.on_robot_mined_entity, on_mined_entity)
Event.add(defines.events.on_built_entity, on_built_entity)
Event.add(defines.events.on_train_created, on_train_created)

return Public