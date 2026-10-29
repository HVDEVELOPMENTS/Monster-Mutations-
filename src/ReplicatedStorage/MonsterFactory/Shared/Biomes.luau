--!strict
-- Biome definitions. `Environment` holds the default value of each environmental
-- variable; mutations with an `Environment` rule are eligible only when the
-- biome's value lies inside their [min, max] range.
-- `MutationModifiers` multiply BaseWeight for listed mutations (within-tier only).
-- `Unlock` lists every requirement; all must be met. Unlocks are permanent.
-- `Species` are the biome's native species; any species from an unlocked biome may
-- be incubated in any unlocked biome.

export type Biome = {
	Id: string,
	DisplayName: string,
	Description: string,
	Order: number,
	Environment: { [string]: number },
	Species: { string },
	MutationModifiers: { [string]: number },
	Catalysts: { string },
	Unlock: { Level: number, MutationsDiscovered: number, Coins: number },
	Theme: { Accent: Color3 },
	ShortName: string,
}

local Biomes = {}

Biomes.List = {
	{
		Id = "VerdantMeadows",
		DisplayName = "Verdant Meadows",
		Description = "Rolling hills, wildflowers and gentle streams. Your first biome.",
		Order = 1,
		Environment = { Temperature = 18, Humidity = 55, Growth = 80, ElementalEnergy = 20 },
		Species = { "Mossling", "Pebbleback", "Brookhopper" },
		MutationModifiers = { MossyCoat = 1.5, LeafMarkings = 1.25 },
		Catalysts = { "Dewdrop", "FertileSoil", "AncientSeed" },
		Unlock = { Level = 1, MutationsDiscovered = 0, Coins = 0 },
		Theme = { Accent = Color3.fromRGB(80, 210, 100) },
		ShortName = "Meadow",
	},
	{
		Id = "FrostfallTundra",
		DisplayName = "Frostfall Tundra",
		Description = "Snowfields and frozen lakes. Snowstorms and Aurora Nights change what can form here.",
		Order = 2,
		Environment = { Temperature = -15, Humidity = 30, Growth = 10, ElementalEnergy = 40 },
		Species = { "Snowmote", "Frostfang", "Glimmerseal" },
		MutationModifiers = { FrostedCoat = 1.25 },
		Catalysts = { "FrostShard", "GlacierCrystal", "AuroraFragment" },
		Unlock = { Level = 4, MutationsDiscovered = 6, Coins = 250 },
		Theme = { Accent = Color3.fromRGB(110, 190, 255) },
		ShortName = "Tundra",
	},
	{
		Id = "EmberpeakVolcano",
		DisplayName = "Emberpeak Volcano",
		Description = "Lava channels and glowing vents. Ashfall and Magma Surges change what forms here.",
		Order = 3,
		Environment = { Temperature = 45, Humidity = 10, Growth = 5, ElementalEnergy = 70 },
		Species = { "Cindermite", "Basaltback", "Ashwing" },
		MutationModifiers = { EmberFlecks = 1.25 },
		Catalysts = { "Emberstone", "ObsidianShard", "MagmaHeart" },
		Unlock = { Level = 7, MutationsDiscovered = 14, Coins = 600 },
		Theme = { Accent = Color3.fromRGB(255, 110, 40) },
		ShortName = "Volcano",
	},
	{
		Id = "TidebreakCoast",
		DisplayName = "Tidebreak Coast",
		Description = "Beaches, reefs and tide pools. King Tides and Bioluminescent Nights change what forms here.",
		Order = 4,
		Environment = { Temperature = 22, Humidity = 90, Growth = 40, ElementalEnergy = 45 },
		Species = { "Reefling", "Coralback", "Seamist" },
		MutationModifiers = { ShellPattern = 1.25 },
		Catalysts = { "Pearl", "CoralFragment", "Tideglass" },
		Unlock = { Level = 9, MutationsDiscovered = 22, Coins = 1000 },
		Theme = { Accent = Color3.fromRGB(60, 200, 220) },
		ShortName = "Coast",
	},
	{
		Id = "ThunderwildHighlands",
		DisplayName = "Thunderwild Highlands",
		Description = "Windswept ridges and lightning rods. Lightning Storms and Static Surges change what forms here.",
		Order = 5,
		Environment = { Temperature = 12, Humidity = 50, ElementalEnergy = 60, Charge = 50 },
		Species = { "Sparkhare", "Stormcrest", "Thunderhorn" },
		MutationModifiers = { StaticFur = 1.25 },
		Catalysts = { "ChargedShard", "Stormglass", "Thunderstone" },
		Unlock = { Level = 12, MutationsDiscovered = 32, Coins = 1600 },
		Theme = { Accent = Color3.fromRGB(255, 225, 70) },
		ShortName = "Highlands",
	},
	{
		Id = "ToxicBloomSwamp",
		DisplayName = "Toxic Bloom Swamp",
		Description = "Murky pools and giant mushrooms. Sporefall and Toxic Blooms change what forms here.",
		Order = 6,
		Environment = { Temperature = 28, Humidity = 95, ElementalEnergy = 55, Toxicity = 50 },
		Species = { "Sporeling", "Miretoad", "Venomtail" },
		MutationModifiers = { MossPatches = 1.25 },
		Catalysts = { "ToxicSpore", "VenomSac", "AncientMushroom" },
		Unlock = { Level = 14, MutationsDiscovered = 42, Coins = 2500 },
		Theme = { Accent = Color3.fromRGB(150, 225, 60) },
		ShortName = "Swamp",
	},
} :: { Biome }

Biomes.ById = {} :: { [string]: Biome }
for _, b in Biomes.List do
	Biomes.ById[b.Id] = b
end

return Biomes
