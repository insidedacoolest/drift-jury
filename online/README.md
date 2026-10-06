# Drift Factory Judge App — server-delivered version

The same judge as the installed app, delivered by the server as a CSP online
script: players join and have it, nothing to install.

- `main.lua` — entry point (window, HUD, 3D markers, run updates).
- `build.lua` — bundles `main.lua` and the app's modules from
  `ac-lua/DriftFactoryJudgeApp/src` into one file, since CSP loads an online
  script from a single URL.
- `driftfactory.lua` — the generated bundle the server points at. Don't edit
  it by hand; rebuild it.
- `fonts.zip` — the brand fonts (Saira, JetBrains Mono) with their SIL OFL
  licenses. The script asks CSP to download and cache it; if that fails the
  HUD uses CSP's default font.

## Rebuilding

From the repository root, after changing `main.lua` or anything in
`ac-lua/DriftFactoryJudgeApp/src`:

```
lua online/build.lua
```

Then commit `online/driftfactory.lua` and push to `master`. Players get the
new version the next time they join.

## Server configuration

In the server's CSP extra options (`csp_extra_options.ini`; on Pitlane
Hosting, the server's "CSP Extras" section):

```ini
[SCRIPT_DRIFTFACTORY]
SCRIPT = 'https://raw.githubusercontent.com/insidedacoolest/drift-jury/master/online/driftfactory.lua'
REQUIRED = 1
```

`REQUIRED = 1` only lets in players whose CSP loaded the script. AssettoServer
also needs "CSP client messages" (`EnableClientMessages`) on for the shared
leaderboard.

## Differences from the installed app

- The main window opens from the online extras menu in CSP's chat app
  (lightbulb icon) instead of the apps taskbar.
- The score HUD is drawn at the bottom center of the screen.
- Online scripts can't write files, so personal results are kept in CSP's
  own per-player storage (`ac.storage`) instead of JSON files.
- No layout editor, calibration or car setup — those need to save layouts,
  so they stay in the installed app (offline). Layouts reach players through
  the official layouts in `layouts/`.
- A player who also has the installed app gets a note in its window and the
  installed copy stays idle on that server, so runs aren't judged twice.
