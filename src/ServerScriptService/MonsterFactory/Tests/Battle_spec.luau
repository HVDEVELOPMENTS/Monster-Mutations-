-- Battles: element chart and stats are sane, battles run to a result, rewards
-- are paid once on a win, trainers rest after a win, wild spots respawn, and
-- every action is validated.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Registry = require(ReplicatedStorage.MonsterFactory.Shared.Registry)
local Battle = require(ReplicatedStorage.MonsterFactory.Shared.Battle)
local Trainers = require(ReplicatedStorage.MonsterFactory.Shared.Trainers)
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
	local clock = 2000000
	battles.Now = function()
		return clock
	end
	battles.Spots.Wild.TestSpot = { Biome = "VerdantMeadows", Species = "Mossling" }
	local nextId = 85000
	local function newPlayer()
		PlayerData._UseStoreForTests(nil, generation)
		nextId += 1
		local p = { UserId = nextId, Parent = workspace, Name = "B" .. nextId }
		return p, PlayerData.Load(p).Data
	end
	local function give(p, d, speciesId: string, tier: number, seed: number)
		local sp = Registry.Species.ById[speciesId]
		local rec = generation:Generate(p.UserId, { SpeciesId = speciesId, BiomeId = sp.HomeBiome }, Random.new(seed))
		rec.RarityTier = tier
		d.Monsters[rec.MonsterId] = rec
		return rec.MonsterId
	end
	-- Plays like a sensible kid until the battle ends: SUPER when the meter is
	-- full, otherwise the strongest move. Returns the last response.
	local function playOut(p, battle)
		local last
		local view = battle
		for _ = 1, Battle.MaxTurns + 1 do
			local me = view.Team[view.P]
			local action
			if me.Super and me.Charge >= Battle.SUPER_CHARGE then
				action = { Type = "Super" }
			else
				local best, bestPower = 1, -1
				for i, id in me.Moves do
					if Battle.Moves[id].Power > bestPower then
						best, bestPower = i, Battle.Moves[id].Power
					end
				end
				action = { Type = "Move", Index = best }
			end
			last = battles:Act(p, battle.Id, action)
			if not last.Ok or last.Result then
				return last
			end
			view = last.Battle
		end
		return last
	end

	t.it("element chart is consistent and every species has moves and stats", function()
		for atk, list in Battle.Strong do
			for def in list do
				t.ok(not (Battle.Strong[def] and Battle.Strong[def][atk]), atk .. " vs " .. def .. " is one-way")
				t.eq(Battle.ElementMultiplier(atk, def), Battle.STRONG, "strong")
				t.eq(Battle.ElementMultiplier(def, atk), Battle.WEAK, "weak back")
			end
		end
		for _, sp in Registry.Species.List do
			t.ok(Battle.ElementMoves[sp.PrimaryElement], sp.Id .. " element has moves")
			local rec = generation:Generate(1, { SpeciesId = sp.Id, BiomeId = sp.HomeBiome }, Random.new(7))
			local s = Battle.StatsFor(rec)
			t.ok(s.MaxHP > 0 and s.Attack > 0 and s.Defense > 0 and s.Speed > 0, sp.Id .. " stats")
			for _, m in Battle.MovesFor(rec) do
				t.ok(Battle.Moves[m] ~= nil, sp.Id .. " move " .. m)
			end
		end
		for _, tr in Trainers.List do
			t.ok(Registry.Biomes.ById[tr.Biome] ~= nil, tr.Id .. " biome")
			for _, e in tr.Team do
				t.ok(Registry.Species.ById[e.Species] ~= nil, tr.Id .. " species " .. e.Species)
			end
		end
	end)

	t.it("a strong team beats a wild monster once and is paid once", function()
		local p, d = newPlayer()
		give(p, d, "Mossling", 6, 1)
		d.Coins = 0
		local s = battles:Start(p, "Wild", "TestSpot")
		t.ok(s.Ok and #s.Battle.Team == 1 and #s.Battle.Enemy == 1, "battle started with best monster")
		local r = playOut(p, s.Battle)
		t.eq(r.Result, "Win", "won")
		t.ok(r.Coins > 0 and d.Coins == r.Coins, "paid the reward")
		t.eq(d.Battles.Wins, 1, "win counted")
		t.eq(battles:Act(p, s.Battle.Id, { Type = "Move", Index = 1 }).Error, "NoBattle", "battle is over")
		t.eq(battles:Start(p, "Wild", "TestSpot").Error, "WildGone", "spot respawns later")
		clock += Battle.WildRespawnSeconds
		t.ok(battles:Start(p, "Wild", "TestSpot").Ok, "spot back after respawn time")
		battles:Forget(p)
		PlayerData._ForgetForTests(p)
	end)

	t.it("a weak team loses to a top trainer; the trainer rests after a win", function()
		local p, d = newPlayer()
		for _, b in Registry.Biomes.List do
			d.UnlockedBiomes[b.Id] = true
		end
		give(p, d, "Mossling", 1, 2)
		local s = battles:Start(p, "Trainer", "DrVenom")
		t.ok(s.Ok and #s.Battle.Enemy == 3, "trainer team of three")
		local r = playOut(p, s.Battle)
		t.eq(r.Result, "Lose", "lost")
		t.eq(d.Battles.Losses, 1, "loss counted")
		t.eq(d.TrainerWins.DrVenom, nil, "no cooldown after a loss")

		local strong = give(p, d, "Venomtail", 8, 3)
		d.Equipped = { strong }
		local coins = d.Coins
		local s2 = battles:Start(p, "Trainer", "Pip")
		local r2 = playOut(p, s2.Battle)
		t.eq(r2.Result, "Win", "beat Pip")
		t.eq(d.Coins, coins + Trainers.ById.Pip.Reward, "trainer reward")
		-- A rematch is allowed straight away, but pays no coins while Pip rests.
		local s3 = battles:Start(p, "Trainer", "Pip")
		t.ok(s3.Ok and s3.Battle.Title:find("Rematch") ~= nil, "rematch allowed")
		local coins2 = d.Coins
		local r3 = playOut(p, s3.Battle)
		t.ok(r3.Result == "Win" and r3.Coins == 0 and d.Coins == coins2, "no coins during the cooldown")
		clock += Battle.TrainerCooldownSeconds
		local s4 = battles:Start(p, "Trainer", "Pip")
		t.ok(s4.Ok and s4.Battle.Title:find("Rematch") == nil, "Pip pays again after resting")
		battles:Forget(p)
		PlayerData._ForgetForTests(p)
	end)

	t.it("actions are validated; switching and running work", function()
		local p, d = newPlayer()
		local a = give(p, d, "Mossling", 2, 4)
		local b = give(p, d, "Pebbleback", 2, 5)
		d.Equipped = { a, b }
		t.eq(battles:Start(p, "Wild", "Nowhere").Error, "BadRequest", "unknown spot")
		t.eq(battles:Start(p, "Boss", "TestSpot").Error, "BadRequest", "unknown kind")
		t.eq(battles:Start(p, "Trainer", "Yuki").Error, "BiomeLocked", "locked biome trainer")
		local s = battles:Start(p, "Wild", "TestSpot")
		t.ok(s.Ok and #s.Battle.Team == 2, "two pets fight")
		t.ok(battles:Start(p, "Wild", "TestSpot").Resumed, "one battle at a time")
		t.eq(battles:Act(p, "wrong", { Type = "Run" }).Error, "NoBattle", "wrong battle id")
		t.eq(battles:Act(p, s.Battle.Id, { Type = "Move", Index = 9 }).Error, "BadRequest", "bad move")
		t.eq(battles:Act(p, s.Battle.Id, { Type = "Switch", To = 1 }).Error, "BadRequest", "already out")
		local sw = battles:Act(p, s.Battle.Id, { Type = "Switch", To = 2 })
		t.ok(sw.Ok and sw.Battle.P == 2, "switched")
		local run = battles:Act(p, s.Battle.Id, { Type = "Run" })
		t.eq(run.Result, "Ran", "ran away")
		t.eq(d.Battles.Wins + d.Battles.Losses, 0, "running is neither")
		PlayerData._ForgetForTests(p)
	end)

	t.it("trainers: valid themed mutations and a signature attack each; crits follow match-ups", function()
		local sigs = {}
		for _, tr in Trainers.List do
			local sig = Battle.Moves[tr.Signature.Id]
			t.ok(sig and sig.Signature, tr.Id .. " signature registered")
			t.ok(not sigs[tr.Signature.Id], tr.Id .. " signature is unique")
			sigs[tr.Signature.Id] = true
			t.ok(Battle.ElementMoves[sig.Element] ~= nil, tr.Id .. " signature element")
			for _, e in tr.Team do
				local sp = Registry.Species.ById[e.Species]
				local groups = {}
				t.ok(#e.Mutations > 0, tr.Id .. " " .. e.Species .. " has mutations")
				for _, id in e.Mutations do
					local m = Registry.Mutations.ById[id]
					t.ok(m ~= nil, tr.Id .. " mutation exists: " .. id)
					if m then
						t.ok(m.RarityTier <= e.Tier, tr.Id .. " " .. id .. " fits tier " .. e.Tier)
						t.ok(not m.RequiredAttachment or sp.Attachments[m.RequiredAttachment], tr.Id .. " " .. id .. " attachment")
						t.ok(not m.AllowedBiomes or table.find(m.AllowedBiomes, tr.Biome), tr.Id .. " " .. id .. " is from its biome")
						if m.ExclusiveGroup then
							t.ok(not groups[m.ExclusiveGroup], tr.Id .. " " .. id .. " exclusive group")
							groups[m.ExclusiveGroup] = true
						end
					end
				end
			end
		end
		local p, d = newPlayer()
		give(p, d, "Mossling", 1, 9)
		local s = battles:Start(p, "Trainer", "Pip")
		for _, foe in s.Battle.Enemy do
			t.ok(table.find(foe.Moves, "PebblePop") ~= nil, "Pip's monsters know Pebble Pop")
			t.ok(#foe.ActiveMutations > 0, "Pip's monsters wear their mutations")
		end
		battles:Forget(p)
		PlayerData._ForgetForTests(p)
		t.ok(Battle.CritChance(Battle.STRONG) > Battle.CritChance(1) and Battle.CritChance(1) > Battle.CritChance(Battle.WEAK), "match-ups change crit chance")
		local rng, crits = Random.new(3), 0
		local ember = { Element = "Ember", Stats = { Attack = 20, Defense = 20 } }
		local leaf = { Element = "Verdant", Stats = { Attack = 20, Defense = 20 } }
		for _ = 1, 2000 do
			local r = Battle.Attack(ember, leaf, "Ember", rng)
			crits += if r.Crit then 1 else 0
		end
		t.near(crits / 2000, Battle.CRIT_CHANCE_STRONG, 0.04, "Ember crits Verdant about 25% of the time")
	end)

	t.it("no monsters means no battle", function()
		local p = newPlayer()
		t.eq(battles:Start(p, "Wild", "TestSpot").Error, "NoMonsters", "need a monster")
		PlayerData._ForgetForTests(p)
	end)

	t.it("SUPER moves need a full meter; statuses tick and wear off", function()
		for element in Battle.ElementMoves do
			local s = Battle.SuperMoves[element]
			t.ok(s and Battle.Moves[s[1]] and Battle.Moves[s[1]].Super, element .. " has a SUPER move")
		end
		for el, status in Battle.ElementStatus do
			t.ok(Battle.Statuses[status] ~= nil, el .. " status " .. status)
		end
		local p, d = newPlayer()
		give(p, d, "Cindermite", 4, 21)
		local s = battles:Start(p, "Wild", "TestSpot")
		t.ok(s.Ok and s.Battle.Team[1].Super == "InfernoBlast", "Cindermite's SUPER is Inferno Blast")
		t.eq(battles:Act(p, s.Battle.Id, { Type = "Super" }).Error, "BadRequest", "meter not full yet")
		local b = battles._battles[p]
		b.Team[b.P].Charge = Battle.SUPER_CHARGE
		b.Enemy[b.E].HP = b.Enemy[b.E].Stats.MaxHP * 10 -- survive to see the effects
		local r = battles:Act(p, s.Battle.Id, { Type = "Super" })
		local superEv, burned = nil, false
		for _, ev in r.Events do
			if ev.Kind == "Move" and ev.Side == "P" then
				superEv = ev
			end
			if ev.Kind == "Status" and ev.Side == "E" and ev.Status == "Burn" then
				burned = true
			end
		end
		t.ok(superEv and superEv.Super and not superEv.Miss, "SUPER move used and never misses")
		t.eq(superEv and superEv.AtkCharge, 0, "meter empties when the SUPER is used")
		t.ok(burned, "a SUPER always applies its element's status")
		-- Burn ticks at the end of each turn, then wears off.
		local ticks, ended = 0, false
		for _ = 1, 4 do
			local rr = battles:Act(p, s.Battle.Id, { Type = "Move", Index = 1 })
			for _, ev in rr.Events or {} do
				if ev.Kind == "StatusTick" and ev.Side == "E" then
					ticks += 1
				end
				if ev.Kind == "StatusEnd" and ev.Side == "E" then
					ended = true
				end
			end
			if rr.Result then
				break
			end
		end
		t.ok(ticks >= 2, "burn hurts each turn")
		t.ok(ended, "burn wears off")
		battles:Forget(p)
		PlayerData._ForgetForTests(p)
	end)

	t.it("beating a boss trainer the first time earns its badge and a bonus", function()
		local p, d = newPlayer()
		local strong = give(p, d, "Venomtail", 8, 31)
		d.Equipped = { strong }
		t.ok(Trainers.ById.Rosa.Boss, "Rosa is the meadow boss")
		local coins = d.Coins
		local s = battles:Start(p, "Trainer", "Rosa")
		local r = playOut(p, s.Battle)
		t.eq(r.Result, "Win", "beat Rosa")
		t.eq(r.Badge, "VerdantMeadows", "meadow badge")
		t.ok(d.Badges.VerdantMeadows ~= nil, "badge saved")
		t.eq(d.Coins - coins, Trainers.ById.Rosa.Reward * (1 + Trainers.BadgeBonusMultiplier), "prize plus badge bonus")
		clock += Battle.TrainerCooldownSeconds
		local r2 = playOut(p, battles:Start(p, "Trainer", "Rosa").Battle)
		t.ok(r2.Result == "Win" and r2.Badge == nil, "the badge is earned once")
		battles:Forget(p)
		PlayerData._ForgetForTests(p)
	end)
end
