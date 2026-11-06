local _, ns = ...

-- Samples the player's position and stores it as route segments. A new
-- segment starts on level-up, boarding or leaving a flight path, teleports,
-- and continent changes, so each can be drawn in its own style. A teleport
-- within a continent (hearthstone, portal, release to a graveyard) is kept as
-- a two-point "teleport" segment joining where the player left and arrived.
local Recorder = {}
ns.Recorder = Recorder

local SAMPLE_INTERVAL = 2      -- seconds between position checks
local MIN_DISTANCE = 15        -- yards moved before another point is stored
local TELEPORT_SPEED = 80      -- yards per second; faster than any mount or flight path
local RECONNECT_DISTANCE = 200 -- after a gap (instance, loading screen, combat), rejoin the route if this close

local function Round(value)
	return math.floor(value * 10 + 0.5) / 10
end

-- Returns continentID, worldX, worldY, uiMapID, or nil when the position is
-- unavailable: inside instances, or when the client returns secret values.
function Recorder:ReadPosition()
	local ok, c, x, y, mapID = pcall(function()
		local mapID = C_Map.GetBestMapForUnit("player")
		if not ns.IsReadable(mapID) then
			return
		end
		local mapPos = C_Map.GetPlayerMapPosition(mapID, "player")
		if not mapPos then
			return
		end
		local mx, my = mapPos:GetXY()
		if not (ns.IsReadable(mx) and ns.IsReadable(my)) then
			return
		end
		local continentID, worldPos = C_Map.GetWorldPosFromMapPos(mapID, mapPos)
		if not (continentID and worldPos) then
			return
		end
		local wx, wy = worldPos:GetXY()
		return continentID, wx, wy, mapID
	end)
	if ok and c then
		return c, x, y, mapID
	end
end

-- The most recent outdoor position, used to place events that happen where
-- the position can't be read (deaths in dungeons, for example).
function Recorder:GetLastKnownPosition()
	return self.lastC, self.lastX, self.lastY, self.lastMapID
end

local function Append(seg, x, y)
	local n = #seg.x + 1
	seg.x[n], seg.y[n] = x, y
	seg.t1 = time()
end

function Recorder:Tick()
	if not ns.settings.recording then
		return
	end

	local c, x, y, mapID = self:ReadPosition()
	if not c then
		self.gap = true
		return
	end
	x, y = Round(x), Round(y)

	local now = GetTime()
	local kind = UnitOnTaxi("player") and "taxi" or "ground"
	local level = UnitLevel("player")
	local seg = self.segment

	-- Does this point continue the existing route, or is it a jump?
	local connected, dist = false, 0
	if seg and seg.c == c then
		local n = #seg.x
		dist = ns.Geo.Distance(seg.x[n], seg.y[n], x, y)
		if self.gap or not self.lastTime then
			connected = dist <= RECONNECT_DISTANCE
		else
			local jump = ns.Geo.Distance(self.lastX, self.lastY, x, y)
			connected = jump / math.max(now - self.lastTime, 0.1) <= TELEPORT_SPEED
		end
	end
	self.lastC, self.lastX, self.lastY, self.lastMapID = c, x, y, mapID
	self.lastTime, self.gap = now, false

	if connected and seg.kind == kind and seg.level == level then
		if dist < MIN_DISTANCE then
			return
		end
		Append(seg, x, y)
	else
		if seg and seg.c == c and not connected then
			local jump = { c = c, kind = "teleport", level = level, t0 = time(), x = {}, y = {} }
			Append(jump, seg.x[#seg.x], seg.y[#seg.y])
			Append(jump, x, y)
			table.insert(ns.char.segments, jump)
		end
		local newSeg = { c = c, kind = kind, level = level, t0 = time(), x = {}, y = {} }
		if connected then
			-- Start from the previous point so the line stays continuous
			Append(newSeg, seg.x[#seg.x], seg.y[#seg.y])
		end
		Append(newSeg, x, y)
		table.insert(ns.char.segments, newSeg)
		self.segment = newSeg
	end

	if connected then
		ns.char.stats.distance = ns.char.stats.distance + dist
	end
	ns.Fire("ROUTE_UPDATED")
end

function Recorder:Start()
	local segments = ns.char.segments
	local seg = segments[#segments]
	self.segment = seg
	if seg then
		self.lastC, self.lastX, self.lastY = seg.c, seg.x[#seg.x], seg.y[#seg.y]
	end
	self.gap = true
	if not self.ticker then
		self.ticker = C_Timer.NewTicker(SAMPLE_INTERVAL, function()
			self:Tick()
		end)
	end
end

ns.RegisterEvent("PLAYER_LOGIN", function()
	Recorder:Start()
end)

ns.RegisterEvent("PLAYER_ENTERING_WORLD", function()
	Recorder.gap = true
end)
