-- ============================================================
-- MidnightQoL_ResourceBars / ResourceBars.lua
-- Live resource bars: polls UnitPower every frame (OnUpdate),
-- supports continuous bars and discrete pip bars.
-- Spec-profile aware: each spec gets its own bar configuration.
-- ============================================================

local API = MidnightQoLAPI

-- ── Power type map ────────────────────────────────────────────────────────────
-- Maps specID (from GetSpecializationInfo) to the Blizzard Enum.PowerType values
-- for primary and secondary resources shown on the bar.
-- specID is the 4th return of GetSpecializationInfo(GetSpecialization()).

local POWER_MANA   = Enum.PowerType.Mana
local POWER_RAGE   = Enum.PowerType.Rage
local POWER_FOCUS  = Enum.PowerType.Focus
local POWER_ENERGY = Enum.PowerType.Energy
local POWER_CHI    = Enum.PowerType.Chi
local POWER_RUNES  = Enum.PowerType.Runes
local POWER_RUNIC  = Enum.PowerType.RunicPower
local POWER_SOUL   = Enum.PowerType.SoulShards
local POWER_LUNAR  = Enum.PowerType.LunarPower
local POWER_HOLY   = Enum.PowerType.HolyPower
local POWER_MAELSTROM = Enum.PowerType.Maelstrom
local POWER_INSANITY  = Enum.PowerType.Insanity
local POWER_FURY      = Enum.PowerType.Fury
local POWER_PAIN      = Enum.PowerType.Pain
local POWER_ESSENCE   = Enum.PowerType.Essence
local POWER_COMBO     = Enum.PowerType.ComboPoints
local POWER_ARCANE    = Enum.PowerType.ArcaneCharges

