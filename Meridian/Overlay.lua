-- Quest-area overlays. Providers return {questID=, x=, y=, radius=} in zone-normalized coords.
-- Areas are drawn additive so overlapping quests visibly brighten. One Overlay instance per Canvas.
local ADDON, M = ...

local Overlay = {}
Overlay.__index = Overlay
M.Overlay = Overlay

local DEFAULT_RADIUS = 0.03 -- fraction of map width; used for point-only data
local CIRCLE = "Interface\\CharacterFrame\\TempPortraitAlphaMaskSmall"

Overlay.providers = {}

-- Fallback provider: Blizzard quest POIs. Point data only, so draw a fixed-size area.
Overlay.providers.blizzard = function(uiMapID)
    local out = {}
    for _, q in ipairs(C_QuestLog.GetQuestsOnMap(uiMapID) or {}) do
        out[#out + 1] = { questID = q.questID, x = q.x, y = q.y, radius = DEFAULT_RADIUS }
    end
    return out
end

-- Stable per-quest hue so each quest's area is distinguishable.
local function color(questID)
    local h = (questID * 0.61803398875) % 1
    local i, f = math.floor(h * 6), h * 6 - math.floor(h * 6)
    local q, t = 1 - f, f
    local r, g, b = ({1, q, 0, 0, t, 1})[i % 6 + 1], ({t, 1, 1, q, 0, 0})[i % 6 + 1], ({0, 0, t, 1, 1, q})[i % 6 + 1]
    return r, g, b
end
Overlay.color = color

function Overlay:New(canvas)
    local o = setmetatable({ canvas = canvas, pool = {}, active = {}, questPos = {}, areas = {}, markerPool = {}, markers = {} }, Overlay)
    local prev = canvas.OnChanged
    canvas.OnChanged = function(...) if prev then prev(...) end; o:Rescale() end
    return o
end

local MAX_MARKERS = 500

-- Giver marker: a frame so it can counter-scale and take a tooltip.
function Overlay:AcquireMarker()
    local m = table.remove(self.markerPool)
    if not m then
        m = CreateFrame("Frame", nil, self.canvas.pinLayer)
        m:SetSize(14, 14)
        m:EnableMouse(true)
        m.tex = m:CreateTexture(nil, "OVERLAY")
        m.tex:SetAllPoints()
        m.tex:SetTexture("Interface\\GossipFrame\\AvailableQuestIcon")
        m:SetScript("OnEnter", function(s)
            GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
            GameTooltip:SetText(s.name or "Quest", 1, 0.82, 0)
            if s.level then GameTooltip:AddLine("Level " .. s.level, 1, 1, 1) end
            GameTooltip:Show()
        end)
        m:SetScript("OnLeave", GameTooltip_Hide)
    end
    m:SetFrameLevel(self.canvas.pinLayer:GetFrameLevel() + 10)
    m:Show()
    return m
end

function Overlay:Rescale()
    local s = 1 / self.canvas.zoom
    for _, m in ipairs(self.markers) do
        m:SetScale(s)
        m:ClearAllPoints()
        m:SetPoint("CENTER", self.canvas.pinLayer, "TOPLEFT", m.px / s, -m.py / s)
    end
end

function Overlay:Acquire()
    local p = table.remove(self.pool)
    if not p then
        p = self.canvas.pinLayer:CreateTexture(nil, "ARTWORK")
        p:SetTexture(CIRCLE)
        p:SetBlendMode("ADD")
        if self.canvas.mask then p:AddMaskTexture(self.canvas.mask) end
    end
    p:Show()
    return p
end

function Overlay:Clear()
    for _, p in ipairs(self.active) do p:Hide(); self.pool[#self.pool + 1] = p end
    wipe(self.active)
    wipe(self.questPos)
    for _, m in ipairs(self.markers) do m:Hide(); self.markerPool[#self.markerPool + 1] = m end
    wipe(self.markers)
    wipe(self.areas)
end

function Overlay:Refresh()
    local c = self.canvas
    if not c.mapID then return end
    self:Clear()
    if not M.db.overlays then return self:RefreshGivers() end
    -- Prefer real quest areas (QuestieDB); fall back to Blizzard's single-point markers.
    local useDB = M.Data:Available()
    for zoneID, rect in pairs(c.zones) do
        local list = useDB and M.Data:Provider(zoneID) or self.providers.blizzard(zoneID)
        for _, a in ipairs(list) do
            local px, py = c:ZoneToCanvas(zoneID, a.x, a.y)
            if not self.questPos[a.questID] then self.questPos[a.questID] = { px, py } end
            self.areas[#self.areas + 1] = { questID = a.questID, zone = zoneID, x = a.x, y = a.y }
            if not M.db.hidden[a.questID] then
                local p = self:Acquire()
                local r, g, b = color(a.questID)
                p:SetVertexColor(r, g, b, M.db.overlayAlpha)
                local d = a.radius * 2 * math.abs(rect.w)
                p:SetSize(d, d)
                c:PlacePinAt(p, px, py)
                self.active[#self.active + 1] = p
            end
        end
    end
    self:RefreshGivers()
end

-- Quest-giver markers for quests the player could accept now (needs the QuestieDB starter index).
function Overlay:RefreshGivers()
    if not (M.db.avail and M.Data:Available()) then return end
    if not M.Data.starters then
        if not M.Data.building then
            M:Print("Indexing quest givers...")
            M.Data:BuildStarters(function() M.UI:RefreshAll() end)
        end
        return
    end
    local c, state = self.canvas, M.Data:PlayerState()
    for zoneID in pairs(c.zones) do
        for _, g in ipairs(M.Data:Available(zoneID, state)) do
            if #self.markers >= MAX_MARKERS then return self:Rescale() end
            local m = self:AcquireMarker()
            m.px, m.py = c:ZoneToCanvas(zoneID, g.x, g.y)
            m.name, m.level = g.name, g.level
            self.markers[#self.markers + 1] = m
        end
    end
    self:Rescale()
end
