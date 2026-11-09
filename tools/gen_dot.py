"""Generates Meridian/Media/dot.tga: a solid white disc with a 1.5 px antialiased rim, tinted per route leg.
Run from the repo root: python3 tools/gen_dot.py"""
import struct

S = 32
R = S / 2 - 1
rows = []
for py in range(S):
    row = bytearray()
    for px in range(S):
        d = ((px + .5 - S / 2) ** 2 + (py + .5 - S / 2) ** 2) ** .5
        a = max(0.0, min(1.0, (R - d) / 1.5 + .5))
        row += bytes((255, 255, 255, round(255 * a)))
    rows.append(bytes(row))
hdr = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, S, S, 32, 8)
with open("Meridian/Media/dot.tga", "wb") as f:
    f.write(hdr + b"".join(reversed(rows)))
print("wrote Meridian/Media/dot.tga")
