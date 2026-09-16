--[[
	Skill Registry -- validates and indexes immutable skill entries.
	VZN Framework | Copyright (c) 2026 Zachary Vanier.
]]

--» DEPENDENCIES «--

local Types = require(if script then script.Parent.Types else "./Types")

--» TYPE DEFINITIONS «--

type Entry = Types.Entry
type Registry = Types.Registry

type RegistryModule = {
	Create: (Entries: { Entry }) -> Registry,
}

--» PUBLIC API «--

local RegistryModule = {} :: RegistryModule

RegistryModule.Create = function(Entries: { Entry }): Registry
	local ById: { [string]: Entry } = {}
	local Ordered: { Entry } = {}

	for _, EntryValue in Entries do
		local Definition = EntryValue.Definition
		assert(Definition.Id ~= "", "Skill definition Id cannot be empty")
		assert(Definition.Cooldown >= 0, `Skill {Definition.Id} has a negative cooldown`)
		assert(ById[Definition.Id] == nil, `Duplicate skill id: {Definition.Id}`)
		assert(
			type(EntryValue.Behavior.ResolveAudience) == "function",
			`Skill {Definition.Id} requires ResolveAudience`
		)
		assert(type(EntryValue.Behavior.Validate) == "function", `Skill {Definition.Id} requires Validate`)

		ById[Definition.Id] = EntryValue
		table.insert(Ordered, EntryValue)
	end

	local RegistryValue: Registry = {
		Resolve = function(SkillId: string): Entry?
			return ById[SkillId]
		end,
		List = function(): { Entry }
			return table.clone(Ordered)
		end,
	}

	return table.freeze(RegistryValue)
end

return table.freeze(RegistryModule)
