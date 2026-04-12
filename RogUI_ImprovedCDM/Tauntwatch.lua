-- ============================================================
-- RogUI / TauntWatch.lua
-- Encounter-aware taunt swap monitor.
-- Loads boss set by zone (instanceID), listens per encounterID.
-- Bar displays only the taunt swap icons for the active fight.
-- Click an icon to open per-swap settings (stack threshold +
-- sound alert configuration).
-- ============================================================

local API = RogUIAPI
if not API then return end

-- ─── Encounter Database ───────────────────────────────────────────────────────
-- Structure: ZONE_DATA[zoneID].encounters[encounterID].watches[]
--
-- watch fields:
--   type          "debuff" | "buff" | "cast"
--   spellID       spell / aura / debuff ID
--   bossID        NPC ID used to verify CLEU source (cast/buff)
--   bossUnit      unit token "boss1"…"boss5" used for buff aura scan
--   label         short display name
--   desc          tooltip description
--   defaultStacks initial stack-alert threshold (debuff/buff only; 0 = any stack)

local ZONE_DATA = {

    -- ════════════════════════════════════════════════════════
    -- THE DREAMRIFT   zone 2548
    -- ════════════════════════════════════════════════════════
    [2548] = {
        zoneName  = "The Dreamrift",
        encounters = {

            [2684] = {           -- Chimeras
                name    = "Chimeras",
                watches = {
                    { type="cast",   spellID=402183, bossID=214001, bossUnit="boss1",
                      label="Dust Upheaval",
                      desc="Boss casting Dust Upheaval — prepare to swap" },
                },
            },
        },
    },

    -- ════════════════════════════════════════════════════════
    -- VOIDSPIRE   zone 2652
    -- ════════════════════════════════════════════════════════
    [2652] = {
        zoneName  = "Voidspire",
        encounters = {

            [2814] = {           -- Imperator Averzian
                name    = "Imperator Averzian",
                watches = {
                    { type="debuff", spellID=410922, bossID=215110,
                      label="Blackening Wounds", defaultStacks=5,
                      desc="Tank debuff stacking — swap at threshold" },
                    { type="cast",   spellID=410935, bossID=215110, bossUnit="boss1",
                      label="Umbral Collapse",
                      desc="Boss casting Umbral Collapse — swap now" },
                },
            },

            [2818] = {           -- Vorasius
                name    = "Vorasius",
                watches = {
                    { type="debuff", spellID=415670, bossID=215150,
                      label="Smashed", defaultStacks=5,
                      desc="Tank debuff stacking — swap at threshold" },
                },
            },

            [2820] = {           -- Fallen-King Salhadaar
                name    = "Fallen-King Salhadaar",
                watches = {
                    { type="cast", spellID=420112, bossID=215200, bossUnit="boss1",
                      label="Destabilizing Strikes",
                      desc="Boss casting Destabilizing Strikes — swap now" },
                },
            },

            [2822] = {           -- Vaelgor and Ezzorak
                name    = "Vaelgor and Ezzorak",
                watches = {
                    { type="buff", spellID=422301, bossID=215440, bossUnit="boss1",
                      label="Vaelwing", defaultStacks=1,
                      desc="Vaelgor gaining Vaelwing stacks — watch for swap" },
                    { type="buff", spellID=422305, bossID=215441, bossUnit="boss2",
                      label="Rakfang", defaultStacks=1,
                      desc="Ezzorak gaining Rakfang stacks — watch for swap" },
                },
            },

            [2825] = {           -- Lightblinded Vanguard
                name    = "Lightblinded Vanguard",
                watches = {
                    { type="cast", spellID=423150, bossID=216002, bossUnit="boss1",
                      label="Judgment (Venel Lightblood)",
                      desc="Venel Lightblood casting Judgment" },
                    { type="cast", spellID=423155, bossID=216005, bossUnit="boss2",
                      label="Judgment (Amias Bellamy)",
                      desc="Amias Bellamy casting Judgment" },
                },
            },

            [2828] = {           -- Crown of Chaos
                name    = "Crown of Chaos",
                watches = {
                    { type="debuff", spellID=425600, bossID=216500,
                      label="Rift Slash", defaultStacks=5,
                      desc="Tank debuff stacking — swap at threshold" },
                    { type="debuff", spellID=425615, bossID=216500,
                      label="Devouring Darkness", defaultStacks=5,
                      desc="Tank debuff stacking — swap at threshold" },
                },
            },
        },
    },

    -- ════════════════════════════════════════════════════════
    -- MARCH ON QUEL'DANAS   zone 2701
    -- ════════════════════════════════════════════════════════
    [2701] = {
        zoneName  = "March on Quel'Danas",
        encounters = {

            [2902] = {           -- Belo'ren
                name    = "Belo'ren",
                watches = {
                    { type="cast", spellID=430501, bossID=218000, bossUnit="boss1",
                      label="Light Edict",
                      desc="Belo'ren casting Light Edict — swap now" },
                    { type="cast", spellID=430502, bossID=218000, bossUnit="boss1",
                      label="Void Edict",
                      desc="Belo'ren casting Void Edict — swap now" },
                    { type="cast", spellID=430505, bossID=218000, bossUnit="boss1",
                      label="Voidlight Edict",
                      desc="Belo'ren casting Voidlight Edict — swap now" },
                },
            },

            [2910] = {           -- Midnight Fall
                name    = "Midnight Fall",
                watches = {
                    { type="debuff", spellID=435210, bossID=218550,
                      label="Impaled", defaultStacks=5,
                      desc="Tank debuff stacking — swap at threshold" },
                },
            },
        },
    },
}

local spellToEncounter = {}
for zID, zData in pairs(ZONE_DATA) do
    for eID, eData in pairs(zData.encounters) do
        for _, w in ipairs(eData.watches) do
            spellToEncounter[w.spellID] = eID
        end
    end
end

-- ─── Runtime state ────────────────────────────────────────────────────────────
local currentZoneID      = nil
local currentEncounterID = nil
local activeWatches      = {}   -- [spellID] = watchDef
local tankDebuffState    = {}   -- [spellID] = { [unit] = {stacks, expTime} }
local bossBuffState      = {}   -- [spellID] = stacks
local bossCastPending    = {}   -- [spellID] = bool
local activeBossIDs      = {}   -- [npcID]   = true  (for CLEU filtering)
local _debuffAlertFired  = {}   -- [spellID] = lastAlertedStackCount
local _buffAlertFired    = {}

-- ─── DB helpers ───────────────────────────────────────────────────────────────
local function GetDB()
    if not RogUIDB then return nil end
    if not RogUIDB.tauntWatch then
        RogUIDB.tauntWatch = { thresholds={}, sounds={}, enabled=true }
    end
    RogUIDB.tauntWatch.thresholds = RogUIDB.tauntWatch.thresholds or {}
    RogUIDB.tauntWatch.sounds     = RogUIDB.tauntWatch.sounds     or {}
    return RogUIDB.tauntWatch
