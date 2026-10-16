-- Public API boundary. Unavailable/secret values mean unavailable coverage;
-- they are never converted, compared, or recovered through another channel.
SBeGone = SBeGone or {}
local A = {}
SBeGone.Access = A

function A.CanRead(value)
	if type(issecretvalue) == "function" then
		local ok, secret = pcall(issecretvalue, value)
		if not ok or secret then SBeGone.coverageLimited = true; return false end
	end
	if type(canaccessvalue) == "function" then
		local ok, accessible = pcall(canaccessvalue, value)
		if not ok or not accessible then SBeGone.coverageLimited = true; return false end
	end
	return true
end

-- The callers need at most two return values. Check BOTH before exposing
-- either to detection, table keys, string matching, or size arithmetic.
function A.Query(fn, ...)
	if type(fn) ~= "function" then return nil, nil, false end
	local ok, first, second = pcall(fn, ...)
	if not ok or not A.CanRead(first) or not A.CanRead(second) then
		return nil, nil, false
	end
	return first, second, true
end

function A.UnitReadable(unit)
	if not A.CanRead(unit) or type(unit) ~= "string" then return false end
	local query = C_Secrets and C_Secrets.ShouldUnitIdentityBeSecret
	if type(query) == "function" then
		local secret, _, ok = A.Query(query, unit)
		if not ok or secret ~= false then SBeGone.coverageLimited = true; return false end
	end
	return true
end

function A.FrameUsable(frame)
	if not A.CanRead(frame) then return false end
	local kind = type(frame)
	if kind ~= "table" and kind ~= "userdata" then return false end
	local method, _, readable = A.Query(function() return frame.IsForbidden end)
	if not readable then return false end
	if type(method) == "function" then
		local forbidden, _, ok = A.Query(method, frame)
		if not ok or forbidden ~= false then SBeGone.coverageLimited = true; return false end
	end
	return true
end
