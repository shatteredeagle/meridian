#!/bin/sh
# Fetches the map DB2 tables for the installed Forever build as CSV from wago.tools (they mirror Blizzard's CDN).
# usage: fetch_db2.sh OUT_DIR [BUILD]   (BUILD defaults to the Version in the install's .build.info)
OUT="$1"; BUILD="$2"
WOW="${WOW_ROOT:-$HOME/Faugus/battlenet/drive_c/Program Files (x86)/World of Warcraft}"
[ -z "$BUILD" ] && BUILD=$(awk -F'|' 'NR==2{print $15}' "$WOW/.build.info")
mkdir -p "$OUT"
for t in Map UiMap UiMapAssignment UiMapArt UiMapArtTile UiMapXMapArt UiMapArtStyleLayer WorldMapOverlay WorldMapOverlayTile AreaTable AreaPOI TaxiNodes; do
  curl -sf -o "$OUT/$t.csv" "https://wago.tools/db2/$t/csv?build=$BUILD" || echo "failed: $t"
done
echo "build $BUILD -> $OUT"
