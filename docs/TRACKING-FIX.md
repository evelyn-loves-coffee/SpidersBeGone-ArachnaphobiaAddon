# v0.2.4: covers that remain on screen

Historical release note. [v0.2.5](NATIVE-OVERLAYS.md) removes numeric mapping
guesses and adds secret/forbidden-value and deferred-cleanup handling.

The reported failure is a cover staying in one screen position while the
spider moves. v0.2.3 creates every cover under UIParent and sets a cross-parent
anchor to a nameplate. Its tests checked the anchor arguments but did not
represent parenting or inherited scale, and did not establish actual motion.

v0.2.4 parents only the addon's cover frame to the nameplate. Width and drop
are expressed in that plate's local units, so the client applies the native
movement and distance scale to both. The plate scale must not also be baked
into the width, which would scale the cover twice. The existing 16–512 UI-unit
bounds and fixed-size fallback are converted to local units. Releasing a slot
returns its frame to UIParent before reuse or any drag measurement.

The public unit-to-plate mapper is authoritative, including a nil return.
When it is unavailable, matching GetUnit/unitToken/unit/UnitFrame.unit metadata
takes priority over frame-number guesses. A metadata-free indexed fallback
remains for the reduced client described in this repository. A known unit
replacement or missing mapping releases the old cover immediately; the grace
period remains only for a missing token. Hidden frames are not attached.

This changes the addon's own frames only. It does not measure restricted
coordinates, modify Blizzard frames, change models, or send images anywhere.

Blizzard's published UI code likewise parents its attached class bars to the
nameplate and exposes unit identity on the plate:
[nameplate driver](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_NamePlates/Blizzard_NamePlates.lua),
[plate base](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_NamePlates/Blizzard_NamePlateBase.lua).
These are implementation references, not proof of behavior in this beta client.

## Validation

The Lua 5.1 suite in `tools/test_core.lua` covers inherited movement and zoom
between polling ticks, no double scaling, UI scale, size bounds, restricted
geometry, remapped frame IDs, mapper nil, hidden plates, token reuse, cleanup,
parenting refusal, pool reuse, saved settings, and the existing hover mode.
The parent/scale regressions failed against v0.2.3 before the fix.

Run with Lua 5.1 from the repository root:

```sh
lua5.1 tools/test_core.lua
```

Or use a Python runtime embedding Lua 5.1:

```sh
uv run --with lupa python -c "from lupa.lua51 import LuaRuntime; LuaRuntime().execute(open('tools/test_core.lua', encoding='utf-8').read())"
```

## Required in-game review

No game client was available for this fix, so exact visual coverage remains
unverified. After installing, confirm `/spider` reports v0.2.4. Enable enemy
nameplates and auto tracking, then walk around two spiders without targeting
or hovering. Their covers should move independently, grow and shrink with
camera zoom, disappear with their plates, and permit clicks through them.
Try `/spider grow 2` and adjust `/spider drop` if the cover is too small or
offset. Test `/spider auto off` and arrange mode, then return auto tracking on.

Limitations: coverage requires visible nameplates; the metadata-free fallback
still assumes indexed pairing; nameplate stacking or screen-edge clamping can
displace a cover from the model. The client has no verified projection API to
align a cover independently of its plate. These limitations cannot be ruled
out by the offline renderer stub.
