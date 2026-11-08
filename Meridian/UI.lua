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
    local W = M.Widgets
    local f = CreateFrame("Frame", "MeridianFrame", UIParent, "BackdropTemplate")
    W.Panel(f)
    f:SetSize(M.db.width, M.db.height)
    if M.db.pos then
        f:SetPoint(M.db.pos[1], UIParent, M.db.pos[2], M.db.pos[3], M.db.pos[4])
    else
        f:SetPoint("CENTER")
    end
    f:SetMovable(true)
    f:SetResizable(true)
    if f.SetResizeBounds then f:SetResizeBounds(680, 420) end
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function() f:StopMovingOrSizing(); savePosition(f) end)
    tinsert(UISpecialFrames, "MeridianFrame")
    f:Hide()

    -- title bar
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.title:SetPoint("TOPLEFT", 12, -9)
    f.title:SetText("Meridian")
    W.IconButton(f, "close", "Close", nil, function() f:Hide() end, { size = 22, iconSize = 12 }):SetPoint("TOPRIGHT", -4, -4)

    -- toolbar strip
    local tb = CreateFrame("Frame", nil, f)
    tb:SetPoint("TOPLEFT", 1, -28)
    tb:SetPoint("TOPRIGHT", -1, -28)
    tb:SetHeight(34)
    tb.bg = tb:CreateTexture(nil, "BACKGROUND")
    tb.bg:SetAllPoints()
    tb.bg:SetColorTexture(1, 1, 1, 0.04)
    tb.line = tb:CreateTexture(nil, "ARTWORK")
    tb.line:SetPoint("BOTTOMLEFT")
    tb.line:SetPoint("BOTTOMRIGHT")
    tb.line:SetHeight(1)
    tb.line:SetColorTexture(1, 1, 1, 0.1)
    self.toolbar = tb

    -- map area and footer
    f.content = CreateFrame("Frame", nil, f)
    f.content:SetPoint("TOPLEFT", tb, "BOTTOMLEFT", 5, -5)
    f.content:SetPoint("BOTTOMRIGHT", -6, 24)

    local c = M.Canvas:New(f)
    self.frame, self.canvas = f, c
    self.overlay = M.Overlay:New(c)
    c.view.bg = c.view:CreateTexture(nil, "BACKGROUND")
    c.view.bg:SetAllPoints()
    c.view.bg:SetColorTexture(0, 0, 0, 0.6)

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

    -- toolbar: icon buttons in groups; toggles show their state
    self.toggles = {}
    local x = 8
    local function add(icon, title, desc, fn, state)
        local b = W.IconButton(tb, icon, title, desc, fn, { toggle = state ~= nil, state = state })
        b:SetPoint("LEFT", tb, "LEFT", x, 0)
        x = x + 28
        if state then self.toggles[#self.toggles + 1] = { b, state } end
        return b
    end
    local function gap()
        local sep = W.Separator(tb)
        sep:SetPoint("LEFT", tb, "LEFT", x + 3, 0)
        x = x + 12
    end
    add("plus", "Zoom in", "Mouse wheel also zooms at the cursor.", function() c:SetZoom(c.zoom * 1.4) end)
    add("minus", "Zoom out", nil, function() c:SetZoom(c.zoom / 1.4) end)
    add("fit", "Fit to window", "Show the whole map.", function() c:Fit() end)
    gap()
    add("continent", "Continent view", "All zones stitched together, centered on you.", function() self:GoToPlayer() end)
    add("zone", "Zone view", "Just the zone you are in. Double-click any zone on the continent to open it.", function() self:GoToPlayer(true) end)
    add("locate", "Find me", "Center on your position.", function() self:CenterOnPlayer() end)
    gap()
    add("reveal", "Reveal map", "On: whole map revealed. Off: only areas you have explored.",
        function() self:ToggleReveal() end, function() return M.db.reveal == "full" end)
    add("areas", "Quest areas", "Colored areas where your quest objectives are. Overlaps add up; hover for names.",
        function() self:ToggleOverlays() end, function() return M.db.overlays end)
    add("givers", "Quest givers", "Markers for quests you can pick up now.",
        function() self:ToggleGivers() end, function() return M.db.avail end)
    add("arrow", "Direction arrow", "Points to the nearest quest area. Shift-click a quest in the list to pick one.",
        function() M.Arrow:Toggle() end, function() return M.db.arrow end)
    gap()
    add("list", "Quest list", "Show or hide the quest panel.",
        function() self:ToggleTracker() end, function() return M.db.tracker end)
    add("minimap", "Minimap", "A small map that follows you.",
        function() self:ToggleMini() end, function() return M.db.mini end)
    gap()
    add("gear", "Options", "Opacity, marker size, arrow, minimap and more. Also /mm config.", function() M.Options:Open() end)

    self:AttachMarker(f, c)
    self:CreateReadout(f, c)
    M.Tracker:Create(f, c, self.overlay)
    self:LayoutView()

    -- double-click a zone on the continent view to drill into it
    c.view:SetScript("OnMouseUp", function(_, btnName)
        local d = c.dragging
        c.dragging = nil
        if btnName == "LeftButton" and d and IsControlKeyDown() and math.abs(c.offX - d.ox) + math.abs(c.offY - d.oy) < 4 then
            return M.Way:AddFromCursor(c) -- Ctrl-click drops a waypoint
        end
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
    M.Arrow:Create(self.overlay)
    self:SyncToolbar()
end

-- Re-read every toggle's state into its button.
function UI:SyncToolbar()
    for _, t in ipairs(self.toggles or {}) do t[1]:SetActive(t[2]()) end
end

-- Apply saved settings to the live frames. `after`: "map" re-reads pins, "rebuild" redraws map art, "reload" nothing more.
function UI:ApplySettings(after)
    self.overlay:ApplyAlpha()
    if self.mini then self.mini.overlay:ApplyAlpha() end
    if M.Tracker.SyncSlider then M.Tracker:SyncSlider() end
    self.overlay:Rescale()
    if self.mini then self.mini.overlay:Rescale(); self:ApplyMini() end
    M.Arrow:ApplyStyle()
    self.mini.frame:SetShown(M.db.mini)
    if M.db.arrow ~= M.Arrow.frame:IsShown() then M.Arrow.frame:SetShown(M.db.arrow); M.Arrow.areas = nil end
    if after == "rebuild" then
        self.canvas:Rebuild()
        if self.mini then self.mini.canvas:Rebuild() end
    end
    if after == "map" or after == "rebuild" then self:RefreshAll() end
    self:SyncToolbar()
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
    c.view:SetPoint("TOPLEFT", f.content, "TOPLEFT", 0, 0)
    if M.db.tracker then
        c.view:SetPoint("BOTTOMRIGHT", M.Tracker.panel, "BOTTOMLEFT", -4, 0)
    else
        c.view:SetPoint("BOTTOMRIGHT", f.content, "BOTTOMRIGHT", 0, 0)
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

-- Center the main map on the player (opens the window if needed).
function UI:CenterOnPlayer()
    if not self.frame:IsShown() then self.frame:Show() end
    local px, py = self:PlayerCanvasPos(self.canvas)
    if px then self.canvas:CenterOnCanvas(px, py) else self:GoToPlayer() end
end

function UI:ToggleReveal()
    M.db.reveal = M.db.reveal == "full" and "explored" or "full"
    self.canvas:Rebuild()
    if self.mini then self.mini.canvas:Rebuild() end
    self:RefreshAll()
    self:SyncToolbar()
end

function UI:ToggleOverlays()
    M.db.overlays = not M.db.overlays
    self:RefreshAll()
    self:SyncToolbar()
end

function UI:ToggleGivers()
    M.db.avail = not M.db.avail
    self:RefreshAll()
    self:SyncToolbar()
end

function UI:ToggleTracker()
    M.db.tracker = not M.db.tracker
    M.Tracker.panel:SetShown(M.db.tracker)
    self:LayoutView()
    self:SyncToolbar()
end

function UI:ResetView() self.canvas:Fit() end
function UI:Toggle() self.frame:SetShown(not self.frame:IsShown()) end
