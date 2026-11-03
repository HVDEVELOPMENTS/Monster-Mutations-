-- Daily rewards and daily quests: the calendar walks 1..7 and restarts after a
-- missed day or a finished week; quests count real actions, reset each day and
-- can only be claimed once, when finished.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Registry = require(ReplicatedStorage.MonsterFactory.Shared.Registry)
local Rewards = require(ReplicatedStorage.MonsterFactory.Shared.Rewards)
local Services = script.Parent.Parent.Services
local MutationService = require(Services.MutationService)
local MonsterGenerationService = require(Services.MonsterGenerationService)
local PlayerData = require(Services.PlayerDataService)
local RewardsService = require(Services.RewardsService)

return function(t)
	local mutation = MutationService.new(Registry)
	local generation = MonsterGenerationService.new(Registry, mutation)
	local rewards = RewardsService.new({ PlayerData = PlayerData })
	local clock = 20000 * Rewards.DAY + 3600
	rewards.Now = function()
		return clock
	end
	local nextId = 91000
	local function newPlayer()
		PlayerData._UseStoreForTests(nil, generation)
		nextId += 1
		local p = { UserId = nextId, Parent = workspace, Name = "R" .. nextId }
		return p, PlayerData.Load(p).Data
	end

	t.it("every gift and quest refers to real items and kinds", function()
		for i, g in Rewards.DailyGifts do
			t.ok(g.Coins > 0, "day " .. i .. " coins")
			for id in g.Items or {} do
				t.ok(Registry.Materials.ById[id] ~= nil, "day " .. i .. " item " .. id)
			end
		end
		local kinds = { Hatch = true, HatchRare = true, BattleWin = true, TrainerWin = true, Gather = true, Fuse = true, Discover = true }
		for _, q in Rewards.Pool do
			t.ok(kinds[q.Kind], q.Id .. " kind is counted somewhere")
		end
		local qs = Rewards.QuestsFor(123, 20000)
		t.eq(#qs, Rewards.QuestsPerDay, "three quests a day")
		local seen = {}
		for _, q in qs do
			t.ok(not seen[q.Kind], "no two quests of the same kind")
			seen[q.Kind] = true
		end
		t.eq(Rewards.QuestsFor(123, 20000)[1].Id, qs[1].Id, "same quests for the same day")
	end)

	t.it("the daily calendar walks the week, once a day, and restarts after a gap", function()
		local p, d = newPlayer()
		local coins = d.Coins
		local r1 = rewards:ClaimDaily(p)
		t.ok(r1.Ok and r1.Day == 1 and d.Coins == coins + Rewards.DailyGifts[1].Coins, "day 1 gift")
		t.eq(rewards:ClaimDaily(p).Error, "AlreadyClaimed", "once a day")
		for day = 2, 7 do
			clock += Rewards.DAY
			local r = rewards:ClaimDaily(p)
			t.eq(r.Day, day, "day " .. day)
		end
		t.ok((d.Inventory.AncientSeed or 0) >= 1, "day 7 jackpot item")
		clock += Rewards.DAY
		t.eq(rewards:ClaimDaily(p).Day, 1, "a new week after day 7")
		clock += Rewards.DAY * 3
		t.eq(rewards:ClaimDaily(p).Day, 1, "a missed day restarts the week")
		PlayerData._ForgetForTests(p)
	end)

	t.it("quests count actions, pay once when finished, and reset the next day", function()
		local p, d = newPlayer()
		local day = Rewards.DayOf(clock)
		local quest = Rewards.QuestsFor(p.UserId, day)[1]
		t.eq(rewards:ClaimQuest(p, quest.Id).Error, "NotFinished", "not done yet")
		t.eq(rewards:ClaimQuest(p, "NoSuchQuest").Error, "BadRequest", "unknown quest")
		RewardsService.Bump(d, quest.Kind, quest.Goal, clock)
		local view = RewardsService.PublicState(d, p.UserId, clock)
		t.eq(view.Quests[1].Progress, quest.Goal, "progress shown")
		local coins = d.Coins
		local r = rewards:ClaimQuest(p, quest.Id)
		t.ok(r.Ok and d.Coins == coins + Rewards.QuestCoins(quest, d.Level), "paid")
		t.eq(rewards:ClaimQuest(p, quest.Id).Error, "AlreadyClaimed", "only once")
		clock += Rewards.DAY
		local tomorrow = RewardsService.PublicState(d, p.UserId, clock)
		for _, q in tomorrow.Quests do
			t.ok(q.Progress == 0 and not q.Claimed, "fresh quests tomorrow")
		end
		PlayerData._ForgetForTests(p)
	end)
end
