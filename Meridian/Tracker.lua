-- Quest list panel: toggle each quest's overlay, click to center on it (shift-click: set arrow target), hover for objectives.
local ADDON, M = ...

local Tracker = {}
M.Tracker = Tracker

local ROW_H, MAX_ROWS = 18, 22

function Tracker:Create(host, canvas, overlay)
    self.canvas, self.overlay = canvas, overlay
    local p = CreateFrame("Frame", nil, host)
    p:SetWidth(200)
    p:SetPoint("TOPRIGHT", host.content, "TOPRIGHT", 0, 0)
    p:SetPoint("BOTTOMRIGHT", host.content, "BOTTOMRIGHT", 0, 0)
    p.header = p:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    p.header:SetPoint("TOPLEFT", 8, -7)
    p.bg = p:CreateTexture(nil, "BACKGROUND")
    p.bg:SetAllPoints()
    p.bg:SetColorTexture(0.03, 0.03, 0.04, 0.9)
    p:SetShown(M.db.tracker)
    self.panel, self.rows = p, {}

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

local function showTip(row)
    GameTooltip:SetOwner(row, "ANCHOR_LEFT")
    GameTooltip:SetText(row.title, 1, 1, 1)
    for _, o in ipairs(C_QuestLog.GetQuestObjectives(row.questID) or {}) do
        if o.text and o.text ~= "" then
            if o.finished then GameTooltip:AddLine(o.text, 0.5, 0.5, 0.5) else GameTooltip:AddLine(o.text, 1, 0.82, 0) end
        end
    end
    GameTooltip:AddLine("Shift-click: point arrow (and Blizzard's marker). Ctrl-click: focus.", 0.6, 0.6, 0.6, true)
    if not Tracker.overlay.questPos[row.questID] then
        GameTooltip:AddLine("No known location on this map", 1, 0.3, 0.3)
    end
    GameTooltip:Show()
end

function Tracker:Row(i)
    local r = self.rows[i]
    if r then return r end
    r = CreateFrame("Button", nil, self.panel)
    r:SetHeight(ROW_H)
    r:SetPoint("TOPLEFT", 2, -24 - (i - 1) * ROW_H)
    r:SetPoint("RIGHT", -2, 0)
    r.check = CreateFrame("CheckButton", nil, r, "UICheckButtonTemplate")
    r.check:SetSize(18, 18)
    r.check:SetPoint("LEFT")
    r.check:SetScript("OnClick", function(s)
        M.db.hidden[r.questID] = (not s:GetChecked()) or nil
        M.UI:RefreshAll()
    end)
    r.swatch = r:CreateTexture(nil, "ARTWORK")
    r.swatch:SetSize(8, 12)
    r.swatch:SetPoint("LEFT", r.check, "RIGHT", 0, 0)
    r.text = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    r.text:SetPoint("LEFT", r.swatch, "RIGHT", 4, 0)
    r.text:SetPoint("RIGHT")
    r.text:SetJustifyH("LEFT")
    r.text:SetWordWrap(false)
    r:SetScript("OnEnter", function(s)
        showTip(s)
        Tracker.overlay:SetHighlight({ [s.questID] = true })
    end)
    r:SetScript("OnLeave", function()
        GameTooltip:Hide()
        Tracker.overlay:SetHighlight(nil)
    end)
    r:SetScript("OnClick", function()
        if IsShiftKeyDown() then
            M.db.target = (M.db.target ~= r.questID) and r.questID or nil
            M.Way:SetActive(nil)
            M.Arrow.areas = nil
            Tracker:SuperTrack(M.db.target)
            M:Print(M.db.target and ("Arrow target: " .. r.title) or "Arrow target: nearest quest")
        elseif IsControlKeyDown() then
            M.db.focus = (M.db.focus ~= r.questID) and r.questID or nil
            M:Print(M.db.focus and ("Focus: " .. r.title) or "Focus off")
            M.UI:RefreshAll()
        else
            Tracker:Focus(r.questID)
        end
    end)
    self.rows[i] = r
    return r
end

-- Keep Blizzard's own super-tracked quest (on-screen arrow and marker) in step with our arrow target.
function Tracker:SuperTrack(questID)
    if not (M.db.superTrack and C_SuperTrack and C_SuperTrack.SetSuperTrackedQuestID) then return end
    C_SuperTrack.SetSuperTrackedQuestID(questID or 0)
end

function Tracker:Focus(questID)
    local pos = self.overlay.questPos[questID]
    if not pos then return M:Print("No known location for that quest on this map.") end
    local c = self.canvas
    if c.zoom < 1 then c:SetZoom(1) end
    c:CenterOnCanvas(pos[1], pos[2])
end

function Tracker:Refresh()
    if not self.panel:IsShown() then return end
    local n = 0
    for i = 1, C_QuestLog.GetNumQuestLogEntries() do
        local info = C_QuestLog.GetInfo(i)
        if info and not info.isHeader and info.questID and n < MAX_ROWS then
            n = n + 1
            local r = self:Row(n)
            r.questID, r.title = info.questID, info.title or ("Quest " .. info.questID)
            r.text:SetText((M.db.focus == info.questID and "> " or "") .. r.title)
            r.swatch:SetColorTexture(M.Overlay.color(info.questID))
            r.check:SetChecked(not M.db.hidden[info.questID])
            r:Show()
        end
    end
    for i = n + 1, #self.rows do self.rows[i]:Hide() end
    self.panel.header:SetText("Quests  |cff888888" .. n .. "|r")
end
