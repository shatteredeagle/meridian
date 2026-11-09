-- Optional Polestar integration: draws the walking route Polestar's guide arrow is following as breadcrumb dots on
-- Meridian's maps. Only Polestar's published route is read (Polestar.Nav.GetRouteGeometry and its NAV_ROUTE_GEOMETRY
-- message); nothing of Polestar's drawing code is used. Pure helpers are testable offline.
local ADDON, M = ...

local Route = {}
M.Route = Route

local DOT_PX = 5          -- dot diameter on screen
local GAP_PX = 14         -- distance between dot centres on screen
local MAX_DOTS = 700      -- per canvas; spacing widens when a route is long
local DOT = "Interface\\AddOns\\Meridian\\Media\\area"
local YARDS_TO_PX = 0.35

-- Leg kinds that are jumps (nothing to walk) and the colour of each other kind (r, g, b).
local JUMP = { hearth = true, teleport = true, portal = true }
local COLOR = { walk = { 1, 0.82, 0.2 }, flight = { 0.4, 1, 0.5 }, boat = { 0.4, 0.8, 1 }, zeppelin = { 0.6, 0.8, 1 },
    tram = { 0.8, 0.8, 0.8 }, lift = { 0.8, 0.8, 0.8 } }

-- Points spaced `gap` apart along a polyline {{x, y}, ...}, the first one half a gap in. Returns {{x, y}, ...}.
function Route.spaced(line, gap)
    local out, carry = {}, gap / 2
    for i = 2, #line do
        local x0, y0, x1, y1 = line[i - 1][1], line[i - 1][2], line[i][1], line[i][2]
        local dx, dy = x1 - x0, y1 - y0
        local len = math.sqrt(dx * dx + dy * dy)
        local at = carry
        while at <= len do
            local t = len > 0 and at / len or 0
            out[#out + 1] = { x0 + dx * t, y0 + dy * t }
            at = at + gap
        end
        carry = at - len
    end
    return out
end

local function polestarRoute()
    local P = _G.Polestar
    local nav = P and P.Nav
    if not (nav and nav.GetRouteGeometry) then return nil end
    local ok, geometry = pcall(nav.GetRouteGeometry)
    return ok and type(geometry) == "table" and geometry.legs or nil
end

function Route:Available()
    local P = _G.Polestar
    return P ~= nil and P.Nav ~= nil and P.Nav.GetRouteGeometry ~= nil
end

-- A world point (continent/world id, x, y) as canvas px on this canvas, or nil when it is on another world or the
-- canvas has no way to place it.
local function toCanvas(canvas, c, wx, wy)
    local s = canvas.stitch
    if s then
        if c ~= s.world then return nil end
        local w = { wx, wy }
        return (w[s.ax] * s.sx - s.minx) * YARDS_TO_PX, (w[s.ay] * s.sy - s.miny) * YARDS_TO_PX
    end
    if canvas.mapID and canvas.zones[canvas.mapID] and C_Map.GetMapPosFromWorldPos then
        local _, v = C_Map.GetMapPosFromWorldPos(c, CreateVector2D(wx, wy), canvas.mapID)
        if v then
            local x, y = v:GetXY()
            if x >= -0.05 and x <= 1.05 and y >= -0.05 and y <= 1.05 then return canvas:ZoneToCanvas(canvas.mapID, x, y) end
        end
    end
    return nil
end

local function frameFor(canvas)
    local f = canvas.routeFrame
    if not f then
        f = CreateFrame("Frame", nil, canvas.pinLayer)
        f:SetAllPoints()
        f:SetFrameLevel(canvas.pinLayer:GetFrameLevel() + 1)
        f.dots, f.shown = {}, 0
        canvas.routeFrame = f
    end
    return f
end

local function dot(f, i)
    local d = f.dots[i]
    if not d then
        d = {
            under = f:CreateTexture(nil, "ARTWORK", nil, 1),
            core = f:CreateTexture(nil, "ARTWORK", nil, 2),
        }
        d.under:SetTexture(DOT)
        d.under:SetVertexColor(0.02, 0.03, 0.06)
        d.under:SetAlpha(0.7)
        d.core:SetTexture(DOT)
        f.dots[i] = d
    end
    return d
end

-- Redraw the route on one canvas. Cheap to call when nothing changed (zoom, map and route revision are checked).
function Route:Draw(canvas, force)
    if not canvas.pinLayer then return end
    local f = frameFor(canvas)
    local on = M.db and M.db.polestarRoute ~= false and self:Available() and canvas.mapID
    if not on then
        if f.shown > 0 then for i = 1, f.shown do f.dots[i].under:Hide(); f.dots[i].core:Hide() end; f.shown = 0 end
        f.key = nil
        return
    end
    local key = (canvas.mapID or 0) .. ":" .. string.format("%.3f", canvas.zoom) .. ":" .. (self.revision or 0)
    if f.key == key and not force then return end
    f.key = key

    local legs = polestarRoute()
    local pointsByLeg, total = {}, 0
    for _, leg in ipairs(legs or {}) do
        if not JUMP[leg.kind] and type(leg.pts) == "table" then
            local line = {}
            for _, p in ipairs(leg.pts) do
                local px, py = toCanvas(canvas, p[1], p[2], p[3])
                if px then line[#line + 1] = { px, py } end
            end
            if #line > 1 then
                pointsByLeg[#pointsByLeg + 1] = { kind = leg.kind, current = leg.current, line = line }
                for i = 2, #line do
                    local dx, dy = line[i][1] - line[i - 1][1], line[i][2] - line[i - 1][2]
                    total = total + math.sqrt(dx * dx + dy * dy)
                end
            end
        end
    end

    local zoom = canvas.zoom
    local gap = GAP_PX / zoom
    if total / gap > MAX_DOTS then gap = total / MAX_DOTS end
    local size = DOT_PX / zoom
    local n, seenCurrent = 0, false
    for _, leg in ipairs(pointsByLeg) do
        if leg.current then seenCurrent = true end
        local later = seenCurrent and not leg.current
        local c = COLOR[leg.kind] or COLOR.walk
        for _, p in ipairs(Route.spaced(leg.line, gap)) do
            n = n + 1
            local d = dot(f, n)
            d.under:SetSize(size + 2 / zoom, size + 2 / zoom)
            d.core:SetSize(size, size)
            d.under:ClearAllPoints()
            d.under:SetPoint("CENTER", f, "TOPLEFT", p[1], -p[2])
            d.core:ClearAllPoints()
            d.core:SetPoint("CENTER", f, "TOPLEFT", p[1], -p[2])
            d.core:SetVertexColor(c[1], c[2], c[3])
            d.core:SetAlpha(later and 0.45 or 1)
            d.under:Show()
            d.core:Show()
        end
    end
    for i = n + 1, f.shown do f.dots[i].under:Hide(); f.dots[i].core:Hide() end
    f.shown = n
end

-- Redraw every Meridian canvas that exists (main map and minimap).
function Route:Refresh(force)
    local ui = M.UI
    if not ui then return end
    if ui.canvas then self:Draw(ui.canvas, force) end
    if ui.mini and ui.mini.canvas then self:Draw(ui.mini.canvas, force) end
end

-- Hook Polestar's route-changed message once Polestar has loaded (it may load after Meridian).
function Route:Init()
    if self.hooked or not self:Available() or not _G.Polestar.On then return end
    self.hooked = true
    _G.Polestar.On("NAV_ROUTE_GEOMETRY", function()
        Route.revision = (Route.revision or 0) + 1
        Route:Refresh()
    end)
end
