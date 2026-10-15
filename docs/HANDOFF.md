# HANDOFF — resume here (fresh session)

Last updated: **2026-10-15 (c)**, after the second in-game M3 round
(probe battery P1–P6 / NP1–NP2 run; both open issues resolved; fixes
SBG13 + SBG14 shipped in **v0.2.2** — **next session starts at §Resume
(round 2)**). A new agent session should start with this file.

## One-line status

**M1, M2, M3 implementation DONE.** Open issue A is **closed** (new build
confirmed, persistence works) and open issue B is **fixed** (SBG14: the
player guard rejected every spider). A third bug surfaced while
interpreting the data and is also fixed (SBG13: cleared cover state was
forgotten, default parks resurrected over it). What remains for M3
sign-off is one in-game round (steps 4–7 of the protocol), and the
**owner's real goal — automatic, mouseover-free covers on visible spiders
(M3.5) — is blocked on one question: a legal screen position for each
visible spider.** §Resume (round 2) has the probe battery that answers it.

**Owner constraint (restated 2026-10-15, NON-NEGOTIABLE):** the game must
stay playable; covers are **UI overlay only**. Never modify unit models,
names, combat behaviour, game files, or the client's own frames — the owner
counts that as game tampering / ban risk. Read-only public API queries
(`UnitName`, `UnitCreatureFamily`, `GetNamePlateAtPosition`, …) and our own
frames are in scope; taint-workarounds that touch Blizzard frames are not.

## Resume (round 2) — what probe round 2 proved

| Probe | Result | Conclusion |
| :-- | :-- | :-- |
| P1 selftest | `v0.2.1`, build 1.60.1/70374, Lua 5.1, `driver=true` | **new build running** — issue A closed |
| P1 manual `Save()` | `8 entries` written, and they persisted across `/spider on` | alloc-based Save works |
| P2 state | `ready=true char=Eldette enabled=true` | lifecycle fine |
| P3 unit | `name=Young Night Web Spider` **`class=Young Night Web Spider`** `fam=3 id=1504` | **SBG14**: `UnitClass` returns the unit's **name** for non-players → the old player-guard rejected every spider |
| P4 `IsSpider("mouseover")` | `false` on a confirmed spider | symptom of SBG14 (fixed) |
| P5 cursor | `1022.93 x 585.07` | `GetCursorPosition` good, UI space |
| P6 tick | `hover key=nil` (no allocation) | consistent — the predicate was the only broken link |
| NP1 nameplate **units** | `nameplate1..4` visible, names readable | **unit enumeration works** (3 spiders + 1 scavenger) |
| NP2 nameplate **frames** | `NamePlate1:GetPoint(): Action[FrameMeasurement] failed because[Can't measure restricted regions]`, `ForceTaint_Strong` | nameplate frame geometry is **client-protected** → the drafted "read the plate's GetPoint" design is **dead**, and we will not work around it (owner constraint) |

### Fixes shipped in v0.2.2 (offline suite 81 checks, ALL PASS)

1. **SBG14** (`Units.lua`): player guard is now `UnitIsPlayer(unit) == true`
   (strict boolean, so a name-returning implementation can never false-reject)
   plus a name comparison against `UnitName("player")`. `UnitClass` is no
   longer used.
2. **SBG13** (`Core.lua`, `Cover.lua`): cleared cover state was being
   forgotten — a cleared character was stored as a bare empty table
   (`covers.Eldette = {}`, verified on disk), and every `/reload` re-ran the
   **first-run** branch (8 parks, `saved=0`; and `/spider on` then hid them).
   Two-part fix:
   * **v2 record** `covers[char] = { init = true, list = { … } }` — the wrapper
     is never empty, so "intentionally cleared" can never look like "never
     ran". v1 lists migrate lazily in `C.SavedList`; `DEFAULTS.version = 2`.
   * **restore ordering**: no more restore at script-load unless the settings
     table was already populated (`SBeGone.loadSnapshot.settingsPresent`);
     `VARIABLES_LOADED` now unlocks the restore, with a bounded `C_Timer`
     retry (`SBeGone.RetryEnterWorld`).
   * `SBeGone.debug = true` in this build prints ONE diagnostic line per
     restore: `SBG| restore: settingsAtScriptLoad=? firstRun=? saved=? parks=?`
     — that line decides definitively whether this client applies
     SavedVariables before or after addon Lua.