end

local function GetThreshold(spellID, default)
    local db = GetDB()
    if db and db.thresholds[spellID] ~= nil then return db.thresholds[spellID] end
    return default or 5
end
local function SetThreshold(spellID, v) local db=GetDB(); if db then db.thresholds[spellID]=v end end

local function GetSound(spellID)   local db=GetDB(); return db and db.sounds[spellID] end
local function SetSound(spellID,s) local db=GetDB(); if db then db.sounds[spellID]=s end end

-- ─── Sound helper ─────────────────────────────────────────────────────────────
local function PlayWatchSound(spellID)
    local snd = GetSound(spellID)
    if snd and API.PlayCustomSound then API.PlayCustomSound(snd, false) end
end

-- ─── Icon bar constants ───────────────────────────────────────────────────────
local ICON_SIZE = 48
local ICON_PAD  = 6
local BAR_PAD   = 8

-- ─── Frame references ─────────────────────────────────────────────────────────
local barFrame      = nil
local iconButtons   = {}   -- [spellID] = button
local settingsPopup = nil

-- ─── Settings popup ───────────────────────────────────────────────────────────
local function BuildSettingsPopup()
    if settingsPopup then return settingsPopup end

    local f = CreateFrame("Frame", "RogUITauntWatchSettings", UIParent, "BackdropTemplate")
    f:SetSize(280, 210)
    f:SetFrameStrata("DIALOG")
    f:SetFrameLevel(200)
    f:SetBackdrop({ bgFile="Interface\\Buttons\\WHITE8x8",
                    edgeFile="Interface\\Buttons\\WHITE8x8", edgeSize=1 })
    f:SetBackdropColor(0.06, 0.06, 0.12, 0.96)
    f:SetBackdropBorderColor(0.4, 0.4, 0.7, 1)
    f:SetMovable(true); f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop",  f.StopMovingOrSizing)
    f:Hide()

    -- Title
    local title = f:CreateFontString(nil,"OVERLAY","GameFontNormal")
    title:SetPoint("TOPLEFT",f,"TOPLEFT",10,-10)
    title:SetPoint("TOPRIGHT",f,"TOPRIGHT",-30,-10)
    title:SetJustifyH("LEFT"); title:SetTextColor(1,0.85,0.2,1)
    f.title = title

    -- Spell icon
    local spellIcon = f:CreateTexture(nil,"ARTWORK")
    spellIcon:SetSize(36,36); spellIcon:SetPoint("TOPLEFT",f,"TOPLEFT",10,-28)
    spellIcon:SetTexCoord(0.08,0.92,0.08,0.92)
    f.spellIcon = spellIcon

    -- Description
    local desc = f:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    desc:SetPoint("TOPLEFT",spellIcon,"TOPRIGHT",8,0)
    desc:SetPoint("TOPRIGHT",f,"TOPRIGHT",-10,-28)
    desc:SetJustifyH("LEFT"); desc:SetHeight(36)
    f.desc = desc

    -- Close
    local closeBtn = CreateFrame("Button",nil,f,"UIPanelCloseButton")
    closeBtn:SetSize(22,22); closeBtn:SetPoint("TOPRIGHT",f,"TOPRIGHT",-2,-2)
    closeBtn:SetScript("OnClick", function() f:Hide() end)

    -- ── Stack threshold ─────────────────────────────────────────────────
    local threshHeader = f:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    threshHeader:SetPoint("TOPLEFT",f,"TOPLEFT",10,-76)
    threshHeader:SetTextColor(0.7,0.9,1,1)
    threshHeader:SetText("Stack Alert Threshold")
    f.threshHeader = threshHeader

    local threshDesc = f:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    threshDesc:SetPoint("TOPLEFT",threshHeader,"BOTTOMLEFT",0,-2)
    threshDesc:SetTextColor(0.55,0.55,0.55,1); threshDesc:SetText("Alert when stacks reach:")
    f.threshDesc = threshDesc

    local decBtn = CreateFrame("Button",nil,f,"GameMenuButtonTemplate")
    decBtn:SetSize(26,22); decBtn:SetPoint("TOPLEFT",threshDesc,"BOTTOMLEFT",0,-4)
    decBtn:SetText("-"); f.decBtn = decBtn

    local threshDisplay = f:CreateFontString(nil,"OVERLAY","GameFontNormal")
    threshDisplay:SetPoint("LEFT",decBtn,"RIGHT",6,0)
    threshDisplay:SetWidth(30); threshDisplay:SetJustifyH("CENTER")
    f.threshDisplay = threshDisplay

    local incBtn = CreateFrame("Button",nil,f,"GameMenuButtonTemplate")
    incBtn:SetSize(26,22); incBtn:SetPoint("LEFT",threshDisplay,"RIGHT",6,0)
    incBtn:SetText("+"); f.incBtn = incBtn

    -- ── Sound ───────────────────────────────────────────────────────────
    local soundHeader = f:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    soundHeader:SetPoint("TOPLEFT",decBtn,"BOTTOMLEFT",0,-12)
    soundHeader:SetTextColor(0.7,0.9,1,1); soundHeader:SetText("Sound Alert")
    f.soundHeader = soundHeader

    local soundLabel = f:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    soundLabel:SetPoint("TOPLEFT",soundHeader,"BOTTOMLEFT",0,-2)
    soundLabel:SetTextColor(0.55,0.55,0.55,1); soundLabel:SetText("Selected:")
    f.soundLabel = soundLabel

    local soundDisplay = f:CreateFontString(nil,"OVERLAY","GameFontHighlight")
    soundDisplay:SetPoint("LEFT",soundLabel,"RIGHT",4,0)
    soundDisplay:SetWidth(130); soundDisplay:SetJustifyH("LEFT")
    soundDisplay:SetTextColor(1,1,0.5,1)
    f.soundDisplay = soundDisplay

    local chooseSoundBtn = CreateFrame("Button",nil,f,"GameMenuButtonTemplate")
    chooseSoundBtn:SetSize(116,22)
    chooseSoundBtn:SetPoint("TOPLEFT",soundLabel,"BOTTOMLEFT",0,-4)
    chooseSoundBtn:SetText("Choose Sound…"); f.chooseSoundBtn = chooseSoundBtn

    local clearSoundBtn = CreateFrame("Button",nil,f,"GameMenuButtonTemplate")
    clearSoundBtn:SetSize(60,22)
    clearSoundBtn:SetPoint("LEFT",chooseSoundBtn,"RIGHT",4,0)
    clearSoundBtn:SetText("Clear"); f.clearSoundBtn = clearSoundBtn

    -- Preview sound button
    local previewBtn = CreateFrame("Button",nil,f,"GameMenuButtonTemplate")
    previewBtn:SetSize(60,22)
    previewBtn:SetPoint("TOPLEFT",chooseSoundBtn,"BOTTOMLEFT",0,-4)
    previewBtn:SetText("▶ Play"); f.previewBtn = previewBtn

    settingsPopup = f
    return f
