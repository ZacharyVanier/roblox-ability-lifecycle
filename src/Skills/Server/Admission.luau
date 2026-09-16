--[[
	Skill Admission -- rejects replayed, out-of-sequence, and rate-limited intents.
	VZN Framework | Copyright (c) 2026 Zachary Vanier.
]]

--» DEPENDENCIES «--

local Types = require("./Types")

--» TYPE DEFINITIONS «--

type Admission = Types.Admission
type Request = Types.Request
type ValidationResult = Types.ValidationResult

type Clock = {
	Now: () -> number,
}

type ActorState = {
	LastSequence: number,
	RecentRequests: { number },
	SeenUses: { [string]: number },
	ReplayOrder: {
		{
			UseId: string,
			Timestamp: number,
		}
	},
}

type AdmissionModule = {
	Create: (Clock: Clock, MaxRequests: number, WindowSeconds: number, MaxSeenUses: number?) -> Admission,
}

--» PUBLIC API «--

local AdmissionModule = {} :: AdmissionModule

AdmissionModule.Create = function(
	ClockValue: Clock,
	MaxRequests: number,
	WindowSeconds: number,
	MaxSeenUses: number?
): Admission
	assert(MaxRequests > 0, "Admission MaxRequests must be positive")
	assert(WindowSeconds > 0, "Admission WindowSeconds must be positive")
	local ReplayLimit = MaxSeenUses or math.max(64, MaxRequests * 4)
	assert(ReplayLimit > 0 and ReplayLimit % 1 == 0, "Admission MaxSeenUses must be a positive integer")

	local Actors: { [string]: ActorState } = {}

	local AdmissionValue: Admission = {
		Admit = function(RequestValue: Request): ValidationResult
			local State = Actors[RequestValue.ActorId]
			if State == nil then
				State = {
					LastSequence = 0,
					RecentRequests = {},
					SeenUses = {},
					ReplayOrder = {},
				}
				Actors[RequestValue.ActorId] = State
			end

			local Now = ClockValue.Now()
			local Cutoff = Now - WindowSeconds
			local Recent = {}
			for _, Timestamp in State.RecentRequests do
				if Timestamp > Cutoff then
					table.insert(Recent, Timestamp)
				end
			end
			State.RecentRequests = Recent

			local ReplayOrder = {}
			for _, ReplayValue in State.ReplayOrder do
				if ReplayValue.Timestamp > Cutoff then
					table.insert(ReplayOrder, ReplayValue)
				elseif State.SeenUses[ReplayValue.UseId] == ReplayValue.Timestamp then
					State.SeenUses[ReplayValue.UseId] = nil
				end
			end
			State.ReplayOrder = ReplayOrder

			if #Recent >= MaxRequests then
				return { Ok = false, Reason = "RateLimited" }
			end
			table.insert(Recent, Now)

			if RequestValue.Sequence <= State.LastSequence then
				return { Ok = false, Reason = "OutOfSequence" }
			end
			State.LastSequence = RequestValue.Sequence

			if RequestValue.Action == "Begin" and State.SeenUses[RequestValue.UseId] then
				return { Ok = false, Reason = "Replay" }
			end

			if RequestValue.Action == "Begin" then
				State.SeenUses[RequestValue.UseId] = Now
				table.insert(State.ReplayOrder, {
					UseId = RequestValue.UseId,
					Timestamp = Now,
				})
				while #State.ReplayOrder > ReplayLimit do
					local Removed = table.remove(State.ReplayOrder, 1)
					if Removed and State.SeenUses[Removed.UseId] == Removed.Timestamp then
						State.SeenUses[Removed.UseId] = nil
					end
				end
			end
			return { Ok = true, Reason = nil }
		end,

		ClearActor = function(ActorId: string): ()
			Actors[ActorId] = nil
		end,
	}

	return table.freeze(AdmissionValue)
end

return table.freeze(AdmissionModule)
