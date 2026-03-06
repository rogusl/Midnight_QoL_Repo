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
    -- Poisons show as buffs on the player with keywords
    local i = 1
    while true do
        local name, _, _, _, _, _, _, _, _, spellId = UnitBuff("player", i)
        if not name then break end
        if spellId and POISON_IDS[spellId] then found[spellId] = true end
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
raidBuffHUD:SetScript("OnDragStart", function(self) self:StartMoving() end)
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

    raidBuffHUD:Show()
    -- Auto-hide after 10 seconds
    raidBuffHideTimer = C_Timer.NewTimer(10, function()
        raidBuffHideTimer = nil
        UIFrameFadeOut(raidBuffHUD, 0.5, 1, 0)
        C_Timer.After(0.5, function() raidBuffHUD:Hide(); raidBuffHUD:SetAlpha(1) end)
    end)
end

local function CheckRaidBuffs()
    local db = GetDB()
    if not db.raidbuffCheckEnabled then return end
    if not IsInGroup() then return end

    local classesPresent = {}
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
                local name, _, _, _, _, _, _, _, _, spellId = UnitBuff("player", i)
                if not name then break end
                if spellId == buffDef.spellId then found = true; break end
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
local BREZ_SPELLS = { 20484, 20707, 61999, 196718 }

local brezFrame = CreateFrame("Frame", "MidnightQoLBrezFrame", UIParent, "BackdropTemplate")
brezFrame:SetSize(200, 28)
brezFrame:SetPoint("CENTER", UIParent, "CENTER", 0, -160)
brezFrame:SetFrameStrata("MEDIUM")
brezFrame:SetMovable(true)
brezFrame:EnableMouse(true)
brezFrame:RegisterForDrag("LeftButton")
brezFrame:SetScript("OnDragStart", function(self) if not InCombatLockdown() then self:StartMoving() end end)
brezFrame:SetScript("OnDragStop",  function(self) self:StopMovingOrSizing()
    if BuffAlertDB then BuffAlertDB.brezX = self:GetLeft(); BuffAlertDB.brezY = self:GetTop() end
end)
brezFrame:SetBackdrop({ bgFile = "Interface/Buttons/WHITE8x8",
    edgeFile = "Interface/DialogFrame/UI-DialogBox-Border", edgeSize = 10,
    insets = { left=3, right=3, top=3, bottom=3 } })
brezFrame:SetBackdropColor(0, 0, 0, 0.75)
brezFrame:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.8)
brezFrame:Hide()

local brezText = brezFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
brezText:SetPoint("CENTER", brezFrame, "CENTER", 0, 0)
brezText:SetText("")

local function GetBrezStatus()
    for _, spellId in ipairs(BREZ_SPELLS) do
        -- Check if any group member has this spell known (not just player)
        -- We check the cooldown for all raid members who could have it
        local cdInfo = C_Spell.GetSpellCooldown and C_Spell.GetSpellCooldown(spellId)
        if cdInfo then
            local charges, maxCharges = C_Spell.GetSpellCharges and C_Spell.GetSpellCharges(spellId) or 0, 1
            if charges then
                return charges, maxCharges, cdInfo.startTime and (cdInfo.startTime + cdInfo.duration - GetTime()) or 0
            end
        end
    end
    return 0, 1, 0
end

local brezTicker = nil

local function UpdateBrezFrame()
    local db = GetDB()
    if not db.battlerezEnabled or not IsInGroup() then
        brezFrame:Hide(); return
    end

    -- Find which brez spell the player has
    local mySpellId = nil
    for _, sid in ipairs(BREZ_SPELLS) do
        if IsSpellKnown(sid) then mySpellId = sid; break end
    end

    if not mySpellId then brezFrame:Hide(); return end

    local chargeInfo = C_Spell.GetSpellCharges and C_Spell.GetSpellCharges(mySpellId)
    if not chargeInfo then brezFrame:Hide(); return end

    local charges    = chargeInfo.currentCharges or 0
    local maxCharges = chargeInfo.maxCharges or 1
    local remaining  = 0
    if charges < maxCharges and chargeInfo.cooldownStartTime and chargeInfo.cooldownDuration then
        remaining = (chargeInfo.cooldownStartTime + chargeInfo.cooldownDuration) - GetTime()
    end

    brezFrame:Show()
    local spellName = C_Spell.GetSpellName and C_Spell.GetSpellName(mySpellId) or "Battle Rez"
    local chargeStr = "|cFFFFD700" .. charges .. "/" .. maxCharges .. "|r"
    if remaining > 0 and charges < maxCharges then
        local mins = math.floor(remaining / 60)
        local secs = math.floor(remaining % 60)
        local timeStr = mins > 0 and string.format("%dm%ds", mins, secs) or string.format("%ds", secs)
        brezText:SetText(spellName .. "  " .. chargeStr .. "  |cFFAAAAAA" .. timeStr .. "|r")
    else
        brezText:SetText(spellName .. "  " .. chargeStr)
    end

    -- Restore saved position
    if BuffAlertDB and BuffAlertDB.brezX and BuffAlertDB.brezY then
        brezFrame:ClearAllPoints()
        brezFrame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", BuffAlertDB.brezX, BuffAlertDB.brezY)
    end
end

-- ── Events ────────────────────────────────────────────────────────────────────
local utilEvents = CreateFrame("Frame")
utilEvents:RegisterEvent("PLAYER_LOGIN")
utilEvents:RegisterEvent("PLAYER_REGEN_DISABLED")  -- combat enter → poison check
utilEvents:RegisterEvent("READY_CHECK")
utilEvents:RegisterEvent("SPELL_UPDATE_COOLDOWN")
utilEvents:RegisterEvent("PLAYER_ENTERING_WORLD")
utilEvents:RegisterEvent("GROUP_ROSTER_UPDATE")

utilEvents:SetScript("OnEvent", function(self, event, unit, ...)
    local db = GetDB()
    if event == "PLAYER_LOGIN" then
        C_Timer.After(2, function()
            UpdateBrezFrame()
            brezTicker = C_Timer.NewTicker(1, UpdateBrezFrame)
        end)
    elseif event == "PLAYER_REGEN_DISABLED" then
        C_Timer.After(0.5, CheckRoguePoisons)
    elseif event == "READY_CHECK" then
        C_Timer.After(0.3, CheckRaidBuffs)
    elseif event == "SPELL_UPDATE_COOLDOWN" or event == "PLAYER_ENTERING_WORLD" or event == "GROUP_ROSTER_UPDATE" then
        UpdateBrezFrame()
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
