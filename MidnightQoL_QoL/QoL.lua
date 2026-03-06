-- ============================================================
-- MidnightQoL_QoL / QoL.lua
-- Pet reminder overlay for Hunters and Warlocks.
-- ============================================================

local API = MidnightQoLAPI

local PET_CLASSES = { HUNTER = true, WARLOCK = true }

-- Abilities are based on the pet's family/spec role.
-- Warlock: Command Demon ability (what the player presses) + passive utility.
-- Hunter:  what the pet's family brings to the group.
local PET_ABILITIES = {
    -- ── Warlock demons ────────────────────────────────────────────────────
    ["Imp"]        = { interrupt="Cauterize Master — Command Demon",              defensive="Singe Magic — dispel magic debuff from ally" },
    ["Voidwalker"] = { defensive="Shadow Bulwark — Command Demon absorb shield" },
    ["Felhunter"]  = { interrupt="Spell Lock — Command Demon silence/interrupt",  cleanse="Devour Magic — dispel magic" },
    ["Succubus"]   = { cc="Seduction — Command Demon charm (humanoids)" },
    ["Felguard"]   = { interrupt="Axe Toss — Command Demon stun",                cc="Pursuit — root" },
    ["Wrathguard"] = { interrupt="Mortal Cleave — Command Demon",                 cc="Threatening Presence — taunt" },
    ["Observer"]   = { interrupt="Optical Blast — Command Demon silence",         cleanse="Fel Absorption — absorb" },
    ["Infernal"]   = { cc="Meteor Strike — stun,  Immolation — AoE" },
    ["Doomguard"]  = { interrupt="Doom Bolt — Command Demon",                     defensive="Demonic Fortitude — stamina buff" },
    ["Darkglare"]  = { cc="Eye Sore — damage + DoT" },
    -- ── Hunter pets — by pet family role ─────────────────────────────────
    -- Ferocity (DPS / Heroism)
    ["Cat"]          = { interrupt="Rake — silence" },
    ["Lynx"]         = { interrupt="Rake — silence" },
    ["Cheetah"]      = { interrupt="Rake — silence" },
    ["Owl"]          = { interrupt="Screech — silence" },
    ["Bat"]          = { interrupt="Sonic Blast — silence" },
    ["Dragonhawk"]   = { interrupt="Fire Breath" },
    ["Nether Ray"]   = { interrupt="Nether Shock — silence" },
    ["Wind Serpent"] = { interrupt="Lightning Breath" },
    ["Carrion Bird"] = { interrupt="Demoralizing Screech" },
    ["Raptor"]       = { interrupt="Tear Armor" },
    ["Devilsaur"]    = { interrupt="Monstrous Bite",      cc="Fearsome Roar — fear" },
    ["Wolf"]         = { defensive="Furious Howl — attack power buff" },
    ["Core Hound"]   = { defensive="Ancient Hysteria — Heroism/Lust" },
    ["Hyena"]        = { cc="Cackling Howl — speed reduce" },
    ["Wasp"]         = { cc="Sting — slow" },
    ["Scorpid"]      = { cc="Scorpid Poison — slow" },
    ["Serpent"]      = { cleanse="Viper Sting — mana drain" },
    -- Tenacity (tank / defensive)
    ["Bear"]         = { defensive="Thick Hide, Last Stand — damage reduction" },
    ["Turtle"]       = { defensive="Shell Shield — extreme damage reduction" },
    ["Boar"]         = { defensive="Charge, Gore — threat" },
    ["Gorilla"]      = { interrupt="Pummel",              defensive="Thunderstomp — AoE threat" },
    ["Warp Stalker"] = { defensive="Warp — phase shift" },
    ["Crab"]         = { defensive="Shell Shield",        cc="Pin — root" },
    ["Clefthoof"]    = { defensive="Thick Hide" },
    ["Worm"]         = { defensive="Burrow Attack" },
    ["Tallstrider"]  = { defensive="Dust Cloud — miss chance" },
    -- Cunning (PvP / utility)
    ["Spider"]       = { cc="Web — root" },
    ["Silithid"]     = { cc="Venom Web Spray — root" },
    ["Rhino"]        = { cc="Stampede — knockback" },
    ["Mammoth"]      = { cc="Trample — knockback" },
    ["Ravager"]      = { cc="Ravage" },
    ["Sporebat"]     = { cc="Spore Cloud — slow" },
    ["Chimaera"]     = { cleanse="Froststorm Breath — slow" },
    -- Special utility
    ["Quilen"]       = { defensive="Eternal Guardian — battle rez", cleanse="Quilen Wail — AoE dispel" },
    ["Spirit Beast"] = { cleanse="Spirit Mend — heal",    defensive="Spirit Walk — stealth" },
    ["Water Strider"]= { defensive="Surface Trot — water walking" },
}

local PET_ROLE_FALLBACK = {
    HUNTER  = { defensive="Unknown family — check Petopia for role" },
    WARLOCK = { interrupt="Command Demon varies by active pet" },
}

