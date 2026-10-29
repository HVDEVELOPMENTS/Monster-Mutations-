-- Stage 6: upgrades, research, gathering, auto-equip.

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Registry = require(ReplicatedStorage.MonsterFactory.Shared.Registry)
local Config = require(ReplicatedStorage.MonsterFactory.Shared.Config)
local Progression = require(ReplicatedStorage.MonsterFactory.Shared.Progression)
local Services = script.Parent.Parent.Services
local MutationService = require(Services.MutationService)
local MonsterGenerationService = require(Services.MonsterGenerationService)
local PlayerData = require(Services.PlayerDataService)
local EconomyService = require(Services.EconomyService)
local IncubationService = require(Services.IncubationService)
local ProgressionService = require(Services.ProgressionService)

return function(t)
	local mutation = MutationService.new(Registry)
	local generation = MonsterGenerationService.new(Registry, mutation)
	local economy = EconomyService.new({ PlayerData = PlayerData })
	local incubation = IncubationService.new({ PlayerData = PlayerData, Generation = generation, Mutation = mutation, Economy = economy })
	local prog = ProgressionService.new({ PlayerData = PlayerData })
	local clock = 1000000
	incubation.Now = function()
		return clock
	end
	prog.Now = incubation.Now
	local nextId = 81000
	local function newPlayer()
		PlayerData._UseStoreForTests(nil, generation)
		nextId += 1
		local p = { UserId = nextId, Parent = workspace, Name = "P" .. nextId }
		return p, PlayerData.Load(p).Data
	end
	local function start(p, species, biome, catalysts)
		return incubation:Start(p, { RequestId = HttpService:GenerateGUID(false), SpeciesId = species, BiomeId = biome or "VerdantMeadows", Catalysts = catalysts })
	end

	t.it("upgrades: exact costs, one level at a time, max level enforced", function()
		local p, d = newPlayer()
		d.Coins = 100000
		local u = Progression.UpgradeById.ImprovedIncubator
		local spent = 0
		for lvl = 1, #u.Costs do
			local before = d.Coins
			local r = prog:BuyUpgrade(p, u.Id)
			t.ok(r.Ok and r.Level == lvl, "level " .. lvl)
			t.eq(before - d.Coins, u.Costs[lvl], "cost of level " .. lvl)
			spent += u.Costs[lvl]
		end
		t.eq(prog:BuyUpgrade(p, u.Id).Error, "MaxLevel", "max")
		t.eq(100000 - d.Coins, spent, "no extra charge at max")
		t.eq(prog:BuyUpgrade(p, "Nope").Error, "UnknownUpgrade", "bad id")
		d.Coins = 0
		t.eq(prog:BuyUpgrade(p, "RareResonator").Error, "NotEnoughCoins", "broke")
		PlayerData._ForgetForTests(p)
	end)

	t.it("Improved Incubator shortens incubation by exactly 1 s per level", function()
		local p, d = newPlayer()
		d.Coins = 10000
		local s = start(p, "Mossling")
		t.eq(d.Incubation.EndsAt - d.Incubation.StartedAt, Config.IncubationSeconds, "base")
		clock += 100
		incubation:Claim(p, s.Incubation.OpId)
		d.Upgrades.ImprovedIncubator = 3
		start(p, "Mossling")
		t.eq(d.Incubation.EndsAt - d.Incubation.StartedAt, Config.IncubationSeconds - 3, "level 3")
		PlayerData._ForgetForTests(p)
	end)

	t.it("Rare Resonator multiplies only the Rare tier weight, and the odds report shows it", function()
		local base = { SpeciesId = "Mossling", BiomeId = "VerdantMeadows" }
		local boosted = { SpeciesId = "Mossling", BiomeId = "VerdantMeadows", TierModifiers = { { Tier = 3, Multiplier = 1.2, Source = "Upgrade:RareResonator" } } }
		local a = mutation:GetOddsReport(base).Categories[1].Tiers
		local b = mutation:GetOddsReport(boosted).Categories[1].Tiers
		local rareW, otherW = Registry.Rarity.Tiers[3].Chance * 1.2, 1 - Registry.Rarity.Tiers[3].Chance
		t.near(b[3].Probability, rareW / (rareW + otherW), 1e-9, "exact renormalised Rare")
		t.near(b[1].Probability / b[2].Probability, a[1].Probability / a[2].Probability, 1e-9, "other tiers keep their ratio")
		local tagged = false
		for _, m in b[3].Modifiers do
			tagged = tagged or m.Source == "Upgrade:RareResonator"
		end
		t.ok(tagged, "modifier reported")
		local r, err = mutation:Resolve({ SpeciesId = "Mossling", BiomeId = "VerdantMeadows", TierModifiers = { { Tier = 99, Multiplier = 5, Source = "x" } } })
		t.eq(err, "BadTierModifier", "invalid modifier rejected")
		local p, d = newPlayer()
		d.Upgrades.RareResonator = 2
		local ctx = incubation:BuildContext(d, { SpeciesId = "Mossling", BiomeId = "VerdantMeadows" })
		t.near(ctx.TierModifiers[1].Multiplier, 1.2, 1e-9, "server builds the modifier from the saved level")
		PlayerData._ForgetForTests(p)
	end)

	t.it("Habitat Expansion adds earning slots; Recycler keeps ~its stated share of catalysts", function()
		local p, d = newPlayer()
		for i = 1, 12 do
			local rec = generation:Generate(p.UserId, { SpeciesId = "Mossling", BiomeId = "VerdantMeadows" }, Random.new(i))
			d.Monsters[rec.MonsterId] = rec
		end
		local eight = economy:ComputeIncome(d)
		d.Upgrades.HabitatExpansion = 2
		local twelve = economy:ComputeIncome(d)
		t.ok(twelve > eight, "more slots, more income")
		t.eq(ProgressionService.EarningSlots(d), Config.EarningSlots + 4, "8 + 4")
		-- Recycler: 20% at level 2.
		d.Upgrades.CatalystRecycler = 2
		d.Coins, d.Inventory.Dewdrop = 1e9, 999
		local kept, n = 0, 3000
		for _ = 1, n do
			local r = start(p, "Mossling", "VerdantMeadows", { "Dewdrop" })
			kept += #r.Recycled
			d.Incubation = nil
			d.Inventory.Dewdrop = 999
		end
		local se = math.sqrt(0.2 * 0.8 / n)
		t.log(string.format("Recycler L2: kept %.3f of catalysts (stated 0.200), n=%d", kept / n, n))
		t.ok(math.abs(kept / n - 0.2) <= 4 * se, "recycle rate")
		PlayerData._ForgetForTests(p)
	end)

	t.it("research: prerequisites, biome, RP cost, idempotent; unlocks gated mutation", function()
		local p, d = newPlayer()
		d.ResearchPoints = 1000
		t.eq(prog:BuyResearch(p, "WorldtreeStudy").Error, "ResearchLocked", "needs Recipe Analyzer")
		t.ok(prog:BuyResearch(p, "RecipeAnalyzer").Ok, "analyzer")
		t.eq(d.ResearchPoints, 1000 - Progression.ResearchById.RecipeAnalyzer.Cost, "RP spent")
		t.ok(prog:BuyResearch(p, "RecipeAnalyzer").AlreadyOwned, "no double charge")
		t.eq(d.ResearchPoints, 1000 - Progression.ResearchById.RecipeAnalyzer.Cost, "still once")
		t.eq(prog:BuyResearch(p, "CryoStudy").Error, "BiomeLocked", "cryo needs Frostfall")
		d.ResearchPoints = 10
		t.eq(prog:BuyResearch(p, "WorldtreeStudy").Error, "NotEnoughResearch", "not enough RP")
		d.ResearchPoints = 1000
		t.ok(prog:BuyResearch(p, "WorldtreeStudy").Ok, "worldtree")
		d.Level = 10
		local ctx = incubation:BuildContext(d, { SpeciesId = "Mossling", BiomeId = "VerdantMeadows" })
		local r = assert(mutation:Resolve(ctx))
		t.ok(mutation:CheckEligibility(Registry.Mutations.ById.WorldtreeSeed, r, {}), "Worldtree Seed now eligible")
		PlayerData._ForgetForTests(p)
	end)

	t.it("claiming awards Research Points and auto-equips the first monster only", function()
		local p, d = newPlayer()
		d.Coins = 10000
		local s = start(p, "Mossling")
		clock += 100
		local c = incubation:Claim(p, s.Incubation.OpId)
		t.ok(c.AutoEquipped, "first monster auto-equipped")
		t.eq(d.Equipped, c.Record.MonsterId, "equipped id")
		local newCount = #c.NewMutations + 1
		t.eq(c.ResearchPoints, math.floor(c.Record.Stats.ResearchValue * Progression.RPPerResearchValue) + newCount * Progression.RPPerDiscovery, "RP formula")
		t.eq(d.ResearchPoints, c.ResearchPoints, "RP saved")
		local s2 = start(p, "Pebbleback")
		clock += 100
		local c2 = incubation:Claim(p, s2.Incubation.OpId)
		t.ok(not c2.AutoEquipped, "second monster does not steal the slot")
		t.eq(d.Equipped, c.Record.MonsterId, "still the first")
		PlayerData._ForgetForTests(p)
	end)

	t.it("gathering: range, cooldown, biome lock, stack limit", function()
		local p, d = newPlayer()
		local char = Instance.new("Model")
		local root = Instance.new("Part")
		root.Name = "HumanoidRootPart"
		root.Anchored = true
		root.Parent = char
		p.Character = char
		local node = Instance.new("Part")
		node.Anchored = true
		node:SetAttribute("NodeType", "DewdropFlower")
		node:SetAttribute("NodeId", "TestFlower")
		node.Position = Vector3.new(0, 0, 0)
		root.Position = Vector3.new(100, 0, 0)
		t.eq(prog:Gather(p, node).Error, "TooFar", "too far")
		root.Position = Vector3.new(3, 0, 0)
		local before = d.Inventory.Dewdrop or 0
		local r = prog:Gather(p, node)
		t.ok(r.Ok and (d.Inventory.Dewdrop or 0) > before, "gathered")
		local again = prog:Gather(p, node)
		t.eq(again.Error, "Cooldown", "cooldown")
		clock += Progression.GatherNodes.DewdropFlower.Cooldown
		t.ok(prog:Gather(p, node).Ok, "ready after cooldown")
		clock += 1000
		d.Inventory.Dewdrop = Registry.Materials.ById.Dewdrop.StackLimit
		local full = prog:Gather(p, node)
		t.eq(d.Inventory.Dewdrop, Registry.Materials.ById.Dewdrop.StackLimit, "never exceeds stack limit")
		t.eq(full.Granted.Dewdrop, nil, "nothing granted past the limit")
		local frost = node:Clone()
		frost:SetAttribute("NodeType", "FrostCrystal")
		frost:SetAttribute("NodeId", "TestCrystal")
		t.eq(prog:Gather(p, frost).Error, "BiomeLocked", "frost node needs Frostfall")
		char:Destroy()
		node:Destroy()
		frost:Destroy()
		PlayerData._ForgetForTests(p)
	end)

	t.it("gather drop chances match the stated values (30k rolls)", function()
		local rng = Random.new(66)
		local n = 30000
		local function rate(nodeType, events, mat)
			local c = 0
			for _ = 1, n do
				if ProgressionService.RollDrops(nodeType, events, rng)[mat] then
					c += 1
				end
			end
			return c / n
		end
		for _, case in {
			{ "DewdropFlower", {}, "FertileSoil", 0.15 },
			{ "DewdropFlower", {}, "AncientSeed", 0.03 },
			{ "FrostCrystal", {}, "GlacierCrystal", 0.12 },
			{ "FrostCrystal", {}, "AuroraFragment", 0 },
			{ "FrostCrystal", { AuroraNight = 1 }, "AuroraFragment", 0.05 },
		} do
			local obs = rate(case[1], case[2], case[3])
			local p = case[4]
			local se = math.sqrt(math.max(p * (1 - p), 1e-12) / n)
			t.log(string.format("%-14s %-15s expected %.3f observed %.4f", case[1], case[3], p, obs))
			t.ok(math.abs(obs - p) <= 4 * se + 1e-9, case[3])
			task.wait()
		end
	end)
end
