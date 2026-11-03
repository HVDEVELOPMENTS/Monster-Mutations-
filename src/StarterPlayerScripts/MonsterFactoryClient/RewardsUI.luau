-- The "feel good" layer: daily reward calendar, daily quests, flying coins and
-- the level-up celebration (rules in Shared/Rewards, claims on the server).
--   * Daily calendar pops up once per session when today's gift is ready.
--   * Quests panel (menu button with a red badge when something is claimable);
--     a "Quest complete!" cheer the moment a goal is reached.
--   * Coins fly into the coin counter for every reward.
--   * LEVEL UP! screen with confetti and what the new level unlocked.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("MonsterFactory"):WaitForChild("Shared")
local Rewards = require(Shared.Rewards)
local Config = require(Shared.Config)
local Species = require(Shared.Species)
local Materials = require(Shared.Materials)
local UI = require(script.Parent.UIKit)
local FX = require(script.Parent.BattleFX)

local RewardsUI = {}

local function tween(inst: Instance, t: number, props: { [string]: any }, style: Enum.EasingStyle?)
	local tw = TweenService:Create(inst, TweenInfo.new(t, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props)
	tw:Play()
	return tw
end

-- ctx: { Screen, R, ShowError, CoinTarget: GuiObject, QuestsButton: GuiButton,
--        QuestsBadge: Frame, QuestsBadgeLabel: TextLabel, DailyButton: GuiButton,
--        QuestsPanel: panel, IsBusy: () -> boolean }
function RewardsUI.Init(ctx)
	local screen = ctx.Screen
	local state = nil

	-- ===== Flying coins =====
	local function flyCoins(from: Vector2?, count: number)
		local target = ctx.CoinTarget
		local to = target.AbsolutePosition + target.AbsoluteSize / 2 - screen.AbsolutePosition
		local start = from or (screen.AbsoluteSize / 2)
		for i = 1, math.clamp(count, 4, 18) do
			local c = UI.new("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundColor3 = UI.Colors.Gold,
				Position = UDim2.fromOffset(start.X, start.Y),
				Size = UDim2.fromOffset(26, 26),
				ZIndex = 90,
				Parent = screen,
			})
			UI.Corner(c, 13)
			UI.Stroke(c, 3)
			UI.Gloss(c, UI.Colors.Gold)
			local spread = Vector2.new(math.random(-120, 120), math.random(-90, 40))
			task.delay(i * 0.035, function()
				tween(c, 0.25, { Position = UDim2.fromOffset(start.X + spread.X, start.Y + spread.Y) }, Enum.EasingStyle.Back).Completed:Wait()
				tween(c, 0.45, { Position = UDim2.fromOffset(to.X, to.Y), Size = UDim2.fromOffset(14, 14) }, Enum.EasingStyle.Quad).Completed:Wait()
				c:Destroy()
				UI.Play("Tick", 1.4 + math.random() * 0.4, 0.25)
			end)
		end
	end
	RewardsUI.FlyCoins = flyCoins

	-- ===== Modal helper =====
	local function modal(title: string, color: Color3, size: Vector2)
		local back = UI.new("Frame", { BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.45, Size = UDim2.fromScale(1, 1), ZIndex = 55, Active = true, Parent = screen })
		local f = UI.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = UI.Colors.Panel,
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(size.X, size.Y),
			ZIndex = 56,
			Parent = back,
		})
		UI.Corner(f, 22)
		UI.Stroke(f, 6)
		UI.Gloss(f, UI.Colors.Panel)
		local header = UI.new("Frame", { BackgroundColor3 = color, Size = UDim2.new(1, 0, 0, 70), ZIndex = 57, Parent = f })
		UI.Corner(header, 18)
		UI.Stroke(header, 4)
		UI.Gloss(header, color)
		UI.Label(header, title, { Font = UI.TitleFont, Size = UDim2.new(1, -30, 1, -12), Position = UDim2.fromOffset(15, 6), MaxTextSize = 50, ZIndex = 58 })
		local s = UI.new("UIScale", { Scale = 0.4, Parent = f })
		tween(s, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
		UI.Play("Pop", 1.1, 0.7)
		return back, f
	end

	-- ===== Daily calendar =====
	local dailyShown = false
	local dailyOpen = false
	local function giftText(g)
		local parts = { UI.FormatNumber(g.Coins) .. " coins" }
		for id, n in g.Items or {} do
			local m = Materials.ById[id]
			table.insert(parts, n .. " " .. (m and m.DisplayName or id))
		end
		return table.concat(parts, "\n+ ")
	end
	local function openDaily()
		if dailyOpen or not state or not state.Rewards then
			return
		end
		dailyOpen = true
		local daily = state.Rewards.Daily
		local back, f = modal("DAILY REWARDS", UI.Colors.Gold, Vector2.new(900, 430))
		local row = UI.new("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(20, 90), Size = UDim2.new(1, -40, 0, 200), ZIndex = 57, Parent = f })
		UI.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 10), HorizontalAlignment = Enum.HorizontalAlignment.Center, Parent = row })
		local todayTile
		for i, g in Rewards.DailyGifts do
			local got = i < daily.Day or (i == daily.Day and not daily.CanClaim)
			local today = i == daily.Day and daily.CanClaim
			local col = if today then UI.Colors.Green elseif got then UI.Colors.Gold elseif i == 7 then UI.Colors.Purple else UI.Colors.Card
			local tile = UI.new("Frame", { BackgroundColor3 = col, Size = UDim2.fromOffset(110, if i == 7 then 200 else 180), ZIndex = 57, Parent = row })
			UI.Corner(tile, 14)
			UI.Stroke(tile, if today then 5 else 3)
			UI.Gloss(tile, col)
			UI.Label(tile, "DAY " .. i, { Font = UI.TitleFont, Size = UDim2.new(1, -10, 0, 34), Position = UDim2.fromOffset(5, 8), ZIndex = 58 })
			UI.Label(tile, giftText(g), { Size = UDim2.new(1, -12, 0, 70), Position = UDim2.fromOffset(6, 52), TextWrapped = true, MaxTextSize = 20, ZIndex = 58 })
			UI.Label(tile, if got then "GOT IT!" elseif today then "TODAY!" elseif i == 7 then "JACKPOT!" else "", {
				Font = UI.TitleFont,
				Size = UDim2.new(1, -10, 0, 28),
				Position = UDim2.new(0, 5, 1, -38),
				TextColor3 = if today then Color3.new(1, 1, 1) else UI.Colors.Gold,
				ZIndex = 58,
			})
			if today then
				todayTile = tile
			end
		end
		if todayTile then
			task.spawn(function()
				local sc = UI.new("UIScale", { Parent = todayTile })
				while todayTile.Parent do
					sc.Scale = 1 + math.abs(math.sin(os.clock() * 3)) * 0.06
					task.wait(0.03)
				end
			end)
		end
		local btn = UI.Button(f, if daily.CanClaim then string.format("CLAIM DAY %d!", daily.Day) else "Come back tomorrow!", if daily.CanClaim then UI.Colors.Green else UI.Colors.Blue, {
			Size = UDim2.fromOffset(360, 70),
			Position = UDim2.new(0.5, -180, 1, -96),
			ZIndex = 58,
		})
		for _, d in btn:GetDescendants() do
			if d:IsA("GuiObject") then
				d.ZIndex = 59
			end
		end
		local close = UI.Button(f, "X", UI.Colors.Red, { Size = UDim2.fromOffset(50, 50), Position = UDim2.new(1, -62, 0, 10), ZIndex = 59 })
		local function done()
			dailyOpen = false
			back:Destroy()
		end
		close.Activated:Connect(done)
		btn.Activated:Connect(function()
			if not daily.CanClaim then
				done()
				return
			end
			local from = todayTile and (todayTile.AbsolutePosition + todayTile.AbsoluteSize / 2 - screen.AbsolutePosition)
			local r = ctx.R.ClaimDaily:InvokeServer()
			if r and r.Ok then
				flyCoins(from, 14)
				task.spawn(FX.Confetti, screen)
				UI.Toast(string.format("Day %d gift: +%s coins!", r.Day, UI.FormatNumber(r.Coins)), UI.Colors.Gold)
				task.delay(0.6, done)
			else
				ctx.ShowError(r and r.Error)
				done()
			end
		end)
	end
	ctx.DailyButton.Activated:Connect(openDaily)

	-- ===== Quests panel =====
	local panel = ctx.QuestsPanel
	local list = UI.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = panel.Content })
	UI.new("UIListLayout", { Padding = UDim.new(0, 12), SortOrder = Enum.SortOrder.LayoutOrder, Parent = list })
	local resetLabel = nil
	local function refreshQuests()
		for _, c in list:GetChildren() do
			if c:IsA("GuiObject") then
				c:Destroy()
			end
		end
		if not state or not state.Rewards then
			return
		end
		resetLabel = UI.Label(list, "", { LayoutOrder = 0, Size = UDim2.new(1, 0, 0, 26), TextColor3 = UI.Colors.Muted })
		for i, q in state.Rewards.Quests do
			local done = q.Progress >= q.Goal
			local col = if q.Claimed then UI.Colors.Gold elseif done then UI.Colors.Green else UI.Colors.Card
			local card = UI.new("Frame", { BackgroundColor3 = col, LayoutOrder = i, Size = UDim2.new(1, 0, 0, 110), Parent = list })
			UI.Corner(card, 16)
			UI.Stroke(card, 4)
			UI.Gloss(card, col)
			UI.Label(card, q.Text, { Font = UI.TitleFont, Size = UDim2.new(0.62, 0, 0, 36), Position = UDim2.fromOffset(16, 10), TextXAlignment = Enum.TextXAlignment.Left })
			local bar = UI.Bar(card, UI.Colors.Green, { Size = UDim2.new(0.6, -16, 0, 20), Position = UDim2.fromOffset(16, 56) })
			bar.Set(q.Progress / q.Goal)
			UI.Label(card, string.format("%d / %d", q.Progress, q.Goal), { Size = UDim2.fromOffset(120, 22), Position = UDim2.fromOffset(16, 80), TextXAlignment = Enum.TextXAlignment.Left })
			UI.Label(card, string.format("+%s coins  +%d XP", UI.FormatNumber(q.Coins), q.XP), { Size = UDim2.new(0.35, 0, 0, 30), Position = UDim2.new(0.62, 0, 0, 10), TextColor3 = UI.Colors.Gold })
			local b = UI.Button(card, if q.Claimed then "CLAIMED!" elseif done then "CLAIM!" else "Keep going!", if done and not q.Claimed then UI.Colors.Green else UI.Colors.Blue, {
				Size = UDim2.new(0.32, 0, 0, 52),
				Position = UDim2.new(0.66, 0, 0, 48),
			})
			UI.SetDisabled(b, q.Claimed or not done)
			b.Activated:Connect(function()
				if UI.IsDisabled(b) then
					return
				end
				local from = b.AbsolutePosition + b.AbsoluteSize / 2 - screen.AbsolutePosition
				local r = ctx.R.ClaimQuest:InvokeServer(q.Id)
				if r and r.Ok then
					flyCoins(from, 10)
					UI.Toast(string.format("Quest reward: +%s coins!", UI.FormatNumber(r.Coins)), UI.Colors.Gold)
				else
					ctx.ShowError(r and r.Error)
				end
			end)
		end
	end
	panel.OnOpen = refreshQuests
	ctx.QuestsButton.Activated:Connect(function()
		ctx.OpenPanel(panel)
	end)
	-- Countdown to new quests.
	task.spawn(function()
		while true do
			if resetLabel and resetLabel.Parent and state and state.Rewards then
				local left = math.max(0, state.Rewards.Daily.NextDayAt - workspace:GetServerTimeNow())
				resetLabel.Text = string.format("New quests in %d:%02d:%02d", left // 3600, (left % 3600) // 60, left % 60)
			end
			task.wait(1)
		end
	end)

	-- ===== Level up =====
	local function levelUp(level: number)
		local unlocks = {}
		for i, l in Config.EggSlotLevels do
			if l == level and i > 1 then
				table.insert(unlocks, string.format("You can hatch %d eggs at once!", i))
			end
		end
		for _, sp in Species.List do
			local c = Config.Species[sp.Id]
			if c and c.UnlockLevel == level then
				table.insert(unlocks, "New monster: " .. sp.DisplayName .. "!")
			end
		end
		local back, f = modal("LEVEL UP!", UI.Colors.Purple, Vector2.new(560, 360))
		UI.Label(f, "LEVEL " .. level, { Font = UI.TitleFont, Size = UDim2.new(1, -40, 0, 90), Position = UDim2.fromOffset(20, 84), TextColor3 = UI.Colors.Gold, MaxTextSize = 80, ZIndex = 58 })
		UI.Label(f, if #unlocks > 0 then table.concat(unlocks, "\n") else "Your monsters are getting stronger!", {
			Size = UDim2.new(1, -40, 0, 80),
			Position = UDim2.fromOffset(20, 176),
			TextWrapped = true,
			MaxTextSize = 26,
			ZIndex = 58,
		})
		local ok = UI.Button(f, "AWESOME!", UI.Colors.Green, { Size = UDim2.fromOffset(260, 64), Position = UDim2.new(0.5, -130, 1, -84), ZIndex = 58 })
		for _, d in ok:GetDescendants() do
			if d:IsA("GuiObject") then
				d.ZIndex = 59
			end
		end
		ok.Activated:Connect(function()
			back:Destroy()
		end)
		task.spawn(FX.Confetti, screen)
		UI.Play("Pop", 0.8, 0.8)
	end

	-- ===== State =====
	local lastQuestProgress: { [string]: number } = {}
	local lastLevel: number? = nil
	local lastCoins: number? = nil
	local api = {}
	function api.Update(s)
		state = s
		local r = s.Rewards
		if not r then
			return
		end
		-- Quest cheers and the menu badge.
		local claimable = 0
		for _, q in r.Quests do
			local before = lastQuestProgress[q.Id]
			if before and before < q.Goal and q.Progress >= q.Goal and not q.Claimed then
				UI.Toast("Quest complete: " .. q.Text .. "! Open Quests to claim.", UI.Colors.Green)
				UI.Play("Pop", 1.4, 0.7)
			end
			lastQuestProgress[q.Id] = q.Progress
			if q.Progress >= q.Goal and not q.Claimed then
				claimable += 1
			end
		end
		ctx.QuestsBadge.Visible = claimable > 0
		ctx.QuestsBadgeLabel.Text = tostring(claimable)
		if panel.IsOpen then
			refreshQuests()
		end
		-- Level up!
		if lastLevel and s.Level > lastLevel then
			task.delay(0.5, function()
				while ctx.IsBusy() do
					task.wait(0.5)
				end
				levelUp(s.Level)
			end)
		end
		lastLevel = s.Level
		-- Big coin gains fly into the counter.
		if lastCoins and s.Coins - lastCoins >= 50 and not ctx.IsBusy() then
			flyCoins(nil, math.floor((s.Coins - lastCoins) / 25))
		end
		lastCoins = s.Coins
		-- The calendar greets you once per session when a gift is waiting.
		if not dailyShown and r.Daily.CanClaim then
			dailyShown = true
			task.spawn(function()
				task.wait(2)
				while ctx.IsBusy() or ctx.WelcomeOpen() do
					task.wait(1)
				end
				openDaily()
			end)
		end
	end
	return api
end

return RewardsUI
