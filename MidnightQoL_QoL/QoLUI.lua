-- ============================================================
-- MidnightQoL_QoL / QoLUI.lua
-- Adds the General tab to Core's tab system.
-- Contains: Feature Toggles, Pet Reminder configure section.
-- (Pull/Break sections added by BarsUI.lua)
-- ============================================================

local API = MidnightQoLAPI

-- ── General tab content frame ─────────────────────────────────────────────────
local generalFrame = CreateFrame("Frame","MidnightQoLGeneralFrame",UIParent)
generalFrame:SetSize(620,600); generalFrame:Hide()

-- ── Helper ────────────────────────────────────────────────────────────────────
local function MakeCheck(name, parent, labelText, anchorFrame, offsetY)
    local chk = CreateFrame("CheckButton", name, parent, "UICheckButtonTemplate")
    chk:SetSize(24,24)
    if anchorFrame then chk:SetPoint("TOPLEFT", anchorFrame, "BOTTOMLEFT", 0, offsetY or -6) end
    local lbl = _G[name.."Text"]
    if lbl then lbl:SetText(labelText) end
    return chk
end

-- ── Section: Feature Toggles ───────────────────────────────────────────────────
local featHeader = generalFrame:CreateFontString(nil,"OVERLAY","GameFontNormalLarge")
featHeader:SetPoint("TOPLEFT",10,-10); featHeader:SetText("|cFFFFD700Features|r")

-- Buff/Debuff Alerts toggle (mirrors the hidden Core checkbox)
local alertsCheck = CreateFrame("CheckButton","CSGenAlertsCheck",generalFrame,"UICheckButtonTemplate")
alertsCheck:SetSize(24,24); alertsCheck:SetPoint("TOPLEFT", featHeader, "BOTTOMLEFT", 0, -6)
local alertsLbl = _G["CSGenAlertsCheckText"]
if alertsLbl then alertsLbl:SetText("Buff/Debuff Alerts") end
alertsCheck:SetScript("OnClick", function(self)
    local cb = API.buffAlertEnabledCheckbox
    if cb then cb:SetChecked(self:GetChecked()); cb:GetScript("OnClick")(cb) end
    if BuffAlertDB then BuffAlertDB.buffDebuffAlertsEnabled = self:GetChecked() end
end)

-- Whisper Indicator toggle
local whisperCheck = CreateFrame("CheckButton","CSGenWhisperCheck",generalFrame,"UICheckButtonTemplate")
whisperCheck:SetSize(24,24); whisperCheck:SetPoint("TOPLEFT", alertsCheck, "BOTTOMLEFT", 0, -4)
local whisperLbl = _G["CSGenWhisperCheckText"]
if whisperLbl then whisperLbl:SetText("Whisper Indicator") end
whisperCheck:SetScript("OnClick", function(self)
    local cb = API.whisperIndicatorEnabledCheckbox
    if cb then cb:SetChecked(self:GetChecked()); cb:GetScript("OnClick")(cb) end
    if API.SetWhisperIndicator then API.SetWhisperIndicator(self:GetChecked()) end
end)

-- Minimap Button toggle
local mmCheck = CreateFrame("CheckButton","CSGenMinimapCheck",generalFrame,"UICheckButtonTemplate")
mmCheck:SetSize(24,24); mmCheck:SetPoint("TOPLEFT", whisperCheck, "BOTTOMLEFT", 0, -4)
local mmLbl = _G["CSGenMinimapCheckText"]
if mmLbl then mmLbl:SetText("Minimap Button") end
mmCheck:SetScript("OnClick", function(self)
    local cb = API.minimapBtnCheckbox
    if cb then cb:SetChecked(self:GetChecked()); cb:GetScript("OnClick")(cb) end
end)

-- Keep mirror checks in sync when hidden Core checkboxes change
if API.minimapBtnCheckbox then
    API.minimapBtnCheckbox:HookScript("OnClick", function(self) mmCheck:SetChecked(self:GetChecked()) end)
end

