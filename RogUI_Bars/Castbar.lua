-- ============================================================
-- RogUI / Modules / Castbar / Castbar.lua
-- MIGRATED: Unified event system (no standalone event frame)
-- Player castbar replacement.
-- Features: per-state colors, channel ticks, GCD spark,
-- latency zone, interrupt flash, Edit Mode anchor.
-- ============================================================

local API = RogUIAPI
if not API then return end

local DEFAULTS = {
    enabled           = false,
    hideBlizzard      = true,
    x                 = 0,
    y                 = -220,
    width             = 280,
    height            = 18,
    alpha             = 1.0,  -- NEW: Global castbar alpha
    colorCasting      = {0.2, 0.6, 1.0},
    colorChanneling   = {0.4, 1.0, 0.4},
    colorNonInterrupt = {0.6, 0.6, 0.6},
    colorInterrupted  = {1.0, 0.2, 0.2},
    colorFinished     = {1.0, 1.0, 0.4},
    colorEmpowered    = {1.0, 0.6, 0.0},
    colorBackground   = {0.0, 0.0, 0.0},
    colorLatency      = {0.7, 0.1, 0.1},
    colorGCD          = {1.0, 1.0, 1.0},
    showIcon          = true,
    showTimer         = true,
    showSpellName     = true,
    showGCD           = true,
    showLatency       = true,
    showChannelTicks  = true,
    finishedFlashDur  = 0.25,
    iconSize          = 20,
}

-- Use centralized DB (replaces local GetDB)
local function GetDB() return API.GetDB("RogUICastbarDB", DEFAULTS) end

-- ── Tick counts for common channeled spells ────────────────────────────────────
local CHANNEL_TICKS = {
    [15407]  = 5,  -- Mind Flay
    [391993] = 3,  -- Mind Flay: Insanity
    [228266] = 3,  -- Void Torrent
    [47540]  = 8,  -- Penance
    [198013] = 5,  -- Eye Beam
    [257044] = 5,  -- Rapid Fire
    [5143]   = 5,  -- Arcane Missiles
    [12051]  = 6,  -- Evocation
    [120360] = 3,  -- Barrage
    [212084] = 6,  -- Fel Barrage
    [190245] = 3,  -- Blade Dance? no — keep as example
}

-- ── Build castbar frame ────────────────────────────────────────────────────────
local f = CreateFrame("Frame", "RogUIPlayerCastbar", UIParent)
f:SetFrameStrata("MEDIUM")
f:SetFrameLevel(100)
f:SetSize(DEFAULTS.width, DEFAULTS.height)
f:SetMovable(true)
f:EnableMouse(true)
f:RegisterForDrag("LeftButton")
f:Hide()

-- NEW: Apply global castbar alpha on creation
f:SetAlpha(GetDB().alpha or DEFAULTS.alpha)

-- Background
local bg = f:CreateTexture(nil, "BACKGROUND")
bg:SetAllPoints(f)
bg:SetColorTexture(0, 0, 0, 0.75)
f.bg = bg

-- Border
local border = CreateFrame("Frame", nil, f, "BackdropTemplate")
border:SetAllPoints(f)
border:SetBackdropBorderTexture("Interface/Buttons/WHITE8X8")
    border:SetBackdropBorderSizeZ(1)
border:SetBackdropBorderColor(0, 0, 0, 0.8)
f.border = border

-- Fill bar
local bar = CreateFrame("StatusBar", nil, f)
bar:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
bar:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)
local barTex = bar:CreateTexture(nil, "ARTWORK")
barTex:SetColorTexture(1, 1, 1, 1)
bar:SetStatusBarTexture(barTex)
bar:SetMinMaxValues(0, 1)
bar:SetValue(0)
f.bar = bar

-- Latency zone
local latTex = f:CreateTexture(nil, "ARTWORK", nil, 1)
latTex:SetColorTexture(0.7, 0.1, 0.1, 0.5)
latTex:SetPoint("TOPRIGHT", f, "TOPRIGHT", -1, -1)
latTex:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)
latTex:SetWidth(2)
latTex:Hide()
f.latTex = latTex

