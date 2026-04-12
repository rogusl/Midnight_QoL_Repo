-- ============================================================
-- RogUI / Modules / QoL / QoL.lua
-- MIGRATED: Unified event system
-- Pet reminder overlay for Hunters and Warlocks.
-- ============================================================

local API = RogUIAPI

local PET_CLASSES = { HUNTER = true, WARLOCK = true }

-- Abilities are based on the pet's family/spec role.
-- Warlock: Command Demon ability (what the player presses) + passive utility.
-- Hunter:  what the pet's family brings to the group.
local PET_ABILITIES = {
    -- ── Warlock demons ────────────────────────────────────────────────────
    ["Imp"]        = { interrupt="Cauterize Master — Command Demon",
                       defensive="Singe Magic — dispel magic debuff from ally" },
    ["Voidwalker"] = { defensive="Shadow Bulwark — Command Demon absorb shield" },
    ["Felhunter"]  = { interrupt="Spell Lock — Command Demon silence/interrupt",
                       cleanse="Devour Magic — dispel magic" },
    ["Succubus"]   = { cc="Seduction — Command Demon charm (humanoids)" },
    ["Felguard"]   = { interrupt="Axe Toss — Command Demon stun" },
    ["Wrathguard"] = { interrupt="Mortal Cleave — Command Demon" },
    ["Observer"]   = { interrupt="Optical Blast — Command Demon silence" },
    ["Infernal"]   = { cc="Meteor Strike — stun" },
    ["Doomguard"]  = { interrupt="Doom Bolt — Command Demon" },
    ["Darkglare"]  = { cc="Eye Sore — damage + DoT" },
    -- ── Hunter pets — keyed by spec role ──────────────────────────────────
    ["Ferocity"] = { defensive="Primal Rage — Heroism/Bloodlust (2 min cd)" },
    ["Tenacity"] = { defensive="Survival of the Fittest — 20% DR cooldown" },
    ["Cunning"]  = { defensive="Master's Call — removes roots/snares on you and pet" },
}

-- Maps GetPetSpecialization() spec IDs to the keys in PET_ABILITIES above.
-- These IDs are stable: 253 = Ferocity, 254 = Tenacity, 255 = Cunning.
local HUNTER_PET_SPEC_ID_TO_NAME = { [253]="Ferocity", [254]="Tenacity", [255]="Cunning" }

local PET_ROLE_FALLBACK = {
    HUNTER  = { defensive="Unknown spec — open pet talents to assign Ferocity/Tenacity/Cunning" },
    WARLOCK = { interrupt="Command Demon varies by active pet" },
}

local function GetPetSpecName()
    if not UnitExists("pet") then return nil end

    -- TWW+: GetSpecialization(false, true) returns the pet's spec index (1/2/3).
    -- GetSpecializationInfo(index, false, true) returns the spec name.
    if GetSpecialization then
        local petSpecIndex = GetSpecialization(false, true)
        if petSpecIndex and petSpecIndex > 0 then
            local _, specName = GetSpecializationInfo(petSpecIndex, false, true)
            if specName then
                for _, k in ipairs({"Ferocity", "Tenacity", "Cunning"}) do
                    if specName:find(k) then return k end
                end
            end
        end
    end

    -- Legacy fallback: GetPetSpecialization() (returns 253/254/255 in older API)
    if GetPetSpecialization then
        local specID = GetPetSpecialization()
        local name = specID and HUNTER_PET_SPEC_ID_TO_NAME[specID]
        if name then return name end
    end

    return nil
end

local function IsPetSpecPending()
    -- Truly pending only if the spec index API returns nil (not yet loaded).
    -- Index 0 or no spec set is a valid resolved state — don't block on it.
    if API.playerClass ~= "HUNTER" then return false end
    if not UnitExists("pet") then return false end
    if GetSpecialization then
        return GetSpecialization(false, true) == nil
    end
    if GetPetSpecialization then
        return GetPetSpecialization() == nil
    end
    return false
end

-- /midpetdebug — paste output here if the spec still shows wrong
SLASH_MIDPETDEBUG1 = "/midpetdebug"
SlashCmdList["MIDPETDEBUG"] = function()
    print("|cFF00CCFF[RogUI Pet Debug]|r")
    print("  UnitExists(pet): "..tostring(UnitExists("pet")))
    print("  UnitCreatureFamily(pet): "..tostring(UnitCreatureFamily and UnitCreatureFamily("pet")))
    local petIdx = GetSpecialization and GetSpecialization(false, true)
    print("  GetSpecialization(false,true): "..tostring(petIdx))
    if petIdx and petIdx > 0 then
        local _, sn = GetSpecializationInfo(petIdx, false, true)
        print("  GetSpecializationInfo name: "..tostring(sn))
    end
    print("  GetPetSpecialization(): "..tostring(GetPetSpecialization and GetPetSpecialization()))
    print("  GetPetSpecName(): "..tostring(GetPetSpecName()))
    print("  IsPetSpecPending(): "..tostring(IsPetSpecPending()))
