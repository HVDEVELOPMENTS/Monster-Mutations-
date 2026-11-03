-- Getting Started guide: steps advance from real progress, and the reward is
-- paid once, only after every step is done.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Registry = require(ReplicatedStorage.MonsterFactory.Shared.Registry)
local Tutorial = require(ReplicatedStorage.MonsterFactory.Shared.Tutorial)
local Services = script.Parent.Parent.Services
local MutationService = require(Services.MutationService)
local MonsterGenerationService = require(Services.MonsterGenerationService)
local PlayerData = require(Services.PlayerDataService)
local EconomyService = require(Services.EconomyService)

return function(t)
	local mutation = MutationService.new(Registry)
	local generation = MonsterGenerationService.new(Registry, mutation)
	local economy = EconomyService.new({ PlayerData = PlayerData })
	local nextId = 89000

	t.it("steps advance with progress and the reward is paid once at the end", function()
		PlayerData._UseStoreForTests(nil, generation)
		nextId += 1
		local p = { UserId = nextId, Parent = workspace, Name = "T" .. nextId }
		local d = PlayerData.Load(p).Data
		local function step()
			local i = Tutorial.Current(Tutorial.FromData(d))
			return i and Tutorial.Steps[i].Id
		end
		t.eq(step(), "Hatch", "new player starts at Hatch")
		t.eq(economy:ClaimTutorialReward(p).Error, "NotFinished", "no reward yet")
		table.insert(d.Incubations, { OpId = "x" })
		t.eq(step(), "Open", "an egg in the chamber -> open it")
		table.clear(d.Incubations)
		local rec = generation:Generate(p.UserId, { SpeciesId = "Mossling", BiomeId = "VerdantMeadows" }, Random.new(1))
		d.Monsters[rec.MonsterId] = rec
		d.Stats.Incubations = 1
		t.eq(step(), "Gather", "has a monster -> gather")
		d.GatherCooldowns.VerdantMeadows_1 = 1
		t.eq(step(), "Battle", "gathered -> battle")
		d.Battles.Wins = 1
		t.eq(step(), "Collect", "won -> collect")
		local collect = Tutorial.Steps[5]
		local _, cur, goal = Tutorial.StepStatus(collect, Tutorial.FromData(d))
		t.ok(cur == 1 and goal == 5, "collect shows 1/5")
		d.Stats.Incubations = 5
		t.eq(step(), "Fuse", "5 hatched -> fuse")
		d.Stats.Fusions = 1
		t.eq(step(), nil, "all done")
		local coins = d.Coins
		local r = economy:ClaimTutorialReward(p)
		t.ok(r.Ok and d.Coins == coins + Tutorial.Reward, "reward paid")
		t.eq(economy:ClaimTutorialReward(p).Error, "AlreadyClaimed", "only once")
		PlayerData._ForgetForTests(p)
	end)
end
