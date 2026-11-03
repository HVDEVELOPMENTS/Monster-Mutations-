-- Edit-time world generator: one large themed zone per biome (WorldLayout), with
-- walls, a central path, decor, gather nodes, a Mutation Chamber, event props and
-- gates between zones. Run from the command bar / MCP:
--   require(game.ServerStorage.MonsterFactory.WorldBuilder).Build()
-- Build(sharedFolder?) accepts a fresh clone of Shared so Studio's module cache
-- never hands it stale definitions. Deterministic (seeded): rebuilding gives the
-- same world.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local WorldLayout = require(ReplicatedStorage.MonsterFactory.Shared.WorldLayout)
local Biomes = require(ReplicatedStorage.MonsterFactory.Shared.Biomes)
local Species = require(ReplicatedStorage.MonsterFactory.Shared.Species)
local Trainers = require(ReplicatedStorage.MonsterFactory.Shared.Trainers)

local WorldBuilder = {}

local V, C = Vector3.new, CFrame.new
local BLOCK, BALL, CYL = Enum.PartType.Block, Enum.PartType.Ball, Enum.PartType.Cylinder
local HALF = WorldLayout.ZoneSize / 2
local UP = CFrame.Angles(0, 0, math.pi / 2) -- cylinder axis X -> Y
-- Top of terrain fills. Smooth terrain's surface lands ~2 studs above a fill's
-- top, so this puts the walkable surface at y = 0.4 (measured in Studio).
local TERRAIN_TOP = -1.6

-- Themes were laid out for 180-stud zones. SCALE spreads landmarks out to the
-- real zone size, BIG grows landmarks (less than SCALE so they don't dwarf the
-- player), COUNT multiplies scattered decor (half the area growth, to keep the
-- part count sane). Set from WorldLayout in Build.
local SCALE, BIG, COUNT = 1, 1, 1
local function setScale()
	HALF = WorldLayout.ZoneSize / 2
	SCALE = WorldLayout.ZoneSize / 180
	BIG = math.sqrt(SCALE)
	COUNT = math.max(1, SCALE * SCALE / 2)
end
-- Scattered decor count for a 180-stud design count.
local function n(designCount: number): number
	return math.floor(designCount * COUNT + 0.5)
end
-- Landmark offset from the zone centre, given in 180-stud design units.
local function at(x: number, y: number, z: number): Vector3
	return V(x * SCALE, y, z * SCALE)
end

local function P(parent: Instance, name: string, shape: Enum.PartType, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, transparency: number?, collide: boolean?)
	local p = Instance.new("Part")
	p.Name = name
	local ellipsoid = shape == BALL and not (size.X == size.Y and size.Y == size.Z)
	p.Shape = if ellipsoid then BLOCK else shape
	if ellipsoid then
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = p
	end
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Transparency = transparency or 0
	p.Anchored = true
	p.CanCollide = collide ~= false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function emitter(parent: Instance, name: string, eventOnly: string?, props: { [string]: any })
	local e = Instance.new("ParticleEmitter")
	e.Name = name
	if eventOnly then
		e.Enabled = false
		e:SetAttribute("EventOnly", eventOnly)
	end
	for k, v in props do
		(e :: any)[k] = v
	end
	e.Parent = parent
	return e
end

local function surfaceText(part: BasePart, text: string, color: Color3)
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		local sg = Instance.new("SurfaceGui")
		sg.Face = face
		sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		sg.PixelsPerStud = 25
		sg.Parent = part
		local t = Instance.new("TextLabel")
		t.Size = UDim2.fromScale(1, 1)
		t.BackgroundTransparency = 1
		t.TextScaled = true
		t.Font = Enum.Font.FredokaOne
		t.TextColor3 = color
		t.TextStrokeTransparency = 0.2
		t.Text = text
		t.Parent = sg
	end
end

-- Random spot inside a zone, away from the path, chamber area and edges.
local function spot(rng: Random, center: Vector3, keepOut: { { Vector3 | number } }?)
	for _ = 1, 40 do
		local x = rng:NextNumber(-HALF + 8, HALF - 8)
		local z = rng:NextNumber(-HALF + 10, HALF - 10)
		local pos = center + V(x, 0, z)
		local ok = math.abs(x) > 11
		for _, k in keepOut or {} do
			if ((pos - (k[1] :: Vector3)) * V(1, 0, 1)).Magnitude < (k[2] :: number) then
				ok = false
			end
		end
		if ok then
			return pos
		end
	end
	return center + V(HALF - 12, 0, 0)
end

local function prompt(node: BasePart, objectText: string)
	local pr = Instance.new("ProximityPrompt")
	pr.ActionText = "Gather"
	pr.ObjectText = objectText
	pr.HoldDuration = 0.6
	pr.MaxActivationDistance = 12
	pr.RequiresLineOfSight = false
	pr.Parent = node
end

-- ===== Gather node models =====
local NodeMakers = {}
NodeMakers.DewdropFlower = function(m, pos)
	P(m, "Stem", CYL, V(2.2, 0.3, 0.3), C(pos + V(0, 1.1, 0)) * UP, Color3.fromRGB(80, 170, 70))
	for k = 0, 5 do
		local a = k / 6 * math.pi * 2
		P(m, "Petal", BALL, V(0.9, 0.3, 0.6), C(pos + V(math.cos(a) * 0.55, 2.35, math.sin(a) * 0.55)) * CFrame.Angles(0, -a, 0.3), Color3.fromRGB(255, 170, 210))
	end
	return P(m, "Node", BALL, V(0.8, 0.8, 0.8), C(pos + V(0, 2.45, 0)), Color3.fromRGB(180, 235, 255), Enum.Material.Glass, 0, false), "Dewdrop Flower"
end
NodeMakers.FrostCrystal = function(m, pos)
	for k = 1, 3 do
		local a = k / 3 * math.pi * 2
		P(m, "Shard", BLOCK, V(0.7, 1.6, 0.7), C(pos + V(math.cos(a) * 0.6, 1.2, math.sin(a) * 0.6)) * CFrame.Angles(math.cos(a) * 0.35, a, math.sin(a) * 0.35), Color3.fromRGB(160, 220, 255), Enum.Material.Glass)
	end
	local n = P(m, "Node", BLOCK, V(1.1, 2.8, 1.1), C(pos + V(0, 1.8, 0)) * CFrame.Angles(0, math.rad(45), 0), Color3.fromRGB(120, 200, 255), Enum.Material.Neon, 0.2, false)
	return n, "Frost Crystal"
end
NodeMakers.EmberVent = function(m, pos)
	P(m, "VentRock", CYL, V(1.4, 3.2, 3.2), C(pos + V(0, 1.1, 0)) * UP, Color3.fromRGB(60, 55, 58), Enum.Material.Basalt)
	local n = P(m, "Node", BALL, V(1.4, 1.4, 1.4), C(pos + V(0, 2.0, 0)), Color3.fromRGB(255, 120, 30), Enum.Material.Neon, 0.1, false)
	emitter(n, "VentSmoke", nil, { Texture = "rbxasset://textures/particles/smoke_main.dds", Rate = 4, Lifetime = NumberRange.new(2, 3), Speed = NumberRange.new(2, 3), Size = NumberSequence.new(0.6, 2), Color = ColorSequence.new(Color3.fromRGB(90, 85, 85)), Transparency = NumberSequence.new(0.4, 1), EmissionDirection = Enum.NormalId.Top })
	return n, "Ember Vent"
end
NodeMakers.TidePool = function(m, pos)
	P(m, "PoolRim", CYL, V(0.6, 4, 4), C(pos + V(0, 0.7, 0)) * UP, Color3.fromRGB(130, 125, 120), Enum.Material.Slate)
	local n = P(m, "Node", CYL, V(0.3, 3.2, 3.2), C(pos + V(0, 1.05, 0)) * UP, Color3.fromRGB(80, 200, 230), Enum.Material.Glass, 0.2, false)
	return n, "Tide Pool"
