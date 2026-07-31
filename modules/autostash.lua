local Global = require 'utils.global'
local Core = require 'utils.utils'
local SpamProtection = require 'utils.spam_protection'
local Color = require 'utils.color_presets'
local Event = require 'utils.event'
local GuiDispatcher = require 'utils.gui_dispatcher'
local TopBar = require 'utils.top_bar'
local GuiRebuild = require 'utils.gui_rebuild'
local BottomFrame = require 'comfy_panel.bottom_frame'

local floor = math.floor
local module_name = '[color=blue][Autostash][/color] '

local this = {
    floating_text_y_offsets = {},
    whitelist = {},
    furnace_fuel = {},
    insert_to_neutral_chests = false,
    insert_into_furnace = false,
    insert_into_wagon = false,
    bottom_button = false,
    small_radius = 2,
    limit_containers = 50,
    enabled = true
}

local Public = {}

Global.register(
    this,
    function(t)
        this = t
    end
)

local bps_blacklist = {
    ['blueprint-book'] = true,
    ['blueprint'] = true
}

local function create_floaty_text(surface, position, name, count)
    if this.floating_text_y_offsets[position.x .. '_' .. position.y] then
        this.floating_text_y_offsets[position.x .. '_' .. position.y] = this.floating_text_y_offsets[position.x .. '_' .. position.y] - 0.5
    else
        this.floating_text_y_offsets[position.x .. '_' .. position.y] = 0
    end

    if not surface.valid then return end

    for _, player in pairs(game.connected_players) do
        if player.physical_surface_index == surface.index then
            player.create_local_flying_text(
                {
                    position = {
                        position.x,
                        position.y + this.floating_text_y_offsets[position.x .. '_' .. position.y]
                    },
                    text = {'', '-', count, ' ', prototypes.item[name].localised_name},
                    color = {r = 255, g = 255, b = 255}
                }
            )
        end
    end
end

local function prepare_floaty_text(list, surface, position, name, count)
    local str = surface.index .. ',' .. position.x .. ',' .. position.y
    if not list[str] then
        list[str] = {}
    end
    if not list[str][name] then
        list[str][name] = {surface = surface, position = position, count = 0}
    end
    list[str][name].count = list[str][name].count + count
end

local function chest_is_valid(chest)
    for _, e in pairs(
        chest.surface.find_entities_filtered(
            {
                type = {'inserter', 'loader'},
                area = {{chest.position.x - 1, chest.position.y - 1}, {chest.position.x + 1, chest.position.y + 1}}
            }
        )
    ) do
        if e.name ~= 'long-handed-inserter' then
            if e.position.x == chest.position.x then
                if e.direction == 0 or e.direction == 16 then
                    return false
                end
            end
            if e.position.y == chest.position.y then
                if e.direction == 8 or e.direction == 24 then
                    return false
                end
            end
        end
    end

    local i1 = chest.surface.find_entity('long-handed-inserter', {chest.position.x - 2, chest.position.y})
    if i1 then
        if i1.direction == 8 or i1.direction == 24 then
            return false
        end
    end
    local i2 = chest.surface.find_entity('long-handed-inserter', {chest.position.x + 2, chest.position.y})
    if i2 then
        if i2.direction == 8 or i2.direction == 24 then
            return false
        end
    end

    local i3 = chest.surface.find_entity('long-handed-inserter', {chest.position.x, chest.position.y - 2})
    if i3 then
        if i3.direction == 0 or i3.direction == 16 then
            return false
        end
    end
    local i4 = chest.surface.find_entity('long-handed-inserter', {chest.position.x, chest.position.y + 2})
    if i4 then
        if i4.direction == 0 or i4.direction == 16 then
            return false
        end
    end

    return true
end

local function sort_entities_by_distance(position, entities)
    local t = {}
    local distance
    local index
    local size_of_entities = #entities
    if size_of_entities < 2 then
        return entities
    end

    for _, entity in pairs(entities) do
        distance = (entity.position.x - position.x) ^ 2 + (entity.position.y - position.y) ^ 2
        index = floor(distance) + 1
        if not t[index] then
            t[index] = {}
        end
        table.insert(t[index], entity)
    end

    local i = 0
    local containers = {}
    for _, range in pairs(t) do
        for _, entity in pairs(range) do
            i = i + 1
            if i >= (this.limit_containers or 50) then
                return containers
            end
            containers[i] = entity
        end
    end

    return containers