-- Spell icon
local icon = f:CreateTexture(nil, "ARTWORK")
icon:SetSize(DEFAULTS.iconSize, DEFAULTS.iconSize)
icon:SetPoint("RIGHT", f, "LEFT", -3, 0)
icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
icon:Hide()
f.icon = icon

-- Spell name
local nameStr = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
nameStr:SetPoint("LEFT", bar, "LEFT", 5, 1)
nameStr:SetFont(nameStr:GetFont(), 11, "OUTLINE")
nameStr:SetTextColor(1, 1, 1, 1)
nameStr:SetJustifyH("LEFT")
f.nameStr = nameStr

-- Timer
local timerStr = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
timerStr:SetPoint("RIGHT", bar, "RIGHT", -5, 1)
timerStr:SetFont(timerStr:GetFont(), 11, "OUTLINE")
timerStr:SetTextColor(1, 1, 1, 1)
timerStr:SetJustifyH("RIGHT")
f.timerStr = timerStr

-- GCD spark bar (thin bar below castbar)
local gcdBar = CreateFrame("StatusBar", nil, f)
gcdBar:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, -3)
gcdBar:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, -3)
gcdBar:SetHeight(3)
local gcdTex = gcdBar:CreateTexture(nil, "ARTWORK")
gcdTex:SetColorTexture(1, 1, 1, 0.75)
gcdBar:SetStatusBarTexture(gcdTex)
gcdBar:SetMinMaxValues(0, 1)
gcdBar:SetValue(0)
gcdBar:Hide()
f.gcdBar = gcdBar

-- Channel tick marks
f.ticks = {}
for i = 1, 10 do
    local t = f:CreateTexture(nil, "OVERLAY")
    t:SetSize(2, DEFAULTS.height)
    t:SetColorTexture(1, 1, 1, 0.55)
    t:Hide()
    f.ticks[i] = t
end

-- ── Helpers ────────────────────────────────────────────────────────────────────
local function SetBarColor(colorKey)
    local db = GetDB()
    local c = db[colorKey] or DEFAULTS[colorKey]
    f.bar:SetStatusBarColor(c[1], c[2], c[3], 1)
    local bc = db.colorBackground or DEFAULTS.colorBackground
    f.bg:SetColorTexture(bc[1], bc[2], bc[3], 0.75)
end

local function HideTicks()
    for i = 1, 10 do f.ticks[i]:Hide() end
end

local function ShowTicks(numTicks)
    HideTicks()
    if not numTicks or numTicks <= 1 then return end
    local w = f:GetWidth() - 2
    for i = 1, numTicks - 1 do
        local t = f.ticks[i]
        t:ClearAllPoints()
        t:SetHeight(f:GetHeight())
        t:SetPoint("LEFT", f, "LEFT", (w * i / numTicks) + 1, 0)
        t:Show()
    end
end

-- ── Cast lifecycle ─────────────────────────────────────────────────────────────
f.casting    = false
f.channeling = false
f.startTime  = 0
f.endTime    = 0
f.delay      = 0
-- delayedPending: set by UNIT_SPELLCAST_DELAYED so that the UNIT_SPELLCAST_STOP
-- that WoW often fires in the same or next frame does NOT kill the bar.
f.delayedPending     = false
f.channelStopPending = false

