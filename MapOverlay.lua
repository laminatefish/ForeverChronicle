local _, ns = ...

-- Draws the recorded route and event pins on the world map, through the
-- map's data-provider system so it follows map changes, panning and zoom.
local Overlay = {}
ns.Overlay = Overlay

local ROUTE_WIDTH = 3  -- screen pixels
local MIN_STEP = 4     -- screen pixels between drawn points
local DASH_LENGTH = 6  -- screen pixels per dash (and per gap) in teleport lines
local MAX_LINES = 5000

-- The map's pin frame level we draw at: above the explored-area art and fog,
-- below flight points and quest pins. Without it the overlay sits under the
-- map art. Only read the levels manager: writing to it taints every pin's
-- frame level and gets the addon blocked when the map opens or closes.
local BASE_FRAME_LEVEL_TYPE = "PIN_FRAME_LEVEL_MAP_HIGHLIGHT"

-- Defaults for the route style; the player's choices are kept in
-- ns.settings.routeStartColor, routeEndColor and routeWidth (nil means default)
local START_COLOR = { 1, 0.85, 0.4 }  -- pale gold at level 1
local END_COLOR = { 0.75, 0.08, 0.1 } -- crimson at max level

local ROUTE_WIDTHS = {
	{ width = 2, label = "Thin" },
	{ width = ROUTE_WIDTH, label = "Normal" },
	{ width = 5, label = "Thick" },
}

local PIN_STYLES = {
	begin = { setting = "showLevels", size = 18, layer = 2, icon = ns.Chronicle.ICONS.begin },
	level = { setting = "showLevels", size = 16, layer = 1, icon = ns.Chronicle.ICONS.level },
	dungeon = { setting = "showDungeons", size = 18, layer = 2, icon = ns.Chronicle.ICONS.dungeon },
	note = { setting = "showNotes", size = 16, layer = 2, icon = ns.Chronicle.ICONS.note },
	death = { setting = "showDeaths", size = 22, layer = 3, texture = ns.Chronicle.ICONS.death },
}

local TOGGLES = {
	{ key = "showRoute", label = "Route" },
	{ key = "showDeaths", label = "Deaths" },
	{ key = "showLevels", label = "Level-ups" },
	{ key = "showDungeons", label = "Dungeons" },
	{ key = "showNotes", label = "Journal notes" },
}

local function RouteWidth()
	return ns.settings.routeWidth or ROUTE_WIDTH
end

local function LevelColor(level)
	local first = ns.settings.routeStartColor or START_COLOR
	local last = ns.settings.routeEndColor or END_COLOR
	local maxLevel = GetMaxLevelForPlayerExpansion and GetMaxLevelForPlayerExpansion() or 60
	local f = math.min(math.max((level - 1) / math.max(maxLevel - 1, 1), 0), 1)
	return first[1] + (last[1] - first[1]) * f,
		first[2] + (last[2] - first[2]) * f,
		first[3] + (last[3] - first[3]) * f
end

local function ToCanvas(t, x, y, w, h)
	local u, v = ns.Geo.WorldToMap(t, x, y)
	return u * w, v * h
end

local function IsNearCanvas(x, y, w, h)
	return x > -0.1 * w and x < 1.1 * w and y > -0.1 * h and y < 1.1 * h
end

-- Data provider, combined with MapCanvasDataProviderMixin once the map loads

local OverlayMixin = {}

function OverlayMixin:OnAdded(owningMap)
	MapCanvasDataProviderMixin.OnAdded(self, owningMap)
	self.frame = CreateFrame("Frame", nil, owningMap:GetCanvas())
	self.frame:SetAllPoints()
	self.lines, self.numLines = {}, 0
	self.pins, self.numPins = {}, 0
	self:ApplyFrameLevel()
end

-- Levels shift when other providers insert their own, so reapply on each draw
function OverlayMixin:GetFrameLevelFor(layer)
	return self:GetMap():GetPinFrameLevelsManager():GetValidFrameLevel(BASE_FRAME_LEVEL_TYPE) + layer
end

function OverlayMixin:ApplyFrameLevel()
	self.frame:SetFrameLevel(self:GetFrameLevelFor(0))
end