end

local function GetPetAbilitySummary()
    local data
    if API.playerClass == "HUNTER" then
        local specName = GetPetSpecName()
        if IsPetSpecPending() then return nil end  -- genuinely not loaded yet
        -- specName may be nil if pet has no spec (specID==0) — use fallback
        data = specName and PET_ABILITIES[specName] or PET_ROLE_FALLBACK["HUNTER"]
    else
        local family = UnitCreatureFamily and UnitCreatureFamily("pet")
        data = family and PET_ABILITIES[family] or PET_ROLE_FALLBACK[API.playerClass]
    end
    if not data then return nil end
    local parts = {}
    if data.interrupt then table.insert(parts, "|cFFFF6060[INTERRUPT]|r "..data.interrupt) end
    if data.cleanse   then table.insert(parts, "|cFF60FF60[DISPEL]|r "   ..data.cleanse)   end
    if data.defensive then table.insert(parts, "|cFF6699FF[UTILITY]|r "  ..data.defensive) end
    if data.cc        then table.insert(parts, "|cFFFFFF60[CC]|r "        ..data.cc)        end
    return #parts > 0 and table.concat(parts,"\n") or nil
end

-- ── Pet reminder frame ─────────────────────────────────────────────────────────
local petReminderFrame = CreateFrame("Frame","RogUIPetReminder",UIParent)
petReminderFrame:SetSize(420,96); petReminderFrame:SetPoint("CENTER",UIParent,"CENTER",0,80)
petReminderFrame:SetFrameStrata("HIGH"); petReminderFrame:SetMovable(true); petReminderFrame:EnableMouse(true)
petReminderFrame:RegisterForDrag("LeftButton"); petReminderFrame:SetClampedToScreen(true)
petReminderFrame:SetScript("OnDragStart",function(self) if API.IsLayoutMode and API.IsLayoutMode() then self:StartMoving() end end)
petReminderFrame:SetScript("OnDragStop",function(self)
    self:StopMovingOrSizing()
    if RogUIDB then
        local cx=UIParent:GetWidth()/2; local cy=UIParent:GetHeight()/2
        local fx=self:GetLeft()+self:GetWidth()/2; local fy=self:GetBottom()+self:GetHeight()/2
        RogUIDB.petReminderX=math.floor(fx-cx+0.5); RogUIDB.petReminderY=math.floor(fy-cy+0.5)
    end
end)
petReminderFrame:Hide()

local petReminderBG = petReminderFrame:CreateTexture(nil,"BACKGROUND")
petReminderBG:SetAllPoints(); petReminderBG:SetColorTexture(0,0,0,0.78)

local petReminderAccent = petReminderFrame:CreateTexture(nil,"BORDER")
petReminderAccent:SetSize(4,96); petReminderAccent:SetPoint("LEFT",petReminderFrame,"LEFT",0,0)
petReminderAccent:SetColorTexture(1,0.4,0,1)

local petReminderIcon = petReminderFrame:CreateTexture(nil,"ARTWORK")
petReminderIcon:SetSize(64,64); petReminderIcon:SetPoint("LEFT",petReminderFrame,"LEFT",14,0)
petReminderIcon:SetTexCoord(0.08,0.92,0.08,0.92)

local petReminderText = petReminderFrame:CreateFontString(nil,"OVERLAY","GameFontNormalLarge")
petReminderText:SetPoint("TOPLEFT",petReminderIcon,"TOPRIGHT",10,-4)
petReminderText:SetPoint("RIGHT",petReminderFrame,"RIGHT",-10,0)
petReminderText:SetJustifyH("LEFT"); petReminderText:SetTextColor(1,0.4,0,1)
petReminderText:SetText("Summon your pet!")

local petReminderSub = petReminderFrame:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
petReminderSub:SetPoint("TOPLEFT",petReminderText,"BOTTOMLEFT",0,-4)
petReminderSub:SetPoint("RIGHT",petReminderFrame,"RIGHT",-10,0)
petReminderSub:SetJustifyH("LEFT"); petReminderSub:SetTextColor(0.85,0.85,0.85,1); petReminderSub:SetText("")

