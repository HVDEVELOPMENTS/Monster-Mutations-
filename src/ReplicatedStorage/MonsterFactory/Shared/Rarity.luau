--!strict
-- Rarity tiers. `Chance` is the probability of rolling this tier in a single
-- per-category tier roll (see MutationService). Chances sum to 1.
-- Colour is never the only signal: every tier also has a label, short code and glyph.
-- Glyphs use only shapes the UI font renders (circle, diamond, triangle, stars).

export type Tier = {
	Tier: number,
	Id: string,
	Name: string,
	Short: string,
	Glyph: string,
	Chance: number,
	Color: Color3,
	Scale: number, -- visual size multiplier, applied on top of the size gene
}

local Rarity = {}

Rarity.Tiers = {
	{ Tier = 1, Id = "Common", Name = "Common", Short = "C", Glyph = "●", Chance = 0.60, Color = Color3.fromRGB(190, 190, 190), Scale = 1.0 },
	{ Tier = 2, Id = "Uncommon", Name = "Uncommon", Short = "U", Glyph = "◆", Chance = 0.25, Color = Color3.fromRGB(90, 210, 90), Scale = 1.08 },
	{ Tier = 3, Id = "Rare", Name = "Rare", Short = "R", Glyph = "▲", Chance = 0.10, Color = Color3.fromRGB(70, 150, 255), Scale = 1.18 },
	{ Tier = 4, Id = "Epic", Name = "Epic", Short = "E", Glyph = "★", Chance = 0.04, Color = Color3.fromRGB(175, 90, 255), Scale = 1.3 },
	{ Tier = 5, Id = "Legendary", Name = "Legendary", Short = "L", Glyph = "★★", Chance = 0.009, Color = Color3.fromRGB(255, 170, 30), Scale = 1.45 },
	{ Tier = 6, Id = "Mythic", Name = "Mythic", Short = "M", Glyph = "★★★", Chance = 0.0009, Color = Color3.fromRGB(255, 70, 90), Scale = 1.6 },
	{ Tier = 7, Id = "Celestial", Name = "Celestial", Short = "CE", Glyph = "★★★★", Chance = 0.00009, Color = Color3.fromRGB(120, 230, 255), Scale = 1.8 },
	{ Tier = 8, Id = "Transcendent", Name = "Transcendent", Short = "T", Glyph = "★★★★★", Chance = 0.00001, Color = Color3.fromRGB(255, 255, 255), Scale = 2.0 },
} :: { Tier }

Rarity.Count = #Rarity.Tiers

function Rarity.Get(tier: number): Tier?
	return Rarity.Tiers[tier]
end

function Rarity.IsValid(tier: any): boolean
	return type(tier) == "number" and Rarity.Tiers[tier] ~= nil
end

return Rarity
