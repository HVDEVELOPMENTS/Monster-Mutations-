-- Renders every player's equipped monster as a follower (client-side, so it costs
-- the server nothing). The server only publishes the look via the "EquippedPet"
-- player attribute. Motion is smoothed with exponential damping; walkers hop while
-- moving (footstep puff on each landing) and bob when idle; floaters hover.
-- The local player's pet never appears while an egg-hatch reveal is playing
-- (LocalPlayer attribute "RevealActive"); it hatches into the world afterwards.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("MonsterFactory"):WaitForChild("Shared")
local MonsterVisuals = require(Shared.MonsterVisuals)
local MonsterEffects = require(Shared.MonsterEffects)
local Species = require(Shared.Species)

local PET_SCALE = 0.75
local FOLLOW_OFFSET = Vector3.new(3.2, 0, 3.0) -- right of and behind the owner
local FOLLOW_SPEED = 7 -- higher = snappier
local HOP_HEIGHT = 0.7
local HOP_RATE = 2.4 -- hops per second at walking speed

local folder = workspace:FindFirstChild("ClientPets") or Instance.new("Folder")
folder.Name = "ClientPets"
folder.Parent = workspace

type Pet = {
	Offset: Vector3,
	SpawnT: number,
	Model: Model,
	Effects: any,
	Key: string,
	Floating: boolean,
	GroundOffset: number,
	Pos: Vector3,
	Yaw: number,
	Hop: number,
	Phase: number,
	Burst: boolean?,
}
local pets: { [Player]: Pet } = {}

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function removePet(player: Player)
	local pet = pets[player]
	if pet then
		pet.Model:Destroy()
		pets[player] = nil
	end
end

local localPlayer = Players.LocalPlayer

