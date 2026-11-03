-- Attack animations for the battle screen, drawn as 2D effects on a full-screen
-- layer above the monster viewports (ViewportFrames can't show particles).
-- Every element has its own look, Pokemon style:
--   Ember   fireballs that arc over and burst into flame
--   Tide    a stream of water drops, then a splash
--   Frost   spinning ice shards, the target turns icy blue
--   Storm   a lightning bolt from the sky with a white flash
--   Verdant a swirl of spinning leaves
--   Earthen rocks dropping onto the target, the screen shakes
--   Toxic   bubbles that pop into a purple cloud
--   Normal  a white impact star
-- Strong moves (Power >= 70) use more and bigger pieces, plus flash and shake.
-- Motion is stepped on Heartbeat, so it plays even when frames are slow.

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local FX = {}

local BLACK = Color3.fromRGB(14, 14, 28)

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

-- Runs fn(t) with t going 0 -> 1 over `duration` seconds; yields until done.
local function animate(duration: number, fn: (number) -> ())
	local start = os.clock()
	while true do
		local t = math.min((os.clock() - start) / duration, 1)
		fn(t)
		if t >= 1 then
			break
		end
		RunService.Heartbeat:Wait()
	end
end
FX.Animate = animate

local function easeOut(t: number): number
	return 1 - (1 - t) * (1 - t)
end

-- A piece of effect: shape "circle" | "diamond" | "leaf" | "shard" | "rock" | "bar".
local function piece(layer: GuiObject, shape: string, color: Color3, size: number, pos: Vector2): Frame
	local f = Instance.new("Frame")
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.BackgroundColor3 = color
	f.BorderSizePixel = 0
	f.Position = UDim2.fromOffset(pos.X, pos.Y)
	f.ZIndex = 70
	if shape == "circle" then
		f.Size = UDim2.fromOffset(size, size)
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(1, 0)
		c.Parent = f
	elseif shape == "diamond" then
		f.Size = UDim2.fromOffset(size * 0.7, size * 0.7)
		f.Rotation = 45
	elseif shape == "leaf" then
		f.Size = UDim2.fromOffset(size, size * 0.5)
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(1, 0)
		c.Parent = f
	elseif shape == "shard" then
		f.Size = UDim2.fromOffset(size * 1.4, size * 0.35)
	elseif shape == "rock" then
		f.Size = UDim2.fromOffset(size, size * 0.85)
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0.3, 0)
		c.Parent = f
	else -- bar
		f.Size = UDim2.fromOffset(size, 6)
	end
	local s = Instance.new("UIStroke")
	s.Thickness = 2.5
	s.Color = BLACK
	s.Parent = f
	-- Shine: lighter top, so every piece looks glossy like the UI.
	local g = Instance.new("UIGradient")
	g.Color = ColorSequence.new(color:Lerp(Color3.new(1, 1, 1), 0.55), color)
	g.Rotation = 90
	g.Parent = f
	f.Parent = layer
	return f
end

local function fadeOut(f: GuiObject, t: number)
	TweenService:Create(f, TweenInfo.new(t), { BackgroundTransparency = 1 }):Play()
	local s = f:FindFirstChildOfClass("UIStroke")
	if s then
		TweenService:Create(s, TweenInfo.new(t), { Transparency = 1 }):Play()
	end
	task.delay(t, function()
		f:Destroy()
	end)
end

-- Expanding ring + sparks flying out: every hit ends with one.
function FX.Burst(layer: GuiObject, at: Vector2, color: Color3, scale: number?)
	local k = scale or 1
	local ring = Instance.new("Frame")
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.BackgroundTransparency = 1
	ring.Position = UDim2.fromOffset(at.X, at.Y)
	ring.Size = UDim2.fromOffset(20, 20)
	ring.ZIndex = 71
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(1, 0)
	c.Parent = ring
	local s = Instance.new("UIStroke")
	s.Thickness = 8
	s.Color = color
	s.Parent = ring
	ring.Parent = layer
	TweenService:Create(ring, TweenInfo.new(0.35, Enum.EasingStyle.Quad), { Size = UDim2.fromOffset(170 * k, 170 * k) }):Play()
	TweenService:Create(s, TweenInfo.new(0.35), { Transparency = 1, Thickness = 1 }):Play()
	task.delay(0.4, function()
		ring:Destroy()
	end)
	for i = 1, math.floor(8 * k) do
		local a = i / math.floor(8 * k) * math.pi * 2 + math.random() * 0.4
		local sp = piece(layer, "diamond", color, 14 * k, at)
		local dist = (60 + math.random() * 50) * k
		TweenService:Create(sp, TweenInfo.new(0.35, Enum.EasingStyle.Quad), {
			Position = UDim2.fromOffset(at.X + math.cos(a) * dist, at.Y + math.sin(a) * dist),
			Rotation = sp.Rotation + 180,
		}):Play()
		task.delay(0.15, function()
			fadeOut(sp, 0.2)
		end)
	end
