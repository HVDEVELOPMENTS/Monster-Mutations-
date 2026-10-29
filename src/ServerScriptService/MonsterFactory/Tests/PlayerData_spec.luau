-- Persistence tests against a fake DataStore. The fake JSON-encodes every write and
-- read (like real DataStores), so aliasing bugs and non-serialisable data show up.
-- Real DataStores still need a published place; see the Stage 3 notes.

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Registry = require(ReplicatedStorage.MonsterFactory.Shared.Registry)
local Config = require(ReplicatedStorage.MonsterFactory.Shared.Config)
local Services = script.Parent.Parent.Services
local PlayerData = require(Services.PlayerDataService)
local MutationService = require(Services.MutationService)
local MonsterGenerationService = require(Services.MonsterGenerationService)
local EconomyService = require(Services.EconomyService)
local IncubationService = require(Services.IncubationService)

local function newFakeStore()
	local store = { Data = {}, FailNext = 0, Writes = 0 }
	function store:UpdateAsync(key, fn)
		if self.FailNext > 0 then
			self.FailNext -= 1
			error("502: simulated DataStore outage")
		end
		local old = self.Data[key] and HttpService:JSONDecode(self.Data[key])
		local new = fn(old)
		if new == nil then
			return old
		end
		self.Data[key] = HttpService:JSONEncode(new)
		self.Writes += 1
		return HttpService:JSONDecode(self.Data[key])
	end
	function store:Peek(key)
		return self.Data[key] and HttpService:JSONDecode(self.Data[key])
	end
	return store
end

local nextUser = 9000
local function fakePlayer(userId)
	return { UserId = userId, Parent = workspace, Name = "Fake" .. userId }
end

