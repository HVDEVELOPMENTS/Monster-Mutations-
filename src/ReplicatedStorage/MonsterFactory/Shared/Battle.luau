--!strict
-- Turn-based monster battles (Pokemon style), pure rules shared by the server
-- (which runs every battle) and the client (which only shows them).
--   * Stats come from the monster record: species Power, rarity tier, and how
--     far into the world the species lives (its unlock level), so wild monsters
--     in later biomes are naturally tougher.
--   * Each monster has up to 4 moves: Tackle, two moves of its element and, if
--     it has a second element from mutations, that element's basic move.
--   * Elements beat each other in a circle (Strong table): x1.5 / x0.67 damage.

local Config = require(script.Parent.Config)
local Species = require(script.Parent.Species)

local Battle = {}

-- ===== Elements =====
-- Strong[attacker][defender] = true means x1.5 damage (and x0.67 the other way).
Battle.Strong = {
	Verdant = { Tide = true, Earthen = true },
	Ember = { Verdant = true, Frost = true, Toxic = true },
	Tide = { Ember = true, Earthen = true },
	Frost = { Verdant = true, Storm = true },
	Storm = { Tide = true, Verdant = true },
	Earthen = { Storm = true, Ember = true, Toxic = true },
	Toxic = { Verdant = true, Tide = true },
}
Battle.STRONG, Battle.WEAK = 1.5, 0.67

function Battle.ElementMultiplier(attack: string, defend: string): number
	if Battle.Strong[attack] and Battle.Strong[attack][defend] then
		return Battle.STRONG
	elseif Battle.Strong[defend] and Battle.Strong[defend][attack] then
		return Battle.WEAK
	end
	return 1
end

-- ===== Moves =====
export type Move = { Id: string, DisplayName: string, Element: string, Power: number, Accuracy: number, Signature: boolean? }
Battle.Moves = {} :: { [string]: Move }
local function move(id: string, name: string, element: string, power: number, accuracy: number)
	Battle.Moves[id] = { Id = id, DisplayName = name, Element = element, Power = power, Accuracy = accuracy }
end
move("Tackle", "Tackle", "Normal", 35, 100)
move("VineWhip", "Vine Whip", "Verdant", 45, 100)
move("LeafStorm", "Leaf Storm", "Verdant", 75, 85)
move("RockThrow", "Rock Throw", "Earthen", 45, 100)
move("Earthquake", "Earthquake", "Earthen", 75, 85)
move("Splash", "Water Splash", "Tide", 45, 100)
move("TidalWave", "Tidal Wave", "Tide", 75, 85)
move("IceShard", "Ice Shard", "Frost", 45, 100)
move("Blizzard", "Blizzard", "Frost", 75, 85)
move("Ember", "Ember", "Ember", 45, 100)
move("FireBlast", "Fire Blast", "Ember", 75, 85)
move("Spark", "Spark", "Storm", 45, 100)
move("Thunderbolt", "Thunderbolt", "Storm", 75, 85)
move("PoisonSting", "Poison Sting", "Toxic", 45, 100)
move("ToxicCloud", "Toxic Cloud", "Toxic", 75, 85)

-- Trainer signature attacks (Shared/Trainers): one per trainer, known only by
-- that trainer's monsters.
local Trainers = require(script.Parent.Trainers)
for _, tr in Trainers.List do
	local s = tr.Signature
	move(s.Id, s.DisplayName, s.Element, s.Power, s.Accuracy)
	Battle.Moves[s.Id].Signature = true
end

-- SUPER moves: one ultimate per element, unlocked when a monster's power meter
-- is full (Charge >= SUPER_CHARGE). Always hit and always apply the element's effect.
Battle.SuperMoves = {
	Verdant = { "JungleFury", "Jungle Fury" },
	Earthen = { "MeteorSmash", "Meteor Smash" },
	Tide = { "Tsunami", "Tsunami" },
	Frost = { "AbsoluteFreeze", "Absolute Freeze" },
	Ember = { "InfernoBlast", "Inferno Blast" },
	Storm = { "ThunderStorm", "Thunder Storm" },
	Toxic = { "PlagueCloud", "Plague Cloud" },
}
for element, s in Battle.SuperMoves do
	move(s[1], s[2], element, 115, 100)
	Battle.Moves[s[1]].Super = true