end

local function get_nearby_chests(player, a, furnace, wagon)
    local r = player.force.character_reach_distance_bonus + 10
    local r_square = r * r
    local chests, inventories = {}, {}
    local size_of_chests = 0
    local area = {{player.physical_position.x - r, player.physical_position.y - r}, {player.physical_position.x + r, player.physical_position.y + r}}

    area = a or area

    local container_type = {'container', 'logistic-container', 'linked-container'}
    local inventory_type = defines.inventory.chest
    local containers = {}
    local i = 0

    if furnace then
        container_type = {'furnace', 'mining-drill'}
        inventory_type = defines.inventory.crafter_input
    end
    if wagon then
        container_type = {'cargo-wagon', 'logistic-container'}
        inventory_type = defines.inventory.cargo_wagon
    end

    local forces = player.force
    if this.insert_to_neutral_chests then
        forces = {player.force, 'neutral'}
    end

    for _, e in pairs(player.physical_surface.find_entities_filtered({type = container_type, area = area, force = forces})) do
        if ((player.physical_position.x - e.position.x) ^ 2 + (player.physical_position.y - e.position.y) ^ 2) <= r_square then
            i = i + 1
            containers[i] = e
        end
    end

    if #containers <= 0 and not furnace and not wagon then
        if script.active_mods['Krastorio2'] then
            for _, e in pairs(player.physical_surface.find_entities_filtered({type = 'assembling-machine', area = area, force = forces})) do
                if ((player.physical_position.x - e.position.x) ^ 2 + (player.physical_position.y - e.position.y) ^ 2) <= r_square then
                    i = i + 1
                    containers[i] = e
                end
            end
        end
    end

    containers = sort_entities_by_distance(player.physical_position, containers)
    for _, entity in pairs(containers) do
        size_of_chests = size_of_chests + 1
        chests[size_of_chests] = entity
        inventories[size_of_chests] = entity.get_inventory(inventory_type)
    end
    return {chest = chests, inventory = inventories}
end

local function check_if_valid_requests(chest)
    if not chest or not chest.valid then
        return false
    end

    local logistics = chest.get_logistic_point(defines.logistic_member_index.logistic_container)
    if logistics then
        local filters = Core.get_filters(logistics)
        return #filters > 0
    else
        return false
    end
end

local function insert_to_furnace(inventory, stack, chests, floaty_text_list)
    local name = stack.name
    local quality = stack.quality
    local total_count = stack.count

    if total_count <= 0 then
        return
    end

    local chest_list = chests.chest
    if not chest_list or #chest_list == 0 then
        return
    end

    local chest_count = #chest_list
    local try = 0
    local max_tries = chest_count

    local function apply_and_remove(inserted, chest)
        if inserted <= 0 then return 0 end
        if not inventory then return 0 end

        local removed = inventory.remove({name = name, count = inserted, quality = quality})
        if removed <= 0 then return 0 end

        total_count = total_count - removed
        prepare_floaty_text(floaty_text_list, chest.surface, chest.position, name, removed)
        return removed
    end

    local function check_weight()
        if chest_count <= 0 then return 0, 0 end
        local base = math.floor(total_count / chest_count)
        local var = total_count % chest_count
        return base, var
    end

    local to_insert, variate = check_weight()

    ::retry::

    for chest_index, chest in pairs(chest_list) do
        if total_count <= 0 then return end

        local chest_inventory = chests.inventory[chest_index]
        if not chest_inventory then
            goto continue
        end

        if chest.type ~= 'furnace' and chest.type ~= 'assembling-machine' and chest.type ~= 'mining-drill' then
            goto continue
        end

        local amount = to_insert
        if variate > 0 then
            amount = amount + 1
            variate = variate - 1
        end

        if amount <= 0 then
            return
        end

        if amount > total_count then
            amount = total_count
        end

        if name == 'stone' then
            if amount % 2 ~= 0 then
                try = try + 1
                if try <= max_tries then
                    chest_count = chest_count - 1
                    if chest_count <= 0 then return end
                    to_insert, variate = check_weight()
                    goto retry
                else
                    return
                end
            end
        end

        if chest_inventory.can_insert({name = name, count = amount, quality = quality}) then
            local inserted = chest_inventory.insert({name = name, count = amount, quality = quality})
            apply_and_remove(inserted, chest)
        end

        ::continue::
    end

    to_insert, variate = check_weight()

    for _, chest in pairs(chest_list) do
        if total_count <= 0 then return end

        if chest.type ~= 'furnace' and chest.type ~= 'assembling-machine' then
            goto end_func
        end

        local amount = to_insert
        if variate > 0 then
            amount = amount + 1
            variate = variate - 1
        end

        if amount <= 0 then
            return
        end

        if amount > total_count then
            amount = total_count
        end

        local inv = chest.get_inventory(defines.inventory.chest)
        if inv and inv.can_insert({name = name, count = amount, quality = quality}) then
            local inserted = inv.insert({name = name, count = amount, quality = quality})
            apply_and_remove(inserted, chest)
        end

        ::end_func::
    end
