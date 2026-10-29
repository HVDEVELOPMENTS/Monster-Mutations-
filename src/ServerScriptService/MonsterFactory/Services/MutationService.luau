--!strict
-- Server-authoritative mutation probability engine.
--
-- Roll model, per category (in Categories order):
--   1. Slot fill:   slot 1 fills with FillChance; extra slots with ExtraSlotFillChance
--                   (only while the previous slot filled).
--   2. Tier roll:   P(tier) = Chance[tier] * TierMultiplier, renormalised over all tiers.
--                   TierMultiplier = catalyst effects for that category x context
--                   TierModifiers (e.g. upgrades, which apply to every category).
--   3. Pick:        weighted pick among *eligible* mutations of that category+tier.
--                   EffectiveWeight = BaseWeight * Biome * Catalyst * Event * Affinity (clamped).
--                   Active biome events also shift environment variables before
--                   Environment rules are checked.
--                   No eligible mutation at the rolled tier -> slot stays empty.
-- Already-chosen mutations, taken exclusive groups and incompatibilities are
-- removed from the pool before the pick, so a duplicate can never be rolled.
--
-- Hybrids (after all rolled categories): each recipe in HybridRecipes priority order
-- whose inputs and conditions are all met rolls its Chance once (Chance 1 =
-- guaranteed); the first to succeed adds its output. At most one hybrid per monster.
--
-- Bad-luck protection (opts.Pity = true): the first category (in order) that has an
-- eligible mutation at PITY_TIER or above has its slot 1 force-filled, and its tier
-- roll is restricted to tiers >= PITY_TIER that have candidates (renormalised).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local WeightedRandom = require(ReplicatedStorage.MonsterFactory.Shared.WeightedRandom)

local MutationService = {}
MutationService.__index = MutationService

MutationService.AFFINITY_MULTIPLIER = 1.25
MutationService.MUTATION_MULT_MIN = 0.25
MutationService.MUTATION_MULT_MAX = 5
MutationService.TIER_MULT_MIN = 0.25
MutationService.TIER_MULT_MAX = 3
MutationService.PITY_TIER = 3

export type Context = {
	SpeciesId: string,
	BiomeId: string,
	Catalysts: { string }?,
	Events: { [string]: boolean }?,
	Research: { [string]: boolean }?,
	Progression: number?,
	TierModifiers: { { Tier: number, Multiplier: number, Source: string } }?,
}

type Resolved = {
	Species: any,
	Biome: any,
	CatalystSet: { [string]: boolean },
	CatalystDefs: { any },
	Events: { [string]: boolean },
	EventDefs: { any },
	Research: { [string]: boolean },
	Progression: number,
	Environment: { [string]: number },
	TierModifiers: { any },
}

local function contains(list: { string }?, value: string): boolean
	if not list then
		return false
	end
	return table.find(list, value) ~= nil
end

local function clamp(x: number, lo: number, hi: number): number
	return math.clamp(x, lo, hi)
end

function MutationService.new(registry: any)
	local self = setmetatable({}, MutationService)
	self.Registry = registry
	-- Index: [categoryId][tier] = { mutation }
	local index = {}
	for _, cat in registry.Categories.List do
		index[cat.Id] = {}
		for t = 1, registry.Rarity.Count do
			index[cat.Id][t] = {}
		end
	end
	for _, m in registry.Mutations.List do
		assert(index[m.Category], "unknown category on mutation " .. m.Id)
		assert(registry.Rarity.IsValid(m.RarityTier), "bad tier on mutation " .. m.Id)
		assert(type(m.BaseWeight) == "number" and m.BaseWeight > 0, "bad BaseWeight on " .. m.Id)
		table.insert(index[m.Category][m.RarityTier], m)
	end
	self._index = index
	return self
end