end

local function OpenSettingsForWatch(watchDef, anchorBtn)
    local f = BuildSettingsPopup()
    local sid = watchDef.spellID

    f.title:SetText(watchDef.label or "Taunt Swap")
    local iconTex = C_Spell.GetSpellTexture(sid)
    f.spellIcon:SetTexture(iconTex or "Interface\\Icons\\INV_Misc_QuestionMark")
    f.desc:SetText(watchDef.desc or "")
    f._forSpell = sid

    local hasStacks = (watchDef.type == "debuff" or watchDef.type == "buff")
    f.threshHeader:SetShown(hasStacks)
    f.threshDesc:SetShown(hasStacks)
    f.decBtn:SetShown(hasStacks)
    f.threshDisplay:SetShown(hasStacks)
    f.incBtn:SetShown(hasStacks)

    if hasStacks then
        local function RefreshThresh()
            f.threshDisplay:SetText(tostring(GetThreshold(sid, watchDef.defaultStacks)))
        end
        RefreshThresh()
        f.decBtn:SetScript("OnClick", function()
            SetThreshold(sid, math.max(1, GetThreshold(sid, watchDef.defaultStacks) - 1))
            RefreshThresh()
            if API.SaveSpecProfile then API.SaveSpecProfile() end
        end)
        f.incBtn:SetScript("OnClick", function()
            SetThreshold(sid, math.min(99, GetThreshold(sid, watchDef.defaultStacks) + 1))
            RefreshThresh()
            if API.SaveSpecProfile then API.SaveSpecProfile() end
        end)
    end

    local function RefreshSound()
        local snd = GetSound(sid)
        f.soundDisplay:SetText(snd and ("|cFFFFFF55"..snd.."|r") or "|cFF888888None|r")
    end
    RefreshSound()

    f.chooseSoundBtn:SetScript("OnClick", function()
        if API.OpenSoundPicker then
            -- arg 1 = anchor frame, arg 2 = callback(soundData)
            API.OpenSoundPicker(f.chooseSoundBtn, function(sound)
                SetSound(sid, sound.path)
                RefreshSound()
                if API.SaveSpecProfile then API.SaveSpecProfile() end
            end)
        elseif SoundsList and #SoundsList > 0 then
            -- Fallback: cycle through SoundsList
            local cur = GetSound(sid)
            local nextIdx = 1
            if cur then
                for i, s in ipairs(SoundsList) do
                    if s == cur then nextIdx = (i % #SoundsList) + 1; break end
                end
            end
            SetSound(sid, SoundsList[nextIdx])
            RefreshSound()
            PlayWatchSound(sid)
            if API.SaveSpecProfile then API.SaveSpecProfile() end
        end
    end)

    f.clearSoundBtn:SetScript("OnClick", function()
        SetSound(sid, nil); RefreshSound()
        if API.SaveSpecProfile then API.SaveSpecProfile() end
    end)

    f.previewBtn:SetScript("OnClick", function()
        PlayWatchSound(sid)
    end)

    -- Position near icon button
    f:ClearAllPoints()
    if anchorBtn then
        f:SetPoint("BOTTOMLEFT", anchorBtn, "TOPLEFT", 0, 4)
    else
        f:SetPoint("CENTER", UIParent, "CENTER", 0, 100)
    end
    f:Show()

    -- Boundary nudge (after layout)
    C_Timer.After(0, function()
        if not f:IsShown() then return end
        if (f:GetTop() or 0) > GetScreenHeight() then
            f:ClearAllPoints()
            f:SetPoint("TOPLEFT", anchorBtn or UIParent, "BOTTOMLEFT", 0, -4)
        end
        if (f:GetLeft() or 0) < 0 then
            f:ClearAllPoints()
            f:SetPoint("LEFT", UIParent, "LEFT", 4, 0)
        end
    end)
end

-- ─── Icon bar ─────────────────────────────────────────────────────────────────
local function EnsureBarFrame()
    if barFrame then return barFrame end

    local bf = CreateFrame("Frame","RogUITauntWatchBar",UIParent,"BackdropTemplate")
    bf:SetFrameStrata("HIGH"); bf:SetFrameLevel(50)
    bf:SetBackdrop({ bgFile="Interface\\Buttons\\WHITE8x8",
                     edgeFile="Interface\\Buttons\\WHITE8x8", edgeSize=1 })
    bf:SetBackdropColor(0.04,0.04,0.08,0.82)
    bf:SetBackdropBorderColor(0.35,0.35,0.6,1)
    bf:SetMovable(true); bf:EnableMouse(true)
    bf:RegisterForDrag("LeftButton")
    bf:SetScript("OnDragStart", bf.StartMoving)
    bf:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local db = GetDB()
        if db then
            local x,y = self:GetCenter()
            db.barX = x - GetScreenWidth()  / 2
            db.barY = y - GetScreenHeight() / 2
        end
        if API.SaveSpecProfile then API.SaveSpecProfile() end
    end)

    -- Drag label above bar
    local hint = bf:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    hint:SetPoint("BOTTOMLEFT",bf,"TOPLEFT",0,2)
    hint:SetTextColor(0.5,0.5,0.6,0.7); hint:SetText("Taunt Watch  (drag)")
    bf.hint = hint

    bf:Hide()
    barFrame = bf
    return bf
end

