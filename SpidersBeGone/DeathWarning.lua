-- A brief, click-through notice when an observed spider dies. This does not
-- position a corpse cover, inspect the combat log, or query pointer input.
SBeGone = SBeGone or {}
local W = { DURATION = 1.75, RECENT_SECONDS = 3, MAX_RECENT = 80 }
SBeGone.DeathWarning = W
local A = SBeGone.Access
W.byToken, W.byGUID = {}, {}
W.generation = 0

local function running()
	return SBeGone.ready and SBeGoneSettings and SBeGoneSettings.enabled
		and not SBeGoneSettings.arrange and not SBeGone.hidden and not SBeGone.autoSuspended
end

local function now()
	local value = A.Query(GetTime)
	return type(value) == "number" and value or nil
end

function W.Hide()
	W.generation = W.generation + 1
	W.expires = nil
	if W.frame then pcall(W.frame.Hide, W.frame) end
end

function W.Clear()
	W.Hide()
	W.byToken, W.byGUID = {}, {}
end

local MESSAGE = "LOOK AWAY\nSpider corpse may be visible."
local function popup()
	if W.frame then return W.frame end
	local frame
	local ok = pcall(function()
		frame = CreateFrame("Frame")
		frame:SetParent(UIParent)
		frame:SetFrameStrata("HIGH")
		if frame.SetFrameLevel then pcall(frame.SetFrameLevel, frame, 100) end
		frame:SetWidth(560)
		frame:SetHeight(110)
		frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
		frame:EnableMouse(false)
		frame:Hide()
		local background = frame:CreateTexture(nil, "ARTWORK")
		background:SetAllPoints()
		background:SetTexture(0.08, 0.03, 0.03, 0.95)
		local text = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
		text:SetAllPoints(frame)
		text:SetText(MESSAGE)
		if text.SetFont then pcall(text.SetFont, text, "Fonts\\FRIZQT__.TTF", 26, "OUTLINE") end
		if text.SetTextColor then pcall(text.SetTextColor, text, 1, 0.85, 0.25, 1) end
		if text.SetJustifyH then pcall(text.SetJustifyH, text, "CENTER") end
		if text.SetJustifyV then pcall(text.SetJustifyV, text, "MIDDLE") end
		frame.text = text
	end)
	if not ok then
		if frame then pcall(frame.Hide, frame) end
		W.popupUnavailable = true
		return nil
	end
	W.frame, W.popupUnavailable = frame, false
	return frame
end

local function warn(record, time)
	if record.warned or not running() then return end
	record.warned = true
	local frame = popup()
	if not frame or not pcall(frame.Show, frame) then
		print("SBG| LOOK AWAY - spider corpse may be visible (warning popup unavailable)")
		return
	end
	W.generation = W.generation + 1
	local generation = W.generation
	W.expires = time + W.DURATION
	if C_Timer and C_Timer.After then
		C_Timer.After(W.DURATION, function()
			if W.generation == generation then W.Hide() end
		end)
	end
end

function W.ForgetToken(token, forgetGUID)
	local record = W.byToken[token]
	if forgetGUID and record and record.guid then W.byGUID[record.guid] = nil end
	W.byToken[token] = nil
end

local function prune(time)
	local count, oldestGUID, oldest = 0, nil, math.huge
	for guid, record in pairs(W.byGUID) do
		if time - record.seen > W.RECENT_SECONDS then
			W.byGUID[guid] = nil
		else
			count = count + 1
			if record.seen < oldest then oldestGUID, oldest = guid, record.seen end
		end
	end
	if count >= W.MAX_RECENT and oldestGUID then W.byGUID[oldestGUID] = nil end
end

-- Called only after the ordinary nameplate predicate identifies a spider.
function W.Observe(token)
	if not running() or not A.UnitReadable(token) then return end
	local guid
	if type(UnitGUID) == "function" then
		local value, _, readable = A.Query(UnitGUID, token)
		if not readable then W.ForgetToken(token, true); return end
		if type(value) == "string" then guid = value end
	end
	local time = now()
	if not time then return end
	local record = W.byToken[token]
	if not record or record.guid ~= guid then
		record = (guid and W.byGUID[guid]) or { guid = guid }
	end
	record.seen = time
	W.byToken[token] = record
	if guid then
		if not W.byGUID[guid] then prune(time) end
		W.byGUID[guid] = record
	end
	local dead = A.Query(UnitIsDead, token)
	if dead == false and not guid then record.warned = false end
	if dead == true then warn(record, time) end
end

-- A health/flags/removal event may precede the next scan. Reconfirm identity
-- so token reuse or newly restricted data cannot warn about another unit.
function W.CheckUnit(token)
	if not running() or not A.CanRead(token) or type(token) ~= "string"
		or not W.byToken[token] then return end
	if not A.UnitReadable(token) then W.ForgetToken(token, true); return end
	if UnitExists and A.Query(UnitExists, token) ~= true then return end
	local record = W.byToken[token]
	if record.guid then
		local guid, _, readable = A.Query(UnitGUID, token)
		if not readable then W.ForgetToken(token, true); return end
		if guid ~= record.guid then W.ForgetToken(token); return end
	elseif not SBeGone.Units.IsSpider(token) then
		W.ForgetToken(token)
		return
	end
	local time = now()
	if time and A.Query(UnitIsDead, token) == true then warn(record, time) end
end

-- A readable GUID event can arrive just after a native plate is removed.
-- Only recently observed spiders qualify; no GUID parsing/unseen detection.
function W.OnDeath(guid)
	if not running() or not A.CanRead(guid) or type(guid) ~= "string" then return end
	local record, time = W.byGUID[guid], now()
	if not record or not time or time - record.seen > W.RECENT_SECONDS then return end
	for token, active in pairs(W.byToken) do
		if active == record and not A.UnitReadable(token) then
			W.ForgetToken(token, true)
			return
		end
	end
	warn(record, time)
end

function W.Tick()
	if not SBeGone.ready or not SBeGoneSettings or not SBeGoneSettings.enabled or SBeGone.hidden then
		W.Clear()
		return
	end
	local time = now()
	if not time then return end
	if W.expires and time >= W.expires then W.Hide() end
	if not running() then W.byToken, W.byGUID = {}, {}; return end
	prune(time)
	for token, record in pairs(W.byToken) do
		if time - record.seen > W.RECENT_SECONDS then
			W.ForgetToken(token)
		else
			W.CheckUnit(token)
		end
	end
end
