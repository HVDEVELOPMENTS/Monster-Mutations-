--!strict
-- Bundles all definition tables. Services take a registry so tests can inject
-- small hand-built ones.

local Registry = {
	Rarity = require(script.Parent.Rarity),
	Categories = require(script.Parent.Categories),
	Species = require(script.Parent.Species),
	Mutations = require(script.Parent.Mutations),
	Biomes = require(script.Parent.Biomes),
	Materials = require(script.Parent.Materials),
	Events = require(script.Parent.Events),
	HybridRecipes = require(script.Parent.HybridRecipes),
}

return Registry
