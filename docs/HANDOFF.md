# Handoff: v0.3.8 automatic nameplate covers only

**Primary in-game test machine: the user's partner's computer
(`evelyn-loves-coffee`).** This checkout is for development and packaging.
Do not describe a change as installed or tested on the partner's machine
without results from that machine. Core tracking was previously verified
there in Tirisfal; this removal of the input-taking cover system needs a new
live check. See [TRACKING-ONLY.md](TRACKING-ONLY.md) for the test sequence.

## Previous cursor incident and upgrade

The user reported that an old layout command spawned a screen cover on the
partner's client. Clicking it broke mouse control, including after `/reload`.
The failure was not reproduced here. The entire secondary cover/layout
system has now been removed, rather than leaving an optional input mode.
No native cursor reset, game-setting change or input workaround is attempted.

For upgrading an affected client, fully exit the game before replacing the
addon folder, then restart.

## Picker slider incident (v0.3.5)

With v0.3.2-v0.3.4 installed, loading into the game and clicking around left
the mouse cursor frozen in place. The only mouse-capture control in the addon
was the picker's native opacity Slider, which captures the mouse for dragging
and had never been live-validated. v0.3.5 removes the Slider entirely:
opacity is set with click-only 80/85/90/95/100% buttons, which hold no mouse
state. No mouseover, drag, movement or cursor-reset workaround is introduced.
The offline suite now records every requested frame kind and fails if a
Slider is ever created, and scans the cover and picker source for Slider,
movement, drag and screen-measurement APIs. A fully game exit is still
advised before replacing the folder. Existing supported preferences may be kept;
schema 4 purges the entire obsolete layout state, including late-loaded saves.
Recovery of the already affected native client requires partner validation.

## Picker backgrounds, preview and cover corners (v0.3.6)

The picker opened with **no visible window background**. Evidence: Spoken —
the only proven-working UI addon on this client — renders every visible
texture from a **string path**; the numeric `SetTexture(r, g, b, a)` form is
only documented as existing, and on this client it silently did nothing, so
the picker's solid colors (window, buttons, field) never appeared. v0.3.6
therefore ships the picker's solids as tiny 8×8 TGA files loaded via the
string-path form (`picker-bg/btn/btn-sel/field.tga`), and rebuilds the
preview as **three stacked single-texture frames** (checker, backing, art) —
one texture per frame is the layout every working frame already follows,
while the old three-textures-on-one-frame preview (which never showed the
fox) was unproven. New offline checks assert the string-path backgrounds
and the separate preview frames.

The bundled **fox and squircle presets now have transparent rounded
corners** (32-bit RGBA TGA; `make_backgrounds.py` emits alpha, and the new
`tools/make_cover_alpha.py` cuts the border-connected navy backing out of
the imported fox, idempotently, with a feathered edge). Charcoal remains a
fully opaque plain square. Packaging now accepts 24- or 32-bit cover
textures. If a client ever refuses the 32-bit files, the affected preset
degrades to its navy backing (plain square); no code path can crash on it.

A custom image still keeps a navy backing behind it (minimum coverage
floor), so transparency in *custom* art shows navy, not the world — only
the bundled presets let the world through the corners.

The in-game camera-drag cursor freeze (simple clicks fine; click+drag of the
camera freezes the in-game cursor; Alt-Tab out/back releases it) is
consistent with a **client/input-layer (Wine/Proton DInput) bug, not the
addon**: the addon creates no mouse-capture control since v0.3.5, never
touches the camera, and a camera drag happens over any region of the screen,
not just the picker. Decisive localizing test on the partner's machine:
with a spider covered, camera-drag *over the cover* and *elsewhere*; then
`/as disable` and drag the same spot with no cover. If the freeze follows
the drag regardless of addon state, it is the client; no addon-side mouse
fix is attempted (owner rule: remove the offending surface, don't patch
around input).

## Camouflage presets and the fox card (v0.3.7)

User feedback on v0.3.6: even at 100% opacity the covers read as
translucent because this client fades nameplates — and therefore their
children, the covers — with distance; that fade is a game property and
cannot be disabled from the addon. A flat fill then lets the spider's
outline trace through the fade, and the v0.3.6 corner cut left the fox
with too much open (transparent) area around the illustration.

v0.3.7 addresses both without touching rendering code (PaintCover is
unchanged; the covers are still one texture per frame at the chosen
opacity):

- **Every preset is a camouflage squircle.** `make_backgrounds.py` now
  generates three-tone camouflage (domain-warped fractal value noise,
  stable per-preset seeds — the patterns are fixed art, not random)
  inside the same supersampled squircle, so a busy pattern breaks up the
  outline instead of a uniform field. Red, blue, sage and charcoal all
  ship as 32-bit RGBA with transparent rounded corners.
