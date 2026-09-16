--[[
	Behavior Runner -- advances injected use behaviors through ordered lifecycle transitions.
	VZN Framework | Copyright (c) 2026 Zachary Vanier | MIT License.
	GitHub-managed: do not modify in Roblox Studio.
]]

--» DEPENDENCIES «--

local Types = require(if script then script.Parent.Types else "./Types")

--» TYPE DEFINITIONS «--

type Clock = Types.Clock
type Context = Types.Context
type EndReason = Types.EndReason
type Runner = Types.Runner
type State = Types.State
type TransitionResult = Types.TransitionResult
type Transport = Types.Transport
type UseBehavior = Types.UseBehavior

type Execution = {
	Behavior: UseBehavior,
	Context: Context,
	State: State,
}

type RunnerModule = {
	Create: (Clock: Clock, Transport: Transport) -> Runner,
}

--» PRIVATE FUNCTIONS «--

local function result(Ok: boolean, Changed: boolean, StateValue: State?, ErrorValue: string?): TransitionResult
	return {
		Ok = Ok,
		Changed = Changed,
		State = StateValue,
		Error = ErrorValue,
	}
end

local function invoke(Callback: (() -> ())?): (boolean, string?)
	if Callback == nil then
		return true, nil
	end

	local Ok, ErrorValue = pcall(Callback)
	if Ok then
		return true, nil
	end

	return false, tostring(ErrorValue)
end

--» PUBLIC API «--

local RunnerModule = {} :: RunnerModule

