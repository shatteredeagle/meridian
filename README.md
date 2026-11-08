# Meridian

Carbonite-style pan/zoom map for WoW Forever. Phase 2: custom map window + overlapping quest areas.

Install: copy or symlink `Meridian/` into `World of Warcraft/_retail_/Interface/AddOns/` (Forever's folder; check yours).
Reveal: `R` button or `/mm reveal` toggles fully revealed vs. your explored areas.
Use: `/meridian` (or `/mm`) toggles the window. Wheel zooms at cursor, drag pans, `+ - F @` buttons zoom / fit / go to player.

Test offline: `lua tests/math_test.lua`

## Controls
Toolbar: `+ - F` zoom/fit, `@` continent centered on you, `Z` your zone only, `R` reveal mode, `Q` quest overlays on/off, `T` quest list, `M` minimap.
Double-click a zone on the continent view to drill into it. Quest list: checkbox hides that quest's overlay, click centers on it, hover shows objectives.
Minimap: `/mm mini`. Follows you; drag to pan (stops following), `@` re-follows, top strip moves the frame.

## Status
- Phase 2 (map + overlays) tested in-client by the user: stitched continent, QuestieDB areas, reveal toggle.
- Phase 3 code written, untested in-client: quest list, minimap, double-click drill-down, saved window position.
- Quest areas are read at runtime from the installed QuestieDB addon (nothing bundled). `/mm data` shows the active source.
- Not done: available (not-yet-accepted) quests, round minimap mask, route/arrow to next objective.
