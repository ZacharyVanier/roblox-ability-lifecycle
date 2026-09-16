--[[
	Charge Ability -- deterministic walkthrough of release, interruption, and failure.
	Copyright (c) 2026 Zachary Vanier | MIT License.
	Run with Lune from the repository root.
]]

local Runner = require("../src/VZNCore/Features/Behavior/Shared/Runner")
local Types = require("../src/VZNCore/Features/Behavior/Shared/Types")

local Now = 0
local Events: { string } = {}
local ActiveEffects = 0

local AbilityRunner = Runner.Create({
	Now = function(): number
		return Now
	end,
}, {
	ReplicateToAll = function(
		ActorId: string,
		BehaviorId: string,
		UseId: string,
		EventName: string,
		Payload: Types.Payload
	): ()
		table.insert(Events, `{ActorId}/{BehaviorId}/{UseId}: {EventName} ({Payload.NumberValue or 0})`)
	end,
})

local ChargeAbility: Types.UseBehavior = {
	OnStart = function(Context: Types.Context): ()
		ActiveEffects += 1
		Context.ReplicateToAll("ChargeStarted", {})
	end,
	OnHold = function(Context: Types.Context, Elapsed: number): ()
		Context.ReplicateToAll("Charging", { NumberValue = Elapsed })
	end,
	OnRelease = function(Context: Types.Context, Elapsed: number): ()
		Context.ReplicateToAll("Released", { NumberValue = Elapsed })
	end,
	OnCancel = function(Context: Types.Context, Reason: Types.EndReason): ()
		Context.ReplicateToAll("Interrupted", { TextValue = Reason })
	end,
	OnEnded = function(): ()
		ActiveEffects -= 1
	end,
}

local Started = AbilityRunner.Begin("player-1", "Charge", "cast-1", ChargeAbility)
assert(Started.Ok and Started.Changed, "the first cast should start")
local Duplicate = AbilityRunner.Begin("player-1", "Charge", "cast-1", ChargeAbility)
assert(Duplicate.Ok and not Duplicate.Changed, "a repeated input must not acquire a second effect")
Now = 0.5
assert(AbilityRunner.Hold("player-1", "cast-1").Ok, "the cast should enter Hold")
Now = 1.5
assert(AbilityRunner.Release("player-1", "cast-1").Ok, "the cast should release")
assert(ActiveEffects == 0, "release must clean up its effect")
assert(AbilityRunner.GetState("player-1", "cast-1") == nil, "released casts must leave active storage")

assert(AbilityRunner.Begin("player-1", "Charge", "cast-2", ChargeAbility).Ok, "a new cast should start")
assert(AbilityRunner.Cancel("player-1", "cast-2").Ok, "an interruption should cancel the cast")
assert(AbilityRunner.Cancel("player-1", "cast-2").Ok, "repeated cancellation should be harmless")
assert(ActiveEffects == 0, "interruption must clean up its effect")

local FailedReason: Types.EndReason? = nil
local Failed = AbilityRunner.Begin("player-1", "BrokenEffect", "cast-3", {
	OnStart = function(): ()
		error("Example effect could not initialize")
	end,
	OnEnded = function(_, Reason: Types.EndReason): ()
		FailedReason = Reason
	end,
})
assert(not Failed.Ok and Failed.Error ~= nil, "a callback failure should return an explicit failure")
assert(FailedReason == "Failed", "failed initialization must still end the execution")
assert(AbilityRunner.GetState("player-1", "cast-3") == nil, "failed casts must leave active storage")

assert(AbilityRunner.Begin("player-1", "Charge", "cast-4", ChargeAbility).Ok, "the runner remains usable")
AbilityRunner.Destroy()
AbilityRunner.Destroy()
assert(ActiveEffects == 0, "shutdown must clean up active effects exactly once")
assert(not AbilityRunner.Begin("player-1", "Charge", "cast-5", ChargeAbility).Ok, "shutdown is terminal")

for _, Event in Events do
	print(Event)
end
print("PASS: release, duplicate input, interruption, callback failure, and shutdown")
