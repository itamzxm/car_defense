local RPGtable = require 'modules.rpg.table'
local Loot = require "maps.amap.loot"
local BiterRolls = require 'modules.wave_defense.biter_rolls'
local Pets = require 'maps.amap.biter_pets'
local WPT = require 'maps.amap.table'
local Alert = require 'utils.alert'
local WD = require 'modules.wave_defense.table'
local Task = require 'utils.task'
local Token = require 'utils.token'
local random = math.random

local ent_to_create = {'biter-spawner', 'spitter-spawner'}



local function unstuck_player(index)
  local player = game.get_player(index)
  local surface = player.physical_surface
  if player.physical_surface.name ~= 'nauvis' then return end
  local position = surface.find_non_colliding_position('character', player.physical_position, 32, 0.5)
  if not position then
    return
  end
  player.teleport(position, surface)
end

local do_biter =
Token.register(
function(data)
  local surface=data.surface
  local name=data.name
  local pos=data.position
   surface.create_entity({name = name, position = pos,force=game.forces.enemy})
end
)
local function hidden_biter(entity)
  if not entity or not entity.valid then return end
  local pos = entity.position
  local roll = math.random(1, 2)
  local name
  if roll == 1 then
    name = BiterRolls.wave_defense_roll_spitter_name()
  elseif roll == 2 then
    name = BiterRolls.wave_defense_roll_biter_name()
  else
    name = BiterRolls.wave_defense_roll_worm_name()
  end
  if not name then return end
  local wave_number = WD.get('wave_number')
  local count = math.floor(wave_number*0.1)+math.random(1,10)
  if count>= 30 then count=30 end
  local data={}
  data.surface=entity.surface
  data.position=pos
  data.name=name
  for i=1,count do
    Task.set_timeout_in_ticks(i*30, do_biter, data)
  end

end

local function hidden_biter_pet(player, entity)
  if not entity or not entity.valid then return end
  local pos = entity.position
  local name
  local unit
  if math.random(1, 3) == 1 then
    name =BiterRolls.wave_defense_roll_spitter_name()
  else
    name = BiterRolls.wave_defense_roll_biter_name()
  end
  if name then
    unit = entity.surface.create_entity({name = name, position = pos,force=game.forces.player})
    Pets.biter_pets_tame_unit(game.players[player.index], unit)
  end
end
local function hidden_treasure(player, entity)
  if not entity or not entity.valid then return end
  local rpg = RPGtable.get('rpg_t')
  local magic = rpg[player.index].magicka
  local msg = 'look,you find a treasure'
  Alert.alert_player(player, 5, msg)
  Loot.add_rare(entity.surface, entity.position, 'wooden-chest', magic)
end


local function on_player_mined_entity(event)
  local entity = event.entity
  if not entity.valid then return end
  if entity.type ~= "simple-entity" and entity.type ~= "tree" then

     return 
     end
     if entity.surface ~= game.surfaces['nauvis'] then
    return
  end
  local surface = entity.surface
  local this = WPT.get()

  if	surface== this.yiciyuan_surface then return end
 
  if event.player_index then game.players[event.player_index].insert({name = "coin", count = 1}) end
  local player = game.players[event.player_index]
  local rpg = RPGtable.get('rpg_t')
  local rpg_char = rpg[player.index]
  if rpg_char.stone_path then
    entity.surface.set_tiles({{name = 'stone-path', position = entity.position}}, true)
  end


  if math.random(1,2048) < 2 then
    local position = {entity.position.x , entity.position.y }
    surface.create_entity({name = 'tank', position = position, force = 'player'})
    unstuck_player(player.index)
    local msg = ('You find a tank!')
    Alert.alert_player(player, 15, msg)
  end

  if math.random(1,150) < 2 then
    local position = {entity.position.x , entity.position.y }
    local e = surface.create_entity({name = ent_to_create[math.random(1, #ent_to_create)], position = position, force = 'enemy'})
    e.destructible = false
    this.biter_wudi[#this.biter_wudi+1]=e
    unstuck_player(player.index)
  end
  if math.random(1,150)  < 2 then
    hidden_treasure(player,entity)
  end
  if math.random(1,170)  < 3 then
    hidden_biter_pet(player,entity)
  end
  if math.random(1,100)  < 3 then
    hidden_biter(entity)
   end
end

local function on_entity_died(event)

  if not event.entity then return end
  if not event.entity.valid then return end

if event.entity.surface ~= game.surfaces['nauvis'] then
    return
  end
  local this = WPT.get()
  if not this.active_surface_index or not game.surfaces[this.active_surface_index] or not event.entity.surface then return end
  if not(event.entity.surface.index == game.surfaces[this.active_surface_index].index) then return end


  local force = event.entity.force
  if force and force.index == game.forces.player.index then
    local name = event.entity.name


    if name =="artillery-wagon" or name =="artillery-turret" then
          local unit_number=event.entity.unit_number
      if this.water_arty[unit_number] then
         this.water_arty[unit_number] =nil
      end
    end

    if name == 'flamethrower-turret' then
      this.flame = this.flame - 1
      if this.flame <= 0 then
        this.flame = 0
      end
      return
    end

    if name == 'land-mine' then
      this.now_mine = this.now_mine - 1
      if this.now_mine <= 0 then
        this.now_mine = 0
      end
        return
    end

    if name == 'tesla-turret' then
      this.tesla = this.tesla - 1
      if this.tesla <= 0 then
        this.tesla = 0
      end
      return
    end

    if name == 'railgun-turret' then
      this.railgun = this.railgun - 1
      if this.railgun <= 0 then
        this.railgun = 0
      end
      return
    end

  end

end
local Event = require 'utils.event'
Event.add(defines.events.on_entity_died, on_entity_died)
Event.add(defines.events.on_player_mined_entity, on_player_mined_entity,{
    {filter = "type", type = 'simple-entity'},
    {filter = "type", type = 'linked-chest'},
    {filter = "type", type = 'car'},
    
    {filter = "type", type = 'artillery-wagon'},
    {filter = "type", type = 'artillery-turret'},
    {filter = "type", type = 'land-mine'},
    {filter = "type", type = 'spider-vehicle'},
    {filter = "type", type = 'ammo-turret'},
    {filter = "type", type = 'electric-turret'},
    {filter = "type", type = 'fluid-turret'},
	{filter = "type", type = 'tree'}
})
