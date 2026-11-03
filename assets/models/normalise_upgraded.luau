-- Run in Studio (Edit datamodel, via MCP execute_luau) after File > Import 3D of
-- assets/models/Monsters16.fbx (built by rig_upgrade.py). Splits the import into
-- ReplicatedStorage.MonsterMeshes.<Species> templates in rig space:
--   * pieces are named "<Species>_<Piece>"; "<Species>_Origin" marks the rig origin,
--   * the importer brings our FBX in turned 180 deg about Y, so pieces are turned back,
--   * baked textures become SurfaceAppearances so MonsterVisuals can tint them.
-- These species have no MeshTones/RigAnchors, so MonsterVisuals styles them from
-- their part rigs ("from rig" mode).
local IMPORT_NAME = "Monsters16"
local TURN = CFrame.Angles(0, math.pi, 0)

local import = workspace:FindFirstChild(IMPORT_NAME)
assert(import, "no imported " .. IMPORT_NAME .. " model in Workspace")

local origins: { [string]: Vector3 } = {}
local pieces: { [string]: { MeshPart } } = {}
for _, p in import:GetDescendants() do
	if p:IsA("MeshPart") then
		local species, piece = p.Name:match("^([^_]+)_(.+)$")
		if species then
			piece = piece:gsub("%.%d+$", "")
			if piece == "Origin" then
				origins[species] = p.Position
			else
				pieces[species] = pieces[species] or {}
				table.insert(pieces[species], p)
			end
		end
	end
end

local folder = game.ReplicatedStorage:FindFirstChild("MonsterMeshes") or Instance.new("Folder")
folder.Name = "MonsterMeshes"
folder.Parent = game.ReplicatedStorage

local made = {}
for species, list in pieces do
	local origin = assert(origins[species], "no origin marker for " .. species)
	local m = Instance.new("Model")
	m.Name = species
	for _, p in list do
		local piece = p:Clone()
		piece:ClearAllChildren()
		piece.Name = p.Name:match("^[^_]+_(.+)$"):gsub("%.%d+$", "")
		piece.CFrame = TURN * CFrame.new(origin):ToObjectSpace(p.CFrame)
		piece.Anchored = true
		piece.CanCollide = false
		piece.CanQuery = false
		piece.CanTouch = false
		piece.CastShadow = false
		if piece.TextureID ~= "" then
			local sa = Instance.new("SurfaceAppearance")
			sa.ColorMap = piece.TextureID
			piece:SetAttribute("ColorMap", piece.TextureID) -- game scripts can't read ColorMap (viewports need it)
			sa.Parent = piece
			piece.TextureID = ""
		end
		piece.Parent = m
	end
	m.PrimaryPart = m:FindFirstChild("Body") :: BasePart
	local old = folder:FindFirstChild(species)
	if old then
		old:Destroy()
	end
	m.Parent = folder
	table.insert(made, string.format("%s(%d)", species, #list))
end
import:Destroy()
table.sort(made)
return #made .. " species: " .. table.concat(made, ", ")
