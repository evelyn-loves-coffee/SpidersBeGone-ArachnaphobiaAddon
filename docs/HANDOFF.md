# Handoff: v0.3.3 automatic nameplate covers only

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
addon folder, then restart. Existing supported preferences may be kept;
schema 4 purges the entire obsolete layout state, including late-loaded saves.
Recovery of the already affected native client requires partner validation.

## Current implementation

- v0.3.3 uses **`/sbg`** as its only slash-command prefix, including status,
  enable/disable, config, image selection, opacity and calibration. The older
  prefixes are no longer registered. All help and active guides use `/sbg`.

- Every cover belongs to an accessible native spider nameplate. It stays
  hidden until attached and is permanently mouse-disabled. No movement API,
  drag script, screen placement, screen measurement, layout save/restore,
  interactive cover mode or associated command remains.
- The 24-slot pool recycles only nameplate covers. Reverse ownership prevents
  a reused slot from being adopted by another unit. Rejected cleanup hides
  and quarantines a slot; ordinary API retries make it reusable later.
- `/sbg enable` enables/retries tracking; `/sbg disable` hides all covers
  and clears the death warning. Disabled state survives reloads. Tracking
  requires no targeting, mouseover or cursor queries.
- `/sbg config` explicitly opens an image picker. That editor accepts input;
  cover frames never do. The opacity slider spans 80-100% in 1% steps and
  applies immediately to existing covers and the checkerboard preview. Native
  no-argument slider callbacks query their own value; refresh guards prevent
  recursion. Percentage buttons are used if the client rejects Slider APIs.
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
and the obsolete color field. `opacity` is now a supported setting: it defaults
to 1, rounds to 1% steps and clamps to 0.8-1 on load, input and rendering.
The enabled preference, selected image, custom path, extra names and tracking
calibration are preserved. Migration
runs both at script load and the actual SavedVariables restore point.

Defaults: `trackScale=1.6`, `drop=0.5`, `nearThreshold=0` (off), `nearBoost=2.6`,
fallback `coverSize=96`. The drop was calibrated on the partner's Tirisfal
test round. Near-field boost uses accessible apparent plate width, not
unavailable creature distance. To calibrate it, debug on, approach a spider,
read the `SBG| near:` values and choose `/sbg near N`. Do not change the
sizing model without live measurements. Nameplate stacking/clamping can
still move a cover away from the body, and very close models can extend
beyond a cover. No UI-layer workaround for missing world projection is used.

## Files and offline verification

- `Cover.lua`: native-only pool, permanent click-through, no saved positions.
- `Core.lua`: controls, schema-4 cleanup, guarded scanning and lifecycle.
- `Appearance.lua` / `Config.lua`: image choices and explicit picker.
- `Access.lua` / `Units.lua`: readable public queries and spider recognition.
- `DeathWarning.lua`: bounded recent observations and brief centered notice.
- `tools/test_core.lua`: client stubs prohibit movement/screen reads and record
  mouse-enable history; regressions cover supported behavior, old-state cleanup,
  opacity bounds, alpha rendering and slider/button compatibility.

From the repository root:

```powershell
$env:UV_CACHE_DIR = Join-Path (Get-Location) '.test-cache'
$env:UV_LINK_MODE = 'copy'
uv run --offline --with lupa python tools/package_addon.py
git diff --check
```

The installable `SpidersBeGone-0.3.3-fixed.zip` is in the repository's parent
directory; logs and extracted-source checks are ignored under `dist/`.
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

The v0.3.2 slider, thumb rendering and focus release need live validation on
the partner's machine. Test both endpoints, reload at an intermediate value,
and confirm ground/camera controls still pass through live covers. Shipped
textures are validated opaque RGB and fade as one image layer; custom images
retain a backing and may look more opaque, never less opaque than the setting.
