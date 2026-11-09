#!/usr/bin/env python3
"""Read Eastern Kingdoms terrain *data* (not map art) from extracted ADT files and resample it onto the art grid.

Steps:
  terrain.py fdids WDT_FILE OUT_TXT          list root-ADT FileDataIDs from azeroth.wdt (MAID chunk)
  terrain.py grid LAYOUT ADT_DIR DB2_DIR OUT_NPZ
      -> heights (yards), liquid (0 none / 1 water / 2 ocean / 3 magma / 4 slime) and areaID per art pixel.

The grid step reads only height samples (MCVT), the chunk area ID and the liquid table (MH2O): geometry, no textures.
World <-> grid: global cell gx = tileX*128 + chunkX*8 + cellX, world Y = 17066.667 - gx*4.1667 (same for X with rows).
"""
import csv, json, os, struct, sys
import numpy as np

TILE_YD = 1600.0 / 3.0
CELL_YD = TILE_YD / 128.0
ORIGIN = 32 * TILE_YD


def chunks(buf, start=0, end=None):
    end = len(buf) if end is None else end
    p = start
    while p + 8 <= end:
        tag = buf[p:p + 4][::-1].decode("latin1")
        size = struct.unpack_from("<I", buf, p + 4)[0]
        yield tag, p + 8, size
        p += 8 + size


def wdt_fdids(path, out):
    buf = open(path, "rb").read()
    ids = []
    for tag, off, size in chunks(buf):
        if tag == "MAID":
            for i in range(64 * 64):
                root, obj0, _obj1, tex0 = struct.unpack_from("<IIII", buf, off + i * 32)
                if root:
                    ids.append((i % 64, i // 64, root, obj0, tex0))
    with open(out, "w") as f:  # root x y obj0 tex0
        for x, y, fid, obj0, tex0 in ids:
            f.write(f"{fid} {x} {y} {obj0} {tex0}\n")
    print(f"{len(ids)} ADTs")


def parse_adt(buf):
    """Yield (chunkX, chunkY, area, heights[9x9 outer], liquid[8x8]) per MCNK."""
    mh2o = None
    mcnks = []
    for tag, off, size in chunks(buf):
        if tag == "MH2O":
            mh2o = (off, size)
        elif tag == "MCNK":
            mcnks.append((off, size))
    liq = [None] * 256
    if mh2o:
        base = mh2o[0]
        for i in range(256):
            o_inst, n_layers, _ = struct.unpack_from("<III", buf, base + i * 12)
            if not n_layers:
                continue
            grid = np.zeros((8, 8), np.uint8)
            for l in range(n_layers):
                p = base + o_inst + l * 24
                ltype, _lvf, _mn, _mx, xo, yo, w, h, o_bits, _ov = struct.unpack_from("<HHffBBBBII", buf, p)
                kind = LIQ.get(ltype, 1)
                bits = None
                if o_bits:
                    nb = (w * h + 7) // 8
                    raw = buf[base + o_bits: base + o_bits + nb]
                    bits = np.unpackbits(np.frombuffer(raw, np.uint8), bitorder="little")[: w * h].reshape(h, w)
                for yy in range(h):
                    for xx in range(w):
                        if bits is None or bits[yy, xx]:
                            if 0 <= yo + yy < 8 and 0 <= xo + xx < 8:
                                grid[yo + yy, xo + xx] = max(grid[yo + yy, xo + xx], kind) if kind != 2 else 2
            liq[i] = grid
    for off, size in mcnks:
        flags, ix, iy = struct.unpack_from("<III", buf, off)
        area = struct.unpack_from("<I", buf, off + 0x34)[0]
        posz = struct.unpack_from("<f", buf, off + 0x68 + 8)[0]
        hts = None
        for tag, so, ssize in chunks(buf, off + 128, off + size):
            if tag == "MCVT":
                v = np.frombuffer(buf, np.float32, 145, so)
                # 145 = 9 outer + 8 inner per row pair; keep the 9x9 outer grid
                outer = np.concatenate([v[r * 17: r * 17 + 9] for r in range(9)]).reshape(9, 9)
                hts = outer + posz
        yield ix, iy, area, hts, liq[iy * 16 + ix]


LIQ = {}


def build_grid(layout, adt_dir, db2, out):
    for r in csv.DictReader(open(f"{db2}/LiquidType.csv")):
        LIQ[int(r["ID"])] = int(r["SoundBank"]) + 1  # 1 water 2 ocean 3 magma 4 slime
    L = json.load(open(layout))
    minx, miny = L["stitchOrigin"]["minx"], L["stitchOrigin"]["miny"]
    k, s = L["yardsToPx"], L["artScale"]
    aw, ah = L["art"]
    idx = {}
    for line in open(f"{adt_dir}/index.txt"):
        fid, x, y = map(int, line.split()[:3])
        idx[(x, y)] = fid
    # global cell grid covering all tiles present (64*128 cells per side is too big; crop to tile bbox)
    xs = [x for x, _ in idx]; ys = [y for _, y in idx]
    tx0, tx1, ty0, ty1 = min(xs), max(xs) + 1, min(ys), max(ys) + 1
    W, H = (tx1 - tx0) * 128, (ty1 - ty0) * 128
    height = np.full((H, W), np.nan, np.float32)
    liquid = np.zeros((H, W), np.uint8)
    area = np.zeros((H, W), np.uint32)
    for (tx, ty), fid in idx.items():
        p = f"{adt_dir}/{fid}.blp"
        if not os.path.exists(p):
            continue
        buf = open(p, "rb").read()
        for cx, cy, a, hts, lq in parse_adt(buf):
            gx, gy = (tx - tx0) * 128 + cx * 8, (ty - ty0) * 128 + cy * 8
            area[gy:gy + 8, gx:gx + 8] = a
            if hts is not None:
                # cell value = mean of its 4 corner heights
                height[gy:gy + 8, gx:gx + 8] = (hts[:-1, :-1] + hts[1:, :-1] + hts[:-1, 1:] + hts[1:, 1:]) / 4
            if lq is not None:
                liquid[gy:gy + 8, gx:gx + 8] = lq
    # sample each art pixel centre: canvas c = art*s + s/2 ; -worldY = c/k + minx ; gx = (ORIGIN - worldY)/CELL
    ax = (np.arange(aw) * s + s / 2) / k + minx       # = -worldY
    ay = (np.arange(ah) * s + s / 2) / k + miny       # = -worldX
    gx = np.floor((ORIGIN + ax) / CELL_YD).astype(int) - tx0 * 128
    gy = np.floor((ORIGIN + ay) / CELL_YD).astype(int) - ty0 * 128
    inside_x = (gx >= 0) & (gx < W); inside_y = (gy >= 0) & (gy < H)
    gxc, gyc = np.clip(gx, 0, W - 1), np.clip(gy, 0, H - 1)
    hs = height[np.ix_(gyc, gxc)]
    ls = liquid[np.ix_(gyc, gxc)]
    ars = area[np.ix_(gyc, gxc)]
    mask = np.outer(inside_y, inside_x)
    hs[~mask] = np.nan; ls[~mask] = 0; ars[~mask] = 0
    np.savez_compressed(out, height=hs, liquid=ls, area=ars)
    print(f"cells {W}x{H} -> art {aw}x{ah}; land px {np.isfinite(hs).sum()}, liquid px {(ls > 0).sum()}")


if __name__ == "__main__":
    if sys.argv[1] == "fdids":
        wdt_fdids(sys.argv[2], sys.argv[3])
    else:
        build_grid(*sys.argv[2:6])
