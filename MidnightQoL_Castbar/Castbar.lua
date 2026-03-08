-- ============================================================
-- MidnightQoL_Castbar / Castbar.lua
-- Player castbar replacement.
-- Features: per-state colors, channel ticks, GCD spark,
-- latency zone, interrupt flash, Edit Mode anchor.
-- ============================================================

local API = MidnightQoLAPI
if not API then return end

local DEFAULTS = {
    enabled           = false,
    hideBlizzard      = true,
    x                 = 0,
    y                 = -220,
    width             = 280,
    height            = 18,
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

local function GetDB()
    if not CastbarDB then CastbarDB = {} end
    for k, v in pairs(DEFAULTS) do
        if CastbarDB[k] == nil then CastbarDB[k] = v end
    end
    return CastbarDB
end

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
local f = CreateFrame("Frame", "MQoLPlayerCastbar", UIParent)
f:SetFrameStrata("MEDIUM")
f:SetFrameLevel(100)
f:SetSize(DEFAULTS.width, DEFAULTS.height)
f:SetMovable(true)
f:EnableMouse(true)
f:RegisterForDrag("LeftButton")
f:Hide()

-- Background
local bg = f:CreateTexture(nil, "BACKGROUND")
bg:SetAllPoints(f)
bg:SetColorTexture(0, 0, 0, 0.75)
f.bg = bg

-- Border
local border = CreateFrame("Frame", nil, f, "BackdropTemplate")
border:SetAllPoints(f)
border:SetBackdrop({edgeFile="Interface/Buttons/WHITE8X8", edgeSize=1})
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

local function StartCast(name, startMs, endMs, notInterrupt, isEmpowered)
    local db = GetDB()
    if not db.enabled then return end
    f._orphanCheck = 0
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
    f:Show()
end

local function StartChannel(name, startMs, endMs, notInterrupt, spellID)
    local db = GetDB()
    if not db.enabled then return end
    f._orphanCheck = 0
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
    f:Show()
end

local finishTimer = nil
local function StopCast(interrupted)
    if finishTimer then finishTimer:Cancel(); finishTimer = nil end
    if f.interrupted and interrupted then return end  -- already showing interrupted, don't stack
    f.casting    = false
    f.channeling = false
    f.latTex:Hide()
    HideTicks()
    if f.interrupted then return end  -- UNIT_SPELLCAST_STOP after INTERRUPTED — bar already handled
    if not f:IsShown() then return end
    if interrupted then
        f.interrupted = true
        SetBarColor("colorInterrupted")
        local spellName = f.nameStr:GetText() or ""
        -- Strip any previous [Interrupted] tag before appending (safety net)
        spellName = spellName:gsub("%s*|cFFFF4444%[Interrupted%]|r", "")
        f.nameStr:SetText(spellName .. " |cFFFF4444[Interrupted]|r")
        f.timerStr:SetText("")
        finishTimer = C_Timer.NewTimer(0.7, function() f.interrupted = nil; f:Hide() end)
    else
        local db = GetDB()
        local dur = db.finishedFlashDur or DEFAULTS.finishedFlashDur
        if dur > 0 then
            SetBarColor("colorFinished")
            f.bar:SetValue(1)
            f.timerStr:SetText("")
            finishTimer = C_Timer.NewTimer(dur, function() f:Hide() end)
        else
            f:Hide()
        end
    end
end

-- ── OnUpdate ───────────────────────────────────────────────────────────────────
f:SetScript("OnUpdate", function(self, elapsed)
    local db = GetDB()
    if not db.enabled then self:Hide(); return end
    local now = GetTime()

    if self.channeling then
        local remaining = self.endTime - now
        if remaining <= 0 then self:Hide(); return end
        local total = self.endTime - self.startTime
        if total > 0 then self.bar:SetValue(remaining / total) end
        if db.showTimer then self.timerStr:SetText(string.format("%.1f", remaining)) end
        -- Safety: orphan channel check
        self._orphanCheck = (self._orphanCheck or 0) + elapsed
        if self._orphanCheck >= 0.1 then
            self._orphanCheck = 0
            if not UnitChannelInfo("player") then
                StopCast(false)
                return
            end
        end

    elseif self.casting then
        local total = (self.endTime - self.startTime) + self.delay
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
        -- Safety: quest/interact casts sometimes never fire STOP or SUCCEEDED.
        -- If the bar thinks we're casting but the game has no cast, hide it.
        self._orphanCheck = (self._orphanCheck or 0) + elapsed
        if self._orphanCheck >= 0.1 then
            self._orphanCheck = 0
            if not UnitCastingInfo("player") then
                StopCast(false)
                return
            end
        end
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

-- ── Events ─────────────────────────────────────────────────────────────────────
local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("UNIT_SPELLCAST_START")
events:RegisterEvent("UNIT_SPELLCAST_CHANNEL_START")
events:RegisterEvent("UNIT_SPELLCAST_STOP")
events:RegisterEvent("UNIT_SPELLCAST_CHANNEL_STOP")
events:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
events:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED")
events:RegisterEvent("UNIT_SPELLCAST_DELAYED")
events:RegisterEvent("UNIT_SPELLCAST_CHANNEL_UPDATE")
events:RegisterEvent("UNIT_SPELLCAST_EMPOWER_START")
events:RegisterEvent("UNIT_SPELLCAST_EMPOWER_STOP")
events:RegisterEvent("UNIT_SPELLCAST_FAILED")
events:RegisterEvent("UNIT_SPELLCAST_FAILED_QUIET")

local function ApplyPosition()
    local db = GetDB()
    f:ClearAllPoints()
    f:SetSize(db.width or DEFAULTS.width, db.height or DEFAULTS.height)
    f:SetPoint("CENTER", UIParent, "CENTER", db.x or 0, db.y or -220)
    -- Resize tick heights
    for i = 1, 10 do f.ticks[i]:SetHeight(f:GetHeight()) end
end
API.ApplyCastbarPosition = ApplyPosition

events:SetScript("OnEvent", function(self, event, unit, castGUID, spellID)
    if event == "ADDON_LOADED" then
        if unit == "MidnightQoL_Castbar" then
            ApplyPosition()
        end
        return
    end

    if event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
        ApplyPosition()
        local db = GetDB()
        if db.hideBlizzard and db.enabled then
            -- TWW uses PlayerCastingBarFrame; pre-TWW uses CastingBarFrame.
            -- Also cover the override action bar and pet castbar.
            local targets = {
                "CastingBarFrame",
                "PlayerCastingBarFrame",
                "OverlayPlayerCastingBarFrame",
                "OverrideActionBarCastBar",
                "PetCastingBarFrame",
            }
            for _, frameName in ipairs(targets) do
                local frame = _G[frameName]
                if frame then
                    pcall(function()
                        frame:UnregisterAllEvents()
                        -- Use alpha to hide rather than :Hide() so we don't
                        -- trigger Blizzard's OnShow/OnHide teardown paths that
                        -- iterate protected animation tables (forbidden table error).
                        frame:SetAlpha(0)
                        frame:SetScript("OnShow", function(s) s:SetAlpha(0) end)
                    end)
                end
            end
        end
        return
    end

    if unit ~= "player" then return end
    local db = GetDB()
    if not db.enabled then return end

    if event == "UNIT_SPELLCAST_START" then
        local name, _, _, startTime, endTime, _, _, notInterrupt = UnitCastingInfo("player")
        if name then StartCast(name, startTime, endTime, notInterrupt, false) end

    elseif event == "UNIT_SPELLCAST_EMPOWER_START" then
        local name, _, _, startTime, endTime = UnitCastingInfo("player")
        if name then StartCast(name, startTime, endTime, false, true) end

    elseif event == "UNIT_SPELLCAST_CHANNEL_START" then
        local name, _, _, startTime, endTime, _, notInterrupt = UnitChannelInfo("player")
        if name then StartChannel(name, startTime, endTime, notInterrupt, spellID) end

    elseif event == "UNIT_SPELLCAST_STOP" or event == "UNIT_SPELLCAST_EMPOWER_STOP" then
        -- UNIT_SPELLCAST_STOP fires for pushback (game pauses cast then restarts),
        -- for clean finishes (before SUCCEEDED), AND for silently-failed casts
        -- (mount blocked, facing, range, moving, etc.) that never get FAILED/INTERRUPTED.
        --
        -- Guard: if the cast GUID still matches what the bar is showing, a new
        -- UNIT_SPELLCAST_START hasn't arrived yet — this is a real stop, not pushback.
        -- We defer by one frame so a same-frame START can override us.
        local stoppedGUID = castGUID
        C_Timer.After(0, function()
            local currentName, _, currentGUID = UnitCastingInfo("player")
            -- If the player has started a different/new cast in this frame, leave the bar alone.
            if currentName and currentGUID and currentGUID ~= stoppedGUID then return end
            -- Otherwise (no cast, or same cast still listed) → stop the bar.
            StopCast(false)
        end)

    elseif event == "UNIT_SPELLCAST_CHANNEL_STOP" then
        local stoppedGUID = castGUID
        C_Timer.After(0, function()
            local currentName = UnitChannelInfo("player")
            if not currentName then StopCast(false) end
        end)

    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        StopCast(false)

    elseif event == "UNIT_SPELLCAST_INTERRUPTED" then
        StopCast(true)

    elseif event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_FAILED_QUIET" then
        f.casting = false; f.channeling = false; f:Hide()

    elseif event == "UNIT_SPELLCAST_DELAYED" then
        -- Pushback: WoW fires STOP then START around the delay, but there's a
        -- 1-frame gap. Re-read cast info and restart the bar immediately so it
        -- never disappears during the pushback.
        local name, _, _, startTime, endTime, _, _, notInterrupt = UnitCastingInfo("player")
        if name then
            StartCast(name, startTime, endTime, notInterrupt, false)
        end

    elseif event == "UNIT_SPELLCAST_CHANNEL_UPDATE" then
        local name, _, _, startTime, endTime = UnitChannelInfo("player")
        if name and f:IsShown() then f.endTime = endTime / 1000 end
    end
end)

-- ── Drag ───────────────────────────────────────────────────────────────────────
f:SetScript("OnDragStart", function(self)
    if API.IsLayoutMode and API.IsLayoutMode() then self:StartMoving() end
end)
f:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    if CastbarDB then
        local cx, cy = UIParent:GetWidth()/2, UIParent:GetHeight()/2
        CastbarDB.x = math.floor(self:GetLeft() + self:GetWidth()/2 - cx + 0.5)
        CastbarDB.y = math.floor(self:GetBottom() + self:GetHeight()/2 - cy + 0.5)
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
            if CastbarDB then CastbarDB.x = nx; CastbarDB.y = ny end
            f:ClearAllPoints()
            f:SetPoint("CENTER", UIParent, "CENTER", nx, ny)
        end,
        resizeCallback = function(nw, nh)
            nw = math.max(80, math.floor(nw + 0.5))
            nh = math.max(8,  math.floor(nh + 0.5))
            if CastbarDB then CastbarDB.width = nw; CastbarDB.height = nh end
            f:SetSize(nw, nh)
        end,
    }}
end)

API.castbarFrame = f
