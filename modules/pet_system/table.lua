-- 虫子宠物系统 - 全局数据表和常量
local Global = require 'utils.global'

local this = {
    pet_data = {},              -- player_index -> { pets = {...} }
    batch_player_index = 1,     -- 批处理索引
    unit_to_owner = {},         -- unit_number -> {player_index, pet_index} 反向索引
    deployed_pets = {},         -- 出战宠物列表 {{player_index, pet_index}, ...}
    lava_pools = {},            -- 熔岩池列表 {{position, surface, damage, remaining, player_index}, ...}
}

Global.register(
    this,
    function(tbl)
        this = tbl
    end
)

local Public = {}

-- GUI 元素唯一名称
Public.draw_main_button_name = 'pet_draw_main_button'
Public.main_frame_name = 'pet_main_frame'
Public.detail_frame_name = 'pet_detail_frame'
Public.confirm_frame_name = 'pet_confirm_frame'
Public.exp_transfer_frame_name = 'pet_exp_transfer_frame'
Public.skill_replace_frame_name = 'pet_skill_replace_frame'
Public.skill_book_frame_name = 'pet_skill_book_frame'
Public.help_frame_name = 'pet_help_frame'
Public.rename_frame_name = 'pet_rename_frame'

-- 按钮名称（用于卡片的点击）
Public.card_button_prefix = 'pet_card_button_'

-- ============================================================
-- 宠物名字生成
-- ============================================================

-- 名字前缀（形容词/描述词）
local pet_name_prefixes = {
    '小', '大', '铁', '钢', '铜', '金', '银', '赤',
    '火', '冰', '雷', '风', '血', '毒', '影', '光',
    '暗', '岩', '骨', '刃', '怒', '狂', '猛', '暴',
    '巨', '灵', '青', '黑', '白', '紫', '灰', '飞',
    '钻', '烈', '迅', '刚',
}

-- 名字后缀（身体部位/特征词）
local pet_name_suffixes = {
    '牙', '爪', '角', '鳞', '甲', '壳', '刺', '锤',
    '拳', '尾', '翼', '星', '月', '魂', '王', '兽',
    '虫', '龙', '虎', '狼', '蛇', '鹰', '蝎', '盾',
    '锥', '矛', '晶', '脊', '须',
}

