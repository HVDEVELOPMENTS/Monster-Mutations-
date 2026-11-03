-- Coins, passive income, levels, selling and the catalyst shop.

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.MonsterFactory.Shared.Config)
local Registry = require(ReplicatedStorage.MonsterFactory.Shared.Registry)
local Tutorial = require(ReplicatedStorage.MonsterFactory.Shared.Tutorial)
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
	local slot = table.find(data.Equipped, monsterId)
	if slot then
		table.remove(data.Equipped, slot)
		self:PublishEquipped(player)
	end
	data.Coins += value
	data.Stats.Sold += 1
	self:InvalidateIncome(player)
	self.PlayerData.MarkDirty(player, "All")
	return { Ok = true, Coins = value }
end

-- Bulk sell: every monster at or below `maxTier` that is not locked or equipped.
-- Capped at Rare so one tap can never dump high-value monsters. preview = true
-- only counts, so the client can confirm with real numbers.
EconomyService.BulkSellMaxTier = 3

function EconomyService:SellBulk(player: Player, maxTier: any, preview: any)
	local profile = self.PlayerData.Get(player)
	if not profile then
		return { Ok = false, Error = "NotLoaded" }
	end
	if type(maxTier) ~= "number" or maxTier ~= math.floor(maxTier) or maxTier < 1 or maxTier > EconomyService.BulkSellMaxTier then
		return { Ok = false, Error = "BadRequest" }
	end
	local data = profile.Data
	local ids, value = {}, 0
	for id, rec in data.Monsters do
		if rec.RarityTier <= maxTier and not data.Locked[id] and not table.find(data.Equipped, id) then
			table.insert(ids, id)
			value += Config.SellValue[rec.RarityTier] or 0
		end
	end
	if preview == true or #ids == 0 then
		return { Ok = true, Count = #ids, Coins = value, Preview = true }
	end
	for _, id in ids do
		data.Monsters[id] = nil
	end
	data.Coins += value
	data.Stats.Sold += #ids
	self:InvalidateIncome(player)
	self.PlayerData.MarkDirty(player, "All")
	return { Ok = true, Count = #ids, Coins = value }
end

-- Publishes the equipped monsters' looks (not their stats) as the "EquippedPets"
-- player attribute (a JSON list, in slot order) so every client can render the
-- followers.
function EconomyService:PublishEquipped(player: Player)
	if typeof(player) ~= "Instance" then
		return -- test doubles have no attributes
	end
	local profile = self.PlayerData.Get(player)
	local looks = {}
	if profile then
		for _, id in profile.Data.Equipped do
			local rec = profile.Data.Monsters[id]
			if rec then
				table.insert(looks, {
					MonsterId = rec.MonsterId,
					SpeciesId = rec.SpeciesId,
					DisplayName = rec.DisplayName,
					Genes = rec.Genes,
					ActiveMutations = rec.ActiveMutations,
					RarityTier = rec.RarityTier,
					PrimaryElement = rec.PrimaryElement,
				})
			end
		end
	end
	player:SetAttribute("EquippedPets", HttpService:JSONEncode(looks))
end

-- Equip (on = true, the default) or unequip a follower; monsterId nil unequips all.
-- Equipping is refused when every pet slot is taken.
function EconomyService:Equip(player: Player, monsterId: any, on: any)
	local profile = self.PlayerData.Get(player)
	if not profile then
		return { Ok = false, Error = "NotLoaded" }
	end
	local data = profile.Data
	if on ~= nil and type(on) ~= "boolean" then
		return { Ok = false, Error = "BadRequest" }
	end
	if monsterId == nil then
		table.clear(data.Equipped)
	else
		if not isId(monsterId) or not data.Monsters[monsterId] then
			return { Ok = false, Error = "NotOwned" }
		end
		local slot = table.find(data.Equipped, monsterId)
		if on == false then
			if slot then
				table.remove(data.Equipped, slot)
			end
		elseif not slot then
			if #data.Equipped >= ProgressionService.PetSlots(data) then
				return { Ok = false, Error = "PetSlotsFull" }
			end
			table.insert(data.Equipped, monsterId)
		end
	end
	self:PublishEquipped(player)
	self.PlayerData.MarkDirty(player, "All")
	return { Ok = true, Equipped = data.Equipped }
end

-- Getting Started reward (Shared/Tutorial): paid once, only when every step is
-- really done according to the saved data.
function EconomyService:ClaimTutorialReward(player: Player)
	local profile = self.PlayerData.Get(player)
	if not profile then
		return { Ok = false, Error = "NotLoaded" }
	end
	local data = profile.Data
	if data.TutorialRewarded then
		return { Ok = false, Error = "AlreadyClaimed" }
	end
	if Tutorial.Current(Tutorial.FromData(data)) ~= nil then
		return { Ok = false, Error = "NotFinished" }
	end
	data.TutorialRewarded = true
	data.Coins += Tutorial.Reward
	self.PlayerData.MarkDirty(player, "All")
	return { Ok = true, Coins = Tutorial.Reward }
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
