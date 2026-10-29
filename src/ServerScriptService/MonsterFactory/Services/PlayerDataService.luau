-- Persistent player data with session locking, bounded retries, versioned schema
-- and a memory-only fallback when DataStores are unavailable (unpublished place,
-- or Studio API access disabled). In fallback mode nothing persists and the
-- client is told so; we never claim progress was saved when it was not.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.MonsterFactory.Shared.Config)

local PlayerDataService = {}

PlayerDataService.SCHEMA_VERSION = 1
PlayerDataService.STORE_NAME = "MonsterFactory_PlayerData_v1"
PlayerDataService.AUTOSAVE_SECONDS = 60
PlayerDataService.LOCK_STALE_SECONDS = 300
PlayerDataService.MAX_ATTEMPTS = 4
PlayerDataService.LOCK_WAIT_ATTEMPTS = 5
PlayerDataService.BACKOFF_SECONDS = 1 -- retry waits 1x, 2x, 4x this
PlayerDataService.LOCK_RETRY_SECONDS = 3

PlayerDataService.SavingEnabled = false
PlayerDataService.FallbackReason = nil :: string?

local profiles: { [Player]: any } = {}
local store: DataStore? = nil
local generation = nil
local changedCallbacks = {}

local function key(userId: number): string
	return "u_" .. userId
end

local function defaultData()
	local inv = {}
	for id, n in Config.StartingInventory do
		inv[id] = n
	end
	return {
		V = PlayerDataService.SCHEMA_VERSION,
		Coins = Config.StartingCoins,
		XP = 0,
		Level = 1,
		Monsters = {}, -- [MonsterId] = record
		Locked = {}, -- [MonsterId] = true (protected from selling)
		Inventory = inv, -- [MaterialId] = count
		UnlockedBiomes = { VerdantMeadows = true },
		Discoveries = { Species = {}, Mutations = {} }, -- [id] = first-discovery timestamp
		Unseen = {}, -- ["Species:X" | "Mutation:X"] = true  (drives NEW badges)
		Milestones = {}, -- [MilestoneId] = timestamp
		Incubation = nil, -- { OpId, RequestId, SpeciesId, BiomeId, Catalysts, StartedAt, EndsAt, Record }
		LastClaim = nil, -- { OpId, Response }  (idempotent re-claims)
		RecentStarts = {}, -- { { RequestId, OpId } } last few, for idempotent starts
		PityCounter = 0,
		Stats = { Incubations = 0, Sold = 0 },
		Settings = { SkipReveal = false },
		ResearchPoints = 0,
		Research = {}, -- [ResearchId] = true
		Upgrades = {}, -- [UpgradeId] = level
		GatherCooldowns = {}, -- [NodeId] = last gather (unix time)
		Quarantine = {}, -- invalid records kept for support, never auto-deleted
	}
end

local function isFiniteNumber(x: any): boolean
	return type(x) == "number" and x == x and x ~= math.huge and x ~= -math.huge
end

-- Fills missing fields, migrates old versions and validates everything before use.
function PlayerDataService.Migrate(data: any)
	local defaults = defaultData()
	if type(data) ~= "table" then
		return defaults
	end
	-- Future migrations: if data.V == 1 then ... data.V = 2 end
	for k, v in defaults do
		if data[k] == nil then
			data[k] = v
		end
	end
	if not isFiniteNumber(data.Coins) or data.Coins < 0 then
		warn("[PlayerData] invalid Coins, resetting to 0")
		data.Coins = 0
	end
	if not isFiniteNumber(data.XP) or data.XP < 0 then
		data.XP = 0
	end
	if not isFiniteNumber(data.Level) or data.Level < 1 then
		data.Level = 1
	end
	if not isFiniteNumber(data.PityCounter) or data.PityCounter < 0 then
		data.PityCounter = 0
	end
	if not isFiniteNumber(data.ResearchPoints) or data.ResearchPoints < 0 then
		data.ResearchPoints = 0
	end
	for id, lvl in data.Upgrades do
		if type(id) ~= "string" or not isFiniteNumber(lvl) or lvl < 0 then
			data.Upgrades[id] = nil
		end
	end
	for id, n in data.Inventory do
		if type(id) ~= "string" or not isFiniteNumber(n) or n < 0 then
			data.Inventory[id] = nil
		else
			data.Inventory[id] = math.floor(n)
		end
	end
	if generation then
		for id, rec in data.Monsters do
			local ok, why = generation:ValidateRecord(rec)
			if not ok or rec.MonsterId ~= id then
				warn("[PlayerData] quarantining invalid monster", id, why)
				data.Quarantine[tostring(id)] = rec
				data.Monsters[id] = nil
			end
		end
		if data.Incubation and not (type(data.Incubation) == "table" and generation:ValidateRecord(data.Incubation.Record)) then
			warn("[PlayerData] quarantining invalid incubation")
			data.Quarantine["incubation_" .. os.time()] = data.Incubation
			data.Incubation = nil
		end
	end
	data.V = PlayerDataService.SCHEMA_VERSION
	return data
end

local function withRetries(label: string, fn: () -> any): (boolean, any)
	local lastErr
	for attempt = 1, PlayerDataService.MAX_ATTEMPTS do
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end
		lastErr = result
		warn(string.format("[PlayerData] %s failed (attempt %d): %s", label, attempt, tostring(result)))
		if attempt < PlayerDataService.MAX_ATTEMPTS then
			task.wait(PlayerDataService.BACKOFF_SECONDS * 2 ^ (attempt - 1))
		end
	end
	return false, lastErr
end

