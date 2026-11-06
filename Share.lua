local _, ns = ...

-- Sharing backstories between players who both run the addon. Nothing is
-- broadcast: when a player is seen (nameplate, target, mouseover) their addon
-- is asked, once, whether they share a backstory, and the text itself is only
-- sent when someone asks to read it. Other players' backstories are kept for
-- the session only.
--
-- Messages are addon whispers on COMMS_PREFIX, fields separated by tabs:
--   Q                     do you share a backstory?
--   A <version>           yes; version is when it was last edited
--   N                     no
--   R                     please send it
--   T <version> <i> <n> <chunk>   part i of n of the encoded text
--   S <days> <deaths> <tenths of a mile>   journey card, sent after A or N
--                                          when the player shares it
local Share = {}
ns.Share = Share

local COMMS_PREFIX = "ForeverChronicle" -- addon message prefixes are limited to 16 characters
local SEND_INTERVAL = 0.3    -- seconds between our messages
local THROTTLE_BACKOFF = 1.5 -- seconds to wait when the client says we're sending too fast
local MAX_SEND_ATTEMPTS = 5
local REASK_AFTER = 300      -- seconds before asking the same player again, to pick up edits
local RESEND_AFTER = 30      -- seconds before sending the same player the whole text again
local READ_TIMEOUT = 15      -- seconds to wait for a backstory before giving up
local CHUNK_SIZE = 230       -- leaves room for the header in a 255-character message
local MAX_SHARED_LENGTH = 4000
local MAX_CHUNKS = 30

Share.ICON = "Interface\\Icons\\INV_Misc_Book_09"
local NAMEPLATE_ICON_SIZE = 18

local queue = {}
local ticker, pausedUntil = nil, 0
local MAX_CARD_VALUE = 1000000 -- sanity limit on numbers in someone else's card

local players = {}   -- [fullName] = { asked, has, version, text, textVersion, card }
local transfers = {} -- [fullName] = { version, n, parts, received }
local lastSent = {}  -- [fullName] = time we last sent them the whole text
local plateNames = {} -- [nameplate unit] = fullName
local plateIcons = {} -- [nameplate unit] = icon button

-- Encoding: the text may hold newlines and "|" (chat escape codes), which are
-- escaped so every message is plain, single-line text
local function Encode(text)
	text = text:gsub("\\", "\\\\")
	text = text:gsub("\n", "\\n")
	text = text:gsub("|", "\\p")
	return text
end

local function Decode(text)
	return (text:gsub("\\(.)", function(c)
		return c == "n" and "\n" or c == "p" and "|" or c
	end))
end

