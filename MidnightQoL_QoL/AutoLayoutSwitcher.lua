-- ============================================================
-- MidnightQoL_QoL / AutoLayoutSwitcher.lua
-- Layout-centric config: each Edit Mode layout row lets you
-- assign a talent loadout and optionally auto-apply that
-- loadout when entering warmode, a BG, or an arena.
-- ============================================================

local API = MidnightQoLAPI

-- ── DB helpers ────────────────────────────────────────────────────────────────
-- alsLayoutRules: [layoutIndex(str)] = {
--     loadoutID     = number or nil,
--     loadoutName   = string,   -- name fallback if ID changes
--     pvpAutoApply  = bool,     -- apply this loadout in warmode/bg/arena
-- }

local DEFAULTS = {
    alsEnabled     = true,
    alsLayoutRules = {},
}

local function GetDB()
    if not BuffAlertDB then return DEFAULTS end
    for k, v in pairs(DEFAULTS) do
        if BuffAlertDB[k] == nil then BuffAlertDB[k] = v end
    end
    return BuffAlertDB
end

local function GetRules()
    local db = GetDB()
    db.alsLayoutRules = db.alsLayoutRules or {}
    return db.alsLayoutRules
end

local function GetRule(layoutIndex)
    return GetRules()[tostring(layoutIndex)]
end

local function SaveRule(layoutIndex, loadoutID, loadoutName, pvpAutoApply)
    GetRules()[tostring(layoutIndex)] = {
        loadoutID    = loadoutID,
        loadoutName  = loadoutName,
        pvpAutoApply = pvpAutoApply,
    }
end

local function ClearRule(layoutIndex)
    GetRules()[tostring(layoutIndex)] = nil
end

-- Account-wide default layout (shared across all characters)
local function GetAccountDB()
    if not MidnightQoLAccountDB then MidnightQoLAccountDB = {} end
    return MidnightQoLAccountDB
end

local function GetDefaultLayout()      return GetAccountDB().alsDefaultLayout end
local function SaveDefaultLayout(i,n)  GetAccountDB().alsDefaultLayout = {layoutIndex=i, layoutName=n} end
local function ClearDefaultLayout()    GetAccountDB().alsDefaultLayout = nil end

-- ── Edit Mode layout helpers ──────────────────────────────────────────────────
local function GetLayoutsRaw()
    if EditModeManagerFrame and EditModeManagerFrame.GetLayouts then
        return EditModeManagerFrame:GetLayouts() or {}
    end
    return {}
end

local function GetActiveLayoutIndex()
    if not EditModeManagerFrame then return nil end
    local info = EditModeManagerFrame.GetActiveLayoutInfo and EditModeManagerFrame:GetActiveLayoutInfo()
    if not info then return nil end
    if info.layoutIndex then return info.layoutIndex end
    if info.layoutName then
        for i, li in ipairs(GetLayoutsRaw()) do
            if li.layoutName == info.layoutName then return i end
        end
    end
    return nil
end

local function SetActiveLayout(layoutIndex)
    if InCombatLockdown() then return false end
    if C_EditMode and C_EditMode.SetActiveLayout then
        C_EditMode.SetActiveLayout(layoutIndex)
        return true
    end
    return false
end

-- ── Loadout helpers ───────────────────────────────────────────────────────────
local function GetActiveLoadoutID()
    if not (C_ClassTalents and C_ClassTalents.GetLastSelectedSavedConfigID) then return nil end
    local specIndex = GetSpecialization and GetSpecialization()
    if not specIndex then return nil end
    local specID = select(1, GetSpecializationInfo(specIndex))
    if not specID then return nil end
    local id = C_ClassTalents.GetLastSelectedSavedConfigID(specID)
    return (id and id ~= 0) and id or nil
end

local function GetLoadoutName(loadoutID)
    if C_Traits and C_Traits.GetConfigInfo then
        local info = C_Traits.GetConfigInfo(loadoutID)
        return info and info.name
    end
    return nil
end

