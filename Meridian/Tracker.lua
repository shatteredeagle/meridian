-- Quest list panel: toggle each quest's overlay, click to center on it (shift-click: set arrow target), hover for objectives.
local ADDON, M = ...

local Tracker = {}
M.Tracker = Tracker

local function rowH() return math.max(18, math.floor((M.Widgets.fontSize or 11) + 7)) end
local SORTS = { "zone", "level", "distance", "log" }
local SORT_NAMES = { zone = "Zone", level = "Level", distance = "Distance", log = "Quest log" }

---------------------------------------------------------------------------------
-- Pure list logic (tested offline)
---------------------------------------------------------------------------------

-- "done/total" over an objective list (entries with text), or nil when the quest has none.
function Tracker.progress(objs)
    local done, total = 0, 0
    for _, o in ipairs(objs or {}) do
        if o.text and o.text ~= "" then
            total = total + 1
            if o.finished then done = done + 1 end
        end
    end
    if total == 0 then return nil end
    return done .. "/" .. total
end

-- Row text: level, title and, without relying on colour, "done" or the objective progress.
function Tracker.label(e)
    local s = (e.level and e.level > 0) and ("[" .. e.level .. "] " .. e.title) or e.title
    if e.complete then return s .. " - done" end
    if e.progress then return s .. "  " .. e.progress end
    return s
end

-- Order entries ({idx, title, level, zone, questID}). dist(questID) -> number|nil (nil sorts last).
function Tracker.sortEntries(list, mode, dist)
    local function tie(a, b) return a.idx < b.idx end
    local cmp
    if mode == "zone" then
        cmp = function(a, b)
            local za, zb = (a.zone or ""):lower(), (b.zone or ""):lower()
            if za ~= zb then return za < zb end
            if (a.level or 0) ~= (b.level or 0) then return (a.level or 0) < (b.level or 0) end
            return tie(a, b)
        end
    elseif mode == "level" then
        cmp = function(a, b)
            if (a.level or 0) ~= (b.level or 0) then return (a.level or 0) < (b.level or 0) end
            return tie(a, b)
        end
    elseif mode == "distance" then
        cmp = function(a, b)
            local da, db = dist and dist(a.questID) or math.huge, dist and dist(b.questID) or math.huge
            da, db = da or math.huge, db or math.huge
            if da ~= db then return da < db end
            return tie(a, b)
        end
    else
        cmp = tie
    end
    table.sort(list, cmp)
    return list
end

