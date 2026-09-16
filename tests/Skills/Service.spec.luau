--[[
	Skill Service spec -- verifies atomic validation, targeted lifecycle, and authoritative routing.
	VZN Framework | Copyright (c) 2026 Zachary Vanier.
]]

local Harness = require("../TestHarness")
local roblox = require("@lune/roblox")
local BehaviorRunner = require("../../src/Behavior/Shared/Runner")
local Registry = require("../../src/Skills/Shared/Registry")
local Admission = require("../../src/Skills/Server/Admission")
local Service = require("../../src/Skills/Server/Service")

local Test, Finish = Harness.New("Skill Service")
local Vector3 = roblox.Vector3

local function nonePayload()
	return { Kind = "None" }
end

local function request(Sequence, UseId, Action, SkillId, Payload)
	return {
		ActorId = "actor",
		SkillId = SkillId or "Pulse",
		UseId = UseId,
		Sequence = Sequence,
		Action = Action,
		Payload = Payload or nonePayload(),
	}
end

local function actorAndObserver(Context)
	return { ActorIds = { Context.ActorId, "observer", Context.ActorId } }
end

local function dependencies(Entries)
	local Consumed = 0
	local Checked = 0
	local Messages = {}
	local Lifecycle = {}
	local Presented = {}
	local Runner = BehaviorRunner.Create({
		Now = function()
			return 10
		end,
	}, { ReplicateToAll = function() end })
	local Values = {
		Admission = {
			Admit = function()
				return { Ok = true }
			end,
			ClearActor = function() end,
		},
		BehaviorRunner = Runner,
		Clock = {
			Now = function()
				return 10
			end,
		},
		Cooldowns = {
			Check = function()
				Checked += 1
				return { Ready = true, Remaining = 0, Charges = 1 }
			end,
			Consume = function()
				Consumed += 1
				return true
			end,
			ClearActor = function() end,
		},
		Registry = Registry.Create(Entries),
		Transport = {
			Present = function(Audience, ActorId, SkillId, UseId, Generation, EventName, Payload)
				table.insert(Presented, {
					Audience = Audience,
					ActorId = ActorId,
					SkillId = SkillId,
					UseId = UseId,
					Generation = Generation,
					EventName = EventName,
					Payload = Payload,
				})
			end,
			SendLifecycle = function(Audience, ActorId, SkillId, UseId, Generation, Active, Reason)
				table.insert(Lifecycle, {
					Audience = Audience,
					ActorId = ActorId,
					SkillId = SkillId,
					UseId = UseId,
					Generation = Generation,
					Active = Active,
					Reason = Reason,
				})
			end,
			SendAccepted = function(_, _, _, Generation)
				table.insert(Messages, `SkillAccepted:{Generation}`)
			end,
			SendRejected = function(_, _, _, Reason)
				table.insert(Messages, `SkillRejected:{Reason}`)
			end,
		},
	}

	return Values,
		{
			GetConsumed = function()
				return Consumed
			end,
			GetChecked = function()
				return Checked
			end,
			Messages = Messages,
			Lifecycle = Lifecycle,
			Presented = Presented,
			Runner = Runner,
		}
end