-- Icon paths — using named Interface/Icons paths avoids numeric ID collisions
local FAMILY_ICONS = {
    -- Warlock demons (each has its own summon spell icon)
    ["Imp"]          = "Interface\\Icons\\Spell_Shadow_SummonImp",
    ["Voidwalker"]   = "Interface\\Icons\\Spell_Shadow_SummonVoidWalker",
    ["Felhunter"]    = "Interface\\Icons\\Spell_Shadow_SummonFelHunter",
    ["Succubus"]     = "Interface\\Icons\\Spell_Shadow_SummonSuccubus",
    ["Felguard"]     = "Interface\\Icons\\Ability_Warlock_SummonFelguard",
    ["Wrathguard"]   = "Interface\\Icons\\Ability_Warlock_SummonFelguard",
    ["Observer"]     = "Interface\\Icons\\Ability_Warlock_SummonObserver",
    ["Infernal"]     = "Interface\\Icons\\Spell_Shadow_SummonInfernal",
    ["Doomguard"]    = "Interface\\Icons\\Spell_Shadow_SummonDoomguard",
    ["Darkglare"]    = "Interface\\Icons\\Ability_Warlock_SummonDarkglare",
    -- Hunter pets
    ["Cat"]          = "Interface\\Icons\\Ability_Hunter_Pet_Cat",
    ["Lynx"]         = "Interface\\Icons\\Ability_Hunter_Pet_Cat",
    ["Cheetah"]      = "Interface\\Icons\\Ability_Hunter_Pet_Cat",
    ["Bear"]         = "Interface\\Icons\\Ability_Hunter_Pet_Bear",
    ["Boar"]         = "Interface\\Icons\\Ability_Hunter_Pet_Boar",
    ["Gorilla"]      = "Interface\\Icons\\Ability_Hunter_Pet_Gorilla",
    ["Turtle"]       = "Interface\\Icons\\Ability_Hunter_Pet_Turtle",
    ["Bat"]          = "Interface\\Icons\\Ability_Hunter_Pet_Bat",
    ["Owl"]          = "Interface\\Icons\\Ability_Hunter_Pet_Owl",
    ["Crab"]         = "Interface\\Icons\\Ability_Hunter_Pet_Crab",
    ["Ravager"]      = "Interface\\Icons\\Ability_Hunter_Pet_Ravager",
    ["Raptor"]       = "Interface\\Icons\\Ability_Hunter_Pet_Raptor",
    ["Scorpid"]      = "Interface\\Icons\\Ability_Hunter_Pet_Scorpid",
    ["Spider"]       = "Interface\\Icons\\Ability_Hunter_Pet_Spider",
    ["Wind Serpent"] = "Interface\\Icons\\Ability_Hunter_Pet_WindSerpent",
    ["Spirit Beast"] = "Interface\\Icons\\Ability_Hunter_Pet_SpiritBeast",
    ["Devilsaur"]    = "Interface\\Icons\\Ability_Hunter_Pet_Devilsaur",
    ["Core Hound"]   = "Interface\\Icons\\Ability_Hunter_Pet_CoreHound",
    ["Silithid"]     = "Interface\\Icons\\Ability_Hunter_Pet_Silithid",
    ["Hyena"]        = "Interface\\Icons\\Ability_Hunter_Pet_Hyena",
    ["Warp Stalker"] = "Interface\\Icons\\Ability_Hunter_Pet_WarpStalker",
    ["Tallstrider"]  = "Interface\\Icons\\Ability_Hunter_Pet_Tallstrider",
    ["Rhino"]        = "Interface\\Icons\\Ability_Hunter_Pet_Rhino",
    ["Mammoth"]      = "Interface\\Icons\\Ability_Hunter_Pet_Mammoth",
    ["Dragonhawk"]   = "Interface\\Icons\\Ability_Hunter_Pet_Dragonhawk",
    ["Nether Ray"]   = "Interface\\Icons\\Ability_Hunter_Pet_NetherRay",
    ["Sporebat"]     = "Interface\\Icons\\Ability_Hunter_Pet_Sporebat",
    ["Wasp"]         = "Interface\\Icons\\Ability_Hunter_Pet_Wasp",
    ["Wolf"]         = "Interface\\Icons\\Ability_Hunter_Pet_Wolf",
    ["Serpent"]      = "Interface\\Icons\\Ability_Hunter_Pet_Serpent",
    ["Quilen"]       = "Interface\\Icons\\Ability_Hunter_Pet_Quilen",
    ["Chimaera"]     = "Interface\\Icons\\Ability_Hunter_Pet_Chimaera",
    ["Water Strider"]= "Interface\\Icons\\Ability_Hunter_Pet_WaterStrider",
    ["Clefthoof"]    = "Interface\\Icons\\Ability_Hunter_Pet_Clefthoof",
    ["Worm"]         = "Interface\\Icons\\Ability_Hunter_Pet_Worm",
    ["Carrion Bird"] = "Interface\\Icons\\Ability_Hunter_Pet_CarrionBird",
}

