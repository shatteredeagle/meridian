# Method A: stylized Blizzard map art (not in git)

Made by `tools/pixelmap/build_a.sh`: Blizzard's own zone map tiles (base layer + every exploration overlay, read from the
local CASC storage with CascLib; 509 of 880 tiles were not stored locally and came from wago.tools' CDN mirror of the
same build) are stitched per Meridian's zone rects, each pixel taken from the zone that owns that ground, then
median-filtered, box-downscaled to the art grid, ordered-dithered (Bayer 4x4) into a 44-colour palette
(`tools/pixelmap/palettes/a-stylize.gpl`), given terrain-data water bands, a 1 px coast outline and data roads, and
despeckled/exported in Aseprite (`a_finish.lua`).

Everything in this folder except this README is git-ignored: it is a derivative of Blizzard's copyrighted map art.
Rebuild it locally with `tools/pixelmap/build_all.sh <work dir>` (or `build_a.sh` once the inputs exist).
