#!/usr/bin/env python3
"""Method A, step 2: turn the stitched Blizzard art into limited-palette pixel art on the art grid.

usage: a_stylize.py LAYOUT SOURCE_PNG B_DATA_DIR PALETTE_GPL OUT_PNG
  SOURCE_PNG  a_source.py output (canvas resolution)
  B_DATA_DIR  prep_b.py output; b_water.png supplies the water mask, distance-to-land and coast pixels (terrain
              data), so coasts are clean 1 px lines instead of the painted, approximate shorelines
Pipeline: median 3 (kills hatching noise) -> box downscale to the art grid -> slight saturation/contrast push ->
Bayer 4x4 ordered dither into the land colours of the palette -> water bands from distance -> 1 px coast outline ->
roads from terrain data as thin lines one tone lighter than the ground. Writes an RGB PNG of palette colours; a_finish.lua indexes and cleans it in Aseprite.
"""
import json, sys
import numpy as np
from PIL import Image, ImageEnhance, ImageFilter
from scipy import ndimage

SPREAD = 30.0
BAYER = np.array([[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]], np.float32)
WCUT = [1.5, 4.5, 11, 30, 75]
SEA = ["foam", "shallow", "mid", "ocean", "deep", "abyss"]
LAKE = ["water1", "water1", "water0", "water0", "water0", "water0"]  # rivers and lakes: muted, like the painted ones
NOT_LAND = {"abyss", "deep", "ocean", "mid", "shallow", "foam", "outline", "lava", "glow", "water0", "water1"}


def gpl(path):
    names, cols = [], []
    for line in open(path):
        p = line.split()
        if len(p) >= 4 and p[0].isdigit():
            cols.append([int(p[0]), int(p[1]), int(p[2])]); names.append(p[3])
    return names, np.array(cols, np.float32)


def nearest(px, pal):
    # "redmean" weighted RGB distance, in row blocks to bound memory
    out = np.empty(px.shape[0], np.int32)
    for i in range(0, px.shape[0], 400000):
        a = px[i:i + 400000, None, :]
        d = a - pal[None]
        rm = (a[..., 0] + pal[None, :, 0]) / 2
        dist = (2 + rm / 256) * d[..., 0] ** 2 + 4 * d[..., 1] ** 2 + (2 + (255 - rm) / 256) * d[..., 2] ** 2
        out[i:i + 400000] = dist.argmin(1)
    return out


def main(layout, source, bdata, palpath, out):
    L = json.load(open(layout))
    aw, ah = L["art"]
    s = L["artScale"]
    names, pal = gpl(palpath)
    idx = {n: i for i, n in enumerate(names)}
    src = Image.open(source).convert("RGB")
    a = np.asarray(src).copy()
    # fill unpainted land (zone rect gaps) from the nearest painted pixel
    hole = a.sum(2) == 0
    if hole.any():
        _, (iy, ix) = ndimage.distance_transform_edt(hole, return_indices=True)
        a = a[iy, ix]
    src = Image.fromarray(a).filter(ImageFilter.MedianFilter(3))
    big = Image.new("RGB", (aw * s, ah * s)); big.paste(src, (0, 0))
    art = big.resize((aw, ah), Image.BOX)
    art = ImageEnhance.Color(art).enhance(1.18)
    art = ImageEnhance.Contrast(art).enhance(1.1)
    px = np.asarray(art, np.float32)
    yy, xx = np.mgrid[0:ah, 0:aw]
    b = (BAYER[yy % 4, xx % 4] + 0.5) / 16 - 0.5
    land_ids = np.array([i for i, n in enumerate(names) if n not in NOT_LAND])
    q = land_ids[nearest((px + b[..., None] * SPREAD).reshape(-1, 3), pal[land_ids])].reshape(ah, aw)

    w = np.asarray(Image.open(f"{bdata}/b_water.png"))
    liq, dist, road = w[..., 0], w[..., 1].astype(np.float32), w[..., 2]
    water = (liq > 0) & (dist != 255)
    coast = dist == 255
    v = dist * (0.82 + (b + 0.5) * 0.36)
    band = np.full((ah, aw), len(WCUT), np.int32)
    for i in range(len(WCUT) - 1, 0, -1):
        band[v < WCUT[i]] = i
    band[dist < 1.5] = 0
    sea_ids = np.array([idx[n] for n in SEA]); lake_ids = np.array([idx[n] for n in LAKE])
    wq = np.where(liq == 2, sea_ids[band], lake_ids[band])
    wq = np.where(liq == 3, np.where(b > 0.2, idx["glow"], idx["lava"]), wq)
    wq = np.where(liq == 4, np.where(b > 0.0, idx["plague1"], idx["plague0"]), wq)
    q = np.where(water, wq, q)
    # coast: dark navy line on the sea, a brown bank line (like the painted maps) on rivers and lakes
    seaside = ndimage.binary_dilation(water & (liq == 2), np.ones((3, 3), bool))
    q[coast] = np.where(seaside[coast], idx["outline"], idx["umber0"])
    # roads from terrain data, thinned to a 1 px centre line (local maximum of the road weight across the road) and
    # drawn one tone lighter than the ground under them, so they read without a hard cream stroke
    rw = ndimage.gaussian_filter(road.astype(np.float32), 0.7)
    peak = ((rw >= np.roll(rw, 1, 1)) & (rw >= np.roll(rw, -1, 1))) | ((rw >= np.roll(rw, 1, 0)) & (rw >= np.roll(rw, -1, 0)))
    r = (rw >= 95) & peak & ~water & ~coast
    lum = pal @ np.array([0.3, 0.59, 0.11], np.float32)
    lighter = np.arange(len(pal))
    for i in land_ids:
        cand = [j for j in land_ids if 14 < lum[j] - lum[i] < 60]
        if cand:
            d = [np.sum((pal[j] - pal[i]) ** 2) for j in cand]
            lighter[i] = cand[int(np.argmin(d))]
    q[r] = lighter[q[r]]
    Image.fromarray(pal.astype(np.uint8)[q]).save(out)  # RGB, every pixel exactly a palette colour
    print(f"{out}: {aw}x{ah}, {len(names)} colours")


if __name__ == "__main__":
    main(*sys.argv[1:6])
