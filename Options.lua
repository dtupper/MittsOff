-- Settings panel: the tunable rules on the left, and on the right every spec
-- of every class as a hypothetical invite, recolored live as rules change.
-- A subpage checks one class and role, like /mittsoff check.

local _, ns = ...
local R, D = ns.Rules, ns.MittsOff
local TITLE = "Mitts Off!"

local SECTIONS = {
	{ title = "Who rolls on what", items = {
		{ "offspec", "Hybrids roll for their other specs" },
		{ "shared", "Casters and healers share spell power gear" },
		{ "cloth", "Every caster and healer rolls on cloth" },
		{ "rollDown", "Heavier armor wearers roll on lighter armor" },
		{ "tankDamage", "Plate tanks roll on damage gear" },
	} },
	{ title = "What to mention", items = {
		{ "unsure", "Unknown specs" },
		{ "accessories", "Weapons, cloaks and jewelry" },
		{ "caredOnly", "Only you, friends and guildmates" },
	} },
	{ title = "Where to warn", items = {
		{ "finder", "Group finder listings" },
		{ "whispers", "Whispers while you are listed" },
		{ "invites", "Chat, when you invite someone" },
	} },
}
D.SECTIONS = SECTIONS

-- Two columns that fit the settings window's canvas, about 630 wide.
local LEFT, RIGHT, COLUMN = 16, 330, 290
local GRAY_DOT = "Interface\\COMMON\\Indicator-Gray"

local panel = CreateFrame("Frame")
panel.name = TITLE
panel:Hide()
D.panel = panel

local checks, rows, dropdown, talents = {}, {}, nil, nil
D.checks, D.rows = checks, rows

local function heading(text, x, y)
	local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	title:SetPoint("TOPLEFT", x, y)
	title:SetText(text)
	local line = panel:CreateTexture(nil, "ARTWORK")
	line:SetColorTexture(1, 0.82, 0, 0.25)
	line:SetSize(COLUMN, 1)
	line:SetPoint("TOPLEFT", x, y - 17)
	return y - 24
end

local function rowLabel(row)
	local class = LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[row.class] or row.class
	if row.single then return class end
	return row.build.name .. " " .. class
end

local function refresh()
	for key, check in pairs(checks) do
		check:SetChecked(MittsOffDB[key] and true or false)
	end
	if dropdown and dropdown.GenerateMenu then dropdown:GenerateMenu() end
	if talents then talents:SetText(D.treeText()) end
	for index, data in ipairs(D.preview()) do
		local row = rows[index]
		local conflict = data.conflict
		local color = RAID_CLASS_COLORS and RAID_CLASS_COLORS[data.class]
		row.conflict = conflict
		row.name:SetText(rowLabel(data))
		row.name:SetTextColor(color and color.r or 1, color and color.g or 1, color and color.b or 1)
		row.name:SetAlpha(conflict and 1 or 0.45)
		row.detail:SetText(conflict and R.brief(conflict) or "")
		if conflict then
			local icon = D.ICONS[conflict.severity]
			row.dot:SetTexture(icon[1])
			row.dot:SetVertexColor(icon[2], icon[3], icon[4])
			row.dot:SetAlpha(1)
		else
			row.dot:SetTexture(GRAY_DOT)
			row.dot:SetVertexColor(1, 1, 1)
			row.dot:SetAlpha(0.4)
		end
	end
end
D.refreshSettings = refresh

local function addCheck(key, label, y)
	local check = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
	check:SetSize(26, 26)
	check:SetPoint("TOPLEFT", LEFT - 4, y)
	-- The label is part of the click target.
	check:SetHitRectInsets(0, -(COLUMN - 26), 0, 0)
	check:SetScript("OnClick", function(self)
		D.set(key, self:GetChecked() and true or false)
		refresh()
	end)
	local text = check:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	text:SetPoint("LEFT", check, "RIGHT", 2, 0)
	text:SetText(label)
	checks[key] = check
	return y - 26
end

local function addRow(index, y)
	local row = CreateFrame("Frame", nil, panel)
	row:SetSize(COLUMN, 20)
	row:SetPoint("TOPLEFT", RIGHT, y)
	row.dot = row:CreateTexture(nil, "ARTWORK")
	row.dot:SetSize(14, 14)
	row.dot:SetPoint("LEFT", 0, 0)
	row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	row.name:SetPoint("LEFT", 20, 0)
	row.detail = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	-- Fills what the name leaves and truncates rather than overlap it.
	row.detail:SetPoint("LEFT", row.name, "RIGHT", 8, 0)
	row.detail:SetPoint("RIGHT", 0, 0)
	row.detail:SetJustifyH("RIGHT")
	row.detail:SetWordWrap(false)
	row:EnableMouse(true)
	row:SetScript("OnEnter", function(self)
		if not self.conflict then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		local c = D.COLORS[self.conflict.severity]
		GameTooltip:AddLine(("|c%s%s|r"):format(c, R.describe(self.conflict)), 1, 1, 1, true)
		GameTooltip:Show()
	end)
	row:SetScript("OnLeave", function() GameTooltip:Hide() end)
	rows[index] = row
	return y - 20
