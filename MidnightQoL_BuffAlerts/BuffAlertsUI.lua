-- ============================================================
-- MidnightQoL_BuffAlerts / BuffAlertsUI.lua
-- Alerts tab UI: aura entry widgets, add/remove/save.
-- Registers into Core's tab system via API.RegisterTab().
-- ============================================================

local API = MidnightQoLAPI

-- References to the shared lists (same table objects from BuffAlerts.lua)
local trackedBuffs     = API.trackedBuffs
local trackedDebuffs   = API.trackedDebuffs
local trackedExternals = API.trackedExternals

-- ── Content frame (hosted inside Core's scroll frame) ─────────────────────────
local contentFrame = CreateFrame("Frame", "MidnightQoLAlertsFrame", UIParent)
contentFrame:SetSize(620, 1); contentFrame:Hide()

-- ── Per-type entry pool ────────────────────────────────────────────────────────
local auraEntryPool = {buff={}, debuff={}, external={}}

local function CreateAuraEntry(parentFrame, slotIndex, auraType)
    local ef = CreateFrame("Frame","BuffAlertEntry"..auraType..slotIndex, parentFrame)
    ef:SetSize(640,115); ef:Hide()

    local sep = ef:CreateTexture(nil,"BACKGROUND"); sep:SetColorTexture(0.3,0.3,0.3,0.4)
    sep:SetPoint("TOPLEFT",0,0); sep:SetSize(640,1)

    local enableCb = CreateFrame("CheckButton","BuffAlertEnableCheckbox"..auraType..slotIndex,ef,"UICheckButtonTemplate")
    enableCb:SetSize(20,20); enableCb:SetPoint("TOPLEFT",0,-2)

    local presetLabel = ef:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    presetLabel:SetPoint("TOPLEFT",22,-2); presetLabel:SetText("Spell:")

    local idLabel = ef:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    idLabel:SetPoint("TOPLEFT",222,-2); idLabel:SetText("ID:")

    local idInput = CreateFrame("EditBox","BuffAlertIDInput"..auraType..slotIndex,ef,"InputBoxTemplate")
    idInput:SetSize(60,20); idInput:SetPoint("TOPLEFT",240,-4)
    idInput:SetAutoFocus(false); idInput:SetMaxLetters(50)

    local spellDropdown = API.CreateSpellSelectorButton(ef,"BuffAlertSpellDropdown"..auraType..slotIndex,auraType,idInput)
    spellDropdown:SetPoint("TOPLEFT",62,-4); spellDropdown.auraType = auraType

    local soundLabel = ef:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    soundLabel:SetPoint("TOPLEFT",0,-28); soundLabel:SetText("Sound:")

    local soundDropdown = API.CreateSoundSelectorButton(ef,"BuffAlertSoundDropdown"..auraType..slotIndex)
    soundDropdown:SetPoint("TOPLEFT",40,-28); soundDropdown.auraType = auraType

    local texLabel = ef:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    texLabel:SetPoint("TOPLEFT",0,-54); texLabel:SetText("Alert Img:")

    local texInput = CreateFrame("EditBox","BuffAlertTexInput"..auraType..slotIndex,ef)
    texInput:Hide(); texInput:SetAutoFocus(false); texInput:SetMaxLetters(200)

    local imgBtn = API.CreateImageSelectorButton(ef,"BuffAlertImgBtn"..auraType..slotIndex,texInput,
        function() return tonumber(idInput:GetText()) end)
    imgBtn:SetPoint("TOPLEFT",55,-56)

    local previewBtn = CreateFrame("Button",nil,ef,"GameMenuButtonTemplate")
    previewBtn:SetSize(50,18); previewBtn:SetPoint("TOPLEFT",200,-56); previewBtn:SetText("Preview")
    previewBtn:SetScript("OnClick",function()
        local img = imgBtn.selectedImage
        if img and img ~= "" then API.ShowAlertOverlay({alertTexture=img,alertSize=80,alertDuration=2},"preview") end
    end)

    local xLabel = ef:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    xLabel:SetPoint("TOPLEFT",284,-54); xLabel:SetText("X:")
    local xInput = CreateFrame("EditBox","BuffAlertTexX"..auraType..slotIndex,ef,"InputBoxTemplate")
    xInput:SetSize(38,18); xInput:SetPoint("TOPLEFT",296,-56); xInput:SetAutoFocus(false); xInput:SetMaxLetters(6)

    local yLabel = ef:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    yLabel:SetPoint("TOPLEFT",338,-54); yLabel:SetText("Y:")
    local yInput = CreateFrame("EditBox","BuffAlertTexY"..auraType..slotIndex,ef,"InputBoxTemplate")
    yInput:SetSize(38,18); yInput:SetPoint("TOPLEFT",350,-56); yInput:SetAutoFocus(false); yInput:SetMaxLetters(6)

    local szLabel = ef:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    szLabel:SetPoint("TOPLEFT",392,-54); szLabel:SetText("H:")
    local szInput = CreateFrame("EditBox","BuffAlertTexSize"..auraType..slotIndex,ef,"InputBoxTemplate")
    szInput:SetSize(30,18); szInput:SetPoint("TOPLEFT",405,-56); szInput:SetAutoFocus(false); szInput:SetMaxLetters(4)

    local barWLabel = ef:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    barWLabel:SetPoint("TOPLEFT",438,-54); barWLabel:SetText("W:")
    local barWInput = CreateFrame("EditBox","BuffAlertBarWidth"..auraType..slotIndex,ef,"InputBoxTemplate")
    barWInput:SetSize(38,18); barWInput:SetPoint("TOPLEFT",450,-56); barWInput:SetAutoFocus(false); barWInput:SetMaxLetters(5)

    local durLabel = ef:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    durLabel:SetPoint("TOPLEFT",492,-54); durLabel:SetText("Dur:")
    local durInput = CreateFrame("EditBox","BuffAlertTexDur"..auraType..slotIndex,ef,"InputBoxTemplate")
    durInput:SetSize(35,18); durInput:SetPoint("TOPLEFT",510,-56); durInput:SetAutoFocus(false); durInput:SetMaxLetters(4)
    local durHint = ef:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    durHint:SetPoint("TOPLEFT",549,-54); durHint:SetTextColor(0.5,0.5,0.5,1); durHint:SetText("s (0=∞)")

    local glowCheck = CreateFrame("CheckButton","BuffAlertGlow"..auraType..slotIndex,ef,"UICheckButtonTemplate")
    glowCheck:SetSize(20,20); glowCheck:SetPoint("TOPLEFT",0,-78)
    local glowLabel = ef:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    glowLabel:SetPoint("TOPLEFT",22,-78); glowLabel:SetText("Glow on icon")

    local hideNativeCheck = CreateFrame("CheckButton","BuffAlertHideNative"..auraType..slotIndex,ef,"UICheckButtonTemplate")
    hideNativeCheck:SetSize(20,20); hideNativeCheck:SetPoint("TOPLEFT",140,-78)
    local hideNativeLabel = ef:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    hideNativeLabel:SetPoint("TOPLEFT",162,-78); hideNativeLabel:SetText("Hide native icon")

    -- Alert mode: Icon or Bar
    local modeLabel = ef:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    modeLabel:SetPoint("TOPLEFT",290,-78); modeLabel:SetText("Mode:")

    local iconModeBtn = CreateFrame("CheckButton","BuffAlertModeIcon"..auraType..slotIndex,ef,"UIRadioButtonTemplate")
    iconModeBtn:SetSize(20,20); iconModeBtn:SetPoint("TOPLEFT",328,-78)
    local iconModeLbl = ef:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    iconModeLbl:SetPoint("LEFT",iconModeBtn,"RIGHT",2,0); iconModeLbl:SetText("Icon")

    local barModeBtn = CreateFrame("CheckButton","BuffAlertModeBar"..auraType..slotIndex,ef,"UIRadioButtonTemplate")
    barModeBtn:SetSize(20,20); barModeBtn:SetPoint("TOPLEFT",390,-78)
    local barModeLbl = ef:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    barModeLbl:SetPoint("LEFT",barModeBtn,"RIGHT",2,0); barModeLbl:SetText("Bar")

    -- Radio toggle logic
    iconModeBtn:SetScript("OnClick", function()
        iconModeBtn:SetChecked(true); barModeBtn:SetChecked(false)
    end)
    barModeBtn:SetScript("OnClick", function()
        barModeBtn:SetChecked(true); iconModeBtn:SetChecked(false)
    end)
    iconModeBtn:SetChecked(true)  -- default

    local tagText = ef:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    tagText:SetPoint("TOPRIGHT",-10,-5)

    local testBtn = CreateFrame("Button",nil,ef,"GameMenuButtonTemplate")
    testBtn:SetSize(50,20); testBtn:SetPoint("TOPRIGHT",-58,-4); testBtn:SetText("Test")
    testBtn:SetScript("OnClick",function()
        if soundDropdown.selectedSound then
            API.PlayCustomSound(soundDropdown.selectedSound, soundDropdown.selectedSoundIsID)
        end
    end)

    local removeBtn = CreateFrame("Button",nil,ef,"GameMenuButtonTemplate")
    removeBtn:SetSize(50,20); removeBtn:SetPoint("TOPRIGHT",-4,-4); removeBtn:SetText("Remove")
    removeBtn:SetScript("OnClick",function(self)
        if auraType=="buff"    then table.remove(trackedBuffs,    self.dataIndex)
        elseif auraType=="debuff" then table.remove(trackedDebuffs,  self.dataIndex)
        else                       table.remove(trackedExternals, self.dataIndex) end
        API.RefreshAuraListUI()
    end)

    return {
        frame=ef, enableCheckbox=enableCb, spellDropdown=spellDropdown, idInput=idInput,
        soundDropdown=soundDropdown, texInput=texInput, imgBtn=imgBtn,
        xInput=xInput, yInput=yInput, szInput=szInput, barWInput=barWInput, durInput=durInput,
        tagText=tagText, removeBtn=removeBtn, glowCheck=glowCheck, hideNativeCheck=hideNativeCheck,
        iconModeBtn=iconModeBtn, barModeBtn=barModeBtn,
    }
end

local function GetPooledEntry(auraType, slotIndex)
    local pool = auraEntryPool[auraType]
    if not pool[slotIndex] then pool[slotIndex] = CreateAuraEntry(contentFrame, slotIndex, auraType) end
    return pool[slotIndex]
end

local function RefreshAuraListUI()
    -- Ensure we always have the latest table references from API
    trackedBuffs     = API.trackedBuffs     or trackedBuffs     or {}
    trackedDebuffs   = API.trackedDebuffs   or trackedDebuffs   or {}
    trackedExternals = API.trackedExternals or trackedExternals or {}

    local rowCount = 0
    local function DrawSection(list, typeLabel, typeColor)
        if not list then return end   -- guard: table not ready yet
        local pool = auraEntryPool[typeLabel:lower()]
        for dataIndex, aura in ipairs(list) do
            rowCount = rowCount + 1
            local entry = GetPooledEntry(typeLabel:lower(), dataIndex)
            entry.frame:ClearAllPoints()
            entry.frame:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 0, -(rowCount-1)*120)
            entry.removeBtn.dataIndex = dataIndex
            entry.tagText:SetText(typeColor..typeLabel.."|r")
            entry.idInput:SetText(tostring(aura.spellId or 0))
            entry.spellDropdown.auraType   = typeLabel:lower()
            entry.spellDropdown.idInputRef = entry.idInput
            entry.soundDropdown:SetSelectedSound(aura.sound, aura.soundIsID)
            entry.enableCheckbox:SetChecked(aura.enabled ~= false)
            entry.imgBtn:SetSelectedImage(aura.alertTexture or nil)
            entry.texInput:SetText(aura.alertTexture and tostring(aura.alertTexture) or "")
            entry.xInput:SetText(aura.alertX   and tostring(aura.alertX)   or "")
            entry.yInput:SetText(aura.alertY   and tostring(aura.alertY)   or "")
            entry.szInput:SetText(aura.alertSize     and tostring(aura.alertSize)     or "")
            local barWIn = _G["BuffAlertBarWidth"..typeLabel:lower()..dataIndex]
            if barWIn then barWIn:SetText(aura.alertBarWidth and tostring(aura.alertBarWidth) or "") end
            entry.durInput:SetText(tostring(aura.alertDuration or 0))
            if entry.glowCheck      then entry.glowCheck:SetChecked(aura.glowEnabled    == true) end
            if entry.hideNativeCheck then entry.hideNativeCheck:SetChecked(aura.hideNativeIcon == true) end
            -- Alert mode radio
            if entry.iconModeBtn and entry.barModeBtn then
                local isBar = (aura.alertMode == "bar")
                entry.iconModeBtn:SetChecked(not isBar)
                entry.barModeBtn:SetChecked(isBar)
            end
            local sname = (aura.spellId and aura.spellId>0)
                and (C_Spell.GetSpellInfo(aura.spellId) and C_Spell.GetSpellInfo(aura.spellId).name)
                or "Select Spell"
            entry.spellDropdown:SetText(aura.name or sname)
            entry.frame:Show()
        end
        for slotIndex = #list+1, #pool do pool[slotIndex].frame:Hide() end
    end
    DrawSection(trackedBuffs,     "BUFF",     "|cFF00FF00")
    --[[ DEBUFFS/EXTERNALS DISABLED — tracking not yet implemented
    DrawSection(trackedDebuffs,   "DEBUFF",   "|cFFFF0000")
    DrawSection(trackedExternals, "EXTERNAL", "|cFF00CCFF")
    --]]
    contentFrame:SetHeight(math.max(200, rowCount*120))
