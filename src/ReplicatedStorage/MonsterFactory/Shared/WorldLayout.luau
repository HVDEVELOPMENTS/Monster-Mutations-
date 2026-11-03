--!strict
-- Zone layout: one large zone per biome, chained along -Z like a pet-simulator
-- world. Zone i+1 starts where zone i ends; a gate sits on the shared edge.
-- Shared so the server (teleports, trespass guard) and client (teleport menu)
-- agree with the WorldBuilder.

local WorldLayout = {}

WorldLayout.ZoneSize = 720 -- studs, square
WorldLayout.GateWidth = 24
-- +Z edge of the first zone. Fixed so the spawn and main chamber stay just inside
-- the meadow's entrance whatever ZoneSize is.
WorldLayout.EntranceZ = 60

export type Zone = { Biome: string, Center: Vector3, Spawn: Vector3 }

WorldLayout.Zones = {} :: { Zone }
local order = { "VerdantMeadows", "FrostfallTundra", "EmberpeakVolcano", "TidebreakCoast", "ThunderwildHighlands", "ToxicBloomSwamp" }
for i, biome in order do
	local center = Vector3.new(0, 0, WorldLayout.EntranceZ - WorldLayout.ZoneSize / 2 - (i - 1) * WorldLayout.ZoneSize)
	-- Spawn just inside the entrance (the +Z edge); the meadow uses the main spawn.
	local spawn = if i == 1 then Vector3.new(0, 3, 6) else center + Vector3.new(0, 3, WorldLayout.ZoneSize / 2 - 14)
	table.insert(WorldLayout.Zones, { Biome = biome, Center = center, Spawn = spawn })
end

WorldLayout.ByBiome = {} :: { [string]: Zone }
for _, z in WorldLayout.Zones do
	WorldLayout.ByBiome[z.Biome] = z
end

-- Zone containing a world position (nil if outside every zone).
function WorldLayout.ZoneAt(pos: Vector3): Zone?
	local half = WorldLayout.ZoneSize / 2
	for _, z in WorldLayout.Zones do
		if math.abs(pos.X - z.Center.X) <= half and math.abs(pos.Z - z.Center.Z) <= half then
			return z
		end
	end
	return nil
end

return WorldLayout
