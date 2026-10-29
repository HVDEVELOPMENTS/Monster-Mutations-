--!strict
-- Mutation categories and slot rules.
-- For each category, slot 1 is rolled with FillChance; each further slot (up to
-- MaxSlots) is rolled with ExtraSlotFillChance, only if the previous slot filled.
-- A filled slot then rolls a rarity tier; if no eligible mutation exists at that
-- tier the slot stays empty (no fallback), so advertised tier chances stay exact.
-- Order matters: later categories check compatibility against earlier picks.

export type Category = {
	Id: string,
	DisplayName: string,
	Order: number,
	MaxSlots: number,
	FillChance: number,
	ExtraSlotFillChance: number,
	Rolled: boolean?, -- false = never rolled directly (filled by hybrid recipes)
}

local Categories = {}

Categories.List = {
	{ Id = "Elemental", DisplayName = "Elemental", Order = 1, MaxSlots = 1, FillChance = 1.0, ExtraSlotFillChance = 0 },
	{ Id = "Physical", DisplayName = "Physical", Order = 2, MaxSlots = 2, FillChance = 0.55, ExtraSlotFillChance = 0.2 },
	{ Id = "Pattern", DisplayName = "Pattern", Order = 3, MaxSlots = 1, FillChance = 0.6, ExtraSlotFillChance = 0 },
	{ Id = "Aura", DisplayName = "Aura", Order = 4, MaxSlots = 1, FillChance = 0.3, ExtraSlotFillChance = 0 },
	{ Id = "Utility", DisplayName = "Utility", Order = 5, MaxSlots = 2, FillChance = 0.35, ExtraSlotFillChance = 0.1 },
	{ Id = "Hybrid", DisplayName = "Hybrid", Order = 6, MaxSlots = 1, FillChance = 0, ExtraSlotFillChance = 0, Rolled = false },
} :: { Category }

Categories.ById = {} :: { [string]: Category }
for _, c in Categories.List do
	Categories.ById[c.Id] = c
end

return Categories
