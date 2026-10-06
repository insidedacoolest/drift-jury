# Drift Factory Judge App

Custom Shaders Patch Lua app for Assetto Corsa drift judging, on- or offline.

A modified version of DriftJudging SP by DeadEndReece — see
[CREDITS.md](CREDITS.md) for what changed and where it comes from.

## License

Licensed under the GNU Affero General Public License, version 3 or later,
with additional attribution and origin terms carried over from the original
project. The full license is in [LICENSE.md](LICENSE.md).

Do not remove the copyright/license notices or claim the original project as
your own. Modified versions must be clearly marked as modified.

## What's different from upstream DriftJudging SP

Runs in online multiplayer sessions, not just offline driving. The one thing
that doesn't work online is auto-align-to-start-line (CSP blocks moving your
own car via script once connected to a server) — online, drive to the start
circle yourself before pressing the horn; everything else (judging, editor,
results) works the same as offline. Details in [CREDITS.md](CREDITS.md).

## Official layouts (online)

Online, the app never uses a player's own locally edited layout. It downloads
the official layout for the current track from this repository —
`layouts/<track>/<layout>.json`, served from
`raw.githubusercontent.com/insidedacoolest/drift-jury/master/` — so everyone
on a server is judged against the same layout and scoring targets. No server
configuration is needed.

- The last successful download is cached locally and used if GitHub can't be
  reached.
- A download that finishes mid-run is applied once the run ends.
- A track with no published layout shows "Ainda não há layout para esta
  pista" and can't be run online.
- Online, only the server admin sees the editing tabs (Editor de Layout,
  Configuração do Carro, Calibração). Offline everything stays open, for
  preparing tracks.

**Publishing a track:** prepare it offline in the Layout Editor and press
`Guardar Layout`. That writes
`Documents/Assetto Corsa/cfg/extension/state/lua/app/DriftFactoryJudgeApp/layouts/<track>/<layout>.json`;
copy that file unchanged to `layouts/<track>/<layout>.json` at the root of
this repository and push to `master`. Players pick it up the next time they
load into that track (GitHub's raw CDN can take a few minutes to refresh).

## Server-delivered version

The same judge can be delivered by the server itself as a CSP online script,
so players don't install anything — see `online/README.md` at the repository
root. On a server that does this, this installed copy stays idle and tells
the player to use the server's version instead.

## NOTES:
Sometimes right clicking a node will glitch the camera out, to get the best results make sure you are directly on top of it and then delete it.
Sometimes Recorded road paths will "Float", I think its a map mesh issue but you can just go back at a different angle to adjust it to the position.


## Workflow
(Enable Debug Mode)
1. Open the `Layout Editor` tab.
2. Load into your map and go to your Start position and click `Capture Lead Start`
3. Record or edit a route with at least two points.
4. Enable `Draw/Edit Outer` (Instructions are displayed to you in the UI)
5. Click `Finish Draft` after you have completed your outer zone (Repeat for the rest of the outer zones)
6. Click "Place/Remove Clips", Select the size you want the clip to be and CTRL + CLICK to place your clip.
7. Perfect the layouts zones and paths for better results.
8. Save the layout, export to share with friends.
9. Enter the start circle and press the horn to begin a solo run — online, drive there yourself first.

Import and export use file dialogs, while the working library is stored in the
CSP app `ScriptConfig` directory. If no personal layout exists, the app can load a
bundled starter layout from `bundled-layouts/<track>/<layout>.json`; saving
copies it into the player's own `ScriptConfig` layout library. Exports clean
layout JSON and removes server-only fields such as lineup spots.

Results are private to the local player and stored separately per track,
layout, and exact car model. Each file retains a permanent valid PB and the
latest 50 completed valid or invalid runs.

## Scoring

Qualifying scoring of the Drift Masters judging rules 2026 (sections 1.6–1.8),
up to 100 points:

- **Line — 60**: every outer zone and inner clip is worth an equal share
  (rear wheels inside the zone, front bumper at the clip); a missed one scores
  0. Leaving the drawn route ("off line") weighs 10% of the line.
- **Angle — 20**: high angle achieved and held in the judged sections;
  nothing up to 20°, full marks from 55°.
- **Style — 20**:
  - **Initiation 5**: early (drift established within 12 m after the start
    zone, nothing after 40 m), rate to angle (meters to 80% of the target
    angle) and smooth (no angle given back). A double initiation halves it.
  - **Fluidity 10**: car settled (few abrupt steering, throttle and angle
    corrections) and, where the course has them, quick lock-to-lock
    transitions (high angle to high angle).
  - **Commitment 5**: pace (full at 90 km/h), keeping it (no big speed
    drops) and consistent throttle.
  Fluidity and commitment only count while actually drifting (15°→30°).

**Deductions**: a wall or car contact −2, −5 (lost 5 km/h or more) or −10
(lost 15 km/h or more); one or two wheels off track −2; a short
straightening (correction, angle under 5° for 0.4 s) −3. A scrape or a
continuous mistake counts once. Deductions never void a run.

**Incomplete run** (0 points): spinning out, stop drifting (straight for
1.5 s), three wheels off track, plus a jump start, driving the wrong way,
stopping, no progress for 4 s or going over 90 s.

**Ties** on the server leaderboard follow the Drift Masters tie breaker:
best score, second-best score, then the best run's line, angle and style.

Not judged in-game: the accel/decel map, opposite drift per section, hood
or doors opening, and "unchaseable" runs.

## Editor Controls

- Route tool: drag points to move, `Shift`+drag to smooth nearby route nodes,
  `Ctrl`+click a segment to insert, and right-click a point to remove.
- Outer-zone tool: `Ctrl`+click to add draft points or insert on an existing
  edge, drag points to move, and right-click to remove.
- Clip tool: `Ctrl`+click to place and right-click to remove.
- Editor visibility can hide committed outer zones and inner clips from the
  local editor view and selection tools without changing scoring or saved data.
- All geometry updates locally in the same frame. Disk writes only occur when
  `Save Layout` is selected.

## Calibration

Calibration requires five valid runs and uses the best three to recommend
target speed, target angle, minimum angle, and style angles. Applying a
recommendation can update the detected pack profile, such as `VDC_*` or
`SWARM_*`, or the exact current-car profile. Exact car profiles override pack
profiles only for values they set; unset values inherit from the pack. The
layout must still be saved explicitly. Unsaved override changes apply to the
current app session immediately, but they are lost on reload until `Save Layout`
is pressed.

## Known limitation

Scoring is computed entirely client-side — fine for a community having fun
together, but there's no shared leaderboard yet and nothing stops a modified
client from reporting a fake score. A server-authoritative version is a
separate, larger project (see the parent `drift-jury/` blueprint's Phase 3).
