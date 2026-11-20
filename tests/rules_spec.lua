local H = ...
local R = H.load("Rules.lua", {}).Rules
local test, eq, ok = H.test, H.eq, H.ok

local function p(name, class, role, extra)
	local profile = { name = name, class = class, level = 60 }
	if role then profile.roles = { [role] = true } end
	for key, value in pairs(extra or {}) do
		profile[key] = value
	end
	return profile
end

-- Expected severity and reason for a pair, or false for no conflict.
local function pair(name, a, b, severity, reason, opts)
	test(name, function()
		for _, order in ipairs({ { a, b }, { b, a } }) do
			local found = R.compare(order[1], order[2], opts)
			if not severity then
				eq(found, nil, "conflict")
			else
				ok(found, "conflict")
				eq(found.severity, severity, "severity")
				eq(found.reason, reason, "reason")
			end
		end
	end)
end

local feralTank = p("Me", "DRUID", "TANK", { tree = 2, isSelf = true })
local feralCat = p("Me", "DRUID", "DAMAGER", { tree = 2, isSelf = true })
local protWarrior = p("Me", "WARRIOR", "TANK", { tree = 3, isSelf = true })

-- The three examples from the brief.
pair("feral druid vs shaman healer: their offspec wears mail, so weapons and jewelry", feralTank, p("Sham", "SHAMAN", "HEALER"), R.MIGHT, "armor")
pair("feral druid vs shaman healer below 40 share leather", p("Me", "DRUID", "TANK", { tree = 2, isSelf = true, level = 30 }), p("Sham", "SHAMAN", "HEALER", { level = 30 }), R.OFFSPEC, "same")
pair("feral druid vs rogue always competes", feralTank, p("Stab", "ROGUE", "DAMAGER"), R.WILL, "same")
pair("prot warrior vs ret paladin: their tank offspec wants the same plate", protWarrior, p("Ret", "PALADIN", "DAMAGER"), R.OFFSPEC, "same")
pair("prot warrior vs rogue is only a maybe", protWarrior, p("Stab", "ROGUE"), R.MIGHT, "unsure")
pair("feral tank vs mage never competes", feralTank, p("Frost", "MAGE", "DAMAGER"), false)
pair("mage vs mage always competes", p("A", "MAGE", "DAMAGER"), p("B", "MAGE", "DAMAGER"), R.WILL, "same")

-- Same lane, same armor.
pair("mage vs warlock", p("A", "MAGE"), p("B", "WARLOCK"), R.WILL, "same")
pair("shadow priest vs mage", p("A", "PRIEST", "DAMAGER"), p("B", "MAGE"), R.WILL, "same")
pair("prot warrior vs prot paladin", protWarrior, p("B", "PALADIN", "TANK"), R.WILL, "same")
pair("hunter vs enhancement shaman", p("A", "HUNTER"), p("B", "SHAMAN", "DAMAGER", { tree = 2 }), R.WILL, "same")
pair("cat vs bear", feralCat, p("B", "DRUID", "TANK"), R.WILL, "same")
pair("resto druid vs resto druid", p("A", "DRUID", "HEALER"), p("B", "DRUID", "HEALER"), R.WILL, "same")

-- Physical and tank gear goes by armor type: different armor leaves weapons, cloaks and jewelry.
pair("rogue vs fury warrior", p("A", "ROGUE"), p("B", "WARRIOR", "DAMAGER"), R.MIGHT, "armor")
pair("hunter vs rogue at 60", p("A", "HUNTER"), p("B", "ROGUE"), R.MIGHT, "armor")
pair("bear vs prot warrior", feralTank, protWarrior, R.MIGHT, "armor")
pair("bear vs fury warrior", feralTank, p("B", "WARRIOR", "DAMAGER"), R.MIGHT, "armor")

-- Spell power gear is mostly cloth and everyone who casts rolls on it.
pair("holy priest vs holy paladin", p("A", "PRIEST", "HEALER"), p("B", "PALADIN", "HEALER"), R.WILL, "cloth")
pair("mage vs elemental shaman", p("A", "MAGE"), p("B", "SHAMAN", "DAMAGER", { build = "ele" }), R.WILL, "cloth")
pair("resto druid vs resto shaman", p("A", "DRUID", "HEALER"), p("B", "SHAMAN", "HEALER"), R.WILL, "cloth")

