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

M.Overlay.RegisterSource("poi", poiSource)
M.Overlay.RegisterSource("rare", rareSource)
M.Overlay.RegisterSource("taxi", taxiSource)

---------------------------------------------------------------------------------
-- Events (registered only while a type is on)
---------------------------------------------------------------------------------

local lastRefresh = 0
local function onEvent(_, event)
    if event == "AREA_POIS_UPDATED" then wipe(poiCache) end
    local now = GetTime()
    if now - lastRefresh < 1 then return end -- vignette events are chatty
    lastRefresh = now
    M.UI:RefreshAll()
end

-- Register or drop listeners to match the toggles.
function Pins:Apply()
    if not self.frame then
        if not (M.db.pinPoi or M.db.pinRare or M.db.pinTaxi) then return end
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
end