local function ShowPetReminderOverlay(playSound)
    if not (RogUIDB and RogUIDB.petReminderEnabled) then return end
    if not PET_CLASSES[API.playerClass] then return end

    local db = RogUIDB or {}
    local hasPet = UnitExists("pet")

    if petReminderFrame.hideTimer then
        petReminderFrame.hideTimer:Cancel(); petReminderFrame.hideTimer=nil
    end

    local r=db.petReminderR or 1; local g=db.petReminderG or 0.4; local b=db.petReminderB or 0
    local sz=db.petReminderSize or 18
    petReminderText:SetFont(petReminderText:GetFont(), sz, "OUTLINE")
    petReminderSub:SetFont(petReminderSub:GetFont(), math.max(10,sz-4), "OUTLINE")

    petReminderFrame:ClearAllPoints()
    petReminderFrame:SetPoint("CENTER",UIParent,"CENTER", db.petReminderX or 0, db.petReminderY or 80)

    if hasPet then
        petReminderAccent:SetColorTexture(0.2,0.8,0.2,1)
        petReminderText:SetTextColor(0.3,1,0.3,1)
        local family = UnitCreatureFamily and UnitCreatureFamily("pet") or ""
        local petName = UnitName("pet") or "Your Pet"
        -- For hunters show the spec (Ferocity/Tenacity/Cunning) since that
        -- determines the actual ability, not the family name.
        local displayTag
        if API.playerClass == "HUNTER" then
            local specName = GetPetSpecName()
            displayTag = specName and ("|cFFFFD700"..specName.."|r") or (family ~= "" and ("|cFFAAAAAA("..family..")|r") or nil)
        else
            displayTag = family ~= "" and ("|cFFAAAAAA("..family..")|r") or nil
        end
        petReminderText:SetText(petName..(displayTag and ("  "..displayTag) or ""))
        local petIconPath = FAMILY_ICONS[family] or (API.playerClass=="HUNTER" and "Interface\\Icons\\Ability_Hunter_BeastCall" or "Interface\\Icons\\Spell_Shadow_SummonImp")
        petReminderIcon:SetTexture(petIconPath)
        petReminderSub:SetText(GetPetAbilitySummary() or "|cFFAAAAAA(No ability data for this family)|r")
    else
        petReminderAccent:SetColorTexture(r,g,b,1)
        petReminderText:SetTextColor(r,g,b,1)
        petReminderIcon:SetTexture(API.playerClass=="HUNTER" and "Interface\\Icons\\Ability_Hunter_BeastCall" or "Interface\\Icons\\Spell_Shadow_SummonImp")
        petReminderText:SetText("Summon your pet!")
        petReminderSub:SetText("|cFFFF4444No pet active — abilities unavailable!|r")
        if playSound then
            if db.petReminderSound then
                API.PlayCustomSound(db.petReminderSound, db.petReminderSoundIsID)
            else PlaySound(SOUNDKIT.RAID_WARNING or 8959) end
            print("|cFFFF6600[RogUI]|r Don't forget to summon your pet!")
        end
    end

    petReminderFrame:SetAlpha(0); petReminderFrame:Show()
    UIFrameFadeIn(petReminderFrame,0.4,0,1)
    petReminderFrame.hideTimer = C_Timer.NewTimer(20,function()
        UIFrameFadeOut(petReminderFrame,1.0,1,0)
        C_Timer.After(1.1,function() if petReminderFrame:GetAlpha()<0.05 then petReminderFrame:Hide() end end)
        petReminderFrame.hideTimer=nil
    end)
end

local function CheckPetReminder(reason)
    if not (RogUIDB and RogUIDB.petReminderEnabled) then return end
    if not PET_CLASSES[API.playerClass] then return end
    -- Don't fire while mounted or flying — pet is dismissed by design
    if IsMounted() then return end
    -- If the pet exists but spec hasn't been populated yet, stay silent —
    -- PET_SPECIALIZATION_CHANGED will fire once the data is ready.
    if IsPetSpecPending() then return end
    ShowPetReminderOverlay(not UnitExists("pet"))
