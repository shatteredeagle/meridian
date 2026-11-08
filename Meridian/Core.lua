local ADDON, M = ...
_G.Meridian = M

M.defaults = { zoomMin = 0.5, zoomMax = 4, opacity = 0.75, reveal = "full", overlays = true, tracker = true, mini = false, miniSize = 220, miniZoom = 1.5, miniRound = true, avail = false, greyRange = 7, arrow = false, blizzWay = true, claimWay = true, wayArrive = 10, iconScale = 1, width = 900, height = 600 }

local function initDB()
    MeridianDB = MeridianDB or {}
    for k, v in pairs(M.defaults) do
        if MeridianDB[k] == nil then MeridianDB[k] = v end
    end
    MeridianDB.hidden = MeridianDB.hidden or {}
    MeridianDB.waypoints = MeridianDB.waypoints or {}
    M.db = MeridianDB
end

function M:Print(...) print("|cff66ccffMeridian|r:", ...) end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function(_, event, name)
    if event == "ADDON_LOADED" and name == ADDON then
        initDB()
    elseif event == "PLAYER_LOGIN" then
        M.UI:Create()
        M.Way:Init()
    end
end)

SLASH_MERIDIAN1 = "/meridian"
SLASH_MERIDIAN2 = "/mm"
SlashCmdList.MERIDIAN = function(raw)
    local cmd, rest = (raw or ""):match("^(%S*)%s*(.-)%s*$")
    local msg = cmd:lower()
    if msg == "way" then
        M.Way:Slash(rest)
    elseif msg == "reset" then
        M.UI:ResetView()
    elseif msg == "arrow" then
        M.Arrow:Toggle()
    elseif msg == "givers" then
        M.UI:ToggleGivers()
    elseif msg == "round" then
        M.db.miniRound = not M.db.miniRound
        M:Print("Round minimap:", M.db.miniRound and "on" or "off", "- /reload to apply")
    elseif msg == "mini" then
        M.UI:ToggleMini()
    elseif msg == "reveal" then
        M.UI:ToggleReveal()
    elseif msg == "data" then
        M:Print("QuestieDB:", _G.LibQuestieDB and "found" or "missing",
            "| ZoneDB:", (_G.QuestieLoader and _G.QuestieLoader:ImportModule("ZoneDB")) and "found" or "missing",
            "| source:", M.Data:Available() and "QuestieDB areas" or "Blizzard POIs",
            "| reveal data:", (_G.ZGV and _G.ZGV.Foglight and _G.ZGV.Foglight.DataProvider.data) and "Zygor Foglight" or "none (explored areas only)")
    else
        M.UI:Toggle()
    end
end
