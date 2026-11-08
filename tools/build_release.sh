#!/bin/sh
# Builds dist/Meridian-<version>.zip containing only the Meridian/ addon folder. Run from the repo root.
set -e
VER=$(sed -n 's/^## Version: *//p' Meridian/Meridian.toc)
mkdir -p dist
rm -f "dist/Meridian-$VER.zip"
zip -qr "dist/Meridian-$VER.zip" Meridian -x '*.aseprite' '*~'
echo "dist/Meridian-$VER.zip"; unzip -l "dist/Meridian-$VER.zip" | tail -1
