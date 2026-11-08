-- Find a zone, quest or quest-giver NPC by name and jump to it; list the quests available in a zone.
-- Ranking is pure (tested offline). Quest search over the whole database needs the QuestieDB starter index,
-- which is built on first use (the same index the quest-giver markers use).
local ADDON, M = ...

local Search = {}
M.Search = Search

---------------------------------------------------------------------------------
-- Pure helpers
---------------------------------------------------------------------------------

local KIND_ORDER = { zone = 1, dungeon = 2, npc = 3, quest = 4 }
local KIND_LABEL = { zone = "Zone", dungeon = "Dungeon", npc = "NPC", quest = "Quest" }
Search.KIND_LABEL = KIND_LABEL

-- 100 exact, 80 prefix, 60 start of a later word, 40 anywhere; nil for no match. Case-insensitive.
function Search.score(query, name)
    if not name or query == "" then return nil end
    local q, n = query:lower(), name:lower()
    if n == q then return 100 end
    if n:sub(1, #q) == q then return 80 end
    if n:find(" " .. q, 1, true) then return 60 end
    if n:find(q, 1, true) then return 40 end
    return nil
end

-- items: array of {name, kind, ...}. Best `limit` matches: score, then kind (zone, npc, quest), then shorter name.
function Search.rank(query, items, limit)
    query = (query or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local hits = {}
    for _, it in ipairs(items) do
        local s = Search.score(query, it.name)
        if s then hits[#hits + 1] = { item = it, score = s } end
    end
    table.sort(hits, function(a, b)
        if a.score ~= b.score then return a.score > b.score end
        local ka, kb = KIND_ORDER[a.item.kind] or 9, KIND_ORDER[b.item.kind] or 9
        if ka ~= kb then return ka < kb end
        if #a.item.name ~= #b.item.name then return #a.item.name < #b.item.name end
        return a.item.name < b.item.name
    end)
    local out = {}
    for i = 1, math.min(limit or 10, #hits) do out[i] = hits[i].item end
    return out
end

-- Text of a result row: the kind is always spelled out.
function Search.rowText(it)
    local s = "[" .. (KIND_LABEL[it.kind] or "?") .. "] " .. it.name
    if it.level and it.level > 0 then s = s .. " (" .. it.level .. ")" end
    return s
end

---------------------------------------------------------------------------------
-- Candidates and jumping
---------------------------------------------------------------------------------

local nameCache = {}
local function questName(id)
    local n = nameCache[id]
    if n == nil then n = M.Data:QuestName(id) or false; nameCache[id] = n end
    return n or nil
end

function Search:Candidates()
    local items = {}
    local dungeons = M.db.dungeons and M.Dungeons
    for _, m in ipairs(M.Way:MapList(true)) do
        if not (dungeons and dungeons:ForMap(m.id)) then items[#items + 1] = { kind = "zone", name = m.name, map = m.id } end
    end
    if dungeons then
        for _, it in ipairs(dungeons.searchItems(dungeons:List())) do items[#items + 1] = it end
    end
    local inLog = {}
    for _, q in ipairs(M.Data:LogQuests()) do
        inLog[q.questID] = true
        items[#items + 1] = { kind = "quest", name = q.title or ("Quest " .. q.questID), questID = q.questID, inLog = true }
    end
    local starters = M.Data.starters
    if starters then
        local seenNpc, seenQuest = {}, {}
        for ui, list in pairs(starters) do
            for _, s in ipairs(list) do
                local id, npc = s[1], s[4]
                if not inLog[id] and not seenQuest[id] then
                    seenQuest[id] = true
                    local n = questName(id)
                    if n then items[#items + 1] = { kind = "quest", name = n, questID = id } end
                end
                if npc and not seenNpc[npc] then seenNpc[npc] = ui end
            end
        end
        -- NPC names are looked up only for the givers on the maps currently on screen (cheap)
        local shown = M.UI.canvas.zones or {}
        for npc, ui in pairs(seenNpc) do
            if shown[ui] then
                local info = M.Data:SourceInfo(npc)
                if info and info.name then
                    items[#items + 1] = { kind = "npc", name = info.name, npc = npc, map = ui }
                end
            end
        end
    end
    return items
end

-- Target pin shown after a jump; right-click it to clear.
function Search:SetTarget(map, x, y, title)
    self.target = map and { map = map, x = x, y = y, title = title } or nil
    M.UI:RefreshAll()
end

function Search:Jump(it)
    local ui, c = M.UI, M.UI.canvas
    local map, x, y = it.map, it.x, it.y
    if it.kind == "zone" then
        ui:SetMap(map)
        self:SetTarget(nil)
        return
    elseif it.kind == "dungeon" then
        self:SetTarget(nil)
        return M.Dungeons:Open(it.dungeon)
    elseif it.kind == "npc" then
        for _, s in ipairs(M.Data.starters[map] or {}) do
            if s[4] == it.npc then x, y = s[2], s[3]; break end
        end
    elseif it.kind == "quest" and not map then
        local locs = M.Data:StarterLocations(it.questID)
        if #locs > 0 then
            map, x, y = locs[1].map, locs[1].x, locs[1].y
        elseif it.inLog then -- objective area of a logged quest
            for ui2, areas in pairs(M.Data:QuestAreasAll(it.questID)) do
                if areas[1] then map, x, y = ui2, areas[1].x, areas[1].y; break end
            end
        end
    end
    if not (map and x) then return M:Print("No known location for " .. it.name) end
    if not c.zones[map] then ui:SetMap(map) end
    self:SetTarget(map, x, y, it.name)
    local px, py = c:ZoneToCanvas(map, x, y)
    if px then
        if c.zoom < 1.5 then c:SetZoom(1.5) end
        c:CenterOnCanvas(px, py)
    end
end

M.Overlay.RegisterSource("search", function(self, c)
    local t = Search.target
    if not (t and c.zones[t.map]) then return end
    local cr, cg, cb = M.Overlay.markerColor("poi")
    self:AddMarker(t.map, { x = t.x, y = t.y, pin = "poi", size = 22, r = cr, g = cg, b = cb, title = t.title or "Search result",
        hint = "Right-click: clear.", onClick = function(_, btn) if btn == "RightButton" then Search:SetTarget(nil) end end })
end)

-- Quests the player could accept in a zone, as result items sorted by level then name.
function Search:AvailableIn(zoneID)
    local items = {}
    if not M.Data.starters then return items end
    for _, g in ipairs(M.Data:Available(zoneID, M.Data:PlayerState())) do
        items[#items + 1] = { kind = "quest", name = g.name or ("Quest " .. g.questID), level = g.level, questID = g.questID,
            map = zoneID, x = g.x, y = g.y, npc = g.npc }
    end
    table.sort(items, function(a, b)
        if (a.level or 0) ~= (b.level or 0) then return (a.level or 0) < (b.level or 0) end
        return a.name < b.name
    end)
    return items
end

---------------------------------------------------------------------------------
-- UI: search box in the toolbar, results list beneath it
---------------------------------------------------------------------------------

local MAX_RESULTS = 12

function Search:ShowResults(items, header)
    local list = self.list
    self.items = items
    for i = 1, MAX_RESULTS do
        local b = list.rows[i]
        local it = items[i]
        if it then
            b.item = it
            b.text:SetText(Search.rowText(it))
            b:Show()
        else
            b:Hide()
        end
    end
    list.header:SetText(header or "")
    list:SetHeight(24 + math.max(1, math.min(#items, MAX_RESULTS)) * 18)
    list:SetShown(#items > 0 or (header and header ~= ""))
end

function Search:Run(query)
    if #query < 2 then return self:ShowResults({}, "") end
    local needIndex = M.Data:Available() and not M.Data.starters
    if needIndex and not M.Data.building then
        M:Print("Indexing quests for search...")
        M.Data:BuildStarters(function() if self.box:GetText() == query then self:Run(query) end end)
    end
    local ranked = Search.rank(query, self:Candidates(), MAX_RESULTS)
    self:ShowResults(ranked, #ranked == 0 and "No matches" or (needIndex and "Quest index still building..." or ""))
end

function Search:Here()
    local c = M.UI.canvas
    local zone = C_Map.GetBestMapForUnit("player")
    if not (zone and c.zones[zone]) then
        local info = c.mapID and c.mapID > 0 and C_Map.GetMapInfo(c.mapID)
        zone = info and info.mapType ~= Enum.UIMapType.Continent and c.mapID or nil
    end
    if not zone then return M:Print("Open a zone first (double-click one on the continent).") end
    if not M.Data:Available() then return M:Print("Needs QuestieDB.") end
    if not M.Data.starters then
        M:Print("Indexing quests...")
        return M.Data:BuildStarters(function() self:Here() end)
    end
    local info = C_Map.GetMapInfo(zone)
    local items = self:AvailableIn(zone)
    self:ShowResults(items, "Available in " .. (info and info.name or "this zone") .. ": " .. #items)
end

function Search:Create(tb)
    local box = CreateFrame("EditBox", "MeridianSearchBox", tb, "InputBoxTemplate")
    box:SetSize(150, 20)
    box:SetPoint("RIGHT", tb, "RIGHT", -12, 0)
    box:SetAutoFocus(false)
    box:SetMaxLetters(40)
    box.hint = box:CreateFontString(nil, "OVERLAY", "MeridianFontWhite")
    box.hint:SetPoint("LEFT", 2, 0)
    box.hint:SetText("Search...")
    box.hint:SetAlpha(0.5)
    self.box = box

    local here = M.Widgets.IconButton(tb, "list", "Available here", "List the quests you could accept in this zone.", function() self:Here() end)
    here:SetPoint("RIGHT", box, "LEFT", -6, 0)

    local list = CreateFrame("Frame", nil, tb, "BackdropTemplate")
    M.Widgets.Panel(list)
    list:SetWidth(280)
    list:SetPoint("TOPRIGHT", box, "BOTTOMRIGHT", 4, -2)
    list:SetFrameStrata("DIALOG")
    list.header = list:CreateFontString(nil, "OVERLAY", "MeridianFontGold")
    list.header:SetPoint("TOPLEFT", 8, -6)
    list.rows = {}
    for i = 1, MAX_RESULTS do
        local b = CreateFrame("Button", nil, list)
        b:SetHeight(18)
        b:SetPoint("TOPLEFT", 4, -20 - (i - 1) * 18)
        b:SetPoint("RIGHT", -4, 0)
        b.text = b:CreateFontString(nil, "OVERLAY", "MeridianFontWhite")
        b.text:SetPoint("LEFT", 4, 0)
        b.text:SetPoint("RIGHT")
        b.text:SetJustifyH("LEFT")
        b.text:SetWordWrap(false)
        b:SetHighlightTexture("Interface\\Buttons\\WHITE8X8")
        b:GetHighlightTexture():SetVertexColor(1, 1, 1, 0.12)
        b:SetScript("OnClick", function(s)
            Search:Jump(s.item)
            list:Hide()
            box:SetText("")
            box:ClearFocus()
        end)
        list.rows[i] = b
    end
    list:Hide()
    self.list = list

    local pending
    box:SetScript("OnTextChanged", function(s)
        box.hint:SetShown(s:GetText() == "")
        local q = s:GetText()
        pending = q
        C_Timer.After(0.25, function() if pending == q and box:GetText() == q then self:Run(q) end end)
    end)
    box:SetScript("OnEnterPressed", function()
        local it = self.items and self.items[1]
        if it and list:IsShown() then list.rows[1]:Click() end
    end)
    box:SetScript("OnEscapePressed", function(s) s:SetText(""); s:ClearFocus(); list:Hide() end)
end
