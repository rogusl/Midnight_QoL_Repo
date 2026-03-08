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
    -- C_UnitAuras.GetBuffDataByIndex replaces the removed UnitBuff API (TWW 11.0+)
    local i = 1
    while true do
        local aura = C_UnitAuras.GetBuffDataByIndex("player", i)
        if not aura then break end
        if aura.spellId and POISON_IDS[aura.spellId] then found[aura.spellId] = true end
        i = i + 1
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
            local found = false
            local i = 1
            while true do
                local aura = C_UnitAuras.GetBuffDataByIndex("player", i)
                if not aura then break end
                if aura.spellId == buffDef.spellId then found = true; break end
                i = i + 1
            end
            if not found then missing[#missing+1] = buffDef end
        end
    end

    ShowRaidBuffHUD(missing)
end

-- ============================================================
-- BATTLE REZ TRACKER
-- Shows charges available and time until next charge.
-- Tracks: Rebirth (20484), Soulstone (20707), Raise Ally (61999),
--         Reincarnation (21169 — self only, different mechanic, skip),
--         Eternal Guardian (196718 — DK talent)
-- ============================================================
-- Spell IDs that constitute a combat rez, keyed by class for display label.
-- 20484  = Rebirth        (Druid)
-- 20707  = Soulstone Res  (Warlock)
-- 61999  = Raise Ally     (Death Knight)
-- 265116 = Reawaken       (Evoker — added in Dragonflight)
local BREZ_SPELL_INFO = {
    [20484]  = "Rebirth",
    [20707]  = "Soulstone",
    [61999]  = "Raise Ally",
    [265116] = "Reawaken",
}


-- Scan group for combat rez availability via LibOpenRaid + local spellbook.
local function GetRaidBrezStatus()
    local bestCharges = 0
    local bestMax     = 1
    local soonestCD   = math.huge

    local prefix = IsInRaid() and "raid" or "party"
    local count  = IsInRaid() and GetNumGroupMembers() or GetNumSubgroupMembers()
    local units  = {"player"}
    for i = 1, count do units[#units+1] = prefix..i end

    local lib = GetOpenRaidLib()

    for _, unit in ipairs(units) do
        if UnitExists(unit) then
            if UnitIsUnit(unit, "player") then
                for spellId in pairs(BREZ_SPELL_INFO) do
                    if IsSpellKnown(spellId) then
                        local ci = C_Spell.GetSpellCharges and C_Spell.GetSpellCharges(spellId)
                        if ci then
                            local ch  = ci.currentCharges or 0
                            local mx  = ci.maxCharges or 1
                            local rem = 0
                            if ch < mx and ci.cooldownStartTime and ci.cooldownDuration then
                                rem = math.max(0, (ci.cooldownStartTime + ci.cooldownDuration) - GetTime())
                            end
                            if ch > bestCharges then bestCharges = ch; bestMax = mx end
                            if rem > 0 and rem < soonestCD then soonestCD = rem end
                        end
                    end
                end
            elseif lib then
                for spellId in pairs(BREZ_SPELL_INFO) do
                    local cooldownInfo = lib.GetUnitCooldownInfo(unit, spellId)
                    if cooldownInfo then
                        local isReady, _, timeLeft, charges = lib.GetCooldownStatusFromCooldownInfo(cooldownInfo)
                        local ch  = charges or (isReady and 1 or 0)
                        local rem = (not isReady and timeLeft) and math.max(0, timeLeft) or 0
                        if ch > bestCharges then bestCharges = ch; bestMax = 1 end
                        if rem > 0 and rem < soonestCD then soonestCD = rem end
                    end
                end
            end
        end
    end

    -- Nobody in the group has a brez spell at all
    if bestCharges == 0 and soonestCD == math.huge then
        return nil, nil, nil
    end
    local remaining = (soonestCD < math.huge) and soonestCD or 0
    return bestCharges, bestMax, remaining
end

-- ── Battle Rez tracker ───────────────────────────────────────────────────────
-- Icon + stack counter + timer until next charge.
-- Spell 26994 = Blizzard shared combat rez charge pool (most reliable source).
-- Fallback: scan group via LibOpenRaid / local spellbook.

-- Icon texture: use the Rebirth spell icon (spell ID 20484) as the generic brez icon.
local BREZ_ICON = 136080  -- Interface/Icons/Spell_Nature_Reincarnation

local brezFrame = CreateFrame("Frame", "MidnightQoLBrezFrame", UIParent)
brezFrame:SetSize(52, 66)
brezFrame:SetPoint("CENTER", UIParent, "CENTER", 0, -160)
brezFrame:SetFrameStrata("MEDIUM")
brezFrame:SetMovable(true)
brezFrame:EnableMouse(true)
brezFrame:RegisterForDrag("LeftButton")
brezFrame:SetScript("OnDragStart", function(self)
    if (API.IsLayoutMode and API.IsLayoutMode()) and not InCombatLockdown() then self:StartMoving() end
end)
brezFrame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    if BuffAlertDB then BuffAlertDB.brezX = self:GetLeft(); BuffAlertDB.brezY = self:GetTop() end
end)
brezFrame:Hide()

-- Icon background (dark square)
local brezBg = brezFrame:CreateTexture(nil, "BACKGROUND")
brezBg:SetAllPoints()
brezBg:SetColorTexture(0, 0, 0, 0.6)

-- Brez spell icon
local brezIcon = brezFrame:CreateTexture(nil, "ARTWORK")
brezIcon:SetPoint("TOPLEFT", brezFrame, "TOPLEFT", 2, -2)
brezIcon:SetSize(48, 48)
brezIcon:SetTexture(BREZ_ICON)
brezIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)  -- trim bliz icon border