-- Armor changes at 40.
pair("hunter vs rogue below 40 share leather", p("A", "HUNTER", nil, { level = 32 }), p("B", "ROGUE", nil, { level = 32 }), R.WILL, "same")
pair("warrior vs hunter across 40", p("A", "WARRIOR", "DAMAGER", { level = 38 }), p("B", "HUNTER", nil, { level = 41 }), R.WILL, "same")
pair("warrior 38 vs warrior 42", p("A", "WARRIOR", "DAMAGER", { level = 38 }), p("B", "WARRIOR", "DAMAGER", { level = 42 }), R.MIGHT, "armor")
test("unknown level assumes the heavier armor", function()
	eq(R.armor("PALADIN"), "plate")
	eq(R.armor("SHAMAN", 39), "leather")
	eq(R.armor("SHAMAN", 40), "mail")
	eq(R.armor("PRIEST", 10), "cloth")
end)

-- Ambiguous listings.
pair("shaman listed as damage could be either spec", p("A", "ROGUE"), p("B", "SHAMAN", "DAMAGER"), R.MIGHT, "unsure")
pair("druid with no role vs druid with no role", p("A", "DRUID"), p("B", "DRUID"), R.MIGHT, "unsure")
pair("damage shaman vs resto druid: healing offspec", p("A", "SHAMAN", "DAMAGER"), p("B", "DRUID", "HEALER"), R.OFFSPEC, "cloth")
pair("enhancement shaman vs resto druid: healing offspec", p("A", "SHAMAN", "DAMAGER", { tree = 2 }), p("B", "DRUID", "HEALER"), R.OFFSPEC, "cloth")
pair("a physical offspec in different armor only threatens weapons and jewelry", p("A", "DRUID", "HEALER"), p("B", "WARRIOR", "DAMAGER"), R.MIGHT, "armor")
pair("prot paladin's healing offspec threatens a mage's cloth", p("A", "PALADIN", "TANK"), p("B", "MAGE"), R.OFFSPEC, "cloth")
pair("damage shaman's healing offspec threatens a shadow priest's cloth", p("A", "SHAMAN", "DAMAGER"), p("B", "PRIEST", "DAMAGER"), R.OFFSPEC, "cloth")
pair("a main spec clash outranks an offspec one", p("A", "MAGE"), p("B", "PRIEST", "HEALER"), R.WILL, "same")

-- Spell power serves casters and healers alike.
pair("mage vs holy priest", p("A", "MAGE"), p("B", "PRIEST", "HEALER"), R.WILL, "same")
pair("mage vs resto druid", p("A", "MAGE"), p("B", "DRUID", "HEALER"), R.WILL, "cloth")
pair("warlock vs resto shaman", p("A", "WARLOCK"), p("B", "SHAMAN", "HEALER"), R.WILL, "cloth")
pair("balance druid vs resto druid", p("A", "DRUID", "DAMAGER", { tree = 1 }), p("B", "DRUID", "HEALER"), R.WILL, "same")
pair("mage vs holy priest with offspec guessing off", p("A", "MAGE"), p("B", "PRIEST", "HEALER"), R.WILL, "same", { offspec = false })
pair("shadow priest vs mage is still a certainty", p("A", "PRIEST", "DAMAGER"), p("B", "MAGE"), R.WILL, "same")
pair("holy priest vs prot paladin's healing offspec", p("A", "PRIEST", "HEALER"), p("B", "PALADIN", "TANK"), R.OFFSPEC, "cloth")
test("shared spell power reads plainly", function()
	local found = R.evaluate({ p("Frost", "MAGE") }, { p("Me", "PRIEST", "HEALER", { isSelf = true }) })
	eq(R.describe(found[1]), "Frost will compete with you for cloth spell power gear")
end)
pair("the player's own offspec is never guessed", feralTank, p("B", "PRIEST", "HEALER"), false)
pair("two healers with caster offspecs still share healing", p("A", "PRIEST", "HEALER"), p("B", "SHAMAN", "HEALER"), R.WILL, "cloth")
pair("holy paladin vs mage share spell power", p("A", "PALADIN", "HEALER"), p("B", "MAGE"), R.WILL, "cloth")
pair("prot paladin vs rogue: tanks pick up damage pieces", p("A", "PALADIN", "TANK"), p("B", "ROGUE"), R.MIGHT, "unsure")
pair("holy paladin vs rogue: retribution offspec wears plate", p("A", "PALADIN", "HEALER"), p("B", "ROGUE"), R.MIGHT, "armor")
pair("holy paladin vs fury warrior: retribution offspec", p("A", "PALADIN", "HEALER"), p("B", "WARRIOR", "DAMAGER"), R.OFFSPEC, "same")
pair("prot paladin vs resto shaman: healing offspec", p("A", "PALADIN", "TANK"), p("B", "SHAMAN", "HEALER"), R.OFFSPEC, "cloth")

