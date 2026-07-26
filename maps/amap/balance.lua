local Event = require 'utils.event'
local Difficulty = require 'modules.difficulty_vote_by_amount'

local Public = {}

--Public.events = {breached_wall = Event.generate_event_name('breached_wall')}

function Public.init_enemy_weapon_damage()
    local data = {
        --['artillery-shell'] = -1.3,
        ['biological'] = 0,
        ['bullet'] = 0,
        ['cannon-shell'] = 0,
        ['capsule'] = 0,
        ['electric'] = 0,
        ['flamethrower'] = 0,
        ['grenade'] = 0,
        ['landmine'] = 0,
        ['melee'] = 0,
        ['rocket'] = 0,
        ['shotgun-shell'] = 0,
        ['beam'] = 0,
        ['laser'] = 0,
        
       -- ['railgun'] = 0,
       -- ['combat-robot-beam'] = 0,
      --  ['combat-robot-laser'] = 0,
     --   ['laser-turret'] = 0
    }
    local e = game.forces.enemy

    e.technologies['refined-flammables-1'].researched = true
    e.technologies['laser-weapons-damage-1'].researched = true
    e.technologies['refined-flammables-2'].researched = true
    for k, v in pairs(data) do
        e.set_ammo_damage_modifier(k, v)
    end
end

local function enemy_weapon_damage()
    local e = game.forces.enemy

    local data = {
       ['artillery-shell'] = 0.4,
       ['biological'] = 0.08,
        ['bullet'] = 0.4,
        ['capsule'] = 0.24,
        ['electric'] = 0.16,
        ['flamethrower'] = 0.6,
        ['grenade'] = 0.5,
        ['landmine'] = 0.12,
        ['melee'] = 0.14,
        ['rocket'] = 0.7,
        ['beam'] = 0.24,
        ['laser'] = 0.5,
       -- ['combat-robot-beam'] = 0.08,
        --['combat-robot-laser'] = 0.08,
     --   ['laser-turret'] = 0.08
        --['shotgun-shell'] = 0.08
    }

    

    for k, v in pairs(data) do
        local new = Difficulty.get().difficulty_vote_value * v

        local e_old = e.get_ammo_damage_modifier(k)
        e.set_ammo_damage_modifier(k, new + e_old)
    end
end

--Event.add(Public.events.breached_wall, enemy_weapon_damage)

Event.on_nth_tick(54000, enemy_weapon_damage)

return Public
