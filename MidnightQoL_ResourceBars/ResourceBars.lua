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
-- Each shape entry has:
--   key       unique string identifier
--   label     shown in the UI dropdown
--   tex       texture path — must be a white/alpha silhouette so SetVertexColor
--             correctly tints it.  All textures below are pre-existing WoW files.
--   wMult     optional width multiplier vs pip size (default 1)
--   hMult     optional height multiplier vs pip size (default 1)
--
-- SetVertexColor works on file-based textures.
-- SetColorTexture (procedural) does NOT support SetMask/shapes — avoid it for pips.

local PIP_SHAPES = {
    -- ── Basic geometry ────────────────────────────────────────────────────────
    {
        key="square",
        label="Square",
        tex="Interface\\Buttons\\WHITE8x8",
    },
    {
        key="circle",
        label="Circle",
        tex="Interface\\CharacterFrame\\TempPortraitAlphaMask",
    },
    -- ── Diamond ───────────────────────────────────────────────────────────────
    {
        key="diamond",
        label="Diamond",
        tex="Interface\\AddOns\\MidnightQoL\\Images\\pip_diamond",
    },
    -- ── Rune ─────────────────────────────────────────────────────────────────
    {
        key="rune",
        label="Rune",
        tex="Interface\\AddOns\\MidnightQoL\\Images\\pip_rune",
    },
    -- ── Star ─────────────────────────────────────────────────────────────────
    {
        key="star",
        label="Star",
        tex="Interface\\AddOns\\MidnightQoL\\Images\\pip_star",
    },
    -- ── Arrow ────────────────────────────────────────────────────────────────
    {
        key="arrow",
        label="Arrow",
        tex="Interface\\AddOns\\MidnightQoL\\Images\\pip_arrow",
    },
    -- ── Skull ────────────────────────────────────────────────────────────────
    {
        key="skull",
        label="Skull",
        tex="Interface\\AddOns\\MidnightQoL\\Images\\pip_skull",
    },
    -- ── Moon ─────────────────────────────────────────────────────────────────
    {
        key="moon",
        label="Moon",
        tex="Interface\\AddOns\\MidnightQoL\\Images\\pip_moon",
    },
    -- ── Lightning ─────────────────────────────────────────────────────────────
    -- Custom white-on-transparent bolt silhouette bundled with the addon.
    {
        key="lightning",
        label="Lightning",
        tex="Interface\\AddOns\\MidnightQoL\\Images\\pip_lightning",
    },
}

local PIP_SHAPE_INDEX = {}
for _, s in ipairs(PIP_SHAPES) do PIP_SHAPE_INDEX[s.key] = s end

-- Returns actual pixel width, height for a given base pip size and shape.
local function PipDimensions(ps, shapeKey)
    local shape = PIP_SHAPE_INDEX[shapeKey or "square"]
    if not shape then return ps, ps end
    local pw = math.max(4, math.floor(ps * (shape.wMult or 1) + 0.5))
    local ph = math.max(4, math.floor(ps * (shape.hMult or 1) + 0.5))
    return pw, ph
end

-- Create a new pip Frame with the correct texture for shapeKey.
local function CreatePipFrame(parent, shapeKey, pw, ph)
    local shape = PIP_SHAPE_INDEX[shapeKey or "square"]
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(pw, ph)
    local tex = f:CreateTexture(nil, "ARTWORK")
    tex:SetTexture(shape and shape.tex or "Interface\\Buttons\\WHITE8x8")
    tex:SetAllPoints(f)
    tex:SetVertexColor(1, 1, 1, 1)
    f.tex = tex
    return f
end

-- Tint an existing pip frame.
local function ColorPip(pip, r, g, b, a)
    if pip and pip.tex then pip.tex:SetVertexColor(r, g, b, a or 1) end
end

-- Swap the texture (and optionally resize) when the shape setting changes.
local function ApplyPipShape(pip, shapeKey, pw, ph)
    if not pip or not pip.tex then return end
    local shape = PIP_SHAPE_INDEX[shapeKey or "square"]
    pip.tex:SetTexture(shape and shape.tex or "Interface\\Buttons\\WHITE8x8")
    if pw and ph then pip:SetSize(pw, ph) end
end

API.PIP_SHAPES    = PIP_SHAPES
API.PipDimensions = PipDimensions
API.ColorPip      = ColorPip
API.ApplyPipShape = ApplyPipShape