end
API.CheckPetReminder = CheckPetReminder

-- ── In-combat pet nag: repeat sound every 10s until pet is summoned ────────────
local petNagTimer = nil

local function StopPetNag()
    if petNagTimer then petNagTimer:Cancel(); petNagTimer = nil end
end

local function StartPetNag()
    StopPetNag()
    if not (RogUIDB and RogUIDB.petReminderEnabled) then return end
    if not PET_CLASSES[API.playerClass] then return end
    if IsMounted() then return end
    if UnitExists("pet") then return end
    local function nag()
        -- Stop if we left combat, pet appeared, or feature was disabled
        if not InCombatLockdown() or UnitExists("pet") or IsMounted()
            or not (RogUIDB and RogUIDB.petReminderEnabled) then
            StopPetNag(); return
        end
        -- Re-read DB each tick so sound changes take effect immediately
        local db = RogUIDB
        if db.petReminderSound then
            API.PlayCustomSound(db.petReminderSound, db.petReminderSoundIsID)
        else PlaySound(SOUNDKIT.RAID_WARNING or 8959) end
        -- Also nudge the overlay so it stays visible / resets its hide timer
        ShowPetReminderOverlay(false)
        petNagTimer = C_Timer.NewTimer(10, nag)
    end
    petNagTimer = C_Timer.NewTimer(10, nag)
end

-- ── Layout handle provider ─────────────────────────────────────────────────────
API.RegisterLayoutHandles(function()
    local ox = (RogUIDB and RogUIDB.petReminderX) or 0
    local oy = (RogUIDB and RogUIDB.petReminderY) or 80
    return {{
        label        = "Pet Reminder",
        iconTex      = "Interface\\Icons\\Ability_Hunter_BeastCall",
        ox           = ox, oy = oy,
        liveFrameRef = petReminderFrame,
        saveCallback = function(nx,ny)
            if RogUIDB then RogUIDB.petReminderX=nx; RogUIDB.petReminderY=ny end
            petReminderFrame:ClearAllPoints(); petReminderFrame:SetPoint("CENTER",UIParent,"CENTER",nx,ny)
        end,
    }}
end)

-- ============================================================
-- DAMAGE METER AUTO-RESET
-- On instance entry, prompt the player to reset the built-in
-- Blizzard damage meter (C_DamageMeter.Reset).
-- Uses StaticPopup so the dialog is taint-free and dismissable.
-- Only fires when: enabled, entering an instance (not login/reload),
-- and the damage meter CVar is actually on.
-- ============================================================

StaticPopupDialogs["MIDNIGHTQOL_METER_RESET"] = {
    text      = "|cFF00CCFF[RogUI]|r Reset the damage meter for this run?",
    button1   = "Reset",
    button2   = "Cancel",
    OnAccept  = function()
        if C_DamageMeter and C_DamageMeter.Reset then
            C_DamageMeter.Reset()
        end
    end,
    timeout   = 30,
    whileDead = false,
    hideOnEscape = true,
    preferredIndex = 3,
}

local function TryPromptMeterReset()
    if not RogUIDB or not RogUIDB.meterAutoReset then return end
    -- Only prompt if the damage meter is actually enabled
    if GetCVar("damageMeterEnabled") ~= "1" then return end
    -- Only prompt in instanced content (dungeon, raid, M+, scenario)
    local _, instanceType = GetInstanceInfo()
    if instanceType ~= "party" and instanceType ~= "raid"
        and instanceType ~= "scenario" then return end
    StaticPopup_Show("MIDNIGHTQOL_METER_RESET")
end

-- ── Events (unified system) ───────────────────────────────────────────────────
-- qolEvents frame replaced by API.RegisterEvent calls (see end of section)

-- Poll for pet spec up to maxTries times, 1s apart.
-- Stops as soon as GetPetSpecialization() returns a valid ID.
local function WaitForPetSpec(maxTries)
    maxTries = maxTries or 8
    local tries = 0
    local function attempt()
        tries = tries + 1
        if not UnitExists("pet") then return end  -- pet gone, abort
        if not IsPetSpecPending() then
            CheckPetReminder("pet spec resolved")
            return
        end
        if tries < maxTries then
            C_Timer.After(1, attempt)
        end
    end
    C_Timer.After(0.5, attempt)
end

