local WPT = require 'maps.amap.table'

local Public = {}
local random = math.random
local floor = math.floor

local function floaty_hearts(entity, c)
    local position = {x = entity.position.x - 0.75, y = entity.position.y - 1}
    local b = 1.35
    for _ = 1, c, 1 do
        local p = {
            (position.x + 0.4) + (b * -1 + random(0, b * 20) * 0.1),
            position.y + (b * -1 + random(0, b * 20) * 0.1)
        }
        entity.surface.create_entity({name = 'flying-text', position = p, text = '♥', color = {random(150, 255), 0, 255}})
    end
end
local function can_move(entity, player)

  local square_distance = (player.position.x - entity.position.x) ^ 2 + (player.position.y - entity.position.y) ^ 2
  if square_distance < 64 or square_distance > 25600 then
    return false
  end
  return true
end
local function tame_unit_effects(player, entity)
    floaty_hearts(entity, 7)

    rendering.draw_text {
        text = '~' .. player.name .. "'s pet~",
        surface = player.surface,
        target = entity,
        target_offset = {0, -2.6},
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



local function is_valid_player(player, unit)
    if not player.character then
        return
    end
    if not player.character.valid then
        return
    end
    if player.surface.index ~= unit.surface.index then
        return
    end
    return true
end

function Public.biter_pets_tame_unit(player, unit)
  local this=WPT.get()
  local index=player.index

  if unit.name =='biter-spawner' or unit.name =='spitter-spawner' then 
    tame_unit_effects(player, unit)
    return
  end
  if not this.biter_pets[index] then
     this.biter_pets[index]={}
  end
    local biter_pets = this.biter_pets[index]
    local temp_biters_pet={}
    for _,v in pairs(biter_pets) do 
      if v and v.valid then 
        temp_biters_pet[#temp_biters_pet+1]=v
      end
    end

    biter_pets=temp_biters_pet
    this.biter_pets[index]=biter_pets

    if #biter_pets >this.biter_max then
      player.print({'amap.too_many_biter'})
      unit.die()
      return false
    end

    unit.ai_settings.allow_destroy_when_commands_fail = true
    unit.ai_settings.allow_try_return_to_spawner = false
  
    biter_pets[#biter_pets+1] = unit
    tame_unit_effects(player, unit)

    --重新编组
    local unit_group = player.surface.create_unit_group({position = unit.position, force = 'player'})
    local follow_number = this.biter_follow_number
    local biter_arty=0
    for _,v in pairs(biter_pets) do 
      if biter_arty<follow_number then 
        if v and v.valid and can_move(v, player) then 
          unit_group.add_member(v)
          biter_arty=biter_arty+1
        end
      end
    end
    unit_group.set_command(
      {
        type = defines.command.wander,
        destination = unit.position,
        distraction = defines.distraction.by_enemy
      }
    )
    return true
end

function Public.tame_unit_for_closest_player(unit)
    local valid_players = {}
    for _, player in pairs(game.connected_players) do
        if is_valid_player(player, unit) then
            table.insert(valid_players, player)
        end
    end

    local nearest_player = valid_players[1]
    if not nearest_player then
        return
    end

    Public.biter_pets_tame_unit(nearest_player, unit, true)
end




local function command_unit(entity, player)
        entity.set_command(
            {
                type = defines.command.go_to_location,
                destination_entity = player.character,
                radius = 4,
                distraction = defines.distraction.by_damage
            }
        )

end

local function on_player_changed_position(event)

  if random(1, 100) ~= 1 then
      return
  end
  local this=WPT.get()
  local player = game.players[event.player_index]
  local index = player.index

  local biter_pets = this.biter_pets[index]
  if not biter_pets then return end
  if not player.character then
      return
  end

  if	not(player.surface.index == game.surfaces[this.active_surface_index].index) then return end

  if not this.biter_command[index] then
    this.biter_command[index]=0
  end

  if this.biter_command[index] + 600 > game.tick then
      return
  end

  this.biter_command[index]= game.tick


  local unit_group = player.surface.create_unit_group({position = player.position, force = 'player'})
  local follow_number = this.biter_follow_number
  local biter_arty=0
  for _,v in pairs(biter_pets) do 
    if biter_arty<follow_number then 
      if v and v.valid and can_move(v, player) then 
        unit_group.add_member(v)
        biter_arty=biter_arty+1
      end
    end
  end
  unit_group.set_command(
    {
      type = defines.command.wander,
      destination = player.position,
      distraction = defines.distraction.by_enemy
    }
  )
end


local event = require 'utils.event'
event.add(defines.events.on_player_changed_position, on_player_changed_position)

return Public
