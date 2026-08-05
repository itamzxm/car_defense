local Token = require 'utils.token'
local Task = require 'utils.task'
local Loot = require 'maps.amap.loot'
local Alert = require 'utils.alert'
local rpgtable = require 'modules.rpg.table'
local RPG_spee = require 'modules.rpg.core'
local functions = require 'maps.amap.functions'
local TPT = require 'maps.amap.tianfu_table'
local WPT = require 'maps.amap.table'
local BiterPets = require 'maps.amap.biter_pets'
local BiterClass = require 'maps.amap.biter_class'
local EntityCache = require 'maps.amap.entity_cache'
local BasicMarkets = require 'maps.amap.basic_markets'
local TianfuQuality = require 'maps.amap.tianfu_quality'
local PetSys = require 'modules.pet_system.table'
local Event = require 'utils.event'
local Public = {}

-- 品质系数表（Phase B 方案2）：核心数值 ≤10 用 LOW，>10 用 REG
local COEFF_LOW = {1, 1.2, 1.4, 1.6, 1.8}
local COEFF_REG = {1, 1.2, 1.4, 1.6, 1.8}
-- 成品类天赋：物品品质名（q_idx 1..5 → normal..legendary），用于 player.insert 的 quality 字段
local QUALITY_NAMES = {'normal', 'uncommon', 'rare', 'epic', 'legendary'}

local goal = {'unit', 'turret', 'unit-spawner','spider-leg','combat-robot','spider-unit'}

local function get_player_car_entity(player, q_idx)
    local this = WPT.get()
    local car_entity = this.tank[player.index]
    if car_entity and car_entity.valid then
        return car_entity
    end
    return false
end

local lowdowm_1 = Token.register(function(player)
    rpgtable.update_player_stats(player)
end)
local t = {

    ['small-biter'] = 1,
    ['small-spitter'] = 2,
    ['small-worm-turret'] = 32,
    ['medium-biter'] = 8,
    ['medium-spitter'] = 8,
    ['medium-worm-turret'] = 64,
    ['big-biter'] = 32,
    ['big-spitter'] = 32,
    ['big-worm-turret'] = 128,
    ['behemoth-biter'] = 128,
    ['behemoth-spitter'] = 128,
    ['behemoth-worm-turret'] = 256,
    ['biter-spawner'] = 320,
    ['spitter-spawner'] = 320
}

local ban_build_name = {
    ['gun-turret'] = true,
    ['flamethrower-turret'] = true,
    ['tank'] = true,
    ['car'] = true
}-- 无敌状态结束回调
local un_wudi = Token.register(function(player)
    if player and player.character.valid then
        player.character.destructible = true
    end
end)


local function get_total_crafting_time(item_name, depth, q_idx)
    local this=WPT.get()
    depth = depth or 0
    if depth > 10 then return 1 end
    
    if not this.time_cache then
        this.time_cache = {}
    end
    if this.time_cache[item_name] then
        return this.time_cache[item_name]
    end

    local recipe =prototypes.recipe[item_name]
    
    if not recipe then
        this.time_cache[item_name] = 1
        return 1
    end

    local total_time = recipe.energy
    
    local product_amount = 1
    for _, product in pairs(recipe.products) do
        if product.name == item_name then
            product_amount = product.amount or product.amount_min or 1
            break
        end
    end
    
    for _, ingredient in pairs(recipe.ingredients) do
        if ingredient.type == "item" then
            local sub_time = get_total_crafting_time(ingredient.name, depth + 1)
            total_time = total_time + (sub_time * ingredient.amount / product_amount)
        end
    end

    this.time_cache[item_name] = total_time
    return total_time
end

local function insert_item_to_player(player, item_name, count, q_idx)
    if not player or not player.valid then
        return false
    end
    
    if not item_name or not count or count <= 0 then
        return false
    end
    
    local item_prototype = prototypes.item[item_name]
    if not item_prototype then
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

    if item_name ~= 'coin' then
        local current_count = target_character.get_item_count(item_name)
        local stack_size = item_prototype.stack_size or 1
        local stack_count = math.floor(current_count / stack_size)
        
        if stack_count >= 3 then
            return false
        end
    end
    
    local insert_opts = {name = item_name, count = count,quality = q_idx or "normal"}

    if not target_character.can_insert(insert_opts) then
        return false
    end

    local inserted = target_character.insert(insert_opts)
    return inserted > 0
end

    -- 定义安全检查函数
    local function validate_ghost(ghost, item_name, q_idx)
        if ban_build_name[item_name] then
            return false
        end

        if ghost.quality and ghost.quality.name ~= "normal" then
            return false
        end

        local item_prototype = prototypes.item[item_name]
        if item_prototype and item_prototype.group and item_prototype.group.name == "other" then
            return false
        end

        local recipe_name = item_name
        local force_recipes = game.forces.player.recipes
        
        if force_recipes[recipe_name] then
            if not force_recipes[recipe_name].enabled then
                return false
            end
        end

        local time_cost = get_total_crafting_time(item_name)
        if time_cost > 6000 then
            return false 
        end

        return true, time_cost
    end

    local function create_damage_floating_text(target_entity, damage_amount, damage_type, player, q_idx)
    
    local color = {r = 1, g = 0.5, b = 0}
    
    local text_position = {
        x = target_entity.position.x,
        y = target_entity.position.y - 1.5
    }
    
    player.create_local_flying_text({
        text = tostring(math.floor(damage_amount)),
        position = text_position,
        color = color,
        time_to_live = 60,
        speed = 1.5
    })
end

local function deal_damage_with_floating_text(target_entity, player, damage_amount, damage_type, q_idx)
    if type(damage_amount) ~= 'number' or damage_amount <= 0 then
        return false
    end     
    local this=WPT.get()
    local damage_multiplier = this.damage_multiplier or 1
    local final_damage = math.floor(damage_amount * damage_multiplier)
    
    
    -- 艾露尼斯：周期性天赋伤害随品质翻1.5~3.5倍，每次消耗3条鱼
    if this.tianfu_enabled[player.index] and this.tianfu_enabled[player.index]['ailunisi'] == true then
        local aq = TianfuQuality.idx(player, 'ailunisi') or 1
        local dmg_mult = ({1.5, 2.0, 2.5, 3.0, 3.5})[aq]
        local fish_count = player.get_item_count('raw-fish')
        if fish_count >= 3 then
            player.remove_item({ name = 'raw-fish', count = 3 })
            final_damage = final_damage * dmg_mult
        end
    end
    
    damage_type = damage_type or 'explosion'
    create_damage_floating_text(target_entity, final_damage, damage_type, player)
    target_entity.damage(final_damage, 'player', damage_type, player.character)
 
    return true
end
local car_name = { 'car', 'tank', 'spidertron' }

local time_skills = {
    ['jiansheche'] = {
        name = jiansheche,
        time = 60 * 10
    },
    ['dianjiqiang'] = {
        name = dianjiqiang,
        time = 60  -- 1秒冷却（每秒触发一次）
    },
    ['wanlaotianlei'] = {
        name = wanlaotianlei,
        time = 60 * 45  -- 每45秒触发一次（被动自动触发）
    },
    ['dcrg'] = {
        name = dcrg,
        time = 60  -- 1秒冷却（每秒触发一次）
    },
    ['danmu_gongji'] = {
        name = danmu_gongji,
        time = 60 * 3  -- 3秒冷却
    },
    ['chongfengxianzhen'] = {
        name = chongfengxianzhen,
        time = 60 * 15  -- 15秒冷却
    },
     ['yanfayanjiuzhongxin'] = {
        name = yanfayanjiuzhongxin,
        time = 60 * 30  -- 30秒冷却
    },
    ['mlzq'] = {
        name = mlzq,
        time = 60 * 60
    },
    ['bujiwu'] = {
        name = bujiwu,
        time = 60 * 60
    },
    ['mzqz'] = {
        name = mzqz,
        time = 60 * 30
    },
    ['yjjn'] = {
        name = yjjn,
        time = 60 * 45
    },
    ['leitingwanjun'] = {
        name = leitingwanjun,
        time = 60 * 3  -- 每3秒触发一次
    },
    ['gcd'] = {
        name = gcd,
        time = 60 *60 * 30
    },
    ['cjs'] = {
        name = cjs,
        time = 60 * 60 * 3
    },
    ['beibaozhengli'] = {
        name = beibaozhengli,
        time = 60 * 2  -- 5秒冷却
    },
    ['wjjt'] = {
        name = wjjt,
        time = 60 * 135
    },
    ['kls'] = {
        name = kls,
        time = 60 * 60
    },
    ['whea'] = {
        name = whea,
        time = 60 * 5
    },
    ['kytd'] = {
        name = kytd,
        time = 60 * 60 * 10
    },
    ['zhrm'] = {
        name = zhrm,
        time = 60 * 60 * 10
    },
    ['scmcc'] = {
        name = scmcc,
        time = 60 * 60  -- 每1分钟触发一次
    },
    ['kejigongsi'] = {
        name = kejigongsi,
        time = 60 * 60  -- 每1分钟触发一次
    },
    ['mbz'] = {
        name = mbz,
        time = 60 * 60
    },
    ['tls'] = {
        name = tls,
        time = 60 * 45
    },
    ['zsfs'] = {
        name = zsfs,
        time = 60 * 60 * 10
    },
    ['djrc'] = {
        name = djrc,
        time = 60 * 60 * 60
    },
    ['pulu'] = {
        name = pulu,
        time = 60 * 60
    },
    ['dafs'] = {
        name = dafs,
        time = 60 * 10
    },
    ['ljss'] = {
        name = ljss,
        time = 60 * 12
    },
    ['mfxt'] = {
        name = mfxt,
        time = 60 * 60
    },
    ['ylsgd'] = {
        name = ylsgd,
        time = 60 * 3
    },
    ['fuzhushou'] = {
        name = fuzhushou,
        time = 60 * 3
    },
    ['tann'] = {
        name = tann,
        time = 60 * 60 * 10
    },
    ['rsrl'] = {
        name = rsrl,
        time = 60 * 5
    },
    ['xly'] = {
        name = xly,
        time = 60 * 60
    },
    ['tzzj'] = {
        name = tzzj,
        time = 60 * 60 * 10
    },

    ['hhc'] = {
        name = hhc,
        time = 60 * 7
    },
    ['jgq'] = {
        name = jgq,
        time = 60 * 10
    },

    ['xj'] = {
        name = xj,
        time = 60 * 3
    },
    ['smlw'] = {
        name = smlw,
        time = 60 * 60 * 30
    },
    ['jndd'] = {
        name = jndd,
        time = 60 * 60
    },
    ['ycj'] = {
        name = ycj,
        time = 60 * 60
    },

    ['qns'] = {
        name = qns,
        time = 60 * 3
    },
    ['falibiqu'] = {
        name = falibiqu,
        time = 60  -- 1秒冷却（每秒触发一次）
    },
    ['chuanqibaozang'] = {
        name = chuanqibaozang,
        time = 60*45   -- 30秒冷却
    },
    ['dl'] = {
        name = dl,
        time = 60 * 4
    },
    ['jifengbu'] = {
        name = jifengbu,
        time = 60 * 10  -- 10秒冷却
    },
    ['jxhx'] = {
        name = jxhx,
        time = 60
    },
    ['wlfs'] = {
        name = wlfs,
        time = 60 * 13
    },
    ['xxzb'] = {
        name = xxzb,
        time = 60
    },
    ['xuyiyiquan'] = {
        name = xuyiyiquan,
        time = 60 * 6  -- 6秒冷却
    },
    ['juemuren'] = {
        name = juemuren,
        time = 60 * 15
    },
    ['lg'] = {
        name = lg,
        time = 60 * 10
    },
    ['xxg'] = {
        name = xxg,
        time = 60 * 10
    },
    ['dgwd'] = {
        name = dgwd,
        time = 60 * 22
    },
    ['honzha'] = {
        name = honzha,
        time = 60 * 60
    },
    ['chifu'] = {
        name = chifu,
        time = 60
    },
    ['touqian'] = {
        name = touqian,
        time = 60 * 60
    },
    ['fatiao'] = {
        name = fatiao,
        time = 60 * 3
    },
    ['fkdda'] = {
        name = fkdda,
        time = 60 * 3
    },
    ['fkddb'] = {
        name = fkddb,
        time = 60 * 5
    },
    ['keyan'] = {
        name = keyan,
        time = 60 * 20
    },

    ['hmds'] = {
        name = hmds,
        time = 60 * 22
    },
    ['sglz'] = {
        name = sglz,
        time = 60 * 6
    },
    ['bpz'] = {
        name = bpz,
        time = 60 * 60
    },
    ['boom_player'] = {
        name = boom_player,
        time = 60 * 3
    },
    ['small_buss'] = {
        name = small_buss,
        time = 60 * 30
    },
    ['zrsc'] = {
        name = zrsc,
        time = 60 * 60
    },
    ['zhs'] = {
        name = zhs,
        time = 60 * 15
    },
    ['wolf'] = {
        name = wolf,
        time = 60 * 3
    },
    ['dutu'] = {
        name = dutu,
        time = 60 * 10 * 6
    },
    ['wxs'] = {
        name = wxs,
        time = 60 * 2
    },
    ['junhuo'] = {
        name = junhuo,
        time = 60 * 30
    },
    ['genben'] = {
        name = genben,
        time = 60 * 8
    },
    ['fish'] = {
        name = fish,
        time = 60 * 20
    },
    ['zdfs'] = {
        name = zdfs,
        time = 60 * 3
    },
    ['zdfs2'] = {
        name = zdfs2,
        time = 60 * 6
    },
    ['jingong'] = {
        name = jingong,
        time = 60 * 75
    },
    ['hd'] = {
        name = hd,
        time = 60 * 60 * 15
    },
    ['fali'] = {
        name = fali,
        time = 60 * 3
    },
    ['juqichengjian'] = {
        name = juqichengjian,
        time = 60
    },
    ['fumo'] = {
        name = fumo,
        time = 60 * 20  -- 30秒冷却
    },
    ['carxiu'] = {
        name = carxiu,
        time = 60 * 5
    },
    ['ftlt'] = {
        name = ftlt,
        time = 30 * 60
    },
    ['tdlx'] = {
        name = tdlx,
        time = 60 * 60
    },
    ['fangshou'] = {
        name = fangshou,
        time = 60 * 60
    },
    ['dianluban'] = {
        name = dianluban,
        time = 60 * 3
    },
    ['xueqiu'] = {
        name = xueqiu,
        time = 60 * 3
    },
    ['jiguang'] = {
        name = jiguang,
        time = 60 * 60 * 3
    },
    ['wudi'] = {
        name = wudi,
        time = 60 * 10
    },
    ['pailei'] = {
        name = pailei,
        time = 60 * 3
    },
    ['sansan'] = {
        name = sansan,
        time = 60*30
    },
    ['mlst'] = {
        name = mlst,
        time = 60 * 60 * 1
    },
    ['xxyd'] = {
        name = xxyd,
        time = 60 * 60 * 1
    },
    ['morefali'] = {
        name = morefali,
        time = 60 * 30
    },
    ['rlfdz'] = {
        name = rlfdz,
        time = 60 * 60 *45
    },
    ['yuer'] = {
        name = yuer,
        time = 60 * 10
    },
    

    ['shen_fa'] = {
        name = shen_fa,
        time = 60 * 10 -- 30秒冷却时间
    },
    ['diyu_rongyan'] = {
        name = diyu_rongyan,
        time = 60 * 10 -- 10秒冷却时间
    },
    ['lanhuangjiaonang'] = {
        name = lanhuangjiaonang,
        time = 60 * 15 -- 15秒冷却
    },
    ['zishenzhuanjia'] = {
        name = zishenzhuanjia,
        time = 60 * 30 -- 30秒冷却
    },
    ['daodaoku'] = {
        name = daodaoku,
        time = 60 * 30 -- 30秒冷却
    },
    ['weilai'] = {
        name = weilai,
        time = 60 * 120 -- 120秒冷却
    },
    ['jidiche'] = {
        name = jidiche,
        time = 60 * 10 -- 10秒冷却
    },
    ['hushenfu'] = {
        name = hushenfu,
        time = 60 * 10 -- 10秒冷却时间
    },
    ['zhuoshao'] = {
        name = zhuoshao,
        time = 60 * 10  -- 10秒冷却
    },
    ['tieshenhuwei'] = {
        name = tieshenhuwei,
        time = 60 * 22  -- 22秒冷却
    },
    ['shui_hu_fu'] = {
        name = shui_hu_fu,
        time = 60 * 30  -- 30秒冷却，用于充能恢复
    },
    ['shui_dun'] = {
        name = shui_dun,
        time = 60 * 10  -- 10秒冷却，周期性释放劣化版水龙弹
    },
    ['lengdongyubaoxianshu'] = {
        name = lengdongyubaoxianshu,
        time = 60 * 30  -- 30秒冷却
    },
    ['chaoshikongshangdian'] = {
        name = chaoshikongshangdian,
        time = 60*60*45  -- 每45分钟触发一次
    },
    ['gycs'] = {
        name = gycs,
        time = 60 * 60  -- 每1分钟触发一次
    },
    ['gongchengche'] = {
        name = gongchengche,
        time = 60 * 12  -- 10秒冷却
    },
    ['yelianche'] = {
        name = yelianche,
        time = 60 * 13  -- 10秒冷却
    },
    ['tianzhao'] = {
        name = tianzhao,
        time = 60*3  -- 3秒冷却
    },
    ['yuedui_gushou'] = {
        name = yuedui_gushou,
        time = 60 * 10  -- 10秒冷却
    },
    ['xunshoushi'] = {
        name = xunshoushi,
        time = 60 * 30  -- 每30秒触发一次
    },
    ['tesla_battery'] = {
        name = tesla_battery,
        time = 60 * 5  -- 每5秒触发一次
    },
    ['lidazhuanfei'] = {
        name = lidazhuanfei,
        time = 60 * 4  -- 每3秒触发一次
    },
    ['qiche_ren'] = {
        name = qiche_ren,
        time = 60 * 1  -- 1秒冷却
    },
    ['xuyiyiquan'] = {
        name = xuyiyiquan,
        time = 60 * 6  -- 6秒冷却
    },
    ['ailunisi'] = {
        name = ailunisi,
        time = 60 * 60  -- 被动天赋，在deal_damage_with_floating_text中触发
    },
    ['haiguanfang'] = {
        name = haiguanfang,
        time = 60 * 60  -- 每1分钟触发一次
    },
    ['emengyingrao'] = {
        name = emengyingrao,
        time = 60 * 60  -- 每1分钟触发一次
    },
    ['zhidanbing'] = {
        name = zhidanbing,
        time = 60  -- 每秒触发一次
    },
    ['guajichengsheng'] = {
        name = guajichengsheng,
        time = 60 * 60 -- 每分钟检测一次（挂机触发）
    },
    ['yuediaoyuerou'] = {
        name = yuediaoyuerou,
        time = 60 * 60 -- 每分钟触发一次
    },
    ['linghang'] = {
        name = linghang,
        time = 60 * 60 -- 每分钟触发一次
    },
    ['duoduoyishan'] = {
        name = duoduoyishan,
        time = 30 * 60 -- 每30秒触发一次
    },
    ['zidongfanmai'] = {
        name = zidongfanmai,
        time = 5 * 60 -- 每5秒检测一次（自动贩卖机）
    },
    ['huoliyu'] = {
        name = huoliyu,
        time = 60 * 60 -- 每1分钟触发一次
    },
    ['njbomb'] = {
        name = njbomb,
        time = 60 * 6 -- 每6秒触发一次（被动自动为友方虫子施加亡语）
    },
}


local function unstuck_player(index, q_idx)
    local player = game.get_player(index)
    if not player or not player.valid then
        return
    end
    if player.physical_surface.name ~= 'nauvis' then return end
    local is_stuck = false
    if not is_stuck then
        local surface = player.physical_surface
        local nearby_entities = surface.find_entities_filtered({
            area = { { player.physical_position.x - 1, player.physical_position.y - 1 }, { player.physical_position.x + 1, player.physical_position.y + 1 } },
            type = { 'tree', 'rock', 'simple-entity', 'unit', 'turret', 'unit-spawner' }
        })

        if #nearby_entities >= 4 then
            is_stuck = true
        end
    end
    if is_stuck then
        local surface = player.physical_surface
        local position = surface.find_non_colliding_position('character', player.physical_position, 16, 0.5)
        if position then
            player.teleport(position, surface)
        end
    end
end


local function new_print(player, text, q_idx)
    local this = WPT.get()
    local tick = game.tick
    local player_index = player.index

    if not this.print_cooldown then
        this.print_cooldown = {}
    end

    if this.print_cooldown[player_index] and tick - this.print_cooldown[player_index] < 30 then
        return
    end

    this.print_cooldown[player_index] = tick

    for _, target_player in pairs(game.connected_players) do
        if player.physical_surface == target_player.surface then
        target_player.create_local_flying_text{
            text = text,
            color = player.color,
            position = player.physical_position,
            speed = 0.8
    }
    end
    end
end

local function tame_unit_effects(player, entity, q_idx)
    rendering.draw_text {
        text = '~' .. player.name .. "'s pet~",
        surface = player.physical_surface,
        target = entity,
        target_offset = { 0, -2.6 },
        color = {
            r = player.color.r * 0.6 + 0.25,
            g = player.color.g * 0.6 + 0.25,
            b = player.color.b * 0.6 + 0.25,
            a = 1
        },
        scale = 1.05,
        font = 'default-large-semibold',
        alignment = 'center',
        scale_with_zoom = false
    }
end

-- 复用 rpg/spells.lua 的规范升级函数（Public.upgrade_spell）
-- 它已正确处理两种模式：阶段升级(need_list+upgrade_list) 与 连续升级(need_times+bonus+base)
-- 旧本地副本对连续升级技能会 pairs(nil) 崩溃（spell 无 need_list 时 need_upgrade_list=nil）
-- 同时也修正了旧副本忽略 up 参数导致 up=false 查询调用也被 +1 的隐藏 bug
local function upgrade_spell(player, object_entityName, print_name, up, q_idx)
    return RPG_spee.spells.upgrade_spell(player, object_entityName, up)
end
local jgq_work = Token.register(function(player)
    local entities = EntityCache.find_entities_cached(player.physical_surface, {
        position = player.physical_position,
        type = goal,
        radius = 16,
        force = game.forces.enemy,
        limit = 20
    })
    for i = 1, 5, 1 do
        if #entities ~= 0 and i <= #entities then
            local e = player.physical_surface.create_entity({
                name = 'laser',
                position = player.physical_position,
                force = 'player',
                source = player.character,
                target = entities[i],
                speed = 1,
                player = player
            })
        end
    end
end)
local kill_forces = Token.register(function(data)
    for _, v in pairs(data) do
        if v and v.valid then
            v.destroy()
        end
    end
end)

local juemuren_death_callback = Token.register(function(data)
    local unit = data.unit
    local player = data.player
    local damage = data.damage
    if unit and unit.valid then
        local position = unit.position
        unit.destroy()
        if player and player.valid and player.character and player.character.valid then
            local enemies = EntityCache.find_entities_cached(player.physical_surface, {
                position = position,
                radius = 7,
                type = goal
            })
            for _, enemy in pairs(enemies) do
                if enemy.valid then
                    deal_damage_with_floating_text(enemy, player, damage, 'explosion')
                end
            end
        end
    end
end)

local function splash_damage(surface, position, final_damage_amount, radius, no_firend_damage, player, q_idx)
    if not player or not player.character or not player.character.valid then
        return
    end
    
    local create = surface.create_entity
    local damage = final_damage_amount
    
    for _, e in pairs(EntityCache.find_entities_cached(surface, {
        position = position,
        radius = radius,
        type = goal,
        limit = 15
    })) do
        if e.valid and e.health and damage > 0 then
            local distance_from_center = ((e.position.x - position.x) ^ 2 + (e.position.y - position.y) ^ 2)
            local damage_distance_modifier = 1 - distance_from_center / radius / radius
            
            if (not no_firend_damage) or (no_firend_damage and e.force.name ~= 'player') then
                deal_damage_with_floating_text(e, player, damage * damage_distance_modifier, 'explosion')
            end
        end
    end
end

local fashe = Token.register(function(data)
    local biter = data.biter
    if biter and biter.valid and biter.health then
        if biter.health then
            local position = data.position
            local player = data.player
            local e = player.physical_surface.create_entity({
                name = 'explosive-rocket',
                position = player.physical_position,
                force = 'player',
                source = player.character,
                target = biter,
                speed = 1,
                player = player,
                quality = data.quality
            })
        end
    end
end)
local function attack(position, group, player, q_idx)
    local nearby_entities = EntityCache.find_entities_cached(player.surface, {
        position = position,
        radius = 20,
        type = goal,
        force = "enemy"
    })
    if #nearby_entities > 0 then
        local commands = {}
        commands[#commands + 1] = {
            type = defines.command.attack_area,
            destination = nearby_entities[1].position,
            radius = 16,
            distraction = defines.distraction.by_enemy
        }

        for i = 1, #nearby_entities, 1 do
            if nearby_entities[i].valid then
                commands[#commands + 1] = {
                    type = defines.command.attack,
                    target = nearby_entities[i],
                    distraction = defines.distraction.by_enemy
                }
            end
        end
        return true
    else
        return false
    end
end
-- 方案 C：桶调度接管冷却控制后，check_tick 退化为恒 true
-- 保留函数签名是为了避免修改 100+ 个 time_skill 函数中的 if check_tick(...) then 调用
-- AFK 检查、character 检查、冷却检查都由 on_tick 桶调度提前做了
-- 注：trigger_skill.lua 中的 check_tick 保持原样（事件驱动天赋不走桶调度）
local function check_tick(player, skill, die, q_idx)
    return true
end


local function jiansheche(player, q_idx)
    if check_tick(player, 'jiansheche') then
        local base_buildings = 12
        local rpg_t = rpgtable.get('rpg_t')
        local attribute_val = rpg_t[player.index].dexterity or 0 
        local extra_buildings = math.floor(attribute_val / (200 / COEFF_REG[q_idx or 1])) * 6
        local max_buildings = base_buildings + extra_buildings

        local count = 0
        local surface = player.physical_surface 

        local car = get_player_car_entity(player)
        
        if not car or not car.valid then
            return
        end

        local car_inv = car.get_inventory(defines.inventory.car_trunk)
        if not car_inv then return end

        local ghost_count = surface.count_entities_filtered({
            position = car.position,
            name = 'entity-ghost',
            radius = 20,
            force = game.forces.player
        })

        if ghost_count == 0 then
            return
        end

        local ghosts = surface.find_entities_filtered({
            position = car.position,
            name = 'entity-ghost',
            radius = 20,
            force = game.forces.player
        })

        for _, ghost in pairs(ghosts) do
            if count >= max_buildings then break end

            if ghost.valid then
                local ghost_name = ghost.ghost_name
                
                if not ban_build_name[ghost_name] then
                    local player_have = player.get_item_count(ghost_name)
                    local car_have = car_inv.get_item_count(ghost_name)
                    
                    local total_have = player_have + car_have
                    
                    if total_have > 0 then
                        if validate_ghost(ghost, ghost_name) then
                            local success, revived_entity = ghost.revive({raise_revive = true})
                            
                            if success then
                                local need = 1
                                if player_have > 0 then
                                    local removed = player.remove_item({name = ghost_name, count = 1})
                                    need = need - removed
                                end
                                
                                if need > 0 and car_have > 0 then
                                    car_inv.remove({name = ghost_name, count = need})
                                end
                                
                                count = count + 1
                            end
                        end
                    end
                end
            end
        end
    end
end