3. **`/spider parks [N]`** — sets the parked-shield count (0 removes them all)
   without hand-editing SavedVariables. `parks` only replaces `kind="park"`
   covers; hover-stuck covers are untouched. This closes the open owner
   decision "keep the 8 defaults?" without a code change.

### The one blocker for M3.5: where is a visible spider on screen?

Facts in hand: **no** world-position/projection APIs on this client
(hard-won fact 6); nameplate **frame** geometry is taint-restricted (NP2);
nameplate **units** enumerate fine (NP1). So we can know *which* spiders are
on screen and *what family* they are, but not yet *where*. Probe battery N1–N7
below picks the position source; each answer maps to a design path.

**Playability note for M3.5 (owner constraint):** pool covers are currently
`EnableMouse(true)` so they can be dragged — which also means a cover blocks
clicks to the world. Auto-tracked covers must be **mouse-through**
(`EnableMouse(false)`), with dragging moved behind an explicit
`/spider arrange` mode. The current stickiness trick (a cover under the
cursor ends the hover) must be replaced by per-unit tracking, since
mouse-through covers no longer interrupt `mouseover`.

## [ARCHIVED — round 1] Resume — in-game state as of 2026-10-15 (before round 2)

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

### Probe battery N1–N8 (round 3; all lines measured ≤255 chars)

Run with 2–3 spiders visible and their nameplates on. Re-run after every
`/reload` (the `SBG2` helper does not survive a reload).

* **N1** — does the spider filter work on nameplate units? (auto-cover depends
  on it; mouse over nothing in particular)
* **N2** — which nameplate/zoom APIs exist at all?
* **N3** — put the **cursor on a spider's nameplate**, then hit-test it.
* **N4** — define the pcall-guarded geometry prober (must run before N5/N6).
* **N5/N6** — which frame getters the client refuses (all should print
  `ok=false` after NP2; `ok=true` on `GetRect`/`GetCenter` would be a win).
* **N7** — can *our* frame anchor to a plate (client does the projection for
  us)? Then read our own point to see if it is live.
* **N8** — read-only distance/zoom values for the dynamic-resize rule.

```ruby
# N1 — spider filter on nameplate units
/run for i=1,8 do local t="nameplate"..i local ok,v=pcall(UnitIsVisible,t) if ok and v then print("SBG2| np"..i.." "..tostring(UnitName(t)).." fam="..tostring(select(2,UnitCreatureFamily(t))).." id="..tostring(UnitCreatureID(t))) end end
```
```ruby
# N2 — API existence
/run print("SBG2| APIs CNP="..tostring(type(C_NamePlate)).." GNPAP="..tostring(type(GetNamePlateAtPosition)).." GNP="..tostring(type(GetNamePlates)).." zoom="..tostring(type(GetCameraZoom)))
```
```ruby
# N3 — cursor MUST be on a spider nameplate when this runs (hit-test lookup)
/run local f=GetNamePlateAtPosition and GetNamePlateAtPosition(GetCursorPosition()) print("SBG2| hit="..tostring(f).." dbg="..tostring(f and GetDebugName and GetDebugName(f)))
```
```ruby
# N4 — prober helper (run first)
/run SBG2={m=function(f,n) local ok,r=pcall(function() local a,b,c,d=f[n](f) return tostring(a)..","..tostring(b)..","..tostring(c)..","..tostring(d) end) print("SBG2| "..n.." ok="..tostring(ok).." v="..tostring(r)) end}
```
```ruby
# N5 — geometry getters (expect ok=false = measurement blocked)
/run local f=_G["NamePlate1"] or _G["nameplate1"] SBG2.m(f,"GetRect") SBG2.m(f,"GetCenter") SBG2.m(f,"GetWidth") SBG2.m(f,"GetEffectiveScale")
```
```ruby
# N6 — identity getters (sanity: does the frame handle work at all?)
/run local f=_G["NamePlate1"] or _G["nameplate1"] SBG2.m(f,"GetName") SBG2.m(f,"GetFrameLevel") SBG2.m(f,"GetParent")
```
```ruby
# N7 — anchor OUR frame to the plate, then read OUR OWN point (our frames are
# not restricted, so if the client honours the anchor we get position for free)
/run local t=_G.SBG2T or CreateFrame("Frame",nil,UIParent) _G.SBG2T=t t:Show() local ok,e=pcall(function() t:SetPoint("CENTER",_G["NamePlate1"],"CENTER") end) print("SBG2| anchor="..tostring(ok).." "..tostring(e))
```
```ruby
/run local _,_,_,x,y=_G.SBG2T:GetPoint(0,UIParent,"BOTTOMLEFT") print("SBG2| anchored own pt: "..tostring(x).." x "..tostring(y))
```
```ruby
# N8 — distance proxy for the dynamic-resize rule (read-only)
/run print("SBG2| zoom="..tostring(GetCameraZoom and GetCameraZoom()).." cvarZoom="..tostring(GetCVar and GetCVar("cameraDistanceMaxZoomFactor")).." plateScale="..tostring(GetCVar and GetCVar("namePlateEnemyScale")))
```