local function OnQoLEvent(event, ...)
    if event == "PLAYER_LOGIN" then
        -- Restore pet reminder position
        if RogUIDB and RogUIDB.petReminderX then
            petReminderFrame:ClearAllPoints()
            petReminderFrame:SetPoint("CENTER",UIParent,"CENTER", RogUIDB.petReminderX, RogUIDB.petReminderY or 80)
        end
        C_Timer.After(3, function() CheckPetReminder("login") end)
    elseif event == "READY_CHECK" then
        CheckPetReminder("ready check")
    elseif event == "UNIT_PET" then
        local unit = ...
        if unit == "player" and PET_CLASSES[API.playerClass] then
            if IsMounted() then return end
            -- Pet appeared — kill the nag regardless of combat state
            if UnitExists("pet") then StopPetNag() end
            if InCombatLockdown() then return end
            if IsPetSpecPending() then
                -- Spec data isn't ready yet — poll until it is
                WaitForPetSpec()
            else
                C_Timer.After(0.5, function() CheckPetReminder("pet changed") end)
            end
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        local isInitialLogin, isReloadingUi = ...
        -- Fire on all zone transitions including login and reload
        C_Timer.After(3, function() CheckPetReminder("entering world") end)
        -- Prompt meter reset only on genuine zone transitions, not login/reload
        if not isInitialLogin and not isReloadingUi then
            C_Timer.After(1.5, TryPromptMeterReset)
        end
    elseif event == "PLAYER_SPECIALIZATION_CHANGED" then
        CheckPetReminder("spec change")
    elseif event == "PLAYER_REGEN_DISABLED" then
        -- Entered combat — start nagging every 10s if pet is missing
        if not (RogUIDB and RogUIDB.petReminderEnabled) then return end
        if not PET_CLASSES[API.playerClass] then return end
        if not IsMounted() and not UnitExists("pet") then
            ShowPetReminderOverlay(true)
            StartPetNag()
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        StopPetNag()
        -- Only remind on leaving combat if the pet is actually missing
        if not (RogUIDB and RogUIDB.petReminderEnabled) then return end
        if not PET_CLASSES[API.playerClass] then return end
        if IsMounted() then return end
        if not UnitExists("pet") then
            C_Timer.After(1, function()
                -- Re-check after 1s to give Hunter pets a chance to resummon automatically
                if not InCombatLockdown() and not UnitExists("pet") and not IsMounted() then
                    ShowPetReminderOverlay(true)
                end
            end)
        end
    end
end

-- ============================================================
-- Bars (merged from RogUI_Bars)
-- Break bar frame, pull timer, addon message broadcast/receive.
-- ============================================================

local BREAK_CHANNEL = "CS_BREAK"  -- 16-char max WoW addon prefix

-- ── Addon comms registration ───────────────────────────────────────────────────
local function RegisterAddonComms()
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        C_ChatInfo.RegisterAddonMessagePrefix(BREAK_CHANNEL)
        C_ChatInfo.RegisterAddonMessagePrefix("D4")
    end
end

-- ── Break bar frame ────────────────────────────────────────────────────────────
local breakBar = CreateFrame("Frame", "RogUIBreakBar", UIParent)
breakBar:SetSize(300, 32)
breakBar:SetPoint("TOP", UIParent, "TOP", 0, -180)
breakBar:SetFrameStrata("HIGH"); breakBar:Hide()
breakBar:SetMovable(true); breakBar:EnableMouse(true)
breakBar:RegisterForDrag("LeftButton")
breakBar:SetScript("OnDragStart", function(self) if API.IsLayoutMode and API.IsLayoutMode() then self:StartMoving() end end)
breakBar:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    if RogUIDB then
        local cx = UIParent:GetWidth()/2;  local cy = UIParent:GetHeight()/2
        local bx = self:GetLeft()+self:GetWidth()/2; local by = self:GetBottom()+self:GetHeight()/2
        RogUIDB.breakBarX = math.floor(bx-cx+0.5)
        RogUIDB.breakBarY = math.floor(by-cy+0.5)
    end
end)

local breakBG = breakBar:CreateTexture(nil, "BACKGROUND")
breakBG:SetAllPoints(); breakBG:SetColorTexture(0,0,0,0.7)

local breakFill = breakBar:CreateTexture(nil, "ARTWORK")
breakFill:SetPoint("TOPLEFT", breakBar, "TOPLEFT", 0, 0)
breakFill:SetPoint("BOTTOMLEFT", breakBar, "BOTTOMLEFT", 0, 0)
breakFill:SetWidth(300); breakFill:SetColorTexture(0.2, 0.6, 1, 0.85)
API.breakFill = breakFill