-- Stack counter (top-right corner of icon)
local brezCount = brezFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
brezCount:SetPoint("BOTTOMRIGHT", brezIcon, "BOTTOMRIGHT", 2, 2)
brezCount:SetTextColor(1, 1, 1)
brezCount:SetShadowColor(0, 0, 0, 1)
brezCount:SetShadowOffset(1, -1)

-- Timer text (below icon)
local brezTimer = brezFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
brezTimer:SetPoint("BOTTOM", brezFrame, "BOTTOM", 0, 2)
brezTimer:SetPoint("LEFT", brezFrame, "LEFT", 0, 0)
brezTimer:SetPoint("RIGHT", brezFrame, "RIGHT", 0, 0)
brezTimer:SetJustifyH("CENTER")
brezTimer:SetTextColor(0.8, 0.8, 0.8)

-- Thin border
local brezBorder = CreateFrame("Frame", nil, brezFrame, "BackdropTemplate")
brezBorder:SetAllPoints()
brezBorder:SetBackdrop({ edgeFile = "Interface/Buttons/WHITE8x8", edgeSize = 1 })
brezBorder:SetBackdropBorderColor(0.25, 0.25, 0.25, 0.9)

local brezTicker = nil

local function UpdateBrezFrame()
    local db = GetDB()
    if not db.battlerezEnabled then
        brezFrame:Hide(); return
    end
    if not IsInGroup() and not UnitAffectingCombat("player") then
        brezFrame:Hide(); return
    end

    -- Try the Blizzard shared combat rez pool first (spell 26994)
    local charges, maxCharges, remaining
    local sharedCI = C_Spell.GetSpellCharges and C_Spell.GetSpellCharges(26994)
    if sharedCI and sharedCI.maxCharges and sharedCI.maxCharges > 0 then
        charges    = sharedCI.currentCharges or 0
        maxCharges = sharedCI.maxCharges
        remaining  = 0
        if charges < maxCharges and sharedCI.cooldownStartTime and sharedCI.cooldownDuration then
            remaining = math.max(0, (sharedCI.cooldownStartTime + sharedCI.cooldownDuration) - GetTime())
        end
    else
        -- Fallback: scan group via LibOpenRaid / local spellbook
        local c, mx, rem = GetRaidBrezStatus()
        charges    = c
        maxCharges = mx
        remaining  = rem
    end

    -- Hide if nobody in the group has a brez spell
    if not charges and not maxCharges then
        brezFrame:Hide(); return
    end

    -- Restore saved position
    if BuffAlertDB and BuffAlertDB.brezX and BuffAlertDB.brezY then
        brezFrame:ClearAllPoints()
        brezFrame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", BuffAlertDB.brezX, BuffAlertDB.brezY)
    end

    brezFrame:Show()

    -- Stack counter: dim icon when 0 charges
    charges    = charges    or 0
    maxCharges = maxCharges or 1
    remaining  = remaining  or 0

    if charges == 0 then
        brezIcon:SetVertexColor(0.4, 0.4, 0.4)
        brezCount:SetTextColor(1, 0.3, 0.3)
    else
        brezIcon:SetVertexColor(1, 1, 1)
        brezCount:SetTextColor(1, 1, 0)
    end
    brezCount:SetText(charges .. "/" .. maxCharges)

    -- Timer: show countdown to next charge, hide if full
    if remaining > 0 and charges < maxCharges then
        local mins = math.floor(remaining / 60)
        local secs = math.floor(remaining % 60)
        if mins > 0 then
            brezTimer:SetText(string.format("%d:%02d", mins, secs))
        else
            -- Pulse red when under 30s
            if secs <= 30 then
                brezTimer:SetTextColor(1, 0.4, 0.4)
            else
                brezTimer:SetTextColor(0.8, 0.8, 0.8)
            end
            brezTimer:SetText(secs .. "s")
        end
        brezTimer:Show()
    else
        brezTimer:SetText("")
        brezTimer:Hide()
    end
