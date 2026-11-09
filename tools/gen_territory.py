#!/usr/bin/env python3
"""Generates Meridian/Media/territory/<uiMapID>.tga: one alpha mask per zone map, the shape of the land that zone owns.

Zone maps paint their neighbours' ground as blank parchment, so stitched together they cover each other. A zone's
overlay pieces (the explored-area art; Blizzard's WorldMapOverlay table) are exactly where that zone's own land is, so
the union of their alpha, grown a little and softened, is its territory. Meridian draws each zone's base art through
its mask (neighbours then hand over to each other along soft borders). Only silhouettes are written, no colour art.

usage: python3 tools/gen_territory.py DB2_DIR CACHE_DIR [PREVIEW_DIR]
  DB2_DIR   folder of CSVs from tools/pixelmap/fetch_db2.sh (UiMap, UiMapXMapArt, WorldMapOverlay, WorldMapOverlayTile)
  CACHE_DIR where overlay textures (BLP) are cached (from wago.tools' CDN mirror of the same build)
Also writes Meridian/TerritoryData.lua (the list of zone ids that have a mask).
"""
import csv, os, struct, sys, time, urllib.request
from concurrent.futures import ThreadPoolExecutor

import numpy as np
from PIL import Image
from scipy import ndimage

DB2, CACHE = sys.argv[1], sys.argv[2]
PREVIEW = sys.argv[3] if len(sys.argv) > 3 else None
BUILD = "1.60.1.70450"
OUT = "Meridian/Media/territory"
LAYER_W, LAYER_H = 1002, 668      # a classic zone map's art size
TILE = 256
GROW = 18                         # px the overlay union is grown by (the land round it: coast, shallows, borders)
SOFT = 14                         # gaussian sigma of the border, px
EDGE = 0.06                       # fraction of each side faded to zero (the frame)
MASK = 128                        # output size (stretched over the zone's rectangle)
UA = {"User-Agent": "meridian-tools/1"}


def table(name):
    return list(csv.DictReader(open(os.path.join(DB2, name + ".csv"), encoding="utf-8")))


def fetch(fid):
    path = os.path.join(CACHE, "%s.blp" % fid)
    if not os.path.exists(path) or os.path.getsize(path) < 50:
        url = "https://wago.tools/api/casc/%s?download&version=%s" % (fid, BUILD)
        for attempt in range(3):
            try:
                data = urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=60).read()
                open(path, "wb").write(data)
                break
            except Exception:
                time.sleep(1 + attempt)
        else:
            return None
    return path


def alpha_of(fid):
    p = fetch(fid)
    if not p:
        return None
    try:
        return np.asarray(Image.open(p).convert("RGBA"))[:, :, 3]
    except Exception:
        b = open(p, "rb").read()                       # uncompressed BLP2, which Pillow doesn't read
        w, h = struct.unpack("<II", b[12:20])
        off = struct.unpack("<16I", b[20:84])[0]
        return np.frombuffer(b[off:off + w * h * 4], dtype=np.uint8).reshape(h, w, 4)[:, :, 3]


def main():
    os.makedirs(CACHE, exist_ok=True)
    os.makedirs(OUT, exist_ok=True)
    uimap = {r["ID"]: r for r in table("UiMap")}
    art_of = {}
    for r in table("UiMapXMapArt"):
        if r["PhaseID"] == "0":
            art_of.setdefault(r["UiMapID"], []).append(r["UiMapArtID"])
    overlays = {}
    for r in table("WorldMapOverlay"):
        overlays.setdefault(r["UiMapArtID"], []).append(r)
    tiles = {}
    for r in table("WorldMapOverlayTile"):
        if r["LayerIndex"] == "0":
            tiles.setdefault(r["WorldMapOverlayID"], []).append((int(r["RowIndex"]), int(r["ColIndex"]), int(r["FileDataID"])))

    zones = {}
    for zid, r in uimap.items():
        if r["Type"] != "3" or r["ParentUiMapID"] not in ("1414", "1415"):
            continue
        arts = [a for a in art_of.get(zid, []) if a in overlays]
        if arts:
            zones[zid] = max(arts, key=lambda a: len(overlays[a]))
    print(len(zones), "zones with overlay data")

    need = sorted({fid for z, a in zones.items() for o in overlays[a] for (_, _, fid) in tiles.get(o["ID"], [])})
    print(len(need), "overlay textures to fetch")
    with ThreadPoolExecutor(8) as ex:
        alphas = dict(zip(need, ex.map(alpha_of, need)))

    ids = []
    for zid, art in sorted(zones.items(), key=lambda t: int(t[0])):
        canvas = np.zeros((LAYER_H, LAYER_W), dtype=np.uint8)
        for o in overlays[art]:
            ow, oh, ox, oy = int(o["TextureWidth"]), int(o["TextureHeight"]), int(o["OffsetX"]), int(o["OffsetY"])
            wide = -(-ow // TILE)
            for row, col, fid in tiles.get(o["ID"], []):
                a = alphas.get(fid)
                if a is None:
                    continue
                x0, y0 = ox + col * TILE, oy + row * TILE
                pw = min(TILE, ow - col * TILE)
                ph = min(TILE, oh - row * TILE)
                sub = a[:ph, :pw]
                x1, y1 = min(LAYER_W, x0 + pw), min(LAYER_H, y0 + ph)
                if x1 <= max(0, x0) or y1 <= max(0, y0):
                    continue
                sx, sy = max(0, -x0), max(0, -y0)
                dst = canvas[max(0, y0):y1, max(0, x0):x1]
                src = sub[sy:sy + dst.shape[0], sx:sx + dst.shape[1]]
                np.maximum(dst, src, out=dst)
        land = canvas > 40
        if not land.any():
            continue
        dist = ndimage.distance_transform_edt(~land)
        grown = (dist <= GROW).astype(np.float32)
        soft = ndimage.gaussian_filter(grown, SOFT)
        # fade the frame so the rectangle's own edge never shows
        yy = np.minimum(np.arange(LAYER_H), LAYER_H - 1 - np.arange(LAYER_H)) / (LAYER_H * EDGE)
        xx = np.minimum(np.arange(LAYER_W), LAYER_W - 1 - np.arange(LAYER_W)) / (LAYER_W * EDGE)
        edge = np.clip(np.minimum(yy[:, None], xx[None, :]), 0, 1)
        edge = edge * edge * (3 - 2 * edge)
        mask = np.clip(soft * edge, 0, 1)
        small = np.asarray(Image.fromarray((mask * 255).astype(np.uint8)).resize((MASK, MASK), Image.LANCZOS))
        rows = []
        for y in range(MASK):
            row = bytearray()
            for x in range(MASK):
                row += bytes((255, 255, 255, int(small[y, x])))
            rows.append(bytes(row))
        hdr = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, MASK, MASK, 32, 8)
        with open(os.path.join(OUT, "%s.tga" % zid), "wb") as f:
            f.write(hdr + b"".join(reversed(rows)))
        ids.append(int(zid))
        if PREVIEW:
            os.makedirs(PREVIEW, exist_ok=True)
            Image.fromarray((mask * 255).astype(np.uint8)).save(os.path.join(PREVIEW, "%s.png" % zid))
    with open("Meridian/TerritoryData.lua", "w") as f:
        f.write("-- Zones that have a territory mask in Media/territory (generated by tools/gen_territory.py; do not edit).\n")
        f.write("local ADDON, M = ...\nM.Territory = {\n")
        for i in ids:
            f.write("    [%d] = true,\n" % i)
        f.write("}\n")
    print("wrote", len(ids), "masks")


main()