local function GetPetAbilitySummary()
    local family = UnitCreatureFamily and UnitCreatureFamily("pet")
    local data   = family and PET_ABILITIES[family] or PET_ROLE_FALLBACK[API.playerClass]
    if not data then return nil end
    local parts = {}
    if data.interrupt then table.insert(parts, "|cFFFF6060[INTERRUPT]|r "..data.interrupt) end
    if data.cleanse   then table.insert(parts, "|cFF60FF60[DISPEL]|r "   ..data.cleanse)   end
    if data.defensive then table.insert(parts, "|cFF6699FF[UTILITY]|r "  ..data.defensive) end
    if data.cc        then table.insert(parts, "|cFFFFFF60[CC]|r "        ..data.cc)        end
    return #parts > 0 and table.concat(parts,"\n") or nil
end

-- ── Pet reminder frame ─────────────────────────────────────────────────────────
local petReminderFrame = CreateFrame("Frame","MidnightQoLPetReminder",UIParent)
petReminderFrame:SetSize(420,96); petReminderFrame:SetPoint("CENTER",UIParent,"CENTER",0,80)
petReminderFrame:SetFrameStrata("HIGH"); petReminderFrame:SetMovable(true); petReminderFrame:EnableMouse(true)
petReminderFrame:RegisterForDrag("LeftButton"); petReminderFrame:SetClampedToScreen(true)
petReminderFrame:SetScript("OnDragStart",function(self) self:StartMoving() end)
petReminderFrame:SetScript("OnDragStop",function(self)
    self:StopMovingOrSizing()
    if BuffAlertDB then
        local cx=UIParent:GetWidth()/2; local cy=UIParent:GetHeight()/2
        local fx=self:GetLeft()+self:GetWidth()/2; local fy=self:GetBottom()+self:GetHeight()/2
        BuffAlertDB.petReminderX=math.floor(fx-cx+0.5); BuffAlertDB.petReminderY=math.floor(fy-cy+0.5)
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
    if not (BuffAlertDB and BuffAlertDB.petReminderEnabled) then return end
    if not PET_CLASSES[API.playerClass] then return end

    local db = BuffAlertDB or {}
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
        petReminderText:SetText(petName..(family~="" and ("  |cFFAAAAAA("..family..")|r") or ""))
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
            print("|cFFFF6600[MidnightQoL]|r Don't forget to summon your pet!")
        end
    end

    petReminderFrame:SetAlpha(0); petReminderFrame:Show()
    UIFrameFadeIn(petReminderFrame,0.4,0,1)
    petReminderFrame.hideTimer = C_Timer.NewTimer(8,function()
        UIFrameFadeOut(petReminderFrame,1.0,1,0)
        C_Timer.After(1.1,function() if petReminderFrame:GetAlpha()<0.05 then petReminderFrame:Hide() end end)
        petReminderFrame.hideTimer=nil
    end)
end

local function CheckPetReminder(reason)
    if not (BuffAlertDB and BuffAlertDB.petReminderEnabled) then return end
    if not PET_CLASSES[API.playerClass] then return end
    -- Don't fire while mounted or flying — pet is dismissed by design
    if IsMounted() then return end
    ShowPetReminderOverlay(not UnitExists("pet"))
end
API.CheckPetReminder = CheckPetReminder

-- ── Layout handle provider ─────────────────────────────────────────────────────
API.RegisterLayoutHandles(function()
    local ox = (BuffAlertDB and BuffAlertDB.petReminderX) or 0
    local oy = (BuffAlertDB and BuffAlertDB.petReminderY) or 80
    return {{
        label        = "Pet Reminder",
        iconTex      = "Interface\\Icons\\Ability_Hunter_BeastCall",
        ox           = ox, oy = oy,
        liveFrameRef = petReminderFrame,
        saveCallback = function(nx,ny)
            if BuffAlertDB then BuffAlertDB.petReminderX=nx; BuffAlertDB.petReminderY=ny end
            petReminderFrame:ClearAllPoints(); petReminderFrame:SetPoint("CENTER",UIParent,"CENTER",nx,ny)
        end,
    }}
end)

-- ── Events ─────────────────────────────────────────────────────────────────────
local qolEvents = CreateFrame("Frame")
qolEvents:RegisterEvent("PLAYER_LOGIN")
qolEvents:RegisterEvent("READY_CHECK")
qolEvents:RegisterEvent("UNIT_PET")
qolEvents:RegisterEvent("PLAYER_ENTERING_WORLD")
qolEvents:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")

qolEvents:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_LOGIN" then
        C_Timer.After(3, function() CheckPetReminder("login") end)
        -- Restore pet reminder position
        if BuffAlertDB and BuffAlertDB.petReminderX then
            petReminderFrame:ClearAllPoints()
            petReminderFrame:SetPoint("CENTER",UIParent,"CENTER", BuffAlertDB.petReminderX, BuffAlertDB.petReminderY or 80)
        end
    elseif event == "READY_CHECK" then
        CheckPetReminder("ready check")
    elseif event == "UNIT_PET" then
        local unit = ...
        if unit == "player" and PET_CLASSES[API.playerClass] then
            -- Small delay so mount state is settled before we check IsMounted()
            C_Timer.After(0.5, function() CheckPetReminder("pet changed") end)
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        local isInitialLogin, isReloadingUi = ...
        if not isInitialLogin and not isReloadingUi and IsInInstance() then
            C_Timer.After(3, function() CheckPetReminder("entering instance") end)
        end
    elseif event == "PLAYER_SPECIALIZATION_CHANGED" then
        CheckPetReminder("spec change")
    end
end)