end
NodeMakers.LightningRod = function(m, pos)
	P(m, "RodBase", CYL, V(1, 2.6, 2.6), C(pos + V(0, 0.5, 0)) * UP, Color3.fromRGB(90, 90, 100), Enum.Material.Slate)
	P(m, "Rod", CYL, V(5, 0.4, 0.4), C(pos + V(0, 3, 0)) * UP, Color3.fromRGB(170, 170, 180), Enum.Material.Metal)
	local n = P(m, "Node", BALL, V(1.2, 1.2, 1.2), C(pos + V(0, 5.8, 0)), Color3.fromRGB(255, 230, 80), Enum.Material.Neon, 0, false)
	emitter(n, "RodSparks", nil, { Rate = 6, Lifetime = NumberRange.new(0.2, 0.4), Speed = NumberRange.new(3, 6), SpreadAngle = Vector2.new(180, 180), Size = NumberSequence.new(0.25, 0), Color = ColorSequence.new(Color3.fromRGB(255, 240, 140)), LightEmission = 1 })
	return n, "Lightning Rod"
end
NodeMakers.SporePod = function(m, pos)
	P(m, "PodStem", CYL, V(1.6, 0.8, 0.8), C(pos + V(0, 0.8, 0)) * UP, Color3.fromRGB(220, 210, 180))
	local n = P(m, "Node", BALL, V(2.2, 1.6, 2.2), C(pos + V(0, 2.0, 0)), Color3.fromRGB(150, 220, 70), Enum.Material.Neon, 0.15, false)
	emitter(n, "PodSpores", nil, { Texture = "rbxasset://textures/particles/sparkles_main.dds", Rate = 4, Lifetime = NumberRange.new(2, 3), Speed = NumberRange.new(0.5, 1), SpreadAngle = Vector2.new(180, 180), Size = NumberSequence.new(0.2), Color = ColorSequence.new(Color3.fromRGB(200, 255, 140)), LightEmission = 0.6 })
	return n, "Spore Pod"
end

-- ===== Decor =====
local function tree(m, pos, rng, trunkColor, leafColor, leafMat)
	local h = rng:NextNumber(7, 12)
	P(m, "Trunk", CYL, V(h, 1.4, 1.4), C(pos + V(0, h / 2, 0)) * UP, trunkColor, Enum.Material.Wood)
	for k = 0, 2 do
		local s = rng:NextNumber(5, 7.5) - k * 1.2
		P(m, "Canopy", BALL, V(s, s * 0.8, s), C(pos + V(rng:NextNumber(-0.8, 0.8), h + k * 1.8, rng:NextNumber(-0.8, 0.8))), leafColor:Lerp(Color3.new(0, 0, 0), k * 0.05), leafMat or Enum.Material.Grass)
	end
end

local function pine(m, pos, rng, snow)
	local h = rng:NextNumber(8, 13)
	P(m, "Trunk", CYL, V(h * 0.4, 1.0, 1.0), C(pos + V(0, h * 0.2, 0)) * UP, Color3.fromRGB(90, 65, 45), Enum.Material.Wood)
	for k = 0, 3 do
		local s = (h * 0.55) - k * 1.3
		P(m, "PineLayer", BALL, V(s, s * 0.55, s), C(pos + V(0, h * 0.35 + k * h * 0.17, 0)), if snow then Color3.fromRGB(235, 242, 250) else Color3.fromRGB(50, 110, 70), if snow then Enum.Material.Snow else Enum.Material.Grass)
	end
end

local function palm(m, pos, rng)
	local lean = rng:NextNumber(-0.25, 0.25)
	local top = pos
	for k = 0, 5 do
		local seg = C(pos + V(lean * k * 1.6, 1 + k * 1.6, 0))
		P(m, "PalmTrunk", CYL, V(1.7, 0.9 - k * 0.05, 0.9 - k * 0.05), seg * UP, Color3.fromRGB(150, 115, 75), Enum.Material.Wood)
		top = seg.Position
	end
	for k = 1, 6 do
		local a = k / 6 * math.pi * 2
		P(m, "Frond", BALL, V(5, 0.3, 1.4), C(top + V(math.cos(a) * 2.3, 0.3, math.sin(a) * 2.3)) * CFrame.Angles(0, -a, -0.35), Color3.fromRGB(70, 160, 70), Enum.Material.Grass)
	end
	P(m, "Coconut", BALL, V(0.8, 0.8, 0.8), C(top + V(0.4, -0.3, 0.2)), Color3.fromRGB(110, 80, 50))
end

local function rock(m, pos, rng, color, material)
	local s = rng:NextNumber(2, 5)
	P(m, "Rock", BALL, V(s * 1.3, s * 0.8, s), C(pos + V(0, s * 0.25, 0)) * CFrame.Angles(0, rng:NextNumber(0, 6.28), 0), color, material or Enum.Material.Slate)
end

-- ===== Blender prop sets (ServerStorage.WorldAssets.<Set>, see assets/models) =====
-- Themes use these when imported and fall back to the part decor above otherwise.
local function assetSet(name: string): Folder?
	local root = game:GetService("ServerStorage"):FindFirstChild("WorldAssets")
	return root and root:FindFirstChild(name) :: Folder?
end

-- Wind sway (driven client-side by the Ambience script): each tagged piece bends
-- about SwayBase by up to SwayAmp radians.
local SWAY = { Foliage = 0.035, Blades = 0.22, Petals = 0.22, Fronds = 0.07 }

local function leafFall(part: BasePart, texture: string)
	local e = Instance.new("ParticleEmitter")
	e.Name = "FallingLeaves"
	e.Texture = texture
	e.Rate = 0.5
	e.Lifetime = NumberRange.new(7, 10)
	e.Speed = NumberRange.new(0.3, 1)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Acceleration = V(0, -1.4, 0)
	e.Drag = 0.6
	e.WindAffectsDrag = true -- drifts with workspace.GlobalWind
	e.Rotation = NumberRange.new(0, 360)
	e.RotSpeed = NumberRange.new(-120, 120)
	e.Size = NumberSequence.new(0.45)
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.85, 0), NumberSequenceKeypoint.new(1, 1) })
	e.Shape = Enum.ParticleEmitterShape.Box
	e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	e.Parent = part
end

-- Clones prop `name` from `set` standing at pos (ground point), turned by yaw.
local function place(set: Folder, name: string, parent: Instance, pos: Vector3, yaw: number, scale: number): Model?
	local template = set:FindFirstChild(name) :: Model?
	if not template then
		return nil
	end
	local m = template:Clone()
	if scale ~= 1 then
		m:ScaleTo(scale)
	end
	m:PivotTo(CFrame.new(pos) * CFrame.Angles(0, yaw, 0))
	local leaf = set:GetAttribute("LeafTexture")
	for _, p in m:GetChildren() do
		local amp = SWAY[p.Name]
		if amp and p:IsA("BasePart") then
			p:SetAttribute("SwayBase", pos)
			p:SetAttribute("SwayAmp", amp)
			CollectionService:AddTag(p, "Sway")
			if p.Name == "Foliage" and leaf and (name == "Oak" or name == "Birch") then
				leafFall(p, leaf)
			end
		end
	end
	m.Parent = parent
	return m
end

-- Mountain ranges along both long sides of a zone, outside its walls (prop
-- "Mountain" in the meadow set, "Range" in the biome sets).
local function mountainRanges(set: Folder, parent: Instance, center: Vector3, rng: Random, propName: string?)
	local step = 330
	for _, side in { -1, 1 } do
		for z = -HALF + step / 2, HALF, step do
			local pos = center + V(side * (HALF + 100 + rng:NextNumber(0, 60)), 0, z + rng:NextNumber(-40, 40))
			place(set, propName or "Mountain", parent, pos, math.pi / 2 + rng:NextNumber(-0.2, 0.2) + (if side > 0 then math.pi else 0), rng:NextNumber(0.9, 1.4))
		end
	end
end

