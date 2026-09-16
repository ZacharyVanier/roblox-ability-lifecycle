--[[
	Skills Types -- shared contracts for skill definitions, requests, and authority adapters.
	VZN Framework | Copyright (c) 2026 Zachary Vanier.
]]

--» DEPENDENCIES «--

local ReplicatedStorage = if script then game:GetService("ReplicatedStorage") else nil
local BehaviorRoot = if ReplicatedStorage then ReplicatedStorage.VZNCore.Features.Behavior else nil
local BehaviorTypes = require(if BehaviorRoot then BehaviorRoot.Shared.Types else "../../Behavior/Shared/Types")

--» TYPE DEFINITIONS «--

export type Mode = "Instant" | "Hold" | "Charged" | "Counter" | "Toggle"
export type Action = "Begin" | "Hold" | "Release" | "Cancel"
export type EndReason = BehaviorTypes.EndReason

export type Values = {
	Numbers: { number },
	Texts: { string },
	Booleans: { boolean },
}

export type Payload =
	{ Kind: "None" }
	| {
		Kind: "Aim",
		Position: Vector3,
		Direction: Vector3,
		TargetId: string?,
		Values: Values?,
	}
	| {
		Kind: "Placement",
		Placement: CFrame,
		TargetId: string?,
		Values: Values?,
	}
	| {
		Kind: "Values",
		TargetId: string?,
		Values: Values,
	}

export type Audience = {
	ActorIds: { string },
}

export type Definition = {
	Id: string,
	Mode: Mode,
	Cooldown: number,
	GlobalCooldown: number?,
	Group: string?,
	GroupCooldown: number?,
	MaxCharges: number?,
	RechargeDuration: number?,
}

export type Request = {
	ActorId: string,
	SkillId: string,
	UseId: string,
	Sequence: number,
	Action: Action,
	Payload: Payload,
}

export type ValidationContext = {
	ActorId: string,
	SkillId: string,
	UseId: string,
	Generation: number,
	Action: Action,
	Payload: Payload,
	Now: number,
}

export type ValidationResult = {
	Ok: boolean,
	Reason: string?,
}

export type Context = {
	ActorId: string,
	SkillId: string,
	UseId: string,
	Generation: number,
	StartedAt: number,
	Action: Action,
	Payload: Payload,
	Present: (EventName: string, Payload: Payload) -> (),
}

export type Behavior = {
	ResolveAudience: (Context: ValidationContext) -> Audience,
	Validate: (Context: ValidationContext) -> ValidationResult,
	OnStart: ((Context: Context) -> ())?,
	OnHold: ((Context: Context, Elapsed: number) -> ())?,
	OnRelease: ((Context: Context, Elapsed: number) -> ())?,
	OnCancel: ((Context: Context, Reason: EndReason) -> ())?,
	OnEnded: ((Context: Context, Reason: EndReason) -> ())?,
}

export type Entry = {
	Definition: Definition,
	Behavior: Behavior,
}

export type Registry = {
	Resolve: (SkillId: string) -> Entry?,
	List: () -> { Entry },
}

export type Availability = {
	Ready: boolean,
	Reason: string?,
	Remaining: number,
	Charges: number,
}

export type CooldownStore = {
	Check: (ActorId: string, Definition: Definition) -> Availability,
	Consume: (ActorId: string, Definition: Definition) -> boolean,
	ClearActor: (ActorId: string) -> (),
}

export type Admission = {
	Admit: (Request: Request) -> ValidationResult,
	ClearActor: (ActorId: string) -> (),
}

export type ServerTransport = {
	Present: (
		Audience: Audience,
		ActorId: string,
		SkillId: string,
		UseId: string,
		Generation: number,
		EventName: string,
		Payload: Payload
	) -> (),
	SendLifecycle: (
		Audience: Audience,
		ActorId: string,
		SkillId: string,
		UseId: string,
		Generation: number,
		Active: boolean,
		Reason: EndReason?
	) -> (),
	SendAccepted: (ActorId: string, SkillId: string, UseId: string, Generation: number) -> (),
	SendRejected: (ActorId: string, SkillId: string, UseId: string, Reason: string) -> (),
}

export type ClientTransport = {
	SendIntent: (SkillId: string, UseId: string, Sequence: number, Action: Action, Payload: Payload) -> (),
}

export type ServiceResult = {
	Ok: boolean,
	Changed: boolean,
	Generation: number?,
	Reason: string?,
}

export type Service = {
	Handle: (Request: Request) -> ServiceResult,
	RemoveActor: (ActorId: string) -> (),
	Destroy: () -> (),
}

return table.freeze({})
