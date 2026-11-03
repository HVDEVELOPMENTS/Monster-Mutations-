-- Builds a monster Model from definitions (species rig + mutation visuals).
-- Visuals are derived, never saved. Models face -Z. All parts are anchored,
-- non-colliding and shadowless so they are cheap in ViewportFrames and the world.
-- Aura "orbiters" are tagged with attributes so a caller can animate them; there
-- is no built-in loop per monster.

local Mutations = require(script.Parent.Mutations)
local Species = require(script.Parent.Species)
local Rarity = require(script.Parent.Rarity)

local MonsterVisuals = {}

MonsterVisuals.MAX_ORBITERS = 8

MonsterVisuals.Palettes = {
	Moss = Color3.fromRGB(110, 170, 80),
	Fern = Color3.fromRGB(70, 140, 70),
	Lime = Color3.fromRGB(150, 200, 70),
	Slate = Color3.fromRGB(120, 125, 135),
	Sandstone = Color3.fromRGB(195, 165, 120),
	Clay = Color3.fromRGB(175, 115, 85),
	Pond = Color3.fromRGB(80, 150, 130),
	Reed = Color3.fromRGB(135, 165, 90),
	Teal = Color3.fromRGB(60, 170, 170),
	Snow = Color3.fromRGB(240, 245, 252),
	Frostblue = Color3.fromRGB(170, 210, 245),
	Pearl = Color3.fromRGB(225, 225, 235),
	Arctic = Color3.fromRGB(205, 215, 225),
	Slateblue = Color3.fromRGB(110, 130, 165),
	Charcoal = Color3.fromRGB(60, 55, 60),
	Basalt = Color3.fromRGB(90, 85, 92),
	Rust = Color3.fromRGB(155, 85, 60),
	Ashgrey = Color3.fromRGB(150, 142, 142),
	Magma = Color3.fromRGB(200, 85, 45),
	Reef = Color3.fromRGB(255, 145, 60),
	Coral = Color3.fromRGB(240, 115, 115),
	Lagoon = Color3.fromRGB(85, 190, 215),
	Seafoam = Color3.fromRGB(150, 230, 210),
	Sand = Color3.fromRGB(220, 195, 150),
	Sunbeam = Color3.fromRGB(250, 215, 95),
	Stormgrey = Color3.fromRGB(125, 130, 145),
	Cream = Color3.fromRGB(240, 230, 210),
	Skyblue = Color3.fromRGB(125, 180, 240),
	Toadstool = Color3.fromRGB(215, 65, 60),
	Violet = Color3.fromRGB(145, 95, 195),
	Mossgreen = Color3.fromRGB(105, 145, 75),
	Bogbrown = Color3.fromRGB(115, 92, 62),
}

local BLACK = Color3.new(0, 0, 0)

local function mat(name: string?): Enum.Material
	if name then
		local ok, m = pcall(function()
			return (Enum.Material :: any)[name]
		end)
		if ok and m then
			return m
		end
	end
	return Enum.Material.SmoothPlastic
end

-- Ball parts are always perfect spheres in Roblox, so a non-uniform "ball" is made
-- as a block with a sphere SpecialMesh, which stretches into a true ellipsoid.
local function part(model: Model, name: string, shape: Enum.PartType, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?)
	local p = Instance.new("Part")
	p.Name = name
	local ellipsoid = shape == Enum.PartType.Ball and not (size.X == size.Y and size.Y == size.Z)
	p.Shape = if ellipsoid then Enum.PartType.Block else shape
	if ellipsoid then
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = p
	end
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = model
	return p
end

local BALL, BLOCK, CYL = Enum.PartType.Ball, Enum.PartType.Block, Enum.PartType.Cylinder
local V, C = Vector3.new, CFrame.new

-- Chunky shape helpers. A WedgePart's slope faces -Z with its tall edge at +Z, so two
-- mirrored wedges make a triangular fin; two crossed fins make a pointed spike.
local function wedge(model: Model, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?)
	local w = Instance.new("WedgePart")
	w.Name = name
	w.Size = size
	w.CFrame = cf
	w.Color = color
	w.Material = material or Enum.Material.SmoothPlastic
	w.Anchored = true
	w.CanCollide = false
	w.CanQuery = false
	w.CanTouch = false
	w.CastShadow = false
	w.Parent = model
	return w
end

-- Triangular fin standing on `cf` (base centre), peak at cf * (0, h, 0).
local function fin(m: Model, name: string, cf: CFrame, w: number, h: number, d: number, color: Color3, material: Enum.Material?)
	wedge(m, name, V(w, h, d / 2), cf * C(0, h / 2, -d / 4), color, material)
	wedge(m, name, V(w, h, d / 2), cf * C(0, h / 2, d / 4) * CFrame.Angles(0, math.pi, 0), color, material)
end

-- Pointed spike: base centre at cf, tip at cf * (0, h, 0).
local function spike(m: Model, name: string, cf: CFrame, h: number, base: number, color: Color3, material: Enum.Material?)
	fin(m, name, cf, base * 0.45, h, base, color, material)
	fin(m, name, cf * CFrame.Angles(0, math.pi / 2, 0), base * 0.45, h, base, color, material)
end

local WHITE = Color3.new(1, 1, 1)
local BLUSH = Color3.fromRGB(255, 140, 160)
local function shade(c: Color3, f: number)
	return if f >= 0 then c:Lerp(WHITE, f) else c:Lerp(BLACK, -f)
end

-- Species rigs: build(model, color) -> anchors. Faces are drawn by drawFace from:
--   Eyes (CFrames facing -Z), EyeSize, Style ("Cute" | "Fierce" | "Frog"), IrisColor,
--   Mouth (CFrame), Cheeks ({ CFrame }).
-- Mutation anchors: Head, Back, Tail (CFrames) and Body = { Center, Radius }.
local Rigs = {}
-- Anchors shared by a part rig and its mesh rig (fresh table per call; Build mutates it).
local RigAnchors = {}

RigAnchors.Mossling = function()
	return {
		Style = "Cute",
		Eyes = { C(-0.55, 2.12, -1.3), C(0.55, 2.12, -1.3) },
		EyeSize = 0.82,
		Mouth = C(0, 1.72, -1.38),
		Cheeks = { CFrame.lookAt(V(-0.95, 1.8, -1.12), V(-1.6, 1.8, -2.0)), CFrame.lookAt(V(0.95, 1.8, -1.12), V(1.6, 1.8, -2.0)) },
		Head = C(0, 3.05, 0),
		Back = C(0, 2.95, 0.6),
		Body = { Center = V(0, 1.75, 0), Radius = 1.35 },
	}
end

Rigs.Mossling = function(m, col)
	local body = part(m, "Body", BALL, V(3.0, 2.7, 2.8), C(0, 1.75, 0), col)
	m.PrimaryPart = body
	part(m, "Belly", BALL, V(1.9, 1.6, 0.6), C(0, 1.3, -1.15), shade(col, 0.45))
	for _, x in { -0.85, 0.85 } do
		for _, z in { -0.75, 0.75 } do
			part(m, "Foot", BALL, V(0.85, 0.7, 0.85), C(x, 0.35, z), shade(col, -0.18))
		end
		for _, dx in { -0.15, 0.15 } do
			spike(m, "Claw", C(x + dx, 0.2, -1.05) * CFrame.Angles(-math.pi / 2, 0, 0), 0.28, 0.16, shade(col, -0.55))
		end
	end
	local leaf = Color3.fromRGB(100, 215, 90)
	fin(m, "Leaf", C(-0.32, 2.95, 0) * CFrame.Angles(0, 0, 0.4), 0.14, 1.2, 0.9, leaf)
	fin(m, "Leaf", C(0.32, 2.95, 0) * CFrame.Angles(0, 0, -0.4), 0.14, 1.2, 0.9, leaf)
	for k = 0, 2 do
		spike(m, "BackSpike", C(0, 2.85 - k * 0.3, 0.45 + k * 0.42) * CFrame.Angles(0.5 + k * 0.3, 0, 0), 0.55, 0.42, shade(col, -0.45))
	end
	return RigAnchors.Mossling()
end

Rigs.Pebbleback = function(m, col)
	local skin = shade(col:Lerp(Color3.fromRGB(150, 190, 120), 0.55), 0.15)
	local shell = part(m, "Body", BALL, V(3.4, 2.3, 3.4), C(0, 1.6, 0.25), col)
	m.PrimaryPart = shell
	part(m, "ShellRim", CYL, V(0.35, 3.7, 3.7), C(0, 0.9, 0.25) * CFrame.Angles(0, 0, math.pi / 2), shade(col, -0.35))
	local stones = { V(-0.75, 2.55, 0.2), V(0.7, 2.6, -0.2), V(0.05, 2.75, 0.85), V(-0.1, 2.5, -0.65), V(1.05, 2.15, 0.9), V(-1.1, 2.2, 1.0) }
	for i, pos in stones do
		local cf = CFrame.lookAt(pos, pos + (pos - V(0, 1.6, 0.25)))
		part(m, "Stone", BALL, V(0.85, 0.85, 0.32), cf, if i % 2 == 0 then shade(col, -0.25) else shade(col, 0.2))
	end
	part(m, "Head", BALL, V(1.7, 1.6, 1.6), C(0, 1.6, -1.95), skin)
	for _, x in { -1.1, 1.1 } do
		for _, z in { -0.75, 1.1 } do
			part(m, "Leg", CYL, V(0.9, 0.9, 0.9), C(x, 0.45, z) * CFrame.Angles(0, 0, math.pi / 2), skin)
			spike(m, "Claw", C(x, 0.15, z - 0.5) * CFrame.Angles(-math.pi / 2, 0, 0), 0.25, 0.18, WHITE)
		end
	end
	return {
		Style = "Cute",
		Eyes = { C(-0.4, 1.82, -2.6), C(0.4, 1.82, -2.6) },
		EyeSize = 0.6,
		Mouth = C(0, 1.38, -2.72),
		Cheeks = { CFrame.lookAt(V(-0.65, 1.5, -2.45), V(-1.2, 1.5, -3.2)), CFrame.lookAt(V(0.65, 1.5, -2.45), V(1.2, 1.5, -3.2)) },
		Head = C(0, 2.4, -1.95),
		Back = C(0, 2.75, 0.25),
		Body = { Center = V(0, 1.6, 0.25), Radius = 1.6 },
	}
end

Rigs.Brookhopper = function(m, col)
	local body = part(m, "Body", BALL, V(2.9, 2.0, 2.6), C(0, 1.2, 0.2), col)
	m.PrimaryPart = body
	part(m, "Belly", BALL, V(2.0, 1.3, 0.7), C(0, 0.95, -0.95), shade(col, 0.55))
	for _, x in { -0.72, 0.72 } do
		part(m, "EyeBulb", BALL, V(1.05, 1.05, 1.05), C(x, 2.1, -0.55), col)
		part(m, "BackLeg", BALL, V(1.0, 0.9, 1.7), C(x * 1.7, 0.55, 0.65), shade(col, -0.15))
		part(m, "FrontLeg", BALL, V(0.5, 0.65, 0.5), C(x, 0.33, -0.85), shade(col, -0.15))
		for k = -1, 1 do
			part(m, "Toe", BALL, V(0.22, 0.16, 0.3), C(x + k * 0.16, 0.08, -1.12), shade(col, 0.4))
		end
	end
	for i, pos in { V(-0.6, 2.05, 0.6), V(0.55, 2.1, 0.9), V(0.05, 2.15, 0.25) } do
		part(m, "Spot", BALL, V(0.55, 0.2, 0.55), CFrame.lookAt(pos, pos + (pos - V(0, 1.2, 0.2))) * CFrame.Angles(math.pi / 2, 0, i), shade(col, -0.35))
	end
	part(m, "Tail", BALL, V(0.55, 0.5, 0.65), C(0, 1.0, 1.5), col)
	return {
		Style = "Frog",
		Eyes = { C(-0.72, 2.18, -1.05), C(0.72, 2.18, -1.05) },
		EyeSize = 0.76,
		Mouth = C(0, 1.4, -1.2),
		Cheeks = { CFrame.lookAt(V(-1.05, 1.45, -0.85), V(-1.7, 1.45, -1.6)), CFrame.lookAt(V(1.05, 1.45, -0.85), V(1.7, 1.45, -1.6)) },
		Head = C(0, 2.75, -0.45),
		Tail = C(0, 1.05, 1.8),
		Body = { Center = V(0, 1.2, 0.2), Radius = 1.15 },
	}
end