-- isPip = show as discrete circles, maxPips = circle count
-- isBar = show as a continuous fill bar
local SPEC_POWER = {
    -- Death Knight
    [250] = {primary={type=POWER_RUNES,  isPip=true, maxPips=6, label="Runes"},  secondary={type=POWER_RUNIC, isBar=true, label="Runic Power"}},
    [251] = {primary={type=POWER_RUNES,  isPip=true, maxPips=6, label="Runes"},  secondary={type=POWER_RUNIC, isBar=true, label="Runic Power"}},
    [252] = {primary={type=POWER_RUNES,  isPip=true, maxPips=6, label="Runes"},  secondary={type=POWER_RUNIC, isBar=true, label="Runic Power"}},
    -- Demon Hunter
    [577] = {primary={type=POWER_FURY,   isBar=true, label="Fury"},  secondary=nil},
    [581] = {primary={type=POWER_PAIN,   isBar=true, label="Pain"},  secondary=nil},
    -- Druid
    [102] = {primary={type=POWER_MANA,   isBar=true, label="Mana"},     secondary={type=POWER_LUNAR, isBar=true, label="Astral Power"}},
    [103] = {primary={type=POWER_ENERGY, isBar=true, label="Energy"},   secondary={type=POWER_COMBO, isPip=true, maxPips=5, label="Combo Points"}},
    [104] = {primary={type=POWER_RAGE,   isBar=true, label="Rage"},     secondary=nil},
    [105] = {primary={type=POWER_MANA,   isBar=true, label="Mana"},     secondary=nil},
    -- Evoker
    [1467]= {primary={type=POWER_MANA,   isBar=true, label="Mana"},     secondary={type=POWER_ESSENCE, isPip=true, maxPips=6, label="Essence"}},
    [1468]= {primary={type=POWER_MANA,   isBar=true, label="Mana"},     secondary={type=POWER_ESSENCE, isPip=true, maxPips=6, label="Essence"}},
    [1473]= {primary={type=POWER_MANA,   isBar=true, label="Mana"},     secondary={type=POWER_ESSENCE, isPip=true, maxPips=6, label="Essence"}},
    -- Hunter
    [253] = {primary={type=POWER_FOCUS,  isBar=true, label="Focus"},    secondary=nil},
    [254] = {primary={type=POWER_FOCUS,  isBar=true, label="Focus"},    secondary=nil},
    [255] = {primary={type=POWER_FOCUS,  isBar=true, label="Focus"},    secondary=nil},
    -- Mage
    [62]  = {primary={type=POWER_MANA,   isBar=true, label="Mana"},     secondary={type=POWER_ARCANE, isPip=true, maxPips=4, label="Arcane Charges"}},
    [63]  = {primary={type=POWER_MANA,   isBar=true, label="Mana"},     secondary=nil},
    [64]  = {primary={type=POWER_MANA,   isBar=true, label="Mana"},     secondary=nil},
    -- Monk
    [268] = {primary={type=POWER_ENERGY, isBar=true, label="Energy"},   secondary={type=POWER_CHI, isPip=true, maxPips=6, label="Chi"}},
    [269] = {primary={type=POWER_ENERGY, isBar=true, label="Energy"},   secondary={type=POWER_CHI, isPip=true, maxPips=5, label="Chi"}},
    [270] = {primary={type=POWER_MANA,   isBar=true, label="Mana"},     secondary=nil},
    -- Paladin
    [65]  = {primary={type=POWER_MANA,   isBar=true, label="Mana"},     secondary={type=POWER_HOLY, isPip=true, maxPips=5, label="Holy Power"}},
    [66]  = {primary={type=POWER_MANA,   isBar=true, label="Mana"},     secondary=nil},
    [70]  = {primary={type=POWER_MANA,   isBar=true, label="Mana"},     secondary={type=POWER_HOLY, isPip=true, maxPips=5, label="Holy Power"}},
    -- Priest
    [256] = {primary={type=POWER_MANA,   isBar=true, label="Mana"},     secondary=nil},
    [257] = {primary={type=POWER_MANA,   isBar=true, label="Mana"},     secondary=nil},
    [258] = {primary={type=POWER_MANA,   isBar=true, label="Mana"},     secondary={type=POWER_INSANITY, isBar=true, label="Insanity"}},
    -- Rogue
    [259] = {primary={type=POWER_ENERGY, isBar=true, label="Energy"},   secondary={type=POWER_COMBO, isPip=true, maxPips=7, label="Combo Points"}},
    [260] = {primary={type=POWER_ENERGY, isBar=true, label="Energy"},   secondary={type=POWER_COMBO, isPip=true, maxPips=6, label="Combo Points"}},
    [261] = {primary={type=POWER_ENERGY, isBar=true, label="Energy"},   secondary={type=POWER_COMBO, isPip=true, maxPips=6, label="Combo Points"}},
    -- Shaman
    [262] = {primary={type=POWER_MANA,   isBar=true, label="Mana"},     secondary={type=POWER_MAELSTROM, isBar=true, label="Maelstrom"}},
    [263] = {primary={type=POWER_MANA,   isBar=true, label="Mana"},     secondary=nil},
    [264] = {primary={type=POWER_MANA,   isBar=true, label="Mana"},     secondary=nil},
    -- Warlock
    [265] = {primary={type=POWER_MANA,   isBar=true, label="Mana"},     secondary={type=POWER_SOUL, isPip=true, maxPips=5, label="Soul Shards"}},
    [266] = {primary={type=POWER_MANA,   isBar=true, label="Mana"},     secondary=nil},
    [267] = {primary={type=POWER_MANA,   isBar=true, label="Mana"},     secondary=nil},
    -- Warrior
    [71]  = {primary={type=POWER_RAGE,   isBar=true, label="Rage"},     secondary=nil},
    [72]  = {primary={type=POWER_RAGE,   isBar=true, label="Rage"},     secondary=nil},
    [73]  = {primary={type=POWER_RAGE,   isBar=true, label="Rage"},     secondary=nil},
}

API.SPEC_POWER = SPEC_POWER

