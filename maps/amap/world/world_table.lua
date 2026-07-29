local Global = require 'utils.global'
local Event = require 'utils.event'

local this = {}
local Public = {}

Global.register(
    this,
    function(tbl)
        this = tbl
    end
)

function Public.reset_table()
  -- 地表生成配置
  -- 保留：被 framework 中各世界模块的 surface_config_name 引用
  this.surface_configs = {
    -- 洞穴世界 - 高资源频率，丰富矿产
    cave = {
      ["water"] = {frequency = 0.1, size = 0.1, richness = 0.1},
      ["coal"] = {frequency = 2, size = 1, richness = 0.7},
      ["stone"] = {frequency = 2, size = 1, richness = 0.7},
      ["copper-ore"] = {frequency = 2, size = 2, richness = 0.7},
      ["iron-ore"] = {frequency = 2, size = 2, richness = 0.7},
      ["uranium-ore"] = {frequency = 2, size = 2, richness = 0.7},
      ["crude-oil"] = {frequency = 3, size = 2, richness = 1.2},
      ["trees"] = {frequency = 1, size = 0.7, richness = 0.7},
      ["enemy-base"] = {frequency = 3, size = 2, richness = 1}
    },
    -- 四分之一资源 - 标准资源分布
    quarter = {
       ["water"] = {frequency = 0.1, size = 0.1, richness = 0.1},
      ["coal"] = {frequency = 1, size = 1, richness = 0.7},
      ["stone"] = {frequency = 1, size = 1, richness = 0.7},
      ["copper-ore"] = {frequency = 1, size = 2, richness = 0.7},
      ["iron-ore"] = {frequency = 1, size = 2, richness = 0.7},
      ["uranium-ore"] = {frequency = 1.4, size = 2, richness = 1},
      ["crude-oil"] = {frequency = 2, size = 2, richness = 1.2},
      ["trees"] = {frequency = 1, size = 0.7, richness = 0.7},
      ["enemy-base"] = {frequency = 3, size = 2, richness = 1}
    },
    -- 水世界 - 高水资源，无自然资源
    water = {
       ["water"] = {frequency = 0.1, size = 0.1, richness = 0.1},
        ["coal"] = {frequency = 1, size = 2, richness = 1.5},
      ["stone"] =  {frequency = 1, size = 2, richness = 1.5},
      ["copper-ore"] =  {frequency = 1, size = 2, richness = 1.5},
      ["iron-ore"] =  {frequency = 1, size = 2, richness = 1.5},
      ["uranium-ore"] = {frequency = 1, size = 2, richness = 1.5},
      ["crude-oil"] =  {frequency = 1, size = 2, richness = 1.5},
      ["trees"] = {frequency = 1, size = 0.7, richness = 0.7},
      ["enemy-base"] = {frequency = 3, size = 2, richness = 1}
    },
    -- 自由游戏 - 标准配置
    freeplay = {
      ["coal"] = {frequency = 1, size = 1, richness = 1},
      ["stone"] = {frequency = 1, size = 1, richness = 1},
      ["copper-ore"] = {frequency = 1, size = 1, richness = 1},
      ["iron-ore"] = {frequency = 1, size = 1, richness = 1},
      ["uranium-ore"] = {frequency = 1, size = 1, richness = 1},
      ["crude-oil"] = {frequency = 1, size = 1, richness = 1},
      ["trees"] = {frequency = 1, size = 1, richness = 1},
      ["enemy-base"] = {frequency = 3, size = 3, richness = 2}
    },
    -- 世界14：草星入侵 - 仅覆盖敌人配置，其余走Gleba原生默认
    world14 = {
      ["enemy-base"] = {frequency = 3, size = 3, richness = 1},
    },
    -- 全树木 - 高树木密度
    all_tree = {
      ["coal"] = {frequency = 2, size = 1, richness = 1},
      ["stone"] = {frequency = 2, size = 1, richness = 1},
      ["copper-ore"] = {frequency = 2, size = 2, richness = 1},
      ["iron-ore"] = {frequency = 2, size = 2, richness = 1},
      ["uranium-ore"] = {frequency = 2, size = 2, richness = 1},
      ["crude-oil"] = {frequency = 3, size = 2, richness = 1.2},
      ["trees"] = {frequency = 3, size = 4, richness = 0.7},
      ["enemy-base"] = {frequency = 3, size = 1.5, richness = 1.5}
    },
    -- 全虫子 - 极高敌人密度
    all_biter = {
      ["coal"] = {frequency = 10, size = 10, richness = 5},
      ["stone"] = {frequency = 10, size = 10, richness = 5},
      ["copper-ore"] = {frequency = 10, size = 10, richness = 5},
      ["iron-ore"] = {frequency = 10, size = 10, richness = 5},
      ["uranium-ore"] = {frequency = 10, size = 10, richness = 5},
      ["crude-oil"] = {frequency = 10, size = 10, richness = 5},
      ["trees"] = {frequency = 1, size = 1, richness = 1},
      ["enemy-base"] = {frequency = 10, size = 10, richness = 2}
    },
    -- 竞技场 - 极高资源密度
    jjc = {
      ["coal"] = {frequency = 10, size = 10, richness = 5},
      ["stone"] = {frequency = 10, size = 10, richness = 5},
      ["copper-ore"] = {frequency = 10, size = 10, richness = 5},
      ["iron-ore"] = {frequency = 10, size = 10, richness = 5},
      ["uranium-ore"] = {frequency = 10, size = 10, richness = 5},
      ["crude-oil"] = {frequency = 10, size = 10, richness = 5},
      ["trees"] = {frequency = 1, size = 1, richness = 1},
      ["enemy-base"] = {frequency = 10, size = 3, richness = 2}
    },
    -- 混合矿石 - 标准混合配置
    mix_ore = {
      ["coal"] = {frequency = 2, size = 1, richness = 0.7},
      ["stone"] = {frequency = 2, size = 1, richness = 0.7},
      ["copper-ore"] = {frequency = 2, size = 2, richness = 0.7},
      ["iron-ore"] = {frequency = 2, size = 2, richness = 0.7},
      ["uranium-ore"] = {frequency = 2, size = 2, richness = 0.7},
      ["crude-oil"] = {frequency = 3, size = 2, richness = 1.2},
      ["trees"] = {frequency = 1, size = 0.7, richness = 0.7},
      ["enemy-base"] = {frequency = 3, size = 2, richness = 1}
    },
    -- 无矿石 - 无资源生成
    no_ore = {
      ["coal"] = {frequency = 1, size = 0, richness = 1},
      ["stone"] = {frequency = 1, size = 0, richness = 1},
      ["copper-ore"] = {frequency = 1, size = 0, richness = 1},
      ["iron-ore"] = {frequency = 1, size = 0, richness = 1},
      ["uranium-ore"] = {frequency = 1, size = 0, richness = 1},
      ["crude-oil"] = {frequency = 1, size = 0, richness = 1},
      ["trees"] = {frequency = 2, size = 1, richness = 1},
      ["enemy-base"] = {frequency = 5, size = 4, richness = 2}
    },
    -- 世界15 塔防：无矿石、无树木、无野外虫巢（敌人仅由波次系统生成），地表由 terrain_generator 覆盖为十字
    world15 = {
      ["water"] = {frequency = 1, size = 1, richness = 1},
      ["coal"] = {frequency = 1, size = 0, richness = 1},
      ["stone"] = {frequency = 1, size = 0, richness = 1},
      ["copper-ore"] = {frequency = 1, size = 0, richness = 1},
      ["iron-ore"] = {frequency = 1, size = 0, richness = 1},
      ["uranium-ore"] = {frequency = 1, size = 0, richness = 1},
      ["crude-oil"] = {frequency = 1, size = 0, richness = 1},
      ["trees"] = {frequency = 0, size = 0, richness = 1},
      ["enemy-base"] = {frequency = 0, size = 0, richness = 0}
    },
    -- 铁路模式 - 高资源密度，无树木
    rail = {
      ["coal"] = {frequency = 2, size = 1, richness = 1},
      ["stone"] = {frequency = 2, size = 1, richness = 1},
      ["copper-ore"] = {frequency = 3, size = 2, richness = 1},
      ["iron-ore"] = {frequency = 3, size = 2, richness = 1},
      ["uranium-ore"] = {frequency = 2.8, size = 2, richness = 1},
      ["crude-oil"] = {frequency = 4, size = 2, richness = 1.2},
      ["trees"] = {frequency = 1, size = 0, richness = 1},
      ["enemy-base"] = {frequency = 10, size = 4, richness = 1}
    },
    -- 无矿石无虫子 - 安全但无资源
    no_ore_no_biter = {
       ["water"] = {frequency = 0.1, size = 0.1, richness = 0.1},
      ["coal"] = {frequency = 1, size = 0, richness = 1},
      ["stone"] = {frequency = 1, size = 0, richness = 1},
      ["copper-ore"] = {frequency = 1, size = 0, richness = 1},
      ["iron-ore"] = {frequency = 1, size = 0, richness = 1},
      ["uranium-ore"] = {frequency = 1, size = 0, richness = 1},
      ["crude-oil"] = {frequency = 1, size = 0, richness = 1},
      ["trees"] = {frequency = 2, size = 1, richness = 1},
      ["enemy-base"] = {frequency = 2, size = 2, richness = 0}
    },
    -- 有矿石无虫子 - 安全有资源
    have_ore_no_biter = {
       ["water"] = {frequency = 0.1, size = 0.1, richness = 0.1},
      ["coal"] = {frequency = 1.5, size = 1.5, richness = 1.5},
      ["stone"] = {frequency = 1, size = 1, richness = 1.5},
      ["copper-ore"] = {frequency = 1.5, size = 2, richness = 1.5},
      ["iron-ore"] = {frequency = 1.5, size = 2, richness = 1.5},
      ["uranium-ore"] = {frequency = 1, size = 1, richness = 1.8},
      ["crude-oil"] = {frequency = 1, size = 1, richness = 1.5},
      ["trees"] = {frequency = 1, size = 1, richness = 1},
      ["enemy-base"] = {frequency = 1, size = 0, richness = 1}
    },
    -- 螺旋世界 - 蚊香圈地形
    spiral = {
      ["coal"] = {frequency = 1.2, size = 1.2, richness = 1.2},
      ["stone"] = {frequency = 1, size = 1, richness = 1.2},
      ["copper-ore"] = {frequency = 1.2, size = 1.5, richness = 1.2},
      ["iron-ore"] = {frequency = 1.2, size = 1.5, richness = 1.2},
      ["uranium-ore"] = {frequency = 1, size = 1, richness = 1.5},
      ["crude-oil"] = {frequency = 1.5, size = 1.5, richness = 1.5},
      ["trees"] = {frequency = 0.8, size = 0.8, richness = 0.8},
      ["enemy-base"] = {frequency = 2, size = 1.5, richness = 1}
    },
    -- 机械城市 - 高科技防御型世界
    jixianchengshi = {
       ["water"] = {frequency = 0.1, size = 0.1, richness = 0.1},
      ["coal"] = {frequency = 2, size = 1, richness = 0.7},
      ["stone"] = {frequency = 2, size = 1, richness = 0.7},
      ["copper-ore"] = {frequency = 2, size = 2, richness = 0.7},
      ["iron-ore"] = {frequency = 2, size = 2, richness = 0.7},
      ["uranium-ore"] = {frequency = 2, size = 2, richness = 0.7},
      ["crude-oil"] = {frequency = 3, size = 2, richness = 1.2},
      ["trees"] = {frequency = 1, size = 0.7, richness = 0.7},
      ["enemy-base"] = {frequency = 1, size = 0, richness = 1}
    },
    -- 背水一战 - 无矿只有树
    beishuiyizhan = {
       ["water"] = {frequency = 0.1, size = 0.1, richness = 0.1},
      ["coal"] = {frequency = 1, size = 0, richness = 1},
      ["stone"] = {frequency = 1, size = 0, richness = 1},
      ["copper-ore"] = {frequency = 1, size = 0, richness = 1},
      ["iron-ore"] = {frequency = 1, size = 0, richness = 1},
      ["uranium-ore"] = {frequency = 1, size = 0, richness = 1},
      ["crude-oil"] = {frequency = 1, size = 0, richness = 1},
      ["trees"] = {frequency = 1, size = 0.7, richness = 0.7},
      ["enemy-base"] = {frequency = 1, size = 0, richness = 1}
    }
  }
  -- 注：world_time / world_surface_mapping / world_map_settings / biter_spawn_rules
  -- 已迁移到各世界模块（maps/amap/world/worlds/world_XX_*.lua），
  -- 通过 World.register() 注册到 framework 中统一管理。
end

function Public.get(key)
  if key then
    return this[key]
  else
    return this
  end
end

function Public.set(key, value)
  if key and (value or value == false) then
    this[key] = value
    return this[key]
  elseif key then
    return this[key]
  else
    return this
  end
end

local on_init = function()
  Public.reset_table()
end

Event.on_init(on_init)

return Public