end
Battle.SUPER_CHARGE = 100
Battle.CHARGE_DEAL = 25 -- meter gained by landing a hit
Battle.CHARGE_TAKE = 12 -- meter gained by taking one

function Battle.SuperFor(record: any): string?
	local s = Battle.SuperMoves[record.PrimaryElement]
	return s and s[1]
end

-- ===== Status effects =====
-- An element's moves can leave its status on the target (chance by move kind).
-- Burn/Poison hurt every turn; Freeze/Shock may cost a turn; Soak weakens
-- attacks. Verdant moves heal the attacker instead; Earthen moves raise a Guard.
Battle.Statuses = {
	Burn = { Label = "BURNED", Color = Color3.fromRGB(255, 110, 40), Turns = 3, Tick = 0.07 },
	Poison = { Label = "POISONED", Color = Color3.fromRGB(170, 80, 230), Turns = 3, Tick = 0.09 },
	Freeze = { Label = "FROZEN", Color = Color3.fromRGB(130, 220, 255), Turns = 2, SkipChance = 0.5 },
	Shock = { Label = "SHOCKED", Color = Color3.fromRGB(255, 210, 40), Turns = 3, SkipChance = 0.3 },
	Soak = { Label = "SOAKED", Color = Color3.fromRGB(60, 150, 255), Turns = 3, AttackMult = 0.75 },
}
Battle.ElementStatus = { Ember = "Burn", Toxic = "Poison", Frost = "Freeze", Storm = "Shock", Tide = "Soak" }
Battle.HEAL_SHARE = 0.3 -- Verdant: heal this share of the damage dealt
Battle.GUARD_TURNS = 3 -- Earthen: defense x GUARD_MULT for this many turns
Battle.GUARD_MULT = 1.3

function Battle.EffectChance(moveId: string): number
	local m = Battle.Moves[moveId]
	if m.Element == "Normal" then
		return 0
	elseif m.Super then
		return 1
	elseif m.Signature then
		return 0.5
	elseif m.Power >= 70 then
		return 0.35
	end
	return 0.15
end

-- { basic, strong } per element.
Battle.ElementMoves = {
	Verdant = { "VineWhip", "LeafStorm" },
	Earthen = { "RockThrow", "Earthquake" },
	Tide = { "Splash", "TidalWave" },
	Frost = { "IceShard", "Blizzard" },
	Ember = { "Ember", "FireBlast" },
	Storm = { "Spark", "Thunderbolt" },
	Toxic = { "PoisonSting", "ToxicCloud" },
}

-- Element colours for move buttons.
Battle.ElementColors = {
	Normal = Color3.fromRGB(170, 170, 185),
	Verdant = Color3.fromRGB(90, 200, 70),
	Earthen = Color3.fromRGB(190, 140, 80),
	Tide = Color3.fromRGB(60, 150, 255),
	Frost = Color3.fromRGB(130, 220, 255),
	Ember = Color3.fromRGB(255, 110, 40),
	Storm = Color3.fromRGB(255, 210, 40),
	Toxic = Color3.fromRGB(170, 80, 230),
}

function Battle.MovesFor(record: any): { string }
	local moves = { "Tackle" }
	for _, id in Battle.ElementMoves[record.PrimaryElement] or {} do
		table.insert(moves, id)
	end
	local second = record.SecondaryElement
	if second and second ~= record.PrimaryElement and Battle.ElementMoves[second] then
		table.insert(moves, Battle.ElementMoves[second][1])
	end
	return moves
end

-- ===== Stats =====
export type Stats = { MaxHP: number, Attack: number, Defense: number, Speed: number }