local MAELSTROM_WEAPON = 21  -- Enhancement buff (already declared above; kept for clarity)
local WILD_IMPS        = 22  -- fake power type: Demonology Warlock Wild Imps

-- ── Wild Imp count: read from Implosion button's Count FontString ─────────────
-- GetActionInfo and C_ActionBar APIs can't reliably identify Implosion by spell ID
-- on paged/override bars. Instead we find the button once OOC using SpellIsTargeting
-- or by checking the button's spell name via GameTooltip, then cache the FontString.
-- Simplest reliable method: use GetActionInfo with the correct paged slot offset.
local IMPLOSION_SPELL_ID = 196277
local implosionCountFontStr = nil

local function FindImplosionCountFontStr()
    -- GetActionInfo may return a valid spellID that doesn't match 196277 directly
    -- (can happen with overrideSpellID substitution). Match by spell name instead,
    -- which is always safe and works regardless of ID remapping.
    local implosionName
    local ok, info = pcall(C_Spell.GetSpellInfo, IMPLOSION_SPELL_ID)
    if ok and info and info.name then
        implosionName = info.name
    else
        implosionName = "Implosion"  -- hardcoded fallback
    end

    local prefixes = {
        "ActionButton","MultiBarBottomLeftButton","MultiBarBottomRightButton",
        "MultiBarRightButton","MultiBarLeftButton",
        "MultiBar5Button","MultiBar6Button","MultiBar7Button","MultiBar8Button",
    }
    for _, prefix in ipairs(prefixes) do
        for i = 1, 12 do
            local name = prefix .. i
            local btn = _G[name]
            if btn and btn.action then
                local atype, _, spellID = GetActionInfo(btn.action)
                if atype == "spell" and spellID then
                    -- Match by ID first, then by name as fallback
                    local matched = (spellID == IMPLOSION_SPELL_ID)
                    if not matched then
                        local nok, ninfo = pcall(C_Spell.GetSpellInfo, spellID)
                        if nok and ninfo and ninfo.name == implosionName then
                            matched = true
                        end
                    end
                    if matched then
                        local fs = btn.Count or _G[name .. "Count"]
                        if fs and type(fs.GetText) == "function" then return fs end
                    end
                end
            end
        end
    end
    return nil
end

local function GetWildImpCount()
    if InCombatLockdown() then
        if not implosionCountFontStr then return 0 end
        return tonumber(implosionCountFontStr:GetText()) or 0
    end
    implosionCountFontStr = FindImplosionCountFontStr()
    if not implosionCountFontStr then return 0 end
    return tonumber(implosionCountFontStr:GetText()) or 0
end

