--[[
	Skill Admission spec -- verifies sequence, replay, rate, and cleanup gates.
	VZN Framework | Copyright (c) 2026 Zachary Vanier.
]]

local Harness = require("../TestHarness")
local Admission = require("../../src/Skills/Server/Admission")

local Test, Finish = Harness.New("Skill Admission")

local function request(Sequence, UseId)
	return {
		ActorId = "actor",
		SkillId = "Pulse",
		UseId = UseId,
		Sequence = Sequence,
		Action = "Begin",
	}
end

Test("rejects stale sequences and replayed use ids", function()
	local Gate = Admission.Create({
		Now = function()
			return 1
		end,
	}, 10, 1)

	assert(Gate.Admit(request(1, "a")).Ok, "test assertion failed")
	assert(Gate.Admit(request(1, "b")).Reason == "OutOfSequence", "test assertion failed")
	assert(Gate.Admit(request(2, "a")).Reason == "Replay", "test assertion failed")
end)

Test("rate limits within the configured window", function()
	local Now = 1
	local Gate = Admission.Create({
		Now = function()
			return Now
		end,
	}, 2, 1)

	assert(Gate.Admit(request(1, "a")).Ok, "test assertion failed")
	assert(Gate.Admit(request(2, "b")).Ok, "test assertion failed")
	assert(Gate.Admit(request(3, "c")).Reason == "RateLimited", "test assertion failed")
	Now = 3
	assert(Gate.Admit(request(4, "d")).Ok, "test assertion failed")
end)

Test("charges stale and replayed requests against the adversarial budget", function()
	local Gate = Admission.Create({
		Now = function()
			return 1
		end,
	}, 3, 1)

	assert(Gate.Admit(request(1, "accepted")).Ok, "the first request should be accepted")
	assert(Gate.Admit(request(1, "stale")).Reason == "OutOfSequence", "stale traffic should be classified")
	assert(Gate.Admit(request(2, "accepted")).Reason == "Replay", "replayed traffic should be classified")
	assert(Gate.Admit(request(3, "next")).Reason == "RateLimited", "rejected traffic should exhaust the budget")
end)

Test("clears all actor admission state", function()
	local Gate = Admission.Create({
		Now = function()
			return 1
		end,
	}, 1, 1)
	Gate.Admit(request(7, "old"))
	Gate.ClearActor("actor")

	assert(Gate.Admit(request(1, "old")).Ok, "test assertion failed")
	assert(Gate.Admit(request(1, "next")).Reason == "RateLimited", "test assertion failed")
	assert(type(Gate.ClearActor) == "function", "test assertion failed")
end)

Test("bounds and expires replay history deterministically", function()
	local Now = 1
	local Gate = Admission.Create({
		Now = function()
			return Now
		end,
	}, 20, 1, 3)

	assert(Gate.Admit(request(1, "a")).Ok, "test assertion failed")
	assert(Gate.Admit(request(2, "b")).Ok, "test assertion failed")
	assert(Gate.Admit(request(3, "c")).Ok, "test assertion failed")
	assert(Gate.Admit(request(4, "d")).Ok, "test assertion failed")
	assert(Gate.Admit(request(5, "a")).Ok, "oldest replay entry should be evicted")
	assert(Gate.Admit(request(6, "d")).Reason == "Replay", "new replay entry should remain protected")
	Now = 3
	assert(Gate.Admit(request(7, "d")).Ok, "replay entries should expire with the configured window")
end)

Finish()
