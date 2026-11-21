-- Settings panel: the tunable rules on the left, and on the right every spec
-- of every class as a hypothetical invite plus the current group, updated live.
-- A subpage checks one class, spec, level or target, like /mittsoff check.

local _, ns = ...
local R, D = ns.Rules, ns.MittsOff
local TITLE = "Mitts Off!"

local SECTIONS = {
	{ title = "Who rolls on what", items = {
		{ "offspec", "Hybrids roll for other specs" },
		{ "shared", "Casters and healers share spell power" },
		{ "cloth", "All casters and healers roll on cloth" },
		{ "rollDown", "Heavier wearers roll on lighter armor" },
		{ "tankDamage", "Plate tanks roll on damage gear" },
	} },
	{ title = "What to mention", items = {
		{ "unsure", "Unknown specs" },
		{ "accessories", "Weapons, cloaks and jewelry" },
		{ "caredOnly", "Only you, friends and guildmates" },
	} },
	{ title = "Where to warn", items = {
		{ "finder", "Group Finder listings" },
		{ "whispers", "Whispers while listed" },
		{ "groupWhispers", "Whispers while leading an open group" },
		{ "invites", "Chat, when you invite someone" },
	} },
}
D.SECTIONS = SECTIONS

local TOOLTIPS = {
	offspec = "Counts hybrids rolling on |cffff8c1aother specs (OS)|r. Your own offspec is never guessed.",
	shared = "Treats |cffffffffspell power|r gear as shared between casters and healers.",
	cloth = "Includes leather, mail and plate casters rolling on |cffffffffcloth|r.",
	rollDown = "Counts heavier classes rolling on |cfffffffflighter physical or tank armor|r.",
	tankDamage = "Flags |cffffd100physical DPS|r competition for plate tanks picking up damage pieces.",
	unsure = "Shows |cffffd100maybe (?)|r warnings when a player's spec is unclear.",
	accessories = "Shows |cffffd100maybe (?)|r warnings for weapons, cloaks and jewelry across armor types.",
	caredOnly = "Reports only conflicts involving |cffffffffyou, friends or guildmates|r.",
	finder = "Shows conflict badges and tooltips on |cffffffffGroup Finder|r rows.",
	whispers = "Prints chat warnings for incoming whispers while |cfffffffflisted in Group Finder|r.",
	groupWhispers = "Prints chat warnings for whispers while |cffffffffleading a non-full party|r.",
	invites = "Repeats conflict warnings in chat when you |cffffffffinvite someone|r.",
}

-- Two columns that fit the settings window's canvas, about 630 wide.
local LEFT, LEFT_WIDTH = 16, 274
local RIGHT, RIGHT_WIDTH = 314, 304
local MAX_GROUP_ROWS = 4

local PREVIEW_NAMES = {
	["Arms or Fury"] = "Arms / Fury",
	["Discipline or Holy"] = "Disc / Holy",
}

local panel = CreateFrame("Frame")
panel.name = TITLE
panel:Hide()
D.panel = panel

local checks, rows, groupRows, soloText, moreGroupText = {}, {}, {}, nil, nil
local dropdown, talents
D.checks, D.rows, D.groupRows = checks, rows, groupRows

local function heading(text, x, y, width)
	local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	title:SetPoint("TOPLEFT", x, y)
	title:SetText(text)
	local line = panel:CreateTexture(nil, "ARTWORK")
	line:SetColorTexture(1, 0.82, 0, 0.25)
	line:SetSize(width, 1)
	line:SetPoint("TOPLEFT", x, y - 15)
	return y - 21
end

local function rowLabel(row)
	local class = D.className(row.class)
	if row.single then return class end
	return (PREVIEW_NAMES[row.build.name] or row.build.name) .. " " .. class
end

