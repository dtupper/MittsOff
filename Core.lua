-- Game side of Mitts Off: builds profiles for the player, the party and whoever is
-- being considered, asks Rules for conflicts, and shows them in the group
-- finder, in chat for whispers, and in chat when an invite goes out.

local _, ns = ...
local R = ns.Rules

local D = {
	seen = {},
	whispered = {},
	memberBuilds = {},
	memberCared = {},
	entries = setmetatable({}, { __mode = "k" }),
}
ns.MittsOff = D

-- Saved settings: every rule from Rules.DEFAULTS, plus where warnings show.
local DEFAULTS = { finder = true, whispers = true, groupWhispers = true, invites = true }
for name, value in pairs(R.DEFAULTS) do
	DEFAULTS[name] = value
end
D.DEFAULTS = DEFAULTS

local ROLES = { TANK = true, HEALER = true, DAMAGER = true }
-- Class talent trees on Forever, by class ID (fallback if C_Traits.GetConfigInfo is unavailable).
local TREES = { [1] = 1117, [2] = 1100, [3] = 1091, [4] = 1111, [5] = 1114, [7] = 1082, [8] = 1112, [9] = 1116, [11] = 1089 }
local WHISPER_QUIET_SECONDS = 120

D.CLASSES = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }

local BADGES = {
	[R.WILL] = { text = "MS", color = "ffff4d4d", bg = { 0.60, 0.10, 0.10 }, border = { 1.0, 0.32, 0.32 } },
	[R.OFFSPEC] = { text = "OS", color = "ffff8c1a", bg = { 0.66, 0.28, 0.04 }, border = { 1.0, 0.56, 0.12 } },
	[R.MIGHT] = { text = "?", color = "ffffd100", bg = { 0.52, 0.42, 0.05 }, border = { 1.0, 0.84, 0.18 } },
}
local CLEAR_BADGE = { text = "", bg = { 0.20, 0.20, 0.20 }, border = { 0.45, 0.45, 0.45 }, alpha = 0.4 }
local COLORS = {
	[R.WILL] = BADGES[R.WILL].color,
	[R.OFFSPEC] = BADGES[R.OFFSPEC].color,
	[R.MIGHT] = BADGES[R.MIGHT].color,
}
D.BADGES, D.COLORS = BADGES, COLORS

local FALLBACK_CLASS_NAMES = {
	WARRIOR = "Warrior",
	PALADIN = "Paladin",
	HUNTER = "Hunter",
	ROGUE = "Rogue",
	PRIEST = "Priest",
	SHAMAN = "Shaman",
	MAGE = "Mage",
	WARLOCK = "Warlock",
	DRUID = "Druid",
}

local CLASS_ALIASES = {
	warr = "WARRIOR",
	war = "WARRIOR",
	pala = "PALADIN",
	pally = "PALADIN",
	pal = "PALADIN",
	hunt = "HUNTER",
	rog = "ROGUE",
	pri = "PRIEST",
	sham = "SHAMAN",
	shamy = "SHAMAN",
	shammy = "SHAMAN",
	lock = "WARLOCK",
	dru = "DRUID",
}

local function plain(value)
	if issecretvalue and issecretvalue(value) then return nil end
	return value
end

local function say(text) DEFAULT_CHAT_FRAME:AddMessage("|cffffd100Mitts Off!|r " .. text) end

function D.className(class)
	return (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[class]) or FALLBACK_CLASS_NAMES[class] or class
end

function D.classColorHex(class)
	local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
	if c and c.r then
		return ("ff%02x%02x%02x"):format(math.floor(c.r * 255 + 0.5), math.floor(c.g * 255 + 0.5), math.floor(c.b * 255 + 0.5))
	end
	return "ffffffff"
end

function D.resolveClass(token)
	if type(token) ~= "string" or token == "" then return nil end
	local lower = token:lower()
	if R.BUILDS[token:upper()] then return token:upper() end
	if CLASS_ALIASES[lower] then return CLASS_ALIASES[lower] end
	for _, class in ipairs(D.CLASSES) do
		local male = LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[class]
		local female = LOCALIZED_CLASS_NAMES_FEMALE and LOCALIZED_CLASS_NAMES_FEMALE[class]
		if (male and male:lower() == lower) or (female and female:lower() == lower) then return class end
	end
end

local function resolveClassName(name)
	name = plain(name)
	if type(name) ~= "string" or name == "" then return nil end
	local trimmed = name:match("^%s*(.-)%s*$")
	return D.resolveClass(trimmed)
end

---------------------------------------------------------------------------
-- Badges and formatting

