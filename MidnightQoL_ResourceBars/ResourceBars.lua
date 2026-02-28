-- ============================================================
-- MidnightQoL_ResourceBars / ResourceBars.lua
-- ============================================================

local API = MidnightQoLAPI

-- ── Constants & Localized Functions ──────────────────────────────────────────
local GetPower    = UnitPower
local GetPowerMax = UnitPowerMax
local STAGGER          = 20  -- fake power type: uses UnitStagger/UnitHealthMax
local MAELSTROM_WEAPON = 21  -- fake power type: Enhancement buff
-- Spell ID changed in The War Within (11.0). Try new ID first, fall back to classic.
local MAELSTROM_WEAPON_SPELL_ID      = 344179  -- TWW / Dragonflight rework
local MAELSTROM_WEAPON_SPELL_ID_OLD  = 53817   -- classic / pre-rework fallback

-- ── Pip shape definitions ────────────────────────────────────────────────────
-- All shapes use SetColorTexture for reliable solid fills in TWW.
-- Circle uses a guaranteed WoW mask texture to punch a circular cutout.
local CIRCLE_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"

local PIP_SHAPES = {
    { key="square",  label="■ Square",  mask=nil },
    { key="circle",  label="● Circle",  mask=CIRCLE_MASK },
    { key="wide",    label="▬ Wide",    mask=nil, wide=true },
    { key="thin",    label="| Thin",    mask=nil, thin=true },
}
local PIP_SHAPE_INDEX = {}
for _, s in ipairs(PIP_SHAPES) do PIP_SHAPE_INDEX[s.key] = s end

local function ApplyPipShape(pip, shapeKey)
    pip:SetColorTexture(1, 1, 1, 1)  -- solid white; color set per-frame via SetColorTexture
    local shape = PIP_SHAPE_INDEX[shapeKey or "square"]
    if shape and shape.mask then
        pip:SetMask(shape.mask)
    else
        pip:SetMask(nil)
    end
end
API.PIP_SHAPES = PIP_SHAPES

local SECONDARY_POWER_TYPES = {
    [Enum.PowerType.RunicPower]=true, [Enum.PowerType.HolyPower]=true, [Enum.PowerType.Chi]=true,
    [Enum.PowerType.ComboPoints]=true, [Enum.PowerType.ArcaneCharges]=true, [Enum.PowerType.SoulShards]=true,
    [Enum.PowerType.LunarPower]=true, [Enum.PowerType.Maelstrom]=true, [Enum.PowerType.Insanity]=true,
    [Enum.PowerType.Essence]=true, [Enum.PowerType.Runes]=true, [STAGGER]=true, [MAELSTROM_WEAPON]=true,
}

-- ── Spec → valid power types ──────────────────────────────────────────────────
-- Keyed by specID (4th return of GetSpecializationInfo). Each entry lists every
-- power type that spec can meaningfully display, so the UI picker can filter.
-- Enhancement (263) lists MAELSTROM_WEAPON (21) not Enum.PowerType.Maelstrom (11).
local SPEC_POWERS = {
    -- Death Knight
    [250]={Enum.PowerType.Runes, Enum.PowerType.RunicPower},
    [251]={Enum.PowerType.Runes, Enum.PowerType.RunicPower},
    [252]={Enum.PowerType.Runes, Enum.PowerType.RunicPower},
    -- Demon Hunter
    [577]={Enum.PowerType.Fury},
    [581]={Enum.PowerType.Pain},
    -- Druid
    [102]={Enum.PowerType.Mana,   Enum.PowerType.LunarPower},
    [103]={Enum.PowerType.Energy, Enum.PowerType.ComboPoints},
    [104]={Enum.PowerType.Rage},
    [105]={Enum.PowerType.Mana},
    -- Evoker
    [1467]={Enum.PowerType.Mana, Enum.PowerType.Essence},
    [1468]={Enum.PowerType.Mana, Enum.PowerType.Essence},
    [1473]={Enum.PowerType.Mana, Enum.PowerType.Essence},
    -- Hunter
    [253]={Enum.PowerType.Focus},
    [254]={Enum.PowerType.Focus},
    [255]={Enum.PowerType.Focus},
    -- Mage
    [62] ={Enum.PowerType.Mana, Enum.PowerType.ArcaneCharges},
    [63] ={Enum.PowerType.Mana},
    [64] ={Enum.PowerType.Mana},
    -- Monk
    [268]={Enum.PowerType.Energy, STAGGER},               -- Brewmaster: Energy + Stagger (no Chi)
    [269]={Enum.PowerType.Energy, Enum.PowerType.Chi},
    [270]={Enum.PowerType.Mana},
    -- Paladin
    [65] ={Enum.PowerType.Mana, Enum.PowerType.HolyPower},
    [66] ={Enum.PowerType.Mana},
    [70] ={Enum.PowerType.Mana, Enum.PowerType.HolyPower},
    -- Priest
    [256]={Enum.PowerType.Mana},
    [257]={Enum.PowerType.Mana},
    [258]={Enum.PowerType.Mana, Enum.PowerType.Insanity},
    -- Rogue
    [259]={Enum.PowerType.Energy, Enum.PowerType.ComboPoints},
    [260]={Enum.PowerType.Energy, Enum.PowerType.ComboPoints},
    [261]={Enum.PowerType.Energy, Enum.PowerType.ComboPoints},
    -- Shaman
    [262]={Enum.PowerType.Mana, Enum.PowerType.Maelstrom},  -- Elemental
    [263]={Enum.PowerType.Mana, MAELSTROM_WEAPON},           -- Enhancement
    [264]={Enum.PowerType.Mana},                             -- Restoration
    -- Warlock
    [265]={Enum.PowerType.Mana, Enum.PowerType.SoulShards},
    [266]={Enum.PowerType.Mana},
    [267]={Enum.PowerType.Mana},
    -- Warrior
    [71] ={Enum.PowerType.Rage},
    [72] ={Enum.PowerType.Rage},
    [73] ={Enum.PowerType.Rage},
}

