-- Dungeon and instance maps: find them, show entrances on zone/continent maps, open them in the canvas with
-- floor switching, and overlay in-dungeon quest hand-ins/givers where data exists.
--
-- Sources, merged by name (none is required):
--   1. ForeverDungeonJournal (optional): its DUNGEON_MAPS floors (client map IDs, or its own map tiles/textures),
--      entrance coordinates on zone maps, in-dungeon NPC positions and quest lists.
--   2. C_Map: every map of type Dungeon that has art, grouped into floors by map group (or by name).
--   3. C_EncounterJournal.GetDungeonEntrancesForMap: entrance positions on zone maps (guarded; may be absent).
-- Pure helpers (names, floor grouping, tile layout, entrance grouping, quest matching) are tested offline.
local ADDON, M = ...
local L = M.L

local Dungeons = {}
M.Dungeons = Dungeons

---------------------------------------------------------------------------------
-- Pure helpers
---------------------------------------------------------------------------------

-- Lower-case letters and digits only, so "Razorfen Kraul" and "Razorfen  Kraul!" compare equal.
function Dungeons.norm(s)
    if type(s) ~= "string" then return "" end
    return (s:lower():gsub("[^%w\128-\255]", ""))
end

-- "Scarlet Monastery: Library" -> "Library".
function Dungeons.baseName(s)
    if type(s) ~= "string" then return "" end
    return (s:gsub("^.-:%s*", ""))
end

-- Same dungeon? Equal after normalising, or one contains the other (at least 6 letters, so "Maraudon" matches
-- "Maraudon: Orange" but a 3-letter fragment never matches).
function Dungeons.nameMatches(a, b)
    local na, nb = Dungeons.norm(a), Dungeons.norm(b)
    if na == "" or nb == "" then return false end
    if na == nb then return true end
    local short, long = na, nb
    if #short > #long then short, long = long, short end
    return #short >= 6 and long:find(short, 1, true) ~= nil
end

