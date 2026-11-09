-- Method A, step 3 (Aseprite): load the stylized indexed PNG, remove lone specks, export .aseprite/PNG/tiles.
-- Params: src (a_stylize.py output), pal (.gpl), out, name.
local P = app.params
local here = debug.getinfo(1, "S").source:sub(2):match("(.*/)") or "./"
local pal = Palette{ fromFile = P.pal }
-- the stylizer writes RGB (Aseprite's PNG loader dropped palette entries >= 32 of an indexed file); map back exactly
local rgb = Image{ fromFile = P.src }
local W, H = rgb.width, rgb.height
local pc = app.pixelColor
local lut = {}
for i = 0, #pal - 1 do
  local c = pal:getColor(i)
  lut[(c.red << 16) | (c.green << 8) | c.blue] = i
end
local src = Image(W, H, ColorMode.INDEXED)
local miss = 0
for it in rgb:pixels() do
  local v = it()
  local i = lut[(pc.rgbaR(v) << 16) | (pc.rgbaG(v) << 8) | pc.rgbaB(v)]
  if not i then i = 0; miss = miss + 1 end
  src:drawPixel(it.x, it.y, i)
end
assert(miss == 0, miss .. " pixels not in the palette")
local img = src:clone()
-- a pixel whose 8 neighbours all share one other colour is noise from the source hatching: take the neighbours' colour
local fixed = 0
for y = 1, H - 2 do
  for x = 1, W - 2 do
    local n = src:getPixel(x - 1, y)
    if n ~= src:getPixel(x, y) and n == src:getPixel(x + 1, y) and n == src:getPixel(x, y - 1) and n == src:getPixel(x, y + 1)
      and n == src:getPixel(x - 1, y - 1) and n == src:getPixel(x + 1, y - 1) and n == src:getPixel(x - 1, y + 1)
      and n == src:getPixel(x + 1, y + 1) then
      img:drawPixel(x, y, n); fixed = fixed + 1
    end
  end
end
local abyss = 0 -- first palette entry is the deep-sea fill for tile padding
local tw, th = dofile(here .. "export.lua")(img, pal, P.out, P.name, abyss)
print(string.format("despeckled %d px; %dx%d, %dx%d tiles", fixed, W, H, tw, th))
