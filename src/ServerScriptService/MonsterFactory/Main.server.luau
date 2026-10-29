-- Monster Factory server entry point: wires services to remotes.
-- Every remote is rate limited and every argument is validated by the service.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local Shared = ReplicatedStorage.MonsterFactory.Shared
local Services = script.Parent.Services
local Config = require(Shared.Config)
local Registry = require(Shared.Registry)

local MutationService = require(Services.MutationService)
local MonsterGenerationService = require(Services.MonsterGenerationService)
local PlayerDataService = require(Services.PlayerDataService)
local EconomyService = require(Services.EconomyService)
local IncubationService = require(Services.IncubationService)
local DiscoveryService = require(Services.DiscoveryService)
local BiomeService = require(Services.BiomeService)
local ProgressionService = require(Services.ProgressionService)
local Progression = require(Shared.Progression)
local WorldLayout = require(Shared.WorldLayout)

local mutation = MutationService.new(Registry)
local generation = MonsterGenerationService.new(Registry, mutation)
PlayerDataService.Init({ Generation = generation })
local economy = EconomyService.new({ PlayerData = PlayerDataService })
local biomes = BiomeService.new({ PlayerData = PlayerDataService })
local progression = ProgressionService.new({ PlayerData = PlayerDataService })
local incubation = IncubationService.new({
	PlayerData = PlayerDataService,
	Generation = generation,
	Mutation = mutation,
	Economy = economy,
})

-- Remotes ---------------------------------------------------------------
local remotesFolder = ReplicatedStorage.MonsterFactory.Remotes
remotesFolder:ClearAllChildren()
local function remote(className: string, name: string)
	local r = Instance.new(className)
	r.Name = name
	r.Parent = remotesFolder
	return r
end
local StateChanged = remote("RemoteEvent", "StateChanged")
local CoinsChanged = remote("RemoteEvent", "CoinsChanged")
local Notify = remote("RemoteEvent", "Notify")

-- Sliding-window rate limiter per player per action.
local calls: { [Player]: { [string]: { number } } } = {}
local function allowed(player: Player, action: string): boolean
	local limit = Config.RateLimits[action]
	if not limit then
		return false
	end
	local max, window = limit[1], limit[2]
	calls[player] = calls[player] or {}
	local list = calls[player][action] or {}
	calls[player][action] = list
	local now = os.clock()
	while list[1] and now - list[1] > window do
		table.remove(list, 1)
	end
	if #list >= max then
		return false
	end
	table.insert(list, now)
	return true
end

-- Client view of a player's state (no hidden incubation result, no internals).
local function buildState(player: Player)
	local profile = PlayerDataService.Get(player)
	if not profile then
		return nil
	end
	local d = profile.Data
	local monsters = {}
	for _, rec in d.Monsters do
		table.insert(monsters, rec)
	end
	return {
		Coins = d.Coins,
		Level = d.Level,
		XP = d.XP,
		XPToNext = Config.XPToNext(d.Level),
		Monsters = monsters,
		Locked = d.Locked,
		Equipped = d.Equipped,
		ResearchPoints = d.ResearchPoints,
		Research = d.Research,
		Upgrades = d.Upgrades,
		GatherCooldowns = d.GatherCooldowns,
		IncubationSeconds = ProgressionService.IncubationSeconds(d),
		EarningSlots = ProgressionService.EarningSlots(d),
		Inventory = d.Inventory,
		UnlockedBiomes = d.UnlockedBiomes,
		Discoveries = d.Discoveries,
		Unseen = d.Unseen,
		Milestones = d.Milestones,
		Incubation = incubation:PublicState(d),
		PityCounter = d.PityCounter,
		PityThreshold = Config.PityThreshold,
		IncomePerSecond = economy:GetIncome(player),
		Settings = d.Settings,
		BiomeRequirements = (function()
			local out = {}
			for _, b in Registry.Biomes.List do
				if not d.UnlockedBiomes[b.Id] then
					local met, reqs = BiomeService.GetRequirements(d, b.Id)
					out[b.Id] = { Met = met, Requirements = reqs }
				end
			end
			return out
		end)(),
		SaveStatus = profile.SaveStatus,
		SavingEnabled = PlayerDataService.SavingEnabled,
		ServerTime = os.time(),
	}
end

