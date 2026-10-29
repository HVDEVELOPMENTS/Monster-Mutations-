--!strict
-- Catalysts / genetic materials.
-- Effects:
--   { Type = "TierMultiplier", Category = "Pattern", Tier = 3, Multiplier = 1.5 }
--       multiplies one tier's weight in one category's tier roll (then renormalised,
--       so the odds shown to the player change accordingly).
--   { Type = "MutationMultiplier", MutationId = "X", Multiplier = 2 }
--       multiplies one mutation's weight inside its tier pool only.
-- Catalysts can also *unlock* mutations that list them in RequiredCatalysts.

export type Effect = {
	Type: string,
	Category: string?,
	Tier: number?,
	MutationId: string?,
	Multiplier: number,
}

export type Material = {
	Id: string,
	DisplayName: string,
	Description: string,
	RarityTier: number,
	SourceBiome: string,
	Family: string,
	Consumable: boolean,
	StackLimit: number,
	Effects: { Effect },
}

local Materials = {}

Materials.List = {
	{ Id = "Dewdrop", DisplayName = "Dewdrop", Family = "Organic", RarityTier = 1, SourceBiome = "VerdantMeadows",
		Description = "Unlocks Crystal Dew and doubles Dewdrop Eyes weight.", Consumable = true, StackLimit = 999,
		Effects = { { Type = "MutationMultiplier", MutationId = "DewdropEyes", Multiplier = 2 } } },
	{ Id = "FertileSoil", DisplayName = "Fertile Soil", Family = "Organic", RarityTier = 2, SourceBiome = "VerdantMeadows",
		Description = "Raises the Rare tier weight of Physical mutations by 50%.", Consumable = true, StackLimit = 999,
		Effects = { { Type = "TierMultiplier", Category = "Physical", Tier = 3, Multiplier = 1.5 } } },
	{ Id = "AncientSeed", DisplayName = "Ancient Seed", Family = "Organic", RarityTier = 4, SourceBiome = "VerdantMeadows",
		Description = "Unlocks Elderwood Heart.", Consumable = true, StackLimit = 99,
		Effects = {} },
	{ Id = "FrostShard", DisplayName = "Frost Shard", Family = "Elemental", RarityTier = 1, SourceBiome = "FrostfallTundra",
		Description = "Unlocks Iceglass Armour and doubles Frozen Armour weight.", Consumable = true, StackLimit = 999,
		Effects = { { Type = "MutationMultiplier", MutationId = "FrozenArmour", Multiplier = 2 } } },
	{ Id = "GlacierCrystal", DisplayName = "Glacier Crystal", Family = "Mineral", RarityTier = 2, SourceBiome = "FrostfallTundra",
		Description = "Raises the Rare tier weight of Elemental mutations by 50%.", Consumable = true, StackLimit = 999,
		Effects = { { Type = "TierMultiplier", Category = "Elemental", Tier = 3, Multiplier = 1.5 } } },
	{ Id = "AuroraFragment", DisplayName = "Aurora Fragment", Family = "Celestial", RarityTier = 4, SourceBiome = "FrostfallTundra",
		Description = "During Aurora Night: unlocks Aurora Sovereign and doubles Aurora Markings weight.", Consumable = true, StackLimit = 99,
		Effects = { { Type = "MutationMultiplier", MutationId = "AuroraMarkings", Multiplier = 2 } } },
	{ Id = "Emberstone", DisplayName = "Emberstone", Family = "Elemental", RarityTier = 1, SourceBiome = "EmberpeakVolcano",
		Description = "Unlocks Volcanic Armour and doubles Ember Flecks weight.", Consumable = true, StackLimit = 999,
		Effects = { { Type = "MutationMultiplier", MutationId = "EmberFlecks", Multiplier = 2 } } },
	{ Id = "ObsidianShard", DisplayName = "Obsidian Shard", Family = "Mineral", RarityTier = 2, SourceBiome = "EmberpeakVolcano",
		Description = "Raises the Epic tier weight of Physical mutations by 50%.", Consumable = true, StackLimit = 999,
		Effects = { { Type = "TierMultiplier", Category = "Physical", Tier = 4, Multiplier = 1.5 } } },
	{ Id = "MagmaHeart", DisplayName = "Magma Heart", Family = "Elemental", RarityTier = 4, SourceBiome = "EmberpeakVolcano",
		Description = "Unlocks Caldera Sovereign and doubles Magmatic Core weight.", Consumable = true, StackLimit = 99,
		Effects = { { Type = "MutationMultiplier", MutationId = "MagmaticCore", Multiplier = 2 } } },
	{ Id = "Pearl", DisplayName = "Pearl", Family = "Mineral", RarityTier = 1, SourceBiome = "TidebreakCoast",
		Description = "Unlocks Pearl Armour and doubles Pearl Eyes weight.", Consumable = true, StackLimit = 999,
		Effects = { { Type = "MutationMultiplier", MutationId = "PearlEyes", Multiplier = 2 } } },
	{ Id = "CoralFragment", DisplayName = "Coral Fragment", Family = "Organic", RarityTier = 2, SourceBiome = "TidebreakCoast",
		Description = "Raises the Rare tier weight of Physical mutations by 50%.", Consumable = true, StackLimit = 999,
		Effects = { { Type = "TierMultiplier", Category = "Physical", Tier = 3, Multiplier = 1.5 } } },
	{ Id = "Tideglass", DisplayName = "Tideglass", Family = "Mineral", RarityTier = 4, SourceBiome = "TidebreakCoast",
		Description = "Doubles the Legendary tier weight of Elemental mutations.", Consumable = true, StackLimit = 99,
		Effects = { { Type = "TierMultiplier", Category = "Elemental", Tier = 5, Multiplier = 2 } } },
	{ Id = "ChargedShard", DisplayName = "Charged Shard", Family = "Elemental", RarityTier = 1, SourceBiome = "ThunderwildHighlands",
		Description = "Doubles Spark Tail weight.", Consumable = true, StackLimit = 999,
		Effects = { { Type = "MutationMultiplier", MutationId = "SparkTail", Multiplier = 2 } } },
	{ Id = "Stormglass", DisplayName = "Stormglass", Family = "Mineral", RarityTier = 2, SourceBiome = "ThunderwildHighlands",
		Description = "Unlocks Stormglass Scales; Epic Elemental tier weight x1.5.", Consumable = true, StackLimit = 999,
		Effects = { { Type = "TierMultiplier", Category = "Elemental", Tier = 4, Multiplier = 1.5 } } },
	{ Id = "Thunderstone", DisplayName = "Thunderstone", Family = "Elemental", RarityTier = 4, SourceBiome = "ThunderwildHighlands",
		Description = "Unlocks Stormbringer.", Consumable = true, StackLimit = 99, Effects = {} },
	{ Id = "ToxicSpore", DisplayName = "Toxic Spore", Family = "Organic", RarityTier = 1, SourceBiome = "ToxicBloomSwamp",
		Description = "Doubles Spotted Skin weight.", Consumable = true, StackLimit = 999,
		Effects = { { Type = "MutationMultiplier", MutationId = "SpottedSkin", Multiplier = 2 } } },
	{ Id = "VenomSac", DisplayName = "Venom Sac", Family = "Organic", RarityTier = 2, SourceBiome = "ToxicBloomSwamp",
		Description = "Unlocks Corrosive Armour and doubles Venom Stinger weight.", Consumable = true, StackLimit = 999,
		Effects = { { Type = "MutationMultiplier", MutationId = "VenomStinger", Multiplier = 2 } } },
	{ Id = "AncientMushroom", DisplayName = "Ancient Mushroom", Family = "Organic", RarityTier = 4, SourceBiome = "ToxicBloomSwamp",
		Description = "Unlocks Corrupted Garden; Legendary Aura tier weight x2.", Consumable = true, StackLimit = 99,
		Effects = { { Type = "TierMultiplier", Category = "Aura", Tier = 5, Multiplier = 2 } } },
} :: { Material }

Materials.ById = {} :: { [string]: Material }
for _, m in Materials.List do
	Materials.ById[m.Id] = m
end

-- Max catalysts usable in one incubation.
Materials.MaxPerIncubation = 3

return Materials
