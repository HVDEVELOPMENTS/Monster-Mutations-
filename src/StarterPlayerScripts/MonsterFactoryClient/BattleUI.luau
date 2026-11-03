-- Pokemon-style battle screen. The server decides everything (BattleService);
-- this screen sends the player's choice and plays back the returned events:
-- a lunge, the element's attack animation (BattleFX), a hit flash, damage
-- numbers, smooth HP bars and short sentences a young player can read.
-- Layout: sky + ground arena; the foe stands top-right facing you, your monster
-- bottom-left seen from behind; message box, move buttons, team and Run below.

local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("MonsterFactory"):WaitForChild("Shared")
local Battle = require(Shared.Battle)
local UI = require(script.Parent.UIKit)
local FX = require(script.Parent.BattleFX)

local BattleUI = {}
BattleUI.Active = false

local BACK_YAW = 2.55 -- your monster, seen over its shoulder
local FRONT_YAW = 0.35 -- the foe, facing you

local function tween(inst: Instance, t: number, props: { [string]: any }, style: Enum.EasingStyle?, dir: Enum.EasingDirection?)
	local tw = TweenService:Create(inst, TweenInfo.new(t, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), props)
	tw:Play()
	return tw
end

local function zAll(inst: Instance, z: number)
	if inst:IsA("GuiObject") then
		inst.ZIndex = z
	end
	for _, d in inst:GetDescendants() do
		if d:IsA("GuiObject") then
			d.ZIndex = z
		end
	end
end

