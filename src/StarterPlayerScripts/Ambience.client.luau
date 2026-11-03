-- Wind sway for world props (client-side, so it costs the server nothing).
-- WorldBuilder tags swaying pieces "Sway" with a SwayBase (ground point they bend
-- about) and SwayAmp (max bend in radians). Each piece bends away from
-- workspace.GlobalWind; a wave travels along the wind and slow gusts swell it, so
-- grass ripples across the meadow. Only pieces near the camera are animated, all
-- in one BulkMoveTo per frame.

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local RADIUS = 170 -- studs from the camera
local REFRESH = 0.4 -- seconds between rebuilding the near list
local WAVE_LENGTH = 0.07 -- radians of phase per stud along the wind
local WAVE_SPEED = 2.2
local BASE_WIND = 7.6 -- GlobalWind magnitude that gives the authored SwayAmp

type Item = { Part: BasePart, Rest: CFrame, Base: Vector3, Amp: number, Phase: number, Rate: number }

local items: { [BasePart]: Item } = {}
local near: { Item } = {}
local rng = Random.new()

local function add(inst: Instance)
	if not inst:IsA("BasePart") then
		return
	end
	local base = inst:GetAttribute("SwayBase")
	local amp = inst:GetAttribute("SwayAmp")
	if typeof(base) ~= "Vector3" or type(amp) ~= "number" then
		return
	end
	-- Big foliage moves slowly; blades and petals flutter.
	local rate = if amp < 0.1 then 0.55 else 1
	items[inst] = { Part = inst, Rest = inst.CFrame, Base = base, Amp = amp, Phase = rng:NextNumber(0, 0.8), Rate = rate }
end

local function remove(inst: Instance)
	items[inst :: BasePart] = nil
end

CollectionService:GetInstanceAddedSignal("Sway"):Connect(add)
CollectionService:GetInstanceRemovedSignal("Sway"):Connect(remove)
for _, inst in CollectionService:GetTagged("Sway") do
	add(inst)
end

local parts: { BasePart } = {}
local cframes: { CFrame } = {}
local sinceRefresh = math.huge
local wasNear: { [Item]: boolean } = {}

RunService.RenderStepped:Connect(function(dt)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local camPos = camera.CFrame.Position

	sinceRefresh += dt
	if sinceRefresh >= REFRESH then
		sinceRefresh = 0
		local nowNear = {}
		table.clear(near)
		for _, item in items do
			if item.Part.Parent and (item.Base - camPos).Magnitude < RADIUS then
				table.insert(near, item)
				nowNear[item] = true
			end
		end
		-- Pieces that left the radius settle back to rest.
		table.clear(parts)
		table.clear(cframes)
		for item in wasNear do
			if not nowNear[item] and item.Part.Parent then
				table.insert(parts, item.Part)
				table.insert(cframes, item.Rest)
			end
		end
		if #parts > 0 then
			workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
		end
		wasNear = nowNear
	end
	if #near == 0 then
		return
	end

	local wind = workspace.GlobalWind
	local flat = Vector3.new(wind.X, 0, wind.Z)
	local strength = flat.Magnitude / BASE_WIND
	if strength < 0.01 then
		return
	end
	local dir = flat.Unit
	local axis = Vector3.yAxis:Cross(dir) -- bending about this tips tops toward dir
	local t = os.clock()
	local gust = 0.75 + 0.2 * math.sin(t * 0.37) + 0.12 * math.sin(t * 1.31 + 1)

	table.clear(parts)
	table.clear(cframes)
	for _, item in near do
		local wave = item.Base:Dot(dir) * WAVE_LENGTH - t * WAVE_SPEED * item.Rate + item.Phase
		-- Mostly leaning with the wind, oscillating around that lean.
		local angle = item.Amp * strength * gust * (0.55 + 0.45 * math.sin(wave))
		local pivot = CFrame.new(item.Base)
		table.insert(parts, item.Part)
		table.insert(cframes, pivot * CFrame.fromAxisAngle(axis, angle) * pivot:Inverse() * item.Rest)
	end
	workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
end)
