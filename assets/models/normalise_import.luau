-- Run in Studio (Edit datamodel, via the MCP execute_luau tool) after File > Import 3D
-- of assets/models/<Species>.fbx. Moves the imported model into
-- ReplicatedStorage.MonsterMeshes.<Species> in rig space:
--   * strips Blender's ".001" name suffixes,
--   * turns it to face -Z (the importer brings our FBX in facing +Z),
--   * puts the Body centre at BodyCenter (Roblox rig coordinates from the Blender script),
--   * flattens the hierarchy and sets cheap part flags,
--   * turns each baked TextureID into a SurfaceAppearance, so MonsterVisuals can
--     tint it with the palette colour and (optionally) make it glow: the texture
--     doubles as the emissive mask, so its bright areas (lava cracks) emit.
-- Extra copies of the same import left in Workspace are removed. Run with
-- SPECIES = nil to only (re)apply the SurfaceAppearance step to existing templates.
local SPECIES: string? = "Mossling"
local SETTINGS = {
	-- BodyCenter = Body bounding-box centre printed by the Blender script.
	Mossling = { BodyCenter = Vector3.new(0, 1.855, 0) },
	Cindermite = {
		BodyCenter = Vector3.new(0, 1.854, 0.009),
		Emissive = { Strength = 3, Tint = Color3.fromRGB(255, 150, 60) },
	},
}
local TURN = CFrame.Angles(0, math.pi, 0)

local function baseName(name: string): string
	return (name:gsub("%.%d+$", ""))
end
local function findBody(m: Instance): BasePart?
	for _, d in m:GetDescendants() do
		if d:IsA("MeshPart") and baseName(d.Name) == "Body" then
			return d
		end
	end
	return nil
end

-- TextureID -> SurfaceAppearance (+ emissive). Idempotent.
local function applySurface(template: Model, settings)
	for _, p in template:GetChildren() do
		if p:IsA("MeshPart") then
			local sa = p:FindFirstChildOfClass("SurfaceAppearance")
			if p.TextureID ~= "" and not sa then
				sa = Instance.new("SurfaceAppearance")
				sa.ColorMap = p.TextureID
				p:SetAttribute("ColorMap", p.TextureID) -- game scripts can't read ColorMap (viewports need it)
				sa.Parent = p
				p.TextureID = ""
			end
			if sa and settings.Emissive then
				sa.EmissiveMaskContent = Content.fromUri(sa.ColorMap)
				sa.EmissiveStrength = settings.Emissive.Strength
				sa.EmissiveTint = settings.Emissive.Tint
			end
		end
	end
end

local folder = game.ReplicatedStorage:FindFirstChild("MonsterMeshes") or Instance.new("Folder")
folder.Name = "MonsterMeshes"
folder.Parent = game.ReplicatedStorage

if not SPECIES then
	local done = {}
	for _, t in folder:GetChildren() do
		if SETTINGS[t.Name] then
			applySurface(t, SETTINGS[t.Name])
			table.insert(done, t.Name)
		end
	end
	return "surfaces applied: " .. table.concat(done, ", ")
end

local settings = assert(SETTINGS[SPECIES], "no SETTINGS for " .. SPECIES)
local imports = {}
for _, m in workspace:GetChildren() do
	if m:IsA("Model") and m.Name == SPECIES and findBody(m) then
		table.insert(imports, m)
	end
end
assert(#imports > 0, "no imported " .. SPECIES .. " model in Workspace")

local src = imports[1]
local body = findBody(src) :: BasePart
local origin = body.Position
local out = Instance.new("Model")
out.Name = SPECIES
for _, p in src:GetDescendants() do
	if p:IsA("MeshPart") then
		local rel = CFrame.new(origin):ToObjectSpace(p.CFrame)
		local piece = p:Clone()
		piece:ClearAllChildren()
		piece.Name = baseName(p.Name)
		piece.CFrame = CFrame.new(settings.BodyCenter) * TURN * rel
		piece.Anchored = true
		piece.CanCollide = false
		piece.CanQuery = false
		piece.CanTouch = false
		piece.CastShadow = false
		piece.Parent = out
	end
end
out.PrimaryPart = out:FindFirstChild("Body") :: BasePart
applySurface(out, settings)

local old = folder:FindFirstChild(SPECIES)
if old then
	old:Destroy()
end
out.Parent = folder
for _, m in imports do
	m:Destroy()
end

local names = {}
for _, p in out:GetChildren() do
	table.insert(names, p.Name)
end
table.sort(names)
return string.format("%s: %d pieces [%s], %d import(s) cleared", SPECIES, #names, table.concat(names, ", "), #imports)
