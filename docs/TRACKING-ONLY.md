# v0.3.1: automatic nameplate covers only

The addon attaches its own click-through covers to accessible spider
nameplates. No targeting, mouseover or pointer input is required. Every
cover stays mouse-disabled for its entire lifetime, including allocation,
attachment, reuse, failed cleanup and removal.

## Normal controls

- `/spider enable`: enable tracking and retry paused coverage. Enabled by default.
- `/spider disable`: release and hide covers; stays disabled after reload.
- `/spider config`: explicitly open the image picker, with presets and a custom path.
- `/spider cover <choice>`: choose an image through chat commands.
- `/spider`: show status and diagnostics. `/spider help` lists supported commands.

`on`, `off` and `toggle` remain compatibility aliases. Coverage calibration
(`grow`, `drop`, `near`, fallback `size`), extra creature names and debug logging
remain available. See the README and [image guide](COVER-IMAGES.md).

There are no screen-positioned covers, movement handlers, layout commands,
or per-character cover positions. The image picker is the only addon window
that accepts input, and appears only when requested. The automatic centered
corpse notice remains click-through and expires after 1.75 seconds.

## Upgrade behavior

Schema 4 removes the entire old `covers` table across all characters, plus
`parkCount`, `arrange`, retired detection selectors and obsolete tint/opacity
fields. Migration runs at script load and again at the real settings restore
point, since this client can replace SavedVariables after the addon loads.
An old `arrange=true` cannot pause tracking or make a cover accept clicks.

Supported preferences remain: enabled/disabled state, selected cover/custom
path, extra names and tracking calibration. Live covers are always rebuilt
from native plates. None can appear just because an old layout was saved.
Rejected parent/anchor operations still use ordinary cleanup and defer slot
reuse; there is no alternate hidden-data channel.

## Validate on the partner's machine

The primary live test client is the partner's computer (`evelyn-loves-coffee`),
not this development machine. Offline tests and a built ZIP do not establish
successful installation or native input behavior there.

The reported stuck-cursor incident survived `/reload`. Fully exit the game
before replacing `Interface/AddOns/SpidersBeGone/` with this version, then
restart and confirm bare `/spider` reports v0.3.1. Existing supported settings
can remain in place; migration deletes the old layout automatically.

1. Log in away from spiders: no leftover cover should appear, and mouse and
   camera control should work. Check again after reload and relog.
2. Approach several spiders with the pointer elsewhere. Covers should follow
   movement, camera rotation and zoom. Ground clicks, targeting and camera
   control must pass through them. Clicking a cover must not move it.
3. Disable, reload and relog: no cover should appear. Enable: only live
   nameplate covers should resume.
4. Open the image picker, change presets/custom art, close it, and check
   mouse and keyboard focus return to the game. Image choice should persist.
5. Verify the look-away popup after an observed death: centered, click-through,
   gone after 1.5 to 2 seconds. The corpse itself can remain visible.

The offline suite traps cover movement and screen-measurement calls and records
every mouse-enable call, failing if any cover ever accepts input. It also
exercises legacy/late saves, native movement/scaling, pool churn, access guards,
cleanup failures, disable/reload, image selection and corpse warnings.
