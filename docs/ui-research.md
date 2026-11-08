# Meridian UI research (2026-11-08)

Scope note: searches returned solid sources for Questie, Carbonite and TomTom only. Mapster, Magnify, Cartographer, HandyNotes, ElvUI and Blizzard behaviours below are from general addon knowledge and are NOT source-verified. API notes come from the wow-api MCP (Forever).

## Findings per addon
- **Questie** (https://github.com/Questie/Questie): separate icons for start, turn-in and objective; tooltips on map notes and on NPCs/objects in the world; Shift on an icon shows extra detail (XP); party members' progress in tooltips; tracker auto-adds accepted quests, can show all log quests, right-click menu with "focus" (other quest icons go translucent) and "point arrow" via TomTom; "My Journey" window with quests-by-zone and search; minimap button opens options; extensive options panel; translated into nine languages. No dedicated accessibility options.
- **Carbonite** (https://www.curseforge.com/wow/addons/carbonite , https://atk.github.io/Carbonite): Google-Maps-style movable/resizable/zoomable map, HUD with TomTom emulation, quest watch with group and personal views, integrations (HandyNotes, Questie, Zygor, RareScanner). Known downside: bloat and memory; the scaling layer is the cost. Lesson: keep modules optional and cheap.
- **TomTom** (https://www.curseforge.com/wow/addons/tomtom , https://wowpedia.fandom.com/wiki/TomTom): `/way x y`, `/way Zone x y`, click-map-to-set waypoint, Crazy Arrow with distance and ETA, closest-waypoint, back-waypoint, corpse waypoint, arrow themes, waypoints on map and minimap. De facto standard; addons that set waypoints are expected to speak `/way`.
- **Mapster / Magnify / Cartographer / HandyNotes / ElvUI (unverified)**: Mapster: map scale and alpha sliders, cursor and player coordinates, movable map. Magnify: wheel zoom on the world map. Cartographer: `/way`, notes. HandyNotes: per-plugin pin sets with a settings panel and per-icon scale/alpha. ElvUI minimap: square minimap, coordinates, zone text, a collected button bar. Blizzard: super-track a quest (arrow plus on-screen marker), right-click map to clear a waypoint, Ctrl-click to place a user waypoint.

## Forever API constraints (wow-api MCP)
- Waypoints: `C_Map.SetUserWaypoint(UiMapPoint)`, `C_Map.CanSetUserWaypointOnMap(uiMapID)`; `C_SuperTrack.SetSuperTrackedUserWaypoint`, `SetSuperTrackedQuestID`, `GetNextWaypointForMap`.
- Quests: `C_QuestLog.GetQuestsOnMap(uiMapID)` available. `C_Map.GetPlayerMapPosition(uiMapID, "player")` present.
- Not found by search (verify in client before relying): `Settings.RegisterAddOnCategory`, gamepad query functions, `GetQuestsCompleted`. Use `C_QuestLog.IsQuestFlaggedCompleted` for completion and fall back to InterfaceOptions if Settings is absent.
- Pixel/edge: Meridian is a custom frame, so Blizzard map events and POI pins are not free; everything Meridian shows it draws.

## Current Meridian state (code read)
Has: pan/zoom canvas, continent stitch and zone drill-down, reveal toggle, quest areas with overlap tooltips, yellow "!" givers, quest list with hide/centre/highlight, opacity slider, direction arrow, minimap, icon toolbar with toggle states, saved position/size, Escape closes.
Missing: any keybinding, settings panel, `/way` or waypoint support, turn-in markers, minimap launcher button, window scale/opacity, click-to-waypoint, super-track integration, controller/accessibility affordances, party quest info, search, localization, per-quest colour picker, reputation/skill checks.
