# HANDOFF — resume here (fresh session)

Last updated: **2026-10-15**, after the first in-game M3 round
(fixes SBG8–SBG12 committed; two open in-game issues, probe battery
prepared — **next session starts at §Resume**).
A new agent session should start with this file.

## One-line status

**M1, M2, and the M3 implementation are DONE**; client fixes SBG8–SBG12
are committed (HEAD `9586588`, then version bump to **0.2.1** for build
identification). M3 in-game verification is **in progress**: covers render
and parks spawn, but (A) the user's last session still showed `saved=0`
(build in question — decisive probe prepared) and (B) hovering a spider
allocated no cover (probe battery prepared, not yet run). Owner's desired
UX: **covers should track visible spiders as the character walks past
them, ideally without mouseover** (nameplate-anchored — probes prepared).

## Resume — in-game state as of 2026-10-15 (read this first)

### What the user observed (last in-game session)

- `/reload` → no errors; **8 parked discs** visible top-left.
- `/spider` → `covers shown=8/24 | saved=0`.
- `/spider on` → discs **cleared**, 0 restored.
- Hovering a spider → **no disc appears**.
- While hovering (mouse still on the spider):
  - `UnitName("mouseover")` = "Young Night Web Spider" ✓
  - `SBeGone.Cover.ShownCount()` = 0
  - 2× manual `SBeGone.Tick()` → still `shown=0`, no `SBG| tick error` line.

### What is verified on disk (no need to re-check)

- Installed addon in `~/Apps/wow/AddOns/SpidersBeGone` **is the new build**
  (grep-verified: contains the SBG12 `GetPoint` fix; `diff -r` clean vs
  repo; installed 2026-10-15 02:07).
- SavedVariables file (readable in play, do NOT edit — outside `AddOns/`):
  `<pfx>/WTF/Account/810808997#1/SavedVariables/SpidersBeGone.lua`
  currently holds `covers.Eldette = {}` (empty — the "intentionally
  cleared" state from the user's `/spider clear` test; written 02:08:20).
  ⇒ Next login restores **0 parks** (first-run respawn is suppressed by
  the empty present list). That is expected, not a bug.

### Open issue A — is the client actually running the new build?

The `shown=8, saved=0` pair is the *old* IsShown-based-Save signature;
the new allocation-based Save cannot produce it. Possible explanations:
the test ran before the 02:07 install, or `/reload` did not re-execute
the TOC. **Decisive probe (P1 below):** with discs visible, run a manual
`C.Save()` and read back the saved count — new build ⇒ 8 entries.
Selftest line 1 must now say **`v0.2.1`** (bumped specifically to remove
build ambiguity).

### Open issue B — hover allocates no cover

Chain under test (`Core.lua SBeGone.Update` hover branch):
`ready` + `enabled` → `U.IsSpider("mouseover")` → `GetCursorPosition()` →
`C.Allocate`. Suspects, in order:
1. **`UnitClass("mouseover")` returns non-nil for spiders on this
   client** → the player-guard in `U.IsSpider` wrongly rejects them
   (never probed in-game; `UnitName`/`UnitCreatureFamily` on the same
   token work). If so: replace the guard with a player-**name** comparison
   (`UnitName("mouseover") == UnitName("player")`), keep `UnitClass` only
   as secondary.
2. **`GetCursorPosition()` returns nil / is absent** → hover branch
   silently skips (it is `and`-guarded, no error). If so: need a different
   screen position source (the nameplate position doubles as one — see
   feature below).
3. Testing artifact: chat focus can drop `mouseover` off the unit; the
   user held the mouse on the spider, and `UnitName` printed it, so this
   is less likely but the probe battery re-checks it live.
4. **Probe pitfall (caused our confusion):** `ShownCount()` is
   IsShown-based and Show() is deferred (SBG12) — a freshly allocated
   cover is NOT counted until the next display pass. Signals that DO work
   immediately: `SBeGone.hover.key` (non-nil = allocated), the visual disc,
   and `C.Save()` read-back.

### Probe battery (copy-paste to the user; all lines ≤255 chars)

Run after `/reload` (which must show no errors) and after confirming
selftest line 1 says `v0.2.1`:

**P1 — build/persistence check** (while discs are visible):
```
/run SBeGone.Cover.Save() local l=SBeGoneSettings.covers["Eldette"] print("SBG2| manual save: "..tostring(l and #l or "nil").." entries, shown="..tostring(SBeGone.Cover.ShownCount()))
```
- `8 entries` → new build confirmed; earlier `saved=0` was a stale-build or
  load-order artifact → proceed to hover probes.
- `0 entries` → old code still running → `/reload` again (watch chat for
  errors); if still 0, re-copy the addon folder and `/reload` again.

**P2–P6 — hover chain** (mouse ON a spider, do not move it between lines):

```
/run print("SBG2| state: ready="..tostring(SBeGone.ready).." char="..tostring(SBeGone.char).." enabled="..tostring(SBeGoneSettings.enabled))
```
```
/run print("SBG2| unit: name="..tostring(UnitName("mouseover")).." class="..tostring(UnitClass("mouseover")).." fam="..tostring(select(2,UnitCreatureFamily("mouseover"))).." id="..tostring(UnitCreatureID("mouseover")))
```
```
/run print("SBG2| IsSpider="..tostring(SBeGone.Units.IsSpider("mouseover")))
```
```
/run local x,y=GetCursorPosition() print("SBG2| cursor: "..tostring(x).." x "..tostring(y))
```
```
/run SBeGone.Tick() print("SBG2| after tick, hover key: "..tostring(SBeGone.hover.key).." shown="..tostring(SBeGone.Cover.ShownCount()))
```

Decision tree:
- P2: all true → continue. `enabled=false` → user left `/spider off` on.
- P3 `class=`: **nil** → guard fine. **anything else** → suspect #1
  confirmed → implement name-comparison player guard.
- P4 `true` + P5 two numbers + P2 true + P6 `hover key=nil` → bug is in
  `Update`'s placement path; add temporary `SBG|` debug prints in Update
  (guarded by a `SBeGone.debug` flag) to find the skip.
- P5 `cursor: nil` → suspect #2 confirmed → choose alternative position
  source (nameplate anchor, or probe `GetCursorPosition` arg forms).
- P6 `hover key` non-nil → allocation works; if no disc is visible, check
  the cover's `SetPoint` values / strata (and the vertical-mirror note in
  the M3 section).

