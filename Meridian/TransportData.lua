-- Boat and zeppelin docks: kind, route, world id (0 Eastern Kingdoms, 1 Kalimdor), world x, world y, faction (A / H / none).
-- Derived from OpenMap's transport table (c) 2026 OpenMap contributors, MIT licence, itself built from the game's tables;
-- see THIRD_PARTY.md. Regenerate rather than edit.
local ADDON, M = ...
M.TransportData = {
    { "boat", "Booty Bay - Ratchet", 1, -1005.6, -3841.6 },
    { "boat", "Booty Bay - Ratchet", 0, -14277.7, 582.9 },
    { "zeppelin", "Grom'gol - Orgrimmar", 0, -12464.0, 231.6, "H" },
    { "zeppelin", "Grom'gol - Orgrimmar", 1, 1360.9, -4631.3, "H" },
    { "boat", "Menethil Ships", 0, -3905.2, -585.8, "A" },
    { "boat", "Menethil Ships", 1, -4016.4, -4740.6, "A" },
    { "boat", "Rut'theran - Auberdine", 1, 8532.0, 1023.7, "A" },
    { "boat", "Rut'theran - Auberdine", 1, 6594.4, 759.8, "A" },
    { "boat", "Menethil Ships", 0, -3709.5, -575.1, "A" },
    { "boat", "Menethil Ships", 1, 6406.2, 823.1, "A" },
    { "zeppelin", "Orgrimmar Zepplins", 0, -12406.9, 211.8, "H" },
    { "zeppelin", "Orgrimmar Zepplins", 0, 2062.6, 235.3, "H" },
    { "zeppelin", "Orgrimmar Zepplins", 1, 1318.1, -4658.0, "H" },
    { "zeppelin", "Orgrimmar Zepplins", 0, 2062.4, 293.0, "H" },
    { "boat", "Feathermoon - Feralas", 1, -4197.3, 3286.6, "A" },
    { "boat", "Feathermoon - Feralas", 1, -4347.8, 2444.4, "A" },
}