-- Validates and resolves a client-derived context. Returns (resolved, nil) or (nil, error).
function MutationService:Resolve(ctx: Context): (Resolved?, string?)
	local reg = self.Registry
	if type(ctx) ~= "table" then
		return nil, "BadContext"
	end
	local species = type(ctx.SpeciesId) == "string" and reg.Species.ById[ctx.SpeciesId]
	if not species then
		return nil, "UnknownSpecies"
	end
	local biome = type(ctx.BiomeId) == "string" and reg.Biomes.ById[ctx.BiomeId]
	if not biome then
		return nil, "UnknownBiome"
	end
	local catalysts = ctx.Catalysts or {}
	if type(catalysts) ~= "table" or #catalysts > reg.Materials.MaxPerIncubation then
		return nil, "TooManyCatalysts"
	end
	local set, defs = {}, {}
	for _, id in catalysts do
		local def = type(id) == "string" and reg.Materials.ById[id]
		if not def then
			return nil, "UnknownCatalyst"
		end
		if set[id] then
			return nil, "DuplicateCatalyst"
		end
		set[id] = true
		table.insert(defs, def)
	end
	local progression = ctx.Progression or 0
	if type(progression) ~= "number" or progression ~= progression then
		return nil, "BadProgression"
	end
	-- Events must exist and belong to this biome; they shift the environment.
	local events = ctx.Events or {}
	if type(events) ~= "table" then
		return nil, "BadEvent"
	end
	local environment = table.clone(biome.Environment)
	local eventDefs = {}
	for id, on in events do
		local def = reg.Events and reg.Events.ById[id]
		if not def or def.Biome ~= biome.Id or on ~= true then
			return nil, "BadEvent"
		end
		table.insert(eventDefs, def)
		for var, delta in def.EnvironmentDelta do
			environment[var] = (environment[var] or 0) + delta
		end
	end
	table.sort(eventDefs, function(a, b)
		return a.Id < b.Id
	end)
	local tierMods = ctx.TierModifiers or {}
	if type(tierMods) ~= "table" then
		return nil, "BadTierModifier"
	end
	for _, tm in tierMods do
		if type(tm) ~= "table" or not reg.Rarity.IsValid(tm.Tier) or type(tm.Multiplier) ~= "number" or tm.Multiplier <= 0 or type(tm.Source) ~= "string" then
			return nil, "BadTierModifier"
		end
	end
	return {
		TierModifiers = tierMods,
		Species = species,
		Biome = biome,
		CatalystSet = set,
		CatalystDefs = defs,
		Events = events,
		EventDefs = eventDefs,
		Research = ctx.Research or {},
		Progression = progression,
		Environment = environment,
	}, nil
end

-- Returns (true) or (false, reason). `chosen` is a list of mutation defs already on the monster.
function MutationService:CheckEligibility(m: any, r: Resolved, chosen: { any }?): (boolean, string?)
	local species = r.Species
	if m.AllowedSpecies and not contains(m.AllowedSpecies, species.Id) then
		return false, "Species"
	end
	if contains(m.ExcludedSpecies, species.Id) then
		return false, "Species"
	end
	if m.RequiredAttachment and not species.Attachments[m.RequiredAttachment] then
		return false, "Attachment"
	end
	if m.AllowedBiomes and not contains(m.AllowedBiomes, r.Biome.Id) then
		return false, "Biome"
	end
	if m.RequiredElements and not contains(m.RequiredElements, species.PrimaryElement) then
		return false, "Element"
	end
	if contains(m.ExcludedElements, species.PrimaryElement) then
		return false, "Element"
	end
	for _, c in m.RequiredCatalysts or {} do
		if not r.CatalystSet[c] then
			return false, "Catalyst"
		end
	end
	for _, e in m.RequiredEvents or {} do
		if not r.Events[e] then
			return false, "Event"
		end
	end
	for _, res in m.RequiredResearch or {} do
		if not r.Research[res] then
			return false, "Research"
		end
	end
	if m.MinimumProgression and r.Progression < m.MinimumProgression then
		return false, "Progression"
	end
	if m.Environment then
		for var, range in m.Environment do
			local v = r.Environment[var]
			if v == nil or v < range[1] or v > range[2] then
				return false, "Environment"
			end
		end
	end
	for _, other in chosen or {} do
		if other.Id == m.Id then
			return false, "Duplicate"
		end
		if m.ExclusiveGroup and other.ExclusiveGroup == m.ExclusiveGroup then
			return false, "ExclusiveGroup"
		end
		if contains(m.IncompatibleMutations, other.Id) or contains(other.IncompatibleMutations, m.Id) then
			return false, "Incompatible"
		end
	end
	return true, nil
