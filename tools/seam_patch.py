#!/usr/bin/env python3
"""Builds LOCAL-ONLY seam patches for the stitched continent maps and installs them as the addon MeridianSeamPatches.

Where two zone maps meet, Blizzard's art sometimes leaves a strip of bare parchment (with a neighbour's name painted on it).
A patch is a small picture, cut from the finished composite beside the strip and blended over it. It contains Blizzard's
art, so it is installed only on this machine (never committed or released); Meridian/SeamPatches.lua holds just where each
one goes, and Meridian draws a patch only when the addon is present.

Offline composite = the continent map, each zone's art through Meridian/Media/territory masks, and all overlay pieces, placed
with the same rectangles the game computes (0.35 canvas px per yard).

usage: python3 tools/seam_patch.py DB2_DIR CACHE_DIR ADDONS_DIR
"""
import csv, os, struct, sys, urllib.request
import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

DB2, CACHE, ADDONS = sys.argv[1:4]
BUILD = "1.60.1.70450"
K = 0.35                                   # canvas px per yard
CONT = "1415"                              # Eastern Kingdoms

# One patch per seam. polygon: canvas px (continent canvas); source: the filled area is copied from this offset (canvas px).
PATCHES = [
    dict(name="hillsbrad_arathi", world=0, roi=(5960, 2600, 6350, 3070), S=0.5,
         polygon=[(135, 95), (107, 142), (85, 172), (67, 202), (62, 207), (88, 212), (95, 208), (115, 192), (140, 170), (152, 142), (165, 100)],   # px of the patch picture
         source=tuple(int(v) for v in os.environ.get("SEAM_SOURCE", "-120,0").split(","))),
]

def table(n): return list(csv.DictReader(open(os.path.join(DB2, n + ".csv"), encoding="utf-8")))

def img(fid):
    p = os.path.join(CACHE, "%s.blp" % fid)
    if not os.path.exists(p) or os.path.getsize(p) < 50:
        req = urllib.request.Request("https://wago.tools/api/casc/%s?download&version=%s" % (fid, BUILD), headers={"User-Agent": "meridian-tools/1"})
        open(p, "wb").write(urllib.request.urlopen(req, timeout=60).read())
    try:
        return Image.open(p).convert("RGBA")
    except Exception:
        b = open(p, "rb").read(); w, h = struct.unpack("<II", b[12:20]); off = struct.unpack("<16I", b[20:84])[0]
        return Image.frombytes("RGBA", (w, h), b[off:off + w * h * 4], "raw", "BGRA")

uimap = {r["ID"]: r for r in table("UiMap")}
box = {}
for r in table("UiMapAssignment"):
    if r["UiMapID"] not in box and r["MapID"] == "0":
        box[r["UiMapID"]] = tuple(float(r[k]) for k in ("Region_0", "Region_1", "Region_3", "Region_4"))   # minX, minY, maxX, maxY
cminx, cminy, cmaxx, cmaxy = box[CONT]
art_of = {}
for r in table("UiMapXMapArt"):
    if r["PhaseID"] == "0": art_of.setdefault(r["UiMapID"], []).append(r["UiMapArtID"])
ovs = {}
for r in table("WorldMapOverlay"): ovs.setdefault(r["UiMapArtID"], []).append(r)
otiles = {}
for r in table("WorldMapOverlayTile"):
    if r["LayerIndex"] == "0": otiles.setdefault(r["WorldMapOverlayID"], []).append((int(r["RowIndex"]), int(r["ColIndex"]), int(r["FileDataID"])))
btiles = {}
for r in table("UiMapArtTile"):
    if r["LayerIndex"] == "0": btiles.setdefault(r["UiMapArtID"], []).append((int(r["RowIndex"]), int(r["ColIndex"]), int(r["FileDataID"])))

def base_of(art):
    im = Image.new("RGBA", (1024, 768), (0, 0, 0, 0))
    for row, col, fid in btiles.get(art, []): im.paste(img(fid), (col * 256, row * 256))
    return im.crop((0, 0, 1002, 668))

def feather(w, h, fade):
    yy = np.minimum(np.arange(h), h - 1 - np.arange(h)) / (h * fade); xx = np.minimum(np.arange(w), w - 1 - np.arange(w)) / (w * fade)
    e = np.clip(np.minimum(yy[:, None], xx[None, :]), 0, 1); return e * e * (3 - 2 * e)

zones = []
for zid, r in uimap.items():
    if r["Type"] == "3" and r["ParentUiMapID"] == CONT and zid in box:
        mnx, mny, mxx, mxy = box[zid]
        rect = ((cmaxy - mxy) * K, (cmaxx - mxx) * K, (mxy - mny) * K, (mxx - mnx) * K)
        zones.append((zid, rect))
