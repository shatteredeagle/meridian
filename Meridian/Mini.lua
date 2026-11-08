-- Optional minimap: a small pan/zoom map that follows the player. Drag to pan (stops following), "@" re-follows.
local ADDON, M = ...
local UI = M.UI

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

    local c = M.Canvas:New(f, { round = M.db.miniRound })
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
    mini.grab = grab
    grab.tex = grab:CreateTexture(nil, "OVERLAY")
    grab.tex:SetAllPoints()
    grab.tex:SetColorTexture(1, 1, 1, 0.12)
    local re = M.Widgets.IconButton(f, "locate", "Follow me", "Re-center and keep following.", function() mini.follow = true end,
        { size = 18, iconSize = 12 })
    re:SetPoint("TOPRIGHT", -2, -2)
    c.view:HookScript("OnMouseDown", function() mini.follow = false end)

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