Rigs.Snowmote = function(m, col)
	local body = part(m, "Body", BALL, V(2.8, 2.6, 2.6), C(0, 2.3, 0), col)
	m.PrimaryPart = body
	for i = 1, 8 do
		local ang = i / 8 * math.pi * 2
		part(m, "Puff", BALL, V(0.95, 0.95, 0.95), C(math.cos(ang) * 1.25, 1.75 + (i % 2) * 0.25, math.sin(ang) * 1.2), shade(col, 0.35))
	end
	for _, x in { -0.75, 0.75 } do
		local cf = C(x, 3.3, 0.1) * CFrame.Angles(0, 0, -x * 0.45)
		fin(m, "Ear", cf, 0.28, 1.0, 0.75, col)
		fin(m, "EarInner", cf * C(0, 0.05, -0.12), 0.29, 0.65, 0.4, BLUSH)
	end
	local ice = Color3.fromRGB(170, 225, 255)
	for k = -1, 1 do
		spike(m, "IceSpike", C(k * 0.35, 3.45 - math.abs(k) * 0.1, 0.45) * CFrame.Angles(0.35, 0, k * 0.35), 0.6, 0.3, ice, Enum.Material.Glass)
	end
	local glow = part(m, "FloatGlow", BALL, V(1.6, 0.25, 1.6), C(0, 0.55, 0), Color3.fromRGB(180, 225, 255), Enum.Material.Neon)
	glow.Transparency = 0.45
	return {
		Style = "Cute",
		Eyes = { C(-0.55, 2.52, -1.25), C(0.55, 2.52, -1.25) },
		EyeSize = 0.82,
		Mouth = C(0, 2.05, -1.33),
		Cheeks = { CFrame.lookAt(V(-0.95, 2.15, -1.08), V(-1.6, 2.15, -1.9)), CFrame.lookAt(V(0.95, 2.15, -1.08), V(1.6, 2.15, -1.9)) },
		Head = C(0, 3.65, -0.1),
		Body = { Center = V(0, 2.3, 0), Radius = 1.3 },
	}
end

Rigs.Frostfang = function(m, col)
	local light = shade(col, 0.55)
	local body = part(m, "Body", BALL, V(2.0, 1.8, 3.0), C(0, 1.75, 0.4), col)
	m.PrimaryPart = body
	part(m, "ChestFluff", BALL, V(1.5, 1.3, 0.9), C(0, 1.6, -0.85), light)
	part(m, "Head", BALL, V(2.0, 1.8, 1.8), C(0, 2.85, -1.2), col)
	part(m, "Snout", BALL, V(1.0, 0.75, 1.0), C(0, 2.45, -2.05), light)
	part(m, "Nose", BALL, V(0.32, 0.25, 0.25), C(0, 2.7, -2.55), Color3.fromRGB(35, 35, 50))
	for _, x in { -0.6, 0.6 } do
		local cf = C(x, 3.55, -1.05) * CFrame.Angles(0, 0, -x * 0.5)
		fin(m, "Ear", cf, 0.26, 1.0, 0.75, col)
		fin(m, "EarInner", cf * C(0, 0.05, -0.12), 0.27, 0.6, 0.4, light)
	end
	for _, x in { -0.6, 0.6 } do
		for _, z in { -0.45, 1.25 } do
			part(m, "Leg", BALL, V(0.62, 1.3, 0.7), C(x, 0.7, z), col)
			part(m, "Paw", BALL, V(0.7, 0.42, 0.8), C(x, 0.2, z - 0.1), light)
		end
		for _, dx in { -0.12, 0.12 } do
			spike(m, "Claw", C(x + dx, 0.15, -0.95) * CFrame.Angles(-math.pi / 2, 0, 0), 0.25, 0.14, Color3.fromRGB(40, 50, 80))
		end
	end
	part(m, "TailBase", BALL, V(0.8, 0.8, 1.0), C(0, 2.2, 1.95), col)
	part(m, "TailMid", BALL, V(0.75, 0.75, 0.9), C(0, 2.65, 2.35), col)
	part(m, "Tail", BALL, V(0.65, 0.65, 0.75), C(0, 3.05, 2.55), light)
	local ice = Color3.fromRGB(150, 215, 255)
	for k = 0, 3 do
		spike(m, "Crest", C(0, 2.55 - k * 0.05, -0.15 + k * 0.5) * CFrame.Angles(0.25, 0, 0), 0.75 - k * 0.1, 0.45, ice, Enum.Material.Glass)
	end
	return {
		Style = "Fierce",
		IrisColor = Color3.fromRGB(90, 200, 255),
		Eyes = { C(-0.45, 3.0, -2.03), C(0.45, 3.0, -2.03) },
		EyeSize = 0.5,
		Mouth = C(0, 2.12, -2.42),
		Cheeks = {},
		Head = C(0, 3.75, -1.2),
		Back = C(0, 2.65, 0.5),
		Tail = C(0, 3.3, 2.75),
		Body = { Center = V(0, 1.75, 0.4), Radius = 1.0 },
	}
end

Rigs.Glimmerseal = function(m, col)
	local light = shade(col, 0.5)
	local body = part(m, "Body", BALL, V(2.4, 1.9, 3.6), C(0, 1.0, 0.45), col)
	m.PrimaryPart = body
	part(m, "Belly", BALL, V(1.5, 1.1, 0.6), C(0, 1.1, -1.1), light)
	part(m, "Head", BALL, V(2.0, 1.9, 1.9), C(0, 2.05, -1.2), col)
	part(m, "Muzzle", BALL, V(1.0, 0.6, 0.6), C(0, 1.68, -2.05), light)
	part(m, "Nose", BALL, V(0.3, 0.22, 0.2), C(0, 1.9, -2.33), Color3.fromRGB(40, 40, 55))
	for _, side in { -1, 1 } do
		part(m, "Flipper", BALL, V(1.3, 0.25, 0.75), C(side * 1.25, 0.4, -0.45) * CFrame.Angles(0, side * 0.4, side * -0.25), shade(col, -0.2))
		part(m, "TailFlipper", BALL, V(0.9, 0.2, 0.65), C(side * 0.42, 0.3, 2.35) * CFrame.Angles(0, side * -0.5, 0), shade(col, -0.2))
		for j = 0, 1 do
			part(m, "Whisker", BLOCK, V(0.55, 0.04, 0.04), C(side * 0.75, 1.65 - j * 0.12, -2.15) * CFrame.Angles(0, side * 0.25, side * (0.12 - j * 0.25)), Color3.fromRGB(60, 60, 75))
		end
	end
	for i, pos in { V(-0.7, 1.75, 0.6), V(0.6, 1.8, 1.1), V(0.1, 1.9, 0.2), V(-0.4, 1.6, 1.5), V(0.8, 1.5, 0.0), V(-0.9, 1.4, -0.3) } do
		part(m, "Glitter", BALL, V(0.14, 0.14, 0.14), C(pos), WHITE, Enum.Material.Neon)
	end
	part(m, "Tail", BALL, V(0.45, 0.4, 0.45), C(0, 0.55, 2.2), col)
	return {
		Style = "Cute",
		Eyes = { C(-0.5, 2.2, -1.98), C(0.5, 2.2, -1.98) },
		EyeSize = 0.86,
		Mouth = C(0, 1.45, -2.3),
		Cheeks = { CFrame.lookAt(V(-0.85, 1.72, -1.9), V(-1.4, 1.72, -2.6)), CFrame.lookAt(V(0.85, 1.72, -1.9), V(1.4, 1.72, -2.6)) },
		Head = C(0, 3.0, -1.2),
		Tail = C(0, 0.5, 2.5),
		Body = { Center = V(0, 1.0, 0.45), Radius = 1.0 },
	}
end

-- ===== Emberpeak Volcano rigs =====
local LAVA = Color3.fromRGB(255, 120, 30)

-- Mesh rig only (molten block biped from assets/models/cindermite.py); the part rig
-- below keeps its own beetle anchors.
RigAnchors.Cindermite = function()
	return {
		Style = "Molten",
		Eyes = { C(-0.5, 2.1, -1.13), C(0.5, 2.1, -1.13) },
		EyeSize = 0.62,
		Mouth = C(0, 1.42, -1.13),
		Head = C(0, 3.0, 0),
		Back = C(0, 2.6, 0.9),
		Body = { Center = V(0, 1.85, 0), Radius = 1.2 },
	}
end

Rigs.Cindermite = function(m, col)
	local body = part(m, "Body", BALL, V(2.6, 1.5, 3.0), C(0, 1.1, 0.2), col)
	m.PrimaryPart = body
	for _, side in { -1, 1 } do
		part(m, "ShellHalf", BALL, V(1.35, 0.9, 2.7), C(side * 0.62, 1.62, 0.3) * CFrame.Angles(0, 0, side * -0.2), shade(col, -0.12))
		for _, z in { -0.6, 0.2, 1.0 } do
			part(m, "Foot", BALL, V(0.35, 0.45, 0.35), C(side * 1.15, 0.3, z), shade(col, -0.3))
		end
		local ant = C(side * 0.3, 1.75, -1.5) * CFrame.Angles(0.4, 0, side * -0.35)
		part(m, "Antenna", BLOCK, V(0.08, 0.8, 0.08), ant * C(0, 0.35, 0), shade(col, -0.3))
		part(m, "AntennaTip", BALL, V(0.2, 0.2, 0.2), ant * C(0, 0.78, 0), LAVA, Enum.Material.Neon)
	end
	part(m, "LavaCrack", BLOCK, V(0.08, 0.15, 2.4), C(0, 2.05, 0.3), LAVA, Enum.Material.Neon)
	for i, pos in { V(-0.7, 1.95, -0.3), V(0.65, 1.95, 0.5), V(-0.5, 1.85, 1.0), V(0.6, 1.9, -0.5) } do
		part(m, "LavaSpot", BALL, V(0.25, 0.25, 0.25), C(pos), LAVA, Enum.Material.Neon)
	end
	part(m, "Head", BALL, V(1.5, 1.2, 1.1), C(0, 1.15, -1.35), shade(col, 0.15))
	return {
		Style = "Cute",
		Eyes = { C(-0.36, 1.3, -1.86), C(0.36, 1.3, -1.86) },
		EyeSize = 0.55,
		Mouth = C(0, 0.9, -1.88),
		Cheeks = { CFrame.lookAt(V(-0.62, 1.0, -1.7), V(-1.2, 1.0, -2.4)), CFrame.lookAt(V(0.62, 1.0, -1.7), V(1.2, 1.0, -2.4)) },
		Head = C(0, 1.8, -1.35),
		Back = C(0, 2.1, 0.4),
		Body = { Center = V(0, 1.1, 0.2), Radius = 1.1 },
	}
end

Rigs.Basaltback = function(m, col)
	local light = shade(col, 0.35)
	local body = part(m, "Body", BALL, V(3.0, 2.3, 3.8), C(0, 1.9, 0.3), col)
	m.PrimaryPart = body
	part(m, "Belly", BALL, V(2.0, 1.4, 2.6), C(0, 1.45, 0.2), light)
	part(m, "Head", BALL, V(1.9, 1.6, 1.8), C(0, 2.0, -1.9), col)
	part(m, "Snout", BALL, V(1.2, 0.9, 0.9), C(0, 1.7, -2.6), light)
	spike(m, "Horn", C(0, 2.0, -2.75) * CFrame.Angles(-0.55, 0, 0), 0.95, 0.45, shade(col, -0.35), Enum.Material.Slate)
	part(m, "HornGlow", BALL, V(0.18, 0.18, 0.18), C(0, 2.75, -3.2), LAVA, Enum.Material.Neon)
	for _, side in { -1, 1 } do
		fin(m, "Ear", C(side * 0.75, 2.65, -1.7) * CFrame.Angles(0, 0, -side * 0.9), 0.2, 0.6, 0.5, col)
		for _, z in { -0.9, 1.3 } do
			part(m, "Leg", BALL, V(0.8, 1.3, 0.85), C(side * 0.95, 0.7, z), col)
			part(m, "Paw", BALL, V(0.9, 0.35, 1.0), C(side * 0.95, 0.18, z - 0.05), shade(col, -0.2))
		end
	end
	for i = -1, 1 do
		part(m, "LavaCrack", BLOCK, V(0.08, 0.12, 1.4), C(i * 0.6, 3.05 - math.abs(i) * 0.15, 0.3) * CFrame.Angles(0, i * 0.3, 0), LAVA, Enum.Material.Neon)
	end
	part(m, "Tail", BALL, V(0.45, 0.45, 0.8), C(0, 2.1, 2.25), col)
	return {
		Style = "Fierce",
		IrisColor = LAVA,
		Eyes = { C(-0.5, 2.3, -2.6), C(0.5, 2.3, -2.6) },
		EyeSize = 0.45,
		Mouth = C(0, 1.45, -2.97),
		Cheeks = {},
		Head = C(0, 2.8, -1.9),
		Back = C(0, 3.05, 0.3),
		Tail = C(0, 2.1, 2.6),
		Body = { Center = V(0, 1.9, 0.3), Radius = 1.2 },
	}
