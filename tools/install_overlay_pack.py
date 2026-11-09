#!/usr/bin/env python3
"""Installs the zone overlay textures the local client may lack, as a LOCAL-ONLY addon (MeridianOverlayFiles).

The Forever install here streams some game files on demand: the explored-area overlay pieces of zones you have never
visited can be absent from disk, so a "reveal" has nothing to draw. This copies those pieces (from wago.tools' mirror of the
same build, cached by tools/gen_territory.py) into AddOns/MeridianOverlayFiles/<fileDataID>.blp, and Meridian then draws
them by path. The files are Blizzard's art: keep them local, never commit or release them (git-ignored).
Also writes Meridian/OverlayPackIDs.lua (just the list of IDs).

usage: python3 tools/install_overlay_pack.py DB2_DIR CACHE_DIR ADDONS_DIR
"""
import csv, os, shutil, sys

DB2, CACHE, ADDONS = sys.argv[1:4]
uimap = {r["ID"]: r for r in csv.DictReader(open(os.path.join(DB2, "UiMap.csv"), encoding="utf-8"))}
zones = {z for z, r in uimap.items() if r["Type"] == "3" and r["ParentUiMapID"] in ("1414", "1415")}
art_of = {}
for r in csv.DictReader(open(os.path.join(DB2, "UiMapXMapArt.csv"), encoding="utf-8")):
    if r["PhaseID"] == "0" and r["UiMapID"] in zones:
        art_of.setdefault(r["UiMapArtID"], r["UiMapID"])
overlays = {r["ID"] for r in csv.DictReader(open(os.path.join(DB2, "WorldMapOverlay.csv"), encoding="utf-8")) if r["UiMapArtID"] in art_of}
fids = sorted({int(r["FileDataID"]) for r in csv.DictReader(open(os.path.join(DB2, "WorldMapOverlayTile.csv"), encoding="utf-8"))
               if r["WorldMapOverlayID"] in overlays and r["LayerIndex"] == "0"})
dest = os.path.join(ADDONS, "MeridianOverlayFiles")
os.makedirs(dest, exist_ok=True)
have = []
for fid in fids:
    src = os.path.join(CACHE, "%d.blp" % fid)
    if os.path.exists(src) and os.path.getsize(src) > 50:
        shutil.copyfile(src, os.path.join(dest, "%d.blp" % fid))
        have.append(fid)
open(os.path.join(dest, "MeridianOverlayFiles.toc"), "w").write(
    "## Interface: 16001\n## Title: Meridian overlay files (local)\n## Notes: Zone overlay textures for Meridian's Reveal map. Local use only.\n"
    "## DefaultState: enabled\n\nMeridianOverlayFiles.lua\n")
open(os.path.join(dest, "MeridianOverlayFiles.lua"), "w").write("-- textures only\n")
with open("Meridian/OverlayPackIDs.lua", "w") as f:
    f.write("-- IDs of the overlay textures in the optional local MeridianOverlayFiles addon (tools/install_overlay_pack.py).\n")
    f.write("local ADDON, M = ...\nM.OverlayPackIDs = {\n")
    for fid in have:
        f.write("    [%d] = true,\n" % fid)
    f.write("}\n")
print(len(have), "of", len(fids), "textures installed to", dest)