local SECONDARY_POWER_TYPES = {
    [Enum.PowerType.RunicPower]=true, [Enum.PowerType.HolyPower]=true, [Enum.PowerType.Chi]=true,
    [Enum.PowerType.ComboPoints]=true, [Enum.PowerType.ArcaneCharges]=true, [Enum.PowerType.SoulShards]=true,
    [Enum.PowerType.LunarPower]=true, [Enum.PowerType.Maelstrom]=true, [Enum.PowerType.Insanity]=true,
    [Enum.PowerType.Essence]=true, [Enum.PowerType.Runes]=true, [STAGGER]=true, [MAELSTROM_WEAPON]=true,
    [WILD_IMPS]=true,
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
    [266]={Enum.PowerType.Mana, Enum.PowerType.SoulShards, WILD_IMPS},  -- Demonology
    [267]={Enum.PowerType.Mana, Enum.PowerType.SoulShards},
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
    elseif pt == WILD_IMPS then
        -- Wild Imps: read count from Implosion action button (safe frame-state read)
        cur = GetWildImpCount()
        -- max pips driven by cfg.maxPips; default display cap of 6 for Demonology
        max = (cfg.maxPips and cfg.maxPips > 0) and cfg.maxPips or 6
    else
        cur = GetPower(unit, pt) or 0
        max = GetPowerMax(unit, pt) or 1
    end

    if cfg.isPip then
        -- Use the live game maximum as the pip count so resources like Combo Points
        -- and Maelstrom Weapon automatically show the correct number of pips.
        -- cfg.maxPips acts as a manual override when explicitly set (>0).
        local n = (cfg.maxPips and cfg.maxPips > 0) and cfg.maxPips or max
        n = math.max(1, math.min(n, 25))  -- clamp 1–25

        -- Grow pip pool on-demand if needed
        if #f.pips < n then
            for p = #f.pips + 1, n do
                local ps = cfg.pipSize or 18
                local pw, ph = PipDimensions(ps, cfg.pipShape)
                f.pips[p] = CreatePipFrame(f, cfg.pipShape or "square", pw, ph)
            end
        end

        local activeR, activeG, activeB = cfg.r or 1, cfg.g or 0.8, cfg.b or 0.1
        for p = 1, 25 do
            local pip = f.pips[p]
            if pip then
                if p <= n then
                    pip:Show()
                    if p <= cur then
                        ColorPip(pip, activeR, activeG, activeB, 1)
                    else
                        ColorPip(pip, 0.3, 0.3, 0.3, 0.5)
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
    f:SetScript("OnDragStart", function(self) if not (API.IsLayoutMode and API.IsLayoutMode()) then return end; self:StartMoving() end)
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

    -- Text frames parented to UIParent at HIGH strata so they always
    -- render above the bar fills regardless of frame level.
    local labelFrame = CreateFrame("Frame", nil, UIParent)
    labelFrame:SetAllPoints(f)
    labelFrame:SetFrameStrata("HIGH")
    labelFrame:SetFrameLevel(100)
    f.label = labelFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.label:SetPoint("BOTTOM", labelFrame, "TOP", 0, 2)

    local valueFrame = CreateFrame("Frame", nil, UIParent)
    valueFrame:SetAllPoints(f)
    valueFrame:SetFrameStrata("HIGH")
    valueFrame:SetFrameLevel(100)
    f.value = valueFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.value:SetPoint("CENTER", valueFrame, "CENTER", 0, 0)
    f.value:SetFont(f.value:GetFont(), 11, "OUTLINE")
    -- Keep refs so we can reanchor if the bar moves
    f.labelFrame = labelFrame
    f.valueFrame = valueFrame

    f.pips = {}
    for p = 1, 10 do
        f.pips[p] = CreatePipFrame(f, "square", 18, 18)
        f.pips[p]:Hide()
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
                elseif cfg.powerType == WILD_IMPS then
                    liveMax = 6  -- sensible default max for pip display
                else
                    liveMax = GetPowerMax(ResolveUnit(cfg.unit), cfg.powerType) or 10
                end
                local n = (cfg.maxPips and cfg.maxPips > 0) and cfg.maxPips or liveMax
                n = math.max(1, math.min(n, 25))
                -- Grow pip pool if needed
                if #f.pips < n then
                    for p = #f.pips + 1, n do
                        f.pips[p] = CreatePipFrame(f, cfg.pipShape or "square", ps, ps)
                        f.pips[p]:Hide()
                    end
                end
                -- Shape-aware pip dimensions
                local pw, ph = PipDimensions(ps, cfg.pipShape)
                -- Centre the pip row within the frame
                local totalW = n * (pw + gap) - gap
                f:SetSize(totalW, ph)
                local startX = 0  -- left-anchored; frame is centred by SetPoint("CENTER")
                for p = 1, 25 do
                    if p <= n then
                        f.pips[p]:SetSize(pw, ph)
                        f.pips[p]:SetPoint("LEFT", f, "LEFT", startX + (p-1)*(pw+gap), 0)
                        ApplyPipShape(f.pips[p], cfg.pipShape, pw, ph)
                        f.pips[p]:Show()
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
API.RebuildLiveBars               = RebuildBars
API.barConfigs                    = barConfigs
API.MAELSTROM_WEAPON              = MAELSTROM_WEAPON
API.MAELSTROM_WEAPON_SPELL_ID     = MAELSTROM_WEAPON_SPELL_ID
API.MAELSTROM_WEAPON_SPELL_ID_OLD = MAELSTROM_WEAPON_SPELL_ID_OLD
API.SPEC_POWERS                   = SPEC_POWERS
API.WILD_IMPS                     = WILD_IMPS
API.GetWildImpCount               = GetWildImpCount

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
Events:RegisterEvent("ACTIONBAR_SLOT_CHANGED")

Events:SetScript("OnEvent", function(self, event, unit)
    if event == "ACTIONBAR_SLOT_CHANGED" then
        implosionCountFontStr = nil
        return
    end
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

        -- Keep Maelstrom Weapon count fresh on every aura change

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