local function GetSpecs()
    local specs = {}
    for i = 1, (GetNumSpecializations and GetNumSpecializations() or 0) do
        local id, name = GetSpecializationInfo(i)
        if id and name then specs[#specs+1] = {id=id, name=name, index=i} end
    end
    return specs
end

local function GetLoadoutsForSpec(specID)
    local out = {}
    if not (C_ClassTalents and C_ClassTalents.GetConfigIDsBySpecID) then return out end
    for _, configID in ipairs(C_ClassTalents.GetConfigIDsBySpecID(specID) or {}) do
        local info = C_Traits and C_Traits.GetConfigInfo and C_Traits.GetConfigInfo(configID)
        if info then out[#out+1] = {id=configID, name=info.name or tostring(configID)} end
    end
    return out
end

local function GetAllLoadouts()
    local out = {}
    for _, spec in ipairs(GetSpecs()) do
        for _, lo in ipairs(GetLoadoutsForSpec(spec.id)) do
            out[#out+1] = {id=lo.id, name=lo.name, specName=spec.name}
        end
    end
    return out
end

-- ── PvP zone detection ────────────────────────────────────────────────────────
local function IsInPvPZone()
    if C_PvP and C_PvP.IsWarModeDesired and C_PvP.IsWarModeDesired() then return true end
    local instanceType = select(2, IsInInstance())
    if instanceType == "arena" or instanceType == "pvp" then return true end
    return false
end

-- ── Core switch logic ─────────────────────────────────────────────────────────
local deferredSwitchPending = false

local function GetPvPRule()
    for idxStr, rule in pairs(GetRules()) do
        if rule.pvpAutoApply then
            return tonumber(idxStr), rule
        end
    end
    return nil, nil
end

local function TrySwitchLayout(force)
    local db = GetDB()
    if not db.alsEnabled then return end
    if InCombatLockdown() then deferredSwitchPending = true; return end

    local activeLayoutIndex = GetActiveLayoutIndex()

    -- PvP: if in a pvp zone, switch to the flagged layout and load its loadout
    if IsInPvPZone() then
        local pvpLayoutIdx, pvpRule = GetPvPRule()
        if pvpLayoutIdx then
            if pvpLayoutIdx ~= activeLayoutIndex then
                SetActiveLayout(pvpLayoutIdx)
                local layouts = GetLayoutsRaw()
                local lname = (layouts[pvpLayoutIdx] and layouts[pvpLayoutIdx].layoutName) or ("Layout "..pvpLayoutIdx)
                print(string.format("|cFF00CCFF[MidnightQoL]|r PvP zone — switched layout to |cFFFFD700%s|r", lname))
            end
            if pvpRule.loadoutID then
                local activeID = GetActiveLoadoutID()
                if force or activeID ~= pvpRule.loadoutID then
                    if C_ClassTalents and C_ClassTalents.LoadConfig then
                        C_ClassTalents.LoadConfig(pvpRule.loadoutID)
                        local loName = GetLoadoutName(pvpRule.loadoutID) or pvpRule.loadoutName or "PvP"
                        print(string.format("|cFF00CCFF[MidnightQoL]|r PvP zone — loaded talent loadout |cFFFFD700%s|r", loName))
                    end
                end
            end
            deferredSwitchPending = false
            return
        end
    end

    -- Normal: active layout drives which loadout to load
    if activeLayoutIndex then
        local rule = GetRule(activeLayoutIndex)
        if rule and rule.loadoutID then
            local activeID = GetActiveLoadoutID()
            if force or activeID ~= rule.loadoutID then
                if C_ClassTalents and C_ClassTalents.LoadConfig then
                    C_ClassTalents.LoadConfig(rule.loadoutID)
                    local lname = GetLoadoutName(rule.loadoutID) or rule.loadoutName or tostring(rule.loadoutID)
                    local layouts = GetLayoutsRaw()
                    local layoutName = (layouts[activeLayoutIndex] and layouts[activeLayoutIndex].layoutName) or ("Layout "..activeLayoutIndex)
                    print(string.format("|cFF00CCFF[MidnightQoL]|r Switched to loadout |cFFFFD700%s|r for layout |cFFFFD700%s|r", lname, layoutName))
                end
            end
        end
    end

    deferredSwitchPending = false
end

-- ── Event handler ─────────────────────────────────────────────────────────────
local alsEvents = CreateFrame("Frame")
alsEvents:RegisterEvent("PLAYER_LOGIN")
alsEvents:RegisterEvent("PLAYER_ENTERING_WORLD")
alsEvents:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
alsEvents:RegisterEvent("ACTIVE_PLAYER_SPECIALIZATION_CHANGED")
alsEvents:RegisterEvent("PLAYER_REGEN_ENABLED")
alsEvents:RegisterEvent("ZONE_CHANGED_NEW_AREA")
alsEvents:RegisterEvent("UPDATE_BATTLEFIELD_STATUS")
alsEvents:RegisterEvent("PVP_RATED_STATS_UPDATE")

alsEvents:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        C_Timer.After(1, function() TrySwitchLayout(true) end)
    elseif event == "PLAYER_REGEN_ENABLED" then
        if deferredSwitchPending then TrySwitchLayout(true) end
    elseif event == "PLAYER_ENTERING_WORLD" then
        C_Timer.After(0.5, function() TrySwitchLayout(true) end)
    elseif event == "ZONE_CHANGED_NEW_AREA" or event == "UPDATE_BATTLEFIELD_STATUS"
        or event == "PVP_RATED_STATS_UPDATE" then
        C_Timer.After(0.2, function() TrySwitchLayout(true) end)
    else
        TrySwitchLayout(false)
    end
end)

-- ── UI Tab ────────────────────────────────────────────────────────────────────
local alsFrame = CreateFrame("Frame", "MidnightQoLALSFrame", UIParent)
alsFrame:SetSize(620, 600); alsFrame:Hide()

-- Shared loadout picker popup
local loPopup = CreateFrame("Frame","MidnightALSLoadoutPopup",UIParent,"BackdropTemplate")
loPopup:SetSize(220,300); loPopup:SetFrameStrata("TOOLTIP")
loPopup:SetBackdrop({bgFile="Interface/DialogFrame/UI-DialogBox-Background",
    edgeFile="Interface/DialogFrame/UI-DialogBox-Border",
    tile=true,tileSize=16,edgeSize=16,insets={left=4,right=4,top=4,bottom=4}})
loPopup:SetBackdropColor(0.08,0.08,0.12,0.98); loPopup:Hide()
local loScroll = CreateFrame("ScrollFrame",nil,loPopup,"UIPanelScrollFrameTemplate")
loScroll:SetPoint("TOPLEFT",8,-8); loScroll:SetPoint("BOTTOMRIGHT",-28,8)
local loContent = CreateFrame("Frame",nil,loScroll)
loContent:SetSize(180,1); loScroll:SetScrollChild(loContent)

local function OpenLoadoutPicker(anchorBtn, onSelect)
    if loPopup:IsShown() and loPopup.anchor == anchorBtn then
        loPopup:Hide(); return
    end
    loPopup.anchor = anchorBtn
    for _, c in ipairs({loContent:GetChildren()}) do c:Hide() end

    local ROW_H = 22
    local rows  = {}

    -- None option
    local noneBtn = CreateFrame("Button",nil,loContent)
    noneBtn:SetSize(175,ROW_H)
    local noneHL = noneBtn:CreateTexture(nil,"HIGHLIGHT"); noneHL:SetAllPoints(); noneHL:SetColorTexture(1,1,1,0.12)
    local noneLbl = noneBtn:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    noneLbl:SetPoint("LEFT",4,0); noneLbl:SetText("|cFFAAAAAA(no loadout)|r")
    noneBtn:SetScript("OnClick", function() onSelect(nil,nil); loPopup:Hide() end)
    rows[#rows+1] = noneBtn

    local lastSpec = nil
    for _, lo in ipairs(GetAllLoadouts()) do
        if lo.specName ~= lastSpec then
            local hdr = CreateFrame("Frame",nil,loContent); hdr:SetSize(175,ROW_H)
            local hdrLbl = hdr:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
            hdrLbl:SetPoint("LEFT",4,0); hdrLbl:SetTextColor(1,0.8,0,1); hdrLbl:SetText(lo.specName)
            rows[#rows+1] = hdr; lastSpec = lo.specName
        end
        local btn = CreateFrame("Button",nil,loContent); btn:SetSize(175,ROW_H)
        local hl = btn:CreateTexture(nil,"HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1,1,1,0.12)
        local lbl = btn:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
        lbl:SetPoint("LEFT",14,0); lbl:SetText(lo.name)
        local capLo = lo
        btn:SetScript("OnClick", function() onSelect(capLo.id, capLo.name); loPopup:Hide() end)
        rows[#rows+1] = btn
    end

    local totalH = 0
    for _, r in ipairs(rows) do
        r:ClearAllPoints(); r:SetPoint("TOPLEFT",0,-totalH); r:Show()
        totalH = totalH + ROW_H
    end
    loContent:SetHeight(math.max(1,totalH))
    loPopup:SetHeight(math.min(300, totalH+16))
    loPopup:ClearAllPoints(); loPopup:SetPoint("TOPLEFT",anchorBtn,"BOTTOMLEFT",0,-4)
    loPopup:Show()
end

-- Widget pools
local layoutRows   = {}
local staticWidgets = {}  -- one-time labels/headers

local function GetLayoutOptions()
    local out = {}
    for i, info in ipairs(GetLayoutsRaw()) do
        out[#out+1] = {index=i, name=info.layoutName or ("Layout "..i)}
    end
    return out
end

local function RefreshPanel()
    local layouts        = GetLayoutOptions()
    local activeLayoutIdx = GetActiveLayoutIndex()
    local y = -16

    -- ── Enable toggle ─────────────────────────────────────────────────────────
    if not staticWidgets.enableToggle then
        local et = CreateFrame("CheckButton",nil,alsFrame,"UICheckButtonTemplate")
        et:SetSize(24,24); et:SetPoint("TOPLEFT",alsFrame,"TOPLEFT",16,y)
        et:SetScript("OnClick",function(self) GetDB().alsEnabled = self:GetChecked() end)
        local el = alsFrame:CreateFontString(nil,"ARTWORK","GameFontNormal")
        el:SetPoint("LEFT",et,"RIGHT",4,0)
        el:SetText("Auto-swap talent loadout when layout changes or entering PvP")
        staticWidgets.enableToggle = et
        staticWidgets.enableLabel  = el
    else
        staticWidgets.enableToggle:SetPoint("TOPLEFT",alsFrame,"TOPLEFT",16,y)
        staticWidgets.enableLabel:Show()
    end
    staticWidgets.enableToggle:SetChecked(GetDB().alsEnabled ~= false)
    y = y - 32

    -- ── Info lines ────────────────────────────────────────────────────────────
    if not staticWidgets.desc1 then
        staticWidgets.desc1 = alsFrame:CreateFontString(nil,"ARTWORK","GameFontNormalSmall")
        staticWidgets.desc1:SetTextColor(0.7,0.7,0.7,1)
        staticWidgets.desc1:SetText("Assign a talent loadout to each layout. It will be loaded automatically when that layout is active.")
    end
    staticWidgets.desc1:ClearAllPoints()
    staticWidgets.desc1:SetPoint("TOPLEFT",alsFrame,"TOPLEFT",16,y); y = y - 18

    if not staticWidgets.desc2 then
        staticWidgets.desc2 = alsFrame:CreateFontString(nil,"ARTWORK","GameFontNormalSmall")
        staticWidgets.desc2:SetTextColor(1,0.6,0.2,1)
        staticWidgets.desc2:SetText("⚔ Check PvP on one row to auto-switch that layout+loadout when entering warmode, a BG, or arena.")
    end
    staticWidgets.desc2:ClearAllPoints()
    staticWidgets.desc2:SetPoint("TOPLEFT",alsFrame,"TOPLEFT",16,y); y = y - 26

    -- Column headers
    if not staticWidgets.colLayout then
        staticWidgets.colLayout  = alsFrame:CreateFontString(nil,"ARTWORK","GameFontNormal")
        staticWidgets.colLoadout = alsFrame:CreateFontString(nil,"ARTWORK","GameFontNormal")
        staticWidgets.colPvP     = alsFrame:CreateFontString(nil,"ARTWORK","GameFontNormal")
        staticWidgets.colLayout:SetText("|cFFFFD700Layout|r")
        staticWidgets.colLoadout:SetText("|cFFFFD700Talent Loadout|r")
        staticWidgets.colPvP:SetText("|cFFFF9900⚔ PvP|r")
    end
    staticWidgets.colLayout:ClearAllPoints();  staticWidgets.colLayout:SetPoint("TOPLEFT",alsFrame,"TOPLEFT",16,y)
    staticWidgets.colLoadout:ClearAllPoints(); staticWidgets.colLoadout:SetPoint("TOPLEFT",alsFrame,"TOPLEFT",200,y)
    staticWidgets.colPvP:ClearAllPoints();     staticWidgets.colPvP:SetPoint("TOPLEFT",alsFrame,"TOPLEFT",490,y)
    y = y - 26

    -- ── Per-layout rows ────────────────────────────────────────────────────────
    for rowIdx, layout in ipairs(layouts) do
        local rule    = GetRule(layout.index)
        local isActive = (layout.index == activeLayoutIdx)

        -- Acquire/create row widgets
        local row = layoutRows[rowIdx]
        if not row then
            row = {}
            layoutRows[rowIdx] = row
            row.nameLbl    = alsFrame:CreateFontString(nil,"ARTWORK","GameFontHighlight")
            row.loadoutBtn = CreateFrame("Button","MidnightALSBtn"..rowIdx,alsFrame,"GameMenuButtonTemplate")
            row.loadoutBtn:SetSize(260,22)
            row.pvpCb      = CreateFrame("CheckButton",nil,alsFrame,"UICheckButtonTemplate")
            row.pvpCb:SetSize(22,22)
        end

        -- Layout name
        row.nameLbl:ClearAllPoints()
        row.nameLbl:SetPoint("TOPLEFT",alsFrame,"TOPLEFT",16,y)
        row.nameLbl:SetText(isActive and (layout.name.." |cFF00FF00◀|r") or layout.name)
        row.nameLbl:Show()

        -- Loadout button
        row.loadoutBtn:ClearAllPoints()
        row.loadoutBtn:SetPoint("TOPLEFT",alsFrame,"TOPLEFT",195,y+2)
        row.loadoutBtn:SetText((rule and rule.loadoutName) or "|cFFAAAAAA(no loadout)|r")
        row.loadoutBtn:Show()

        local capIdx  = layout.index
        local capRowIdx = rowIdx
        row.loadoutBtn:SetScript("OnClick", function(self)
            OpenLoadoutPicker(self, function(loadoutID, loadoutName)
                local r = GetRule(capIdx)
                local pvpFlag = r and r.pvpAutoApply or false
                if loadoutID then
                    SaveRule(capIdx, loadoutID, loadoutName, pvpFlag)
                    self:SetText(loadoutName)
                else
                    if pvpFlag then SaveRule(capIdx, nil, nil, true)
                    else ClearRule(capIdx) end
                    self:SetText("|cFFAAAAAA(no loadout)|r")
                end
            end)
        end)

        -- PvP checkbox
        row.pvpCb:ClearAllPoints()
        row.pvpCb:SetPoint("TOPLEFT",alsFrame,"TOPLEFT",492,y+2)
        row.pvpCb:SetChecked(rule and rule.pvpAutoApply or false)
        row.pvpCb:Show()

        row.pvpCb:SetScript("OnClick", function(self)
            local checked = self:GetChecked()
            local r = GetRule(capIdx)
            if checked or (r and r.loadoutID) then
                SaveRule(capIdx, r and r.loadoutID, r and r.loadoutName, checked)
            else
                ClearRule(capIdx)
            end
            -- Enforce single PvP rule
            if checked then
                for otherRowIdx, otherRow in ipairs(layoutRows) do
                    if otherRowIdx ~= capRowIdx and otherRow.pvpCb then
                        otherRow.pvpCb:SetChecked(false)
                        local otherLayout = layouts[otherRowIdx]
                        if otherLayout then
                            local or2 = GetRule(otherLayout.index)
                            if or2 then SaveRule(otherLayout.index, or2.loadoutID, or2.loadoutName, false) end
                        end
                    end
                end
            end
        end)

        y = y - 30
    end

    -- Hide excess rows
    for i = #layouts + 1, #layoutRows do
        local r = layoutRows[i]
        if r then
            if r.nameLbl    then r.nameLbl:Hide() end
            if r.loadoutBtn then r.loadoutBtn:Hide() end
            if r.pvpCb      then r.pvpCb:Hide() end
        end
    end
end

alsFrame:SetScript("OnShow", RefreshPanel)

-- ── Register tab ──────────────────────────────────────────────────────────────
local alsTabEvents = CreateFrame("Frame")
alsTabEvents:RegisterEvent("PLAYER_LOGIN")
alsTabEvents:SetScript("OnEvent", function(self, event)
    if event ~= "PLAYER_LOGIN" then return end
    self:UnregisterEvent("PLAYER_LOGIN")
    C_Timer.After(0.1, function()
        if not API.RegisterTab then return end
        API.RegisterTab("Layouts", alsFrame, RefreshPanel, 70, nil, 2)
    end)
end)

API.ALSTrySwitchLayout    = TrySwitchLayout
API.ALSGetActiveLoadoutID = GetActiveLoadoutID

API.Debug("[MidnightQoL] AutoLayoutSwitcher loaded.")
