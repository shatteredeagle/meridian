"""Generates Meridian/Media/feather.tga (narrow, for overlay detail) and feather_wide.tga (for base art): a white square
whose alpha fades to 0 at every edge (smoothstep).
Used as a mask on each stitched zone so neighbouring zone maps blend instead of showing hard rectangles.
Run from the repo root: python3 tools/gen_feather.py"""
import struct

S = 128

def smooth(t):
    t = max(0.0, min(1.0, t))
    return t * t * (3 - 2 * t)

def write(name, fade):
    rows = []
    for py in range(S):
        row = bytearray()
        for px in range(S):
            x, y = (px + .5) / S, (py + .5) / S
            a = smooth(min(x, 1 - x, y, 1 - y) / fade)
            row += bytes((255, 255, 255, round(255 * a)))
        rows.append(bytes(row))
    hdr = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, S, S, 32, 8)
    with open("Meridian/Media/%s.tga" % name, "wb") as f:
        f.write(hdr + b"".join(reversed(rows)))
    print("wrote Meridian/Media/%s.tga (fade %.2f)" % (name, fade))

write("feather", 0.08)       # overlay detail: stays crisp up to the zone edge
write("feather_wide", 0.22)  # base art: neighbouring zones' parchment blends over a wide band
