#!/bin/sh
# Inputs for all three methods, into WORK_DIR (outside git). Run from the repo root.
# usage: tools/pixelmap/build_data.sh WORK_DIR
# Needs: python3 with numpy/scipy/PIL, git, cmake, a C++ compiler, curl, a local Forever install (WOW_ROOT).
# Fetches: CascLib source (github.com/ladislav-zezula/CascLib, MIT) built in WORK_DIR/casclib-src;
#          DB2 CSVs for the installed build from wago.tools; the wowdev community listfile (file names only);
#          zone map tiles the local storage lacks, from wago.tools' CDN mirror pinned to the same build.
set -e
WORK="$1"; mkdir -p "$WORK"
WOW="${WOW_ROOT:-$HOME/Faugus/battlenet/drive_c/Program Files (x86)/World of Warcraft}"
BUILD=$(awk -F'|' 'NR==2{print $15}' "$WOW/.build.info")
T=tools/pixelmap
LIB="$WORK/casclib-src/CascLib/build/libcasc.so"
if [ ! -f "$LIB" ]; then
  mkdir -p "$WORK/casclib-src"
  git clone --depth 1 -q https://github.com/ladislav-zezula/CascLib.git "$WORK/casclib-src/CascLib"
  cmake -S "$WORK/casclib-src/CascLib" -B "$WORK/casclib-src/CascLib/build" -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
    -DCASC_BUILD_SHARED_LIB=ON -DCASC_BUILD_STATIC_LIB=OFF -DCMAKE_BUILD_TYPE=Release >/dev/null
  make -C "$WORK/casclib-src/CascLib/build" -j"$(nproc)" >/dev/null
fi
[ -f "$WORK/db2/UiMap.csv" ] || $T/fetch_db2.sh "$WORK/db2" "$BUILD"
[ -f "$WORK/db2/LiquidType.csv" ] || curl -sf -o "$WORK/db2/LiquidType.csv" "https://wago.tools/db2/LiquidType/csv?build=$BUILD"
python3 -I $T/layout.py "$WORK/db2" docs/pixelmap/layout.json
# terrain data: azeroth.wdt -> root/obj0/tex0 ADTs
python3 -I $T/casc_extract.py "$LIB" "$WOW" wowf "$WORK/wdt" 775971
mkdir -p "$WORK/adt"
python3 -I $T/terrain.py fdids "$WORK/wdt/775971.blp" "$WORK/adt/index.txt"
awk '{print $1"\n"$4"\n"$5}' "$WORK/adt/index.txt" > "$WORK/adt_fdids.txt"
python3 -I $T/casc_extract.py "$LIB" "$WOW" wowf "$WORK/adt" "@$WORK/adt_fdids.txt" > "$WORK/extract_adt.log"
tail -1 "$WORK/extract_adt.log"
python3 -I $T/terrain.py grid docs/pixelmap/layout.json "$WORK/adt" "$WORK/db2" "$WORK/terrain.npz"
[ -f "$WORK/listfile/community-listfile.csv" ] || { mkdir -p "$WORK/listfile"; curl -sfL -o "$WORK/listfile/community-listfile.csv" \
  https://github.com/wowdev/wow-listfile/releases/latest/download/community-listfile.csv; }
python3 -I $T/features.py docs/pixelmap/layout.json "$WORK/adt" "$WORK/listfile/community-listfile.csv" "$WORK/feat"
# Method A source art: every zone tile + exploration overlay tile + the continent map
python3 -I - "$WORK" <<'PY'
import csv, json, sys
w = sys.argv[1]
d = json.load(open("docs/pixelmap/layout.json"))
ids = set()
for z in d["zones"]:
    ids |= {t[2] for t in z["art"]["tiles"]}
    for o in z["art"]["overlays"]:
        ids |= {t[2] for t in o["tiles"]}
for r in csv.DictReader(open(f"{w}/db2/UiMapArtTile.csv")):
    if r["UiMapArtID"] == "2140" and r["LayerIndex"] == "0":
        ids.add(int(r["FileDataID"]))
open(f"{w}/fdids_a.txt", "w").write("\n".join(map(str, sorted(ids))))
PY
python3 -I $T/casc_extract.py "$LIB" "$WOW" wowf "$WORK/blizz_art" "@$WORK/fdids_a.txt" > "$WORK/extract_a.log"
tail -1 "$WORK/extract_a.log"
$T/fetch_missing.sh "$WORK/extract_a.log" "$WORK/blizz_art" "$BUILD"
