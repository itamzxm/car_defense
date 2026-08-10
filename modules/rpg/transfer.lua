-- transfer.lua
-- 属性点/天赋转移系统（从 rpg/functions.lua 抽取）
-- create_transfer_gui + execute_transfer：105 级玩家可将一半属性点和随机一半天赋转移给另一在线玩家
-- 挂载到 modules.rpg.table 的 Public 表（与原行为一致，gui.lua 经 Public.create_transfer_gui 调用不变）

local Public = require 'modules.rpg.table'
local Gui = require 'utils.gui'
local WPT = require 'maps.amap.table'
local tianfu_table = require 'maps.amap.tianfu_table'

-- 创建属性点和天赋转移界面
function Public.create_transfer_gui(player)
  local rpg_t = Public.get_value_from_player(player.index)
  
  -- 检查玩家是否已经转移过属性
  if rpg_t.transfered_once then
    player.print("您已经转移过属性和天赋，每人仅可转移一次！", {r = 1, g = 0.5, b = 0.5})
    return
  end
  
  --检查玩家等级是否达到105级
  if rpg_t.level < 105 then
    player.print("您的等级还未达到105级，无法转移属性！", {r = 1, g = 0.5, b = 0.5})
    return
  end

  -- 检查玩家是否还有属性点或天赋点
  if rpg_t.points_left <= 0 and rpg_t.strength <= 10 and rpg_t.magicka <= 10 and rpg_t.dexterity <= 10 and rpg_t.vitality <= 10 then
    player.print("您没有任何属性点或天赋可以转移！", {r = 1, g = 0.5, b = 0.5})
    return
  end
  
  local frame = player.gui.screen.add({type = "frame", name = Public.transfer_frame_name, caption = {'amap.rpg_transfer_title'}, direction = "vertical"})
  frame.auto_center = true
  
  local scroll_pane = frame.add({type = "scroll-pane", direction = "vertical"})
  scroll_pane.style.maximal_height = 300
  
  -- 获取在线玩家列表（排除自己）
  local online_players = {}
  for _, p in pairs(game.connected_players) do
    if p.index ~= player.index then
      table.insert(online_players, p)
    end
  end
  
  -- 如果没有其他在线玩家
  if #online_players == 0 then
    frame.add({type = "label", caption = {'amap.rpg_transfer_no_player'}})
    local close_button = frame.add({type = "button", caption = {'amap.rpg_transfer_close'}})
    close_button.style.font = "default-bold"
    close_button.name = "transfer_cancel_button"
    Gui.on_click("transfer_cancel_button", function(event)
      if frame and frame.valid then
        frame.destroy()
      end
    end)
    return
  end
  
  -- 为每个在线玩家创建按钮
  for _, target_player in pairs(online_players) do
    local button = scroll_pane.add({
      type = "button", 
      caption = target_player.name,
      name = "transfer_to_" .. target_player.index
    })
    button.style.font = "default-bold"
    button.style.minimal_width = 200
    
    -- 添加点击事件
    Gui.on_click("transfer_to_" .. target_player.index, function(event)
      -- 执行转移操作
      Public.execute_transfer(player, target_player)
      
      -- 关闭界面
      if frame and frame.valid then
        frame.destroy()
      end
    end)
  end
  
  -- 添加关闭按钮
  local close_button = frame.add({type = "button", caption = {'amap.rpg_transfer_cancel'}})
  close_button.style.font = "default-bold"
  close_button.name = "transfer_cancel_button"
  Gui.on_click("transfer_cancel_button", function(event)
    if frame and frame.valid then
      frame.destroy()
    end
  end)
end

