-- Stage 9: Blender mesh rigs. Fake templates check the build path; the real
-- ReplicatedStorage.MonsterMeshes templates (when present) are checked for
-- tones, sane placement and building with every mutation.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.MonsterFactory.Shared
local MonsterVisuals = require(Shared.MonsterVisuals)
local Mutations = require(Shared.Mutations)
local Species = require(Shared.Species)

local function fakeTemplate(names: { string })
	local folder = Instance.new("Folder")
	local model = Instance.new("Model")
	model.Name = "Mossling"
	for i, name in names do
		local p = Instance.new("MeshPart")
		p.Name = name
		p.Size = Vector3.new(1, 1, 1)
		p.CFrame = CFrame.new(i, 1, 0)
		p.CanCollide = true
		if name == "Body" then
			Instance.new("SurfaceAppearance").Parent = p -- a "textured" body
		end
		p.Parent = model
	end
	model.Parent = folder
	return folder
end

local function withFolder(folder: Instance?, fn)
	local old = MonsterVisuals.MeshFolder
	MonsterVisuals.MeshFolder = folder
	local ok, err = pcall(fn)
	MonsterVisuals.MeshFolder = old
	if not ok then
		error(err, 0)
	end
end

return function(t)
	t.it("species without a template keep the part rig", function()
		withFolder(Instance.new("Folder"), function()
			local m = MonsterVisuals.Build("Mossling")
			t.ok(m.PrimaryPart and m.PrimaryPart:IsA("Part"), "part body")
			t.ok(m:FindFirstChild("BackShade"), "part rig shading")
			m:Destroy()
		end)
	end)

	t.it("a template builds tinted, anchored mesh pieces with the face and anchors", function()
		withFolder(fakeTemplate({ "Body", "Foot", "Foot", "Leaf", "Claw" }), function()
			local genes = { BaseColorGene = "Moss" }
			local m = MonsterVisuals.Build("Mossling", genes)
			local body = m.PrimaryPart
			t.ok(body and body:IsA("MeshPart") and body.Name == "Body", "mesh body is primary")
			t.ok(not m:FindFirstChild("BackShade"), "no part-rig shading on mesh body")
			local moss = MonsterVisuals.Palettes.Moss
			t.ok(body.Color:ToHex() == moss:ToHex(), "body uses palette colour")
			local sa = body:FindFirstChildOfClass("SurfaceAppearance")
			t.ok(sa and sa.Color:ToHex() == moss:ToHex(), "textured body is tinted through its SurfaceAppearance")
			MonsterVisuals.Build("Mossling", genes, { "MossyCoat" }):Destroy() -- recolours via setTint
			local tones = MonsterVisuals.MeshTones.Mossling
			for _, p in m:GetChildren() do
				if p:IsA("MeshPart") then
					t.ok(p.Anchored and not p.CanCollide and not p.CanTouch and not p.CastShadow, "cheap flags " .. p.Name)
					if typeof(tones[p.Name]) == "Color3" then
						t.ok(p.Color:ToHex() == tones[p.Name]:ToHex(), "fixed tone " .. p.Name)
					end
				end
			end
			local feet = 0
			for _, p in m:GetChildren() do
				feet += if p.Name == "Foot" then 1 else 0
			end
			t.eq(feet, 2, "every template piece cloned")
			t.ok(m:FindFirstChild("Eye"), "face drawn from anchors")
			MonsterVisuals.AnimatePose(m, 1.3, 1)
			m:Destroy()
		end)
	end)

	t.it("an upgraded template takes colours, glow and anchors from the part rig", function()
		local partBody
		withFolder(Instance.new("Folder"), function()
			local m = MonsterVisuals.Build("Basaltback")
			partBody = m.PrimaryPart.Color
			m:Destroy()
		end)
		local folder = fakeTemplate({ "Body", "LavaCrack", "Leg" })
		folder.Mossling.Name = "Basaltback" -- no MeshTones/RigAnchors: "from rig" mode
		withFolder(folder, function()
			t.ok(MonsterVisuals.GetMeshTemplate("Basaltback") ~= nil, "template used")
			local m = MonsterVisuals.Build("Basaltback")
			local body = m.PrimaryPart
			t.ok(body:IsA("MeshPart"), "mesh body")
			local sa = body:FindFirstChildOfClass("SurfaceAppearance")
			t.ok(sa and sa.Color:ToHex() == partBody:ToHex(), "body tinted like the part rig's body")
			local crack = m:FindFirstChild("LavaCrack") :: BasePart
			t.ok(crack.Material == Enum.Material.Neon and not crack:FindFirstChildOfClass("SurfaceAppearance"), "glowing part stays neon")
			t.ok(m:FindFirstChild("Eye"), "face drawn from the part rig's anchors")
			MonsterVisuals.AnimatePose(m, 0.5, 1)
			m:Destroy()
		end)
	end)

	t.it("real templates are complete and build with every mutation", function()
		local folder = ReplicatedStorage:FindFirstChild("MonsterMeshes")
		if not folder then
			t.log("no ReplicatedStorage.MonsterMeshes; skipped")
			return
		end
		withFolder(nil, function()
			for _, template in folder:GetChildren() do
				local id = template.Name
				t.ok(Species.ById[id], "template is a species: " .. id)
				t.ok(MonsterVisuals.GetMeshTemplate(id), "template usable: " .. id)
				-- Every piece is styled: by a tone (hand-made rigs) or by a same-named
				-- part in the part rig (upgraded rigs).
				local styled = MonsterVisuals.MeshTones[id]
				if not styled then
					styled = {}
					local old = MonsterVisuals.MeshFolder
					MonsterVisuals.MeshFolder = Instance.new("Folder")
					local partRig = MonsterVisuals.Build(id)
					MonsterVisuals.MeshFolder = old
					for _, p in partRig:GetChildren() do
						styled[p.Name] = true
					end
					partRig:Destroy()
				end
				for _, p in template:GetDescendants() do
					if p:IsA("MeshPart") then
						t.ok(p.Parent == template, id .. ": piece is a direct child " .. p.Name)
						t.ok(styled[p.Name] ~= nil, id .. ": style for " .. p.Name)
					end
				end
				-- Normalised: body bottom near the ground, centred on X.
				local body = template:FindFirstChild("Body") :: BasePart
				t.near(body.Position.X, 0, 0.1, id .. ": body centred")
				t.ok(body.Position.Y - body.Size.Y / 2 > -0.2, id .. ": body above ground")

				-- Pivot must face -Z with no import turn, or pets/reveals face backwards.
				local built = MonsterVisuals.Build(id)
				t.ok(built:GetPivot().LookVector:Dot(Vector3.new(0, 0, -1)) > 0.999, id .. ": pivot faces -Z")
				t.ok(built:GetPivot().UpVector:Dot(Vector3.yAxis) > 0.999, id .. ": pivot is upright")
				built:Destroy()

				local errors = 0
				for _, mut in Mutations.List do
					local ok, err = pcall(function()
						local m = MonsterVisuals.Build(id, nil, { mut.Id }, { RarityTier = 6 })
						MonsterVisuals.AnimatePose(m, 0.7, 1)
						MonsterVisuals.Animate(m, 0.7)
						m:Destroy()
					end)
					if not ok then
						errors += 1
						t.log(id .. " + " .. mut.Id .. ": " .. tostring(err))
					end
				end
				t.eq(errors, 0, id .. ": builds with every mutation")
			end
		end)
	end)
end
