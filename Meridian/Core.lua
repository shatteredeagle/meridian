local ADDON, M = ...
local L = M.L
_G.Meridian = M

M.defaults = { zoomMin = 0.5, zoomMax = 4, opacity = 0.75, reveal = "full", overlays = true, tracker = true, mini = false, miniSize = 220, miniZoom = 1.5, miniRound = false, avail = false, turnin = true, greyRange = 7, arrow = false, blizzWay = true, claimWay = true, wayArrive = 10, arrowStyle = 1, iconScale = 1, sortMode = "zone", palette = "default", fontScale = 1, controller = false, polestarRoute = true, mapKey = false, pinTaxi = true, pinRare = false, pinPoi = false, dungeons = true, blend = true, pin = false, openView = true, contrast = false, superTrack = true, launcher = true, launcherAngle = 225, miniCoords = true, scale = 1, alpha = 1, locked = false, width = 900, height = 600 }

local function initDB()
    MeridianDB = MeridianDB or {}
    for k, v in pairs(M.defaults) do
        if MeridianDB[k] == nil then MeridianDB[k] = v end
    end
    MeridianDB.hidden = MeridianDB.hidden or {}
    MeridianDB.waypoints = MeridianDB.waypoints or {}
    MeridianDB.collapsed = MeridianDB.collapsed or {}
    MeridianDB.taxi = MeridianDB.taxi or {}
    M.db = MeridianDB
end

-- Key binding labels (Bindings.xml)
BINDING_HEADER_MERIDIAN = "Meridian"
BINDING_NAME_MERIDIAN_TOGGLE = L["Toggle map"]
BINDING_NAME_MERIDIAN_MINIMAP = L["Toggle minimap"]
BINDING_NAME_MERIDIAN_ARROW = L["Toggle direction arrow"]
BINDING_NAME_MERIDIAN_CENTER = L["Center map on player"]
BINDING_NAME_MERIDIAN_LIST = L["Toggle quest list"]
BINDING_NAME_MERIDIAN_PIN = L["Pin map to character"]

-- Optional: the key(s) bound to Blizzard's world map open Meridian instead. Override bindings can't change in combat,
-- so a change made then waits for combat to end. Turning it off clears our overrides and the stock binding returns.
local keyOwner = CreateFrame("Frame")
keyOwner:SetScript("OnEvent", function(self) self:UnregisterEvent("PLAYER_REGEN_ENABLED"); M:ApplyMapKey() end)
function M:ApplyMapKey()
    if InCombatLockdown() then return keyOwner:RegisterEvent("PLAYER_REGEN_ENABLED") end
    ClearOverrideBindings(keyOwner)
    if not M.db.mapKey then return end
    local k1, k2 = GetBindingKey("TOGGLEWORLDMAP")
    if not k1 then k1 = "M" end
    SetOverrideBinding(keyOwner, true, k1, "MERIDIAN_TOGGLE")
    if k2 then SetOverrideBinding(keyOwner, true, k2, "MERIDIAN_TOGGLE") end
end

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
        M.Pad:Apply()
        M.Pins:Apply()
        M.Way:Init()
        M.Options:Register()
        M.Launcher:Create()
        M:ApplyMapKey()
        M.Route:Init()
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
    elseif msg == "find" or msg == "search" then
        M.UI.frame:Show()
        M.Search.box:SetText(rest)
        M.Search.box:SetFocus()
    elseif msg == "here" then
        M.UI.frame:Show()
        M.Search:Here()
    elseif msg == "pad" then
        M.db.controller = not M.db.controller
        M.Pad:Apply()
        M:Print("Controller support:", M.db.controller and "on" or "off")
    elseif msg == "art" or msg:match("^art ") then
        local arg = msg:match("^art%s+(%S+)")
        if arg == "shift" then
            local dx, dy = msg:match("^art%s+shift%s+(-?[%d%.]+)%s+(-?[%d%.]+)")
            if dx then M.db.artDx, M.db.artDy = tonumber(dx), tonumber(dy); M.UI.canvas:Rebuild() end
            M:Print("Pixel art shift (canvas px): auto", M.Art.shift and string.format("%.1f, %.1f", M.Art.shift[1], M.Art.shift[2]) or "-", "extra", M.db.artDx or 0, M.db.artDy or 0, "(usage: /mm art shift dx dy)")
        else
            M.Art:Set(arg)
        end
    elseif msg == "pin" then
        M:Print("Map pinned to you:", M.UI:TogglePin() and "on" or "off")
    elseif msg == "blend" then
        M.db.blend = not M.db.blend
        M.UI.canvas:Rebuild()
        if M.UI.mini then M.UI.mini.canvas:Rebuild() end
        M:Print("Blend zone edges:", M.db.blend and "on" or "off")
    elseif msg == "dungeons" then
        M.Dungeons:Toggle()
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
    elseif msg == "overlays" then
        -- diagnostic for "reveal map leaves terrain hidden": what each source offers per zone. The full table is saved
        -- to MeridianDB.diag (readable in the SavedVariables file after /reload); one line is printed for the current zone.
        local zgv = _G.ZGV
        local data = zgv and zgv.Foglight and zgv.Foglight.DataProvider and zgv.Foglight.DataProvider.data
        local function line(id)
            local explored = C_MapExplorationInfo.GetExploredMapTextures(id) or {}
            local info = C_Map.GetMapInfo(id)
            return string.format("%d %s explored=%d zygor=%d drawn=%d", id, info and info.name or "?", #explored,
                data and data[id] and #data[id] or 0, #M.OverlaysFor(id, true))
        end
        local ids = {}
        for id in pairs(data or {}) do ids[#ids + 1] = id end
        table.sort(ids)
        local out = { "reveal=" .. tostring(M.db.reveal), "zygor data=" .. (data and "loaded" or "MISSING") }
        for _, id in ipairs(ids) do out[#out + 1] = line(id) end
        M.db.diag = out
        local here = tonumber(rest) or C_Map.GetBestMapForUnit("player")
        M:Print(line(here), "| full table saved: /reload, then it is in MeridianDB.diag")
    elseif msg == "data" then
        M:Print("QuestieDB:", _G.LibQuestieDB and "found" or "missing",
            "| ZoneDB:", (_G.QuestieLoader and _G.QuestieLoader:ImportModule("ZoneDB")) and "found" or "missing",
            "| source:", M.Data:Available() and "QuestieDB areas" or "Blizzard POIs",
            "| reveal data:", (_G.ZGV and _G.ZGV.Foglight and _G.ZGV.Foglight.DataProvider.data) and "Zygor Foglight" or "none (explored areas only)")
    else
        M.UI:Toggle()
    end
end
