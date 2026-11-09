#!/usr/bin/env python3
"""Ground materials, trees and buildings for Method B, from ADT *data* (texture-layer names and weights, placements).

usage: features.py LAYOUT ADT_DIR LISTFILE_CSV OUT_DIR
  OUT_DIR/material.png  L-mode, one material class per art pixel (see CLASSES)
  OUT_DIR/road.png      L-mode, road/paving weight 0..255 per art pixel (thin roads survive downsampling)
  OUT_DIR/objects.json  {"trees": [[x, y, size, kind], ...], "buildings": [[x0, y0, x1, y1, name], ...]} in art px

No texture pixels are read: a material is chosen from the tileset *file name* (e.g. ".../elwynncobblestonebase_s.blp"
-> road) and weighted by the layer alpha maps.
"""
import json, os, re, struct, sys
from multiprocessing import Pool
import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(__file__))
from terrain import chunks, ORIGIN, CELL_YD  # noqa: E402

CLASSES = ["void", "grass", "dirt", "rock", "sand", "snow", "road", "farm", "ash", "lava", "blight", "mud", "seabed"]
RULES = [  # first match wins
    ("lava", r"lava"),
    ("road", r"road|cobble|brick|paver|cityfloor|footprint|trolltile|dock|pillartile"),
    ("farm", r"crop|straw"),
    ("snow", r"snow|ice"),
    ("ash", r"ash|charcoal|black_s|blastedlandsblack|chardrock|cooled|obsid"),
    ("blight", r"blight|creep|corrupt|plaguedearth|slime"),
    ("seabed", r"underwater|oceanfloor|coral|seaweed|vashjir"),
    ("sand", r"sand|shore|beach"),
    ("grass", r"grass|flower|moss|leaf|leaves|fern|plant|weed|needle|underbrush|scrub|vine|root"),
    ("rock", r"rock|rubble|shale|gravel|mountain|stone|crack|spire"),
    ("mud", r"mud|muck"),
    ("dirt", r"."),
]
NC = len(CLASSES)
ROAD = CLASSES.index("road")


def classify(name):
    base = name.rsplit("/", 1)[-1]
    for cls, rx in RULES:
        if re.search(rx, base):
            return CLASSES.index(cls)
    return CLASSES.index("dirt")


def rle(buf, p):
    out = bytearray()
    while len(out) < 4096:
        b = buf[p]; p += 1
        n = b & 0x7F
        if b & 0x80:
            out += bytes([buf[p]]) * n; p += 1
        else:
            out += buf[p:p + n]; p += n
    return np.frombuffer(bytes(out[:4096]), np.uint8).reshape(64, 64)