RunnerModule.Create = function(ClockValue: Clock, TransportValue: Transport): Runner
	assert(type(ClockValue.Now) == "function", "Behavior Runner requires Clock.Now")
	assert(type(TransportValue.ReplicateToAll) == "function", "Behavior Runner requires Transport.ReplicateToAll")

	local Active: { [string]: { [string]: Execution } } = {}
	local Destroyed = false

	local function getExecution(ActorId: string, UseId: string): Execution?
		local ActorExecutions = Active[ActorId]
		return if ActorExecutions then ActorExecutions[UseId] else nil
	end

	local function removeExecution(ActorId: string, UseId: string): ()
		local ActorExecutions = Active[ActorId]
		if ActorExecutions == nil then
			return
		end

		ActorExecutions[UseId] = nil
		if next(ActorExecutions) == nil then
			Active[ActorId] = nil
		end
	end

	local function finish(
		ActorId: string,
		UseId: string,
		ExecutionValue: Execution,
		Reason: EndReason,
		Callback: (() -> ())?,
		PrimaryError: string?
	): TransitionResult
		ExecutionValue.State = if Reason == "Released" then "Released" else "Cancelled"
		removeExecution(ActorId, UseId)

		local CallbackOk, CallbackError = invoke(Callback)

		local EndedOk, EndedError = invoke(function()
			if ExecutionValue.Behavior.OnEnded then
				ExecutionValue.Behavior.OnEnded(ExecutionValue.Context, Reason)
			end
		end)

		ExecutionValue.State = "Ended"

		if PrimaryError then
			return result(false, true, "Ended", PrimaryError)
		end
		if not CallbackOk then
			return result(false, true, "Ended", CallbackError)
		end
		if not EndedOk then
			return result(false, true, "Ended", EndedError)
		end

		return result(true, true, "Ended", nil)
	end

	local RunnerValue: Runner
	RunnerValue = {
		Begin = function(ActorId: string, BehaviorId: string, UseId: string, Behavior: UseBehavior): TransitionResult
			if Destroyed then
				return result(false, false, nil, "Behavior Runner is destroyed")
			end

			local Existing = getExecution(ActorId, UseId)
			if Existing then
				return result(true, false, Existing.State, nil)
			end

			local ActorExecutions = Active[ActorId]
			if ActorExecutions == nil then
				ActorExecutions = {}
				Active[ActorId] = ActorExecutions
			end

			local StartedAt = ClockValue.Now()
			local ContextValue = table.freeze({
				ActorId = ActorId,
				BehaviorId = BehaviorId,
				UseId = UseId,
				StartedAt = StartedAt,
				ReplicateToAll = function(EventName: string, Payload: Types.Payload): ()
					TransportValue.ReplicateToAll(ActorId, BehaviorId, UseId, EventName, Payload)
				end,
			}) :: Context
			local ExecutionValue: Execution = {
				Behavior = Behavior,
				Context = ContextValue,
				State = "Started",
			}
			ActorExecutions[UseId] = ExecutionValue

			local Ok, ErrorValue = invoke(function()
				if Behavior.OnStart then
					Behavior.OnStart(ContextValue)
				end
			end)
			if not Ok then
				return finish(ActorId, UseId, ExecutionValue, "Failed", nil, ErrorValue)
			end

			return result(true, true, "Started", nil)
		end,

		Hold = function(ActorId: string, UseId: string): TransitionResult
			local ExecutionValue = getExecution(ActorId, UseId)
			if ExecutionValue == nil then
				return result(false, false, nil, "Unknown behavior execution")
			end
			if ExecutionValue.State == "Holding" then
				return result(true, false, "Holding", nil)
			end
			if ExecutionValue.State ~= "Started" then
				return result(false, false, ExecutionValue.State, "Behavior execution cannot enter Hold")
			end

			local Ok, ErrorValue = invoke(function()
				if ExecutionValue.Behavior.OnHold then
					ExecutionValue.Behavior.OnHold(
						ExecutionValue.Context,
						ClockValue.Now() - ExecutionValue.Context.StartedAt
					)
				end
			end)
			if not Ok then
				return finish(ActorId, UseId, ExecutionValue, "Failed", nil, ErrorValue)
			end

			ExecutionValue.State = "Holding"
			return result(true, true, "Holding", nil)
		end,

		Release = function(ActorId: string, UseId: string): TransitionResult
			local ExecutionValue = getExecution(ActorId, UseId)
			if ExecutionValue == nil then
				return result(false, false, nil, "Unknown behavior execution")
			end
			if ExecutionValue.State ~= "Started" and ExecutionValue.State ~= "Holding" then
				return result(false, false, ExecutionValue.State, "Behavior execution cannot be released")
			end

			return finish(ActorId, UseId, ExecutionValue, "Released", function()
				if ExecutionValue.Behavior.OnRelease then
					ExecutionValue.Behavior.OnRelease(
						ExecutionValue.Context,
						ClockValue.Now() - ExecutionValue.Context.StartedAt
					)
				end
			end, nil)
		end,

		Cancel = function(ActorId: string, UseId: string, Reason: EndReason?): TransitionResult
			local ExecutionValue = getExecution(ActorId, UseId)
			if ExecutionValue == nil then
				return result(true, false, nil, nil)
			end

			local FinalReason = Reason or "Cancelled"
			return finish(ActorId, UseId, ExecutionValue, FinalReason, function()
				if ExecutionValue.Behavior.OnCancel then
					ExecutionValue.Behavior.OnCancel(ExecutionValue.Context, FinalReason)
				end
			end, nil)
		end,

		GetState = function(ActorId: string, UseId: string): State?
			local ExecutionValue = getExecution(ActorId, UseId)
			return if ExecutionValue then ExecutionValue.State else nil
		end,

		Destroy = function(): ()
			if Destroyed then
				return
			end
			Destroyed = true

			local Pending = {}
			for ActorId, ActorExecutions in Active do
				for UseId, ExecutionValue in ActorExecutions do
					table.insert(Pending, {
						ActorId = ActorId,
						UseId = UseId,
						Execution = ExecutionValue,
					})
				end
			end
			for _, PendingValue in Pending do
				local ExecutionValue = PendingValue.Execution
				if getExecution(PendingValue.ActorId, PendingValue.UseId) ~= ExecutionValue then
					continue
				end

				finish(PendingValue.ActorId, PendingValue.UseId, ExecutionValue, "Destroyed", function()
					if ExecutionValue.Behavior.OnCancel then
						ExecutionValue.Behavior.OnCancel(ExecutionValue.Context, "Destroyed")
					end
				end, nil)
			end
			table.clear(Active)
		end,
	}

	return table.freeze(RunnerValue)
end

return table.freeze(RunnerModule)
