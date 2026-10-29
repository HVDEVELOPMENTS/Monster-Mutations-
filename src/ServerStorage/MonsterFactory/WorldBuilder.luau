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

local WorldBuilder = {}

local V, C = Vector3.new, CFrame.new
local BLOCK, BALL, CYL = Enum.PartType.Block, Enum.PartType.Ball, Enum.PartType.Cylinder
local HALF = WorldLayout.ZoneSize / 2
local UP = CFrame.Angles(0, 0, math.pi / 2) -- cylinder axis X -> Y

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

-- ===== Zone themes =====
local Themes = {}

Themes.VerdantMeadows = {
	Ground = nil, -- uses the existing baseplate
	Wall = { Color = Color3.fromRGB(55, 120, 55), Material = Enum.Material.Grass },
	Path = Color3.fromRGB(190, 160, 110),
	Node = "DewdropFlower",
	Decorate = function(m, center, rng, keep)
		P(m, "Pond", CYL, V(0.3, 34, 34), C(center + V(-48, 0.25, -45)) * UP, Color3.fromRGB(80, 170, 220), Enum.Material.SmoothPlastic, 0.25, false)
		table.insert(keep, { center + V(-48, 0, -45), 22 })
		for _ = 1, 22 do
			tree(m, spot(rng, center, keep), rng, Color3.fromRGB(110, 75, 45), Color3.fromRGB(90, 175, 70))
		end
		for _ = 1, 30 do
			local pos = spot(rng, center, keep)
			P(m, "Bush", BALL, V(4, 2.6, 3.4), C(pos + V(0, 1, 0)), Color3.fromRGB(70, 150, 60), Enum.Material.Grass)
		end
		for _ = 1, 45 do
			local pos = spot(rng, center, keep)
			local col = ({ Color3.fromRGB(255, 120, 160), Color3.fromRGB(255, 220, 90), Color3.fromRGB(170, 130, 255), Color3.new(1, 1, 1) })[rng:NextInteger(1, 4)]
			P(m, "Flower", BALL, V(0.7, 0.4, 0.7), C(pos + V(0, 0.5, 0)), col, nil, 0, false)
		end
		for _ = 1, 10 do
			rock(m, spot(rng, center, keep), rng, Color3.fromRGB(130, 130, 125))
		end
	end,
}

Themes.FrostfallTundra = {
	Ground = { Color = Color3.fromRGB(238, 244, 252), Material = Enum.Material.Snow },
	Wall = { Color = Color3.fromRGB(175, 215, 240), Material = Enum.Material.Glacier },
	Path = Color3.fromRGB(200, 215, 230),
	Node = "FrostCrystal",
	Decorate = function(m, center, rng, keep)
		P(m, "FrozenLake", CYL, V(0.3, 46, 46), C(center + V(45, 0.55, -35)) * UP, Color3.fromRGB(170, 215, 245), Enum.Material.Ice)
		table.insert(keep, { center + V(45, 0, -35), 26 })
		for _ = 1, 30 do
			pine(m, spot(rng, center, keep), rng, true)
		end
		for _ = 1, 22 do
			local pos = spot(rng, center, keep)
			local h = rng:NextNumber(4, 10)
			P(m, "IceCrystal", BLOCK, V(1.8, h, 1.8), C(pos + V(0, h / 2, 0)) * CFrame.Angles(rng:NextNumber(-0.3, 0.3), rng:NextNumber(0, 6.28), rng:NextNumber(-0.3, 0.3)), Color3.fromRGB(150, 210, 255), Enum.Material.Glass, 0.2)
		end
		for _ = 1, 16 do
			local pos = spot(rng, center, keep)
			P(m, "Snowdrift", BALL, V(7, 2.4, 5), C(pos + V(0, 0.6, 0)), Color3.fromRGB(245, 248, 255), Enum.Material.Snow)
		end
		-- Events
		local sky = P(m, "StormSky", BLOCK, V(WorldLayout.ZoneSize, 1, WorldLayout.ZoneSize), C(center + V(0, 45, 0)), Color3.new(1, 1, 1), nil, 1, false)
		sky.CanQuery = false
		emitter(sky, "SnowstormEmitter", "Snowstorm", { EmissionDirection = Enum.NormalId.Bottom, Rate = 400, Lifetime = NumberRange.new(6, 8), Speed = NumberRange.new(6, 9), Size = NumberSequence.new(0.45), Color = ColorSequence.new(Color3.new(1, 1, 1)), LightEmission = 0.3, Acceleration = V(4, 0, 0) })
		local colors = { Color3.fromRGB(120, 255, 190), Color3.fromRGB(110, 200, 255), Color3.fromRGB(160, 120, 255) }
		for i = 0, 20 do
			local a = i / 20 * math.pi
			local r = P(m, "AuroraRibbon", BLOCK, V(14, 16, 0.4), C(center + V(math.cos(a) * 80, 60 + math.sin(i * 0.8) * 4, -40 + math.sin(a) * 20)) * CFrame.Angles(0, -a + math.pi / 2, math.sin(i) * 0.2), colors[(i % 3) + 1], Enum.Material.Neon, 1, false)
			r.CanQuery = false
			r.CastShadow = false
			r:SetAttribute("EventOnly", "AuroraNight")
			r:SetAttribute("EventTransparency", 0.35)
		end
	end,
}