def tex_weights(args):
    """Per-cell class weights (NC, 128, 128) uint8 for one tex0 file."""
    path, texclass = args
    buf = open(path, "rb").read()
    mdid = []
    mcnk = []
    for tag, off, size in chunks(buf):
        if tag == "MDID":
            mdid = [struct.unpack_from("<I", buf, off + i * 4)[0] for i in range(size // 4)]
        elif tag == "MCNK":
            mcnk.append((off, size))
    W = np.zeros((NC, 128, 128), np.float32)
    for ci, (off, size) in enumerate(mcnk[:256]):
        cy, cx = divmod(ci, 16)
        layers, mcal = [], None
        for tag, so, ss in chunks(buf, off, off + size):
            if tag == "MCLY":
                layers = [struct.unpack_from("<IIIi", buf, so + i * 16) for i in range(ss // 16)]
            elif tag == "MCAL":
                mcal = so
        if not layers:
            continue
        rem = np.ones((64, 64), np.float32)
        ws = [None] * len(layers)
        for li in range(len(layers) - 1, 0, -1):  # sequential blend: top layer wins its alpha
            tid, fl, ao, _ = layers[li]
            if mcal is None or not fl & 0x100:
                a = np.zeros((64, 64), np.float32)
            elif fl & 0x200:
                a = rle(buf, mcal + ao).astype(np.float32) / 255
            else:
                a = np.frombuffer(buf, np.uint8, 4096, mcal + ao).reshape(64, 64).astype(np.float32) / 255
            ws[li] = a * rem
            rem = rem * (1 - a)
        ws[0] = rem
        for li, (tid, *_r) in enumerate(layers):
            fid = mdid[tid] if tid < len(mdid) else 0
            c = texclass.get(fid, CLASSES.index("dirt"))
            cell = ws[li].reshape(8, 8, 8, 8).mean(axis=(1, 3))
            W[c, cy * 8:cy * 8 + 8, cx * 8:cx * 8 + 8] += cell
    return np.clip(W * 255, 0, 255).astype(np.uint8)


def tree_kind(name):
    n = name.rsplit("/", 1)[-1]
    if not re.search(r"tree|pine|palm|oak|bush|shrub|willow|redwood|jungletree|canopy|aspen|birch", n):
        return None
    if re.search(r"stump|log|fallen|leaf_|branch|root|seedling|sapling|trunk", n):
        return None
    if re.search(r"bush|shrub", n):
        return "bush"
    if re.search(r"palm", n):
        return "palm"
    if re.search(r"dead|burn|burnt|bare|plague|blight|ash|charred|spooky|duskwood", n):
        return "dead"
    if re.search(r"pine|snow|conifer|redwood|fir|spruce|evergreen|silverpine|alterac|dunmorogh|winter", n):
        return "pine"
    if re.search(r"jungle|stranglethorn|vine", n):
        return "jungle"
    return "leaf"


def main(layout, adt_dir, listfile, out):
    os.makedirs(out, exist_ok=True)
    L = json.load(open(layout))
    minx, miny = L["stitchOrigin"]["minx"], L["stitchOrigin"]["miny"]
    k, s = L["yardsToPx"], L["artScale"]
    aw, ah = L["art"]
    idx = [tuple(map(int, l.split())) for l in open(f"{adt_dir}/index.txt")]
    # names for every texture / model id referenced
    need = set()
    for root, x, y, obj0, tex0 in idx:
        b = open(f"{adt_dir}/{tex0}.blp", "rb").read()
        for tag, off, size in chunks(b):
            if tag == "MDID":
                need |= {struct.unpack_from("<I", b, off + i * 4)[0] for i in range(size // 4)}
    objs = {}
    for root, x, y, obj0, tex0 in idx:
        b = open(f"{adt_dir}/{obj0}.blp", "rb").read()
        m = []
        for tag, off, size in chunks(b):
            if tag == "MDDF":
                for i in range(size // 36):
                    nid, _u, px, py, pz, _a, _b, _c, sc, fl = struct.unpack_from("<II6fHH", b, off + i * 36)
                    m.append(("m2", nid, px, pz, sc / 1024.0))
                    need.add(nid)
            elif tag == "MODF":
                for i in range(size // 64):
                    nid, _u, px, py, pz, _a, _b, _c, x0, y0, z0, x1, y1, z1 = struct.unpack_from("<II12f", b, off + i * 64)
                    m.append(("wmo", nid, x0, z0, x1, z1))
                    need.add(nid)
        objs[(x, y)] = m
    names = {}
    with open(listfile, encoding="utf8", errors="replace") as f:
        for line in f:
            i, _, n = line.partition(";")
            if int(i) in need:
                names[int(i)] = n.strip()
    texclass = {fid: classify(names.get(fid, "")) for fid in need}

    xs = [r[1] for r in idx]; ys = [r[2] for r in idx]
    tx0, ty0 = min(xs), min(ys)
    Wd, Hd = (max(xs) + 1 - tx0) * 128, (max(ys) + 1 - ty0) * 128
    grid = np.zeros((NC, Hd, Wd), np.uint8)
    with Pool(min(16, os.cpu_count() or 4)) as pool:
        res = pool.map(tex_weights, [(f"{adt_dir}/{r[4]}.blp", texclass) for r in idx], chunksize=8)
    for r, w in zip(idx, res):
        gx, gy = (r[1] - tx0) * 128, (r[2] - ty0) * 128
        grid[:, gy:gy + 128, gx:gx + 128] = w
    # art pixel (i, j) covers canvas [i*s, (i+1)*s) -> cells; box-average each class onto the art grid
    cx0 = ((0 / k + minx) + ORIGIN) / CELL_YD - tx0 * 128
    cy0 = ((0 / k + miny) + ORIGIN) / CELL_YD - ty0 * 128
    cx1 = ((aw * s / k + minx) + ORIGIN) / CELL_YD - tx0 * 128
    cy1 = ((ah * s / k + miny) + ORIGIN) / CELL_YD - ty0 * 128
    art = np.zeros((NC, ah, aw), np.float32)
    for c in range(NC):
        im = Image.fromarray(grid[c])
        art[c] = np.asarray(im.resize((aw, ah), Image.BOX, box=(cx0, cy0, cx1, cy1)), np.float32)
    mat = art.argmax(0).astype(np.uint8)
    mat[art.max(0) < 1] = 0
    road = art[ROAD]
    Image.fromarray(mat).save(f"{out}/material.png")
    Image.fromarray(np.clip(road, 0, 255).astype(np.uint8)).save(f"{out}/road.png")

    def to_art(px, pz):
        return ((px - ORIGIN - minx) * k / s, (pz - ORIGIN - miny) * k / s)

    trees, blds, wnames = [], [], {}
    for m in objs.values():
        for o in m:
            if o[0] == "m2":
                kind = tree_kind(names.get(o[1], ""))
                if kind:
                    x, y = to_art(o[2], o[3])
                    if 0 <= x < aw and 0 <= y < ah:
                        trees.append([round(x, 1), round(y, 1), round(o[4], 2), kind])
            else:
                x0, y0 = to_art(o[2], o[3]); x1, y1 = to_art(o[4], o[5])
                n = names.get(o[1], str(o[1])).rsplit("/", 1)[-1]
                blds.append([round(min(x0, x1), 1), round(min(y0, y1), 1), round(max(x0, x1), 1), round(max(y0, y1), 1), n])
                wnames[n] = wnames.get(n, 0) + 1
    # one WMO can be placed from several ADTs (same uniqueId); dedupe by rect+name
    blds = [list(b) for b in {tuple(b) for b in blds}]
    json.dump({"trees": trees, "buildings": blds}, open(f"{out}/objects.json", "w"))
    counts = np.bincount(mat.ravel(), minlength=NC)
    print("materials:", {CLASSES[i]: int(c) for i, c in enumerate(counts)})
    print(f"trees {len(trees)}, buildings {len(blds)}")


if __name__ == "__main__":
    main(*sys.argv[1:5])