local function openMemberMenu(anchor, member)
	if MenuUtil and MenuUtil.CreateContextMenu then
		MenuUtil.CreateContextMenu(anchor, function(_, root)
			if root.CreateTitle then root:CreateTitle(member.name or "?") end
			root:CreateRadio("Auto", function() return D.memberBuilds[member.key] == nil end, function()
				D.memberBuilds[member.key] = nil
				D.refreshAll()
			end)
			for _, option in ipairs(R.BUILDS[member.class] or {}) do
				root:CreateRadio(option.name, function() return D.memberBuilds[member.key] == option.key end, function()
					D.memberBuilds[member.key] = option.key
					D.refreshAll()
				end)
			end
			if root.CreateDivider then root:CreateDivider() end
			if root.CreateCheckbox then
				local key, baseCared = member.key, D.cared(member.key)
				local function isProtected()
					if D.memberCared[key] ~= nil then return D.memberCared[key] end
					return baseCared
				end
				root:CreateCheckbox("Protect loot", isProtected, function()
					D.memberCared[key] = not isProtected()
					D.refreshAll()
				end)
			end
		end)
		return
	end
	local builds = R.BUILDS[member.class] or {}
	local current = D.memberBuilds[member.key]
	if not current then
		D.memberBuilds[member.key] = builds[1] and builds[1].key or nil
	else
		local nextBuild
		for i, b in ipairs(builds) do
			if b.key == current then
				nextBuild = builds[i + 1] and builds[i + 1].key or nil
				break
			end
		end
		D.memberBuilds[member.key] = nextBuild
	end
	D.refreshAll()
end

local function refreshGroup()
	if not soloText then return end
	local group = D.group()
	local others = #group - 1
	soloText:SetShown(others == 0)
	for i, row in ipairs(groupRows) do
		local member = group[i + 1]
		if member then
			row.member = member
			local color = RAID_CLASS_COLORS and RAID_CLASS_COLORS[member.class]
			local hex = D.classColorHex(member.class)
			local tag = member.relation and (" |cff888888(" .. member.relation .. ")|r") or ""
			row.name:SetText(("|c%s%s|r%s"):format(hex, member.name or "?", tag))
			if color then row.name:SetTextColor(1, 1, 1) end
			row.specText:SetText(D.shortSpec(member))
			row.specButton:Show()
			row:Show()
		else
			row.member = nil
			row:Hide()
		end
	end
	if others > MAX_GROUP_ROWS then
		moreGroupText:SetText(("...and %d more in group"):format(others - MAX_GROUP_ROWS))
		moreGroupText:Show()
	else
		moreGroupText:Hide()
	end
end

local function refresh()
	for key, check in pairs(checks) do
		check:SetChecked(MittsOffDB[key] and true or false)
	end
	if dropdown and dropdown.GenerateMenu then dropdown:GenerateMenu() end
	if talents then talents:SetText(D.treeText(false)) end
	for index, data in ipairs(D.preview()) do
		local row = rows[index]
		local conflict = data.conflict
		local color = RAID_CLASS_COLORS and RAID_CLASS_COLORS[data.class]
		row.conflict = conflict
		row.conflicts = data.conflicts
		row.name:SetText(rowLabel(data))
		row.name:SetTextColor(color and color.r or 1, color and color.g or 1, color and color.b or 1)
		row.name:SetAlpha(conflict and 1 or 0.45)
		row.detail:SetText(conflict and R.brief(conflict) or "")
		D.styleBadge(row.badge, conflict and conflict.severity or nil)
	end
	refreshGroup()
end
D.refreshSettings = refresh

local function addCheck(key, label, y)
	local check = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
	check:SetSize(22, 22)
	check:SetPoint("TOPLEFT", LEFT - 3, y)
	check:SetHitRectInsets(0, -(LEFT_WIDTH - 22), 0, 0)
	check:SetScript("OnClick", function(self)
		D.set(key, self:GetChecked() and true or false)
	end)
	check:SetScript("OnEnter", function(self)
		if not (GameTooltip and TOOLTIPS[key]) then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine(label, 1, 0.82, 0)
		GameTooltip:AddLine(TOOLTIPS[key], 0.9, 0.9, 0.9, true)
		GameTooltip:Show()
	end)
	check:SetScript("OnLeave", function()
		if GameTooltip then GameTooltip:Hide() end
	end)
	local text = check:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	text:SetPoint("LEFT", check, "RIGHT", 2, 0)
	text:SetWidth(LEFT_WIDTH - 24)
	text:SetJustifyH("LEFT")
	text:SetWordWrap(false)
	text:SetText(label)
	checks[key] = check
	return y - 22
end

