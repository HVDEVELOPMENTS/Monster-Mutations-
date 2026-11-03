-- Monster fusion: every same-biome pair has one result; inputs are validated,
-- paid for and used up exactly once; the Rare+ guarantee applies when both
-- inputs are Rare or better.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Registry = require(ReplicatedStorage.MonsterFactory.Shared.Registry)
local Fusion = require(ReplicatedStorage.MonsterFactory.Shared.Fusion)
local Services = script.Parent.Parent.Services
local MutationService = require(Services.MutationService)
local MonsterGenerationService = require(Services.MonsterGenerationService)
local PlayerData = require(Services.PlayerDataService)
local EconomyService = require(Services.EconomyService)
local IncubationService = require(Services.IncubationService)
local FusionService = require(Services.FusionService)

return function(t)
	local mutation = MutationService.new(Registry)
	local generation = MonsterGenerationService.new(Registry, mutation)
	local economy = EconomyService.new({ PlayerData = PlayerData })
	local incubation = IncubationService.new({ PlayerData = PlayerData, Generation = generation, Mutation = mutation, Economy = economy })
	local fusion = FusionService.new({ PlayerData = PlayerData, Generation = generation, Mutation = mutation, Economy = economy, Incubation = incubation })
	local nextId = 83000
	local function newPlayer()
		PlayerData._UseStoreForTests(nil, generation)
		nextId += 1
		local p = { UserId = nextId, Parent = workspace, Name = "F" .. nextId }
		return p, PlayerData.Load(p).Data
	end
	local function give(p, d, speciesId: string, tier: number?, seed: number?)
		local sp = Registry.Species.ById[speciesId]
		local rec = generation:Generate(p.UserId, { SpeciesId = speciesId, BiomeId = sp.HomeBiome }, Random.new(seed or 1))
		if tier then
			rec.RarityTier = tier
		end
		d.Monsters[rec.MonsterId] = rec
		return rec.MonsterId
	end

	t.it("every pair of different species in a biome fuses into its third species", function()
		local byBiome = {}
		for _, s in Registry.Species.List do
			byBiome[s.HomeBiome] = byBiome[s.HomeBiome] or {}
			table.insert(byBiome[s.HomeBiome], s.Id)
		end
		for biome, ids in byBiome do
			t.eq(#ids, 3, biome .. " has three species")
			for i, a in ids do
				for j, b in ids do
					local out, why = Fusion.ResultFor(a, b)
					if i == j then
						t.eq(why, "FuseSameSpecies", "same species refused")
					else
						t.ok(out and out ~= a and out ~= b and Registry.Species.ById[out].HomeBiome == biome, a .. " + " .. b)
						t.eq(Fusion.ResultFor(b, a), out, "order does not matter")
					end
				end
			end
		end
		t.eq(select(2, Fusion.ResultFor("Mossling", "Snowmote")), "FuseDifferentBiome", "different biomes refused")
	end)

	t.it("fusing uses both monsters, charges once and makes the third species", function()
		local p, d = newPlayer()
		local a = give(p, d, "Mossling", 1, 1)
		local b = give(p, d, "Pebbleback", 1, 2)
		d.Equipped = { a }
		d.Coins = 1000
		local pre = fusion:Fuse(p, a, b, true)
		t.ok(pre.Ok and pre.Preview and pre.SpeciesId == "Brookhopper", "preview names the result")
		t.eq(pre.Cost, Fusion.Cost("Brookhopper"), "preview cost")
		t.ok(d.Monsters[a] and d.Coins == 1000, "preview changes nothing")
		local r = fusion:Fuse(p, a, b)
		t.ok(r.Ok, "fused")
		t.eq(r.Record.SpeciesId, "Brookhopper", "third species")
		t.eq(r.Record.OriginMethod, "Fusion", "origin recorded")
		t.ok(not d.Monsters[a] and not d.Monsters[b], "inputs used up")
		t.ok(d.Monsters[r.Record.MonsterId], "result owned")
		t.eq(#d.Equipped, 0, "fused pet leaves its slot")
		t.eq(d.Coins, 1000 - pre.Cost + r.RewardCoins, "paid once (plus discovery reward)")
		t.eq(fusion:Fuse(p, a, b).Error, "NotOwned", "a retry can't fuse again")
		PlayerData._ForgetForTests(p)
	end)

	t.it("fusion refuses locked, unowned, mismatched or unaffordable pairs", function()
		local p, d = newPlayer()
		local a = give(p, d, "Mossling", 1, 3)
		local b = give(p, d, "Pebbleback", 1, 4)
		local c = give(p, d, "Mossling", 1, 5)
		d.Coins = 0
		t.eq(fusion:Fuse(p, a, b).Error, "NotEnoughCoins", "needs coins")
		d.Coins = 1000
		t.eq(fusion:Fuse(p, a, c).Error, "FuseSameSpecies", "two of the same species")
		t.eq(fusion:Fuse(p, a, a).Error, "BadRequest", "same monster twice")
		t.eq(fusion:Fuse(p, a, "nope").Error, "NotOwned", "unowned")
		d.Locked[b] = true
		t.eq(fusion:Fuse(p, a, b).Error, "Locked", "locked monsters are safe")
		PlayerData._ForgetForTests(p)
	end)

	t.it("two Rare+ monsters guarantee a Rare+ result", function()
		local p, d = newPlayer()
		d.Coins = 100000
		for i = 1, 10 do
			local a = give(p, d, "Mossling", 3, 100 + i)
			local b = give(p, d, "Pebbleback", 3, 200 + i)
			local r = fusion:Fuse(p, a, b)
			t.ok(r.Ok and r.Record.RarityTier >= 3, "guaranteed Rare+ (" .. i .. ")")
		end
		PlayerData._ForgetForTests(p)
	end)
end
