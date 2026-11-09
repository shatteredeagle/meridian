#!/bin/sh
# Everything: inputs, the three methods, the comparison sheet. Run from the repo root.
# usage: tools/pixelmap/build_all.sh WORK_DIR
set -e
T=tools/pixelmap
$T/build_data.sh "$1"
$T/build_b.sh "$1" b
$T/build_b.sh "$1" c
$T/build_a.sh "$1"
python3 -I $T/previews.py compare docs/pixelmap/layout.json docs/pixelmap/compare.png \
  "A stylize Blizzard art=docs/pixelmap/a-stylize" "B procedural from data=docs/pixelmap/b-scratch" \
  "C B + landmarks=docs/pixelmap/c-hybrid"