- **The fox sits on a navy squircle card.** `make_cover_alpha.py` still
  cuts the border-connected backing out of the import, then composites the
  fox over a navy squircle of the same shape language as the presets:
  the open areas around the fox are solid backing, not holes, and only
  the rounded corners are transparent. The script is a pure function of
  the original opaque import and refuses already-processed input (the
  card would otherwise be baked in twice); regenerate from
  `git show HEAD:ArachnaphobiaShield/cover.tga`.
- **Packaging invariant:** 32-bit covers must have a transparent
  top-left corner and an opaque center, so a regression to opaque
  corners (or a missing card) fails the build.
- `tools/make_choices_preview.py` regenerates the bundled
  `docs/art/cover_choices.png` from the current TGAs.

Custom images are unchanged: a navy backing is still drawn behind them at
the configured opacity (minimum coverage floor).

## Opacity retired, fox camo card, strict custom path (v0.3.8)

The v0.3.7 camo presets already conceded the client's distance fade; v0.3.8
concludes from it that the opacity setting itself is fiction. A cover is a
child of the nameplate, and the client fades nameplates with distance no
matter what vertex alpha the addon sets, so 80% and 100% covers fade
identically: the control promised something the client will not allow. The
entire control is removed — picker buttons, saved value, `/as opacity`
command and clamping code — and covers are always fully opaque. `Normalize`
drops a legacy saved opacity on load; `/as opacity` is now an unknown
subcommand. The camouflage (and now the fox card) is the real mitigation:
a busy pattern hides the outline that the fade would otherwise reveal.

- **The fox sits on a navy-toned camouflage squircle card.**
  `make_cover_alpha.py` composites the cut fox over the same camo field as
  the presets (navy base, stable seed, same relative blotch scale via the
  size-normalized field) inside the squircle; the open areas around the fox
  are camo backing, and only the rounded corners are transparent. The
  32-bit packaging invariant (transparent corner, opaque center) is
  unchanged and still enforced.
