-- ============================================================
-- MidnightQoL_QoL / Utility.lua
-- Utility alerts:
--   • Rogue missing-poison alert on combat enter
--   • Raid buff checker on ready check (10s icon HUD)
--   • Battle Rez tracker (charge count + cooldown)
-- NOTE: Lust/Sated alert is handled via the Buffs tab (trackedBuffs)
--       using the non-secret sated debuff IDs as triggers.
-- ============================================================

local API = MidnightQoLAPI

-- LibOpenRaid-1.0: resolved after PLAYER_LOGIN so LibStub is guaranteed initialised.
-- All access goes through this local; nil-checked at every call site.
local openRaidLib = nil
local function GetOpenRaidLib()
    if not openRaidLib and LibStub then
        openRaidLib = LibStub:GetLibrary("LibOpenRaid-1.0", true)
    end
    return openRaidLib
end

-- ── DB helpers ────────────────────────────────────────────────────────────────
local function GetDB()
    if not BuffAlertDB then return {} end
    if BuffAlertDB.poisonAlertEnabled   == nil then BuffAlertDB.poisonAlertEnabled   = false end
    if BuffAlertDB.raidbuffCheckEnabled == nil then BuffAlertDB.raidbuffCheckEnabled = false end
    if BuffAlertDB.battlerezEnabled     == nil then BuffAlertDB.battlerezEnabled     = false end
    return BuffAlertDB
end

-- ============================================================
-- ROGUE POISON ALERT
-- On combat enter, check that this rogue spec's expected poisons are applied.
-- ============================================================
-- Poison spell IDs (applied to weapons)
local POISON_IDS = {
    [2823]   = "Deadly Poison",
    [8679]   = "Wound Poison",
    [3408]   = "Crippling Poison",
    [5761]   = "Mind-Numbing Poison",
    [315584] = "Instant Poison",
    [381637] = "Atrophic Poison",
    [381664] = "Numbing Poison",
}
-- Which poisons count as "offensive" (main-hand worthy)
local OFFENSIVE_POISONS = { [2823]=true, [8679]=true, [315584]=true }

local function GetAppliedPoisons()
    local found = {}
    -- Query each known poison ID directly instead of iterating the aura list and
    -- comparing tainted secret spellId values (which throws a taint error in TWW).
    -- Matches the pcall pattern used throughout this addon (BuffAlerts, CheckRaidBuffs).
    for spellId in pairs(POISON_IDS) do
        local ok, auraData = pcall(C_UnitAuras.GetPlayerAuraBySpellID, spellId)
        if ok and auraData then found[spellId] = true end
    end
    return found
end