-- maps: array of {mapID, name, group (map group id or nil/0), order (height index or nil)}.
-- Maps sharing a group id (or, without one, a name) are the floors of one dungeon, lowest order first.
-- Returns array of {name, floors = {{mapID, label}}} in first-seen order.
function Dungeons.groupFloors(maps)
    local groups, order, seenMap = {}, {}, {}
    for _, m in ipairs(maps) do
        if m.mapID and not seenMap[m.mapID] then
            seenMap[m.mapID] = true
            local key = (m.group and m.group > 0) and ("g" .. m.group) or ("n" .. Dungeons.norm(m.name))
            local g = groups[key]
            if not g then g = { floors = {} }; groups[key] = g; order[#order + 1] = g end
            g.floors[#g.floors + 1] = { mapID = m.mapID, label = m.name, order = m.order or 0 }
        end
    end
    for _, g in ipairs(order) do
        table.sort(g.floors, function(a, b)
            if a.order ~= b.order then return a.order < b.order end
            return a.mapID < b.mapID
        end)
        g.name = g.floors[1].label
    end
    return order
end

-- The 4x3 grid of 256px tiles Blizzard map art uses, clipped to the visible w x h:
-- array of {index (file suffix 1..), x, y, w, h (px), u, v (texture coordinate right/bottom)}.
function Dungeons.tileSpecs(w, h, tile, cols, rows)
    local out = {}
    for row = 0, rows - 1 do
        for col = 0, cols - 1 do
            local x0, y0 = col * tile, row * tile
            if x0 < w and y0 < h then
                local pw, ph = math.min(tile, w - x0), math.min(tile, h - y0)
                out[#out + 1] = { index = row * cols + col + 1, x = x0, y = y0, w = pw, h = ph, u = pw / tile, v = ph / tile }
            end
        end
    end
    return out
end

local TILE_W, TILE_H = 1002, 668 -- visible size of a classic map's 4x3 tile grid

-- Canvas size of a floor drawn from its own art: tile grid, or a single texture with the art in its top-left
-- (texRight/texBottom of a square power-of-two texture; the art's aspect is texRight/texBottom).
function Dungeons.customSize(floor)
    if floor.tiles then return TILE_W, TILE_H end
    local aspect = (floor.texRight or 1) / (floor.texBottom or 1)
    return TILE_W, math.floor(TILE_W / aspect + 0.5)
end

-- Entrances sharing a spot (e.g. the wings of one dungeon) become one marker.
-- list: array of {d, map, x, y}. Returns array of {key, map, x, y, items = {entrance...}}.
function Dungeons.groupEntrances(list)
    local out, byKey = {}, {}
    for _, e in ipairs(list) do
        local key = e.map .. ":" .. math.floor(e.x * 100 + 0.5) .. ":" .. math.floor(e.y * 100 + 0.5)
        local g = byKey[key]
        if not g then g = { key = key, map = e.map, x = e.x, y = e.y, items = {} }; byKey[key] = g; out[#out + 1] = g end
        g.items[#g.items + 1] = e
    end
    return out
end

local function mentions(text, npc)
    return type(text) == "string" and type(npc) == "string" and text:lower():find(npc:lower(), 1, true) ~= nil
end

-- Quests (array of {id, name, turnin}) that hand in at `npc` and satisfy ready(id).
function Dungeons.turninQuests(npc, quests, ready)
    local out = {}
    for _, q in ipairs(quests or {}) do
        if mentions(q.turnin, npc) and ready(q.id) then out[#out + 1] = q end
    end
    return out
end

-- Can the player pick this dungeon quest up? p: {level, faction, greyRange, done(id), logged(id)}.
function Dungeons.canOffer(q, p)
    if not q.id or p.done(q.id) or p.logged(q.id) then return false end
    if q.requires and q.requires > p.level then return false end
    if q.level and q.level < p.level - (p.greyRange or 7) then return false end
    if q.faction and q.faction ~= "Both" and p.faction and q.faction ~= p.faction then return false end
    return true
end

-- Quests (array) that start at `npc` and satisfy offer(q).
function Dungeons.offerQuests(npc, quests, offer)
    local out = {}
    for _, q in ipairs(quests or {}) do
        if mentions(q.pickup, npc) and offer(q) then out[#out + 1] = q end
    end
    return out
end

-- Search candidates for a dungeon list.
function Dungeons.searchItems(list)
    local items = {}
    for _, d in ipairs(list) do items[#items + 1] = { kind = "dungeon", name = d.name, dungeon = d } end
    return items
end

-- Centre of a map rectangle, or nil when it is empty (GetMapRectOnMap returns zeros for unrelated maps).
function Dungeons.rectCenter(minX, maxX, minY, maxY)
    if not (minX and maxX and minY and maxY) or maxX <= minX or maxY <= minY then return nil end
    return (minX + maxX) / 2, (minY + maxY) / 2
end

---------------------------------------------------------------------------------
-- Registry (built on first use)
---------------------------------------------------------------------------------

local MAX_SCAN = 3000
local fakeKey = -1000 -- floors with no client map ID get negative keys, so they never collide with uiMapIDs

local function hasArt(id)
    if not (C_Map and C_Map.GetMapArtLayers and C_Map.GetMapArtLayerTextures) then return false end
    local ok, layers = pcall(C_Map.GetMapArtLayers, id)
    if not ok or type(layers) ~= "table" or not layers[1] then return false end
    local ok2, files = pcall(C_Map.GetMapArtLayerTextures, id, 1)
    return ok2 and type(files) == "table" and #files > 0
end

local function xy(v)
    if type(v) ~= "table" then return nil end
    if v.GetXY then return v:GetXY() end
    if v.x and v.y then return v.x, v.y end
end

local function fdjNS() return _G.ForeverDungeonJournal_NS end

local function floorLabel(i, n, name) return n > 1 and string.format(L["Floor %d"], i) or name end

-- ForeverDungeonJournal's dungeons, if that addon is loaded.
local function fromFDJ(out)
    local fdj = fdjNS()
    if not (fdj and type(fdj.DUNGEON_MAPS) == "table") then return end
    local names = {}
    for name in pairs(fdj.DUNGEON_MAPS) do names[#names + 1] = name end
    table.sort(names)
    for _, name in ipairs(names) do
        local spec = fdj.DUNGEON_MAPS[name]
        local d = { name = name, floors = {}, source = "journal", turnins = spec.turnins, portal = spec.entrance }
        local nf = #(spec.floors or {})
        for i, f in ipairs(spec.floors or {}) do
            local fl = { index = #d.floors + 1, mapID = f.uiMapID, label = floorLabel(i, nf, name) }
            local art = f.uiMapID and hasArt(f.uiMapID)
            if not art and (f.tiles or f.texture) then
                fl.tiles, fl.texture, fl.texBottom, fl.texRight = f.tiles, f.texture, f.texBottom, f.texRight
                fl.custom = true
            end
            if art or fl.custom then
                if fl.mapID then
                    fl.key = fl.mapID
                else
                    fakeKey = fakeKey - 1
                    fl.key = fakeKey
                end
                fl.sourceFloor = i
                d.floors[#d.floors + 1] = fl
            end
        end
        local rec = fdj.DB and fdj.DB[name]
        if rec then
            d.quests = rec.quests
            d.level = rec.level
            local e = rec.entrance
            if e and e.mapID and e.x and e.y then
                d.entrance = { map = e.mapID, x = e.x, y = e.y, label = e.label, detail = e.detail }
            end
        end
        if #d.floors > 0 then out[#out + 1] = d end
    end
end

-- Every client map of type Dungeon with art, grouped into dungeons.
local function fromClient(out)
    if not (C_Map and C_Map.GetMapInfo and Enum and Enum.UIMapType) then return end
    local used, maps, info = {}, {}, {}
    for _, d in ipairs(out) do
        for _, f in ipairs(d.floors) do if f.mapID then used[f.mapID] = true end end
    end
    for id = 1, MAX_SCAN do
        local ok, i = pcall(C_Map.GetMapInfo, id)
        if ok and type(i) == "table" and i.mapType == Enum.UIMapType.Dungeon and i.name and not used[id] and hasArt(id) then
            local group = 0
            if C_Map.GetMapGroupID then
                local ok2, g = pcall(C_Map.GetMapGroupID, id)
                if ok2 and type(g) == "number" then group = g end
            end
            maps[#maps + 1] = { mapID = id, name = i.name, group = group }
            info[id] = i
        end
    end
    -- floor order from the map group, where the client has one
    local order = {}
    if C_Map.GetMapGroupMembersInfo then
        local seen = {}
        for _, m in ipairs(maps) do
            if m.group > 0 and not seen[m.group] then
                seen[m.group] = true
                local ok, members = pcall(C_Map.GetMapGroupMembersInfo, m.group)
                for _, mem in ipairs(ok and type(members) == "table" and members or {}) do
                    order[mem.mapID] = mem.relativeHeightIndex
                end
            end
        end
    end
    for _, m in ipairs(maps) do m.order = order[m.mapID] end
    for _, g in ipairs(Dungeons.groupFloors(maps)) do
        local dupe = false
        for _, d in ipairs(out) do
            if Dungeons.nameMatches(g.name, d.name) or Dungeons.nameMatches(g.name, Dungeons.baseName(d.name)) then dupe = true; break end
        end
        if not dupe then
            local d = { name = g.name, floors = {}, source = "client" }
            for i, f in ipairs(g.floors) do
                d.floors[i] = { index = i, key = f.mapID, mapID = f.mapID, label = floorLabel(i, #g.floors, g.name) }
            end
            -- last-resort entrance: where the dungeon's map sits on its parent zone map
            local first = info[g.floors[1].mapID]
            if first and first.parentMapID and first.parentMapID > 0 and C_Map.GetMapRectOnMap then
                local ok, a, b, c, e = pcall(C_Map.GetMapRectOnMap, g.floors[1].mapID, first.parentMapID)
                local x, y
                if ok then x, y = Dungeons.rectCenter(a, b, c, e) end
                if x then d.entrance = { map = first.parentMapID, x = x, y = y } end
            end
            out[#out + 1] = d
        end
    end
end

-- All known dungeons (array), built once. Entrance-less dungeons are still searchable.
function Dungeons:List()
    if self.list then return self.list end
    local list = {}
    local ok1, e1 = pcall(fromFDJ, list)
    local ok2, e2 = pcall(fromClient, list)
    if not ok1 or not ok2 then M:Print("Dungeon scan problem: " .. tostring(ok1 and e2 or e1)) end
    self.byKey = {}
    for _, d in ipairs(list) do
        for i, f in ipairs(d.floors) do self.byKey[f.key] = { d = d, floor = i } end
    end
    self.entranceCache = {}
    self.list = list
    return list
end

-- The dungeon and floor index a map key belongs to, or nil.
function Dungeons:ForMap(key)
    if not key then return nil end
    self:List()
    local hit = self.byKey[key]
    if hit then return hit.d, hit.floor end
end

-- Floor spec when the canvas must draw its own art for `key` (a floor whose map the client cannot draw).
function Dungeons:CustomFloor(key)
    if not (key and self.byKey) then return nil end
    local hit = self.byKey[key]
    local f = hit and hit.d.floors[hit.floor]
    return f and f.custom and f or nil
end

-- Entrances shown on one zone map: array of {d, map, x, y}.
function Dungeons:EntrancesOn(mapID)
    self:List()
    local hit = self.entranceCache[mapID]
    if hit then return hit end
    hit = {}
    local has = {}
    for _, d in ipairs(self.list) do
        local e = d.entrance
        if e and e.map == mapID then
            hit[#hit + 1] = { d = d, map = mapID, x = e.x, y = e.y, label = e.label, detail = e.detail }
            has[d] = true
        end
    end
    local api = C_EncounterJournal
    if api and api.GetDungeonEntrancesForMap then
        local ok, list = pcall(api.GetDungeonEntrancesForMap, mapID)
        for _, e in ipairs(ok and type(list) == "table" and list or {}) do
            local x, y = xy(e.position)
            if x and e.name then
                for _, d in ipairs(self.list) do
                    if not has[d] and Dungeons.nameMatches(e.name, d.name) then
                        hit[#hit + 1] = { d = d, map = mapID, x = x, y = y, label = e.name, detail = e.description }
                        has[d] = true
                    end
                end
            end
        end
    end
    self.entranceCache[mapID] = hit
    return hit
end

---------------------------------------------------------------------------------
-- Opening, floors, back button
---------------------------------------------------------------------------------

-- The floor the player is standing on, or nil.
function Dungeons:PlayerFloor(d)
    local best = C_Map.GetBestMapForUnit("player")
    local hd, idx = self:ForMap(best)
    if hd == d then return idx end
end

function Dungeons:Open(d, floorIdx)
    local UI = M.UI
    floorIdx = floorIdx or self:PlayerFloor(d) or (d.portal and d.portal.floor) or 1
    local f = d.floors[floorIdx] or d.floors[1]
    if not f then return end
    UI.frame:Show()
    UI:SetMap(f.key)
    UI.canvas:Fit()
end

-- Open the dungeon the given map belongs to (used for "go to player" inside an instance). True if it did.
function Dungeons:OpenForMap(mapID)
    if not M.db.dungeons then return false end
    local d, idx = self:ForMap(mapID)
    if not d then return false end
    self:Open(d, idx)
    return true
end

local BAR_FLOORS = 12

function Dungeons:CreateBar()
    local W, UI = M.Widgets, M.UI
    local bar = CreateFrame("Frame", nil, UI.frame, "BackdropTemplate")
    W.Panel(bar)
    bar:SetHeight(26)
    bar:SetPoint("TOPLEFT", UI.canvas.view, "TOPLEFT", 8, -8)
    bar:SetFrameLevel(UI.canvas.pinLayer:GetFrameLevel() + 100)
    bar.back = CreateFrame("Button", nil, bar, "UIPanelButtonTemplate")
    bar.back:SetSize(90, 20)
    bar.back:SetPoint("LEFT", 4, 0)
    bar.back:SetScript("OnClick", function() self:Back() end)
    bar.title = bar:CreateFontString(nil, "OVERLAY", "MeridianFontGold")
    bar.title:SetPoint("LEFT", bar.back, "RIGHT", 8, 0)
    bar.floors = {}
    for i = 1, BAR_FLOORS do
        local b = CreateFrame("Button", nil, bar, "UIPanelButtonTemplate")
        b:SetSize(24, 20)
        b:SetText(tostring(i))
        b:SetScript("OnClick", function()
            local d = self.current
            if d and d.floors[i] then UI:SetMap(d.floors[i].key); UI.canvas:Fit() end
        end)
        b:SetScript("OnEnter", function(s)
            local d = self.current
            local fl = d and d.floors[i]
            if not fl then return end
            GameTooltip:SetOwner(s, "ANCHOR_BOTTOM")
            GameTooltip:SetText(fl.label, 1, 1, 1)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        bar.floors[i] = b
    end
    self.bar = bar
    return bar
end

-- Called by UI:SetMap for every map change: show the floor bar while a dungeon is on screen.
function Dungeons:OnMapChanged(key, prev)
    if not self.byKey then if self.bar then self.bar:Hide() end; return end
    local d, idx = self:ForMap(key)
    if not d then
        self.current, self.currentFloor = nil, nil
        if self.bar then self.bar:Hide() end
        return
    end
    if not self:ForMap(prev) then self.from = prev end -- remember the map to go back to
    self.current, self.currentFloor = d, idx
    local bar = self.bar or self:CreateBar()
    local back = self.from or (d.entrance and d.entrance.map)
    bar.back:SetEnabled(back ~= nil)
    bar.back:SetText(L["Back"])
    bar.title:SetText(d.name)
    local x = bar.title:GetStringWidth() + 8
    local n = #d.floors
    for i = 1, BAR_FLOORS do
        local b = bar.floors[i]
        if i <= n and n > 1 then
            b:ClearAllPoints()
            b:SetPoint("LEFT", bar.title, "RIGHT", 10 + (i - 1) * 26, 0)
            b:SetText(i == idx and ("[" .. i .. "]") or tostring(i)) -- current floor is bracketed, not just disabled
            b:SetEnabled(i ~= idx)
            b:Show()
        else
            b:Hide()
        end
    end
    local floorsW = n > 1 and (10 + n * 26) or 0
    bar:SetWidth(4 + 90 + 8 + x + floorsW + 8)
    bar:Show()
end

function Dungeons:Back()
    local UI = M.UI
    local to = self.from
    if not to and self.current and self.current.entrance then to = self.current.entrance.map end
    if to then UI:SetMap(to) end
end

function Dungeons:Toggle()
    M.db.dungeons = not M.db.dungeons
    if not M.db.dungeons and self.bar then self.bar:Hide() end
    M.UI:RefreshAll()
    M.UI:SyncToolbar()
    M:Print(L["Dungeon maps"] .. ":", M.db.dungeons and "on" or "off")
end

---------------------------------------------------------------------------------
-- Markers
---------------------------------------------------------------------------------

local nextIdx = {} -- entrance group key -> which dungeon the next click opens

local function entranceMarkers(self, c, zoneID)
    local cr, cg, cb = M.Overlay.markerColor("dungeon")
    for _, g in ipairs(Dungeons.groupEntrances(Dungeons:EntrancesOn(zoneID))) do
        local names = {}
        for i, e in ipairs(g.items) do names[i] = e.d.name end
        local multi = #g.items > 1
        self:AddMarker(zoneID, { x = g.x, y = g.y, pin = "dungeon", size = 18, r = cr, g = cg, b = cb, kind = "dungeon",
            title = multi and L["Dungeons"] or g.items[1].d.name,
            lines = multi and names or { g.items[1].detail or L["Dungeon"] },
            hint = multi and L["Click: open the dungeon map. Click again for the next one here."] or L["Click: open the dungeon map."],
            onClick = function(_, btn)
                if btn ~= "LeftButton" then return end
                local i = nextIdx[g.key] or 1
                if i > #g.items then i = 1 end
                nextIdx[g.key] = i + 1
                Dungeons:Open(g.items[i].d)
            end })
    end
end

local function interiorMarkers(self, c, d, idx)
    local fl = d.floors[idx]
    local cr, cg, cb = M.Overlay.markerColor("dungeon")
    local p = d.portal
    if p and (p.floor or 1) == idx and p.x and p.y then
        self:AddMarker(fl.key, { x = p.x, y = p.y, pin = "dungeon", size = 18, r = cr, g = cg, b = cb, kind = "dungeon",
            title = L["Entrance"], lines = { d.name } })
    end
    if not (d.quests and d.turnins and C_QuestLog) then return end
    local function logged(id) return C_QuestLog.GetLogIndexForQuestID and C_QuestLog.GetLogIndexForQuestID(id) ~= nil end
    local function ready(id) return logged(id) and C_QuestLog.IsComplete and C_QuestLog.IsComplete(id) and true or false end
    local faction = UnitFactionGroup and UnitFactionGroup("player")
    local state = { level = UnitLevel("player"), faction = faction, greyRange = M.db.greyRange, logged = logged,
        done = function(id) return C_QuestLog.IsQuestFlaggedCompleted and C_QuestLog.IsQuestFlaggedCompleted(id) or false end }
    for _, t in ipairs(d.turnins) do
        if (t.floor or 1) == idx and t.x and t.y then
            if M.db.turnin then
                local rq = Dungeons.turninQuests(t.npc, d.quests, ready)
                if #rq > 0 then
                    local tr, tg, tb = M.Overlay.markerColor("turnin")
                    local lines = {}
                    for i, q in ipairs(rq) do lines[i] = q.name end
                    self:AddMarker(fl.key, { x = t.x, y = t.y, pin = "turnin", size = 18, r = tr, g = tg, b = tb, kind = "turnin",
                        title = t.npc, lines = lines, questID = rq[1].id })
                end
            end
            if M.db.avail then
                local oq = Dungeons.offerQuests(t.npc, d.quests, function(q) return Dungeons.canOffer(q, state) end)
                if #oq > 0 then
                    local gr, gg, gb = M.Overlay.markerColor("give")
                    local lines = {}
                    for i, q in ipairs(oq) do lines[i] = q.name .. (q.level and (" (" .. q.level .. ")") or "") end
                    self:AddMarker(fl.key, { x = t.x, y = t.y - 0.025, pin = "give", size = 16, r = gr, g = gg, b = gb, kind = "give",
                        title = t.npc, lines = lines, questID = oq[1].id })
                end
            end
        end
    end
end

M.Overlay.RegisterSource("dungeons", function(self, c)
    if not (M.db.dungeons and c == M.UI.canvas) then return end
    local d, idx = Dungeons:ForMap(c.mapID)
    if d then return interiorMarkers(self, c, d, idx) end
    for zoneID in pairs(c.zones) do
        if zoneID > 0 then entranceMarkers(self, c, zoneID) end
    end
end)