-- ── Live bar frames pool ──────────────────────────────────────────────────────
-- We keep one "bar set" per config slot (there can be up to 4 bars configured).
-- Each set contains the bar frame + optional pip frames.

local MAX_BARS = 2
local barFrames = {}    -- [i] = the live HUD bar frame
local barConfigs = {}   -- [i] = {enabled, powerType, isPip, maxPips, ...layout}
local updateFrame = CreateFrame("Frame")

API.barFrames  = barFrames
API.barConfigs = barConfigs

-- ── Spec profile save/load ────────────────────────────────────────────────────
local function OnSaveProfile(profile)
    -- Harvest live barConfigs into profile
    profile.resourceBars = {}
    for i = 1, MAX_BARS do
        local cfg = barConfigs[i]
        if cfg then
            profile.resourceBars[i] = {
                enabled    = cfg.enabled,
                unit       = cfg.unit or "player",
                powerType  = cfg.powerType,
                isPip      = cfg.isPip,
                maxPips    = cfg.maxPips,
                isBar      = cfg.isBar,
                label      = cfg.label,
                x          = cfg.x, y = cfg.y,
                w          = cfg.w, h = cfg.h,
                r          = cfg.r, g = cfg.g, b = cfg.b,
                bgR        = cfg.bgR, bgG = cfg.bgG, bgB = cfg.bgB,
                showLabel  = cfg.showLabel,
                showValue  = cfg.showValue,
                pipSize    = cfg.pipSize,
                pipGap     = cfg.pipGap,
            }
        end
    end
end

local function OnLoadProfile(profile)
    if not profile.resourceBars then
        -- Auto-populate bars based on spec power map
        local specID = API.currentSpecID
        local specPow = SPEC_POWER[specID]
        profile.resourceBars = {}
        if specPow then
            if specPow.primary then
                profile.resourceBars[1] = {
                    enabled   = true,
                    powerType = specPow.primary.type,
                    isPip     = specPow.primary.isPip or false,
                    maxPips   = specPow.primary.maxPips or 5,
                    isBar     = specPow.primary.isBar or false,
                    label     = specPow.primary.label or "",
                    x=0, y=-200, w=200, h=20,
                    r=0.2,g=0.6,b=1, bgR=0.1,bgG=0.1,bgB=0.1,
                    showLabel=true, showValue=true, pipSize=18, pipGap=4,
                }
            end
            if specPow.secondary then
                profile.resourceBars[2] = {
                    enabled   = true,
                    powerType = specPow.secondary.type,
                    isPip     = specPow.secondary.isPip or false,
                    maxPips   = specPow.secondary.maxPips or 5,
                    isBar     = specPow.secondary.isBar or false,
                    label     = specPow.secondary.label or "",
                    x=0, y=-228, w=200, h=14,
                    r=1,g=0.8,b=0.1, bgR=0.1,bgG=0.1,bgB=0.1,
                    showLabel=false, showValue=false, pipSize=16, pipGap=4,
                }
            end
        end
    end
    -- Load configs and rebuild live bars
    for i = 1, MAX_BARS do
        barConfigs[i] = profile.resourceBars and profile.resourceBars[i] or nil
        if barConfigs[i] and not barConfigs[i].unit then barConfigs[i].unit = "player" end
    end
    if API.RebuildLiveBars then API.RebuildLiveBars() end
    if API.RefreshResourceBarUI then API.RefreshResourceBarUI() end
end

API.RegisterProfileCallbacks(OnSaveProfile, OnLoadProfile)

