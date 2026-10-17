# Open issue: the automatic near ramp keeps mid-range covers too large

**Status: reopened after the v0.4.2 in-game test, CLOSED in v0.4.3 — ramp
moved to 75→85 UI inside the client's real apparent-width range (far clamp
73, close ~90); 224/224 offline tests green. Follow-up v0.4.4 raised the
close ceiling 2.6→3.0: plate width saturates at ~91, so the flat ceiling
is the only lever for the legs poking past the cover at extreme close
range. (Recorded 2026-10-17, fixed the same evening, second round.)**

## Second round (v0.4.2 in-game, 2026-10-17)

Owner report: "the far away spiders still had a quite large cover that was
unnecessarily large." `/as debug on` capture (Tirisfal, Night Web Spiders):

- Far plates were steady at **73.0 UI apparent width** across four plates
  — the client's far clamp.
- Approach traces: `74.6→77.7→84.4→89.7` and `73.0→77.0→80.5→82.8→86.1`;
close values 89.7 / 89.0.
- The far plates therefore sat at **73.0 × 2.14** — inside the v0.4.2
  60→80 ramp window, because the client never reports apparent widths
  below 73. Both earlier knees (30, 60) were *below the client's minimum*
  and therefore boosted even far plates.

**Fix (implemented, v0.4.3):** ramp **75→85 UI** — inside the client's
actual 73–90 range: low knee 75 keeps far plates (≤ ~74) unboosted and
plate-proportional (the `/as near 1` far-shrink kept); high knee 85 sits
below the measured close band (87–113 UI) so the boost stays flat at
×2.6 at close range. `Core.lua` (`NEAR_RAMP_LO/HI = 75, 85`), tests
(apparent-73 unboosted, apparent-80 mid-ramp ×1.75 at ceiling 2.5,
apparent-85 full, apparent-90 flat), README and HANDOFF updated.

**Residual risk:** the 73 far clamp is a client/patch constant inferred
from one capture; if a future client patch widens the far range, re-check
the `AS| near:` line. The knees remain two constants in `Core.lua`.

## Resolution (v0.4.2, superseded by v0.4.3)

- `Core.lua`: `NEAR_RAMP_LO, NEAR_RAMP_HI = 60, 80`; comments and the
  DEFAULTS rationale updated; version 0.4.2.
- `tools/test_core.lua`: apparent 50 now asserts **unboosted** (below the
  new 60 knee, drop ratio preserved); new apparent-70 test asserts the
  mid-ramp partial boost with the ceiling respected (1.75 at ceiling 2.5);
  high-knee (80 → full) and flat-band (90 → full) tests unchanged.
- README (status + near-field section, known-issue note removed) and
  HANDOFF (settings paragraph) updated to the 60→80 ramp.
- Pending: owner walks far → close in game with `/as debug on` and confirms
  far covers are small again and the close band is flat.

---

## Where v0.4.1 stood

- v0.4.1 (commit `5747282`, pushed) retired the `/as near` level setting and
  computes the near-field boost automatically every 10 Hz tick:
  `nearBoostFor(apparent, nearBoost)` in `Core.lua` — no boost at/under
  `NEAR_RAMP_LO = 30` UI apparent width, smoothstep to the `nearBoost`
  ceiling (`2.6`) at/above `NEAR_RAMP_HI = 80`, flat across the measured
  close band (87–113 UI, 2026-10-16 calibration at 1.205 px/UI).
- Offline suite: 222/222 pass (`lua5.1 tools/test_core.lua`).
- `nearThreshold` is purged on load (schema 5); `/as near` prints a
  deprecation notice; `/as debug on` prints `AS| near: NPx=<width>*<factor>`
  per tracked plate.

## The problem (in-game, 2026-10-17)

Screenshot (Tirisfal, five Young Night Web Spiders at mixed distances,
3440×1440 capture; temp file no longer on disk): the covers on the **far**
spiders are no longer noticeably smaller than the close ones.

Owner's words:

> On previous `/as near 1`, the further away spiders had a smaller shield,
> and that is a beneficial aspect I want to keep. Nearer spiders had
> appropriate sized [covers].

## Root cause

