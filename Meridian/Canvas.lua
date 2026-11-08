-- Pan/zoom canvas: tiled map art for one uiMapID. Pure math helpers are in M.Math (testable offline).
local ADDON, M = ...

local Math = {}
M.Math = Math

function Math.clamp(v, lo, hi) return v < lo and lo or (v > hi and hi or v) end

-- Zoom keeping the canvas point under the cursor fixed.
-- offX/offY: canvas TOPLEFT offset from viewport TOPLEFT (px). cx/cy: cursor in viewport px.
function Math.zoomAround(offX, offY, zoom, newZoom, cx, cy)
    local ratio = newZoom / zoom
    return cx - (cx - offX) * ratio, cy - (cy - offY) * ratio
end

-- Keep the canvas from drifting fully off the viewport.
function Math.clampOffset(offX, offY, zoom, cw, ch, vw, vh)
    local w, h = cw * zoom, ch * zoom
    local minX, maxX = math.min(0, vw - w), math.max(0, vw - w)
    local minY, maxY = math.min(0, vh - h), math.max(0, vh - h)
    return Math.clamp(offX, minX, maxX), Math.clamp(offY, minY, maxY)
end

-- Orientation of a map's axes in world space, from samples at (0,0), (1,0), (0,1).
-- Returns ax, sx, ay, sy: map-x follows world axis ax (1|2) with sign sx; map-y follows ay with sy.
function Math.worldAxes(p00, p10, p01)
    local function dominant(a, b)
        local d1, d2 = b[1] - a[1], b[2] - a[2]
        if math.abs(d1) >= math.abs(d2) then return 1, d1 >= 0 and 1 or -1 end
        return 2, d2 >= 0 and 1 or -1
    end
    local ax, sx = dominant(p00, p10)
    local ay, sy = dominant(p00, p01)
    return ax, sx, ay, sy
end

-- Normalized map coords (0..1) <-> canvas px (unzoomed).
function Math.toCanvas(nx, ny, cw, ch) return nx * cw, ny * ch end
function Math.toNormalized(px, py, cw, ch) return px / cw, py / ch end

local Canvas = {}
Canvas.__index = Canvas
M.Canvas = Canvas

function Canvas:New(parent)
    local self = setmetatable({}, Canvas)
    local view = CreateFrame("Frame", nil, parent)
    view:SetClipsChildren(true)
    view:EnableMouse(true)
    view:EnableMouseWheel(true)
    local canvas = CreateFrame("Frame", nil, view)
    canvas:SetPoint("TOPLEFT")
    self.view, self.canvas = view, canvas
    self.zoneFrames, self.zoom, self.offX, self.offY = {}, 1, 0, 0
    self.cw, self.ch = 1, 1
    self.pinLayer = CreateFrame("Frame", nil, canvas)
    self.pinLayer:SetAllPoints()
    self.pinLayer:SetFrameLevel(canvas:GetFrameLevel() + 500)

    view:SetScript("OnMouseWheel", function(_, delta) self:OnWheel(delta) end)
    view:SetScript("OnMouseDown", function(_, btn) if btn == "LeftButton" then self:BeginDrag() end end)
    view:SetScript("OnMouseUp", function() self.dragging = nil end)
    view:SetScript("OnUpdate", function() self:OnDrag() end)
    return self
end

function Canvas:CursorInView()
    local scale = self.view:GetEffectiveScale()
    local x, y = GetCursorPosition()
    return x / scale - self.view:GetLeft(), self.view:GetTop() - y / scale
end

function Canvas:BeginDrag()
    local cx, cy = self:CursorInView()
    self.dragging = { cx = cx, cy = cy, ox = self.offX, oy = self.offY }
end

function Canvas:OnDrag()
    local d = self.dragging
    if not d then return end
    local cx, cy = self:CursorInView()
    self:SetOffset(d.ox + (cx - d.cx), d.oy + (cy - d.cy))
end

function Canvas:OnWheel(delta)
    local cx, cy = self:CursorInView()
    self:SetZoom(self.zoom * (delta > 0 and 1.2 or 1 / 1.2), cx, cy)
end

function Canvas:Apply()
    self.canvas:SetScale(self.zoom)
    self.canvas:ClearAllPoints()
    -- canvas is scaled, so its anchor offset is in scaled units
    self.canvas:SetPoint("TOPLEFT", self.view, "TOPLEFT", self.offX / self.zoom, -self.offY / self.zoom)
    if self.OnChanged then self:OnChanged() end
end