-- ── Live bar builder ──────────────────────────────────────────────────────────
local function CreateBarFrame(i)
    local f = CreateFrame("Frame","MidnightQoLBar"..i,UIParent)
    f:SetFrameStrata("BACKGROUND")
    f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
    f:SetClampedToScreen(true)
    f:SetScript("OnDragStart",function(self) self:StartMoving() end)
    f:SetScript("OnDragStop",function(self)
        self:StopMovingOrSizing()
        local cx=UIParent:GetWidth()/2; local cy=UIParent:GetHeight()/2
        local nx=math.floor(self:GetLeft()+self:GetWidth()/2-cx+0.5)
        local ny=math.floor(self:GetBottom()+self:GetHeight()/2-cy+0.5)
        local cfg=barConfigs[i]; if cfg then cfg.x=nx; cfg.y=ny end
    end)
    f:Hide()
    -- Background
    f.bg = f:CreateTexture(nil,"BACKGROUND"); f.bg:SetAllPoints(f); f.bg:SetColorTexture(0.1,0.1,0.1,0.8)
    -- Fill (for continuous bars)
    f.fill = f:CreateTexture(nil,"ARTWORK"); f.fill:SetColorTexture(0.2,0.6,1,0.9)
    f.fill:SetPoint("TOPLEFT",f,"TOPLEFT",0,0); f.fill:SetPoint("BOTTOMLEFT",f,"BOTTOMLEFT",0,0); f.fill:SetWidth(1)
    -- Label
    f.label = f:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    f.label:SetPoint("LEFT",f,"LEFT",4,0); f.label:SetJustifyH("LEFT"); f.label:SetTextColor(1,1,1,0.9)
    -- Value text
    f.value = f:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    f.value:SetPoint("RIGHT",f,"RIGHT",-4,0); f.value:SetJustifyH("RIGHT"); f.value:SetTextColor(1,1,1,0.7)
    -- Pip frames (for discrete resources like Chi, Holy Power, Runes, Combo Points)
    f.pips = {}
    for p = 1, 10 do
        local pip = f:CreateTexture(nil,"ARTWORK")
        pip:SetTexture("Interface\\Buttons\\UI-Quickslot2")   -- circular gem look
        pip:Hide()
        f.pips[p] = pip
    end
    return f
end

local function RebuildLiveBars()
    for i = 1, MAX_BARS do
        if not barFrames[i] then barFrames[i] = CreateBarFrame(i) end
        local f   = barFrames[i]
        local cfg = barConfigs[i]
        if not cfg or not cfg.enabled then
            f:Hide()
        else
            f:ClearAllPoints()
            f:SetPoint("CENTER", UIParent, "CENTER", cfg.x or 0, cfg.y or -200)
            -- Hide all pips first
            for _, pip in ipairs(f.pips) do pip:Hide() end

            if cfg.isPip then
                -- Size the frame to fit pips in a row
                local ps  = cfg.pipSize or 18
                local gap = cfg.pipGap  or 4
                local n   = cfg.maxPips or 5
                local fw  = n*(ps+gap) - gap
                f:SetSize(fw, ps)
                f.fill:Hide()
                f.bg:Hide()
                -- Position pips left to right
                for p = 1, n do
                    local pip = f.pips[p]
                    pip:SetSize(ps,ps)
                    pip:SetPoint("LEFT",f,"LEFT",(p-1)*(ps+gap),0)
                    pip:Show()
                end
                f.label:SetText(cfg.showLabel and (cfg.label or "") or "")
            else
                -- Continuous bar
                local w = cfg.w or 200; local h = cfg.h or 20
                f:SetSize(w,h)
                f.fill:Show()
                f.bg:Show()
                f.fill:SetColorTexture(cfg.r or 0.2, cfg.g or 0.6, cfg.b or 1, 0.9)
                f.bg:SetColorTexture(cfg.bgR or 0.1, cfg.bgG or 0.1, cfg.bgB or 0.1, 0.8)
                f.label:SetText(cfg.showLabel and (cfg.label or "") or "")
            end
            f:Show()
        end
    end
end
API.RebuildLiveBars = RebuildLiveBars

