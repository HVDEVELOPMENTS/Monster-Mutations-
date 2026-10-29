-- World effects for monsters that exist in 3D (followers, displays): an element aura
-- from the species, layers that grow with rarity, and footstep puffs.
-- ViewportFrames don't render particles, so this is world-only.
-- Budget: per monster at most 3 emitters, 1 light, 1 trail; every rate is capped.

local Rarity = require(script.Parent.Rarity)

local MonsterEffects = {}

local TEX = {
	Sparkle = "rbxasset://textures/particles/sparkles_main.dds",
	Smoke = "rbxasset://textures/particles/smoke_main.dds",
	Fire = "rbxasset://textures/particles/fire_main.dds",
}

-- Per element: aura colour/texture/motion and the footstep puff.
MonsterEffects.Elements = {
	Verdant = { Color = Color3.fromRGB(120, 225, 90), Texture = TEX.Sparkle, Speed = 0.6, Rotation = true, Step = Color3.fromRGB(110, 190, 80) },
	Earthen = { Color = Color3.fromRGB(190, 160, 120), Texture = TEX.Smoke, Speed = 0.3, Step = Color3.fromRGB(170, 140, 100) },
	Tide = { Color = Color3.fromRGB(140, 220, 255), Texture = TEX.Sparkle, Speed = 0.9, Rise = true, Step = Color3.fromRGB(150, 210, 255) },
	Frost = { Color = Color3.fromRGB(225, 245, 255), Texture = TEX.Sparkle, Speed = 0.4, Fall = true, Step = Color3.fromRGB(235, 245, 255) },
	Ember = { Color = Color3.fromRGB(255, 140, 50), Texture = TEX.Fire, Speed = 0.8, Rise = true, Step = Color3.fromRGB(90, 80, 80) },
	Storm = { Color = Color3.fromRGB(255, 235, 110), Texture = TEX.Sparkle, Speed = 2.2, Step = Color3.fromRGB(200, 200, 160) },
	Toxic = { Color = Color3.fromRGB(150, 230, 70), Texture = TEX.Smoke, Speed = 0.4, Rise = true, Step = Color3.fromRGB(110, 120, 70) },
}
local DEFAULT_ELEMENT = MonsterEffects.Elements.Earthen

local function emitter(parent: Instance, name: string, props: { [string]: any })
	local e = Instance.new("ParticleEmitter")
	e.Name = name
	e.LightEmission = 0.4
	e.Lifetime = NumberRange.new(1.2, 1.8)
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 0) })
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
	for k, v in props do
		(e :: any)[k] = v
	end
	e.Parent = parent
	return e
end

