-- ============================================================
-- RogUI / Modules / ImprovedCDM / ImprovedCDM.lua
--
-- FULLY MERGED: ImprovedCDM + BuffAlerts + CooldownKeybinds + UI
-- All three modules combined into one efficient unified module
-- ============================================================

local API = RogUIAPI
if not API then return end

local MODULE_NAME = "ImprovedCDM"

-- ════════════════════════════════════════════════════════════
-- SECTION 1: IMPROVED CDM - Database and Constants
-- ════════════════════════════════════════════════════════════

local DB_KEY = "improvedCDM"

-- ── Constants ─────────────────────────────────────────────────────────────────

local FRAME_PREFIX = "ICDM_"

-- CDM TriggerAlertEvent numeric codes (Enum.CooldownViewerAlertEventType)
local EVT_AVAILABLE     = 1
local EVT_PANDEMIC      = 2
local EVT_ON_COOLDOWN   = 3
local EVT_CHARGE_GAINED = 4

-- Default values for a new icon set
local SET_DEFAULTS = {
    iconSize        = 36,
    iconWidth       = 36,
    iconHeight      = 36,
    gridRows        = 2,
    gridCols        = 4,
    spacing         = 2,
    posX            = 0,
    posY            = 100,
    showBorder      = false,
    showBackground  = true,
    visibility      = "always",   -- "always" | "combat" | "ooc"
    borderR = 0.5, borderG = 0.5, borderB = 0.5, borderA = 1.0,
    bgR     = 0.0, bgG     = 0.0, bgB     = 0.0, bgA     = 0.6,
    alpha   = 1.0,
    enabled = true,
}

-- ── Module state ──────────────────────────────────────────────────────────────

local iconSets     = {}   -- [setName] = set object (runtime containers)
local spellSounds  = {}   -- [tostring(spellID)] = { onAvailable={}, ... }
local hookedFrames = {}   -- [frame] = true  (already hooked CDM icons)
local inCombat     = false

-- Expose on API so ImprovedCDMUI.lua can reach them directly
API.icdm_iconSets    = iconSets
API.icdm_spellSounds = spellSounds

-- ── Helpers ───────────────────────────────────────────────────────────────────

local function DeepCopy(orig)
    if type(orig) ~= "table" then return orig end
    local copy = {}
    for k, v in pairs(orig) do copy[DeepCopy(k)] = DeepCopy(v) end
    setmetatable(copy, getmetatable(orig))
    return copy
end

local function GetRootDB()
    if not RogUIDB then return nil end
    if not RogUIDB[DB_KEY] then
        RogUIDB[DB_KEY] = { sets = {}, spellSounds = {} }
    end
    local db = RogUIDB[DB_KEY]
    if not db.sets        then db.sets        = {} end
    if not db.spellSounds then db.spellSounds = {} end
    return db
end

-- ── Visibility management ─────────────────────────────────────────────────────

local function ApplyContainerVisibility(set)
    if not set or not set.container then return end
    if set.db.enabled == false then
        set.container:Hide()
        return
    end
    local v = set.db.visibility or "always"
    if     v == "combat" then
        if inCombat then set.container:Show() else set.container:Hide() end
    elseif v == "ooc"    then
        if inCombat then set.container:Hide() else set.container:Show() end
    else
        set.container:Show()
    end
end

local function ApplyAllVisibility()
    for _, set in pairs(iconSets) do
        ApplyContainerVisibility(set)
    end
end

-- ── Container build / rebuild ─────────────────────────────────────────────────

local function BuildContainer(setName, db)
    local frameName = FRAME_PREFIX .. setName

    -- Reuse existing frame across spec-swaps / refreshes
    local container = _G[frameName]
    if not container then
        container = CreateFrame("Frame", frameName, UIParent, "BackdropTemplate")
        container._isICDMContainer = true
        container:SetMovable(true)
        container:EnableMouse(false)
        container:SetClampedToScreen(true)
    end

    -- Size from layout settings
    local slotW   = db.iconWidth  or db.iconSize or SET_DEFAULTS.iconWidth
    local slotH   = db.iconHeight or db.iconSize or SET_DEFAULTS.iconHeight
    local spacing = db.spacing    or SET_DEFAULTS.spacing
    local cols    = db.gridCols   or SET_DEFAULTS.gridCols
    local rows    = db.gridRows   or SET_DEFAULTS.gridRows
    local pad     = 6
    local w = cols * slotW + (cols - 1) * spacing + pad * 2
    local h = rows * slotH + (rows - 1) * spacing + pad * 2
    container:SetSize(math.max(slotW, w), math.max(slotH, h))
    container:ClearAllPoints()
    container:SetPoint("CENTER", UIParent, "CENTER", db.posX or 0, db.posY or 100)

    -- Apply the alpha setting 
    -- (Prioritizes global RogUIDB.cdmAlpha, fallback to db.alpha or 1.0)
    local targetAlpha = 1.0
    if RogUIDB and RogUIDB.cdmAlpha then
        targetAlpha = RogUIDB.cdmAlpha
        db.alpha = RogUIDB.cdmAlpha 
    elseif db.alpha then
        targetAlpha = db.alpha
    end
    container:SetAlpha(targetAlpha)

    -- Backdrop
    container:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 2,
    })
    
    if db.showBackground then
        container:SetBackdropColor(
            db.bgR or 0, db.bgG or 0, db.bgB or 0, db.bgA or 0.6)
    else
        container:SetBackdropColor(0, 0, 0, 0)
    end

    if db.showBorder then
        container:SetBackdropBorderColor(
            db.borderR or 0.5, db.borderG or 0.5, db.borderB or 0.5, db.borderA or 1)
    else
        container:SetBackdropBorderColor(0, 0, 0, 0)
    end

    container:SetFrameStrata("MEDIUM")

    -- Taint-safe anchor proxy — external addons anchor to this, not the container
    local proxyName = frameName .. "_Anchor"
    local proxy = _G[proxyName]
    if not proxy then
        proxy = CreateFrame("Frame", proxyName, UIParent)
        proxy._isICDMAnchor = true
        proxy:EnableMouse(false)
    end
    proxy:SetSize(container:GetSize())
    proxy:ClearAllPoints()
    proxy:SetPoint("CENTER", container, "CENTER", 0, 0)
    proxy:SetFrameStrata("BACKGROUND")

    return container
end
-- ── Icon set object ───────────────────────────────────────────────────────────

local function NewIconSet(setName, db)
    -- Fill any missing fields from defaults
    for k, v in pairs(SET_DEFAULTS) do
        if db[k] == nil then db[k] = v end
    end
    local container, proxy = BuildContainer(setName, db)
    return {
        name      = setName,
        db        = db,
        container = container,
        proxy     = proxy,
        members   = {},
    }
end

-- ── Public: icon set management ───────────────────────────────────────────────

function API.ICDM_CreateSet(setName)
    if not setName or setName == "" then return nil end
    if iconSets[setName] then return iconSets[setName] end
    local rootDB = GetRootDB()
    if not rootDB then return nil end
    if not rootDB.sets[setName] then
        rootDB.sets[setName] = DeepCopy(SET_DEFAULTS)
    end
    local set = NewIconSet(setName, rootDB.sets[setName])
    iconSets[setName] = set
    ApplyContainerVisibility(set)
    return set
end

function API.ICDM_DeleteSet(setName)
    local set = iconSets[setName]
    if not set then return end
    -- Reparent any member icons back to UIParent
    for frame in pairs(set.members) do
        if frame:GetParent() == set.container then
            frame:SetParent(UIParent)
        end
    end
    if set.container then set.container:Hide() end
    iconSets[setName] = nil
    local rootDB = GetRootDB()
    if rootDB then rootDB.sets[setName] = nil end
end

function API.ICDM_RefreshSet(setName)
    local set = iconSets[setName]
    if not set then return end
    BuildContainer(setName, set.db)
    ApplyContainerVisibility(set)
end

function API.ICDM_ApplyIconStyle(icon, db)
    if not icon or not db then return end
    -- Enforce strict sizing, falling back to 36 if uninitialized
    local sizeW = db.iconWidth or db.iconSize or 36
    local sizeH = db.iconHeight or db.iconSize or 36
    icon:SetSize(sizeW, sizeH)
    
    if icon.icon then 
        icon.icon:SetSize(sizeW, sizeH) 
    end
    
    -- Force the cooldown spiral to perfectly match the icon boundaries
    if icon.cooldown then 
        icon.cooldown:SetAllPoints(icon) 
    end
end

-- ============================================================
-- NEW: Taunt Alert Router
-- ============================================================
function API.TriggerTauntAlert(spellID, stacks)
    -- Look for a specific ImprovedCDM bar named "TauntWatch"
    local tauntSet = API.icdm_iconSets["TauntWatch"]
    
    if tauntSet then
        -- Push the taunt swap data directly into the CDM bar system
        if API.ICDM_UpdateIcon then
            API.ICDM_UpdateIcon(tauntSet, spellID, {
                texture = C_Spell.GetSpellTexture(spellID) or "Interface\\Icons\\INV_Misc_QuestionMark",
                count = stacks,
                duration = 10, -- Standard alert duration
            })
        end
    end
end

-- ── CDM icon frame hooking ────────────────────────────────────────────────────

local function GetSpellIDFromFrame(frame)
    -- Best path: CDM's cooldownID → C_CooldownViewer API
    if frame.cooldownID and C_CooldownViewer
            and C_CooldownViewer.GetCooldownViewerCooldownInfo then
        local info = C_CooldownViewer.GetCooldownViewerCooldownInfo(frame.cooldownID)
        if info and info.spellID then return info.spellID end
    end
    -- Direct field on frame
    if frame.spellID then return frame.spellID end
    -- BCDM name pattern fallback
    if frame.GetName then
        local n = frame:GetName()
        if n then
            local id = tonumber(n:match("^BCDM_Custom_(%d+)"))
                    or tonumber(n:match("^BCDM_AdditionalCustom_(%d+)"))
            if id then return id end
        end
    end
    return nil
end

local function HookIconFrame(frame)
    if hookedFrames[frame]          then return end
    if not frame.TriggerAlertEvent  then return end
    hookedFrames[frame] = true

    hooksecurefunc(frame, "TriggerAlertEvent", function(self, eventType)
        local spellID = GetSpellIDFromFrame(self)
        if not spellID then return end
        local entry = spellSounds[tostring(spellID)]
        if not entry then return end

        local se
        if     eventType == EVT_AVAILABLE     then se = entry.onAvailable
        elseif eventType == EVT_PANDEMIC      then se = entry.onPandemic
        elseif eventType == EVT_ON_COOLDOWN   then se = entry.onCooldown
        elseif eventType == EVT_CHARGE_GAINED then se = entry.onChargeGained
        end

        if se and se.sound then
            API.PlayCustomSound(se.sound, se.soundIsID)
        end
    end)
end

-- All known CDM viewer / container frame names in _G
local CDM_VIEWERS = {
    "EssentialCooldownViewer",
    "UtilityCooldownViewer",
    "EssentialCooldownViewer_CDM_Container",
    "UtilityCooldownViewer_CDM_Container",
    "CDM_DefensivesContainer",
    "CDM_TrinketsContainer",
    "CDM_RacialsContainer",
    "BCDM_CustomCooldownViewer",
    "BCDM_CustomItemSpellBar",
    "BCDM_CustomItemBar",
    "BCDM_AdditionalCustomCooldownViewer",
    "BCDM_TrinketBar",
}

local function ScanAndHookViewers()
    for _, viewerName in ipairs(CDM_VIEWERS) do
        local viewer = _G[viewerName]
        if viewer and viewer.GetChildren then
            for _, child in ipairs({viewer:GetChildren()}) do
                HookIconFrame(child)
                -- Some viewers nest icons one level deeper
                if child.GetChildren then
                    for _, grandchild in ipairs({child:GetChildren()}) do
                        HookIconFrame(grandchild)
                    end
                end
            end
        end
    end
    -- Also hook icons inside our own ICDM containers
    for _, set in pairs(iconSets) do
        if set.container and set.container.GetChildren then
            for _, child in ipairs({set.container:GetChildren()}) do
                HookIconFrame(child)
            end
        end
    end
end

-- ── Public: spell sound management ───────────────────────────────────────────

-- eventKey: "onAvailable" | "onPandemic" | "onCooldown" | "onChargeGained"
function API.ICDM_SetSpellSound(spellID, eventKey, sound, soundIsID)
    if not spellID or not eventKey then return end
    local key = tostring(spellID)

    -- Runtime table
    if not spellSounds[key] then
        spellSounds[key] = {
            onAvailable    = {},
            onPandemic     = {},
            onCooldown     = {},
            onChargeGained = {},
        }
    end
    local entry = spellSounds[key]
    if not entry[eventKey] then entry[eventKey] = {} end
    entry[eventKey].sound     = sound
    entry[eventKey].soundIsID = soundIsID

    -- Persist to DB
    local rootDB = GetRootDB()
    if not rootDB then return end
    if not rootDB.spellSounds[key] then
        rootDB.spellSounds[key] = {
            onAvailable    = {},
            onPandemic     = {},
            onCooldown     = {},
            onChargeGained = {},
        }
    end
    if not rootDB.spellSounds[key][eventKey] then
        rootDB.spellSounds[key][eventKey] = {}
    end
    rootDB.spellSounds[key][eventKey].sound     = sound
    rootDB.spellSounds[key][eventKey].soundIsID = soundIsID
end

function API.ICDM_ClearSpellSound(spellID, eventKey)
    if not spellID then return end
    local key = tostring(spellID)
    if eventKey then
        if spellSounds[key] then spellSounds[key][eventKey] = nil end
        local rootDB = GetRootDB()
        if rootDB and rootDB.spellSounds[key] then
            rootDB.spellSounds[key][eventKey] = nil
        end
    else
        spellSounds[key] = nil
        local rootDB = GetRootDB()
        if rootDB then rootDB.spellSounds[key] = nil end
    end
end

-- ── Spec profile: save / load ─────────────────────────────────────────────────

local function OnSaveProfile(profile)
    if not profile then return end
    local rootDB = GetRootDB()
    if not rootDB then return end

    -- Flush any live-dragged container positions into DB before serialising
    for setName, set in pairs(iconSets) do
        if set.container and rootDB.sets[setName] then
            local cx, cy = set.container:GetCenter()
            local ux, uy = UIParent:GetCenter()
            if cx and ux then
                rootDB.sets[setName].posX = cx - ux
                rootDB.sets[setName].posY = (cy or 0) - (uy or 0)
            end
        end
    end

    profile.icdm = {
        sets        = DeepCopy(rootDB.sets),
        spellSounds = DeepCopy(rootDB.spellSounds),
    }
end

local function OnLoadProfile(profile)
    if not profile then return end
    local rootDB = GetRootDB()
    if not rootDB then return end

    if profile.icdm then
        if profile.icdm.sets        then
            rootDB.sets        = DeepCopy(profile.icdm.sets)
        end
        if profile.icdm.spellSounds then
            rootDB.spellSounds = DeepCopy(profile.icdm.spellSounds)
        end
    end

    -- Rebuild runtime spell sounds table
    wipe(spellSounds)
    for k, v in pairs(rootDB.spellSounds) do
        spellSounds[k] = DeepCopy(v)
    end

    -- Rebuild icon sets
    for setName in pairs(iconSets) do API.ICDM_DeleteSet(setName) end
    for setName in pairs(rootDB.sets) do API.ICDM_CreateSet(setName) end

    C_Timer.After(0.5, ScanAndHookViewers)

    -- Refresh the settings tab if it is currently visible
    if API.ICDM_RefreshTabUI then
        C_Timer.After(0.1, API.ICDM_RefreshTabUI)
    end
