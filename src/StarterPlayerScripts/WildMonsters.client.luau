-- Draws the wild monster living on each WildSpot (client-side, so it costs the
-- server nothing). The species comes from the spot's WildSpecies attribute, the
-- same one BattleService fights. Only spots near the camera get a model; each
-- idles, looks around and hops now and then. A spot you just beat is empty
-- (HiddenUntil attribute, set by the client after a win) and its prompt is off.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("MonsterFactory"):WaitForChild("Shared")
local MonsterVisuals = require(Shared.MonsterVisuals)
local Species = require(Shared.Species)

local DRAW_RADIUS = 220
local SCALE = 0.9

local folder = Instance.new("Folder")
folder.Name = "WildMonsters"
folder.Parent = workspace

type Wild = { Model: Model, Ground: number, Phase: number, Yaw: number }
local wilds: { [BasePart]: Wild } = {}

local function hidden(spot: BasePart): boolean
	local untilT = spot:GetAttribute("HiddenUntil")
	return type(untilT) == "number" and workspace:GetServerTimeNow() < untilT
end

local function build(spot: BasePart): Wild?
	local speciesId = spot:GetAttribute("WildSpecies")
	local sp = Species.ById[speciesId]
	if not sp then
		return nil
	end
	local genes = { BaseColorGene = sp.Palettes[1], SizeGene = SCALE }
	local model = MonsterVisuals.Build(speciesId, genes, {}, { Seed = #spot.Name })
	model.Name = "Wild_" .. speciesId
	local bbox, size = model:GetBoundingBox()
	local ground = model:GetPivot().Position.Y - (bbox.Position.Y - size.Y / 2)
	model.Parent = folder
	return { Model = model, Ground = ground, Phase = math.random() * 6, Yaw = math.random() * 6 }
end

local function remove(spot: BasePart)
	local w = wilds[spot]
	if w then
		w.Model:Destroy()
		wilds[spot] = nil
	end
end

CollectionService:GetInstanceRemovedSignal("WildSpot"):Connect(function(spot)
	remove(spot :: BasePart)
end)

-- Spawn/despawn by distance and respawn timers, a few times a second.
task.spawn(function()
	while true do
		local cam = workspace.CurrentCamera
		local camPos = cam and cam.CFrame.Position or Vector3.zero
		for _, inst in CollectionService:GetTagged("WildSpot") do
			local spot = inst :: BasePart
			local prompt = spot:FindFirstChildWhichIsA("ProximityPrompt")
			local gone = hidden(spot)
			if prompt then
				prompt.Enabled = not gone
			end
			local nearCam = (spot.Position - camPos).Magnitude < DRAW_RADIUS
			if nearCam and not gone then
				if not wilds[spot] then
					wilds[spot] = build(spot)
				end
			elseif wilds[spot] then
				remove(spot)
			end
		end
		task.wait(0.4)
	end
end)

local clock = 0
RunService.RenderStepped:Connect(function(dt)
	clock += dt
	for spot, w in wilds do
		-- Slowly turn to look around; a little hop every few seconds.
		w.Yaw += math.sin(clock * 0.4 + w.Phase) * dt * 0.6
		local hopT = (clock + w.Phase) % 4
		local hop = if hopT < 0.5 then math.sin(hopT / 0.5 * math.pi) * 0.8 else 0
		local base = spot.Position + Vector3.new(0, 0.15 + w.Ground + hop, 0)
		w.Model:PivotTo(CFrame.new(base) * CFrame.Angles(0, w.Yaw, 0))
		MonsterVisuals.AnimatePose(w.Model, clock + w.Phase, if hop > 0 then 0.6 else 0)
		MonsterVisuals.Animate(w.Model, clock)
	end
end)