local function StartCast(name, startMs, endMs, notInterrupt, isEmpowered)
    local db = GetDB()
    if not db.enabled then return end
    -- Cancel any active fadeOut: a new cast supersedes it
    f.fadeOut  = nil
    f.stopTime = nil
    f.casting    = true
    f.channeling = false
    f.startTime  = startMs / 1000
    f.endTime    = endMs   / 1000
    f.delay      = 0
    f.notInterruptible = notInterrupt or false
    f.bar:SetValue(0)
    f.latTex:Hide()
    HideTicks()
    if isEmpowered then
        SetBarColor("colorEmpowered")
    elseif notInterrupt then
        SetBarColor("colorNonInterrupt")
    else
        SetBarColor("colorCasting")
    end
    if db.showSpellName then f.nameStr:SetText(name or "") end
    if db.showTimer then f.timerStr:SetText("") end
    if db.showIcon then
        local _, _, tex = UnitCastingInfo("player")
        if tex then f.icon:SetTexture(tex); f.icon:Show() else f.icon:Hide() end
    else f.icon:Hide() end
    f:SetAlpha(1)
    f:Show()
end

local function StartChannel(name, startMs, endMs, notInterrupt, spellID)
    local db = GetDB()
    if not db.enabled then return end
    -- Cancel any active fadeOut: a new channel supersedes it
    f.fadeOut  = nil
    f.stopTime = nil
    f.casting    = false
    f.channeling = true
    f.startTime  = startMs / 1000
    f.endTime    = endMs   / 1000
    f.delay      = 0
    f.notInterruptible = notInterrupt or false
    f.bar:SetValue(1)
    f.latTex:Hide()
    if notInterrupt then SetBarColor("colorNonInterrupt") else SetBarColor("colorChanneling") end
    if db.showSpellName then f.nameStr:SetText(name or "") end
    if db.showTimer then f.timerStr:SetText("") end
    if db.showIcon then
        local _, _, tex = UnitChannelInfo("player")
        if tex then f.icon:SetTexture(tex); f.icon:Show() else f.icon:Hide() end
    else f.icon:Hide() end
    if db.showChannelTicks and spellID then
        ShowTicks(CHANNEL_TICKS[spellID])
    else HideTicks() end
    f:SetAlpha(1)
    f:Show()
end

local function StopCast(interrupted)
    -- NEW: Fail-safe check. If we are told to stop but the API says we are still
    -- casting or channeling, we ignore the stop command. This prevents items
    -- and passive procs from killing the bar prematurely.
    if not interrupted then
        if UnitCastingInfo("player") or UnitChannelInfo("player") then 
            return 
        end
    end

    f.casting            = false
    f.channeling         = false
    f.delayedPending     = false
    f.channelStopPending = false
    f.latTex:Hide()
    HideTicks()
    if not f:IsShown() then return end
    f.timerStr:SetText("")
    if interrupted then
        SetBarColor("colorInterrupted")
        local spellName = f.nameStr:GetText() or ""
        spellName = spellName:gsub("%s*|cFFFF4444%[Interrupted%]|r", "")
        f.nameStr:SetText(spellName .. " |cFFFF4444[Interrupted]|r")
        f.stopTime = GetTime() - 0.3  -- fade lasts ~0.7s
    else
        local db = GetDB()
        local dur = db.finishedFlashDur or DEFAULTS.finishedFlashDur
        SetBarColor("colorFinished")
        f.bar:SetValue(1)
        -- Hold full alpha for dur seconds then fade over 1s
        f.stopTime = GetTime() - (1 - math.max(dur, 0))
    end
    f.fadeOut = true
end

