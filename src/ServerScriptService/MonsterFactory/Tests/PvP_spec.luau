-- Player vs player battles: challenge/accept/decline, both sides choose before a
-- turn plays, each side sees itself as "P", the turn timer picks for idle
-- players, forfeits and disconnects end it, and prizes can't be farmed.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Registry = require(ReplicatedStorage.MonsterFactory.Shared.Registry)
local Services = script.Parent.Parent.Services
local MutationService = require(Services.MutationService)
local MonsterGenerationService = require(Services.MonsterGenerationService)
local PlayerData = require(Services.PlayerDataService)
local EconomyService = require(Services.EconomyService)
local BattleService = require(Services.BattleService)

return function(t)
	local mutation = MutationService.new(Registry)
	local generation = MonsterGenerationService.new(Registry, mutation)
	local economy = EconomyService.new({ PlayerData = PlayerData })
	local battles = BattleService.new({ PlayerData = PlayerData, Generation = generation, Economy = economy })
	local clock = 3000000
	battles.Now = function()
		return clock
	end
	battles.IsPlayer = function(x)
		return type(x) == "table" and x.UserId ~= nil
	end
	local inbox = {} -- [player] = { messages }
	battles.Push = function(player, msg)
		inbox[player] = inbox[player] or {}
		table.insert(inbox[player], msg)
	end
	local function last(player, kind: string?)
		local list = inbox[player] or {}
		for i = #list, 1, -1 do
			if not kind or list[i].Kind == kind then
				return list[i]
			end
		end
		return nil
	end

	local nextId = 87000
	local function newPlayer(speciesId: string?, tier: number?)
		PlayerData._UseStoreForTests(nil, generation)
		nextId += 1
		local p = { UserId = nextId, Parent = workspace, Name = "V" .. nextId, DisplayName = "Kid" .. nextId }
		local d = PlayerData.Load(p).Data
		if speciesId then
			local sp = Registry.Species.ById[speciesId]
			local rec = generation:Generate(p.UserId, { SpeciesId = speciesId, BiomeId = sp.HomeBiome }, Random.new(nextId))
			rec.RarityTier = tier or 1
			d.Monsters[rec.MonsterId] = rec
		end
		return p, d
	end
	local function startPvP(a, b)
		t.ok(battles:Challenge(a, b).Ok, "challenge sent")
		local ch = last(b, "Challenge")
		t.ok(ch and ch.FromUserId == a.UserId, "target got the challenge")
		t.ok(battles:Respond(b, a.UserId, true).Ok, "accepted")
		return last(a, "Start").Battle, last(b, "Start").Battle
	end

	t.it("challenge needs two free players with monsters; declining tells the challenger", function()
		local a = newPlayer("Mossling")
		local b = newPlayer("Pebbleback")
		local empty = newPlayer()
		t.eq(battles:Challenge(a, a).Error, "BadRequest", "can't challenge yourself")
		t.eq(battles:Challenge(a, "nobody").Error, "BadRequest", "must be a player")
		t.eq(battles:Challenge(a, empty).Error, "PlayerHasNoMonsters", "target needs a monster")
		t.eq(battles:Challenge(empty, a).Error, "NoMonsters", "challenger needs a monster")
		t.ok(battles:Challenge(a, b).Ok, "challenged")
		t.ok(battles:Respond(b, a.UserId, false).Ok, "declined")
		t.eq(last(a, "Declined").Name, b.DisplayName, "challenger told")
		t.eq(battles:Respond(b, a.UserId, true).Error, "ChallengeGone", "can't accept after declining")
		battles:Challenge(a, b)
		clock += BattleService.ChallengeSeconds
		t.eq(battles:Respond(b, a.UserId, true).Error, "ChallengeGone", "challenges expire")
		for _, p in { a, b, empty } do
			battles:Forget(p)
			PlayerData._ForgetForTests(p)
		end
	end)

	t.it("a turn plays only when both have chosen, and each side sees itself as P", function()
		local a = newPlayer("Mossling", 2)
		local b = newPlayer("Cindermite", 2)
		local va, vb = startPvP(a, b)
		t.eq(va.Kind, "PvP", "pvp battle")
		t.eq(va.Id, vb.Id, "same battle")
		t.eq(va.Team[1].SpeciesId, "Mossling", "A sees its own monster as Team")
		t.eq(vb.Team[1].SpeciesId, "Cindermite", "B sees its own monster as Team")
		t.eq(vb.Opponent, a.DisplayName, "B sees who challenged")
		t.eq(battles:Challenge(a, b).Error, "AlreadyBattling", "one battle at a time")
		local r = battles:Act(a, va.Id, { Type = "Move", Index = 1 })
		t.ok(r.Ok and r.Waiting, "A waits for B")
		t.eq(last(a, "Turn"), nil, "no turn yet")
		t.ok(last(b, "OpponentReady") ~= nil, "B told A is ready")
		t.eq(battles:Act(a, va.Id, { Type = "Move", Index = 1 }).Error, "AlreadyChose", "one choice per turn")
		battles:Act(b, vb.Id, { Type = "Move", Index = 2 })
		local ta, tb = last(a, "Turn"), last(b, "Turn")
		t.ok(ta and tb, "both got the turn")
		t.eq(#ta.Events, #tb.Events, "same events")
		for i, ev in ta.Events do
			if ev.Side then
				t.ok(ev.Side ~= tb.Events[i].Side, "sides flipped for B")
			end
		end
		t.eq(ta.Battle.Team[1].HP, tb.Battle.Enemy[1].HP, "HP agrees both ways")
		battles:Forget(a)
		battles:Forget(b)
		PlayerData._ForgetForTests(a)
		PlayerData._ForgetForTests(b)
	end)

	t.it("the turn timer picks for an idle player; a battle runs to a winner who is paid once", function()
		local a, da = newPlayer("Venomtail", 8)
		local b, db = newPlayer("Mossling", 1)
		local va = startPvP(a, b)
		local coins = da.Coins
		local result
		for _ = 1, 60 do
			battles:Act(a, va.Id, { Type = "Move", Index = 1 })
			clock += BattleService.PvPTurnSeconds
			battles:Tick() -- B never chooses: the computer does
			result = last(a, "Turn")
			if result and result.Result then
				break
			end
		end
		t.eq(result and result.Result, "Win", "strong A wins")
		t.eq(last(b, "Turn").Result, "Lose", "B loses")
		t.eq(da.Coins, coins + BattleService.PvPReward, "prize paid")
		t.eq(da.Battles.PvPWins, 1, "pvp win counted")
		t.eq(db.Battles.PvPLosses, 1, "pvp loss counted")
		-- Again straight away: no second prize from the same opponent.
		local va2 = startPvP(a, b)
		battles:Act(a, va2.Id, { Type = "Run" })
		t.eq(last(b, "Turn").Result, "Win", "running away forfeits")
		local again = startPvP(b, a)
		battles:Act(b, again.Id, { Type = "Run" })
		local before = da.Coins
		local va3 = startPvP(a, b)
		battles:Forget(b) -- B leaves the game
		t.eq(last(a, "Turn").Result, "Win", "leaving forfeits")
		t.eq(da.Coins, before, "no farming the same opponent")
		t.eq(battles:Act(a, va3.Id, { Type = "Move", Index = 1 }).Error, "NoBattle", "battle over")
		battles:Forget(a)
		PlayerData._ForgetForTests(a)
		PlayerData._ForgetForTests(b)
	end)
end
