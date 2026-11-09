-- Optional minimap: a small pan/zoom map that follows the player. Drag to pan (stops following), "@" re-follows.
local ADDON, M = ...
local UI = M.UI

local MIN_SIZE, MAX_SIZE = 100, 800

-- Width and height: the grip sets them freely; the options slider resets both to one square size.
local function miniSize()
    return M.db.miniW or M.db.miniSize, M.db.miniH or M.db.miniSize
end

function UI:CreateMini()
    local f = CreateFrame("Frame", "MeridianMini", UIParent, "BackdropTemplate")
    local w, h = miniSize()
    f:SetSize(w, h)
    if M.db.miniPos then
        f:SetPoint(M.db.miniPos[1], UIParent, M.db.miniPos[2], M.db.miniPos[3], M.db.miniPos[4])
    else
        f:SetPoint("TOPRIGHT", -30, -200)
    end
    f:SetAlpha(M.db.miniAlpha or 1)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    if not M.db.miniRound then f:SetBackdrop({ edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12 }) end
    f:SetFrameStrata("LOW") -- below bags, the character panel and dialogs; the minimap never covers other windows

    local c = M.Canvas:New(f, { round = M.db.miniRound, alwaysFull = true })
    c.view:SetPoint("TOPLEFT", 3, -3)
    c.view:SetPoint("BOTTOMRIGHT", -3, 3)
    local overlay = M.Overlay:New(c)
    c.view.bg = c.view:CreateTexture(nil, "BACKGROUND")
    c.view.bg:SetAllPoints()
    c.view.bg:SetColorTexture(0.12, 0.24, 0.30, 1)
    if c.mask then c.view.bg:AddMaskTexture(c.mask) end
    self:AttachMarker(f, c)
    self.mini = { frame = f, canvas = c, overlay = overlay, follow = true }
    local mini = self.mini

    -- move handle (top edge) and re-follow button
    local grab = CreateFrame("Button", nil, f)
    grab:SetSize(f:GetWidth() - 30, 10)
    grab:SetPoint("TOPLEFT", 0, 0)
    grab:RegisterForDrag("LeftButton")
    grab:SetScript("OnDragStart", function() if not M.db.locked then f:StartMoving() end end)
    grab:SetScript("OnDragStop", function()
        f:StopMovingOrSizing()
        local point, _, rel, x, y = f:GetPoint()
        M.db.miniPos = { point, rel, x, y }
    end)
    grab:SetHeight(14)
    grab:SetFrameLevel(f:GetFrameLevel() + 60) -- above the canvas and its pins, or the strip never gets the mouse
    mini.grab = grab

    -- resize grip (bottom-right): drag to scale the square; the size is saved
    local grip = CreateFrame("Button", nil, f)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", -1, 1)
    grip:SetFrameLevel(f:GetFrameLevel() + 60)
    -- a circle's corner is empty, so tuck the grip onto the rim at the lower right
    if M.db.miniRound then grip:SetPoint("BOTTOMRIGHT", -(f:GetWidth() * 0.12), f:GetHeight() * 0.12) end
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:SetScript("OnMouseDown", function(_, btn)
        if btn ~= "LeftButton" or M.db.locked then return end
        local cx, cy = GetCursorPosition()
        local sc = f:GetEffectiveScale()
        grip.sx, grip.sy, grip.w, grip.h, grip.scale = cx / sc, cy / sc, f:GetWidth(), f:GetHeight(), sc
        grip.wasFollow = mini.follow
        grip:SetScript("OnUpdate", function()
            local x, y = GetCursorPosition()
            local dx, dy = x / grip.scale - grip.sx, grip.sy - y / grip.scale
            local w = math.max(MIN_SIZE, math.min(MAX_SIZE, math.floor(grip.w + dx + 0.5)))
            local h = math.max(MIN_SIZE, math.min(MAX_SIZE, math.floor(grip.h + dy + 0.5)))
            local ow, oh = miniSize()
            if w ~= ow or h ~= oh then
                M.db.miniW, M.db.miniH = w, h
                UI:ApplyMini(true)
                -- the view grows from its top-left corner; shift the map by half so the same spot stays in the middle
                if not mini.follow then c:SetOffset(c.offX + (w - ow) / 2, c.offY + (h - oh) / 2) end
            end
        end)
    end)
    grip:SetScript("OnMouseUp", function()
        grip:SetScript("OnUpdate", nil)
        if grip.wasFollow ~= nil then mini.follow = grip.wasFollow end -- resizing never unpins
    end)
    grip:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("Drag to resize")
        GameTooltip:AddLine("Drag the top strip to move.", 1, 1, 1)
        GameTooltip:Show()
    end)
    grip:SetScript("OnLeave", GameTooltip_Hide)
    mini.grip = grip
    grab.tex = grab:CreateTexture(nil, "OVERLAY")
    grab.tex:SetAllPoints()
    grab.tex:SetColorTexture(1, 1, 1, 0.12)
    grab.tex:Hide() -- only shown while the mouse is over the strip
    grab:SetScript("OnEnter", function() grab.tex:Show() end)
    grab:SetScript("OnLeave", function() grab.tex:Hide() end)
    local re = M.Widgets.IconButton(f, "locate", "Follow me", "Re-center and keep following.", function() mini.follow = true end,
        { size = 18, iconSize = 12 })
    re:SetPoint("TOPRIGHT", -2, -2)
    re:SetFrameLevel(f:GetFrameLevel() + 60)
    c.view:HookScript("OnMouseDown", function(_, btn) if btn == "LeftButton" then mini.follow = false end end)

    -- right-click: a menu with the same toggles as the main window's top row
    c.view:HookScript("OnMouseUp", function(_, btn)
        if btn ~= "RightButton" then return end
        if not (MenuUtil and MenuUtil.CreateContextMenu) then return M.Options:Open() end
        MenuUtil.CreateContextMenu(f, function(_, root)
            root:CreateTitle("Meridian")
            local function zoom(factor)
                M.db.miniZoom = math.max(0.5, math.min(4, M.db.miniZoom * factor))
                c:SetZoom(M.db.miniZoom)
                mini.zoomApplied = M.db.miniZoom
            end
            root:CreateButton("Zoom in", function() zoom(1.4) end)
            root:CreateButton("Zoom out", function() zoom(1 / 1.4) end)
            root:CreateButton("Find me (follow)", function() mini.follow = true end)
            -- opacity: a slider where the menu system has one, else a short list of steps
            local function setAlpha(v) M.db.miniAlpha = math.max(0.1, math.min(1, v)); f:SetAlpha(M.db.miniAlpha) end
            local ok = M.db.miniAlpha ~= nil and pcall(function()
                root:CreateSlider("Opacity", function() return M.db.miniAlpha or 1 end, setAlpha, 0.1, 1, 0.05)
            end)
            if not ok then
                local sub = root:CreateButton("Opacity")
                for _, pct in ipairs({ 100, 85, 70, 55, 40, 25, 10 }) do
                    sub:CreateRadio(pct .. "%", function() return math.abs((M.db.miniAlpha or 1) * 100 - pct) < 3 end, function() setAlpha(pct / 100) end)
                end
            end
            root:CreateDivider()
            root:CreateCheckbox("Quest areas", function() return M.db.overlays end, function() UI:ToggleOverlays() end)
            root:CreateCheckbox("Quest givers", function() return M.db.avail end, function() UI:ToggleGivers() end)
            root:CreateCheckbox("Flight points", function() return M.db.pinTaxi end,
                function() M.db.pinTaxi = not M.db.pinTaxi; M.Pins:Apply(); UI:RefreshAll() end)
            root:CreateCheckbox("Boats and zeppelins", function() return M.db.pinTransport end,
                function() M.db.pinTransport = not M.db.pinTransport; UI:RefreshAll() end)
            root:CreateCheckbox("Direction arrow", function() return M.db.arrow end, function() M.Arrow:Toggle() end)
            root:CreateCheckbox("Coordinates and N marker", function() return M.db.miniCoords end,
                function() M.db.miniCoords = not M.db.miniCoords end)
            root:CreateCheckbox("Lock window, minimap and arrow", function() return M.db.locked end,
                function() M.db.locked = not M.db.locked end)
            root:CreateDivider()
            root:CreateButton("Clear waypoints and arrow target", function()
                M.db.target = nil -- a quest picked for the arrow
                if M.Arrow.areas then M.Arrow.areas = nil end
                M.Way:Clear()
            end)
            root:CreateButton("Open the map", function() if not UI.frame:IsShown() then UI:Toggle() end end)
            root:CreateButton("Options", function() M.Options:Open() end)
            root:CreateButton("Hide minimap", function() UI:ToggleMini() end)
        end)
    end)

    -- north marker (the map never rotates) and player coordinates
    local north = f:CreateFontString(nil, "OVERLAY", "MeridianFontGold")
    north:SetPoint("TOP", f, "TOP", 0, -12)
    north:SetText("N")
    local cbtn = CreateFrame("Button", nil, f)
    cbtn:SetSize(70, 14)
    cbtn:SetPoint("BOTTOM", f, "BOTTOM", 0, 8)
    local coords = cbtn:CreateFontString(nil, "OVERLAY", "MeridianFontWhite")
    coords:SetAllPoints()
    cbtn:SetScript("OnClick", function()
        UI:ClickCoords(function()
            local zone = C_Map.GetBestMapForUnit("player")
            local pp = zone and C_Map.GetPlayerMapPosition(zone, "player")
            if pp then local x, y = pp:GetXY(); return UI:WayText(zone, x, y) end
        end, cbtn)
    end)
    mini.north, mini.coords = north, coords

    -- mouse-wheel zoom becomes the minimap's zoom, so later settings changes and resizes don't undo it
    local prev = c.OnChanged
    c.OnChanged = function(...)
        if prev then prev(...) end
        if c.mapID and not mini.busy and c.zoom ~= M.db.miniZoom then
            M.db.miniZoom = math.max(0.5, math.min(4, c.zoom))
            mini.zoomApplied = M.db.miniZoom
        end
    end

    local acc = 0
    f:SetScript("OnUpdate", function(_, dt)
        acc = acc + dt
        if acc < 0.2 then return end
        acc = 0
        local zone = C_Map.GetBestMapForUnit("player")
        if not zone then return end
        local target = UI.continentOf(zone) or zone
        if c.mapID ~= target then
            mini.busy = true -- Fit() inside SetMap must not overwrite the saved zoom
            c:SetMap(target)
            c:SetZoom(M.db.miniZoom)
            mini.busy = nil
            overlay:Refresh()
        end
        north:SetShown(M.db.miniCoords)
        if M.db.miniCoords then
            local pp = C_Map.GetPlayerMapPosition(zone, "player")
            if pp then
                local x, y = pp:GetXY()
                coords:SetFormattedText("%.1f, %.1f", x * 100, y * 100)
            else
                coords:SetText("")
            end
        else
            coords:SetText("")
        end
        if mini.follow then
            local px, py = UI:PlayerCanvasPos(c)
            if px then c:CenterOnCanvas(px, py) end
        end
        UI:UpdateMarker(c) -- the player arrow also moves when the map is panned away (follow off), not only when it recentres
    end)
    f:SetShown(M.db.mini)
end

-- Size and zoom from settings (live).
function UI:ApplyMini(sizeOnly)
    local mini = self.mini
    local w, h = miniSize()
    mini.frame:SetSize(w, h)
    mini.frame:SetAlpha(M.db.miniAlpha or 1)
    mini.grab:SetWidth(w - 30)
    if sizeOnly then return end
    if mini.canvas.mapID and mini.canvas.zoom ~= M.db.miniZoom and mini.zoomApplied ~= M.db.miniZoom then
        mini.zoomApplied = M.db.miniZoom
        mini.canvas:SetZoom(M.db.miniZoom)
    end
end

function UI:ToggleMini()
    M.db.mini = not M.db.mini
    self.mini.frame:SetShown(M.db.mini)
    if M.db.mini then self.mini.follow = true; self:RefreshAll() end
    self:SyncToolbar()
end
