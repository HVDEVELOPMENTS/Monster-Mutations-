--!strict
-- Base species. `Attachments` lists the body regions the species rig exposes;
-- physical/aura mutations declare which region they need (RequiredAttachment).

export type Species = {
	Id: string,
	DisplayName: string,
	Description: string,
	SpeciesRarity: number,
	PrimaryElement: string,
	BodyType: string,
	HomeBiome: string,
	Attachments: { [string]: boolean },
	Palettes: { string },
	SizeRange: { number },
	BaseStats: { Power: number, IncomeRate: number, ResearchValue: number },
}

local Species = {}

Species.List = {
	{
		Id = "Mossling",
		DisplayName = "Mossling",
		Description = "A small, round plant creature that naps in sunbeams.",
		SpeciesRarity = 1,
		PrimaryElement = "Verdant",
		BodyType = "Quadrupedal",
		HomeBiome = "VerdantMeadows",
		Attachments = { Head = true, Back = true, Eyes = true, Body = true },
		Palettes = { "Moss", "Fern", "Lime" },
		SizeRange = { 0.9, 1.1 },
		BaseStats = { Power = 5, IncomeRate = 1, ResearchValue = 1 },
	},
	{
		Id = "Pebbleback",
		DisplayName = "Pebbleback",
		Description = "A squat, sturdy creature with a shell of river stones.",
		SpeciesRarity = 1,
		PrimaryElement = "Earthen",
		BodyType = "Quadrupedal",
		HomeBiome = "VerdantMeadows",
		Attachments = { Head = true, Back = true, Eyes = true, Body = true },
		Palettes = { "Slate", "Sandstone", "Clay" },
		SizeRange = { 0.95, 1.2 },
		BaseStats = { Power = 7, IncomeRate = 0.8, ResearchValue = 1 },
	},
	{
		Id = "Brookhopper",
		DisplayName = "Brookhopper",
		Description = "A quick amphibian that skips across streams.",
		SpeciesRarity = 2,
		PrimaryElement = "Tide",
		BodyType = "Amphibious",
		HomeBiome = "VerdantMeadows",
		Attachments = { Head = true, Tail = true, Eyes = true, Body = true },
		Palettes = { "Pond", "Reed", "Teal" },
		SizeRange = { 0.85, 1.05 },
		BaseStats = { Power = 4, IncomeRate = 1.2, ResearchValue = 1.2 },
	},
	-- ===== Frostfall Tundra =====
	{
		Id = "Snowmote",
		DisplayName = "Snowmote",
		Description = "A drifting puff of living snow with tiny ears.",
		SpeciesRarity = 1,
		PrimaryElement = "Frost",
		BodyType = "Floating",
		HomeBiome = "FrostfallTundra",
		Attachments = { Head = true, Eyes = true, Body = true },
		Palettes = { "Snow", "Frostblue", "Pearl" },
		SizeRange = { 0.85, 1.1 },
		BaseStats = { Power = 4, IncomeRate = 1.6, ResearchValue = 1.3 },
	},
	{
		Id = "Frostfang",
		DisplayName = "Frostfang",
		Description = "A lean tundra hunter with a frost-tipped tail.",
		SpeciesRarity = 2,
		PrimaryElement = "Frost",
		BodyType = "Quadrupedal",
		HomeBiome = "FrostfallTundra",
		Attachments = { Head = true, Back = true, Tail = true, Eyes = true, Body = true },
		Palettes = { "Arctic", "Slateblue", "Snow" },
		SizeRange = { 0.95, 1.2 },
		BaseStats = { Power = 9, IncomeRate = 1.5, ResearchValue = 1.2 },
	},
	{
		Id = "Glimmerseal",
		DisplayName = "Glimmerseal",
		Description = "A playful seal whose coat glitters like fresh ice.",
		SpeciesRarity = 3,
		PrimaryElement = "Tide",
		BodyType = "Aquatic",
		HomeBiome = "FrostfallTundra",
		Attachments = { Head = true, Tail = true, Eyes = true, Body = true },
		Palettes = { "Pearl", "Frostblue", "Slateblue" },
		SizeRange = { 0.9, 1.15 },
		BaseStats = { Power = 6, IncomeRate = 2.0, ResearchValue = 1.5 },
	},
	-- ===== Emberpeak Volcano =====
	{
		Id = "Cindermite", DisplayName = "Cindermite", SpeciesRarity = 1, PrimaryElement = "Ember", BodyType = "Insectoid",
		Description = "A round little lava beetle whose shell glows through the cracks.",
		HomeBiome = "EmberpeakVolcano", Attachments = { Head = true, Back = true, Eyes = true, Body = true },
		Palettes = { "Charcoal", "Basalt", "Rust" }, SizeRange = { 0.85, 1.05 },
		BaseStats = { Power = 7, IncomeRate = 2.2, ResearchValue = 1.5 },
	},
	{
		Id = "Basaltback", DisplayName = "Basaltback", SpeciesRarity = 2, PrimaryElement = "Earthen", BodyType = "Quadrupedal",
		Description = "A stocky volcanic grazer with a horn of cooled lava rock.",
		HomeBiome = "EmberpeakVolcano", Attachments = { Head = true, Back = true, Tail = true, Eyes = true, Body = true },
		Palettes = { "Basalt", "Rust", "Charcoal" }, SizeRange = { 0.95, 1.2 },
		BaseStats = { Power = 12, IncomeRate = 2.0, ResearchValue = 1.4 },
	},
	{
		Id = "Ashwing", DisplayName = "Ashwing", SpeciesRarity = 3, PrimaryElement = "Ember", BodyType = "Winged",
		Description = "A fluffy ember bat that rides the hot updrafts.",
		HomeBiome = "EmberpeakVolcano", Attachments = { Head = true, Wings = true, Tail = true, Eyes = true, Body = true },
		Palettes = { "Ashgrey", "Magma", "Charcoal" }, SizeRange = { 0.85, 1.1 },
		BaseStats = { Power = 8, IncomeRate = 2.6, ResearchValue = 1.8 },
	},
	-- ===== Tidebreak Coast =====
	{
		Id = "Reefling", DisplayName = "Reefling", SpeciesRarity = 1, PrimaryElement = "Tide", BodyType = "Floating",
		Description = "A chubby reef fish that swims through the air as if it were water.",
		HomeBiome = "TidebreakCoast", Attachments = { Head = true, Tail = true, Eyes = true, Body = true },
		Palettes = { "Reef", "Coral", "Lagoon" }, SizeRange = { 0.85, 1.1 },
		BaseStats = { Power = 6, IncomeRate = 2.6, ResearchValue = 1.7 },
	},
	{
		Id = "Coralback", DisplayName = "Coralback", SpeciesRarity = 2, PrimaryElement = "Tide", BodyType = "Crustacean",
		Description = "A sideways-scuttling crab with a little reef growing on its shell.",
		HomeBiome = "TidebreakCoast", Attachments = { Head = true, Back = true, Eyes = true, Body = true },
		Palettes = { "Coral", "Sand", "Reef" }, SizeRange = { 0.95, 1.15 },
		BaseStats = { Power = 11, IncomeRate = 2.4, ResearchValue = 1.6 },
	},
	{
		Id = "Seamist", DisplayName = "Seamist", SpeciesRarity = 3, PrimaryElement = "Tide", BodyType = "Floating",
		Description = "A drifting jellyfish with a soft, glowing bell.",
		HomeBiome = "TidebreakCoast", Attachments = { Head = true, Eyes = true, Body = true },
		Palettes = { "Lagoon", "Seafoam", "Coral" }, SizeRange = { 0.85, 1.1 },
		BaseStats = { Power = 5, IncomeRate = 3.0, ResearchValue = 2.0 },
	},
	-- ===== Thunderwild Highlands =====
	{
		Id = "Sparkhare", DisplayName = "Sparkhare", SpeciesRarity = 1, PrimaryElement = "Storm", BodyType = "Quadrupedal",
		Description = "A speedy hare whose fur crackles with static.",
		HomeBiome = "ThunderwildHighlands", Attachments = { Head = true, Tail = true, Eyes = true, Body = true },
		Palettes = { "Sunbeam", "Cream", "Stormgrey" }, SizeRange = { 0.85, 1.05 },
		BaseStats = { Power = 8, IncomeRate = 3.4, ResearchValue = 2.0 },
	},
	{
		Id = "Stormcrest", DisplayName = "Stormcrest", SpeciesRarity = 2, PrimaryElement = "Storm", BodyType = "Winged",
		Description = "A round little bird with a lightning-bolt crest.",
		HomeBiome = "ThunderwildHighlands", Attachments = { Head = true, Wings = true, Tail = true, Eyes = true, Body = true },
		Palettes = { "Skyblue", "Stormgrey", "Cream" }, SizeRange = { 0.85, 1.1 },
		BaseStats = { Power = 9, IncomeRate = 3.6, ResearchValue = 2.2 },
	},
	{
		Id = "Thunderhorn", DisplayName = "Thunderhorn", SpeciesRarity = 3, PrimaryElement = "Earthen", BodyType = "Quadrupedal",
		Description = "A mountain goat whose horns call down the lightning.",
		HomeBiome = "ThunderwildHighlands", Attachments = { Head = true, Back = true, Tail = true, Eyes = true, Body = true },
		Palettes = { "Stormgrey", "Slateblue", "Cream" }, SizeRange = { 0.95, 1.2 },
		BaseStats = { Power = 15, IncomeRate = 3.2, ResearchValue = 2.0 },
	},
	-- ===== Toxic Bloom Swamp =====
	{
		Id = "Sporeling", DisplayName = "Sporeling", SpeciesRarity = 1, PrimaryElement = "Toxic", BodyType = "Fungal",
		Description = "A waddling mushroom with a spotty cap.",
		HomeBiome = "ToxicBloomSwamp", Attachments = { Head = true, Eyes = true, Body = true },
		Palettes = { "Toadstool", "Violet", "Mossgreen" }, SizeRange = { 0.85, 1.1 },
		BaseStats = { Power = 8, IncomeRate = 3.8, ResearchValue = 2.4 },
	},
	{
		Id = "Miretoad", DisplayName = "Miretoad", SpeciesRarity = 2, PrimaryElement = "Toxic", BodyType = "Amphibious",
		Description = "A chunky bog toad covered in friendly warts.",
		HomeBiome = "ToxicBloomSwamp", Attachments = { Head = true, Back = true, Eyes = true, Body = true },
		Palettes = { "Mossgreen", "Bogbrown", "Violet" }, SizeRange = { 0.95, 1.2 },
		BaseStats = { Power = 11, IncomeRate = 3.6, ResearchValue = 2.2 },
	},
	{
		Id = "Venomtail", DisplayName = "Venomtail", SpeciesRarity = 3, PrimaryElement = "Toxic", BodyType = "Reptilian",
		Description = "A swamp lizard with a glowing stinger tail.",
		HomeBiome = "ToxicBloomSwamp", Attachments = { Head = true, Back = true, Tail = true, Eyes = true, Body = true },
		Palettes = { "Bogbrown", "Violet", "Mossgreen" }, SizeRange = { 0.9, 1.15 },
		BaseStats = { Power = 16, IncomeRate = 3.4, ResearchValue = 2.4 },
	},
} :: { Species }

Species.ById = {} :: { [string]: Species }
for _, s in Species.List do
	Species.ById[s.Id] = s
end

return Species