local function tzbd(player, q_idx)
    local index = upgrade_spell(player, "biter_special_forces", { 'spells.biter_special_forces' }, true)
    local main_table = WPT.get()
    if player.physical_surface ~= game.surfaces[main_table.active_surface_index] then
        return false
    end
    local biter_list = {
        ['1'] = 'small-biter',
        ['2'] = 'medium-biter',
        ['3'] = 'big-biter',
        ['4'] = 'behemoth-biter'
    }

    local spitter_list = {
        ['1'] = 'small-spitter',
        ['2'] = 'medium-spitter',
        ['3'] = 'big-spitter',
        ['4'] = 'behemoth-spitter'
    }

    local shachong_list = {

        ['1'] = 'small-worm-turret',
        ['2'] = 'medium-worm-turret',
        ['3'] = 'big-worm-turret',
        ['4'] = 'behemoth-worm-turret'
    }
    local surface = player.physical_surface
    local position = player.physical_position

    local biter_name = biter_list[index]
    local spitter_name = spitter_list[index]
    local shachong_name = shachong_list[index]

    local position = player.physical_surface.find_non_colliding_position(shachong_name, {
        x = position.x + math.random(-15, 15),
        y = position.y + math.random(-15, 15)
    }, 20, 1, true)
    if not position then
        return false
    end
    local shachong = surface.create_entity {
        name = shachong_name,
        position = position,
        force = game.forces.player
    }
    if not shachong then
        return
    end

    tame_unit_effects(player, shachong)
    local forces = {}
    forces[#forces + 1] = shachong
    local group = player.physical_surface.create_unit_group({
        position = player.physical_position,
        force = player.force
    })
    for i = 1, 3 do
        local biter = surface.create_entity {
            name = biter_name,
            position = player.physical_surface.find_non_colliding_position(biter_name, shachong.position, 20, 1, true),
            force = game.forces.player
        }
        biter.ai_settings.allow_try_return_to_spawner = false
        forces[#forces + 1] = biter
        tame_unit_effects(player, biter)

        group.add_member(biter)
    end
    for i = 1, 2 do
        local spitter = surface.create_entity {
            name = spitter_name,
            position = player.physical_surface.find_non_colliding_position(spitter_name, shachong.position, 20, 1, true),
            force = game.forces.player
        }
        spitter.ai_settings.allow_try_return_to_spawner = false
        forces[#forces + 1] = spitter
        tame_unit_effects(player, spitter)
        group.add_member(spitter)
    end
  --  unstuck_player(player.index)
    if attack(shachong.position, group, shachong) then
        Task.set_timeout_in_ticks(60 * 22, kill_forces, forces)
    else
      Task.set_timeout_in_ticks(60 * 22, kill_forces, forces)
    end
end

local function dianjiqiang(player, q_idx)
    if check_tick(player, 'dianjiqiang') then
        local rpg_t = rpgtable.get('rpg_t')
        local magic_power = rpg_t[player.index].magicka or 0

        local base_damage = 15

        local laser_damage_bonus = game.forces.player.get_ammo_damage_modifier("laser")+1
        local attack_speed_bonus = game.forces.player.get_gun_speed_modifier('laser') + 1


        local final_damage = base_damage * laser_damage_bonus * attack_speed_bonus * COEFF_REG[q_idx or 1]
        local repeat_times = 2 * (math.floor(magic_power / 300) + 1)

        local surface = player.physical_surface
        local enemies = EntityCache.find_entities_cached(surface, {
            position = player.physical_position,
            radius = 18,
            force = game.forces.enemy,
            type = goal
        })

        if #enemies > 0 then
            table.sort(enemies, function(a, b)
                local dist_a = (a and a.valid) and
                ((a.position.x - player.physical_position.x) ^ 2 + (a.position.y - player.physical_position.y) ^ 2) or math.huge
                local dist_b = (b and b.valid) and
                ((b.position.x - player.physical_position.x) ^ 2 + (b.position.y - player.physical_position.y) ^ 2) or math.huge
                return dist_a < dist_b
            end)

            local hit_count = 0

            for i = 1, repeat_times do
                if #enemies >= i then
                    local target = enemies[i]
                    if target.valid then
                        surface.create_entity({
                            name = 'electric-beam',
                            position = player.physical_position,
                            target = target.position,
                            source = player.physical_position,
                            duration = 10
                        })

                        deal_damage_with_floating_text(target, player, final_damage, 'laser')
                        hit_count = hit_count + 1
                    end
                end
            end
        end

        return true
    end
end

-- 万牢天雷引：每道伤害（每秒）结算函数（用 Token 注册，由 Task 每秒调度一次）
local wanlaotianlei_tick = Token.register(function(data)
    local player = game.get_player(data.player_index)
    if not player or not player.valid then
        return
    end
    if not player.character or not player.character.valid then
        return
    end
    local surface = player.physical_surface
    if not surface then
        return
    end

    local enemies = EntityCache.find_entities_cached(surface, {
        position = player.physical_position,
        radius = 20,
        force = game.forces.enemy,
        type = goal
    })

    if #enemies == 0 then
        return
    end

    -- 特效疏密控制：2.5 格网格分桶，已创建特效的格子及其 8 邻格内不再创建新特效
    -- 网格键格式 "gx,gy"，使用 floor(x/2.5) 作为格坐标
    local FX_GRID_SIZE = 2.5
    local fx_grid = {}

    -- 范围伤害：对 20 米内所有敌人造成伤害
    for i = 1, #enemies do
        local target = enemies[i]
        if target and target.valid then
            -- 伤害照常结算
            deal_damage_with_floating_text(target, player, data.damage, 'laser')

            -- 特效去重：检查自身格 + 周围 8 格是否已有特效
            local gx = math.floor(target.position.x / FX_GRID_SIZE)
            local gy = math.floor(target.position.y / FX_GRID_SIZE)
            local has_nearby_fx = false
            for dx = -1, 1 do
                for dy = -1, 1 do
                    if fx_grid[(gx + dx) .. ',' .. (gy + dy)] then
                        has_nearby_fx = true
                        break
                    end
                end
                if has_nearby_fx then break end
            end

            -- 无邻近特效则创建，并标记当前格
            if not has_nearby_fx then
                surface.create_entity({
                    name = 'lightning',
                    position = { x = target.position.x, y = target.position.y - 24 },
                    force = 'player',
                    source = player.character,
                    target = target,
                    speed = 1.0,
                    quality = QUALITY_NAMES[data.q_idx or 1]
                })
                fx_grid[gx .. ',' .. gy] = true
            end
        end
    end
end)

local function wanlaotianlei(player, q_idx)
    if not check_tick(player, 'wanlaotianlei') then
        return false
    end
    if not player or not player.valid or not player.character or not player.character.valid then
        return false
    end

    local rpg_t = rpgtable.get('rpg_t')
    local magicka = rpg_t[player.index].magicka or 0

    local base_damage = 20 + magicka
    local laser_damage_bonus = game.forces.player.get_ammo_damage_modifier("laser") + 1
    local attack_speed_bonus = game.forces.player.get_gun_speed_modifier('laser') + 1

    -- 每秒伤害 = 基础 × 激光加成 × 射速加成 × 品质系数
    -- 魔法伤害四项：激光伤害✓ 射速✓ 品质✓ 玩家魔力✓（已通过 base_damage = 20 + magicka 纳入）
    local per_tick_damage = base_damage * laser_damage_bonus * attack_speed_bonus * COEFF_REG[q_idx or 1]

    -- 持续时间：2秒 + 每400魔力+1秒
    local duration_seconds = 2 + math.floor(magicka / 400)
    local surface = player.physical_surface
    if not surface then
        return false
    end

    -- 每秒结算一次，从第0秒起，共 duration_seconds 次（每秒一次伤害）
    for s = 0, duration_seconds - 1 do
        Task.set_timeout_in_ticks(s * 60, wanlaotianlei_tick, {
            player_index = player.index,
            q_idx = q_idx or 1,
            damage = per_tick_damage
        })
    end

    new_print(player, { 'tianfu.wanlaotianlei_over' })
    return true
end

local function danmu_gongji(player, q_idx)
    if check_tick(player, 'danmu_gongji') then
        if not player or not player.valid or not player.character then
            return false
        end
        
        local surface = player.physical_surface
        
        local enemies = EntityCache.find_entities_cached(surface, {
            position = player.physical_position,
            radius = 30,
            force = game.forces.enemy,
            type = goal
        })
        
        if #enemies > 18 then
            local character = player.character
            local ammo_inventory = character.get_inventory(defines.inventory.character_main)
            
            local supported_ammo = {
                'firearm-magazine',
                'piercing-rounds-magazine',
                'uranium-rounds-magazine',
                'shotgun-shell',
                'piercing-shotgun-shell',
                'rocket',
                'explosive-rocket',
                'flamethrower-ammo',
                'cannon-shell',
                'explosive-cannon-shell',
                'uranium-cannon-shell',
                'explosive-uranium-cannon-shell',
                'artillery-shell',
                'grenade',
             --   'cluster-grenade'
            }
            
            local available_ammo = {}
            for _, ammo_name in pairs(supported_ammo) do
                local count = ammo_inventory.get_item_count(ammo_name)
                if count > 0 then
                    table.insert(available_ammo, {name = ammo_name, count = count})
                end
            end
            
            if #available_ammo > 0 then
                local throw_count = math.floor(8 * COEFF_LOW[q_idx or 1])
                
                local projectile_data = {
                    ['firearm-magazine'] = {name = 'shotgun-pellet', speed = 1},
                    ['piercing-rounds-magazine'] = {name = 'piercing-shotgun-pellet', speed = 1},
                    ['uranium-rounds-magazine'] = {name = 'piercing-shotgun-pellet', speed = 1},
                    ['shotgun-shell'] = {name = 'shotgun-pellet', speed = 1},
                    ['piercing-shotgun-shell'] = {name = 'piercing-shotgun-pellet', speed = 1},
                    ['rocket'] = {name = 'rocket', speed = 1},
                    ['explosive-rocket'] = {name = 'explosive-rocket', speed = 1},
                    ['flamethrower-ammo'] = {name = 'flamethrower-fire-stream', speed = 1},
                    ['cannon-shell'] = {name = 'cannon-projectile', speed = 1},
                    ['explosive-cannon-shell'] = {name = 'explosive-cannon-projectile', speed = 1},
                    ['uranium-cannon-shell'] = {name = 'uranium-cannon-projectile', speed = 1},
                    ['explosive-uranium-cannon-shell'] = {name = 'explosive-uranium-cannon-projectile', speed = 1},
                    ['artillery-shell'] = {name = 'artillery-projectile', speed = 1},
                    ['grenade'] = {name = 'grenade', speed = 1},
                    ['cluster-grenade'] = {name = 'cluster-grenade', speed = 1},
                    ['atomic-bomb'] = {name = 'atomic-rocket', speed = 1}
                }
                
                for i = 1, throw_count do
                    if #available_ammo == 0 then
                        break
                    end
                    
                    local random_index = math.random(1, #available_ammo)
                    local selected_ammo = available_ammo[random_index]
                    
                    if selected_ammo.count > 0 then
                        character.remove_item({name = selected_ammo.name, count = 1})
                        selected_ammo.count = selected_ammo.count - 1
                        
                        if selected_ammo.count == 0 then
                            table.remove(available_ammo, random_index)
                        end
                        
                        local target = enemies[math.random(1, #enemies)]
                        if target and target.valid then
                            local ammo_info = projectile_data[selected_ammo.name]
                            if ammo_info then
                                surface.create_entity({
                                    name = ammo_info.name,
                                    position = player.physical_position,
                                    force = player.force,
                                    source = character,
                                    target = target,
                                    speed = ammo_info.speed
                                })
                            end
                        end
                    end
                end
            end
        end
        
        return true
    end
end

local function chongfengxianzhen(player, q_idx)
    if check_tick(player, 'chongfengxianzhen') then
        local entities = EntityCache.find_entities_cached(player.physical_surface, {
            position = player.physical_position,
            radius = 12,
            force = game.forces.enemy,
            type = goal
        })

        if #entities >= 5 then
            local rpg_t = rpgtable.get('rpg_t')
            rpg_t[player.index].vitality = rpg_t[player.index].vitality + ({1, 1, 2, 2, 3})[q_idx or 1]
            new_print(player, { 'tianfu.chongfengxianzhen_over' })
        end
    end
    return true
end

local function zhidanbing(player, q_idx)
    if check_tick(player, 'zhidanbing') then
        if not player or not player.valid or not player.character or not player.character.valid then
            return false
        end

        local capsule_items = {
            'grenade',
            'cluster-grenade',
            'poison-capsule',
            'slowdown-capsule',
            'defender-capsule',
            'distractor-capsule',
            'destroyer-capsule'
        }

        local available_capsules = {}
        for _, capsule_name in pairs(capsule_items) do
            local count = player.character.get_item_count(capsule_name)
            if count > 0 then
                table.insert(available_capsules, {name = capsule_name, count = count})
            end
        end

        if #available_capsules == 0 then
            return false
        end

        local enemies = EntityCache.find_entities_cached(player.physical_surface, {
            position = player.physical_position,
            radius = 18,
            type = goal,
            force = 'enemy',
            limit = 16
        })

        if #enemies == 0 then
            return false
        end

        local selected_capsule = available_capsules[math.random(1, #available_capsules)]
        
        local target = enemies[math.random(1, #enemies)]

        player.physical_surface.create_entity({
            name = selected_capsule.name,
            source = player.character,
            position = player.physical_position,
            target = target,
            force = player.force,
            speed = 1,
            quality = QUALITY_NAMES[q_idx or 1]
        })

        player.remove_item({
            name = selected_capsule.name,
            count = 1,
            quality = 'normal'
        })


        return true
    end
    return true
end

local function yanfayanjiuzhongxin(player, q_idx)
    local this = TPT.get()
    
    local index = player.index
    if not check_tick(player, 'yanfayanjiuzhongxin') then
        return false
    end

    if not this.yanfa_count[index] then
        this.yanfa_count[index] = 0
    end

    local item_value_table = {
        ['heavy-armor'] = { value = 250, level = 1 },
        ['modular-armor'] = { value = 750, level = 2 },
        ['solar-panel-equipment'] = { value = 240, level = 2 },
        ['energy-shield-equipment'] = { value = 400, level = 2 },
        ['battery-equipment'] = { value = 160, level = 2 },
        ['power-armor'] = { value = 5000, level = 3 },
        ['exoskeleton-equipment'] = { value = 1000, level = 3 },
     
        ['energy-shield-mk2-equipment'] = { value = 4000, level = 4 },
        ['battery-mk2-equipment'] = { value = 5000, level = 4 },
        ['personal-laser-defense-equipment'] = { value = 4000, level = 4 },
        ['power-armor-mk2'] = { value = 35000, level = 5 },
        ['fission-reactor-equipment'] = { value = 9000, level = 5 }
    }

    local armor_level_map = {
        ['heavy-armor'] = 1,
        ['modular-armor'] = 2,
        ['power-armor'] = 3,
        ['power-armor-mk2'] = 5
    }

    local rpg_t = rpgtable.get('rpg_t')
    local dexterity = math.min(3000, rpg_t[index].dexterity or 0)

    this.yanfa_count[index] = dexterity + this.yanfa_count[index]
    
    local player_equipment_level = math.max(1, math.floor(dexterity / 100))

    local equipped_armor_name = nil
    local equipped_armor_level = 0
    
    local armor_inv = player.get_inventory(defines.inventory.character_armor)
    if armor_inv and armor_inv[1] and armor_inv[1].valid_for_read then
        equipped_armor_name = armor_inv[1].name
        if armor_level_map[equipped_armor_name] then
            equipped_armor_level = armor_level_map[equipped_armor_name]
        end
    end

    local available_items = {}
    for item_name, item_info in pairs(item_value_table) do
        local can_make = false
        if player_equipment_level == 1 then
            can_make = (item_info.level == 1 or item_info.level == 0)
        elseif player_equipment_level >= 2 and player_equipment_level < 5 then
            can_make = (item_info.level == player_equipment_level or item_info.level == player_equipment_level - 1)
        else
            can_make = (item_info.level == 4 or item_info.level == 5)
        end

        if can_make then
            table.insert(available_items, { name = item_name, info = item_info })
        end
    end

    for i = #available_items, 1, -1 do
        local item = available_items[i]
        local should_remove = false

        if item.name == equipped_armor_name then
            should_remove = true
        end

        if not should_remove then
        
            if player.character.get_item_count(item.name) >= 1 then
                
                should_remove = true
            end
        end

        if not should_remove and armor_level_map[item.name] then
            if equipped_armor_level == 5 then
                if armor_level_map[item.name] ~= 5 then
                    should_remove = true
                end
            else
                if armor_level_map[item.name] <= equipped_armor_level then
                    should_remove = true
                end
            end
        end

        if should_remove then
            table.remove(available_items, i)
        end
    end

    if #available_items > 0 then
        local selected = available_items[math.random(1, #available_items)]
        local selected_item = selected.name
        local item_info = selected.info

        if this.yanfa_count[index] >= item_info.value then
            local inserted = insert_item_to_player(player, selected_item, 1, QUALITY_NAMES[q_idx or 1])
            
            if inserted then
                this.yanfa_count[index] = this.yanfa_count[index] - item_info.value
                new_print(player, { 'tianfu.yanfayanjiuzhongxin_over', { 'item-name.' .. selected_item } })
            end
        end
    end

    return true
end

local function mlzq(player, q_idx)
    if not player.character or not player.character.valid then
        return false
    end
    local max = player.character.max_health
    local now = player.character.health
    if max == now then
        return false
    end
    local rpg_t = rpgtable.get('rpg_t')
    local mana_per_tick = RPG_spee.get_mana_modifier(player)
    rpg_t[player.index].mana = rpg_t[player.index].mana + mana_per_tick * COEFF_LOW[q_idx or 1]
    if rpg_t[player.index].mana >= rpg_t[player.index].mana_max then
        rpg_t[player.index].mana = rpg_t[player.index].mana_max
    end
end

local function bujiwu(player, q_idx)
    if check_tick(player, 'bujiwu') then
        local rpg_t = rpgtable.get('rpg_t')
        local players = game.connected_players
        local k = math.floor(rpg_t[player.index].dexterity / 150) + 1
        local coin = math.floor((#players - 1) * k * 5 * COEFF_REG[q_idx or 1])
        if coin >= 1500 then
            coin = 1500
        end
        if coin <= 0 then
            return false
        end
        insert_item_to_player(player, 'coin', coin)

        new_print(player, { 'tianfu.bujiwu_over', coin })
        return true
    end
end

local function mzqz(player, q_idx)
    if check_tick(player, 'mzqz') then
        local rpg_t = rpgtable.get('rpg_t')
        local k = rpg_t[player.index].level
        if k >= 300 then
            k = 300
        end
        rpg_t[player.index].mana = rpg_t[player.index].mana + 2 * k * COEFF_LOW[q_idx or 1]
        rpg_t[player.index].xp = rpg_t[player.index].xp + math.floor(0.5 * k * COEFF_LOW[q_idx or 1])
        if rpg_t[player.index].mana >= rpg_t[player.index].mana_max then
            rpg_t[player.index].mana = rpg_t[player.index].mana_max
        end

        new_print(player,{ 'tianfu.mzqz_over', math.floor(2 * k * COEFF_LOW[q_idx or 1]), math.floor(0.5 * k * COEFF_LOW[q_idx or 1]) })
        return true
    end
end

local function yjjn(player, q_idx)
    local this = TPT.get()
    local index = player.index
    if not this.yjjn_cn[index] then
        this.yjjn_cn[index] = 0
        this.yjjn_count[index] = 0
    end
    this.yjjn_count[index] = this.yjjn_count[index] + 1
    if this.yjjn_count[index] >= 60 then
        this.yjjn_count[index] = 0
        this.yjjn_cn[index] = this.yjjn_cn[index] + 1
        local times = upgrade_spell(player, "xiao_jingling", { 'xiao_jingling.ufo' }, true)
        if this.yjjn_cn[index] >= times then
            this.yjjn_cn[index] = times
        end
    end
    if check_tick(player, 'yjjn') and this.yjjn_cn[index] >= 1 then
        local biters = EntityCache.find_entities_cached(player.physical_surface, {
            position = player.physical_position,
            type = goal,
            radius = 13,
            force = "enemy",
            limit = 1
        })
        if #biters == 0 then
            return
        end
        this.yjjn_cn[index] = this.yjjn_cn[index] - 1
        local name = 'distractor-capsule'
        local position = player.physical_position
        local target = {
            x = position.x + math.random(-5, 5),
            y = position.y + math.random(-5, 5)
        }
        local e = player.physical_surface.create_entity({
            name = name,
            position = player.physical_position,
            force = 'player',
            source = player.character,
            target = target,
            speed = 0.8,
            player = player,
            last_user = player,
            quality = QUALITY_NAMES[q_idx or 1]

        })
        new_print(player, { 'tianfu.yjjn_over', this.yjjn_cn[index] })
        return true
    end
end

local function leitingwanjun(player, q_idx)
    if not check_tick(player, 'leitingwanjun') then
        return false
    end
    local this = TPT.get()
    local index = player.index
    local rpg_t = rpgtable.get('rpg_t')
    
    if not this.leitingwanjun_charges[index] then
        this.leitingwanjun_charges[index] = 1
        this.leitingwanjun_magic_bonus[index] = 0
    end
    
    local times = upgrade_spell(player, "leizhenyu", { 'spells.leizhenyu' }, false)
    
    local player_magic = rpg_t[index].magicka or 0
    local magic_bonus = math.floor(player_magic / 300)
    local max_charges = 12
    
    this.leitingwanjun_magic_bonus[index] = this.leitingwanjun_magic_bonus[index] + 1
    if this.leitingwanjun_magic_bonus[index] >= 5 then 
        this.leitingwanjun_magic_bonus[index] = 0
        if this.leitingwanjun_charges[index] < max_charges then
            this.leitingwanjun_charges[index] = this.leitingwanjun_charges[index] + 1+magic_bonus
            local times = upgrade_spell(player, "leizhenyu", { 'spells.leizhenyu' }, true)
        end
        if  this.leitingwanjun_charges[index]>max_charges then
            this.leitingwanjun_charges[index] = max_charges
        end
    end
    
    local damage = math.floor((20+math.floor(player_magic*0.4)+times) * COEFF_REG[q_idx or 1])
    
    if this.leitingwanjun_charges[index] <= 0 then
        return true
    end

    local nearby_enemies = EntityCache.find_entities_cached(player.physical_surface, {
        position = player.physical_position,
        type = goal,
        force = "enemy",
        radius = 16,
        limit = 1
    })

    if #nearby_enemies <= 0 then
        return true
    end

    local tesla_name = 'lightning'
    local target_entity = nearby_enemies[1]

    if target_entity and target_entity.valid then
        player.physical_surface.create_entity({
            name = tesla_name,
            position ={x = target_entity.position.x, y = target_entity.position.y - 24},
            force = 'player',
            source = player.character,
            target = target_entity,
            speed = 1.0,
            quality = QUALITY_NAMES[q_idx or 1]
        })

        local radius = 7
        local position = target_entity.position
        for _, e in pairs(EntityCache.find_entities_cached(target_entity.surface, {
            position = position,
            radius = radius,
            type = goal,
            force = 'enemy'
        })) do
            if e.valid and e.health and damage > 0 then
                local distance_from_center = math.sqrt((e.position.x - position.x) ^ 2 + (e.position.y - position.y) ^ 2)
                local damage_distance_modifier = 1 - distance_from_center / radius

                    deal_damage_with_floating_text(e, player, damage * damage_distance_modifier, 'electric')
            end
        end
        this.leitingwanjun_charges[index] = this.leitingwanjun_charges[index] - 1

        new_print(player, { 'tianfu.leitingwanjun_over', this.leitingwanjun_charges[index] })
        return true
    end

    return false
end

local tesla_battery_bounce_token2 = Token.register(function(data)
    local player = data.player
    local source = data.target
    local bounce_count = data.bounce_count
    local max_bounces = data.max_bounces
    local attacked_enemies = data.attacked_enemies
    
    if not player or not player.valid  then
        return
    end
    
    if bounce_count >= max_bounces then
        return
    end
    
        local nearby_enemies = EntityCache.find_entities_cached(player.physical_surface, {
        position = source,
        type = goal,
        force = "enemy",
        radius = 16,
    })
        
        local filtered_enemies = {}
        for _, enemy in pairs(nearby_enemies) do
            if enemy.valid and enemy.health > 0 then
                local is_attacked = false
                for _, attacked in pairs(attacked_enemies) do
                    if attacked == enemy then
                        is_attacked = true
                        break
                    end
                end
                if not is_attacked then
                    table.insert(filtered_enemies, enemy)
                end
            end
        end
        
        local num_targets = math.random(1, 3)
        local selected_enemies = {}
        
        for i = 1, num_targets do
            if #filtered_enemies == 0 then
                break
            end
            local random_index = math.random(1, #filtered_enemies)
            table.insert(selected_enemies, filtered_enemies[random_index])
            table.remove(filtered_enemies, random_index)
        end
        
        for _, enemy in pairs(selected_enemies) do
            if enemy.valid and enemy.health > 0 then
                player.physical_surface.create_entity({
                    name = 'chain-tesla-turret-beam-bounce',
                    position = source,
                    force = 'enemy',
                    source = source,
                    target = enemy.position,
                    speed = 1.0,
                    duration=15
                })

                
                player.physical_surface.create_entity({
                    name = 'chain-tesla-turret-beam-bounce',
                    position = source,
                    force = 'player',
                    source = source,
                    target = enemy,
                    speed = 1.0,
                    duration=15
                })
            end
        end
  
end)

local tesla_battery_bounce_token = Token.register(function(data)
    local player = data.player
    local source = data.target
    local bounce_count = data.bounce_count
    local max_bounces = data.max_bounces
    local attacked_enemies = data.attacked_enemies
    
    if not player or not player.valid  then
        return
    end
    
    if bounce_count >= max_bounces then
        return
    end
    
        local nearby_enemies = EntityCache.find_entities_cached(player.physical_surface, {
        position = source,
        type =goal,
        force = "enemy",
        radius = 16
    })
        
        local filtered_enemies = {}
        for _, enemy in pairs(nearby_enemies) do
            if enemy.valid and enemy.health > 0 then
                local is_attacked = false
                for _, attacked in pairs(attacked_enemies) do
                    if attacked == enemy then
                        is_attacked = true
                        break
                    end
                end
                if not is_attacked then
                    table.insert(filtered_enemies, enemy)
                end
            end
        end
        
        local num_targets = math.random(2, 4)
        local selected_enemies = {}
        
        for i = 1, num_targets do
            if #filtered_enemies == 0 then
                break
            end
            local random_index = math.random(1, #filtered_enemies)
            table.insert(selected_enemies, filtered_enemies[random_index])
            table.remove(filtered_enemies, random_index)
        end
        
        for _, enemy in pairs(selected_enemies) do
            if enemy.valid and enemy.health > 0 then
                table.insert(attacked_enemies, enemy)
                player.physical_surface.create_entity({
                    name = 'chain-tesla-turret-beam-bounce',
                    position = source,
                    force = 'enemy',
                    source = source,
                    target = enemy.position,
                    speed = 1.0,
                    duration=30
                })
                 player.physical_surface.create_entity({
                    name = 'chain-tesla-turret-beam-bounce',
                    position = source,
                    force = 'player',
                    source = source,
                    target = enemy,
                    speed = 1.0,
                    duration=30
                })
                
                Task.set_timeout_in_ticks(15, tesla_battery_bounce_token2, {
                player = player,
                player_index = data.player_index,
                target = enemy.position,
                bounce_count = bounce_count + 1,
                max_bounces = max_bounces,
                attacked_enemies = attacked_enemies
            })
            end
        end
  
end)

local function tesla_battery(player, q_idx)
    if not check_tick(player, 'tesla_battery') then
        return false
    end
    local this = TPT.get()
    local index = player.index
    local rpg_t = rpgtable.get('rpg_t')
    
    if not this.tesla_battery_charges[index] then
        this.tesla_battery_charges[index] = 1
        this.tesla_battery_charge_counter[index] = 0
    end
    
    local player_agility = rpg_t[index].dexterity or 0
    local max_charges = 12
    
    this.tesla_battery_charge_counter[index] = this.tesla_battery_charge_counter[index] + 1
    if this.tesla_battery_charge_counter[index] >= 6 then
        this.tesla_battery_charge_counter[index] = 0
        if this.tesla_battery_charges[index] < max_charges then
            this.tesla_battery_charges[index] = this.tesla_battery_charges[index] + 1
            new_print(player, {'tianfu.tesla_battery_charge', this.tesla_battery_charges[index]})
        end

        if this.tesla_battery_charges[index] >= max_charges then
            local gold_reward = math.min(math.floor(player_agility * 0.1 * COEFF_REG[q_idx or 1]), 300)
            if gold_reward > 0 then

                insert_item_to_player(player, 'coin', gold_reward)
                new_print(player, { 'tianfu.tesla_battery_gold', gold_reward })
            end
        end
    end
    if this.tesla_battery_charges[index] <= 0 then
        return true
    end

    local nearby_enemies = EntityCache.find_entities_cached(player.physical_surface, {
        position = player.physical_position,
        type = goal,
        force = "enemy",
        radius = 27
    })

    if #nearby_enemies <= 0 then
        return true
    end

    local num_targets = math.min(#nearby_enemies, math.random(3, 5))
    local selected_targets = {}
    for i = 1, num_targets do
        local random_index = math.random(1, #nearby_enemies)
        table.insert(selected_targets, nearby_enemies[random_index])
        table.remove(nearby_enemies, random_index)
    end

    for _, target_entity in ipairs(selected_targets) do
        if target_entity and target_entity.valid then
            this.tesla_battery_charges[index] = this.tesla_battery_charges[index] - 1
            new_print(player, { 'tianfu.tesla_battery_over', this.tesla_battery_charges[index] })
            
            local attacked_enemies = {}
            table.insert(attacked_enemies, target_entity)
            
            player.physical_surface.create_entity({
                name = 'chain-tesla-turret-beam-start',
                position = player.physical_position,
                force = 'enemy',
                source = player.character,
                target = target_entity.position,
                speed = 1.0,
                duration=45
            })

              player.physical_surface.create_entity({
                name = 'chain-tesla-turret-beam-start',
                position = player.physical_position,
                force = 'player',
                source = player.character,
                target = target_entity,
                speed = 1.0,
                duration=45
            })
            
            Task.set_timeout_in_ticks(15, tesla_battery_bounce_token, {
                player = player,
                player_index = index,
                target = target_entity.position,
                bounce_count = 0,
                max_bounces = 20,
                attacked_enemies = attacked_enemies
            })
        end
    end

    return true
end

local function gcd(player, q_idx)
    if check_tick(player, 'gcd') then
        insert_item_to_player(player, 'roboport', 1, QUALITY_NAMES[q_idx or 1])
        insert_item_to_player(player, 'construction-robot', 20, QUALITY_NAMES[q_idx or 1])
        insert_item_to_player(player, 'storage-chest', 1, QUALITY_NAMES[q_idx or 1])
        new_print(player, { 'tianfu.gcd_over' })
        return true
    end
end

local function cjs(player, q_idx)
    if check_tick(player, 'cjs') then
        local this = TPT.get()
        local rpg_t = rpgtable.get('rpg_t')
        local all_player = {}
        if this.qns_true then
            local players = game.connected_players
            for i = 1, #players do
                local player1 = players[i]
                rpg_t[player1.index].magicka = rpg_t[player1.index].magicka + math.floor(1 * COEFF_LOW[q_idx or 1] + 0.5)
                if player.name ~= player1.name then
                    new_print(player1, { 'tianfu.cjs_over3', player.name })
                else
                    new_print(player, { 'tianfu.cjs_over2', player.name })
                end
            end
        else
            local players = game.connected_players
            for i = 1, #players do
                local player1 = players[i]
                if player1.name ~= player.name then
                    all_player[#all_player + 1] = player1.index
                end
            end
            if #all_player == 0 then
                return false
            end

            local index = all_player[math.random(1, #all_player)]

            local player1 = game.players[index]
            rpg_t[player.index].xp = rpg_t[player.index].xp + math.floor(30 * COEFF_REG[q_idx or 1] + 0.5)
            rpg_t[player1.index].magicka = rpg_t[player1.index].magicka + math.floor(3 * COEFF_LOW[q_idx or 1] + 0.5)
            new_print(player, { 'tianfu.cjs_over', player1.name })
            new_print(player, { 'tianfu.cjs_over3', player.name })
        end

        return true
    end
end

local function wjjt(player, q_idx)
    if check_tick(player, 'wjjt') then
        local rpg_t = rpgtable.get('rpg_t')

        local a = math.floor(rpg_t[player.index].strength / 150) + 1
        if a >= 10 then
            a = 10
        end
        insert_item_to_player(player, 'destroyer-capsule', a, QUALITY_NAMES[q_idx or 1])
        new_print(player, { 'tianfu.wjjt_over', a })
        return true
    end
end

local function kls(player, q_idx)
    if check_tick(player, 'kls') then
        local rpg_t = rpgtable.get('rpg_t')
        local magicer = false
        if rpg_t[player.index].magicka > rpg_t[player.index].strength then
            if rpg_t[player.index].magicka > rpg_t[player.index].dexterity then
                if rpg_t[player.index].magicka > rpg_t[player.index].vitality then
                    magicer = true
                end
            end
        end

        if not magicer then
            return false
        end
        local players = game.connected_players
        local max = 0
        for i = 1, #players do
            local player1 = players[i]
            if rpg_t[player1.index].level > max then
                max = rpg_t[player1.index].level
            end
        end
        rpg_t[player.index].xp = rpg_t[player.index].xp + max * COEFF_REG[q_idx or 1]

        new_print(player, { 'tianfu.kls_over', max })
        return true
    end
end

local function whea(player, q_idx)
    if check_tick(player, 'whea') then
        local this = TPT.get()
        if not this.whea_count[player.name] then
            this.whea_count[player.name] = 0
        end

        local rpg_t = rpgtable.get('rpg_t')
        local times = math.floor(rpg_t[player.index].vitality / 100) + 1
        if times >= 25 then
            times = 25
        end

        local biters = player.physical_surface.find_entities_filtered({
            position = player.physical_position,
            type = {'unit', 'spider-unit'},
            radius = 7,
            force = "enemy",
            limit = times
        })

        if #biters == 0 then
            return
        end
        for _, v in pairs(biters) do
            if v and v.valid and v.max_health<=3000 then
                v.die()
            end
        end

        this.whea_count[player.name] = this.whea_count[player.name] + #biters
        if this.whea_count[player.name] >= 50 then
            this.whea_count[player.name] = this.whea_count[player.name] - 50

            rpg_t[player.index].vitality = rpg_t[player.index].vitality + TianfuQuality.qround(5 * COEFF_LOW[q_idx or 1])
        end
        new_print(player, { 'tianfu.whea_over', #biters })
    end
end

local function kytd(player, q_idx)
    if check_tick(player, 'kytd') then
        local players = game.connected_players
        local all_player = {}
        local max = 0
        local rpg_t = rpgtable.get('rpg_t')
        local k = 0
        for i = 1, #players do
            local player1 = players[i]
            if rpg_t[player1.index].dexterity > rpg_t[player1.index].strength then
                if rpg_t[player1.index].dexterity > rpg_t[player1.index].magicka then
                    if rpg_t[player1.index].dexterity > rpg_t[player1.index].vitality then
                        k = k + 1
                        all_player[#all_player + 1] = player1
                    end
                end
            end
        end

        if k >= 10 then
            k = 10
        end
        for i = 1, #all_player do
            local player1 = all_player[i]
            rpg_t[player1.index].dexterity = rpg_t[player1.index].dexterity + k * ({1, 1, 2, 2, 3})[q_idx or 1]
            if player1 ~= player then
                new_print(player1, { 'tianfu.kytd_over2', k })
            end
        end

        new_print(player, { 'tianfu.kytd_over', k })
        return true
    end
end

local function zhrm(player, q_idx)
    if check_tick(player, 'zhrm') then
        local rpg_t = rpgtable.get('rpg_t')
        rpg_t[player.index].xp = rpg_t[player.index].xp + math.floor(rpg_t[player.index].mana_max * 0.5) * COEFF_REG[q_idx or 1]
        return true
    end
end

local function scmcc(player, q_idx)
    if check_tick(player, 'scmcc') then
        local main_table = WPT.get()
        if main_table.tank[player.index] and main_table.tank[player.index].valid then
            local ores = { 'iron-ore', 'copper-ore', 'stone', 'coal' }
            local rpg_t = rpgtable.get('rpg_t')
            if not rpg_t[player.index] then
                return
            end

            local position = main_table.tank[player.index].position
            local surface = main_table.tank[player.index].surface

            if not main_table.scmcc_data then
                main_table.scmcc_data = {}
            end
            if not main_table.scmcc_data[player.index] then
                main_table.scmcc_data[player.index] = {
                    last_position = { x = position.x, y = position.y },
                    stay_start_tick = game.tick
                }
            end

            local player_data = main_table.scmcc_data[player.index]
            local last_pos = player_data.last_position

            local position_changed = math.abs(position.x - last_pos.x) > 0.1 or math.abs(position.y - last_pos.y) > 0.1

            if position_changed then
                player_data.last_position = { x = position.x, y = position.y }
                player_data.stay_start_tick = game.tick
            else
                local stay_duration = game.tick - player_data.stay_start_tick
                if stay_duration >= 7200 then
                    local dexterity = rpg_t[player.index].dexterity
                    local strength = rpg_t[player.index].strength

                    local base_value = math.min(math.max(dexterity, strength), 3000)

                    local amount = math.floor((math.floor(base_value / 64) + 1) * COEFF_REG[q_idx or 1])

                    local dist = 3
                    local abc = 1

                    local directions = {
                        { x_dir = 1, y_dir = 1, ore_index = 1 },
                        { x_dir = -1, y_dir = 1, ore_index = 2 },
                        { x_dir = 1, y_dir = -1, ore_index = 3 },
                        { x_dir = -1, y_dir = -1, ore_index = 4 }
                    }

                    for _, dir in pairs(directions) do
                        for a = 1, 20 do
                            for b = 1, 20 do
                                local p = {
                                    x = position.x + (dir.x_dir * a) + (dir.x_dir * dist),
                                    y = position.y + (dir.y_dir * b) + (dir.y_dir * dist)
                                }
                                local existing_entities = surface.find_entities_filtered({
                                    position = p,
                                    radius = 0.5,
                                    type = 'resource'
                                })

                                if #existing_entities > 0 then
                                    local existing_entity = existing_entities[1]

                                    if existing_entity.name == ores[dir.ore_index] then
                                        existing_entity.amount = existing_entity.amount + (amount * abc)
                                    end
                                else
                                    if surface.can_place_entity { name = ores[dir.ore_index], position = p } then
                                        surface.create_entity({
                                            name = ores[dir.ore_index],
                                            position = p,
                                            amount = amount * abc
                                        })
                                    end
                                end
                            end
                        end
                    end

                    new_print(player, { 'tianfu.scmcc_over', amount * abc * 1600 })
                    player_data.stay_start_tick = game.tick
                end
            end
        end
    end
    return true
end

local function mbz(player, q_idx)
    if check_tick(player, 'mbz') then
        local rpg_t = rpgtable.get('rpg_t')
        rpg_t[player.index].dexterity = math.floor((math.floor(rpg_t[player.index].level * 2) + 10) * COEFF_REG[q_idx])
        return true
    end
end

local function tls(player, q_idx)
    if check_tick(player, 'tls') then
        local rpg_t = rpgtable.get('rpg_t')
        local k = (math.floor(rpg_t[player.index].level / 35) + 1) * ({1, 1, 2, 2, 3})[q_idx]
        if k >= 4 then
            k = 4
        end
        for i = 1, k do
            tzbd(player)
        end
        new_print(player, { 'tianfu.tls_over' })
        return true
    end
end

local function zsfs(player, q_idx)
    if check_tick(player, 'zsfs') then
        local players = game.connected_players
        local all_player = {}
        local max = 0
        local rpg_t = rpgtable.get('rpg_t')
        local coin = 0
        for i = 1, #players do
            local player1 = players[i]
            if rpg_t[player1.index].level > max then
                coin = math.floor(player1.get_item_count('coin') * 0.05 * COEFF_REG[q_idx])
            end
        end
        if coin >= 10000 then
            coin = 10000
        end
        if coin > 0 then
            insert_item_to_player(player, 'coin', coin)
            new_print(player, { 'tianfu.zsfs_over', coin })
        end
        return true
    end
end

local function djrc(player, q_idx)
    local rpg_t = rpgtable.get('rpg_t')
    local main_table = WPT.get()

    if not rpg_t[player.index] then
        return false
    end
    if rpg_t[player.index].dexterity < 500 then
        return false
    end

    -- 上限：最多通过顶尖人才获得 24 个天赋
    if not main_table.djrc_count[player.index] then
        main_table.djrc_count[player.index] = 0
    end
    if main_table.djrc_count[player.index] >= 24 then
        new_print(player, { 'tianfu.djrc_limit' })
        return false
    end

    if check_tick(player, 'djrc') then
        local point_count = ({1, 1, 2, 2, 3})[q_idx or 1]
        -- nil 守卫：tianfu_count[player.index] 可能在玩家未选过天赋时为 nil
        -- 不加守卫会导致算术错误，djrc 静默失败，玩家"过很久后才生效"
        if not main_table.tianfu_count[player.index] then
            main_table.tianfu_count[player.index] = 0
        end
        main_table.tianfu_count[player.index] = main_table.tianfu_count[player.index] - point_count
        main_table.djrc_count[player.index] = main_table.djrc_count[player.index] + 1
        new_print(player, { 'tianfu.djrc_over', point_count, 24 - main_table.djrc_count[player.index] })
        return true
    end
    return false
end

local function pulu(player, q_idx)
    
    
    if check_tick(player, 'pulu') then
        if player.force.name ~= "player" then return end
        local surface = player.physical_surface
        local position = player.physical_position
        
        -- 设定范围
        local width = math.floor(20 * COEFF_REG[q_idx])
        local radius = width * 0.5
        local tiles_to_set = {}

        local function is_bad_tile(tile, q_idx)
            if not tile.valid then return true end
            
            local name = tile.name
            
            if string.find(name, "water") or 
               string.find(name, "lava") or 
               string.find(name, "oil") or 
               string.find(name, "out-of-map") then
                return true
            end
            
            local mask = tile.prototype.collision_mask
            
            if mask then
                -- 如果地砖阻挡了“水层”（它是水）
                if mask["water-tile"] then return true end
                
                -- 【新增】：如果地砖阻挡了“玩家层”（玩家走不上去，多半是深水或岩浆）
                if mask["player-layer"] then return true end
                
                -- 【新增】：如果地砖阻挡了“物品层”（通常意味着这里不能放东西）
                if mask["item-layer"] then return true end
                
                -- Space Age 特有的层检测（如果存在）
                if mask["object-layer"] then return true end
            end

            -- 3. 如果已经是石路了，就不用铺了（省性能）
            if name == "stone-path" then return true end
            
            -- 4. 混凝土/精炼混凝土也不要覆盖（防止破坏玩家家里更好的路）
            if name == "concrete" or name == "hazard-concrete-left" or name == "refined-concrete" then 
                return true 
            end

            return false
        end

        for a = 1, width do
            for b = 1, width do
                local p = { 
                    x = position.x - radius + a, 
                    y = position.y - radius + b 
                }
                
                local tile = surface.get_tile(p)
                
                if not is_bad_tile(tile) then
                    table.insert(tiles_to_set, {
                        name = "stone-path",
                        position = p
                    })
                end
            end
        end

        if #tiles_to_set > 0 then
            -- 使用 true 启用边缘修正
            surface.set_tiles(tiles_to_set, true)
            new_print(player, { 'tianfu.pulu_over' })
        end
        
        return true
    end
end

local function dafs(player, q_idx)
    if check_tick(player, 'dafs') then
        local biters = player.physical_surface.count_entities_filtered {
            position = player.physical_position,
            radius = 16,
            type = {'unit', 'spider-unit'},
            force = game.forces.player,
            limit = 20
        }
        if biters == 0 then
            return false
        end
        local rpg_t = rpgtable.get('rpg_t')
        rpg_t[player.index].xp = rpg_t[player.index].xp + biters * ({1, 1, 2, 2, 3})[q_idx]
        new_print(player, { 'tianfu.dafs_over', biters })
        return true
    end
end

local function ljss(player, q_idx)
    if check_tick(player, 'ljss') then
        local biters = player.physical_surface.find_entities_filtered({
            position = player.physical_position,
            radius = 16,
            type = {'unit', 'spider-unit'},
            force = game.forces.player,
            limit = 20
        })
        if #biters == 0 then
            return false
        end
        local rpg_t = rpgtable.get('rpg_t')
        local k = (math.floor(rpg_t[player.index].magicka / 125) + 1) * ({1, 1, 2, 2, 3})[q_idx]
        rpg_t[player.index].xp = rpg_t[player.index].xp + #biters * k

        for _, v in pairs(biters) do
            if v and v.valid then
                v.die()
            end
        end

        new_print(player, { 'tianfu.ljss_over', #biters * k })
        return true
    end
end

local function mfxd(player, q_idx)
    if check_tick(player, 'mfxt') then
        local rpg_t = rpgtable.get('rpg_t')
        local k = math.floor(rpg_t[player.index].magicka / 100) + 1
        insert_item_to_player(player, 'distractor-capsule', k, QUALITY_NAMES[q_idx])
        new_print(player, { 'tianfu.mfxt_over', k })

        return true
    end
end

local function ylsgd(player, q_idx)
 
    
    if check_tick(player, 'ylsgd') then
        -- 基础建筑数量：6个

    if player.force.name ~= "player" then
        return
    end
        local base_buildings = 6

        -- 获取玩家的敏捷值
        local rpg_t = rpgtable.get('rpg_t')
        -- 注意：原代码用了 dexterity，这里假设你是对的（如果用 agility 请自行修改）
        local attribute_val = rpg_t[player.index].dexterity or 0 

        -- 计算额外的建筑数量：每200点，额外多建造3个
        local extra_buildings = math.floor(attribute_val / 200) * 3

        -- 总建筑数量上限
        local max_buildings = math.floor((base_buildings + extra_buildings) * COEFF_LOW[q_idx])

        local count = 0
        local surface = player.physical_surface -- 缓存surface，稍微优化性能

        -- 查找附近的幽灵实体
        local ghost_count = surface.count_entities_filtered({
            position = player.physical_position,
            name = 'entity-ghost',
            radius = 13,
            force = game.forces.player
        })

        if ghost_count == 0 then
            return
        end

        local ghosts = surface.find_entities_filtered({
            position = player.physical_position,
            name = 'entity-ghost',
            radius = 13,
            force = game.forces.player
        })

        for _, ghost in pairs(ghosts) do
            -- 达到上限停止
            if count >= max_buildings then
                break
            end

            -- 检查幽灵是否有效
            if ghost.valid then
                local ghost_name = ghost.ghost_name
                
                -- 检查是否在黑名单中
                if not ban_build_name[ghost_name] then
                    -- 检查玩家背包是否有对应的物品
                    -- 注意：有些实体名字和物品名字不完全一致（如弯铁路），但绝大多数情况是一致的
                    -- 这里沿用你的逻辑，直接用 ghost_name 查库存
                    local player_have = player.get_item_count(ghost_name)
                    
                    if player_have > 0 then
                        -- 【关键修改】：使用 revive() 复活实体
                        -- revive 参数：{raise_revive = true} 会触发 script_raised_revive 事件，对其他Mod兼容性更好
                         if  validate_ghost(ghost, ghost_name) then
                        local success, _ = ghost.revive({raise_revive = true})
                        
                        -- 如果复活成功（没有被障碍物挡住）
                        if success then
                            -- 扣除玩家物品
                            player.remove_item({
                                name = ghost_name,
                                count = 1
                            })
                            count = count + 1
                        end
                    end
                    end
                end
            end
        end
    end
end

local function fuzhushou(player, q_idx)
    if check_tick(player, 'fuzhushou') then
        if player.force.name~='player' then
            return
        end
        -- 物品价值表 (键是 ghost_name)
        local item_values = {
            -- 传送带类
            ['underground-belt'] = 8,
            ['fast-underground-belt'] = 24,
            ['express-underground-belt'] = 172,

            ['splitter'] = 8,
            ['fast-splitter'] = 32,
            ['express-splitter'] = 248,

            -- 机械臂类
            ['inserter'] = 2,
            ['long-handed-inserter'] = 4,
            ['fast-inserter'] = 8,
            ['bulk-inserter'] = 128,

            -- 管道类
            ['pipe'] = 1,
            ['pipe-to-ground'] = 15
        }

        -- 获取玩家的敏捷值
        local rpg_t = rpgtable.get('rpg_t')
        -- 注意确认属性名是 dexterity 还是 agility，这里沿用你代码里的 dexterity
        local agility = math.min(rpg_t[player.index].dexterity or 0, 3000)

        -- 根据敏捷计算可生成的总价值
        local base_value = 10
        local agility_bonus = math.floor(agility / 100) * 5
        local total_value = math.floor((base_value + agility_bonus) * COEFF_LOW[q_idx])

        local used_value = 0
        local built_count = 0
        local surface = player.physical_surface -- 缓存一下提高性能

        -- 查找玩家附近的实体幽灵
        local ghost_count = surface.count_entities_filtered({
            position = player.physical_position,
            name = 'entity-ghost',
            radius = 16,
            force = game.forces.player
        })

        if ghost_count == 0 then
            return
        end

        local ghosts = surface.find_entities_filtered({
            position = player.physical_position,
            name = 'entity-ghost',
            radius = 16,
            force = game.forces.player
        })

        for _, ghost in pairs(ghosts) do
            -- 如果点数用完了，直接退出循环，节省性能
            if used_value >= total_value then
                break
            end
            
            if ghost.valid then
                local g_name = ghost.ghost_name
                
                -- 检查是否在价值表中
                if item_values[g_name] then
                    local item_value = item_values[g_name]

                    -- 检查剩余价值是否足够
                    if (used_value + item_value) <= total_value then
                        
                        -- 【核心修改】：尝试复活实体
                        -- 不需要 create_entity，revive 会自动处理所有类型（地下、管道、筛选器等）
                        -- raise_revive = true 保证其他Mod能检测到这个建造事件
                        if  validate_ghost(ghost, g_name) then
                        ghost.revive({raise_revive = true})
                         used_value = used_value + item_value
                         built_count = built_count + 1
                    end
                    end
                end
            end
        end

        if built_count > 0 then
            new_print(player, { 'tianfu.fuzhushou_over', built_count })
        end

        return true
    end
end

local function tann(player, q_idx)
    if check_tick(player, 'tann') then
        local players = game.connected_players
        local all_player = {}
        for i = 1, #players do
            local player1 = players[i]
            if player1.name ~= player.name then
                all_player[#all_player + 1] = player1.index
            end
        end
        if #all_player == 0 then
            return false
        end
        local index = all_player[math.random(1, #all_player)]
        local rpg_t = rpgtable.get('rpg_t')
        local k = ((3 + math.floor(rpg_t[player.index].dexterity / 100)) / 100) * COEFF_REG[q_idx]
        if k >= 0.1 then
            k = 0.1
        end
        local target_player = game.players[index]
        local coin = 0
        if target_player.character then
            coin = math.floor(target_player.character.get_item_count('coin') * k)
        end
        if coin >= 0 then
            insert_item_to_player(player, 'coin', coin)

            new_print(player, { 'tianfu.tann_over', coin })
        end
        return true
    end
end

local function rsrl(player, q_idx)
    if check_tick(player, 'rsrl') then
        if player.force.name ~= "player" then
            return
        end
        local rpg_t = rpgtable.get('rpg_t')
        local count = math.floor(math.max(rpg_t[player.index].strength, rpg_t[player.index].dexterity) * COEFF_LOW[q_idx])
        local smelted_items = {}

        local iron = player.character.get_item_count('iron-ore')
        if iron > 0 and count > 0 then
            local smelt_count = math.min(iron, count)
            player.remove_item {
                name = 'iron-ore',
                count = smelt_count
            }
            player.insert({name = 'iron-plate', count = smelt_count})

            count = count - smelt_count
            smelted_items['iron-plate'] = smelt_count
        end

        local copper = player.character.get_item_count('copper-ore')
        if copper > 0 and count > 0 then
            local smelt_count = math.min(copper, count)
            player.remove_item {
                name = 'copper-ore',
                count = smelt_count
            }
            player.insert({name = 'copper-plate', count = smelt_count})
          
            count = count - smelt_count
            smelted_items['copper-plate'] = smelt_count
        end

        local stone = player.character.get_item_count('stone')
        if stone > 0 and count > 0 then
            local smelt_count = math.min(stone, count)
            player.remove_item {
                name = 'stone',
                count = smelt_count
            }
            player.insert({name = 'stone-brick', count = smelt_count})
           
            count = count - smelt_count
            smelted_items['stone-brick'] = smelt_count
        end

        -- 显示获得的物品悬浮文字
        for item_name, item_count in pairs(smelted_items) do
            player.create_local_flying_text({
                text = "+" .. item_count .. " [img=item/" .. item_name .. "]",
                position = player.physical_position,
                color = { r = 200 / 255, g = 160 / 255, b = 30 / 255 }
            })
        end

        new_print(player, { 'tianfu.rsrl_over' })
    end
    return true
end

local function xly(player, q_idx)
    if check_tick(player, 'xly') then
        local total = 0
        local players = game.connected_players
        for i = 1, #players do
            local player1 = players[i]
            if player1.afk_time < 36000 then
                total = total + 1
            end
        end

        local rpg_t = rpgtable.get('rpg_t')
        local all_xp = math.floor(math.min(2000, 100 * (math.floor(rpg_t[player.index].level / 10) + 1)) * COEFF_REG[q_idx])
        local xp_per_player = math.floor(all_xp / total)
        for i = 1, #players do
            local player1 = players[i]
            if player1.afk_time < 36000 then
                rpg_t[player1.index].xp = rpg_t[player1.index].xp + xp_per_player
                -- 为每个收到经验的玩家添加提示
                if player1.index ~= player.index then
                    player1.create_local_flying_text{
                        text = {'tianfu.xly_receive', xp_per_player, player.name},
                        color = {r=0.2, g=0.8, b=1.0},
                        position = player1.physical_position,
                        speed = 0.8
                    }
                end
            end
        end

        new_print(player, { 'tianfu.xly_over', all_xp })
        return true
    end
end

local function tzzj(player, q_idx)
    if check_tick(player, 'tzzj') then
        local k = 0
        k = player.character.get_item_count('coin')
        local count = math.floor(k * 0.05 * COEFF_REG[q_idx])
        if count >= 20000 then
            count = 20000
        end
        if count > 1 then
            insert_item_to_player(player, 'coin', count)
            new_print(player, { 'tianfu.tzzj_over' })
        end
    end
    return true
end

local function hhc(player, q_idx)
    if check_tick(player, 'hhc') then
        local position = player.physical_position
        local entities = EntityCache.find_entities_cached(player.physical_surface, {
            position = position,
            type = goal,
            radius = 12,
            force = game.forces.enemy,
        })

        if #entities == 0 then
            return false
        else
            local target = entities[1]
            if target and target.valid then
                player.physical_surface.create_entity({
                    name = 'slowdown-capsule',
                    position = position,
                    force = 'player',
                    source = player.character,
                    target = target.position,
                    speed = 1,
                    player = player,
                    quality = QUALITY_NAMES[q_idx or 1]

                })
            end
            return true
        end
    end
end

local function jgq(player, q_idx)
    if check_tick(player, 'jgq') then
        new_print(player, { 'tianfu.jgq_over' })

        local index = upgrade_spell(player, "jgq", { 'spells.jgq' }, true)
        local loop_n = math.max(1, math.floor(index * COEFF_REG[q_idx]))

        for i = 1, loop_n do
            Task.set_timeout_in_ticks(i * 15, jgq_work, player)
        end
        return true
    end
end

local function xj(player, q_idx)
    if not player.character or not player.character.valid then
        return false
    end
    local max = math.min(player.character.max_health, 30000)
    local now = math.min(player.character.health, 30000)
    if max == now then
        return false
    end

    if check_tick(player, 'xj') then
        if not player.character or not player.character.valid then
            return false
        end

        local k = (max - now) * 0.2 * COEFF_LOW[q_idx]

        splash_damage(player.physical_surface, player.physical_position, k, 6, true, player)

        return true
    end
end

local function smlw(player, q_idx)
    if check_tick(player, 'smlw') then
        local rpg_t = rpgtable.get('rpg_t')
        local luck = rpg_t[player.index].magicka
        if luck > 1000 then luck = 1000 end
        local magic = math.floor(luck * 3 * COEFF_REG[q_idx])
        Loot.cool_with_quality(player.physical_surface, player.physical_surface
            .find_non_colliding_position("steel-chest", player.physical_position, 20, 1, true) or
            player.physical_position, 'steel-chest',
            magic)

        local msg = { 'amap.whatopen' }
        Alert.alert_player(player, 5, msg)

        new_print(player, { 'tianfu.smlw_over' })
        return true
    end
end

local function jndd(player, q_idx)
    if check_tick(player, 'jndd') then
        local c = player.physical_surface.count_entities_filtered({
            position = player.physical_position,
            radius = 16,
            force = game.forces.player
        })
       


        c = math.floor(c / 5)
        local rpg_t = rpgtable.get('rpg_t')
        -- 品质仅作用于「每100敏捷的金币系数」K（11223公式）；每5设备的基础金币固定为1，不随品质变化（单一品质作用点）
        local K = ({1, 1, 2, 2, 3})[q_idx]
        local coin = c + math.floor(rpg_t[player.index].dexterity / 100) * K
        if coin >= 1500 then
            coin = 1500
        end
        if coin <= 0 then
            return
        end
        insert_item_to_player(player, 'coin', coin)

        new_print(player, { 'tianfu.jndd_over', coin })

        return true
    end
end

local function ycj(player, q_idx)
    if check_tick(player, 'ycj') then
        local rpg_t = rpgtable.get('rpg_t')
        -- 基础金币数60，每100点敏捷多发10金币
        local base_coin = 60
        local dexterity_bonus = math.floor(rpg_t[player.index].dexterity / 100) * 10
        local total_coin = math.floor(math.min(base_coin + dexterity_bonus, 120) * COEFF_REG[q_idx])

        for l, player1 in pairs(game.connected_players) do
            insert_item_to_player(player1, 'coin', total_coin)
            -- 为每个收到金币的玩家添加提示
            if player1.index ~= player.index then
                player1.create_local_flying_text{
                    text = {'tianfu.ycj_receive', total_coin, player.name},
                    color = {r=0.8, g=0.8, b=0.2},
                    position = player1.physical_position,
                    speed = 0.8
                }
            end
        end
        player.remove_item {
            name = 'coin',
            count = total_coin
        }
        new_print(player, { 'tianfu.ycj_over', total_coin })
        return true
    end
end

local function qns(player, q_idx)
    if check_tick(player, 'qns') then
        local this = WPT.get()
        local rpg_t = rpgtable.get('rpg_t')
        local s = rpg_t[player.index].strength
        local d = rpg_t[player.index].dexterity
        local m = rpg_t[player.index].magicka
        local v = rpg_t[player.index].vitality

        if s >= 400 and d >= 400 and m >= 400 and v >= 400 then
            new_print(player, { 'tianfu.qns_over' })
            this.qns_true = true
            local all = (s + d + m + v)-1600

            local times = math.floor(all / 400) + 1
            if times >= 10 then
                times = 10
            end
            local position = player.physical_position
            local entities = EntityCache.find_entities_cached(player.physical_surface, {
                position = position,
                type = goal,
                radius = 24,
                force = game.forces.enemy
            })

            for i = 1, times, 1 do
                for k = 1, 4, 1 do
                    if #entities ~= 0 then
                        local index = math.random(1, #entities)
                        local target = entities[index]
                        local data = {
                            biter = target,
                            position = position,
                            player = player,
                            quality = QUALITY_NAMES[q_idx or 1]
                        }
                        Task.set_timeout_in_ticks(i * 30, fashe, data)
                        table.remove(entities, index)
                    end
                end
            end
        end
        return true
    end
end

local function dl(player, q_idx)
    if check_tick(player, 'dl') then
          if player.force.name ~= 'player' then
            return false
        end
        local all = player.physical_surface.count_entities_filtered {
            position = player.physical_position,
            type = 'character',
            radius = 15,
            force = "player"
        }

        if all ~= 1 then
            return false
        end
        -- 品质系数应缩放的是完整倍率(1.5×)而非仅基础加成(0.5)
        -- modifier = 目标倍率 - 1，即 1.5*COEFF_LOW[q_idx] - 1
        player.character_running_speed_modifier = player.character_running_speed_modifier + 1.5 * COEFF_LOW[q_idx] - 1
        Task.set_timeout_in_ticks(60 * 4, lowdowm_1, player)

        return true
    end
end

local function jxhx(player, q_idx)
    if check_tick(player, 'jxhx') then
        if not player.character then
            return
        end
        local armor_inventory = player.get_inventory(defines.inventory.character_armor)
        if not armor_inventory or not armor_inventory.valid then
            return
        end
        local armor = armor_inventory[1]
        if not armor or not armor.valid_for_read then
            return
        end
        local grid = armor.grid
        if not grid or not grid.valid then
            return
        end

        local rpg_t = rpgtable.get('rpg_t')
        if rpg_t[player.index].dexterity < 800 then
            return
        end
        local ok = false
        if rpg_t[player.index].dexterity > rpg_t[player.index].strength then
            if rpg_t[player.index].dexterity > rpg_t[player.index].magicka then
                if rpg_t[player.index].dexterity > rpg_t[player.index].vitality then
                    ok = true
                end
            end
        end
        if not ok then
            return
        end
        local equip = grid.equipment

        local energy = math.floor(math.floor(rpg_t[player.index].dexterity / 2) * 2500 * COEFF_REG[q_idx])
        local all = energy
        for _, piece in pairs(equip) do
            if piece.valid and piece.generator_power == 0 then
                local energy_needs = piece.max_energy - piece.energy
                if energy <= 0 then
                    new_print(player, { 'tianfu.jxhx_over', all })
                    return true
                end
                if energy_needs > 0 then
                    if energy > 0 then
                        if piece.energy + energy >= piece.max_energy then
                            piece.energy = piece.max_energy
                            energy = energy - energy_needs
                        else
                            piece.energy = piece.energy + energy
                            energy = 0
                        end
                    end
                end
            end
        end
        new_print(player, { 'tianfu.jxhx_over', all })
        return true
    end
end

local function wlfs(player, q_idx)
    if check_tick(player, 'wlfs') then
        local main_table = WPT.get()
        if player.physical_surface ~= game.surfaces[main_table.active_surface_index] then
            return false
        end
        local position = player.physical_position
        local entities = player.physical_surface.find_entities_filtered({
            position = position,
            radius = 33,
            type = 'corpse'
        })
        local i = 0
        if #entities == 0 then
            return false
        end
        for _, entity in pairs(entities) do
           
                entity.destroy()
                i = i + 1
      
        end

        i = i * 5
        i = math.floor(i * COEFF_REG[q_idx])

        local wlfs_cap = math.floor(2000 * COEFF_REG[q_idx])
        if i >= wlfs_cap then
            i = wlfs_cap
        end

        local forces = {}
        local position = player.physical_position
        local times = 0
        local group = player.physical_surface.create_unit_group({
            position = player.physical_position,
            force = player.force
        })
        local attempts = 0
        local max_attempts = 1000  -- 防止死循环的最大尝试次数
        
        -- 检查t表是否为空
        local t_empty = true
        for name, worth in pairs(t) do
            t_empty = false
            break
        end
        
        if not t_empty then
            while i > 0 and attempts < max_attempts do
                local i_reduced = false
                for name, worth in pairs(t) do
                    if i >= worth then
                        i = i - worth
                        local e = player.physical_surface.create_entity {
                            name = name,
                            position = {
                                x = position.x + math.random(-18, 18),
                                y = position.y + math.random(-18, 18)
                            },
                            force = game.forces.player
                        }
                        forces[#forces + 1] = e
                        tame_unit_effects(player, e)
                        if e and e.valid and (e.type == 'unit' or e.type == 'spider-unit') then
                            group.add_member(e)
                        end
                        i_reduced = true
                    end
                    i = i - 1
                end
                -- 如果没有减少i且for循环结束后i仍然很大，跳出循环
                if not i_reduced and i > 100 then
                    break
                end
                attempts = attempts + 1
            end
        end
        if attack(position, group, player) then
            Task.set_timeout_in_ticks(60 * 10, kill_forces, forces)
        else
           Task.set_timeout_in_ticks(60 * 10, kill_forces, forces)
        end

        new_print(player, { 'tianfu.wlfs_over' })
        return true
    end
end

local function xxzb(player, q_idx)
    if check_tick(player, 'xxzb') then
        local rpg_t = rpgtable.get('rpg_t')
        local mana_gain = (1 + math.floor(rpg_t[player.index].vitality / 400)) * ({1, 1, 2, 2, 3})[q_idx]
        rpg_t[player.index].mana = rpg_t[player.index].mana + mana_gain

        if rpg_t[player.index].mana >= rpg_t[player.index].mana_max then
            rpg_t[player.index].mana = rpg_t[player.index].mana_max
        end
        return true
    end
end

local function juemuren(player, q_idx)
    if check_tick(player, 'juemuren') then
        local main_table = WPT.get()
        if player.physical_surface ~= game.surfaces[main_table.active_surface_index] then
            return false
        end
        
        local position = player.physical_position
        local entities = player.physical_surface.find_entities_filtered({
            position = position,
            radius = 33,
            type = 'corpse'
        })
        
        local valid_corpses = {}
        for _, entity in pairs(entities) do
      
                table.insert(valid_corpses, entity)
          
        end
        
        if #valid_corpses == 0 then
            return false
        end
        
        local selected_corpse = valid_corpses[math.random(1, #valid_corpses)]
        local corpse_position = selected_corpse.position
        selected_corpse.destroy()
        
        local rpg_t = rpgtable.get('rpg_t')
        local magicka = rpg_t[player.index].magicka or 0
        local damage_on_death = magicka * 0.2 * COEFF_LOW[q_idx]
        
        local biter_names = {'small-biter', 'small-spitter', 'medium-biter', 'medium-spitter', 'big-biter', 'big-spitter', 'behemoth-biter', 'behemoth-spitter'}
        local selected_biter_name = biter_names[math.random(1, #biter_names)]
        
        local revived_unit = player.physical_surface.create_entity {
            name = selected_biter_name,
            position = corpse_position,
            force = game.forces.player
        }
        
        if revived_unit and revived_unit.valid then
            revived_unit.destructible = false
            tame_unit_effects(player, revived_unit)
            
            Task.set_timeout_in_ticks(60 * 5, juemuren_death_callback, {
                unit = revived_unit,
                player = player,
                damage = damage_on_death
            })
            
            new_print(player, { 'tianfu.juemuren_over' })
            return true
        end
    end
    return false
end


local function lg(player, q_idx)
    if check_tick(player, 'lg') then
        local position = player.physical_position
        local entities = player.physical_surface.find_entities_filtered({
            position = position,
            radius = 33,
            type = 'corpse'
        })
        local i = 0
        if #entities == 0 then
            return false
        end
        for _, entity in pairs(entities) do

                entity.destroy()
                i = i + 1

        end

        local rpg_t = rpgtable.get('rpg_t')
        local lg_gain = math.floor(i / 100) * ({1, 1, 2, 2, 3})[q_idx]
        rpg_t[player.index].strength = rpg_t[player.index].strength + lg_gain

        new_print(player, { 'tianfu.lg_over', lg_gain })
        return true
    end
end

local function xxg(player, q_idx)
    if check_tick(player, 'xxg') then
        local position = player.physical_position
        local entities = player.physical_surface.find_entities_filtered({
            position = position,
            radius = 33,
            type = 'corpse'
        })
        local i = 0
        if #entities == 0 then
            return false
        end
        for _, entity in pairs(entities) do

                entity.destroy()
                i = i + 1

        end

        local rpg_t = rpgtable.get('rpg_t')
        -- 每100具尸体按品质获得活力（天赋描述：附近每有100个尸体就提升活力）
        local xxg_gain = math.floor(i / 100) * ({1, 1, 2, 2, 3})[q_idx]
        rpg_t[player.index].vitality = rpg_t[player.index].vitality + xxg_gain

        new_print(player, { 'tianfu.xxg_over', xxg_gain })
        return true
    end
end

local function dgwd(player, q_idx)
    if not player.character or not player.character.valid then
        return false
    end
    local max = player.character.max_health
    local now = player.character.health
    if now == max then
        return false
    end

    local rpg_t = rpgtable.get('rpg_t')
    if not rpg_t[player.index] then
        return false
    end
    local stats = rpg_t[player.index]
    local ok = stats.vitality >= 800
        and stats.vitality > stats.strength
        and stats.vitality > stats.dexterity
        and stats.vitality > stats.magicka

    if check_tick(player, 'dgwd') and ok then
        local k = math.floor(stats.vitality / 135) + 1
        if k > 15 then
            k = 15
        end

        upgrade_spell(player, "wudi_turret", { 'spells.wudi_turret' }, true)
        local forces = {}
        local surface = player.physical_surface
        local position = player.physical_position
        for a = 1, k do
            local ammo_name = upgrade_spell(player, "wudi_turret", { 'spells.wudi_turret' }, false)
            local turret_position = surface.find_non_colliding_position("gun-turret", {
                x = position.x + math.random(-15, 15),
                y = position.y + math.random(-15, 15)
            }, 20, 1, true)

            if turret_position then
                local turret = surface.create_entity {
                    name = "gun-turret",
                    quality = QUALITY_NAMES[q_idx or 1],
                    position = turret_position,
                    force = game.forces.player
                }
                turret.insert {
                    name = ammo_name,
                    count = 50
                }
                turret.destructible = false
                turret.minable_flag = false
                turret.operable = false
                turret.last_user = player
                local main_table = WPT.get()
                main_table.turret_rpg[#main_table.turret_rpg + 1] = turret
                forces[#forces + 1] = turret
            end
        end

        if #forces > 0 then
            new_print(player, { 'tianfu.dgwd_over', #forces })
            Task.set_timeout_in_ticks(60 * 11, kill_forces, forces)
        else
            new_print(player, { 'tianfu.dgwd_fail' })
        end
        return true
    end
    return false
end

local function honzha(player, q_idx)
    if check_tick(player, 'honzha') then
        local rpg_t = rpgtable.get('rpg_t')
        local k = math.floor(rpg_t[player.index].vitality / 100)
        if k <= 1 then
            k = 1
        end
        insert_item_to_player(player, 'cluster-grenade', k, QUALITY_NAMES[q_idx])
        new_print(player, { 'tianfu.honzha_over', k })
        return true
    end
end

local function chifu(player, q_idx)
    if check_tick(player, 'chifu') then
        if not player.character or not player.character.valid then
            return false
        end
        local max = player.character.max_health
        local now = player.character.health
        if max ~= now then
            max = math.min(max, 30000)
            player.character.health = player.character.health + math.floor(max * 0.02 * COEFF_LOW[q_idx] + 0.5)
        end
    end
    return true
end

local function touqian(player, q_idx)
    if check_tick(player, 'touqian') then
        local rpg_t = rpgtable.get('rpg_t')
        local k = math.floor(rpg_t[player.index].dexterity * 0.3 * COEFF_REG[q_idx])
        if k >= math.floor(10000 * COEFF_REG[q_idx]) then
            k = math.floor(10000 * COEFF_REG[q_idx])
        end
        insert_item_to_player(player, 'coin', k)
        new_print(player, { 'tianfu.touqian_over', k })
        return true
    end
end


local function fatiao(player, q_idx)
    if check_tick(player, 'fatiao') then
        local position = player.physical_position
        local entities = EntityCache.find_entities_cached(player.physical_surface, {
            position = position,
            type = goal,
            radius = 24,
            force = game.forces.enemy
        })
        local rpg_t = rpgtable.get('rpg_t')
        local k = math.floor(rpg_t[player.index].strength / 100)
        if entities == 0 then
            return false
        end
        if k <= 1 then
            k = 1
        end
        if k > 20 then
            k = 20
        end

        for i = 1, k, 1 do
            if #entities ~= 0 then
                local index = math.random(1, #entities)
                local target = entities[index]
                if target and target.valid and target.health then
                    if target.health then
                        local e = player.physical_surface.create_entity({
                            name = 'rocket',
                            position = position,
                            force = 'player',
                            source = player.character,
                            target = target,
                            speed = 1,
                            player = player,
                            last_user = player,
                            quality = QUALITY_NAMES[q_idx or 1]

                        })
                    end
                end
                table.remove(entities, index)
            end
        end
    end
    return true
end

local function fkdda(player, q_idx)
    if check_tick(player, 'fkdda') then
        local position = player.physical_position
        local entities = EntityCache.find_entities_cached(player.physical_surface, {
            position = position,
            type = goal,
            radius = 27,
            force = game.forces.enemy
        })

        for i = 1, 3, 1 do
            if #entities ~= 0 then
                local index = math.random(1, #entities)
                local target = entities[index]
                if target and target.valid and target.health then
                    if target.health > 0 then
                        local e = player.physical_surface.create_entity({
                            name = 'rocket',
                            position = position,
                            force = 'player',
                            source = player.character,
                            target = target,
                            speed = 1,
                            player = player,
                            last_user = player,
                            quality = QUALITY_NAMES[q_idx or 1]

                        })
                    end
                end
                table.remove(entities, index)
            end
        end
    end
    return true
end


local function fkddb(player, q_idx)
    if check_tick(player, 'fkddb') then
        local position = player.physical_position
        local entities = EntityCache.find_entities_cached(player.physical_surface, {
            position = position,
            type = goal,
            radius = 27,
            force = game.forces.enemy
        })

        for i = 1, 5, 1 do
            if #entities ~= 0 then
                local index = math.random(1, #entities)
                local target = entities[index]
                if target and target.valid and target.health then
                    if target.health > 0 then
                        local e = player.physical_surface.create_entity({
                            name = 'rocket',
                            position = position,
                            force = 'player',
                            source = player.character,
                            target = target,
                            speed = 1,
                            player = player,
                            last_user = player,
                            quality = QUALITY_NAMES[q_idx or 1]

                        })
                    end
                end
                table.remove(entities, index)
            end
        end
    end
    return true
end

local function keyan(player, q_idx)
    local pingzi = {
        ['automation-science-pack'] = 2,
        ['logistic-science-pack'] = 8,
        ['military-science-pack'] = 34,
        ['chemical-science-pack'] = 84,
        ['production-science-pack'] = 148,
        ['utility-science-pack'] = 168,
    }
    if check_tick(player, 'keyan') then
        local rpg_t = rpgtable.get('rpg_t')
        local mana_max = math.floor(math.min(rpg_t[player.index].dexterity, 2000) * COEFF_REG[q_idx])
        if mana_max >= 10 then
            local position = player.physical_position
            local attempts = 0
            local max_attempts = 1000  -- 防止死循环的最大尝试次数
            
            -- 检查pingzi表是否为空
            local pingzi_empty = true
            for name, worth in pairs(pingzi) do
                pingzi_empty = false
                break
            end
            
            if not pingzi_empty then
                while mana_max > 3 and attempts < max_attempts do
                    local mana_reduced = false
                    for name, worth in pairs(pingzi) do
                        if worth <= mana_max then
                            insert_item_to_player(player, name, 1)
                            mana_max = mana_max - worth
                            mana_reduced = true
                        end
                    end
                    -- 如果没有减少mana，说明无法继续，跳出循环
                    if not mana_reduced then
                        break
                    end
                    attempts = attempts + 1
                end
            end
            new_print(player, { 'tianfu.keyan_over' })
        end
    end
    return true
end



 
local function hmds(player, q_idx)
    if check_tick(player, 'hmds') then
        local value = upgrade_spell(player, "ch", { 'spells.ch' }, true)
        local main_table = WPT.get()
        if player.physical_surface ~= game.surfaces[main_table.active_surface_index] then
            return false
        end
        local rpg_t = rpgtable.get('rpg_t')
        local mana_max = math.floor(rpg_t[player.index].mana_max * 0.8 * COEFF_REG[q_idx]) + value
        if mana_max > 10 then
            local forces = {}
            local position = player.physical_position

            local group = player.physical_surface.create_unit_group({
                position = player.physical_position,
                force = player.force
            })
            local attempts = 0
            local max_attempts = 1000  -- 防止死循环的最大尝试次数
            
            -- 检查t表是否为空
            local t_empty = true
            for name, worth in pairs(t) do
                t_empty = false
                break
            end
            
            if not t_empty then
                while mana_max > 0 and attempts < max_attempts do
                    local mana_reduced = false
                    for name, worth in pairs(t) do
                        if worth <= mana_max then
                            mana_max = mana_max - worth
                            local position = player.physical_surface.find_non_colliding_position(name, {
                                x = position.x + math.random(-18, 18),
                                y = position.y + math.random(-18, 18)
                            }, 20, 1, true)
                            if position then
                                local e = player.physical_surface.create_entity {
                                    name = name,
                                    position = position,
                                    force = game.forces.player
                                }
                                forces[#forces + 1] = e
                                tame_unit_effects(player, e)
                                if e and e.valid and (e.type == 'unit' or e.type == 'spider-unit') then
                                    group.add_member(e)
                                end
                            end
                            mana_reduced = true
                        end
                        mana_max = mana_max - 1
                    end
                    -- 如果没有减少mana且for循环结束后mana_max仍然很大，跳出循环
                    if not mana_reduced and mana_max > 100 then
                        break
                    end
                    attempts = attempts + 1
                end
            end
            if attack(position, group, player) then
                Task.set_timeout_in_ticks(60 * 10, kill_forces, forces)
            else
               Task.set_timeout_in_ticks(60 * 10, kill_forces, forces)
            end

          --  unstuck_player(player.index)
            new_print(player, { 'tianfu.hmds_over' })
        end
    end
    return true
end

local function sglz(player, q_idx)
    if not player.character or not player.character.valid then
        return false
    end
    local max = player.character.max_health
    local now = player.character.health
    if max == now then
        return false
    end
    if check_tick(player, 'sglz') then
        if not player.character or not player.character.valid then
            return false
        end
        if max>=30000 then 
            max=30000
        end

        splash_damage(player.physical_surface, player.physical_position, max * 0.10 * COEFF_LOW[q_idx], 10, true, player)
        player.character.health = player.character.health + max * 0.15 * COEFF_LOW[q_idx]
        new_print(player, { 'tianfu.sglz_over' })
    end
    return true
end

local function bpz(player, q_idx)
    local this = TPT.get()
    local rpg_t = rpgtable.get('rpg_t')
    if not this.bpz_count[player.index] then
        this.bpz_count[player.index] = 1
        rpg_t[player.index].dexterity = rpg_t[player.index].dexterity + 15
    end
    if check_tick(player, 'bpz') then
        if rpg_t[player.index].dexterity > rpg_t[player.index].strength then
            if rpg_t[player.index].dexterity > rpg_t[player.index].magicka then
                if rpg_t[player.index].dexterity > rpg_t[player.index].vitality then
                    local dex_gain = ({1, 1, 2, 2, 3})[q_idx or 1]
                    rpg_t[player.index].dexterity = rpg_t[player.index].dexterity + dex_gain
                    new_print(player, { 'tianfu.bpz_over' })
                end
            end
        end
    end
    return true
end

local function boom_player(player, q_idx)
    local this = TPT.get()
    -- 初始化玩家的充能数据（使用this而不是global，参考yjjn函数模式）
    --检查冷却时间
    if not check_tick(player, 'boom_player') then
        return
    end

    local index = player.index
    if not this.boom_player_count[index] then
        this.boom_player_count[index] = 0
        this.boom_player_charges[index] = 0
    end

    -- 处理充能逻辑：基于函数调用次数计数，参考yjjn函数
    this.boom_player_count[index] = this.boom_player_count[index] + 1

    if this.boom_player_count[index] >= 10 then
        this.boom_player_count[index] = 0

        -- 获取玩家属性
        local rpg_t = rpgtable.get('rpg_t')
        local vitality = rpg_t[player.index].vitality or 0

        -- 基础充能+活力加成充能
        local base_charges = 1
        local vitality_bonus = math.floor(vitality / 200)
        local total_charges_to_add = base_charges + vitality_bonus

        -- 更新充能
        this.boom_player_charges[index] = this.boom_player_charges[index] + total_charges_to_add

        -- 计算最大充能数（基础12 + 活力加成的一半）
        local max_charges = 12
        if this.boom_player_charges[index] > max_charges then
            this.boom_player_charges[index] = max_charges
        end

        if total_charges_to_add > 0 then
            new_print(player, { 'tianfu.boom_player_charge', total_charges_to_add, this.boom_player_charges[index] })
        end
    end

    -- 处理技能释放
    if this.boom_player_charges[index] >= 1 then
        -- 查找周围的敌人
        local enemies = EntityCache.find_entities_cached(player.physical_surface, {
            position = player.physical_position,
            type = goal,
            radius = 15,
            force = "enemy"
        })

        if #enemies > 0 then
            -- 获取玩家力量属性
            local rpg_t = rpgtable.get('rpg_t')
            local strength = rpg_t[player.index].strength or 0
            local grenade_type = strength > 1000 and 'cluster-grenade' or 'grenade' -- 红手雷

            -- 选择不同的敌人目标
            local target1 = enemies[math.random(1, #enemies)]
            local target2 = target1

            -- 如果有多个敌人，确保第二个目标不同
            if #enemies > 1 then
                repeat
                    target2 = enemies[math.random(1, #enemies)]
                until target2 ~= target1
            end

            -- 向第一个目标投弹
            player.physical_surface.create_entity({
                name = grenade_type,
                quality = ({ 'normal', 'uncommon', 'rare', 'epic', 'legendary' })[q_idx or 1],
                position = player.physical_position,
                force = 'player',
                source = player.character,
                target = target1,
                speed = 0.8,
                player = player
            })

            -- 向第二个目标投弹
            player.physical_surface.create_entity({
                name = grenade_type,
                quality = ({ 'normal', 'uncommon', 'rare', 'epic', 'legendary' })[q_idx or 1],
                position = player.physical_position,
                force = 'player',
                source = player.character,
                target = target2,
                speed = 0.8,
                player = player
            })

            -- 消耗充能
            this.boom_player_charges[index] = this.boom_player_charges[index] - 2
            new_print(player, { 'tianfu.boom_player_over', this.boom_player_charges[index] })
        end
    end
    return true
end

local function small_buss(player, q_idx)
    if check_tick(player, 'small_buss') then
        -- 获取玩家敏捷属性并计算保底收益加成：每100敏捷+10金币
        local rpg_t = rpgtable.get('rpg_t')
        local agility_bonus = math.floor(rpg_t[player.index].dexterity / 100) 
        local base_min = -30 + math.floor(agility_bonus * 10 * COEFF_REG[q_idx])
        local coin = base_min + math.floor(math.random(1, 120))
        if coin >= 1500 then
            coin = 1500
        end
        if coin >= 0 then
            insert_item_to_player(player, 'coin', coin)
            new_print(player, { 'tianfu.small_buss_win', coin })
        else
            player.remove_item {
                name = 'coin',
                count = coin * -1
            }
            new_print(player, { 'tianfu.small_buss_lose', coin * -1 })
        end
    end

    return true
end

local function zrsc(player, q_idx)
    if check_tick(player, 'zrsc') then
        local rpg_t = rpgtable.get('rpg_t')
        local zrsc_gain = math.floor(3 * COEFF_LOW[q_idx] + 0.5)
        rpg_t[player.index].vitality = rpg_t[player.index].vitality + zrsc_gain
        new_print(player, { 'tianfu.zrsc_over', zrsc_gain })
    end
    return true
end

local function zhs(player, q_idx)
    if check_tick(player, 'zhs') then
        local trigger_count = ({1, 1, 2, 2, 3})[q_idx or 1]
        for _ = 1, trigger_count do
            tzbd(player)
        end
        new_print(player, { 'tianfu.zhs_over' })
        return true
    end
end

local function wolf(player, q_idx)
    if not player.character or not player.character.valid then
        return false
    end
    local max = math.min(player.character.max_health, 30000)
    local now = math.min(player.character.health, 30000)
    if max == now then
        return false
    end

    if check_tick(player, 'wolf') then
        if not player.character or not player.character.valid then
            return false
        end
        player.character.health = player.character.health + (max - now) * 0.2 * COEFF_LOW[q_idx]
    end
    return true
end

local function dutu(player, q_idx)
    if check_tick(player, 'dutu') then
        if player.character.get_item_count('coin') >= 1500 and math.random(1, 8) == 1 then
            player.remove_item {
                name = 'coin',
                count = 1500
            }

            local luck = math.floor(math.random(1, 150))
            new_print(player, { 'amap.lucknb', luck })
            local magic = math.floor((luck * 5 + 100) * COEFF_REG[q_idx])
            Loot.cool(player.physical_surface, player.physical_surface
                .find_non_colliding_position("steel-chest", player.physical_position, 20, 1, true) or
                player.physical_position,
                'steel-chest', magic)

            local msg = { 'amap.whatopen' }
            Alert.alert_player(player, 5, msg)
            new_print(player, { 'tianfu.dutu_over' })
        end
    end
    return true
end
 
local function wxs(player, q_idx)
    if check_tick(player, 'wxs') then
        local player_build_types = { 'wall', 'ammo-turret', 'fluid-turret', 'electric-turret', 'electric-pole', 'gate' }
        local position = player.physical_position
        local entities = player.physical_surface.find_entities_filtered({
            type = player_build_types,
            force = player.force,
            radius = 20,
            position = position
        })
        local count = 0
        for i = 1, #entities do
            local e = entities[i]
            if e.max_health ~= e.health then
                e.health = e.health + e.max_health * 0.05 * COEFF_LOW[q_idx]
                count = count + 1
            end
        end
        if count > 0 then
            new_print(player, { 'tianfu.wxs_over' })
            return true
        end
    end
    return false
end

local function junhuo(player, q_idx)
    if check_tick(player, 'junhuo') then
        -- 基础子弹数量
        local base_bullets = 10

        -- 获取玩家的敏捷值
        local rpg_t = rpgtable.get('rpg_t')
        local agility = rpg_t[player.index].dexterity or 0

        -- 计算额外的子弹数量：每200点敏捷，额外多给10发
        local extra_bullets = math.floor(agility / 200) * 10

        -- 总子弹数量
        local total_bullets = base_bullets + extra_bullets

        -- 检查玩家背包中的子弹数量
        local current_bullets = player.get_item_count('firearm-magazine')

        -- 只有当子弹数量小于等于1000时才插入子弹
        if current_bullets <= 500 then
            insert_item_to_player(player, 'firearm-magazine', total_bullets, QUALITY_NAMES[q_idx])
        end

        -- 显示动态的子弹数量
        new_print(player, { 'tianfu.junhuo_over', total_bullets })
    end
    return true
end

local function genben(player, q_idx)
    if check_tick(player, 'genben') then
        insert_item_to_player(player, 'defender-capsule', 1, QUALITY_NAMES[q_idx])

        new_print(player, { 'tianfu.genben_over' })
    end
    return true
end

local function fish(player, q_idx)
    if check_tick(player, 'fish') then
        local times= upgrade_spell(player, "advanced_fishing", { 'spells.advanced_fishing' }, true)
        local base_count = math.random(2, 5)
        -- 添加魔法值加成：每200魔法多给的鱼随品质(11223)缩放
        local rpg_t = rpgtable.get('rpg_t')
        local magic_bonus = math.floor(rpg_t[player.index].magicka / 200) + times
        local count = base_count + magic_bonus * ({1, 1, 2, 2, 3})[q_idx]
        -- 最大鱼数为25
        if count >= 25 then
            count = 25
        end
        insert_item_to_player(player, 'raw-fish', count)
        new_print(player, { 'tianfu.fish_over', count })
    end
    return true
end

local function lengdongyubaoxianshu(player, q_idx)
    if check_tick(player, 'lengdongyubaoxianshu') then
        local fish_count = player.get_item_count('raw-fish')
        if fish_count > 0 then
            player.remove_item({ name = 'raw-fish', count = fish_count })
            insert_item_to_player(player, 'raw-fish', fish_count)
            new_print(player, { 'tianfu.lengdongyubaoxianshu_over', fish_count })
        end
    end
    return true
end

local function ailunisi(player, q_idx)
    return true
end

local function haiguanfang(player, q_idx)
    if check_tick(player, 'haiguanfang') then
        local main_table = WPT.get()
        local player_index = player.index
        
        local car_entity = main_table.tank[player_index]
        local car_surface = nil
        local car_area = nil
        
        if car_entity and car_entity.valid then
            local unit_number = car_entity.unit_number
            if unit_number then
                car_surface = game.surfaces[tostring(unit_number)]
                if car_surface and car_surface.valid then
                    local abc = main_table.world_number == 6 and 2 or 1
                    local car_name = car_entity.name
                    if car_name == 'car' then
                        car_area = {left_top = {x = -20*abc, y = 0}, right_bottom = {x = 20*abc, y = 20*abc}}
                    elseif car_name == 'tank' then
                        car_area = {left_top = {x = -30*abc, y = 0}, right_bottom = {x = 30*abc, y = 40*abc}}
                    elseif car_name == 'spidertron' or car_name == 'spider-vehicle' then
                        car_area = {left_top = {x = -40*abc, y = 0}, right_bottom = {x = 40*abc, y = 60*abc}}
                    end
                end
            end
        end
        
        if not car_surface then
            return true
        end
        
        local island_info = main_table.tianfu_islands[player_index]
        local need_create = false
        
        if not island_info then
            need_create = true
        else
            if main_table.islands and main_table.islands[island_info.island_id] then
                local island = main_table.islands[island_info.island_id]
                if not island.market_entity or not island.market_entity.valid then
                    need_create = true
                end
            else
                need_create = true
            end
        end
        
        if need_create then
            local market_position = {x = 0, y = -4}
            local market_entity = car_surface.create_entity({
                name = 'market',
                position = market_position,
                force = 'player',
                create_build_effect_smoke = false
            })
            
            if market_entity then
                market_entity.destructible = false
                market_entity.minable_flag = false
                
                local this = WPT.get()
                
                if not this.islands then
                    this.islands = {}
                end
                
                local island_id = #this.islands + 1
                
                local tag_id = game.forces.player.add_chart_tag(car_surface, {
                    position = market_position,
                    text = '资源岛'
                })
                
                local island_data = {
                    id = island_id,
                    level = 0,
                    type = 'resource',
                    owner = nil,
                    owner_name = nil,
                    market_entity = market_entity,
                    production_items = {},
                    production_capacity = 0,
                    last_production_time = 0,
                    text_id = nil,
                    storage_chests = {},
                    tag_id = tag_id,
                    investments = {}
                }
                
                this.islands[island_id] = island_data
                
                local buy_island_item = {
                    price = {{name = "coin", count = 10000}},
                    offer = {
                        type = 'nothing',
                        effect_description = {'amap.buy_island', {'amap.resource_island'}, 6, '10000'}
                    }
                }
                
                market_entity.add_market_item(buy_island_item)
                
                main_table.tianfu_islands[player_index] = {
                    island_id = island_id,
                    surface_index = car_surface.index
                }
                
                new_print(player, {'tianfu.haiguanfang_island_created'})
            end
        end
        
        local water_tiles = car_surface.find_tiles_filtered({
            name = 'water',
            area = car_area
        })
        
        if #water_tiles > 0 then
            local fish_count = ({1, 2, 3, 4, 5})[q_idx or 1]
            for _ = 1, fish_count do
                local random_tile = water_tiles[math.random(1, #water_tiles)]
                car_surface.create_entity({
                    name = 'fish',
                    position = random_tile.position,
                    force = 'player'
                })
            end
        end
    end
    return true
end

Public.haiguanfang = haiguanfang

local function emengyingrao(player, q_idx)
    if not check_tick(player, 'emengyingrao') then
        return false
    end
    
    if not player.character or not player.character.valid then
        return false
    end
    
    local rpg_t = rpgtable.get('rpg_t')
    local player_level = rpg_t[player.index].level
    
    local is_highest_level = true
    for _, p in pairs(game.connected_players) do
        if p.index ~= player.index then
            local other_level = rpg_t[p.index] and rpg_t[p.index].level or 0
            if other_level > player_level then
                is_highest_level = false
                break
            end
        end
    end
    
    if not is_highest_level then
        return false
    end
    
    local max_health = player.character.max_health
    local current_health = player.character.health
    local is_injured = current_health < max_health
    
    if not is_injured then
        return false
    end
    
    if math.random(1, 100) > 50 then
        return false
    end
    
    local main_table = WPT.get()
    local current_locked = main_table.emengyingrao_locked_player
    
    
    main_table.emengyingrao_locked_player = player.character
    main_table.emengyingrao_lock_end_tick = game.tick + math.floor(60 * 60 * COEFF_REG[q_idx])
    
    new_print(player, {'tianfu.emengyingrao_over'})
    
    return true
end

Public.emengyingrao = emengyingrao

local function falibiqu(player, q_idx)
    if check_tick(player, 'falibiqu') then
        local rpg_t = rpgtable.get('rpg_t')
        local player_position = player.physical_position
        local surface = player.physical_surface

        local max_mana = rpg_t[player.index].mana_max or 100
        local damage = (10 + max_mana * 0.02) * COEFF_REG[q_idx]

        local nearby_enemies = EntityCache.find_entities_cached(surface, {
            position = player_position,
            radius = 4,
            force = game.forces.enemy,
            type = goal
        })

        if #nearby_enemies > 0 then
            local target = nearby_enemies[math.random(1, #nearby_enemies)]
            if target.valid then
                deal_damage_with_floating_text(target, player, damage, 'laser')
                local heal_amount = damage
                local max_health = player.character.max_health
                local current_health = player.character.health
                if current_health + heal_amount > max_health then
                    player.character.health = max_health
                else
                    player.character.health = current_health + heal_amount
                end
                rpg_t[player.index].mana = math.min(rpg_t[player.index].mana + heal_amount, max_mana)
            end
        end
    end
    return true
end

Public.falibiqu = falibiqu

local function zdfs(player, q_idx)
    if check_tick(player, 'zdfs') then
        local position = player.physical_position
        local entities = EntityCache.find_entities_cached(player.physical_surface, {
            position = position,
            type = goal,
            radius = 27,
            force = game.forces.enemy
        })
        if #entities ~= 0 then
            local e = player.physical_surface.create_entity({
                name = 'explosive-rocket',
                position = position,
                force = 'player',
                source = player.character,
                target = entities[math.random(1, #entities)],
                speed = 1,
                quality = QUALITY_NAMES[q_idx or 1]
            })
        end
    end
    return true
end

local function zdfs2(player, q_idx)
    if check_tick(player, 'zdfs2') then
        local position = player.physical_position
        local entities = EntityCache.find_entities_cached(player.physical_surface, {
            position = position,
            type = goal,
            radius = 27,
            force = game.forces.enemy
        })

        for i = 1, 2, 1 do
            if #entities ~= 0 then
                local index = math.random(1, #entities)
                local target = entities[index]
                if target and target.valid and target.health then
                    if target.health > 0 then
                        local e = player.physical_surface.create_entity({
                            name = 'explosive-rocket',
                            position = position,
                            force = 'player',
                            source = player.character,
                            target = target,
                            speed = 1,
                            player = player,
                            quality = QUALITY_NAMES[q_idx or 1]

                        })
                    end
                end
                table.remove(entities, index)
            end
        end
    end
    return true
end



local function kejigongsi(player, q_idx)
    if check_tick(player, 'kejigongsi') then
        -- 获取已研发科技数量
        local main_table=WPT.get()
        local researched_count=main_table.science
        -- 计算金币奖励：科技数量 * 3.5
        local gold_reward = math.floor(researched_count * 3.5 * COEFF_REG[q_idx])
        
        if gold_reward > 0 then
            insert_item_to_player(player, 'coin', gold_reward)
            new_print(player, { 'tianfu.kejigongsi_over', researched_count, gold_reward })
        end
    end
    return true
end

local function jingong(player, q_idx)
    if check_tick(player, 'jingong') then
        insert_item_to_player(player, 'destroyer-capsule', 1, QUALITY_NAMES[q_idx])
        new_print(player, { 'tianfu.jingong_over' })
    end

    return true
end

local function hd(player, q_idx)
    if check_tick(player, 'hd') then
        local something = player.get_inventory(defines.inventory.character_guns)
        -- 检查inventory是否存在且有效
        if not something then
            return
        end
        for _, item_data in pairs(something.get_contents()) do
            player.remove_item {
                name = item_data.name,
                count = item_data.count,
                quality = item_data.quality
            }
        end

        local rpg_t = rpgtable.get('rpg_t')
        rpg_t[player.index].vitality = 10

        local all = 0
        local k = 0
        for l, playerl in pairs(game.connected_players) do
            if playerl.character and playerl.character.valid then
                k = playerl.character.get_item_count('coin')
                all = all + k
                k = 0
            end
        end
        -- all=100
        -- game.print('all'..all)
        local count = math.floor(all * 0.05 * COEFF_REG[q_idx])
        if count >= 50000 then
            count = 50000
        end
        if count > 1 then
            insert_item_to_player(player, 'coin', count)
            new_print(player, { 'tianfu.hd_over', count })
        end
    end
    return true
end

local function fali(player, q_idx)
    if check_tick(player, 'fali') then
        local rpg_t = rpgtable.get('rpg_t')
        local player_position = player.physical_position
        local count = 0
        
        for l, target_player in pairs(game.connected_players) do
            if count >= 5 then break end
            -- 计算距离，只对50米内的玩家生效
            --只有玩家图层一致才生效
            if target_player.surface == player.surface then
                local distance = math.sqrt(
                    (target_player.physical_position.x - player_position.x)^2 + 
                    (target_player.physical_position.y - player_position.y)^2
                )
                
                if distance <= 50 and rpg_t[target_player.index].mana ~= rpg_t[target_player.index].mana_max then
                rpg_t[target_player.index].mana = math.floor(rpg_t[target_player.index].mana * 1.05 * COEFF_LOW[q_idx])
                count = count + 1
            end
        end
        
        end
        -- new_print({'tianfu.fali_over',player.name})
    end
    return true
end

local function juqichengjian(player, q_idx)
    if check_tick(player, 'juqichengjian') then
        local rpg_t = rpgtable.get('rpg_t')
        local player_index = player.index
        
        local current_mana = rpg_t[player_index].mana or 0
        local mana_cost = math.floor(current_mana * 0.1)
        
        if mana_cost > 1 then
           
            
            local level = rpg_t[player_index].level
            local magic = rpg_t[player_index].magicka or 0
            local damage = (mana_cost + level + math.floor(magic * 0.1)) * COEFF_REG[q_idx]
            
            local surface = player.physical_surface
            local enemies = surface.find_entities_filtered({
                position = player.physical_position,
                radius = 4,
                force = game.forces.enemy,
                type = goal
            })
            
            if #enemies > 0 then
                rpg_t[player_index].mana = current_mana - mana_cost
                table.sort(enemies, function(a, b)
                    local dist_a = (a and a.valid) and
                    ((a.position.x - player.physical_position.x) ^ 2 + (a.position.y - player.physical_position.y) ^ 2) or math.huge
                    local dist_b = (b and b.valid) and
                    ((b.position.x - player.physical_position.x) ^ 2 + (b.position.y - player.physical_position.y) ^ 2) or math.huge
                    return dist_a < dist_b
                end)
                
                local max_targets = math.min(#enemies, 5)
                for i = 1, max_targets do
                    local target = enemies[i]
                    if target.valid then
                        surface.create_entity({
                            name = 'electric-beam',
                            position = player.physical_position,
                            target = target,
                            source = player.character,
                            duration = 10
                        })
                        
                        deal_damage_with_floating_text(target, player, damage, 'laser')
                    end
                end
            end
        end
    end
    return true
end

Public.juqichengjian = juqichengjian

local function carxiu(player, q_idx)
    if check_tick(player, 'carxiu') then
        local position = player.physical_position
        local entities = player.physical_surface.find_entities_filtered {
            name = car_name,
            force = player.force,
            area = { { position.x - 3, position.y - 3 }, { position.x + 3, position.y + 3 } }
        }
        local count = 0
        for i = 1, #entities do
            local e = entities[i]
            if e.max_health ~= e.health then
                e.health = e.health + e.max_health * 0.05 * COEFF_LOW[q_idx]
            end
        end
        if #entities ~= 0 then
            new_print(player, { 'tianfu.carxiu_over' })
        end
    end
    return true
end

local function ftlt(player, q_idx)
    if check_tick(player, 'ftlt') then
        local all = 100
        local t = math.random(30, 45)
        
        -- 检查玩家已有物品数量
        local current_iron = player.get_item_count("iron-plate")
        local current_copper = player.get_item_count("copper-plate")
        
        -- 只有当铁板数量不超过200时才给予铁板奖励
        if current_iron <= 200 then
            insert_item_to_player(player, 'iron-plate', math.floor((all - t) * COEFF_REG[q_idx]))
        end
        
        -- 只有当铜板数量不超过200时才给予铜板奖励
        if current_copper <= 200 then
            insert_item_to_player(player, 'copper-plate', math.floor(t * COEFF_REG[q_idx]))
        end
        
        new_print(player, { 'tianfu.ftlt_over', all - t, t })
    end
    return true
end

local function tdlx(player, q_idx)
    if check_tick(player, 'tdlx') then
        local players = game.connected_players
        local count = #players
        local xp = #players * 5 * COEFF_LOW[q_idx]

        local rpg_t = rpgtable.get('rpg_t')
        rpg_t[player.index].xp = rpg_t[player.index].xp + xp

        new_print(player, { 'tianfu.tdlx_over', xp })
    end
    return true
end

local function fangshou(player, q_idx)
    if check_tick(player, 'fangshou') then
        -- 获取玩家的敏捷属性
        local rpg_t = rpgtable.get('rpg_t')
        local agility = rpg_t[player.index].dexterity

        -- 计算倍数：基础为1，每250敏捷加1倍
        local multiplier = 1 + math.floor(agility / 250)
        if multiplier > 3 then
            multiplier = 3
        end

        -- 计算最终数量
        local magazine_count = 20 * multiplier
        local turret_count = 2 * multiplier
        
        -- 检查玩家当前的机枪炮塔和子弹数量
        local current_turret_count = player.get_item_count('gun-turret')
        local current_magazine_count = player.get_item_count('firearm-magazine')
        
        local given_turret = 0
        local given_magazine = 0
        
        -- 只有在机枪炮塔少于50个时才给予机枪炮塔
        if current_turret_count < 50 then
            insert_item_to_player(player, 'gun-turret', turret_count, QUALITY_NAMES[q_idx])
            given_turret = turret_count
        end
        
        -- 只有在子弹少于600发时才给予子弹
        if current_magazine_count < 600 then
            insert_item_to_player(player, 'firearm-magazine', magazine_count, QUALITY_NAMES[q_idx])
            given_magazine = magazine_count
        end
        
        -- 只有在实际给予了物品时才显示消息
        if given_turret > 0 or given_magazine > 0 then
            -- 如果有倍数加成，显示带有倍数信息的消息
            if multiplier > 1 then
                new_print(player, { 'tianfu.fangshou_over_bonus', multiplier, given_turret, given_magazine })
            else
                new_print(player, { 'tianfu.fangshou_over' })
            end
        end
    end
    return true
end

local function dianluban(player, q_idx)
    if check_tick(player, 'dianluban') then
        -- 获取玩家的敏捷属性
        local rpg_t = rpgtable.get('rpg_t')
        local agility = rpg_t[player.index].dexterity

        -- 计算倍数：基础为1，每300敏捷加1倍
        local multiplier = 1 + math.floor(agility / 300)

        -- 计算最终数量
        local iron_count = 6 * multiplier
        local copper_count = 18 * multiplier

        -- 检查玩家已有物品数量
        local current_iron = player.get_item_count("iron-plate")
        local current_copper = player.get_item_count("copper-cable")
        
        -- 只有当铁板数量不超过200时才给予铁板奖励
        if current_iron <= 400 then
            insert_item_to_player(player, 'iron-plate', math.floor(iron_count * COEFF_REG[q_idx]))
        end
        
        -- 只有当铜线数量不超过200时才给予铜线奖励
        if current_copper <= 400 then
            insert_item_to_player(player, 'copper-cable', math.floor(copper_count * COEFF_REG[q_idx]))
        end

        -- 如果有倍数加成，显示消息
        if multiplier > 1 then
            new_print(player, { 'tianfu.dianluban_over', multiplier, iron_count, copper_count })
        end
    end
    return true
end

local function xueqiu(player, q_idx)
    if check_tick(player, 'xueqiu') then
        local rpg_t = rpgtable.get('rpg_t')
        rpg_t[player.index].xp = rpg_t[player.index].xp + math.floor(2 * COEFF_LOW[q_idx] + 0.5)
    end
    return true
end

local function jiguang(player, q_idx)
    if check_tick(player, 'jiguang') then
        -- 基础获得1个激光炮塔
        local count = 1
        -- 获取玩家的敏捷属性
        local rpg_t = rpgtable.get('rpg_t')
        if rpg_t[player.index] then
            local dexterity = rpg_t[player.index].dexterity or 0
            -- 每200敏捷增加1个额外的激光炮塔
            count = count + math.floor(dexterity / 300)
        end
        insert_item_to_player(player, 'laser-turret', count, QUALITY_NAMES[q_idx])
        -- 如果获得多个，显示不同的提示信息
        if count > 1 then
            new_print(player, { 'tianfu.jiguang_over_multiple', count })
        else
            new_print(player, { 'tianfu.jiguang_over' })
        end
    end
    return true
end

local function wudi(player, q_idx)
    if math.random(1, 7) ~= 1 then
        return true
    end
    if check_tick(player, 'wudi') then
        player.character.destructible = false
        Task.set_timeout_in_ticks(math.floor(60 * 3 * COEFF_REG[q_idx]), un_wudi, player)
        new_print(player, { 'tianfu.wudi_over' })
    end
    return true
end

local function pailei(player, q_idx)
    if check_tick(player, 'pailei') then
        local entities = player.physical_surface.find_entities_filtered {
            position = player.physical_position,
            radius = 20,
            name = "land-mine",
            force = game.forces.enemy
        }
        if #entities ~= 0 then
            for k, v in pairs(entities) do
                v.destroy()
            end
            insert_item_to_player(player, 'coin', math.floor(#entities * 500 * COEFF_REG[q_idx]))
            new_print(player, { 'tianfu.pailei_over', math.floor(#entities * 500 * COEFF_REG[q_idx]) })
        end
    end
    return true
end

local function sansan(player, q_idx)
    if check_tick(player, 'sansan') then
        -- 获取玩家的敏捷属性
        local rpg_t = rpgtable.get('rpg_t')
        local dexterity = rpg_t[player.index].dexterity or 0
        -- 计算重复次数：基础1次 + 每300点敏捷多1次
        local repeat_times = 1 + math.floor(dexterity / 300)

        for i = 1, repeat_times do
            -- 1. 子弹合成：30个相同的子弹升级为更高品质的10个子弹
            local bullet_types = {
                "firearm-magazine",         -- 基础子弹
                "piercing-rounds-magazine", -- 穿甲弹
                "uranium-rounds-magazine"   -- 铀弹
            }

            -- 创建可升级的子弹池
            local upgradable_bullets = {}
            for j = 1, #bullet_types - 1 do -- 排除最高级子弹
                if player.get_item_count(bullet_types[j]) >= 30 then
                    table.insert(upgradable_bullets, j)
                end
            end

            -- 随机选择一种可升级的子弹
            if #upgradable_bullets > 0 then
                local choice = upgradable_bullets[math.random(1, #upgradable_bullets)]
                local from_bullet = bullet_types[choice]
                local to_bullet = bullet_types[choice + 1]

                -- 消耗30个低级子弹，生成10个高级子弹
                player.remove_item {
                    name = from_bullet,
                    count = 30
                }
                insert_item_to_player(player, to_bullet, 10, QUALITY_NAMES[q_idx])
            end

            -- 2. 霰弹合成：30发霰弹合成为10发穿甲霰弹
            if player.get_item_count("shotgun-shell") >= 30 then
                player.remove_item {
                    name = "shotgun-shell",
                    count = 30
                }
                insert_item_to_player(player, 'piercing-shotgun-shell', 10, QUALITY_NAMES[q_idx])
            end

            -- 3. 火箭弹合成：9个标准火箭弹合并成3个爆破火箭弹
            if player.get_item_count("rocket") >= 9 then
                player.remove_item {
                    name = "rocket",
                    count = 9
                }
                insert_item_to_player(player, 'explosive-rocket', 3, QUALITY_NAMES[q_idx])
            end
        end
    end
    return true
end

local function mlst(player, q_idx)
    if check_tick(player, 'mlst') then
        local rpg_t = rpgtable.get('rpg_t')
        local k = math.floor(rpg_t[player.index].magicka / 200) + 1
        if k <= 1 then
            k = 1
        end
        if k >= 5 then
            k = 5
        end
        local mlst_gain = TianfuQuality.qround(k * COEFF_LOW[q_idx])
        rpg_t[player.index].vitality = rpg_t[player.index].vitality + mlst_gain
        new_print(player, { 'tianfu.mlst_over', mlst_gain })
    end
    return true
end

local function xxyd(player, q_idx)
    if check_tick(player, 'xxyd') then
        local rpg_t = rpgtable.get('rpg_t')
        local k = math.floor(rpg_t[player.index].vitality / 200) + 1
        if k <= 1 then
            k = 1
        end
        if k >= 5 then
            k = 5
        end
        local xxyd_gain = TianfuQuality.qround(k * COEFF_LOW[q_idx])
        rpg_t[player.index].magicka = rpg_t[player.index].magicka + xxyd_gain
        new_print(player, { 'tianfu.xxyd_over', xxyd_gain })
    end
    return true
end

local function morefali(player, q_idx)
    if check_tick(player, 'morefali') then
        local rpg_t = rpgtable.get('rpg_t')
        local coin = 0
        local huifu = math.floor(rpg_t[player.index].mana_max * 0.3 * COEFF_LOW[q_idx])
        if rpg_t[player.index].mana + huifu > rpg_t[player.index].mana_max then
            coin = rpg_t[player.index].mana + huifu - rpg_t[player.index].mana_max
            coin = math.floor(coin * 0.5)
            rpg_t[player.index].mana = rpg_t[player.index].mana
            rpg_t[player.index].xp = rpg_t[player.index].xp + coin
        else
            rpg_t[player.index].mana = rpg_t[player.index].mana + huifu
        end
        new_print(player, { 'tianfu.morefali_over', coin })
    end
end

local function rlfdz(player, q_idx)
    --判断冷却时间是否到了
    if check_tick(player, 'rlfdz') then
        insert_item_to_player(player, 'accumulator', 3, QUALITY_NAMES[q_idx])
    end
    return true
end

local function yuer(player, q_idx)
    if check_tick(player, 'yuer') then
        local rpg_t = rpgtable.get('rpg_t')
        local position = player.physical_position
        --每有200点法力就额外给一条鱼
        local extra_fish = math.floor(rpg_t[player.index].magicka / 300) + 1

        local entities = player.physical_surface.find_entities_filtered({
            position = position,
            radius = 33,
            type = 'corpse'
        })
        local i = 0
        if #entities == 0 then
            return false
        end
        for _, entity in pairs(entities) do

                entity.destroy()
                i = i + 1
          
        end

        -- 计算鱼的数量，使用变量代替固定值
        --每有30个尸体就给一条鱼
        local k = math.floor(i / 35)
        local total_fish = extra_fish * k
        if total_fish ~= 0 then
            insert_item_to_player(player, 'raw-fish', math.floor(total_fish * COEFF_REG[q_idx]))

            new_print(player, { 'tianfu.yuer_over', math.floor(total_fish * COEFF_REG[q_idx]) })
        end
        -- 给玩家添加鱼

        return true
    end
end

local function shen_fa(player, q_idx)
  
    if check_tick(player, 'shen_fa') then
      
        -- 基于玩家魔力计算伤害
        local rpg_t = rpgtable.get('rpg_t')
        local magic_power = rpg_t[player.index].magicka or 0
        local times = upgrade_spell(player, "lightning_chain", { 'spells.lightning_chain' }, true)

        -- 变量：基于魔力的伤害系数
        local damage_per_magic = 0.3      -- 每点魔力增加的伤害
        local base_damage = 20 + times * 10 -- 基础伤害+

        -- 计算总伤害：基础伤害 + (魔力/10)*额外伤害
        local magic_bonus = math.floor(magic_power) * damage_per_magic
        local total_damage = (base_damage + magic_bonus) * COEFF_REG[q_idx]

        -- 查找周围的敌对虫子
        local surface = player.physical_surface
        local enemies = EntityCache.find_entities_cached(surface, {
            position = player.physical_position,
            radius = 20,
            force = game.forces.enemy,
            type = goal
        })

        if #enemies > 0 then
            -- 变量：最大攻击目标数量
            local max_targets = 15 -- 最多攻击的虫子数量

            -- 按血量排序敌人，优先选择血量最低的
            table.sort(enemies, function(a, b)
                -- 安全检查，确保实体有效且有health属性
                local health_a = (a and a.valid and a.health) and a.health or 0
                local health_b = (b and b.valid and b.health) and b.health or 0
                return health_a < health_b
            end)

            -- 限制目标数量
            local targets = {}
            for i = 1, math.min(#enemies, max_targets) do
                table.insert(targets, enemies[i])
            end

            -- 分配伤害直到杀死虫子，多余伤害传递给下一个目标
            local remaining_damage = total_damage
            local total_dealt_damage = 0

            for _, enemy in pairs(targets) do
                if enemy.valid then
                    -- 创建视觉效果
                    surface.create_entity({
                        name = 'electric-beam',
                        position = player.physical_position,
                        target = enemy.position,
                        source = player.physical_position,
                        duration = 20
                    })

                    remaining_damage = remaining_damage * 0.8
                    deal_damage_with_floating_text(enemy, player, remaining_damage, 'electric')
                    total_dealt_damage = total_dealt_damage + remaining_damage
                    
                    if remaining_damage <= total_damage * 0.4 then
                        remaining_damage = total_damage * 0.4
                    end
                end
            end

            new_print(player, { 'tianfu.shen_fa_over', math.floor(total_dealt_damage) })
        end

        return true
    end
end
     local lava_eruption_task = Token.register(function(data)
                    local target = data.target
                    local target_pos = data.target_pos
                    local surface = data.surface
                    local player = data.player
                    local magic_power = data.magic_power
           
                    
                        -- 在目标周围造成范围伤害
                        local area_enemies = EntityCache.find_entities_cached(surface, {
                            position = target_pos,
                            radius = 7,
                            force = game.forces.enemy,
                            type = goal
                        })
                        
                        -- 计算范围伤害（基于魔力值）
                        local area_damage = (50 + math.floor(magic_power / 2)) * COEFF_REG[data.q_idx]
                        
                        for _, enemy in pairs(area_enemies) do
                            if enemy.valid then
                                deal_damage_with_floating_text(enemy, player, area_damage, 'fire')
                            end
                        end
                   
                end)
local function diyu_rongyan(player, q_idx)
    if check_tick(player, 'diyu_rongyan') then
        local surface = player.physical_surface
        local position = player.physical_position
        local times = upgrade_spell(player, "huanxing_huoshan_penfa", { 'spells.huanxing_huoshan_penfa' }, true)
        -- 搜寻附近的敌方虫子
        local enemies = EntityCache.find_entities_cached(surface, {
            position = position,
            radius = 20,
            force = game.forces.enemy,
            type = goal
        })
        
        if #enemies > 0 then
            -- 随机选择一个敌人
            local target = enemies[math.random(1, #enemies)]
            
            local target_pos = target.position
            local rpg_t = rpgtable.get('rpg_t')
            local magic_power = rpg_t[player.index].magicka or 0
            
            -- 创建熔岩效果（使用火焰云效果）
            local lava_effect = surface.create_entity({
                name = 'small-demolisher-fissure',
                position = target_pos,
                force = player.force,
                 source = player.character,
                 player = player
            })
            
            -- 立刻对目标周围2米内所有虫子造成微量伤害（基于魔力值）
            local immediate_enemies = EntityCache.find_entities_cached(surface, {
                position = target_pos,
                radius = 2,
                force = game.forces.enemy,
                type = goal
            })
            
            local immediate_damage = (10 + math.floor(magic_power / 10) + times * 5) * COEFF_REG[q_idx]
            local immediate_killed_count = 0
            
            for _, enemy in pairs(immediate_enemies) do
                -- 对每个敌人造成伤害
                deal_damage_with_floating_text(enemy, player, immediate_damage, 'fire')
            end
            
            -- 注册2秒后的延迟任务
       
            
            -- 2秒后执行（120 ticks）
            Task.set_timeout_in_ticks(100, lava_eruption_task, {
                target = target,
                target_pos = target_pos,
                surface = surface,
                player = player,
                magic_power = magic_power,
                q_idx = q_idx
            })
            new_print(player, { 'tianfu.diyu_rongyan_over' })
        end
        
        return true
    end
end

local function lanhuangjiaonang(player, q_idx)
    --检查冷却时间
    if not check_tick(player, 'lanhuangjiaonang') then
        return false
    end

    -- 随机决定是减速胶囊还是剧毒胶囊
    local capsule_type
    if math.random(1, 2) == 1 then
        capsule_type = 'slowdown-capsule' -- 减速胶囊
    else
        capsule_type = 'poison-capsule'   -- 剧毒胶囊
    end

    -- 检查玩家背包内对应胶囊数量是否超过200
    local current_count = player.get_item_count(capsule_type)
    if current_count >= 200 then
        return false
    end

    -- 给予玩家1个胶囊
    insert_item_to_player(player, capsule_type, 1, QUALITY_NAMES[q_idx])
 
    new_print(player, { 'tianfu.lanhuangjiaonang_over', 1 })
    return true
end

local function zishenzhuanjia(player, q_idx)
    if not check_tick(player, 'zishenzhuanjia') then return false end
    if math.random(1, 100) > math.floor(10 * COEFF_REG[q_idx]) then return false end
    
    local surface = player.physical_surface
    local position = player.physical_position
    local search_radius = 24
    
    local production_buildings = surface.find_entities_filtered({
        position = position,
        radius = search_radius,
        force = game.forces.player,
        type = {'assembling-machine', 'furnace', 'chemical-plant', 'oil-refinery', 'mining-drill'}
    })
    
    if #production_buildings == 0 then return false end
    
    local target_building = production_buildings[math.random(1, #production_buildings)]
    if not target_building or not target_building.valid then return false end
    
    -- 检查建筑是否可以挖掘，如果不能则跳过
    if not target_building.minable_flag then return false end
    
    -- 获取当前品质
    local current_quality = target_building.quality.name
    local quality_order = {"normal", "uncommon", "rare", "epic", "legendary"}
    local current_quality_index = 0
    for i, q in ipairs(quality_order) do
        if q == current_quality then current_quality_index = i break end
    end
    
    if current_quality_index >= #quality_order then return false end
    
    -- 随机目标品质
    local quality_upgrades = {
        {name = "legendary", chance = 5},
        {name = "epic", chance = 15},
        {name = "rare", chance = 25},
        {name = "uncommon", chance = 40}
    }
    
    local upgraded_quality = nil
    local random_roll = math.random(1, 100)
    local current_threshold = 0
    for _, item in ipairs(quality_upgrades) do
        current_threshold = current_threshold + item.chance
        if random_roll <= current_threshold then
            upgraded_quality = item.name
            break
        end
    end
    
    if not upgraded_quality then return false end
    
    -- 确保是提升而非降级
    local upgraded_quality_index = 0
    for i, q in ipairs(quality_order) do
        if q == upgraded_quality then upgraded_quality_index = i break end
    end
    if upgraded_quality_index <= current_quality_index then return false end

    -- --- 核心修复：保存所有状态 ---
    local b_name = target_building.name
    local b_pos = target_building.position
    local b_dir = target_building.direction
    local b_force = target_building.force
    
    -- 只保存配方名称（字符串），不保存对象
    local recipe_name = nil
    if target_building.type == "assembling-machine" then
        local r = target_building.get_recipe()
        if r then
            recipe_name = r.name
        end
    elseif target_building.type == "furnace" then
        local r = target_building.get_recipe()
        if r then
            recipe_name = r.name
        end
    end
    
    -- 通用库存保存逻辑 (涵盖模块、输入、输出)
    local all_inventories = {}
    for i = 1, 10 do -- 遍历可能的库存索引
        local inv = target_building.get_inventory(i)
        if inv then
            all_inventories[i] = inv.get_contents()
        end
    end

    -- 销毁旧建筑
    target_building.destroy()
    
    -- 创建新建筑
    local new_building = surface.create_entity({
        name = b_name,
        position = b_pos,
        direction = b_dir,
        force = b_force,
        quality = upgraded_quality,
        fast_replace = true, -- 尽量尝试快速替换以保留部分连接
        raise_built = true
    })
    
    if new_building and new_building.valid then
        -- 在还原库存前设置配方
        if recipe_name then
            local success, err = pcall(function()
                new_building.set_recipe(recipe_name)
            end)
            
            if not success then
                -- 设置配方失败，通常是因为该建筑不支持此配方
            end
        end
        
        -- 设置完配方后，再还原物品和模块
        for inv_index, contents in pairs(all_inventories) do
            local new_inv = new_building.get_inventory(inv_index)
            if new_inv then
                for _, item in ipairs(contents) do
                    new_inv.insert(item)
                end
            end
        end
        
        new_print(player, {'tianfu.zishenzhuanjia_success', b_name, upgraded_quality})
        return true
    end
    
    return false
end

local function daodaoku(player, q_idx)
    -- 检查冷却时间
    if not check_tick(player, 'daodaoku') then
        return false
    end

    -- 获取玩家力量属性
    local rpg_t = rpgtable.get('rpg_t')
    local strength = rpg_t[player.index].strength or 1

    -- 获取玩家的【武器栏】而不是【主背包】
    local inventory = player.get_inventory(defines.inventory.character_guns)
    
    -- 安全检查：如果玩家处于上帝模式或无实体状态，可能没有背包
    if not inventory then
        return true
    end

    local has_rocket_launcher = false

    -- 遍历所有武器槽位（通常是3个），只要发现一个火箭筒就算拥有
    for i = 1, #inventory do
        local stack = inventory[i]
        if stack and stack.valid_for_read and stack.name == 'rocket-launcher' then
            has_rocket_launcher = true
            break -- 找到了就停止循环
        end
    end

    if not has_rocket_launcher then
        -- 如果没有装备火箭筒，则给予火箭筒
        insert_item_to_player(player, 'rocket-launcher', 1, QUALITY_NAMES[q_idx])
        new_print(player, { 'tianfu.daodaoku_over', 1 })
    else
        -- 如果已经装备火箭筒，则给予导弹
        -- 根据力量计算获得的导弹数量：每30秒获得1个，每300力量多获得1个，上限10个
        local count = 1 + math.floor(strength / 300)
        count = math.min(count, 20)  -- 上限20个

        -- 随机决定是普通导弹还是红导弹
        local missile_type
        if math.random(1, 2) == 1 then
            missile_type = 'rocket'           -- 导弹
        else
            missile_type = 'explosive-rocket' -- 红导弹
        end

        -- 给予玩家导弹
        insert_item_to_player(player, missile_type, count, QUALITY_NAMES[q_idx])

        new_print(player, { 'tianfu.daodaoku_over', count })
    end
    
    return true
end


-- 霰弹合成触发函数
local function xiandanhecheng(player, q_idx)

    -- 检查冷却时间
    if not check_tick(player, 'xiandanhecheng') then
        return false
    end

    -- 获取玩家敏捷属性
    local rpg_t = rpgtable.get('rpg_t')
    local dexterity = rpg_t[player.index].dexterity or 1

    -- 检查玩家是否有霰弹
    local shotgun_shell_stack = player.get_item_count('shotgun-shell')
    if shotgun_shell_stack <= 0 then
        return false
    end

    -- 根据敏捷计算合成次数：每30秒将3发霰弹合成为穿甲霰弹，每200敏捷多合成一次
    local craft_count = 1 + math.floor(dexterity / 200)

    -- 计算需要消耗的霰弹数量
    local required_shells = craft_count * 3

    -- 检查是否有足够的霰弹
    if shotgun_shell_stack < required_shells then
        -- 调整合成数量为玩家拥有的霰弹能支持的最大次数
        craft_count = math.floor(shotgun_shell_stack / 3)
        if craft_count <= 0 then
            return false
        end
        required_shells = craft_count * 3
    end

    -- 移除原霰弹并添加穿甲霰弹
    player.remove_item {
        name = 'shotgun-shell',
        count = required_shells
    }
    insert_item_to_player(player, 'piercing-shotgun-shell', craft_count, QUALITY_NAMES[q_idx])

    new_print(player, { 'tianfu.xiandanhecheng_over', craft_count })
    return true
end
local function hushenfu(player, q_idx)
    local this = TPT.get()
    if check_tick(player, 'hushenfu') then
        if not player.character or not player.character.valid then
            return true
        end

        -- 确保护盾数据结构存在
        if not this.hushenfu_shield then
            this.hushenfu_shield = {}
        end
        if not this.hushenfu_shield[player.index] then
            this.hushenfu_shield[player.index] = 0
        end

        local actual_max_health = player.character.max_health
        local limited_max_health = math.min(actual_max_health, 30000)
        local current_health = player.character.health
        local heal_amount = limited_max_health * 0.1 * COEFF_LOW[q_idx] -- 10%限制后最大生命值
        local max_shield = limited_max_health * 0.5  -- 最大护盾为限制后最大生命值的50%

        -- 计算治疗效果
        if current_health + heal_amount > actual_max_health then
            -- 治疗溢出，转化为护盾
            local overflow = current_health + heal_amount - actual_max_health
            player.character.health = actual_max_health

            -- 添加护盾，不超过最大护盾值
            this.hushenfu_shield[player.index] = math.min(this.hushenfu_shield[player.index] + overflow, max_shield)
            new_print(player,
                { 'tianfu.hushenfu_over', math.floor(heal_amount), math.floor(this.hushenfu_shield[player.index]) })
        else
            -- 直接治疗
            player.character.health = current_health + heal_amount
            new_print(player,
                { 'tianfu.hushenfu_over', math.floor(heal_amount), math.floor(this.hushenfu_shield[player.index]) })
        end
    end
    return true
end

-- 灼烧技能实现
local function zhuoshao(player, q_idx)
    if not check_tick(player, 'zhuoshao') then
        return false
    end
     local huo_dun_level = upgrade_spell(player, "huo_dun", { 'spells.huo_dun' }, true)
    if not player.character or not player.character.valid then
        return false
    end

    -- 查找半径16米内的敌方虫子
    local enemies = EntityCache.find_entities_cached(player.physical_surface, {
        position = player.physical_position,
        radius = 20,
        type = goal,
        force = game.forces.enemy
    })

    if #enemies == 0 then
        return false
    end

    local target = enemies[1]
    -- 获取火遁技能等级（使用upgrade_spell函数，会自动升级）
   
    
    -- 基础伤害15点，每级+5点
    local base_damage = 15
    local bonus_damage =huo_dun_level * 4  -- 每20次升级增加5点伤害
    local total_damage = (base_damage + bonus_damage) * COEFF_REG[q_idx]
    
    -- 对目标周围0.5半径内的所有敌方单位造成伤害
    local splash_targets = EntityCache.find_entities_cached(player.physical_surface, {
        position = target.position,
        radius = 2,
        type = goal,
        force = game.forces.enemy
    })
    
    -- 创建火焰效果并造成伤害
    for _, entity in pairs(splash_targets) do
        if entity and entity.valid then
            -- 创建火焰投射物效果
            player.physical_surface.create_entity{
                name = 'fire-flame',
                position = entity.position,
                force = 'player'
            }
            
            -- 造成伤害 - 使用正确的参数格式让玩家获得奖励
            deal_damage_with_floating_text(entity, player, total_damage, 'fire')
        end
    end
    
    new_print(player, {'tianfu.zhuoshao_over', #splash_targets, total_damage})
    return true
end

-- 贴身护卫技能实现
local function tieshenhuwei(player, q_idx)
    if not check_tick(player, 'tieshenhuwei') then
        return false
    end

    local ammo_name = upgrade_spell(player, "wudi_turret", { 'spells.wudi_turret' }, false)
    
    if not player.character or not player.character.valid then
        return false
    end

    -- 查找半径16米内的敌方虫子
    local enemies = EntityCache.find_entities_cached(player.physical_surface, {
        position = player.physical_position,
        radius = 16,
        type = goal,
        force = game.forces.enemy,
        limit = 1
    })

    -- 如果没有发现敌人，不召唤炮塔
    if #enemies == 0 then
        return false
    end

    -- 创建无敌炮塔
    local forces = {}
    local surface = player.physical_surface
    local position = player.physical_position
    
    -- 获取弹药类型（参考dgwd函数的逻辑）
    
    
    local turret = surface.create_entity {
        name = "gun-turret",
        quality = QUALITY_NAMES[q_idx],
        position = surface.find_non_colliding_position("gun-turret", {
            x = position.x + math.random(-8, 8),
            y = position.y + math.random(-8, 8)
        }, 15, 1, true),
        force = game.forces.player
    }
    
    if turret and turret.valid then
        turret.insert {
            name = ammo_name,
            count = 10
        }
        turret.destructible = false
        turret.minable_flag = false
        turret.operable = false
        turret.last_user = player
        
        local main_table = WPT.get()
        main_table.turret_rpg[#main_table.turret_rpg + 1] = turret
        forces[#forces + 1] = turret
        
        -- 11秒后销毁炮塔
        Task.set_timeout_in_ticks(60 * 11, kill_forces, forces)
        
        new_print(player, {'tianfu.tieshenhuwei_over'})
        return true
    end
    
    return false
end

-- 水护符充能恢复技能实现
local function shui_hu_fu(player, q_idx)
    if not check_tick(player, 'shui_hu_fu') then
        return false
    end

    local this = TPT.get()
    local times = upgrade_spell(player, "shui_long_dan", {'spells.shui_long_dan'}, true)
    -- 确保充能数据结构存在
    if not this.shui_hu_fu_charge then
        this.shui_hu_fu_charge = {}
    end
    if not this.shui_hu_fu_charge[player.index] then
        this.shui_hu_fu_charge[player.index] = 0
    end

    -- 每30秒获得充能（品质越高充能越多），最多3层
    if this.shui_hu_fu_charge[player.index] < 3 then
        local charge_gain = ({1, 1, 2, 2, 3})[q_idx or 1]
        this.shui_hu_fu_charge[player.index] = math.min(3, this.shui_hu_fu_charge[player.index] + charge_gain)
        
        -- 显示充能获得提示
        new_print(player, {'tianfu.shui_hu_fu_charge', this.shui_hu_fu_charge[player.index]})
        return true
    end
    
    return false
end

-- 水遁天赋：每10秒释放一次劣化版水龙弹
-- 水遁天赋：每10秒释放一次劣化版水龙弹
local function shui_dun(player, q_idx)
    -- 1. 基础检查
    if not check_tick(player, 'shui_dun') then
        return false
    end
    local times = upgrade_spell(player, "shui_long_dan", {'spells.shui_long_dan'}, true)
    if not player.character or not player.character.valid then
        return false
    end
    
    local surface = player.physical_surface
    local player_pos = player.physical_position
    
    -- 2. 寻找敌人 (使用缓存搜索)
    local nearby_enemies = EntityCache.find_entities_cached(surface, {
        position = player_pos,
        radius = 27,
        force = 'enemy',
        type = {'unit', 'spider-unit'}
    })
    
    if #nearby_enemies == 0 then
        return false  -- 周围没有敌人，不释放，也就没有视觉效果
    end
    
    -- 3. 随机选择一个敌人作为目标
    local target_enemy = nearby_enemies[math.random(#nearby_enemies)]
    
    if not target_enemy or not target_enemy.valid then
        return false
    end
    
    -- 4. 获取属性 (使用与Code 2相同的安全方式，防止nil报错)
    local rpg_t = rpgtable.get('rpg_t')
    local magicka_bonus = rpg_t[player.index].magicka or 0
    
    -- 5. 参数设定
    local base_damage = (20 + magicka_bonus * 0.5 + times * 2) * COEFF_REG[q_idx]
    local water_radius = 2
    local knockback_distance = 2
    local target_position = target_enemy.position
    
    -- 计算路径
    local distance = math.sqrt(
        (target_position.x - player_pos.x)^2 + 
        (target_position.y - player_pos.y)^2
    )
    local steps = math.floor(distance * 2) + 1
    
    for i = 1, steps do
        local ratio = i / steps
        local path_x = player_pos.x + (target_position.x - player_pos.x) * ratio
        local path_y = player_pos.y + (target_position.y - player_pos.y) * ratio
        
        -- 在主路径上创建水柱效果
        surface.create_entity({
            name = 'water-splash', 
            position = {path_x, path_y},
            force = game.forces.player
        })
        
   -- 在水柱路径上寻找敌人（每3格寻找一次，半径为1）
    if i % 3 == 1 then
      local enemies = surface.find_entities_filtered({
        position = {x = path_x, y = path_y},
        radius = 1.5,
        force = 'enemy',
        type = {'unit', 'spider-unit'}
      })
      
      for _, enemy in pairs(enemies) do
        if enemy.valid and enemy.health then
          -- 造成伤害
          deal_damage_with_floating_text(enemy, player, base_damage, 'laser')
          -- 击退效果 - 将水柱方向相反的方向推
        end
      end
    end
    end
    
    -- 提示
    if new_print then
        new_print(player, {'tianfu.shui_dun_cast'})
    end
    
    return true
end

-- 力大砖飞天赋实现
local function lidazhuanfei(player, q_idx)
    if not check_tick(player, 'lidazhuanfei') then
        return false
    end
    
    
    local surface = player.physical_surface
    local player_pos = player.physical_position
    
    -- 获取玩家属性
    local rpg_t = rpgtable.get('rpg_t')
    local strength = rpg_t[player.index].strength or 0
    
    -- 寻找4米内的敌人
    local nearby_enemies = surface.find_entities_filtered({
        position = player_pos,
        radius = 4,
        force = 'enemy',
        type = {'unit', 'spider-unit'}
    })
    
    if #nearby_enemies == 0 then
        return false
    end
    
    -- 筛选最近的敌人
    local closest_enemy = nil
    local min_distance = math.huge
    
    for _, enemy in pairs(nearby_enemies) do
        if enemy.valid and enemy.health then
            local distance = math.sqrt(
                (enemy.position.x - player_pos.x)^2 + 
                (enemy.position.y - player_pos.y)^2
            )
            if distance < min_distance then
                min_distance = distance
                closest_enemy = enemy
            end
        end
    end
    
    if not closest_enemy or not closest_enemy.valid then
        return false
    end
    
    -- 计算击飞方向（从玩家指向敌人）
    local knockback_direction = {
        x = closest_enemy.position.x - player_pos.x,
        y = closest_enemy.position.y - player_pos.y
    }
    
    -- 标准化方向向量
    local direction_length = math.sqrt(knockback_direction.x^2 + knockback_direction.y^2)
    if direction_length > 0 then
        knockback_direction.x = knockback_direction.x / direction_length
        knockback_direction.y = knockback_direction.y / direction_length
    end
    
    -- 计算击飞目标位置（20米）
    local knockback_target = {
        x = closest_enemy.position.x + knockback_direction.x * 20,
        y = closest_enemy.position.y + knockback_direction.y * 20
    }
    
    -- 计算路径点（用于沿途伤害和特效）
    local steps = 20
    local base_damage = strength * 0.2 * COEFF_REG[q_idx]
    
    for i = 1, steps do
        local ratio = i / steps
        local path_x = closest_enemy.position.x + (knockback_target.x - closest_enemy.position.x) * ratio
        local path_y = closest_enemy.position.y + (knockback_target.y - closest_enemy.position.y) * ratio
        
        -- 在路径上创建vulcanus-cliff-collapse特效
        surface.create_entity({
            name = 'vulcanus-cliff-collapse',
            position = {path_x, path_y},
            force = game.forces.player
        })
        
        -- 每3步寻找一次敌人
        if i % 3 == 0 then
            local path_enemies = EntityCache.find_entities_cached(surface, {
                position = {x = path_x, y = path_y},
                radius = 2,
                force = 'enemy',
                type = {'unit', 'spider-unit'}
            })
            
            for _, enemy in pairs(path_enemies) do
                if enemy.valid and enemy.health then
                    deal_damage_with_floating_text(enemy, player, base_damage, 'physical')
                end
            end
        end
    end
    
    -- 击飞最近的敌人
    if closest_enemy and closest_enemy.valid then
        local safe_position = surface.find_non_colliding_position(closest_enemy.name, knockback_target, 10, 0.5)
        if safe_position then
            closest_enemy.teleport(safe_position)
        end
        deal_damage_with_floating_text(closest_enemy, player, base_damage, 'physical')
    end
    
    -- 提示
    new_print(player, {'tianfu.lidazhuanfei_cast', math.floor(base_damage)})
    
    return true
end

Public.lidazhuanfei = lidazhuanfei
-- 传说宝藏技能实现
local function chuanqibaozang(player, q_idx)
    if not check_tick(player, 'chuanqibaozang') then
        return false
    end
    
    if not player.character or not player.character.valid then
        return false
    end

      if not script.active_mods['quality'] then
        return false
      end
    
    -- 获取玩家的魔法和敏捷属性
    local rpg_t = rpgtable.get('rpg_t')
    local magic = rpg_t[player.index].magicka or 0
    local dexterity = rpg_t[player.index].dexterity or 0

    --限制魔法最大3000、敏捷最大1000
    magic = math.min(magic, 3000)
    dexterity = math.min(dexterity, 1000)
    
    -- 定义武器类物品列表（基于basic_markets.lua的6个表，保留value和rarity属性）
    local weapon_items = {
        -- 【weapons表】枪械类武器
        {name = 'pistol', value = 10, rarity = 1},
        {name = 'submachine-gun', value = 50, rarity = 2},
        {name = 'shotgun', value = 40, rarity = 2},
        {name = 'tank-machine-gun', value = 600, rarity = 3},
        {name = 'combat-shotgun', value = 400, rarity = 5},
        {name = 'rocket-launcher', value = 500, rarity = 5},
        {name = 'land-mine', value = 10, rarity = 4},
        
        -- 【ammo表】弹药类
        {name = 'firearm-magazine', value = 3, rarity = 1},
        {name = 'piercing-rounds-magazine', value = 6, rarity = 4},
        {name = 'uranium-rounds-magazine', value = 20, rarity = 8},
        {name = 'shotgun-shell', value = 3, rarity = 1},
        {name = 'piercing-shotgun-shell', value = 8, rarity = 5},
        {name = 'cannon-shell', value = 8, rarity = 4},
        {name = 'explosive-cannon-shell', value = 12, rarity = 5},
        {name = 'uranium-cannon-shell', value = 16, rarity = 7},
        {name = 'explosive-uranium-cannon-shell', value = 20, rarity = 8},
        {name = 'artillery-shell', value = 64, rarity = 300},
        {name = 'rocket', value = 45, rarity = 7},
        {name = 'explosive-rocket', value = 50, rarity = 7},
        {name = 'atomic-bomb', value = 15000, rarity = 10},
        {name = 'flamethrower-ammo', value = 20, rarity = 6},
        
        -- 【caspules表】投掷类和胶囊类
        {name = 'grenade', value = 16, rarity = 2},
        {name = 'cluster-grenade', value = 55, rarity = 5},
        {name = 'poison-capsule', value = 28, rarity = 6},
        {name = 'slowdown-capsule', value = 8, rarity = 1},
        {name = 'defender-capsule', value = 10, rarity = 1},
        {name = 'distractor-capsule', value = 30, rarity = 3},
        {name = 'destroyer-capsule', value = 70, rarity = 5},
        
        -- 【armor表】护甲类（战斗相关）
        {name = 'light-armor', value = 25, rarity = 1},
        {name = 'heavy-armor', value = 250, rarity = 4},
        {name = 'modular-armor', value = 750, rarity = 5},
        {name = 'power-armor', value = 5000, rarity = 6},
        {name = 'power-armor-mk2', value = 35000, rarity = 10},
        
        -- 【equipment表】装备模块（战斗相关）
        {name = 'solar-panel-equipment', value = 240, rarity = 3},
        {name = 'fission-reactor-equipment', value = 9000, rarity = 7},
        {name = 'energy-shield-equipment', value = 400, rarity = 6},
        {name = 'energy-shield-mk2-equipment', value = 4000, rarity = 8},
        {name = 'battery-equipment', value = 160, rarity = 2},
        {name = 'battery-mk2-equipment', value = 5000, rarity = 8},
        {name = 'personal-laser-defense-equipment', value = 4000, rarity = 7},
        {name = 'discharge-defense-equipment', value = 7000, rarity = 8},
        {name = 'belt-immunity-equipment', value = 200, rarity = 1},
        {name = 'exoskeleton-equipment', value = 1000, rarity = 3},
        {name = 'personal-roboport-equipment', value = 1000, rarity = 3},
        {name = 'personal-roboport-mk2-equipment', value = 5000, rarity = 8},
        {name = 'night-vision-equipment', value = 250, rarity = 1},
        
        -- 【defense表】防御建筑（战斗相关）
        {name = 'stone-wall', value = 4, rarity = 1},
        {name = 'gate', value = 8, rarity = 1},
        {name = 'gun-turret', value = 64, rarity = 1},
        {name = 'laser-turret', value = 1024, rarity = 6},
        {name = 'artillery-turret', value = 15192, rarity = 8},
    }
    
    -- 获取玩家背包中的所有物品
    local main_inventory = player.get_inventory(defines.inventory.character_main)
    if not main_inventory then
    
        return false
    end
    
    local can_do=math.floor(dexterity/100)
    if can_do <=0 then 
        can_do=1
    end
    
    -- 查找背包中的武器类物品（同名物品只选择一个）
    local weapon_stacks = {}
    local found_weapon_names = {} -- 用于记录已经找到的武器名称
    
    for i = 1, #main_inventory do
        local stack = main_inventory[i]
        if stack.valid_for_read then
            -- 检查是否为武器类物品
            for _, weapon_item in ipairs(weapon_items) do
                if weapon_item.rarity <= can_do then
                    if stack.name == weapon_item.name then
                        -- 检查这个武器名称是否已经被记录
                        if not found_weapon_names[stack.name] then
                            -- 如果没有记录过，加入列表并标记为已找到
                            table.insert(weapon_stacks, {index = i, stack = stack, item_info = weapon_item})
                            found_weapon_names[stack.name] = true
                            break
                        end
                        -- 如果已经记录过同名武器，跳过这个物品
                    end
                end
            end
        end
    end
    
    -- 如果没有找到武器类物品，返回false
    if #weapon_stacks == 0 then
   
        return false
    end
    
    -- 随机选择一个武器物品
    local selected = weapon_stacks[math.random(1, #weapon_stacks)]
    local item_name = selected.stack.name
    local item_count = selected.stack.count
    local item_info = selected.item_info  -- 保留物品的value和rarity信息
    local current_quality = "normal"
    if selected.stack.quality and selected.stack.quality.name then
        current_quality = selected.stack.quality.name
    end
    
    -- 计算品质提升概率（与魔法属性挂钩）
    -- 基础概率：魔法属性每300点增加1%成功率
    local base_chance = math.min(magic / 600/100, 0.1)  -- 最高50%成功率
   
    local quality_upgrades = { 
        { name = "legendary", chance = 0.005 }, -- 1% 
        { name = "epic",      chance = 0.015 }, -- 3% 
        { name = "rare",      chance = 0.025 }, -- 5% 
        { name = "uncommon",  chance = 0.05 }  -- 10% 
    } 
    -- 注意：这里使用数组(table)来保证遍历顺序，因为普通的kv table遍历顺序是不确定的 
    
    -- 假设的基础概率加成（防止报错，这里设为0） 
    local base_chance = base_chance or 0 
    
    local upgraded_quality = nil -- 默认为 nil (即 Normal) 
    local random_roll = math.random() 
    local current_threshold = 0 -- 当前累加的阈值 
    
    -- 遍历配置表进行判断 
    for _, item in ipairs(quality_upgrades) do 
        -- 计算当前这一项的实际概率 
        local actual_chance = item.chance + base_chance 
        if item.chance ==0.005 then 
actual_chance=actual_chance-base_chance/4
        end
              if item.chance ==0.015 then 
actual_chance=actual_chance-base_chance/2
        end
        -- 累加阈值 
        current_threshold = current_threshold + actual_chance 
        
        -- 判断随机数是否落在当前范围内 
        if random_roll <= current_threshold then 
            upgraded_quality = item.name 
            break -- 一旦命中，立即停止循环 
        end 
    end 

    --品质价值倍数：普通品质+100，稀有品质+200，史诗品质+300，传说品质+400
    local quality_multipliers = {
        normal = 1,
        uncommon = 2,
        rare = 3,
        epic = 4,
        legendary = 5
    }


    

    -- 新规则：天赋品质决定最低产出品质
    -- q_idx 为天赋自身品质等级（1=normal ~ 5=legendary），与 quality_multipliers 的值一一对应
    local quality_names_by_idx = {"normal", "uncommon", "rare", "epic", "legendary"}
    local tianfu_quality = quality_names_by_idx[q_idx]

    -- 如果随机到的品质低于天赋品质（或未随机到任何品质），则以天赋品质为最低产出品质
    if not upgraded_quality or quality_multipliers[upgraded_quality] < q_idx then
        upgraded_quality = tianfu_quality
    end

    -- 如果最终产出品质不高于物品当前品质，则无提升，返回
    if quality_multipliers[upgraded_quality] <= quality_multipliers[current_quality] then
        return false
    end
    
    -- 显示当前物品品质信息（调试用）
    -- if current_quality ~= "normal" then
    --     game.print("当前物品品质: " .. current_quality .. ", 目标品质: " .. upgraded_quality)
    -- end
    --逻辑：1.计算提升总价值 =玩家魔力*敏捷
    local total_upgrade_value = magic * dexterity

    
    --2.计算转化的物品数=计算提升总价值/物品价值/品质价值倍数/当前物品品质倍数
    local target_quality_multiplier = quality_multipliers[upgraded_quality]
    local current_quality_multiplier = quality_multipliers[current_quality]
    local convert_count = math.floor(total_upgrade_value / item_info.value / target_quality_multiplier * current_quality_multiplier)
    
    if convert_count == 0 then
        convert_count=1
    end
    -- 确保转化的物品数不超过背包中的实际数量
    convert_count = math.min(convert_count, item_count)
    
    -- 如果转化的物品数小于1，返回失败
    if convert_count < 1 then
        return false
    end

    --3.移除玩家对应背包数量的物品，插入等量高品质的物品。
    -- 移除原物品
    local removed = main_inventory.remove({name = item_name, count = convert_count})
    if removed < convert_count then
        -- 如果移除失败，尝试移除实际能移除的数量
        convert_count = removed
    end
    
    if convert_count > 0 then
        -- 插入高品质物品
        local inserted = main_inventory.insert({name = item_name, count = convert_count, quality = upgraded_quality})
        
        if inserted > 0 then
            new_print(player, {'tianfu.chuanqibaozang_success', convert_count, upgraded_quality, item_name})
            return true
        else
            -- 如果插入失败，返还原来的物品
            main_inventory.insert({name = item_name, count = convert_count})
            new_print(player, {'tianfu.chuanqibaozang_inventory_full'})
            return false
        end
    end

    return false
end

local function xuyiyiquan(player, q_idx)
    if not check_tick(player, 'xuyiyiquan') then
        return false
    end
    
    local rpg_t = rpgtable.get('rpg_t')
    local player_index = player.index
    
    local strength = rpg_t[player_index].strength or 0
    if strength <= 0 then return false end
    
    local player_position = player.physical_position
    local surface = player.physical_surface
    local search_radius = 15
    
    local candidates = EntityCache.find_entities_cached(surface, {
        position = player_position,
        radius = search_radius,
        force = 'enemy',
        type = {'unit', 'spider-unit'}
    })
    
    if #candidates == 0 then return false end
    
    local player_direction = player.character.direction
    local dir_vectors = {
        [defines.direction.north]     = {x = 0, y = -1},
        [defines.direction.northeast] = {x = 0.707, y = -0.707},
        [defines.direction.east]      = {x = 1, y = 0},
        [defines.direction.southeast] = {x = 0.707, y = 0.707},
        [defines.direction.south]     = {x = 0, y = 1},
        [defines.direction.southwest] = {x = -0.707, y = 0.707},
        [defines.direction.west]      = {x = -1, y = 0},
        [defines.direction.northwest] = {x = -0.707, y = -0.707}
    }
    
    local facing_vector = dir_vectors[player_direction] or {x = 0, y = -1}
    local angle_threshold = math.cos(math.rad(80))
    
    local enemies = {}
    
    for _, target in pairs(candidates) do
        if target.valid then
            local dx = target.position.x - player_position.x
            local dy = target.position.y - player_position.y
            local distance = math.sqrt(dx^2 + dy^2)
            
            if distance > 0 then
                local nx = dx / distance
                local ny = dy / distance
                local dot_product = facing_vector.x * nx + facing_vector.y * ny
                
                if dot_product >= angle_threshold then
                    table.insert(enemies, target)
                end
            elseif distance == 0 then
                table.insert(enemies, target)
            end
        end
    end
    
    if #enemies == 0 then return false end
    
    local damage = strength * 0.4 * COEFF_REG[q_idx]
    
    for _, enemy in pairs(enemies) do
        if enemy.valid and enemy.health > 0 then
            
            
            -- 创建攻击特效
            surface.create_entity({
                name = 'vulcanus-cliff-collapse',
                position = enemy.position,
                force = game.forces.player
            })
            deal_damage_with_floating_text(enemy, player, damage, 'physical')
        end
    end
    
    new_print(player, { 'tianfu.xuyiyiquan_over', #enemies, math.floor(damage) })
    
    return true
end

-- 新增天赋（自动消化需求）：挂机成圣 / 越钓越肉 / 领航
-- #8 挂机成圣（通用/其他）：挂机（不移动）时每分钟获取金币，品质作用于金币
local function guajichengsheng(player, q_idx)
    local this = WPT.get()
    local index = player.index
    -- 自维护「未移动」检测（不依赖 check_tick 的 AFK 守卫，挂机反而应生效）
    if not this.guaji then this.guaji = {} end
    if not this.guaji[index] then
        this.guaji[index] = {
            x = player.physical_position.x,
            y = player.physical_position.y,
            idle_start = game.tick,
            last_fire = 0
        }
    end
    local d = this.guaji[index]
    local moved = math.abs(player.physical_position.x - d.x) > 0.5 or
        math.abs(player.physical_position.y - d.y) > 0.5
    if moved then
        d.x = player.physical_position.x
        d.y = player.physical_position.y
        d.idle_start = game.tick
        return
    end
    -- 持续未移动 >= 60 秒视为挂机
    if game.tick - d.idle_start < 60 * 60 then
        return
    end
    -- 每分钟发放一次
    if game.tick - d.last_fire < 60 * 60 then
        return
    end
    d.last_fire = game.tick
    local coin = math.floor(300 * COEFF_REG[q_idx or 1])
    insert_item_to_player(player, 'coin', coin)
    new_print(player, { 'tianfu.guajichengsheng_over', coin })
end

-- #13 越钓越肉（法师）：每分钟获得鱼，每累积 100 条鱼 +1 活力；品质作用于鱼数量
local function yuediaoyuerou(player, q_idx)
    if check_tick(player, 'yuediaoyuerou') then
        local this = WPT.get()
        local index = player.index
        if not this.yuediao then this.yuediao = {} end
        if not this.yuediao[index] then
            this.yuediao[index] = { fish_total = 0 }
        end
        local fish = math.floor(10 * COEFF_REG[q_idx or 1])
        insert_item_to_player(player, 'raw-fish', fish)
        this.yuediao[index].fish_total = this.yuediao[index].fish_total + fish
        -- 每累积 100 条鱼 +1 活力（品质只作用于鱼数量，活力固定 +1）
        -- 与其他天赋一致：直接经 rpg_t 写属性（本文件局部 rpgtable = require 'modules.rpg.table'，即 RPG 底层单例，等价于原记忆里的 RPG.get('rpg_t')）
        local rpg_t = rpgtable.get('rpg_t')
        while this.yuediao[index].fish_total >= 100 do
            this.yuediao[index].fish_total = this.yuediao[index].fish_total - 100
            rpg_t[player.index].vitality = rpg_t[player.index].vitality + 1
        end
        new_print(player, { 'tianfu.yuediaoyuerou_over', fish })
        return true
    end
end

-- #16 领航（通用/其他）：每分钟为等级低于你的在线玩家提供等同于你等级的经验，每经验值扣你 6 金币
local function linghang(player, q_idx)
    if check_tick(player, 'linghang') then
        local rpg_t = rpgtable.get('rpg_t')
        local my_level = rpg_t[player.index].level or 0
        if my_level <= 0 then
            return
        end
        -- 品质作用于经验获取量
        local exp_each = math.floor(my_level * COEFF_REG[q_idx or 1])
        if exp_each <= 0 then
            return
        end
        local players = game.connected_players
        local recipients = {}
        local total_exp = 0
        for i = 1, #players do
            local p = players[i]
            if p.index ~= player.index and p.valid then
                local pr = rpg_t[p.index]
                if pr and (pr.level or 0) < my_level then
                    recipients[#recipients + 1] = p
                    total_exp = total_exp + exp_each
                end
            end
        end
        if #recipients == 0 then
            return
        end
        -- 每经验值扣除你的 6 金币（金币不足则不发放）
        local cost = total_exp * 6
        local my_gold = 0
        if player.character and player.character.valid then
            my_gold = player.character.get_item_count('coin')
        end
        if my_gold < cost then
            return
        end
        player.remove_item({ name = 'coin', count = cost })
        for i = 1, #recipients do
            local p = recipients[i]
            local pr = rpg_t[p.index]
            pr.xp = pr.xp + exp_each
            p.create_local_flying_text({
                text = { 'tianfu.linghang_receive', exp_each, player.name },
                color = { r = 0.2, g = 0.8, b = 1.0 },
                position = p.physical_position,
                speed = 0.8
            })
        end
        new_print(player, { 'tianfu.linghang_over', total_exp, cost })
        return true
    end
end

-- #14 多多益善（战士）：每30秒召唤 等级*10 只随机敌方虫子在身边（单轮封顶 DUODUO_SPAWN_CAP 只），金币按「实际召唤数量」×0.35 结算（品质作用于金币）。
-- 单轮安全闸：每轮实际生成的实体数量封顶 DUODUO_SPAWN_CAP，从源头压住每轮虫海（玩家单轮最高只拿到封顶数的虫与对应金币）；
-- 场上总量不做硬上限（旧虫不自动清理，会随游戏时长累积），仅通过单轮封顶降低每轮爆发量。
local DUODUO_ENEMY_POOL = {
    'small-biter', 'small-spitter',
    'medium-biter', 'medium-spitter',
    'big-biter', 'big-spitter',
    'behemoth-biter', 'behemoth-spitter'
}
local DUODUO_SPAWN_CAP = 30  -- 每轮生成实体硬上限（单轮安全闸，由 200 下调至 30）

local function duoduoyishan(player, q_idx)
    if not check_tick(player, 'duoduoyishan') then
        return
    end
    local rpg_t = rpgtable.get('rpg_t')
    local level = rpg_t[player.index].level or 1
    if level <= 0 then
        level = 1
    end
    local intended = level * 10  -- 意愿召唤数：等级 * 10 只（仅用于计算封顶前的目标）
    q_idx = q_idx or 1
    -- 单轮安全闸：实际生成的敌方虫子数量封顶，不随等级无限增长
    local spawned = math.min(intended, DUODUO_SPAWN_CAP)
    -- 金币基于「实际生成数」结算（金币跟随实际虫子走），每只基础 5 金币、品质线性缩放（5 × COEFF_REG）
    local gold = math.floor(spawned * 5 * COEFF_REG[q_idx])
    local surface = player.physical_surface
    local pos = player.physical_position
    for i = 1, spawned do
        local name = DUODUO_ENEMY_POOL[math.random(1, #DUODUO_ENEMY_POOL)]
        -- 在玩家身边 5~8 米内随机点生成随机敌方虫子（force='enemy'，复用现有原型）
        local spawn_pos = surface.find_non_colliding_position(name, {
            x = pos.x + math.random(-8, 8),
            y = pos.y + math.random(-8, 8)
        }, 8, 1, true)
        if spawn_pos then
            surface.create_entity({
                name = name,
                position = spawn_pos,
                force = game.forces.enemy
            })
        end
    end
    if gold > 0 then
        insert_item_to_player(player, 'coin', gold)
    end
    new_print(player, { 'tianfu.duoduoyishan_over', spawned, gold })
end

-- #21 自动贩卖机（法师）：每5秒检测一次，当背包中鱼数量超过「1000 + 宠物数量×2000」时，
-- 超出部分的鱼自动按商店价格贩卖成金币。宠物数量上限3（Y 上限，clamp 0..3）。
-- 不应用品质：q_idx 不参与任何数值计算（阈值、售价、超出量均与品质无关）。
-- 商店收购价取 basic_markets.lua:62 market.caspules['raw-fish'].value = 7（每条鱼7金币）。
-- 复用项目标准加币接口 insert_item_to_player(player, 'coin', n) 发放金币；鱼移除用 player.remove_item（与宠物系统饥饿扣鱼同源）。
-- 错误不可掩盖：鱼不足阈值、宠物数为0、未学会等均正常 return，不 try-catch 兜底。
local FISH_SHOP_PRICE = 4        -- 商店收购价：每条鱼固定 4 金币（用户确认）
local FISH_BASE_THRESHOLD = 1000 -- 阈值基础值 X = 1000
local FISH_PER_PET = 2000        -- 每只宠物增加阈值 Y = 2000
local FISH_PET_MAX = 3           -- 宠物数量上限（Y 上限）

local function zidongfanmai(player, q_idx)
    if not check_tick(player, 'zidongfanmai') then
        return
    end
    -- 宠物数量（上限 3，clamp 到 0..3）
    local pet_data = PetSys.get_player_pet_data(player)
    local pet_count = #pet_data.pets
    if pet_count > FISH_PET_MAX then
        pet_count = FISH_PET_MAX
    end
    -- 阈值 = X + Y×宠物数量
    local threshold = FISH_BASE_THRESHOLD + pet_count * FISH_PER_PET
    -- 背包鱼数量
    local fish_count = player.get_item_count('raw-fish')
    if fish_count <= threshold then
        return
    end
    -- 超出部分的鱼按商店价贩卖
    local excess = fish_count - threshold
    player.remove_item({ name = 'raw-fish', count = excess })
    local coins = excess * FISH_SHOP_PRICE
    if coins > 0 then
        insert_item_to_player(player, 'coin', coins)
    end
    new_print(player, { 'tianfu.zidongfanmai_over', excess, coins })
end

-- #52 活力鱼（法师）：每1分钟被动触发，消耗背包85条鱼为自身换活力；每450魔力多触发一次
-- 性能安全闸：触发次数封顶 20（正常玩家远达不到；仅物理执行加帽，保留「每450魔法多触发一次」收益意图）
local function huoliyu(player, q_idx)
    if not check_tick(player, 'huoliyu') then
        return
    end
    local rpg_t = rpgtable.get('rpg_t')
    local magicka = rpg_t[player.index].magicka or 0
    -- 触发次数 = 1 + 每450魔力一次，封顶20
    local triggers = 1 + math.floor(magicka / 450)
    if triggers > 20 then triggers = 20 end
    -- 每消耗85条鱼 +__2__ 活力（品质作用于属性点，arr 模式 {1,1,2,2,3}）
    local vit_each = ({1, 1, 2, 2, 3})[q_idx or 1]
    local gained = 0
    for i = 1, triggers do
        local fish_count = player.get_item_count('raw-fish')
        if fish_count < 85 then
            break  -- 鱼不足则跳过剩余触发（不报错、不卡死）
        end
        player.remove_item({ name = 'raw-fish', count = 85 })
        rpg_t[player.index].vitality = rpg_t[player.index].vitality + vit_each
        gained = gained + vit_each
    end
    if gained > 0 then
        new_print(player, { 'tianfu.huoliyu_over', gained })
    end
    return true
end

-- 黏土炸弹（#55）：法师被动 time-skill
-- 每6秒为玩家周围20米内随机一只友方虫子打上「亡语」标记；
-- 该虫子死亡时，对死亡点5米内所有敌方单位造成相当于持有者当前法力值×品质系数的伤害。
-- 标记仅记录于 WPT（this.clay_bomb_marks），不修改虫子本身属性；后一次打标覆盖前一次。
local function njbomb(player, q_idx)
    if not check_tick(player, 'njbomb') then
        return false
    end
    if not player or not player.valid or not player.character or not player.character.valid then
        return false
    end

    local surface = player.physical_surface
    if not surface then
        return false
    end

    -- 枚举玩家周围20米内、force=player 的友方虫子（unit 类实体，含驯服的虫子）
    local friends = surface.find_entities_filtered({
        position = player.physical_position,
        radius = 20,
        type = 'unit',
        force = game.forces.player
    })

    if not friends or #friends == 0 then
        return false
    end

    -- 随机选一只
    local target = friends[math.random(#friends)]
    if not target or not target.valid then
        return false
    end

    -- 打标记（覆盖式：后一次覆盖前一次，持有者=当前玩家）
    local this = WPT.get()
    if not this.clay_bomb_marks then
        this.clay_bomb_marks = {}
    end
    this.clay_bomb_marks[target.unit_number] = {
        player_index = player.index,
        q_idx = q_idx or 1
    }

    new_print(player, { 'tianfu.njbomb_over' })
    return true
end

-- 黏土炸弹亡语：独立 on_entity_died handler（不带 filters，内部自过滤）
-- 仅对带黏土炸弹标记的「友方虫子(unit)」生效，不改动 biter_die.lua 的既有 handler。
local on_clay_bomb_died = function(event)
    local entity = event.entity
    if not (entity and entity.valid) then
        return
    end
    if entity.type ~= 'unit' then
        return
    end

    local unit_number = entity.unit_number
    local this = WPT.get()
    if not this.clay_bomb_marks then
        return
    end

    local data = this.clay_bomb_marks[unit_number]
    if not data then
        return
    end

    -- 取出持有者与品质后立即清除标记（防重复触发与内存泄漏）
    this.clay_bomb_marks[unit_number] = nil

    local player = game.get_player(data.player_index)
    if not (player and player.valid) then
        return
    end

    -- 副本隔离：副本玩家不触发主世界黏土炸弹亡语
    if player.force.name ~= 'player' then return end

    local rpg_t = rpgtable.get('rpg_t')
    local pt = rpg_t[player.index]
    if not pt then
        return
    end
    local magicka = pt.magicka or 0
    local q_idx = data.q_idx or 1

    -- 最终伤害 = 当前法力值 × 品质系数（字面直读：不额外硬塞激光加成）
    local damage = magicka * COEFF_REG[q_idx]

    if damage <= 0 then
        return
    end

    local surface = entity.surface
    local position = entity.position
    if not (surface and position) then
        return
    end

    -- 对死亡点5米内所有敌方单位造成伤害（5 ≤ 24）
    -- 用项目统一的 EntityCache 缓存搜索：仅返回敌方 unit/turret/spawner 等带血小类，
    -- 内部已按 health>0 过滤，不会捞回尸体/烟雾/装饰物等无血量实体，
    -- 从根本上规避 "Entity is not entity-with-health" 崩溃。
    local enemies = EntityCache.find_entities_cached(surface, {
        position = position,
        radius = 5,
        force = game.forces.enemy,
        type = goal
    })

    local dealer = (player.character and player.character.valid) and player.character or nil

    for _, enemy in pairs(enemies) do
        if enemy and enemy.valid and enemy.health and enemy.health > 0 then
            enemy.damage(damage, game.forces.player, 'laser', dealer)
        end
    end
end
Event.add(defines.events.on_entity_died, on_clay_bomb_died)

-- 公共接口
Public.time_skills = time_skills

-- 导出所有技能函数（仅声明，具体实现在tianfu.lua中）
Public.dianjiqiang = dianjiqiang
Public.wanlaotianlei = wanlaotianlei
Public.chongfengxianzhen = chongfengxianzhen
Public.zhidanbing = zhidanbing
Public.yanfayanjiuzhongxin = yanfayanjiuzhongxin
Public.mlzq = mlzq
Public.bujiwu = bujiwu
Public.mzqz = mzqz
Public.yjjn = yjjn
Public.leitingwanjun = leitingwanjun
Public.gcd = gcd
Public.cjs = cjs
Public.wjjt = wjjt
Public.kls = kls
Public.whea = whea
Public.kytd = kytd
Public.zhrm = zhrm
Public.scmcc = scmcc
Public.mbz = mbz
Public.tls = tls
Public.zsfs = zsfs
Public.djrc = djrc
Public.pulu = pulu
Public.dafs = dafs
Public.ljss = ljss
Public.mfxt = mfxd
Public.ylsgd = ylsgd
Public.jiansheche = jiansheche
Public.fuzhushou = fuzhushou
Public.zidongfanmai = zidongfanmai
Public.huoliyu = huoliyu
Public.njbomb = njbomb
Public.tann = tann
Public.rsrl = rsrl
Public.xly = xly
Public.tzzj = tzzj
Public.hhc = hhc
Public.jgq = jgq
Public.xj = xj
Public.smlw = smlw
Public.jndd = jndd
Public.ycj = ycj
Public.qns = qns
Public.dl = dl
Public.jxhx = jxhx
Public.wlfs = wlfs
Public.xxzb = xxzb
Public.juemuren = juemuren
Public.lg = lg
Public.xxg = xxg
Public.dgwd = dgwd
Public.honzha = honzha
Public.chifu = chifu
Public.touqian = touqian
Public.fatiao = fatiao
Public.fkdda = fkdda
Public.fkddb = fkddb
Public.keyan = keyan
Public.hmds = hmds
Public.sglz = sglz
Public.bpz = bpz
Public.boom_player = boom_player
Public.small_buss = small_buss
Public.zrsc = zrsc
Public.zhs = zhs
Public.wolf = wolf
Public.dutu = dutu
Public.wxs = wxs
Public.junhuo = junhuo
Public.genben = genben
Public.fish = fish
Public.zdfs = zdfs
Public.zdfs2 = zdfs2
Public.jingong = jingong
Public.kejigongsi = kejigongsi
Public.hd = hd
Public.fali = fali
Public.carxiu = carxiu
Public.ftlt = ftlt
Public.tdlx = tdlx
Public.fangshou = fangshou
Public.dianluban = dianluban
Public.xueqiu = xueqiu
Public.jiguang = jiguang
Public.wudi = wudi
Public.pailei = pailei
Public.sansan = sansan
Public.mlst = mlst
Public.xxyd = xxyd
Public.morefali = morefali
Public.rlfdz = rlfdz
Public.yuer = yuer
Public.shen_fa = shen_fa
Public.lengdongyubaoxianshu = lengdongyubaoxianshu
Public.diyu_rongyan = diyu_rongyan
Public.lanhuangjiaonang = lanhuangjiaonang
Public.zishenzhuanjia = zishenzhuanjia
Public.daodaoku = daodaoku
Public.xiandanhecheng = xiandanhecheng
Public.hushenfu = hushenfu
Public.zhuoshao = zhuoshao
Public.tieshenhuwei = tieshenhuwei
Public.shui_hu_fu = shui_hu_fu
Public.shui_dun = shui_dun
Public.chuanqibaozang = chuanqibaozang
Public.tesla_battery = tesla_battery
Public.xuyiyiquan = xuyiyiquan

-- 工业城市天赋：每分钟吸收周围污染转化为金币
local function gycs(player, q_idx)
    if check_tick(player, 'gycs') then
    
            local rpg_t = rpgtable.get('rpg_t')
        
            -- 获取玩家坦克位置和表面
            local position = player.physical_position
            local surface = player.physical_surface
            
            -- 获取玩家敏捷属性
            local dexterity = rpg_t[player.index].dexterity
            
            -- 基础污染吸收范围（半径20格）
            local pollution_radius = 20
            
            -- 计算区域内的总污染量
            local total_pollution = 0
            local pollution_chunks = {}
            
            -- 扫描污染区域内的区块
            for x = -pollution_radius, pollution_radius, 16 do
                for y = -pollution_radius, pollution_radius, 16 do
                    local chunk_position = {
                        x = math.floor((position.x + x) / 16),
                        y = math.floor((position.y + y) / 16)
                    }
                    local pollution_amount = surface.get_pollution(chunk_position)
                    if pollution_amount > 0 then
                        table.insert(pollution_chunks, {
                            position = chunk_position,
                            pollution = pollution_amount
                        })
                        total_pollution = total_pollution + pollution_amount
                    end
                end
            end
            
            if total_pollution <= 0 then
                return true
            end
            
            -- 每1点敏捷多吸收10点污染
            local bonus_absorption = dexterity 
            local max_absorption = math.min(total_pollution, 1000 + bonus_absorption)
            
            -- 清除吸收的污染
            local absorbed_pollution = 0
            for _, chunk in ipairs(pollution_chunks) do
                if absorbed_pollution >= max_absorption then
                    break
                end
                
                local chunk_absorption = math.min(chunk.pollution, max_absorption - absorbed_pollution)
                surface.pollute({
                    x = chunk.position.x * 32 + 16,
                    y = chunk.position.y * 32 + 16
                }, -chunk_absorption)
                absorbed_pollution = absorbed_pollution + chunk_absorption
            end
            
            -- 每12点污染转化为1金币
            
           
                local coin_count = math.floor(dexterity*0.4*COEFF_REG[q_idx or 1])
                if coin_count >= 1500 then
                    coin_count = 1500
                end
                insert_item_to_player(player, 'coin', coin_count)
                
                -- 显示效果信息
                new_print(player, { 'tianfu.gycs_over',  coin_count })
            
        
    end
    return true
end

Public.gycs = gycs

-- 检查属性是否是4个属性中最高的
local function is_highest_attribute(player, attribute_name, q_idx)
    local rpg_t = rpgtable.get('rpg_t')
    local current_value = rpg_t[player.index][attribute_name]
    
    -- 获取所有4个属性值
    local vitality = rpg_t[player.index].vitality
    local magicka = rpg_t[player.index].magicka  
    local strength = rpg_t[player.index].strength
    local dexterity = rpg_t[player.index].dexterity
    
    -- 检查当前属性是否 >= 其他所有属性
    if attribute_name == 'vitality' then
        return current_value >= magicka and current_value >= strength and current_value >= dexterity
    elseif attribute_name == 'magicka' then
        return current_value >= vitality and current_value >= strength and current_value >= dexterity
    elseif attribute_name == 'strength' then
        return current_value >= vitality and current_value >= magicka and current_value >= dexterity
    elseif attribute_name == 'dexterity' then
        return current_value >= vitality and current_value >= magicka and current_value >= strength
    end
    
    return false
end

-- 电磁干扰天赋：敏捷大于1200且为4个属性中最高时，每秒消耗装甲电池电量对附近虫子造成激光伤害
local function dcrg(player, q_idx)
    if check_tick(player, 'dcrg') then
        local rpg_t = rpgtable.get('rpg_t')
        
        -- 检查敏捷是否大于1200且为4个属性中最高
        local dexterity = rpg_t[player.index].dexterity or 0
        if dexterity < 1200 or not is_highest_attribute(player, 'dexterity') then
            return true
        end
        
        -- 检查玩家是否有角色和装甲
        if not player.character or not player.character.valid then
            return true
        end
        
        local armor_inventory = player.get_inventory(defines.inventory.character_armor)
        if not armor_inventory or not armor_inventory.valid then
            return true
        end
        
        local armor = armor_inventory[1]
        if not armor or not armor.valid_for_read then
            return true
        end
        
        local grid = armor.grid
        if not grid or not grid.valid then
            return true
        end
        
        -- 查找装甲中的电池设备
        local battery_equipment = {}
        local total_battery_energy = 0
        local total_battery_max_energy = 0
        
        for _, equipment in pairs(grid.equipment) do
            if equipment.valid and equipment.type == "battery-equipment" then
                table.insert(battery_equipment, equipment)
                total_battery_energy = total_battery_energy + equipment.energy
                total_battery_max_energy = total_battery_max_energy + equipment.max_energy
            end
        end
        
        -- 如果没有电池设备，返回
        if #battery_equipment == 0 or total_battery_max_energy == 0 then
            return true
        end
        
        -- 查找附近的敌对虫子（最多24只）
        local surface = player.physical_surface
        local position = player.physical_position
        
        local enemies = EntityCache.find_entities_cached(surface, {
            position = position,
            radius = 20,  -- 20格范围
            force = game.forces.enemy,
            type = goal,
            limit = 24
        })
        
        if #enemies == 0 then
            return true
        end
        
        -- 最大计提电量：50千焦 * 24 = 1200千焦
        local max_extractable_energy = 50000 * 24  -- 1200千焦
        
        -- 检查电池电量是否达到最大计提要求
        if total_battery_energy < max_extractable_energy then
            return true  -- 电量不足，不触发伤害
        end
        
        -- 计算电量到伤害的转换率：50千焦电力 = 20点激光伤害
        local energy_to_damage_ratio = 2500 / 1  -- 每1点伤害需要2500电量
        
        -- 按最大计提电量计算总伤害额
        local total_damage_possible = math.floor(max_extractable_energy / energy_to_damage_ratio * COEFF_REG[q_idx or 1])
        
        -- 从电池中提取最大计提电量
        local remaining_extract = max_extractable_energy
        for _, battery in ipairs(battery_equipment) do
            if remaining_extract <= 0 then
                break
            end
            
            local available_energy = battery.energy
            local extract_from_this = math.min(available_energy, remaining_extract)
            battery.energy = battery.energy - extract_from_this
            remaining_extract = remaining_extract - extract_from_this
        end
        
        -- 计算平均分配给每个敌人的伤害（基于最大计提电量）
        local enemy_count = #enemies
        local damage_per_enemy = math.floor(total_damage_possible / enemy_count)
        
        -- 检查是否有激光伤害加成
        local laser_damage_bonus = game.forces.player.get_ammo_damage_modifier("laser")+1
        local attack_speed_bonus = game.forces.player.get_gun_speed_modifier('laser') + 1

        -- 计算最终伤害
        local final_damage_per_enemy = damage_per_enemy * laser_damage_bonus * attack_speed_bonus
        
        -- 对每个敌人造成平均分配的激光伤害
        for _, enemy in ipairs(enemies) do
            if enemy.valid then
                -- 创建电磁干扰视觉效果
                surface.create_entity({
                    name = 'electric-beam',
                    position = position,
                    target = enemy.position,
                    source = position,
                    duration = 10
                })
                
                -- 造成平均分配的激光伤害
                deal_damage_with_floating_text(enemy, player, final_damage_per_enemy, 'laser')
            end
        end
        
        -- 显示效果信息
        new_print(player, { 'tianfu.dcrg_over', enemy_count, final_damage_per_enemy })
        
        return true
    end
end

Public.dcrg = dcrg
Public.danmu_gongji = danmu_gongji
-- 核弹支援天赋：活力大于1200时，血量低于50%召唤2个核弹轰炸

-- 工程车天赋：每10秒依次获得1个物品
local function gongchengche(player, q_idx)
    if check_tick(player, 'gongchengche') then

        local this=WPT.get()
        local car = get_player_car_entity(player)
        if not car or not car.valid then
            return true
        end
        
        -- 物品序列
        local item_sequence = {
            'boiler', 'steam-engine', 'electric-mining-drill', 'steel-furnace',
            'medium-electric-pole', 'inserter', 'assembling-machine-2', 'pumpjack',
            'oil-refinery', 'chemical-plant', 'storage-chest', 'roboport',
            'construction-robot', 'logistic-robot', 'requester-chest', 'passive-provider-chest'
        }
        
        
        if not this.gongchengche_index[player.index] then
            this.gongchengche_index[player.index] = 1
        end
        
        -- 记录每个物品已给予的数量
        if not this.gongchengche_count[player.index] then
            this.gongchengche_count[player.index] = {}
        end
        
        local current_index = this.gongchengche_index[player.index]
        local current_item = item_sequence[current_index]
        
        -- 获取当前物品已给予的数量
        local given_count = this.gongchengche_count[player.index][current_item] or 0
        
        -- 检查当前物品是否已给予6个
        if given_count < 5 then
            -- 给予当前物品 
            car.insert({name = current_item, count = 1, quality = QUALITY_NAMES[q_idx or 1]})
           new_print(player, { 'tianfu.gongchengche_over', current_item })
            
            -- 更新已给予的数量
            this.gongchengche_count[player.index][current_item] = given_count + 1
        else
            -- 移动到下一个物品
            this.gongchengche_count[player.index][current_item] = 0
            local next_index = current_index + 1
            if next_index > #item_sequence then
                next_index = 1  -- 重置序列
            end
            this.gongchengche_index[player.index] = next_index
            
            -- 给予新的当前物品
            local new_item = item_sequence[next_index]
            car.insert({name = new_item, count = 1, quality = QUALITY_NAMES[q_idx or 1]})
            new_print(player, { 'tianfu.gongchengche_over', current_item })
            -- 重置新物品的已给予数量为1
            this.gongchengche_count[player.index][new_item] = 1
        end
    end
    return true
end

Public.gongchengche = gongchengche

-- 冶炼车天赋：每10秒基于附近矿物类型获得对应冶炼成品
local function yelianche(player, q_idx)
    if check_tick(player, 'yelianche') then
        local car = get_player_car_entity(player)
        if not car or not car.valid then
            return true
        end
        -- 获取玩家敏捷属性
        local rpg_t = rpgtable.get('rpg_t')
        if not rpg_t or not rpg_t[player.index] then
            return true
        end
        
        local agility = rpg_t[player.index].dexterity or 0
        local amount = math.floor(agility * 0.5 * COEFF_REG[q_idx or 1])  -- 敏捷的50%
        amount = math.min(amount, 500)  -- 最大500
        
        if amount <= 0 then
            return true
        end
        
        -- 查找附近的矿物
        local position = car.position
        local surface = car.surface
        
        -- 定义矿物与对应冶炼成品的映射
        local resource_to_product = {
            ['iron-ore'] = 'iron-plate',
            ['copper-ore'] = 'copper-plate',
            ['stone'] = 'stone-brick'
        }
        
        -- 查找附近的矿物（范围设为20格）
        local nearby_resources = surface.find_entities_filtered({
            position = position,
            radius = 5,
            type = 'resource'
        })
        
        if #nearby_resources == 0 then
            return true
        end
        
        -- 收集所有可用的产品
        local available_products = {}
        for _, entity in pairs(nearby_resources) do
            if entity.valid and resource_to_product[entity.name] then
                table.insert(available_products, resource_to_product[entity.name])
                -- 3. 可选：如果你希望它是真正的“挖掘”，需要扣除地上的矿资源
                -- if entity.amount > 0 then entity.amount = entity.amount - 1 end
               
            end
        end
        
        -- 如果没有可用的产品
        if #available_products == 0 then
            return true
        end
        
        -- 从可用产品中随机选择一个
        local product_name = available_products[math.random(#available_products)]
        
        -- 检查车背包内是否已有超过3.6k的对应冶炼成品
        local current_count = car.get_item_count(product_name)
        if current_count >= 2000 then
            return true
        end
        
        -- 给予冶炼成品
        car.insert({name = product_name, count = amount})
        new_print(player, { 'tianfu.yelianche_over', amount, product_name })
    end
    return true
end

Public.yelianche = yelianche

-- 未来战士天赋：每90秒获得1个特斯拉子弹，如果没有装备特斯拉枪则改为获得特斯拉枪
local function weilai(player, q_idx)
    -- 检查冷却时间
   
    if not check_tick(player, 'weilai') then
        return false
    end

    -- 物品的标准名称（请确保你玩的是2.0 Space Age，或者是添加了该物品的MOD）
    -- 绝大多数情况下是带连字符的
    local gun_name = 'teslagun'   
    local ammo_name = 'tesla-ammo'

    -- 获取玩家的【武器栏】而不是【主背包】
    local inventory = player.get_inventory(defines.inventory.character_guns)
    
    -- 安全检查：如果玩家处于上帝模式或无实体状态，可能没有背包
    if not inventory then
        return true
    end

    local has_tesla_gun = false

    -- 遍历所有武器槽位（通常是3个），只要发现一把特斯拉枪就算拥有
    for i = 1, #inventory do
        local stack = inventory[i]
        if stack and stack.valid_for_read and stack.name == gun_name then
            has_tesla_gun = true
            break -- 找到了就停止循环
        end
    end
    
    -- 根据是否装备特斯拉枪给予不同物品
    if has_tesla_gun then
        -- 已装备特斯拉枪，给予1个特斯拉子弹
        insert_item_to_player(player, ammo_name, 1, QUALITY_NAMES[q_idx or 1])
        new_print(player, { 'tianfu.weilai_ammo', 1 })
    else
        -- 未装备特斯拉枪，给予特斯拉枪
        -- 尝试插入枪支
        local inserted = insert_item_to_player(player, gun_name, 1, QUALITY_NAMES[q_idx or 1])
        
        -- 调试信息：如果依然没给到，可能是名字还是不对，或者背包满了
     
            new_print(player, { 'tianfu.weilai_gun' })
     
    end
    
    return true
end

Public.weilai = weilai

local function jidiche(player, q_idx)
    -- 检查 tick 频率，不需要每 tick 都运行，例如每 10 tick 运行一次
    -- 注意：你需要自己调整 check_tick 的逻辑来适配积累池，或者直接在这里处理
    if not check_tick(player, 'jidiche') then
        return
    end
    local this = WPT.get()
    local car = get_player_car_entity(player)
  
    -- 初始化玩家的劳动力积累池 (建议放在 global 表里，这里用临时变量演示逻辑)
    -- 实际代码中，请用 global.build_buffer[player.index] 来存储，否则每次函数结束就清零了
    -- 这里假设你已经有了 global 表结构

    this.build_buffer[player.index] = this.build_buffer[player.index] or 0
    
    -- 1. 获取属性
    local rpg_t = rpgtable.get('rpg_t')
    local agility = rpg_t[player.index].dexterity or 0
    
    -- 2. 计算本回合增加的劳动力（时间单位：秒）
    -- 假设：每100点敏捷，每秒提供 1秒 的制作能力。
    -- 假设函数每 60 tick (1秒) 运行一次，或者你需要根据 check_tick 的间隔来算
    -- 这里的公式： (敏捷 * 系数)
    local time_income = (agility * 0.1) * 4 * COEFF_REG[q_idx or 1]
    
    -- 累加到池子
    this.build_buffer[player.index] = this.build_buffer[player.index] + time_income
    
    -- 设置最大积累上限，防止挂机一晚上瞬间秒建全图
    local max_buffer = 50000 -- 最多积累600秒的工作量
    if this.build_buffer[player.index] > max_buffer then
        this.build_buffer[player.index] = max_buffer
    end
  if not car or not car.valid then
    
        return
    end
    local buffer = this.build_buffer[player.index]

    local surface = car.surface
    
    -- 3. 寻找附近的幽灵
    local ghost_count = surface.count_entities_filtered({
        position = car.position,
        name = 'entity-ghost',
        radius = 24, -- 建造范围
        force = game.forces.player
    })

    if ghost_count == 0 then
        return
    end

    local ghosts = surface.find_entities_filtered({
        position = car.position,
        name = 'entity-ghost',
        radius = 24, -- 建造范围
        force = game.forces.player
    })

    local built_count = 0
    for _, ghost in pairs(ghosts) do
        -- 如果积累的时间用完了，就停止
        if buffer <= 0 then break end

        if ghost.valid then
            -- 获取该幽灵对应的物品原型
            local items = ghost.ghost_prototype.items_to_place_this
            local item_name = nil
            
            if items and items[1] then
                item_name = items[1].name
            else
                -- 如果没有对应物品（极少数情况），直接赋值物品名为幽灵名尝试
                item_name = ghost.ghost_name
            end

            -- 执行防作弊检查
            local is_valid = validate_ghost(ghost, item_name)
            -- 计算这个建筑的总制作时间
            if  is_valid then
             
            
            local cost_time = get_total_crafting_time(item_name)

            -- 如果计算结果为0（异常），给一个最小低保值 1秒
            if cost_time <= 0 then cost_time = 1 end
   
            -- 检查预算是否足够
            if buffer >= cost_time then
                -- 尝试复活
                local success, _ = ghost.revive({raise_revive = true})
                
                if success then
                    -- 扣除预算
                    buffer = buffer - cost_time
                    built_count = built_count + 1
                    -- 建造成功提示
                    new_print(player, { 'tianfu.jidiche_build', item_name })
                    
                end
                end
            end
        end
    end

    -- 更新全局池子
    this.build_buffer[player.index] = buffer
end
Public.jidiche = jidiche

-- 先驱者天赋：每20分钟提升1%激光、子弹、重炮、火焰、电击伤害
-- 疾风步天赋：移速提高10%，每有100点法力值移速提高10%，最大50%
local function jifengbu(player, q_idx)
    if check_tick(player, 'jifengbu') then
        if player.force.name ~= 'player' then
            return false
        end
        local rpg_t = rpgtable.get('rpg_t')
        local index = player.index
        
        -- 获取玩家法力值
        local magicka = rpg_t[index].mana or 0
       
        -- 计算移速加成：基础10% + 每100点法力值10%，最大50%
        local speed_bonus = 0.1 * COEFF_LOW[q_idx or 1]  -- 基础10%
        local mana_bonus = math.floor(magicka / 100) * 0.1 * COEFF_LOW[q_idx or 1]  -- 每100点法力值10%
        mana_bonus = math.min(mana_bonus, 0.9)  -- 限制法力值加成最大为40%
        
        local total_bonus = speed_bonus + mana_bonus
        total_bonus = math.min(total_bonus, 1)  -- 总加成不超过50%
        
        -- 应用移速加成
        player.character_running_speed_modifier = player.character_running_speed_modifier + total_bonus
        
        -- 设置定时器取消效果
        Task.set_timeout_in_ticks(60 * 10, lowdowm_1, player)  -- 10秒后取消效果
        
        -- 发送提示消息
        new_print(player, { 'tianfu.jifengbu_over', math.floor(total_bonus * 100)})
        
        return true
    end
    return false
end

Public.jifengbu = jifengbu

-- 乐队鼓手天赋：每10秒提升附近玩家的移动速度
local function yuedui_gushou(player, q_idx)
    if check_tick(player, 'yuedui_gushou') then
        local surface = player.physical_surface
        local character = player.character
        local position = player.physical_position
        local radius = math.floor(20 * COEFF_REG[q_idx or 1])  -- {16,20,24,28,32}

        for _, e in pairs(surface.find_entities_filtered({
            position = position,
            radius = radius,
            type = {'character', 'unit', 'spider-unit'},
            force = 'player',
        })) do
            if e.valid then
            surface.create_entity({
                name = "jellynut-speed-sticker",
                position = position,
                source = character,
                target = e,
                force = "player",
                player = player,
            })
            end
        end

        return true
    end
    return false
end

Public.yuedui_gushou = yuedui_gushou

-- 背包整理天赋：自动整理背包和车辆之间的物品
-- 背包整理天赋：自动整理背包和车辆之间的物品
-- 背包整理 talent：自动整理背包和车辆物品
local function beibaozhengli(player, q_idx)
    if not check_tick(player, 'beibaozhengli') then return false end

    local blacklist_items = {
        ['raw-fish'] = true, ['coin'] = true, ['modular-armor'] = true,
        ['power-armor'] = true, ['power-armor-mk2'] = true, ['mech-armor'] = true,
    }

    local science_packs = {
        ['automation-science-pack'] = true, ['logistic-science-pack'] = true,
        ['military-science-pack'] = true, ['chemical-science-pack'] = true,
        ['production-science-pack'] = true, ['utility-science-pack'] = true,
        ['space-science-pack'] = true,
    }

    local tank = get_player_car_entity(player)

    
    if not tank or not tank.valid then return false end
    
    if player.physical_surface ~= tank.surface then return false end

    local main_inv = player.get_inventory(defines.inventory.character_main)
    local tank_inv = tank.get_inventory(defines.inventory.car_trunk)
    if not main_inv or not tank_inv then return false end

    -- 1. 数据预处理：一次性获取所有库存内容（减少API调用）
    local p_contents = main_inv.get_contents()
    local t_contents = tank_inv.get_contents()
    local items_transferred = 0

    -- 计算背包可用容量比例：空闲槽位 / 总槽位
    local inv_total = #main_inv
    local inv_free = 0
    for i = 1, inv_total do
        if not main_inv[i].valid_for_read then inv_free = inv_free + 1 end
    end
    local inv_free_ratio = inv_total > 0 and (inv_free / inv_total) or 0

    -- 2. 统计玩家持有的总量（背包 + 手持）
    -- 结构：counts[name][quality] = count
    local player_total = {}
    for _, entry in pairs(p_contents) do
        local q = entry.quality or "normal"
        player_total[entry.name] = player_total[entry.name] or {}
        player_total[entry.name][q] = entry.count
    end

    -- 处理手持物品（不作为扣除源，但计入总量）
    local cursor = player.cursor_stack
    local cursor_info = nil
    if cursor and cursor.valid_for_read then
        local c_name, c_qual = cursor.name, cursor.quality.name
        player_total[c_name] = player_total[c_name] or {}
        player_total[c_name][c_qual] = (player_total[c_name][c_qual] or 0) + cursor.count
        cursor_info = {name = c_name, quality = c_qual} -- 标记手持，防止误动
    end

    -- 3. 合并处理：遍历坦克里的物品 + 玩家原本有的物品
    -- 我们只需要遍历坦克和背包的并集
    local processed = {}

    -- 内部函数：处理核心逻辑
    local function process_item(name, quality, q_idx)
        local key = name .. "_" .. quality
        if processed[key] or blacklist_items[name] then return end
        processed[key] = true

        local proto = prototypes.item[name]
        if not proto then return end

        -- 科技瓶：背包里的全部传送到车内，不从车内补充回背包
        if science_packs[name] then
            local in_inv = 0
            for _, v in pairs(p_contents) do
                if v.name == name and (v.quality or "normal") == quality then
                    in_inv = v.count; break
                end
            end
            if in_inv > 0 then
                local spec = {name = name, count = in_inv, quality = quality}
                if tank_inv.can_insert(spec) then
                    local removed = main_inv.remove(spec)
                    if removed > 0 then
                        items_transferred = items_transferred + tank_inv.insert({name = name, count = removed, quality = quality})
                    end
                end
            end
            return
        end

        local target_count = proto.stack_size * 2
        local current_owned = (player_total[name] and player_total[name][quality]) or 0
        
        -- 这里的逻辑：只要坦克有，或者玩家有，都会进入这个逻辑
        if current_owned > target_count and inv_free_ratio < 0.1 then
            -- 情况 A: 玩家拿多了，往车里放
            local to_move = current_owned - target_count
            -- 注意：只能从背包拿，不能动鼠标上的。所以要看背包里实际有多少
            local in_inv = 0
            for _, v in pairs(p_contents) do 
                if v.name == name and (v.quality or "normal") == quality then 
                    in_inv = v.count; break 
                end 
            end
            to_move = math.min(to_move, in_inv)

            if to_move > 0 then
                local spec = {name = name, count = to_move, quality = quality}
                if tank_inv.can_insert(spec) then
                    local removed = main_inv.remove(spec)
                    if removed > 0 then
                        items_transferred = items_transferred + tank_inv.insert({name = name, count = removed, quality = quality})
                    end
                end
            end

        elseif current_owned < target_count then
            -- 情况 B: 玩家少了，从车里补 (即使玩家现在是0，只要车里有，也会补)
            local needed = target_count - current_owned
            -- 检查车里有多少
            local in_tank = 0
            for _, v in pairs(t_contents) do 
                if v.name == name and (v.quality or "normal") == quality then 
                    in_tank = v.count; break 
                end 
            end

            local to_take = math.min(needed, in_tank)
            if to_take > 0 then
                local spec = {name = name, count = to_take, quality = quality}
                if main_inv.can_insert(spec) then
                    local removed = tank_inv.remove(spec)
                    if removed > 0 then
                        items_transferred = items_transferred + main_inv.insert({name = name, count = removed, quality = quality})
                    end
                end
            end
        end
    end

    -- 先处理坦克里的物品（满足“车里有就补”的需求）
    for _, entry in pairs(t_contents) do
        process_item(entry.name, entry.quality or "normal")
    end
    -- 再处理玩家背包里的物品（处理“玩家多了要放回”的需求）
    for _, entry in pairs(p_contents) do
        process_item(entry.name, entry.quality or "normal")
    end

    if items_transferred > 0 then
        new_print(player, {'tianfu.beibaozhengli_over', items_transferred})
    end
    return true
end

Public.beibaozhengli = beibaozhengli

-- 附魔天赋：每30秒召唤一只附魔虫子
local function fumo(player, q_idx)
    if not check_tick(player, 'fumo') then
        return false
    end

    -- 检查玩家是否有效且有角色
    if not player or not player.valid or not player.character or not player.character.valid then
        return false
    end

    local surface = player.physical_surface
    local position = player.physical_position
    local this = TPT.get()
    local rpg_t = rpgtable.get('rpg_t')
    
    -- 获取玩家当前法力值
    local current_mana = rpg_t[player.index].magicka or 0
    
    -- 计算最大附魔虫子数量：基础1只 + 每300法力增加1只
    local base_bug_count = math.floor(current_mana / 300) + 1
    local max_bug_count = math.floor(current_mana / 300) + 1
    
    -- 获取玩家当前已有的附魔虫子数量
    local player_biters = this.fumo_biters[player.index] or {}
    local current_bug_count = 0
    
    -- 统计有效的附魔虫子数量
    for i = #player_biters, 1, -1 do
        local biter = player_biters[i]
        if not biter or not biter.valid then
            table.remove(player_biters, i)
        else
            current_bug_count = current_bug_count + 1
        end
    end
    
    -- 如果已经达到最大数量，不召唤新虫子
    if current_bug_count >= max_bug_count then
        return true
    end
    
    -- 查找周围的友方虫子（中立或玩家阵营的）
    local allied_entities = surface.find_entities_filtered({
        position = position,
        radius = 20,
        force = {'player'},  -- 查找中立或玩家阵营的实体
        type = {'unit', 'spider-unit'}  -- 只查找单位（虫子和蜘蛛）
    })
    
    -- 过滤出可以转生的虫子（排除已经驯服的）
    local available_bugs = {}
    for _, entity in pairs(allied_entities) do
        if entity.valid and (entity.type == 'unit' or entity.type == 'spider-unit') and (entity.name:find('biter') or entity.name:find('spider')) then
            -- 检查是否已经是附魔虫子（通过标记或所有者判断）
            local is_already_enchanted = false
            for _, existing_biter in pairs(player_biters) do
                if existing_biter == entity then
                    is_already_enchanted = true
                    break
                end
            end
            
            if not is_already_enchanted then
                table.insert(available_bugs, entity)
            end
        end
    end
    
    -- 如果没有可用的虫子，尝试创建一只
    if #available_bugs == 0 then
        return true
    end
    
    -- 如果找到可用的虫子，转生它
    if #available_bugs > 0 then
        local target_bug = available_bugs[math.random(1, #available_bugs)]
        
        -- 杀死并转生虫子
        if target_bug.valid then
         
            local bug_name = target_bug.name
            local position = target_bug.position
            -- 重新创建虫子作为附魔虫子
               target_bug.die()
            local enchanted_bug = surface.create_entity({
                name = bug_name,
                position = position,
                force = 'player',  -- 设为玩家阵营
                quality = QUALITY_NAMES[q_idx or 1]
            })
            
            if enchanted_bug then
                -- 使用BiterPets系统驯服虫子
                
                BiterPets.biter_pets_tame_unit(player, enchanted_bug)
                rendering.draw_text {
        text = '已附魔',
        surface = enchanted_bug.surface,
         target =
            {
                entity = enchanted_bug,
                offset = { 0, -1.5 },
            },
        color = {
            r =  0.6 + 0.25,
            g = 0.6 + 0.25,
            b = 0.6 + 0.25,
            a = 1
        },
        scale = 1.05,
        font = 'default-large-semibold',
        alignment = 'center',
        scale_with_zoom = false
    }
                -- 记录到附魔虫子表
                if not this.fumo_biters[player.index] then
                    this.fumo_biters[player.index] = {}
                end
                table.insert(this.fumo_biters[player.index], enchanted_bug)
                
                -- 建立unit_number到玩家的映射
                if enchanted_bug.valid and enchanted_bug.unit_number then
                    this.fumo_biter_to_player[enchanted_bug.unit_number] = player.index
                end
               
                -- 显示激活消息
                local message = {'tianfu.fumo_over', 1}
                new_print(player, message)
                
                -- 添加视觉效果
                tame_unit_effects(player, enchanted_bug)
                Task.set_timeout_in_ticks(60 * 60 * 2, kill_forces, {enchanted_bug})
                return true
            end
        end
    end
    
    return false
end

Public.fumo = fumo

local function xunshoushi(player, q_idx)
    if not check_tick(player, 'xunshoushi') then
        return false
    end

    local surface = player.physical_surface
    local position = player.physical_position

    local allied_entities = surface.find_entities_filtered({
        position = position,
        radius = 16,
        force = {'player'},
        type = {'unit', 'spider-unit'}
    })

    local biter_class_data = BiterClass.get()

    local available_bugs = {}
    for _, entity in pairs(allied_entities) do
        if entity.valid and (entity.type == 'unit' or entity.type == 'spider-unit') and (entity.name:find('biter') or entity.name:find('spitter') or entity.name:find('spider')) then
            local unit_number = entity.unit_number
            if unit_number and not biter_class_data.mage_biter_units[unit_number] and not biter_class_data.warrior_biter_units[unit_number]  then
                table.insert(available_bugs, entity)
            end
        end
    end

    if #available_bugs == 0 then
        return true
    end

    local class_count = ({1, 1, 2, 2, 3})[q_idx or 1]
    local used = {}
    for _ = 1, math.min(class_count, #available_bugs) do
        local idx = math.random(1, #available_bugs)
        if not used[idx] then
            used[idx] = true
            local target_bug = available_bugs[idx]
            if target_bug.valid then
                local class_type = math.random(1, 2)
                if class_type == 1 then
                    BiterClass.add_mage_biter(target_bug)
                    new_print(player, {'tianfu.xunshoushi_mage'})
                else
                    BiterClass.add_warrior_biter(target_bug)
                    new_print(player, {'tianfu.xunshoushi_warrior'})
                end
                Task.set_timeout_in_ticks(60 * 60 * 2, kill_forces, {target_bug})
            end
        end
    end
     
    return true
end

Public.xunshoushi = xunshoushi

-- 天照：每三秒随机点燃1个敌人，直到敌人死亡
local function tianzhao(player, q_idx)
    if not check_tick(player, 'tianzhao') then
        return false
    end

    if not player or not player.valid or not player.character or not player.character.valid then
        return false
    end

    local surface = player.physical_surface
    local character = player.character
    local position = player.physical_position

    local enemies = surface.find_entities_filtered({
        position = position,
        radius = 20,
        force = game.forces.enemy,
        type = {"unit", "spider-unit"}
    })

    if #enemies > 0 then
        local target_count = math.min(({1, 2, 3, 4, 5})[q_idx or 1], #enemies)
        local targets = {}
        for _ = 1, target_count do
            local target = enemies[math.random(#enemies)]
            if target and target.valid then
                targets[target.unit_number or target] = target
            end
        end
        for _, target in pairs(targets) do
            if target and target.valid then
            surface.create_entity({
                name = "fire-sticker",
                position = position,
                source = character,
                target = target,
                force = "player",
                player = player,
            })
            end
        end
    end

    return true
end

Public.tianzhao = tianzhao

-- 超时空商店：每20分钟刷新商店物品，玩家可以以2折价格购买1件物品
local function chaoshikongshangdian(player, q_idx)
    if not check_tick(player, 'chaoshikongshangdian') then
        return false
    end

    local this = TPT.get()
    local index = player.index

    -- 初始化商店物品列表
    if not this.chaoshikongshangdian_items then
        this.chaoshikongshangdian_items = {}
    end
    if not this.chaoshikongshangdian_items[index] then
        this.chaoshikongshangdian_items[index] = {}
    end

    -- 从 basic_markets.lua 获取可购买的物品列表（稀有度大于5）
    local market_items = BasicMarkets.get_random_item(12, false, false, 5)
    
    if not market_items or #market_items == 0 then
        return false
    end
    
    -- 随机打乱物品列表
    table.shuffle_table(market_items)

    -- 保存24个物品
    local shop_items = {}
    local max_items = math.min(24, #market_items)
    
    for i = 1, max_items do
        local market_item = market_items[i]
        local item_name = market_item.offer.item
        
        -- 获取物品的原价（从市场列表中获取）
        local original_price = market_item.price[1].count
        
        -- 折扣随品质递增（传说仅0.4折）
        local discount_rate = ({0.2, 0.16, 0.12, 0.08, 0.04})[q_idx or 1]
        local discount_price = math.floor(original_price * discount_rate)
        
        -- 确保价格至少为1
        if discount_price < 1 then
            discount_price = 1
        end

        shop_items[i] = {
            item_name = item_name,
            item_count = 1,
            price = discount_price
        }
    end

    -- 存储商店物品列表
    this.chaoshikongshangdian_items[index] = shop_items

    -- 记录刷新时间
    this.chaoshikongshangdian_last_refresh[index] = game.tick

    -- 重置已花费金币，设置限额为10K
    this.chaoshikongshangdian_spent[index] = 0

    -- 通知玩家
    player.print({'tianfu.chaoshikongshangdian_refresh_list', #shop_items})

    return true
end

Public.chaoshikongshangdian = chaoshikongshangdian

Public.get_total_crafting_time = get_total_crafting_time

Public.insert_item_to_player = insert_item_to_player

local function qiche_ren(player, q_idx)
    if not check_tick(player, 'qiche_ren') then return false end
    
    return true
end


Public.qiche_ren = qiche_ren

Public.guajichengsheng = guajichengsheng
Public.yuediaoyuerou = yuediaoyuerou
Public.linghang = linghang
Public.duoduoyishan = duoduoyishan

return Public