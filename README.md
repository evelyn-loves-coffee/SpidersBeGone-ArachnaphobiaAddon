# Spiders Be Gone — Arachnaphobia Addon

Addon for **World of Warcraft Forever** (classic 1.x-line client, v1.60.1) that
covers spider models with a nameplate-attached UI element. UI-layer only: no model
swaps, no game-file modification.

**Status: v0.2.7 tracking only — tracking in-game verified 2026-10-16 (Tirisfal);
`drop` default calibrated in the same round; near-field boost added for
spiders that are close enough to outgrow the plate-sized cover.**
Tracked covers are now **children of the spider's nameplate**, so native
movement and scale apply to the cover and its offset between polling ticks.
The public unit-to-nameplate mapper is preferred; a metadata fallback requires
an exact unit match. Forbidden frames and secret values are skipped. Rejected
cleanup defers reuse of that frame, and repeated errors pause automatic covers
instead of switching detection modes. Tracking is enabled by default and never
requires targeting or mouseover. Cursor detection and sticky covers are removed.

**Safety boundary (owner rule).** This addon draws its own overlay frames and
reads public unit information. It never modifies unit models, names, combat
behaviour, game files, or the client's own frames, and it does not use taint
workarounds. The addon never reads a plate's screen coordinates. Attachment is
used only when the client accepts it. Optional width/scale readings are checked
for accessibility; unavailable readings fall back to configured dimensions.
Covers are **click-through**: you
can run, click and target straight through them (`/spider arrange` is the only
mode that takes the mouse, for lining shields up).

See [docs/HANDOFF.md](docs/HANDOFF.md) to resume from a fresh session,
[docs/TRACKING-ONLY.md](docs/TRACKING-ONLY.md) for current controls, and
[docs/PLAN.md](docs/PLAN.md) / [docs/API-VERIFICATION.md](docs/API-VERIFICATION.md)
for the historical design and client-probe records.

## Install

Extract the fixed ZIP and replace the `SpidersBeGone/` folder in your client's
`Interface/AddOns/` directory, then log in or `/reload`. The `.toc` must be at
`Interface/AddOns/SpidersBeGone/SpidersBeGone.toc`, without an extra nested
repository folder. `/spider` should report **v0.2.7**.

Enable enemy nameplates in the game. The addon starts enabled on a new install;
`/spider enable` also enables tracking immediately and retries paused coverage.
`/spider disable` stops tracking and hides every cover, including manual shields.
No mouseover or separate auto command is needed. Tune coverage with `/spider grow 2`
and `/spider drop 0.5` as needed.

The cover follows the visible nameplate. Stacking or screen-edge clamping by
the game can move a nameplate away from the model; this client exposes no usable
world-to-screen projection to correct that independently. Exact model coverage
still needs an in-game check while moving, rotating the camera, and zooming.

**Near-field boost:** the client holds nameplate apparent size in a narrow
band while the model keeps growing as the camera approaches, so a
plate-proportional cover under-covers close spiders (legs showing). True
camera distance is unmeasurable on this client (every position API is
absent), so the boost is not graded by distance: when a plate's apparent
width reaches `/spider near`'s threshold, its cover is multiplied by the
near-field boost (default `2.6`). Calibrate once: `/spider debug on`, walk
from far to close at a spider, read the `SBG| near:` line, then
`/spider near <N>` (default `0` = off).

**Known limitation:** when the camera is very close, the client clamps the
nameplate itself (edge/stacking), the cover follows the plate, and no
UI-layer addon can reposition the plate on this client.
`/spider` reports `limited=true` when a checked value/frame is inaccessible,
and `paused=true` after repeated failures. `/spider enable` explicitly retries
automatic covers. See [docs/TRACKING-ONLY.md](docs/TRACKING-ONLY.md) for controls
and upgrade behavior, and [docs/NATIVE-OVERLAYS.md](docs/NATIVE-OVERLAYS.md) for
the native attachment implementation.

## NoSpider inspiration and Classic data

