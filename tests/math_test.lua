-- Offline test of pure math. Run: lua tests/math_test.lua
local M = {}
local chunk = assert(loadfile("Meridian/Canvas.lua"))
-- stub the WoW globals Canvas.lua touches at load time (none, but keep Canvas class unused)
chunk("Meridian", M)
local Math = M.Math

local function eq(a, b, msg) assert(math.abs(a - b) < 1e-9, msg .. ": " .. a .. " ~= " .. b) end

-- zooming around a point keeps that canvas point fixed on screen
local ox, oy, z = -100, -50, 1
local cx, cy = 300, 200
local canvasX = (cx - ox) / z
local nx, ny = Math.zoomAround(ox, oy, z, 2, cx, cy)
eq((cx - nx) / 2, canvasX, "zoom keeps anchor x")
eq((cy - ny) / 2, (cy - oy) / z, "zoom keeps anchor y")

-- clamp: canvas larger than viewport can't expose empty space
local x, y = Math.clampOffset(50, 50, 1, 2000, 1000, 800, 600)
eq(x, 0, "clamp x max"); eq(y, 0, "clamp y max")
x, y = Math.clampOffset(-5000, -5000, 1, 2000, 1000, 800, 600)
eq(x, -1200, "clamp x min"); eq(y, -400, "clamp y min")
-- canvas smaller than viewport may sit anywhere in the slack
x = Math.clampOffset(10, 0, 1, 400, 300, 800, 600)
eq(x, 10, "small canvas free")

local px, py = Math.toCanvas(0.5, 0.25, 1000, 800)
eq(px, 500, "toCanvas x"); eq(py, 200, "toCanvas y")
print("ok")

