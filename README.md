# Meridian

Carbonite-style pan/zoom map for WoW Forever. Phase 2: custom map window + overlapping quest areas.

Install: copy or symlink `Meridian/` into `World of Warcraft/_retail_/Interface/AddOns/` (Forever's folder; check yours).
Use: `/meridian` (or `/mm`) toggles the window. Wheel zooms at cursor, drag pans, `+ - F @` buttons zoom / fit / go to player.

Test offline: `lua tests/math_test.lua`

## Status
- Done: canvas tiling, pan/zoom, resize, player centering, additive per-quest overlays from Blizzard POIs.
- Unverified in-client: tile layout, `GetQuestsOnMap` behaviour. No WoW install on Orion.
- Quest areas: read at runtime from the installed QuestieDB addon (nothing bundled, so no licensing issue). `/mm data` shows which source is active.
- Next: phase 3 (minimap, tracker).
