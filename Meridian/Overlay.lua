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

-- Colour-blind-safe palette (Okabe-Ito), cycled by quest id.
local OKABE = { { 0.9, 0.62, 0 }, { 0.34, 0.71, 0.91 }, { 0, 0.62, 0.45 }, { 0.94, 0.89, 0.26 },
    { 0, 0.45, 0.7 }, { 0.84, 0.37, 0 }, { 0.8, 0.47, 0.65 }, { 0.75, 0.75, 0.75 } }

-- Stable per-quest colour so each quest's area is distinguishable. palette: "cb" for colour-blind safe.
function Overlay.paletteColor(palette, questID)
    if palette == "cb" then
        local c = OKABE[questID % #OKABE + 1]
        return c[1], c[2], c[3]
    end
    local h = (questID * 0.61803398875) % 1
    local i, f = math.floor(h * 6), h * 6 - math.floor(h * 6)
    local q, t = 1 - f, f
    local r, g, b = ({1, q, 0, 0, t, 1})[i % 6 + 1], ({t, 1, 1, q, 0, 0})[i % 6 + 1], ({0, 0, t, 1, 1, q})[i % 6 + 1]
    return r, g, b
end
local function color(questID) return Overlay.paletteColor(M.db and M.db.palette, questID) end
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
-- Marker tints per kind; the pin silhouettes already differ, the colours only help.
local MARKER_COLORS = {
    default = { give = { 1, 0.85, 0.1 }, turnin = { 0.5, 1, 0.5 }, way = { 0.35, 0.8, 1 }, taxi = { 0.6, 0.8, 1 }, rare = { 1, 0.5, 0.2 }, poi = { 0.9, 0.9, 0.5 }, party = { 0.5, 0.8, 1 }, dungeon = { 0.75, 0.55, 1 } },
    cb = { give = { 0.94, 0.89, 0.26 }, turnin = { 0, 0.62, 0.45 }, way = { 0.34, 0.71, 0.91 }, taxi = { 0, 0.45, 0.7 }, rare = { 0.84, 0.37, 0 }, poi = { 0.8, 0.47, 0.65 }, party = { 0.34, 0.71, 0.91 }, dungeon = { 0.9, 0.62, 0 } },
}
function Overlay.markerColor(kind, palette)
    local set = MARKER_COLORS[palette or (M.db and M.db.palette) or "default"] or MARKER_COLORS.default
    local c = set[kind] or { 1, 1, 1 }
    return c[1], c[2], c[3]
end

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
        local function show(s)
            self.markerHover = true
            local sp = s.spec
            GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
            GameTooltip:SetText(sp.title or "", sp.r or 1, sp.g or 0.82, sp.b or 0)
            local lines = sp.lines
            if type(lines) == "function" then lines = lines(sp) end
            for _, l in ipairs(lines or {}) do GameTooltip:AddLine(l, 1, 1, 1, true) end
            if sp.detail then sp.detail(GameTooltip, sp) end
            if sp.hint then GameTooltip:AddLine(sp.hint, 0.6, 0.6, 0.6, true) end
            GameTooltip:Show()
            M.Tip.Track(function() show(s) end)
        end
        m:SetScript("OnEnter", show)
        m:SetScript("OnLeave", function() self.markerHover = nil; M.Tip.Track(nil); GameTooltip:Hide() end)
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
    local px, py = self.canvas:PosToCanvas(zoneID, spec.x, spec.y)
    if not px then return end
    local m = self:AcquireMarker()
    m.spec, m.px, m.py = spec, px, py
    m.base = spec.size or 16
    m.tex:SetTexture(PINS .. spec.pin)
    m.tex:SetVertexColor(spec.r or 1, spec.g or 1, spec.b or 1)
    self.markers[#self.markers + 1] = m
    return m
end

local DOT_MIN_PX = 9 -- a single-spawn circle never draws smaller than this on screen

function Overlay:Rescale()
    local s = 1 / self.canvas.zoom
    if M.Route then M.Route:Draw(self.canvas) end
    for _, p in ipairs(self.active) do
        if p.dot then
            local d = math.max(p.d, DOT_MIN_PX * s)
            p.r = d / 2
            p:SetSize(d, d)
        end
    end
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
        local list = zoneID <= 0 and {} or useDB and M.Data:Provider(zoneID) or self.providers.blizzard(zoneID)
        for _, a in ipairs(list) do
            local px, py = c:ZoneToCanvas(zoneID, a.x, a.y)
            if not self.questPos[a.questID] then self.questPos[a.questID] = { px, py } end
            self.areas[#self.areas + 1] = { questID = a.questID, zone = zoneID, x = a.x, y = a.y }
            if not M.db.hidden[a.questID] then
                local p = self:Acquire()
                local d = a.radius * 2 * math.abs(rect.w)
                p.questID, p.px, p.py, p.r, p.d, p.dot = a.questID, px, py, d / 2, d, a.dot
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
    if M.db.focus then self:ApplyAlpha() end
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
            local npc = g.npc
            local cr, cg, cb = Overlay.markerColor("give")
            self:AddMarker(zoneID, { x = g.x, y = g.y, pin = "give", size = 16, r = cr, g = cg, b = cb,
                title = g.name or "Quest", kind = "give", questID = g.questID,
                lines = function()
                    local out = { "Level " .. (g.level or "?") }
                    local src = npc and M.Data:SourceInfo(npc)
                    if src and src.name then
                        local lv = M.Tip.levelRange(src.minLevel, src.maxLevel)
                        out[#out + 1] = (src.isObject and "Object: " or "From: ") .. src.name .. (lv and (" (level " .. lv .. ")") or "")
                    end
                    return out
                end,
                detail = function(tt) M.Tip.details(tt, g.questID, false) end })
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
                    local cr, cg, cb = Overlay.markerColor("turnin")
                    self:AddMarker(zoneID, { x = p[1], y = p[2], pin = "turnin", size = 18, r = cr, g = cg, b = cb,
                        title = q.title or "Quest", lines = { "Ready to turn in" }, kind = "turnin", questID = q.questID,
                        detail = function(tt) M.Tip.details(tt, q.questID, true) end })
                end
            end
        end
    end
end
Overlay.RegisterSource("turnins", turninSource)


-- Tint and fade every pin. A highlighted quest (hover) is drawn bright, the rest are pushed back.
function Overlay:ApplyAlpha()
    local focus = M.db.focus
    if not focus then
        self.focusSet = nil
    elseif not (self.focusSet and self.focusSet[focus]) then
        self.focusSet = { [focus] = true }
    end
    local hl, base = self.highlight or self.focusSet, M.db.opacity
    for _, m in ipairs(self.markers) do
        local q = m.spec and m.spec.questID
        m:SetAlpha((focus and q and q ~= focus) and 0.25 or 1)
    end
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
        if IsShiftKeyDown() then M.Tip.details(GameTooltip, id, true) end
    end
    if not IsShiftKeyDown() then GameTooltip:AddLine("Hold Shift for rewards and prerequisites", 0.5, 0.5, 0.5) end
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
        local key = table.concat(ids, ",") .. (IsShiftKeyDown() and "S" or "")
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