end

Rigs.Ashwing = function(m, col)
	local body = part(m, "Body", BALL, V(2.4, 2.3, 2.2), C(0, 2.4, 0), col)
	m.PrimaryPart = body
	part(m, "Belly", BALL, V(1.5, 1.4, 0.6), C(0, 2.15, -0.9), shade(col, 0.45))
	part(m, "ChestEmber", BALL, V(0.3, 0.3, 0.3), C(0, 1.85, -1.05), LAVA, Enum.Material.Neon)
	for _, side in { -1, 1 } do
		local ear = C(side * 0.62, 3.35, 0) * CFrame.Angles(0, 0, -side * 0.35)
		fin(m, "Ear", ear, 0.22, 1.05, 0.8, col)
		fin(m, "EarInner", ear * C(0, 0.05, -0.12), 0.23, 0.65, 0.42, LAVA:Lerp(col, 0.4))
		fin(m, "Wing", C(side * 1.15, 2.6, 0.2) * CFrame.Angles(0, 0, -side * 1.3), 0.08, 1.9, 1.5, shade(col, -0.3))
		part(m, "Foot", BALL, V(0.35, 0.3, 0.45), C(side * 0.42, 1.2, -0.1), shade(col, -0.25))
	end
	part(m, "Tail", BALL, V(0.45, 0.45, 0.45), C(0, 2.0, 1.15), LAVA, Enum.Material.Neon)
	return {
		Style = "Cute",
		Eyes = { C(-0.5, 2.62, -1.02), C(0.5, 2.62, -1.02) },
		EyeSize = 0.78,
		Mouth = C(0, 2.15, -1.1),
		Cheeks = { CFrame.lookAt(V(-0.85, 2.25, -0.88), V(-1.5, 2.25, -1.6)), CFrame.lookAt(V(0.85, 2.25, -0.88), V(1.5, 2.25, -1.6)) },
		Head = C(0, 3.6, 0),
		Tail = C(0, 2.0, 1.35),
		Body = { Center = V(0, 2.4, 0), Radius = 1.15 },
	}
end

-- ===== Tidebreak Coast rigs =====
Rigs.Reefling = function(m, col)
	local body = part(m, "Body", BALL, V(1.9, 2.1, 3.0), C(0, 2.4, 0), col)
	m.PrimaryPart = body
	for _, z in { -0.45, 0.55 } do
		part(m, "Stripe", BALL, V(1.95, 2.12, 0.28), C(0, 2.4, z), Color3.new(1, 1, 1))
	end
	part(m, "Belly", BALL, V(1.3, 1.0, 2.0), C(0, 1.85, -0.1), shade(col, 0.4))
	fin(m, "Tail", C(0, 2.4, 1.35) * CFrame.Angles(math.pi / 2, 0, 0), 0.1, 1.0, 1.3, shade(col, -0.15))
	fin(m, "Fin", C(0, 3.35, 0.2), 0.1, 0.7, 1.3, shade(col, -0.15))
	for _, side in { -1, 1 } do
		part(m, "Flipper", BALL, V(0.9, 0.12, 0.5), C(side * 1.0, 2.1, -0.2) * CFrame.Angles(0, side * 0.3, side * -0.3), shade(col, -0.1))
	end
	return {
		Style = "Cute",
		Eyes = { C(-0.55, 2.68, -1.05), C(0.55, 2.68, -1.05) },
		EyeSize = 0.68,
		Mouth = C(0, 2.15, -1.48),
		Cheeks = { CFrame.lookAt(V(-0.75, 2.2, -1.05), V(-1.3, 2.2, -1.8)), CFrame.lookAt(V(0.75, 2.2, -1.05), V(1.3, 2.2, -1.8)) },
		Head = C(0, 3.45, -0.6),
		Tail = C(0, 2.4, 1.9),
		Body = { Center = V(0, 2.4, 0), Radius = 1.0 },
	}
end

Rigs.Coralback = function(m, col)
	local body = part(m, "Body", BALL, V(3.2, 1.5, 2.4), C(0, 1.2, 0), col)
	m.PrimaryPart = body
	part(m, "Shell", BALL, V(3.0, 0.9, 2.2), C(0, 1.6, 0.05), shade(col, -0.12))
	local pink = Color3.fromRGB(255, 160, 190)
	for i, x in { -0.6, 0.1, 0.7 } do
		local base = C(x, 1.95, 0.2 + (i % 2) * 0.3)
		part(m, "CoralBranch", BLOCK, V(0.15, 0.6, 0.15), base * C(0, 0.3, 0), pink)
		part(m, "CoralBranch", BLOCK, V(0.12, 0.4, 0.12), base * C(0.12, 0.45, 0) * CFrame.Angles(0, 0, -0.6), pink)
		part(m, "CoralTip", BALL, V(0.18, 0.18, 0.18), base * C(0, 0.65, 0), Color3.fromRGB(255, 220, 230))
	end
	for _, side in { -1, 1 } do
		part(m, "EyeStalk", BLOCK, V(0.12, 0.6, 0.12), C(side * 0.45, 2.0, -0.9), shade(col, -0.1))
		part(m, "Pincer", BALL, V(0.9, 0.7, 1.0), C(side * 1.6, 1.1, -1.0), col)
		spike(m, "Pincer", C(side * 1.6, 1.35, -1.45) * CFrame.Angles(-1.2, 0, 0), 0.4, 0.3, shade(col, -0.2))
		for _, z in { -0.2, 0.35, 0.9 } do
			part(m, "Leg", BALL, V(0.25, 0.95, 0.25), C(side * 1.45, 0.45, z) * CFrame.Angles(0, 0, side * 0.5), shade(col, -0.15))
		end
	end
	return {
		Style = "Cute",
		Eyes = { C(-0.45, 2.45, -0.98), C(0.45, 2.45, -0.98) },
		EyeSize = 0.5,
		Mouth = C(0, 1.0, -1.18),
		Cheeks = { CFrame.lookAt(V(-0.75, 1.2, -1.05), V(-1.3, 1.2, -1.8)), CFrame.lookAt(V(0.75, 1.2, -1.05), V(1.3, 1.2, -1.8)) },
		Head = C(0, 2.3, -0.2),
		Back = C(0, 2.05, 0.3),
		Body = { Center = V(0, 1.2, 0), Radius = 1.1 },
	}
end

Rigs.Seamist = function(m, col)
	local bell = part(m, "Body", BALL, V(2.6, 2.0, 2.6), C(0, 3.0, 0), col)
	bell.Transparency = 0.2
	m.PrimaryPart = bell
	part(m, "InnerGlow", BALL, V(1.2, 1.0, 1.2), C(0, 3.0, 0), shade(col, 0.6), Enum.Material.Neon)
	for i = 1, 8 do
		local ang = i / 8 * math.pi * 2
		part(m, "Rim", BALL, V(0.4, 0.3, 0.4), C(math.cos(ang) * 1.15, 2.15, math.sin(ang) * 1.15), shade(col, 0.2))
	end
	for i = 1, 6 do
		local ang = i / 6 * math.pi * 2 + 0.3
		for k = 0, 3 do
			part(m, "Tentacle", BALL, V(0.22, 0.45, 0.22), C(math.cos(ang) * 0.7, 1.8 - k * 0.4, math.sin(ang) * 0.7), shade(col, 0.3 - k * 0.1))
		end
	end
	return {
		Style = "Cute",
		Eyes = { C(-0.5, 3.05, -1.22), C(0.5, 3.05, -1.22) },
		EyeSize = 0.62,
		Mouth = C(0, 2.6, -1.28),
		Cheeks = { CFrame.lookAt(V(-0.85, 2.75, -1.0), V(-1.5, 2.75, -1.7)), CFrame.lookAt(V(0.85, 2.75, -1.0), V(1.5, 2.75, -1.7)) },
		Head = C(0, 4.05, 0),
		Body = { Center = V(0, 3.0, 0), Radius = 1.25 },
	}
end

-- ===== Thunderwild Highlands rigs =====
local BOLT = Color3.fromRGB(255, 230, 80)

Rigs.Sparkhare = function(m, col)
	local light = shade(col, 0.45)
	local body = part(m, "Body", BALL, V(2.2, 2.0, 2.5), C(0, 1.5, 0.3), col)
	m.PrimaryPart = body
	part(m, "Belly", BALL, V(1.4, 1.3, 0.6), C(0, 1.35, -0.85), light)
	part(m, "Head", BALL, V(1.8, 1.6, 1.6), C(0, 2.6, -0.9), col)
	part(m, "Muzzle", BALL, V(0.8, 0.5, 0.4), C(0, 2.3, -1.65), light)
	part(m, "Nose", BALL, V(0.2, 0.15, 0.12), C(0, 2.45, -1.82), Color3.fromRGB(240, 130, 150))
	for _, side in { -1, 1 } do
		local ear = C(side * 0.42, 3.25, -0.75) * CFrame.Angles(0.15, 0, -side * 0.18)
		fin(m, "Ear", ear, 0.22, 1.7, 0.6, col)
		fin(m, "EarInner", ear * C(0, 0.1, -0.1), 0.23, 1.2, 0.32, light)
		part(m, "BackLeg", BALL, V(0.8, 0.9, 1.4), C(side * 0.85, 0.5, 0.8), shade(col, -0.1))
		part(m, "Foot", BALL, V(0.5, 0.35, 0.9), C(side * 0.85, 0.15, 0.3), light)
		part(m, "Paw", BALL, V(0.4, 0.5, 0.45), C(side * 0.45, 0.3, -0.7), light)
	end
	part(m, "Bolt", BLOCK, V(0.14, 0.4, 0.08), C(-0.06, 3.0, -1.66) * CFrame.Angles(0, 0, 0.5), BOLT, Enum.Material.Neon)
	part(m, "Bolt", BLOCK, V(0.14, 0.4, 0.08), C(0.06, 2.72, -1.68) * CFrame.Angles(0, 0, 0.5), BOLT, Enum.Material.Neon)
	part(m, "Tail", BALL, V(0.7, 0.7, 0.7), C(0, 1.7, 1.6), Color3.new(1, 1, 1))
	return {
		Style = "Cute",
		Eyes = { C(-0.45, 2.75, -1.55), C(0.45, 2.75, -1.55) },
		EyeSize = 0.62,
		Mouth = C(0, 2.13, -1.72),
		Cheeks = { CFrame.lookAt(V(-0.75, 2.35, -1.4), V(-1.3, 2.35, -2.1)), CFrame.lookAt(V(0.75, 2.35, -1.4), V(1.3, 2.35, -2.1)) },
		Head = C(0, 3.4, -0.9),
		Tail = C(0, 1.8, 1.9),
		Body = { Center = V(0, 1.5, 0.3), Radius = 1.05 },
	}
end

Rigs.Stormcrest = function(m, col)
	local body = part(m, "Body", BALL, V(2.3, 2.3, 2.4), C(0, 2.4, 0), col)
	m.PrimaryPart = body
	part(m, "Belly", BALL, V(1.5, 1.5, 0.6), C(0, 2.15, -0.95), shade(col, 0.5))
	spike(m, "Beak", C(0, 2.3, -1.15) * CFrame.Angles(-math.pi / 2, 0, 0), 0.55, 0.4, Color3.fromRGB(255, 175, 60))
	for i = -1, 1 do
		fin(m, "Crest", C(i * 0.18, 3.45, 0.05 + math.abs(i) * 0.15) * CFrame.Angles(-0.3, 0, i * 0.35), 0.1, 0.9 - math.abs(i) * 0.2, 0.6, BOLT, Enum.Material.Neon)
	end
	for _, side in { -1, 1 } do
		fin(m, "Wing", C(side * 1.15, 2.5, 0.2) * CFrame.Angles(0, 0, -side * 1.25), 0.08, 1.7, 1.4, shade(col, -0.2))
		part(m, "Foot", BALL, V(0.3, 0.25, 0.45), C(side * 0.4, 1.2, -0.1), Color3.fromRGB(255, 175, 60))
	end
	fin(m, "Tail", C(0, 2.2, 1.15) * CFrame.Angles(math.pi / 2 + 0.4, 0, 0), 0.1, 0.9, 0.8, shade(col, -0.2))
	return {
		Style = "Cute",
		Eyes = { C(-0.5, 2.68, -1.04), C(0.5, 2.68, -1.04) },
		EyeSize = 0.72,
		Mouth = nil,
		Cheeks = { CFrame.lookAt(V(-0.8, 2.2, -0.9), V(-1.4, 2.2, -1.6)), CFrame.lookAt(V(0.8, 2.2, -0.9), V(1.4, 2.2, -1.6)) },
		Head = C(0, 3.55, 0),
		Tail = C(0, 2.3, 1.6),
		Body = { Center = V(0, 2.4, 0), Radius = 1.15 },
	}