end
API.RefreshAuraListUI = RefreshAuraListUI

-- ── Save callback: reads UI widgets back into tracked lists ───────────────────
local function HarvestUIValues()
    local DEFAULT_SOUND_ID = 12743
    local function harvestList(list, auraType)
        for index, aura in ipairs(list) do
            local t = auraType
            local input = _G["BuffAlertIDInput"..t..index]
            if input then
                if t == "external" then
                    local raw = input:GetText()
                    if raw:find(",") then
                        aura.spellId=0; aura.spellIds={}
                        for idStr in raw:gmatch("[^,]+") do
                            local n=tonumber(idStr:match("^%s*(.-)%s*$"))
                            if n then table.insert(aura.spellIds,n) end
                        end
                    else aura.spellId=tonumber(raw) or 0; aura.spellIds=nil end
                else aura.spellId=tonumber(input:GetText()) or 0 end
            end
            local enableCb=_G["BuffAlertEnableCheckbox"..t..index]; if enableCb then aura.enabled=enableCb:GetChecked() end
            -- Propagate isLustTracker from spell dropdown selection
            local spellDropRef = _G["BuffAlertSpellDropdownBUFF"..index]
            if spellDropRef and spellDropRef.selectedSpellIsLust ~= nil then
                aura.isLustTracker = spellDropRef.selectedSpellIsLust
            end
            local imgBtnRef=_G["BuffAlertImgBtn"..t..index]
            local rawImg=imgBtnRef and imgBtnRef.selectedImage
            aura.alertTexture=(rawImg and rawImg~="" and tostring(rawImg)) or nil
            local xIn=_G["BuffAlertTexX"..t..index];    if xIn  then aura.alertX=tonumber(xIn:GetText()) or 0 end
            local yIn=_G["BuffAlertTexY"..t..index];    if yIn  then aura.alertY=tonumber(yIn:GetText()) or 0 end
            local szIn=_G["BuffAlertTexSize"..t..index];   if szIn  then aura.alertSize=tonumber(szIn:GetText()) or 64 end
            local barWIn=_G["BuffAlertBarWidth"..t..index]; if barWIn then aura.alertBarWidth=tonumber(barWIn:GetText()) or 200 end
            local durIn=_G["BuffAlertTexDur"..t..index]; if durIn then aura.alertDuration=tonumber(durIn:GetText()) or 0 end
            local glowCb=_G["BuffAlertGlow"..t..index];        if glowCb  then aura.glowEnabled=glowCb:GetChecked() end
            local hideCb=_G["BuffAlertHideNative"..t..index];  if hideCb  then aura.hideNativeIcon=hideCb:GetChecked() end
            -- Alert mode
            local barModeBtn = _G["BuffAlertModeBar"..t..index]
            if barModeBtn then
                aura.alertMode = barModeBtn:GetChecked() and "bar" or "icon"
            end
            local sd=_G["BuffAlertSoundDropdown"..t..index]
            if sd then
                aura.sound    =sd.selectedSound or DEFAULT_SOUND_ID
                aura.soundIsID=(sd.selectedSound~=nil) and sd.selectedSoundIsID or true
            end
        end
    end
    harvestList(trackedBuffs,     "buff")
    --[[ DEBUFFS/EXTERNALS DISABLED — tracking not yet implemented
    harvestList(trackedDebuffs,   "debuff")
    harvestList(trackedExternals, "external")
    --]]
