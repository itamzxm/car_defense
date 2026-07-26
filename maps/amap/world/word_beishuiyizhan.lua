local WPT = require 'maps.amap.table'
local diff = require 'maps.amap.diff'
local Event = require 'utils.event'
local ThreatValues = require 'modules.wave_defense.threat_values'
local WorldTable = require 'maps.amap.world.world_table'

local beishuiyizhan = {}

local STRATEGIC_POINTS_CONVERT_INTERVAL = 15
local BIO_LAB_ENERGY_UPDATE_INTERVAL = 1

local science_pack_values = {
    ['automation-science-pack'] = 2,
    ['logistic-science-pack'] = 8,
    ['military-science-pack'] = 34,
    ['chemical-science-pack'] = 84,
    ['production-science-pack'] = 148,
    ['utility-science-pack'] = 168,
}

local function create_bio_lab(surface)
    local this = WPT.get()
    if not this.bio_labs then
        this.bio_labs = {}
    end
    if #this.bio_labs>=1 then 
        return 
    end
    local lab_pos = {x = 0, y = 8}
    local lab = surface.create_entity({
        name = "biolab",
        position = lab_pos,
        force = "player"
    })
    if lab and lab.valid then
        lab.destructible = false
        lab.minable_flag = false
        table.insert(this.bio_labs, lab)
    end
end

local function get_bio_labs()
    local this = WPT.get()
    if not this.bio_labs then
        this.bio_labs = {}
    end
    return this.bio_labs
end

local function on_entity_died(event)
    local entity = event.entity
    if not entity or not entity.valid then return end
    
    if entity.force.name == "enemy" then
        local map = diff.get()
        if map.world ~= 12 then return end
        
        local this = WPT.get()
        local threat_value = ThreatValues[entity.name] or 0
        
        if not this.strategic_points then
            this.strategic_points = 0
        end
        
        this.strategic_points = this.strategic_points + threat_value
    
    end
end

local function convert_strategic_points()
    local this = WPT.get()
    if not this.strategic_points or this.strategic_points <= 0 then return end
    
    local bio_labs = get_bio_labs()
    if #bio_labs == 0 then return end
    
    local lab = bio_labs[1]
    if not lab or not lab.valid then return end
    
    local inventory = lab.get_inventory(defines.inventory.lab_input)
    if not inventory then return end
    
    -- 使用 points 局部变量操作，减少对全局表的频繁访问
    local points = this.strategic_points

    ---------------------------------------------------------
    -- 1. 找出所有瓶子（6种）中的“绝对最小值”
    -- 必须涵盖 science_pack_values 定义的所有瓶子，缺货的按 0 计算
    ---------------------------------------------------------
    local min_count = nil
    for pack_name, _ in pairs(science_pack_values) do
        -- 直接从仓库获取精确数量，如果仓库没有这种瓶子，返回 0
        local count = inventory.get_item_count(pack_name)
        if min_count == nil or count < min_count then
            min_count = count
        end
    end

    -- 如果配置表为空，直接退出
    if min_count == nil then return end

    ---------------------------------------------------------
    -- 2. 计算本轮全局唯一的“目标阶梯” (target_count)
    -- 无论红绿有多少，目标只由最低的那个瓶子决定
    ---------------------------------------------------------
    local target_count = math.min((math.floor(min_count / 20) + 1) * 20, 199)
    
    ---------------------------------------------------------
    -- 3. 遍历补货：只有“当前数量 < 目标”的瓶子才补货
    ---------------------------------------------------------
    for pack_name, value in pairs(science_pack_values) do
        local current_count = inventory.get_item_count(pack_name)
        
        -- 【核心逻辑判断】
        -- 如果红瓶 118，目标 20 (因为蓝瓶 19)， 118 < 20 为假，绝对不会执行插入
        if current_count < target_count then
            local needed = target_count - current_count
            local max_affordable = math.floor(points / value)
            local count_to_add = math.min(needed, max_affordable)
            
            if count_to_add > 0 then
                local inserted = inventory.insert({name = pack_name, count = count_to_add})
                if inserted > 0 then
                    local cost = inserted * value
                    points = points - cost
                    -- 实时更新全局点数，防止扣费不同步
                    this.strategic_points = points 
                    
                    -- 如果中途点数扣光，立刻终止
                    if points <= 0 then return end
                end
            end
        end
    end
end

local function update_bio_lab_energy()
    local bio_labs = get_bio_labs()
    for _, lab in ipairs(bio_labs) do
        if lab and lab.valid then
            lab.energy = 99999999999999
        end
    end
    
    local valid_labs = {}
    for _, lab in ipairs(bio_labs) do
        if lab and lab.valid then
            table.insert(valid_labs, lab)
        end
    end
    local this = WPT.get()
    this.bio_labs = valid_labs
end

local function on_tick(event)
    local map = diff.get()
    if map.world ~= 12 then return end
    
    local tick = event.tick
    
    if tick % STRATEGIC_POINTS_CONVERT_INTERVAL == 0 then
        convert_strategic_points()
    end
    
    if tick % BIO_LAB_ENERGY_UPDATE_INTERVAL == 0 then
        update_bio_lab_energy()
    end
end

local function on_research_finished(event)
    local research = event.research
    local map = diff.get()
    
    if map.world ~= 12 then return end
    
    if research.name == "utility-science-pack" then
        local surface = game.surfaces['nauvis']
        local this = WPT.get()
        
        if not this.port_discovered then
            this.port_discovered = true
            
            if script.active_mods["space-age"] then
                local random_planet = {"nauvis", "vulcanus", "fulgora", "gleba", "aquilo"}
               --  local random_planet = { "fulgora"}
                local planet_name = random_planet[math.random(1, #random_planet)]
                local map_gen_settings = table.deepcopy(game.planets[planet_name].prototype.map_gen_settings)
                
                if planet_name == "nauvis" then
                    local world_data = WorldTable.get()
                    local cave_config = world_data.surface_configs.cave
                    
                    for resource_name, settings in pairs(cave_config) do
                        if map_gen_settings.autoplace_controls[resource_name] then
                            map_gen_settings.autoplace_controls[resource_name].frequency = settings.frequency
                            map_gen_settings.autoplace_controls[resource_name].size = settings.size
                            map_gen_settings.autoplace_controls[resource_name].richness = settings.richness
                        end
                    end
                end
                
                surface.map_gen_settings = map_gen_settings
                game.print({"amap.world12_planet_unlocked", planet_name})
                
                local force = game.forces.player
            if planet_name == "vulcanus" then
                force.technologies["planet-discovery-vulcanus"].researched = true
            elseif planet_name == "fulgora" then
                force.technologies["planet-discovery-fulgora"].researched = true
            elseif planet_name == "gleba" then
                force.technologies["planet-discovery-gleba"].researched = true
            elseif planet_name == "aquilo" then
                force.technologies["planet-discovery-aquilo"].researched = true
            end
            end
        end
    end
end


function beishuiyizhan.create_initial_bio_lab(surface)
    create_bio_lab(surface)
end

function beishuiyizhan.get_strategic_points()
    local this = WPT.get()
    return this.strategic_points or 0
end

function beishuiyizhan.is_port_discovered()
    local this = WPT.get()
    return this.port_discovered or false
end

Event.add(defines.events.on_entity_died, on_entity_died)
Event.on_nth_tick(1, on_tick)
Event.add(defines.events.on_research_finished, on_research_finished)

return beishuiyizhan
