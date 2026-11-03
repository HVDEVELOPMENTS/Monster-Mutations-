-- Incubation chamber: one egg per unlocked egg slot (more slots at higher levels,
-- Config.EggSlotLevels). Each outcome is rolled and saved when incubation STARTS
-- (the "stabilisation" point), then revealed on claim. Disconnecting or retrying
-- can never reroll or duplicate it:
--   * Start is idempotent per client RequestId (recent ids remembered in save data).
--   * Claim is idempotent per OpId (last claim response remembered in save data).
--   * Completion time is a saved server timestamp; the client never reports it.

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.MonsterFactory.Shared.Config)
local Registry = require(ReplicatedStorage.MonsterFactory.Shared.Registry)
local Events = require(ReplicatedStorage.MonsterFactory.Shared.Events)
local BiomeService = require(script.Parent.BiomeService)
local ProgressionService = require(script.Parent.ProgressionService)
local DiscoveryService = require(script.Parent.DiscoveryService)
local EconomyService = require(script.Parent.EconomyService)
local RewardsService = require(script.Parent.RewardsService)

local IncubationService = {}
IncubationService.__index = IncubationService

local MAX_RECENT_STARTS = 10

function IncubationService.new(deps)
	local self = setmetatable({}, IncubationService)
	self.PlayerData = deps.PlayerData
	self.Generation = deps.Generation
	self.Mutation = deps.Mutation
	self.Economy = deps.Economy
	self.Rng = Random.new()
	self.Now = os.time -- overridable in tests
	return self
end

local function isId(x: any): boolean
	return type(x) == "string" and #x > 0 and #x <= 64
end

-- Validates a client selection against the player's data. Returns (ctx, nil) or (nil, error).
function IncubationService:BuildContext(data: any, payload: any)
	if type(payload) ~= "table" or not isId(payload.SpeciesId) or not isId(payload.BiomeId) then
		return nil, "BadRequest"
	end
	local biome = Registry.Biomes.ById[payload.BiomeId]
	if not biome or not data.UnlockedBiomes[payload.BiomeId] then
		return nil, "BiomeLocked"
	end
	-- Any available species may incubate in any unlocked biome (cross-biome experiments).
	local available, why = BiomeService.IsSpeciesAvailable(data, payload.SpeciesId)
	if not available then
		return nil, why
	end
	local catalysts = payload.Catalysts or {}
	if type(catalysts) ~= "table" or #catalysts > Registry.Materials.MaxPerIncubation then
		return nil, "BadCatalysts"
	end
	local clean = {}
	for i, id in catalysts do
		if type(i) ~= "number" or not isId(id) then
			return nil, "BadCatalysts"
		end
		table.insert(clean, id)
	end
	return {
		SpeciesId = payload.SpeciesId,
		BiomeId = payload.BiomeId,
		Catalysts = clean,
		Events = self:ActiveEventSet(payload.BiomeId),
		Research = table.clone(data.Research),
		Progression = data.Level,
		TierModifiers = ProgressionService.TierModifiers(data),
	}, nil
end

-- Server-clock event state for a biome: { [eventId] = true }.
function IncubationService:ActiveEventSet(biomeId: string)
	local set = {}
	for id in Events.GetActive(biomeId, self.Now()) do
		set[id] = true
	end
	return set
end

-- Public (client-safe) view of one egg. The rolled record stays hidden until claimed.
function IncubationService:PublicEgg(inc: any)
	return {
		OpId = inc.OpId,
		SpeciesId = inc.SpeciesId,
		BiomeId = inc.BiomeId,
		StartedAt = inc.StartedAt,
		EndsAt = inc.EndsAt,
		Ready = self.Now() >= inc.EndsAt,
	}
end

-- Every egg in the chamber, oldest first.
function IncubationService:PublicState(data: any)
	local eggs = {}
	for _, inc in data.Incubations do
		table.insert(eggs, self:PublicEgg(inc))
	end
	return eggs
end

function IncubationService:PityActive(data: any): boolean
	return data.PityCounter >= Config.PityThreshold - 1
end

function IncubationService:GetOdds(player: Player, payload: any)
	local profile = self.PlayerData.Get(player)
	if not profile then
		return { Ok = false, Error = "NotLoaded" }
	end
	local ctx, err = self:BuildContext(profile.Data, payload)
	if not ctx then
		return { Ok = false, Error = err }
	end
	local report, rerr = self.Mutation:GetOddsReport(ctx)
	if not report then
		return { Ok = false, Error = rerr }
	end
	return { Ok = true, Report = report, PityActive = self:PityActive(profile.Data) }
end

