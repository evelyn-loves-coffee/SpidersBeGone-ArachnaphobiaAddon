# Classic data sources and scope

The native nameplate overlay needs a visible accessible plate and accessible
creature identification, not a zone/sub-zone database. No location database
was added: the requested conditional dependency does not exist. Static spawn
coordinates would not locate a specific live spider, account for movement,
or recover information withheld by the client.

The owner confirmed that Forever uses **WoW Classic / Vanilla as its content
baseline**. Use that baseline for NPC and area selection; do not treat it as
an unrelated world database. This content baseline does not establish that
every TBC-source map identifier or Lua API behaves identically in Forever.

## Selected source and tradeoffs

The owner selected **LibTourist Classic Era** for general third-party area
metadata instead of Questie/QuestieDB. NoSpider remains credited inspiration
for the native overlay design and is being assessed as a complementary source
of spider-specific information; no additional data has been imported.
Preserve LibTourist's MIT license and original
attribution with any future copied metadata, pin the source version, and
review only the Classic subset and identifiers actually needed.

This decision does not change the current cover's detection or nameplate
attachment. LibTourist is not yet bundled: there is no zone-dependent runtime
feature to consume it. Adding the whole library would not make a cover follow
its model more accurately or make inaccessible unit data available.

LibTourist supplies general geography: zone/instance names and relationships,
map metadata, connections, level ranges and instance entrance locations. It
does not supply a spider NPC catalogue or per-creature spawn coordinates.
Compared with Questie's entity database, we forgo ready-made NPC names/IDs,
spawn records and related quest data that could help expand the curated
spider list or build historical area warnings. Neither source establishes
that an arbitrary creature's model looks like a spider without classification
review.

Consequently, fine-grained spider sub-area warnings, spider spawn markers and
static proximity warnings would need separately curated and licensed
spider-specific records. A general zone catalogue alone cannot implement
them. The existing 124-ID baseline, accessible family/name matching and user
name additions remain available. Classic Era metadata does not guarantee
coverage of Forever additions or compatibility of its map IDs.

## What NoSpider adds to LibTourist

The supplied v1.4.3 folder contains the spider-specific information absent
from LibTourist's general geography. The datasets are complementary:

| NoSpider file | Additional information | Potential use after review |
| --- | --- | --- |
| `SpiderNPCs.lua` | Creature IDs, English/Korean name patterns, dungeon-to-creature associations and entrance pin locations. | Cross-check classification and label spider-bearing dungeons. All 124 IDs in our current baseline already occur among this file's 146 unique ID entries; its 22 other entries are unfiltered and must not be treated as 22 eligible Classic additions. General entrance geography overlaps LibTourist. |
| `SpiderZones.lua` | Explicit spider/bug warning flags for selected outdoor and instance maps. | Historical zone-entry warnings; LibTourist's zone membership alone cannot establish spider presence. |
| `SpiderSubZones.lua` | Selected cave/sub-area warning names, English/Korean aliases and approximate area marker coordinates. | More specific warnings, for example Night Web's Hollow and the Arachnid Quarter. These are curated selected areas, not a complete sub-zone catalogue. |
| `SpiderSpawnData.lua` | Bulk historical spider/bug spawn coordinates merged by map, sourced from Wowhead. | Excluded from import: the published Wowhead terms do not provide the required redistribution grant. A separate applicable permission would be needed; NoSpider's MIT label does not establish it. |

NoSpider lists MIT and credits GrasHopper42. Retain applicable original
notices, the license and README credit with any imported material; document
the selected version and changes. Its own curated records are a useful
candidate complement to LibTourist without requiring Questie. The bulk
Wowhead-derived table has been reviewed against the published terms below
and is excluded without a separate applicable permission.

