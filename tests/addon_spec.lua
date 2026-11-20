-- Drives Core.lua end to end against the fake game API.
local H = ...
local test, eq, ok = H.test, H.eq, H.ok
local stub = dofile(H.root .. "/tests/wow_stub.lua")

-- Dot texture and tint, as the row shows them.
local RED, ORANGE, YELLOW = "Interface\\COMMON\\Indicator-Red 1,1,1", "Interface\\COMMON\\Indicator-Yellow 1,0.5,0.2", "Interface\\COMMON\\Indicator-Yellow 1,1,1"

-- Starts the addon in a fresh world. setup(world) runs before login.
local function boot(setup)
	local world = stub()
	world.loadGroupFinder()
	if setup then setup(world) end
	local ns = {}
	H.load("Rules.lua", ns)
	H.load("Core.lua", ns)
	H.load("Options.lua", ns)
	world.D, world.frame = ns.MittsOff, ns.MittsOff.frame
	world.frame:Fire("ADDON_LOADED", "MittsOff")
	world.frame:Fire("PLAYER_LOGIN")
	return world
end

-- The settings panel's preview row for a spec: its dot, name and detail text.
local function previewRow(world, label)
	for _, row in ipairs(world.D.rows) do
		if row.name.text == label then return { row.dot.path .. " " .. row.dot.tint, row.detail.text } end
	end
end

local function feral(world) world.player.points = { 0, 30, 21 } end

local function solo(name, class, roles, extra)
	local result = { members = { { name = name, class = class, roles = roles } } }
	for key, value in pairs(extra or {}) do
		result[key] = value
	end
	return result
end

-- What the browse row for a listing shows: RED, YELLOW or nil.
local function icon(world, resultID)
	local entry = world.newFrame()
	entry.resultID = resultID
	LFGBrowseSearchEntry_Update(entry)
	return entry.MittsOffIcon and entry.MittsOffIcon.shown and (entry.MittsOffIcon.path .. " " .. entry.MittsOffIcon.tint) or nil
end

local function tooltip(world, resultID)
	LFGBrowseSearchEntryTooltip_UpdateAndShow(LFGBrowseSearchEntryTooltip, resultID)
	return world.tooltip.shown and world.tooltip.lines or {}
end

local function whisper(world, text, sender, class)
	world.guids["guid-" .. sender] = class
	world.frame:Fire("CHAT_MSG_WHISPER", text, sender, "", "", "", "", 0, 0, "", 0, 0, "guid-" .. sender)
end

test("talent points pick the tree by pane order, not by group ID", function()
	local world = boot(feral)
	eq({ world.D.myTree() }, { 2, "Second", 30 })
	world.player.points = { 31, 0, 20 }
	eq((world.D.myTree()), 1)
	world.player.points = { 10, 10, 0 }
	eq((world.D.myTree()), nil)
end)

test("a feral druid whose tree has the highest group ID is still feral", function()
	local world = boot(feral)
	world.treeGroups = { 9001, 9003, 9002 }
	world.results[1] = solo("Stab", "ROGUE", { dps = true })
	world.results[2] = solo("Tree", "DRUID", { healer = true })
	eq(icon(world, 1), RED)
	SlashCmdList.MITTSOFF("status")
	eq({ world.chat[1], world.chat[2] }, { "Mitts Off! You are gearing as Feral (cat) or Feral (bear).", "Mitts Off! Most talent points: Second (30), tree 2." })
end)

test("browse rows: rogue red, resto druid orange, unclear warrior yellow, mage clear for a feral druid", function()
	local world = boot(feral)
	world.results[1] = solo("Stab", "ROGUE", { dps = true })
	world.results[2] = solo("Tree", "DRUID", { healer = true })
	world.results[3] = solo("Frost", "MAGE", { dps = true })
	world.results[4] = solo("Prot", "WARRIOR", { tank = true })
	eq(icon(world, 1), RED)
	eq(icon(world, 2), ORANGE)
	eq(icon(world, 3), nil)
	world.player.role = "DAMAGER"
	eq(icon(world, 4), YELLOW)
end)

