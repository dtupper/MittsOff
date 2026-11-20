-- Settings panel: the tunable rules on the left, and on the right every spec
-- of every class as a hypothetical invite, recolored live as rules change.

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

local checks, rows, dropdown = {}, {}, nil
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
	y = y - 40

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

function D.registerSettings()
	if D.category or not (Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory) then return end
	D.category = Settings.RegisterCanvasLayoutCategory(panel, TITLE)
	Settings.RegisterAddOnCategory(D.category)
end

-- Opens the panel. Returns false when the client cannot, so the caller can fall back to chat.
function D.openSettings()
	if not (D.category and Settings and Settings.OpenToCategory) then return false end
	Settings.OpenToCategory(D.category:GetID())
	return true
end