Decision tree:
* **N1 `fam=3`** for the spiders → filter works on nameplate tokens; if nil,
  fall back to name patterns for nameplate units (works today for "Spider").
* **N3 returns a frame** (non-nil) → **hit-test route is alive**: grid-scan the
  screen with `GetNamePlateAtPosition`, group hits by frame identity, derive
  centre + extent → gives BOTH position and apparent size (dynamic resize),
  using read-only lookups only. ~300–600 C calls/sec at 10 Hz — cheap.
* **N5 `ok=true` on `GetRect`/`GetCenter`** → direct geometry after all (best
  case; contradicts NP2 — then NP2's failure was arg-form, not the API).
* **N7 `anchor=true` and the second N7 line prints numbers that change as the
  spider moves** → **anchor route is alive**: our cover frame follows the
  plate, the client does the 3D→UI projection, no measurement by us.
* All three dead → auto-cover is **not implementable** on this client without
  touching protected internals → report to the owner and ship
  mouseover-sticky (their stated fallback) plus `/spider parks`.

### [SUPERSEDED — round 1; results are in the round-2 table above]
### Probe battery P1–P6 / NP1–NP2 — copy-paste lines (kept for the record)

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
15. **`UnitClass` returns the unit's NAME for non-player units (SBG14,
    2026-10-15):** hovering NPC 1504 reported `class="Young Night Web Spider"`.
    `UnitClass(unit) ~= nil` is therefore **not** a player test and rejected
    every spider for a whole round. Player test that works:
    `UnitIsPlayer(unit) == true` (strict boolean) or `UnitName(unit) ==
    UnitName("player")`. Never re-use `UnitClass` as a type discriminator here.
16. **Nameplate frames are client-protected (NP2, 2026-10-15):**
    `_G["NamePlate1"]:GetPoint()` → `Action[FrameMeasurement] failed
    because[Can't measure restricted regions]` + `ForceTaint_Strong`. Nameplate
    **units** (`nameplate1..N` with `UnitName`/`UnitIsVisible`) DO work. Do not
    attempt taint workarounds — the owner has ruled out touching the client's
    own frames (ban risk), and it is also the wrong tool: we only need
    positions, never modifications.
17. **A bare empty SavedVariables table cannot encode "cleared" (SBG13,
    2026-10-15):** `covers[char] = {}` behaved as "never ran" on the next load
    (default parks resurrected over the cleared state; `/spider on` then hid
    them). Encode intent in a wrapper that is never empty
    (`{ init = true, list = {} }`). Related: the restore must not run before
    SavedVariables are in hand — gate it on `VARIABLES_LOADED` (confirmed
    registrable, SBG6).