-- Scatters props from a set: list = { { Prop, designCount, minScale, maxScale } }.
local function scatter(set: Folder, parent: Instance, center: Vector3, rng: Random, keep, list)
	for _, e in list do
		for _ = 1, n(e[2]) do
			place(set, e[1], parent, spot(rng, center, keep), rng:NextNumber(0, 6.28), rng:NextNumber(e[3], e[4]))
		end
	end
end

-- Grass-like props grow in patches of `per` clumps.
local function patches(set: Folder, propName: string, parent: Instance, center: Vector3, rng: Random, keep, count: number, per: number)
	for _ = 1, count do
		local patch = spot(rng, center, keep)
		for _ = 1, per do
			local pos = patch + V(rng:NextNumber(-4, 4), 0.4, rng:NextNumber(-4, 4))
			place(set, propName, parent, pos, rng:NextNumber(0, 6.28), rng:NextNumber(0.7, 1.3))
		end
	end
end

-- ===== Zone themes =====
local Themes = {}

Themes.VerdantMeadows = {
	-- Terrain ground (the zone outgrew the 512-stud baseplate).
	Terrain = Enum.Material.Grass,
	Wall = { Color = Color3.fromRGB(55, 120, 55), Material = Enum.Material.Grass },
	Path = Color3.fromRGB(190, 160, 110),
	Node = "DewdropFlower",
	Decorate = function(m, center, rng, keep)
		for _, pond in { { at(-48, 0, -45), 34 }, { at(55, 0, 10), 26 }, { at(-40, 0, 50), 22 } } do
			local d = pond[2] * BIG
			-- Terrain water (waves, reflections) with a sandy rim. Carve to air first:
			-- filling water over solid terrain doesn't replace it.
			local pc = center + pond[1]
			workspace.Terrain:FillCylinder(C(pc + V(0, TERRAIN_TOP - 2, 0)), 4, d / 2 + 3, Enum.Material.Sand)
			workspace.Terrain:FillCylinder(C(pc + V(0, TERRAIN_TOP - 2.5, 0)), 5, d / 2, Enum.Material.Air)
			workspace.Terrain:FillCylinder(C(pc + V(0, TERRAIN_TOP - 2.5, 0)), 5, d / 2, Enum.Material.Water)
			table.insert(keep, { center + pond[1], d / 2 + 5 })
		end
		local props = assetSet("Meadow")
		if props then
			-- Blender props: oak/birch woods, bushes, mossy rocks, flowers, patches of
			-- swaying grass and mountain ranges beyond the walls.
			mountainRanges(props, m, center, rng)
			for _ = 1, n(22) do
				place(props, if rng:NextNumber() < 0.6 then "Oak" else "Birch", m, spot(rng, center, keep), rng:NextNumber(0, 6.28), rng:NextNumber(0.85, 1.3))
			end
			for _ = 1, n(30) do
				place(props, "Bush", m, spot(rng, center, keep), rng:NextNumber(0, 6.28), rng:NextNumber(0.8, 1.3))
			end
			for _ = 1, n(10) do
				place(props, if rng:NextNumber() < 0.5 then "RockA" else "RockB", m, spot(rng, center, keep), rng:NextNumber(0, 6.28), rng:NextNumber(0.7, 1.4))
			end
			for _ = 1, n(45) do
				place(props, "Flowers", m, spot(rng, center, keep), rng:NextNumber(0, 6.28), rng:NextNumber(0.8, 1.2))
			end
			for _ = 1, 420 do -- grass grows in patches
				local patch = spot(rng, center, keep)
				for _ = 1, 8 do
					local pos = patch + V(rng:NextNumber(-4, 4), 0.4, rng:NextNumber(-4, 4))
					place(props, "Grass", m, pos, rng:NextNumber(0, 6.28), rng:NextNumber(0.7, 1.3))
				end
			end
			return
		end
		for _ = 1, n(22) do
			tree(m, spot(rng, center, keep), rng, Color3.fromRGB(110, 75, 45), Color3.fromRGB(90, 175, 70))
		end
		for _ = 1, n(30) do
			local pos = spot(rng, center, keep)
			P(m, "Bush", BALL, V(4, 2.6, 3.4), C(pos + V(0, 1, 0)), Color3.fromRGB(70, 150, 60), Enum.Material.Grass)
		end
		for _ = 1, n(45) do
			local pos = spot(rng, center, keep)
			local col = ({ Color3.fromRGB(255, 120, 160), Color3.fromRGB(255, 220, 90), Color3.fromRGB(170, 130, 255), Color3.new(1, 1, 1) })[rng:NextInteger(1, 4)]
			P(m, "Flower", BALL, V(0.7, 0.4, 0.7), C(pos + V(0, 0.5, 0)), col, nil, 0, false)
		end
		for _ = 1, n(10) do
			rock(m, spot(rng, center, keep), rng, Color3.fromRGB(130, 130, 125))
		end
	end,
}

Themes.FrostfallTundra = {
	Terrain = Enum.Material.Snow,
	Wall = { Color = Color3.fromRGB(175, 215, 240), Material = Enum.Material.Glacier },
	Path = Color3.fromRGB(200, 215, 230),
	Node = "FrostCrystal",
	Decorate = function(m, center, rng, keep)
		local lake = 46 * BIG
		P(m, "FrozenLake", CYL, V(0.3, lake, lake), C(center + at(45, 0.55, -35)) * UP, Color3.fromRGB(170, 215, 245), Enum.Material.Ice)
		table.insert(keep, { center + at(45, 0, -35), lake / 2 + 3 })
		local props = assetSet("FrostfallTundra")
		if props then
			-- Blender props: snow-laden pines, ice spires, snowy rocks, frosted
			-- shrubs, pale grass and snowy peaks beyond the walls.
			mountainRanges(props, m, center, rng, "Range")
			scatter(props, m, center, rng, keep, {
				{ "SnowPine", 30, 0.85, 1.35 },
				{ "IceSpire", 14, 0.7, 1.4 },
				{ "SnowRock", 12, 0.7, 1.5 },
				{ "FrostBush", 18, 0.8, 1.3 },
			})
			patches(props, "FrozenGrass", m, center, rng, keep, 160, 6)
		else
			for _ = 1, n(30) do
				pine(m, spot(rng, center, keep), rng, true)
			end
			for _ = 1, n(22) do
				local pos = spot(rng, center, keep)
				local h = rng:NextNumber(4, 10)
				P(m, "IceCrystal", BLOCK, V(1.8, h, 1.8), C(pos + V(0, h / 2, 0)) * CFrame.Angles(rng:NextNumber(-0.3, 0.3), rng:NextNumber(0, 6.28), rng:NextNumber(-0.3, 0.3)), Color3.fromRGB(150, 210, 255), Enum.Material.Glass, 0.2)
			end
		end
		for _ = 1, n(16) do
			local pos = spot(rng, center, keep)
			P(m, "Snowdrift", BALL, V(7, 2.4, 5), C(pos + V(0, 0.6, 0)), Color3.fromRGB(245, 248, 255), Enum.Material.Snow)
		end
		-- Events
		local sky = P(m, "StormSky", BLOCK, V(WorldLayout.ZoneSize, 1, WorldLayout.ZoneSize), C(center + V(0, 45, 0)), Color3.new(1, 1, 1), nil, 1, false)
		sky.CanQuery = false
		emitter(sky, "SnowstormEmitter", "Snowstorm", { EmissionDirection = Enum.NormalId.Bottom, Rate = 400 * BIG, Lifetime = NumberRange.new(6, 8), Speed = NumberRange.new(6, 9), Size = NumberSequence.new(0.45), Color = ColorSequence.new(Color3.new(1, 1, 1)), LightEmission = 0.3, Acceleration = V(4, 0, 0) })
		local colors = { Color3.fromRGB(120, 255, 190), Color3.fromRGB(110, 200, 255), Color3.fromRGB(160, 120, 255) }
		for i = 0, 20 do
			local a = i / 20 * math.pi
			local r = P(m, "AuroraRibbon", BLOCK, V(14 * SCALE, 16 * BIG, 0.4), C(center + at(math.cos(a) * 80, 60 * BIG + math.sin(i * 0.8) * 4, -40 + math.sin(a) * 20)) * CFrame.Angles(0, -a + math.pi / 2, math.sin(i) * 0.2), colors[(i % 3) + 1], Enum.Material.Neon, 1, false)
			r.CanQuery = false
			r.CastShadow = false
			r:SetAttribute("EventOnly", "AuroraNight")
			r:SetAttribute("EventTransparency", 0.35)
		end
	end,
}