-- 生成随机宠物名字（前缀+后缀组合，如 铁牙、雷魂、金翼）
function Public.generate_pet_name()
    local prefix = pet_name_prefixes[math.random(1, #pet_name_prefixes)]
    local suffix = pet_name_suffixes[math.random(1, #pet_name_suffixes)]
    return prefix .. suffix
end

-- 品质中文名（仅内部/调试用；对外显示走 locale）
-- 顺序按 Factorio 官方对照：1普通 2精良(uncommon) 3稀有(rare) 4史诗 5传说
Public.quality_names = {'普通', '精良', '稀有', '史诗', '传说'}

-- 返回品质的 localised 名（供 print / GUI caption）
function Public.quality_locale(q)
    return {'pet_system.quality_' .. (q or 1)}
end

Public.quality_colors = {
    {r = 200, g = 200, b = 200}, -- 1 普通 灰
    {r = 50,  g = 205, b = 50 }, -- 2 精良 绿(uncommon)
    {r = 30,  g = 144, b = 255}, -- 3 稀有 蓝(rare)
    {r = 147, g = 112, b = 219}, -- 4 史诗 紫
    {r = 255, g = 165, b = 0  }, -- 5 传说 橙
}

-- 品质每级技能点（idx 1..5）
Public.quality_skill_points = {5, 6, 7, 8, 9}

-- 获取宠物技能槽位数量（传说5个，其他品质4个）
function Public.get_skill_slots(pet)
    if pet.quality == 5 then
        return 5
    end
    return 4
end

-- 宠物类型中文名映射
Public.pet_type_names = {
    ['small-biter'] = {'pet_system.small_biter'},
    ['medium-biter'] = {'pet_system.medium_biter'},
    ['big-biter'] = {'pet_system.big_biter'},
    ['behemoth-biter'] = {'pet_system.behemoth_biter'},
    ['small-spitter'] = {'pet_system.small_spitter'},
    ['medium-spitter'] = {'pet_system.medium_spitter'},
    ['big-spitter'] = {'pet_system.big_spitter'},
    ['behemoth-spitter'] = {'pet_system.behemoth_spitter'},
    ['small-stomper-pentapod'] = {'pet_system.small_stomper'},
    ['medium-stomper-pentapod'] = {'pet_system.medium_stomper'},
    ['big-stomper-pentapod'] = {'pet_system.big_stomper'},
    ['small-strafer-pentapod'] = {'pet_system.small_strafer'},
    ['medium-strafer-pentapod'] = {'pet_system.medium_strafer'},
    ['big-strafer-pentapod'] = {'pet_system.big_strafer'},
    ['small-wriggler-pentapod'] = {'pet_system.small_wriggler'},
    ['medium-wriggler-pentapod'] = {'pet_system.medium_wriggler'},
    ['big-wriggler-pentapod'] = {'pet_system.big_wriggler'},
}

-- 技能名称列表（用于展示）
Public.skill_names = {
    '雷霆一击',
    '火焰盾',
    '水龙弹',
    '雷霆万钧',
    '疾风步',
    '毒雾',
    '冰霜护甲',
    '狂暴',
    '吸血光环',
    '荆棘光环',
}

-- 经验等级表（与RPG系统一致）
Public.experience_levels = {0}
for a = 1, 4999, 1 do
    Public.experience_levels[#Public.experience_levels + 1] = Public.experience_levels[#Public.experience_levels] + a * 4
end

-- ============================================================
-- 宠物蛋系统
-- ============================================================

-- 宠物蛋品质概率（idx 1..5）
local quality_weights = {
    low  = {70, 18, 8,  3,  1}, -- 普通70 精良18 稀有8 史诗3 传说1
    mid  = {50, 27, 15, 6,  2},
    high = {30, 30, 25, 10, 5},
}

-- 蛋和技能书价格
Public.egg_prices = {
    low = 10000,
    mid = 30000,
    high = 60000,
}
Public.skill_book_prices = {
    low = 10000,
    mid = 30000,
    high = 60000,
}

-- 加权随机抽奖（返回品质整数下标 1..5）
local function raffle(weights)
    local total = 0
    for _, w in ipairs(weights) do
        total = total + w
    end
    local r = math.random(1, total)
    local cumulative = 0
    for idx, w in ipairs(weights) do
        cumulative = cumulative + w
        if r <= cumulative then
            return idx
        end
    end
    return 1
end

-- 宠物蛋可抽到的小型宠物（中型/大型/巨兽通过进化获得）
local pet_type_unlocks = {
    {level = 1,   types = {'small-biter', 'small-spitter'}},
    {level = 15,  types = {'small-wriggler-pentapod'}},
    {level = 125, types = {'small-strafer-pentapod'}},
    {level = 185, types = {'small-stomper-pentapod'}},
}

function Public.get_available_pet_types(player_level)
    -- 收集所有已解锁的小型宠物类型
    local types = {}
    for _, unlock in ipairs(pet_type_unlocks) do
        if player_level >= unlock.level then
            for _, t in ipairs(unlock.types) do
                types[#types + 1] = t
            end
        end
    end
    return types
end

-- 基于威胁值的宠物基础属性（统一初始值，品质加成由后续 growth 计算）
local pet_base_stats = {
    ['small-biter']              = {base_attack = 5, base_hp = 5},
    ['small-spitter']            = {base_attack = 5, base_hp = 5},
    ['medium-biter']             = {base_attack = 5, base_hp = 5},
    ['medium-spitter']           = {base_attack = 5, base_hp = 5},
    ['big-biter']                = {base_attack = 5, base_hp = 5},
    ['big-spitter']              = {base_attack = 5, base_hp = 5},
    ['behemoth-biter']           = {base_attack = 5, base_hp = 5},
    ['behemoth-spitter']         = {base_attack = 5, base_hp = 5},
    ['small-wriggler-pentapod']  = {base_attack = 5, base_hp = 5},
    ['medium-wriggler-pentapod'] = {base_attack = 5, base_hp = 5},
    ['big-wriggler-pentapod']    = {base_attack = 5, base_hp = 5},
    ['small-strafer-pentapod']   = {base_attack = 5, base_hp = 5},
    ['medium-strafer-pentapod']  = {base_attack = 5, base_hp = 5},
    ['big-strafer-pentapod']     = {base_attack = 5, base_hp = 5},
    ['small-stomper-pentapod']   = {base_attack = 5, base_hp = 5},
    ['medium-stomper-pentapod']  = {base_attack = 5, base_hp = 5},
    ['big-stomper-pentapod']     = {base_attack = 5, base_hp = 5},
}

-- 宠物每分钟吃鱼量（与威胁值对应）
Public.fish_consumption = {
    ['small-biter']              = 1,
    ['small-spitter']            = 1,
    ['medium-biter']             = 4,
    ['medium-spitter']           = 4,
    ['big-biter']                = 16,
    ['big-spitter']              = 16,
    ['behemoth-biter']           = 64,
    ['behemoth-spitter']         = 64,
    ['small-wriggler-pentapod']  = 2,
    ['medium-wriggler-pentapod'] = 8,
    ['big-wriggler-pentapod']    = 32,
    ['small-strafer-pentapod']   = 160,
    ['medium-strafer-pentapod']  = 240,
    ['big-strafer-pentapod']     = 480,
    ['small-stomper-pentapod']   = 350,
    ['medium-stomper-pentapod']  = 640,
    ['big-stomper-pentapod']     = 1280,
}

-- ============================================================
-- 宠物进化系统
-- ============================================================

-- 进化链：当前类型 → {下一形态, 所需宠物等级}
-- 公式：进化等级 = 10 × √(目标威胁值)
Public.evolution_chains = {
    -- Biter 线
    ['small-biter']              = {next_type = 'medium-biter',          level = 20},
    ['medium-biter']             = {next_type = 'big-biter',             level = 40},
    ['big-biter']                = {next_type = 'behemoth-biter',        level = 80},
    -- Spitter 线
    ['small-spitter']            = {next_type = 'medium-spitter',        level = 20},
    ['medium-spitter']           = {next_type = 'big-spitter',           level = 40},
    ['big-spitter']              = {next_type = 'behemoth-spitter',      level = 80},
    -- Wriggler 线
    ['small-wriggler-pentapod']  = {next_type = 'medium-wriggler-pentapod', level = 30},
    ['medium-wriggler-pentapod'] = {next_type = 'big-wriggler-pentapod',    level = 55},
    -- Strafer 线
    ['small-strafer-pentapod']   = {next_type = 'medium-strafer-pentapod',  level = 155},
    ['medium-strafer-pentapod']  = {next_type = 'big-strafer-pentapod',     level = 220},
    -- Stomper 线
    ['small-stomper-pentapod']   = {next_type = 'medium-stomper-pentapod',  level = 255},
    ['medium-stomper-pentapod']  = {next_type = 'big-stomper-pentapod',     level = 360},
}

-- 检查并执行进化（仅改变类型，其他一律不变）
-- 返回: evolved (bool), new_type (string or nil)
function Public.check_evolution(pet)
    local evolved = false
    local new_type = nil
    while true do
        local chain = Public.evolution_chains[pet.type]
        if not chain then break end
        if pet.level < chain.level then break end
        new_type = chain.next_type
        pet.type = new_type
        evolved = true
    end
    return evolved, new_type
end

-- 品质吃鱼倍率（每分钟，idx 1..5）
Public.quality_fish_multiplier = {1.0, 1.25, 1.5, 1.75, 2.0}

-- 饱食度每分钟固定变化（无论品质）
Public.HUNGER_CHANGE = 10

-- 暴露基础属性供外部使用
function Public.get_pet_base_stats()
    return pet_base_stats
end

-- 公开的品质抽奖函数（供技能系统等使用）
function Public.roll_quality(egg_type)
    return raffle(quality_weights[egg_type])
end

-- 生成一只新宠物
function Public.generate_pet(player, egg_type, player_level)
    player_level = player_level or 1

    -- 1. 抽取品质
    local quality = raffle(quality_weights[egg_type])

    -- 2. 抽取类型
    local available_types = Public.get_available_pet_types(player_level)
    if #available_types == 0 then
        available_types = {'small-biter'}
    end
    local pet_type = available_types[math.random(1, #available_types)]

    -- 3. 初始等级固定为 1 级
    local level = 1

    -- 4. 基础属性（所有宠物统一初始值，品质和类型不影响）
    local base_attack = 5
    local base_hp = 5

    -- 5. 计算初始技能点（品质越高，每级技能点越多）
    local points_per_level = Public.quality_skill_points[quality]
    local skill_points = level * points_per_level

    -- 6. 生成名字
    local name = Public.generate_pet_name()

    -- 7. 构建宠物数据
    local pet = {
        name = name,
        type = pet_type,
        quality = quality,
        level = level,
        hunger = 100,
        max_hunger = 100,
        hp = base_hp,
        max_hp = base_hp,
        attack = base_attack,
        base_attack = base_attack,
        base_hp = base_hp,
        exp = 0,
        skill_points = skill_points,
        allocated_attack = 0,
        allocated_hp = 0,
        skills = {},
        created_tick = game.tick,  -- 创建时间，用于闭关修炼判断"未出战时长"
    }

    -- 初始化技能槽位（传说5个，其他4个）
    local slots = Public.get_skill_slots(pet)
    for i = 1, slots do
        pet.skills[i] = nil
    end

    return pet
end

-- 获取玩家宠物数据
function Public.get_player_pet_data(player)
    local index = player.index
    if not this.pet_data[index] then
        this.pet_data[index] = {
            pets = {},
        }
    end
    return this.pet_data[index]
end

-- 获取全局数据
function Public.get()
    return this
end

-- 重置全部宠物数据（地图重开时调用）
function Public.reset_table()
    this.pet_data = {}
    this.batch_player_index = 1
    this.unit_to_owner = {}
    this.deployed_pets = {}
    this.lava_pools = {}
end

return Public
