-- Offline smoke test for Spiders Be Gone (M3).
-- Run from the repo root:  lua5.1 tools/test_core.lua
-- Stubs the minimal client API surface as verified on the target client
-- (docs/API-VERIFICATION.md), loads the addon files in TOC order, and
-- exercises: settings migration, predicate, pool FIFO, sticky hover flow,
-- drag sync, per-character persistence, slash commands.
-- Exit code 0 = all pass.

--------------------------------------------------------------------- stubs
local t = 0
GetBuildInfo = function() return "1.60.1", "70374", "Oct 12 2026", "16001" end
GetTime = function() t = t + 0.3; return t end
GetEffectiveScreenInfo = function() return 1772, 1181 end

-- unit database: token -> { name, level, class, famName, famId, id, hostile }
local units = {}
local function setUnit(token, data) units[token] = data end
local function clearUnits()
	for k in pairs(units) do units[k] = nil end
end

UnitName = function(u) local d = units[u]; return d and d.name end
GetUnitName = UnitName
UnitLevel = function(u) local d = units[u]; return (d and d.level) or 0 end
-- SBG14 (in-game 2026-10-15): UnitClass returns the unit's NAME for
-- non-player units on this client, so a non-nil return does NOT mean player.
UnitClass = function(u)
	local d = units[u]
	if not d then return nil end
	if d.player then return d.class end
	return d.class or d.name
end
-- Strict boolean (the guard accepts only == true).
UnitIsPlayer = function(u)
	local d = units[u]
	if d and d.player then return true end
end
UnitCreatureFamily = function(u)
	local d = units[u]
	if not d then return nil, nil end
	return d.famName, d.famId
end
UnitCreatureID = function(u) local d = units[u]; return d and d.id end
-- TWO-ARG client form (SBG5): UnitCanAttack("player", unit) = "can I attack it"
UnitCanAttack = function(unit, target)
	if unit == "player" then
		local d = units[target]
		return (d and d.hostile) or false
	end
	return false
end

UnitExists = function(u) return units[u] ~= nil end
UnitIsVisible = function(u) return units[u] ~= nil end

local cursor = { x = 100, y = 200 }
GetCursorPosition = function() return cursor.x, cursor.y, 1 end

C_Timer = { After = function() end } -- no-op; tests drive SBeGone.Tick()

UIParent = { scale = 1 }
function UIParent:GetEffectiveScale() return self.scale end
SlashCmdList = {}

-- Nameplate stand-in: unit token -> indexed global frame (proven layout in
-- game 2026-10-15: NamePlate1..4 exist, nameplate1..4 answer unit queries).
-- Geometry getters THROW, exactly like the client's restricted regions
-- (SBG15: "Action[FrameMeasurement] failed because[Can't measure restricted
-- regions]") — so any code path that measures a plate, or a frame anchored to
-- one, fails the suite instead of passing silently.
local function makePlate(w, effScale)
	local f = CreateFrame()
	f:SetWidth(w)
	f:SetHeight(w * 0.15)
	f.effScale = effScale
	f.visible = true
	local blocked = function()
		error("Action[FrameMeasurement] failed because[Can't measure restricted regions]", 0)
	end
	f.GetPoint, f.GetRect, f.GetCenter = blocked, blocked, blocked
	return f
end
local function setPlate(idx, plate)
	if plate and plate.unitToken == nil then plate.unitToken = "nameplate" .. idx end
	_G["NamePlate" .. idx] = plate
	return plate
end

