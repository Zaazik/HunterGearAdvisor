-- Test runner: lua tests/run.lua (from the addon root). Lua 5.4 with WoW Lua 5.1 shims.
unpack = unpack or table.unpack

local root = (arg and arg[0] and arg[0]:match("^(.*)[/\\]tests[/\\]run%.lua$")) or "."
package.path = root .. "/tests/?.lua;" .. package.path

local ns = {}
local function load(path)
	local chunk = assert(loadfile(root .. "/" .. path))
	chunk("HunterGearAdvisor", ns)
end
load("Core/Model.lua")
load("Core/Parse.lua")
load("Core/Score.lua")
load("Core/PreRaid.lua")
load("Game/SetData.lua") -- pure data: test_score scores real sets with it
load("Game/UseData.lua") -- pure data: test_score prices real on-use buffs with it
load("Game/ProcData.lua") -- pure data: test_score links real procs with it (Items.LinkProcs's rule)

local passed, failed = 0, 0
local T = {}
function T.eq(actual, expected, msg)
	if actual ~= expected then
		error(string.format("%s: expected %s, got %s", msg or "eq", tostring(expected), tostring(actual)), 2)
	end
end
function T.near(actual, expected, tol, msg)
	if type(actual) ~= "number" or math.abs(actual - expected) > tol then
		error(string.format("%s: expected %s +- %s, got %s", msg or "near", tostring(expected), tostring(tol), tostring(actual)), 2)
	end
end
function T.truthy(v, msg) if not v then error((msg or "truthy") .. ": got " .. tostring(v), 2) end end

local files = { "test_parse", "test_model", "test_score", "test_game", "test_preraid" }
for _, f in ipairs(files) do
	local cases = require(f)(ns, T)
	for _, case in ipairs(cases) do
		local ok, err = pcall(case[2])
		if ok then
			passed = passed + 1
		else
			failed = failed + 1
			print(string.format("FAIL %s / %s\n    %s", f, case[1], err))
		end
	end
end
print(string.format("%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
