local math_random = math.random
local Public = {}

function Public.raffle(values,weights) --arguments of the form {[a] = A, [b] = B, ...} and {[a] = a_weight, [b] = b_weight, ...} or just {a,b,c,...} and {1,2,3...}

	local total_weight = 0
	for k,w in pairs(weights) do
		assert(values[k])
		if w > 0 then
			total_weight = total_weight + w
		end
		-- negative weights treated as zero
	end
	assert(total_weight > 0)

	local cumulative_probability = 0
	local rng = math_random()
	for k,v in pairs(values) do
		assert(weights[k])
		cumulative_probability = cumulative_probability + (weights[k] / total_weight)
		if rng <= cumulative_probability then
			return v
		end
	end
end

return Public
