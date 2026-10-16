# Spiders Be Gone — Arachnaphobia Addon

Addon for **World of Warcraft Forever** (classic 1.x-line client, v1.60.1) that
covers spider models with a nameplate-attached UI element. UI-layer only: no model
swaps, no game-file modification.

**Status: v0.3.1 — core tracking verified in game 2026-10-16 (Tirisfal);
only automatic nameplate covers remain. The fox, background presets, custom
images and brief corpse warning are retained. The new build passes offline
checks; live validation belongs on the partner's test machine.**
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
Covers are **always click-through**: you can run, click and target straight
through them. They have no input mode, movement handlers or saved positions.
Only the image picker accepts input when you explicitly open it.

See [docs/HANDOFF.md](docs/HANDOFF.md) to resume from a fresh session,
[docs/TRACKING-ONLY.md](docs/TRACKING-ONLY.md) for current controls, and
[historical design](https://github.com/evelyn-loves-coffee/SpidersBeGone-ArachnaphobiaAddon/blob/main/docs/PLAN.md) / [client-probe records](https://github.com/evelyn-loves-coffee/SpidersBeGone-ArachnaphobiaAddon/blob/main/docs/API-VERIFICATION.md)
for the historical design and client-probe records.

## Install

Extract the fixed ZIP and replace the `SpidersBeGone/` folder in your client's
`Interface/AddOns/` directory, then log in or `/reload`. The `.toc` must be at
`Interface/AddOns/SpidersBeGone/SpidersBeGone.toc`, without an extra nested
repository folder. `/spider` should report **v0.3.1**.

Choose your cover with **`/spider config`**. The default is the supplied fox
illustration; alternatives are muted red, blue and sage squircles, plain
charcoal, or your own local image. Choices update existing covers immediately
and save automatically. Every cover has an opaque backing and preserves its
original colors. See [the image guide](docs/COVER-IMAGES.md) for previews, commands
and custom-image preparation. Tracking stays click-through and requires no
mouseover; the 1.75-second corpse warning is unchanged.

Enable enemy nameplates in the game. The addon starts enabled on a new install;
`/spider enable` also enables tracking immediately and retries paused coverage.
`/spider disable` stops tracking and hides every cover.
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

Covers also disappear when the game removes a dead unit's nameplate. When
the addon observes an accessible spider death, a click-through **LOOK AWAY**
warning appears in the center of the screen for **1.75 seconds**, without
targeting or mouseover. It warns that the corpse may be visible; it does not
cover or track the body. Deaths not observed through accessible unit data or
a recent readable death event can be missed. NoSpider uses a mouseover warning
for this case; see [docs/CORPSE-HANDLING.md](docs/CORPSE-HANDLING.md) for our
automatic implementation and its limits.
`/spider` reports `limited=true` when a checked value/frame is inaccessible,
and `paused=true` after repeated failures. `/spider enable` explicitly retries
automatic covers. See [docs/TRACKING-ONLY.md](docs/TRACKING-ONLY.md) for controls
and upgrade behavior, and [the native attachment record](https://github.com/evelyn-loves-coffee/SpidersBeGone-ArachnaphobiaAddon/blob/main/docs/NATIVE-OVERLAYS.md) for
the native attachment implementation.

`/spider disable` also dismisses the corpse warning and clears its observation
history. The timer and subsequent deaths cannot redisplay it while disabled.
`corpsePopup=unavailable` in diagnostics means the popup text API failed; a chat
warning is used instead so tracking can continue.

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
| `/spider` | diagnostics: version, build, enabled, tracking, covers shown, limited / paused |
| `/spider config` | open the cover picker with preview, presets and custom-image path |
| `/spider cover <choice>` | select `fox`, `red`, `blue`, `sage`, `charcoal`, or `custom <local .tga path>` |
| `/spider enable` | enable tracking and retry paused coverage; enabled by default |
| `/spider disable` | stop tracking and hide every cover; stays disabled after reload |
| `/spider toggle` | switch between enabled tracking and disabled covers |
| `/spider grow [N]` | how much bigger than the nameplate a cover is (`0.2`–`6`, default `1.6`) |
| `/spider drop [N]` | how far below the nameplate it sits (`0`–`4`, default `0.5` — calibrated in game 2026-10-16) |
| `/spider near [N]` | near-field boost: plate apparent width (`UI` px) at/above which the tracked cover gets the ×`2.6` boost (`0`–`1000`, default `0` = off) |
| `/spider size [N]` | fallback cover size in UI units (`16`–`512`) when plate geometry is unavailable |
| `/spider name <name>` | "cover this one too": add an **exact** creature name (spaces allowed) |
| `/spider names` | list the names you added |
| `/spider forget <name>` | remove one you added |
| `/spider debug [on\|off]` | verbose decisions for bug reports (off by default) |
| `/spider help` | usage |

`/spider on` and `/spider off` remain compatibility aliases for enable/disable.

**Upgrade to v0.3.1:** old screen-cover layouts and editing modes are deleted
for every character, including settings loaded late by the client. The
selected image, custom path, enabled preference and tracking calibration are
preserved. Cover positions are never saved; covers are rebuilt from live
nameplates. The removed layout/reset commands are no longer accepted.

**Primary in-game test machine:** the user's partner's computer
(`evelyn-loves-coffee`). This development checkout does not establish that
an update is installed or tested there. Because the reported cursor failure
survived `/reload`, fully exit the game on that machine before replacing the
addon folder and testing this upgrade. The previous input failure has not
been reproduced here, so recovery of an already affected client still needs
confirmation there.

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
- `tools/make_art.py` regenerates only the addon icon (stdlib only).
- `tools/make_backgrounds.py` regenerates the four original simple backgrounds.
- `uv run --with pillow python tools/import_cover.py <local-image-path> --output <local-cover.tga>`
  converts a local image without uploading it; see [COVER-IMAGES.md](docs/COVER-IMAGES.md).
- Presets are data-driven in `Appearance.lua`; the picker is created only on request.
  Release packaging includes only explicitly listed bundled assets.

## License

MIT (code and original generated background presets). See [LICENSE](LICENSE).
The supplied fox artwork is included with the user's permission to publish it
with this addon; the code license does not grant a separate license to reuse
that artwork elsewhere.