18. **Show() is deferred; GetPoint returns 9 values (SBG12, 2026-10-15):**
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
- **Slash:** `/spider [on|off|toggle|clear|parks N|help]`, bare = selftest
  (3 `SBG|` lines: version/build/Lua, enabled/interface/char/driver/sticky,
  pool/saved/size).
- **Offline suite:** `lua5.1 tools/test_core.lua` — 81 checks (migration,
  predicate incl. the SBG14 name-as-class regression, sticky on/off, FIFO
  eviction, drag sync, epsilon, per-char persistence, slash, `/spider parks`,
  SBG13 cleared-state + load-order regressions). Run before every in-game round.

Protocol (user does this part; repo is already installed in `AddOns/`):

1. `/reload` — no errors in chat; addon appears in the AddOns list.
2. `/spider` — 3 `SBG|` lines; line 1 must say **`v0.2.2`** (build check);
   `char=` shows the character name. One extra `SBG| restore:` line appears at
   login (v0.2.2 SBG13 diagnostic) — please report it. Eldette's saved state is
   the old v1 "cleared" form, so the first v0.2.2 login migrates it to
   `{init=true, list={}}` and must report `firstRun=false saved=0 parks=0`
   with **no** default discs. `/spider parks 8` brings the discs back.
3. **Probe round 3 (N1–N8) from §Resume (round 2)** — picks the legal position
   source for M3.5. Fix whatever it pins down, re-install, `/reload`, continue.
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

- **Keep the 8 default parked discs?** RESOLVED mechanically in v0.2.2:
  `/spider parks N` (0 = none) — owner can settle it in game, no SavedVariables
  editing, no code change. Still worth an answer for the *default* once M3.5
  lands (auto-cover would make parks pure clutter).
- **Auto-cover semantics (NEW, needed for M3.5):** tracked covers should
  follow the spider while it is visible and then either (a) be released when it
  leaves the nameplate set (pool churn, no residue) or (b) stick where the
  spider was last seen (grows to the 24-slot cap, FIFO). Owner's wording
  ("dynamically moving") points at (a) with an optional stick timeout.
- **Mouse-through + `/spider arrange` (NEW):** auto covers must not eat clicks
  (playability). Dragging moves behind a mode. Needs owner sign-off because it
  changes how parked discs are dragged today.
- **Pool size (NEW):** 24 slots was sized for hover+park use. A screen full of
  Tirisfal spiders may exceed it; needs a cap decision + eviction policy once
  the position source is known (N-probe round).
- **Panic hotkey in v1.0?** `KEY_DOWN` route dead (SBG6); `Bindings.xml` is
  the live candidate (needs an in-game key-binding-UI check); `/spider
  hide` is the guaranteed fallback.
- **v1.0 scope** — current default unless the owner objects: sticky hover
  shield + parkable shields + blind mode + `/spider clear`; frame cover
  optional; panic hotkey TBD.
- Owner requirement already encoded (2026-10-13): covers must **persist** —
  "all spiders should be covered", not just while hovered (`stickyCovers`
  default on).

