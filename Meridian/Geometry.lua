-- Pure geometry for quest areas (no WoW API; tested offline).
--
-- Objectives become, per map: one small dot per spawn of an object or a short list of mobs, and for bigger groups of mob
-- spawns a polygon region. Spawns are grouped by how close their coverage comes (linking nearest first) while a group
-- stays under a maximum span, so a long coastline becomes a chain of regions rather than one hull over the sea. A
-- region is the polygon whose sides touch the outline of its spawns' discs from outside, so it covers every spawn.
-- The ideas follow Polestar's quest-area regions (a separate GPL addon; this is an independent implementation).
local ADDON, M = ...

local G = {}
M.Geometry = G

-- Units: fractions of the zone map's width (0..1).
local LINK = 0.04        -- discs this close (gap) join one group
local MAX_SPAN = 0.22    -- a group never grows wider than this
local MIN_R, PAD = 0.008, 0.005 -- a spawn covers a disc of at least MIN_R, drawn PAD wider
local SMALL = 0.045      -- a group narrower than this is an 8-gon, bigger ones a 16-gon
local DOT_RADIUS, DOT_MERGE, MAX_DOTS, SMALL_GROUP = 0.007, 0.004, 40, 3
G.LINK, G.MAX_SPAN = LINK, MAX_SPAN

local sin, cos, pi, sqrt, max, min = math.sin, math.cos, math.pi, math.sqrt, math.max, math.min

local sides = {}
for _, k in ipairs({ 8, 16 }) do
    local t = { n = k, cos = {}, sin = {}, det = sin(2 * pi / k) }
    for i = 1, k do
        local a = 2 * pi * (i - 1) / k
        t.cos[i], t.sin[i] = cos(a), sin(a)
    end
    sides[k] = t
end

-- Drop points that sit on top of an earlier one (the same spawn listed under several sources).
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

