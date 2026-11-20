-- Game side of Mitts Off: builds profiles for the player, the party and whoever is
-- being considered, asks Rules for conflicts, and shows them in the group
-- finder, in chat for whispers, and in chat when an invite goes out.

local _, ns = ...
local R = ns.Rules

local D = { seen = {}, whispered = {} }
ns.MittsOff = D

-- Saved settings: every rule from Rules.DEFAULTS, plus where warnings show.
local DEFAULTS = { finder = true, whispers = true, invites = true }
for name, value in pairs(R.DEFAULTS) do
	DEFAULTS[name] = value
end
D.DEFAULTS = DEFAULTS
local ROLES = { TANK = true, HEALER = true, DAMAGER = true }
-- Class talent trees on Forever, by class ID.
local TREES = { [1] = 1117, [2] = 1100, [3] = 1091, [4] = 1111, [5] = 1114, [7] = 1082, [8] = 1112, [9] = 1116, [11] = 1089 }
local COLORS = { [R.WILL] = "ffff4040", [R.OFFSPEC] = "ffff8c1a", [R.MIGHT] = "ffffd100" }
-- Texture and tint for the dot on a group finder row. There is no orange dot, so the yellow one is tinted.
local ICONS = {
	[R.WILL] = { "Interface\\COMMON\\Indicator-Red", 1, 1, 1 },
	[R.OFFSPEC] = { "Interface\\COMMON\\Indicator-Yellow", 1, 0.5, 0.2 },
	[R.MIGHT] = { "Interface\\COMMON\\Indicator-Yellow", 1, 1, 1 },
}
local WHISPER_QUIET_SECONDS = 120

local function plain(value)
	if issecretvalue and issecretvalue(value) then return nil end
	return value
end

local function say(text) DEFAULT_CHAT_FRAME:AddMessage("|cffffd100Mitts Off!|r " .. text) end

---------------------------------------------------------------------------
-- Names and relations

-- One key per character: "name" on the player's realm, "name-realm" elsewhere.
function D.key(name, realm)
	name = plain(name)
	if type(name) ~= "string" or name == "" then return nil end
	local short, fromName = name:match("^([^-]+)-(.+)$")
	if short then name, realm = short, fromName end
	realm = plain(realm)
	realm = type(realm) == "string" and realm:gsub("[%s%-']", "") or ""
	local home = (GetNormalizedRealmName and GetNormalizedRealmName() or ""):gsub("[%s%-']", "")
	if realm == "" or realm:lower() == home:lower() then return name:lower() end
	return (name .. "-" .. realm):lower()
end

local function rebuildCared()
	local cared = {}
	local function add(name, realm)
		local key = D.key(name, realm)
		if key then cared[key] = true end
	end
	if C_FriendList and C_FriendList.GetNumFriends then
		for i = 1, C_FriendList.GetNumFriends() or 0 do
			local info = C_FriendList.GetFriendInfoByIndex(i)
			if info then add(info.name) end
		end
	end
	if IsInGuild and IsInGuild() and GetNumGuildMembers then
		for i = 1, GetNumGuildMembers() or 0 do
			add((GetGuildRosterInfo(i)))
		end
	end
	if BNGetNumFriends and C_BattleNet and C_BattleNet.GetFriendAccountInfo then
		for i = 1, BNGetNumFriends() or 0 do
			local accounts = C_BattleNet.GetFriendNumGameAccounts and C_BattleNet.GetFriendNumGameAccounts(i) or 0
			for j = 1, accounts do
				local game = C_BattleNet.GetFriendGameAccountInfo(i, j)
				if game then add(game.characterName, game.realmName) end
			end
			local account = C_BattleNet.GetFriendAccountInfo(i)
			local game = account and account.gameAccountInfo
			if game then add(game.characterName, game.realmName) end
		end
	end
	D.caredSet = cared
end

-- True for friends, Battle.net friends and guildmates.
function D.cared(key)
	if not key then return false end
	if not D.caredSet then rebuildCared() end
	return D.caredSet[key] == true
end

---------------------------------------------------------------------------
-- Profiles