-- Every rule can be tuned.
local mage, holyPriest, restoDruid = p("A", "MAGE"), p("B", "PRIEST", "HEALER"), p("C", "DRUID", "HEALER")
pair("shared off: mage vs holy priest falls back to the shadow offspec", mage, holyPriest, R.OFFSPEC, "same", { shared = false })
pair("shared off, offspec off: mage vs holy priest is clear", mage, holyPriest, false, nil, { shared = false, offspec = false })
pair("cloth off: mage vs resto druid is weapons and jewelry", mage, restoDruid, R.MIGHT, "armor", { cloth = false })
pair("cloth off: mage vs holy priest still share cloth", mage, holyPriest, R.WILL, "same", { cloth = false })
pair("cloth and accessories off: mage vs resto druid is clear", mage, restoDruid, false, nil, { cloth = false, accessories = false })
pair("accessories off: rogue vs fury warrior is clear", p("A", "ROGUE"), p("B", "WARRIOR", "DAMAGER"), false, nil, { accessories = false })
pair("roll down: fury warrior takes a rogue's leather", p("A", "ROGUE"), p("B", "WARRIOR", "DAMAGER"), R.WILL, "wears", { rollDown = true })
pair("roll down: a shaman healer's offspec takes a druid's leather", feralTank, p("Sham", "SHAMAN", "HEALER"), R.OFFSPEC, "wears", { rollDown = true })
pair("roll down: an offspec in lighter armor cannot take plate", p("A", "DRUID", "HEALER"), p("B", "WARRIOR", "DAMAGER"), R.MIGHT, "armor", { rollDown = true })
pair("unsure off: rogue vs damage shaman is weapons and jewelry at most", p("A", "ROGUE"), p("B", "SHAMAN", "DAMAGER"), false, nil, { unsure = false })
pair("tank damage off: prot warrior vs rogue is clear", protWarrior, p("Stab", "ROGUE"), false, nil, { tankDamage = false })
pair("tank damage on: prot warrior vs fury warrior", protWarrior, p("B", "WARRIOR", "DAMAGER", { build = "dps" }), R.OFFSPEC, "same")
test("roll down counts only when the lighter wearer matters", function()
	local roll = { rollDown = true }
	local rogue, warrior = p("Stab", "ROGUE"), p("War", "WARRIOR", "DAMAGER")
	local _, top = R.evaluate({ warrior }, { p("Me", "ROGUE", nil, { isSelf = true }) }, roll)
	eq(top, R.WILL)
	_, top = R.evaluate({ rogue }, { p("Me", "WARRIOR", "DAMAGER", { isSelf = true }) }, roll)
	eq(top, R.MIGHT)
	_, top = R.evaluate({ p("Stab", "ROGUE", nil, { cared = true }) }, { p("Me", "WARRIOR", "DAMAGER", { isSelf = true }) }, roll)
	eq(top, R.WILL)
	local found = R.evaluate({ warrior }, { p("Me", "ROGUE", nil, { isSelf = true }) }, roll)
	eq(R.describe(found[1]), "War will compete with you for leather physical gear")
end)
test("defaults cover every tunable rule", function()
	eq(R.DEFAULTS, { caredOnly = true, offspec = true, shared = true, cloth = true, rollDown = false, tankDamage = true, unsure = true, accessories = true })
end)