local function addRow(index, y)
	local row = CreateFrame("Frame", nil, panel)
	row:SetSize(RIGHT_WIDTH, 19)
	row:SetPoint("TOPLEFT", RIGHT, y)
	row.badge = D.createBadge(row, 26, 15)
	row.badge:SetPoint("LEFT", 0, 0)
	row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	row.name:SetPoint("LEFT", 32, 0)
	row.detail = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	-- Fills what the name leaves and truncates rather than overlap it.
	row.detail:SetPoint("LEFT", row.name, "RIGHT", 6, 0)
	row.detail:SetPoint("RIGHT", 0, 0)
	row.detail:SetJustifyH("RIGHT")
	row.detail:SetWordWrap(false)
	row:EnableMouse(true)
	row:SetScript("OnEnter", function(self)
		if not self.conflicts or #self.conflicts == 0 then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine(self.name:GetText(), 1, 0.82, 0)
		for _, conflict in ipairs(self.conflicts) do
			D.addConflictTooltipLine(GameTooltip, conflict, true)
		end
		GameTooltip:Show()
	end)
	row:SetScript("OnLeave", function()
		D.restoreTooltipFonts()
		GameTooltip:Hide()
	end)
	rows[index] = row
	return y - 19
end

local function addGroupRow(index, y)
	local row = CreateFrame("Frame", nil, panel)
	row:SetSize(RIGHT_WIDTH, 19)
	row:SetPoint("TOPLEFT", RIGHT, y)
	row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.name:SetPoint("LEFT", 0, 0)
	row.name:SetWidth(175)
	row.name:SetJustifyH("LEFT")
	row.name:SetWordWrap(false)

	local btn = CreateFrame("Button", nil, row)
	btn:SetSize(124, 17)
	btn:SetPoint("RIGHT", 0, 0)
	local specText = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	specText:SetAllPoints(btn)
	specText:SetJustifyH("RIGHT")
	specText:SetWordWrap(false)
	specText:SetTextColor(0.5, 0.78, 1)
	btn:SetScript("OnClick", function(self)
		if row.member then openMemberMenu(self, row.member) end
	end)
	btn:SetScript("OnEnter", function(self)
		if not (GameTooltip and row.member) then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine(row.member.name or "?", 1, 0.82, 0)
		GameTooltip:AddLine("Click to set spec or loot protection.", 0.9, 0.9, 0.9, true)
		GameTooltip:Show()
	end)
	btn:SetScript("OnLeave", function()
		if GameTooltip then GameTooltip:Hide() end
	end)
	row.specButton = btn
	row.specText = specText
	groupRows[index] = row
	return y - 19
end

local function addLegend(y)
	local legend = CreateFrame("Frame", nil, panel)
	legend:SetSize(RIGHT_WIDTH, 18)
	legend:SetPoint("TOPLEFT", RIGHT, y)
	local items = {
		{ R.WILL, "Main", 0 },
		{ R.OFFSPEC, "Offspec", 82 },
		{ R.MIGHT, "Maybe", 174 },
	}
	for _, item in ipairs(items) do
		local badge = D.createBadge(legend, 24, 14)
		badge:SetPoint("LEFT", item[3], 0)
		D.styleBadge(badge, item[1])
		local text = legend:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		text:SetPoint("LEFT", badge, "RIGHT", 5, 0)
		text:SetText(item[2])
	end
	return y - 22
end

local function build()
	local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
	title:SetPoint("TOPLEFT", LEFT, -12)
	title:SetText(TITLE)

	local y = heading("Your spec", LEFT, -42, LEFT_WIDTH)
	dropdown = CreateFrame("DropdownButton", nil, panel, "WowStyle1DropdownTemplate")
	D.specDropdown = dropdown
	dropdown:SetWidth(230)
	dropdown:SetPoint("TOPLEFT", LEFT, y)
	dropdown:SetupMenu(function(_, root)
		local me = D.me()
		local detected = D.buildNames(R.mainBuilds({ class = me.class, tree = me.tree, roles = me.roles }))
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
	end)
	talents = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	D.talentsText = talents
	talents:SetPoint("TOPLEFT", LEFT, y - 29)
	talents:SetWidth(LEFT_WIDTH)
	talents:SetJustifyH("LEFT")
	y = y - 55

	for _, section in ipairs(SECTIONS) do
		y = heading(section.title, LEFT, y, LEFT_WIDTH)
		for _, item in ipairs(section.items) do
			y = addCheck(item[1], item[2], y)
		end
		y = y - 8
	end

	local reset = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	reset:SetSize(110, 22)
	reset:SetPoint("TOPLEFT", LEFT, y - 4)
	reset:SetText("Defaults")
	reset:SetScript("OnClick", function() D.reset() end)

	local rowY = heading("Who competes with your group", RIGHT, -42, RIGHT_WIDTH)
	rowY = addLegend(rowY)
	for index = 1, #D.preview() do
		rowY = addRow(index, rowY)
	end

	rowY = heading("Your group", RIGHT, rowY - 8, RIGHT_WIDTH)
	soloText = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	soloText:SetPoint("TOPLEFT", RIGHT, rowY)
	soloText:SetText("Solo")
	for index = 1, MAX_GROUP_ROWS do
		rowY = addGroupRow(index, rowY)
	end
	moreGroupText = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	moreGroupText:SetPoint("TOPLEFT", RIGHT, rowY)
	moreGroupText:Hide()