Any prospective subset needs content review: remove TBC/Wrath zones,
sub-areas, creatures, dungeon associations, aliases and coordinates together.
The supplied tables include Karazhan, Outland and Azjol-Nerub. Some
expansion-added creatures are in Classic geography (for example Tcha'kaz in
the Hinterlands), and spawn coordinates are merged by map: removing an NPC
ID from the detection list would not remove its coordinates from that map.
Verify identifiers and retained coordinates against Forever before use.

Neither source supplies a live unit's screen position or restores access to
restricted identity/position values. These datasets can support historical
area warnings; native accessible nameplates still position covers.

## Online sources reviewed

| Source | Provides | Decision |
| --- | --- | --- |
| [LibTourist Classic Era](https://www.wowace.com/projects/libtourist-classic-era) | Classic zone/instance relationships, localized names, and geographical metadata; the author lists MIT. | Selected source for optional Classic area metadata. No spider classification or per-creature spawn locations; not needed or bundled for nameplate covers. Forever map compatibility requires verification. |
| [QuestieDB's Classic database](https://github.com/Questie/QuestieDB/tree/master/data/Classic) | Classic quest/NPC/object database, migrated from Questie, with a broader scope than this mask. | Excluded by the owner's source choice. Questie lists GPLv3, not MIT, and no separate permissive data grant was found in QuestieDB. No data imported. |
| [NoSpider](https://www.curseforge.com/wow/addons/nospider-arachnophobia-mode) by GrasHopper42 | Spider IDs, area/sub-area warning tables, map overlays and spawn data for TBC Classic. [MIT is listed by the author](https://www.curseforge.com/wow/addons/nospider-arachnophobia-mode/license). | Credited design inspiration. Its original curated records are a candidate complement after Classic filtering and provenance review. Exclude its Wowhead-derived spawn table without separate applicable permission. No files/data copied in this release. |

The supplied NoSpider v1.4.3 folder was inspected in place. Its cover is
parented to the native plate and anchored below it. The separate zone/map
features use the location tables; they are not inputs to the model-cover
position. Its spawn file labels Wowhead as the coordinate source. A project
license label should not be treated as an independent verification of every
bundled upstream dataset's rights or accuracy.

## Wowhead reuse review

Wowhead's [terms page](https://www.wowhead.com/classic/termsofservice) and
[official support article](https://help.zam.com/support/solutions/articles/27000016858-terms-of-service)
identify the [ZAM/Fanbyte terms](https://corp.fanbyte.com/legal/terms), last
updated May 14, 2025. These expressly cover Wowhead:

- Section 4 grants limited internal use and restricts reproduction,
  distribution and sublicensing.
- Section 8 prohibits data mining and specified automated retrieval.
- Section 15 reserves rights in the data and compilation.

A [Wowhead forum response about data export](https://www.wowhead.com/classic-ptr/forums/topic/export-of-wowhead-data-346592)
also states that scraping and exporting its data are not permitted. No public
permissive license or spawn-data redistribution exception was located.

Decision: exclude NoSpider's identifiable Wowhead-derived bulk coordinates
unless a separate applicable permission is established. Attribution or a Lua
format conversion is not such permission. NoSpider's author can license their
own contributions under MIT; that label alone does not establish a right to
relicense an upstream compilation. This is the project's source-selection
decision from the published terms, not a finding about the copyright status
of every individual game fact or NoSpider's possible private permissions.

The supplied collector explicitly retrieves the `tbc` page variant even for
its `NPCS_CLASSIC` list, parses `g_mapperData`, then merges coordinates by
zone. It was inspected only, not executed. Its tables therefore also require
Vanilla content filtering independent of the licensing issue. No new
Wowhead spawn data was downloaded or copied for this review.

## License review: LibTourist and Questie

LibTourist Classic Era's author lists MIT on the project page. The inspected
`WoW-1.15.9-release1` archive (source revision 246, commit
`d2380757a8fe2b1cb2d341817e36e1cd0bccee3a`) also includes `LICENSE.txt`
with the MIT terms, and its main Lua file, which contains the zone tables,
explicitly states `License: MIT` and credits Odica and its predecessor
libraries. No separate restrictive license notice was found in that file.
The archive's license uses placeholder copyright fields; preserve it as
supplied together with the actual author/source attribution rather than
inventing a copyright year or deleting notices. Any future copied subset
must retain the permission notice and applicable original notices, record
the source version and changes, and independently verify Forever map IDs.
This review concerns the main library's metadata, not an automatic license
audit of every bundled dependency.

[Questie's author-published license](https://www.curseforge.com/wow/addons/questie/license)
is GPLv3. GPL-covered code/data may be reused under its conditions, including
preserving notices, supplying the license and source, and marking changes.
When copied tables form part of a derivative combined program, GPLv3 can
require that combined work to be distributed under GPLv3; a separate file
name alone does not establish an independent aggregate. MIT contributions
can be combined into a GPL distribution, but GPL-covered material cannot
simply be relabeled MIT.

The current data repository is QuestieDB. Its
[provenance record](https://github.com/Questie/QuestieDB/blob/master/PROVENANCE.md)
traces the initial tables to Questie commit
`454b9d072965ee8f1a881429260fcf1fac8d60f7`. At review, no separate
license/copying/notice file or permissive data-license header was found in
QuestieDB's tree or inspected Classic NPC table. Provenance is not a new
license grant. Do not assume that the move to another repository removes
Questie's obligations or licenses subsequent changes under MIT. A direct
import needs a clear applicable grant and GPL compliance, or separate
permission from the relevant rights holders.

LibTourist's MIT metadata is the selected source if area metadata becomes
necessary. Neither source has been incorporated into the runtime. The
nameplate cover still needs neither source.

## Current shipped data

`SpidersBeGone/SpiderDB.lua` retains the existing owner-curated baseline,
filtered to 124 IDs. Tcha'kaz (17236) was the lone TBC-introduced entry in
that list and has been removed. The supplied NoSpider collection script
places it in its TBC group despite its Hinterlands location. Filtering by
Classic zone name or continent alone would therefore be insufficient.
Original Classic Naxxramas and its creatures remain in the list: numeric
creature-ID thresholds are not an expansion filter.

The runtime has no zone catalogue, imported spawn data, automatic distance
display, or off-plate warning system. Detection still accepts accessible
spider family/name data for Forever additions. Removing a historical database
entry is not a rule to leave a live spider uncovered if its public data
identifies it as one.

## Rules for a future optional area-warning import

1. Use an explicit reviewed Classic content allowlist for outdoor areas,
   dungeons and raids. Include Original Naxxramas, Ahn'Qiraj, Zul'Gurub and
   other Classic instances where appropriate.
2. Exclude expansion zones and instances, including Eversong Woods,
   Ghostlands, Azuremyst/Bloodmyst, all Outland zones, Blade's Edge Mountains,
   Hellfire Peninsula/Citadel, Karazhan, Shattered Halls and Hyjal Summit.
   Also exclude the Wrath Azjol-Nerub entries found in the supplied sub-zone
   file. Classic geography alone does not establish content eligibility.
3. Filter sub-zone names, translations, aliases, map IDs, NPC memberships,
   and spawn coordinates together. Never import the full TBC tables and
   merely hide their top-level zone labels.
4. Verify map IDs against the running Forever client. TBC UI map IDs,
   Wowhead zone IDs, instance map IDs and localized zone text are distinct
   identifier systems and must not be substituted for one another.
5. A historical warning is advisory. It must not imply that a live spider
   was detected, identify a restricted unit, or determine an overlay's
   screen coordinates. Unknown areas never mean spider-free areas.
6. Preserve the source's required copyright/permission notices with any
   actual copied code/data, document the source version and transformations,
   and acknowledge NoSpider in the README. This release copies none of it.

NoSpider's original curated spider-area records can fill gaps in LibTourist's
general geography after source review. No data import or extra warning
feature is implemented by this research; its identifiable Wowhead-derived
bulk spawn table is excluded without separate applicable permission.
