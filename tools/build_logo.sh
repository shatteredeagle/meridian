#!/bin/sh
# Rebuilds docs/logo/ from tools/gen_logo.lua with Aseprite (Steam install). Run from the repo root.
ASE="${ASEPRITE:-$HOME/.local/share/Steam/steamapps/common/Aseprite/aseprite}"
"$ASE" -b --script tools/gen_logo.lua
"$ASE" -b docs/logo/logo.aseprite --scale 8 --save-as docs/logo/logo-400.png
"$ASE" -b docs/logo/logo.aseprite --scale 16 --save-as docs/logo/logo-800.png