test("a reused row clears its icon", function()
	local world = boot(feral)
	world.results[1] = solo("Stab", "ROGUE", { dps = true })
	world.results[2] = solo("Frost", "MAGE", { dps = true })
	local entry = world.newFrame()
	entry.resultID = 1
	LFGBrowseSearchEntry_Update(entry)
	ok(entry.MittsOffIcon.shown, "icon shown")
	entry.resultID = 2
	LFGBrowseSearchEntry_Update(entry)
	eq(entry.MittsOffIcon.shown, false)
end)

test("tooltip explains the conflict and hides when there is none", function()
	local world = boot(feral)
	world.results[1] = solo("Stab", "ROGUE", { dps = true })
	world.results[2] = solo("Frost", "MAGE", { dps = true })
	eq(tooltip(world, 1), { "Stab will compete with you for leather physical gear" })
	eq(tooltip(world, 2), {})
	eq(world.tooltip.shown, false)
end)

test("prot warrior sees a ret paladin orange and a rogue yellow", function()
	local world = boot(function(w)
		w.player.class, w.player.points, w.player.role = "WARRIOR", { 5, 5, 41 }, "TANK"
	end)
	world.results[1] = solo("Ret", "PALADIN", { dps = true })
	world.results[2] = solo("Stab", "ROGUE", { dps = true })
	eq(icon(world, 1), ORANGE)
	eq(tooltip(world, 1), { "Ret will compete with you for plate tank gear (their offspec)" })
	eq(icon(world, 2), YELLOW)
	eq(tooltip(world, 2), { "Stab might compete with you for physical gear, depending on spec" })
end)

test("stranger mage in party: another mage is not flagged", function()
	local world = boot(function(w)
		feral(w)
		w.party = { { name = "Pug", class = "MAGE", level = 60 } }
	end)
	world.results[1] = solo("New", "MAGE", { dps = true })
	eq(icon(world, 1), nil)
end)

test("friend mage in party: another mage is flagged", function()
	local world = boot(function(w)
		feral(w)
		w.party = { { name = "Pal", class = "MAGE", level = 60 } }
		w.friends = { "Pal" }
	end)
	world.results[1] = solo("New", "MAGE", { dps = true })
	eq(icon(world, 1), RED)
	eq(tooltip(world, 1), { "New will compete with Pal for cloth spell gear" })
end)

test("guildmate in party counts, with or without the realm suffix", function()
	local world = boot(function(w)
		feral(w)
		w.party = { { name = "Pal", class = "MAGE", level = 60 } }
		w.guild = { "Pal-Stormrage" }
	end)
	world.results[1] = solo("New", "MAGE", { dps = true })
	eq(icon(world, 1), RED)
end)

test("a guildmate listing is flagged against a stranger in the party", function()
	local world = boot(function(w)
		feral(w)
		w.party = { { name = "Pug", class = "MAGE", level = 60 } }
		w.guild = { "Pal-Stormrage" }
	end)
	world.results[1] = solo("Pal", "MAGE", { dps = true })
	eq(tooltip(world, 1), { "Pal will compete with Pug for cloth spell gear" })
end)

test("battle.net friend on another realm is matched by name and realm", function()
	local world = boot(function(w)
		feral(w)
		w.party = { { name = "Pal", realm = "Area 52", class = "MAGE", level = 60 }, { name = "Pal", class = "WARLOCK", level = 60 } }
		w.bnet = { { characterName = "Pal", realmName = "Area52" } }
	end)
	world.results[1] = solo("New", "PRIEST", { dps = true })
	eq(tooltip(world, 1), { "New will compete with Pal for cloth spell gear" })
end)

