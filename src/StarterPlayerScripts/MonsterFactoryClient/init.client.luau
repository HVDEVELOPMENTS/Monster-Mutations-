-- Monster Factory client: HUD, incubator, monsters, collection index, shop and reveal.
-- The client only displays state and sends selections; the server decides outcomes.

local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local MF = ReplicatedStorage:WaitForChild("MonsterFactory")
local Shared = MF:WaitForChild("Shared")
local Remotes = MF:WaitForChild("Remotes")

local Rarity = require(Shared.Rarity)
local Species = require(Shared.Species)
local Mutations = require(Shared.Mutations)
local Materials = require(Shared.Materials)
local Biomes = require(Shared.Biomes)
local Categories = require(Shared.Categories)
local Config = require(Shared.Config)
local UI = require(script.UIKit)
local Reveal = require(script.Reveal)
local FusionUI = require(script.FusionUI)
local BattleUI = require(script.BattleUI)
local TutorialUI = require(script.TutorialUI)
local RewardsUI = require(script.RewardsUI)

local function rf(name: string): RemoteFunction
	return Remotes:WaitForChild(name) :: RemoteFunction
end
local R = {
	GetState = rf("GetState"),
	GetOdds = rf("GetOdds"),
	StartIncubation = rf("StartIncubation"),
	ClaimIncubation = rf("ClaimIncubation"),
	SellMonster = rf("SellMonster"),
	SellBulk = rf("SellBulk"),
	ToggleLock = rf("ToggleLock"),
	BuyCatalyst = rf("BuyCatalyst"),
	MarkSeen = rf("MarkSeen"),
	SetSetting = rf("SetSetting"),
	UnlockBiome = rf("UnlockBiome"),
	EquipMonster = rf("EquipMonster"),
	BuyUpgrade = rf("BuyUpgrade"),
	BuyResearch = rf("BuyResearch"),
	TeleportToBiome = rf("TeleportToBiome"),
	FuseMonsters = rf("FuseMonsters"),
	StartBattle = rf("StartBattle"),
	BattleAction = rf("BattleAction"),
	ChallengePlayer = rf("ChallengePlayer"),
	RespondChallenge = rf("RespondChallenge"),
	ClaimTutorialReward = rf("ClaimTutorialReward"),
	ClaimDaily = rf("ClaimDaily"),
	ClaimQuest = rf("ClaimQuest"),
}
local NotifyEvent = Remotes:WaitForChild("Notify") :: RemoteEvent
local StateChanged = Remotes:WaitForChild("StateChanged") :: RemoteEvent
local CoinsChanged = Remotes:WaitForChild("CoinsChanged") :: RemoteEvent

local ERRORS = {
	NotEnoughCoins = "Not enough coins!",
	ChamberBusy = "All your egg spots are busy! Level up to hatch more at once.",
	MissingCatalyst = "You don't have that catalyst.",
	SpeciesLocked = "Reach a higher level to unlock this species.",
	BiomeLocked = "That biome is locked.",
	NotReady = "Not ready yet!",
	Locked = "This monster is locked. Unlock it to sell.",
	RateLimited = "Slow down a little!",
	StackFull = "You can't carry more of that.",
	MonsterStorageFull = "Monster storage is full. Sell some monsters first.",
	NotLoaded = "Still loading your data...",
	ServerError = "Something went wrong. Please try again.",
	SpeciesBiomeLocked = "Unlock that species' biome first.",
	RequirementsNotMet = "You don't meet the unlock requirements yet.",
	BadEvent = "The biome event just changed - try again.",
	MaxLevel = "Already at max level.",
	NotEnoughResearch = "Not enough Research Points.",
	ResearchLocked = "Research the previous node first.",
	TooFar = "Move closer to gather.",
	PetSlotsFull = "All pet slots are full. Unequip one first (or get a Companion Harness).",
	FuseSameSpecies = "Pick two DIFFERENT kinds of monster!",
	FuseDifferentBiome = "Both monsters must come from the same place!",
	NoMonsters = "Hatch a monster first, then come back to battle!",
	WildGone = "That monster ran away. It will come back soon!",
	TrainerResting = "This trainer is resting. Come back a bit later!",
	NoBattle = "That battle is over.",
	AlreadyBattling = "Finish your battle first!",
	PlayerBusy = "That player is busy right now. Try again soon!",
	PlayerHasNoMonsters = "That player has no monsters yet!",
	ChallengeGone = "That challenge is over.",
	AlreadyChose = "You already picked a move!",
	NotFinished = "Finish all the steps first!",
	AlreadyClaimed = "You already got this reward.",
}
local function showError(code: string?)
	UI.Toast(ERRORS[code or ""] or ("Error: " .. tostring(code)), UI.Colors.Red)
end

local state = nil

local function isPet(monsterId: string): boolean
	return state ~= nil and table.find(state.Equipped, monsterId) ~= nil
end

-- First egg that has finished hatching, if any.
local function readyEgg()
	if not state then
		return nil
	end
	local now = workspace:GetServerTimeNow()
	for _, inc in state.Incubations do
		if now >= inc.EndsAt then
			return inc
		end
	end
	return nil
end

local function freeEggSlots(): number
	return if state then state.EggSlots - #state.Incubations else 0
end

-- Equip a monster as a follower (on = false unequips it). Used by cards, Index and reveal.
local function equipMonster(monsterId: string, displayName: string?, on: boolean?)
	local r = R.EquipMonster:InvokeServer(monsterId, on ~= false)
	if r and r.Ok then
		local name = displayName or "Your monster"
		UI.Toast(if on == false then (name .. " stopped following you") else (name .. " is following you!"), UI.Colors.Purple)
		UI.Play("Pop", 1.1, 0.5)
	else
		showError(r and r.Error)
	end
end
local Events = require(Shared.Events)
local HybridRecipes = require(Shared.HybridRecipes)
local Progression = require(Shared.Progression)
local WorldLayout = require(Shared.WorldLayout)
-- Biome currently selected in the incubator (the server re-validates access).
local BIOME = "VerdantMeadows"

-- Screen -----------------------------------------------------------------
local screen = UI.new("ScreenGui", {
	Name = "MonsterFactoryUI",
	ResetOnSpawn = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	Parent = player:WaitForChild("PlayerGui"),
})
UI.InitToasts(screen)

-- HUD ------------------------------------------------------------------
local hud = UI.new("Frame", {
	Name = "Hud",
	BackgroundTransparency = 1,
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 8),
	Size = UDim2.fromOffset(560, 64),
	Parent = screen,
})
UI.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(0, 12), SortOrder = Enum.SortOrder.LayoutOrder, Parent = hud })

local coinPill = UI.new("Frame", { Name = "Coins", LayoutOrder = 1, BackgroundColor3 = UI.Colors.Gold, Size = UDim2.fromOffset(240, 60), Parent = hud })
UI.Corner(coinPill, 16)
UI.Stroke(coinPill, 3)
UI.Gradient(coinPill, Color3.fromRGB(255, 230, 120), Color3.fromRGB(230, 150, 30))
local coinLabel = UI.Label(coinPill, "0", { Size = UDim2.new(1, -20, 0, 36), Position = UDim2.fromOffset(10, 2) })
local incomeLabel = UI.Label(coinPill, "+0/s", { Size = UDim2.new(1, -20, 0, 18), Position = UDim2.fromOffset(10, 38), TextColor3 = Color3.fromRGB(255, 255, 220) })
local coinScale = UI.new("UIScale", { Parent = coinPill })

local levelPill = UI.new("Frame", { Name = "Level", LayoutOrder = 2, BackgroundColor3 = UI.Colors.Purple, Size = UDim2.fromOffset(200, 60), Parent = hud })
UI.Corner(levelPill, 16)
UI.Stroke(levelPill, 3)
UI.Gradient(levelPill, Color3.fromRGB(190, 140, 255), Color3.fromRGB(110, 60, 200))
local levelLabel = UI.Label(levelPill, "Level 1", { Size = UDim2.new(1, -20, 0, 30), Position = UDim2.fromOffset(10, 4) })
local xpBar = UI.Bar(levelPill, UI.Colors.Green, { Size = UDim2.new(1, -24, 0, 14), Position = UDim2.fromOffset(12, 38) })

local savePill = UI.new("Frame", { Name = "Save", LayoutOrder = 3, BackgroundColor3 = UI.Colors.Card, Size = UDim2.fromOffset(100, 60), Parent = hud })
UI.Corner(savePill, 16)
UI.Stroke(savePill, 3)
local saveLabel = UI.Label(savePill, "...", { Size = UDim2.new(1, -12, 1, -12), Position = UDim2.fromOffset(6, 6) })
-- Badges from boss trainers (one per biome).
local badgePill = UI.new("Frame", { Name = "Badges", LayoutOrder = 4, BackgroundColor3 = UI.Colors.Purple, Size = UDim2.fromOffset(120, 60), Parent = hud })
UI.Corner(badgePill, 16)
UI.Stroke(badgePill, 3)
UI.Gloss(badgePill, UI.Colors.Purple)
local badgeLabel = UI.Label(badgePill, "BADGES\n0/6", { Size = UDim2.new(1, -12, 1, -12), Position = UDim2.fromOffset(6, 6) })

-- Biome event banner (schedule is public and shared with the server).
local eventBanner = UI.new("Frame", {
	Name = "EventBanner",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 80),
	Size = UDim2.fromOffset(460, 34),
	BackgroundColor3 = UI.Colors.Card,
	Parent = screen,
})
UI.Corner(eventBanner, 12)
UI.Stroke(eventBanner, 3)
local eventLabel = UI.Label(eventBanner, "", { Size = UDim2.new(1, -16, 1, -8), Position = UDim2.fromOffset(8, 4) })

-- Side menu --------------------------------------------------------------
local menu = UI.new("Frame", {
	Name = "Menu",
	BackgroundTransparency = 1,
	AnchorPoint = Vector2.new(0, 0.5),
	Position = UDim2.new(0, 12, 0.5, 0),
	Size = UDim2.fromOffset(110, 500),
	Parent = screen,
})
UI.new("UIListLayout", { Padding = UDim.new(0, 10), VerticalAlignment = Enum.VerticalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder, Parent = menu })
local menuCount = 0
local function menuButton(text: string, color: Color3)
	menuCount += 1
	local b = UI.Button(menu, text, color, { Name = text, LayoutOrder = menuCount, Size = UDim2.fromOffset(104, 62) })
	local badge = UI.new("Frame", { BackgroundColor3 = UI.Colors.Red, Size = UDim2.fromOffset(34, 26), Position = UDim2.new(1, -24, 0, -10), Visible = false, ZIndex = 3, Parent = b })
	UI.Corner(badge, 13)
	UI.Stroke(badge, 2)
	local badgeLabel = UI.Label(badge, "!", { ZIndex = 4 })
	return b, badge, badgeLabel
end
local incubateBtn = menuButton("Hatch", UI.Colors.Green)
local monstersBtn = menuButton("Monsters", UI.Colors.Blue)
local indexBtn, indexBadge, indexBadgeLabel = menuButton("Collect", UI.Colors.Purple)
local shopBtn = menuButton("Shop", UI.Colors.Orange)
local labBtn = menuButton("Upgrade", UI.Colors.Blue)
local teleportBtn = menuButton("Travel", UI.Colors.Gold)
local questsBtn, questsBadge, questsBadgeLabel = menuButton("Quests", UI.Colors.Green)
local dailyBtn = menuButton("Daily", UI.Colors.Orange)

-- Chamber widget (bottom) ------------------------------------------------
local chamber = UI.new("Frame", {
	Name = "Chamber",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -16),
	Size = UDim2.fromOffset(420, 132),
	BackgroundColor3 = UI.Colors.Panel,
	Parent = screen,
})
UI.Corner(chamber, 18)
UI.Stroke(chamber, 4)
local chamberTitle = UI.Label(chamber, "Make a new monster!", { Size = UDim2.new(1, -132, 0, 28), Position = UDim2.fromOffset(12, 8) })
local chamberBar = UI.Bar(chamber, UI.Colors.Green, { Size = UDim2.new(1, -24, 0, 16), Position = UDim2.fromOffset(12, 40) })
local chamberBtn = UI.Button(chamber, "HATCH!", UI.Colors.Green, { Name = "ChamberButton", Size = UDim2.new(1, -24, 0, 40), Position = UDim2.fromOffset(12, 62) })
local chamberBtnScale = chamberBtn:FindFirstChildOfClass("UIScale") :: UIScale
local pityLabel = UI.Label(chamber, "", { Size = UDim2.new(1, -24, 0, 18), Position = UDim2.fromOffset(12, 108), TextColor3 = UI.Colors.Muted })

-- Panels -----------------------------------------------------------------
local incubatorPanel = UI.Panel(screen, "Hatch a Monster - Verdant Meadows", UDim2.new(0.86, 0, 0.8, 0), UI.Colors.Green)
local monstersPanel = UI.Panel(screen, "My Monsters", UDim2.new(0.86, 0, 0.8, 0), UI.Colors.Blue)
local indexPanel = UI.Panel(screen, "My Collection", UDim2.new(0.86, 0, 0.8, 0), UI.Colors.Purple)
local shopPanel = UI.Panel(screen, "Shop", UDim2.new(0.6, 0, 0.7, 0), UI.Colors.Orange)
local labPanel = UI.Panel(screen, "Upgrades", UDim2.new(0.86, 0, 0.8, 0), UI.Colors.Blue)
local teleportPanel = UI.Panel(screen, "Teleport", UDim2.new(0.4, 0, 0.6, 0), UI.Colors.Gold)
local fusionPanel = UI.Panel(screen, "Monster Fusion", UDim2.new(0.86, 0, 0.8, 0), UI.Colors.Purple)
local questsPanel = UI.Panel(screen, "Daily Quests", UDim2.new(0.6, 0, 0.62, 0), UI.Colors.Green)
local allPanels = { incubatorPanel, monstersPanel, indexPanel, shopPanel, labPanel, teleportPanel, fusionPanel, questsPanel }
local function openOnly(panel)
	for _, p in allPanels do
		if p ~= panel then
			p.Close()
		end
	end
	if panel.IsOpen then
		panel.Close()
	else
		panel.Open()
	end
