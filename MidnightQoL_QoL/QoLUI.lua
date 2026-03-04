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
        if API.RebuildLiveBars then API.RebuildLiveBars() end
    end
end)

-- Debug Mode toggle
local debugCheck = CreateFrame("CheckButton","CSGenDebugCheck",generalFrame,"UICheckButtonTemplate")
debugCheck:SetSize(24,24); debugCheck:SetPoint("TOPLEFT", resBarsCheck, "BOTTOMLEFT", 0, -4)
local debugLbl = _G["CSGenDebugCheckText"]
if debugLbl then debugLbl:SetText("Debug Mode  |cFFAAAAAA(/mqldebug)|r") end
debugCheck:SetScript("OnClick", function(self)
    API.DEBUG = self:GetChecked()
    if BuffAlertDB then BuffAlertDB.debugEnabled = API.DEBUG end
    print("|cFF00FF00[MidnightQoL]|r Debug mode " .. (API.DEBUG and "|cFFFFFF00ENABLED|r" or "|cFFAAAAAAdisabled|r"))
end)

-- ── Section: Quest Automation ─────────────────────────────────────────────────
local questHeader = generalFrame:CreateFontString(nil,"OVERLAY","GameFontNormalLarge")
questHeader:SetPoint("TOPLEFT", debugCheck, "BOTTOMLEFT", 0, -20)
questHeader:SetText("|cFFFFD700Quest Automation|r")

local questDesc = generalFrame:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
questDesc:SetPoint("TOPLEFT", questHeader, "BOTTOMLEFT", 0, -4)
questDesc:SetWidth(580); questDesc:SetJustifyH("LEFT"); questDesc:SetWordWrap(true)
questDesc:SetText("Automatically accept and/or turn in quests without clicking through dialog boxes.")

local autoAcceptCheck = CreateFrame("CheckButton","CSAutoQuestAcceptCheck",generalFrame,"UICheckButtonTemplate")
autoAcceptCheck:SetSize(24,24); autoAcceptCheck:SetPoint("TOPLEFT", questDesc, "BOTTOMLEFT", 0, -6)
local aaLbl = _G["CSAutoQuestAcceptCheckText"]
if aaLbl then aaLbl:SetText("Auto Accept Quests") end
autoAcceptCheck:SetScript("OnClick", function(self)
    if BuffAlertDB then BuffAlertDB.autoQuestAccept = self:GetChecked() end
end)

local autoTurnInCheck = CreateFrame("CheckButton","CSAutoQuestTurnInCheck",generalFrame,"UICheckButtonTemplate")
autoTurnInCheck:SetSize(24,24); autoTurnInCheck:SetPoint("TOPLEFT", autoAcceptCheck, "BOTTOMLEFT", 0, -4)
local atiLbl = _G["CSAutoQuestTurnInCheckText"]
if atiLbl then atiLbl:SetText("Auto Turn In Quests") end
autoTurnInCheck:SetScript("OnClick", function(self)
    if BuffAlertDB then BuffAlertDB.autoQuestTurnIn = self:GetChecked() end
end)

local questNoteLbl = generalFrame:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
questNoteLbl:SetPoint("TOPLEFT", autoTurnInCheck, "BOTTOMLEFT", 24, -4)
questNoteLbl:SetTextColor(0.7, 0.7, 0.7, 1)
questNoteLbl:SetText("|cFFFF8800Note:|r Auto turn-in skips reward selection dialogs. Quests with multiple reward choices still require manual selection.")

-- ── Section: Experience Bar ───────────────────────────────────────────────────
local expHeader = generalFrame:CreateFontString(nil,"OVERLAY","GameFontNormalLarge")
expHeader:SetPoint("TOPLEFT", questNoteLbl, "BOTTOMLEFT", -24, -20)
expHeader:SetText("|cFFFFD700Experience Bar|r")

