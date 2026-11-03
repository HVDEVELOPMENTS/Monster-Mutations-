-- Daily rewards and daily quests (rules in Shared/Rewards). Saved data:
--   Daily  = { Streak, LastDay }                      calendar progress
--   Quests = { Day, Progress = { [Kind] = n }, Claimed = { [QuestId] = true } }
-- Other services call RewardsService.Bump(data, kind, amount) when the player
-- hatches, battles, gathers, fuses or discovers; progress resets each new day.
-- Claims are checked here, so a reward can never be taken early or twice.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Rewards = require(ReplicatedStorage.MonsterFactory.Shared.Rewards)

local RewardsService = {}
RewardsService.__index = RewardsService

function RewardsService.new(deps: { PlayerData: any })
	local self = setmetatable({}, RewardsService)
	self.PlayerData = deps.PlayerData
	self.Now = os.time
	return self
end

-- Today's quest progress, starting fresh on a new day.
local function questsToday(data: any, day: number)
	if type(data.Quests) ~= "table" or data.Quests.Day ~= day then
		data.Quests = { Day = day, Progress = {}, Claimed = {} }
	end
	return data.Quests
end

-- Counts an action towards today's quests (kind = a Rewards.Pool Kind).
function RewardsService.Bump(data: any, kind: string, amount: number?, now: number?)
	local q = questsToday(data, Rewards.DayOf(now or os.time()))
	q.Progress[kind] = (q.Progress[kind] or 0) + (amount or 1)
end

-- Client view: the calendar and today's quests with progress.
function RewardsService.PublicState(data: any, userId: number, now: number)
	local day = Rewards.DayOf(now)
	local calendarDay, canClaim = Rewards.DailyStatus(data.Daily, day)
	local q = questsToday(data, day)
	local quests = {}
	for _, quest in Rewards.QuestsFor(userId, day) do
		table.insert(quests, {
			Id = quest.Id,
			Text = quest.Text,
			Goal = quest.Goal,
			Progress = math.min(q.Progress[quest.Kind] or 0, quest.Goal),
			Claimed = q.Claimed[quest.Id] == true,
			Coins = Rewards.QuestCoins(quest, data.Level),
			XP = quest.XP,
		})
	end
	return {
		Daily = { Day = calendarDay, CanClaim = canClaim, NextDayAt = (day + 1) * Rewards.DAY },
		Quests = quests,
	}
end

function RewardsService:ClaimDaily(player: Player)
	local profile = self.PlayerData.Get(player)
	if not profile then
		return { Ok = false, Error = "NotLoaded" }
	end
	local data = profile.Data
	local today = Rewards.DayOf(self.Now())
	local calendarDay, canClaim = Rewards.DailyStatus(data.Daily, today)
	if not canClaim then
		return { Ok = false, Error = "AlreadyClaimed" }
	end
	local gift = Rewards.DailyGifts[calendarDay]
	data.Daily = { Streak = calendarDay, LastDay = today }
	data.Coins += gift.Coins
	for id, n in gift.Items or {} do
		data.Inventory[id] = (data.Inventory[id] or 0) + n
	end
	self.PlayerData.MarkDirty(player, "All")
	return { Ok = true, Day = calendarDay, Coins = gift.Coins, Items = gift.Items }
end

function RewardsService:ClaimQuest(player: Player, questId: any)
	local profile = self.PlayerData.Get(player)
	if not profile then
		return { Ok = false, Error = "NotLoaded" }
	end
	local data = profile.Data
	local day = Rewards.DayOf(self.Now())
	local quest = nil
	for _, q in Rewards.QuestsFor(player.UserId, day) do
		if q.Id == questId then
			quest = q
		end
	end
	if not quest then
		return { Ok = false, Error = "BadRequest" }
	end
	local q = questsToday(data, day)
	if q.Claimed[quest.Id] then
		return { Ok = false, Error = "AlreadyClaimed" }
	end
	if (q.Progress[quest.Kind] or 0) < quest.Goal then
		return { Ok = false, Error = "NotFinished" }
	end
	q.Claimed[quest.Id] = true
	local coins = Rewards.QuestCoins(quest, data.Level)
	data.Coins += coins
	-- Required here, not at the top: Progression -> Rewards -> Economy -> Progression.
	local EconomyService = require(script.Parent.EconomyService)
	local levels = EconomyService.AddXP(data, quest.XP)
	self.PlayerData.MarkDirty(player, "All")
	return { Ok = true, Coins = coins, XP = quest.XP, LevelsGained = levels, NewLevel = data.Level }
end

return RewardsService
