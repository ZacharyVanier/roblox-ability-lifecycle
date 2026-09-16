--[[
	Behavior Types -- contracts for deterministic use lifecycles.
	VZN Framework | Copyright (c) 2026 Zachary Vanier | MIT License.
	GitHub-managed: do not modify in Roblox Studio.
]]

--» TYPE DEFINITIONS «--

export type Payload = {
	NumberValue: number?,
	TextValue: string?,
	BooleanValue: boolean?,
}

export type Clock = {
	Now: () -> number,
}

export type Transport = {
	ReplicateToAll: (ActorId: string, BehaviorId: string, UseId: string, EventName: string, Payload: Payload) -> (),
}

export type EndReason = "Released" | "Cancelled" | "Failed" | "Destroyed"
export type State = "Started" | "Holding" | "Released" | "Cancelled" | "Ended"

export type Context = {
	ActorId: string,
	BehaviorId: string,
	UseId: string,
	StartedAt: number,
	ReplicateToAll: (EventName: string, Payload: Payload) -> (),
}

export type UseBehavior = {
	OnStart: ((Context: Context) -> ())?,
	OnHold: ((Context: Context, Elapsed: number) -> ())?,
	OnRelease: ((Context: Context, Elapsed: number) -> ())?,
	OnCancel: ((Context: Context, Reason: EndReason) -> ())?,
	OnEnded: ((Context: Context, Reason: EndReason) -> ())?,
}

export type TransitionResult = {
	Ok: boolean,
	Changed: boolean,
	State: State?,
	Error: string?,
}

export type Runner = {
	Begin: (ActorId: string, BehaviorId: string, UseId: string, Behavior: UseBehavior) -> TransitionResult,
	Hold: (ActorId: string, UseId: string) -> TransitionResult,
	Release: (ActorId: string, UseId: string) -> TransitionResult,
	Cancel: (ActorId: string, UseId: string, Reason: EndReason?) -> TransitionResult,
	GetState: (ActorId: string, UseId: string) -> State?,
	Destroy: () -> (),
}

return table.freeze({})