local expDesc = generalFrame:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
expDesc:SetPoint("TOPLEFT", expHeader, "BOTTOMLEFT", 0, -4)
expDesc:SetWidth(580); expDesc:SetJustifyH("LEFT"); expDesc:SetWordWrap(true)
expDesc:SetText("Slim styled XP bar shown above your action bar. Drag it to reposition, or use the position fields below.")

local expEnableCheck = CreateFrame("CheckButton","CSExpBarEnableCheck",generalFrame,"UICheckButtonTemplate")
expEnableCheck:SetSize(24,24); expEnableCheck:SetPoint("TOPLEFT", expDesc, "BOTTOMLEFT", 0, -6)
local expEnableLbl = _G["CSExpBarEnableCheckText"]
if expEnableLbl then expEnableLbl:SetText("Enable Experience Bar") end
expEnableCheck:SetScript("OnClick", function(self)
    if BuffAlertDB then BuffAlertDB.expBarEnabled = self:GetChecked() end
    if API.UpdateExpBar then API.UpdateExpBar() end
end)

local expTextCheck = CreateFrame("CheckButton","CSExpBarTextCheck",generalFrame,"UICheckButtonTemplate")
expTextCheck:SetSize(24,24); expTextCheck:SetPoint("TOPLEFT", expEnableCheck, "BOTTOMLEFT", 0, -4)
local expTextLbl = _G["CSExpBarTextCheckText"]
if expTextLbl then expTextLbl:SetText("Show XP Text") end
expTextCheck:SetScript("OnClick", function(self)
    if BuffAlertDB then BuffAlertDB.expBarShowText = self:GetChecked() end
    if API.UpdateExpBar then API.UpdateExpBar() end
end)

local expTTLCheck = CreateFrame("CheckButton","CSExpBarTTLCheck",generalFrame,"UICheckButtonTemplate")
expTTLCheck:SetSize(24,24); expTTLCheck:SetPoint("TOPLEFT", expTextCheck, "BOTTOMLEFT", 24, -2)
local expTTLLbl = _G["CSExpBarTTLCheckText"]
if expTTLLbl then expTTLLbl:SetText("Show Time to Level  |cFFAAAAAA(requires XP gain to calculate)|r") end
expTTLCheck:SetScript("OnClick", function(self)
    if BuffAlertDB then BuffAlertDB.expBarShowTTL = self:GetChecked() end
    if API.UpdateExpBar then API.UpdateExpBar() end
end)

local expRestedCheck = CreateFrame("CheckButton","CSExpBarRestedCheck",generalFrame,"UICheckButtonTemplate")
expRestedCheck:SetSize(24,24); expRestedCheck:SetPoint("TOPLEFT", expTTLCheck, "BOTTOMLEFT", -24, -4)
local expRestedLbl = _G["CSExpBarRestedCheckText"]
if expRestedLbl then expRestedLbl:SetText("Show Rested XP Overlay") end
expRestedCheck:SetScript("OnClick", function(self)
    if BuffAlertDB then BuffAlertDB.expBarShowRested = self:GetChecked() end
    if API.UpdateExpBar then API.UpdateExpBar() end
end)

local expRepCheck = CreateFrame("CheckButton","CSExpBarRepCheck",generalFrame,"UICheckButtonTemplate")
expRepCheck:SetSize(24,24); expRepCheck:SetPoint("TOPLEFT", expRestedCheck, "BOTTOMLEFT", 0, -4)
local expRepLbl = _G["CSExpBarRepCheckText"]
if expRepLbl then expRepLbl:SetText("Show Reputation Bar at Max Level") end
expRepCheck:SetScript("OnClick", function(self)
    if BuffAlertDB then BuffAlertDB.expBarShowRep = self:GetChecked() end
    if API.UpdateExpBar then API.UpdateExpBar() end
end)

