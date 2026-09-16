--[[
	Behavior Runner spec -- verifies deterministic lifecycle ordering and cleanup.
	VZN Framework | Copyright (c) 2026 Zachary Vanier.
]]

local Harness = require("../TestHarness")
local Runner = require("../../src/Behavior/Shared/Runner")

local Test, Finish = Harness.New("Behavior Runner")

Test("orders start, hold, release, and ended", function()
	local Now = 10
	local Calls = {}
	local BehaviorRunner = Runner.Create({
		Now = function()
			return Now
		end,
	}, {
		ReplicateToAll = function() end,
	})

	BehaviorRunner.Begin("actor", "Pulse", "use-1", {
		OnStart = function()
			table.insert(Calls, "start")
		end,
		OnHold = function(_, Elapsed)
			table.insert(Calls, `hold:{Elapsed}`)
		end,
		OnRelease = function(_, Elapsed)
			table.insert(Calls, `release:{Elapsed}`)
		end,
		OnEnded = function(_, Reason)
			table.insert(Calls, `ended:{Reason}`)
		end,
	})
	Now = 12
	BehaviorRunner.Hold("actor", "use-1")
	Now = 14
	local Released = BehaviorRunner.Release("actor", "use-1")

	assert(Released.Ok and Released.Changed, "test assertion failed")
	assert(table.concat(Calls, ",") == "start,hold:2,release:4,ended:Released", "test assertion failed")
	assert(BehaviorRunner.GetState("actor", "use-1") == nil, "test assertion failed")
end)

Test("makes duplicate transitions idempotent", function()
	local Starts = 0
	local BehaviorRunner = Runner.Create({
		Now = function()
			return 0
		end,
	}, { ReplicateToAll = function() end })
	local Behavior = {
		OnStart = function()
			Starts += 1
		end,
	}

	local First = BehaviorRunner.Begin("actor", "Pulse", "same", Behavior)
	local Duplicate = BehaviorRunner.Begin("actor", "Pulse", "same", Behavior)
	local FirstHold = BehaviorRunner.Hold("actor", "same")
	local DuplicateHold = BehaviorRunner.Hold("actor", "same")

	assert(First.Changed and not Duplicate.Changed, "test assertion failed")
	assert(FirstHold.Changed and not DuplicateHold.Changed, "test assertion failed")
	assert(Starts == 1, "test assertion failed")
end)

Test("owns replication and cancels active uses during cleanup", function()
	local Replicated = 0
	local Cancelled = 0
	local Ended = 0
	local BehaviorRunner = Runner.Create({
		Now = function()
			return 5
		end,
	}, {
		ReplicateToAll = function(ActorId, BehaviorId, UseId, EventName, Payload)
			assert(ActorId == "actor" and BehaviorId == "Pulse" and UseId == "cleanup", "test assertion failed")
			assert(EventName == "Pulse", "test assertion failed")
			assert(Payload.NumberValue == 3, "test assertion failed")
			Replicated += 1
		end,
	})

	BehaviorRunner.Begin("actor", "Pulse", "cleanup", {
		OnStart = function(Context)
			Context.ReplicateToAll("Pulse", { NumberValue = 3 })
		end,
		OnCancel = function()
			Cancelled += 1
		end,
		OnEnded = function(_, Reason)
			assert(Reason == "Destroyed", "test assertion failed")
			Ended += 1
		end,
	})
	BehaviorRunner.Destroy()
	BehaviorRunner.Destroy()

	assert(Replicated == 1, "test assertion failed")
	assert(Cancelled == 1, "test assertion failed")
	assert(Ended == 1, "test assertion failed")
end)

Test("terminal callbacks cannot recursively finish an execution", function()
	local BehaviorRunner
	local Cancelled = 0
	local Ended = 0
	BehaviorRunner = Runner.Create({
		Now = function()
			return 0
		end,
	}, {
		ReplicateToAll = function() end,
	})

	BehaviorRunner.Begin("actor", "Pulse", "reentrant", {
		OnCancel = function()
			Cancelled += 1
			BehaviorRunner.Cancel("actor", "reentrant")
			BehaviorRunner.Destroy()
		end,
		OnEnded = function()
			Ended += 1
			BehaviorRunner.Cancel("actor", "reentrant")
		end,
	})
	local Result = BehaviorRunner.Cancel("actor", "reentrant")

	assert(Result.Ok and Result.Changed, "the original cancellation should finish")
	assert(Cancelled == 1, "the cancellation callback should run exactly once")
	assert(Ended == 1, "the ended callback should run exactly once")
	assert(BehaviorRunner.GetState("actor", "reentrant") == nil, "finished executions should stay removed")
end)

Test("destroy skips executions cancelled by an earlier terminal callback", function()
	local BehaviorRunner
	local Cancelled = {
		A = 0,
		B = 0,
	}
	local Ended = {
		A = 0,
		B = 0,
	}
	BehaviorRunner = Runner.Create({
		Now = function()
			return 0
		end,
	}, {
		ReplicateToAll = function() end,
	})

	BehaviorRunner.Begin("actor", "Pulse", "a", {
		OnCancel = function()
			Cancelled.A += 1
			BehaviorRunner.Cancel("actor", "b", "Cancelled")
		end,
		OnEnded = function()
			Ended.A += 1
		end,
	})
	BehaviorRunner.Begin("actor", "Pulse", "b", {
		OnCancel = function()
			Cancelled.B += 1
			BehaviorRunner.Cancel("actor", "a", "Cancelled")
		end,
		OnEnded = function()
			Ended.B += 1
		end,
	})

	BehaviorRunner.Destroy()

	assert(Cancelled.A == 1 and Ended.A == 1, "the first execution should finish exactly once")
	assert(Cancelled.B == 1, "the nested cancellation callback should run exactly once")
	assert(Ended.B == 1, "the nested ended callback should run exactly once")
	assert(BehaviorRunner.GetState("actor", "a") == nil, "the first execution should stay removed")
	assert(BehaviorRunner.GetState("actor", "b") == nil, "the nested execution should stay removed")
end)

Finish()
