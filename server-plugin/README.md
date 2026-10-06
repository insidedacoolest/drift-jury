# DriftFactoryPlugin (AssettoServer)

Serves the Drift Factory Judge App online script (`online/driftfactory.lua`)
to every CSP player who joins, from AssettoServer itself — for hosts that
don't let you link an online script from GitHub (Pitlane Hosting only
accepts Pastebin links there).

When the server starts, the plugin downloads the current
`online/driftfactory.lua` from this repository's `master` branch and hands
it to AssettoServer's own script provider (`CSPServerScriptProvider`), which
adds it to the CSP extra options sent to clients and serves it from the
server's HTTP port. If GitHub can't be reached, the copy built into the
plugin is used. New versions of the app therefore only need a push to
GitHub and a server restart — no new plugin upload.

Needs `EnableClientMessages: true` in `extra_cfg.yml` for the shared
leaderboard (the plugin logs a warning if it's off).

## Results and Discord (0.3)

The plugin also receives every run result the online script reports
(`RunResultEvent`, the same layout as `src/leaderboard.lua`), relays it to
the other players (AssettoServer stops relaying a message type once a
plugin handles it) and keeps:

- `driftfactory-data/runs.jsonl` — every run, valid or not, for good;
- `driftfactory-data/state.json` — each driver's best valid run per track
  per week (Monday–Sunday, Europe/Lisbon), plus the Discord message ids.

With webhook URLs configured it mirrors that to Discord: a live status
message, a weekly leaderboard per track (edited in place, marked FINAL at
the end of the week) and announcements of new weekly bests and winners.
See `discord-setup/README.md`. Optional configuration:

```yaml
---
!DriftFactoryConfiguration
StatusWebhookUrl: https://discord.com/api/webhooks/...
LeaderboardWebhookUrl: https://discord.com/api/webhooks/...
RunsWebhookUrl: https://discord.com/api/webhooks/...
JoinUrl: https://acstuff.ru/s/q:race/online/join?ip=...&httpPort=...
StatusIntervalSeconds: 60
TimeZone: Europe/Lisbon
DataDirectory: driftfactory-data
```

## Website data (0.4)

`GET /driftfactory/site.json` on the server's HTTP port returns the server
right now (track, players, cars, join link), this week's leaderboard (top
50, with the line/angle/style breakdown) and the finished weeks (top 10
each, most recent first, up to a year). Read-only and public — the same
information Discord shows, without Steam ids.

The site's hosting can't reach the game server's HTTP port, so since 0.5
the plugin also pushes the same snapshot every minute (and right after a
new weekly best) to the Drift Virtual page on driftfactory.pt:

```yaml
SiteSyncUrl: https://driftfactory.pt/api/virtual/sync   # default
SiteSyncKey: <key>   # dist/site/site-sync-key.txt; the site only keeps its SHA-256
```

Without `SiteSyncKey` nothing is sent. The page shows the server as
offline once the last push is over three minutes old.

## Building

Built against AssettoServer **v0.0.54** (the version Pitlane runs), .NET 8:

```
git clone https://github.com/compujuckel/AssettoServer.git
git -C AssettoServer checkout v0.0.54
dotnet publish server-plugin/DriftFactoryPlugin/DriftFactoryPlugin.csproj -c Release -o dist/plugin/DriftFactoryPlugin -p:AssettoServerSrc=<path to AssettoServer checkout>
```

(AssettoServer's build needs a full clone, not a shallow one — it derives
its version number from git history.) Zip the `DriftFactoryPlugin` folder
and upload it to the server's plugins; enable it with
`EnablePlugins: [DriftFactoryPlugin]`.

Tested against a local AssettoServer v0.0.54: the plugin loads, fetches the
script from GitHub, and `/api/scripts/0` serves it byte-for-byte.