local expHideMaxCheck = CreateFrame("CheckButton","CSExpBarHideMaxCheck",generalFrame,"UICheckButtonTemplate")
expHideMaxCheck:SetSize(24,24); expHideMaxCheck:SetPoint("TOPLEFT", expRepCheck, "BOTTOMLEFT", 0, -4)
local expHideMaxLbl = _G["CSExpBarHideMaxCheckText"]
if expHideMaxLbl then expHideMaxLbl:SetText("Hide at Max Level (when no rep tracked)") end
expHideMaxCheck:SetScript("OnClick", function(self)
    if BuffAlertDB then BuffAlertDB.expBarHideAtMax = self:GetChecked() end
    if API.UpdateExpBar then API.UpdateExpBar() end
end)

-- Width / Height sliders (built manually — UISliderTemplate child names are unreliable)
-- Width / Height inputs
local expSizeLabel = generalFrame:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
expSizeLabel:SetPoint("TOPLEFT", expHideMaxCheck, "BOTTOMLEFT", 0, -20)
expSizeLabel:SetText("Width:")

local expWidthEdit = CreateFrame("EditBox", "CSExpBarWidthEdit", generalFrame, "InputBoxTemplate")
expWidthEdit:SetSize(60, 20)
expWidthEdit:SetPoint("LEFT", expSizeLabel, "RIGHT", 6, 0)
expWidthEdit:SetAutoFocus(false)
expWidthEdit:SetNumeric(true)
expWidthEdit:SetScript("OnEnterPressed", function(self)
    local val = math.max(100, math.min(1800, tonumber(self:GetText()) or 600))
    self:SetText(tostring(val))
    self:ClearFocus()
    if BuffAlertDB then BuffAlertDB.expBarWidth = val end
    if API.ApplyExpBarSettings then API.ApplyExpBarSettings() end
end)
expWidthEdit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

local expHeightLabel = generalFrame:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
expHeightLabel:SetPoint("LEFT", expWidthEdit, "RIGHT", 16, 0)
expHeightLabel:SetText("Height:")

local expHeightEdit = CreateFrame("EditBox", "CSExpBarHeightEdit", generalFrame, "InputBoxTemplate")
expHeightEdit:SetSize(44, 20)
expHeightEdit:SetPoint("LEFT", expHeightLabel, "RIGHT", 6, 0)
expHeightEdit:SetAutoFocus(false)
expHeightEdit:SetNumeric(true)
expHeightEdit:SetScript("OnEnterPressed", function(self)
    local val = math.max(2, math.min(60, tonumber(self:GetText()) or 10))
    self:SetText(tostring(val))
    self:ClearFocus()
    if BuffAlertDB then BuffAlertDB.expBarHeight = val end
    if API.ApplyExpBarSettings then API.ApplyExpBarSettings() end
end)
expHeightEdit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

local expSizeTip = generalFrame:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
expSizeTip:SetPoint("LEFT", expHeightEdit, "RIGHT", 10, 0)
expSizeTip:SetTextColor(0.6, 0.6, 0.6, 1)
expSizeTip:SetText("(press Enter to apply  •  or use Edit Layout to drag & resize)")

-- ── Bar colors ────────────────────────────────────────────────────────────────
local expColorsHeader = generalFrame:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
expColorsHeader:SetPoint("TOPLEFT", expSizeLabel, "BOTTOMLEFT", 0, -22)
expColorsHeader:SetText("Bar Colors:")
expColorsHeader:SetTextColor(1, 1, 1, 1)

