# Meridian punchlist (ranked; 1-5 are NEXT-UP)

Sizes: S under half a day, M ~1 day, L multi-day.

1. [DONE] **NEXT-UP: Waypoints + `/way` (TomTom-compatible)**. Ctrl-click map sets a waypoint; `/way x y`, `/way Zone x y`, `/way clear`; waypoint drawn on map and minimap, arrow can target it. Why: every Carbonite/TomTom/Questie user expects it; biggest functional gap. Size M. API: `C_Map.SetUserWaypoint`/`CanSetUserWaypointOnMap`, `C_SuperTrack.SetSuperTrackedUserWaypoint`; keep own list for multiple points. Respect an existing TomTom if loaded.
2. [DONE] **NEXT-UP: Turn-in markers ("?")**. Yellow "!" exists, add "?" for completed quests at the turn-in NPC, in a distinct colour/shape (not colour alone). Why: closes the quest loop; Questie's core. Size M. API: `C_QuestLog.IsComplete`, Questie DB finisher data (same source as givers).
3. [DONE] **NEXT-UP: Keybindings**. Bindings.xml: toggle map, toggle minimap, toggle arrow, centre on player, with `BINDING_HEADER_MERIDIAN`. Why: a map you open constantly needs a key; currently slash only. Size S.
4. [DONE] **NEXT-UP: Settings panel**. One options page (Settings API if present, else InterfaceOptions fallback) for opacity, window scale, icon size, minimap size/shape, grey range, arrow style, reveal default; also reachable from a gear icon and `/mm config`. Why: slash toggles like `/mm round` needing /reload are hidden and unfriendly. Size M. API: verify `Settings.*` exists on Forever.
5. [DONE] **NEXT-UP: Window scale + overall alpha + lock**. Scale slider, window opacity, lock-position toggle, remember tracker panel visibility. Why: Mapster's most-used options; essential for high-DPI and small screens. Size S. API: `SetScale`, `SetAlpha`; fix position anchor after scale.
6. [DONE] **Minimap launcher button + minimap tracking**: draggable button on Blizzard minimap (left-click map, right-click config) and a compass/coords text on Meridian's minimap. Size S.
7. [DONE] **Super-track integration**: shift-click in the quest list also calls `C_SuperTrack.SetSuperTrackedQuestID`, so Blizzard's on-screen arrow agrees; "focus quest" fades other overlays (Questie). Size S.
8. **Quest list upgrades**: sort by zone/level/distance, collapse by zone, show completed state and objective progress inline, party members' progress in tooltips. Size M. API: `C_QuestLog.GetNumQuestLogEntries`, `GetQuestObjectives`; party via `C_QuestLog.IsUnitOnQuest`.
9. **Cursor/player coordinates readout** on map and minimap (Mapster-style), click to copy as `/way`. Size S. API: `C_Map.GetPlayerMapPosition`.
10. **Tooltip detail modifiers**: Shift for XP/rewards/prereqs, giver tooltip shows NPC name, level, quest chain. Size S-M.
11. **Accessibility pass**: distinct shapes per marker type, optional colour-blind palette, font size option, high-contrast outlines, don't rely on colour for toggle state (add check/underline). Size M.
12. **Controller support**: gamepad stick pan, triggers zoom, face buttons to cycle quests; needs focus handling for toolbar. Size L. API: gamepad query functions not found in MCP search; verify in client with wow-controller-support skill.
13. **Search/journey**: find a zone, NPC or quest by name and jump to it; "available quests in this zone" list. Size M.
14. **Other pin sources (HandyNotes-style)**: flight paths, rares, vignettes, POIs with per-type toggles. Size L. API: `C_TaxiMap`, `C_Vignette`, `C_AreaPoiInfo`.
15. **Localization + in-client verification of untested items** (quest list, minimap, drill-down, givers, arrow per README): add locale table scaffolding and a test checklist. Size M.