end

local function insert_into_wagon(stack, chests, name, floaty_text_list)
    for chestnr, chest in pairs(chests.chest) do
        if chest.type == 'cargo-wagon' then
            local chest_inventory = chests.inventory[chestnr]
            if chest_inventory and chest_inventory.can_insert(stack) then
                local inserted_count = chest_inventory.insert(stack)
                stack.count = stack.count - inserted_count
                prepare_floaty_text(floaty_text_list, chest.surface, chest.position, name, inserted_count)
                if stack.count <= 0 then
                    return chestnr
                end
            end
        end
    end
end

local function insert_into_wagon_filtered(stack, chests, name, floaty_text_list)
    for chestnr, chest in pairs(chests.chest) do
        if chest.type == 'cargo-wagon' then
            local chest_inventory = chests.inventory[chestnr]
            if chest_inventory then
                for index = 1, 40 do
                    if chest_inventory.can_insert(stack) then
                        if chest_inventory.get_filter(index) ~= nil then
                            local n = chest_inventory.get_filter(index)
                            if n == name then
                                local inserted_count = chest_inventory.insert(stack)
                                stack.count = stack.count - inserted_count
                                prepare_floaty_text(floaty_text_list, chest.surface, chest.position, name, inserted_count)
                                if stack.count <= 0 then
                                    return chestnr
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    for chestnr, chest in pairs(chests.chest) do
        if chest.type == 'logistic-container' then
            local chest_inventory = chests.inventory[chestnr]
            if chest_inventory then
                local logistics = chest.get_logistic_point(defines.logistic_member_index.logistic_container)
                if logistics then
                    local filters = Core.get_filters(logistics)
                    for _, filter in pairs(filters) do
                        if filter.value.name == name then
                            local inserted_count = chest_inventory.insert(stack)
                            stack.count = stack.count - inserted_count
                            prepare_floaty_text(floaty_text_list, chest.surface, chest.position, name, inserted_count)
                            if stack.count <= 0 then
                                return chestnr
                            end
                        end
                    end
                end
            end
        end
    end
end