return function(t)
	local mutation = MutationService.new(Registry)
	local generation = MonsterGenerationService.new(Registry, mutation)
	local economy = EconomyService.new({ PlayerData = PlayerData })
	local incubation = IncubationService.new({ PlayerData = PlayerData, Generation = generation, Mutation = mutation, Economy = economy })
	local clock = os.time()
	incubation.Now = function()
		return clock
	end
	PlayerData.BACKOFF_SECONDS = 0.01
	PlayerData.LOCK_RETRY_SECONDS = 0.01
	PlayerData.LOCK_WAIT_ATTEMPTS = 2

	local function setup()
		local store = newFakeStore()
		PlayerData._UseStoreForTests(store, generation)
		nextUser += 1
		return store, nextUser, "u_" .. nextUser
	end
	local function incubateAndClaim(p)
		local s = incubation:Start(p, { RequestId = HttpService:GenerateGUID(false), SpeciesId = "Mossling", BiomeId = "VerdantMeadows" })
		assert(s.Ok, "start failed: " .. tostring(s.Error))
		clock += Config.IncubationSeconds
		local c = incubation:Claim(p, s.Incubation.OpId)
		assert(c.Ok, "claim failed: " .. tostring(c.Error))
		return c
	end

	t.it("new player gets defaults; lock is held while playing and released on leave", function()
		local store, uid, key = setup()
		local p = fakePlayer(uid)
		local profile = PlayerData.Load(p)
		t.ok(profile, "loaded")
		t.eq(profile.Data.Coins, Config.StartingCoins, "starting coins")
		t.ok(store:Peek(key).Lock ~= nil, "lock written on load")
		PlayerData.Release(p)
		t.eq(store:Peek(key).Lock, nil, "lock cleared on release")
	end)

	t.it("progress survives leave + rejoin (coins, monsters, discoveries, inventory)", function()
		local store, uid, key = setup()
		local p = fakePlayer(uid)
		PlayerData.Load(p)
		local claim = incubateAndClaim(p)
		local before = PlayerData.Get(p).Data
		local coins, level, xp = before.Coins, before.Level, before.XP
		PlayerData.Release(p)
		local p2 = fakePlayer(uid)
		local d = PlayerData.Load(p2).Data
		t.eq(d.Coins, coins, "coins")
		t.eq(d.Level, level, "level")
		t.eq(d.XP, xp, "xp")
		local rec = d.Monsters[claim.Record.MonsterId]
		t.ok(rec, "monster persisted")
		t.eq(#rec.ActiveMutations, #claim.Record.ActiveMutations, "mutations persisted")
		t.ok(generation:ValidateRecord(rec), "persisted record still valid")
		t.ok(d.Discoveries.Species.Mossling, "discovery persisted")
		t.eq(d.PityCounter, if claim.Record.RarityTier >= 3 then 0 else 1, "pity counter persisted")
		PlayerData.Release(p2)
	end)

	t.it("incubation started before leaving resumes after rejoin with the SAME rolled monster", function()
		local store, uid = setup()
		local p = fakePlayer(uid)
		PlayerData.Load(p)
		local s = incubation:Start(p, { RequestId = HttpService:GenerateGUID(false), SpeciesId = "Pebbleback", BiomeId = "VerdantMeadows" })
		t.ok(s.Ok, "start")
		local hiddenId = PlayerData.Get(p).Data.Incubation.Record.MonsterId
		local coinsAfterCharge = PlayerData.Get(p).Data.Coins
		PlayerData.Release(p) -- player disconnects mid-incubation
		clock += Config.IncubationSeconds + 60 -- time passes while offline
		local p2 = fakePlayer(uid)
		local d = PlayerData.Load(p2).Data
		t.ok(d.Incubation, "incubation still there")
		t.eq(d.Incubation.OpId, s.Incubation.OpId, "same op")
		t.eq(d.Coins, coinsAfterCharge, "not refunded or double-charged")
		local c = incubation:Claim(p2, s.Incubation.OpId)
		t.ok(c.Ok, "claim after rejoin")
		t.eq(c.Record.MonsterId, hiddenId, "outcome was not rerolled")
		PlayerData.Release(p2)
	end)

	t.it("claim retried after a rejoin does not duplicate the monster", function()
		local store, uid = setup()
		local p = fakePlayer(uid)
		PlayerData.Load(p)
		local c = incubateAndClaim(p)
		local opId = PlayerData.Get(p).Data.LastClaim.OpId
		PlayerData.Release(p)
		local p2 = fakePlayer(uid)
		PlayerData.Load(p2)
		local again = incubation:Claim(p2, opId)
		t.ok(again.Ok and again.Duplicate, "duplicate claim answered from saved response")
		t.eq(again.Record.MonsterId, c.Record.MonsterId, "same monster")
		local n = 0
		for _ in PlayerData.Get(p2).Data.Monsters do
			n += 1
		end
		t.eq(n, 1, "still exactly one monster")
		PlayerData.Release(p2)
	end)

	t.it("another server's fresh lock blocks loading; a stale lock is taken over", function()
		local store, uid, key = setup()
		store.Data[key] = HttpService:JSONEncode({ V = 1, Coins = 777, Lock = { Job = "other-server", T = os.time() } })
		local p = fakePlayer(uid)
		local profile, err = PlayerData.Load(p)
		t.eq(profile, nil, "blocked by fresh lock")
		t.ok(type(err) == "string" and err:find("another server"), "clear message: " .. tostring(err))
		t.eq(store:Peek(key).Coins, 777, "other server's data untouched")
		store.Data[key] = HttpService:JSONEncode({ V = 1, Coins = 777, Lock = { Job = "other-server", T = os.time() - PlayerData.LOCK_STALE_SECONDS - 5 } })
		profile = PlayerData.Load(p)
		t.ok(profile, "stale lock taken over")
		t.eq(profile.Data.Coins, 777, "existing data kept")
		PlayerData.Release(p)
	end)

	t.it("save is refused (and reported) if another server took the session", function()
		local store, uid, key = setup()
		local p = fakePlayer(uid)
		local profile = PlayerData.Load(p)
		profile.Data.Coins = 5
		PlayerData.MarkDirty(p, "All")
		local d = store:Peek(key)
		d.Lock = { Job = "other-server", T = os.time() }
		d.Coins = 999
		store.Data[key] = HttpService:JSONEncode(d)
		local ok = PlayerData.Save(p, false)
		t.eq(ok, false, "save refused")
		t.eq(profile.SaveStatus, "Failed", "status reported to player")
		t.ok(profile.Dirty, "still marked unsaved")
		t.eq(store:Peek(key).Coins, 999, "did not overwrite the other server")
		PlayerData._ForgetForTests(p)
	end)

	t.it("transient DataStore errors are retried; persistent failure never claims success", function()
		local store, uid, key = setup()
		store.FailNext = 2
		local p = fakePlayer(uid)
		local profile = PlayerData.Load(p)
		t.ok(profile, "loaded after 2 failures")
		profile.Data.Coins = 42
		PlayerData.MarkDirty(p, "All")
		store.FailNext = 100
		local ok = PlayerData.Save(p, false)
		t.eq(ok, false, "save failed")
		t.eq(profile.SaveStatus, "Failed", "status Failed, not Saved")
		t.ok(profile.Dirty, "kept dirty for the next attempt")
		store.FailNext = 0
		t.ok(PlayerData.Save(p, true), "recovers once the store is back")
		t.eq(store:Peek(key).Coins, 42, "data written")
		PlayerData._ForgetForTests(p)
		local store2, uid2 = setup()
		store2.FailNext = 100
		local p2 = fakePlayer(uid2)
		local prof2, err = PlayerData.Load(p2)
		t.eq(prof2, nil, "load fails instead of handing out blank data")
		t.ok(err, "error message for kick")
	end)

	t.it("old/partial data is migrated; invalid values repaired; bad monsters quarantined not deleted", function()
		local store, uid, key = setup()
		local good = generation:Generate(uid, { SpeciesId = "Mossling", BiomeId = "VerdantMeadows" }, Random.new(1))
		local bad = table.clone(good)
		bad.MonsterId = "bad-1"
		bad.ActiveMutations = { "NoSuchMutation" }
		store.Data[key] = HttpService:JSONEncode({
			Coins = "lots", -- invalid type
			XP = -5,
			Monsters = { [good.MonsterId] = good, ["bad-1"] = bad },
			Inventory = { Dewdrop = 3, Junk = -2 },
		})
		local p = fakePlayer(uid)
		local d = PlayerData.Load(p).Data
		t.eq(d.V, PlayerData.SCHEMA_VERSION, "version stamped")
		t.eq(d.Coins, 0, "invalid coins repaired")
		t.eq(d.XP, 0, "negative xp repaired")
		t.eq(d.Inventory.Dewdrop, 3, "valid inventory kept")
		t.eq(d.Inventory.Junk, nil, "negative inventory dropped")
		t.ok(d.Monsters[good.MonsterId], "valid monster kept")
		t.eq(d.Monsters["bad-1"], nil, "invalid monster removed from play")
		t.ok(d.Quarantine["bad-1"], "invalid monster kept in quarantine")
		t.ok(d.UnlockedBiomes.VerdantMeadows, "missing fields filled")
		PlayerData.Release(p)
		t.ok(store:Peek(key).Quarantine["bad-1"], "quarantine persisted")
	end)

	t.it("everything in a full profile is DataStore-serialisable", function()
		local store, uid, key = setup()
		local p = fakePlayer(uid)
		PlayerData.Load(p)
		for _ = 1, 3 do
			incubateAndClaim(p)
		end
		local ok, err = pcall(HttpService.JSONEncode, HttpService, PlayerData.Get(p).Data)
		t.ok(ok, "JSON encode: " .. tostring(err))
		local size = #HttpService:JSONEncode(PlayerData.Get(p).Data)
		t.log(string.format("profile with 3 monsters = %d bytes (DataStore limit 4,194,304)", size))
		PlayerData.Release(p)
	end)

	PlayerData._UseStoreForTests(nil, generation)
end
