local Queue = {}

--- Creates a new queue.
--- @return table
function Queue.new()
    local queue = { _head = 1, _tail = 1 }
    return queue
end

--- Returns the number of elements in the queue.
--- @param queue table
--- @return number
function Queue.size(queue)
    return queue._head - queue._tail
end

--- Pushes an element to the end of the queue.
--- @param queue table
--- @param element any
function Queue.push(queue, element)
    local index = queue._head
    queue[index] = element
    queue._head = index + 1
end

--- Pushes the element such that it would be the next element popped.
--- @param queue table
--- @param element any
function Queue.push_to_end(queue, element)
    local index = queue._tail - 1
    queue[index] = element
    queue._tail = index
end

--- Returns the next element to be popped without removing it.
--- @param queue table
--- @return any
function Queue.peek(queue)
    return queue[queue._tail]
end

--- Returns the last pushed element without removing it.
--- @param queue table
--- @return any
function Queue.peek_start(queue)
    return queue[queue._head - 1]
end

--- Returns the element at the given offset from the front (0-based).
--- @param queue table
--- @param index number
--- @return any
function Queue.peek_index(queue, index)
    return queue[queue._tail + index - 1]
end

--- Pops the front element. Returns nil on an empty queue.
--- @param queue table
--- @return any
function Queue.pop(queue)
    local index = queue._tail

    local element = queue[index]
    queue[index] = nil

    if element then
        queue._tail = index + 1
    end

    return element
end

--- Converts the queue to a plain array (front to back).
--- @param queue table
--- @return table
function Queue.to_array(queue)
    local n = 1
    local res = {}

    for i = queue._tail, queue._head - 1 do
        res[n] = queue[i]
        n = n + 1
    end

    return res
end

--- Iterates the queue from front to back.
--- @param queue table
--- @return function iterator
function Queue.pairs(queue)
    local index = queue._tail
    return function()
        local element = queue[index]

        if element then
            local old = index
            index = index + 1
            return old, element
        else
            return nil
        end
    end
end

--- Empties the queue and resets its pointers.
--- @param queue table
function Queue.clear(queue)
    for k, _ in pairs(queue) do
        queue[k] = nil
    end
    queue._head, queue._tail = 1, 1
end

return Queue
