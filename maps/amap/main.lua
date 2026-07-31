local Public = {}
-- hi guy!
local reset_pos = require'stronghold_generation_algorithm_v2'.reset_table
local Factories = require 'maps.amap.production'
local RPG = require 'modules.rpg.main'
local PL = require 'comfy_panel.player_list'
local Functions = require 'maps.amap.functions'
local BiterClass = require 'maps.amap.biter_class'
local IC = require 'maps.amap.ic.table'
local ICW = require 'maps.amap.ICW.table'
local CS = require 'maps.amap.surface'
local Balance = require 'maps.amap.balance'
local Event = require 'utils.event'
local ICMinimap = require 'maps.amap.ic.minimap'

local WD = require 'modules.wave_defense.table'
local Map = require 'modules.map_info'
local WPT = require 'maps.amap.table'
local WorldTable = require 'maps.amap.world.world_table'
local Autostash = require 'modules.autostash'
local BottomFrame = require 'comfy_panel.bottom_frame'
local rock = require 'maps.amap.rock'
local Loot = require 'maps.amap.loot'
local Modifiers = require 'player_modifiers'
local Difficulty = require 'modules.difficulty_vote_by_amount'
local arty = require "maps.amap.enemy_arty"
local diff = require 'maps.amap.diff'
local World = require 'maps.amap.world.framework'  -- 世界框架

local Collapse = require 'modules.collapse'
local global = require 'utils.global'
local Instance = require 'maps.amap.instance.instance'  -- 史诗木箱 spawn API

require "maps.amap.vote_choise_map"

local collapse_kill = {
    entities = {
        ['laser-turret'] = true,
        ['flamethrower-turret'] = true,
        ['gun-turret'] = true,
        ['artillery-turret'] = true,
        ['land-mine'] = true,
        ['locomotive'] = true,
        ['cargo-wagon'] = true,
        ['character'] = true,
        ['car'] = true,
        ['tank'] = true,
        ['assembling-machine'] = true,
        ['furnace'] = true,
        ['steel-chest'] = true
    },
    enabled = true
}


local player_build = {'steam-turbine', 'assembling-machine-1', 'assembling-machine-2', 'assembling-machine-3',
                      'oil-refinery', 'chemical-plant', 'car', 'spidertron', 'tank', 'character', 'gun-turret',
                      'electric-mining-drill', 'laser-turret', 'steam-engine', 'big-mining-drill'    ,'foundry'
  ,'recycler'
  ,'electromagnetic-plant'
  ,'heating-tower','rail-support'}
local tianfu = require 'maps.amap.tianfu'

require 'maps.amap.mining'
require "modules.rocks_yield_ore_veins"

require 'maps.amap.auto_put_turret'
require 'maps.amap.world.world_main'
require 'maps.amap.gui'
-- require 'maps.amap.market_gui'  -- 已禁用自定义市场 GUI，恢复官方界面

require 'maps.amap.biter_die'

require 'maps.amap.ic.main'
require 'maps.amap.ICW.main'
require 'maps.amap.biters_yield_coins'
require 'maps.amap.magic_wood'


require 'modules.shotgun_buff'
require 'modules.no_deconstruction_of_neutral_entities'
require 'modules.wave_defense.main'
require 'modules.charging_station'

local pet_system = require 'modules.pet_system.table'
local PseudoBuilding = require 'maps.amap.pseudo_building.main'  -- 伪建筑框架（门面，内部 require 5 个 buildings）



local function insert_coin_to_player(player, coin_count)
  if not player or not player.valid then
    return false
  end
  
  if not coin_count or coin_count <= 0 then
    return false
  end
  
  local this = WPT.get()
  local dungeon_data = nil
  if this.dungeons then
    dungeon_data = this.dungeons[player.index]
  end
  
  local target_character = player.character
  
  if dungeon_data and dungeon_data.active and dungeon_data.original_character and dungeon_data.original_character.valid then
    target_character = dungeon_data.original_character
  end
  
  if not target_character or not target_character.valid then
    return false
  end
  
  local inserted = target_character.insert({name = 'coin', count = coin_count})
  return inserted > 0
end

local init_new_force = function()
    local new_force = game.forces.protectors
    local enemy = game.forces.enemy
    if not new_force then
        new_force = game.create_force('protectors')
    end
    new_force.set_friend('enemy', true)
    enemy.set_friend('protectors', true)
end

local init_qiche_force = function()
    local qiche = game.forces.qiche
    if not qiche then
        qiche = game.create_force('qiche')
    end
    -- 与玩家阵营互为友好
    qiche.set_friend('player', true)
    game.forces.player.set_friend('qiche', true)
    -- 与enemy阵营也保持友好（不参与战斗）
    qiche.set_friend('enemy', true)
    game.forces.enemy.set_friend('qiche', true)
    -- 与protectors阵营互为友好
    if game.forces.protectors then
        qiche.set_friend('protectors', true)
        game.forces.protectors.set_friend('qiche', true)
    end
    -- 给所有配方设置25%产能加成
    for recipe_name, recipe in pairs(qiche.recipes) do
        recipe.productivity_bonus = 0.25
    end
end

