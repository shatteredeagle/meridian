-- Waypoints: Ctrl-click the map or use /way (TomTom syntax). Keeps its own list, mirrors the newest one
-- to Blizzard's user waypoint, and hands everything to TomTom when TomTom is installed. Parsing is pure (tested offline).
local ADDON, M = ...

local Way = {}
M.Way = Way

---------------------------------------------------------------------------------
-- Pure helpers
---------------------------------------------------------------------------------

local function trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end

-- Parse the text after "/way". Returns a table or nil, errorText:
--   {cmd = "help"|"clear"|"list"}  or  {map = id|nil, zone = name|nil, x = 0..1, y = 0..1, title = text|nil}
-- Accepts "52 41", "52.3, 41.2", "Elwynn Forest 52 41 Goldshire", "#37 52 41". Numbers above 1 are percentages.
function Way.parse(msg)
    msg = trim(msg or "")
    local low = msg:lower()
    if low == "" or low == "help" or low == "?" then return { cmd = "help" } end
    if low == "clear" or low == "reset" or low == "clear all" then return { cmd = "clear" } end
    if low == "list" then return { cmd = "list" } end

    local toks = {}
    for t in msg:gsub("[,%(%)]", " "):gmatch("%S+") do toks[#toks + 1] = t end
    local i = 1
    while toks[i] and not tonumber(toks[i]) and not toks[i]:match("^#%d+$") do i = i + 1 end
    local r = {}
    if i > 1 then r.zone = table.concat(toks, " ", 1, i - 1) end
    if toks[i] and toks[i]:match("^#%d+$") then
        r.map = tonumber(toks[i]:sub(2))
        r.zone = nil
        i = i + 1
    end
    local x, y = tonumber(toks[i] or ""), tonumber(toks[i + 1] or "")
    if not (x and y) then return nil, "Need two coordinates, e.g. /way 52.3 41.2" end
    if x < 0 or y < 0 or x > 100 or y > 100 then return nil, "Coordinates must be between 0 and 100" end
    if x > 1 or y > 1 then x, y = x / 100, y / 100 end
    r.x, r.y = x, y
    if toks[i + 2] then r.title = table.concat(toks, " ", i + 2) end
    return r
end

-- "/way Zone 52.3 41.2" (the form other players can paste).
function Way.format(zoneName, x, y)
    return string.format("/way %s%.1f %.1f", zoneName and (zoneName .. " ") or "", x * 100, y * 100)
end

-- Best map for a typed name: exact, then prefix, then substring (case-insensitive). maps: array of {name, id}.
function Way.matchName(query, maps)
    query = trim(query or ""):lower()
    if query == "" then return nil end
    local prefix, sub
    for _, m in ipairs(maps) do
        local n = (m.name or ""):lower()
        if n == query then return m.id end
        if not prefix and n:sub(1, #query) == query then prefix = m.id end
        if not sub and n:find(query, 1, true) then sub = m.id end
    end
    return prefix or sub
end

---------------------------------------------------------------------------------
-- Game side
---------------------------------------------------------------------------------

local function list() return M.db.waypoints end

local function mapName(id)
    local info = C_Map.GetMapInfo(id)
    return info and info.name
end

-- Every named zone-level map on the player's continent and the world's continents.
function Way:Resolve(name)
    local maps, seen = {}, {}
    local function addKids(parent)
        for _, k in ipairs(C_Map.GetMapChildrenInfo(parent, nil, true) or {}) do
            if not seen[k.mapID] and k.mapType ~= Enum.UIMapType.Continent then
                seen[k.mapID] = true
                maps[#maps + 1] = { name = k.name, id = k.mapID }
            end
        end
    end
    local here = C_Map.GetBestMapForUnit("player")
    local cont = here and M.UI.continentOf(here)
    if cont then addKids(cont) end
    for _, root in ipairs({ 946, 947 }) do -- cosmic / Azeroth roots; harmless if absent
        for _, k in ipairs(C_Map.GetMapChildrenInfo(root, Enum.UIMapType.Continent, true) or {}) do addKids(k.mapID) end
    end
    return Way.matchName(name, maps)
end

local function blizzardPoint(map, x, y)
    if UiMapPoint and UiMapPoint.CreateFromCoordinates then return UiMapPoint.CreateFromCoordinates(map, x, y) end
    return { uiMapID = map, position = CreateVector2D(x, y) }
end

-- Mirror the active waypoint to Blizzard's own (on-screen marker and super-track arrow).
function Way:SyncBlizzard()
    if not (M.db.blizzWay and C_Map and C_Map.SetUserWaypoint) then return end
    local wp = self:Active()
    if wp then
        if C_Map.CanSetUserWaypointOnMap and not C_Map.CanSetUserWaypointOnMap(wp.map) then return end
        C_Map.SetUserWaypoint(blizzardPoint(wp.map, wp.x, wp.y))
        if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then C_SuperTrack.SetSuperTrackedUserWaypoint(true) end
        self.mirrored = true
    elseif self.mirrored then
        if C_Map.ClearUserWaypoint then C_Map.ClearUserWaypoint() end
        self.mirrored = nil
    end
end

-- The active waypoint is stored by id (saved tables don't keep object identity across reloads).
function Way:Active()
    local id = M.db.wayActive
    if not id then return nil end
    for _, w in ipairs(list()) do if w.id == id then return w end end
end

local function refresh()
    if M.UI and M.UI.frame then M.UI:RefreshAll() end
end

function Way:SetActive(wp)
    M.db.wayActive = wp and wp.id or nil
    if wp then M.db.target = nil end -- a waypoint outranks a picked quest
    self:SyncBlizzard()
    if wp and not M.db.arrow then M.Arrow:Toggle() end
    if M.Arrow.areas then M.Arrow.areas = nil end
end

function Way:Add(map, x, y, title)
    M.db.wayNext = (M.db.wayNext or 0) + 1
    local wp = { id = M.db.wayNext, map = map, x = x, y = y, title = title }
    list()[#list() + 1] = wp
    if _G.TomTom and _G.TomTom.AddWaypoint then
        pcall(_G.TomTom.AddWaypoint, _G.TomTom, map, x, y, { title = title or "Meridian", from = "Meridian" })
    end
    self:SetActive(wp)
    M:Print(string.format("Waypoint set: %s %.1f, %.1f", mapName(map) or map, x * 100, y * 100))
    refresh()
    return wp
end

function Way:Remove(wp)
    for i, w in ipairs(list()) do
        if w == wp then table.remove(list(), i); break end
    end
    if M.db.wayActive == wp.id then
        M.db.wayActive = nil
        self:SyncBlizzard()
    end
    refresh()
end

function Way:Clear()
    wipe(list())
    M.db.wayActive = nil
    self:SyncBlizzard()
    M:Print("Waypoints cleared.")
    refresh()
end

function Way:Slash(msg)
    local r, err = Way.parse(msg)
    if not r then return M:Print(err) end
    if r.cmd == "help" then
        M:Print("/way x y [title] | /way Zone x y [title] | /way #mapID x y | /way list | /way clear. Ctrl-click the map to drop one.")
    elseif r.cmd == "clear" then
        self:Clear()
    elseif r.cmd == "list" then
        if #list() == 0 then return M:Print("No waypoints.") end
        for i, w in ipairs(list()) do
            M:Print(i .. ".", Way.format(mapName(w.map), w.x, w.y), w.title or "", w == self:Active() and "(active)" or "")
        end
    else
        local map = r.map
        if r.zone then
            map = self:Resolve(r.zone)
            if not map then return M:Print("Unknown zone: " .. r.zone) end
        end
        map = map or C_Map.GetBestMapForUnit("player")
        if not map then return M:Print("No map for current location.") end
        self:Add(map, r.x, r.y, r.title)
    end
end

-- Pins on every Meridian canvas (main map and minimap).
M.Overlay.RegisterSource("waypoints", function(self, c)
    local wps = list()
    if not wps or #wps == 0 then return end
    local active = Way:Active()
    for _, w in ipairs(wps) do
        if c.zones[w.map] then
            local cr, cg, cb = M.Overlay.markerColor("way")
            self:AddMarker(w.map, { x = w.x, y = w.y, pin = "way", size = w == active and 22 or 18, r = cr, g = cg, b = cb,
                title = w.title or "Waypoint", lines = { Way.format(mapName(w.map), w.x, w.y) },
                hint = "Left-click: point the arrow here. Right-click: remove.",
                onClick = function(_, btn)
                    if btn == "RightButton" then Way:Remove(w) else Way:SetActive(w) end
                end })
        end
    end
end)

-- Claim /way unless TomTom (which owns it) is installed. Called at login so every addon has loaded.
function Way:Init()
    if _G.TomTom or not M.db.claimWay then return end
    SLASH_MERIDIANWAY1 = "/way"
    SlashCmdList.MERIDIANWAY = function(msg) Way:Slash(msg) end
end

-- Shown on the toolbar tooltip / README: mouse entry point.
function Way:AddFromCursor(canvas)
    local px, py = canvas:CursorOnCanvas()
    if not px then return end
    local id, x, y = canvas:ZoneAt(px, py)
    if not id then return end
    local info = C_Map.GetMapInfo(id)
    if info and info.mapType == Enum.UIMapType.Continent then return M:Print("Zoom into a zone (double-click it) to place a waypoint.") end
    self:Add(id, x, y)
end
