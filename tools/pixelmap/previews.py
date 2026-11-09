#!/usr/bin/env python3
"""Preview crops and the comparison sheet. All scaling is integer nearest-neighbour.

usage: previews.py crops LAYOUT FULL_PNG OUT_DIR        -> OUT_DIR/<crop>-1x.png, <crop>-4x.png
       previews.py compare LAYOUT OUT_PNG LABEL=DIR ... -> side-by-side sheet (one row per crop + a continent row)
"""
import json, sys
from PIL import Image, ImageDraw, ImageFont

FONT = None


def font():
    global FONT
    if FONT is None:
        for p in ("/usr/share/fonts/TTF/DejaVuSans-Bold.ttf", "/usr/share/fonts/dejavu/DejaVuSans-Bold.ttf"):
            try:
                FONT = ImageFont.truetype(p, 22); break
            except OSError:
                pass
        FONT = FONT or ImageFont.load_default()
    return FONT


def crops(layout, full, out):
    L = json.load(open(layout))
    im = Image.open(full).convert("RGB")
    for name, (x0, y0, x1, y1) in L["crops"].items():
        c = im.crop((x0, y0, x1, y1))
        c.save(f"{out}/{name}-1x.png")
        c.resize((c.width * 4, c.height * 4), Image.NEAREST).save(f"{out}/{name}-4x.png")
    print(f"previews in {out}")


def compare(layout, outp, cols):
    L = json.load(open(layout))
    cols = [c.split("=", 1) for c in cols]
    # rows: continent (downscaled 1/4 by nearest = 4 art px per sheet px, labelled), then each crop at 2x
    pad, head = 12, 36
    tiles = []
    for label, d in cols:
        col = []
        full = Image.open(f"{d}/full.png").convert("RGB")
        col.append(full.resize((full.width // 4, full.height // 4), Image.NEAREST))
        for name, (x0, y0, x1, y1) in L["crops"].items():
            c = Image.open(f"{d}/{name}-1x.png").convert("RGB")
            # 2x of a centred window, so the sheet stays a sane size
            w, h = min(c.width, 300), min(c.height, 260)
            cx, cy = (c.width - w) // 2, (c.height - h) // 2
            col.append(c.crop((cx, cy, cx + w, cy + h)).resize((w * 2, h * 2), Image.NEAREST))
        tiles.append((label, col))
    colw = max(max(i.width for i in col) for _, col in tiles)
    rowh = [max(col[r].height for _, col in tiles) for r in range(len(tiles[0][1]))]
    W = pad + len(tiles) * (colw + pad)
    H = head + sum(rowh) + pad * (len(rowh) + 1)
    sheet = Image.new("RGB", (W, H), (24, 22, 28))
    dr = ImageDraw.Draw(sheet)
    for ci, (label, col) in enumerate(tiles):
        x = pad + ci * (colw + pad)
        dr.text((x, 6), label, fill=(240, 220, 160), font=font())
        y = head
        for r, im in enumerate(col):
            sheet.paste(im, (x, y))
            y += rowh[r] + pad
    sheet.save(outp)
    print(f"{outp}: {W}x{H}")


if __name__ == "__main__":
    if sys.argv[1] == "crops":
        crops(*sys.argv[2:5])
    else:
        compare(sys.argv[2], sys.argv[3], sys.argv[4:])