local function MakeExpColorSwatch(labelText, anchorLeft, dbR, dbG, dbB, onApply)
    local lbl = generalFrame:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    lbl:SetPoint("LEFT", anchorLeft, "RIGHT", 14, 0)
    lbl:SetTextColor(0.75, 0.75, 0.75, 1)
    lbl:SetText(labelText)

    local swatch = generalFrame:CreateTexture(nil,"ARTWORK")
    swatch:SetSize(16,16)
    swatch:SetPoint("LEFT", lbl, "RIGHT", 5, 0)
    swatch:SetColorTexture(dbR, dbG, dbB, 1)

    local btn = CreateFrame("Button", nil, generalFrame, "UIPanelButtonTemplate")
    btn:SetSize(40, 18)
    btn:SetPoint("LEFT", swatch, "RIGHT", 4, 0)
    btn:SetText("Pick")
    btn.swatch = swatch
    btn:SetScript("OnClick", function()
        local r = (BuffAlertDB and BuffAlertDB[dbR]) or dbR
        local g = (BuffAlertDB and BuffAlertDB[dbG]) or dbG
        local b = (BuffAlertDB and BuffAlertDB[dbB]) or dbB
        -- dbR/dbG/dbB here are actually the current values passed in, use swatch color
        local sr, sg, sb = swatch:GetVertexColor()
        if ColorPickerFrame.SetupColorPickerAndShow then
            ColorPickerFrame:SetupColorPickerAndShow({
                hasOpacity=false, r=sr, g=sg, b=sb,
                swatchFunc = function()
                    local nr,ng,nb = ColorPickerFrame:GetColorRGB()
                    swatch:SetColorTexture(nr,ng,nb,1); onApply(nr,ng,nb)
                end,
                okayFunc = function()
                    local nr,ng,nb = ColorPickerFrame:GetColorRGB()
                    swatch:SetColorTexture(nr,ng,nb,1); onApply(nr,ng,nb)
                end,
                cancelFunc = function(prev)
                    swatch:SetColorTexture(prev.r,prev.g,prev.b,1); onApply(prev.r,prev.g,prev.b)
                end,
            })
        else
            ColorPickerFrame.func = function()
                local nr,ng,nb = ColorPickerFrame:GetColorRGB()
                swatch:SetColorTexture(nr,ng,nb,1); onApply(nr,ng,nb)
            end
            ColorPickerFrame.cancelFunc = function(prev)
                swatch:SetColorTexture(prev.r,prev.g,prev.b,1); onApply(prev.r,prev.g,prev.b)
            end
            ColorPickerFrame.hasOpacity = false
            ColorPickerFrame:SetColorRGB(sr,sg,sb); ShowUIPanel(ColorPickerFrame)
        end
    end)
    return btn, swatch
end

-- XP fill
local expXpColorBtn, expXpColorSwatch = MakeExpColorSwatch("XP", expColorsHeader,
    0.0, 0.6, 1.0,
    function(r,g,b)
        if BuffAlertDB then BuffAlertDB.expBarColorR=r; BuffAlertDB.expBarColorG=g; BuffAlertDB.expBarColorB=b end
        if API.ApplyExpBarSettings then API.ApplyExpBarSettings() end
    end)

-- Rested overlay
local expRestColorBtn, expRestColorSwatch = MakeExpColorSwatch("Rested", expXpColorBtn,
    0.3, 0.0, 0.8,
    function(r,g,b)
        if BuffAlertDB then BuffAlertDB.expBarRestedR=r; BuffAlertDB.expBarRestedG=g; BuffAlertDB.expBarRestedB=b end
        if API.ApplyExpBarSettings then API.ApplyExpBarSettings() end
    end)

-- Background
local expBgColorBtn, expBgColorSwatch = MakeExpColorSwatch("BG", expRestColorBtn,
    0.0, 0.0, 0.0,
    function(r,g,b)
        if BuffAlertDB then BuffAlertDB.expBarBgR=r; BuffAlertDB.expBarBgG=g; BuffAlertDB.expBarBgB=b end
        if API.ApplyExpBarSettings then API.ApplyExpBarSettings() end
    end)

-- Reputation bar
local expRepColorBtn, expRepColorSwatch = MakeExpColorSwatch("Rep", expBgColorBtn,
    0.8, 0.2, 1.0,
    function(r,g,b)
        if BuffAlertDB then BuffAlertDB.expBarRepR=r; BuffAlertDB.expBarRepG=g; BuffAlertDB.expBarRepB=b end
        if API.UpdateExpBar then API.UpdateExpBar() end
    end)