local function CheckRoguePoisons()
    local db = GetDB()
    if not db.poisonAlertEnabled then return end
    local _, class = UnitClass("player")
    if class ~= "ROGUE" then return end

    local applied = GetAppliedPoisons()
    local count = 0
    for _ in pairs(applied) do count = count + 1 end

    -- Rogues should have at least 1 offensive and 1 total poison
    local hasOffensive = false
    for id in pairs(applied) do
        if OFFENSIVE_POISONS[id] then hasOffensive = true; break end
    end

    local missing = {}
    if not hasOffensive then missing[#missing+1] = "an offensive poison (Deadly/Wound/Instant)" end
    if count == 0 then missing[#missing+1] = "any poison" end

    if #missing > 0 then
        print("|cFFFF0000[MidnightQoL]|r |cFFFFD700Rogue: Missing " .. table.concat(missing, " and ") .. "!|r")
    end
end

-- ============================================================
-- RAID BUFF CHECKER
-- On READY_CHECK, show a 10-second HUD with icons of missing buffs.
-- ============================================================
local RAID_BUFFS = {
    { name = "Battle Shout",          spellId = 6673,   class = "WARRIOR" },
    { name = "Arcane Intellect",      spellId = 1459,   class = "MAGE"    },
    { name = "Mark of the Wild",      spellId = 1126,   class = "DRUID"   },
    { name = "Power Word: Fortitude", spellId = 21562,  class = "PRIEST"  },
    { name = "Blessing of the Bronze",spellId = 381748, class = "EVOKER"  },
    { name = "Skyfury",               spellId = 462854, class = "SHAMAN"  },
}
local BUFF_BY_CLASS = {}
for _, b in ipairs(RAID_BUFFS) do BUFF_BY_CLASS[b.class] = b end

-- HUD frame
local raidBuffHUD = CreateFrame("Frame", "MidnightQoLRaidBuffHUD", UIParent, "BackdropTemplate")
raidBuffHUD:SetPoint("CENTER", UIParent, "CENTER", 0, 200)
raidBuffHUD:SetFrameStrata("HIGH")
raidBuffHUD:SetMovable(true); raidBuffHUD:EnableMouse(true); raidBuffHUD:RegisterForDrag("LeftButton")
raidBuffHUD:SetScript("OnDragStart", function(self) if API.IsLayoutMode and API.IsLayoutMode() then self:StartMoving() end end)
raidBuffHUD:SetScript("OnDragStop",  function(self) self:StopMovingOrSizing()
    if BuffAlertDB then BuffAlertDB.raidBuffHUDX = self:GetLeft(); BuffAlertDB.raidBuffHUDY = self:GetTop() end
end)
raidBuffHUD:SetBackdrop({ bgFile="Interface/Buttons/WHITE8x8",
    edgeFile="Interface/DialogFrame/UI-DialogBox-Border", edgeSize=10,
    insets={left=4,right=4,top=4,bottom=4} })
raidBuffHUD:SetBackdropColor(0, 0, 0, 0.85)
raidBuffHUD:SetBackdropBorderColor(0.6, 0.6, 0.6, 0.8)
raidBuffHUD:Hide()

local raidBuffTitle = raidBuffHUD:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
raidBuffTitle:SetPoint("TOPLEFT", raidBuffHUD, "TOPLEFT", 8, -6)
raidBuffTitle:SetText("|cFFFF6600Missing Raid Buffs|r")

local raidBuffIcons = {}  -- pool of icon frames

local function GetOrCreateRaidIcon(idx)
    if raidBuffIcons[idx] then return raidBuffIcons[idx] end
    local f = CreateFrame("Frame", nil, raidBuffHUD)
    f:SetSize(36, 36)
    f.tex = f:CreateTexture(nil, "ARTWORK")
    f.tex:SetAllPoints()
    f.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    f.lbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.lbl:SetPoint("TOP", f, "BOTTOM", 0, -2)
    f.lbl:SetTextColor(1, 0.6, 0.6)
    raidBuffIcons[idx] = f
    return f
end

local raidBuffHideTimer = nil

local function ShowRaidBuffHUD(missing)
    if raidBuffHideTimer then raidBuffHideTimer:Cancel(); raidBuffHideTimer = nil end

    -- Hide all icons first
    for _, ic in ipairs(raidBuffIcons) do ic:Hide() end

    if #missing == 0 then
        raidBuffHUD:Hide()
        return
    end

    local ICO_SIZE  = 36
    local ICO_PAD   = 6
    local TITLE_H   = 22
    local totalW    = ICO_PAD + (#missing * (ICO_SIZE + ICO_PAD))
    local totalH    = TITLE_H + ICO_SIZE + 28  -- room for label below icon

    raidBuffHUD:SetSize(math.max(totalW, 120), totalH)

    for idx, buffDef in ipairs(missing) do
        local ic = GetOrCreateRaidIcon(idx)
        ic:SetPoint("TOPLEFT", raidBuffHUD, "TOPLEFT",
            ICO_PAD + (idx - 1) * (ICO_SIZE + ICO_PAD), -(TITLE_H + 4))
        local info = C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(buffDef.spellId)
        ic.tex:SetTexture(info and info.iconID or 134400)
        local className = buffDef.class:sub(1,1) .. buffDef.class:sub(2):lower()
        ic.lbl:SetText(className)
        ic:Show()
    end

    -- Restore position if saved
    if BuffAlertDB and BuffAlertDB.raidBuffHUDX and BuffAlertDB.raidBuffHUDY then
        raidBuffHUD:ClearAllPoints()
        raidBuffHUD:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT",
            BuffAlertDB.raidBuffHUDX, BuffAlertDB.raidBuffHUDY)
    end

    raidBuffHUD:SetAlpha(1)
    raidBuffHUD:Show()
    -- No auto-hide: frame stays visible until all buffs are present or group disbands
end

local function CheckRaidBuffs()
    local db = GetDB()
    if not db.raidbuffCheckEnabled then return end
    if not IsInGroup() then return end

    -- Build the set of classes present in the group.
    -- Prefer LibOpenRaid unit info (cross-realm safe, includes late joiners that
    -- UnitClass() can return nil for before their unit token is populated).
    local classesPresent = {}
    local lib = GetOpenRaidLib()
    if lib then
        local allInfo = lib.GetAllUnitsInfo()
        if allInfo then
            for _, unitInfo in pairs(allInfo) do
                if unitInfo.class and unitInfo.class ~= "" then
                    classesPresent[unitInfo.class] = true
                end
            end
        end
    end
    -- Always fall back / supplement with direct UnitClass calls so the check
    -- works even if LibOpenRaid hasn't received unit info yet (e.g. fresh login).
    local numMembers = GetNumGroupMembers()
    for i = 1, numMembers do
        local unit = IsInRaid() and ("raid"..i) or ("party"..i)
        if UnitExists(unit) then
            local _, cls = UnitClass(unit)
            if cls then classesPresent[cls] = true end
        end
    end
    local _, myCls = UnitClass("player")
    if myCls then classesPresent[myCls] = true end

    local missing = {}
    for cls in pairs(classesPresent) do
        local buffDef = BUFF_BY_CLASS[cls]
        if buffDef then
            -- Use GetPlayerAuraBySpellID keyed on our own spell ID so we never
            -- touch a tainted secret value.  Matches the pcall pattern used in
            -- BuffAlerts.lua (ShowAlertOverlay / progress ticker).
            local found = false
            local ok, auraData = pcall(C_UnitAuras.GetPlayerAuraBySpellID, buffDef.spellId)
            if ok and auraData then found = true end
            if not found then missing[#missing+1] = buffDef end
        end
    end

    ShowRaidBuffHUD(missing)
end

-- ============================================================
-- BATTLE REZ TRACKER
-- Icon + charge count + cooldown swipe/timer.
--
-- Approach taken directly from BattleRezTracker (Ferroz):
--   • C_Spell.GetSpellCharges(20484) — Rebirth is the canonical charge
--     pool Blizzard uses for the shared raid brez mechanic. All brez
--     spells (Raise Ally, Soulstone, Reawaken) share this pool so
--     querying Rebirth is sufficient regardless of who is in the group.
--   • CooldownFrameTemplate handles the swipe + countdown — no manual
--     ticker, no text manipulation, no taint from reading expiration times.
--   • countText:SetAlpha(currentCharges) — taint-safe show/hide trick:
--     alpha is clamped to [0,1] so 0=hidden, 1+=visible without ever
--     comparing the secret charge value.
--   • RegisterStateDriver handles combat alpha without taint.
--   • A separate zoneVisibility frame controls Show/Hide OOC only.
-- ============================================================

local BREZ_SPELL_ID = 20484   -- Rebirth: canonical shared brez charge pool

-- Icon texture from spell data (resolved once at frame creation)
local brezSpellInfo = C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(BREZ_SPELL_ID)
local BREZ_ICON     = (brezSpellInfo and brezSpellInfo.iconID) or 136080

-- ── Frame (SecureHandlerStateTemplate for taint-free alpha via state driver) ──
local brezFrame = CreateFrame("Frame", "MidnightQoLBrezFrame", UIParent,
    "SecureHandlerStateTemplate")
brezFrame:SetSize(52, 52)
brezFrame:SetPoint("CENTER", UIParent, "CENTER", 0, -160)
brezFrame:SetFrameStrata("MEDIUM")
brezFrame:SetClampedToScreen(true)
brezFrame:SetMovable(true)
brezFrame:EnableMouse(true)
brezFrame:RegisterForDrag("LeftButton")
brezFrame:SetScript("OnDragStart", function(self)
    if (API.IsLayoutMode and API.IsLayoutMode()) and not InCombatLockdown() then
        self:StartMoving()
    end
end)
brezFrame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    if BuffAlertDB then BuffAlertDB.brezX = self:GetLeft(); BuffAlertDB.brezY = self:GetTop() end
end)
brezFrame:Hide()

-- Icon background
local brezBg = brezFrame:CreateTexture(nil, "BACKGROUND")
brezBg:SetAllPoints()
brezBg:SetColorTexture(0, 0, 0, 0.6)

-- Spell icon
local brezIcon = brezFrame:CreateTexture(nil, "BACKGROUND", nil, 1)
brezIcon:SetAllPoints()
brezIcon:SetTexture(BREZ_ICON)
brezIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

-- CooldownFrame — handles swipe overlay and countdown numbers natively.
-- No manual ticker needed; no expiration-time reads; no taint.
local brezCD = CreateFrame("Cooldown", nil, brezFrame, "CooldownFrameTemplate")
brezCD:SetFrameLevel(brezFrame:GetFrameLevel() + 1)
brezCD:SetAllPoints(brezFrame)
brezCD:SetDrawSwipe(true)
brezCD:SetDrawEdge(false)
brezCD:SetHideCountdownNumbers(false)
brezCD:SetUseAuraDisplayTime(true)
brezCD:SetCountdownAbbrevThreshold(600)

-- Charge count (bottom-right corner)
local brezCount = brezFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightOutline")
brezCount:SetPoint("BOTTOMRIGHT", brezFrame, "BOTTOMRIGHT", -2, 2)
brezCount:SetFont(brezCount:GetFont(), 14, "OUTLINE")

-- Thin border
local brezBorder = CreateFrame("Frame", nil, brezFrame, "BackdropTemplate")
brezBorder:SetAllPoints()
brezBorder:SetBackdrop({ edgeFile = "Interface/Buttons/WHITE8x8", edgeSize = 1 })
brezBorder:SetBackdropBorderColor(0.25, 0.25, 0.25, 0.9)

-- Dim out-of-combat via state driver (taint-free; no SetAlpha in addon code)
brezFrame:SetAttribute("alpha-full", 1.0)
brezFrame:SetAlpha(0.5)
RegisterStateDriver(brezFrame, "brez-alpha", "[combat] active; inactive")
brezFrame:SetAttribute("_onstate-brez-alpha", [[
    local full = self:GetAttribute("alpha-full") or 1
    self:SetAlpha(newstate == "active" and full or full / 2)
]])

local function UpdateBrezDisplay()
    -- Read charge data from Rebirth (shared pool for all raid brez spells)
    local ci = C_Spell.GetSpellCharges and C_Spell.GetSpellCharges(BREZ_SPELL_ID)
    local currentCharges = 0
    local startTime, duration = 0, 0
    if ci then
        currentCharges = ci.currentCharges or 0
        startTime      = ci.cooldownStartTime or 0
        duration       = ci.cooldownDuration  or 0
    end

    -- Charge count text.
    -- SetAlpha(currentCharges) is the taint-safe visibility trick from BattleRezTracker:
    -- the value is clamped to [0,1] automatically, so 0 = invisible, ≥1 = fully visible,
    -- without ever branching on the secret charge value in addon Lua.
    brezCount:SetFormattedText("%d", currentCharges)
    if InCombatLockdown() then
        brezCount:SetAlpha(1.0)
    else
        brezCount:SetAlpha(currentCharges)
    end

    -- Hand startTime + duration to the CooldownFrame.
    -- It drives the swipe, edge flash, and countdown numbers entirely in C++.
    if startTime and duration and duration > 0 then
        brezCD:SetCooldown(startTime, duration)
    else
        brezCD:Clear()
    end
end

local function UpdateBrezVisibility()
    -- Visibility changes must happen outside combat (protected frames).
    if InCombatLockdown() then return end
    local db = GetDB()
    if not db.battlerezEnabled then
        brezFrame:Hide(); return
    end
    -- Show in raids, M+, and delves (same logic as reference addon)
    local _, instanceType = GetInstanceInfo()
    local isMythicPlus = C_ChallengeMode and C_ChallengeMode.GetActiveKeystoneInfo() > 0
    if instanceType == "raid" or isMythicPlus or instanceType == "scenario" then
        -- Restore saved position before showing
        if BuffAlertDB and BuffAlertDB.brezX and BuffAlertDB.brezY then
            brezFrame:ClearAllPoints()
            brezFrame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT",
                BuffAlertDB.brezX, BuffAlertDB.brezY)
        end
        brezFrame:Show()
    else
        brezFrame:Hide()
    end
end

-- Thin wrapper kept for external callers (layout editor, API.UpdateBrezFrame)
local function UpdateBrezFrame()
    UpdateBrezVisibility()
    UpdateBrezDisplay()
end

-- Zone/visibility events handled on a plain frame (never touches protected state)
local brezVisFrame = CreateFrame("Frame")
brezVisFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
brezVisFrame:RegisterEvent("PLAYER_REGEN_ENABLED")   -- leaving combat → safe to Show/Hide
brezVisFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
brezVisFrame:RegisterEvent("CHALLENGE_MODE_START")
brezVisFrame:SetScript("OnEvent", function() UpdateBrezVisibility() end)

-- ── Events ────────────────────────────────────────────────────────────────────
local utilEvents = CreateFrame("Frame")
utilEvents:RegisterEvent("PLAYER_LOGIN")
utilEvents:RegisterEvent("PLAYER_REGEN_DISABLED")  -- combat enter → poison check
utilEvents:RegisterEvent("READY_CHECK")
utilEvents:RegisterEvent("SPELL_UPDATE_CHARGES")   -- brez charge used/gained
utilEvents:RegisterEvent("GROUP_ROSTER_UPDATE")
utilEvents:RegisterEvent("UNIT_AURA")

local raidBuffTicker = nil

utilEvents:SetScript("OnEvent", function(self, event, unit, ...)
    local db = GetDB()
    if event == "PLAYER_LOGIN" then
        C_Timer.After(2, function()
            UpdateBrezFrame()
            raidBuffTicker = C_Timer.NewTicker(5, CheckRaidBuffs)

            -- LibOpenRaid: only used for raid buff class detection now.
            local lib = GetOpenRaidLib()
            if lib then
                local MidnightQoLCallbacks = {}
                function MidnightQoLCallbacks.OnUnitInfoUpdate()
                    CheckRaidBuffs()
                end
                lib.RegisterCallback(MidnightQoLCallbacks, "UnitInfoUpdate", "OnUnitInfoUpdate")
                lib.RequestAllData()
            end
        end)
    elseif event == "PLAYER_REGEN_DISABLED" then
        C_Timer.After(0.5, CheckRoguePoisons)
    elseif event == "READY_CHECK" then
        C_Timer.After(0.3, CheckRaidBuffs)
    elseif event == "SPELL_UPDATE_CHARGES" then
        -- CooldownFrame handles its own redraw; we only need to refresh the count text.
        UpdateBrezDisplay()
    elseif event == "GROUP_ROSTER_UPDATE" then
        UpdateBrezVisibility()
        CheckRaidBuffs()
    elseif event == "UNIT_AURA" and unit == "player" then
        CheckRaidBuffs()
    end
end)

-- ── Sync enable states from General tab ──────────────────────────────────────
local _baseHideAlertPreviews = nil  -- resolved at call-time so BuffAlerts can register first
API.HideAlertPreviews = function()
    -- Chain into BuffAlerts' version if it has registered itself under a private key
    if not _baseHideAlertPreviews and API._hideAlertPreviewsBase then
        _baseHideAlertPreviews = API._hideAlertPreviewsBase
    end
    if _baseHideAlertPreviews then _baseHideAlertPreviews() end
    -- Hide the frames we showed as previews (UpdateBrezFrame will re-show if conditions are met)
    raidBuffHUD:Hide()
    UpdateBrezFrame()
end

API.UpdateBrezFrame = UpdateBrezFrame

-- ── Layout editor handles ─────────────────────────────────────────────────────
API.RegisterLayoutHandles(function()
    local handles = {}
    local sw, sh = UIParent:GetWidth(), UIParent:GetHeight()

    -- Helper: get center-based ox/oy from a frame's current TOPLEFT position
    local function FrameCenterOffset(f)
        local left = f:GetLeft()
        local top  = f:GetTop()
        if not left or not top then return 0, 0 end
        local cx = left + f:GetWidth()/2
        local cy = top  - f:GetHeight()/2
        return math.floor(cx - sw/2 + 0.5), math.floor(cy - sh/2 + 0.5)
    end

    -- Battle Rez tracker
    do
        -- Force it visible with dummy content so the player can see and drag it
        brezFrame:ClearAllPoints()
        local bx = (BuffAlertDB and BuffAlertDB.brezX) or (sw/2 - brezFrame:GetWidth()/2)
        local by = (BuffAlertDB and BuffAlertDB.brezY) or (sh/2 - 160)
        brezFrame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", bx, by)
        brezFrame:Show()
        -- Preview: show 2 charges and a running cooldown swipe
        brezCount:SetFormattedText("%d", 2)
        brezCount:SetAlpha(1.0)
        brezCD:SetCooldown(GetTime(), 599)  -- 10-min cooldown preview

        local ox, oy = FrameCenterOffset(brezFrame)
        table.insert(handles, {
            label        = "Battle Rez Tracker",
            iconTex      = "Interface\\Icons\\Spell_Holy_Resurrection",
            ox           = ox, oy = oy,
            liveFrameRef = brezFrame,
            saveCallback = function(nx, ny)
                local nbx = nx + sw/2 - brezFrame:GetWidth()/2
                local nby = ny + sh/2 + brezFrame:GetHeight()/2
                brezFrame:ClearAllPoints()
                brezFrame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", nbx, nby)
                if BuffAlertDB then BuffAlertDB.brezX = nbx; BuffAlertDB.brezY = nby end
            end,
        })
    end

    -- Raid Buff HUD
    do
        -- Position it, then show with dummy data
        local hx = (BuffAlertDB and BuffAlertDB.raidBuffHUDX) or (sw/2 - 60)
        local hy = (BuffAlertDB and BuffAlertDB.raidBuffHUDY) or (sh/2 + 200)
        raidBuffHUD:ClearAllPoints()
        raidBuffHUD:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", hx, hy)
        -- Use dummy entries that match the expected struct (spellId + class)
        ShowRaidBuffHUD({
            { spellId=21562, class="PRIEST"  },  -- Power Word: Fortitude
            { spellId=6673,  class="WARRIOR" },  -- Battle Shout
        })
        -- Cancel the auto-hide timer that ShowRaidBuffHUD starts
        if raidBuffHideTimer then raidBuffHideTimer:Cancel(); raidBuffHideTimer = nil end

        local ox, oy = FrameCenterOffset(raidBuffHUD)
        table.insert(handles, {
            label        = "Raid Buff Reminder",
            iconTex      = "Interface\\Icons\\Spell_Holy_PrayerOfFortitude",
            ox           = ox, oy = oy,
            liveFrameRef = raidBuffHUD,
            saveCallback = function(nx, ny)
                local nbx = nx + sw/2 - raidBuffHUD:GetWidth()/2
                local nby = ny + sh/2 + raidBuffHUD:GetHeight()/2
                raidBuffHUD:ClearAllPoints()
                raidBuffHUD:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", nbx, nby)
                if BuffAlertDB then BuffAlertDB.raidBuffHUDX = nbx; BuffAlertDB.raidBuffHUDY = nby end
            end,
        })
    end

    return handles
end)

API.Debug("[MidnightQoL] Utility module loaded.")
