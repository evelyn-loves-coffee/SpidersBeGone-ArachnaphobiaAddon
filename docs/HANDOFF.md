# Handoff: v0.3.0 cover picker, tracking and automatic corpse warning

Current implementation and controls are in [TRACKING-ONLY.md](TRACKING-ONLY.md)
(v0.2.6 snapshot; v0.2.7 added the near-field boost, and v0.2.8 adds the
corpse warning; v0.3.0 adds cover selection and approved fox artwork). The
packaged Lua 5.1 suite passes offline. Core tracking was in-game verified
2026-10-16 (below); the remaining live checks are the tracking-only
enable/disable path, migration of a real pre-schema-3 save, calibrating
the near-field threshold, and native rendering/input for the new picker.

After pulling `2777b0d` and integrating `75571b9`, added the centered LOOK AWAY popup for
observed spider deaths. It is click-through and expires after 1.75 seconds.
NoSpider itself releases removed plates and uses mouseover warnings, not
continued corpse masking. Our implementation preserves no-mouseover tracking
and native-frame reuse cleanup; the new popup needs live validation. See
[CORPSE-HANDLING.md](CORPSE-HANDLING.md) for detection and limitations.

## Current behavior

- **Cover picker (v0.3.0):** `/spider config` opens a preview, five bundled
  choices (fox, red, blue, sage, charcoal) and a custom local texture field.
  `/spider cover <choice>` also works if the client rejects window APIs.
  The selected image persists and updates existing covers without changing
  tracking, allocation or disabled state. Original colors and full opacity
  are enforced; the fallback fills the entire frame. See [COVER-IMAGES.md](COVER-IMAGES.md).
  The user explicitly authorized publishing the supplied fox with this addon
  on 2026-10-16. Additional supplied images still need publication permission.

- Tracking is the only automatic detection path. No targeting or mouseover
  input is required or queried. Covers attach to native accessible plates.
- `/spider enable` enables tracking, exits arrange mode and retries paused
  coverage. New installs start enabled; `/spider disable` stops tracking and
  hides every cover, including manual shields. The preference survives reload.
- Bare `/spider` prints diagnostics. `on`/`off` remain aliases; the retired
  `auto` command prints replacement guidance and cannot select another mode.
- Manual parked shields remain optional and click-through outside arrange
  mode. New installs have zero manual shields; existing configured manual
  shields and their positions are preserved. Disabled commands and saved
  layout restoration cannot show covers or capture mouse input.
- **Near-field boost (v0.2.7):** the client holds nameplate apparent size in
  a narrow band while the model keeps growing as the camera approaches, so a
  plate-proportional cover under-covers close spiders. True camera distance
  is unmeasurable on this client (all position APIs absent), so the boost is
  not graded by distance: when a plate's apparent width
  (`GetWidth × GetEffectiveScale`, UI-scale px) reaches `nearThreshold`
  (`/spider near`, default `0` = off), the tracked cover is multiplied by
  `nearBoost` (default `2.6`). `/spider debug on` prints an `SBG| near:`
  line (1 Hz) with each plate's apparent width for calibration.
- Secret identities and forbidden frames are skipped. Rejected cleanup
  defers reuse. Repeated errors pause tracking; enable explicitly retries.
- A readable death state on an observed nameplate or a readable death GUID
  matching a recent observation triggers the brief centered popup. Mere
  plate loss, stale/unseen GUIDs and secret values do not. Disable/world
  transitions clear it and its bounded recent-observation cache.

## Files and verification

- `SpidersBeGone/Appearance.lua`: preset registry, saved choice and local-path validation.
- `SpidersBeGone/Config.lua`: optional picker with preview; no window at startup.
- `SpidersBeGone/Core.lua`: commands, settings migration, scan and lifecycle.
- `SpidersBeGone/DeathWarning.lua`: original centered UI, 1.75-second timeout,
  deduplication, guarded death queries/events and recent-GUID matching.
- `SpidersBeGone/Cover.lua`: native parenting, manual layout migration and
  visibility gating. `Access.lua`/`Units.lua` enforce readable public queries.
- `tools/test_core.lua`: behavioral regressions including pointer-query
  instrumentation, disabled reload/events, migration, movement and restrictions.
- `tools/package_addon.py`: builds the installable ZIP and tests its extracted
  Lua sources. From the repository root:

```powershell
$env:UV_CACHE_DIR = Join-Path (Get-Location) '.test-cache'
$env:UV_LINK_MODE = 'copy'
uv run --offline --with lupa python tools/package_addon.py
git diff --check
```

The generated ZIP is in the repository's parent directory; validation logs
and extracted-package checks are ignored under `dist/`.

For live validation use the checklist in TRACKING-ONLY.md: approach multiple
spiders with the pointer elsewhere, move/zoom, disable and reload, then enable
and verify covers resume and clicks pass through. Native stacking/clamping,
missing plates, corpses, and restricted data can still expose models. Offline
stubs do not establish actual client behavior or Blizzard approval.

## Data-source decisions