-- Pending quests color (on new line)
local expPendingColorRow = generalFrame:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
expPendingColorRow:SetPoint("TOPLEFT", expColorsHeader, "BOTTOMLEFT", 0, -28)
expPendingColorRow:SetText("Completed Quests:")
expPendingColorRow:SetTextColor(1, 1, 1, 1)

local expPendingColorBtn, expPendingColorSwatch = MakeExpColorSwatch("", expPendingColorRow,
    1.0, 0.85, 0.0,
    function(r,g,b)
        if BuffAlertDB then BuffAlertDB.expBarPendingR=r; BuffAlertDB.expBarPendingG=g; BuffAlertDB.expBarPendingB=b end
        if API.ApplyExpBarSettings then API.ApplyExpBarSettings() end
    end)

local expColorLastAnchor = expPendingColorRow  -- leftmost element on last color row

-- ── Section: Reputation Bar ───────────────────────────────────────────────────
local repBarHeader = generalFrame:CreateFontString(nil,"OVERLAY","GameFontNormalLarge")
repBarHeader:SetPoint("TOPLEFT", expPendingColorRow, "BOTTOMLEFT", 0, -20)
repBarHeader:SetText("|cFFFF80FFReputation Bar|r")

local repBarDesc = generalFrame:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
repBarDesc:SetPoint("TOPLEFT", repBarHeader, "BOTTOMLEFT", 0, -4)
repBarDesc:SetText("Shows your tracked faction standing with pending quest rep overlay.")

local repEnableCheck = CreateFrame("CheckButton","CSRepBarEnableCheck",generalFrame,"UICheckButtonTemplate")
repEnableCheck:SetSize(24,24); repEnableCheck:SetPoint("TOPLEFT", repBarDesc, "BOTTOMLEFT", 0, -4)
local repEnableLbl = _G["CSRepBarEnableCheckText"]
if repEnableLbl then repEnableLbl:SetText("Enable Reputation Bar") end
repEnableCheck:SetScript("OnClick", function(self)
    if BuffAlertDB then BuffAlertDB.repBarEnabled = self:GetChecked() end
    if API.UpdateRepBar then API.UpdateRepBar() end
end)

local repTextCheck = CreateFrame("CheckButton","CSRepBarTextCheck",generalFrame,"UICheckButtonTemplate")
repTextCheck:SetSize(24,24); repTextCheck:SetPoint("TOPLEFT", repEnableCheck, "BOTTOMLEFT", 0, -4)
local repTextLbl = _G["CSRepBarTextCheckText"]
if repTextLbl then repTextLbl:SetText("Show Rep Text") end
repTextCheck:SetScript("OnClick", function(self)
    if BuffAlertDB then BuffAlertDB.repBarShowText = self:GetChecked() end
    if API.UpdateRepBar then API.UpdateRepBar() end
end)

-- Width / Height
local repSizeLabel = generalFrame:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
repSizeLabel:SetPoint("TOPLEFT", repTextCheck, "BOTTOMLEFT", 0, -14)
repSizeLabel:SetText("Width:")

local repWidthEdit = CreateFrame("EditBox","CSRepBarWidthEdit",generalFrame,"InputBoxTemplate")
repWidthEdit:SetSize(60,20); repWidthEdit:SetPoint("LEFT", repSizeLabel, "RIGHT", 6, 0)
repWidthEdit:SetAutoFocus(false); repWidthEdit:SetNumeric(true)
repWidthEdit:SetScript("OnEnterPressed", function(self)
    local val = math.max(100, math.min(1800, tonumber(self:GetText()) or 600))
    self:SetText(tostring(val)); self:ClearFocus()
    if BuffAlertDB then BuffAlertDB.repBarWidth = val end
    if API.ApplyRepBarSettings then API.ApplyRepBarSettings() end
end)
repWidthEdit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

local repHeightLabel = generalFrame:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
repHeightLabel:SetPoint("LEFT", repWidthEdit, "RIGHT", 16, 0)
repHeightLabel:SetText("Height:")

