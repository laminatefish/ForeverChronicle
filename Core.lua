local addonName, ns = ...

ns.name = addonName
ns.title = "Forever Chronicle"

local DEFAULT_SETTINGS = {
	recording = true,
	showRoute = true,
	showDeaths = true,
	showLevels = true,
	showDungeons = true,
	showNotes = true,
	shareBackstory = false,
	shareJourney = false,
}

-- Per-character data. Saved per character by the client, so it never needs a
-- Name-Realm key (Forever has no realms).
local function NewCharacterData()
	return {
		schema = 1,
		created = time(),
		backstory = "",
		backstoryEdited = nil, -- when the backstory last changed; tells readers their copy is stale
		segments = {}, -- route: { c = continentID, kind = "ground"|"taxi"|"teleport", level, t0, t1, x = {}, y = {} }
		events = {},   -- { kind, t, level, zone, subzone, c, x, y, mapID, approximate, text }
		zones = {},    -- [uiMapID] = first visit time
		stats = { deaths = 0, distance = 0 },
	}
end

function ns.Print(fmt, ...)
	print("|cffd4af37" .. ns.title .. ":|r " .. string.format(fmt, ...))
end

-- Forever characters have a first name and a surname: UnitName returns them
-- as its two values (where other clients return name and realm), and the
-- player's real name joins them with the client's surname separator. Whispers,
-- addon messages included, need that full name; the first name alone finds
-- nobody. NameUtil is Blizzard's own helper for this.
function ns.GetFullName(unit)
	if NameUtil and NameUtil.GetUnmodifiedUnitFullName then
		return NameUtil.GetUnmodifiedUnitFullName(unit)
	end
	return (UnitName(unit))
end

-- The name as the game shows it, for the journal
function ns.GetDisplayName(unit)
	if NameUtil and NameUtil.FormatUnitNameForDisplay then
		return NameUtil.FormatUnitNameForDisplay(unit)
	end
	return (UnitName(unit))
end

-- With the controller UI on, Blizzard menus, the colour picker and UI panels
-- register with the gamepad frame controls manager as they open. Opened from
-- addon code, that leaves its binding state tainted, and the next protected
-- gamepad call (SetPreferredGamepadInteractTarget) is blocked. Check this
-- before opening any of them.
function ns.IsGamepadUI()
	return InputUtil and InputUtil.IsGamepadUIEnabled and InputUtil.IsGamepadUIEnabled() or false
end

-- Values can be "secret" under Midnight-style addon restrictions: they can be
-- displayed but not compared or used in arithmetic. Treat those as unreadable.
function ns.IsReadable(value)
	if value == nil then
		return false
	end
	if canaccessvalue then
		return canaccessvalue(value)
	end
	if issecretvalue then
		return not issecretvalue(value)
	end
	return true
end

-- Internal callbacks between modules
local callbacks = {}

function ns.RegisterCallback(name, fn)
	callbacks[name] = callbacks[name] or {}
	table.insert(callbacks[name], fn)
end

function ns.Fire(name, ...)
	for _, fn in ipairs(callbacks[name] or {}) do
		fn(...)
	end
end

-- Game events
local eventFrame = CreateFrame("Frame")
local handlers = {}

function ns.RegisterEvent(event, fn)
	if not handlers[event] then
		handlers[event] = {}
		eventFrame:RegisterEvent(event)
	end
	table.insert(handlers[event], fn)
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
	for _, fn in ipairs(handlers[event]) do
		fn(...)
	end
end)

ns.RegisterEvent("ADDON_LOADED", function(loadedName)
	if loadedName ~= addonName then
		return
	end

	ForeverChronicleDB = ForeverChronicleDB or {}
	local db = ForeverChronicleDB
	db.settings = db.settings or {}
	for key, value in pairs(DEFAULT_SETTINGS) do
		if db.settings[key] == nil then
			db.settings[key] = value
		end
	end
	ns.db = db
	ns.settings = db.settings

	if not (ForeverChronicleCharDB and ForeverChronicleCharDB.schema) then
		ForeverChronicleCharDB = NewCharacterData()
		ns.isNewCharacter = true
	end
	ns.char = ForeverChronicleCharDB
end)

ns.RegisterEvent("PLAYER_LOGIN", function()
	ns.char.startLevel = ns.char.startLevel or UnitLevel("player")
end)
