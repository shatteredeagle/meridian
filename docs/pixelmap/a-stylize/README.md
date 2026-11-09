# Method A: stylized Blizzard map art (not in git)

Made by `tools/pixelmap/build_a.sh`: Blizzard's own zone map tiles (base layer + every exploration overlay, read from the
local CASC storage with CascLib; 509 of 880 tiles were not stored locally and came from wago.tools' CDN mirror of the
same build) are stitched per Meridian's zone rects. Each pixel takes the art of the zone that owns that ground, blended softly
across zone seams; ground a map shows but does not own comes from the map whose own ground is nearest. Each layer's
parchment frame and its painted labels/banners (auto-detected plus boxes in `tools/pixelmap/a_labels.json`) are cut
out and clone-stamped from nearby clean art; larger gaps get a colour fill shaded by the terrain hillshade. Then
median filter, box downscale to the art grid, Bayer 4x4 ordered dither into a 44-colour palette
(`tools/pixelmap/palettes/a-stylize.gpl`, muted sea and river tones), terrain-data water (rectangular liquid tables
under WMOs dropped) with a navy sea coast and brown river banks, roads as thin lines one tone lighter than the ground,
and Aseprite despeckle/export (`a_finish.lua`).

Everything in this folder except this README is git-ignored: it is a derivative of Blizzard's copyrighted map art.
Rebuild it locally with `tools/pixelmap/build_all.sh <work dir>` (or `build_a.sh` once the inputs exist).