test("several listed roles keep every matching build", function()
	local wants = R.wants({ class = "PALADIN", roles = { TANK = true, HEALER = true } })
	eq(wants, { tank = R.MAYBE, healing = R.MAYBE, physical = R.MAYBE })
end)
test("role beats a contradicting talent tree", function()
	eq(R.wants({ class = "WARRIOR", roles = { DAMAGER = true }, tree = 3 }), { physical = R.MAIN, tank = R.OFF })
end)
test("tree alone picks the build", function()
	eq(R.wants({ class = "SHAMAN", tree = 2 }), { physical = R.MAIN, spell = R.OFF, healing = R.OFF })
	eq(R.wants({ class = "DRUID", tree = 2 }), { physical = R.MAIN, tank = R.MAYBE, spell = R.OFF, healing = R.OFF })
end)
test("manual build beats role and tree", function()
	eq(R.wants({ class = "DRUID", build = "balance", roles = { TANK = true }, tree = 2 }), { spell = R.MAIN, physical = R.OFF, tank = R.OFF, healing = R.OFF })
end)
test("unknown build key is ignored", function()
	eq(R.wants({ class = "MAGE", build = "nope" }), { spell = R.MAIN })
end)
test("unknown class wants nothing", function()
	eq(R.wants({ class = "MONK" }), {})
	eq(R.compare({ class = "MONK" }, feralTank), nil)
end)

-- Offspec guessing can be turned off.
pair("offspec off: feral vs shaman healer", feralTank, p("Sham", "SHAMAN", "HEALER"), false, nil, { offspec = false })
pair("offspec off: feral vs rogue still competes", feralTank, p("Stab", "ROGUE"), R.WILL, "same", { offspec = false })
pair("offspec off: unsure specs still count", p("A", "ROGUE"), p("B", "SHAMAN", "DAMAGER"), R.MIGHT, "unsure", { offspec = false })

-- Who we care about.
local function names(found)
	local out = {}
	for i, conflict in ipairs(found) do
		out[i] = conflict.candidate.name .. ">" .. conflict.member.name
	end
	return out
end

test("stranger mage in party: inviting another stranger mage is silent", function()
	local found, top = R.evaluate({ p("New", "MAGE") }, { feralTank, p("Pug", "MAGE") })
	eq(found, {})
	eq(top, nil)
end)
test("friend mage in party: inviting a mage warns", function()
	local found, top = R.evaluate({ p("New", "MAGE") }, { feralTank, p("Pal", "MAGE", nil, { cared = true }) })
	eq(names(found), { "New>Pal" })
	eq(top, R.WILL)
end)
test("inviting a friend warns about strangers they compete with", function()
	local found = R.evaluate({ p("Pal", "MAGE", nil, { cared = true }) }, { feralTank, p("Pug", "MAGE") })
	eq(names(found), { "Pal>Pug" })
end)
test("caring about everyone warns about strangers", function()
	local found = R.evaluate({ p("New", "MAGE") }, { feralTank, p("Pug", "MAGE") }, { caredOnly = false })
	eq(names(found), { "New>Pug" })
end)
test("a stranger's offspec threatens a friend's main spec, not the reverse", function()
	local friendTank = p("Pal", "DRUID", "TANK", { cared = true })
	eq(names((R.evaluate({ p("Sham", "SHAMAN", "HEALER") }, { friendTank }))), { "Sham>Pal" })
	eq(names((R.evaluate({ p("New", "ROGUE") }, { p("Pal", "PALADIN", "HEALER", { cared = true }) }))), {})
end)
test("a friend's own offspec does not hide what a stranger takes from them", function()
	-- Pal's healing offspec against Sham would rank higher, but Sham is a stranger.
	local found = R.evaluate({ p("Sham", "SHAMAN", "HEALER", { level = 30 }) }, { p("Pal", "DRUID", "TANK", { cared = true, level = 30 }) })
	eq({ found[1].severity, found[1].lane, found[1].offspec.name }, { R.OFFSPEC, "physical", "Sham" })
end)
test("cloth spell power is contested both ways", function()
	local _, top = R.evaluate({ p("Tree", "DRUID", "HEALER") }, { p("Me", "MAGE", nil, { isSelf = true }) })
	eq(top, R.WILL)
	_, top = R.evaluate({ p("Frost", "MAGE") }, { p("Me", "DRUID", "HEALER", { isSelf = true, tree = 3 }) })
	eq(top, R.WILL)
end)
test("main spec, offspec and possible conflicts sort in that order", function()
	local found, top = R.evaluate({ p("Stab", "ROGUE"), p("Ret", "PALADIN", "DAMAGER"), p("Tank", "PALADIN", "TANK") }, { protWarrior })
	eq(names(found), { "Tank>Me", "Ret>Me", "Stab>Me" })
	eq({ found[1].severity, found[2].severity, found[3].severity }, { R.WILL, R.OFFSPEC, R.MIGHT })
	eq(top, R.WILL)
end)
test("conflicts with the player always count and sort by severity", function()
	local found, top = R.evaluate({ p("Stab", "ROGUE") }, { p("Pal", "PALADIN", "DAMAGER", { cared = true }), feralCat })
	eq(names(found), { "Stab>Me", "Stab>Pal" })
	eq(top, R.WILL)
end)
test("a listed group is checked member by member", function()
	local found = R.evaluate({ p("Lead", "WARRIOR", "TANK"), p("Stab", "ROGUE"), p("Heal", "PRIEST", "HEALER") }, { feralCat })
	eq(names(found), { "Stab>Me", "Lead>Me" })
end)

