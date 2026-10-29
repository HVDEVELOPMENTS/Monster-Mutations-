-- Simulator-style UI helpers: chunky rounded panels, thick outlines, gradients,
-- bouncy buttons, toasts, floating numbers and auto-animated viewports.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage.MonsterFactory.Shared
local Rarity = require(Shared.Rarity)
local MonsterVisuals = require(Shared.MonsterVisuals)

local UI = {}

UI.Font = Enum.Font.FredokaOne
UI.Colors = {
	Panel = Color3.fromRGB(34, 38, 62),
	PanelDark = Color3.fromRGB(24, 27, 46),
	Card = Color3.fromRGB(48, 54, 86),
	Stroke = Color3.fromRGB(10, 10, 22),
	Text = Color3.fromRGB(255, 255, 255),
	Muted = Color3.fromRGB(170, 178, 210),
	Gold = Color3.fromRGB(255, 205, 60),
	Green = Color3.fromRGB(80, 210, 100),
	Blue = Color3.fromRGB(70, 150, 255),
	Red = Color3.fromRGB(240, 80, 80),
	Orange = Color3.fromRGB(255, 150, 40),
	Purple = Color3.fromRGB(160, 100, 255),
}

-- Only built-in sounds that load without asset permissions. Pitch varies the feel.
UI.Sounds = {
	Click = "rbxasset://sounds/electronicpingshort.wav",
	Pop = "rbxasset://sounds/button.wav",
	Swoosh = "rbxasset://sounds/button.wav",
	Tick = "rbxasset://sounds/electronicpingshort.wav",
	Snap = "rbxasset://sounds/electronicpingshort.wav",
}

function UI.Play(soundName: string, pitch: number?, volume: number?)
	local s = Instance.new("Sound")
	s.SoundId = UI.Sounds[soundName] or soundName
	s.Volume = volume or 0.5
	s.PlaybackSpeed = pitch or 1
	s.Parent = SoundService
	s:Play()
	s.Ended:Once(function()
		s:Destroy()
	end)
	task.delay(5, function()
		if s.Parent then
			s:Destroy()
		end
	end)
end

function UI.new(className: string, props: { [string]: any }?, children: { Instance }?)
	local inst = Instance.new(className)
	local parent = nil
	for k, v in props or {} do
		if k == "Parent" then
			parent = v
		else
			(inst :: any)[k] = v
		end
	end
	for _, c in children or {} do
		c.Parent = inst
	end
	inst.Parent = parent
	return inst
end

function UI.Corner(inst: Instance, radius: number?)
	return UI.new("UICorner", { CornerRadius = UDim.new(0, radius or 12), Parent = inst })
end

function UI.Stroke(inst: Instance, thickness: number?, color: Color3?)
	return UI.new("UIStroke", {
		Thickness = thickness or 3,
		Color = color or UI.Colors.Stroke,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = inst,
	})
end

function UI.Gradient(inst: Instance, top: Color3, bottom: Color3)
	return UI.new("UIGradient", { Color = ColorSequence.new(top, bottom), Rotation = 90, Parent = inst })
end

function UI.Padding(inst: Instance, px: number)
	return UI.new("UIPadding", {
		PaddingTop = UDim.new(0, px),
		PaddingBottom = UDim.new(0, px),
		PaddingLeft = UDim.new(0, px),
		PaddingRight = UDim.new(0, px),
		Parent = inst,
	})
end

-- Text with the chunky outlined look.
function UI.Label(parent: Instance, text: string, props: { [string]: any }?)
	local l = UI.new("TextLabel", {
		BackgroundTransparency = 1,
		Font = UI.Font,
		Text = text,
		TextColor3 = UI.Colors.Text,
		TextScaled = true,
		Size = UDim2.fromScale(1, 1),
		Parent = parent,
	})
	UI.new("UIStroke", { Thickness = 2, Color = UI.Colors.Stroke, Parent = l })
	local sizeLimit = UI.new("UITextSizeConstraint", { MaxTextSize = 40, Parent = l })
	for k, v in props or {} do
		if k == "MaxTextSize" then
			sizeLimit.MaxTextSize = v
		else
			(l :: any)[k] = v
		end
	end
	return l
end