end

local function sectionTitle(parent: Instance, text: string, y: number, width: UDim?)
	return UI.Label(parent, text, {
		Size = UDim2.new(width or UDim.new(1, 0), UDim.new(0, 26)),
		Position = UDim2.fromOffset(0, y),
		TextXAlignment = Enum.TextXAlignment.Left,
	})
end

local function scrolling(parent: Instance, props)
	local s = UI.new("ScrollingFrame", {
		BackgroundColor3 = UI.Colors.PanelDark,
		BorderSizePixel = 0,
		ScrollBarThickness = 8,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		Parent = parent,
	})
	UI.Corner(s, 12)
	UI.Padding(s, 8)
	for k, v in props do
		(s :: any)[k] = v
	end
	return s
end

local function clearChildren(inst: Instance, keepClass: { string }?)
	for _, c in inst:GetChildren() do
		if not (keepClass and table.find(keepClass, c.ClassName)) then
			c:Destroy()
		end
	end
end
local KEEP_LAYOUT = { "UIGridLayout", "UIListLayout", "UIPadding", "UICorner" }

-- ===== Incubator =====
local selection = { SpeciesId = "Mossling", Catalysts = {} :: { [string]: boolean } }
local lastSelection = nil
local incContent = incubatorPanel.Content
local leftCol = UI.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(0.57, 0, 1, 0), Parent = incContent })
local rightCol = UI.new("Frame", { BackgroundTransparency = 1, Position = UDim2.fromScale(0.6, 0), Size = UDim2.new(0.4, 0, 1, 0), Parent = incContent })

-- Biome tabs.
local biomeTabs = {}
for i, b in Biomes.List do
	local tab = UI.Button(leftCol, b.DisplayName, b.Theme.Accent, {
		Name = "Biome_" .. b.Id,
		Size = UDim2.new(1 / #Biomes.List, -5, 0, 40),
		Position = UDim2.new((i - 1) / #Biomes.List, (i - 1) * 5 / #Biomes.List, 0, 0),
	})
	biomeTabs[b.Id] = tab
end

local Y0 = 50
sectionTitle(leftCol, "1. Choose a species (any unlocked species works in any biome)", Y0)
local speciesRow = UI.new("ScrollingFrame", {
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	Position = UDim2.fromOffset(0, Y0 + 28),
	Size = UDim2.new(1, 0, 0, 212),
	ScrollingDirection = Enum.ScrollingDirection.X,
	AutomaticCanvasSize = Enum.AutomaticSize.X,
	CanvasSize = UDim2.new(),
	ScrollBarThickness = 8,
	Parent = leftCol,
})
UI.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder, Parent = speciesRow })
sectionTitle(leftCol, "2. Add catalysts (optional, max " .. Materials.MaxPerIncubation .. ")", Y0 + 246)
local catalystRow = UI.new("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(0, Y0 + 274), Size = UDim2.new(1, 0, 0, 96), Parent = leftCol })
UI.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder, Parent = catalystRow })
local startBtn = UI.Button(leftCol, "HATCH!", UI.Colors.Green, { Name = "StartButton", Size = UDim2.new(1, 0, 0, 60), Position = UDim2.fromOffset(0, Y0 + 380) })
local incPityLabel = UI.Label(leftCol, "", { Size = UDim2.new(1, 0, 0, 20), Position = UDim2.fromOffset(0, Y0 + 446), TextColor3 = UI.Colors.Gold })
local skipToggle = UI.Button(leftCol, "Skip reveal: OFF", UI.Colors.Card, { Size = UDim2.fromOffset(200, 34), Position = UDim2.fromOffset(0, Y0 + 472) })
-- Fusion lives in the chamber too: mix two monsters into a new one.
local fuseOpenBtn = UI.Button(leftCol, "FUSE MONSTERS", UI.Colors.Purple, { Name = "FuseOpen", Size = UDim2.new(1, -210, 0, 34), Position = UDim2.fromOffset(210, Y0 + 472) })

-- Shown instead of the chamber controls while the selected biome is locked.
local lockedPane = UI.new("Frame", {
	Name = "LockedBiome",
	BackgroundColor3 = UI.Colors.PanelDark,
	Position = UDim2.fromOffset(0, Y0),
	Size = UDim2.new(1, 0, 1, -Y0),
	Visible = false,
	ZIndex = 10,
	Parent = leftCol,
})
UI.Corner(lockedPane, 14)
UI.Stroke(lockedPane, 3)
local lockedTitle = UI.Label(lockedPane, "", { Size = UDim2.new(1, -30, 0, 36), Position = UDim2.fromOffset(15, 14), ZIndex = 11 })
local lockedDesc = UI.Label(lockedPane, "", { Size = UDim2.new(1, -30, 0, 44), Position = UDim2.fromOffset(15, 56), TextWrapped = true, TextColor3 = UI.Colors.Muted, MaxTextSize = 18, ZIndex = 11 })
local lockedReqs = UI.new("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(15, 110), Size = UDim2.new(1, -30, 0, 120), ZIndex = 11, Parent = lockedPane })
UI.new("UIListLayout", { Padding = UDim.new(0, 6), Parent = lockedReqs })
local unlockBtn = UI.Button(lockedPane, "Unlock", UI.Colors.Green, { Name = "UnlockButton", Size = UDim2.new(1, -30, 0, 56), Position = UDim2.new(0, 15, 0, 250), ZIndex = 11 })
local lockedPreview = UI.Label(lockedPane, "", { Size = UDim2.new(1, -30, 0, 80), Position = UDim2.fromOffset(15, 320), TextWrapped = true, TextColor3 = UI.Colors.Muted, MaxTextSize = 16, ZIndex = 11 })

sectionTitle(rightCol, "Odds for this setup", 0)
local oddsList = scrolling(rightCol, { Position = UDim2.fromOffset(0, 30), Size = UDim2.new(1, 0, 1, -30) })
UI.new("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder, Parent = oddsList })

local speciesCards = {}
for i, sp in Species.List do
	local card = UI.new("TextButton", { Text = "", AutoButtonColor = false, BackgroundColor3 = UI.Colors.Card, Size = UDim2.fromOffset(160, 196), LayoutOrder = i, Parent = speciesRow })
	UI.Corner(card, 14)
	local stroke = UI.Stroke(card, 3)
	local vpHolder = UI.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 110), Parent = card })
	UI.MonsterViewport(vpHolder, sp.Id, { BaseColorGene = sp.Palettes[1] }, {}, { Spin = 0.5 })
	UI.Label(card, sp.DisplayName, { Size = UDim2.new(1, -10, 0, 24), Position = UDim2.fromOffset(5, 110) })
	UI.RarityChip(card, sp.SpeciesRarity, { Size = UDim2.new(1, -20, 0, 22), Position = UDim2.fromOffset(10, 136) })
	local cost = UI.Label(card, Config.Species[sp.Id].Cost .. " coins", { Size = UDim2.new(1, -10, 0, 22), Position = UDim2.fromOffset(5, 164), TextColor3 = UI.Colors.Gold })
	local lock = UI.new("Frame", { BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.35, Size = UDim2.fromScale(1, 1), Visible = false, ZIndex = 5, Parent = card })
	UI.Corner(lock, 14)
	local lockLabel = UI.Label(lock, "LOCKED", { Size = UDim2.new(1, -20, 0, 60), Position = UDim2.new(0, 10, 0.5, -30), ZIndex = 6 })
	UI.Label(card, Biomes.ById[sp.HomeBiome].ShortName, {
		Size = UDim2.fromOffset(64, 16), Position = UDim2.fromOffset(4, 4), TextColor3 = Biomes.ById[sp.HomeBiome].Theme.Accent, MaxTextSize = 14,
	})
	speciesCards[sp.Id] = { Card = card, Stroke = stroke, Lock = lock, LockLabel = lockLabel, Cost = cost, Species = sp }
end

local catalystCards = {}
for i, mat in Materials.List do
	local card = UI.new("TextButton", { Text = "", AutoButtonColor = false, BackgroundColor3 = UI.Colors.Card, Size = UDim2.fromOffset(160, 92), LayoutOrder = i, Parent = catalystRow })
	UI.Corner(card, 14)
	local stroke = UI.Stroke(card, 3)
	UI.Label(card, mat.DisplayName, { Size = UDim2.new(1, -10, 0, 24), Position = UDim2.fromOffset(5, 4) })
	local owned = UI.Label(card, "x0", { Size = UDim2.new(1, -10, 0, 20), Position = UDim2.fromOffset(5, 28), TextColor3 = UI.Colors.Gold })
	UI.Label(card, mat.Description, { Size = UDim2.new(1, -10, 0, 36), Position = UDim2.fromOffset(5, 50), TextColor3 = UI.Colors.Muted, TextWrapped = true, MaxTextSize = 14 })
	catalystCards[mat.Id] = { Card = card, Stroke = stroke, Owned = owned, Biome = mat.SourceBiome }
end

local function selectedCatalystList(): { string }
	local list = {}
	for _, mat in Materials.List do
		if selection.Catalysts[mat.Id] then
			table.insert(list, mat.Id)
		end
	end
	return list
end

local oddsRequestToken = 0
local function refreshOdds()
	oddsRequestToken += 1
	local token = oddsRequestToken
	local resp = R.GetOdds:InvokeServer({ SpeciesId = selection.SpeciesId, BiomeId = BIOME, Catalysts = selectedCatalystList() })
	if token ~= oddsRequestToken then
		return
	end
	clearChildren(oddsList, KEEP_LAYOUT)
	if not resp or not resp.Ok then
		UI.Label(oddsList, "Odds unavailable: " .. tostring(resp and resp.Error), { Size = UDim2.new(1, 0, 0, 24), TextColor3 = UI.Colors.Muted })
		return
	end
	local order = 0
	local function row(text: string, color: Color3?, height: number?)
		order += 1
		return UI.Label(oddsList, text, {
			Size = UDim2.new(1, -8, 0, height or 20),
			LayoutOrder = order,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = color or UI.Colors.Text,
		})
	end
	if resp.PityActive then
		row("Bad-luck protection ACTIVE: this incubation is guaranteed a Rare+ mutation. Odds below show a normal roll.", UI.Colors.Gold, 40).TextWrapped = true
	end
	local env = resp.Report.Environment or {}
	if #resp.Report.ActiveEvents > 0 then
		for _, id in resp.Report.ActiveEvents do
			local ev = Events.ById[id]
			row("EVENT: " .. ev.DisplayName .. " - " .. ev.Description, ev.Color, 40).TextWrapped = true
		end
	end
	if env.Temperature then
		row(string.format("Environment: Temperature %d, Energy %d", env.Temperature, env.ElementalEnergy or 0), UI.Colors.Muted)
	end
	for _, cat in resp.Report.Categories do
		local extra = if cat.ExtraSlots > 0 then string.format(" (+%d extra slot @ %s)", cat.ExtraSlots, UI.FormatPercent(cat.ExtraSlotFillChance)) else ""
		row(Categories.ById[cat.Category].DisplayName .. extra, UI.Colors.Gold, 24)
		table.sort(cat.Candidates, function(a, b)
			return a.Probability > b.Probability
		end)
		for _, c in cat.Candidates do
			local m = Mutations.ById[c.MutationId]
			local def = Rarity.Get(c.Tier)
			local tags = {}
			for _, mod in c.Modifiers or {} do
				local kind, name = mod.Source:match("^(%w+):(.+)$")
				if kind == "Event" then
					name = Events.ById[name] and Events.ById[name].DisplayName or name
				elseif kind == "Catalyst" then
					name = Materials.ById[name] and Materials.ById[name].DisplayName or name
				elseif kind == "Biome" then
					name = "biome"
				elseif kind == "Affinity" then
					name = "affinity"
				end
				table.insert(tags, string.format("x%g %s", mod.Multiplier, name or mod.Source))
			end
			local tagText = if #tags > 0 then "  [" .. table.concat(tags, ", ") .. "]" else ""
			row(string.format("  %s %s  -  %s%s", def.Glyph, m.DisplayName, UI.FormatPercent(c.Probability), tagText), def.Color)
		end
		row("  (none)  -  " .. UI.FormatPercent(cat.EmptyChance), UI.Colors.Muted)
	end
	-- Hybrids: chance applies only if every input ends up on the monster.
	local hybridRows = 0
	for _, h in resp.Report.Hybrids or {} do
		local recipe = HybridRecipes.ById[h.RecipeId]
		if h.BlockedBy == "Biome" or not recipe then
			continue
		end
		if hybridRows == 0 then
			row("Hybrid recipes (chance if all inputs end up on the monster)", UI.Colors.Gold, 24)
		end
		hybridRows += 1
		local out = Mutations.ById[h.Output]
		local def = Rarity.Get(out.RarityTier)
		local known = state and state.Discoveries.Mutations[h.Output] ~= nil
		local chanceText = if h.Guaranteed then "GUARANTEED" else UI.FormatPercent(h.Chance)
		local status = ""
		if h.BlockedBy == "Catalyst" then
			local names = {}
			for _, c in recipe.RequiredCatalysts or {} do
				table.insert(names, Materials.ById[c].DisplayName)
			end
			status = "  (needs " .. table.concat(names, ", ") .. ")"
		elseif h.BlockedBy == "Event" then
			local names = {}
			for _, e in recipe.RequiredEvents or {} do
				table.insert(names, Events.ById[e].DisplayName)
			end
			status = "  (only during " .. table.concat(names, ", ") .. ")"
		elseif h.BlockedBy then
			status = "  (locked: " .. h.BlockedBy .. ")"
		end
		local name = if known then out.DisplayName else "??? hybrid"
		row(string.format("  %s %s  -  %s%s", def.Glyph, name, chanceText, status), if h.ConditionsMet then def.Color else UI.Colors.Muted)
		-- Recipe Analyzer research reveals the ingredients before discovery.
		if known or (state and state.Research and state.Research.RecipeAnalyzer) then
			local parts = {}
			for _, input in recipe.Inputs do
				local kind, n = input:match("^(%w+):(.+)$")
				local label = if kind == "Mutation" then Mutations.ById[n].DisplayName else (n .. " element")
				table.insert(parts, label .. (if h.InputsFromSpecies[input] then " (have)" else ""))
			end
			row("      needs " .. table.concat(parts, " + "), UI.Colors.Muted)
		else
			row("      hint: " .. recipe.Hint, UI.Colors.Muted, 34).TextWrapped = true
		end
	end
	row("Odds are exact per slot and come from the same server code that rolls.", UI.Colors.Muted, 34).TextWrapped = true
