# Handoff: v0.2.6 tracking-only covers

Current implementation and controls are in [TRACKING-ONLY.md](TRACKING-ONLY.md).
The packaged Lua 5.1 suite passes offline; live Forever validation is pending.

## Current behavior

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
- Settings schema 3 removes old `autoTrack`/`stickyCovers` flags and saved
  cursor-generated covers across all characters. Explicit parked records
  remain. SavedVariables arriving after script load are also migrated.
- Secret identities and forbidden frames are skipped. Rejected cleanup
  defers reuse. Repeated errors pause tracking; enable explicitly retries.

## Files and verification

- `SpidersBeGone/Core.lua`: commands, settings migration, scan and lifecycle.
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