Themes.EmberpeakVolcano = {
	Ground = { Color = Color3.fromRGB(55, 50, 55), Material = Enum.Material.Basalt },
	Wall = { Color = Color3.fromRGB(60, 52, 55), Material = Enum.Material.Basalt },
	Path = Color3.fromRGB(90, 75, 70),
	Node = "EmberVent",
	Decorate = function(m, center, rng, keep)
		-- The volcano: stacked tapering rings with a glowing crater and smoke.
		local vpos = center + V(48, 0, -40)
		for k = 0, 6 do
			local r = 46 - k * 6
			P(m, "Volcano", CYL, V(5, r, r), C(vpos + V(0, 2.5 + k * 5, 0)) * UP, Color3.fromRGB(70 - k * 3, 58 - k * 2, 58 - k * 2), Enum.Material.Basalt)
		end
		local crater = P(m, "Crater", CYL, V(1, 8, 8), C(vpos + V(0, 37.6, 0)) * UP, Color3.fromRGB(255, 110, 30), Enum.Material.Neon)
		emitter(crater, "VolcanoSmoke", nil, { Texture = "rbxasset://textures/particles/smoke_main.dds", Rate = 12, Lifetime = NumberRange.new(6, 9), Speed = NumberRange.new(5, 8), Size = NumberSequence.new(4, 12), Color = ColorSequence.new(Color3.fromRGB(80, 75, 75)), Transparency = NumberSequence.new(0.3, 1), EmissionDirection = Enum.NormalId.Top })
		emitter(crater, "Eruption", "MagmaSurge", { Texture = "rbxasset://textures/particles/fire_main.dds", Rate = 80, Lifetime = NumberRange.new(1.5, 2.5), Speed = NumberRange.new(15, 25), Size = NumberSequence.new(3, 0.5), Color = ColorSequence.new(Color3.fromRGB(255, 180, 60), Color3.fromRGB(255, 60, 20)), LightEmission = 1, EmissionDirection = Enum.NormalId.Top, SpreadAngle = Vector2.new(20, 20), Acceleration = V(0, -20, 0) })
		table.insert(keep, { vpos, 30 })
		for i, z in { -20, 30 } do
			local river = P(m, "LavaRiver", BLOCK, V(80, 0.5, 5), C(center + V(-45, 0.45, z)) * CFrame.Angles(0, (i - 1.5) * 0.3, 0), Color3.fromRGB(255, 110, 30), Enum.Material.Neon, 0, false)
			emitter(river, "SurgeFlames", "MagmaSurge", { Texture = "rbxasset://textures/particles/fire_main.dds", Rate = 60, Lifetime = NumberRange.new(0.8, 1.4), Speed = NumberRange.new(4, 7), Size = NumberSequence.new(1.6, 0), Color = ColorSequence.new(Color3.fromRGB(255, 160, 50), Color3.fromRGB(255, 60, 20)), EmissionDirection = Enum.NormalId.Top, LightEmission = 1 })
			local l = Instance.new("PointLight")
			l.Color = Color3.fromRGB(255, 120, 40)
			l.Range = 40
			l.Brightness = 3
			l.Enabled = false
			l:SetAttribute("EventOnly", "MagmaSurge")
			l.Parent = river
		end
		for _ = 1, 26 do
			local pos = spot(rng, center, keep)
			local h = rng:NextNumber(4, 13)
			P(m, "Spire", BLOCK, V(2.6, h, 2.6), C(pos + V(0, h / 2, 0)) * CFrame.Angles(rng:NextNumber(-0.2, 0.2), rng:NextNumber(0, 6.28), rng:NextNumber(-0.2, 0.2)), Color3.fromRGB(70, 60, 62), Enum.Material.Basalt)
			if rng:NextNumber() < 0.4 then
				P(m, "LavaGlow", BALL, V(1, 1, 1), C(pos + V(0, h + 0.3, 0)), Color3.fromRGB(255, 130, 40), Enum.Material.Neon, 0, false)
			end
		end
		for _ = 1, 16 do
			rock(m, spot(rng, center, keep), rng, Color3.fromRGB(25, 20, 30), Enum.Material.Glass)
		end
		local sky = P(m, "AshSky", BLOCK, V(WorldLayout.ZoneSize, 1, WorldLayout.ZoneSize), C(center + V(0, 50, 0)), Color3.new(1, 1, 1), nil, 1, false)
		sky.CanQuery = false
		emitter(sky, "AshfallEmitter", "Ashfall", { EmissionDirection = Enum.NormalId.Bottom, Rate = 300, Lifetime = NumberRange.new(7, 9), Speed = NumberRange.new(4, 6), Size = NumberSequence.new(0.4), Color = ColorSequence.new(Color3.fromRGB(110, 105, 105)), Acceleration = V(2, 0, 0) })
	end,
}

