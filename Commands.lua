local _, ns = ...

local function Help()
	ns.Print("commands:")
	print("  /fc - open or close the journal")
	print("  /fc note <text> - write a journal entry pinned to where you stand")
	print("  /fc route - show or hide the route on the world map")
	print("  /fc pause | resume - stop or restart recording your route")
	print("  /fc stats - print your deeds and records")
	print("  /fc share - start or stop sharing your backstory")
	print("  /fc read - read your target's backstory")
	print("  /fc card - start or stop showing your journey card to other players")
	print("  /fc probe - report which game data addons can read here")
	print("  /fc probe ui - record how the character panel is built")
end

local function ToggleSetting(key, label)
	ns.settings[key] = not ns.settings[key]
	ns.Overlay:Refresh()
	ns.Print("%s %s.", label, ns.settings[key] and "shown" or "hidden")
end

local COMMANDS = {
	[""] = function()
		ns.Journal:Toggle()
	end,
	journal = function()
		ns.Journal:Toggle()
	end,
	note = function(text)
		if text == "" then
			ns.Print("Usage: /fc note <text>")
			return
		end
		local e = ns.Chronicle:AddNote(text)
		ns.Print("Entry written in %s.", e.subzone ~= "" and e.subzone or e.zone)
	end,
	route = function()
		ToggleSetting("showRoute", "Route")
	end,
	pause = function()
		ns.settings.recording = false
		ns.Print("Route recording paused.")
	end,
	resume = function()
		ns.settings.recording = true
		ns.Print("Route recording resumed.")
	end,
	share = function()
		ns.settings.shareBackstory = not ns.settings.shareBackstory
		ns.Journal:Refresh()
		if ns.settings.shareBackstory then
			ns.Print("Sharing your backstory with other %s players.", ns.title)
		else
			ns.Print("Your backstory is private.")
		end
	end,
	card = function()
		ns.settings.shareJourney = not ns.settings.shareJourney
		ns.Journal:Refresh()
		if ns.settings.shareJourney then
			ns.Print("Showing your journey card: %s", ns.Share:FormatCard(ns.Chronicle:GetRecords()))
		else
			ns.Print("Your journey card is hidden.")
		end
	end,
	read = function()
		ns.Share:ReadUnit("target")
	end,
	stats = function()
		local r = ns.Chronicle:GetRecords()
		ns.Print("Day %d. Level %d. %d deaths. %.1f miles. %d zones discovered.", r.days, r.level, r.deaths, r.miles, r.zones)
	end,
	probe = function(what)
		if what == "ui" then
			ns.Probe:DumpUI()
		else
			ns.Probe:Run()
		end
	end,
	help = Help,
}

SLASH_FOREVERCHRONICLE1 = "/fc"
SLASH_FOREVERCHRONICLE2 = "/chronicle"
SlashCmdList.FOREVERCHRONICLE = function(msg)
	local command, rest = msg:match("^%s*(%S*)%s*(.-)%s*$")
	local handler = COMMANDS[command:lower()]
	if handler then
		handler(rest)
	else
		Help()
	end
end

-- Addon compartment (the addons button by the minimap)
function ForeverChronicle_OnCompartmentClick()
	ns.Journal:Toggle()
end