local breakLabel = breakBar:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
breakLabel:SetAllPoints(); breakLabel:SetJustifyH("CENTER"); breakLabel:SetText("Break: 5:00")

breakBar.endTime       = 0
breakBar.totalDuration = 1

breakBar:SetScript("OnUpdate", function(self, dt)
    local remaining = self.endTime - GetTime()
    if remaining <= 0 then self:Hide(); return end
    breakFill:SetWidth(math.max(1, 300 * (remaining / self.totalDuration)))
    breakLabel:SetText(string.format("Break: %d:%02d", math.floor(remaining/60), math.floor(remaining%60)))
end)

local function StartBreakBar(durationSecs)
    breakBar.endTime       = GetTime() + durationSecs
    breakBar.totalDuration = durationSecs
    breakFill:SetWidth(300)
    local r = (RogUIDB and RogUIDB.breakBarR) or 0.2
    local g = (RogUIDB and RogUIDB.breakBarG) or 0.6
    local b = (RogUIDB and RogUIDB.breakBarB) or 1.0
    breakFill:SetColorTexture(r, g, b, 0.85)
    breakLabel:SetText(string.format("Break: %d:%02d", math.floor(durationSecs/60), math.floor(durationSecs%60)))
    if RogUIDB and RogUIDB.breakBarX then
        breakBar:ClearAllPoints()
        breakBar:SetPoint("CENTER", UIParent, "CENTER", RogUIDB.breakBarX, RogUIDB.breakBarY or 0)
    end
    breakBar:Show()
end
API.StartBreakBar = StartBreakBar

-- ── Layout handle provider ─────────────────────────────────────────────────────
API.RegisterLayoutHandles(function()
    local cy = UIParent:GetHeight()/2
    local ox = (RogUIDB and RogUIDB.breakBarX) or 0
    local oy = (RogUIDB and RogUIDB.breakBarY) or (cy - 180 - cy)
    return {{
        label        = "Break Timer Bar",
        iconTex      = "Interface\\Icons\\Ability_Rogue_Sprint",
        ox           = ox, oy = oy,
        liveFrameRef = breakBar,
        saveCallback = function(nx, ny)
            if RogUIDB then RogUIDB.breakBarX=nx; RogUIDB.breakBarY=ny end
            breakBar:ClearAllPoints(); breakBar:SetPoint("CENTER",UIParent,"CENTER",nx,ny)
        end,
    }}
end)

API.RegisterEvent("QoL", "PLAYER_LOGIN",                function(...) OnQoLEvent("PLAYER_LOGIN", ...) end)
API.RegisterEvent("QoL", "READY_CHECK",                 function(...) OnQoLEvent("READY_CHECK", ...) end)
API.RegisterEvent("QoL", "UNIT_PET",                    function(...) OnQoLEvent("UNIT_PET", ...) end)
API.RegisterEvent("QoL", "PLAYER_ENTERING_WORLD",       function(...) OnQoLEvent("PLAYER_ENTERING_WORLD", ...) end)
API.RegisterEvent("QoL", "PLAYER_SPECIALIZATION_CHANGED", function(...) OnQoLEvent("PLAYER_SPECIALIZATION_CHANGED", ...) end)
API.RegisterEvent("QoL", "PLAYER_REGEN_ENABLED",        function(...) OnQoLEvent("PLAYER_REGEN_ENABLED", ...) end)
API.RegisterEvent("QoL", "PLAYER_REGEN_DISABLED",       function(...) OnQoLEvent("PLAYER_REGEN_DISABLED", ...) end)