Themes.TidebreakCoast = {
	Ground = { Color = Color3.fromRGB(228, 208, 160), Material = Enum.Material.Sand },
	Wall = { Color = Color3.fromRGB(125, 120, 115), Material = Enum.Material.Slate },
	Path = Color3.fromRGB(205, 180, 130),
	Node = "TidePool",
	Decorate = function(m, center, rng, keep)
		-- Ocean along the east side, with a raised King Tide layer.
		local ocean = P(m, "Ocean", BLOCK, V(55, 0.6, WorldLayout.ZoneSize - 2), C(center + V(HALF - 28, 0.5, 0)), Color3.fromRGB(50, 150, 210), Enum.Material.SmoothPlastic, 0.25, false)
		ocean.CanQuery = false
		local tide = P(m, "KingTideWater", BLOCK, V(75, 1.6, WorldLayout.ZoneSize - 2), C(center + V(HALF - 38, 1.1, 0)), Color3.fromRGB(45, 140, 220), Enum.Material.SmoothPlastic, 1, false)
		tide.CanQuery = false
		tide:SetAttribute("EventOnly", "KingTide")
		tide:SetAttribute("EventTransparency", 0.4)
		table.insert(keep, { center + V(HALF - 28, 0, 0), 32 })
		for _ = 1, 22 do
			palm(m, spot(rng, center, keep), rng)
		end
		for i = 1, 18 do
			local pos = spot(rng, center, keep)
			local col = ({ Color3.fromRGB(255, 120, 140), Color3.fromRGB(255, 170, 90), Color3.fromRGB(180, 120, 255), Color3.fromRGB(90, 220, 200) })[(i % 4) + 1]
			for k = 1, 5 do
				P(m, "Coral", BLOCK, V(0.5, rng:NextNumber(1.2, 3), 0.5), C(pos + V(rng:NextNumber(-1, 1), 1, rng:NextNumber(-1, 1))) * CFrame.Angles(rng:NextNumber(-0.4, 0.4), 0, rng:NextNumber(-0.4, 0.4)), col, nil, 0, false)
			end
		end
		for _ = 1, 14 do
			rock(m, spot(rng, center, keep), rng, Color3.fromRGB(125, 120, 112))
		end
		for _ = 1, 40 do
			local pos = center + V(rng:NextNumber(HALF - 60, HALF - 5), 0.7, rng:NextNumber(-HALF + 5, HALF - 5))
			local g = P(m, "BioGlow", BALL, V(0.7, 0.7, 0.7), C(pos), Color3.fromRGB(80, 255, 220), Enum.Material.Neon, 1, false)
			g:SetAttribute("EventOnly", "BioluminescentNight")
			g:SetAttribute("EventTransparency", 0)
		end
	end,
}

