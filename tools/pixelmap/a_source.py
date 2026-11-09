#!/usr/bin/env python3
"""Method A, step 1: stitch Blizzard's zone map art into one continent image at Meridian canvas resolution.

usage: a_source.py LAYOUT ART_DIR DB2_DIR TERRAIN_NPZ OUT_PNG [B_LAND_PNG] [LABELS_JSON]
ART_DIR holds <fileDataID>.blp (tools/pixelmap/casc_extract.py + fetch_missing.sh).
Placement is Canvas:BuildContinent/DrawZone's: each zone's 1002x668 layer (base tiles + every exploration overlay,
i.e. "fully revealed") scaled into its canvas rect. Unlike Meridian's feathered stack, each pixel takes the art of the
zone that owns that ground (terrain area IDs), blended softly across zone seams, so the parchment frames, neighbour
previews and border labels of the other maps drop out. Each layer's frame and its painted labels (detected, plus
hand-listed boxes in LABELS_JSON) are unusable; ground with no usable art is synthesised from the surrounding colours
shaded by the terrain hillshade (B_LAND_PNG blue channel). Open sea is left black.
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


def label_mask(im, boxes):
    """Painted text in a 1002x668 zone layer: hand-listed boxes (a_labels.json) plus detected text-like strokes."""
    from scipy import ndimage
    rgb = im.convert("RGB")
    a = np.asarray(rgb, np.float32)
    hsv = np.asarray(rgb.convert("HSV"), np.float32)
    h, sat, v = hsv[..., 0] * 360 / 255, hsv[..., 1] / 255, hsv[..., 2]
    lum = a @ np.array([0.3, 0.59, 0.11], np.float32)
    light = ((h > 30) & (h < 62) & (sat > 0.55) & (v > 150)) | ((lum > 170) & (sat < 0.45))
    dark = lum < 80
    # stroke pixels: light next to dark (outlined light text) or dark next to light (haloed dark text)
    cand = (light & ndimage.maximum_filter(dark, 3)) | (dark & ndimage.maximum_filter(light, 3))
    blob = ndimage.binary_closing(ndimage.binary_dilation(cand, np.ones((3, 5))), np.ones((3, 9)))
    lab, _n = ndimage.label(blob)
    keep = np.zeros(blob.shape, bool)
    for i, sl in enumerate(ndimage.find_objects(lab), 1):
        hh, ww = sl[0].stop - sl[0].start, sl[1].stop - sl[1].start
        if not (5 <= hh <= 40 and ww >= 2.0 * hh and ww >= 14):
            continue
        comp = lab[sl] == i
        c = cand[sl] & comp
        # letters switch on/off often along a row; roads and ridges do not
        freq = (np.diff(c.astype(np.int8), axis=1) != 0).sum(1)[comp.any(1)].mean() / ww
        if freq > 0.13 and c[comp].mean() > 0.3:
            keep[sl] |= comp
    for x0, y0, x1, y1 in boxes:
        keep[y0:y1, x0:x1] = True
    return ndimage.binary_dilation(keep, iterations=5)


def frame_mask(w, h):
    """The torn parchment frame and corner ornaments along a zone layer's edge (1002x668 coordinates)."""
    yy, xx = np.mgrid[0:h, 0:w]
    e = np.minimum(np.minimum(xx, w - 1 - xx), np.minimum(yy, h - 1 - yy))
    cx = np.minimum(xx, w - 1 - xx); cy = np.minimum(yy, h - 1 - yy)
    return (e < 36) | ((cx < 70) & (cy < 70))


def gauss(a, sigma):
    from scipy import ndimage
    return ndimage.gaussian_filter(a, sigma, mode="nearest", truncate=3.0)


