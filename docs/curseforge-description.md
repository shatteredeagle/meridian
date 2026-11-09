# Meridian

**A Carbonite-style world map for WoW Forever.** Pan and zoom one seamless continent, see every quest area at once, and never lose track of where your quests are.

> **Alpha.** Meridian is new and still being tested in the client. Expect rough edges, and please report bugs (with the BugSack error if there is one).

## Why Meridian

Blizzard's map shows one quest at a time. Meridian shows all of them, overlapping, on a map you can actually move around: scroll to zoom at the cursor, drag to pan, double-click a zone to drill into it.

## Features

**The map**
- One continuous, stitched continent view with feathered zone edges, instead of a pile of separate zone pages.
- Zone drill-down, a "find me" button, and a fully revealed or explored-only map (fully revealed uses Zygor's map data when it is installed).
- Window scale, opacity and position lock. The window position is remembered.

**Quests**
- Every active quest's area drawn on the map, overlapping, each in its own colour. Hover to see every quest under the cursor.
- Quest list panel: sort by zone, level or distance, collapse by zone, see progress inline, hide individual quests, hover to highlight, click to centre.
- Yellow "!" markers for quests you could pick up (level, race, class and prerequisites checked) and green "?" markers at the turn-in for quests you have completed.
- Shift for extra tooltip detail: rewards, prerequisites and quest chain.
- Focus mode (Ctrl-click a quest) fades everything else.

**Navigation**
- Waypoints: right-click the map to drop a pin and the arrow points the way (Ctrl-click works too), or `/way x y`, `/way Zone x y`. Works alongside TomTom and syncs with Blizzard's own waypoint.
- A direction arrow that points to the nearest quest area, a completed quest's hand-in, or your waypoint.
- A follow-me minimap (square or round) and a launcher button on Blizzard's minimap.
- Cursor and player coordinates; click to get a ready-to-use `/way` line.

**Dungeons**
- Dungeon entrances marked on zone and continent maps. Click one to open that dungeon's map, with floor switching. Uses ForeverDungeonJournal's art and data when it is installed.

**Search**
- Find zones, quests, quest givers and dungeons by name and jump straight to them. One click lists the quests available in your current zone.

**Comfort and accessibility**
- A colour-blind palette, a text size option, a high-contrast mode, and a distinct shape for every marker type (not colour alone).
- An options page, key bindings for everything, and an experimental controller mode (off by default).
- Optional extra pins for flight paths, rares and points of interest (off by default).

## Quick start

Type `/mm` (or `/meridian`) to open the map. Hover any toolbar icon to see what it does. Type `/mm config` for options.

| Command | What it does |
| --- | --- |
| `/mm` | Toggle the map |
| `/mm mini` | Toggle the minimap |
| `/mm arrow` | Toggle the direction arrow |
| `/mm givers` | Toggle quest-giver markers |
| `/mm dungeons` | Toggle dungeon entrances |
| `/mm reveal` | Fully revealed or explored-only |
| `/mm blend` | Blend zone edges on the continent map |
| `/way x y` | Set a waypoint |
| `/mm config` | Open options |

## Optional add-ons

Meridian runs on its own. Quest areas, givers and turn-ins use QuestieDB data when it is installed (Questie, or the standalone QuestieDB). Zygor Guides Viewer enables the fully revealed map, and ForeverDungeonJournal adds dungeon art and quest data. TomTom keeps `/way` if you use it.

## Known limits

- Alpha: much of it has not run in the live client yet.
- Controller support is minimal and may need tuning for your pad.
- Quest-giver checks do not cover reputation or skill requirements yet.
- Localization: English, plus machine-translated, unreviewed UI text for German, French, Spanish (Spain and Latin America), Italian, Portuguese (Brazil), Russian, Korean and Simplified and Traditional Chinese. Native-speaker corrections welcome; chat messages and some tooltips are still English.

## Feedback

Found a bug or have an idea? Open an issue on the project page and include your WoW build, other map or quest addons you run, and any BugSack error text.
