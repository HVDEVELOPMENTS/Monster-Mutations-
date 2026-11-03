-- Turn-based battles against wild monsters and NPC trainers (rules in
-- Shared/Battle). The server runs everything: the client only picks a move,
-- a switch or Run, and gets back the events to animate. One battle per player,
-- kept in memory (never saved); rewards are paid once, when it is won.
--   * Your team: equipped pets in slot order, or your 3 strongest monsters.
--   * Wild spots (WorldBuilder "WildSpot") each hold one species; a beaten spot
--     comes back for you after Battle.WildRespawnSeconds.
--   * Trainers (Shared/Trainers) pay their reward again after a cooldown that is
--     saved in TrainerWins.
--   * Player vs player: see the "Player vs player" section below.

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Battle = require(ReplicatedStorage.MonsterFactory.Shared.Battle)
local Trainers = require(ReplicatedStorage.MonsterFactory.Shared.Trainers)
local Registry = require(ReplicatedStorage.MonsterFactory.Shared.Registry)
local EconomyService = require(script.Parent.EconomyService)
local RewardsService = require(script.Parent.RewardsService)

local BattleService = {}
BattleService.__index = BattleService

BattleService.MaxDistance = 26 -- studs from the wild spot / trainer to start

function BattleService.new(deps)
	local self = setmetatable({}, BattleService)
	self.PlayerData = deps.PlayerData
	self.Generation = deps.Generation
	self.Economy = deps.Economy
	self.Incubation = deps.Incubation -- live biome events for wild rolls
	self.Rng = Random.new()
	self.Now = os.time
	-- Filled by Main from the world (tests inject their own):
	-- Wild[spotId] = { Biome, Species, Position? }, Trainer[trainerId] = { Position? }
	self.Spots = { Wild = {}, Trainer = {} }
	self.PositionOf = function(_player): Vector3?
		return nil
	end
	self._battles = {} :: { [any]: any }
	self._wildBeaten = {} :: { [any]: { [string]: number } }
	self._challenges = {} :: { [any]: { From: any, At: number } } -- [target] = pending challenge
	self._pvpPaid = {} :: { [any]: { [number]: number } } -- [winner][loser UserId] = last prize
	self.Push = function(_player, _message) end -- Main: fires the "Battle" RemoteEvent
	self.IsPlayer = function(x: any): boolean -- tests swap in fake players
		return typeof(x) == "Instance" and x:IsA("Player")
	end
	return self
end

-- extraMove: a trainer's signature attack, added to the monster's own moves.
local function combatant(record: any, extraMove: string?)
	local stats = Battle.StatsFor(record)
	local moves = Battle.MovesFor(record)
	if extraMove then
		table.insert(moves, extraMove)
	end
	return {
		Record = record,
		Element = record.PrimaryElement,
		Stats = stats,
		HP = stats.MaxHP,
		Moves = moves,
		Super = Battle.SuperFor(record), -- ultimate move, usable at a full meter
		Charge = 0, -- power meter, 0..Battle.SUPER_CHARGE
		Status = nil :: string?, -- Battle.Statuses key
		StatusTurns = 0,
		Guard = 0, -- turns of raised defense left
	}
end

local function publicSide(list: { any })
	local out = {}
	for _, c in list do
		local r = c.Record
		table.insert(out, {
			Name = r.DisplayName,
			SpeciesId = r.SpeciesId,
			MonsterId = r.MonsterId,
			Genes = r.Genes,
			ActiveMutations = r.ActiveMutations,
			RarityTier = r.RarityTier,
			Element = c.Element,
			HP = c.HP,
			MaxHP = c.Stats.MaxHP,
			Speed = c.Stats.Speed,
			Moves = c.Moves,
			Super = c.Super,
			Charge = c.Charge,
			Status = c.Status,
			Guard = c.Guard,
		})
	end
	return out
end

