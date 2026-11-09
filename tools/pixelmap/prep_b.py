#!/usr/bin/env python3
"""Pack Method B/C data layers into two RGB PNGs + a POI list that the Aseprite renderer reads.

usage: prep_b.py LAYOUT TERRAIN_NPZ FEAT_DIR DB2_DIR ENTRANCES_LUA OUT_DIR
  OUT_DIR/b_land.png   R = material class, G = biome, B = hillshade (0..255, 128 = flat)
  OUT_DIR/b_water.png  R = liquid (0 none, 1 water, 2 ocean, 3 magma, 4 slime), G = distance to land in px on water
                       (1..250) or 255 on a coast land pixel, B = road weight
  OUT_DIR/pois.json    dungeon entrances and cities in art px
"""
import csv, json, os, re, sys
import numpy as np
from PIL import Image
from scipy import ndimage

BIOMES = {  # root AreaTable ID -> biome index (see palette ramps in b_render.lua)
    "lush": [12, 38, 267, 47, 44, 16591],
    "dark": [10, 130, 17065, 16756, 85, 36, 41, 8],
    "jungle": [33, 408, 17066],
    "dry": [40, 45],
    "marsh": [11],
    "plague": [28, 139],
    "snow": [1],
    "burnt": [46],
    "city": [1519],
    "red": [3, 51, 4],
}
BIOME_IDS = ["none"] + list(BIOMES)


def main(layout, npz, feat, db2, entrances, out):
    os.makedirs(out, exist_ok=True)
    L = json.load(open(layout))
    aw, ah = L["art"]
    s, k = L["artScale"], L["yardsToPx"]
    T = np.load(npz)
    h, liq, area = T["height"], T["liquid"], T["area"]
    parent = {int(r["ID"]): int(r["ParentAreaID"]) for r in csv.DictReader(open(f"{db2}/AreaTable.csv"))}

    def root(a):
        seen = 0
        while parent.get(a, 0) and seen < 6:
            a = parent[a]; seen += 1
        return a
    lut = {}
    for name, ids in BIOMES.items():
        for i in ids:
            lut[i] = BIOME_IDS.index(name)
    biome = np.zeros(area.shape, np.uint8)
    for a in np.unique(area):
        if a:
            biome[area == a] = lut.get(root(int(a)), BIOME_IDS.index("lush"))
    # organic biome borders: area IDs are per 33-yard chunk, so sample them through a smooth random displacement
    rng = np.random.default_rng(7)
    def smooth_field(sigma, amp):
        f = ndimage.gaussian_filter(rng.standard_normal(area.shape).astype(np.float32), sigma)
        return f / (f.std() + 1e-6) * amp
    yy, xx = np.mgrid[0:area.shape[0], 0:area.shape[1]]
    jx = np.clip(xx + smooth_field(6, 4) + smooth_field(2, 1.5), 0, area.shape[1] - 1).astype(int)
    jy = np.clip(yy + smooth_field(6, 4) + smooth_field(2, 1.5), 0, area.shape[0] - 1).astype(int)
    biome = biome[jy, jx]
    # hillshade: yards per art px = s / k; light from the north-west, exaggerated x2
    hf = np.where(np.isfinite(h), h, -50.0).astype(np.float32)
    hf = ndimage.gaussian_filter(hf, 0.8)
    ypp = s / k
    gy, gx = np.gradient(hf, ypp)
    nx, ny, nz = -gx * 2.0, -gy * 2.0, np.ones_like(hf)
    n = np.sqrt(nx * nx + ny * ny + nz * nz)
    lx, ly, lz = -0.6, -0.6, 0.53
    dot = (nx * lx + ny * ly + nz * lz) / n
    flat = lz
    shade = np.clip(128 + (dot - flat) * 260, 0, 255).astype(np.uint8)
    mat = np.asarray(Image.open(f"{feat}/material.png"))
    road = np.asarray(Image.open(f"{feat}/road.png"))
    void = ~np.isfinite(h)
    water = (liq > 0) | void
    land = ~water
    # water: G = distance to land in px (1..250, Lua bands it with dithering); coast land pixels get 255
    dist = ndimage.distance_transform_edt(water)
    band = np.zeros(h.shape, np.uint8)
    band[water] = np.clip(dist[water], 1, 250).astype(np.uint8)
    coast = land & ndimage.binary_dilation(water, structure=np.ones((3, 3), bool))
    band[coast] = 255
    liquid = np.where(void, 2, liq).astype(np.uint8)
    # open sea is often typed plain "Water" in the ADTs: any water body touching the map edge counts as ocean
    lab, _n = ndimage.label(water & (liquid <= 2))
    edge = np.unique(np.concatenate([lab[0], lab[-1], lab[:, 0], lab[:, -1]]))
    sea = np.isin(lab, edge[edge > 0])
    liquid[sea] = 2
    land_img = np.stack([mat, biome, shade], -1)
    water_img = np.stack([liquid, band, road], -1)
    Image.fromarray(land_img).save(f"{out}/b_land.png")
    Image.fromarray(water_img).save(f"{out}/b_water.png")

    zones = {z["id"]: z for z in L["zones"]}
    pois = []
    src = open(entrances, encoding="utf8").read()
    for m in re.finditer(r'\["([^"]+)"\]\s*=\s*\{\s*mapID\s*=\s*(\d+),\s*x\s*=\s*([\d.]+),\s*y\s*=\s*([\d.]+).*?markerType\s*=\s*"(\w+)"', src, re.S):
        name, mid, x, y, kind = m.group(1), int(m.group(2)), float(m.group(3)), float(m.group(4)), m.group(5)
        z = zones.get(mid)
        if not z:
            continue
        rx, ry, rw, rh = z["rect"]
        pois.append({"name": name, "kind": kind, "x": round((rx + x * rw) / s, 1), "y": round((ry + y * rh) / s, 1)})
    # merge entrances that share a spot (Scarlet Monastery wings)
    uniq = {}
    for p in pois:
        uniq.setdefault((round(p["x"]), round(p["y"])), p)
    pois = list(uniq.values())
    for cid, name in ((1453, "Stormwind City"), (1455, "Ironforge"), (1458, "Undercity")):
        rx, ry, rw, rh = zones[cid]["rect"]
        pois.append({"name": name, "kind": "city", "x": round((rx + rw / 2) / s, 1), "y": round((ry + rh / 2) / s, 1),
                     "rect": [round(rx / s, 1), round(ry / s, 1), round(rw / s, 1), round(rh / s, 1)]})
    json.dump(pois, open(f"{out}/pois.json", "w"), indent=1)
    write_objects(f"{feat}/objects.json", pois, f"{out}/objects.lua")
    print(f"land {land.sum()} px, water {water.sum()} px, pois {len(pois)}")


