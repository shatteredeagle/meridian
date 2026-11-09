#!/bin/sh
# Method B/C build: data layers (Python) -> Aseprite composition -> previews. Run from the repo root.
# usage: tools/pixelmap/build_b.sh WORK_DIR [b|c]
#   WORK_DIR holds layout inputs made by tools/pixelmap/build_data.sh (db2/, terrain.npz, feat/).
set -e
WORK="$1"; MODE="${2:-b}"
ASE="${ASEPRITE:-$HOME/.local/share/Steam/steamapps/common/Aseprite/aseprite}"
WOW="${WOW_ROOT:-$HOME/Faugus/battlenet/drive_c/Program Files (x86)/World of Warcraft}"
ENT="$WOW/_forever_/Interface/AddOns/ForeverDungeonJournal/Data/DungeonEntrances.lua"
case "$MODE" in b) DIR=docs/pixelmap/b-scratch; NAME=b-scratch ;; c) DIR=docs/pixelmap/c-hybrid; NAME=c-hybrid ;; esac
python3 -I tools/pixelmap/prep_b.py docs/pixelmap/layout.json "$WORK/terrain.npz" "$WORK/feat" "$WORK/db2" "$ENT" "$WORK/bdata"
mkdir -p "$DIR"
"$ASE" -b --script-param data="$WORK/bdata" --script-param pal="$PWD/tools/pixelmap/palettes/b-terrain.gpl" \
  --script-param out="$PWD/$DIR" --script-param name="$NAME" --script-param mode="$MODE" \
  --script "$PWD/tools/pixelmap/b_render.lua"
python3 -I tools/pixelmap/previews.py crops docs/pixelmap/layout.json "$DIR/full.png" "$DIR"
