-- ============================================================
-- MidnightQoL_ResourceBars / ResourceBarsUI.lua
-- Config tab for resource bars: add/remove, power type picker,
-- colour picker, size/position controls, pip settings.
-- ============================================================

local API = MidnightQoLAPI

local MAX_BARS    = 2
local function GetBarConfigs() return API.barConfigs end

-- ── Content frame ─────────────────────────────────────────────────────────────
local contentFrame = CreateFrame("Frame","MidnightQoLResourceBarsFrame",UIParent)
contentFrame:SetSize(640,500); contentFrame:Hide()

-- ── Header ────────────────────────────────────────────────────────────────────
local headerLbl = contentFrame:CreateFontString(nil,"OVERLAY","GameFontNormalLarge")
headerLbl:SetPoint("TOPLEFT",0,-4)
headerLbl:SetText("|cFFFFD700Resource Bars|r")

local descLbl = contentFrame:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
descLbl:SetPoint("TOPLEFT",0,-28); descLbl:SetWidth(630); descLbl:SetJustifyH("LEFT"); descLbl:SetWordWrap(true)
descLbl:SetTextColor(0.75,0.75,0.75,1)
descLbl:SetText(
    "Configure up to "..MAX_BARS.." live resource bars per spec. Bars auto-populate with your spec's primary and "..
    "secondary resources. Use Edit Layout to drag them to position."
)

-- ── Row widget pool ───────────────────────────────────────────────────────────
local rowWidgets = {}   -- [i] = widget table for bar slot i

-- Power type entries for the dropdown
local POWER_ENTRIES = {
    {name="Mana",          type=0},
    {name="Rage",          type=1},
    {name="Focus",         type=2},
    {name="Energy",        type=3},
    {name="Combo Points",  type=4},
    {name="Runes",         type=5},
    {name="Runic Power",   type=6},
    {name="Soul Shards",   type=7},
    {name="Lunar Power",   type=8},
    {name="Holy Power",    type=9},
    {name="Maelstrom",     type=11},
    {name="Chi",           type=12},
    {name="Insanity",      type=13},
    {name="Arcane Charges",type=16},
    {name="Fury",          type=17},
    {name="Pain",          type=18},
    {name="Essence",       type=19},
    {name="Stagger",        type=20},
}

local function PowerTypeName(pt)
    for _,e in ipairs(POWER_ENTRIES) do
        if e.type == pt then return e.name end
    end
    return "Power("..tostring(pt)..")"
end

-- Simple colour box helper
local function CreateColourSwatch(parent, name, r, g, b, onChange)
    local btn = CreateFrame("Button", name, parent)
    btn:SetSize(22,16)
    local tex = btn:CreateTexture(nil,"ARTWORK"); tex:SetAllPoints(btn)
    tex:SetColorTexture(r,g,b,1); btn.tex=tex; btn.r=r; btn.g=g; btn.b=b
    local border = btn:CreateTexture(nil,"BORDER"); border:SetAllPoints(btn)
    border:SetColorTexture(0.6,0.6,0.6,1); btn:SetFrameLevel(btn:GetFrameLevel()+1)
    btn:HookScript("OnClick",function(self)
        ColorPickerFrame:SetupColorPickerAndShow({
            r=self.r, g=self.g, b=self.b, opacity=1,
            swatchFunc=function()
                self.r,self.g,self.b=ColorPickerFrame:GetColorRGB()
                self.tex:SetColorTexture(self.r,self.g,self.b,1)
                if onChange then onChange(self.r,self.g,self.b) end
            end,
            cancelFunc=function(prevValues)
                self.r,self.g,self.b=prevValues.r,prevValues.g,prevValues.b
                self.tex:SetColorTexture(self.r,self.g,self.b,1)
            end,
        })
    end)
    return btn
end

-- Power type dropdown popup (shared, one at a time)
local powerDropPopup = CreateFrame("Frame","CSResPowerDrop",UIParent,"BackdropTemplate")
powerDropPopup:SetSize(180,250); powerDropPopup:SetFrameStrata("TOOLTIP")
powerDropPopup:SetBackdrop({bgFile="Interface/DialogFrame/UI-DialogBox-Background",
    edgeFile="Interface/DialogFrame/UI-DialogBox-Border",
    tile=true,tileSize=16,edgeSize=16,insets={left=4,right=4,top=4,bottom=4}})
