-- Optional minimap: a small pan/zoom map that follows the player. Drag to pan (stops following), "@" re-follows.
local ADDON, M = ...
local UI = M.UI

local MIN_SIZE, MAX_SIZE = 120, 600

function UI:CreateMini()
    local f = CreateFrame("Frame", "MeridianMini", UIParent, "BackdropTemplate")
    local s = M.db.miniSize
    f:SetSize(s, s)
    if M.db.miniPos then
        f:SetPoint(M.db.miniPos[1], UIParent, M.db.miniPos[2], M.db.miniPos[3], M.db.miniPos[4])
    else
        f:SetPoint("TOPRIGHT", -30, -200)
    end
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    if not M.db.miniRound then f:SetBackdrop({ edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12 }) end
    f:SetFrameStrata("MEDIUM")

    local c = M.Canvas:New(f, { round = M.db.miniRound, alwaysFull = true })
    c.view:SetPoint("TOPLEFT", 3, -3)
    c.view:SetPoint("BOTTOMRIGHT", -3, 3)
    local overlay = M.Overlay:New(c)
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
    if M.db.miniRound then grip:SetPoint("BOTTOMRIGHT", -(f:GetWidth() * 0.12), f:GetWidth() * 0.12) end
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:SetScript("OnMouseDown", function(_, btn)
        if btn ~= "LeftButton" or M.db.locked then return end
        local cx, cy = GetCursorPosition()
        local sc = f:GetEffectiveScale()
        grip.sx, grip.sy, grip.size, grip.scale = cx / sc, cy / sc, f:GetWidth(), sc
        grip:SetScript("OnUpdate", function()
            local x, y = GetCursorPosition()
            local dx, dy = x / grip.scale - grip.sx, grip.sy - y / grip.scale
            local size = math.max(MIN_SIZE, math.min(MAX_SIZE, math.floor(grip.size + math.max(dx, dy) + 0.5)))
            if size ~= M.db.miniSize then
                M.db.miniSize = size
                UI:ApplyMini()
            end
        end)
    end)
    grip:SetScript("OnMouseUp", function() grip:SetScript("OnUpdate", nil) end)
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
            root:CreateDivider()
            root:CreateCheckbox("Quest areas", function() return M.db.overlays end, function() UI:ToggleOverlays() end)
            root:CreateCheckbox("Quest givers", function() return M.db.avail end, function() UI:ToggleGivers() end)
            root:CreateCheckbox("Direction arrow", function() return M.db.arrow end, function() M.Arrow:Toggle() end)
            root:CreateCheckbox("Coordinates and N marker", function() return M.db.miniCoords end,
                function() M.db.miniCoords = not M.db.miniCoords end)
            root:CreateCheckbox("Lock window, minimap and arrow", function() return M.db.locked end,
                function() M.db.locked = not M.db.locked end)
            root:CreateDivider()
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

    local acc = 0
    f:SetScript("OnUpdate", function(_, dt)
        acc = acc + dt
        if acc < 0.2 then return end
        acc = 0
        local zone = C_Map.GetBestMapForUnit("player")
        if not zone then return end
        local target = UI.continentOf(zone) or zone
        if c.mapID ~= target then
            c:SetMap(target)
            c:SetZoom(M.db.miniZoom)
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
    end)
    f:SetShown(M.db.mini)
end

-- Size and zoom from settings (live).
function UI:ApplyMini()
    local mini = self.mini
    local s = M.db.miniSize
    mini.frame:SetSize(s, s)
    mini.grab:SetWidth(s - 30)
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
