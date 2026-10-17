-- Offline Lua 5.1 regression suite for nameplate-only covers.
--------------------------------------------------------------------- stubs
local t, movementCalls = 0, 0
GetBuildInfo = function() return "1.60.1", "70374", "Oct 12 2026", "16001" end
GetTime = function() t = t + 0.3; return t end
GetEffectiveScreenInfo = function() return 1772, 1181 end

-- unit database: token -> { name, level, class, famName, famId, id, hostile }
local units = {}
local legacyReads = 0
local function unitData(token)
    if token == "mouseover" then legacyReads = legacyReads + 1 end
    return units[token]
end
local function setUnit(token, data) units[token] = data end
local function clearUnits()
	for k in pairs(units) do units[k] = nil end
end

UnitName = function(u) local d = unitData(u); return d and d.name end
GetUnitName = UnitName
UnitLevel = function(u) local d = unitData(u); return (d and d.level) or 0 end
-- AS14 (in-game 2026-10-15): UnitClass returns the unit's NAME for
-- non-player units on this client, so a non-nil return does NOT mean player.
UnitClass = function(u)
	local d = unitData(u)
	if not d then return nil end
	if d.player then return d.class end
	return d.class or d.name
end
-- Strict boolean (the guard accepts only == true).
UnitIsPlayer = function(u)
	local d = unitData(u)
	if d and d.player then return true end
end
UnitCreatureFamily = function(u)
	local d = unitData(u)
	if not d then return nil, nil end
	return d.famName, d.famId
end
UnitCreatureID = function(u) local d = unitData(u); return d and d.id end
-- TWO-ARG client form (AS5): UnitCanAttack("player", unit) = "can I attack it"
UnitCanAttack = function(unit, target)
	if unit == "player" then
		local d = unitData(target)
		return (d and d.hostile) or false
	end
	return false
end

UnitExists = function(u) return unitData(u) ~= nil end
UnitIsVisible = function(u) return unitData(u) ~= nil end
UnitIsDead = function(u) local d = unitData(u); return d and d.dead == true or false end
UnitGUID = function(u) local d = unitData(u); return d and d.guid end

GetCursorPosition = function()
    legacyReads = legacyReads + 1
    error("automatic covers must not read the cursor", 0)
end

C_Timer = { After = function() end } -- no-op; tests drive ArachnaphobiaShield.Tick()

UIParent = { scale = 1 }
function UIParent:GetEffectiveScale() return self.scale end
SlashCmdList = {}

