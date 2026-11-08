-- Small flat widgets: icon buttons with toggle state, separators, flat dark panel backdrop.
local ADDON, M = ...

local W = {}
M.Widgets = W

local ICONS = "Interface\\AddOns\\Meridian\\Media\\icons\\"
local WHITE = "Interface\\Buttons\\WHITE8X8"
local IDLE, HOVER, ACTIVE = { 0.74, 0.76, 0.8 }, { 1, 1, 1 }, { 1, 0.82, 0.2 }

W.colors = { bg = { 0.06, 0.06, 0.07, 0.96 }, edge = { 0.26, 0.26, 0.3, 1 }, accent = ACTIVE }

function W.Panel(f)
    f:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    f:SetBackdropColor(unpack(W.colors.bg))
    f:SetBackdropBorderColor(unpack(W.colors.edge))
end

local function paint(b)
    local c = b.hover and HOVER or (b.active and ACTIVE or IDLE)
    b.icon:SetVertexColor(c[1], c[2], c[3])
    b.bg:SetAlpha(b.hover and 0.14 or 0)
    b.bar:SetShown(b.active and b.toggle)
end

-- opts: toggle (bool), state (fn -> bool, read for the tooltip), size, iconSize
function W.IconButton(parent, icon, title, desc, onClick, opts)
    opts = opts or {}
    local b = CreateFrame("Button", nil, parent)
    local size = opts.size or 26
    b:SetSize(size, size)
    b.toggle = opts.toggle
    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetAllPoints()
    b.bg:SetColorTexture(1, 1, 1, 1)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    local isz = opts.iconSize or math.floor(size * 0.7)
    b.icon:SetSize(isz, isz)
    b.icon:SetPoint("CENTER")
    b.icon:SetTexture(ICONS .. icon)
    b.bar = b:CreateTexture(nil, "OVERLAY")
    b.bar:SetColorTexture(ACTIVE[1], ACTIVE[2], ACTIVE[3], 1)
    b.bar:SetPoint("BOTTOMLEFT", 4, 0)
    b.bar:SetPoint("BOTTOMRIGHT", -4, 0)
    b.bar:SetHeight(2)

    function b:SetActive(v) self.active = v and true or false; paint(self) end
    b:SetScript("OnEnter", function(s)
        s.hover = true
        paint(s)
        GameTooltip:SetOwner(s, "ANCHOR_BOTTOM")
        GameTooltip:SetText(title, 1, 1, 1)
        if desc then GameTooltip:AddLine(desc, 0.75, 0.75, 0.75, true) end
        if opts.toggle and opts.state then
            local on = opts.state()
            GameTooltip:AddLine(on and "On" or "Off", on and 0.4 or 0.6, on and 1 or 0.6, on and 0.4 or 0.6)
        end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function(s) s.hover = nil; paint(s); GameTooltip:Hide() end)
    b:SetScript("OnClick", function(s, ...)
        onClick(s, ...)
        if s.hover and s:GetScript("OnEnter") then s:GetScript("OnEnter")(s) end -- refresh tooltip state
    end)
    paint(b)
    return b
end

function W.Separator(parent)
    local t = parent:CreateTexture(nil, "ARTWORK")
    t:SetSize(1, 16)
    t:SetColorTexture(1, 1, 1, 0.16)
    return t
end
