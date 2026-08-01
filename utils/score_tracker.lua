local Global = require 'utils.global'
local Event = require 'utils.event'
local error = error
local format = string.format
local raise_event = script.raise_event

-- 统计框架：登记制 score 的持久化读写 + 变更事件通知（照 RedMew score_tracker 移植）。
-- 登记制的意义：score 必须先 register 才能读写，杜绝手滑拼错键名静默创建新统计。
-- 具体的统计口径（键名/图标/locale）由各业务模块登记，本文件不预置任何统计项。

local score_metadata = {}

local memory_players = {}
local memory_global = {}

Global.register(
    {memory_players = memory_players, memory_global = memory_global},
    function(tbl)
        memory_players = tbl.memory_players
        memory_global = tbl.memory_global
    end
)

Event.add(defines.events.on_player_removed, function(event)
    memory_players[event.player_index] = nil
end)

local Public = {}

Public.events = {
    -- Event { score_name = score_name, player_index = player_index }
    on_player_score_changed = Event.generate_event_name('on_player_score_changed'),
    -- Event { score_name = score_name }
    on_global_score_changed = Event.generate_event_name('on_global_score_changed')
}

local on_player_score_changed = Public.events.on_player_score_changed
local on_global_score_changed = Public.events.on_global_score_changed

--- 登记一个统计项。必须在加载期（control 阶段）调用。
-- @param name 统计键名（本模块内唯一）
-- @param locale_string locale 引用，如 {'amap.xxx'}
-- @param icon 图标名
function Public.register(name, locale_string, icon)
    if _LIFECYCLE ~= _STAGE.control then
        error(format('score 类型只能在加载期（control 阶段）登记，不能在事件内调用。试图登记: "%s"。', name), 2)
    end

    if score_metadata[name] then
        error(format('统计项 "%s" 已被登记，禁止重复登记。', name), 2)
    end

    local score = {
        name = name,
        icon = icon,
        locale_string = locale_string
    }

    score_metadata[name] = score

    return score
end

--- 玩家统计增减
function Public.change_for_player(player_index, score_name, value)
    if value == 0 then
        return
    end

    local setting = score_metadata[score_name]
    if not setting then
        if _DEBUG then
            error(format('试图增减未登记的统计项 "%s"。', score_name), 2)
        end
        return
    end

    local player_score = memory_players[player_index]
    if not player_score then
        player_score = {}
        memory_players[player_index] = player_score
    end

    player_score[score_name] = (player_score[score_name] or 0) + value

    raise_event(
        on_player_score_changed,
        {score_name = score_name, player_index = player_index}
    )
end

--- 全局统计增减
function Public.change_for_global(score_name, value)
    if value == 0 then
        return
    end

    local setting = score_metadata[score_name]
    if not setting then
        if _DEBUG then
            error(format('试图增减未登记的统计项 "%s"。', score_name), 2)
        end
        return
    end

    memory_global[score_name] = (memory_global[score_name] or 0) + value

    raise_event(
        on_global_score_changed,
        {score_name = score_name}
    )
end

--- 全局统计赋值（值不变时跳过，不发事件）
function Public.set_for_global(score_name, value)
    if not value then
        value = 0
    end

    local setting = score_metadata[score_name]
    if not setting then
        if _DEBUG then
            error(format('试图为未登记的统计项 "%s" 赋值。', score_name), 2)
        end
        return
    end

    local previous_value = Public.get_for_global(score_name)
    if value == previous_value then
        return
    end

    memory_global[score_name] = value

    raise_event(
        on_global_score_changed,
        {score_name = score_name}
    )
end

--- 玩家统计赋值（值不变时跳过，不发事件）
function Public.set_for_player(player_index, score_name, value)
    if not value then
        value = 0
    end

    local setting = score_metadata[score_name]
    if not setting then
        if _DEBUG then
            error(format('试图为未登记的统计项 "%s" 赋值。', score_name), 2)
        end
        return
    end

    local player_score = memory_players[player_index]
    if not player_score then
        player_score = {}
        memory_players[player_index] = player_score
    end

    local previous_value = Public.get_for_player(player_index, score_name)
    if value == previous_value then
        return
    end

    player_score[score_name] = value

    raise_event(
        on_player_score_changed,
        {score_name = score_name, player_index = player_index}
    )
end

--- 清零所有已登记统计
function Public.reset()
    for score_name, _ in pairs(memory_global) do
        Public.set_for_global(score_name, 0)
    end
    for player_index, player_memory in pairs(memory_players) do
        for score_name, _ in pairs(player_memory) do
            Public.set_for_player(player_index, score_name, 0)
        end
    end
end

--- 读取玩家统计；未登记返回 nil，登记但无记录返回 0
function Public.get_for_player(player_index, score_name)
    local setting = score_metadata[score_name]
    if not setting then
        return nil
    end

    local player_scores = memory_players[player_index]
    if not player_scores then
        return 0
    end

    return player_scores[score_name] or 0
end

--- 读取全局统计；未登记返回 0
function Public.get_for_global(score_name)
    local setting = score_metadata[score_name]
    if not setting then
        return 0
    end

    return memory_global[score_name] or 0
end

--- 返回指定统计项的元数据 + 玩家值合并表（供 GUI 展示）
function Public.get_player_scores_with_metadata(player_index, score_names)
    local scores = {}
    local size = 0
    for i = 1, #score_names do
        local score_name = score_names[i]
        local metadata = score_metadata[score_name]
        if metadata then
            local player_scores = memory_players[player_index]
            if player_scores then
                size = size + 1
                scores[size] = {
                    name = metadata.name,
                    locale_string = metadata.locale_string,
                    icon = metadata.icon,
                    value = player_scores[score_name] or 0
                }
            end
        end
    end

    return scores
end

--- 返回指定统计项的元数据 + 全局值合并表（供 GUI 展示）
function Public.get_global_scores_with_metadata(score_names)
    local scores = {}
    local size = 0
    for i = 1, #score_names do
        local score_name = score_names[i]
        local metadata = score_metadata[score_name]
        if metadata then
            size = size + 1
            scores[size] = {
                name = metadata.name,
                locale_string = metadata.locale_string,
                icon = metadata.icon,
                value = memory_global[score_name] or 0
            }
        end
    end

    return scores
end

--- 返回全部统计元数据（引用，勿直接修改）
function Public.get_score_metadata()
    return score_metadata
end

return Public
