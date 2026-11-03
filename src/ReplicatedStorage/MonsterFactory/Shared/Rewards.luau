--!strict
-- Daily rewards and daily quests (pure rules, shared by server and client).
--   * Daily rewards: one gift per day along a 7-day calendar that grows to a
--     Day 7 jackpot. Missing a day only restarts the week; nothing is lost.
--   * Daily quests: 3 goals a day, picked from Pool the same way for the same
--     player and day, so server and client agree. Progress counts from the
--     player's actions that day; each finished quest is claimed for coins + XP.
-- Days are UTC days (unix time // 86400).

local Rewards = {}

Rewards.DAY = 86400

function Rewards.DayOf(unix: number): number
	return unix // Rewards.DAY
end

-- ===== Daily rewards =====
export type Gift = { Coins: number, Items: { [string]: number }? }
Rewards.DailyGifts = {
	{ Coins = 50 },
	{ Coins = 100 },
	{ Coins = 150, Items = { Dewdrop = 2 } },
	{ Coins = 250 },
	{ Coins = 350, Items = { FertileSoil = 1 } },
	{ Coins = 500 },
	{ Coins = 1000, Items = { AncientSeed = 1 } }, -- Day 7 jackpot
} :: { Gift }

-- Which calendar day (1-7) today's gift is, and whether it can be claimed.
-- daily = { Streak = days claimed in this week (0-7), LastDay = day number }
function Rewards.DailyStatus(daily: any, today: number): (number, boolean)
	local last = daily and daily.LastDay or -1
	local streak = daily and daily.Streak or 0
	if last == today then
		return math.max(streak, 1), false -- already claimed today
	end
	if last ~= today - 1 or streak >= #Rewards.DailyGifts then
		return 1, true -- first day, missed a day, or a finished week: start over
	end
	return streak + 1, true
end

-- ===== Daily quests =====
export type Quest = { Id: string, Kind: string, Goal: number, Text: string, Coins: number, XP: number }
Rewards.Pool = {
	{ Id = "Hatch3", Kind = "Hatch", Goal = 3, Text = "Hatch 3 eggs", Coins = 60, XP = 20 },
	{ Id = "Hatch8", Kind = "Hatch", Goal = 8, Text = "Hatch 8 eggs", Coins = 150, XP = 40 },
	{ Id = "Rare1", Kind = "HatchRare", Goal = 1, Text = "Hatch a RARE or better monster", Coins = 120, XP = 30 },
	{ Id = "Win2", Kind = "BattleWin", Goal = 2, Text = "Win 2 battles", Coins = 80, XP = 25 },
	{ Id = "Win5", Kind = "BattleWin", Goal = 5, Text = "Win 5 battles", Coins = 180, XP = 50 },
	{ Id = "Trainer1", Kind = "TrainerWin", Goal = 1, Text = "Beat a trainer", Coins = 120, XP = 30 },
	{ Id = "Gather3", Kind = "Gather", Goal = 3, Text = "Pick 3 glowing flowers or crystals", Coins = 60, XP = 20 },
	{ Id = "Fuse1", Kind = "Fuse", Goal = 1, Text = "Fuse two monsters", Coins = 100, XP = 30 },
	{ Id = "Discover1", Kind = "Discover", Goal = 1, Text = "Discover a new mutation", Coins = 100, XP = 30 },
} :: { Quest }
Rewards.QuestById = {} :: { [string]: Quest }
for _, q in Rewards.Pool do
	Rewards.QuestById[q.Id] = q
end
Rewards.QuestsPerDay = 3

-- Coins grow a little with level so quests stay worth doing later on.
function Rewards.QuestCoins(q: Quest, level: number): number
	return math.floor(q.Coins * (1 + 0.15 * math.max(level - 1, 0)) + 0.5)
end

-- Today's quests for a player: distinct, never two of the same kind.
function Rewards.QuestsFor(userId: number, day: number): { Quest }
	local rng = Random.new(day * 1000003 + userId % 1000003)
	local picked, kinds = {}, {}
	local order = table.clone(Rewards.Pool)
	for i = #order, 2, -1 do
		local j = rng:NextInteger(1, i)
		order[i], order[j] = order[j], order[i]
	end
	for _, q in order do
		if not kinds[q.Kind] and #picked < Rewards.QuestsPerDay then
			kinds[q.Kind] = true
			table.insert(picked, q)
		end
	end
	return picked
end

return Rewards
