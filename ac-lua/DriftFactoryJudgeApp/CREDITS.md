# Credits

**Drift Factory Judge App** is a modified version of **DriftJudging SP** by
**DeadEndReece** (Copyright (C) 2026 DeadEndReece), used and modified under
the terms of the GNU Affero General Public License v3.0 plus the additional
attribution terms in [LICENSE.md](LICENSE.md).

This is **not** an official DriftJudging SP release, and DriftFactory is not
affiliated with or endorsed by DeadEndReece.

Original DriftJudging SP: https://www.patreon.com/DeadEndReece/posts/driftjudgesp-0-1-161016086

## What's different from the original DriftJudging SP

- Renamed to "Drift Factory Judge App" throughout the UI and manifest.
- Runs in online multiplayer sessions. The original refuses to operate
  online at all (`sim.isOnlineRace` disabled the whole app); this version
  keeps judging and layout editing working online. The one thing that
  genuinely can't work online is the automatic teleport-to-the-start-line
  convenience (CSP itself blocks moving your own car via script once
  connected to a multiplayer server) — online, the driver lines up at the
  start manually instead of being auto-placed there.
- Online, layouts come from an official, admin-published source (see
  README.md, "Official layouts") instead of each player's local file, and
  the editing tabs are restricted to the server admin.
- Shared session leaderboard between players online, Portuguese
  translation, and a redesigned score HUD.
- A server-delivered version (CSP online script) built from the same
  modules — see `online/README.md` at the repository root. Start and finish
  are now drawn on track for every player, not only in the editor's debug
  mode.
- Stricter run rules: besides a spin or no progress, a run is invalid on a
  jump start (moving during the countdown, instead of a 10-point penalty),
  driving the wrong way, straightening up after the drift has started,
  leaving the track with all four wheels, or stopping. Thresholds are in
  `src/defaults.lua` (`M.flow`).
- The score HUD uses the DriftFactory brand typefaces, bundled in `fonts/`:
  Saira (Copyright 2020 The Saira Project Authors, github.com/Omnibus-Type/Saira)
  and JetBrains Mono (Copyright 2020 The JetBrains Mono Project Authors,
  github.com/JetBrains/JetBrainsMono), both under the SIL Open Font License
  1.1 — see `fonts/OFL-Saira.txt` and `fonts/OFL-JetBrainsMono.txt`.
- (Further changes get listed here as they're made.)

## Known limitation carried over from this fork

Scoring is still computed entirely client-side, same as the original. On a
public server that means it's judged on trust, not validated — there's no
shared leaderboard yet and nothing stops a modified client from reporting a
fake score. A server-authoritative version (a CSP online script that
receives and validates each run, and broadcasts a real shared leaderboard)
is a separate, larger project, not part of this fork.