local setting = function()
    game.forces.enemy.create_ghost_on_entity_death = true
    --game.map_settings.ghost_time_to_live = 5 * 60 * 60
    -- game.map_settings.enemy_evolution.destroy_factor = 0.002
    game.forces.enemy.technologies['construction-robotics'].researched = true
    game.forces.enemy.technologies['laser-shooting-speed-1'].researched = true
    game.forces.enemy.technologies['laser-shooting-speed-2'].researched = true
    game.forces.enemy.technologies['laser-shooting-speed-3'].researched = true
    game.forces.enemy.technologies['laser-shooting-speed-4'].researched = true
    game.forces.enemy.technologies['laser-shooting-speed-5'].researched = true
    game.forces.enemy.technologies['laser-shooting-speed-6'].researched = true

    game.forces.enemy.friendly_fire = false
    game.forces.enemy.worker_robots_speed_modifier = 5
    game.forces.enemy.bulk_inserter_capacity_bonus = 100
    game.map_settings.enemy_expansion.enabled = true

    game.map_settings.enemy_expansion.max_expansion_cooldown = 60 * 60 * 30
    game.map_settings.enemy_expansion.min_expansion_cooldown = 60 * 60 * 5
    game.map_settings.enemy_expansion.max_expansion_distance = 20
    game.map_settings.enemy_expansion.settler_group_min_size = 5
    game.map_settings.enemy_expansion.settler_group_max_size = 50
    --  game.forces.player.set_ammo_damage_modifier("artillery-shell", 0)
    game.forces.player.set_ammo_damage_modifier("melee", 0)
      game.forces.player.set_ammo_damage_modifier("biological", 0)
     game.forces.player.set_ammo_damage_modifier("rocket", 0)

end
local function unlock_planet_technologies(planet_list)
    for _, planet_name in ipairs(planet_list) do
        game.forces.player.technologies['planet-discovery-' .. planet_name].researched = true
    end
end

local function create_planet_surface(planet_name, active_surface_index, ziyuan, world_number)
    if game.planets[planet_name] and not game.surfaces[planet_name] then
        -- 使用 table.deepcopy 以免修改原始原型数据
        -- 世界14：草星使用地球（nauvis）地形
        local base_planet = planet_name
        if world_number == 14 and planet_name == "gleba" and game.planets["nauvis"] then
            base_planet = "nauvis"
        end
        local map_gen_settings = table.deepcopy(game.planets[base_planet].prototype.map_gen_settings)
        map_gen_settings.seed = game.surfaces[active_surface_index].map_gen_settings.seed
        
        -- 定义各星球的特色资源列表
        local planet_specials = {
            ["vulcanus"] = {"tungsten-ore", "calcite", "sulfuric-acid-geyser"},
            ["fulgora"] = {"scrap"},
            ["gleba"] = {"yumako-tree", "jellynut-tree"},
            ["aquilo"] = {"lithium-ore", "fluorite-ore"}
        }

        -- 先应用你传入的基础资源配置 (ziyuan)
        if ziyuan then
            for name, settings in pairs(ziyuan) do
                -- 初始化该资源的控制项（如果不存在）
                map_gen_settings.autoplace_controls[name] = settings
            end
        end

        -- 只有世界7和8才会翻倍资源
        if world_number == 7 or world_number == 8 or world_number == 13 then
                  -- 3. 针对当前星球，将特色资源的频率设为 2 倍
        local specials = planet_specials[planet_name]
        if specials then
            for _, res_name in ipairs(specials) do
                -- 获取基础频率（如果 ziyuan 里没写，则默认为 1.0）
                local base_freq = 1.0
                if ziyuan[res_name] and ziyuan[res_name].frequency then
                    base_freq = tonumber(ziyuan[res_name].frequency) or 1.0
                end

                -- 设置特色资源控制：频率翻倍，尺寸和丰富度给个比较舒服的默认值
                map_gen_settings.autoplace_controls[res_name] = {
                    frequency = tostring(base_freq * 2), -- 翻倍并转回字符串
                    size = "1.2",                       -- 稍微调大一点特色矿物的覆盖范围
                    richness = "1.2"                    -- 稍微调高一点特色矿物的丰富度
                }
            end
        end

        -- 4. 特殊处理：如果你希望 Gleba 的虫子也多一点（对应你表里的 gleba_enemy_base）
        if planet_name == "gleba" and ziyuan["gleba_enemy_base"] then
            local freq = tonumber(ziyuan["gleba_enemy_base"].frequency) or 1
            map_gen_settings.autoplace_controls["gleba_enemy_base"].frequency = tostring(freq * 1.5)
        end
        end

        game.create_surface(planet_name, map_gen_settings)
        return true
    end
    return false
end

local function create_ore(surface, position)
    local ores = {'iron-ore', 'copper-ore', 'stone', 'coal'}
    local dist = 5
    local amount_multiplier = 2
    local directions = {{1, 1}, {-1, 1}, {1, -1}, {-1, -1}}

    for quadrant, dir in ipairs(directions) do
        for a = 1, 40 do
            for b = 1, 40 do
                local p = {
                    position.x + (a + dist) * dir[1],
                    position.y + (b + dist) * dir[2]
                }
                surface.create_entity({
                    name = ores[quadrant],
                    position = p,
                    amount = 250 * amount_multiplier
                })
            end
        end
    end
end
local function create_water(surface, position)
    for i = 1, 3 do
        for b = 1, 3 do
            local p = {
                x = position.x - b + 2,
                y = position.y - i - 2
            }
            if surface.can_place_entity {
                name = "steel-chest",
                position = p
            } then
                surface.set_tiles({{
                    name = "water",
                    position = p
                }})
            end
        end
    end
    local entities = surface.find_entities_filtered {
        position = {
            x = position.x,
            y = position.y + 4
        },
        name = "crude-oil",
        radius = 25
    }
    if #entities == 0 then
        surface.create_entity({
            name = "crude-oil",
            position = {
                x = position.x,
                y = position.y + 4
            }
        })
    end