BKIND = [  # first match wins; None = not drawn
    (None, r"collision|pvp_|^md_|mine|cave|crypt|tunnel|turtle|arch|excavation|railing|gate|wallpost|lowwall|zeppelin|crane"),
    ("bridge", r"bridge|dock|landingpad|platform|stair"),
    ("ruin", r"ruin|wreck|wall|destroyed|busted|burnt|abandoned"),
    ("hut", r"tent|hut|hovel|troll|burrow|mud_|ogre|orc|kennel"),
    ("tower", r"tower|silo|lighthouse|sentinel|ziggurat|spire"),
    ("house", r"."),
]


def write_objects(src, pois, out):
    o = json.load(open(src))
    lines = ["return {", "trees = {"]
    for x, y, sc, kind in o["trees"]:
        lines.append(f'{{{x},{y},{sc},"{kind}"}},')
    lines += ["},", "buildings = {"]
    kept = 0
    for x0, y0, x1, y1, name in o["buildings"]:
        w, h = x1 - x0, y1 - y0
        kind = next(k for k, rx in BKIND if re.search(rx, name))
        numeric = re.fullmatch(r"\d+\.wmo", name) is not None
        if not kind or w > 14 or h > 14 or (numeric and max(w, h) > 6) or max(w, h) < 0.6:
            continue
        lines.append(f'{{{x0},{y0},{x1},{y1},"{kind}"}},')
        kept += 1
    lines += ["},", "big = {"]  # large WMOs by name, for the C landmarks
    for x0, y0, x1, y1, name in o["buildings"]:
        if x1 - x0 > 14 or y1 - y0 > 14:
            lines.append(f'{{{x0},{y0},{x1},{y1},{json.dumps(name)}}},')
    lines += ["},", "pois = {"]
    for p in pois:
        r = p.get("rect")
        rs = f",rect={{{r[0]},{r[1]},{r[2]},{r[3]}}}" if r else ""
        lines.append(f'{{name={json.dumps(p["name"])},kind="{p["kind"]}",x={p["x"]},y={p["y"]}{rs}}},')
    lines += ["},", "}"]
    open(out, "w").write("\n".join(lines))
    print(f"objects.lua: {len(o['trees'])} trees, {kept} buildings")


if __name__ == "__main__":
    main(*sys.argv[1:7])