local function buildPet(player: Player)
	if player == localPlayer and localPlayer:GetAttribute("RevealActive") then
		removePet(player) -- wait for the egg to hatch first
		return
	end
	local raw = player:GetAttribute("EquippedPet")
	if type(raw) ~= "string" or raw == "" then
		removePet(player)
		return
	end
	if pets[player] and pets[player].Key == raw then
		return
	end
	local ok, info = pcall(HttpService.JSONDecode, HttpService, raw)
	if not ok or type(info) ~= "table" or not Species.ById[info.SpeciesId] then
		removePet(player)
		return
	end
	removePet(player)
	local genes = table.clone(info.Genes or {})
	genes.SizeGene = (genes.SizeGene or 1) * PET_SCALE
	local model = MonsterVisuals.Build(info.SpeciesId, genes, info.ActiveMutations, { Seed = #(info.MonsterId or ""), RarityTier = info.RarityTier })
	model.Name = player.Name .. "_Pet"
	local bbox, size = model:GetBoundingBox()
	local groundOffset = model:GetPivot().Position.Y - (bbox.Position.Y - size.Y / 2)
	model.Parent = folder
	local effects = MonsterEffects.Apply(model, info.PrimaryElement, info.RarityTier or 1)
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local start = if root then root.Position + FOLLOW_OFFSET else Vector3.zero
	-- Bigger (rarer) monsters walk a little further out.
	local offsetScale = math.max(1, size.X / 3.5)
	pets[player] = {
		Offset = FOLLOW_OFFSET * offsetScale,
		SpawnT = os.clock(),
		Model = model,
		Effects = effects,
		Key = raw,
		Floating = Species.ById[info.SpeciesId].BodyType == "Floating" or Species.ById[info.SpeciesId].BodyType == "Winged",
		GroundOffset = groundOffset,
		Pos = start,
		Yaw = 0,
		Hop = 0,
		Phase = math.random() * 6,
	}
end

local function watch(player: Player)
	player:GetAttributeChangedSignal("EquippedPet"):Connect(function()
		buildPet(player)
	end)
	buildPet(player)
end
for _, p in Players:GetPlayers() do
	task.spawn(watch, p)
end
Players.PlayerAdded:Connect(watch)
Players.PlayerRemoving:Connect(removePet)
localPlayer:GetAttributeChangedSignal("RevealActive"):Connect(function()
	buildPet(localPlayer)
end)

local function groundHeight(pos: Vector3, exclude: { Instance }): number?
	rayParams.FilterDescendantsInstances = exclude
	local hit = workspace:Raycast(pos + Vector3.new(0, 6, 0), Vector3.new(0, -20, 0), rayParams)
	return hit and hit.Position.Y
end

local clock = 0
RunService.RenderStepped:Connect(function(dt)
	clock += dt
	local camPos = workspace.CurrentCamera and workspace.CurrentCamera.CFrame.Position
	for player, pet in pets do
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not root or not pet.Model.Parent then
			continue
		end
		-- Target: beside/behind the owner, relative to where they face.
		local rootCf = root.CFrame
		local flatLook = Vector3.new(rootCf.LookVector.X, 0, rootCf.LookVector.Z)
		if flatLook.Magnitude < 1e-3 then
			flatLook = Vector3.new(0, 0, -1)
		end
		local basis = CFrame.lookAt(Vector3.zero, flatLook.Unit)
		local target = root.Position + basis:VectorToWorldSpace(pet.Offset)
		if (target - pet.Pos).Magnitude > 60 then
			pet.Pos = target -- teleported / respawned: snap
		end
		local alpha = 1 - math.exp(-FOLLOW_SPEED * dt)
		local prev = pet.Pos
		pet.Pos = pet.Pos:Lerp(target, alpha)
		local vel = (pet.Pos - prev) / math.max(dt, 1e-3)
		local speed = Vector3.new(vel.X, 0, vel.Z).Magnitude

		-- Face the movement direction while moving, else the owner's facing.
		local faceDir = if speed > 0.8 then Vector3.new(vel.X, 0, vel.Z).Unit else flatLook.Unit
		local targetYaw = math.atan2(-faceDir.X, -faceDir.Z)
		local dy = (targetYaw - pet.Yaw + math.pi) % (2 * math.pi) - math.pi
		pet.Yaw += dy * (1 - math.exp(-10 * dt))

		local ground = groundHeight(pet.Pos, { folder, char }) or (root.Position.Y - 3)
		local y = ground + pet.GroundOffset
		local tilt = 0
		if pet.Floating then
			y += 1.2 + math.sin(clock * 2 + pet.Phase) * 0.35
			tilt = math.clamp(speed * 0.03, 0, 0.25)
		elseif speed > 0.8 then
			local before = pet.Hop
			pet.Hop += dt * HOP_RATE * math.clamp(speed / 12, 0.6, 1.6)
			if math.floor(pet.Hop) > math.floor(before) then
				pet.Effects.Step() -- landed
			end
			y += math.abs(math.sin(pet.Hop * math.pi)) * HOP_HEIGHT
			tilt = 0.12
		else
			pet.Hop = 0
			y += math.abs(math.sin(clock * 1.6 + pet.Phase)) * 0.12
		end
		-- Hatch-in: drop in with a bounce and a burst of puffs during the first 0.6 s.
		local age = os.clock() - pet.SpawnT
		if age < 0.6 then
			y += (1 - age / 0.6) * 3 * math.abs(math.cos(age * 8))
			if not pet.Burst then
				pet.Burst = true
				for _ = 1, 3 do
					pet.Effects.Step()
				end
			end
		end
		pet.Model:PivotTo(CFrame.new(pet.Pos.X, y, pet.Pos.Z) * CFrame.Angles(0, pet.Yaw, 0) * CFrame.Angles(-tilt, 0, 0))
		MonsterVisuals.AnimatePose(pet.Model, clock + pet.Phase, math.clamp(speed / 10, 0, 1))
		MonsterVisuals.Animate(pet.Model, clock)
		pet.Effects.Update(clock, camPos)
	end
end)
