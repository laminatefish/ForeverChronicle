local _, ns = ...

-- /fc probe: reports what the client allows an addon to read right now,
-- including what sharing a backstory would need (nameplates, targets, addon
-- messages). Run it in the open world, in open-world combat, and inside a
-- dungeon. Results are printed and kept in ForeverChronicleDB.probes.
local Probe = {}
ns.Probe = Probe

local MAX_SAVED_PROBES = 20

local function Describe(value)
	if value == nil then
		return "nil"
	end
	if issecretvalue and issecretvalue(value) then
		return "<secret>"
	end
	if type(value) == "table" and value.GetXY then
		local ok, x, y = pcall(value.GetXY, value)
		if ok then
			return "(" .. Describe(x) .. ", " .. Describe(y) .. ")"
		end
		return "<vector, unreadable>"
	end
	return tostring(value)
end

local function Pack(...)
	return { n = select("#", ...), ... }
end

local function Try(fn)
	local results = Pack(pcall(fn))
	if not results[1] then
		return "error: " .. tostring(results[2])
	end
	local parts = {}
	for i = 2, results.n do
		parts[#parts + 1] = Describe(results[i])
	end
	return #parts > 0 and table.concat(parts, ", ") or "(no value)"
end

local function Exists(path)
	local value = _G
	for part in path:gmatch("[^%.]+") do
		value = type(value) == "table" and value[part] or nil
	end
	return value ~= nil and "yes" or "no"
end

-- Sharing a backstory with other players: can the addon tell whose nameplate
-- or tooltip it is, and can addon messages get through?

local COMMS_PREFIX = "ForeverChronicle" -- addon message prefixes are limited to 16 characters
local COMMS_TIMEOUT = 5
local MAX_PLATES_LISTED = 3

local function Readable(value)
	return ns.IsReadable(value) and "readable" or "hidden"
end

-- Who a unit is, and whether the addon may know it
local function DescribeUnit(unit)
	if not UnitExists(unit) then
		return "none"
	end
	local name, surname = UnitName(unit)
	return string.format("player=%s name=%s surname=%s full=%s (%s) guid=%s", Describe(UnitIsPlayer(unit)), Describe(name),
		Describe(surname), Describe(ns.GetFullName(unit)), Readable(ns.GetFullName(unit)), Readable(UnitGUID(unit)))
end

-- Checks every nameplate unit token rather than GetNamePlates(), which leaves
-- out forbidden plates (ones addons may not touch, like friendly players'
-- plates in instances)
local MAX_NAMEPLATE_UNITS = 40

local function DescribeNameplates()
	local count, players, listed = 0, 0, {}
	for i = 1, MAX_NAMEPLATE_UNITS do
		local unit = "nameplate" .. i
		if UnitExists(unit) then
			count = count + 1
			local isPlayer = UnitIsPlayer(unit)
			if isPlayer then
				players = players + 1
			end
			local plate = C_NamePlate.GetNamePlateForUnit(unit, true)
			local forbidden = plate and plate:IsForbidden()
			-- List players first; creatures only while there is room
			if #listed < MAX_PLATES_LISTED and (isPlayer or #listed < MAX_PLATES_LISTED - 1) then
				listed[#listed + 1] = string.format("[%s %s%s]", unit, DescribeUnit(unit), forbidden and " FORBIDDEN" or "")
			end
		end
	end
	return string.format("%d shown, %d players %s", count, players, table.concat(listed, " "))
end

local CHECKS = {
	{ "Client build", function() return GetBuildInfo() end },
	{ "Project ID", function() return WOW_PROJECT_ID end },
	{ "issecretvalue / canaccessvalue", function() return Exists("issecretvalue"), Exists("canaccessvalue") end },
	{ "In instance (type)", function() return IsInInstance() end },
	{ "In combat", function() return UnitAffectingCombat("player") end },
	{ "On flight path", function() return UnitOnTaxi("player") end },
	{ "Best map ID", function() return C_Map.GetBestMapForUnit("player") end },
	{ "Map position", function()
		return C_Map.GetPlayerMapPosition(C_Map.GetBestMapForUnit("player"), "player")
	end },
	{ "World position", function()
		local mapID = C_Map.GetBestMapForUnit("player")
		return C_Map.GetWorldPosFromMapPos(mapID, C_Map.GetPlayerMapPosition(mapID, "player"))
	end },
	{ "UnitPosition", function() return UnitPosition("player") end },
	{ "Recorder reads", function() return ns.Recorder:ReadPosition() end },
	{ "Level / max level", function()
		return UnitLevel("player"), GetMaxLevelForPlayerExpansion and GetMaxLevelForPlayerExpansion()
	end },
	{ "Combat log restricted", function()
		return C_CombatLog and C_CombatLog.IsCombatLogRestricted and C_CombatLog.IsCombatLogRestricted()
	end },
	{ "Chat messaging lockdown", function()
		return C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown()
	end },
	{ "Statistics API (GetStatistic)", function() return Exists("GetStatistic") end },
	{ "Statistic 60 (total deaths?)", function() return GetStatistic(60) end },
	{ "Statistic 1197 (total kills?)", function() return GetStatistic(1197) end },
	{ "Damage meter API", function() return Exists("C_DamageMeter") end },
	{ "Battle.net game data API", function() return Exists("C_BattleNet.SendGameData") end },
	{ "Nameplate API", function() return Exists("C_NamePlate.GetNamePlates"), Exists("C_NamePlate.GetNamePlateForUnit") end },
	{ "Nameplates on (all, friendly players, enemies)", function()
		return C_CVar.GetCVar("nameplateShowAll"), C_CVar.GetCVar("nameplateShowFriendlyPlayers"), C_CVar.GetCVar("nameplateShowEnemies")
	end },
	{ "Nameplates nearby", DescribeNameplates },
	{ "Target", function() return DescribeUnit("target") end },
	{ "Own name (first, surname, full)", function() return UnitName("player"), ns.GetFullName("player") end },
	{ "Surname separator (bytes)", function()
		local separator = Constants.CharacterNameSeparatorConsts.CHARACTERNAME_SURNAME_SEPARATOR
		return string.format("%q", separator), table.concat({ string.byte(separator, 1, -1) }, " ")
	end },
	{ "Surnames shown / NameUtil helper", function()
		return C_PlayerInfo.ShouldDisplaySurname and C_PlayerInfo.ShouldDisplaySurname(), Exists("NameUtil.GetUnmodifiedUnitFullName")
	end },
	{ "Tooltip unit hook (TooltipDataProcessor)", function() return Exists("TooltipDataProcessor.AddTooltipPostCall") end },
	{ "Addon message API", function()
		return Exists("C_ChatInfo.SendAddonMessage"), Exists("C_ChatInfo.RegisterAddonMessagePrefix")
	end },
}

-- Whispers an addon message to yourself and reports whether, and how fast,
-- it comes back. Also sends a full 255-character message, the most one can hold.
function Probe:TestComms(result)
	local function Report(line)
		table.insert(result.lines, line)
		print("  " .. line)
	end

	local name = ns.GetFullName("player")
	if not (C_ChatInfo and C_ChatInfo.SendAddonMessage and ns.IsReadable(name)) then
		Report("Addon message self-test: not possible here")
		return
	end
	Report("Addon message self-test: whispering " .. string.format("%q", name))
	C_ChatInfo.RegisterAddonMessagePrefix(COMMS_PREFIX)

	local token = tostring(GetTime())
	local long = token .. ":" .. string.rep("x", 255 - #token - 1)
	local pending = { short = token, long = long }
	local sentAt = GetTime()

	if not self.commsFrame then
		self.commsFrame = CreateFrame("Frame")
		self.commsFrame:RegisterEvent("CHAT_MSG_ADDON")
	end
	self.commsFrame:SetScript("OnEvent", function(_, _, prefix, message, channel, sender)
		if prefix ~= COMMS_PREFIX then
			return
		end
		for kind, text in pairs(pending) do
			if message == text then
				pending[kind] = nil
				Report(string.format("Addon message self-test (%s, %d chars): received after %.2fs via %s from %s",
					kind, #message, GetTime() - sentAt, Describe(channel), Describe(sender)))
			end
		end
	end)

	for kind, text in pairs(pending) do
		local ok, sendResult = pcall(C_ChatInfo.SendAddonMessage, COMMS_PREFIX, text, "WHISPER", name)
		Report(string.format("Addon message self-test (%s): send %s", kind, ok and ("returned " .. Describe(sendResult)) or ("error: " .. tostring(sendResult))))
	end

	C_Timer.After(COMMS_TIMEOUT, function()
		for kind in pairs(pending) do
			Report(string.format("Addon message self-test (%s): nothing received after %ds", kind, COMMS_TIMEOUT))
		end
		self.commsFrame:SetScript("OnEvent", nil)
		ns.Print("Message test done. /reload to write the results to the SavedVariables file.")
	end)
end

function Probe:Run()
	local result = { t = time(), lines = {} }
	ns.Print("Probe results:")
	for _, check in ipairs(CHECKS) do
		local line = check[1] .. ": " .. Try(check[2])
		table.insert(result.lines, line)
		print("  " .. line)
	end

	local probes = ns.db.probes or {}
	ns.db.probes = probes
	table.insert(probes, result)
	while #probes > MAX_SAVED_PROBES do
		table.remove(probes, 1)
	end
	ns.Print("Testing addon messages for %d seconds...", COMMS_TIMEOUT)
	self:TestComms(result)
end

-- /fc probe ui: records how the character panel is built, for fitting the
-- journal's tab in with the panel's own. Waits a few seconds first so the
-- panel can be opened (and a tab hovered) after typing the command.
-- Results are kept in ForeverChronicleDB.uiDump.

local UI_DUMP_DELAY = 5
local UI_DUMP_DEPTH = 6
local UI_DUMP_MAX_LINES = 4000

local function FrameLabel(frame)
	if not frame then
		return "nil"
	end
	local name = frame.GetName and frame:GetName()
	if name then
		return name
	end
	local parent = frame.GetParent and frame:GetParent()
	if parent then
		for key, value in pairs(parent) do
			if value == frame then
				return FrameLabel(parent) .. "." .. tostring(key)
			end
		end
	end
	return "<" .. tostring(frame:GetObjectType()) .. ">"
end

local function DescribePoints(region)
	local parts = {}
	for i = 1, region:GetNumPoints() do
		local point, relativeTo, relativePoint, x, y = region:GetPoint(i)
		parts[#parts + 1] = string.format("%s>%s:%s(%s,%s)", tostring(point), relativeTo and FrameLabel(relativeTo) or "screen",
			tostring(relativePoint), Describe(x), Describe(y))
	end
	return table.concat(parts, " ")
end

local function DescribeRegion(region)
	local parts = { region:GetObjectType() }
	if region.GetName and region:GetName() then
		parts[#parts + 1] = region:GetName()
	end
	if region.GetAtlas and region:GetAtlas() then
		parts[#parts + 1] = "atlas=" .. region:GetAtlas()
	elseif region.GetTexture and region:GetTexture() then
		parts[#parts + 1] = "tex=" .. tostring(region:GetTexture())
	end
	if region.GetText and region:GetText() then
		parts[#parts + 1] = "text=" .. Describe(region:GetText())
	end
	if region.GetDrawLayer then
		parts[#parts + 1] = "layer=" .. tostring(region:GetDrawLayer())
	end
	parts[#parts + 1] = string.format("%sx%s", Describe(region:GetWidth()), Describe(region:GetHeight()))
	parts[#parts + 1] = region:IsShown() and "shown" or "hidden"
	parts[#parts + 1] = DescribePoints(region)
	return table.concat(parts, " ")
end

local function DescribeFrame(frame)
	if frame:IsForbidden() then
		return "<forbidden>"
	end
	local parts = { frame:GetObjectType(), FrameLabel(frame) }
	parts[#parts + 1] = string.format("%sx%s", Describe(frame:GetWidth()), Describe(frame:GetHeight()))
	parts[#parts + 1] = frame:IsShown() and "shown" or "hidden"
	parts[#parts + 1] = "level=" .. tostring(frame:GetFrameLevel()) .. " strata=" .. tostring(frame:GetFrameStrata())
	if frame.IsProtected and frame:IsProtected() then
		parts[#parts + 1] = "PROTECTED"
	end
	if frame.GetID and frame:GetID() ~= 0 then
		parts[#parts + 1] = "id=" .. tostring(frame:GetID())
	end
	parts[#parts + 1] = DescribePoints(frame)
	-- Keys holding lists of frames, like a Tabs array
	for key, value in pairs(frame) do
		if type(value) == "table" and type(value[1]) == "table" and value[1].GetObjectType then
			parts[#parts + 1] = "list:" .. tostring(key) .. "[" .. #value .. "]"
		end
	end
	return table.concat(parts, " ")
end

local function DumpTree(lines, frame, depth, indent)
	if #lines >= UI_DUMP_MAX_LINES then
		return
	end
	local ok, line = pcall(DescribeFrame, frame)
	lines[#lines + 1] = indent .. (ok and line or "error: " .. tostring(line))
	if not ok or depth <= 0 or frame:IsForbidden() then
		return
	end
	for _, region in ipairs({ frame:GetRegions() }) do
		local rok, rline = pcall(DescribeRegion, region)
		lines[#lines + 1] = indent .. "  - " .. (rok and rline or "error: " .. tostring(rline))
	end
	for _, child in ipairs({ frame:GetChildren() }) do
		DumpTree(lines, child, depth - 1, indent .. "  ")
	end
end

local function IsAnchoredTo(frame, target)
	for i = 1, frame:GetNumPoints() do
		local _, relativeTo = frame:GetPoint(i)
		while relativeTo do
			if relativeTo == target then
				return true
			end
			relativeTo = relativeTo.GetParent and relativeTo:GetParent()
		end
	end
	return false
end

function Probe:DumpUI()
	ns.Print("Recording the interface in %d seconds. Open the character panel and hover one of its side tabs.", UI_DUMP_DELAY)
	C_Timer.After(UI_DUMP_DELAY, function()
		local lines = { "Build: " .. Try(function() return GetBuildInfo() end) }

		lines[#lines + 1] = "== Under the mouse, and its parents"
		local foci = GetMouseFoci and GetMouseFoci() or { GetMouseFocus and GetMouseFocus() }
		local focus = foci and foci[1]
		while focus do
			local ok, line = pcall(DescribeFrame, focus)
			lines[#lines + 1] = "  " .. (ok and line or "error: " .. tostring(line))
			focus = focus.GetParent and focus:GetParent()
		end

		lines[#lines + 1] = "== CharacterFrame"
		if CharacterFrame then
			DumpTree(lines, CharacterFrame, UI_DUMP_DEPTH, "")
		end

		lines[#lines + 1] = "== Other shown frames anchored to the character panel"
		for _, child in ipairs({ UIParent:GetChildren() }) do
			local ok, anchored = pcall(function()
				return child ~= CharacterFrame and not child:IsForbidden() and child:IsShown() and CharacterFrame and IsAnchoredTo(child, CharacterFrame)
			end)
			if ok and anchored then
				DumpTree(lines, child, UI_DUMP_DEPTH, "")
			end
		end

		ns.db.uiDump = { t = time(), lines = lines }
		ns.Print("Recorded %d lines. /reload to write them to the SavedVariables file.", #lines)
	end)
end
