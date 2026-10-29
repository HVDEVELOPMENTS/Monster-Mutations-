-- Coins, passive income, levels, selling and the catalyst shop.

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.MonsterFactory.Shared.Config)
local Registry = require(ReplicatedStorage.MonsterFactory.Shared.Registry)
local ProgressionService = require(script.Parent.ProgressionService)

local EconomyService = {}
EconomyService.__index = EconomyService

function EconomyService.new(deps: { PlayerData: any })
	local self = setmetatable({}, EconomyService)
	self.PlayerData = deps.PlayerData
	self._incomeCache = {} :: { [Player]: number }
	return self
end

-- Sum of the highest IncomeRates, over as many monsters as the player has earning slots.
function EconomyService:ComputeIncome(data: any): number
	local rates = {}
	for _, rec in data.Monsters do
		table.insert(rates, rec.Stats.IncomeRate)
	end
	table.sort(rates, function(a, b)
		return a > b
	end)
	local total = 0
	for i = 1, math.min(#rates, ProgressionService.EarningSlots(data)) do
		total += rates[i]
	end
	return total
end

function EconomyService:GetIncome(player: Player): number
	local cached = self._incomeCache[player]
	if cached then
		return cached
	end
	local profile = self.PlayerData.Get(player)
	if not profile then
		return 0
	end
	local v = self:ComputeIncome(profile.Data)
	self._incomeCache[player] = v
	return v
end

function EconomyService:InvalidateIncome(player: Player)
	self._incomeCache[player] = nil
end

function EconomyService:ForgetPlayer(player: Player)
	self._incomeCache[player] = nil
end

-- Adds XP and handles level-ups. Returns number of levels gained.
function EconomyService.AddXP(data: any, amount: number): number
	data.XP += amount
	local gained = 0
	while data.XP >= Config.XPToNext(data.Level) do
		data.XP -= Config.XPToNext(data.Level)
		data.Level += 1
		gained += 1
	end
	return gained
end

function EconomyService:StartIncomeLoop(players: Players)
	task.spawn(function()
		while true do
			task.wait(1)
			for _, player in players:GetPlayers() do
				local profile = self.PlayerData.Get(player)
				if profile then
					local income = self:GetIncome(player)
					if income > 0 then
						profile.Data.Coins += income
						self.PlayerData.MarkDirty(player, "Coins")
					end
				end
			end
		end
	end)
end

local function isId(x: any): boolean
	return type(x) == "string" and #x > 0 and #x <= 64
end

function EconomyService:Sell(player: Player, monsterId: any)
	local profile = self.PlayerData.Get(player)
	if not profile then
		return { Ok = false, Error = "NotLoaded" }
	end
	if not isId(monsterId) then
		return { Ok = false, Error = "BadRequest" }
	end
	local data = profile.Data
	local rec = data.Monsters[monsterId]
	if not rec then
		return { Ok = false, Error = "NotOwned" }
	end
	if data.Locked[monsterId] then
		return { Ok = false, Error = "Locked" }
	end
	local value = Config.SellValue[rec.RarityTier] or 0
	data.Monsters[monsterId] = nil
	if data.Equipped == monsterId then
		data.Equipped = nil
		self:PublishEquipped(player)
	end
	data.Coins += value
	data.Stats.Sold += 1
	self:InvalidateIncome(player)
	self.PlayerData.MarkDirty(player, "All")
	return { Ok = true, Coins = value }
end

-- Publishes the equipped monster's look (not its stats) as a player attribute so
-- every client can render the follower. Empty string = nothing equipped.
function EconomyService:PublishEquipped(player: Player)
	if typeof(player) ~= "Instance" then
		return -- test doubles have no attributes
	end
	local profile = self.PlayerData.Get(player)
	local rec = profile and profile.Data.Equipped and profile.Data.Monsters[profile.Data.Equipped]
	if not rec then
		player:SetAttribute("EquippedPet", "")
		return
	end
	player:SetAttribute("EquippedPet", HttpService:JSONEncode({
		MonsterId = rec.MonsterId,
		SpeciesId = rec.SpeciesId,
		DisplayName = rec.DisplayName,
		Genes = rec.Genes,
		ActiveMutations = rec.ActiveMutations,
		RarityTier = rec.RarityTier,
		PrimaryElement = rec.PrimaryElement,
	}))
end

-- Equip a monster as your follower, or pass nil to unequip.
function EconomyService:Equip(player: Player, monsterId: any)
	local profile = self.PlayerData.Get(player)
	if not profile then
		return { Ok = false, Error = "NotLoaded" }
	end
	if monsterId ~= nil and (not isId(monsterId) or not profile.Data.Monsters[monsterId]) then
		return { Ok = false, Error = "NotOwned" }
	end
	profile.Data.Equipped = monsterId
	self:PublishEquipped(player)
	self.PlayerData.MarkDirty(player, "All")
	return { Ok = true, Equipped = monsterId }
end

function EconomyService:ToggleLock(player: Player, monsterId: any)
	local profile = self.PlayerData.Get(player)
	if not profile or not isId(monsterId) or not profile.Data.Monsters[monsterId] then
		return { Ok = false, Error = "NotOwned" }
	end
	local locked = profile.Data.Locked
	locked[monsterId] = if locked[monsterId] then nil else true
	self.PlayerData.MarkDirty(player, "All")
	return { Ok = true, Locked = locked[monsterId] == true }
end

function EconomyService:BuyCatalyst(player: Player, materialId: any, quantity: any)
	local profile = self.PlayerData.Get(player)
	if not profile then
		return { Ok = false, Error = "NotLoaded" }
	end
	if not isId(materialId) or not Registry.Materials.ById[materialId] or not Config.CatalystPrices[materialId] then
		return { Ok = false, Error = "UnknownItem" }
	end
	if type(quantity) ~= "number" or quantity ~= math.floor(quantity) or quantity < 1 or quantity > Config.MaxBuyQuantity then
		return { Ok = false, Error = "BadQuantity" }
	end
	local data = profile.Data
	local def = Registry.Materials.ById[materialId]
	if not data.UnlockedBiomes[def.SourceBiome] then
		return { Ok = false, Error = "BiomeLocked" }
	end
	local have = data.Inventory[materialId] or 0
	if have + quantity > def.StackLimit then
		return { Ok = false, Error = "StackFull" }
	end
	local cost = Config.CatalystPrices[materialId] * quantity
	if data.Coins < cost then
		return { Ok = false, Error = "NotEnoughCoins" }
	end
	data.Coins -= cost
	data.Inventory[materialId] = have + quantity
	self.PlayerData.MarkDirty(player, "All")
	return { Ok = true }
end

return EconomyService
