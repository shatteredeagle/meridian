-- Direction arrow to the nearest (or shift-click targeted) quest area on the player's continent.
local ADDON, M = ...

local Arrow = {}
M.Arrow = Arrow

local Math = M.Math

function Arrow:Create(overlay)
    local f = CreateFrame("Frame", "MeridianArrow", UIParent)
    f:SetSize(64, 64)
    if M.db.arrowPos then
        f:SetPoint(M.db.arrowPos[1], UIParent, M.db.arrowPos[2], M.db.arrowPos[3], M.db.arrowPos[4])
    else
        f:SetPoint("TOP", 0, -120)
    end
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function()
        f:StopMovingOrSizing()
        local point, _, rel, x, y = f:GetPoint()
        M.db.arrowPos = { point, rel, x, y }
    end)
    f.tex = f:CreateTexture(nil, "ARTWORK")
    f.tex:SetAllPoints()
    f.tex:SetTexture("Interface\\Minimap\\MinimapArrow")
    f.text = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.text:SetPoint("TOP", f, "BOTTOM", 0, -2)
    self.frame = f
    f:SetShown(M.db.arrow)

    local acc, since = 0, 0
    f:SetScript("OnUpdate", function(_, dt)
        acc, since = acc + dt, since + dt
        if acc < 0.1 then return end
        acc = 0
        if since > 5 then since = 0; self.areas = nil end -- recompute areas every few seconds
        self:Update()
    end)
    local ev = CreateFrame("Frame")
    ev:RegisterEvent("QUEST_LOG_UPDATE")
    ev:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    ev:SetScript("OnEvent", function() self.areas = nil end)
end

-- Areas of all logged quests on the player's continent: {questID, title, zone, x, y}.
function Arrow:CollectAreas(continent)
    local out = {}
    if not M.Data:Available() then return out end
    local zones = C_Map.GetMapChildrenInfo(continent, Enum.UIMapType.Zone, true) or {}
    for _, q in ipairs(M.Data:LogQuests()) do
        if not M.db.hidden[q.questID] then
            local byZone = M.Data:QuestAreasAll(q.questID)
            for _, z in ipairs(zones) do
                for _, a in ipairs(byZone[z.mapID] or {}) do
                    out[#out + 1] = { questID = q.questID, title = q.title, zone = z.mapID, x = a.x, y = a.y }
                end
            end
        end
    end
    return out
end

function Arrow:Update()
    local f = self.frame
    local zone = C_Map.GetBestMapForUnit("player")
    local pp = zone and C_Map.GetPlayerMapPosition(zone, "player")
    local cont = zone and M.UI.continentOf(zone)
    if not (pp and cont) then return f.text:SetText("") end
    self.areas = self.areas or self:CollectAreas(cont)

    local px, py = pp:GetXY()
    local me, world = M.WorldPos(zone, px, py)
    if not me then return end
    -- map-axis orientation from this zone
    local p00, p10, p01 = M.WorldPos(zone, 0, 0), M.WorldPos(zone, 1, 0), M.WorldPos(zone, 0, 1)
    if not (p00 and p10 and p01) then return end
    local ax, sx, ay, sy = Math.worldAxes(p00, p10, p01)

    local best, bestD
    for _, a in ipairs(self.areas) do
        if not M.db.target or a.questID == M.db.target then
            local t, w = M.WorldPos(a.zone, a.x, a.y)
            if t and w == world then
                local dx, dy = (t[ax] - me[ax]) * sx, (t[ay] - me[ay]) * sy
                local d = math.sqrt(dx * dx + dy * dy)
                if not bestD or d < bestD then best, bestD = { a = a, dx = dx, dy = dy }, d end
            end
        end
    end
    if not best then
        f.tex:SetAlpha(0.3)
        return f.text:SetText("No quest area nearby")
    end
    f.tex:SetAlpha(1)
    f.tex:SetRotation(Math.wrap(Math.bearing(best.dx, best.dy) - (GetPlayerFacing() or 0)))
    f.text:SetFormattedText("%s\n%d yds", best.a.title or "Quest", bestD)
end

function Arrow:Toggle()
    M.db.arrow = not M.db.arrow
    self.frame:SetShown(M.db.arrow)
    self.areas = nil
    if M.UI.SyncToolbar then M.UI:SyncToolbar() end
end
