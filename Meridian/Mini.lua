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
    grab:SetScript("OnDragStart", function() f:StartMoving() end)
    grab:SetScript("OnDragStop", function()
        f:StopMovingOrSizing()
        local point, _, rel, x, y = f:GetPoint()
        M.db.miniPos = { point, rel, x, y }
    end)
    grab.tex = grab:CreateTexture(nil, "OVERLAY")
    grab.tex:SetAllPoints()
    grab.tex:SetColorTexture(1, 1, 1, 0.12)
    local re = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    re:SetSize(22, 14)
    re:SetPoint("TOPRIGHT", -2, -2)
    re:SetText("@")
    re:SetScript("OnClick", function() mini.follow = true end)
    c.view:HookScript("OnMouseDown", function() mini.follow = false end)

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
        if mini.follow then
            local px, py = UI:PlayerCanvasPos(c)
            if px then c:CenterOnCanvas(px, py) end
        end
    end)
    f:SetShown(M.db.mini)
end

function UI:ToggleMini()
    M.db.mini = not M.db.mini
    self.mini.frame:SetShown(M.db.mini)
    if M.db.mini then self.mini.follow = true; self:RefreshAll() end
end