-- ── OnUpdate ───────────────────────────────────────────────────────────────────
f:SetScript("OnUpdate", function(self, elapsed)
    local db = GetDB()
    if not db.enabled then self:Hide(); return end
    local now = GetTime()

    if self.channeling then
        local remaining = self.endTime - now
        if remaining <= 0 then
            self.channeling = false
            self.fadeOut    = true
            self.stopTime   = now
            return
        end
        local total = self.endTime - self.startTime
        if total > 0 then self.bar:SetValue(remaining / total) end
        if db.showTimer then self.timerStr:SetText(string.format("%.1f", remaining)) end

    elseif self.casting then
        local total = self.endTime - self.startTime
        if total <= 0 then self:Hide(); return end
        local progress = math.min((now - self.startTime) / total, 1)
        self.bar:SetValue(progress)
        local remaining = math.max(0, self.endTime - now)
        if db.showTimer then self.timerStr:SetText(string.format("%.1f", remaining)) end
        -- Latency zone
        if db.showLatency then
            local _, _, _, latMs = GetNetStats()
            latMs = latMs or 0
            local frac = math.min(latMs / 1000, 0.3)
            local w = self:GetWidth() * frac
            self.latTex:SetWidth(math.max(1, w))
            self.latTex:Show()
        end
        if now > self.endTime then
            self.casting  = false
            self.fadeOut  = true
            self.stopTime = now
        end

    elseif self.fadeOut then
        -- Fade out over 1s from stopTime; stopTime offset controls hold duration
        local alpha = self.stopTime and (self.stopTime - now + 1) or 0
        if alpha >= 1 then alpha = 1 end
        if alpha <= 0 then
            self.fadeOut  = nil
            self.stopTime = nil
            self:SetAlpha(1)
            self:Hide()
            return
        end
        self:SetAlpha(alpha)
        return  -- skip GCD update during fade

    else
        self:Hide()
        return
    end
    -- GCD spark
    if db.showGCD then
        local gInfo = C_Spell.GetSpellCooldown(61304)
        local gStart = gInfo and gInfo.startTime
        local gDur   = gInfo and gInfo.duration
        if gStart and gStart > 0 and gDur and gDur > 0 then
            local p = math.min((now - gStart) / gDur, 1)
            self.gcdBar:SetValue(p)
            self.gcdBar:Show()
        else
            self.gcdBar:Hide()
        end
    else
        self.gcdBar:Hide()
    end
end)

-- ── Events (unified system - replaces standalone event frame) ─────────────────

local function OnAddonLoaded(addonName)
    if addonName ~= "RogUI_Core" then return end
    -- Apply saved position on addon load
    local db = GetDB()
    if db and (db.x or db.y) then
        f:ClearAllPoints()
        f:SetPoint("CENTER", UIParent, "CENTER", db.x or 0, db.y or -220)
    end
end

local function OnPlayerLoginOrEnteringWorld()
    -- Ensure position is applied
    local db = GetDB()
    if db and (db.x or db.y) then
        f:ClearAllPoints()
        f:SetPoint("CENTER", UIParent, "CENTER", db.x or 0, db.y or -220)
    end
    local db = GetDB()
    if db.hideBlizzard and db.enabled then
        local targets = {
            "CastingBarFrame", "PlayerCastingBarFrame",
            "OverlayPlayerCastingBarFrame", "OverrideActionBarCastBar", "PetCastingBarFrame",
        }
        for _, frameName in ipairs(targets) do
            local frame = _G[frameName]
            if frame then
                pcall(function()
                    frame:UnregisterAllEvents()
                    frame:SetAlpha(0)
                    frame:SetScript("OnShow", function(s) s:SetAlpha(0) end)
                end)
            end
        end
    end
end

local function OnSpellEvent(unit, castGUID, spellID)
    -- Core.lua passes (...) without the event name; we receive raw WoW args.
    -- We reconstruct the event dispatch by checking state after each call.
    -- This handler is registered per-event so we read the firing event from
    -- a closure variable set before dispatch. However, since Core dispatches
    -- each event to its own registered handler, we register separate closures.
end