end

panel:SetScript("OnShow", function()
	if not panel.built then
		panel.built = true
		build()
	end
	refresh()
end)

---------------------------------------------------------------------------
-- Check a player: what one hypothetical invite would bring into the group,
-- the panel form of /mittsoff check.

local CHECK_TITLE = "Check a player"
local CHECK_LEVELS = {
	{ label = "Your level" },
	{ label = "Under 40", level = 35 },
	{ label = "40+", level = 60 },
}
local ROLE_LABELS = { TANK = "Tank", HEALER = "Healer", DAMAGER = "Damage" }
local CHECK_LINES, CHECK_WIDTH = 10, 590

local checkPanel = CreateFrame("Frame")
checkPanel.name = CHECK_TITLE
checkPanel:Hide()
D.checkPanel = checkPanel

local picked = { class = D.CLASSES[1] }
local lines, classMenu, specMenu, levelMenu, targetBtn, contextText = {}, nil, nil, nil, nil, nil
D.checkPicked, D.checkLines = picked, lines

local function specOptionsFor(class)
	local opts = { { label = "Any spec" } }
	local builds = R.BUILDS[class] or {}
	if #builds <= 1 then return opts end
	local byRole = {}
	for _, b in ipairs(builds) do
		byRole[b.role] = (byRole[b.role] or 0) + 1
	end
	for _, role in ipairs(R.classRoles(class)) do
		if byRole[role] > 1 then
			opts[#opts + 1] = { label = ROLE_LABELS[role] .. " (any)", role = role }
		end
	end
	for _, b in ipairs(builds) do
		opts[#opts + 1] = { label = b.name, build = b.key }
	end
	return opts
end

local function watchingSummary()
	local parts = {}
	for _, m in ipairs(D.group()) do
		if not MittsOffDB.caredOnly or m.isSelf or m.cared then
			local who = m.isSelf and "You" or (m.name or "?")
			parts[#parts + 1] = ("%s (%s)"):format(who, D.shortSpec(m))
		end
	end
	return "Watching: " .. table.concat(parts, ", ")
end

local function clearTargetCheck()
	picked.targetProfile = nil
	picked.targetError = nil
	picked.targetTitle = nil
end

local function refreshCheck()
	if classMenu and classMenu.GenerateMenu then classMenu:GenerateMenu() end
	if specMenu and specMenu.GenerateMenu then specMenu:GenerateMenu() end
	if levelMenu and levelMenu.GenerateMenu then levelMenu:GenerateMenu() end
	if contextText then
		contextText:SetText(picked.targetTitle and ("Target: " .. picked.targetTitle) or watchingSummary())
	end
	local found
	if picked.targetError then
		for i, line in ipairs(lines) do
			line:SetText(i == 1 and ("|cffffd100%s|r"):format(picked.targetError) or "")
		end
		return
	elseif picked.targetProfile then
		found = D.check({ picked.targetProfile })
	else
		found = D.hypothetical(picked.class, picked.role, picked.build, picked.level)
	end
	for i, line in ipairs(lines) do
		local conflict = found[i]
		line:SetText(conflict and D.formatConflict(conflict) or "")
	end
	if #found == 0 then lines[1]:SetText("No competition.") end
end
D.refreshCheck = refreshCheck

local function buildCheck()
	local title = checkPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
	title:SetPoint("TOPLEFT", LEFT, -12)
	title:SetText(CHECK_TITLE)

	classMenu = CreateFrame("DropdownButton", nil, checkPanel, "WowStyle1DropdownTemplate")
	D.checkClassMenu = classMenu
	classMenu:SetWidth(150)
	classMenu:SetPoint("TOPLEFT", LEFT, -52)
	classMenu:SetupMenu(function(_, root)
		for _, class in ipairs(D.CLASSES) do
			root:CreateRadio(D.className(class), function() return picked.class == class end, function()
				picked.class = class
				picked.role = nil
				picked.build = nil
				clearTargetCheck()
				refreshCheck()
			end)
		end
	end)

	specMenu = CreateFrame("DropdownButton", nil, checkPanel, "WowStyle1DropdownTemplate")
	D.checkSpecMenu = specMenu
	specMenu:SetWidth(180)
	specMenu:SetPoint("LEFT", classMenu, "RIGHT", 10, 0)
	specMenu:SetupMenu(function(_, root)
		for _, option in ipairs(specOptionsFor(picked.class)) do
			root:CreateRadio(option.label, function()
				return picked.role == option.role and picked.build == option.build
			end, function()
				picked.role = option.role
				picked.build = option.build
				clearTargetCheck()
				refreshCheck()
			end)
		end
	end)

	levelMenu = CreateFrame("DropdownButton", nil, checkPanel, "WowStyle1DropdownTemplate")
	D.checkLevelMenu = levelMenu
	levelMenu:SetWidth(120)
	levelMenu:SetPoint("LEFT", specMenu, "RIGHT", 10, 0)
	levelMenu:SetupMenu(function(_, root)
		for _, option in ipairs(CHECK_LEVELS) do
			root:CreateRadio(option.label, function() return picked.level == option.level end, function()
				picked.level = option.level
				clearTargetCheck()
				refreshCheck()
			end)
		end
	end)

	targetBtn = CreateFrame("Button", nil, checkPanel, "UIPanelButtonTemplate")
	D.checkTargetButton = targetBtn
	targetBtn:SetSize(105, 22)
	targetBtn:SetPoint("LEFT", levelMenu, "RIGHT", 10, 0)
	targetBtn:SetText("Check target")
	targetBtn:SetScript("OnClick", function()
		local found, detail = D.checkTarget()
		if not found then
			picked.targetProfile = nil
			picked.targetError = detail
			picked.targetTitle = nil
		else
			picked.targetProfile = detail
			picked.targetError = nil
			picked.targetTitle = ("%s (%s, level %d)"):format(detail.name, D.className(detail.class), detail.level or 0)
		end
		refreshCheck()
	end)

	contextText = checkPanel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	D.checkContextText = contextText
	contextText:SetPoint("TOPLEFT", LEFT, -86)
	contextText:SetWidth(CHECK_WIDTH)
	contextText:SetJustifyH("LEFT")

	local y = -108
	for i = 1, CHECK_LINES do
		local line = checkPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		line:SetWidth(CHECK_WIDTH)
		line:SetJustifyH("LEFT")
		if i == 1 then
			line:SetPoint("TOPLEFT", LEFT, y)
		else
			line:SetPoint("TOPLEFT", lines[i - 1], "BOTTOMLEFT", 0, -6)
		end
		lines[i] = line
	end
end

checkPanel:SetScript("OnShow", function()
	if not checkPanel.built then
		checkPanel.built = true
		buildCheck()
	end
	refreshCheck()
end)

---------------------------------------------------------------------------
-- Registration

function D.registerSettings()
	if D.category or not (Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory) then return end
	D.category = Settings.RegisterCanvasLayoutCategory(panel, TITLE)
	if Settings.RegisterCanvasLayoutSubcategory then
		D.checkCategory = Settings.RegisterCanvasLayoutSubcategory(D.category, checkPanel, CHECK_TITLE)
	end
	Settings.RegisterAddOnCategory(D.category)
end

-- Opens the panel, or the check page when page is "check". Returns false when
-- the client cannot, so the caller can fall back to chat.
function D.openSettings(page)
	local category = page == "check" and D.checkCategory or D.category
	if not (category and Settings and Settings.OpenToCategory) then return false end
	Settings.OpenToCategory(category:GetID())
	return true
end