-- Nameplate stand-in: unit token -> indexed global frame (proven layout in
-- game 2026-10-15: NamePlate1..4 exist, nameplate1..4 answer unit queries).
-- Geometry getters THROW, exactly like the client's restricted regions
-- (AS15: "Action[FrameMeasurement] failed because[Can't measure restricted
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

-- Frame stub: native parenting/size state, with screen measurement prohibited.
_G.__frames = {}
local function makeFrame()
	local f = { visible = false, pending = false, points = {}, size = { 0, 0 }, events = {} }
	_G.__frames[#_G.__frames + 1] = f
	-- Client-faithful (AS12): Show() is deferred to the next display pass;
	-- flushDisplay() below simulates that pass.
	function f:Show() self.pending = true end
	function f:Hide() self.visible = false; self.pending = false end
	function f:IsShown() return self.visible end
	function f:SetParent(parent) self.parent = parent end
	function f:GetParent() return self.parent end
	function f:SetFrameStrata(_) end
	-- Client-faithful (AS9): SetClampRect and SetSize are ABSENT on this
	-- client — do not stub them, so any direct call fails the suite the
	-- same way it fails in-game.
	function f:EnableMouse(on)
		self.mouse = on
		self.mouseHistory = self.mouseHistory or {}
		self.mouseHistory[#self.mouseHistory + 1] = on
	end
	function f:SetMovable(_) movementCalls = movementCalls + 1; error("cover movement is forbidden", 0) end
	f.StartMoving, f.StopMovingOrSizing, f.RegisterForDrag = f.SetMovable, f.SetMovable, f.SetMovable
	function f:SetText(value) self.text = value end
	function f:GetText() return self.text or "" end
	function f:SetFont(...) self.font = { ... } end
	function f:SetAutoFocus(on) self.autoFocus = on end
	function f:ClearFocus() self.focusCleared = true end
	function f:SetOrientation(value) self.orientation = value end
	function f:SetMinMaxValues(lo, hi) self.minimum, self.maximum = lo, hi end
	function f:SetValueStep(value) self.step = value end
	function f:SetObeyStepOnDrag(value) self.obeyStep = value end
	function f:SetThumbTexture(value) self.thumb = value end
	function f:GetValue() return self.value end
	function f:SetValue(value)
		self.value = math.max(self.minimum or 0, math.min(self.maximum or 1, value))
		if self.rawScripts and self.rawScripts.OnValueChanged then self.rawScripts.OnValueChanged() end
	end
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
	function f:GetPoint() error("screen-position reads are forbidden", 0) end
	-- Client-faithful (AS8): the native CreateTexture rejects layer names
	-- it does not know ("bad argument #3 ... self:CreateTexture(params)");
	-- only the layers proven on this client are accepted (Spoken's working
	-- vanilla branch uses "ARTWORK" and "HIGHLIGHT").
	local VALID_LAYERS = { ARTWORK = true, HIGHLIGHT = true }
	function f:CreateTexture(_, layer)
		if layer ~= nil and not VALID_LAYERS[layer] then
			error("bad argument #3 to 'CreateTexture' (Usage: local texture = self:CreateTexture(params))", 0)
		end
		local tex = {}
		tex.frame = f
		function tex:SetAllPoints(_) self.allPoints = true end
		function tex:SetPoint(...) end
		function tex:SetTexture(...)
			local path = ...
			if path == _G.__unloadableTexture then return false end
			if path == _G.__throwTexture then error("texture rejected", 0) end
			self.texture = { ... }
		end
		function tex:SetVertexColor(...)
			if _G.__rejectVertexAlpha and select("#", ...) == 4 then error("RGB-only client", 0) end
			self.tint = { ... }
		end
		function tex:SetVertexAlpha(value) self.tint[4] = value end
		function tex:SetWidth(value) self.width = value end
		function tex:SetHeight(value) self.height = value end
		return tex
	end
	function f:CreateFontString()
		local text = {}
		function text:SetAllPoints(frame) self.frame = frame end
		function text:SetText(value) self.value = value end
		function text:SetFont(...) self.font = { ... } end
		function text:SetTextColor(...) self.color = { ... } end
		function text:SetJustifyH(value) self.justifyH = value end
		function text:SetJustifyV(value) self.justifyV = value end
		return text
	end
	function f:SetScript(script, handler)
		self.scripts = self.scripts or {}
		self.rawScripts = self.rawScripts or {}
		self.rawScripts[script] = handler
		-- Client-faithful (AS10): the native SetScript calls handlers
		-- with NO arguments; event data arrives via the `this`/`event`/
		-- `arg1`..`arg9` globals (Spoken's Compat.lua override proves
		-- the convention). Firing an event = set the globals, call the
		-- stored wrapper.
		self.scripts[script] = function() handler() end
	end
	function f:RegisterEvent(e) self.events[#self.events + 1] = e end
	return f
end
-- Record every frame kind the addon requests; the final invariant proves no
-- mouse-capturing Slider is ever created.
_G.__frameKinds = {}
CreateFrame = function(kind)
    if type(kind) == "string" then _G.__frameKinds[#_G.__frameKinds + 1] = kind end
    return makeFrame()
end

-- One display pass: commits deferred Show()s (AS12). The real client does
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

-- Saved fixtures intentionally include the retired settings that caused
-- input problems on the partner's client. They must be deleted, not restored.
ArachnaphobiaShieldSettings = { enabled = "yes", parkCount = 8, arrange = true,
    covers = { Partner = { init = true, list = { { x = 100, y = 200, kind = "park" } } } },
    autoTrack = false, stickyCovers = true }
for _, file in ipairs({ "SpiderDB", "Access", "Units", "DeathWarning", "Appearance", "Cover", "Config", "Core" }) do
    dofile("ArachnaphobiaShield/" .. file .. ".lua")
end

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

-- ---- settings and commands --------------------------------------------
check(ArachnaphobiaShieldSettings.version == 4 and ArachnaphobiaShieldSettings.enabled == true,
    "upgrade: schema 4 repairs invalid enabled state")
check(ArachnaphobiaShieldSettings.covers == nil and ArachnaphobiaShieldSettings.parkCount == nil and ArachnaphobiaShieldSettings.arrange == nil,
    "upgrade: all characters' old cover layouts and input modes are removed")
check(ArachnaphobiaShieldSettings.autoTrack == nil and ArachnaphobiaShieldSettings.stickyCovers == nil,
    "upgrade: retired detection modes cannot suppress tracking")
check(ArachnaphobiaShield.Cover.Park == nil and ArachnaphobiaShield.Cover.Place == nil and ArachnaphobiaShield.Cover.Save == nil
    and ArachnaphobiaShield.Cover.Restore == nil and ArachnaphobiaShield.Cover.SyncDrags == nil
    and ArachnaphobiaShield.Cover.ApplyInteractivity == nil, "cover: removed APIs cannot create screen covers or enable interaction")
check(_G.SLASH_AS1 == "/as" and type(SlashCmdList["AS"]) == "function"
    and _G.SLASH_SPIDER1 == nil and _G.SLASH_SPIDER2 == nil, "slash: /as is registered without the retired command aliases")
local out = capture(function() ArachnaphobiaShield.Slash("") end)
check(#out == 3 and out[1]:find("WoW 1%.60%.1") and out[3]:find("mode=tracking"),
    "status: reports client and tracking without saved-layout controls")
check(not table.concat(out, " "):find("arrange=") and not table.concat(out, " "):find("saved="),
    "status: removed layout settings do not appear in diagnostics")
for _, command in ipairs({ "park", "parks 8", "arrange on", "arrange off", "clear", "release", "auto on", "size 96", "size" }) do
    out = capture(function() ArachnaphobiaShield.Slash(command) end)
    check(#out == 1 and out[1]:find("unknown subcommand"), "slash: obsolete command has no implementation: " .. command)
end

-- ---- /as grow / /as near: v0.4.0 percentage and level semantics --------
out = capture(function() ArachnaphobiaShield.Slash("grow 100") end)
check(#out == 1 and out[1]:find("grow = 100%", 1, true) and ArachnaphobiaShieldSettings.trackScale == 1.0,
    "grow: 100 is the default and stores a 1.0 multiplier")
out = capture(function() ArachnaphobiaShield.Slash("grow 80") end)
check(out[1]:find("grow = 80%", 1, true) and ArachnaphobiaShieldSettings.trackScale == 0.8, "grow: 80 stores 0.8")
out = capture(function() ArachnaphobiaShield.Slash("grow 120") end)
check(out[1]:find("grow = 120%", 1, true) and ArachnaphobiaShieldSettings.trackScale == 1.2, "grow: 120 stores 1.2")
for _, bad in ipairs({ "79", "121", "1.5" }) do
    out = capture(function() ArachnaphobiaShield.Slash("grow " .. bad) end)
    check(#out == 1 and out[1]:find("whole number 80-120", 1, true), "grow rejects: " .. bad)
end
out = capture(function() ArachnaphobiaShield.Slash("grow abc") end)
check(#out == 1 and out[1]:find("grow = 120%", 1, true), "grow: non-numeric input reports the current value")
out = capture(function() ArachnaphobiaShield.Slash("grow") end)
check(#out == 1 and out[1]:find("grow = 120%", 1, true), "grow: no argument reports the current percentage")
out = capture(function() ArachnaphobiaShield.Slash("near 1") end)
check(out[1]:find("near = 1 ") and ArachnaphobiaShieldSettings.nearThreshold == 80, "near: level 1 stores threshold 80")
out = capture(function() ArachnaphobiaShield.Slash("near 2") end)
check(ArachnaphobiaShieldSettings.nearThreshold == 30, "near: level 2 stores threshold 30")
out = capture(function() ArachnaphobiaShield.Slash("near 3") end)
check(ArachnaphobiaShieldSettings.nearThreshold == 10, "near: level 3 stores threshold 10")
out = capture(function() ArachnaphobiaShield.Slash("near 0") end)
check(ArachnaphobiaShieldSettings.nearThreshold == 0, "near: level 0 turns the boost off")
for _, bad in ipairs({ "4", "-1", "1.5" }) do
    out = capture(function() ArachnaphobiaShield.Slash("near " .. bad) end)
    check(#out == 1 and out[1]:find("whole number 0-3", 1, true), "near rejects: " .. bad)
end
out = capture(function() ArachnaphobiaShield.Slash("near abc") end)
check(#out == 1 and out[1]:find("near = 0"), "near: non-numeric input reports the current state")
out = capture(function() ArachnaphobiaShield.Slash("near") end)
check(#out == 1 and out[1]:find("near = 0"), "near: no argument reports the current level state")
out = capture(function() ArachnaphobiaShield.Slash("help") end)
check(#out == 2 and not table.concat(out, " "):find("parks") and not table.concat(out, " "):find("arrange")
    and not table.concat(out, " "):find("clear / release"), "help: only supported commands are advertised")

-- ---- predicate ----------------------------------------------------------
setUnit("t", { name = "Young Night Web Spider", level = 2, famName = "Spider", famId = 3, id = 1504 })
check(ArachnaphobiaShield.Units.IsSpider("t") == true, "predicate: family id 3 -> spider")
setUnit("p", { name = "WarriorGuy", class = "Warrior", player = true,
	famName = "Spider", famId = 3, level = 20 })
check(ArachnaphobiaShield.Units.IsSpider("p") == false, "predicate: player never covered (UnitIsPlayer)")
-- AS14 regression: the client reports an NPC's class as its NAME; that must
-- not make the guard reject the spider (in-game P3/P4: IsSpider=false).
check(UnitClass("t") == "Young Night Web Spider",
	"predicate: client reports NPC 'class' as the unit name (AS14)")
check(ArachnaphobiaShield.Units.IsSpider("t") == true,
	"predicate: spider still detected despite name-as-class report (AS14)")
setUnit("player", { name = "WarriorGuy", class = "Warrior", player = true })
setUnit("p2", { name = "WarriorGuy", famName = "Spider", famId = 3, level = 20 })
check(ArachnaphobiaShield.Units.IsSpider("p2") == false,
	"predicate: same name as the player is never covered (name guard)")
check(ArachnaphobiaShield.Units.IsSpider("t") == true,
	"predicate: spider detection unaffected by a known player unit")
clearUnits()
setUnit("t2", { name = "Gloomweaver", level = 5 })
check(ArachnaphobiaShield.Units.IsSpider("t2") == true, "predicate: name pattern Gloomweaver")
setUnit("t3", { name = "Big Bad Spider", level = 10 })
check(ArachnaphobiaShield.Units.IsSpider("t3") == true, "predicate: name contains Spider")
ArachnaphobiaShieldSettings.extraNames = { "Skitterclaw" }
setUnit("t4", { name = "Skitterclaw", level = 3 })
check(ArachnaphobiaShield.Units.IsSpider("t4") == true, "predicate: extraNames exact match")
ArachnaphobiaShieldSettings.extraNames = {}

-- ---- curated creature-ID database (owner data, SpiderDB.lua) -----------
check(type(ArachnaphobiaShield.DB) == "table" and ArachnaphobiaShield.DB.ids[1504] == true,
	"db: loaded with the owner's spider IDs (1504 Young Night Web Spider)")
check(#ArachnaphobiaShield.DB.patterns >= 14, "db: loaded with the owner's name fragments")

-- Names that give nothing away, filed outside the Spider family: only the ID
-- list can catch these, so it is consulted first.
setUnit("d1", { name = "Moss Stalker", level = 12, famName = "Beast", famId = 1, id = 1780 })
check(ArachnaphobiaShield.Units.IsSpider("d1") == true, "db: 'Moss Stalker' (family Beast) covered by ID 1780")
setUnit("d2", { name = "Crypt Horror", level = 50, id = 8557 })
check(ArachnaphobiaShield.Units.IsSpider("d2") == true,
	"db: 'Crypt Horror' covered by ID even with no creature family reported")
setUnit("d3", { name = "Beetle", level = 1, famName = "Beast", famId = 1, id = 15475 })
check(ArachnaphobiaShield.Units.IsSpider("d3") == true,
	"db: bug-model creature on the owner's list is covered (15475 Beetle)")
setUnit("d4", { name = "Young Scavenger", level = 24, famName = "Beast", famId = 1, id = 1499 })
check(ArachnaphobiaShield.Units.IsSpider("d4") == false,
	"db: a non-spider id (1499 Young Scavenger) is not covered by name or family")
setUnit("d5", { name = "Ash Spider", level = 20, id = 999999, famName = "Beast", famId = 1 })
check(ArachnaphobiaShield.Units.IsSpider("d5") == true,
	"db: an unlisted id still falls through to the name fragment")
setUnit("d6", { name = "WEBWOOD LURKER", level = 20 })
check(ArachnaphobiaShield.Units.IsSpider("d6") == true, "db: fragments match case-insensitively")

-- settings.namePatterns is ADDITIVE (the owner's SavedVariables already holds
-- the old two-entry list; replacing would drop "webwood", "nerub", ...).
ArachnaphobiaShieldSettings.namePatterns = { "Arachnid" }
setUnit("d7", { name = "Giant Arachnid", level = 10 })
check(ArachnaphobiaShield.Units.IsSpider("d7") == true, "db: user fragments are honoured")
setUnit("d8", { name = "Webwood Silkspinner", level = 20 })
check(ArachnaphobiaShield.Units.IsSpider("d8") == true,
	"db: built-in fragments still work while user fragments are set")
ArachnaphobiaShieldSettings.namePatterns = {}
clearUnits()

-- ---- /as name | names | forget (owner escape hatch) -----------------
out = capture(function() SlashCmdList["AS"](" name Anconan Spider ") end)
check(ArachnaphobiaShieldSettings.extraNames[1] == "Anconan Spider" and #out == 1,
	"name: adds an exact creature name")
setUnit("n1", { name = "anconan spider", level = 20 })
check(ArachnaphobiaShield.Units.IsSpider("n1") == true,
	"name: the named creature is covered straight away (case-insensitive)")
out = capture(function() SlashCmdList["AS"](" name Anconan Spider ") end)
check(#ArachnaphobiaShieldSettings.extraNames == 1 and out[1]:find("already on your") ~= nil,
	"name: duplicates refused instead of growing the list")
out = capture(function() SlashCmdList["AS"](" names ") end)
check(out[1]:find("1 extra name") ~= nil and out[2]:find("Anconan Spider") ~= nil,
	"names: header line plus the list")
out = capture(function() SlashCmdList["AS"](" forget Anconan Spider ") end)
check(#ArachnaphobiaShieldSettings.extraNames == 0 and out[1]:find("forgot") ~= nil,
	"forget: removes the name again")
out = capture(function() SlashCmdList["AS"](" name ") end)
check(out[1]:find("usage") ~= nil, "name: bare form prints usage and changes nothing")
-- 255-char chat limit: a long list must wrap, never truncate mid-name
for i = 1, 20 do
	SlashCmdList["AS"](" name Spider With A Very Long Placeholder Name " .. i .. " ")
end
check(#ArachnaphobiaShieldSettings.extraNames == 20, "name: 20 distinct names accepted")
out = capture(function() SlashCmdList["AS"](" names ") end)
local over = 0
for _, line in ipairs(out) do if #line > 255 then over = over + 1 end end
check(#out >= 3 and over == 0, "names: long list wraps inside the 255-char chat limit")
ArachnaphobiaShieldSettings.extraNames = {}
clearUnits()
setUnit("t5", { name = "Spiderling", level = 5, famName = "Spider", famId = 3 })
ArachnaphobiaShieldSettings.minLevel = 10
check(ArachnaphobiaShield.Units.IsSpider("t5") == false, "predicate: level window excludes")
ArachnaphobiaShieldSettings.minLevel = 1
setUnit("t6", { name = "Spider", level = 3, famName = "Spider", famId = 3, hostile = false })
ArachnaphobiaShieldSettings.requireHostile = true
check(ArachnaphobiaShield.Units.IsSpider("t6") == false, "predicate: requireHostile + friendly -> no")
units["t6"].hostile = true
check(ArachnaphobiaShield.Units.IsSpider("t6") == true, "predicate: requireHostile + hostile -> yes")
ArachnaphobiaShieldSettings.requireHostile = false
clearUnits()

-- ---- enter / disable / reload with legacy settings ---------------------
clearUnits()
setUnit("player", { name = "TestWarrior", player = true })
ArachnaphobiaShieldSettings.minLevel, ArachnaphobiaShieldSettings.maxLevel, ArachnaphobiaShieldSettings.requireHostile = 1, 99, false
ArachnaphobiaShieldSettings.trackScale, ArachnaphobiaShieldSettings.drop, ArachnaphobiaShieldSettings.coverSize = 1.0, 0.5, 96
ArachnaphobiaShield.ready = false
event = "PLAYER_ENTERING_WORLD"
ArachnaphobiaShield.eventFrame.scripts.OnEvent()
event = nil
flushDisplay()
check(ArachnaphobiaShield.ready and ArachnaphobiaShield.driverOn and ArachnaphobiaShield.Cover.ShownCount() == 0,
    "login: starts tracking without spawning a screen-positioned cover")
local allQuiet = true
for _, slot in ipairs(ArachnaphobiaShield.Cover.pool) do
    if slot.frame.mouse ~= false or slot.frame.points[1] ~= nil then allQuiet = false end
end
check(allQuiet and movementCalls == 0, "login: every pooled frame ignores input and has no screen anchor")
setUnit("nameplate1", { name = "Forest Spider", famId = 3, level = 10 })
setPlate(1, makePlate(100, 1))
ArachnaphobiaShield.Tick()
flushDisplay()
check(ArachnaphobiaShield.Cover.ShownCount() == 1, "enable: native tracking starts without targeting or mouseover")
capture(function() ArachnaphobiaShield.Slash("disable") end)
ArachnaphobiaShield.Tick()
event, arg1 = "NAME_PLATE_UNIT_ADDED", "nameplate1"
ArachnaphobiaShield.eventFrame.scripts.OnEvent()
event, arg1 = nil, nil
flushDisplay()
check(ArachnaphobiaShield.Cover.ShownCount() == 0 and next(ArachnaphobiaShield.track) == nil,
    "disable: scan and plate events cannot recreate a cover")
-- Simulate SavedVariables arriving after script load on the partner's client.
ArachnaphobiaShieldSettings = { enabled = false, coverStyle = "blue", parkCount = 12, arrange = true,
    covers = { A = { { x = 3, y = 4, kind = "park" } }, B = { list = { { x = 5, y = 6 } } } } }
ArachnaphobiaShield.ready, ArachnaphobiaShield.loadSnapshot.settingsPresent, ArachnaphobiaShield.sawVariablesLoaded = false, false, false
check(not ArachnaphobiaShield.OnEnterWorld(), "upgrade: waits for the actual late-loaded save")
event = "VARIABLES_LOADED"
ArachnaphobiaShield.eventFrame.scripts.OnEvent()
event = nil
flushDisplay()
check(ArachnaphobiaShieldSettings.version == 4 and ArachnaphobiaShieldSettings.covers == nil
    and ArachnaphobiaShieldSettings.parkCount == nil and ArachnaphobiaShieldSettings.arrange == nil,
    "upgrade: late-loaded saved layouts and arrange=true are purged across characters")
check(ArachnaphobiaShieldSettings.enabled == false and ArachnaphobiaShieldSettings.coverStyle == "blue" and ArachnaphobiaShield.Cover.ShownCount() == 0,
    "upgrade: preserves disabled state and image choice without restoring covers")
capture(function() ArachnaphobiaShield.Slash("enable") end)
flushDisplay()
check(ArachnaphobiaShieldSettings.enabled and ArachnaphobiaShield.Cover.ShownCount() == 1,
    "enable: resumes only the live nameplate cover")
capture(function() ArachnaphobiaShield.Slash("enable") end)
flushDisplay()
check(ArachnaphobiaShield.Cover.ShownCount() == 1, "enable: repeated enable cannot duplicate covers")
ArachnaphobiaShieldSettings = {}
ArachnaphobiaShield.ready = false
ArachnaphobiaShield.OnEnterWorld()
ArachnaphobiaShield.ClearTrack()
check(ArachnaphobiaShieldSettings.coverStyle == "fox" and ArachnaphobiaShieldSettings.enabled and ArachnaphobiaShieldSettings.covers == nil,
    "defaults: fresh install selects the fox and enables only tracking")

-- The owner's actual goal (2026-10-15): walk toward spiders, no targeting and
-- no mouseover, and a cover appears over each spider model, moving and
-- resizing with it. Client facts this rests on (in game, same day):
--   * nameplate1..4 exist as tokens AND as _G["NamePlate1"..4] (NP1)
--   * UnitCreatureFamily works on plate tokens (spider fam=3, beast fam=1)
--   * plate GetWidth / GetEffectiveScale answer (N5: 142.5, 0.512)
--   * plate GetRect / GetCenter / GetPoint THROW (AS15) — the makePlate stub
--     throws too, so measuring anything plate-related fails the suite
--   * anchoring our own frame to a plate is allowed (N7: "anchor=true")

ArachnaphobiaShield.track = {}
clearUnits()
setUnit("player", { name = "TestWarrior", class = "Warrior" })
ArachnaphobiaShield.Cover.ClearAll()

local plateA = setPlate(1, makePlate(100, 0.5)) -- apparent width 50 UI units
local plateB = setPlate(2, makePlate(100, 0.5))
plateA.unitToken, plateB.unitToken = "nameplate1", "nameplate2"
plateA.restricted, plateB.restricted = true, true
setUnit("nameplate1",
	{ name = "Young Night Web Spider", level = 24, famName = "Spider", famId = 3, id = 1504 })
setUnit("nameplate2", { name = "Young Scavenger", level = 24, famId = 1, id = 1499 })

ArachnaphobiaShield.Tick()
flushDisplay()
local trA = ArachnaphobiaShield.track.nameplate1
check(ArachnaphobiaShield.Cover.ShownCount() == 1,
	"track: one cover for the visible spider, none for the beast (no mouseover needed)")
check(trA ~= nil and ArachnaphobiaShield.Cover.IsAllocated(trA), "track: matching unit owns an allocated cover")
check(ArachnaphobiaShield.Cover.pool[trA].anchored == true, "track: cover is anchored to the plate")
local ptA = ArachnaphobiaShield.Cover.pool[trA].frame.points[1]
check(ptA and ptA.relFrame == plateA and ptA.anchor == "CENTER" and ptA.relPoint == "CENTER",
	"track: anchored to the plate frame itself (client moves it, not us)")
local trackedFrame = ArachnaphobiaShield.Cover.pool[trA].frame
check(trackedFrame:GetParent() == plateA,
	"track: cover belongs to the moving nameplate instead of the screen root")
-- 100 plate-local units (100% of the plate) render as 50 UI units at scale 0.5.
check(ArachnaphobiaShield.Cover.pool[trA].w == 100 and trackedFrame:GetWidth() * trackedFrame:GetEffectiveScale() == 50,
	"track: plate-local cover size inherits distance scale exactly once")
-- drop = 0.5 cover-heights below the plate (calibrated in game 2026-10-16:
-- at 0.9 the model sat above the cover's top edge)
check(ptA and math.abs((ptA.y or 0) * trackedFrame:GetEffectiveScale() + 25) < 0.001,
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
check(rx == 500 and ry == 375, "track: native transform places the cover below its spider plate")
plateA.nativeX, plateA.nativeY = 750, 350
rx, ry = renderedCenter(trackedFrame)
check(rx == 750 and ry == 325,
	"track: native model movement moves its cover before the next polling tick")

-- Perspective changes between the 10 Hz scans: native parenting must scale
-- BOTH the disc and its offset immediately, without another Lua update.
plateA.effScale = 1
check(trackedFrame:GetWidth() * trackedFrame:GetEffectiveScale() == 100
	and ptA.y * trackedFrame:GetEffectiveScale() == -50,
	"track: camera zoom scales the cover and drop between polling ticks")
ArachnaphobiaShield.Tick()
check(trackedFrame:GetWidth() == 100,
	"track: next poll does not apply the inherited plate scale a second time")
plateA.effScale = 0.5

-- The plate gets bigger (camera moves in): the cover grows on the next tick.
plateA:SetWidth(200)
ArachnaphobiaShield.Tick()
check(ArachnaphobiaShield.Cover.pool[trA].w == 200, "track: cover grows when the plate's local width grows")

check(ArachnaphobiaShieldSettings.covers == nil, "track: no live cover positions are persisted")

-- Frame IDs are pool allocation IDs, not unit IDs. Swap the globals without
-- changing the creatures, just as the client does when plates are recycled.
setPlate(1, plateB)
setPlate(2, plateA)
ArachnaphobiaShield.Tick()
check(ArachnaphobiaShield.Cover.pool[trA].frame:GetParent() == plateA,
	"track: reordered frame numbers still follow the spider's unit token")
check(ArachnaphobiaShield.PlateFrameFor("nameplate2", 2) == plateB,
	"lookup: a recycled numeric suffix never overrides explicit unit identity")
setPlate(1, plateA)
setPlate(2, plateB)

local mapped = makePlate(100, 0.5)
mapped.unitToken = "nameplate1"
C_NamePlate = { GetNamePlateForUnit = function() return mapped end }
ArachnaphobiaShield.Tick()
check(ArachnaphobiaShield.track.nameplate1 == trA and trackedFrame:GetParent() == mapped,
	"track: a changed public mapping reparents the existing cover without duplicating it")
mapped.unitToken = "nameplate2"
check(ArachnaphobiaShield.PlateFrameFor("nameplate1", 1) == nil,
	"lookup: a mapper returning a different unit is rejected")
C_NamePlate.GetNamePlateForUnit = function() return nil end
ArachnaphobiaShield.Tick()
check(ArachnaphobiaShield.track.nameplate1 == nil and not ArachnaphobiaShield.Cover.IsAllocated(trA),
	"track: valid unit with no mapped plate releases its cover instead of sticking forever")
check(trackedFrame:GetParent() == UIParent,
	"track: released covers leave the nameplate's movement and scale tree")
C_NamePlate = nil

-- The reduced client may expose GetUnit(), UnitFrame.unit, or no metadata.
local lookup = setPlate(3, makePlate(100, 1))
lookup.GetUnit = function() return "nameplate4" end
check(ArachnaphobiaShield.PlateFrameFor("nameplate4", 4) == lookup,
	"lookup: GetUnit resolves a plate whose frame number differs from its token")
lookup.GetUnit = nil
lookup.unitToken = nil
lookup.UnitFrame = { unit = "nameplate4" }
check(ArachnaphobiaShield.PlateFrameFor("nameplate4", 4) == lookup,
	"lookup: UnitFrame.unit resolves the reduced client's plate")
lookup.UnitFrame = nil
lookup.unitToken = nil
check(ArachnaphobiaShield.PlateFrameFor("nameplate3", 3) == nil,
	"lookup: metadata-free clients do not guess frame ownership from numbers")
lookup:Hide()
check(ArachnaphobiaShield.PlateFrameFor("nameplate3", 3) == nil,
	"lookup: hidden pooled frames cannot own a live cover")
setPlate(3, nil)

-- UI scale is independent of distance scale, including the existing visual
-- bounds. A missing width falls back to the configured size in UI units.
UIParent.scale = 0.8
plateA.effScale = 0.4
plateA:SetWidth(100)
ArachnaphobiaShield.Tick()
trA = ArachnaphobiaShield.track.nameplate1
trackedFrame = ArachnaphobiaShield.Cover.pool[trA].frame
check(trackedFrame:GetWidth() * trackedFrame:GetEffectiveScale() / UIParent.scale == 50,
	"track: non-default UI scale stays independent of perspective scale")
plateA:SetWidth(10000)
ArachnaphobiaShield.Tick()
check(trackedFrame:GetWidth() * trackedFrame:GetEffectiveScale() / UIParent.scale == 512,
	"track: maximum cover size remains 512 UI units after parenting")
plateA:SetWidth(1)
ArachnaphobiaShield.Tick()
check(trackedFrame:GetWidth() * trackedFrame:GetEffectiveScale() / UIParent.scale == 16,
	"track: minimum cover size remains 16 UI units after parenting")
local getWidth = plateA.GetWidth
plateA.GetWidth = nil
ArachnaphobiaShield.Tick()
check(math.abs(trackedFrame:GetWidth() * trackedFrame:GetEffectiveScale() / UIParent.scale - ArachnaphobiaShield.Cover.Size()) < 0.000001,
	"track: unavailable plate width uses the fixed UI size without double scaling")
plateA.GetWidth = getWidth
UIParent.scale, plateA.effScale = 1, 0.5
plateA:SetWidth(100)

-- Near-field boost (2026-10-16 owner screenshot: the closest visible spider
-- showed its legs). The client holds nameplate apparent size in a narrow
-- band while the model keeps growing as the camera approaches, so the
-- calibrated cover under-covers close spiders. True camera distance is
-- unmeasurable on this client (every position API absent -
-- docs/API-VERIFICATION.md); the near band is detected on the plate's
-- apparent width (width x scale, UI-scale px).
ArachnaphobiaShieldSettings.nearThreshold = 40 -- plate apparent width is 100 x 0.5 = 50
ArachnaphobiaShieldSettings.nearBoost = 2.5
ArachnaphobiaShield.Tick()
check(trackedFrame:GetWidth() == 100 * 1.0 * 2.5,
	"near: plate at/above the threshold gets the near-field size boost")
local ptNear = ArachnaphobiaShield.Cover.pool[trA].frame.points[1]
check(ptNear.y * trackedFrame:GetEffectiveScale() == -62.5,
	"near: the boosted cover keeps the drop ratio below the plate")
plateA.effScale = 0.2 -- apparent 20 < 40: a far spider
ArachnaphobiaShield.Tick()
check(trackedFrame:GetWidth() == 100,
	"near: plate below the threshold keeps the calibrated size")
plateA.effScale = 0.5
ArachnaphobiaShieldSettings.nearThreshold = 0
ArachnaphobiaShieldSettings.nearBoost = 2.6
ArachnaphobiaShield.Tick()
check(trackedFrame:GetWidth() == 100, "near: threshold 0 disables the boost")

-- A token changing to a non-spider is positive evidence of reuse. Grace
-- applies only to a missing token, never to a known different creature.
setUnit("nameplate1", { name = "Young Scavenger", level = 24, famId = 1, id = 1499 })
ArachnaphobiaShield.Tick()
check(ArachnaphobiaShield.track.nameplate1 == nil and not trackedFrame:IsShown(),
	"track: token reuse for a non-spider removes the old cover on the first tick")
setUnit("nameplate1", { name = "Forest Spider", level = 24, famId = 3, id = 1504 })
ArachnaphobiaShield.Tick()
flushDisplay()
trA = ArachnaphobiaShield.track.nameplate1

-- Spider walks away: grace first, then release.
units.nameplate1 = nil
ArachnaphobiaShield.Tick()
check(ArachnaphobiaShield.Cover.ShownCount() == 1, "track: brief loss of the plate does not strobe the cover")
for _ = 1, 6 do ArachnaphobiaShield.Tick() end
flushDisplay()
check(ArachnaphobiaShield.Cover.ShownCount() == 0 and ArachnaphobiaShield.track.nameplate1 == nil,
	"track: cover is auto-released once the spider is gone")
-- ---- hidden allocation, FIFO reuse, ownership and blocked cleanup -------
local C = ArachnaphobiaShield.Cover
C.ClearAll()
local firstSlot = C.Allocate()
flushDisplay()
check(C.IsAllocated(firstSlot) and C.ShownCount() == 0 and C.pool[firstSlot].frame.points[1] == nil,
    "pool: allocation alone never places or shows a cover")
for _ = 2, C.MAX do C.Allocate() end
local recycled = C.Allocate()
check(recycled == firstSlot, "pool: overflow recycles the oldest native-cover allocation")
local activeCount = 0
for _, slot in ipairs(C.pool) do if slot.allocated then activeCount = activeCount + 1 end end
check(activeCount == C.MAX and #C.free == 0, "pool: overflow stays bounded without creating frames")
C.ClearAll()
local poolPlate = makePlate(100, 1)
local refused = C.Allocate()
local refusedFrame = C.pool[refused].frame
local parentCall = refusedFrame.SetParent
refusedFrame.SetParent = function(self, parent)
    if parent == poolPlate then error("parent rejected", 0) end
    return parentCall(self, parent)
end
check(not C.PlaceTracked(refused, poolPlate, 40), "attach: native parenting refusal is honored")
C.Release(refused)
check(not refusedFrame:IsShown() and refusedFrame.parent == UIParent,
    "attach: parenting refusal leaves no visible screen cover")
refusedFrame.SetParent = parentCall
refused = C.Allocate()
refusedFrame = C.pool[refused].frame
local pointCall = refusedFrame.SetPoint
refusedFrame.SetPoint = function() error("anchor rejected", 0) end
check(not C.PlaceTracked(refused, poolPlate, 40) and C.pool[refused].anchored,
    "attach: partial attachment is recorded when the native anchor fails")
C.Release(refused)
refusedFrame.SetPoint = pointCall
check(not C.pool[refused].anchored and not refusedFrame:IsShown() and refusedFrame.points[1] == nil,
    "attach: partial attachment cleans up without positioning a screen cover")
local ownershipSlot = C.Allocate()
C.PlaceTracked(ownershipSlot, poolPlate, 40)
ArachnaphobiaShield.track.nameplate1, ArachnaphobiaShield.trackSlots[ownershipSlot] = ownershipSlot, "nameplate2"
setUnit("nameplate1", { name = "Forest Spider", famId = 3, level = 10 })
setPlate(1, makePlate(100, 1))
ArachnaphobiaShield.TrackTick()
check(ArachnaphobiaShield.track.nameplate1 ~= ownershipSlot and C.pool[ownershipSlot].frame.parent == poolPlate,
    "ownership: a recycled index cannot adopt another unit's native cover")
ArachnaphobiaShield.ClearTrack()
local blocked = C.Allocate()
C.PlaceTracked(blocked, poolPlate, 40)
local blockedFrame, normalParent = C.pool[blocked].frame, C.pool[blocked].frame.SetParent
blockedFrame.SetParent = function(self, parent)
    if parent == UIParent then error("detach unavailable", 0) end
    return normalParent(self, parent)
end
check(not C.Release(blocked) and C.pool[blocked].pendingRelease and not C.IsAllocated(blocked),
    "cleanup: rejected detachment quarantines its hidden slot")
check(C.Allocate() ~= blocked and blockedFrame.mouse == false and not blockedFrame:IsShown(),
    "cleanup: blocked slots stay hidden and click-through rather than being reused")
blockedFrame.SetParent = normalParent
C.RetryReleases()
check(not C.pool[blocked].pendingRelease and blockedFrame.parent == UIParent and blockedFrame.points[1] == nil,
    "cleanup: an ordinary retry detaches and clears the stale native anchor")
local freeBefore = #C.free
C.Release(blocked)
check(#C.free == freeBefore, "cleanup: repeated release cannot duplicate free indices")
ArachnaphobiaShield.ClearTrack()
local blockedMethods = {}
for _ = 1, C.MAX do
    local index = C.Allocate()
    C.PlaceTracked(index, poolPlate, 40)
    local frame = C.pool[index].frame
    blockedMethods[frame] = frame.SetParent
    frame.SetParent = function(self, parent)
        if parent == UIParent then error("restricted cleanup", 0) end
        return blockedMethods[self](self, parent)
    end
    C.Release(index)
end
check(C.Allocate() == nil and #C.free == 0, "cleanup: fully blocked pool returns no slot and never bypasses restrictions")
for frame, method in pairs(blockedMethods) do frame.SetParent = method end
C.RetryReleases()
check(#C.free == C.MAX, "cleanup: all quarantined slots recover when ordinary APIs permit detachment")
ArachnaphobiaShield.ClearTrack()
-- Churn beyond capacity: free-list identities and reverse ownership must stay sane.
for index = 1, 36 do
    setUnit("nameplate" .. index, { name = "Forest Spider", famId = 3, level = 10 })
    setPlate(index, makePlate(100, 1))
end
for _ = 1, 20 do ArachnaphobiaShield.Tick() end
flushDisplay()
local count, sane = 0, true
for token, slot in pairs(ArachnaphobiaShield.track) do
    count = count + 1
    if not C.IsAllocated(slot) or ArachnaphobiaShield.trackSlots[slot] ~= token then sane = false end
end
check(count == C.MAX and sane and #C.free == 0, "churn: full native pool keeps one matching owner per allocated slot")
ArachnaphobiaShield.ClearTrack()
for index = 1, 40 do setPlate(index, nil) end
clearUnits()

-- ---- anchor refusal fails safe ------------------------------------------
-- A refused SetPoint must never leave a frame with no anchor on screen, and a
-- run of refusals must stop instead of churning the pool 10 times a second.
ArachnaphobiaShield.Cover.ClearAll()
ArachnaphobiaShield.ClearTrack()
ArachnaphobiaShield.trackFailures = 0
local realPlaceTracked = ArachnaphobiaShield.Cover.PlaceTracked
ArachnaphobiaShield.Cover.PlaceTracked = function() return false end
setPlate(1, makePlate(220, 1.4))
setUnit("nameplate1", {
	name = "Forest Spider", famName = "Spider", famId = 3, level = 20,
	exists = true, visible = true,
})
out = capture(function()
	for _ = 1, 25 do ArachnaphobiaShield.TrackTick() end
end)
local stillAllocated = 0
for i = 1, ArachnaphobiaShield.Cover.MAX do
	if ArachnaphobiaShield.Cover.pool[i].allocated then stillAllocated = stillAllocated + 1 end
end
check(stillAllocated == 0, "anchor refusal: no position-less cover is left allocated")
check(ArachnaphobiaShield.autoSuspended == true and ArachnaphobiaShieldSettings.enabled == true,
	"anchor refusal: pauses coverage without silently enabling another detection mode")
check(ArachnaphobiaShield.trackFailures >= 20, "anchor refusal: refusals counted for diagnostics")
check(#out == 1 and out[1]:find("would not anchor") ~= nil,
	"anchor refusal: reported once, not on every tick")
ArachnaphobiaShield.Cover.PlaceTracked = realPlaceTracked
ArachnaphobiaShield.Cover.ClearAll()
ArachnaphobiaShield.ClearTrack()
setPlate(1, nil)
clearUnits()

-- ---- Forever restrictions and Classic-only baseline ----------------------
local countIDs = 0
for _ in pairs(ArachnaphobiaShield.DB.ids) do countIDs = countIDs + 1 end
check(countIDs == 124 and ArachnaphobiaShield.DB.counts.ids == countIDs,
	"classic data: declared count matches the shipped creature database")
local excludedIDs = { 17236, 16350, 16351, 16352, 17522, 17523, 17683,
	18466, 18467, 18647, 20714, 20998, 22044, 22132 }
local includesExpansion = false
for _, id in ipairs(excludedIDs) do
	if ArachnaphobiaShield.DB.ids[id] then includesExpansion = true end
end
check(not includesExpansion, "classic data: TBC-only creatures are excluded, including Tcha'kaz in a Classic zone")
check(ArachnaphobiaShield.DB.ids[15952] and ArachnaphobiaShield.DB.ids[16698],
	"classic data: original Naxxramas creatures are retained without an arbitrary numeric ID cutoff")

ArachnaphobiaShield.autoSuspended = false
ArachnaphobiaShield.Cover.ClearAll()
ArachnaphobiaShield.ClearTrack()
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
check(not ArachnaphobiaShield.Access.CanRead(denied), "access: secret values are rejected before interpretation")
local first, second, queryOK = ArachnaphobiaShield.Access.Query(function() return "Spider", denied end)
check(not queryOK and first == nil and second == nil,
	"access: a secret second return never leaks into family comparisons")
C_Secrets = { ShouldUnitIdentityBeSecret = function() return true end }
local realName = UnitName
local identityCalls = 0
UnitName = function(unit) identityCalls = identityCalls + 1; return realName(unit) end
check(not ArachnaphobiaShield.Units.IsSpider("nameplate1") and identityCalls == 0,
	"access: identity restriction prevents name/ID detection rather than trying another channel")
UnitName = realName
C_Secrets = nil

local realID, realFamily, realLevel = UnitCreatureID, UnitCreatureFamily, UnitLevel
UnitCreatureID = function() return denied end
UnitCreatureFamily = function() return "Beast", denied end
UnitName = function(unit) if unit == "player" then return "Tester" end; return denied end
check(not ArachnaphobiaShield.Units.IsSpider("nameplate1"),
	"access: secret names, IDs and family results cannot trigger a guessed cover")
UnitCreatureID, UnitCreatureFamily, UnitName = realID, realFamily, realName
UnitLevel = function() return denied end
check(not ArachnaphobiaShield.Units.IsSpider("nameplate1"),
	"access: secret levels are never used in the configured numeric range")
UnitLevel = realLevel

safePlate.IsForbidden = function() return true end
local originalShown = safePlate.IsShown
safePlate.IsShown = function() error("forbidden frame must not be inspected", 0) end
check(ArachnaphobiaShield.PlateFrameFor("nameplate1", 1) == nil,
	"access: forbidden plates are rejected before their other methods are called")
safePlate.IsForbidden, safePlate.IsShown = nil, originalShown
safePlate.GetUnit = function() return denied end
check(ArachnaphobiaShield.PlateFrameFor("nameplate1", 1) == nil,
	"access: secret plate metadata is not treated as missing metadata")
safePlate.GetUnit = nil
C_NamePlate.GetNamePlateForUnit = function() error("lookup restricted", 0) end
check(ArachnaphobiaShield.PlateFrameFor("nameplate1", 1) == nil,
	"access: a rejected public lookup is not bypassed with a global-frame search")
C_NamePlate.GetNamePlateForUnit = function() return safePlate end
local realWidth, realScale = safePlate.GetWidth, safePlate.GetEffectiveScale
safePlate.GetWidth = function() return denied end
safePlate.GetEffectiveScale = function() return denied end
local geometryOK = pcall(ArachnaphobiaShield.TrackTick)
local safeSlot = ArachnaphobiaShield.track.nameplate1
check(geometryOK and safeSlot and ArachnaphobiaShield.Cover.pool[safeSlot].frame:GetParent() == safePlate,
	"access: inaccessible size/scale uses configured geometry and native parenting without secret arithmetic")
check(ArachnaphobiaShield.Cover.pool[safeSlot].frame.mouse == false,
	"access: a tracked cover always has mouse input explicitly disabled")
safePlate.GetWidth, safePlate.GetEffectiveScale = realWidth, realScale

-- ---- native events and paused-coverage recovery -------------------------
ArachnaphobiaShield.ClearTrack()
ArachnaphobiaShield.autoSuspended = false
clearUnits()
setUnit("player", { name = "EventTester", player = true })
setUnit("nameplate1", { name = "Forest Spider", famId = 3, level = 10 })
setPlate(1, makePlate(100, 1))
event, arg1 = "NAME_PLATE_UNIT_ADDED", "nameplate1"
ArachnaphobiaShield.eventFrame.scripts.OnEvent()
local eventSlot = ArachnaphobiaShield.track.nameplate1
check(eventSlot ~= nil, "events: native plate addition attaches before the next timer scan")
event = "NAME_PLATE_UNIT_REMOVED"
ArachnaphobiaShield.eventFrame.scripts.OnEvent()
check(ArachnaphobiaShield.track.nameplate1 == nil and not C.IsAllocated(eventSlot), "events: native plate removal releases immediately")
event, arg1 = nil, nil
local originalUpdate = ArachnaphobiaShield.Update
ArachnaphobiaShield.Update = function() error("normal operation rejected", 0) end
capture(function() for _ = 1, 4 do ArachnaphobiaShield.Tick() end end)
ArachnaphobiaShield.Update = originalUpdate
check(ArachnaphobiaShield.autoSuspended and ArachnaphobiaShieldSettings.enabled and C.ShownCount() == 0,
    "errors: repeated failures pause and release covers")
capture(function() ArachnaphobiaShield.Slash("enable") end)
check(not ArachnaphobiaShield.autoSuspended and ArachnaphobiaShield.track.nameplate1 ~= nil,
    "errors: explicit enable retries through normal native APIs")
C_NamePlate, C_Secrets, issecretvalue, canaccessvalue = nil, nil, nil, nil
ArachnaphobiaShield.ClearTrack()
clearUnits()
for index = 1, 40 do setPlate(index, nil) end

-- ---- centered automatic corpse warnings ---------------------------------
local W = ArachnaphobiaShield.DeathWarning
local originalTime, originalAfter = GetTime, C_Timer.After
local warningTime, warningTimers = 1000, {}
GetTime = function() return warningTime end
C_Timer.After = function(delay, callback)
    warningTimers[#warningTimers + 1] = { delay = delay, callback = callback }
end
ArachnaphobiaShieldSettings.enabled = true
ArachnaphobiaShield.hidden, ArachnaphobiaShield.autoSuspended = nil, false
ArachnaphobiaShield.Cover.ClearAll()
ArachnaphobiaShield.ClearTrack()
W.Clear()
clearUnits()
setUnit("player", { name = "CorpseTester", player = true })
setPlate(1, makePlate(100, 1))
setUnit("nameplate1", { name = "Forest Spider", level = 2, famId = 3,
    guid = "public-spider-A", dead = false })
ArachnaphobiaShield.Tick()
check(W.expires == nil, "corpse warning: living spiders do not display a warning")
units.nameplate1.dead = true
warningTime = 1000.1
event, arg1 = "UNIT_HEALTH", "nameplate1"
ArachnaphobiaShield.eventFrame.scripts.OnEvent()
event, arg1 = nil, nil
flushDisplay()
check(W.frame and W.frame:IsShown() and W.frame.text.value:find("LOOK AWAY")
    and W.frame.text.value:find("corpse"), "corpse warning: a tracked death displays look-away text")
local warningPoint = W.frame.points[1]
check(W.frame:GetParent() == UIParent and warningPoint.anchor == "CENTER"
    and warningPoint.relPoint == "CENTER" and warningPoint.x == 0 and warningPoint.y == 0,
    "corpse warning: popup is centered on the screen independently of the removed plate")
check(W.frame.mouse == false, "corpse warning: centered notice is click-through")
check(math.abs(W.expires - warningTime - 1.75) < 0.00001,
    "corpse warning: display duration is 1.75 seconds")
local firstDeadline = W.expires
local firstTimer = warningTimers[#warningTimers]
check(firstTimer.delay == 1.75, "corpse warning: a real timer expires the popup between scans")
W.OnDeath("public-spider-A")
ArachnaphobiaShield.Tick()
check(W.expires == firstDeadline, "corpse warning: duplicate health/death/poll signals do not extend the notice")
warningTime = firstDeadline - 0.01
W.Tick()
check(W.frame:IsShown(), "corpse warning: remains visible until its duration ends")
warningTime = firstDeadline
W.Tick()
check(not W.frame:IsShown() and W.expires == nil, "corpse warning: disappears after 1.75 seconds")

-- Plate removal alone is not proof of death; readable GUID events can follow it.
W.Clear()
units.nameplate1.guid, units.nameplate1.dead = "public-spider-B", false
ArachnaphobiaShield.Tick()
event, arg1 = "NAME_PLATE_UNIT_REMOVED", "nameplate1"
ArachnaphobiaShield.eventFrame.scripts.OnEvent()
event, arg1 = nil, nil
check(W.expires == nil, "corpse warning: leaving nameplate range does not produce a death warning")
units.nameplate1 = nil
ArachnaphobiaShield.eventFrame.rawScripts.OnEvent(nil, "UNIT_DIED", "public-spider-B")
flushDisplay()
check(W.frame:IsShown(), "corpse warning: public death event can warn just after the plate/token disappears")
W.Hide()
W.OnDeath("never-observed-creature")
check(W.expires == nil, "corpse warning: unrelated or unseen deaths are ignored")
W.Clear()
setUnit("nameplate1", { name = "Forest Spider", level = 2, famId = 3,
    guid = "expired-spider", dead = false })
ArachnaphobiaShield.Tick()
warningTime = warningTime + W.RECENT_SECONDS + 0.1
W.OnDeath("expired-spider")
check(W.expires == nil, "corpse warning: stale observations cannot trigger remote death notices")

-- Token reuse and identity restrictions must not consult stale classifications.
W.Clear()
units.nameplate1.guid = "old-spider"
W.Observe("nameplate1")
units.nameplate1 = { name = "Wolf", level = 2, famId = 1, guid = "new-wolf", dead = true }
W.CheckUnit("nameplate1")
check(W.expires == nil, "corpse warning: recycled tokens do not report a different creature as a spider")
W.Clear()
setUnit("nameplate1", { name = "Forest Spider", level = 2, famId = 3,
    guid = "restricted-spider", dead = false })
W.Observe("nameplate1")
local secretDeath = {}
issecretvalue = function(value) return rawequal(value, secretDeath) end
arg1 = "restricted-spider"
ArachnaphobiaShield.eventFrame.rawScripts.OnEvent(nil, "UNIT_DIED", secretDeath)
arg1 = nil
check(W.expires == nil, "corpse warning: secret event payload never falls back to legacy arguments")
local savedDead = UnitIsDead
UnitIsDead = function() return secretDeath end
W.CheckUnit("nameplate1")
check(W.expires == nil, "corpse warning: inaccessible death state cannot trigger a guessed warning")
UnitIsDead = savedDead
C_Secrets = { ShouldUnitIdentityBeSecret = function() return true end }
W.OnDeath("restricted-spider")
check(W.expires == nil and W.byGUID["restricted-spider"] == nil,
    "corpse warning: death events also reject an actively restricted cached unit")
W.CheckUnit("nameplate1")
W.OnDeath("restricted-spider")
check(W.expires == nil, "corpse warning: newly restricted identity discards cached classification")
C_Secrets, issecretvalue = nil, nil

-- Missing GUID APIs still allow observed readable death-state transitions.
W.Clear()
units.nameplate1.guid, units.nameplate1.dead = "removing-spider", false
ArachnaphobiaShield.Tick()
units.nameplate1.dead = true
event, arg1 = "NAME_PLATE_UNIT_REMOVED", "nameplate1"
ArachnaphobiaShield.eventFrame.scripts.OnEvent()
event, arg1 = nil, nil
flushDisplay()
check(W.frame:IsShown() and ArachnaphobiaShield.track.nameplate1 == nil,
    "corpse warning: plate removal checks readable death state before releasing the cover")
W.Clear()
local savedGUID = UnitGUID
UnitGUID = nil
units.nameplate1.dead = false
W.Observe("nameplate1")
units.nameplate1.dead = true
ArachnaphobiaShield.eventFrame.rawScripts.OnEvent(nil, "UNIT_FLAGS", "nameplate1")
flushDisplay()
check(W.frame:IsShown(), "corpse warning: readable unit death works without GUID or death-event support")
W.Hide()
units.nameplate1.dead = false
W.Observe("nameplate1")
units.nameplate1.dead = true
W.Observe("nameplate1")
check(W.expires ~= nil, "corpse warning: a later living-to-dead transition can warn without GUID support")
UnitGUID = savedGUID

-- New deaths reset the timeout; an older callback cannot dismiss a newer notice.
W.Clear()
units.nameplate1.guid = "spider-C"
W.Observe("nameplate1")
local oldWarningTimer = warningTimers[#warningTimers]
warningTime = warningTime + 0.5
units.nameplate1.guid = "spider-D"
W.Observe("nameplate1")
flushDisplay()
oldWarningTimer.callback()
check(W.frame:IsShown(), "corpse warning: an old timer cannot hide a newer death notice")
warningTimers[#warningTimers].callback()
check(not W.frame:IsShown(), "corpse warning: the current notice timer hides its popup")
W.Clear()
units.nameplate1.guid = "spider-E"
W.Observe("nameplate1")
flushDisplay()
capture(function() ArachnaphobiaShield.Slash("disable") end)
check(not W.frame:IsShown() and next(W.byGUID) == nil and next(W.byToken) == nil,
    "corpse warning: disable immediately hides the popup and clears observations")
W.OnDeath("spider-E")
W.Observe("nameplate1")
flushDisplay()
check(W.expires == nil, "corpse warning: disabled events and scans cannot show the notice")
ArachnaphobiaShieldSettings.enabled = true
W.Observe("nameplate1")
event = "PLAYER_ENTERING_WORLD"
ArachnaphobiaShield.eventFrame.scripts.OnEvent()
event = nil
check(W.expires == nil and next(W.byGUID) == nil,
    "corpse warning: world transitions clear warnings and cached identities")

-- An unavailable text API must not interrupt ordinary nameplate tracking.
local normalCreateFrame, previousPopup = CreateFrame, W.frame
W.Clear()
W.frame = nil
CreateFrame = function()
    local frame = normalCreateFrame()
    frame.CreateFontString = function() error("font API unavailable", 0) end
    return frame
end
units.nameplate1.guid = "spider-F"
local warningOutput = capture(function() W.Observe("nameplate1") end)
CreateFrame = normalCreateFrame
check(W.popupUnavailable and #warningOutput == 1 and warningOutput[1]:find("LOOK AWAY"),
    "corpse warning: unavailable popup API falls back to a clear chat notice without an error")
W.frame = previousPopup
W.Clear()
W.popupUnavailable = false
units.nameplate1.dead = false
for index = 1, W.MAX_RECENT + 5 do
    units.nameplate1.guid = "churn-spider-" .. index
    W.Observe("nameplate1")
end
local recentCount = 0
for _ in pairs(W.byGUID) do recentCount = recentCount + 1 end
check(recentCount <= W.MAX_RECENT, "corpse warning: recent observations stay bounded during token churn")
W.Clear()
check(legacyReads == 0, "corpse warning: all paths remain free of mouseover and cursor queries")
GetTime, C_Timer.After = originalTime, originalAfter

-- ---- appearance selection / persistence / configuration ----------------
local P, C, O = ArachnaphobiaShield.Appearance, ArachnaphobiaShield.Cover, ArachnaphobiaShield.Config
check(P.Current().id == "fox", "appearance: missing preference defaults to the fox")
local normalized = { coverStyle = "unknown", customCover = 42 }
P.Normalize(normalized)
check(normalized.coverStyle == "fox" and normalized.customCover == "",
    "appearance: corrupt saved choices fall back without a broken texture path")
normalized = { coverStyle = "CUSTOM", customCover = "Interface/AddOns/MyCovers/flower.tga" }
P.Normalize(normalized)
check(normalized.coverStyle == "fox" and normalized.customCover == "",
    "appearance: legacy MyCovers paths are retired and fall back to the fox")
normalized = { coverStyle = "custom", customCover = "Interface/AddOns/ArachnaphobiaShield/Custom/flower.tga" }
P.Normalize(normalized)
check(normalized.coverStyle == "custom" and normalized.customCover == "Interface\\AddOns\\ArachnaphobiaShield\\Custom\\flower.tga",
    "appearance: valid saved custom choices survive normalization")
normalized = { coverStyle = "fox", opacity = 0.75 }
P.Normalize(normalized)
check(normalized.opacity == nil, "appearance: the retired opacity key is dropped on load")
normalized.customCover = "https://example.org/flower.tga"
P.Normalize(normalized)
check(normalized.coverStyle == "fox", "appearance: invalid saved custom path returns to the fox")
check(P.CustomPath(' "Interface/AddOns/ArachnaphobiaShield/Custom/my flower.tga" ')
    == "Interface\\AddOns\\ArachnaphobiaShield\\Custom\\my flower.tga",
    "appearance: local paths accept slash separators, spaces and surrounding quotes")
for _, path in ipairs({ "C:\\Pictures\\flower.tga", "https://example.org/flower.tga",
    "Interface\\AddOns\\..\\flower.tga", "Interface\\AddOns\\MyCovers\\flower.tga",
    "Interface\\AddOns\\ArachnaphobiaShield\\Custom\\flower.png",
    "Interface\\AddOns\\ArachnaphobiaShield\\Custom\\a\n.tga",
    "Interface\\AddOns\\ArachnaphobiaShield\\Custom\\\\flower.tga" }) do
    check(P.CustomPath(path) == nil, "appearance: rejects unsupported path " .. path:gsub("\n", "(newline)"))
end

-- Changing appearance updates both allocated and spare frames in place.
ArachnaphobiaShieldSettings.enabled = true
C.ClearAll()
local appearanceSlot = C.Allocate()
C.PlaceTracked(appearanceSlot, makePlate(100, 1), 40)
flushDisplay()
local beforeFrame, beforeParent = C.pool[appearanceSlot].frame, C.pool[appearanceSlot].frame.parent
for _, preset in ipairs(P.PRESETS) do
    capture(function() ArachnaphobiaShield.Slash("cover " .. preset.id) end)
    local painted = true
    for _, slot in ipairs(C.pool) do
        if slot.art.texture[1] ~= preset.path or slot.art.tint[1] ~= 1 or slot.art.tint[4] ~= 1
            or slot.base.texture[1] ~= C.BACKDROP_PATH or slot.base.tint[4] ~= 0
            or not slot.base.allPoints then painted = false end
    end
    check(painted and ArachnaphobiaShieldSettings.coverStyle == preset.id,
        "appearance: immediately paints every cover with " .. preset.id .. " and baked-in backing")
end
check(C.pool[appearanceSlot].frame == beforeFrame and beforeFrame.parent == beforeParent
    and C.IsAllocated(appearanceSlot), "appearance: selection preserves existing frames and allocation")
ArachnaphobiaShieldSettings.color, ArachnaphobiaShieldSettings.opacity = { 1, 0, 0 }, 0.1
C.ApplyStyle()
check(C.pool[appearanceSlot].art.tint[2] == 1 and C.pool[appearanceSlot].art.tint[4] == 1,
    "appearance: legacy tint and retired opacity settings cannot make a cover translucent")
capture(function() ArachnaphobiaShield.Slash("cover custom Interface/AddOns/ArachnaphobiaShield/Custom/my flower.tga") end)
local customPath = "Interface\\AddOns\\ArachnaphobiaShield\\Custom\\my flower.tga"
check(ArachnaphobiaShieldSettings.coverStyle == "custom" and ArachnaphobiaShieldSettings.customCover == customPath
    and C.pool[appearanceSlot].art.texture[1] == customPath,
    "appearance: custom command preserves spaces and applies a local texture")
capture(function() ArachnaphobiaShield.Slash("cover missing") end)
capture(function() ArachnaphobiaShield.Slash("cover custom C:\\Pictures\\image.png") end)
check(ArachnaphobiaShieldSettings.coverStyle == "custom" and ArachnaphobiaShieldSettings.customCover == customPath,
    "appearance: rejected choices leave the previous selection untouched")
capture(function() ArachnaphobiaShield.Slash("cover fox") end)
capture(function() ArachnaphobiaShield.Slash("cover custom") end)
check(P.Current().path == customPath, "appearance: custom command can reuse the saved local path")

-- Re-enter through the real settings/restore path, including late saves.
ArachnaphobiaShield.ready = false
ArachnaphobiaShield.OnEnterWorld()
check(P.Current().id == "custom" and C.pool[1].art.texture[1] == customPath,
    "appearance: saved custom choice survives settings migration and character restore")
C.ClearAll()
local trackedStyleSlot = C.Allocate()
local trackedStylePlate = makePlate(100, 1)
C.PlaceTracked(trackedStyleSlot, trackedStylePlate, 40)
capture(function() ArachnaphobiaShield.Slash("cover blue") end)
check(C.pool[trackedStyleSlot].frame.parent == trackedStylePlate
    and C.pool[trackedStyleSlot].anchored and C.IsAllocated(trackedStyleSlot)
    and C.pool[trackedStyleSlot].frame.mouse == false,
    "appearance: live style changes preserve native tracking attachment and click-through")
local originalBaseTexture = C.pool[trackedStyleSlot].base.SetTexture
C.pool[trackedStyleSlot].base.SetTexture = function() error("paint restricted", 0) end
local styleCallOK = pcall(C.ApplyStyle)
check(styleCallOK and C.textureFailed,
    "appearance: a rejected paint on an attached cover is reported without bypassing restrictions")
C.pool[trackedStyleSlot].base.SetTexture = originalBaseTexture
capture(function() ArachnaphobiaShield.Slash("cover custom") end)

__unloadableTexture = customPath
C.ApplyStyle()
check(C.textureFailed and C.pool[appearanceSlot].art.texture[1] == C.ART_PATH,
    "appearance: an explicit file-load failure falls back to the shipped fox")
__unloadableTexture, __throwTexture = nil, customPath
C.ApplyStyle()
check(C.textureFailed and C.pool[appearanceSlot].art.texture[1] == C.ART_PATH,
    "appearance: a rejected texture call cannot interrupt covers")
__throwTexture = nil
C.ApplyStyle()
check(C.pool[1].art.texture[1] == customPath,
    "appearance: repainting an initialized pool retains the saved choice")

capture(function() ArachnaphobiaShield.Slash("disable") end)
capture(function() ArachnaphobiaShield.Slash("cover blue") end)
flushDisplay()
check(not ArachnaphobiaShieldSettings.enabled and C.ShownCount() == 0,
    "appearance: choosing art while disabled cannot enable or reveal covers")
check(O.frame == nil, "config: no interactive window is created automatically")
capture(function() ArachnaphobiaShield.Slash("config") end)
flushDisplay()
check(O.frame and O.frame:IsShown() and O.frame.mouse == true,
    "config: the explicit command opens the cover picker")
check(O.input.autoFocus == false and O.preview.texture[1] == P.Find("blue").path,
    "config: preview matches the saved choice without grabbing keyboard focus")
check(O.background.texture[1] == "Interface\\AddOns\\ArachnaphobiaShield\\picker-bg.tga"
    and O.buttons.fox.background.texture[1] == "Interface\\AddOns\\ArachnaphobiaShield\\picker-btn.tga"
    and O.input.background.texture[1] == "Interface\\AddOns\\ArachnaphobiaShield\\picker-field.tga",
    "picker: window, buttons and field use proven string-path background textures")
check(O.preview.frame == O.previewBase.frame
    and O.preview.frame ~= O.previewChecker.frame
    and O.preview.frame:IsShown() and O.previewChecker.frame:IsShown(),
    "picker: backing and art share the pool-style cover frame; both preview frames shown after open")
O.buttons.red.scripts.OnClick()
check(ArachnaphobiaShieldSettings.coverStyle == "red" and O.preview.texture[1] == P.Find("red").path,
    "config: native no-argument button scripts save and preview the selected preset")
check(O.buttons.red.background.texture[1] == "Interface\\AddOns\\ArachnaphobiaShield\\picker-btn-sel.tga"
    and O.buttons.fox.background.texture[1] == "Interface\\AddOns\\ArachnaphobiaShield\\picker-btn.tga",
    "picker: the selected preset's button shows the selected background")
O.input:SetText("Interface/AddOns/ArachnaphobiaShield/Custom/flower.tga")
O.input.scripts.OnEnterPressed()
check(P.Current().id == "custom" and O.input.focusCleared and O.preview.texture[1] == P.Current().path,
    "config: custom input applies on Enter and releases focus")
O.input:SetText("https://example.org/flower.tga")
O.buttons.custom.scripts.OnClick()
check(P.Current().id == "custom" and O.status.value:find("Use a local") ~= nil,
    "config: invalid custom input explains the expected local path")
O.input.scripts.OnEscapePressed()
check(not O.frame:IsShown() and C.ShownCount() == 0,
    "config: Escape closes the editor while disabled covers remain hidden")

local pickerFrame = O.frame
O.frame = nil
local ordinaryCreateFrame = CreateFrame
CreateFrame = function()
    local frame = ordinaryCreateFrame()
    frame.CreateFontString = function() error("UI API unavailable", 0) end
    return frame
end
local pickerFallback = capture(function() ArachnaphobiaShield.Slash("config") end)
CreateFrame = ordinaryCreateFrame
check(O.unavailable and #pickerFallback == 3 and pickerFallback[1]:find("/as cover"),
    "config: an unavailable UI leaves working command-based cover selection")
O.frame, O.unavailable = pickerFrame, nil
capture(function() ArachnaphobiaShield.Slash("cover sage") end)
check(P.Current().id == "sage" and C.ShownCount() == 0,
    "config: command selection still works after a window API failure")
check(legacyReads == 0, "appearance: configuration never queries mouseover or the cursor")

-- ---- fixed opacity: the retired control is gone end to end ----
check(P.ClampOpacity == nil and P.SetOpacity == nil and P.Opacity == nil
    and P.MIN_OPACITY == nil and P.MAX_OPACITY == nil,
    "opacity: the retired opacity API is gone from the addon")
for _, preset in ipairs(P.PRESETS) do
    P.Select(preset.id)
    local exact = true
    for _, slot in ipairs(C.pool) do
        -- Fully opaque shipped texture + no second background alpha layer.
        if slot.art.tint[4] ~= 1 or slot.base.tint[4] ~= 0 then exact = false end
    end
    check(exact, "opacity: " .. preset.id .. " is fully opaque without doubling alpha")
end
P.Select("custom", "Interface\\AddOns\\ArachnaphobiaShield\\Custom\\flower.tga")
local backed = true
for _, slot in ipairs(C.pool) do
    if slot.base.tint[4] ~= 1 or slot.art.tint[4] ~= 1 then backed = false end
end
check(backed, "opacity: transparent custom art keeps a fully opaque navy backing")
local fallbackBase = C.pool[1].base
C.PaintCover(fallbackBase, nil, P.Current())
check(fallbackBase.tint[4] == 1, "opacity: missing custom art cannot reduce the backing below opaque")
__rejectVertexAlpha = true
P.Select("fox")
check(C.pool[1].art.tint[4] == 1 and C.pool[1].base.tint[4] == 0,
    "opacity: RGB-only vertex-color clients still get full opacity via SetVertexAlpha")
__rejectVertexAlpha = nil
O.Open()
check(O.opacityButtons == nil and O.opacityValue == nil and O.opacitySlider == nil,
    "config: the picker no longer offers any opacity control")
check(O.preview.tint[4] == 1, "config: the preview cover is fully opaque")
check(not ArachnaphobiaShieldSettings.enabled and C.ShownCount() == 0,
    "opacity: choosing an image never enables or reveals disabled covers")
capture(function() ArachnaphobiaShield.Slash("opacity 0.2") end)
check(C.pool[1].art.tint[4] == 1 and ArachnaphobiaShieldSettings.opacity == nil,
    "opacity: the retired command is an unknown subcommand and covers stay opaque")
ArachnaphobiaShieldSettings.opacity = 0.75
ArachnaphobiaShield.ready = false
ArachnaphobiaShield.OnEnterWorld()
check(ArachnaphobiaShieldSettings.opacity == nil and C.pool[1].art.tint[4] == 1,
    "opacity: a late-loaded legacy opacity value is retired and covers stay opaque")
capture(function() ArachnaphobiaShield.Slash("enable") end)
local liveSlot = ArachnaphobiaShield.track.nameplate1
local liveFrame = C.pool[liveSlot].frame
local liveParent = liveFrame.parent
capture(function() ArachnaphobiaShield.Slash("cover red") end)
check(C.pool[liveSlot].frame == liveFrame and liveFrame.parent == liveParent
    and liveFrame.mouse == false and C.pool[liveSlot].art.tint[4] == 1,
    "opacity: a live style change stays click-through and fully opaque")
capture(function() ArachnaphobiaShield.Slash("disable") end)
O.Close()

-- Rebuilding the picker must never request a native Slider frame, because a
-- Slider captures the mouse for dragging and froze the cursor in game.
O.frame = nil
local guardedCreateFrame = CreateFrame
local sliderRequested = false
CreateFrame = function(kind)
    if kind == "Slider" then sliderRequested = true end
    return guardedCreateFrame(kind)
end
O.Open()
CreateFrame = guardedCreateFrame
flushDisplay()
check(not sliderRequested and O.frame:IsShown() and O.opacityButtons == nil,
    "config: rebuilding the picker never requests a mouse-capturing Slider frame")
O.Close()

-- ---- /as reset: factory defaults --------------------------------------
-- State entering this section: tracking disabled, pool released.
capture(function() ArachnaphobiaShield.Slash("cover blue") end)
capture(function() ArachnaphobiaShield.Slash("grow 120") end)
capture(function() ArachnaphobiaShield.Slash("drop 1.25") end)
capture(function() ArachnaphobiaShield.Slash("near 1") end)
capture(function() ArachnaphobiaShield.Slash("name Reset Test Spider") end)
capture(function() ArachnaphobiaShield.Slash("debug on") end)
ArachnaphobiaShield.autoSuspended = true
O.Open()
O.input:SetText("Interface/AddOns/ArachnaphobiaShield/Custom/unsubmitted.tga")
capture(function() ArachnaphobiaShield.Slash("reset") end)
check(ArachnaphobiaShieldSettings.version == 4 and ArachnaphobiaShieldSettings.enabled == true
    and ArachnaphobiaShieldSettings.coverStyle == "fox" and ArachnaphobiaShieldSettings.customCover == ""
    and ArachnaphobiaShieldSettings.opacity == nil and ArachnaphobiaShieldSettings.coverSize == 96
    and ArachnaphobiaShieldSettings.trackScale == 1.0 and ArachnaphobiaShieldSettings.drop == 0.5
    and ArachnaphobiaShieldSettings.trackRelease == 0.5 and ArachnaphobiaShieldSettings.nearThreshold == 0
    and ArachnaphobiaShieldSettings.nearBoost == 2.6 and ArachnaphobiaShieldSettings.requireHostile == false
    and ArachnaphobiaShieldSettings.minLevel == 1 and ArachnaphobiaShieldSettings.maxLevel == 99
    and #ArachnaphobiaShieldSettings.extraNames == 0 and #ArachnaphobiaShieldSettings.namePatterns == 0
    and ArachnaphobiaShieldSettings.debug == false, "reset: every saved setting returns to the factory default")
check(ArachnaphobiaShieldSettings.autoTrack == nil and ArachnaphobiaShieldSettings.stickyCovers == nil
    and ArachnaphobiaShieldSettings.parkCount == nil and ArachnaphobiaShieldSettings.arrange == nil
    and ArachnaphobiaShieldSettings.covers == nil and ArachnaphobiaShieldSettings.color == nil
    and ArachnaphobiaShieldSettings.opacity == nil,
    "reset: retired settings are not reintroduced")
check(ArachnaphobiaShield.debug == false and ArachnaphobiaShield.autoSuspended == false
    and ArachnaphobiaShield.trackFailures == 0 and ArachnaphobiaShield.tickErrors == 0,
    "reset: runtime pause and debug state follow the restored defaults")
check(O.input:GetText() == "" and O.preview.texture[1] == P.PRESETS[1].path
    and O.preview.tint[4] == 1, "reset: an open picker refreshes to the defaults")
O.Close()
flushDisplay()
local resetSlot = ArachnaphobiaShield.track.nameplate1
check(resetSlot ~= nil and C.IsAllocated(resetSlot) and C.ShownCount() > 0
    and C.pool[resetSlot].frame.parent == _G["NamePlate1"]
    and C.pool[resetSlot].art.texture[1] == P.PRESETS[1].path
    and C.pool[resetSlot].art.tint[4] == 1 and C.pool[resetSlot].base.tint[4] == 0
    and C.pool[resetSlot].frame.mouse == false,
    "reset: tracking resumes with the default cover at full opacity, click-through")

-- Every cover, including recycled and quarantined frames, must have NEVER
-- received EnableMouse(true), not merely be click-through at the end.
local neverInteractive = true
for _, slot in ipairs(ArachnaphobiaShield.Cover.pool) do
    for _, on in ipairs(slot.frame.mouseHistory or {}) do if on then neverInteractive = false end end
end
check(neverInteractive and movementCalls == 0, "input: no cover ever accepts clicks or invokes client movement APIs")
check(legacyReads == 0, "input: no cursor or mouseover queries exist in any automatic path")
local sliderCreated = false
for _, kind in ipairs(_G.__frameKinds) do
    if kind == "Slider" then sliderCreated = true end
end
check(not sliderCreated, "input: no Slider frame is ever created anywhere in the addon")
local prohibitedAPI = false
for _, path in ipairs({ "ArachnaphobiaShield/Cover.lua", "ArachnaphobiaShield/Config.lua" }) do
    local sourceFile = assert(io.open(path, "rb"))
    local source = sourceFile:read("*a")
    sourceFile:close()
    for _, name in ipairs({ "SetMovable", "StartMoving", "StopMovingOrSizing", "RegisterForDrag",
        "OnDragStart", "OnDragStop", "GetPoint", "GetCenter", "GetRect", '"Slider"' }) do
        if source:find(name, 1, true) then prohibitedAPI = true end
    end
end
check(not prohibitedAPI, "input: cover and picker source contain no movement, drag, screen-measurement or Slider API")
if fails > 0 then
	error(fails .. " test(s) FAILED", 0)
end

print("ALL TESTS PASS")