test("friend list changes are picked up", function()
	local world = boot(function(w)
		feral(w)
		w.party = { { name = "Pug", class = "MAGE", level = 60 } }
	end)
	world.results[1] = solo("New", "MAGE", { dps = true })
	eq(icon(world, 1), nil)
	world.friends = { "Pug" }
	world.frame:Fire("FRIENDLIST_UPDATE")
	eq(icon(world, 1), RED)
end)

test("/mittsoff strangers warns about everyone", function()
	local world = boot(function(w)
		feral(w)
		w.party = { { name = "Pug", class = "MAGE", level = 60 } }
	end)
	world.results[1] = solo("New", "MAGE", { dps = true })
	SlashCmdList.MITTSOFF("strangers")
	eq(icon(world, 1), RED)
	SlashCmdList.MITTSOFF("strangers")
	eq(icon(world, 1), nil)
end)

test("/mittsoff offspec silences the resto druid", function()
	local world = boot(feral)
	world.results[1] = solo("Tree", "DRUID", { healer = true })
	eq(icon(world, 1), ORANGE)
	SlashCmdList.MITTSOFF("offspec")
	eq(icon(world, 1), nil)
end)

test("a listed group is checked member by member with party roles", function()
	local world = boot(feral)
	world.results[1] = { members = {
		{ name = "Lead", class = "WARRIOR", role = "TANK" },
		{ name = "Stab", class = "ROGUE", role = "DAMAGER" },
		{ name = "Heal", class = "PRIEST", role = "HEALER" },
	} }
	eq(tooltip(world, 1), {
		"Stab will compete with you for leather physical gear",
		"Lead might compete with you for physical gear, depending on spec",
	})
end)

test("own listing, delisted listings and current party members are ignored", function()
	local world = boot(function(w)
		feral(w)
		w.party = { { name = "Stab", class = "ROGUE", level = 60 } }
	end)
	world.results[1] = solo("Me", "DRUID", { tank = true }, { hasSelf = true })
	world.results[2] = solo("Gone", "ROGUE", { dps = true }, { isDelisted = true })
	world.results[3] = solo("Stab", "ROGUE", { dps = true })
	eq(icon(world, 1), nil)
	eq(icon(world, 2), nil)
	eq(icon(world, 3), nil)
	eq(icon(world, 99), nil)
end)

test("a solo listing's comment can name the spec", function()
	local world = boot(feral)
	world.results[1] = solo("Moon", "DRUID", { dps = true }, { comment = "boomkin lf ZF" })
	world.results[2] = solo("Claw", "DRUID", { dps = true }, { comment = "cat dps lf ZF" })
	world.results[3] = solo("Dru", "DRUID", { dps = true })
	eq(tooltip(world, 1), { "Moon will compete with you for leather physical gear (their offspec)" })
	eq(tooltip(world, 2), { "Claw will compete with you for leather physical gear" })
	eq(tooltip(world, 3), { "Dru might compete with you for physical gear, depending on spec" })
end)

test("level decides armor", function()
	local world = boot(function(w)
		feral(w)
		w.player.level = 35
	end)
	world.results[1] = { members = { { name = "Hunt", class = "HUNTER", roles = { dps = true }, level = 36 } } }
	eq(tooltip(world, 1), { "Hunt will compete with you for leather physical gear" })
end)

test("talents outrank a wrong party role", function()
	local world = boot(function(w)
		w.player.points, w.player.role = { 0, 11, 40 }, "DAMAGER"
	end)
	world.results[1] = solo("Tree", "DRUID", { healer = true })
	world.results[2] = solo("Stab", "ROGUE", { dps = true })
	eq(icon(world, 1), RED)
	eq(icon(world, 2), nil)
end)

test("party role splits bear from cat", function()
	local world = boot(function(w)
		feral(w)
		w.player.role = "DAMAGER"
	end)
	world.results[1] = solo("Prot", "WARRIOR", { tank = true })
	eq(tooltip(world, 1), { "Prot might compete with you for physical gear, depending on spec" })
	world.player.role = "TANK"
	eq(tooltip(world, 1), { "Prot might compete with you for tank gear (weapons, cloaks, jewelry)" })
end)

