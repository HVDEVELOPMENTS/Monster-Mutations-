--!strict
-- Biome environmental events on a fixed, public, repeating schedule.
-- The schedule is a pure function of Unix time, so every server and every client
-- agrees on exactly when each event starts and ends - no hidden timers, and no
-- dependence on real-world weather. Each event repeats every cycle, so a player
-- who can't play at one time gets another window shortly after.
--
-- While active, an event can:
--   * shift environment variables (EnvironmentDelta, added to the biome's values),
--   * multiply listed mutations' within-tier weights (MutationModifiers),
--   * satisfy mutations that list it in RequiredEvents.
-- The event state is captured when an incubation STARTS (that is when it rolls).

export type Event = {
	Id: string,
	DisplayName: string,
	Description: string,
	Biome: string,
	StartOffset: number, -- seconds into the biome cycle
	Duration: number,
	EnvironmentDelta: { [string]: number },
	MutationModifiers: { [string]: number },
	Color: Color3,
}

local Events = {}

-- Seconds per repeating cycle, per biome.
Events.CycleSeconds = {
	FrostfallTundra = 15 * 60,
	EmberpeakVolcano = 12 * 60,
	TidebreakCoast = 16 * 60,
	ThunderwildHighlands = 14 * 60,
	ToxicBloomSwamp = 13 * 60,
}

Events.List = {
	{
		Id = "Snowstorm",
		DisplayName = "Snowstorm",
		Description = "Temperature -15 (enables Permafrost Veins). Blizzard Heart x2, Snowdrift Aura x1.5, Frozen Armour x1.5.",
		Biome = "FrostfallTundra",
		StartOffset = 0,
		Duration = 4 * 60,
		EnvironmentDelta = { Temperature = -15, ElementalEnergy = 20 },
		MutationModifiers = { BlizzardHeart = 2, SnowdriftAura = 1.5, FrozenArmour = 1.5 },
		Color = Color3.fromRGB(200, 225, 255),
	},
	{
		Id = "AuroraNight",
		DisplayName = "Aurora Night",
		Description = "Unlocks Aurora Markings and Aurora Sovereign. Glacier Scales x1.5.",
		Biome = "FrostfallTundra",
		StartOffset = 7.5 * 60,
		Duration = 4 * 60,
		EnvironmentDelta = {},
		MutationModifiers = { GlacierScales = 1.5 },
		Color = Color3.fromRGB(120, 255, 190),
	},
	{
		Id = "Ashfall",
		DisplayName = "Ashfall",
		Description = "Ash drifts down. Ashen Pattern x2, Smoke Aura x1.5.",
		Biome = "EmberpeakVolcano",
		StartOffset = 0,
		Duration = 3 * 60,
		EnvironmentDelta = { Humidity = -5 },
		MutationModifiers = { AshenPattern = 2, SmokeAura = 1.5 },
		Color = Color3.fromRGB(150, 140, 135),
	},
	{
		Id = "MagmaSurge",
		DisplayName = "Magma Surge",
		Description = "Temperature +25 (enables Magmatic Core). Eruption Heart x2.",
		Biome = "EmberpeakVolcano",
		StartOffset = 6 * 60,
		Duration = 3 * 60,
		EnvironmentDelta = { Temperature = 25, ElementalEnergy = 20 },
		MutationModifiers = { EruptionHeart = 2 },
		Color = Color3.fromRGB(255, 120, 40),
	},
	{
		Id = "KingTide",
		DisplayName = "King Tide",
		Description = "Energy +30. Tidal Heart x2, Kelp Tail x1.5.",
		Biome = "TidebreakCoast",
		StartOffset = 0,
		Duration = 4 * 60,
		EnvironmentDelta = { ElementalEnergy = 30 },
		MutationModifiers = { TidalHeart = 2, KelpTail = 1.5 },
		Color = Color3.fromRGB(70, 160, 255),
	},
	{
		Id = "BioluminescentNight",
		DisplayName = "Bioluminescent Night",
		Description = "Unlocks Bioluminescent Reef. Seafoam Aura x1.5.",
		Biome = "TidebreakCoast",
		StartOffset = 8 * 60,
		Duration = 4 * 60,
		EnvironmentDelta = {},
		MutationModifiers = { SeafoamAura = 1.5 },
		Color = Color3.fromRGB(80, 255, 220),
	},
	{
		Id = "LightningStorm",
		DisplayName = "Lightning Storm",
		Description = "Charge +40 (enables Lightning Core). Tempest Heart x2.",
		Biome = "ThunderwildHighlands",
		StartOffset = 0,
		Duration = 4 * 60,
		EnvironmentDelta = { Charge = 40, Humidity = 20 },
		MutationModifiers = { TempestHeart = 2 },
		Color = Color3.fromRGB(255, 230, 80),
	},
	{
		Id = "StaticSurge",
		DisplayName = "Static Surge",
		Description = "Living Lightning x2, Static Aura x1.5.",
		Biome = "ThunderwildHighlands",
		StartOffset = 7 * 60,
		Duration = 3 * 60,
		EnvironmentDelta = { Charge = 15 },
		MutationModifiers = { LivingLightning = 2, StaticAura = 1.5 },
		Color = Color3.fromRGB(170, 140, 255),
	},
	{
		Id = "Sporefall",
		DisplayName = "Sporefall",
		Description = "Unlocks Bioluminescent Spores. Fungal Frills x1.5.",
		Biome = "ToxicBloomSwamp",
		StartOffset = 0,
		Duration = 4 * 60,
		EnvironmentDelta = {},
		MutationModifiers = { FungalFrills = 1.5 },
		Color = Color3.fromRGB(190, 255, 120),
	},
	{
		Id = "ToxicBloom",
		DisplayName = "Toxic Bloom",
		Description = "Toxicity +35 (enables Venom Core). Fungal Sovereign x2.",
		Biome = "ToxicBloomSwamp",
		StartOffset = 7 * 60,
		Duration = 3 * 60,
		EnvironmentDelta = { Toxicity = 35 },
		MutationModifiers = { FungalSovereign = 2 },
		Color = Color3.fromRGB(140, 230, 60),
	},
} :: { Event }

Events.ById = {} :: { [string]: Event }
for _, e in Events.List do
	Events.ById[e.Id] = e
end

-- Active events for a biome at Unix time t: { [eventId] = endsAt }.
function Events.GetActive(biomeId: string, t: number): { [string]: number }
	local out = {}
	local cycle = Events.CycleSeconds[biomeId]
	if not cycle then
		return out
	end
	local cycleStart = t - (t % cycle)
	local pos = t % cycle
	for _, e in Events.List do
		if e.Biome == biomeId and pos >= e.StartOffset and pos < e.StartOffset + e.Duration then
			out[e.Id] = cycleStart + e.StartOffset + e.Duration
		end
	end
	return out
end

-- Next start time (>= t) of an event.
function Events.NextStart(eventId: string, t: number): number?
	local e = Events.ById[eventId]
	local cycle = e and Events.CycleSeconds[e.Biome]
	if not e or not cycle then
		return nil
	end
	local cycleStart = t - (t % cycle)
	local start = cycleStart + e.StartOffset
	if start < t then
		start += cycle
	end
	return start
end

return Events