end

-- (available, lockText) for a species, mirroring the server's BiomeService rules.
local function speciesStatus(id: string): (boolean, string?)
	local sp = Species.ById[id]
	if not state.UnlockedBiomes[sp.HomeBiome] then
		return false, "LOCKED\n" .. Biomes.ById[sp.HomeBiome].DisplayName
	end
	if state.Level < Config.Species[id].UnlockLevel then
		return false, "LOCKED\nLevel " .. Config.Species[id].UnlockLevel
	end
	return true, nil
end

local titleLabel = incubatorPanel.Frame:FindFirstChildWhichIsA("Frame"):FindFirstChildOfClass("TextLabel") :: TextLabel

local function refreshIncubator()
	if not state then
		return
	end
	local biome = Biomes.ById[BIOME]
	local unlocked = state.UnlockedBiomes[BIOME] == true
	titleLabel.Text = "Hatch a Monster - " .. biome.DisplayName
	for id, tab in biomeTabs do
		local label = Biomes.ById[id].DisplayName
		if not state.UnlockedBiomes[id] then
			label ..= " (locked)"
		end
		UI.SetButtonText(tab, label)
		UI.SetDisabled(tab, id ~= BIOME)
	end
	-- Native species of the selected biome first, then the rest.
	for id, c in speciesCards do
		local ok, why = speciesStatus(id)
		c.Lock.Visible = not ok
		c.LockLabel.Text = why or ""
		c.Card.LayoutOrder = (if c.Species.HomeBiome == BIOME then 0 else 100) + (if ok then 0 else 50) + Biomes.ById[c.Species.HomeBiome].Order
		c.Stroke.Color = if selection.SpeciesId == id then UI.Colors.Gold else UI.Colors.Stroke
		c.Stroke.Thickness = if selection.SpeciesId == id then 5 else 3
	end
	local count = 0
	for id, c in catalystCards do
		local have = state.Inventory[id] or 0
		c.Card.Visible = c.Biome == BIOME
		if have <= 0 or c.Biome ~= BIOME then
			selection.Catalysts[id] = nil
		end
		c.Owned.Text = "x" .. have
		c.Stroke.Color = if selection.Catalysts[id] then UI.Colors.Gold else UI.Colors.Stroke
		c.Stroke.Thickness = if selection.Catalysts[id] then 5 else 3
		c.Card.BackgroundColor3 = if have > 0 then UI.Colors.Card else UI.Colors.PanelDark
	end
	for _ in selection.Catalysts do
		count += 1
	end
	-- Locked biome: requirement checklist + unlock button instead of the chamber.
	lockedPane.Visible = not unlocked
	if not unlocked then
		local info = state.BiomeRequirements and state.BiomeRequirements[BIOME]
		lockedTitle.Text = biome.DisplayName .. " is locked"
		lockedDesc.Text = biome.Description
		clearChildren(lockedReqs, { "UIListLayout" })
		local allMet = true
		for _, r in (info and info.Requirements) or {} do
			local have = if r.Id == "Coins" then math.floor(state.Coins) else r.Have
			local met = have >= r.Need
			allMet = allMet and met
			UI.Label(lockedReqs, string.format("%s  %s  (%s / %s)", if met then "[x]" else "[ ]", r.Label, UI.FormatNumber(have), UI.FormatNumber(r.Need)), {
				Size = UDim2.new(1, 0, 0, 28), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = if met then UI.Colors.Green else UI.Colors.Text, ZIndex = 11,
			})
		end
		UI.SetDisabled(unlockBtn, not allMet)
		UI.SetButtonText(unlockBtn, string.format("Unlock %s (%s coins)", biome.DisplayName, UI.FormatNumber(biome.Unlock.Coins)))
		local names = {}
		for _, sid in biome.Species do
			table.insert(names, Species.ById[sid].DisplayName)
		end
		local evNames = {}
		for _, ev in Events.List do
			if ev.Biome == BIOME then
				table.insert(evNames, ev.DisplayName)
			end
		end
		lockedPreview.Text = "Unlocks: " .. table.concat(names, ", ") .. ", new mutations, catalysts" .. (if #evNames > 0 then (" and timed events (" .. table.concat(evNames, ", ") .. ")") else "") .. "."
	end
	local cost = Config.Species[selection.SpeciesId].Cost
	local busy = freeEggSlots() <= 0
	UI.SetDisabled(startBtn, busy)
	UI.SetButtonText(startBtn, if busy then "All egg spots busy..." else string.format("HATCH!  (%d coins)", cost))
	local left = state.PityThreshold - state.PityCounter
	incPityLabel.Text = if left <= 1 then "Your next monster will be RARE or better!" else string.format("You will get a RARE monster in %d hatches or less!", left)
	UI.SetButtonText(skipToggle, "Skip reveal: " .. (if state.Settings.SkipReveal then "ON" else "OFF"))
end

for biomeId, tab in biomeTabs do
	tab.Activated:Connect(function()
		if BIOME == biomeId then
			return
		end
		BIOME = biomeId
		refreshIncubator()
		if state and state.UnlockedBiomes[biomeId] then
			task.spawn(refreshOdds)
		else
			oddsRequestToken += 1 -- drop any in-flight odds for the previous biome
			clearChildren(oddsList, KEEP_LAYOUT)
			UI.Label(oddsList, "Unlock this biome to see its exact odds.", { Size = UDim2.new(1, -8, 0, 24), TextColor3 = UI.Colors.Muted })
		end
	end)
end
unlockBtn.Activated:Connect(function()
	if UI.IsDisabled(unlockBtn) then
		showError("RequirementsNotMet")
		return
	end
	local r = R.UnlockBiome:InvokeServer(BIOME)
	if r and r.Ok then
		UI.Play("Pop", 0.7, 0.8)
		UI.Toast(Biomes.ById[BIOME].DisplayName .. " UNLOCKED!", Biomes.ById[BIOME].Theme.Accent)
	else
		showError(r and r.Error)
	end
end)

for id, c in speciesCards do
	c.Card.Activated:Connect(function()
		local ok = state and speciesStatus(id)
		if not ok then
			UI.Toast("Locked: " .. (select(2, speciesStatus(id)) or ""):gsub("\n", " - "), UI.Colors.Orange)
			return
		end
		selection.SpeciesId = id
		UI.Play("Pop", 1.2, 0.3)
		refreshIncubator()
		task.spawn(refreshOdds)
	end)
end
for id, c in catalystCards do
	c.Card.Activated:Connect(function()
		if not state or (state.Inventory[id] or 0) <= 0 then
			UI.Toast("You have no " .. Materials.ById[id].DisplayName .. ". Buy some in the Shop!", UI.Colors.Orange)
			return
		end
		if selection.Catalysts[id] then
			selection.Catalysts[id] = nil
		else
			if #selectedCatalystList() >= Materials.MaxPerIncubation then
				UI.Toast("Max " .. Materials.MaxPerIncubation .. " catalysts.", UI.Colors.Orange)
				return
			end
			selection.Catalysts[id] = true
		end
		UI.Play("Pop", 1.3, 0.3)
		refreshIncubator()
		task.spawn(refreshOdds)
	end)
end
skipToggle.Activated:Connect(function()
	if state then
		R.SetSetting:InvokeServer("SkipReveal", not state.Settings.SkipReveal)
	end
end)
incubatorPanel.OnOpen = function()
	refreshIncubator()
	task.spawn(refreshOdds)
end

-- quiet = started by Auto: no toast and the incubator panel is left alone.
local function startIncubation(sel, quiet: boolean?)
	local payload = {
		RequestId = HttpService:GenerateGUID(false),
		SpeciesId = sel.SpeciesId,
		BiomeId = sel.BiomeId,
		Catalysts = sel.CatalystList,
	}
	local resp = R.StartIncubation:InvokeServer(payload)
	if not resp or not resp.Ok then
		showError(resp and resp.Error)
		return false
	end
	lastSelection = sel
	-- Show the new egg now instead of waiting for the next state push.
	if state and resp.Incubations then
		state.Incubations = resp.Incubations
	end
	UI.Play("Swoosh", 0.9, 0.5)
	if not quiet then
		UI.Toast("Incubation started!", UI.Colors.Green)
		incubatorPanel.Close()
	end
	return true
end
startBtn.Activated:Connect(function()
	if UI.IsDisabled(startBtn) then
		showError("ChamberBusy")
		return
	end
	if not state.UnlockedBiomes[BIOME] then
		showError("BiomeLocked")
		return
	end
	startIncubation({ SpeciesId = selection.SpeciesId, BiomeId = BIOME, CatalystList = selectedCatalystList() })
end)

-- ===== Monsters =====
local PAGE_SIZE = 18
local monsterPage = 1
local selectedMonsterId: string? = nil
local sellConfirmId: string? = nil
local monContent = monstersPanel.Content
local monLeft = UI.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(0.6, 0, 1, 0), Parent = monContent })
local monGrid = scrolling(monLeft, { Size = UDim2.new(1, 0, 1, -50) })
UI.new("UIGridLayout", { CellSize = UDim2.fromOffset(150, 170), CellPadding = UDim2.fromOffset(8, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = monGrid })
local pager = UI.new("Frame", { BackgroundTransparency = 1, Position = UDim2.new(0, 0, 1, -44), Size = UDim2.new(1, 0, 0, 44), Parent = monLeft })
local prevBtn = UI.Button(pager, "<", UI.Colors.Card, { Size = UDim2.fromOffset(60, 40) })
local pageLabel = UI.Label(pager, "", { Size = UDim2.new(1, -430, 0, 30), Position = UDim2.fromOffset(70, 5) })
local nextBtn = UI.Button(pager, ">", UI.Colors.Card, { Size = UDim2.fromOffset(60, 40), Position = UDim2.new(1, -60, 0, 0) })
-- Bulk sell: pick the highest rarity to clear, then tap twice (preview, confirm).
-- Locked and equipped monsters are always kept; the server caps it at Rare.
local bulkTier = 1
local bulkConfirm: { Count: number, Coins: number }? = nil
local bulkTierBtn = UI.Button(pager, "", UI.Colors.Card, { Name = "BulkTier", Size = UDim2.fromOffset(110, 40), Position = UDim2.new(1, -356, 0, 0) })
local bulkSellBtn = UI.Button(pager, "", UI.Colors.Red, { Name = "BulkSell", Size = UDim2.fromOffset(170, 40), Position = UDim2.new(1, -238, 0, 0) })
local function refreshBulk()
	UI.SetButtonText(bulkTierBtn, "Up to " .. Rarity.Get(bulkTier).Name)
	UI.SetButtonText(bulkSellBtn, if bulkConfirm then string.format("Sell %d for %s?", bulkConfirm.Count, UI.FormatNumber(bulkConfirm.Coins)) else "Sell all")
end
refreshBulk()
bulkTierBtn.Activated:Connect(function()
	bulkTier = bulkTier % 3 + 1
	bulkConfirm = nil
	UI.Play("Pop", 1.2, 0.3)
	refreshBulk()
end)
bulkSellBtn.Activated:Connect(function()
	local confirm = bulkConfirm
	local r = R.SellBulk:InvokeServer(bulkTier, confirm == nil)
	bulkConfirm = nil
	if not r or not r.Ok then
		showError(r and r.Error)
	elseif r.Preview then
		if r.Count == 0 then
			UI.Toast("Nothing to sell (locked and equipped monsters are kept).", UI.Colors.Orange)
		else
			bulkConfirm = { Count = r.Count, Coins = r.Coins }
		end
	elseif r.Count > 0 then
		UI.FloatText(coinPill, "+" .. UI.FormatNumber(r.Coins), UI.Colors.Gold)
		UI.Toast(string.format("Sold %d monsters for %s coins.", r.Count, UI.FormatNumber(r.Coins)), UI.Colors.Gold)
		UI.Play("Pop", 0.9, 0.5)
	end
	refreshBulk()
end)
local inspect = UI.new("Frame", { BackgroundColor3 = UI.Colors.PanelDark, Position = UDim2.fromScale(0.62, 0), Size = UDim2.new(0.38, 0, 1, 0), Parent = monContent })
UI.Corner(inspect, 14)

local function sortedMonsters()
	local list = table.clone(state.Monsters)
	table.sort(list, function(a, b)
		if a.RarityTier ~= b.RarityTier then
			return a.RarityTier > b.RarityTier
		end
		return a.CreationTimestamp > b.CreationTimestamp
	end)
	return list
end

local function findMonster(id: string?)
	for _, rec in state.Monsters do
		if rec.MonsterId == id then
			return rec
		end
	end
	return nil
end

local function refreshInspect()
	clearChildren(inspect, { "UICorner" })
	local rec = state and findMonster(selectedMonsterId)
	if not rec then
		UI.Label(inspect, "Select a monster to inspect it.", { Size = UDim2.new(1, -20, 0, 30), Position = UDim2.new(0, 10, 0.5, -15), TextColor3 = UI.Colors.Muted })
		return
	end
	local sp = Species.ById[rec.SpeciesId]
	local vp = UI.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 170), Parent = inspect })
	UI.MonsterViewport(vp, rec.SpeciesId, rec.Genes, rec.ActiveMutations, { Spin = 0.6, Seed = #rec.MonsterId, RarityTier = rec.RarityTier })
	UI.Label(inspect, rec.DisplayName, { Size = UDim2.new(1, -20, 0, 28), Position = UDim2.fromOffset(10, 172) })
	UI.RarityChip(inspect, rec.RarityTier, { Size = UDim2.fromOffset(150, 24), Position = UDim2.new(0.5, -155, 0, 204) })
	local spChip = UI.RarityChip(inspect, rec.SpeciesRarity, { Size = UDim2.fromOffset(150, 24), Position = UDim2.new(0.5, 5, 0, 204) })
	;(spChip:FindFirstChildOfClass("TextLabel") :: TextLabel).Text = sp.DisplayName .. ": " .. Rarity.Get(rec.SpeciesRarity).Name
	local lines = {
		string.format("Power %d   |   Income %.2f/s   |   Research %.2f", rec.Stats.Power, rec.Stats.IncomeRate, rec.Stats.ResearchValue),
		string.format("Element: %s%s   |   Size x%.2f (gene) x%.2f (%s)   |   %s", rec.PrimaryElement, if rec.SecondaryElement then (" / " .. rec.SecondaryElement) else "", rec.Genes.SizeGene, Rarity.Get(rec.RarityTier).Scale, Rarity.Get(rec.RarityTier).Name, rec.Genes.BaseColorGene),
	}
	for i, l in lines do
		UI.Label(inspect, l, { Size = UDim2.new(1, -20, 0, 18), Position = UDim2.fromOffset(10, 234 + (i - 1) * 22), TextColor3 = UI.Colors.Muted })
	end
	local mutList = scrolling(inspect, { Position = UDim2.fromOffset(10, 284), Size = UDim2.new(1, -20, 1, -398), BackgroundColor3 = UI.Colors.Panel })
	UI.new("UIListLayout", { Padding = UDim.new(0, 4), Parent = mutList })
	if #rec.ActiveMutations == 0 then
		UI.Label(mutList, "No mutations (pure " .. sp.DisplayName .. ")", { Size = UDim2.new(1, 0, 0, 22), TextColor3 = UI.Colors.Muted })
	end
	for _, id in rec.ActiveMutations do
		local m = Mutations.ById[id]
		local def = Rarity.Get(m.RarityTier)
		UI.Label(mutList, string.format("%s %s  [%s, %s]", def.Glyph, m.DisplayName, m.Category, def.Name), { Size = UDim2.new(1, 0, 0, 20), TextColor3 = def.Color, TextXAlignment = Enum.TextXAlignment.Left })
		UI.Label(mutList, "    " .. m.Description, { Size = UDim2.new(1, 0, 0, 16), TextColor3 = UI.Colors.Muted, TextXAlignment = Enum.TextXAlignment.Left })
	end
	local equipped = isPet(rec.MonsterId)
	local slotsText = string.format("%d/%d", #state.Equipped, state.PetSlots)
	local equipBtn = UI.Button(inspect, if equipped then ("Unequip (pets " .. slotsText .. ")") else ("Equip - follows you (pets " .. slotsText .. ")"), if equipped then UI.Colors.Purple else UI.Colors.Blue, {
		Name = "EquipButton", Size = UDim2.new(1, -20, 0, 44), Position = UDim2.new(0, 10, 1, -106),
	})
	equipBtn.Activated:Connect(function()
		equipMonster(rec.MonsterId, rec.DisplayName, not equipped)
	end)
	local locked = state.Locked[rec.MonsterId] == true
	local lockBtn = UI.Button(inspect, if locked then "Locked" else "Lock", if locked then UI.Colors.Gold else UI.Colors.Card, { Size = UDim2.new(0.4, -10, 0, 44), Position = UDim2.new(0, 10, 1, -54) })
	local value = Config.SellValue[rec.RarityTier]
	local sellText = if sellConfirmId == rec.MonsterId then ("Confirm sell: " .. UI.FormatNumber(value)) else ("Sell (" .. UI.FormatNumber(value) .. ")")
	local sellBtn = UI.Button(inspect, sellText, UI.Colors.Red, { Size = UDim2.new(0.6, -10, 0, 44), Position = UDim2.new(0.4, 0, 1, -54) })
	UI.SetDisabled(sellBtn, locked)
	lockBtn.Activated:Connect(function()
		local r = R.ToggleLock:InvokeServer(rec.MonsterId)
		if not r.Ok then
			showError(r.Error)
		end
	end)
	sellBtn.Activated:Connect(function()
		if UI.IsDisabled(sellBtn) then
			showError("Locked")
			return
		end
		if sellConfirmId ~= rec.MonsterId then
			sellConfirmId = rec.MonsterId
			refreshInspect()
			return
		end
		sellConfirmId = nil
		local r = R.SellMonster:InvokeServer(rec.MonsterId)
		if r.Ok then
			UI.FloatText(coinPill, "+" .. UI.FormatNumber(r.Coins), UI.Colors.Gold)
			selectedMonsterId = nil
		else
			showError(r.Error)
		end
	end)
end

local function refreshMonsters()
	if not state then
		return
	end
	clearChildren(monGrid, KEEP_LAYOUT)
	local list = sortedMonsters()
	local pages = math.max(1, math.ceil(#list / PAGE_SIZE))
	monsterPage = math.clamp(monsterPage, 1, pages)
	pageLabel.Text = string.format("Page %d / %d   (%d / %d monsters)", monsterPage, pages, #list, Config.MaxMonsters)
	if #list == 0 then
		UI.Label(monGrid, "No monsters yet. Incubate one!", { Size = UDim2.new(1, 0, 0, 30), TextColor3 = UI.Colors.Muted })
	end
	for i = (monsterPage - 1) * PAGE_SIZE + 1, math.min(#list, monsterPage * PAGE_SIZE) do
		local rec = list[i]
		local def = Rarity.Get(rec.RarityTier)
		local card = UI.new("TextButton", { Text = "", AutoButtonColor = false, BackgroundColor3 = UI.Colors.Card, LayoutOrder = i, Parent = monGrid })
		UI.Corner(card, 12)
		UI.Stroke(card, if rec.MonsterId == selectedMonsterId then 5 else 3, if rec.MonsterId == selectedMonsterId then UI.Colors.Gold else def.Color:Lerp(Color3.new(0, 0, 0), 0.4))
		UI.Gradient(card, Color3.new(1, 1, 1), def.Color:Lerp(Color3.new(1, 1, 1), 0.4))
		local vp = UI.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 100), Parent = card })
		UI.MonsterViewport(vp, rec.SpeciesId, rec.Genes, rec.ActiveMutations, { Seed = #rec.MonsterId, RarityTier = rec.RarityTier })
		UI.Label(card, rec.DisplayName, { Size = UDim2.new(1, -10, 0, 22), Position = UDim2.fromOffset(5, 102) })
		UI.RarityChip(card, rec.RarityTier, { Size = UDim2.new(1, -16, 0, 22), Position = UDim2.fromOffset(8, 130) })
		if state.Locked[rec.MonsterId] then
			UI.Label(card, "LOCK", { Size = UDim2.fromOffset(44, 18), Position = UDim2.fromOffset(4, 4), TextColor3 = UI.Colors.Gold })
		end
		if isPet(rec.MonsterId) then
			UI.Label(card, "PET", { Size = UDim2.fromOffset(40, 18), Position = UDim2.new(1, -44, 0, 4), TextColor3 = UI.Colors.Purple })
		elseif #state.Equipped < state.PetSlots then
			-- One-click equip right on the card.
			local quick = UI.Button(card, "Equip", UI.Colors.Purple, { Name = "QuickEquip", Size = UDim2.fromOffset(58, 24), Position = UDim2.new(1, -62, 0, 4), ZIndex = 3 })
			quick.Activated:Connect(function()
				equipMonster(rec.MonsterId, rec.DisplayName)
			end)
		end
		card.Activated:Connect(function()
			selectedMonsterId = rec.MonsterId
			sellConfirmId = nil
			UI.Play("Pop", 1.2, 0.3)
			refreshMonsters()
		end)
	end
	refreshInspect()
end
prevBtn.Activated:Connect(function()
	monsterPage -= 1
	refreshMonsters()
end)
nextBtn.Activated:Connect(function()
	monsterPage += 1
	refreshMonsters()
end)
monstersPanel.OnOpen = function()
	bulkConfirm = nil
	refreshBulk()
	refreshMonsters()
end

-- ===== Index =====
local indexTab = "Species"
local idxContent = indexPanel.Content
local completionLabel = UI.Label(idxContent, "", { Size = UDim2.new(0.5, 0, 0, 26), TextXAlignment = Enum.TextXAlignment.Left })
local completionBar = UI.Bar(idxContent, UI.Colors.Purple, { Size = UDim2.new(0.5, -10, 0, 16), Position = UDim2.fromOffset(0, 32) })
local tabSpecies = UI.Button(idxContent, "Species", UI.Colors.Purple, { Name = "TabSpecies", Size = UDim2.fromOffset(130, 44), Position = UDim2.new(1, -410, 0, 0) })
local tabMutations = UI.Button(idxContent, "Mutations", UI.Colors.Purple, { Name = "TabMutations", Size = UDim2.fromOffset(130, 44), Position = UDim2.new(1, -275, 0, 0) })
local tabHybrids = UI.Button(idxContent, "Hybrids", UI.Colors.Purple, { Name = "TabHybrids", Size = UDim2.fromOffset(130, 44), Position = UDim2.new(1, -140, 0, 0) })
local idxGrid = scrolling(idxContent, { Position = UDim2.fromOffset(0, 60), Size = UDim2.new(1, 0, 1, -60) })
local idxLayout = UI.new("UIGridLayout", { CellPadding = UDim2.fromOffset(8, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = idxGrid })

local function requirementHint(m): string
	local bits = {}
	if m.AllowedBiomes then
		local names = {}
		for _, b in m.AllowedBiomes do
			table.insert(names, Biomes.ById[b] and Biomes.ById[b].DisplayName or b)
		end
		table.insert(bits, "Biome: " .. table.concat(names, ", "))
	end
	if m.RequiredCatalysts then
		local names = {}
		for _, c in m.RequiredCatalysts do
			table.insert(names, Materials.ById[c] and Materials.ById[c].DisplayName or c)
		end
		table.insert(bits, "Needs: " .. table.concat(names, ", "))
	end
	if m.RequiredElements then
		table.insert(bits, "Element: " .. table.concat(m.RequiredElements, "/"))
	end
	if m.RequiredAttachment then
		table.insert(bits, "Body part: " .. m.RequiredAttachment)
	end
	if m.RequiredResearch then
		table.insert(bits, "Research required")
	end
	if m.MinimumProgression then
		table.insert(bits, "Level " .. m.MinimumProgression .. "+")
	end
	if m.RequiredEvents then
		local names = {}
		for _, e in m.RequiredEvents do
			table.insert(names, Events.ById[e] and Events.ById[e].DisplayName or e)
		end
		table.insert(bits, "Event: " .. table.concat(names, ", "))
	end
	if m.Environment and m.Environment.Temperature then
		local r = m.Environment.Temperature
		table.insert(bits, if r[1] <= -100 then ("Temp " .. r[2] .. " or colder") else ("Temp " .. r[1] .. " to " .. r[2]))
	end
	return if #bits > 0 then table.concat(bits, "  |  ") else "Verdant Meadows, any species"
end

local function newBadge(parent: Instance)
	local tag = UI.new("Frame", { BackgroundColor3 = UI.Colors.Red, Size = UDim2.fromOffset(50, 22), Position = UDim2.new(1, -46, 0, -6), Rotation = 8, ZIndex = 4, Parent = parent })
	UI.Corner(tag, 6)
	UI.Stroke(tag, 2)
	UI.Label(tag, "NEW!", { ZIndex = 5 })
end

local function markSeen(key: string)
	if state and state.Unseen[key] then
		task.spawn(function()
			R.MarkSeen:InvokeServer(key)
		end)
	end
end

local function refreshIndex()
	if not state then
		return
	end
	clearChildren(idxGrid, KEEP_LAYOUT)
	local totalEntries = #Species.List + #Mutations.List
	local found = 0
	for _ in state.Discoveries.Species do
		found += 1
	end
	for _ in state.Discoveries.Mutations do
		found += 1
	end
	completionLabel.Text = string.format("Collection: %d / %d discovered (%d%%)", found, totalEntries, math.floor(found / totalEntries * 100))
	completionBar.Set(found / totalEntries, true)
	-- The unselected tab is drawn greyed but stays clickable.
	UI.SetDisabled(tabSpecies, indexTab ~= "Species")
	UI.SetDisabled(tabMutations, indexTab ~= "Mutations")
	UI.SetDisabled(tabHybrids, indexTab ~= "Hybrids")
	if indexTab == "Species" then
		idxLayout.CellSize = UDim2.fromOffset(190, 230)
		for i, sp in Species.List do
			local known = state.Discoveries.Species[sp.Id] ~= nil
			local card = UI.new("TextButton", { Text = "", AutoButtonColor = false, BackgroundColor3 = UI.Colors.Card, LayoutOrder = i, Parent = idxGrid })
			UI.Corner(card, 14)
			UI.Stroke(card, 3)
			local vp = UI.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 120), Parent = card })
			UI.MonsterViewport(vp, sp.Id, { BaseColorGene = sp.Palettes[1] }, {}, { Spin = if known then 0.5 else 0, Silhouette = not known })
			UI.Label(card, if known then sp.DisplayName else "???", { Size = UDim2.new(1, -10, 0, 26), Position = UDim2.fromOffset(5, 122) })
			UI.RarityChip(card, sp.SpeciesRarity, { Size = UDim2.new(1, -20, 0, 22), Position = UDim2.fromOffset(10, 152) })
			UI.Label(card, if known then sp.Description else ("Found in " .. Biomes.ById[sp.HomeBiome].DisplayName .. ". Incubate it to discover."), {
				Size = UDim2.new(1, -14, 0, 48), Position = UDim2.fromOffset(7, 178), TextWrapped = true, TextColor3 = UI.Colors.Muted, MaxTextSize = 16,
			})
			if state.Unseen["Species:" .. sp.Id] then
				newBadge(card)
			end
			-- Equip your best monster of this species straight from the Index.
			local best = nil
			for _, rec in state.Monsters do
				if rec.SpeciesId == sp.Id and (best == nil or rec.RarityTier > best.RarityTier or (rec.RarityTier == best.RarityTier and rec.CreationTimestamp > best.CreationTimestamp)) then
					best = rec
				end
			end
			if best then
				local following = isPet(best.MonsterId)
				local eq = UI.Button(card, if following then "Following" else "Equip best", UI.Colors.Purple, {
					Name = "EquipBest", Size = UDim2.fromOffset(100, 26), Position = UDim2.new(1, -104, 0, 4), ZIndex = 3,
				})
				UI.SetDisabled(eq, following)
				eq.Activated:Connect(function()
					if not following then
						equipMonster(best.MonsterId, best.DisplayName)
					end
				end)
			end
			card.Activated:Connect(function()
				markSeen("Species:" .. sp.Id)
			end)
		end
	elseif indexTab == "Hybrids" then
		idxLayout.CellSize = UDim2.fromOffset(420, 150)
		for i, recipe in HybridRecipes.List do
			local out = Mutations.ById[recipe.Output]
			local known = state.Discoveries.Mutations[recipe.Output] ~= nil
			local def = Rarity.Get(out.RarityTier)
			local card = UI.new("TextButton", { Text = "", AutoButtonColor = false, BackgroundColor3 = if known then UI.Colors.Card else UI.Colors.PanelDark, LayoutOrder = i, Parent = idxGrid })
			UI.Corner(card, 12)
			UI.Stroke(card, 3, if known then def.Color:Lerp(Color3.new(0, 0, 0), 0.3) else UI.Colors.Stroke)
			local analyzed = state.Research and state.Research.RecipeAnalyzer
			local ingredients = recipe.DisplayName:match("^(.-) = ") or "???"
			UI.Label(card, if known then recipe.DisplayName elseif analyzed then (ingredients .. " = ???") else "??? + ??? = ???", { Size = UDim2.new(1, -16, 0, 26), Position = UDim2.fromOffset(8, 6), TextXAlignment = Enum.TextXAlignment.Left })
			UI.RarityChip(card, out.RarityTier, { Size = UDim2.fromOffset(130, 22), Position = UDim2.fromOffset(8, 36) })
			UI.Label(card, if recipe.Chance >= 1 then "Guaranteed recipe" else ("Chance: " .. UI.FormatPercent(recipe.Chance)), {
				Size = UDim2.fromOffset(200, 22), Position = UDim2.fromOffset(148, 36), TextColor3 = UI.Colors.Gold, TextXAlignment = Enum.TextXAlignment.Left,
			})
			-- Conditions are always shown: players need them to decide what to try.
			local conds = {}
			for _, b in recipe.Biomes or {} do
				table.insert(conds, Biomes.ById[b].DisplayName)
			end
			for _, c in recipe.RequiredCatalysts or {} do
				table.insert(conds, "needs " .. Materials.ById[c].DisplayName)
			end
			for _, e in recipe.RequiredEvents or {} do
				table.insert(conds, "during " .. Events.ById[e].DisplayName)
			end
			UI.Label(card, "Where: " .. table.concat(conds, ", "), { Size = UDim2.new(1, -16, 0, 20), Position = UDim2.fromOffset(8, 64), TextColor3 = UI.Colors.Text, TextXAlignment = Enum.TextXAlignment.Left, MaxTextSize = 18 })
			UI.Label(card, if known then out.Description else ("Hint: " .. recipe.Hint), {
				Size = UDim2.new(1, -16, 0, 50), Position = UDim2.fromOffset(8, 90), TextWrapped = true, TextColor3 = UI.Colors.Muted, TextXAlignment = Enum.TextXAlignment.Left, MaxTextSize = 17,
			})
			if state.Unseen["Mutation:" .. out.Id] then
				newBadge(card)
			end
			card.Activated:Connect(function()
				markSeen("Mutation:" .. out.Id)
			end)
		end
	else
		idxLayout.CellSize = UDim2.fromOffset(260, 112)
		local list = table.clone(Mutations.List)
		table.sort(list, function(a, b)
			if a.Category ~= b.Category then
				return Categories.ById[a.Category].Order < Categories.ById[b.Category].Order
			end
			return a.RarityTier < b.RarityTier
		end)
		for i, m in list do
			local known = state.Discoveries.Mutations[m.Id] ~= nil
			local def = Rarity.Get(m.RarityTier)
			local card = UI.new("TextButton", { Text = "", AutoButtonColor = false, BackgroundColor3 = if known then UI.Colors.Card else UI.Colors.PanelDark, LayoutOrder = i, Parent = idxGrid })
			UI.Corner(card, 12)
			UI.Stroke(card, 3, if known then def.Color:Lerp(Color3.new(0, 0, 0), 0.3) else UI.Colors.Stroke)
			UI.Label(card, if known then m.DisplayName else "???", { Size = UDim2.new(1, -16, 0, 24), Position = UDim2.fromOffset(8, 6), TextXAlignment = Enum.TextXAlignment.Left })
			UI.RarityChip(card, m.RarityTier, { Size = UDim2.fromOffset(120, 22), Position = UDim2.fromOffset(8, 34) })
			UI.Label(card, m.Category, { Size = UDim2.fromOffset(110, 20), Position = UDim2.fromOffset(136, 35), TextColor3 = UI.Colors.Muted })
			UI.Label(card, if known then m.Description else requirementHint(m), {
				Size = UDim2.new(1, -16, 0, 44), Position = UDim2.fromOffset(8, 62), TextWrapped = true, TextColor3 = UI.Colors.Muted, TextXAlignment = Enum.TextXAlignment.Left, MaxTextSize = 18,
			})
			if state.Unseen["Mutation:" .. m.Id] then
				newBadge(card)
			end
			card.Activated:Connect(function()
				markSeen("Mutation:" .. m.Id)
			end)
		end
	end
end
tabSpecies.Activated:Connect(function()
	indexTab = "Species"
	refreshIndex()
end)
tabMutations.Activated:Connect(function()
	indexTab = "Mutations"
	refreshIndex()
end)
tabHybrids.Activated:Connect(function()
	indexTab = "Hybrids"
	refreshIndex()
end)
indexPanel.OnOpen = refreshIndex

-- ===== Shop =====
local shopList = scrolling(shopPanel.Content, { Size = UDim2.fromScale(1, 1) })
UI.new("UIListLayout", { Padding = UDim.new(0, 8), Parent = shopList })
local shopOwned = {}
for _, mat in Materials.List do
	local price = Config.CatalystPrices[mat.Id]
	if price then
		local row = UI.new("Frame", { BackgroundColor3 = UI.Colors.Card, Size = UDim2.new(1, -8, 0, 96), Parent = shopList })
		UI.Corner(row, 14)
		UI.Stroke(row, 3)
		UI.Label(row, mat.DisplayName, { Size = UDim2.new(0.5, 0, 0, 28), Position = UDim2.fromOffset(14, 8), TextXAlignment = Enum.TextXAlignment.Left })
		UI.RarityChip(row, mat.RarityTier, { Size = UDim2.fromOffset(120, 22), Position = UDim2.new(0.5, -130, 0, 12) })
		UI.Label(row, mat.Description, { Size = UDim2.new(1, -350, 0, 24), Position = UDim2.fromOffset(14, 38), TextColor3 = UI.Colors.Muted, TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = true, MaxTextSize = 16 })
		shopOwned[mat.Id] = UI.Label(row, "Owned: 0", { Size = UDim2.new(0.6, 0, 0, 20), Position = UDim2.fromOffset(14, 66), TextColor3 = UI.Colors.Gold, TextXAlignment = Enum.TextXAlignment.Left })
		for j, qty in { 1, 5 } do
			local b = UI.Button(row, string.format("x%d  (%s)", qty, UI.FormatNumber(price * qty)), UI.Colors.Green, {
				Size = UDim2.fromOffset(150, 40), Position = UDim2.new(1, -320 + (j - 1) * 160, 0.5, -20),
			})
			b.Activated:Connect(function()
				local r = R.BuyCatalyst:InvokeServer(mat.Id, qty)
				if r.Ok then
					UI.FloatText(b, "+" .. qty .. " " .. mat.DisplayName, UI.Colors.Green)
					UI.Play("Pop", 1, 0.5)
				else
					showError(r.Error)
				end
			end)
		end
	end
end
local function refreshShop()
	if not state then
		return
	end
	for id, l in shopOwned do
		local biomeId = Materials.ById[id].SourceBiome
		if state.UnlockedBiomes[biomeId] then
			l.Text = "Owned: " .. (state.Inventory[id] or 0)
			l.TextColor3 = UI.Colors.Gold
		else
			l.Text = "Unlock " .. Biomes.ById[biomeId].DisplayName .. " to buy"
			l.TextColor3 = UI.Colors.Muted
		end
	end
end
shopPanel.OnOpen = refreshShop

-- ===== Lab: upgrades, research, gathering info =====
local labLeft = scrolling(labPanel.Content, { Size = UDim2.new(0.5, -6, 1, 0) })
UI.new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = labLeft })
local labRight = scrolling(labPanel.Content, { Position = UDim2.new(0.5, 6, 0, 0), Size = UDim2.new(0.5, -6, 1, 0) })
UI.new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = labRight })