Old `/as near 1` was a **binary cliff at apparent 80**: below 80 the cover
was exactly the calibrated plate-proportional size (so it shrank with
distance, as the client shrinks nameplates); at/above 80 it got the full
×2.6.

The v0.4.1 ramp starts at **30**, so every plate with apparent width in
**30–80 now gets a partial boost** that `/as near 1` never gave:

| apparent width | old `/as near 1` | v0.4.1 ramp 30→80 |
| --- | --- | --- |
| 20 (far) | 1.00 | 1.00 |
| 40 | 1.00 | **1.17** |
| 50 | 1.00 | **1.56** |
| 60 | 1.00 | **2.04** |
| 70 | 1.00 | **2.44** |
| 80+ | 2.60 | 2.60 |

Mid-distance spiders (the common case while walking through an area) sit in
30–80, so they get up to ×2.04 that they didn't before — the "small shield
far away" property the owner wants is what this eats.

## Desired behavior (from the owner)

1. **Far/mid plates: no boost** — the cover stays plate-proportional and
   shrinks with distance (the `/as near 1` far behavior).
2. **Close band (87–113 UI): full ×2.6, flat** — no cover "breathing" while
   the client clamps the plate (already working in v0.4.1; keep).
3. No user-facing setting (the agreed no-config design).

## Candidate fixes

| Option | Ramp window | Pros | Cons |
| --- | --- | --- | --- |
| **A. Move the low knee to 60 (recommended)** | 60→80 | Keeps "small far away" for everything ≤ 60; full ×2.6 by 80, exactly what level 1 already gave at the cliff; keeps the smooth transition (no sudden pop as you close in); one-constant change | The 60 knee is a design choice, not a measurement (only 87–113 is measured) |
| B. Move the low knee to 80 | 80→87 | No boost below 80 = literally level 1 under the cliff | Only a 7 UI-wide ramp — effectively the cliff back, just softened by 7 UI; delays full boost vs level 1 for 80–87 plates |
| C. Pure binary at 80 | — | Exactly the old level 1, simplest | Re-introduces the size pop on approach that motivated the ramp; least of the three changes vs v0.4.0 |

**Recommendation: A.** It is the only option that preserves all three
desired properties at once. If the in-game result still feels off, the
`AS| near:` debug line gives apparent width + factor per plate, so the knee
can be re-tuned with one number.

## Implementation plan (when approved)

1. `Core.lua`: `NEAR_RAMP_LO, NEAR_RAMP_HI = 30, 80` → `60, 80`; update the
   DEFAULTS comment block and the `nearBoostFor` comment (knees + rationale).
2. `tools/test_core.lua` near block: the "mid-range partial boost (ramp at
   50 UI)" test becomes "apparent 50 stays unboosted (below the 60 knee)";
   the high-knee (apparent 80 → full ceiling) and flat-band (90 → full,
   inside 87–113) tests are unchanged; add an apparent-70 partial-boost
   check (expected factor `1 + 1.6 × smoothstep(0.5) = 1.8` at the default
   ceiling 2.6). The geometry section already neutralizes the boost
   (`nearBoost = 1.0`), no change there.
3. Docs: README near-field section + status line (ramp is 60→80, not
   30→80), `docs/HANDOFF.md` settings paragraph, this file (close it with
   the outcome).
4. Re-run `lua5.1 tools/test_core.lua` (expect green), commit, push,
   in-game re-test: walk far → close with `/as debug on`, confirm far
   covers are small again and the band stays flat.

## State of thinking / decisions deferred to the owner

- **Knee choice (60 vs 80 vs binary): OPEN.** Table above; A recommended.
- **Is a mid-range partial boost ever wanted at all?** The original request
  (before 2026-10-17) asked for an intermediate between old levels 1 and 2;
  the in-game result overruled that — the owner explicitly wants the level-1
  far behavior back. If A still boosts too early, the next step is B/C, not
  a setting.
- **Bump on fix: v0.4.2** (no schema change; `nearBoost` default stays 2.6).
- Screenshot evidence: the 2026-10-17 capture was a clipboard temp file and
  is no longer on disk; if the owner keeps the original, it belongs in
  `docs/art/near-ramp-2026-10-17.png`.