-- Splits without cutting a UTF-8 character in two
local function Chunks(text, size)
	local chunks, i = {}, 1
	while i <= #text do
		local j = math.min(i + size - 1, #text)
		while j < #text and j > i and text:byte(j + 1) >= 0x80 and text:byte(j + 1) < 0xC0 do
			j = j - 1
		end
		chunks[#chunks + 1] = text:sub(i, j)
		i = j + 1
	end
	return chunks
end

-- Sending, one message at a time

local function IsLockedDown()
	return C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown()
end

local function SendNext()
	local now = GetTime()
	if now < pausedUntil or IsLockedDown() then
		return
	end
	local message = table.remove(queue, 1)
	if not message then
		ticker:Cancel()
		ticker = nil
		return
	end
	local ok, result = pcall(C_ChatInfo.SendAddonMessage, COMMS_PREFIX, message.text, "WHISPER", message.target)
	local throttled = Enum.SendAddonMessageResult and result == Enum.SendAddonMessageResult.AddonMessageThrottle
	if ok and throttled then
		message.attempts = message.attempts + 1
		if message.attempts < MAX_SEND_ATTEMPTS then
			table.insert(queue, 1, message)
		end
		pausedUntil = now + THROTTLE_BACKOFF
	end
end

local function Send(target, text, urgent)
	local message = { target = target, text = text, attempts = 0 }
	if urgent then
		table.insert(queue, 1, message)
	else
		table.insert(queue, message)
	end
	if not ticker then
		ticker = C_Timer.NewTicker(SEND_INTERVAL, SendNext)
	end
end

-- What we know about other players

local function GetPlayer(name)
	local player = players[name]
	if not player then
		player = {}
		players[name] = player
	end
	return player
end

function Share:HasBackstory(name)
	return name and players[name] and players[name].has or false
end

-- The full name of a unit if it is another player and the client lets us know
-- who they are; nil otherwise (restricted values raise errors, hence pcall)
function Share:GetUnitPlayerName(unit)
	local ok, name = pcall(function()
		if not UnitIsPlayer(unit) or UnitIsUnit(unit, "player") then
			return
		end
		local fullName = ns.GetFullName(unit)
		if ns.IsReadable(fullName) and fullName ~= "" then
			return fullName
		end
	end)
	return ok and name or nil
end

function Share:Ask(name, urgent)
	local player = GetPlayer(name)
	if player.asked and GetTime() - player.asked < REASK_AFTER then
		return
	end
	player.asked = GetTime()
	Send(name, "Q", urgent)
end

function Share:AskUnit(unit, urgent)
	local name = self:GetUnitPlayerName(unit)
	if name then
		self:Ask(name, urgent)
	end
end

-- Reading someone's backstory: from the cache if it's current, otherwise ask
function Share:Read(name)
	local player = GetPlayer(name)
	ns.Reader:Open(name)
	if player.text and player.textVersion == player.version then
		ns.Reader:ShowText(name, player.text)
		return
	end
	ns.Reader:ShowStatus(name, string.format("Asking %s for their story...", name))
	transfers[name] = nil
	Send(name, "R", true)
	local requested = GetTime()
	player.requested = requested
	C_Timer.After(READ_TIMEOUT, function()
		if player.requested == requested and not (player.text and player.textVersion == player.version) then
			ns.Reader:ShowStatus(name, string.format("%s didn't answer. They may not share a backstory, or may be out of reach.", name))
		end
	end)
end

function Share:ReadUnit(unit)
	local name = self:GetUnitPlayerName(unit)
	if not name then
		ns.Print("Target another player to read their backstory.")
		return
	end
	self:Read(name)
end

-- Our own backstory, as shared

local function SharedText()
	if not ns.settings.shareBackstory then
		return
	end
	local text = Encode(strtrim(ns.char.backstory or ""))
	if text == "" then
		return
	end
	if #text > MAX_SHARED_LENGTH then
		text = Chunks(text, MAX_SHARED_LENGTH)[1]
		-- Don't end halfway through an escape: an odd run of trailing backslashes
		if #text:match("\\*$") % 2 == 1 then
			text = text:sub(1, -2)
		end
	end
	return text
end

local function SharedVersion()
	return ns.char.backstoryEdited or ns.char.created or 0
end

-- Incoming messages

local HANDLERS = {}

-- Our journey card: a few hard facts, as whole numbers
local function CardMessage()
	local records = ns.Chronicle:GetRecords()
	return string.format("S\t%d\t%d\t%d", records.days, records.deaths, math.floor(records.miles * 10 + 0.5))
end

function HANDLERS.Q(sender)
	if SharedText() then
		Send(sender, "A\t" .. SharedVersion())
	else
		Send(sender, "N")
	end
	if ns.settings.shareJourney then
		Send(sender, CardMessage())
	end
end

function HANDLERS.S(sender, rest)
	local days, deaths, tenths = rest:match("^(%d+)\t(%d+)\t(%d+)$")
	days, deaths, tenths = tonumber(days), tonumber(deaths), tonumber(tenths)
	if not (days and deaths and tenths) or math.max(days, deaths, tenths) > MAX_CARD_VALUE then
		return
	end
	GetPlayer(sender).card = { days = days, deaths = deaths, miles = tenths / 10 }
end

function HANDLERS.A(sender, rest)
	local player = GetPlayer(sender)
	player.has, player.version = true, tonumber(rest)
	Share:UpdateNameplates(sender)
end

function HANDLERS.N(sender)
	local player = GetPlayer(sender)
	player.has, player.version, player.requested = false, nil, nil
	ns.Reader:ShowStatus(sender, string.format("%s doesn't share a backstory.", sender))
	Share:UpdateNameplates(sender)
end

function HANDLERS.R(sender)
	local text = SharedText()
	if not text then
		Send(sender, "N", true)
		return
	end
	if lastSent[sender] and GetTime() - lastSent[sender] < RESEND_AFTER then
		return
	end
	lastSent[sender] = GetTime()
	local chunks = Chunks(text, CHUNK_SIZE)
	for i, chunk in ipairs(chunks) do
		Send(sender, string.format("T\t%d\t%d\t%d\t%s", SharedVersion(), i, #chunks, chunk))
	end
end

function HANDLERS.T(sender, rest)
	local version, i, n, chunk = rest:match("^(%d+)\t(%d+)\t(%d+)\t(.*)$")
	version, i, n = tonumber(version), tonumber(i), tonumber(n)
	if not (version and i and n) or n > MAX_CHUNKS or i < 1 or i > n then
		return
	end
	local transfer = transfers[sender]
	if not transfer or transfer.version ~= version or transfer.n ~= n then
		transfer = { version = version, n = n, parts = {}, received = 0 }
		transfers[sender] = transfer
	end
	if not transfer.parts[i] then
		transfer.parts[i] = chunk
		transfer.received = transfer.received + 1
	end

	local player = GetPlayer(sender)
	player.has, player.version = true, version
	if transfer.received < n then
		ns.Reader:ShowStatus(sender, string.format("Receiving %s's story (%d of %d)...", sender, transfer.received, n))
		return
	end
	transfers[sender] = nil
	player.text, player.textVersion = Decode(table.concat(transfer.parts)), version
	ns.Reader:ShowText(sender, player.text)
	Share:UpdateNameplates(sender)
end

ns.RegisterEvent("CHAT_MSG_ADDON", function(prefix, message, _, sender)
	if prefix ~= COMMS_PREFIX or not (ns.IsReadable(sender) and ns.IsReadable(message)) then
		return
	end
	local kind, rest = message:match("^(%u)\t?(.*)$")
	local handler = kind and HANDLERS[kind]
	if handler and sender ~= ns.GetFullName("player") then
		handler(sender, rest)
	end
end)

-- Nameplate icons

local function CreatePlateIcon()
	local icon = CreateFrame("Button")
	icon:SetSize(NAMEPLATE_ICON_SIZE, NAMEPLATE_ICON_SIZE)
	local texture = icon:CreateTexture(nil, "ARTWORK")
	texture:SetAllPoints()
	texture:SetTexture(Share.ICON)
	texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	local mask = icon:CreateMaskTexture()
	mask:SetAllPoints()
	mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	texture:AddMaskTexture(mask)
	icon:SetScript("OnClick", function(self)
		if self.name then
			Share:Read(self.name)
		end
	end)
	icon:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(self.name or "", 1, 0.82, 0)
		GameTooltip:AddLine("Has a backstory. Click to read it.", 1, 1, 1)
		GameTooltip:Show()
	end)
	icon:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	return icon
end

local iconPool = {}

local function HidePlateIcon(unit)
	local icon = plateIcons[unit]
	if icon then
		icon:Hide()
		icon:ClearAllPoints()
		icon:SetParent(nil)
		plateIcons[unit] = nil
		table.insert(iconPool, icon)
	end
end

-- Only plates we're allowed to touch: GetNamePlateForUnit leaves out forbidden ones
local function ShowPlateIcon(unit, name)
	local plate = C_NamePlate.GetNamePlateForUnit(unit)
	if not plate then
		return
	end
	local icon = plateIcons[unit] or table.remove(iconPool) or CreatePlateIcon()
	plateIcons[unit] = icon
	icon.name = name
	icon:SetParent(plate)
	icon:ClearAllPoints()
	icon:SetPoint("BOTTOM", plate, "TOP", 0, 2)
	icon:Show()
end

function Share:UpdateNameplates(name)
	for unit, plateName in pairs(plateNames) do
		if plateName == name then
			if self:HasBackstory(name) then
				ShowPlateIcon(unit, name)
			else
				HidePlateIcon(unit)
			end
		end
	end
end

ns.RegisterEvent("NAME_PLATE_UNIT_ADDED", function(unit)
	local name = Share:GetUnitPlayerName(unit)
	plateNames[unit] = name
	if not name then
		return
	end
	if Share:HasBackstory(name) then
		ShowPlateIcon(unit, name)
	end
	Share:Ask(name)
end)

ns.RegisterEvent("NAME_PLATE_UNIT_REMOVED", function(unit)
	plateNames[unit] = nil
	HidePlateIcon(unit)
end)

ns.RegisterEvent("PLAYER_TARGET_CHANGED", function()
	Share:AskUnit("target", true)
end)

ns.RegisterEvent("UPDATE_MOUSEOVER_UNIT", function()
	Share:AskUnit("mouseover", true)
end)

-- Tooltip lines

local function BestedText(deaths)
	if deaths == 0 then
		return "Never bested"
	elseif deaths == 1 then
		return "Bested once"
	end
	return string.format("Bested %d times", deaths)
end

-- Takes a received card or our own records, which have the same fields
function Share:FormatCard(card)
	return string.format("%.1f miles travelled · %s · Day %d", card.miles, BestedText(card.deaths), card.days)
end

local function AddTooltipLine(tooltip)
	if tooltip ~= GameTooltip then
		return
	end
	local ok, _, unit = pcall(tooltip.GetUnit, tooltip)
	if not (ok and unit) then
		return
	end
	local okSelf, isSelf = pcall(function()
		return UnitIsUnit(unit, "player") and true or false
	end)
	local card, hasBackstory
	if okSelf and isSelf then
		-- Your own card, as other players see it, while you share it
		card = ns.settings.shareJourney and ns.Chronicle:GetRecords()
	else
		local name = Share:GetUnitPlayerName(unit)
		card = name and players[name] and players[name].card
		hasBackstory = name and Share:HasBackstory(name)
	end
	if card then
		tooltip:AddLine(string.format("|T%s:14|t %s", Share.ICON, Share:FormatCard(card)), 1, 0.82, 0)
	end
	if hasBackstory then
		tooltip:AddLine(string.format("|T%s:14|t Has a backstory (/fc read)", Share.ICON), 1, 0.82, 0)
	end
end

ns.RegisterEvent("PLAYER_LOGIN", function()
	C_ChatInfo.RegisterAddonMessagePrefix(COMMS_PREFIX)
	if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum.TooltipDataType then
		TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, AddTooltipLine)
	end
end)
