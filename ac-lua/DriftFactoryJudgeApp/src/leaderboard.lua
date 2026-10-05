--[[
  Shared, session-only leaderboard broadcast via CSP's ac.OnlineEvent —
  peer-to-peer between clients (relayed through the server's chat-message
  channel under the hood), no dedicated server-side script needed. Every
  client ends up with its own copy, built from everyone's broadcasts,
  including its own (sender.index == 0 means "from me").

  NOT authoritative: a modified client could broadcast a fake score, same
  trust model as the rest of this fork for now. A validated version needs
  an actual server-side script independently re-checking each run — a
  separate, bigger project (see README.md).
]]

local M = {}

local entries = {} -- carIndex -> { name, score, valid, line, angle, styleSpeed }

local broadcast = ac.OnlineEvent({
  ac.StructItem.key('driftFactoryJudgeApp_runResult'),
  score = ac.StructItem.float(),
  valid = ac.StructItem.boolean(),
  line = ac.StructItem.float(),
  angle = ac.StructItem.float(),
  styleSpeed = ac.StructItem.float(),
}, function(sender, data)
  local carIndex = sender and sender.index or 0
  local existing = entries[carIndex]
  if existing and not (data.valid and (not existing.valid or data.score > existing.score)) then
    return
  end
  entries[carIndex] = {
    name = ac.getDriverName(carIndex) or ('Car ' .. carIndex),
    score = data.score,
    valid = data.valid,
    line = data.line,
    angle = data.angle,
    styleSpeed = data.styleSpeed,
  }
end)

-- Reports a completed (non-calibration) run's score to everyone else online.
-- A no-op over the network while offline (nothing else is listening), but
-- still updates this client's own leaderboard entry either way.
--
-- `repeatForNewConnections = true` makes CSP remember this as our current
-- "sticky" broadcast and auto-resend it to anyone who joins the server
-- later in the session — without it, a player joining after you'd never
-- see your score at all, since OnlineEvent only delivers messages sent
-- *after* you're connected, not anything broadcast earlier.
function M.report(score)
  broadcast({
    score = score.score or 0,
    valid = score.valid or false,
    line = score.line or 0,
    angle = score.angle or 0,
    styleSpeed = score.styleSpeed or 0,
  }, true)
end

-- Best-score-first list of every driver seen this session.
function M.entries()
  local list = {}
  for _, entry in pairs(entries) do list[#list + 1] = entry end
  table.sort(list, function(a, b) return a.score > b.score end)
  return list
end

return M