-- geometry: two far-apart groups -> two areas; a lone point gets the minimum radius
local G2 = {}
assert(loadfile("Meridian/Geometry.lua"))("Meridian", G2)
local a = G2.Geometry.areas({ {0.1, 0.1}, {0.12, 0.1}, {0.9, 0.9} })
assert(#a == 2, "two clusters, got " .. #a)
eq(a[1].x, 0.11, "cluster center x")
assert(a[2].radius >= 0.015, "min radius")
assert(#G2.Geometry.areas({}) == 0, "empty")
print("geometry ok")

-- world axes: map-x -> world y (negated), map-y -> world x (negated), like Azeroth
local ax, sx, ay, sy = Math.worldAxes({1000, 500}, {1000, 100}, {400, 500})
assert(ax == 2 and sx == -1 and ay == 1 and sy == -1, "worldAxes")
print("axes ok")

assert(Math.pow2(1) == 1 and Math.pow2(200) == 256 and Math.pow2(256) == 256 and Math.pow2(257) == 512, "pow2")
print("pow2 ok")

-- bearing: target due north (dy<0) -> 0; due west (dx<0) -> +pi/2 (CCW); due east -> -pi/2
local bearing = Math.bearing
eq(Math.wrap(3 * math.pi / 2), -math.pi / 2, "wrap")
eq(bearing(0, -10), 0, "north"); eq(bearing(-10, 0), math.pi / 2, "west"); eq(bearing(10, 0), -math.pi / 2, "east")

-- eligibility (Data.lua is loadable offline: it only touches WoW globals inside functions)
local DM = {}
assert(loadfile("Meridian/Data.lua"))("Meridian", DM)
local D = DM.Data
local done = { [10] = true }
local P = { level = 20, greyRange = 7, raceMask = 1, classMask = 4,
    done = function(id) return done[id] end, inLog = function(id) return id == 99 end }
local function q(t) t.id = t.id or 1; return t end
assert(D.eligible(q{ level = 20, reqLevel = 18 }, P), "basic")
assert(not D.eligible(q{ reqLevel = 25 }, P), "too low level")
assert(not D.eligible(q{ level = 5 }, P), "grey quest")
assert(not D.eligible(q{ id = 10 }, P), "already done")
assert(not D.eligible(q{ id = 99 }, P), "in log")
assert(not D.eligible(q{ races = 2 }, P), "wrong race")
assert(D.eligible(q{ races = 3 }, P), "race mask hit")
assert(not D.eligible(q{ classes = 1 }, P), "wrong class")
assert(D.eligible(q{ group = { 10 } }, P), "prereq group met")
assert(not D.eligible(q{ group = { 10, 11 } }, P), "prereq group unmet")
assert(D.eligible(q{ single = { 11, 10 } }, P), "single prereq one met")
assert(not D.eligible(q{ single = { 11, 12 } }, P), "single prereq none met")
assert(not D.eligible(q{ exclusive = { 10 } }, P), "exclusive done")
assert(D.anyBit(5, 4) and not D.anyBit(5, 2), "anyBit")
print("eligibility ok")

-- waypoints: /way parsing, formatting, zone-name matching
local WM = { Overlay = { RegisterSource = function() end } }
assert(loadfile("Meridian/Waypoints.lua"))("Meridian", WM)
local P = WM.Way.parse
local r = P("52.3 41.2")
eq(r.x, 0.523, "way x"); eq(r.y, 0.412, "way y"); assert(not r.zone and not r.title, "plain way")
r = P("Elwynn Forest 52, 41 Goldshire inn")
assert(r.zone == "Elwynn Forest" and r.title == "Goldshire inn", "zone and title")
eq(r.x, 0.52, "zone x")
r = P("#37 10 20")
assert(r.map == 37 and not r.zone, "map id form"); eq(r.y, 0.2, "map id y")
assert(P("clear").cmd == "clear" and P("RESET").cmd == "clear" and P("").cmd == "help" and P("list").cmd == "list", "commands")
assert(not P("52"), "needs two coords")
assert(not P("150 20"), "out of range")
r = P("(0.5, 0.25)")
eq(r.x, 0.5, "fraction x"); eq(r.y, 0.25, "fraction y")
assert(WM.Way.format("Elwynn Forest", 0.523, 0.412) == "/way Elwynn Forest 52.3 41.2", "format")
assert(WM.Way.format(nil, 0.5, 0.5) == "/way 50.0 50.0", "format bare")
local maps = { { name = "Stormwind City", id = 1 }, { name = "Elwynn Forest", id = 2 }, { name = "Northern Elwynn Pass", id = 3 } }
assert(WM.Way.matchName("elwynn forest", maps) == 2, "exact")
assert(WM.Way.matchName("storm", maps) == 1, "prefix")
assert(WM.Way.matchName("pass", maps) == 3, "substring")
assert(WM.Way.matchName("zzz", maps) == nil, "no match")
print("waypoints ok")

-- scale change keeps the window centre fixed on screen: screen position = center * scale
local rx, ry = Math.rescaleCenter(400, 300, 1, 1.25)
eq(rx * 1.25, 400, "rescale x"); eq(ry * 1.25, 300, "rescale y")
print("rescale ok")

-- minimap button placement round-trips through angle
local ex, ey = Math.edgePos(90, 50)
eq(ex, 0, "edge x"); eq(ey, 50, "edge y")
eq(Math.angleTo(ex, ey), 90, "angle back")
ex, ey = Math.edgePos(225, 10)
eq(Math.angleTo(ex, ey), -135, "angle wraps to -180..180")
print("edge ok")

-- quest list: progress text, labels, sorting, zone grouping
local TM = {}
assert(loadfile("Meridian/Tracker.lua"))("Meridian", TM)
local T = TM.Tracker
assert(T.progress({ { text = "a", finished = true }, { text = "b" }, { text = "" } }) == "1/2", "progress")
assert(T.progress({}) == nil and T.progress(nil) == nil, "no objectives")
assert(T.label({ title = "Wolves", level = 7, progress = "1/3" }) == "[7] Wolves  1/3", "label progress")
assert(T.label({ title = "Wolves", level = 7, complete = true }) == "[7] Wolves - done", "label done")
assert(T.label({ title = "Wolves" }) == "Wolves", "label bare")
local function ents()
    return { { idx = 1, title = "A", level = 9, zone = "Westfall", questID = 1 },
             { idx = 2, title = "B", level = 5, zone = "Elwynn", questID = 2 },
             { idx = 3, title = "C", level = 7, zone = "Westfall", questID = 3 },
             { idx = 4, title = "D", level = 3, zone = "Elwynn", questID = 4 } }
end
local function ids(l) local o = {} for _, e in ipairs(l) do o[#o + 1] = e.title end return table.concat(o) end
assert(ids(T.sortEntries(ents(), "zone")) == "DBCA", "sort zone then level")
assert(ids(T.sortEntries(ents(), "level")) == "DBCA", "sort level")
assert(ids(T.sortEntries(ents(), "log")) == "ABCD", "sort log")
local dist = { [1] = 50, [3] = 10 } -- 2 and 4 unknown: last, in log order
assert(ids(T.sortEntries(ents(), "distance", function(id) return dist[id] end)) == "CABD", "sort distance")
local rows = T.buildRows(T.sortEntries(ents(), "zone"), "zone", { Westfall = true })
assert(#rows == 4 and rows[1].header == "Elwynn" and rows[1].count == 2 and rows[2].entry.title == "D", "zone rows")
assert(rows[4].header == "Westfall" and rows[4].collapsed and rows[4].count == 2, "collapsed zone has header only")
assert(#T.buildRows(ents(), "level") == 4, "flat rows")
print("quest list ok")

-- tooltip text builders (Tooltips.lua creates one event frame at load, so stub CreateFrame for the load)
CreateFrame = function() return { RegisterEvent = function() end, SetScript = function() end } end
local TipM = {}
assert(loadfile("Meridian/Tooltips.lua"))("Meridian", TipM)
CreateFrame = nil
local Tip = TipM.Tip
assert(Tip.moneyText(12345) == "1g 23s 45c" and Tip.moneyText(100) == "1s" and Tip.moneyText(0) == nil, "money")
local names = { [10] = "Wolves", [11] = "Boars", [12] = "Bears" }
local nameOf = function(id) return names[id] end
local lines = Tip.chainLines({ reqLevel = 8, group = { 10, 11 }, single = { 12 }, exclusive = { 99 } }, nameOf, 11)
assert(lines[1] == "Requires level 8" and lines[2] == "After all of: Wolves, Boars" and lines[3] == "After: Bears", "chain lines")
assert(lines[4] == "Not with: Quest 99" and lines[5] == "Leads to: Boars", "chain tail")
assert(Tip.chainLines({ single = { 10, 11 } }, nameOf)[1] == "After one of: Wolves, Boars", "one of")
assert(#Tip.chainLines({}, nameOf) == 0, "no chain")
assert(Tip.levelRange(12, 14) == "12-14" and Tip.levelRange(12, 12) == "12" and Tip.levelRange(nil) == nil, "level range")
print("tooltips ok")
