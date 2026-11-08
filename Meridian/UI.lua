local ADDON, M = ...

local UI = {}
M.UI = UI

function UI:Create()
    local f = CreateFrame("Frame", "MeridianFrame", UIParent, "BasicFrameTemplateWithInset")
    f:SetSize(M.db.width, M.db.height)
    f:SetPoint("CENTER")
    f:SetMovable(true)
    f:SetResizable(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f.TitleText:SetText("Meridian")
    tinsert(UISpecialFrames, "MeridianFrame")
    f:Hide()

    local c = M.Canvas:New(f)
    c.view:SetPoint("TOPLEFT", f.InsetBg, "TOPLEFT", 2, -2)
    c.view:SetPoint("BOTTOMRIGHT", f.InsetBg, "BOTTOMRIGHT", -2, 2)
    M.Overlay:Init(c)

    -- resize grip
    local grip = CreateFrame("Button", nil, f)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", -2, 2)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetScript("OnMouseDown", function() f:StartSizing("BOTTOMRIGHT") end)
    grip:SetScript("OnMouseUp", function()
        f:StopMovingOrSizing()
        M.db.width, M.db.height = f:GetWidth(), f:GetHeight()
    end)

    -- zoom controls
    local function btn(label, x, fn)
        local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        b:SetSize(24, 20)
        b:SetPoint("TOPLEFT", x, -4)
        b:SetText(label)
        b:SetScript("OnClick", fn)
    end
    btn("+", 8, function() c:SetZoom(c.zoom * 1.4) end)
    btn("-", 36, function() c:SetZoom(c.zoom / 1.4) end)
    btn("F", 64, function() c:Fit() end)
    btn("@", 92, function() self:GoToPlayer() end)
    btn("R", 148, function() self:ToggleReveal() end)
    btn("Z", 120, function() self:GoToPlayer(true) end)

    self:CreatePlayerMarker(f, c)
    self:CreateReadout(f, c)

    local ev = CreateFrame("Frame")
    ev:RegisterEvent("QUEST_LOG_UPDATE")
    ev:RegisterEvent("QUEST_POI_UPDATE")
    ev:RegisterEvent("MAP_EXPLORATION_UPDATED")
    ev:SetScript("OnEvent", function(_, event)
        if not f:IsShown() then return end
        if event == "MAP_EXPLORATION_UPDATED" then c:Rebuild() end
        M.Overlay:Refresh()
    end)

    f:SetScript("OnShow", function()
        if not c.mapID then self:GoToPlayer() end
    end)
    self.frame, self.canvas = f, c
end

function UI:SetMap(uiMapID)
    self.canvas:SetMap(uiMapID)
    M.Overlay:Refresh()
end

-- Walk up the map tree to the continent containing uiMapID.
local function continentOf(uiMapID)
    local id = uiMapID
    while id and id > 0 do
        local info = C_Map.GetMapInfo(id)
        if not info then return nil end
        if info.mapType == Enum.UIMapType.Continent then return id end
        id = info.parentMapID
    end
end

-- zoneOnly=true shows just the player's zone instead of the stitched continent.
function UI:GoToPlayer(zoneOnly)
    local zone = C_Map.GetBestMapForUnit("player")
    if not zone then return M:Print("No map for current location.") end
    self:SetMap((not zoneOnly and continentOf(zone)) or zone)
    local pos = C_Map.GetPlayerMapPosition(zone, "player")
    if pos then
        local x, y = pos:GetXY()
        local px, py = self.canvas:ZoneToCanvas(zone, x, y)
        if px then self.canvas:CenterOnCanvas(px, py) end
    end
end

-- Player arrow: constant on-screen size (counter-scaled), rotated to facing.
function UI:CreatePlayerMarker(f, c)
    local m = CreateFrame("Frame", nil, c.pinLayer)
    m:SetSize(24, 24)
    m:SetFrameLevel(c.pinLayer:GetFrameLevel() + 50)
    m.tex = m:CreateTexture(nil, "OVERLAY")
    m.tex:SetAllPoints()
    m.tex:SetTexture("Interface\\Minimap\\MinimapArrow")
    self.marker = m
    local acc = 0
    f:HookScript("OnUpdate", function(_, dt)
        acc = acc + dt
        if acc < 0.1 then return end
        acc = 0
        self:UpdatePlayerMarker()
    end)
    local prev = c.OnChanged
    c.OnChanged = function(...) if prev then prev(...) end; self:UpdatePlayerMarker() end
end

function UI:UpdatePlayerMarker()
    local m, c = self.marker, self.canvas
    if not (m and c.mapID) then return end
    local zone = C_Map.GetBestMapForUnit("player")
    local pos = zone and c.zones[zone] and C_Map.GetPlayerMapPosition(zone, "player")
    if not pos then return m:Hide() end
    local x, y = pos:GetXY()
    local px, py = c:ZoneToCanvas(zone, x, y)
    local s = 1 / c.zoom
    m:SetScale(s)
    m:ClearAllPoints()
    m:SetPoint("CENTER", c.pinLayer, "TOPLEFT", px / s, -py / s)
    m.tex:SetRotation(GetPlayerFacing() or 0)
    m:Show()
end

-- Bottom-left readout: zone name and map coordinates under the cursor.
function UI:CreateReadout(f, c)
    local fs = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 10, 6)
    local acc = 0
    f:HookScript("OnUpdate", function(_, dt)
        acc = acc + dt
        if acc < 0.05 then return end
        acc = 0
        local px, py = c:CursorOnCanvas()
        local id, x, y = nil
        if px then id, x, y = c:ZoneAt(px, py) end
        if id then
            local info = C_Map.GetMapInfo(id)
            fs:SetFormattedText("%s  %.1f, %.1f", info and info.name or id, x * 100, y * 100)
        else
            fs:SetText("")
        end
    end)
end

function UI:ToggleReveal()
    M.db.reveal = M.db.reveal == "full" and "explored" or "full"
    M:Print("Map reveal:", M.db.reveal == "full" and "fully revealed" or "explored areas only")
    self.canvas:Rebuild()
    M.Overlay:Refresh()
end

function UI:ResetView() self.canvas:Fit() end
function UI:Toggle() self.frame:SetShown(not self.frame:IsShown()) end