end

-- ── Events ────────────────────────────────────────────────────────────────────
local utilEvents = CreateFrame("Frame")
utilEvents:RegisterEvent("PLAYER_LOGIN")
utilEvents:RegisterEvent("PLAYER_REGEN_DISABLED")  -- combat enter → poison check
utilEvents:RegisterEvent("READY_CHECK")
utilEvents:RegisterEvent("SPELL_UPDATE_COOLDOWN")
utilEvents:RegisterEvent("SPELL_UPDATE_CHARGES")
utilEvents:RegisterEvent("PLAYER_ENTERING_WORLD")
utilEvents:RegisterEvent("GROUP_ROSTER_UPDATE")
utilEvents:RegisterEvent("UNIT_AURA")

local raidBuffTicker = nil

utilEvents:SetScript("OnEvent", function(self, event, unit, ...)
    local db = GetDB()
    if event == "PLAYER_LOGIN" then
        C_Timer.After(2, function()
            UpdateBrezFrame()
            brezTicker     = C_Timer.NewTicker(1,  UpdateBrezFrame)
            raidBuffTicker = C_Timer.NewTicker(5,  CheckRaidBuffs)

            -- Register LibOpenRaid callbacks now that LibStub is fully initialised.
            local lib = GetOpenRaidLib()
            if lib then
                -- When any unit in the group uses or refreshes a brez cooldown,
                -- immediately update the tracker rather than waiting for the 1s ticker.
                local MidnightQoLBrezCallbacks = {}
                function MidnightQoLBrezCallbacks.OnCooldownUpdate(unitId, spellId)
                    if BREZ_SPELL_INFO[spellId] then
                        UpdateBrezFrame()
                    end
                end
                function MidnightQoLBrezCallbacks.OnCooldownListUpdate()
                    UpdateBrezFrame()
                end
                -- Unit death/rez affects brez charge availability display.
                function MidnightQoLBrezCallbacks.OnUnitDeath()
                    UpdateBrezFrame()
                end
                function MidnightQoLBrezCallbacks.OnUnitAlive()
                    UpdateBrezFrame()
                end
                -- When unit info arrives (spec/class), re-run the buff check so we
                -- catch classes that joined late or whose token was nil at roster update.
                function MidnightQoLBrezCallbacks.OnUnitInfoUpdate()
                    CheckRaidBuffs()
                end

                lib.RegisterCallback(MidnightQoLBrezCallbacks, "CooldownUpdate",    "OnCooldownUpdate")
                lib.RegisterCallback(MidnightQoLBrezCallbacks, "CooldownListUpdate","OnCooldownListUpdate")
                lib.RegisterCallback(MidnightQoLBrezCallbacks, "UnitDeath",         "OnUnitDeath")
                lib.RegisterCallback(MidnightQoLBrezCallbacks, "UnitAlive",         "OnUnitAlive")
                lib.RegisterCallback(MidnightQoLBrezCallbacks, "UnitInfoUpdate",    "OnUnitInfoUpdate")

                -- Ask the group to broadcast their current data so we're not waiting
                -- for the next natural update cycle.
                lib.RequestAllData()
            end
        end)
    elseif event == "PLAYER_REGEN_DISABLED" then
        C_Timer.After(0.5, CheckRoguePoisons)
    elseif event == "READY_CHECK" then
        C_Timer.After(0.3, CheckRaidBuffs)
    elseif event == "SPELL_UPDATE_COOLDOWN" or event == "SPELL_UPDATE_CHARGES" or event == "PLAYER_ENTERING_WORLD" or event == "GROUP_ROSTER_UPDATE" then
        UpdateBrezFrame()
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
        brezText:SetText("|cFF00FF00Rebirth|r  2/2")

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