local function RebuildIconBar()
    local bf = EnsureBarFrame()

    -- Hide / unparent old buttons
    for _, btn in pairs(iconButtons) do btn:Hide(); btn:SetParent(nil) end
    iconButtons = {}

    -- Build ordered watch list for this encounter
    local watchList = {}
    for _, wd in pairs(activeWatches) do table.insert(watchList, wd) end
    table.sort(watchList, function(a,b) return (a.spellID or 0) < (b.spellID or 0) end)

    if #watchList == 0 then bf:Hide(); return end

    local totalW = BAR_PAD * 2 + #watchList * ICON_SIZE + (#watchList - 1) * ICON_PAD
    local totalH = BAR_PAD * 2 + ICON_SIZE
    bf:SetSize(totalW, totalH)

    local db = GetDB()
    local bx = (db and db.barX) or 0
    local by = (db and db.barY) or -200
    bf:ClearAllPoints()
    bf:SetPoint("CENTER", UIParent, "CENTER", bx, by)

    for i, wd in ipairs(watchList) do
        local sid = wd.spellID
        local btn = CreateFrame("Button", nil, bf)
        btn:SetSize(ICON_SIZE, ICON_SIZE)
        btn:SetPoint("TOPLEFT", bf, "TOPLEFT",
            BAR_PAD + (i-1)*(ICON_SIZE+ICON_PAD), -BAR_PAD)
        btn:EnableMouse(true)
        btn:RegisterForClicks("LeftButtonUp")

        -- Background / border tint by type
        local bgTex = btn:CreateTexture(nil,"BACKGROUND")
        bgTex:SetAllPoints(btn)
        if     wd.type == "debuff" then bgTex:SetColorTexture(0.3,0.05,0.05,0.6)
        elseif wd.type == "buff"   then bgTex:SetColorTexture(0.05,0.3,0.05,0.6)
        else                            bgTex:SetColorTexture(0.3,0.2,0.0,0.6) end
        btn.bgTex = bgTex

        -- Spell icon
        local tex = btn:CreateTexture(nil,"ARTWORK")
        tex:SetAllPoints(btn); tex:SetTexCoord(0.08,0.92,0.08,0.92)
        tex:SetTexture(C_Spell.GetSpellTexture(sid) or "Interface\\Icons\\INV_Misc_QuestionMark")
        btn.tex = tex

        -- Highlight border (shown on threshold breach)
        local borderTex = btn:CreateTexture(nil,"OVERLAY")
        borderTex:SetAllPoints(btn)
        borderTex:SetColorTexture(1,1,1,0); btn.borderTex = borderTex

        -- Stack count label
        local stackStr = btn:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
        stackStr:SetPoint("BOTTOMRIGHT",btn,"BOTTOMRIGHT",-2,2)
        stackStr:SetFont(stackStr:GetFont(),13,"OUTLINE")
        stackStr:SetTextColor(1,0.2,0.2,1); stackStr:Hide()
        btn.stackStr = stackStr

        -- Cast flash overlay
        local flash = btn:CreateTexture(nil,"OVERLAY")
        flash:SetAllPoints(btn); flash:SetColorTexture(1,0.55,0,0); flash:SetAlpha(0)
        btn.flash = flash

        -- Type badge (tiny corner text)
        local badge = btn:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
        badge:SetPoint("TOPLEFT",btn,"TOPLEFT",2,-2)
        badge:SetFont(badge:GetFont(),9,"OUTLINE")
        if     wd.type == "debuff" then badge:SetText("|cFFFF4444D|r")
        elseif wd.type == "buff"   then badge:SetText("|cFF44FF44B|r")
        else                            badge:SetText("|cFFFFAA00C|r") end
        btn.badge = badge

        -- Tooltip
        btn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self,"ANCHOR_RIGHT")
            GameTooltip:SetText(wd.label or "", 1, 0.85, 0.2, 1)
            if wd.desc and wd.desc ~= "" then
                GameTooltip:AddLine(wd.desc, 0.8,0.8,0.8,true)
            end
            local tc = wd.type=="debuff" and "|cFFFF4444" or
                       wd.type=="buff"   and "|cFF44FF44" or "|cFFFFAA00"
            GameTooltip:AddLine(tc..wd.type:upper().."|r  •  Spell "..sid)
            if wd.type=="debuff" or wd.type=="buff" then
                GameTooltip:AddLine("Threshold: "..GetThreshold(sid,wd.defaultStacks).." stacks",0.7,0.7,0.7)
            end
            local snd = GetSound(sid)
            GameTooltip:AddLine("Sound: "..(snd and ("|cFFFFFF55"..snd.."|r") or "|cFF888888None|r"))
            GameTooltip:AddLine("|cFFAAAAAA[Click] Configure|r")
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

        -- Click → settings popup
        btn:SetScript("OnClick", function(self, button)
            if button == "LeftButton" then
                if settingsPopup and settingsPopup:IsShown() and settingsPopup._forSpell == sid then
                    settingsPopup:Hide()
                else
                    OpenSettingsForWatch(wd, self)
                end
            end
        end)

        iconButtons[sid] = btn
    end

    bf:Show()
end

-- ─── Live icon state update ───────────────────────────────────────────────────
local function UpdateIconState(spellID, stacks, isCastFlash)
    local btn = iconButtons[spellID]
    if not btn then return end

    if isCastFlash then
        btn.flash:SetAlpha(0.8)
        local elapsed = 0
        btn:SetScript("OnUpdate", function(self, dt)
            elapsed = elapsed + dt
            self.flash:SetAlpha(math.max(0, 0.8*(1 - elapsed/0.9)))
            if elapsed >= 0.9 then self.flash:SetAlpha(0); self:SetScript("OnUpdate",nil) end
        end)
    else
        local wd = activeWatches[spellID]
        if stacks and stacks > 0 then
            local threshold = wd and GetThreshold(spellID, wd.defaultStacks) or 0
            btn.stackStr:SetText(tostring(stacks)..(threshold>0 and ("/"..threshold) or ""))
            btn.stackStr:Show()
            if threshold > 0 and stacks >= threshold then
                -- Red border pulse when at/over threshold
                btn.borderTex:SetColorTexture(1,0.1,0.1,0.9)
            else
                btn.borderTex:SetColorTexture(1,1,1,0)
            end
        else
            btn.stackStr:Hide()
            btn.borderTex:SetColorTexture(1,1,1,0)
        end
    end
end

-- ─── Scanning ─────────────────────────────────────────────────────────────────
local function ScanTankDebuffs()
    for spellID, watchDef in pairs(activeWatches) do
        if watchDef.type == "debuff" then
            local newState  = {}
            local bestStacks = 0

            local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, spellID)
            if ok and aura then
                local s = aura.applications or 1
                newState["player"] = { stacks=s, expTime=aura.expirationTime }
                if s > bestStacks then bestStacks = s end
            end

            local isRaid = IsInRaid()
            local prefix = isRaid and "raid" or "party"
            local limit  = isRaid and 40 or 4
            for i = 1, limit do
                local unit = prefix..i
                if UnitExists(unit) and not UnitIsUnit(unit,"player") then
                    if UnitGroupRolesAssigned(unit) == "TANK" then
                        local ok2, ad = pcall(C_UnitAuras.GetAuraDataBySpellID, unit, spellID, "HARMFUL")
                        if ok2 and ad then
                            local s = ad.applications or 1
                            newState[unit] = { stacks=s, expTime=ad.expirationTime }
                            if s > bestStacks then bestStacks = s end
                        end
                    end
                end
            end

            tankDebuffState[spellID] = newState
            UpdateIconState(spellID, bestStacks, false)

            local threshold = GetThreshold(spellID, watchDef.defaultStacks)
            local prevFired = _debuffAlertFired[spellID] or 0
            if bestStacks >= threshold and bestStacks ~= prevFired then
                _debuffAlertFired[spellID] = bestStacks
                PlayWatchSound(spellID)
            elseif bestStacks < threshold then
                _debuffAlertFired[spellID] = 0
            end
        end
    end
end

local function ScanBossBuffs()
    for spellID, watchDef in pairs(activeWatches) do
        if watchDef.type == "buff" then
            local bossUnit = watchDef.bossUnit or "boss1"
            local stacks   = 0
            if UnitExists(bossUnit) then
                local ok, ad = pcall(C_UnitAuras.GetAuraDataBySpellID, bossUnit, spellID, "HELPFUL")
                stacks = (ok and ad and ad.applications) or 0
            end
            bossBuffState[spellID] = stacks
            UpdateIconState(spellID, stacks, false)

            local threshold = GetThreshold(spellID, watchDef.defaultStacks)
            local prevFired = _buffAlertFired[spellID] or 0
            if stacks >= threshold and stacks ~= prevFired then
                _buffAlertFired[spellID] = stacks
                PlayWatchSound(spellID)
            elseif stacks < threshold then
                _buffAlertFired[spellID] = 0
            end
        end
    end