test("whispers warn only while listed", function()
	local world = boot(feral)
	whisper(world, "inv pls", "Stab-Stormrage", "ROGUE")
	eq(world.chat, {})
	world.listed = true
	whisper(world, "inv pls", "Stab-Stormrage", "ROGUE")
	eq(world.chat, { "Mitts Off! Stab will compete with you for leather physical gear" })
end)

test("whispers stay quiet for a while per sender, and for no conflict", function()
	local world = boot(function(w)
		feral(w)
		w.listed = true
	end)
	whisper(world, "inv", "Stab", "ROGUE")
	whisper(world, "hello?", "Stab", "ROGUE")
	whisper(world, "mage lfg", "Frost", "MAGE")
	eq(#world.chat, 1)
	world.now = world.now + 121
	whisper(world, "still there?", "Stab", "ROGUE")
	eq(#world.chat, 2)
end)

test("whisper text narrows the spec", function()
	local world = boot(function(w)
		feral(w)
		w.listed = true
	end)
	whisper(world, "resto druid lf group", "Tree", "DRUID")
	whisper(world, "Cat dps here", "Claw", "DRUID")
	whisper(world, "enh shaman lfg", "Totem", "SHAMAN")
	eq(world.chat, {
		"Mitts Off! Tree will compete with you for leather physical gear (their offspec)",
		"Mitts Off! Claw will compete with you for leather physical gear",
		"Mitts Off! Totem might compete with you for physical gear (weapons, cloaks, jewelry)",
	})
end)

test("a holy priest and a resto druid both see mages red", function()
	local world = boot(function(w)
		w.player.class, w.player.points, w.player.role = "PRIEST", { 20, 31, 0 }, "HEALER"
	end)
	world.results[1] = solo("Frost", "MAGE", { dps = true })
	eq(tooltip(world, 1), { "Frost will compete with you for cloth spell power gear" })
	world.player.class, world.player.points = "DRUID", { 0, 11, 40 }
	eq(tooltip(world, 1), { "Frost will compete with you for cloth spell power gear" })
end)

test("/mittsoff whispers turns whisper checks off", function()
	local world = boot(function(w)
		feral(w)
		w.listed = true
	end)
	SlashCmdList.MITTSOFF("whispers")
	world.chat = {}
	whisper(world, "inv", "Stab", "ROGUE")
	eq(world.chat, {})
end)

test("inviting someone seen in the finder repeats the warning and still invites", function()
	local world = boot(feral)
	world.results[1] = solo("Stab", "ROGUE", { dps = true })
	icon(world, 1)
	C_PartyInfo.InviteUnit("Stab")
	C_PartyInfo.InviteUnit("Nobody")
	eq(world.invited, { "Stab", "Nobody" })
	eq(world.chat, { "Mitts Off! Stab will compete with you for leather physical gear" })
end)

test("/mittsoff spec overrides detection and auto restores it", function()
	local world = boot(feral)
	world.results[1] = solo("Stab", "ROGUE", { dps = true })
	SlashCmdList.MITTSOFF("spec balance")
	eq(MittsOffCharDB.build, "balance")
	eq(icon(world, 1), nil)
	SlashCmdList.MITTSOFF("spec nonsense")
	eq(MittsOffCharDB.build, "balance")
	SlashCmdList.MITTSOFF("spec auto")
	eq(MittsOffCharDB.build, nil)
	eq(icon(world, 1), RED)
end)

test("/mittsoff check answers for a hypothetical invite", function()
	local world = boot(feral)
	SlashCmdList.MITTSOFF("check rogue")
	SlashCmdList.MITTSOFF("check mage dps")
	eq(world.chat, { "Mitts Off! They will compete with you for leather physical gear", "Mitts Off! No competition." })
end)

test("/mittsoff status shows the detected spec", function()
	local world = boot(feral)
	SlashCmdList.MITTSOFF("status")
	eq(world.chat[1], "Mitts Off! You are gearing as Feral (cat) or Feral (bear).")
end)

test("/mittsoff opens the settings panel, or falls back to chat without one", function()
	local world = boot(feral)
	SlashCmdList.MITTSOFF("")
	eq(world.opened, "Mitts Off!")
	eq(world.chat, {})
	eq(#world.D.rows, 18)
	Settings.OpenToCategory = nil
	SlashCmdList.MITTSOFF("")
	eq(world.chat[1], "Mitts Off! You are gearing as Feral (cat) or Feral (bear).")
end)

test("settings panel shows saved values and a preview for a feral druid", function()
	local world = boot(feral)
	SlashCmdList.MITTSOFF("")
	for _, section in ipairs(world.D.SECTIONS) do
		for _, item in ipairs(section.items) do
			eq(world.D.checks[item[1]].checked, world.D.DEFAULTS[item[1]], item[1])
		end
	end
	eq(previewRow(world, "Rogue"), { RED, "leather physical" })
	eq(previewRow(world, "Restoration Druid"), { ORANGE, "leather physical, offspec" })
	eq(previewRow(world, "Arms or Fury Warrior"), { YELLOW, "weapons, cloaks, jewelry" })
	eq(previewRow(world, "MAGE"), { "Interface\\COMMON\\Indicator-Gray 1,1,1", "" })
end)

test("every setting has a checkbox and every checkbox a setting", function()
	local world = boot(feral)
	SlashCmdList.MITTSOFF("")
	local listed = {}
	for _, section in ipairs(world.D.SECTIONS) do
		for _, item in ipairs(section.items) do
			listed[item[1]] = true
			ok(world.D.DEFAULTS[item[1]] ~= nil, item[1] .. " has a default")
		end
	end
	for name in pairs(world.D.DEFAULTS) do
		ok(listed[name], name .. " is in the panel")
	end
end)

test("ticking a rule saves it and recolors the preview", function()
	local world = boot(feral)
	SlashCmdList.MITTSOFF("")
	local function click(key, checked)
		local check = world.D.checks[key]
		check.checked = checked
		check.scripts.OnClick(check)
	end
	click("rollDown", true)
	eq(MittsOffDB.rollDown, true)
	eq(previewRow(world, "Arms or Fury Warrior"), { RED, "leather physical" })
	click("offspec", false)
	eq(previewRow(world, "Restoration Druid"), { "Interface\\COMMON\\Indicator-Gray 1,1,1", "" })
	click("rollDown", false)
	click("accessories", false)
	eq(previewRow(world, "Arms or Fury Warrior"), { "Interface\\COMMON\\Indicator-Gray 1,1,1", "" })
end)

test("the spec dropdown overrides detection and Defaults restores everything", function()
	local world = boot(feral)
	SlashCmdList.MITTSOFF("")
	local menu = world.D.specDropdown.menu
	local labels = {}
	for i, radio in ipairs(menu) do
		labels[i] = radio.text
	end
	eq(labels, { "Automatic: Feral (cat) or Feral (bear)", "Balance", "Feral (cat)", "Feral (bear)", "Restoration" })
	eq(menu[1].isSelected(), true)
	world.D.set("whispers", false)
	menu[2].select()
	eq(MittsOffCharDB.build, "balance")
	eq(world.D.specDropdown.menu[2].isSelected(), true)
	eq(previewRow(world, "Rogue"), { "Interface\\COMMON\\Indicator-Gray 1,1,1", "" })
	eq(previewRow(world, "MAGE"), { RED, "cloth spell" })
	world.D.reset()
	world.D.refreshSettings()
	eq(MittsOffDB.whispers, true)
	eq(MittsOffCharDB.build, nil)
	eq(previewRow(world, "Rogue"), { RED, "leather physical" })
end)

test("the settings panel shows the leading talent tree", function()
	local world = boot(feral)
	SlashCmdList.MITTSOFF("")
	eq(world.D.talentsText.text, "Most talent points: Second (30), tree 2.")
	world.player.points = { 10, 10, 0 }
	world.D.refreshSettings()
	eq(world.D.talentsText.text, "No single talent tree leads, so your party role decides.")
end)

-- The check page's lines, without colour codes, up to the first empty one.
local function checkLines(world)
	local out = {}
	for _, line in ipairs(world.D.checkLines) do
		if line.text == "" then break end
		out[#out + 1] = (line.text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
	end
	return out
end

local function pick(menu, label)
	for _, radio in ipairs(menu.menu) do
		if radio.text == label then return radio.select() end
	end
	error("no option " .. label)
end

test("the check page answers like /mittsoff check", function()
	local world = boot(feral)
	SlashCmdList.MITTSOFF("check")
	eq(world.opened, "Check a player")
	eq(world.category.name, "Mitts Off!")
	eq(world.categories["Check a player"].parent, world.category)
	pick(world.D.checkClassMenu, "Rogue")
	eq(checkLines(world), { "They will compete with you for leather physical gear" })
	pick(world.D.checkClassMenu, "MAGE")
	pick(world.D.checkRoleMenu, "Damage")
	eq(checkLines(world), { "No competition." })
	eq(world.D.checkRoleMenu.menu[4].isSelected(), true)
	eq(world.chat, {})
	world.chat = {}
	SlashCmdList.MITTSOFF("check rogue")
	eq(world.chat, { "Mitts Off! They will compete with you for leather physical gear" })
end)

test("finder and invite warnings can be switched off", function()
	local world = boot(feral)
	world.results[1] = solo("Stab", "ROGUE", { dps = true })
	eq(icon(world, 1), RED)
	world.D.set("invites", false)
	C_PartyInfo.InviteUnit("Stab")
	eq(world.chat, {})
	world.D.set("finder", false)
	eq(icon(world, 1), nil)
	eq(tooltip(world, 1), {})
end)

test("saved settings survive a reload and new defaults fill in", function()
	local world = stub()
	world.loadGroupFinder()
	local ns = {}
	H.load("Rules.lua", ns)
	H.load("Core.lua", ns)
	MittsOffDB = { caredOnly = false }
	ns.MittsOff.frame:Fire("ADDON_LOADED", "MittsOff")
	local expected = {}
	for name, value in pairs(ns.MittsOff.DEFAULTS) do
		expected[name] = value
	end
	expected.caredOnly = false
	eq(MittsOffDB, expected)
	eq(MittsOffDB.rollDown, false)
end)

test("group finder hooks wait for the load on demand addon", function()
	local world = stub()
	local ns = {}
	H.load("Rules.lua", ns)
	H.load("Core.lua", ns)
	world.player.points = { 0, 30, 21 }
	ns.MittsOff.frame:Fire("ADDON_LOADED", "MittsOff")
	ns.MittsOff.frame:Fire("PLAYER_LOGIN")
	world.loadGroupFinder()
	ns.MittsOff.frame:Fire("ADDON_LOADED", "Blizzard_GroupFinder_VanillaStyle")
	ns.MittsOff.frame:Fire("ADDON_LOADED", "SomethingElse")
	world.results[1] = solo("Stab", "ROGUE", { dps = true })
	eq(icon(world, 1), RED)
end)

test("secret values are treated as unknown", function()
	local world = boot(feral)
	local secret = {}
	issecretvalue = function(value) return value == secret end
	eq(world.D.key(secret), nil)
	local real = C_LFGList.GetSearchResultPlayerInfo
	C_LFGList.GetSearchResultPlayerInfo = function(...)
		local info = real(...)
		info.name = secret
		return info
	end
	world.results[1] = solo("Stab", "ROGUE", { dps = true })
	eq(icon(world, 1), nil)
end)