local function labRow(parent: Instance, order: number, height: number)
	local row = UI.new("Frame", { BackgroundColor3 = UI.Colors.Card, Size = UDim2.new(1, -8, 0, height), LayoutOrder = order, Parent = parent })
	UI.Corner(row, 12)
	UI.Stroke(row, 3)
	return row
end

local function refreshLab()
	if not state then
		return
	end
	clearChildren(labLeft, KEEP_LAYOUT)
	clearChildren(labRight, KEEP_LAYOUT)
	UI.Label(labLeft, "Factory Upgrades", { Size = UDim2.new(1, -8, 0, 30), LayoutOrder = 0, TextColor3 = UI.Colors.Gold })
	for i, u in Progression.Upgrades do
		local level = (state.Upgrades and state.Upgrades[u.Id]) or 0
		local maxLevel = #u.Costs
		local row = labRow(labLeft, i, 104)
		UI.Label(row, string.format("%s  (Lv %d/%d)", u.DisplayName, level, maxLevel), { Size = UDim2.new(1, -20, 0, 26), Position = UDim2.fromOffset(10, 6), TextXAlignment = Enum.TextXAlignment.Left })
		UI.Label(row, "Now: " .. (if level > 0 then u.Describe(level) else "no effect"), { Size = UDim2.new(1, -190, 0, 20), Position = UDim2.fromOffset(10, 36), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = UI.Colors.Muted, MaxTextSize = 16, TextWrapped = true })
		if level < maxLevel then
			UI.Label(row, "Next: " .. u.Describe(level + 1), { Size = UDim2.new(1, -190, 0, 36), Position = UDim2.fromOffset(10, 60), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = UI.Colors.Green, MaxTextSize = 16, TextWrapped = true })
			local cost = u.Costs[level + 1]
			local b = UI.Button(row, UI.FormatNumber(cost) .. " coins", UI.Colors.Green, { Name = "Buy_" .. u.Id, Size = UDim2.fromOffset(160, 44), Position = UDim2.new(1, -170, 0.5, -22) })
			UI.SetDisabled(b, state.Coins < cost)
			b.Activated:Connect(function()
				local r = R.BuyUpgrade:InvokeServer(u.Id)
				if r and r.Ok then
					UI.Toast(u.DisplayName .. " upgraded to Lv " .. r.Level .. "!", UI.Colors.Green)
					UI.Play("Pop", 0.9, 0.6)
				else
					showError(r and r.Error)
				end
			end)
		else
			UI.Label(row, "MAX", { Size = UDim2.fromOffset(160, 40), Position = UDim2.new(1, -170, 0.5, -20), TextColor3 = UI.Colors.Gold })
		end
	end

	UI.Label(labRight, string.format("Research  -  %d RP", state.ResearchPoints or 0), { Size = UDim2.new(1, -8, 0, 30), LayoutOrder = 0, TextColor3 = UI.Colors.Gold })
	UI.Label(labRight, string.format("Earn RP by claiming monsters (Research value x%d) and +%d per new discovery.", Progression.RPPerResearchValue, Progression.RPPerDiscovery), {
		Size = UDim2.new(1, -8, 0, 34), LayoutOrder = 1, TextColor3 = UI.Colors.Muted, TextWrapped = true, MaxTextSize = 16,
	})
	for i, node in Progression.Research do
		local owned = state.Research and state.Research[node.Id]
		local reqMet = true
		for _, req in node.Requires do
			reqMet = reqMet and state.Research[req] == true
		end
		local biomeOk = node.RequiresBiome == nil or state.UnlockedBiomes[node.RequiresBiome]
		local row = labRow(labRight, 10 + i, 96)
		UI.Label(row, node.DisplayName, { Size = UDim2.new(1, -190, 0, 26), Position = UDim2.fromOffset(10, 6), TextXAlignment = Enum.TextXAlignment.Left })
		UI.Label(row, node.Description, { Size = UDim2.new(1, -190, 0, 54), Position = UDim2.fromOffset(10, 34), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = UI.Colors.Muted, TextWrapped = true, MaxTextSize = 16 })
		if owned then
			UI.Label(row, "RESEARCHED", { Size = UDim2.fromOffset(160, 40), Position = UDim2.new(1, -170, 0.5, -20), TextColor3 = UI.Colors.Green })
		else
			local label = if not reqMet then "Needs " .. Progression.ResearchById[node.Requires[1]].DisplayName elseif not biomeOk then "Unlock " .. Biomes.ById[node.RequiresBiome].DisplayName else (node.Cost .. " RP")
			local b = UI.Button(row, label, UI.Colors.Blue, { Name = "Research_" .. node.Id, Size = UDim2.fromOffset(160, 44), Position = UDim2.new(1, -170, 0.5, -22) })
			UI.SetDisabled(b, not (reqMet and biomeOk and (state.ResearchPoints or 0) >= node.Cost))
			b.Activated:Connect(function()
				local r = R.BuyResearch:InvokeServer(node.Id)
				if r and r.Ok then
					UI.Toast("Researched " .. node.DisplayName .. "!", UI.Colors.Blue)
					UI.Play("Pop", 0.8, 0.6)
				else
					showError(r and r.Error)
				end
			end)
		end
	end

	UI.Label(labRight, "Gathering (walk up to a node and hold E)", { Size = UDim2.new(1, -8, 0, 30), LayoutOrder = 50, TextColor3 = UI.Colors.Gold })
	local order = 51
	for _, nodeType in Progression.GatherOrder do
		local node = Progression.GatherNodes[nodeType]
		local lines = { string.format("%s (%s, every %ds): %d-%d %s", node.DisplayName, Biomes.ById[node.Biome].DisplayName, node.Cooldown, node.BaseAmount[1], node.BaseAmount[2], Materials.ById[node.Base].DisplayName) }
		for _, b in node.Bonus do
			table.insert(lines, string.format("   + %s %s chance%s", Materials.ById[b.Material].DisplayName, UI.FormatPercent(b.Chance), if b.Event then (" (" .. Events.ById[b.Event].DisplayName .. " only)") else ""))
		end
		for _, line in lines do
			UI.Label(labRight, line, { Size = UDim2.new(1, -8, 0, 20), LayoutOrder = order, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = UI.Colors.Text, MaxTextSize = 16 })
			order += 1
		end
	end
