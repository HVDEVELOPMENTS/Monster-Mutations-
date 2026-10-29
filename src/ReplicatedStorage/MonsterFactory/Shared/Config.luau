--!strict
-- Economy and progression tuning. All numbers here are shown to players where relevant.

local Config = {}

Config.StartingCoins = 150
Config.StartingInventory = { Dewdrop = 2 }

Config.IncubationSeconds = 8
Config.MaxMonsters = 200

-- Coins per incubation, and the level at which each species becomes available.
Config.Species = {
	Mossling = { Cost = 25, UnlockLevel = 1 },
	Pebbleback = { Cost = 25, UnlockLevel = 1 },
	Brookhopper = { Cost = 45, UnlockLevel = 3 },
	-- Frostfall species also need Frostfall Tundra unlocked.
	Snowmote = { Cost = 60, UnlockLevel = 4 },
	Frostfang = { Cost = 85, UnlockLevel = 5 },
	Glimmerseal = { Cost = 120, UnlockLevel = 6 },
	-- Emberpeak Volcano
	Cindermite = { Cost = 110, UnlockLevel = 7 },
	Basaltback = { Cost = 150, UnlockLevel = 8 },
	Ashwing = { Cost = 200, UnlockLevel = 9 },
	-- Tidebreak Coast
	Reefling = { Cost = 160, UnlockLevel = 9 },
	Coralback = { Cost = 200, UnlockLevel = 10 },
	Seamist = { Cost = 260, UnlockLevel = 11 },
	-- Thunderwild Highlands
	Sparkhare = { Cost = 300, UnlockLevel = 12 },
	Stormcrest = { Cost = 360, UnlockLevel = 13 },
	Thunderhorn = { Cost = 420, UnlockLevel = 14 },
	-- Toxic Bloom Swamp
	Sporeling = { Cost = 400, UnlockLevel = 14 },
	Miretoad = { Cost = 460, UnlockLevel = 15 },
	Venomtail = { Cost = 540, UnlockLevel = 16 },
}

Config.CatalystPrices = {
	Dewdrop = 10, FertileSoil = 40, AncientSeed = 300,
	FrostShard = 15, GlacierCrystal = 60, AuroraFragment = 400,
	Emberstone = 25, ObsidianShard = 90, MagmaHeart = 600,
	Pearl = 30, CoralFragment = 100, Tideglass = 750,
	ChargedShard = 40, Stormglass = 140, Thunderstone = 900,
	ToxicSpore = 50, VenomSac = 160, AncientMushroom = 1100,
}
-- Catalysts from a locked biome can't be bought yet.
Config.MaxBuyQuantity = 10

-- Sell value by monster rarity tier.
Config.SellValue = { 8, 15, 40, 120, 500, 2500, 15000, 100000 }

-- Only the N highest-income monsters earn passive coins (your "habitat").
Config.EarningSlots = 8

-- XP per claimed monster by rarity tier; XP needed for the next level.
Config.XPByTier = { 10, 15, 30, 60, 150, 400, 1000, 3000 }
function Config.XPToNext(level: number): number
	return 40 + level * 25
end

-- Bad-luck protection: after this many claims in a row with nothing Rare or
-- better, the next incubation is guaranteed to contain a Rare+ mutation.
Config.PityThreshold = 20

-- One-time coin reward the first time you discover a mutation, by its tier.
Config.DiscoveryReward = { 5, 10, 25, 60, 200, 800, 3000, 10000 }
Config.SpeciesDiscoveryReward = 20

-- Collection milestones (rewarded once).
Config.Milestones = {
	{ Id = "FirstMutation", Name = "First Mutation", Kind = "MutationCount", Value = 1, Reward = 25 },
	{ Id = "Mutations5", Name = "Budding Geneticist (5 mutations)", Kind = "MutationCount", Value = 5, Reward = 75 },
	{ Id = "Mutations12", Name = "Meadow Scholar (12 mutations)", Kind = "MutationCount", Value = 12, Reward = 250 },
	{ Id = "FirstRare", Name = "First Rare+", Kind = "TierReached", Value = 3, Reward = 50 },
	{ Id = "FirstEpic", Name = "First Epic+", Kind = "TierReached", Value = 4, Reward = 150 },
	{ Id = "FirstLegendary", Name = "First Legendary+", Kind = "TierReached", Value = 5, Reward = 600 },
	{ Id = "AllMeadowSpecies", Name = "Meadow Family (all 3 species)", Kind = "SpeciesCount", Value = 3, Reward = 120 },
	{ Id = "FirstFrost", Name = "Frostbitten (first Frostfall mutation)", Kind = "BiomeMutation", Value = "FrostfallTundra", Reward = 150 },
	{ Id = "Mutations25", Name = "Field Geneticist (25 mutations)", Kind = "MutationCount", Value = 25, Reward = 600 },
	{ Id = "AllSpecies6", Name = "Two Biomes, Six Species", Kind = "SpeciesCount", Value = 6, Reward = 500 },
	{ Id = "FirstEmber", Name = "Fire-Forged (first Emberpeak mutation)", Kind = "BiomeMutation", Value = "EmberpeakVolcano", Reward = 300 },
	{ Id = "FirstTide", Name = "Sea Legs (first Tidebreak mutation)", Kind = "BiomeMutation", Value = "TidebreakCoast", Reward = 400 },
	{ Id = "Mutations50", Name = "Master Geneticist (50 mutations)", Kind = "MutationCount", Value = 50, Reward = 2000 },
	{ Id = "AllSpecies12", Name = "Four Biomes, Twelve Species", Kind = "SpeciesCount", Value = 12, Reward = 2500 },
	{ Id = "FirstStorm", Name = "Lightning Struck (first Highlands mutation)", Kind = "BiomeMutation", Value = "ThunderwildHighlands", Reward = 600 },
	{ Id = "FirstToxic", Name = "Bog Explorer (first Swamp mutation)", Kind = "BiomeMutation", Value = "ToxicBloomSwamp", Reward = 800 },
	{ Id = "AllSpecies18", Name = "Six Biomes, Eighteen Species", Kind = "SpeciesCount", Value = 18, Reward = 6000 },
}

-- Rate limits: max calls per window (seconds) for each remote action.
Config.RateLimits = {
	GetState = { 10, 10 },
	GetOdds = { 20, 10 },
	StartIncubation = { 5, 5 },
	ClaimIncubation = { 5, 5 },
	SellMonster = { 10, 5 },
	ToggleLock = { 10, 5 },
	BuyCatalyst = { 10, 5 },
	MarkSeen = { 30, 5 },
	SetSetting = { 10, 5 },
	UnlockBiome = { 5, 5 },
	EquipMonster = { 6, 5 },
	BuyUpgrade = { 5, 5 },
	BuyResearch = { 5, 5 },
	Gather = { 6, 5 },
	TeleportToBiome = { 3, 5 },
}

return Config