end

-- Full-screen colour flash.
function FX.Flash(layer: GuiObject, color: Color3, strength: number?)
	local f = Instance.new("Frame")
	f.BackgroundColor3 = color
	f.BackgroundTransparency = 1 - (strength or 0.6)
	f.Size = UDim2.fromScale(1, 1)
	f.ZIndex = 75
	f.Parent = layer
	TweenService:Create(f, TweenInfo.new(0.3), { BackgroundTransparency = 1 }):Play()
	task.delay(0.32, function()
		f:Destroy()
	end)
end

-- Shakes a GuiObject (the whole arena for big hits) around its position.
function FX.Shake(target: GuiObject, power: number, duration: number)
	local base = target.Position
	animate(duration, function(t)
		local p = math.floor(power * (1 - t))
		target.Position = base + UDim2.fromOffset(math.random(-p, p), math.random(-p, p))
	end)
	target.Position = base
end

-- ===== Element attacks =====
-- Each yields until the hit lands. from/to are screen points (layer space).
local Attacks = {}

function Attacks.Normal(layer, from: Vector2, to: Vector2, strong: boolean)
	task.wait(0.12)
	local star = piece(layer, "diamond", Color3.fromRGB(255, 255, 255), if strong then 90 else 60, to)
	TweenService:Create(star, TweenInfo.new(0.2, Enum.EasingStyle.Back), { Rotation = 135 }):Play()
	task.delay(0.15, function()
		fadeOut(star, 0.2)
	end)
end

function Attacks.Ember(layer, from: Vector2, to: Vector2, strong: boolean)
	local n = if strong then 4 else 2
	local col = Color3.fromRGB(255, 120, 30)
	for i = 1, n do
		task.spawn(function()
			local ball = piece(layer, "circle", col, if strong then 46 else 34, from)
			local core = piece(ball, "circle", Color3.fromRGB(255, 230, 90), if strong then 22 else 16, Vector2.new(0, 0))
			core.Position = UDim2.fromScale(0.5, 0.5)
			local lift = 90 + i * 20
			animate(0.38, function(t)
				local x = lerp(from.X, to.X, t)
				local y = lerp(from.Y, to.Y, t) - math.sin(t * math.pi) * lift
				ball.Position = UDim2.fromOffset(x, y)
				ball.Rotation = t * 360
				-- Flickering flame trail.
				if math.random() < 0.6 then
					local ember = piece(layer, "circle", Color3.fromRGB(255, 180, 40), 14, Vector2.new(x, y))
					TweenService:Create(ember, TweenInfo.new(0.3), { Position = ember.Position + UDim2.fromOffset(math.random(-10, 10), -20), Size = UDim2.fromOffset(4, 4) }):Play()
					fadeOut(ember, 0.3)
				end
			end)
			ball:Destroy()
			FX.Burst(layer, to, Color3.fromRGB(255, 140, 30), if strong then 1.2 else 0.8)
		end)
		task.wait(0.12)
	end
	task.wait(0.3)
end