local function insert_item_into_chest(stack, chests, filtered_chests, name, floaty_text_list, previous_insert)
    local container = {
        ['container'] = true,
        ['logistic-container'] = true,
        ['linked-container'] = true
    }

    if previous_insert and previous_insert.name == name and previous_insert.full ~= nil then
        local chest_inventory = chests.inventory[previous_insert.full]
        if chest_inventory and chest_inventory.can_insert(stack) then
            local inserted_count = chest_inventory.insert(stack)
            stack.count = stack.count - inserted_count
            prepare_floaty_text(floaty_text_list, chests.chest[previous_insert.full].surface, chests.chest[previous_insert.full].position, name, inserted_count)
            if stack.count <= 0 then
                return previous_insert.full
            end
        end
    end

    for chestnr, chest in pairs(chests.chest) do
        if chest.type == 'logistic-container' then
            local chest_inventory = chests.inventory[chestnr]
            if chest_inventory then
                local logistics = chest.get_logistic_point(defines.logistic_member_index.logistic_container)
                if logistics then
                    local filters = Core.get_filters(logistics)
                    for _, filter in pairs(filters) do
                        if filter.value.name == name then
                            local inserted_count = chest_inventory.insert(stack)
                            stack.count = stack.count - inserted_count
                            prepare_floaty_text(floaty_text_list, chest.surface, chest.position, name, inserted_count)
                            if stack.count <= 0 then
                                return chestnr
                            end
                        end
                    end
                end
            end
        end
    end

    for chestnr, chest in pairs(chests.chest) do
        if container[chest.type] then
            if check_if_valid_requests(chest) then
                goto continue
            end
            local chest_inventory = chests.inventory[chestnr]
            if chest_inventory and chest_inventory.find_item_stack(stack.name) then
                if chest_inventory.can_insert(stack) then
                    local inserted_count = chest_inventory.insert(stack)
                    stack.count = stack.count - inserted_count
                    prepare_floaty_text(floaty_text_list, chest.surface, chest.position, name, inserted_count)
                    if stack.count <= 0 then
                        return chestnr
                    end
                end
            end
            ::continue::
        end
    end

    for chestnr, chest in pairs(filtered_chests.chest) do
        if container[chest.type] then
            if check_if_valid_requests(chest) then
                goto continue
            end
            local chest_inventory = filtered_chests.inventory[chestnr]
            if not chest_inventory then
                break
            end
            local count = chest_inventory.get_item_count() == 0
            if count then
                local inserted_count = chest_inventory.insert(stack)
                stack.count = stack.count - inserted_count
                prepare_floaty_text(floaty_text_list, chest.surface, chest.position, name, inserted_count)
                if stack.count <= 0 then
                    return chestnr
                end
            end
            ::continue::
        end
    end

    local item_prototypes = prototypes.item

    local item_subgroup = prototypes.item[name].subgroup.name
    if item_subgroup then
        for chestnr, chest in pairs(filtered_chests.chest) do
            if check_if_valid_requests(chest) then
                goto continue
            end
            if container[chest.type] then
                local chest_inventory = filtered_chests.inventory[chestnr]
                if not chest_inventory then
                    break
                end
                local content = chest_inventory.get_contents()
                if chest_inventory.can_insert(stack) then
                    for equal_name, _ in pairs(content) do
                        local t = item_prototypes[equal_name]
                        if t and t.subgroup.name == item_subgroup then
                            local inserted_count = chest_inventory.insert(stack)
                            stack.count = stack.count - inserted_count
                            prepare_floaty_text(floaty_text_list, chest.surface, chest.position, name, inserted_count)
                            if stack.count <= 0 then
                                return chestnr
                            end
                        end
                    end
                end
            end
            ::continue::
        end
    end

    for chestnr, chest in pairs(filtered_chests.chest) do
        if container[chest.type] then
            if check_if_valid_requests(chest) then
                goto continue
            end
            local chest_inventory = filtered_chests.inventory[chestnr]
            if not chest_inventory then
                break
            end
            if chest_inventory.can_insert(stack) then
                local inserted_count = chest_inventory.insert(stack)
                stack.count = stack.count - inserted_count
                prepare_floaty_text(floaty_text_list, chest.surface, chest.position, name, inserted_count)
                if stack.count <= 0 then
                    return chestnr
                end
            end
            ::continue::
        end
    end
end