Themes.ThunderwildHighlands = {
	Ground = { Color = Color3.fromRGB(125, 160, 95), Material = Enum.Material.Grass },
	Wall = { Color = Color3.fromRGB(110, 110, 120), Material = Enum.Material.Rock },
	Path = Color3.fromRGB(150, 140, 120),
	Node = "LightningRod",
	Decorate = function(m, center, rng, keep)
		-- Rocky hills.
		for _, h in { { V(-50, 0, -40), 40, 14 }, { V(55, 0, 20), 34, 11 }, { V(45, 0, -55), 28, 9 } } do
			P(m, "Hill", BALL, V(h[2], h[3] * 2, h[2]), C(center + h[1]), Color3.fromRGB(115, 135, 90), Enum.Material.Grass)
			P(m, "HillRock", BALL, V(h[2] * 0.4, h[3] * 0.7, h[2] * 0.35), C(center + h[1] + V(h[2] * 0.15, h[3] * 0.75, 0)), Color3.fromRGB(120, 120, 128), Enum.Material.Rock)
			table.insert(keep, { center + h[1], h[2] / 2 + 3 })
		end
		for _ = 1, 12 do
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
		for _ = 1, 18 do
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
		for _ = 1, 60 do
			local pos = spot(rng, center, keep)
			P(m, "GrassTuft", BLOCK, V(0.3, 1.4, 0.3), C(pos + V(0, 0.7, 0)) * CFrame.Angles(0, rng:NextNumber(0, 6), 0.35), Color3.fromRGB(160, 190, 110), Enum.Material.Grass, 0, false)
		end
		for _ = 1, 12 do
			rock(m, spot(rng, center, keep), rng, Color3.fromRGB(125, 125, 132), Enum.Material.Rock)
		end
		-- Lightning Storm: dark cloud layer + falling sparks.
		for k = 1, 9 do
			local cloud = P(m, "StormCloud", BALL, V(50, 10, 40), C(center + V(((k - 1) % 3 - 1) * 55, 48, (math.floor((k - 1) / 3) - 1) * 55)), Color3.fromRGB(70, 70, 85), Enum.Material.SmoothPlastic, 1, false)
			cloud.CanQuery = false
			cloud.CastShadow = false
			cloud:SetAttribute("EventOnly", "LightningStorm")
			cloud:SetAttribute("EventTransparency", 0.25)
		end
		local sky = P(m, "StormSky", BLOCK, V(WorldLayout.ZoneSize, 1, WorldLayout.ZoneSize), C(center + V(0, 44, 0)), Color3.new(1, 1, 1), nil, 1, false)
		sky.CanQuery = false
		emitter(sky, "StormSparks", "LightningStorm", { EmissionDirection = Enum.NormalId.Bottom, Rate = 120, Lifetime = NumberRange.new(1.2, 1.6), Speed = NumberRange.new(30, 40), Size = NumberSequence.new(0.5, 0), Color = ColorSequence.new(Color3.fromRGB(255, 240, 150)), LightEmission = 1 })
	end,
}

