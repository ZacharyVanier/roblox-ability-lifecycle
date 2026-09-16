--[[
	Skill Cooldown Store -- tracks server-clock deadlines and per-skill charges.
	VZN Framework | Copyright (c) 2026 Zachary Vanier.
]]

--» DEPENDENCIES «--

local Types = require("./Types")

--» TYPE DEFINITIONS «--

type Availability = Types.Availability
type CooldownStore = Types.CooldownStore
type Definition = Types.Definition

type Clock = {
	Now: () -> number,
}

type ChargeState = {
	Charges: number,
	Deadlines: { number },
}

type ActorState = {
	GlobalDeadline: number,
	GroupDeadlines: { [string]: number },
	Skills: { [string]: ChargeState },
}

type CooldownStoreModule = {
	Create: (Clock: Clock) -> CooldownStore,
}

--» PRIVATE FUNCTIONS «--

local function maximumCharges(DefinitionValue: Definition): number
	return math.max(1, math.floor(DefinitionValue.MaxCharges or 1))
end

local function rechargeDuration(DefinitionValue: Definition): number
	return DefinitionValue.RechargeDuration or DefinitionValue.Cooldown
end

--» PUBLIC API «--

local CooldownStoreModule = {} :: CooldownStoreModule

CooldownStoreModule.Create = function(ClockValue: Clock): CooldownStore
	assert(type(ClockValue.Now) == "function", "CooldownStore requires Clock.Now")

	local Actors: { [string]: ActorState } = {}

	local function getActor(ActorId: string): ActorState
		local State = Actors[ActorId]
		if State == nil then
			State = {
				GlobalDeadline = 0,
				GroupDeadlines = {},
				Skills = {},
			}
			Actors[ActorId] = State
		end
		return State
	end

	local function getCharges(State: ActorState, DefinitionValue: Definition, Now: number): ChargeState
		local Charges = State.Skills[DefinitionValue.Id]
		local MaxCharges = maximumCharges(DefinitionValue)
		if Charges == nil then
			Charges = {
				Charges = MaxCharges,
				Deadlines = {},
			}
			State.Skills[DefinitionValue.Id] = Charges
		end

		local Pending = {}
		for _, Deadline in Charges.Deadlines do
			if Deadline <= Now and Charges.Charges < MaxCharges then
				Charges.Charges += 1
			else
				table.insert(Pending, Deadline)
			end
		end
		Charges.Deadlines = Pending
		return Charges
	end

	local Store: CooldownStore
	Store = {
		Check = function(ActorId: string, DefinitionValue: Definition): Availability
			local Now = ClockValue.Now()
			local State = getActor(ActorId)
			local Charges = getCharges(State, DefinitionValue, Now)

			if State.GlobalDeadline > Now then
				return {
					Ready = false,
					Reason = "GlobalCooldown",
					Remaining = State.GlobalDeadline - Now,
					Charges = Charges.Charges,
				}
			end

			local Group = DefinitionValue.Group
			local GroupDeadline = if Group then State.GroupDeadlines[Group] or 0 else 0
			if GroupDeadline > Now then
				return {
					Ready = false,
					Reason = "GroupCooldown",
					Remaining = GroupDeadline - Now,
					Charges = Charges.Charges,
				}
			end

			if Charges.Charges <= 0 then
				local NextDeadline = Charges.Deadlines[1] or Now
				for _, Deadline in Charges.Deadlines do
					NextDeadline = math.min(NextDeadline, Deadline)
				end
				return {
					Ready = false,
					Reason = "SkillCooldown",
					Remaining = math.max(0, NextDeadline - Now),
					Charges = 0,
				}
			end

			return { Ready = true, Reason = nil, Remaining = 0, Charges = Charges.Charges }
		end,

		Consume = function(ActorId: string, DefinitionValue: Definition): boolean
			local AvailabilityValue = Store.Check(ActorId, DefinitionValue)
			if not AvailabilityValue.Ready then
				return false
			end

			local Now = ClockValue.Now()
			local State = getActor(ActorId)
			local Charges = getCharges(State, DefinitionValue, Now)
			Charges.Charges -= 1

			local Recharge = rechargeDuration(DefinitionValue)
			if Recharge > 0 then
				table.insert(Charges.Deadlines, Now + Recharge)
				table.sort(Charges.Deadlines)
			else
				Charges.Charges = maximumCharges(DefinitionValue)
			end

			State.GlobalDeadline = math.max(State.GlobalDeadline, Now + (DefinitionValue.GlobalCooldown or 0))
			if DefinitionValue.Group then
				State.GroupDeadlines[DefinitionValue.Group] = math.max(
					State.GroupDeadlines[DefinitionValue.Group] or 0,
					Now + (DefinitionValue.GroupCooldown or 0)
				)
			end

			return true
		end,

		ClearActor = function(ActorId: string): ()
			Actors[ActorId] = nil
		end,
	}

	return table.freeze(Store)
end

return table.freeze(CooldownStoreModule)
