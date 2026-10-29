-- Tiered reveal sequence. The outcome is already final (claimed from the server);
-- this is presentation only. Tap anywhere to skip to the end at any time.
-- Anticipation is honest: the egg's glow climbs through tiers only up to the real tier.
-- While a reveal is open the LocalPlayer attribute "RevealActive" is set, so the
-- world follower (PetController) only hatches into the world after it closes.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage.MonsterFactory.Shared
local Rarity = require(Shared.Rarity)
local Mutations = require(Shared.Mutations)
local Species = require(Shared.Species)
local MonsterVisuals = require(Shared.MonsterVisuals)
local UI = require(script.Parent.UIKit)

local Reveal = {}
Reveal.Active = false

local function tween(inst, t, props, style, dir)
	local tw = TweenService:Create(inst, TweenInfo.new(t, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), props)
	tw:Play()
	return tw
end

-- ctx: { Skip: boolean, OnContinue: () -> (), OnAgain: (() -> ())?, AgainLabel: string?, OnEquip: (() -> ())? }
function Reveal.Play(response, ctx)
	if Reveal.Active then
		return
	end
	Reveal.Active = true
	Players.LocalPlayer:SetAttribute("RevealActive", true)
	local record = response.Record
	local tier = record.RarityTier
	local tierDef = Rarity.Get(tier)
	local species = Species.ById[record.SpeciesId]
	local newSet = {}
	for _, id in response.NewMutations or {} do
		newSet[id] = true
	end

	local gui = UI.new("ScreenGui", {
		Name = "RevealGui",
		DisplayOrder = 20,
		IgnoreGuiInset = true,
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
	})
	local backdrop = UI.new("TextButton", {
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Parent = gui,
	})
	local stage = UI.new("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(900, 640),
		Parent = gui,
	})
	UI.new("UIAspectRatioConstraint", { AspectRatio = 900 / 640, Parent = stage })
	UI.new("UISizeConstraint", { MaxSize = Vector2.new(900, 640), Parent = stage })

	-- Rotating light rays behind the monster.
	local rays = UI.new("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.36),
		Size = UDim2.fromOffset(620, 620),
		Visible = false,
		Parent = stage,
	})
	for i = 1, 12 do
		local r = UI.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(0, 34, 1, 0),
			Rotation = i * 15,
			BackgroundColor3 = tierDef.Color,
			BackgroundTransparency = 0.75,
			BorderSizePixel = 0,
			Parent = rays,
		})
		UI.new("UIGradient", {
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0), NumberSequenceKeypoint.new(1, 1) }),
			Rotation = 90,
			Parent = r,
		})
	end

	-- Charging orb.
	local orb = UI.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.36),
		Size = UDim2.fromOffset(170, 200),
		BackgroundColor3 = Rarity.Tiers[1].Color,
		Parent = stage,
	})
	UI.Corner(orb, 100)
	UI.Stroke(orb, 5)
	UI.Gradient(orb, Color3.new(1, 1, 1), Color3.fromRGB(150, 150, 150))
	local orbScale = UI.new("UIScale", { Scale = 0, Parent = orb })
	-- Egg spots in the species' colour, and cracks that appear while it charges.
	local spotColor = MonsterVisuals.Palettes[record.Genes.BaseColorGene] or Color3.fromRGB(120, 200, 120)
	for _, s in { { 0.25, 0.3, 34 }, { 0.62, 0.22, 26 }, { 0.55, 0.6, 40 }, { 0.2, 0.68, 22 } } do
		local spot = UI.new("Frame", { BackgroundColor3 = spotColor, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(s[1], s[2]), Size = UDim2.fromOffset(s[3], s[3] * 0.8), Parent = orb })
		UI.Corner(spot, 40)
	end
	local cracks = {}
	for i, c in { { 0.5, 0.18, 20, 46 }, { 0.42, 0.3, -35, 40 }, { 0.6, 0.36, 30, 44 }, { 0.38, 0.5, 15, 50 }, { 0.62, 0.55, -25, 46 }, { 0.5, 0.7, 40, 42 } } do
		local crack = UI.new("Frame", { BackgroundColor3 = Color3.fromRGB(40, 35, 30), BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(c[1], c[2]), Size = UDim2.fromOffset(5, c[4]), Rotation = c[3], Visible = false, ZIndex = 2, Parent = orb })
		cracks[i] = crack
	end

	-- Monster viewport.
	local vpHolder = UI.new("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.36),
		Size = UDim2.fromOffset(340, 340),
		Visible = false,
		Parent = stage,
	})
	local vpScale = UI.new("UIScale", { Scale = 0, Parent = vpHolder })
	UI.MonsterViewport(vpHolder, record.SpeciesId, record.Genes, record.ActiveMutations, { Spin = 0.6, Seed = #record.MonsterId, RarityTier = record.RarityTier })

	-- Banner.
	local banner = UI.Label(stage, tierDef.Glyph .. " " .. string.upper(tierDef.Name) .. " " .. tierDef.Glyph, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.66),
		Size = UDim2.fromOffset(600, 64),
		TextColor3 = tierDef.Color,
		Visible = false,
	})
	;(banner:FindFirstChildOfClass("UITextSizeConstraint") :: UITextSizeConstraint).MaxTextSize = 64
	local bannerScale = UI.new("UIScale", { Parent = banner })
	local speciesNote = Rarity.Get(record.SpeciesRarity).Name .. " species"
	if record.DisplayName ~= species.DisplayName then
		speciesNote = species.DisplayName .. ", " .. speciesNote
	end
	local nameLabel = UI.Label(stage, record.DisplayName .. "  (" .. speciesNote .. ")", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.735),
		Size = UDim2.fromOffset(700, 32),
		Visible = false,
	})

	-- Mutation chips.
	local chips = UI.new("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.775),
		Size = UDim2.fromOffset(820, 80),
		Parent = stage,
	})
	UI.new("UIGridLayout", {
		CellSize = UDim2.fromOffset(200, 34),
		CellPadding = UDim2.fromOffset(8, 6),
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = chips,
	})
	local chipList = {}
	local sorted = table.clone(record.ActiveMutations)
	table.sort(sorted, function(a, b)
		return Mutations.ById[a].RarityTier > Mutations.ById[b].RarityTier
	end)
	for i, id in sorted do
		local m = Mutations.ById[id]
		local def = Rarity.Get(m.RarityTier)
		local chip = UI.new("Frame", { BackgroundColor3 = def.Color, LayoutOrder = i, Visible = false, Parent = chips })
		UI.Corner(chip, 10)
		UI.Stroke(chip, 2)
		UI.Gradient(chip, Color3.new(1, 1, 1), Color3.fromRGB(170, 170, 170))
		UI.Label(chip, def.Glyph .. " " .. m.DisplayName, { Size = UDim2.new(1, -10, 1, -8), Position = UDim2.fromOffset(5, 4) })
		if newSet[id] then
			local tag = UI.new("Frame", { BackgroundColor3 = UI.Colors.Red, Size = UDim2.fromOffset(48, 20), Position = UDim2.new(1, -40, 0, -10), Rotation = 8, Parent = chip })
			UI.Corner(tag, 6)
			UI.Stroke(tag, 2)
			UI.Label(tag, "NEW!")
		end
		if m.Category == "Hybrid" then
			local tag = UI.new("Frame", { BackgroundColor3 = UI.Colors.Purple, Size = UDim2.fromOffset(64, 20), Position = UDim2.new(0, -14, 0, -10), Rotation = -8, Parent = chip })
			UI.Corner(tag, 6)
			UI.Stroke(tag, 2)
			UI.Label(tag, "HYBRID")
		end
		local s = UI.new("UIScale", { Parent = chip })
		table.insert(chipList, { Frame = chip, Scale = s })
	end
	if #sorted == 0 then
		local l = UI.Label(chips, "No mutations - a pure " .. species.DisplayName, { TextColor3 = UI.Colors.Muted, Visible = false })
		table.insert(chipList, { Frame = l, Scale = UI.new("UIScale", { Parent = l }) })
	end

	-- Rewards line + buttons.
	local rewardBits = { "+" .. response.XP .. " XP" }
	if (response.RewardCoins or 0) > 0 then
		table.insert(rewardBits, "+" .. UI.FormatNumber(response.RewardCoins) .. " coins (discoveries)")
	end
	if response.PityUsed then
		table.insert(rewardBits, "Bad-luck protection used")
	end
	if record.HybridRecipe then
		local ok, HybridRecipes = pcall(require, ReplicatedStorage.MonsterFactory.Shared.HybridRecipes)
		local recipe = ok and HybridRecipes.ById[record.HybridRecipe]
		if recipe then
			table.insert(rewardBits, "Hybrid: " .. recipe.DisplayName)
		end
	end
	local rewards = UI.Label(stage, table.concat(rewardBits, "   •   "), {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.905),
		Size = UDim2.fromOffset(760, 26),
		TextColor3 = UI.Colors.Gold,
		Visible = false,
	})
	local buttons = UI.new("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 1, 4),
		Size = UDim2.fromOffset(640, 54),
		Visible = false,
		Parent = stage,
	})
	UI.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, 16),
		Parent = buttons,
	})
	local continueBtn = UI.Button(buttons, "Continue", UI.Colors.Blue, { Size = UDim2.fromOffset(190, 52) })
	local againBtn = UI.Button(buttons, ctx.AgainLabel or "Incubate Again", UI.Colors.Green, { Size = UDim2.fromOffset(220, 52) })
	againBtn.Visible = ctx.OnAgain ~= nil
	local equipBtn = UI.Button(buttons, "Equip", UI.Colors.Purple, { Name = "RevealEquip", Size = UDim2.fromOffset(150, 52) })
	equipBtn.Visible = ctx.OnEquip ~= nil
	equipBtn.Activated:Connect(function()
		if ctx.OnEquip and not UI.IsDisabled(equipBtn) then
			ctx.OnEquip()
			UI.SetDisabled(equipBtn, true)
			UI.SetButtonText(equipBtn, "Following!")
		end
	end)

	local skipHint = UI.Label(gui, "Tap to skip", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -16),
		Size = UDim2.fromOffset(200, 24),
		TextColor3 = UI.Colors.Muted,
	})

	local raysConn = RunService.RenderStepped:Connect(function(dt)
		rays.Rotation += dt * 20
	end)

	local skipped = ctx.Skip == true
	local finished = false
	local function wait_(t: number): boolean
		local t0 = os.clock()
		while os.clock() - t0 < t do
			if skipped then
				return false
			end
			RunService.RenderStepped:Wait()
		end
		return not skipped
	end

	local function finalize()
		if finished then
			return
		end
		finished = true
		backdrop.BackgroundTransparency = 0.25
		orb.Visible = false
		rays.Visible = tier >= 2
		vpHolder.Visible = true
		vpScale.Scale = 1
		banner.Visible = true
		bannerScale.Scale = 1
		nameLabel.Visible = true
		for _, c in chipList do
			c.Frame.Visible = true
			c.Scale.Scale = 1
		end
		rewards.Visible = true
		buttons.Visible = true
		skipHint.Visible = false
		stage.Position = UDim2.fromScale(0.5, 0.5)
	end

	local function close()
		raysConn:Disconnect()
		gui:Destroy()
		Reveal.Active = false
		Players.LocalPlayer:SetAttribute("RevealActive", nil) -- pet hatches into the world now
	end
	backdrop.Activated:Connect(function()
		skipped = true
		finalize()
	end)
	continueBtn.Activated:Connect(function()
		close()
		ctx.OnContinue()
	end)
	againBtn.Activated:Connect(function()
		close()
		if ctx.OnAgain then
			ctx.OnAgain()
		end
	end)

	local function confetti()
		if tier < 3 then
			return
		end
		local n = math.min(15 * (tier - 2), 60)
		for _ = 1, n do
			local c = UI.new("Frame", {
				BackgroundColor3 = if math.random() < 0.5 then tierDef.Color else Color3.fromHSV(math.random(), 0.7, 1),
				BorderSizePixel = 0,
				Size = UDim2.fromOffset(math.random(8, 14), math.random(12, 20)),
				Position = UDim2.fromScale(math.random(), -0.05),
				Rotation = math.random(0, 360),
				Parent = gui,
			})
			local dur = math.random(18, 32) / 10
			tween(c, dur, { Position = UDim2.fromScale(c.Position.X.Scale + math.random(-10, 10) / 100, 1.05), Rotation = c.Rotation + math.random(-540, 540) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			task.delay(dur, function()
				c:Destroy()
			end)
		end
	end

	task.spawn(function()
		if skipped then
			finalize()
			return
		end
		tween(backdrop, 0.3, { BackgroundTransparency = 0.25 })
		tween(orbScale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
		UI.Play("Swoosh", 0.8, 0.4)
		if not wait_(0.35) then
			return
		end
		-- Charge: shake grows; the orb climbs tier colours up to the real tier.
		local charge = math.min(1.1 + 0.35 * tier, 3.8)
		local steps = math.max(tier, 1)
		local t0 = os.clock()
		local shown = 1
		while os.clock() - t0 < charge do
			if skipped then
				return
			end
			local a = (os.clock() - t0) / charge
			local amp = math.floor(2 + a * (4 + tier * 2))
			orb.Position = UDim2.new(0.5, math.random(-amp, amp), 0.36, math.random(-amp, amp))
			orb.Rotation = math.random(-amp, amp) * 0.6
			for i, crack in cracks do
				if not crack.Visible and a >= i / (#cracks + 1) then
					crack.Visible = true
					UI.Play("Tick", 1.6 + i * 0.05, 0.3)
				end
			end
			local target = math.clamp(math.floor(a * steps) + 1, 1, tier)
			if target > shown then
				shown = target
				orb.BackgroundColor3 = Rarity.Get(shown).Color
				orbScale.Scale = 1.15
				tween(orbScale, 0.2, { Scale = 1 + a * 0.15 }, Enum.EasingStyle.Back)
				UI.Play("Tick", 0.9 + shown * 0.12, 0.5)
			end
			RunService.RenderStepped:Wait()
		end
		-- Legendary+: light pillars and a slow-motion moment before the hatch.
		if tier >= 5 then
			rays.Visible = true
			backdrop.BackgroundTransparency = 0.1
			UI.Play("Pop", 0.5, 0.8)
			local t1 = os.clock()
			while os.clock() - t1 < 0.9 do
				if skipped then
					return
				end
				local k = (os.clock() - t1) / 0.9
				orbScale.Scale = 1.15 + k * 0.25
				orb.Rotation = math.sin(os.clock() * 40) * 4 * k
				RunService.RenderStepped:Wait()
			end
		end
		-- Mythic+: three-colour transformation flashes.
		if tier >= 6 then
			for _, col in { Color3.fromRGB(255, 90, 120), Color3.fromRGB(120, 230, 255), tierDef.Color } do
				local f = UI.new("Frame", { BackgroundColor3 = col, BackgroundTransparency = 0.2, Size = UDim2.fromScale(1, 1), Parent = gui })
				tween(f, 0.18, { BackgroundTransparency = 1 })
				task.delay(0.2, function()
					f:Destroy()
				end)
				UI.Play("Snap", 1.2, 0.6)
				if not wait_(0.2) then
					return
				end
			end
		end
		-- Hatch: shell pieces fly out.
		for i = 1, 10 do
			local ang = i / 10 * math.pi * 2
			local shell = UI.new("Frame", {
				BackgroundColor3 = if i % 3 == 0 then spotColor else Color3.fromRGB(245, 245, 240),
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.36),
				Size = UDim2.fromOffset(math.random(26, 44), math.random(20, 34)),
				Rotation = math.random(0, 360),
				Parent = stage,
			})
			UI.Corner(shell, 6)
			UI.Stroke(shell, 2)
			tween(shell, 0.7, {
				Position = UDim2.new(0.5, math.cos(ang) * math.random(220, 360), 0.36, math.sin(ang) * math.random(160, 280)),
				Rotation = shell.Rotation + math.random(-360, 360),
				BackgroundTransparency = 1,
			}, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			task.delay(0.7, function()
				shell:Destroy()
			end)
		end
		-- Burst.
		local flash = UI.new("Frame", { BackgroundColor3 = Color3.new(1, 1, 1), Size = UDim2.fromScale(1, 1), Parent = gui })
		tween(flash, 0.5, { BackgroundTransparency = 1 })
		task.delay(0.5, function()
			flash:Destroy()
		end)
		UI.Play("Snap", 0.8 + tier * 0.05, 0.7)
		orb.Visible = false
		rays.Visible = tier >= 2
		vpHolder.Visible = true
		tween(vpScale, 0.45, { Scale = 1 }, Enum.EasingStyle.Back)
		confetti()
		if tier >= 4 then
			task.spawn(function()
				for i = 1, 14 do
					if skipped then
						break
					end
					local amp = math.floor((14 - i) * (tier - 2))
					stage.Position = UDim2.new(0.5, math.random(-amp, amp), 0.5, math.random(-amp, amp))
					task.wait(0.03)
				end
				stage.Position = UDim2.fromScale(0.5, 0.5)
			end)
		end
		if not wait_(0.45) then
			return
		end
		banner.Visible = true
		bannerScale.Scale = 2.4
		tween(bannerScale, 0.4, { Scale = 1 }, Enum.EasingStyle.Bounce)
		UI.Play("Pop", 0.7 + tier * 0.08, 0.6)
		if not wait_(0.35) then
			return
		end
		nameLabel.Visible = true
		for _, c in chipList do
			c.Frame.Visible = true
			c.Scale.Scale = 0
			tween(c.Scale, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
			UI.Play("Pop", 1.3, 0.35)
			if not wait_(0.18) then
				return
			end
		end
		if not wait_(0.2) then
			return
		end
		finalize()
	end)
end

return Reveal
