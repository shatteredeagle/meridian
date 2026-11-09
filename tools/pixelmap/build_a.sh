#!/bin/sh
# Method A build. Needs WORK_DIR from build_data.sh plus WORK_DIR/blizz_art (extracted zone map tiles) and
# WORK_DIR/bdata (prep_b.py). Output stays out of git (docs/pixelmap/a-stylize is ignored except README.md).
set -e
WORK="$1"
ASE="${ASEPRITE:-$HOME/.local/share/Steam/steamapps/common/Aseprite/aseprite}"
DIR=docs/pixelmap/a-stylize
PAL="$PWD/tools/pixelmap/palettes/a-stylize.gpl"
WOW="${WOW_ROOT:-$HOME/Faugus/battlenet/drive_c/Program Files (x86)/World of Warcraft}"
python3 -I tools/pixelmap/prep_b.py docs/pixelmap/layout.json "$WORK/terrain.npz" "$WORK/feat" "$WORK/db2" \
  "$WOW/_forever_/Interface/AddOns/ForeverDungeonJournal/Data/DungeonEntrances.lua" "$WORK/bdata"
python3 -I tools/pixelmap/a_source.py docs/pixelmap/layout.json "$WORK/blizz_art" "$WORK/db2" "$WORK/terrain.npz" \
  "$WORK/a_source.png" "$WORK/bdata/b_land.png" tools/pixelmap/a_labels.json
python3 -I tools/pixelmap/a_stylize.py docs/pixelmap/layout.json "$WORK/a_source.png" "$WORK/bdata" "$PAL" "$WORK/a_styl.png"
mkdir -p "$DIR"
"$ASE" -b --script-param src="$WORK/a_styl.png" --script-param pal="$PAL" --script-param out="$PWD/$DIR" \
  --script-param name=a-stylize --script "$PWD/tools/pixelmap/a_finish.lua"
python3 -I tools/pixelmap/previews.py crops docs/pixelmap/layout.json "$DIR/full.png" "$DIR"