function OverlayMixin:RemoveAllData()
	for i = 1, self.numLines do
		self.lines[i]:Hide()
	end
	for i = 1, self.numPins do
		self.pins[i]:Hide()
	end
	self.numLines, self.numPins = 0, 0
end

function OverlayMixin:OnMapChanged()
	self:RefreshAllData()
end

function OverlayMixin:OnCanvasScaleChanged()
	-- Keep sizes constant on screen now; redraw at the new detail level once zooming settles
	self:ApplyScale()
	if self.redrawTimer then
		self.redrawTimer:Cancel()
	end
	self.redrawTimer = C_Timer.NewTimer(0.25, function()
		self.redrawTimer = nil
		self:RefreshAllData()
	end)
end

function OverlayMixin:ApplyScale()
	local scale = self:GetMap():GetCanvasScale()
	for i = 1, self.numLines do
		self.lines[i]:SetThickness(RouteWidth() / scale)
	end
	for i = 1, self.numPins do
		local pin = self.pins[i]
		pin:SetSize(pin.baseSize / scale, pin.baseSize / scale)
	end
end

function OverlayMixin:RefreshAllData()
	self:RemoveAllData()
	if not ns.char then
		return
	end
	local map = self:GetMap()
	self:ApplyFrameLevel()
	local t = ns.Geo.GetMapTransform(map:GetMapID())
	local w, h = map:GetCanvas():GetSize()
	if not t or w == 0 or h == 0 then
		return
	end
	local scale = map:GetCanvasScale()
	if ns.settings.showRoute then
		self:DrawRoute(t, w, h, scale)
	end
	self:DrawPins(t, w, h, scale)
end

function OverlayMixin:DrawLine(x1, y1, x2, y2, r, g, b, a, thickness)
	if self.numLines >= MAX_LINES then
		return false
	end
	self.numLines = self.numLines + 1
	local line = self.lines[self.numLines]
	if not line then
		line = self.frame:CreateLine(nil, "ARTWORK")
		self.lines[self.numLines] = line
	end
	line:SetColorTexture(r, g, b, a)
	line:SetThickness(thickness)
	line:SetStartPoint("TOPLEFT", self.frame, x1, -y1)
	line:SetEndPoint("TOPLEFT", self.frame, x2, -y2)
	line:Show()
	return true
end

-- Teleports have only their two ends recorded, so cut the line into dashes
function OverlayMixin:DrawDashedLine(x1, y1, x2, y2, r, g, b, a, thickness, dash)
	local length = math.sqrt((x2 - x1) ^ 2 + (y2 - y1) ^ 2)
	local dx, dy = (x2 - x1) / length * dash, (y2 - y1) / length * dash
	for i = 0, length / dash, 2 do
		local f = math.min(i + 1, length / dash)
		if f > i and not self:DrawLine(x1 + dx * i, y1 + dy * i, x1 + dx * f, y1 + dy * f, r, g, b, a, thickness) then
			return false
		end
	end
	return true
end

function OverlayMixin:DrawRoute(t, w, h, scale)
	local minStepSq = (MIN_STEP / scale) ^ 2
	local thickness = RouteWidth() / scale
	for _, seg in ipairs(ns.char.segments) do
		local n = #seg.x
		if seg.c == t.c and n > 1 and seg.kind == "teleport" then
			local r, g, b = LevelColor(seg.level)
			local x1, y1 = ToCanvas(t, seg.x[1], seg.y[1], w, h)
			local x2, y2 = ToCanvas(t, seg.x[n], seg.y[n], w, h)
			if (IsNearCanvas(x1, y1, w, h) or IsNearCanvas(x2, y2, w, h)) and (x1 ~= x2 or y1 ~= y2) then
				if not self:DrawDashedLine(x1, y1, x2, y2, r, g, b, 0.5, thickness, DASH_LENGTH / scale) then
					return
				end
			end
		elseif seg.c == t.c and n > 1 then
			local r, g, b = LevelColor(seg.level)
			local dashed = seg.kind == "taxi"
			local alpha = dashed and 0.6 or 0.9
			local px, py = ToCanvas(t, seg.x[1], seg.y[1], w, h)
			local step = 0
			for i = 2, n do
				local x, y = ToCanvas(t, seg.x[i], seg.y[i], w, h)
				local dx, dy = x - px, y - py
				if dx * dx + dy * dy >= minStepSq or i == n then
					step = step + 1
					local visible = IsNearCanvas(px, py, w, h) or IsNearCanvas(x, y, w, h)
					if visible and (not dashed or step % 2 == 1) then
						if not self:DrawLine(px, py, x, y, r, g, b, alpha, thickness) then
							return
						end
					end
					px, py = x, y
				end
			end
		end
	end