end
API.HarvestBuffAlertUIValues = HarvestUIValues

-- Hook Core's save button to harvest widget values before saving
local saveBtn = _G["MidnightQoLSaveBtn"]
if saveBtn then saveBtn:HookScript("OnClick", HarvestUIValues) end

-- ── Add buttons ───────────────────────────────────────────────────────────────
-- Parented to mainFrame, anchored above the bottom bar (y=50).
-- Shown only when the Alerts tab is active, hidden otherwise.
local mainFrame = _G["MidnightQoLMainFrame"]

local addBuffBtn = CreateFrame("Button","MidnightQoLAddBuffBtn",mainFrame,"GameMenuButtonTemplate")
addBuffBtn:SetSize(110,25); addBuffBtn:SetText("+ Add Buff"); addBuffBtn:Hide()
addBuffBtn:SetPoint("BOTTOMLEFT", mainFrame, "BOTTOMLEFT", 20, 50)
addBuffBtn:SetScript("OnClick",function()
    trackedBuffs = API.trackedBuffs
    table.insert(trackedBuffs,{spellId=0,sound=nil})
    RefreshAuraListUI()
end)

--[[ DEBUFFS/EXTERNALS DISABLED — tracking not yet implemented
local addDebuffBtn = CreateFrame("Button","MidnightQoLAddDebuffBtn",mainFrame,"GameMenuButtonTemplate")
addDebuffBtn:SetSize(110,25); addDebuffBtn:SetText("+ Add Debuff"); addDebuffBtn:Hide()
addDebuffBtn:SetPoint("LEFT", addBuffBtn, "RIGHT", 6, 0)
addDebuffBtn:SetScript("OnClick",function()
    trackedDebuffs = API.trackedDebuffs
    table.insert(trackedDebuffs,{spellId=0,sound=nil})
    RefreshAuraListUI()
end)

local addExternalBtn = CreateFrame("Button","MidnightQoLAddExternalBtn",mainFrame,"GameMenuButtonTemplate")
addExternalBtn:SetSize(120,25); addExternalBtn:SetText("+ Add External"); addExternalBtn:Hide()
addExternalBtn:SetPoint("LEFT", addDebuffBtn, "RIGHT", 6, 0)
addExternalBtn:SetScript("OnClick",function()
    trackedExternals = API.trackedExternals
    table.insert(trackedExternals,{spellId=0,sound=nil})
    RefreshAuraListUI()
end)
--]]

