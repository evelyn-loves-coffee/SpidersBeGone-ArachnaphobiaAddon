-- Spiders Be Gone — Units.lua: the single spider predicate (M3).
-- Every "is this unit a spider?" decision goes through U.IsSpider.
SBeGone = SBeGone or {}

local U = {}
SBeGone.Units = U

-- Fallback name patterns (settings.namePatterns overrides at runtime).
U.NAME_PATTERNS = { "Spider", "Gloomweaver" }

-- Spider predicate (PLAN §3.1). `unit` is a tracked unit token.
function U.IsSpider(unit)
	local s = SBeGoneSettings or {}

	-- 1. Never cover players.
	--    SBG14 (in-game 2026-10-15, probe P3): UnitClass on this client
	--    returns the unit's NAME for non-player units — hovering the test
	--    spider reported class="Young Night Web Spider". The old "UnitClass is
	--    non-nil => player" guard therefore rejected EVERY spider (P4:
	--    IsSpider=false on a confirmed family-3 unit). Guards now, in order:
	--    a) UnitIsPlayer, accepted only on a strict boolean `true` so an
	--       implementation that (like UnitClass) returns a name can never
	--       false-reject a spider;
	--    b) name equality with our own name (catches players when
	--       UnitIsPlayer is absent).
	if UnitIsPlayer and UnitIsPlayer(unit) == true then
		return false
	end
	if UnitName then
		local uName = UnitName(unit)
		if uName ~= nil and uName == UnitName("player") then
			return false
		end
	end

	-- 2. Primary: creature family "Spider" (id 3) — confirmed in-client (SBG4).
	local isSpider = false
	if UnitCreatureFamily then
		local _, famId = UnitCreatureFamily(unit)
		if famId == 3 then
			isSpider = true
		end
	end

	-- 3. Fallback: name patterns + user extraNames (units reporting no family).
	--    plain find (no Lua patterns) — extraNames is user data.
	if not isSpider then
		local name
		if UnitName then
			name = UnitName(unit)
		elseif GetUnitName then
			name = GetUnitName(unit)
		end
		if name then
			local pats
			if type(s.namePatterns) == "table" and #s.namePatterns > 0 then
				pats = s.namePatterns
			else
				pats = U.NAME_PATTERNS
			end
			for _, pat in ipairs(pats) do
				if type(pat) == "string" and name:find(pat, 1, true) then
					isSpider = true
					break
				end
			end
			if not isSpider then
				for _, extra in ipairs(s.extraNames or {}) do
					if name == extra then
						isSpider = true
						break
					end
				end
			end
		end
	end

	if not isSpider then
		return false
	end

	-- 4. Level window.
	local lvl = (UnitLevel and UnitLevel(unit)) or 0
	local minL = (type(s.minLevel) == "number") and s.minLevel or 1
	local maxL = (type(s.maxLevel) == "number") and s.maxLevel or 99
	if lvl < minL or lvl > maxL then
		return false
	end

	-- 5. Optional hostile-only gate. UnitCanAttack is TWO-ARG on this client
	--    (SBG5): UnitCanAttack("player", unit) = "can I attack it".
	if s.requireHostile then
		if not (UnitCanAttack and UnitCanAttack("player", unit)) then
			return false
		end
	end

	return true
end