Themes.EmberpeakVolcano = {
	Terrain = Enum.Material.Basalt,
	Wall = { Color = Color3.fromRGB(60, 52, 55), Material = Enum.Material.Basalt },
	Path = Color3.fromRGB(90, 75, 70),
	Node = "EmberVent",
	Decorate = function(m, center, rng, keep)
		-- The volcano with a glowing crater and smoke: the Blender volcano (lava
		-- pool and rivers included) when imported, else stacked tapering rings.
		local vpos = center + at(48, 0, -40)
		local props = assetSet("EmberpeakVolcano")
		local craterAt, craterSize
		local volcanoModel = props and place(props, "Volcano", m, vpos, 0.6, 1.1)
		if volcanoModel then
			local h = volcanoModel:GetExtentsSize().Y
			craterAt, craterSize = vpos + V(0, h - 6, 0), 20
		else
			for k = 0, 6 do
				local r = (46 - k * 6) * BIG
				P(m, "Volcano", CYL, V(5 * BIG, r, r), C(vpos + V(0, (2.5 + k * 5) * BIG, 0)) * UP, Color3.fromRGB(70 - k * 3, 58 - k * 2, 58 - k * 2), Enum.Material.Basalt)
			end
			craterAt, craterSize = vpos + V(0, 35 * BIG + 0.5, 0), 8 * BIG
		end
		local crater = P(m, "Crater", CYL, V(1, craterSize, craterSize), C(craterAt) * UP, Color3.fromRGB(255, 110, 30), Enum.Material.Neon, if volcanoModel then 1 else 0)
		emitter(crater, "VolcanoSmoke", nil, { Texture = "rbxasset://textures/particles/smoke_main.dds", Rate = 12, Lifetime = NumberRange.new(6, 9), Speed = NumberRange.new(5, 8), Size = NumberSequence.new(4 * BIG, 12 * BIG), Color = ColorSequence.new(Color3.fromRGB(80, 75, 75)), Transparency = NumberSequence.new(0.3, 1), EmissionDirection = Enum.NormalId.Top })
		emitter(crater, "Eruption", "MagmaSurge", { Texture = "rbxasset://textures/particles/fire_main.dds", Rate = 80, Lifetime = NumberRange.new(1.5, 2.5), Speed = NumberRange.new(15, 25), Size = NumberSequence.new(3, 0.5), Color = ColorSequence.new(Color3.fromRGB(255, 180, 60), Color3.fromRGB(255, 60, 20)), LightEmission = 1, EmissionDirection = Enum.NormalId.Top, SpreadAngle = Vector2.new(20, 20), Acceleration = V(0, -20, 0) })
		table.insert(keep, { vpos, if volcanoModel then 110 else 30 * BIG })
		for i, z in { -20, 30 } do
			local river = P(m, "LavaRiver", BLOCK, V(80 * SCALE, 0.5, 5 * BIG), C(center + at(-45, 0.45, z)) * CFrame.Angles(0, (i - 1.5) * 0.3, 0), Color3.fromRGB(255, 110, 30), Enum.Material.Neon, 0, false)
			emitter(river, "SurgeFlames", "MagmaSurge", { Texture = "rbxasset://textures/particles/fire_main.dds", Rate = 60, Lifetime = NumberRange.new(0.8, 1.4), Speed = NumberRange.new(4, 7), Size = NumberSequence.new(1.6, 0), Color = ColorSequence.new(Color3.fromRGB(255, 160, 50), Color3.fromRGB(255, 60, 20)), EmissionDirection = Enum.NormalId.Top, LightEmission = 1 })
			local l = Instance.new("PointLight")
			l.Color = Color3.fromRGB(255, 120, 40)
			l.Range = 60
			l.Brightness = 3
			l.Enabled = false
			l:SetAttribute("EventOnly", "MagmaSurge")
			l.Parent = river
		end
		if props then
			-- Blender props: basalt columns, lava-veined rocks, charred trees,
			-- obsidian spires, ash grass and dark peaks beyond the walls.
			mountainRanges(props, m, center, rng, "Range")
			scatter(props, m, center, rng, keep, {
				{ "BasaltColumns", 16, 0.8, 1.6 },
				{ "LavaRock", 14, 0.7, 1.5 },
				{ "DeadTree", 16, 0.8, 1.3 },
				{ "ObsidianSpire", 10, 0.7, 1.3 },
			})
			patches(props, "AshGrass", m, center, rng, keep, 90, 5)
		else
			for _ = 1, n(26) do
				local pos = spot(rng, center, keep)
				local h = rng:NextNumber(4, 13)
				P(m, "Spire", BLOCK, V(2.6, h, 2.6), C(pos + V(0, h / 2, 0)) * CFrame.Angles(rng:NextNumber(-0.2, 0.2), rng:NextNumber(0, 6.28), rng:NextNumber(-0.2, 0.2)), Color3.fromRGB(70, 60, 62), Enum.Material.Basalt)
				if rng:NextNumber() < 0.4 then
					P(m, "LavaGlow", BALL, V(1, 1, 1), C(pos + V(0, h + 0.3, 0)), Color3.fromRGB(255, 130, 40), Enum.Material.Neon, 0, false)
				end
			end
			for _ = 1, n(16) do
				rock(m, spot(rng, center, keep), rng, Color3.fromRGB(25, 20, 30), Enum.Material.Glass)
			end
		end
		local sky = P(m, "AshSky", BLOCK, V(WorldLayout.ZoneSize, 1, WorldLayout.ZoneSize), C(center + V(0, 50, 0)), Color3.new(1, 1, 1), nil, 1, false)
		sky.CanQuery = false
		emitter(sky, "AshfallEmitter", "Ashfall", { EmissionDirection = Enum.NormalId.Bottom, Rate = 300 * BIG, Lifetime = NumberRange.new(7, 9), Speed = NumberRange.new(4, 6), Size = NumberSequence.new(0.4), Color = ColorSequence.new(Color3.fromRGB(110, 105, 105)), Acceleration = V(2, 0, 0) })
	end,
}

