local Public = {}
local Event = require 'utils.event'
local WPT = require 'maps.amap.table'
local WD = require 'modules.wave_defense.table'
local RPG = require 'modules.rpg.main'
local Loot = require 'maps.amap.loot'

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
    ['JiaoLH'] = true,

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

Event.on_nth_tick(60, wheel_destiny)

return Public
