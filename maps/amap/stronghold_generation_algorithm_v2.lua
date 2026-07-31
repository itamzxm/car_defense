local Public = {}
local table = {}

local Event = require 'utils.event'
local WPT = require 'maps.amap.table'
local Global = require 'utils.global'
local Task = require 'utils.task'
local Token = require 'utils.token'
local WD = require 'modules.wave_defense.table'
local World = require 'maps.amap.world.framework'

Global.register(
table,
function(tbl)
  table = tbl
end
) 

function Public.reset_table()
  table.rail=false
  table.tongbu=true
  table.first_pos={}
  table.robot_platform = nil
  table.rocket_silo = nil
end

function Public.clear_rocket_silo()
  table.rocket_silo = nil
  if table.silo_tag and table.silo_tag.valid then
    table.silo_tag.destroy()
    table.silo_tag = nil
  end
  table.robot_platform = nil
end

function Public.get_rocket_silo()
  if not table.rocket_silo then
    return false
  else
    return table.rocket_silo
  end
end
local player_build_no_character = {
  'steam-turbine',
  'assembling-machine-1',
  'assembling-machine-2',
  'assembling-machine-3',
  'oil-refinery',
  'chemical-plant',
  'car',
  'spidertron',
  'tank',
  'character',
  'electric-mining-drill',
  'laser-turret',
  'steam-engine',
  'roboport',
  'flamethrower-turret',
  'big-mining-drill'
    ,'foundry'
  ,'recycler'
  ,'electromagnetic-plant'
  ,'heating-tower','rail-support'
}
local player_build = {
  'steam-turbine',
  'assembling-machine-1',
  'assembling-machine-2',
  'assembling-machine-3',
  'oil-refinery',
  'chemical-plant',
  'car',
  'spidertron',
  'tank',
  'electric-mining-drill',
  'laser-turret',
  'steam-engine',
  'roboport',
  'flamethrower-turret',
  'big-mining-drill'
  ,'foundry'
  ,'recycler'
  ,'electromagnetic-plant'
  ,'heating-tower','rail-support'
}

local rail = {
  "straight-rail",
  "curved-rail-a",
  "curved-rail-b",
  'pumpjack'
}
-- 计算堡垒位置是否有冲突
-- return: true/false

local PI = 3.14

-- 核弹发射函数
local launch_nuclear_missile = Token.register(function(data)
    local rocket_silo = data.rocket_silo

    local surface = data.surface
    
    if not rocket_silo or not rocket_silo.valid then
        return
    end
    local wave_defense_table = WD.get_table()
    if not wave_defense_table.target then
        return
    end
    if not wave_defense_table.target.valid then
        return
    end
    local target = wave_defense_table.target
    
    -- 发射原子火箭
    surface.create_entity {
        name = 'atomic-rocket',
        position = {
            x = target.position.x,
            y = target.position.y - 100
        },
        force = 'enemy',
        source = {
            x = target.position.x,
            y = target.position.y - 100
        },
        target = target,
        speed = 1
    }
    
    game.print({'amap.enemy_atomic_rocket', target.position.x, target.position.y, surface.name})
    game.print('虫子已经发射核弹！', {255, 0, 0})
    
    -- 发射后清除发射井
end)
local is_sh_conflict = function(sh_pos,surface)

  local ok=true
  local juli = 110
  local position=sh_pos

  local this=WPT.get()

  -- 世界级堡垒落点校验（框架字段 fortress_position_valid）
  -- 供有特殊地形约束的世界使用（如世界17 网格战争：堡垒不得落在网格单元及其缓冲区内）。
  -- 返回 false 表示该点不可用；未声明该字段的世界不受影响。
  local fortress_valid = World.get_field(this.world_number, 'fortress_position_valid')
  if fortress_valid then
    local okpos, res = pcall(fortress_valid, position, surface)
    if okpos and res == false then
      return false
    end
  end

  local entities
  if WPT.world_number~=8 then
    entities = surface.find_entities_filtered{position = position, radius = juli, name = player_build , force = game.forces.player,limit =1}
    else
      entities  = surface.find_entities_filtered{position = position, radius = juli, name = player_build_no_character , force = game.forces.player,limit =1}
    end

  if #entities~=0 then
    ok=false
    return ok
  end


  local area = {left_top = {position.x-48, position.y-48}, right_bottom = {position.x+48, position.y+48}}
  local roboports=surface.find_entities_filtered({type = {"roboport"}, area = area,force=game.forces.enemy,limit =1})
  if #roboports~=0 then
      this.robot_time = this.robot_time + 1
    for k,v in pairs(roboports) do
      if not v.destructible then