Test("contains validation exceptions before authoritative mutation", function()
	local Starts = 0
	local Values, Evidence = dependencies({
		{
			Definition = { Id = "Pulse", Mode = "Instant", Cooldown = 1 },
			Behavior = {
				ResolveAudience = actorAndObserver,
				Validate = function()
					error("private validation detail")
				end,
				OnStart = function()
					Starts += 1
				end,
			},
		},
	})
	local Result = Service.Create(Values).Handle(request(1, "use-1", "Begin"))

	assert(not Result.Ok and Result.Reason == "ValidationException", "validation errors should be sanitized")
	assert(
		Evidence.GetChecked() == 1 and Evidence.GetConsumed() == 0,
		"validation must run after check but before consume"
	)
	assert(Starts == 0 and #Evidence.Lifecycle == 0, "validation failure must not transition or replicate lifecycle")
	assert(Evidence.Messages[1] == "SkillRejected:ValidationException", "the client should receive only a typed reason")
end)

Test("contains hostile validation result normalization", function()
	local Results = {
		setmetatable({}, {
			__index = function()
				error("hostile result access")
			end,
		}),
		{ Ok = false, Reason = 42 },
		{ Ok = false, Reason = string.rep("x", 97) },
	}
	local Expected = { "ValidationException", "InvalidValidationResult", "InvalidValidationResult" }
	for Index, ValidationResult in Results do
		local Starts = 0
		local Values, Evidence = dependencies({
			{
				Definition = { Id = "Pulse", Mode = "Instant", Cooldown = 1 },
				Behavior = {
					ResolveAudience = actorAndObserver,
					Validate = function()
						return ValidationResult
					end,
					OnStart = function()
						Starts += 1
					end,
				},
			},
		})
		local Result = Service.Create(Values).Handle(request(1, `hostile-{Index}`, "Begin"))

		assert(not Result.Ok and Result.Reason == Expected[Index], "hostile results should be sanitized")
		assert(Evidence.GetConsumed() == 0 and Starts == 0, "invalid result access must stay atomic")
		assert(#Evidence.Lifecycle == 0, "invalid result access must not create lifecycle state")
	end
end)

Test("targets an explicit audience and reliably brackets instant presentation", function()
	local Calls = {}
	local Values, Evidence = dependencies({
		{
			Definition = { Id = "Pulse", Mode = "Instant", Cooldown = 1 },
			Behavior = {
				ResolveAudience = actorAndObserver,
				Validate = function()
					return { Ok = true }
				end,
				OnStart = function(Context)
					table.insert(Calls, "start")
					Context.Present("Pulse", { Kind = "None" })
				end,
				OnRelease = function()
					table.insert(Calls, "release")
				end,
				OnEnded = function()
					table.insert(Calls, "ended")
				end,
			},
		},
	})
	local Result = Service.Create(Values).Handle(request(1, "use-1", "Begin"))

	assert(
		Result.Ok and Result.Changed and Result.Generation == 1,
		"the first accepted use should allocate generation one"
	)
	assert(table.concat(Calls, ",") == "start,release,ended", "instant lifecycle order should stay deterministic")
	assert(Evidence.GetConsumed() == 1 and Evidence.Messages[1] == "SkillAccepted:1", "acceptance should commit once")
	assert(
		#Evidence.Presented == 1 and Evidence.Presented[1].Generation == 1,
		"presentation should carry use generation"
	)
	assert(
		table.concat(Evidence.Presented[1].Audience.ActorIds, ",") == "actor,observer",
		"the project audience should be deduplicated without a global default"
	)
	assert(
		Evidence.Lifecycle[1].Active and not Evidence.Lifecycle[2].Active,
		"reliable start and terminal snapshots should bracket VFX"
	)
	assert(Evidence.Lifecycle[2].Reason == "Released", "terminal cleanup should include the authoritative reason")
end)

Test("passes typed aim and target payloads into per-skill validation", function()
	local Validated = false
	local AimPayload = {
		Kind = "Aim",
		Position = Vector3.new(10, 2, -4),
		Direction = Vector3.new(0, 0, -1),
		TargetId = "target-7",
		Values = {
			Numbers = { 0.75, 3 },
			Texts = { "primary" },
			Booleans = { true },
		},
	}
	local Values = dependencies({
		{
			Definition = { Id = "Pulse", Mode = "Instant", Cooldown = 0 },
			Behavior = {
				ResolveAudience = actorAndObserver,
				Validate = function(Context)
					Validated = Context.Payload.Kind == "Aim"
						and Context.Payload.TargetId == "target-7"
						and Context.Payload.Direction == Vector3.new(0, 0, -1)
						and Context.Payload.Values.Numbers[2] == 3
					return { Ok = Validated, Reason = if Validated then nil else "InvalidAim" }
				end,
			},
		},
	})
	local Result = Service.Create(Values).Handle(request(1, "aim-use", "Begin", nil, AimPayload))

	assert(Result.Ok, "a skill should accept its explicitly validated aim envelope")
	assert(Validated, "aim position, direction, target, and typed values should reach validation")
	assert(Result.Generation == 1, "accepted aim use should receive a server generation")
end)

Test("snapshots actor uses before cancellation callbacks mutate active state", function()
	local Runner
	local Cancelled = { First = 0, Second = 0 }
	local Values, Evidence = dependencies({
		{
			Definition = { Id = "First", Mode = "Hold", Cooldown = 0 },
			Behavior = {
				ResolveAudience = actorAndObserver,
				Validate = function()
					return { Ok = true }
				end,
				OnCancel = function()
					Cancelled.First += 1
					Runner.Cancel("actor", "second-use", "Cancelled")
				end,
			},
		},
		{
			Definition = { Id = "Second", Mode = "Hold", Cooldown = 0 },
			Behavior = {
				ResolveAudience = actorAndObserver,
				Validate = function()
					return { Ok = true }
				end,
				OnCancel = function()
					Cancelled.Second += 1
				end,
			},
		},
	})
	Runner = Evidence.Runner
	local Skills = Service.Create(Values)
	assert(Skills.Handle(request(1, "first-use", "Begin", "First")).Ok, "first use should start")
	assert(Skills.Handle(request(2, "second-use", "Begin", "Second")).Ok, "second use should start")

	Skills.RemoveActor("actor")

	assert(
		Cancelled.First == 1 and Cancelled.Second == 1,
		"nested cancellation should finish each snapshotted use once"
	)
	assert(Evidence.Runner.GetState("actor", "first-use") == nil, "first use should be removed")
	assert(Evidence.Runner.GetState("actor", "second-use") == nil, "nested use should stay removed")
	assert(#Evidence.Lifecycle == 4, "both starts and both reliable terminals should be emitted")
end)

Test("rejects cross-skill use aliases after admission replay eviction", function()
	local Now = 0
	local function validBehavior()
		return {
			ResolveAudience = actorAndObserver,
			Validate = function()
				return { Ok = true }
			end,
		}
	end
	local Values, Evidence = dependencies({
		{ Definition = { Id = "First", Mode = "Hold", Cooldown = 0 }, Behavior = validBehavior() },
		{ Definition = { Id = "Second", Mode = "Hold", Cooldown = 0 }, Behavior = validBehavior() },
	})
	Values.Admission = Admission.Create({
		Now = function()
			return Now
		end,
	}, 20, 1, 1)
	local Skills = Service.Create(Values)
	assert(Skills.Handle(request(1, "shared-use", "Begin", "First")).Ok, "the first skill should start")
	Now = 2
	local Reused = Skills.Handle(request(2, "shared-use", "Begin", "Second"))

	assert(not Reused.Ok and Reused.Reason == "UseIdActive", "runner ownership must outlive replay eviction")
	assert(Evidence.GetChecked() == 1 and Evidence.GetConsumed() == 1, "alias rejection must precede cooldown work")
	assert(Evidence.Runner.GetState("actor", "shared-use") == "Started", "the original execution must survive")

	local Second = Skills.Handle(request(3, "second-use", "Begin", "Second"))
	assert(Second.Ok and Second.Generation == 1, "alias rejection must not advance the second skill generation")
	assert(Skills.Handle(request(4, "shared-use", "Release", "First")).Ok, "the original use should still release")
	assert(Evidence.Runner.GetState("actor", "shared-use") == nil, "the original lifecycle should terminate normally")
	assert(
		Evidence.Lifecycle[3].UseId == "shared-use" and not Evidence.Lifecycle[3].Active,
		"terminal state should target the original use"
	)
end)

Test("rejects foreign toggle aliases before cancellation", function()
	local Now = 0
	local Validations = 0
	local function toggleBehavior()
		return {
			ResolveAudience = actorAndObserver,
			Validate = function()
				Validations += 1
				return { Ok = true }
			end,
		}
	end
	local Values, Evidence = dependencies({
		{ Definition = { Id = "First", Mode = "Toggle", Cooldown = 0 }, Behavior = toggleBehavior() },
		{ Definition = { Id = "Second", Mode = "Toggle", Cooldown = 0 }, Behavior = toggleBehavior() },
	})
	Values.Admission = Admission.Create({
		Now = function()
			return Now
		end,
	}, 20, 10, 1)
	local Skills = Service.Create(Values)
	assert(Skills.Handle(request(1, "first-use", "Begin", "First")).Ok, "first toggle should start")
	assert(Skills.Handle(request(2, "second-use", "Begin", "Second")).Ok, "second toggle should start")
	local Foreign = Skills.Handle(request(3, "first-use", "Begin", "Second"))

	assert(not Foreign.Ok and Foreign.Reason == "UseIdActive", "foreign toggle identity must reject")
	assert(Evidence.GetChecked() == 2 and Evidence.GetConsumed() == 2, "foreign identity must precede cooldown work")
	assert(Validations == 2 and #Evidence.Lifecycle == 2, "foreign identity must precede validation and lifecycle")
	assert(
		Evidence.Runner.GetState("actor", "first-use") == "Started"
			and Evidence.Runner.GetState("actor", "second-use") == "Started",
		"foreign identity must not cancel either toggle"
	)

	local OwnCancellation = Skills.Handle(request(4, "second-use", "Begin", "Second"))
	assert(OwnCancellation.Ok and OwnCancellation.Generation == 1, "a toggle may cancel its own active identity")
	assert(Evidence.Runner.GetState("actor", "first-use") == "Started", "the other toggle must remain active")
	assert(Evidence.Runner.GetState("actor", "second-use") == nil, "the intended toggle should cancel")
	assert(
		Evidence.Lifecycle[3].UseId == "second-use" and not Evidence.Lifecycle[3].Active,
		"own cancel should terminate reliably"
	)

	local Restart = Skills.Handle(request(5, "second-restart", "Begin", "Second"))
	assert(Restart.Ok and Restart.Generation == 2, "the rejected alias must not advance generation")
	assert(Evidence.GetConsumed() == 3, "only the valid restart should consume another cooldown")
end)

Test("serializes yielding begin validation per actor", function()
	local ValidationCalls = 0
	local ShouldYield = true
	local Values, Evidence = dependencies({
		{
			Definition = { Id = "Pulse", Mode = "Hold", Cooldown = 0 },
			Behavior = {
				ResolveAudience = actorAndObserver,
				Validate = function()
					ValidationCalls += 1
					if ShouldYield then
						ShouldYield = false
						coroutine.yield()
					end
					return { Ok = true }
				end,
			},
		},
	})
	local Skills = Service.Create(Values)
	local FirstResult
	local SecondResult
	local FirstThread = coroutine.create(function()
		FirstResult = Skills.Handle(request(1, "first-use", "Begin"))
	end)
	local SecondThread = coroutine.create(function()
		SecondResult = Skills.Handle(request(2, "second-use", "Begin"))
	end)

	assert(coroutine.resume(FirstThread), "the first intent should yield during validation")
	assert(coroutine.resume(SecondThread), "the second intent should wait behind actor ownership")
	assert(Evidence.GetConsumed() == 0 and SecondResult == nil, "queued work must not overtake validation")
	assert(coroutine.resume(FirstThread), "resuming the owner should drain the queued intent")

	assert(FirstResult.Ok and not SecondResult.Ok, "only the first concurrent begin should commit")
	assert(
		SecondResult.Reason == "Skill already has an active use",
		"the queued begin should observe authoritative active state"
	)
	assert(ValidationCalls == 1 and Evidence.GetConsumed() == 1, "concurrency must not double validate or consume")
	assert(Evidence.Runner.GetState("actor", "first-use") == "Started", "the committed use must remain live")
	assert(Evidence.Runner.GetState("actor", "second-use") == nil, "the rejected use must not become orphaned")
end)

Test("rejects same-actor re-entry without deadlock", function()
	local Skills
	local InnerResult
	local Values, Evidence = dependencies({
		{
			Definition = { Id = "Pulse", Mode = "Hold", Cooldown = 0 },
			Behavior = {
				ResolveAudience = actorAndObserver,
				Validate = function()
					if InnerResult == nil then
						InnerResult = Skills.Handle(request(2, "inner-use", "Begin"))
					end
					return { Ok = true }
				end,
			},
		},
	})
	Skills = Service.Create(Values)
	local OuterResult = Skills.Handle(request(1, "outer-use", "Begin"))

	assert(OuterResult.Ok, "the owning intent should still complete")
	assert(not InnerResult.Ok and InnerResult.Reason == "ReentrantRequest", "same-thread re-entry should reject")
	assert(
		Evidence.GetConsumed() == 1 and Evidence.Runner.GetState("actor", "inner-use") == nil,
		"re-entry must not mutate authority"
	)
end)

Test("preserves release before a queued begin", function()
	local YieldRelease = true
	local Values, Evidence = dependencies({
		{
			Definition = { Id = "Pulse", Mode = "Hold", Cooldown = 0 },
			Behavior = {
				ResolveAudience = actorAndObserver,
				Validate = function(Context)
					if Context.Action == "Release" and YieldRelease then
						YieldRelease = false
						coroutine.yield()
					end
					return { Ok = true }
				end,
			},
		},
	})
	local Skills = Service.Create(Values)
	assert(Skills.Handle(request(1, "old-use", "Begin")).Ok, "the original use should start")
	local ReleaseResult
	local BeginResult
	local ReleaseThread = coroutine.create(function()
		ReleaseResult = Skills.Handle(request(2, "old-use", "Release"))
	end)
	local BeginThread = coroutine.create(function()
		BeginResult = Skills.Handle(request(3, "new-use", "Begin"))
	end)

	assert(coroutine.resume(ReleaseThread), "release should yield during project validation")
	assert(coroutine.resume(BeginThread), "the later begin should queue")
	assert(coroutine.resume(ReleaseThread), "release completion should drain the later begin")

	assert(ReleaseResult.Ok and BeginResult.Ok, "both ordered intents should complete")
	assert(BeginResult.Generation == 2 and Evidence.GetConsumed() == 2, "the replacement should commit exactly once")
	assert(Evidence.Runner.GetState("actor", "old-use") == nil, "the released use must not remain orphaned")
	assert(Evidence.Runner.GetState("actor", "new-use") == "Started", "the later begin should own active state")
	assert(
		Evidence.Lifecycle[2].UseId == "old-use" and Evidence.Lifecycle[3].UseId == "new-use",
		"wire lifecycle order should match intent order"
	)
end)

Test("drains actor removal behind yielding validation", function()
	local Values, Evidence = dependencies({
		{
			Definition = { Id = "Pulse", Mode = "Hold", Cooldown = 0 },
			Behavior = {
				ResolveAudience = actorAndObserver,
				Validate = function()
					coroutine.yield()
					return { Ok = true }
				end,
			},
		},
	})
	local Skills = Service.Create(Values)
	local BeginResult
	local BeginThread = coroutine.create(function()
		BeginResult = Skills.Handle(request(1, "removed-use", "Begin"))
	end)
	local RemoveThread = coroutine.create(function()
		Skills.RemoveActor("actor")
	end)

	assert(coroutine.resume(BeginThread), "begin should yield inside validation")
	assert(coroutine.resume(RemoveThread), "removal should queue behind the actor intent")
	assert(coroutine.resume(BeginThread), "the yielding intent should unwind into queued removal")
	assert(not BeginResult.Ok and BeginResult.Reason == "ActorRemoving", "teardown should invalidate in-flight work")
	assert(
		Evidence.GetConsumed() == 0 and Evidence.Runner.GetState("actor", "removed-use") == nil,
		"removal must leave no authority residue"
	)
	assert(coroutine.status(RemoveThread) == "dead", "queued removal should drain without deadlock")
end)

Test("drains destruction behind yielding validation", function()
	local Values, Evidence = dependencies({
		{
			Definition = { Id = "Pulse", Mode = "Hold", Cooldown = 0 },
			Behavior = {
				ResolveAudience = actorAndObserver,
				Validate = function()
					coroutine.yield()
					return { Ok = true }
				end,
			},
		},
	})
	local Skills = Service.Create(Values)
	local BeginResult
	local BeginThread = coroutine.create(function()
		BeginResult = Skills.Handle(request(1, "destroyed-use", "Begin"))
	end)
	local DestroyThread = coroutine.create(function()
		Skills.Destroy()
	end)

	assert(coroutine.resume(BeginThread), "begin should yield inside validation")
	assert(coroutine.resume(DestroyThread), "destruction should queue behind the actor intent")
	assert(coroutine.resume(BeginThread), "the yielding intent should unwind into queued destruction")
	assert(not BeginResult.Ok and BeginResult.Reason == "ServiceDestroyed", "destroy should invalidate in-flight work")
	assert(
		Evidence.GetConsumed() == 0 and Evidence.Runner.GetState("actor", "destroyed-use") == nil,
		"destroy must leave no authority residue"
	)
	assert(coroutine.status(DestroyThread) == "dead", "queued destruction should drain without deadlock")
end)

Finish()
