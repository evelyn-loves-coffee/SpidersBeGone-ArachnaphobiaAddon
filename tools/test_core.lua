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
UnitClass = function(u) local d = units[u]; return d and d.class end
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
local function makeFrame()
	local f = { visible = false, points = {}, size = { 0, 0 }, events = {} }
	function f:Show() self.visible = true end
	function f:Hide() self.visible = false end
	function f:IsShown() return self.visible end
	function f:SetParent(_) end
	function f:SetFrameStrata(_) end
	function f:SetClampRect(a, b, c, d) self.clamp = { a, b, c, d } end
	function f:EnableMouse(_) end
	function f:SetMovable(_) end
	function f:SetSize(w, h) self.size = { w, h } end
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
		return p.anchor, p.relFrame, p.x, p.y, 0
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
	function f:SetScript(_, _) end
	function f:RegisterEvent(e) self.events[#self.events + 1] = e end
	return f
end
CreateFrame = function() return makeFrame() end

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

local function savedCount(char)
	local list = SBeGoneSettings.covers and SBeGoneSettings.covers[char]
	return list and #list or -1
end

-- ---- settings migration (on load) -------------------------------------
check(SBeGoneSettings.version == 1, "settings: version set to 1")
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
check(#out == 1 and out[1]:find("on|off|toggle|clear|help") ~= nil,
	"slash: help usage line")

-- ---- predicate ----------------------------------------------------------
setUnit("t", { name = "Young Night Web Spider", level = 2, famName = "Spider", famId = 3, id = 1504 })
check(SBeGone.Units.IsSpider("t") == true, "predicate: family id 3 -> spider")
setUnit("p", { name = "WarriorGuy", class = "Warrior", famName = "Spider", famId = 3, level = 20 })
check(SBeGone.Units.IsSpider("p") == false, "predicate: player never covered")
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

-- ---- enter world (first run: default pre-parked shields) ---------------
SBeGoneSettings.parkCount = 8
setUnit("player", { name = "TestWarrior", class = "Warrior" })
SBeGone.OnEnterWorld()
check(SBeGone.ready == true, "enter world: ready")
check(SBeGone.Cover.inited == true, "enter world: pool inited")
check(SBeGone.Cover.pool[1].art ~= nil and SBeGone.Cover.pool[1].base ~= nil,
	"pool: textures created under client-faithful layer validation (SBG8)")
check(SBeGone.Cover.ShownCount() == 8, "enter world: 8 default parked shields")
check(savedCount("TestWarrior") == 8, "enter world: 8 covers saved for character")
check(SBeGoneSettings.covers["TestWarrior"][1].kind == "park", "enter world: saved kind=park")

-- ---- sticky hover flow --------------------------------------------------
setUnit("mouseover",
	{ name = "Young Night Web Spider", level = 2, famName = "Spider", famId = 3, id = 1504 })
cursor.x, cursor.y = 300, 400
SBeGone.Tick()
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
SBeGone.Cover.pool[di].frame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", 777, 888)
SBeGone.Cover.SyncDrags()
check(SBeGone.Cover.pool[di].x == 777 and SBeGone.Cover.pool[di].y == 888,
	"drags: dragged position adopted")
check(savedCount("TestWarrior") == 1 and SBeGoneSettings.covers["TestWarrior"][1].x == 777,
	"drags: dragged position saved")
SBeGone.Cover.Place(di, 777.4, 888.2)
check(SBeGone.Cover.pool[di].frame.points[1].x == 777,
	"place: sub-pixel movement ignored (epsilon)")

-- ---- per-character persistence -------------------------------------------
SBeGoneSettings.covers["OtherChar"] = {
	{ x = 500, y = 500, w = 80, h = 80, kind = "hover" },
}
SBeGone.ready = false
SBeGone.char = nil
clearUnits()
setUnit("player", { name = "OtherChar", class = "Warrior" })
SBeGone.OnEnterWorld()
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

SBeGone.ready = false
SBeGone.char = nil
clearUnits()
setUnit("player", { name = "FreshChar", class = "Warrior" })
SBeGone.OnEnterWorld()
check(SBeGone.Cover.ShownCount() == 8, "chars: fresh character gets 8 default parks")
check(savedCount("FreshChar") == 8, "chars: fresh character's parks saved")

--------------------------------------------------------------------- result
if fails > 0 then
	error(fails .. " test(s) FAILED", 0)
end
print("ALL M3 TESTS PASS")
