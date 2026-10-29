local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Registry = require(ReplicatedStorage.MonsterFactory.Shared.Registry)
local MutationService = require(script.Parent.Parent.Services.MutationService)
local MonsterGenerationService = require(script.Parent.Parent.Services.MonsterGenerationService)

return function(t)
	local gen = MonsterGenerationService.new(Registry, MutationService.new(Registry))
	local ctx = { SpeciesId = "Mossling", BiomeId = "VerdantMeadows" }

	t.it("creates valid records with unique ids", function()
		local rng = Random.new(11)
		local ids = {}
		for _ = 1, 500 do
			local rec = gen:Generate(123, ctx, rng)
			t.ok(rec, "record")
			local ok, why = gen:ValidateRecord(rec)
			t.ok(ok, "validate: " .. tostring(why))
			t.ok(not ids[rec.MonsterId], "unique id")
			ids[rec.MonsterId] = true
			t.eq(rec.OwnerUserId, 123, "owner")
			t.eq(rec.OriginBiome, "VerdantMeadows", "biome")
		end
	end)

	t.it("rarity tier equals highest mutation tier (Common if none)", function()
		local rng = Random.new(12)
		for _ = 1, 2000 do
			local rec = gen:Generate(1, ctx, rng)
			local top = 1
			for _, id in rec.ActiveMutations do
				top = math.max(top, Registry.Mutations.ById[id].RarityTier)
			end
			t.eq(rec.RarityTier, top, "tier")
			t.eq(rec.SpeciesRarity, 1, "species rarity kept separate")
		end
	end)

	t.it("stat modifiers are summed and capped", function()
		local sp = Registry.Species.ById.Mossling
		local s = gen:ComputeStats(sp, { "Efficient", "EternalSpring" })
		t.near(s.IncomeRate, sp.BaseStats.IncomeRate * 1.20, 1e-6, "income +20%")
		local saved = MonsterGenerationService.CAPS.IncomeRate
		MonsterGenerationService.CAPS.IncomeRate = 0.1
		local capped = gen:ComputeStats(sp, { "Efficient", "EternalSpring" })
		MonsterGenerationService.CAPS.IncomeRate = saved
		t.near(capped.IncomeRate, sp.BaseStats.IncomeRate * 1.10, 1e-6, "capped at +10%")
	end)

	t.it("rejects bad owner and bad context", function()
		local rng = Random.new(1)
		local r1, e1 = gen:Generate("me" :: any, ctx, rng)
		t.eq(r1, nil, "bad owner")
		t.eq(e1, "BadOwner", "code")
		local r2, e2 = gen:Generate(1, { SpeciesId = "Mossling", BiomeId = "Moon" }, rng)
		t.eq(r2, nil, "bad biome")
		t.eq(e2, "UnknownBiome", "code")
	end)

	t.it("ValidateRecord rejects tampered records", function()
		local rec = gen:Generate(1, ctx, Random.new(5))
		local bad = table.clone(rec)
		bad.ActiveMutations = { "NotAMutation" }
		t.ok(not gen:ValidateRecord(bad), "unknown mutation")
		bad.ActiveMutations = { "SoftGlow", "SoftGlow" }
		t.ok(not gen:ValidateRecord(bad), "duplicate mutation")
		bad = table.clone(rec)
		bad.RarityTier = 99
		t.ok(not gen:ValidateRecord(bad), "bad tier")
	end)
end
