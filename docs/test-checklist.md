# Meridian in-client test checklist

Nothing below has been run in WoW; the code was written without a client. Work top to bottom, note failures with the Lua error text (turn on `/console scriptErrors 1`). Install per README, `/reload`, then:

## 0. Load
- [ ] No Lua errors on login. `/mm` opens the window; `/mm data` reports QuestieDB / Zygor status.
- [ ] Escape closes the window. Position and size are remembered after `/reload`.

## 1. Waypoints and /way
- [ ] Ctrl-click a zone (zone view): teardrop pin appears, chat says "Waypoint set". Same on the continent view.
- [ ] `/way 52.3 41.2`, `/way Elwynn Forest 40 60 test`, `/way #<mapID> 10 10`, `/way list`, `/way clear` all behave.
- [ ] Arrow turns on, points at the waypoint, and the waypoint disappears within 10 yds ("Arrived").
- [ ] Pin: left-click re-targets, right-click removes. Minimap (`/mm mini`) shows the pin too.
- [ ] Blizzard's own waypoint/super-track marker appears (options: "Also set Blizzard's waypoint"). If it errors, report which call.
- [ ] With TomTom installed: `/way` still belongs to TomTom, and Ctrl-click also creates a TomTom waypoint (check TomTom:AddWaypoint takes 0..1 coords).
- [ ] Waypoints survive `/reload`.

## 2. Turn-in markers
- [ ] Complete a quest: green "?" appears at the hand-in NPC (needs QuestieDB `Quest.finishedBy`). Arrow points there.
- [ ] `/mm turnins` toggles. Tooltip says "Ready to turn in".

## 3. Key bindings
- [ ] Esc > Options > Keybindings > Meridian lists 5 entries; each works.

## 4. Options page
- [ ] Gear icon and `/mm config` open the page (Settings panel, Interface Options, or standalone window; report which).
- [ ] Every control changes the thing it names, live (opacity, marker size, reveal, minimap size/zoom, arrow style, grey range).
- [ ] Round minimap and "Handle /way" say they need /reload.

## 5. Scale, opacity, lock
- [ ] Window scale slider keeps the window centred; position survives `/reload` at a non-1 scale.
- [ ] Opacity works; lock stops dragging window, minimap and arrow and hides the resize grip. Reset window works.

## 6. Minimap button and minimap text
- [ ] Button on Blizzard's minimap: left toggles map, right opens options, drag moves it around the edge and it stays put after reload. Check with a square minimap addon (ElvUI) too.
- [ ] Meridian minimap shows N and your coordinates; clicking them opens the copy box.

## 7. Super-track and focus
- [ ] Shift-click a quest row: our arrow and Blizzard's super-tracked quest agree; again clears both.
- [ ] Ctrl-click a row: other quest areas and markers fade; row starts with ">".

## 8. Quest list
- [ ] Sort button cycles zone / level / distance / log. Zone headers collapse and stay collapsed after reload.
- [ ] Rows show level and "1/3" or "- done". Wheel scrolls with many quests. Font-size option does not break row layout.
- [ ] In a party: tooltip names members on the same quest.

## 9. Coordinates
- [ ] Bottom of the map shows cursor and "You:" coordinates. Click opens a box with `/way Zone x y` already selected; Ctrl-C then Enter works. Shift-click puts it in chat.

## 10. Tooltips
- [ ] Hover quest area, giver, turn-in and list row: Shift adds rewards (logged quests) and prerequisites; pressing/releasing Shift updates a visible tooltip.
- [ ] Giver tooltip shows NPC name and level (depends on QuestieDB `Npc.name/minLevel/maxLevel`; blank is acceptable, an error is not).

## 11. Accessibility
- [ ] Colour-blind palette recolours areas and markers. Text size slider rescales text and list rows. High contrast gives white borders and outlined text.
- [ ] Toggle buttons show a check mark and underline when on.

## 12. Controller (off by default; needs a gamepad)
- [ ] Enable in options or `/mm pad`. With the map open: left stick pans, triggers zoom, shoulders cycle quests, PAD1 centres, PAD2 closes, PAD4 toggles the list. Report the stick names and which button names actually fire (add a print in `Controller.lua` OnGamePadStick/Button).
- [ ] Disabling restores normal behaviour (no stuck input).

## 13. Search
- [ ] Type 2+ letters: zones, logged quests, then DB quests (first search says "Indexing quests for search..."). Enter or click jumps and drops a diamond marker; right-click clears.
- [ ] Search with QuestieDB missing still finds zones and log quests.
- [ ] List icon / `/mm here` lists available quests for the current zone.

## 14. Extra pins (each off by default)
- [ ] Flight paths: open a flight master map once, enable the option, continent view shows arrowheads.
- [ ] Rares: star near a known rare/treasure in your current zone.
- [ ] Points of interest: diamonds in zones that have area POIs.
- [ ] Turning all three off stops the events (no performance cost).

## 15. Localization
- [ ] On a German client, a few toolbar tooltips and key binding names switch to German; everything else stays English.

## 16. Dungeon maps (Dungeons.lua)
- [ ] Login with no Lua errors, with and without ForeverDungeonJournal loaded. `/mm dungeons` toggles (chat says on/off); doorway toolbar icon glows gold with a check mark when on; Options has the "Dungeon maps" checkbox.
- [ ] Continent view and a zone with a known dungeon (Dun Morogh/Gnomeregan, Barrens/Razorfen, Deadmines in Westfall): castle-gate markers at the entrances, tooltip names the dungeon. Markers are not on the minimap.
- [ ] Click a marker: the canvas switches to the dungeon map (art drawn, not blank). Check one with client art and one that uses the journal's own art (Hall of Thanes, Ruins of Lordaeron, Dalaran Underbelly).
- [ ] Multi-floor dungeon (Gnomeregan, Blackrock Depths, Scarlet Monastery): floor buttons 1..n appear, the current one is bracketed and disabled, switching changes the art. Hover shows the floor label. Report floor order wrong or reversed (map group `relativeHeightIndex` is unverified).
- [ ] Back returns to the zone/continent you came from; with no previous map it goes to the entrance zone. Scarlet Monastery: clicking the shared entrance cycles Library, Armory, Cathedral, Graveyard.
- [ ] Search "gnom", "dead", "scarlet": `[Dungeon]` rows; click opens the dungeon. With the option off, no dungeon rows.
- [ ] Standing inside an instance: `Find me` or the zone icon opens that floor; the player arrow shows (report if the client returns no position or a different map ID than the journal's `uiMapID`).
- [ ] Inside a dungeon view: entrance portal marker (journal data), quest areas for logged dungeon quests (QuestieDB or Blizzard POIs), "?" at the hand-in NPC after completing a dungeon quest, "!" at the NPC for an available one. Ctrl-click prints "Waypoints need a real map" on a custom-art floor.
- [ ] Reveal toggle, resize and `/reload` keep the dungeon view sane (reload returns to the usual map). Options > Dungeon maps off hides markers and the floor bar.
- [ ] Report: which C_Map scan results looked wrong (extra/missing dungeons, duplicates of journal ones), and whether `C_EncounterJournal.GetDungeonEntrancesForMap` returned positions.

## Previously untested (from README)
- [ ] Quest list, minimap, drill-down (double-click a zone), quest givers, direction arrow, saved positions.