function Canvas:SetOffset(x, y)
    self.offX, self.offY = Math.clampOffset(x, y, self.zoom, self.cw, self.ch, self.view:GetWidth(), self.view:GetHeight())
    self:Apply()
end

function Canvas:SetZoom(z, cx, cy)
    z = Math.clamp(z, math.min(M.db.zoomMin, self.fitZoom or M.db.zoomMin), M.db.zoomMax)
    cx, cy = cx or self.view:GetWidth() / 2, cy or self.view:GetHeight() / 2
    local x, y = Math.zoomAround(self.offX, self.offY, self.zoom, z, cx, cy)
    self.zoom = z
    self:SetOffset(x, y)
end

-- Fit the whole map in the viewport, centered.
function Canvas:Fit()
    local z = math.min(self.view:GetWidth() / self.cw, self.view:GetHeight() / self.ch)
    self.zoom, self.fitZoom = z, z
    self:SetOffset((self.view:GetWidth() - self.cw * z) / 2, (self.view:GetHeight() - self.ch * z) / 2)
end

function Canvas:CenterOnCanvas(px, py)
    self:SetOffset(self.view:GetWidth() / 2 - px * self.zoom, self.view:GetHeight() / 2 - py * self.zoom)
end

function Canvas:CenterOn(nx, ny)
    local px, py = Math.toCanvas(nx, ny, self.cw, self.ch)
    self:CenterOnCanvas(px, py)
end

local YARDS_TO_PX = 0.35

-- Smallest power of two >= n (explored-overlay texture files are padded to this).
function Math.pow2(n)
    local p = 1
    while p < n do p = p * 2 end
    return p
end

local TILE = 256

local function getTex(list, frame, layer, n)
    local t = list[n]
    if not t then
        t = frame:CreateTexture(nil, layer)
        list[n] = t
    end
    return t
end

-- Draw one zone's art into the canvas rect {x,y,w,h} inside its own frame (frame level = draw order).
-- In "explored" mode the base art is dimmed and Blizzard's explored overlays are drawn at full brightness.
function Canvas:DrawZone(uiMapID, rect, zi)
    local f = self.zoneFrames[zi]
    if not f then
        f = CreateFrame("Frame", nil, self.canvas)
        f.tiles, f.fog = {}, {}
        self.zoneFrames[zi] = f
    end
    f:SetFrameLevel(self.canvas:GetFrameLevel() + zi)
    f:SetAllPoints()
    f:Show()
    for _, t in ipairs(f.tiles) do t:Hide() end
    for _, t in ipairs(f.fog) do t:Hide() end

    local layers = C_Map.GetMapArtLayers(uiMapID)
    local layer = layers and layers[1]
    local files = layer and C_Map.GetMapArtLayerTextures(uiMapID, 1)
    if not files then return end
    local k = rect.w / layer.layerWidth
    local tw, th = layer.tileWidth * k, layer.tileHeight * k
    local cols = math.ceil(layer.layerWidth / layer.tileWidth)
    local explored = M.db.reveal == "explored"
    local dim = explored and 0.3 or 1
    for i, file in ipairs(files) do
        local t = getTex(f.tiles, f, "BACKGROUND", i)
        local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
        t:SetSize(tw, th)
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", rect.x + col * tw, -(rect.y + row * th))
        t:SetTexture(file)
        t:SetVertexColor(dim, dim, dim)
        t:Show()
    end
    if not explored then return end

    local n = 0
    for _, ov in ipairs(C_MapExplorationInfo.GetExploredMapTextures(uiMapID) or {}) do
        local wide, tall = math.ceil(ov.textureWidth / TILE), math.ceil(ov.textureHeight / TILE)
        for j = 1, tall do
            for c = 1, wide do
                local idx = (j - 1) * wide + c
                local fid = ov.fileDataIDs[idx]
                if fid then
                    local pw = c < wide and TILE or ((ov.textureWidth % TILE == 0) and TILE or ov.textureWidth % TILE)
                    local ph = j < tall and TILE or ((ov.textureHeight % TILE == 0) and TILE or ov.textureHeight % TILE)
                    local fw, fh = Math.pow2(pw), Math.pow2(ph)
                    n = n + 1
                    local t = getTex(f.fog, f, "ARTWORK", n)
                    t:SetTexture(fid, nil, nil, "TRILINEAR")
                    t:SetTexCoord(0, pw / fw, 0, ph / fh)
                    t:SetVertexColor(1, 1, 1)
                    t:SetSize(pw * k, ph * k)
                    t:ClearAllPoints()
                    t:SetPoint("TOPLEFT", rect.x + (ov.offsetX + (c - 1) * TILE) * k, -(rect.y + (ov.offsetY + (j - 1) * TILE) * k))
                    t:Show()
                end
            end
        end
    end
