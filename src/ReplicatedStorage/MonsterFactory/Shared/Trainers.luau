--!strict
-- NPC trainers: two per biome, standing in their zone (WorldBuilder places a
-- TrainerSpot per entry, Main spawns and animates the character). Each trainer's
-- monsters wear hand-picked mutations from their home biome and know the
-- trainer's own Signature attack (defined here, registered into Battle.Moves).
-- Beat one to earn Reward coins; they pay out again after
-- Battle.TrainerCooldownSeconds. Trainers_spec checks every entry.

local Trainers = {}

export type Member = { Species: string, Tier: number, Mutations: { string } }
export type Trainer = {
	Id: string,
	DisplayName: string,
	Biome: string,
	Team: { Member },
	Reward: number,
	Shirt: Color3,
	Greeting: string,
	Boss: boolean?, -- the biome's boss: beating them the first time earns its Badge
	Signature: { Id: string, DisplayName: string, Element: string, Power: number, Accuracy: number },
}

Trainers.List = {
	-- Verdant Meadows
	{ Id = "Pip", DisplayName = "Pip", Biome = "VerdantMeadows", Shirt = Color3.fromRGB(90, 200, 90), Reward = 60,
		Greeting = "Let's see how strong your monsters are!",
		Signature = { Id = "PebblePop", DisplayName = "Pebble Pop", Element = "Earthen", Power = 60, Accuracy = 95 },
		Team = {
			{ Species = "Mossling", Tier = 1, Mutations = { "MossyCoat", "SoftGlow" } },
			{ Species = "Pebbleback", Tier = 1, Mutations = { "PebblePlating", "LeafMarkings" } },
		} },
	{ Id = "Rosa", Boss = true, DisplayName = "Rosa", Biome = "VerdantMeadows", Shirt = Color3.fromRGB(240, 110, 160), Reward = 150,
		Greeting = "My meadow team never loses!",
		Signature = { Id = "PetalDance", DisplayName = "Petal Dance", Element = "Verdant", Power = 80, Accuracy = 90 },
		Team = {
			{ Species = "Brookhopper", Tier = 2, Mutations = { "LilyPadHat", "WildflowerAura" } },
			{ Species = "Mossling", Tier = 2, Mutations = { "MossyMane", "VerdantSpots" } },
			{ Species = "Pebbleback", Tier = 3, Mutations = { "CloverCrown", "Thornbound" } },
		} },
	-- Frostfall Tundra
	{ Id = "Yuki", DisplayName = "Yuki", Biome = "FrostfallTundra", Shirt = Color3.fromRGB(150, 210, 255), Reward = 220,
		Greeting = "Brrr! Ready for a chilly battle?",
		Signature = { Id = "SnowballBarrage", DisplayName = "Snowball Barrage", Element = "Frost", Power = 75, Accuracy = 95 },
		Team = {
			{ Species = "Snowmote", Tier = 1, Mutations = { "SnowflakePattern", "ColdBreath" } },
			{ Species = "Frostfang", Tier = 2, Mutations = { "FrostedCoat", "Chilled" } },
		} },
	{ Id = "Bjorn", Boss = true, DisplayName = "Bjorn", Biome = "FrostfallTundra", Shirt = Color3.fromRGB(80, 110, 200), Reward = 420,
		Greeting = "Only the bravest beat the frost!",
		Signature = { Id = "GlacierCrash", DisplayName = "Glacier Crash", Element = "Frost", Power = 90, Accuracy = 85 },
		Team = {
			{ Species = "Frostfang", Tier = 3, Mutations = { "FrozenArmour", "FrozenCore" } },
			{ Species = "Snowmote", Tier = 2, Mutations = { "SnowdriftAura", "SnowflakePattern" } },
			{ Species = "Glimmerseal", Tier = 3, Mutations = { "IcicleFins", "Chilled" } },
		} },
	-- Emberpeak Volcano
	{ Id = "Blaze", DisplayName = "Blaze", Biome = "EmberpeakVolcano", Shirt = Color3.fromRGB(255, 120, 40), Reward = 450,
		Greeting = "Things are about to get HOT!",
		Signature = { Id = "FlameWheel", DisplayName = "Flame Wheel", Element = "Ember", Power = 80, Accuracy = 95 },
		Team = {
			{ Species = "Cindermite", Tier = 2, Mutations = { "EmberFlecks", "Heated" } },
			{ Species = "Basaltback", Tier = 2, Mutations = { "ObsidianPlating", "WarmGlow" } },
		} },
	{ Id = "MagmaMax", Boss = true, DisplayName = "Magma Max", Biome = "EmberpeakVolcano", Shirt = Color3.fromRGB(180, 40, 30), Reward = 800,
		Greeting = "Feel the power of the volcano!",
		Signature = { Id = "VolcanoBurst", DisplayName = "Volcano Burst", Element = "Ember", Power = 95, Accuracy = 85 },
		Team = {
			{ Species = "Basaltback", Tier = 3, Mutations = { "VolcanicArmour", "MagmaticCore" } },
			{ Species = "Cindermite", Tier = 3, Mutations = { "InfernalEyes", "LavaVeins" } },
			{ Species = "Ashwing", Tier = 3, Mutations = { "AshenWings", "Heated", "SmokeAura" } },
		} },
	-- Tidebreak Coast
	{ Id = "Marina", DisplayName = "Marina", Biome = "TidebreakCoast", Shirt = Color3.fromRGB(60, 190, 200), Reward = 700,
		Greeting = "Make a splash with me!",
		Signature = { Id = "BubbleBeam", DisplayName = "Bubble Beam", Element = "Tide", Power = 80, Accuracy = 95 },
		Team = {
			{ Species = "Reefling", Tier = 2, Mutations = { "ShellPattern", "BubbleBreath" } },
			{ Species = "Coralback", Tier = 3, Mutations = { "CoralAntlers", "Brined" } },
		} },
	{ Id = "CaptainKai", Boss = true, DisplayName = "Captain Kai", Biome = "TidebreakCoast", Shirt = Color3.fromRGB(30, 60, 140), Reward = 1200,
		Greeting = "Ahoy! My crew is the best on the coast!",
		Signature = { Id = "CannonSplash", DisplayName = "Cannon Splash", Element = "Tide", Power = 95, Accuracy = 85 },
		Team = {
			{ Species = "Coralback", Tier = 3, Mutations = { "PearlArmour", "Undertow" } },
			{ Species = "Reefling", Tier = 3, Mutations = { "PearlEyes", "TidalMarkings" } },
			{ Species = "Seamist", Tier = 4, Mutations = { "SeafoamAura", "TidalHeart" } },
		} },
	-- Thunderwild Highlands
	{ Id = "Volt", DisplayName = "Volt", Biome = "ThunderwildHighlands", Shirt = Color3.fromRGB(255, 220, 50), Reward = 1100,
		Greeting = "You'll be shocked by my speed!",
		Signature = { Id = "ZapDash", DisplayName = "Zap Dash", Element = "Storm", Power = 80, Accuracy = 100 },
		Team = {
			{ Species = "Sparkhare", Tier = 3, Mutations = { "StaticFur", "SparkTail", "Charged" } },
			{ Species = "Stormcrest", Tier = 3, Mutations = { "StormFeathers", "WindAura" } },
		} },
	{ Id = "Thora", Boss = true, DisplayName = "Thora", Biome = "ThunderwildHighlands", Shirt = Color3.fromRGB(120, 90, 200), Reward = 1800,
		Greeting = "The storm answers to me!",
		Signature = { Id = "ThunderHammer", DisplayName = "Thunder Hammer", Element = "Storm", Power = 95, Accuracy = 85 },
		Team = {
			{ Species = "Stormcrest", Tier = 3, Mutations = { "ArcWings", "LightningCore" } },
			{ Species = "Sparkhare", Tier = 4, Mutations = { "LightningMarkings", "ChargedWhiskers" } },
			{ Species = "Thunderhorn", Tier = 4, Mutations = { "ConductiveHorns", "TempestHeart" } },
		} },
	-- Toxic Bloom Swamp
	{ Id = "Bog", DisplayName = "Bog", Biome = "ToxicBloomSwamp", Shirt = Color3.fromRGB(110, 150, 60), Reward = 1600,
		Greeting = "Hehe, watch out for the goo!",
		Signature = { Id = "SludgeBomb", DisplayName = "Sludge Bomb", Element = "Toxic", Power = 85, Accuracy = 90 },
		Team = {
			{ Species = "Sporeling", Tier = 3, Mutations = { "MossPatches", "PaleSpores" } },
			{ Species = "Miretoad", Tier = 3, Mutations = { "MudArmour", "Toxified" } },
		} },
	{ Id = "DrVenom", Boss = true, DisplayName = "Dr. Venom", Biome = "ToxicBloomSwamp", Shirt = Color3.fromRGB(150, 40, 170), Reward = 2600,
		Greeting = "My monsters are the final test!",
		Signature = { Id = "VenomStorm", DisplayName = "Venom Storm", Element = "Toxic", Power = 100, Accuracy = 85 },
		Team = {
			{ Species = "Miretoad", Tier = 4, Mutations = { "CorrosiveArmour", "VenomCore" } },
			{ Species = "Sporeling", Tier = 4, Mutations = { "GlowingMushroomCap", "ToxicMist" } },
			{ Species = "Venomtail", Tier = 5, Mutations = { "VenomStinger", "FungalSovereign", "VenomMarkings" } },
		} },
} :: { Trainer }

-- Badge bonus coins for beating a boss the first time (on top of the normal prize).
Trainers.BadgeBonusMultiplier = 2

Trainers.ById = {} :: { [string]: Trainer }
for _, tr in Trainers.List do
	Trainers.ById[tr.Id] = tr
end

return Trainers