**NP1–NP2 — nameplate access** (for the auto-cover feature; stand near
2–3 spiders with nameplates visible):

```
/run for i=1,32 do local t="nameplate"..i local ok,vis=pcall(UnitIsVisible,t) if ok and vis then local ok2,nm=pcall(UnitName,t) print("SBG2| np"..i.." name="..tostring(nm)) end end
```
```
/run for i=1,32 do local f=_G["nameplate"..i] or _G["NamePlate"..i] if f and f.IsShown and f:IsShown() then local _,_,_,x,y=f:GetPoint(0,UIParent,"BOTTOMLEFT") print("SBG2| frame np"..i.." x="..tostring(x).." y="..tostring(y)) end end
```

### Owner's desired feature (drives the next build step)

Quote: covers should land on **every spider on screen — some close, some
far** (screenshot: scattered spiders, nameplates only go so far); and:
"when I walk past spider enemies, ideally without needing to mouseover, a
cover unit frame should extend from the existing unit frame and cover the
enemy model. If automatic anchoring is not possible, mouseover is an
acceptable backup."

Design (pending NP1/NP2 results): each tick, enumerate nameplate
units/frames (NP1/NP2 pattern); for each whose unit passes `U.IsSpider`,
read the nameplate's screen position (frame `GetPoint` — offsets are the
4th/5th returns, SBG12) and place/track a cover at that position (offset
below the plate to sit on the model). This reuses the pool, persistence,
and soft-clamp as-is; nameplates already do the 3D→UI projection the game
refuses to expose. If NP1+NP2 are both empty: nameplate route is dead →
mouseover sticky hover stays the only interaction (owner's stated
fallback) and we say so explicitly.

## M3 (code complete 2026-10-14) — in-game verification protocol

## Read in this order

1. `docs/PLAN.md` — full design. Key sections: §2 (confirmed API surface +
   SBG1–SBG6 results), §3 (architecture; §3.0 = final UI-anchored design),
   §4 (file inventory, settings schema, slash, panic hotkey), §6
   (milestones), §12 (probe rounds — §12.10 SBG7 is the only remaining
   probe).
2. `docs/API-VERIFICATION.md` — authoritative record of what exists/absent
   on the client (M1 exit record).
3. `SpidersBeGone/` — the addon (M3: `Units.lua` predicate, `Cover.lua`
   24-slot pool + persistence, `Core.lua` driver/slash/lifecycle, TOC,
   art).
4. `tools/test_core.lua` — offline test harness (run: `lua5.1
   tools/test_core.lua` from the repo root).
5. `~/Apps/AGENTS.md` — the PAWS standard the work is judged by.

