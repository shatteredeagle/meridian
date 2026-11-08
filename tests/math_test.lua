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