-- Tests only: use an injected store (any object with UpdateAsync) without Init's
-- autosave loop or BindToClose. Passing nil returns to memory-only mode.
function PlayerDataService._UseStoreForTests(fakeStore: any, gen: any)
	generation = gen
	store = fakeStore
	PlayerDataService.SavingEnabled = fakeStore ~= nil
end

-- Tests only: drop a profile without saving (simulates a server crash).
function PlayerDataService._ForgetForTests(player: any)
	profiles[player] = nil
end

function PlayerDataService.Init(deps: { Generation: any })
	generation = deps.Generation
	if game.PlaceId == 0 then
		PlayerDataService.FallbackReason = "Place is not published"
	else
		local ok, err = pcall(function()
			store = DataStoreService:GetDataStore(PlayerDataService.STORE_NAME)
			;(store :: DataStore):GetAsync("probe")
		end)
		if ok then
			PlayerDataService.SavingEnabled = true
		else
			store = nil
			PlayerDataService.FallbackReason = "DataStores unavailable: " .. tostring(err)
		end
	end
	if not PlayerDataService.SavingEnabled then
		warn("[PlayerData] MEMORY-ONLY MODE - progress will NOT be saved. Reason: " .. tostring(PlayerDataService.FallbackReason))
	end

	task.spawn(function()
		while true do
			task.wait(PlayerDataService.AUTOSAVE_SECONDS)
			for player, profile in profiles do
				if profile.Dirty then
					task.spawn(PlayerDataService.Save, player, false)
				end
			end
		end
	end)

	game:BindToClose(function()
		local pending = 0
		for player in profiles do
			pending += 1
			task.spawn(function()
				PlayerDataService.Save(player, true)
				pending -= 1
			end)
		end
		local t0 = os.clock()
		while pending > 0 and os.clock() - t0 < 25 do
			task.wait(0.1)
		end
	end)
end

-- Loads (and session-locks) a player's data. Returns profile or (nil, reason).
function PlayerDataService.Load(player: Player)
	local data
	if PlayerDataService.SavingEnabled and store then
		local lockedOut = false
		for _ = 1, PlayerDataService.LOCK_WAIT_ATTEMPTS do
			lockedOut = false
			local ok, result = withRetries("Load", function()
				return (store :: DataStore):UpdateAsync(key(player.UserId), function(old)
					if type(old) == "table" and type(old.Lock) == "table" and old.Lock.Job ~= game.JobId
						and os.time() - (old.Lock.T or 0) < PlayerDataService.LOCK_STALE_SECONDS then
						lockedOut = true
						return nil -- cancel write; another server owns this session
					end
					local d = if type(old) == "table" then old else defaultData()
					d.Lock = { Job = game.JobId, T = os.time() }
					return d
				end)
			end)
			if not ok then
				return nil, "Could not load your data. Please rejoin."
			end
			if not lockedOut then
				data = result
				break
			end
			task.wait(PlayerDataService.LOCK_RETRY_SECONDS)
		end
		if lockedOut then
			return nil, "Your data is still open in another server. Please wait a minute and rejoin."
		end
	else
		data = defaultData()
	end
	if not player.Parent then
		return nil, "Left during load"
	end
	data = PlayerDataService.Migrate(data)
	data.Lock = nil
	local profile = {
		Data = data,
		Dirty = false,
		SaveStatus = if PlayerDataService.SavingEnabled then "Saved" else "Disabled",
		Saving = false,
	}
	profiles[player] = profile
	return profile
end

function PlayerDataService.Get(player: Player)
	return profiles[player]
end

function PlayerDataService.OnChanged(cb: (Player, string) -> ())
	table.insert(changedCallbacks, cb)
end

-- Marks data changed; `what` is a hint for clients ("Coins", "All", ...).
function PlayerDataService.MarkDirty(player: Player, what: string?)
	local profile = profiles[player]
	if not profile then
		return
	end
	profile.Dirty = true
	if PlayerDataService.SavingEnabled and profile.SaveStatus == "Saved" then
		profile.SaveStatus = "Unsaved"
	end
	for _, cb in changedCallbacks do
		task.spawn(cb, player, what or "All")
	end
end

-- Saves now. `release` clears the session lock (on leave / shutdown). Returns success.
function PlayerDataService.Save(player: Player, release: boolean): boolean
	local profile = profiles[player]
	if not profile then
		return false
	end
	if not (PlayerDataService.SavingEnabled and store) then
		profile.Dirty = false
		return false
	end
	while profile.Saving do
		task.wait(0.1)
	end
	profile.Saving = true
	profile.Dirty = false
	local stolen = false
	local ok = withRetries("Save", function()
		(store :: DataStore):UpdateAsync(key(player.UserId), function(old)
			if type(old) == "table" and type(old.Lock) == "table" and old.Lock.Job ~= game.JobId
				and os.time() - (old.Lock.T or 0) < PlayerDataService.LOCK_STALE_SECONDS then
				stolen = true
				return nil
			end
			local out = table.clone(profile.Data)
			out.Lock = if release then nil else { Job = game.JobId, T = os.time() }
			return out
		end)
	end)
	profile.Saving = false
	if ok and not stolen then
		if not profile.Dirty then
			profile.SaveStatus = "Saved"
		end
	else
		profile.Dirty = true
		profile.SaveStatus = "Failed"
		warn("[PlayerData] save failed for", player.UserId, if stolen then "(session taken by another server)" else "")
	end
	for _, cb in changedCallbacks do
		task.spawn(cb, player, "SaveStatus")
	end
	return ok and not stolen
end

function PlayerDataService.Release(player: Player)
	if profiles[player] then
		PlayerDataService.Save(player, true)
		profiles[player] = nil
	end
end

Players.PlayerRemoving:Connect(function(player)
	PlayerDataService.Release(player)
end)

return PlayerDataService