-- ── Bar update logic ─────────────────────────────────────────────────────────
-- Called from power events instead of OnUpdate to avoid taint and nil returns.
-- UNIT_POWER_FREQUENT is the correct event for addon resource bars in WoW.
local function UpdateAllBars()
    for i = 1, MAX_BARS do
        local f   = barFrames[i]
        local cfg = barConfigs[i]
        if not (f and f:IsShown() and cfg and cfg.enabled) then break end

        local pt   = cfg.powerType
        local unit = cfg.unit or "player"
        local cur, max
        if pt == 20 then
            -- Stagger: use UnitStagger (only valid for player)
            cur = UnitStagger(unit) or 0
            max = UnitHealthMax(unit) or 1
        else
            cur = UnitPower(unit, pt)
            max = UnitPowerMax(unit, pt)
        end
        -- Sanitise: force to plain numbers, discarding any taint
        cur = cur and (cur + 0) or 0
        max = max and (max + 0) or 1
        if max <= 0 then max = 1 end

        -- Wrap arithmetic in pcall so any residual taint cannot error-spam
        pcall(function()
            if cfg.isPip then
                local n = cfg.maxPips or 5
                for p = 1, n do
                    local pip = f.pips[p]
                    if pip then
                        if p <= cur then
                            pip:SetVertexColor(cfg.r or 1, cfg.g or 0.8, cfg.b or 0.1, 1)
                        else
                            pip:SetVertexColor(0.3, 0.3, 0.3, 0.5)
                        end
                    end
                end
                f.value:SetText(cfg.showValue and (math.floor(cur) .. "/" .. n) or "")
            else
                local frac = cur / max
                local totalW = f:GetWidth()
                f.fill:SetWidth(math.max(1, totalW * frac))
                f.value:SetText(cfg.showValue and (math.floor(cur) .. "/" .. math.floor(max)) or "")
            end
        end)
    end
end
API.UpdateAllBars = UpdateAllBars

-- ── Event-driven power updates ────────────────────────────────────────────────
-- Replace OnUpdate polling with WoW power events — guaranteed non-nil, no taint.
updateFrame:RegisterEvent("UNIT_POWER_FREQUENT")
updateFrame:RegisterEvent("UNIT_MAXPOWER")
updateFrame:RegisterEvent("UNIT_HEALTH")
updateFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
updateFrame:SetScript("OnEvent", function(self, event, unit)
    -- Filter to player-only events; PLAYER_ENTERING_WORLD has no unit arg
    -- Allow updates for any tracked unit (player, party members, target, focus)
    if unit ~= nil then
        local tracked = false
        for i = 1, MAX_BARS do
            local cfg = barConfigs[i]
            if cfg and cfg.enabled and (cfg.unit or "player") == unit then
                tracked = true; break
            end
        end
        if not tracked then return end
    end
    UpdateAllBars()
end)

-- ── Layout handle provider ────────────────────────────────────────────────────
API.RegisterLayoutHandles(function()
    local handles = {}
    for i = 1, MAX_BARS do
        local f   = barFrames[i]
        local cfg = barConfigs[i]
        if f and f:IsShown() and cfg and cfg.enabled then
            local ox = cfg.x or 0; local oy = cfg.y or -200
            table.insert(handles, {
                label       = "Bar " .. i .. ": " .. (cfg.label or ""),
                iconTex     = "Interface\\Icons\\inv_misc_coin_01",
                ox          = ox, oy = oy,
                liveFrameRef= f,
                saveCallback= function(nx, ny)
                    cfg.x = nx; cfg.y = ny
                    if BuffAlertDB then API.SaveSpecProfile() end
                end,
            })
        end
    end
    return handles
end)

-- ── Slash command ─────────────────────────────────────────────────────────────
SLASH_CSBARS1 = "/csbars"
SlashCmdList["CSBARS"] = function()
    local mainFrame = _G["MidnightQoLMainFrame"]
    if mainFrame then mainFrame:Show() end
    -- Activate Resources tab if available
    local tabRegistry = API.GetTabRegistry and API.GetTabRegistry()
    if tabRegistry then
        for i, t in ipairs(tabRegistry) do
            if t.label == "Resources" then
                if API.ActivateTabByIndex then API.ActivateTabByIndex(i) end
                return
            end
        end
    end
end