function D.createBadge(parent, width, height)
	local badge = CreateFrame("Frame", nil, parent)
	badge:SetSize(width or 26, height or 16)
	badge.border = badge:CreateTexture(nil, "BACKGROUND")
	badge.border:SetAllPoints(badge)
	badge.bg = badge:CreateTexture(nil, "ARTWORK")
	badge.bg:SetPoint("TOPLEFT", badge, "TOPLEFT", 1, -1)
	badge.bg:SetPoint("BOTTOMRIGHT", badge, "BOTTOMRIGHT", -1, 1)
	badge.label = badge:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	badge.label:SetPoint("CENTER", badge, "CENTER", 0, 0)
	if badge.label.GetFont and badge.label.SetFont then
		local font, size = badge.label:GetFont()
		if font then badge.label:SetFont(font, size or 10, "OUTLINE") end
	end
	return badge
end

function D.styleBadge(badge, severity)
	local spec = severity and BADGES[severity] or CLEAR_BADGE
	badge.severity = severity
	if badge.border and badge.border.SetColorTexture then
		badge.border:SetColorTexture(spec.border[1], spec.border[2], spec.border[3], 1)
		badge.bg:SetColorTexture(spec.bg[1], spec.bg[2], spec.bg[3], 0.92)
	end
	badge.label:SetText(spec.text)
	badge.label:SetTextColor(1, 1, 1)
	if badge.SetAlpha then badge:SetAlpha(spec.alpha or 1) end
end

local emphasizedFonts = {}

local function emphasizeRight(tooltip)
	local name = tooltip.GetName and tooltip:GetName()
	local lines = tooltip.NumLines and tooltip:NumLines()
	if not name or not lines then return end
	local fs = _G[name .. "TextRight" .. lines]
	if not (fs and fs.GetFont and fs.SetFont) then return end
	if not emphasizedFonts[fs] then
		local font, size, flags = fs:GetFont()
		if font then emphasizedFonts[fs] = { font, size, flags } end
	end
	local saved = emphasizedFonts[fs]
	if saved then fs:SetFont(saved[1], (saved[2] or 12) + 0.5, "OUTLINE") end
end

function D.restoreTooltipFonts()
	for fs, saved in pairs(emphasizedFonts) do
		fs:SetFont(saved[1], saved[2], saved[3])
	end
end

function D.formatConflict(conflict)
	local sev = COLORS[conflict.severity]
	local tag = BADGES[conflict.severity].text
	local who = conflict.candidate.name or "They"
	local other = conflict.member.isSelf and "you" or (conflict.member.name or "a party member")
	return ("|c%s[%s]|r %s vs %s: |c%s%s|r"):format(sev, tag, who, other, sev, R.reasonText(conflict))
end

local function coloredName(profile, fallback)
	if profile.isSelf then return "|cffffffffyou|r" end
	return ("|c%s%s|r"):format(D.classColorHex(profile.class), profile.name or fallback or "a party member")
end

function D.addConflictTooltipLine(tooltip, conflict, omitCandidate)
	local sev = COLORS[conflict.severity]
	local tag = BADGES[conflict.severity].text
	local other = coloredName(conflict.member, "a party member")
	local left
	if omitCandidate then
		left = ("|c%s[%s]|r |cffccccccvs|r %s"):format(sev, tag, other)
	else
		local who = coloredName(conflict.candidate, "They")
		left = ("|c%s[%s]|r %s |cffaaaaaavs|r %s"):format(sev, tag, who, other)
	end
	local right = ("|c%s%s|r"):format(sev, R.reasonText(conflict))
	if tooltip.AddDoubleLine then
		tooltip:AddDoubleLine(left, right, 1, 1, 1, 1, 1, 1)
		emphasizeRight(tooltip)
	else
		tooltip:AddLine(D.formatConflict(conflict), 1, 1, 1, true)
	end
end