Themes.TidebreakCoast = {
	Terrain = Enum.Material.Sand,
	Wall = { Color = Color3.fromRGB(125, 120, 115), Material = Enum.Material.Slate },
	Path = Color3.fromRGB(205, 180, 130),
	Node = "TidePool",
	Decorate = function(m, center, rng, keep)
		-- Ocean along the east side, with a raised King Tide layer.
		local oceanW, tideW = 55 * BIG, 75 * BIG
		local ocean = P(m, "Ocean", BLOCK, V(oceanW, 0.6, WorldLayout.ZoneSize - 2), C(center + V(HALF - oceanW / 2 - 0.5, 0.5, 0)), Color3.fromRGB(50, 150, 210), Enum.Material.SmoothPlastic, 0.25, false)
		ocean.CanQuery = false
		local tide = P(m, "KingTideWater", BLOCK, V(tideW, 1.6, WorldLayout.ZoneSize - 2), C(center + V(HALF - tideW / 2 - 0.5, 1.1, 0)), Color3.fromRGB(45, 140, 220), Enum.Material.SmoothPlastic, 1, false)
		tide.CanQuery = false
		tide:SetAttribute("EventOnly", "KingTide")
		tide:SetAttribute("EventTransparency", 0.4)
		-- The ocean strip runs the zone's whole length: keep decor out of it.
		for z = -HALF, HALF, oceanW do
			table.insert(keep, { center + V(HALF - oceanW / 2, 0, z), oceanW * 0.75 })
		end
		local props = assetSet("TidebreakCoast")
		if props then
			-- Blender props: swaying palms, pink and blue coral, sea rocks,
			-- starfish, beach grass and sea cliffs beyond the walls.
			mountainRanges(props, m, center, rng, "Range")
			scatter(props, m, center, rng, keep, {
				{ "Palm", 24, 0.85, 1.3 },
				{ "CoralPink", 12, 0.8, 1.6 },
				{ "CoralBlue", 12, 0.8, 1.6 },
				{ "SeaRock", 12, 0.7, 1.5 },
				{ "Starfish", 20, 0.8, 1.4 },
			})
			patches(props, "BeachGrass", m, center, rng, keep, 120, 5)
		else
			for _ = 1, n(22) do
				palm(m, spot(rng, center, keep), rng)
			end
			for i = 1, n(18) do
				local pos = spot(rng, center, keep)
				local col = ({ Color3.fromRGB(255, 120, 140), Color3.fromRGB(255, 170, 90), Color3.fromRGB(180, 120, 255), Color3.fromRGB(90, 220, 200) })[(i % 4) + 1]
				for k = 1, 5 do
					P(m, "Coral", BLOCK, V(0.5, rng:NextNumber(1.2, 3), 0.5), C(pos + V(rng:NextNumber(-1, 1), 1, rng:NextNumber(-1, 1))) * CFrame.Angles(rng:NextNumber(-0.4, 0.4), 0, rng:NextNumber(-0.4, 0.4)), col, nil, 0, false)
				end
			end
			for _ = 1, n(14) do
				rock(m, spot(rng, center, keep), rng, Color3.fromRGB(125, 120, 112))
			end
		end
		for _ = 1, n(40) do
			local pos = center + V(rng:NextNumber(HALF - tideW, HALF - 5), 0.7, rng:NextNumber(-HALF + 5, HALF - 5))
			local g = P(m, "BioGlow", BALL, V(0.7, 0.7, 0.7), C(pos), Color3.fromRGB(80, 255, 220), Enum.Material.Neon, 1, false)
			g:SetAttribute("EventOnly", "BioluminescentNight")
			g:SetAttribute("EventTransparency", 0)
		end
	end,
}

Themes.ThunderwildHighlands = {
	Terrain = Enum.Material.LeafyGrass,
	Wall = { Color = Color3.fromRGB(110, 110, 120), Material = Enum.Material.Rock },
	Path = Color3.fromRGB(150, 140, 120),
	Node = "LightningRod",
	Decorate = function(m, center, rng, keep)
		-- Rocky hills.
		for _, h in { { at(-50, 0, -40), 40, 14 }, { at(55, 0, 20), 34, 11 }, { at(45, 0, -55), 28, 9 }, { at(-55, 0, 45), 32, 10 } } do
			local w, ht = h[2] * BIG, h[3] * BIG
			P(m, "Hill", BALL, V(w, ht * 2, w), C(center + h[1]), Color3.fromRGB(115, 135, 90), Enum.Material.Grass)
			P(m, "HillRock", BALL, V(w * 0.4, ht * 0.7, w * 0.35), C(center + h[1] + V(w * 0.15, ht * 0.75, 0)), Color3.fromRGB(120, 120, 128), Enum.Material.Rock)
			table.insert(keep, { center + h[1], w / 2 + 3 })
		end
		for _ = 1, n(12) do
			local pos = spot(rng, center, keep)
			local h = rng:NextNumber(12, 20)
			P(m, "PoleRod", CYL, V(h, 0.5, 0.5), C(pos + V(0, h / 2, 0)) * UP, Color3.fromRGB(160, 160, 170), Enum.Material.Metal)
			local tip = P(m, "PoleTip", BALL, V(0.9, 0.9, 0.9), C(pos + V(0, h + 0.3, 0)), Color3.fromRGB(255, 230, 80), Enum.Material.Neon)
			local l = Instance.new("PointLight")
			l.Color = Color3.fromRGB(255, 230, 120)
			l.Range = 18
			l.Enabled = false
			l:SetAttribute("EventOnly", "LightningStorm")
			l.Parent = tip
		end
		local props = assetSet("ThunderwildHighlands")
		if props then
			-- Blender props: glowing storm crystals (they light up in a Static
			-- Surge), wind-bent trees, boulders, stone arches, golden grass and
			-- jagged peaks beyond the walls.
			mountainRanges(props, m, center, rng, "Range")
			for _ = 1, n(14) do
				local cm = place(props, "StormCrystal", m, spot(rng, center, keep), rng:NextNumber(0, 6.28), rng:NextNumber(0.7, 1.4))
				local core = cm and cm:FindFirstChild("Spark")
				if core then
					local l = Instance.new("PointLight")
					l.Color = Color3.fromRGB(190, 160, 255)
					l.Range = 16
					l.Brightness = 2
					l.Enabled = false
					l:SetAttribute("EventOnly", "StaticSurge")
					l.Parent = core
				end
			end
			scatter(props, m, center, rng, keep, {
				{ "WindTree", 18, 0.85, 1.3 },
				{ "Boulder", 12, 0.7, 1.5 },
				{ "StoneArch", 4, 0.9, 1.3 },
			})
			patches(props, "GoldGrass", m, center, rng, keep, 150, 6)
		else
			for _ = 1, n(18) do
				local pos = spot(rng, center, keep)
				for k = 1, 3 do
					local h = rng:NextNumber(2, 5)
					local c = P(m, "ChargeCrystal", BLOCK, V(1, h, 1), C(pos + V(rng:NextNumber(-1, 1), h / 2, rng:NextNumber(-1, 1))) * CFrame.Angles(rng:NextNumber(-0.3, 0.3), rng:NextNumber(0, 6), rng:NextNumber(-0.3, 0.3)), Color3.fromRGB(255, 235, 120), Enum.Material.Glass, 0.15)
					if k == 1 then
						local l = Instance.new("PointLight")
						l.Color = Color3.fromRGB(190, 160, 255)
						l.Range = 14
						l.Brightness = 2
						l.Enabled = false
						l:SetAttribute("EventOnly", "StaticSurge")
						l.Parent = c
					end
				end
			end
			for _ = 1, n(60) do
				local pos = spot(rng, center, keep)
				P(m, "GrassTuft", BLOCK, V(0.3, 1.4, 0.3), C(pos + V(0, 0.7, 0)) * CFrame.Angles(0, rng:NextNumber(0, 6), 0.35), Color3.fromRGB(160, 190, 110), Enum.Material.Grass, 0, false)
			end
			for _ = 1, n(12) do
				rock(m, spot(rng, center, keep), rng, Color3.fromRGB(125, 125, 132), Enum.Material.Rock)
			end
		end
		-- Lightning Storm: dark cloud layer + falling sparks.
		for k = 1, 9 do
			local cloud = P(m, "StormCloud", BALL, V(50 * SCALE, 10 * BIG, 40 * SCALE), C(center + at(((k - 1) % 3 - 1) * 55, 48, (math.floor((k - 1) / 3) - 1) * 55)), Color3.fromRGB(70, 70, 85), Enum.Material.SmoothPlastic, 1, false)
			cloud.CanQuery = false
			cloud.CastShadow = false
			cloud:SetAttribute("EventOnly", "LightningStorm")
			cloud:SetAttribute("EventTransparency", 0.25)
		end
		local sky = P(m, "StormSky", BLOCK, V(WorldLayout.ZoneSize, 1, WorldLayout.ZoneSize), C(center + V(0, 44, 0)), Color3.new(1, 1, 1), nil, 1, false)
		sky.CanQuery = false
		emitter(sky, "StormSparks", "LightningStorm", { EmissionDirection = Enum.NormalId.Bottom, Rate = 120 * BIG, Lifetime = NumberRange.new(1.2, 1.6), Speed = NumberRange.new(30, 40), Size = NumberSequence.new(0.5, 0), Color = ColorSequence.new(Color3.fromRGB(255, 240, 150)), LightEmission = 1 })
	end,
}