-- ── Break bar event handler (unified system) ──────────────────────────────────
local function OnBarsEvent(event, ...)
    if event == "PLAYER_LOGIN" then
        RegisterAddonComms()
        if RogUIDB and RogUIDB.breakBarX then
            breakBar:ClearAllPoints()
            breakBar:SetPoint("CENTER", UIParent, "CENTER", RogUIDB.breakBarX, RogUIDB.breakBarY or 0)
        end

    elseif event == "CHAT_MSG_ADDON" then
        local prefix, payload, channel, sender = ...
        if prefix ~= BREAK_CHANNEL and prefix ~= "D4" then return end
        local myName = UnitName("player")
        if sender and myName and (sender==myName or sender:sub(1,#myName+1)==myName.."-") then return end

        -- Handle our own CS_BREAK protocol
        if prefix == BREAK_CHANNEL then
            local cmd, val = payload:match("^(%w+):(%d+)$")
            if cmd == "START" then
                local secs = tonumber(val)
                if secs and secs > 0 then
                    StartBreakBar(secs)
                    local mins = math.floor(secs/60); local secsRem = secs%60
                    local timeStr = secsRem>0 and string.format("%d:%02d",mins,secsRem) or (mins.." min")
                    print("|cFF00CCFF[RogUI]|r "..tostring(sender).." started a "..timeStr.." break.")
                end
            end
            return
        end

        -- Handle DBM/BigWigs shared D4 protocol: "BT\t<seconds>"
        if prefix == "D4" then
            local breakSecs = payload:match("^BT\t(%d+)")
            if breakSecs then
                local secs = tonumber(breakSecs)
                if secs and secs > 0 then
                    StartBreakBar(secs)
                    local mins = math.floor(secs/60); local secsRem = secs%60
                    local timeStr = secsRem>0 and string.format("%d:%02d",mins,secsRem) or (mins.." min")
                    print("|cFF00CCFF[RogUI]|r "..tostring(sender).." started a "..timeStr.." break (via DBM).")
                end
            end
            return
        end
    end

end

API.RegisterEvent("QoL", "PLAYER_LOGIN",      function(...) OnBarsEvent("PLAYER_LOGIN", ...) end)
API.RegisterEvent("QoL", "CHAT_MSG_ADDON",    function(...) OnBarsEvent("CHAT_MSG_ADDON", ...) end)


-- ── Slash commands ─────────────────────────────────────────────────────────────
SLASH_MQPULL1 = "/pull"
SlashCmdList["MQPULL"] = function(msg)
    if RogUIDB and RogUIDB.pullTimerEnabled==false then
        print("|cFFFF4444[RogUI]|r Pull timer is disabled. Enable it in the General tab."); return
    end
    local secs = math.max(1, math.min(60, tonumber(msg) or 10))
    local channel = IsInRaid() and "RAID" or IsInGroup() and "PARTY" or nil
    if channel and C_ChatInfo then
        local mapID = tostring(C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player") or 0)
        pcall(function()
            C_ChatInfo.RegisterAddonMessagePrefix("D4")
            C_ChatInfo.SendAddonMessage("D4","PT\t"..secs.."\t"..mapID, channel)
        end)
    end
    if DBM then
        if DBM.StartPull then DBM:StartPull(secs) elseif DBM.Pull then DBM:Pull(secs) end
    end
    if SlashCmdList["COUNTDOWN"] then SlashCmdList["COUNTDOWN"](tostring(secs))
    elseif SlashCmdList["CD"]     then SlashCmdList["CD"](tostring(secs))
    else
        local eb = ChatEdit_GetActiveWindow()
        if eb then eb:SetText("/cd "..secs); ChatEdit_SendText(eb,0) end
    end
end

SLASH_MQBREAK1 = "/break"
SlashCmdList["MQBREAK"] = function(msg)
    if RogUIDB and RogUIDB.breakTimerEnabled==false then
        print("|cFFFF4444[RogUI]|r Break timer is disabled. Enable it in the General tab."); return
    end
    local mins = tonumber(msg) or 5
    local secs = math.max(1,mins)*60
    StartBreakBar(secs)
    local channel = IsInRaid() and "RAID" or IsInGroup() and "PARTY" or nil
    if channel and C_ChatInfo then
        pcall(function()
            C_ChatInfo.RegisterAddonMessagePrefix("D4")
            C_ChatInfo.SendAddonMessage("D4","BT\t"..math.floor(secs), channel)
        end)
        pcall(function()
            C_ChatInfo.RegisterAddonMessagePrefix(BREAK_CHANNEL)
            C_ChatInfo.SendAddonMessage(BREAK_CHANNEL,"START:"..math.floor(secs), channel)
        end)
    end
    if DBM and DBM.StartBreak then DBM:StartBreak(secs) elseif DBM and DBM.Break then DBM:Break(secs) end
    local dispMins=math.floor(secs/60); local dispSecs=secs%60
    local timeStr = dispSecs>0 and string.format("%d:%02d",dispMins,dispSecs) or (dispMins.." min")
    print("|cFF00CCFF[RogUI]|r Break timer started: "..timeStr
        ..(channel and " (broadcasted to "..channel..")" or " (not in a group)"))
end

-- ── Ready Check ───────────────────────────────────────────────────────────────
SLASH_MQRC1 = "/rc"
SlashCmdList["MQRC"] = function()
    if IsInRaid() or IsInGroup() then
        DoReadyCheck()
    else
        print("|cFFFF4444[RogUI]|r You are not in a group.")
    end
end
