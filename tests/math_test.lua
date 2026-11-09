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
local a = G2.Geometry.areas({ {0.1, 0.1}, {0.12, 0.1}, {0.1, 0.12}, {0.12, 0.12}, {0.9, 0.9} })
assert(#a == 2, "camp + lone spawn, got " .. #a)
eq(a[1].x, 0.11, "cluster center x")
assert(a[2].radius >= 0.007, "lone spawn is a dot")
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
assert(loadfile("Meridian/Locale.lua"))("Meridian", TM)
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

-- palettes
local OM = {}
assert(loadfile("Meridian/Overlay.lua"))("Meridian", OM)
local O = OM.Overlay
local r1, g1, b1 = O.paletteColor("cb", 1)
local r9, g9, b9 = O.paletteColor("cb", 9)
assert(r1 == r9 and g1 == g9 and b1 == b9, "cb palette cycles every 8")
local ra = { O.paletteColor("cb", 0) }
local rb = { O.paletteColor("cb", 1) }
assert(ra[1] ~= rb[1] or ra[2] ~= rb[2], "cb neighbours differ")
for id = 1, 50 do
    local r, g, b = O.paletteColor("default", id)
    assert(r >= 0 and r <= 1 and g >= 0 and g <= 1 and b >= 0 and b <= 1, "default palette range")
end
local gr = O.markerColor("give", "cb")
local gd = O.markerColor("give", "default")
assert(gr ~= gd, "marker palettes differ")
print("palette ok")

-- controller math
local PM = { Math = Math }
assert(loadfile("Meridian/Controller.lua"))("Meridian", PM)
local Pd = PM.Pad
local dx0, dy0 = Pd.panDelta(0.1, 0.1, 0.1, 600)
assert(dx0 == 0 and dy0 == 0, "dead zone")
local dx1, dy1 = Pd.panDelta(1, 0, 0.1, 600)
eq(dx1, -60, "full right pans canvas left"); eq(dy1, 0, "no vertical")
local _, dy2 = Pd.panDelta(0, 1, 0.5, 600)
eq(dy2, 300, "full up moves canvas down")
local hx = Pd.panDelta(0.6, 0, 1, 100)
assert(hx > -25 and hx < 0, "squared response is gentle")
assert(Pd.cycle(nil, 3, 1) == 1 and Pd.cycle(nil, 3, -1) == 3 and Pd.cycle(3, 3, 1) == 1 and Pd.cycle(1, 3, -1) == 3 and Pd.cycle(2, 0, 1) == nil, "cycle")
print("controller ok")

-- search ranking
local SM = { Overlay = { RegisterSource = function() end } }
assert(loadfile("Meridian/Search.lua"))("Meridian", SM)
local Se = SM.Search
assert(Se.score("wolf", "Wolf") == 100 and Se.score("wo", "Wolf") == 80 and Se.score("pack", "Wolf Pack") == 60 and Se.score("olf", "Wolf") == 40, "score tiers")
assert(Se.score("zzz", "Wolf") == nil and Se.score("", "Wolf") == nil, "score miss")
local items = {
    { kind = "quest", name = "Wolves of the Pack" }, { kind = "zone", name = "Wolf Hollow" },
    { kind = "npc", name = "Wolf Tender" }, { kind = "quest", name = "Wolf" }, { kind = "quest", name = "Boars" },
}
local ranked = Se.rank("wolf", items, 10)
assert(#ranked == 3 and ranked[1].name == "Wolf", "exact first")
assert(ranked[2].kind == "zone" and ranked[3].kind == "npc", "kind order within a tier")
assert(#Se.rank("wolf", items, 2) == 2, "limit")
assert(Se.rank("  wolf  ", items, 10)[1].name == "Wolf", "trims")
assert(Se.rowText({ kind = "quest", name = "Wolf", level = 5 }) == "[Quest] Wolf (5)" and Se.rowText({ kind = "zone", name = "X" }) == "[Zone] X", "row text")
print("search ok")

-- pin helpers
local PinM = { Overlay = { RegisterSource = function() end } }
assert(loadfile("Meridian/Pins.lua"))("Meridian", PinM)
local ax_, ay_ = PinM.Pins.xy({ x = 0.2, y = 0.4 })
eq(ax_, 0.2, "xy plain x"); eq(ay_, 0.4, "xy plain y")
ax_, ay_ = PinM.Pins.xy({ GetXY = function() return 0.5, 0.6 end })
eq(ax_, 0.5, "xy method"); eq(ay_, 0.6, "xy method y")
assert(PinM.Pins.xy(nil) == nil and PinM.Pins.xy({}) == nil, "xy missing")
print("pins ok")

-- dungeons: names, floor grouping, tile layout, entrance grouping, quest matching
local DM = { Overlay = { RegisterSource = function() end } }
assert(loadfile("Meridian/Locale.lua"))("Meridian", DM)
assert(loadfile("Meridian/Dungeons.lua"))("Meridian", DM)
local Dg = DM.Dungeons
assert(Dg.norm("Razorfen  Kraul!") == "razorfenkraul" and Dg.norm(nil) == "", "norm")
assert(Dg.baseName("Scarlet Monastery: Library") == "Library" and Dg.baseName("Gnomeregan") == "Gnomeregan", "base name")
assert(Dg.nameMatches("Gnomeregan", "gnomeregan") and Dg.nameMatches("Dire Maul", "Dire Maul: East"), "name match")
assert(not Dg.nameMatches("Wolf", "Wolfsbane Keep") and not Dg.nameMatches("", "x") and not Dg.nameMatches("Deadmines", "Stockade"), "name mismatch")
local groups = Dg.groupFloors({
    { mapID = 229, name = "Gnomeregan", group = 7, order = 3 }, { mapID = 226, name = "Gnomeregan", group = 7, order = 1 },
    { mapID = 227, name = "Gnomeregan", group = 7, order = 2 }, { mapID = 300, name = "Razorfen Downs" },
    { mapID = 301, name = "Razorfen Kraul" }, { mapID = 302, name = "Razorfen Kraul" }, { mapID = 226, name = "dupe", group = 7 } })
assert(#groups == 3 and groups[1].name == "Gnomeregan" and #groups[1].floors == 3, "group by id")
assert(groups[1].floors[1].mapID == 226 and groups[1].floors[3].mapID == 229, "floors sorted by order")
assert(groups[3].name == "Razorfen Kraul" and #groups[3].floors == 2 and groups[2].floors[1].mapID == 300, "group by name")
local specs = Dg.tileSpecs(1002, 668, 256, 4, 3)
assert(#specs == 12 and specs[1].index == 1 and specs[12].index == 12, "tile count")
eq(specs[4].w, 234, "clipped width"); eq(specs[4].u, 234 / 256, "clipped u"); eq(specs[12].h, 156, "clipped height")
eq(specs[5].x, 0, "row 2 starts at 0"); eq(specs[5].y, 256, "row 2 y")
assert(#Dg.tileSpecs(256, 256, 256, 4, 3) == 1, "small art skips empty tiles")
local sw, sh = Dg.customSize({ tiles = "x" })
assert(sw == 1002 and sh == 668, "tile size")
sw, sh = Dg.customSize({ texture = "x", texBottom = 683 / 1024 })
assert(sw == 1002 and sh == 668, "texture 3:2 size")
sw, sh = Dg.customSize({ texture = "x", texBottom = 1365 / 2048 })
assert(sw == 1002 and sh == 668, "2048 texture size")
local eg = Dg.groupEntrances({ { map = 5, x = 0.826, y = 0.338, id = 1 }, { map = 5, x = 0.8263, y = 0.3379, id = 2 }, { map = 5, x = 0.2, y = 0.2, id = 3 }, { map = 6, x = 0.826, y = 0.338, id = 4 } })
assert(#eg == 3 and #eg[1].items == 2 and eg[1].items[2].id == 2, "entrances at one spot share a marker")
local quests = { { id = 1, name = "A", turnin = "Captain Truman, near the entrance", pickup = "Captain Truman", level = 20, requires = 15, faction = "Both" },
    { id = 2, name = "B", turnin = "Someone else", pickup = "Someone else" }, { id = 3, name = "C", turnin = "captain truman", pickup = "x", level = 30, faction = "Horde" } }
local ready = function(id) return id == 1 or id == 3 end
local tq = Dg.turninQuests("Captain Truman", quests, ready)
assert(#tq == 2 and tq[1].id == 1 and tq[2].id == 3, "turn-ins match case-insensitively and need ready")
assert(#Dg.turninQuests("Captain Truman", quests, function() return false end) == 0, "none ready")
local pl = { level = 20, faction = "Alliance", greyRange = 7, done = function(id) return id == 9 end, logged = function(id) return id == 8 end }
assert(Dg.canOffer(quests[1], pl), "offer ok")
assert(not Dg.canOffer(quests[1], { level = 10, faction = "Alliance", done = pl.done, logged = pl.logged }), "level too low")
assert(not Dg.canOffer(quests[3], pl), "wrong faction")
assert(not Dg.canOffer({ id = 9 }, pl) and not Dg.canOffer({ id = 8 }, pl), "done or logged")
assert(not Dg.canOffer({ id = 5, level = 5 }, pl), "grey quest")
assert(#Dg.offerQuests("Captain Truman", quests, function(q) return Dg.canOffer(q, pl) end) == 1, "offer quests")
local cx, cy = Dg.rectCenter(0.2, 0.4, 0.5, 0.7)
eq(cx, 0.3, "rect centre x"); eq(cy, 0.6, "rect centre y")
assert(Dg.rectCenter(0, 0, 0, 0) == nil and Dg.rectCenter(nil, 1, 0, 1) == nil, "empty rect")
local sitems = Dg.searchItems({ { name = "Gnomeregan" }, { name = "Deadmines" } })
assert(#sitems == 2 and sitems[1].kind == "dungeon" and sitems[2].name == "Deadmines", "search items")
assert(Se.rank("gnom", sitems, 5)[1].name == "Gnomeregan" and Se.rowText(sitems[1]) == "[Dungeon] Gnomeregan", "dungeons are searchable")
print("dungeons ok")

-- localization: missing keys fall back to the English text; every L["..."] in the code is listed in enUS.lua
local LM = {}
assert(loadfile("Meridian/Locale.lua"))("Meridian", LM)
assert(LM.L["Anything at all"] == "Anything at all", "fallback returns the key")
GetLocale = function() return "deDE" end
assert(loadfile("Meridian/Locales/deDE.lua"))("Meridian", LM)
GetLocale = nil
assert(LM.L["Zoom in"] ~= "Zoom in" and LM.L["Anything at all"] == "Anything at all", "translated and untranslated keys")
local en = {}
for k in io.open("Meridian/Locales/enUS.lua"):read("*a"):gmatch('\nL%["(.-)"%] = ') do en[k] = true end
local missing = {}
local files = io.popen("ls Meridian/*.lua"):read("*a")
for path in files:gmatch("%S+") do
    for k in io.open(path):read("*a"):gmatch('%f[%w_]L%["(.-)"%]') do
        if not en[k] then missing[#missing + 1] = path .. ": " .. k end
    end
end
assert(#missing == 0, "strings missing from enUS.lua (run tools/extract_strings.py): " .. table.concat(missing, "; "))
-- every shipped locale translates every key and keeps the same % format specifiers in the same order
local function specs(s) local t = {} for sp in s:gmatch("%%[%-%+ #0]*%d*%.?%d*[%a%%]") do t[#t + 1] = sp end return table.concat(t, ",") end
local enList = {}
for k in io.open("Meridian/Locales/enUS.lua"):read("*a"):gmatch('\nL%["(.-)"%] = ') do enList[#enList + 1] = k end
for _, loc in ipairs({ "deDE", "frFR", "esES", "esMX", "itIT", "ptBR", "ruRU", "koKR", "zhCN", "zhTW" }) do
    local LX = {}
    assert(loadfile("Meridian/Locale.lua"))("Meridian", LX)
    GetLocale = function() return loc end
    assert(loadfile("Meridian/Locales/" .. loc .. ".lua"))("Meridian", LX)
    GetLocale = nil
    for _, k in ipairs(enList) do
        local v = rawget(LX.L, k)
        assert(v and v ~= "", loc .. " lacks a translation for: " .. k)
        assert(specs(v) == specs(k), loc .. " format specifiers differ for: " .. k)
    end
end
print("locale ok")

-- objects and short NPC lists become one small dot per spawn
local objs = G2.Geometry.areas({ {0.30, 0.30, -5}, {0.31, 0.30, -5}, {0.60, 0.60, -5}, {0.3001, 0.3001, -6} })
assert(#objs == 3, "three object dots, got " .. #objs)
for _, o in ipairs(objs) do assert(o.dot and o.radius < 0.015, "object dot is small") end
local few = G2.Geometry.areas({ {0.1, 0.1, 7}, {0.5, 0.5, 7} })
assert(#few == 2 and few[1].dot, "two mob spawns -> two dots")
local many = {}
for i = 1, 8 do many[i] = { 0.2 + i * 0.005, 0.2, 9 } end
local m1 = G2.Geometry.areas(many)
assert(#m1 == 1 and not m1[1].dot, "a mob camp stays one area")
print("dots ok")

-- eligibility: reputation and profession skill
local D = {}
assert(loadfile("Meridian/Data.lua"))("Meridian", D)
local base = { inLog = function() return false end, done = function() return false end, level = 60, greyRange = 99 }
local function st(o) for k, v in pairs(base) do o[k] = o[k] or v end return o end
local rq = { id = 1, minRep = { 72, 3000 } }
assert(D.Data.eligible(rq, st({ rep = function() return 3000 end })), "rep met")
assert(not D.Data.eligible(rq, st({ rep = function() return 2999 end })), "rep short")
assert(D.Data.eligible(rq, st({ rep = function() return nil end })), "unknown rep stays listed")
assert(not D.Data.eligible({ id = 2, maxRep = { 72, 0 } }, st({ rep = function() return 10 end })), "rep too high")
local sq = { id = 3, skill = { 171, 150 } }
assert(not D.Data.eligible(sq, st({ skill = function() return 0 end })), "no profession")
assert(not D.Data.eligible(sq, st({ skill = function() return 149 end })), "skill short")
assert(D.Data.eligible(sq, st({ skill = function() return 150 end })), "skill met")
assert(D.Data.eligible(sq, st({})), "no skill info -> listed")
print("rep/skill ok")

-- polestar route dots: spaced along a polyline, carrying the remainder across corners
local RM = {}
assert(loadfile("Meridian/Route.lua"))("Meridian", RM)
local pts = RM.Route.spaced({ {0, 0}, {10, 0}, {10, 10} }, 4)
assert(#pts == 5, "5 dots on a 20-long line at gap 4, got " .. #pts)
eq(pts[1][1], 2, "first dot half a gap in")
eq(pts[3][1], 10, "dot on the corner"); eq(pts[3][2], 0, "corner y")
assert(pts[4][1] == 10 and pts[4][2] == 4, "carry past the corner")
assert(#RM.Route.spaced({ {0, 0} }, 4) == 0, "single point has no dots")
print("route ok")
