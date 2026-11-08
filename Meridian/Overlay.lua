-- Quest-area overlays. Providers return {questID=, x=, y=, radius=} in normalized map coords.
-- Areas are drawn additive so overlapping quests visibly brighten.
local ADDON, M = ...

local Overlay = {}
M.Overlay = Overlay

local DEFAULT_RADIUS = 0.03 -- fraction of map width; used for point-only data
local CIRCLE = "Interface\\CharacterFrame\\TempPortraitAlphaMaskSmall"

Overlay.providers = {}

-- Provider 1: Blizzard quest POIs. Point data only, so draw a fixed-size area.
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

function Overlay:Init(canvas)
    self.canvas = canvas
    self.pool, self.active = {}, {}
    canvas.OnChanged = function() self:Rescale() end
end

function Overlay:Acquire()
    local p = table.remove(self.pool)
    if not p then
        p = self.canvas.pinLayer:CreateTexture(nil, "ARTWORK")
        p:SetTexture(CIRCLE)
        p:SetBlendMode("ADD")
    end
    p:Show()
    return p
end

function Overlay:Clear()
    for _, p in ipairs(self.active) do p:Hide(); self.pool[#self.pool + 1] = p end
    wipe(self.active)
end

function Overlay:Refresh()
    local c = self.canvas
    if not c.mapID then return end
    self:Clear()
    for _, name in pairs(self.providers) do
        for _, a in ipairs(name(c.mapID)) do
            local p = self:Acquire()
            local r, g, b = color(a.questID)
            p:SetVertexColor(r, g, b, M.db.overlayAlpha)
            local d = a.radius * 2 * c.cw
            p:SetSize(d, d)
            c:PlacePin(p, a.x, a.y)
            self.active[#self.active + 1] = p
        end
    end
end

function Overlay:Rescale() end -- areas scale with the canvas; point markers (later) counter-scale here
