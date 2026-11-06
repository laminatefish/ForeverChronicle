local _, ns = ...

-- The journey's notable moments: deaths, level-ups, discoveries, dungeons
-- and the player's own notes. Each is pinned to where it happened.
local Chronicle = {}
ns.Chronicle = Chronicle

Chronicle.ICONS = {
	begin = "Interface\\Icons\\Ability_Townwatch",
	death = "Interface\\TargetingFrame\\UI-TargetingFrame-Skull",
	level = "Interface\\Icons\\Spell_Holy_InnerFire",
	zone = "Interface\\Icons\\INV_Misc_Map_01",
	dungeon = "Interface\\Icons\\INV_Misc_Key_03",
	note = "Interface\\Icons\\INV_Misc_Note_01",
}

local UI_MAP_TYPE_ZONE = Enum and Enum.UIMapType and Enum.UIMapType.Zone or 3

-- UnitLevel lags behind PLAYER_LEVEL_UP, so anything redrawn in response to
-- a level-up would show the old level; the newest level-up event never does.
function Chronicle:GetLevel()
	local level = UnitLevel("player")
	local events = ns.char.events
	for i = #events, 1, -1 do
		if events[i].kind == "level" then
			return math.max(level, events[i].level)
		end
	end
	return level
end

function Chronicle:Add(kind, fields)
	local e = fields or {}
	e.kind = kind
	e.t = time()
	e.level = e.level or self:GetLevel()
	e.zone = e.zone or GetZoneText()
	e.subzone = e.subzone or GetSubZoneText()

	local c, x, y, mapID = ns.Recorder:ReadPosition()
	if not c then
		c, x, y, mapID = ns.Recorder:GetLastKnownPosition()
		e.approximate = c and true or nil
	end
	e.c, e.x, e.y, e.mapID = c, x, y, mapID

	table.insert(ns.char.events, e)
	ns.Fire("EVENT_ADDED", e)
	return e
end

function Chronicle:AddNote(text)
	return self:Add("note", { text = text })
end

-- Finds the zone-level map for the player, skipping caves and other
-- sub-maps, so "discovered" means a whole zone.
local function GetCurrentZoneMap()
	local mapID = C_Map.GetBestMapForUnit("player")
	if not ns.IsReadable(mapID) then
		return
	end
	local info = C_Map.GetMapInfo(mapID)
	while info and info.mapType > UI_MAP_TYPE_ZONE and info.parentMapID and info.parentMapID ~= 0 do
		info = C_Map.GetMapInfo(info.parentMapID)
	end
	if info and info.mapType == UI_MAP_TYPE_ZONE then
		return info.mapID, info.name
	end
end

function Chronicle:CheckZoneDiscovery()
	if IsInInstance() then
		return
	end
	local mapID, name = GetCurrentZoneMap()
	if mapID and not ns.char.zones[mapID] then
		ns.char.zones[mapID] = time()
		self:Add("zone", { zone = name })
	end
end

ns.RegisterEvent("PLAYER_LOGIN", function()
	-- Positions aren't reliable until shortly after login
	C_Timer.After(3, function()
		if ns.isNewCharacter then
			Chronicle:Add("begin")
			ns.isNewCharacter = nil
		end
		Chronicle:CheckZoneDiscovery()
	end)
end)

ns.RegisterEvent("PLAYER_DEAD", function()
	ns.char.stats.deaths = ns.char.stats.deaths + 1
	Chronicle:Add("death")
end)

ns.RegisterEvent("PLAYER_LEVEL_UP", function(newLevel)
	-- UnitLevel hasn't updated yet when this fires
	Chronicle:Add("level", { level = newLevel })
end)

ns.RegisterEvent("ZONE_CHANGED_NEW_AREA", function()
	Chronicle:CheckZoneDiscovery()
end)

ns.RegisterEvent("PLAYER_ENTERING_WORLD", function(isInitialLogin, isReloadingUi)
	if isInitialLogin or isReloadingUi then
		return
	end
	local inInstance, instanceType = IsInInstance()
	if inInstance and (instanceType == "party" or instanceType == "raid") then
		Chronicle:Add("dungeon", { zone = GetInstanceInfo(), subzone = "" })
	end
end)

-- Text for tooltips and the journal

local function Place(e)
	if e.subzone and e.subzone ~= "" and e.subzone ~= e.zone then
		return e.subzone .. ", " .. (e.zone or "")
	end
	return e.zone or "unknown lands"
end

local TITLES = {
	begin = function(e) return "The journey began in " .. Place(e) end,
	death = function(e) return "Fell in " .. Place(e) end,
	level = function(e) return "Reached level " .. e.level end,
	zone = function(e) return "Discovered " .. (e.zone or "a new land") end,
	dungeon = function(e) return "Entered " .. (e.zone or "a dungeon") end,
	note = function(e) return "Journal entry, " .. Place(e) end,
}

function Chronicle:GetJourneyDay(t)
	return math.floor((t - ns.char.created) / 86400) + 1
end

-- Returns title, detail line
function Chronicle:Describe(e)
	local title = (TITLES[e.kind] or Place)(e)
	local detail = string.format("Level %d · Day %d · %s", e.level or 0, self:GetJourneyDay(e.t), date("%d %b %Y, %H:%M", e.t))
	return title, detail
end

function Chronicle:ShowTooltip(owner, e)
	if not e then
		return
	end
	local title, detail = self:Describe(e)
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	GameTooltip:SetText(title, 1, 0.82, 0)
	GameTooltip:AddLine(detail, 0.8, 0.8, 0.8)
	if e.kind == "level" and e.zone then
		GameTooltip:AddLine(Place(e), 0.8, 0.8, 0.8)
	end
	if e.text then
		GameTooltip:AddLine(e.text, 1, 1, 1, true)
	end
	if e.approximate then
		GameTooltip:AddLine("Shown at the last known outdoor position", 0.6, 0.6, 0.6)
	end
	GameTooltip:Show()
end

-- Deeds and records

function Chronicle:GetRecords()
	local char = ns.char
	local level = self:GetLevel()
	local records = {
		level = level,
		levelsGained = level - (char.startLevel or level),
		deaths = char.stats.deaths,
		miles = char.stats.distance / 1760,
		zones = 0,
		days = self:GetJourneyDay(time()),
		points = 0,
	}

	for _ in pairs(char.zones) do
		records.zones = records.zones + 1
	end
	for _, seg in ipairs(char.segments) do
		records.points = records.points + #seg.x
	end

	-- Most dangerous place, and most levels gained without dying
	local deathsByPlace = {}
	local previousLevel = char.startLevel or level
	local bestStreak = 0
	for _, e in ipairs(char.events) do
		if e.kind == "death" then
			local place = e.zone or "unknown lands"
			deathsByPlace[place] = (deathsByPlace[place] or 0) + 1
			bestStreak = math.max(bestStreak, e.level - previousLevel)
			previousLevel = e.level
		end
	end
	records.levelsWithoutDying = math.max(bestStreak, level - previousLevel)

	local worstCount = 0
	for place, count in pairs(deathsByPlace) do
		if count > worstCount then
			records.deadliestPlace, worstCount = place, count
		end
	end
	records.deadliestCount = worstCount

	return records
end
