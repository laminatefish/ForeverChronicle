local _, ns = ...

-- The journal window: the journey timeline, deeds and records, and the
-- character's backstory. Docks beside the character panel when that is open,
-- and opens from a map tab on the panel's edge.
local Journal = {}
ns.Journal = Journal

local WIDTH, HEIGHT = 360, 484 -- the character panel's height
local INSET_WIDTH = WIDTH - 10 -- ButtonFrameTemplate's inset sits 4px in on the left, 6px on the right
local PADDING = 8
local CONTENT_WIDTH = INSET_WIDTH - PADDING * 2
local SCROLL_WIDTH = CONTENT_WIDTH - 28
local ROW_HEIGHT = 42
local ICON_SIZE = 30
local RECORD_HEIGHT = 26

-- The character panel's side tabs (CharacterFrameModeTabs). The journal docks
-- where Blizzard docks its own side panes: just over the tabs' right edge.
local SIDE_TAB_SIZE = 55
local SIDE_TAB_SPACING = 2
local SIDE_TAB_OVERLAP = 11

local TABS = {
	{ key = "journey", label = "The Journey" },
	{ key = "records", label = "Deeds & Records" },
	{ key = "backstory", label = "Backstory" },
}

local TITLE_COLORS = {
	death = { 1, 0.35, 0.3 },
}

local function CreateScrollFrame(parent)
	local scroll = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT")
	scroll:SetPoint("BOTTOMRIGHT", -26, 0)
	return scroll
end

-- The Journey: a timeline, newest first

local function CreateRow(parent, index)
	local row = CreateFrame("Button", nil, parent)
	row:SetSize(SCROLL_WIDTH, ROW_HEIGHT)
	row:SetPoint("TOPLEFT", 0, -(index - 1) * ROW_HEIGHT)
	row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")

	if index % 2 == 1 then
		local stripe = row:CreateTexture(nil, "BACKGROUND")
		stripe:SetAllPoints()
		stripe:SetColorTexture(1, 1, 1, 0.04)
	end

	-- A dark frame behind the icon, so it reads against the timeline
	row.border = row:CreateTexture(nil, "BORDER")
	row.border:SetSize(ICON_SIZE + 2, ICON_SIZE + 2)
	row.border:SetPoint("LEFT", 3, 0)
	row.border:SetColorTexture(0, 0, 0, 1)

	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(ICON_SIZE, ICON_SIZE)
	row.icon:SetPoint("CENTER", row.border)
	row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

	row.title = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	row.title:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 10, -1)
	row.title:SetPoint("RIGHT", -4, 0)
	row.title:SetJustifyH("LEFT")
	row.title:SetWordWrap(false)

	row.detail = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.detail:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 10, 1)
	row.detail:SetPoint("RIGHT", -4, 0)
	row.detail:SetJustifyH("LEFT")
	row.detail:SetWordWrap(false)

	row:SetScript("OnEnter", function(self)
		ns.Chronicle:ShowTooltip(self, self.event)
	end)
	row:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	row:SetScript("OnClick", function(self)
		Journal:ShowOnMap(self.event)
	end)
	return row
end

local function CreateJourneyPage(page)
	local scroll = CreateScrollFrame(page)
	local child = CreateFrame("Frame", nil, scroll)
	child:SetSize(SCROLL_WIDTH, 1)
	scroll:SetScrollChild(child)
	page.child = child
	page.rows = {}

	-- The thread joining one moment to the next, behind the icons
	page.thread = child:CreateTexture(nil, "BACKGROUND", nil, 1)
	page.thread:SetWidth(2)
	page.thread:SetColorTexture(0.8, 0.65, 0.3, 0.5)

	page.empty = page:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	page.empty:SetPoint("CENTER")
	page.empty:SetText("Your story has yet to be written.")

	function page:Refresh()
		local events = ns.char.events
		local count = #events
		for i = 1, count do
			local row = self.rows[i] or CreateRow(self.child, i)
			self.rows[i] = row
			local e = events[count - i + 1]
			local title, detail = ns.Chronicle:Describe(e)
			row.event = e
			row.icon:SetTexture(ns.Chronicle.ICONS[e.kind])
			row.title:SetText(title)
			row.title:SetTextColor(unpack(TITLE_COLORS[e.kind] or { NORMAL_FONT_COLOR:GetRGB() }))
			row.detail:SetText(e.text or detail)
			row:Show()
		end
		for i = count + 1, #self.rows do
			self.rows[i]:Hide()
		end
		self.child:SetHeight(math.max(count * ROW_HEIGHT, 1))
		self.empty:SetShown(count == 0)

		self.thread:SetShown(count > 1)
		if count > 1 then
			self.thread:ClearAllPoints()
			self.thread:SetPoint("TOP", self.rows[1].border, "CENTER")
			self.thread:SetPoint("BOTTOM", self.rows[count].border, "CENTER")
		end
	end