local function report(found, limit)
	local shown = math.min(#found, limit or 3)
	for i = 1, shown do
		say(D.formatConflict(found[i]))
	end
	if #found > shown then
		say(("...and %d more."):format(#found - shown))
	end
end

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

local function isWowBnetGame(game)
	if not game then return false end
	local program = plain(game.clientProgram)
	if not program or program == "" then return true end
	return program == (BNET_CLIENT_WOW or "WoW")
end

local function rebuildCared()
	local cared = {}
	local function add(name, realm, tag)
		local key = D.key(name, realm)
		if key and not cared[key] then cared[key] = tag end
	end
	if C_FriendList and C_FriendList.GetNumFriends then
		for i = 1, C_FriendList.GetNumFriends() or 0 do
			local info = C_FriendList.GetFriendInfoByIndex(i)
			if info then add(info.name, nil, "Friend") end
		end
	end
	if BNGetNumFriends and C_BattleNet and C_BattleNet.GetFriendAccountInfo then
		for i = 1, BNGetNumFriends() or 0 do
			local accounts = C_BattleNet.GetFriendNumGameAccounts and C_BattleNet.GetFriendNumGameAccounts(i) or 0
			for j = 1, accounts do
				local game = C_BattleNet.GetFriendGameAccountInfo(i, j)
				if isWowBnetGame(game) then add(game.characterName, game.realmName, "Battle.net") end
			end
			local account = C_BattleNet.GetFriendAccountInfo(i)
			local game = account and account.gameAccountInfo
			if isWowBnetGame(game) then add(game.characterName, game.realmName, "Battle.net") end
		end
	end
	if IsInGuild and IsInGuild() and GetNumGuildMembers then
		for i = 1, GetNumGuildMembers() or 0 do
			add((GetGuildRosterInfo(i)), nil, "Guild")
		end
	end
	D.caredSet = cared
end

-- True for friends, Battle.net friends and guildmates.
function D.cared(key)
	if not key then return false end
	if not D.caredSet then rebuildCared() end
	return D.caredSet[key] ~= nil
end

function D.relation(key)
	if not key then return nil end
	if not D.caredSet then rebuildCared() end
	return D.caredSet[key]
end

---------------------------------------------------------------------------
-- Profiles

-- The talent tree (1 to 3, in talent pane order) holding most of the player's
-- points, and its name; nil on a tie. Tree groups come back unordered and
-- their IDs follow no order either, so the client's orderIndex decides.
function D.myTree()
	if not (C_ClassTalents and C_ClassTalents.GetActiveConfigID and C_Traits and C_Traits.GetGroupDisplayInfoByTreeID and C_Traits.GetGroupCurrencyInfo) then return nil end
	local configID = plain(C_ClassTalents.GetActiveConfigID())
	if not configID then return nil end
	local cfg = C_Traits.GetConfigInfo and C_Traits.GetConfigInfo(configID)
	local treeID = (cfg and cfg.treeIDs and plain(cfg.treeIDs[1])) or TREES[plain(select(3, UnitClass("player")))]
	if not treeID then return nil end
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
	local level = UnitLevel and plain(UnitLevel(unit))
	if type(level) == "number" and level > 0 then return level end
end

function D.me()
	local name, realm = UnitName("player")
	local profile = {
		name = plain(name),
		key = D.key(name, realm),
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
				local roles = unitRoles(unit)
				local build = D.memberBuilds[key]
				if build and not R.build(class, build) then build = nil end
				local seen = D.seen[key]
				if seen and seen.class == class then
					if not roles and seen.roles then roles = seen.roles end
					if not build and seen.build then
						local sb = R.build(class, seen.build)
						if sb and (not roles or roles[sb.role]) then build = seen.build end
					end
				end
				local caredOverride = D.memberCared[key]
				local cared = D.cared(key)
				if caredOverride ~= nil then cared = caredOverride end
				local relation = caredOverride == true and "Protected"
					or (caredOverride == false and "Ignored")
					or D.relation(key)
					or "Stranger"
				group[#group + 1] = {
					name = plain(name),
					key = key,
					class = class,
					level = unitLevel(unit),
					roles = roles,
					build = build,
					cared = cared,
					relation = relation,
				}
			end
		end
	end
	return group
end

local SHORT_BUILDS = {
	["Arms or Fury"] = "Arms / Fury",
	["Discipline or Holy"] = "Disc / Holy",
}

function D.shortSpec(profile)
	if not profile or not profile.class then return "?" end
	local builds = R.mainBuilds(profile)
	local total = #(R.BUILDS[profile.class] or {})
	if #builds == 0 or (#builds == total and total > 1) then return "Any" end
	if #builds == 2 and builds[1].key == "cat" and builds[2].key == "bear" then return "Feral (cat/bear)" end
	local names = {}
	for i, build in ipairs(builds) do
		names[i] = SHORT_BUILDS[build.name] or build.name
	end
	return table.concat(names, " / ")
end

local function remember(profile)
	if profile.key then D.seen[profile.key] = profile end
	return profile
end

-- Looks up a player from current unit frames, guild roster, or friend lists.
function D.lookupPlayer(key)
	if not key or key == "" then return nil end
	for _, unit in ipairs({ "target", "mouseover" }) do
		if UnitExists and UnitExists(unit) and (not UnitIsPlayer or UnitIsPlayer(unit)) then
			local name, realm = UnitName(unit)
			if D.key(name, realm) == key then
				local class = plain(select(2, UnitClass(unit)))
				if class then
					return remember({
						name = plain(name),
						key = key,
						class = class,
						level = unitLevel(unit) or unitLevel("player"),
						roles = unitRoles(unit),
						cared = D.cared(key),
					})
				end
			end
		end
	end
	if IsInGuild and IsInGuild() and GetNumGuildMembers then
		for i = 1, GetNumGuildMembers() or 0 do
			local name, _, _, level, _, _, _, _, _, _, class = GetGuildRosterInfo(i)
			class = plain(class)
			if class and D.key(name) == key then
				local plainName = plain(name)
				return remember({
					name = plainName and plainName:match("^[^-]+"),
					key = key,
					class = class,
					level = plain(level) or unitLevel("player"),
					cared = true,
				})
			end
		end
	end
	if C_FriendList and C_FriendList.GetNumFriends then
		for i = 1, C_FriendList.GetNumFriends() or 0 do
			local info = C_FriendList.GetFriendInfoByIndex(i)
			if info and D.key(info.name) == key then
				local class = resolveClassName(info.className)
				if class then
					local plainName = plain(info.name)
					return remember({
						name = plainName and plainName:match("^[^-]+"),
						key = key,
						class = class,
						level = plain(info.level) or unitLevel("player"),
						cared = true,
					})
				end
			end
		end
	end
	if BNGetNumFriends and C_BattleNet and C_BattleNet.GetFriendAccountInfo then
		for i = 1, BNGetNumFriends() or 0 do
			local accounts = C_BattleNet.GetFriendNumGameAccounts and C_BattleNet.GetFriendNumGameAccounts(i) or 0
			for j = 1, accounts do
				local game = C_BattleNet.GetFriendGameAccountInfo(i, j)
				if isWowBnetGame(game) and D.key(game.characterName, game.realmName) == key then
					local class = resolveClassName(game.className)
					if class then
						return remember({
							name = plain(game.characterName),
							key = key,
							class = class,
							level = plain(game.characterLevel) or plain(game.level) or unitLevel("player"),
							cared = true,
						})
					end
				end
			end
			local account = C_BattleNet.GetFriendAccountInfo(i)
			local game = account and account.gameAccountInfo
			if isWowBnetGame(game) and D.key(game.characterName, game.realmName) == key then
				local class = resolveClassName(game.className)
				if class then
					return remember({
						name = plain(game.characterName),
						key = key,
						class = class,
						level = plain(game.characterLevel) or plain(game.level) or unitLevel("player"),
						cared = true,
					})
				end
			end
		end
	end
end

-- Everyone in a group finder listing, as candidate profiles.
function D.resultCandidates(resultID)
	local candidates = {}
	local info = resultID and C_LFGList and C_LFGList.GetSearchResultInfo and C_LFGList.GetSearchResultInfo(resultID)
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
				local roles = { TANK = listed.tank or nil, HEALER = listed.healer or nil, DAMAGER = listed.dps or nil }
				local hintRoles, hintBuild = R.hints(plain(info.comment), class)
				profile.roles = next(roles) and roles or hintRoles
				if hintBuild then
					local b = R.build(class, hintBuild)
					if b and (not next(roles) or roles[b.role]) then profile.build = hintBuild end
				end
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

---------------------------------------------------------------------------
-- Group finder

local function ensureTooltip()
	if D.tooltip then return D.tooltip end
	local tip = CreateFrame("GameTooltip", "MittsOffTooltip", UIParent, "GameTooltipTemplate")
	if tip.SetClampedToScreen then tip:SetClampedToScreen(true) end
	if tip.HookScript then tip:HookScript("OnHide", D.restoreTooltipFonts) end
	D.tooltip = tip
	return tip
end

local function positionTooltip(owner)
	local tip = D.tooltip
	if not (tip and owner) then return end
	if tip.ClearAllPoints then tip:ClearAllPoints() end
	local bottom = owner.GetBottom and owner:GetBottom()
	local height = tip.GetHeight and tip:GetHeight()
	if bottom and height and bottom - height - 6 < 0 then
		tip:SetPoint("BOTTOMLEFT", owner, "TOPLEFT", 0, 2)
	else
		tip:SetPoint("TOPLEFT", owner, "BOTTOMLEFT", 0, -2)
	end
end

local function updateEntry(entry)
	if not entry then return end
	D.entries[entry] = true
	local _, top
	if MittsOffDB.finder and entry.resultID then
		_, top = D.check(D.resultCandidates(entry.resultID))
	end
	if not top then
		if entry.MittsOffBadge then entry.MittsOffBadge:Hide() end
		return
	end
	if not entry.MittsOffBadge then
		local badge = D.createBadge(entry, 26, 16)
		badge:SetPoint("RIGHT", entry, "RIGHT", -8, 0)
		if badge.SetFrameLevel and entry.GetFrameLevel then
			badge:SetFrameLevel((entry:GetFrameLevel() or 0) + 3)
		end
		entry.MittsOffBadge = badge
	end
	D.styleBadge(entry.MittsOffBadge, top)
	entry.MittsOffBadge:Show()
end

local function updateTooltip(owner, resultID)
	D.hoveredOwner, D.hoveredResultID = owner, resultID
	local found = MittsOffDB.finder and D.check(D.resultCandidates(resultID)) or {}
	if #found == 0 then
		if D.tooltip then D.tooltip:Hide() end
		return
	end
	local tip = ensureTooltip()
	tip:SetOwner(owner, "ANCHOR_NONE")
	if tip.ClearLines then tip:ClearLines() end
	if tip.SetMinimumWidth and owner.GetWidth then
		local width = owner:GetWidth()
		if width and width > 0 then tip:SetMinimumWidth(width) end
	end
	tip:AddLine("|cffffd100Mitts Off!|r")
	local shown = math.min(#found, 6)
	for i = 1, shown do
		D.addConflictTooltipLine(tip, found[i], false)
	end
	if #found > shown then
		tip:AddLine(("|cff999999+%d more|r"):format(#found - shown))
	end
	tip:Show()
	positionTooltip(owner)
end

local function browseControlLabel()
	if not MittsOffDB.finder then return "Mitts Off: Off" end
	return "Mitts Off: " .. D.shortSpec(D.me())
end

local function updateBrowseControl()
	local control = D.browseControl
	if not control then return end
	if control.GenerateMenu then control:GenerateMenu() end
	local text = browseControlLabel()
	if control.OverrideText then
		control:OverrideText(text)
	elseif control.SetText then
		control:SetText(text)
	end
end

local QUICK_TOGGLES = {
	{ "finder", "Show in Group Finder" },
	{ "offspec", "Hybrid offspec rolls" },
	{ "caredOnly", "Only you, friends and guildmates" },
	{ "unsure", "Unknown specs" },
	{ "accessories", "Weapons, cloaks and jewelry" },
}

local function attachBrowseControl()
	if D.browseControl or not LFGBrowseFrame then return end
	local control = CreateFrame("DropdownButton", "MittsOffBrowseControl", LFGBrowseFrame, "WowStyle1DropdownTemplate")
	if not control then return end
	D.browseControl = control
	control:SetWidth(182)
	control:SetPoint("BOTTOM", LFGBrowseFrame, "BOTTOM", 0, 17)
	if control.SetSelectionTranslator then
		control:SetSelectionTranslator(function() return browseControlLabel() end)
	end
	if control.SetupMenu then
		control:SetupMenu(function(_, root)
			local me = D.me()
			local detected = D.buildNames(R.mainBuilds({ class = me.class, tree = me.tree, roles = me.roles }))
			if root.CreateTitle then root:CreateTitle("Your spec") end
			root:CreateRadio("Automatic: " .. detected, function() return MittsOffCharDB.build == nil end, function()
				MittsOffCharDB.build = nil
				D.refreshAll()
			end)
			for _, option in ipairs(R.BUILDS[me.class] or {}) do
				root:CreateRadio(option.name, function() return MittsOffCharDB.build == option.key end, function()
					MittsOffCharDB.build = option.key
					D.refreshAll()
				end)
			end

			local group = D.group()
			if #group > 1 and root.CreateButton then
				if root.CreateDivider then root:CreateDivider() end
				if root.CreateTitle then root:CreateTitle("Your group") end
				local limit = math.min(#group, 9)
				for i = 2, limit do
					local member = group[i]
					local label = ("%s (%s)"):format(member.name or "?", D.shortSpec(member))
					local sub = root:CreateButton(label)
					if sub and sub.CreateRadio then
						sub:CreateRadio("Auto", function() return D.memberBuilds[member.key] == nil end, function()
							D.memberBuilds[member.key] = nil
							D.refreshAll()
						end)
						for _, option in ipairs(R.BUILDS[member.class] or {}) do
							sub:CreateRadio(option.name, function() return D.memberBuilds[member.key] == option.key end, function()
								D.memberBuilds[member.key] = option.key
								D.refreshAll()
							end)
						end
						if sub.CreateDivider then sub:CreateDivider() end
						if sub.CreateCheckbox then
							local key, baseCared = member.key, D.cared(member.key)
							local function isProtected()
								if D.memberCared[key] ~= nil then return D.memberCared[key] end
								return baseCared
							end
							sub:CreateCheckbox("Protect loot", isProtected, function()
								D.memberCared[key] = not isProtected()
								D.refreshAll()
							end)
						end
					end
				end
			end

			if root.CreateCheckbox then
				if root.CreateDivider then root:CreateDivider() end
				if root.CreateTitle then root:CreateTitle("Quick toggles") end
				for _, item in ipairs(QUICK_TOGGLES) do
					local key, text = item[1], item[2]
					root:CreateCheckbox(text, function() return MittsOffDB[key] and true or false end, function()
						D.set(key, not MittsOffDB[key])
					end)
				end
			end

			if root.CreateButton and D.openSettings then
				if root.CreateDivider then root:CreateDivider() end
				root:CreateButton("All settings...", function() D.openSettings() end)
			end
		end)
	end
	if control.HookScript then
		control:HookScript("OnEnter", function(self)
			if not GameTooltip then return end
			GameTooltip:SetOwner(self, "ANCHOR_TOP")
			GameTooltip:AddLine("|cffffd100Mitts Off!|r")
			local me = D.me()
			GameTooltip:AddLine("Spec: |cffffffff" .. D.buildNames(R.mainBuilds(me)) .. "|r", 0.9, 0.9, 0.9, true)
			local watched = 0
			for _, member in ipairs(D.group()) do
				if not MittsOffDB.caredOnly or member.isSelf or member.cared then watched = watched + 1 end
			end
			GameTooltip:AddLine(("Watching loot for %d %s"):format(watched, watched == 1 and "player" or "players"), 0.7, 0.7, 0.7, true)
			GameTooltip:AddLine("Click for spec and quick toggles.", 1, 0.82, 0, true)
			GameTooltip:Show()
		end)
		control:HookScript("OnLeave", function()
			if GameTooltip then GameTooltip:Hide() end
		end)
	end
	updateBrowseControl()
end

function D.refreshFinder()
	local updated = {}
	if LFGBrowseFrame and LFGBrowseFrame.ScrollBox and LFGBrowseFrame.ScrollBox.ForEachFrame then
		LFGBrowseFrame.ScrollBox:ForEachFrame(function(frame)
			if frame and frame.resultID then
				updated[frame] = true
				updateEntry(frame)
			end
		end)
	end
	for entry in pairs(D.entries) do
		if not updated[entry] and entry.resultID and (not entry.IsShown or entry:IsShown()) then
			updateEntry(entry)
		end
	end
	if D.tooltip and (not D.tooltip.IsShown or D.tooltip:IsShown()) and D.hoveredResultID then
		updateTooltip(D.hoveredOwner, D.hoveredResultID)
	end
	updateBrowseControl()
end

function D.refreshAll()
	D.refreshFinder()
	if D.panel and D.panel.built and (not D.panel.IsShown or D.panel:IsShown()) and D.refreshSettings then
		D.refreshSettings()
	end
	if D.checkPanel and D.checkPanel.built and (not D.checkPanel.IsShown or D.checkPanel:IsShown()) and D.refreshCheck then
		D.refreshCheck()
	end
end

local function hookGroupFinder()
	if D.hooked or not LFGBrowseSearchEntry_Update then return end
	D.hooked = true
	hooksecurefunc("LFGBrowseSearchEntry_Update", updateEntry)
	if LFGBrowseSearchEntryTooltip_UpdateAndShow and LFGBrowseSearchEntryTooltip then
		hooksecurefunc("LFGBrowseSearchEntryTooltip_UpdateAndShow", updateTooltip)
		if LFGBrowseSearchEntry_OnEnter then
			hooksecurefunc("LFGBrowseSearchEntry_OnEnter", function()
				if D.tooltip and (not D.tooltip.IsShown or D.tooltip:IsShown()) then
					positionTooltip(LFGBrowseSearchEntryTooltip)
				end
			end)
		end
		LFGBrowseSearchEntryTooltip:HookScript("OnHide", function()
			D.hoveredResultID = nil
			if D.tooltip then D.tooltip:Hide() end
		end)
	end
	attachBrowseControl()
end

---------------------------------------------------------------------------
-- Whispers and invites

local function isLeadingOpenGroup()
	if not (IsInGroup and IsInGroup()) then return false end
	if IsInRaid and IsInRaid() then return false end
	local count = GetNumGroupMembers and GetNumGroupMembers() or 0
	if count >= 5 then return false end
	if UnitIsGroupLeader and UnitIsGroupLeader("player") then return true end
	if UnitIsGroupAssistant and UnitIsGroupAssistant("player") then return true end
	return not UnitIsGroupLeader
end

local function shouldWarnWhisper()
	if MittsOffDB.whispers and C_LFGList and C_LFGList.HasActiveEntryInfo and C_LFGList.HasActiveEntryInfo() then
		return true
	end
	return MittsOffDB.groupWhispers and isLeadingOpenGroup() or false
end

local function handleWhisper(text, senderName, realm, class, level)
	local key = D.key(senderName, realm)
	if not key or not class then return end
	local plainName = plain(senderName)
	local roles, build = R.hints(plain(text), class)
	local known = D.seen[key]
	if known and known.class ~= class then known = nil end
	local mergedRoles = roles or (known and known.roles)
	local mergedBuild = build
	if not mergedBuild and known and known.build then
		local kb = R.build(class, known.build)
		if kb and (not roles or roles[kb.role]) then mergedBuild = known.build end
	end
	local profile = remember({
		name = plainName and plainName:match("^[^-]+") or D.className(class),
		key = key,
		class = class,
		level = (known and known.level) or level or unitLevel("player"),
		roles = mergedRoles,
		build = mergedBuild,
		cared = D.cared(key),
	})
	if not shouldWarnWhisper() then return end
	local found, top = D.check({ profile })
	if #found == 0 then return end
	local now = GetTime()
	local prev = D.whispered[key]
	if prev and (now - prev.time < WHISPER_QUIET_SECONDS) and (top <= prev.severity) then return end
	D.whispered[key] = { time = now, severity = top }
	report(found)
end

local function onWhisper(text, sender, guid)
	guid = plain(guid)
	if not guid then return end
	local class = plain(select(2, GetPlayerInfoByGUID(guid)))
	handleWhisper(text, sender, nil, class, nil)
end

local function onBnWhisper(text, bnSenderID)
	bnSenderID = plain(bnSenderID)
	if not (bnSenderID and C_BattleNet and C_BattleNet.GetAccountInfoByID) then return end
	local info = C_BattleNet.GetAccountInfoByID(bnSenderID)
	local game = info and info.gameAccountInfo
	if not isWowBnetGame(game) then return end
	local class = resolveClassName(game.className)
	handleWhisper(text, game.characterName, game.realmName, class, plain(game.characterLevel) or plain(game.level))
end

-- Any invite of someone seen in the finder, whispers, target, guild or friends warns.
local function onInvite(name)
	if not MittsOffDB.invites then return end
	local key = D.key(name)
	if not key then return end
	local profile = D.seen[key] or D.lookupPlayer(key)
	if profile then report((D.check({ profile }))) end
end

---------------------------------------------------------------------------
-- Settings and preview

function D.set(name, value)
	MittsOffDB[name] = value
	D.refreshAll()
end

function D.reset()
	for name, value in pairs(DEFAULTS) do
		MittsOffDB[name] = value
	end
	MittsOffCharDB.build = nil
	D.memberBuilds = {}
	D.memberCared = {}
	D.refreshAll()
end

-- Every spec of every class as a hypothetical invite into the current group,
-- for the settings panel: { class, build, single, conflict, conflicts }.
function D.preview()
	local rows = {}
	local level = unitLevel("player")
	for _, class in ipairs(D.CLASSES) do
		local builds = R.BUILDS[class]
		for _, build in ipairs(builds) do
			local found = D.check({ { name = D.className(class), class = class, level = level, build = build.key } })
			rows[#rows + 1] = { class = class, build = build, single = #builds == 1, conflict = found[1], conflicts = found }
		end
	end
	return rows
end

-- Conflicts a player of this class would bring into the group. Role is TANK,
-- HEALER, DAMAGER or nil for an unknown spec; build and level are optional.
function D.hypothetical(class, role, build, level)
	return D.check({ {
		name = D.className(class),
		class = class,
		level = level or unitLevel("player"),
		roles = role and { [role] = true } or nil,
		build = build,
	} })
end

function D.checkTarget()
	if not (UnitExists and UnitExists("target") and (not UnitIsPlayer or UnitIsPlayer("target"))) then
		return nil, "Target a player first."
	end
	if UnitIsUnit and UnitIsUnit("target", "player") then
		return nil, "Target another player."
	end
	local name, realm = UnitName("target")
	local class = plain(select(2, UnitClass("target")))
	local key = D.key(name, realm)
	if not class or not key then return nil, "Cannot read target." end
	local seen = D.seen[key]
	local profile = {
		name = plain(name) or D.className(class),
		key = key,
		class = class,
		level = unitLevel("target") or unitLevel("player"),
		roles = (seen and seen.class == class and seen.roles) or unitRoles("target"),
		build = seen and seen.class == class and seen.build or nil,
		cared = D.cared(key),
	}
	return D.check({ profile }), profile
end

-- The player's leading talent tree, in a sentence.
function D.treeText(verbose)
	local tree, treeName, spent = D.myTree()
	if tree then
		if verbose then return ("Most talent points: %s (%d), tree %d."):format(treeName or "?", spent, tree) end
		return ("Most talent points: %s (%d)."):format(treeName or "?", spent)
	end
	return "No single talent tree leads, so your party role decides."
end

---------------------------------------------------------------------------
-- Slash command

local TOGGLES = {
	strangers = { field = "caredOnly", on = "Ignoring conflicts between strangers", off = "Warning about conflicts between strangers too" },
	offspec = { field = "offspec", on = "Counting offspec rolls", off = "Ignoring offspec rolls" },
	whispers = { field = "whispers", on = "Checking whispers while listed", off = "Ignoring whispers while listed" },
	groupwhispers = { field = "groupWhispers", on = "Checking whispers while leading an open group", off = "Ignoring whispers outside the Group Finder" },
}

local function buildNames(builds)
	local names = {}
	for i, build in ipairs(builds) do
		names[i] = build.name
	end
	return table.concat(names, " or ")
end
D.buildNames = buildNames

local function status()
	local me = D.me()
	say(("You are gearing as %s%s."):format(buildNames(R.mainBuilds(me)), me.build and " (set by you)" or ""))
	say(D.treeText(true))
	local group = D.group()
	if #group > 1 then
		local parts = {}
		for i = 2, #group do
			local m = group[i]
			parts[#parts + 1] = ("%s (%s, %s)"):format(m.name or "?", D.shortSpec(m), m.relation)
		end
		say("Group: " .. table.concat(parts, "; ") .. ".")
	end
	for _, name in ipairs({ "strangers", "offspec", "whispers", "groupwhispers" }) do
		local toggle = TOGGLES[name]
		say(("/mittsoff %s: %s"):format(name, MittsOffDB[toggle.field] and toggle.on or toggle.off))
	end
	local keys = { "auto" }
	for _, build in ipairs(R.BUILDS[me.class] or {}) do
		keys[#keys + 1] = build.key
	end
	say("/mittsoff spec " .. table.concat(keys, " | "))
	say("/mittsoff check <class|target> [role|spec] [level]")
end

local ROLE_ARGS = { tank = "TANK", healer = "HEALER", heal = "HEALER", dps = "DAMAGER", dd = "DAMAGER", damage = "DAMAGER" }

local function checkSlash(arg1, arg2, arg3)
	if arg1 == "target" then
		local found, detail = D.checkTarget()
		if not found then
			say(detail)
		elseif #found == 0 then
			say(("No competition with %s."):format(detail.name))
		else
			report(found, 10)
		end
		return true
	end
	local class = D.resolveClass(arg1)
	if not class then
		if arg1 == "" and D.openSettings and D.openSettings("check") then return true end
		if arg1 ~= "" then say(("Unknown class: %s."):format(arg1)) end
		return arg1 ~= ""
	end
	local role, build, level
	for _, arg in ipairs({ arg2, arg3 }) do
		if arg and arg ~= "" then
			local num = tonumber(arg)
			if num and num >= 1 and num <= 60 then
				level = num
			elseif ROLE_ARGS[arg] then
				role = ROLE_ARGS[arg]
			elseif R.build(class, arg) then
				build = arg
			else
				local hRoles, hBuild = R.hints(arg, class)
				if hBuild then
					build = hBuild
				elseif hRoles and next(hRoles) then
					role = next(hRoles)
				else
					say(("Unknown role or spec for %s: %s."):format(D.className(class), arg))
					return true
				end
			end
		end
	end
	if role and not build then
		local valid = false
		for _, r in ipairs(R.classRoles(class)) do
			if r == role then valid = true end
		end
		if not valid then
			say(("%s cannot play %s."):format(D.className(class), role:lower()))
			return true
		end
	end
	local found = D.hypothetical(class, role, build, level)
	if #found == 0 then say("No competition.") end
	report(found, 10)
	return true
end

function D.slash(input)
	local command, arg1, arg2, arg3 = tostring(input or ""):lower():match("^%s*(%S*)%s*(%S*)%s*(%S*)%s*(%S*)")
	local toggle = TOGGLES[command]
	if toggle then
		D.set(toggle.field, not MittsOffDB[toggle.field])
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
		D.refreshAll()
		say(("You are gearing as %s."):format(buildNames(R.mainBuilds(D.me()))))
	elseif command == "check" then
		if not checkSlash(arg1, arg2, arg3) then status() end
	elseif command == "" and D.openSettings and D.openSettings() then
		return
	else
		status()
	end
end

---------------------------------------------------------------------------
-- Events

local EVENTS = {
	"ADDON_LOADED",
	"PLAYER_LOGIN",
	"CHAT_MSG_WHISPER",
	"CHAT_MSG_BN_WHISPER",
	"FRIENDLIST_UPDATE",
	"GUILD_ROSTER_UPDATE",
	"BN_FRIEND_INFO_CHANGED",
	"BN_FRIEND_ACCOUNT_ONLINE",
	"BN_FRIEND_ACCOUNT_OFFLINE",
	"PLAYER_GUILD_UPDATE",
	"GROUP_ROSTER_UPDATE",
	"PLAYER_ROLES_ASSIGNED",
	"TRAIT_CONFIG_UPDATED",
	"ACTIVE_TALENT_GROUP_CHANGED",
	"PLAYER_TALENT_UPDATE",
	"PLAYER_LEVEL_UP",
}

local frame = CreateFrame("Frame")
D.frame = frame
for _, event in ipairs(EVENTS) do
	pcall(frame.RegisterEvent, frame, event)
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
	elseif event == "CHAT_MSG_BN_WHISPER" then
		local text = ...
		onBnWhisper(text, (select(13, ...)))
	elseif event == "FRIENDLIST_UPDATE" or event == "GUILD_ROSTER_UPDATE" or event == "BN_FRIEND_INFO_CHANGED" or event == "BN_FRIEND_ACCOUNT_ONLINE" or event == "BN_FRIEND_ACCOUNT_OFFLINE" or event == "PLAYER_GUILD_UPDATE" then
		D.caredSet = nil
		D.refreshAll()
	else
		D.refreshAll()
	end
end)
