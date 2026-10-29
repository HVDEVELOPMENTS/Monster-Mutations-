--!strict
-- Collection index bookkeeping: first discoveries, NEW badges and milestones.
-- Operates directly on a player's data table; the caller marks it dirty.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.MonsterFactory.Shared.Config)
local Registry = require(ReplicatedStorage.MonsterFactory.Shared.Registry)

local DiscoveryService = {}

local function count(t: { [any]: any }): number
	local n = 0
	for _ in t do
		n += 1
	end
	return n
end

-- Registers a newly claimed monster. Returns { NewSpecies, NewMutations = { id }, Milestones = { def }, Coins }.
function DiscoveryService.Register(data: any, record: any, now: number)
	local result = { NewSpecies = false, NewMutations = {}, Milestones = {}, Coins = 0 }
	local disc = data.Discoveries
	if not disc.Species[record.SpeciesId] then
		disc.Species[record.SpeciesId] = now
		data.Unseen["Species:" .. record.SpeciesId] = true
		result.NewSpecies = true
		result.Coins += Config.SpeciesDiscoveryReward
	end
	for _, id in record.ActiveMutations do
		if not disc.Mutations[id] then
			disc.Mutations[id] = now
			data.Unseen["Mutation:" .. id] = true
			table.insert(result.NewMutations, id)
			local tier = Registry.Mutations.ById[id].RarityTier
			result.Coins += Config.DiscoveryReward[tier] or 0
		end
	end
	local mutationCount = count(disc.Mutations)
	local speciesCount = count(disc.Species)
	local function hasBiomeMutation(biomeId: string): boolean
		for id in disc.Mutations do
			local allowed = Registry.Mutations.ById[id] and Registry.Mutations.ById[id].AllowedBiomes
			if allowed and table.find(allowed, biomeId) then
				return true
			end
		end
		return false
	end
	for _, m in Config.Milestones do
		if not data.Milestones[m.Id] then
			local reached = (m.Kind == "MutationCount" and mutationCount >= m.Value)
				or (m.Kind == "SpeciesCount" and speciesCount >= m.Value)
				or (m.Kind == "TierReached" and record.RarityTier >= m.Value)
				or (m.Kind == "BiomeMutation" and hasBiomeMutation(m.Value))
			if reached then
				data.Milestones[m.Id] = now
				table.insert(result.Milestones, m)
				result.Coins += m.Reward
			end
		end
	end
	return result
end

-- Clears a NEW badge. Returns true if the key was valid.
function DiscoveryService.MarkSeen(data: any, seenKey: any): boolean
	if type(seenKey) ~= "string" or #seenKey > 80 then
		return false
	end
	if data.Unseen[seenKey] then
		data.Unseen[seenKey] = nil
		return true
	end
	return false
end

return DiscoveryService