-- ctx: { Screen: ScreenGui, R: any, ShowError: (string?, any?) -> (), OnEnd: ((any) -> ())? }
function BattleUI.Init(ctx)
	local root = UI.new("Frame", {
		Name = "Battle",
		Active = true, -- swallow clicks so the HUD underneath can't be pressed
		BackgroundColor3 = Color3.new(1, 1, 1),
		-- Cover the top bar strip too (the ScreenGui keeps the inset).
		Position = UDim2.fromOffset(0, -GuiService:GetGuiInset().Y),
		Size = UDim2.new(1, 0, 1, GuiService:GetGuiInset().Y),
		Visible = false,
		ZIndex = 40,
		Parent = ctx.Screen,
	})
	-- Sky to grass, with a horizon line.
	UI.new("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(120, 200, 255)),
			ColorSequenceKeypoint.new(0.45, Color3.fromRGB(200, 235, 255)),
			ColorSequenceKeypoint.new(0.46, Color3.fromRGB(130, 210, 90)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(70, 160, 60)),
		}),
		Parent = root,
	})

	-- Everything that shakes on a big hit lives in the arena.
	local arena = UI.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 41, Parent = root })

	local function platform(pos: UDim2, w: number)
		local d = UI.new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = Color3.fromRGB(110, 190, 80), Position = pos, Size = UDim2.fromScale(w, w * 0.22), ZIndex = 41, Parent = arena })
		UI.Corner(d, 999)
		UI.Stroke(d, 4, Color3.fromRGB(40, 90, 30))
		UI.Gradient(d, Color3.fromRGB(170, 230, 120), Color3.fromRGB(80, 150, 55))
		return d
	end
	local foePlatform = platform(UDim2.fromScale(0.7, 0.44), 0.3)
	local myPlatform = platform(UDim2.fromScale(0.27, 0.72), 0.36)

	local function holder(pos: UDim2, size: number)
		-- Nearly square, so wide monsters (frogs, seals) aren't cut off at the sides.
		local h = UI.new("Frame", { AnchorPoint = Vector2.new(0.5, 1), BackgroundTransparency = 1, Position = pos, Size = UDim2.fromScale(size, size * 1.15), ZIndex = 42, Parent = arena })
		UI.new("UIAspectRatioConstraint", { AspectRatio = 1 / 1.15, Parent = h })
		return h
	end
	local FOE_POS, MY_POS = UDim2.fromScale(0.7, 0.47), UDim2.fromScale(0.27, 0.76)
	local foeHolder = holder(FOE_POS, 0.27)
	local myHolder = holder(MY_POS, 0.32)

	-- Name + HP cards.
	local function sideCard(pos: UDim2)
		local card = UI.new("Frame", { BackgroundColor3 = UI.Colors.Panel, Position = pos, Size = UDim2.fromScale(0.32, 0.13), ZIndex = 43, Parent = arena })
		UI.Corner(card, 16)
		UI.Stroke(card, 4)
		UI.Gloss(card, UI.Colors.Panel)
		UI.new("UISizeConstraint", { MaxSize = Vector2.new(440, 120), Parent = card })
		local name = UI.Label(card, "", { Size = UDim2.new(0.7, 0, 0.36, 0), Position = UDim2.fromScale(0.04, 0.08), TextXAlignment = Enum.TextXAlignment.Left })
		local chip = UI.new("Frame", { BackgroundColor3 = UI.Colors.Card, Position = UDim2.fromScale(0.76, 0.1), Size = UDim2.fromScale(0.2, 0.3), Parent = card })
		UI.Corner(chip, 8)
		UI.Stroke(chip, 2)
		local chipLabel = UI.Label(chip, "", { Size = UDim2.new(1, -6, 1, -4), Position = UDim2.fromOffset(3, 2) })
		local bar = UI.Bar(card, UI.Colors.Green, { Size = UDim2.new(0.92, 0, 0.2, 0), Position = UDim2.fromScale(0.04, 0.52) })
		local hp = UI.Label(card, "", { Size = UDim2.new(0.5, 0, 0.22, 0), Position = UDim2.fromScale(0.46, 0.74), TextXAlignment = Enum.TextXAlignment.Right })
		-- SUPER meter (gold) along the bottom left.
		local meter = UI.Bar(card, UI.Colors.Gold, { Size = UDim2.new(0.38, 0, 0.12, 0), Position = UDim2.fromScale(0.04, 0.8) })
		local meterLabel = UI.Label(card, "SUPER", { Size = UDim2.new(0.12, 0, 0.16, 0), Position = UDim2.fromScale(0.43, 0.78), TextXAlignment = Enum.TextXAlignment.Left, MaxTextSize = 14 })
		-- Status pill floating above the card (BURNED, FROZEN, GUARD...).
		local status = UI.new("Frame", { BackgroundColor3 = UI.Colors.Red, Position = UDim2.new(0.04, 0, 0, -28), Size = UDim2.fromOffset(120, 26), Visible = false, Parent = card })
		UI.Corner(status, 12)
		UI.Stroke(status, 3)
		local statusLabel = UI.Label(status, "", { Size = UDim2.new(1, -8, 1, -4), Position = UDim2.fromOffset(4, 2) })
		local guard = UI.new("Frame", { BackgroundColor3 = Color3.fromRGB(190, 140, 80), Position = UDim2.new(0.04, 128, 0, -28), Size = UDim2.fromOffset(90, 26), Visible = false, Parent = card })
		UI.Corner(guard, 12)
		UI.Stroke(guard, 3)
		UI.Label(guard, "GUARD", { Size = UDim2.new(1, -8, 1, -4), Position = UDim2.fromOffset(4, 2) })
		zAll(card, 43)
		return { Card = card, Name = name, Bar = bar, Hp = hp, Chip = chip, ChipLabel = chipLabel, Home = pos, Meter = meter, MeterLabel = meterLabel, Status = status, StatusLabel = statusLabel, Guard = guard }
	end
	local foeCard = sideCard(UDim2.fromScale(0.05, 0.07))
	local myCard = sideCard(UDim2.fromScale(0.6, 0.52))

	-- Attack effects draw above everything in the arena.
	local fxLayer = UI.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 70, Parent = root })

	-- Bottom panel: message, moves, team + Run.
	local bottom = UI.new("Frame", { BackgroundColor3 = UI.Colors.Panel, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -10), Size = UDim2.new(1, -20, 0.25, 0), ZIndex = 45, Parent = root })
	UI.Corner(bottom, 18)
	UI.Stroke(bottom, 5)
	UI.Gradient(bottom, Color3.fromRGB(80, 165, 250), Color3.fromRGB(45, 115, 215))
	local msgBox = UI.new("Frame", { BackgroundColor3 = Color3.fromRGB(250, 250, 255), Position = UDim2.fromOffset(10, 10), Size = UDim2.new(0.4, -14, 1, -20), ZIndex = 46, Parent = bottom })
	UI.Corner(msgBox, 14)
	UI.Stroke(msgBox, 3)
	local message = UI.Label(msgBox, "", {
		Size = UDim2.new(1, -24, 1, -16),
		Position = UDim2.fromOffset(12, 8),
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Color3.fromRGB(30, 30, 50),
		MaxTextSize = 30,
		ZIndex = 47,
	})
	local msgStroke = message:FindFirstChildOfClass("UIStroke")
	if msgStroke then
		msgStroke.Enabled = false -- dark text on a light box reads best
	end
	local moveArea = UI.new("Frame", { BackgroundTransparency = 1, Position = UDim2.new(0.4, 4, 0, 10), Size = UDim2.new(0.44, -10, 1, -20), ZIndex = 46, Parent = bottom })
	UI.new("UIGridLayout", { CellSize = UDim2.new(0.5, -5, 0.5, -5), CellPadding = UDim2.fromOffset(8, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = moveArea })
	local sideArea = UI.new("Frame", { BackgroundTransparency = 1, Position = UDim2.new(0.84, 4, 0, 10), Size = UDim2.new(0.16, -14, 1, -20), ZIndex = 46, Parent = bottom })
	local teamRow = UI.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0.58, -4), ZIndex = 46, Parent = sideArea })
	UI.new("UIListLayout", { FillDirection = Enum.FillDirection.Vertical, Padding = UDim.new(0, 3), Parent = teamRow })
	local runBtn = UI.Button(sideArea, "Run", UI.Colors.Red, { Size = UDim2.new(1, 0, 0.42, -2), Position = UDim2.fromScale(0, 0.58), ZIndex = 46 })
	zAll(runBtn, 47)
	local bottomHome = bottom.Position

	-- SUPER! button: appears above the moves when the meter is full, and pulses.
	local superBtn, superLabel = UI.Button(root, "SUPER!", UI.Colors.Gold, {
		Name = "SuperButton",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.63, 0, 0.75, -16),
		Size = UDim2.fromOffset(380, 66),
		Visible = false,
		ZIndex = 48,
	})
	superLabel.Font = UI.TitleFont
	zAll(superBtn, 48)
	local superScale = superBtn:FindFirstChildOfClass("UIScale") :: UIScale
	task.spawn(function()
		while true do
			if superBtn.Visible then
				superScale.Scale = 1 + math.abs(math.sin(os.clock() * 5)) * 0.07
				superBtn.Rotation = math.sin(os.clock() * 9) * 1.5
			end
			task.wait(0.03)
		end
	end)

	-- Result banner.
	local banner = UI.new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = UI.Colors.Gold, Position = UDim2.fromScale(0.5, 0.4), Size = UDim2.fromScale(0.5, 0.32), Visible = false, ZIndex = 85, Parent = root })
	UI.Corner(banner, 22)
	UI.Stroke(banner, 6)
	UI.new("UISizeConstraint", { MaxSize = Vector2.new(620, 300), Parent = banner })
	local bannerGloss = UI.Gloss(banner, UI.Colors.Gold)
	local bannerScale = UI.new("UIScale", { Parent = banner })
	local bannerTitle = UI.Label(banner, "", { Font = UI.TitleFont, Size = UDim2.new(1, -20, 0.4, 0), Position = UDim2.new(0, 10, 0.05, 0), MaxTextSize = 70 })
	local bannerText = UI.Label(banner, "", { Size = UDim2.new(1, -20, 0.22, 0), Position = UDim2.new(0, 10, 0.46, 0) })
	local continueBtn = UI.Button(banner, "Continue", UI.Colors.Green, { Size = UDim2.new(0.5, 0, 0.24, 0), Position = UDim2.fromScale(0.25, 0.71) })
	zAll(banner, 85)

	local battle = nil -- current server view
	local busy = false
	local finished = nil
	local typing = 0

	-- Typewriter text.
	local function setMessage(text: string, instant: boolean?)
		typing += 1
		local token = typing
		if instant then
			message.Text = text
			message.MaxVisibleGraphemes = -1
			return
		end
		message.Text = text
		message.MaxVisibleGraphemes = 0
		task.spawn(function()
			local n = utf8.len(text) or #text
			for i = 1, n, 2 do
				if typing ~= token then
					return
				end
				message.MaxVisibleGraphemes = i
				task.wait(0.012)
			end
			if typing == token then
				message.MaxVisibleGraphemes = -1
			end
		end)
	end

	local function hpColor(frac: number): Color3
		return if frac > 0.5 then UI.Colors.Green elseif frac > 0.2 then UI.Colors.Gold else UI.Colors.Red
	end
	local function setBar(side, c, animate: boolean)
		local frac = c.HP / math.max(c.MaxHP, 1)
		side.Bar.Set(frac, animate)
		local fill = side.Bar.Frame:FindFirstChild("Fill") :: Frame
		local grad = fill and fill:FindFirstChildOfClass("UIGradient")
		if grad then
			local col = hpColor(frac)
			grad.Color = ColorSequence.new(col:Lerp(Color3.new(1, 1, 1), 0.3), col)
		end
		side.Hp.Text = string.format("HP %d / %d", c.HP, c.MaxHP)
	end
	-- Status pill, guard pill and SUPER meter for a fighter.
	local function setExtras(side, c, animate: boolean?)
		local st = c.Status and Battle.Statuses[c.Status]
		side.Status.Visible = st ~= nil
		if st then
			side.StatusLabel.Text = st.Label
			side.Status.BackgroundColor3 = st.Color
		end
		side.Guard.Visible = (c.Guard or 0) > 0
		local frac = (c.Charge or 0) / Battle.SUPER_CHARGE
		side.Meter.Set(frac, animate)
		side.MeterLabel.Text = if frac >= 1 then "READY!" else "SUPER"
		side.MeterLabel.TextColor3 = if frac >= 1 then UI.Colors.Gold else Color3.new(1, 1, 1)
	end
	local function setCard(side, c, label: string)
		side.Name.Text = label
		side.ChipLabel.Text = c.Element
		side.Chip.BackgroundColor3 = Battle.ElementColors[c.Element] or UI.Colors.Card
		setBar(side, c, false)
		setExtras(side, c)
	end
	local function viewportOf(h: Frame): ViewportFrame?
		return h:FindFirstChildOfClass("ViewportFrame")
	end
	local function showMonster(h: Frame, c, mine: boolean)
		for _, ch in h:GetChildren() do
			if not ch:IsA("UIAspectRatioConstraint") then
				ch:Destroy()
			end
		end
		local vp = UI.MonsterViewport(h, c.SpeciesId, c.Genes, c.ActiveMutations, {
			Spin = 0.25,
			RarityTier = c.RarityTier,
			Zoom = if mine then 0.9 else 1.05,
			Yaw = if mine then BACK_YAW else FRONT_YAW,
		})
		if vp then
			vp.ZIndex = 42
		end
	end
	local function foeLabel(c): string
		if battle.Kind == "Wild" then
			return "Wild " .. c.Name
		elseif battle.Kind == "PvP" then
			return (battle.Opponent or "Foe") .. "'s " .. c.Name
		end
		return c.Name
	end
	-- Screen centre of a holder, in fxLayer space.
	local function centerOf(h: GuiObject): Vector2
		return h.AbsolutePosition + h.AbsoluteSize * Vector2.new(0.5, 0.55) - fxLayer.AbsolutePosition
	end

	local refreshControls: () -> ()
	local act: (any) -> ()

	local function refreshSides()
		local me, foe = battle.Team[battle.P], battle.Enemy[battle.E]
		setCard(myCard, me, me.Name)
		setCard(foeCard, foe, foeLabel(foe))
		showMonster(myHolder, me, true)
		showMonster(foeHolder, foe, false)
	end

	refreshControls = function()
		for _, c in moveArea:GetChildren() do
			if c:IsA("GuiObject") then
				c:Destroy()
			end
		end
		for _, c in teamRow:GetChildren() do
			if c:IsA("GuiObject") then
				c:Destroy()
			end
		end
		superBtn.Visible = false
		if not battle then
			return
		end
		local me = battle.Team[battle.P]
		local foe = battle.Enemy[battle.E]
		if me.Super and (me.Charge or 0) >= Battle.SUPER_CHARGE then
			superBtn.Visible = true
			UI.SetButtonText(superBtn, "SUPER: " .. Battle.Moves[me.Super].DisplayName .. "!")
		end
		for i, moveId in me.Moves do
			local m = Battle.Moves[moveId]
			local col = Battle.ElementColors[m.Element] or UI.Colors.Card
			local b, label = UI.Button(moveArea, m.DisplayName, col, { LayoutOrder = i })
			label.Size = UDim2.new(1, -12, 0.55, 0)
			label.Position = UDim2.fromOffset(6, 2)
			local mult = if m.Element == "Normal" then 1 else Battle.ElementMultiplier(m.Element, foe.Element)
			local tag = string.upper(m.Element) .. "  |  POWER " .. m.Power
			local sub = UI.Label(b, tag, { Size = UDim2.new(1, -12, 0.26, 0), Position = UDim2.new(0, 6, 0.55, 0), TextColor3 = Color3.fromRGB(255, 255, 255) })
			if mult > 1 then
				-- Super strong against this foe: gold badge + gentle pulse.
				local badge = UI.new("Frame", { BackgroundColor3 = UI.Colors.Gold, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 6, 0, -8), Size = UDim2.fromOffset(74, 22), Parent = b })
				UI.Corner(badge, 11)
				UI.Stroke(badge, 2)
				UI.Label(badge, "STRONG!", { Size = UDim2.new(1, -6, 1, -4), Position = UDim2.fromOffset(3, 2) })
			elseif mult < 1 then
				sub.TextColor3 = Color3.fromRGB(255, 210, 210)
				sub.Text = tag .. "  (weak)"
			end
			zAll(b, 47)
			b.Activated:Connect(function()
				act({ Type = "Move", Index = i })
			end)
		end
		for i, c in battle.Team do
			local alive = c.HP > 0
			local current = i == battle.P
			local b = UI.Button(teamRow, c.Name, if current then UI.Colors.Gold elseif alive then UI.Colors.Blue else Color3.fromRGB(120, 120, 130), {
				Size = UDim2.new(1, 0, 1 / 3, -2),
			})
			-- Mini HP strip along the bottom.
			local strip = UI.new("Frame", { BackgroundColor3 = Color3.fromRGB(30, 30, 40), Position = UDim2.new(0.06, 0, 1, -7), Size = UDim2.new(0.88, 0, 0, 4), Parent = b })
			UI.new("Frame", { BackgroundColor3 = hpColor(c.HP / c.MaxHP), Size = UDim2.fromScale(c.HP / c.MaxHP, 1), Parent = strip })
			UI.SetDisabled(b, not alive or current)
			zAll(b, 47)
			b.Activated:Connect(function()
				if alive and not current then
					act({ Type = "Switch", To = i })
				end
			end)
		end
	end

	-- Hit reaction: white flash, knock back, shake.
	local function hitReact(h: Frame, crit: boolean)
		local vp = viewportOf(h)
		if vp then
			vp.ImageColor3 = Color3.fromRGB(255, 120, 120)
			task.delay(0.08, function()
				vp.ImageColor3 = Color3.new(1, 1, 1)
			end)
			task.delay(0.16, function()
				vp.ImageColor3 = Color3.fromRGB(255, 160, 160)
			end)
			task.delay(0.24, function()
				vp.ImageColor3 = Color3.new(1, 1, 1)
			end)
		end
		FX.Shake(h, if crit then 16 else 9, 0.3)
	end

	local function popText(at: Vector2, text: string, color: Color3, big: boolean?)
		local l = UI.Label(fxLayer, text, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Font = UI.TitleFont,
			Size = UDim2.fromOffset(if big then 360 else 160, if big then 70 else 48),
			Position = UDim2.fromOffset(at.X, at.Y),
			TextColor3 = color,
			MaxTextSize = if big then 64 else 44,
			ZIndex = 78,
		})
		local s = UI.new("UIScale", { Scale = 0.3, Parent = l })
		tween(s, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
		tween(l, 0.9, { Position = l.Position - UDim2.fromOffset(0, 60) })
		task.delay(0.6, function()
			tween(l, 0.3, { TextTransparency = 1 })
			local st = l:FindFirstChildOfClass("UIStroke")
			if st then
				tween(st, 0.3, { Transparency = 1 })
			end
		end)
		task.delay(0.95, function()
			l:Destroy()
		end)
	end

	-- ===== Trainer talk =====
	-- A speech bubble by the foe's card; lines depend on how the fight goes.
	local bubble = UI.new("Frame", { BackgroundColor3 = Color3.new(1, 1, 1), Position = UDim2.new(0.38, 0, 0.07, 0), Size = UDim2.fromOffset(340, 74), Visible = false, ZIndex = 62, Parent = arena })
	UI.Corner(bubble, 18)
	UI.Stroke(bubble, 4)
	local bubbleLabel = UI.Label(bubble, "", { Size = UDim2.new(1, -24, 1, -14), Position = UDim2.fromOffset(12, 7), TextWrapped = true, TextColor3 = Color3.fromRGB(30, 30, 50), MaxTextSize = 24, ZIndex = 63 })
	local bubbleStroke = bubbleLabel:FindFirstChildOfClass("UIStroke")
	if bubbleStroke then
		bubbleStroke.Enabled = false
	end
	local bubbleToken = 0
	local LINES = {
		FoeDown = { "Hey! That was my favourite!", "Okay... that was strong!", "Don't get cocky!", "Lucky shot!" },
		LastOne = { "This is my last one. GO!", "You won't beat my best!", "Time to get serious!" },
		YourDown = { "Ha! Got you!", "Is that all you've got?", "My team is too strong!" },
		Super = { "Feel my SUPER power!", "Here comes the big one!", "Watch THIS!" },
		Win = { "Better luck next time!", "Train harder and come back!", "Ha! I win!" },
		Lose = { "Wow... you're really good!", "You beat me fair and square!", "I'll train harder!" },
	}
	local function say(kind: string)
		if not battle or battle.Kind ~= "Trainer" then
			return
		end
		local list = LINES[kind]
		bubbleToken += 1
		local token = bubbleToken
		bubbleLabel.Text = (battle.TrainerName or "Trainer") .. ": " .. list[math.random(1, #list)]
		bubble.Visible = true
		local s = bubble:FindFirstChildOfClass("UIScale") or UI.new("UIScale", { Parent = bubble })
		s.Scale = 0.4
		tween(s, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
		task.delay(2.6, function()
			if bubbleToken == token then
				bubble.Visible = false
			end
		end)
	end

	-- SUPER cinematic: darken, the attacker grows, a giant title slams in.
	local function superCinematic(mine: boolean, atkHolder: Frame, m)
		local col = Battle.ElementColors[m.Element] or UI.Colors.Gold
		local dim = UI.new("Frame", { BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 64, Parent = fxLayer })
		tween(dim, 0.2, { BackgroundTransparency = 0.45 })
		local band = UI.new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = col, Position = UDim2.fromScale(-0.6, 0.38), Size = UDim2.fromScale(1.2, 0.16), Rotation = -6, ZIndex = 65, Parent = fxLayer })
		UI.Stroke(band, 6)
		UI.Gloss(band, col)
		local title = UI.Label(band, string.upper(m.DisplayName) .. "!", { Font = UI.TitleFont, Size = UDim2.new(0.8, 0, 0.8, 0), Position = UDim2.fromScale(0.1, 0.1), MaxTextSize = 90, ZIndex = 66 })
		tween(band, 0.3, { Position = UDim2.fromScale(0.5, 0.38) }, Enum.EasingStyle.Back)
		local s = atkHolder:FindFirstChildOfClass("UIScale") or UI.new("UIScale", { Parent = atkHolder })
		tween(s, 0.3, { Scale = 1.35 }, Enum.EasingStyle.Back)
		UI.Play("Pop", 0.6, 0.9)
		task.wait(1.0)
		tween(band, 0.25, { Position = UDim2.fromScale(1.6, 0.38) })
		tween(dim, 0.25, { BackgroundTransparency = 1 })
		tween(s, 0.25, { Scale = 1 })
		task.delay(0.3, function()
			dim:Destroy()
			band:Destroy()
		end)
		task.wait(0.15)
		return title
	end

	local function playEvents(events: { any })
		for _, ev in events do
			if ev.Kind == "Move" then
				local mine = ev.Side == "P"
				local atk = if mine then battle.Team[battle.P] else battle.Enemy[battle.E]
				local def = if mine then battle.Enemy[battle.E] else battle.Team[battle.P]
				local m = Battle.Moves[ev.Move]
				local atkHolder = if mine then myHolder else foeHolder
				local defHolder = if mine then foeHolder else myHolder
				if m.Super then
					setMessage(string.format("%s unleashes %s!", if mine then atk.Name else foeLabel(atk), m.DisplayName))
					if not mine then
						say("Super")
					end
					superCinematic(mine, atkHolder, m)
				elseif m.Signature and battle.TrainerName then
					setMessage(string.format("%s's special move: %s!", battle.TrainerName, m.DisplayName))
					FX.Flash(fxLayer, Battle.ElementColors[m.Element] or Color3.new(1, 1, 1), 0.35)
				else
					setMessage(string.format("%s used %s!", if mine then atk.Name else foeLabel(atk), m.DisplayName))
				end
				-- Lunge toward the target.
				local home = atkHolder.Position
				local dir = if mine then UDim2.fromScale(0.05, -0.04) else UDim2.fromScale(-0.05, 0.04)
				tween(atkHolder, 0.14, { Position = home + dir }, Enum.EasingStyle.Back).Completed:Wait()
				tween(atkHolder, 0.18, { Position = home })
				UI.Play("Swoosh", if mine then 1.15 else 0.9, 0.45)
				-- The element's attack animation flies from attacker to target
				-- (a SUPER plays it twice, at full strength, with a big shake).
				FX.Attack(fxLayer, m.Element, centerOf(atkHolder), centerOf(defHolder), m.Power >= 70, arena)
				if m.Super then
					FX.Attack(fxLayer, m.Element, centerOf(atkHolder), centerOf(defHolder), true, arena)
					FX.Flash(fxLayer, Color3.new(1, 1, 1), 0.85)
					task.spawn(FX.Shake, arena, 22, 0.5)
				end
				-- Meters fill as fighters trade hits.
				if ev.AtkCharge then
					atk.Charge = ev.AtkCharge
					def.Charge = ev.DefCharge
					setExtras(if mine then myCard else foeCard, atk, true)
					setExtras(if mine then foeCard else myCard, def, true)
				end
				if ev.Miss then
					popText(centerOf(defHolder), "MISS", Color3.fromRGB(230, 230, 240))
					setMessage("It missed!")
					task.wait(0.6)
				else
					UI.Play("Pop", if ev.Crit then 0.7 else 0.95, 0.6)
					task.spawn(hitReact, defHolder, ev.Crit or m.Super)
					popText(centerOf(defHolder) + Vector2.new(0, -40), "-" .. ev.Damage, if ev.Mult > 1 or m.Super then UI.Colors.Gold else UI.Colors.Red, m.Super)
					if ev.Crit then
						FX.Flash(fxLayer, Color3.fromRGB(255, 240, 150), 0.6)
						popText(centerOf(defHolder) + Vector2.new(0, 30), "CRITICAL HIT!", UI.Colors.Gold, true)
					end
					def.HP = ev.HP
					setBar(if mine then foeCard else myCard, def, true)
					task.wait(0.55)
					local extra = {}
					if ev.Crit then
						table.insert(extra, "A critical hit!")
					end
					if ev.Mult > 1 then
						table.insert(extra, "It's super strong!")
					elseif ev.Mult < 1 then
						table.insert(extra, "It's not very strong...")
					end
					if #extra > 0 then
						setMessage(table.concat(extra, " "))
						task.wait(0.8)
					end
				end
			elseif ev.Kind == "Skip" then
				local mine = ev.Side == "P"
				local c = if mine then battle.Team[battle.P] else battle.Enemy[battle.E]
				local h = if mine then myHolder else foeHolder
				local st = Battle.Statuses[ev.Status]
				setMessage((if mine then c.Name else foeLabel(c)) .. (if ev.Status == "Freeze" then " is frozen solid!" else " is too shocked to move!"))
				popText(centerOf(h), st.Label .. "!", st.Color, true)
				task.spawn(FX.Shake, h, 6, 0.4)
				task.wait(0.9)
			elseif ev.Kind == "Status" then
				local mine = ev.Side == "P"
				local c = if mine then battle.Team[battle.P] else battle.Enemy[battle.E]
				local st = Battle.Statuses[ev.Status]
				c.Status = ev.Status
				setExtras(if mine then myCard else foeCard, c)
				local h = if mine then myHolder else foeHolder
				FX.Burst(fxLayer, centerOf(h), st.Color, 1)
				popText(centerOf(h) + Vector2.new(0, 40), st.Label .. "!", st.Color, true)
				setMessage((if mine then c.Name else foeLabel(c)) .. " is " .. string.lower(st.Label) .. "!")
				task.wait(0.8)
			elseif ev.Kind == "StatusTick" then
				local mine = ev.Side == "P"
				local c = if mine then battle.Team[battle.P] else battle.Enemy[battle.E]
				local st = Battle.Statuses[ev.Status]
				local h = if mine then myHolder else foeHolder
				FX.Burst(fxLayer, centerOf(h), st.Color, 0.6)
				popText(centerOf(h) + Vector2.new(0, -30), "-" .. ev.Damage, st.Color)
				c.HP = ev.HP
				setBar(if mine then myCard else foeCard, c, true)
				setMessage((if mine then c.Name else foeLabel(c)) .. " is hurt by " .. (if ev.Status == "Burn" then "its burn!" else "poison!"))
				task.wait(0.7)
			elseif ev.Kind == "StatusEnd" then
				local mine = ev.Side == "P"
				local c = if mine then battle.Team[battle.P] else battle.Enemy[battle.E]
				c.Status = nil
				setExtras(if mine then myCard else foeCard, c)
				setMessage((if mine then c.Name else foeLabel(c)) .. " feels better!")
				task.wait(0.5)
			elseif ev.Kind == "Heal" then
				local mine = ev.Side == "P"
				local c = if mine then battle.Team[battle.P] else battle.Enemy[battle.E]
				local h = if mine then myHolder else foeHolder
				c.HP = ev.HP
				setBar(if mine then myCard else foeCard, c, true)
				FX.Burst(fxLayer, centerOf(h), Color3.fromRGB(110, 255, 120), 0.8)
				popText(centerOf(h) + Vector2.new(0, -30), "+" .. ev.Amount, Color3.fromRGB(110, 255, 120))
				setMessage((if mine then c.Name else foeLabel(c)) .. " soaks up energy and heals!")
				task.wait(0.7)
			elseif ev.Kind == "Guard" then
				local mine = ev.Side == "P"
				local c = if mine then battle.Team[battle.P] else battle.Enemy[battle.E]
				c.Guard = 3
				setExtras(if mine then myCard else foeCard, c)
				setMessage((if mine then c.Name else foeLabel(c)) .. " raises a rock-hard guard!")
				task.wait(0.6)
			elseif ev.Kind == "Faint" then
				local mine = ev.Side == "P"
				local c = if mine then battle.Team[ev.Index] else battle.Enemy[ev.Index]
				c.HP = 0
				setMessage((if mine then c.Name else foeLabel(c)) .. " fainted!")
				local h = if mine then myHolder else foeHolder
				local vp = viewportOf(h)
				local home = h.Position
				UI.Play("Pop", 0.5, 0.6)
				tween(h, 0.5, { Position = home + UDim2.fromScale(0, 0.12) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
				if vp then
					tween(vp, 0.5, { ImageTransparency = 1 })
				end
				say(if mine then "YourDown" else "FoeDown")
				task.wait(0.8)
				h.Position = home
			elseif ev.Kind == "SendOut" then
				local mine = ev.Side == "P"
				if mine then
					battle.P = ev.Index
				else
					battle.E = ev.Index
				end
				local c = if mine then battle.Team[ev.Index] else battle.Enemy[ev.Index]
				setMessage(if mine then ("Go, " .. c.Name .. "!") else ((battle.TrainerName or battle.Opponent or "The foe") .. " sends out " .. c.Name .. "!"))
				if not mine then
					local left = 0
					for _, e in battle.Enemy do
						left += if e.HP > 0 then 1 else 0
					end
					if left == 1 then
						say("LastOne")
					end
				end
				refreshSides()
				-- Pop in from a burst of light.
				local h = if mine then myHolder else foeHolder
				FX.Burst(fxLayer, centerOf(h), Color3.fromRGB(255, 255, 255), 1.1)
				local s = h:FindFirstChildOfClass("UIScale") or UI.new("UIScale", { Parent = h })
				s.Scale = 0.2
				tween(s, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
				UI.Play("Pop", 1.1, 0.5)
				task.wait(0.8)
			elseif ev.Kind == "Run" then
				setMessage("You ran away safely!")
				task.wait(0.6)
			elseif ev.Kind == "Forfeit" then
				setMessage(if ev.Side == "P" then "You gave up." else ((battle.Opponent or "Your opponent") .. " gave up!"))
				task.wait(0.9)
			end
		end
	end

	-- PvP turn timer (top centre): the server picks for you when it runs out.
	local timerBox = UI.new("Frame", { AnchorPoint = Vector2.new(0.5, 0), BackgroundColor3 = UI.Colors.Gold, Position = UDim2.new(0.5, 0, 0, GuiService:GetGuiInset().Y + 8), Size = UDim2.fromOffset(230, 44), Visible = false, ZIndex = 60, Parent = root })
	UI.Corner(timerBox, 14)
	UI.Stroke(timerBox, 3)
	UI.Gloss(timerBox, UI.Colors.Gold)
	local timerLabel = UI.Label(timerBox, "", { Size = UDim2.new(1, -12, 1, -8), Position = UDim2.fromOffset(6, 4), ZIndex = 61 })
	local turnEndsAt = 0
	local waiting = false
	local turnSeq = 0 -- bumps whenever the server pushes a PvP turn
	task.spawn(function()
		while true do
			task.wait(0.2)
			-- Hidden while a turn is being played out (busy and not waiting).
			local pvp = battle ~= nil and battle.Kind == "PvP" and BattleUI.Active and (waiting or not busy)
			timerBox.Visible = pvp
			if pvp then
				local left = math.max(0, math.ceil(turnEndsAt - os.clock()))
				timerLabel.Text = if waiting then string.format("Waiting...  %d", left) else string.format("Pick a move!  %d", left)
				timerBox.BackgroundColor3 = if left <= 5 then UI.Colors.Red else UI.Colors.Gold
			end
		end
	end)
	local function startTurnTimer()
		if battle and battle.Kind == "PvP" then
			turnEndsAt = os.clock() + (battle.TurnSeconds or 30)
		end
	end

	local function finish(resp)
		BattleUI.Active = false
		finished = resp
		waiting = false
		if resp.Result == "Ran" then
			tween(root, 0.25, { BackgroundTransparency = 1 })
			task.wait(0.25)
			root.Visible = false
			root.BackgroundTransparency = 0
			if ctx.OnEnd then
				ctx.OnEnd(resp)
			end
			return
		end
		local won = resp.Result == "Win"
		local pvp = battle and battle.Kind == "PvP"
		local col = if won then UI.Colors.Gold else UI.Colors.Blue
		bannerGloss.Color = UI.GlossSequence(col)
		bannerTitle.Text = if won then "YOU WIN!" else (if pvp then "GOOD TRY!" else "OH NO!")
		if won then
			bannerText.Text = if (resp.Coins or 0) > 0 then string.format("+%s coins   +%d XP", UI.FormatNumber(resp.Coins), resp.XP or 0) else "What a battle!"
			if resp.Badge then
				-- First win over a boss: a badge!
				bannerTitle.Text = "NEW BADGE!"
				bannerGloss.Color = UI.GlossSequence(UI.Colors.Purple)
				bannerText.Text = string.format("%s Badge!  +%s coins", ctx.BadgeName and ctx.BadgeName(resp.Badge) or resp.Badge, UI.FormatNumber(resp.Coins or 0))
				task.spawn(FX.Confetti, fxLayer)
			end
		else
			say("Win")
			bannerText.Text = if pvp then ((battle.Opponent or "They") .. " won this time!") else "Your team needs a rest. Try again!"
		end
		banner.Visible = true
		bannerScale.Scale = 0.3
		tween(bannerScale, 0.4, { Scale = 1 }, Enum.EasingStyle.Back)
		UI.Play("Pop", if won then 1.3 else 0.7, 0.7)
		if won then
			say("Lose")
			task.spawn(FX.Confetti, fxLayer)
		end
	end

	-- Plays a finished turn (from our own request, or pushed by the server in PvP).
	local function afterTurn(resp)
		playEvents(resp.Events or {})
		busy = false
		waiting = false
		if resp.Result then
			finish(resp)
			return
		end
		battle = resp.Battle
		refreshSides()
		refreshControls()
		startTurnTimer()
		tween(bottom, 0.25, { Position = bottomHome }, Enum.EasingStyle.Back)
		setMessage("What will " .. battle.Team[battle.P].Name .. " do?")
	end

	act = function(action)
		if busy or not battle then
			return
		end
		busy = true
		superBtn.Visible = false
		for _, c in moveArea:GetChildren() do
			if c:IsA("GuiButton") then
				UI.SetDisabled(c, true)
			end
		end
		tween(bottom, 0.2, { Position = bottomHome + UDim2.fromScale(0, 0.04) })
		local seq = turnSeq
		local resp = ctx.R.BattleAction:InvokeServer(battle.Id, action)
		if not resp or not resp.Ok then
			busy = false
			tween(bottom, 0.2, { Position = bottomHome })
			ctx.ShowError(resp and resp.Error)
			refreshControls()
			return
		end
		if resp.Waiting then
			-- PvP: the turn plays when both have chosen; it arrives through OnPush.
			if turnSeq == seq and BattleUI.Active then
				waiting = true
				setMessage("Waiting for " .. (battle.Opponent or "your opponent") .. " to choose...")
			end
			return
		end
		afterTurn(resp)
	end

	runBtn.Activated:Connect(function()
		act({ Type = "Run" })
	end)
	superBtn.Activated:Connect(function()
		superBtn.Visible = false
		act({ Type = "Super" })
	end)
	continueBtn.Activated:Connect(function()
		banner.Visible = false
		root.Visible = false
		if ctx.OnEnd then
			ctx.OnEnd(finished)
		end
	end)

	-- Intro: white flash, monsters slide in from the sides, cards and controls follow.
	local function intro()
		FX.Flash(fxLayer, Color3.new(1, 1, 1), 1)
		local slides = {
			{ foeHolder, FOE_POS, UDim2.fromScale(0.5, 0) },
			{ foePlatform, foePlatform.Position, UDim2.fromScale(0.5, 0) },
			{ myHolder, MY_POS, UDim2.fromScale(-0.5, 0) },
			{ myPlatform, myPlatform.Position, UDim2.fromScale(-0.5, 0) },
			{ foeCard.Card, foeCard.Home, UDim2.fromScale(-0.45, 0) },
			{ myCard.Card, myCard.Home, UDim2.fromScale(0.45, 0) },
			{ bottom, bottomHome, UDim2.fromScale(0, 0.35) },
		}
		for _, s in slides do
			s[1].Position = s[2] + s[3]
		end
		for i, s in slides do
			task.delay(0.05 * i, function()
				tween(s[1], 0.45, { Position = s[2] }, Enum.EasingStyle.Back)
			end)
		end
	end

	-- VS splash before trainer and PvP battles: two halves slam in, a giant VS
	-- flashes, the trainer's own character waves from their side.
	local function vsIntro(view)
		local layer = UI.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 92, Parent = root })
		local function half(left: boolean, color: Color3, name: string, sub: string)
			local f = UI.new("Frame", {
				AnchorPoint = Vector2.new(if left then 0 else 1, 0),
				BackgroundColor3 = color,
				Position = UDim2.fromScale(if left then -0.6 else 1.6, 0),
				Size = UDim2.fromScale(0.56, 1),
				ZIndex = 92,
				Parent = layer,
			})
			UI.Gloss(f, color)
			UI.Stroke(f, 8)
			UI.Label(f, name, { Font = UI.TitleFont, Size = UDim2.new(0.8, 0, 0.14, 0), Position = UDim2.fromScale(0.1, 0.62), MaxTextSize = 80, ZIndex = 93 })
			UI.Label(f, sub, { Size = UDim2.new(0.8, 0, 0.07, 0), Position = UDim2.fromScale(0.1, 0.77), MaxTextSize = 34, ZIndex = 93 })
			tween(f, 0.35, { Position = UDim2.fromScale(if left then 0 else 1, 0) }, Enum.EasingStyle.Back)
			return f
		end
		local me = view.Team[1]
		local foeName = view.TrainerName or view.Opponent or "Foe"
		local left = half(true, Color3.fromRGB(60, 140, 255), "YOU", string.format("%d monster%s", #view.Team, if #view.Team == 1 then "" else "s"))
		local right = half(false, if view.Boss then Color3.fromRGB(170, 60, 230) else Color3.fromRGB(250, 80, 70), string.upper(foeName), if view.Boss then "BOSS BATTLE!" else string.format("%d monster%s", #view.Enemy, if #view.Enemy == 1 then "" else "s"))
		-- Your lead monster on the left.
		local lh = UI.new("Frame", { BackgroundTransparency = 1, Position = UDim2.fromScale(0.2, 0.12), Size = UDim2.fromScale(0.6, 0.5), ZIndex = 93, Parent = left })
		local lvp = UI.MonsterViewport(lh, me.SpeciesId, me.Genes, me.ActiveMutations, { Spin = 0.4, RarityTier = me.RarityTier, Yaw = 0.6 })
		if lvp then
			lvp.ZIndex = 93
		end
		-- The trainer's character on the right (cloned from the world), else their lead monster.
		local rh = UI.new("Frame", { BackgroundTransparency = 1, Position = UDim2.fromScale(0.2, 0.12), Size = UDim2.fromScale(0.6, 0.5), ZIndex = 93, Parent = right })
		local npc = view.TrainerId and workspace:FindFirstChild("Trainers") and workspace.Trainers:FindFirstChild("Trainer_" .. view.TrainerId)
		if npc then
			local vp = UI.new("ViewportFrame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 93, Parent = rh })
			local copy = npc:Clone()
			for _, d in copy:GetDescendants() do
				if d:IsA("Script") or d:IsA("LocalScript") or d:IsA("ProximityPrompt") then
					d:Destroy()
				end
			end
			copy:PivotTo(CFrame.new()) -- characters face -Z: toward the camera below
			copy.Parent = vp
			local cam = Instance.new("Camera")
			cam.FieldOfView = 30
			cam.CFrame = CFrame.lookAt(Vector3.new(0, 1.5, -11), Vector3.new(0, 0.8, 0))
			cam.Parent = vp
			vp.CurrentCamera = cam
		else
			local foe = view.Enemy[1]
			local rvp = UI.MonsterViewport(rh, foe.SpeciesId, foe.Genes, foe.ActiveMutations, { Spin = 0.4, RarityTier = foe.RarityTier })
			if rvp then
				rvp.ZIndex = 93
			end
		end
		task.wait(0.3)
		local vs = UI.Label(layer, "VS", { Font = UI.TitleFont, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.45), Size = UDim2.fromOffset(300, 220), TextColor3 = UI.Colors.Gold, MaxTextSize = 200, ZIndex = 95 })
		local s = UI.new("UIScale", { Scale = 3, Parent = vs })
		tween(s, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
		FX.Flash(layer, Color3.new(1, 1, 1), 0.9)
		task.spawn(FX.Shake, layer, 14, 0.3)
		UI.Play("Pop", 0.7, 0.9)
		task.wait(1.4)
		tween(left, 0.3, { Position = UDim2.fromScale(-0.7, 0) })
		tween(right, 0.3, { Position = UDim2.fromScale(1.7, 0) })
		tween(vs, 0.3, { TextTransparency = 1 })
		task.delay(0.35, function()
			layer:Destroy()
		end)
	end

	local function begin(view)
		battle = view
		BattleUI.Active = true
		finished = nil
		waiting = false
		banner.Visible = false
		root.Visible = true
		UI.SetButtonText(runBtn, if view.Kind == "PvP" then "Give up" else "Run")
		refreshSides()
		refreshControls()
		startTurnTimer()
		if view.Kind == "Trainer" or view.Kind == "PvP" then
			vsIntro(view)
		end
		intro()
		UI.Play("Pop", 0.9, 0.6)
		setMessage(view.Title .. (if view.Greeting then ("\n\"" .. view.Greeting .. "\"") else ""))
		task.delay(2, function()
			if battle == view and BattleUI.Active and not busy then
				setMessage("What will " .. battle.Team[battle.P].Name .. " do?")
			end
		end)
	end

	local api = {}
	function api.Start(kind: string, id: string)
		if BattleUI.Active or busy then
			return
		end
		busy = true
		local resp = ctx.R.StartBattle:InvokeServer(kind, id)
		busy = false
		if not resp or not resp.Ok then
			ctx.ShowError(resp and resp.Error, resp)
			return
		end
		begin(resp.Battle)
	end

	-- PvP messages from the server ("Battle" RemoteEvent).
	function api.OnPush(msg)
		if msg.Kind == "Start" then
			begin(msg.Battle)
		elseif msg.Kind == "OpponentReady" then
			if BattleUI.Active and not waiting and battle and battle.Kind == "PvP" then
				setMessage((battle.Opponent or "Your opponent") .. " is ready! What will " .. battle.Team[battle.P].Name .. " do?", true)
			end
		elseif msg.Kind == "Turn" then
			if battle and msg.Battle and msg.Battle.Id == battle.Id and BattleUI.Active then
				turnSeq += 1
				busy = true
				waiting = false
				task.spawn(afterTurn, msg)
			end
		end
	end
	return api
end

return BattleUI
