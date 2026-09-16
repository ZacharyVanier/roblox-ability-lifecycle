--[[
	Skill Lifecycle spec -- verifies mode-specific pure transition plans.
	VZN Framework | Copyright (c) 2026 Zachary Vanier.
]]

local Harness = require("../TestHarness")
local Lifecycle = require("../../src/Skills/Shared/Lifecycle")
local Registry = require("../../src/Skills/Shared/Registry")

local Test, Finish = Harness.New("Skill Lifecycle")

Test("completes instant skills in one request", function()
	local Plan = Lifecycle.Plan("Instant", "Begin", false)

	assert(Plan.Ok, "test assertion failed")
	assert(Plan.Steps[1] == "Begin", "test assertion failed")
	assert(Plan.Steps[2] == "Release", "test assertion failed")
end)

Test("toggles active uses off", function()
	local Start = Lifecycle.Plan("Toggle", "Begin", false)
	local Stop = Lifecycle.Plan("Toggle", "Begin", true)

	assert(Start.Steps[1] == "Begin", "test assertion failed")
	assert(Stop.Steps[1] == "CancelExisting", "test assertion failed")
	assert(not Lifecycle.Plan("Toggle", "Hold", true).Ok, "test assertion failed")
end)

Test("rejects invalid active-state transitions", function()
	assert(not Lifecycle.Plan("Hold", "Release", false).Ok, "test assertion failed")
	assert(not Lifecycle.Plan("Charged", "Begin", true).Ok, "test assertion failed")
	assert(Lifecycle.Plan("Counter", "Cancel", true).Ok, "test assertion failed")
end)

Test("indexes immutable registry entries", function()
	local Entry = {
		Definition = { Id = "Pulse", Mode = "Instant", Cooldown = 1 },
		Behavior = {
			ResolveAudience = function(Context)
				return { ActorIds = { Context.ActorId } }
			end,
			Validate = function()
				return { Ok = true }
			end,
		},
	}
	local Skills = Registry.Create({ Entry })

	assert(Skills.Resolve("Pulse") == Entry, "test assertion failed")
	assert(Skills.Resolve("Missing") == nil, "test assertion failed")
	assert(#Skills.List() == 1, "test assertion failed")
end)

Finish()
