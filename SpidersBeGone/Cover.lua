-- Spiders Be Gone — Cover.lua: the 24-slot cover frame pool (M3).
-- Native tracked covers and optional manual shields share this pool.
-- Only explicit manual shields persist per character.
SBeGone = SBeGone or {}

local C = {}
SBeGone.Cover = C

C.MAX = 24
C.ART_PATH = "Interface\\AddOns\\SpidersBeGone\\cover.tga"
C.BACKDROP = { 14 / 255, 19 / 255, 36 / 255 }

C.pool = {}  -- [1..MAX] = { frame, base, art, x, y, w, h, kind }
C.queue = {} -- allocated slot indices, in allocation order (FIFO)
C.free = {}  -- free slot indices

-- This client's native CreateTexture is NOT the classic one. Its usage
-- string is "self:CreateTexture(params)" and it rejects the classic
-- "BACKGROUND" layer (in-game error 2026-10-14, SBG8: "bad argument #3 to
-- 'CreateTexture'"), while the working Spoken addon on this client uses the
-- (nil, "ARTWORK") form. So: try the proven layer first, pcall-guarded.
local LAYER_CANDIDATES = { "ARTWORK", "ART", "BACKGROUND", "MEDIUM", "LOW", "HIGH", "HIGHLIGHT" }
local function makeTexture(frame)
	for _, layer in ipairs(LAYER_CANDIDATES) do
		local ok, tex = pcall(frame.CreateTexture, frame, nil, layer)
		if ok and tex then
			return tex
		end
	end
	local ok, tex = pcall(frame.CreateTexture, frame)
	if ok and tex then
		return tex
	end
	return nil
end
C.CreateTexture = makeTexture

-- Full-color art over an opaque fallback covering the entire frame. Both
-- textures use the proven layer; base is created first so art draws over it.
local function makeFrame()
	local f = CreateFrame("Frame")
	f:SetParent(UIParent)
	f:SetFrameStrata("HIGH")
	-- Playability (owner rule, 2026-10-15): covers must NOT eat clicks by
	-- default — a mouse-enabled disc over the ground blocks moving/targeting
	-- there. Mouse is only enabled in /spider arrange mode (dragging).
	f:EnableMouse(C.IsInteractive())
	f:SetMovable(true)
	local base = makeTexture(f)
	local art = makeTexture(f)
	if base then base:SetAllPoints() end
	if art then art:SetAllPoints() end
	f:Hide()
	return f, base, art
end

-- Arrange mode: covers accept the mouse so they can be dragged and lined up.
-- Everything else is click-through; disabled covers never take input.
function C.IsInteractive()
	local s = SBeGoneSettings
	return (type(s) == "table" and s.enabled and s.arrange and not SBeGone.hidden) and true or false
end

function C.ApplyInteractivity()
	if not C.inited then return end
	local on = C.IsInteractive()
	for i = 1, C.MAX do
		local slot = C.pool[i]
		local interactive = on and not slot.pendingRelease
		-- An anchored frame cannot be dragged (and measuring it throws a taint
		-- error: it transitively touches the restricted plate), so arranging
		-- means letting go of every plate.
		if interactive and slot.anchored then
			interactive = C.Unanchor(i)
		end
		pcall(slot.frame.EnableMouse, slot.frame, interactive and true or false)
	end
end

function C.Init()
	if C.inited then return end
	C.inited = true
	C.pool = {}
	C.queue = {}
	C.free = {}
	for i = 1, C.MAX do
		local f, base, art = makeFrame()
		C.pool[i] = {
			frame = f, base = base, art = art, kind = "park",
			anchored = false, anchoredPlate = nil, anchoredDrop = 0,
			miss = 0,
		}
		C.free[#C.free + 1] = i
	end
	C.Clamp()
	C.ApplyStyle()
end

function C.Size()
	local s = SBeGoneSettings
	return (type(s) == "table" and type(s.coverSize) == "number") and s.coverSize or 96
end

-- Native screen clamp for clients that still have it. SetClampRect is
-- ABSENT on this client (SBG9: in-game "attempt to call a nil value");
-- the real keep-on-screen guarantee is the soft clamp in C.SyncDrags.
function C.Clamp()
	local sw, sh
	if GetEffectiveScreenInfo then
		sw, sh = GetEffectiveScreenInfo()
	end
	if type(sw) ~= "number" then sw, sh = 1920, 1080 end
	for i = 1, C.MAX do
		pcall(C.pool[i].frame.SetClampRect, C.pool[i].frame, 0, sw, 0, sh)
	end
end

-- Vertex tint with a pcall fallback for clients whose SetVertexColor
-- rejects the optional 4th (alpha) argument.
local function setTint(tex, r, g, b, a)
	local ok = pcall(tex.SetVertexColor, tex, r, g, b, a)
	if not ok then
		ok = pcall(tex.SetVertexColor, tex, r, g, b)
		if ok then pcall(tex.SetVertexAlpha, tex, a) end
	end
end

-- Some client builds return no value on success; only false or an error is
-- a detectable failure. A syntactically valid missing file may still show a
-- placeholder, so custom choices must be checked in the preview in game.
function C.PaintArt(tex, path)
	local ok, result = pcall(tex.SetTexture, tex, path)
	local loaded = ok and result ~= false
	if not loaded then pcall(tex.SetTexture, tex, C.ART_PATH) end
	setTint(tex, 1, 1, 1, 1)
	return loaded
end

-- Preserve the supplied artwork's colors. Old color/opacity settings must
-- not tint the fox or reveal a spider through the cover. The imported TGA
-- is also opaque, so coverage does not depend on the fallback texture.
function C.ApplyStyle()
	local path = SBeGone.Appearance.Current().path
	C.textureFailed = false
	for i = 1, C.MAX do
		local slot = C.pool[i]
		if slot.base then
			local ok, result = pcall(slot.base.SetTexture, slot.base, C.BACKDROP[1], C.BACKDROP[2], C.BACKDROP[3], 1)
			if not ok or result == false then C.textureFailed = true end
		end
		if slot.art then
			if not C.PaintArt(slot.art, path) then C.textureFailed = true end
		end
	end
end

-- Place a cover centered at (x, y) in UIParent/BOTTOMLEFT UI coordinates —
-- Epsilon: skip SetPoint when the position moved less than 1 UI pixel.
function C.Place(i, x, y)
	local slot = C.pool[i]
	if slot.anchored then return end -- the client owns this frame's position
	if type(x) ~= "number" or type(y) ~= "number" then return end
	if slot.frame:IsShown() and type(slot.x) == "number"
		and math.abs(slot.x - x) < 1 and math.abs(slot.y - y) < 1 then
		return
	end
	slot.x, slot.y = x, y
	slot.frame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)
	if SBeGoneSettings.enabled and not SBeGone.hidden and not slot.frame:IsShown() then
		slot.frame:Show()
	end
end

-- SetSize is absent on old clients (Spoken shims it with SetWidth +
-- SetHeight, both proven present) — fall back to those.
local function setSize(frame, w, h)
	local ok = pcall(frame.SetSize, frame, w, h)
	if not ok then
		pcall(frame.SetWidth, frame, w)
		pcall(frame.SetHeight, frame, h)
	end
end

function C.Resize(i, w, h)
	local slot = C.pool[i]
	-- Epsilon: auto-track re-sizes every tick from the plate's apparent width;
	-- skip the work when it barely moved.
	if type(w) == "number" and type(h) == "number"
		and type(slot.w) == "number" and type(slot.h) == "number"
		and math.abs(slot.w - w) < 1 and math.abs(slot.h - h) < 1 then
		return
	end
	slot.w, slot.h = w, h
	setSize(slot.frame, w, h)
end

-- Let go of a plate. Anchoring is the whole point of tracking, but the client
-- then refuses to measure our frame (in-game 2026-10-15: our own
-- Frame:GetPoint() reported "Can't measure restricted regions" once it was
-- anchored to a nameplate). So while anchored we never call GetPoint on the
-- frame — see C.SyncDrags and C.Save, which both skip anchored slots.
function C.Unanchor(i)
	local slot = C.pool[i]
	if not slot then return false end
	-- Pool slots are also used for manual covers. Detach OUR frame
	-- from the plate before it can be reused or measured as a screen cover.
	local parentOK = pcall(slot.frame.SetParent, slot.frame, UIParent)
	if not parentOK then SBeGone.coverageLimited = true; return false end
	if slot.frame.ClearAllPoints then
		local clearOK = pcall(slot.frame.ClearAllPoints, slot.frame)
		if not clearOK then return false end
	end
	-- Anchor state and explicit state are mutually exclusive: put the frame
	-- back under our own control at its last known free position.
	if type(slot.x) == "number" and type(slot.y) == "number" then
		local ok = pcall(slot.frame.SetPoint, slot.frame, "CENTER", UIParent, "BOTTOMLEFT", slot.x, slot.y)
		if not ok then return false end
	elseif slot.frame.SetPoint then
		-- An anchored cover has NO coordinates of its own (we never measure it),
		-- so put it somewhere findable instead of leaving it point-less: a frame
		-- with no anchor renders nowhere, which would make a released cover
		-- vanish mid-arrange. Centring needs no measurement.
		local ok = pcall(slot.frame.SetPoint, slot.frame, "CENTER", UIParent, "CENTER")
		if not ok then return false end
	end
	slot.anchored = false
	slot.anchoredPlate = nil
	slot.anchoredDrop = 0
	return true
end

-- Parent OUR cover to the plate as well as anchoring it. A UIParent child
-- with a cross-parent anchor remained parked on screen on the target client;
-- a plate child participates in the native world-frame movement/scale tree.
-- Size and dropY are plate-local units: perspective is inherited once, by
-- both the disc and its offset, between Lua polling ticks. Never measure it.
function C.PlaceTracked(i, plate, dropY)
	if not SBeGoneSettings.enabled or SBeGone.hidden then return false end
	local slot = C.pool[i]
	if not slot or not SBeGone.Access.FrameUsable(plate) or not slot.frame.SetPoint then return false end
	local mouseOK = pcall(slot.frame.EnableMouse, slot.frame, false)
	if not mouseOK then return false end
	dropY = dropY or 0
	-- Re-anchor only when the target changed or the offset moved >= 1 UI unit
	-- (same epsilon policy as C.Place) — 10 Hz x 24 slots stays trivial.
	if slot.anchored and slot.anchoredPlate == plate
		and math.abs((slot.anchoredDrop or 0) - dropY) < 1 then
		if not slot.frame:IsShown() then slot.frame:Show() end
		return true
	end
	if slot.frame.ClearAllPoints then
		local clearOK = pcall(slot.frame.ClearAllPoints, slot.frame)
		if not clearOK then return false end
	end
	local parentOK = pcall(slot.frame.SetParent, slot.frame, plate)
	if not parentOK then return false end
	-- Track attachment immediately, including when the following anchor is
	-- rejected. Cleanup must never mistake a plate child for a screen frame.
	slot.anchored = true
	slot.anchoredPlate = plate
	local ok = pcall(slot.frame.SetPoint, slot.frame, "CENTER", plate, "CENTER", 0, -dropY)
	if not ok then
		return false
	end
	slot.anchored = true
	slot.anchoredPlate = plate
	slot.anchoredDrop = dropY
	slot.x, slot.y = nil, nil
	if not slot.frame:IsShown() then slot.frame:Show() end
	return true
end

-- Eviction: free list first; otherwise sacrifice a slot of `prefer` kind
-- (so a screen full of spiders does not eat the owner's parked discs),
-- falling back to plain FIFO.
local function pickEvict(prefer)
	local oldestAny, oldestPrefer = nil, nil
	for i = 1, C.MAX do
		local slot = C.pool[i]
		if slot.allocated then
			if prefer and slot.kind == prefer then
				if not oldestPrefer or slot.seq < C.pool[oldestPrefer].seq then
					oldestPrefer = i
				end
			end
			if not oldestAny or slot.seq < C.pool[oldestAny].seq then
				oldestAny = i
			end
		end
	end
	return oldestPrefer or oldestAny
end

-- Take a slot from the pool (free list first, else evict preferentially,
-- else oldest = FIFO).
function C.Allocate(kind, x, y, prefer)
	local i
	for attempt = 1, C.MAX do
		if #C.free > 0 then
			i = table.remove(C.free)
			break
		else
			local victim = pickEvict(prefer)
			if not victim then return nil end
			-- Tell the previous owner before recycling its slot.
			if C.onEvict then
				local ok, err = pcall(C.onEvict, victim)
				if not ok and SBeGone.debug then
					print("SBG| onEvict hook error: " .. tostring(err))
				end
			end
			-- A refused detach quarantines that slot. Try another slot instead
			-- of reusing a frame still attached to a restricted nameplate.
			C.Release(victim)
		end
	end
	if not i then
		if #C.free == 0 then return nil end
		i = table.remove(C.free)
	end
	local slot = C.pool[i]
	if not C.Unanchor(i) then
		slot.pendingRelease = true
		slot.anchored = true
		return nil
	end
	C.queue[#C.queue + 1] = i
	slot.kind = kind
	slot.allocated = true
	slot.seq = (C.seq or 0) + 1
	C.seq = slot.seq
	slot.miss = 0
	slot.x, slot.y = nil, nil
	C.Resize(i, C.Size(), C.Size())
	C.Place(i, x, y)
	return i
end

-- Allocate a cover with no position yet (auto-track anchors it immediately).
function C.AllocateUnpositioned(kind, prefer)
	return C.Allocate(kind, nil, nil, prefer)
end

function C.IsAllocated(i)
	local slot = C.pool[i]
	return slot ~= nil and slot.allocated == true
end

-- Who owns a slot right now ("park" / "track"). Callers that key a
-- map on a slot INDEX must check this before adopting it: indices are recycled,
-- so a stale index can point at somebody else's manual shield.
function C.KindOf(i)
	local slot = (type(i) == "number") and C.pool[i] or nil
	return slot and slot.allocated and slot.kind or nil
end

-- Return a slot to the pool (cover disappears).
function C.Release(i)
	local slot = C.pool[i]
	if not slot then return false end
	if not slot.allocated and not slot.pendingRelease then return true end
	pcall(slot.frame.Hide, slot.frame)
	local detached = C.Unanchor(i)
	slot.pendingRelease = not detached
	if not detached then slot.anchored = true end
	slot.allocated = false
	slot.x, slot.y = nil, nil
	for q = #C.queue, 1, -1 do
		if C.queue[q] == i then
			table.remove(C.queue, q)
			break
		end
	end
	if detached then C.free[#C.free + 1] = i end
	return detached
end

-- Retry deferred cleanup through normal APIs only. A slot that cannot be
-- detached is excluded from allocation, persistence and drag measurement.
function C.RetryReleases()
	if not C.inited then return end
	local pending = false
	for i = 1, C.MAX do
		if C.pool[i].pendingRelease then C.Release(i) end
		if C.pool[i].pendingRelease then pending = true end
	end
	if not pending and C.deferredRestore then C.Restore(C.deferredRestore) end
end

function C.HideAll()
	if not C.inited then return end
	for i = 1, C.MAX do
		pcall(C.pool[i].frame.Hide, C.pool[i].frame)
	end
end

function C.ClearAll()
	C.deferredRestore = nil
	C.queue = {}
	C.free = {}
	for i = 1, C.MAX do
		local slot = C.pool[i]
		pcall(slot.frame.Hide, slot.frame)
		local detached = C.Unanchor(i)
		slot.pendingRelease = not detached
		if not detached then slot.anchored = true end
		slot.allocated = false
		slot.x, slot.y = nil, nil
		if detached then C.free[#C.free + 1] = i end
	end
end

function C.ShownCount()
	if not C.inited then return 0 end
	local n = 0
	for i = 1, C.MAX do
		if SBeGone.Access.Query(C.pool[i].frame.IsShown, C.pool[i].frame) == true then n = n + 1 end
	end
	return n
end

-- Covers are SetMovable frames: when the user drags one, adopt the new
-- position into pool state and persist it (called every tick).
-- Soft clamp: SetClampRect is absent on this client (SBG9), so keep each
-- cover's center inside the screen ourselves — a cover can never be
-- dragged away and lost.
function C.SyncDrags()
	if not C.inited then return end
	local sw, sh
	if GetEffectiveScreenInfo then sw, sh = GetEffectiveScreenInfo() end
	if type(sw) ~= "number" then sw, sh = 1920, 1080 end
	local changed = false
	for i = 1, C.MAX do
		local slot = C.pool[i]
		-- Anchored (tracked) covers are positioned by the client from a
		-- restricted frame: measuring them throws
		-- "Action[FrameMeasurement] failed ... restricted regions" (SBG15), so
		-- they are never polled here.
		if slot.frame:IsShown() and not slot.anchored and type(slot.x) == "number" then
			-- GetPoint returns (point, relativeToFrame, relativeToPoint, x, y,
			-- ...) — the offsets are the 4th and 5th returns (SBG12). Reading
			-- the 3rd/4th (as before) gives x = "BOTTOMLEFT" (a string), so
			-- drags were never adopted in-game.
			local _, _, _, x, y = slot.frame:GetPoint(0, UIParent, "BOTTOMLEFT")
			if type(x) == "number"
				and (math.abs(x - slot.x) > 0.5 or math.abs(y - slot.y) > 0.5) then
				local liveX, liveY = x, y
				if x < 0 then x = 0 elseif x > sw then x = sw end
				if y < 0 then y = 0 elseif y > sh then y = sh end
				slot.x, slot.y = x, y
				changed = true
				if math.abs(liveX - x) > 0.5 or math.abs(liveY - y) > 0.5 then
					slot.frame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)
				end
			end
		end
	end
	if changed then
		C.Save()
	end
end

-- Persist the current pool for the current character, as a v2 record:
--   covers[char] = { init = true, list = { {x,y,w,h,kind}, ... } }
-- The wrapper is never empty, so an intentional "cleared" state (list = {}) is
-- still recognizable as "this character has run" after a SavedVariables
-- round-trip. In the v1 form a cleared character was stored as a bare empty
-- table, which is indistinguishable from "never ran" the moment the client's
-- writer/loader drops empty values (SBG13). An empty list means
-- "intentionally cleared" — Restore() will not respawn defaults.
-- Alloc-based, NOT IsShown-based: on this client Show() is deferred to the
-- next display pass, so IsShown() is still false when Restore() saves right
-- after allocating (in-game 2026-10-15: covers shown=8 but saved=0; the
-- WSV file had covers[<char>] = {}). A slot in C.queue with coordinates is
-- exactly the allocation state we want to persist.
function C.Save()
	-- A temporarily exhausted pool must not overwrite a saved layout with
	-- only the subset that could be restored while detachment was blocked.
	if C.deferredRestore then return end
	local char = SBeGone.char
	local s = SBeGoneSettings
	if not char or not s then return end
	if type(s.covers) ~= "table" then s.covers = {} end
	local list = {}
	for _, i in ipairs(C.queue) do
		local slot = C.pool[i]
		-- Persist only what WE positioned. Auto-track (anchored) covers are
		-- excluded on purpose: their position belongs to a spider that will not
		-- exist next session, and an anchored frame cannot be measured anyway.
		if slot.allocated and slot.kind == "park" and not slot.anchored
			and type(slot.x) == "number" and type(slot.y) == "number" then
			list[#list + 1] = { x = slot.x, y = slot.y, w = slot.w, h = slot.h, kind = slot.kind }
		end
	end
	s.covers[char] = { init = true, list = list }
end

-- Default pre-park layout: a row of shields near the top of the screen.
local function DefaultParkPos(n, size)
	local sw, sh
	if GetEffectiveScreenInfo then
		sw, sh = GetEffectiveScreenInfo()
	end
	if type(sw) ~= "number" then sw, sh = 1920, 1080 end
	local gap = 24
	return 100 + (n - 1) * (size + gap), sh - 80
end

-- Read a character's cover list, migrating the v1 bare-list form on the fly.
-- Returns (list, firstRun); firstRun is true only when there is no record at
-- all for the character. A v1 table — even an empty one — counts as "has run",
-- so a cleared character is not re-parked.
function C.SavedList(s, char)
	if type(s.covers) ~= "table" then s.covers = {} end
	local rec = s.covers[char]
	if type(rec) ~= "table" then
		return {}, true
	end
	local firstRun = type(rec.list) == "table" and rec.init ~= true
	local list = type(rec.list) == "table" and rec.list or rec
	local out = {}
	for _, e in ipairs(list) do
		-- Retired cursor covers (including legacy records with no kind) must
		-- never reappear. Keep only explicitly parked manual shields.
		if type(e) == "table" and e.kind == "park" then out[#out + 1] = e end
	end
	s.covers[char] = { init = not firstRun, list = out }
	return out, firstRun
end

-- Spawn n default pre-parked shields (a row near the top-left).
function C.Park(n)
	local placed = 0
	for k = 1, (n or 0) do
		local x, y = DefaultParkPos(k, C.Size())
		if C.Allocate("park", x, y) then placed = placed + 1 end
	end
	return placed
end

-- Release every allocated cover of a kind (used by /spider parks).
function C.RemoveKind(kind)
	for q = #C.queue, 1, -1 do
		local i = C.queue[q]
		if C.pool[i].kind == kind then
			C.Release(i)
		end
	end
end

-- Rebuild the pool for a character: saved covers first, then — only on the
-- character's very first run (no saved list at all) — the default pre-parked
-- shields. Persists the result.
function C.Restore(char)
	C.Init()
	C.ApplyStyle() -- settings may have arrived after the pool was initialized
	SBeGone.char = char
	C.ClearAll()
	local s = SBeGoneSettings or {}
	local saved, firstRun = C.SavedList(s, char)
	local complete = true
	for _, e in ipairs(saved) do
		if type(e) == "table" and type(e.x) == "number" and type(e.y) == "number" then
			local i = C.Allocate("park", e.x, e.y)
			local w = (type(e.w) == "number") and e.w or C.Size()
			local h = (type(e.h) == "number") and e.h or w
			if i then C.Resize(i, w, h) else complete = false end
		end
	end
	local parks = (type(s.parkCount) == "number") and s.parkCount or 0
	if firstRun then
		if C.Park(parks) < parks then complete = false end
	end
	if SBeGone.debug then
		-- SBG13 diagnostic: one line per restore, so chat alone settles
		-- whether SavedVariables were applied before we restored.
		print(("SBG| restore: settingsAtScriptLoad=%s firstRun=%s saved=%d parks=%d"):format(
			tostring(SBeGone.loadSnapshot and SBeGone.loadSnapshot.settingsPresent),
			tostring(firstRun), #saved, firstRun and parks or 0))
	end
	if not complete then
		C.deferredRestore = char
		SBeGone.coverageLimited = true
		return false
	end
	C.Save()
	return true
end
