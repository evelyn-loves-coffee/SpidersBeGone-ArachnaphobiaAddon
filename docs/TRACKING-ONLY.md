# v0.2.6: tracking-only covers

These tracking-only controls also apply in v0.2.8, which adds the automatic
1.75-second corpse-warning popup documented in [CORPSE-HANDLING.md](CORPSE-HANDLING.md).

Tracking is the only automatic detection mode. It scans accessible native
nameplate units and attaches click-through covers to matching spiders without
targeting or mouseover. The cursor detector and its state have been removed.

## Controls

- `/spider enable` enables tracking immediately, exits manual arrange mode
  and retries coverage paused after errors. New installations are enabled.
- `/spider disable` stops tracking, releases tracked covers, hides all manual
  shields and makes the pool click-through. The preference survives reload.
- `/spider` continues to print diagnostics, including `mode=tracking`,
  `enabled`, `limited` and `paused`.
- `/spider on`, `/spider off` and `/spider toggle` remain compatible aliases.
  `/spider auto` is retired and only explains the replacement commands.
- Manual shields remain optional through `/spider parks N` and arrange mode.
  They cannot show or capture input while the addon is disabled. Enabling
  leaves arrange mode and resumes normal tracking.

## Upgrade behavior

Settings schema 3 preserves the overall `enabled` preference and removes
`autoTrack` and `stickyCovers`. An enabled installation formerly configured
with `autoTrack=false` now tracks automatically without an extra command.
Migration runs again when SavedVariables arrive after script load.

Saved covers retain the existing per-character record format. Only explicit
`kind="park"` records are retained; old cursor covers and legacy covers with
no kind are removed for every character. Manual positions and sizes remain.
New installs default to zero manual shields. Existing configured manual
shield counts are preserved. Live tracked covers are never persisted.

Timer scans, plate-added events and direct refresh calls respect the disabled
state. Restoring saved manual shields while disabled also keeps them hidden.

## Validation

`tools/package_addon.py` checks the installable v0.2.6 ZIP and runs the Lua 5.1
suite against its extracted sources. The suite covers enable/disable,
disabled reloads/events/manual commands, legacy settings and cover migration,
no cursor or mouseover queries, fresh-install defaults, and existing native
movement, scaling, pool reuse and restriction handling.

Live Forever validation remains pending. With enemy nameplates enabled:

1. Approach several spiders with the pointer elsewhere; verify covers follow
   while walking, rotating the camera and zooming.
2. Run `/spider disable`; verify all covers disappear and remain absent when
   plates appear, zones change, and after reload.
3. Run `/spider enable`; verify tracking resumes immediately, without a
   mouseover or a separate auto command, and native clicks pass through.
4. Confirm upgrades preserve explicit manual shields, remove old cursor
   covers, and preserve an overall disabled preference.

The existing client restrictions and nameplate alignment limits still apply.
An inaccessible plate or identity can limit coverage; no secondary detection
mode attempts to recover restricted information.