end

-- ─── Encounter management ─────────────────────────────────────────────────────
local function ActivateEncounter(encounterID)
    currentEncounterID = encounterID
    activeWatches      = {}
    tankDebuffState    = {}
    bossBuffState      = {}
    bossCastPending    = {}
    activeBossIDs      = {}
    _debuffAlertFired  = {}
    _buffAlertFired    = {}

    local db = GetDB()
    if db and db.enabled == false then return end

    -- Find zone data; prefer current zone, fall back to scanning all zones
    local zoneData = currentZoneID and ZONE_DATA[currentZoneID]
    if not (zoneData and zoneData.encounters and zoneData.encounters[encounterID]) then
        for _, zd in pairs(ZONE_DATA) do
            if zd.encounters and zd.encounters[encounterID] then
                zoneData = zd; break
            end
        end
    end
    if not zoneData then return end

    local enc = zoneData.encounters[encounterID]
    if not enc then return end

    for _, watch in ipairs(enc.watches) do
        activeWatches[watch.spellID] = watch
        if watch.bossID then activeBossIDs[watch.bossID] = true end
    end

    RebuildIconBar()
    ScanTankDebuffs()
    ScanBossBuffs()
end

local function DeactivateEncounter()
    currentEncounterID = nil
    activeWatches      = {}
    tankDebuffState    = {}
    bossBuffState      = {}
    bossCastPending    = {}
    activeBossIDs      = {}
    _debuffAlertFired  = {}
    _buffAlertFired    = {}
    if settingsPopup then settingsPopup:Hide() end
    for _, btn in pairs(iconButtons) do btn:Hide(); btn:SetParent(nil) end
    iconButtons = {}
    if barFrame then barFrame:Hide() end
end

-- ─── Event handling ───────────────────────────────────────────────────────────
local combatTicker = nil

API.RegisterEvent("TauntWatch", "PLAYER_ENTERING_WORLD", function()
    local _, _, _, _, _, _, _, instanceID = GetInstanceInfo()
    currentZoneID = instanceID
    DeactivateEncounter()
end)

API.RegisterEvent("TauntWatch", "ENCOUNTER_START", function(encounterID)
    ActivateEncounter(encounterID)
    if not combatTicker then
        combatTicker = C_Timer.NewTicker(0.5, function()
            ScanTankDebuffs()
            ScanBossBuffs()
        end)
    end
end)

API.RegisterEvent("TauntWatch", "ENCOUNTER_END", function()
    DeactivateEncounter()
    if combatTicker then combatTicker:Cancel(); combatTicker = nil end
end)

API.RegisterEvent("TauntWatch", "PLAYER_REGEN_ENABLED", function()
    if currentEncounterID then
        C_Timer.After(3, function()
            if not UnitAffectingCombat("player") then
                DeactivateEncounter()
                if combatTicker then combatTicker:Cancel(); combatTicker = nil end
            end
        end)
    end
end)

API.RegisterEvent("TauntWatch", "UNIT_AURA", function(unit)
    if not currentEncounterID then return end
    if unit == "player" or (unit and (unit:find("^raid") or unit:find("^party"))) then
        ScanTankDebuffs()
    elseif unit and unit:find("^boss") then
        ScanBossBuffs()
    end
end)

API.RegisterEvent("TauntWatch", "UNIT_SPELLCAST_START", function(unit, castGUID, spellID)
    if not currentEncounterID then return end
    
    local watchDef = activeWatches[spellID]
    if not watchDef or watchDef.type ~= "cast" then return end
    
    -- Check if this is a boss unit
    local isBoss = false
    if unit and unit:find("^boss") then
        isBoss = true
    else
        for i = 1, 5 do
            if UnitExists("boss"..i) and UnitIsUnit(unit, "boss"..i) then
                isBoss = true; break
            end
        end
    end
    if not isBoss then return end
    
    bossCastPending[spellID] = true
    UpdateIconState(spellID, nil, true)  -- flash + sound
end)

API.RegisterEvent("TauntWatch", "UNIT_SPELLCAST_STOP", function(unit, castGUID, spellID)
    if not currentEncounterID then return end
    if activeWatches[spellID] then
        bossCastPending[spellID] = nil
    end
end)

-- ─── Public API ───────────────────────────────────────────────────────────────
API.TauntWatch = {
    GetZoneData       = function() return ZONE_DATA end,
    GetCurrentEnc     = function() return currentEncounterID end,
    GetCurrentZone    = function() return currentZoneID end,
    IsEnabled         = function() local db=GetDB(); return db and db.enabled~=false end,
    SetEnabled        = function(v)
        local db=GetDB(); if db then db.enabled=v end
        if not v then DeactivateEncounter() end
    end,
    GetThreshold      = GetThreshold,
    SetThreshold      = SetThreshold,
    GetSound          = GetSound,
    SetSound          = SetSound,
    -- Force a rebuild of the icon bar (call after profile load)
    RefreshBar        = function()
        if currentEncounterID then
            RebuildIconBar()
        end
    end,
    GetAnchorPosition = function()
        local db = GetDB()
        local x = (db and db.barX) or 0
        local y = (db and db.barY) or -200
        return x, y
    end,
    SetAnchorPosition = function(x, y)
        local db = GetDB()
        if db then db.barX = x; db.barY = y end
        if barFrame then
            barFrame:ClearAllPoints()
            barFrame:SetPoint("CENTER", UIParent, "CENTER", x, y)
        end
    end,
    GetEncounterData = function()
        local result = {}
        if currentZoneID and ZONE_DATA[currentZoneID] then
            local zoneData = ZONE_DATA[currentZoneID]
            if zoneData.encounters then
                for encID, encData in pairs(zoneData.encounters) do
                    result[encID] = {
                        name = encData.name or "Unknown",
                        watches = encData.watches or {},
                    }
                end
            end
        end
        return result
    end,
}

-- ════════════════════════════════════════════════════════════
-- TAUNT SWAP TRACKER
-- Tracks tank debuffs that require taunt swaps in raid
-- ════════════════════════════════════════════════════════════

-- ── State ──────────────────────────────────────────────────────────────────────
local trackedTauntDebuffs = {}   -- list of {spellId, stackThreshold, sound, soundIsID,
                                 --          alertTexture, alertX, alertY, alertSize,
                                 --          alertBarWidth, alertDuration, alertMode,
                                 --          glowEnabled, enabled, encounterID, name}

-- Map:  spellId -> { unit, stacks, alertKey, overlayFrame }
local activeDebuffState   = {}

