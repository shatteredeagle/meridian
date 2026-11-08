#!/usr/bin/env python3
"""Build docs/pixelmap/layout.json: the Eastern Kingdoms stitch exactly as Meridian's Canvas:BuildContinent does it.

Input: DB2 CSVs for the installed build (tools/pixelmap/fetch_db2.sh puts them in $PIXELMAP_WORK/db2).
Canvas units are Meridian's: YARDS_TO_PX = 0.35, canvas x = -worldY, canvas y = -worldX (map left->right is
decreasing world Y, top->bottom decreasing world X), origin at the min corner over all zone rects.
The pixel-art grid is ART_SCALE canvas units per art pixel; output tiles are TILE art pixels square.

usage: layout.py DB2_DIR OUT_JSON
"""
import csv, json, math, sys

YARDS_TO_PX = 0.35
ART_SCALE = 2          # canvas units per art pixel (art = 0.175 px/yd, ~5.7 yd per pixel)
TILE = 256             # art pixels per output tile edge
CONTINENT = 1415

# Preview crops, as zone groups; the crop is the union of their rects (canvas units), snapped to whole art pixels.
CROPS = {
    "stormwind-elwynn": [1453, 1429],
    "ironforge-dunmorogh": [1455, 1426],
    "steppes-gorge": [1428, 1427],
}


def rows(d, name):
    with open(f"{d}/{name}.csv", newline="") as f:
        return list(csv.DictReader(f))


def main(db2, out):
    uimap = {int(r["ID"]): r for r in rows(db2, "UiMap")}
    kids = [i for i, r in uimap.items() if int(r["ParentUiMapID"]) == CONTINENT and int(r["Type"]) == 3]
    assign = {}
    for r in rows(db2, "UiMapAssignment"):
        u = int(r["UiMapID"])
        if u in kids and int(r["OrderIndex"]) == 0:
            assign[u] = r
    xart = {int(r["UiMapID"]): int(r["UiMapArtID"]) for r in rows(db2, "UiMapXMapArt")}
    art_style = {int(r["ID"]): int(r["UiMapArtStyleID"]) for r in rows(db2, "UiMapArt")}
    style = {int(r["UiMapArtStyleID"]): r for r in rows(db2, "UiMapArtStyleLayer") if r["LayerIndex"] == "0"}
    tiles = {}
    for r in rows(db2, "UiMapArtTile"):
        if r["LayerIndex"] == "0":
            tiles.setdefault(int(r["UiMapArtID"]), []).append((int(r["RowIndex"]), int(r["ColIndex"]), int(r["FileDataID"])))
    ovtiles = {}
    for r in rows(db2, "WorldMapOverlayTile"):
        ovtiles.setdefault(int(r["WorldMapOverlayID"]), []).append((int(r["RowIndex"]), int(r["ColIndex"]), int(r["FileDataID"])))
    overlays = {}
    for r in rows(db2, "WorldMapOverlay"):
        oid = int(r["ID"])
        overlays.setdefault(int(r["UiMapArtID"]), []).append({
            "id": oid, "w": int(r["TextureWidth"]), "h": int(r["TextureHeight"]),
            "x": int(r["OffsetX"]), "y": int(r["OffsetY"]),
            "tiles": sorted(ovtiles.get(oid, [])),
        })

    zones = []
    for u in sorted(kids):
        a = assign.get(u)
        if not a:
            continue
        xmin, ymin, xmax, ymax = (float(a[k]) for k in ("Region_0", "Region_1", "Region_3", "Region_4"))
        # Meridian: c.x0 = p00[ax]*sx with p00 = world(xmax, ymax), ax = Y, sx = -1 etc.
        zones.append({"id": u, "name": uimap[u]["Name_lang"], "world": [xmin, ymin, xmax, ymax],
                      "x0": -ymax, "y0": -xmax, "x1": -ymin, "y1": -xmin})
    minx = min(z["x0"] for z in zones); maxx = max(z["x1"] for z in zones)
    miny = min(z["y0"] for z in zones); maxy = max(z["y1"] for z in zones)
    for z in zones:
        z["rect"] = [(z["x0"] - minx) * YARDS_TO_PX, (z["y0"] - miny) * YARDS_TO_PX,
                     (z["x1"] - z["x0"]) * YARDS_TO_PX, (z["y1"] - z["y0"]) * YARDS_TO_PX]
        for k in ("x0", "y0", "x1", "y1"):
            del z[k]
        art = xart.get(z["id"])
        st = style[art_style[art]]
        z["art"] = {"uiMapArtID": art, "layerWidth": int(st["LayerWidth"]), "layerHeight": int(st["LayerHeight"]),
                    "tileWidth": int(st["TileWidth"]), "tileHeight": int(st["TileHeight"]),
                    "tiles": sorted(tiles.get(art, [])), "overlays": overlays.get(art, [])}
        z["area"] = abs(z["rect"][2] * z["rect"][3])
    zones.sort(key=lambda z: -z["area"])  # Meridian's draw order: big zones behind small ones
    cw, ch = (maxx - minx) * YARDS_TO_PX, (maxy - miny) * YARDS_TO_PX
    aw, ah = math.ceil(cw / ART_SCALE), math.ceil(ch / ART_SCALE)
    tx, ty = math.ceil(aw / TILE), math.ceil(ah / TILE)
    byid = {z["id"]: z for z in zones}
    crops = {}
    for name, ids in CROPS.items():
        x0 = min(byid[i]["rect"][0] for i in ids); y0 = min(byid[i]["rect"][1] for i in ids)
        x1 = max(byid[i]["rect"][0] + byid[i]["rect"][2] for i in ids)
        y1 = max(byid[i]["rect"][1] + byid[i]["rect"][3] for i in ids)
        crops[name] = [int(x0 // ART_SCALE), int(y0 // ART_SCALE), math.ceil(x1 / ART_SCALE), math.ceil(y1 / ART_SCALE)]
    doc = {
        "continent": CONTINENT, "yardsToPx": YARDS_TO_PX, "artScale": ART_SCALE, "tile": TILE,
        "stitchOrigin": {"minx": minx, "miny": miny, "note": "canvas = ((-worldY) - minx, (-worldX) - miny) * yardsToPx"},
        "canvas": [cw, ch], "art": [aw, ah], "tiles": [tx, ty], "padded": [tx * TILE, ty * TILE],
        "crops": crops, "zones": zones,
    }
    with open(out, "w") as f:
        json.dump(doc, f, indent=1)
    print(f"{len(zones)} zones, canvas {cw:.1f}x{ch:.1f}, art {aw}x{ah}, tiles {tx}x{ty}")


if __name__ == "__main__":
    main(*sys.argv[1:3])