function BattleService:View(b: any)
	return {
		Id = b.Id,
		Kind = b.Kind,
		Title = b.Title,
		Greeting = b.Greeting,
		TrainerName = b.TrainerName,
		TrainerId = if b.Kind == "Trainer" then b.SpotId else nil,
		Boss = b.Kind == "Trainer" and Trainers.ById[b.SpotId] ~= nil and Trainers.ById[b.SpotId].Boss == true,
		Team = publicSide(b.Team),
		Enemy = publicSide(b.Enemy),
		P = b.P,
		E = b.E,
		Turn = b.Turn,
	}
end

-- Your fighters: equipped pets, else your strongest three.
local function pickTeam(data: any): { any }
	local team = {}
	for _, id in data.Equipped do
		local rec = data.Monsters[id]
		if rec and #team < 3 then
			table.insert(team, rec)
		end
	end
	-- Fill the rest of the team (up to 3) with your strongest other monsters,
	-- so one equipped pet never has to fight a whole trainer team alone.
	if #team < 3 then
		local inTeam = {}
		for _, rec in team do
			inTeam[rec.MonsterId] = true
		end
		local rest = {}
		for _, rec in data.Monsters do
			if not inTeam[rec.MonsterId] then
				table.insert(rest, rec)
			end
		end
		table.sort(rest, function(a, b)
			return Battle.StatsFor(a).Attack > Battle.StatsFor(b).Attack
		end)
		for i = 1, math.min(3 - #team, #rest) do
			table.insert(team, rest[i])
		end
	end
	return team
end

function BattleService:_makeEnemy(speciesId: string, biomeId: string, tier: number?)
	local ctx = {
		SpeciesId = speciesId,
		BiomeId = biomeId,
		Catalysts = {},
		Events = if self.Incubation then self.Incubation:ActiveEventSet(biomeId) else {},
		Research = {},
		Progression = 1,
		TierModifiers = {},
	}
	local rec, err = self.Generation:Generate(0, ctx, self.Rng, { OriginMethod = "Wild", Now = self.Now() })
	if rec and tier then
		rec.RarityTier = tier
	end
	return rec, err
end

-- A trainer's monster: the team entry's exact mutations (look, stats, a second
-- element if one is elemental) and its tier.
function BattleService:_trainerMonster(entry: any)
	local sp = Registry.Species.ById[entry.Species]
	local rec, err = self:_makeEnemy(entry.Species, sp.HomeBiome, entry.Tier)
	if not rec then
		return nil, err
	end
	local muts, top = {}, nil
	rec.SecondaryElement = nil
	for _, id in entry.Mutations do
		local m = Registry.Mutations.ById[id]
		table.insert(muts, m)
		if m.Element and m.Element ~= sp.PrimaryElement then
			rec.SecondaryElement = m.Element
		end
		if not top or m.RarityTier > top.RarityTier then
			top = m
		end
	end
	rec.ActiveMutations = table.clone(entry.Mutations)
	rec.Genes = self.Generation:BuildGenes(sp, muts, self.Rng)
	rec.Stats = self.Generation:ComputeStats(sp, entry.Mutations)
	rec.DisplayName = if top and top.RarityTier >= 2 then (top.DisplayName .. " " .. sp.DisplayName) else sp.DisplayName
	return rec
end

local function near(self, player, pos: Vector3?): boolean
	local at = self.PositionOf(player)
	if not at or not pos then
		return true -- no world (tests) or no character position to check
	end
	return (at - pos).Magnitude <= BattleService.MaxDistance
end

function BattleService:Start(player: Player, kind: any, id: any)
	local profile = self.PlayerData.Get(player)
	if not profile then
		return { Ok = false, Error = "NotLoaded" }
	end
	local data = profile.Data
	local now = self.Now()
	local current = self._battles[player]
	if current and now - current.LastActive < Battle.IdleSeconds then
		local side = if current.Kind == "PvP" and current.B == player then "E" else "P"
		return { Ok = true, Battle = self:ViewFor(current, side), Resumed = true }
	end
	if type(id) ~= "string" or #id > 64 then
		return { Ok = false, Error = "BadRequest" }
	end
	local team = pickTeam(data)
	if #team == 0 then
		return { Ok = false, Error = "NoMonsters" }
	end

	local b = { Id = HttpService:GenerateGUID(false), Kind = kind, SpotId = id, Turn = 0, P = 1, E = 1, LastActive = now }
	if kind == "Wild" then
		local spot = self.Spots.Wild[id]
		if not spot then
			return { Ok = false, Error = "BadRequest" }
		end
		if not data.UnlockedBiomes[spot.Biome] then
			return { Ok = false, Error = "BiomeLocked" }
		end
		if not near(self, player, spot.Position) then
			return { Ok = false, Error = "TooFar" }
		end
		local beaten = self._wildBeaten[player] and self._wildBeaten[player][id]
		if beaten and now - beaten < Battle.WildRespawnSeconds then
			return { Ok = false, Error = "WildGone", Seconds = Battle.WildRespawnSeconds - (now - beaten) }
		end
		local rec, err = self:_makeEnemy(spot.Species, spot.Biome)
		if not rec then
			return { Ok = false, Error = err }
		end
		b.Enemy = { combatant(rec) }
		-- Wild monsters are the everyday fights: no SUPER moves (trainers and players only).
		b.Enemy[1].Super = nil
		b.Title = "A wild " .. rec.DisplayName .. " appeared!"
	elseif kind == "Trainer" then
		local trainer = Trainers.ById[id]
		if not trainer then
			return { Ok = false, Error = "BadRequest" }
		end
		if not data.UnlockedBiomes[trainer.Biome] then
			return { Ok = false, Error = "BiomeLocked" }
		end
		local spot = self.Spots.Trainer[id]
		-- Trainers walk around: check against where they are now, if spawned.
		local at = spot and (if spot.Live and spot.Live.Parent then spot.Live.Position else spot.Position)
		if not near(self, player, at) then
			return { Ok = false, Error = "TooFar" }
		end
		-- Rematches are always allowed; only the coin reward has a cooldown.
		local last = data.TrainerWins[id]
		local restLeft = if last then Battle.TrainerCooldownSeconds - (now - last) else 0
		if restLeft > 0 then
			b.Practice = true
		end
		b.Enemy = {}
		for _, entry in trainer.Team do
			local rec, err = self:_trainerMonster(entry)
			if not rec then
				return { Ok = false, Error = err }
			end
			table.insert(b.Enemy, combatant(rec, trainer.Signature.Id))
		end
		b.Title = if b.Practice
			then string.format("Rematch with %s! Coins come back in %d:%02d", trainer.DisplayName, restLeft // 60, restLeft % 60)
			else "Trainer " .. trainer.DisplayName .. " wants to battle!"
		b.Greeting = trainer.Greeting
		b.TrainerName = trainer.DisplayName
	else
		return { Ok = false, Error = "BadRequest" }
	end
	b.Team = {}
	for _, rec in team do
		table.insert(b.Team, combatant(rec))
	end
	self._battles[player] = b
	return { Ok = true, Battle = self:View(b) }
end

local function nextAlive(list: { any }, from: number): number?
	for i = 1, #list do
		local j = (from + i - 1) % #list + 1
		if list[j].HP > 0 then
			return j
		end
	end
	return nil
end

-- The active monster of `side` at index faints: event, then the next one comes out.
function BattleService:_faint(b: any, side: string, index: number, events: { any })
	local list = if side == "P" then b.Team else b.Enemy
	table.insert(events, { Kind = "Faint", Side = side, Index = index })
	local nxt = nextAlive(list, index)
	if nxt then
		if side == "E" then
			b.E = nxt
		else
			b.P = nxt
		end
		table.insert(events, { Kind = "SendOut", Side = side, Index = nxt })
	end
end

-- One side attacks the other's active monster; adds events, handles status
-- skips, the power meter, move effects, fainting and the automatic send-out
-- of the next monster. Returns true if a monster fainted.
function BattleService:_hit(b: any, side: string, moveId: string, events: { any }): boolean
	local atkList, defList = if side == "P" then b.Team else b.Enemy, if side == "P" then b.Enemy else b.Team
	local atk = atkList[if side == "P" then b.P else b.E]
	local defIndex = if side == "P" then b.E else b.P
	local def = defList[defIndex]
	local other = if side == "P" then "E" else "P"
	-- Frozen or shocked monsters may lose their turn.
	local st = atk.Status and Battle.Statuses[atk.Status]
	if st and st.SkipChance and self.Rng:NextNumber() < st.SkipChance then
		table.insert(events, { Kind = "Skip", Side = side, Status = atk.Status })
		return false
	end
	local m = Battle.Moves[moveId]
	if m.Super then
		atk.Charge = 0
	end
	local r = Battle.Attack(atk, def, moveId, self.Rng)
	def.HP = math.max(0, def.HP - r.Damage)
	if not r.Miss and not m.Super then
		atk.Charge = math.min(Battle.SUPER_CHARGE, atk.Charge + Battle.CHARGE_DEAL)
		def.Charge = math.min(Battle.SUPER_CHARGE, def.Charge + Battle.CHARGE_TAKE)
	end
	table.insert(events, {
		Kind = "Move", Side = side, Move = moveId, Super = m.Super == true,
		Damage = r.Damage, Mult = r.Mult, Crit = r.Crit, Miss = r.Miss, HP = def.HP,
		AtkCharge = atk.Charge, DefCharge = def.Charge,
	})
	-- The move's element effect.
	if not r.Miss and self.Rng:NextNumber() < Battle.EffectChance(moveId) then
		local status = Battle.ElementStatus[m.Element]
		if status and def.HP > 0 and not def.Status then
			def.Status, def.StatusTurns = status, Battle.Statuses[status].Turns
			table.insert(events, { Kind = "Status", Side = other, Status = status })
		elseif m.Element == "Verdant" and atk.HP < atk.Stats.MaxHP then
			local heal = math.max(1, math.floor(r.Damage * Battle.HEAL_SHARE * (if m.Super then 2 else 1)))
			atk.HP = math.min(atk.Stats.MaxHP, atk.HP + heal)
			table.insert(events, { Kind = "Heal", Side = side, Amount = heal, HP = atk.HP })
		elseif m.Element == "Earthen" then
			atk.Guard = Battle.GUARD_TURNS
			table.insert(events, { Kind = "Guard", Side = side })
		end
	end
	if def.HP > 0 then
		return false
	end
	self:_faint(b, other, defIndex, events)
	return true
end

-- End of a turn: burn/poison damage, statuses and guards wear off.
function BattleService:_endTurn(b: any, events: { any })
	for _, side in { "P", "E" } do
		local list = if side == "P" then b.Team else b.Enemy
		local index = if side == "P" then b.P else b.E
		local c = list[index]
		if c and c.HP > 0 then
			local st = c.Status and Battle.Statuses[c.Status]
			if st and st.Tick then
				local dmg = math.max(1, math.floor(c.Stats.MaxHP * st.Tick))
				c.HP = math.max(0, c.HP - dmg)
				table.insert(events, { Kind = "StatusTick", Side = side, Status = c.Status, Damage = dmg, HP = c.HP })
			end
			if c.Status then
				c.StatusTurns -= 1
				if c.StatusTurns <= 0 then
					table.insert(events, { Kind = "StatusEnd", Side = side, Status = c.Status })
					c.Status = nil
				end
			end
			if c.Guard > 0 then
				c.Guard -= 1
			end
			if c.HP <= 0 then
				self:_faint(b, side, index, events)
			end
		end
	end
end

local function allFainted(list: { any }): boolean
	return nextAlive(list, 1) == nil
end

local function totalHP(list: { any }): number
	local n = 0
	for _, c in list do
		n += c.HP
	end
	return n
end

-- Checks one side's choice; returns a clean action or nil.
local function cleanAction(b: any, side: string, action: any)
	if type(action) ~= "table" then
		return nil
	end
	local list = if side == "P" then b.Team else b.Enemy
	local active = if side == "P" then b.P else b.E
	if action.Type == "Run" then
		return { Type = "Run" }
	elseif action.Type == "Switch" then
		local to = action.To
		if type(to) == "number" and list[to] and list[to].HP > 0 and to ~= active then
			return { Type = "Switch", To = to }
		end
	elseif action.Type == "Move" then
		local moveId = type(action.Index) == "number" and list[active].Moves[action.Index]
		if moveId then
			return { Type = "Move", Move = moveId }
		end
	elseif action.Type == "Super" then
		local c = list[active]
		if c.Super and c.Charge >= Battle.SUPER_CHARGE then
			return { Type = "Move", Move = c.Super }
		end
	end
	return nil
end

-- The computer's choice for a side (the foe in PvE, or a PvP player who ran out
-- of time): a SUPER move as soon as the meter is full, else the best move.
function BattleService:_autoAction(b: any, side: string)
	local me = if side == "P" then b.Team[b.P] else b.Enemy[b.E]
	local foe = if side == "P" then b.Enemy[b.E] else b.Team[b.P]
	if me.Super and me.Charge >= Battle.SUPER_CHARGE then
		return { Type = "Move", Move = me.Super }
	end
	return { Type = "Move", Move = Battle.ChooseMove(me, foe, self.Rng) }
end

-- Best element multiplier a monster's moves get against an element.
local function bestMult(c: any, element: string): number
	local best = 0
	for _, id in c.Moves do
		local m = Battle.Moves[id]
		best = math.max(best, if m.Element == "Normal" then 1 else Battle.ElementMultiplier(m.Element, element))
	end
	return best
end

-- Trainers fight smarter than wild monsters: out of a bad match-up (every
-- move weak) they often swap to a teammate that does better.
function BattleService:_trainerAction(b: any)
	local me, foe = b.Enemy[b.E], b.Team[b.P]
	if not (me.Super and me.Charge >= Battle.SUPER_CHARGE) and bestMult(me, foe.Element) < 1 and me.HP > me.Stats.MaxHP * 0.3 and self.Rng:NextNumber() < 0.7 then
		for i, c in b.Enemy do
			if i ~= b.E and c.HP > 0 and bestMult(c, foe.Element) >= 1 then
				return { Type = "Switch", To = i }
			end
		end
	end
	return self:_autoAction(b, "E")
end

-- One turn: switches happen first, then moves in speed order. A monster that
-- faints (or was just sent out to replace one) doesn't strike back this turn.
function BattleService:_resolve(b: any, actP: any, actE: any): { any }
	local events = {}
	for _, pair in { { "P", actP }, { "E", actE } } do
		local side, act = pair[1], pair[2]
		if act.Type == "Switch" then
			if side == "P" then
				b.P = act.To
			else
				b.E = act.To
			end
			table.insert(events, { Kind = "SendOut", Side = side, Index = act.To })
		end
	end
	local movers = {}
	if actP.Type == "Move" then
		table.insert(movers, "P")
	end
	if actE.Type == "Move" then
		table.insert(movers, "E")
	end
	if #movers == 2 then
		local p, e = b.Team[b.P], b.Enemy[b.E]
		local pFirst = p.Stats.Speed > e.Stats.Speed or (p.Stats.Speed == e.Stats.Speed and self.Rng:NextNumber() < 0.5)
		if not pFirst then
			movers = { "E", "P" }
		end
	end
	for _, side in movers do
		local act = if side == "P" then actP else actE
		if self:_hit(b, side, act.Move, events) then
			break
		end
	end
	if not allFainted(b.Team) and not allFainted(b.Enemy) then
		self:_endTurn(b, events)
	end
	b.Turn += 1
	return events
end

function BattleService:_finish(player: Player, b: any, won: boolean)
	self._battles[player] = nil
	local profile = self.PlayerData.Get(player)
	if not profile then
		return { Result = if won then "Win" else "Lose" }
	end
	local data = profile.Data
	if not won then
		data.Battles.Losses += 1
		self.PlayerData.MarkDirty(player, "All")
		return { Result = "Lose" }
	end
	local now = self.Now()
	local coins, xp
	if b.Kind == "Wild" then
		coins, xp = Battle.WildReward(b.Enemy[1].Record), Battle.WildXP
		self._wildBeaten[player] = self._wildBeaten[player] or {}
		self._wildBeaten[player][b.SpotId] = now
	elseif b.Practice then
		-- Rematch while the trainer's reward is cooling down: a little XP only.
		coins, xp = 0, Battle.WildXP
	else
		coins, xp = Trainers.ById[b.SpotId].Reward, Battle.TrainerXP
		data.TrainerWins[b.SpotId] = now
	end
	-- First win over a biome's boss: its Badge and a bonus prize.
	local badge = nil
	local tr = b.Kind == "Trainer" and Trainers.ById[b.SpotId]
	if tr and tr.Boss and not data.Badges[tr.Biome] then
		data.Badges[tr.Biome] = now
		coins += tr.Reward * Trainers.BadgeBonusMultiplier
		xp += Battle.TrainerXP
		badge = tr.Biome
	end
	data.Coins += coins
	data.Battles.Wins += 1
	RewardsService.Bump(data, "BattleWin", 1, now)
	if b.Kind == "Trainer" then
		RewardsService.Bump(data, "TrainerWin", 1, now)
	end
	local levels = EconomyService.AddXP(data, xp)
	self.PlayerData.MarkDirty(player, "All")
	return { Result = "Win", Coins = coins, XP = xp, LevelsGained = levels, NewLevel = data.Level, Badge = badge }
end

-- action: { Type = "Move", Index = n } | { Type = "Switch", To = n } | { Type = "Run" }
function BattleService:Act(player: Player, battleId: any, action: any)
	local b = self._battles[player]
	if not b or b.Id ~= battleId then
		return { Ok = false, Error = "NoBattle" }
	end
	b.LastActive = self.Now()
	if b.Kind == "PvP" then
		return self:_pvpAct(player, b, action)
	end
	local act = cleanAction(b, "P", action)
	if not act then
		return { Ok = false, Error = "BadRequest" }
	end
	if act.Type == "Run" then
		self._battles[player] = nil
		return { Ok = true, Events = { { Kind = "Run" } }, Result = "Ran" }
	end
	local foeAct = if b.Kind == "Trainer" then self:_trainerAction(b) else self:_autoAction(b, "E")
	local events = self:_resolve(b, act, foeAct)

	local result = nil
	if allFainted(b.Enemy) then
		result = self:_finish(player, b, true)
	elseif allFainted(b.Team) or b.Turn >= Battle.MaxTurns then
		result = self:_finish(player, b, false)
	end
	local resp = { Ok = true, Events = events, Battle = self:View(b) }
	if result then
		for k, v in result do
			resp[k] = v
		end
	end
	return resp
end

-- ===== Player vs player =====
-- A challenges B (standing close); B accepts within ChallengeSeconds. Both
-- pick a move each turn; when both have chosen (or the turn timer runs out and
-- the computer picks for whoever hasn't), the turn is played and pushed to both
-- through self.Push(player, message). In the shared battle A is side "P" and B
-- is side "E"; B's views and events are flipped so each sees themself as "P".
-- Leaving or running away forfeits. The winner earns a small prize, at most
-- once per opponent per PvPRewardCooldown (so friends can't farm coins).
BattleService.ChallengeSeconds = 20
BattleService.ChallengeDistance = 40
BattleService.PvPTurnSeconds = 30
BattleService.PvPReward = 50
BattleService.PvPXP = 20
BattleService.PvPRewardCooldown = 600

local function other(side: string): string
	return if side == "P" then "E" else "P"
end

local function flipEvents(events: { any }): { any }
	local out = {}
	for _, ev in events do
		local e = table.clone(ev)
		if e.Side then
			e.Side = other(e.Side)
		end
		table.insert(out, e)
	end
	return out
end

-- The battle as `side` sees it (side "E" = player B, flipped).
function BattleService:ViewFor(b: any, side: string)
	local v = self:View(b)
	if b.Kind == "PvP" then
		local me = if side == "P" then b.A else b.B
		local foe = if side == "P" then b.B else b.A
		v.Opponent = foe.DisplayName
		v.Me = me.DisplayName
		v.Title = if side == "P" then ("You challenged " .. foe.DisplayName .. "!") else (foe.DisplayName .. " challenged you!")
		v.TurnSeconds = BattleService.PvPTurnSeconds
		if side == "E" then
			v.Team, v.Enemy = v.Enemy, v.Team
			v.P, v.E = v.E, v.P
		end
	end
	return v
end

local function isBusy(self, player: Player): boolean
	return self._battles[player] ~= nil
end

function BattleService:Challenge(player: Player, target: any)
	if not self.IsPlayer(target) or target == player or target.Parent == nil then
		return { Ok = false, Error = "BadRequest" }
	end
	local mine, theirs = self.PlayerData.Get(player), self.PlayerData.Get(target)
	if not mine or not theirs then
		return { Ok = false, Error = "NotLoaded" }
	end
	if isBusy(self, player) then
		return { Ok = false, Error = "AlreadyBattling" }
	end
	if isBusy(self, target) then
		return { Ok = false, Error = "PlayerBusy" }
	end
	if #pickTeam(mine.Data) == 0 then
		return { Ok = false, Error = "NoMonsters" }
	end
	if #pickTeam(theirs.Data) == 0 then
		return { Ok = false, Error = "PlayerHasNoMonsters" }
	end
	local a, b = self.PositionOf(player), self.PositionOf(target)
	if a and b and (a - b).Magnitude > BattleService.ChallengeDistance then
		return { Ok = false, Error = "TooFar" }
	end
	local now = self.Now()
	local pending = self._challenges[target]
	if pending and pending.From ~= player and now - pending.At < BattleService.ChallengeSeconds then
		return { Ok = false, Error = "PlayerBusy" }
	end
	self._challenges[target] = { From = player, At = now }
	self.Push(target, { Kind = "Challenge", FromUserId = player.UserId, FromName = player.DisplayName, Seconds = BattleService.ChallengeSeconds })
	return { Ok = true, Seconds = BattleService.ChallengeSeconds }
end

function BattleService:Respond(player: Player, fromUserId: any, accept: any)
	local c = self._challenges[player]
	local now = self.Now()
	if not c or c.From.UserId ~= fromUserId or now - c.At >= BattleService.ChallengeSeconds or c.From.Parent == nil then
		self._challenges[player] = nil
		return { Ok = false, Error = "ChallengeGone" }
	end
	self._challenges[player] = nil
	local from = c.From
	if accept ~= true then
		self.Push(from, { Kind = "Declined", Name = player.DisplayName })
		return { Ok = true }
	end
	if isBusy(self, player) or isBusy(self, from) then
		return { Ok = false, Error = "PlayerBusy" }
	end
	local fromProfile, myProfile = self.PlayerData.Get(from), self.PlayerData.Get(player)
	if not fromProfile or not myProfile then
		return { Ok = false, Error = "NotLoaded" }
	end
	local teamA, teamB = pickTeam(fromProfile.Data), pickTeam(myProfile.Data)
	if #teamA == 0 or #teamB == 0 then
		return { Ok = false, Error = "NoMonsters" }
	end
	local b = {
		Id = HttpService:GenerateGUID(false),
		Kind = "PvP",
		A = from,
		B = player,
		Team = {},
		Enemy = {},
		P = 1,
		E = 1,
		Turn = 0,
		Pending = {},
		Deadline = now + BattleService.PvPTurnSeconds,
		LastActive = now,
	}
	for _, rec in teamA do
		table.insert(b.Team, combatant(rec))
	end
	for _, rec in teamB do
		table.insert(b.Enemy, combatant(rec))
	end
	self._battles[from] = b
	self._battles[player] = b
	self.Push(from, { Kind = "Start", Battle = self:ViewFor(b, "P") })
	self.Push(player, { Kind = "Start", Battle = self:ViewFor(b, "E") })
	return { Ok = true }
end

function BattleService:_pvpAct(player: Player, b: any, action: any)
	local side = if player == b.A then "P" else "E"
	local act = cleanAction(b, side, action)
	if not act then
		return { Ok = false, Error = "BadRequest" }
	end
	if act.Type == "Run" then
		self:_pvpEnd(b, other(side), { { Kind = "Forfeit", Side = side } })
		return { Ok = true, Waiting = true }
	end
	if b.Pending[side] then
		return { Ok = false, Error = "AlreadyChose" }
	end
	b.Pending[side] = act
	self.Push(if side == "P" then b.B else b.A, { Kind = "OpponentReady" })
	if b.Pending.P and b.Pending.E then
		self:_pvpTurn(b)
	end
	return { Ok = true, Waiting = true }
end

function BattleService:_pvpTurn(b: any)
	local events = self:_resolve(b, b.Pending.P, b.Pending.E)
	b.Pending = {}
	b.Deadline = self.Now() + BattleService.PvPTurnSeconds
	local winner = nil
	if allFainted(b.Enemy) then
		winner = "P"
	elseif allFainted(b.Team) then
		winner = "E"
	elseif b.Turn >= Battle.MaxTurns then
		winner = if totalHP(b.Team) >= totalHP(b.Enemy) then "P" else "E"
	end
	if winner then
		self:_pvpEnd(b, winner, events)
		return
	end
	self.Push(b.A, { Kind = "Turn", Events = events, Battle = self:ViewFor(b, "P") })
	self.Push(b.B, { Kind = "Turn", Events = flipEvents(events), Battle = self:ViewFor(b, "E") })
end

function BattleService:_pvpEnd(b: any, winnerSide: string, events: { any })
	if self._battles[b.A] == b then
		self._battles[b.A] = nil
	end
	if self._battles[b.B] == b then
		self._battles[b.B] = nil
	end
	local now = self.Now()
	for _, side in { "P", "E" } do
		local player = if side == "P" then b.A else b.B
		local foe = if side == "P" then b.B else b.A
		local won = side == winnerSide
		local msg = {
			Kind = "Turn",
			Events = if side == "P" then events else flipEvents(events),
			Battle = self:ViewFor(b, side),
			Result = if won then "Win" else "Lose",
			Coins = 0,
			XP = 0,
		}
		local profile = self.PlayerData.Get(player)
		if profile then
			local data = profile.Data
			if won then
				data.Battles.PvPWins = (data.Battles.PvPWins or 0) + 1
				RewardsService.Bump(data, "BattleWin", 1, now)
				self._pvpPaid[player] = self._pvpPaid[player] or {}
				local last = self._pvpPaid[player][foe.UserId]
				if not last or now - last >= BattleService.PvPRewardCooldown then
					self._pvpPaid[player][foe.UserId] = now
					data.Coins += BattleService.PvPReward
					msg.Coins, msg.XP = BattleService.PvPReward, BattleService.PvPXP
					msg.LevelsGained = EconomyService.AddXP(data, BattleService.PvPXP)
					msg.NewLevel = data.Level
				end
			else
				data.Battles.PvPLosses = (data.Battles.PvPLosses or 0) + 1
			end
			self.PlayerData.MarkDirty(player, "All")
		end
		if player.Parent then
			self.Push(player, msg)
		end
	end
end

-- Called about once a second: plays PvP turns whose timer ran out (the computer
-- picks for whoever didn't choose) and drops stale challenges.
function BattleService:Tick()
	local now = self.Now()
	local seen = {}
	for _, b in self._battles do
		if b.Kind == "PvP" and not seen[b] then
			seen[b] = true
			if now >= b.Deadline then
				for _, side in { "P", "E" } do
					if not b.Pending[side] then
						b.Pending[side] = self:_autoAction(b, side)
					end
				end
				self:_pvpTurn(b)
			end
		end
	end
	for target, c in self._challenges do
		if now - c.At >= BattleService.ChallengeSeconds then
			self._challenges[target] = nil
		end
	end
end

function BattleService:Forget(player: Player)
	local b = self._battles[player]
	if b and b.Kind == "PvP" then
		local side = if player == b.A then "P" else "E"
		self:_pvpEnd(b, other(side), { { Kind = "Forfeit", Side = side } })
	end
	self._battles[player] = nil
	self._wildBeaten[player] = nil
	self._challenges[player] = nil
	self._pvpPaid[player] = nil
	for target, c in self._challenges do
		if c.From == player then
			self._challenges[target] = nil
		end
	end
end

return BattleService
