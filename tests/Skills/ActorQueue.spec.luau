--[[
	Skill Actor Queue spec -- verifies per-actor serialization, reentrancy, and handoff.
	VZN Framework | Copyright (c) 2026 Zachary Vanier.
]]

local Harness = require("../TestHarness")
local ActorQueue = require("../../src/Skills/Server/_ActorQueue")

local Test, Finish = Harness.New("Skill Actor Queue")

Test("runs work and returns its result", function()
	local Queue = ActorQueue.Create()

	local Acquired, Succeeded, Result = Queue.Execute("actor", function()
		return "value"
	end)

	assert(Acquired, "an uncontended actor must acquire")
	assert(Succeeded, "the callback should have succeeded")
	assert(Result == "value", `the callback result must be returned, got {tostring(Result)}`)
end)

Test("refuses reentrant work on the same actor", function()
	local Queue = ActorQueue.Create()
	local InnerAcquired = nil

	Queue.Execute("actor", function()
		InnerAcquired = Queue.Execute("actor", function()
			return "inner"
		end)
		return "outer"
	end)

	assert(InnerAcquired == false, "a reentrant call on the same actor must be refused, not deadlock")
end)

Test("reports ownership only inside the actor's own work", function()
	local Queue = ActorQueue.Create()

	assert(not Queue.IsOwnedByCurrent("actor"), "no lock is held before any work runs")

	local Inside = nil
	local Other = nil
	Queue.Execute("actor", function()
		Inside = Queue.IsOwnedByCurrent("actor")
		Other = Queue.IsOwnedByCurrent("different-actor")
		return nil
	end)

	assert(Inside, "the running thread must own the actor it is working on")
	assert(not Other, "owning one actor must not imply owning another")
	assert(not Queue.IsOwnedByCurrent("actor"), "the lock must be released when work finishes")
end)

Test("keeps separate actors independent", function()
	local Queue = ActorQueue.Create()
	local NestedAcquired = nil

	Queue.Execute("actor-a", function()
		NestedAcquired = Queue.Execute("actor-b", function()
			return "b"
		end)
		return "a"
	end)

	assert(NestedAcquired == true, "a different actor must not be blocked by an unrelated lock")
end)

Test("releases the lock when the callback throws", function()
	local Queue = ActorQueue.Create()

	local Acquired, Succeeded, Result = Queue.Execute("actor", function()
		error("work exploded")
	end)

	assert(Acquired, "the actor was uncontended, so it must acquire")
	assert(not Succeeded, "a throwing callback must report failure")
	assert(Result == nil, "a failed callback returns no result")

	-- The lock must not be stranded by the failure.
	local NextAcquired, NextSucceeded = Queue.Execute("actor", function()
		return true
	end)
	assert(NextAcquired and NextSucceeded, "a failed callback must still release the lock")
	assert(not Queue.IsOwnedByCurrent("actor"), "no ownership may survive the failure")
end)

Test("hands the lock to a waiting thread in FIFO order", function()
	local Queue = ActorQueue.Create()
	local Order = {}

	local Holder
	Holder = coroutine.create(function()
		Queue.Execute("actor", function()
			table.insert(Order, "holder-start")
			coroutine.yield()
			table.insert(Order, "holder-end")
			return nil
		end)
	end)

	local Waiter = coroutine.create(function()
		Queue.Execute("actor", function()
			table.insert(Order, "waiter")
			return nil
		end)
	end)

	coroutine.resume(Holder)
	assert(Order[1] == "holder-start", "the holder must start first")

	coroutine.resume(Waiter)
	assert(#Order == 1, "the waiter must not run while the holder owns the lock")

	coroutine.resume(Holder)

	assert(Order[2] == "holder-end", "the holder must finish its own work first")
	assert(Order[3] == "waiter", "the waiter must run only after the holder released")
	assert(not Queue.IsOwnedByCurrent("actor"), "the lock must be free once every waiter drained")
end)

Finish()
