-- Monster fusion (rules in Shared/Fusion): two owned, unlocked monsters of
-- different species from the same biome are used up to make one new monster of
-- that biome's third species. The result is rolled server-side exactly like an
-- incubation in that biome (current events apply), so the advertised odds hold.
-- A retry after success fails with NotOwned (the inputs are gone), so a fusion
-- can never be applied twice.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.MonsterFactory.Shared.Config)
local Registry = require(ReplicatedStorage.MonsterFactory.Shared.Registry)
local Fusion = require(ReplicatedStorage.MonsterFactory.Shared.Fusion)
local ProgressionService = require(script.Parent.ProgressionService)
local DiscoveryService = require(script.Parent.DiscoveryService)
local EconomyService = require(script.Parent.EconomyService)
local RewardsService = require(script.Parent.RewardsService)

local FusionService = {}
FusionService.__index = FusionService

function FusionService.new(deps)
	local self = setmetatable({}, FusionService)
	self.PlayerData = deps.PlayerData
	self.Generation = deps.Generation
	self.Mutation = deps.Mutation
	self.Economy = deps.Economy
	self.Incubation = deps.Incubation -- for the biome's live event set
	self.Rng = Random.new()
	self.Now = os.time
	return self
end

local function isId(x: any): boolean
	return type(x) == "string" and #x > 0 and #x <= 64
end

-- preview = true only checks and prices it (nothing changes).
function FusionService:Fuse(player: Player, idA: any, idB: any, preview: any)
	local profile = self.PlayerData.Get(player)
	if not profile then
		return { Ok = false, Error = "NotLoaded" }
	end
	local data = profile.Data
	if not isId(idA) or not isId(idB) or idA == idB then
		return { Ok = false, Error = "BadRequest" }
	end
	local a, b = data.Monsters[idA], data.Monsters[idB]
	if not a or not b then
		return { Ok = false, Error = "NotOwned" }
	end
	if data.Locked[idA] or data.Locked[idB] then
		return { Ok = false, Error = "Locked" }
	end
	local resultId, why = Fusion.ResultFor(a.SpeciesId, b.SpeciesId)
	if not resultId then
		return { Ok = false, Error = why }
	end
	local cost = Fusion.Cost(resultId)
	local guaranteed = a.RarityTier >= Fusion.GuaranteeTier and b.RarityTier >= Fusion.GuaranteeTier
	if preview == true then
		return { Ok = true, Preview = true, SpeciesId = resultId, Cost = cost, Guaranteed = guaranteed }
	end
	if data.Coins < cost then
		return { Ok = false, Error = "NotEnoughCoins" }
	end

	local biomeId = Registry.Species.ById[resultId].HomeBiome
	local ctx = {
		SpeciesId = resultId,
		BiomeId = biomeId,
		Catalysts = {},
		Events = self.Incubation:ActiveEventSet(biomeId),
		Research = table.clone(data.Research),
		Progression = data.Level,
		TierModifiers = ProgressionService.TierModifiers(data),
	}
	local ok, verr = self.Mutation:Resolve(ctx)
	if not ok then
		return { Ok = false, Error = verr }
	end
	local now = self.Now()
	local record, roll = self.Generation:Generate(player.UserId, ctx, self.Rng, { OriginMethod = "Fusion", Pity = guaranteed, Now = now })
	if not record then
		return { Ok = false, Error = roll }
	end

	-- Commit: pay, use up both monsters (freeing any pet slots), add the result.
	data.Coins -= cost
	data.Monsters[idA] = nil
	data.Monsters[idB] = nil
	local wasPet = false
	for _, id in { idA, idB } do
		local slot = table.find(data.Equipped, id)
		if slot then
			table.remove(data.Equipped, slot)
			wasPet = true
		end
	end
	data.Monsters[record.MonsterId] = record
	local discovery = DiscoveryService.Register(data, record, now)
	-- Daily quest progress.
	RewardsService.Bump(data, "Fuse", 1, now)
	if #discovery.NewMutations > 0 then
		RewardsService.Bump(data, "Discover", #discovery.NewMutations, now)
	end
	data.Coins += discovery.Coins
	local newCount = #discovery.NewMutations + (if discovery.NewSpecies then 1 else 0)
	local rp = ProgressionService.ResearchPointsFor(record, newCount)
	data.ResearchPoints += rp
	local xp = Config.XPByTier[record.RarityTier] or 0
	local levels = EconomyService.AddXP(data, xp)
	data.Stats.Fusions = (data.Stats.Fusions or 0) + 1

	local milestoneNames = {}
	for _, m in discovery.Milestones do
		table.insert(milestoneNames, { Name = m.Name, Reward = m.Reward })
	end
	self.Economy:InvalidateIncome(player)
	if wasPet then
		self.Economy:PublishEquipped(player)
	end
	self.PlayerData.MarkDirty(player, "All")
	task.spawn(self.PlayerData.Save, player, false)
	return {
		Ok = true,
		Record = record,
		Cost = cost,
		PityUsed = roll.PityUsed == true,
		NewSpecies = discovery.NewSpecies,
		NewMutations = discovery.NewMutations,
		Milestones = milestoneNames,
		RewardCoins = discovery.Coins,
		XP = xp,
		ResearchPoints = rp,
		LevelsGained = levels,
		NewLevel = data.Level,
	}
end

return FusionService