function Attacks.Tide(layer, from: Vector2, to: Vector2, strong: boolean)
	local n = if strong then 14 else 8
	local col = Color3.fromRGB(70, 160, 255)
	for i = 1, n do
		task.spawn(function()
			local drop = piece(layer, "circle", col, math.random(16, 26) * (if strong then 1.3 else 1), from)
			local wobble = math.random() * 6
			animate(0.4, function(t)
				local x = lerp(from.X, to.X, t)
				local y = lerp(from.Y, to.Y, t) + math.sin(t * 9 + wobble) * 18
				drop.Position = UDim2.fromOffset(x, y)
			end)
			fadeOut(drop, 0.1)
		end)
		task.wait(0.04)
	end
	task.wait(0.35)
	-- Splash: drops jump up and fall around the target.
	for i = 1, (if strong then 10 else 6) do
		local d = piece(layer, "circle", col, 14, to)
		local dx = math.random(-70, 70)
		TweenService:Create(d, TweenInfo.new(0.35, Enum.EasingStyle.Quad), { Position = UDim2.fromOffset(to.X + dx, to.Y - math.random(40, 90)) }):Play()
		task.delay(0.2, function()
			fadeOut(d, 0.2)
		end)
	end
	FX.Burst(layer, to, Color3.fromRGB(120, 200, 255), if strong then 1.2 else 0.8)
end

function Attacks.Frost(layer, from: Vector2, to: Vector2, strong: boolean)
	local n = if strong then 9 else 5
	local col = Color3.fromRGB(170, 235, 255)
	for i = 1, n do
		task.spawn(function()
			local spread = Vector2.new(math.random(-30, 30), math.random(-30, 30))
			local shard = piece(layer, "shard", col, if strong then 34 else 26, from + spread)
			local angle = math.deg(math.atan2(to.Y - from.Y, to.X - from.X))
			animate(0.28, function(t)
				local p = (from + spread):Lerp(to + spread * 0.3, easeOut(t))
				shard.Position = UDim2.fromOffset(p.X, p.Y)
				shard.Rotation = angle + t * 30
			end)
			fadeOut(shard, 0.15)
		end)
		task.wait(0.05)
	end
	task.wait(0.3)
	FX.Burst(layer, to, col, if strong then 1.3 else 0.9)
	if strong then
		FX.Flash(layer, Color3.fromRGB(200, 240, 255), 0.5)
	end
end

function Attacks.Storm(layer, from: Vector2, to: Vector2, strong: boolean)
	task.wait(0.1)
	local col = Color3.fromRGB(255, 230, 60)
	-- A zigzag bolt from the top of the screen down onto the target.
	local bolts = if strong then 2 else 1
	for b = 1, bolts do
		local x = to.X + (b - 1) * 30
		local y = -20
		local points = { Vector2.new(x, y) }
		local steps = 7
		for k = 1, steps do
			local py = lerp(-20, to.Y, k / steps)
			local px = if k == steps then to.X else to.X + math.random(-40, 40)
			table.insert(points, Vector2.new(px, py))
		end
		for k = 1, #points - 1 do
			local a, c = points[k], points[k + 1]
			local mid = (a + c) / 2
			local seg = piece(layer, "bar", col, (c - a).Magnitude + 4, mid)
			seg.Size = UDim2.fromOffset((c - a).Magnitude + 4, if strong then 10 else 7)
			seg.Rotation = math.deg(math.atan2(c.Y - a.Y, c.X - a.X))
			task.delay(0.25, function()
				fadeOut(seg, 0.15)
			end)
		end
	end
	FX.Flash(layer, Color3.fromRGB(255, 255, 220), if strong then 0.8 else 0.5)
	FX.Burst(layer, to, col, if strong then 1.3 else 0.9)
	task.wait(0.2)
end

function Attacks.Verdant(layer, from: Vector2, to: Vector2, strong: boolean)
	local n = if strong then 12 else 6
	local col = Color3.fromRGB(90, 210, 70)
	for i = 1, n do
		task.spawn(function()
			local leaf = piece(layer, "leaf", col, if strong then 34 else 26, from)
			local phase = i / n * math.pi * 2
			local radius = if strong then 70 else 45
			animate(0.55, function(t)
				local center = from:Lerp(to, easeOut(t))
				local r = radius * (1 - t)
				local a = phase + t * 10
				leaf.Position = UDim2.fromOffset(center.X + math.cos(a) * r, center.Y + math.sin(a) * r)
				leaf.Rotation = t * 720 + i * 30
			end)
			fadeOut(leaf, 0.12)
		end)
		task.wait(0.03)
	end
	task.wait(0.5)
	FX.Burst(layer, to, col, if strong then 1.2 else 0.8)