end

-- Effective within-tier weight and the list of modifiers that applied.
function MutationService:GetMutationWeight(m: any, r: Resolved): (number, { { Source: string, Multiplier: number } })
	local mods = {}
	local mult = 1
	local biomeMult = r.Biome.MutationModifiers[m.Id]
	if biomeMult then
		mult *= biomeMult
		table.insert(mods, { Source = "Biome:" .. r.Biome.Id, Multiplier = biomeMult })
	end
	for _, cat in r.CatalystDefs do
		for _, eff in cat.Effects do
			if eff.Type == "MutationMultiplier" and eff.MutationId == m.Id then
				mult *= eff.Multiplier
				table.insert(mods, { Source = "Catalyst:" .. cat.Id, Multiplier = eff.Multiplier })
			end
		end
	end
	for _, ev in r.EventDefs do
		local evMult = ev.MutationModifiers[m.Id]
		if evMult then
			mult *= evMult
			table.insert(mods, { Source = "Event:" .. ev.Id, Multiplier = evMult })
		end
	end
	if m.Element and m.Element == r.Species.PrimaryElement then
		mult *= MutationService.AFFINITY_MULTIPLIER
		table.insert(mods, { Source = "Affinity:" .. m.Element, Multiplier = MutationService.AFFINITY_MULTIPLIER })
	end
	mult = clamp(mult, MutationService.MUTATION_MULT_MIN, MutationService.MUTATION_MULT_MAX)
	return m.BaseWeight * mult, mods
end

-- Tier weights for a category's tier roll: { [tier] = weight }, plus modifiers per tier.
function MutationService:GetTierWeights(categoryId: string, r: Resolved): ({ number }, { [number]: { any } })
	local weights, mods = {}, {}
	for _, tierDef in self.Registry.Rarity.Tiers do
		local mult = 1
		local tierMods = {}
		for _, cat in r.CatalystDefs do
			for _, eff in cat.Effects do
				if eff.Type == "TierMultiplier" and eff.Category == categoryId and eff.Tier == tierDef.Tier then
					mult *= eff.Multiplier
					table.insert(tierMods, { Source = "Catalyst:" .. cat.Id, Multiplier = eff.Multiplier })
				end
			end
		end
		for _, tm in r.TierModifiers do
			if tm.Tier == tierDef.Tier then
				mult *= tm.Multiplier
				table.insert(tierMods, { Source = tm.Source, Multiplier = tm.Multiplier })
			end
		end
		mult = clamp(mult, MutationService.TIER_MULT_MIN, MutationService.TIER_MULT_MAX)
		weights[tierDef.Tier] = tierDef.Chance * mult
		mods[tierDef.Tier] = tierMods
	end
	return weights, mods
end

-- Eligible candidates for one category+tier: { { Mutation, Weight, Modifiers } }.
function MutationService:GetCandidates(categoryId: string, tier: number, r: Resolved, chosen: { any }?)
	local out = {}
	for _, m in self._index[categoryId][tier] do
		if self:CheckEligibility(m, r, chosen) then
			local w, mods = self:GetMutationWeight(m, r)
			table.insert(out, { Mutation = m, Weight = w, Modifiers = mods })
		end
	end
	return out
end

-- First category with an eligible mutation at PITY_TIER+ (nil if none).
function MutationService:FindPityCategory(r: Resolved): string?
	for _, cat in self.Registry.Categories.List do
		if cat.Rolled == false then
			continue -- hybrids can only come from recipes, never from pity
		end
		for tier = MutationService.PITY_TIER, self.Registry.Rarity.Count do
			if #self:GetCandidates(cat.Id, tier, r, nil) > 0 then
				return cat.Id
			end
		end
	end
	return nil
end