-- Register all castbar events through the unified system
local function RegisterCastbarEvents()
    API.RegisterEvent("Castbar", "ADDON_LOADED",                  OnAddonLoaded)
    API.RegisterEvent("Castbar", "PLAYER_LOGIN",                  function() OnPlayerLoginOrEnteringWorld() end)
    API.RegisterEvent("Castbar", "PLAYER_ENTERING_WORLD",         function() OnPlayerLoginOrEnteringWorld() end)

    -- ── Cast start ──────────────────────────────────────────────────────────
    API.RegisterEvent("Castbar", "UNIT_SPELLCAST_START", function(unit, castGUID, spellID)
        if unit ~= "player" then return end
        local db = GetDB(); if not db.enabled then return end
        local name, _, _, startTime, endTime, _, _, notInterrupt = UnitCastingInfo("player")
        if name then StartCast(name, startTime, endTime, notInterrupt, false) end
    end)

    API.RegisterEvent("Castbar", "UNIT_SPELLCAST_EMPOWER_START", function(unit)
        if unit ~= "player" then return end
        local db = GetDB(); if not db.enabled then return end
        local name, _, _, startTime, endTime = UnitCastingInfo("player")
        if name then StartCast(name, startTime, endTime, false, true) end
    end)

    -- ── Channel start — also clears any pending channel-stop defer ──────────
    API.RegisterEvent("Castbar", "UNIT_SPELLCAST_CHANNEL_START", function(unit, castGUID, spellID)
        if unit ~= "player" then return end
        local db = GetDB(); if not db.enabled then return end
        f.channelStopPending = false   -- cancel any deferred stop from previous tick
        local name, _, _, startTime, endTime, _, notInterrupt = UnitChannelInfo("player")
        if name then StartChannel(name, startTime, endTime, notInterrupt, spellID) end
    end)

    -- ── Cast stop — respects pushback (delayedPending) flag ─────────────────
    -- UNIT_SPELLCAST_DELAYED fires in the same or next frame as UNIT_SPELLCAST_STOP
    -- during pushback. We set delayedPending=true so STOP doesn't kill the bar.
    API.RegisterEvent("Castbar", "UNIT_SPELLCAST_STOP", function(unit)
        if unit ~= "player" then return end
        if f.delayedPending then
            f.delayedPending     = false
            f.channelStopPending = false  -- DELAYED already handled it
            return
        end
        StopCast(false)
    end)

    API.RegisterEvent("Castbar", "UNIT_SPELLCAST_EMPOWER_STOP", function(unit)
        if unit ~= "player" then return end
        StopCast(false)
    end)

    -- ── Channel stop — deferred to avoid killing mid-channel tick restarts ───
    -- Some spells (Penance, Rapid Fire, multi-tick channels) fire CHANNEL_STOP
    -- then CHANNEL_START again for each tick window. We defer the actual stop
    -- by one frame so CHANNEL_START can cancel it if it arrives immediately.
    API.RegisterEvent("Castbar", "UNIT_SPELLCAST_CHANNEL_STOP", function(unit)
        if unit ~= "player" then return end
        f.channelStopPending = true
        C_Timer.After(0, function()
            -- If CHANNEL_START fired and restarted the channel, skip the stop
            if not f.channelStopPending then return end
            f.channelStopPending = false
            StopCast(false)
        end)
    end)

    -- ── Succeeded/interrupted/failed ────────────────────────────────────────
    API.RegisterEvent("Castbar", "UNIT_SPELLCAST_SUCCEEDED", function(unit, castGUID, spellID)
        if unit ~= "player" then return end
        -- NEW: Only stop if we are doing a regular cast, not a channel.
        -- This prevents instant-cast items from firing a success event 
        -- and killing a channel prematurely.
        if f.casting and not f.channeling then
            StopCast(false)
        end
    end)

    API.RegisterEvent("Castbar", "UNIT_SPELLCAST_INTERRUPTED", function(unit)
        if unit ~= "player" then return end
        StopCast(true)
    end)

    local function HideImmediately()
        f.casting = false; f.channeling = false
        f.delayedPending     = false
        f.channelStopPending = false
        f.fadeOut = nil; f.stopTime = nil
        HideTicks(); f.latTex:Hide()
        f:SetAlpha(1); f:Hide()
    end

    API.RegisterEvent("Castbar", "UNIT_SPELLCAST_FAILED",       function(unit) if unit == "player" then HideImmediately() end end)
    API.RegisterEvent("Castbar", "UNIT_SPELLCAST_FAILED_QUIET", function(unit) if unit == "player" then HideImmediately() end end)

    -- ── Pushback (delayed) — set flag to suppress the paired STOP ───────────
    -- WoW fires DELAYED (new times) then STOP (old cast ended) in pushback.
    -- We set delayedPending=true so STOP knows not to kill the bar, then
    -- immediately restart with the updated times from UnitCastingInfo.
    API.RegisterEvent("Castbar", "UNIT_SPELLCAST_DELAYED", function(unit)
        if unit ~= "player" then return end
        local db = GetDB(); if not db.enabled then return end
        f.delayedPending = true   -- tell STOP handler to stand down
        local name, _, _, startTime, endTime, _, _, notInterrupt = UnitCastingInfo("player")
        if name then
            -- Update times in place — preserves bar visibility through the pushback
            f.fadeOut    = nil
            f.stopTime   = nil
            f.casting    = true
            f.channeling = false
            f.startTime  = startTime / 1000
            f.endTime    = endTime   / 1000
            f.notInterruptible = notInterrupt or false
            f:SetAlpha(1)
            -- Re-show in case a prior STOP already triggered fadeOut
            if not f:IsShown() then f:Show() end
        end
        -- If UnitCastingInfo returned nil (very rare race), delayedPending still
        -- suppresses STOP for this frame. OnUpdate will hide via natural expiry.
    end)

    -- ── Channel update (pushback during channel) ─────────────────────────────
    API.RegisterEvent("Castbar", "UNIT_SPELLCAST_CHANNEL_UPDATE", function(unit)
        if unit ~= "player" then return end
        f.channelStopPending = false  -- cancel any deferred stop
        local name, _, _, startTime, endTime = UnitChannelInfo("player")
        if name then
            f.fadeOut    = nil
            f.stopTime   = nil
            f.channeling = true
            f.startTime  = startTime / 1000
            f.endTime    = endTime   / 1000
            f:SetAlpha(1)
            if not f:IsShown() then f:Show() end
        end
    end)