-- frame stub with faithful point/size state (GetPoint round-trips SetPoint,
-- which the drag-sync logic depends on)
_G.__frames = {}
local function makeFrame()
	local f = { visible = false, pending = false, points = {}, size = { 0, 0 }, events = {} }
	_G.__frames[#_G.__frames + 1] = f
	-- Client-faithful (SBG12): Show() is deferred to the next display pass;
	-- flushDisplay() below simulates that pass.
	function f:Show() self.pending = true end
	function f:Hide() self.visible = false; self.pending = false end
	function f:IsShown() return self.visible end
	function f:SetParent(parent) self.parent = parent end
	function f:GetParent() return self.parent end
	function f:SetFrameStrata(_) end
	-- Client-faithful (SBG9): SetClampRect and SetSize are ABSENT on this
	-- client — do not stub them, so any direct call fails the suite the
	-- same way it fails in-game.
	function f:EnableMouse(on) self.mouse = on end
	function f:SetMovable(_) end
	function f:SetWidth(w) self.size = { w, self.size[2] } end
	function f:SetHeight(h) self.size = { self.size[1], h } end
	function f:GetWidth() return self.size[1] end
	function f:GetHeight() return self.size[2] end
	-- Nameplates carry their own effective scale (in-game N5: 0.512); plain
	-- frames default to 1 (UIParent scale).
	function f:GetEffectiveScale()
		return self.effScale or (self.parent and self.parent:GetEffectiveScale()) or 1
	end
	function f:ClearAllPoints() self.points = {} end
	function f:SetPoint(anchor, relFrame, relPoint, x, y)
		self.points[1] = {
			anchor = anchor, relFrame = relFrame, relPoint = relPoint,
			x = x or 0, y = y or 0,
		}
	end
	function f:GetPoint(_, relFrame, relPoint)
		local p = self.points[1]
		if not p then return nil end
		if (self.parent and self.parent.restricted) or p.relFrame.restricted then
			error("Can't measure restricted regions", 0)
		end
		if relFrame ~= nil and p.relFrame ~= relFrame then return nil end
		if relPoint ~= nil and p.relPoint ~= relPoint then return nil end
		-- Client-faithful (SBG12): (point, relativeToFrame, relativeToPoint,
		-- x, y, width, height, absX, absY) — offsets are the 4th/5th returns.
		return p.anchor, p.relFrame, p.relPoint, p.x, p.y,
			self.size[1], self.size[2], p.x, p.y
	end
	-- Client-faithful (SBG8): the native CreateTexture rejects layer names
	-- it does not know ("bad argument #3 ... self:CreateTexture(params)");
	-- only the layers proven on this client are accepted (Spoken's working
	-- vanilla branch uses "ARTWORK" and "HIGHLIGHT").
	local VALID_LAYERS = { ARTWORK = true, HIGHLIGHT = true }
	function f:CreateTexture(_, layer)
		if layer ~= nil and not VALID_LAYERS[layer] then
			error("bad argument #3 to 'CreateTexture' (Usage: local texture = self:CreateTexture(params))", 0)
		end
		local tex = {}
		function tex:SetAllPoints(_) end
		function tex:SetPoint(...) end
		function tex:SetTexture(...) end
		function tex:SetVertexColor(...) end
		function tex:SetVertexAlpha(_) end
		return tex
	end
	function f:SetScript(script, handler)
		self.scripts = self.scripts or {}
		-- Client-faithful (SBG10): the native SetScript calls handlers
		-- with NO arguments; event data arrives via the `this`/`event`/
		-- `arg1`..`arg9` globals (Spoken's Compat.lua override proves
		-- the convention). Firing an event = set the globals, call the
		-- stored wrapper.
		self.scripts[script] = function() handler() end
	end
	function f:RegisterEvent(e) self.events[#self.events + 1] = e end
	return f
end
CreateFrame = function() return makeFrame() end

-- One display pass: commits deferred Show()s (SBG12). The real client does
-- this every frame; the suite calls it where a frame boundary is guaranteed
-- before the next observation.
local function flushDisplay()
	for _, f in ipairs(_G.__frames) do
		if f.pending then
			f.visible = true
			f.pending = false
		end
	end
end

------------------------------------------------------------------ settings
-- Pre-existing (partially corrupt) SV table to verify migration on load.
SBeGoneSettings = { enabled = "yes", color = "red", covers = 42, parkCount = 3 }

--------------------------------------------------------------------- load
dofile("SpidersBeGone/SpiderDB.lua")
dofile("SpidersBeGone/Access.lua")
dofile("SpidersBeGone/Units.lua")
dofile("SpidersBeGone/Cover.lua")
dofile("SpidersBeGone/Core.lua")

--------------------------------------------------------------------- checks
local fails = 0
local function check(cond, label)
	if cond then
		print("PASS: " .. label)
	else
		fails = fails + 1
		print("FAIL: " .. label)
	end
end

local function capture(fn)
	local out, real = {}, print
	print = function(s) out[#out + 1] = tostring(s) end
	fn()
	print = real
	return out
end

local function findCover(x, y)
	for i = 1, SBeGone.Cover.MAX do
		local s = SBeGone.Cover.pool[i]
		if s.frame:IsShown() and s.x == x and s.y == y then
			return i, s
		end
	end
	return nil
end

-- v2 record form: covers[char] = { init = true, list = { ... } }
local function savedCount(char)
	local rec = SBeGoneSettings.covers and SBeGoneSettings.covers[char]
	if type(rec) ~= "table" then return -1 end
	local list = (type(rec.list) == "table") and rec.list or rec
	return #list
end

-- ---- settings migration (on load) -------------------------------------
check(SBeGoneSettings.version == 2, "settings: version set to 2 (v2 cover records, SBG13)")
check(SBeGoneSettings.enabled == true, "settings: wrong-type 'enabled' reset to default")
check(type(SBeGoneSettings.color) == "table", "settings: wrong-type 'color' reset to default")
check(type(SBeGoneSettings.covers) == "table", "settings: wrong-type 'covers' reset to default")
check(SBeGoneSettings.parkCount == 3, "settings: valid user value (parkCount=3) kept")
check(SBeGoneSettings.stickyCovers == true, "settings: missing key filled (stickyCovers)")
check(SBeGoneSettings.autoTrack == true, "settings: missing key filled (autoTrack)")
check(SBeGoneSettings.arrange == false, "settings: missing key filled (arrange)")
-- The hover/cursor path is the fallback mode; the M3.5 auto-track suite at the
-- end of this file turns autoTrack back on.
SBeGoneSettings.autoTrack = false

-- ---- slash registration -------------------------------------------------
check(_G.SLASH_SPIDER1 == "/spider", "slash: SLASH_SPIDER1")
check(_G.SLASH_SPIDER2 == "/spidergone", "slash: SLASH_SPIDER2")
check(type(SlashCmdList["SPIDER"]) == "function", "slash: SlashCmdList[SPIDER]")

-- ---- bare /spider = selftest (3 lines, before entering the world) ------
local out = capture(function() SlashCmdList["SPIDER"]("") end)
check(#out == 3, "selftest: prints 3 lines")
check(out[1] and out[1]:find("^SBG| v") ~= nil, "selftest: line 1 version/build")
check(out[1] and out[1]:find("WoW 1%.60%.1") ~= nil and out[1]:find("build 70374") ~= nil
	and out[1]:find("interface 16001") ~= nil,
	"selftest: line 1 reads the four-value GetBuildInfo signature (SBG2)")
check(out[1] and out[1]:find("Lua 5%.1") ~= nil and out[1]:find("Lua Lua") == nil,
	"selftest: Lua label appears once, not 'Lua Lua 5.1' (owner report)")
check(out[2] and out[2]:find("^SBG| enabled=true | char=nil") ~= nil,
	"selftest: line 2 enabled/char")
check(out[3] and out[3]:find("covers shown=0/24") ~= nil
	and out[3]:find("auto=") ~= nil, "selftest: line 3 pool + auto-track state")

out = capture(function() SlashCmdList["SPIDER"]("bogus") end)
check(#out == 1 and out[1]:find("unknown subcommand 'bogus'") ~= nil,
	"slash: unknown subcommand message")
out = capture(function() SlashCmdList["SPIDER"]("help") end)
check(#out == 1 and out[1]:find("on / off / toggle / clear / release / auto N") ~= nil
	and out[1]:find("on|") == nil,
	"slash: help usage line (pipe-free - chat filter, SBG11)")

-- ---- predicate ----------------------------------------------------------
setUnit("t", { name = "Young Night Web Spider", level = 2, famName = "Spider", famId = 3, id = 1504 })
check(SBeGone.Units.IsSpider("t") == true, "predicate: family id 3 -> spider")
setUnit("p", { name = "WarriorGuy", class = "Warrior", player = true,
	famName = "Spider", famId = 3, level = 20 })
check(SBeGone.Units.IsSpider("p") == false, "predicate: player never covered (UnitIsPlayer)")
-- SBG14 regression: the client reports an NPC's class as its NAME; that must
-- not make the guard reject the spider (in-game P3/P4: IsSpider=false).
check(UnitClass("t") == "Young Night Web Spider",
	"predicate: client reports NPC 'class' as the unit name (SBG14)")
check(SBeGone.Units.IsSpider("t") == true,
	"predicate: spider still detected despite name-as-class report (SBG14)")
setUnit("player", { name = "WarriorGuy", class = "Warrior", player = true })
setUnit("p2", { name = "WarriorGuy", famName = "Spider", famId = 3, level = 20 })
check(SBeGone.Units.IsSpider("p2") == false,
	"predicate: same name as the player is never covered (name guard)")
check(SBeGone.Units.IsSpider("t") == true,
	"predicate: spider detection unaffected by a known player unit")
clearUnits()
setUnit("t2", { name = "Gloomweaver", level = 5 })
check(SBeGone.Units.IsSpider("t2") == true, "predicate: name pattern Gloomweaver")
setUnit("t3", { name = "Big Bad Spider", level = 10 })
check(SBeGone.Units.IsSpider("t3") == true, "predicate: name contains Spider")
SBeGoneSettings.extraNames = { "Skitterclaw" }
setUnit("t4", { name = "Skitterclaw", level = 3 })
check(SBeGone.Units.IsSpider("t4") == true, "predicate: extraNames exact match")
SBeGoneSettings.extraNames = {}

-- ---- curated creature-ID database (owner data, SpiderDB.lua) -----------
check(type(SBeGone.DB) == "table" and SBeGone.DB.ids[1504] == true,
	"db: loaded with the owner's spider IDs (1504 Young Night Web Spider)")
check(#SBeGone.DB.patterns >= 14, "db: loaded with the owner's name fragments")

-- Names that give nothing away, filed outside the Spider family: only the ID
-- list can catch these, so it is consulted first.
setUnit("d1", { name = "Moss Stalker", level = 12, famName = "Beast", famId = 1, id = 1780 })
check(SBeGone.Units.IsSpider("d1") == true, "db: 'Moss Stalker' (family Beast) covered by ID 1780")
setUnit("d2", { name = "Crypt Horror", level = 50, id = 8557 })
check(SBeGone.Units.IsSpider("d2") == true,
	"db: 'Crypt Horror' covered by ID even with no creature family reported")
setUnit("d3", { name = "Beetle", level = 1, famName = "Beast", famId = 1, id = 15475 })
check(SBeGone.Units.IsSpider("d3") == true,
	"db: bug-model creature on the owner's list is covered (15475 Beetle)")
setUnit("d4", { name = "Young Scavenger", level = 24, famName = "Beast", famId = 1, id = 1499 })
check(SBeGone.Units.IsSpider("d4") == false,
	"db: a non-spider id (1499 Young Scavenger) is not covered by name or family")
setUnit("d5", { name = "Ash Spider", level = 20, id = 999999, famName = "Beast", famId = 1 })
check(SBeGone.Units.IsSpider("d5") == true,
	"db: an unlisted id still falls through to the name fragment")
setUnit("d6", { name = "WEBWOOD LURKER", level = 20 })
check(SBeGone.Units.IsSpider("d6") == true, "db: fragments match case-insensitively")

-- settings.namePatterns is ADDITIVE (the owner's SavedVariables already holds
-- the old two-entry list; replacing would drop "webwood", "nerub", ...).
SBeGoneSettings.namePatterns = { "Arachnid" }
setUnit("d7", { name = "Giant Arachnid", level = 10 })
check(SBeGone.Units.IsSpider("d7") == true, "db: user fragments are honoured")
setUnit("d8", { name = "Webwood Silkspinner", level = 20 })
check(SBeGone.Units.IsSpider("d8") == true,
	"db: built-in fragments still work while user fragments are set")
SBeGoneSettings.namePatterns = {}
clearUnits()

-- ---- /spider name | names | forget (owner escape hatch) -----------------
out = capture(function() SlashCmdList["SPIDER"](" name Anconan Spider ") end)
check(SBeGoneSettings.extraNames[1] == "Anconan Spider" and #out == 1,
	"name: adds an exact creature name")
setUnit("n1", { name = "anconan spider", level = 20 })
check(SBeGone.Units.IsSpider("n1") == true,
	"name: the named creature is covered straight away (case-insensitive)")
out = capture(function() SlashCmdList["SPIDER"](" name Anconan Spider ") end)
check(#SBeGoneSettings.extraNames == 1 and out[1]:find("already on your") ~= nil,
	"name: duplicates refused instead of growing the list")
out = capture(function() SlashCmdList["SPIDER"](" names ") end)
check(out[1]:find("1 extra name") ~= nil and out[2]:find("Anconan Spider") ~= nil,
	"names: header line plus the list")
out = capture(function() SlashCmdList["SPIDER"](" forget Anconan Spider ") end)
check(#SBeGoneSettings.extraNames == 0 and out[1]:find("forgot") ~= nil,
	"forget: removes the name again")
out = capture(function() SlashCmdList["SPIDER"](" name ") end)
check(out[1]:find("usage") ~= nil, "name: bare form prints usage and changes nothing")
-- 255-char chat limit: a long list must wrap, never truncate mid-name
for i = 1, 20 do
	SlashCmdList["SPIDER"](" name Spider With A Very Long Placeholder Name " .. i .. " ")
end
check(#SBeGoneSettings.extraNames == 20, "name: 20 distinct names accepted")
out = capture(function() SlashCmdList["SPIDER"](" names ") end)
local over = 0
for _, line in ipairs(out) do if #line > 255 then over = over + 1 end end
check(#out >= 3 and over == 0, "names: long list wraps inside the 255-char chat limit")
SBeGoneSettings.extraNames = {}
clearUnits()
setUnit("t5", { name = "Spiderling", level = 5, famName = "Spider", famId = 3 })
SBeGoneSettings.minLevel = 10
check(SBeGone.Units.IsSpider("t5") == false, "predicate: level window excludes")
SBeGoneSettings.minLevel = 1
setUnit("t6", { name = "Spider", level = 3, famName = "Spider", famId = 3, hostile = false })
SBeGoneSettings.requireHostile = true
check(SBeGone.Units.IsSpider("t6") == false, "predicate: requireHostile + friendly -> no")
units["t6"].hostile = true
check(SBeGone.Units.IsSpider("t6") == true, "predicate: requireHostile + hostile -> yes")
SBeGoneSettings.requireHostile = false
clearUnits()

-- ---- enter world via PLAYER_ENTERING_WORLD (SBG10) ----------------------
-- Fresh-login state: no player at TOC load, so the event must do the
-- work. The client calls the OnEvent handler with NO args — the event
-- name arrives via the `event` global.
check(SBeGone.eventFrame ~= nil, "event frame created at load")
check(SBeGone.ready == false, "event: not ready before PLAYER_ENTERING_WORLD")
SBeGoneSettings.parkCount = 8
setUnit("player", { name = "TestWarrior", class = "Warrior" })
_G.this = SBeGone.eventFrame
_G.event = "PLAYER_ENTERING_WORLD"
SBeGone.eventFrame.scripts["OnEvent"]()
_G.event = nil
check(SBeGone.ready == true and SBeGone.char == "TestWarrior",
	"event: PLAYER_ENTERING_WORLD initializes via globals (SBG10)")

-- ---- enter world (first run: default pre-parked shields) ---------------
-- (OnEnterWorld is a guarded no-op here — the event already entered.)
setUnit("player", { name = "TestWarrior", class = "Warrior" })
SBeGone.OnEnterWorld()
check(SBeGone.ready == true, "enter world: ready")
check(SBeGone.Cover.inited == true, "enter world: pool inited")
check(SBeGone.Cover.pool[1].art ~= nil and SBeGone.Cover.pool[1].base ~= nil,
	"pool: textures created under client-faithful layer validation (SBG8)")
check(savedCount("TestWarrior") == 8,
	"enter world: parks saved before any display pass (deferred Show, SBG12)")
flushDisplay()
local sizedSlot
for i = 1, SBeGone.Cover.MAX do
	if SBeGone.Cover.pool[i].frame:IsShown() then sizedSlot = i; break end
end
check(sizedSlot ~= nil
	and SBeGone.Cover.pool[sizedSlot].frame.size[1] == 96
	and SBeGone.Cover.pool[sizedSlot].frame.size[2] == 96,
	"resize: SetSize absent -> SetWidth/SetHeight fallback (SBG9)")
check(SBeGone.Cover.ShownCount() == 8, "enter world: 8 default parked shields")
local trec = SBeGoneSettings.covers["TestWarrior"]
check(trec and trec.init == true and type(trec.list) == "table",
	"save: v2 record written (cleared state cannot look like 'never ran', SBG13)")
check(trec and trec.list[1].kind == "park", "enter world: saved kind=park")

-- ---- sticky hover flow --------------------------------------------------
setUnit("mouseover",
	{ name = "Young Night Web Spider", level = 2, famName = "Spider", famId = 3, id = 1504 })
cursor.x, cursor.y = 300, 400
SBeGone.Tick()
flushDisplay()
check(SBeGone.Cover.ShownCount() == 9, "hover: cover allocated (9 shown)")
local slotIdx, slot = findCover(300, 400)
check(slotIdx ~= nil and slot.kind == "hover", "hover: cover at cursor, kind=hover")
cursor.x = 310
SBeGone.Tick()
check(slotIdx ~= nil and SBeGone.Cover.pool[slotIdx].x == 310, "hover: cover follows cursor")
clearUnits()
setUnit("player", { name = "TestWarrior", class = "Warrior" })
SBeGone.Tick()
check(SBeGone.Cover.ShownCount() == 9, "sticky: cover stays after mouse leaves")
check(SBeGone.hover.slot == nil, "sticky: hover state released")
check(savedCount("TestWarrior") == 9, "sticky: 9 covers saved")

-- ---- sticky off: cover releases ----------------------------------------
SBeGoneSettings.stickyCovers = false
setUnit("mouseover",
	{ name = "Young Night Web Spider", level = 2, famName = "Spider", famId = 3, id = 1504 })
cursor.x, cursor.y = 500, 500
SBeGone.Tick()
flushDisplay()
check(SBeGone.Cover.ShownCount() == 10, "sticky off: cover allocated")
clearUnits()
setUnit("player", { name = "TestWarrior", class = "Warrior" })
SBeGone.Tick()
check(SBeGone.Cover.ShownCount() == 9, "sticky off: cover released on leave")
SBeGoneSettings.stickyCovers = true

-- ---- pool FIFO eviction --------------------------------------------------
SBeGone.Cover.ClearAll()
local first = SBeGone.Cover.Allocate("hover", 10, 10)
for i = 2, SBeGone.Cover.MAX do
	SBeGone.Cover.Allocate("hover", 10 + i, 10)
end
local extra = SBeGone.Cover.Allocate("hover", 999, 999)
flushDisplay()
check(SBeGone.Cover.ShownCount() == 24, "pool: capped at 24")
check(extra == first, "pool: FIFO evicts the oldest slot")
check(SBeGone.Cover.pool[extra].x == 999, "pool: evicted slot reused at new position")
SBeGone.Cover.ClearAll()

-- ---- /spider clear -------------------------------------------------------
SlashCmdList["SPIDER"]("clear")
check(SBeGone.Cover.ShownCount() == 0, "clear: all covers hidden")
check(savedCount("TestWarrior") == 0, "clear: saved list emptied (present, not nil)")

-- ---- /spider off / on ----------------------------------------------------
SlashCmdList["SPIDER"]("on")
check(SBeGone.Cover.ShownCount() == 0, "on: restore does not respawn after explicit clear")
setUnit("mouseover",
	{ name = "Young Night Web Spider", level = 2, famName = "Spider", famId = 3, id = 1504 })
SBeGone.Tick()
flushDisplay()
check(SBeGone.Cover.ShownCount() == 1, "on: hover works again")
SlashCmdList["SPIDER"]("off")
check(SBeGoneSettings.enabled == false, "off: enabled=false")
check(SBeGone.Cover.ShownCount() == 0, "off: all covers hidden")
SBeGone.Tick()
check(SBeGone.Cover.ShownCount() == 0, "off: hovering does not spawn covers")
SlashCmdList["SPIDER"]("on")
check(SBeGoneSettings.enabled == true, "on: re-enabled")
clearUnits()

-- ---- drag sync + place epsilon -------------------------------------------
SBeGone.Cover.ClearAll()
SBeGone.Cover.Save()
local di = SBeGone.Cover.Allocate("hover", 300, 400)
flushDisplay()
SBeGone.Cover.pool[di].frame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", 777, 888)
SBeGone.Cover.SyncDrags()
check(SBeGone.Cover.pool[di].x == 777 and SBeGone.Cover.pool[di].y == 888,
	"drags: dragged position adopted")
check(savedCount("TestWarrior") == 1 and SBeGoneSettings.covers["TestWarrior"].list[1].x == 777,
	"drags: dragged position saved")
SBeGone.Cover.Place(di, 777.4, 888.2)
check(SBeGone.Cover.pool[di].frame.points[1].x == 777,
	"place: sub-pixel movement ignored (epsilon)")
SBeGone.Cover.pool[di].frame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", 99999, -50)
SBeGone.Cover.SyncDrags()
check(SBeGone.Cover.pool[di].x == 1772 and SBeGone.Cover.pool[di].y == 0,
	"drags: off-screen drag soft-clamped to screen bounds (SBG9)")

-- ---- per-character persistence -------------------------------------------
SBeGoneSettings.covers["OtherChar"] = {
	{ x = 500, y = 500, w = 80, h = 80, kind = "hover" },
}
SBeGone.ready = false
SBeGone.char = nil
clearUnits()
setUnit("player", { name = "OtherChar", class = "Warrior" })
SBeGone.OnEnterWorld()
flushDisplay()
check(SBeGone.char == "OtherChar", "chars: switched character")
check(SBeGone.Cover.ShownCount() == 1, "chars: OtherChar's saved cover restored")
local oc = SBeGone.Cover.pool
local found = false
for i = 1, SBeGone.Cover.MAX do
	if oc[i].frame:IsShown() and oc[i].x == 500 then
		found = oc[i].w == 80 and oc[i].h == 80
	end
end
check(found, "chars: restored cover size 80x80")
check(savedCount("TestWarrior") == 1, "chars: TestWarrior's list untouched")
check(SBeGoneSettings.covers["OtherChar"].init == true
	and #SBeGoneSettings.covers["OtherChar"].list == 1,
	"migrate: v1 bare list upgraded to v2 record without losing the cover")

SBeGone.ready = false
SBeGone.char = nil
clearUnits()
setUnit("player", { name = "FreshChar", class = "Warrior" })
SBeGone.OnEnterWorld()
flushDisplay()
check(SBeGone.Cover.ShownCount() == 8, "chars: fresh character gets 8 default parks")
check(savedCount("FreshChar") == 8, "chars: fresh character's parks saved")

-- ---- /spider parks -------------------------------------------------------
SBeGone.ready = false
SBeGone.char = nil
clearUnits()
setUnit("player", { name = "TestWarrior", class = "Warrior", player = true })
SBeGone.OnEnterWorld()
flushDisplay()
check(SBeGone.Cover.ShownCount() == 1, "parks: TestWarrior restored (1 cover, no respawn)")
out = capture(function() SlashCmdList["SPIDER"]("parks") end)
check(#out == 1 and out[1]:find("parked shields = 8") ~= nil,
	"parks: bare form reports the count")
-- /spider parks manages kind="park" covers only; hover-stuck covers stay.
local function countKind(kind)
	local n = 0
	for i = 1, SBeGone.Cover.MAX do
		local sl = SBeGone.Cover.pool[i]
		if sl.frame:IsShown() and sl.kind == kind then n = n + 1 end
	end
	return n
end
SlashCmdList["SPIDER"]("parks 3")
flushDisplay()
check(SBeGoneSettings.parkCount == 3, "parks: parkCount set to 3")
check(countKind("park") == 3,
	"parks: old parks removed, 3 new parked")
check(SBeGone.Cover.ShownCount() == 4 and savedCount("TestWarrior") == 4,
	"parks: hover cover kept alongside the 3 parks, all saved")
SlashCmdList["SPIDER"]("parks 0")
flushDisplay()
check(countKind("park") == 0 and SBeGone.Cover.ShownCount() == 1
	and savedCount("TestWarrior") == 1,
	"parks 0: parked shields removed and saved, hover cover untouched")

-- ---- cleared state survives a relog (SBG13 regression) -------------------
SlashCmdList["SPIDER"]("clear")
check(SBeGone.Cover.ShownCount() == 0, "clear: all covers hidden")
SBeGone.ready = false
SBeGone.char = nil
SBeGone.OnEnterWorld()
flushDisplay()
check(SBeGone.Cover.ShownCount() == 0,
	"SBG13: cleared character is NOT re-parked on the next restore")
check(savedCount("TestWarrior") == 0, "SBG13: cleared record stays empty")

-- ---- restore waits for SavedVariables (SBG13 load order) -----------------
SBeGone.ready = false
SBeGone.char = nil
SBeGone.sawVariablesLoaded = nil
SBeGone.loadSnapshot.settingsPresent = false
check(SBeGone.OnEnterWorld() == false,
	"SBG13: restore refused when settings were not applied at script load")
check(SBeGone.ready == false, "SBG13: still not ready (no guess-restored)")
_G.this = SBeGone.eventFrame
_G.event = "VARIABLES_LOADED"
SBeGone.eventFrame.scripts["OnEvent"]()
_G.event = nil
check(SBeGone.sawVariablesLoaded == true and SBeGone.ready == true,
	"SBG13: VARIABLES_LOADED unlocks the restore")

--------------------------------------------------------------------- result
-- ============================================================ M3.5 auto-track
-- The owner's actual goal (2026-10-15): walk toward spiders, no targeting and
-- no mouseover, and a cover appears over each spider model, moving and
-- resizing with it. Client facts this rests on (in game, same day):
--   * nameplate1..4 exist as tokens AND as _G["NamePlate1"..4] (NP1)
--   * UnitCreatureFamily works on plate tokens (spider fam=3, beast fam=1)
--   * plate GetWidth / GetEffectiveScale answer (N5: 142.5, 0.512)
--   * plate GetRect / GetCenter / GetPoint THROW (SBG15) — the makePlate stub
--     throws too, so measuring anything plate-related fails the suite
--   * anchoring our own frame to a plate is allowed (N7: "anchor=true")

SBeGoneSettings.autoTrack = true
SBeGone.track = {}
SBeGone.hoverByKey = {}
SBeGone.hover = { slot = nil, key = nil }
clearUnits()
setUnit("player", { name = "TestWarrior", class = "Warrior" })
SBeGone.Cover.ClearAll()

local plateA = setPlate(1, makePlate(100, 0.5)) -- apparent width 50 UI units
local plateB = setPlate(2, makePlate(100, 0.5))
plateA.unitToken, plateB.unitToken = "nameplate1", "nameplate2"
plateA.restricted, plateB.restricted = true, true
setUnit("nameplate1",
	{ name = "Young Night Web Spider", level = 24, famName = "Spider", famId = 3, id = 1504 })
setUnit("nameplate2", { name = "Young Scavenger", level = 24, famId = 1, id = 1499 })

SBeGone.Tick()
flushDisplay()
local trA = SBeGone.track.nameplate1
check(SBeGone.Cover.ShownCount() == 1,
	"track: one cover for the visible spider, none for the beast (no mouseover needed)")
check(trA ~= nil and SBeGone.Cover.pool[trA].kind == "track", "track: cover kind is track")
check(SBeGone.Cover.pool[trA].anchored == true, "track: cover is anchored to the plate")
local ptA = SBeGone.Cover.pool[trA].frame.points[1]
check(ptA and ptA.relFrame == plateA and ptA.anchor == "CENTER" and ptA.relPoint == "CENTER",
	"track: anchored to the plate frame itself (client moves it, not us)")
local trackedFrame = SBeGone.Cover.pool[trA].frame
check(trackedFrame:GetParent() == plateA,
	"track: cover belongs to the moving nameplate instead of the screen root")
-- 160 plate-local units render as 80 UI units at scale 0.5.
check(SBeGone.Cover.pool[trA].w == 160 and trackedFrame:GetWidth() * trackedFrame:GetEffectiveScale() == 80,
	"track: plate-local cover size inherits distance scale exactly once")
-- drop = 0.9 cover-heights below the plate (models hang below their nameplate)
check(ptA and math.abs((ptA.y or 0) * trackedFrame:GetEffectiveScale() + 72) < 0.001,
	"track: centred below the plate by the drop factor")

-- The renderer owns plate coordinates; the addon may not query them. Move
-- that native transform without a Lua tick and resolve only inside the stub.
local function renderedCenter(frame)
	local point = frame.points[1]
	local parent = frame:GetParent()
	if parent == point.relFrame and parent.nativeX then
		return parent.nativeX + point.x * frame:GetEffectiveScale(),
			parent.nativeY + point.y * frame:GetEffectiveScale()
	end
	return point.x, point.y
end
plateA.nativeX, plateA.nativeY = 500, 400
local rx, ry = renderedCenter(trackedFrame)
check(rx == 500 and ry == 328, "track: native transform places the cover below its spider plate")
plateA.nativeX, plateA.nativeY = 750, 350
rx, ry = renderedCenter(trackedFrame)
check(rx == 750 and ry == 278,
	"track: native model movement moves its cover before the next polling tick")

-- Perspective changes between the 10 Hz scans: native parenting must scale
-- BOTH the disc and its offset immediately, without another Lua update.
plateA.effScale = 1
check(trackedFrame:GetWidth() * trackedFrame:GetEffectiveScale() == 160
	and ptA.y * trackedFrame:GetEffectiveScale() == -144,
	"track: camera zoom scales the cover and drop between polling ticks")
SBeGone.Tick()
check(trackedFrame:GetWidth() == 160,
	"track: next poll does not apply the inherited plate scale a second time")
plateA.effScale = 0.5

-- The plate gets bigger (camera moves in): the cover grows on the next tick.
plateA:SetWidth(200)
SBeGone.Tick()
check(SBeGone.Cover.pool[trA].w == 320, "track: cover grows when the plate's local width grows")

-- Tracked covers are not persisted (their position belongs to a spider that
-- will not exist next session, and an anchored frame cannot be measured).
SBeGone.Cover.Save()
check(savedCount("TestWarrior") == 0, "track: anchored covers are not written to SavedVariables")

-- Frame IDs are pool allocation IDs, not unit IDs. Swap the globals without
-- changing the creatures, just as the client does when plates are recycled.
setPlate(1, plateB)
setPlate(2, plateA)
SBeGone.Tick()
check(SBeGone.Cover.pool[trA].frame:GetParent() == plateA,
	"track: reordered frame numbers still follow the spider's unit token")
check(SBeGone.PlateFrameFor("nameplate2", 2) == plateB,
	"lookup: a recycled numeric suffix never overrides explicit unit identity")
setPlate(1, plateA)
setPlate(2, plateB)

local mapped = makePlate(100, 0.5)
mapped.unitToken = "nameplate1"
C_NamePlate = { GetNamePlateForUnit = function() return mapped end }
SBeGone.Tick()
check(SBeGone.track.nameplate1 == trA and trackedFrame:GetParent() == mapped,
	"track: a changed public mapping reparents the existing cover without duplicating it")
mapped.unitToken = "nameplate2"
check(SBeGone.PlateFrameFor("nameplate1", 1) == nil,
	"lookup: a mapper returning a different unit is rejected")
C_NamePlate.GetNamePlateForUnit = function() return nil end
SBeGone.Tick()
check(SBeGone.track.nameplate1 == nil and not SBeGone.Cover.IsAllocated(trA),
	"track: valid unit with no mapped plate releases its cover instead of sticking forever")
check(trackedFrame:GetParent() == UIParent,
	"track: released covers leave the nameplate's movement and scale tree")
C_NamePlate = nil

-- The reduced client may expose GetUnit(), UnitFrame.unit, or no metadata.
local lookup = setPlate(3, makePlate(100, 1))
lookup.GetUnit = function() return "nameplate4" end
check(SBeGone.PlateFrameFor("nameplate4", 4) == lookup,
	"lookup: GetUnit resolves a plate whose frame number differs from its token")
lookup.GetUnit = nil
lookup.unitToken = nil
lookup.UnitFrame = { unit = "nameplate4" }
check(SBeGone.PlateFrameFor("nameplate4", 4) == lookup,
	"lookup: UnitFrame.unit resolves the reduced client's plate")
lookup.UnitFrame = nil
lookup.unitToken = nil
check(SBeGone.PlateFrameFor("nameplate3", 3) == nil,
	"lookup: metadata-free clients do not guess frame ownership from numbers")
lookup:Hide()
check(SBeGone.PlateFrameFor("nameplate3", 3) == nil,
	"lookup: hidden pooled frames cannot own a live cover")
setPlate(3, nil)

-- UI scale is independent of distance scale, including the existing visual
-- bounds. A missing width falls back to the configured size in UI units.
UIParent.scale = 0.8
plateA.effScale = 0.4
plateA:SetWidth(100)
SBeGone.Tick()
trA = SBeGone.track.nameplate1
trackedFrame = SBeGone.Cover.pool[trA].frame
check(trackedFrame:GetWidth() * trackedFrame:GetEffectiveScale() / UIParent.scale == 80,
	"track: non-default UI scale stays independent of perspective scale")
plateA:SetWidth(10000)
SBeGone.Tick()
check(trackedFrame:GetWidth() * trackedFrame:GetEffectiveScale() / UIParent.scale == 512,
	"track: maximum cover size remains 512 UI units after parenting")
plateA:SetWidth(1)
SBeGone.Tick()
check(trackedFrame:GetWidth() * trackedFrame:GetEffectiveScale() / UIParent.scale == 16,
	"track: minimum cover size remains 16 UI units after parenting")
local getWidth = plateA.GetWidth
plateA.GetWidth = nil
SBeGone.Tick()
check(math.abs(trackedFrame:GetWidth() * trackedFrame:GetEffectiveScale() / UIParent.scale - SBeGone.Cover.Size()) < 0.000001,
	"track: unavailable plate width uses the fixed UI size without double scaling")
plateA.GetWidth = getWidth
UIParent.scale, plateA.effScale = 1, 0.5
plateA:SetWidth(100)

-- A token changing to a non-spider is positive evidence of reuse. Grace
-- applies only to a missing token, never to a known different creature.
setUnit("nameplate1", { name = "Young Scavenger", level = 24, famId = 1, id = 1499 })
SBeGone.Tick()
check(SBeGone.track.nameplate1 == nil and not trackedFrame:IsShown(),
	"track: token reuse for a non-spider removes the old cover on the first tick")
setUnit("nameplate1", { name = "Forest Spider", level = 24, famId = 3, id = 1504 })
SBeGone.Tick()
flushDisplay()
trA = SBeGone.track.nameplate1

-- Spider walks away: grace first, then release.
units.nameplate1 = nil
SBeGone.Tick()
check(SBeGone.Cover.ShownCount() == 1, "track: brief loss of the plate does not strobe the cover")
for _ = 1, 6 do SBeGone.Tick() end
flushDisplay()
check(SBeGone.Cover.ShownCount() == 0 and SBeGone.track.nameplate1 == nil,
	"track: cover is auto-released once the spider is gone")
local released = SBeGone.Cover.pool[trA].frame
local reused = SBeGone.Cover.Allocate("hover", 350, 250)
check(reused == trA and released:GetParent() == UIParent and released:GetEffectiveScale() == 1,
	"pool: a formerly tracked slot becomes an ordinary screen cover when reused")
local dragOK = pcall(SBeGone.Cover.SyncDrags)
check(dragOK, "pool: released plate children can be measured again without restricted geometry")
SBeGone.Cover.Release(reused)

local refused = SBeGone.Cover.AllocateUnpositioned("track", "track")
local refusedFrame = SBeGone.Cover.pool[refused].frame
local originalParent = refusedFrame.SetParent
refusedFrame.SetParent = function(self, parent)
	if parent == plateA then error("parenting refused", 0) end
	return originalParent(self, parent)
end
check(not SBeGone.Cover.PlaceTracked(refused, plateA, 50),
	"track: client parenting refusal is reported as an attachment failure")
SBeGone.Cover.Release(refused)
check(refusedFrame:GetParent() == UIParent and not refusedFrame:IsShown(),
	"track: refused attachment leaves no visible orphaned cover")
refusedFrame.SetParent = originalParent

-- Eviction preference: a full pool of parked shields is not eaten while
-- tracked covers exist to sacrifice instead.
SBeGone.Cover.ClearAll()
local parkSlot = SBeGone.Cover.Allocate("park", 10, 10)
-- bounded: the pool holds MAX slots, and frames only become "shown" when the
-- display queue is flushed, so never loop on ShownCount here
for _ = 2, SBeGone.Cover.MAX do
	SBeGone.Cover.Allocate("park", 20, 20)
end
local t1 = SBeGone.Cover.Allocate("track", nil, nil, "track")
local t2 = SBeGone.Cover.Allocate("track", nil, nil, "track")
check(t2 == t1, "pool: a new tracked cover sacrifices another TRACKED cover first")
check(SBeGone.Cover.IsAllocated(parkSlot), "pool: parked shields survive preferential eviction")

-- arrange mode: covers take the mouse, tracking stops, nothing follows.
SBeGone.Cover.ClearAll()
setUnit("nameplate1",
	{ name = "Young Night Web Spider", level = 24, famId = 3, id = 1504 })
SBeGone.Tick()
flushDisplay()
check(SBeGone.Cover.ShownCount() == 1, "arrange: tracking active before arrange mode")
capture(function() SlashCmdList["SPIDER"]("arrange on") end)
flushDisplay()
check(SBeGoneSettings.arrange == true and SBeGone.Cover.ShownCount() == 0,
	"arrange on: tracked covers released so they can be dragged")
SBeGone.Tick()
check(SBeGone.Cover.ShownCount() == 0, "arrange: no tracking while arranging (covers stay put)")
local interactive = true
for i = 1, SBeGone.Cover.MAX do
	if SBeGone.Cover.pool[i].frame.mouse ~= true then interactive = false end
end
check(interactive, "arrange: every cover accepts the mouse so it can be dragged")
capture(function() SlashCmdList["SPIDER"]("arrange off") end)
check(SBeGoneSettings.arrange == false and SBeGone.Cover.pool[1].frame.mouse == false,
	"arrange off: covers are click-through again (a disc must not eat clicks)")
SBeGone.Tick()
flushDisplay()
check(SBeGone.Cover.ShownCount() == 1, "arrange off: tracking resumes")

-- /spider release clears tracked + sticky covers and keeps parked shields.
SBeGone.Cover.ClearAll()
SBeGoneSettings.autoTrack = false
setUnit("mouseover",
	{ name = "Young Night Web Spider", level = 2, famId = 3, id = 1504 })
SBeGone.Tick()
flushDisplay()
local stickySlot = SBeGone.hover.slot
clearUnits()
setUnit("player", { name = "TestWarrior", class = "Warrior" })
setUnit("nameplate1",
	{ name = "Young Night Web Spider", level = 24, famId = 3, id = 1504 })
SBeGone.Tick()
SBeGoneSettings.autoTrack = true
SBeGone.Tick()
flushDisplay()
check(SBeGone.Cover.ShownCount() == 2, "release setup: one sticky hover cover + one tracked cover")
capture(function() SlashCmdList["SPIDER"]("release") end)
flushDisplay()
check(SBeGone.Cover.ShownCount() == 0 and next(SBeGone.track) == nil
	and next(SBeGone.hoverByKey) == nil,
	"release: tracked and sticky covers both gone (owner's clean-up command)")

-- /spider auto off falls back to the cursor mode and releases what it held.
SBeGone.Tick()
flushDisplay()
capture(function() SlashCmdList["SPIDER"]("auto off") end)
flushDisplay()
check(SBeGoneSettings.autoTrack == false and SBeGone.Cover.ShownCount() == 0,
	"auto off: tracking stops and its covers are released")

-- Tunables are settable from chat (the owner needs to tune drop/size live).
capture(function() SlashCmdList["SPIDER"]("grow 2.5") end)
check(SBeGoneSettings.trackScale == 2.5, "slash: /spider grow sets the plate-relative size")
capture(function() SlashCmdList["SPIDER"]("drop 0.4") end)
check(SBeGoneSettings.drop == 0.4, "slash: /spider drop sets the below-plate offset")
capture(function() SlashCmdList["SPIDER"]("drop 99") end)
check(SBeGoneSettings.drop == 4, "slash: drop clamped to the safe range")
capture(function() SlashCmdList["SPIDER"]("size 120") end)
check(SBeGoneSettings.coverSize == 120, "slash: /spider size sets the fixed cover size")


-- ---- recycled indices must not be adopted (regression, found by this suite) --
-- Pool indices are reused, so "is this index allocated" is NOT an identity:
-- a stale tracking entry used to adopt a sticky hover cover and anchor it to a
-- plate. Both maps plus the slot kind now have to agree.
SBeGone.Cover.ClearAll()
SBeGoneSettings.autoTrack = false
setUnit("mouseover",
	{ name = "Young Night Web Spider", level = 2, famId = 3, id = 1504 })
SBeGone.Tick()
flushDisplay()
local owned = SBeGone.hover.slot
clearUnits()
setUnit("player", { name = "TestWarrior", class = "Warrior" })
SBeGone.Tick() -- sticky cover stays where it is
SBeGone.track.nameplate1 = owned -- poison: recycled index belonging to the hover cover
SBeGone.trackSlots[owned] = nil
SBeGoneSettings.autoTrack = true
SBeGone.Tick()
flushDisplay()
check(SBeGone.track.nameplate1 ~= owned, "track: a recycled index is never adopted")
check(SBeGone.Cover.KindOf(owned) == "hover", "track: the sticky cover keeps its own slot")
check(SBeGone.Cover.pool[owned].anchored ~= true,
	"track: the sticky cover is not dragged onto a nameplate")

-- Arrange mode must never survive a session: a stale "true" in
-- SavedVariables would mean every cover eats clicks at login.
SBeGoneSettings.arrange = true
SBeGone.ready = false
SBeGoneSettings.covers["Newbie"] = nil
clearUnits()
setUnit("player", { name = "Newbie", class = "Hunter" })
SBeGone.OnEnterWorld()
flushDisplay()
check(SBeGoneSettings.arrange == false, "arrange: not carried across a session")
local clickThrough = true
for i = 1, SBeGone.Cover.MAX do
	if SBeGone.Cover.pool[i].frame.mouse ~= false then clickThrough = false end
end
check(clickThrough, "arrange: a fresh session starts click-through (covers never eat clicks)")
SBeGoneSettings.arrange = false

-- Invariant: after churn, no bookkeeping entry points at a slot we do not own.
for _ = 1, SBeGone.Cover.MAX do SBeGone.Cover.Allocate("park", 5, 5) end
SBeGone.Tick()
local strays = 0
for slot, token in pairs(SBeGone.trackSlots) do
	if SBeGone.Cover.KindOf(slot) ~= "track" or SBeGone.track[token] ~= slot then
		strays = strays + 1
	end
end
check(strays == 0, "track: eviction drops entries instead of leaving strays")

-- Sticky hover entries obey the same identity rule as tracking (SBG16): pool
-- indices are recycled, so a stale hover entry must not adopt another cover.
SBeGoneSettings.autoTrack = false
SBeGone.Cover.ClearAll()
SBeGone.ResetTrack()
local stickyIdx = SBeGone.Cover.Allocate("hover", 300, 300)
SBeGone.hover = { slot = nil, key = nil }
SBeGone.hoverByKey["Forest Spider|1"] = stickyIdx
SBeGone.Cover.Release(stickyIdx)
SBeGone.Cover.Allocate("track", nil, nil, "track") -- takes the freed index
units["mouseover"] = { name = "Forest Spider", famName = "Spider", famId = 3, id = 1, level = 20 }
SBeGone.HoverTick()
local hoverSlots, adopted = 0, false
for i = 1, SBeGone.Cover.MAX do
	if SBeGone.Cover.KindOf(i) == "hover" then hoverSlots = hoverSlots + 1 end
	if SBeGone.Cover.KindOf(stickyIdx) == "hover" then adopted = true end
end
check(hoverSlots == 1 and not adopted,
	"hover: a stale sticky entry never adopts a recycled index owned by tracking")
check(SBeGone.hoverByKey["Forest Spider|1"] ~= stickyIdx,
	"hover: the stale entry is replaced, not silently reused")
SBeGone.Cover.ClearAll()
SBeGone.ResetTrack()

-- ---- anchor refusal fails safe ------------------------------------------
-- A refused SetPoint must never leave a frame with no anchor on screen, and a
-- run of refusals must stop instead of churning the pool 10 times a second.
SBeGoneSettings.autoTrack = true
SBeGone.Cover.ClearAll()
SBeGone.ResetTrack()
SBeGone.trackFailures = 0
local realPlaceTracked = SBeGone.Cover.PlaceTracked
SBeGone.Cover.PlaceTracked = function() return false end
setPlate(1, makePlate(220, 1.4))
setUnit("nameplate1", {
	name = "Forest Spider", famName = "Spider", famId = 3, level = 20,
	exists = true, visible = true,
})
out = capture(function()
	for _ = 1, 25 do SBeGone.TrackTick() end
end)
local stillAllocated = 0
for i = 1, SBeGone.Cover.MAX do
	if SBeGone.Cover.pool[i].allocated then stillAllocated = stillAllocated + 1 end
end
check(stillAllocated == 0, "anchor refusal: no position-less cover is left allocated")
check(SBeGone.autoSuspended == true and SBeGoneSettings.autoTrack == true,
	"anchor refusal: pauses coverage without silently enabling another detection mode")
check(SBeGone.trackFailures >= 20, "anchor refusal: refusals counted for diagnostics")
check(#out == 1 and out[1]:find("would not anchor") ~= nil,
	"anchor refusal: reported once, not on every tick")
SBeGone.Cover.PlaceTracked = realPlaceTracked
SBeGone.Cover.ClearAll()
SBeGone.ResetTrack()
setPlate(1, nil)
clearUnits()

-- ---- eviction must not corrupt the allocation queue ----------------------
-- C.Save and C.Restore iterate Cover.queue: an index missing from the queue is
-- a cover that silently disappears after a relog. This path was broken while
-- writing the preferential-eviction test (the FIFO line survived pickEvict).
local function queueIsSane()
	local allocated = 0
	for i = 1, SBeGone.Cover.MAX do
		if SBeGone.Cover.pool[i].allocated then allocated = allocated + 1 end
	end
	if #SBeGone.Cover.queue ~= allocated then
		return false, "queue length " .. #SBeGone.Cover.queue .. " ~= allocated " .. allocated
	end
	local seen = {}
	for _, idx in ipairs(SBeGone.Cover.queue) do
		if seen[idx] then return false, "duplicate index " .. tostring(idx) end
		seen[idx] = true
		local slot = SBeGone.Cover.pool[idx]
		if not slot or not slot.allocated then return false, "queue holds an unallocated index" end
	end
	return true
end
local okQ, whyQ
SBeGoneSettings.autoTrack = false
SBeGone.ResetTrack()
SBeGone.Cover.ClearAll()
for i = 1, 3 do
	local idx = SBeGone.Cover.Allocate("park")
	SBeGone.Cover.Place(idx, 100 + i * 40, 500)
end
flushDisplay()
SBeGone.Cover.Save()
check(savedCount(SBeGone.char) == 3, "queue: three parked shields saved before the churn")
local parkedIdx = {}
for _, idx in ipairs(SBeGone.Cover.queue) do
	if SBeGone.Cover.KindOf(idx) == "park" then parkedIdx[idx] = true end
end
check(next(parkedIdx) ~= nil and (function()
	local n = 0
	for _ in pairs(parkedIdx) do n = n + 1 end
	return n == 3
end)(), "queue: all three parked shields are in the allocation queue")
-- more demand than the pool: forces MAX + 6 evictions
for _ = 1, SBeGone.Cover.MAX + 6 do
	SBeGone.Cover.Allocate("hover", 200, 200, "hover")
end
flushDisplay()
okQ, whyQ = queueIsSane()
check(okQ, "queue: eviction keeps the allocation queue exactly consistent"
	.. (okQ and "" or (" (" .. tostring(whyQ) .. ")")))
local parkedLeft = 0
for idx in pairs(parkedIdx) do
	if SBeGone.Cover.KindOf(idx) == "park" then parkedLeft = parkedLeft + 1 end
end
check(parkedLeft > 0, "queue: parked shields are not all sacrificed to a full pool of hovers")
local expect = 0
for _, idx in ipairs(SBeGone.Cover.queue) do
	local slot = SBeGone.Cover.pool[idx]
	if not slot.anchored and type(slot.x) == "number" then expect = expect + 1 end
end
SBeGone.Cover.Save()
check(savedCount(SBeGone.char) == expect,
	"queue: Save writes exactly the positioned, unanchored covers (no losers)")
SBeGone.Cover.ClearAll()

-- ---- Forever restrictions and Classic-only baseline ----------------------
local countIDs = 0
for _ in pairs(SBeGone.DB.ids) do countIDs = countIDs + 1 end
check(countIDs == 124 and SBeGone.DB.counts.ids == countIDs,
	"classic data: declared count matches the shipped creature database")
local excludedIDs = { 17236, 16350, 16351, 16352, 17522, 17523, 17683,
	18466, 18467, 18647, 20714, 20998, 22044, 22132 }
local includesExpansion = false
for _, id in ipairs(excludedIDs) do
	if SBeGone.DB.ids[id] then includesExpansion = true end
end
check(not includesExpansion, "classic data: TBC-only creatures are excluded, including Tcha'kaz in a Classic zone")
check(SBeGone.DB.ids[15952] and SBeGone.DB.ids[16698],
	"classic data: original Naxxramas creatures are retained without an arbitrary numeric ID cutoff")

SBeGone.autoSuspended = false
SBeGoneSettings.autoTrack = true
SBeGoneSettings.arrange = false
SBeGone.Cover.ClearAll()
SBeGone.ResetTrack()
clearUnits()
setUnit("player", { name = "RestrictedTester", level = 60, player = true })
setUnit("nameplate1", { name = "Forest Spider", level = 10, id = 1504, famId = 3 })
local safePlate = setPlate(1, makePlate(100, 0.5))
C_NamePlate = { GetNamePlateForUnit = function() return safePlate end }

-- A sentinel models denied values. It is deliberately not a real Blizzard
-- secret: actual enforcement still requires a live client test.
local denied = {}
issecretvalue = function(value) return rawequal(value, denied) end
canaccessvalue = function(value) return not rawequal(value, denied) end
check(not SBeGone.Access.CanRead(denied), "access: secret values are rejected before interpretation")
local first, second, queryOK = SBeGone.Access.Query(function() return "Spider", denied end)
check(not queryOK and first == nil and second == nil,
	"access: a secret second return never leaks into family comparisons")
C_Secrets = { ShouldUnitIdentityBeSecret = function() return true end }
local realName = UnitName
local identityCalls = 0
UnitName = function(unit) identityCalls = identityCalls + 1; return realName(unit) end
check(not SBeGone.Units.IsSpider("nameplate1") and identityCalls == 0,
	"access: identity restriction prevents name/ID detection rather than trying another channel")
UnitName = realName
C_Secrets = nil

local realID, realFamily, realLevel = UnitCreatureID, UnitCreatureFamily, UnitLevel
UnitCreatureID = function() return denied end
UnitCreatureFamily = function() return "Beast", denied end
UnitName = function(unit) if unit == "player" then return "Tester" end; return denied end
check(not SBeGone.Units.IsSpider("nameplate1"),
	"access: secret names, IDs and family results cannot trigger a guessed cover")
UnitCreatureID, UnitCreatureFamily, UnitName = realID, realFamily, realName
UnitLevel = function() return denied end
check(not SBeGone.Units.IsSpider("nameplate1"),
	"access: secret levels are never used in the configured numeric range")
UnitLevel = realLevel

safePlate.IsForbidden = function() return true end
local originalShown = safePlate.IsShown
safePlate.IsShown = function() error("forbidden frame must not be inspected", 0) end
check(SBeGone.PlateFrameFor("nameplate1", 1) == nil,
	"access: forbidden plates are rejected before their other methods are called")
safePlate.IsForbidden, safePlate.IsShown = nil, originalShown
safePlate.GetUnit = function() return denied end
check(SBeGone.PlateFrameFor("nameplate1", 1) == nil,
	"access: secret plate metadata is not treated as missing metadata")
safePlate.GetUnit = nil
C_NamePlate.GetNamePlateForUnit = function() error("lookup restricted", 0) end
check(SBeGone.PlateFrameFor("nameplate1", 1) == nil,
	"access: a rejected public lookup is not bypassed with a global-frame search")
C_NamePlate.GetNamePlateForUnit = function() return safePlate end
local realWidth, realScale = safePlate.GetWidth, safePlate.GetEffectiveScale
safePlate.GetWidth = function() return denied end
safePlate.GetEffectiveScale = function() return denied end
local geometryOK = pcall(SBeGone.TrackTick)
local safeSlot = SBeGone.track.nameplate1
check(geometryOK and safeSlot and SBeGone.Cover.pool[safeSlot].frame:GetParent() == safePlate,
	"access: inaccessible size/scale uses configured geometry and native parenting without secret arithmetic")
check(SBeGone.Cover.pool[safeSlot].frame.mouse == false,
	"access: a tracked cover always has mouse input explicitly disabled")
safePlate.GetWidth, safePlate.GetEffectiveScale = realWidth, realScale

local pendingFrame = SBeGone.Cover.pool[safeSlot].frame
local parentMethod = pendingFrame.SetParent
pendingFrame.SetParent = function(self, parent)
	if parent == UIParent then error("detach blocked in this context", 0) end
	return parentMethod(self, parent)
end
check(not SBeGone.Cover.Release(safeSlot), "cleanup: rejected detachment is reported")
local pending = SBeGone.Cover.pool[safeSlot]
check(pending.pendingRelease and pending.anchored and not pending.allocated,
	"cleanup: blocked plate children remain marked attached and unavailable for reuse")
check(pcall(SBeGone.Cover.SyncDrags), "cleanup: blocked children are never measured as screen covers")
SBeGone.Cover.Save()
check(savedCount(SBeGone.char) == 0, "cleanup: deferred children are not persisted")
local differentSlot = SBeGone.Cover.Allocate("hover", 100, 200)
check(differentSlot ~= safeSlot, "cleanup: another cover cannot adopt a blocked plate child")
SBeGoneSettings.arrange = true
SBeGone.Cover.ApplyInteractivity()
check(pendingFrame.mouse == false, "cleanup: arrange mode keeps blocked plate children click-through")
SBeGoneSettings.arrange = false
pendingFrame.SetParent = parentMethod
SBeGone.Cover.RetryReleases()
check(not pending.pendingRelease and not pending.anchored and pendingFrame:GetParent() == UIParent,
	"cleanup: ordinary API retry releases a deferred child when the client permits it")
local freeBefore = #SBeGone.Cover.free
SBeGone.Cover.Release(safeSlot)
check(#SBeGone.Cover.free == freeBefore, "cleanup: repeated release cannot duplicate free pool indices")
SBeGone.Cover.ClearAll()
SBeGone.ResetTrack()
SBeGone.Cover.ApplyInteractivity()

-- Both old global event arguments and the timer fallback remain supported.
event, arg1 = "NAME_PLATE_UNIT_ADDED", "nameplate1"
SBeGone.eventFrame.scripts.OnEvent()
local eventSlot = SBeGone.track.nameplate1
check(eventSlot ~= nil, "events: a plate-added event attaches a cover before the next scan")
event = "NAME_PLATE_UNIT_REMOVED"
SBeGone.eventFrame.scripts.OnEvent()
check(SBeGone.track.nameplate1 == nil and not SBeGone.Cover.IsAllocated(eventSlot),
	"events: a plate-removed event releases its cover immediately")
event, arg1 = nil, nil

local originalUpdate, originalHover = SBeGone.Update, SBeGone.HoverTick
local unexpectedHover = 0
SBeGone.HoverTick = function() unexpectedHover = unexpectedHover + 1 end
SBeGone.Update = function() error("unexpected restricted action", 0) end
capture(function() for _ = 1, 4 do SBeGone.Tick() end end)
SBeGone.Update = originalUpdate
SBeGone.Tick()
check(SBeGone.autoSuspended and SBeGoneSettings.autoTrack and unexpectedHover == 0,
	"errors: repeated failures pause coverage instead of enabling sticky detection")
capture(function() SBeGone.Slash("auto on") end)
check(not SBeGone.autoSuspended, "errors: explicit auto-on clears the suspended state")
SBeGone.HoverTick = originalHover

-- All pool slots may be temporarily unavailable in a restricted context.
-- Restoring must preserve the saved layout and finish once cleanup is legal.
SBeGone.Cover.ClearAll()
SBeGone.ResetTrack()
local blockedFrames = {}
for _ = 1, SBeGone.Cover.MAX do
	local index = SBeGone.Cover.AllocateUnpositioned("track", "track")
	SBeGone.Cover.PlaceTracked(index, safePlate, 50)
	local frame = SBeGone.Cover.pool[index].frame
	blockedFrames[frame] = frame.SetParent
	frame.SetParent = function(self, parent)
		if parent == UIParent then error("cleanup unavailable", 0) end
		return blockedFrames[self](self, parent)
	end
	SBeGone.Cover.Release(index)
end
check(#SBeGone.Cover.free == 0, "cleanup: fully blocked pool has no reusable slots")
check(SBeGone.Cover.Allocate("park", 50, 60) == nil,
	"cleanup: exhausted blocked pool returns no cover instead of reusing a restricted frame")
local restoreCharacter = SBeGone.char
SBeGoneSettings.covers[restoreCharacter] = {
	init = true, list = { { x = 90, y = 120, w = 80, h = 80, kind = "park" } },
}
local restoreOK, restoreResult = pcall(SBeGone.Cover.Restore, restoreCharacter)
check(restoreOK and restoreResult == false and SBeGone.Cover.deferredRestore == restoreCharacter,
	"cleanup: a layout restore defers safely when all slots are blocked")
SBeGone.Cover.Save()
check(savedCount(restoreCharacter) == 1,
	"cleanup: deferred restore cannot erase the existing saved layout")
for frame, method in pairs(blockedFrames) do frame.SetParent = method end
SBeGone.Cover.RetryReleases()
flushDisplay()
check(SBeGone.Cover.deferredRestore == nil and SBeGone.Cover.ShownCount() == 1,
	"cleanup: saved layout restores automatically after normal detachment is permitted")
check(savedCount(restoreCharacter) == 1 and findCover(90, 120) ~= nil,
	"cleanup: restored coordinates and persistence survive complete pool exhaustion")
C_NamePlate, C_Secrets, issecretvalue, canaccessvalue = nil, nil, nil, nil
clearUnits()
setPlate(1, nil)
SBeGone.Cover.ClearAll()
SBeGone.ResetTrack()

if fails > 0 then
	error(fails .. " test(s) FAILED", 0)
end

print("ALL M3 TESTS PASS")