- **The custom-image path is strict and AS-associated.** Custom textures
  must live under `Interface\AddOns\ArachnaphobiaShield\Custom\` (git-ignored,
  never packaged). The old "anywhere under `Interface\AddOns\`" validation
  is gone, and legacy `MyCovers` selections fall back to the fox on load.
- **The navy backing is a string-path texture.** The numeric
  `SetTexture(r, g, b, a)` is a silent no-op on this client (same evidence
  as the picker solids), so the custom-art floor ships as
  `cover-backdrop.tga` (8×8 TGA from `make_backgrounds.py`); `PaintCover`
  loads it by path and hides it with vertex alpha for bundled presets.
- **Build output moves into `dist/`.** `package_addon.py` writes
  `ArachnaphobiaShield-<version>-fixed.zip` into the git-ignored `dist/` folder
  instead of the repository's parent directory; no zip may be left in
  `~/Apps`.
- `tools/render_config_preview.py` renders `docs/art/config_preview.png`
  from the actual assets (640×480 picker, no opacity section).

## Current implementation

- v0.3.3 uses **`/as`** as its only slash-command prefix, including status,
  enable/disable, config, image selection and calibration. The older
  prefixes are no longer registered. All help and active guides use `/as`.

- Every cover belongs to an accessible native spider nameplate. It stays
  hidden until attached and is permanently mouse-disabled. No movement API,
  drag script, screen placement, screen measurement, layout save/restore,
  interactive cover mode or associated command remains.
- The 24-slot pool recycles only nameplate covers. Reverse ownership prevents
  a reused slot from being adopted by another unit. Rejected cleanup hides
  and quarantines a slot; ordinary API retries make it reusable later.
- `/as enable` enables/retries tracking; `/as disable` hides all covers
  and clears the death warning. Disabled state survives reloads. Tracking
  requires no targeting, mouseover or cursor queries.
- `/as config` explicitly opens an image picker. That editor accepts input;
  cover frames never do. Covers are always fully opaque (v0.3.8 removed the
  opacity control: the client fades nameplate children at distance
  regardless of vertex alpha); the picker still creates no Slider frame
  (v0.3.5: a Slider captures the mouse for dragging and froze the cursor in
  game). A button applies immediately to existing covers and the
  checkerboard preview.
  Fox, muted red/blue/sage and plain charcoal remain,
  along with local custom TGA textures. Choices save and apply immediately.
  See [COVER-IMAGES.md](COVER-IMAGES.md). Command selection remains available
  if the client rejects window APIs. Close releases edit-box focus.
- The user authorized publishing the fox with the addon on 2026-10-16.
  Other supplied images still require permission before publication.
- The look-away popup remains centered, click-through and 1.75 seconds long.
  It observes readable known spider deaths; no continued corpse cover is
  possible after the nameplate disappears. See [CORPSE-HANDLING.md](CORPSE-HANDLING.md).
- Secret identities/geometry and forbidden frames are skipped. No alternate
  position or identity channel bypasses restrictions. Repeated failures pause
  tracking; enable explicitly retries.

## Settings and calibration

Schema 4 deletes `covers`, `parkCount`, `arrange`, `autoTrack`, `stickyCovers`
and the obsolete color field; schema 5 (v0.4.1) additionally deletes the
retired `nearThreshold`. `opacity` (added in v0.3.2) is retired in
v0.3.8 and dropped on load, because the client's distance fade makes it a
no-op in practice; the enabled preference, selected image, custom path,
extra names and tracking calibration are preserved, and legacy
`MyCovers` custom paths fall back to the fox. Migration
runs both at script load and the actual SavedVariables restore point.

Defaults: `trackScale=1.0`, `drop=0.5`, `nearBoost=2.6`,
fallback `coverSize=96`. The drop was calibrated on the partner's Tirisfal
test round. The near-field boost (automatic since v0.4.1) uses accessible
apparent plate width, not unavailable creature distance: a smooth ramp on
apparent width (none at/under 75 UI px, full `nearBoost` at/above 85 UI px,
flat across the measured 87–113 UI close band). The client's apparent-width
range is only ~73 (far clamp) to ~90 (close) UI px (debug capture
2026-10-17), so v0.4.3 moved the ramp inside that real range - earlier
knees (30, then 60) sat below the 73 clamp and boosted even far plates
×2.14 (owner: far covers "unnecessarily large"). Far plates (≤ ~74) are now
unboosted and plate-proportional, keeping the `/as near 1` far-shrink
behavior (issue, options table and full fix history:
[NEAR-RAMP.md](NEAR-RAMP.md), closed in v0.4.3). Debug on, approach a
spider, and read the `AS| near:` line (apparent width and computed factor)
to verify. Do not change the sizing model without live measurements. Nameplate stacking/clamping can still move a cover away from
the body, and very close models can extend beyond a cover. No UI-layer
workaround for missing world projection is used.

## Files and offline verification

- `Cover.lua`: native-only pool, permanent click-through, no saved positions.
- `Core.lua`: controls, schema-4 cleanup, guarded scanning and lifecycle.
- `Appearance.lua` / `Config.lua`: image choices and explicit picker.
- `Access.lua` / `Units.lua`: readable public queries and spider recognition.
- `DeathWarning.lua`: bounded recent observations and brief centered notice.
- `tools/test_core.lua`: client stubs prohibit movement/screen reads and record
  mouse-enable history; regressions cover supported behavior, old-state cleanup,
  fixed opacity (no control, no saved value, no command), the strict
  `ArachnaphobiaShield\Custom\` path, the string-path backdrop and the three
  separate preview frames.
- `tools/make_backgrounds.py`: regenerates the four camouflage presets
  (transparent-corner 32-bit RGBA), the four 8×8 picker UI textures and
  `cover-backdrop.tga`. `tools/make_cover_alpha.py`: cuts border-connected
  backing out of the imported fox cover and places it on the navy-toned camo
  squircle card (feathered edge, writes 32-bit RGBA).

From the repository root:

```powershell
$env:UV_CACHE_DIR = Join-Path (Get-Location) '.test-cache'
$env:UV_LINK_MODE = 'copy'
uv run --offline --with lupa python tools/package_addon.py
git diff --check
```

The installable `ArachnaphobiaShield-0.3.8-fixed.zip` is built into the
git-ignored `dist/` directory (v0.3.8 moved it out of the repository's
parent directory); logs and extracted-source checks live there too.
Packaging includes only current guides and an explicit list of approved
artwork. Historical design/probe documents remain in Git for reference;
they are not shipped and must not be used to reintroduce retired features.

## Data sources

Forever uses Vanilla Classic as its baseline. The curated Classic spider
database remains; no TBC zones or spawn dataset is bundled. LibTourist Classic
Era is the selected MIT source if general area metadata becomes necessary.
Questie data is excluded. NoSpider is credited inspiration; none of its code,
artwork or data was copied. Wowhead-derived bulk spawn data is excluded.
See [DATA-SOURCES.md](DATA-SOURCES.md).

The v0.3.8 picker and textures need live validation on the partner's
machine, on top of the v0.3.5 checks (open/close, presets, cursor never
freezes, camera controls pass through live covers):

1. The config window shows a **visible dark panel** with visible button
   faces (the string-path background textures render), and no opacity
   section.
2. The preview shows the **fox on its camo card over a checker**; the
   checker is visible in the **corners** of the fox (corner
   transparency), and the same for the red, blue and sage squircles.
3. In game, the world shows through the rounded corners of the covers, and
   every cover is fully opaque.
4. A custom image under `ArachnaphobiaShield\Custom\` still previews and applies,
   with its navy backing; a legacy `MyCovers` path in an old save falls
   back to the fox.

If a 32-bit TGA is ever refused by the client, the symptom is one preset
rendering as a plain navy square (its backing) — report it; a 24-bit
fallback file can be shipped. Shipped textures are validated 24- or 32-bit
uncompressed TGA and fade as one image layer; custom images retain a
backing and may look more opaque, never less opaque than the setting.