-- Adds effects to a built monster model. record needs SpeciesId-derived PrimaryElement
-- and RarityTier. Returns a handle: { Step(), Update(t, cameraPos), Destroy() }.
function MonsterEffects.Apply(model: Model, element: string?, tier: number)
	local body = model.PrimaryPart :: BasePart
	local el = MonsterEffects.Elements[element or ""] or DEFAULT_ELEMENT
	local tierDef = Rarity.Get(tier) or Rarity.Tiers[1]
	-- Sized from the body part, not the bounding box (orbiters would inflate it).
	local bbox, size = model:GetBoundingBox()
	local radius = math.max(body.Size.X, body.Size.Z) * 0.55
	local groundY = -(body.Position.Y - (bbox.Position.Y - size.Y / 2))
	local emitters: { ParticleEmitter } = {}

	-- 1. Element aura (every monster; rate grows a little with tier).
	local aura = emitter(body, "ElementAura", {
		Texture = el.Texture,
		Color = ColorSequence.new(el.Color),
		Rate = math.min(1.5 + tier * 0.5, 6),
		Speed = NumberRange.new(el.Speed * 0.5, el.Speed),
		SpreadAngle = Vector2.new(180, 180),
		Shape = Enum.ParticleEmitterShape.Sphere,
		ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
		Acceleration = if el.Rise then Vector3.new(0, 1.2, 0) elseif el.Fall then Vector3.new(0, -0.6, 0) else Vector3.zero,
		RotSpeed = if el.Rotation then NumberRange.new(-90, 90) else NumberRange.new(0),
	})
	table.insert(emitters, aura)

	-- 2. Rarity sparkles (Uncommon+), in the tier colour.
	if tier >= 2 then
		table.insert(emitters, emitter(body, "RaritySparkle", {
			Texture = TEX.Sparkle,
			Color = ColorSequence.new(tierDef.Color),
			LightEmission = 1,
			Rate = math.min(tier * 1.5, 12),
			Speed = NumberRange.new(0.3, 0.8 + tier * 0.15),
			SpreadAngle = Vector2.new(180, 180),
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.15 + tier * 0.03), NumberSequenceKeypoint.new(1, 0) }),
			Shape = Enum.ParticleEmitterShape.Sphere,
			ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface,
		}))
	end

	-- 3. Glow light (Rare+).
	if tier >= 3 then
		local light = Instance.new("PointLight")
		light.Color = tierDef.Color
		light.Range = 5 + tier * 1.5
		light.Brightness = 0.6 + tier * 0.25
		light.Parent = body
	end

	-- 4. Pulsing aura ring + movement trail (Epic+).
	-- Reuse the model's rarity AuraDisc if MonsterVisuals built one; it already moves
	-- with the model, so Update only pulses it.
	local ring: BasePart? = model:FindFirstChild("AuraDisc") :: BasePart?
	local ownRing = false
	if tier >= 4 and not ring then
		ownRing = true
		ring = Instance.new("Part")
		ring.Name = "AuraRing"
		ring.Shape = Enum.PartType.Cylinder
		ring.Size = Vector3.new(0.12, radius * 2.4, radius * 2.4)
		ring.Material = Enum.Material.Neon
		ring.Color = tierDef.Color
		ring.Transparency = 0.55
		ring.Anchored = true
		ring.CanCollide = false
		ring.CanQuery = false
		ring.CanTouch = false
		ring.CastShadow = false
		ring:SetAttribute("GroundOffset", groundY + 0.08)
		ring.Parent = model
	end
	if tier >= 4 then
		local a0 = Instance.new("Attachment")
		a0.Position = Vector3.new(0, 0.35, 0)
		a0.Parent = body
		local a1 = Instance.new("Attachment")
		a1.Position = Vector3.new(0, -0.35, 0)
		a1.Parent = body
		local trail = Instance.new("Trail")
		trail.Attachment0 = a0
		trail.Attachment1 = a1
		trail.Color = ColorSequence.new(tierDef.Color)
		trail.Transparency = NumberSequence.new(0.4, 1)
		trail.Lifetime = 0.35
		trail.LightEmission = 0.8
		trail.Parent = body
	end

	-- 5. Rising light beams (Legendary+).
	if tier >= 5 then
		table.insert(emitters, emitter(body, "AscendBeams", {
			Texture = TEX.Sparkle,
			Color = ColorSequence.new(tierDef.Color, Color3.new(1, 1, 1)),
			LightEmission = 1,
			Rate = math.min(4 + (tier - 5) * 3, 12),
			Lifetime = NumberRange.new(1, 1.4),
			Speed = NumberRange.new(3, 5),
			EmissionDirection = Enum.NormalId.Top,
			SpreadAngle = Vector2.new(8, 8),
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0.1) }),
		}))
	end

	-- Footstep puff (burst only, via Step()).
	local feet = Instance.new("Attachment")
	feet.Name = "Feet"
	feet.Position = Vector3.new(0, groundY + 0.1, 0)
	feet.Parent = body
	local puff = emitter(feet, "StepPuff", {
		Texture = TEX.Smoke,
		Color = ColorSequence.new(el.Step),
		LightEmission = 0.1,
		Rate = 0,
		Lifetime = NumberRange.new(0.4, 0.7),
		Speed = NumberRange.new(1.5, 3),
		SpreadAngle = Vector2.new(70, 10),
		EmissionDirection = Enum.NormalId.Top,
		Acceleration = Vector3.new(0, -4, 0),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0.8) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 1) }),
	})

	local handle = {}
	local culled = false
	function handle.Step()
		if not culled then
			puff:Emit(4 + math.min(tier, 6))
		end
	end
	-- Call every frame: pulses the ring and culls effects far from the camera.
	function handle.Update(t: number, cameraPos: Vector3?)
		if cameraPos then
			local far = (cameraPos - body.Position).Magnitude > 120
			if far ~= culled then
				culled = far
				for _, e in emitters do
					e.Enabled = not far
				end
			end
		end
		if ring then
			ring.Transparency = 0.5 + math.sin(t * 3) * 0.15
			if ownRing then
				local d = radius * 2.4 * (1 + math.sin(t * 3) * 0.08)
				ring.Size = Vector3.new(0.12, d, d)
				ring.CFrame = CFrame.new(body.Position + Vector3.new(0, ring:GetAttribute("GroundOffset") :: number, 0)) * CFrame.Angles(0, 0, math.pi / 2)
			end
		end
	end
	function handle.Destroy()
		model:Destroy()
	end
	return handle
end

return MonsterEffects
