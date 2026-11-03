-- Renders every player's equipped monsters as followers (client-side, so it costs
-- the server nothing). The server only publishes their looks via the "EquippedPets"
-- player attribute (a JSON list in slot order); each slot walks at its own spot in
-- a fan behind the owner. Motion is smoothed with exponential damping; walkers hop
-- while moving (footstep puff on each landing) and bob when idle; floaters hover.
-- The local player's pets never appear while an egg-hatch reveal is playing
-- (LocalPlayer attribute "RevealActive"); they hatch into the world afterwards.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("MonsterFactory"):WaitForChild("Shared")
local MonsterVisuals = require(Shared.MonsterVisuals)
local MonsterEffects = require(Shared.MonsterEffects)
local Species = require(Shared.Species)

local PET_SCALE = 0.75
-- Where each slot walks, relative to the owner's facing (+X right, +Z behind).
local SLOT_OFFSETS = {
	Vector3.new(3.2, 0, 3.0),
	Vector3.new(-3.2, 0, 3.0),
	Vector3.new(0, 0, 5.6),
	Vector3.new(4.6, 0, 7.2),
	Vector3.new(-4.6, 0, 7.2),
	Vector3.new(0, 0, 9.6),
}
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
	OffsetScale: number,
	Pos: Vector3,
	Yaw: number,
	Hop: number,
	Phase: number,
	Burst: boolean?,
}
local pets: { [Player]: { [string]: Pet } } = {} -- [owner][MonsterId]

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function removePets(player: Player)
	for _, pet in pets[player] or {} do
		pet.Model:Destroy()
	end
	pets[player] = nil
end

local localPlayer = Players.LocalPlayer

local function slotOffset(slot: number): Vector3
	return SLOT_OFFSETS[slot] or SLOT_OFFSETS[#SLOT_OFFSETS] + Vector3.new(0, 0, 2.4 * (slot - #SLOT_OFFSETS))
end

local function buildPet(player: Player, info: any, key: string, slot: number): Pet
	local genes = table.clone(info.Genes or {})
	genes.SizeGene = (genes.SizeGene or 1) * PET_SCALE
	local model = MonsterVisuals.Build(info.SpeciesId, genes, info.ActiveMutations, { Seed = #(info.MonsterId or ""), RarityTier = info.RarityTier })
	model.Name = player.Name .. "_Pet" .. slot
	local bbox, size = model:GetBoundingBox()
	local groundOffset = model:GetPivot().Position.Y - (bbox.Position.Y - size.Y / 2)
	model.Parent = folder
	local effects = MonsterEffects.Apply(model, info.PrimaryElement, info.RarityTier or 1)
	-- Bigger (rarer) monsters walk a little further out.
	local offsetScale = math.max(1, size.X / 3.5)
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local bodyType = Species.ById[info.SpeciesId].BodyType
	return {
		Offset = slotOffset(slot) * offsetScale,
		OffsetScale = offsetScale,
		SpawnT = os.clock(),
		Model = model,
		Effects = effects,
		Key = key,
		Floating = bodyType == "Floating" or bodyType == "Winged",
		GroundOffset = groundOffset,
		Pos = if root then root.Position + slotOffset(slot) else Vector3.zero,
		Yaw = 0,
		Hop = 0,
		Phase = math.random() * 6,
	}
end

-- Brings a player's followers in line with their attribute: unchanged pets stay
-- (only their slot spot moves), new or changed ones are (re)built.
local function syncPets(player: Player)
	if player == localPlayer and localPlayer:GetAttribute("RevealActive") then
		removePets(player) -- wait for the egg to hatch first
		return
	end
	local raw = player:GetAttribute("EquippedPets")
	local ok, list = pcall(HttpService.JSONDecode, HttpService, if type(raw) == "string" and raw ~= "" then raw else "[]")
	if not ok or type(list) ~= "table" then
		list = {}
	end
	local old = pets[player] or {}
	local new = {}
	for slot, info in list do
		if type(info) ~= "table" or type(info.MonsterId) ~= "string" or not Species.ById[info.SpeciesId] then
			continue
		end
		local key = HttpService:JSONEncode(info)
		local pet = old[info.MonsterId]
		if pet and pet.Key == key then
			old[info.MonsterId] = nil
			pet.Offset = slotOffset(slot) * pet.OffsetScale
		else
			pet = buildPet(player, info, key, slot)
		end
		new[info.MonsterId] = pet
	end
	for _, pet in old do
		pet.Model:Destroy()
	end
	pets[player] = if next(new) then new else nil
end

local function watch(player: Player)
	player:GetAttributeChangedSignal("EquippedPets"):Connect(function()
		syncPets(player)
	end)
	syncPets(player)
end
for _, p in Players:GetPlayers() do
	task.spawn(watch, p)
end
Players.PlayerAdded:Connect(watch)
Players.PlayerRemoving:Connect(removePets)
localPlayer:GetAttributeChangedSignal("RevealActive"):Connect(function()
	syncPets(localPlayer)
end)

local function groundHeight(pos: Vector3, exclude: { Instance }): number?
	rayParams.FilterDescendantsInstances = exclude
	local hit = workspace:Raycast(pos + Vector3.new(0, 6, 0), Vector3.new(0, -20, 0), rayParams)
	return hit and hit.Position.Y
end

local clock = 0

local function stepPet(pet: Pet, char: Model, root: BasePart, dt: number, camPos: Vector3?)
	-- Target: this slot's spot behind the owner, relative to where they face.
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

RunService.RenderStepped:Connect(function(dt)
	clock += dt
	local camPos = workspace.CurrentCamera and workspace.CurrentCamera.CFrame.Position
	for player, list in pets do
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not (char and root) then
			continue
		end
		for _, pet in list do
			if pet.Model.Parent then
				stepPet(pet, char, root, dt, camPos)
			end
		end
	end
end)
