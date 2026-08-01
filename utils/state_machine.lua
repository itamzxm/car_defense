--- This module provides a classical mealy/moore state machine.
-- Each machine is constructed by calling new().
-- States and transitions are lazily added to the machine as transition handlers and state tick handlers are registered.
-- However the state machine must be fully defined after init is done. Dynamic machine changes are currently unsupported.
-- Note: state machine instances can be persisted (their `id` survives); the callback tables are rebuilt at load time
-- because registration is only allowed during the control stage.

local StateMachine = {}

local Debug = require 'utils.debug'

local in_state_callbacks = {}
local transaction_callbacks = {}
local max_stack_depth = 20
local machine_count = 0
local control_stage = _STAGE.control

--- Transitions the supplied machine into a given state and executes all transition callbacks.
-- @param self table State machine instance
-- @param new_state number|string The new state to transition to
function StateMachine.transition(self, new_state)
    Debug.print('Transitioning from state ' .. tostring(self.state) .. ' to state ' .. tostring(new_state) .. '.')
    local old_state = self.state

    local stack_depth = self.stack_depth
    self.stack_depth = stack_depth + 1
    if stack_depth > max_stack_depth then
        if _DEBUG then
            error('[WARNING] Stack overflow at:' .. debug.traceback())
        else
            log('[WARNING] Stack overflow at:' .. debug.traceback())
        end
    end

    local exit_callbacks = transaction_callbacks[self.id][old_state]
    if exit_callbacks then
        local entry_callbacks = exit_callbacks[new_state]
        if entry_callbacks then
            for i = 1, #entry_callbacks do
                local callback = entry_callbacks[i]
                if callback then
                    callback()
                end
            end
        end
    end
    self.state = new_state
end

--- Is this machine in the given state?
-- @param self table State machine instance
-- @param state number|string
-- @return boolean
function StateMachine.in_state(self, state)
    return self.state == state
end

--- Invokes all in-state callbacks of the machine for its current state.
-- @param self table State machine instance
function StateMachine.machine_tick(self)
    local callbacks = in_state_callbacks[self.id][self.state]
    if callbacks then
        for i = 1, #callbacks do
            local callback = callbacks[i]
            if callback then
                callback()
            end
        end
    end
    self.stack_depth = 0
end

--- Registers a handler invoked by machine_tick while the machine is in the given state.
-- NOTICE: errors if called after the control stage. Dynamic machine changes are unsupported.
-- @param self table State machine instance
-- @param state number|string
-- @param callback function
function StateMachine.register_state_tick_callback(self, state, callback)
    if _LIFECYCLE ~= control_stage then
        error('Calling StateMachine.register_state_tick_callback after the control stage is unsupported due to desyncs.', 2)
    end
    in_state_callbacks[self.id][state] = in_state_callbacks[self.id][state] or {}
    table.insert(in_state_callbacks[self.id][state], callback)
end

--- Registers a handler invoked when transitioning from `old` to `new`.
-- NOTICE: errors if called after the control stage. Dynamic machine changes are unsupported.
-- @param self table State machine instance
-- @param old number|string exiting state
-- @param new number|string entering state
-- @param callback function
function StateMachine.register_transition_callback(self, old, new, callback)
    if _LIFECYCLE ~= control_stage then
        error('Calling StateMachine.register_transition_callback after the control stage is unsupported due to desyncs.', 2)
    end
    transaction_callbacks[self.id][old] = transaction_callbacks[self.id][old] or {}
    transaction_callbacks[self.id][old][new] = transaction_callbacks[self.id][old][new] or {}
    table.insert(transaction_callbacks[self.id][old][new], callback)
end

--- Constructs a new state machine.
-- NOTICE: errors if called after the control stage.
-- @param init_state number|string The starting state of the machine
-- @return table The constructed state machine instance
function StateMachine.new(init_state)
    if _LIFECYCLE ~= control_stage then
        error('Calling StateMachine.new after the control stage is unsupported due to desyncs.', 2)
    end
    machine_count = machine_count + 1
    in_state_callbacks[machine_count] = {}
    transaction_callbacks[machine_count] = {}
    return {
        state = init_state,
        stack_depth = 0,
        id = machine_count
    }
end

return StateMachine
