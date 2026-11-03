-- Monster Fusion panel (opened from the Hatch panel). Pick two monsters from
-- the same place; the panel shows what they will make (rules in Shared/Fusion)
-- and the server does the real fusion, then the new monster is revealed.
-- Kid-friendly: after the first pick, only monsters that can fuse with it stay
-- bright; everything else is greyed out.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("MonsterFactory"):WaitForChild("Shared")
local Fusion = require(Shared.Fusion)
local Species = require(Shared.Species)
local Biomes = require(Shared.Biomes)
local Rarity = require(Shared.Rarity)
local UI = require(script.Parent.UIKit)

local FusionUI = {}

-- ctx: { Panel, GetState: () -> any, R: any, ShowError: (string?) -> (), Reveal: any }
function FusionUI.Init(ctx)
	local panel = ctx.Panel
	local content = panel.Content
	local picks: { string? } = { nil, nil }
	local busy = false

	-- Left: your monsters.
	UI.Label(content, "Pick 2 monsters from the same place", {
		Size = UDim2.new(0.58, 0, 0, 28),
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	local grid = UI.new("ScrollingFrame", {
		BackgroundColor3 = UI.Colors.PanelDark,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, 34),
		Size = UDim2.new(0.58, 0, 1, -34),
		ScrollBarThickness = 8,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		Parent = content,
	})
	UI.Corner(grid, 12)
	UI.Padding(grid, 8)
	UI.new("UIGridLayout", { CellSize = UDim2.fromOffset(118, 132), CellPadding = UDim2.fromOffset(8, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = grid })

	-- Right: A + B = ?
	local right = UI.new("Frame", { BackgroundTransparency = 1, Position = UDim2.fromScale(0.61, 0), Size = UDim2.fromScale(0.39, 1), Parent = content })
	local function slotFrame(x: number, label: string)
		local f = UI.new("TextButton", {
			Text = "",
			AutoButtonColor = false,
			BackgroundColor3 = UI.Colors.Card,
			Position = UDim2.new(x, 0, 0, 0),
			Size = UDim2.new(0.42, 0, 0, 150),
			Parent = right,
		})
		UI.Corner(f, 14)
		UI.Stroke(f, 3)
		local hint = UI.Label(f, label, { Name = "Hint", Size = UDim2.new(1, -10, 0, 40), Position = UDim2.new(0, 5, 0.5, -20), TextColor3 = UI.Colors.Muted })
		local holder = UI.new("Frame", { Name = "Holder", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, -26), Parent = f })
		local name = UI.Label(f, "", { Name = "NameLabel", Size = UDim2.new(1, -8, 0, 22), Position = UDim2.new(0, 4, 1, -26) })
		return f, holder, name, hint
	end
	local slotA, holderA, nameA, hintA = slotFrame(0, "Pick a monster")
	local slotB, holderB, nameB, hintB = slotFrame(0.58, "Pick another")
	UI.Label(right, "+", { Size = UDim2.new(0.16, 0, 0, 60), Position = UDim2.new(0.42, 0, 0, 45), MaxTextSize = 60 })
	UI.Label(right, "=", { Size = UDim2.new(1, 0, 0, 40), Position = UDim2.fromOffset(0, 154), MaxTextSize = 44 })
	local result = UI.new("Frame", { BackgroundColor3 = UI.Colors.PanelDark, Position = UDim2.fromOffset(0, 196), Size = UDim2.new(1, 0, 0, 170), Parent = right })
	UI.Corner(result, 14)
	UI.Stroke(result, 3)
	local resultHolder = UI.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(0.5, 0, 1, 0), Parent = result })
	local resultText = UI.Label(result, "?", {
		Size = UDim2.new(0.5, -10, 1, -16),
		Position = UDim2.new(0.5, 0, 0, 8),
		TextWrapped = true,
		MaxTextSize = 26,
	})
	local fuseBtn = UI.Button(right, "FUSE!", UI.Colors.Purple, { Name = "FuseButton", Size = UDim2.new(1, 0, 0, 64), Position = UDim2.fromOffset(0, 378) })
	UI.Label(right, "Both monsters are used up to make the new one.", {
		Size = UDim2.new(1, 0, 0, 20),
		Position = UDim2.fromOffset(0, 448),
		TextColor3 = UI.Colors.Muted,
	})

	local function owned(id: string?)
		local state = ctx.GetState()
		if not (state and id) then
			return nil
		end
		for _, rec in state.Monsters do
			if rec.MonsterId == id then
				return rec
			end
		end
		return nil
	end

	local function showIn(holder: Frame, speciesId: string?, rec: any?, silhouette: boolean?)
		for _, c in holder:GetChildren() do
			c:Destroy()
		end
		if speciesId then
			UI.MonsterViewport(holder, speciesId, rec and rec.Genes or { BaseColorGene = Species.ById[speciesId].Palettes[1] }, rec and rec.ActiveMutations or {}, {
				Spin = 0.5,
				Silhouette = silhouette,
				RarityTier = rec and rec.RarityTier,
			})
		end
	end

	local refresh: () -> ()
	local function pick(id: string)
		if picks[1] == id or picks[2] == id then
			return
		end
		if not picks[1] then
			picks[1] = id
		elseif not picks[2] then
			picks[2] = id
		else
			picks[2] = id -- replace the second pick
		end
		UI.Play("Pop", 1.2, 0.4)
		refresh()
	end
	slotA.Activated:Connect(function()
		picks[1], picks[2] = picks[2], nil
		refresh()
	end)
	slotB.Activated:Connect(function()
		picks[2] = nil
		refresh()
	end)

	refresh = function()
		local state = ctx.GetState()
		if not state then
			return
		end
		-- Drop picks that were sold/fused meanwhile.
		for i = 1, 2 do
			if picks[i] and not owned(picks[i]) then
				picks[i] = nil
			end
		end
		if not picks[1] and picks[2] then
			picks[1], picks[2] = picks[2], nil
		end
		local a, b = owned(picks[1]), owned(picks[2])
		for _, set in { { a, holderA, nameA, hintA }, { b, holderB, nameB, hintB } } do
			local rec, holder, name, hint = set[1], set[2], set[3], set[4]
			showIn(holder, rec and rec.SpeciesId, rec)
			name.Text = if rec then rec.DisplayName else ""
			hint.Visible = rec == nil
		end

		local outId, why = nil, nil
		if a and b then
			outId, why = Fusion.ResultFor(a.SpeciesId, b.SpeciesId)
		end
		local known = outId and state.Discoveries.Species[outId] ~= nil
		showIn(resultHolder, outId, nil, outId ~= nil and not known)
		if outId then
			local cost = Fusion.Cost(outId)
			local guaranteed = a.RarityTier >= Fusion.GuaranteeTier and b.RarityTier >= Fusion.GuaranteeTier
			resultText.Text = string.format("%s!\nCost: %d coins%s", if known then Species.ById[outId].DisplayName else "A new monster", cost, if guaranteed then "\nRARE or better!" else "")
			UI.SetDisabled(fuseBtn, state.Coins < cost)
			UI.SetButtonText(fuseBtn, if state.Coins < cost then "Need more coins" else "FUSE!")
		else
			resultText.Text = if why == "FuseSameSpecies" then "Pick two DIFFERENT monsters!" elseif why == "FuseDifferentBiome" then "They must come from the SAME place!" else "?"
			UI.SetDisabled(fuseBtn, true)
			UI.SetButtonText(fuseBtn, "FUSE!")
		end

		-- Monster cards: after the first pick, only fusable partners stay bright.
		for _, c in grid:GetChildren() do
			if c:IsA("GuiObject") then
				c:Destroy()
			end
		end
		local list = table.clone(state.Monsters)
		local function biomeOrder(biomeId: string): number
			return table.find(Biomes.List, Biomes.ById[biomeId]) or 99
		end
		table.sort(list, function(x, y)
			local bx, by = Species.ById[x.SpeciesId].HomeBiome, Species.ById[y.SpeciesId].HomeBiome
			if bx ~= by then
				return biomeOrder(bx) < biomeOrder(by)
			end
			if x.SpeciesId ~= y.SpeciesId then
				return x.SpeciesId < y.SpeciesId
			end
			return x.RarityTier > y.RarityTier
		end)
		for i, rec in list do
			local picked = rec.MonsterId == picks[1] or rec.MonsterId == picks[2]
			local fits = true
			if a and not picked then
				fits = Fusion.ResultFor(a.SpeciesId, rec.SpeciesId) ~= nil
			end
			local locked = state.Locked[rec.MonsterId] == true
			local card = UI.new("TextButton", {
				Text = "",
				AutoButtonColor = false,
				BackgroundColor3 = if picked then UI.Colors.Gold elseif fits and not locked then UI.Colors.Card else UI.Colors.PanelDark,
				LayoutOrder = i,
				Parent = grid,
			})
			UI.Corner(card, 12)
			UI.Stroke(card, if picked then 4 else 2)
			local vp = UI.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 80), Parent = card })
			if fits or picked then
				UI.MonsterViewport(vp, rec.SpeciesId, rec.Genes, rec.ActiveMutations, { Seed = #rec.MonsterId, RarityTier = rec.RarityTier })
			end
			UI.Label(card, rec.DisplayName, { Size = UDim2.new(1, -8, 0, 20), Position = UDim2.fromOffset(4, 82), TextTransparency = if fits or picked then 0 else 0.5 })
			local def = Rarity.Get(rec.RarityTier)
			UI.Label(card, if locked then "LOCKED" else def.Name, {
				Size = UDim2.new(1, -8, 0, 18),
				Position = UDim2.fromOffset(4, 106),
				TextColor3 = if locked then UI.Colors.Gold else def.Color,
			})
			card.Activated:Connect(function()
				if locked then
					ctx.ShowError("Locked")
				elseif not fits then
					ctx.ShowError(if a and a.SpeciesId == rec.SpeciesId then "FuseSameSpecies" else "FuseDifferentBiome")
				else
					pick(rec.MonsterId)
				end
			end)
		end
	end

	fuseBtn.Activated:Connect(function()
		if busy or UI.IsDisabled(fuseBtn) or not (picks[1] and picks[2]) then
			return
		end
		busy = true
		local resp = ctx.R.FuseMonsters:InvokeServer(picks[1], picks[2])
		busy = false
		if not resp or not resp.Ok then
			ctx.ShowError(resp and resp.Error)
			return
		end
		picks[1], picks[2] = nil, nil
		panel.Close()
		ctx.Reveal.Play(resp, {
			Skip = false,
			OnContinue = function()
				if (resp.LevelsGained or 0) > 0 then
					UI.Toast("LEVEL UP! You are now level " .. resp.NewLevel, UI.Colors.Gold)
				end
			end,
		})
	end)

	panel.OnOpen = refresh
	return { Refresh = function()
		if panel.IsOpen then
			refresh()
		end
	end }
end

return FusionUI
