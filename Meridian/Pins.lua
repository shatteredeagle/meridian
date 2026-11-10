-- Extra map pins, HandyNotes-style, each with its own toggle and all off by default: flight paths, rare/vignette
-- sightings and area points of interest. Nothing is read or listened for until a type is switched on.
local ADDON, M = ...

local Pins = {}
M.Pins = Pins

---------------------------------------------------------------------------------
-- Pure helper
---------------------------------------------------------------------------------

-- x, y from a Blizzard vector (GetXY method) or a plain {x=, y=} table; nil if neither.
function Pins.xy(v)
    if type(v) ~= "table" then return nil end
    if v.GetXY then return v:GetXY() end
    if v.x and v.y then return v.x, v.y end
end

---------------------------------------------------------------------------------
-- Sources
---------------------------------------------------------------------------------

local poiCache = {} -- uiMapID -> array of {name, description, x, y}

local function areaPois(uiMapID)
    local hit = poiCache[uiMapID]
    if hit then return hit end
    hit = {}
    local api = C_AreaPoiInfo
    if api and api.GetAreaPOIForMap and api.GetAreaPOIInfo then
        for _, id in ipairs(api.GetAreaPOIForMap(uiMapID) or {}) do
            local info = api.GetAreaPOIInfo(uiMapID, id)
            local x, y = Pins.xy(info and info.position)
            if info and info.name and x then hit[#hit + 1] = { name = info.name, description = info.description, x = x, y = y } end
        end
    end
    poiCache[uiMapID] = hit
    return hit
end

local function poiSource(self, c)
    if not M.db.pinPoi then return end
    local cr, cg, cb = M.Overlay.markerColor("poi")
    for zoneID in pairs(c.zones) do
        for _, p in ipairs(zoneID > 0 and areaPois(zoneID) or {}) do
            self:AddMarker(zoneID, { x = p.x, y = p.y, pin = "poi", size = 16, r = cr, g = cg, b = cb, title = p.name,
                lines = p.description and p.description ~= "" and { p.description } or nil, kind = "poi" })
        end
    end
end

-- Vignettes (rares, treasures) only exist for what is currently near you, on your current zone map.
local function rareSource(self, c)
    if not M.db.pinRare then return end
    local api = C_VignetteInfo
    local zone = C_Map.GetBestMapForUnit("player")
    if not (api and api.GetVignettes and zone and c.zones[zone]) then return end
    local cr, cg, cb = M.Overlay.markerColor("rare")
    for _, guid in ipairs(api.GetVignettes() or {}) do
        local info = api.GetVignetteInfo(guid)
        local x, y = Pins.xy(api.GetVignettePosition and api.GetVignettePosition(guid, zone))
        if info and info.name and x then
            self:AddMarker(zone, { x = x, y = y, pin = "rare", size = 18, r = cr, g = cg, b = cb, title = info.name, kind = "rare",
                lines = info.isDead and { "Defeated" } or nil })
        end
    end
end

-- Flight points from the bundled list (FlightData.lua, generated from the game's TaxiNodes table). Each is placed on
-- the zone map that contains its world position; the player's faction and neutral ones are shown, and when a town has
-- both a neutral and a faction-specific node, the faction one wins.
local taxiCache -- array of {name, map, x, y, wx, wy, c} for the player's faction, built on first use

local function taxiNodes()
    if taxiCache then return taxiCache end
    taxiCache = {}
    local faction = UnitFactionGroup and UnitFactionGroup("player")
    local mine = faction == "Horde" and "H" or faction == "Alliance" and "A" or nil
    local byName = {}
    for _, n in ipairs(M.FlightData or {}) do
        local f = n[5]
        if not f or f == mine then
            local key = n[1]
            local prev = byName[key]
            if not prev or (f and not prev[5]) then byName[key] = n end
        end
    end
    for _, n in pairs(byName) do
        local map, v = C_Map.GetMapPosFromWorldPos(n[2], CreateVector2D(n[3], n[4]))
        local x, y = Pins.xy(v)
        if map and x then taxiCache[#taxiCache + 1] = { name = n[1], map = map, x = x, y = y, c = n[2], wx = n[3], wy = n[4] } end
    end
    table.sort(taxiCache, function(a, b) return a.name < b.name end)
    return taxiCache
end

local function taxiSource(self, c)
    if not M.db.pinTaxi then return end
    local cr, cg, cb = M.Overlay.markerColor("taxi")
    for _, n in ipairs(taxiNodes()) do
        if c.mapID == n.map or c.zones[n.map] or (c.stitch and c.stitch.world == n.c) then
            self:AddMarker(n.map, { x = n.x, y = n.y, pin = "taxi", size = 16, r = cr, g = cg, b = cb, title = n.name, kind = "taxi",
                lines = { "Flight point" }, hint = "Click: drop a waypoint here.",
                onClick = function(_, btn) if btn == "LeftButton" then M.Way:Add(n.map, n.x, n.y, n.name) end end })
        end
    end
end

-- Your corpse (while you are dead or a ghost): a skull on the map that holds it; click to point the arrow at it.
local function corpseSource(self, c)
    if not M.db.pinCorpse then return end
    local api = C_DeathInfo
    if not (api and api.GetCorpseMapPosition and UnitIsDeadOrGhost and UnitIsDeadOrGhost("player")) then return end
    for zoneID in pairs(c.zones) do
        local x, y
        if zoneID > 0 then x, y = Pins.xy(api.GetCorpseMapPosition(zoneID)) end -- (`a and f()` would keep only f's first value)
        if x then
            local cr, cg, cb = M.Overlay.markerColor("corpse")
            self:AddMarker(zoneID, { x = x, y = y, pin = "corpse", size = 22, r = cr, g = cg, b = cb, title = "Your corpse", kind = "corpse",
                hint = "Click: point the arrow at your corpse.",
                onClick = function(_, btn) if btn == "LeftButton" then M.Way:Add(zoneID, x, y, "Corpse") end end })
            return
        end
    end
end

-- Boat and zeppelin docks (TransportData.lua), for the player's faction, each with its own pin.
local transportCache
local function transportDocks()
    if transportCache then return transportCache end
    transportCache = {}
    local faction = UnitFactionGroup and UnitFactionGroup("player")
    local mine = faction == "Horde" and "H" or faction == "Alliance" and "A" or nil
    for _, d in ipairs(M.TransportData or {}) do
        if not d[6] or d[6] == mine then
            local map, v = C_Map.GetMapPosFromWorldPos(d[3], CreateVector2D(d[4], d[5]))
            local x, y = Pins.xy(v)
            if map and x then transportCache[#transportCache + 1] = { kind = d[1], name = d[2], map = map, x = x, y = y, c = d[3] } end
        end
    end
    return transportCache
end

local function transportSource(self, c)
    if not M.db.pinTransport then return end
    for _, d in ipairs(transportDocks()) do
        if c.mapID == d.map or c.zones[d.map] or (c.stitch and c.stitch.world == d.c) then
            local cr, cg, cb = M.Overlay.markerColor(d.kind)
            self:AddMarker(d.map, { x = d.x, y = d.y, pin = d.kind, size = 18, r = cr, g = cg, b = cb, title = d.name, kind = d.kind,
                lines = { d.kind == "zeppelin" and "Zeppelin" or "Boat" }, hint = "Click: drop a waypoint here.",
                onClick = function(_, btn) if btn == "LeftButton" then M.Way:Add(d.map, d.x, d.y, d.name) end end })
        end
    end
end

M.Overlay.RegisterSource("poi", poiSource)
M.Overlay.RegisterSource("rare", rareSource)
M.Overlay.RegisterSource("taxi", taxiSource)
M.Overlay.RegisterSource("transport", transportSource)
M.Overlay.RegisterSource("corpse", corpseSource)

---------------------------------------------------------------------------------
-- Events (registered only while a type is on)
---------------------------------------------------------------------------------

-- Auto-track the corpse: when you die (or are a ghost) a "Corpse" waypoint points the arrow at it; it goes when you are
-- alive again. Only a waypoint this function made is ever removed.
local function findCorpse()
    local api = C_DeathInfo
    if not (api and api.GetCorpseMapPosition) then return nil end
    local zone = C_Map.GetBestMapForUnit("player")
    local tried = {}
    local function try(id)
        if not id or id <= 0 or tried[id] then return nil end
        tried[id] = true
        local x, y = Pins.xy(api.GetCorpseMapPosition(id))
        if x then return id, x, y end
    end
    local id, x, y = try(zone)
    if id then return id, x, y end
    local info = zone and C_Map.GetMapInfo(zone)
    id, x, y = try(info and info.parentMapID)
    if id then return id, x, y end
    local cont = zone and M.UI and M.UI.continentOf(zone)
    for _, k in ipairs(cont and C_Map.GetMapChildrenInfo(cont, Enum.UIMapType.Zone, true) or {}) do
        id, x, y = try(k.mapID)
        if id then return id, x, y end
    end
end

function Pins.syncCorpse()
    if not M.db.autoCorpse then return end
    local dead = UnitIsDeadOrGhost and UnitIsDeadOrGhost("player")
    local mine = M.db.corpseWay
    if dead then
        local have
        for _, w in ipairs(M.db.waypoints) do if w.id == mine then have = w end end
        if have then return end
        local map, x, y = findCorpse()
        if map then
            local wp = M.Way:Add(map, x, y, "Corpse")
            M.db.corpseWay = wp.id
        end
    elseif mine then
        for _, w in ipairs(M.db.waypoints) do
            if w.id == mine then M.Way:Remove(w) break end
        end
        M.db.corpseWay = nil
    end
end

local CORPSE_EVENTS = { PLAYER_DEAD = true, PLAYER_ALIVE = true, PLAYER_UNGHOST = true, CORPSE_POSITION_UPDATE = true }

local lastRefresh = 0
local function onEvent(_, event)
    if CORPSE_EVENTS[event] then Pins.syncCorpse() end
    if event == "AREA_POIS_UPDATED" then wipe(poiCache) end
    local now = GetTime()
    if now - lastRefresh < 1 then return end -- vignette events are chatty
    lastRefresh = now
    M.UI:RefreshAll()
end

-- Register or drop listeners to match the toggles.
function Pins:Apply()
    if not self.frame then
        if not (M.db.pinPoi or M.db.pinRare or M.db.pinTaxi or M.db.pinCorpse or M.db.autoCorpse) then return end
        self.frame = CreateFrame("Frame")
        self.frame:SetScript("OnEvent", onEvent)
    end
    local f = self.frame
    f:UnregisterAllEvents()
    if M.db.pinRare then
        f:RegisterEvent("VIGNETTES_UPDATED")
        f:RegisterEvent("VIGNETTE_MINIMAP_UPDATED")
    end
    if M.db.pinPoi then f:RegisterEvent("AREA_POIS_UPDATED") end
    if M.db.pinCorpse or M.db.autoCorpse then
        for _, e in ipairs({ "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST", "CORPSE_POSITION_UPDATE" }) do
            pcall(f.RegisterEvent, f, e)
        end
    end
end