zones.sort(key=lambda t: -t[1][2] * t[1][3])
back = base_of(max(art_of[CONT], key=lambda a: len(btiles.get(a, []))))
assets = {}
def zone_assets(zid):
    if zid in assets: return assets[zid]
    arts = [a for a in art_of.get(zid, []) if a in ovs]
    art = max(arts, key=lambda a: len(ovs[a])) if arts else (art_of.get(zid) or [None])[0]
    base = base_of(art); ov = Image.new("RGBA", (1002, 668), (0, 0, 0, 0))
    for o in ovs.get(art, []):
        ox, oy, ow, oh = int(o["OffsetX"]), int(o["OffsetY"]), int(o["TextureWidth"]), int(o["TextureHeight"])
        for row, col, fid in otiles.get(o["ID"], []):
            x, y = ox + col * 256, oy + row * 256
            if x >= 0 and y >= 0: ov.alpha_composite(img(fid).crop((0, 0, min(256, ow - col * 256), min(256, oh - row * 256))), (x, y))
    assets[zid] = (base, ov); return assets[zid]

def render(crop, S):
    x0, y0, x1, y1 = crop; W, H = int((x1 - x0) * S), int((y1 - y0) * S)
    canvas = Image.new("RGBA", (W, H), (31, 61, 77, 255))
    def place(im, rect, mul=None):
        rx, ry, rw, rh = rect; tw, th = max(1, int(rw * S)), max(1, int(rh * S)); px, py = int((rx - x0) * S), int((ry - y0) * S)
        if px >= W or py >= H or px + tw <= 0 or py + th <= 0: return
        a = np.asarray(im.resize((tw, th), Image.LANCZOS)).copy()
        if mul is not None: a[:, :, 3] = (a[:, :, 3] * mul(tw, th)).astype(np.uint8)
        t = Image.fromarray(a)
        if px < 0 or py < 0: t = t.crop((max(0, -px), max(0, -py), tw, th)); px, py = max(0, px), max(0, py)
        canvas.alpha_composite(t, (px, py))
    cw, ch = (cmaxy - cminy) * K, (cmaxx - cminx) * K
    place(back, (0, 0, cw, ch))
    for zid, rect in zones:
        mp = os.path.join("Meridian", "Media", "territory", "%s.tga" % zid)
        m = Image.open(mp).convert("RGBA").split()[3] if os.path.exists(mp) else None
        place(zone_assets(zid)[0], rect, (lambda tw, th, m=m: np.asarray(m.resize((tw, th), Image.BILINEAR)) / 255.0) if m else (lambda tw, th: feather(tw, th, 0.22)))
    for zid, rect in zones:
        place(zone_assets(zid)[1], rect, lambda tw, th: feather(tw, th, 0.08))
    return canvas.convert("RGB")

dest = os.path.join(ADDONS, "MeridianSeamPatches"); os.makedirs(dest, exist_ok=True)
lua = ["-- Where each local seam patch goes (tools/seam_patch.py): world id, world box in yards (min x, min y, max x, max y), file.",
       "local ADDON, M = ...", "M.SeamPatches = {"]
for p in PATCHES:
    S = p["S"]; x0, y0, x1, y1 = p["roi"]
    C = np.asarray(render(p["roi"], S)).astype(np.float32); H, W, _ = C.shape
    m = Image.new("L", (W, H), 0)
    ImageDraw.Draw(m).polygon(p["polygon"], fill=255)
    keep = np.asarray(m) > 0
    dx, dy = int(round(p["source"][0] * S)), int(round(p["source"][1] * S))
    src = np.roll(C, (-dy, -dx), axis=(0, 1))
    alpha = np.clip(ndimage.gaussian_filter(keep.astype(np.float32), 3) * 1.3, 0, 1)
    out = np.dstack([src, alpha * 255]).astype(np.uint8)
    tga = bytearray()
    for y in range(H - 1, -1, -1):
        for x in range(W): tga += bytes((int(out[y, x, 0]), int(out[y, x, 1]), int(out[y, x, 2]), int(out[y, x, 3])))
    with open(os.path.join(dest, p["name"] + ".tga"), "wb") as f:
        f.write(struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, W, H, 32, 8) + bytes(tga))
    Image.fromarray(np.clip(C, 0, 255).astype(np.uint8)).save(os.path.join(CACHE, p["name"] + "_before.png"))
    Image.fromarray(np.dstack([np.where(alpha[:, :, None] > 0, src * alpha[:, :, None] + C * (1 - alpha[:, :, None]), C)]).clip(0, 255).astype(np.uint8)).save(os.path.join(CACHE, p["name"] + "_after.png"))
    # world box: canvas x grows eastward (decreasing world y), canvas y southward (decreasing world x)
    max_y, min_y = cmaxy - x0 / K, cmaxy - x1 / K
    max_x, min_x = cmaxx - y0 / K, cmaxx - y1 / K
    lua.append('    { name = "%s", world = %d, minX = %.1f, minY = %.1f, maxX = %.1f, maxY = %.1f },' % (p["name"], p["world"], min_x, min_y, max_x, max_y))
lua.append("}")
open("Meridian/SeamPatches.lua", "w").write("\n".join(lua) + "\n")
open(os.path.join(dest, "MeridianSeamPatches.toc"), "w").write("## Interface: 16001\n## Title: Meridian seam patches (local)\n## Notes: Local-only picture patches for Meridian's map seams.\n## DefaultState: enabled\n\nMeridianSeamPatches.lua\n")
open(os.path.join(dest, "MeridianSeamPatches.lua"), "w").write("-- textures only\n")
print(len(PATCHES), "patch(es) installed to", dest)
