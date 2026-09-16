--[[
	Skills Server Types -- the feature's single crossing into the replicated realm.
	VZN Framework | Copyright (c) 2026 Zachary Vanier.
]]

--» DEPENDENCIES «--

-- Server maps into ServerStorage while Shared maps into ReplicatedStorage, so a
-- server module reaching a shared contract genuinely needs both paths. Paying
-- that once per feature and re-exporting keeps every sibling on the cheap
-- same-realm form, `require("./Types")`.
local ReplicatedStorage = if script then game:GetService("ReplicatedStorage") else nil
local SkillsRoot = if ReplicatedStorage then ReplicatedStorage.VZNCore.Features.Skills else nil
local BehaviorRoot = if ReplicatedStorage then ReplicatedStorage.VZNCore.Features.Behavior else nil
local SharedTypes = require(if SkillsRoot then SkillsRoot.Shared.Types else "../Shared/Types")
local BehaviorTypes = require(if BehaviorRoot then BehaviorRoot.Shared.Types else "../../Behavior/Shared/Types")

--» TYPE DEFINITIONS «--

export type Mode = SharedTypes.Mode
export type Action = SharedTypes.Action
export type EndReason = SharedTypes.EndReason
export type Values = SharedTypes.Values
export type Payload = SharedTypes.Payload
export type Audience = SharedTypes.Audience
export type Definition = SharedTypes.Definition
export type Request = SharedTypes.Request
export type ValidationContext = SharedTypes.ValidationContext
export type ValidationResult = SharedTypes.ValidationResult
export type Context = SharedTypes.Context
export type Behavior = SharedTypes.Behavior
export type Entry = SharedTypes.Entry
export type Registry = SharedTypes.Registry
export type Availability = SharedTypes.Availability
export type CooldownStore = SharedTypes.CooldownStore
export type Admission = SharedTypes.Admission
export type ServerTransport = SharedTypes.ServerTransport
export type ClientTransport = SharedTypes.ClientTransport
export type ServiceResult = SharedTypes.ServiceResult
export type Service = SharedTypes.Service

-- Behavior is a separate feature, so its contracts cross here too rather than
-- making every consumer repeat a second selector.
export type BehaviorContext = BehaviorTypes.Context
export type BehaviorRunner = BehaviorTypes.Runner
export type UseBehavior = BehaviorTypes.UseBehavior

--» MODULE EXPORT «--

return {}