-- ── State ────────────────────────────────────────────────────────────────────
local resourceBarsEnabled = true
local MAX_BARS   = 2
local barConfigs = {}
local barFrames  = {}
local roleUnitCache = {}

-- ── Utility ──────────────────────────────────────────────────────────────────
local function ResolveUnit(unitCfg)
    if not unitCfg then return "player" end
    return roleUnitCache[unitCfg] or unitCfg
end

local function RefreshBar(i)
    local f = barFrames[i]
    local cfg = barConfigs[i]
    if not f or not f:IsShown() or not cfg or not cfg.enabled then return end

    local unit = ResolveUnit(cfg.unit)
    if not UnitExists(unit) then return end

    local pt = cfg.powerType
    local cur, max
    if pt == STAGGER then
        cur = UnitStagger(unit) or 0
        max = UnitHealthMax(unit) or 1
    elseif pt == MAELSTROM_WEAPON then
        -- Maelstrom Weapon is a stacking buff on Enhancement Shaman, not a power
        -- type. Spell ID changed in TWW; try new ID first then classic fallback.
        local aura = C_UnitAuras.GetPlayerAuraBySpellID(MAELSTROM_WEAPON_SPELL_ID)
                  or C_UnitAuras.GetPlayerAuraBySpellID(MAELSTROM_WEAPON_SPELL_ID_OLD)
        cur = aura and aura.applications or 0
        max = 10
    else
        cur = GetPower(unit, pt) or 0
        max = GetPowerMax(unit, pt) or 1
    end

    if cfg.isPip then
        -- Use the live game maximum as the pip count so resources like Combo Points
        -- and Maelstrom Weapon automatically show the correct number of pips.
        -- cfg.maxPips acts as a manual override when explicitly set (>0).
        local n = (cfg.maxPips and cfg.maxPips > 0) and cfg.maxPips or max
        n = math.max(1, math.min(n, 20))  -- clamp 1–20

        -- Grow pip pool on-demand if needed
        if #f.pips < n then
            for p = #f.pips + 1, n do
                f.pips[p] = f:CreateTexture(nil, "ARTWORK")
                ApplyPipShape(f.pips[p], cfg.pipShape)
            end
        end

        local activeR, activeG, activeB = cfg.r or 1, cfg.g or 0.8, cfg.b or 0.1
        for p = 1, 20 do
            local pip = f.pips[p]
            if pip then
                if p <= n then
                    pip:Show()
                    if p <= cur then
                        pip:SetColorTexture(activeR, activeG, activeB, 1)
                    else
                        pip:SetColorTexture(0.3, 0.3, 0.3, 0.5)
                    end
                else
                    pip:Hide()
                end
            end
        end
    else
        f.bar:SetAllPoints(f)  -- ensure it's full width (may have been moved)
        f.bar:SetMinMaxValues(0, max)
        f.bar:SetValue(cur)
        f.bar:SetStatusBarColor(cfg.r or 0.2, cfg.g or 0.6, cfg.b or 1, 0.9)
    end

    local pipN = (cfg.isPip and ((cfg.maxPips and cfg.maxPips > 0) and cfg.maxPips or max)) or max
    f.value:SetText(cfg.showValue and (cur .. "/" .. math.floor(pipN)) or "")
    f.label:SetText(cfg.showLabel and (cfg.label or "") or "")
