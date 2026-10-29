-- Factory upgrades, research and world gathering. The static helpers turn saved
-- progress into the exact numbers other services use (incubation time, income
-- slots, recycle chance, tier modifiers), so every effect lives in one place.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.MonsterFactory.Shared.Config)
local Registry = require(ReplicatedStorage.MonsterFactory.Shared.Registry)
local Progression = require(ReplicatedStorage.MonsterFactory.Shared.Progression)
local Events = require(ReplicatedStorage.MonsterFactory.Shared.Events)

local ProgressionService = {}
ProgressionService.__index = ProgressionService

function ProgressionService.new(deps: { PlayerData: any })
	local self = setmetatable({}, ProgressionService)
	self.PlayerData = deps.PlayerData
	self.Rng = Random.new()
	self.Now = os.time
	return self
end

-- ===== Derived numbers =====
function ProgressionService.UpgradeLevel(data: any, id: string): number
	return (data.Upgrades and data.Upgrades[id]) or 0
end

function ProgressionService.IncubationSeconds(data: any): number
	local u = Progression.UpgradeById.ImprovedIncubator
	return math.max(1, Config.IncubationSeconds - ProgressionService.UpgradeLevel(data, u.Id) * u.SecondsPerLevel)
end

function ProgressionService.EarningSlots(data: any): number
	local u = Progression.UpgradeById.HabitatExpansion
	return Config.EarningSlots + ProgressionService.UpgradeLevel(data, u.Id) * u.SlotsPerLevel
end

function ProgressionService.RecycleChance(data: any): number
	local u = Progression.UpgradeById.CatalystRecycler
	return ProgressionService.UpgradeLevel(data, u.Id) * u.ChancePerLevel
end

-- Tier modifiers for the mutation engine: { { Tier, Multiplier, Source } }.
function ProgressionService.TierModifiers(data: any)
	local out = {}
	local u = Progression.UpgradeById.RareResonator
	local level = ProgressionService.UpgradeLevel(data, u.Id)
	if level > 0 then
		table.insert(out, { Tier = u.Tier, Multiplier = 1 + level * u.MultiplierPerLevel, Source = "Upgrade:" .. u.Id })
	end
	return out
end

-- Research Points earned for a claimed monster.
function ProgressionService.ResearchPointsFor(record: any, newDiscoveries: number): number
	return math.floor(record.Stats.ResearchValue * Progression.RPPerResearchValue) + newDiscoveries * Progression.RPPerDiscovery
end

-- ===== Purchases =====
function ProgressionService:BuyUpgrade(player: Player, id: any)
	local profile = self.PlayerData.Get(player)
	if not profile then
		return { Ok = false, Error = "NotLoaded" }
	end
	local def = type(id) == "string" and Progression.UpgradeById[id]
	if not def then
		return { Ok = false, Error = "UnknownUpgrade" }
	end
	local data = profile.Data
	local level = ProgressionService.UpgradeLevel(data, id)
	local cost = def.Costs[level + 1]
	if not cost then
		return { Ok = false, Error = "MaxLevel" }
	end
	if data.Coins < cost then
		return { Ok = false, Error = "NotEnoughCoins" }
	end
	data.Coins -= cost
	data.Upgrades[id] = level + 1
	self.PlayerData.MarkDirty(player, "All")
	task.spawn(self.PlayerData.Save, player, false)
	return { Ok = true, Level = level + 1 }
end

function ProgressionService:BuyResearch(player: Player, id: any)
	local profile = self.PlayerData.Get(player)
	if not profile then
		return { Ok = false, Error = "NotLoaded" }
	end
	local def = type(id) == "string" and Progression.ResearchById[id]
	if not def then
		return { Ok = false, Error = "UnknownResearch" }
	end
	local data = profile.Data
	if data.Research[id] then
		return { Ok = true, AlreadyOwned = true }
	end
	for _, req in def.Requires do
		if not data.Research[req] then
			return { Ok = false, Error = "ResearchLocked" }
		end
	end
	if def.RequiresBiome and not data.UnlockedBiomes[def.RequiresBiome] then
		return { Ok = false, Error = "BiomeLocked" }
	end
	if data.ResearchPoints < def.Cost then
		return { Ok = false, Error = "NotEnoughResearch" }
	end
	data.ResearchPoints -= def.Cost
	data.Research[id] = true
	self.PlayerData.MarkDirty(player, "All")
	task.spawn(self.PlayerData.Save, player, false)
	return { Ok = true }
end

-- ===== Gathering =====
-- Pure drop roll: { [materialId] = amount }.
function ProgressionService.RollDrops(nodeType: string, activeEvents: { [string]: any }, rng: Random)
	local node = Progression.GatherNodes[nodeType]
	local drops = { [node.Base] = rng:NextInteger(node.BaseAmount[1], node.BaseAmount[2]) }
	for _, b in node.Bonus do
		if (b.Event == nil or activeEvents[b.Event] ~= nil) and rng:NextNumber() < b.Chance then
			drops[b.Material] = (drops[b.Material] or 0) + 1
		end
	end
	return drops
end

-- Server-side gather from a world node part (attributes NodeType, NodeId).
function ProgressionService:Gather(player: Player, node: BasePart)
	local profile = self.PlayerData.Get(player)
	if not profile then
		return { Ok = false, Error = "NotLoaded" }
	end
	local nodeType, nodeId = node:GetAttribute("NodeType"), node:GetAttribute("NodeId")
	local def = type(nodeType) == "string" and Progression.GatherNodes[nodeType]
	if not def or type(nodeId) ~= "string" then
		return { Ok = false, Error = "BadNode" }
	end
	local data = profile.Data
	if not data.UnlockedBiomes[def.Biome] then
		return { Ok = false, Error = "BiomeLocked" }
	end
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root or (root.Position - node.Position).Magnitude > Progression.GatherRange + 4 then
		return { Ok = false, Error = "TooFar" }
	end
	local now = self.Now()
	local last = data.GatherCooldowns[nodeId] or 0
	if now - last < def.Cooldown then
		return { Ok = false, Error = "Cooldown", ReadyIn = def.Cooldown - (now - last) }
	end
	data.GatherCooldowns[nodeId] = now
	local drops = ProgressionService.RollDrops(nodeType, Events.GetActive(def.Biome, now), self.Rng)
	local granted = {}
	for mat, n in drops do
		local limit = Registry.Materials.ById[mat].StackLimit
		local have = data.Inventory[mat] or 0
		local add = math.max(0, math.min(n, limit - have))
		if add > 0 then
			data.Inventory[mat] = have + add
			granted[mat] = add
		end
	end
	self.PlayerData.MarkDirty(player, "All")
	return { Ok = true, Granted = granted, Cooldown = def.Cooldown }
end

return ProgressionService