end

Rigs.Thunderhorn = function(m, col)
	local light = shade(col, 0.45)
	local body = part(m, "Body", BALL, V(2.4, 2.2, 3.2), C(0, 2.0, 0.3), col)
	m.PrimaryPart = body
	part(m, "ChestFluff", BALL, V(1.6, 1.4, 0.9), C(0, 1.9, -1.0), light)
	part(m, "Head", BALL, V(1.6, 1.6, 1.7), C(0, 2.9, -1.55), col)
	part(m, "Snout", BALL, V(0.9, 0.7, 0.8), C(0, 2.55, -2.25), light)
	part(m, "Beard", BALL, V(0.4, 0.7, 0.35), C(0, 2.0, -2.2), light)
	for _, side in { -1, 1 } do
		-- Curled horn: three spikes bending back.
		local base = C(side * 0.45, 3.5, -1.5)
		spike(m, "Horn", base * CFrame.Angles(0.5, 0, -side * 0.3), 0.6, 0.4, shade(col, -0.35), Enum.Material.Slate)
		spike(m, "Horn", base * C(side * 0.15, 0.45, 0.35) * CFrame.Angles(1.3, 0, -side * 0.4), 0.55, 0.32, shade(col, -0.35), Enum.Material.Slate)
		part(m, "HornSpark", BALL, V(0.16, 0.16, 0.16), base * C(side * 0.25, 0.55, 0.9), BOLT, Enum.Material.Neon)
		fin(m, "Ear", C(side * 0.85, 3.0, -1.4) * CFrame.Angles(0, 0, -side * 1.3), 0.15, 0.5, 0.4, col)
		for _, z in { -0.75, 1.25 } do
			part(m, "Leg", BALL, V(0.55, 1.4, 0.6), C(side * 0.7, 0.75, z), col)
			part(m, "Paw", BALL, V(0.55, 0.3, 0.6), C(side * 0.7, 0.15, z - 0.05), Color3.fromRGB(45, 45, 55))
		end
	end
	part(m, "Tail", BALL, V(0.4, 0.5, 0.4), C(0, 2.5, 1.9), light)
	return {
		Style = "Fierce",
		IrisColor = BOLT,
		Eyes = { C(-0.42, 3.05, -2.3), C(0.42, 3.05, -2.3) },
		EyeSize = 0.42,
		Mouth = C(0, 2.32, -2.62),
		Cheeks = {},
		Head = C(0, 3.7, -1.55),
		Back = C(0, 3.1, 0.4),
		Tail = C(0, 2.6, 2.1),
		Body = { Center = V(0, 2.0, 0.3), Radius = 1.1 },
	}
end

-- ===== Toxic Bloom Swamp rigs =====
local VENOM = Color3.fromRGB(160, 255, 70)

Rigs.Sporeling = function(m, col)
	local stemCol = Color3.fromRGB(240, 230, 205)
	local stem = part(m, "Body", BALL, V(2.0, 2.2, 1.9), C(0, 1.3, 0), stemCol)
	m.PrimaryPart = stem
	part(m, "Cap", BALL, V(3.4, 1.7, 3.3), C(0, 2.75, 0.05), col)
	part(m, "CapUnder", BALL, V(3.0, 0.5, 2.9), C(0, 2.2, 0.05), shade(stemCol, -0.15))
	for i, pos in { V(-0.9, 3.3, -0.6), V(0.8, 3.35, -0.4), V(0.1, 3.55, 0.2), V(-0.6, 3.2, 0.8), V(1.0, 3.1, 0.7), V(-1.3, 2.9, 0.1) } do
		part(m, "CapSpot", BALL, V(0.55, 0.22, 0.55), CFrame.lookAt(pos, pos + (pos - V(0, 2.6, 0.05))) * CFrame.Angles(math.pi / 2, 0, i), Color3.new(1, 1, 1))
	end
	for _, side in { -1, 1 } do
		part(m, "Foot", BALL, V(0.65, 0.4, 0.8), C(side * 0.5, 0.2, -0.1), shade(stemCol, -0.1))
	end
	return {
		Style = "Cute",
		Eyes = { C(-0.45, 1.55, -0.92), C(0.45, 1.55, -0.92) },
		EyeSize = 0.6,
		Mouth = C(0, 1.1, -0.95),
		Cheeks = { CFrame.lookAt(V(-0.72, 1.2, -0.78), V(-1.3, 1.2, -1.5)), CFrame.lookAt(V(0.72, 1.2, -0.78), V(1.3, 1.2, -1.5)) },
		Head = C(0, 3.65, 0.05),
		Body = { Center = V(0, 1.3, 0), Radius = 0.95 },
	}
end

Rigs.Miretoad = function(m, col)
	local body = part(m, "Body", BALL, V(3.1, 2.1, 2.8), C(0, 1.25, 0.2), col)
	m.PrimaryPart = body
	part(m, "Belly", BALL, V(2.1, 1.3, 0.7), C(0, 0.95, -1.0), shade(col, 0.45))
	for _, x in { -0.75, 0.75 } do
		part(m, "EyeBulb", BALL, V(1.0, 1.0, 1.0), C(x, 2.15, -0.6), col)
		part(m, "BackLeg", BALL, V(1.1, 0.95, 1.8), C(x * 1.75, 0.55, 0.7), shade(col, -0.15))
		part(m, "FrontLeg", BALL, V(0.55, 0.7, 0.55), C(x, 0.35, -0.95), shade(col, -0.15))
	end
	for i, pos in { V(-0.8, 2.15, 0.5), V(0.7, 2.2, 0.9), V(0.1, 2.3, 0.2), V(-1.2, 1.7, 0.9), V(1.25, 1.75, 0.3), V(-0.2, 2.1, 1.2), V(0.5, 1.95, 1.4) } do
		part(m, "Wart", BALL, V(0.32, 0.32, 0.32), C(pos), shade(col, if i % 2 == 0 then -0.25 else 0.2))
	end
	return {
		Style = "Frog",
		Eyes = { C(-0.75, 2.22, -1.08), C(0.75, 2.22, -1.08) },
		EyeSize = 0.72,
		Mouth = C(0, 1.4, -1.25),
		Cheeks = { CFrame.lookAt(V(-1.1, 1.45, -0.9), V(-1.8, 1.45, -1.6)), CFrame.lookAt(V(1.1, 1.45, -0.9), V(1.8, 1.45, -1.6)) },
		Head = C(0, 2.8, -0.5),
		Back = C(0, 2.3, 0.4),
		Body = { Center = V(0, 1.25, 0.2), Radius = 1.2 },
	}
end