end

local function CreatePin(parent)
	local pin = CreateFrame("Button", nil, parent)
	pin.texture = pin:CreateTexture(nil, "ARTWORK")
	pin.texture:SetAllPoints()
	pin.mask = pin:CreateMaskTexture()
	pin.mask:SetAllPoints()
	pin.mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	pin:SetScript("OnEnter", function(self)
		ns.Chronicle:ShowTooltip(self, self.event)
	end)
	pin:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	return pin
end

local function ApplyPinStyle(pin, style)
	local tex = pin.texture
	if pin.masked then
		tex:RemoveMaskTexture(pin.mask)
		pin.masked = false
	end
	if style.icon then
		tex:SetTexture(style.icon)
		tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	else
		tex:SetTexture(style.texture)
		tex:SetTexCoord(0, 1, 0, 1)
	end
	if style.icon then
		tex:AddMaskTexture(pin.mask)
		pin.masked = true
	end
end

function OverlayMixin:AcquirePin(style)
	self.numPins = self.numPins + 1
	local pin = self.pins[self.numPins]
	if not pin then
		pin = CreatePin(self.frame)
		self.pins[self.numPins] = pin
	end
	ApplyPinStyle(pin, style)
	pin:SetFrameLevel(self:GetFrameLevelFor(style.layer))
	pin:ClearAllPoints()
	pin:Show()
	return pin
end

function OverlayMixin:DrawPins(t, w, h, scale)
	for _, e in ipairs(ns.char.events) do
		local style = PIN_STYLES[e.kind]
		if style and e.c == t.c and e.x and ns.settings[style.setting] then
			local x, y = ToCanvas(t, e.x, e.y, w, h)
			if IsNearCanvas(x, y, w, h) then
				local pin = self:AcquirePin(style)
				pin.event = e
				pin.baseSize = style.size
				pin:SetSize(style.size / scale, style.size / scale)
				pin:SetPoint("CENTER", self.frame, "TOPLEFT", x, -y)
			end
		end
	end
end

-- Map button and toggle menu

-- Opens the game's colour picker, previewing on the map as the colour changes
local function PickColor(settingKey, default)
	local r, g, b = unpack(ns.settings[settingKey] or default)
	local function Apply()
		local nr, ng, nb = ColorPickerFrame:GetColorRGB()
		ns.settings[settingKey] = { nr, ng, nb }
		Overlay:Refresh()
	end
	local function Cancel()
		ns.settings[settingKey] = { r, g, b }
		Overlay:Refresh()
	end
	if ColorPickerFrame.SetupColorPickerAndShow then
		ColorPickerFrame:SetupColorPickerAndShow({ r = r, g = g, b = b, swatchFunc = Apply, cancelFunc = Cancel })
	else
		ColorPickerFrame.hasOpacity = false
		ColorPickerFrame.func, ColorPickerFrame.cancelFunc = Apply, Cancel
		ColorPickerFrame.previousValues = { r, g, b }
		ColorPickerFrame:SetColorRGB(r, g, b)
		ShowUIPanel(ColorPickerFrame)
	end
end

-- A small square of the colour, for menu labels
local function Swatch(color)
	return string.format("|TInterface\\Buttons\\WHITE8X8:12:12:0:0:8:8:0:8:0:8:%d:%d:%d|t ",
		math.floor(color[1] * 255 + 0.5), math.floor(color[2] * 255 + 0.5), math.floor(color[3] * 255 + 0.5))
end

