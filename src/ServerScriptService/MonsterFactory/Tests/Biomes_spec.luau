-- Stage 8: content validation across EVERY biome. New biomes are checked
-- automatically just by adding their definitions.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.MonsterFactory.Shared
local Registry = require(Shared.Registry)
local Config = require(Shared.Config)
local Progression = require(Shared.Progression)
local MonsterVisuals = require(Shared.MonsterVisuals)
local MonsterEffects = require(Shared.MonsterEffects)
local MutationService = require(script.Parent.Parent.Services.MutationService)

local B, S, M, Mat, E = Registry.Biomes, Registry.Species, Registry.Mutations, Registry.Materials, Registry.Events

return function(t)
	local svc = MutationService.new(Registry)

	t.it("every mutation's references exist and can actually be satisfied", function()
		for _, m in M.List do
			for _, b in m.AllowedBiomes or {} do
				t.ok(B.ById[b], m.Id .. " biome " .. b)
			end
			for _, c in m.RequiredCatalysts or {} do
				local mat = Mat.ById[c]
				t.ok(mat, m.Id .. " catalyst " .. c)
				t.ok(not m.AllowedBiomes or table.find(m.AllowedBiomes, mat.SourceBiome), m.Id .. ": catalyst comes from an allowed biome")
			end
			for _, ev in m.RequiredEvents or {} do
				t.ok(E.ById[ev] and (not m.AllowedBiomes or table.find(m.AllowedBiomes, E.ById[ev].Biome)), m.Id .. ": event " .. ev .. " happens in an allowed biome")
			end
			for _, r in m.RequiredResearch or {} do
				t.ok(Progression.ResearchById[r], m.Id .. " research " .. r)
			end
			if m.Element then
				t.ok(MonsterEffects.Elements[m.Element], m.Id .. " element has effects: " .. m.Element)
			end
		end
	end)

	t.it("every species is fully defined (biome, price, palettes, rig, element effects)", function()
		for _, sp in S.List do
			t.ok(B.ById[sp.HomeBiome], sp.Id .. " home biome")
			t.ok(table.find(B.ById[sp.HomeBiome].Species, sp.Id), sp.Id .. " listed in its biome")
			t.ok(Config.Species[sp.Id], sp.Id .. " has cost/unlock level")
			t.ok(MonsterEffects.Elements[sp.PrimaryElement], sp.Id .. " element effects")
			for _, pal in sp.Palettes do
				t.ok(MonsterVisuals.Palettes[pal], sp.Id .. " palette " .. pal)
			end
			local ok, err = pcall(function()
				MonsterVisuals.Build(sp.Id, {}, {}):Destroy()
			end)
			t.ok(ok, sp.Id .. " rig builds: " .. tostring(err))
		end
	end)

	t.it("every species has a full pool in its home biome", function()
		for _, sp in S.List do
			local rep = svc:GetOddsReport({ SpeciesId = sp.Id, BiomeId = sp.HomeBiome })
			local counts = {}
			for _, c in rep.Categories do
				counts[c.Category] = #c.Candidates
			end
			t.log(string.format("%-12s %-17s Physical %d  Pattern %d  Aura %d  Elemental %d", sp.Id, sp.HomeBiome, counts.Physical, counts.Pattern, counts.Aura, counts.Elemental))
			t.ok(counts.Physical >= 4, sp.Id .. " physical options")
			t.ok(counts.Pattern >= 3 and counts.Aura >= 2 and counts.Elemental >= 2, sp.Id .. " other categories")
		end
	end)

	t.it("biome pools are distinct (only Utility traits are shared)", function()
		local pools = {}
		for _, b in B.List do
			pools[b.Id] = {}
			for _, m in M.List do
				if m.Category ~= "Hybrid" and (m.AllowedBiomes == nil or table.find(m.AllowedBiomes, b.Id)) then
					pools[b.Id][m.Id] = true
				end
			end
		end
		for i, a in B.List do
			for j = i + 1, #B.List do
				for id in pools[a.Id] do
					if pools[B.List[j].Id][id] then
						t.eq(M.ById[id].Category, "Utility", a.Id .. "/" .. B.List[j].Id .. " share " .. id)
					end
				end
			end
		end
	end)

	t.it("odds sum to 1 for every species x biome x event state", function()
		local checked = 0
		for _, b in B.List do
			local states = { {} }
			for _, ev in E.List do
				if ev.Biome == b.Id then
					table.insert(states, { [ev.Id] = true })
				end
			end
			for _, sp in S.List do
				for _, evs in states do
					local rep = assert(svc:GetOddsReport({ SpeciesId = sp.Id, BiomeId = b.Id, Events = evs, Catalysts = b.Catalysts }))
					for _, c in rep.Categories do
						local sum = c.EmptyChance
						for _, cand in c.Candidates do
							sum += cand.Probability
						end
						t.near(sum, 1, 1e-9, sp.Id .. "@" .. b.Id .. "/" .. c.Category)
					end
					checked += 1
				end
			end
			task.wait()
		end
		t.log("odds reports checked: " .. checked)
	end)

	t.it("events: inside their cycle, never overlapping within a biome", function()
		for _, b in B.List do
			local cycle = E.CycleSeconds[b.Id]
			local evs = {}
			for _, ev in E.List do
				if ev.Biome == b.Id then
					table.insert(evs, ev)
					t.ok(cycle and ev.StartOffset + ev.Duration <= cycle, ev.Id .. " fits in cycle")
				end
			end
			for i = 1, #evs do
				for j = i + 1, #evs do
					local a, c = evs[i], evs[j]
					t.ok(a.StartOffset + a.Duration <= c.StartOffset or c.StartOffset + c.Duration <= a.StartOffset, a.Id .. " vs " .. c.Id)
				end
			end
		end
	end)

	t.it("unlock requirements rise with biome order; catalysts priced; gather nodes valid", function()
		local sorted = table.clone(B.List)
		table.sort(sorted, function(a, b)
			return a.Order < b.Order
		end)
		for i = 2, #sorted do
			local p, c = sorted[i - 1].Unlock, sorted[i].Unlock
			t.ok(c.Level >= p.Level and c.MutationsDiscovered >= p.MutationsDiscovered and c.Coins >= p.Coins, sorted[i].Id .. " unlock >= previous")
		end
		for _, b in B.List do
			for _, cid in b.Catalysts do
				t.ok(Mat.ById[cid] and Mat.ById[cid].SourceBiome == b.Id, b.Id .. " catalyst " .. cid)
				t.ok(Config.CatalystPrices[cid], cid .. " has a price")
			end
		end
		for id, node in Progression.GatherNodes do
			t.ok(table.find(Progression.GatherOrder, id), id .. " listed in GatherOrder")
			t.ok(Mat.ById[node.Base] and Mat.ById[node.Base].SourceBiome == node.Biome, id .. " base material")
			for _, bonus in node.Bonus do
				t.ok(Mat.ById[bonus.Material], id .. " bonus " .. bonus.Material)
				t.ok(bonus.Event == nil or (E.ById[bonus.Event] and E.ById[bonus.Event].Biome == node.Biome), id .. " bonus event")
			end
		end
		for _, r in Registry.HybridRecipes.List do
			for _, b in r.Biomes or {} do
				t.ok(B.ById[b], r.Id .. " biome " .. b)
			end
		end
	end)
end
