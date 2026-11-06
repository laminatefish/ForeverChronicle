local _, ns = ...

-- A read-only window for another player's backstory, on the same parchment
-- as the journal's Backstory tab.
local Reader = {}
ns.Reader = Reader

local WIDTH, HEIGHT = 360, 420
local PADDING = 8

function Reader:Create()
	local f = CreateFrame("Frame", "ForeverChronicleReader", UIParent, "ButtonFrameTemplate")
	f:SetSize(WIDTH, HEIGHT)
	f:SetPoint("CENTER")
	f:SetToplevel(true)
	f:SetMovable(true)
	f:SetClampedToScreen(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	table.insert(UISpecialFrames, f:GetName())

	ButtonFrameTemplate_HideButtonBar(f)
	f:SetPortraitToAsset(ns.Share.ICON)

	f.subtitle = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	f.subtitle:SetPoint("TOPLEFT", 66, -36)
	f.subtitle:SetPoint("RIGHT", -12, 0)
	f.subtitle:SetJustifyH("LEFT")
	f.subtitle:SetText("A backstory shared through " .. ns.title)

	local parchment = f.Inset:CreateTexture(nil, "BACKGROUND", nil, 1)
	parchment:SetAtlas("QuestBG-Parchment")
	parchment:SetPoint("TOPLEFT", 3, -3)
	parchment:SetPoint("BOTTOMRIGHT", -3, 3)

	local scroll = CreateFrame("ScrollFrame", nil, f.Inset, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", PADDING + 4, -PADDING - 4)
	scroll:SetPoint("BOTTOMRIGHT", -PADDING - 26, PADDING + 4)

	local child = CreateFrame("Frame", nil, scroll)
	child:SetSize(WIDTH - 70, 1)
	scroll:SetScrollChild(child)

	f.text = child:CreateFontString(nil, "OVERLAY", "QuestFont")
	f.text:SetPoint("TOPLEFT")
	f.text:SetWidth(WIDTH - 70)
	f.text:SetJustifyH("LEFT")
	f.text:SetSpacing(2)
	f.child, f.scroll = child, scroll

	f.status = f.Inset:CreateFontString(nil, "OVERLAY", "QuestFont")
	f.status:SetPoint("LEFT", 24, 0)
	f.status:SetPoint("RIGHT", -24, 0)

	self.frame = f
end

function Reader:Open(name)
	if not self.frame then
		self:Create()
	end
	self.name = name
	self.frame:SetTitle(name)
	self.frame:Show()
end

-- Updates only apply to the backstory being read

function Reader:ShowStatus(name, status)
	local f = self.frame
	if not (f and f:IsShown() and self.name == name) then
		return
	end
	f.text:SetText("")
	f.status:SetText(status)
	f.status:Show()
end

function Reader:ShowText(name, text)
	local f = self.frame
	if not (f and f:IsShown() and self.name == name) then
		return
	end
	f.status:Hide()
	-- Shown literally: "||" stops escape codes in someone else's text from
	-- turning into links, textures or colours
	f.text:SetText((text:gsub("|", "||")))
	f.child:SetHeight(f.text:GetStringHeight() + PADDING)
	f.scroll:SetVerticalScroll(0)
end
