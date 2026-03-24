-- ============================================================
-- MidnightQoL_Castbar / CastbarUI.lua
-- Settings tab: enable/disable, colors, size, options.
-- ============================================================

local API = MidnightQoLAPI
if not API then return end

local DEFAULTS = {
    enabled=true, hideBlizzard=true, x=0, y=-220, width=280, height=18,
    colorCasting={0.2,0.6,1.0}, colorChanneling={0.4,1.0,0.4},
    colorNonInterrupt={0.6,0.6,0.6}, colorInterrupted={1.0,0.2,0.2},
    colorFinished={1.0,1.0,0.4}, colorEmpowered={1.0,0.6,0.0},
    colorBackground={0.0,0.0,0.0},
    showIcon=true, showTimer=true, showSpellName=true,
    showGCD=true, showLatency=true, showChannelTicks=true,
    finishedFlashDur=0.25,
}

local function GetDB()
    if not CastbarDB then CastbarDB = {} end
    for k, v in pairs(DEFAULTS) do
        if CastbarDB[k] == nil then CastbarDB[k] = v end
    end
    return CastbarDB
end

-- ── Color swatch ───────────────────────────────────────────────────────────────
local function CreateColorSwatch(parent, label, dbKey, x, y)
    local lbl = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lbl:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    lbl:SetText(label)
    local sw = CreateFrame("Button", nil, parent)
    sw:SetSize(16, 16)
    sw:SetPoint("LEFT", lbl, "RIGHT", 4, 0)
    local tex = sw:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints(sw)
    tex:SetColorTexture(0.5, 0.5, 0.5, 1)  -- placeholder; OnActivate syncs the real color
    sw.colorTex = tex
    sw.dbKey = dbKey
    sw:SetScript("OnClick", function(self)
        local db2 = GetDB()
        local cc = db2[self.dbKey] or DEFAULTS[self.dbKey]
        ColorPickerFrame:SetupColorPickerAndShow({
            r=cc[1], g=cc[2], b=cc[3],
            swatchFunc = function()
                local r,g,b = ColorPickerFrame:GetColorRGB()
                GetDB()[self.dbKey] = {r,g,b}
                self.colorTex:SetColorTexture(r,g,b,1)
            end,
            cancelFunc = function(prev)
                GetDB()[self.dbKey] = {prev.r, prev.g, prev.b}
                self.colorTex:SetColorTexture(prev.r, prev.g, prev.b, 1)
            end,
            hasOpacity = false,
        })
    end)
    -- Don't set color from DB here — DB may not be loaded yet.
    -- OnActivate() will sync the swatch when the tab is opened.
    return sw
end

-- ── Content frame ─────────────────────────────────────────────────────────────
local cf = CreateFrame("Frame", "MidnightQoLCastbarFrame", UIParent)
cf:SetSize(620, 300)
cf:Hide()

local function MakeCb(name, dbKey, label, px, py)
    local cb = CreateFrame("CheckButton", "CastbarCb_"..name, cf, "UICheckButtonTemplate")
    cb:SetSize(20,20); cb:SetPoint("TOPLEFT", cf, "TOPLEFT", px, py)
    local lbl = cf:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    lbl:SetPoint("LEFT", cb, "RIGHT", 2, 0); lbl:SetText(label)
    cb:SetScript("OnClick", function(s) GetDB()[dbKey] = s:GetChecked() end)
    return cb
end

-- Row 1: Enable / Hide Blizzard
local enableCb = CreateFrame("CheckButton","CastbarEnableCb",cf,"UICheckButtonTemplate")
enableCb:SetSize(24,24); enableCb:SetPoint("TOPLEFT",cf,"TOPLEFT",0,-4)
local enableLbl = cf:CreateFontString(nil,"OVERLAY","GameFontNormal")
enableLbl:SetPoint("LEFT",enableCb,"RIGHT",4,0); enableLbl:SetText("Enable custom player castbar")
enableCb:SetScript("OnClick", function(s)
    GetDB().enabled = s:GetChecked()
    if API.castbarFrame and not s:GetChecked() then API.castbarFrame:Hide() end
end)

local hideCb = CreateFrame("CheckButton","CastbarHideCb",cf,"UICheckButtonTemplate")
hideCb:SetSize(24,24); hideCb:SetPoint("TOPLEFT",cf,"TOPLEFT",0,-30)
local hideLbl = cf:CreateFontString(nil,"OVERLAY","GameFontNormal")
hideLbl:SetPoint("LEFT",hideCb,"RIGHT",4,0)
hideLbl:SetText("Hide Blizzard castbar (requires /reload)")

-- Row 2: show options
local cbIcon    = MakeCb("Icon",    "showIcon",         "Show icon",         0,   -60)
local cbTimer   = MakeCb("Timer",   "showTimer",        "Show timer",        140, -60)
local cbName    = MakeCb("Name",    "showSpellName",    "Show spell name",   280, -60)
local cbGCD     = MakeCb("GCD",     "showGCD",          "GCD spark",         0,   -82)
local cbLatency = MakeCb("Latency", "showLatency",      "Latency zone",      140, -82)
local cbTicks   = MakeCb("Ticks",   "showChannelTicks", "Channel ticks",     280, -82)

-- Row 3: sizes
local function MakeLabel(txt, px, py)
    local l = cf:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    l:SetPoint("TOPLEFT",cf,"TOPLEFT",px,py); l:SetText(txt); return l
