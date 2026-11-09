-- Pure geometry for quest areas (no WoW API; tested offline).
local ADDON, M = ...

local G = {}
M.Geometry = G

local MIN_RADIUS, MAX_RADIUS, LINK_DIST = 0.015, 0.12, 0.07

-- Dots: lootables and interactables (objects) and short NPC lists get one small circle per spawn instead of a big area.
local DOT_RADIUS, DOT_MERGE, MAX_DOTS, SMALL_GROUP = 0.007, 0.004, 40, 3

-- Single-linkage clustering: points within LINK_DIST of any cluster member join it. Returns arrays of points.
local function cluster(pts)
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
    for _, r in ipairs(order) do out[#out + 1] = groups[r] end
    return out
end

-- Drop points that sit on top of an earlier one (same spawn listed under several sources).
local function dedupe(pts)
    local out, d2 = {}, DOT_MERGE * DOT_MERGE
    for _, p in ipairs(pts) do
        local dup
        for _, q in ipairs(out) do
            local dx, dy = p[1] - q[1], p[2] - q[2]
            if dx * dx + dy * dy <= d2 then dup = true; break end
        end
        if not dup then out[#out + 1] = p end
    end
    return out
end

local function dots(pts, out)
    for _, p in ipairs(pts) do out[#out + 1] = { x = p[1], y = p[2], radius = DOT_RADIUS, dot = true } end
end

local function area(g)
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
    return { x = cx, y = cy, radius = rad }
end

-- pts: array of {x, y, sourceId} in 0..1 (sourceId < 0 is an object, otherwise an NPC; may be nil).
-- Returns array of {x=, y=, radius=, dot=true|nil}.
function G.areas(pts)
    local objs, npcs = {}, {}
    for _, p in ipairs(pts) do
        if p[3] and p[3] < 0 then objs[#objs + 1] = p else npcs[#npcs + 1] = p end
    end
    local out = {}
    objs = dedupe(objs)
    if #objs <= MAX_DOTS then dots(objs, out) else for _, g in ipairs(cluster(objs)) do out[#out + 1] = area(g) end end
    for _, g in ipairs(cluster(npcs)) do
        g = dedupe(g)
        if #g <= SMALL_GROUP then dots(g, out) else out[#out + 1] = area(g) end
    end
    return out
end