## Environment cheat sheet (do NOT re-probe what is verified)

- Repo: local git clone (path is **machine-local** — on the machine from
  2026-10-13 it was `~/Apps/SpidersBeGone`; on the current machine it is
  `~/Apps/SpidersBeGone-ArachnaphobiaAddon`), pushed to
  `github.com/evelyn-loves-coffee/SpidersBeGone-ArachnaphobiaAddon`, public.
- Install: `rm -rf ~/Apps/wow/AddOns/SpidersBeGone && cp -r
  <repo>/SpidersBeGone ~/Apps/wow/AddOns/` (substitute the local clone
  path) — then the user does `/reload` in-game. (`~/Apps/wow/AddOns` is a
  symlink into a Steam/Proton pfx; the compatdata id is machine-local —
  current: `.../compatdata/4154337869/pfx/drive_c/Program Files (x86)/World
  of Warcraft/_classic_beta_/Interface/AddOns/`.)
- Client: WoW **Forever 1.60.1**, build 70374, **interface 16001**,
  **Lua 5.1**, modern codebase, reduced API set. UI-scaled screen
  1772×1181. Character: Horde Warrior (test character: **Eldette**).
- Test spider: "Young Night Web Spider" (NPC **1504**, level 2, Tirisfal
  Glades); `UnitCreatureFamily` → `("Spider", 3)`.
- SavedVariables **on disk** (readable in play; NEVER edit — outside
  `AddOns/`): `<pfx>/WTF/Account/810808997#1/SavedVariables/SpidersBeGone.lua`
  (plus a `.bak`). It is ground truth for what actually persisted.

## Hard-won client facts (violating these wastes an in-game round)

1. Chat `/run` is capped at **255 chars including `/run`**. Measure every
   line (`wc -c` / `${#line}`) before the user pastes it.
2. `RegisterEvent` **errors** on unknown events (no silent no-op). Only
   register SBG6-confirmed events: `UNIT_TARGET`, `PLAYER_ENTERING_WORLD`,
   `ZONE_CHANGED_NEW_AREA`, `VARIABLES_LOADED`, `UNIT_AURA`,
   `PLAYER_LOGIN` — or pcall-guard everything.
3. Slash commands: **two-part registration only** — `_G.SLASH_SPIDER1 =
   "/spider"` + `SlashCmdList["SPIDER"] = function(msg) end`. Proven by the
   working Spoken addon and by our M2 verification. There is no
   `CHAT_COMMAND` event.
4. `UnitCanAttack` is **two-arg**: `UnitCanAttack(unit, target)`.
5. Keybindings: XML `<Bindings>` files (Spoken ships one, but it is not
   listed in its TOC — ours must be listed and verified via the
   key-binding UI). Lua `Bindings` table absent; `KEY_DOWN`/`KEY_UP` events
   absent.
6. **No world-position or projection APIs** — 3D-follow is closed for good
   (`ClosestUnitPosition` returns nil even in starting zones). Covers are
   UI-anchored (PLAN §3.0).
7. Frame globals that exist: `TargetFrame`, `FocusFrame`, `UIParent`.
   Absent: `MouseOverInfoFrame`, `PartyFrame1`, `MainMenuBar`.
8. Lua 5.1: no `//`, no `goto`, no `table.pack`, no bitwise ops.
9. The client's own UI code is packed (unreadable on disk — `Interface/`
   contains only `AddOns/`). The Spoken addon (`~/Apps/wow/AddOns/Spoken/`)
   is the best working reference for client conventions.