-- ============================================================
-- Bars (merged from MidnightQoL_Bars)
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
local breakBar = CreateFrame("Frame", "MidnightQoLBreakBar", UIParent)
breakBar:SetSize(300, 32)
breakBar:SetPoint("TOP", UIParent, "TOP", 0, -180)
breakBar:SetFrameStrata("HIGH"); breakBar:Hide()
breakBar:SetMovable(true); breakBar:EnableMouse(true)
breakBar:RegisterForDrag("LeftButton")
breakBar:SetScript("OnDragStart", function(self) self:StartMoving() end)
breakBar:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    if BuffAlertDB then
        local cx = UIParent:GetWidth()/2;  local cy = UIParent:GetHeight()/2
        local bx = self:GetLeft()+self:GetWidth()/2; local by = self:GetBottom()+self:GetHeight()/2
        BuffAlertDB.breakBarX = math.floor(bx-cx+0.5)
        BuffAlertDB.breakBarY = math.floor(by-cy+0.5)
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
    local r = (BuffAlertDB and BuffAlertDB.breakBarR) or 0.2
    local g = (BuffAlertDB and BuffAlertDB.breakBarG) or 0.6
    local b = (BuffAlertDB and BuffAlertDB.breakBarB) or 1.0
    breakFill:SetColorTexture(r, g, b, 0.85)
    breakLabel:SetText(string.format("Break: %d:%02d", math.floor(durationSecs/60), math.floor(durationSecs%60)))
    if BuffAlertDB and BuffAlertDB.breakBarX then
        breakBar:ClearAllPoints()
        breakBar:SetPoint("CENTER", UIParent, "CENTER", BuffAlertDB.breakBarX, BuffAlertDB.breakBarY or 0)
    end
    breakBar:Show()
end
API.StartBreakBar = StartBreakBar

-- ── Layout handle provider ─────────────────────────────────────────────────────
API.RegisterLayoutHandles(function()
    local cy = UIParent:GetHeight()/2
    local ox = (BuffAlertDB and BuffAlertDB.breakBarX) or 0
    local oy = (BuffAlertDB and BuffAlertDB.breakBarY) or (cy - 180 - cy)
    return {{
        label        = "Break Timer Bar",
        iconTex      = "Interface\\Icons\\Ability_Rogue_Sprint",
        ox           = ox, oy = oy,
        liveFrameRef = breakBar,
        saveCallback = function(nx, ny)
            if BuffAlertDB then BuffAlertDB.breakBarX=nx; BuffAlertDB.breakBarY=ny end
            breakBar:ClearAllPoints(); breakBar:SetPoint("CENTER",UIParent,"CENTER",nx,ny)
        end,
    }}
end)

-- ── Event handler ─────────────────────────────────────────────────────────────
local barsEvents = CreateFrame("Frame")
barsEvents:RegisterEvent("PLAYER_LOGIN")
barsEvents:RegisterEvent("CHAT_MSG_ADDON")

barsEvents:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_LOGIN" then
        RegisterAddonComms()
        if BuffAlertDB and BuffAlertDB.breakBarX then
            breakBar:ClearAllPoints()
            breakBar:SetPoint("CENTER", UIParent, "CENTER", BuffAlertDB.breakBarX, BuffAlertDB.breakBarY or 0)
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
                    print("|cFF00CCFF[MidnightQoL]|r "..tostring(sender).." started a "..timeStr.." break.")
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
                    print("|cFF00CCFF[MidnightQoL]|r "..tostring(sender).." started a "..timeStr.." break (via DBM).")
                end
            end
            return
        end
    end
end)

-- ── Slash commands ─────────────────────────────────────────────────────────────
SLASH_MQPULL1 = "/pull"
SlashCmdList["MQPULL"] = function(msg)
    if BuffAlertDB and BuffAlertDB.pullTimerEnabled==false then
        print("|cFFFF4444[MidnightQoL]|r Pull timer is disabled. Enable it in the General tab."); return
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
    if BuffAlertDB and BuffAlertDB.breakTimerEnabled==false then
        print("|cFFFF4444[MidnightQoL]|r Break timer is disabled. Enable it in the General tab."); return
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
    print("|cFF00CCFF[MidnightQoL]|r Break timer started: "..timeStr
        ..(channel and " (broadcasted to "..channel..")" or " (not in a group)"))
end

-- ── Ready Check ───────────────────────────────────────────────────────────────
SLASH_MQRC1 = "/rc"
SlashCmdList["MQRC"] = function()
    if IsInRaid() or IsInGroup() then
        DoReadyCheck()
    else
        print("|cFFFF4444[MidnightQoL]|r You are not in a group.")
    end
end