local function auto_stash(player, event)
    local button = event.button
    local ctrl = event.control
    local shift = event.shift
    if not player.character then
        player.print({'amap.autostash_not_living'}, {color = Color.warning})
        return
    end
    if not player.character.valid then
        player.print({'amap.autostash_not_living'}, {color = Color.warning})
        return
    end
    local inventory = player.get_main_inventory()
    if not inventory then return end
    if inventory.is_empty() then
        player.print({'amap.autostash_empty'}, {color = Color.warning})
        return
    end

    local floaty_text_list = {}
    local chests = {chest = {}, inventory = {}}
    local r = this.small_radius
    local area = {{player.physical_position.x - r, player.physical_position.y - r}, {player.physical_position.x + r, player.physical_position.y + r}}
    if ctrl then
        if button == defines.mouse_button_type.right and this.insert_into_furnace then
            chests = get_nearby_chests(player, nil, true, false)
        end
    elseif shift then
        if button == defines.mouse_button_type.right and this.insert_into_wagon or button == defines.mouse_button_type.left and this.insert_into_wagon then
            chests = get_nearby_chests(player, area, false, true)
        end
    else
        chests = get_nearby_chests(player, area, false, false)
    end

    if not chests.chest or not chests.chest[1] then
        player.print({'amap.autostash_no_containers'}, {color = Color.warning})
        return
    end

    local filtered_chests = {chest = {}, inventory = {}}
    for index, e in pairs(chests.chest) do
        if chest_is_valid(e) then
            filtered_chests.chest[index] = e
            filtered_chests.inventory[index] = chests.inventory[index]
        end
    end

    this.floating_text_y_offsets = {}

    local hotbar_items = {}
    local quick_bar_width = player.quick_bar_width or 10
    for i = 1, 100, 1 do
        local page = math.floor((i - 1) / quick_bar_width) + 1
        local slot_index = ((i - 1) % quick_bar_width) + 1
        local prototype = player.get_quick_bar_slot(page, slot_index)
        if prototype and prototype.name then
            hotbar_items[prototype.name] = true
        end
    end

    local furnace_fuels = {}
    for fuel_name, _ in pairs(this.furnace_fuel) do
        furnace_fuels[fuel_name] = {count = 0, quality = nil}
    end

    local full_insert = {full = nil, name = nil}
    for i = #inventory, 1, -1 do
        if not inventory[i].valid_for_read then
            goto continue
        end
        local name = inventory[i].name
        local is_resource = this.whitelist[name]
        local is_furnace_fuel = this.furnace_fuel[name]
        if not hotbar_items[name] and not bps_blacklist[name] then
            if ctrl and this.insert_into_furnace then
                if button == defines.mouse_button_type.right then
                    if is_furnace_fuel or is_resource then
                        furnace_fuels[name] = furnace_fuels[name] or {count = 0, quality = nil}
                        furnace_fuels[name].count = furnace_fuels[name].count + inventory[i].count
                        furnace_fuels[name].quality = inventory[i].quality
                    end
                end
            elseif shift and this.insert_into_wagon then
                if button == defines.mouse_button_type.right then
                    if is_resource then
                        full_insert = {full = insert_into_wagon(inventory[i], chests, name, floaty_text_list), name = name}
                    end
                end
                if button == defines.mouse_button_type.left then
                    full_insert = {full = insert_into_wagon_filtered(inventory[i], chests, name, floaty_text_list), name = name}
                end
            elseif button == defines.mouse_button_type.right then
                if is_resource then
                    full_insert = {full = insert_item_into_chest(inventory[i], chests, filtered_chests, name, floaty_text_list, full_insert), name = name}
                end
            elseif button == defines.mouse_button_type.left then
                full_insert = {full = insert_item_into_chest(inventory[i], chests, filtered_chests, name, floaty_text_list, full_insert), name = name}
            end
        end
        ::continue::
    end

    for item_name, item_data in pairs(furnace_fuels) do
        local stack = {name = item_name, count = item_data.count, quality = item_data.quality}
        insert_to_furnace(inventory, stack, chests, floaty_text_list)
    end

    for _, texts in pairs(floaty_text_list) do
        for item_name, text in pairs(texts) do
            create_floaty_text(text.surface, text.position, item_name, text.count)
        end
    end

    local c = this.floating_text_y_offsets
    for k, _ in pairs(c) do
        this.floating_text_y_offsets[k] = nil
    end
end

local auto_stash_button_name = 'auto_stash'