end
local function MakeInput(px, py, w, numeric)
    local e = CreateFrame("EditBox",nil,cf,"InputBoxTemplate")
    e:SetSize(w,20); e:SetPoint("TOPLEFT",cf,"TOPLEFT",px,py)
    e:SetAutoFocus(false); e:SetMaxLetters(6)
    if numeric then e:SetNumeric(true) end
    return e
end
MakeLabel("Width:",  0,   -110); local widthIn  = MakeInput(42,  -112, 50, true)
MakeLabel("Height:", 105, -110); local heightIn = MakeInput(147, -112, 40, true)
MakeLabel("Finish flash (s):", 200, -110); local flashIn  = MakeInput(300, -112, 40, false)

-- Row 4: colors header
local colorHdr = cf:CreateFontString(nil,"OVERLAY","GameFontNormal")
colorHdr:SetPoint("TOPLEFT",cf,"TOPLEFT",0,-140)
colorHdr:SetText("|cFFFFD700Bar Colors|r  (click swatch to change)")

local swCasting      = CreateColorSwatch(cf, "Casting:",        "colorCasting",      0,   -160)
local swChanneling   = CreateColorSwatch(cf, "Channeling:",     "colorChanneling",   170, -160)
local swNonInterrupt = CreateColorSwatch(cf, "Non-interrupt:",  "colorNonInterrupt", 340, -160)
local swInterrupted  = CreateColorSwatch(cf, "Interrupted:",    "colorInterrupted",  0,   -180)
local swFinished     = CreateColorSwatch(cf, "Finished flash:", "colorFinished",     170, -180)
local swEmpowered    = CreateColorSwatch(cf, "Empowered:",      "colorEmpowered",    340, -180)
local swBackground   = CreateColorSwatch(cf, "Background:",     "colorBackground",   0,   -200)

-- Preview button
local testBtn = CreateFrame("Button",nil,cf,"GameMenuButtonTemplate")
testBtn:SetSize(80,24); testBtn:SetPoint("TOPLEFT",cf,"TOPLEFT",0,-230)
testBtn:SetText("Preview")
testBtn:SetScript("OnClick", function()
    local f = API.castbarFrame; if not f then return end
    local db = GetDB()
    f.casting=true; f.channeling=false
    f.startTime=GetTime(); f.endTime=GetTime()+2.5; f.delay=0
    local c = db.colorCasting or {0.2,0.6,1.0}
    f.bar:SetStatusBarColor(c[1],c[2],c[3],1)
    f.bar:SetValue(0)
    if db.showSpellName then f.nameStr:SetText("Shadow Bolt") end
    f.icon:SetTexture("Interface\\Icons\\Spell_Shadow_DestroyerOfWorlds"); f.icon:Show()
    f:Show()
end)

-- ── Populate / harvest ─────────────────────────────────────────────────────────
local allSwatches = {swCasting,swChanneling,swNonInterrupt,swInterrupted,swFinished,swEmpowered,swBackground}

local tabWasOpened = false

local function OnActivate()
    tabWasOpened = true
    local db = GetDB()
    enableCb:SetChecked(db.enabled ~= false)
    hideCb:SetChecked(db.hideBlizzard ~= false)
    cbIcon:SetChecked(db.showIcon ~= false)
    cbTimer:SetChecked(db.showTimer ~= false)
    cbName:SetChecked(db.showSpellName ~= false)
    cbGCD:SetChecked(db.showGCD ~= false)
    cbLatency:SetChecked(db.showLatency ~= false)
    cbTicks:SetChecked(db.showChannelTicks ~= false)
    widthIn:SetText(tostring(db.width or 280))
    heightIn:SetText(tostring(db.height or 18))
    flashIn:SetText(tostring(db.finishedFlashDur or 0.25))
    for _, sw in ipairs(allSwatches) do
        local c = db[sw.dbKey] or {0.5,0.5,0.5}
        sw.colorTex:SetColorTexture(c[1],c[2],c[3],1)
    end
end

local function HarvestValues()
    if not tabWasOpened then return end  -- never opened = nothing to harvest, don't overwrite DB
    local db = GetDB()
    db.enabled       = enableCb:GetChecked()
    db.hideBlizzard  = hideCb:GetChecked()
    db.showIcon      = cbIcon:GetChecked()
    db.showTimer     = cbTimer:GetChecked()
    db.showSpellName = cbName:GetChecked()
    db.showGCD       = cbGCD:GetChecked()
    db.showLatency   = cbLatency:GetChecked()
    db.showChannelTicks = cbTicks:GetChecked()
    db.width         = tonumber(widthIn:GetText())  or 280
    db.height        = tonumber(heightIn:GetText()) or 18
    db.finishedFlashDur = tonumber(flashIn:GetText()) or 0.25
    if API.ApplyCastbarPosition then API.ApplyCastbarPosition() end
end

-- Register with core pre-save system so HarvestValues always runs before SaveSpecProfile
if API.RegisterPreSaveCallback then
    API.RegisterPreSaveCallback(HarvestValues)
else
    -- Fallback: hook the save button directly once it exists
    local frame = CreateFrame("Frame")
    frame:RegisterEvent("PLAYER_LOGIN")
    frame:SetScript("OnEvent", function(self)
        local btn = _G["MidnightQoLSaveBtn"]
        if btn then btn:HookScript("OnClick", HarvestValues) end
        self:UnregisterAllEvents()
    end)
end

-- Flush text box values to CastbarDB on logout so they survive without needing Save
local logoutFrame = CreateFrame("Frame")
logoutFrame:RegisterEvent("PLAYER_LOGOUT")
logoutFrame:SetScript("OnEvent", function() HarvestValues() end)

API.RegisterTab("Castbar", cf, OnActivate, 70, nil, 4) -- priority 4