function Battle.StatsFor(record: any): Stats
	local sp = Species.ById[record.SpeciesId]
	local unlock = (Config.Species[record.SpeciesId] and Config.Species[record.SpeciesId].UnlockLevel) or 1
	local world = 1 + unlock * 0.1 -- later species are stronger
	local tier = 1 + 0.15 * ((record.RarityTier or 1) - 1)
	local power = (record.Stats and record.Stats.Power) or sp.BaseStats.Power
	local f = world * tier
	local fast = if sp.BodyType == "Floating" or sp.BodyType == "Winged" then 4 else 0
	return {
		MaxHP = math.floor((30 + power * 2.5) * f + 0.5),
		Attack = math.floor((8 + power) * f + 0.5),
		Defense = math.floor((8 + power * 0.6 + sp.SpeciesRarity * 2) * f + 0.5),
		Speed = 10 + sp.SpeciesRarity * 3 + fast + (record.RarityTier or 1),
	}
end

-- Critical hits follow match-ups, like Pokemon: a monster attacking an element
-- it is strong against lands a critical hit far more often.
Battle.CRIT_CHANCE = 0.06 -- neutral
Battle.CRIT_CHANCE_STRONG = 0.25 -- super strong match-up
Battle.CRIT_CHANCE_WEAK = 0.02 -- weak match-up
Battle.CRIT_MULT = 1.5

function Battle.CritChance(mult: number): number
	return if mult > 1 then Battle.CRIT_CHANCE_STRONG elseif mult < 1 then Battle.CRIT_CHANCE_WEAK else Battle.CRIT_CHANCE
end

-- One attack. rng is a Random; returns { Damage, Mult, Crit, Miss }.
function Battle.Attack(attacker: any, defender: any, moveId: string, rng: Random)
	local m = Battle.Moves[moveId]
	if not m.Super and rng:NextInteger(1, 100) > m.Accuracy then
		return { Damage = 0, Mult = 1, Crit = false, Miss = true }
	end
	local mult = if m.Element == "Normal" then 1 else Battle.ElementMultiplier(m.Element, defender.Element)
	-- Same-element bonus, like STAB.
	local stab = if m.Element == attacker.Element then 1.15 else 1
	local crit = rng:NextNumber() < Battle.CritChance(mult)
	local raw = m.Power * attacker.Stats.Attack / math.max(defender.Stats.Defense, 1) * 0.45 * mult * stab
	raw *= rng:NextNumber(0.85, 1)
	-- Status effects on the fighters (absent on plain records).
	local soak = attacker.Status and Battle.Statuses[attacker.Status] and Battle.Statuses[attacker.Status].AttackMult
	if soak then
		raw *= soak
	end
	if (defender.Guard or 0) > 0 then
		raw /= Battle.GUARD_MULT
	end
	if crit then
		raw *= Battle.CRIT_MULT
	end
	return { Damage = math.max(1, math.floor(raw)), Mult = mult, Crit = crit, Miss = false }
end

-- Enemy choice: usually the move that hits hardest on paper, sometimes random.
function Battle.ChooseMove(attacker: any, defender: any, rng: Random): string
	if rng:NextNumber() < 0.25 then
		return attacker.Moves[rng:NextInteger(1, #attacker.Moves)]
	end
	local best, bestScore = attacker.Moves[1], -1
	for _, id in attacker.Moves do
		local m = Battle.Moves[id]
		local mult = if m.Element == "Normal" then 1 else Battle.ElementMultiplier(m.Element, defender.Element)
		local score = m.Power * m.Accuracy / 100 * mult
		if score > bestScore then
			best, bestScore = id, score
		end
	end
	return best
end

-- ===== Rewards =====
-- Coins for beating one wild monster: a share of its species' egg price,
-- more for rarer ones.
function Battle.WildReward(record: any): number
	local cost = (Config.Species[record.SpeciesId] and Config.Species[record.SpeciesId].Cost) or 25
	return math.ceil(cost * 0.5 * (1 + 0.5 * ((record.RarityTier or 1) - 1)))
end
Battle.WildXP = 8
Battle.TrainerXP = 25
Battle.WildRespawnSeconds = 45 -- a beaten wild spot comes back for you after this
Battle.TrainerCooldownSeconds = 300 -- a beaten trainer pays out again after this
Battle.MaxTurns = 60 -- a battle this long ends as a loss (stops stalling)
Battle.IdleSeconds = 300 -- abandoned battles are dropped

return Battle
