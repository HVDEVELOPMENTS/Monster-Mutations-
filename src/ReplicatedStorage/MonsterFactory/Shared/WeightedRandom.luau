--!strict
-- Weighted selection over { { Key = any, Weight = number } }.
-- Non-positive weights are ignored. Returns nil for an empty / zero-weight list.

export type Entry = { Key: any, Weight: number }

local WeightedRandom = {}

function WeightedRandom.Total(entries: { Entry }): number
	local total = 0
	for _, e in entries do
		if e.Weight > 0 then
			total += e.Weight
		end
	end
	return total
end

-- Returns { [Key] = probability } summing to 1 (or empty if total is 0).
function WeightedRandom.Normalize(entries: { Entry }): { [any]: number }
	local total = WeightedRandom.Total(entries)
	local out = {}
	if total <= 0 then
		return out
	end
	for _, e in entries do
		if e.Weight > 0 then
			out[e.Key] = (out[e.Key] or 0) + e.Weight / total
		end
	end
	return out
end

function WeightedRandom.Pick(entries: { Entry }, rng: Random): any
	local total = WeightedRandom.Total(entries)
	if total <= 0 then
		return nil
	end
	local roll = rng:NextNumber() * total
	local last = nil
	for _, e in entries do
		if e.Weight > 0 then
			roll -= e.Weight
			last = e.Key
			if roll < 0 then
				return e.Key
			end
		end
	end
	-- Floating-point remainder: return the last positive entry.
	return last
end

return WeightedRandom
