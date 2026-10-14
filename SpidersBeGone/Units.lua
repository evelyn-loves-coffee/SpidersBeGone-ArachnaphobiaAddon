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

	-- 1. Never cover players (IsPlayerUnit absent; UnitClass replaces it, SBG5).
	if UnitClass and UnitClass(unit) then
		return false
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
