-- Drives Core.lua and Options.lua end to end against the fake game API.
local H = ...
local test, eq, ok = H.test, H.eq, H.ok
local stub = dofile(H.root .. "/tests/wow_stub.lua")

-- Badge label and fill color, as the row or preview shows them.
local RED = "MS 0.6,0.1,0.1,0.92"
local ORANGE = "OS 0.66,0.28,0.04,0.92"
local YELLOW = "? 0.52,0.42,0.05,0.92"
local CLEAR = " 0.2,0.2,0.2,0.92"

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

-- The settings panel's preview row for a spec: its badge and detail text.
local function previewRow(world, label)
	for _, row in ipairs(world.D.rows) do
		if row.name.text == label then
			return { row.badge.label.text .. " " .. row.badge.bg.color, row.detail.text }, row
		end
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

local function badgeOf(entry)
	local b = entry.MittsOffBadge
	return b and b.shown and (b.label.text .. " " .. b.bg.color) or nil
end

local function makeEntry(world, resultID)
	local entry = world.newFrame()
	entry.resultID = resultID
	LFGBrowseSearchEntry_Update(entry)
	return entry
end

-- What the browse row for a listing shows: RED, ORANGE, YELLOW or nil.
local function icon(world, resultID)
	return badgeOf(makeEntry(world, resultID))
end

local function tooltip(world, resultID)
	LFGBrowseSearchEntryTooltip_UpdateAndShow(LFGBrowseSearchEntryTooltip, resultID)
	local tip = world.D.tooltip
	return tip and tip.shown and tip.lines or {}
end

local function tooltipPairs(world, resultID)
	LFGBrowseSearchEntryTooltip_UpdateAndShow(LFGBrowseSearchEntryTooltip, resultID)
	local tip = world.D.tooltip
	return tip and tip.shown and tip.doubleLines or {}
end

local function whisper(world, text, sender, class)
	world.guids["guid-" .. sender] = class
	world.frame:Fire("CHAT_MSG_WHISPER", text, sender, "", "", "", "", 0, 0, "", 0, 0, "guid-" .. sender)
end

local function findMenuItem(menu, text)
	for _, item in ipairs(menu or {}) do
		if item.text == text then return item end
	end
	error("no menu option: " .. tostring(text))
end

test("talent points pick the tree by pane order, not by group ID", function()
	local world = boot(feral)
	eq({ world.D.myTree() }, { 2, "Second", 30 })
	world.player.points = { 31, 0, 20 }
	eq((world.D.myTree()), 1)
	world.player.points = { 10, 10, 0 }
	eq((world.D.myTree()), nil)
end)

