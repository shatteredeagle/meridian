-- Shared export for the pixel maps: <name>.aseprite, full.png (indexed) and 256x256 tiles (r<row>_c<col>.png, row-major from the
-- top-left of the art grid; see docs/pixelmap/README.md for how tiles map to Meridian's canvas).
return function(img, pal, out, name, fill)
  local TILE = 256
  os.execute('mkdir -p "' .. out .. '/tiles"')
  local spr = Sprite(img.width, img.height, ColorMode.INDEXED)
  spr:setPalette(pal)
  spr.cels[1].image = img
  app.command.BackgroundFromLayer()
  spr:saveAs(out .. "/" .. name .. ".aseprite")
  img:saveAs{ filename = out .. "/full.png", palette = pal }
  local tw, th = math.ceil(img.width / TILE), math.ceil(img.height / TILE)
  for ty = 0, th - 1 do
    for tx = 0, tw - 1 do
      local t = Image(TILE, TILE, ColorMode.INDEXED)
      t:clear(fill)
      t:drawImage(img, Point(-tx * TILE, -ty * TILE))
      t:saveAs{ filename = string.format("%s/tiles/r%02d_c%02d.png", out, ty, tx), palette = pal }
    end
  end
  spr:close()
  return tw, th
end
