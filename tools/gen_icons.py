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
    "dungeons": union(line(.2, .88, .2, .46, .09), line(.8, .88, .8, .46, .09), line(.1, .88, .9, .88, .09)),  # doorway (arch added below)
    "arrow": union(tri(.5, .1, .82, .52, .18, .52), box(.4, .5, .6, .88)),
    "list": union(*[union(disc(.2, y, .055), line(.34, y, .84, y, .075)) for y in (.25, .5, .75)]),
    "minimap": union(ring(.5, .5, .38, .08), disc(.5, .5, .08), line(.5, .12, .5, .22, .07)),
    "gear": union(ring(.5, .5, .27, .14), *[line(.5 + .3 * math.cos(a * math.pi / 4), .5 + .3 * math.sin(a * math.pi / 4),
                                          .5 + .43 * math.cos(a * math.pi / 4), .5 + .43 * math.sin(a * math.pi / 4), .14) for a in range(8)]),
    "check": union(line(.14, .56, .4, .82, .16), line(.4, .82, .88, .2, .16)),
    "close": union(line(.24, .24, .76, .76, .095), line(.76, .24, .24, .76, .095)),
}

def arc(cx, cy, r, a0, a1, w=0.1):
    """Part of a ring between angles a0..a1 (degrees, 0 = east, clockwise on screen)."""
    def f(x, y):
        if abs(math.hypot(x - cx, y - cy) - r) > w / 2: return False
        a = math.degrees(math.atan2(y - cy, x - cx)) % 360
        return (a - a0) % 360 <= (a1 - a0) % 360
    return f
def star(cx, cy, ro, ri, n=5):
    pts = [(cx + (ro if i % 2 == 0 else ri) * math.sin(math.pi * i / n),
            cy - (ro if i % 2 == 0 else ri) * math.cos(math.pi * i / n)) for i in range(2 * n)]
    return union(*[tri(cx, cy, *pts[i], *pts[(i + 1) % (2 * n)]) for i in range(2 * n)])

ICONS["art"] = union(frame(.12, .18, .88, .82, .08), disc(.7, .38, .07), tri(.2, .74, .45, .42, .6, .74), tri(.42, .74, .66, .5, .84, .74))  # picture frame with a mountain and sun
ICONS["pin"] = lambda x, y: (disc(.5, .36, .26)(x, y) or tri(.27, .5, .73, .5, .5, .92)(x, y)) and not disc(.5, .36, .1)(x, y)  # map pin with a hole
ICONS["dungeons"] = union(ICONS["dungeons"], arc(.5, .46, .3, 180, 360, .09), box(.42, .6, .58, .88))  # arched doorway

# Map pins: a white fill with a black outline (tinted by vertex color in-game; the outline stays dark).
# Each has a distinct silhouette so type never depends on colour alone.
PINS = {
    "way": union(disc(.5, .36, .24), tri(.28, .5, .72, .5, .5, .94)),            # teardrop
    "give": union(line(.5, .16, .5, .56, .2), disc(.5, .8, .1)),                  # !
    "turnin": union(arc(.5, .33, .2, 180, 90, .17), line(.5, .53, .5, .62, .17), disc(.5, .84, .1)),  # ?
    "taxi": union(tri(.5, .1, .9, .86, .5, .66), tri(.5, .1, .1, .86, .5, .66)),  # arrowhead
    "rare": star(.5, .52, .44, .19),
    "poi": union(tri(.5, .08, .92, .5, .08, .5), tri(.5, .92, .92, .5, .08, .5)),  # diamond
    "party": union(box(.2, .2, .8, .8)),
    "dungeon": union(box(.16, .45, .84, .9), box(.16, .12, .28, .45), box(.44, .12, .56, .45), box(.72, .12, .84, .45)),  # castle gate                                           # square
}

def write_tga(path, rows):
    # TGA: bottom-left origin, so write rows bottom-up
    hdr = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, S, S, 32, 8)
    with open(path, "wb") as f:
        f.write(hdr + b"".join(reversed(rows)))

def cover(shape, px, py, grow=0.0):
    hits = 0
    for i in range(SS):
        for j in range(SS):
            x, y = (px + (i + .5) / SS) / S, (py + (j + .5) / SS) / S
            if grow:
                hit = any(shape(x + grow * math.cos(a * math.pi / 4), y + grow * math.sin(a * math.pi / 4)) for a in range(8)) or shape(x, y)
            else:
                hit = shape(x, y)
            hits += hit
    return hits / (SS * SS)

os.makedirs(OUT, exist_ok=True)
for name, shape in ICONS.items():
    rows = []
    for py in range(S):
        row = bytearray()
        for px in range(S):
            row += bytes((255, 255, 255, round(255 * cover(shape, px, py))))
        rows.append(bytes(row))
    write_tga(f"{OUT}/{name}.tga", rows)

PIN_OUT = "Meridian/Media/pins"
os.makedirs(PIN_OUT, exist_ok=True)
for name, shape in PINS.items():
    rows = []
    for py in range(S):
        row = bytearray()
        for px in range(S):
            fill, outer = cover(shape, px, py), cover(shape, px, py, 0.05)
            v = 255 if fill > 0 else 0
            row += bytes((v, v, v, round(255 * max(fill, outer))))
        rows.append(bytes(row))
    write_tga(f"{PIN_OUT}/{name}.tga", rows)
print("wrote", len(ICONS), "icons and", len(PINS), "pins")
