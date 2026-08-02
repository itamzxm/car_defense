local Server = require 'utils.server'
local Session = require 'utils.datastore.session_data'
local Modifers = require 'player_modifiers'
local WPT = require 'maps.amap.table'

local Public = {}
local function cleanup_other_surfaces()
    -- 1. 摧毁太空平台 (Space Age 特有)
    -- 遍历所有势力，查找并摧毁其拥有的平台
    for _, force in pairs(game.forces) do
        if force.platforms then -- 确保 API 存在
            -- 注意：在遍历过程中删除元素通常需要倒序或小心处理，
            -- 但 destroy() 通常是安全的，不过为了稳妥，我们收集后再删
            local platforms_to_kill = {}
            for _, platform in pairs(force.platforms) do
                table.insert(platforms_to_kill, platform)
            end

            for _, platform in pairs(platforms_to_kill) do
                if platform.valid then
                    platform.destroy() -- 这会连带删除平台对应的 surface
                end
            end
        end
    end

    -- 2. 删除其他所有地表 (Vulcanus, Fulgora, 自定义地表等)
    for name, surface in pairs(game.surfaces) do
        if name ~= "nauvis" and surface.valid then
            game.delete_surface(surface)
        end
    end
end
local function reset_forces(new_surface)
    local spawn = {
        x = game.forces.player.get_spawn_position(new_surface).x,
        y = game.forces.player.get_spawn_position(new_surface).y
    }
    for _, f in pairs(game.forces) do
        f.reset()
        f.reset_evolution()
        f.set_spawn_position(spawn, new_surface)
    end
end

local function teleport_players(surface)
    if not surface or not surface.valid then
        return
    end
    game.forces.player.set_spawn_position({0, 0}, surface)
    local spawn_position = game.forces.player.get_spawn_position(surface) or {0, 0}

    for _, player in pairs(game.connected_players) do
        local teleport_position = surface.find_non_colliding_position('character', spawn_position, 3, 0) or spawn_position
        player.teleport(teleport_position, surface)
    end
end

local function equip_players(player_starting_items, data)
    local offline_players = {}

    for _, player in pairs(game.players) do
        if player.connected then
            local saved_quickbar = {}
            local quick_bar_width = player.quick_bar_width or 10
            for i = 1, 100 do
                local page = math.floor((i-1) / quick_bar_width) + 1
                local slot = ((i-1) % quick_bar_width) + 1
                local filter = player.get_quick_bar_slot(page, slot)
                if filter then
                    saved_quickbar[i] = {page = page, slot = slot, filter = filter}
                end
            end

            if player.character and player.character.valid then
                player.character.destroy()
            end

            if not player.character then
                player.set_controller({type = defines.controllers.god})
                player.create_character()
            end

            player.clear_items_inside()
            Modifers.update_player_modifiers(player)

            for item, amount in pairs(player_starting_items) do
                player.insert({name = item, count = amount})
            end

            for i, data in pairs(saved_quickbar) do
                if data.filter and data.filter.valid then
                    player.set_quick_bar_slot(data.page, data.slot, data.filter)
                end
            end
        else
            table.insert(offline_players, player.index)
        end
    end

    if #offline_players > 0 then
        for _, player_index in pairs(offline_players) do
            local player = game.players[player_index]
            if player then
                data.players[player.index] = nil
                Session.clear_player(player)
            end
        end
        game.remove_offline_players(offline_players)
    end
end
local function remove_all_chart_tags(surface)
    -- 地图标记是归属于"势力"的，所以我们需要遍历势力
    -- 通常只需要清理 player 势力，但为了保险遍历所有
    for _, force in pairs(game.forces) do
        -- 查找该势力在这个地表上的所有标记
        -- find_chart_tags 第二个参数不传则默认搜索整个地表
        local tags = force.find_chart_tags(surface)

        for _, tag in pairs(tags) do
            if tag.valid then
                tag.destroy()
            end
        end
    end
end
local function clear_linked_chest_inventories()
    -- 显式清空所有关联箱（linked-chest）的共享库存。
    -- Factorio 2.0+ 的 linked-chest 共享库存是引擎级全局状态，
    -- surface.clear() 销毁实体后库存可能不立即释放，故在此主动清理。
    local cleared_link_ids = {}
    for _, surface in pairs(game.surfaces) do
        if surface.valid then
            local chests = surface.find_entities_filtered({type = 'linked-chest'})
            for _, chest in pairs(chests) do
                if chest.valid then
                    local link_id = chest.link_id
                    if not cleared_link_ids[link_id] then
                        cleared_link_ids[link_id] = true
                        local inv = chest.get_inventory(defines.inventory.chest)
                        if inv and not inv.is_empty() then
                            inv.clear()
                        end
                    end
                end
            end
        end
    end
end
function Public.soft_reset_map(old_surface, map_gen_settings, player_starting_items)

    local this = WPT.get()

    local new_surface = game.surfaces["nauvis"]

    if map_gen_settings then
        -- 确保我们有一个新的随机种子，除非传入参数指定了旧种子
        if not map_gen_settings.seed then
            map_gen_settings.seed = math.random(1, 4294967295)
        end
        new_surface.map_gen_settings = map_gen_settings
    end

    clear_linked_chest_inventories()
    new_surface.clear(true)
    remove_all_chart_tags(new_surface)
    --清空玩家的所有物品，背包，武器栏，手持物品等等（在equip_players函数中通过player.clear_items_inside()实现）
    new_surface.request_to_generate_chunks({0, 0}, 1)
    reset_forces(new_surface)
    teleport_players(new_surface)
    equip_players(player_starting_items, this)
    cleanup_other_surfaces()

    return new_surface
end

return Public
