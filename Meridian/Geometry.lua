-- Pure geometry for quest areas (no WoW API; tested offline).
local ADDON, M = ...

local G = {}
M.Geometry = G

local MIN_RADIUS, MAX_RADIUS, LINK_DIST = 0.015, 0.12, 0.07

-- Single-linkage clustering: points within LINK_DIST of any cluster member join it.
-- pts: array of {x, y} in 0..1. Returns array of {x=, y=, radius=}.
function G.areas(pts)
    local parent = {}
    for i = 1, #pts do parent[i] = i end
    local function find(i)
        while parent[i] ~= i do parent[i] = parent[parent[i]]; i = parent[i] end
        return i
    end
    local d2 = LINK_DIST * LINK_DIST
    for i = 1, #pts do
        for j = i + 1, #pts do
            local dx, dy = pts[i][1] - pts[j][1], pts[i][2] - pts[j][2]
            if dx * dx + dy * dy <= d2 then parent[find(i)] = find(j) end
        end
    end
    local groups, order = {}, {}
    for i = 1, #pts do
        local r = find(i)
        if not groups[r] then groups[r] = {}; order[#order + 1] = r end
        local g = groups[r]
        g[#g + 1] = pts[i]
    end
    local out = {}
    for _, r in ipairs(order) do
        local g = groups[r]
        local minx, maxx, miny, maxy = 1e9, -1e9, 1e9, -1e9
        for _, p in ipairs(g) do
            if p[1] < minx then minx = p[1] end
            if p[1] > maxx then maxx = p[1] end
            if p[2] < miny then miny = p[2] end
            if p[2] > maxy then maxy = p[2] end
        end
        local cx, cy = (minx + maxx) / 2, (miny + maxy) / 2
        local rad = 0
        for _, p in ipairs(g) do
            local dx, dy = p[1] - cx, p[2] - cy
            rad = math.max(rad, math.sqrt(dx * dx + dy * dy))
        end
        rad = math.min(MAX_RADIUS, math.max(MIN_RADIUS, rad + MIN_RADIUS / 2))
        out[#out + 1] = { x = cx, y = cy, radius = rad }
    end
    return out
end