end
local function apply_ammo_damage_modifiers(world_number)
    -- 旧 ammo_configs 表保留作为 fallback（未迁移到框架的世界仍走这里）
    local ammo_configs = {
        [7] = {
            ['grenade'] = -0.5,
             ['landmine'] = -0.5,
            ['flamethrower'] = -0.6,
            ['artillery-shell'] = -0.5
        },
        [13] = {
            ['grenade'] = -0.5,
             ['landmine'] = -0.5,
            ['flamethrower'] = -0.6,
            ['artillery-shell'] = -0.5
        },
        [9] = {
            ['grenade'] = -0.75,
            ['landmine'] = -0.75,
            ['flamethrower'] = -0.8,
            ['artillery-shell'] = -0.9
        },
        [11] = {
            ['grenade'] = -0.75,
             ['landmine'] = -0.75,
             ['artillery-shell'] = -0.9
        },
        [12] = {
            ['grenade'] = -0.75,
             ['landmine'] = -0.75,
             ['artillery-shell'] = -0.9
        }
    }

    -- World 框架优先，fallback 到 ammo_configs 旧表
    local config = World.get_field(world_number, 'ammo_damage_modifiers') or ammo_configs[world_number]
    if config then
        for ammo_type, modifier in pairs(config) do
            game.forces.player.set_ammo_damage_modifier(ammo_type, modifier)
        end
    end
end

local function apply_enemy_expansion_settings(world_number)
    -- 旧 expansion_configs 表保留作为 fallback
    local expansion_configs = {
        [6] = {
            max_expansion_cooldown = 60 * 60 * 10,
            min_expansion_cooldown = 60 * 60 * 5,
            max_expansion_distance = 20,
            settler_group_min_size = 5,
            settler_group_max_size = 100
        },
        [8] = {
            max_expansion_cooldown = 60 * 60 * 60 * 60,
            min_expansion_cooldown = 60 * 60 * 60 * 60
        }
    }

    -- World 框架优先，fallback 到 expansion_configs 旧表
    local config = World.get_field(world_number, 'enemy_expansion') or expansion_configs[world_number]
    if config then
        for setting_name, value in pairs(config) do
            game.map_settings.enemy_expansion[setting_name] = value
        end
    end
end

local function apply_planet_surface_settings(world_number, active_surface_index)
    -- 旧 planet_configs 表保留作为 fallback
    local planet_configs = {
        [2] = {
            planets = {'vulcanus', 'fulgora', 'gleba'},
            unlock_technologies = true
        },
        [7] = {
            planets = {'vulcanus', 'fulgora', 'gleba'},
            unlock_technologies = true
        },
        [13] = {
            planets = {'vulcanus', 'fulgora', 'gleba'},
            unlock_technologies = true
        },
        [14] = {
            planets = {'gleba'},
            unlock_technologies = true
        },
        [8] = {
            planets = {'vulcanus', 'fulgora', 'gleba', 'aquilo'},
            unlock_technologies = true,
            special_aquilo = true
        }
    }

    -- World 框架优先：把框架的 planet_surfaces（list）+ unlock_planet_technologies 转成旧 config 格式
    local world_def = World.get(world_number)
    local config
    if world_def and world_def.planet_surfaces then
        config = {
            planets = world_def.planet_surfaces,
            unlock_technologies = world_def.unlock_planet_technologies ~= false  -- 默认 true
        }
    else
        config = planet_configs[world_number]
    end

    if not config then
        return
    end

    if config.unlock_technologies then
        unlock_planet_technologies(config.planets)
    end

        if world_number == 14 and game.surfaces["gleba"] and game.planets["nauvis"] then
        local nauvis_settings = table.deepcopy(game.planets["nauvis"].prototype.map_gen_settings)
        nauvis_settings.seed = game.surfaces[active_surface_index].map_gen_settings.seed
        game.surfaces["gleba"].map_gen_settings = nauvis_settings
    end
end

local function apply_technology_settings(world_number)
    -- 所有世界开局默认解锁悬崖炸药科技
    game.forces.player.technologies['cliff-explosives'].researched = true

    -- World 框架优先
    local world_def = World.get(world_number)

    -- 1. 解锁科技列表（researched=true）
    local tech_list = world_def and world_def.unlocked_technologies
    if not tech_list then
        -- fallback：旧 if/elseif 分支
        if world_number == 12 then
            tech_list = {'steam-power', 'electronics', 'automation-science-pack', 'oil-processing', 'landfill'}
        elseif world_number == 14 then
            tech_list = {'rocket-silo'}
        elseif world_number == 13 then
            tech_list = {'elevated-rail', 'uranium-processing', 'recycling'}
        else
            tech_list = {}
        end
    end
    for _, tech_name in ipairs(tech_list) do
        local tech = game.forces.player.technologies[tech_name]
        if tech then
            tech.researched = true
        end
    end

    -- 2. 启用填海科技（enabled=true）
    local landfill_allowed = world_def and world_def.landfill_allowed
    if landfill_allowed == nil then
        -- fallback：旧 landfill_worlds 列表（含 14，原代码在 elseif 分支单独处理）
        local landfill_worlds = {3, 7, 8, 9, 13, 14}
        for _, world in ipairs(landfill_worlds) do
            if world_number == world then
                landfill_allowed = true
                break
            end
        end
    end
    if landfill_allowed then
        local landfill_tech = game.forces.player.technologies['landfill']
        if landfill_tech then
            landfill_tech.enabled = true
        end
    end
end

