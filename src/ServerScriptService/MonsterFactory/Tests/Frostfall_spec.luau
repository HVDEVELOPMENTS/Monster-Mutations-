-- Stage 4: second biome, environmental events, biome unlocks and cross-biome rules.

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Registry = require(ReplicatedStorage.MonsterFactory.Shared.Registry)
local Config = require(ReplicatedStorage.MonsterFactory.Shared.Config)
local Events = Registry.Events
local Services = script.Parent.Parent.Services
local MutationService = require(Services.MutationService)
local MonsterGenerationService = require(Services.MonsterGenerationService)
local PlayerData = require(Services.PlayerDataService)
local EconomyService = require(Services.EconomyService)
local IncubationService = require(Services.IncubationService)
local BiomeService = require(Services.BiomeService)

local M = Registry.Mutations.ById

return function(t)
	local svc = MutationService.new(Registry)
	local function resolve(ctx)
		return assert(svc:Resolve(ctx))
	end
	local function eligible(id, ctx, chosen)
		return (svc:CheckEligibility(M[id], resolve(ctx), chosen))
	end
	local FROST = "FrostfallTundra"
	local function ctx(species, extra)
		local c = { SpeciesId = species, BiomeId = FROST }
		for k, v in extra or {} do
			c[k] = v
		end
		return c
	end
	local function candidateSet(c)
		local set = {}
		for _, cat in svc:GetOddsReport(c).Categories do
			for _, cand in cat.Candidates do
				set[cand.MutationId] = cand
			end
		end
		return set
	end

	t.it("event schedule is deterministic and matches its definitions", function()
		local cycle = Events.CycleSeconds[FROST]
		local base = cycle * 1000
		local a = Events.GetActive(FROST, base + 10)
		t.eq(a.Snowstorm, base + Events.ById.Snowstorm.Duration, "snowstorm active with correct end")
		t.eq(a.AuroraNight, nil, "no aurora at the same time")
		t.eq(next(Events.GetActive(FROST, base + 300)), nil, "calm window")
		local b = Events.GetActive(FROST, base + 460)
		t.ok(b.AuroraNight, "aurora active")
		t.eq(Events.NextStart("AuroraNight", base + 10), base + Events.ById.AuroraNight.StartOffset, "next aurora")
		t.eq(Events.NextStart("Snowstorm", base + 10), base + cycle, "next snowstorm is next cycle")
		t.eq(next(Events.GetActive("VerdantMeadows", base)), nil, "no events in Verdant")
	end)

	t.it("Verdant and Frostfall have different mutation pools", function()
		local v = candidateSet({ SpeciesId = "Mossling", BiomeId = "VerdantMeadows" })
		local f = candidateSet(ctx("Mossling"))
		local onlyV, onlyF, shared = 0, 0, {}
		for id in v do
			if f[id] then
				table.insert(shared, id)
			else
				onlyV += 1
			end
		end
		for id in f do
			if not v[id] then
				onlyF += 1
			end
		end
		t.log(string.format("Mossling: %d Verdant-only, %d Frostfall-only, shared = %s", onlyV, onlyF, table.concat(shared, ", ")))
		t.ok(onlyV >= 8 and onlyF >= 8, "both biomes have distinct pools")
		for _, id in shared do
			t.eq(M[id].Category, "Utility", "only Utility traits are shared: " .. id)
		end
		t.eq(v.FrostedCoat, nil, "no frost in meadows")
		t.eq(f.LeafMarkings, nil, "no meadow patterns in tundra")
	end)

	t.it("events are validated and must belong to the biome", function()
		local r, err = svc:Resolve({ SpeciesId = "Mossling", BiomeId = "VerdantMeadows", Events = { AuroraNight = true } })
		t.eq(r, nil, "aurora is not a meadow event")
		t.eq(err, "BadEvent", "code")
		r, err = svc:Resolve(ctx("Snowmote", { Events = { FakeEvent = true } }))
		t.eq(err, "BadEvent", "unknown event")
	end)

	t.it("event-locked mutations need the event (and catalyst where listed)", function()
		t.ok(not eligible("AuroraMarkings", ctx("Snowmote")), "no aurora outside the event")
		t.ok(eligible("AuroraMarkings", ctx("Snowmote", { Events = { AuroraNight = true } })), "aurora during the event")
		t.ok(not eligible("AuroraSovereign", ctx("Snowmote", { Events = { AuroraNight = true } })), "sovereign also needs the fragment")
		t.ok(not eligible("AuroraSovereign", ctx("Snowmote", { Catalysts = { "AuroraFragment" } })), "fragment alone is not enough")
		t.ok(eligible("AuroraSovereign", ctx("Snowmote", { Events = { AuroraNight = true }, Catalysts = { "AuroraFragment" } })), "both")
	end)

	t.it("snowstorm lowers temperature, which gates Permafrost Veins", function()
		t.eq(resolve(ctx("Frostfang")).Environment.Temperature, -15, "base temperature")
		t.eq(resolve(ctx("Frostfang", { Events = { Snowstorm = true } })).Environment.Temperature, -30, "storm temperature")
		t.ok(not eligible("PermafrostVeins", ctx("Frostfang")), "too warm normally")
		t.ok(eligible("PermafrostVeins", ctx("Frostfang", { Events = { Snowstorm = true } })), "cold enough in storm")
		t.eq(Registry.Biomes.ById[FROST].Environment.Temperature, -15, "biome definition not mutated")
	end)

	t.it("event modifiers change only the documented mutations and odds still sum to 1", function()
		local calm = candidateSet(ctx("Frostfang"))
		local storm = candidateSet(ctx("Frostfang", { Events = { Snowstorm = true } }))
		t.ok(storm.BlizzardHeart.Probability > calm.BlizzardHeart.Probability, "Blizzard Heart up")
		t.ok(storm.GlacialGuardian.Probability < calm.GlacialGuardian.Probability, "same-tier rival down (renormalised)")
		t.near(storm.FrozenCore.Probability, calm.FrozenCore.Probability * (calm.FrozenCore.WithinTier > 0 and storm.FrozenCore.WithinTier / calm.FrozenCore.WithinTier or 1), 1e-12, "Rare tier only changes via new candidates")
		t.near(storm.SoftGlow and 1 or 0, 0, 0, "no meadow aura")
		local tagged = false
		for _, mod in storm.BlizzardHeart.Modifiers do
			tagged = tagged or mod.Source == "Event:Snowstorm"
		end
		t.ok(tagged, "modifier is reported to the player")
		for _, cat in svc:GetOddsReport(ctx("Frostfang", { Events = { Snowstorm = true } })).Categories do
			local sum = cat.EmptyChance
			for _, c in cat.Candidates do
				sum += c.Probability
			end
			t.near(sum, 1, 1e-9, cat.Category)
		end
	end)

	t.it("Frost species get the elemental affinity bonus; others don't", function()
		local r1 = resolve(ctx("Snowmote"))
		local r2 = resolve(ctx("Mossling"))
		local w1 = svc:GetMutationWeight(M.FrozenCore, r1)
		local w2 = svc:GetMutationWeight(M.FrozenCore, r2)
		t.near(w1, w2 * MutationService.AFFINITY_MULTIPLIER, 1e-9, "affinity x1.25")
		t.ok(not eligible("GlacierScales", ctx("Mossling")), "Glacier Scales needs Frost element")
		t.ok(eligible("GlacierScales", ctx("Frostfang")), "Frostfang qualifies")
	end)

	t.it("40k storm rolls match the reported odds (Frostfang, Elemental + Aura slot 1)", function()
		local c = ctx("Frostfang", { Events = { Snowstorm = true }, Catalysts = { "GlacierCrystal" } })
		local report = svc:GetOddsReport(c)
		local rng = Random.new(404)
		local n = 40000
		local counts = {}
		for i = 1, n do
			for _, e in svc:Roll(c, rng).Log do
				if e.Slot == 1 then
					local k = e.Category .. "/" .. (e.MutationId or "<empty>")
					counts[k] = (counts[k] or 0) + 1
				end
			end
			if i % 5000 == 0 then
				task.wait()
			end
		end
		for _, cat in report.Categories do
			if cat.Category == "Elemental" or cat.Category == "Aura" then
				local rows = { { cat.Category .. "/<empty>", cat.EmptyChance } }
				for _, cand in cat.Candidates do
					table.insert(rows, { cat.Category .. "/" .. cand.MutationId, cand.Probability })
				end
				for _, row in rows do
					local p = row[2]
					local obs = (counts[row[1]] or 0) / n
					local se = math.sqrt(p * (1 - p) / n)
					local z = if se > 0 then (obs - p) / se else 0
					t.log(string.format("%-28s expected %.3f%%  observed %.3f%%  z=%+.2f", row[1], p * 100, obs * 100, z))
					if p * n >= 10 then
						t.ok(math.abs(z) <= 4, row[1] .. " z=" .. z)
					end
				end
			end
		end
	end)

	-- Server flow (memory-only PlayerData, fake players).
	local generation = MonsterGenerationService.new(Registry, svc)
	local economy = EconomyService.new({ PlayerData = PlayerData })
	local incubation = IncubationService.new({ PlayerData = PlayerData, Generation = generation, Mutation = svc, Economy = economy })
	local biomes = BiomeService.new({ PlayerData = PlayerData })
	local clock = Events.CycleSeconds[FROST] * 2000 + 30 -- inside a Snowstorm
	incubation.Now = function()
		return clock
	end
	local nextId = 70000
	local function newPlayer()
		PlayerData._UseStoreForTests(nil, generation)
		nextId += 1
		local p = { UserId = nextId, Parent = workspace, Name = "F" .. nextId }
		return p, PlayerData.Load(p).Data
	end
	local function start(p, species, biome, catalysts)
		return incubation:Start(p, { RequestId = HttpService:GenerateGUID(false), SpeciesId = species, BiomeId = biome, Catalysts = catalysts })
	end

	t.it("locked biome, its species and its catalysts are refused", function()
		local p, d = newPlayer()
		d.Coins, d.Level = 10000, 10
		t.eq(start(p, "Mossling", FROST).Error, "BiomeLocked", "biome locked")
		t.eq(start(p, "Snowmote", "VerdantMeadows").Error, "SpeciesBiomeLocked", "frost species locked")
		t.eq(economy:BuyCatalyst(p, "FrostShard", 1).Error, "BiomeLocked", "frost catalyst locked")
		PlayerData._ForgetForTests(p)
	end)

	t.it("unlock needs level + discoveries + coins; charges once; is permanent", function()
		local p, d = newPlayer()
		d.Coins = 1000
		local r = biomes:Unlock(p, FROST)
		t.eq(r.Error, "RequirementsNotMet", "level 1 refused")
		d.Level = 4
		t.eq(biomes:Unlock(p, FROST).Error, "RequirementsNotMet", "no discoveries refused")
		for i = 1, 6 do
			d.Discoveries.Mutations[Registry.Mutations.List[i].Id] = 1
		end
		d.Coins = 100
		t.eq(biomes:Unlock(p, FROST).Error, "RequirementsNotMet", "not enough coins refused")
		d.Coins = 1000
		t.ok(biomes:Unlock(p, FROST).Ok, "unlocked")
		t.eq(d.Coins, 1000 - Registry.Biomes.ById[FROST].Unlock.Coins, "charged once")
		local again = biomes:Unlock(p, FROST)
		t.ok(again.Ok and again.AlreadyUnlocked, "idempotent")
		t.eq(d.Coins, 1000 - Registry.Biomes.ById[FROST].Unlock.Coins, "not charged twice")
		t.eq(biomes:Unlock(p, "Nowhere").Error, "UnknownBiome", "bad id")
		PlayerData._ForgetForTests(p)
	end)

	t.it("after unlock: cross-biome incubation works and captures the live event", function()
		local p, d = newPlayer()
		d.Coins, d.Level = 10000, 5
		d.UnlockedBiomes[FROST] = true
		local s = start(p, "Mossling", FROST)
		t.ok(s.Ok, "meadow species in tundra: " .. tostring(s.Error))
		t.ok(d.Incubation.Events.Snowstorm, "snowstorm captured at start")
		for _, id in d.Incubation.Record.ActiveMutations do
			local allowed = M[id].AllowedBiomes
			t.ok(allowed == nil or table.find(allowed, FROST), id .. " allowed in Frostfall")
		end
		clock += Config.IncubationSeconds
		t.ok(incubation:Claim(p, s.Incubation.OpId).Ok, "claimed")
		t.eq(start(p, "Glimmerseal", FROST).Error, "SpeciesLocked", "Glimmerseal needs level 6")
		t.ok(start(p, "Frostfang", "VerdantMeadows").Ok, "frost species in meadows")
		t.ok(economy:BuyCatalyst(p, "FrostShard", 2).Ok, "frost catalyst buyable")
		PlayerData._ForgetForTests(p)
	end)
end
