--!strict
-- Monster fusion ("alchemy"): two monsters of DIFFERENT species from the SAME
-- home biome fuse into a new monster of that biome's remaining species. Every
-- biome has three species, so each pair has exactly one result (checked by
-- Fusion_spec). The new monster's mutations are rolled like an incubation in
-- that biome; if both monsters were Rare or better, the result is guaranteed
-- Rare+ (the same guarantee as bad-luck protection). Both monsters are used up.

local Species = require(script.Parent.Species)
local Config = require(script.Parent.Config)

local Fusion = {}

-- Rarity tier both monsters need for the Rare+ guarantee.
Fusion.GuaranteeTier = 3

-- Species made by fusing species a and b, or nil (with a reason code).
function Fusion.ResultFor(a: string, b: string): (string?, string?)
	local sa, sb = Species.ById[a], Species.ById[b]
	if not sa or not sb then
		return nil, "BadRequest"
	end
	if a == b then
		return nil, "FuseSameSpecies"
	end
	if sa.HomeBiome ~= sb.HomeBiome then
		return nil, "FuseDifferentBiome"
	end
	for _, s in Species.List do
		if s.HomeBiome == sa.HomeBiome and s.Id ~= a and s.Id ~= b then
			return s.Id, nil
		end
	end
	return nil, "FuseNoResult"
end

-- Coins to fuse into `speciesId`: half its incubation cost (two monsters go in).
function Fusion.Cost(speciesId: string): number
	return math.ceil(Config.Species[speciesId].Cost / 2)
end

return Fusion
