-- Drift Factory Judge App — server-delivered version (CSP online script).
--
-- The server's CSP extra options load the bundled online/driftfactory.lua
-- (built from this file plus ac-lua/DriftFactoryJudgeApp/src by
-- online/build.lua), so players get the judge just by joining. Same
-- judging, scoring, official layouts and leaderboard as the installed app;
-- layout editing, calibration and car setup stay in the installed app,
-- since online scripts can't save files.
--
-- A modified version of DriftJudging SP by DeadEndReece, AGPL-3.0 with
-- additional attribution terms — see ac-lua/DriftFactoryJudgeApp/CREDITS.md
-- and LICENSE.md in github.com/insidedacoolest/drift-jury.

local Context = require('src.context')
local OnlineStorage = require('src.storage_online')
local Draw = require('src.draw')
local UI = require('src.ui_app')
local Leaderboard = require('src.leaderboard')

local FONTS_URL = 'https://raw.githubusercontent.com/insidedacoolest/drift-jury/master/online/fonts.zip'

local context = Context.new({
  createStorage = function(track, layoutID, carID) return OnlineStorage.new(track, layoutID, carID) end,
  editingDisabled = true,
})

-- Brand fonts: CSP downloads and caches the zip itself; until it lands (or
-- if it can't), the HUD uses CSP's default font.
if web and web.loadRemoteAssets then
  pcall(web.loadRemoteAssets, FONTS_URL, function(err, folder)
    if (not err or err == '') and folder and folder ~= '' then Draw.setFontsDir(folder) end
  end)
end

-- Main window: opened from the online extras menu in CSP's chat app
-- (lightbulb icon), as a tool window that stays on screen.
ui.registerOnlineExtra(ui.Icons.Speedometer, 'Drift Factory Judge', nil,
  function() UI.window(context) end, nil,
  ui.OnlineExtraFlags.Tool, ui.WindowFlags.None, vec2(400, 520))

function script.update(dt)
  dt = tonumber(dt) or 0
  context:applyPendingOfficialLayout()
  context.session:update(dt)
end

function script.draw3D()
  Draw.layout(context)
end

-- Drawn straight onto the screen: the session leaderboard in the top-right
-- corner (unless turned off in the run tab), and the score HUD at the bottom
-- center during the countdown, the run and for a few seconds after.
function script.drawUI()
  if context.showLeaderboard then
    local entries = Leaderboard.entries()
    local width = Draw.leaderboardSize(entries)
    Draw.leaderboard(context, entries, vec2(ac.getSim().windowWidth - width - 24, 24))
  end
  Draw.hud(context, false)
end