local function darker(c: Color3, f: number)
	return c:Lerp(Color3.new(0, 0, 0), f)
end
UI.Darker = darker

-- Bouncy gradient button. Returns the TextButton. Use UI.SetDisabled to grey it out:
-- GuiButton.Active=false would also stop Activated from firing, so we never use it.
function UI.Button(parent: Instance, text: string, color: Color3, props: { [string]: any }?)
	local b = UI.new("TextButton", {
		AutoButtonColor = false,
		BackgroundColor3 = Color3.new(1, 1, 1),
		Text = "",
		Size = UDim2.fromOffset(160, 50),
		Parent = parent,
	})
	UI.Corner(b, 12)
	UI.Stroke(b, 3)
	local grad = UI.Gradient(b, color:Lerp(Color3.new(1, 1, 1), 0.25), darker(color, 0.2))
	local scale = UI.new("UIScale", { Parent = b })
	local label = UI.Label(b, text, { Name = "Label", Size = UDim2.new(1, -12, 1, -10), Position = UDim2.fromOffset(6, 5) })
	local function tweenScale(s: number, t: number?, style: Enum.EasingStyle?)
		TweenService:Create(scale, TweenInfo.new(t or 0.12, style or Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = s }):Play()
	end
	local function enabled()
		return not b:GetAttribute("Disabled")
	end
	b.MouseEnter:Connect(function()
		if enabled() then
			tweenScale(1.06)
		end
	end)
	b.MouseLeave:Connect(function()
		tweenScale(1)
	end)
	b.MouseButton1Down:Connect(function()
		if enabled() then
			tweenScale(0.92, 0.06, Enum.EasingStyle.Quad)
		end
	end)
	b.MouseButton1Up:Connect(function()
		tweenScale(1.06)
	end)
	b.Activated:Connect(function()
		if enabled() then
			UI.Play("Click", 1.1, 0.35)
		end
	end)
	b:GetAttributeChangedSignal("Disabled"):Connect(function()
		grad.Color = if enabled()
			then ColorSequence.new(color:Lerp(Color3.new(1, 1, 1), 0.25), darker(color, 0.2))
			else ColorSequence.new(Color3.fromRGB(120, 120, 130), Color3.fromRGB(80, 80, 90))
	end)
	for k, v in props or {} do
		(b :: any)[k] = v
	end
	return b, label
end

function UI.SetDisabled(b: TextButton, disabled: boolean)
	b:SetAttribute("Disabled", disabled or nil)
end

function UI.IsDisabled(b: TextButton): boolean
	return b:GetAttribute("Disabled") == true
end

function UI.SetButtonText(b: TextButton, text: string)
	local l = b:FindFirstChild("Label") :: TextLabel?
	if l then
		l.Text = text
	end
end

-- Rarity chip: glyph + name on the tier colour (never colour alone).
function UI.RarityChip(parent: Instance, tier: number, props: { [string]: any }?)
	local def = Rarity.Get(tier) or Rarity.Tiers[1]
	local chip = UI.new("Frame", {
		BackgroundColor3 = def.Color,
		Size = UDim2.fromOffset(120, 26),
		Parent = parent,
	})
	UI.Corner(chip, 8)
	UI.Stroke(chip, 2)
	UI.Gradient(chip, Color3.new(1, 1, 1), Color3.fromRGB(190, 190, 190))
	UI.Label(chip, def.Glyph .. " " .. def.Name, { Size = UDim2.new(1, -8, 1, -4), Position = UDim2.fromOffset(4, 2) })
	for k, v in props or {} do
		(chip :: any)[k] = v
	end
	return chip
end

function UI.Bar(parent: Instance, fillColor: Color3, props: { [string]: any }?)
	local bg = UI.new("Frame", { BackgroundColor3 = UI.Colors.PanelDark, Size = UDim2.new(1, 0, 0, 16), Parent = parent })
	UI.Corner(bg, 8)
	UI.Stroke(bg, 2)
	local fill = UI.new("Frame", { Name = "Fill", BackgroundColor3 = fillColor, Size = UDim2.fromScale(0, 1), Parent = bg })
	UI.Corner(fill, 8)
	UI.Gradient(fill, fillColor:Lerp(Color3.new(1, 1, 1), 0.3), darker(fillColor, 0.15))
	for k, v in props or {} do
		(bg :: any)[k] = v
	end
	local api = {}
	function api.Set(alpha: number, animate: boolean?)
		alpha = math.clamp(alpha, 0, 1)
		if animate then
			TweenService:Create(fill, TweenInfo.new(0.35, Enum.EasingStyle.Quad), { Size = UDim2.fromScale(alpha, 1) }):Play()
		else
			fill.Size = UDim2.fromScale(alpha, 1)
		end
	end
	api.Frame = bg
	return api