Themes.ToxicBloomSwamp = {
	Terrain = Enum.Material.Mud,
	Wall = { Color = Color3.fromRGB(60, 70, 45), Material = Enum.Material.Grass },
	Path = Color3.fromRGB(110, 95, 70),
	Node = "SporePod",
	Decorate = function(m, center, rng, keep)
		local props = assetSet("ToxicBloomSwamp")
		for _, pool in { { at(-45, 0, -35), 30 }, { at(50, 0, 35), 26 }, { at(40, 0, -55), 20 }, { at(-55, 0, 45), 22 }, { at(15, 0, -15), 18 } } do
			local d = pool[2] * BIG
			if props then
				-- Lily pads drifting on the murky water.
				for _ = 1, 4 do
					local a, r = rng:NextNumber(0, 6.28), rng:NextNumber(0, d * 0.35)
					place(props, "LilyPads", m, center + pool[1] + V(math.cos(a) * r, 0.62, math.sin(a) * r), rng:NextNumber(0, 6.28), rng:NextNumber(1, 1.8))
				end
			end
			local water = P(m, "MurkPool", CYL, V(0.3, d, d), C(center + pool[1] + V(0, 0.5, 0)) * UP, Color3.fromRGB(80, 110, 50), Enum.Material.SmoothPlastic, 0.2, false)
			local glow = P(m, "BloomGlow", CYL, V(0.32, d * 0.9, d * 0.9), C(center + pool[1] + V(0, 0.55, 0)) * UP, Color3.fromRGB(150, 255, 60), Enum.Material.Neon, 1, false)
			glow:SetAttribute("EventOnly", "ToxicBloom")
			glow:SetAttribute("EventTransparency", 0.4)
			emitter(water, "Bubbles", "ToxicBloom", { Rate = 20, Lifetime = NumberRange.new(1, 2), Speed = NumberRange.new(1, 2), Size = NumberSequence.new(0.5, 0), Color = ColorSequence.new(Color3.fromRGB(170, 255, 90)), LightEmission = 0.8, EmissionDirection = Enum.NormalId.Right })
			table.insert(keep, { center + pool[1], d / 2 + 2 })
		end
		if props then
			-- Blender props: weeping willows, giant spotted mushrooms, glowing
			-- shrooms, mossy logs, cattail reeds and gloomy hills beyond the walls.
			mountainRanges(props, m, center, rng, "Range")
			scatter(props, m, center, rng, keep, {
				{ "Willow", 18, 0.85, 1.3 },
				{ "Mushroom", 12, 0.7, 1.5 },
				{ "GlowShrooms", 18, 0.8, 1.5 },
				{ "MossyLog", 10, 0.8, 1.3 },
			})
			patches(props, "Reeds", m, center, rng, keep, 120, 5)
		else
			for _ = 1, n(18) do
				local pos = spot(rng, center, keep)
				local h = rng:NextNumber(5, 11)
				local capCol = ({ Color3.fromRGB(200, 70, 70), Color3.fromRGB(150, 90, 200), Color3.fromRGB(150, 220, 80) })[rng:NextInteger(1, 3)]
				P(m, "MushroomStem", CYL, V(h, 1.6, 1.6), C(pos + V(0, h / 2, 0)) * UP, Color3.fromRGB(230, 220, 200))
				P(m, "MushroomCap", BALL, V(h * 0.9, h * 0.35, h * 0.9), C(pos + V(0, h, 0)), capCol, if rng:NextNumber() < 0.3 then Enum.Material.Neon else Enum.Material.SmoothPlastic)
			end
			for _ = 1, n(14) do
				local pos = spot(rng, center, keep)
				local h = rng:NextNumber(8, 13)
				P(m, "DeadTrunk", CYL, V(h, 1.2, 1.2), C(pos + V(0, h / 2, 0)) * UP, Color3.fromRGB(70, 55, 45), Enum.Material.Wood)
				for k = 1, 3 do
					P(m, "Branch", BLOCK, V(0.4, 3, 0.4), C(pos + V(0, h * (0.5 + k * 0.12), 0)) * CFrame.Angles(0, k * 2.1, 0.9), Color3.fromRGB(70, 55, 45), Enum.Material.Wood)
					P(m, "Vine", BLOCK, V(0.15, 3.5, 0.15), C(pos + V(math.cos(k * 2.1) * 1.4, h * (0.5 + k * 0.12) - 1.5, math.sin(k * 2.1) * 1.4)), Color3.fromRGB(80, 130, 60), Enum.Material.Grass, 0, false)
				end
			end
			for _ = 1, n(30) do
				local pos = spot(rng, center, keep)
				P(m, "Reed", BLOCK, V(0.25, rng:NextNumber(1.5, 3), 0.25), C(pos + V(0, 1, 0)) * CFrame.Angles(rng:NextNumber(-0.2, 0.2), 0, rng:NextNumber(-0.2, 0.2)), Color3.fromRGB(100, 120, 60), Enum.Material.Grass, 0, false)
			end
		end
		-- Always-on low mist; Sporefall rains spores from above.
		local mistPart = P(m, "MistSource", BLOCK, V(WorldLayout.ZoneSize, 1, WorldLayout.ZoneSize), C(center + V(0, 1, 0)), Color3.new(1, 1, 1), nil, 1, false)
		mistPart.CanQuery = false
		emitter(mistPart, "SwampMist", nil, { Texture = "rbxasset://textures/particles/smoke_main.dds", Rate = 25 * BIG, Lifetime = NumberRange.new(6, 9), Speed = NumberRange.new(0.3, 0.8), Size = NumberSequence.new(6, 10), Color = ColorSequence.new(Color3.fromRGB(170, 190, 140)), Transparency = NumberSequence.new(0.8, 1), EmissionDirection = Enum.NormalId.Top })
		local sky = P(m, "SporeSky", BLOCK, V(WorldLayout.ZoneSize, 1, WorldLayout.ZoneSize), C(center + V(0, 40, 0)), Color3.new(1, 1, 1), nil, 1, false)
		sky.CanQuery = false
		emitter(sky, "Sporefall", "Sporefall", { Texture = "rbxasset://textures/particles/sparkles_main.dds", EmissionDirection = Enum.NormalId.Bottom, Rate = 250 * BIG, Lifetime = NumberRange.new(8, 10), Speed = NumberRange.new(2, 4), Size = NumberSequence.new(0.35), Color = ColorSequence.new(Color3.fromRGB(200, 255, 130)), LightEmission = 0.7 })
	end,
}

-- ===== Personal chambers =====
-- A row of glass pods along the meadow's back wall, behind the spawn. Main gives
-- each player a free pod (OwnerId attribute + name on the sign); the client shows
-- the owner's eggs on the EggSpot parts and enables the prompt for the owner only.
WorldBuilder.PodCount = 12 -- match the game's Max Players setting
local POD_Z = 48 -- meadow pods stand just in front of the +Z wall

function WorldBuilder.PodPositions(): { Vector3 }
	local out = {}
	-- Pod 1 is nearest the spawn; the rest alternate left/right outwards.
	for k = 1, WorldBuilder.PodCount do
		local side = if k % 2 == 1 then -1 else 1
		local j = (k - 1) // 2
		table.insert(out, V(side * (16 + j * 17), 0.4, POD_Z))
	end
	return out
end

