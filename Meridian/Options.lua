-- Options page. Registers with the Settings API when present, else the legacy Interface Options list,
-- else opens as its own window. The control list is data-driven (OPTIONS below); every change is saved to
-- MeridianDB and applied live through UI:ApplySettings.
local ADDON, M = ...
local L = M.L

local Options = {}
M.Options = Options

local COL_W, ROW_H = 300, 30

-- kind: check | slider | choice | button. after: "map" refreshes pins, "rebuild" redraws art, "reload" needs /reload.
local OPTIONS = {
    { "header", L["Map"] },
    { "choice", "reveal", L["Map art"], { { "full", L["Fully revealed"] }, { "explored", L["Explored only"] } }, after = "rebuild" },
    { "slider", "opacity", L["Quest area opacity"], 0.2, 1, 0.05, "%.2f" },
    { "slider", "iconScale", L["Marker size"], 0.6, 2, 0.1, "%.1fx" },
    { "check", "blend", L["Blend zone edges on the continent map"], after = "rebuild" },
    { "check", "openView", L["Open zoomed in on me and pinned (otherwise keep the last view)"], after = "map" },
    { "check", "mapKey", L["Open Meridian with the world map key (M) instead of Blizzard's map"] },
    { "check", "pin", L["Pin the map to my character (follows you; dragging unpins)"], after = "map" },
    { "check", "overlays", L["Show quest areas"], after = "map" },
    { "check", "avail", L["Show quest givers"], after = "map" },
    { "check", "turnin", L["Show turn-in markers"], after = "map" },
    { "check", "dungeons", L["Dungeon maps (entrances on zone maps, multi-floor dungeon views)"], after = "map" },
    { "check", "pinCorpse", L["Show my corpse on the map and minimap"], after = "pins" },
    { "check", "autoCorpse", L["Point the arrow at my corpse when I die (cleared when I am alive)"], after = "pins" },
    { "check", "pinTransport", L["Boats and zeppelins (docks, for your faction)"], after = "pins" },
    { "check", "pinTaxi", L["Flight points (every flight master, for your faction)"], after = "pins" },
    { "slider", "greyRange", L["Hide grey quests below (levels)"], 0, 30, 1, "%d", after = "map" },
    { "check", "polestarRoute", L["Show the Polestar guide route as dots (needs Polestar)"], after = "route" },
    { "header", L["Extra pins (off by default)"] },
    { "check", "pinRare", L["Rares and treasures nearby (current zone)"], after = "pins" },
    { "check", "pinPoi", L["Points of interest"], after = "pins" },
    { "header", L["Accessibility"] },
    { "choice", "palette", L["Colours"], { { "default", L["Standard"] }, { "cb", L["Colour-blind safe"] } }, after = "map" },
    { "slider", "fontScale", L["Text size"], 0.9, 1.6, 0.1, "%.1fx", after = "map" },
    { "check", "contrast", L["High contrast (outlined text, white borders)"] },
    { "check", "controller", L["Controller support (experimental)"], after = "pad" },
    { "header", L["Window"] },
    { "slider", "scale", L["Window scale"], 0.7, 1.5, 0.05, "%.2fx" },
    { "slider", "alpha", L["Window opacity"], 0.3, 1, 0.05, "%.2f" },
    { "check", "locked", L["Lock window, minimap and arrow positions"] },
    { "button", L["Reset window position and size"], function() M.UI:ResetWindow() end },
    { "header", L["Arrow and waypoints"], newcol = true },
    { "check", "arrow", L["Direction arrow"] },
    { "choice", "arrowStyle", L["Arrow style"], { { 1, L["Classic"] }, { 2, L["Bold"] } } },
    { "slider", "wayArrive", L["Waypoint arrival distance (yds)"], 5, 60, 5, "%d" },
    { "check", "superTrack", L["Also super-track the picked quest (Blizzard arrow)"] },
    { "check", "blizzWay", L["Also set Blizzard's waypoint"] },
    { "check", "claimWay", L["Handle /way (needs reload; TomTom keeps it)"], after = "reload" },
    { "header", L["Minimap"] },
    { "check", "mini", L["Show minimap"] },
    { "slider", "miniSize", L["Minimap size"], 120, 600, 10, "%d", after = "mini" },
    { "slider", "miniZoom", L["Minimap zoom"], 0.5, 4, 0.1, "%.1f" },
    { "check", "miniCoords", L["Coordinates and N marker on minimap"] },
    { "check", "launcher", L["Button on the Blizzard minimap"], after = "launcher" },
    { "check", "miniRound", L["Round minimap (needs reload)"], after = "reload" },
}
Options.list = OPTIONS

