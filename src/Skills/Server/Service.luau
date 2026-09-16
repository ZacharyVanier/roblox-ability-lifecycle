--[[
	Skill Service -- validates and commits server-authoritative skill intents.
	VZN Framework | Copyright (c) 2026 Zachary Vanier.
]]

--» DEPENDENCIES «--

local ReplicatedStorage = if script then game:GetService("ReplicatedStorage") else nil
local SharedRoot = if ReplicatedStorage then ReplicatedStorage.VZNCore.Features.Skills.Shared else nil
local Lifecycle = require(if SharedRoot then SharedRoot.Lifecycle else "../Shared/Lifecycle")
local ActorQueue = require("./_ActorQueue")
local Validation = require("./_Validation")
local Types = require("./Types")

--» TYPE DEFINITIONS «--

type Action = Types.Action
type Admission = Types.Admission
type Audience = Types.Audience
type Behavior = Types.Behavior
type Context = Types.Context
type CooldownStore = Types.CooldownStore
type EndReason = Types.EndReason
type Entry = Types.Entry
type Payload = Types.Payload
type Registry = Types.Registry
type Request = Types.Request
type ServerTransport = Types.ServerTransport
type Service = Types.Service
type ServiceResult = Types.ServiceResult
type ValidationContext = Types.ValidationContext

type BehaviorContext = Types.BehaviorContext
type BehaviorRunner = Types.BehaviorRunner
type UseBehavior = Types.UseBehavior

type Clock = {
	Now: () -> number,
}

type Dependencies = {
	Admission: Admission,
	BehaviorRunner: BehaviorRunner,
	Clock: Clock,
	Cooldowns: CooldownStore,
	Registry: Registry,
	Transport: ServerTransport,
}

type ActiveUse = {
	UseId: string,
	Generation: number,
	Audience: Audience,
	Action: Action,
	Payload: Payload,
}

type ServiceModule = {
	Create: (Dependencies: Dependencies) -> Service,
}

--» CONSTANTS «--

local MAX_GENERATION = 4294967295

--» PUBLIC API «--

local ServiceModule = {} :: ServiceModule