local repHeightEdit = CreateFrame("EditBox","CSRepBarHeightEdit",generalFrame,"InputBoxTemplate")
repHeightEdit:SetSize(44,20); repHeightEdit:SetPoint("LEFT", repHeightLabel, "RIGHT", 6, 0)
repHeightEdit:SetAutoFocus(false); repHeightEdit:SetNumeric(true)
repHeightEdit:SetScript("OnEnterPressed", function(self)
    local val = math.max(2, math.min(60, tonumber(self:GetText()) or 10))
    self:SetText(tostring(val)); self:ClearFocus()
    if BuffAlertDB then BuffAlertDB.repBarHeight = val end
    if API.ApplyRepBarSettings then API.ApplyRepBarSettings() end
end)
repHeightEdit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

-- Rep bar colors
local repColorsHeader = generalFrame:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
repColorsHeader:SetPoint("TOPLEFT", repSizeLabel, "BOTTOMLEFT", 0, -22)
repColorsHeader:SetText("Bar Colors:")
repColorsHeader:SetTextColor(1, 1, 1, 1)

local function MakeRepColorSwatch(labelText, anchorLeft, onApply)
    local lbl = generalFrame:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    lbl:SetPoint("LEFT", anchorLeft, "RIGHT", 14, 0)
    lbl:SetTextColor(0.75, 0.75, 0.75, 1); lbl:SetText(labelText)
    local swatch = generalFrame:CreateTexture(nil,"ARTWORK")
    swatch:SetSize(16,16); swatch:SetPoint("LEFT", lbl, "RIGHT", 5, 0)
    local btn = CreateFrame("Button",nil,generalFrame,"UIPanelButtonTemplate")
    btn:SetSize(40,18); btn:SetPoint("LEFT", swatch, "RIGHT", 4, 0); btn:SetText("Pick")
    btn:SetScript("OnClick", function()
        local sr,sg,sb = swatch:GetVertexColor()
        if ColorPickerFrame.SetupColorPickerAndShow then
            ColorPickerFrame:SetupColorPickerAndShow({
                hasOpacity=false, r=sr, g=sg, b=sb,
                swatchFunc = function() local r,g,b=ColorPickerFrame:GetColorRGB(); swatch:SetColorTexture(r,g,b,1); onApply(r,g,b) end,
                okayFunc   = function() local r,g,b=ColorPickerFrame:GetColorRGB(); swatch:SetColorTexture(r,g,b,1); onApply(r,g,b) end,
                cancelFunc = function(p) swatch:SetColorTexture(p.r,p.g,p.b,1); onApply(p.r,p.g,p.b) end,
            })
        else
            ColorPickerFrame.func = function() local r,g,b=ColorPickerFrame:GetColorRGB(); swatch:SetColorTexture(r,g,b,1); onApply(r,g,b) end
            ColorPickerFrame.cancelFunc = function(p) swatch:SetColorTexture(p.r,p.g,p.b,1); onApply(p.r,p.g,p.b) end
            ColorPickerFrame.hasOpacity=false; ColorPickerFrame:SetColorRGB(sr,sg,sb); ShowUIPanel(ColorPickerFrame)
        end
    end)
    return btn, swatch
end

local repFillColorBtn,  repFillColorSwatch  = MakeRepColorSwatch("Rep",     repColorsHeader,
    function(r,g,b) if BuffAlertDB then BuffAlertDB.repBarFillR=r; BuffAlertDB.repBarFillG=g; BuffAlertDB.repBarFillB=b end; if API.ApplyRepBarSettings then API.ApplyRepBarSettings() end end)
local repBgColorBtn,    repBgColorSwatch    = MakeRepColorSwatch("BG",      repFillColorBtn,
    function(r,g,b) if BuffAlertDB then BuffAlertDB.repBarBgR=r; BuffAlertDB.repBarBgG=g; BuffAlertDB.repBarBgB=b end; if API.ApplyRepBarSettings then API.ApplyRepBarSettings() end end)