local function apply(opt)
    if M.UI and M.UI.ApplySettings then M.UI:ApplySettings(opt.after) end
    if opt.after == "reload" then M:Print("That change needs /reload.") end
end

local function makeCheck(panel, opt, key, label)
    local b = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    b:SetSize(24, 24)
    b.label = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    b.label:SetPoint("TOPLEFT", b, "TOPRIGHT", 2, -5)
    b.label:SetWidth(COL_W - 44)
    b.label:SetJustifyH("LEFT")
    b.label:SetText(label)
    b:SetScript("OnClick", function(s)
        M.db[key] = s:GetChecked() and true or false
        apply(opt)
    end)
    b.Refresh = function(s) s:SetChecked(M.db[key]) end
    return b
end

local function makeSlider(panel, opt, key, label, lo, hi, step, fmt)
    local f = CreateFrame("Frame", nil, panel)
    f:SetSize(COL_W - 30, ROW_H)
    f.label = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.label:SetPoint("TOPLEFT")
    f.value = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.value:SetPoint("TOPRIGHT")
    f.label:SetText(label)
    local sl = CreateFrame("Slider", nil, f, "OptionsSliderTemplate")
    sl:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -14)
    sl:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -14)
    sl:SetMinMaxValues(lo, hi)
    sl:SetValueStep(step)
    if sl.SetObeyStepOnDrag then sl:SetObeyStepOnDrag(true) end
    if sl.Text then sl.Text:SetText("") end
    if sl.Low then sl.Low:SetText("") end
    if sl.High then sl.High:SetText("") end
    sl:SetScript("OnValueChanged", function(_, v)
        f.value:SetText(string.format(fmt, v))
        if f.syncing then return end
        M.db[key] = v
        apply(opt)
    end)
    f.slider = sl
    f.Refresh = function(s)
        s.syncing = true
        sl:SetValue(M.db[key] or lo)
        s.value:SetText(string.format(fmt, M.db[key] or lo))
        s.syncing = nil
    end
    return f
end