ServiceModule.Create = function(DependenciesValue: Dependencies): Service
	local ActiveUses: { [string]: { [string]: ActiveUse } } = {}
	local Queue = ActorQueue.Create()
	local Runner = DependenciesValue.BehaviorRunner
	local Transport = DependenciesValue.Transport
	local Generations: { [string]: { [string]: number } } = {}
	local KnownActors: { [string]: boolean } = {}
	local RemovingActors: { [string]: boolean } = {}
	local Destroyed = false

	local function activeUse(ActorId: string, SkillId: string): ActiveUse?
		local ActorUses = ActiveUses[ActorId]
		return if ActorUses then ActorUses[SkillId] else nil
	end

	local function setActiveUse(ActorId: string, SkillId: string, UseValue: ActiveUse?): ()
		local ActorUses = ActiveUses[ActorId]
		if ActorUses == nil and UseValue ~= nil then
			ActorUses = {}
			ActiveUses[ActorId] = ActorUses
		end
		if ActorUses == nil then
			return
		end

		ActorUses[SkillId] = UseValue
		if next(ActorUses) == nil then
			ActiveUses[ActorId] = nil
		end
	end

	local function nextGeneration(ActorId: string, SkillId: string): number?
		local ActorGenerations = Generations[ActorId]
		local Current = if ActorGenerations then ActorGenerations[SkillId] or 0 else 0
		if Current >= MAX_GENERATION then
			return nil
		end
		return Current + 1
	end

	local function commitGeneration(ActorId: string, SkillId: string, Generation: number): ()
		local ActorGenerations = Generations[ActorId]
		if ActorGenerations == nil then
			ActorGenerations = {}
			Generations[ActorId] = ActorGenerations
		end
		ActorGenerations[SkillId] = Generation
	end

	local function validationContext(RequestValue: Request, Generation: number): ValidationContext
		return table.freeze({
			ActorId = RequestValue.ActorId,
			SkillId = RequestValue.SkillId,
			UseId = RequestValue.UseId,
			Generation = Generation,
			Action = RequestValue.Action,
			Payload = RequestValue.Payload,
			Now = DependenciesValue.Clock.Now(),
		})
	end

	local function skillContext(BehaviorContextValue: BehaviorContext, UseValue: ActiveUse): Context
		return table.freeze({
			ActorId = BehaviorContextValue.ActorId,
			SkillId = BehaviorContextValue.BehaviorId,
			UseId = BehaviorContextValue.UseId,
			Generation = UseValue.Generation,
			StartedAt = BehaviorContextValue.StartedAt,
			Action = UseValue.Action,
			Payload = UseValue.Payload,
			Present = function(EventName: string, PresentationPayload: Payload): ()
				Transport.Present(
					UseValue.Audience,
					BehaviorContextValue.ActorId,
					BehaviorContextValue.BehaviorId,
					BehaviorContextValue.UseId,
					UseValue.Generation,
					EventName,
					PresentationPayload
				)
			end,
		})
	end

	local function wrappedBehavior(EntryValue: Entry, UseValue: ActiveUse): UseBehavior
		local Original = EntryValue.Behavior
		return {
			OnStart = if Original.OnStart
				then function(ContextValue: BehaviorContext): ()
					Original.OnStart(skillContext(ContextValue, UseValue))
				end
				else nil,
			OnHold = if Original.OnHold
				then function(ContextValue: BehaviorContext, Elapsed: number): ()
					Original.OnHold(skillContext(ContextValue, UseValue), Elapsed)
				end
				else nil,
			OnRelease = if Original.OnRelease
				then function(ContextValue: BehaviorContext, Elapsed: number): ()
					Original.OnRelease(skillContext(ContextValue, UseValue), Elapsed)
				end
				else nil,
			OnCancel = if Original.OnCancel
				then function(ContextValue: BehaviorContext, Reason: EndReason): ()
					Original.OnCancel(skillContext(ContextValue, UseValue), Reason)
				end
				else nil,
			OnEnded = function(ContextValue: BehaviorContext, Reason: EndReason): ()
				local SkillContext = skillContext(ContextValue, UseValue)
				if activeUse(ContextValue.ActorId, ContextValue.BehaviorId) == UseValue then
					setActiveUse(ContextValue.ActorId, ContextValue.BehaviorId, nil)
				end
				Transport.SendLifecycle(
					UseValue.Audience,
					ContextValue.ActorId,
					ContextValue.BehaviorId,
					ContextValue.UseId,
					UseValue.Generation,
					false,
					Reason
				)
				if Original.OnEnded then
					Original.OnEnded(SkillContext, Reason)
				end
			end,
		}
	end

	local function reject(RequestValue: Request, Reason: string): ServiceResult
		Transport.SendRejected(RequestValue.ActorId, RequestValue.SkillId, RequestValue.UseId, Reason)
		return Validation.Response(false, false, nil, Reason)
	end

	local function accept(RequestValue: Request, Generation: number, Changed: boolean): ServiceResult
		Transport.SendAccepted(RequestValue.ActorId, RequestValue.SkillId, RequestValue.UseId, Generation)
		return Validation.Response(true, Changed, Generation, nil)
	end

	local function unavailableReason(ActorId: string): string?
		if Destroyed then
			return "ServiceDestroyed"
		end
		return if RemovingActors[ActorId] then "ActorRemoving" else nil
	end

	local function validationFailure(BehaviorValue: Behavior, ContextValue: ValidationContext, ActorId: string): string?
		local Valid, Reason = Validation.Validate(BehaviorValue, ContextValue)
		return if Valid then unavailableReason(ActorId) else Reason or "ValidationFailed"
	end

	local function handleUnlocked(RequestValue: Request): ServiceResult
		local UnavailableReason = unavailableReason(RequestValue.ActorId)
		if UnavailableReason then
			return reject(RequestValue, UnavailableReason)
		end
		KnownActors[RequestValue.ActorId] = true

		local Admitted = DependenciesValue.Admission.Admit(RequestValue)
		if not Admitted.Ok then
			return reject(RequestValue, Admitted.Reason or "AdmissionRejected")
		end

		local EntryValue = DependenciesValue.Registry.Resolve(RequestValue.SkillId)
		if EntryValue == nil then
			return reject(RequestValue, "UnknownSkill")
		end

		local ExistingUse = activeUse(RequestValue.ActorId, RequestValue.SkillId)
		local Plan = Lifecycle.Plan(EntryValue.Definition.Mode, RequestValue.Action, ExistingUse ~= nil)
		if not Plan.Ok then
			return reject(RequestValue, Plan.Reason or "InvalidTransition")
		end
		local OwnActiveUse = ExistingUse ~= nil and ExistingUse.UseId == RequestValue.UseId
		local LiveUse = RequestValue.Action == "Begin" and Runner.GetState(RequestValue.ActorId, RequestValue.UseId)
		if LiveUse and not OwnActiveUse then
			return reject(RequestValue, "UseIdActive")
		end

		if Plan.Steps[1] == "CancelExisting" then
			assert(ExistingUse ~= nil, "CancelExisting requires an active skill use")
			local ContextValue = validationContext(RequestValue, ExistingUse.Generation)
			local ValidationFailure = validationFailure(EntryValue.Behavior, ContextValue, RequestValue.ActorId)
			if ValidationFailure then
				return reject(RequestValue, ValidationFailure)
			end

			ExistingUse.Action = RequestValue.Action
			ExistingUse.Payload = RequestValue.Payload
			local Cancelled = Runner.Cancel(RequestValue.ActorId, ExistingUse.UseId, "Cancelled")
			if not Cancelled.Ok then
				return reject(RequestValue, Cancelled.Error or "CancelFailed")
			end
			return accept(RequestValue, ExistingUse.Generation, Cancelled.Changed)
		end

		local UseValue: ActiveUse
		if RequestValue.Action == "Begin" then
			local Generation = nextGeneration(RequestValue.ActorId, RequestValue.SkillId)
			if Generation == nil then
				return reject(RequestValue, "GenerationExhausted")
			end

			local Available = DependenciesValue.Cooldowns.Check(RequestValue.ActorId, EntryValue.Definition)
			if not Available.Ready then
				return reject(RequestValue, Available.Reason or "Cooldown")
			end

			local ContextValue = validationContext(RequestValue, Generation)
			local ValidationFailure = validationFailure(EntryValue.Behavior, ContextValue, RequestValue.ActorId)
			if ValidationFailure then
				return reject(RequestValue, ValidationFailure)
			end

			local AudienceValue = Validation.ResolveAudience(EntryValue.Behavior, ContextValue)
			if AudienceValue == nil then
				return reject(RequestValue, "InvalidAudience")
			end
			local UnavailableAfterAudience = unavailableReason(RequestValue.ActorId)
			if UnavailableAfterAudience then
				return reject(RequestValue, UnavailableAfterAudience)
			end
			if not DependenciesValue.Cooldowns.Consume(RequestValue.ActorId, EntryValue.Definition) then
				return reject(RequestValue, "CooldownChanged")
			end

			commitGeneration(RequestValue.ActorId, RequestValue.SkillId, Generation)
			UseValue = {
				UseId = RequestValue.UseId,
				Generation = Generation,
				Audience = AudienceValue,
				Action = RequestValue.Action,
				Payload = RequestValue.Payload,
			}
			setActiveUse(RequestValue.ActorId, RequestValue.SkillId, UseValue)
		else
			if ExistingUse == nil or ExistingUse.UseId ~= RequestValue.UseId then
				return reject(RequestValue, "UseMismatch")
			end

			local ContextValue = validationContext(RequestValue, ExistingUse.Generation)
			local ValidationFailure = validationFailure(EntryValue.Behavior, ContextValue, RequestValue.ActorId)
			if ValidationFailure then
				return reject(RequestValue, ValidationFailure)
			end
			ExistingUse.Action = RequestValue.Action
			ExistingUse.Payload = RequestValue.Payload
			UseValue = ExistingUse
		end

		local Changed = false
		for _, Step in Plan.Steps do
			local Transition
			if Step == "Begin" then
				Transition = Runner.Begin(
					RequestValue.ActorId,
					RequestValue.SkillId,
					RequestValue.UseId,
					wrappedBehavior(EntryValue, UseValue)
				)
				if Transition.Ok then
					Transport.SendLifecycle(
						UseValue.Audience,
						RequestValue.ActorId,
						RequestValue.SkillId,
						RequestValue.UseId,
						UseValue.Generation,
						true,
						nil
					)
				end
			elseif Step == "Hold" then
				Transition = Runner.Hold(RequestValue.ActorId, RequestValue.UseId)
			elseif Step == "Release" then
				Transition = Runner.Release(RequestValue.ActorId, RequestValue.UseId)
			else
				Transition = Runner.Cancel(RequestValue.ActorId, RequestValue.UseId, "Cancelled")
			end

			if not Transition.Ok then
				if Step == "Begin" and activeUse(RequestValue.ActorId, RequestValue.SkillId) == UseValue then
					setActiveUse(RequestValue.ActorId, RequestValue.SkillId, nil)
				end
				return reject(RequestValue, Transition.Error or "BehaviorFailed")
			end
			Changed = Changed or Transition.Changed
		end

		return accept(RequestValue, UseValue.Generation, Changed)
	end

	local function executeRequest(RequestValue: Request): ServiceResult
		local Acquired, Succeeded, Result = Queue.Execute(RequestValue.ActorId, function(): ServiceResult
			return handleUnlocked(RequestValue)
		end)
		if not Acquired then
			return reject(RequestValue, "ReentrantRequest")
		end
		if not Succeeded then
			return reject(RequestValue, "ServiceException")
		end
		return Result :: ServiceResult
	end

	local function clearActorState(ActorId: string): ()
		local UseIds: { string } = {}
		local ActorUses = ActiveUses[ActorId]
		if ActorUses then
			for _, UseValue in ActorUses do
				table.insert(UseIds, UseValue.UseId)
			end
		end
		for _, UseId in UseIds do
			pcall(Runner.Cancel, ActorId, UseId, "Cancelled")
		end
		ActiveUses[ActorId] = nil
		KnownActors[ActorId] = nil
		pcall(DependenciesValue.Admission.ClearActor, ActorId)
		pcall(DependenciesValue.Cooldowns.ClearActor, ActorId)
	end

	local ServiceValue: Service
	ServiceValue = {
		Handle = executeRequest,

		RemoveActor = function(ActorId: string): ()
			assert(not Queue.IsOwnedByCurrent(ActorId), "Skill RemoveActor cannot run inside an actor intent")
			RemovingActors[ActorId] = true
			local Acquired, Succeeded = Queue.Execute(ActorId, function(): ()
				clearActorState(ActorId)
			end)
			assert(Acquired and Succeeded, "Skill RemoveActor cleanup failed")
			RemovingActors[ActorId] = nil
		end,

		Destroy = function(): ()
			if Destroyed then
				return
			end
			local ActorIds = {}
			for ActorId in KnownActors do
				assert(not Queue.IsOwnedByCurrent(ActorId), "Skill Destroy cannot run inside an actor intent")
				table.insert(ActorIds, ActorId)
			end
			table.sort(ActorIds)
			Destroyed = true
			for _, ActorId in ActorIds do
				local Acquired, Succeeded = Queue.Execute(ActorId, function(): ()
					clearActorState(ActorId)
				end)
				assert(Acquired and Succeeded, "Skill Destroy cleanup failed")
			end
			Runner.Destroy()
			table.clear(KnownActors)
			table.clear(RemovingActors)
			table.clear(ActiveUses)
			table.clear(Generations)
		end,
	}

	return table.freeze(ServiceValue)
end

return table.freeze(ServiceModule)
