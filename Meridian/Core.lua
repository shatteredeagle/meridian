local ADDON, M = ...
_G.Meridian = M

M.defaults = { zoomMin = 0.5, zoomMax = 4, overlayAlpha = 0.25, width = 900, height = 600 }

local function initDB()
    MeridianDB = MeridianDB or {}
    for k, v in pairs(M.defaults) do
        if MeridianDB[k] == nil then MeridianDB[k] = v end
    end
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
    end
end)

SLASH_MERIDIAN1 = "/meridian"
SLASH_MERIDIAN2 = "/mm"
SlashCmdList.MERIDIAN = function(msg)
    msg = (msg or ""):lower()
    if msg == "reset" then
        M.UI:ResetView()
    else
        M.UI:Toggle()
    end
end
