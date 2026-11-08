-- Quest data from the user's installed QuestieDB addon (read at runtime; nothing is bundled).
-- Pure helpers (eligible, anyBit) are testable offline; the rest needs the game.
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

-- True if masks a and b share a set bit (WoW's Lua 5.1 has no & operator; this stays portable).
function Data.anyBit(a, b)
    for i = 0, 30 do
        local bit = 2 ^ i
        if math.floor(a / bit) % 2 == 1 and math.floor(b / bit) % 2 == 1 then return true end
    end
    return false
end

-- Can the player pick this quest up? q: static quest info; p: player state with done()/inLog() predicates.
function Data.eligible(q, p)
    if p.inLog(q.id) or p.done(q.id) then return false end
    if q.reqLevel and q.reqLevel > p.level then return false end
    if q.level and q.level >= 0 and q.level < p.level - p.greyRange then return false end
    if q.races and q.races ~= 0 and p.raceMask and not Data.anyBit(q.races, p.raceMask) then return false end
    if q.classes and q.classes ~= 0 and p.classMask and not Data.anyBit(q.classes, p.classMask) then return false end
    for _, id in ipairs(q.group or {}) do
        if not p.done(id) then return false end
    end
    if q.single and #q.single > 0 then
        local any = false
        for _, id in ipairs(q.single) do if p.done(id) then any = true; break end end
        if not any then return false end
    end
    for _, id in ipairs(q.exclusive or {}) do
        if p.done(id) then return false end
    end
    return true
end

-- uiMapID -> array of {x, y} (0..1) for the given NPC and object IDs.
local function bucket(db, zones, npcIds, objectIds)
    local out = {}
    local function take(spawns)
        if not spawns then return end
        for areaId, list in pairs(spawns) do
            local ui = zones:GetUiMapIdByAreaId(areaId)
            if ui then
                local b = out[ui]
                if not b then b = {}; out[ui] = b end
                for _, c in ipairs(list) do
                    if c[1] and c[1] >= 0 then b[#b + 1] = { c[1] / 100, c[2] / 100 } end
                end
            end
        end
    end
    for _, id in ipairs(npcIds) do take(db.Npc.spawns(id)) end
    for _, id in ipairs(objectIds) do take(db.Object.spawns(id)) end
    return out
end

local areaCache = {} -- questID -> { [uiMapID] = areas }

-- Objective areas for one quest on every map at once (cached; the database is static).
function Data:QuestAreasAll(questID)
    local hit = areaCache[questID]
    if hit then return hit end
    local db, zones = _G.LibQuestieDB, zoneDB()
    local obj = db.Quest.objectives(questID)
    local result = {}
    if obj then
        local npcs, objects = {}, {}
        for _, c in ipairs(obj[1] or {}) do npcs[#npcs + 1] = c[1] end
        for _, o in ipairs(obj[2] or {}) do objects[#objects + 1] = o[1] end
        for _, it in ipairs(obj[3] or {}) do -- item objectives: where the item drops
            for _, n in ipairs(db.Item.npcDrops(it[1]) or {}) do npcs[#npcs + 1] = n end
            for _, o in ipairs(db.Item.objectDrops(it[1]) or {}) do objects[#objects + 1] = o end
        end
        for _, c in ipairs(obj[5] or {}) do npcs[#npcs + 1] = c[1] end -- kill-credit objectives
        for ui, pts in pairs(bucket(db, zones, npcs, objects)) do
            result[ui] = M.Geometry.areas(pts)
        end
    end
    areaCache[questID] = result
    return result
end

local finCache = {} -- questID -> { [uiMapID] = { {x, y}, ... } }

-- Where a quest is handed in, by map (QuestieDB finishedBy; empty when the database lacks it).
function Data:QuestFinishers(questID)
    local hit = finCache[questID]
    if hit then return hit end
    local db, zones = _G.LibQuestieDB, zoneDB()
    local result = {}
    if db and zones and db.Quest.finishedBy then
        local fb = db.Quest.finishedBy(questID)
        if fb then result = bucket(db, zones, fb[1] or {}, fb[2] or {}) end
    end
    finCache[questID] = result
    return result
end

function Data:LogQuests()
    local out = {}
    for i = 1, C_QuestLog.GetNumQuestLogEntries() do
        local info = C_QuestLog.GetInfo(i)
        if info and not info.isHeader and info.questID then
            out[#out + 1] = { questID = info.questID, title = info.title, complete = C_QuestLog.IsComplete(info.questID) and true or false }
        end
    end
    return out
end

-- Overlay provider: areas for every quest in the player's log on one map.
function Data:Provider(uiMapID)
    local out = {}
    if not self:Available() then return out end
    for _, q in ipairs(self:LogQuests()) do
        for _, a in ipairs(self:QuestAreasAll(q.questID)[uiMapID] or {}) do
            out[#out + 1] = { questID = q.questID, x = a.x, y = a.y, radius = a.radius }
        end
    end
    return out
end

---------------------------------------------------------------------------------
-- Quest givers ("available" quests)
---------------------------------------------------------------------------------

local infoCache = {}

local function questInfo(db, id)
    local q = infoCache[id]
    if not q then
        q = {
            id = id, name = db.Quest.name(id), level = db.Quest.questLevel(id), reqLevel = db.Quest.requiredLevel(id),
            races = db.Quest.requiredRaces(id), classes = db.Quest.requiredClasses(id),
            group = db.Quest.preQuestGroup(id), single = db.Quest.preQuestSingle(id), exclusive = db.Quest.exclusiveTo(id),
        }
        infoCache[id] = q
    end
    return q
end

-- Index every quest's starter spawns by map, in slices so the game doesn't hitch. Calls onDone when finished.
function Data:BuildStarters(onDone)
    if self.starters or self.building or not self:Available() then return end
    self.building = true
    local db, zones = _G.LibQuestieDB, zoneDB()
    local ids = db.Quest.GetAllIds()
    local starters, i = {}, 1
    local function step()
        local stop = math.min(i + 149, #ids)
        for k = i, stop do
            local id = ids[k]
            local sb = db.Quest.startedBy(id)
            if sb then
                for ui, pts in pairs(bucket(db, zones, sb[1] or {}, sb[2] or {})) do
                    local list = starters[ui]
                    if not list then list = {}; starters[ui] = list end
                    for _, p in ipairs(pts) do list[#list + 1] = { id, p[1], p[2] } end
                end
            end
        end
        i = stop + 1
        if i <= #ids then
            C_Timer.After(0, step)
        else
            self.starters, self.building = starters, nil
            if onDone then onDone() end
        end
    end
    step()
end

local function playerState(db)
    local _, classFile = UnitClass("player")
    local _, _, raceID = UnitRace("player")
    return {
        level = UnitLevel("player"), greyRange = M.db.greyRange,
        raceMask = db.Enum.raceMaskById[raceID], classMask = db.Enum.classKeys[classFile],
        done = function(id) return C_QuestLog.IsQuestFlaggedCompleted(id) end,
        inLog = function(id) return C_QuestLog.GetLogIndexForQuestID(id) ~= nil end,
    }
end

-- Giver markers for quests the player can accept, on one map: array of {questID, x, y, name, level}.
function Data:Available(uiMapID, state)
    local out = {}
    if not self.starters then return out end
    local db = _G.LibQuestieDB
    local seen = {}
    for _, s in ipairs(self.starters[uiMapID] or {}) do
        local id = s[1]
        if not seen[id .. ":" .. s[2] .. ":" .. s[3]] then
            seen[id .. ":" .. s[2] .. ":" .. s[3]] = true
            local q = questInfo(db, id)
            if Data.eligible(q, state) then out[#out + 1] = { questID = id, x = s[2], y = s[3], name = q.name, level = q.level } end
        end
    end
    return out
end

function Data:PlayerState() return playerState(_G.LibQuestieDB) end
