#!/usr/bin/env python3
"""Method A, step 1: stitch Blizzard's zone map art into one continent image at Meridian canvas resolution.

usage: a_source.py LAYOUT ART_DIR DB2_DIR TERRAIN_NPZ OUT_PNG
ART_DIR holds <fileDataID>.blp (tools/pixelmap/casc_extract.py + fetch_missing.sh).
Placement is Canvas:BuildContinent/DrawZone's: each zone's 1002x668 layer (base tiles + every exploration overlay,
i.e. "fully revealed") scaled into its canvas rect. Unlike Meridian's feathered stack, each pixel takes the art of the
zone that owns that ground (terrain area IDs), so the parchment frames, neighbour previews and border labels of the
other maps drop out. Open sea is left black and flagged in OUT_sea.png for the stylizer.
1 output pixel = 1 canvas unit; the art grid is this downscaled by artScale.
"""
import csv, json, sys
import numpy as np
from PIL import Image, ImageFilter

FEATHER = 18  # canvas px


def blp(d, fid):
    return Image.open(f"{d}/{fid}.blp").convert("RGBA")


def zone_image(z, d):
    a = z["art"]
    lw, lh, tw, th = a["layerWidth"], a["layerHeight"], a["tileWidth"], a["tileHeight"]
    im = Image.new("RGBA", (lw, lh), (0, 0, 0, 0))
    for row, col, fid in a["tiles"]:
        im.paste(blp(d, fid), (col * tw, row * th))
    for ov in a["overlays"]:
        cols = -(-ov["w"] // 256)
        for row, col, fid in ov["tiles"]:
            t = blp(d, fid)
            pw = min(256, ov["w"] - col * 256); ph = min(256, ov["h"] - row * 256)
            t = t.crop((0, 0, pw, ph))
            im.alpha_composite(t, (ov["x"] + col * 256, ov["y"] + row * 256))
    return im.crop((0, 0, lw, lh))


def mirror(v, lo, hi):
    """Reflect integer coordinates into [lo, hi)."""
    span = hi - lo
    v = (v - lo) % (2 * span)
    return lo + np.where(v < span, v, 2 * span - v - 1)


def feather_mask(w, h, f):
    x = np.minimum(np.arange(w), np.arange(w)[::-1]).astype(np.float32)
    y = np.minimum(np.arange(h), np.arange(h)[::-1]).astype(np.float32)
    m = np.minimum.outer(y, x) / f
    return Image.fromarray((np.clip(m, 0, 1) * 255).astype(np.uint8))


def owner_map(L, db2, npz, shape_art):
    """uiMapID per art pixel (0 = open sea / none) from the terrain area IDs, with organic borders."""
    from scipy import ndimage
    T = np.load(npz)
    h, liq, area = T["height"], T["liquid"], T["area"]
    parent = {int(r["ID"]): int(r["ParentAreaID"]) for r in csv.DictReader(open(f"{db2}/AreaTable.csv"))}
    zone_of_area = {}
    for r in csv.DictReader(open(f"{db2}/UiMapAssignment.csv")):
        if r["OrderIndex"] == "0" and int(r["AreaID"]):
            zone_of_area[int(r["AreaID"])] = int(r["UiMapID"])
    ids = {z["id"] for z in L["zones"]}
    s = L["artScale"]
    ah, aw = shape_art
    # smallest-zone-on-top fallback (Meridian draw order) for areas that have no zone map of their own
    top = np.zeros((ah, aw), np.int32)
    for z in L["zones"]:
        rx, ry, rw, rh = (v / s for v in z["rect"])
        top[int(ry):int(ry + rh), int(rx):int(rx + rw)] = z["id"]
    own = np.zeros((ah, aw), np.int32)
    for a in np.unique(area):
        if not a:
            continue
        r, n = int(a), 0
        while r not in zone_of_area and parent.get(r, 0) and n < 6:
            r = parent[r]; n += 1
        u = zone_of_area.get(r)
        m = area == a
        own[m] = u if u in ids else top[m]
    water = (liq > 0) | ~np.isfinite(h)
    land = ~water
    # organic borders between zones (area IDs come in 33-yard chunks)
    rng = np.random.default_rng(11)
    def field(sig, amp):
        f = ndimage.gaussian_filter(rng.standard_normal((ah, aw)).astype(np.float32), sig)
        return f / (f.std() + 1e-6) * amp
    yy, xx = np.mgrid[0:ah, 0:aw]
    jx = np.clip(xx + field(6, 4) + field(2, 1.5), 0, aw - 1).astype(int)
    jy = np.clip(yy + field(6, 4) + field(2, 1.5), 0, ah - 1).astype(int)
    own = own[jy, jx]
    # water: nearest land owner within reach, the rest is open sea
    dist, (iy, ix) = ndimage.distance_transform_edt(water, return_indices=True)
    own = np.where(water, own[iy, ix], own)
    reach = 9 + field(5, 3)
    own[water & (dist > reach)] = 0
    return own, dist


def main(layout, d, db2, npz, out):
    L = json.load(open(layout))
    cw, ch = (int(round(v)) for v in L["canvas"])
    k = L["yardsToPx"]
    minx, miny = L["stitchOrigin"]["minx"], L["stitchOrigin"]["miny"]
    s = L["artScale"]
    aw, ah = L["art"]
    own, dist = owner_map(L, db2, npz, (ah, aw))
    own_c = np.repeat(np.repeat(own, s, 0), s, 1)[:ch, :cw]
    out_rgb = np.zeros((ch, cw, 3), np.uint8)
    done = np.zeros((ch, cw), bool)
    imgs = {}
    for z in L["zones"]:
        rx, ry, rw, rh = z["rect"]
        x0, y0 = int(round(rx)), int(round(ry))
        w, h = int(round(rx + rw)) - x0, int(round(ry + rh)) - y0
        zi = np.asarray(zone_image(z, d).convert("RGB").resize((w, h), Image.LANCZOS))
        # replace the torn parchment frame along the rect edge with mirrored interior art
        ins = max(8, int(0.04 * min(w, h)))
        zi = zi[mirror(np.arange(h), ins, h - ins)][:, mirror(np.arange(w), ins, w - ins)]
        imgs[z["id"]] = (x0, y0, zi)
        sub = own_c[y0:y0 + h, x0:x0 + w] == z["id"]
        hh, ww = sub.shape
        out_rgb[y0:y0 + hh, x0:x0 + ww][sub] = zi[:hh, :ww][sub]
        done[y0:y0 + hh, x0:x0 + ww] |= sub
        print(f"{z['name']}: {w}x{h} at {x0},{y0}, {int(sub.sum())} px owned")
    # ground owned by a zone but outside that zone's rect: take it from the smallest other zone map covering it
    want = (own_c != 0) & ~done
    for z in reversed(L["zones"]):
        if z["id"] in (1455, 1458):  # city interiors are not overland art
            continue
        x0, y0, zi = imgs[z["id"]]
        hh, ww = zi.shape[:2]
        sub = want[y0:y0 + hh, x0:x0 + ww]
        hh, ww = sub.shape
        out_rgb[y0:y0 + hh, x0:x0 + ww][sub] = zi[:hh, :ww][sub]
        want[y0:y0 + hh, x0:x0 + ww] &= ~sub
    # anything still unpainted (land outside every zone rect, e.g. the rim of Forever's enlarged Dun Morogh): continue
    # the nearest painted zone's art by mirroring it back into that zone's rect (inset past the parchment frame)
    from scipy import ndimage
    hole = (out_rgb.sum(2) == 0) & (own_c != 0) | ((out_rgb.sum(2) == 0) & (np.repeat(np.repeat(dist, s, 0), s, 1)[:ch, :cw] == 0))
    if hole.any():
        painted = out_rgb.sum(2) > 0
        _, (iy, ix) = ndimage.distance_transform_edt(~painted, return_indices=True)
        src_zone = np.zeros((ch, cw), np.int32)
        for z in L["zones"]:
            x0, y0, zi = imgs[z["id"]]
            hh, ww = zi.shape[:2]
            src_zone[y0:y0 + hh, x0:x0 + ww] = z["id"]  # smallest last = on top
        hy, hx = np.nonzero(hole)
        zid = src_zone[iy[hy, hx], ix[hy, hx]]
        for z in L["zones"]:
            m = zid == z["id"]
            if not m.any():
                continue
            x0, y0, zi = imgs[z["id"]]
            hh, ww = zi.shape[:2]
            ins = max(8, int(0.05 * min(ww, hh)))
            mx = mirror(hx[m] - x0, ins, ww - ins)
            my = mirror(hy[m] - y0, ins, hh - ins)
            out_rgb[hy[m], hx[m]] = zi[my, mx]
    Image.fromarray(out_rgb).save(out)
    # sea mask at art resolution: 255 where no zone art was used, plus distance to land for the stylizer
    Image.fromarray(np.where(own == 0, 255, 0).astype(np.uint8)).save(out.replace(".png", "_sea.png"))
    Image.fromarray(np.clip(dist, 0, 255).astype(np.uint8)).save(out.replace(".png", "_dist.png"))
    print(f"{out}: {cw}x{ch}")


if __name__ == "__main__":
    main(*sys.argv[1:6])