-- Visual overlay pool (shared approach — create our own small pool)
local TSWAP_POOL_SIZE  = 6
local tswapAlertPool   = {}
local tswapBarPool     = {}
local tswapOverlays    = {}     -- alertKey -> frame (icon or bar)
local tswapGlowFrames  = {}     -- alertKey -> glow frame

local tauntSwapEnabled = true

-- Expose for UI and profile save/load
API.trackedTauntDebuffs  = trackedTauntDebuffs
API.tauntSwapEnabled     = tauntSwapEnabled

-- ── Overlay / bar pool ────────────────────────────────────────────────────────
local function CreateTSwapIconFrame(i)
    local f = CreateFrame("Frame", "RogUITSwapIcon"..i, UIParent)
    f:SetFrameStrata("FULLSCREEN_DIALOG"); f:SetFrameLevel(110)
    f:SetSize(64, 64); f:SetPoint("CENTER", UIParent, "CENTER", 0, 0); f:Hide()
    local tex = f:CreateTexture(nil, "ARTWORK", nil, 7); tex:SetAllPoints(f)
    tex:SetTexCoord(0.08, 0.92, 0.08, 0.92); f.tex = tex
    local cd = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
    cd:SetAllPoints(f); cd:SetDrawEdge(false); cd:SetHideCountdownNumbers(false); f.cooldown = cd
    -- Stack count label
    local stackStr = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    stackStr:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -2, 2)
    stackStr:SetFont(stackStr:GetFont(), 14, "OUTLINE")
    stackStr:SetTextColor(1, 0.2, 0.2, 1)
    f.stackStr = stackStr
    f:SetScript("OnShow", function(self) self:SetAlpha(0); UIFrameFadeIn(self, 0.15, 0, 1) end)
    f.sourceUnit = nil
    return f
end

local function CreateTSwapBarFrame(i)
    local f = CreateFrame("Frame", "RogUITSwapBar"..i, UIParent)
    f:SetFrameStrata("FULLSCREEN_DIALOG"); f:SetFrameLevel(110)
    f:SetSize(200, 26); f:SetPoint("CENTER", UIParent, "CENTER", 0, 0); f:Hide()

    local border = f:CreateTexture(nil, "BACKGROUND", nil, -1)
    border:SetAllPoints(f); border:SetColorTexture(0, 0, 0, 0.9); f.border = border

    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
    bg:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)
    bg:SetColorTexture(0.05, 0.05, 0.05, 0.85); f.bg = bg

    local bar = CreateFrame("StatusBar", nil, f)
    bar:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
    bar:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)
    local barTex = bar:CreateTexture(nil, "ARTWORK"); barTex:SetColorTexture(1, 1, 1, 1)
    bar:SetStatusBarTexture(barTex); bar:SetMinMaxValues(0, 1); bar:SetValue(1)
    bar:SetStatusBarColor(1, 0.2, 0.2, 1); f.bar = bar; f.barTex = barTex

    local gloss = f:CreateTexture(nil, "OVERLAY")
    gloss:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
    gloss:SetPoint("TOPRIGHT", f, "TOPRIGHT", -1, 0)
    gloss:SetHeight(4); gloss:SetColorTexture(1, 1, 1, 0.08); f.gloss = gloss

    local iconBg = f:CreateTexture(nil, "ARTWORK")
    iconBg:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
    iconBg:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 1, 1)
    iconBg:SetWidth(24); iconBg:SetColorTexture(0, 0, 0, 0.5); f.iconBg = iconBg

    local icon = f:CreateTexture(nil, "ARTWORK", nil, 1); icon:SetSize(22, 22)
    icon:SetPoint("CENTER", iconBg, "CENTER", 0, 0)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92); f.icon = icon

    local sep = f:CreateTexture(nil, "OVERLAY")
    sep:SetPoint("TOPLEFT", f, "TOPLEFT", 25, -1)
    sep:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 25, 1)
    sep:SetWidth(1); sep:SetColorTexture(0, 0, 0, 0.6); f.sep = sep

    local nameStr = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    nameStr:SetPoint("LEFT", f, "LEFT", 32, 0)
    nameStr:SetPoint("RIGHT", f, "RIGHT", -50, 0)
    nameStr:SetJustifyH("LEFT")
    nameStr:SetFont(nameStr:GetFont(), 11, "OUTLINE")
    nameStr:SetTextColor(1, 1, 1, 1); f.nameStr = nameStr

    local stackStr = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    stackStr:SetPoint("RIGHT", f, "RIGHT", -4, 0)
    stackStr:SetJustifyH("RIGHT")
    stackStr:SetFont(stackStr:GetFont(), 13, "OUTLINE")
    stackStr:SetTextColor(1, 0.3, 0.3, 1); f.stackStr = stackStr

    f:SetAlpha(1)
    f.sourceUnit = nil
    f.durationTimer = nil
    return f
end

for i = 1, TSWAP_POOL_SIZE do
    tswapAlertPool[i] = CreateTSwapIconFrame(i)
    tswapBarPool[i]   = CreateTSwapBarFrame(i)
end

local function GetFreeIcon()
    for _, f in ipairs(tswapAlertPool) do if not f:IsShown() then return f end end
    tswapAlertPool[1]:Hide(); return tswapAlertPool[1]
end

local function GetFreeBar()
    for _, f in ipairs(tswapBarPool) do if not f:IsShown() then return f end end
    tswapBarPool[1]:Hide(); return tswapBarPool[1]
end

local function ReleaseTSwapOverlay(alertKey)
    if not tswapOverlays[alertKey] then return end
    local f = tswapOverlays[alertKey]
    if f.durationTimer then f.durationTimer:Cancel(); f.durationTimer = nil end
    f:Hide()
    tswapOverlays[alertKey] = nil
    local gf = tswapGlowFrames[alertKey]
    if gf then gf:HideGlow() end
end

