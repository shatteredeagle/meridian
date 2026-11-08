-- Quest-area overlays. Providers return {questID=, x=, y=, radius=} in zone-normalized coords.
-- Areas are drawn additive so overlapping quests visibly brighten. One Overlay instance per Canvas.
local ADDON, M = ...

local Overlay = {}
Overlay.__index = Overlay
M.Overlay = Overlay

local DEFAULT_RADIUS = 0.03 -- fraction of map width; used for point-only data
local CIRCLE = "Interface\\AddOns\\Meridian\\Media\\area" -- soft disc with a crisp rim, tinted per quest

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
    o:AttachHover()
    return o
end

local MAX_MARKERS = 500
local PINS = "Interface\\AddOns\\Meridian\\Media\\pins\\"
function Overlay.pin(name) return PINS .. name end

-- Marker sources add pins (givers, turn-ins, waypoints, ...) after the areas are drawn.
-- Each is fn(overlay, canvas) and must return at once when its feature is off, so unused modules cost nothing.
Overlay.sources = {}
function Overlay.RegisterSource(name, fn) Overlay.sources[#Overlay.sources + 1] = { name = name, fn = fn } end

-- Marker: a button so it can counter-scale, take a tooltip and be clicked.
function Overlay:AcquireMarker()
    local m = table.remove(self.markerPool)
    if not m then
        m = CreateFrame("Button", nil, self.canvas.pinLayer)
        m:RegisterForClicks("AnyUp")
        m.tex = m:CreateTexture(nil, "OVERLAY")
        m.tex:SetAllPoints()
        m:SetScript("OnEnter", function(s)
            self.markerHover = true
            local sp = s.spec
            GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
            GameTooltip:SetText(sp.title or "", sp.r or 1, sp.g or 0.82, sp.b or 0)
            for _, l in ipairs(sp.lines or {}) do GameTooltip:AddLine(l, 1, 1, 1, true) end
            if sp.hint then GameTooltip:AddLine(sp.hint, 0.6, 0.6, 0.6, true) end
            GameTooltip:Show()
        end)
        m:SetScript("OnLeave", function() self.markerHover = nil; GameTooltip:Hide() end)
        m:SetScript("OnClick", function(s, btn) if s.spec and s.spec.onClick then s.spec.onClick(s, btn) end end)
    end
    m:SetFrameLevel(self.canvas.pinLayer:GetFrameLevel() + 10)
    m:Show()
    return m
end

-- spec: x, y (zone-normalized), pin (texture name), size, r/g/b (tint, also the tooltip title colour),
-- title, lines, hint, onClick(marker, button).
function Overlay:AddMarker(zoneID, spec)
    if #self.markers >= MAX_MARKERS then return end
    local px, py = self.canvas:ZoneToCanvas(zoneID, spec.x, spec.y)
    if not px then return end
    local m = self:AcquireMarker()
    m.spec, m.px, m.py = spec, px, py
    m.base = spec.size or 16
    m.tex:SetTexture(PINS .. spec.pin)
    m.tex:SetVertexColor(spec.r or 1, spec.g or 1, spec.b or 1)
    self.markers[#self.markers + 1] = m
    return m
end

function Overlay:Rescale()
    local s = 1 / self.canvas.zoom
    local k = M.db.iconScale or 1
    for _, m in ipairs(self.markers) do
        m:SetSize(m.base, m.base)
        m:SetScale(s * k)
        m:ClearAllPoints()
        m:SetPoint("CENTER", self.canvas.pinLayer, "TOPLEFT", m.px / (s * k), -m.py / (s * k))
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
    if not M.db.overlays then return self:RefreshMarkers() end
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
                local d = a.radius * 2 * math.abs(rect.w)
                p.questID, p.px, p.py, p.r = a.questID, px, py, d / 2
                p:SetSize(d, d)
                c:PlacePinAt(p, px, py)
                self.active[#self.active + 1] = p
            end
        end
    end
    self:ApplyAlpha()
    self:RefreshMarkers()
end

function Overlay:RefreshMarkers()
    for _, src in ipairs(Overlay.sources) do src.fn(self, self.canvas) end
    self:Rescale()
end

-- Quest-giver markers for quests the player could accept now (needs the QuestieDB starter index).
local function giverSource(self, c)
    if not (M.db.avail and M.Data:Available()) then return end
    if not M.Data.starters then
        if not M.Data.building then
            M:Print("Indexing quest givers...")
            M.Data:BuildStarters(function() M.UI:RefreshAll() end)
        end
        return
    end
    local state = M.Data:PlayerState()
    for zoneID in pairs(c.zones) do
        for _, g in ipairs(M.Data:Available(zoneID, state)) do
            self:AddMarker(zoneID, { x = g.x, y = g.y, pin = "give", size = 16, r = 1, g = 0.85, b = 0.1,
                title = g.name or "Quest", lines = { "Level " .. (g.level or "?") }, kind = "give", questID = g.questID })
        end
    end
end
Overlay.RegisterSource("givers", giverSource)

-- Turn-in markers: green "?" at the finisher of every completed quest in the log.
local function turninSource(self, c)
    if not (M.db.turnin and M.Data:Available()) then return end
    for _, q in ipairs(M.Data:LogQuests()) do
        if q.complete then
            for zoneID in pairs(c.zones) do
                for _, p in ipairs(M.Data:QuestFinishers(q.questID)[zoneID] or {}) do
                    self:AddMarker(zoneID, { x = p[1], y = p[2], pin = "turnin", size = 18, r = 0.5, g = 1, b = 0.5,
                        title = q.title or "Quest", lines = { "Ready to turn in" }, kind = "turnin", questID = q.questID })
                end
            end
        end
    end
end
Overlay.RegisterSource("turnins", turninSource)


-- Tint and fade every pin. A highlighted quest (hover) is drawn bright, the rest are pushed back.
function Overlay:ApplyAlpha()
    local hl, base = self.highlight, M.db.opacity
    for _, p in ipairs(self.active) do
        local r, g, b = color(p.questID)
        local a = base
        if hl then a = hl[p.questID] and math.min(1, base * 1.35) or base * 0.3 end
        p:SetVertexColor(r, g, b, a)
    end
end

-- set: table {[questID]=true} or nil to clear.
function Overlay:SetHighlight(set)
    self.highlight = set
    self:ApplyAlpha()
end

-- Quests whose area contains the canvas point, smallest area first (so the topmost reads first).
function Overlay:QuestsAt(px, py)
    local hits = {}
    for _, p in ipairs(self.active) do
        local dx, dy = px - p.px, py - p.py
        if dx * dx + dy * dy <= p.r * p.r then hits[#hits + 1] = p end
    end
    table.sort(hits, function(a, b) return a.r < b.r end)
    local out, seen = {}, {}
    for _, p in ipairs(hits) do
        if not seen[p.questID] then seen[p.questID] = true; out[#out + 1] = p.questID end
    end
    return out
end

local function fillTip(ids)
    GameTooltip:ClearLines()
    if #ids > 1 then GameTooltip:AddLine(#ids .. " overlapping quests", 0.7, 0.7, 0.7) end
    for i, id in ipairs(ids) do
        local r, g, b = color(id)
        GameTooltip:AddLine(C_QuestLog.GetTitleForQuestID(id) or ("Quest " .. id), r, g, b)
        for _, o in ipairs(C_QuestLog.GetQuestObjectives(id) or {}) do
            if o.text and o.text ~= "" and not o.finished then GameTooltip:AddLine("  " .. o.text, 0.8, 0.8, 0.8) end
        end
    end
    GameTooltip:Show()
end

-- Tooltip + highlight for the quest areas under the cursor (all of them where circles overlap).
function Overlay:AttachHover()
    local view, acc = self.canvas.view, 0
    view:HookScript("OnUpdate", function(_, dt)
        acc = acc + dt
        if acc < 0.05 then return end
        acc = 0
        local ids = {}
        if view:IsMouseOver() and not self.markerHover and not self.canvas.dragging then
            local px, py = self.canvas:CursorOnCanvas()
            if px then ids = self:QuestsAt(px, py) end
        end
        local key = table.concat(ids, ",")
        if key == self.hoverKey then return end
        self.hoverKey = key
        if #ids == 0 then
            if self.hoverShown then GameTooltip:Hide(); self.hoverShown = nil end
            self:SetHighlight(self.pinned)
            return
        end
        local set = {}
        for _, id in ipairs(ids) do set[id] = true end
        self:SetHighlight(set)
        GameTooltip:SetOwner(view, "ANCHOR_CURSOR_RIGHT")
        fillTip(ids)
        self.hoverShown = true
    end)
end