test("descriptions read as plain sentences", function()
	local function say(candidate, member, opts)
		return R.describe(R.evaluate({ candidate }, { member }, opts)[1])
	end
	eq(say(p("Stab", "ROGUE"), feralTank), "Stab will compete with you for leather physical gear")
	eq(say(p("Sham", "SHAMAN", "HEALER"), feralTank), "Sham might compete with you for physical gear (weapons, cloaks, jewelry)")
	eq(say(p("Tree", "DRUID", "HEALER"), feralTank), "Tree will compete with you for leather physical gear (their offspec)")
	eq(say(p("Ret", "PALADIN", "DAMAGER"), protWarrior), "Ret will compete with you for plate tank gear (their offspec)")
	eq(say(p("Stab", "ROGUE"), protWarrior), "Stab might compete with you for physical gear, depending on spec")
	eq(say(p("New", "MAGE"), p("Pal", "PALADIN", "TANK"), { caredOnly = false }), "New will compete with Pal for cloth spell power gear (Pal's offspec)")
	eq(say(p("Tree", "DRUID", "HEALER"), p("Me", "WARRIOR", "DAMAGER", { isSelf = true })), "Tree might compete with you for physical gear (weapons, cloaks, jewelry)")
	eq(say(p("Hunt", "HUNTER"), feralCat), "Hunt might compete with you for physical gear (weapons, cloaks, jewelry)")
	eq(say(p("Frost", "MAGE"), p("Me", "SHAMAN", "DAMAGER", { isSelf = true, build = "ele" })), "Frost will compete with you for cloth spell gear")
	eq(say(p("Sham", "SHAMAN", "DAMAGER"), feralCat), "Sham might compete with you for physical gear, depending on spec")
end)

test("whisper hints", function()
	local roles, build = R.hints("Enh shaman LFG, can heal too", "SHAMAN")
	eq(roles, { DAMAGER = true, HEALER = true })
	eq(build, "enh")
	roles, build = R.hints("feral tank here", "DRUID")
	eq(roles, { TANK = true })
	eq(build, nil)
	roles, build = R.hints("boomkin inv pls", "DRUID")
	eq(roles, { DAMAGER = true })
	eq(build, "balance")
	roles, build = R.hints("inv", "MAGE")
	eq(roles, nil)
	eq(build, nil)
	eq((R.hints("stank you", "ROGUE")), nil)
end)
