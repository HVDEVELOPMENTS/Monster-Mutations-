local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Registry = require(ReplicatedStorage.MonsterFactory.Shared.Registry)
local MutationService = require(script.Parent.Parent.Services.MutationService)

local M = Registry.Mutations.ById

return function(t)
	local svc = MutationService.new(Registry)

	local function resolve(ctx)
		local r, err = svc:Resolve(ctx)
		assert(r, "resolve failed: " .. tostring(err))
		return r
	end
	local function eligible(id, ctx, chosen)
		return (svc:CheckEligibility(M[id], resolve(ctx), chosen))
	end
	local base = { SpeciesId = "Mossling", BiomeId = "VerdantMeadows" }

	t.it("rejects invalid input", function()
		local cases = {
			{ { SpeciesId = "Nope", BiomeId = "VerdantMeadows" }, "UnknownSpecies" },
			{ { SpeciesId = "Mossling", BiomeId = "Nope" }, "UnknownBiome" },
			{ { SpeciesId = "Mossling", BiomeId = "VerdantMeadows", Catalysts = { "Fake" } }, "UnknownCatalyst" },
			{ { SpeciesId = "Mossling", BiomeId = "VerdantMeadows", Catalysts = { "Dewdrop", "Dewdrop" } }, "DuplicateCatalyst" },
			{ { SpeciesId = "Mossling", BiomeId = "VerdantMeadows", Catalysts = { "Dewdrop", "FertileSoil", "AncientSeed", "Dewdrop" } }, "TooManyCatalysts" },
			{ { SpeciesId = 5, BiomeId = "VerdantMeadows" }, "UnknownSpecies" },
			{ "garbage", "BadContext" },
		}
		for _, c in cases do
			local r, err = svc:Resolve(c[1])
			t.eq(r, nil, c[2])
			t.eq(err, c[2], "error code")
		end
	end)

	t.it("biome-locked mutation only in its biome and environment", function()
		t.ok(not eligible("FrostedCoat", base), "FrostedCoat must not appear in Verdant")
		t.ok(eligible("FrostedCoat", { SpeciesId = "Mossling", BiomeId = "FrostfallTundra" }), "eligible in Frostfall")
	end)

	t.it("respects species attachments", function()
		t.ok(eligible("Springtail", { SpeciesId = "Brookhopper", BiomeId = "VerdantMeadows" }), "Brookhopper has a tail")
		t.ok(not eligible("Springtail", { SpeciesId = "Pebbleback", BiomeId = "VerdantMeadows" }), "Pebbleback has no tail")
		t.ok(not eligible("PebblePlating", { SpeciesId = "Brookhopper", BiomeId = "VerdantMeadows" }), "Brookhopper has no Back")
	end)

	t.it("respects element requirements", function()
		t.ok(eligible("AncientBarkArmour", { SpeciesId = "Pebbleback", BiomeId = "VerdantMeadows" }), "Earthen ok")
		t.ok(not eligible("BioluminescentLeaves", { SpeciesId = "Pebbleback", BiomeId = "VerdantMeadows" }), "needs Verdant")
	end)

	t.it("catalyst unlocks gated mutations", function()
		t.ok(not eligible("CrystalDew", base), "locked without Dewdrop")
		t.ok(eligible("CrystalDew", { SpeciesId = "Mossling", BiomeId = "VerdantMeadows", Catalysts = { "Dewdrop" } }), "unlocked")
	end)

	t.it("research and progression gates", function()
		t.ok(not eligible("WorldtreeSeed", base), "no research")
		t.ok(not eligible("WorldtreeSeed", { SpeciesId = "Mossling", BiomeId = "VerdantMeadows", Research = { WorldtreeStudy = true } }), "research but low progression")
		t.ok(eligible("WorldtreeSeed", { SpeciesId = "Mossling", BiomeId = "VerdantMeadows", Research = { WorldtreeStudy = true }, Progression = 10 }), "both met")
	end)

	t.it("duplicate, exclusive group and incompatibility rules", function()
		t.ok(not eligible("PebblePlating", base, { M.PebblePlating }), "duplicate")
		t.ok(not eligible("LivingGrove", base, { M.PebblePlating }), "same Armour group")
		t.ok(not eligible("BioluminescentLeaves", base, { M.PebblePlating }), "incompatible (declared on new)")
		t.ok(not eligible("PebblePlating", base, { M.BioluminescentLeaves }), "incompatible (declared on existing)")
		t.ok(eligible("DewdropEyes", base, { M.PebblePlating }), "unrelated is fine")
	end)

	t.it("tier multiplier changes and renormalises the advertised odds", function()
		local plain = svc:GetOddsReport(base)
		local soil = svc:GetOddsReport({ SpeciesId = "Mossling", BiomeId = "VerdantMeadows", Catalysts = { "FertileSoil" } })
		local function tiers(rep, cat)
			for _, c in rep.Categories do
				if c.Category == cat then
					return c.Tiers
				end
			end
		end
		local a, b = tiers(plain, "Physical"), tiers(soil, "Physical")
		t.ok(b[3].Probability > a[3].Probability, "Rare up")
		t.ok(b[1].Probability < a[1].Probability, "Common down after renormalising")
		local sum = 0
		for _, tr in b do
			sum += tr.Probability
		end
		t.near(sum, 1, 1e-9, "tier probs sum")
		t.near(tiers(soil, "Pattern")[3].Probability, tiers(plain, "Pattern")[3].Probability, 1e-12, "other category untouched")
	end)

	t.it("odds report: candidates + empty chance sum to 1 per category", function()
		for _, sp in { "Mossling", "Pebbleback", "Brookhopper" } do
			local rep = svc:GetOddsReport({ SpeciesId = sp, BiomeId = "VerdantMeadows", Catalysts = { "Dewdrop", "AncientSeed" } })
			for _, c in rep.Categories do
				local sum = c.EmptyChance
				for _, cand in c.Candidates do
					sum += cand.Probability
				end
				t.near(sum, 1, 1e-9, sp .. "/" .. c.Category)
			end
		end
	end)

	t.it("same seed gives same roll", function()
		local a = svc:Roll(base, Random.new(42))
		local b = svc:Roll(base, Random.new(42))
		t.eq(#a.Mutations, #b.Mutations, "count")
		for i, m in a.Mutations do
			t.eq(m.Id, b.Mutations[i].Id, "mutation " .. i)
		end
	end)

	t.it("20k rolls never break slot limits or compatibility rules", function()
		local rng = Random.new(7)
		local species = { "Mossling", "Pebbleback", "Brookhopper" }
		for i = 1, 20000 do
			local sp = species[(i % 3) + 1]
			local ctx = { SpeciesId = sp, BiomeId = "VerdantMeadows", Catalysts = { "Dewdrop", "FertileSoil", "AncientSeed" } }
			local res = svc:Roll(ctx, rng)
			local r = res.Resolved
			local perCat, seen, groups = {}, {}, {}
			for idx, m in res.Mutations do
				perCat[m.Category] = (perCat[m.Category] or 0) + 1
				t.ok(not seen[m.Id], "duplicate " .. m.Id)
				seen[m.Id] = true
				if m.ExclusiveGroup then
					t.ok(not groups[m.ExclusiveGroup], "exclusive group " .. m.ExclusiveGroup)
					groups[m.ExclusiveGroup] = true
				end
				local before = table.move(res.Mutations, 1, idx - 1, 1, {})
				local ok, why = svc:CheckEligibility(m, r, before)
				t.ok(ok, m.Id .. " ineligible on " .. sp .. ": " .. tostring(why))
			end
			for catId, n in perCat do
				t.ok(n <= Registry.Categories.ById[catId].MaxSlots, "slot limit " .. catId)
			end
			if i % 2000 == 0 then
				task.wait()
			end
		end
	end)
end