function Public.reset_map()

    local this = WPT.get()
    local wave_defense_table = WD.get_table()
    local world_number = diff.get("world")


    if this.yiciyuan_surface and this.yiciyuan_surface.valid then
        game.delete_surface(this.yiciyuan_surface.name)
        this.yiciyuan_surface = nil
    end
   -- if not this.first_time then
    --    this.first_time = true
     --   this.active_surface_index = game.surfaces['nauvis'].index
    --else
        this.active_surface_index = CS.create_surface()
  --  end
    

    if world_number == 8 or world_number == 7 or world_number == 13 then
        this.yiciyuan_surface = CS.create_yiciyuan_surface()
        local e3 = this.yiciyuan_surface.create_entity({
            name = 'linked-chest',
            position = {
                x = 0,
                y = 0
            },
            force = 'player',
            create_build_effect_smoke = false
        })
        e3.destructible = false
        e3.minable_flag = false
        -- 在世界8的异次元表面创建不可被挖掘不可被破坏的蓄电池
        if world_number == 8 or world_number == 7 or world_number == 13 then
            local position = {
                x = 0,
                y = 0
            }
            local surface = this.yiciyuan_surface
            create_ore(surface, position)
            create_water(surface, position)
        end
    end

    Autostash.insert_into_furnace(true)
    Autostash.bottom_button(true)

    BottomFrame.reset()
    BottomFrame.activate_custom_buttons(true)

    reset_pos()
    game.reset_time_played()
    WPT.reset_table()
    arty.reset_table()

    RPG.rpg_reset_all_players()
    RPG.set_surface_name(game.surfaces[this.active_surface_index].name)
    RPG.enable_health_and_mana_bars(true)
    RPG.enable_wave_defense(false)
    RPG.enable_mana(true)
    RPG.enable_flame_boots(true)
    RPG.personal_tax_rate(0.5)
    RPG.enable_stone_path(true)
    RPG.enable_one_punch(true)
    RPG.enable_one_punch_globally(false)
    RPG.enable_auto_allocate(true)
    RPG.disable_cooldowns_on_spells()
    RPG.enable_explosive_bullets_globally(true)
    RPG.enable_explosive_bullets(true)

    local Diff = Difficulty.get()
    Difficulty.reset_difficulty_poll({
        difficulty_poll_closing_timeout = game.tick + 36000
    })
    Diff.gui_width = 20

    local surface = game.surfaces[this.active_surface_index]
    game.forces.player.set_spawn_position({0, 0}, surface)

    PL.show_roles_in_list(true)
    PL.rpg_enabled(true)

    local players = game.connected_players
    for i = 1, #players do
        local player = players[i]
        player.force = game.forces.player
        Modifiers.reset_player_modifiers(player)
        ICMinimap.kill_minimap(player)
    end
   

    WD.reset_wave_defense()

    wave_defense_table.surface_index = this.active_surface_index
    wave_defense_table.nest_building_density = 32
    wave_defense_table.game_lost = false

    WD.alert_boss_wave(true)
    WD.clear_corpses(false)
    WD.remove_entities(true)
    WD.enable_threat_log(false)
    WD.increase_damage_per_wave(false)
    WD.increase_health_per_wave(false)
    WD.increase_boss_health_per_wave(false)
    WD.set_disable_threat_below_zero(true)

    if world_number == 6 then
        this.jjc = 2
    end
    this.world_number = world_number
    WD.set().next_wave = game.tick + World.get_field(world_number, 'time_limit')
    
    apply_ammo_damage_modifiers(world_number)
    apply_enemy_expansion_settings(world_number)
    apply_planet_surface_settings(world_number, this.active_surface_index)
    apply_technology_settings(world_number)
    
    WorldTable.reset_table()
    tianfu.reset_table()
    pet_system.reset_table()
    PseudoBuilding.reset_table()

    Balance.init_enemy_weapon_damage()
    Functions.disable_tech()

    Collapse.set_kill_entities(false)
    Collapse.set_kill_specific_entities(collapse_kill)
    Collapse.set_speed(8)
    Collapse.set_amount(1)
    Collapse.set_max_line_size(540, true)
    Collapse.set_surface(surface)

    Collapse.start_now(false)

    Collapse.set_position({0, 101})
    Collapse.set_direction('north')
    
    setting()
    init_qiche_force()
    
    if world_number == 6 then
        game.difficulty_settings.technology_price_multiplier = 1
    else
        game.difficulty_settings.technology_price_multiplier = 1
    end

    this.allow_deconst_list["tree"] = true
    this.allow_deconst_list["simple-entity"] = true

    IC.reset()
    IC.allowed_surface(game.surfaces[this.active_surface_index].name)
    ICW.reset()
    ICW.allowed_surface(game.surfaces[this.active_surface_index].name)

      global.rocks_yield_ore_maximum_amount = 999
  global.rocks_yield_ore_base_amount = 100
  global.rocks_yield_ore_distance_modifier = 0.020
  global.watery_world_fishes = {}
  
game.forces.player.technologies['atomic-bomb'].enabled=false
game.forces.player.technologies['productivity-module-2'].enabled=false
game.forces.player.technologies['productivity-module-3'].enabled=false
-- 世界14仅开局解锁高级星岩处理(advanced-asteroid-processing)，由 world_14 def.unlocked_technologies 控制；
-- asteroid-reprocessing 仍留给玩家手动研究（非 14 世界照旧开局解锁全套）
if world_number ~= 14 then
  game.forces.player.technologies['advanced-asteroid-processing'].researched=true
  game.forces.player.technologies['asteroid-reprocessing'].researched=true
end
  -- 初始化WPT表中的捕鱼车数据
  for _, prototype in pairs(prototypes.entity) do
    if prototype.type == "fish" then
      table.insert(global.watery_world_fishes, prototype.name)
    end
  end


    if this.yiciyuan_surface and this.yiciyuan_surface.valid then
        this.yiciyuan_surface.ignore_surface_conditions = false
    end
    game.surfaces["nauvis"].ignore_surface_conditions = false

    diff.apply_world_bonuses()

    
