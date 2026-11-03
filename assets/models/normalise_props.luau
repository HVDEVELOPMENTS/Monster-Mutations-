-- Run in Studio (Edit datamodel, via MCP execute_luau) after File > Import 3D of
-- a prop pack: MeadowProps.fbx (IMPORT_NAME = "MeadowProps", pieces
-- "<Prop>_<Piece>", one set "Meadow") or BiomeProps.fbx (IMPORT_NAME =
-- "BiomeProps", pieces "<Biome>-<Prop>_<Piece>", one set per biome).
-- Groups the pieces into ServerStorage.WorldAssets.<Set>.<Prop> models whose
-- pivot is the prop's bottom centre, ready for WorldBuilder to clone.
--   * Lava / Spark / Bloom pieces glow (Neon in their colour, no texture).
--   * Ice / Crystal / Obsidian pieces are glassy (texture kept).
--   * The meadow's LeafCard piece only carries the falling-leaf sprite: its
--     texture id becomes the set's "LeafTexture" attribute and the card is dropped.
local IMPORT_NAME = "BiomeProps"
local DEFAULT_SET = "Meadow" -- for names without a "<Set>-" prefix

local NO_COLLIDE = { Foliage = true, Blades = true, Petals = true, Fronds = true, Pads = true, Range = true, Lava = true, Bloom = true, Spark = true }
local NO_SHADOW = { Blades = true, Petals = true, Fronds = true, Pads = true, Lava = true, Bloom = true, Spark = true }
local GLOW = {
	Lava = Color3.fromRGB(255, 120, 30),
	Spark = Color3.fromRGB(255, 235, 120),
	Bloom = Color3.fromRGB(90, 255, 120),
}
-- Darkening tints ("<Set>/<Prop>/<Piece>"): baked colours come out lighter in
-- Roblox than in Blender, so these become SurfaceAppearances with a colour tint.
local TINT = {
	["EmberpeakVolcano/Volcano/Rock"] = Color3.fromRGB(80, 66, 62),
	["EmberpeakVolcano/BasaltColumns/Rock"] = Color3.fromRGB(110, 102, 102),
	["EmberpeakVolcano/LavaRock/Rock"] = Color3.fromRGB(120, 100, 95),
	["EmberpeakVolcano/Range/Rock"] = Color3.fromRGB(110, 95, 92),
	["EmberpeakVolcano/DeadTree/Trunk"] = Color3.fromRGB(95, 80, 75),
	["TidebreakCoast/SeaRock/Rock"] = Color3.fromRGB(150, 140, 130),
	["TidebreakCoast/Range/Rock"] = Color3.fromRGB(175, 165, 155),
	["ThunderwildHighlands/Boulder/Rock"] = Color3.fromRGB(140, 135, 145),
	["ThunderwildHighlands/StoneArch/Rock"] = Color3.fromRGB(140, 135, 145),
	["ThunderwildHighlands/Range/Rock"] = Color3.fromRGB(150, 145, 160),
	["ToxicBloomSwamp/Willow/Foliage"] = Color3.fromRGB(150, 170, 120),
	["ToxicBloomSwamp/Range/Rock"] = Color3.fromRGB(140, 150, 120),
}
local GLASS = {
	Ice = { Color = Color3.fromRGB(190, 230, 255), Transparency = 0.25 },
	Crystal = { Color = Color3.fromRGB(255, 225, 120), Transparency = 0.15 },
	Obsidian = { Color = Color3.fromRGB(40, 30, 55), Transparency = 0.05 },
}

local import = workspace:FindFirstChild(IMPORT_NAME)
assert(import, "no imported " .. IMPORT_NAME .. " model in Workspace")

-- sets[set][prop] = { MeshPart }
local sets: { [string]: { [string]: { MeshPart } } } = {}
local leafTextures: { [string]: string } = {}
for _, p in import:GetDescendants() do
	if p:IsA("MeshPart") then
		local name = p.Name:gsub("%.%d+$", "")
		local set, rest = name:match("^([^%-]+)%-(.+)$")
		if not set then
			set, rest = DEFAULT_SET, name
		end
		local prop = rest:match("^([^_]+)_")
		if prop == "LeafCard" then
			leafTextures[set] = p.TextureID
		elseif prop then
			sets[set] = sets[set] or {}
			sets[set][prop] = sets[set][prop] or {}
			table.insert(sets[set][prop], p)
		end
	end
end

local root = game.ServerStorage:FindFirstChild("WorldAssets") or Instance.new("Folder")
root.Name = "WorldAssets"
root.Parent = game.ServerStorage

local made = {}
for setName, props in sets do
	local old = root:FindFirstChild(setName)
	if old then
		old:Destroy()
	end
	local set = Instance.new("Folder")
	set.Name = setName
	if leafTextures[setName] then
		set:SetAttribute("LeafTexture", leafTextures[setName])
	end
	local list = {}
	for prop, parts in props do
		local lo, hi = Vector3.one * math.huge, -Vector3.one * math.huge
		for _, p in parts do
			local half = p.Size / 2
			lo = lo:Min(p.Position - half)
			hi = hi:Max(p.Position + half)
		end
		local base = Vector3.new((lo.X + hi.X) / 2, lo.Y, (lo.Z + hi.Z) / 2)
		local m = Instance.new("Model")
		m.Name = prop
		for _, p in parts do
			local piece = p:Clone()
			piece:ClearAllChildren()
			local pieceName = p.Name:gsub("%.%d+$", ""):match("_([^_]+)$")
			piece.Name = pieceName
			piece.CFrame = p.CFrame - base
			piece.Anchored = true
			piece.CanTouch = false
			piece.CanCollide = not NO_COLLIDE[pieceName] and prop ~= "Range"
			piece.CanQuery = piece.CanCollide
			piece.CastShadow = not NO_SHADOW[pieceName]
			if GLOW[pieceName] then
				piece.TextureID = ""
				piece.Material = Enum.Material.Neon
				piece.Color = GLOW[pieceName]
			elseif GLASS[pieceName] then
				piece.Material = Enum.Material.Glass
				piece.Color = GLASS[pieceName].Color
				piece.Transparency = GLASS[pieceName].Transparency
			end
			local tint = TINT[setName .. "/" .. prop .. "/" .. pieceName]
			if tint and piece.TextureID ~= "" then
				local sa = Instance.new("SurfaceAppearance")
				sa.ColorMap = piece.TextureID
				sa.AlphaMode = Enum.AlphaMode.Overlay
				sa.Color = tint
				sa.Parent = piece
				piece:SetAttribute("ColorMap", piece.TextureID)
				piece.TextureID = ""
			end
			piece.Parent = m
		end
		m.WorldPivot = CFrame.new()
		m.Parent = set
		local size = hi - lo
		table.insert(list, string.format("%s(%d, %.0fx%.0fx%.0f)", prop, #parts, size.X, size.Y, size.Z))
	end
	set.Parent = root
	table.sort(list)
	table.insert(made, setName .. ": " .. table.concat(list, ", "))
end
import:Destroy()
table.sort(made)
return table.concat(made, "\n")
