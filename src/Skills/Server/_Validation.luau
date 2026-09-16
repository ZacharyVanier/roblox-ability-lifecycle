--[[
	Skill Validation -- stateless intent validation and audience normalization.
	VZN Framework | Copyright (c) 2026 Zachary Vanier.
]]

--» DEPENDENCIES «--

local Types = require("./Types")

--» TYPE DEFINITIONS «--

type Audience = Types.Audience
type Behavior = Types.Behavior
type ServiceResult = Types.ServiceResult
type ValidationContext = Types.ValidationContext

type ValidationModule = {
	Response: (Ok: boolean, Changed: boolean, Generation: number?, Reason: string?) -> ServiceResult,
	NormalizeAudience: (AudienceValue: Audience) -> Audience?,
	Validate: (BehaviorValue: Behavior, ContextValue: ValidationContext) -> (boolean, string?),
	ResolveAudience: (BehaviorValue: Behavior, ContextValue: ValidationContext) -> Audience?,
}

--» CONSTANTS «--

local MAX_AUDIENCE_ACTORS = 64
local MAX_REJECTION_REASON_LENGTH = 96

--» PUBLIC API «--

local ValidationModule = {} :: ValidationModule

ValidationModule.Response = function(Ok: boolean, Changed: boolean, Generation: number?, Reason: string?): ServiceResult
	return { Ok = Ok, Changed = Changed, Generation = Generation, Reason = Reason }
end

ValidationModule.NormalizeAudience = function(AudienceValue: Audience): Audience?
	local ActorIds = {}
	local Seen: { [string]: boolean } = {}
	for _, ActorId in AudienceValue.ActorIds do
		if type(ActorId) ~= "string" or #ActorId == 0 or #ActorId > 64 then
			return nil
		end
		if not Seen[ActorId] then
			if #ActorIds >= MAX_AUDIENCE_ACTORS then
				return nil
			end
			Seen[ActorId] = true
			table.insert(ActorIds, ActorId)
		end
	end

	return table.freeze({ ActorIds = table.freeze(ActorIds) })
end

-- Behavior code is project-supplied, so every call into it is contained. A
-- thrown error becomes a typed rejection rather than reaching the transport,
-- which keeps a faulty behavior from leaking its message to clients.
ValidationModule.Validate = function(BehaviorValue: Behavior, ContextValue: ValidationContext): (boolean, string?)
	local Succeeded, Valid, Reason = pcall(function(): (boolean, string?)
		local Result = BehaviorValue.Validate(ContextValue)
		if type(Result) ~= "table" then
			return false, "InvalidValidationResult"
		end

		local OkValue = Result.Ok
		local ReasonValue = Result.Reason
		if type(OkValue) ~= "boolean" then
			return false, "InvalidValidationResult"
		end
		if
			ReasonValue ~= nil
			and (type(ReasonValue) ~= "string" or #ReasonValue == 0 or #ReasonValue > MAX_REJECTION_REASON_LENGTH)
		then
			return false, "InvalidValidationResult"
		end
		if not OkValue then
			return false, ReasonValue or "ValidationFailed"
		end
		return true, nil
	end)
	if not Succeeded then
		return false, "ValidationException"
	end
	return Valid, Reason
end

ValidationModule.ResolveAudience = function(BehaviorValue: Behavior, ContextValue: ValidationContext): Audience?
	local Succeeded, AudienceValue = pcall(function(): Audience?
		return ValidationModule.NormalizeAudience(BehaviorValue.ResolveAudience(ContextValue))
	end)
	if not Succeeded then
		return nil
	end
	return AudienceValue
end

--» MODULE EXPORT «--

return table.freeze(ValidationModule)