-- Batch state pushes: at most one full push per player per frame.
local pendingPush: { [Player]: boolean } = {}
PlayerDataService.OnChanged(function(player, what)
	if what == "Coins" then
		local profile = PlayerDataService.Get(player)
		if profile then
			CoinsChanged:FireClient(player, profile.Data.Coins, economy:GetIncome(player))
		end
		return
	end
	if pendingPush[player] then
		return
	end
	pendingPush[player] = true
	task.defer(function()
		pendingPush[player] = nil
		if player.Parent then
			local state = buildState(player)
			if state then
				StateChanged:FireClient(player, state)
			end
		end
	end)
end)

local function bind(name: string, handler: (Player, ...any) -> any)
	local rf = remote("RemoteFunction", name)
	rf.OnServerInvoke = function(player, ...)
		if not allowed(player, name) then
			return { Ok = false, Error = "RateLimited" }
		end
		if not PlayerDataService.Get(player) then
			return { Ok = false, Error = "NotLoaded" }
		end
		local ok, result = pcall(handler, player, ...)
		if not ok then
			warn("[MonsterFactory] " .. name .. " error: " .. tostring(result))
			return { Ok = false, Error = "ServerError" }
		end
		return result
	end
end

bind("GetState", function(player)
	return { Ok = true, State = buildState(player) }
end)
bind("GetOdds", function(player, payload)
	return incubation:GetOdds(player, payload)
end)
bind("StartIncubation", function(player, payload)
	return incubation:Start(player, payload)
end)
bind("ClaimIncubation", function(player, opId)
	return incubation:Claim(player, opId)
end)
bind("SellMonster", function(player, monsterId)
	return economy:Sell(player, monsterId)
end)
bind("ToggleLock", function(player, monsterId)
	return economy:ToggleLock(player, monsterId)
end)
bind("BuyCatalyst", function(player, materialId, quantity)
	return economy:BuyCatalyst(player, materialId, quantity)
end)
bind("MarkSeen", function(player, seenKey)
	local profile = PlayerDataService.Get(player)
	if DiscoveryService.MarkSeen(profile.Data, seenKey) then
		PlayerDataService.MarkDirty(player, "All")
	end
	return { Ok = true }
end)
bind("BuyUpgrade", function(player, id)
	local r = progression:BuyUpgrade(player, id)
	if r.Ok then
		economy:InvalidateIncome(player)
	end
	return r
end)
bind("BuyResearch", function(player, id)
	return progression:BuyResearch(player, id)
end)
bind("TeleportToBiome", function(player, biomeId)
	local zone = type(biomeId) == "string" and WorldLayout.ByBiome[biomeId]
	if not zone then
		return { Ok = false, Error = "UnknownBiome" }
	end
	if not PlayerDataService.Get(player).Data.UnlockedBiomes[biomeId] then
		return { Ok = false, Error = "BiomeLocked" }
	end
	local char = player.Character
	if not (char and char.PrimaryPart) then
		return { Ok = false, Error = "NoCharacter" }
	end
	char:PivotTo(CFrame.new(zone.Spawn))
	return { Ok = true }
end)
bind("EquipMonster", function(player, monsterId)
	return economy:Equip(player, monsterId)
end)
bind("UnlockBiome", function(player, biomeId)
	return biomes:Unlock(player, biomeId)
end)
bind("SetSetting", function(player, name, value)
	local profile = PlayerDataService.Get(player)
	if name == "SkipReveal" and type(value) == "boolean" then
		profile.Data.Settings.SkipReveal = value
		PlayerDataService.MarkDirty(player, "All")
		return { Ok = true }
	end
	return { Ok = false, Error = "BadSetting" }
end)

-- Player lifecycle -------------------------------------------------------
local function onPlayerAdded(player: Player)
	local profile, err = PlayerDataService.Load(player)
	if not profile then
		if player.Parent then
			player:Kick(err)
		end
		return
	end
	economy:PublishEquipped(player)
	local status = profile.SaveStatus
	PlayerDataService.MarkDirty(player, "All")
	-- Initial push only; nothing new to save yet.
	profile.Dirty = false
	profile.SaveStatus = status
end
Players.PlayerAdded:Connect(onPlayerAdded)
for _, p in Players:GetPlayers() do
	task.spawn(onPlayerAdded, p)
end
Players.PlayerRemoving:Connect(function(player)
	calls[player] = nil
	pendingPush[player] = nil
	economy:ForgetPlayer(player)
end)

