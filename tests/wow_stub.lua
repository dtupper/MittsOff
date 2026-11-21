-- A small fake of the game API that Core.lua touches. Each call to the
-- returned function installs fresh globals and returns the world table that
-- tests edit: world.player, world.party, world.friends, world.guild,
-- world.results, world.listed, world.guids, world.chat, world.invited.
local CLASS_IDS = { WARRIOR = 1, PALADIN = 2, HUNTER = 3, ROGUE = 4, PRIEST = 5, SHAMAN = 7, MAGE = 8, WARLOCK = 9, DRUID = 11 }

local function stripColors(text)
	return (tostring(text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

-- Widgets accept any widget method: the ones tests read are recorded, Create*
-- methods return another widget, and other setters and getters do nothing.
-- Anything else is a plain field, so addon data stored on a widget reads back nil.
local newFrame
local WIDGET = {
	__index = function(_, method)
		if type(method) ~= "string" then return nil end
		if method:find("^Create") then return function() return newFrame() end end
		if method:find("^Set") or method:find("^Get") or method:find("^Enable") or method:find("^Add") or method:find("^Clear") then return function() end end
	end,
}

function newFrame(kind, name)
	local f = { kind = kind, frameName = name, events = {}, scripts = {}, shown = false, menu = {}, points = {}, lines = {}, doubleLines = {} }
	function f:GetName() return self.frameName end
	function f:RegisterEvent(event) self.events[event] = true end
	function f:SetScript(ev, fn) self.scripts[ev] = fn end
	function f:HookScript(ev, fn)
		local prev = self.scripts[ev]
		if prev then
			self.scripts[ev] = function(...)
				prev(...)
				fn(...)
			end
		else
			self.scripts[ev] = fn
		end
	end
	function f:Fire(event, ...)
		if self.events[event] then self.scripts.OnEvent(self, event, ...) end
	end
	function f:SetTexture(path) self.path = path end
	function f:SetVertexColor(r, g, b) self.tint = ("%g,%g,%g"):format(r, g, b) end
	function f:SetColorTexture(r, g, b, a) self.color = ("%g,%g,%g,%g"):format(r, g, b, a or 1) end
	function f:SetAlpha(a) self.alpha = a end
	function f:SetSize(w, h) self.width, self.height = w, h end
	function f:SetWidth(w) self.width = w end
	function f:SetHeight(h) self.height = h end
	function f:GetWidth() return self.width or 0 end
	function f:GetHeight()
		if self.height then return self.height end
		if self.kind == "GameTooltip" then return #self.lines * 16 + 16 end
		return 0
	end
	function f:GetBottom() return self.bottom end
	function f:ClearAllPoints() self.points = {} end
	function f:SetPoint(point, ...) self.points[#self.points + 1] = { point = point, args = { ... } } end
	function f:Show()
		self.shown = true
		if self.scripts.OnShow then self.scripts.OnShow(self) end
	end
	function f:Hide()
		self.shown = false
		self.owner = nil
		if self.scripts.OnHide then self.scripts.OnHide(self) end
	end
	function f:SetShown(v)
		if v then self:Show() else self:Hide() end
	end
	function f:IsShown() return self.shown end
	function f:SetText(text) self.text = text end
	function f:GetText() return self.text end
	function f:OverrideText(text) self.text = text end
	function f:SetChecked(checked) self.checked = checked end
	function f:GetChecked() return self.checked end

	-- Tooltip methods (used for GameTooltipTemplate frames like MittsOffTooltip).
	function f:SetOwner(owner, anchor)
		self.owner, self.anchor = owner, anchor
		self.lines, self.doubleLines = {}, {}
	end
	function f:GetOwner() return self.owner end
	function f:ClearLines() self.lines, self.doubleLines = {}, {} end
	function f:AddLine(text) self.lines[#self.lines + 1] = stripColors(text) end
	function f:AddDoubleLine(left, right)
		local l, r = stripColors(left), stripColors(right)
		self.doubleLines[#self.doubleLines + 1] = { l, r }
		self.lines[#self.lines + 1] = l .. "  " .. r
	end
	function f:NumLines() return #self.lines end
	function f:SetMinimumWidth(w) self.minWidth = w end
	function f:SetClampedToScreen(v) self.clamped = v end

	-- Dropdowns and context menus: items land in f.menu.
	function f:SetupMenu(generator) self.generator = generator end
	function f:GenerateMenu()
		self.menu = {}
		if self.generator then self.generator(self, self) end
	end
	function f:SetSelectionTranslator(fn) self.translator = fn end
	function f:CreateTitle(text)
		local item = { kind = "title", text = text }
		self.menu[#self.menu + 1] = item
		return item
	end
	function f:CreateDivider()
		local item = { kind = "divider" }
		self.menu[#self.menu + 1] = item
		return item
	end
	function f:CreateRadio(text, isSelected, select)
		local item = { kind = "radio", text = text, isSelected = isSelected, select = select }
		self.menu[#self.menu + 1] = item
		return item
	end
	function f:CreateCheckbox(text, isChecked, toggle)
		local item = { kind = "checkbox", text = text, isSelected = isChecked, select = toggle }
		self.menu[#self.menu + 1] = item
		return item
	end
	function f:CreateButton(text, onClick)
		local sub = newFrame("MenuButton")
		sub.kind = "button"
		sub.text = text
		sub.select = onClick
		self.menu[#self.menu + 1] = sub
		return sub
	end

	return setmetatable(f, WIDGET)
end

return function()
	local world = {
		realm = "Stormrage",
		player = { name = "Me", class = "DRUID", level = 60, role = "NONE", points = { 0, 0, 0 }, isLeader = false },
		party = {},
		raid = false,
		target = nil,
		mouseover = nil,
		friends = {},
		guild = {},
		bnet = {},
		bnetAccounts = {},
		results = {},
		listed = false,
		guids = {},
		chat = {},
		invited = {},
		browseFrames = {},
		tooltip = { lines = {}, doubleLines = {}, shown = false },
		now = 1000,
		newFrame = function(kind, name) return newFrame(kind, name) end,
	}

	local function unit(token)
		if token == "player" then return world.player end
		if token == "target" then return world.target end
		if token == "mouseover" then return world.mouseover end
		local kind, index = token:match("^(%a+)(%d+)$")
		if (kind == "party" and not world.raid) or (kind == "raid" and world.raid) then return world.party[tonumber(index)] end
	end

	issecretvalue = nil
	BNET_CLIENT_WOW = "WoW"
	GetNormalizedRealmName = function() return world.realm end
	GetTime = function() return world.now end
	UnitExists = function(token) return unit(token) ~= nil end
	UnitIsPlayer = function(token)
		local u = unit(token)
		return u ~= nil and u.isPlayer ~= false
	end
	UnitIsUnit = function(a, b) return unit(a) ~= nil and unit(a) == unit(b) end
	UnitName = function(token)
		local u = unit(token)
		if u then return u.name, u.realm end
	end
	UnitClass = function(token)
		local u = unit(token)
		if u then return u.class, u.class, CLASS_IDS[u.class] end
	end
	UnitLevel = function(token) return unit(token) and unit(token).level or 0 end
	UnitGroupRolesAssigned = function(token) return unit(token) and unit(token).role or "NONE" end
	GetNumGroupMembers = function() return #world.party > 0 and #world.party + (world.raid and 0 or 1) or 0 end
	IsInGroup = function() return #world.party > 0 end
	IsInRaid = function() return world.raid end
	UnitIsGroupLeader = function(token)
		local u = unit(token)
		return u and u.isLeader == true or false
	end
	UnitIsGroupAssistant = function(token)
		local u = unit(token)
		return u and u.isAssistant == true or false
	end
	IsInGuild = function() return #world.guild > 0 end
	GetNumGuildMembers = function() return #world.guild end
	GetGuildRosterInfo = function(i)
		local g = world.guild[i]
		if type(g) == "table" then
			return g.name, g.rank, g.rankIndex, g.level, g.class, g.zone, g.note, g.officernote, g.online, g.status, g.classFileName or g.class
		end
		return g
	end
	BNGetNumFriends = function() return #world.bnet end
	GetPlayerInfoByGUID = function(guid)
		local class = world.guids[guid]
		if class then return class, class end
	end

	C_FriendList = {
		GetNumFriends = function() return #world.friends end,
		GetFriendInfoByIndex = function(i)
			local f = world.friends[i]
			if type(f) == "table" then return f end
			return { name = f }
		end,
	}
	C_BattleNet = {
		GetFriendAccountInfo = function(i) return { gameAccountInfo = world.bnet[i] } end,
		GetAccountInfoByID = function(id)
			local g = world.bnetAccounts[id]
			return g and { gameAccountInfo = g } or nil
		end,
	}
	C_GuildInfo = { GuildRoster = function() end }

	-- Three talent groups per class. Like the client, they come back out of
	-- order and their IDs do not follow pane order: world.treeGroups[n] is the
	-- group ID of the nth tree in the talent pane.
	world.treeGroups = { 9002, 9003, 9001 }
	world.treeNames = { "First", "Second", "Third" }
	C_ClassTalents = { GetActiveConfigID = function() return 77 end }
	C_Traits = {
		GetGroupDisplayInfoByTreeID = function()
			local out = {}
			for _, tree in ipairs({ 3, 1, 2 }) do
				out[#out + 1] = { groupID = world.treeGroups[tree], orderIndex = tree * 10, displayName = world.treeNames[tree] }
			end
			return out
		end,
		GetGroupCurrencyInfo = function()
			local out = {}
			for tree, spent in ipairs(world.player.points) do
				if spent > 0 then out[#out + 1] = { traitNodeGroupID = world.treeGroups[tree], currencyInfos = { { spent = spent } } } end
			end
			return out
		end,
	}

	C_LFGList = {
		HasActiveEntryInfo = function() return world.listed end,
		GetSearchResultInfo = function(id)
			local result = world.results[id]
			if not result then return nil end
			return { numMembers = #result.members, hasSelf = result.hasSelf or false, isDelisted = result.isDelisted or false, comment = result.comment or "", leaderName = result.members[1].name }
		end,
		GetSearchResultPlayerInfo = function(id, i)
			local m = world.results[id] and world.results[id].members[i]
			if not m then return nil end
			local roles = m.roles or {}
			return { name = m.name, classFilename = m.class, level = m.level or 60, assignedRole = m.role or "NONE", lfgRoles = { tank = roles.tank or false, healer = roles.healer or false, dps = roles.dps or false }, isLeader = i == 1 }
		end,
	}
	C_PartyInfo = { InviteUnit = function(name) world.invited[#world.invited + 1] = name end }

	hooksecurefunc = function(a, b, c)
		local owner, name, hook = _G, a, b
		if type(a) == "table" then owner, name, hook = a, b, c end
		local original = owner[name]
		owner[name] = function(...)
			local results = table.pack(original(...))
			hook(...)
			return table.unpack(results, 1, results.n)
		end
	end

	DEFAULT_CHAT_FRAME = { AddMessage = function(_, text) world.chat[#world.chat + 1] = stripColors(text) end }
	GameTooltip = {
		SetOwner = function(_, owner)
			world.tooltip.owner, world.tooltip.lines, world.tooltip.doubleLines = owner, {}, {}
		end,
		GetOwner = function() return world.tooltip.owner end,
		SetPoint = function() end,
		AddLine = function(_, text) world.tooltip.lines[#world.tooltip.lines + 1] = stripColors(text) end,
		AddDoubleLine = function(_, left, right)
			local l, r = stripColors(left), stripColors(right)
			world.tooltip.doubleLines[#world.tooltip.doubleLines + 1] = { l, r }
			world.tooltip.lines[#world.tooltip.lines + 1] = l .. "  " .. r
		end,
		Show = function() world.tooltip.shown = true end,
		Hide = function() world.tooltip.shown, world.tooltip.owner = false, nil end,
	}
	CreateFrame = function(kind, name)
		local f = newFrame(kind, name)
		if name then _G[name] = f end
		return f
	end
	MenuUtil = {
		CreateContextMenu = function(owner, generator)
			local root = newFrame("Menu")
			generator(owner, root)
			world.contextMenu = root
			return root
		end,
	}
	SlashCmdList = {}
	RAID_CLASS_COLORS, LOCALIZED_CLASS_NAMES_MALE, LOCALIZED_CLASS_NAMES_FEMALE = nil, { DRUID = "Druid", ROGUE = "Rogue", WARRIOR = "Warrior" }, nil
	-- Categories are keyed by name; opening one shows its panel.
	world.categories = {}
	local function category(panel, name)
		world.categories[name] = { panel = panel, name = name, GetID = function() return name end }
		return world.categories[name]
	end
	Settings = {
		RegisterCanvasLayoutCategory = category,
		RegisterCanvasLayoutSubcategory = function(parent, panel, name)
			local sub = category(panel, name)
			sub.parent = parent
			return sub
		end,
		RegisterAddOnCategory = function(added) world.category = added end,
		OpenToCategory = function(id)
			if world.opened and world.categories[world.opened] then
				world.categories[world.opened].panel:Hide()
			end
			world.opened = id
			local panel = world.categories[id].panel
			panel:Show()
		end,
	}
	MittsOffDB, MittsOffCharDB = nil, nil

	-- The group finder is load on demand: world.loadGroupFinder() makes it exist.
	LFGBrowseSearchEntry_Update, LFGBrowseSearchEntry_OnEnter, LFGBrowseSearchEntryTooltip_UpdateAndShow, LFGBrowseSearchEntryTooltip, LFGBrowseFrame = nil, nil, nil, nil, nil
	function world.loadGroupFinder()
		LFGBrowseSearchEntry_Update = function(entry)
			if entry and entry.Show then entry:Show() end
			if entry then world.browseFrames[entry] = true end
		end
		LFGBrowseSearchEntry_OnEnter = function(entry)
			LFGBrowseSearchEntryTooltip_UpdateAndShow(LFGBrowseSearchEntryTooltip, entry.resultID)
			LFGBrowseSearchEntryTooltip:SetPoint("TOPLEFT", entry, "TOPRIGHT", 8, 38)
		end
		LFGBrowseSearchEntryTooltip_UpdateAndShow = function()
			LFGBrowseSearchEntryTooltip:Show()
		end
		LFGBrowseSearchEntryTooltip = newFrame("Frame", "LFGBrowseSearchEntryTooltip")
		LFGBrowseFrame = newFrame("Frame", "LFGBrowseFrame")
		LFGBrowseFrame.ScrollBox = {
			ForEachFrame = function(_, fn)
				for frame in pairs(world.browseFrames) do
					fn(frame)
				end
			end,
		}
	end

	return world
end