10. **Native `CreateTexture` ≠ classic (SBG8, 2026-10-14):** usage `self:
    CreateTexture(params)`; the classic `"BACKGROUND"` layer is **rejected**
    ("bad argument #3"). Proven layers on this client: `"ARTWORK"`,
    `"HIGHLIGHT"` (Spoken's vanilla branch). Region methods proven: 
    `SetTexture(path)`, `SetTexture(r,g,b,a)`, `SetVertexColor(r,g,b)`, 
    `SetAllPoints()` (no args). Our `Cover.lua` pcall-probes layers
    (ARTWORK first) instead of assuming.
11. All probe output should be `SBG|`/`SBG2|`-prefixed via the helper:
    `/run SBG2={p=function(k,v) print(("SBG2| %s: %s"):format(k,tostring(v))) end}`
    (re-run after any `/reload`; cleanup: `/run SBG2=nil`).
12. **Frame methods absent on this client (SBG9, 2026-10-14):**
    `SetClampRect` (in-game "attempt to call a nil value", zero hits in
    Spoken) and `SetSize` (Spoken shims it as `SetWidth`+`SetHeight`,
    which ARE proven). Covers keep-on-screen via a **soft clamp in
    `C.SyncDrags`** (adopted drag position clamped to screen bounds).
    Proven frame methods: `SetParent`, `SetFrameStrata`, `EnableMouse`,
    `SetMovable`, `SetPoint`, `GetPoint`, `IsShown`, `Show`/`Hide`,
    `SetScript`, `RegisterEvent`.
13. **Script handlers are called with NO arguments (SBG10, 2026-10-14):**
    event data arrives via the globals `this`/`event`/`arg1`..`arg9`
    (Spoken's Compat.lua wraps handlers accordingly). Never name a handler
    parameter `event` — it shadows the global and the handler silently
    never fires. Our OnEvent uses `local ev = evt or event` (works under
    both conventions).
14. **Chat filter eats `|` + letter (SBG11, 2026-10-14):** `|toggle` and
    `|help` in a print became `oggle`/`eIp` in chat (consumed as control
    sequences). Chat text uses ` / ` separators; ` | ` (spaced) is safe.
15. **Show() is deferred; GetPoint returns 9 values (SBG12, 2026-10-15):**
    `IsShown()` is false right after `Show()` until the next display pass —
    base persistence on allocation state, not IsShown (in-game: 8 covers
    shown but `saved=0`, WSV had `covers[char] = {}`). `GetPoint` offsets
    are the 4th/5th returns; mis-unpacking silently killed drag adoption.

## M3 (code complete 2026-10-14) — in-game verification protocol

Implementation notes (what shipped):

- **Driver:** `C_Timer.After(0.1)` self-rescheduling loop (~10 Hz), per the
  handoff default — SBG7 (PLAN §12.10) remains optional; if it ever shows
  OnUpdate scripts are live, only `SBeGone.StartDriver` changes (the tick
  function is identical). If the tick never runs, check for
  `SBG| ERROR: C_Timer.After missing` in chat.
- **Sticky hover:** hover a spider → a cover disc appears at the cursor;
  mouse leaves → it sticks (sweep across spiders = one stuck cover per
  spider). Covers are **not click-through** (so they are draggable);
  a cover under the cursor also ends the hover, which is what makes it
  stick.
- **Cursor coordinates:** `GetCursorPosition` is assumed to be in
  UIParent/BOTTOMLEFT UI space (y from the bottom — SBG5's (206, 409) while
  pointing at a ground spider supports this). **If covers appear at a
  vertically mirrored position, flip once:** in `Core.lua` `SBeGone.Update`,
  `cy = (GetEffectiveScreenInfo() and GetEffectiveScreenInfo() or 1080) - cy`
  — or more simply: `local sw, sh = GetEffectiveScreenInfo() ... cy = sh - cy`.
- **Park shields:** first run per character spawns `parkCount` (8) draggable
  discs in a row near the top; every position (hover-stuck or parked, after
  dragging) is saved per character in `SBeGoneSettings.covers[char]` and
  restored on `/reload`/relog. `/spider clear` empties the saved list
  (an empty *present* list suppresses the default respawn). Covers can
  never be dragged off-screen and lost: `C.SyncDrags` soft-clamps adopted
  positions to the screen bounds (`SetClampRect` is absent — SBG9).
- **Slash:** `/spider [on|off|toggle|clear|help]`, bare = selftest (now 3
  `SBG|` lines: version/build/Lua, enabled/interface/char/driver/sticky,
  pool/saved/size).
- **Offline suite:** `lua5.1 tools/test_core.lua` — 62 checks (migration,
  predicate, sticky on/off, FIFO eviction, drag sync, epsilon, per-char
  persistence, slash). Run before every in-game round.

Protocol (user does this part; repo is already installed in `AddOns/`):

1. `/reload` — no errors in chat; addon appears in the AddOns list.
2. `/spider` — 3 `SBG|` lines; line 1 must say **`v0.2.1`** (build check);
   `char=` shows the character name. NOTE: Eldette's save is currently
   "intentionally cleared" (`covers.Eldette = {}`), so expect
   `covers shown=0/24 | saved=0` — NOT 8 parks (the empty present list
   suppresses first-run respawn; that is correct behavior). A fresh
   character still gets the 8 default parks.
3. **P1–P6 + NP1–NP2 probe battery from §Resume above** (resolves the two
   open issues and the nameplate question). Fix whatever they pin down,
   re-install, `/reload`, then continue.
4. Hover a Tirisfal spider → a red disc appears over it; move the mouse
   away → the disc **stays**.
5. Drag a disc somewhere else; `/reload` → it is still there.
6. `/spider clear` → all discs gone (and gone after another `/reload`).
7. `/spider off` → hovering a spider shows nothing; `/spider on` →
   saved positions come back.

**M4 after this passes:** blind mode + panic hotkey (`Bindings.xml` route,
§4.5 — verify our XML actually loads via the key-binding UI) + frame cover
(`TargetFrame`/`FocusFrame` only).

## Owner decisions still open

- **Keep the 8 default parked discs?** Asked 2026-10-15, no answer yet.
  With nameplate auto-cover they'd likely be clutter. If kept, consider a
  `/spider parks` reset command (Eldette's cleared state can't be reset
  from our side — the WSV file is outside `AddOns/` and must not be
  edited).
- **Panic hotkey in v1.0?** `KEY_DOWN` route dead (SBG6); `Bindings.xml` is
  the live candidate (needs an in-game key-binding-UI check); `/spider
  hide` is the guaranteed fallback.
- **v1.0 scope** — current default unless the owner objects: sticky hover
  shield + parkable shields + blind mode + `/spider clear`; frame cover
  optional; panic hotkey TBD.
- Owner requirement already encoded (2026-10-13): covers must **persist** —
  "all spiders should be covered", not just while hovered (`stickyCovers`
  default on).

## Release context

Game is in beta ~1 week; out-of-beta release expected next month (2026-11).
Aim: v1.0.0 (M6: README, polish, tag) before/at the public release. Re-run
the §12 probe set on the release client if the interface number changes
(current: 16001).

## Session log

- **2026-10-14:** M3 implemented (f4c8cc6) + offline suite. First in-game
  round fixed SBG8 (CreateTexture layers), SBG9 (SetClampRect/SetSize
  absent; soft clamp), SBG10 (no-arg script handlers). User confirmed:
  no errors on `/reload`, 8 parked discs render, selftest sane, `mouseover`
  token works (`Young Night Web Spider, fam: 3`).
- **2026-10-15 (a):** User reported: 8 parks shown but `saved=0`; certain
  slash sequences removed them; `/spider help` garbled in chat. Fixed
  **SBG11** (chat filter eats `|`+letter → ` / ` separators), **SBG12**
  (deferred `Show()` → `C.Save` now allocation-based; `GetPoint` offsets
  are 4th/5th returns → drags now adopted), tick driver hardened
  (reschedule-before-update + pcall). WSV file inspection proved the
  persistence bug (`covers.Eldette = {}` on disk). Committed `9586588`.
- **2026-10-15 (b):** User retest: still `shown=8 saved=0`, `/spider on`
  cleared discs, hover allocated nothing. Manual probes: `mouseover` name
  works, `ShownCount()=0` (deferred-Show ambiguity), manual ticks clean.
  → Two open issues (A: build in question; B: hover chain) with a
  prepared probe battery (P1–P6, NP1–NP2) in §Resume. Bumped to **0.2.1**
  for selftest build identification. Owner restated desired UX: cover
  visible spiders without mouseover (nameplate-anchored; mouseover =
  accepted fallback).

## Git

- Everything relevant is committed & pushed (check `git log`; latest:
  `9586588` SBG11/SBG12 fixes + this handoff + 0.2.1 version bump).
  Conventions: direct to `main` (owner decision), lowercase
  conventional-ish messages, tag `v1.0.0` at M6.
- Art regenerates via `python3 tools/make_art.py` (stdlib only) — no binary
  art is ever hand-edited.

## Next session, in order

1. User runs the §Resume probe battery (P1 first — build check; then
   P2–P6 with mouse on a spider; NP1–NP2 near named spiders). Paste all
   `SBG2|` lines + any `SBG| tick error:` lines.
2. Interpret with the §Resume decision tree; implement the indicated fix
   (candidates pre-drafted there: name-comparison player guard; alternate
   cursor source).
3. `lua5.1 tools/test_core.lua` (must stay ALL PASS), reinstall
   (`rm -rf ~/Apps/wow/AddOns/SpidersBeGone && cp -r SpidersBeGone
   ~/Apps/wow/AddOns/`), `diff -r` verify, commit + push, user `/reload`s.
4. Finish M3 protocol steps 4–7 (hover stick, drag persist, clear,
   off/on).
5. NP1/NP2 results → build nameplate auto-cover (M3.5) or report the
   route dead → mouseover-only (owner's fallback).
6. M4: blind mode + panic hotkey (`Bindings.xml` route) + frame cover.
