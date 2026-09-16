--[[
	Skill Validation spec -- verifies audience normalization and contained behavior calls.
	VZN Framework | Copyright (c) 2026 Zachary Vanier.
]]

local Harness = require("../TestHarness")
local Validation = require("../../src/Skills/Server/_Validation")

local Test, Finish = Harness.New("Skill Validation")

local Context = {
	ActorId = "actor",
	SkillId = "Pulse",
	UseId = "use-1",
	Generation = 1,
	Action = "Begin",
	Payload = {},
	Now = 0,
}

Test("builds a service result from its parts", function()
	local Accepted = Validation.Response(true, true, 4, nil)
	assert(Accepted.Ok and Accepted.Changed, "an accepted result must carry both flags")
	assert(Accepted.Generation == 4, "the generation must be preserved")
	assert(Accepted.Reason == nil, "an accepted result carries no reason")

	local Rejected = Validation.Response(false, false, nil, "Cooldown")
	assert(not Rejected.Ok and not Rejected.Changed, "a rejection must clear both flags")
	assert(Rejected.Reason == "Cooldown", "the rejection reason must be preserved")
end)

Test("normalizes an audience and drops duplicates", function()
	local Normalized = Validation.NormalizeAudience({ ActorIds = { "a", "b", "a" } })

	assert(Normalized ~= nil, "a well-formed audience must normalize")
	assert(#Normalized.ActorIds == 2, `duplicates must collapse, got {#Normalized.ActorIds}`)
	assert(Normalized.ActorIds[1] == "a" and Normalized.ActorIds[2] == "b", "first-seen order must be kept")
	assert(table.isfrozen(Normalized), "a normalized audience must be frozen")
end)

Test("rejects malformed and oversized audiences", function()
	assert(Validation.NormalizeAudience({ ActorIds = { "" } }) == nil, "an empty actor id must be rejected")
	assert(Validation.NormalizeAudience({ ActorIds = { 7 } }) == nil, "a non-string actor id must be rejected")
	assert(
		Validation.NormalizeAudience({ ActorIds = { string.rep("x", 65) } }) == nil,
		"an over-long actor id must be rejected"
	)

	local TooMany = {}
	for Index = 1, 65 do
		table.insert(TooMany, `actor-{Index}`)
	end
	assert(Validation.NormalizeAudience({ ActorIds = TooMany }) == nil, "an oversized audience must be rejected")
end)

Test("accepts a well-formed validation result", function()
	local Valid, Reason = Validation.Validate({
		Validate = function()
			return { Ok = true }
		end,
	}, Context)

	assert(Valid, "a passing behavior must validate")
	assert(Reason == nil, "a passing behavior carries no reason")
end)

Test("contains a throwing behavior and sanitizes its message", function()
	local Valid, Reason = Validation.Validate({
		Validate = function()
			error("internal backend hostname leaked here")
		end,
	}, Context)

	assert(not Valid, "a throwing behavior must fail validation")
	assert(Reason == "ValidationException", "the raw error must not reach the caller")
end)

Test("rejects malformed validation results", function()
	local Shapes = {
		function()
			return "not a table"
		end,
		function()
			return { Ok = "yes" }
		end,
		function()
			return { Ok = false, Reason = "" }
		end,
		function()
			return { Ok = false, Reason = string.rep("r", 97) }
		end,
	}

	for Index, Validate in Shapes do
		local Valid, Reason = Validation.Validate({ Validate = Validate }, Context)
		assert(not Valid, `shape {Index} must fail validation`)
		assert(Reason == "InvalidValidationResult", `shape {Index} must report a typed reason, got {tostring(Reason)}`)
	end
end)

Test("contains a throwing audience resolver", function()
	local Resolved = Validation.ResolveAudience({
		ResolveAudience = function()
			error("resolver exploded")
		end,
	}, Context)

	assert(Resolved == nil, "a throwing resolver must yield no audience rather than propagate")
end)

Finish()
