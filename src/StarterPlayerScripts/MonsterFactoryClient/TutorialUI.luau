-- Getting Started guide (steps in Shared/Tutorial), made for young players:
--   * a welcome popup the first time,
--   * a tracker card (top right) with one simple goal and a progress bar,
--   * a bouncing "TAP!" arrow over the button to press, or a sparkly trail on
--     the ground to the flower / wild monster to find,
--   * a "Great job!" cheer for each step and a reward popup at the end.
-- The guide can be hidden (saved setting) and reopened with the "Guide" button.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("MonsterFactory"):WaitForChild("Shared")
local Tutorial = require(Shared.Tutorial)
local UI = require(script.Parent.UIKit)

local TutorialUI = {}

local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"

local function popIn(frame: GuiObject)
	local s = frame:FindFirstChildOfClass("UIScale") or UI.new("UIScale", { Parent = frame })
	s.Scale = 0.4
	TweenService:Create(s, TweenInfo.new(0.35, Enum.EasingStyle.Back), { Scale = 1 }):Play()
end

-- ctx: { Screen, R, ShowError, Targets = { Chamber: GuiObject, HatchMenu: GuiObject }, IsBusy: () -> boolean }
function TutorialUI.Init(ctx)
	local player = Players.LocalPlayer
	local screen = ctx.Screen

	-- ===== Tracker card =====
	local card = UI.new("Frame", {
		Name = "GuideCard",
		AnchorPoint = Vector2.new(1, 0),
		BackgroundColor3 = UI.Colors.Panel,
		Position = UDim2.new(1, -12, 0, 140),
		Size = UDim2.fromOffset(320, 150),
		Visible = false,
		ZIndex = 20,
		Parent = screen,
	})
	UI.Corner(card, 16)
	UI.Stroke(card, 4)
	UI.Gloss(card, UI.Colors.Panel)
	local header = UI.new("Frame", { BackgroundColor3 = UI.Colors.Gold, Size = UDim2.new(1, 0, 0, 34), ZIndex = 21, Parent = card })
	UI.Corner(header, 14)
	UI.Stroke(header, 3)
	UI.Gloss(header, UI.Colors.Gold)
	local headerLabel = UI.Label(header, "GETTING STARTED", { Font = UI.TitleFont, Size = UDim2.new(1, -60, 1, -6), Position = UDim2.fromOffset(10, 3), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 22 })
	local hideBtn = UI.Button(header, "X", UI.Colors.Red, { Size = UDim2.fromOffset(30, 26), Position = UDim2.new(1, -36, 0, 4), ZIndex = 22 })
	local title = UI.Label(card, "", { Font = UI.TitleFont, Size = UDim2.new(1, -20, 0, 30), Position = UDim2.fromOffset(10, 40), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 21 })
	local text = UI.Label(card, "", {
		Size = UDim2.new(1, -20, 0, 44),
		Position = UDim2.fromOffset(10, 72),
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		MaxTextSize = 20,
		ZIndex = 21,
	})
	local bar = UI.Bar(card, UI.Colors.Green, { Size = UDim2.new(1, -20, 0, 14), Position = UDim2.new(0, 10, 1, -24), ZIndex = 21 })
	for _, d in bar.Frame:GetDescendants() do
		if d:IsA("GuiObject") then
			d.ZIndex = 22
		end
	end
	local barLabel = UI.Label(card, "", { Size = UDim2.new(0, 60, 0, 16), Position = UDim2.new(1, -70, 1, -42), TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 21 })

	-- Small button to bring the guide back after hiding it.
	local guideBtn = UI.Button(screen, "Guide", UI.Colors.Gold, {
		Name = "GuideButton",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 140),
		Size = UDim2.fromOffset(96, 40),
		Visible = false,
		ZIndex = 20,
	})

	-- ===== "TAP!" arrow (over UI buttons) =====
	local arrow = UI.new("Frame", { Name = "GuideArrow", BackgroundTransparency = 1, Size = UDim2.fromOffset(80, 64), Visible = false, ZIndex = 35, Parent = screen })
	local tip = UI.new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = UI.Colors.Gold, Position = UDim2.new(0.5, 0, 1, -14), Rotation = 45, Size = UDim2.fromOffset(26, 26), ZIndex = 35, Parent = arrow })
	UI.Stroke(tip, 3)
	local pill = UI.new("Frame", { BackgroundColor3 = UI.Colors.Gold, Size = UDim2.new(1, 0, 0, 36), ZIndex = 36, Parent = arrow })
	UI.Corner(pill, 12)
	UI.Stroke(pill, 3)
	UI.Gloss(pill, UI.Colors.Gold)
	UI.Label(pill, "TAP!", { Font = UI.TitleFont, Size = UDim2.new(1, -8, 1, -6), Position = UDim2.fromOffset(4, 3), ZIndex = 37 })

	-- ===== Sparkly trail (to world targets) =====
	local trailFolder = Instance.new("Folder")
	trailFolder.Name = "GuideTrail"
	trailFolder.Parent = workspace
	local targetAnchor = Instance.new("Part")
	targetAnchor.Name = "GuideTarget"
	targetAnchor.Anchored, targetAnchor.CanCollide, targetAnchor.CanQuery, targetAnchor.CanTouch = true, false, false, false
	targetAnchor.Transparency = 1
	targetAnchor.Size = Vector3.one
	targetAnchor.Parent = trailFolder
	local targetAttach = Instance.new("Attachment")
	targetAttach.Parent = targetAnchor
	local beam = Instance.new("Beam")
	beam.Attachment1 = targetAttach
	beam.Color = ColorSequence.new(Color3.fromRGB(255, 230, 90))
	beam.Texture = SPARKLE
	beam.TextureMode = Enum.TextureMode.Wrap
	beam.TextureLength = 3
	beam.TextureSpeed = 1.5
	beam.LightEmission = 1
	beam.Width0, beam.Width1 = 2.6, 2.6
	beam.FaceCamera = true
	beam.Transparency = NumberSequence.new(0.1)
	beam.Enabled = false
	beam.Parent = targetAnchor
	local here = Instance.new("BillboardGui")
	here.Size = UDim2.fromOffset(180, 64)
	here.StudsOffset = Vector3.new(0, 6, 0)
	here.AlwaysOnTop = true
	here.Enabled = false
	here.Parent = targetAnchor
	local hereLabel = UI.Label(here, "HERE!", { Font = UI.TitleFont, TextColor3 = UI.Colors.Gold })
	local myAttach: Attachment? = nil

	local function nearest(tag: string?, folderName: string?, filter: (BasePart) -> boolean): BasePart?
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not root then
			return nil
		end
		local list = {}
		if tag then
			list = CollectionService:GetTagged(tag)
		elseif folderName then
			local f = workspace:FindFirstChild(folderName)
			list = if f then f:GetDescendants() else {}
		end
		local best, bestD = nil, math.huge
		for _, inst in list do
			if inst:IsA("BasePart") and filter(inst) then
				local d = (inst.Position - root.Position).Magnitude
				if d < bestD then
					best, bestD = inst, d
				end
			end
		end
		return best
	end

	-- ===== Popups =====
	local function popup(titleText: string, lines: string, buttonText: string, color: Color3, onPress: () -> ())
		local p = UI.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = UI.Colors.Panel,
			Position = UDim2.fromScale(0.5, 0.45),
			Size = UDim2.fromOffset(520, 330),
			ZIndex = 50,
			Parent = screen,
		})
		UI.Corner(p, 22)
		UI.Stroke(p, 6)
		UI.Gloss(p, UI.Colors.Panel)
		UI.Label(p, titleText, { Font = UI.TitleFont, Size = UDim2.new(1, -30, 0, 56), Position = UDim2.fromOffset(15, 14), MaxTextSize = 48, ZIndex = 51 })
		UI.Label(p, lines, {
			Size = UDim2.new(1, -50, 0, 160),
			Position = UDim2.fromOffset(25, 80),
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			MaxTextSize = 26,
			ZIndex = 51,
		})
		local b = UI.Button(p, buttonText, color, { Size = UDim2.fromOffset(260, 64), Position = UDim2.new(0.5, -130, 1, -82), ZIndex = 51 })
		for _, d in b:GetDescendants() do
			if d:IsA("GuiObject") then
				d.ZIndex = 52
			end
		end
		popIn(p)
		UI.Play("Pop", 1.1, 0.7)
		b.Activated:Connect(function()
			p:Destroy()
			onPress()
		end)
		return p
	end

	-- ===== State =====
	local latest = nil
	local shownWelcome = false
	local lastStep: number? = nil
	local rewardShown = false
	local hidden = false

	local function hide(h: boolean)
		hidden = h
		ctx.R.SetSetting:InvokeServer("TutorialHidden", h)
	end
	hideBtn.Activated:Connect(function()
		hide(true)
	end)
	guideBtn.Activated:Connect(function()
		hide(false)
	end)

	local api = {}
	function api.Update(state)
		latest = state
		hidden = state.Settings and state.Settings.TutorialHidden == true
		local progress = Tutorial.FromState(state)
		local i = Tutorial.Current(progress)
		if i and lastStep and i > lastStep then
			UI.Toast("Great job! Next: " .. Tutorial.Steps[i].Title, UI.Colors.Green)
			UI.Play("Pop", 1.3, 0.7)
		end
		lastStep = i
		-- First visit: say hello.
		if not shownWelcome and i == 1 and not hidden then
			shownWelcome = true
			popup(
				"Welcome!",
				"- Hatch eggs to make cute monsters.\n- Pick glowing flowers and battle wild monsters.\n- Collect them all and become the best trainer!\n\nThe yellow guide shows you what to do next.",
				"LET'S GO!",
				UI.Colors.Green,
				function() end
			)
		end
		-- All done: the reward.
		if not i and not state.TutorialRewarded and not rewardShown then
			rewardShown = true
			popup(
				"You did it!",
				"You finished the Getting Started guide!\n\nHere is a present to help you on your adventure.",
				"CLAIM " .. Tutorial.Reward .. " COINS!",
				UI.Colors.Gold,
				function()
					local r = ctx.R.ClaimTutorialReward:InvokeServer()
					if r and r.Ok then
						UI.Toast("+" .. r.Coins .. " coins! Have fun!", UI.Colors.Gold)
					else
						ctx.ShowError(r and r.Error)
					end
				end
			)
		end
		if not i then
			card.Visible = false
			guideBtn.Visible = false
			return
		end
		local step = Tutorial.Steps[i]
		headerLabel.Text = string.format("GETTING STARTED  %d/%d", i, #Tutorial.Steps)
		title.Text = step.Title
		text.Text = step.Text
		local _, cur, goal = Tutorial.StepStatus(step, progress)
		if cur and goal then
			bar.Set(cur / goal, true)
			barLabel.Text = string.format("%d/%d", cur, goal)
		else
			bar.Set((i - 1) / #Tutorial.Steps, true)
			barLabel.Text = ""
		end
		card.Visible = not hidden
		guideBtn.Visible = hidden
	end

	-- Pointers follow the current step every frame.
	RunService.RenderStepped:Connect(function()
		local i = latest and Tutorial.Current(Tutorial.FromState(latest))
		local busy = ctx.IsBusy() or hidden
		local step = i and Tutorial.Steps[i]
		-- UI arrow.
		local target = step and not busy and ctx.Targets[step.Pointer]
		if target and target.Visible and target.AbsoluteSize.X > 0 then
			local bob = math.abs(math.sin(os.clock() * 4)) * 10
			local at = target.AbsolutePosition - screen.AbsolutePosition
			local size = target.AbsoluteSize
			if size.X > 200 then
				-- Wide button (HATCH!): point at it from the left, so the text above stays readable.
				tip.Position = UDim2.new(1, -8, 0, 18)
				arrow.Position = UDim2.fromOffset(at.X - 96 - bob, at.Y + size.Y / 2 - 18)
			else
				tip.Position = UDim2.new(0.5, 0, 1, -14)
				arrow.Position = UDim2.fromOffset(at.X + size.X / 2 - 40, at.Y - 70 - bob)
			end
			arrow.Visible = true
		else
			arrow.Visible = false
		end
		-- World trail.
		local spot: BasePart? = nil
		if step and not busy then
			if step.Pointer == "Gather" then
				spot = nearest(nil, "GatherNodes", function(p)
					return p:GetAttribute("NodeType") ~= nil and (p:GetAttribute("NodeId") or ""):find("^VerdantMeadows") ~= nil
				end)
			elseif step.Pointer == "Wild" then
				spot = nearest("WildSpot", nil, function(p)
					local untilT = p:GetAttribute("HiddenUntil")
					return (latest.UnlockedBiomes[p:GetAttribute("Biome")] == true) and not (type(untilT) == "number" and workspace:GetServerTimeNow() < untilT)
				end)
			end
		end
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if spot and root then
			if not myAttach or myAttach.Parent ~= root then
				myAttach = Instance.new("Attachment")
				myAttach.Name = "GuideAttach"
				myAttach.Position = Vector3.new(0, -2.5, 0)
				myAttach.Parent = root
			end
			beam.Attachment0 = myAttach
			targetAnchor.Position = spot.Position + Vector3.new(0, 0.5, 0)
			beam.Enabled = (spot.Position - root.Position).Magnitude > 10
			here.Enabled = true
			hereLabel.Text = if step.Pointer == "Gather" then "FLOWER!" else "BATTLE!"
		else
			beam.Enabled = false
			here.Enabled = false
		end
	end)
	return api
end

return TutorialUI