test("C_Traits.GetConfigInfo supplies the tree ID when available", function()
	local seenTreeID
	local world = boot(function(w)
		feral(w)
		C_Traits.GetConfigInfo = function() return { treeIDs = { 4242 } } end
		local realDisplay = C_Traits.GetGroupDisplayInfoByTreeID
		C_Traits.GetGroupDisplayInfoByTreeID = function(treeID)
			seenTreeID = treeID
			return realDisplay(treeID)
		end
	end)
	eq((world.D.myTree()), 2)
	eq(seenTreeID, 4242)
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

test("browse rows: rogue MS, resto druid OS, unclear warrior ?, mage clear for a feral druid", function()
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

test("a reused row clears its badge", function()
	local world = boot(feral)
	world.results[1] = solo("Stab", "ROGUE", { dps = true })
	world.results[2] = solo("Frost", "MAGE", { dps = true })
	local entry = makeEntry(world, 1)
	ok(entry.MittsOffBadge.shown, "badge shown")
	entry.resultID = 2
	LFGBrowseSearchEntry_Update(entry)
	eq(entry.MittsOffBadge.shown, false)
end)

test("dedicated tooltip shows header, double-line reasoning, and hides when clear", function()
	local world = boot(feral)
	world.results[1] = solo("Stab", "ROGUE", { dps = true })
	world.results[2] = solo("Frost", "MAGE", { dps = true })
	eq(tooltip(world, 1), { "Mitts Off!", "[MS] Stab vs you  leather physical" })
	eq(tooltipPairs(world, 1), { { "[MS] Stab vs you", "leather physical" } })
	eq(tooltip(world, 2), {})
	eq(world.D.tooltip.shown, false)
	eq(world.tooltip.shown, false)
end)

test("tooltip truncates past 6 conflicts and flips above near screen bottom", function()
	local world = boot(function(w)
		feral(w)
		w.party = {
			{ name = "A", class = "MAGE", level = 60 },
			{ name = "B", class = "PRIEST", level = 60 },
			{ name = "C", class = "WARLOCK", level = 60 },
			{ name = "D", class = "DRUID", level = 60 },
		}
		w.friends = { "A", "B", "C", "D" }
	end)
	world.results[1] = { members = {
		{ name = "X1", class = "MAGE", role = "DAMAGER" },
		{ name = "X2", class = "PRIEST", role = "HEALER" },
	} }
	local lines = tooltip(world, 1)
	eq(#lines, 8)
	eq(lines[1], "Mitts Off!")
	eq(lines[8], "+2 more")

	-- Near bottom of screen: flips above LFGBrowseSearchEntryTooltip after OnEnter anchors it.
	local entry = makeEntry(world, 1)
	local origOnEnter = LFGBrowseSearchEntry_OnEnter
	LFGBrowseSearchEntryTooltip.bottom = 10
	LFGBrowseSearchEntry_OnEnter(entry)
	eq(world.D.tooltip.points[1].point, "BOTTOMLEFT")
	LFGBrowseSearchEntryTooltip.bottom = 400
	LFGBrowseSearchEntry_OnEnter(entry)
	eq(world.D.tooltip.points[1].point, "TOPLEFT")
	LFGBrowseSearchEntryTooltip:Hide()
	eq(world.D.tooltip.shown, false)
	ok(origOnEnter ~= nil)
end)

test("prot warrior sees a ret paladin OS and a rogue as tank damage", function()
	local world = boot(function(w)
		w.player.class, w.player.points, w.player.role = "WARRIOR", { 5, 5, 41 }, "TANK"
	end)
	world.results[1] = solo("Ret", "PALADIN", { dps = true })
	world.results[2] = solo("Stab", "ROGUE", { dps = true })
	eq(icon(world, 1), ORANGE)
	eq(tooltipPairs(world, 1), { { "[OS] Ret vs you", "plate tank (their offspec)" } })
	eq(icon(world, 2), YELLOW)
	eq(tooltipPairs(world, 2), { { "[?] Stab vs you", "physical (tank damage)" } })
end)

test("visible group finder rows refresh live on settings, spec and roster changes", function()
	local world = boot(function(w)
		feral(w)
		w.party = { { name = "Pug", class = "MAGE", level = 60 } }
	end)
	world.results[1] = solo("New", "MAGE", { dps = true })
	world.results[2] = solo("Stab", "ROGUE", { dps = true })
	local mageRow = makeEntry(world, 1)
	local rogueRow = makeEntry(world, 2)
	eq(badgeOf(mageRow), nil)
	eq(badgeOf(rogueRow), RED)

	world.D.set("caredOnly", false)
	eq(badgeOf(mageRow), RED)
	world.D.set("caredOnly", true)
	eq(badgeOf(mageRow), nil)

	world.friends = { "Pug" }
	world.frame:Fire("FRIENDLIST_UPDATE")
	eq(badgeOf(mageRow), RED)

	SlashCmdList.MITTSOFF("spec balance")
	eq(badgeOf(rogueRow), nil)
	SlashCmdList.MITTSOFF("spec auto")
	eq(badgeOf(rogueRow), RED)

	world.party = {}
	world.frame:Fire("GROUP_ROSTER_UPDATE")
	eq(badgeOf(mageRow), nil)
end)

test("group finder quick dropdown updates spec, toggles and party overrides live", function()
	local world = boot(function(w)
		feral(w)
		w.party = { { name = "Tree", class = "DRUID", level = 60 } }
		w.friends = { "Tree" }
	end)
	world.results[1] = solo("Stab", "ROGUE", { dps = true })
	world.results[2] = solo("Frost", "MAGE", { dps = true })
	local rogueRow = makeEntry(world, 1)
	local mageRow = makeEntry(world, 2)

	ok(world.D.browseControl ~= nil, "browse control attached")
	eq(world.D.browseControl.text, "Mitts Off: Feral (cat/bear)")
	eq(badgeOf(rogueRow), RED)
	eq(badgeOf(mageRow), YELLOW) -- Tree's spec is unknown

	-- Override party member Tree to Resto via the quick dropdown submenu.
	local treeSub = findMenuItem(world.D.browseControl.menu, "Tree (Any)")
	findMenuItem(treeSub.menu, "Restoration").select()
	eq(badgeOf(mageRow), RED)

	-- Switch player to Balance via quick dropdown.
	findMenuItem(world.D.browseControl.menu, "Balance").select()
	eq(world.D.browseControl.text, "Mitts Off: Balance")
	eq(badgeOf(rogueRow), nil)
	eq(badgeOf(mageRow), RED)

	-- Turn off Group Finder badges via quick toggle.
	findMenuItem(world.D.browseControl.menu, "Show in Group Finder").select()
	eq(world.D.browseControl.text, "Mitts Off: Off")
	eq(badgeOf(mageRow), nil)
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
	eq(tooltipPairs(world, 1), { { "[MS] New vs Pal", "cloth spell" } })
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
	eq(tooltipPairs(world, 1), { { "[MS] Pal vs Pug", "cloth spell" } })
end)

test("battle.net friend on another realm is matched and non-WoW games ignored", function()
	local world = boot(function(w)
		feral(w)
		w.party = {
			{ name = "Pal", realm = "Area 52", class = "MAGE", level = 60 },
			{ name = "Pal", class = "WARLOCK", level = 60 },
			{ name = "D4Pal", class = "PRIEST", level = 60 },
		}
		w.bnet = {
			{ characterName = "Pal", realmName = "Area52", clientProgram = "WoW" },
			{ characterName = "D4Pal", realmName = "Stormrage", clientProgram = "Fen" },
		}
	end)
	world.results[1] = solo("New", "PRIEST", { dps = true })
	eq(tooltipPairs(world, 1), { { "[MS] New vs Pal", "cloth spell" } })
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

test("party members carry over specs seen in finder or whispers", function()
	local world = boot(function(w)
		feral(w)
		w.listed = true
	end)
	-- Moon whispers as boomkin before joining; party role remains NONE.
	whisper(world, "boomkin lfg", "Moon", "DRUID")
	world.party = { { name = "Moon", class = "DRUID", level = 60, role = "NONE" } }
	world.friends = { "Moon" }
	world.frame:Fire("FRIENDLIST_UPDATE")
	world.results[1] = solo("Frost", "MAGE", { dps = true })
	world.results[2] = solo("Stab", "ROGUE", { dps = true })
	eq(tooltipPairs(world, 1), { { "[MS] Frost vs Moon", "cloth spell" } })
	-- Moon is Balance, not Feral, so Stab only conflicts with you (not Moon).
	eq(tooltipPairs(world, 2), { { "[MS] Stab vs you", "leather physical" } })
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
	eq(tooltipPairs(world, 1), {
		{ "[MS] Stab vs you", "leather physical" },
		{ "[?] Lead vs you", "physical (tank damage)" },
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
	eq(world.D.me().key, "me")
end)

test("a solo listing's comment names spec or fills missing roles without overriding ticked role", function()
	local world = boot(feral)
	world.results[1] = solo("Moon", "DRUID", { dps = true }, { comment = "boomkin lf ZF" })
	world.results[2] = solo("Claw", "DRUID", { dps = true }, { comment = "cat dps lf ZF" })
	world.results[3] = solo("Dru", "DRUID", { dps = true })
	world.results[4] = solo("Sham", "SHAMAN", {}, { comment = "enh sham lfg" })
	world.results[5] = solo("Bear", "DRUID", { tank = true }, { comment = "can resto, tanking" })
	eq(tooltipPairs(world, 1), { { "[OS] Moon vs you", "leather physical (their offspec)" } })
	eq(tooltipPairs(world, 2), { { "[MS] Claw vs you", "leather physical" } })
	eq(tooltipPairs(world, 3), { { "[?] Dru vs you", "physical (spec unknown)" } })
	eq(tooltipPairs(world, 4), { { "[?] Sham vs you", "weapons, cloaks, jewelry" } })
	eq(tooltipPairs(world, 5), { { "[MS] Bear vs you", "leather physical" } })
end)

test("level decides armor", function()
	local world = boot(function(w)
		feral(w)
		w.player.level = 35
	end)
	world.results[1] = { members = { { name = "Hunt", class = "HUNTER", roles = { dps = true }, level = 36 } } }
	eq(tooltipPairs(world, 1), { { "[MS] Hunt vs you", "leather physical" } })
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
	eq(tooltipPairs(world, 1), { { "[?] Prot vs you", "physical (tank damage)" } })
	world.player.role = "TANK"
	eq(tooltipPairs(world, 1), { { "[?] Prot vs you", "weapons, cloaks, jewelry" } })
end)

test("whispers warn while listed or leading an open group, and cache silently when unlisted", function()
	local world = boot(feral)
	whisper(world, "cat dps lf group", "Claw-Stormrage", "DRUID")
	eq(world.chat, {})
	ok(world.D.seen["claw"] ~= nil and world.D.seen["claw"].build == "cat", "cached while unlisted")

	-- Leading an open group warns via groupWhispers.
	world.player.isLeader = true
	world.party = { { name = "Pal", class = "MAGE", level = 60 } }
	whisper(world, "inv pls", "Stab-Stormrage", "ROGUE")
	eq(world.chat, { "Mitts Off! [MS] Stab vs you: leather physical" })

	-- Disabling groupWhispers stops it when unlisted, while listed still warns.
	SlashCmdList.MITTSOFF("groupwhispers")
	world.chat = {}
	whisper(world, "inv pls", "RogueTwo", "ROGUE")
	eq(world.chat, {})

	-- Full group (5) does not warn even with groupWhispers enabled.
	SlashCmdList.MITTSOFF("groupwhispers")
	world.chat = {}
	world.party = {
		{ name = "A", class = "MAGE", level = 60 },
		{ name = "B", class = "MAGE", level = 60 },
		{ name = "C", class = "MAGE", level = 60 },
		{ name = "D", class = "MAGE", level = 60 },
	}
	whisper(world, "inv pls", "RogueThree", "ROGUE")
	eq(world.chat, {})

	world.party = {}
	world.listed = true
	whisper(world, "inv pls", "RogueThree", "ROGUE")
	eq(world.chat, { "Mitts Off! [MS] RogueThree vs you: leather physical" })
end)

test("whispers stay quiet per sender unless severity escalates, and drop stale conflicting build", function()
	local world = boot(function(w)
		feral(w)
		w.listed = true
	end)
	whisper(world, "inv", "Dru", "DRUID")
	eq(world.chat, { "Mitts Off! [?] Dru vs you: physical (spec unknown)" })
	-- Same or lower severity within 120s is quiet.
	world.now = world.now + 5
	whisper(world, "still there?", "Dru", "DRUID")
	eq(#world.chat, 1)
	-- Higher severity escalates immediately through quiet timer.
	world.now = world.now + 5
	whisper(world, "boomkin btw", "Dru", "DRUID")
	eq(world.chat[2], "Mitts Off! [OS] Dru vs you: leather physical (their offspec)")
	-- Conflicting role in a follow-up whisper drops the stale boomkin build.
	world.now = world.now + 125
	whisper(world, "actually I can heal", "Dru", "DRUID")
	eq(world.D.seen["dru"].build, nil)
	eq(world.D.seen["dru"].roles, { HEALER = true })
	-- Escalating to MS from OS also cuts through quiet timer.
	world.now = world.now + 5
	whisper(world, "or cat dps", "Dru", "DRUID")
	eq(world.chat[4], "Mitts Off! [MS] Dru vs you: leather physical")
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
		"Mitts Off! [OS] Tree vs you: leather physical (their offspec)",
		"Mitts Off! [MS] Claw vs you: leather physical",
		"Mitts Off! [?] Totem vs you: weapons, cloaks, jewelry",
	})
end)

test("battle.net whispers warn for WoW friends", function()
	local world = boot(function(w)
		feral(w)
		w.listed = true
		w.bnetAccounts[55] = { characterName = "Buddy", realmName = "Area52", clientProgram = "WoW", className = "Rogue", characterLevel = 60 }
		w.bnetAccounts[56] = { characterName = "D4Buddy", realmName = "Area52", clientProgram = "Fen", className = "Rogue", characterLevel = 60 }
	end)
	world.frame:Fire("CHAT_MSG_BN_WHISPER", "inv me", "BTag", "", "", "", "", 0, 0, "", 0, 0, "", 55)
	world.frame:Fire("CHAT_MSG_BN_WHISPER", "hey", "Other", "", "", "", "", 0, 0, "", 0, 0, "", 56)
	eq(world.chat, { "Mitts Off! [MS] Buddy vs you: leather physical" })
end)

test("a holy priest and a resto druid both see mages red", function()
	local world = boot(function(w)
		w.player.class, w.player.points, w.player.role = "PRIEST", { 20, 31, 0 }, "HEALER"
	end)
	world.results[1] = solo("Frost", "MAGE", { dps = true })
	eq(tooltipPairs(world, 1), { { "[MS] Frost vs you", "cloth spell power" } })
	world.player.class, world.player.points = "DRUID", { 0, 11, 40 }
	eq(tooltipPairs(world, 1), { { "[MS] Frost vs you", "cloth spell power" } })
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

test("inviting warns from seen cache, target, guild or friends and still invites", function()
	local world = boot(function(w)
		feral(w)
		w.target = { name = "TargetRogue", class = "ROGUE", level = 60 }
		w.guild = { { name = "GuildRogue-Stormrage", level = 60, classFileName = "ROGUE" } }
		w.friends = { { name = "FriendRogue", level = 60, className = "Rogue" } }
	end)
	world.results[1] = solo("Stab", "ROGUE", { dps = true })
	icon(world, 1)
	C_PartyInfo.InviteUnit("Stab")
	C_PartyInfo.InviteUnit("TargetRogue")
	C_PartyInfo.InviteUnit("GuildRogue")
	C_PartyInfo.InviteUnit("FriendRogue")
	C_PartyInfo.InviteUnit("Nobody")
	eq(world.invited, { "Stab", "TargetRogue", "GuildRogue", "FriendRogue", "Nobody" })
	eq(world.chat, {
		"Mitts Off! [MS] Stab vs you: leather physical",
		"Mitts Off! [MS] TargetRogue vs you: leather physical",
		"Mitts Off! [MS] GuildRogue vs you: leather physical",
		"Mitts Off! [MS] FriendRogue vs you: leather physical",
	})
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

test("/mittsoff check supports classes, aliases, specs, levels, target and rejects bad args", function()
	local world = boot(function(w)
		feral(w)
		w.target = { name = "Zul", class = "ROGUE", level = 60 }
	end)
	SlashCmdList.MITTSOFF("check rogue")
	SlashCmdList.MITTSOFF("check mage dps")
	SlashCmdList.MITTSOFF("check sham enh 35")
	SlashCmdList.MITTSOFF("check druid cat")
	SlashCmdList.MITTSOFF("check target")
	SlashCmdList.MITTSOFF("check mage tank")
	SlashCmdList.MITTSOFF("check rogue banana")
	eq(world.chat, {
		"Mitts Off! [MS] Rogue vs you: leather physical",
		"Mitts Off! No competition.",
		"Mitts Off! [MS] Shaman vs you: leather physical",
		"Mitts Off! [MS] Druid vs you: leather physical",
		"Mitts Off! [MS] Zul vs you: leather physical",
		"Mitts Off! Mage cannot play tank.",
		"Mitts Off! Unknown role or spec for Rogue: banana.",
	})
end)

test("/mittsoff status shows the detected spec and current group", function()
	local world = boot(function(w)
		feral(w)
		w.party = { { name = "Pal", class = "MAGE", level = 60 } }
		w.friends = { "Pal" }
	end)
	SlashCmdList.MITTSOFF("status")
	eq(world.chat[1], "Mitts Off! You are gearing as Feral (cat) or Feral (bear).")
	eq(world.chat[2], "Mitts Off! Most talent points: Second (30), tree 2.")
	eq(world.chat[3], "Mitts Off! Group: Pal (Mage, Friend).")
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

test("settings panel shows saved values, preview, hover tooltips and group controls", function()
	local world = boot(function(w)
		feral(w)
		w.party = { { name = "Pal", class = "MAGE", level = 60 } }
		w.friends = { "Pal" }
	end)
	SlashCmdList.MITTSOFF("")
	for _, section in ipairs(world.D.SECTIONS) do
		for _, item in ipairs(section.items) do
			eq(world.D.checks[item[1]].checked, world.D.DEFAULTS[item[1]], item[1])
		end
	end
	local rogueTuple, roguePreview = previewRow(world, "Rogue")
	local restoTuple, restoPreview = previewRow(world, "Restoration Druid")
	eq(rogueTuple, { RED, "leather physical" })
	eq(restoTuple, { RED, "cloth spell power" })
	eq(previewRow(world, "Arms / Fury Warrior"), { YELLOW, "weapons, cloaks, jewelry" })
	eq(previewRow(world, "Mage"), { RED, "cloth spell" })

	-- Hovering a preview row lists all conflicts in GameTooltip (here both Pal and you).
	restoPreview.scripts.OnEnter(restoPreview)
	eq(world.tooltip.shown, true)
	eq(world.tooltip.doubleLines, {
		{ "[MS] vs Pal", "cloth spell power" },
		{ "[OS] vs you", "leather physical (their offspec)" },
	})
	restoPreview.scripts.OnLeave(restoPreview)
	eq(world.tooltip.shown, false)
	ok(roguePreview ~= nil)

	-- Hovering a checkbox shows a brief tooltip.
	local offCheck = world.D.checks.offspec
	offCheck.scripts.OnEnter(offCheck)
	eq(world.tooltip.shown, true)
	offCheck.scripts.OnLeave(offCheck)
	eq(world.tooltip.shown, false)

	-- Group section lists Pal and opens menu on click; unprotecting Pal drops Mage clear and Resto to OS.
	eq(world.D.groupRows[1].shown, true)
	eq(world.D.groupRows[1].specText.text, "Mage")
	world.D.groupRows[1].specButton.scripts.OnClick(world.D.groupRows[1].specButton)
	ok(world.contextMenu ~= nil, "member context menu opened")
	findMenuItem(world.contextMenu.menu, "Protect loot").select()
	eq(world.D.memberCared["pal"], false)
	eq(previewRow(world, "Mage")[1], CLEAR)
	eq(previewRow(world, "Restoration Druid"), { ORANGE, "leather physical, OS" })
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
	eq(previewRow(world, "Arms / Fury Warrior"), { RED, "leather physical" })
	click("offspec", false)
	eq(previewRow(world, "Restoration Druid"), { CLEAR, "" })
	click("rollDown", false)
	click("accessories", false)
	eq(previewRow(world, "Arms / Fury Warrior"), { CLEAR, "" })
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
	world.D.memberCared["someone"] = true
	menu[2].select()
	eq(MittsOffCharDB.build, "balance")
	eq(world.D.specDropdown.menu[2].isSelected(), true)
	eq(previewRow(world, "Rogue"), { CLEAR, "" })
	eq(previewRow(world, "Mage"), { RED, "cloth spell" })
	world.D.reset()
	eq(MittsOffDB.whispers, true)
	eq(MittsOffCharDB.build, nil)
	eq(world.D.memberCared, {})
	eq(previewRow(world, "Rogue"), { RED, "leather physical" })
end)

test("the settings panel shows the leading talent tree", function()
	local world = boot(feral)
	SlashCmdList.MITTSOFF("")
	eq(world.D.talentsText.text, "Most talent points: Second (30).")
	world.player.points = { 10, 10, 0 }
	world.D.refreshSettings()
	eq(world.D.talentsText.text, "No single talent tree leads, so your party role decides.")
end)

local function checkLines(world)
	local out = {}
	for _, line in ipairs(world.D.checkLines) do
		if line.text == "" then break end
		out[#out + 1] = (line.text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
	end
	return out
end

local function menuLabels(menu)
	local out = {}
	for i, item in ipairs(menu.menu) do
		out[i] = item.text
	end
	return out
end

local function pick(menu, label)
	for _, radio in ipairs(menu.menu) do
		if radio.text == label then return radio.select() end
	end
	error("no option " .. label)
end

test("the check page filters valid specs, supports level and target, and matches /mittsoff check", function()
	local world = boot(function(w)
		feral(w)
		w.target = { name = "Zul", class = "ROGUE", level = 60 }
	end)
	SlashCmdList.MITTSOFF("check")
	eq(world.opened, "Check a player")
	eq(world.category.name, "Mitts Off!")
	eq(world.categories["Check a player"].parent, world.category)

	pick(world.D.checkClassMenu, "Rogue")
	eq(menuLabels(world.D.checkSpecMenu), { "Any spec" })
	eq(checkLines(world), { "[MS] Rogue vs you: leather physical" })

	pick(world.D.checkClassMenu, "Mage")
	eq(menuLabels(world.D.checkSpecMenu), { "Any spec" })
	eq(checkLines(world), { "No competition." })

	pick(world.D.checkClassMenu, "Shaman")
	eq(menuLabels(world.D.checkSpecMenu), { "Any spec", "Damage (any)", "Elemental", "Enhancement", "Restoration" })
	pick(world.D.checkSpecMenu, "Enhancement")
	eq(checkLines(world), { "[?] Shaman vs you: weapons, cloaks, jewelry" })
	pick(world.D.checkLevelMenu, "Under 40")
	eq(checkLines(world), { "[MS] Shaman vs you: leather physical" })

	world.D.checkTargetButton.scripts.OnClick(world.D.checkTargetButton)
	eq(checkLines(world), { "[MS] Zul vs you: leather physical" })

	world.target = nil
	world.D.checkTargetButton.scripts.OnClick(world.D.checkTargetButton)
	eq(checkLines(world), { "Target a player first." })

	eq(world.chat, {})
	SlashCmdList.MITTSOFF("check rogue")
	eq(world.chat, { "Mitts Off! [MS] Rogue vs you: leather physical" })
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
	eq(MittsOffDB.groupWhispers, true)
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