end
labPanel.OnOpen = refreshLab

NotifyEvent.OnClientEvent:Connect(function(kind, result)
	if kind ~= "Gather" or type(result) ~= "table" then
		return
	end
	if result.Ok then
		local bits = {}
		for mat, n in result.Granted or {} do
			table.insert(bits, "+" .. n .. " " .. (Materials.ById[mat] and Materials.ById[mat].DisplayName or mat))
		end
		UI.Toast(if #bits > 0 then table.concat(bits, ", ") else "Your bag is full for that item.", UI.Colors.Green)
		UI.Play("Pop", 1.3, 0.6)
	elseif result.Error == "Cooldown" then
		UI.Toast(string.format("Already gathered - ready again in %ds", math.ceil(result.ReadyIn or 0)), UI.Colors.Orange)
	else
		showError(result.Error)
	end
end)

-- ===== Zone gates (open locally once the biome is unlocked) =====
local function applyGates()
	if not state then
		return
	end
	for _, barrier in CollectionService:GetTagged("BiomeGate") do
		local open = state.UnlockedBiomes[barrier:GetAttribute("Biome")] == true
		barrier.CanCollide = not open
		barrier.Transparency = if open then 1 else 0.6
		local pr = barrier:FindFirstChildWhichIsA("ProximityPrompt")
		if pr then
			pr.Enabled = not open
		end
	end
end

local function hookGate(barrier: Instance)
	local pr = barrier:FindFirstChildWhichIsA("ProximityPrompt")
	if not pr then
		return
	end
	pr.Triggered:Connect(function()
		local biomeId = barrier:GetAttribute("Biome")
		local r = R.UnlockBiome:InvokeServer(biomeId)
		if r and r.Ok then
			UI.Toast(Biomes.ById[biomeId].DisplayName .. " UNLOCKED! The gate is open.", Biomes.ById[biomeId].Theme.Accent)
			UI.Play("Pop", 0.7, 0.8)
		elseif r and r.Error == "RequirementsNotMet" then
			for _, req in r.Requirements or {} do
				if not req.Met then
					UI.Toast(string.format("Need: %s (%s / %s)", req.Label, UI.FormatNumber(req.Have), UI.FormatNumber(req.Need)), UI.Colors.Orange)
				end
			end
		else
			showError(r and r.Error)
		end
	end)
	applyGates()
end
for _, g in CollectionService:GetTagged("BiomeGate") do
	task.spawn(hookGate, g)
end
CollectionService:GetInstanceAddedSignal("BiomeGate"):Connect(hookGate)

-- ===== Teleport =====
local teleportList = scrolling(teleportPanel.Content, { Size = UDim2.fromScale(1, 1) })
UI.new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = teleportList })
local function refreshTeleport()
	if not state then
		return
	end
	clearChildren(teleportList, KEEP_LAYOUT)
	for i, zone in WorldLayout.Zones do
		local b = Biomes.ById[zone.Biome]
		local unlocked = state.UnlockedBiomes[zone.Biome] == true
		local btn = UI.Button(teleportList, string.format("%d. %s%s", i, b.DisplayName, if unlocked then "" else "  (locked)"), b.Theme.Accent, {
			Name = "TP_" .. zone.Biome, Size = UDim2.new(1, -8, 0, 56), LayoutOrder = i,
		})
		UI.SetDisabled(btn, not unlocked)
		btn.Activated:Connect(function()
			if not unlocked then
				showError("BiomeLocked")
				return
			end
			local r = R.TeleportToBiome:InvokeServer(zone.Biome)
			if r and r.Ok then
				teleportPanel.Close()
				UI.Play("Swoosh", 1.1, 0.5)
			else
				showError(r and r.Error)
			end
		end)
	end