end

-- Modal panel with title + close button and a pop-in animation.
function UI.Panel(screen: ScreenGui, title: string, size: UDim2, accent: Color3)
	local frame = UI.new("Frame", {
		Name = title .. "Panel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.52),
		Size = size,
		BackgroundColor3 = UI.Colors.Panel,
		Visible = false,
		Parent = screen,
	})
	UI.Corner(frame, 18)
	UI.Stroke(frame, 4)
	UI.new("UISizeConstraint", { MaxSize = Vector2.new(size.X.Offset > 0 and size.X.Offset or 980, 680), Parent = frame })
	local scale = UI.new("UIScale", { Parent = frame })
	local header = UI.new("Frame", { BackgroundColor3 = accent, Size = UDim2.new(1, 0, 0, 56), Parent = frame })
	UI.Corner(header, 18)
	UI.Gradient(header, accent:Lerp(Color3.new(1, 1, 1), 0.2), darker(accent, 0.25))
	UI.Label(header, title, { Size = UDim2.new(1, -120, 0, 40), Position = UDim2.fromOffset(20, 8), TextXAlignment = Enum.TextXAlignment.Left })
	local close = UI.Button(header, "X", UI.Colors.Red, { Size = UDim2.fromOffset(46, 46), Position = UDim2.new(1, -52, 0, 5) })
	local content = UI.new("Frame", {
		Name = "Content",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(14, 66),
		Size = UDim2.new(1, -28, 1, -80),
		Parent = frame,
	})
	local panel = { Frame = frame, Content = content, IsOpen = false, OnOpen = nil :: (() -> ())? }
	function panel.Open()
		panel.IsOpen = true
		frame.Visible = true
		scale.Scale = 0.7
		TweenService:Create(scale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		UI.Play("Swoosh", 1.2, 0.3)
		if panel.OnOpen then
			panel.OnOpen()
		end
	end
	function panel.Close()
		panel.IsOpen = false
		frame.Visible = false
	end
	close.Activated:Connect(panel.Close)
	return panel
end

-- Toast messages stacked at the top of the screen.
local toastHolder: Frame? = nil
function UI.InitToasts(screen: ScreenGui)
	toastHolder = UI.new("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 90),
		Size = UDim2.fromOffset(420, 300),
		ZIndex = 50,
		Parent = screen,
	})
	UI.new("UIListLayout", { Padding = UDim.new(0, 6), HorizontalAlignment = Enum.HorizontalAlignment.Center, Parent = toastHolder })
end

function UI.Toast(text: string, color: Color3?)
	if not toastHolder then
		return
	end
	local f = UI.new("Frame", { BackgroundColor3 = color or UI.Colors.Blue, Size = UDim2.fromOffset(400, 44), ZIndex = 50, Parent = toastHolder })
	UI.Corner(f, 12)
	UI.Stroke(f, 3)
	UI.Label(f, text, { Size = UDim2.new(1, -16, 1, -10), Position = UDim2.fromOffset(8, 5), ZIndex = 51 })
	local s = UI.new("UIScale", { Scale = 0.5, Parent = f })
	TweenService:Create(s, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	task.delay(2.6, function()
		TweenService:Create(s, TweenInfo.new(0.2), { Scale = 0 }):Play()
		task.wait(0.2)
		f:Destroy()
	end)
end

-- "+25" style number that floats up from a GuiObject.
function UI.FloatText(anchor: GuiObject, text: string, color: Color3)
	local screen = anchor:FindFirstAncestorOfClass("ScreenGui")
	if not screen then
		return
	end
	local pos = anchor.AbsolutePosition + anchor.AbsoluteSize / 2
	local l = UI.Label(screen, text, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(160, 36),
		Position = UDim2.fromOffset(pos.X + math.random(-30, 30), pos.Y + 30),
		TextColor3 = color,
		ZIndex = 60,
	})
	TweenService:Create(l, TweenInfo.new(1.1, Enum.EasingStyle.Quad), {
		Position = l.Position - UDim2.fromOffset(0, 70),
		TextTransparency = 1,
	}):Play()
	task.delay(1.1, function()
		l:Destroy()
	end)
