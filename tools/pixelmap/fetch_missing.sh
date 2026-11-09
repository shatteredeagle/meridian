#!/bin/sh
# Fills files the local CASC storage lacks (streamed-on-demand installs) from wago.tools' mirror of Blizzard's CDN,
# pinned to the same build. usage: fetch_missing.sh EXTRACT_LOG OUT_DIR BUILD
LOG="$1"; OUT="$2"; BUILD="$3"
grep "not available" "$LOG" | cut -d: -f1 | while read -r fid; do
  [ -s "$OUT/$fid.blp" ] && continue
  curl -sf -o "$OUT/$fid.blp" "https://wago.tools/api/casc/$fid?download&version=$BUILD" || echo "failed $fid"
done
