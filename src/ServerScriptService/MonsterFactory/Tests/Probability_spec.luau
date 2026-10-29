-- Large-sample checks that observed frequencies match the configured / reported odds.
-- Pass criterion: |observed - expected| <= 4 standard errors. Tiers whose expected
-- count is below 10 are reported but not asserted (too few samples to judge).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Registry = require(ReplicatedStorage.MonsterFactory.Shared.Registry)
local WeightedRandom = require(ReplicatedStorage.MonsterFactory.Shared.WeightedRandom)
local MutationService = require(script.Parent.Parent.Services.MutationService)

local function check(t, label, observedCount, n, p)
	local obs = observedCount / n
	local se = math.sqrt(p * (1 - p) / n)
	local z = if se > 0 then (obs - p) / se else 0
	local expectedCount = p * n
	local judged = expectedCount >= 10
	t.log(string.format("%-28s expected %.5f%%  observed %.5f%%  abs dev %.5f%%  z=%+.2f  n=%d %s",
		label, p * 100, obs * 100, math.abs(obs - p) * 100, z, n, if judged then "" else "(not judged: <10 expected)"))
	if judged then
		t.ok(math.abs(z) <= 4, label .. " deviates: z=" .. z)
	end
end

return function(t)
	local svc = MutationService.new(Registry)

	t.it("100k single tier rolls match the rarity table", function()
		local rng = Random.new(2026)
		local entries = {}
		for _, tier in Registry.Rarity.Tiers do
			table.insert(entries, { Key = tier.Tier, Weight = tier.Chance })
		end
		local n = 100000
		local counts = {}
		for i = 1, n do
			local k = WeightedRandom.Pick(entries, rng)
			counts[k] = (counts[k] or 0) + 1
			if i % 25000 == 0 then
				task.wait()
			end
		end
		for _, tier in Registry.Rarity.Tiers do
			check(t, tier.Name, counts[tier.Tier] or 0, n, tier.Chance)
		end
	end)

	t.it("60k full rolls: slot-1 outcomes match GetOddsReport (Mossling + FertileSoil + Dewdrop)", function()
		local ctx = { SpeciesId = "Mossling", BiomeId = "VerdantMeadows", Catalysts = { "FertileSoil", "Dewdrop" } }
		local report = svc:GetOddsReport(ctx)
		local rng = Random.new(99)
		local n = 60000
		local counts = {} -- [cat][mutationId or "<empty>"]
		for i = 1, n do
			local res = svc:Roll(ctx, rng)
			local seenCat = {}
			for _, entry in res.Log do
				if entry.Slot == 1 then
					counts[entry.Category] = counts[entry.Category] or {}
					local key = entry.MutationId or "<empty>"
					counts[entry.Category][key] = (counts[entry.Category][key] or 0) + 1
					seenCat[entry.Category] = true
				end
			end
			if i % 5000 == 0 then
				task.wait()
			end
		end
		for _, c in report.Categories do
			local cc = counts[c.Category] or {}
			check(t, c.Category .. "/<empty>", cc["<empty>"] or 0, n, c.EmptyChance)
			for _, cand in c.Candidates do
				check(t, c.Category .. "/" .. cand.MutationId, cc[cand.MutationId] or 0, n, cand.Probability)
			end
		end
	end)
end
