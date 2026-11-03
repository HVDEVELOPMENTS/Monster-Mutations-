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
local FusionService = require(Services.FusionService)
local BattleService = require(Services.BattleService)
local RewardsService = require(Services.RewardsService)
local Trainers = require(Shared.Trainers)
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
local fusion = FusionService.new({
	PlayerData = PlayerDataService,
	Generation = generation,
	Mutation = mutation,
	Economy = economy,
	Incubation = incubation,
})
local rewards = RewardsService.new({ PlayerData = PlayerDataService })
local battle = BattleService.new({
	PlayerData = PlayerDataService,
	Generation = generation,
	Economy = economy,
	Incubation = incubation,
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
local BattlePush = remote("RemoteEvent", "Battle") -- PvP: challenges, starts and turns

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
		PetSlots = ProgressionService.PetSlots(d),
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
		Incubations = incubation:PublicState(d),
		EggSlots = ProgressionService.EggSlots(d),
		EggSlotLevels = Config.EggSlotLevels,
		PityCounter = d.PityCounter,
		PityThreshold = Config.PityThreshold,
		Battles = d.Battles,
		TrainerWins = d.TrainerWins,
		Badges = d.Badges,
		Stats = d.Stats,
		TutorialRewarded = d.TutorialRewarded,
		Rewards = RewardsService.PublicState(d, player.UserId, os.time()),
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

-- Leaderboard (player list): Coins, Monsters owned, best rarity owned. Display only;
-- the profile stays the source of truth.
local Rarity = require(Shared.Rarity)
local function updateLeaderstats(player: Player, coinsOnly: boolean?)
	local profile = PlayerDataService.Get(player)
	local stats = player:FindFirstChild("leaderstats")
	if not profile or not stats then
		return
	end
	local d = profile.Data
	stats.Coins.Value = math.floor(d.Coins)
	if coinsOnly then
		return
	end
	local count, best = 0, 0
	for _, rec in d.Monsters do
		count += 1
		best = math.max(best, rec.RarityTier)
	end
	stats.Monsters.Value = count
	stats.Best.Value = if best > 0 then Rarity.Get(best).Name else "-"
end
local function makeLeaderstats(player: Player)
	local stats = Instance.new("Folder")
	stats.Name = "leaderstats"
	for _, v in { { "IntValue", "Coins" }, { "IntValue", "Monsters" }, { "StringValue", "Best" } } do
		local value = Instance.new(v[1])
		value.Name = v[2]
		value.Parent = stats
	end
	stats.Parent = player
end

-- Batch state pushes: at most one full push per player per frame.
local pendingPush: { [Player]: boolean } = {}
PlayerDataService.OnChanged(function(player, what)
	if typeof(player) ~= "Instance" then
		return -- the Studio PvP test bot has no client
	end
	if what == "Coins" then
		local profile = PlayerDataService.Get(player)
		if profile then
			CoinsChanged:FireClient(player, profile.Data.Coins, economy:GetIncome(player))
			updateLeaderstats(player, true)
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
				updateLeaderstats(player)
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
bind("SellBulk", function(player, maxTier, preview)
	return economy:SellBulk(player, maxTier, preview)
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
bind("EquipMonster", function(player, monsterId, on)
	return economy:Equip(player, monsterId, on)
end)
bind("ClaimDaily", function(player)
	return rewards:ClaimDaily(player)
end)
bind("ClaimQuest", function(player, questId)
	return rewards:ClaimQuest(player, questId)
end)
bind("ClaimTutorialReward", function(player)
	return economy:ClaimTutorialReward(player)
end)
bind("FuseMonsters", function(player, idA, idB, preview)
	return fusion:Fuse(player, idA, idB, preview)
end)
bind("StartBattle", function(player, kind, id)
	return battle:Start(player, kind, id)
end)
bind("BattleAction", function(player, battleId, action)
	return battle:Act(player, battleId, action)
end)
bind("ChallengePlayer", function(player, target)
	return battle:Challenge(player, target)
end)
bind("RespondChallenge", function(player, fromUserId, accept)
	return battle:Respond(player, fromUserId, accept)
end)
battle.Push = function(player: Player, message)
	if typeof(player) == "Instance" then -- the Studio test bot has no client
		BattlePush:FireClient(player, message)
	end
end
task.spawn(function()
	while true do
		task.wait(1)
		local ok, err = pcall(battle.Tick, battle)
		if not ok then
			warn("[MonsterFactory] battle tick: " .. tostring(err))
		end
	end
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
	if name == "TutorialHidden" and type(value) == "boolean" then
		profile.Data.Settings.TutorialHidden = value
		PlayerDataService.MarkDirty(player, "All")
		return { Ok = true }
	end
	return { Ok = false, Error = "BadSetting" }
end)

-- Player lifecycle -------------------------------------------------------
game:GetService("StarterPlayer").CharacterWalkSpeed = Config.WalkSpeed
local function onCharacter(character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
	if humanoid then
		humanoid.WalkSpeed = Config.WalkSpeed
	end
end
local function onPlayerAdded(player: Player)
	makeLeaderstats(player)
	-- The default above only covers characters spawned after this script ran.
	player.CharacterAdded:Connect(onCharacter)
	if player.Character then
		task.spawn(onCharacter, player.Character)
	end
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
-- Personal chambers: each player gets the lowest free pod on the meadow wall
-- (WorldBuilder "PlayerPods"). The pod's OwnerId and sign tell every client
-- whose it is; only the owner's client enables its prompt and shows its eggs.
local function setPodSign(pod: Instance, text: string)
	local sign = pod:FindFirstChild("Sign")
	for _, d in (if sign then sign:GetDescendants() else {}) do
		if d:IsA("TextLabel") then
			d.Text = text
		end
	end
end
local function podList(): { Instance }
	local folder = workspace:FindFirstChild("PlayerPods")
	local pods = if folder then folder:GetChildren() else {}
	table.sort(pods, function(a, b)
		return (a:GetAttribute("PodIndex") or 0) < (b:GetAttribute("PodIndex") or 0)
	end)
	return pods
end
-- Players (re)spawn standing in front of their own pod, facing it.
local function spawnAtPod(player: Player, character: Model, pod: Model)
	local base = pod.PrimaryPart
	if not base then
		return
	end
	local front = base.Position + Vector3.new(0, 3, -14)
	task.defer(function()
		if character.Parent and pod:GetAttribute("OwnerId") == player.UserId then
			character:PivotTo(CFrame.lookAt(front, Vector3.new(base.Position.X, front.Y, base.Position.Z)))
		end
	end)
end
local function assignPod(player: Player)
	for _, pod in podList() do
		if pod:GetAttribute("OwnerId") == nil then
			pod:SetAttribute("OwnerId", player.UserId)
			player:SetAttribute("Pod", pod:GetAttribute("PodIndex"))
			setPodSign(pod, string.upper(player.DisplayName) .. "'S CHAMBER")
			player.CharacterAdded:Connect(function(character)
				spawnAtPod(player, character, pod)
			end)
			if player.Character then
				spawnAtPod(player, player.Character, pod)
			end
			return
		end
	end
end
local function releasePod(player: Player)
	for _, pod in podList() do
		if pod:GetAttribute("OwnerId") == player.UserId then
			pod:SetAttribute("OwnerId", nil)
			setPodSign(pod, "FREE CHAMBER")
		end
	end
end

Players.PlayerAdded:Connect(assignPod)
Players.PlayerAdded:Connect(onPlayerAdded)
for _, p in Players:GetPlayers() do
	task.spawn(assignPod, p)
	task.spawn(onPlayerAdded, p)
end
Players.PlayerRemoving:Connect(function(player)
	calls[player] = nil
	pendingPush[player] = nil
	economy:ForgetPlayer(player)
	releasePod(player)
	battle:Forget(player)
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

-- Battle spots (WorldBuilder "BattleSpots"): wild spots and trainer stages.
-- Prompts are handled by the client, which calls StartBattle; the server checks
-- the player is standing near the spot it names.
battle.PositionOf = function(player: Player): Vector3?
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	return root and root.Position
end
local CollectionService = game:GetService("CollectionService")
for _, spot in CollectionService:GetTagged("WildSpot") do
	battle.Spots.Wild[spot:GetAttribute("SpotId")] = {
		Biome = spot:GetAttribute("Biome"),
		Species = spot:GetAttribute("WildSpecies"),
		Position = spot.Position,
	}
end
-- Trainers: living NPCs, one per stage, shirt in the trainer's colour. They
-- stroll around their stage, stop to face anyone who comes close and wave hello
-- (server-side, so every player sees the same thing). Animations are Roblox's
-- standard R15 idle/walk/wave.
local TRAINER_ANIMS = {
	Idle = "rbxassetid://507766666",
	Walk = "rbxassetid://507777826",
	Wave = "rbxassetid://507770239",
}
local TRAINER_WANDER = 7 -- studs from the stage centre
local TRAINER_NOTICE = 22 -- studs: stop and face a player this close
local trainerFolder = Instance.new("Folder")
trainerFolder.Name = "Trainers"
trainerFolder.Parent = workspace
local liveTrainers = {}

local function spawnTrainer(tr, stage: BasePart)
	local top = stage.Position + Vector3.new(0, 0.4, 0)
	local desc = Instance.new("HumanoidDescription")
	local skin = Color3.fromRGB(234, 184, 146)
	desc.HeadColor = skin
	desc.LeftArmColor, desc.RightArmColor = tr.Shirt, tr.Shirt
	desc.TorsoColor = tr.Shirt
	desc.LeftLegColor, desc.RightLegColor = Color3.fromRGB(45, 50, 70), Color3.fromRGB(45, 50, 70)
	local ok, npc = pcall(function()
		return Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
	end)
	if not ok or not npc then
		warn("[MonsterFactory] trainer avatar failed: " .. tostring(npc))
		return
	end
	npc.Name = "Trainer_" .. tr.Id
	local humanoid = npc:FindFirstChildOfClass("Humanoid") :: Humanoid
	humanoid.DisplayName = "Trainer " .. tr.DisplayName
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Viewer
	humanoid.WalkSpeed = 7
	local rootPart = npc.PrimaryPart :: BasePart
	local face = Vector3.new(stage:GetAttribute("Facing") or 1, 0, 0)
	local height = humanoid.HipHeight + rootPart.Size.Y / 2
	npc:PivotTo(CFrame.lookAt(top + Vector3.new(0, height, 0), top + Vector3.new(0, height, 0) + face))
	local pr = Instance.new("ProximityPrompt")
	pr.ActionText = "Battle!"
	pr.ObjectText = "Trainer " .. tr.DisplayName
	pr.MaxActivationDistance = 14
	pr.RequiresLineOfSight = false
	pr.Parent = rootPart
	npc:SetAttribute("TrainerId", tr.Id)
	npc.ModelStreamingMode = Enum.ModelStreamingMode.Atomic -- prompt arrives with the model
	CollectionService:AddTag(npc, "Trainer")
	npc.Parent = trainerFolder
	pcall(function()
		rootPart:SetNetworkOwner(nil) -- the server drives them
	end)

	local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator")
	animator.Parent = humanoid
	local tracks = {}
	for name, id in TRAINER_ANIMS do
		local a = Instance.new("Animation")
		a.AnimationId = id
		local okLoad, track = pcall(animator.LoadAnimation, animator, a)
		if okLoad then
			tracks[name] = track
		end
	end
	if tracks.Idle then
		tracks.Idle.Looped = true
		tracks.Idle:Play()
	end
	if tracks.Walk then
		tracks.Walk.Looped = true
	end
	humanoid.Running:Connect(function(speed)
		if not tracks.Walk then
			return
		end
		if speed > 0.5 and not tracks.Walk.IsPlaying then
			tracks.Walk:Play(0.2)
		elseif speed <= 0.5 and tracks.Walk.IsPlaying then
			tracks.Walk:Stop(0.2)
		end
	end)
	table.insert(liveTrainers, {
		Npc = npc,
		Humanoid = humanoid,
		Root = rootPart,
		Home = top,
		Tracks = tracks,
		NextWander = os.clock() + math.random() * 4,
		Greeted = {} :: { [Player]: number },
	})
	-- Battles are checked against the trainer's live position.
	battle.Spots.Trainer[tr.Id] = { Position = top, Live = rootPart }
end

for _, stage in CollectionService:GetTagged("TrainerSpot") do
	local tr = Trainers.ById[stage:GetAttribute("TrainerId")]
	if tr then
		battle.Spots.Trainer[tr.Id] = { Position = stage.Position + Vector3.new(0, 0.4, 0) }
		task.spawn(spawnTrainer, tr, stage)
	end
end

-- Trainer brains: face and greet nearby players, otherwise wander.
task.spawn(function()
	while true do
		task.wait(0.25)
		local now = os.clock()
		for _, t in liveTrainers do
			if not t.Npc.Parent then
				continue
			end
			local pos = t.Root.Position
			local nearest, nearestDist = nil, TRAINER_NOTICE
			for _, player in Players:GetPlayers() do
				local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
				if root then
					local d = (root.Position - pos).Magnitude
					if d < nearestDist then
						nearest, nearestDist = player, d
					end
				end
			end
			if nearest then
				-- Stop, turn to the player, wave the first time they come by.
				t.Humanoid:MoveTo(pos)
				local target = (nearest.Character :: Model).HumanoidRootPart.Position
				local flat = Vector3.new(target.X, pos.Y, target.Z)
				if (flat - pos).Magnitude > 0.5 then
					t.Root.CFrame = t.Root.CFrame:Lerp(CFrame.lookAt(pos, flat), 0.35)
				end
				local last = t.Greeted[nearest]
				if (not last or now - last > 30) and t.Tracks.Wave then
					t.Greeted[nearest] = now
					t.Tracks.Wave:Play(0.15)
				end
				t.NextWander = now + 3
			elseif now >= t.NextWander then
				local a = math.random() * math.pi * 2
				local r = math.random() * TRAINER_WANDER
				t.Humanoid:MoveTo(t.Home + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r))
				t.NextWander = now + 3 + math.random() * 4
			end
		end
	end
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
local testBot = nil -- fake PvP opponent, see "PvPBot"
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
			local eggs = PlayerDataService.Get(p).Data.Incubations
			for _, inc in eggs do
				inc.EndsAt = os.time()
			end
			return #eggs > 0
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
		elseif cmd == "PvPBot" then
			-- Solo Play can't have two players: a fake "TestBot" player (memory only)
			-- challenges p through the real PvP code, so p's client gets the popup.
			local p, species = ...
			local bot = testBot
			if not bot then
				bot = { UserId = -777, Name = "TestBot", DisplayName = "TestBot", Parent = workspace }
				testBot = bot
				PlayerDataService.Load(bot :: any)
				local isPlayer = battle.IsPlayer
				battle.IsPlayer = function(x)
					return x == bot or isPlayer(x)
				end
			end
			local data = PlayerDataService.Get(bot :: any).Data
			table.clear(data.Monsters)
			table.clear(data.Equipped)
			for _, speciesId in species or { "Mossling", "Pebbleback" } do
				local sp = Registry.Species.ById[speciesId]
				local rec = generation:Generate(bot.UserId, { SpeciesId = speciesId, BiomeId = sp.HomeBiome }, Random.new())
				data.Monsters[rec.MonsterId] = rec
				table.insert(data.Equipped, rec.MonsterId)
			end
			return battle:Challenge(bot :: any, p)
		elseif cmd == "BotAct" then
			-- The bot picks a move in its current PvP battle (index 1 = Tackle).
			local index = ...
			local b = testBot and battle._battles[testBot]
			if not b then
				return { Ok = false, Error = "NoBattle" }
			end
			return battle:Act(testBot :: any, b.Id, { Type = "Move", Index = index or 1 })
		end
		return nil
	end
end

print("[MonsterFactory] server ready. Saving enabled:", PlayerDataService.SavingEnabled)
