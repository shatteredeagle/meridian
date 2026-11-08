-- Small flat widgets: icon buttons with toggle state, separators, flat dark panel backdrop.
local ADDON, M = ...

local W = {}
M.Widgets = W

local ICONS = "Interface\\AddOns\\Meridian\\Media\\icons\\"
local WHITE = "Interface\\Buttons\\WHITE8X8"
local IDLE, HOVER, ACTIVE = { 0.74, 0.76, 0.8 }, { 1, 1, 1 }, { 1, 0.82, 0.2 }

W.colors = { bg = { 0.06, 0.06, 0.07, 0.96 }, edge = { 0.26, 0.26, 0.3, 1 }, accent = ACTIVE }
local NORMAL_COLORS = { bg = { 0.06, 0.06, 0.07, 0.96 }, edge = { 0.26, 0.26, 0.3, 1 }, idle = { 0.74, 0.76, 0.8 } }
local CONTRAST_COLORS = { bg = { 0, 0, 0, 1 }, edge = { 1, 1, 1, 1 }, idle = { 0.95, 0.95, 1 } }

W.panels, W.buttons = {}, {}

-- Fonts the addon's text uses: base size follows the "font scale" option, outlined in high-contrast mode.
local FONTS = { MeridianFontGold = { 1, 0.82, 0 }, MeridianFontWhite = { 1, 1, 1 } }
function W.ApplyFonts()
    local file, size = GameFontNormalSmall:GetFont()
    local scale = M.db and M.db.fontScale or 1
    local flags = (M.db and M.db.contrast) and "OUTLINE" or ""
    for name, c in pairs(FONTS) do
        local f = _G[name] or CreateFont(name)
        f:SetFont(file, math.floor(size * scale + 0.5), flags)
        f:SetTextColor(c[1], c[2], c[3])
    end
    W.fontSize = size * scale
end

-- High contrast: opaque black panels, white borders, brighter idle icons.
function W.ApplyContrast()
    local on = M.db and M.db.contrast
    local set = on and CONTRAST_COLORS or NORMAL_COLORS
    W.colors.bg, W.colors.edge = set.bg, set.edge
    IDLE[1], IDLE[2], IDLE[3] = set.idle[1], set.idle[2], set.idle[3]
    for _, f in ipairs(W.panels) do
        f:SetBackdropColor(unpack(W.colors.bg))
        f:SetBackdropBorderColor(unpack(W.colors.edge))
    end
    for _, b in ipairs(W.buttons) do W.paint(b) end
    W.ApplyFonts()
end

function W.Panel(f)
    W.panels[#W.panels + 1] = f
    f:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    f:SetBackdropColor(unpack(W.colors.bg))
    f:SetBackdropBorderColor(unpack(W.colors.edge))
end

-- Toggle state is shown three ways besides colour: the underline bar, a check mark and the tooltip's On/Off.
local function paint(b)
    local c = b.hover and HOVER or (b.active and ACTIVE or IDLE)
    b.icon:SetVertexColor(c[1], c[2], c[3])
    b.bg:SetAlpha(b.hover and 0.14 or 0)
    b.bar:SetShown(b.active and b.toggle)
    b.check:SetShown(b.active and b.toggle)
end
W.paint = paint

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
    b.check = b:CreateTexture(nil, "OVERLAY")
    b.check:SetSize(9, 9)
    b.check:SetPoint("TOPRIGHT", -1, -1)
    b.check:SetTexture(ICONS .. "check")
    b.check:SetVertexColor(ACTIVE[1], ACTIVE[2], ACTIVE[3])
    W.buttons[#W.buttons + 1] = b

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

-- A one-line box with the text pre-selected, so Ctrl-C copies it (WoW has no clipboard API).
-- Shift-click paths use ChatFrame_OpenChat instead. Closes on Enter, Escape or focus loss.
function W.CopyBox(text, anchor)
    local box = W.copyBox
    if not box then
        box = CreateFrame("Frame", "MeridianCopyBox", UIParent, "BackdropTemplate")
        W.Panel(box)
        box:SetSize(280, 46)
        box:SetFrameStrata("FULLSCREEN_DIALOG")
        box.hint = box:CreateFontString(nil, "OVERLAY", "MeridianFontWhite")
        box.hint:SetPoint("TOPLEFT", 8, -6)
        box.hint:SetText("Ctrl-C to copy, then Enter")
        box.edit = CreateFrame("EditBox", nil, box)
        box.edit:SetFontObject("ChatFontNormal")
        box.edit:SetAutoFocus(false)
        box.edit:SetPoint("TOPLEFT", 8, -20)
        box.edit:SetPoint("BOTTOMRIGHT", -8, 4)
        local function close() box:Hide() end
        box.edit:SetScript("OnEscapePressed", close)
        box.edit:SetScript("OnEnterPressed", close)
        box.edit:SetScript("OnEditFocusLost", close)
        W.copyBox = box
    end
    box:ClearAllPoints()
    box:SetPoint("BOTTOM", anchor or UIParent, "TOP", 0, 4)
    box:Show()
    box.edit:SetText(text)
    box.edit:SetFocus()
    box.edit:HighlightText()
end

-- Put text into the chat input (shift-click convention); falls back to the copy box.
function W.ToChat(text, anchor)
    if ChatFrame_OpenChat then ChatFrame_OpenChat(text) else W.CopyBox(text, anchor) end
end