end

function Attacks.Earthen(layer, from: Vector2, to: Vector2, strong: boolean, arena: GuiObject?)
	local n = if strong then 6 else 3
	local col = Color3.fromRGB(170, 120, 70)
	for i = 1, n do
		task.spawn(function()
			local landing = to + Vector2.new(math.random(-45, 45), math.random(-15, 15))
			local rock = piece(layer, "rock", col, math.random(30, 46) * (if strong then 1.2 else 1), Vector2.new(landing.X, -40))
			animate(0.32, function(t)
				rock.Position = UDim2.fromOffset(landing.X, lerp(-40, landing.Y, t * t))
				rock.Rotation = t * 140
			end)
			FX.Burst(layer, landing, Color3.fromRGB(200, 160, 100), 0.5)
			fadeOut(rock, 0.25)
		end)
		task.wait(0.09)
	end
	task.wait(0.35)
	if arena then
		task.spawn(FX.Shake, arena, if strong then 14 else 7, 0.35)
	end
end

function Attacks.Toxic(layer, from: Vector2, to: Vector2, strong: boolean)
	local n = if strong then 8 else 5
	local col = Color3.fromRGB(170, 80, 230)
	for i = 1, n do
		task.spawn(function()
			local bubble = piece(layer, "circle", col, math.random(18, 30), from)
			bubble.BackgroundTransparency = 0.25
			local lift = math.random(40, 110)
			animate(0.45, function(t)
				local p = from:Lerp(to, t)
				bubble.Position = UDim2.fromOffset(p.X + math.sin(t * 8 + i) * 12, p.Y - math.sin(t * math.pi) * lift)
			end)
			fadeOut(bubble, 0.1)
		end)
		task.wait(0.06)
	end
	task.wait(0.4)
	-- The cloud: soft purple puffs that grow and fade over the target.
	for i = 1, (if strong then 7 else 4) do
		local puff = piece(layer, "circle", col, 30, to + Vector2.new(math.random(-40, 40), math.random(-30, 20)))
		puff.BackgroundTransparency = 0.35
		TweenService:Create(puff, TweenInfo.new(0.6), { Size = UDim2.fromOffset(110, 110), BackgroundTransparency = 1 }):Play()
		local s = puff:FindFirstChildOfClass("UIStroke")
		if s then
			s.Transparency = 0.6
			TweenService:Create(s, TweenInfo.new(0.6), { Transparency = 1 }):Play()
		end
		task.delay(0.62, function()
			puff:Destroy()
		end)
	end
	task.wait(0.15)
end

-- Plays the attack for an element; yields until it lands.
function FX.Attack(layer: GuiObject, element: string, from: Vector2, to: Vector2, strong: boolean, arena: GuiObject?)
	local fn = Attacks[element] or Attacks.Normal
	fn(layer, from, to, strong, arena)
	if strong and element ~= "Storm" and element ~= "Earthen" then
		task.spawn(FX.Shake, arena or layer, 8, 0.25)
	end
end

-- Confetti for a win.
function FX.Confetti(layer: GuiObject)
	local size = layer.AbsoluteSize
	local colors = { Color3.fromRGB(255, 80, 80), Color3.fromRGB(255, 210, 40), Color3.fromRGB(90, 220, 60), Color3.fromRGB(60, 160, 255), Color3.fromRGB(170, 85, 255) }
	for i = 1, 60 do
		local x = math.random(0, math.floor(size.X))
		local c = piece(layer, "bar", colors[i % #colors + 1], 16, Vector2.new(x, -20))
		c.Size = UDim2.fromOffset(12, 18)
		c.ZIndex = 80
		local fall = 1.4 + math.random() * 1.2
		TweenService:Create(c, TweenInfo.new(fall, Enum.EasingStyle.Linear), {
			Position = UDim2.fromOffset(x + math.random(-80, 80), size.Y + 30),
			Rotation = math.random(-540, 540),
		}):Play()
		task.delay(fall, function()
			c:Destroy()
		end)
		if i % 6 == 0 then
			task.wait(0.03)
		end
	end
end

return FX
