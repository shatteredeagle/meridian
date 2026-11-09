#!/usr/bin/env python3
"""Converts the pixel-map tiles (docs/pixelmap/{a-stylize,b-scratch,c-hybrid}/tiles/*.png) to 32-bit TGA and installs
them as a separate local-only addon, MeridianPixelMaps, next to Meridian. Meridian's ArtStyles.lua draws them.
Never commit or release the output (method A is derived from Blizzard art).
Run from the repo root: python3 tools/pixelmap/install_tiles.py [AddOns dir]"""
import os, struct, sys
from PIL import Image

ADDONS = sys.argv[1] if len(sys.argv) > 1 else os.path.expanduser(
    "~/Faugus/battlenet/drive_c/Program Files (x86)/World of Warcraft/_forever_/Interface/AddOns")
SRC = {"a": "docs/pixelmap/a-stylize/tiles", "b": "docs/pixelmap/b-scratch/tiles", "c": "docs/pixelmap/c-hybrid/tiles"}
OUT = os.path.join(ADDONS, "MeridianPixelMaps")

def write_tga(path, im):
    im = im.convert("RGBA")
    w, h = im.size
    r, g, b, a = im.split()
    raw = Image.merge("RGBA", (b, g, r, a)).tobytes()
    rows = [raw[i * w * 4:(i + 1) * w * 4] for i in range(h)]
    # type 2 (uncompressed true colour), 32 bpp, 8 alpha bits, bottom-left origin (rows bottom-up, like the icon TGAs)
    hdr = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, w, h, 32, 8)
    with open(path, "wb") as f:
        f.write(hdr + b"".join(reversed(rows)))

total = 0
for key, src in SRC.items():
    if not os.path.isdir(src):
        print("skip", key, "(no", src + ")")
        continue
    os.makedirs(os.path.join(OUT, key), exist_ok=True)
    for name in sorted(os.listdir(src)):
        if name.endswith(".png"):
            write_tga(os.path.join(OUT, key, name[:-4] + ".tga"), Image.open(os.path.join(src, name)))
            total += 1
with open(os.path.join(OUT, "MeridianPixelMaps.toc"), "w") as f:
    f.write("## Interface: 16001\n## Title: Meridian Pixel Maps (local experiment)\n"
            "## Notes: Pixel-art Eastern Kingdoms tiles for Meridian. Local only; do not redistribute.\n"
            "## Dependencies: \n")
print("wrote", total, "tiles to", OUT)