-- A button that cycles through its values; the current one is always spelled out in the label.
local function makeChoice(panel, opt, key, label, values)
    local b = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    b:SetSize(COL_W - 30, 22)
    local function text()
        for _, v in ipairs(values) do
            if v[1] == M.db[key] then return label .. ": " .. v[2] end
        end
        return label
    end
    b:SetScript("OnClick", function(s)
        local idx = 1
        for i, v in ipairs(values) do if v[1] == M.db[key] then idx = i end end
        M.db[key] = values[idx % #values + 1][1]
        s:SetText(text())
        apply(opt)
    end)
    b.Refresh = function(s) s:SetText(text()) end
    return b
end

local function makeButton(panel, label, fn)
    local b = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    b:SetSize(COL_W - 30, 22)
    b:SetText(label)
    b:SetScript("OnClick", fn)
    b.Refresh = function() end
    return b
end

function Options:Build()
    if self.panel then return self.panel end
    local p = CreateFrame("Frame", "MeridianOptionsPanel")
    p.name = "Meridian"
    p.OnCommit, p.OnDefault, p.OnRefresh = function() end, function() end, function() end
    self.panel, self.controls = p, {}

    local title = p:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Meridian")

    -- everything below the title scrolls, so a long page never runs off the bottom of the window
    local sf = CreateFrame("ScrollFrame", nil, p, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", 0, -44)
    sf:SetPoint("BOTTOMRIGHT", -28, 8)
    local content = CreateFrame("Frame", nil, sf)
    content:SetSize(2 * COL_W + 20, 600)
    sf:SetScrollChild(content)
    self.content = content

    -- two columns, filled top to bottom; a header with newcol starts the second one
    local col, y, deepest = 0, -6, 0
    for _, o in ipairs(OPTIONS) do
        local kind = o[1]
        local x = 16 + col * COL_W
        if kind == "header" then
            if o.newcol then col, y, x = 1, -6, 16 + COL_W end
            local fs = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
            fs:SetPoint("TOPLEFT", x, y)
            fs:SetText(o[2])
            y = y - 22
        else
            local w
            if kind == "check" then w = makeCheck(content, o, o[2], o[3]); y = y - 2
            elseif kind == "slider" then w = makeSlider(content, o, o[2], o[3], o[4], o[5], o[6], o[7])
            elseif kind == "choice" then w = makeChoice(content, o, o[2], o[3], o[4])
            elseif kind == "button" then w = makeButton(content, o[2], o[3]) end
            w:SetPoint("TOPLEFT", x + (kind == "check" and 0 or 4), y)
            self.controls[#self.controls + 1] = w
            local step = kind == "slider" and ROW_H + 6 or 28
            if kind == "check" and w.label then step = math.max(step, (w.label:GetStringHeight() or 0) + 10) end
            y = y - step
        end
        deepest = math.min(deepest, y)
    end
    content:SetHeight(-deepest + 16)
    y = deepest
    self.bottomY = y
    p:SetScript("OnShow", function() self:Refresh() end)
    return p
end

function Options:Refresh()
    for _, w in ipairs(self.controls or {}) do w:Refresh() end
end

-- Add rows after the fact (other modules extend the page: window scale, accessibility, pin types...).
function Options.Add(opt, atIndex)
    table.insert(OPTIONS, atIndex or (#OPTIONS + 1), opt)
end

function Options:Register()
    local p = self:Build()
    if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
        local ok, cat = pcall(Settings.RegisterCanvasLayoutCategory, p, "Meridian")
        if ok and cat then
            pcall(Settings.RegisterAddOnCategory, cat)
            self.category = cat
            return
        end
    end
    if InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(p)
        self.legacy = true
    end
end

-- Last resort when neither options UI exists: show the page in a window of our own.
function Options:OpenStandalone()
    local h = self.holder
    if not h then
        h = CreateFrame("Frame", "MeridianOptions", UIParent, "BackdropTemplate")
        M.Widgets.Panel(h)
        h:SetSize(2 * COL_W + 40, 560)
        h:SetPoint("CENTER")
        h:SetFrameStrata("DIALOG")
        h:SetMovable(true)
        h:EnableMouse(true)
        h:RegisterForDrag("LeftButton")
        h:SetScript("OnDragStart", h.StartMoving)
        h:SetScript("OnDragStop", h.StopMovingOrSizing)
        M.Widgets.IconButton(h, "close", "Close", nil, function() h:Hide() end, { size = 22, iconSize = 12 }):SetPoint("TOPRIGHT", -4, -4)
        tinsert(UISpecialFrames, "MeridianOptions")
        self.holder = h
        local p = self:Build()
        p:SetParent(h)
        p:SetAllPoints(h)
    end
    h:Show()
    self:Refresh()
end

function Options:Open()
    if self.category and Settings and Settings.OpenToCategory then
        local id = self.category.GetID and self.category:GetID() or self.category
        if pcall(Settings.OpenToCategory, id) then return end
    end
    if self.legacy and InterfaceOptionsFrame_OpenToCategory then
        InterfaceOptionsFrame_OpenToCategory(self.panel) -- the first call often lands on the wrong page
        InterfaceOptionsFrame_OpenToCategory(self.panel)
        return
    end
    self:OpenStandalone()
end