def main(layout, d, db2, npz, out, shade_png=None, labels_json=None):
    from scipy import ndimage
    L = json.load(open(layout))
    cw, ch = (int(round(v)) for v in L["canvas"])
    s = L["artScale"]
    aw, ah = L["art"]
    own, dist = owner_map(L, db2, npz, (ah, aw))
    own_c = np.repeat(np.repeat(own, s, 0), s, 1)[:ch, :cw]
    land_c = np.repeat(np.repeat(dist == 0, s, 0), s, 1)[:ch, :cw]
    boxes = {k: v for k, v in json.load(open(labels_json)).items() if not k.startswith("_")} if labels_json else {}
    BLEND = 16.0  # canvas px: soft seams between neighbouring zones' art
    acc_p = np.zeros((ch, cw, 3), np.float32); w_p = np.zeros((ch, cw), np.float32)
    acc_s = np.zeros((ch, cw, 3), np.float32); w_s = np.zeros((ch, cw), np.float32)
    for z in L["zones"]:
        if z["id"] in (1453, 1455, 1458):  # city maps: other scale, labelled districts; Elwynn's art draws Stormwind
            continue
        rx, ry, rw, rh = z["rect"]
        x0, y0 = int(round(rx)), int(round(ry))
        w, h = int(round(rx + rw)) - x0, int(round(ry + rh)) - y0
        zim = zone_image(z, d)
        bad = frame_mask(zim.width, zim.height) | label_mask(zim, boxes.get(str(z["id"]), []))
        good = np.asarray(Image.fromarray((~bad).astype(np.uint8) * 255).resize((w, h), Image.BILINEAR), np.float32) / 255
        good = np.clip((gauss(good, 2.0) - 0.5) * 2, 0, 1)  # feathered availability
        zi = np.asarray(zim.convert("RGB").resize((w, h), Image.LANCZOS), np.float32)
        hh, ww = min(h, ch - y0), min(w, cw - x0)
        sl = (slice(y0, y0 + hh), slice(x0, x0 + ww))
        zi, good = zi[:hh, :ww], good[:hh, :ww]
        # own ground, minus slivers thinner than ~50 canvas px (a zone whose ground runs just past its map edge would
        # otherwise paint a narrow stripe of its own colour)
        owned = (own_c[sl] == z["id"]) & (good > 0.5)
        owned = ndimage.binary_dilation(ndimage.binary_erosion(owned, iterations=25), iterations=25) & owned
        mine = gauss(owned.astype(np.float32), BLEND) * good
        acc_p[sl] += zi * mine[..., None]; w_p[sl] += mine
        # fallback art (ground this zone's map shows but does not own): favour the map whose own ground is nearest,
        # so a preview strip at one map's edge never wins over the art continuing from the neighbouring zone
        q = 4
        own_small = (own_c[sl][::q, ::q] == z["id"])
        if own_small.any():
            dq = ndimage.distance_transform_edt(~own_small) * q
            dq = np.asarray(Image.fromarray(dq.astype(np.float32)).resize((ww, hh), Image.BILINEAR))
        else:
            dq = np.full((hh, ww), 1e4, np.float32)
        ws = good * np.exp(-dq / 60.0)
        acc_s[sl] += zi * ws[..., None]; w_s[sl] += ws
        print(f"{z['name']}: {w}x{h} at {x0},{y0}, label+frame {bad.mean():.3f}")
    prim = acc_p / np.maximum(w_p, 1e-6)[..., None]
    sec = acc_s / np.maximum(w_s, 1e-6)[..., None] * (w_s > 1e-4)[..., None]
    w_s = np.clip(w_s * 20, 0, 1)  # any nearby map counts as available
    del acc_p, acc_s
    a_p = np.clip(w_p * 1.6, 0, 1)
    # neighbour previews are tinted differently: shift the fallback art's local mean colour onto the owner's
    def local_mean(img, wt, sig):
        num = np.stack([gauss(img[..., c] * wt, sig) for c in range(3)], -1)
        den = gauss(wt, sig)
        return num / np.maximum(den, 1e-6)[..., None], den
    mp, dp = local_mean(prim, a_p, 40)
    ms, _ds = local_mean(sec, np.clip(w_s, 0, 1), 40)
    tint = np.clip(dp * 3, 0, 1)[..., None]
    sec = sec + (mp - ms) * tint
    del mp, ms
    a_s = np.clip(w_s, 0, 1) * (1 - a_p)
    a_syn = 1 - a_p - a_s
    # synthetic ground where no usable art exists (outside every rect, frames, labels): the surrounding art's colour,
    # spread outwards at two scales, shaded with the real terrain's hillshade
    known = (a_p + a_s) > 0.6
    col = (prim * a_p[..., None] + sec * a_s[..., None]) / np.maximum(a_p + a_s, 1e-6)[..., None]
    wk = known.astype(np.float32)
    syn = np.zeros_like(col)
    for sig in (10, 40, 160):
        num = np.stack([gauss(col[..., c] * wk, sig) for c in range(3)], -1)
        den = gauss(wk, sig)
        fill = num / np.maximum(den, 1e-6)[..., None]
        need = (syn.sum(2) == 0) & (den > 1e-3)
        syn[need] = fill[need]
    if shade_png:
        sh = np.asarray(Image.open(shade_png))[..., 2].astype(np.float32)
        sh = np.asarray(Image.fromarray(sh).resize((cw, ch), Image.BILINEAR), np.float32)
        syn *= np.clip(0.86 + 0.28 * sh / 255, 0.8, 1.14)[..., None]
    res = prim * a_p[..., None] + sec * a_s[..., None] + syn * a_syn[..., None]
    # small unusable patches (labels, banners): clone-stamp the nearest clean strip of art above/below/beside them,
    # which keeps the hatching texture; only big gaps keep the shaded synthetic fill
    hole = a_syn > 0.35
    known = (a_syn < 0.1) & land_c
    lab, _n = ndimage.label(hole)
    cloned = 0
    for i, sl in enumerate(ndimage.find_objects(lab), 1):
        h0, w0 = sl[0].stop - sl[0].start, sl[1].stop - sl[1].start
        if h0 > 150 or w0 > 600:
            continue
        m = lab[sl] == i
        pad = 6
        y0, y1 = max(sl[0].start - pad, 0), min(sl[0].stop + pad, ch)
        x0, x1 = max(sl[1].start - pad, 0), min(sl[1].stop + pad, cw)
        mm = np.zeros((y1 - y0, x1 - x0), bool); mm[sl[0].start - y0:sl[0].stop - y0, sl[1].start - x0:sl[1].stop - x0] = m
        mm = ndimage.binary_dilation(mm, iterations=3)
        offs = [(f * dy, f * dx) for f in (1, 2) for dy, dx in
                ((-(h0 + 16), 0), (h0 + 16, 0), (0, -(w0 + 16)), (0, w0 + 16), (-(h0 + 16), -(w0 // 2)), (h0 + 16, w0 // 2))]
        for dy, dx in offs:
            sy0, sx0 = y0 + dy, x0 + dx
            if sy0 < 0 or sx0 < 0 or sy0 + (y1 - y0) > ch or sx0 + (x1 - x0) > cw:
                continue
            if known[sy0:sy0 + y1 - y0, sx0:sx0 + x1 - x0].mean() < 0.98:  # whole window clean, not just the hole
                continue
            alpha = np.clip(ndimage.distance_transform_edt(mm) / 3.0, 0, 1)[..., None]
            src = res[sy0:sy0 + y1 - y0, sx0:sx0 + x1 - x0].copy()
            # match the stamp's colour to the ground just around the hole (no dark/light boxes)
            ring = ndimage.binary_dilation(mm, iterations=6) & ~mm
            if ring.any():
                src += res[y0:y1, x0:x1][ring].mean(0) - src[ring].mean(0)
            res[y0:y1, x0:x1] = res[y0:y1, x0:x1] * (1 - alpha) + src * alpha
            a_syn[y0:y1, x0:x1][mm] = 0
            cloned += 1
            break
    print(f"clone-stamped {cloned} of {_n} unusable patches")
    res[~land_c & (own_c == 0)] = 0
    Image.fromarray(np.clip(res, 0, 255).astype(np.uint8)).save(out)
    Image.fromarray((np.clip(a_syn, 0, 1) * 255).astype(np.uint8)).save(out.replace(".png", "_synthetic.png"))
    Image.fromarray(np.where(own == 0, 255, 0).astype(np.uint8)).save(out.replace(".png", "_sea.png"))
    print(f"{out}: {cw}x{ch}, synthetic share of land {float(a_syn[land_c].mean()):.3f}")


if __name__ == "__main__":
    main(*sys.argv[1:8])