end

-- Deeds & Records

local RECORDS = {
	{ "Level", function(r) return r.level end },
	{ "Levels gained on this journey", function(r) return r.levelsGained end },
	{ "Days on the road", function(r) return r.days end },
	{ "Distance travelled", function(r) return string.format("%.1f miles", r.miles) end },
	{ "Zones discovered", function(r) return r.zones end },
	{ "Deaths", function(r) return r.deaths end },
	{ "Most dangerous place", function(r)
		return r.deadliestPlace and string.format("%s (%d)", r.deadliestPlace, r.deadliestCount) or "None yet"
	end },
	{ "Most levels without dying", function(r) return r.levelsWithoutDying end },
	{ "Route points recorded", function(r) return r.points end },
}

local function CreateRecordsPage(page)
	page.values = {}
	for i, record in ipairs(RECORDS) do
		local line = CreateFrame("Frame", nil, page)
		line:SetPoint("TOPLEFT", 0, -(i - 1) * RECORD_HEIGHT)
		line:SetSize(CONTENT_WIDTH, RECORD_HEIGHT)

		-- The same banding as the stats on the character panel
		local band = line:CreateTexture(nil, "BACKGROUND")
		band:SetAllPoints()
		if i % 2 == 1 then
			band:SetAtlas("UI-Character-Info-Line-Bounce")
			band:SetAlpha(0.3)
		end

		local label = line:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		label:SetPoint("LEFT", 8, 0)
		label:SetText(record[1])

		local value = line:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		value:SetPoint("RIGHT", -8, 0)
		value:SetJustifyH("RIGHT")
		page.values[i] = value
	end

	local share = CreateFrame("CheckButton", nil, page, "UICheckButtonTemplate")
	share:SetSize(24, 24)
	share:SetPoint("BOTTOMLEFT", -2, -4)
	share.label = share:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	share.label:SetPoint("LEFT", share, "RIGHT", 2, 1)
	share.label:SetText("Show my journey card to other " .. ns.title .. " players")
	share:SetScript("OnClick", function(self)
		ns.settings.shareJourney = self:GetChecked()
	end)
	share:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText("Journey card", 1, 0.82, 0)
		GameTooltip:AddLine("Adds a line to your tooltip for players who also run " .. ns.title .. ":", 1, 1, 1, true)
		GameTooltip:AddLine(ns.Share:FormatCard(ns.Chronicle:GetRecords()), 1, 0.82, 0, true)
		GameTooltip:AddLine("Hover over yourself to preview it.", 0.8, 0.8, 0.8, true)
		GameTooltip:Show()
	end)
	share:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	page.share = share

	function page:Refresh()
		local records = ns.Chronicle:GetRecords()
		for i, record in ipairs(RECORDS) do
			self.values[i]:SetText(tostring(record[2](records)))
		end
		self.share:SetChecked(ns.settings.shareJourney)
	end
end

-- Backstory

local function CreateBackstoryPage(page)
	local heading = page:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	heading:SetPoint("TOPLEFT", 4, 0)

	local share = CreateFrame("CheckButton", nil, page, "UICheckButtonTemplate")
	share:SetSize(24, 24)
	share:SetPoint("BOTTOMLEFT", -2, -4)
	share.label = share:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	share.label:SetPoint("LEFT", share, "RIGHT", 2, 1)
	share.label:SetText("Share with other " .. ns.title .. " players")
	share:SetScript("OnClick", function(self)
		ns.settings.shareBackstory = self:GetChecked()
	end)
	share:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText("Share my backstory", 1, 0.82, 0)
		GameTooltip:AddLine("Players who also run " .. ns.title .. " see a book icon over your nameplate and can read your backstory.", 1, 1, 1, true)
		GameTooltip:Show()
	end)
	share:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)

	local hint = page:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	hint:SetPoint("BOTTOMRIGHT", -4, 4)
	hint:SetText("Saved as you write.")

	local box = CreateFrame("Frame", nil, page, "BackdropTemplate")
	box:SetPoint("TOPLEFT", 0, -22)
	box:SetPoint("BOTTOMRIGHT", 0, 24)
	box:SetBackdrop({
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		edgeSize = 14,
	})

	-- The quest frame's parchment, with the quest frame's font to match
	local parchment = box:CreateTexture(nil, "BACKGROUND")
	parchment:SetAtlas("QuestBG-Parchment")
	parchment:SetPoint("TOPLEFT", 3, -3)
	parchment:SetPoint("BOTTOMRIGHT", -3, 3)

	local scroll = CreateFrame("ScrollFrame", nil, box, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 8, -8)
	scroll:SetPoint("BOTTOMRIGHT", -28, 8)

	local edit = CreateFrame("EditBox", nil, scroll)
	edit:SetMultiLine(true)
	edit:SetAutoFocus(false)
	edit:SetFontObject(QuestFont or ChatFontNormal)
	edit:SetWidth(CONTENT_WIDTH - 44)
	edit:SetScript("OnEscapePressed", edit.ClearFocus)
	edit:SetScript("OnTextChanged", function(self, userInput)
		if userInput then
			ns.char.backstory = self:GetText()
			ns.char.backstoryEdited = time()
		end
	end)
	if ScrollingEdit_OnCursorChanged then
		edit:SetScript("OnCursorChanged", ScrollingEdit_OnCursorChanged)
		edit:SetScript("OnUpdate", function(self, elapsed)
			ScrollingEdit_OnUpdate(self, elapsed, scroll)
		end)
	end
	scroll:SetScrollChild(edit)

	box:EnableMouse(true)
	box:SetScript("OnMouseDown", function()
		edit:SetFocus()
	end)

	function page:Refresh()
		heading:SetText("Who is " .. ns.GetDisplayName("player") .. "?")
		share:SetChecked(ns.settings.shareBackstory)
		if not edit:HasFocus() then
			edit:SetText(ns.char.backstory or "")
		end
	end
