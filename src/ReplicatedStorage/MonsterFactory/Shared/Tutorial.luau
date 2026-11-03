--!strict
-- Getting Started guide for new players: one simple goal at a time. Each step's
-- completion is worked out from progress the player already has (hatches,
-- monsters, gathering, battle wins, fusions), so the server (reward) and the
-- client (tracker, pointers) agree without extra saved state.

local Tutorial = {}

-- Pointer: what the client points at ("Chamber" = the HATCH/OPEN button,
-- "HatchMenu" = the Hatch menu button, "Gather" / "Wild" = nearest world spot).
export type Step = { Id: string, Title: string, Text: string, Pointer: string, Goal: number? }

Tutorial.Steps = {
	{ Id = "Hatch", Title = "Make a monster!", Text = "Press the green HATCH! button to put an egg in your chamber.", Pointer = "Chamber" },
	{ Id = "Open", Title = "Open your egg!", Text = "Wait for the egg to wobble, then press OPEN!", Pointer = "Chamber" },
	{ Id = "Gather", Title = "Pick a glowing flower!", Text = "Follow the sparkly trail, walk up to the flower and hold E.", Pointer = "Gather" },
	{ Id = "Battle", Title = "Win a battle!", Text = "Follow the trail to a wild monster, press E and pick a move!", Pointer = "Wild" },
	{ Id = "Collect", Title = "Hatch 5 eggs!", Text = "Keep pressing HATCH! to grow your monster team.", Pointer = "Chamber", Goal = 5 },
	{ Id = "Fuse", Title = "Fuse two monsters!", Text = "Open Hatch, press FUSE MONSTERS and pick two monsters from the same place.", Pointer = "HatchMenu" },
} :: { Step }

-- Coins for finishing every step (paid once, by the server).
Tutorial.Reward = 250

export type Progress = { Monsters: number, Eggs: number, Hatched: number, Gathered: boolean, BattleWins: number, Fusions: number }

local function count(t: any): number
	local n = 0
	for _ in t or {} do
		n += 1
	end
	return n
end

-- From saved player data (server).
function Tutorial.FromData(data: any): Progress
	return {
		Monsters = count(data.Monsters),
		Eggs = count(data.Incubations),
		Hatched = (data.Stats and data.Stats.Incubations) or 0,
		Gathered = next(data.GatherCooldowns or {}) ~= nil,
		BattleWins = ((data.Battles and data.Battles.Wins) or 0) + ((data.Battles and data.Battles.PvPWins) or 0),
		Fusions = (data.Stats and data.Stats.Fusions) or 0,
	}
end

-- From the client state push (same fields, Monsters/Incubations are lists).
function Tutorial.FromState(state: any): Progress
	return Tutorial.FromData(state)
end

-- How far along a step is: returns (done, current, goal) for counting steps.
function Tutorial.StepStatus(step: Step, p: Progress): (boolean, number?, number?)
	if step.Id == "Hatch" then
		return p.Eggs > 0 or p.Monsters > 0 or p.Hatched > 0
	elseif step.Id == "Open" then
		return p.Monsters > 0 or p.Fusions > 0
	elseif step.Id == "Gather" then
		return p.Gathered
	elseif step.Id == "Battle" then
		return p.BattleWins > 0
	elseif step.Id == "Collect" then
		local goal = step.Goal or 5
		return p.Hatched >= goal, math.min(p.Hatched, goal), goal
	elseif step.Id == "Fuse" then
		return p.Fusions > 0
	end
	return true
end

-- Index of the first unfinished step, or nil when everything is done.
function Tutorial.Current(p: Progress): number?
	for i, step in Tutorial.Steps do
		if not Tutorial.StepStatus(step, p) then
			return i
		end
	end
	return nil
end

return Tutorial
