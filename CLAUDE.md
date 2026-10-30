# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Monster Factory: a Roblox game (Luau) about incubating monsters whose mutations come from a server-side probability engine, across biome zones laid out pet-simulator style. The published place is "MONSTER MUTATIONS [NEW!!!]" (placeId 88434145842016).

## Workflow: Rojo + Studio MCP

- Code lives in `src/` and is synced into Studio by Rojo (`default.project.json`). Sync is **one-way, files -> Studio**: edit files here, never scripts in Studio (Studio edits get overwritten).
- Rojo must be running and connected: `rojo serve` in this folder, then Studio Plugins -> Rojo -> Connect. The Rojo plugin needs Studio's "Script Injection" permission.
- Rojo only manages the four `MonsterFactory`/`StarterPlayerScripts` paths in the project file. The **world** (zones, chambers, gates, gather nodes) is not in `src/`; it is generated in Studio by `WorldBuilder` (see below) and saved in the place.
- To re-import scripts from a saved place: `rojo syncback --input MonsterFactory.rbxl --non-interactive`, then delete the generated `*.meta.json` files that only contain an empty `SerializedOverrides`, and restore the plain `default.project.json` (syncback injects `$properties`).
- `git` may not be on PATH in older shells; it is at `%LOCALAPPDATA%\Programs\Git\cmd\git.exe`. Line endings are pinned to LF (`.gitattributes`) so synced sources stay unchanged.
- Studio is driven through the Roblox Studio MCP tools. Get the `studio_id` from `list_roblox_studios` each session (it changes). Edit-only tools fail while Studio is in Play mode; the user sometimes presses Play, so check `get_studio_state` and stop play before editing.

## Project agents and commands

`.claude/agents/` has `planner`, `architect` and `code-reviewer`, tuned to this game's rules (server authority, exact odds, saved-data migration). `.claude/commands/` has `/plan-feature <request>` (plan, then wait for approval) and `/checkpoint create|verify|list <name>` (run the Studio tests, then tag `checkpoint/<name>` in git). They are adapted from the idea of WorldFlowAI/everything-claude-code, rewritten for Roblox; its hooks and web-specific rules were deliberately not installed.

## Running tests

There is no CLI test runner; tests run inside Studio via the MCP `execute_luau` tool in a **Play** session on the **Server** datamodel (a fresh VM, so module caches are clean). Start play with `start_stop_play`, then run:

```lua
local root = game.ServerScriptService.MonsterFactory:Clone() -- clone avoids stale require() caches
local runner = require(root.Tests.TestRunner)
local specs = {}
for _, m in ipairs(root.Tests:GetChildren()) do
	if m.Name:match("_spec$") then table.insert(specs, m) end
end
local report, passed, failed = runner.Run(specs)
return report
```

Run a single spec with `runner.Run({ root.Tests.Hybrid_spec })`. Specs are ModuleScripts returning `function(t)` and using `t.it`, `t.ok`, `t.eq`, `t.near`, `t.log`. Running in the Edit datamodel works only for code that hasn't changed since Studio last required it (Edit-mode `require` caches across calls).

`Biomes_spec` validates **all** content generically (references resolvable, per-species pools, odds summing to 1 for every species x biome x event, events non-overlapping, unlock order), so new biomes/mutations are checked just by adding definitions. A useful extra smoke check is building every species x mutation with `MonsterVisuals.Build` + `MonsterEffects.Apply` + `AnimatePose` and counting errors.

`PlayerData_spec` covers saving against a fake DataStore. Real DataStores need "Enable Studio Access to API Services"; without it `PlayerDataService` runs memory-only and the HUD shows "Not saved (test)".

## Rebuilding the world

In the Edit datamodel:

```lua
local shared = game.ReplicatedStorage.MonsterFactory.Shared:Clone()
require(game.ServerStorage.MonsterFactory.WorldBuilder:Clone()).Build(shared)
```

Pass the cloned `Shared` folder so stale cached definitions aren't used. The build is seeded and deterministic; it clears and regenerates every zone model, `GatherNodes`, `ZoneGates` and the per-zone chambers (the meadow keeps the original `workspace.MutationChamber`).

## Architecture

**Data-driven content** lives in `src/ReplicatedStorage/MonsterFactory/Shared/` and is bundled by `Registry` (Rarity, Categories, Species, Mutations, Biomes, Materials, Events, HybridRecipes). Other Shared modules: `Config` (economy, prices, milestones, remote rate limits), `Progression` (upgrades, research, gather nodes), `WorldLayout` (zone positions), `MonsterVisuals`/`MonsterEffects` (rendering). Engine services take a registry so tests can inject small ones.

**Server is authoritative.** `Main.server.luau` wires services to RemoteFunctions; every remote is rate-limited (`Config.RateLimits`) and validated in the service. Clients only send selections; outcomes are never trusted from the client.

