# Corpse coverage: NoSpider comparison and Forever limits

Investigated after pulling upstream commit
`2777b0db57baae7d38efe829421ad253826a7b19` on October 16, 2026. That
update's alignment calibration and late-settings handling are preserved.
The initial pulled addon passes 216 packaged-source Lua 5.1 checks. Before
publishing, the warning was also rebased onto upstream `75571b9` to retain
its near-field cover boost and `3ebe8a7` to retain its validation checklist;
the combined release is v0.2.8.

## What NoSpider actually does

The supplied NoSpider v1.4.3 `Core.lua` removes its overlay in
`OnNamePlateRemoved` when `NAME_PLATE_UNIT_REMOVED` fires. It does not retain
a model-following cover for a corpse. Its `UPDATE_MOUSEOVER_UNIT` handler
instead checks `UnitExists`, spider identity and `UnitIsDead` for the
mouseover token, then calls its warning routine. That routine uses a raid
notice and optional sound. This is a corpse notification, not corpse masking.

The author's [project description](https://www.curseforge.com/wow/addons/nospider-arachnophobia-mode)
also explicitly describes mouseover corpse warnings and says corpses without
nameplates cannot be covered by its overlay approach. Its separate combat-log
detection can raise general spider warnings, but does not locate or cover a
corpse after the native plate disappears.

## Why the current cover disappears

Our cover is a child of the native nameplate. When the client hides or
removes that plate on death, its child has no visible moving anchor. Retaining
the frame reference would not retain an association with the corpse: native
plates are pooled and can be reassigned to another unit. The current removal
handler correctly releases our cover and drops the token mapping.

The prior client probes found no usable enemy world-position/screen-projection
route, and nameplate measurement was restricted. See
[API-VERIFICATION.md](https://github.com/evelyn-loves-coffee/ArachnaphobiaShield/blob/main/docs/API-VERIFICATION.md) and
[FOREVER-API-REVIEW.md](https://github.com/evelyn-loves-coffee/ArachnaphobiaShield/blob/main/docs/FOREVER-API-REVIEW.md). Moving the cover to UIParent
without a valid position would not track a corpse as the camera moves. No
verified public API for forcing an enemy corpse to retain its native
nameplate was identified in this review. The map-oriented UnitPositionFrame
API is not a demonstrated corpse-to-screen projection API.

Accordingly, this investigation does not establish a permitted automatic
corpse-cover implementation. Keep native-frame removal/reuse cleanup and the
tracking-only, no-mouseover requirement. Do not force native plate visibility,
guess screen coordinates, or reactivate the retired cursor detector.

## Implemented in v0.2.8: centered look-away popup

The [Forever Unit API documentation](https://github.com/Gethe/wow-ui-source/blob/b401e0332adfbf0460d319b06d8ea29279a941f1/Interface/AddOns/Blizzard_APIDocumentationGenerated/UnitDocumentation.lua)
lists `UnitIsDead`, `UnitGUID`, and a `UNIT_DIED` event whose payload is a GUID.
Identity-related values/events can be secret. Earlier client probes confirmed
`UnitIsDead` exists; delivery and timing of these events on nameplate units
still require live testing in the installed client.

The user selected a centered look-away warning lasting 1.5 to 2 seconds.
`DeathWarning.lua` independently implements a **1.75-second**, click-through
popup: "LOOK AWAY / Spider corpse may be visible."

- The normal scan observes spider nameplate units. Polling and optional
  `UNIT_HEALTH`/`UNIT_FLAGS` events check their accessible `UnitIsDead` state.
  Plate removal makes one final guarded check before ordinary cover cleanup.
- Optional `UNIT_DIED` events can also match readable GUIDs from spiders
  observed within the last three seconds, including just-removed plates.
  The GUID cache is bounded to 80 records. It never parses an arbitrary GUID
  to classify an unseen creature or reads the combat log.
- Repeated death/health/poll signals for the same record do not extend the
  warning. Another observed death starts a new 1.75-second notice; old timer
  callbacks cannot dismiss the newer notice. Periodic expiry is a backup.
- Disable, clear, and world transitions dismiss the notice and clear cached
  observations. Disabled events cannot redisplay it. Restricted identity,
  secret event values, stale GUIDs and mere plate disappearance do not trigger
  a guessed death notice. Missing GUID support still permits readable unit
  death-state detection; unsupported events are registered with `pcall`.
- The notice is owned by the addon and centered on UIParent. If its text API
  fails, it falls back to a chat warning without interrupting tracking and
  diagnostics report `corpsePopup=unavailable`.

This warning cannot hide the body, detect every pre-existing corpse, or
guarantee that an unobserved/restricted death is reported. In particular,
instant token removal can precede an observable death flag, and a matching
readable death event may be unavailable. No mouseover, target requirement,
model-position query, imported database or native-frame modification is added.

## Verification

The packaged-source Lua 5.1 suite checks centered placement, click-through,
1.75-second expiry, deduplication, overlapping timers, death after removal,
removal-time checks, no false warning on range loss, token reuse, stale/unseen
GUIDs, secret payloads, missing GUID APIs, disable/world cleanup, bounded
observations, font-API fallback, and no cursor/mouseover queries.

Live acceptance is still required: kill a tracked spider with the pointer
elsewhere; verify the centered warning lasts 1.5 to 2 seconds even when its
plate disappears. Kill two spiders in quick succession, test disable while
the warning is visible, and confirm clicks and movement pass through it.
Use `/as` to inspect `corpsePopup` if no visual warning appears.
