-- Detail lines for quest tooltips. Plain hover stays short; holding Shift adds rewards, prerequisites and chains.
-- Text builders are pure (tested offline); the tooltip calls need the game.
local ADDON, M = ...

local Tip = {}
M.Tip = Tip

---------------------------------------------------------------------------------
-- Pure helpers
---------------------------------------------------------------------------------

-- 12345 -> "1g 23s 45c" (zero parts left out).
function Tip.moneyText(copper)
    copper = math.floor(copper or 0)
    if copper <= 0 then return nil end
    local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
    local parts = {}
    if g > 0 then parts[#parts + 1] = g .. "g" end
    if s > 0 then parts[#parts + 1] = s .. "s" end
    if c > 0 then parts[#parts + 1] = c .. "c" end
    return table.concat(parts, " ")
end

-- Prerequisite and chain lines for a quest record ({group, single, exclusive, reqLevel, level}).
-- nameOf(id) -> string|nil; next is the following quest id (or nil).
function Tip.chainLines(q, nameOf, nextId)
    local out = {}
    local function names(ids)
        local n = {}
        for _, id in ipairs(ids) do n[#n + 1] = nameOf(id) or ("Quest " .. id) end
        return table.concat(n, ", ")
    end
    if q.reqLevel and q.reqLevel > 0 then out[#out + 1] = "Requires level " .. q.reqLevel end
    if q.group and #q.group > 0 then out[#out + 1] = "After all of: " .. names(q.group) end
    if q.single and #q.single > 0 then
        out[#out + 1] = (#q.single == 1 and "After: " or "After one of: ") .. names(q.single)
    end
    if q.exclusive and #q.exclusive > 0 then out[#out + 1] = "Not with: " .. names(q.exclusive) end
    if nextId then out[#out + 1] = "Leads to: " .. (nameOf(nextId) or ("Quest " .. nextId)) end
    return out
end

-- "12" or "12-14" for a creature's level range.
function Tip.levelRange(lo, hi)
    if not lo or lo <= 0 then return nil end
    if hi and hi > lo then return lo .. "-" .. hi end
    return tostring(lo)
end

---------------------------------------------------------------------------------
-- Game side
---------------------------------------------------------------------------------

local GREY = 0.65

-- XP, money and item rewards of a quest in the log (the log must have the data cached).
function Tip.rewardLines(tt, questID)
    local xp = GetQuestLogRewardXP and GetQuestLogRewardXP(questID)
    if xp and xp > 0 then tt:AddLine("Reward: " .. xp .. " XP", 0.6, 1, 0.6) end
    local money = GetQuestLogRewardMoney and Tip.moneyText(GetQuestLogRewardMoney(questID))
    if money then tt:AddLine("Reward: " .. money, 0.6, 1, 0.6) end
    if GetNumQuestLogRewards and GetQuestLogRewardInfo then
        for i = 1, GetNumQuestLogRewards(questID) do
            local name, _, count = GetQuestLogRewardInfo(i, questID)
            if name then tt:AddLine("Reward: " .. name .. ((count or 1) > 1 and (" x" .. count) or ""), 0.6, 1, 0.6) end
        end
    end
end

function Tip.prereqLines(tt, questID)
    local q = M.Data:QuestInfo(questID)
    if not q then return end
    for _, l in ipairs(Tip.chainLines(q, function(id) return M.Data:QuestName(id) end, M.Data:NextInChain(questID))) do
        tt:AddLine(l, GREY, GREY, GREY, true)
    end
end

-- Add the Shift-detail block for a quest, or a hint to hold Shift.
function Tip.details(tt, questID, inLog)
    if not IsShiftKeyDown() then
        tt:AddLine("Hold Shift for rewards and prerequisites", 0.5, 0.5, 0.5)
        return
    end
    if inLog then Tip.rewardLines(tt, questID) end
    Tip.prereqLines(tt, questID)
end

-- Tooltips redraw when Shift is pressed or released while hovering: the hovered widget registers its redraw here.
function Tip.Track(fn) Tip.redraw = fn end

local ev = CreateFrame("Frame")
ev:RegisterEvent("MODIFIER_STATE_CHANGED")
ev:SetScript("OnEvent", function()
    if Tip.redraw and GameTooltip:IsShown() then Tip.redraw() end
end)