-- ── Tab registration ───────────────────────────────────────────────────────────
local function OnAlertsTabActivate()
    trackedBuffs     = API.trackedBuffs
    --[[ DEBUFFS/EXTERNALS DISABLED
    trackedDebuffs   = API.trackedDebuffs
    trackedExternals = API.trackedExternals
    --]]
    RefreshAuraListUI()
    addBuffBtn:Show()
    --[[ DEBUFFS/EXTERNALS DISABLED
    addDebuffBtn:Show()
    addExternalBtn:Show()
    --]]
end

local function OnAlertsTabDeactivate()
    addBuffBtn:Hide()
    --[[ DEBUFFS/EXTERNALS DISABLED
    addDebuffBtn:Hide()
    addExternalBtn:Hide()
    --]]
end

-- ── Boss Warning Sound ────────────────────────────────────────────────────────
local bwSection = contentFrame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
bwSection:SetText("|cFFFF8844Boss Warning Sound|r  |cFFAAAAAA(plays when Blizzard's boss popup appears)|r")

local bwSoundDropdown = API.CreateSoundSelectorButton(contentFrame, "MidnightBossWarnSoundBtn")

local bwTestBtn = CreateFrame("Button", nil, contentFrame, "GameMenuButtonTemplate")
bwTestBtn:SetSize(60, 22)
bwTestBtn:SetText("Test")
bwTestBtn:SetScript("OnClick", function()
    local db = BuffAlertDB
    if db and db.bossWarnSound and db.bossWarnSound.sound then
        API.PlayCustomSound(db.bossWarnSound.sound, db.bossWarnSound.soundIsID)
    end
end)