Forever uses Vanilla Classic as its content baseline. LibTourist Classic Era
(MIT) is the selected general metadata source if required; no geography
library is needed for tracking. Questie/QuestieDB data is excluded. NoSpider
is credited inspiration and its original curated records are a possible
complement after Classic filtering and source review. Its identifiable
Wowhead-derived bulk spawn table is excluded without separate permission.
See [DATA-SOURCES.md](DATA-SOURCES.md) for evidence and licensing decisions.

Earlier probe results and superseded controls are retained in
[HANDOFF-HISTORY.md](HANDOFF-HISTORY.md), [PLAN.md](PLAN.md), and the older
release notes. Do not reintroduce the removed cursor detector from them.

## In-game verification (2026-10-16, Tirisfal)

Round run on the v0.2.5-based build (nameplate tracking, before the
tracking-only refactor):

- **Tracking confirmed**: covers attach to spider nameplates and follow the
  model with camera movement and zoom.
- **Stale-save bug found and fixed**: the owner's selftest read `auto=nil`
  with clearly visible spiders. The client applies SavedVariables by
  *replacing* the whole settings table, possibly after script load; the
  owner's save predated M3.5 and had no `autoTrack`/`trackScale`/`drop`
  keys. This build handles the same gap: schema-3 migration runs at the
  restore point too (`EnsureSettings()` after the SBG13 load-order guard),
  removing the retired mode flags and filling missing tracking keys.
- **`drop` calibrated 0.9 → 0.5**: screenshot measurement (Young Night Web
  Spider, Tirisfal) put the model's body above the cover's top edge at 0.9;
  at 0.5 the whole model (hanging ≈0.2–0.3 cover-heights below plate
  centre) is inside the cover with minimal nameplate overlap. `drop` is in
  cover-height units, so the calibration is distance-invariant.
- Still to verify on the live client: the `enable`/`disable` reload path,
  migration of a real pre-schema-3 save, and the near-field threshold
  (`/spider debug on` → walk far-to-close at a spider → `/spider near N`).

## Next in-game round (v0.3.0)

Upstream's last installed-state report was v0.2.7, commit `75571b9`, with
`AddOns/` in sync and 221 packaged-source checks. This session pulled its
follow-up checklist commit `3ebe8a7` and preserved both updates.
The current combined build is v0.3.0 with **288 packaged-source checks** and
ZIP `SpidersBeGone-0.3.0-fixed.zip`; it has not been installed in game here.

In order:

1. Install the v0.3.0 addon folder, then `/reload`; bare `/spider` must report
   **v0.3.0** with `grow=1.6 drop=0.5
   near=0`, tracking enabled, `limited=false`.
2. **Regression re-check** (30 s): Tirisfal, walk up on spiders — covers
   attach, show the fox in its original colors on an opaque dark blue square,
   follow movement and zoom, ground still click-through. Check old saved tint/
   opacity values cannot recolor it or let the model show through.
3. **Cover picker:** `/spider config`, click each preset and check the
   preview and live covers change immediately. Enter a prepared local TGA
   path; verify its preview and persistence after `/reload`. Disable covers
   and change the image; covers must stay hidden. Verify the picker closes
   and releases keyboard focus. Command fallback: `/spider cover red`.
4. **Near-field calibration:**
   - `/spider debug on`
   - Stand as close to a spider as practical (the distance where the legs
     showed in the 2026-10-16 screenshot); read the `SBG| near:` line →
     **close value**.
   - Step back ~30 yd → **far value** (the line prints 1×/s per tracked
     plate: `nameplate1=<apparent width in UI-scale px>`).
   - `/spider near N` with N just **above** the far value.
   - Walk in again: the legs must be inside the cover, and the cover must
     keep tracking while moving/zooming. The size step at the threshold is
     by design binary; if it looks too abrupt, lower `/spider grow` slightly.
5. **Enable/disable path** (leftover from the v0.2.6 round):
   `/spider disable` → every cover hides; `/reload` → still disabled, no
   covers; `/spider enable` → tracking resumes immediately.
6. **Real stale-save migration:** the owner's live save is pre-schema-3 (no
   `autoTrack`/`trackScale`/`drop`/`near*` keys). It is migrated
   automatically on first login of a v0.2.6+ build — confirm step 1's
   reported defaults, tracking on, and **no ghost cursor covers** from the
   old mode. (The Lua suite already covers the same path with a simulated
   stale save.)
7. **Corpse warning:** with the pointer elsewhere, kill a tracked spider.
   Verify the centered LOOK AWAY popup lasts 1.5 to 2 seconds, remains
   click-through, and can appear even when the plate disappears. Kill two
   spiders in quick succession; a stale timer must not hide the newer
   warning early. Disable while it is visible; it must hide immediately and
   stay off. Corpses themselves remain uncovered after native plate removal.

If anything fails: keep `/spider debug on`, reproduce, and collect the `SBG|`
chat lines (especially `SBG| near:` — the evidence for retuning
`nearThreshold`/`nearBoost`) plus a screenshot. Do not change the sizing
model (plate-proportional + near-band boost) without that data.
