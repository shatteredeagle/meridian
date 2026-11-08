-- Launcher button on Blizzard's minimap: left-click toggles the map, right-click opens options, drag moves it around the edge.
local ADDON, M = ...
local L = M.L

local Launcher = {}
M.Launcher = Launcher

local Math = M.Math

function Launcher:Place()
    local b, mm = self.button, _G.Minimap
    if not (b and mm) then return end
    local r = mm:GetWidth() / 2 + 6
    local x, y = Math.edgePos(M.db.launcherAngle, r)
    b:ClearAllPoints()
    b:SetPoint("CENTER", mm, "CENTER", x, y)
end

function Launcher:Create()
    local mm = _G.Minimap
    if self.button or not mm or not M.db.launcher then return end
    local b = CreateFrame("Button", "MeridianLauncher", mm)
    b:SetSize(31, 31)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(8)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:RegisterForDrag("LeftButton")
    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetSize(20, 20)
    bg:SetPoint("CENTER")
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetSize(17, 17)
    icon:SetPoint("CENTER")
    icon:SetTexture("Interface\\AddOns\\Meridian\\Media\\icons\\continent")
    icon:SetVertexColor(1, 0.82, 0.2)
    local border = b:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    b:SetScript("OnClick", function(_, btn)
        if btn == "RightButton" then M.Options:Open() else M.UI:Toggle() end
    end)
    b:SetScript("OnEnter", function(s)
        GameTooltip:SetOwner(s, "ANCHOR_LEFT")
        GameTooltip:SetText("Meridian", 1, 1, 1)
        GameTooltip:AddLine(L["Left-click: toggle map"], 0.75, 0.75, 0.75)
        GameTooltip:AddLine(L["Right-click: options"], 0.75, 0.75, 0.75)
        GameTooltip:AddLine(L["Drag: move this button"], 0.75, 0.75, 0.75)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:SetScript("OnDragStart", function(s)
        s:SetScript("OnUpdate", function()
            local scale = mm:GetEffectiveScale()
            local cx, cy = GetCursorPosition()
            local mx, my = mm:GetCenter()
            M.db.launcherAngle = Math.angleTo(cx / scale - mx, cy / scale - my)
            self:Place()
        end)
    end)
    b:SetScript("OnDragStop", function(s) s:SetScript("OnUpdate", nil) end)
    self.button = b
    self:Place()
end

function Launcher:Apply()
    if M.db.launcher then
        if self.button then self.button:Show(); self:Place() else self:Create() end
    elseif self.button then
        self.button:Hide()
    end
end