-- Rolls all categories. Returns (result, nil) or (nil, error).
-- opts: { Pity: boolean? }
-- result = { Mutations = { mutationDef }, Log = { { Category, Slot, Tier?, MutationId?, Outcome } }, PityUsed }
function MutationService:Roll(ctx: Context, rng: Random, opts: { Pity: boolean? }?)
	local r, err = self:Resolve(ctx)
	if not r then
		return nil, err
	end
	local pityCategory = if opts and opts.Pity then self:FindPityCategory(r) else nil
	local chosen = {}
	local log = {}
	for _, cat in self.Registry.Categories.List do
		if cat.Rolled == false then
			continue
		end
		local tierWeights = self:GetTierWeights(cat.Id, r)
		local tierEntries = {}
		for tier, w in tierWeights do
			table.insert(tierEntries, { Key = tier, Weight = w })
		end
		table.sort(tierEntries, function(a, b)
			return a.Key < b.Key
		end)
		for slot = 1, cat.MaxSlots do
			local forced = slot == 1 and cat.Id == pityCategory
			local fill = if slot == 1 then cat.FillChance else cat.ExtraSlotFillChance
			if not forced and rng:NextNumber() >= fill then
				table.insert(log, { Category = cat.Id, Slot = slot, Outcome = "NotFilled" })
				break
			end
			local rollEntries = tierEntries
			if forced then
				rollEntries = {}
				for _, e in tierEntries do
					if e.Key >= MutationService.PITY_TIER and #self:GetCandidates(cat.Id, e.Key, r, chosen) > 0 then
						table.insert(rollEntries, e)
					end
				end
				if #rollEntries == 0 then
					rollEntries = tierEntries
					forced = false
				end
			end
			local tier = WeightedRandom.Pick(rollEntries, rng)
			local candidates = self:GetCandidates(cat.Id, tier, r, chosen)
			local entries = {}
			for _, c in candidates do
				table.insert(entries, { Key = c.Mutation, Weight = c.Weight })
			end
			local pick = WeightedRandom.Pick(entries, rng)
			if not pick then
				table.insert(log, { Category = cat.Id, Slot = slot, Tier = tier, Outcome = "NoCandidateAtTier" })
				break
			end
			table.insert(chosen, pick)
			table.insert(log, { Category = cat.Id, Slot = slot, Tier = tier, MutationId = pick.Id, Outcome = if forced then "PityPicked" else "Picked" })
		end
	end
	local hybrid, recipe = self:ResolveHybrid(chosen, r, rng)
	if hybrid then
		table.insert(chosen, hybrid)
		table.insert(log, { Category = "Hybrid", Slot = 1, Tier = hybrid.RarityTier, MutationId = hybrid.Id, RecipeId = recipe.Id, Outcome = "HybridFormed" })
	end
	return { Mutations = chosen, Log = log, Resolved = r, PityUsed = pityCategory ~= nil, RecipeId = recipe and recipe.Id }, nil
end

-- Elements present on a monster: its species element plus every Elemental mutation's.
function MutationService:ElementSet(chosen: { any }, r: Resolved): { [string]: boolean }
	local set = { [r.Species.PrimaryElement] = true }
	for _, m in chosen do
		if m.Category == "Elemental" and m.Element then
			set[m.Element] = true
		end
	end
	return set
end

-- Context conditions of a recipe (everything except inputs). Returns (ok, reason).
function MutationService:CheckRecipeConditions(recipe: any, r: Resolved): (boolean, string?)
	if recipe.Biomes and not contains(recipe.Biomes, r.Biome.Id) then
		return false, "Biome"
	end
	for _, c in recipe.RequiredCatalysts or {} do
		if not r.CatalystSet[c] then
			return false, "Catalyst"
		end
	end
	for _, e in recipe.RequiredEvents or {} do
		if not r.Events[e] then
			return false, "Event"
		end
	end
	for _, res in recipe.RequiredResearch or {} do
		if not r.Research[res] then
			return false, "Research"
		end
	end
	return true, nil
end

-- Which recipe inputs are present on `chosen`: (allPresent, { [input] = present }).
function MutationService:CheckRecipeInputs(recipe: any, chosen: { any }, r: Resolved): (boolean, { [string]: boolean })
	local elements = self:ElementSet(chosen, r)
	local ids = {}
	for _, m in chosen do
		ids[m.Id] = true
	end
	local status, all = {}, true
	for _, input in recipe.Inputs do
		local kind, name = input:match("^(%w+):(.+)$")
		local present = (kind == "Element" and elements[name] == true) or (kind == "Mutation" and ids[name] == true)
		status[input] = present
		all = all and present
	end
	return all, status