end

local function worldPos(uiMapID, nx, ny)
    local _, pos = C_Map.GetWorldPosFromMapPos(uiMapID, CreateVector2D(nx, ny))
    if not pos then return nil end
    local x, y = pos:GetXY()
    return { x, y }
end

-- Stitch every zone of a continent into one contiguous map using world coordinates.
function Canvas:BuildContinent(contID)
    local kids = C_Map.GetMapChildrenInfo(contID, Enum.UIMapType.Zone, true)
    if not kids or #kids == 0 then return false end
    local corners, ax, sx, ay, sy = {}, nil
    for _, k in ipairs(kids) do
        local p00, p11 = worldPos(k.mapID, 0, 0), worldPos(k.mapID, 1, 1)
        if p00 and p11 then
            if not ax then
                local p10, p01 = worldPos(k.mapID, 1, 0), worldPos(k.mapID, 0, 1)
                if p10 and p01 then ax, sx, ay, sy = Math.worldAxes(p00, p10, p01) end
            end
            corners[#corners + 1] = { id = k.mapID, p00, p11 }
        end
    end
    if not ax or #corners == 0 then return false end
    local minx, miny, maxx, maxy = 1e12, 1e12, -1e12, -1e12
    for _, c in ipairs(corners) do
        c.x0, c.y0 = c[1][ax] * sx, c[1][ay] * sy
        c.x1, c.y1 = c[2][ax] * sx, c[2][ay] * sy
        minx, maxx = math.min(minx, c.x0, c.x1), math.max(maxx, c.x0, c.x1)
        miny, maxy = math.min(miny, c.y0, c.y1), math.max(maxy, c.y0, c.y1)
    end
    for _, c in ipairs(corners) do
        c.rect = { x = (c.x0 - minx) * YARDS_TO_PX, y = (c.y0 - miny) * YARDS_TO_PX,
                   w = (c.x1 - c.x0) * YARDS_TO_PX, h = (c.y1 - c.y0) * YARDS_TO_PX }
        c.area = math.abs(c.rect.w * c.rect.h)
    end
    table.sort(corners, function(a, b) return a.area > b.area end) -- big zones behind small ones
    self.cw, self.ch = (maxx - minx) * YARDS_TO_PX, (maxy - miny) * YARDS_TO_PX
    self.canvas:SetSize(self.cw, self.ch)
    for zi, c in ipairs(corners) do
        self.zones[c.id] = c.rect
        self:DrawZone(c.id, c.rect, zi)
    end
    self.zoneCount = #corners
    return true
end

function Canvas:BuildSingle(uiMapID)
    local layers = C_Map.GetMapArtLayers(uiMapID)
    local layer = layers and layers[1]
    self.cw, self.ch = layer and layer.layerWidth or 1002, layer and layer.layerHeight or 668
    self.canvas:SetSize(self.cw, self.ch)
    local rect = { x = 0, y = 0, w = self.cw, h = self.ch }
    self.zones[uiMapID] = rect
    self:DrawZone(uiMapID, rect, 1)
    self.zoneCount = 1
end

-- Redraw art (e.g. after a reveal-mode change) without moving the view.
function Canvas:Rebuild()
    if not self.mapID then return end
    local z, x, y = self.zoom, self.offX, self.offY
    self:SetMap(self.mapID)
    self.zoom = z
    self:SetOffset(x, y)
end

function Canvas:SetMap(uiMapID)
    self.mapID = uiMapID
    for _, f in ipairs(self.zoneFrames) do f:Hide() end
    self.zones = {}
    local info = C_Map.GetMapInfo(uiMapID)
    if not (info and info.mapType == Enum.UIMapType.Continent and self:BuildContinent(uiMapID)) then
        self:BuildSingle(uiMapID)
    end
    self:Fit()
end

-- Zone-normalized position -> canvas px (nil if that zone isn't on the canvas).
function Canvas:ZoneToCanvas(uiMapID, nx, ny)
    local z = self.zones[uiMapID]
    if not z then return nil end
    return z.x + nx * z.w, z.y + ny * z.h
end

function Canvas:PlacePinAt(pin, px, py)
    pin:ClearAllPoints()
    pin:SetPoint("CENTER", self.pinLayer, "TOPLEFT", px, -py)
end