end

local on_init = function()
    local map = diff.get()
    map.world = 1
    Public.reset_map()
    local tooltip = {
        [1] = ({'amap.easy'}),
        [2] = ({'amap.med'}),
        [3] = ({'amap.hard'})
    }
    Difficulty.set_tooltip(tooltip)

    -- local Diff = Difficulty.get()
    -- Diff.difficulties[1].name="宝宝模式-baby_mode"
    -- Diff.difficulties[2].name="简单模式_easy_mode"
    -- Diff.difficulties[3].name="团队合作_norml_mode"

    -- game.forces.player.research_queue_enabled = true -- 已在Factorio 2.0中移除
    local T = Map.Pop_info()
    T.localised_category = 'amap'
    T.main_caption_color = {
        r = 150/255,
        g = 150/255,
        b = 0
    }
    T.sub_caption_color = {
        r = 0,
        g = 150/255,
        b = 0
    }
end

local function no_point(player, k)

    local money = 1000 + 1000 * k
    local can_remove = false
    local player_coin = player.character.get_item_count('coin')
    if player_coin >= money then
        can_remove = true
    end
    if can_remove then
        player.print({'amap.nopoint', money})
        player.remove_item {
            name = 'coin',
            count = money
        }

    else
        local rpg_t = RPG.get('rpg_t')
        local get_xp = 100 + k * 50
        rpg_t[player.index].xp = rpg_t[player.index].xp - get_xp
        player.print({'amap.lost_xp', get_xp})
    end
end

local wheel = function(player, many)
    if not player.character or not player.character.valid then
        return
    end
    if many >= 500 then
        many = 500
    end
    local rpg_t = RPG.get('rpg_t')
    local q = math.random(1, 18)
    local k = math.floor(many / 100)
    local get_point = math.min(k * 5 + 5, 25)
    
    local wheel_results = {
        [18] = function()
            local get_xp = 100 + k * 50
            rpg_t[player.index].xp = rpg_t[player.index].xp - get_xp
            player.print({'amap.lost_xp', get_xp})
        end,
        [17] = function()
            if rpg_t[player.index].magicka < (get_point + 10) then
                no_point(player, k)
            else
                rpg_t[player.index].magicka = rpg_t[player.index].magicka - get_point
                player.print({'amap.nb16', get_point + 10})
            end
        end,
        [16] = function()
            if rpg_t[player.index].dexterity < (get_point + 10) then
                no_point(player, k)
            else
                rpg_t[player.index].dexterity = rpg_t[player.index].dexterity - get_point
                player.print({'amap.nb17', get_point})
            end
        end,
        [15] = function()
            if rpg_t[player.index].vitality < (get_point + 10) then
                no_point(player, k)
            else
                rpg_t[player.index].vitality = rpg_t[player.index].vitality - get_point
                player.print({'amap.nb18', get_point})
            end
        end,
        [14] = function()
            if rpg_t[player.index].strength < (get_point + 10) then
                no_point(player, k)
            else
                rpg_t[player.index].strength = rpg_t[player.index].strength - get_point
                player.print({'amap.nb15', get_point})
            end
        end,
        [13] = function()
            local luck = math.min(50 * k + 50, 400)
            Loot.cool(player.physical_surface, player.physical_surface
                .find_non_colliding_position("steel-chest", player.physical_position, 20, 1, true) or player.physical_position, 'steel-chest',
                luck)
            player.print({'amap.nb14', luck})
        end,
        [12] = function()
            local get_xp = 100 + k * 50
            rpg_t[player.index].xp = rpg_t[player.index].xp + get_xp
            player.print({'amap.nb12', get_xp})
        end,
        [11] = function()
            local amount = 10 + 10 * k
            player.insert {
                name = 'distractor-capsule',
                count = amount
            }
            player.print({'amap.nb11', amount})
        end,
        [10] = function()
            local amount = 100 + 100 * k
            player.insert {
                name = 'raw-fish',
                count = amount
            }
            player.print({'amap.nb10', amount})
        end,
        [9] = function()
            player.insert {
                name = 'raw-fish',
                count = 1
            }
            player.print({'amap.nb9'})
        end,
        [8] = function()
            rpg_t[player.index].strength = rpg_t[player.index].strength + get_point
            player.print({'amap.nb6', get_point})
        end,
        [7] = function()
            player.print({'amap.nb5', get_point})
            rpg_t[player.index].magicka = rpg_t[player.index].magicka + get_point
        end,
        [6] = function()
            player.print({'amap.nb4', get_point})
            rpg_t[player.index].dexterity = rpg_t[player.index].dexterity + get_point
        end,
        [5] = function()
            player.print({'amap.nb3', get_point})
            rpg_t[player.index].vitality = rpg_t[player.index].vitality + get_point
        end,
        [4] = function()
            player.print({'amap.nb2', get_point})
            rpg_t[player.index].points_left = rpg_t[player.index].points_left + get_point
        end,
        [3] = function()
            local money = 1000 + 1000 * k
            player.print({'amap.nbone', money})
            player.insert {
                name = 'coin',
                count = money
            }
        end,
        [2] = function()
            local money = 1000 + 1000 * k
            player.print({'amap.sorry', money})
            player.remove_item {
                name = 'coin',
                count = money
            }
        end,
        [1] = function()
            player.print({'amap.what'})
        end
    }
    
    if wheel_results[q] then
        wheel_results[q]()
    end
end