local function buildPods(accent: Color3)
	local folder = Instance.new("Folder")
	folder.Name = "PlayerPods"
	for k, pos in WorldBuilder.PodPositions() do
		local m = Instance.new("Model")
		m.Name = "Pod" .. k
		local base = P(m, "Base", CYL, V(1.2, 13, 13), C(pos + V(0, 0.6, 0)) * UP, Color3.fromRGB(60, 70, 95), Enum.Material.Metal)
		P(m, "Pedestal", CYL, V(0.5, 10, 10), C(pos + V(0, 1.4, 0)) * UP, Color3.fromRGB(200, 230, 255), Enum.Material.Neon)
		P(m, "Glass", CYL, V(9, 10.4, 10.4), C(pos + V(0, 6.1, 0)) * UP, Color3.fromRGB(170, 230, 255), Enum.Material.Glass, 0.7, false)
		P(m, "Roof", CYL, V(1.4, 13, 13), C(pos + V(0, 11.3, 0)) * UP, Color3.fromRGB(60, 70, 95), Enum.Material.Metal)
		P(m, "RoofGlow", CYL, V(0.4, 11, 11), C(pos + V(0, 10.5, 0)) * UP, accent, Enum.Material.Neon, 0, false)
		P(m, "BackPanel", BLOCK, V(14, 16, 1), C(pos + V(0, 8, 7.4)), Color3.fromRGB(45, 52, 75), Enum.Material.Metal)
		local sign = P(m, "Sign", BLOCK, V(13, 3, 0.4), C(pos + V(0, 13.4, 6.6)), Color3.fromRGB(30, 35, 55))
		surfaceText(sign, "FREE CHAMBER", Color3.fromRGB(255, 230, 120))
		-- Up to 4 eggs (one per egg slot) stand on the pedestal in a 2 x 2 square.
		for s, off in { V(-1.8, 0, -1.6), V(1.8, 0, -1.6), V(-1.8, 0, 1.6), V(1.8, 0, 1.6) } do
			local spot = P(m, "EggSpot" .. s, BLOCK, V(0.5, 0.5, 0.5), C(pos + off + V(0, 3.2, 0)), Color3.new(1, 1, 1), nil, 1, false)
			spot.CanQuery = false
		end
		-- Control console in front of the pod (the side facing the spawn, -Z): a
		-- glowing button at chest height that carries the pod's prompt.
		local front = pos + V(0, 0, -8.5)
		P(m, "ConsoleStand", CYL, V(3, 2.2, 2.2), C(front + V(0, 1.5, 0)) * UP, Color3.fromRGB(60, 70, 95), Enum.Material.Metal)
		local console = P(m, "Console", CYL, V(0.6, 2.8, 2.8), C(front + V(0, 3.3, 0)) * UP, accent, Enum.Material.Neon)
		local pr = Instance.new("ProximityPrompt")
		pr.ActionText = "Hatch"
		pr.ObjectText = "Your Chamber"
		pr.MaxActivationDistance = 10
		pr.RequiresLineOfSight = false
		pr.Enabled = false -- the client enables it on its owner's pod only
		pr.Parent = console
		m.PrimaryPart = base
		-- Stream the whole pod at once, so its prompt is there whenever the pod is.
		m.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
		m:SetAttribute("PodIndex", k)
		CollectionService:AddTag(m, "PlayerPod")
		m.Parent = folder
	end
	folder.Parent = workspace
end

-- ===== Battle spots =====
-- Wild spots: a glowing battle circle where one wild monster of a fixed species
-- lives (the client draws the monster; BattleService fights the same species).
-- Commoner species get more spots. Trainer spots: where Main spawns each
-- trainer from Shared/Trainers, beside the path, facing it.
WorldBuilder.WildSpotsPerZone = 8
local WILD_PATTERN = { 1, 1, 2, 1, 2, 1, 3, 2 } -- species by SpeciesRarity