end
teleportPanel.OnOpen = refreshTeleport

-- ===== Claim / reveal =====
-- Auto: hatch when ready and restart the last incubation. Hatches below Epic just
-- toast (Rare is too frequent to stop for); an Epic+ hatch pauses Auto and plays
-- the full reveal.
local AUTO_REVEAL_TIER = 4
local autoOn = false
local autoBtn = UI.Button(chamber, "Auto: Off", UI.Colors.Card, { Name = "AutoButton", Size = UDim2.fromOffset(96, 28), Position = UDim2.new(1, -108, 0, 6) })
local function refreshAuto()
	UI.SetButtonText(autoBtn, if autoOn then "Auto: On" else "Auto: Off")
	autoBtn.BackgroundColor3 = if autoOn then UI.Colors.Green else UI.Colors.Card
end
local function setAuto(on: boolean, reason: string?)
	autoOn = on
	refreshAuto()
	if reason then
		UI.Toast(reason, UI.Colors.Orange)
	end
end

local claiming = false
local function claim(auto: boolean?)
	local egg = readyEgg()
	if claiming or not egg then
		return
	end
	claiming = true
	local resp = R.ClaimIncubation:InvokeServer(egg.OpId)
	claiming = false
	if not resp or not resp.Ok then
		showError(resp and resp.Error)
		if auto then
			setAuto(false)
		end
		return
	end
	-- That egg is gone now; don't wait for the state push to show it.
	for i, inc in state.Incubations do
		if inc.OpId == egg.OpId then
			table.remove(state.Incubations, i)
			break
		end
	end
	local function afterReveal()
		if resp.AutoEquipped then
			UI.Toast(resp.Record.DisplayName .. " hatched and is following you!", UI.Colors.Purple)
		end
		for _, m in resp.Milestones or {} do
			UI.Toast("Milestone: " .. m.Name .. "  +" .. UI.FormatNumber(m.Reward), UI.Colors.Purple)
		end
		if (resp.LevelsGained or 0) > 0 then
			UI.Toast("LEVEL UP! You are now level " .. resp.NewLevel, UI.Colors.Gold)
			UI.Play("Pop", 0.8, 0.7)
		end
	end
	local again = lastSelection
	if (resp.ResearchPoints or 0) > 0 then
		UI.FloatText(levelPill, "+" .. resp.ResearchPoints .. " RP", UI.Colors.Blue)
	end
	if auto then
		local def = Rarity.Get(resp.Record.RarityTier)
		if resp.Record.RarityTier < AUTO_REVEAL_TIER then
			UI.Toast(string.format("Hatched %s (%s)", resp.Record.DisplayName, def.Name), def.Color:Lerp(Color3.new(0, 0, 0), 0.25))
			afterReveal()
			return
		end
		setAuto(false, "Auto paused - " .. def.Name .. " hatch!")
	end
	Reveal.Play(resp, {
		Skip = state.Settings.SkipReveal,
		OnEquip = if resp.AutoEquipped then nil else function()
			equipMonster(resp.Record.MonsterId, resp.Record.DisplayName)
		end,
		OnContinue = afterReveal,
		OnAgain = if again then function()
			afterReveal()
			startIncubation(again)
		end else nil,
		AgainLabel = if again then string.format("Again (%d)", Config.Species[again.SpeciesId].Cost) else nil,
	})
end

autoBtn.Activated:Connect(function()
	if autoOn then
		setAuto(false)
	elseif not lastSelection then
		UI.Toast("Start an incubation first - Auto repeats your last one.", UI.Colors.Orange)
	else
		setAuto(true)
		UI.Play("Pop", 1.2, 0.4)
	end
end)
refreshAuto()

chamberBtn.Activated:Connect(function()
	if not state then
		return
	end
	if readyEgg() then
		claim()
	elseif freeEggSlots() > 0 then
		openOnly(incubatorPanel)
	else
		showError("NotReady")
	end
end)