local ban_player = {
    ['SLIME_Z'] = true,
    ['Winnie_Bin'] = true,
    ['tianyuyu'] = true,
    ['aceshotter'] = true,
    ['Hangover-'] = true,
    ['noneofone'] = true,
    ['L292'] = true,
    ['Junkmin'] = true,
    ['s695922378'] = true,
    ['llw'] = true,
    ['LymBAOBEI'] = true,
    ['jiyang2017'] = true,
    ['MoonFairy-a'] = true,
    ['2351472480'] = true,
    ['fang-fang'] = true,

}

local wheel_destiny = function()
    local this = WPT.get()
    local last = this.last
    local wave_number = WD.get('wave_number')
    
    if last >= wave_number then
        return
    end
    
    if wave_number % 25 ~= 0 then
        return
    end
    
    this.last = wave_number
    game.print({'amap.roll'}, {
        r = 0.22,
        g = 0.88,
        b = 0.22
    })
    
    for _, player in pairs(game.connected_players) do
        if this.jjc == 2 then
            local rpg_t = RPG.get('rpg_t')
            player.insert({
                name = 'coin',
                count = 5000
            })
            rpg_t[player.index].xp = (rpg_t[player.index].xp or 0) + 200
            player.print({'amap.jjc_25_bonus'}, {r=255, g=215, b=0})
        end
        
        if not ban_player[player.name] and player.force.name == 'player' then
            wheel(player, wave_number)
        end
    end
end

local car_buff = function()
    local this = WPT.get()
    local rpg_t = RPG.get('rpg_t')

    -- World 框架钩子：处理世界专属的全局 car_buff 逻辑（出生点设置、放车提示等）
    local world_def = World.get(this.world_number)
    if world_def and world_def.on_car_buff then
        world_def.on_car_buff(this, rpg_t)
    end

    for _, player in pairs(game.connected_players) do
        local index = player.index

        -- 初始化汽车/火车等级和升级进度（世界13即使没车也需要初始化）
        if not this.qcdj[index] then
            this.qcdj[index] = 1
        end
        if not this.up_jijing_histroy[index] then
            this.up_jijing_histroy[index] = 0
        end

        -- 火车内部空间：在火车内部空间的玩家永远可以吃到加成
        local is_in_train_interior = false
        if player.vehicle and player.vehicle.valid then
            local vname = player.vehicle.name
            if vname == 'locomotive' or vname == 'cargo-wagon' then
                is_in_train_interior = true
            end
        end

        local has_qiche_ren = tianfu.is_learned(player, 'qiche_ren')
        local should_buff = false

        -- 检查玩家汽车光圈（汽车周围140格半径）
        if this.tank[index] and this.tank[index].valid then
            if this.tank[index].surface == player.physical_surface then
                local dist_squared = (player.physical_position.x - this.tank[index].position.x) ^ 2 +
                                             (player.physical_position.y - this.tank[index].position.y) ^ 2
                if dist_squared <= 140 * 140 then
                    should_buff = true
                end
            end
        end

        -- World 框架钩子：处理世界专属的玩家级 buff 逻辑（如世界 13 火车光圈）
        if world_def and world_def.on_car_buff_player and not should_buff then
            should_buff = world_def.on_car_buff_player(this, player, rpg_t)
        end

        -- 天赋"汽车人"和火车内部空间永远享受加成
        if has_qiche_ren or is_in_train_interior then
            should_buff = true
        end

        if should_buff then
            local xp = math.floor((2 + (this.qcdj[index] - 1) * 2) / 2)
            local coin = math.floor((10 + (this.qcdj[index] - 1) * 4) / 2)
            if xp < 1 then xp = 1 end
            if coin < 1 then coin = 1 end
            rpg_t[player.index].xp = rpg_t[player.index].xp + xp
            insert_coin_to_player(player, coin)
            this.up_jijing_histroy[index] = this.up_jijing_histroy[index] + 10
            if this.up_jijing_histroy[index] >= 1800 then
                this.up_jijing_histroy[index] = 0
                player.print({'amap.qcdj_up', this.qcdj[index], xp + 1*2, coin + 2*2})
                this.qcdj[index] = this.qcdj[index] + 1
                if this.car_level_text[index] and this.car_level_text[index].valid then
                    this.car_level_text[index].text = 'LV' .. tostring(this.qcdj[index])
                end
            end
        end
    end
end

local gain_xp = function()
    local this = WPT.get()
    local wave_number = WD.get('wave_number')
    if wave_number <= this.number then
        return
    end

    local rpg_t = RPG.get('rpg_t')
    local world_def = World.get(this.world_number)

    for _, player in pairs(game.connected_players) do
        -- 副本隔离：副本内玩家不获得主世界被动经验
        if player.surface and Instance.is_dungeon_surface(player.surface.name) then
            goto continue_gain_xp
        end

        -- World 框架钩子：处理世界专属的玩家级 gain_xp 逻辑（baolei_y 跟踪、max_pos 跟踪等）
        if world_def and world_def.on_gain_xp then
            world_def.on_gain_xp(this, player, wave_number)
        end

        rpg_t[player.index].xp = rpg_t[player.index].xp + 5

        ::continue_gain_xp::
    end

    this.number = wave_number

    -- World 框架钩子：处理世界专属的全局 gain_xp 逻辑（Collapse 启动、速度调整等）
    if world_def and world_def.on_gain_xp_global then
        world_def.on_gain_xp_global(this, wave_number)
    end
end