- **2026-10-15 (c):** Probe round 2 ran. **Issue A closed** — selftest said
  `v0.2.1`, manual `Cover.Save()` wrote 8 entries and they persisted: the new
  build and the alloc-based persistence are both fine. **Issue B root-caused
  and fixed (SBG14)** — `UnitClass("mouseover")` returns the unit's *name* for
  non-players, so the player guard rejected every spider (`IsSpider=false` on
  NPC 1504). **Third bug found and fixed (SBG13)** — cleared cover state was
  forgotten on reload (`covers[char] = {}` looked like "never ran", so the 8
  default parks came back with `saved=0` and `/spider on` then hid them): now a
  v2 `{init,list}` record + `VARIABLES_LOADED`-gated restore + one-shot
  `SBG| restore:` diagnostic. Added `/spider parks N`. NP1 proved nameplate
  **units** work; NP2 proved nameplate **frames** are taint-restricted
  (`Can't measure restricted regions`) — plate-geometry design is dead. Owner
  restated the goal (auto-cover visible spiders while walking, no mouseover,
  dynamic move + resize) and the hard constraint (**UI overlay only, game must
  stay playable, never touch models or client internals**). Shipped as
  **v0.2.2**, offline suite now 81 checks ALL PASS, installed to `AddOns/`.
  Next: probe round 3 (N1–N8) to pick a *legal* position source.

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
- **2026-10-15 (c):** Probe round 2 interpreted. **Issue A CLOSED** (selftest
  `v0.2.1`; manual `Cover.Save()` → 8 entries, persisted across `/spider on`).
  **Issue B root-caused + fixed → SBG14**: `UnitClass("mouseover")` returned
  `"Young Night Web Spider"`, so the "UnitClass non-nil ⇒ player" guard
  rejected every spider (`IsSpider=false` on NPC 1504, `fam=3`). Player guard is
  now `UnitIsPlayer(u) == true` + name comparison. **New bug found in the same
  data → SBG13**: a cleared character was stored as a bare empty table, which
  the next load treated as "never ran" — hence "`/reload` → 8 parks, saved=0"
  and "`/spider on` → discs gone". Fixed with a v2 `{ init = true, list = … }`
  cover record (lazy v1 migration) plus a restore that will not run before
  SavedVariables are in hand (`VARIABLES_LOADED` unlock + bounded C_Timer
  retry) and a one-line `SBG| restore:` diagnostic. Added `/spider parks N`.
  NP1/NP2: nameplate **units** enumerable, nameplate **frames**
  taint-restricted (`Can't measure restricted regions`, `ForceTaint_Strong`) →
  plate-geometry design abandoned (also aligns with the owner's no-tampering
  rule). Shipped **v0.2.2**; offline suite 62 → **81 checks ALL PASS**;
  installed to `AddOns/`. Next: probe round 3 (N1–N8) to choose a *legal*
  screen-position source for M3.5 auto-cover.

## Git

- Everything relevant is committed & pushed (check `git log`; latest:
  `9586588` SBG11/SBG12 fixes + this handoff + 0.2.1 version bump).
  Conventions: direct to `main` (owner decision), lowercase
  conventional-ish messages, tag `v1.0.0` at M6.
- Art regenerates via `python3 tools/make_art.py` (stdlib only) — no binary
  art is ever hand-edited.

## Next session, in order

1. User `/reload`s the installed **v0.2.2** and reports the single
   `SBG| restore: settingsAtScriptLoad=? firstRun=? saved=? parks=?` line
   (decides the SavedVariables load order for good) plus normal M3 behaviour:
   hover a spider → disc appears and sticks; `/spider clear` → gone and stays
   gone across `/reload`; `/spider parks 0` → no parked discs; `/spider parks 8`
   → row of 8; `/spider off|on` behaves.
2. User runs probe round 3 (**N1–N8** in §Resume round 2). Paste every
   `SBG2|` line.
3. Interpret with the N-decision tree → pick the position source:
   anchor-to-plate (N7) > hit-test scan (N3) > direct geometry (N5) > dead end.
4. Implement **M3.5 auto-cover** on that source: per-nameplate-unit slots,
   tick enumeration of `nameplate1..N` filtered by `U.IsSpider`, dynamic
   position each tick, dynamic size from the distance proxy (plate extent if
   available, else `GetCameraZoom`), **mouse-through**, `/spider arrange` for
   dragging, release policy per the owner answer above. Reuse the pool,
   persistence and soft clamp as-is.
5. Keep `lua5.1 tools/test_core.lua` ALL PASS (add nameplate-unit stubs and a
   fake restricted frame so the blocked paths are covered offline), reinstall,
   `diff -r`, commit + push.
6. If every position source is dead: report it and ship mouseover-sticky as the
   product (owner's stated fallback) — say so explicitly, do not fake it.
7. M4: blind mode + panic hotkey (`Bindings.xml` route) + frame cover
   (`TargetFrame`/`FocusFrame` only — those frames are ours to read, unlike
   nameplates).