-- 执行属性点和天赋转移
function Public.execute_transfer(source_player, target_player)
  local source_rpg = Public.get_value_from_player(source_player.index)
  local target_rpg = Public.get_value_from_player(target_player.index)
  
  -- 检查玩家是否已经转移过属性
  if source_rpg.transfered_once then
    source_player.print("您已经转移过属性和天赋，每人仅可转移一次！", {r = 1, g = 0.5, b = 0.5})
    return
  end
  
  -- 计算要转移的属性点（一半）
  local strength_to_transfer = math.floor((source_rpg.strength - 10) / 2)
  local magicka_to_transfer = math.floor((source_rpg.magicka - 10) / 2)
  local dexterity_to_transfer = math.floor((source_rpg.dexterity - 10) / 2)
  local vitality_to_transfer = math.floor((source_rpg.vitality - 10) / 2)
  
  -- 转移属性点
  if strength_to_transfer > 0 then
    source_rpg.strength = 10
    target_rpg.strength = target_rpg.strength + strength_to_transfer
  end
  
  if magicka_to_transfer > 0 then
    source_rpg.magicka = 10
    target_rpg.magicka = target_rpg.magicka + magicka_to_transfer
  end
  
  if dexterity_to_transfer > 0 then
    source_rpg.dexterity = 10
    target_rpg.dexterity = target_rpg.dexterity + dexterity_to_transfer
  end
  
  if vitality_to_transfer > 0 then
    source_rpg.vitality = 10
    target_rpg.vitality = target_rpg.vitality + vitality_to_transfer
  end
  
  -- 转移未分配的属性点
  local points_to_transfer = math.floor(source_rpg.points_left / 2)
  if points_to_transfer > 0 then
    source_rpg.points_left = 0
    target_rpg.points_left = target_rpg.points_left + points_to_transfer
  end
  
  -- 转移天赋
   local main_table = WPT.get()
   local tianfu = tianfu_table.get()
   local source_skills = main_table.skill and main_table.skill[source_player.name]
   -- ★ 方案 D 简化版：字典存储 skill_name -> q_idx，用 next 判断非空（# 对字典恒为 0）
   if source_skills and next(source_skills) then
     -- 确保目标玩家的skill表存在
     if not main_table.skill[target_player.name] then
       main_table.skill[target_player.name] = {}
     end

     -- 收集源玩家天赋 key 列表（用于随机抽取一半）
     local source_keys = {}
     for k, _ in pairs(source_skills) do
       table.insert(source_keys, k)
     end

     -- 计算要转移的天赋数量（一半）
     local skills_to_transfer = math.floor(#source_keys / 2)

     if skills_to_transfer > 0 then
       local transferred_skills = {}  -- set：skill_id -> true
       local skipped_skills = {}      -- set：skill_id -> true

       -- 随机选择天赋进行转移
       for i = 1, skills_to_transfer do
         if #source_keys > 0 then
           -- 从源玩家剩余天赋里随机抽一个
           local r = math.random(1, #source_keys)
           local skill_id = source_keys[r]
           local quality = source_skills[skill_id]

           -- 从待抽列表中移除，避免重复抽取
           table.remove(source_keys, r)

           -- 检查目标玩家是否已经学习了这个天赋
           local already_learned = (main_table.skill[target_player.name][skill_id] ~= nil)

           -- 无论转移还是跳过，都从源玩家学习表中移除（原逻辑：被抽中的天赋即消耗）
           source_skills[skill_id] = nil

           if already_learned then
             skipped_skills[skill_id] = true
           else
             -- 转移天赋学习表（含品质 q_idx）
             main_table.skill[target_player.name][skill_id] = quality
             transferred_skills[skill_id] = true

             -- 转移天赋启用状态表 tianfu_enabled
             local source_enabled = main_table.tianfu_enabled[source_player.index]
             local target_enabled = main_table.tianfu_enabled[target_player.index]

             if source_enabled and source_enabled[skill_id] ~= nil then
               if not target_enabled then
                 main_table.tianfu_enabled[target_player.index] = {}
                 target_enabled = main_table.tianfu_enabled[target_player.index]
               end
               target_enabled[skill_id] = source_enabled[skill_id]
             end

             if source_enabled then
               source_enabled[skill_id] = nil
             end

             -- 转移天赋执行表（tianfu[skill_id] = {玩家名...}）
             if tianfu[skill_id] then
               for idx, player_name in pairs(tianfu[skill_id]) do
                 if player_name == source_player.name then
                   table.remove(tianfu[skill_id], idx)
                   break
                 end
               end
             end

             if not tianfu[skill_id] then
               tianfu[skill_id] = {}
             end
             table.insert(tianfu[skill_id], target_player.name)
           end
         end
       end

       -- 统计数量并通知
       local transfer_count = 0
       for _ in pairs(transferred_skills) do transfer_count = transfer_count + 1 end
       local skip_count = 0
       for _ in pairs(skipped_skills) do skip_count = skip_count + 1 end

       if transfer_count > 0 or skip_count > 0 then
         if transfer_count > 0 then
           source_player.print("成功向玩家 " .. target_player.name .. " 转移了 " .. transfer_count .. " 个天赋！", {r = 0.5, g = 1, b = 0.5})
           target_player.print("从玩家 " .. source_player.name .. " 处获得了 " .. transfer_count .. " 个天赋！", {r = 0.5, g = 1, b = 0.5})
         end

         if skip_count > 0 then
           source_player.print("跳过了 " .. skip_count .. " 个天赋，因为目标玩家已经学习了这些天赋。", {r = 1, g = 0.8, b = 0.2})
         end
       end
     end
   end
  
  -- 标记源玩家已经转移过
  source_rpg.transfered_once = true
  
  -- 更新玩家状态
  Public.update_player_stats(source_player)
  Public.update_player_stats(target_player)
  
  -- 发送通知消息
  source_player.print("成功向玩家 " .. target_player.name .. " 转移了一半的属性点和天赋！您已无法再次转移。", {r = 0.5, g = 1, b = 0.5})
  target_player.print("从玩家 " .. source_player.name .. " 处获得了属性点和天赋！", {r = 0.5, g = 1, b = 0.5})
end

return Public
