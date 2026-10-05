--[[
  Minimal, dependency-free test runner for the pure core/ modules.

  Usage (from the drift-jury/ directory):
    lua tests/run.lua

  Each test_*.lua file returns a list of { name = "...", fn = function() ... end }
  where `fn` uses plain `assert()`. No external test framework — the goal is
  that these can run anywhere a `lua` binary exists, with zero setup, which
  matters a lot for a scoring engine that has to stay tunable offline
  (§48-50 of the blueprint) without opening Assetto Corsa every time.
]]

package.path = package.path .. ';./?.lua;../ac-lua/DriftJuryPoC/core/?.lua'

local suites = {
  'test_angle',
  'test_zones',
  'test_scoring',
  'test_state_machine',
  'test_gates',
}

local totalPass, totalFail = 0, 0

for _, suiteName in ipairs(suites) do
  local ok, suiteOrErr = pcall(require, suiteName)
  if not ok then
    print('FAIL  [' .. suiteName .. '] could not load suite: ' .. tostring(suiteOrErr))
    totalFail = totalFail + 1
  else
    for _, case in ipairs(suiteOrErr) do
      local passed, err = pcall(case.fn)
      if passed then
        totalPass = totalPass + 1
      else
        totalFail = totalFail + 1
        print('FAIL  [' .. suiteName .. '] ' .. case.name .. '\n      ' .. tostring(err))
      end
    end
  end
end

print(string.format('\n%d passed, %d failed', totalPass, totalFail))
os.exit(totalFail == 0 and 0 or 1)
