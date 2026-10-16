> Historical reference only. v0.3.1 removed screen-positioned covers and all editing/input modes. Follow [HANDOFF.md](HANDOFF.md) for the current implementation and test machine. This file is not shipped in the addon ZIP.

# v0.2.5 native nameplate overlays

Historical implementation notes. Native attachment/restriction handling still
applies in v0.2.6; its tracking-only controls and settings migration supersede
the mode selection below. See [TRACKING-ONLY.md](TRACKING-ONLY.md).

This release continues the nameplate-attached model cover in v0.2.4 and adds
the restriction handling identified in the source review. The implementation
is original, with NoSpider acknowledged as inspiration in the README.

- `Access.lua` checks public accessibility/secret-value flags before results
  are used for identification, string matching, comparisons or arithmetic.
  A unit flagged as identity-secret is not identified through another channel.
- The public nameplate mapper is authoritative. If it is absent, a global
  plate must expose an exact readable unit-token match. Numeric frame-number
  guessing was removed. Forbidden frames are rejected before further inspection.
- An addon-owned cover is explicitly mouse-disabled, parented to an accessible
  nameplate, and anchored with local offsets. Screen coordinates and actual
  distance are not read. Native transforms supply movement and perspective.
- Width/scale queries use accessible results only. Unavailable geometry uses
  configured dimensions; this fallback is not a distance estimate. Exact
  coverage and perceived size limits cannot be guaranteed when geometry is hidden.
- Optional plate-added/removed events improve lifecycle response. Unknown
  events are rejected normally, leaving the bounded periodic scan in place.
- A rejected detach leaves the frame excluded from the free pool, persistence,
  drag measurement and arrange-mode interaction. Normal API retries can release
  it when permitted. Failed operations do not change Blizzard's restrictions.
  If all slots are unavailable, saved-layout restoration waits for cleanup
  and preserves the original record until it can finish.
- Repeated unexpected errors or attachment failures pause automatic coverage
  instead of silently enabling sticky hover mode. `/spider auto on` retries.
- The baseline database contains 124 Classic IDs; the TBC-era Tcha'kaz entry
  was removed. No TBC zones, sub-zones, spawn tables or map libraries were added.

`/spider` reports the current `limited` and `paused` state. A limited result
means at least one checked capability/value/frame was unavailable; it is not
evidence that every visible spider is covered or that no spiders are present.

## Verification

Run the original and added regression checks with Lua 5.1:

```sh
lua5.1 tools/test_core.lua
```

The suite exercises native movement/zoom, exact mapping, secret-value and
forbidden-frame handling, rejected detachment, deferred reuse, click-through,
native lifecycle events, error suspension, and Classic-only data. Its denied
value sentinel is a simulation, not Blizzard's actual secret-value system.

`tools/package_addon.py` packages the addon, license and README, checks archive
integrity and TOC dependencies, and runs the Lua suite against the extracted
package. Python can embed Lua 5.1 via `uv run --with lupa`.

No live game client is available here. In-game confirmation remains required
for the actual Forever build, open world, instances and combat. Check model
coverage while moving/zooming, plate reuse, native clicks under the cover,
zone transitions, and behavior when data or attachment is blocked. Stacking,
screen-edge clamping, corpses and invisible plates can still expose models.
These checks establish runtime behavior; they do not constitute Blizzard approval.