economy:StartIncomeLoop(Players)

-- Locked-zone guard: gate barriers only open on the client, so the server sends
-- anyone found inside a zone they haven't unlocked back to their last allowed zone.
local lastAllowed: { [Player]: string } = {}
task.spawn(function()
	while true do
		task.wait(1)
		for _, player in Players:GetPlayers() do
			local profile = PlayerDataService.Get(player)
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if profile and root then
				local zone = WorldLayout.ZoneAt(root.Position)
				if zone then
					if profile.Data.UnlockedBiomes[zone.Biome] then
						lastAllowed[player] = zone.Biome
					else
						local back = WorldLayout.ByBiome[lastAllowed[player] or "VerdantMeadows"]
						player.Character:PivotTo(CFrame.new(back.Spawn))
					end
				end
			end
		end
	end
end)
Players.PlayerRemoving:Connect(function(player)
	lastAllowed[player] = nil
end)

-- World gather nodes: server-side prompts, validated by ProgressionService.
local gatherBusy: { [Player]: boolean } = {}
local function hookNode(node: Instance)
	if not node:IsA("BasePart") or not node:GetAttribute("NodeType") then
		return
	end
	local prompt = node:FindFirstChildWhichIsA("ProximityPrompt")
	if not prompt then
		return
	end
	prompt.Triggered:Connect(function(player)
		if gatherBusy[player] or not allowed(player, "Gather") then
			return
		end
		gatherBusy[player] = true
		local ok, result = pcall(progression.Gather, progression, player, node)
		gatherBusy[player] = nil
		if ok then
			Notify:FireClient(player, "Gather", result)
		end
	end)
end
local nodesFolder = workspace:FindFirstChild("GatherNodes")
if nodesFolder then
	for _, n in nodesFolder:GetDescendants() do
		hookNode(n)
	end
	nodesFolder.DescendantAdded:Connect(function(n)
		task.defer(hookNode, n)
	end)
end

-- Studio-only test hook for automated integration tests (never in live servers).
if RunService:IsStudio() then
	local hook = ServerStorage:FindFirstChild("MonsterFactoryTestHook") or Instance.new("BindableFunction")
	hook.Name = "MonsterFactoryTestHook"
	hook.Parent = ServerStorage
	hook.OnInvoke = function(cmd, ...)
		if cmd == "Data" then
			local p = ...
			local profile = PlayerDataService.Get(p)
			return profile and profile.Data
		elseif cmd == "SetCoins" then
			local p, n = ...
			PlayerDataService.Get(p).Data.Coins = n
			PlayerDataService.MarkDirty(p, "All")
			return true
		elseif cmd == "FastForward" then
			local p = ...
			local inc = PlayerDataService.Get(p).Data.Incubation
			if inc then
				inc.EndsAt = os.time()
			end
			return inc ~= nil
		elseif cmd == "GrantTestMonster" then
			-- Visual testing only: a monster with chosen mutations.
			local p, speciesId, mutationIds = ...
			local sp = Registry.Species.ById[speciesId]
			local rec = generation:Generate(p.UserId, { SpeciesId = speciesId, BiomeId = sp.HomeBiome }, Random.new(), { OriginMethod = "StudioTest" })
			local muts = {}
			for _, id in mutationIds do
				table.insert(muts, Registry.Mutations.ById[id])
			end
			rec.ActiveMutations = mutationIds
			rec.Genes = generation:BuildGenes(sp, muts, Random.new())
			rec.Stats = generation:ComputeStats(sp, mutationIds)
			local top = 1
			for _, m in muts do
				top = math.max(top, m.RarityTier)
			end
			rec.RarityTier = top
			PlayerDataService.Get(p).Data.Monsters[rec.MonsterId] = rec
			economy:InvalidateIncome(p)
			PlayerDataService.MarkDirty(p, "All")
			return rec.MonsterId
		elseif cmd == "SetLevel" then
			local p, n = ...
			PlayerDataService.Get(p).Data.Level = n
			PlayerDataService.MarkDirty(p, "All")
			return true
		elseif cmd == "SavingEnabled" then
			return PlayerDataService.SavingEnabled, PlayerDataService.FallbackReason
		end
		return nil
	end
end

print("[MonsterFactory] server ready. Saving enabled:", PlayerDataService.SavingEnabled)
