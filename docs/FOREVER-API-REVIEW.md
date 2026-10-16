> Historical reference only. v0.3.1 removed screen-positioned covers and all editing/input modes. Follow [HANDOFF.md](HANDOFF.md) for the current implementation and test machine. This file is not shipped in the addon ZIP.

# Forever 1.60.1: overlay API and restriction review

Historical audit of v0.2.4. Its implementation gaps are addressed in the
[v0.2.5 update](NATIVE-OVERLAYS.md); live-client validation remains pending.

Reviewed on October 15, 2026, at the user's request. This is a source and
policy review, with no live game-client testing. NoSpider was inspected in
place and left unchanged. No NoSpider code, artwork, libraries, or databases
were copied into SpidersBeGone. The runtime addon and distributed v0.2.4 ZIP
are unchanged by this review.

Recommendation: use an independently implemented, mouse-disabled overlay
parented and anchored to an accessible nameplate. Let the client move it.
Accept unavailable identity/geometry as a coverage limitation; never recover
it through alternate hidden-data channels. v0.2.4 is an experimental tracking
patch, not a verified solution for every restricted area.

## Versions and evidence

- Supplied reference: `C:/Users/chipa/Downloads/NoSpider - v1.4.3/NoSpider`.
  Its TOC declares interface **20505**, a TBC Classic target. The TOC's own
  version field says 1.4.0 despite the archive's v1.4.3 name.
- SpidersBeGone targets interface **16001**. Its older probe record names
  Forever **1.60.1 build 70374**; that record was not independently reproduced
  during this review.
- The inspected Blizzard UI source mirror's `forever` branch resolves to
  commit **b401e0332adfbf0460d319b06d8ea29279a941f1**, whose commit title is
  **1.60.1 (70425)**. References below use that snapshot where possible.
- Published Lua/generated documentation establishes available interfaces and
  intended restrictions. It does not expose every native enforcement rule or
  establish what the user's installed build currently permits.

## What the TBC addon actually does

In NoSpider `Core.lua`, lines 238–279, the model-cover path obtains an overlay
frame, makes it a child of the nameplate, and anchors its top to the plate's
bottom. It does not query the plate's screen center or project world positions
for that cover. Its update handler estimates range for a text label.

Lines 608–627 associate nameplate unit tokens with frames and remove overlays
when the unit leaves. Lines 675 onward periodically rescan visible tokens.
The separate player-map-position/spawn-coordinate logic around lines 515–539
drives proximity warnings; `MapOverlay.lua` draws world-map heatmaps. Those
features are unnecessary for the requested visual mask.

The transferable observation is the standard parent/anchor API pattern, not
a coordinate-recovery algorithm. This review takes no TBC implementation or
its range, combat-log, spawn-warning, or automatic CVar features.

## Restrictions: confirmed mechanisms, runtime-dependent application

| Mechanism | Evidence in the Forever snapshot | Consequence for this addon |
| --- | --- | --- |
| Restricted maps and game states | Restriction types include Map, Combat, Encounter, PvPMatch and others. Secret predicates describe restricted maps including dungeons/raids. | A zone/state transition can change what addon code may inspect. A full map-by-map restriction list was not established. |
| Protected frame operations | Region APIs mark operations such as SetParent and EnableMouse as protected; resizing APIs do likewise for SetPoint. | Whether an operation is allowed depends on the object and context. A normal addon-owned frame is not automatically forbidden, and being out of combat is not a universal permission grant. |
| Forbidden objects/aspects | Script-object APIs expose IsForbidden and checks on forbidden aspects. | Skip inaccessible plates. Do not request forbidden frames or use Blizzard's trusted execution as a workaround. |
| Secret identity or geometry | Unit APIs flag identity queries; frame APIs flag geometry or scale values as potentially secret. | A function existing or returning successfully does not make its result safe for comparisons, arithmetic, table keys, or string matching. |

