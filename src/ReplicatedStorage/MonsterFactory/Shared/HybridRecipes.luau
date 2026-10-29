--!strict
-- Hybrid combination registry. A hybrid is resolved AFTER the normal mutation roll:
-- if a monster ends up with all of a recipe's Inputs and every condition holds,
-- the recipe either fires automatically (Chance = 1, "guaranteed") or rolls its
-- Chance once. At most one hybrid per monster; recipes are tried in Priority order
-- (highest first). Order of inputs never matters.
--
-- Inputs:  "Element:<name>"   satisfied by the species' element or any Elemental mutation's element
--          "Mutation:<id>"    satisfied if that mutation was rolled
-- Conditions (all optional): Biomes, RequiredCatalysts, RequiredEvents, RequiredResearch.
-- Repeating an incubation can never skip a condition: conditions are re-checked on
-- every roll against the server-built context.

export type Recipe = {
	Id: string,
	DisplayName: string,
	Inputs: { string },
	Output: string, -- mutation id (Category "Hybrid")
	Chance: number, -- 1 = guaranteed once all inputs and conditions are met
	Priority: number,
	Biomes: { string }?,
	RequiredCatalysts: { string }?,
	RequiredEvents: { string }?,
	RequiredResearch: { string }?,
	Hint: string, -- shown before discovery
}

local HybridRecipes = {}

HybridRecipes.List = {
	{
		Id = "PermafrostShell",
		DisplayName = "Earthen + Frost = Permafrost Shell",
		Inputs = { "Element:Earthen", "Element:Frost" },
		Output = "PermafrostShell",
		Chance = 1,
		Priority = 10,
		Biomes = { "FrostfallTundra" },
		RequiredCatalysts = { "GlacierCrystal" },
		Hint = "An earthy creature that turns frosty in the tundra - with a Glacier Crystal it always works.",
	},
	{
		Id = "Rootstone",
		DisplayName = "Earthen + Verdant = Rootstone",
		Inputs = { "Element:Earthen", "Element:Verdant" },
		Output = "Rootstone",
		Chance = 0.4,
		Priority = 10,
		Biomes = { "VerdantMeadows" },
		Hint = "Stone and growing things, in the meadows.",
	},
	{
		Id = "Frostbloom",
		DisplayName = "Verdant + Frost = Frostbloom",
		Inputs = { "Element:Verdant", "Element:Frost" },
		Output = "Frostbloom",
		Chance = 0.35,
		Priority = 20,
		Biomes = { "FrostfallTundra" },
		Hint = "A plant creature that catches a chill.",
	},
	{
		Id = "Icefloe",
		DisplayName = "Tide + Frost = Icefloe",
		Inputs = { "Element:Tide", "Element:Frost" },
		Output = "Icefloe",
		Chance = 0.3,
		Priority = 20,
		Biomes = { "FrostfallTundra" },
		Hint = "Water creatures in freezing places...",
	},
	{
		Id = "PrismaticAurora",
		DisplayName = "Aurora Markings + Crystal Antlers = Prismatic Aurora",
		Inputs = { "Mutation:AuroraMarkings", "Mutation:CrystalAntlers" },
		Output = "PrismaticAurora",
		Chance = 0.5,
		Priority = 50,
		Biomes = { "FrostfallTundra" },
		RequiredEvents = { "AuroraNight" },
		Hint = "Crystal that drinks in the aurora's light. Only on Aurora Night.",
	},
	{
		Id = "MoltenCore",
		DisplayName = "Ember + Earthen = Molten Core",
		Inputs = { "Element:Ember", "Element:Earthen" },
		Output = "MoltenCore",
		Chance = 0.4,
		Priority = 20,
		Biomes = { "EmberpeakVolcano" },
		Hint = "Rock that remembers being lava.",
	},
	{
		Id = "Steamvent",
		DisplayName = "Ember + Tide = Steamvent",
		Inputs = { "Element:Ember", "Element:Tide" },
		Output = "Steamvent",
		Chance = 0.3,
		Priority = 20,
		Biomes = { "EmberpeakVolcano", "TidebreakCoast" },
		Hint = "Fire meets water - by the sea or in the volcano.",
	},
	{
		Id = "Kelpbloom",
		DisplayName = "Verdant + Tide = Kelpbloom",
		Inputs = { "Element:Verdant", "Element:Tide" },
		Output = "Kelpbloom",
		Chance = 0.35,
		Priority = 15,
		Biomes = { "TidebreakCoast" },
		Hint = "A plant creature that learns to swim.",
	},
	{
		Id = "Frostfire",
		DisplayName = "Frost + Ember = Frostfire",
		Inputs = { "Element:Frost", "Element:Ember" },
		Output = "Frostfire",
		Chance = 0.25,
		Priority = 40,
		Biomes = { "EmberpeakVolcano" },
		Hint = "A creature of ice, brought somewhere very hot.",
	},
	{
		Id = "Tempest",
		DisplayName = "Tide + Storm = Tempest",
		Inputs = { "Element:Tide", "Element:Storm" },
		Output = "Tempest",
		Chance = 0.3,
		Priority = 20,
		Biomes = { "ThunderwildHighlands", "TidebreakCoast" },
		Hint = "Sea and sky collide - on the coast or in the highlands.",
	},
	{
		Id = "Hailstorm",
		DisplayName = "Frost + Storm = Hailstorm",
		Inputs = { "Element:Frost", "Element:Storm" },
		Output = "Hailstorm",
		Chance = 0.3,
		Priority = 25,
		Biomes = { "ThunderwildHighlands", "FrostfallTundra" },
		Hint = "Ice in the clouds.",
	},
	{
		Id = "Blightbloom",
		DisplayName = "Verdant + Toxic = Blightbloom",
		Inputs = { "Element:Verdant", "Element:Toxic" },
		Output = "Blightbloom",
		Chance = 0.35,
		Priority = 15,
		Biomes = { "ToxicBloomSwamp" },
		Hint = "A plant creature that wanders into the swamp.",
	},
	{
		Id = "Cinderblight",
		DisplayName = "Ember + Toxic = Cinderblight",
		Inputs = { "Element:Ember", "Element:Toxic" },
		Output = "Cinderblight",
		Chance = 0.25,
		Priority = 35,
		Biomes = { "ToxicBloomSwamp", "EmberpeakVolcano" },
		Hint = "Embers and poison - in the swamp or the volcano.",
	},
} :: { Recipe }

HybridRecipes.ById = {} :: { [string]: Recipe }
for _, r in HybridRecipes.List do
	assert(HybridRecipes.ById[r.Id] == nil, "duplicate recipe " .. r.Id)
	assert(r.Chance > 0 and r.Chance <= 1, "bad chance on recipe " .. r.Id)
	HybridRecipes.ById[r.Id] = r
end
-- Highest priority first; ties by Id so resolution is deterministic.
table.sort(HybridRecipes.List, function(a, b)
	if a.Priority ~= b.Priority then
		return a.Priority > b.Priority
	end
	return a.Id < b.Id
end)

return HybridRecipes
