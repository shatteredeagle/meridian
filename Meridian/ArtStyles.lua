-- Optional map art styles for the Eastern Kingdoms continent view: Blizzard's own art (default) or one of the pixel-art
-- experiments (a, b, c; see docs/pixelmap/README.md). The pixel tiles live in a separate, local-only addon folder
-- (MeridianPixelMaps, written by tools/pixelmap/install_tiles.py) and are drawn under the quest overlays.
local ADDON, M = ...

local Art = {}
M.Art = Art

Art.styles = {
    { key = "blizzard", name = "Blizzard" },
    { key = "a", name = "Pixel A: stylized Blizzard art" },
    { key = "b", name = "Pixel B: procedural from game data" },
    { key = "c", name = "Pixel C: B + landmarks" },
}

local MAP_ID = 1415                    -- Eastern Kingdoms
local LAYOUT_MINX, LAYOUT_MINY = -3450.0, -3837.5 -- yards: origin the tiles were rendered against (layout.json)
local YARDS_TO_PX = 0.35               -- must match Canvas.lua
local TILE, COLS, ROWS = 512, 7, 14    -- canvas units per tile, tile grid

local function styleIndex(key)
    for i, s in ipairs(Art.styles) do if s.key == key then return i end end
    return 1
end

function Art:Current() return M.db.artStyle or "blizzard" end

function Art:Name(key) return Art.styles[styleIndex(key or self:Current())].name end

local function addonExists(name)
    local ok, found = pcall(function()
        if C_AddOns and C_AddOns.DoesAddOnExist then return C_AddOns.DoesAddOnExist(name) end
        if GetAddOnInfo then return GetAddOnInfo(name) ~= nil end
    end)
    return ok and found and true or false
end

-- Is the local tile addon present? (Without it the pixel styles are unavailable.)
function Art:Installed()
    if self.installed == nil then self.installed = addonExists("MeridianPixelMaps") end
    return self.installed
end

-- Should this continent be drawn with the chosen art style instead of Blizzard's zone maps?
function Art:Wants(contID)
    local key = self:Current()
    return key ~= "blizzard" and contID == MAP_ID and self:Installed()
end

function Art:Hide(canvas)
    if canvas.pixelFrame then canvas.pixelFrame:Hide() end
end

-- Draw the 7 x 14 tile grid into the canvas, shifted so it lines up with this client's stitched origin.
function Art:Draw(canvas)
    local f = canvas.pixelFrame
    if not f then
        f = CreateFrame("Frame", nil, canvas.canvas)
        f.tex = {}
        canvas.pixelFrame = f
    end
    f:SetFrameLevel(canvas.canvas:GetFrameLevel() + 1)
    f:SetAllPoints()
    f:Show()
    local s = canvas.stitch
    local dx = s and (LAYOUT_MINX - s.minx) * YARDS_TO_PX or 0
    local dy = s and (LAYOUT_MINY - s.miny) * YARDS_TO_PX or 0
    dx, dy = dx + (M.db.artDx or 0), dy + (M.db.artDy or 0)
    self.shift = { dx, dy }
    local key, n = self:Current(), 0
    for r = 0, ROWS - 1 do
        for c = 0, COLS - 1 do
            n = n + 1
            local t = f.tex[n]
            if not t then
                t = f:CreateTexture(nil, "BACKGROUND")
                if canvas.mask then t:AddMaskTexture(canvas.mask) end
                f.tex[n] = t
            end
            t:SetTexture(string.format("Interface\\AddOns\\MeridianPixelMaps\\%s\\r%02d_c%02d", key, r, c), nil, nil, "NEAREST")
            t:SetSize(TILE, TILE)
            t:ClearAllPoints()
            t:SetPoint("TOPLEFT", f, "TOPLEFT", c * TILE + dx, -(r * TILE + dy))
            t:Show()
        end
    end
end

-- Switch style (key, or nil to cycle) and redraw every canvas.
function Art:Set(key)
    if not key then
        local i = styleIndex(self:Current()) % #Art.styles + 1
        key = Art.styles[i].key
    end
    local idx = styleIndex(key)
    key = Art.styles[idx].key
    if key ~= "blizzard" and not self:Installed() then
        return M:Print("Pixel tiles not installed: run tools/pixelmap/install_tiles.py, then restart the game.")
    end
    M.db.artStyle = key
    M.UI.canvas:Rebuild()
    if M.UI.mini then M.UI.mini.canvas:Rebuild() end
    M.UI:RefreshAll()
    M.UI:SyncToolbar()
    local cont = M.UI.canvas.mapID
    M:Print("Map art:", self:Name(key) .. (key ~= "blizzard" and cont ~= MAP_ID and " (only drawn on the Eastern Kingdoms continent view)" or ""))
end