-- Resource Bars toggle
local resBarsCheck = CreateFrame("CheckButton","CSGenResBarsCheck",generalFrame,"UICheckButtonTemplate")
resBarsCheck:SetSize(24,24); resBarsCheck:SetPoint("TOPLEFT", mmCheck, "BOTTOMLEFT", 0, -4)
local resBarsLbl = _G["CSGenResBarsCheckText"]
if resBarsLbl then resBarsLbl:SetText("Resource Bars") end
resBarsCheck:SetScript("OnClick", function(self)
    local enabled = self:GetChecked()
    if BuffAlertDB then BuffAlertDB.resourceBarsEnabled = enabled end
    local cb = API.resourceBarsEnabledCheckbox
    if cb then
        cb:SetChecked(enabled)
        -- SyncResourceBarsToggle is hooked onto cb via HookScript in ResourceBars.lua;
        -- HookScript handlers fire on SetChecked only if triggered via click, so call rebuild directly.
        if API.RebuildLiveBars then API.RebuildLiveBars() end
    end
end)

-- ── Section: Pet Reminder ─────────────────────────────────────────────────────
local petHeader = generalFrame:CreateFontString(nil,"OVERLAY","GameFontNormalLarge")
petHeader:SetPoint("TOPLEFT", resBarsCheck, "BOTTOMLEFT", 0, -20)
petHeader:SetText("|cFFFFD700Pet Reminder|r")

local petDesc = generalFrame:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
petDesc:SetPoint("TOPLEFT", petHeader, "BOTTOMLEFT", 0, -4)
petDesc:SetText("Reminds Hunters and Warlocks to summon a pet on enter, spec change, and ready check.")

local petEnableCheck = MakeCheck("CSPetReminderCheck", generalFrame, "Enable pet reminder", petDesc, -4)
petEnableCheck:SetScript("OnClick", function(self)
    if BuffAlertDB then BuffAlertDB.petReminderEnabled = self:GetChecked() end
end)

local petMoveTip = generalFrame:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
petMoveTip:SetPoint("TOPLEFT", petEnableCheck, "BOTTOMLEFT", 0, -8)
petMoveTip:SetTextColor(0.7,0.9,1,1); petMoveTip:SetText("To reposition: click |cFFFFD700Edit Layout|r below")

-- Pet sound selector
local petSoundLabel = generalFrame:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
petSoundLabel:SetPoint("TOPLEFT", petEnableCheck, "BOTTOMLEFT", 0, -34)
petSoundLabel:SetText("Alert Sound:")

local petSoundDropdown = API.CreateSoundSelectorButton(generalFrame, "CSPetSoundDropdown")
petSoundDropdown:SetPoint("LEFT", petSoundLabel, "RIGHT", 6, 0)
petSoundDropdown:SetScript("OnClick", function(self)
    if not API.OpenSoundPicker then return end
    API.OpenSoundPicker(self, function(sound)
        self.selectedSound     = sound.path
        self.selectedSoundIsID = sound.isID
        self:SetText(sound.name or "Select Sound")
        if BuffAlertDB then
            BuffAlertDB.petReminderSound      = sound.path
            BuffAlertDB.petReminderSoundIsID  = sound.isID
        end
    end)
end)

local petSoundTestBtn = CreateFrame("Button",nil,generalFrame,"UIPanelButtonTemplate")
petSoundTestBtn:SetSize(50,22); petSoundTestBtn:SetPoint("LEFT", petSoundDropdown, "RIGHT", 6, 0)
petSoundTestBtn:SetText("Test")
petSoundTestBtn:SetScript("OnClick", function()
    if petSoundDropdown.selectedSound then
        API.PlayCustomSound(petSoundDropdown.selectedSound, petSoundDropdown.selectedSoundIsID)
    end
end)

-- ── Sync function (called when General tab is opened) ─────────────────────────
local function SyncGeneralUI()
    if not BuffAlertDB then return end
    alertsCheck:SetChecked(BuffAlertDB.buffDebuffAlertsEnabled ~= false)
    whisperCheck:SetChecked(BuffAlertDB.whisperIndicatorEnabled ~= false)
    mmCheck:SetChecked(BuffAlertDB.minimapBtnShown ~= false)
    resBarsCheck:SetChecked(BuffAlertDB.resourceBarsEnabled ~= false)
    petEnableCheck:SetChecked(BuffAlertDB.petReminderEnabled or false)
    if BuffAlertDB.petReminderSound then
        petSoundDropdown:SetSelectedSound(BuffAlertDB.petReminderSound, BuffAlertDB.petReminderSoundIsID)
    end
    -- Let BarsUI sync its controls too
    if API._barsGeneralSync then API._barsGeneralSync() end
    -- Update spec label
    if API.specInfoLabel then
        local specIndex = GetSpecialization and GetSpecialization()
        local specName  = specIndex and select(2, GetSpecializationInfo(specIndex)) or "Unknown"
        API.specInfoLabel:SetText("Active Spec: |cFFFFD700"..(API.playerClass or "?").." - "..tostring(specName).."|r")
    end
