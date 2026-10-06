# DriftFactory Discord server

`setup.mjs` builds the community Discord server from `content.mjs` —
roles, categories, channels and their permissions, the fixed messages
(welcome, rules, how to join, cars, tracks, layouts) and the webhooks the
AssettoServer plugin (`server-plugin/`) posts to. Re-running it is safe:
existing channels are reused and the bot's messages are edited in place.

## What's live

Posted by `DriftFactoryPlugin` on the game server through webhooks, no
bot needs to stay online:

- **#estado-servidores** — track, drivers online, cars and the Content
  Manager join link, refreshed every minute (one message, edited).
- **#classificação** — one leaderboard message per track per week (Monday
  to Sunday, Lisbon time), best valid run per driver, edited after every
  improvement and marked FINAL when the week ends. Old weeks stay.
- **#runs** — new weekly bests and the weekly winner.

Every run is also kept for good on the server in
`driftfactory-data/runs.jsonl`.

## Running it

1. Create an empty Discord server and a bot application
   (discord.com/developers/applications), add the bot to the server with
   the Administrator permission.
2. Put the bot token in `dist/discord/token.txt` (git-ignored).
3. `node discord-setup/setup.mjs`
4. Paste `dist/discord/pitlane-config.yml` (webhook URLs — secrets) into
   the plugin's configuration (`!DriftFactoryConfiguration` in
   `extra_cfg.yml`; on Pitlane, the plugin's configuration) and restart the
   game server.

To change texts or channels, edit `content.mjs` and run it again.
