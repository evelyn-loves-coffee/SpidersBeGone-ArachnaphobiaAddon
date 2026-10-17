# Arachnaphobia Shield — Arachnaphobia Addon

Addon for **World of Warcraft Forever** (classic 1.x-line client, v1.60.1) that
covers spider models with a nameplate-attached UI element. UI-layer only: no model
swaps, no game-file modification.

**Status: v0.4.6 — the prefilled custom field now parks the caret at the
end of the prefix, so the user literally only types the file name.**
v0.4.5 fixed the picker custom-path UX: the field prefills the required
`Interface\AddOns\ArachnaphobiaShield\Custom\` prefix, the hint line shows
the full path (no more clipped error), and the empty `Custom\` folder ships
in the release zip (contents stay git-ignored and un-packaged). Directory
enumeration is impossible on this client (the addon sandbox has no
filesystem API; WTF exposes only SavedVariables), so prefix + typed file
name is the convenience ceiling. v0.4.4 raised the close ceiling x2.6 →
x3.0 (legs at extreme close range); the 75-85 UI near ramp is validated
in-game (far `73*1.00`, close `91*3.00` flat). In-game debug capture
(2026-10-17) showed the client clamps far
nameplates at **73 UI** and grows them to ~90 on approach - both earlier
knees (30, then 60) sat *below* the client's minimum and boosted even far
plates (x2.14 at the 73 clamp). v0.4.3 moved the ramp to 75-85 UI so it
lives inside the client's actual range: far plates (<= ~74) are unboosted
and plate-proportional (the `/as near 1` far-shrink the owner wants kept),
the boost smoothsteps to the full ceiling by 85 - just below the measured
close band (87-113 UI), so the cover is constant at close range. v0.4.4
raises that ceiling from `x2.6` to `x3.0`: the plate width saturates at
~91, so the flat ceiling is the only lever that adds cover at extreme
close range, where the model's legs poked past the cover (owner, 2026-10-17).
v0.4.1 retired the `/as near` level: the boost is computed automatically
every 10 Hz tick from the nameplate's apparent width. Full history:
docs/NEAR-RAMP.md. v0.4.0 fixed the
blank `/as config` preview (the checker, backing and art now follow the
in-game cover's one-frame layout and show cycle) and simplifies tuning:
`/as grow` takes a percentage (`100` = default, allowed `80`–`120`), `/as
near` takes a level `0`–`3` (`0` off, `1` = closest only, `3` = from
farther), and the dead `/as size` command is retired (the plate-width
fallback it set never triggers on this client). v0.3.8 removed the
opacity control entirely: this client fades nameplates (and their children,
i.e. the covers) with distance no matter what the addon sets, so the setting
could never do what it promised. Covers are always fully opaque. The fox now
sits on a navy-toned **camouflage** squircle card instead of a flat navy one,
custom images must live under `Interface\AddOns\ArachnaphobiaShield\Custom\`
(legacy `MyCovers` paths fall back to the fox), and the release zip builds
into the git-ignored `dist/` folder instead of the repository's parent
directory. v0.3.7 replaces the flat preset fills with three-tone camouflage
patterns (domain-warped fractal noise plus grain) so a spider outline is
harder to trace through the client's distance fade, and places the fox on a
navy squircle card so its open areas are backing instead of holes. The fox,
camouflage backgrounds, custom images and brief corpse warning remain. Core
tracking was verified in game 2026-10-16 (Tirisfal); the build passes offline
checks.
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
[historical design](https://github.com/evelyn-loves-coffee/ArachnaphobiaShield/blob/main/docs/PLAN.md) / [client-probe records](https://github.com/evelyn-loves-coffee/ArachnaphobiaShield/blob/main/docs/API-VERIFICATION.md)
for the historical design and client-probe records.

## Install

Extract the fixed ZIP and replace the `ArachnaphobiaShield/` folder in your client's
`Interface/AddOns/` directory, then log in or `/reload`. The `.toc` must be at
`Interface/AddOns/ArachnaphobiaShield/ArachnaphobiaShield.toc`, without an extra nested
repository folder. `/as` should report **v0.4.3**.

Choose your cover with **`/as config`**. The default is the supplied fox
illustration on a navy-toned camouflage squircle card; alternatives are
camouflage red, blue, sage and charcoal squircles, or your own local image.
Choices update existing covers immediately and save automatically. Covers
are always fully opaque (v0.3.8 removed the opacity control: the client
fades them at distance regardless, so the setting could not do what it
promised). The preview updates immediately; artwork keeps its original
colors. See [the image guide](docs/COVER-IMAGES.md) for previews, commands
and custom-image preparation. Tracking stays click-through and requires no
mouseover; the 1.75-second corpse warning is unchanged.

Enable enemy nameplates in the game. The addon starts enabled on a new install;
`/as enable` also enables tracking immediately and retries paused coverage.
`/as disable` stops tracking and hides every cover.
No mouseover or separate auto command is needed. Tune coverage with `/as
grow 120` (up to `120%` of the nameplate) and `/as drop 0.5` as needed.

The cover follows the visible nameplate. Stacking or screen-edge clamping by
the game can move a nameplate away from the model; this client exposes no usable
world-to-screen projection to correct that independently. Exact model coverage
still needs an in-game check while moving, rotating the camera, and zooming.

**Near-field boost (automatic since v0.4.1):** the client holds nameplate
apparent size in a narrow band while the model keeps growing as the camera
approaches, so a plate-proportional cover under-covers close spiders (legs
showing). True camera distance is unmeasurable on this client (every
position API is absent), so the boost is not graded by distance: every
10 Hz tick multiplies the tracked size by a smooth ramp of the plate's
apparent width - none at/under 75 UI px, ramping up to the near-field
boost (`x3.0`) at/above 85 UI px. The client's apparent width only spans
~73 (far clamp) to ~90 (close) UI px (debug capture 2026-10-17), so the
ramp lives inside that real range: far plates stay unboosted and
plate-proportional, and the 85 knee sits just below the measured close
band (87–113 UI units, calibrated from 2026-10-16 screenshots at 1.205
px/UI), so the boost is constant across the whole band the client clamps
to. There is no setting to change it (`/as near` is retired); verify with
`/as debug on` and the `AS| near:` line (apparent width and computed factor
per plate).

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
`/as` reports `limited=true` when a checked value/frame is inaccessible,
and `paused=true` after repeated failures. `/as enable` explicitly retries
automatic covers. See [docs/TRACKING-ONLY.md](docs/TRACKING-ONLY.md) for controls
and upgrade behavior, and [the native attachment record](https://github.com/evelyn-loves-coffee/ArachnaphobiaShield/blob/main/docs/NATIVE-OVERLAYS.md) for
the native attachment implementation.

`/as disable` also dismisses the corpse warning and clears its observation
history. The timer and subsequent deaths cannot redisplay it while disabled.
`corpsePopup=unavailable` in diagnostics means the popup text API failed; a chat
warning is used instead so tracking can continue.

## NoSpider inspiration and Classic data

Arachnaphobia Shield is an independent **spiritual successor to the accessibility
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
| `/as` | diagnostics: version, build, enabled, tracking, covers shown, limited / paused |
| `/as config` | open the cover picker with preview, presets and custom-image path |
| `/as cover <choice>` | select `fox`, `red`, `blue`, `sage`, `charcoal`, or `custom <local .tga path>` |
| `/as enable` | enable tracking and retry paused coverage; enabled by default |
| `/as disable` | stop tracking and hide every cover; stays disabled after reload |
| `/as toggle` | switch between enabled tracking and disabled covers |
| `/as grow [N]` | cover size as a **percentage** of the nameplate width, whole number `80`–`120`, `100` = default |
| `/as drop [N]` | how far below the nameplate it sits (`0`–`4`, default `0.5` — calibrated in game 2026-10-16) |
| `/as name <name>` | "cover this one too": add an **exact** creature name (spaces allowed) |
| `/as names` | list the names you added |
| `/as forget <name>` | remove one you added |
| `/as debug [on\|off]` | verbose decisions for bug reports (off by default) |
| `/as help` | usage |

`/as on` and `/as off` remain compatibility aliases for enable/disable.

**Upgrade from before v0.3.1:** old screen-cover layouts and editing modes are deleted
for every character, including settings loaded late by the client. The
selected image, custom path, enabled preference and tracking calibration are
preserved; the retired opacity setting and legacy `MyCovers` custom paths are
dropped on load (such a selection falls back to the fox). Cover positions are
never saved; covers are rebuilt from live nameplates. The removed
layout/reset/opacity commands are no longer accepted.

**Primary in-game test machine:** the user's partner's computer
(`evelyn-loves-coffee`). This development checkout does not establish that
an update is installed or tested there. Because the reported cursor failure
survived `/reload`, fully exit the game on that machine before replacing the
addon folder and testing this upgrade. The previous input failure has not
been reproduced here, so recovery of an already affected client still needs
confirmation there.

### How a spider is recognised

1. **Creature ID** against a curated database (`ArachnaphobiaShield/SpiderDB.lua`,
   124 spider and spider-looking creature IDs compiled by the owner, with their
   home zones) — exact, and the only thing that catches names that give nothing
   away ("Moss Stalker", "Crypt Horror", "Krethis Shadowspinner") or the
   bug-model creatures the client files outside the Spider family.
2. **Creature family** `Spider` (id 3) — covers every spider that is not in the
   database.
3. **Name fragments** (`spider`, `weaver`, `widow`, `skitter`, `tarantula`, …,
   case-insensitive) — last resort for units that report neither.

Spotted a spider that none of the three caught? `/as name <exact name>` adds
it permanently (per character, saved in SavedVariables); `/as names` and
`/as forget <name>` manage the list. Extra fragments can be added in
`ArachnaphobiaShieldSettings.namePatterns` — those are *added to* the built-in set, never a
replacement.

Player units are excluded. The level window (`minLevel`/`maxLevel`) and
`requireHostile` still apply. Identification requires accessible unit data;
the addon does not infer hidden identities from another source.

## Custom cover images — setup and troubleshooting

The picker has **no file browser and shows no directory listing, by design**:
the addon never enumerates the game's filesystem. You type the exact path of
a TGA that already sits inside the game folder.

**1. Put the image in the addon's custom folder.** The `Custom\` folder
ships with the addon (empty); put a `.tga` file in it, e.g.
`Interface\AddOns\ArachnaphobiaShield\Custom\flower.tga`. A plain 24-bit TGA
always works; 32-bit RGBA TGA (with real transparency) works too. Square
images look best — the image is scaled into the square cover box without
cropping. The folder's *contents* are git-ignored and never packaged;
when updating the addon, extract the zip **over** the existing folder (or
re-copy your images) so your images survive.

On the partner's test machine the AddOns folder is
`.../World of Warcraft/_classic_beta_/Interface/AddOns/` (Wine prefix;
`/home/evelyn/Apps/wow/AddOns` is a symlink to it). Copy the image into a
subfolder of that directory.

**2. Point the addon at it**, either way:
- Picker: `/as config` → type the path in the *Custom image* field → click
  **Use image** (or press Enter). The preview shows the image on a checker
  before you commit; the status line confirms it.
- Command: `/as cover custom Interface\AddOns\ArachnaphobiaShield\Custom\flower.tga`

The path is **relative to the game root with backslashes** — no `C:` prefix.

**3. If it does not work**, match the symptom:

| Symptom | Cause / fix |
| :-- | :-- |
| Picker status: *“Image failed to load; showing the fox.”* | The client could not load the file. Check spelling, backslashes and that the file really is a TGA the client can decode. Test a known-good file first (e.g. `Interface\AddOns\ArachnaphobiaShield\cover.tga`). |
| Picker rejects the path with an error | The path must be under `Interface\AddOns\ArachnaphobiaShield\Custom\`, end with `.tga`, contain no `..`, no double backslashes, no control characters, and be ≤ 240 characters. |
| Preview looks right but the in-game cover shows the fox | The texture loaded in the picker but not at cover size/time. Retry after `/reload`; try a smaller 24-bit TGA. |
| Transparent parts of your image show as navy, not the world | Intentional: a navy backing is drawn behind custom images so the cover keeps its minimum coverage floor. Only the bundled presets (which carry real corner transparency) let the world through the corners. |
| Image is cropped / stretched | It is not cropped; non-square images get letterboxing inside the cover box. Use a square source. |

**Notes on the bundled presets (since v0.3.7, fox camo since v0.3.8):**
every preset (red, blue, sage, charcoal) is a 32-bit RGBA **camouflage
squircle**: three organic tones of its color plus fine grain, with
**transparent rounded corners** — the world shows through the corners only.
The fox cover is the fox **on a navy-toned camouflage squircle card**: the
open areas around the fox are solid camo backing, not transparency (v0.3.6
cut them to holes and the result read as too see-through). The camouflage
is deliberate: this client fades nameplates (and their children, i.e. the
covers) with distance, and that fade cannot be disabled from the addon; a
busy pattern makes a spider outline much harder to trace through the fade
than a flat fill, and covers are always fully opaque (v0.3.8 removed the
opacity control because it could not override the distance fade). If a
client ever refuses a 32-bit file, the affected cover degrades to the navy
backing (a plain square); a 24-bit fallback file can be shipped if that is
ever observed. The picker window itself uses file-based background
textures, so the config menu has a visible dark panel and button faces even
on clients that silently ignore numeric `SetTexture(r, g, b, a)`.

## Developer notes

- Target client: **World of Warcraft Forever 1.60.1** (interface **16001**,
  Lua 5.1, modern codebase with a reduced API set — see docs/PLAN.md §2).
- All in-client probe rounds and their results are in docs/PLAN.md §12.
- `tools/make_art.py` regenerates only the addon icon (stdlib only).
- `tools/make_backgrounds.py` regenerates the four camouflage squircles
  (32-bit RGBA, transparent corners; stable per-preset seeds, so the
  patterns are fixed art), the four 8×8 picker UI textures
  (`picker-bg/btn/btn-sel/field.tga`) and `cover-backdrop.tga` (the navy
  floor drawn under unverified custom art).
- `uv run --with pillow python tools/import_cover.py <local-image-path> --output <local-cover.tga>`
  converts a local image without uploading it; then run
  `uv run --with pillow python tools/make_cover_alpha.py` to cut the
  border-connected backing out of the result and place the art on the
  navy-toned camouflage squircle card. The script is a pure function of the
  original opaque import and refuses already-processed input (restore the
  import with `git show HEAD:ArachnaphobiaShield/cover.tga` before regenerating).
  `tools/render_config_preview.py` re-renders
  [docs/art/config_preview.png](docs/art/config_preview.png); see
  [COVER-IMAGES.md](docs/COVER-IMAGES.md).
- `tools/package_addon.py` writes the release zip into the git-ignored
  `dist/` folder (never into the repository's parent directory) and runs
  the offline Lua regression suite against the extracted files.
- Presets are data-driven in `Appearance.lua`; the picker is created only on request.
  Release packaging includes only explicitly listed bundled assets.

## License

MIT (code and original generated background presets). See [LICENSE](LICENSE).
The supplied fox artwork is included with the user's permission to publish it
with this addon; the code license does not grant a separate license to reuse
that artwork elsewhere.
