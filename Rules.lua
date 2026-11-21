-- Pure loot competition rules. No game API in this file, so the test harness
-- can load it under a plain Lua interpreter.
--
-- Model: every build wants one or more gear lanes (physical, spell, healing,
-- tank) and wears one armor type. Two players compete when they want the same
-- lane; spell and healing count as one because spell power serves both.
--
-- Physical and tank gear goes by armor type: a warrior rolls on mail or
-- plate, not on a druid's leather, so two players WILL compete only in the
-- same armor and otherwise MIGHT, over weapons, cloaks and jewelry. Spell
-- power gear is different: most of it is cloth and every caster and healer
-- rolls on it, so those lanes WILL compete whatever the armor.
--
-- An offspec counts like a main spec, because hybrids level in one spec and
-- group in another; it is reported as OFFSPEC. An unclear spec is a MIGHT.

local _, ns = ...
ns = ns or {}

local R = {}
ns.Rules = R

-- How sure we are that a player wants a lane.
R.MAIN, R.MAYBE, R.OFF = 3, 2, 1
-- How two players compete: main spec against main spec, through someone's
-- offspec, or only possibly.
R.WILL, R.OFFSPEC, R.MIGHT = 3, 2, 1

R.LANES = { "physical", "spell", "healing", "tank" }

-- Talent tree numbers follow the talent pane order for each class. `also`
-- lists lanes a build picks from without gearing for them outright (plate
-- tanks take damage pieces for threat).
R.BUILDS = {
	WARRIOR = {
		{ key = "dps", name = "Arms or Fury", role = "DAMAGER", trees = { 1, 2 }, lanes = { "physical" } },
		{ key = "tank", name = "Protection", role = "TANK", trees = { 3 }, lanes = { "tank" }, also = { "physical" } },
	},
	PALADIN = {
		{ key = "holy", name = "Holy", role = "HEALER", trees = { 1 }, lanes = { "healing" } },
		{ key = "tank", name = "Protection", role = "TANK", trees = { 2 }, lanes = { "tank" }, also = { "physical" } },
		{ key = "ret", name = "Retribution", role = "DAMAGER", trees = { 3 }, lanes = { "physical" } },
	},
	HUNTER = {
		{ key = "hunter", name = "Hunter", role = "DAMAGER", trees = { 1, 2, 3 }, lanes = { "physical" } },
	},
	ROGUE = {
		{ key = "rogue", name = "Rogue", role = "DAMAGER", trees = { 1, 2, 3 }, lanes = { "physical" } },
	},
	PRIEST = {
		{ key = "heal", name = "Discipline or Holy", role = "HEALER", trees = { 1, 2 }, lanes = { "healing" } },
		{ key = "shadow", name = "Shadow", role = "DAMAGER", trees = { 3 }, lanes = { "spell" } },
	},
	SHAMAN = {
		{ key = "ele", name = "Elemental", role = "DAMAGER", trees = { 1 }, lanes = { "spell" } },
		{ key = "enh", name = "Enhancement", role = "DAMAGER", trees = { 2 }, lanes = { "physical" } },
		{ key = "resto", name = "Restoration", role = "HEALER", trees = { 3 }, lanes = { "healing" } },
	},
	MAGE = {
		{ key = "mage", name = "Mage", role = "DAMAGER", trees = { 1, 2, 3 }, lanes = { "spell" } },
	},
	WARLOCK = {
		{ key = "warlock", name = "Warlock", role = "DAMAGER", trees = { 1, 2, 3 }, lanes = { "spell" } },
	},
	DRUID = {
		{ key = "balance", name = "Balance", role = "DAMAGER", trees = { 1 }, lanes = { "spell" } },
		{ key = "cat", name = "Feral (cat)", role = "DAMAGER", trees = { 2 }, lanes = { "physical" } },
		{ key = "bear", name = "Feral (bear)", role = "TANK", trees = { 2 }, lanes = { "physical", "tank" } },
		{ key = "resto", name = "Restoration", role = "HEALER", trees = { 3 }, lanes = { "healing" } },
	},
}

-- Armor type by class. A list entry is { armor before the level, level, armor from it }.
R.ARMOR = {
	MAGE = "cloth",
	WARLOCK = "cloth",
	PRIEST = "cloth",
	ROGUE = "leather",
	DRUID = "leather",
	HUNTER = { "leather", 40, "mail" },
	SHAMAN = { "leather", 40, "mail" },
	WARRIOR = { "mail", 40, "plate" },
	PALADIN = { "mail", 40, "plate" },
}