Themes.ToxicBloomSwamp = {
	Ground = { Color = Color3.fromRGB(85, 92, 58), Material = Enum.Material.Mud },
	Wall = { Color = Color3.fromRGB(60, 70, 45), Material = Enum.Material.Grass },
	Path = Color3.fromRGB(110, 95, 70),
	Node = "SporePod",
	Decorate = function(m, center, rng, keep)
		for _, pool in { { V(-45, 0, -35), 30 }, { V(50, 0, 35), 26 }, { V(40, 0, -55), 20 }, { V(-55, 0, 45), 22 } } do
			local water = P(m, "MurkPool", CYL, V(0.3, pool[2], pool[2]), C(center + pool[1] + V(0, 0.5, 0)) * UP, Color3.fromRGB(80, 110, 50), Enum.Material.SmoothPlastic, 0.2, false)
			local glow = P(m, "BloomGlow", CYL, V(0.32, pool[2] * 0.9, pool[2] * 0.9), C(center + pool[1] + V(0, 0.55, 0)) * UP, Color3.fromRGB(150, 255, 60), Enum.Material.Neon, 1, false)
			glow:SetAttribute("EventOnly", "ToxicBloom")
			glow:SetAttribute("EventTransparency", 0.4)
			emitter(water, "Bubbles", "ToxicBloom", { Rate = 20, Lifetime = NumberRange.new(1, 2), Speed = NumberRange.new(1, 2), Size = NumberSequence.new(0.5, 0), Color = ColorSequence.new(Color3.fromRGB(170, 255, 90)), LightEmission = 0.8, EmissionDirection = Enum.NormalId.Right })
			table.insert(keep, { center + pool[1], pool[2] / 2 + 2 })
		end
		for _ = 1, 18 do
			local pos = spot(rng, center, keep)
			local h = rng:NextNumber(5, 11)
			local capCol = ({ Color3.fromRGB(200, 70, 70), Color3.fromRGB(150, 90, 200), Color3.fromRGB(150, 220, 80) })[rng:NextInteger(1, 3)]
			P(m, "MushroomStem", CYL, V(h, 1.6, 1.6), C(pos + V(0, h / 2, 0)) * UP, Color3.fromRGB(230, 220, 200))
			P(m, "MushroomCap", BALL, V(h * 0.9, h * 0.35, h * 0.9), C(pos + V(0, h, 0)), capCol, if rng:NextNumber() < 0.3 then Enum.Material.Neon else Enum.Material.SmoothPlastic)
		end
		for _ = 1, 14 do
			local pos = spot(rng, center, keep)
			local h = rng:NextNumber(8, 13)
			P(m, "DeadTrunk", CYL, V(h, 1.2, 1.2), C(pos + V(0, h / 2, 0)) * UP, Color3.fromRGB(70, 55, 45), Enum.Material.Wood)
			for k = 1, 3 do
				P(m, "Branch", BLOCK, V(0.4, 3, 0.4), C(pos + V(0, h * (0.5 + k * 0.12), 0)) * CFrame.Angles(0, k * 2.1, 0.9), Color3.fromRGB(70, 55, 45), Enum.Material.Wood)
				P(m, "Vine", BLOCK, V(0.15, 3.5, 0.15), C(pos + V(math.cos(k * 2.1) * 1.4, h * (0.5 + k * 0.12) - 1.5, math.sin(k * 2.1) * 1.4)), Color3.fromRGB(80, 130, 60), Enum.Material.Grass, 0, false)
			end
		end
		for _ = 1, 30 do
			local pos = spot(rng, center, keep)
			P(m, "Reed", BLOCK, V(0.25, rng:NextNumber(1.5, 3), 0.25), C(pos + V(0, 1, 0)) * CFrame.Angles(rng:NextNumber(-0.2, 0.2), 0, rng:NextNumber(-0.2, 0.2)), Color3.fromRGB(100, 120, 60), Enum.Material.Grass, 0, false)
		end
		-- Always-on low mist; Sporefall rains spores from above.
		local mistPart = P(m, "MistSource", BLOCK, V(WorldLayout.ZoneSize, 1, WorldLayout.ZoneSize), C(center + V(0, 1, 0)), Color3.new(1, 1, 1), nil, 1, false)
		mistPart.CanQuery = false
		emitter(mistPart, "SwampMist", nil, { Texture = "rbxasset://textures/particles/smoke_main.dds", Rate = 25, Lifetime = NumberRange.new(6, 9), Speed = NumberRange.new(0.3, 0.8), Size = NumberSequence.new(6, 10), Color = ColorSequence.new(Color3.fromRGB(170, 190, 140)), Transparency = NumberSequence.new(0.8, 1), EmissionDirection = Enum.NormalId.Top })
		local sky = P(m, "SporeSky", BLOCK, V(WorldLayout.ZoneSize, 1, WorldLayout.ZoneSize), C(center + V(0, 40, 0)), Color3.new(1, 1, 1), nil, 1, false)
		sky.CanQuery = false
		emitter(sky, "Sporefall", "Sporefall", { Texture = "rbxasset://textures/particles/sparkles_main.dds", EmissionDirection = Enum.NormalId.Bottom, Rate = 250, Lifetime = NumberRange.new(8, 10), Speed = NumberRange.new(2, 4), Size = NumberSequence.new(0.35), Color = ColorSequence.new(Color3.fromRGB(200, 255, 130)), LightEmission = 0.7 })
	end,
}

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
	for _, name in { "GatherNodes", "ZoneGates" } do
		local old = workspace:FindFirstChild(name)
		if old then
			old:Destroy()
		end
	end