-- Flatten sorted entries into display rows; in zone mode each zone gets a header row and can be collapsed.
function Tracker.buildRows(list, mode, collapsed)
    local rows = {}
    if mode ~= "zone" then
        for _, e in ipairs(list) do rows[#rows + 1] = { entry = e } end
        return rows
    end
    local i = 1
    while i <= #list do
        local zone, j = list[i].zone or "Other", i
        while list[j + 1] and (list[j + 1].zone or "Other") == zone do j = j + 1 end
        local shut = collapsed and collapsed[zone] and true or false
        rows[#rows + 1] = { header = zone, count = j - i + 1, collapsed = shut }
        if not shut then
            for k = i, j do rows[#rows + 1] = { entry = list[k] } end
        end
        i = j + 1
    end
    return rows
end

function Tracker:Create(host, canvas, overlay)
    self.canvas, self.overlay = canvas, overlay
    local p = CreateFrame("Frame", nil, host)
    p:SetWidth(230)
    p:SetPoint("TOPRIGHT", host.content, "TOPRIGHT", 0, 0)
    p:SetPoint("BOTTOMRIGHT", host.content, "BOTTOMRIGHT", 0, 0)
    p.header = p:CreateFontString(nil, "OVERLAY", "MeridianFontGold")
    p.header:SetPoint("TOPLEFT", 8, -7)
    p.bg = p:CreateTexture(nil, "BACKGROUND")
    p.bg:SetAllPoints()
    p.bg:SetColorTexture(0.03, 0.03, 0.04, 0.9)
    p:SetShown(M.db.tracker)
    self.panel, self.rows = p, {}

    -- sort mode (cycles) and mouse-wheel scrolling
    local sort = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    sort:SetSize(110, 18)
    sort:SetPoint("TOPRIGHT", -4, -4)
    sort:SetScript("OnClick", function()
        local idx = 1
        for i, m in ipairs(SORTS) do if m == M.db.sortMode then idx = i end end
        M.db.sortMode = SORTS[idx % #SORTS + 1]
        self.scroll = 0
        self:Refresh()
    end)
    sort:SetScript("OnEnter", function(s)
        GameTooltip:SetOwner(s, "ANCHOR_LEFT")
        GameTooltip:SetText("Sort quests", 1, 1, 1)
        GameTooltip:AddLine("Click to cycle: zone, level, distance (on this map), quest log order.", 0.75, 0.75, 0.75, true)
        GameTooltip:Show()
    end)
    sort:SetScript("OnLeave", function() GameTooltip:Hide() end)
    self.sortButton = sort
    self.scroll = 0
    p:EnableMouseWheel(true)
    p:SetScript("OnMouseWheel", function(_, delta)
        self.scroll = math.max(0, (self.scroll or 0) - delta * 3)
        self:Refresh()
    end)

    local sl = CreateFrame("Slider", nil, p, "OptionsSliderTemplate")
    sl:SetPoint("BOTTOMLEFT", 10, 22)
    sl:SetPoint("BOTTOMRIGHT", -10, 22)
    sl:SetMinMaxValues(0.2, 1)
    sl:SetValueStep(0.05)
    sl:SetObeyStepOnDrag(true)
    sl:SetValue(M.db.opacity)
    if sl.Text then sl.Text:SetText("Overlay opacity") end
    if sl.Low then sl.Low:SetText("") end
    if sl.High then sl.High:SetText("") end
    sl:SetScript("OnValueChanged", function(_, v)
        if self.syncing then return end
        M.db.opacity = v
        M.UI:ApplySettings()
    end)
    self.slider = sl
end

-- Keep the panel slider in step when opacity changes elsewhere (options page).
function Tracker:SyncSlider()
    if not self.slider then return end
    self.syncing = true
    self.slider:SetValue(M.db.opacity)
    self.syncing = nil
end

-- Names of party members who share this quest.
local function partyOn(questID)
    local out = {}
    if not (IsInGroup and IsInGroup() and C_QuestLog.IsUnitOnQuest) then return out end
    for i = 1, 4 do
        local unit = "party" .. i
        if UnitExists(unit) and C_QuestLog.IsUnitOnQuest(unit, questID) then out[#out + 1] = UnitName(unit) end
    end
    return out
end

local function showTip(row)
    local e = row.entry
    GameTooltip:SetOwner(row, "ANCHOR_LEFT")
    GameTooltip:SetText(e.title, 1, 1, 1)
    local sub = {}
    if e.level and e.level > 0 then sub[#sub + 1] = "Level " .. e.level end
    if e.zone then sub[#sub + 1] = e.zone end
    if e.complete then sub[#sub + 1] = "Ready to turn in" end
    if #sub > 0 then GameTooltip:AddLine(table.concat(sub, "  -  "), 0.7, 0.7, 0.7) end
    for _, o in ipairs(C_QuestLog.GetQuestObjectives(e.questID) or {}) do
        if o.text and o.text ~= "" then
            if o.finished then GameTooltip:AddLine(o.text, 0.5, 0.5, 0.5) else GameTooltip:AddLine(o.text, 1, 0.82, 0) end
        end
    end
    local party = partyOn(e.questID)
    if #party > 0 then GameTooltip:AddLine("Party on this quest: " .. table.concat(party, ", "), 0.5, 0.8, 1, true) end
    if IsShiftKeyDown() then M.Tip.details(GameTooltip, e.questID, true) end
    GameTooltip:AddLine("Shift-click: point arrow (and Blizzard's marker). Ctrl-click: focus. Hold Shift: details.", 0.6, 0.6, 0.6, true)
    if not Tracker.overlay.questPos[e.questID] then
        GameTooltip:AddLine("No known location on this map", 1, 0.3, 0.3)
    end
    GameTooltip:Show()
    M.Tip.Track(function() showTip(row) end)
end

function Tracker:Row(i)
    local r = self.rows[i]
    if r then return r end
    r = CreateFrame("Button", nil, self.panel)
    r.check = CreateFrame("CheckButton", nil, r, "UICheckButtonTemplate")
    r.check:SetSize(18, 18)
    r.check:SetPoint("LEFT")
    r.check:SetScript("OnClick", function(s)
        M.db.hidden[r.entry.questID] = (not s:GetChecked()) or nil
        M.UI:RefreshAll()
    end)
    r.swatch = r:CreateTexture(nil, "ARTWORK")
    r.swatch:SetSize(8, 12)
    r.swatch:SetPoint("LEFT", r.check, "RIGHT", 0, 0)
    r.text = r:CreateFontString(nil, "OVERLAY", "MeridianFontGold")
    r.text:SetJustifyH("LEFT")
    r.text:SetWordWrap(false)
    r:SetScript("OnEnter", function(s)
        if s.header then return end
        showTip(s)
        Tracker.overlay:SetHighlight({ [s.entry.questID] = true })
    end)
    r:SetScript("OnLeave", function()
        M.Tip.Track(nil)
        GameTooltip:Hide()
        Tracker.overlay:SetHighlight(nil)
    end)
    r:SetScript("OnClick", function(s)
        if s.header then
            M.db.collapsed[s.header] = (not M.db.collapsed[s.header]) or nil
            return Tracker:Refresh()
        end
        local e = s.entry
        if IsShiftKeyDown() then
            M.db.target = (M.db.target ~= e.questID) and e.questID or nil
            M.Way:SetActive(nil)
            M.Arrow.areas = nil
            Tracker:SuperTrack(M.db.target)
            M:Print(M.db.target and ("Arrow target: " .. e.title) or "Arrow target: nearest quest")
        elseif IsControlKeyDown() then
            M.db.focus = (M.db.focus ~= e.questID) and e.questID or nil
            M:Print(M.db.focus and ("Focus: " .. e.title) or "Focus off")
            M.UI:RefreshAll()
        else
            Tracker:Focus(e.questID)
        end
    end)
    self.rows[i] = r
    return r
end

function Tracker:Focus(questID)
    local pos = self.overlay.questPos[questID]
    if not pos then return M:Print("No known location for that quest on this map.") end
    local c = self.canvas
    if c.zoom < 1 then c:SetZoom(1) end
    c:CenterOnCanvas(pos[1], pos[2])
end

-- Log quests as entries; zone comes from the log's own zone headers.
function Tracker:Entries()
    local list, zone = {}, nil
    for i = 1, C_QuestLog.GetNumQuestLogEntries() do
        local info = C_QuestLog.GetInfo(i)
        if info and info.isHeader then
            zone = info.title
        elseif info and info.questID then
            local objs = C_QuestLog.GetQuestObjectives(info.questID)
            list[#list + 1] = {
                idx = i, questID = info.questID, title = info.title or ("Quest " .. info.questID),
                level = info.level, zone = zone, complete = C_QuestLog.IsComplete(info.questID) and true or false,
                progress = Tracker.progress(objs),
            }
        end
    end
    return list
end

function Tracker:Refresh()
    if not self.panel:IsShown() then return end
    local mode = M.db.sortMode
    local list = self:Entries()
    local canvas, ppx, ppy = self.canvas
    if mode == "distance" then ppx, ppy = M.UI:PlayerCanvasPos(canvas) end
    Tracker.sortEntries(list, mode, ppx and function(id)
        local pos = self.overlay.questPos[id]
        return pos and math.sqrt((pos[1] - ppx) ^ 2 + (pos[2] - ppy) ^ 2) or nil
    end)
    local rows = Tracker.buildRows(list, mode, M.db.collapsed)
    self.sortButton:SetText("Sort: " .. (SORT_NAMES[mode] or mode))

    local visible = math.max(5, math.floor(((self.panel:GetHeight() or 0) - 24 - 52) / rowH()))
    self.scroll = math.max(0, math.min(self.scroll or 0, math.max(0, #rows - visible)))
    for slot = 1, visible do
        local item = rows[slot + self.scroll]
        if not item then
            if self.rows[slot] then self.rows[slot]:Hide() end
        else
            local r = self:Row(slot)
            r:SetHeight(rowH())
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", 2, -24 - (slot - 1) * rowH())
            r:SetPoint("RIGHT", -2, 0)
            r:Show()
            r.text:ClearAllPoints()
            if item.header then
                r.header, r.entry = item.header, nil
                r.check:Hide()
                r.swatch:Hide()
                r.text:SetPoint("LEFT", 4, 0)
                r.text:SetPoint("RIGHT")
                r.text:SetText((item.collapsed and "+ " or "- ") .. item.header .. "  (" .. item.count .. ")")
                r.text:SetTextColor(0.7, 0.7, 0.75)
            else
                local e = item.entry
                r.header, r.entry = nil, e
                r.check:Show()
                r.swatch:Show()
                r.text:SetPoint("LEFT", r.swatch, "RIGHT", 4, 0)
                r.text:SetPoint("RIGHT")
                r.swatch:SetColorTexture(M.Overlay.color(e.questID))
                r.check:SetChecked(not M.db.hidden[e.questID])
                r.text:SetText((M.db.focus == e.questID and "> " or "") .. Tracker.label(e))
                if e.complete then r.text:SetTextColor(0.5, 1, 0.5) else r.text:SetTextColor(1, 0.82, 0) end
            end
        end
    end
    for slot = visible + 1, #self.rows do self.rows[slot]:Hide() end
    self.panel.header:SetText("Quests  |cff888888" .. #list .. "|r")
end