**Roll model** (`MutationService`): for each rolled category in order, slot 1 fills with `FillChance` (extra slots with `ExtraSlotFillChance`), then a tier is rolled from `Rarity.Chance` x tier multipliers (catalyst `TierMultiplier` effects, upgrade `TierModifiers`), then a weighted pick among *eligible* mutations of that category+tier. If no mutation is eligible at the rolled tier the slot stays empty (no fallback), which keeps advertised tier odds exact. Eligibility checks species, attachment points, biome, element, catalysts, events, research, progression, environment ranges, duplicates, exclusive groups and incompatibilities. After the roll, `ResolveHybrid` tries recipes by priority (Chance 1 = guaranteed); at most one hybrid. `GetOddsReport` uses the same functions as `Roll`, which is what the UI shows. Pity (bad-luck protection) forces a Rare+ in the first category that can supply one, never the Hybrid category.

**Events** (`Events`) are a pure function of Unix time per biome, so server and clients agree without networking. Active events shift the biome `Environment` and multiply listed mutation weights; incubations capture event state at start.

**Incubation** (`IncubationService`): the result is rolled and saved at **Start** (hidden from the client), revealed on **Claim**. Start is idempotent per client `RequestId`, Claim per `OpId` (`LastClaim` stored). Claim registers discoveries, XP, Research Points and auto-equips the first monster.

**Persistence** (`PlayerDataService`): versioned schema with `Migrate` (fills defaults, repairs bad values, quarantines invalid monsters rather than deleting), session locking via `UpdateAsync`, bounded retries, memory-only fallback. Monster records store genes and mutation ids only; visuals are derived.

**Client** (`StarterPlayerScripts/MonsterFactoryClient`, with `UIKit` and `Reveal` child modules) builds the whole UI in code from server `StateChanged` pushes. `PetController` renders every player's equipped monster from the `EquippedPet` player attribute (client-side, no server cost); it stays hidden while the LocalPlayer attribute `RevealActive` is set.

**Visuals** (`MonsterVisuals`): per-species `Rigs[...]` build part models facing **-Z** and return anchors (`Head`, `Back`, `Tail`, `Eyes`, `Body={Center,Radius}`, face style). Mutation looks come from bespoke `Builders[id]`, or generically from `Visual.Kind` via `KindBuilders` (Plates, Horns, Crown, Spikes, Core, Orbit, Veins, TailTip, Fins, Wings, Antlers, Shell, Cap, Tint, None), so new mutations usually need no code. Final scale = size gene x `Rarity.Scale`; tiers 2+ add a viewport-visible rarity aura. Animation roles come from part **names** (`ROLE_BY_NAME`: Foot/Leg/Paw = gait, Tail*, Ear, Wing, Tentacle, Eye = blink, ...), so name new rig parts accordingly. World-only particles/lights/trails come from `MonsterEffects` by element and tier.

**World** (`ServerStorage/MonsterFactory/WorldBuilder`): one 180x180 zone per biome from `WorldLayout`, a theme table per biome (`Themes[biomeId]` with ground, walls, gather node type, `Decorate`), gates tagged `BiomeGate` and chambers tagged `MutationChamber` (CollectionService). Gate barriers open client-side per player; the server's trespass loop in `Main` sends players out of locked zones. Props with an `EventOnly` attribute are toggled by the client during that event.

## Adding a biome

Touch only definitions plus one world theme: `Biomes` (incl. `Unlock`, `Theme.Accent`, `ShortName`), `Events` (+ `CycleSeconds`), `Species` (+ `Config.Species` cost/level, palettes in `MonsterVisuals.Palettes`, a rig in `Rigs`), `Mutations` (with `AllowedBiomes`), `Materials` (+ `Config.CatalystPrices`), `Progression.GatherNodes`/`GatherOrder` (+ research node for its Mythic), `HybridRecipes`, a new `MonsterEffects.Elements` entry if a new element, `WorldLayout` order, and `WorldBuilder` `Themes`/`NodeMakers`. Then run the tests (Biomes_spec catches gaps) and rebuild the world.

## Roblox gotchas found in this project

- `Enum.PartType.Ball` parts are always perfect spheres; non-uniform "balls" must be a Block with a sphere `SpecialMesh` (the `part()` helpers do this).
- `GuiButton.Active = false` stops `Activated` from firing; use `UI.SetDisabled` (attribute-based) for greyed-out buttons.
- `ParticleEmitter.Squeeze` is not available in this Studio build.
- Built-in `rbxasset://sounds/swoosh.wav` and `snap.mp3` fail to load; `UIKit.Sounds` maps everything to sounds that work.
- The UI font (FredokaOne) doesn't render some glyphs; rarity glyphs are limited to shapes and stars.
