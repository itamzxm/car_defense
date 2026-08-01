local Declare = require 'utils.test.declare'
local Assert = require 'utils.test.assert'
local Queue = require 'utils.queue'

Declare.module(
    {'utils', 'Queue'},
    function()
        Declare.test(
            'push pop peek order',
            function()
                local q = Queue.new()
                Queue.push(q, 'a')
                Queue.push(q, 'b')
                Queue.push(q, 'c')
                Assert.equal('a', Queue.peek(q))
                Assert.equal(3, Queue.size(q))
                Assert.equal('a', Queue.pop(q))
                Assert.equal('b', Queue.pop(q))
                Assert.equal('c', Queue.pop(q))
                Assert.equal(nil, Queue.pop(q))
                Assert.equal(0, Queue.size(q))
            end
        )

        Declare.test(
            'push_to_end inserts at front',
            function()
                local q = Queue.new()
                Queue.push(q, 'a')
                Queue.push(q, 'b')
                Queue.push_to_end(q, 'x')
                Assert.equal('x', Queue.peek(q))
                Assert.equal(3, Queue.size(q))
                Assert.equal('x', Queue.pop(q))
                Assert.equal('a', Queue.pop(q))
            end
        )

        Declare.test(
            'to_array and clear',
            function()
                local q = Queue.new()
                Queue.push(q, 1)
                Queue.push(q, 2)
                Queue.push(q, 3)
                Assert.table_equal({1, 2, 3}, Queue.to_array(q))
                Queue.clear(q)
                Assert.equal(0, Queue.size(q))
                Assert.equal(nil, Queue.pop(q))
                Queue.push(q, 'after')
                Assert.equal('after', Queue.pop(q))
            end
        )

        Declare.test(
            'pairs iteration front to back',
            function()
                local q = Queue.new()
                Queue.push(q, 'x')
                Queue.push(q, 'y')
                local out = {}
                for _, v in Queue.pairs(q) do
                    out[#out + 1] = v
                end
                Assert.table_equal({'x', 'y'}, out)
            end
        )
    end
)
