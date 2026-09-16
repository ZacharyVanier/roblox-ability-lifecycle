--[[
	TestHarness -- runs small standalone Lune test files.
	VZN Framework | Copyright (c) 2026 Zachary Vanier | MIT License.
	GitHub-managed: do not modify in Roblox Studio.
]]

local process = require("@lune/process")

export type Test = (string, () -> ()) -> ()
export type Finish = () -> ()

export type Harness = {
	New: (string) -> (Test, Finish),
}

local Harness = {} :: Harness

Harness.New = function(SuiteName: string): (Test, Finish)
	local Passed = 0
	local Failed = 0

	local function Test(Name: string, Callback: () -> ()): ()
		local DidPass, ErrorValue = pcall(Callback)

		if DidPass then
			Passed += 1
			print(`  PASS: {Name}`)
		else
			Failed += 1
			print(`  FAIL: {Name}`)
			print(`        {ErrorValue}`)
		end
	end

	local function Finish(): ()
		print(`{SuiteName}: {Passed} passed, {Failed} failed`)

		if Failed > 0 then
			process.exit(1)
		end
	end

	return Test, Finish
end

return table.freeze(Harness)
