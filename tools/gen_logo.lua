-- Draws the Meridian logo as 50x50 pixel art. Run from the repo root:
--   aseprite -b --script tools/gen_logo.lua   (see tools/build_logo.sh for the PNG exports)
local W = 50
local spr = Sprite(W, W, ColorMode.RGB)
local img = spr.cels[1].image

local function C(hex) return Color{ r = tonumber(hex:sub(1, 2), 16), g = tonumber(hex:sub(3, 4), 16), b = tonumber(hex:sub(5, 6), 16), a = 255 } end
local P = {
  bg = C("120d08"), bg2 = C("1d150b"), rim = C("6b4d17"),
  g0 = C("2a1d0e"), g1 = C("3d2b14"), g2 = C("55401f"), g3 = C("70522a"),
  gold = C("d49a2a"), light = C("ffe08a"), mid = C("f2c14e"),
  pin = C("7dff7d"), pinD = C("0e3a0e"), pinL = C("d8ffd8"),
}
local function put(x, y, c) if x >= 0 and y >= 0 and x < W and y < W then img:putPixel(x, y, c) end end

-- Background: rounded square with a dim gold rim and a faint lower-right shade.
local R = 9
for y = 0, W - 1 do for x = 0, W - 1 do
  local cx, cy = math.min(math.max(x, R), W - 1 - R), math.min(math.max(y, R), W - 1 - R)
  local d = math.sqrt((x - cx) ^ 2 + (y - cy) ^ 2)
  if d <= R + 0.5 then
    local c = P.bg
    if (x + y) % 2 == 0 and x + y > W then c = P.bg2 end
    if d > R - 1 then c = P.rim end
    put(x, y, c)
  end
end end

-- Globe.
local gx, gy, gr = 25, 26, 17
local bayer = { { 0, 2 }, { 3, 1 } }
for y = 0, W - 1 do for x = 0, W - 1 do
  local dx, dy = x - gx, y - gy
  local d = math.sqrt(dx * dx + dy * dy)
  if d <= gr + 0.3 then
    local hl = math.sqrt((x - (gx - 6)) ^ 2 + (y - (gy - 7)) ^ 2) / (gr * 1.5) -- 0 at the highlight
    local t = hl * 4 + (bayer[y % 2 + 1][x % 2 + 1] - 1.5) * 0.35
    put(x, y, t < 1 and P.g3 or t < 2 and P.g2 or t < 3 and P.g1 or P.g0)
  end
end end

-- Longitude / latitude lines (1 px, gold), clipped to the globe.
local function ellipse(rx, ry, c, dash)
  for y = 0, W - 1 do for x = 0, W - 1 do
    local dx, dy = (x - gx) / rx, (y - gy) / ry
    local e = math.sqrt(dx * dx + dy * dy)
    local ring = math.abs(e - 1) * math.min(rx, ry)
    local dd = math.sqrt((x - gx) ^ 2 + (y - gy) ^ 2)
    if ring < 0.55 and dd < gr - 0.4 and (not dash or (x + y) % 2 == 0) then put(x, y, c) end
  end end
end
ellipse(12, 17, P.gold)
ellipse(7, 17, P.gold)
for x = gx - gr + 1, gx + gr - 1 do put(x, gy, P.gold) end -- equator
for y = gy - gr + 1, gy + gr - 1 do put(gx, y, P.mid); put(gx + 1, y, P.mid) end -- prime meridian, 2 px

-- Globe rim: light on the upper-left, darker gold lower-right.
for y = 0, W - 1 do for x = 0, W - 1 do
  local dx, dy = x - gx, y - gy
  local d = math.sqrt(dx * dx + dy * dy)
  if math.abs(d - gr) < 0.7 then put(x, y, (dx + dy < 0) and P.light or P.mid) end
end end

-- Compass ticks.
for i = 0, 3 do
  put(gx, 4 + i, P.light); put(gx + 1, 4 + i, P.light)
  put(gx, 42 + i, P.mid); put(gx + 1, 42 + i, P.mid)
  put(3 + i, gy, P.mid); put(44 + i, gy, P.mid)
end

-- Map pin, 11 wide, on the prime meridian near the top.
local pin = {
  "...00000...",
  "..0AAAAA0..",
  ".0AAAAAAA0.",
  ".0AALLAAA0.",
  "0AAALLAAAA0",
  "0AAAAAAAAA0",
  "0AAA000AAA0",
  "0AAA000AAA0",
  ".0AA000AA0.",
  ".0AAAAAAA0.",
  "..0AAAAA0..",
  "...0AAA0...",
  "....0A0....",
  ".....0.....",
}
local ox, oy = gx - 4, 11
for j, row in ipairs(pin) do for i = 1, #row do
  local ch = row:sub(i, i)
  local c = ch == "0" and P.pinD or ch == "A" and P.pin or ch == "L" and P.pinL or nil
  if c then put(ox + i - 1, oy + j - 1, c) end
end end

spr:saveAs("docs/logo/logo.aseprite")
