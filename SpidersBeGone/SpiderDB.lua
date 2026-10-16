--[[ Spiders Be Gone - curated spider database.

Owner-supplied data (2026-10-15, "here is a list of some known spider names and
locations"): creature IDs of every spider the owner wants covered, annotated
with the zone they live in, plus the name fragments that catch anything the ID
list misses.

Why IDs are the PRIMARY signal (docs/PLAN.md detection):
  * UnitCreatureID is exact - no name guessing, no language issues, and it
    covers creatures whose NAME gives nothing away ("Moss Stalker", "Crypt
    Horror", "Krethis Shadowspinner") and whose creature FAMILY is not Spider.
  * Creature family 3 IS Spider, but the owner's list deliberately includes
    bug-model creatures outside that family (e.g. 15475 Beetle, 16698 Corpse
    Scarab) - the phobia set is the owner's to define, not the family table's.
  * Name fragments stay as the last resort for units whose ID/family the client
    will not report (and for spiders added to the game after this list).

Detection order in Units.lua: id hit -> creature family -> name fragment.
Zone comments are kept on purpose: they are the provenance of each entry and
they power the zone hints (/spider where) once GetZoneText is SBG-verified.
--]]

SBeGone = SBeGone or {}
SBeGone.DB = {
	counts = { ids = 124, patterns = 14 },
	content = "Classic Azeroth baseline; Forever additions detected by family/name",

	-- Creature (entry) IDs, grouped by home zone.
	ids = {
    -- ============================================
    -- Teldrassil
    -- ============================================
    [1986] = true,  -- Webwood Spider
    [1998] = true,  -- Webwood Lurker
    [1999] = true,  -- Webwood Venomfang
    [2000] = true,  -- Webwood Silkspinner
    [2001] = true,  -- Giant Webwood Spider
    [1994] = true,  -- Githyiss the Vile
    [7319] = true,  -- Lady Sathrah

    -- ============================================
    -- Elwynn Forest
    -- ============================================
    [30]   = true,  -- Forest Spider
    [43]   = true,  -- Mine Spider
    [471]  = true,  -- Mother Fang

    -- ============================================
    -- Tirisfal Glades
    -- ============================================
    [1504] = true,  -- Young Night Web Spider
    [1505] = true,  -- Night Web Spider
    [1555] = true,  -- Vicious Night Web Spider
    [1688] = true,  -- Night Web Matriarch
    [10359] = true, -- Sri'skulk

    -- ============================================
    -- Silverpine Forest
    -- ============================================
    [1780] = true,  -- Moss Stalker
    [1781] = true,  -- Mist Creeper
    [12433] = true, -- Krethis Shadowspinner

    -- ============================================
    -- Western Plaguelands
    -- ============================================
    [1821] = true,  -- Carrion Lurker
    [1822] = true,  -- Venom Mist Lurker
    [1824] = true,  -- Plague Lurker

    -- ============================================
    -- Eastern Plaguelands
    -- ============================================
    [8555] = true,  -- Crypt Stalker
    [8556] = true,  -- Crypt Walker
    [8557] = true,  -- Crypt Horror
    [8558] = true,  -- Crypt Slayer

    -- ============================================
    -- Loch Modan
    -- ============================================
    [1184] = true,  -- Cliff Lurker
    [1185] = true,  -- Wood Lurker
    [1195] = true,  -- Forest Lurker
    [14266] = true, -- Shanda the Spinner

    -- ============================================
    -- Wetlands
    -- ============================================
    [1111] = true,  -- Leech Stalker
    [1112] = true,  -- Leech Widow
    [4040] = true,  -- Cave Stalker

    -- ============================================
    -- Redridge Mountains
    -- ============================================
    [442]  = true,  -- Tarantula
    [505]  = true,  -- Greater Tarantula
    [616]  = true,  -- Chatter

    -- ============================================
    -- Duskwood
    -- ============================================
    [217]  = true,  -- Venom Web Spider
    [539]  = true,  -- Pygmy Venom Web Spider
    [569]  = true,  -- Green Recluse
    [574]  = true,  -- Naraxis
    [930]  = true,  -- Black Widow Hatchling
    [949]  = true,  -- Carrion Recluse

    -- ============================================
    -- Swamp of Sorrows
    -- ============================================
    [769]  = true,  -- Deathstrike Tarantula
    [858]  = true,  -- Sorrow Spinner

    -- ============================================
    -- Ashenvale
    -- ============================================
    [3819] = true,  -- Wildthorn Stalker
    [3820] = true,  -- Wildthorn Venomspitter
    [3821] = true,  -- Wildthorn Lurker

    -- ============================================
    -- Stonetalon Mountains
    -- ============================================
    [4005] = true,  -- Deepmoss Creeper
    [4006] = true,  -- Deepmoss Webspinner
    [4007] = true,  -- Deepmoss Venomspitter
    [4263] = true,  -- Deepmoss Hatchling
    [4264] = true,  -- Deepmoss Matriarch
    [11921] = true, -- Besseleth

    -- ============================================
    -- Hillsbrad Foothills
    -- ============================================
    [2348] = true,  -- Elder Moss Creeper
    [2349] = true,  -- Giant Moss Creeper
    [2350] = true,  -- Forest Moss Creeper
    [14279] = true, -- Creepthess

    -- ============================================
    -- Arathi Highlands
    -- ============================================
    [2563] = true,  -- Plains Creeper
    [2565] = true,  -- Giant Plains Creeper

    -- ============================================
    -- Dustwallow Marsh
    -- ============================================
    [4376] = true,  -- Darkmist Spider
    [4377] = true,  -- Darkmist Lurker
    [4378] = true,  -- Darkmist Recluse
    [4379] = true,  -- Darkmist Silkspinner
    [4380] = true,  -- Darkmist Widow
    [4411] = true,  -- Darkfang Lurker
    [4412] = true,  -- Darkfang Creeper
    [4413] = true,  -- Darkfang Spider
    [4414] = true,  -- Darkfang Venomspitter
    [4415] = true,  -- Giant Darkfang Spider

    -- ============================================
    -- Tanaris
    -- ============================================
    [5455] = true,  -- Centipaar Wasp
    [5456] = true,  -- Centipaar Stinger
    [5457] = true,  -- Centipaar Swarmer
    [5458] = true,  -- Centipaar Worker
    [5459] = true,  -- Centipaar Tunneler
    [5460] = true,  -- Centipaar Sandreaver

    -- ============================================
    -- Un'Goro Crater
    -- ============================================
    [6551]  = true, -- Gorishi Wasp
    [6552]  = true, -- Gorishi Worker
    [6553]  = true, -- Gorishi Reaver
    [6554]  = true, -- Gorishi Stinger
    [6555]  = true, -- Gorishi Tunneler
    [9496]  = true, -- Gorishi Egg
    [9498]  = true, -- Gorishi Grub
    [10040] = true, -- Gorishi Hive Guard
    [10041] = true, -- Gorishi Hive Queen

    -- ============================================
    -- Searing Gorge
    -- ============================================
    [5856] = true,  -- Glassweb Spider
    [5857] = true,  -- Searing Lava Spider
    [5858] = true,  -- Greater Lava Spider
    [8277] = true,  -- Rekk'tilac

    -- ============================================
    -- Burning Steppes
    -- ============================================
    [9699]  = true,  -- Fire Beetle

    -- ============================================
    -- Azshara
    -- ============================================
    [8762] = true,  -- Timberweb Recluse

    -- ============================================
    -- Silithus
    -- ============================================
    [11738] = true, -- Sand Skitterer
    [11739] = true, -- Rock Stalker
    [14472] = true, -- Gretheer

    -- ============================================
    -- Blackrock Depths
    -- ============================================
    [8933] = true,  -- Cave Creeper
    [8932] = true,  -- Borer Beetle

    -- ============================================
    -- Dire Maul
    -- ============================================
    [13160] = true, -- Carrion Swarmer

    -- ============================================
    -- Razorfen Downs
    -- ============================================
    [7349] = true,  -- Tomb Fiend
    [7351] = true,  -- Tomb Reaver
    [7355] = true,  -- Tuten'kash

    -- ============================================
    -- Stratholme
    -- ============================================
    [10412] = true, -- Crypt Crawler
    [10413] = true, -- Crypt Beast

    -- ============================================
    -- Scholomance
    -- ============================================
    [11551] = true, -- Necrofiend

    -- ============================================
    -- Blackrock Spire
    -- ============================================
    [10596] = true, -- Mother Smolderweb
    [10375] = true, -- Spire Spiderling
    [10376] = true, -- Crystal Fang

    -- ============================================
    -- Zul'Gurub
    -- ============================================
    [11370] = true, -- Razzashi Broodwidow
    [14532] = true, -- Razzashi Venombrood
    [15041] = true, -- Spawn of Mar'li

    -- ============================================
    -- AQ20, AQ40
    -- ============================================
    [15229] = true, -- Vekniss Soldier
    [15230] = true, -- Vekniss Warrior
    [15233] = true, -- Vekniss Guardian
    [15240] = true, -- Vekniss Hive Crawler
    [15247] = true, -- Qiraji Brainwasher
    [15510] = true, -- Fankriss the Unyielding
    [15511] = true, -- Lord Kri
    [15475] = true, -- Beetle

    -- ============================================
    -- Naxxramas
    -- ============================================
    [15952] = true, -- Maexxna
    [15974] = true, -- Dread Creeper
    [15975] = true, -- Carrion Spinner
    [15976] = true, -- Venom Stalker
    [15977] = true, -- Infectious Skitterer
    [15978] = true, -- Crypt Reaver
    [16573] = true, -- Crypt Guard
    [16698] = true, -- Corpse Scarab

    -- ============================================
    -- The Hinterlands
    -- ============================================
    [2686] = true,  -- Witherbark Broodguard
},

	-- Name fragments, matched case-insensitively against the unit's name.
	patterns = {
    "spider", "tarantula", "webspinner", "silkspinner",
    "venomfang", "darkfang", "widow", "recluse",
    "skitterer", "creeper", "smolderweb", "webwood",
    "nerub", "crypt fiend"
},
}
