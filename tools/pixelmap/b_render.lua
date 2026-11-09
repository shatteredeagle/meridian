-- Method B (and the base of C): composes the Eastern Kingdoms as indexed pixel art from data layers only.
-- Run through tools/pixelmap/build.sh. Params (--script-param k=v):
--   data   dir with b_land.png, b_water.png, objects.lua (tools/pixelmap/prep_b.py)
--   pal    palette .gpl (tools/pixelmap/palettes/b-terrain.gpl)
--   out    output dir: <name>.aseprite, <name>.png (full continent), tiles/r<row>_c<col>.png (256x256)
--   name   base file name
--   mode   "b" (markers only) or "c" (adds the hand-drawn landmarks from c_landmarks.lua)
local P = app.params
local DATA, OUT, NAME, MODE = P.data, P.out, P.name or "map", P.mode or "b"
local here = debug.getinfo(1, "S").source:sub(2):match("(.*/)") or "./"

-- Palette: names -> indices from the .gpl
local names, pal = {}, {}
for line in io.lines(P.pal) do
  local r, g, b, n = line:match("^%s*(%d+)%s+(%d+)%s+(%d+)%s+(%S+)")
  if r then
    pal[#pal + 1] = Color{ r = tonumber(r), g = tonumber(g), b = tonumber(b), a = 255 }
    names[n] = #pal - 1
  end
end
local function C(n) local i = names[n]; assert(i, "no colour " .. n); return i end

local land = Image{ fromFile = DATA .. "/b_land.png" }
local water = Image{ fromFile = DATA .. "/b_water.png" }
local W, H = land.width, land.height
local img = Image(W, H, ColorMode.INDEXED)
local pc = app.pixelColor
local R, G, B = pc.rgbaR, pc.rgbaG, pc.rgbaB

local BAYER = { 0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5 }
local function bayer(x, y) return (BAYER[(y % 4) * 4 + (x % 4) + 1] + 0.5) / 16 end
local function hash(x, y)
  local h = (x * 374761393 + y * 668265263) & 0xffffffff
  h = ((h ~ (h >> 13)) * 1274126177) & 0xffffffff
  return (h & 0xffff) / 65536
end
-- smooth value noise, cell size s
local function vnoise(x, y, s)
  local gx, gy = x // s, y // s
  local fx, fy = (x % s) / s, (y % s) / s
  fx, fy = fx * fx * (3 - 2 * fx), fy * fy * (3 - 2 * fy)
  local a, b = hash(gx, gy), hash(gx + 1, gy)
  local c, d = hash(gx, gy + 1), hash(gx + 1, gy + 1)
  return (a + (b - a) * fx) + ((c + (d - c) * fx) - (a + (b - a) * fx)) * fy
end

-- biome: 0 none 1 lush 2 dark 3 jungle 4 dry 5 marsh 6 plague 7 snow 8 burnt 9 city 10 red (prep_b.py BIOMES)
local GRASS = { [0] = "lush", "lush", "dark", "jungle", "dry", "plague", "plague", "dark", "ash", "lush", "dry" }
local DIRT = { [0] = "dirt", "dirt", "dirt", "dirt", "dirt", "dirt", "plague", "dirt", "ash", "dirt", "red" }
local ROCK = { [0] = "rock", "rock", "rock", "rock", "rock", "rock", "rock", "rock", "ash", "rock", "red" }
local MUD = { [0] = "dry", "dry", "dark", "jungle", "dry", "plague", "plague", "dark", "ash", "dry", "red" }
-- material: 0 void 1 grass 2 dirt 3 rock 4 sand 5 snow 6 road 7 farm 8 ash 9 lava 10 blight 11 mud 12 seabed
local NOISE = { [0] = 0.3, 0.4, 0.35, 0.5, 0.25, 0.2, 0, 0, 0.35, 0, 0, 0.35, 0.25 }

local function ramp(mat, biome)
  if mat == 1 then return GRASS[biome]
  elseif mat == 2 or mat == 0 then return DIRT[biome]
  elseif mat == 3 then return ROCK[biome]
  elseif mat == 4 or mat == 12 then return "sand"
  elseif mat == 5 then return "snow"
  elseif mat == 8 then return "ash"
  elseif mat == 11 then return MUD[biome]
  end
  return DIRT[biome]
end

local RAMPS = {}
for _, n in ipairs({ "lush", "dark", "jungle", "dry", "plague", "dirt", "red", "rock", "ash", "snow", "sand" }) do
  RAMPS[n] = { C(n .. "0"), C(n .. "1"), C(n .. "2") }
end
local OUTLINE, ROAD, FARM, BLIGHT = C("outline"), C("road"), C("farm"), C("blight")
local LAVA0, LAVA1 = C("lava0"), C("lava1")
local WBAND = { C("foam"), C("shallow"), C("mid"), C("ocean"), C("deep"), C("abyss") }
local LAKE = { C("shallow"), C("shallow"), C("mid"), C("ocean"), C("ocean"), C("ocean") }
local WCUT = { 1.5, 4.5, 11, 30, 75 } -- distance-to-land thresholds between the water bands
local function waterBand(d, x, y)
  if d < 1.5 then return 1 end
  local v = d * (0.82 + bayer(x, y) * 0.36) -- ordered dither across each threshold
  for i = 2, #WCUT do if v < WCUT[i] then return i end end
  return 6
end

local biomeAt = {} -- remembered per pixel row-major for trees/buildings (only biome, small ints)
local t0 = os.clock()
for y = 0, H - 1 do
  for x = 0, W - 1 do
    local lp, wp = land:getPixel(x, y), water:getPixel(x, y)
    local mat, biome, shade = R(lp), G(lp), B(lp)
    local liq, band, roadw = R(wp), G(wp), B(wp)
    biomeAt[y * W + x + 1] = biome
    local c
    if liq > 0 and band ~= 255 then
      if liq == 3 then
        c = (vnoise(x, y, 3) + bayer(x, y) * 0.5 > 0.95) and LAVA1 or LAVA0
      elseif liq == 4 then
        c = BLIGHT
      else
        local set = liq == 2 and WBAND or LAKE
        local b = waterBand(band, x, y)
        c = set[b]
        -- sparse wave glints: short horizontal dashes one shade lighter
        if b >= 3 and (x % 7) < 3 and hash(x // 7, y // 2) < 0.03 and y % 2 == 0 then c = set[b - 1] end
      end
    elseif band == 255 then
      c = OUTLINE
    elseif roadw >= 80 then
      c = ROAD
    elseif mat == 9 then
      c = (bayer(x, y) > 0.6) and LAVA1 or LAVA0
    elseif mat == 10 then
      c = BLIGHT
    elseif mat == 7 then
      c = ((x + 2 * y) % 4 == 0) and RAMPS.dirt[2] or FARM
    else
      local r = RAMPS[ramp(mat, biome)]
      local n = (vnoise(x, y, 9) - 0.5) * NOISE[mat] * 2 + (hash(x, y) - 0.5) * NOISE[mat] * 0.25
      local t = 1.0 + (shade - 128) / 44 + n
      local lv = math.floor(t + bayer(x, y) - 0.5 + 0.5)
      if lv < 0 then lv = 0 elseif lv > 2 then lv = 2 end
      c = r[lv + 1]
    end
    img:drawPixel(x, y, c)
  end
end
print(string.format("terrain %.1fs", os.clock() - t0))

local O = dofile(DATA .. "/objects.lua")
local function put(x, y, c) if x >= 0 and y >= 0 and x < W and y < H then img:drawPixel(x, y, c) end end
local function isWater(x, y)
  if x < 0 or y < 0 or x >= W or y >= H then return true end
  local wp = water:getPixel(x, y)
  return R(wp) > 0 and G(wp) ~= 255
end
local function biomeOf(x, y) return biomeAt[math.max(0, math.min(H - 1, y)) * W + math.max(0, math.min(W - 1, x)) + 1] or 1 end

-- Buildings (footprints from WMO bounding boxes), drawn before trees.
local SLATE = { [2] = true, [5] = true, [6] = true, [7] = true, [9] = true }
local ROOFS = { red = { C("roof0"), C("roof1") }, slate = { C("deep"), C("mid") } }
local SHADOW = C("shadow")
local nb = 0
for _, b in ipairs(O.buildings) do
  local x0, y0 = math.floor(b[1] + 0.5), math.floor(b[2] + 0.5)
  local x1, y1 = math.max(x0 + 1, math.floor(b[3] + 0.5) - 1), math.max(y0 + 1, math.floor(b[4] + 0.5) - 1)
  local kind = b[5]
  if not isWater((x0 + x1) // 2, (y0 + y1) // 2) or kind == "bridge" then
    nb = nb + 1
    local bio = biomeOf(x0, y0)
    if kind == "bridge" then
      for y = y0, y1 do for x = x0, x1 do put(x, y, ROAD) end end
    elseif kind == "ruin" then
      for y = y0, y1 do for x = x0, x1 do
        if (x + y) % 2 == 0 or x == x0 or y == y1 then put(x, y, (x + y) % 3 == 0 and RAMPS.rock[1] or RAMPS.rock[2]) end
      end end
    else
      local roof = (kind == "hut") and { RAMPS.dirt[1], RAMPS.dirt[3] }
        or (kind == "tower") and { RAMPS.rock[1], RAMPS.rock[3] }
        or (SLATE[bio] and ROOFS.slate or ROOFS.red)
      for x = x0 + 1, x1 + 1 do put(x, y1 + 1, SHADOW) end
      for y = y0 + 1, y1 + 1 do put(x1 + 1, y, SHADOW) end
      local mid = (y0 + y1) / 2
      for y = y0, y1 do for x = x0, x1 do put(x, y, y <= mid and roof[2] or roof[1]) end end
    end
  end
end

-- Trees: shadows first, then canopies north to south.
local trees = O.trees
table.sort(trees, function(a, b) return a[2] < b[2] end)
local TREE = {
  leaf = function(bio) return RAMPS[GRASS[bio] == "ash" and "dark" or GRASS[bio]] end,
  pine = function() return RAMPS.dark end,
  jungle = function() return RAMPS.jungle end,
  palm = function() return RAMPS.jungle end,
  dead = function() return RAMPS.dirt end,
  bush = function(bio) return RAMPS[GRASS[bio] == "ash" and "dark" or GRASS[bio]] end,
}
local function radius(t)
  if t[4] == "bush" then return 0 end
  local r = math.floor(t[3] * 1.2 + 0.5)
  if r < 1 then r = 1 elseif r > 3 then r = 3 end
  return r
end
local drawn = 0
for _, t in ipairs(trees) do
  local cx, cy, r = math.floor(t[1]), math.floor(t[2]), radius(t)
  if not isWater(cx, cy) and r > 0 then
    for dy = -r, r do for dx = -r, r do
      if dx * dx + dy * dy <= r * r + 0.5 then put(cx + dx + 1, cy + dy + 1, SHADOW) end
    end end
  end
end
for _, t in ipairs(trees) do
  local cx, cy, r, kind = math.floor(t[1]), math.floor(t[2]), radius(t), t[4]
  if not isWater(cx, cy) then
    local rp = TREE[kind](biomeOf(cx, cy))
    drawn = drawn + 1
    if kind == "bush" then
      put(cx, cy, rp[1])
    elseif kind == "pine" then
      for dy = -r - 1, r do
        local w = math.max(0, math.floor((dy + r + 1) / 2))
        for dx = -w, w do put(cx + dx, cy + dy, dx < 0 and rp[3] or (dx > 0 and rp[1] or rp[2])) end
      end
    elseif kind == "palm" then
      put(cx, cy, rp[2])
      for i = 1, r + 1 do
        put(cx - i, cy - (i > 1 and 1 or 0), rp[3]); put(cx + i, cy - (i > 1 and 1 or 0), rp[2])
        put(cx, cy - i, rp[3]); put(cx, cy + i, rp[1])
      end
    elseif kind == "dead" then
      put(cx, cy, rp[1]); put(cx - 1, cy - 1, rp[2]); put(cx + 1, cy - 1, rp[2]); put(cx, cy - 1, rp[1])
    else
      for dy = -r, r do for dx = -r, r do
        if dx * dx + dy * dy <= r * r + 0.5 then
          local s = dx + dy
          put(cx + dx, cy + dy, (s < -r * 0.5) and rp[3] or ((s > r * 0.5) and rp[1] or rp[2]))
        end
      end end
    end
  end
end
print(string.format("objects: %d buildings, %d trees (%.1fs)", nb, drawn, os.clock() - t0))

-- POI markers / landmarks
local L = { img = img, put = put, C = C, RAMPS = RAMPS, W = W, H = H, isWater = isWater, bayer = bayer, hash = hash,
  vnoise = vnoise, biomeOf = biomeOf }
if MODE == "c" then
  dofile(here .. "c_landmarks.lua")(L, O)
else
  -- small gate marker: dark outline, stone arch, black doorway
  local GATE = {
    ".ooooo.",
    "oSSSSSo",
    "oSddcSo",
    "oSdddSo",
    "oSdddSo",
    "ooooooo",
  }
  local map = { o = OUTLINE, S = RAMPS.rock[3], d = SHADOW, c = LAVA1 }
  for _, p in ipairs(O.pois) do
    if p.kind == "dungeon" then
      local x0, y0 = math.floor(p.x) - 3, math.floor(p.y) - 5
      for j, row in ipairs(GATE) do for i = 1, #row do
        local ch = row:sub(i, i)
        if map[ch] then put(x0 + i - 1, y0 + j - 1, map[ch]) end
      end end
    end
  end
end

-- Output
local p = Palette(#pal)
for i, c in ipairs(pal) do p:setColor(i - 1, c) end
local tw, th = dofile(here .. "export.lua")(img, p, OUT, NAME, names.abyss)
print(string.format("done %dx%d, %dx%d tiles, %.1fs", W, H, tw, th, os.clock() - t0))
