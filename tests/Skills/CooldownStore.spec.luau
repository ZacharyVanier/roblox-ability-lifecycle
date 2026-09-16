--[[
	Skill Cooldown Store spec -- verifies absolute deadlines, charges, and cooldown scopes.
	VZN Framework | Copyright (c) 2026 Zachary Vanier.
]]

local Harness = require("../TestHarness")
local CooldownStore = require("../../src/Skills/Server/CooldownStore")

local Test, Finish = Harness.New("Skill Cooldown Store")

Test("replenishes charges from absolute deadlines", function()
	local Now = 10
	local Store = CooldownStore.Create({
		Now = function()
			return Now
		end,
	})
	local Definition = {
		Id = "Pulse",
		Mode = "Charged",
		Cooldown = 5,
		MaxCharges = 2,
		RechargeDuration = 5,
	}

	assert(Store.Consume("actor", Definition), "test assertion failed")
	assert(Store.Consume("actor", Definition), "test assertion failed")
	assert(Store.Check("actor", Definition).Reason == "SkillCooldown", "test assertion failed")
	Now = 15
	assert(Store.Check("actor", Definition).Charges == 2, "test assertion failed")
end)

Test("enforces global and group cooldown deadlines", function()
	local Now = 20
	local Store = CooldownStore.Create({
		Now = function()
			return Now
		end,
	})
	local First = {
		Id = "First",
		Mode = "Instant",
		Cooldown = 0,
		GlobalCooldown = 2,
		Group = "Movement",
		GroupCooldown = 4,
	}
	local Second = { Id = "Second", Mode = "Instant", Cooldown = 0, Group = "Movement" }

	assert(Store.Consume("actor", First), "test assertion failed")
	assert(Store.Check("actor", Second).Reason == "GlobalCooldown", "test assertion failed")
	Now = 23
	assert(Store.Check("actor", Second).Reason == "GroupCooldown", "test assertion failed")
	Now = 25
	assert(Store.Check("actor", Second).Ready, "test assertion failed")
end)

Test("removes actor-owned cooldown state", function()
	local Store = CooldownStore.Create({
		Now = function()
			return 0
		end,
	})
	local Definition = { Id = "Pulse", Mode = "Instant", Cooldown = 10 }

	assert(Store.Consume("actor", Definition), "test assertion failed")
	assert(not Store.Check("actor", Definition).Ready, "test assertion failed")
	Store.ClearActor("actor")
	assert(Store.Check("actor", Definition).Ready, "test assertion failed")
end)

Finish()