end

API.RegisterProfileCallbacks(OnSaveProfile, OnLoadProfile)

-- ── Layout mode provider ──────────────────────────────────────────────────────
-- Handle structure matches Core.lua's EnterLayoutMode exactly:
--   { label, iconTex, ox, oy, liveFrameRef, saveCallback }

API.RegisterLayoutHandles(function()
    local handles = {}
    for setName, set in pairs(iconSets) do
        if set.container and set.db.enabled ~= false then
            local cx, cy   = set.container:GetCenter()
            local ux, uy   = UIParent:GetCenter()
            local ox = cx and ux and (cx - ux) or (set.db.posX or 0)
            local oy = cy and uy and (cy - uy) or (set.db.posY or 0)

            local capturedName = setName
            local capturedSet  = set

            table.insert(handles, {
                label        = "CDM Set: " .. setName,
                iconTex      = "Interface\\Icons\\Ability_Cooldown",
                ox           = ox,
                oy           = oy,
                liveFrameRef = set.container,
                saveCallback = function(nx, ny)
                    capturedSet.db.posX = nx
                    capturedSet.db.posY = ny
                    -- Persist to DB immediately
                    local rootDB = GetRootDB()
                    if rootDB and rootDB.sets[capturedName] then
                        rootDB.sets[capturedName].posX = nx
                        rootDB.sets[capturedName].posY = ny
                    end
                    -- Sync the position EditBoxes in the UI tab if open
                    if API.ICDM_SyncSetPosition then
                        API.ICDM_SyncSetPosition(capturedName, nx, ny)
                    end
                end,
            })
        end
    end
    return handles
end)

-- ════════════════════════════════════════════════════════════
-- SECTION 2: BUFF ALERTS - Core Logic
-- ════════════════════════════════════════════════════════════

-- ── State ─────────────────────────────────────────────────────────────────────
local trackedBuffs     = {}
--[[ DEBUFFS/EXTERNALS DISABLED — for future development
local trackedDebuffs   = {}
local trackedExternals = {}
--]]

local activeAlerts     = {}
-- Alerts triggered by the buff-viewer OnShow/OnHide hook.
-- Only OnBuffViewerFrameHide may dismiss these.
local buffViewerAlerts = {}

-- Expose on API so BuffAlertsUI and Layout mode can access them
API.trackedBuffs     = trackedBuffs
--[[ DEBUFFS/EXTERNALS DISABLED — for future development
API.trackedDebuffs   = trackedDebuffs
API.trackedExternals = trackedExternals
--]]


local buffDebuffAlertsEnabled = true

-- Declared here (used by buff hook section below)
local buffHookedFrames = {}

-- Stack tracking removed: buffs are tracked purely via CooldownViewer/BuffTracker
-- frame show/hide. No C_UnitAuras stack reads, no count cache.

-- ── Spell list helpers (used by spell picker) ─────────────────────────────────
local function GetClassSpellList(listType)
    local map = {
        WARRIOR    = WarriorSpells,    PALADIN  = PaladinSpells,
        HUNTER     = HunterSpells,     ROGUE    = RogueSpells,
        PRIEST     = PriestSpells,     DRUID    = DruidSpells,
        SHAMAN     = ShamanSpells,     MAGE     = MageSpells,
        WARLOCK    = WarlockSpells,    DEATHKNIGHT = DeathKnightSpells,
        DEMONHUNTER = DemonHunterSpells, MONK   = MonkSpells,
        EVOKER     = EvokerSpells,
    }
    local t = map[API.playerClass or ""]
    -- Spell files use plural keys ("buffs"/"debuffs"); auraType is singular ("buff"/"debuff")
    local key = (listType == "buff") and "buffs" or (listType == "debuff") and "debuffs" or listType
    return (t and t[key]) or {}
end

local function GetAvailableSpells(listType)
    local available = {}
    if listType == "external" then
        if ExternalBuffSpells then
            for _, spell in ipairs(ExternalBuffSpells) do
                if spell.ids then table.insert(available, {id=spell.ids[1], ids=spell.ids, name=spell.name})
                else table.insert(available, {id=spell.id, name=spell.name}) end
            end
        end
    else
        -- Universal presets shown for all classes at the top of the buff list
        if listType == "buff" then
            table.insert(available, {
                id            = 57723,
                name          = "Lust / Sated (all variants)",
                isLustTracker = true,
            })
        end
        for _, spell in ipairs(GetClassSpellList(listType)) do
            table.insert(available, {id=spell.id, name=spell.name})
        end
    end
    return available
end
API.GetAvailableSpells = GetAvailableSpells

-- ── Spec profile callbacks ─────────────────────────────────────────────────────
local function OnSaveProfile(profile)
    profile.trackedBuffs     = trackedBuffs
--[[ DEBUFFS/EXTERNALS DISABLED — for future development
    profile.trackedDebuffs   = trackedDebuffs
    profile.trackedExternals = trackedExternals
--]]

    profile.buffDebuffAlertsEnabled = buffDebuffAlertsEnabled
    -- Keep legacy flat keys for backward compat
    if RogUIDB then
        RogUIDB.trackedBuffs     = trackedBuffs
--[[ DEBUFFS/EXTERNALS DISABLED — for future development
        RogUIDB.trackedDebuffs   = trackedDebuffs
        RogUIDB.trackedExternals = trackedExternals
--]]

        RogUIDB.buffDebuffAlertsEnabled = buffDebuffAlertsEnabled
    end
end

local function OnLoadProfile(profile)
    -- Wipe and repopulate the SAME table objects so all upvalue references stay valid
    for k in pairs(trackedBuffs)     do trackedBuffs[k]     = nil end
--[[ DEBUFFS/EXTERNALS DISABLED — for future development
    for k in pairs(trackedDebuffs)   do trackedDebuffs[k]   = nil end
    for k in pairs(trackedExternals) do trackedExternals[k] = nil end
--]]


    for _, v in ipairs(profile.trackedBuffs     or {}) do table.insert(trackedBuffs,     v) end
--[[ DEBUFFS/EXTERNALS DISABLED — for future development
    for _, v in ipairs(profile.trackedDebuffs   or {}) do table.insert(trackedDebuffs,   v) end
    for _, v in ipairs(profile.trackedExternals or {}) do table.insert(trackedExternals, v) end
--]]


    -- Migrate: old default alertDuration of 3 was saved before "0 = stay forever" behaviour.
    -- Clear it to 0 so buff-viewer-owned alerts stay up until the buff actually falls off.
    local function stripOldDuration(list)
        for _, aura in ipairs(list) do
            if aura.alertDuration == 3 then aura.alertDuration = 0 end
        end
    end
    stripOldDuration(trackedBuffs)
--[[ DEBUFFS/EXTERNALS DISABLED — for future development
    stripOldDuration(trackedDebuffs)
    stripOldDuration(trackedExternals)
--]]


    local savedEnabled = profile.buffDebuffAlertsEnabled
    if savedEnabled == nil then
        savedEnabled = RogUIDB and RogUIDB.buffDebuffAlertsEnabled
    end
    buffDebuffAlertsEnabled = (savedEnabled == true)
    if API.buffAlertEnabledCheckbox then
        API.buffAlertEnabledCheckbox:SetChecked(buffDebuffAlertsEnabled)
    end
    -- Refresh UI if open
    if API.RefreshAuraListUI then API.RefreshAuraListUI() end
    -- Rebuild spell→CooldownID map for new profile data
    C_Timer.After(0.1, function() if API.RebuildNameMap then API.RebuildNameMap() end end)
end

API.RegisterProfileCallbacks(OnSaveProfile, OnLoadProfile)

-- Also watch the feature toggle checkbox
local function SyncFeatureToggle()
    if not API.buffAlertEnabledCheckbox then return end
    buffDebuffAlertsEnabled = API.buffAlertEnabledCheckbox:GetChecked()
    if RogUIDB then RogUIDB.buffDebuffAlertsEnabled = buffDebuffAlertsEnabled end
end
-- Hook fires after Core's checkbox exists (it's created before sub-addons load via TOC order)
if API.buffAlertEnabledCheckbox then
    API.buffAlertEnabledCheckbox:HookScript("OnClick", SyncFeatureToggle)
end

-- ── Visual alert overlay pool ─────────────────────────────────────────────────
local ALERT_POOL_SIZE = 8
local alertPool       = {}
local activeOverlays  = {}

local function CreateAlertOverlayFrame(i)
    local f = CreateFrame("Frame","RogUIAlertOverlay"..i, UIParent)
    f:SetFrameStrata("FULLSCREEN_DIALOG"); f:SetFrameLevel(100)
    f:SetSize(64,64); f:SetPoint("CENTER",UIParent,"CENTER",0,0); f:Hide()
    local tex = f:CreateTexture(nil,"ARTWORK",nil,7); tex:SetAllPoints(f)
    tex:SetTexCoord(0.08,0.92,0.08,0.92); f.tex = tex
    local cd = CreateFrame("Cooldown",nil,f,"CooldownFrameTemplate")
    cd:SetAllPoints(f); cd:SetDrawEdge(false); cd:SetHideCountdownNumbers(false); f.cooldown = cd
    f:SetScript("OnShow", function(self) self:SetAlpha(0); UIFrameFadeIn(self,0.15,0,1) end)
    f.sourceFrame = nil
    return f
end

-- ── Progress bar alert pool ───────────────────────────────────────────────────
local BAR_POOL_SIZE = 8
local barAlertPool  = {}

local function CreateAlertBarFrame(i)
    local f = CreateFrame("Frame","RogUIAlertBar"..i, UIParent)
    f:SetFrameStrata("FULLSCREEN_DIALOG"); f:SetFrameLevel(100)
    f:SetSize(200, 26); f:SetPoint("CENTER",UIParent,"CENTER",0,0); f:Hide()

    -- Outer border (1px darker rim)
    local border = f:CreateTexture(nil,"BACKGROUND",nil,-1)
    border:SetAllPoints(f); border:SetColorTexture(0,0,0,0.9); f.border = border

    -- Dark background inset
    local bg = f:CreateTexture(nil,"BACKGROUND")
    bg:SetPoint("TOPLEFT",f,"TOPLEFT",1,-1)
    bg:SetPoint("BOTTOMRIGHT",f,"BOTTOMRIGHT",-1,1)
    bg:SetColorTexture(0.05,0.05,0.05,0.85); f.bg = bg

    -- Solid colour fill bar — uses a plain white texture so SetStatusBarColor
    -- gives a fully saturated, untextured solid fill with no fading atlas
    local bar = CreateFrame("StatusBar", nil, f)
    bar:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
    bar:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)
    local barTex = bar:CreateTexture(nil,"ARTWORK")
    barTex:SetColorTexture(1,1,1,1)
    bar:SetStatusBarTexture(barTex)
    bar:SetMinMaxValues(0, 1); bar:SetValue(1)
    bar:SetStatusBarColor(0.2, 0.8, 1, 1)
    f.bar = bar
    f.barTex = barTex

    -- Subtle gloss/shine strip across the top third
    local gloss = f:CreateTexture(nil,"OVERLAY")
    gloss:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
    gloss:SetPoint("TOPRIGHT", f, "TOPRIGHT", -1, 0)
    gloss:SetHeight(4)
    gloss:SetColorTexture(1,1,1,0.08); f.gloss = gloss

    -- Spell icon on the left (square, fills height)
    local iconBg = f:CreateTexture(nil,"ARTWORK")
    iconBg:SetPoint("TOPLEFT",f,"TOPLEFT",1,-1)
    iconBg:SetPoint("BOTTOMLEFT",f,"BOTTOMLEFT",1,1)
    iconBg:SetWidth(24); iconBg:SetColorTexture(0,0,0,0.5); f.iconBg = iconBg

    local icon = f:CreateTexture(nil,"ARTWORK",nil,1); icon:SetSize(22,22)
    icon:SetPoint("CENTER", iconBg, "CENTER", 0, 0)
    icon:SetTexCoord(0.08,0.92,0.08,0.92); f.icon = icon

    -- Thin separator between icon and bar
    local sep = f:CreateTexture(nil,"OVERLAY")
    sep:SetPoint("TOPLEFT",f,"TOPLEFT",25,-1)
    sep:SetPoint("BOTTOMLEFT",f,"BOTTOMLEFT",25,1)
    sep:SetWidth(1); sep:SetColorTexture(0,0,0,0.6); f.sep = sep

    -- Spell name label (left, after icon)
    local nameStr = f:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    nameStr:SetPoint("LEFT", f, "LEFT", 32, 0)
    nameStr:SetPoint("RIGHT", f, "RIGHT", -34, 0)
    nameStr:SetJustifyH("LEFT")
    nameStr:SetFont(nameStr:GetFont(), 11, "OUTLINE")
    nameStr:SetTextColor(1,1,1,1)
    f.nameStr = nameStr

    -- Stack count on the right
    local stackStr = f:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    stackStr:SetPoint("RIGHT", f, "RIGHT", -4, 0)
    stackStr:SetJustifyH("RIGHT")
    stackStr:SetFont(stackStr:GetFont(), 12, "OUTLINE")
    stackStr:SetTextColor(1,1,0,1)
    f.stackStr = stackStr

    -- Timer text (remaining seconds, shown when duration is known)
    local timerStr = f:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    timerStr:SetPoint("RIGHT", f, "RIGHT", -4, 0)
    timerStr:SetJustifyH("RIGHT")
    timerStr:SetFont(timerStr:GetFont(), 10, "OUTLINE")
    timerStr:SetTextColor(0.9,0.9,0.9,0.8)
    timerStr:Hide()
    f.timerStr = timerStr

    -- No fade-in: just appear immediately at full alpha
    f:SetAlpha(1)
    f.sourceFrame = nil
    f.progressTimer = nil
    return f
end

for i = 1, BAR_POOL_SIZE do barAlertPool[i] = CreateAlertBarFrame(i) end

local function GetFreeBarAlertFrame()
    for _, f in ipairs(barAlertPool) do if not f:IsShown() then return f end end
    barAlertPool[1]:Hide(); return barAlertPool[1]
end

for i = 1, ALERT_POOL_SIZE do alertPool[i] = CreateAlertOverlayFrame(i) end

local function GetFreeAlertFrame()
    for _, f in ipairs(alertPool) do if not f:IsShown() then return f end end
    alertPool[1]:Hide(); return alertPool[1]
end

local function ReleaseOverlay(alertKey)
    local f = activeOverlays[alertKey]; if not f then return end
    activeOverlays[alertKey] = nil
    if f.sourceFrame then f.sourceFrame:SetAlpha(1); f.sourceFrame = nil end
    -- Cancel all timers
    if f.durationTimer then f.durationTimer:Cancel(); f.durationTimer = nil end
    if f.progressTimer then f.progressTimer:Cancel(); f.progressTimer = nil end
    if f.cooldown then
        -- Icon mode: fade out smoothly
        f.cooldown:Clear()
        UIFrameFadeOut(f, 0.2, f:GetAlpha(), 0)
        C_Timer.After(0.2, function() f:Hide() end)
    else
        -- Bar mode: clear OnUpdate and snap off immediately
        f:SetScript("OnUpdate", nil)
        f.lastCount = nil
        f:Hide()
    end
