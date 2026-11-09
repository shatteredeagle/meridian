-- Optional, off by default: gamepad control of the main map. Left stick pans, triggers zoom, shoulders cycle quests,
-- face buttons: 1 (A) waypoint at the crosshair, 3 (X) centre on you, 2 (B) close, 4 (Y) quest list, Back pins. Nothing is registered until it is switched on, so it costs
-- nothing when unused. Stick and button identifiers are unverified guesses (see docs/test-checklist.md).
local ADDON, M = ...

local Pad = {}
M.Pad = Pad

local Math = M.Math

-- Radial dead zone, then a squared response so small deflections move slowly. Returns the pan in px for dt seconds.
-- x, y in -1..1 (y up). Output sign follows the canvas offset: pushing right moves the canvas left.
function Pad.panDelta(x, y, dt, speed, dead)
    local len = math.sqrt(x * x + y * y)
    dead = dead or 0.2
    if len <= dead then return 0, 0 end
    local scaled = (len - dead) / (1 - dead)
    local k = scaled * scaled * speed * dt / len
    return -x * k, y * k
end

-- Index after stepping through n items with wraparound (step = +1 / -1; cur may be nil).
function Pad.cycle(cur, n, step)
    if n <= 0 then return nil end
    if not cur then return step > 0 and 1 or n end
    return (cur - 1 + step) % n + 1
end

local ZOOM_KEYS = { PADRTRIGGER = 1.25, PADLTRIGGER = 1 / 1.25 }

function Pad:Cycle(step)
    local ids = M.Tracker.orderIds or {}
    local cur
    for i, id in ipairs(ids) do if id == self.current then cur = i end end
    local i = Pad.cycle(cur, #ids, step)
    if not i then return end
    self.current = ids[i]
    M.UI.overlay.pinned = { [self.current] = true }
    M.UI.overlay:SetHighlight(M.UI.overlay.pinned)
    M.Tracker:Focus(self.current)
end

function Pad:OnButton(button)
    local ui, c = M.UI, M.UI.canvas
    if ZOOM_KEYS[button] then
        c:SetZoom(c.zoom * ZOOM_KEYS[button])
    elseif button == "PAD1" then
        -- drop a waypoint under the crosshair
        if M.Way:AddAtCanvas(c, c:ViewCenterOnCanvas()) and not M.db.arrow then M.Arrow:Toggle() end
    elseif button == "PAD3" then
        ui:CenterOnPlayer()
    elseif button == "PADBACK" then
        ui:TogglePin()
    elseif button == "PADDUP" then
        self:Cycle(-1)
    elseif button == "PADDDOWN" then
        self:Cycle(1)
    elseif button == "PAD2" then
        ui.frame:Hide()
    elseif button == "PAD4" then
        ui:ToggleTracker()
    elseif button == "PADRSHOULDER" then
        self:Cycle(1)
    elseif button == "PADLSHOULDER" then
        self:Cycle(-1)
    end
end

-- Turn the handlers on or off to match M.db.controller. Safe to call any time.
function Pad:Apply()
    local f = M.UI and M.UI.frame
    if not f then return end
    local on = M.db.controller and true or false
    if on and not self.hooked then
        self.hooked = true
        f:SetScript("OnGamePadButtonDown", function(_, button) if self.enabled then self:OnButton(button) end end)
        f:SetScript("OnGamePadStick", function(_, stick, x, y)
            if not self.enabled then return end
            -- every stick pans except one that looks like a camera/right stick, which zooms with vertical push
            local s = tostring(stick):lower()
            if s:find("camera") or s:find("right") then self.zoomPush = y or 0 else self.px, self.py = x or 0, y or 0 end
        end)
        f:HookScript("OnUpdate", function(_, dt)
            if not self.enabled then return end
            local c = M.UI.canvas
            if self.px and (self.px ~= 0 or self.py ~= 0) then
                local dx, dy = Pad.panDelta(self.px, self.py, dt, 600)
                c:SetOffset(c.offX + dx, c.offY + dy)
            end
            if self.zoomPush and math.abs(self.zoomPush) > 0.3 then
                c:SetZoom(c.zoom * (1 + self.zoomPush * dt * 1.5))
            end
        end)
        f.padHint = f:CreateFontString(nil, "OVERLAY", "MeridianFontWhite")
        f.padHint:SetPoint("BOTTOMRIGHT", -26, 6)
        f.padHint:SetText("Stick pan | Triggers zoom | Shoulders/D-pad quests | A waypoint at + | X me | B close | Y list | Back pin")
        -- crosshair marking where A drops a waypoint
        local holder = CreateFrame("Frame", nil, M.UI.canvas.view)
        holder:SetAllPoints()
        holder:SetFrameLevel(M.UI.canvas.view:GetFrameLevel() + 50)
        f.padCross = holder:CreateTexture(nil, "OVERLAY")
        f.padCross:SetTexture("Interface\\AddOns\\Meridian\\Media\\icons\\pin")
        f.padCross:SetSize(18, 18)
        f.padCross:SetAlpha(0.8)
        f.padCross:SetPoint("CENTER", holder, "CENTER")
        f.padHolder = holder
    end
    self.enabled = on
    if self.hooked then
        f:EnableGamePadButton(on)
        f:EnableGamePadStick(on)
        f.padHint:SetShown(on)
        f.padHolder:SetShown(on)
        if not on then self.px, self.py, self.zoomPush = nil end
    end
end