function IncubationService:Start(player: Player, payload: any)
	local profile = self.PlayerData.Get(player)
	if not profile then
		return { Ok = false, Error = "NotLoaded" }
	end
	local data = profile.Data
	if type(payload) ~= "table" or not isId(payload.RequestId) then
		return { Ok = false, Error = "BadRequest" }
	end
	for _, s in data.RecentStarts do
		if s.RequestId == payload.RequestId then
			-- Retry of a request we already processed: report the same egg, charge nothing.
			for _, inc in data.Incubations do
				if inc.OpId == s.OpId then
					return { Ok = true, Duplicate = true, Incubation = self:PublicEgg(inc), Incubations = self:PublicState(data) }
				end
			end
			return { Ok = true, Duplicate = true, Incubations = self:PublicState(data) }
		end
	end
	if #data.Incubations >= ProgressionService.EggSlots(data) then
		return { Ok = false, Error = "ChamberBusy" }
	end
	local count = 0
	for _ in data.Monsters do
		count += 1
	end
	if count >= Config.MaxMonsters then
		return { Ok = false, Error = "MonsterStorageFull" }
	end
	local ctx, err = self:BuildContext(data, payload)
	if not ctx then
		return { Ok = false, Error = err }
	end
	local ok, verr = self.Mutation:Resolve(ctx)
	if not ok then
		return { Ok = false, Error = verr }
	end
	for _, id in ctx.Catalysts do
		if (data.Inventory[id] or 0) < 1 then
			return { Ok = false, Error = "MissingCatalyst" }
		end
	end
	local cost = Config.Species[ctx.SpeciesId].Cost
	if data.Coins < cost then
		return { Ok = false, Error = "NotEnoughCoins" }
	end

	local pity = self:PityActive(data)
	local record, roll = self.Generation:Generate(player.UserId, ctx, self.Rng, { OriginMethod = "Incubation", Pity = pity, Now = self.Now() })
	if not record then
		return { Ok = false, Error = roll }
	end

	-- Commit: charge, consume catalysts (Catalyst Recycler may keep some), store the hidden result.
	data.Coins -= cost
	local recycleChance = ProgressionService.RecycleChance(data)
	local recycled = {}
	for _, id in ctx.Catalysts do
		if recycleChance > 0 and self.Rng:NextNumber() < recycleChance then
			table.insert(recycled, id)
		else
			data.Inventory[id] -= 1
			if data.Inventory[id] <= 0 then
				data.Inventory[id] = nil
			end
		end
	end
	local now = self.Now()
	local inc = {
		OpId = HttpService:GenerateGUID(false),
		RequestId = payload.RequestId,
		SpeciesId = ctx.SpeciesId,
		BiomeId = ctx.BiomeId,
		Catalysts = ctx.Catalysts,
		Events = ctx.Events,
		StartedAt = now,
		EndsAt = now + ProgressionService.IncubationSeconds(data),
		Record = record,
		PityUsed = roll.PityUsed,
	}
	table.insert(data.Incubations, inc)
	-- Pity counts at the roll (not the claim), so eggs waiting in other slots
	-- can never all be pity eggs.
	if record.RarityTier >= 3 then
		data.PityCounter = 0
	else
		data.PityCounter += 1
	end
	table.insert(data.RecentStarts, { RequestId = payload.RequestId, OpId = inc.OpId })
	while #data.RecentStarts > MAX_RECENT_STARTS do
		table.remove(data.RecentStarts, 1)
	end
	data.Stats.Incubations += 1
	self.PlayerData.MarkDirty(player, "All")
	task.spawn(self.PlayerData.Save, player, false)
	return { Ok = true, Incubation = self:PublicEgg(inc), Incubations = self:PublicState(data), Recycled = recycled }
end

function IncubationService:Claim(player: Player, opId: any)
	local profile = self.PlayerData.Get(player)
	if not profile then
		return { Ok = false, Error = "NotLoaded" }
	end
	local data = profile.Data
	if not isId(opId) then
		return { Ok = false, Error = "BadRequest" }
	end
	if data.LastClaim and data.LastClaim.OpId == opId then
		local resp = table.clone(data.LastClaim.Response)
		resp.Duplicate = true
		return resp
	end
	local slot, inc = nil, nil
	for i, egg in data.Incubations do
		if egg.OpId == opId then
			slot, inc = i, egg
			break
		end
	end
	if not inc then
		return { Ok = false, Error = "NoSuchIncubation" }
	end
	if self.Now() < inc.EndsAt then
		return { Ok = false, Error = "NotReady", EndsAt = inc.EndsAt }
	end

	local record = inc.Record
	local now = self.Now()
	data.Monsters[record.MonsterId] = record
	table.remove(data.Incubations, slot)
	local discovery = DiscoveryService.Register(data, record, now)
	-- Daily quest progress.
	RewardsService.Bump(data, "Hatch", 1, now)
	if record.RarityTier >= 3 then
		RewardsService.Bump(data, "HatchRare", 1, now)
	end
	if #discovery.NewMutations > 0 then
		RewardsService.Bump(data, "Discover", #discovery.NewMutations, now)
	end
	data.Coins += discovery.Coins
	local newCount = #discovery.NewMutations + (if discovery.NewSpecies then 1 else 0)
	local rp = ProgressionService.ResearchPointsFor(record, newCount)
	data.ResearchPoints += rp
	-- First monster ever: equip it automatically so the follower shows up.
	local autoEquipped = false
	if #data.Equipped == 0 then
		table.insert(data.Equipped, record.MonsterId)
		autoEquipped = true
	end
	local xp = Config.XPByTier[record.RarityTier] or 0
	local levels = EconomyService.AddXP(data, xp)

	local milestoneNames = {}
	for _, m in discovery.Milestones do
		table.insert(milestoneNames, { Name = m.Name, Reward = m.Reward })
	end
	local response = {
		Ok = true,
		Record = record,
		PityUsed = inc.PityUsed == true,
		NewSpecies = discovery.NewSpecies,
		NewMutations = discovery.NewMutations,
		Milestones = milestoneNames,
		RewardCoins = discovery.Coins,
		XP = xp,
		ResearchPoints = rp,
		AutoEquipped = autoEquipped,
		LevelsGained = levels,
		NewLevel = data.Level,
	}
	data.LastClaim = { OpId = opId, Response = response }
	self.Economy:InvalidateIncome(player)
	if autoEquipped then
		self.Economy:PublishEquipped(player)
	end
	self.PlayerData.MarkDirty(player, "All")
	task.spawn(self.PlayerData.Save, player, false)
	return response
end

return IncubationService