local repPendColorBtn,  repPendColorSwatch  = MakeRepColorSwatch("Pending", repBgColorBtn,
    function(r,g,b) if BuffAlertDB then BuffAlertDB.repBarPendingR=r; BuffAlertDB.repBarPendingG=g; BuffAlertDB.repBarPendingB=b end; if API.ApplyRepBarSettings then API.ApplyRepBarSettings() end end)

-- ── Section: Pet Reminder ─────────────────────────────────────────────────────
local petHeader = generalFrame:CreateFontString(nil,"OVERLAY","GameFontNormalLarge")
petHeader:SetPoint("TOPLEFT", repColorsHeader, "BOTTOMLEFT", 0, -20)
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
    debugCheck:SetChecked(API.DEBUG or false)
    autoAcceptCheck:SetChecked(BuffAlertDB.autoQuestAccept or false)
    autoTurnInCheck:SetChecked(BuffAlertDB.autoQuestTurnIn or false)
    -- Experience bar
    expEnableCheck:SetChecked(BuffAlertDB.expBarEnabled ~= false)
    expTextCheck:SetChecked(BuffAlertDB.expBarShowText ~= false)
    expTTLCheck:SetChecked(BuffAlertDB.expBarShowTTL ~= false)
    expRestedCheck:SetChecked(BuffAlertDB.expBarShowRested ~= false)
    expRepCheck:SetChecked(BuffAlertDB.expBarShowRep ~= false)
    expHideMaxCheck:SetChecked(BuffAlertDB.expBarHideAtMax ~= false)
    expWidthEdit:SetText(tostring(BuffAlertDB.expBarWidth or 600))
    expHeightEdit:SetText(tostring(BuffAlertDB.expBarHeight or 10))
    expXpColorSwatch:SetColorTexture(
        BuffAlertDB.expBarColorR or 0.0, BuffAlertDB.expBarColorG or 0.6, BuffAlertDB.expBarColorB or 1.0, 1)
    expRestColorSwatch:SetColorTexture(
        BuffAlertDB.expBarRestedR or 0.3, BuffAlertDB.expBarRestedG or 0.0, BuffAlertDB.expBarRestedB or 0.8, 1)
    expBgColorSwatch:SetColorTexture(
        BuffAlertDB.expBarBgR or 0.0, BuffAlertDB.expBarBgG or 0.0, BuffAlertDB.expBarBgB or 0.0, 1)
    expPendingColorSwatch:SetColorTexture(
        BuffAlertDB.expBarPendingR or 1.0, BuffAlertDB.expBarPendingG or 0.85, BuffAlertDB.expBarPendingB or 0.0, 1)
    -- Rep bar
    repEnableCheck:SetChecked(BuffAlertDB.repBarEnabled or false)
    repTextCheck:SetChecked(BuffAlertDB.repBarShowText ~= false)
    repWidthEdit:SetText(tostring(BuffAlertDB.repBarWidth or 600))
    repHeightEdit:SetText(tostring(BuffAlertDB.repBarHeight or 10))
    repFillColorSwatch:SetColorTexture(
        BuffAlertDB.repBarFillR or 0.8, BuffAlertDB.repBarFillG or 0.2, BuffAlertDB.repBarFillB or 1.0, 1)
    repBgColorSwatch:SetColorTexture(
        BuffAlertDB.repBarBgR or 0.0, BuffAlertDB.repBarBgG or 0.0, BuffAlertDB.repBarBgB or 0.0, 1)
    repPendColorSwatch:SetColorTexture(
        BuffAlertDB.repBarPendingR or 1.0, BuffAlertDB.repBarPendingG or 0.85, BuffAlertDB.repBarPendingB or 0.0, 1)
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
    pullHeader:SetPoint("TOPLEFT", petSoundLabel, "BOTTOMLEFT", 0, -20)
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