local function get_biter_point()
    local this = WPT.get()
    local wave_defense_table = WD.get_table()

    -- 噩梦萦绕天赋：检查是否有锁定的玩家目标
    if this.emengyingrao_locked_player and this.emengyingrao_lock_end_tick then
        if game.tick >= this.emengyingrao_lock_end_tick then
            -- 锁定时间已过，清除锁定
            this.emengyingrao_locked_player = nil
            this.emengyingrao_lock_end_tick = 0
        elseif this.emengyingrao_locked_player.valid then
            -- 使用锁定的玩家作为目标
            wave_defense_table.target = this.emengyingrao_locked_player
        else
            -- 锁定的玩家已失效，清除锁定
            this.emengyingrao_locked_player = nil
            this.emengyingrao_lock_end_tick = 0
        end
    end
    
    -- 更新循环计数器，在1-4之间循环
    this.roll = (this.roll % 4) + 1
    
    -- 应用世界特殊规则，计算生成方向
    local world_rule = World.get_field(this.world_number, 'biter_spawn_rule')
    
    -- 崩落线出生点模式：x=0固定，y跟随崩落线偏移（不依赖目标实体，先检测）
    if world_rule and world_rule.collapse_spawn then
        local collapse_pos = Collapse.get_position()
        local offset = world_rule.collapse_spawn_offset or -25
        local spawn_y = collapse_pos.y + offset
        
        -- 世界13：虫子离火车最远100米，超了就限制在火车后方100米
        if this.world_number == 13 then
            local target = wave_defense_table.target
            if target and target.valid then
                local gap = collapse_pos.y - target.position.y
                local max_behind = world_rule.train_max_behind_distance or 125
                if gap > max_behind then
                    spawn_y = target.position.y + max_behind
                end
            end
        end
        
        wave_defense_table.spawn_position = {
            x = 0,
            y = spawn_y
        }
        return
    end
    
    -- 世界框架：四路同时进攻（由 world 的 biter_spawn_rule.four_way 配置驱动）
    if world_rule and world_rule.four_way then
        local entity = wave_defense_table.target
        if not entity or not entity.valid then return end
        local offset_x = entity.position.x
        local offset_y = entity.position.y
        -- 四路同时生成位置表（下、右、上、左），距中心 200 tile，留足正方形边缓冲
        wave_defense_table.spawn_positions = {}
        for _, off in ipairs(world_rule.four_way) do
            table.insert(wave_defense_table.spawn_positions, {x = offset_x + off[1], y = offset_y + off[2]})
        end
        return
    end
    -- 世界框架：虫子固定从存活堡垒出生（biter_spawn_rule.from_fortress，世界16「平凡之日」）
    -- 每次随机挑一个存活堡垒（机器人平台有效）作为出生点；
    -- 无存活堡垒时不更新出生点（进攻本身由 wave_attack_settings.require_fortress 拦截，不会刷虫）
    if world_rule and world_rule.from_fortress then
        wave_defense_table.spawn_positions = nil
        local positions = arty.get_valid_fortress_positions()
        if #positions > 0 then
            local pos = positions[math.random(1, #positions)]
            wave_defense_table.spawn_position = {x = pos.x, y = pos.y}
        end
        return
    end

    -- 非四路世界清除残留的多位置数据
    wave_defense_table.spawn_positions = nil

    -- 检查目标有效性（collapse_spawn 不需要目标，因此放后面）
    local entity = wave_defense_table.target
    if not entity or not entity.valid then
        return
    end
    
    local position = entity.position
    local surface = entity.surface
    local juli = 30
    local k = this.roll
    
    if world_rule and world_rule.k_value then
        local k_value = world_rule.k_value
        if type(k_value) == "number" then
            -- 固定方向
            k = k_value
        elseif k_value == "silo_3_or_roll" then
            -- 有silo时用方向3，否则用循环值
            k = (this.silo and this.silo.valid) and 3 or this.roll
        elseif k_value == "silo_random_3_4_or_roll" then
            -- 有silo时随机方向3或4，否则用循环值
            k = (this.silo and this.silo.valid) and math.random(3, 4) or this.roll
        end
    end
    
    -- 方向偏移表 [x_offset, y_offset]
    local directions = {
        [1] = { juli,  juli},   -- 右下
        [2] = {-juli,  juli},   -- 左下  
        [3] = { juli, -juli},   -- 右上
        [4] = {-juli, -juli}    -- 左上
    }
    
    -- 计算初始位置
    local dir = directions[k] or directions[1]
    local temp_pos = {
        x = position.x + dir[1],
        y = position.y + dir[2]
    }
    
    -- 应用世界特殊位置调整（强制x坐标对齐目标）
    if world_rule then
        local force_align = world_rule.force_x_align
        if force_align == true then
            -- 始终强制对齐
            temp_pos.x = entity.position.x
        elseif force_align == "random_1_3_silo" and math.random(1, 3) == 1 and this.silo and this.silo.valid then
            -- 1/3概率强制对齐（需要silo存在）
            temp_pos.x = entity.position.x
        end
    end
    
    -- 世界7污染转移：当k=2或k=4且silo有效时，将整个地图的污染转移到silo位置
    if world_rule and world_rule.transfer_pollution and (k == 2 or k == 4) and this.silo and this.silo.valid then
        local pollution = surface.get_total_pollution()
        surface.clear_pollution()
        surface.pollute(this.silo.position, pollution)
    end
    
    -- 检查并调整位置避免玩家建筑
    local function has_player_buildings(pos)
        return surface.count_entities_filtered({
            position = pos,
            radius = juli,
            name = player_build,
            force = game.forces.player,
            limit = 1
        }) > 0
    end
    
    -- 沿原方向移动直到找到没有玩家建筑的位置
    while has_player_buildings(temp_pos) do
        -- 沿原方向继续移动
        temp_pos.x = temp_pos.x + dir[1]
        temp_pos.y = temp_pos.y + dir[2]
        
        -- 保持世界特殊规则（强制x坐标对齐）
        if world_rule then
            local force_align = world_rule.force_x_align
            if force_align == true then
                temp_pos.x = entity.position.x
            elseif force_align == "random_1_3_silo" and math.random(1, 3) == 1 and this.silo and this.silo.valid then
                temp_pos.x = entity.position.x
            end
        end
    end
    
    -- 特殊模式处理：竞技场模式需要检查位置是否可放置rocket-silo
    if this.jjc == 2 then
        local valid_position = surface.find_non_colliding_position('rocket-silo', temp_pos, 128, 1)
        if not valid_position then
            -- 位置无效，递归重试
            temp_pos = get_biter_point()
            wave_defense_table.spawn_position = temp_pos
            return
        end
    end
    
    -- 世界8边界处理：当目标超出边界时，重置生成位置为目标位置
    if world_rule and world_rule.boundary_limit and world_rule.boundary_action == "reset_to_target" then
        local limit = world_rule.boundary_limit
        if math.abs(position.x) >= limit or math.abs(position.y) >= limit then
            temp_pos = entity.position
        end
    end
    
    -- 设置生成位置
    wave_defense_table.spawn_position = temp_pos
    -- game.print('[gps=' .. temp_pos.x .. ',' .. temp_pos.y .. ',' .. surface.name .. ']')
end

local on_tick = function()
    local tick = game.tick
    local this = WPT.get()
    if tick % 60 == 0 then

        Factories.produce_assemblers()
        --  if this.start_game ==2 then
        wheel_destiny()
        gain_xp()
        -- end

        -- 定时检测玩家是否意外丢失角色，没有则创建（死亡复生/编辑器模式不干预）
        for _, player in pairs(game.connected_players) do
            if not player.character
                and player.controller_type ~= defines.controllers.editor
                and not player.ticks_to_respawn
            then
                player.set_controller({type = defines.controllers.god})
                player.create_character()
            end
        end
    end

    if tick % 600 == 0 then
        if this.enable_wild_factorio then
            Factories.check_activity()
        end
        get_biter_point()
        car_buff()
    end
    if tick % 54000 == 0 then
        -- if this.start_game~=2 then return end
        local wave_number = WD.get('wave_number')
        if wave_number < 1 then
            return
        end
        if this.enable_wild_factorio then
            Factories.jump_procedure()
        end
    end

    -- World 框架钩子：处理世界专属的 on_nth_tick 逻辑（如世界 14 每 30 秒自动填火箭进度）
    if tick % 1800 == 0 then
        local world_def = World.get(this.world_number)
        if world_def and world_def.on_tick then
            world_def.on_tick(this, tick)
        end
    end

    -- 史诗木箱投递：200 波后每半小时（108000 tick）随机选一名在线玩家
    -- 在其附近 24 米内随机位置投递一个史诗木箱（全局上限 5 个，由 spawn API 内部判定）
    if tick % 108000 == 0 then
        local wave_number = WD.get('wave_number')
        if wave_number >= 1 then
            local active_surface_index = this.active_surface_index
            local surface = game.surfaces[active_surface_index]
            if surface and surface.valid then
                -- 收集非挂机在线玩家（afk_time < 36000 = 10 分钟）
                local candidates = {}
                for _, p in pairs(game.connected_players) do
                    if p.afk_time < 36000
                        and p.character and p.character.valid
                        and p.physical_surface and p.physical_surface.index == active_surface_index
                    then
                        candidates[#candidates + 1] = p
                    end
                end
                if #candidates > 0 then
                    local target = candidates[math.random(#candidates)]
                    -- 在玩家附近 24 米内随机选位置（符合"作用范围上限 24 米"规则）
                    local angle = math.random() * 2 * math.pi
                    local dist = math.random(8, 24)  -- 8 ~ 24 米随机半径，避免太近压玩家
                    local pos = {
                        x = target.physical_position.x + math.cos(angle) * dist,
                        y = target.physical_position.y + math.sin(angle) * dist
                    }
                    local chest = Instance.spawn_epic_chest(surface, pos)
                    if chest then
                        game.print({'amap.epic_chest_delivered', target.name},
                                   {r = 0.84, g = 0.6, b = 0.2})
                    end
                end
            end
        end
    end

end



-- 区块生成事件监听函数
local function on_chunk_generated(event)
    local surface = event.surface
    local area = event.area
    local this = WPT.get()
    -- 只处理主地图 surface，忽略 IC/ICW 等内部空间 surface
    if this.active_surface_index and surface.index ~= this.active_surface_index then
        return
    end
     local wave_defense_table = WD.get_table()
        if this.silo and this.silo.valid then
            wave_defense_table.target = this.silo
        end
    -- 检查是否是坐标(0,0)的区块，且宝箱尚未创建
    if area.left_top.x == 0 and area.left_top.y == 0 and not this.treasure_chest_created then
        -- 在区块中心创建宝箱
        local e =surface.create_entity({
            name = 'steel-chest',
            position = {x = 0, y = 0},
            force = 'player'
        })
        -- 标记宝箱已创建
        rock.ft(surface, 0)
        --设置波防目标
       
        rock.market(surface)
       
        --清空全局经验池
        local rpg_extra = RPG.get('rpg_extra')
        if rpg_extra and rpg_extra.global_pool then
            rpg_extra.global_pool = 0
            RPG.set('rpg_extra', rpg_extra)
        end
        
        if e and e.valid then
            this.treasure_chest_created = true
        end
        e.destroy()
         this.more_biter = 0
    end
end

Event.on_init(on_init)
Event.add(defines.events.on_chunk_generated, on_chunk_generated)
Event.on_nth_tick(60, on_tick)


return Public
