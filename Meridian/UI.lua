local ADDON, M = ...
local L = M.L

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
    local pos = zone and C_Map.GetPlayerMapPosition(zone, "player")
    if not pos then return nil end
    local x, y = pos:GetXY()
    return c:PosToCanvas(zone, x, y) -- also works from a city or sub-zone on a stitched continent
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

-- Text of the "/way" line for a position (zone name resolved from the map).
function UI:WayText(uiMapID, x, y)
    local info = uiMapID and uiMapID > 0 and C_Map.GetMapInfo(uiMapID)
    return M.Way.format(info and info.name, x, y)
end

-- Click handler for a coordinate readout: copy box, or into chat with Shift.
function UI:ClickCoords(getText, anchor)
    local text = getText()
    if not text then return end
    if IsShiftKeyDown() then M.Widgets.ToChat(text, anchor) else M.Widgets.CopyBox(text, anchor) end
end

-- Bottom readouts: zone and map coordinates under the cursor (bottom-left), and your own (bottom-centre).
-- Both are buttons: click copies "/way Zone x y", Shift-click puts it into chat. The cursor readout copies
-- the last point the cursor was over the map, since the cursor is on the readout when you click it.
function UI:CreateReadout(f, c)
    local function makeReadout(point, x)
        local b = CreateFrame("Button", nil, f)
        b:SetHeight(16)
        b:SetPoint(point, f, point, x, 4)
        b.fs = b:CreateFontString(nil, "OVERLAY", "MeridianFontWhite")
        b.fs:SetPoint("LEFT")
        b:SetScript("OnEnter", function(s)
            GameTooltip:SetOwner(s, "ANCHOR_TOP")
            GameTooltip:SetText("Click: copy as /way", 1, 1, 1)
            GameTooltip:AddLine("Shift-click: put it in the chat box", 0.75, 0.75, 0.75)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        return b
    end
    local cur = makeReadout("BOTTOMLEFT", 10)
    local me = makeReadout("BOTTOM", 60)
    cur:SetScript("OnClick", function() self:ClickCoords(function() return self.lastCursorWay end, cur) end)
    me:SetScript("OnClick", function()
        self:ClickCoords(function()
            local zone = C_Map.GetBestMapForUnit("player")
            local pp = zone and C_Map.GetPlayerMapPosition(zone, "player")
            if pp then local x, y = pp:GetXY(); return self:WayText(zone, x, y) end
        end, me)
    end)
    -- Pinned to the character: re-centre every tick, follow the player across zones, unpin when the user pans.
    c.OnWheelEdge = function(delta, cx, cy)
        if M.db.worldView == false or delta > 0 then return false end
        return c.stitch and c.backRect and c.zoom <= (c.fitZoom or 0) * 1.03 and self:ToWorld(cx, cy) or false
    end
    c.AfterWheel = function(delta, cx, cy)
        if M.db.worldView == false or c.mapID ~= WORLD then return end
        if delta < 0 and c.zoom < (c.fitZoom or 0) then c:Fit() end
        if delta > 0 and c.zoom >= (c.fitZoom or 0) * DIVE then self:IntoContinent(cx, cy) end
    end
    c.OnUserPan = function() if M.db.pin then M.db.pin = false; self:SyncToolbar() end end
    local pacc, lastZone, inCity = 0, nil, false
    local function mapIsCity(id) return id and self.isCity(id) end
    f:HookScript("OnUpdate", function(_, dt)
        if not M.db.pin or c.dragging then return end
        pacc = pacc + dt
        if pacc < 0.1 then return end
        pacc = 0
        local zone = C_Map.GetBestMapForUnit("player")
        if zone and zone ~= lastZone then
            lastZone = zone
            local wasCity = inCity
            inCity = mapIsCity(zone)
            if inCity then
                local r = c.stitch and c.zones[zone]
                if r then -- the city is drawn on the continent: just zoom in until its own map has faded in
                    local w, h = c.view:GetWidth(), c.view:GetHeight()
                    if r.w > 0 and r.h > 0 and w > 0 and h > 0 then c:SetZoom(math.min(w / r.w, h / r.h)) end
                elseif c.mapID ~= zone then
                    self:SetMap(zone) -- no continent to draw it on: its own map
                end
                local cx, cy = self:PlayerCanvasPos(c)
                if cx then c:CenterOnCanvas(cx, cy) end
            elseif wasCity or mapIsCity(c.mapID) or (M.Dungeons and M.Dungeons:ForMap(c.mapID)) then
                self:OpenView() -- walked back out of a city or dungeon: zone-level zoom on the continent again
            elseif not c.zones[zone] then
                local mid = c.mapID
                local info = mid and mid > 0 and C_Map.GetMapInfo(mid)
                self:GoToPlayer(not (info and info.mapType == Enum.UIMapType.Continent))
            end
        end
        local px, py = self:PlayerCanvasPos(c)
        if px then c:CenterOnCanvas(px, py) end
    end)
    local acc = 0
    f:HookScript("OnUpdate", function(_, dt)
        acc = acc + dt
        if acc < 0.05 then return end
        acc = 0
        self:UpdateMarker(c) -- the player arrow keeps moving while the map is not following you
        local px, py = c:CursorOnCanvas()
        local id, x, y = nil
        if px then id, x, y = c:ZoneAt(px, py) end
        if id then
            local info = id > 0 and C_Map.GetMapInfo(id)
            cur.fs:SetFormattedText("%s  %.1f, %.1f", info and info.name or id, x * 100, y * 100)
            self.lastCursorWay = self:WayText(id, x, y)
        elseif not cur:IsMouseOver() then
            cur.fs:SetText("")
        end
        cur:SetWidth(math.max(1, cur.fs:GetStringWidth()))
        local zone = C_Map.GetBestMapForUnit("player")
        local pp = zone and C_Map.GetPlayerMapPosition(zone, "player")
        if pp then
            local mx, my = pp:GetXY()
            me.fs:SetFormattedText("You: %.1f, %.1f", mx * 100, my * 100)
        else
            me.fs:SetText("")
        end
        me:SetWidth(math.max(1, me.fs:GetStringWidth()))
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
    f:SetScale(M.db.scale)
    f:SetAlpha(M.db.alpha)
    f:SetMovable(true)
    f:SetResizable(true)
    if f.SetResizeBounds then f:SetResizeBounds(680, 420) end
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function() if not M.db.locked then f:StartMoving() end end)
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
    c.view.bg:SetColorTexture(0.12, 0.24, 0.30, 1) -- sea colour: ground no zone map covers (coasts, gaps between zones) reads as water, not a black hole

    -- resize grip
    local grip = CreateFrame("Button", nil, f)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", -2, 2)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetScript("OnMouseDown", function() if not M.db.locked then f:StartSizing("BOTTOMRIGHT") end end)
    self.grip = grip
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
    add("plus", L["Zoom in"], L["Mouse wheel also zooms at the cursor."], function() c:SetZoom(c.zoom * 1.4) end)
    add("minus", L["Zoom out"], nil, function() c:SetZoom(c.zoom / 1.4) end)
    add("fit", L["Fit to window"], L["Show the whole map."], function() c:Fit() end)
    gap()
    add("continent", L["Continent view"], L["All zones stitched together, centered on you."], function() self:GoToPlayer() end)
    add("zone", L["Zone view"], L["Just the zone you are in. Double-click any zone on the continent to open it."], function() self:GoToPlayer(true) end)
    add("locate", L["Find me"], L["Center on your position."], function() self:CenterOnPlayer() end)
    add("pin", L["Pin to me"], L["Keep the map centered on your character and follow you between zones. Dragging the map unpins it. Also /mm pin."],
        function() self:TogglePin() end, function() return M.db.pin end)
    gap()
    add("reveal", L["Reveal map"], L["On: whole map revealed. Off: only areas you have explored."],
        function() self:ToggleReveal() end, function() return M.db.reveal == "full" end)
    add("areas", L["Quest areas"], L["Colored areas where your quest objectives are. Overlaps add up; hover for names."],
        function() self:ToggleOverlays() end, function() return M.db.overlays end)
    add("givers", L["Quest givers"], L["Markers for quests you can pick up now."],
        function() self:ToggleGivers() end, function() return M.db.avail end)
    add("art", L["Map art style"], L["Cycle the map art: Blizzard, then the three pixel-art experiments (Eastern Kingdoms continent view). Also /mm art [blizzard|a|b|c]."],
        function() M.Art:Set() end, function() return M.Art:Current() ~= "blizzard" end)
    add("dungeons", L["Dungeon maps"], L["Dungeon entrances on the map (click one to open that dungeon's map, with its floors). Also /mm dungeons."],
        function() M.Dungeons:Toggle() end, function() return M.db.dungeons end)
    add("arrow", L["Direction arrow"], L["Points to the nearest quest area. Shift-click a quest in the list to pick one."],
        function() M.Arrow:Toggle() end, function() return M.db.arrow end)
    gap()
    add("list", L["Quest list"], L["Show or hide the quest panel."],
        function() self:ToggleTracker() end, function() return M.db.tracker end)
    add("minimap", L["Minimap"], L["A small map that follows you."],
        function() self:ToggleMini() end, function() return M.db.mini end)
    gap()
    add("gear", L["Options"], L["Opacity, marker size, arrow, minimap and more. Also /mm config."], function() M.Options:Open() end)

    M.Search:Create(tb)
    self:AttachMarker(f, c)
    self:CreateReadout(f, c)
    M.Tracker:Create(f, c, self.overlay)
    self:LayoutView()

    -- double-click a zone on the continent view to drill into it
    c.view:SetScript("OnMouseUp", function(_, btnName)
        local d = c.dragging
        c.dragging = nil
        if btnName == "RightButton" then
            -- right-click empty map: drop a pin and make sure the arrow is on so it points the way
            if M.Way:AddFromCursor(c) and not M.db.arrow then M.Arrow:Toggle() end
            return
        end
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
        if M.db.openView ~= false then self:OpenView() elseif not c.mapID then self:GoToPlayer() end
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

-- Window scale (centre stays put), overall opacity and lock state.
function UI:ApplyWindow()
    local f = self.frame
    local old, new = f:GetScale(), M.db.scale
    if math.abs(old - new) > 0.001 then
        local cx, cy = f:GetCenter()
        f:SetScale(new)
        if cx then
            cx, cy = M.Math.rescaleCenter(cx, cy, old, new)
            f:ClearAllPoints()
            f:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cx, cy)
            savePosition(f)
        end
    end
    f:SetAlpha(M.db.alpha)
    self.grip:SetShown(not M.db.locked)
end

function UI:ResetWindow()
    M.db.scale, M.db.alpha, M.db.pos = 1, 1, nil
    M.db.width, M.db.height = M.defaults.width, M.defaults.height
    local f = self.frame
    f:SetSize(M.db.width, M.db.height)
    f:SetScale(1)
    f:ClearAllPoints()
    f:SetPoint("CENTER")
    self:ApplySettings()
end

-- Apply saved settings to the live frames. `after`: "map" re-reads pins, "rebuild" redraws map art, "reload" nothing more.
function UI:ApplySettings(after)
    M.Widgets.ApplyContrast()
    self:ApplyWindow()
    self.overlay:ApplyAlpha()
    if self.mini then self.mini.overlay:ApplyAlpha() end
    if M.Tracker.SyncSlider then M.Tracker:SyncSlider() end
    M.Launcher:Apply()
    M:ApplyMapKey()
    M.Pad:Apply()
    M.Pins:Apply()
    if after == "route" then M.Route:Refresh(true) end
    self.overlay:Rescale()
    if after == "mini" then M.db.miniW, M.db.miniH = nil, nil end -- the size slider means a square again
    if self.mini then self.mini.overlay:Rescale(); self:ApplyMini() end
    M.Arrow:ApplyStyle()
    self.mini.frame:SetShown(M.db.mini)
    if M.db.arrow ~= M.Arrow.frame:IsShown() then M.Arrow.frame:SetShown(M.db.arrow); M.Arrow.areas = nil end
    if after == "rebuild" then
        self.canvas:Rebuild()
        if self.mini then self.mini.canvas:Rebuild() end
    end
    if after == "map" or after == "rebuild" or after == "pins" then self:RefreshAll() end
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

-- The world map (Azeroth) as the outermost zoom level: zooming out past a continent's fit shows both continents, and
-- zooming into one of them there opens that continent, with the view carried over so it feels like one zoom.
local WORLD, DIVE = 947, 2.2
local CONTINENTS = { 1414, 1415 }

function UI:ToWorld(cx, cy)
    local c = self.canvas
    local l, r, t, b = C_Map.GetMapRectOnMap(c.mapID, WORLD)
    local br = c.backRect
    if not (l and r and r > l and br) then return false end
    local u, v = ((cx - c.offX) / c.zoom - br.x) / br.w, ((cy - c.offY) / c.zoom - br.y) / br.h
    local zoomC, backW = c.zoom, br.w
    self:SetMap(WORLD)
    local W, H = c.cw, c.ch
    local wx, wy = (l + u * (r - l)) * W, (t + v * (b - t)) * H
    c:SetZoom(math.max(c.fitZoom or 0, zoomC * backW / ((r - l) * W)), cx, cy)
    c:SetOffset(cx - wx * c.zoom, cy - wy * c.zoom)
    return true
end

function UI:IntoContinent(cx, cy)
    local c = self.canvas
    local W, H = c.cw, c.ch
    local uw, vw = ((cx - c.offX) / c.zoom) / W, ((cy - c.offY) / c.zoom) / H
    for _, cont in ipairs(CONTINENTS) do
        local l, r, t, b = C_Map.GetMapRectOnMap(cont, WORLD)
        if l and uw >= l and uw <= r and vw >= t and vw <= b then
            local u, v = (uw - l) / (r - l), (vw - t) / (b - t)
            local zoomW = c.zoom
            self:SetMap(cont)
            local br = c.backRect
            if not br then return false end
            c:SetZoom(math.max(c.fitZoom or 0, zoomW * (r - l) * W / br.w), cx, cy)
            c:SetOffset(cx - (br.x + u * br.w) * c.zoom, cy - (br.y + v * br.h) * c.zoom)
            return true
        end
    end
    return false
end

function UI:SetMap(uiMapID)
    local prev = self.canvas.mapID
    self.canvas:SetMap(uiMapID)
    self.overlay:Refresh()
    M.Dungeons:OnMapChanged(uiMapID, prev)
end

-- zoneOnly=true shows just the player's zone instead of the stitched continent.
function UI:GoToPlayer(zoneOnly)
    local zone = C_Map.GetBestMapForUnit("player")
    if not zone then return M:Print("No map for current location.") end
    if M.Dungeons:OpenForMap(zone) then -- inside an instance: show its floor
        local dx, dy = self:PlayerCanvasPos(self.canvas)
        if dx then self.canvas:CenterOnCanvas(dx, dy) end
        return
    end
    self:SetMap((not zoneOnly and continentOf(zone)) or zone)
    local px, py = self:PlayerCanvasPos(self.canvas)
    if px then self.canvas:CenterOnCanvas(px, py) end
end

-- Capital cities, and anything the client types as a city: they get their own map view when the player is in them.
local CITIES = { [1453] = true, [1454] = true, [1455] = true, [1456] = true, [1457] = true, [1458] = true }
function UI.isCity(id)
    if CITIES[id] then return true end
    local info = id and id > 0 and C_Map.GetMapInfo(id)
    return info and info.mapType == Enum.UIMapType.City or false
end

-- Default view on open: the stitched continent, zoomed to about one zone, centred on you and pinned to you.
function UI:OpenView()
    local c = self.canvas
    local zone = C_Map.GetBestMapForUnit("player")
    if not zone then return not c.mapID and self:GoToPlayer() end
    if M.Dungeons:OpenForMap(zone) then -- inside an instance: its floor, pinned
        M.db.pin = true
        return self:SyncToolbar()
    end
    local target = continentOf(zone) or zone
    if c.mapID ~= target then self:SetMap(target) end
    local r = c.zones[zone]
    if not r then -- standing in a city/sub-zone: size to its parent zone
        local info = C_Map.GetMapInfo(zone)
        r = info and c.zones[info.parentMapID]
    end
    local w, h = c.view:GetWidth(), c.view:GetHeight()
    if r and r.w > 0 and r.h > 0 and w > 0 and h > 0 then c:SetZoom(math.min(w / r.w, h / r.h)) end
    local px, py = self:PlayerCanvasPos(c)
    if px then c:CenterOnCanvas(px, py) end
    M.db.pin = true
    self:SyncToolbar()
end

-- Pin the main map to the character (keeps it centred and follows between zones).
function UI:TogglePin()
    M.db.pin = not M.db.pin
    if M.db.pin then
        if not self.frame:IsShown() then self.frame:Show() end
        self:CenterOnPlayer()
    end
    self:SyncToolbar()
    return M.db.pin
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