end

-- ── Register as the FIRST tab (General) ───────────────────────────────────────
-- We defer via C_Timer.After(0) to ensure all other PLAYER_LOGIN handlers
-- (including Core's, which initialises BuffAlertDB) have run before we call RegisterTab.
-- TOC Dependencies guarantees Core's Lua runs before ours, so the API exists;
-- we just need DB to be populated.

local qolUIEvents = CreateFrame("Frame")
qolUIEvents:RegisterEvent("PLAYER_LOGIN")
qolUIEvents:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        C_Timer.After(0, function()
            -- Sync initial state from DB
            SyncGeneralUI()
            -- Register General as the first tab
            API.RegisterTab("General", generalFrame, SyncGeneralUI, 80, nil, 1)
        end)
    end
end)

-- ============================================================
-- Bars UI (merged from MidnightQoL_Bars)
-- Adds Pull Timer and Break Timer sections to the General tab.
-- ============================================================

local function BuildBarsGeneralUI()
    local generalFrame = _G["MidnightQoLGeneralFrame"]
    if not generalFrame then return end

    -- ── Pull Timer section ─────────────────────────────────────────────────────
    local pullHeader = generalFrame:CreateFontString(nil,"OVERLAY","GameFontNormalLarge")
    pullHeader:SetPoint("TOPLEFT", 10, -240)
    pullHeader:SetText("|cFFFFD700Pull Timer|r")

    local pullDesc = generalFrame:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    pullDesc:SetPoint("TOPLEFT", pullHeader, "BOTTOMLEFT", 0, -4)
    pullDesc:SetText("/pull [seconds]  — starts a raid countdown (default 10s)")

    local pullEnableCheck = CreateFrame("CheckButton","CSPullTimerCheck",generalFrame,"UICheckButtonTemplate")
    pullEnableCheck:SetSize(24,24); pullEnableCheck:SetPoint("TOPLEFT", pullDesc, "BOTTOMLEFT", 0, -6)
    local pullLbl = _G["CSPullTimerCheckText"]
    if pullLbl then pullLbl:SetText("Enable pull timer (/pull command)") end
    pullEnableCheck:SetChecked(BuffAlertDB and BuffAlertDB.pullTimerEnabled~=false or true)
    pullEnableCheck:SetScript("OnClick", function(self)
        if BuffAlertDB then BuffAlertDB.pullTimerEnabled = self:GetChecked() end
    end)

    -- ── Break Timer section ────────────────────────────────────────────────────
    local breakHeader = generalFrame:CreateFontString(nil,"OVERLAY","GameFontNormalLarge")
    breakHeader:SetPoint("TOPLEFT", pullEnableCheck, "BOTTOMLEFT", 0, -14)
    breakHeader:SetText("|cFFFFD700Break Timer|r")

    local breakDesc = generalFrame:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    breakDesc:SetPoint("TOPLEFT", breakHeader, "BOTTOMLEFT", 0, -4)
    breakDesc:SetText("/break [minutes]  — broadcasts a break bar to raid members (default 5m)")

    local breakEnableCheck = CreateFrame("CheckButton","CSBreakTimerCheck",generalFrame,"UICheckButtonTemplate")
    breakEnableCheck:SetSize(24,24); breakEnableCheck:SetPoint("TOPLEFT", breakDesc, "BOTTOMLEFT", 0, -6)
    local breakLbl = _G["CSBreakTimerCheckText"]
    if breakLbl then breakLbl:SetText("Enable break timer (/break command)") end
    breakEnableCheck:SetChecked(BuffAlertDB and BuffAlertDB.breakTimerEnabled~=false or true)
    breakEnableCheck:SetScript("OnClick", function(self)
        if BuffAlertDB then BuffAlertDB.breakTimerEnabled = self:GetChecked() end
    end)

    -- ── Bar color picker ───────────────────────────────────────────────────────
    local breakColorLabel = generalFrame:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    breakColorLabel:SetPoint("TOPLEFT", breakEnableCheck, "BOTTOMLEFT", 0, -10)
    breakColorLabel:SetText("Bar Color:")

    local breakColorSwatch = generalFrame:CreateTexture(nil,"ARTWORK")
    breakColorSwatch:SetSize(18,18); breakColorSwatch:SetPoint("LEFT", breakColorLabel, "RIGHT", 8, 0)
    local r0 = (BuffAlertDB and BuffAlertDB.breakBarR) or 0.2
    local g0 = (BuffAlertDB and BuffAlertDB.breakBarG) or 0.6
    local b0 = (BuffAlertDB and BuffAlertDB.breakBarB) or 1.0
    breakColorSwatch:SetColorTexture(r0, g0, b0, 1)

    local function ApplyBreakBarColor(r, g, b)
        if MidnightQoLAPI.breakFill then MidnightQoLAPI.breakFill:SetColorTexture(r,g,b,0.85) end
        breakColorSwatch:SetColorTexture(r,g,b,1)
        if BuffAlertDB then BuffAlertDB.breakBarR=r; BuffAlertDB.breakBarG=g; BuffAlertDB.breakBarB=b end
    end

    local breakColorBtn = CreateFrame("Button",nil,generalFrame,"UIPanelButtonTemplate")
    breakColorBtn:SetSize(54,20); breakColorBtn:SetPoint("LEFT", breakColorSwatch, "RIGHT", 6, 0)
    breakColorBtn:SetText("Pick")
    breakColorBtn:SetScript("OnClick", function()
        local r=(BuffAlertDB and BuffAlertDB.breakBarR) or 0.2
        local g=(BuffAlertDB and BuffAlertDB.breakBarG) or 0.6
        local b=(BuffAlertDB and BuffAlertDB.breakBarB) or 1.0
        if ColorPickerFrame.SetupColorPickerAndShow then
            ColorPickerFrame:SetupColorPickerAndShow({
                hasOpacity=false, r=r, g=g, b=b,
                swatchFunc = function() local nr,ng,nb=ColorPickerFrame:GetColorRGB(); ApplyBreakBarColor(nr,ng,nb) end,
                okayFunc   = function() local nr,ng,nb=ColorPickerFrame:GetColorRGB(); ApplyBreakBarColor(nr,ng,nb) end,
                cancelFunc = function(prev) ApplyBreakBarColor(prev.r,prev.g,prev.b) end,
            })
        else
            ColorPickerFrame.func = function() ApplyBreakBarColor(ColorPickerFrame:GetColorRGB()) end
            ColorPickerFrame.cancelFunc = function(prev) ApplyBreakBarColor(prev.r,prev.g,prev.b) end
            ColorPickerFrame.hasOpacity = false
            ColorPickerFrame:SetColorRGB(r,g,b); ShowUIPanel(ColorPickerFrame)
        end
    end)

    ApplyBreakBarColor(r0, g0, b0)

    -- Hook into the General tab sync so these controls stay up to date
    local existingSync = MidnightQoLAPI._barsGeneralSync
    MidnightQoLAPI._barsGeneralSync = function()
        pullEnableCheck:SetChecked(BuffAlertDB and BuffAlertDB.pullTimerEnabled~=false or true)
        breakEnableCheck:SetChecked(BuffAlertDB and BuffAlertDB.breakTimerEnabled~=false or true)
        local r=(BuffAlertDB and BuffAlertDB.breakBarR) or 0.2
        local g=(BuffAlertDB and BuffAlertDB.breakBarG) or 0.6
        local b=(BuffAlertDB and BuffAlertDB.breakBarB) or 1.0
        breakColorSwatch:SetColorTexture(r,g,b,1)
        if existingSync then existingSync() end
    end
end

local barsUIEvents = CreateFrame("Frame")
barsUIEvents:RegisterEvent("PLAYER_LOGIN")
barsUIEvents:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        C_Timer.After(0, BuildBarsGeneralUI)
    end
end)