-- Groups of points: nearest pairs first, a join only while the group stays within MAX_SPAN. Pairs are found through a grid
-- (cell = reach of a link) so a thousand spawns do not compare a million pairs. Returns an array of arrays of points.
local function group(pts)
    local n = #pts
    local reach = LINK + 2 * MIN_R
    local grid = {}
    for i = 1, n do
        local cx, cy = math.floor(pts[i][1] / reach), math.floor(pts[i][2] / reach)
        local key = cx * 100003 + cy
        local c = grid[key]
        if not c then c = {}; grid[key] = c end
        c[#c + 1] = i
    end
    local pairsList = {}
    local r2 = reach * reach
    for i = 1, n do
        local cx, cy = math.floor(pts[i][1] / reach), math.floor(pts[i][2] / reach)
        for gx = cx - 1, cx + 1 do
            for gy = cy - 1, cy + 1 do
                local c = grid[gx * 100003 + gy]
                if c then
                    for _, j in ipairs(c) do
                        if j > i then
                            local dx, dy = pts[i][1] - pts[j][1], pts[i][2] - pts[j][2]
                            local d = dx * dx + dy * dy
                            if d <= r2 then pairsList[#pairsList + 1] = { d, i, j } end
                        end
                    end
                end
            end
        end
    end
    table.sort(pairsList, function(a, b) return a[1] < b[1] end)
    local parent, box = {}, {}
    for i = 1, n do parent[i] = i; box[i] = { pts[i][1], pts[i][1], pts[i][2], pts[i][2] } end
    local function find(i)
        while parent[i] ~= i do parent[i] = parent[parent[i]]; i = parent[i] end
        return i
    end
    for _, pr in ipairs(pairsList) do
        local a, b = find(pr[2]), find(pr[3])
        if a ~= b then
            local A, B = box[a], box[b]
            local x0, x1, y0, y1 = min(A[1], B[1]), max(A[2], B[2]), min(A[3], B[3]), max(A[4], B[4])
            if max(x1 - x0, y1 - y0) <= MAX_SPAN then
                parent[a] = b
                box[b] = { x0, x1, y0, y1 }
            end
        end
    end
    local groups, order = {}, {}
    for i = 1, n do
        local r = find(i)
        if not groups[r] then groups[r] = {}; order[#order + 1] = r end
        local g = groups[r]
        g[#g + 1] = pts[i]
    end
    local out = {}
    for _, r in ipairs(order) do out[#out + 1] = groups[r] end
    return out
end

-- The polygon whose sides are tangent to the discs (radius MIN_R + PAD) round the group's points: for each of K directions
-- the farthest the discs reach, then the corner where neighbouring sides meet. Returns { x1, y1, x2, y2, ... }, centre, radius.
local function region(g)
    local x0, x1, y0, y1 = 1e9, -1e9, 1e9, -1e9
    for _, p in ipairs(g) do
        x0, x1, y0, y1 = min(x0, p[1]), max(x1, p[1]), min(y0, p[2]), max(y1, p[2])
    end
    local t = sides[max(x1 - x0, y1 - y0) < SMALL and 8 or 16]
    local K, ck, sk = t.n, t.cos, t.sin
    local r = MIN_R + PAD
    local h = {}
    for k = 1, K do
        local best = -1e9
        for _, p in ipairs(g) do
            local v = p[1] * ck[k] + p[2] * sk[k] + r
            if v > best then best = v end
        end
        h[k] = best
    end
    local hull, sx, sy = {}, 0, 0
    for k = 1, K do
        local j = k % K + 1
        local x = (h[k] * sk[j] - h[j] * sk[k]) / t.det
        local y = (h[j] * ck[k] - h[k] * ck[j]) / t.det
        hull[#hull + 1] = x
        hull[#hull + 1] = y
        sx, sy = sx + x, sy + y
    end
    local cx, cy = sx / K, sy / K
    local rad = 0
    for i = 1, #hull - 1, 2 do rad = max(rad, sqrt((hull[i] - cx) ^ 2 + (hull[i + 1] - cy) ^ 2)) end
    return hull, cx, cy, rad
end

-- The most common kind among a group's points (kill, interact, loot ...), nil when none is set.
local function kindOf(g)
    local count, best, bestN = {}, nil, 0
    for _, p in ipairs(g) do
        local k = p[4]
        if k then
            count[k] = (count[k] or 0) + 1
            if count[k] > bestN then best, bestN = k, count[k] end
        end
    end
    return best
end

local function dots(pts, out)
    for _, p in ipairs(pts) do out[#out + 1] = { x = p[1], y = p[2], radius = DOT_RADIUS, dot = true, kind = p[4] } end
end

-- pts: array of {x, y, sourceId, kind} in 0..1 (sourceId < 0 is an object, otherwise an NPC; both optional).
-- Returns array of {x=, y=, radius=, dot=true | hull={x1, y1, ...}, kind=}.
function G.areas(pts)
    local objs, npcs = {}, {}
    for _, p in ipairs(pts) do
        if p[3] and p[3] < 0 then objs[#objs + 1] = p else npcs[#npcs + 1] = p end
    end
    local out = {}
    objs = dedupe(objs)
    local loose = {} -- more objects than dots can carry: grouped like mobs
    if #objs <= MAX_DOTS then dots(objs, out) else loose = objs end
    for _, src in ipairs({ npcs, loose }) do
        for _, g in ipairs(group(src)) do
            g = dedupe(g)
            if #g <= SMALL_GROUP then
                dots(g, out)
            else
                local hull, cx, cy, rad = region(g)
                out[#out + 1] = { x = cx, y = cy, radius = rad, hull = hull, kind = kindOf(g) }
            end
        end
    end
    return out
end

-- Is the point inside the convex polygon { x1, y1, ... }? (either winding)
function G.inside(hull, x, y)
    local sign
    local n = #hull / 2
    for i = 1, n do
        local j = i % n + 1
        local ax, ay, bx, by = hull[2 * i - 1], hull[2 * i], hull[2 * j - 1], hull[2 * j]
        local cr = (bx - ax) * (y - ay) - (by - ay) * (x - ax)
        if cr ~= 0 then
            local s = cr > 0
            if sign == nil then sign = s elseif sign ~= s then return false end
        end
    end
    return true
end