local function ShowTSwapOverlay(debuff, spellName, stacks)
    local alertKey = tonumber(debuff.spellId) or 0
    if alertKey == 0 then return end

    -- Release old overlay if already shown (stack count update)
    if tswapOverlays[alertKey] then
        local old = tswapOverlays[alertKey]
        if old.durationTimer then old.durationTimer:Cancel(); old.durationTimer = nil end
        old:Hide()
        tswapOverlays[alertKey] = nil
    end

    local ox = tonumber(debuff.alertX) or 0
    local oy = tonumber(debuff.alertY) or 0

    if debuff.alertMode == "bar" then
        local sz   = tonumber(debuff.alertSize)    or 26
        local barW = tonumber(debuff.alertBarWidth) or 200
        local f = GetFreeBar()
        f:SetSize(barW, sz); f:ClearAllPoints()
        f:SetPoint("CENTER", UIParent, "CENTER", ox, oy)
        f:SetAlpha(1)
        f.bar:SetStatusBarColor(1, 0.2, 0.2, 1)
        f.nameStr:SetText(spellName)
        f.stackStr:SetText(stacks .. (tonumber(debuff.stackThreshold) > 0 and ("/"..debuff.stackThreshold) or ""))
        local iconTex = debuff.alertTexture
        if not iconTex or iconTex == "" or iconTex == "spell_icon" then
            if debuff.spellId and debuff.spellId > 0 then
                local info = C_Spell.GetSpellInfo(debuff.spellId)
                iconTex = info and info.iconID or "Interface\\Icons\\INV_Misc_QuestionMark"
            end
        end
        f.icon:SetTexture(iconTex or "Interface\\Icons\\INV_Misc_QuestionMark")
        f:Show()
        tswapOverlays[alertKey] = f

        local dur = tonumber(debuff.alertDuration) or 5
        if dur > 0 then
            if f.durationTimer then f.durationTimer:Cancel() end
            f.durationTimer = C_Timer.NewTimer(dur, function()
                ReleaseTSwapOverlay(alertKey)
            end)
        end
        return f
    else
        local sz = tonumber(debuff.alertSize) or 64
        local f = GetFreeIcon()
        f:SetSize(sz, sz); f:ClearAllPoints()
        f:SetPoint("CENTER", UIParent, "CENTER", ox, oy)
        f:SetAlpha(1)
        local iconTex = debuff.alertTexture
        if not iconTex or iconTex == "" or iconTex == "spell_icon" then
            if debuff.spellId and debuff.spellId > 0 then
                local info = C_Spell.GetSpellInfo(debuff.spellId)
                iconTex = info and info.iconID or "Interface\\Icons\\INV_Misc_QuestionMark"
            end
        end
        f.tex:SetTexture(iconTex or "Interface\\Icons\\INV_Misc_QuestionMark")
        f.stackStr:SetText(stacks .. (tonumber(debuff.stackThreshold) > 0 and ("/"..debuff.stackThreshold) or ""))
        f:Show()
        tswapOverlays[alertKey] = f

        local dur = tonumber(debuff.alertDuration) or 5
        if dur > 0 then
            if f.durationTimer then f.durationTimer:Cancel() end
            f.durationTimer = C_Timer.NewTimer(dur, function()
                ReleaseTSwapOverlay(alertKey)
            end)
        end
        return f
    end
end

-- ── Glow ──────────────────────────────────────────────────────────────────────
local function CreateTSwapGlow(r, g, b)
    local glow = CreateFrame("Frame", nil, UIParent)
    glow:SetFrameStrata("FULLSCREEN_DIALOG"); glow:SetFrameLevel(200)
    glow:SetSize(64, 64); glow:Hide()
    local function makeEdge(pt, relPt, w, h)
        local t = glow:CreateTexture(nil, "OVERLAY")
        t:SetTexture("Interface\\SpellActivationOverlay\\IconAlert")
        t:SetTexCoord(0, 1, 0, 0.5); t:SetVertexColor(r, g, b, 0.85); t:SetSize(w, h)
        t:SetPoint(pt, glow, relPt, 0, 0)
    end
    makeEdge("TOP","TOP",64,16); makeEdge("BOTTOM","BOTTOM",64,16)
    makeEdge("LEFT","LEFT",16,64); makeEdge("RIGHT","RIGHT",16,64)
    local ag = glow:CreateAnimationGroup(); ag:SetLooping("BOUNCE")
    local anim = ag:CreateAnimation("Alpha"); anim:SetFromAlpha(0.4); anim:SetToAlpha(1.0)
    anim:SetDuration(0.6); anim:SetSmoothing("IN_OUT"); glow.animGroup = ag
    function glow:ShowGlow(anchor)
        self:ClearAllPoints()
        if anchor and anchor.IsShown and anchor:IsShown() then
            self:SetParent(anchor); self:SetAllPoints(anchor)
        else
            self:SetParent(UIParent); self:SetPoint("CENTER", UIParent, "CENTER", 0, -100); self:SetSize(64, 64)
        end
        self:Show(); self.animGroup:Play()
    end
    function glow:HideGlow() self.animGroup:Stop(); self:Hide() end
    return glow
end

local function GetOrCreateGlow(alertKey)
    if tswapGlowFrames[alertKey] then return tswapGlowFrames[alertKey] end
    local gf = CreateTSwapGlow(1, 0.2, 0.2)
    tswapGlowFrames[alertKey] = gf
    return gf
end

-- ── Check and alert ───────────────────────────────────────────────────────────
local function CheckTauntDebuff(debuff)
    if not debuff or not debuff.spellId or debuff.spellId == 0 then return end
    if debuff.enabled == false then return end
    
    local sid = tonumber(debuff.spellId) or 0
    local alertKey = sid

    -- Filter out tracking if it belongs to an encounter we are not currently in
    local requiredEnc = debuff.encounterID or spellToEncounter[sid]
    if requiredEnc and currentEncounterID ~= requiredEnc then
        if activeDebuffState[alertKey] then
            activeDebuffState[alertKey] = nil
            ReleaseTSwapOverlay(alertKey)
        end
        return
    end

    local threshold = tonumber(debuff.stackThreshold) or 5
    local stacks = 0
    local hasAura = false

    if UnitExists("player") then
        local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, sid)
        if ok and aura then 
            stacks = aura.applications or 1 
            hasAura = true
        end
    end

    if hasAura then
        local prev = activeDebuffState[alertKey]
        local wasActive = prev and prev.alertFired

        -- Threshold of 0 means alert on ANY stack; otherwise only at threshold
        local shouldAlert = (threshold == 0) or (stacks >= threshold)

        if shouldAlert then
            if not wasActive then
                -- Fire alert
                activeDebuffState[alertKey] = { stacks = stacks, unit = "player", alertFired = true }
                local spellName = ""
                local ok, sinfo = pcall(C_Spell.GetSpellInfo, sid)
                if ok and sinfo then spellName = sinfo.name or "" end
                if debuff.sound then API.PlayCustomSound(debuff.sound, debuff.soundIsID) end
                local overlay = ShowTSwapOverlay(debuff, spellName, stacks)
                if overlay and debuff.glowEnabled then
                    local gf = GetOrCreateGlow(alertKey); gf:ShowGlow(overlay)
                end
            else
                -- Already alerted — just refresh stack count label on existing overlay
                local f = tswapOverlays[alertKey]
                if f and f.stackStr then
                    f.stackStr:SetText(stacks .. (threshold > 0 and ("/"..threshold) or ""))
                    f.stackStr:Show()
                end
                activeDebuffState[alertKey].stacks = stacks
            end
        else
            -- Below threshold: make sure previous sub-threshold alerts are dismissed
            if wasActive then
                activeDebuffState[alertKey] = { stacks = stacks, unit = "player", alertFired = false }
                ReleaseTSwapOverlay(alertKey)
            end
        end
    else
        -- Debuff gone
        if activeDebuffState[alertKey] then
            activeDebuffState[alertKey] = nil
            ReleaseTSwapOverlay(alertKey)
        end
    end
