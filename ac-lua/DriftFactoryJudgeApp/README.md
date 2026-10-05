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
