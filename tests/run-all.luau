--[[
	Test Runner -- discovers and runs the standalone VZN Framework test suite.
	VZN Framework | Copyright (c) 2026 Zachary Vanier.
]]

--» TYPE DEFINITIONS «--

type FailureEntry = {
	File: string,
	Output: string,
}

--» DEPENDENCIES & VARIABLES «--

local FileSystem = require("@lune/fs")
local Process = require("@lune/process")

local Passed: number = 0
local Failed: number = 0
local AssertionSiteCount: number = 0
local Errors: { FailureEntry } = {}

local FindSpecFiles
FindSpecFiles = function(Directory: string): { string }
	local Files: { string } = {}

	for _, Entry in FileSystem.readDir(Directory) do
		local Path = `{Directory}/{Entry}`
		if FileSystem.isDir(Path) then
			if Path == "tests/Roblox" then
				continue
			end
			for _, SubFile in FindSpecFiles(Path) do
				table.insert(Files, SubFile)
			end
		elseif Entry:match("%.spec%.luau$") or Entry:match("%.test%.luau$") then
			table.insert(Files, Path)
		end
	end

	return Files
end

--» TEST EXECUTION «--

local SpecFiles = FindSpecFiles("tests")
table.sort(SpecFiles)

print("\nVZN Framework Test Suite")
print("==================")
print(`Found {#SpecFiles} test files\n`)

if #SpecFiles == 0 then
	print("no specification files were discovered under tests/")
	Process.exit(1)
end

for _, File in SpecFiles do
	local Source = FileSystem.readFile(File)
	local _, Assertions = Source:gsub("assert%s*%(", "")
	AssertionSiteCount += Assertions

	local DisplayName = File:gsub("tests/", ""):gsub("%.spec%.luau$", ""):gsub("%.test%.luau$", "")
	local Result = Process.exec("lune", { "run", File })
	if Result.ok then
		Passed += 1
		print(`  PASS  {DisplayName}`)
	else
		Failed += 1
		print(`  FAIL  {DisplayName}`)
		local Detail = (Result.stdout .. Result.stderr):gsub("^%s+", "")
		Detail = (Detail:gsub("%s+$", ""))

		table.insert(Errors, {
			File = DisplayName,
			Output = if Detail == "" then "produced no output" else Detail,
		})
	end
end

print("\n==================")
print(`Results: {Passed} passed, {Failed} failed, {Passed + Failed} total, {AssertionSiteCount} assertion sites`)

for _, Failure in Errors do
	print(`\n  {Failure.File}:`)
	print(`    {Failure.Output}`)
end

if Failed > 0 then
	Process.exit(1)
end

print("\nAll tests passed!")
