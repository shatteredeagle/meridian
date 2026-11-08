# Meridian

Carbonite-style pan/zoom map for WoW Forever: custom map window, overlapping quest areas, waypoints, quest list and minimap. Kept modular so unused features cost nothing (extra pins and controller support are off by default).

Install: copy or symlink `Meridian/` into `World of Warcraft/_retail_/Interface/AddOns/` (Forever's folder; check yours).
Reveal: `R` button or `/mm reveal` toggles fully revealed vs. your explored areas.
Use: `/meridian` (or `/mm`) toggles the window. Wheel zooms at cursor, drag pans, `+ - F @` buttons zoom / fit / go to player.

Test offline: `lua tests/math_test.lua`

## Controls
Icon toolbar (hover any icon for what it does; toggles glow gold when on): zoom in/out/fit | continent, zone, find me | reveal map, quest areas, quest givers, direction arrow | quest list, minimap.
Double-click a zone on the continent view to drill into it. Hold Shift over any quest tooltip for rewards, prerequisites and chain; giver tooltips name the NPC. Hover quest areas for names (every overlapping quest is listed). Quest list: the sort button cycles zone / level / distance / log order; zone headers collapse; each row shows level and objective progress (or "done"); wheel scrolls; party members on a quest are named in its tooltip. Checkbox hides that quest's overlay, click centers on it, hover highlights it and shows objectives. The slider sets overlay opacity.
Minimap button: sits on Blizzard's minimap; left-click map, right-click options, drag to move. Meridian minimap: `/mm mini`, shows N and your coordinates. Follows you; drag to pan (stops following), the locate icon re-follows, top strip moves the frame.

Coordinates: bottom of the map shows the cursor's and your own; click one to copy it as a `/way` line (Ctrl-C from the box), Shift-click to drop it in chat.
Waypoints: Ctrl-click the map (zone view, or any zone on the continent). `/way x y [title]`, `/way Zone x y`, `/way #mapID x y`, `/way list`, `/way clear` (same as `/mm way ...`; if TomTom is installed it keeps `/way` and also receives ours). Pin: left-click points the arrow, right-click removes. The arrow follows the newest waypoint until you arrive (10 yds).

Keys (Options > Keybindings > Meridian, unbound by default): toggle map, minimap, direction arrow, quest list, center on player.

Window: scale, opacity and a position lock live on the options page (the quest list's shown/hidden state is remembered).
Accessibility (options page): colour-blind-safe palette, text size, high contrast. Marker types differ by shape, and toggles show a check mark as well as colour.
Controller (experimental, off; options page or `/mm pad`): stick pans, triggers zoom, shoulder buttons cycle quests, PAD1 centres on you, PAD2 closes, PAD4 toggles the list. Toolbar buttons are not controller-navigable; use key bindings.
Dungeon maps (options page, on by default; toolbar doorway icon or `/mm dungeons`): a castle-gate marker sits on each zone or continent map where a dungeon entrance is known. Click it to open that dungeon's map (click again for the next dungeon when several share an entrance, e.g. the Scarlet Monastery wings). Inside, the bar at the top-left of the map shows the dungeon, a Back button and one button per floor (the current floor is bracketed). Quest areas, givers and turn-ins use the same data as zones; with ForeverDungeonJournal installed, hand-in and pick-up NPCs inside the dungeon get "?" and "!" markers for your logged and available dungeon quests. Your position shows when the client reports one for that floor; the "Find me" and zone buttons open the instance you are standing in. Dungeons are found by the search box too ([Dungeon] rows).
Search: box at the right of the toolbar (or `/mm find text`) finds zones, quests (log and QuestieDB) and nearby quest-giver NPCs and jumps there; the list icon beside it (or `/mm here`) shows the quests you can accept in this zone.
Extra pins (options page, all off): flight paths (remembered when you open a flight master map; continent view), rares/treasures nearby, points of interest.
Options: gear icon or `/mm config` (Settings panel when the client has one, else Interface Options, else a window of its own).

Slash: `/mm` toggle, `/mm dungeons`, `/mm config`, `/mm way ...`, `/mm turnins`, `/mm mini`, `/mm arrow`, `/mm givers`, `/mm reveal`, `/mm round` (minimap shape, needs /reload), `/mm data`, `/mm reset`.
Arrow: points to the nearest quest area on your continent; shift-click a quest in the list to target it (again to clear; Blizzard's super-tracked quest follows). Ctrl-click focuses a quest and fades the rest. Drag it to move.
Turn-ins: green "?" markers at the hand-in for each completed quest (`/mm turnins` toggles); the arrow then points there.
Givers: yellow "!" markers for quests you could accept (level, race, class, prerequisites checked). First use indexes QuestieDB in the background.

## Status
- Tested in-client by the user: stitched continent, QuestieDB areas, reveal toggle.
- Icons and pins are generated by `python3 tools/gen_icons.py` (white glyph TGAs, tinted in-game). Locale keys: `python3 tools/extract_strings.py`.
- Everything else is written but **untested in-client**. Walk through `docs/test-checklist.md`. Highest risk: options page (`Settings.*` names unverified, falls back to Interface Options or its own window), controller support (stick and button identifiers are guesses; off by default), extra pins (taxi/vignette/POI field names unverified; off by default), QuestieDB lookups added for finishers, NPC names and chains (guarded, features just go quiet if absent), TomTom forwarding, copy box, Blizzard minimap button.
- Offline tests (`lua tests/math_test.lua`) cover geometry, zoom/pan math, axes, bearing, quest eligibility, `/way` parsing, quest list sort/grouping, tooltip text, palettes, controller math, search ranking, pin helpers and locale consistency.
- Localization: strings go through `L["..."]` (English text is the key; `Locales/enUS.lua` lists them, `Locales/deDE.lua` is a small unreviewed starter). Chat messages and some tooltips are not translated yet.
- Dungeon maps (Dungeons.lua) are written but **untested in-client**: C_Map dungeon scan, `C_EncounterJournal.GetDungeonEntrancesForMap`, map group floor order and custom floor art are unverified; see the Dungeon maps section of `docs/test-checklist.md`. Pure parts (name matching, floor grouping, tile layout, entrance grouping, quest matching) are in the offline tests.
- Not done: reputation/skill prerequisite checks for givers, per-quest colour picker, NPC search beyond the givers on visible maps, translated chat messages.
