-- Quest-area provider backed by the user's installed QuestieDB addon (read at runtime; no data is bundled).
local ADDON, M = ...

local Data = {}
M.Data = Data

local function zoneDB()
    local QL = _G.QuestieLoader
    return QL and QL:ImportModule("ZoneDB")
end

function Data:Available()
    return _G.LibQuestieDB ~= nil and zoneDB() ~= nil
end

-- Collect spawn points ({x,y} in 0..1) on uiMapID for a list of {kind, id} sources.
local function spawnsOnMap(db, zones, uiMapID, npcIds, objectIds, out)
    local function take(spawns)
        if not spawns then return end
        for areaId, list in pairs(spawns) do
            if zones:GetUiMapIdByAreaId(areaId) == uiMapID then
                for _, c in ipairs(list) do
                    if c[1] and c[1] >= 0 then out[#out + 1] = { c[1] / 100, c[2] / 100 } end
                end
            end
        end
    end
    for _, id in ipairs(npcIds) do take(db.Npc.spawns(id)) end
    for _, id in ipairs(objectIds) do take(db.Object.spawns(id)) end
end

-- Areas for one quest's objectives on a map. Returns array of {x, y, radius}.
function Data:QuestAreas(questID, uiMapID)
    local db, zones = _G.LibQuestieDB, zoneDB()
    local obj = db.Quest.objectives(questID)
    if not obj then return {} end
    local npcs, objects = {}, {}
    for _, c in ipairs(obj[1] or {}) do npcs[#npcs + 1] = c[1] end
    for _, o in ipairs(obj[2] or {}) do objects[#objects + 1] = o[1] end
    for _, it in ipairs(obj[3] or {}) do -- item objectives: where the item drops
        for _, n in ipairs(db.Item.npcDrops(it[1]) or {}) do npcs[#npcs + 1] = n end
        for _, o in ipairs(db.Item.objectDrops(it[1]) or {}) do objects[#objects + 1] = o end
    end
    for _, c in ipairs(obj[5] or {}) do npcs[#npcs + 1] = c[1] end -- kill-credit objectives
    local pts = {}
    spawnsOnMap(db, zones, uiMapID, npcs, objects, pts)
    return M.Geometry.areas(pts)
end

-- Overlay provider: every quest in the player's log.
function Data:Provider(uiMapID)
    local out = {}
    if not self:Available() then return out end
    for i = 1, C_QuestLog.GetNumQuestLogEntries() do
        local info = C_QuestLog.GetInfo(i)
        if info and not info.isHeader and info.questID then
            for _, a in ipairs(self:QuestAreas(info.questID, uiMapID)) do
                out[#out + 1] = { questID = info.questID, x = a.x, y = a.y, radius = a.radius }
            end
        end
    end
    return out
end
