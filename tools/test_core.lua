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

local cursor = { x = 100, y = 200 }
GetCursorPosition = function() return cursor.x, cursor.y, 1 end

C_Timer = { After = function() end } -- no-op; tests drive SBeGone.Tick()

UIParent = {}
SlashCmdList = {}

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
	function f:SetParent(_) end
	function f:SetFrameStrata(_) end
	-- Client-faithful (SBG9): SetClampRect and SetSize are ABSENT on this
	-- client — do not stub them, so any direct call fails the suite the
	-- same way it fails in-game.
	function f:EnableMouse(_) end
	function f:SetMovable(_) end
	function f:SetWidth(w) self.size = { w, self.size[2] } end
	function f:SetHeight(h) self.size = { self.size[1], h } end
	function f:SetPoint(anchor, relFrame, relPoint, x, y)
		self.points[1] = {
			anchor = anchor, relFrame = relFrame, relPoint = relPoint,
			x = x or 0, y = y or 0,
		}
	end
	function f:GetPoint(_, relFrame, relPoint)
		local p = self.points[1]
		if not p then return nil end
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

-- ---- slash registration -------------------------------------------------
check(_G.SLASH_SPIDER1 == "/spider", "slash: SLASH_SPIDER1")
check(_G.SLASH_SPIDER2 == "/spidergone", "slash: SLASH_SPIDER2")
check(type(SlashCmdList["SPIDER"]) == "function", "slash: SlashCmdList[SPIDER]")

-- ---- bare /spider = selftest (3 lines, before entering the world) ------
local out = capture(function() SlashCmdList["SPIDER"]("") end)
check(#out == 3, "selftest: prints 3 lines")
check(out[1] and out[1]:find("^SBG| v") ~= nil, "selftest: line 1 version/build")
check(out[2] and out[2]:find("^SBG| enabled=true | interface=16001 | char=nil") ~= nil,
	"selftest: line 2 enabled/interface/char")
check(out[3] and out[3]:find("^SBG| covers shown=0/24") ~= nil, "selftest: line 3 pool")

out = capture(function() SlashCmdList["SPIDER"]("bogus") end)
check(#out == 1 and out[1]:find("unknown subcommand 'bogus'") ~= nil,
	"slash: unknown subcommand message")
out = capture(function() SlashCmdList["SPIDER"]("help") end)
check(#out == 1 and out[1]:find("on / off / toggle / clear / parks N / help") ~= nil
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
SBeGoneSettings.extraNames = { "Webspinner" }
setUnit("t4", { name = "Webspinner", level = 3 })
check(SBeGone.Units.IsSpider("t4") == true, "predicate: extraNames exact match")
SBeGoneSettings.extraNames = {}
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
if fails > 0 then
	error(fails .. " test(s) FAILED", 0)
end
print("ALL M3 TESTS PASS")
