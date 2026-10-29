--!strict
-- Turns a mutation roll into a compact, persistable monster record.
-- Visual properties are NOT stored: they are derived from mutation definitions.

local HttpService = game:GetService("HttpService")

local MonsterGenerationService = {}
MonsterGenerationService.__index = MonsterGenerationService

MonsterGenerationService.RECORD_VERSION = 1
-- Caps on summed gameplay modifiers so stacking can never run away.
MonsterGenerationService.CAPS = { Power = 20, IncomeRate = 0.5, ResearchValue = 1.0 }
-- Mutations at or above this tier prefix the display name ("Thornbound Mossling").
MonsterGenerationService.NAME_PREFIX_TIER = 3

export type MonsterRecord = {
	V: number,
	MonsterId: string,
	SpeciesId: string,
	DisplayName: string,
	Generation: number,
	CreationTimestamp: number,
	OriginBiome: string,
	OriginMethod: string,
	OwnerUserId: number,
	PrimaryElement: string,
	SecondaryElement: string?,
	Genes: { [string]: any },
	ActiveMutations: { string },
	RarityTier: number,
	SpeciesRarity: number,
	Stats: { Power: number, IncomeRate: number, ResearchValue: number },
	HybridRecipe: string?, -- recipe that produced the Hybrid mutation, if any
}

function MonsterGenerationService.new(registry: any, mutationService: any)
	local self = setmetatable({}, MonsterGenerationService)
	self.Registry = registry
	self.MutationService = mutationService
	return self
end

local function round(x: number, places: number): number
	local m = 10 ^ places
	return math.floor(x * m + 0.5) / m
end

function MonsterGenerationService:ComputeStats(species: any, mutationIds: { string })
	local caps = MonsterGenerationService.CAPS
	local add = { Power = 0, IncomeRate = 0, ResearchValue = 0 }
	for _, id in mutationIds do
		local m = self.Registry.Mutations.ById[id]
		for stat, v in (m and m.GameplayModifiers) or {} do
			if add[stat] ~= nil then
				add[stat] += v
			end
		end
	end
	local base = species.BaseStats
	return {
		Power = base.Power + math.min(add.Power, caps.Power),
		IncomeRate = round(base.IncomeRate * (1 + math.min(add.IncomeRate, caps.IncomeRate)), 4),
		ResearchValue = round(base.ResearchValue * (1 + math.min(add.ResearchValue, caps.ResearchValue)), 4),
	}
end

-- Builds genes from the species and picked mutations.
function MonsterGenerationService:BuildGenes(species: any, mutations: { any }, rng: Random)
	local genes = {
		BodyType = species.BodyType,
		BaseColorGene = species.Palettes[rng:NextInteger(1, #species.Palettes)],
		SizeGene = round(rng:NextNumber(species.SizeRange[1], species.SizeRange[2]), 2),
		PatternGene = "None",
		EyeGene = "Default",
		HornGene = "None",
		TailGene = if species.Attachments.Tail then "Default" else "None",
		AuraGene = "None",
	}
	for _, m in mutations do
		if m.Category == "Pattern" then
			genes.PatternGene = m.Id
		elseif m.Category == "Aura" then
			genes.AuraGene = m.Id
		elseif m.ExclusiveGroup == "Eyes" then
			genes.EyeGene = m.Id
		elseif m.ExclusiveGroup == "HeadTop" then
			genes.HornGene = m.Id
		elseif m.RequiredAttachment == "Tail" then
			genes.TailGene = m.Id
		end
	end
	return genes
end

-- opts: { OriginMethod: string?, Now: number?, MonsterId: string?, Pity: boolean? }
-- Returns (record, rollResult) or (nil, error).
function MonsterGenerationService:Generate(ownerUserId: number, ctx: any, rng: Random, opts: { [string]: any }?)
	if type(ownerUserId) ~= "number" then
		return nil, "BadOwner"
	end
	opts = opts or {}
	local roll, err = self.MutationService:Roll(ctx, rng, { Pity = (opts :: any).Pity == true })
	if not roll then
		return nil, err
	end
	local species = roll.Resolved.Species
	local ids = {}
	local topTier, topMutation = 1, nil
	local secondary = nil
	for _, m in roll.Mutations do
		table.insert(ids, m.Id)
		if m.RarityTier > topTier or (m.RarityTier == topTier and topMutation == nil) then
			topTier, topMutation = m.RarityTier, m
		end
		if m.Category == "Elemental" and m.Element and m.Element ~= species.PrimaryElement then
			secondary = m.Element
		end
	end
	local name = species.DisplayName
	if topMutation and topMutation.RarityTier >= MonsterGenerationService.NAME_PREFIX_TIER then
		name = topMutation.DisplayName .. " " .. name
	end
	local record: MonsterRecord = {
		V = MonsterGenerationService.RECORD_VERSION,
		MonsterId = (opts :: any).MonsterId or HttpService:GenerateGUID(false),
		SpeciesId = species.Id,
		DisplayName = name,
		Generation = 1,
		CreationTimestamp = (opts :: any).Now or os.time(),
		OriginBiome = roll.Resolved.Biome.Id,
		OriginMethod = (opts :: any).OriginMethod or "Incubation",
		OwnerUserId = ownerUserId,
		PrimaryElement = species.PrimaryElement,
		SecondaryElement = secondary,
		Genes = self:BuildGenes(species, roll.Mutations, rng),
		ActiveMutations = ids,
		RarityTier = if #ids > 0 then topTier else 1,
		SpeciesRarity = species.SpeciesRarity,
		Stats = self:ComputeStats(species, ids),
		HybridRecipe = roll.RecipeId,
	}
	return record, roll
end

-- Validates a record loaded from storage. Returns (true) or (false, reason).
function MonsterGenerationService:ValidateRecord(rec: any): (boolean, string?)
	if type(rec) ~= "table" then
		return false, "NotTable"
	end
	if rec.V ~= MonsterGenerationService.RECORD_VERSION then
		return false, "Version"
	end
	if type(rec.MonsterId) ~= "string" or #rec.MonsterId == 0 then
		return false, "MonsterId"
	end
	if not self.Registry.Species.ById[rec.SpeciesId] then
		return false, "Species"
	end
	if type(rec.ActiveMutations) ~= "table" then
		return false, "Mutations"
	end
	local seen = {}
	for _, id in rec.ActiveMutations do
		if not self.Registry.Mutations.ById[id] or seen[id] then
			return false, "Mutations"
		end
		seen[id] = true
	end
	if not self.Registry.Rarity.IsValid(rec.RarityTier) then
		return false, "Rarity"
	end
	return true, nil
end

return MonsterGenerationService