end

-- Window

function Journal:SelectTab(index)
	for i, info in ipairs(TABS) do
		self.pages[info.key]:SetShown(i == index)
	end
	PanelTemplates_SetTab(self.frame, index)
	self.selectedTab = TABS[index].key
	self.pages[self.selectedTab]:Refresh()
end

function Journal:Create()
	local f = CreateFrame("Frame", "ForeverChronicleJournal", UIParent, "ButtonFrameTemplate")
	f:SetSize(WIDTH, HEIGHT)
	f:SetPoint("CENTER")
	f:SetToplevel(true)
	f:SetMovable(true)
	f:SetClampedToScreen(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", function(self)
		if not Journal.docked then
			self:StartMoving()
		end
	end)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	table.insert(UISpecialFrames, f:GetName())

	ButtonFrameTemplate_HideButtonBar(f)
	f:SetPortraitToAsset("Interface\\Icons\\INV_Misc_Map_01")
	f:SetTitle(ns.title)

	f.subtitle = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	f.subtitle:SetPoint("TOPLEFT", 66, -36)
	f.subtitle:SetPoint("RIGHT", -12, 0)
	f.subtitle:SetJustifyH("LEFT")

	self.pages = {}
	for i, info in ipairs(TABS) do
		local tab = CreateFrame("Button", "$parentTab" .. i, f, "PanelTabButtonTemplate")
		tab:SetID(i)
		tab:SetText(info.label)
		if i == 1 then
			tab:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 11, 2)
		else
			tab:SetPoint("LEFT", _G[f:GetName() .. "Tab" .. (i - 1)], "RIGHT", 3, 0)
		end
		tab:SetScript("OnClick", function()
			PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB)
			Journal:SelectTab(i)
		end)

		local page = CreateFrame("Frame", nil, f.Inset)
		page:SetPoint("TOPLEFT", PADDING, -PADDING)
		page:SetPoint("BOTTOMRIGHT", -PADDING, PADDING)
		page:Hide()
		self.pages[info.key] = page
	end
	PanelTemplates_SetNumTabs(f, #TABS)
	CreateJourneyPage(self.pages.journey)
	CreateRecordsPage(self.pages.records)
	CreateBackstoryPage(self.pages.backstory)

	f:Hide()
	f:SetScript("OnShow", function()
		PlaySound(SOUNDKIT.IG_CHARACTER_INFO_OPEN)
		Journal:Refresh()
		Journal:UpdateCharacterTab()
	end)
	f:SetScript("OnHide", function()
		PlaySound(SOUNDKIT.IG_CHARACTER_INFO_CLOSE)
		Journal:UpdateCharacterTab()
	end)
	self.frame = f
	self:SelectTab(1)
end

function Journal:Refresh()
	local f = self.frame
	if not (f and f:IsShown()) then
		return
	end
	local race = UnitRace("player")
	local class = UnitClass("player")
	f.subtitle:SetText(string.format("%s, level %d %s %s", ns.GetDisplayName("player"), ns.Chronicle:GetLevel(), race or "", class or ""))
	self.pages[self.selectedTab]:Refresh()
end

-- Beside the character panel when it is open, otherwise wherever it was left
function Journal:UpdatePosition()
	local f = self.frame
	local dock = CharacterFrame and CharacterFrame:IsShown()
	if dock then
		local x = (CharacterFrameModeTabs and CharacterFrameModeTabs:GetWidth() or 0) - SIDE_TAB_OVERLAP
		f:ClearAllPoints()
		f:SetPoint("TOPLEFT", CharacterFrame, "TOPRIGHT", x, 0)
		f:SetPoint("BOTTOMLEFT", CharacterFrame, "BOTTOMRIGHT", x, 0)
	elseif self.docked then
		f:ClearAllPoints()
		f:SetPoint("CENTER")
	end
	self.docked = dock
end

function Journal:Toggle()
	if not self.frame then
		self:Create()
	end
	if self.frame:IsShown() then
		self.frame:Hide()
	else
		self:UpdatePosition()
		self.frame:Show()
	end
end

function Journal:ShowOnMap(e)
	if not (e and e.mapID) or ns.IsGamepadUI() then
		return
	end
	if OpenWorldMap then
		OpenWorldMap(e.mapID)
	elseif WorldMapFrame then
		ShowUIPanel(WorldMapFrame)
		WorldMapFrame:SetMapID(e.mapID)
	end
end

-- The map tab, below the character panel's own side tabs and drawn the same
-- way. Blizzard's tab list is only read, never added to, to avoid taint.

local function LastSideTab()
	local tabs = CharacterFrameModeTabs and CharacterFrameModeTabs.Tabs
	local last
	for _, tab in ipairs(tabs or {}) do
		if tab:IsShown() then
			last = tab
		end
	end
	return last
end

function Journal:UpdateCharacterTab()
	local tab = self.characterTab
	if not tab then
		return
	end
	tab.selected:SetShown(self.frame and self.frame:IsShown() or false)

	tab:ClearAllPoints()
	local last = LastSideTab()
	if last then
		tab:SetPoint("TOPLEFT", last, "BOTTOMLEFT", 0, -SIDE_TAB_SPACING)
		-- The gamepad's RB hint hangs under the last tab; keep it at the bottom
		local hint = CharacterFrameTabIndicatorsRightTabButton
		if hint and hint:IsShown() then
			hint:ClearAllPoints()
			hint:SetPoint("TOP", tab, "BOTTOM")
		end
	else
		tab:SetPoint("TOPLEFT", CharacterFrame, "TOPRIGHT", 0, -30)
	end
end

function Journal:CreateCharacterTab()
	if self.characterTab or not CharacterFrame then
		return
	end
	local tab = CreateFrame("Button", "ForeverChronicleCharacterTab", CharacterFrame)
	tab:SetSize(SIDE_TAB_SIZE, SIDE_TAB_SIZE)
	tab:SetFrameLevel((CharacterFrameModeTabs or CharacterFrame):GetFrameLevel() + 1)

	local background = tab:CreateTexture(nil, "BACKGROUND")
	background:SetAtlas("common-sidetab", true)
	background:SetPoint("CENTER")

	local icon = tab:CreateTexture(nil, "ARTWORK")
	icon:SetTexture("Interface\\Icons\\INV_Misc_Map_01")
	icon:SetSize(50, 50)
	icon:SetPoint("CENTER", -4, 0)
	local mask = tab:CreateMaskTexture()
	mask:SetAtlas("common-sidetab-mask", true)
	mask:SetPoint("CENTER")
	icon:AddMaskTexture(mask)

	tab.selected = tab:CreateTexture(nil, "OVERLAY")
	tab.selected:SetAtlas("common-sidetab-selected", true)
	tab.selected:SetPoint("CENTER")

	local highlight = tab:CreateTexture(nil, "HIGHLIGHT")
	highlight:SetAtlas("common-sidetab-hover", true)
	highlight:SetPoint("CENTER")

	tab:SetScript("OnClick", function()
		Journal:Toggle()
	end)
	tab:SetScript("OnEnter", function(self)
		-- Placed as the panel's own tabs place theirs
		GameTooltip:SetOwner(self, "ANCHOR_NONE")
		GameTooltip:SetPoint("BOTTOMLEFT", self, "TOPRIGHT", -4, -4)
		GameTooltip:SetText(ns.title, 1, 0.82, 0)
		GameTooltip:AddLine("Your journey, deeds and backstory.", 1, 1, 1)
		GameTooltip:Show()
	end)
	tab:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)

	-- The side tabs may only be built or laid out once the panel opens
	CharacterFrame:HookScript("OnShow", function()
		Journal:UpdateCharacterTab()
		if Journal.frame and Journal.frame:IsShown() then
			Journal:UpdatePosition()
		end
	end)
	CharacterFrame:HookScript("OnHide", function()
		if Journal.docked and Journal.frame and Journal.frame:IsShown() then
			Journal.frame:Hide()
		end
	end)

	self.characterTab = tab
	self:UpdateCharacterTab()
end

ns.RegisterEvent("PLAYER_LOGIN", function()
	Journal:CreateCharacterTab()
end)

ns.RegisterEvent("ADDON_LOADED", function(name)
	if name == "Blizzard_CharacterFrame" then
		Journal:CreateCharacterTab()
	end
end)

ns.RegisterCallback("EVENT_ADDED", function()
	Journal:Refresh()
end)