end

local function build()
	local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
	title:SetPoint("TOPLEFT", LEFT, -16)
	title:SetText(TITLE)

	local y = heading("Your spec", LEFT, -58)
	dropdown = CreateFrame("DropdownButton", nil, panel, "WowStyle1DropdownTemplate")
	D.specDropdown = dropdown
	dropdown:SetWidth(220)
	dropdown:SetPoint("TOPLEFT", LEFT, y)
	dropdown:SetupMenu(function(_, root)
		local me = D.me()
		local detected = D.buildNames(R.mainBuilds({ class = me.class, tree = me.tree, roles = me.roles }))
		root:CreateRadio("Automatic: " .. detected, function() return MittsOffCharDB.build == nil end, function()
			MittsOffCharDB.build = nil
			refresh()
		end)
		for _, option in ipairs(R.BUILDS[me.class] or {}) do
			root:CreateRadio(option.name, function() return MittsOffCharDB.build == option.key end, function()
				MittsOffCharDB.build = option.key
				refresh()
			end)
		end
	end)
	talents = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	D.talentsText = talents
	talents:SetPoint("TOPLEFT", LEFT, y - 32)
	talents:SetWidth(COLUMN)
	talents:SetJustifyH("LEFT")
	y = y - 58

	for _, section in ipairs(SECTIONS) do
		y = heading(section.title, LEFT, y)
		for _, item in ipairs(section.items) do
			y = addCheck(item[1], item[2], y)
		end
		y = y - 12
	end

	local reset = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	reset:SetSize(110, 22)
	reset:SetPoint("TOPLEFT", LEFT, y - 4)
	reset:SetText("Defaults")
	reset:SetScript("OnClick", function()
		D.reset()
		refresh()
	end)

	local rowY = heading("Who competes with your group", RIGHT, -58)
	for index = 1, #D.preview() do
		rowY = addRow(index, rowY)
	end
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
local CHECK_ROLES = {
	{ label = "Any role" },
	{ role = "TANK", label = "Tank" },
	{ role = "HEALER", label = "Healer" },
	{ role = "DAMAGER", label = "Damage" },
}
local CHECK_LINES, CHECK_WIDTH = 10, 590

local checkPanel = CreateFrame("Frame")
checkPanel.name = CHECK_TITLE
checkPanel:Hide()
D.checkPanel = checkPanel

local picked, lines, classMenu, roleMenu = { class = D.CLASSES[1] }, {}, nil, nil
D.checkPicked, D.checkLines = picked, lines

local function className(class)
	return LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[class] or class
end

local function refreshCheck()
	if classMenu and classMenu.GenerateMenu then classMenu:GenerateMenu() end
	if roleMenu and roleMenu.GenerateMenu then roleMenu:GenerateMenu() end
	local found = D.hypothetical(picked.class, picked.role)
	for i, line in ipairs(lines) do
		local conflict = found[i]
		line:SetText(conflict and ("|c%s%s|r"):format(D.COLORS[conflict.severity], R.describe(conflict)) or "")
	end
	if #found == 0 then lines[1]:SetText("No competition.") end
end
D.refreshCheck = refreshCheck

local function buildCheck()
	local title = checkPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
	title:SetPoint("TOPLEFT", LEFT, -16)
	title:SetText(CHECK_TITLE)

	classMenu = CreateFrame("DropdownButton", nil, checkPanel, "WowStyle1DropdownTemplate")
	D.checkClassMenu = classMenu
	classMenu:SetWidth(180)
	classMenu:SetPoint("TOPLEFT", LEFT, -58)
	classMenu:SetupMenu(function(_, root)
		for _, class in ipairs(D.CLASSES) do
			root:CreateRadio(className(class), function() return picked.class == class end, function()
				picked.class = class
				refreshCheck()
			end)
		end
	end)

	roleMenu = CreateFrame("DropdownButton", nil, checkPanel, "WowStyle1DropdownTemplate")
	D.checkRoleMenu = roleMenu
	roleMenu:SetWidth(140)
	roleMenu:SetPoint("LEFT", classMenu, "RIGHT", 12, 0)
	roleMenu:SetupMenu(function(_, root)
		for _, option in ipairs(CHECK_ROLES) do
			root:CreateRadio(option.label, function() return picked.role == option.role end, function()
				picked.role = option.role
				refreshCheck()
			end)
		end
	end)

	local y = -104
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
