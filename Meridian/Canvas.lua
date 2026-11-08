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
    self.tiles, self.zoom, self.offX, self.offY = {}, 1, 0, 0
    self.cw, self.ch = 1, 1
    self.pinLayer = CreateFrame("Frame", nil, canvas)
    self.pinLayer:SetAllPoints()

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
    z = Math.clamp(z, M.db.zoomMin, M.db.zoomMax)
    cx, cy = cx or self.view:GetWidth() / 2, cy or self.view:GetHeight() / 2
    local x, y = Math.zoomAround(self.offX, self.offY, self.zoom, z, cx, cy)
    self.zoom = z
    self:SetOffset(x, y)
end

-- Fit the whole map in the viewport, centered.
function Canvas:Fit()
    local z = math.min(self.view:GetWidth() / self.cw, self.view:GetHeight() / self.ch)
    self.zoom = z
    self:SetOffset((self.view:GetWidth() - self.cw * z) / 2, (self.view:GetHeight() - self.ch * z) / 2)
end

function Canvas:CenterOn(nx, ny)
    local px, py = Math.toCanvas(nx, ny, self.cw, self.ch)
    self:SetOffset(self.view:GetWidth() / 2 - px * self.zoom, self.view:GetHeight() / 2 - py * self.zoom)
end

function Canvas:SetMap(uiMapID)
    self.mapID = uiMapID
    for _, t in ipairs(self.tiles) do t:Hide() end
    local layers = C_Map.GetMapArtLayers(uiMapID)
    local layer = layers and layers[1]
    if not layer then self.cw, self.ch = 1002, 668; self.canvas:SetSize(self.cw, self.ch); return end
    local files = C_Map.GetMapArtLayerTextures(uiMapID, 1)
    self.cw, self.ch = layer.layerWidth, layer.layerHeight
    self.canvas:SetSize(self.cw, self.ch)
    local tw, th = layer.tileWidth, layer.tileHeight
    local cols = math.ceil(self.cw / tw)
    for i, file in ipairs(files or {}) do
        local t = self.tiles[i]
        if not t then
            t = self.canvas:CreateTexture(nil, "BACKGROUND")
            self.tiles[i] = t
        end
        local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
        t:SetSize(tw, th)
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", col * tw, -row * th)
        t:SetTexture(file)
        t:Show()
    end
    self:Fit()
end

-- Convert a normalized position into a canvas TOPLEFT offset for pin placement.
function Canvas:PlacePin(pin, nx, ny)
    local px, py = Math.toCanvas(nx, ny, self.cw, self.ch)
    pin:ClearAllPoints()
    pin:SetPoint("CENTER", self.pinLayer, "TOPLEFT", px, -py)
end
