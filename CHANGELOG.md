# Changelog

Unreleased (all items untested in-client unless noted; see docs/test-checklist.md).

- Punchlist 1: Waypoints and /way. Ctrl-click the map to drop one; /way x y [title], /way Zone x y, /way #mapID x y, /way list, /way clear (also /mm way ...). Pins on the map and minimap (right-click removes, left-click points the arrow), arrow auto-targets the newest and clears on arrival, newest is mirrored to Blizzard's user waypoint and super-track. TomTom installed: /way is left to it and waypoints are forwarded to it. New teardrop/!/?/arrowhead/star/diamond pin art (tools/gen_icons.py).

- Punchlist 2: Turn-in markers. Green "?" pin (own silhouette, not just colour) at the finisher NPC/object of every completed log quest, from QuestieDB finishedBy (guarded if the DB lacks it). The arrow now points completed quests at their hand-in. /mm turnins toggles.
