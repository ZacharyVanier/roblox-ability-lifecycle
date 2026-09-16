--[[
	Skill Actor Queue -- serializes authoritative intent work per actor in FIFO order.
	VZN Framework | Copyright (c) 2026 Zachary Vanier.
]]

--» TYPE DEFINITIONS «--

type ActorLock = {
	Owner: thread,
	Waiters: { thread },
}

type ActorQueue = {
	Execute: <Result>(ActorId: string, Callback: () -> Result) -> (boolean, boolean, Result?),
	IsOwnedByCurrent: (ActorId: string) -> boolean,
}

type ActorQueueModule = {
	Create: () -> ActorQueue,
}

--» PUBLIC API «--

local ActorQueueModule = {} :: ActorQueueModule

ActorQueueModule.Create = function(): ActorQueue
	local Locks: { [string]: ActorLock } = {}

	local function acquire(ActorId: string): boolean
		local CurrentThread = coroutine.running()
		local Lock = Locks[ActorId]
		if Lock == nil then
			Locks[ActorId] = { Owner = CurrentThread, Waiters = {} }
			return true
		end
		if Lock.Owner == CurrentThread then
			return false
		end
		table.insert(Lock.Waiters, CurrentThread)
		coroutine.yield()
		return true
	end

	local function release(ActorId: string): ()
		local Lock = Locks[ActorId]
		assert(Lock ~= nil and Lock.Owner == coroutine.running(), "Skill actor queue ownership was violated")
		while #Lock.Waiters > 0 do
			local NextThread = table.remove(Lock.Waiters, 1)
			Lock.Owner = NextThread
			if coroutine.resume(NextThread) then
				return
			end
		end
		Locks[ActorId] = nil
	end

	return table.freeze({
		Execute = function<Result>(ActorId: string, Callback: () -> Result): (boolean, boolean, Result?)
			if not acquire(ActorId) then
				return false, false, nil
			end
			local Succeeded, ResultValue = pcall(Callback)
			release(ActorId)
			if not Succeeded then
				return true, false, nil
			end
			return true, true, ResultValue
		end,
		IsOwnedByCurrent = function(ActorId: string): boolean
			local Lock = Locks[ActorId]
			return Lock ~= nil and Lock.Owner == coroutine.running()
		end,
	})
end

return table.freeze(ActorQueueModule)
