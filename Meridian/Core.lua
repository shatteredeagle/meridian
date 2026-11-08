local ADDON, M = ...
_G.Meridian = M

M.defaults = { zoomMin = 0.5, zoomMax = 4, opacity = 0.75, reveal = "full", overlays = true, tracker = true, mini = false, miniSize = 220, miniZoom = 1.5, miniRound = true, avail = false, turnin = true, greyRange = 7, arrow = false, blizzWay = true, claimWay = true, wayArrive = 10, arrowStyle = 1, iconScale = 1, sortMode = "zone", palette = "default", fontScale = 1, contrast = false, superTrack = true, launcher = true, launcherAngle = 225, miniCoords = true, scale = 1, alpha = 1, locked = false, width = 900, height = 600 }

local function initDB()
    MeridianDB = MeridianDB or {}
    for k, v in pairs(M.defaults) do
        if MeridianDB[k] == nil then MeridianDB[k] = v end
    end
    MeridianDB.hidden = MeridianDB.hidden or {}
    MeridianDB.waypoints = MeridianDB.waypoints or {}
    MeridianDB.collapsed = MeridianDB.collapsed or {}
    M.db = MeridianDB
end

-- Key binding labels (Bindings.xml)
BINDING_HEADER_MERIDIAN = "Meridian"
BINDING_NAME_MERIDIAN_TOGGLE = "Toggle map"
BINDING_NAME_MERIDIAN_MINIMAP = "Toggle minimap"
BINDING_NAME_MERIDIAN_ARROW = "Toggle direction arrow"
BINDING_NAME_MERIDIAN_CENTER = "Center map on player"
BINDING_NAME_MERIDIAN_LIST = "Toggle quest list"

function M:Print(...) print("|cff66ccffMeridian|r:", ...) end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function(_, event, name)
    if event == "ADDON_LOADED" and name == ADDON then
        initDB()
    elseif event == "PLAYER_LOGIN" then
        M.Widgets.ApplyFonts()
        M.UI:Create()
        M.Widgets.ApplyContrast()
        M.Way:Init()
        M.Options:Register()
        M.Launcher:Create()
    end
end)

SLASH_MERIDIAN1 = "/meridian"
SLASH_MERIDIAN2 = "/mm"
SlashCmdList.MERIDIAN = function(raw)
    local cmd, rest = (raw or ""):match("^(%S*)%s*(.-)%s*$")
    local msg = cmd:lower()
    if msg == "way" then
        M.Way:Slash(rest)
    elseif msg == "config" or msg == "options" or msg == "settings" then
        M.Options:Open()
    elseif msg == "reset" then
        M.UI:ResetView()
    elseif msg == "arrow" then
        M.Arrow:Toggle()
    elseif msg == "givers" then
        M.UI:ToggleGivers()
    elseif msg == "turnins" then
        M.db.turnin = not M.db.turnin
        M.UI:RefreshAll()
        M:Print("Turn-in markers:", M.db.turnin and "on" or "off")
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