powerDropPopup:SetBackdropColor(0.08,0.08,0.12,0.98); powerDropPopup:Hide()

local pdScroll=CreateFrame("ScrollFrame","CSResPowerDropScroll",powerDropPopup,"UIPanelScrollFrameTemplate")
pdScroll:SetPoint("TOPLEFT",8,-8); pdScroll:SetPoint("BOTTOMRIGHT",-28,8)
local pdContent=CreateFrame("Frame","CSResPowerDropContent",pdScroll)
pdContent:SetSize(140,1); pdScroll:SetScrollChild(pdContent)

local function OpenPowerDrop(anchorBtn, onSelect)
    if powerDropPopup:IsShown() and powerDropPopup.anchor==anchorBtn then
        powerDropPopup:Hide(); return
    end
    powerDropPopup.anchor=anchorBtn
    -- Clear old rows
    for _,c in ipairs({pdContent:GetChildren()}) do c:Hide() end
    local ROW_H=22
    for i,entry in ipairs(POWER_ENTRIES) do
        local btn=CreateFrame("Button",nil,pdContent)
        btn:SetSize(135,ROW_H); btn:SetPoint("TOPLEFT",0,-(i-1)*ROW_H)
        local hl=btn:CreateTexture(nil,"HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1,1,1,0.12)
        local lbl=btn:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
        lbl:SetPoint("LEFT",4,0); lbl:SetText(entry.name)
        local capE=entry
        btn:SetScript("OnClick",function()
            onSelect(capE.type, capE.name)
            powerDropPopup:Hide()
        end)
    end
    pdContent:SetHeight(#POWER_ENTRIES*ROW_H)
    powerDropPopup:ClearAllPoints(); powerDropPopup:SetPoint("TOPLEFT",anchorBtn,"BOTTOMLEFT",0,-4)
    powerDropPopup:Show()
end

-- ── Per-bar row factory ───────────────────────────────────────────────────────
-- Layout: each row is 140px tall, with 3 explicit sub-rows at fixed Y offsets.
--   Sub-row 1 (y=  0): [✓] Bar N: [Power▼]  ○Bar ○Pips
--   Sub-row 2 (y=-30): Unit: [Player▼]  W:[___] H:[___]  Pips:[_] PipSz:[_]  Fill:■ BG:■
--   Sub-row 3 (y=-58): Label:[__________]  ✓Show label  ✓Show value
local ROW_H  = 140
local ROW_Y0 = -70   -- y of first row's sub-row 1 relative to contentFrame TOPLEFT

-- Unit entries for the unit selector dropdown
local UNIT_ENTRIES = {
    {name="Player",          unit="player"},
    {name="Target",          unit="target"},
    {name="Focus",           unit="focus"},
    {name="Party 1 (Healer)",unit="party1"},
    {name="Party 2",         unit="party2"},
    {name="Party 3",         unit="party3"},
    {name="Party 4",         unit="party4"},
}

-- Shared unit dropdown popup (same approach as power dropdown)
local unitDropPopup = CreateFrame("Frame","CSResUnitDrop",UIParent,"BackdropTemplate")
unitDropPopup:SetSize(180,180); unitDropPopup:SetFrameStrata("TOOLTIP")
unitDropPopup:SetBackdrop({bgFile="Interface/DialogFrame/UI-DialogBox-Background",
    edgeFile="Interface/DialogFrame/UI-DialogBox-Border",
    tile=true,tileSize=16,edgeSize=16,insets={left=4,right=4,top=4,bottom=4}})
unitDropPopup:SetBackdropColor(0.08,0.08,0.12,0.98); unitDropPopup:Hide()

local udContent=CreateFrame("Frame","CSResUnitDropContent",unitDropPopup)
udContent:SetSize(160,1)
local udScroll=CreateFrame("ScrollFrame","CSResUnitDropScroll",unitDropPopup,"UIPanelScrollFrameTemplate")
udScroll:SetPoint("TOPLEFT",8,-8); udScroll:SetPoint("BOTTOMRIGHT",-28,8)
udScroll:SetScrollChild(udContent)

local function OpenUnitDrop(anchorBtn, onSelect)
    if unitDropPopup:IsShown() and unitDropPopup.anchor==anchorBtn then
        unitDropPopup:Hide(); return
    end
    unitDropPopup.anchor=anchorBtn
    for _,c in ipairs({udContent:GetChildren()}) do c:Hide() end
    local ROW=22
    for idx,entry in ipairs(UNIT_ENTRIES) do
        local btn=CreateFrame("Button",nil,udContent)
        btn:SetSize(155,ROW); btn:SetPoint("TOPLEFT",0,-(idx-1)*ROW)
        local hl=btn:CreateTexture(nil,"HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1,1,1,0.12)
        local lbl=btn:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
        lbl:SetPoint("LEFT",4,0); lbl:SetText(entry.name)
        local capE=entry
        btn:SetScript("OnClick",function()
            onSelect(capE.unit, capE.name)
            unitDropPopup:Hide()
        end)
    end
    udContent:SetHeight(#UNIT_ENTRIES*ROW)
    unitDropPopup:ClearAllPoints()
    unitDropPopup:SetPoint("TOPLEFT",anchorBtn,"BOTTOMLEFT",0,-4)
    unitDropPopup:Show()
end

local function CreateBarRow(i)
    -- Y positions for each sub-row (relative to contentFrame TOPLEFT)
    local y1 = ROW_Y0 - (i-1)*ROW_H        -- sub-row 1: enable + power + type
    local y2 = y1 - 30                       -- sub-row 2: unit + size + colour
    local y3 = y1 - 62                       -- sub-row 3: label + toggles

    -- Separator line above each row
    local sep = contentFrame:CreateTexture(nil,"BACKGROUND")
    sep:SetColorTexture(0.3,0.3,0.3,0.4); sep:SetSize(630,1)
    sep:SetPoint("TOPLEFT",0,y1+8)

    -- ── Sub-row 1 ─────────────────────────────────────────────────────────────
    local enableCb = CreateFrame("CheckButton","CSBar"..i.."Enable",contentFrame,"UICheckButtonTemplate")
    enableCb:SetSize(22,22); enableCb:SetPoint("TOPLEFT",0,y1)

    local barLbl = contentFrame:CreateFontString(nil,"OVERLAY","GameFontNormal")
    barLbl:SetPoint("LEFT",enableCb,"RIGHT",2,0); barLbl:SetText("Bar "..i..":")

    local powerBtn = CreateFrame("Button","CSBar"..i.."Power",contentFrame,"GameMenuButtonTemplate")
    powerBtn:SetSize(130,22); powerBtn:SetPoint("LEFT",barLbl,"RIGHT",6,0)
    powerBtn:SetText("(select power)"); powerBtn.powerType=nil

    local barRadio = CreateFrame("CheckButton","CSBar"..i.."IsBar",contentFrame,"UICheckButtonTemplate")
    barRadio:SetSize(18,18); barRadio:SetPoint("LEFT",powerBtn,"RIGHT",14,0); barRadio:SetChecked(true)
    local barRadioLbl=contentFrame:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    barRadioLbl:SetPoint("LEFT",barRadio,"RIGHT",2,0); barRadioLbl:SetText("Bar")

    local pipRadio = CreateFrame("CheckButton","CSBar"..i.."IsPip",contentFrame,"UICheckButtonTemplate")
    pipRadio:SetSize(18,18); pipRadio:SetPoint("LEFT",barRadioLbl,"RIGHT",10,0)
    local pipRadioLbl=contentFrame:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    pipRadioLbl:SetPoint("LEFT",pipRadio,"RIGHT",2,0); pipRadioLbl:SetText("Pips")

    barRadio:SetScript("OnClick",function(self)
        if self:GetChecked() then pipRadio:SetChecked(false) else self:SetChecked(true) end
    end)
    pipRadio:SetScript("OnClick",function(self)
        if self:GetChecked() then barRadio:SetChecked(false) else self:SetChecked(true) end
    end)

    -- ── Sub-row 2 ─────────────────────────────────────────────────────────────
    local unitLbl = contentFrame:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    unitLbl:SetPoint("TOPLEFT",0,y2); unitLbl:SetText("Unit:")

    local unitBtn = CreateFrame("Button","CSBar"..i.."Unit",contentFrame,"GameMenuButtonTemplate")
    unitBtn:SetSize(110,20); unitBtn:SetPoint("LEFT",unitLbl,"RIGHT",4,0)
    unitBtn:SetText("Player"); unitBtn.unit="player"

    local wLbl = contentFrame:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    wLbl:SetPoint("LEFT",unitBtn,"RIGHT",14,0); wLbl:SetText("W:")
    local wEdit = CreateFrame("EditBox","CSBar"..i.."W",contentFrame,"InputBoxTemplate")
    wEdit:SetSize(40,18); wEdit:SetAutoFocus(false); wEdit:SetMaxLetters(5)
    wEdit:SetPoint("LEFT",wLbl,"RIGHT",2,0); wEdit:SetText("200")

    local hLbl = contentFrame:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    hLbl:SetPoint("LEFT",wEdit,"RIGHT",8,0); hLbl:SetText("H:")
    local hEdit = CreateFrame("EditBox","CSBar"..i.."H",contentFrame,"InputBoxTemplate")
    hEdit:SetSize(35,18); hEdit:SetAutoFocus(false); hEdit:SetMaxLetters(4)
    hEdit:SetPoint("LEFT",hLbl,"RIGHT",2,0); hEdit:SetText("20")

    local pipCntLbl = contentFrame:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    pipCntLbl:SetPoint("LEFT",hEdit,"RIGHT",8,0); pipCntLbl:SetText("Pips:")
    local pipCountEdit = CreateFrame("EditBox","CSBar"..i.."PipCount",contentFrame,"InputBoxTemplate")
    pipCountEdit:SetSize(28,18); pipCountEdit:SetAutoFocus(false); pipCountEdit:SetMaxLetters(3)
    pipCountEdit:SetPoint("LEFT",pipCntLbl,"RIGHT",2,0); pipCountEdit:SetText("5")

    local pipSzLbl = contentFrame:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    pipSzLbl:SetPoint("LEFT",pipCountEdit,"RIGHT",8,0); pipSzLbl:SetText("Sz:")
    local pipSizeEdit = CreateFrame("EditBox","CSBar"..i.."PipSize",contentFrame,"InputBoxTemplate")
    pipSizeEdit:SetSize(28,18); pipSizeEdit:SetAutoFocus(false); pipSizeEdit:SetMaxLetters(3)
    pipSizeEdit:SetPoint("LEFT",pipSzLbl,"RIGHT",2,0); pipSizeEdit:SetText("18")

    local fillColLbl = contentFrame:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    fillColLbl:SetPoint("LEFT",pipSizeEdit,"RIGHT",12,0); fillColLbl:SetText("Fill:")
    local fillSwatch = CreateColourSwatch(contentFrame,"CSBar"..i.."FillCol",0.2,0.6,1,nil)
    fillSwatch:SetPoint("LEFT",fillColLbl,"RIGHT",4,0)

    local bgColLbl = contentFrame:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    bgColLbl:SetPoint("LEFT",fillSwatch,"RIGHT",10,0); bgColLbl:SetText("BG:")
    local bgSwatch = CreateColourSwatch(contentFrame,"CSBar"..i.."BgCol",0.1,0.1,0.1,nil)
    bgSwatch:SetPoint("LEFT",bgColLbl,"RIGHT",4,0)

    -- ── Sub-row 3 ─────────────────────────────────────────────────────────────
    local labelLbl = contentFrame:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    labelLbl:SetPoint("TOPLEFT",0,y3); labelLbl:SetText("Label:")
    local labelEdit = CreateFrame("EditBox","CSBar"..i.."Label",contentFrame,"InputBoxTemplate")
    labelEdit:SetSize(130,18); labelEdit:SetAutoFocus(false); labelEdit:SetMaxLetters(40)
    labelEdit:SetPoint("LEFT",labelLbl,"RIGHT",4,0)

    local showLabelCb = CreateFrame("CheckButton","CSBar"..i.."ShowLabel",contentFrame,"UICheckButtonTemplate")
    showLabelCb:SetSize(18,18); showLabelCb:SetPoint("LEFT",labelEdit,"RIGHT",14,0)
    local slLbl=contentFrame:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    slLbl:SetPoint("LEFT",showLabelCb,"RIGHT",2,0); slLbl:SetText("Show label")

    local showValueCb = CreateFrame("CheckButton","CSBar"..i.."ShowValue",contentFrame,"UICheckButtonTemplate")
    showValueCb:SetSize(18,18); showValueCb:SetPoint("LEFT",slLbl,"RIGHT",14,0)
    local svLbl=contentFrame:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    svLbl:SetPoint("LEFT",showValueCb,"RIGHT",2,0); svLbl:SetText("Show value")

    -- ── Dropdown wire-ups ─────────────────────────────────────────────────────
    powerBtn:SetScript("OnClick",function(self)
        OpenPowerDrop(self,function(pt,ptName)
            self.powerType=pt; self:SetText(ptName)
        end)
    end)
    unitBtn:SetScript("OnClick",function(self)
        OpenUnitDrop(self,function(unit,unitName)
            self.unit=unit; self:SetText(unitName)
        end)
    end)

    return {
        enableCb=enableCb, powerBtn=powerBtn, unitBtn=unitBtn,
        barRadio=barRadio, pipRadio=pipRadio,
        wEdit=wEdit, hEdit=hEdit,
        pipCountEdit=pipCountEdit, pipSizeEdit=pipSizeEdit,
        fillSwatch=fillSwatch, bgSwatch=bgSwatch,
        labelEdit=labelEdit, showLabelCb=showLabelCb, showValueCb=showValueCb,
        _sep=sep,
        -- Font strings and extra labels stored for show/hide
        _fontStrings={barLbl, barRadioLbl, pipRadioLbl, unitLbl,
                      wLbl, hLbl, pipCntLbl, pipSzLbl, fillColLbl, bgColLbl, labelLbl,
                      slLbl, svLbl},
    }
end

-- ── Build row widgets (hidden by default — shown only when added) ─────────────
local activeRows = 0   -- how many rows are currently shown

-- Pre-create all row widgets but hide them
for i = 1, MAX_BARS do
    rowWidgets[i] = CreateBarRow(i)
    -- Hide every element of this row by hiding its separator and enable checkbox
    -- We track visibility via a flag on the widget table
    rowWidgets[i]._visible = false
end

-- ── Row visibility helpers ────────────────────────────────────────────────────
local addBarBtn   -- forward declared, created below

local function SetRowVisible(i, visible)
    local w = rowWidgets[i]
    if not w then return end
    w._visible = visible
    -- Show/hide all child frames parented to contentFrame for this row.
    -- We use a simpler approach: each widget is already on contentFrame,
    -- so we show/hide the individual frames we have references to.
    local frames = {
        w.enableCb, w.powerBtn, w.unitBtn, w.barRadio, w.pipRadio,
        w.wEdit, w.hEdit, w.pipCountEdit, w.pipSizeEdit,
        w.fillSwatch, w.bgSwatch, w.labelEdit, w.showLabelCb, w.showValueCb,
    }
    for _, f in ipairs(frames) do
        if f then
            if visible then f:Show() else f:Hide() end
        end
    end
    -- Font strings need SetShown (available in WoW's Lua)
    if w._fontStrings then
        for _, fs in ipairs(w._fontStrings) do
            if fs then fs:SetShown(visible) end
        end
    end
    if w._sep then w._sep:SetAlpha(visible and 0.4 or 0) end
    if w._removeBtn then
        if visible then w._removeBtn:Show() else w._removeBtn:Hide() end
    end
end

local function UpdateAddBarBtn()
    if addBarBtn then
        local y = ROW_Y0 - activeRows * ROW_H - 10
        addBarBtn:ClearAllPoints()
        addBarBtn:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 0, y)
        if activeRows < MAX_BARS then
            addBarBtn:Show()
        else
            addBarBtn:Hide()
        end
        contentFrame:SetHeight(math.max(200, -y + 40))
    end
end

local function ShowRow(i)
    SetRowVisible(i, true)
    activeRows = i  -- rows are always shown in order 1..activeRows
    UpdateAddBarBtn()
end

local function HideRow(i)
    -- Reset this row's data
    local w = rowWidgets[i]
    if w then
        w.enableCb:SetChecked(false)
        w.powerBtn:SetText("(none)"); w.powerBtn.powerType = nil
        w.unitBtn:SetText("Player"); w.unitBtn.unit = "player"
        w.barRadio:SetChecked(true); w.pipRadio:SetChecked(false)
        w.wEdit:SetText("200"); w.hEdit:SetText("20")
        w.pipCountEdit:SetText("5"); w.pipSizeEdit:SetText("18")
        w.labelEdit:SetText("")
        w.showLabelCb:SetChecked(true); w.showValueCb:SetChecked(true)
    end
    -- Also clear the barConfig so it won't show a live bar
    local barConfigs = GetBarConfigs()
    if barConfigs then barConfigs[i] = nil end
    SetRowVisible(i, false)
    activeRows = i - 1
    UpdateAddBarBtn()
end

-- Attach remove buttons to each row (done after helpers are defined)
for i = 1, MAX_BARS do
    local w = rowWidgets[i]
    local removeBtn = CreateFrame("Button", "CSBar"..i.."Remove", contentFrame, "UIPanelButtonTemplate")
    removeBtn:SetSize(22, 22); removeBtn:SetText("X"); removeBtn:Hide()
    -- Position at far right of sub-row 1
    local y1 = ROW_Y0 - (i-1)*ROW_H
    removeBtn:SetPoint("TOPRIGHT", contentFrame, "TOPRIGHT", -4, y1+2)
    removeBtn:SetScript("OnClick", function() HideRow(i) end)
    w._removeBtn = removeBtn
    -- Store sep reference for alpha toggling
    -- (sep was created inside CreateBarRow; we need to recreate or reference it)
    -- Simpler: we'll just accept the sep line stays (it's subtle at 0 alpha anyway)
end

-- ── + Add Bar button (lives on contentFrame, not mainFrame) ──────────────────
addBarBtn = CreateFrame("Button", "CSBarsAddBtn", contentFrame, "GameMenuButtonTemplate")
addBarBtn:SetSize(110, 24); addBarBtn:SetText("+ Add Bar")
addBarBtn:SetScript("OnClick", function()
    if activeRows < MAX_BARS then
        local next = activeRows + 1
        ShowRow(next)
    end
end)
UpdateAddBarBtn()

-- ── Refresh UI from barConfigs ────────────────────────────────────────────────
local function RefreshResourceBarUI()
    local barConfigs = GetBarConfigs()
    -- Count how many saved configs exist to know which rows to show
    local savedCount = 0
    for i = 1, MAX_BARS do
        if barConfigs and barConfigs[i] then savedCount = i end
    end

    -- Show/hide rows based on saved data
    for i = 1, MAX_BARS do
        local cfg = barConfigs and barConfigs[i]
        if i <= savedCount then
            SetRowVisible(i, true)
        else
            SetRowVisible(i, false)
        end
        activeRows = savedCount

        local w = rowWidgets[i]
        if w and cfg then
            w.enableCb:SetChecked(cfg.enabled ~= false)
            w.powerBtn:SetText(PowerTypeName(cfg.powerType or 0))
            w.powerBtn.powerType = cfg.powerType
            local unitName = "Player"
            for _,e in ipairs(UNIT_ENTRIES) do if e.unit==(cfg.unit or "player") then unitName=e.name; break end end
            w.unitBtn:SetText(unitName); w.unitBtn.unit = cfg.unit or "player"
            w.barRadio:SetChecked(not cfg.isPip)
            w.pipRadio:SetChecked(cfg.isPip == true)
            w.wEdit:SetText(tostring(cfg.w or 200))
            w.hEdit:SetText(tostring(cfg.h or 20))
            w.pipCountEdit:SetText(tostring(cfg.maxPips or 5))
            w.pipSizeEdit:SetText(tostring(cfg.pipSize or 18))
            w.labelEdit:SetText(cfg.label or "")
            w.showLabelCb:SetChecked(cfg.showLabel ~= false)
            w.showValueCb:SetChecked(cfg.showValue ~= false)
            if w.fillSwatch then
                w.fillSwatch.r=cfg.r or 0.2; w.fillSwatch.g=cfg.g or 0.6; w.fillSwatch.b=cfg.b or 1
                w.fillSwatch.tex:SetColorTexture(w.fillSwatch.r,w.fillSwatch.g,w.fillSwatch.b,1)
            end
            if w.bgSwatch then
                w.bgSwatch.r=cfg.bgR or 0.1; w.bgSwatch.g=cfg.bgG or 0.1; w.bgSwatch.b=cfg.bgB or 0.1
                w.bgSwatch.tex:SetColorTexture(w.bgSwatch.r,w.bgSwatch.g,w.bgSwatch.b,1)
            end
        elseif w and not cfg then
            w.enableCb:SetChecked(false)
            w.powerBtn:SetText("(none)"); w.powerBtn.powerType=nil
            w.unitBtn:SetText("Player"); w.unitBtn.unit="player"
            w.barRadio:SetChecked(true); w.pipRadio:SetChecked(false)
            w.wEdit:SetText("200"); w.hEdit:SetText("20")
            w.pipCountEdit:SetText("5"); w.pipSizeEdit:SetText("18")
            w.labelEdit:SetText("")
            w.showLabelCb:SetChecked(true); w.showValueCb:SetChecked(true)
        end
    end
    UpdateAddBarBtn()
end
API.RefreshResourceBarUI = RefreshResourceBarUI

-- ── Harvest UI → barConfigs (called by main Save button) ─────────────────────
local function HarvestResourceBarUI()
    local barConfigs = GetBarConfigs()
    if not barConfigs then return end
    -- Clear all slots first
    for i = 1, MAX_BARS do barConfigs[i] = nil end
    -- Only harvest visible rows
    for i = 1, activeRows do
        local w = rowWidgets[i]
        if w and w._visible then
            -- Preserve dragged position and gap from existing config
            local oldCfg = barConfigs[i]
            barConfigs[i] = {
                x      = oldCfg and oldCfg.x or 0,
                y      = oldCfg and oldCfg.y or (-200 - (i-1)*30),
                pipGap = oldCfg and oldCfg.pipGap or 4,
            }
            local cfg = barConfigs[i]
            cfg.enabled   = w.enableCb:GetChecked()
            cfg.unit      = w.unitBtn and w.unitBtn.unit or "player"
            cfg.powerType = w.powerBtn.powerType or 0
            cfg.isPip     = w.pipRadio:GetChecked()
            cfg.isBar     = not cfg.isPip
            cfg.maxPips   = tonumber(w.pipCountEdit:GetText()) or 5
            cfg.pipSize   = tonumber(w.pipSizeEdit:GetText()) or 18
            cfg.w         = tonumber(w.wEdit:GetText()) or 200
            cfg.h         = tonumber(w.hEdit:GetText()) or 20
            cfg.label     = w.labelEdit:GetText()
            cfg.showLabel = w.showLabelCb:GetChecked()
            cfg.showValue = w.showValueCb:GetChecked()
            if w.fillSwatch then cfg.r=w.fillSwatch.r; cfg.g=w.fillSwatch.g; cfg.b=w.fillSwatch.b end
            if w.bgSwatch   then cfg.bgR=w.bgSwatch.r; cfg.bgG=w.bgSwatch.g; cfg.bgB=w.bgSwatch.b end
        end
    end
    if API.RebuildLiveBars then API.RebuildLiveBars() end
end
API.HarvestResourceBarUI = HarvestResourceBarUI

-- Register as a pre-save callback so harvest runs before OnSaveProfile writes to disk
-- API.RegisterPreSaveCallback fires before SaveSpecProfile's save callbacks
if API.RegisterPreSaveCallback then
    API.RegisterPreSaveCallback(HarvestResourceBarUI)
else
    -- Fallback: hook the save button (runs after SetScript but before profile write
    -- if we use a pre-hook approach)
    local saveBtn = _G["MidnightQoLSaveBtn"]
    if saveBtn then
        -- Use a pre-click hook by replacing the script
        local orig = saveBtn:GetScript("OnClick")
        saveBtn:SetScript("OnClick", function(self)
            HarvestResourceBarUI()
            if orig then orig(self) end
        end)
    end
end

-- ── Tab registration ──────────────────────────────────────────────────────────
local function OnResourcesTabActivate()
    RefreshResourceBarUI()
end
local function OnResourcesTabDeactivate()
    -- nothing to hide — no floating buttons
end

API.RegisterTab("Resources", contentFrame, OnResourcesTabActivate, 90, OnResourcesTabDeactivate, 3)