Rigs.Venomtail = function(m, col)
	local light = shade(col, 0.4)
	local body = part(m, "Body", BALL, V(2.0, 1.4, 3.2), C(0, 1.15, 0.2), col)
	m.PrimaryPart = body
	part(m, "Belly", BALL, V(1.4, 0.7, 2.6), C(0, 0.75, 0.1), light)
	part(m, "Head", BALL, V(1.5, 1.1, 1.5), C(0, 1.55, -1.7), col)
	part(m, "Snout", BALL, V(0.9, 0.55, 0.7), C(0, 1.35, -2.35), light)
	for _, side in { -1, 1 } do
		for _, z in { -0.7, 1.0 } do
			part(m, "Leg", BALL, V(0.45, 0.95, 0.45), C(side * 1.05, 0.5, z) * CFrame.Angles(0, 0, side * 0.6), shade(col, -0.15))
			part(m, "Paw", BALL, V(0.5, 0.22, 0.6), C(side * 1.35, 0.11, z - 0.05), shade(col, -0.25))
		end
	end
	-- Tail curls up and forward over the back to a glowing stinger.
	local segs = { { V(0, 1.3, 1.85), 0.75 }, { V(0, 1.9, 2.45), 0.65 }, { V(0, 2.65, 2.55), 0.55 }, { V(0, 3.25, 2.1), 0.45 } }
	for i, s in segs do
		part(m, if i == 1 then "TailBase" elseif i == #segs then "Tail" else "TailMid", BALL, V(s[2], s[2], s[2]), C(s[1]), if i % 2 == 0 then shade(col, -0.2) else col)
	end
	spike(m, "Tail", C(V(0, 3.45, 1.75)) * CFrame.Angles(-2.1, 0, 0), 0.5, 0.3, VENOM, Enum.Material.Neon)
	return {
		Style = "Fierce",
		IrisColor = VENOM,
		Eyes = { C(-0.45, 1.78, -2.3), C(0.45, 1.78, -2.3) },
		EyeSize = 0.42,
		Mouth = C(0, 1.15, -2.62),
		Cheeks = {},
		Head = C(0, 2.1, -1.7),
		Back = C(0, 1.85, 0.3),
		Tail = C(0, 3.5, 2.0),
		Body = { Center = V(0, 1.15, 0.2), Radius = 1.0 },
	}
end

-- Big glossy eyes, mouth and blush. eyeColor/eyeMat come from an Eye mutation, if any.
-- ===== Stage 9: Blender mesh rigs =====
-- Templates are Models of MeshParts in ReplicatedStorage.MonsterMeshes.<SpeciesId>,
-- imported from assets/models and saved in the place (Rojo does not manage them).
-- They are normalised once in Studio so each piece already sits in rig space;
-- Build clones them and styles each piece from MeshTones: a number (shade of the
-- palette colour), a Color3, "Texture" (keep the baked texture from Blender, as
-- is), or { Color, Material, Transparency } (plain, texture removed). Numbers and
-- Color3s tint a textured piece through its SurfaceAppearance. Anchors come from RigAnchors. A species
-- without a template, tones or anchors keeps its part rig.
local NEON_FLAME = { Color = Color3.fromRGB(255, 125, 25), Material = "Neon", Transparency = 0.05 }
MonsterVisuals.MeshTones = {
	Mossling = { Body = 0, Belly = 0.45, Foot = -0.18, Claw = -0.55, BackSpike = -0.45, Leaf = "Texture" },
	Cindermite = { Body = "Texture", Leg = "Texture", Arm = "Texture", Flame = NEON_FLAME },
}
-- Tests point this at their own folder; nil means ReplicatedStorage.MonsterMeshes.
MonsterVisuals.MeshFolder = nil :: Instance?

function MonsterVisuals.GetMeshTemplate(speciesId: string): Model?
	local folder = MonsterVisuals.MeshFolder or game:GetService("ReplicatedStorage"):FindFirstChild("MonsterMeshes")
	local t = folder and folder:FindFirstChild(speciesId)
	if not (t and t:IsA("Model") and t:FindFirstChild("Body")) then
		return nil
	end
	-- Hand-made rigs need tones + anchors; upgraded rigs only need the part rig.
	if (MonsterVisuals.MeshTones[speciesId] and RigAnchors[speciesId]) or Rigs[speciesId] then
		return t
	end
	return nil
end

-- Visible colour of a piece. A textured mesh shows its SurfaceAppearance tint
-- (multiplied over the baked texture), not BasePart.Color, so colour mutations
-- go through these.
local function getTint(p: BasePart): Color3
	local sa = p:FindFirstChildOfClass("SurfaceAppearance")
	return if sa then sa.Color else p.Color
end
local function setTint(p: BasePart, c: Color3)
	p.Color = c
	local sa = p:FindFirstChildOfClass("SurfaceAppearance")
	if sa then
		sa.Color = c
	end
end

-- Plain piece: no texture, explicit colour/material (neon flames, glass spikes).
local function makePlain(p: MeshPart, color: Color3, material: Enum.Material, transparency: number)
	for _, sa in p:GetChildren() do
		if sa:IsA("SurfaceAppearance") then
			sa:Destroy()
		end
	end
	p.TextureID = ""
	p.Color = color
	p.Material = material
	p.Transparency = transparency
end

local function addPiece(m: Model, p: MeshPart)
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Parent = m
end

local function finishMeshRig(m: Model)
	local body = m:FindFirstChild("Body") :: BasePart
	m.PrimaryPart = body
	-- Imported pieces carry the import's turn (e.g. 180 deg about Y). Pin the model
	-- pivot to the body centre with no rotation, as part rigs have, so PivotTo /
	-- lookAt callers (pet follower, reveal, viewports) face the monster along -Z.
	body.PivotOffset = body.CFrame:ToObjectSpace(CFrame.new(body.Position))
end

local function buildMeshRig(m: Model, template: Model, tones, col: Color3)
	for _, src in template:GetChildren() do
		if src:IsA("MeshPart") then
			local p = src:Clone()
			local tone = tones[p.Name]
			if type(tone) == "table" then
				makePlain(p, tone.Color, mat(tone.Material), tone.Transparency or 0)
			elseif tone ~= "Texture" then
				-- Palette shade: tints the baked texture when there is one.
				setTint(p, if typeof(tone) == "Color3" then tone else shade(col, tone or 0))
				p.Material = Enum.Material.SmoothPlastic
			end
			addPiece(m, p)
		end
	end
	finishMeshRig(m)
end

-- Upgraded rigs (assets/models/rig_upgrade.py): each mesh piece is a sculpted copy
-- of the part rig's same-named part(s), in the same place. The part rig is built
-- off-screen for its anchors and to colour each piece like its nearest same-named
-- part, so palettes, shading and glowing parts carry over without tone tables.
local PLAIN_MATERIALS = { [Enum.Material.Neon] = true, [Enum.Material.Glass] = true, [Enum.Material.ForceField] = true }
local function buildMeshFromRig(m: Model, template: Model, speciesId: string, col: Color3)
	local scratch = Instance.new("Model")
	local anchors = Rigs[speciesId](scratch, col)
	local byName: { [string]: { BasePart } } = {}
	for _, p in scratch:GetChildren() do
		if p:IsA("BasePart") then
			byName[p.Name] = byName[p.Name] or {}
			table.insert(byName[p.Name], p)
		end
	end
	for _, src in template:GetChildren() do
		if src:IsA("MeshPart") then
			local piece = src:Clone()
			local best, bestDist = nil, math.huge
			for _, p in byName[piece.Name] or {} do
				local d = (p.Position - piece.Position).Magnitude
				if d < bestDist then
					best, bestDist = p, d
				end
			end
			if best and PLAIN_MATERIALS[best.Material] then
				makePlain(piece, best.Color, best.Material, best.Transparency)
				piece.Reflectance = best.Reflectance
			elseif best then
				setTint(piece, best.Color)
				piece.Material = Enum.Material.SmoothPlastic
			end
			addPiece(m, piece)
		end
	end
	scratch:Destroy()
	finishMeshRig(m)
	return anchors
end

local function drawFace(m: Model, a, eyeColor: Color3?, eyeMat: Enum.Material?)
	local s = a.EyeSize
	local dark = Color3.fromRGB(22, 22, 34)
	for i, cf in a.Eyes do
		local side = if i == 1 then -1 else 1
		if a.Style == "Molten" then
			-- Big round glowing eyes in dark sockets, like embers looking out of rock.
			part(m, "Eye", BALL, V(s * 1.15, s * 1.15, s * 0.3), cf, Color3.fromRGB(25, 12, 10))
			part(m, "Iris", BALL, V(s * 0.9, s * 0.9, s * 0.2), cf * C(0, 0, -s * 0.08), eyeColor or Color3.fromRGB(255, 200, 60), eyeMat or Enum.Material.Neon)
			part(m, "Pupil", BALL, V(s * 0.42, s * 0.42, s * 0.12), cf * C(side * s * 0.04, -s * 0.02, -s * 0.15), Color3.fromRGB(30, 15, 10))
			part(m, "Glint", BALL, V(s * 0.16, s * 0.16, s * 0.08), cf * C(-s * 0.2, s * 0.22, -s * 0.2), WHITE, Enum.Material.Neon)
		elseif a.Style == "Fierce" then
			part(m, "Eye", BALL, V(s * 1.15, s * 0.8, s * 0.4), cf, dark)
			part(m, "Iris", BALL, V(s * 0.75, s * 0.55, s * 0.2), cf * C(0, -s * 0.03, -s * 0.15), eyeColor or a.IrisColor or WHITE, Enum.Material.Neon)
			part(m, "Glint", BALL, V(s * 0.2, s * 0.2, s * 0.1), cf * C(-s * 0.18, s * 0.1, -s * 0.24), WHITE, Enum.Material.Neon)
			part(m, "Brow", BLOCK, V(s * 1.35, s * 0.24, s * 0.3), cf * C(side * -s * 0.05, s * 0.48, -s * 0.12) * CFrame.Angles(0, 0, side * -0.4), dark)
		else
			local base = if eyeColor then eyeColor:Lerp(BLACK, 0.35) else dark
			part(m, "Eye", BALL, V(s * 0.85, s, s * 0.45), cf, base, eyeMat)
			part(m, "Glint", BALL, V(s * 0.42, s * 0.42, s * 0.14), cf * C(s * 0.14, s * 0.2, -s * 0.2), WHITE, Enum.Material.Neon)
			part(m, "Glint", BALL, V(s * 0.2, s * 0.2, s * 0.1), cf * C(-s * 0.17, -s * 0.22, -s * 0.2), WHITE, Enum.Material.Neon)
		end
	end
	local mouth = a.Mouth
	if mouth then
		if a.Style == "Fierce" then
			part(m, "Mouth", BLOCK, V(0.55, 0.06, 0.05), mouth, dark)
			for _, x in { -0.16, 0.16 } do
				spike(m, "Fang", mouth * C(x, 0.02, -0.02) * CFrame.Angles(math.pi, 0, 0), 0.22, 0.13, WHITE)
			end
		elseif a.Style == "Molten" then
			-- Dark slot with a hot glow inside.
			part(m, "Mouth", BLOCK, V(0.8, 0.26, 0.08), mouth, Color3.fromRGB(30, 12, 8))
			part(m, "Mouth", BLOCK, V(0.6, 0.08, 0.06), mouth * C(0, -0.04, -0.03), Color3.fromRGB(255, 110, 30), Enum.Material.Neon)
		elseif a.Style == "Frog" then
			part(m, "Mouth", BLOCK, V(0.75, 0.07, 0.05), mouth, dark)
			for _, side in { -1, 1 } do
				part(m, "Mouth", BLOCK, V(0.3, 0.07, 0.05), mouth * C(side * 0.47, 0.06, 0.02) * CFrame.Angles(0, 0, side * 0.45), dark)
			end
		else
			for _, side in { -1, 1 } do
				part(m, "Mouth", BLOCK, V(0.2, 0.06, 0.05), mouth * C(side * 0.085, 0, 0) * CFrame.Angles(0, 0, side * 0.55), dark)
			end
		end
	end
	for _, cf in a.Cheeks or {} do
		part(m, "Blush", BALL, V(0.45, 0.28, 0.1), cf, BLUSH)
	end
end

-- Deterministic points on the upper half of a sphere (for spots/patterns).
local function surfacePoints(body, n: number, seed: number)
	local rng = Random.new(seed)
	local pts = {}
	for _ = 1, n do
		local theta = rng:NextNumber(0, math.pi * 2)
		local phi = rng:NextNumber(0.15, 1.25)
		local dir = V(math.cos(theta) * math.sin(phi), math.cos(phi), math.sin(theta) * math.sin(phi))
		table.insert(pts, body.Center + dir * body.Radius * 0.97)
	end
	return pts
end

local function addOrbiters(m: Model, center: Vector3, count: number, radius: number, color: Color3, size: number, speed: number)
	count = math.min(count, MonsterVisuals.MAX_ORBITERS)
	for i = 1, count do
		local p = part(m, "Orbiter", BALL, V(size, size, size), C(center), color, Enum.Material.Neon)
		p:SetAttribute("OrbitCenter", center)
		p:SetAttribute("OrbitRadius", radius)
		p:SetAttribute("OrbitPhase", (i - 1) / count * math.pi * 2)
		p:SetAttribute("OrbitSpeed", speed)
		p:SetAttribute("OrbitBob", (i % 2) * 0.4)
	end
end

-- Mutation-specific builders. Unknown mutations fall back to a small accent at their region.
local Builders = {}

Builders.DewdropEyes = function() end -- applied in eye pass

Builders.PebblePlating = function(m, a, v)
	for i = -1, 1 do
		part(m, "Plate", BALL, V(0.9, 0.35, 0.9), a.Back * C(i * 0.6, 0, i * 0.2), v.Color, mat(v.Material))
	end
end

Builders.AncientBarkArmour = function(m, a, v)
	for i = -1, 1 do
		part(m, "Bark", BLOCK, V(0.6, 0.45, 1.6), a.Back * C(i * 0.65, -0.1 * math.abs(i), 0) * CFrame.Angles(0, 0, math.rad(-i * 22)), v.Color, mat(v.Material))
	end
end

Builders.LivingGrove = function(m, a, v)
	for i, off in { V(-0.55, 0, 0.2), V(0.5, 0, -0.1), V(0, 0, 0.6) } do
		local h = 0.6 + i * 0.15
		part(m, "Trunk", CYL, V(h, 0.18, 0.18), a.Back * C(off + V(0, h / 2, 0)) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(110, 75, 45), Enum.Material.Wood)
		part(m, "Canopy", BALL, V(0.7, 0.6, 0.7), a.Back * C(off + V(0, h + 0.2, 0)), v.Color, Enum.Material.Grass)
	end
end

Builders.BioluminescentLeaves = function(m, a, v)
	for i = 1, 4 do
		local ang = (i - 2.5) * 0.5
		part(m, "GlowLeaf", BLOCK, V(0.1, 0.8, 0.45), a.Back * CFrame.Angles(0, 0, ang) * C(0, 0.45, (i % 2) * 0.3), v.Color, Enum.Material.Neon)
	end
end

Builders.SmallHornBuds = function(m, a, v)
	for _, x in { -0.35, 0.35 } do
		part(m, "HornBud", BALL, V(0.3, 0.45, 0.3), a.Head * C(x, 0, 0), v.Color)
	end
end

Builders.CloverCrown = function(m, a, v)
	for i = 1, 4 do
		local ang = i / 4 * math.pi * 2
		local pos = a.Head * C(math.cos(ang) * 0.45, 0, math.sin(ang) * 0.45)
		for j = 0, 1 do
			part(m, "Clover", BALL, V(0.32, 0.12, 0.32), pos * C(j * 0.14 - 0.07, 0.02, 0), v.Color, Enum.Material.Grass)
		end
	end
end

Builders.Springtail = function(m, a, v)
	if not a.Tail then
		return
	end
	local old = m:FindFirstChild("Tail")
	if old then
		old:Destroy()
	end
	for i = 0, 6 do
		local ang = i * 1.1
		part(m, "Coil", BALL, V(0.32, 0.32, 0.32), a.Tail * C(math.cos(ang) * 0.25, i * 0.12, i * 0.12 + math.sin(ang) * 0.25), v.Color)
	end
end

Builders.Thornbound = function(m, a, v)
	local b = a.Body
	for i = 1, 3 do
		local tilt = CFrame.Angles(math.rad(70 + i * 15), math.rad(i * 60), 0)
		for j = 0, 9 do
			local ang = j / 10 * math.pi * 2
			local pos = C(b.Center) * tilt * C(math.cos(ang) * b.Radius * 1.02, 0, math.sin(ang) * b.Radius * 1.02)
			part(m, "Thorn", BALL, V(0.18, 0.18, 0.18), pos, v.Color)
		end
	end
end

Builders.VerdantGuardian = function(m, a, v)
	addOrbiters(m, a.Body.Center + V(0, 0.6, 0), 3, a.Body.Radius + 0.9, v.Color, 0.35, 1.2)
	part(m, "GuardianGem", BALL, V(0.45, 0.45, 0.45), C(a.Body.Center + V(0, 0.2, -a.Body.Radius)), v.Color, Enum.Material.Neon)
end

Builders.ElderwoodHeart = function(m, a, v)
	part(m, "HeartCore", BALL, V(0.7, 0.7, 0.7), C(a.Body.Center + V(0, 0.1, -a.Body.Radius * 0.9)), Color3.fromRGB(255, 200, 90), Enum.Material.Neon)
	for i = 1, 5 do
		local ang = i / 5 * math.pi * 2
		part(m, "HeartRoot", BLOCK, V(0.12, 0.12, 0.9), C(a.Body.Center + V(math.cos(ang) * 0.5, math.sin(ang) * 0.5, -a.Body.Radius * 0.85)) * CFrame.Angles(0, 0, ang), v.Color, Enum.Material.Wood)
	end
end

Builders.WorldtreeSeed = function(m, a, v)
	local top = (a.Head or C(a.Body.Center)).Position + V(0, 1.1, 0)
	part(m, "Seed", BALL, V(0.55, 0.75, 0.55), C(top), v.Color, Enum.Material.Neon)
	addOrbiters(m, top, 6, 0.8, Color3.fromRGB(255, 255, 200), 0.15, 2)
end

-- ===== Frostfall =====
Builders.IceTippedTail = function(m, a, v)
	if a.Tail then
		part(m, "IceTip", BALL, V(0.55, 0.55, 0.55), a.Tail, v.Color, mat(v.Material))
	end
end

Builders.CrystalWhiskers = function(m, a, v)
	local mid = (a.Eyes[1].Position + a.Eyes[2].Position) / 2 - V(0, 0.35, 0.1)
	for _, side in { -1, 1 } do
		for j = 0, 1 do
			local start = mid + V(side * 0.35, -j * 0.12, 0)
			part(m, "Whisker", BLOCK, V(0.7, 0.05, 0.05), C(start + V(side * 0.35, 0, 0)) * CFrame.Angles(0, 0, side * (0.15 - j * 0.3)), v.Color, Enum.Material.Glass)
		end
	end
end

Builders.FrostedHorns = function(m, a, v)
	for _, x in { -0.4, 0.4 } do
		part(m, "Horn", BLOCK, V(0.25, 0.8, 0.25), a.Head * C(x, 0.3, 0) * CFrame.Angles(0, 0, -x * 0.6), v.Color, mat(v.Material))
	end
end

Builders.CrystalAntlers = function(m, a, v)
	for _, side in { -1, 1 } do
		local base = a.Head * C(side * 0.35, 0.1, 0)
		part(m, "Antler", BLOCK, V(0.18, 1.2, 0.18), base * CFrame.Angles(0, 0, -side * 0.35) * C(0, 0.6, 0), v.Color, Enum.Material.Glass)
		for k = 1, 2 do
			part(m, "AntlerTine", BLOCK, V(0.12, 0.6, 0.12), base * CFrame.Angles(0, 0, -side * 0.35) * C(0, 0.4 + k * 0.35, 0) * CFrame.Angles(0, 0, -side * 0.9) * C(0, 0.3, 0), v.Color, Enum.Material.Neon)
		end
	end
end

local function plates(m, a, v, count, size)
	local at = a.Back or (C(a.Body.Center + V(0, a.Body.Radius * 0.85, 0)))
	for i = 1, count do
		local off = (i - (count + 1) / 2) * 0.55
		part(m, "Plate", BLOCK, size, at * C(0, 0, off) * CFrame.Angles(0, math.rad(45), 0), v.Color, mat(v.Material))
	end
end
Builders.FrozenArmour = function(m, a, v)
	plates(m, a, v, 3, V(0.8, 0.35, 0.8))
end
Builders.IceglassArmour = function(m, a, v)
	plates(m, a, v, 4, V(0.9, 0.5, 0.9))
end
Builders.GlacierScales = function(m, a, v)
	for i, pos in surfacePoints(a.Body, 9, 7) do
		local cf = CFrame.lookAt(pos, pos + (pos - a.Body.Center)) * CFrame.Angles(math.pi / 2, 0, i)
		part(m, "Scale", BLOCK, V(0.45, 0.12, 0.45), cf, v.Color, mat(v.Material))
	end
end

Builders.Chilled = function(m, a, v)
	local body = m.PrimaryPart
	setTint(body, getTint(body):Lerp(v.Color, 0.35))
end
Builders.FrozenCore = function(m, a, v)
	part(m, "FrostCore", BALL, V(0.6, 0.6, 0.6), C(a.Body.Center + V(0, 0.1, -a.Body.Radius * 0.95)), v.Color, Enum.Material.Neon)
end
Builders.PermafrostVeins = function(m, a, v)
	for i = 1, 6 do
		local ang = i / 6 * math.pi * 2
		local pos = a.Body.Center + V(math.cos(ang), 0.2, math.sin(ang)) * a.Body.Radius * 0.98
		part(m, "Vein", BLOCK, V(0.08, 0.9, 0.08), CFrame.lookAt(pos, a.Body.Center) * CFrame.Angles(0, 0, ang), v.Color, Enum.Material.Neon)
	end
end
Builders.BlizzardHeart = function(m, a, v)
	addOrbiters(m, a.Body.Center, 6, a.Body.Radius + 0.6, v.Color, 0.25, 2.2)
	part(m, "StormCore", BALL, V(0.55, 0.55, 0.55), C(a.Body.Center + V(0, 0.1, -a.Body.Radius * 0.95)), Color3.fromRGB(230, 245, 255), Enum.Material.Neon)
end
Builders.GlacialGuardian = function(m, a, v)
	addOrbiters(m, a.Body.Center + V(0, 0.5, 0), 4, a.Body.Radius + 1.0, v.Color, 0.4, 1.0)
end
Builders.EternalWinter = function(m, a, v)
	local head = a.Head or C(a.Body.Center + V(0, a.Body.Radius, 0))
	for i = 1, 5 do
		local ang = i / 5 * math.pi * 2
		part(m, "IceSpike", BLOCK, V(0.15, 0.6, 0.15), head * C(math.cos(ang) * 0.4, 0.25, math.sin(ang) * 0.4), v.Color, Enum.Material.Glass)
	end
end
Builders.AuroraSovereign = function(m, a, v)
	local head = a.Head or C(a.Body.Center + V(0, a.Body.Radius, 0))
	local colors = { Color3.fromRGB(120, 255, 190), Color3.fromRGB(150, 120, 255), Color3.fromRGB(90, 200, 255) }
	for i = 1, 6 do
		local ang = i / 6 * math.pi * 2
		part(m, "Halo", BALL, V(0.25, 0.25, 0.25), head * C(math.cos(ang) * 0.6, 0.5, math.sin(ang) * 0.6), colors[(i % 3) + 1], Enum.Material.Neon)
	end
	addOrbiters(m, a.Body.Center + V(0, 0.8, 0), 6, a.Body.Radius + 0.9, colors[1], 0.2, 1.4)
end
Builders.AbsoluteZero = function(m, a, v)
	local body = m.PrimaryPart
	body.Material = Enum.Material.Glass
	setTint(body, v.Color)
	addOrbiters(m, a.Body.Center, 8, a.Body.Radius + 0.5, Color3.fromRGB(200, 240, 255), 0.15, 0.4)
end

-- ===== Hybrids =====
Builders.PermafrostShell = function(m, a, v)
	for i = 1, 5 do
		local ang = (i - 3) * 0.45
		local cf = a.Back * CFrame.Angles(0, 0, ang) * C(0, 0.15, (i % 2) * 0.35 - 0.15)
		part(m, "FrostPlate", BLOCK, V(0.75, 0.3, 0.9), cf * CFrame.Angles(0, math.rad(45), 0), v.Color, Enum.Material.Ice)
		spike(m, "FrostSpike", cf * C(0, 0.15, 0), 0.5, 0.3, Color3.fromRGB(210, 240, 255), Enum.Material.Glass)
	end
end

Builders.Rootstone = function(m, a, v)
	local b = a.Body
	for i = 1, 6 do
		local ang = i / 6 * math.pi * 2
		local pos = b.Center + V(math.cos(ang), -0.1, math.sin(ang)) * b.Radius * 1.0
		part(m, "Root", BLOCK, V(0.16, 1.1, 0.16), CFrame.lookAt(pos, b.Center) * CFrame.Angles(0, 0, ang * 0.5), v.Color, Enum.Material.Wood)
	end
	for i = 1, 3 do
		part(m, "RootStone", BALL, V(0.5, 0.35, 0.5), a.Back * C((i - 2) * 0.55, 0.1, (i % 2) * 0.3), Color3.fromRGB(125, 125, 130), Enum.Material.Slate)
	end
	fin(m, "RootSprout", a.Back * C(0, 0.25, 0), 0.12, 0.8, 0.6, Color3.fromRGB(90, 200, 90))
end

Builders.Frostbloom = function(m, a, v)
	local center = a.Head * C(0, 0.15, 0)
	for i = 1, 6 do
		local ang = i / 6 * math.pi * 2
		part(m, "Petal", BALL, V(0.42, 0.14, 0.26), center * CFrame.Angles(0, ang, 0) * C(0.3, 0, 0) * CFrame.Angles(0, 0, 0.35), v.Color, Enum.Material.Neon)
	end
	part(m, "BloomCore", BALL, V(0.28, 0.28, 0.28), center * C(0, 0.06, 0), Color3.fromRGB(255, 255, 255), Enum.Material.Neon)
	for _, side in { -1, 1 } do
		fin(m, "FrostLeaf", center * C(side * 0.55, -0.1, 0) * CFrame.Angles(0, 0, -side * 1.0), 0.1, 0.7, 0.45, Color3.fromRGB(120, 200, 190), Enum.Material.Ice)
	end
end

Builders.Icefloe = function(m, a, v)
	local b = a.Body
	local bottom = b.Center.Y - b.Radius - 0.6
	part(m, "Floe", CYL, V(0.4, b.Radius * 3.4, b.Radius * 3.0), C(0, math.max(bottom, 0.15), b.Center.Z) * CFrame.Angles(0, 0.3, math.pi / 2), v.Color, Enum.Material.Ice)
	for i = 1, 4 do
		local ang = i / 4 * math.pi * 2 + 0.4
		part(m, "FloeChunk", BLOCK, V(0.5, 0.35, 0.45), C(math.cos(ang) * b.Radius * 1.5, math.max(bottom, 0.15) + 0.25, b.Center.Z + math.sin(ang) * b.Radius * 1.3) * CFrame.Angles(0.2, ang, 0.1), Color3.fromRGB(230, 245, 255), Enum.Material.Glass)
	end
end

Builders.PrismaticAurora = function(m, a, v)
	local rainbow = { Color3.fromRGB(255, 90, 120), Color3.fromRGB(255, 190, 70), Color3.fromRGB(120, 255, 150), Color3.fromRGB(90, 190, 255), Color3.fromRGB(190, 120, 255) }
	for i, col in rainbow do
		local ang = (i - 3) * 0.35
		spike(m, "Prism", a.Head * CFrame.Angles(0, 0, ang) * C(0, 0.1, 0), 0.9 - math.abs(i - 3) * 0.12, 0.28, col, Enum.Material.Neon)
	end
	for i, col in rainbow do
		addOrbiters(m, a.Body.Center + V(0, 0.9, 0), 1, a.Body.Radius + 1.1, col, 0.24, 1.3)
		local kids = m:GetChildren()
		kids[#kids]:SetAttribute("OrbitPhase", i / #rainbow * math.pi * 2) -- spread the colours evenly
	end
end

-- ===== Stage 7: species-compatible mutations =====
-- Collar/mane ring around the upper body (works on every rig).
local function collar(m, a, color, material, count, size)
	local b = a.Body
	for i = 1, count do
		local ang = i / count * math.pi * 2
		local pos = b.Center + V(math.cos(ang) * b.Radius * 0.95, b.Radius * 0.45, math.sin(ang) * b.Radius * 0.95)
		part(m, "Tuft", BALL, size, CFrame.lookAt(pos, pos + (pos - b.Center)), color, material)
	end
end

Builders.LilyPadHat = function(m, a, v)
	part(m, "LilyPad", CYL, V(0.08, 1.3, 1.3), a.Head * C(0, 0.08, 0) * CFrame.Angles(0, 0, math.pi / 2), v.Color, Enum.Material.Grass)
	for i = 1, 5 do
		local ang = i / 5 * math.pi * 2
		part(m, "LilyPetal", BALL, V(0.3, 0.12, 0.18), a.Head * C(math.cos(ang) * 0.15, 0.22, math.sin(ang) * 0.15) * CFrame.Angles(0, -ang, 0.5), Color3.fromRGB(255, 170, 210))
	end
end

Builders.MossyMane = function(m, a, v)
	collar(m, a, v.Color, Enum.Material.Grass, 9, V(0.6, 0.6, 0.35))
end

Builders.PetalTail = function(m, a, v)
	if not a.Tail then
		return
	end
	for i = -2, 2 do
		part(m, "TailPetal", BALL, V(0.25, 0.12, 0.7), a.Tail * CFrame.Angles(0, i * 0.35, 0) * C(0, 0.1, 0.35), v.Color, Enum.Material.SmoothPlastic)
	end
end

Builders.SnowCape = function(m, a, v)
	collar(m, a, v.Color, Enum.Material.Snow, 10, V(0.65, 0.65, 0.4))
end

Builders.IcicleFins = function(m, a, v)
	if not a.Tail then
		return
	end
	for i = -1, 1 do
		spike(m, "Icicle", a.Tail * C(i * 0.22, -0.1, 0) * CFrame.Angles(math.pi, 0, 0), 0.55 - math.abs(i) * 0.15, 0.18, v.Color, Enum.Material.Glass)
	end
end

Builders.RimeCrown = function(m, a, v)
	for i = 1, 7 do
		local ang = i / 7 * math.pi * 2
		spike(m, "RimeSpike", a.Head * C(math.cos(ang) * 0.42, 0, math.sin(ang) * 0.42), 0.45 + (i % 2) * 0.2, 0.2, v.Color, Enum.Material.Glass)
	end
	part(m, "RimeGem", BALL, V(0.25, 0.25, 0.25), a.Head * C(0, 0.25, -0.42), Color3.fromRGB(140, 220, 255), Enum.Material.Neon)
end

-- ===== Data-driven looks =====
-- New mutations can pick a look with Visual.Kind instead of a bespoke builder:
--   Plates, Horns, Crown, Spikes, Core, Orbit, Veins, TailTip, Fins, Wings, Antlers,
--   Shell, Tint. Optional: Count, Color, Material, Accent (second colour).
local KindBuilders = {}

-- "None": the effect is applied elsewhere (e.g. Eye mutations recolour the eyes).
KindBuilders.None = function() end

KindBuilders.Plates = function(m, a, v)
	plates(m, a, v, v.Count or 3, V(0.85, 0.35, 0.85))
end

KindBuilders.Horns = function(m, a, v)
	for _, side in { -1, 1 } do
		spike(m, "KindHorn", a.Head * C(side * 0.38, -0.05, 0) * CFrame.Angles(-0.3, 0, -side * 0.45), 0.75, 0.3, v.Color, mat(v.Material))
	end
end

KindBuilders.Crown = function(m, a, v)
	local n = v.Count or 6
	for i = 1, n do
		local ang = i / n * math.pi * 2
		spike(m, "KindCrown", a.Head * C(math.cos(ang) * 0.42, 0, math.sin(ang) * 0.42), 0.45 + (i % 2) * 0.2, 0.2, v.Color, mat(v.Material))
	end
	part(m, "KindCrownGem", BALL, V(0.25, 0.25, 0.25), a.Head * C(0, 0.25, -0.42), v.Accent or Color3.new(1, 1, 1), Enum.Material.Neon)
end

KindBuilders.Spikes = function(m, a, v)
	local n = v.Count or 4
	for k = 0, n - 1 do
		spike(m, "KindSpike", a.Back * C(0, -k * 0.06, -0.5 + k * (1.2 / math.max(n - 1, 1))) * CFrame.Angles(0.3, 0, 0), 0.6 - k * 0.05, 0.4, v.Color, mat(v.Material))
	end
end

KindBuilders.Core = function(m, a, v)
	part(m, "KindCore", BALL, V(0.6, 0.6, 0.6), C(a.Body.Center + V(0, 0.1, -a.Body.Radius * 0.95)), v.Color, Enum.Material.Neon)
end

KindBuilders.Orbit = function(m, a, v)
	addOrbiters(m, a.Body.Center + V(0, 0.5, 0), v.Count or 4, a.Body.Radius + 0.9, v.Color, 0.3, 1.1)
end

KindBuilders.Veins = function(m, a, v)
	local n = v.Count or 6
	for i = 1, n do
		local ang = i / n * math.pi * 2
		local pos = a.Body.Center + V(math.cos(ang), 0.25, math.sin(ang)) * a.Body.Radius * 0.99
		part(m, "KindVein", BLOCK, V(0.08, 0.9, 0.08), CFrame.lookAt(pos, a.Body.Center) * CFrame.Angles(0, 0, ang), v.Color, Enum.Material.Neon)
	end
end

KindBuilders.TailTip = function(m, a, v)
	if a.Tail then
		part(m, "IceTip", BALL, V(0.55, 0.55, 0.55), a.Tail, v.Color, mat(v.Material))
	end
end

KindBuilders.Fins = function(m, a, v)
	for _, side in { -1, 1 } do
		local at = C(a.Body.Center + V(side * a.Body.Radius * 0.95, 0.1, 0.1))
		fin(m, "KindFin", at * CFrame.Angles(0, 0, -side * 1.2), 0.1, 0.9, 1.1, v.Color, mat(v.Material))
	end
	fin(m, "KindFin", C(a.Body.Center + V(0, a.Body.Radius * 0.95, 0.2)), 0.1, 0.8, 1.2, v.Color, mat(v.Material))
end

KindBuilders.Wings = function(m, a, v)
	for _, side in { -1, 1 } do
		local at = C(a.Body.Center + V(side * a.Body.Radius * 0.8, a.Body.Radius * 0.5, 0.2))
		fin(m, "Wing", at * CFrame.Angles(0, 0, -side * 1.35), 0.08, 1.7, 1.3, v.Color, mat(v.Material))
	end
end

KindBuilders.Antlers = function(m, a, v)
	for _, side in { -1, 1 } do
		local base = a.Head * C(side * 0.35, 0.1, 0)
		part(m, "Antler", BLOCK, V(0.18, 1.1, 0.18), base * CFrame.Angles(0, 0, -side * 0.35) * C(0, 0.55, 0), v.Color, mat(v.Material))
		for k = 1, 2 do
			part(m, "AntlerTine", BLOCK, V(0.12, 0.55, 0.12), base * CFrame.Angles(0, 0, -side * 0.35) * C(0, 0.35 + k * 0.32, 0) * CFrame.Angles(0, 0, -side * 0.9) * C(0, 0.27, 0), v.Accent or v.Color, mat(v.Material))
		end
	end
end

KindBuilders.Shell = function(m, a, v)
	local b = a.Body
	part(m, "KindShell", BALL, V(b.Radius * 2.15, b.Radius * 1.2, b.Radius * 2.15), C(b.Center + V(0, b.Radius * 0.45, 0.1)), v.Color, mat(v.Material))
end

-- A little mushroom cap on the head (Accent = spot colour).
KindBuilders.Cap = function(m, a, v)
	part(m, "CapStem", BALL, V(0.35, 0.5, 0.35), a.Head * C(0, 0.2, 0), Color3.fromRGB(240, 235, 215))
	part(m, "CapTop", BALL, V(1.1, 0.6, 1.1), a.Head * C(0, 0.5, 0), v.Color, mat(v.Material))
	for i = 1, 4 do
		local ang = i / 4 * math.pi * 2
		part(m, "CapDot", BALL, V(0.18, 0.08, 0.18), a.Head * C(math.cos(ang) * 0.3, 0.75, math.sin(ang) * 0.3), v.Accent or Color3.new(1, 1, 1))
	end
end

KindBuilders.Tint = function(m, a, v)
	local body = m.PrimaryPart
	setTint(body, getTint(body):Lerp(v.Color, 0.4))
end

-- ===== Realism details (every monster) =====
-- Two-tone shading (darker back), glossy eyes, toe pads, tufts and nostrils.
local function detailPass(m: Model, a, col: Color3, speciesId: string)
	local body = m.PrimaryPart :: BasePart
	-- Part rigs only; mesh bodies (no Shape property) carry their own shading.
	if body:IsA("Part") and (body.Shape == BALL or body:FindFirstChildOfClass("SpecialMesh")) then
		local s = body.Size
		part(m, "BackShade", BALL, V(s.X * 0.97, s.Y * 0.9, s.Z * 0.97), body.CFrame * C(0, s.Y * 0.09, s.Z * 0.02), shade(col, -0.16))
	end
	for _, p in m:GetChildren() do
		if p.Name == "Eye" then
			(p :: BasePart).Reflectance = 0.18
		elseif p.Name == "Foot" or p.Name == "Paw" then
			local fp = p :: BasePart
			for dx = -1, 1 do
				part(m, "Toe", BALL, V(0.17, 0.12, 0.17), fp.CFrame * C(dx * fp.Size.X * 0.25, -fp.Size.Y * 0.32, -fp.Size.Z * 0.42), shade(col, 0.4))
			end
		end
	end
	if speciesId == "Frostfang" or speciesId == "Snowmote" then
		for i, eye in a.Eyes do
			local side = if i == 1 then -1 else 1
			fin(m, "Tuft", eye * C(side * a.EyeSize * 1.2, -a.EyeSize * 0.6, 0.15) * CFrame.Angles(0, 0, side * 1.2), 0.12, 0.45, 0.35, shade(col, 0.3))
		end
	end
	if (speciesId == "Pebbleback" or speciesId == "Brookhopper") and a.Mouth then
		for _, x in { -0.13, 0.13 } do
			part(m, "Nostril", BALL, V(0.08, 0.06, 0.05), a.Mouth * C(x, 0.3, -0.02), Color3.fromRGB(30, 30, 40))
		end
	end
end

-- ===== Rarity aura (visible in viewports too; particles are world-only) =====
-- Grows with tier: halo (Uncommon+), orbiting sparks (Rare+), ground disc (Epic+),
-- light pillars (Legendary+), crown star + outer ring (Mythic+).
local function rarityAura(m: Model, a, tier: number, groundY: number)
	if tier < 2 then
		return
	end
	local def = Rarity.Get(tier) or Rarity.Tiers[1]
	local b = a.Body
	local halo = part(m, "AuraHalo", BALL, V(b.Radius * 2.9, b.Radius * 2.7, b.Radius * 2.9), C(b.Center), def.Color, Enum.Material.Neon)
	-- Kept faint so the monster's own colours always read through.
	halo.Transparency = math.max(0.9, 0.95 - tier * 0.008)
	if tier >= 3 then
		addOrbiters(m, b.Center + V(0, b.Radius * 0.3, 0), math.min(tier + 1, MonsterVisuals.MAX_ORBITERS), b.Radius + 1.2, def.Color, 0.16 + tier * 0.02, 0.9)
	end
	if tier >= 4 then
		local disc = part(m, "AuraDisc", CYL, V(0.1, b.Radius * 3.6, b.Radius * 3.6), C(b.Center.X, groundY + 0.06, b.Center.Z) * CFrame.Angles(0, 0, math.pi / 2), def.Color, Enum.Material.Neon)
		disc.Transparency = 0.55
	end
	if tier >= 5 then
		for i = 1, 6 do
			local ang = i / 6 * math.pi * 2
			local h = 2.5 + tier * 0.4
			local beam = part(m, "AuraBeam", BLOCK, V(0.12, h, 0.12), C(b.Center.X + math.cos(ang) * b.Radius * 1.7, groundY + h / 2, b.Center.Z + math.sin(ang) * b.Radius * 1.7), def.Color, Enum.Material.Neon)
			beam.Transparency = 0.7
		end
	end
	if tier >= 6 then
		local top = (a.Head or C(b.Center + V(0, b.Radius, 0))).Position + V(0, 1.3, 0)
		spike(m, "AuraStar", C(top), 0.5, 0.35, Color3.new(1, 1, 1), Enum.Material.Neon)
		spike(m, "AuraStar", C(top + V(0, 0.5, 0)) * CFrame.Angles(math.pi, 0, 0), 0.5, 0.35, Color3.new(1, 1, 1), Enum.Material.Neon)
		addOrbiters(m, b.Center, MonsterVisuals.MAX_ORBITERS, b.Radius + 2.0, Color3.new(1, 1, 1), 0.14, -0.6)
	end
end

local function applyPattern(m: Model, anchors, v, seedBase: number)
	local body = m.PrimaryPart
	if v.Pattern == "Moss" then
		body.Material = Enum.Material.Grass
		setTint(body, getTint(body):Lerp(v.Color, 0.6))
		return
	end
	if v.Pattern == "Frost" then
		setTint(body, getTint(body):Lerp(v.Color, 0.65))
		body.Material = Enum.Material.Ice
		return
	end
	local count = if v.Pattern == "Droplets" or v.Pattern == "Aurora" then 10 else 7
	local size = if v.Pattern == "Leaves" or v.Pattern == "Aurora" then V(0.55, 0.12, 0.35) else V(0.35, 0.35, 0.35)
	local auroraColors = { v.Color, Color3.fromRGB(160, 120, 255), Color3.fromRGB(90, 200, 255) }
	for i, pos in surfacePoints(anchors.Body, count, seedBase) do
		local shape = if v.Pattern == "Leaves" or v.Pattern == "Aurora" then BLOCK else BALL
		local cf = CFrame.lookAt(pos, pos + (pos - anchors.Body.Center)) * CFrame.Angles(math.pi / 2, 0, i)
		local color = if v.Pattern == "Aurora" then auroraColors[(i % 3) + 1] else v.Color
		part(m, "Pattern", shape, size, cf, color, mat(v.Material))
	end
end

local function applyAura(m: Model, anchors, v)
	local count = math.clamp(math.floor((v.Rate or 2) * 1.5), 2, MonsterVisuals.MAX_ORBITERS)
	addOrbiters(m, anchors.Body.Center + V(0, 0.4, 0), count, anchors.Body.Radius + 0.7, v.Color, 0.22, 0.8)
	-- World-only particles (ViewportFrames do not render particles). Low, capped rate.
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "AuraEmitter"
	emitter.Color = ColorSequence.new(v.Color)
	emitter.Rate = math.min(v.Rate or 2, 6)
	emitter.Lifetime = NumberRange.new(1, 1.6)
	emitter.Speed = NumberRange.new(0.3, 0.8)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Size = NumberSequence.new(0.25, 0)
	emitter.LightEmission = 0.6
	emitter.Parent = m.PrimaryPart
end

-- Builds a model. opts: { Silhouette: boolean?, Seed: number?, RarityTier: number? }
-- RarityTier scales the monster up (Rarity.Scale) and adds the rarity aura.
function MonsterVisuals.Build(speciesId: string, genes: { [string]: any }?, mutationIds: { string }?, opts: { [string]: any }?)
	opts = opts or {}
	genes = genes or {}
	local species = Species.ById[speciesId]
	assert(species, "unknown species " .. tostring(speciesId))
	local model = Instance.new("Model")
	model.Name = speciesId
	local palette = genes.BaseColorGene or species.Palettes[1]
	local color = MonsterVisuals.Palettes[palette] or Color3.fromRGB(150, 150, 150)
	local template = MonsterVisuals.GetMeshTemplate(speciesId)
	local anchors
	if template and MonsterVisuals.MeshTones[speciesId] and RigAnchors[speciesId] then
		buildMeshRig(model, template, MonsterVisuals.MeshTones[speciesId], color)
		anchors = RigAnchors[speciesId]()
	elseif template then
		anchors = buildMeshFromRig(model, template, speciesId, color)
	else
		anchors = Rigs[speciesId](model, color)
	end
	-- Safe defaults so a builder never fails on a rig without that region.
	local top = C(anchors.Body.Center + V(0, anchors.Body.Radius * 0.9, 0))
	anchors.Back = anchors.Back or top
	anchors.Head = anchors.Head or top

	-- Face (eye colour/material can come from an Eye mutation)
	local eyeColor, eyeMat = nil, nil
	local eyeMut = genes.EyeGene and Mutations.ById[genes.EyeGene]
	if eyeMut and eyeMut.Visual then
		eyeColor, eyeMat = eyeMut.Visual.Color, mat(eyeMut.Visual.Material)
	end
	drawFace(model, anchors, eyeColor, eyeMat)
	detailPass(model, anchors, color, speciesId)

	local seed = opts.Seed or 1
	for _, id in mutationIds or {} do
		local m = Mutations.ById[id]
		local v = m and m.Visual
		if v then
			if Builders[id] then
				Builders[id](model, anchors, v)
			elseif v.Kind and KindBuilders[v.Kind] then
				KindBuilders[v.Kind](model, anchors, v)
			elseif m.Category == "Pattern" then
				applyPattern(model, anchors, v, seed)
			elseif m.Category == "Aura" then
				applyAura(model, anchors, v)
			else
				local at = anchors[v.Region or ""] or C(anchors.Body.Center)
				if typeof(at) ~= "CFrame" then
					at = C(anchors.Body.Center)
				end
				part(model, "Accent", BALL, V(0.5, 0.5, 0.5), at, v.Color or Color3.new(1, 1, 1), Enum.Material.Neon)
			end
		end
	end

	local tier = if opts.Silhouette then 1 else (opts.RarityTier or 1)
	if tier >= 2 then
		local bbox, bsize = model:GetBoundingBox()
		rarityAura(model, anchors, tier, bbox.Position.Y - bsize.Y / 2)
	end

	if opts.Silhouette then
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then
				d.Color = Color3.fromRGB(20, 20, 28)
				d.Material = Enum.Material.SmoothPlastic
				if d:IsA("MeshPart") then
					d.TextureID = "" -- baked textures would show through the silhouette
				end
			elseif d:IsA("SurfaceAppearance") then
				d:Destroy()
			elseif d:IsA("ParticleEmitter") then
				d:Destroy()
			end
		end
	end

	-- Store orbit centers relative to the pivot so Animate works wherever the model is moved.
	local pivot0 = model:GetPivot()
	for _, p in model:GetChildren() do
		if p.Name == "Orbiter" then
			p:SetAttribute("OrbitCenter", pivot0:PointToObjectSpace(p:GetAttribute("OrbitCenter")))
		end
	end

	-- Final size = size gene x rarity scale (bigger the rarer it is).
	local size = if type(genes.SizeGene) == "number" and genes.SizeGene > 0 then genes.SizeGene else 1
	size *= (Rarity.Get(tier) or Rarity.Tiers[1]).Scale
	if size ~= 1 then
		model:ScaleTo(math.clamp(size, 0.4, 3))
	end
	MonsterVisuals.PrepareAnimation(model)
	return model
end

-- ===== Procedural animation =====
-- Parts are given roles from their names; their rest pose (relative to the body
-- pivot) is recorded once, then AnimatePose re-poses them each frame. No
-- per-model loops: callers drive it from one shared RenderStepped.
local ROLE_BY_NAME = {
	Foot = "Leg", Leg = "Leg", Paw = "Leg", FrontLeg = "Leg", BackLeg = "Leg", Toe = "Leg", Claw = "Leg",
	Tail = "Tail", TailBase = "Tail", TailMid = "Tail", TailFlipper = "Tail", IceTip = "Tail", Coil = "Tail",
	Ear = "Ear", EarInner = "Ear",
	Leaf = "Leaf", Sprout = "Leaf", FrostLeaf = "Leaf",
	Flipper = "Flipper", Pincer = "Flipper",
	Wing = "Wing",
	Tentacle = "Tentacle",
	Fin = "Leaf",
	Antenna = "Ear", AntennaTip = "Ear", Crest = "Ear",
	Eye = "Blink", Iris = "Blink", Glint = "Blink", Pupil = "Blink",
	Puff = "Puff",
	Arm = "Arm",
	Flame = "Flame",
}
local animData = setmetatable({}, { __mode = "k" }) :: { [Model]: any }

function MonsterVisuals.PrepareAnimation(model: Model)
	local pivot = model:GetPivot()
	local entries = {}
	local tailRootZ = math.huge
	for _, p in model:GetChildren() do
		local role = p:IsA("BasePart") and p ~= model.PrimaryPart and ROLE_BY_NAME[p.Name]
		if role then
			local rest = pivot:ToObjectSpace(p.CFrame)
			local e = { Part = p, Rest = rest, Size = p.Size, Role = role, Side = if rest.X >= 0 then 1 else -1 }
			if role == "Leg" then
				-- Diagonal gait: front-left with back-right, and vice versa.
				e.Phase = if (rest.X >= 0) == (rest.Z < 0) then 0 else math.pi
				e.Pivot = Vector3.new(rest.X, rest.Y + 0.6, rest.Z)
			elseif role == "Tail" then
				tailRootZ = math.min(tailRootZ, rest.Z)
			elseif role == "Ear" or role == "Leaf" then
				e.Pivot = (rest * CFrame.new(0, -p.Size.Y * 0.4, 0)).Position
			elseif role == "Flipper" then
				e.Pivot = Vector3.new(rest.X - e.Side * p.Size.X * 0.4, rest.Y, rest.Z)
			elseif role == "Wing" then
				e.Pivot = Vector3.new(rest.X - e.Side * 0.7, rest.Y, rest.Z)
			elseif role == "Tentacle" then
				e.Pivot = Vector3.new(rest.X, rest.Y + 0.6, rest.Z)
			elseif role == "Arm" then
				-- Shoulder: top of the arm. Swings opposite to the leg on its side.
				e.Pivot = Vector3.new(rest.X, rest.Y + p.Size.Y * 0.4, rest.Z)
				e.Phase = if rest.X >= 0 then math.pi else 0
			elseif role == "Flame" then
				e.Pivot = (rest * CFrame.new(0, -p.Size.Y * 0.5, 0)).Position
				e.Phase = rest.X * 3.1 + rest.Z * 1.7
			end
			table.insert(entries, e)
		end
	end
	for _, e in entries do
		if e.Role == "Tail" then
			e.Pivot = Vector3.new(0, e.Rest.Y, tailRootZ - 0.3)
		end
	end
	animData[model] = { Entries = entries, Seed = (#entries * 1.37) % 3 }
end

local function about(pivotPoint: Vector3, rot: CFrame, rest: CFrame): CFrame
	return CFrame.new(pivotPoint) * rot * CFrame.new(-pivotPoint) * rest
end

-- Re-poses animated parts. `move` is 0 (idle) .. 1 (moving at full speed).
function MonsterVisuals.AnimatePose(model: Model, t: number, move: number)
	local data = animData[model]
	if not data then
		return
	end
	local pivot = model:GetPivot()
	local s = data.Seed
	local wag = math.sin(t * (6 + move * 6) + s) * (0.25 + move * 0.15)
	-- Ears twitch in short bursts every few seconds.
	local twitchPhase = (t + s * 2) % 3.2
	local twitch = if twitchPhase < 0.3 then math.sin(twitchPhase / 0.3 * math.pi * 2) * 0.35 else 0
	local sway = math.sin(t * 1.8 + s) * 0.18
	local flap = math.sin(t * (3 + move * 6) + s) * (0.15 + move * 0.35)
	-- Blink: eyes squash closed for 0.12 s roughly every 3.5 s.
	local blinkPhase = (t + s * 3) % 3.5
	local blink = if blinkPhase < 0.12 then 0.12 else 1
	for _, e in data.Entries do
		local p = e.Part
		local role = e.Role
		if role == "Leg" then
			local a = math.sin(t * 11 + e.Phase) * 0.6 * move
			local lift = math.max(0, math.sin(t * 11 + e.Phase)) * 0.15 * move
			p.CFrame = pivot * CFrame.new(0, lift, 0) * about(e.Pivot, CFrame.Angles(a, 0, 0), e.Rest)
		elseif role == "Tail" then
			p.CFrame = pivot * about(e.Pivot, CFrame.Angles(0, wag, 0), e.Rest)
		elseif role == "Ear" then
			p.CFrame = pivot * about(e.Pivot, CFrame.Angles(0, 0, twitch * e.Side), e.Rest)
		elseif role == "Leaf" then
			p.CFrame = pivot * about(e.Pivot, CFrame.Angles(0, 0, sway * e.Side), e.Rest)
		elseif role == "Flipper" then
			p.CFrame = pivot * about(e.Pivot, CFrame.Angles(0, 0, flap * e.Side), e.Rest)
		elseif role == "Wing" then
			p.CFrame = pivot * about(e.Pivot, CFrame.Angles(0, 0, math.sin(t * 9 + s) * 0.5 * e.Side), e.Rest)
		elseif role == "Tentacle" then
			local sw = math.sin(t * 2.2 + e.Rest.X * 3 + e.Rest.Z * 2) * 0.3
			p.CFrame = pivot * about(e.Pivot, CFrame.Angles(sw, 0, sw * 0.5), e.Rest)
		elseif role == "Arm" then
			local a = math.sin(t * 11 + e.Phase) * 0.7 * move + math.sin(t * 1.6 + s) * 0.06
			p.CFrame = pivot * about(e.Pivot, CFrame.Angles(a, 0, 0), e.Rest)
		elseif role == "Flame" then
			-- Flicker: stretch up and down from the base, with a little lick sideways.
			local k = 1 + math.sin(t * 9 + e.Phase) * 0.12 + math.sin(t * 15.3 + e.Phase * 2) * 0.06
			p.Size = Vector3.new(e.Size.X, e.Size.Y * k, e.Size.Z)
			local lick = CFrame.Angles(0, 0, math.sin(t * 5 + e.Phase) * 0.12)
			p.CFrame = pivot * about(e.Pivot, lick, e.Rest * CFrame.new(0, e.Size.Y * (k - 1) / 2, 0))
		elseif role == "Puff" then
			p.CFrame = pivot * CFrame.new(0, math.sin(t * 2.5 + e.Rest.X * 3) * 0.08, 0) * e.Rest
		elseif role == "Blink" then
			p.Size = Vector3.new(e.Size.X, e.Size.Y * blink, e.Size.Z)
			p.CFrame = pivot * e.Rest
		end
	end
end

-- Advances orbiters on a built model (call from a single shared loop).
function MonsterVisuals.Animate(model: Model, t: number)
	local pivot = model:GetPivot()
	local scale = model:GetScale()
	for _, p in model:GetChildren() do
		if p.Name == "Orbiter" then
			local c = p:GetAttribute("OrbitCenter") :: Vector3
			local r = p:GetAttribute("OrbitRadius") :: number
			local ph = p:GetAttribute("OrbitPhase") :: number
			local sp = p:GetAttribute("OrbitSpeed") :: number
			local bob = p:GetAttribute("OrbitBob") :: number
			local a = ph + t * sp
			local local_ = c + V(math.cos(a) * r, math.sin(t * 2 + ph) * bob, math.sin(a) * r)
			p.CFrame = pivot * C(local_ * scale)
		end
	end
end

return MonsterVisuals