local bwStatusLbl = contentFrame:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
bwStatusLbl:SetTextColor(0.6, 0.6, 0.6, 1)

local function RefreshBossWarnUI()
    -- Position relative to bottom of aura list — use a fixed offset from top
    -- We anchor to contentFrame bottom since aura list is dynamic
    bwSection:ClearAllPoints()
    bwSection:SetPoint("BOTTOMLEFT", contentFrame, "BOTTOMLEFT", 8, 72)

    bwSoundDropdown:ClearAllPoints()
    bwSoundDropdown:SetPoint("BOTTOMLEFT", contentFrame, "BOTTOMLEFT", 8, 44)

    bwTestBtn:ClearAllPoints()
    bwTestBtn:SetPoint("LEFT", bwSoundDropdown, "RIGHT", 8, 0)

    bwStatusLbl:ClearAllPoints()
    bwStatusLbl:SetPoint("LEFT", bwTestBtn, "RIGHT", 10, 0)
    bwStatusLbl:SetText("|cFF00FF00● listening for ENCOUNTER_WARNING|r")

    -- Load saved sound
    local db = BuffAlertDB
    if db and db.bossWarnSound then
        bwSoundDropdown:SetSelectedSound(db.bossWarnSound.sound, db.bossWarnSound.soundIsID)
    end

    -- Save on change
    bwSoundDropdown.onSoundSelected = function(sound, isID)
        BuffAlertDB.bossWarnSound = BuffAlertDB.bossWarnSound or {}
        BuffAlertDB.bossWarnSound.sound    = sound
        BuffAlertDB.bossWarnSound.soundIsID = isID
    end
end

-- Hook into tab activate so the section refreshes and status is current
local _origActivate = OnAlertsTabActivate
OnAlertsTabActivate = function()
    _origActivate()
    RefreshBossWarnUI()
end

API.RegisterTab("Alerts", contentFrame, OnAlertsTabActivate, 80, OnAlertsTabDeactivate, 2) -- priority 2
-- Ensure buttons start hidden (RebuildTabBar activates tab 1/General on load)
OnAlertsTabDeactivate()