Sources:
[restriction types](https://github.com/Gethe/wow-ui-source/blob/b401e0332adfbf0460d319b06d8ea29279a941f1/Interface/AddOns/Blizzard_APIDocumentationGenerated/RestrictedActionsConstantsDocumentation.lua),
[secret predicates](https://github.com/Gethe/wow-ui-source/blob/b401e0332adfbf0460d319b06d8ea29279a941f1/Interface/AddOns/Blizzard_APIDocumentationGenerated/SecretPredicatesDocumentation.lua),
[region operations](https://github.com/Gethe/wow-ui-source/blob/b401e0332adfbf0460d319b06d8ea29279a941f1/Interface/AddOns/Blizzard_APIDocumentationGenerated/SimpleScriptRegionAPIDocumentation.lua),
[anchors](https://github.com/Gethe/wow-ui-source/blob/b401e0332adfbf0460d319b06d8ea29279a941f1/Interface/AddOns/Blizzard_APIDocumentationGenerated/SimpleScriptRegionResizingAPIDocumentation.lua),
[forbidden objects](https://github.com/Gethe/wow-ui-source/blob/b401e0332adfbf0460d319b06d8ea29279a941f1/Interface/AddOns/Blizzard_APIDocumentationGenerated/SimpleFrameScriptObjectAPIDocumentation.lua).

These generated definitions include shared systems. Their presence does not
prove every listed restriction is enabled on every Forever build. The
documented C_Secrets.HasSecretRestrictions() and
C_Secrets.ShouldUnitIdentityBeSecret(unit) are relevant capability checks,
when exposed by the running build. See the
[C_Secrets API](https://github.com/Gethe/wow-ui-source/blob/b401e0332adfbf0460d319b06d8ea29279a941f1/Interface/AddOns/Blizzard_APIDocumentationGenerated/SecretPredicateAPIDocumentation.lua).

The repository's recorded `Can't measure restricted regions` errors are
consistent with a real frame restriction, not proof of a Lua language error.
Calling through pcall only catches an error; it neither removes protection
nor demonstrates authorization.

## Tracking choices for Forever

| Choice | Assessment |
| --- | --- |
| C_NamePlate.GetNamePlateForUnit(token) | Documented on the Forever branch. Use its normal default, without requesting forbidden frames. A successful nil result is unavailable coverage. |
| NAME_PLATE_UNIT_ADDED / REMOVED | Documented on Forever. Prefer supported events for lifecycle, with bounded polling as a fallback. Probe the running build because old notes differ. |
| Parent/anchor an addon frame to an accessible plate | Best candidate. Native movement avoids reading screen coordinates. Must be tested in and out of combat, and rejected cleanly if the client blocks it. |
| Plate GetCenter/GetRect/GetPoint | Unnecessary for this design; restricted/secret geometry cannot be converted into usable coordinates by the addon. |
| Read width/effective scale to resize | Only consume values established as accessible. Parenting already inherits scale; fixed local sizes can avoid additional geometry queries. |
| Track arbitrary spider world positions | No working general-purpose world-position plus screen-projection route was established. A unit token is an identity handle, not a screen coordinate. |

Sources: Forever
[nameplate lookup](https://github.com/Gethe/wow-ui-source/blob/b401e0332adfbf0460d319b06d8ea29279a941f1/Interface/AddOns/Blizzard_APIDocumentationGenerated/NamePlateDocumentation.lua),
[nameplate events](https://github.com/Gethe/wow-ui-source/blob/b401e0332adfbf0460d319b06d8ea29279a941f1/Interface/AddOns/Blizzard_APIDocumentationGenerated/NamePlateManagerDocumentation.lua),
[native nameplate attachment examples](https://github.com/Gethe/wow-ui-source/blob/b401e0332adfbf0460d319b06d8ea29279a941f1/Interface/AddOns/Blizzard_NamePlates/Blizzard_NamePlates.lua),
[scale API](https://github.com/Gethe/wow-ui-source/blob/b401e0332adfbf0460d319b06d8ea29279a941f1/Interface/AddOns/Blizzard_APIDocumentationGenerated/SimpleFrameAPIDocumentation.lua).

Blizzard's own trusted UI using a function does not alone establish addon
permission to use it in every context. In particular, do not copy its
issecure()/forbidden-frame handling to seek extra access.

The UnitPositionFrame API was also inspected: its map-ID and ping methods
serve map unit displays, not an established world-model overlay route.
UnitPosition being documented does not establish access to arbitrary enemy
positions. ClosestUnitPosition explicitly marks its returns secret in this
snapshot; it should not be used to recover spider coordinates. See
[unit APIs](https://github.com/Gethe/wow-ui-source/blob/b401e0332adfbf0460d319b06d8ea29279a941f1/Interface/AddOns/Blizzard_APIDocumentationGenerated/UnitDocumentation.lua).

Even successful plate attachment cannot ensure complete model coverage:
hidden/distant plates, corpses, loading transitions, stacking, and screen-edge
clamping can leave models visible or displace their covers. An independent
manual screen shield remains possible without identifying a restricted unit.

## Policy assessment and intended scope

The inspected SpidersBeGone runtime draws addon-owned UI and queries unit
information. It contains no movement/casting/targeting automation, native
memory access, model/game-file patching, range-unlocking, or restriction bypass.
It explicitly disables mouse input during tracking; arrange mode intentionally
enables dragging and stops tracking. Its cover does not change a nameplate's
native hit-test geometry.

My assessment is that a visual-only accessibility mask using normally exposed
APIs is consistent with ordinary UI-addon scope. This is an assessment, not
Blizzard approval or an account-safety guarantee. A callable API and a benign
purpose do not independently certify an addon. The
[UI Add-On Development Policy](https://us.forums.blizzard.com/en/wow/t/ui-add-on-development-policy/24534)
requires EULA compliance, readable/free code, and no harmful impact, and
reserves Blizzard's right to disable functionality. The
[EULA](https://www.blizzard.com/en-us/legal/bfbbb648-bcc6-4b78-a5c7-e2fe20c135df/blizzard-end-user-license-agreement)
prohibits unauthorized cheats, bots and hacks. The policy supplies
WoWUI@blizzard.com for addon-specific questions; nobody was contacted.

Keep the feature limited to the mask and user-controlled sizing. Do not import
NoSpider's additional distance, off-plate detection, spawn or combat-log
features for this request. This is a scope recommendation, not a finding that
those separate features violate policy.

## Remaining work before a verified release

The 168 existing offline checks do not simulate the client's secret-value
system or all combat/forbidden-object rules. Source inspection identifies:

1. `Units.lua`, U.IsSpider: unit names, IDs and family values are compared or
   used in tables/string operations without explicit secret/access checks.
2. `Core.lua`, plateToken/plateShown/plateSize: metadata, visibility, width and
   scale are assumed usable after a successful call. Checks must precede all
   interpretation of restricted results. Reject forbidden handles first.
3. `Core.lua`, PlateFrameFor: the metadata-free indexed-global fallback still
   guesses a unit/frame association. Remove that fallback for a strict
   confirmed-identity mode; unavailable mapping must not become a guessed cover.
4. `Cover.lua`, C.Unanchor: failures when returning a cover to UIParent are
   currently swallowed before anchored state is cleared. A rejected detach
   must not allow later measurement or reuse as an ordinary screen frame.
5. `Core.lua`, Tick: repeated errors switch to sticky hover mode, which uses
   the same unguarded predicate. Restriction handling should stop that unit's
   automatic tracking, clean up or defer safely, and report limited coverage.

These are hardening and validation gaps, not evidence that the addon currently
bypasses Blizzard restrictions. No runtime changes were made in this review.

Test the actual build in open world and a dungeon/raid, both out of combat
and in combat, plus zoning and plate reuse. Check unit-identification access
separately from attachment permission. Verify camera movement/zoom and that
clicks pass through the cover without changing the plate's normal click area.
Do not describe this build as complete until those results are recorded.

Safe initial diagnostics, each under the repository's recorded 255-character
chat-command limit, only report build/capability flags:

```lua
/run print("SBG build:", GetBuildInfo())
/run print("SBG mapper:", type(C_NamePlate and C_NamePlate.GetNamePlateForUnit))
/run local f=C_Secrets and C_Secrets.HasSecretRestrictions; print("SBG secrets enabled:",f and f())
/run local f=C_Secrets and C_Secrets.ShouldUnitIdentityBeSecret; print("SBG target identity secret:",f and f("target"))
```

## License boundary

The NoSpider author's
[project license page](https://www.curseforge.com/wow/addons/nospider-arachnophobia-mode/license)
lists MIT and project ID 1485269, matching the supplied TOC. No top-level
license notice was found in the supplied folder; bundled libraries contain
their own licenses. SpidersBeGone has its own MIT LICENSE.

The chosen approach is independent implementation informed by API usage.
If actual NoSpider code or substantial portions are reused later, preserve
the applicable copyright/permission notice and audit bundled licenses rather
than assuming the project's MIT label covers everything. No attribution to
NoSpider is added as a claim of code reuse, because none occurred here.
