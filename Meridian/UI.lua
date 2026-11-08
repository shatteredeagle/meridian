local ADDON, M = ...

local UI = {}
M.UI = UI

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
UI.continentOf = continentOf

local function savePosition(f)
    local point, _, rel, x, y = f:GetPoint()
    M.db.pos = { point, rel, x, y }
end

-- Player arrow: constant on-screen size (counter-scaled), rotated to facing. Updates ~10x/s from `host`.
function UI:AttachMarker(host, c)
    local m = CreateFrame("Frame", nil, c.pinLayer)
    m:SetSize(24, 24)
    m:SetFrameLevel(c.pinLayer:GetFrameLevel() + 50)
    m.tex = m:CreateTexture(nil, "OVERLAY")
    m.tex:SetAllPoints()
    m.tex:SetTexture("Interface\\Minimap\\MinimapArrow")
    c.marker = m
    local acc = 0
    host:HookScript("OnUpdate", function(_, dt)
        acc = acc + dt
        if acc < 0.1 then return end
        acc = 0
        self:UpdateMarker(c)
    end)
    local prev = c.OnChanged
    c.OnChanged = function(...) if prev then prev(...) end; self:UpdateMarker(c) end
end

-- Returns the player's canvas position on c, or nil.
function UI:PlayerCanvasPos(c)
    local zone = C_Map.GetBestMapForUnit("player")
    local pos = zone and c.zones[zone] and C_Map.GetPlayerMapPosition(zone, "player")
    if not pos then return nil end
    local x, y = pos:GetXY()
    return c:ZoneToCanvas(zone, x, y)
end

function UI:UpdateMarker(c)
    local m = c.marker
    if not (m and c.mapID) then return end
    local px, py = self:PlayerCanvasPos(c)
    if not px then return m:Hide() end
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

function UI:Create()
    local f = CreateFrame("Frame", "MeridianFrame", UIParent, "BasicFrameTemplateWithInset")
    f:SetSize(M.db.width, M.db.height)
    if M.db.pos then
        f:SetPoint(M.db.pos[1], UIParent, M.db.pos[2], M.db.pos[3], M.db.pos[4])
    else
        f:SetPoint("CENTER")
    end
    f:SetMovable(true)
    f:SetResizable(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function() f:StopMovingOrSizing(); savePosition(f) end)
    f.TitleText:SetText("Meridian")
    tinsert(UISpecialFrames, "MeridianFrame")
    f:Hide()

    local c = M.Canvas:New(f)
    self.frame, self.canvas = f, c
    c.view:SetPoint("TOPLEFT", f.InsetBg, "TOPLEFT", 2, -2)
    c.view:SetPoint("BOTTOMRIGHT", f.InsetBg, "BOTTOMRIGHT", -2, 2)
    self.overlay = M.Overlay:New(c)

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

    -- toolbar
    local function btn(label, x, tip, fn)
        local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        b:SetSize(24, 20)
        b:SetPoint("TOPLEFT", x, -4)
        b:SetText(label)
        b:SetScript("OnClick", fn)
        b:SetScript("OnEnter", function(s)
            GameTooltip:SetOwner(s, "ANCHOR_BOTTOM")
            GameTooltip:SetText(tip)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", GameTooltip_Hide)
    end
    btn("+", 8, "Zoom in", function() c:SetZoom(c.zoom * 1.4) end)
    btn("-", 36, "Zoom out", function() c:SetZoom(c.zoom / 1.4) end)
    btn("F", 64, "Fit whole map", function() c:Fit() end)
    btn("@", 92, "Continent, centered on you", function() self:GoToPlayer() end)
    btn("Z", 120, "Your zone only", function() self:GoToPlayer(true) end)
    btn("R", 148, "Toggle fully revealed / explored only", function() self:ToggleReveal() end)
    btn("Q", 176, "Toggle quest overlays", function() self:ToggleOverlays() end)
    btn("T", 204, "Toggle quest list", function() self:ToggleTracker() end)
    btn("M", 232, "Toggle minimap", function() self:ToggleMini() end)

    self:AttachMarker(f, c)
    self:CreateReadout(f, c)
    M.Tracker:Create(f, c, self.overlay)
    self:LayoutView()

    -- double-click a zone on the continent view to drill into it
    c.view:SetScript("OnMouseUp", function(_, btnName)
        local d = c.dragging
        c.dragging = nil
        if btnName == "LeftButton" and d then
            local now = GetTime()
            if self.lastClick and now - self.lastClick < 0.3 and math.abs(c.offX - d.ox) + math.abs(c.offY - d.oy) < 4 then
                local px, py = c:CursorOnCanvas()
                local id = px and c:ZoneAt(px, py)
                if id and id ~= c.mapID then self:SetMap(id) end
            end
            self.lastClick = now
        end
    end)

    local ev = CreateFrame("Frame")
    ev:RegisterEvent("QUEST_LOG_UPDATE")
    ev:RegisterEvent("QUEST_POI_UPDATE")
    ev:RegisterEvent("MAP_EXPLORATION_UPDATED")
    ev:SetScript("OnEvent", function(_, event)
        if event == "MAP_EXPLORATION_UPDATED" and f:IsShown() then c:Rebuild() end
        self:RefreshAll()
    end)

    f:SetScript("OnShow", function()
        if not c.mapID then self:GoToPlayer() end
        self:RefreshAll()
    end)

    self:CreateMini()
end

function UI:RefreshAll()
    if self.frame:IsShown() then
        self.overlay:Refresh()
        M.Tracker:Refresh()
    end
    if self.mini and self.mini.frame:IsShown() then self.mini.overlay:Refresh() end
end

function UI:LayoutView()
    local c, f = self.canvas, self.frame
    c.view:ClearAllPoints()
    c.view:SetPoint("TOPLEFT", f.InsetBg, "TOPLEFT", 2, -2)
    if M.db.tracker then
        c.view:SetPoint("BOTTOMRIGHT", M.Tracker.panel, "BOTTOMLEFT", -2, 0)
    else
        c.view:SetPoint("BOTTOMRIGHT", f.InsetBg, "BOTTOMRIGHT", -2, 2)
    end
end

function UI:SetMap(uiMapID)
    self.canvas:SetMap(uiMapID)
    self.overlay:Refresh()
end

-- zoneOnly=true shows just the player's zone instead of the stitched continent.
function UI:GoToPlayer(zoneOnly)
    local zone = C_Map.GetBestMapForUnit("player")
    if not zone then return M:Print("No map for current location.") end
    self:SetMap((not zoneOnly and continentOf(zone)) or zone)
    local px, py = self:PlayerCanvasPos(self.canvas)
    if px then self.canvas:CenterOnCanvas(px, py) end
end

function UI:ToggleReveal()
    M.db.reveal = M.db.reveal == "full" and "explored" or "full"
    M:Print("Map reveal:", M.db.reveal == "full" and "fully revealed" or "explored areas only")
    self.canvas:Rebuild()
    if self.mini then self.mini.canvas:Rebuild() end
    self:RefreshAll()
end

function UI:ToggleOverlays()
    M.db.overlays = not M.db.overlays
    self:RefreshAll()
end

function UI:ToggleTracker()
    M.db.tracker = not M.db.tracker
    M.Tracker.panel:SetShown(M.db.tracker)
    self:LayoutView()
end

function UI:ResetView() self.canvas:Fit() end
function UI:Toggle() self.frame:SetShown(not self.frame:IsShown()) end