end

-- ── Frame Creation ───────────────────────────────────────────────────────────
local function CreateResourceBarFrame(i)
    if barFrames[i] then return barFrames[i] end

    local f = CreateFrame("Frame", nil, UIParent) -- Anonymous frame
    f:SetFrameStrata("MEDIUM")
    f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
    f:SetClampedToScreen(true)
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local cfg = barConfigs[i]
        if cfg then
            local cx, cy = UIParent:GetWidth()/2, UIParent:GetHeight()/2
            cfg.x = math.floor(self:GetLeft() + self:GetWidth()/2 - cx + 0.5)
            cfg.y = math.floor(self:GetBottom() + self:GetHeight()/2 - cy + 0.5)
        end
    end)

    -- The actual StatusBar (Taint-safe)
    f.bar = CreateFrame("StatusBar", nil, f)
    f.bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    f.bar:SetAllPoints(f)
    
    f.bg = f.bar:CreateTexture(nil, "BACKGROUND")
    f.bg:SetAllPoints(f)

    f.label = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.label:SetPoint("BOTTOM", f, "TOP", 0, 2)

    f.value = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.value:SetPoint("CENTER", f, "CENTER", 0, 0)
    f.value:SetFont(f.value:GetFont(), 11, "OUTLINE")

    f.pips = {}
    for p = 1, 10 do
        f.pips[p] = f:CreateTexture(nil, "ARTWORK")
        f.pips[p]:SetColorTexture(1, 1, 1, 1)
    end

    barFrames[i] = f
    return f
end

local function RebuildBars()
    for i = 1, MAX_BARS do
        local cfg = barConfigs[i]
        local f = CreateResourceBarFrame(i)
        if cfg and cfg.enabled and resourceBarsEnabled then
            f:ClearAllPoints()
            f:SetPoint("CENTER", UIParent, "CENTER", cfg.x or 0, cfg.y or -200)
            if cfg.isPip then
                f.bar:Hide()
                local ps, gap = cfg.pipSize or 18, cfg.pipGap or 4
                -- Derive pip count from live game max; cfg.maxPips is a manual override
                local liveMax
                if cfg.powerType == MAELSTROM_WEAPON then
                    liveMax = 10
                else
                    liveMax = GetPowerMax(ResolveUnit(cfg.unit), cfg.powerType) or 10
                end
                local n = (cfg.maxPips and cfg.maxPips > 0) and cfg.maxPips or liveMax
                n = math.max(1, math.min(n, 20))
                -- Grow pip pool if needed
                if #f.pips < n then
                    for p = #f.pips + 1, n do
                        f.pips[p] = f:CreateTexture(nil, "ARTWORK")
                    end
                end
                -- Shape-aware pip dimensions
                local shape = PIP_SHAPE_INDEX[cfg.pipShape or "square"]
                local pw = ps  -- pip width
                local ph = ps  -- pip height
                if shape and shape.wide then pw = ps * 2; ph = math.max(8, ps / 2)
                elseif shape and shape.thin then pw = math.max(4, ps / 3); ph = ps end
                f:SetSize(n * (pw + gap) - gap, ph)
                for p = 1, 20 do
                    if p <= n then
                        f.pips[p]:SetSize(pw, ph)
                        f.pips[p]:SetPoint("LEFT", f, "LEFT", (p-1)*(pw+gap), 0)
                        ApplyPipShape(f.pips[p], cfg.pipShape)
                    elseif f.pips[p] then
                        f.pips[p]:ClearAllPoints()
                        f.pips[p]:Hide()
                    end
                end
            else
                f.bar:Show()
                f:SetSize(cfg.w or 200, cfg.h or 20)
                f.bg:SetColorTexture(cfg.bgR or 0.1, cfg.bgG or 0.1, cfg.bgB or 0.1, 0.8)
                for p=1,20 do if f.pips[p] then f.pips[p]:Hide() end end
            end
            f:Show()
            RefreshBar(i)
        else
            f:Hide()
        end
    end
