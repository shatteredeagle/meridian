#!/usr/bin/env python3
"""Generate the toolbar glyphs as 64x64 white-on-transparent TGAs (tinted in-game).
Run from the repo root: python3 tools/gen_icons.py"""
import math, struct, os

S, SS = 64, 4  # size, supersampling per axis
OUT = "Meridian/Media/icons"

# Shapes are predicates on (x, y) in a 0..1 box, y down.
def seg_dist(px, py, ax, ay, bx, by):
    dx, dy = bx - ax, by - ay
    t = max(0, min(1, ((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy or 1)))
    return math.hypot(px - ax - t * dx, py - ay - t * dy)

def line(ax, ay, bx, by, w=0.075): return lambda x, y: seg_dist(x, y, ax, ay, bx, by) <= w / 2
def disc(cx, cy, r): return lambda x, y: math.hypot(x - cx, y - cy) <= r
def ring(cx, cy, r, w=0.075): return lambda x, y: abs(math.hypot(x - cx, y - cy) - r) <= w / 2
def box(x0, y0, x1, y1): return lambda x, y: x0 <= x <= x1 and y0 <= y <= y1
def frame(x0, y0, x1, y1, w=0.075):
    return lambda x, y: box(x0, y0, x1, y1)(x, y) and not box(x0 + w, y0 + w, x1 - w, y1 - w)(x, y)
def ellipse_ring(cx, cy, rx, ry, w=0.075):
    def f(x, y):
        d = math.hypot((x - cx) / rx, (y - cy) / ry)
        return abs(d - 1) <= w / min(rx, ry) / 2
    return f
def tri(ax, ay, bx, by, cx, cy):
    def f(x, y):
        d1 = (x - bx) * (ay - by) - (ax - bx) * (y - by)
        d2 = (x - cx) * (by - cy) - (bx - cx) * (y - cy)
        d3 = (x - ax) * (cy - ay) - (cx - ax) * (y - ay)
        return not ((d1 < 0 or d2 < 0 or d3 < 0) and (d1 > 0 or d2 > 0 or d3 > 0))
    return f
def union(*fs): return lambda x, y: any(f(x, y) for f in fs)

ICONS = {
    "plus": union(line(.2, .5, .8, .5, .1), line(.5, .2, .5, .8, .1)),
    "minus": line(.2, .5, .8, .5, .1),
    "fit": union(*[line(a, b, c, d, .09) for a, b, c, d in [
        (.16, .38, .16, .16), (.16, .16, .38, .16), (.84, .38, .84, .16), (.84, .16, .62, .16),
        (.16, .62, .16, .84), (.16, .84, .38, .84), (.84, .62, .84, .84), (.84, .84, .62, .84)]]),
    "locate": union(ring(.5, .5, .26, .08), disc(.5, .5, .08),
                    line(.5, .08, .5, .2), line(.5, .8, .5, .92), line(.08, .5, .2, .5), line(.8, .5, .92, .5)),
    "continent": union(frame(.14, .14, .48, .48), frame(.52, .14, .86, .48), frame(.14, .52, .48, .86), frame(.52, .52, .86, .86)),
    "zone": union(frame(.2, .2, .8, .8, .09), disc(.5, .5, .09)),
    "reveal": union(ellipse_ring(.5, .5, .4, .24, .08), disc(.5, .5, .12)),
    "areas": union(ring(.38, .5, .24, .08), ring(.62, .5, .24, .08)),
    "givers": union(line(.5, .14, .5, .6, .16), disc(.5, .82, .09)),
    "arrow": union(tri(.5, .1, .82, .52, .18, .52), box(.4, .5, .6, .88)),
    "list": union(*[union(disc(.2, y, .055), line(.34, y, .84, y, .075)) for y in (.25, .5, .75)]),
    "minimap": union(ring(.5, .5, .38, .08), disc(.5, .5, .08), line(.5, .12, .5, .22, .07)),
    "close": union(line(.24, .24, .76, .76, .095), line(.76, .24, .24, .76, .095)),
}

os.makedirs(OUT, exist_ok=True)
for name, shape in ICONS.items():
    rows = []
    for py in range(S):
        row = bytearray()
        for px in range(S):
            n = sum(shape((px + (i + .5) / SS) / S, (py + (j + .5) / SS) / S) for i in range(SS) for j in range(SS))
            row += bytes((255, 255, 255, round(255 * n / (SS * SS))))
        rows.append(bytes(row))
    # TGA: bottom-left origin, so write rows bottom-up
    hdr = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, S, S, 32, 8)
    with open(f"{OUT}/{name}.tga", "wb") as f:
        f.write(hdr + b"".join(reversed(rows)))
print("wrote", len(ICONS), "icons")
