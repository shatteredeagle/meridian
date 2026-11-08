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
        for _, p in ipairs(areaPois(zoneID)) do
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

-- Flight paths are only readable while a flight master's map is open, so they are remembered in the saved data.
local function taxiSource(self, c)
    if not M.db.pinTaxi then return end
    local cr, cg, cb = M.Overlay.markerColor("taxi")
    for map, nodes in pairs(M.db.taxi) do
        if c.mapID == map or c.zones[map] then
            for _, n in ipairs(nodes) do
                self:AddMarker(map, { x = n.x, y = n.y, pin = "taxi", size = 16, r = cr, g = cg, b = cb, title = n.name, kind = "taxi",
                    lines = { "Flight path" } })
            end
        end
    end
end

M.Overlay.RegisterSource("poi", poiSource)
M.Overlay.RegisterSource("rare", rareSource)
M.Overlay.RegisterSource("taxi", taxiSource)

---------------------------------------------------------------------------------
-- Events (registered only while a type is on)
---------------------------------------------------------------------------------

local function harvestTaxi()
    if not (M.db.pinTaxi and C_TaxiMap and C_TaxiMap.GetAllTaxiNodes) then return end
    local map = GetTaxiMapID and GetTaxiMapID() or C_Map.GetBestMapForUnit("player")
    if not map then return end
    local list = {}
    for _, n in ipairs(C_TaxiMap.GetAllTaxiNodes(map) or {}) do
        local x, y = Pins.xy(n.position)
        if n.name and x then list[#list + 1] = { name = n.name, x = x, y = y } end
    end
    if #list > 0 then
        M.db.taxi[map] = list
        M.UI:RefreshAll()
    end
end

local lastRefresh = 0
local function onEvent(_, event)
    if event == "TAXIMAP_OPENED" then return harvestTaxi() end
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
    if M.db.pinTaxi then f:RegisterEvent("TAXIMAP_OPENED") end
    if M.db.pinRare then
        f:RegisterEvent("VIGNETTES_UPDATED")
        f:RegisterEvent("VIGNETTE_MINIMAP_UPDATED")
    end
    if M.db.pinPoi then f:RegisterEvent("AREA_POIS_UPDATED") end
end
