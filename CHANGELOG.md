# Changelog

Unreleased (all items untested in-client unless noted; see docs/test-checklist.md).

- Punchlist 1: Waypoints and /way. Ctrl-click the map to drop one; /way x y [title], /way Zone x y, /way #mapID x y, /way list, /way clear (also /mm way ...). Pins on the map and minimap (right-click removes, left-click points the arrow), arrow auto-targets the newest and clears on arrival, newest is mirrored to Blizzard's user waypoint and super-track. TomTom installed: /way is left to it and waypoints are forwarded to it. New teardrop/!/?/arrowhead/star/diamond pin art (tools/gen_icons.py).

- Punchlist 2: Turn-in markers. Green "?" pin (own silhouette, not just colour) at the finisher NPC/object of every completed log quest, from QuestieDB finishedBy (guarded if the DB lacks it). The arrow now points completed quests at their hand-in. /mm turnins toggles.

- Punchlist 3: Key bindings (Bindings.xml, header Meridian): toggle map, minimap, arrow, quest list, center on player. New UI:CenterOnPlayer shared with the Find me button.

- Punchlist 4: Options page (Options.lua): opacity, marker size, reveal default, quest area/giver/turn-in toggles, grey range, arrow on/style/arrival distance, Blizzard waypoint mirror, /way claim, minimap on/size/zoom/shape. Registers via Settings.RegisterCanvasLayoutCategory if present, else InterfaceOptions_AddCategory, else opens its own window. Reachable from the new gear toolbar icon and /mm config. Settings apply live (UI:ApplySettings); arrow has a classic and a bold style. Other modules extend the page with Options.Add.

- Punchlist 5: Window scale (0.7-1.5, centre stays put), window opacity and a lock toggle (window, minimap and arrow positions; hides the resize grip) on the options page, plus Reset window. Quest list visibility was already saved (db.tracker).

- Punchlist 6: Launcher button on Blizzard's minimap (left-click toggles the map, right-click opens options, drag moves it around the edge; can be turned off in options). Meridian's own minimap now shows a fixed N marker and your coordinates.

- Punchlist 7: Super-track integration. Shift-click in the quest list also calls C_SuperTrack.SetSuperTrackedQuestID so Blizzard's arrow matches (option; clears with the arrow target). Ctrl-click focuses a quest: other quest areas and quest markers fade (Questie-style); the focused row is marked with >.

- Punchlist 8: Quest list upgrades. Sort button cycles zone / level / distance (on the current map) / log order; zone mode groups by the log's zone headers with collapsible headers (remembered); rows show level and either done or objective progress as text (not colour alone); mouse-wheel scrolls; tooltips add level, zone and which party members are on the quest (C_QuestLog.IsUnitOnQuest; the API gives membership, not their objective counts).

- Punchlist 9: Coordinate readouts. Main map: cursor coordinates (bottom-left) plus a new "You: x, y" readout (bottom-centre); minimap already shows yours. Click any readout to open a pre-selected box with "/way Zone x y" for Ctrl-C (WoW has no clipboard API); Shift-click puts it in the chat input instead.

- Punchlist 10: Tooltip detail modifiers (Tooltips.lua). Hover shows a short tooltip; holding Shift (redraws live when pressed) adds XP/money/item rewards for logged quests (GetQuestLogReward*) and prerequisites, mutually exclusive quests and the next quest in the chain (QuestieDB, guarded). Giver tooltips now name the NPC/object and its level range.

- Punchlist 11: Accessibility pass. Every marker type already has its own silhouette (teardrop, !, ?, arrowhead, star, diamond, square) with a black outline; new: colour-blind-safe palette (Okabe-Ito) for quest areas and markers, text size option (own Font objects), high-contrast mode (outlined text, opaque panels, white borders, brighter icons), and toggle buttons now show a check mark and underline as well as colour.

- Punchlist 12: Controller support, minimal and OFF by default (Controller.lua; options checkbox or /mm pad). Uses Frame:EnableGamePadButton/Stick with OnGamePadButtonDown/OnGamePadStick: stick pans (dead zone, squared response), triggers zoom, shoulders cycle the quest list order and centre on each, PAD1 centres on you, PAD2 closes, PAD4 toggles the list; a hint line appears while enabled. Nothing is registered until enabled. Stick/button identifiers and focus acquisition are unverified; toolbar buttons are not controller-navigable (mouse-only), the toolbar has key bindings as a substitute.