local function AddRouteStyleMenu(root)
	local style = root:CreateButton("Route style")
	style:CreateButton(Swatch(ns.settings.routeStartColor or START_COLOR) .. "Colour at level 1...", function()
		PickColor("routeStartColor", START_COLOR)
	end)
	style:CreateButton(Swatch(ns.settings.routeEndColor or END_COLOR) .. "Colour at max level...", function()
		PickColor("routeEndColor", END_COLOR)
	end)
	style:CreateDivider()
	for _, option in ipairs(ROUTE_WIDTHS) do
		style:CreateRadio(option.label, function()
			return RouteWidth() == option.width
		end, function()
			ns.settings.routeWidth = option.width
			Overlay:Refresh()
		end)
	end
	style:CreateDivider()
	style:CreateButton("Reset route style", function()
		ns.settings.routeStartColor, ns.settings.routeEndColor, ns.settings.routeWidth = nil, nil, nil
		Overlay:Refresh()
	end)
end

local function ShowMenu(button)
	if not MenuUtil or ns.IsGamepadUI() then
		ns.Journal:Toggle()
		return
	end
	MenuUtil.CreateContextMenu(button, function(_, root)
		root:CreateTitle(ns.title)
		for _, toggle in ipairs(TOGGLES) do
			root:CreateCheckbox(toggle.label, function()
				return ns.settings[toggle.key]
			end, function()
				ns.settings[toggle.key] = not ns.settings[toggle.key]
				Overlay:Refresh()
			end)
		end
		AddRouteStyleMenu(root)
		root:CreateDivider()
		root:CreateCheckbox("Recording", function()
			return ns.settings.recording
		end, function()
			ns.settings.recording = not ns.settings.recording
		end)
		root:CreateButton("Open journal", function()
			ns.Journal:Toggle()
		end)
	end)
end

local function CreateMapButton()
	local container = WorldMapFrame.ScrollContainer or WorldMapFrame
	local button = CreateFrame("Button", "ForeverChronicleMapButton", container)
	button:SetSize(31, 31)
	-- Forever moves the map pin button to this corner; stack below it, as the
	-- map's own buttons stack, and draw at its strata so neither covers the other
	local pinButton = WorldMapFrame.WorldMapTrackingPinButton
	if pinButton then
		button:SetPoint("TOPLEFT", pinButton, "BOTTOMLEFT", 0, -2)
		button:SetFrameStrata(pinButton:GetFrameStrata())
	else
		button:SetPoint("TOPLEFT", 8, -8)
	end
	button:SetFrameLevel(container:GetFrameLevel() + 100)

	local background = button:CreateTexture(nil, "BACKGROUND")
	background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
	background:SetSize(20, 20)
	background:SetPoint("TOPLEFT", 7, -5)

	local icon = button:CreateTexture(nil, "ARTWORK")
	icon:SetTexture("Interface\\Icons\\INV_Misc_Map_01")
	icon:SetSize(17, 17)
	icon:SetPoint("TOPLEFT", 7, -6)

	local border = button:CreateTexture(nil, "OVERLAY")
	border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	border:SetSize(53, 53)
	border:SetPoint("TOPLEFT")

	button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

	button:SetScript("OnClick", ShowMenu)
	button:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(ns.title, 1, 0.82, 0)
		if ns.IsGamepadUI() then
			GameTooltip:AddLine("Click to open the journal.", 1, 1, 1)
		else
			GameTooltip:AddLine("Click to choose what the map shows.", 1, 1, 1)
		end
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
end

function Overlay:Init()
	if self.provider or not (WorldMapFrame and MapCanvasDataProviderMixin and ns.char) then
		return
	end
	self.provider = CreateFromMixins(MapCanvasDataProviderMixin, OverlayMixin)
	WorldMapFrame:AddDataProvider(self.provider)
	CreateMapButton()
end

function Overlay:Refresh()
	if self.provider and WorldMapFrame:IsShown() then
		self.provider:RefreshAllData()
	end
end

ns.RegisterEvent("PLAYER_LOGIN", function()
	Overlay:Init()
end)

ns.RegisterEvent("ADDON_LOADED", function(name)
	if name == "Blizzard_WorldMap" then
		Overlay:Init()
	end
end)

ns.RegisterCallback("ROUTE_UPDATED", function()
	Overlay:Refresh()
end)

ns.RegisterCallback("EVENT_ADDED", function()
	Overlay:Refresh()
end)