end

local function ShowAlertOverlay(aura, spellName, sourceFrame)
    -- Bar mode
    if aura.alertMode == "bar" then
        local sz   = tonumber(aura.alertSize)     or 26
        local barW = tonumber(aura.alertBarWidth)  or 200
        local ox   = tonumber(aura.alertX)         or 0
        local oy   = tonumber(aura.alertY)         or 0
        local f    = GetFreeBarAlertFrame()
        f:SetSize(barW, sz); f:ClearAllPoints()
        f:SetPoint("CENTER", UIParent, "CENTER", ox, oy)
        f:SetAlpha(1)

        local br = tonumber(aura.barR) or 0.2
        local bg_ = tonumber(aura.barG) or 0.8
        local bb  = tonumber(aura.barB) or 1.0
        f.bar:SetStatusBarColor(br, bg_, bb, 1.0)

        local iconTex
        if aura.spellId and aura.spellId > 0 then
            local info = C_Spell.GetSpellInfo(aura.spellId)
            iconTex = info and info.iconID
        end
        f.icon:SetTexture(iconTex or "Interface\\Icons\\INV_Misc_QuestionMark")
        f.nameStr:SetText(spellName or "")
        f.stackStr:SetText(""); f.stackStr:Hide()
        f.sourceFrame = sourceFrame

        if f.durationTimer then f.durationTimer:Cancel(); f.durationTimer = nil end
        if f.progressTimer then f.progressTimer:Cancel(); f.progressTimer = nil end
        f:SetScript("OnUpdate", nil)
        f.lastCount = nil

        -- Duration drain: bar drains from full → 0 over the aura's lifetime.
        -- Read duration OOC only; in combat the bar stays full (we have no safe
        -- way to get expiration time without C_UnitAuras).
        local totalDur, remaining
        if aura.spellId and aura.spellId > 0 and not InCombatLockdown() then
            local ok, auraData = pcall(C_UnitAuras.GetPlayerAuraBySpellID, aura.spellId)
            if ok and auraData and auraData.duration and auraData.duration > 0 then
                totalDur  = auraData.duration
                remaining = auraData.expirationTime - GetTime()
            end
        end
        if totalDur and totalDur > 0 and remaining and remaining > 0 then
            f.bar:SetMinMaxValues(0, totalDur)
            f.bar:SetValue(remaining)
            f.progressTimer = C_Timer.NewTicker(0.1, function()
                if not f:IsShown() then f.progressTimer:Cancel(); f.progressTimer = nil; return end
                if InCombatLockdown() then return end
                local ok2, ad2 = pcall(C_UnitAuras.GetPlayerAuraBySpellID, aura.spellId)
                if ok2 and ad2 and ad2.expirationTime and ad2.expirationTime > 0 then
                    local timeLeft = ad2.expirationTime - GetTime()
                    f.bar:SetMinMaxValues(0, ad2.duration > 0 and ad2.duration or totalDur)
                    f.bar:SetValue(math.max(0, timeLeft))
                end
            end)
        else
            f.bar:SetMinMaxValues(0, 1); f.bar:SetValue(1)
        end

        f:Show()
        local dur = tonumber(aura.alertDuration)
        if dur and dur > 0 and dur < 9999 and not f.boundToHandle then
            f.durationTimer = C_Timer.NewTimer(dur, function()
                f.durationTimer = nil
                if f:IsShown() and not f.boundToHandle then f:Hide() end
            end)
        end
        return f
    end

    -- Icon mode (default)
    if not aura or not aura.alertTexture or aura.alertTexture == "" then return end
    local texVal = tostring(aura.alertTexture)
    if texVal == "spell_icon" then
        if aura.spellId and aura.spellId > 0 then
            local info = C_Spell.GetSpellInfo(aura.spellId)
            texVal = info and tostring(info.iconID) or "Interface\\Icons\\INV_Misc_QuestionMark"
        else texVal = "Interface\\Icons\\INV_Misc_QuestionMark" end
    else
        local shorthand = texVal:match("^spell:(%d+)$")
        if shorthand then
            local info = C_Spell.GetSpellInfo(tonumber(shorthand))
            texVal = info and tostring(info.iconID) or texVal
        end
    end
    local texArg = tonumber(texVal) or texVal
    local sz = tonumber(aura.alertSize) or 64
    local ox = tonumber(aura.alertX)   or 0
    local oy = tonumber(aura.alertY)   or 0
    local f  = GetFreeAlertFrame()
    f:SetSize(sz,sz); f:ClearAllPoints(); f:SetPoint("CENTER",UIParent,"CENTER",ox,oy)
    f.tex:SetTexture(texArg); f.sourceFrame = sourceFrame; f.cooldown:Clear(); f:Show()
    -- No stack text on icon overlays
    if f.stackText then f.stackText:SetText("") end
    if f.durationTimer then f.durationTimer:Cancel(); f.durationTimer = nil end
    local dur = tonumber(aura.alertDuration)
    if dur and dur > 0 and dur < 9999 and not f.boundToHandle then
        f.durationTimer = C_Timer.NewTimer(dur, function()
            f.durationTimer = nil
            if f:IsShown() and not f.boundToHandle then
                UIFrameFadeOut(f, 0.4, f:GetAlpha(), 0)
                C_Timer.After(0.4, function() if not f.boundToHandle then f:Hide() end end)
            end
        end)
    end
    return f
end

API.ShowAlertOverlay = ShowAlertOverlay
API._hideAlertPreviewsBase = function()
    for _, f in ipairs(alertPool) do
        if f.durationTimer then f.durationTimer:Cancel(); f.durationTimer = nil end
        f.cooldown:Clear(); f.boundToHandle = nil; f:Hide(); f.sourceFrame = nil
    end
    for _, f in ipairs(barAlertPool) do
        if f.durationTimer then f.durationTimer:Cancel(); f.durationTimer = nil end
        if f.progressTimer then f.progressTimer:Cancel(); f.progressTimer = nil end
        f.boundToHandle = nil; f:Hide(); f.sourceFrame = nil
    end
end

-- ── Glow system ────────────────────────────────────────────────────────────────
local spellGlowFrames = {}

local function CreateGlowFrame(r, g, b)
    -- Parent to UIParent temporarily; will be re-anchored to the alert overlay at ShowGlow time.
    local glow = CreateFrame("Frame", nil, UIParent)
    glow:SetFrameStrata("FULLSCREEN_DIALOG")
    glow:SetFrameLevel(200)
    glow:SetSize(64, 64)
    glow:Hide()
    local function makeEdge(point, relPoint, w, h)
        local t = glow:CreateTexture(nil, "OVERLAY")
        t:SetTexture("Interface\\SpellActivationOverlay\\IconAlert")
        t:SetTexCoord(0, 1, 0, 0.5); t:SetVertexColor(r, g, b, 0.85); t:SetSize(w, h)
        t:SetPoint(point, glow, relPoint, 0, 0)
    end
    makeEdge("TOP","TOP",64,16); makeEdge("BOTTOM","BOTTOM",64,16)
    makeEdge("LEFT","LEFT",16,64); makeEdge("RIGHT","RIGHT",16,64)
    local ag = glow:CreateAnimationGroup(); ag:SetLooping("BOUNCE")
    local anim = ag:CreateAnimation("Alpha"); anim:SetFromAlpha(0.4); anim:SetToAlpha(1.0)
    anim:SetDuration(0.6); anim:SetSmoothing("IN_OUT"); glow.animGroup = ag
    function glow:ShowGlow(anchorFrame)
        -- Anchor to the alert overlay so the glow sits on top of it.
        -- Fall back to a sensible screen position if no anchor is given.
        self:ClearAllPoints()
        if anchorFrame and anchorFrame.IsShown and anchorFrame:IsShown() then
            self:SetParent(anchorFrame)
            self:SetAllPoints(anchorFrame)
        else
            self:SetParent(UIParent)
            self:SetPoint("CENTER", UIParent, "CENTER", 0, -100)
            self:SetSize(64, 64)
        end
        self:Show(); self.animGroup:Play()
    end
    function glow:HideGlow()
        self.animGroup:Stop()
        self:Hide()
    end
    return glow
end

local function GetOrCreateGlowForAura(aura)
    local sid = aura.spellId; if not sid or sid <= 0 then return nil end
    if spellGlowFrames[sid] then return spellGlowFrames[sid] end
    local r, g, b = 1, 0.8, 0
    if aura.glowColor then r=aura.glowColor[1] or r; g=aura.glowColor[2] or g; b=aura.glowColor[3] or b end
    local gf = CreateGlowFrame(r, g, b)
    spellGlowFrames[sid] = gf; return gf
end

-- ── CooldownViewer hook ────────────────────────────────────────────────────────
local HookBuffViewerPanels       -- forward declaration
local IsBuffViewerFrameShowing
local cidToEntry = {}
local sidToEntry = {}
local hookedFrames       = {}
local pendingHide        = {}

local function OnCooldownViewerFrameShow(self)
    if not buffDebuffAlertsEnabled then return end
    local cid = self.cooldownID; if not cid then return end
    local entry = cidToEntry[cid]
    if not entry then
        -- CID not in map yet — try to resolve by spell ID and cache for next time
        local spellID
        pcall(function()
            local ci = self.cooldownInfo
            if ci then spellID = ci.overrideSpellID or ci.spellID end
        end)
        if spellID and sidToEntry[spellID] then
            entry = sidToEntry[spellID]; cidToEntry[cid] = entry
        end
    end
    if not entry or entry.aura.enabled == false then return end
    local alertKey = entry.alertKey
    pendingHide[alertKey] = nil
    -- Don't hide buff-section frames — they show the active buff icon and
    -- should remain visible while the buff is up. Only hide pure cooldown frames.
    if not buffHookedFrames[self] then self:SetAlpha(0) end
    if activeAlerts[alertKey] then return end
    activeAlerts[alertKey] = true
    local spellName = ""
    local ok, sinfo = pcall(C_Spell.GetSpellInfo, entry.sid)
    if ok and sinfo then spellName = sinfo.name or "" end
    if entry.aura.sound then API.PlayCustomSound(entry.aura.sound, entry.aura.soundIsID) end
    local overlay = ShowAlertOverlay(entry.aura, spellName, self)
    if overlay then activeOverlays[alertKey] = overlay end
    if API.DEBUG then print(entry.color .. "[RogUI]|r " .. entry.label .. ": " .. spellName) end
    if entry.aura.glowEnabled then
        local gf = GetOrCreateGlowForAura(entry.aura); if gf then gf:ShowGlow(overlay) end
    end
end

local function OnCooldownViewerFrameHide(self)
    local cid = self.cooldownID; if not cid then return end
    local entry = cidToEntry[cid]; if not entry then return end
    local alertKey = entry.alertKey
    if not activeAlerts[alertKey] then return end
    self:SetAlpha(1)
    pendingHide[alertKey] = true
    C_Timer.After(0.1, function()
        if not pendingHide[alertKey] then return end
        pendingHide[alertKey] = nil
        activeAlerts[alertKey] = nil
        ReleaseOverlay(alertKey)
        local gf = spellGlowFrames[alertKey]; if gf then gf:HideGlow() end
    end)
end

local function HookItemFrame(frame)
    if hookedFrames[frame] then return end
    if not frame.cooldownID then return end
    hookedFrames[frame] = true
    frame:HookScript("OnShow", OnCooldownViewerFrameShow)
    frame:HookScript("OnHide",  OnCooldownViewerFrameHide)
end