Spiders Be Gone is an independent **spiritual successor to the accessibility
approach** of [NoSpider - Arachnophobia Mode](https://www.curseforge.com/wow/addons/nospider-arachnophobia-mode)
by **GrasHopper42**, whose author lists the project under the
[MIT License](https://www.curseforge.com/wow/addons/nospider-arachnophobia-mode/license).
Its native parent-and-anchor overlay approach informed this Forever
implementation. NoSpider code, artwork, bundled libraries, zone tables, and
spawn coordinates have not been copied into this addon.

**A zone/sub-zone database is not required for nameplate overlays.** The
nameplate supplies native positioning. Static zone or spawn data can support
optional historical-area warnings; it cannot locate a restricted creature or
bypass missing identity/position access. Zone membership never gates our covers.

The bundled creature database is a **Classic Azeroth baseline** with 124
owner-curated IDs. It includes original Classic dungeons and raids. The
TBC-introduced Tcha'kaz entry was removed even though its location is a Classic
zone. No expansion zone/sub-zone tables or spawn datasets are bundled.
Forever uses Vanilla Classic as its content baseline. Accessible family/name
matching also supports creatures absent from the curated ID list; the list
is not a claim of a completely verified Forever bestiary.

**LibTourist Classic Era (MIT)** is the selected external source if general
area metadata becomes necessary. Questie/QuestieDB data is excluded.
LibTourist has no spider NPC/spawn database; NoSpider's curated spider-area
records are being assessed as a complementary source after Classic filtering
and source review. None of its data has been imported.
Its Wowhead-derived bulk spawn table is excluded because the published
Wowhead terms do not provide the required redistribution permission.
No geography library is bundled for the current nameplate covers. The source
review and Classic filtering rules are in [docs/DATA-SOURCES.md](docs/DATA-SOURCES.md).

## Slash command

| Command | Effect |
| :-- | :-- |
| `/spider` | diagnostics: version, build, enabled, tracking, covers shown / saved, limited / paused |
| `/spider enable` | enable tracking and retry paused coverage; enabled by default |
| `/spider disable` | stop tracking and hide every cover; stays disabled after reload |
| `/spider toggle` | switch between enabled tracking and disabled covers |
| `/spider release` | release tracked covers; they return on the next scan if enabled; keeps manual shields |
| `/spider clear` | remove all covers and forget this character's saved layout |
| `/spider parks N` | set the number of pre-parked shields (`0` removes them) |
| `/spider arrange [on\|off]` | drag mode: covers take the mouse so you can move them; never survives a relog |
| `/spider grow [N]` | how much bigger than the nameplate a cover is (`0.2`–`6`, default `1.6`) |
| `/spider drop [N]` | how far below the nameplate it sits (`0`–`4`, default `0.5` — calibrated in game 2026-10-16) |
| `/spider near [N]` | near-field boost: plate apparent width (`UI` px) at/above which the tracked cover gets the ×`2.6` boost (`0`–`1000`, default `0` = off) |
| `/spider size [N]` | fixed cover size in UI units (`16`–`512`) for manual shields and unavailable-geometry fallback |
| `/spider name <name>` | "cover this one too": add an **exact** creature name (spaces allowed) |
| `/spider names` | list the names you added |
| `/spider forget <name>` | remove one you added |
| `/spider debug [on\|off]` | verbose decisions for bug reports (off by default) |
| `/spider help` | usage |

`/spider on` and `/spider off` remain compatibility aliases for enable/disable.
The old `/spider auto` command is retired and only prints migration guidance.

**What is remembered per character:** explicitly parked manual shields and
their sizes. New installs start with zero manual shields; existing configured
manual shields are preserved. Tracked covers are rebuilt from live nameplates.
Upgrades remove old cursor-generated covers and mode settings, including
`autoTrack=false`, while preserving the overall enabled/disabled preference.
Manual covers stay hidden while disabled, including after reload. Nothing can
be dragged off-screen.

### How a spider is recognised

1. **Creature ID** against a curated database (`SpidersBeGone/SpiderDB.lua`,
   124 spider and spider-looking creature IDs compiled by the owner, with their
   home zones) — exact, and the only thing that catches names that give nothing
   away ("Moss Stalker", "Crypt Horror", "Krethis Shadowspinner") or the
   bug-model creatures the client files outside the Spider family.
2. **Creature family** `Spider` (id 3) — covers every spider that is not in the
   database.
3. **Name fragments** (`spider`, `weaver`, `widow`, `skitter`, `tarantula`, …,
   case-insensitive) — last resort for units that report neither.

Spotted a spider that none of the three caught? `/spider name <exact name>` adds
it permanently (per character, saved in SavedVariables); `/spider names` and
`/spider forget <name>` manage the list. Extra fragments can be added in
`SBeGoneSettings.namePatterns` — those are *added to* the built-in set, never a
replacement.

Player units are excluded. The level window (`minLevel`/`maxLevel`) and
`requireHostile` still apply. Identification requires accessible unit data;
the addon does not infer hidden identities from another source.

## Developer notes

- Target client: **World of Warcraft Forever 1.60.1** (interface **16001**,
  Lua 5.1, modern codebase with a reduced API set — see docs/PLAN.md §2).
- All in-client probe rounds and their results are in docs/PLAN.md §12.
- Art is generated by `tools/make_art.py` (stdlib only); rerun to regenerate
  `SpidersBeGone/icon.tga` and `SpidersBeGone/cover.tga`.

## License

MIT (code). See [LICENSE](LICENSE).