end

local function CheckAllTauntDebuffs()
    for _, debuff in ipairs(trackedTauntDebuffs) do
        CheckTauntDebuff(debuff)
    end
end
API.CheckAllTauntDebuffs = CheckAllTauntDebuffs

-- ── Profile save / load ───────────────────────────────────────────────────────
local function OnSaveProfile(profile)
    profile.trackedTauntDebuffs = trackedTauntDebuffs
    profile.tauntSwapEnabled    = tauntSwapEnabled
    if RogUIDB then
        RogUIDB.trackedTauntDebuffs = trackedTauntDebuffs
        RogUIDB.tauntSwapEnabled    = tauntSwapEnabled
    end
end

local function OnLoadProfile(profile)
    for k in pairs(trackedTauntDebuffs) do trackedTauntDebuffs[k] = nil end
    
    local savedMap = {}
    for _, v in ipairs(profile.trackedTauntDebuffs or {}) do
        if v.spellId then savedMap[v.spellId] = v end
    end
    
    -- Sync with ZONE_DATA so TauntSwap settings auto-populate for UI & Layout Mode
    for zID, zData in pairs(ZONE_DATA) do
        for eID, eData in pairs(zData.encounters) do
            for _, w in ipairs(eData.watches) do
                if w.type == "debuff" then
                    if savedMap[w.spellID] then
                        local item = savedMap[w.spellID]
                        item.encounterID = eID
                        table.insert(trackedTauntDebuffs, item)
                        savedMap[w.spellID] = nil
                    else
                        table.insert(trackedTauntDebuffs, {
                            spellId = w.spellID,
                            enabled = true,
                            stackThreshold = w.defaultStacks or 5,
                            alertMode = "icon",
                            alertSize = 64,
                            alertTexture = "spell_icon",
                            encounterID = eID
                        })
                    end
                end
            end
        end
    end
    
    -- Append any custom ones
    for _, v in pairs(savedMap) do
        table.insert(trackedTauntDebuffs, v)
    end

    local saved = profile.tauntSwapEnabled
    if saved == nil then saved = RogUIDB and RogUIDB.tauntSwapEnabled end
    tauntSwapEnabled = (saved ~= false)   -- default true
    API.tauntSwapEnabled = tauntSwapEnabled
end

API.RegisterProfileCallbacks(OnSaveProfile, OnLoadProfile)

-- ── Combat ticker ──────────────────────────────────────────────────────────────
local combatTicker = nil

local function StartCombatTicker()
    if combatTicker then return end
    combatTicker = C_Timer.NewTicker(0.25, CheckAllTauntDebuffs)
end

local function StopCombatTicker()
    if combatTicker then combatTicker:Cancel(); combatTicker = nil end
end

API.RegisterEvent("TauntSwap", "PLAYER_LOGIN", function()
    C_Timer.After(2, CheckAllTauntDebuffs)
end)

API.RegisterEvent("TauntSwap", "UNIT_AURA", function(unit)
    if tauntSwapEnabled then
        CheckAllTauntDebuffs()
    end
end)

API.RegisterEvent("TauntSwap", "PLAYER_REGEN_DISABLED", function()
    if tauntSwapEnabled then StartCombatTicker() end
end)

API.RegisterEvent("TauntSwap", "PLAYER_REGEN_ENABLED", function()
    StopCombatTicker()
    C_Timer.After(0.5, function()
        for alertKey in pairs(tswapOverlays) do
            ReleaseTSwapOverlay(alertKey)
        end
        for k in pairs(activeDebuffState) do activeDebuffState[k] = nil end
    end)
end)

-- ── Layout mode handles ───────────────────────────────────────────────────────
API.RegisterLayoutHandles(function()
    local handles = {}
    for idx, debuff in ipairs(trackedTauntDebuffs) do
        local ox = debuff.alertX or 0; local oy = debuff.alertY or 0
        local iconTex = debuff.alertTexture
        
        -- Default to the spell icon if unassigned/blank
        if not iconTex or iconTex == "" or iconTex == "spell_icon" then
            if debuff.spellId and debuff.spellId > 0 then
                local info = C_Spell.GetSpellInfo(debuff.spellId)
                iconTex = info and info.iconID or "Interface\\Icons\\INV_Misc_QuestionMark"
            else
                iconTex = "Interface\\Icons\\INV_Misc_QuestionMark"
            end
        end

        local spellName = "Unknown"
        if debuff.spellId and debuff.spellId > 0 then
            local info = C_Spell.GetSpellInfo(debuff.spellId)
            spellName = info and info.name or ("ID "..debuff.spellId)
        end
        local capturedDebuff = debuff; local capturedIdx = idx
        local isBar = (debuff.alertMode == "bar")
        local alertKey = tonumber(debuff.spellId) or 0
        local liveFrame = (alertKey > 0) and tswapOverlays[alertKey] or nil
        
        table.insert(handles, {
            label        = "TauntSwap: "..spellName,
            iconTex      = iconTex,
            ox = ox, oy = oy,
            liveFrameRef = liveFrame,
            saveCallback = function(nx, ny)
                capturedDebuff.alertX = nx; capturedDebuff.alertY = ny
                local xBox = _G["CM_TSwapAlertX"..capturedIdx]
                local yBox = _G["CM_TSwapAlertY"..capturedIdx]
                if xBox then xBox:SetText(tostring(nx)) end
                if yBox then yBox:SetText(tostring(ny)) end
                if RogUIDB then API.SaveSpecProfile() end
            end,
            resizeCallback = function(nw, nh)
                nw = math.max(40, math.floor(nw + 0.5))
                nh = math.max(8,  math.floor(nh + 0.5))
                if isBar then
                    capturedDebuff.alertBarWidth = nw
                    capturedDebuff.alertSize     = nh
                    local wBox = _G["CM_TSwapAlertBarWidth"..capturedIdx]
                    local hBox = _G["CM_TSwapAlertSize"..capturedIdx]
                    if wBox then wBox:SetText(tostring(nw)) end
                    if hBox then hBox:SetText(tostring(nh)) end
                else
                    local sz = math.max(nw, nh)
                    capturedDebuff.alertSize = sz
                    local szBox = _G["CM_TSwapAlertSize"..capturedIdx]
                    if szBox then szBox:SetText(tostring(sz)) end
                end
                if RogUIDB then API.SaveSpecProfile() end
            end,
            previewFunc = function()
                return ShowTSwapOverlay({
                    alertTexture = debuff.alertTexture, spellId = debuff.spellId,
                    alertMode = debuff.alertMode, alertBarWidth = debuff.alertBarWidth,
                    alertSize = debuff.alertSize, alertDuration = 9999,
                    alertX = debuff.alertX or 0, alertY = debuff.alertY or 0,
                    stackThreshold = debuff.stackThreshold,
                }, spellName, tonumber(debuff.stackThreshold) or 1)
            end,
        })
    end
    return handles
end)