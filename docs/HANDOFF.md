# HANDOFF — resume here (fresh session)

Last updated: **2026-10-14**, after M3 implementation (offline-verified).
A new agent session should start with this file.

## One-line status

**M1, M2, and the M3 implementation are DONE** (M3: sticky hover shield +
parkable shields — code + offline tests all pass; **not yet verified
in-game**). Next step: the **M3 in-game verification protocol** below, then
M4.

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
  1772×1181. Character: Horde Warrior.
- Test spider: "Young Night Web Spider" (NPC **1504**, level 2, Tirisfal
  Glades); `UnitCreatureFamily` → `("Spider", 3)`.

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
10. All probe output should be `SBG|`/`SBG2|`-prefixed via the helper:
    `/run SBG2={p=function(k,v) print(("SBG2| %s: %s"):format(k,tostring(v))) end}`
    (re-run after any `/reload`; cleanup: `/run SBG2=nil`).

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
  (an empty *present* list suppresses the default respawn).
- **Slash:** `/spider [on|off|toggle|clear|help]`, bare = selftest (now 3
  `SBG|` lines: version/build/Lua, enabled/interface/char/driver/sticky,
  pool/saved/size).
- **Offline suite:** `lua5.1 tools/test_core.lua` — 58 checks (migration,
  predicate, sticky on/off, FIFO eviction, drag sync, epsilon, per-char
  persistence, slash). Run before every in-game round.

Protocol (user does this part; repo is already installed in `AddOns/`):

1. `/reload` — no errors in chat; addon appears in the AddOns list.
2. `/spider` — 3 `SBG|` lines; `char=` should show the character name,
   `covers shown=8/24` (first run: 8 parked discs near the top of the
   screen).
3. Hover a Tirisfal spider → a red disc appears over it; move the mouse
   away → the disc **stays**.
4. Drag a disc somewhere else; `/reload` → it is still there.
5. `/spider clear` → all discs gone (and gone after another `/reload`).
6. `/spider off` → hovering a spider shows nothing; `/spider on` →
   saved positions come back.

**M4 after this passes:** blind mode + panic hotkey (`Bindings.xml` route,
§4.5 — verify our XML actually loads via the key-binding UI) + frame cover
(`TargetFrame`/`FocusFrame` only).

## Owner decisions still open

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

## Git

- Everything relevant is committed & pushed (check `git log`; latest:
  M3 implementation + in-game verification protocol). Conventions: `main` branch, lowercase
  conventional-ish messages, tag `v1.0.0` at M6.
- Art regenerates via `python3 tools/make_art.py` (stdlib only) — no binary
  art is ever hand-edited.
