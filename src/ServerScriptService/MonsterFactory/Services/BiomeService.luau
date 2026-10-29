-- Biome unlocks and species availability. Unlocks combine level, discoveries and
-- coins (never coins alone) and are permanent.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.MonsterFactory.Shared.Config)
local Registry = require(ReplicatedStorage.MonsterFactory.Shared.Registry)

local BiomeService = {}
BiomeService.__index = BiomeService

function BiomeService.new(deps: { PlayerData: any })
	local self = setmetatable({}, BiomeService)
	self.PlayerData = deps.PlayerData
	return self
end

local function countKeys(t: { [any]: any }): number
	local n = 0
	for _ in t do
		n += 1
	end
	return n
end

-- Requirement checklist for a biome: (allMet, { { Id, Label, Have, Need, Met } }).
function BiomeService.GetRequirements(data: any, biomeId: string)
	local biome = Registry.Biomes.ById[biomeId]
	local u = biome.Unlock
	local reqs = {
		{ Id = "Level", Label = "Reach level " .. u.Level, Have = data.Level, Need = u.Level },
		{ Id = "Mutations", Label = "Discover " .. u.MutationsDiscovered .. " mutations", Have = countKeys(data.Discoveries.Mutations), Need = u.MutationsDiscovered },
		{ Id = "Coins", Label = "Pay " .. u.Coins .. " coins", Have = math.floor(data.Coins), Need = u.Coins },
	}
	local all = true
	for _, r in reqs do
		r.Met = r.Have >= r.Need
		all = all and r.Met
	end
	return all, reqs
end

-- A species is available once its home biome is unlocked and the level is reached.
function BiomeService.IsSpeciesAvailable(data: any, speciesId: string): (boolean, string?)
	local sp = Registry.Species.ById[speciesId]
	local cfg = Config.Species[speciesId]
	if not sp or not cfg then
		return false, "SpeciesUnavailable"
	end
	if not data.UnlockedBiomes[sp.HomeBiome] then
		return false, "SpeciesBiomeLocked"
	end
	if data.Level < cfg.UnlockLevel then
		return false, "SpeciesLocked"
	end
	return true, nil
end

function BiomeService:Unlock(player: Player, biomeId: any)
	local profile = self.PlayerData.Get(player)
	if not profile then
		return { Ok = false, Error = "NotLoaded" }
	end
	if type(biomeId) ~= "string" or not Registry.Biomes.ById[biomeId] then
		return { Ok = false, Error = "UnknownBiome" }
	end
	local data = profile.Data
	if data.UnlockedBiomes[biomeId] then
		return { Ok = true, AlreadyUnlocked = true }
	end
	local met, reqs = BiomeService.GetRequirements(data, biomeId)
	if not met then
		return { Ok = false, Error = "RequirementsNotMet", Requirements = reqs }
	end
	data.Coins -= Registry.Biomes.ById[biomeId].Unlock.Coins
	data.UnlockedBiomes[biomeId] = true
	self.PlayerData.MarkDirty(player, "All")
	task.spawn(self.PlayerData.Save, player, false)
	return { Ok = true }
end

return BiomeService