-- ===== State =====
local displayedCoins = 0
local function setCoins(coins: number, income: number?)
	local gained = coins - displayedCoins
	displayedCoins = coins
	coinLabel.Text = UI.FormatNumber(coins)
	if income then
		incomeLabel.Text = string.format("+%.1f/s", income)
	end
	if gained >= 1 then
		coinScale.Scale = 1.08
		TweenService:Create(coinScale, TweenInfo.new(0.2, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	end
end

local function refreshHud()
	setCoins(state.Coins, state.IncomePerSecond)
	local badges = 0
	for _ in state.Badges or {} do
		badges += 1
	end
	badgeLabel.Text = string.format("BADGES\n%d/%d", badges, #Biomes.List)
	levelLabel.Text = "Level " .. state.Level
	xpBar.Set(state.XP / state.XPToNext, true)
	if not state.SavingEnabled then
		saveLabel.Text = "Not saved\n(test)"
		savePill.BackgroundColor3 = UI.Colors.Orange
	elseif state.SaveStatus == "Failed" then
		saveLabel.Text = "Save\nfailed"
		savePill.BackgroundColor3 = UI.Colors.Red
	elseif state.SaveStatus == "Saved" then
		saveLabel.Text = "Saved"
		savePill.BackgroundColor3 = UI.Colors.Green
	else
		saveLabel.Text = "Saving..."
		savePill.BackgroundColor3 = UI.Colors.Card
	end
	local unseen = 0
	for _ in state.Unseen do
		unseen += 1
	end
	indexBadge.Visible = unseen > 0
	indexBadgeLabel.Text = tostring(unseen)
	local left = state.PityThreshold - state.PityCounter
	pityLabel.Text = if left <= 1 then "Next one is RARE or better!" else string.format("A RARE monster in %d hatches or less!", left)
end

-- ===== Getting Started guide =====
local tutorialApi = TutorialUI.Init({
	Screen = screen,
	R = R,
	ShowError = showError,
	Targets = { Chamber = chamberBtn, HatchMenu = incubateBtn },
	IsBusy = function()
		return BattleUI.Active or Reveal.Active or player:GetAttribute("RevealActive") == true
	end,
})

-- ===== Daily rewards, quests, level-ups =====
local rewardsApi = RewardsUI.Init({
	Screen = screen,
	R = R,
	ShowError = showError,
	CoinTarget = coinPill,
	QuestsButton = questsBtn,
	QuestsBadge = questsBadge,
	QuestsBadgeLabel = questsBadgeLabel,
	DailyButton = dailyBtn,
	QuestsPanel = questsPanel,
	OpenPanel = function(p)
		openOnly(p)
	end,
	IsBusy = function()
		return BattleUI.Active or Reveal.Active or player:GetAttribute("RevealActive") == true
	end,
	WelcomeOpen = function()
		for _, d in screen:GetDescendants() do
			if d:IsA("TextLabel") and d.Text == "Welcome!" then
				return true
			end
		end
		return false
	end,
})

-- ===== Fusion (opened from the Hatch panel) =====
local fusionApi = FusionUI.Init({
	Panel = fusionPanel,
	GetState = function()
		return state
	end,
	R = R,
	ShowError = showError,
	Reveal = Reveal,
})
fuseOpenBtn.Activated:Connect(function()
	openOnly(fusionPanel)
end)

local function applyState(s)
	state = s
	refreshHud()
	if incubatorPanel.IsOpen then
		refreshIncubator()
	end
	if monstersPanel.IsOpen then
		refreshMonsters()
	end
	if indexPanel.IsOpen then
		refreshIndex()
	end
	if shopPanel.IsOpen then
		refreshShop()
	end
	if labPanel.IsOpen then
		refreshLab()
	end
	if teleportPanel.IsOpen then
		refreshTeleport()
	end
	fusionApi.Refresh()
	tutorialApi.Update(s)
	rewardsApi.Update(s)
	applyGates()
end

StateChanged.OnClientEvent:Connect(applyState)
CoinsChanged.OnClientEvent:Connect(function(coins, income)
	if state then
		state.Coins = coins
		state.IncomePerSecond = income
	end
	setCoins(coins, income)
end)

incubateBtn.Activated:Connect(function()
	openOnly(incubatorPanel)
end)
monstersBtn.Activated:Connect(function()
	openOnly(monstersPanel)
end)
indexBtn.Activated:Connect(function()
	openOnly(indexPanel)
end)
shopBtn.Activated:Connect(function()
	openOnly(shopPanel)
end)
labBtn.Activated:Connect(function()
	openOnly(labPanel)
end)
teleportBtn.Activated:Connect(function()
	openOnly(teleportPanel)
end)

-- World props that react to events: any descendant of a biome area with an
-- "EventOnly" attribute (event id) is shown/enabled only during that event.
-- Parts use "EventTransparency" for their visible transparency.
local function setWorldEvents(activeAll: { [string]: number })
	for _, b in Biomes.List do
		local area = workspace:FindFirstChild(b.Id)
		if area then
			for _, d in area:GetDescendants() do
				local ev = d:GetAttribute("EventOnly")
				if ev then
					local on = activeAll[ev] ~= nil
					if d:IsA("ParticleEmitter") or d:IsA("Light") then
						d.Enabled = on
					elseif d:IsA("BasePart") then
						d.Transparency = if on then (d:GetAttribute("EventTransparency") or 0) else 1
					end
				end
			end
		end
	end
end

-- Active events across every biome: { [eventId] = endsAt }.
local function allActiveEvents(now: number)
	local out = {}
	for biomeId in Events.CycleSeconds do
		for id, endsAt in Events.GetActive(biomeId, now) do
			out[id] = endsAt
		end
	end
	return out
end

-- ===== Eggs in your chamber (client-side visuals; results stay secret) =====
-- Each egg sits on an EggSpot in the player's own pod (see WorldBuilder pods);
-- without a pod the first egg falls back to the zone's shared chamber core.
local RunService = game:GetService("RunService")
local MonsterVisuals = require(Shared.MonsterVisuals)
local worldEggs: { [string]: Model } = {} -- [OpId] = egg model

-- The local player's pod (OwnerId attribute set by the server), if any.
local function myPod(): Model?
	for _, pod in CollectionService:GetTagged("PlayerPod") do
		if pod:GetAttribute("OwnerId") == Players.LocalPlayer.UserId then
			return pod :: Model
		end
	end
	return nil
end

-- Where egg number `slot` stands in your pod (no pod yet: no world egg; the
-- chamber widget still shows it).
local function eggAnchor(slot: number): CFrame?
	local pod = myPod()
	local spot = pod and pod:FindFirstChild("EggSpot" .. slot) :: BasePart?
	if spot then
		-- Lift so the egg (3.1 tall) stands on the spot. Its spots and cracks face its
		-- +Z; pods face -Z (toward the spawn), so turn it around.
		return spot.CFrame * CFrame.new(0, 1.3, 0) * CFrame.Angles(0, math.pi, 0)
	end
	return nil
end

local function destroyEgg(opId: string)
	local m = worldEggs[opId]
	if m then
		m:Destroy()
		worldEggs[opId] = nil
	end
end

local function buildWorldEgg(inc, at: CFrame)
	local sp = Species.ById[inc.SpeciesId]
	local spot = MonsterVisuals.Palettes[sp.Palettes[1]] or Color3.fromRGB(120, 200, 120)
	local m = Instance.new("Model")
	m.Name = "IncubatingEgg"
	local function ep(name, shape, size, cf, color, material)
		local p = Instance.new("Part")
		p.Name, p.Shape, p.Size, p.CFrame, p.Color = name, shape, size, cf, color
		p.Material = material or Enum.Material.SmoothPlastic
		p.Anchored, p.CanCollide, p.CanQuery, p.CastShadow = true, false, false, false
		if shape == Enum.PartType.Ball and not (size.X == size.Y and size.Y == size.Z) then
			-- Ball parts are always spheres; a sphere mesh on a block gives a real egg shape.
			p.Shape = Enum.PartType.Block
			p.Size = size
			local mesh = Instance.new("SpecialMesh")
			mesh.MeshType = Enum.MeshType.Sphere
			mesh.Parent = p
		end
		p.Parent = m
		return p
	end
	local egg = ep("Egg", Enum.PartType.Ball, Vector3.new(2.4, 3.1, 2.4), at, Color3.fromRGB(250, 248, 240))
	m.PrimaryPart = egg
	-- Spots and cracks face the egg's +Z, toward where players approach.
	for _, d in { Vector3.new(0.7, 0.6, 0.85), Vector3.new(-0.8, 0.1, 0.7), Vector3.new(0.2, -0.7, 1.0), Vector3.new(-0.3, 1.0, 0.8), Vector3.new(0.9, -0.3, -0.6) } do
		local pos = at:PointToWorldSpace(d)
		ep("Spot", Enum.PartType.Ball, Vector3.new(0.55, 0.45, 0.2), CFrame.lookAt(pos, pos + (pos - at.Position)), spot)
	end
	for i = 1, 4 do
		local crack = ep("Crack", Enum.PartType.Block, Vector3.new(0.06, 0.7, 0.06), at * CFrame.new((i - 2.5) * 0.35, 0.2 + (i % 2) * 0.3, 1.15) * CFrame.Angles(0, 0, (i % 2 == 0) and 0.5 or -0.5), Color3.fromRGB(40, 35, 30))
		crack.Transparency = 1
		crack:SetAttribute("Index", i)
	end
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 240, 200)
	light.Range = 10
	light.Brightness = 0.5
	light.Parent = egg
	local bb = Instance.new("BillboardGui")
	bb.Name = "ReadyTag"
	bb.Size = UDim2.fromOffset(160, 40)
	bb.StudsOffset = Vector3.new(0, 2.6, 0)
	bb.AlwaysOnTop = true
	bb.Enabled = false
	bb.Parent = egg
	UI.Label(bb, "Ready!", { TextColor3 = UI.Colors.Gold })
	m.Parent = workspace
	-- Rest pose of every part relative to the egg, so wobble moves them together.
	for _, p in m:GetChildren() do
		p:SetAttribute("Rest", egg.CFrame:ToObjectSpace(p.CFrame))
	end
	m:SetAttribute("Base", egg.CFrame)
	worldEggs[inc.OpId] = m
end

local function animateEgg(egg: Model, inc, now: number)
	local total = math.max(inc.EndsAt - inc.StartedAt, 1)
	local progress = math.clamp(1 - (inc.EndsAt - now) / total, 0, 1)
	local ready = progress >= 1
	-- Wobble grows as hatching approaches; a ready egg rocks hard and glows.
	local amp = if ready then 0.22 else 0.03 + progress * progress * 0.18
	local speed = if ready then 14 else 6 + progress * 8
	local base = egg:GetAttribute("Base") :: CFrame
	local wobble = base * CFrame.Angles(math.sin(now * speed * 0.7) * amp * 0.5, 0, math.sin(now * speed) * amp)
	for _, p in egg:GetChildren() do
		local rest = p:GetAttribute("Rest")
		if rest then
			p.CFrame = wobble * rest
		end
		if p.Name == "Crack" then
			p.Transparency = if progress >= (p:GetAttribute("Index") :: number) / 5 then 0 else 1
		end
	end
	local eggPart = egg.PrimaryPart :: BasePart
	local light = eggPart:FindFirstChildOfClass("PointLight")
	if light then
		light.Brightness = if ready then 2 + math.sin(now * 6) else 0.5 + progress
	end
	local tag = eggPart:FindFirstChild("ReadyTag") :: BillboardGui?
	if tag then
		tag.Enabled = ready
	end
end

RunService.RenderStepped:Connect(function()
	local eggs = if state then state.Incubations else {}
	local live = {}
	local now = workspace:GetServerTimeNow()
	for slot, inc in eggs do
		live[inc.OpId] = true
		local egg = worldEggs[inc.OpId]
		if not (egg and egg.Parent) then
			local at = eggAnchor(slot)
			if at then
				buildWorldEgg(inc, at)
				egg = worldEggs[inc.OpId]
			end
		end
		if egg then
			animateEgg(egg, inc, now)
		end
	end
	for opId in worldEggs do
		if not live[opId] then
			destroyEgg(opId)
		end
	end
end)

-- Pod prompts: only your own pod's prompt is shown. It hatches a ready egg or
-- opens the incubator.
local claimFromPod: (() -> ())? = nil
-- Your own pod is marked for you only: a gold outline and a bouncing sign.
local myPodMarker: BillboardGui? = nil
local myPodHighlight: Highlight? = nil
local function markMyPod(pod: Model?)
	if myPodMarker then
		myPodMarker:Destroy()
		myPodMarker = nil
	end
	if myPodHighlight then
		myPodHighlight:Destroy()
		myPodHighlight = nil
	end
	if not pod then
		return
	end
	local h = Instance.new("Highlight")
	h.FillTransparency = 1
	h.OutlineColor = UI.Colors.Gold
	h.DepthMode = Enum.HighlightDepthMode.Occluded
	h.Adornee = pod
	h.Parent = pod
	myPodHighlight = h
	local bb = Instance.new("BillboardGui")
	bb.Name = "YourChamberSign"
	bb.Size = UDim2.fromOffset(260, 70)
	bb.StudsOffset = Vector3.new(0, 17, 0)
	bb.AlwaysOnTop = true
	bb.MaxDistance = 250
	bb.Adornee = pod.PrimaryPart
	bb.Parent = pod
	local pill = UI.new("Frame", { BackgroundColor3 = UI.Colors.Gold, Size = UDim2.fromScale(1, 1), Parent = bb })
	UI.Corner(pill, 16)
	UI.Stroke(pill, 4)
	UI.Gloss(pill, UI.Colors.Gold)
	UI.Label(pill, "YOUR CHAMBER!", { Font = UI.TitleFont, Size = UDim2.new(1, -16, 1, -12), Position = UDim2.fromOffset(8, 6) })
	myPodMarker = bb
	task.spawn(function()
		while bb.Parent do
			bb.StudsOffset = Vector3.new(0, 17 + math.abs(math.sin(os.clock() * 3)) * 1.2, 0)
			task.wait(0.03)
		end
	end)
end

local function hookPod(pod: Instance)
	-- Pods stream in whole (Atomic), but wait a moment in case the prompt lags.
	local console = pod:WaitForChild("Console", 10)
	local prompt = console and console:FindFirstChildWhichIsA("ProximityPrompt") or pod:FindFirstChildWhichIsA("ProximityPrompt", true)
	if not prompt then
		return
	end
	local function refresh()
		local mine = pod:GetAttribute("OwnerId") == Players.LocalPlayer.UserId
		prompt.Enabled = mine
		if mine then
			markMyPod(pod :: Model)
		elseif myPodMarker and myPodMarker.Parent == pod then
			markMyPod(nil)
		end
	end
	-- "Open egg!" when one is ready, otherwise "Hatch".
	task.spawn(function()
		while pod.Parent do
			if prompt.Enabled then
				prompt.ActionText = if readyEgg() then "Open egg!" else "Hatch"
			end
			task.wait(0.3)
		end
	end)
	pod:GetAttributeChangedSignal("OwnerId"):Connect(function()
		refresh()
		-- A newly assigned pod: rebuild eggs at its spots.
		for opId in worldEggs do
			destroyEgg(opId)
		end
	end)
	refresh()
	prompt.Triggered:Connect(function()
		if claimFromPod then
			claimFromPod()
		end
	end)
end
for _, pod in CollectionService:GetTagged("PlayerPod") do
	task.spawn(hookPod, pod)
end
CollectionService:GetInstanceAddedSignal("PlayerPod"):Connect(hookPod)

local function fmtTime(s: number): string
	s = math.max(0, math.floor(s))
	return string.format("%d:%02d", s // 60, s % 60)
end

task.spawn(function()
	for _, b in Biomes.List do
		workspace:WaitForChild(b.Id, 5)
	end
	setWorldEvents(allActiveEvents(math.floor(workspace:GetServerTimeNow())))
end)

-- Event banner + transitions (all biomes; events in unlocked biomes are preferred).
local lastEventKey = nil
task.spawn(function()
	while true do
		local now = workspace:GetServerTimeNow()
		local activeAll = allActiveEvents(math.floor(now))
		local shownId, shownEnds, bestScore = nil, nil, -1
		for id, endsAt in activeAll do
			local ev = Events.ById[id]
			local score = if state and state.UnlockedBiomes[ev.Biome] then 2 else 1
			if score > bestScore then
				shownId, shownEnds, bestScore = id, endsAt, score
			end
		end
		local keys = {}
		for id in activeAll do
			table.insert(keys, id)
		end
		table.sort(keys)
		local key = table.concat(keys, ",")
		if shownId then
			local ev = Events.ById[shownId]
			local more = if #keys > 1 then string.format("  (+%d more)", #keys - 1) else ""
			eventLabel.Text = string.format("%s in %s - %s left%s", string.upper(ev.DisplayName), Biomes.ById[ev.Biome].DisplayName, fmtTime(shownEnds - now), more)
			eventBanner.BackgroundColor3 = ev.Color:Lerp(Color3.new(0, 0, 0), 0.45)
		else
			local soonest, soonestAt = nil, math.huge
			for _, ev in Events.List do
				local at = Events.NextStart(ev.Id, math.floor(now))
				if at and at < soonestAt then
					soonest, soonestAt = ev, at
				end
			end
			eventLabel.Text = if soonest then string.format("%s: %s in %s", Biomes.ById[soonest.Biome].DisplayName, soonest.DisplayName, fmtTime(soonestAt - now)) else ""
			eventBanner.BackgroundColor3 = UI.Colors.Card
		end
		if key ~= lastEventKey then
			if lastEventKey ~= nil then
				for id in activeAll do
					if not string.find("," .. lastEventKey .. ",", "," .. id .. ",", 1, true) then
						local ev = Events.ById[id]
						UI.Toast(ev.DisplayName .. " has begun in " .. Biomes.ById[ev.Biome].DisplayName .. "!", ev.Color:Lerp(Color3.new(0, 0, 0), 0.3))
						UI.Play("Pop", 0.8, 0.6)
					end
				end
			end
			lastEventKey = key
			setWorldEvents(activeAll)
			if incubatorPanel.IsOpen and state and state.UnlockedBiomes[BIOME] then
				task.spawn(refreshOdds)
			end
		end
		task.wait(0.25)
	end
end)

-- Chamber widget ticker (countdown + pulsing OPEN button) and the Auto loop.
local autoBusy = false
local function autoStep()
	if not autoOn or autoBusy or claiming or Reveal.Active then
		return
	end
	local ready = readyEgg()
	if not ready and (freeEggSlots() <= 0 or not lastSelection) then
		return
	end
	autoBusy = true
	task.spawn(function()
		if ready then
			claim(true)
		elseif not startIncubation(lastSelection, true) then
			setAuto(false, "Auto stopped.")
		end
		autoBusy = false
	end)
end
task.spawn(function()
	local wasReady = false
	while true do
		task.wait(0.1)
		if state then
			autoStep()
			local now = workspace:GetServerTimeNow()
			local ready = readyEgg()
			-- The egg closest to hatching.
			local soonest = nil
			for _, inc in state.Incubations do
				if not soonest or inc.EndsAt < soonest.EndsAt then
					soonest = inc
				end
			end
			local count = if state.EggSlots > 1 then string.format("  (%d/%d eggs)", #state.Incubations, state.EggSlots) else ""
			if ready then
				chamberTitle.Text = Species.ById[ready.SpeciesId].DisplayName .. " is ready!" .. count
				chamberBar.Set(1)
				UI.SetButtonText(chamberBtn, "OPEN!")
				if not wasReady then
					wasReady = true
					UI.Play("Pop", 1.4, 0.6)
				end
				chamberBtnScale.Scale = 1 + math.abs(math.sin(os.clock() * 4)) * 0.06
			else
				wasReady = false
				if soonest then
					local left = soonest.EndsAt - now
					chamberTitle.Text = string.format("Hatching %s...  %ds%s", Species.ById[soonest.SpeciesId].DisplayName, math.ceil(left), count)
					chamberBar.Set(1 - left / math.max(soonest.EndsAt - soonest.StartedAt, 1))
				else
					chamberTitle.Text = "Make a new monster!"
					chamberBar.Set(0)
				end
				if freeEggSlots() > 0 then
					UI.SetButtonText(chamberBtn, if soonest then "HATCH ANOTHER!" else "HATCH!")
					-- Gentle "press me" pulse so young players always know the next step.
					chamberBtnScale.Scale = 1 + math.abs(math.sin(os.clock() * 2.5)) * 0.04
				else
					UI.SetButtonText(chamberBtn, "Wait...")
					chamberBtnScale.Scale = 1
				end
			end
		end
	end
end)

-- ===== Battles: wild spots and trainers =====
local battleApi
local BattleRules = require(Shared.Battle)
local TrainerDefs = require(Shared.Trainers)
local lastWildSpot: string? = nil
local function setFrozen(frozen: boolean)
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.WalkSpeed = if frozen then 0 else Config.WalkSpeed
		hum.JumpPower = if frozen then 0 else 50
	end
end
battleApi = BattleUI.Init({
	Screen = screen,
	R = R,
	BadgeName = function(biomeId: string): string
		local b = Biomes.ById[biomeId]
		return if b then b.ShortName else biomeId
	end,
	ShowError = function(code: string?, resp: any?)
		if code == "TrainerResting" and resp and resp.Seconds then
			UI.Toast(string.format("This trainer is resting! Come back in %d:%02d", resp.Seconds // 60, resp.Seconds % 60), UI.Colors.Orange)
		else
			showError(code)
		end
	end,
	OnEnd = function(resp)
		setFrozen(false)
		-- A beaten wild monster leaves its spot (for you) until it respawns.
		if resp and resp.Result == "Win" and lastWildSpot then
			for _, spot in CollectionService:GetTagged("WildSpot") do
				if spot:GetAttribute("SpotId") == lastWildSpot then
					spot:SetAttribute("HiddenUntil", workspace:GetServerTimeNow() + BattleRules.WildRespawnSeconds)
				end
			end
		end
		if resp and resp.Result == "Win" and (resp.LevelsGained or 0) > 0 then
			UI.Toast("LEVEL UP! You are now level " .. resp.NewLevel, UI.Colors.Gold)
		end
	end,
})
local function startBattle(kind: string, id: string)
	lastWildSpot = if kind == "Wild" then id else nil
	for _, p in allPanels do
		p.Close()
	end
	battleApi.Start(kind, id)
	if BattleUI.Active then
		setFrozen(true)
	end
end
local function hookBattlePrompt(inst: Instance, kind: string, idAttr: string)
	local prompt = inst:FindFirstChildWhichIsA("ProximityPrompt", true)
	if not prompt then
		return
	end
	prompt.Triggered:Connect(function()
		local id = inst:GetAttribute(idAttr)
		if type(id) == "string" and not BattleUI.Active and not Reveal.Active then
			startBattle(kind, id)
		end
	end)
	-- Trainers show their coin prize, or when it comes back after a win.
	local tr = kind == "Trainer" and TrainerDefs.ById[inst:GetAttribute(idAttr) or ""]
	if tr then
		task.spawn(function()
			while inst.Parent do
				local last = state and state.TrainerWins and state.TrainerWins[tr.Id]
				local left = if last then BattleRules.TrainerCooldownSeconds - (workspace:GetServerTimeNow() - last) else 0
				prompt.ObjectText = if left > 0
					then string.format("Trainer %s - coins in %d:%02d", tr.DisplayName, left // 60, left % 60)
					else string.format("Trainer %s - %d coins", tr.DisplayName, tr.Reward)
				task.wait(1)
			end
		end)
	end
end
for _, spot in CollectionService:GetTagged("WildSpot") do
	hookBattlePrompt(spot, "Wild", "SpotId")
end
CollectionService:GetInstanceAddedSignal("WildSpot"):Connect(function(spot)
	hookBattlePrompt(spot, "Wild", "SpotId")
end)
for _, npc in CollectionService:GetTagged("Trainer") do
	hookBattlePrompt(npc, "Trainer", "TrainerId")
end
CollectionService:GetInstanceAddedSignal("Trainer"):Connect(function(npc)
	task.defer(hookBattlePrompt, npc, "Trainer", "TrainerId")
end)

-- ===== Player vs player =====
-- Walk up to another player and press "Battle!" to challenge them; they get a
-- popup to accept. The battle itself runs through BattleUI (OnPush).
local BattlePush = Remotes:WaitForChild("Battle") :: RemoteEvent

local challengePopup = UI.new("Frame", {
	Name = "ChallengePopup",
	AnchorPoint = Vector2.new(0.5, 0),
	BackgroundColor3 = UI.Colors.Panel,
	Position = UDim2.new(0.5, 0, 0, 180),
	Size = UDim2.fromOffset(440, 170),
	Visible = false,
	ZIndex = 30,
	Parent = screen,
})
UI.Corner(challengePopup, 18)
UI.Stroke(challengePopup, 5)
UI.Gloss(challengePopup, UI.Colors.Panel)
local challengeScale = UI.new("UIScale", { Parent = challengePopup })
local challengeText = UI.Label(challengePopup, "", { Font = UI.TitleFont, Size = UDim2.new(1, -20, 0, 50), Position = UDim2.fromOffset(10, 10), ZIndex = 31 })
local challengeBar = UI.Bar(challengePopup, UI.Colors.Gold, { Size = UDim2.new(1, -40, 0, 12), Position = UDim2.fromOffset(20, 66), ZIndex = 31 })
local acceptBtn = UI.Button(challengePopup, "BATTLE!", UI.Colors.Green, { Size = UDim2.new(0.5, -25, 0, 58), Position = UDim2.fromOffset(20, 94), ZIndex = 31 })
local declineBtn = UI.Button(challengePopup, "No thanks", UI.Colors.Red, { Size = UDim2.new(0.5, -25, 0, 58), Position = UDim2.new(0.5, 5, 0, 94), ZIndex = 31 })
local pendingChallenge = nil -- { FromUserId, EndsAt }

local function closeChallenge()
	pendingChallenge = nil
	challengePopup.Visible = false
end
local function answerChallenge(accept: boolean)
	local c = pendingChallenge
	closeChallenge()
	if not c then
		return
	end
	local r = R.RespondChallenge:InvokeServer(c.FromUserId, accept)
	if not r or not r.Ok then
		showError(r and r.Error)
	end
end
acceptBtn.Activated:Connect(function()
	answerChallenge(true)
end)
declineBtn.Activated:Connect(function()
	answerChallenge(false)
end)
task.spawn(function()
	while true do
		task.wait(0.1)
		local c = pendingChallenge
		if c then
			local left = c.EndsAt - os.clock()
			challengeBar.Set(math.max(0, left / c.Seconds))
			if left <= 0 then
				closeChallenge()
			end
		end
	end
end)

BattlePush.OnClientEvent:Connect(function(msg)
	if type(msg) ~= "table" then
		return
	end
	if msg.Kind == "Challenge" then
		if BattleUI.Active or Reveal.Active then
			return -- busy: it just times out
		end
		pendingChallenge = { FromUserId = msg.FromUserId, Seconds = msg.Seconds or 20, EndsAt = os.clock() + (msg.Seconds or 20) }
		challengeText.Text = msg.FromName .. " wants to battle!"
		challengePopup.Visible = true
		challengeScale.Scale = 0.4
		TweenService:Create(challengeScale, TweenInfo.new(0.3, Enum.EasingStyle.Back), { Scale = 1 }):Play()
		UI.Play("Pop", 1.2, 0.7)
	elseif msg.Kind == "Declined" then
		UI.Toast(msg.Name .. " said no thanks this time.", UI.Colors.Orange)
	elseif msg.Kind == "Start" then
		closeChallenge()
		for _, p in allPanels do
			p.Close()
		end
		lastWildSpot = nil
		battleApi.OnPush(msg)
		setFrozen(true)
	else
		battleApi.OnPush(msg)
	end
end)

-- A "Battle!" prompt on every other player's character (made locally, so only
-- you see prompts for others).
local function addChallengePrompt(other: Player, character: Model)
	if other == player then
		return
	end
	local rootPart = character:WaitForChild("HumanoidRootPart", 10)
	if not rootPart then
		return
	end
	local pr = Instance.new("ProximityPrompt")
	pr.Name = "ChallengePrompt"
	pr.ActionText = "Battle!"
	pr.ObjectText = "Challenge " .. other.DisplayName
	pr.HoldDuration = 0.4
	pr.MaxActivationDistance = 12
	pr.RequiresLineOfSight = false
	pr.Parent = rootPart
	pr.Triggered:Connect(function()
		if BattleUI.Active or Reveal.Active then
			return
		end
		local r = R.ChallengePlayer:InvokeServer(other)
		if r and r.Ok then
			UI.Toast("Challenge sent to " .. other.DisplayName .. "! Waiting for an answer...", UI.Colors.Purple)
		else
			showError(r and r.Error)
		end
	end)
end
local function watchPlayer(other: Player)
	other.CharacterAdded:Connect(function(c)
		addChallengePrompt(other, c)
	end)
	if other.Character then
		task.spawn(addChallengePrompt, other, other.Character)
	end
end
for _, p in Players:GetPlayers() do
	watchPlayer(p)
end
Players.PlayerAdded:Connect(watchPlayer)

-- Your own pod: open a ready egg, or open the incubator to start one.
claimFromPod = function()
	if readyEgg() then
		claim()
	elseif not incubatorPanel.IsOpen then
		openOnly(incubatorPanel)
	end
end

-- Initial state.
task.spawn(function()
	for _ = 1, 20 do
		local resp = R.GetState:InvokeServer()
		if resp and resp.Ok and resp.State then
			applyState(resp.State)
			if not resp.State.SavingEnabled then
				UI.Toast("Test mode: progress is NOT saved in this session.", UI.Colors.Orange)
			end
			return
		end
		task.wait(1)
	end
end)