end

function WorldBuilder.Build(sharedFolder: Instance?)
	if sharedFolder then
		WorldLayout = require(sharedFolder:FindFirstChild("WorldLayout"))
		Biomes = require(sharedFolder:FindFirstChild("Biomes"))
		HALF = WorldLayout.ZoneSize / 2
	end
	WorldBuilder.Clear()
	local nodes = Instance.new("Folder")
	nodes.Name = "GatherNodes"
	nodes.Parent = workspace
	local gates = Instance.new("Folder")
	gates.Name = "ZoneGates"
	gates.Parent = workspace
	local mainChamber = workspace:FindFirstChild("MutationChamber")
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

		-- Ground, path, walls.
		if theme.Ground then
			local g = P(m, "Ground", BLOCK, V(WorldLayout.ZoneSize, 2, WorldLayout.ZoneSize), C(center + V(0, -0.6, 0)), theme.Ground.Color, theme.Ground.Material)
			m.PrimaryPart = g
		end
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

		-- Chamber (the meadow keeps the original one).
		local chamberPos = if i == 1 then V(0, 0, -18) else center + V(-28, 0, HALF - 42)
		local chamber
		if i == 1 then
			chamber = mainChamber
		elseif mainChamber then
			chamber = mainChamber:Clone()
			chamber.Name = "MutationChamber_" .. zone.Biome
			-- Translate only (the base cylinder's pivot carries a rotation we must keep).
			chamber:PivotTo(mainChamber:GetPivot() + (chamberPos + V(0, 0.4, 0) - V(0, 0, -18)))
			chamber.Parent = workspace
		end
		if chamber then
			chamber:SetAttribute("ChamberBiome", zone.Biome)
			CollectionService:AddTag(chamber, "MutationChamber")
		end
		local keep = { { chamberPos, 14 }, { zone.Spawn, 10 } }

		-- Entrance sign.
		local sign = P(m, "ZoneSign", BLOCK, V(26, 6, 1), C(center + V(28, 9, HALF - 8)), Color3.fromRGB(35, 35, 50))
		surfaceText(sign, string.upper(biome.DisplayName), biome.Theme.Accent)
		for _, x in { 16, 40 } do
			P(m, "SignPost", BLOCK, V(1, 9, 1), C(center + V(x, 4.5, HALF - 8)), Color3.fromRGB(70, 55, 45), Enum.Material.Wood)
		end
		table.insert(keep, { center + V(28, 0, HALF - 8), 16 })

		theme.Decorate(decor, center, rng, keep)

		-- Gather nodes in a ring around the zone.
		local made = 0
		for k = 1, 8 do
			local a = k / 8 * math.pi * 2 + 0.3
			local pos = center + V(math.cos(a) * 52, 0.4, math.sin(a) * 52)
			if math.abs(pos.X - center.X) < 12 then
				pos += V(16, 0, 0)
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
	end
	local out = {}
	for b, n in counts do
		table.insert(out, b .. "=" .. n)
	end
	return table.concat(out, ", ")
end

return WorldBuilder
