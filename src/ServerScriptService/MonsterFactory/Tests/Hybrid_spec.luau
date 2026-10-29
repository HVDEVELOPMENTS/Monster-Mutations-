-- Stage 5: hybrid recipes.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Registry = require(ReplicatedStorage.MonsterFactory.Shared.Registry)
local Services = script.Parent.Parent.Services
local MutationService = require(Services.MutationService)
local MonsterGenerationService = require(Services.MonsterGenerationService)

local M = Registry.Mutations.ById
local Recipes = Registry.HybridRecipes

return function(t)
	local svc = MutationService.new(Registry)
	local function resolve(species, biome, extra)
		local c = { SpeciesId = species, BiomeId = biome }
		for k, v in extra or {} do
			c[k] = v
		end
		return assert(svc:Resolve(c))
	end
	local function list(ids)
		local out = {}
		for _, id in ids do
			table.insert(out, M[id])
		end
		return out
	end
	-- Fraction of n trials where ResolveHybrid produced each output.
	local function trial(r, chosenIds, n, seed)
		local rng = Random.new(seed)
		local counts = {}
		local chosen = list(chosenIds)
		for _ = 1, n do
			local h = svc:ResolveHybrid(chosen, r, rng)
			local k = h and h.Id or "<none>"
			counts[k] = (counts[k] or 0) + 1
		end
		return counts
	end
	local function within(t_, label, count, n, p)
		local se = math.sqrt(p * (1 - p) / n)
		local obs = count / n
		t_.log(string.format("%-34s expected %.3f  observed %.3f  n=%d", label, p, obs, n))
		t_.ok(math.abs(obs - p) <= 4 * se + 1e-9, label)
	end

	t.it("registry is consistent; hybrid outputs are their own category", function()
		for _, r in Recipes.List do
			local out = M[r.Output]
			t.ok(out, "output exists: " .. r.Id)
			t.eq(out.Category, "Hybrid", "output category " .. r.Id)
			for _, input in r.Inputs do
				local kind, name = input:match("^(%w+):(.+)$")
				t.ok(kind == "Element" or (kind == "Mutation" and M[name] ~= nil), "valid input " .. input)
			end
		end
	end)

	t.it("guaranteed recipe always fires when inputs + conditions are met", function()
		local r = resolve("Pebbleback", "FrostfallTundra", { Catalysts = { "GlacierCrystal" } })
		local c = trial(r, { "FrozenCore" }, 2000, 1)
		t.eq(c.PermafrostShell, 2000, "always")
	end)

	t.it("conditions are enforced: catalyst, biome, event", function()
		t.eq(trial(resolve("Pebbleback", "FrostfallTundra"), { "FrozenCore" }, 500, 2).PermafrostShell, nil, "no catalyst -> never")
		-- Frost element in Verdant isn't possible via rolls, but the rule must hold anyway.
		t.eq(trial(resolve("Pebbleback", "VerdantMeadows"), { "FrozenCore" }, 500, 3).PermafrostShell, nil, "wrong biome -> never")
		local noAurora = trial(resolve("Snowmote", "FrostfallTundra"), { "AuroraMarkings", "CrystalAntlers" }, 2000, 4)
		t.eq(noAurora.PrismaticAurora, nil, "no Aurora Night -> never")
	end)

	t.it("missing inputs never form; input order does not matter", function()
		local r = resolve("Mossling", "FrostfallTundra")
		t.eq(trial(r, { "SnowflakePattern" }, 1000, 5).Frostbloom, nil, "no Frost element")
		local a = trial(r, { "FrozenCore", "SnowflakePattern" }, 20000, 6)
		local b = trial(r, { "SnowflakePattern", "FrozenCore" }, 20000, 6)
		t.eq(a.Frostbloom, b.Frostbloom, "same result for either order (same seed)")
	end)

	t.it("chance recipes match their stated chance (20k each)", function()
		local n = 20000
		local fb = trial(resolve("Mossling", "FrostfallTundra"), { "FrozenCore" }, n, 7)
		within(t, "Frostbloom (35%)", fb.Frostbloom or 0, n, Recipes.ById.Frostbloom.Chance)
		local ice = trial(resolve("Glimmerseal", "FrostfallTundra"), { "Chilled" }, n, 8)
		within(t, "Icefloe (30%)", ice.Icefloe or 0, n, Recipes.ById.Icefloe.Chance)
		local rs = trial(resolve("Pebbleback", "VerdantMeadows"), { "Thornbound" }, n, 9)
		within(t, "Rootstone (40%)", rs.Rootstone or 0, n, Recipes.ById.Rootstone.Chance)
	end)

	t.it("higher priority recipe wins; lower one only gets the remainder", function()
		local r = resolve("Mossling", "FrostfallTundra", { Events = { AuroraNight = true } })
		local n = 20000
		local c = trial(r, { "FrozenCore", "AuroraMarkings", "CrystalAntlers" }, n, 10)
		local pa = Recipes.ById.PrismaticAurora.Chance
		within(t, "Prismatic Aurora (first, 50%)", c.PrismaticAurora or 0, n, pa)
		within(t, "Frostbloom (second, 50% x 35%)", c.Frostbloom or 0, n, (1 - pa) * Recipes.ById.Frostbloom.Chance)
	end)

	t.it("at most one hybrid per monster", function()
		local r = resolve("Mossling", "FrostfallTundra")
		local c = trial(r, { "FrozenCore", "Frostbloom" }, 500, 11)
		t.eq(c["<none>"], 500, "already has a hybrid")
	end)

	t.it("full rolls: hybrids only come from recipes, never from normal slots or pity", function()
		local gen = MonsterGenerationService.new(Registry, svc)
		local rng = Random.new(12)
		local ctx = { SpeciesId = "Pebbleback", BiomeId = "FrostfallTundra", Catalysts = { "GlacierCrystal" } }
		local withFrost, shells = 0, 0
		for i = 1, 15000 do
			local rec, roll = gen:Generate(1, ctx, rng, { Pity = i % 3 == 0 })
			local hasFrost, hasShell = false, false
			for _, m in roll.Mutations do
				hasFrost = hasFrost or (m.Category == "Elemental" and m.Element == "Frost")
				hasShell = hasShell or m.Id == "PermafrostShell"
			end
			for _, e in roll.Log do
				if e.Category == "Hybrid" then
					t.eq(e.Outcome, "HybridFormed", "hybrid only via recipe")
				end
			end
			t.eq(hasShell, hasFrost, "guaranteed shell exactly when a Frost elemental rolled")
			if hasShell then
				t.eq(rec.HybridRecipe, "PermafrostShell", "recipe recorded")
				shells += 1
			end
			if hasFrost then
				withFrost += 1
			end
			t.ok(gen:ValidateRecord(rec), "record valid")
			if i % 3000 == 0 then
				task.wait()
			end
		end
		t.log(string.format("Pebbleback + Glacier Crystal: %d / 15000 rolled a Frost elemental -> %d Permafrost Shells", withFrost, shells))
		t.ok(shells > 0, "some shells formed")
	end)

	t.it("odds report explains each recipe's status", function()
		local function find(rep, id)
			for _, h in rep.Hybrids do
				if h.RecipeId == id then
					return h
				end
			end
		end
		local plain = find(svc:GetOddsReport({ SpeciesId = "Pebbleback", BiomeId = "FrostfallTundra" }), "PermafrostShell")
		t.eq(plain.BlockedBy, "Catalyst", "tells you the catalyst is missing")
		local ready = find(svc:GetOddsReport({ SpeciesId = "Pebbleback", BiomeId = "FrostfallTundra", Catalysts = { "GlacierCrystal" } }), "PermafrostShell")
		t.ok(ready.ConditionsMet and ready.Guaranteed, "ready + guaranteed")
		t.ok(ready.InputsFromSpecies["Element:Earthen"], "species supplies Earthen")
		t.ok(not ready.InputsFromSpecies["Element:Frost"], "Frost must still roll")
		local aur = find(svc:GetOddsReport({ SpeciesId = "Snowmote", BiomeId = "FrostfallTundra" }), "PrismaticAurora")
		t.eq(aur.BlockedBy, "Event", "event requirement reported")
	end)
end
