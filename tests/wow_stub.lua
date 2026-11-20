-- A small fake of the game API that Core.lua touches. Each call to the
-- returned function installs fresh globals and returns the world table that
-- tests edit: world.player, world.party, world.friends, world.guild,
-- world.results, world.listed, world.guids, world.chat, world.invited.
local CLASS_IDS = { WARRIOR = 1, PALADIN = 2, HUNTER = 3, ROGUE = 4, PRIEST = 5, SHAMAN = 7, MAGE = 8, WARLOCK = 9, DRUID = 11 }

-- Widgets accept any widget method: the ones tests read are recorded, Create*
-- methods return another widget, and other setters and getters do nothing.
-- Anything else is a plain field, so addon data stored on a widget reads back nil.
local newFrame
local WIDGET = {
	__index = function(_, method)
		if type(method) ~= "string" then return nil end
		if method:find("^Create") then return function() return newFrame() end end
		if method:find("^Set") or method:find("^Get") or method:find("^Enable") or method:find("^Add") then return function() end end
	end,
}

function newFrame()
	local f = { events = {}, scripts = {}, shown = false, menu = {} }
	function f:RegisterEvent(event) self.events[event] = true end
	function f:SetScript(name, fn) self.scripts[name] = fn end
	function f:HookScript(name, fn) self.scripts[name] = fn end
	function f:Fire(event, ...)
		if self.events[event] then self.scripts.OnEvent(self, event, ...) end
	end
	function f:SetTexture(path) self.path = path end
	function f:SetVertexColor(r, g, b) self.tint = ("%g,%g,%g"):format(r, g, b) end
	function f:Show() self.shown = true end
	function f:Hide() self.shown = false end
	function f:SetText(text) self.text = text end
	function f:GetText() return self.text end
	function f:SetChecked(checked) self.checked = checked end
	function f:GetChecked() return self.checked end
	-- Dropdowns: radios land in f.menu as { text, isSelected, select }.
	function f:SetupMenu(generator) self.generator = generator end
	function f:GenerateMenu()
		self.menu = {}
		self.generator(self, self)
	end
	function f:CreateRadio(text, isSelected, select) self.menu[#self.menu + 1] = { text = text, isSelected = isSelected, select = select } end
	return setmetatable(f, WIDGET)
end

return function()
	local world = {
		realm = "Stormrage",
		player = { name = "Me", class = "DRUID", level = 60, role = "NONE", points = { 0, 0, 0 } },
		party = {},
		raid = false,
		friends = {},
		guild = {},
		bnet = {},
		results = {},
		listed = false,
		guids = {},
		chat = {},
		invited = {},
		tooltip = { lines = {}, shown = false },
		now = 1000,
		newFrame = newFrame,
	}

	local function unit(token)
		if token == "player" then return world.player end
		local kind, index = token:match("^(%a+)(%d+)$")
		if (kind == "party" and not world.raid) or (kind == "raid" and world.raid) then return world.party[tonumber(index)] end
	end

	issecretvalue = nil
	GetNormalizedRealmName = function() return world.realm end
	GetTime = function() return world.now end
	UnitExists = function(token) return unit(token) ~= nil end
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
	IsInRaid = function() return world.raid end
	IsInGuild = function() return #world.guild > 0 end
	GetNumGuildMembers = function() return #world.guild end
	GetGuildRosterInfo = function(i) return world.guild[i] end
	BNGetNumFriends = function() return #world.bnet end
	GetPlayerInfoByGUID = function(guid)
		local class = world.guids[guid]
		if class then return class, class end
	end

	C_FriendList = {
		GetNumFriends = function() return #world.friends end,
		GetFriendInfoByIndex = function(i) return { name = world.friends[i] } end,
	}
	C_BattleNet = {
		GetFriendAccountInfo = function(i) return { gameAccountInfo = world.bnet[i] } end,
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

	DEFAULT_CHAT_FRAME = { AddMessage = function(_, text) world.chat[#world.chat + 1] = (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end }
	GameTooltip = {
		SetOwner = function(_, owner)
			world.tooltip.owner, world.tooltip.lines = owner, {}
		end,
		GetOwner = function() return world.tooltip.owner end,
		SetPoint = function() end,
		AddLine = function(_, text) world.tooltip.lines[#world.tooltip.lines + 1] = (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end,
		Show = function() world.tooltip.shown = true end,
		Hide = function() world.tooltip.shown, world.tooltip.owner = false, nil end,
	}
	CreateFrame = function() return newFrame() end
	SlashCmdList = {}
	RAID_CLASS_COLORS, LOCALIZED_CLASS_NAMES_MALE = nil, { DRUID = "Druid", ROGUE = "Rogue", WARRIOR = "Warrior" }
	Settings = {
		RegisterCanvasLayoutCategory = function(panel, name) return { panel = panel, name = name, GetID = function() return name end } end,
		RegisterAddOnCategory = function(category) world.category = category end,
		OpenToCategory = function(id)
			world.opened = id
			world.category.panel.scripts.OnShow(world.category.panel)
		end,
	}
	MittsOffDB, MittsOffCharDB = nil, nil

	-- The group finder is load on demand: world.loadGroupFinder() makes it exist.
	LFGBrowseSearchEntry_Update, LFGBrowseSearchEntryTooltip_UpdateAndShow, LFGBrowseSearchEntryTooltip = nil, nil, nil
	function world.loadGroupFinder()
		LFGBrowseSearchEntry_Update = function() end
		LFGBrowseSearchEntryTooltip_UpdateAndShow = function() end
		LFGBrowseSearchEntryTooltip = newFrame()
	end

	return world
end