-- The talent tree (1 to 3, in talent pane order) holding most of the player's
-- points, and its name; nil on a tie. Tree groups come back unordered and
-- their IDs follow no order either, so the client's orderIndex decides.
function D.myTree()
	if not (C_ClassTalents and C_ClassTalents.GetActiveConfigID and C_Traits and C_Traits.GetGroupDisplayInfoByTreeID and C_Traits.GetGroupCurrencyInfo) then return nil end
	local treeID = TREES[plain(select(3, UnitClass("player")))]
	local configID = plain(C_ClassTalents.GetActiveConfigID())
	if not treeID or not configID then return nil end
	local infos, groups = {}, {}
	for _, info in ipairs(C_Traits.GetGroupDisplayInfoByTreeID(treeID) or {}) do
		local id, order = plain(info.groupID), plain(info.orderIndex)
		if id and order then infos[#infos + 1] = { id = id, order = order, name = plain(info.displayName) } end
	end
	if #infos ~= 3 then return nil end
	table.sort(infos, function(x, y) return x.order < y.order end)
	for index, info in ipairs(infos) do
		groups[index] = info.id
	end
	local best, bestSpent, tied = nil, 0, false
	-- Trees with no points are left out of the reply.
	for _, info in ipairs(C_Traits.GetGroupCurrencyInfo(configID, groups) or {}) do
		local id = plain(info.traitNodeGroupID)
		local currency = info.currencyInfos and info.currencyInfos[1]
		local spent = currency and plain(currency.spent)
		if id and type(spent) == "number" then
			if spent > bestSpent then
				best, bestSpent, tied = id, spent, false
			elseif spent == bestSpent then
				tied = true
			end
		end
	end
	if not best or tied then return nil end
	for index, id in ipairs(groups) do
		if id == best then return index, infos[index].name, bestSpent end
	end
end

local function unitRoles(unit)
	local role = UnitGroupRolesAssigned and plain(UnitGroupRolesAssigned(unit))
	if ROLES[role] then return { [role] = true } end
end

local function unitLevel(unit)
	local level = plain(UnitLevel(unit))
	if type(level) == "number" and level > 0 then return level end
end

function D.me()
	local profile = {
		name = plain((UnitName("player"))),
		class = plain(select(2, UnitClass("player"))),
		level = unitLevel("player"),
		isSelf = true,
		build = MittsOffCharDB and MittsOffCharDB.build or nil,
		tree = (D.myTree()),
		roles = unitRoles("player"),
	}
	-- Talents are fact, the party role is a label: drop a role no build in the tree plays.
	if profile.tree and profile.roles then
		local fits = false
		for _, build in ipairs(R.mainBuilds({ class = profile.class, tree = profile.tree })) do
			if profile.roles[build.role] then fits = true end
		end
		if not fits then profile.roles = nil end
	end
	return profile
end

-- The player first, then everyone else in the party or raid.
function D.group()
	local group = { D.me() }
	local count = GetNumGroupMembers and GetNumGroupMembers() or 0
	local raid = IsInRaid and IsInRaid()
	for i = 1, raid and count or math.max(count - 1, 0) do
		local unit = (raid and "raid" or "party") .. i
		if UnitExists(unit) and not UnitIsUnit(unit, "player") then
			local name, realm = UnitName(unit)
			local class = plain(select(2, UnitClass(unit)))
			local key = D.key(name, realm)
			if class and key then
				group[#group + 1] = { name = plain(name), key = key, class = class, level = unitLevel(unit), roles = unitRoles(unit), cared = D.cared(key) }
			end
		end
	end
	return group
end

local function remember(profile)
	if profile.key then D.seen[profile.key] = profile end
	return profile
end

-- Everyone in a group finder listing, as candidate profiles.
function D.resultCandidates(resultID)
	local candidates = {}
	local info = resultID and C_LFGList.GetSearchResultInfo(resultID)
	if not info or plain(info.hasSelf) or plain(info.isDelisted) then return candidates end
	local count = plain(info.numMembers) or 0
	for i = 1, count do
		local member = C_LFGList.GetSearchResultPlayerInfo(resultID, i)
		local class = member and plain(member.classFilename)
		local key = member and D.key(member.name)
		if class and key then
			local profile = { name = plain(member.name), key = key, class = class, level = plain(member.level), cared = D.cared(key) }
			local listed = member.lfgRoles
			if count == 1 and type(listed) == "table" then
				-- Someone listed alone ticks every role they are willing to play.
				profile.roles = { TANK = listed.tank or nil, HEALER = listed.healer or nil, DAMAGER = listed.dps or nil }
				profile.build = select(2, R.hints(plain(info.comment), class))
			elseif ROLES[plain(member.assignedRole)] then
				profile.roles = { [member.assignedRole] = true }
			end
			candidates[#candidates + 1] = remember(profile)
		end
	end
	return candidates
end

-- Conflicts between candidates and the current group, strongest first.
function D.check(candidates)
	local group = D.group()
	local inGroup = {}
	for _, member in ipairs(group) do
		if member.key then inGroup[member.key] = true end
	end
	local outside = {}
	for _, candidate in ipairs(candidates) do
		if not inGroup[candidate.key] then outside[#outside + 1] = candidate end
	end
	return R.evaluate(outside, group, MittsOffDB)
end

local function colored(conflict) return ("|c%s%s|r"):format(COLORS[conflict.severity], R.describe(conflict)) end

local function report(found, limit)
	for i = 1, math.min(#found, limit or 3) do
		say(colored(found[i]))
	end
end

---------------------------------------------------------------------------
-- Group finder

local function updateEntry(entry)
	local _, top
	if MittsOffDB.finder then
		_, top = D.check(D.resultCandidates(entry.resultID))
	end
	if not top then
		if entry.MittsOffIcon then entry.MittsOffIcon:Hide() end
		return
	end
	if not entry.MittsOffIcon then
		entry.MittsOffIcon = entry:CreateTexture(nil, "OVERLAY")
		entry.MittsOffIcon:SetSize(14, 14)
		entry.MittsOffIcon:SetPoint("TOPRIGHT", entry, "TOPRIGHT", -6, -5)
	end
	local path, r, g, b = ICONS[top][1], ICONS[top][2], ICONS[top][3], ICONS[top][4]
	entry.MittsOffIcon:SetTexture(path)
	entry.MittsOffIcon:SetVertexColor(r, g, b)
	entry.MittsOffIcon:Show()
end

local function updateTooltip(tooltip, resultID)
	local found = MittsOffDB.finder and D.check(D.resultCandidates(resultID)) or {}
	if #found == 0 then
		if GameTooltip:GetOwner() == tooltip then GameTooltip:Hide() end
		return
	end
	GameTooltip:SetOwner(tooltip, "ANCHOR_NONE")
	GameTooltip:SetPoint("TOPLEFT", tooltip, "BOTTOMLEFT", 0, -2)
	for i = 1, math.min(#found, 6) do
		GameTooltip:AddLine(colored(found[i]), 1, 1, 1, true)
	end
	GameTooltip:Show()
end

local function hookGroupFinder()
	if D.hooked or not LFGBrowseSearchEntry_Update then return end
	D.hooked = true
	hooksecurefunc("LFGBrowseSearchEntry_Update", updateEntry)
	if LFGBrowseSearchEntryTooltip_UpdateAndShow and LFGBrowseSearchEntryTooltip then
		hooksecurefunc("LFGBrowseSearchEntryTooltip_UpdateAndShow", updateTooltip)
		LFGBrowseSearchEntryTooltip:HookScript("OnHide", function(tooltip)
			if GameTooltip:GetOwner() == tooltip then GameTooltip:Hide() end
		end)
	end
end

---------------------------------------------------------------------------
-- Whispers and invites

local function onWhisper(text, sender, guid)
	if not MittsOffDB.whispers or not (C_LFGList and C_LFGList.HasActiveEntryInfo and C_LFGList.HasActiveEntryInfo()) then return end
	local key = D.key(sender)
	guid = plain(guid)
	if not key or not guid then return end
	local class = plain(select(2, GetPlayerInfoByGUID(guid)))
	if not class then return end
	local roles, build = R.hints(plain(text), class)
	local known = D.seen[key]
	-- Their level is not in the whisper; they want the same content, so assume the player's.
	local profile = remember({
		name = sender:match("^[^-]+"),
		key = key,
		class = class,
		level = known and known.level or unitLevel("player"),
		roles = roles or (known and known.roles),
		build = build or (known and known.build),
		cared = D.cared(key),
	})
	local now = GetTime()
	if D.whispered[key] and now - D.whispered[key] < WHISPER_QUIET_SECONDS then return end
	local found = D.check({ profile })
	if #found > 0 then
		D.whispered[key] = now
		report(found)
	end
end

-- Any invite of someone seen in the finder or in whispers repeats the warning.
local function onInvite(name)
	local profile = MittsOffDB.invites and D.seen[D.key(name) or ""]
	if profile then report((D.check({ profile }))) end
end

---------------------------------------------------------------------------
-- Settings and preview

function D.set(name, value) MittsOffDB[name] = value end

function D.reset()
	for name, value in pairs(DEFAULTS) do
		MittsOffDB[name] = value
	end
	MittsOffCharDB.build = nil
end

-- Every spec of every class as a hypothetical invite into the current group,
-- for the settings panel: { class, build, single, conflict } per row, where
-- single marks a class with one build and conflict is the strongest or nil.
function D.preview()
	local rows = {}
	local level = unitLevel("player")
	for _, class in ipairs({ "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }) do
		local builds = R.BUILDS[class]
		for _, build in ipairs(builds) do
			local found = D.check({ { name = "They", class = class, level = level, build = build.key } })
			rows[#rows + 1] = { class = class, build = build, single = #builds == 1, conflict = found[1] }
		end
	end
	return rows
end

---------------------------------------------------------------------------
-- Slash command

local TOGGLES = {
	strangers = { field = "caredOnly", on = "Ignoring conflicts between strangers", off = "Warning about conflicts between strangers too" },
	offspec = { field = "offspec", on = "Counting offspec rolls", off = "Ignoring offspec rolls" },
	whispers = { field = "whispers", on = "Checking whispers while listed", off = "Ignoring whispers" },
}
D.COLORS, D.ICONS = COLORS, ICONS

local function buildNames(builds)
	local names = {}
	for i, build in ipairs(builds) do
		names[i] = build.name
	end
	return table.concat(names, " or ")
end

local function status()
	local me = D.me()
	say(("You are gearing as %s%s."):format(buildNames(R.mainBuilds(me)), me.build and " (set by you)" or ""))
	local tree, treeName, spent = D.myTree()
	if tree then
		say(("Most talent points: %s (%d), tree %d."):format(treeName or "?", spent, tree))
	else
		say("No single talent tree leads, so your party role decides.")
	end
	for _, name in ipairs({ "strangers", "offspec", "whispers" }) do
		local toggle = TOGGLES[name]
		say(("/mittsoff %s: %s"):format(name, MittsOffDB[toggle.field] and toggle.on or toggle.off))
	end
	local keys = { "auto" }
	for _, build in ipairs(R.BUILDS[me.class] or {}) do
		keys[#keys + 1] = build.key
	end
	say("/mittsoff spec " .. table.concat(keys, " | "))
	say("/mittsoff check <class> [tank | healer | dps]")
end
D.buildNames = buildNames

local ROLE_ARGS = { tank = "TANK", healer = "HEALER", heal = "HEALER", dps = "DAMAGER" }

function D.slash(input)
	local command, arg1, arg2 = tostring(input or ""):lower():match("^%s*(%S*)%s*(%S*)%s*(%S*)")
	local toggle = TOGGLES[command]
	if toggle then
		MittsOffDB[toggle.field] = not MittsOffDB[toggle.field]
		say((MittsOffDB[toggle.field] and toggle.on or toggle.off) .. ".")
	elseif command == "spec" then
		local class = D.me().class
		if arg1 == "auto" or arg1 == "" then
			MittsOffCharDB.build = nil
		elseif R.build(class, arg1) then
			MittsOffCharDB.build = arg1
		else
			say("No such spec for your class.")
			return
		end
		say(("You are gearing as %s."):format(buildNames(R.mainBuilds(D.me()))))
	elseif command == "check" and R.BUILDS[arg1:upper()] then
		local role = ROLE_ARGS[arg2]
		local candidate = { name = "They", class = arg1:upper(), level = unitLevel("player"), roles = role and { [role] = true } or nil }
		local found = D.check({ candidate })
		if #found == 0 then say("No competition.") end
		report(found, 10)
	elseif command == "" and D.openSettings and D.openSettings() then
		return
	else
		status()
	end
end

---------------------------------------------------------------------------
-- Events

local frame = CreateFrame("Frame")
D.frame = frame
for _, event in ipairs({ "ADDON_LOADED", "PLAYER_LOGIN", "CHAT_MSG_WHISPER", "FRIENDLIST_UPDATE", "GUILD_ROSTER_UPDATE", "BN_FRIEND_INFO_CHANGED" }) do
	frame:RegisterEvent(event)
end
frame:SetScript("OnEvent", function(_, event, ...)
	if event == "ADDON_LOADED" then
		MittsOffDB = MittsOffDB or {}
		for name, value in pairs(DEFAULTS) do
			if MittsOffDB[name] == nil then MittsOffDB[name] = value end
		end
		MittsOffCharDB = MittsOffCharDB or {}
		hookGroupFinder()
	elseif event == "PLAYER_LOGIN" then
		hooksecurefunc(C_PartyInfo, "InviteUnit", onInvite)
		if C_GuildInfo and C_GuildInfo.GuildRoster then C_GuildInfo.GuildRoster() end
		SLASH_MITTSOFF1, SLASH_MITTSOFF2 = "/mittsoff", "/mitts"
		SlashCmdList.MITTSOFF = D.slash
		if D.registerSettings then D.registerSettings() end
	elseif event == "CHAT_MSG_WHISPER" then
		local text, sender = ...
		onWhisper(text, sender, (select(12, ...)))
	else
		D.caredSet = nil
	end
end)