local function battleSpotsFor(zone, biome, center: Vector3, clear: (Vector3) -> boolean, parent: Instance)
	local bySpecies = {}
	for _, s in Species.List do
		if s.HomeBiome == zone.Biome then
			bySpecies[s.SpeciesRarity] = s.Id
		end
	end
	for k = 1, WorldBuilder.WildSpotsPerZone do
		local speciesId = bySpecies[WILD_PATTERN[(k - 1) % #WILD_PATTERN + 1]] or bySpecies[1]
		local radius = WorldLayout.ZoneSize * 0.27
		local a = k / WorldBuilder.WildSpotsPerZone * math.pi * 2 + 0.5
		local pos = center + V(math.cos(a) * radius, 0.4, math.sin(a) * radius)
		for step = 1, 12 do
			if clear(pos) then
				break
			end
			local a2 = a + step * 0.1
			pos = center + V(math.cos(a2) * radius, 0.4, math.sin(a2) * radius)
		end
		local spot = P(parent, "WildSpot", CYL, V(0.3, 14, 14), C(pos + V(0, 0.2, 0)) * UP, biome.Theme.Accent, Enum.Material.Neon, 0.65, false)
		spot.CanQuery = false
		spot.CastShadow = false
		spot:SetAttribute("SpotId", zone.Biome .. "_W" .. k)
		spot:SetAttribute("Biome", zone.Biome)
		spot:SetAttribute("WildSpecies", speciesId)
		local pr = Instance.new("ProximityPrompt")
		pr.ActionText = "Battle!"
		pr.ObjectText = "Wild " .. Species.ById[speciesId].DisplayName
		pr.MaxActivationDistance = 16
		pr.RequiresLineOfSight = false
		pr.Parent = spot
		CollectionService:AddTag(spot, "WildSpot")
	end
	local n = 0
	for _, tr in Trainers.List do
		if tr.Biome == zone.Biome then
			n += 1
			local side = if n % 2 == 1 then -1 else 1
			local z = center.Z + (if n == 1 then HALF * 0.45 else -HALF * 0.15)
			local pos = V(center.X + side * 16, 0.4, z)
			-- Stand on a little stage, facing the path.
			local stage = P(parent, "TrainerSpot", CYL, V(0.8, 9, 9), C(pos + V(0, 0.4, 0)) * UP, Color3.fromRGB(70, 70, 90), Enum.Material.Metal)
			stage:SetAttribute("TrainerId", tr.Id)
			stage:SetAttribute("Facing", -side) -- +X or -X toward the path
			CollectionService:AddTag(stage, "TrainerSpot")
		end
	end
end

-- ===== Build =====
function WorldBuilder.Clear()
	for _, z in WorldLayout.Zones do
		local old = workspace:FindFirstChild(z.Biome)
		if old then
			old:Destroy()
		end
		local ch = workspace:FindFirstChild("MutationChamber_" .. z.Biome)
		if ch then
			ch:Destroy()
		end
	end
	-- Players only use their own pod now: the big shared chamber (a place
	-- object, not generated) goes too.
	for _, name in { "GatherNodes", "ZoneGates", "PlayerPods", "BattleSpots", "MutationChamber" } do
		local old = workspace:FindFirstChild(name)
		if old then
			old:Destroy()
		end
	end
	-- Terrain over every zone footprint (ground, water), so a rebuild starts clean.
	for _, z in WorldLayout.Zones do
		workspace.Terrain:FillBlock(C(z.Center + V(0, 30, 0)), V(WorldLayout.ZoneSize + 16, 80, WorldLayout.ZoneSize), Enum.Material.Air)
	end
end

-- Global look: wind (sways grass/leaves, see the Ambience client script), soft
-- shadows, haze and a warm grade. Lighting.Technology = Future and
-- MaterialService.Use2022Materials can't be set from scripts; set them in Studio.
function WorldBuilder.ApplyAtmosphere()
	local Lighting = game:GetService("Lighting")
	workspace.GlobalWind = V(7, 0, 3)
	Lighting.ClockTime = 14.5
	Lighting.Brightness = 2.6
	Lighting.EnvironmentDiffuseScale = 1
	Lighting.EnvironmentSpecularScale = 0.6
	Lighting.ShadowSoftness = 0.25
	Lighting.OutdoorAmbient = Color3.fromRGB(120, 125, 135)
	local function effect(className: string, props: { [string]: any })
		local e = Lighting:FindFirstChildOfClass(className) or Instance.new(className)
		for k, v in props do
			(e :: any)[k] = v
		end
		e.Parent = Lighting
	end
	effect("Atmosphere", { Density = 0.32, Offset = 0.2, Color = Color3.fromRGB(200, 215, 230), Decay = Color3.fromRGB(120, 140, 160), Glare = 0.25, Haze = 1.4 })
	effect("BloomEffect", { Intensity = 0.6, Size = 28, Threshold = 1.6 })
	effect("SunRaysEffect", { Intensity = 0.06, Spread = 0.7 })
	effect("ColorCorrectionEffect", { Saturation = 0.12, Contrast = 0.08, Brightness = 0.02, TintColor = Color3.fromRGB(255, 250, 240) })
	-- Meadow grass is a little lusher than the default terrain green.
	workspace.Terrain:SetMaterialColor(Enum.Material.Grass, Color3.fromRGB(96, 150, 62))
	workspace.Terrain:SetMaterialColor(Enum.Material.LeafyGrass, Color3.fromRGB(118, 150, 82))
end

function WorldBuilder.Build(sharedFolder: Instance?)
	if sharedFolder then
		WorldLayout = require(sharedFolder:FindFirstChild("WorldLayout"))
		Biomes = require(sharedFolder:FindFirstChild("Biomes"))
		Species = require(sharedFolder:FindFirstChild("Species"))
		Trainers = require(sharedFolder:FindFirstChild("Trainers"))
	end
	setScale()
	WorldBuilder.Clear()
	WorldBuilder.ApplyAtmosphere()
	local nodes = Instance.new("Folder")
	nodes.Name = "GatherNodes"
	nodes.Parent = workspace
	local gates = Instance.new("Folder")
	gates.Name = "ZoneGates"
	gates.Parent = workspace
	local battleSpots = Instance.new("Folder")
	battleSpots.Name = "BattleSpots"
	battleSpots.Parent = workspace
	-- New players spawn facing the row of pods, so they see their own chamber first.
	local spawnPad = workspace:FindFirstChildWhichIsA("SpawnLocation")
	if spawnPad then
		spawnPad.CFrame = CFrame.new(spawnPad.Position) * CFrame.Angles(0, math.pi, 0)
	end
	local counts = {}

	for i, zone in WorldLayout.Zones do
		local theme = Themes[zone.Biome]
		local biome = Biomes.ById[zone.Biome]
		local center = zone.Center
		local rng = Random.new(1000 + i)
		local m = Instance.new("Model")
		m.Name = zone.Biome
		local decor = Instance.new("Folder")
		decor.Name = "Decor"
		decor.Parent = m

		-- Ground (terrain surface at y = 0.4 where decor and chambers stand), path, walls.
		workspace.Terrain:FillBlock(C(center + V(0, TERRAIN_TOP - 3, 0)), V(WorldLayout.ZoneSize, 6, WorldLayout.ZoneSize), theme.Terrain)
		P(m, "Path", BLOCK, V(12, 0.2, WorldLayout.ZoneSize), C(center + V(0, 0.45, 0)), theme.Path, Enum.Material.Ground, 0, false)
		for _, side in { -1, 1 } do
			P(m, "Wall", BLOCK, V(4, 30, WorldLayout.ZoneSize + 4), C(center + V(side * (HALF + 2), 15, 0)), theme.Wall.Color, theme.Wall.Material)
		end
		if i == 1 then
			P(m, "Wall", BLOCK, V(WorldLayout.ZoneSize + 8, 30, 4), C(center + V(0, 15, HALF + 2)), theme.Wall.Color, theme.Wall.Material)
		end
		if i == #WorldLayout.Zones then
			P(m, "Wall", BLOCK, V(WorldLayout.ZoneSize + 8, 30, 4), C(center + V(0, 15, -HALF - 2)), theme.Wall.Color, theme.Wall.Material)
		end

		-- Each player's own chamber is a pod on the meadow wall (no shared chambers).
		local keep = { { zone.Spawn, 10 } }
		if i == 1 then
			buildPods(biome.Theme.Accent)
			for _, pos in WorldBuilder.PodPositions() do
				table.insert(keep, { pos + V(0, 0, -4), 15 })
			end
		end

		-- Entrance sign.
		local sign = P(m, "ZoneSign", BLOCK, V(26, 6, 1), C(center + V(28, 9, HALF - 8)), Color3.fromRGB(35, 35, 50))
		surfaceText(sign, string.upper(biome.DisplayName), biome.Theme.Accent)
		for _, x in { 16, 40 } do
			P(m, "SignPost", BLOCK, V(1, 9, 1), C(center + V(x, 4.5, HALF - 8)), Color3.fromRGB(70, 55, 45), Enum.Material.Wood)
		end
		table.insert(keep, { center + V(28, 0, HALF - 8), 16 })

		theme.Decorate(decor, center, rng, keep)

		-- Gather nodes in two rings (8 each), nudged off the path and out of ponds,
		-- lakes and other landmarks.
		local made = 0
		local function clear(pos: Vector3): boolean
			if math.abs(pos.X - center.X) < 12 then
				return false
			end
			for _, k in keep do
				if ((pos - (k[1] :: Vector3)) * V(1, 0, 1)).Magnitude < (k[2] :: number) then
					return false
				end
			end
			return true
		end
		for k = 1, 16 do
			local radius = WorldLayout.ZoneSize * (if k <= 8 then 0.18 else 0.36)
			local a = k / 8 * math.pi * 2 + (if k <= 8 then 0.3 else 0.7)
			local pos = center + V(math.cos(a) * radius, 0.4, math.sin(a) * radius)
			for step = 1, 12 do
				if clear(pos) then
					break
				end
				local a2 = a + step * 0.12
				pos = center + V(math.cos(a2) * radius, 0.4, math.sin(a2) * radius)
			end
			local nm = Instance.new("Model")
			nm.Name = theme.Node .. k
			local node, label = NodeMakers[theme.Node](nm, pos)
			node:SetAttribute("NodeType", theme.Node)
			node:SetAttribute("NodeId", zone.Biome .. "_" .. k)
			prompt(node, label)
			nm.Parent = nodes
			made += 1
		end

		battleSpotsFor(zone, biome, center, clear, battleSpots)

		-- Gate to the next zone.
		local nextZone = WorldLayout.Zones[i + 1]
		if nextZone then
			local nextBiome = Biomes.ById[nextZone.Biome]
			local gz = center.Z - HALF
			local gm = Instance.new("Model")
			gm.Name = "Gate_" .. nextZone.Biome
			local segW = (WorldLayout.ZoneSize - WorldLayout.GateWidth) / 2 + 4
			for _, side in { -1, 1 } do
				P(gm, "GateWall", BLOCK, V(segW, 30, 4), C(side * (WorldLayout.GateWidth / 2 + segW / 2), 15, gz), Color3.fromRGB(85, 80, 95), Enum.Material.Cobblestone)
				P(gm, "Pillar", BLOCK, V(4, 34, 6), C(side * (WorldLayout.GateWidth / 2 + 2), 17, gz), Color3.fromRGB(60, 55, 70), Enum.Material.Cobblestone)
			end
			P(gm, "Arch", BLOCK, V(WorldLayout.GateWidth + 8, 4, 6), C(0, 32, gz), Color3.fromRGB(60, 55, 70), Enum.Material.Cobblestone)
			local barrier = P(gm, "Barrier", BLOCK, V(WorldLayout.GateWidth, 30, 1), C(0, 15, gz), nextBiome.Theme.Accent, Enum.Material.Neon, 0.6)
			barrier:SetAttribute("Biome", nextZone.Biome)
			CollectionService:AddTag(barrier, "BiomeGate")
			local label = P(gm, "GateSign", BLOCK, V(WorldLayout.GateWidth + 6, 5, 0.6), C(0, 26, gz + 3.4), Color3.fromRGB(30, 30, 45))
			local u = nextBiome.Unlock
			surfaceText(label, string.format("%s\nLevel %d  |  %d mutations  |  %d coins", string.upper(nextBiome.DisplayName), u.Level, u.MutationsDiscovered, u.Coins), nextBiome.Theme.Accent)
			local pr = Instance.new("ProximityPrompt")
			pr.Name = "UnlockPrompt"
			pr.ActionText = "Unlock"
			pr.ObjectText = nextBiome.DisplayName
			pr.HoldDuration = 0.4
			pr.MaxActivationDistance = 16
			pr.RequiresLineOfSight = false
			pr.Parent = barrier
			gm.Parent = gates
		end
		m.Parent = workspace
		counts[zone.Biome] = #m:GetDescendants() + made
		task.wait() -- one zone per frame keeps Studio responsive
	end
	local out = {}
	for b, n in counts do
		table.insert(out, b .. "=" .. n)
	end
	return table.concat(out, ", ")
end

return WorldBuilder
