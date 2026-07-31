-- maps/amap/world/worlds/world_17_grid_war.lua
-- 世界 17：网格战争
--
-- 玩法：以世界 1 为基底（65 分钟、默认堡垒模式），但移除石头/野外建筑生成。
--       旷野绝对空白（无矿、无树、无水、无野外虫巢），一切价值集中在
--       随机散布的「网格单元」里：
--         · 单元内净空 64×64（与中央安全区同尺寸），外圈 2 层水环，
--           随机 1 侧铺浅滩 —— 浅滩单位与载具都能通过，是该单元唯一出入口。
--         · 家单元 = 中央安全区本身，内含 4 种基础矿各 500k（总量 2M）。
--         · 非家单元建格时就按距离分层定死「将产出什么」，并用对应地砖标识
--           （地球=草地 / 火山系=volcanic / 电磁系=fulgoran / 草星系=尤马科土）。
--         · 单元内 15 虫巢 + 30 沙虫；打光全部虫巢即兑现资源，并在单元外侧
--           远离原点方向补刷 4 个虫巢。
--       堡垒不会生成在网格单元上（fortress_position_valid 钩子）。
--
-- 机制实现全在 maps/amap/world/word_grid_war.lua，本文件只做注册。

local World = require 'maps.amap.world.framework'
local GridWar = require 'maps.amap.world.word_grid_war'

--==============================================================================
-- 地形生成器（逐 tile 调用；只铺地砖，实体填充走 word_grid_war 的延迟队列）
--==============================================================================

local function terrain_generator(surface, position, seed, get_tile, set_tiles, event, maxs, q, w, x, y, area)
    if maxs < 64 then
        return
    end

    local cell, dx, dy = GridWar.cell_at(seed, position.x, position.y)
    if not cell then
        return
    end

    GridWar.paint_cell_tile(surface, position, cell, dx, dy)

    -- 登记单元进待填充队列。
    -- 不能只在 dx==0,dy==0 登记：单元跨 3×3 区块，玩家可能先只揭开边角区块，
    -- 中心 tile 尚未生成 → 该格永远不填虫巢。
    -- 改为「每 8 格取一次」：任意 32 宽的区块跨度内必有 8 的倍数，
    -- 保证每个与单元相交的区块都会命中至少一次；register_cell 内部有幂等检查。
    if dx % 8 == 0 and dy % 8 == 0 then
        GridWar.register_cell(cell)
    end
end

--==============================================================================
-- 注册到框架
--==============================================================================

World.register(17, {
    --==========================================================================
    -- 元数据
    --==========================================================================
    name_key = 'amap.world_name_17',
    desc_key = 'amap.world_name_info_17',
    -- 参与随机/投票选图
    selectable = true,

    --==========================================================================
    -- 时间与地形
    --==========================================================================
    -- 65 分钟（50 分钟游戏时间 + 15 分钟首波延迟），与世界 1 一致
    time_limit = 60 * 60 * 50 + 60 * 60 * 15,

    -- 旷野绝对空白配置（world_table.lua surface_configs.world17）
    surface_config_name = 'world17',

    map_settings = {
        starting_area = 1
    },

    -- 恢复默认野外生成：商店/箱子/组装机（weight_worm=0 故无野外虫巢）
    disable_default_rocks = false,

    terrain_generator = terrain_generator,

    --==========================================================================
    -- 战斗规则
    --==========================================================================
    -- 火焰塔上限走通用进化逻辑
    max_flame = nil,
    biter_spawn_rule = nil,
    ammo_damage_modifiers = nil,
    enemy_expansion = nil,

    --==========================================================================
    -- 堡垒生成
    --==========================================================================
    arty_settings = {
        mode = 'default'
    },
    -- 堡垒避让：不允许落在网格单元（含 16 格缓冲）内
    -- 由 stronghold_generation_algorithm_v2.is_sh_conflict 统一调用
    fortress_position_valid = GridWar.fortress_position_valid,

    --==========================================================================
    -- 星球与科技
    --==========================================================================
    -- 不额外开星球地表（外星资源直接长在本世界的网格单元里）
    planet_surfaces = nil,
    planet_resource_boost = nil,
    unlock_planet_technologies = nil,

    -- 开局解锁：回收（处理废料）与农业（处理草星植物），
    -- 否则网格里挖到的外星资源无法加工
    unlocked_technologies = {'recycling', 'agriculture'},

    -- 允许填海：跨水环除了走浅滩侧，也可自行填海开路
    landfill_allowed = true,

    --==========================================================================
    -- 通关奖励
    --==========================================================================
    -- 跟随机器人数量加成（继承自原「异次元空间」世界 8，该世界已禁用）
    world_bonus_type = {
        name = 'following_robot_count_modifier',
        force_modifier = 'following_robot_count_modifier',
        base_value = 3,
        max_value = 20
    },
    -- 参与终极奖励（世界通关挑战）
    joins_solar_system_edge = true,

    --==========================================================================
    -- 专属玩法钩子
    --==========================================================================
    on_car_buff = nil,
    on_car_buff_player = nil,
    on_gain_xp = nil,
    on_gain_xp_global = nil,
    on_tick = nil
})
