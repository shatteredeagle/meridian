# Method B: procedural from data

Made by `tools/pixelmap/build_b.sh <work dir> b`: no Blizzard art pixels. Python (`terrain.py`, `features.py`,
`prep_b.py`) turns game *data* (ADT heights, liquids, area IDs, ground-texture names and blend weights, tree/building
placements) into per-pixel layers; the Aseprite script `b_render.lua` composes the map from them with the 48-colour
palette `tools/pixelmap/palettes/b-terrain.gpl`: biome ramps x hillshade with Bayer dithering, distance-banded water,
1 px coast outline, road lines, building footprints, tree sprites and dungeon gate markers.
