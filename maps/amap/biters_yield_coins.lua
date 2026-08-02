local Event = require 'utils.event'
local insert = table.insert
local floor = math.floor
local WPT = require 'maps.amap.table'
local World = require 'maps.amap.world.framework'

local coin_yield = {
  ['behemoth-biter'] = 6,
  ['behemoth-spitter'] = 6,
  ['behemoth-worm-turret'] = 24,
  ['big-biter'] = 4,
  ['big-spitter'] = 4,
  ['big-worm-turret'] = 19,
  ['biter-spawner'] = 38,
  ['medium-biter'] = 2,
  ['medium-spitter'] = 2,
  ['medium-worm-turret'] = 14,
  ['small-biter'] = 1,
  ['small-spitter'] = 1,
  ['small-worm-turret'] = 10,
  ['spitter-spawner'] = 38,
  -- 新pentapod类敌人
  ['big-stomper-pentapod'] = 36,
  ['medium-stomper-pentapod'] = 24,
  ['small-stomper-pentapod'] = 12,
  ['big-strafer-pentapod'] = 18,
  ['medium-strafer-pentapod'] = 7,
  ['small-strafer-pentapod'] = 8,
  ['big-wriggler-pentapod'] = 6,
  ['medium-wriggler-pentapod'] = 2,
  ['small-wriggler-pentapod'] = 1
}

local entities_that_earn_coins = {
  ['artillery-turret'] = true,
  ['gun-turret'] = true,
  ['laser-turret'] = true,
  ['flamethrower-turret'] = true
}

local function get_coin_count(entity)
  local coin_count = coin_yield[entity.name]
  if not coin_count then
    return
  end
  return coin_count
end

local function insert_coin_to_player(player, coin_count)
  if not player or not player.valid then
    return false
  end

  if not coin_count or coin_count <= 0 then
    return false
  end

  if not player.character then
    return false
  end

  if player.index == nil then
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

local function on_entity_died(event)
  local entity = event.entity
  if not entity.valid then
    return
  end
  if entity.force.index ~= 2 then
    return
  end

  -- 世界框架：部分世界（如世界15）使用自身奖励表独立给币，此处排除避免双重给币
  if World.get_field((WPT.get() or {}).world_number, 'custom_enemy_reward') then
    return
  end

  if math.random(1, 3) ~=1 then
return
  end
  local cause = event.cause

  local coin_count = get_coin_count(entity)
  if not coin_count  then
    return
  end

  local players_to_reward = {}
  local p
  local reward_has_been_given = false

  if cause then
    if cause.valid then
      if (cause and cause.name == 'character' and cause.player) then
        p = cause.player
      end

      if cause.name == 'character' then
        insert(players_to_reward, cause.player)
        reward_has_been_given = true
      end
      if cause.type == 'car' then
        local player = cause.get_driver()
        local passenger = cause.get_passenger()
        if player then
          insert(players_to_reward, player.player)
        end
        if passenger then
          insert(players_to_reward, passenger.player)
        end
        reward_has_been_given = true
      end
      if cause.type == 'locomotive' then
        local train_passengers = cause.train.passengers
        if train_passengers then
          for _, passenger in pairs(train_passengers) do
            insert(players_to_reward, passenger)
          end
          reward_has_been_given = true
        end
      end
      for _, player in pairs(players_to_reward) do
        insert_coin_to_player(player, coin_count)
      end
    end



    if entities_that_earn_coins[cause.name] then
      local this=WPT.get()
       if not this.gun_turret then
          this.gun_turret = {}
       end
       local index = this.gun_turret[cause.unit_number]
       if index then
        local player = game.players[index]
        if player.character and player.character.valid then
          insert_coin_to_player(player, coin_count)
          reward_has_been_given = true
        end
       end
    end
  end
  if cause then
    if  cause.last_user and not reward_has_been_given then
      local player = cause.last_user

      if player.character and player.character.valid then
        insert_coin_to_player(player, coin_count)
      end
    end
  end

end

Event.add(defines.events.on_entity_died, on_entity_died)
