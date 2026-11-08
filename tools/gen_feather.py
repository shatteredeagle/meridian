"""Generates Meridian/Media/feather.tga: a white square whose alpha fades to 0 at every edge (smoothstep).
Used as a mask on each stitched zone so neighbouring zone maps blend instead of showing hard rectangles.
Run from the repo root: python3 tools/gen_feather.py"""
import struct

S = 128
FADE = 0.14  # fraction of the width/height over which the edge fades out

def smooth(t):
    t = max(0.0, min(1.0, t))
    return t * t * (3 - 2 * t)

rows = []
for py in range(S):
    row = bytearray()
    for px in range(S):
        x, y = (px + .5) / S, (py + .5) / S
        a = smooth(min(x, 1 - x, y, 1 - y) / FADE)
        row += bytes((255, 255, 255, round(255 * a)))
    rows.append(bytes(row))
hdr = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, S, S, 32, 8)
with open("Meridian/Media/feather.tga", "wb") as f:
    f.write(hdr + b"".join(reversed(rows)))
print("wrote Meridian/Media/feather.tga")
