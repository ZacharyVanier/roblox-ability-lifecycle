--[[
	Skill Lifecycle -- plans mode-specific behavior transitions without side effects.
	VZN Framework | Copyright (c) 2026 Zachary Vanier.
]]

--» DEPENDENCIES «--

local Types = require(if script then script.Parent.Types else "./Types")

--» TYPE DEFINITIONS «--

type Action = Types.Action
type Mode = Types.Mode

export type Step = "Begin" | "Hold" | "Release" | "Cancel" | "CancelExisting"

export type PlanResult = {
	Ok: boolean,
	Steps: { Step },
	Reason: string?,
}

type Lifecycle = {
	Plan: (Mode: Mode, Action: Action, HasActiveUse: boolean) -> PlanResult,
}

--» PUBLIC API «--

local Lifecycle = {} :: Lifecycle

Lifecycle.Plan = function(ModeValue: Mode, ActionValue: Action, HasActiveUse: boolean): PlanResult
	if ModeValue == "Instant" then
		if ActionValue == "Begin" then
			return { Ok = true, Steps = { "Begin", "Release" }, Reason = nil }
		end
		return { Ok = false, Steps = {}, Reason = "Instant skills only accept Begin" }
	end

	if ModeValue == "Toggle" then
		if ActionValue == "Begin" then
			return {
				Ok = true,
				Steps = if HasActiveUse then { "CancelExisting" } else { "Begin" },
				Reason = nil,
			}
		end
		if ActionValue == "Cancel" and HasActiveUse then
			return { Ok = true, Steps = { "Cancel" }, Reason = nil }
		end
		return { Ok = false, Steps = {}, Reason = "Toggle skills accept Begin or Cancel" }
	end

	if ActionValue == "Begin" then
		if HasActiveUse then
			return { Ok = false, Steps = {}, Reason = "Skill already has an active use" }
		end
		return { Ok = true, Steps = { "Begin" }, Reason = nil }
	end

	if not HasActiveUse then
		return { Ok = false, Steps = {}, Reason = "Skill has no active use" }
	end

	return { Ok = true, Steps = { ActionValue :: Step }, Reason = nil }
end

return table.freeze(Lifecycle)
