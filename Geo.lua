local _, ns = ...

-- Conversion between world coordinates (yards, per continent) and the 0-1
-- coordinates of any uiMap. Routes are stored in world coordinates so one
-- recording draws correctly on zone and continent maps alike.
local Geo = {}
ns.Geo = Geo

local transforms = {}

function Geo.Distance(x1, y1, x2, y2)
	local dx, dy = x2 - x1, y2 - y1
	return math.sqrt(dx * dx + dy * dy)
end

-- Builds an affine transform from the world positions of a map's corners
-- (0,0), (1,0) and (0,1). Solving it generally avoids caring which world axis
-- runs which way on screen.
function Geo.SolveTransform(continentID, ox, oy, rx, ry, dx, dy)
	local ax, ay = rx - ox, ry - oy
	local bx, by = dx - ox, dy - oy
	local det = ax * by - ay * bx
	if det == 0 then
		return nil
	end
	return { c = continentID, ox = ox, oy = oy, ax = ax, ay = ay, bx = bx, by = by, det = det }
end

function Geo.WorldToMap(t, x, y)
	local px, py = x - t.ox, y - t.oy
	return (px * t.by - py * t.bx) / t.det, (t.ax * py - t.ay * px) / t.det
end

local function CornerWorldPos(mapID, u, v)
	local continentID, worldPos = C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(u, v))
	if continentID and worldPos then
		local x, y = worldPos:GetXY()
		return continentID, x, y
	end
end

-- Returns nil for maps without world coordinates (the cosmic and world maps).
function Geo.GetMapTransform(mapID)
	if not mapID then
		return nil
	end
	local t = transforms[mapID]
	if t == nil then
		t = false
		local ok, c0, ox, oy, c1, rx, ry, c2, dx, dy = pcall(function()
			local c0, ox, oy = CornerWorldPos(mapID, 0, 0)
			local c1, rx, ry = CornerWorldPos(mapID, 1, 0)
			local c2, dx, dy = CornerWorldPos(mapID, 0, 1)
			return c0, ox, oy, c1, rx, ry, c2, dx, dy
		end)
		if ok and c0 and c0 == c1 and c0 == c2 then
			t = Geo.SolveTransform(c0, ox, oy, rx, ry, dx, dy) or false
		end
		transforms[mapID] = t
	end
	return t or nil
end