end

RegisterCastbarEvents()

-- ── Drag ───────────────────────────────────────────────────────────────────────
f:SetScript("OnDragStart", function(self)
    if API.IsLayoutMode and API.IsLayoutMode() then self:StartMoving() end
end)
f:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    if RogUICastbarDB then
        local cx, cy = UIParent:GetWidth()/2, UIParent:GetHeight()/2
        RogUICastbarDB.x = math.floor(self:GetLeft() + self:GetWidth()/2 - cx + 0.5)
        RogUICastbarDB.y = math.floor(self:GetBottom() + self:GetHeight()/2 - cy + 0.5)
    end
end)

-- ── Register with Edit Mode layout chain ──────────────────────────────────────
API.RegisterLayoutHandles(function()
    local db = GetDB()
    if not (db and db.enabled) then return {} end
    return {{
        label        = "Player Castbar",
        iconTex      = "Interface\\Icons\\Spell_Holy_Aspiration",
        ox           = db.x or 0,
        oy           = db.y or -220,
        liveFrameRef = f,
        saveCallback = function(nx, ny)
            if RogUICastbarDB then RogUICastbarDB.x = nx; RogUICastbarDB.y = ny end
            f:ClearAllPoints()
            f:SetPoint("CENTER", UIParent, "CENTER", nx, ny)
        end,
        resizeCallback = function(nw, nh)
            nw = math.max(80, math.floor(nw + 0.5))
            nh = math.max(8,  math.floor(nh + 0.5))
            if RogUICastbarDB then RogUICastbarDB.width = nw; RogUICastbarDB.height = nh end
            f:SetSize(nw, nh)
        end,
    }}
end)

-- NEW: API function to apply castbar alpha
function API.Castbar_ApplyAlpha()
    local db = GetDB()
    local targetAlpha = db.alpha or DEFAULTS.alpha or 1.0
    if f then
        f:SetAlpha(targetAlpha)
    end
end

API.castbarFrame = f