local function create_gui_button(player, bottom_frame_data)
    bottom_frame_data = bottom_frame_data or BottomFrame.get_player_data(player)

    local tooltip
    if this.insert_into_furnace and this.insert_into_wagon then
        tooltip = {'amap.autostash_tooltip_furnace_wagon'}
    elseif this.insert_into_furnace then
        tooltip = {'amap.autostash_tooltip_furnace'}
    elseif this.insert_into_wagon then
        tooltip = {'amap.autostash_tooltip_wagon'}
    else
        tooltip = {'amap.autostash_tooltip_default'}
    end

    local flow = TopBar.get_button_flow(player)
    local button

    if not flow[auto_stash_button_name] then
        button = TopBar.add_button(player, {
            type = 'sprite-button',
            sprite = 'item/wooden-chest',
            name = auto_stash_button_name,
            tooltip = tooltip
        })
        button.style.padding = 1
        button.style.margin = 0
    else
        button = flow[auto_stash_button_name]
        button.tooltip = tooltip
    end

    if this.bottom_button then
        if bottom_frame_data and not bottom_frame_data.top then
            if button and button.valid then
                button.destroy()
            end
        end
    end
end

local function do_whitelist()
    if not this.enabled then
        return
    end
    local resources = prototypes.entity
    this.whitelist = {}
    for k, _ in pairs(resources) do
        if resources[k] and resources[k].type == 'resource' and resources[k].mineable_properties then
            if resources[k].mineable_properties.products and resources[k].mineable_properties.products[1] then
                local r = resources[k].mineable_properties.products[1].name
                this.whitelist[r] = true
            elseif resources[k].mineable_properties.products and resources[k].mineable_properties.products[2] then
                local r = resources[k].mineable_properties.products[2].name
                this.whitelist[r] = true
            end
        end
    end

    local items = prototypes.item
    for k, _ in pairs(items) do
        if items[k] and items[k].group.name == 'resource-refining' then
            local r = items[k].name
            this.whitelist[r] = true
        end
        if items[k] and items[k].fuel_category and items[k].fuel_value then
            local r = items[k].name
            this.furnace_fuel[r] = 0
        end
        if items[k] and items[k].name:find('%f[%a][Oo]re%f[%A]') then
            this.whitelist[k] = true
        end
    end
end

local function on_player_joined_game(event)
    if not this.enabled then
        return
    end
    local player = game.players[event.player_index]
    create_gui_button(player)
    if this.bottom_button then
        BottomFrame.add_inner_frame({
            player = player,
            element_name = auto_stash_button_name,
            tooltip = {'amap.autostash_tooltip_default'},
            sprite = 'item/wooden-chest'
        })
    end
end

local function on_auto_stash_click(event)
    local player = game.players[event.player_index]
    local is_spamming = SpamProtection.is_spamming(player, nil, 'Autostash click')
    if is_spamming then
        return
    end
    auto_stash(player, event)
end

GuiDispatcher.register_click('auto_stash', on_auto_stash_click)

function Public.insert_into_furnace(value)
    this.insert_into_furnace = value or false
end

function Public.insert_into_wagon(value)
    this.insert_into_wagon = value or false
end

function Public.bottom_button(value)
    this.bottom_button = value or false
end

function Public.limit_containers(value)
    this.limit_containers = value or 50
end

function Public.insert_to_neutral_chests(value)
    this.insert_to_neutral_chests = value or false
end

function Public.set_enabled(value)
    this.enabled = value or false
end

Event.on_configuration_changed(do_whitelist)

Event.on_init(do_whitelist)
Event.add(defines.events.on_player_joined_game, on_player_joined_game)

Event.add(
    BottomFrame.events.bottom_quickbar_location_changed,
    function(event)
        if not this.enabled then
            return
        end
        local player_index = event.player_index
        if not player_index then
            return
        end
        local player = game.get_player(player_index)
        if not player or not player.valid then
            return
        end
        create_gui_button(player, event.data)
    end
)

GuiRebuild.register('autostash', function(player)
    create_gui_button(player)
end)

return Public