local function contains(list, value)
	for i = 1, #list do
		if list[i] == value then return true end
	end
	return false
end

function R.armor(class, level)
	local armor = R.ARMOR[class]
	if type(armor) ~= "table" then return armor end
	if level and level < armor[2] then return armor[1] end
	return armor[3]
end

function R.build(class, key)
	for _, build in ipairs(R.BUILDS[class] or {}) do
		if build.key == key then return build end
	end
end

local ROLE_ORDER = { "TANK", "HEALER", "DAMAGER" }

function R.classRoles(class)
	local has = {}
	for _, build in ipairs(R.BUILDS[class] or {}) do
		has[build.role] = true
	end
	local roles = {}
	for _, role in ipairs(ROLE_ORDER) do
		if has[role] then roles[#roles + 1] = role end
	end
	return roles
end

-- The builds a profile plausibly plays as a main spec. A profile is
-- { class, level, roles = { TANK = true, ... }, tree = 1..3, build = key };
-- everything except class is optional.
function R.mainBuilds(profile)
	local main = R.BUILDS[profile.class] or {}
	local function narrow(keep)
		local kept = {}
		for _, build in ipairs(main) do
			if keep(build) then kept[#kept + 1] = build end
		end
		if #kept > 0 then main = kept end
	end
	if profile.build and R.build(profile.class, profile.build) then
		narrow(function(build) return build.key == profile.build end)
		return main
	end
	if profile.roles and next(profile.roles) then narrow(function(build) return profile.roles[build.role] end) end
	if profile.tree then narrow(function(build) return contains(build.trees, profile.tree) end) end
	return main
end

-- Every rule a player can tune, with its default. Callers pass a table with
-- any of these keys as opts; missing keys fall back to the default.
R.DEFAULTS = {
	caredOnly = true, -- only warn when the player, a friend or a guildmate is involved
	offspec = true, -- hybrids also roll for their other specs
	shared = true, -- casters and healers roll on the same spell power gear
	cloth = true, -- casters and healers in leather, mail and plate roll on cloth
	rollDown = false, -- heavier armor wearers roll on lighter physical and tank armor
	tankDamage = true, -- plate tanks pick up damage gear
	unsure = true, -- report conflicts that depend on an unknown spec
	accessories = true, -- report conflicts over weapons, cloaks and jewelry only
}

local function on(opts, key)
	local value = opts and opts[key]
	if value == nil then return R.DEFAULTS[key] end
	return value
end

-- lane -> MAIN, MAYBE or OFF for every lane the profile could roll on.
-- Also returns a set of lanes added only via build.also (such as plate tanks
-- picking up damage pieces). The player's own offspec is never guessed.
function R.wants(profile, opts)
	local main = R.mainBuilds(profile)
	local seen = {}
	for _, build in ipairs(main) do
		for _, lane in ipairs(build.lanes) do
			seen[lane] = (seen[lane] or 0) + 1
		end
	end
	local wants, also = {}, {}
	for lane, count in pairs(seen) do
		wants[lane] = count == #main and R.MAIN or R.MAYBE
	end
	for _, build in ipairs(main) do
		for _, lane in ipairs(on(opts, "tankDamage") and build.also or {}) do
			if not wants[lane] then
				wants[lane] = R.MAYBE
				also[lane] = true
			end
		end
	end
	if profile.isSelf then return wants, also end
	for _, build in ipairs(R.BUILDS[profile.class] or {}) do
		for _, lane in ipairs(build.lanes) do
			wants[lane] = wants[lane] or R.OFF
		end
	end
	return wants, also
end

-- Lane of the first profile, lane of the second, and the name of what they
-- fight over. Spell power heals and deals damage alike, so the last two rows
-- pit casters against healers.
local MATCHUPS = {
	{ "physical", "physical", "physical" },
	{ "spell", "spell", "spell" },
	{ "healing", "healing", "healing" },
	{ "tank", "tank", "tank" },
	{ "spell", "healing", "spellpower" },
	{ "healing", "spell", "spellpower" },
}

local ARMOR_RANK = { cloth = 1, leather = 2, mail = 3, plate = 4 }

-- The strongest competition between two profiles, or nil.
-- Result: { severity, lane, reason, offspec, lighter }.
-- reason is "same" (same armor), "cloth" (spell power gear, whatever they
-- wear), "wears" (the heavier wearer rolls on the armor of `lighter`),
-- "armor" (only weapons, cloaks and jewelry), "tankDamage" (plate tank
-- taking damage pieces) or "unsure". offspec names the profile competing
-- through an offspec.
--
-- matters(profile), when given, says whose losses count. Without it everyone's
-- do. An offspec roll counts only when the one losing main spec gear to it
-- matters, and rolling down only when the lighter wearer does.
function R.compare(a, b, opts, matters)
	local wantsA, alsoA = R.wants(a, opts)
	local wantsB, alsoB = R.wants(b, opts)
	local rankA, rankB = ARMOR_RANK[R.armor(a.class, a.level)], ARMOR_RANK[R.armor(b.class, b.level)]
	if not rankA or not rankB then return nil end
	local lighter = rankA ~= rankB and (rankA < rankB and a or b) or nil
	local best
	for _, matchup in ipairs(MATCHUPS) do
		local wa, wb = wantsA[matchup[1]], wantsB[matchup[2]]
		local guess = wa == R.OFF or wb == R.OFF
		local holder = guess and (wa == R.OFF and a or b) or nil
		local skipped = (matchup[1] ~= matchup[2] and not on(opts, "shared"))
			or (guess and (not on(opts, "offspec") or (matters and not matters(holder == a and b or a))))
		-- Two offspecs, or an unclear spec against an offspec, is too thin to mention.
		if wa and wb and wa + wb >= 4 and not skipped then
			local found = { lane = matchup[3], weight = wa + wb, offspec = holder }
			local worn = matchup[3] == "physical" or matchup[3] == "tank"
			if not guess and (wa == R.MAYBE or wb == R.MAYBE) then
				local aAlso = wa == R.MAYBE and alsoA[matchup[1]]
				local bAlso = wb == R.MAYBE and alsoB[matchup[2]]
				if (wa == R.MAIN or aAlso) and (wb == R.MAIN or bAlso) and (aAlso or bAlso) then
					found.severity, found.reason = R.MIGHT, "tankDamage"
				else
					found.severity, found.reason = R.MIGHT, "unsure"
				end
			elseif not lighter then
				found.severity, found.reason = R.WILL, "same"
			elseif not worn and on(opts, "cloth") then
				found.severity, found.reason = R.WILL, "cloth"
			elseif worn and on(opts, "rollDown") and holder ~= lighter and (not matters or matters(lighter)) then
				found.severity, found.reason, found.lighter = R.WILL, "wears", lighter
			else
				found.severity, found.reason = R.MIGHT, "armor"
			end
			if found.offspec and found.severity == R.WILL then found.severity = R.OFFSPEC end
			local wanted = (found.reason ~= "unsure" or on(opts, "unsure")) and (found.reason ~= "armor" or on(opts, "accessories"))
			if wanted and (not best or found.severity > best.severity or (found.severity == best.severity and found.weight > best.weight)) then best = found end
		end
	end
	return best
end

-- Every competition between a set of candidates and the current group.
-- Profiles may carry isSelf (the player) and cared (friend or guildmate).
-- With opts.caredOnly, a pair counts only when it involves the player or
-- someone the player cares about, and only their losses count.
function R.evaluate(candidates, group, opts)
	local caredOnly = on(opts, "caredOnly")
	local function matters(profile) return profile.isSelf or profile.cared end
	local found = {}
	for _, candidate in ipairs(candidates) do
		for _, member in ipairs(group) do
			if not caredOnly or matters(member) or matters(candidate) then
				local conflict = R.compare(candidate, member, opts, caredOnly and matters or nil)
				if conflict then
					conflict.candidate, conflict.member = candidate, member
					found[#found + 1] = conflict
				end
			end
		end
	end
	table.sort(found, function(x, y)
		if x.severity ~= y.severity then return x.severity > y.severity end
		if (x.member.isSelf or false) ~= (y.member.isSelf or false) then return x.member.isSelf or false end
		return x.weight > y.weight
	end)
	return found, found[1] and found[1].severity or nil
end

local LANE_TEXT = { physical = "physical", spell = "spell", healing = "healing", tank = "tank", spellpower = "spell power" }

local function offspecSuffix(conflict)
	if not conflict.offspec then return "" end
	if conflict.offspec == conflict.candidate then return " (their offspec)" end
	if conflict.member.isSelf then return " (your offspec)" end
	return (" (%s's offspec)"):format(conflict.member.name or "a party member")
end

-- Short reasoning for a conflict, suitable for tooltip highlights and chat.
function R.reasonText(conflict)
	local lane = LANE_TEXT[conflict.lane]
	local suffix = offspecSuffix(conflict)
	if conflict.reason == "same" or conflict.reason == "cloth" or conflict.reason == "wears" then
		local wearer = conflict.lighter or conflict.member
		local armor = conflict.reason == "cloth" and "cloth" or R.armor(wearer.class, wearer.level)
		return ("%s %s%s"):format(armor, lane, suffix)
	elseif conflict.reason == "armor" then
		return "weapons, cloaks, jewelry" .. suffix
	elseif conflict.reason == "tankDamage" then
		return lane .. " (tank damage)"
	end
	return lane .. " (spec unknown)"
end

-- One concise line for a conflict from R.evaluate.
function R.describe(conflict)
	local who = conflict.candidate.name or "They"
	local other = conflict.member.isSelf and "you" or (conflict.member.name or "a party member")
	return ("%s vs %s: %s"):format(who, other, R.reasonText(conflict))
end

-- What is at stake, in a few words, for a list: "leather physical, OS".
function R.brief(conflict)
	if conflict.reason == "armor" then return conflict.offspec and "weapons, jewelry, OS" or "weapons, cloaks, jewelry" end
	if conflict.reason == "tankDamage" then return "tank damage" end
	if conflict.reason == "unsure" then return "spec unknown" end
	local wearer = conflict.lighter or conflict.member
	local armor = conflict.reason == "cloth" and "cloth" or R.armor(wearer.class, wearer.level)
	return ("%s %s%s"):format(armor, LANE_TEXT[conflict.lane], conflict.offspec and ", OS" or "")
end

local ROLE_WORDS = {
	tank = "TANK", tanking = "TANK", bear = "TANK", prot = "TANK", protection = "TANK", mt = "TANK", ot = "TANK", offtank = "TANK",
	heal = "HEALER", heals = "HEALER", healer = "HEALER", healing = "HEALER", resto = "HEALER", restoration = "HEALER",
	holy = "HEALER", disc = "HEALER", discipline = "HEALER", hpal = "HEALER", hpala = "HEALER", hpriest = "HEALER",
	rdruid = "HEALER", rsham = "HEALER", rshaman = "HEALER",
	dps = "DAMAGER", dd = "DAMAGER", damage = "DAMAGER",
	ret = "DAMAGER", retri = "DAMAGER", retribution = "DAMAGER",
	enh = "DAMAGER", enha = "DAMAGER", enhance = "DAMAGER", enhancement = "DAMAGER",
	ele = "DAMAGER", elemental = "DAMAGER",
	shadow = "DAMAGER", spriest = "DAMAGER",
	fury = "DAMAGER", arms = "DAMAGER",
	balance = "DAMAGER", boomkin = "DAMAGER", boomie = "DAMAGER", boomy = "DAMAGER", moonkin = "DAMAGER",
	cat = "DAMAGER", kitty = "DAMAGER", feral = "DAMAGER",
}
local BUILD_WORDS = {
	WARRIOR = { arms = "dps", fury = "dps", prot = "tank", protection = "tank" },
	PALADIN = { holy = "holy", hpal = "holy", hpala = "holy", prot = "tank", protection = "tank", ret = "ret", retri = "ret", retribution = "ret" },
	PRIEST = { disc = "heal", discipline = "heal", holy = "heal", hpriest = "heal", shadow = "shadow", spriest = "shadow" },
	SHAMAN = { ele = "ele", elemental = "ele", enh = "enh", enha = "enh", enhancement = "enh", resto = "resto", restoration = "resto", rsham = "resto", rshaman = "resto" },
	DRUID = { balance = "balance", boomkin = "balance", boomie = "balance", boomy = "balance", moonkin = "balance", cat = "cat", kitty = "cat", bear = "bear", resto = "resto", restoration = "resto", rdruid = "resto" },
}

-- Reads role and spec words out of a whisper or comment such as "enh shaman lfg".
-- Returns roles (set or nil) and a build key (or nil) for the given class.
function R.hints(text, class)
	local roles, build
	local sawFeral, sawExplicitDamager = false, false
	for word in tostring(text or ""):lower():gmatch("%a+") do
		local role = ROLE_WORDS[word]
		if role then
			roles = roles or {}
			roles[role] = true
			if word == "feral" then
				sawFeral = true
			elseif role == "DAMAGER" then
				sawExplicitDamager = true
			end
		end
		build = build or (BUILD_WORDS[class] and BUILD_WORDS[class][word])
	end
	if class == "DRUID" and sawFeral and not build then
		if roles and roles.TANK then
			if not sawExplicitDamager then
				build = "bear"
				roles.DAMAGER = nil
			end
		else
			build = "cat"
		end
	end
	return roles, build
end

return R