end

-- Viewports: one shared RenderStepped loop spins visible models and animates orbiters.
local viewports: { [ViewportFrame]: { Model: Model, Spin: number, Base: CFrame, Phase: number } } = {}
local clock = 0
RunService.RenderStepped:Connect(function(dt)
	clock += dt
	for vp, info in viewports do
		if not vp.Parent then
			viewports[vp] = nil
		elseif vp.Visible and vp.AbsoluteSize.X > 0 then
			local visible = true
			local a = vp:FindFirstAncestorWhichIsA("GuiObject")
			while a do
				if not a.Visible then
					visible = false
					break
				end
				a = a:FindFirstAncestorWhichIsA("GuiObject")
			end
			if visible then
				-- Gentle idle bob and a side-to-side sway (not a full spin), so the face
				-- stays toward the viewer.
				local bob = CFrame.new(0, math.sin(clock * 2.2 + info.Phase) * 0.1, 0)
				local sway = math.sin(clock * info.Spin * 1.5 + info.Phase) * 0.6 * math.min(info.Spin * 2, 1)
				info.Model:PivotTo(bob * info.Base * CFrame.Angles(0, sway, 0))
				if not info.Static then
					MonsterVisuals.AnimatePose(info.Model, clock + info.Phase, 0)
				end
				MonsterVisuals.Animate(info.Model, clock)
			end
		end
	end
end)

-- Creates a ViewportFrame showing a monster. opts: { Spin, Silhouette, Seed, Zoom, RarityTier }
function UI.MonsterViewport(parent: Instance, speciesId: string, genes: any?, mutations: { string }?, opts: { [string]: any }?)
	opts = opts or {}
	local vp = UI.new("ViewportFrame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		LightColor = Color3.fromRGB(255, 250, 235),
		Ambient = Color3.fromRGB(150, 150, 170),
		LightDirection = Vector3.new(-1, -1, -1),
		Parent = parent,
	})
	local model = MonsterVisuals.Build(speciesId, genes, mutations, { Silhouette = opts.Silhouette, Seed = opts.Seed, RarityTier = opts.RarityTier })
	-- Models face -Z and the camera sits at -Z, so a small yaw gives a 3/4 view.
	local base = CFrame.Angles(0, 0.5, 0)
	model:PivotTo(base)
	model.Parent = vp
	local cam = Instance.new("Camera")
	cam.FieldOfView = 40
	local _, size = model:GetBoundingBox()
	local dist = (math.max(size.X, size.Y, size.Z) * 1.45 + 2) * (opts.Zoom or 1)
	cam.CFrame = CFrame.lookAt(Vector3.new(0, size.Y * 0.35, -dist), Vector3.new(0, 0, 0))
	cam.Parent = vp
	vp.CurrentCamera = cam
	viewports[vp] = { Model = model, Spin = opts.Spin or 0, Base = base, Phase = math.random() * 6, Static = opts.Silhouette }
	return vp
end

function UI.FormatNumber(n: number): string
	n = math.floor(n)
	if n >= 1e9 then
		return string.format("%.2fB", n / 1e9)
	elseif n >= 1e6 then
		return string.format("%.2fM", n / 1e6)
	elseif n >= 1e4 then
		return string.format("%.1fK", n / 1e3)
	end
	local s = tostring(n)
	return (s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", ""))
end

function UI.FormatPercent(p: number): string
	local pct = p * 100
	if pct == 0 then
		return "0%"
	elseif pct >= 10 then
		return string.format("%.1f%%", pct)
	elseif pct >= 0.1 then
		return string.format("%.2f%%", pct)
	end
	return string.format("%.4f%%", pct) .. string.format(" (1 in %s)", UI.FormatNumber(1 / p))
end

return UI
