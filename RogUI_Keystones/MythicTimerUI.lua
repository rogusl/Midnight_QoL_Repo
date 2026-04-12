-- ============================================================
-- RogUI / Modules / Keystones / MythicTimerUI.lua
-- UI Settings for M+ Timer
-- ============================================================

local API = RogUIAPI

local TIMER_DEFAULTS = {
    enabled = true,
    posX    = 0,
    posY    = 200,
    scale   = 1.0,
    opacity = 0.7,
}

local function GetDB()
    if not RogUIDB then return TIMER_DEFAULTS end
    RogUIDB.keystones = RogUIDB.keystones or {}
    RogUIDB.keystones.timerSettings = RogUIDB.keystones.timerSettings or {}
    local db = RogUIDB.keystones.timerSettings
    for k, v in pairs(TIMER_DEFAULTS) do
        if db[k] == nil then db[k] = v end
    end
    return db
end

local cf = CreateFrame("Frame", "RogUIKeystonesTimerFrame", UIParent)
cf:SetSize(600, 450)
cf:Hide()

local y = -10
local leftMargin = 20

local function Header(txt)
    local t = cf:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    t:SetText(txt)
    t:SetPoint("TOPLEFT", leftMargin, y)
    y = y - 28
end

local function Divider()
    local d = cf:CreateTexture(nil, "ARTWORK")
    d:SetSize(560, 1)
    d:SetPoint("TOPLEFT", leftMargin, y)
    d:SetColorTexture(1, 1, 1, 0.15)
    y = y - 15
end

-- ── UI Content ────────────────────────────────────────────────────────────────

Header("|cFFFFD700Timer Configuration|r")
Divider()

-- 1. Enabled Toggle
local enabledCheckbox = CreateFrame("CheckButton", "MQLTimerEnabledCheck", cf, "UICheckButtonTemplate")
enabledCheckbox:SetSize(26, 26)
enabledCheckbox:SetPoint("TOPLEFT", leftMargin, y)
_G[enabledCheckbox:GetName().."Text"]:SetFontObject("GameFontHighlight")
_G[enabledCheckbox:GetName().."Text"]:SetText("Enable Mythic+ Timer")
enabledCheckbox:SetScript("OnClick", function(self)
    GetDB().enabled = self:GetChecked()
    if not self:GetChecked() and API.MythicTimer then API.MythicTimer.Stop() end
end)

y = y - 50 -- Space before the first slider

-- 2. Scale Slider
local scaleSlider = CreateFrame("Slider", "MQLTimerScaleSlider", cf, "OptionsSliderTemplate")
scaleSlider:SetSize(240, 18)
-- Move the slider further right and down to give the label room
scaleSlider:SetPoint("TOPLEFT", leftMargin + 10, y)
scaleSlider:SetMinMaxValues(0.5, 2.0)
scaleSlider:SetValueStep(0.1)

-- Use the built-in Text element as the header to avoid overlap
local scaleText = _G[scaleSlider:GetName().."Text"]
scaleText:ClearAllPoints()
scaleText:SetPoint("BOTTOMLEFT", scaleSlider, "TOPLEFT", 0, 5)
scaleText:SetFontObject("GameFontNormal")

_G[scaleSlider:GetName().."Low"]:SetText("0.5x")
_G[scaleSlider:GetName().."High"]:SetText("2.0x")

scaleSlider:SetScript("OnValueChanged", function(self, value)
    GetDB().scale = value
    scaleText:SetText(string.format("Timer Scale: %.1fx", value))
    if API.MythicTimer then API.MythicTimer.ApplySettings() end
end)

y = y - 55 -- Large gap between sliders

-- 3. Opacity Slider
local opacitySlider = CreateFrame("Slider", "MQLTimerOpacitySlider", cf, "OptionsSliderTemplate")
opacitySlider:SetSize(240, 18)
opacitySlider:SetPoint("TOPLEFT", leftMargin + 10, y)
opacitySlider:SetMinMaxValues(0.2, 1.0)
opacitySlider:SetValueStep(0.05)

-- Use the built-in Text element as the header
local opacityText = _G[opacitySlider:GetName().."Text"]
opacityText:ClearAllPoints()
opacityText:SetPoint("BOTTOMLEFT", opacitySlider, "TOPLEFT", 0, 5)
opacityText:SetFontObject("GameFontNormal")

_G[opacitySlider:GetName().."Low"]:SetText("20%")
_G[opacitySlider:GetName().."High"]:SetText("100%")

opacitySlider:SetScript("OnValueChanged", function(self, value)
    GetDB().opacity = value
    opacityText:SetText(string.format("Timer Opacity: %d%%", value * 100))
    if API.MythicTimer then API.MythicTimer.ApplySettings() end
end)

y = y - 65

-- 4. Features Info
Header("|cFFAAAAAAFeatures Info|r")
Divider()

local infoText = cf:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
infoText:SetPoint("TOPLEFT", leftMargin, y)
infoText:SetWidth(540)
infoText:SetJustifyH("LEFT")
infoText:SetSpacing(4)
infoText:SetText("• Automatic dungeon timer with color-coded warnings\n• Real-time objective and boss tracking\n• High-precision enemy forces percentage\n• Drag the timer while in-game to reposition it")

-- ── Sync controls from DB on show ─────────────────────────────────────────────
cf:SetScript("OnShow", function()
    local db = GetDB()
    enabledCheckbox:SetChecked(db.enabled)
    
    local sVal = db.scale or 1.0
    scaleSlider:SetValue(sVal)
    _G[scaleSlider:GetName().."Text"]:SetText(string.format("Timer Scale: %.1fx", sVal))
    
    local oVal = db.opacity or 0.7
    opacitySlider:SetValue(oVal)
    _G[opacitySlider:GetName().."Text"]:SetText(string.format("Timer Opacity: %d%%", oVal * 100))
end)

API.MythicTimerUIFrame = cf