end
API.RebuildLiveBars           = RebuildBars
API.barConfigs                = barConfigs
API.MAELSTROM_WEAPON          = MAELSTROM_WEAPON
API.MAELSTROM_WEAPON_SPELL_ID = MAELSTROM_WEAPON_SPELL_ID
API.MAELSTROM_WEAPON_SPELL_ID_OLD = MAELSTROM_WEAPON_SPELL_ID_OLD
API.SPEC_POWERS               = SPEC_POWERS

-- ── Layout handle provider ────────────────────────────────────────────────────
API.RegisterLayoutHandles(function()
    local handles = {}
    for i = 1, MAX_BARS do
        local f   = barFrames[i]
        local cfg = barConfigs[i]
        if f and f:IsShown() and cfg and cfg.enabled then
            local ox = cfg.x or 0; local oy = cfg.y or -200
            table.insert(handles, {
                label        = "Bar " .. i .. (cfg.label ~= "" and cfg.label and (": " .. cfg.label) or ""),
                iconTex      = "Interface\\Icons\\inv_misc_coin_01",
                ox           = ox, oy = oy,
                liveFrameRef = f,
                saveCallback = function(nx, ny)
                    cfg.x = nx; cfg.y = ny
                    if BuffAlertDB and API.SaveSpecProfile then API.SaveSpecProfile() end
                end,
                resizeCallback = function(nw, nh)
                    cfg.w = math.floor(nw + 0.5)
                    cfg.h = math.floor(nh + 0.5)
                    f:SetSize(cfg.w, cfg.h)
                    if BuffAlertDB and API.SaveSpecProfile then API.SaveSpecProfile() end
                    -- Refresh UI edit boxes if open
                    local wEdit = _G["CSBar"..i.."W"]; if wEdit then wEdit:SetText(tostring(cfg.w)) end
                    local hEdit = _G["CSBar"..i.."H"]; if hEdit then hEdit:SetText(tostring(cfg.h)) end
                end,
            })
        end
    end
    return handles
end)

-- ── Event Registry ───────────────────────────────────────────────────────────
local Events = CreateFrame("Frame")
Events:RegisterEvent("PLAYER_ENTERING_WORLD")
Events:RegisterEvent("UNIT_POWER_UPDATE")
Events:RegisterEvent("UNIT_MAXPOWER")
Events:RegisterEvent("UNIT_AURA")           -- for Maelstrom Weapon stacks
Events:RegisterEvent("GROUP_ROSTER_UPDATE")

Events:SetScript("OnEvent", function(self, event, unit)
    if event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ENTERING_WORLD" then
        wipe(roleUnitCache)
        for _, u in ipairs({"player","party1","party2","party3","party4"}) do
            if UnitExists(u) then
                local r = UnitGroupRolesAssigned(u)
                if r and r ~= "NONE" then roleUnitCache["role:"..r] = u end
            end
        end
        if event == "PLAYER_ENTERING_WORLD" then RebuildBars() end
    end

    for i = 1, MAX_BARS do
        local cfg = barConfigs[i]
        if cfg and cfg.enabled then
            if not unit or unit == ResolveUnit(cfg.unit) then
                RefreshBar(i)
            end
        end
    end
end)

-- Smooth update for things like Energy/Mana regen
local elapsedTotal = 0
Events:SetScript("OnUpdate", function(self, elapsed)
    elapsedTotal = elapsedTotal + elapsed
    if elapsedTotal < 0.05 then return end
    elapsedTotal = 0
    for i = 1, MAX_BARS do RefreshBar(i) end
end)

-- ── Profile Integration ──────────────────────────────────────────────────────
local CHI_TYPE = Enum.PowerType.Chi  -- 12

API.RegisterProfileCallbacks(
    function(p) p.resourceBars = {} for i=1,MAX_BARS do if barConfigs[i] then p.resourceBars[i] = CopyTable(barConfigs[i]) end end end,
    function(p)
        for i=1,MAX_BARS do barConfigs[i] = p.resourceBars and p.resourceBars[i] or nil end
        -- Migration: Brewmaster (268) should never have Chi — replace with Stagger
        if API.currentSpecID == 268 then
            for i=1,MAX_BARS do
                local cfg = barConfigs[i]
                if cfg and cfg.powerType == CHI_TYPE then
                    cfg.powerType = STAGGER
                    cfg.isPip     = false
                    cfg.isBar     = true
                end
            end
        end
        if BuffAlertDB then resourceBarsEnabled = BuffAlertDB.resourceBarsEnabled ~= false end
        RebuildBars()
    end
)