local ReplicatedStorage = game:GetService("ReplicatedStorage")
local WeightedRandom = require(ReplicatedStorage.MonsterFactory.Shared.WeightedRandom)

return function(t)
	t.it("normalizes to 1 and ignores non-positive weights", function()
		local p = WeightedRandom.Normalize({
			{ Key = "a", Weight = 1 },
			{ Key = "b", Weight = 3 },
			{ Key = "z", Weight = 0 },
			{ Key = "n", Weight = -5 },
		})
		t.near(p.a, 0.25, 1e-9, "a")
		t.near(p.b, 0.75, 1e-9, "b")
		t.eq(p.z, nil, "zero weight")
		t.eq(p.n, nil, "negative weight")
	end)

	t.it("returns nil for empty or all-zero lists", function()
		local rng = Random.new(1)
		t.eq(WeightedRandom.Pick({}, rng), nil, "empty")
		t.eq(WeightedRandom.Pick({ { Key = 1, Weight = 0 } }, rng), nil, "zero")
	end)

	t.it("never picks a zero-weight entry (20k picks)", function()
		local rng = Random.new(2)
		local entries = { { Key = "x", Weight = 0 }, { Key = "y", Weight = 1 }, { Key = "w", Weight = 0 } }
		for _ = 1, 20000 do
			t.eq(WeightedRandom.Pick(entries, rng), "y", "pick")
		end
	end)

	t.it("observed frequencies match weights (100k picks)", function()
		local rng = Random.new(3)
		local entries = { { Key = 1, Weight = 1 }, { Key = 2, Weight = 2 }, { Key = 3, Weight = 7 } }
		local counts = { 0, 0, 0 }
		local n = 100000
		for _ = 1, n do
			local k = WeightedRandom.Pick(entries, rng)
			counts[k] += 1
		end
		for i, p in { 0.1, 0.2, 0.7 } do
			local se = math.sqrt(p * (1 - p) / n)
			t.near(counts[i] / n, p, 4 * se, "key " .. i)
		end
	end)
end