if this.robot_time==8 then 
        if not table.rocket_silo or not table.rocket_silo.valid then
            -- 创建火箭发射井
            local entity=roboports[math.random(1,#roboports)]
            table.robot_platform = entity
            table.rocket_silo = surface.create_entity({
                name = "rocket-silo", 
                position = entity.position, 
                force = "enemy"
            })
            table.rocket_silo.destructible = false

            this.silo_tag=game.forces.player.add_chart_tag(surface, {
        position = entity.position,
        icon = { type = "entity", name = "rocket-silo" },
        text = '敌方核弹发射井',
    })
            if table.rocket_silo then
                game.print({'amap.enemy_rocket_silo', entity.position.x, entity.position.y, surface.name})
            end
        end
end

      
        ok=false
        return ok
      end
    end
  end

  local rails = surface.find_entities_filtered{position = position, radius = 48, name = rail , force = game.forces.player,limit =1}
  if #rails~=0 then
    ok=false
    if not table.rail then
      table.rail=true
      table.target=rails[1]
      table.tongbu=false
    end
    return ok
  end

  -- 增加堡垒计数器，确保每次调用都会增加
  return ok
end


-- 寻找可能生成堡垒的位置
-- params:
-- car_pos - 靶车位置
-- sh_dis - 堡垒间最小距离，同时也是搜索圆增长的步长（因为 x 轴上两个堡垒至少间隔这个距离，故半径增长不能少于此)
-- return: 堡垒位置

-- 新的搜索逻辑：
-- 1. 固定搜索半径，当检测冲突的时候，改变搜索角度
-- 2. 如果一圈搜索完都没有找到合适的位置，则增加搜索半径，从0角度开始进行第二次搜索
-- 3. 如果第二次搜索，也没有搜索到，则建设火箭发射井

function Public.find_available_stronghold_position(car_pos, sh_dis, surface, car, only_below)
    local this = WPT.get()
    this.robot_time = 0

    -- 如果火箭发射井已存在，不再处理（等待倒计时发射）
    if table.rocket_silo and table.rocket_silo.valid then
                      -- 添加3分钟倒计时警告
                game.print('警告：敌方核弹发射井将在3分钟后发射核弹！', {255, 0, 0})
                game.print('警告：敌方核弹发射井将在3分钟后发射核弹！！', {255, 0, 0})
                game.print('警告：敌方核弹发射井将在3分钟后发射核弹！！！', {255, 0, 0})
                
                -- 设置3分钟后发射核弹
                --重复10次
                for i=1,10 do
                Task.set_timeout_in_ticks(60 * 60 * 3*i, launch_nuclear_missile, {
                    rocket_silo = table.rocket_silo,
                    target = car,
                    surface = surface
                })
                end
        return nil
    end
    
    -- 初始化搜索参数
    local search_radius = sh_dis  -- 初始搜索半径
    local search_attempts = 0     -- 搜索轮次计数器
    local max_search_attempts = 10 -- 最大搜索轮次
    
    -- 角度增量（每步增加的角度）
    local angle_step
    if only_below then
        angle_step = PI / 7  -- 半个圆分成8个点，角度间隔为π/7
    else
        angle_step = 2 * PI / 15  -- 完整圆分成16个点，角度间隔为2π/15
    end
    
    -- 根据only_below参数确定搜索角度范围
    local max_angle_index
    if only_below then
        max_angle_index = 7  -- 半个圆（0到π），共8个点（0-7）
    else
        max_angle_index = 15  -- 完整圆（0到2π），共16个点（0-15）
    end
    
    -- 调试信息
    -- game.print("开始搜索堡垒位置，robot_time: " .. table.robot_time)
    
    -- 开始搜索循环
    while search_attempts < max_search_attempts do
        -- 每轮搜索从上一次的角度开始
--如果火箭发射井存在返回Nil
        if table.rocket_silo and table.rocket_silo.valid then
          return nil
        end

        local angle_index = this.theta_times
        
        -- 在当前半径下进行一圈搜索
        local initial_angle_index = angle_index
        while angle_index <= max_angle_index do
            -- 计算当前角度
            local sh_theta = angle_index * angle_step
            
            -- 计算候选位置
            local sh_pos_x = car_pos.x + search_radius * math.cos(sh_theta)
            local sh_pos_y = car_pos.y + search_radius * math.sin(sh_theta)
            local sh_pos = {x = sh_pos_x, y = sh_pos_y}
            
            -- 当only_below为true时，y<0的坐标视为无效
            local position_valid = true
            if only_below and sh_pos.y < 0 then
                position_valid = false
            end
            
            -- 检查位置是否有效且无冲突
            if position_valid and is_sh_conflict(sh_pos, surface) then
                -- 找到合适位置，更新theta_times并返回位置
                this.theta_times = angle_index + 1
                Public.reset_table()
                return sh_pos
            end
               if table.rocket_silo and table.rocket_silo.valid then
          return nil
        end
            
            -- 移动到下一个角度
            angle_index = angle_index + 1
        end
        
        -- 如果完成了一整圈搜索，重置theta_times
        if initial_angle_index == 0 and angle_index > max_angle_index then
            this.theta_times = 0
        end
        
        -- 如果当前半径的一圈搜索完成仍未找到合适位置，则增加搜索半径
        search_radius = search_radius + sh_dis
        search_attempts = search_attempts + 1
        
        -- 重置theta_times为0，以便在下一圈搜索中从头开始
        this.theta_times = 0
        
        -- 检查是否超出最大搜索半径限制
        if search_radius > 10000 then
            break
        end

        
    end
    
    -- 如果两轮搜索都未找到合适位置，则处理火箭发射井逻辑
    -- 当搜索尝试次数达到最大值时，建造火箭发射井
    if search_attempts >= max_search_attempts then
        -- 记录第一个位置用于火箭发射井
        -- 移除了对 table.robot_time 的判断条件
        local first_pos = {
            x = car_pos.x + sh_dis * math.cos(0),
            y = car_pos.y + sh_dis * math.sin(0)
        }
        table.first_pos = first_pos
        

        
        return nil
    end
    
    -- 如果所有搜索都失败，返回nil
    return nil
end

-- 监听物体死亡事件
local function on_entity_died(event)
    local entity = event.entity
    
    if not entity or not entity.valid then
        return
    end
    
    -- 检查死亡的物体是否是机器人平台
    if entity == table.robot_platform then
        
            -- 取消火箭发射井的无敌状态
            if table.rocket_silo and table.rocket_silo.valid then
                table.rocket_silo.destructible = true
                game.print('敌方堡垒已被摧毁！核弹发射井失去保护！', {255, 255, 0})
            end
            -- 清除机器人平台引用
            table.robot_platform = nil
            --清除标签
             if table.silo_tag and table.silo_tag.valid then
    table.silo_tag.destroy()
    table.silo_tag = nil
  end
    end
end

local function on_init()
  Public.reset_table()
end
Event.on_init(on_init)
Event.add(defines.events.on_entity_died, on_entity_died)
return Public