end

-- Applies the hybrid rule to a finished roll. Returns (outputMutation, recipe) or nil.
function MutationService:ResolveHybrid(chosen: { any }, r: Resolved, rng: Random)
	local recipes = self.Registry.HybridRecipes
	if not recipes then
		return nil, nil
	end
	for _, m in chosen do
		if m.Category == "Hybrid" then
			return nil, nil -- already has one
		end
	end
	for _, recipe in recipes.List do
		if self:CheckRecipeConditions(recipe, r) and (self:CheckRecipeInputs(recipe, chosen, r)) then
			if recipe.Chance >= 1 or rng:NextNumber() < recipe.Chance then
				return self.Registry.Mutations.ById[recipe.Output], recipe
			end
		end
	end
	return nil, nil
end

-- Exact odds for slot 1 of every category, computed by the same functions Roll uses.
-- Extra slots are conditional on slot 1 and are reported as fill chances only.
function MutationService:GetOddsReport(ctx: Context)
	local r, err = self:Resolve(ctx)
	if not r then
		return nil, err
	end
	local activeEvents = {}
	for _, ev in r.EventDefs do
		table.insert(activeEvents, ev.Id)
	end
	local report = { SpeciesId = r.Species.Id, BiomeId = r.Biome.Id, Categories = {}, ActiveEvents = activeEvents, Environment = r.Environment }
	-- Hybrid recipes: chance is conditional on the inputs being present after the roll.
	report.Hybrids = {}
	for _, recipe in (self.Registry.HybridRecipes and self.Registry.HybridRecipes.List) or {} do
		local condOk, reason = self:CheckRecipeConditions(recipe, r)
		local _, have = self:CheckRecipeInputs(recipe, {}, r) -- what the species alone provides
		table.insert(report.Hybrids, {
			RecipeId = recipe.Id,
			Output = recipe.Output,
			Chance = recipe.Chance,
			Guaranteed = recipe.Chance >= 1,
			ConditionsMet = condOk,
			BlockedBy = reason,
			InputsFromSpecies = have,
		})
	end
	for _, cat in self.Registry.Categories.List do
		if cat.Rolled == false then
			continue
		end
		local tierWeights, tierMods = self:GetTierWeights(cat.Id, r)
		local entries = {}
		for tier, w in tierWeights do
			table.insert(entries, { Key = tier, Weight = w })
		end
		local tierProb = WeightedRandom.Normalize(entries)
		local catReport = {
			Category = cat.Id,
			FillChance = cat.FillChance,
			ExtraSlots = cat.MaxSlots - 1,
			ExtraSlotFillChance = cat.ExtraSlotFillChance,
			Tiers = {},
			Candidates = {},
			EmptyChance = 1 - cat.FillChance,
		}
		for tier = 1, self.Registry.Rarity.Count do
			local pt = tierProb[tier] or 0
			local cands = self:GetCandidates(cat.Id, tier, r, nil)
			table.insert(catReport.Tiers, { Tier = tier, Probability = pt, Modifiers = tierMods[tier], CandidateCount = #cands })
			if #cands == 0 then
				catReport.EmptyChance += cat.FillChance * pt
			else
				local inTier = {}
				for _, c in cands do
					table.insert(inTier, { Key = c.Mutation.Id, Weight = c.Weight })
				end
				local pIn = WeightedRandom.Normalize(inTier)
				for _, c in cands do
					table.insert(catReport.Candidates, {
						MutationId = c.Mutation.Id,
						Tier = tier,
						EffectiveWeight = c.Weight,
						WithinTier = pIn[c.Mutation.Id],
						Probability = cat.FillChance * pt * pIn[c.Mutation.Id],
						Modifiers = c.Modifiers,
					})
				end
			end
		end
		table.insert(report.Categories, catReport)
	end
	return report, nil
end

return MutationService
