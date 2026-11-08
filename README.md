# Meridian

Carbonite-style pan/zoom map for WoW Forever. Phase 2: custom map window + overlapping quest areas.

Install: copy or symlink `Meridian/` into `World of Warcraft/_retail_/Interface/AddOns/` (Forever's folder; check yours).
Reveal: `R` button or `/mm reveal` toggles fully revealed vs. your explored areas.
Use: `/meridian` (or `/mm`) toggles the window. Wheel zooms at cursor, drag pans, `+ - F @` buttons zoom / fit / go to player.

Test offline: `lua tests/math_test.lua`

## Controls
Toolbar: `+ - F` zoom/fit, `@` continent centered on you, `Z` your zone only, `R` reveal mode, `Q` quest overlays on/off, `T` quest list, `M` minimap, `!` available-quest givers, `>` direction arrow.
Double-click a zone on the continent view to drill into it. Quest list: checkbox hides that quest's overlay, click centers on it, hover shows objectives.
Minimap: `/mm mini`. Follows you; drag to pan (stops following), `@` re-follows, top strip moves the frame.

Slash: `/mm` toggle, `/mm mini`, `/mm arrow`, `/mm givers`, `/mm reveal`, `/mm round` (minimap shape, needs /reload), `/mm data`, `/mm reset`.
Arrow: points to the nearest quest area on your continent; shift-click a quest in the list to target it (again to clear). Drag it to move.
Givers: yellow "!" markers for quests you could accept (level, race, class, prerequisites checked). First use indexes QuestieDB in the background.

## Status
- Tested in-client by the user: stitched continent, QuestieDB areas, reveal toggle.
- Written but untested in-client: quest list, minimap (round via mask texture), drill-down, givers, arrow, saved positions.
- Offline tests (`lua tests/math_test.lua`) cover geometry, zoom/pan math, axes, bearing, quest eligibility.
- Not done: reputation/skill prerequisite checks for givers, turn-in markers, per-quest colors picker, localization.
