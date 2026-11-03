--!strict
-- Factory upgrades, research and gathering. Every effect is a precise, documented
-- number; nothing is a vague "luck" boost.

local Progression = {}

-- ===== Factory upgrades (bought with coins, one level at a time) =====
-- Effect values are per level; `Costs[n]` buys level n.
Progression.Upgrades = {
	{
		Id = "ImprovedIncubator",
		DisplayName = "Improved Incubator",
		Describe = function(level: number): string
			return string.format("Incubation time -%d s (base 8 s)", level)
		end,
		SecondsPerLevel = 1,
		Costs = { 100, 250, 600, 1500 },
	},
	{
		Id = "RareResonator",
		DisplayName = "Rare Resonator",
		Describe = function(level: number): string
			return string.format("Rare-tier weight x%.1f in every category's tier roll (odds panel shows the result)", 1 + 0.1 * level)
		end,
		Tier = 3,
		MultiplierPerLevel = 0.1,
		Costs = { 300, 800, 2000 },
	},
	{
		Id = "CatalystRecycler",
		DisplayName = "Catalyst Recycler",
		Describe = function(level: number): string
			return string.format("%d%% chance to keep each catalyst you use", level * 10)
		end,
		ChancePerLevel = 0.1,
		Costs = { 250, 700 },
	},
	{
		Id = "HabitatExpansion",
		DisplayName = "Habitat Expansion",
		Describe = function(level: number): string
			return string.format("+%d monsters earn passive income (base 8)", level * 2)
		end,
		SlotsPerLevel = 2,
		Costs = { 200, 500, 1200 },
	},
	{
		Id = "CompanionHarness",
		DisplayName = "Companion Harness",
		Describe = function(level: number): string
			return string.format("+%d monster%s can follow you (base 3)", level, if level == 1 then "" else "s")
		end,
		PetSlotsPerLevel = 1,
		Costs = { 1500, 5000 },
	},
}
Progression.UpgradeById = {}
for _, u in Progression.Upgrades do
	Progression.UpgradeById[u.Id] = u
end

-- ===== Research (bought with Research Points) =====
-- Research Points come from claiming monsters: floor(ResearchValue * RPPerResearchValue),
-- plus a bonus for each first discovery.
Progression.RPPerResearchValue = 5
Progression.RPPerDiscovery = 10

Progression.Research = {
	{
		Id = "RecipeAnalyzer",
		DisplayName = "Recipe Analyzer",
		Description = "Shows the ingredients of undiscovered hybrid recipes.",
		Cost = 60,
		Requires = {},
	},
	{
		Id = "WorldtreeStudy",
		DisplayName = "Worldtree Study",
		Description = "Allows the Mythic mutation Worldtree Seed in Verdant Meadows (also needs level 10).",
		Cost = 250,
		Requires = { "RecipeAnalyzer" },
	},
	{
		Id = "CryoStudy",
		DisplayName = "Cryo Study",
		Description = "Allows the Mythic mutation Absolute Zero in Frostfall Tundra (also needs level 15).",
		Cost = 500,
		Requires = { "RecipeAnalyzer" },
		RequiresBiome = "FrostfallTundra",
	},
	{
		Id = "Forgecraft",
		DisplayName = "Forgecraft",
		Description = "Allows the Mythic mutation Worldforged in Emberpeak Volcano (also needs level 18).",
		Cost = 900,
		Requires = { "RecipeAnalyzer" },
		RequiresBiome = "EmberpeakVolcano",
	},
	{
		Id = "DeepStudy",
		DisplayName = "Deep Study",
		Description = "Allows the Mythic mutation Abyssal Sovereign in Tidebreak Coast (also needs level 18).",
		Cost = 1200,
		Requires = { "RecipeAnalyzer" },
		RequiresBiome = "TidebreakCoast",
	},
	{
		Id = "StormStudy",
		DisplayName = "Storm Study",
		Description = "Allows the Mythic mutation Worldstorm in Thunderwild Highlands (also needs level 22).",
		Cost = 1600,
		Requires = { "RecipeAnalyzer" },
		RequiresBiome = "ThunderwildHighlands",
	},
	{
		Id = "BlightStudy",
		DisplayName = "Blight Study",
		Description = "Allows the Mythic mutation Primordial Blight in Toxic Bloom Swamp (also needs level 24).",
		Cost = 2000,
		Requires = { "RecipeAnalyzer" },
		RequiresBiome = "ToxicBloomSwamp",
	},
}
Progression.ResearchById = {}
for _, r in Progression.Research do
	Progression.ResearchById[r.Id] = r
end

-- ===== Gathering =====
-- Each world node can be gathered by each player once per Cooldown seconds.
-- Drops: Base always drops BaseAmount; each Bonus rolls its Chance independently
-- (event bonuses only apply while that event is active). All chances are shown in-game.
Progression.GatherNodes = {
	DewdropFlower = {
		DisplayName = "Dewdrop Flower",
		Biome = "VerdantMeadows",
		Cooldown = 45,
		Base = "Dewdrop",
		BaseAmount = { 1, 2 },
		Bonus = {
			{ Material = "FertileSoil", Chance = 0.15 },
			{ Material = "AncientSeed", Chance = 0.03 },
		},
	},
	FrostCrystal = {
		DisplayName = "Frost Crystal",
		Biome = "FrostfallTundra",
		Cooldown = 60,
		Base = "FrostShard",
		BaseAmount = { 1, 2 },
		Bonus = {
			{ Material = "GlacierCrystal", Chance = 0.12 },
			{ Material = "AuroraFragment", Chance = 0.05, Event = "AuroraNight" },
		},
	},
	EmberVent = {
		DisplayName = "Ember Vent",
		Biome = "EmberpeakVolcano",
		Cooldown = 60,
		Base = "Emberstone",
		BaseAmount = { 1, 2 },
		Bonus = {
			{ Material = "ObsidianShard", Chance = 0.12 },
			{ Material = "MagmaHeart", Chance = 0.04, Event = "MagmaSurge" },
		},
	},
	TidePool = {
		DisplayName = "Tide Pool",
		Biome = "TidebreakCoast",
		Cooldown = 60,
		Base = "Pearl",
		BaseAmount = { 1, 2 },
		Bonus = {
			{ Material = "CoralFragment", Chance = 0.15 },
			{ Material = "Tideglass", Chance = 0.04, Event = "KingTide" },
		},
	},
	LightningRod = {
		DisplayName = "Lightning Rod",
		Biome = "ThunderwildHighlands",
		Cooldown = 60,
		Base = "ChargedShard",
		BaseAmount = { 1, 2 },
		Bonus = {
			{ Material = "Stormglass", Chance = 0.12 },
			{ Material = "Thunderstone", Chance = 0.04, Event = "LightningStorm" },
		},
	},
	SporePod = {
		DisplayName = "Spore Pod",
		Biome = "ToxicBloomSwamp",
		Cooldown = 60,
		Base = "ToxicSpore",
		BaseAmount = { 1, 2 },
		Bonus = {
			{ Material = "VenomSac", Chance = 0.14 },
			{ Material = "AncientMushroom", Chance = 0.04, Event = "ToxicBloom" },
		},
	},
}
-- Display order for gather nodes (biome progression order).
Progression.GatherOrder = { "DewdropFlower", "FrostCrystal", "EmberVent", "TidePool", "LightningRod", "SporePod" }
Progression.GatherRange = 14 -- studs from node to character

return Progression