local function RebuildNameMap()
    cidToEntry = {}; sidToEntry = {}

    -- Register a spell ID strictly by SID and CID — no name fallback.
    -- Name-based matching caused cross-spell collisions (e.g. Celestial Brew
    -- triggering a Fortifying Brew alert because both share "Brew" in their
    -- cooldown bucket name). Exact ID matching only.
    -- CID deduplication: if two tracked spells share a cooldown ID (same bucket),
    -- the first registration wins and the second is skipped for CID mapping.
    -- Both still exist in sidToEntry (debuff/external tracking disabled for now)
    local function addByID(sid, aura, label, color, alertKey)
        if not sid or sid <= 0 then return end
        if sidToEntry[sid] then return end  -- already registered
        local entry = {aura=aura, label=label, color=color, alertKey=alertKey, sid=sid}
        sidToEntry[sid] = entry
        local ok, cid = pcall(C_Spell.GetSpellCooldownID, sid)
        if ok and cid and cid > 0 then
            if not cidToEntry[cid] then cidToEntry[cid] = entry end
        end
    end

    for _, buff in ipairs(trackedBuffs) do
        if buff.enabled ~= false and buff.spellId and buff.spellId > 0 then
            addByID(buff.spellId, buff, "Gained", "|cFF00FF00", buff.spellId)
        end
    end
    --[[ DEBUFFS/EXTERNALS DISABLED — for future development
    for _, debuff in ipairs(trackedDebuffs) do
        if debuff.enabled ~= false and debuff.spellId and debuff.spellId > 0 then
            addByID(debuff.spellId, debuff, "Debuff", "|cFFFF0000", debuff.spellId)
        end
    end
    for _, ext in ipairs(trackedExternals) do
        if ext.enabled ~= false then
            local watchIds = (ext.spellIds and #ext.spellIds > 0) and ext.spellIds or {tonumber(ext.spellId)}
            local alertKey = tonumber(watchIds[1]) or 0
            for _, wid in ipairs(watchIds) do
                if wid and wid > 0 then
                    addByID(wid, ext, "External", "|cFF00CCFF", alertKey)
                end
            end
        end
    end
    --]]

    local panelNames = {
        "EssentialCooldownViewer","UtilityCooldownViewer","BuffIconCooldownViewer",
        "CooldownViewerSystem","CooldownViewerFrame","BuffAndEssentialCooldownViewer",
    }
    local hookCount = 0

    -- Map a frame CID to an entry using only exact spell-ID lookup.
    -- No name fallback — names are not unique enough to be safe.
    local function tryMapFrame(child)
        local cid = child.cooldownID
        if not cid then return end
        if cidToEntry[cid] then return end  -- already mapped
        local frameSpellID = child.rangeCheckSpellID
        if not frameSpellID then
            pcall(function()
                if child.cooldownInfo then
                    frameSpellID = child.cooldownInfo.overrideSpellID or child.cooldownInfo.spellID
                end
            end)
        end
        if frameSpellID and sidToEntry[frameSpellID] then
            cidToEntry[cid] = sidToEntry[frameSpellID]
        end
    end

    local function walkFrame(parent, depth)
        if not parent or depth > 4 then return end
        local ok, children = pcall(function() return {parent:GetChildren()} end)
        if not ok then return end
        for _, child in ipairs(children) do
            if child.cooldownID ~= nil then
                if not buffHookedFrames[child] then
                    HookItemFrame(child); hookCount = hookCount + 1
                    tryMapFrame(child)
                end
            else walkFrame(child, depth+1) end
        end
    end
    for _, name in ipairs(panelNames) do walkFrame(_G[name], 0) end
    if hookCount == 0 then
        for fname, fval in pairs(_G) do
            if type(fname)=="string" and fname:find("CooldownViewer")
               and type(fval)=="table" and type(fval.GetChildren)=="function" then
                walkFrame(fval, 0)
            end
        end
    end

    -- Restore CID mappings for frames hooked in previous calls
    -- (cidToEntry is wiped at the top of this function on every rebuild).
    for frame in pairs(hookedFrames) do
        local cid = frame.cooldownID
        if cid and not cidToEntry[cid] then
            tryMapFrame(frame)
        end
    end

    local cidCount = 0; for _ in pairs(cidToEntry) do cidCount = cidCount + 1 end
    API.Debug("RebuildNameMap: " .. cidCount .. " CIDs mapped, hookCount=" .. hookCount)
    lastHookCount = hookCount
    HookBuffViewerPanels()
end
API.RebuildNameMap = RebuildNameMap

-- ── Buff viewer panel hooks ────────────────────────────────────────────────────
-- These resolve the forward declarations at the top of the CooldownViewer section.

IsBuffViewerFrameShowing = function(sid)
    for frame in pairs(buffHookedFrames) do
        local fsid = frame.buffSpellID or frame.spellID
        if fsid == sid and frame:IsShown() then return true end
    end
    return false
end

local function OnBuffViewerFrameShow(self)
    if not buffDebuffAlertsEnabled then return end
    local sid = self.buffSpellID or self.spellID
    if not sid or sid <= 0 then return end
    -- Buff viewer frames: only process tracked buffs (not debuffs)
    local entry
    for _, aura in ipairs(trackedBuffs) do
        if aura.enabled ~= false and tonumber(aura.spellId) == sid then
            entry = aura; break
        end
    end
    if not entry then return end
    local alertKey = sid
    pendingHide[alertKey] = nil
    if activeAlerts[alertKey] then return end
    activeAlerts[alertKey] = true
    buffViewerAlerts[alertKey] = true
    local spellName = ""
    local ok, sinfo = pcall(C_Spell.GetSpellInfo, sid)
    if ok and sinfo then spellName = sinfo.name or "" end
    if entry.sound then API.PlayCustomSound(entry.sound, entry.soundIsID) end
    local overlay = ShowAlertOverlay(entry, spellName, self)
    if overlay then
        activeOverlays[alertKey] = overlay
        if overlay.durationTimer then overlay.durationTimer:Cancel(); overlay.durationTimer = nil end
    end
    if API.DEBUG then print("|cFF00FF00[RogUI]|r Gained: " .. spellName) end
    if entry.glowEnabled then
        local gf = GetOrCreateGlowForAura(entry); if gf then gf:ShowGlow(overlay) end
    end
end

local function OnBuffViewerFrameHide(self)
    local sid = self.buffSpellID or self.spellID
    if not sid or sid <= 0 then return end
    local alertKey = sid
    if not activeAlerts[alertKey] then return end
    pendingHide[alertKey] = true
    C_Timer.After(0.3, function()
        if not pendingHide[alertKey] then return end
        pendingHide[alertKey] = nil
        activeAlerts[alertKey] = nil
        buffViewerAlerts[alertKey] = nil
        ReleaseOverlay(alertKey)
        local gf = spellGlowFrames[alertKey]; if gf then gf:HideGlow() end
    end)
end

local function HookBuffFrame(frame)
    if buffHookedFrames[frame] then return end
    buffHookedFrames[frame] = true
    frame:HookScript("OnShow", OnBuffViewerFrameShow)
    frame:HookScript("OnHide",  OnBuffViewerFrameHide)
end

local function resolveBuffSpellID(child)
    if child.buffSpellID and child.buffSpellID > 0 then return child.buffSpellID end
    if child.spellID and child.spellID > 0 then return child.spellID end
    local sid
    pcall(function()
        if child.cooldownInfo then
            sid = child.cooldownInfo.overrideSpellID or child.cooldownInfo.spellID
        end
    end)
    if sid and sid > 0 then return sid end
    if child.rangeCheckSpellID and child.rangeCheckSpellID > 0 then
        return child.rangeCheckSpellID
    end
    return nil
end

local hookedBuffPanels = {}

local function walkAndHookBuffPanel(parent, depth)
    if not parent or depth > 5 then return end
    local ok, children = pcall(function() return {parent:GetChildren()} end)
    if not ok then return end
    for _, child in ipairs(children) do
        local sid = resolveBuffSpellID(child)
        if sid then
            if not child.buffSpellID or child.buffSpellID == 0 then
                child.buffSpellID = sid
            end
            HookBuffFrame(child)
        else
            walkAndHookBuffPanel(child, depth + 1)
        end
    end
end

HookBuffViewerPanels = function()
    local panelNames = {
        "BuffIconCooldownViewer",
        "BuffAndEssentialCooldownViewer",
        "MidnightBuffViewer",
        "RogUIBuffViewer",
    }
    for fname, fval in pairs(_G) do
        if type(fname) == "string" and fname:find("Buff") and fname:find("Viewer")
           and type(fval) == "table" and type(fval.GetChildren) == "function" then
            table.insert(panelNames, fname)
        end
    end

    for _, name in ipairs(panelNames) do
        local panel = _G[name]
        if panel then
            walkAndHookBuffPanel(panel, 0)
            -- Hook the panel's OnShow so new child frames created after startup
            -- (e.g. first time a buff appears) get hooked immediately
            if not hookedBuffPanels[name] then
                hookedBuffPanels[name] = true
                if panel.HookScript then
                    panel:HookScript("OnShow", function()
                        walkAndHookBuffPanel(panel, 0)
                    end)
                    -- Also hook each child's OnShow at the panel level via a ticker
                    -- fired once per second to catch newly materialised children
                end
            end
        end
    end
end
API.HookBuffViewerPanels = HookBuffViewerPanels
-- ── Buff lookup (CooldownViewer path only) ───────────────────────────────────
-- Buffs are tracked EXCLUSIVELY via CooldownViewer frame OnShow/OnHide hooks
-- and the PollBuffFrames in-combat ticker. No C_UnitAuras scanning for buffs.

local function FindTrackedEntry(sid)
    for _, aura in ipairs(trackedBuffs) do
        if aura.enabled ~= false and tonumber(aura.spellId) == sid then
            return aura, "Gained", "|cFF00FF00"
        end
    end
    return nil
end

--[[ FUTURE: Debuff tracking via UNIT_AURA + instanceID removal ... ]]

local buffLossDebounce = {}  -- kept for PLAYER_REGEN_ENABLED cleanup loop

-- Stubs so call sites outside the block comments compile without error
local function BuildInstanceMap() end
local function ScanTrackedDebuffs() end
local function FireAuraGained(sid) end
local function FireAuraLost(sid) end
local function StartExternalTicker() end
local function ApplyExtFramePosition() end

-- ── In-combat buff visibility poller ─────────────────────────────────────────
-- Polls hooked buff-viewer frames every 0.1s in combat.
-- Buffs ONLY — debuffs are handled via UNIT_AURA OOC + instanceID removal in combat.
local combatPollTicker = nil
local buffFrameLastSeen = {}
local pollPendingHideTimers = {}

-- PollBuffFrames: polls buff-viewer frame visibility every 0.1s in combat.
-- OnShow/OnHide hooks are the primary trigger; this poll catches any frames that
-- change visibility between hook fires. Loss uses a 0.5s debounce so transient
-- hide/re-show cycles (absorb updates, stack refreshes) don't flicker.
local buffPollLossTimers = {}
local buffPollLastSeen   = {}

local function PollBuffFrames()
    if not buffDebuffAlertsEnabled then return end
    for frame in pairs(buffHookedFrames) do
        local sid = tonumber(frame.buffSpellID or frame.spellID)
        if sid and sid > 0 then
            local isBuff = false
            for _, aura in ipairs(trackedBuffs) do
                if aura.enabled ~= false and tonumber(aura.spellId) == sid then
                    isBuff = true; break
                end
            end
            if isBuff then
                local shown = frame:IsShown()
                if shown then
                    -- Cancel any pending loss
                    if buffPollLossTimers[sid] then
                        buffPollLossTimers[sid]:Cancel()
                        buffPollLossTimers[sid] = nil
                    end
                    pendingHide[sid] = nil
                    if not activeAlerts[sid] then
                        -- Inline gain — same logic as OnBuffViewerFrameShow
                        local entry
                        for _, a in ipairs(trackedBuffs) do
                            if a.enabled ~= false and tonumber(a.spellId) == sid then
                                entry = a; break
                            end
                        end
                        if entry then
                            activeAlerts[sid]     = true
                            buffViewerAlerts[sid] = true
                            local spellName = ""
                            local ok, sinfo = pcall(C_Spell.GetSpellInfo, sid)
                            if ok and sinfo then spellName = sinfo.name or "" end
                            if entry.sound then API.PlayCustomSound(entry.sound, entry.soundIsID) end
                            local overlay = ShowAlertOverlay(entry, spellName, frame)
                            if overlay then
                                activeOverlays[sid] = overlay
                                if overlay.durationTimer then overlay.durationTimer:Cancel(); overlay.durationTimer = nil end
                            end
                            if API.DEBUG then print("|cFF00FF00[RogUI]|r Gained: " .. spellName) end
                            if entry.glowEnabled then
                                local gf = GetOrCreateGlowForAura(entry); if gf then gf:ShowGlow() end
                            end
                        end
                    end
                    buffPollLastSeen[frame] = true
                else
                    if buffPollLastSeen[frame] and not buffPollLossTimers[sid] then
                        -- Debounce loss: wait 0.5s then confirm still hidden
                        buffPollLossTimers[sid] = C_Timer.NewTimer(0.5, function()
                            buffPollLossTimers[sid] = nil
                            -- Only dismiss if no hooked frame for this sid is shown
                            local anyShown = false
                            for fr in pairs(buffHookedFrames) do
                                if (tonumber(fr.buffSpellID or fr.spellID) == sid) and fr:IsShown() then
                                    anyShown = true; break
                                end
                            end
                            if not anyShown and activeAlerts[sid] then
                                pendingHide[sid] = nil
                                activeAlerts[sid] = nil
                                buffViewerAlerts[sid] = nil
                                ReleaseOverlay(sid)
                                local gf = spellGlowFrames[sid]; if gf then gf:HideGlow() end
                            end
                        end)
                    end
                    buffPollLastSeen[frame] = false
                end
            end
        end
    end
end

local combatPollTick = 0

local function StartCombatPoll()
    if combatPollTicker then return end
    combatPollTick = 0
    for frame in pairs(buffHookedFrames) do
        buffFrameLastSeen[frame]   = frame:IsShown()
        buffPollLastSeen[frame]    = frame:IsShown()
    end
    combatPollTicker = C_Timer.NewTicker(0.1, function()
        combatPollTick = combatPollTick + 1
        -- Re-walk panels every 2s (every 20 ticks) to hook frames that
        -- appeared mid-combat (e.g. first cast of a buff while in combat)
        if combatPollTick % 20 == 0 then
            HookBuffViewerPanels()
            -- Seed any newly discovered frames
            for frame in pairs(buffHookedFrames) do
                if buffPollLastSeen[frame] == nil then
                    buffPollLastSeen[frame] = frame:IsShown()
                end
            end
        end
        PollBuffFrames()
    end)
end

local function StopCombatPoll()
    if combatPollTicker then combatPollTicker:Cancel(); combatPollTicker = nil end
    for key, timer in pairs(pollPendingHideTimers) do
        timer:Cancel(); pollPendingHideTimers[key] = nil
    end
end

-- Sated debuff IDs that signal lust was used. These are non-secret (debuffs, not buffs).
-- A buff entry with isLustTracker=true uses this table instead of a buff-viewer hook.
local SATED_DEBUFF_IDS = {
    [57723]=true, [57724]=true, [80354]=true,
    [95809]=true, [160455]=true, [264689]=true, [390435]=true,
}
local LUST_ALERT_KEY = 57723  -- canonical alert key for all sated variants
local lustDebuffActive = false

local function CheckLustDebuff()
    if not buffDebuffAlertsEnabled then return end
    -- Find a lust entry in trackedBuffs
    local lustEntry = nil
    for _, aura in ipairs(trackedBuffs) do
        if aura.isLustTracker and aura.enabled ~= false then
            lustEntry = aura; break
        end
    end
    if not lustEntry then return end

    -- Scan debuffs using C_UnitAuras (UnitDebuff removed in TWW)
    local foundSID = nil
    for spellId in pairs(SATED_DEBUFF_IDS) do
        local ok, auraData = pcall(C_UnitAuras.GetPlayerAuraBySpellID, spellId)
        if ok and auraData then foundSID = spellId; break end
    end

    if foundSID and not lustDebuffActive then
        lustDebuffActive = true
        activeAlerts[LUST_ALERT_KEY] = true
        local ok, sinfo = pcall(C_Spell.GetSpellInfo, foundSID)
        local spellName = (ok and sinfo and sinfo.name) or "Lust"
        if lustEntry.sound then API.PlayCustomSound(lustEntry.sound, lustEntry.soundIsID) end
        local overlay = ShowAlertOverlay(lustEntry, spellName, nil)
        if overlay then activeOverlays[LUST_ALERT_KEY] = overlay end
        if lustEntry.glowEnabled then
            local gf = GetOrCreateGlowForAura(lustEntry); if gf then gf:ShowGlow() end
        end
        if API.DEBUG then print("|cFFFF6600[RogUI]|r Lust: " .. spellName) end
    elseif not foundSID and lustDebuffActive then
        lustDebuffActive = false
        activeAlerts[LUST_ALERT_KEY] = nil
        ReleaseOverlay(LUST_ALERT_KEY)
        local gf = spellGlowFrames[LUST_ALERT_KEY]; if gf then gf:HideGlow() end
    end
end
API.CheckLustDebuff  = CheckLustDebuff
API.LUST_ALERT_KEY   = LUST_ALERT_KEY
API.SATED_DEBUFF_IDS = SATED_DEBUFF_IDS

local function OnBuffAlertsUnitAura(unit, updateInfo)
    if unit == "player" then CheckLustDebuff() end
end

local function OnBuffAlertsPlayerLogin()
    C_Timer.After(1, function()
        RebuildNameMap()
        HookBuffViewerPanels()
        C_Timer.After(0.5, function()
            if API.CheckCDMismatch then API.CheckCDMismatch() end
        end)
        C_Timer.After(2, function()
            RebuildNameMap()
            HookBuffViewerPanels()
        end)
    end)
end

local function OnBuffAlertsRegenDisabled()
    HookBuffViewerPanels()
    StartCombatPoll()
end

local function OnBuffAlertsRegenEnabled()
    StopCombatPoll()
    for sid, timer in pairs(buffPollLossTimers) do
        timer:Cancel(); buffPollLossTimers[sid] = nil
    end
    HookBuffViewerPanels()
    local panelNames = {"EssentialCooldownViewer","UtilityCooldownViewer","BuffIconCooldownViewer",
        "CooldownViewerSystem","CooldownViewerFrame","BuffAndEssentialCooldownViewer"}
    local function warmFrame(parent, depth)
        if not parent or depth > 2 then return end
        local ok, children = pcall(function() return {parent:GetChildren()} end)
        if not ok then return end
        for _, child in ipairs(children) do
            if child.cooldownID ~= nil then
                local cid = child.cooldownID
                if not cidToEntry[cid] and child.cooldownInfo then
                    local spellID = child.cooldownInfo.overrideSpellID or child.cooldownInfo.spellID
                    if spellID and sidToEntry[spellID] then cidToEntry[cid] = sidToEntry[spellID] end
                end
            else warmFrame(child, depth+1) end
        end
    end
    for _, name in ipairs(panelNames) do warmFrame(_G[name], 0) end
end

API.RegisterEvent("BuffAlerts", "UNIT_AURA",            OnBuffAlertsUnitAura)
API.RegisterEvent("BuffAlerts", "PLAYER_LOGIN",         OnBuffAlertsPlayerLogin)
API.RegisterEvent("BuffAlerts", "PLAYER_REGEN_DISABLED",  OnBuffAlertsRegenDisabled)
API.RegisterEvent("BuffAlerts", "PLAYER_REGEN_ENABLED",   OnBuffAlertsRegenEnabled)

-- ── CD Mismatch popup ─────────────────────────────────────────────────────────
local cdMismatchPopup = CreateFrame("Frame","CSCDMismatchPopup",UIParent,"BackdropTemplate")
cdMismatchPopup:SetSize(440,260); cdMismatchPopup:SetPoint("CENTER",UIParent,"CENTER",0,60)
cdMismatchPopup:SetFrameStrata("DIALOG")
cdMismatchPopup:SetBackdrop({bgFile="Interface/DialogFrame/UI-DialogBox-Background",
    edgeFile="Interface/DialogFrame/UI-DialogBox-Border",
    tile=true,tileSize=16,edgeSize=16,insets={left=8,right=8,top=8,bottom=8}})
cdMismatchPopup:SetBackdropColor(0.05,0.05,0.1,0.97)
cdMismatchPopup:SetMovable(true); cdMismatchPopup:EnableMouse(true)
cdMismatchPopup:RegisterForDrag("LeftButton")
cdMismatchPopup:SetScript("OnDragStart",function(self) if API.IsLayoutMode and API.IsLayoutMode() then self:StartMoving() end end)
cdMismatchPopup:SetScript("OnDragStop",function(self) self:StopMovingOrSizing() end)
cdMismatchPopup:Hide()

local cdMismatchText, cdMismatchContent
do
    local icon = cdMismatchPopup:CreateTexture(nil,"ARTWORK"); icon:SetSize(32,32)
    icon:SetPoint("TOPLEFT",14,-14); icon:SetTexture("Interface\\DialogFrame\\UI-Dialog-Icon-AlertOther")
    local titleStr = cdMismatchPopup:CreateFontString(nil,"OVERLAY","GameFontNormalLarge")
    titleStr:SetPoint("TOPLEFT",icon,"TOPRIGHT",8,0); titleStr:SetText("|cFFFFD700RogUI — Action Required|r")
    local subtitle = cdMismatchPopup:CreateFontString(nil,"OVERLAY","GameFontNormal")
    subtitle:SetPoint("TOPLEFT",titleStr,"BOTTOMLEFT",0,-4); subtitle:SetTextColor(1,0.6,0.2,1)
    subtitle:SetText("Some tracked spells are missing from the Cooldown Manager and Buff Tracker")
    local scroll = CreateFrame("ScrollFrame","CSCDMismatchScroll",cdMismatchPopup,"UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT",12,-68); scroll:SetPoint("BOTTOMRIGHT",-30,40)
    cdMismatchContent = CreateFrame("Frame","CSCDMismatchContent",scroll)
    cdMismatchContent:SetSize(390,1); scroll:SetScrollChild(cdMismatchContent)
    cdMismatchText = cdMismatchContent:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    cdMismatchText:SetPoint("TOPLEFT",4,-4); cdMismatchText:SetWidth(382)
    cdMismatchText:SetJustifyH("LEFT"); cdMismatchText:SetJustifyV("TOP"); cdMismatchText:SetWordWrap(true)
    local dismissBtn = CreateFrame("Button",nil,cdMismatchPopup,"GameMenuButtonTemplate")
    dismissBtn:SetSize(100,24); dismissBtn:SetPoint("BOTTOMRIGHT",cdMismatchPopup,"BOTTOMRIGHT",-10,8)
    dismissBtn:SetText("Dismiss"); dismissBtn:SetScript("OnClick",function() cdMismatchPopup:Hide() end)
    local neverBtn = CreateFrame("Button",nil,cdMismatchPopup,"GameMenuButtonTemplate")
    neverBtn:SetSize(130,24); neverBtn:SetPoint("RIGHT",dismissBtn,"LEFT",-6,0); neverBtn:SetText("Don't show again")
    neverBtn:SetScript("OnClick",function()
        cdMismatchPopup:Hide()
        if RogUIDB then
            RogUIDB.cdMismatchSuppressed = true
            -- Save the current spell fingerprint so we re-show if the list changes
            local ids = {}
            local function collect(list)
                for _, a in ipairs(list) do
                    if a.enabled ~= false then
                        local sid = tonumber(a.spellId) or (a.spellIds and tonumber(a.spellIds[1]))
                        if sid and sid > 0 then table.insert(ids, sid) end
                    end
                end
            end
            collect(trackedBuffs)
            table.sort(ids)
            RogUIDB.cdMismatchFingerprint = table.concat(ids, ",")
        end
    end)
    local openBtn = CreateFrame("Button",nil,cdMismatchPopup,"GameMenuButtonTemplate")
    openBtn:SetSize(180,24); openBtn:SetPoint("BOTTOMLEFT",cdMismatchPopup,"BOTTOMLEFT",10,8)
    openBtn:SetText("[+] Open Cooldown Manager")
    openBtn:SetScript("OnClick",function()
        local opened = false
        if Settings and Settings.OpenToCategory then
            pcall(function() Settings.OpenToCategory("ActionBars"); opened=true end)
        end
        if not opened and InterfaceOptionsFrame_OpenToCategory then
            pcall(function() InterfaceOptionsFrame_OpenToCategory("ActionBars") end)
        elseif not opened and SettingsPanel then SettingsPanel:Show() end
        print("|cFFFFD700[RogUI]|r Open the |cFF00CCFFCooldown Manager|r → click |cFF00CCFF+|r → add each missing spell.")
    end)
end

-- Track whether RebuildNameMap found any CooldownViewer frames
local lastHookCount = 0

local function CheckCDMismatch()
    -- Only run if we actually found CooldownViewer frames to hook into.
    -- If hookCount is 0, we can't distinguish "not in Cooldown Manager" from
    -- "Cooldown Manager frames not loaded yet" — so skip to avoid false positives.
    if lastHookCount == 0 then return end

    -- Build the fingerprint of currently-tracked spell IDs so we can detect
    -- if the spell list changed since the user clicked "Don't show again".
    local function makeFingerprint()
        local ids = {}
        local function collect(list)
            for _, a in ipairs(list) do
                if a.enabled ~= false then
                    local sid = tonumber(a.spellId) or (a.spellIds and tonumber(a.spellIds[1]))
                    if sid and sid > 0 then table.insert(ids, sid) end
                end
            end
        end
        collect(trackedBuffs)
        table.sort(ids)
        return table.concat(ids, ",")
    end

    local fp = makeFingerprint()
    if fp == "" then return end  -- nothing tracked

    -- If suppressed, only skip if the spell list hasn't changed since suppression
    if RogUIDB and RogUIDB.cdMismatchSuppressed then
        if RogUIDB.cdMismatchFingerprint == fp then return end
        -- Spell list changed — clear suppression and re-check
        RogUIDB.cdMismatchSuppressed = false
        RogUIDB.cdMismatchFingerprint = nil
    end

    -- Build a set of spell IDs that ARE covered by either the cooldown bar (sidToEntry)
    -- or the buff section poll (buffHookedFrames). Either one provides in-combat detection.
    local coveredSids = {}
    for sid in pairs(sidToEntry) do coveredSids[sid] = true end
    for frame in pairs(buffHookedFrames) do
        local fsid = frame.buffSpellID or frame.spellID
        if fsid then coveredSids[fsid] = true end
    end

    local missing = {}
    local function checkEntry(aura, category)
        if aura.enabled == false then return end
        local wids = (aura.spellIds and #aura.spellIds > 0) and aura.spellIds or {tonumber(aura.spellId)}
        -- An entry is covered if ANY of its watch IDs is in a tracked frame
        for _, sid in ipairs(wids) do
            if sid and sid > 0 and coveredSids[sid] then return end
        end
        -- None of the IDs are covered — report the primary one
        local sid = wids[1]; if not sid or sid <= 0 then return end
        local name = ""; local ok,info = pcall(C_Spell.GetSpellInfo, sid)
        if ok and info then name = info.name or ("Spell "..sid) end
        table.insert(missing, {sid=sid, name=name, category=category})
    end
    for _,b in ipairs(trackedBuffs)     do checkEntry(b,"Buff")     end
    if #missing == 0 then return end

    local lines = {
        "|cFFFF4444Warning:|r The following spells are not tracked in either the",
        "|cFF00CCFFCooldown Manager|r or the |cFF00CCFFBuff Tracker|r.\n",
        "This means they |cFFFF4444will not appear during combat|r — WoW restricts",
        "aura data to addons while fighting. Out-of-combat alerts will still work.\n",
        "|cFFFFD700How to fix:|r Open the Cooldown Manager (button below), click |cFF00CCFF+|r,",
        "and add each spell either as a |cFF00CCFFCooldown|r or a |cFF00CCFFBuff|r.\n",
    }
    for _,m in ipairs(missing) do
        table.insert(lines, string.format(
            "  |cFFFF8800[%s]|r  %s  |cFF999999(ID: %d)|r",
            m.category, m.name, m.sid))
    end
    cdMismatchText:SetText(table.concat(lines,"\n"))
    cdMismatchContent:SetHeight(math.max(180, cdMismatchText:GetStringHeight()+16))
    cdMismatchPopup:Show()
end
API.CheckCDMismatch = CheckCDMismatch

-- ── Layout handle provider ─────────────────────────────────────────────────────
API.RegisterLayoutHandles(function()
    local handles = {}
    local function addAuraHandles(list, typeLabel)
        for idx, aura in ipairs(list) do
            if aura.alertTexture and aura.alertTexture ~= "" then
                local ox = aura.alertX or 0; local oy = aura.alertY or 0
                local iconTex = aura.alertTexture
                if iconTex == "spell_icon" and aura.spellId and aura.spellId > 0 then
                    local info = C_Spell.GetSpellInfo(aura.spellId)
                    iconTex = info and info.iconID or "Interface\\Icons\\INV_Misc_QuestionMark"
                elseif iconTex:match("^spell:(%d+)$") then
                    local sid = tonumber(iconTex:match("^spell:(%d+)$"))
                    local info = sid and C_Spell.GetSpellInfo(sid)
                    iconTex = info and info.iconID or "Interface\\Icons\\INV_Misc_QuestionMark"
                end
                local spellName = "Unknown"
                if aura.spellId and aura.spellId > 0 then
                    local info = C_Spell.GetSpellInfo(aura.spellId)
                    spellName = info and info.name or ("ID "..aura.spellId)
                end
                local capturedAura = aura; local capturedIdx = idx; local capturedType = typeLabel:lower()
                local isBar = (aura.alertMode == "bar")
                -- liveFrameRef: the currently-showing overlay for this aura, if any.
                -- alertKey for both bar and icon mode is the spellId.
                local alertKey = tonumber(aura.spellId) or 0
                local liveFrame = (alertKey > 0) and activeOverlays[alertKey] or nil
                table.insert(handles, {
                    label        = typeLabel..": "..spellName,
                    iconTex      = iconTex,
                    ox           = ox, oy = oy,
                    liveFrameRef = liveFrame,
                    saveCallback = function(nx,ny)
                        capturedAura.alertX = nx; capturedAura.alertY = ny
                        local xBox = _G["BuffAlertTexX"..capturedType..capturedIdx]
                        local yBox = _G["BuffAlertTexY"..capturedType..capturedIdx]
                        if xBox then xBox:SetText(tostring(nx)) end
                        if yBox then yBox:SetText(tostring(ny)) end
                        if RogUIDB then API.SaveSpecProfile() end
                    end,
                    resizeCallback = function(nw, nh)
                        nw = math.max(40,  math.floor(nw + 0.5))
                        nh = math.max(8,   math.floor(nh + 0.5))
                        if isBar then
                            capturedAura.alertBarWidth = nw
                            capturedAura.alertSize     = nh
                            local wBox = _G["BuffAlertBarWidth"..capturedType..capturedIdx]
                            local hBox = _G["BuffAlertTexSize"..capturedType..capturedIdx]
                            if wBox then wBox:SetText(tostring(nw)) end
                            if hBox then hBox:SetText(tostring(nh)) end
                        else
                            -- Icon mode: keep square
                            local sz = math.max(nw, nh)
                            capturedAura.alertSize = sz
                            local szBox = _G["BuffAlertTexSize"..capturedType..capturedIdx]
                            if szBox then szBox:SetText(tostring(sz)) end
                        end
                        if RogUIDB then API.SaveSpecProfile() end
                    end,
                    previewFunc  = function()
                        return ShowAlertOverlay({
                            alertTexture=aura.alertTexture, spellId=aura.spellId,
                            alertMode=aura.alertMode, alertBarWidth=aura.alertBarWidth,
                            alertSize=aura.alertSize, alertDuration=9999,
                            alertX=aura.alertX or 0, alertY=aura.alertY or 0,
                        }, spellName)
                    end,
                })
            end
        end
    end
    addAuraHandles(trackedBuffs,    "Buff")
    return handles
end)

-- ── Slash commands ─────────────────────────────────────────────────────────────
SLASH_CUSTOMSOUNDSDEBUG1 = "/qoldebug"
SlashCmdList["CUSTOMSOUNDSDEBUG"] = function()
    print("|cFFFFFF00[RogUI DEBUG]|r =============================")
    print("buffDebuffAlertsEnabled: "..tostring(buffDebuffAlertsEnabled))
    print("Tracked: buffs="..#trackedBuffs.."  (debuffs/externals disabled)")
    local cidCount=0; for _ in pairs(cidToEntry) do cidCount=cidCount+1 end
    print("CID map entries: "..cidCount)
    RebuildNameMap()
    print("|cFFFFFF00[RogUI DEBUG]|r ============================= done")
end

SLASH_CSTRACK1 = "/qoltrack"
SlashCmdList["CSTRACK"] = function()
    print("|cFFFFFF00[RogUI]|r Scanning visible CooldownViewer frames...")
    local found = {}
    local panelNames = {"EssentialCooldownViewer","UtilityCooldownViewer","BuffIconCooldownViewer",
        "CooldownViewerSystem","CooldownViewerFrame","BuffAndEssentialCooldownViewer"}
    local function scanFrame(parent, depth)
        if not parent or depth > 4 then return end
        local ok, children = pcall(function() return {parent:GetChildren()} end)
        if not ok then return end
        for _, child in ipairs(children) do
            if child.cooldownID ~= nil and child:IsShown() then
                local cid = child.cooldownID
                local frameSpellID = child.rangeCheckSpellID
                local ciSpellID; pcall(function()
                    if child.cooldownInfo then ciSpellID = child.cooldownInfo.overrideSpellID or child.cooldownInfo.spellID end
                end)
                local resolvedID = frameSpellID or ciSpellID
                local spellName = "?"
                if resolvedID then local nok,ninfo = pcall(C_Spell.GetSpellInfo,resolvedID)
                    if nok and ninfo then spellName = ninfo.name or "?" end end
                local mapped = cidToEntry[cid]
                    and ("|cFF00FF00MAPPED -> sid="..cidToEntry[cid].sid.."|r")
                    or  "|cFFFF4444NOT MAPPED|r"
                table.insert(found, string.format("  cid=%-6d  spellID=%-8s  name='%s'  %s",
                    cid, tostring(resolvedID), spellName, mapped))
            else scanFrame(child, depth+1) end
        end
    end
    for _, name in ipairs(panelNames) do scanFrame(_G[name], 0) end
    if #found == 0 then print("  (none visible)")
    else for _,line in ipairs(found) do print(line) end end
    print("|cFFFFFF00[RogUI]|r Done.")
end

SLASH_CSFRAMES1 = "/qolframes"
SlashCmdList["CSFRAMES"] = function()
    print("|cFFFFFF00[RogUI]|r Scanning for CooldownViewer frames...")
    local found = {}
    for fname, fval in pairs(_G) do
        if type(fname)=="string" and fname:find("Cooldown") and type(fval)=="table" then
            local ok, hasGC = pcall(function() return type(fval.GetChildren)=="function" end)
            if ok and hasGC then
                local childCount=0; local cdChildren=0
                local ok2,children = pcall(function() return {fval:GetChildren()} end)
                if ok2 then childCount=#children
                    for _,c in ipairs(children) do if c.cooldownID~=nil then cdChildren=cdChildren+1 end end
                end
                table.insert(found,{name=fname,children=childCount,cdChildren=cdChildren})
            end
        end
    end
    table.sort(found,function(a,b) return a.name<b.name end)
    if #found==0 then print("  (none found)")
    else for _,f in ipairs(found) do
        print(string.format("  %-45s  children=%-3d  cd-children=%d",f.name,f.children,f.cdChildren))
    end end
    print("|cFFFFFF00[RogUI]|r Done.")
end

-- ══════════════════════════════════════════════════════════════════════════════
-- Boss Warning Sound System
-- ══════════════════════════════════════════════════════════════════════════════

local function PlayBossAlert()
    local db = RogUIDB
    if db and db.bossWarnSound and db.bossWarnSound.sound then
        API.PlayCustomSound(db.bossWarnSound.sound, db.bossWarnSound.soundIsID)
    end
end

-- This handles the Big Center Text alerts (Blizzard 'Dong' sound)
API.RegisterEvent("BuffAlerts", "RAID_BOSS_EMOTE", function()
    PlayBossAlert()
end)

-- This handles encounter warning popups
API.RegisterEvent("BuffAlerts", "ENCOUNTER_WARNING", function()
    PlayBossAlert()
end)
-- ════════════════════════════════════════════════════════════
-- SECTION 3: COOLDOWN KEYBINDS - Core Logic
-- ════════════════════════════════════════════════════════════


local API = RogUIAPI
if not API then return end

local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)

-- ── Viewer → key mapping (frame global name → settings key) ──────────────────
local VIEWERS = {
    EssentialCooldownViewer               = "Essential",
    UtilityCooldownViewer                 = "Utility",
    BCDM_CustomCooldownViewer             = "BCDMCustomSpells",
    BCDM_CustomItemSpellBar               = "BCDMCustomItemSpellBar",
    BCDM_AdditionalCustomCooldownViewer   = "BCDMCustomSpells",
    BCDM_CustomItemBar                    = "BCDMCustomItems",
    BCDM_TrinketBar                       = "BCDMTrinkets",
    EssentialCooldownViewer_CDM_Container = "Essential",
    UtilityCooldownViewer_CDM_Container   = "Utility",
    CDM_DefensivesContainer               = "Defensives",
    CDM_TrinketsContainer                 = "Trinkets",
    CDM_RacialsContainer                  = "Racials",
}

local VIEWER_DEFAULTS = {
    Essential            = { showKeybinds=true, anchor="TOPRIGHT", fontSize=13, offsetX=-1, offsetY=-1, fontName="Friz Quadrata TT", fontFlags="OUTLINE", color={1,1,1,1} },
    Utility              = { showKeybinds=true, anchor="TOPRIGHT", fontSize=12, offsetX=-1, offsetY=-1, fontName="Friz Quadrata TT", fontFlags="OUTLINE", color={1,1,1,1} },
    Defensives           = { showKeybinds=true, anchor="TOPRIGHT", fontSize=12, offsetX=-1, offsetY=-1, fontName="Friz Quadrata TT", fontFlags="OUTLINE", color={1,1,1,1} },
    Trinkets             = { showKeybinds=true, anchor="TOPRIGHT", fontSize=12, offsetX=-1, offsetY=-1, fontName="Friz Quadrata TT", fontFlags="OUTLINE", color={1,1,1,1} },
    Racials              = { showKeybinds=true, anchor="TOPRIGHT", fontSize=12, offsetX=-1, offsetY=-1, fontName="Friz Quadrata TT", fontFlags="OUTLINE", color={1,1,1,1} },
    BCDMCustomSpells     = { showKeybinds=true, anchor="TOPRIGHT", fontSize=12, offsetX=-1, offsetY=-1, fontName="Friz Quadrata TT", fontFlags="OUTLINE", color={1,1,1,1} },
    BCDMCustomItems      = { showKeybinds=true, anchor="TOPRIGHT", fontSize=12, offsetX=-1, offsetY=-1, fontName="Friz Quadrata TT", fontFlags="OUTLINE", color={1,1,1,1} },
    BCDMTrinkets         = { showKeybinds=true, anchor="TOPRIGHT", fontSize=12, offsetX=-1, offsetY=-1, fontName="Friz Quadrata TT", fontFlags="OUTLINE", color={1,1,1,1} },
    BCDMCustomItemSpellBar={ showKeybinds=true, anchor="TOPRIGHT", fontSize=13, offsetX=-1, offsetY=-1, fontName="Friz Quadrata TT", fontFlags="OUTLINE", color={1,1,1,1} },
}

-- ── DB helpers ────────────────────────────────────────────────────────────────
local function GetDB()
    if not RogUIDB then return nil end
    if not RogUIDB.cooldownKeybinds then
        RogUIDB.cooldownKeybinds = { enabled=true, viewers={} }
    end
    return RogUIDB.cooldownKeybinds
end

local function GetViewerDB(viewerKey)
    local db = GetDB()
    if not db then return VIEWER_DEFAULTS[viewerKey] or {} end
    if not db.viewers[viewerKey] then
        local d = VIEWER_DEFAULTS[viewerKey] or {}
        local copy = {}
        for k,v in pairs(d) do
            if type(v)=="table" then copy[k]={}; for k2,v2 in pairs(v) do copy[k][k2]=v2 end
            else copy[k]=v end
        end
        db.viewers[viewerKey] = copy
    end
    return db.viewers[viewerKey]
end

API.CKBGetDB       = GetDB
API.CKBGetViewerDB = GetViewerDB

-- ── State ─────────────────────────────────────────────────────────────────────
local isEnabled          = false
local mappingCache       = nil
local viewerChildrenCache    = {}
local viewerChildCountCache  = {}
local hooked             = {}
local scheduledOOC       = false
local dirtyOOC           = false
local scheduledSeries    = false
local seriesDirty        = false
local seriesIndex        = 1
local seriesDelays       = {0.15, 0.45, 1.00, 2.00}
local activeAdapterName  = nil
local trinketWarmupRunning = false
local trinketWarmupIndex = 1
local trinketWarmupDelays= {0.15, 0.35, 0.75, 1.50, 3.00}

-- ── Helpers ───────────────────────────────────────────────────────────────────
local DEFAULT_FONT = "Fonts\\FRIZQT__.TTF"

local function GetFontPath(n)
    if not n or n=="" then return DEFAULT_FONT end
    if LSM then local p=LSM:Fetch("font",n); if p then return p end end
    return DEFAULT_FONT
end

local function Trim(s)
    if s==nil then return nil end
    return (tostring(s):gsub("^%s+",""):gsub("%s+$",""))
end

local function FormatKey(key)
    if not key or key=="" then return "" end
    key=key:upper()
    if key=="-" then return "-" end
    key=key:gsub("MOUSE%s*WHEEL%s*UP","MOUSEWHEELUP"):gsub("MOUSE%s*WHEEL%s*DOWN","MOUSEWHEELDOWN"):gsub("MOUSE%s*BUTTON","MOUSEBUTTON")
    key=key:gsub("SHIFT%-","S"):gsub("CTRL%-","C"):gsub("ALT%-","A")
    key=key:gsub("MOUSEWHEELUP","MU"):gsub("MOUSEWHEELDOWN","MD"):gsub("MOUSEBUTTON","M"):gsub("BUTTON","M")
    key=key:gsub("NUMPADPLUS","N+"):gsub("NUMPADMINUS","N-"):gsub("NUMPADMULTIPLY","N*"):gsub("NUMPADDIVIDE","N/"):gsub("NUMPADDECIMAL","N."):gsub("NUMPADENTER","NENT"):gsub("NUMPAD","N"):gsub("NUM","N")
    key=key:gsub("PAGEUP","PGU"):gsub("PAGEDOWN","PGD"):gsub("INSERT","INS"):gsub("DELETE","DEL"):gsub("BACKSPACE","BS"):gsub("SPACEBAR","Spc"):gsub("ENTER","Ent"):gsub("ESCAPE","Esc"):gsub("TAB","Tab"):gsub("CAPSLOCK","Caps"):gsub("HOME","Hom"):gsub("END","End")
    local endsM=(key:sub(-1)=="-")
    if endsM then key=key:sub(1,-2).."<M>" end
    key=key:gsub("%-","")
    if endsM then key=key:gsub("<M>","-") end
    return key
end

local function IsAnyViewerEnabled()
    local db=GetDB(); if not db or not db.enabled then return false end
    for _,vk in pairs(VIEWERS) do local v=GetViewerDB(vk); if v and v.showKeybinds then return true end end
    return false
end

local function InCombat() return InCombatLockdown and InCombatLockdown() end
local function MappingLooksEmpty(m)
    return not m or (not next(m.byID) and not next(m.byName) and not next(m.itemsByID) and not next(m.itemsByName))
end

local function GetAttachFrame(obj)
    if not obj then return nil end
    if obj.IsObjectType and obj:IsObjectType("Frame") then return obj end
    if obj.GetParent then local p=obj:GetParent(); if p and p.IsObjectType and p:IsObjectType("Frame") then return p end end
    return nil
end

local function CollectFrameDescendants(root,out,seen,depth,maxD,maxN)
    if not root or not root.GetChildren or #out>=maxN or depth>maxD then return end
    for _,child in ipairs({root:GetChildren()}) do
        if #out>=maxN then return end
        local f=GetAttachFrame(child)
        if f and not seen[f] then seen[f]=true; out[#out+1]=f end
        CollectFrameDescendants(child,out,seen,depth+1,maxD,maxN)
    end
end

-- ── Spell / item resolution ───────────────────────────────────────────────────
local function GetSpellIDFromName(n)
    if not n or n=="" then return nil end
    local num=tonumber(n)
    if num then
        if C_Spell and C_Spell.DoesSpellExist and C_Spell.DoesSpellExist(num) then return num end
        return nil
    end
    if C_Spell then
        if C_Spell.GetSpellIDForSpellIdentifier then local s=C_Spell.GetSpellIDForSpellIdentifier(n); if s and s~=0 then return s end end
        if C_Spell.GetSpellInfo then local i=C_Spell.GetSpellInfo(n); if i and i.spellID and i.spellID~=0 then return i.spellID end end
    end
    if GetSpellInfo then local s=select(7,GetSpellInfo(n)); if s and s~=0 then return s end end
    return nil
end

local function GetSpellNameFromID(id)
    if not id or id==0 then return nil end
    if C_Spell then
        if C_Spell.GetSpellName then local n=C_Spell.GetSpellName(id); if n and n~="" then return n end end
        if C_Spell.GetSpellInfo then local i=C_Spell.GetSpellInfo(id); if i and i.name and i.name~="" then return i.name end end
    end
    if GetSpellInfo then local n=GetSpellInfo(id); if n and n~="" then return n end end
    return nil
end

local function GetItemNameFromID(id)
    if not id or id==0 then return nil end
    if C_Item and C_Item.GetItemNameByID then local n=C_Item.GetItemNameByID(id); if n and n~="" then return n end end
    if GetItemInfo then local n=GetItemInfo(id); if n and n~="" then return n end end
    return nil
end

-- ── Macro parsing ─────────────────────────────────────────────────────────────
local function CleanTok(t)
    if t==nil then return nil end
    t=tostring(t):gsub("%[.-%]%s*",""):gsub("#.*$",""):gsub("!+","")
    t=Trim(t); return (t=="" and nil or t)
end
local function StripBrackets(s)
    s=Trim(s or "")
    while s~="" do local f=s:match("^(%b[])"); if not f then break end; s=Trim(s:sub(#f+1)) end
    return s
end
local function ExtractCastTokens(body)
    -- Returns a list of all spell/item names found in /cast and /castsequence lines,
    -- including all conditional branches separated by semicolons.
    if not body or body=="" then return nil end
    local found = {}
    for line in body:gmatch("[^\r\n]+") do
        line=Trim(line or ""); if line~="" then
            local cmd,rest=line:match("^/(%S+)%s+(.+)$")
            if cmd and rest then
                cmd=cmd:lower()
                if cmd=="cast" or cmd=="castsequence" then
                    -- Split on ; to get all conditional branches
                    for seg in (rest..";"):gmatch("([^;]*);") do
                        seg = StripBrackets(Trim(seg))
                        if cmd=="castsequence" then seg=seg:gsub("^reset=[^%s]+%s*","") end
                        -- Take first spell in a castsequence comma list
                        seg = Trim(seg:match("^([^,]+)") or seg)
                        local tok = CleanTok(seg)
                        if tok and tok~="" then
                            found[tok:lower()] = tok
                        end
                    end
                end
            end
        end
    end
    local out = {}
    for _, v in pairs(found) do out[#out+1] = v end
    return #out > 0 and out or nil
end
local function ExtractCastToken(body)
    -- Legacy single-result wrapper kept for callers that only want one
    local tokens = ExtractCastTokens(body)
    return tokens and tokens[1] or nil
end
local function GetMacroBody(idx)
    if not idx or idx==0 then return nil end
    if GetMacroInfo then local _,_,b=GetMacroInfo(idx); if b and b~="" then return b end end
    if _G.GetMacroBody then local b=_G.GetMacroBody(idx); if b and b~="" then return b end end
    return nil
end
local function ExtractUseTokens(body)
    if not body or body=="" then return nil end
    local found={}
    for line in body:gmatch("[^\r\n]+") do
        line=Trim(line); if line and line~="" then
            local cmd,rest=line:match("^/(%S+)%s+(.+)$")
            if cmd and rest then
                cmd=cmd:lower()
                if cmd=="use" or cmd=="item" then
                    for seg in rest:gmatch("([^;]+)") do
                        local tok=CleanTok(seg)
                        if tok then for part in tok:gmatch("([^,]+)") do local t=CleanTok(part); if t then found[t:lower()]=t end end end
                    end
                end
            end
        end
    end
    local out; for _,v in pairs(found) do out=out or {}; out[#out+1]=v end; return out
end
local function ExtractShowtooltip(body)
    if not body or body=="" then return nil end
    for line in body:gmatch("[^\r\n]+") do
        line=Trim(line or "")
        if line:lower():find("#showtooltip",1,true) then
            local r=line:match("^#showtooltip%s*(.+)$"); r=Trim(r or "")
            if r~="" then r=CleanTok(r); if r and r~="" then return r end end
            return nil
        end
    end
    return nil
end
local function ResolveMacroSpells(idx,body)
    -- Returns a list of all spell IDs this macro could cast (all conditional branches)
    if not idx or idx==0 then return nil end
    local results = {}
    if GetMacroSpell then
        local v=GetMacroSpell(idx)
        if type(v)=="number" and v>0 then results[#results+1]=v end
        if type(v)=="string" then local n=Trim(v); if n~="" then local s=GetSpellIDFromName(n); if s then results[#results+1]=s end end end
    end
    local st=ExtractShowtooltip(body)
    if st then local s=GetSpellIDFromName(st); if s and not results[1] then results[#results+1]=s end end
    local tokens=ExtractCastTokens(body)
    if tokens then
        for _,tok in ipairs(tokens) do
            local s=GetSpellIDFromName(tok)
            if s then
                local seen=false
                for _,existing in ipairs(results) do if existing==s then seen=true; break end end
                if not seen then results[#results+1]=s end
            end
        end
    end
    return #results>0 and results or nil
end
local function ResolveMacroSpell(idx,body)
    local r=ResolveMacroSpells(idx,body); return r and r[1] or nil
end

-- ── Key extraction ────────────────────────────────────────────────────────────
local function TryGetKey(btn)
    if not btn then return nil end
    if btn.config and btn.config.keyBoundTarget then local k=GetBindingKey(btn.config.keyBoundTarget); if k and k~="" then return k end end
    if btn.commandName then local k=GetBindingKey(btn.commandName); if k and k~="" then return k end end
    local nm=btn.GetName and btn:GetName()
    if nm and GetBindingKey then
        local k=GetBindingKey("CLICK "..nm..":LeftButton"); if k and k~="" then return k end
        k=GetBindingKey("CLICK "..nm..":RightButton"); if k and k~="" then return k end
    end
    if btn.HotKey and btn.HotKey.GetText then local t=btn.HotKey:GetText(); if t and t~="" and t~="●" then return t end end
    return nil
end
local function DirectKey(icon)
    icon=GetAttachFrame(icon); if not icon then return "" end
    local raw=TryGetKey(icon)
    if (not raw or raw=="" or raw=="●") and icon.GetParent then raw=TryGetKey(icon:GetParent()) end
    if raw and raw~="" and raw~="●" then return FormatKey(raw) end
    return ""
end

-- ── Map storage ───────────────────────────────────────────────────────────────
local function AddNameKey(map,nm,k) if nm and nm~="" and k and k~="" and not map[nm:lower()] then map[nm:lower()]=k end end

local function AddSpellKey(map,id,k)
    if not map or not id or id==0 or not k or k=="" then return end
    if map.byID[id] then return end
    map.byID[id]=k; AddNameKey(map.byName,GetSpellNameFromID(id),k)
    if C_Spell then
        if C_Spell.GetOverrideSpell then local o=C_Spell.GetOverrideSpell(id); if o and not map.byID[o] then map.byID[o]=k; AddNameKey(map.byName,GetSpellNameFromID(o),k) end end
        if C_Spell.GetBaseSpell    then local b=C_Spell.GetBaseSpell(id);    if b and not map.byID[b] then map.byID[b]=k; AddNameKey(map.byName,GetSpellNameFromID(b),k) end end
    end
end
local function SetSpellKey(map,id,k)
    if not map or not id or id==0 or not k or k=="" then return end
    map.byID[id]=k; local nm=GetSpellNameFromID(id); if nm then map.byName[nm:lower()]=k end
    if C_Spell then
        if C_Spell.GetOverrideSpell then local o=C_Spell.GetOverrideSpell(id); if o and o~=0 then map.byID[o]=k; local on=GetSpellNameFromID(o); if on then map.byName[on:lower()]=k end end end
        if C_Spell.GetBaseSpell    then local b=C_Spell.GetBaseSpell(id);    if b and b~=0 then map.byID[b]=k; local bn=GetSpellNameFromID(b); if bn then map.byName[bn:lower()]=k end end end
    end
end
local function LookupSpell(map,id)
    if not map or not id then return "" end
    if map.byID[id] then return map.byID[id] end
    if C_Spell then
        if C_Spell.GetOverrideSpell then local o=C_Spell.GetOverrideSpell(id); if o and map.byID[o] then return map.byID[o] end end
        if C_Spell.GetBaseSpell    then local b=C_Spell.GetBaseSpell(id);    if b and map.byID[b] then return map.byID[b] end end
    end
    local nm=GetSpellNameFromID(id); if nm then return map.byName[nm:lower()] or "" end
    return ""
end
local function AddItemKey(map,id,k)
    if not map or not id or id==0 or not k or k=="" then return end
    if map.itemsByID[id] then return end
    map.itemsByID[id]=k; local nm=GetItemNameFromID(id); if nm and not map.itemsByName[nm:lower()] then map.itemsByName[nm:lower()]=k end
end
local function LookupItem(map,id)
    if not map or not id then return "" end
    if map.itemsByID[id] then return map.itemsByID[id] end
    local nm=GetItemNameFromID(id); if nm then return map.itemsByName[nm:lower()] or "" end
    return ""
end

-- ── BCDM helpers ──────────────────────────────────────────────────────────────
local function BCDMNum(nm)
    if not nm then return nil end
    return tonumber(nm:match("^BCDM_Custom_(%d+)")) or tonumber(nm:match("^BCDM_AdditionalCustom_(%d+)"))
end
local function BCDMTrinketSlot(nm)
    if not nm then return nil end; return tonumber(nm:match("^BCDM_Custom_Trinket_(%d+)"))
end
local function IsBCDMTrinket(f)
    f=GetAttachFrame(f); if not f or not f.GetName then return false end
    local nm=f:GetName()
    return nm and ((nm:find("BCDM",1,true) and nm:lower():find("trinket",1,true)) or nm:match("^BCDM_Custom_Trinket_%d+")~=nil)
end
local function IsBCDMCustom(f)
    f=GetAttachFrame(f); if not f or not f.GetName then return false end
    local nm=f:GetName(); return nm and (nm:match("^BCDM_Custom_%d+") or nm:match("^BCDM_AdditionalCustom_%d+"))
end

local function GetBtnSpell(btn)
    if not btn then return nil end
    local s=btn.spellID or btn.spellId or btn.SpellID
    if type(s)=="number" and s>0 then return s end
    if btn.GetAttribute then
        local t=btn:GetAttribute("type") or btn:GetAttribute("type1")
        if t=="spell" then local sp=btn:GetAttribute("spell") or btn:GetAttribute("spell1"); if type(sp)=="number" and sp>0 then return sp end; if type(sp)=="string" then return GetSpellIDFromName(sp) end end
    end
    if btn.action then local at,id=GetActionInfo(btn.action); if at=="spell" and type(id)=="number" then return id end end
    return nil
end
local function GetBtnItem(btn)
    if not btn then return nil end
    local i=btn.itemID or btn.itemId or btn.ItemID
    if type(i)=="number" and i>0 then return i end
    if btn.GetAttribute then
        local t=btn:GetAttribute("type") or btn:GetAttribute("type1")
        if t=="item" then local it=btn:GetAttribute("item") or btn:GetAttribute("item1"); if type(it)=="number" and it>0 then return it end; if type(it)=="string" then local n=tonumber(it); if n and n>0 then return n end end end
    end
    if btn.action then local at,id=GetActionInfo(btn.action); if at=="item" and type(id)=="number" then return id end end
    return nil
end

local function ScanBCDM(map)
    local roots={_G["BCDM_CustomCooldownViewer"],_G["BCDM_CustomItemSpellBar"],_G["BCDM_CustomItemBar"],_G["BCDM_AdditionalCustomCooldownViewer"],_G["BCDM_TrinketBar"],_G["CDM_TrinketsContainer"]}
    for _,root in ipairs(roots) do
        if root then
            local list,seen={},{}; CollectFrameDescendants(root,list,seen,1,7,2000)
            for _,f in ipairs(list) do
                local btn=GetAttachFrame(f); if btn then
                    local rk=TryGetKey(btn)
                    if rk and rk~="" and rk~="●" then
                        local fmt=FormatKey(rk); if fmt~="" then
                            local s=GetBtnSpell(btn); if s then AddSpellKey(map,s,fmt)
                            else local i=GetBtnItem(btn); if i then AddItemKey(map,i,fmt) end end
                        end
                    end
                end
            end
        end
    end
end

-- ── Adapters ──────────────────────────────────────────────────────────────────
local Adapters={}
Adapters.Blizzard={
    Detect=function() return true end,
    Iterate=function(y)
        for _,pfx in ipairs({"ActionButton","MultiBarBottomLeftButton","MultiBarBottomRightButton","MultiBarRightButton","MultiBarLeftButton","MultiBar5Button","MultiBar6Button","MultiBar7Button"}) do
            for j=1,12 do local btn=_G[pfx..j]; if btn and btn.action then local k=TryGetKey(btn); if k and k~="●" then local sl=btn.action; if ActionButton_GetPagedID then local pg=ActionButton_GetPagedID(btn); if type(pg)=="number" and pg>0 then sl=pg end end; y(sl,k) end end end
        end
    end,
}
Adapters.Dominos={Detect=function() local b=_G["DominosActionButton1"]; return b and b.action~=nil end,Iterate=function(y) for i=1,180 do local b=_G["DominosActionButton"..i]; if b and b.action then local k=TryGetKey(b); if k and k~="●" then y(b.action,k) end end end end}
Adapters.BT4={Detect=function() local b=_G["BT4Button1"]; return b and b.action~=nil end,Iterate=function(y) for i=1,180 do local b=_G["BT4Button"..i]; if b and b.action then local k=TryGetKey(b); if k and k~="●" then y(b.action,k) end end end end}
Adapters.ElvUI={Detect=function() local b=_G["ElvUI_Bar1Button1"]; return b and b.action~=nil end,Iterate=function(y) for bar=1,15 do for j=1,12 do local b=_G["ElvUI_Bar"..bar.."Button"..j]; if b and b.action then local k=TryGetKey(b); if k and k~="●" then y(b.action,k) end end end end end}

local function PickAdapter()
    if Adapters.Dominos.Detect() then return Adapters.Dominos,"Dominos" end
    if Adapters.BT4.Detect()     then return Adapters.BT4,"BT4"         end
    if Adapters.ElvUI.Detect()   then return Adapters.ElvUI,"ElvUI"     end
    return Adapters.Blizzard,"Blizzard"
end

-- ── Mapping builder ───────────────────────────────────────────────────────────
local function ScanPrimaryBase(map,mq)
    if not GetBindingKey or not GetActionInfo then return end
    for i=1,12 do
        local rk=GetBindingKey("ACTIONBUTTON"..i)
        if rk and rk~="" and rk~="●" then
            local fmt=FormatKey(rk); if fmt~="" then
                local at,id=GetActionInfo(i)
                if at=="spell" then AddSpellKey(map,id,fmt)
                elseif at=="item" then AddItemKey(map,id,fmt)
                elseif at=="macro" then mq[#mq+1]={slot=i,id=id,fmt=fmt} end
            end
        end
    end
end

local function ResolveMacroSlot(slot,id)
    local nm=GetActionText and GetActionText(slot)
    if nm and nm~="" and GetMacroIndexByName then local idx=GetMacroIndexByName(nm); if idx and idx>0 then return idx end end
    if type(id)=="number" and id>0 and GetMacroInfo then local n=GetMacroInfo(id); if n then return id end end
    return nil
end

local function BuildMapping()
    if InCombat() then return {byID={},byName={},itemsByID={},itemsByName={}},false end
    local adapter,name=PickAdapter()
    if not adapter then return {byID={},byName={},itemsByID={},itemsByName={}},false end
    local changed=(activeAdapterName~=name); activeAdapterName=name
    local map={byID={},byName={},itemsByID={},itemsByName={}}
    local mq={}
    adapter.Iterate(function(slot,rk)
        local fmt=FormatKey(rk); if fmt=="" then return end
        local at,id=GetActionInfo(slot); if not at or not id then return end
        if at=="spell" then AddSpellKey(map,id,fmt)
        elseif at=="item" then AddItemKey(map,id,fmt)
        elseif at=="macro" then mq[#mq+1]={slot=slot,id=id,fmt=fmt} end
    end)
    ScanPrimaryBase(map,mq)
    ScanBCDM(map)
    for _,m in ipairs(mq) do
        local mi=ResolveMacroSlot(m.slot,m.id)
        if mi then
            local body=GetMacroBody(mi)
            local spells=ResolveMacroSpells(mi,body)
            if spells then for _,ms in ipairs(spells) do SetSpellKey(map,ms,m.fmt) end end
            local lb=(body or ""):lower()
            local hasCast=lb:find("/cast",1,true) or lb:find("/castsequence",1,true)
            local uses=ExtractUseTokens(body)
            if uses then for _,tok in ipairs(uses) do
                local n=tonumber(tok)
                if n then
                    if n==13 or n==14 then
                        if not hasCast then local eq=GetInventoryItemID and GetInventoryItemID("player",n); if eq and not map.itemsByID[eq] then AddItemKey(map,eq,m.fmt) end end
                    else if not map.itemsByID[n] then AddItemKey(map,n,m.fmt) end end
                end
            end end
        end
    end
    return map,changed
end

local function RebuildMapping() local m,c=BuildMapping(); mappingCache=m; return c end

-- ── Overlays ──────────────────────────────────────────────────────────────────
local function GetOrCreateOverlay(icon)
    icon=GetAttachFrame(icon); if not icon then return nil end
    if icon.mqCKBText and icon.mqCKBText.text then return icon.mqCKBText.text end
    icon.mqCKBText=CreateFrame("Frame",nil,icon,"BackdropTemplate")
    icon.mqCKBText:SetFrameLevel(icon:GetFrameLevel()+1)
    local t=icon.mqCKBText:CreateFontString(nil,"OVERLAY","NumberFontNormalSmall")
    t:SetShadowColor(0,0,0,1); t:SetShadowOffset(1,-1); t:SetDrawLayer("OVERLAY",7)
    icon.mqCKBText.text=t; return t
end

local function ApplyStyle(icon,vk)
    icon=GetAttachFrame(icon); if not icon or not icon.mqCKBText then return end
    local v=GetViewerDB(vk); local t=GetOrCreateOverlay(icon); if not t then return end
    t:ClearAllPoints(); t:SetPoint(v.anchor or "TOPRIGHT",icon,v.anchor or "TOPRIGHT",v.offsetX or -1,v.offsetY or -1)
    t:SetFont(GetFontPath(v.fontName),v.fontSize or 12,v.fontFlags or "")
    local c=v.color or {1,1,1,1}; t:SetTextColor(c[1] or 1,c[2] or 1,c[3] or 1,c[4] or 1)
end

local function HideOverlay(icon)
    icon=GetAttachFrame(icon); if icon and icon.mqCKBText then icon.mqCKBText:Hide() end
end

-- ── Extract spell/item from cooldown icon ─────────────────────────────────────
local function ExtractSpell(icon)
    icon=GetAttachFrame(icon); if not icon then return nil end
    if icon.GetCooldownInfo then local ok,i=pcall(icon.GetCooldownInfo,icon); if ok and i then local s=i.overrideSpellID or i.spellID or i.linkedSpellID; if s and s~=0 then return s end end end
    if icon.GetSpellID then local ok,s=pcall(icon.GetSpellID,icon); if ok and s and s~=0 then return s end end
    if icon.cooldownID and C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo then local i=C_CooldownViewer.GetCooldownViewerCooldownInfo(icon.cooldownID); if i and i.spellID then return i.spellID end end
    if not icon.isItem then
        local s=icon.spellID or icon.spellId or icon.SpellID; if s then return s end
        if icon.GetName then s=BCDMNum(icon:GetName()); if s then return s end end
        if icon.GetParent then local p=icon:GetParent(); if p and p.GetName then return BCDMNum(p:GetName()) end end
    end
    return nil
end

local function ExtractItem(icon,vk)
    icon=GetAttachFrame(icon); if not icon then return nil end
    local i=icon.itemID or icon.itemId or icon.ItemID
    if not i and icon.GetName then i=BCDMNum(icon:GetName()) end
    if not i and icon.GetParent then local p=icon:GetParent(); if p and p.GetName then i=BCDMNum(p:GetName()) end end
    if not i and vk=="BCDMTrinkets" then
        local sl; if icon.GetName then sl=BCDMTrinketSlot(icon:GetName()) end
        if not sl and icon.GetParent then local p=icon:GetParent(); if p and p.GetName then sl=BCDMTrinketSlot(p:GetName()) end end
        if sl and GetInventoryItemID then i=GetInventoryItemID("player",sl) end
    end
    return i
end

local function ClearIconCaches(kids) for _,ch in ipairs(kids) do ch=GetAttachFrame(ch); if ch then ch.mqCKBSID=nil; ch.mqCKBIID=nil end end end

-- ── Viewer child cache ────────────────────────────────────────────────────────
local function ShouldRecache(vfn,vk)
    local f=_G[vfn]; if not f then return true end
    if f.itemFramePool then return true end
    local c=viewerChildrenCache[vfn]; if not c then return true end
    if f.GetNumChildren and f:GetNumChildren()~=(viewerChildCountCache[vfn] or 0) then return true end
    if vk=="BCDMTrinkets" and #c==0 then return true end
    return false
end
local function CacheChildren(vfn,vk)
    local vf=_G[vfn]
    if not vf then viewerChildrenCache[vfn]=nil; viewerChildCountCache[vfn]=0; return end
    local list={}
    if vf.itemFramePool then for fr in vf.itemFramePool:EnumerateActive() do if fr:IsShown() then list[#list+1]=fr end end
    elseif vk=="BCDMCustomSpells" or vk=="BCDMCustomItems" or vk=="BCDMTrinkets" then
        local seen={}; CollectFrameDescendants(vf,list,seen,1,7,2000)
    else list={vf:GetChildren()} end
    viewerChildrenCache[vfn]=list
    viewerChildCountCache[vfn]=vf.GetNumChildren and vf:GetNumChildren() or #list
    ClearIconCaches(list)
end
local function GetChildren(vfn,vk)
    if not _G[vfn] then return {} end
    if ShouldRecache(vfn,vk) then CacheChildren(vfn,vk) end
    return viewerChildrenCache[vfn] or {}
end

-- ── Apply viewer ──────────────────────────────────────────────────────────────
local function ApplyViewer(vfn,vk,map)
    local vf=_G[vfn]; if not vf then return end
    local v=GetViewerDB(vk)
    if not v or not v.showKeybinds then
        for _,ch in ipairs(viewerChildrenCache[vfn] or {vf:GetChildren()}) do HideOverlay(ch) end; return
    end
    for _,ch in ipairs(GetChildren(vfn,vk)) do
        ch=GetAttachFrame(ch); if ch then
            local isCustom=(vk=="BCDMCustomSpells" or vk=="BCDMCustomItems")
            local isBT=(vk=="BCDMTrinkets"); local isCT=(vk=="Trinkets")
            local ok=(not isCustom and not isBT and not isCT) or (isCustom and IsBCDMCustom(ch)) or (isBT and IsBCDMTrinket(ch)) or isCT
            if ok then
                local text=""; local hasT=false
                if vk=="BCDMTrinkets" or vk=="Trinkets" then
                    local dk=DirectKey(ch)
                    if dk~="" then text=dk; hasT=true
                    else local i=ExtractItem(ch,vk); if i then local mk=LookupItem(map,i); if mk~="" then text=mk; hasT=true end end end
                elseif vk=="BCDMCustomItems" then
                    local i=ExtractItem(ch,vk); if i then text=LookupItem(map,i); hasT=true end
                else
                    local s=ExtractSpell(ch)
                    if s then text=LookupSpell(map,s); hasT=true
                    else
                        local i=ExtractItem(ch,vk)
                        if i then
                            text=LookupItem(map,i)
                            if text=="" and ch.cdmRacialEntry and ch.cdmRacialEntry.alternateItemID then text=LookupItem(map,ch.cdmRacialEntry.alternateItemID) end
                            hasT=true
                        end
                    end
                end
                if hasT then
                    local t=GetOrCreateOverlay(ch)
                    if t then ApplyStyle(ch,vk)
                        if text=="" then t:SetText(""); HideOverlay(ch)
                        else ch.mqCKBText:Show(); t:SetText(text); t:Show() end
                    end
                else HideOverlay(ch) end
            else HideOverlay(ch) end
        end
    end
end

local function ApplyAll()
    if not mappingCache then return end
    for vfn,vk in pairs(VIEWERS) do CacheChildren(vfn,vk); ApplyViewer(vfn,vk,mappingCache) end
end

local function ApplyAllStyles()
    if not mappingCache then return end
    for vfn,vk in pairs(VIEWERS) do
        local vf=_G[vfn]; if vf then
            for _,ch in ipairs(GetChildren(vfn,vk)) do
                ch=GetAttachFrame(ch)
                if ch and ch.mqCKBText and ch.mqCKBText:IsShown() then ApplyStyle(ch,vk) end
            end
        end
    end
end

-- ── Trinket warmup ────────────────────────────────────────────────────────────
local function HasTrinketKey()
    if not mappingCache then return false end
    CacheChildren("BCDM_TrinketBar","BCDMTrinkets")
    for _,ch in ipairs(GetChildren("BCDM_TrinketBar","BCDMTrinkets")) do
        ch=GetAttachFrame(ch); if ch and IsBCDMTrinket(ch) and DirectKey(ch)~="" then return true end
    end
    return false
end

local WarmupTrinkets
WarmupTrinkets=function()
    if not isEnabled then trinketWarmupRunning=false; return end
    if InCombat() then C_Timer.After(0.5,WarmupTrinkets); return end
    if not mappingCache then RebuildMapping() end
    CacheChildren("BCDM_TrinketBar","BCDMTrinkets")
    ApplyViewer("BCDM_TrinketBar","BCDMTrinkets",mappingCache)
    if HasTrinketKey() then trinketWarmupRunning=false; return end
    trinketWarmupIndex=trinketWarmupIndex+1
    if trinketWarmupIndex>#trinketWarmupDelays then trinketWarmupRunning=false; return end
    C_Timer.After(trinketWarmupDelays[trinketWarmupIndex],WarmupTrinkets)
end

local function ScheduleWarmup()
    if not isEnabled or trinketWarmupRunning then return end
    trinketWarmupRunning=true; trinketWarmupIndex=1
    C_Timer.After(trinketWarmupDelays[1],WarmupTrinkets)
end

-- ── Viewer hooks ──────────────────────────────────────────────────────────────
local function EnsureHooks()
    for vfn,vk in pairs(VIEWERS) do
        if not hooked[vfn] then
            local f=_G[vfn]; if f then
                if type(f.RefreshLayout)=="function" then
                    hooksecurefunc(f,"RefreshLayout",function()
                        if not isEnabled then return end
                        CacheChildren(vfn,vk); if InCombat() then return end
                        if not mappingCache then RebuildMapping() end
                        ApplyViewer(vfn,vk,mappingCache)
                        if vk=="BCDMTrinkets" then ScheduleWarmup() end
                    end)
                end
                local ACDM=_G["Ayije_CDM"]
                if ACDM and not ACDM.__mqCKBQ and type(ACDM.QueueViewer)=="function" then
                    ACDM.__mqCKBQ=true
                    hooksecurefunc(ACDM,"QueueViewer",function(_,vn)
                        if not isEnabled then return end; local k=VIEWERS[vn]; if not k then return end
                        C_Timer.After(0.05,function()
                            if not isEnabled or InCombat() then return end
                            CacheChildren(vn,k); if not mappingCache then RebuildMapping() end; ApplyViewer(vn,k,mappingCache)
                        end)
                    end)
                end
                if not f.__mqCKBOS then
                    f.__mqCKBOS=true
                    f:HookScript("OnShow",function()
                        if not isEnabled then return end; CacheChildren(vfn,vk)
                        if InCombat() then return end; if not mappingCache then RebuildMapping() end
                        ApplyViewer(vfn,vk,mappingCache)
                        if vk=="BCDMTrinkets" or vk=="Trinkets" then ScheduleWarmup() end
                    end)
                end
                hooked[vfn]=true; CacheChildren(vfn,vk)
            end
        end
    end
end

-- ── Schedulers ────────────────────────────────────────────────────────────────
local function ScheduleOOC()
    if not isEnabled then return end; dirtyOOC=true; if scheduledOOC then return end; scheduledOOC=true
    local function run() scheduledOOC=false; if not isEnabled then return end
        if InCombat() then C_Timer.After(0.5,run); return end
        if dirtyOOC then dirtyOOC=false; RebuildMapping(); EnsureHooks(); ApplyAll(); ScheduleWarmup() end
    end
    C_Timer.After(0.1,run)
end

local scheduledStyle=false
local function ScheduleStyle()
    if not isEnabled or scheduledStyle then return end; scheduledStyle=true
    local function run() scheduledStyle=false; if not isEnabled then return end
        if InCombat() then C_Timer.After(0.5,run); return end; ApplyAllStyles()
    end
    C_Timer.After(0.05,run)
end

local function ScheduleSeries()
    if not isEnabled then return end; seriesDirty=true; if scheduledSeries then return end; scheduledSeries=true; seriesIndex=1
    local function step()
        if not isEnabled then scheduledSeries=false; seriesDirty=false; return end
        if InCombat() then C_Timer.After(0.5,step); return end
        if seriesDirty then
            seriesDirty=false; local ch=RebuildMapping(); EnsureHooks(); ApplyAll(); ScheduleWarmup()
            seriesIndex=seriesIndex+1
            if (ch or MappingLooksEmpty(mappingCache)) and seriesIndex<=#seriesDelays then
                C_Timer.After(seriesDelays[seriesIndex],function() seriesDirty=true; step() end); return
            end
        end
        scheduledSeries=false
    end
    C_Timer.After(seriesDelays[seriesIndex],step)
end

-- ── Binding hooks ─────────────────────────────────────────────────────────────
local bindHooked=false
local function HookBindings()
    if bindHooked then return end; bindHooked=true
    local function onBC() if isEnabled then ScheduleOOC() end end
    if hooksecurefunc then
        for _,fn in ipairs({"SetBinding","SetBindingClick","SetBindingSpell","SetBindingMacro","SaveBindings","LoadBindings"}) do
            if _G[fn] then hooksecurefunc(fn,onBC) end
        end
    end
end

-- ── Enable / Disable / OnChanged ─────────────────────────────────────────────
local evFrame=CreateFrame("Frame")
local BAR_ADDONS={BetterCooldownManager=true,Ayije_CDM=true,ElvUI=true,Bartender4=true,Dominos=true}
evFrame:SetScript("OnEvent",function(_,event,arg1)
    if not isEnabled then return end
    if event=="PLAYER_ENTERING_WORLD" or (event=="ADDON_LOADED" and (arg1=="RogUI_Core" or BAR_ADDONS[arg1])) then ScheduleSeries(); return end
    if event=="UNIT_INVENTORY_CHANGED" and arg1 and arg1~="player" then return end
    local ooc=event=="UPDATE_BINDINGS" or event=="UPDATE_MACROS" or event=="ACTIONBAR_SLOT_CHANGED" or event=="SPELLS_CHANGED"
           or event=="SPELL_DATA_LOAD_RESULT" or event=="PLAYER_SPECIALIZATION_CHANGED" or event=="TRAIT_CONFIG_UPDATED"
           or event=="ACTIONBAR_PAGE_CHANGED" or event=="UPDATE_BONUS_ACTIONBAR" or event=="EDIT_MODE_LAYOUTS_UPDATED"
           or event=="PLAYER_EQUIPMENT_CHANGED" or event=="UNIT_INVENTORY_CHANGED"
           or event=="UPDATE_OVERRIDE_ACTIONBAR" or event=="UPDATE_VEHICLE_ACTIONBAR" or event=="UPDATE_POSSESS_BAR"
    if ooc then ScheduleOOC(); if event=="PLAYER_EQUIPMENT_CHANGED" or event=="UNIT_INVENTORY_CHANGED" then ScheduleWarmup() end end
end)

local ALL_EVS={"PLAYER_ENTERING_WORLD","ADDON_LOADED","UPDATE_BINDINGS","UPDATE_MACROS","ACTIONBAR_SLOT_CHANGED","SPELLS_CHANGED","SPELL_DATA_LOAD_RESULT","PLAYER_SPECIALIZATION_CHANGED","TRAIT_CONFIG_UPDATED","UPDATE_BONUS_ACTIONBAR","ACTIONBAR_PAGE_CHANGED","EDIT_MODE_LAYOUTS_UPDATED","PLAYER_EQUIPMENT_CHANGED","UNIT_INVENTORY_CHANGED","UPDATE_OVERRIDE_ACTIONBAR","UPDATE_VEHICLE_ACTIONBAR","UPDATE_POSSESS_BAR"}

local function CKBEnable()
    if isEnabled then return end; isEnabled=true
    for _,ev in ipairs(ALL_EVS) do pcall(evFrame.RegisterEvent,evFrame,ev) end
    HookBindings(); EnsureHooks(); ScheduleSeries(); ScheduleWarmup()
end
local function CKBDisable()
    if not isEnabled then return end; isEnabled=false; mappingCache=nil
    evFrame:UnregisterAllEvents(); trinketWarmupRunning=false
    for vfn in pairs(VIEWERS) do
        local vf=_G[vfn]; if vf then
            for _,ch in ipairs(viewerChildrenCache[vfn] or {vf:GetChildren()}) do HideOverlay(ch) end
        end
    end
end
local function OnChanged()
    if not IsAnyViewerEnabled() then CKBDisable(); return end
    if not isEnabled then CKBEnable(); return end
    if mappingCache then ScheduleStyle() end; ScheduleOOC()
end
local function ResetDefaults()
    local db=GetDB(); if not db then return end
    db.enabled=true; db.viewers={}
    mappingCache=nil; viewerChildrenCache={}; viewerChildCountCache={}; hooked={}
    scheduledOOC=false; dirtyOOC=false; scheduledSeries=false; seriesDirty=false
    activeAdapterName=nil; trinketWarmupRunning=false; OnChanged()
end

-- ── Expose to API ─────────────────────────────────────────────────────────────
API.CKBEnable           = CKBEnable
API.CKBDisable          = CKBDisable
API.CKBOnSettingChanged = OnChanged
API.CKBResetDefaults    = ResetDefaults

-- ── Boot ──────────────────────────────────────────────────────────────────────
API.RegisterEvent("CooldownKeybinds", "PLAYER_LOGIN", function()
    local db=GetDB()
    if db and db.enabled and IsAnyViewerEnabled() then CKBEnable() end
end)
