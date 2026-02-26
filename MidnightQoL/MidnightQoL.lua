-- ============================================================
-- MidnightQoL.lua  (Core)
-- Main window, minimap button, layout mode, spec profile
-- save/load, profile copy system, sound engine, Setup Guide.
-- ============================================================

local API = MidnightQoLAPI

-- ── Debug helper ──────────────────────────────────────────────────────────────
local function Debug(msg)
    if API.DEBUG then
        print("|cFF00FF00[MidnightQoL DEBUG]|r " .. tostring(msg))
    end
end
API.Debug = Debug

-- ── Name normalisation helpers ────────────────────────────────────────────────
local function NormalizeName(name)
    if not name or name == "" then return "" end
    local s = tostring(name):match("^([^%-]+)") or tostring(name)
    return s:match("^%s*(.-)%s*$"):lower()
end
local function NormalizeBNName(name)
    if not name or name == "" then return "" end
    return tostring(name):match("^%s*(.-)%s*$"):lower()
end
API.NormalizeName   = NormalizeName
API.NormalizeBNName = NormalizeBNName

-- ── Sound engine ──────────────────────────────────────────────────────────────
local customSoundFiles = (type(SoundsList) == "table") and SoundsList or {}

local function GetAvailableSounds()
    local sounds = {
        {name = "Quest Complete", path = 12743, isID = true},
        {name = "Default Alert",  path = 12743, isID = true},
    }
    for _, entry in ipairs(customSoundFiles) do
        local filename, displayName
        if type(entry) == "table" then
            filename    = entry.file
            displayName = entry.displayName or entry.file
        else
            filename    = entry
            displayName = entry
        end
        local soundPath = "Interface/AddOns/MidnightQoL/Sounds/" .. filename .. ".ogg"
        table.insert(sounds, {name = displayName, path = soundPath, isID = false})
    end
    return sounds
end

local customImageFiles = (type(ImagesList) == "table") and ImagesList or {}

local function GetAvailableImages()
    local images = {
        {name = "Spell Icon (auto)",     path = "spell_icon",         isSpellIcon = true},
        {name = "── Common Icons ──",    path = nil,                  isSeparator = true},
        {name = "Warning Diamond",       path = "Interface\\DialogFrame\\UI-Dialog-Icon-AlertOther"},
        {name = "Skull",                 path = "Interface\\TargetingFrame\\UI-TargetingFrame-Skull"},
        {name = "Raid Target - Star",    path = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_1"},
        {name = "Raid Target - Circle",  path = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_2"},
        {name = "Raid Target - Diamond", path = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_3"},
        {name = "Raid Target - Triangle",path = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_4"},
        {name = "Raid Target - Moon",    path = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_5"},
        {name = "Raid Target - Square",  path = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_6"},
        {name = "Raid Target - Cross",   path = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_7"},
        {name = "Raid Target - Skull",   path = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8"},
        {name = "Interrupt (red X)",     path = "Interface\\Icons\\Ability_Kick"},
        {name = "Defensive CD",          path = "Interface\\Icons\\Spell_Shadow_NetherProtection"},
        {name = "Heal",                  path = "Interface\\Icons\\Spell_Holy_FlashHeal"},
        {name = "Lightning",             path = "Interface\\Icons\\Spell_Nature_Lightning"},
        {name = "Fire",                  path = "Interface\\Icons\\Spell_Fire_Fireball02"},
        {name = "Frost",                 path = "Interface\\Icons\\Spell_Frost_FrostBolt02"},
        {name = "Shadow",                path = "Interface\\Icons\\Spell_Shadow_ShadowBolt"},
        {name = "Arcane",                path = "Interface\\Icons\\Spell_Holy_MagicalSentry"},
        {name = "Nature",                path = "Interface\\Icons\\Spell_Nature_Starfall"},
        {name = "Bloodlust / Heroism",   path = "Interface\\Icons\\Spell_Nature_Bloodlust"},
        {name = "Power Infusion",        path = "Interface\\Icons\\Spell_Holy_PowerInfusion"},
        {name = "── Addon Images ──",    path = nil,                  isSeparator = true},
    }
    for _, entry in ipairs(customImageFiles) do
        local path, displayName
        if type(entry) == "table" then
            path        = entry.file
            displayName = entry.displayName or entry.file
        else
            path        = entry
            displayName = entry
        end
        if not path:find("\\") and not path:find("/") then
            path = "Interface/AddOns/MidnightQoL/Images/" .. path
        end
        table.insert(images, {name = displayName, path = path})
    end
    return images
end

local function PlayCustomSound(soundPath, isID)
    if not soundPath then return end
    local ok, err = pcall(function()
        local numericID = tonumber(soundPath)
        if numericID then PlaySound(numericID, "SFX", false)
        else PlaySoundFile(tostring(soundPath), "SFX") end
    end)
    if not ok then Debug("PlayCustomSound error: " .. tostring(err)) end
end

API.PlayCustomSound    = PlayCustomSound
API.GetAvailableSounds = GetAvailableSounds
API.GetAvailableImages = GetAvailableImages

-- ── Spec profile system ────────────────────────────────────────────────────────
local function GetSpecProfileKey()
    return (API.playerClass or "UNKNOWN") .. "_" .. tostring(API.currentSpecID or 0)
end

local function GetOrCreateSpecProfile(key)
    if not BuffAlertDB then return nil end
    if not BuffAlertDB.specProfiles then BuffAlertDB.specProfiles = {} end
    local k = key or GetSpecProfileKey()
    if not BuffAlertDB.specProfiles[k] then
        BuffAlertDB.specProfiles[k] = {}
    end
    return BuffAlertDB.specProfiles[k]
end

local function SaveSpecProfile()
    local profile = GetOrCreateSpecProfile()
    if not profile then return end
    for _, cb in ipairs(API._saveCallbacks) do
        local ok, err = pcall(cb, profile)
        if not ok then Debug("SaveSpecProfile callback error: " .. tostring(err)) end
    end
    Debug("Saved spec profile: " .. GetSpecProfileKey())
end

local function LoadSpecProfile(key)
    local profile = GetOrCreateSpecProfile(key)
    if not profile then return end
    for _, cb in ipairs(API._loadCallbacks) do
        local ok, err = pcall(cb, profile)
        if not ok then Debug("LoadSpecProfile callback error: " .. tostring(err)) end
    end
    Debug("Loaded spec profile: " .. (key or GetSpecProfileKey()))
end

local function RegisterProfileCallbacks(saveFunc, loadFunc)
    if saveFunc then table.insert(API._saveCallbacks, saveFunc) end
    if loadFunc then table.insert(API._loadCallbacks, loadFunc) end
end

API.GetSpecProfileKey        = GetSpecProfileKey
API.GetOrCreateSpecProfile   = GetOrCreateSpecProfile
API.SaveSpecProfile          = SaveSpecProfile
API.LoadSpecProfile          = LoadSpecProfile
API.RegisterProfileCallbacks  = RegisterProfileCallbacks
API.RegisterPreSaveCallback   = function(fn)
    table.insert(API._preSaveCallbacks, fn)
end

-- ── Profile deep-copy helper ──────────────────────────────────────────────────
local function DeepCopy(orig)
    local copy
    if type(orig) == "table" then
        copy = {}
        for k, v in pairs(orig) do
            copy[DeepCopy(k)] = DeepCopy(v)
        end
        setmetatable(copy, getmetatable(orig))
    else
        copy = orig
    end
    return copy
end
API.DeepCopy = DeepCopy

-- ── Main window ────────────────────────────────────────────────────────────────
local mainFrame = CreateFrame("Frame", "MidnightQoLMainFrame", UIParent, "BackdropTemplate")
mainFrame:SetSize(700, 600)
mainFrame:SetPoint("CENTER", UIParent, "CENTER", 0, -50)
mainFrame:SetBackdrop({
    bgFile   = "Interface/DialogFrame/UI-DialogBox-Background",
    edgeFile = "Interface/DialogFrame/UI-DialogBox-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = {left = 11, right = 12, top = 12, bottom = 11}
})
mainFrame:SetBackdropColor(0.1, 0.1, 0.1, 0.8)
mainFrame:SetMovable(true); mainFrame:EnableMouse(true)
mainFrame:RegisterForDrag("LeftButton"); mainFrame:SetClampedToScreen(true)
mainFrame:SetScript("OnDragStart", function(self) self:StartMoving() end)
mainFrame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    if BuffAlertDB then
        local point, _, relPoint, x, y = self:GetPoint()
        BuffAlertDB.mainFramePos = {point=point, relPoint=relPoint, x=x, y=y}
    end
end)
mainFrame:Hide()

local title = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
title:SetPoint("TOPLEFT", 20, -20); title:SetText("Midnight QoL Configuration")

local closeBtn = CreateFrame("Button", nil, mainFrame, "UIPanelCloseButton")
closeBtn:SetPoint("TOPRIGHT", mainFrame, "TOPRIGHT", -5, -5)

-- Scroll frame (hosts whichever content frame is active)
local scrollFrame = CreateFrame("ScrollFrame", "MidnightQoLScrollFrame", mainFrame, "UIPanelScrollFrameTemplate")
scrollFrame:SetPoint("TOPLEFT", 20, -90)
scrollFrame:SetPoint("BOTTOMRIGHT", -35, 50)

-- ── Tab system ─────────────────────────────────────────────────────────────────
-- Each entry: { label, frame, onActivate, onDeactivate, width }
local tabRegistry     = {}
local tabButtons      = {}
local currentTabIndex = 1

local function ActivateTabByIndex(i)
    -- Call deactivate on old tab
    if tabRegistry[currentTabIndex] and tabRegistry[currentTabIndex].onDeactivate then
        tabRegistry[currentTabIndex].onDeactivate()
    end
    -- Hide all registered frames
    for _, entry in ipairs(tabRegistry) do
        if entry.frame then entry.frame:Hide() end
    end
    -- Highlight correct button
    for j, btn in ipairs(tabButtons) do
        if j == i then
            btn:SetNormalFontObject("GameFontHighlightSmall")
            btn:LockHighlight()
        else
            btn:SetNormalFontObject("GameFontNormalSmall")
            btn:UnlockHighlight()
        end
    end
    currentTabIndex = i
    local entry = tabRegistry[i]
    if not entry then return end
    entry.frame:SetParent(scrollFrame)
    entry.frame:SetPoint("TOPLEFT", 0, 0)
    scrollFrame:SetScrollChild(entry.frame)
    entry.frame:Show()
    if entry.onActivate then entry.onActivate() end
    -- Notify add-button manager
    if API.UpdateAddButtons then API.UpdateAddButtons(i) end
end

local function RebuildTabBar()
    -- Deactivate current tab before rebuilding so its buttons/state are cleaned up
    if tabRegistry[currentTabIndex] and tabRegistry[currentTabIndex].onDeactivate then
        tabRegistry[currentTabIndex].onDeactivate()
    end
    for _, btn in ipairs(tabButtons) do btn:Hide(); btn:SetParent(nil) end
    tabButtons = {}
    local TAB_GAP = 8
    local nextX   = 20
    for i, entry in ipairs(tabRegistry) do
        local w   = entry.width or 80
        local btn = CreateFrame("Button", "MidnightQoLTab" .. i, mainFrame, "GameMenuButtonTemplate")
        btn:SetSize(w, 25)
        btn:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", nextX, -50)
        btn:SetText(entry.label)
        btn.tabIndex = i
        btn:SetScript("OnClick", function(self)
            ActivateTabByIndex(self.tabIndex)
        end)
        tabButtons[i] = btn
        nextX = nextX + w + TAB_GAP
    end
    -- Re-activate current tab to fix highlight state
    if #tabRegistry > 0 then
        ActivateTabByIndex(math.min(currentTabIndex, #tabRegistry))
    end
end

local function RegisterTab(label, frame, onActivate, widthOverride, onDeactivate, priority)
    table.insert(tabRegistry, {
        label        = label,
        frame        = frame,
        onActivate   = onActivate,
        onDeactivate = onDeactivate,
        width        = widthOverride,
        priority     = priority or 50,
    })
    -- Sort by priority (lower number = further left)
    table.sort(tabRegistry, function(a, b) return (a.priority or 50) < (b.priority or 50) end)
    RebuildTabBar()
    -- First tab registered becomes active
    if #tabRegistry == 1 then
        ActivateTabByIndex(1)
    end
end

API.RegisterTab        = RegisterTab
API.ActivateTabByIndex = ActivateTabByIndex
API.GetCurrentTabIndex = function() return currentTabIndex end
API.GetTabRegistry     = function() return tabRegistry end

-- ── Bottom bar ─────────────────────────────────────────────────────────────────
-- Save button sits at BOTTOMRIGHT; add-buttons from sub-addons sit at BOTTOMLEFT.
-- Both live at y=50 so they clear the scroll frame edge.
local saveBtn = CreateFrame("Button", "MidnightQoLSaveBtn", mainFrame, "GameMenuButtonTemplate")
saveBtn:SetSize(100, 25)
saveBtn:SetPoint("BOTTOMRIGHT", mainFrame, "BOTTOMRIGHT", -20, 15)
saveBtn:SetText("Save")
saveBtn:SetScript("OnClick", function()
    -- Run pre-save callbacks first (e.g. harvest UI → configs)
    for _, cb in ipairs(API._preSaveCallbacks) do pcall(cb) end
    SaveSpecProfile()
    mainFrame:Hide()
end)

local setupLinkBtn = CreateFrame("Button", "MidnightQoLSetupLinkBtn", mainFrame, "GameMenuButtonTemplate")
setupLinkBtn:SetSize(120, 25)
setupLinkBtn:SetPoint("BOTTOMLEFT", mainFrame, "BOTTOMLEFT", 20, 15)
setupLinkBtn:SetText("Setup Guide")

local layoutModeBtn = CreateFrame("Button", "MidnightQoLLayoutModeBtn", mainFrame, "GameMenuButtonTemplate")
layoutModeBtn:SetSize(120, 25)
layoutModeBtn:SetPoint("LEFT", setupLinkBtn, "RIGHT", 6, 0)
layoutModeBtn:SetText("Edit Layout")

local specInfoLabel = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
specInfoLabel:SetPoint("LEFT", layoutModeBtn, "RIGHT", 14, 0)
specInfoLabel:SetWidth(240); specInfoLabel:SetJustifyH("LEFT")
specInfoLabel:SetTextColor(0.75, 0.75, 0.75, 1)
specInfoLabel:SetText("Active Spec: loading...")
API.specInfoLabel = specInfoLabel

-- ── Setup Guide panel ─────────────────────────────────────────────────────────
local setupPanel = CreateFrame("Frame", "MidnightQoLSetupPanel", UIParent, "BackdropTemplate")
setupPanel:SetSize(500, 400); setupPanel:SetPoint("CENTER")
setupPanel:SetFrameStrata("DIALOG")
setupPanel:SetBackdrop({
    bgFile   = "Interface/DialogFrame/UI-DialogBox-Background",
    edgeFile = "Interface/DialogFrame/UI-DialogBox-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = {left = 8, right = 8, top = 8, bottom = 8}
})
setupPanel:SetBackdropColor(0.05, 0.05, 0.1, 0.97)
setupPanel:SetMovable(true); setupPanel:EnableMouse(true)
setupPanel:RegisterForDrag("LeftButton")
setupPanel:SetScript("OnDragStart", function(self) self:StartMoving() end)
setupPanel:SetScript("OnDragStop",  function(self) self:StopMovingOrSizing() end)
setupPanel:Hide()

do
    local t = setupPanel:CreateFontString(nil,"OVERLAY","GameFontNormalLarge")
    t:SetPoint("TOP",0,-12); t:SetText("Setup Guide")
    local cb = CreateFrame("Button",nil,setupPanel,"UIPanelCloseButton"); cb:SetPoint("TOPRIGHT",-4,-4)
    local scr = CreateFrame("ScrollFrame","MidnightQoLSetupScroll",setupPanel,"UIPanelScrollFrameTemplate")
    scr:SetPoint("TOPLEFT",12,-36); scr:SetPoint("BOTTOMRIGHT",-30,12)
    local con = CreateFrame("Frame","MidnightQoLSetupContent",scr)
    con:SetSize(440,1); scr:SetScrollChild(con)
    local txt = con:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    txt:SetPoint("TOPLEFT",4,-4); txt:SetWidth(432)
    txt:SetJustifyH("LEFT"); txt:SetJustifyV("TOP"); txt:SetWordWrap(true)
    local guideText = (type(SETUP_GUIDE_TEXT)=="string" and SETUP_GUIDE_TEXT~="")
        and SETUP_GUIDE_TEXT or "|cFFFFD700Setup Guide|r\n\nSetupGuide.lua not found or empty."
    txt:SetText(guideText)
    setupLinkBtn:SetScript("OnClick", function()
        if setupPanel:IsShown() then setupPanel:Hide()
        else setupPanel:Show(); con:SetHeight(math.max(400, txt:GetStringHeight()+20)) end
    end)
end

-- ── Layout mode ────────────────────────────────────────────────────────────────
local layoutHandles = {}
local layoutActive  = false

local layoutDimmer = CreateFrame("Frame", "MidnightQoLLayoutDimmer", UIParent)
layoutDimmer:SetAllPoints(UIParent); layoutDimmer:SetFrameStrata("MEDIUM")
layoutDimmer:EnableMouse(false); layoutDimmer:Hide()
local dimTex = layoutDimmer:CreateTexture(nil,"BACKGROUND")
dimTex:SetAllPoints(); dimTex:SetColorTexture(0,0,0,0.45)

local layoutDoneBtn = CreateFrame("Button","MidnightQoLLayoutDoneBtn",UIParent,"GameMenuButtonTemplate")
layoutDoneBtn:SetSize(120,30); layoutDoneBtn:SetPoint("TOP",UIParent,"TOP",0,-10)
layoutDoneBtn:SetFrameStrata("FULLSCREEN_DIALOG"); layoutDoneBtn:SetText("[OK]  Done Editing"); layoutDoneBtn:Hide()

local function GetOrCreateHandle(i)
    if layoutHandles[i] then return layoutHandles[i] end
    local h = CreateFrame("Frame","MidnightQoLLayoutHandle"..i,UIParent,"BackdropTemplate")
    h:SetFrameStrata("FULLSCREEN_DIALOG")
    h:SetBackdrop({
        bgFile   = "Interface/DialogFrame/UI-DialogBox-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile=true, tileSize=8, edgeSize=8, insets={left=2,right=2,top=2,bottom=2}
    })
    h:SetBackdropColor(0.1,0.3,0.6,0.75); h:SetBackdropBorderColor(0.6,0.9,1,0.9)
    h:SetMovable(true); h:EnableMouse(true); h:RegisterForDrag("LeftButton"); h:SetClampedToScreen(true)
    local icon = h:CreateTexture(nil,"ARTWORK"); icon:SetSize(32,32); icon:SetPoint("LEFT",6,0); h.icon=icon
    local lbl  = h:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    lbl:SetPoint("LEFT",44,4); lbl:SetWidth(150); lbl:SetJustifyH("LEFT"); h.lbl=lbl
    local pos  = h:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    pos:SetPoint("LEFT",44,-8); pos:SetWidth(150); pos:SetJustifyH("LEFT"); pos:SetTextColor(0.7,0.9,1,1); h.posLbl=pos
    h:SetSize(210,46)
    h:SetScript("OnDragStart",function(self) self.isDragging=true; self:StartMoving() end)
    h:SetScript("OnDragStop",function(self)
        self:StopMovingOrSizing(); self.isDragging=false
        local cx=UIParent:GetWidth()/2; local cy=UIParent:GetHeight()/2
        local ox=math.floor(self:GetLeft()+self:GetWidth()/2-cx+0.5)
        local oy=math.floor(self:GetBottom()+self:GetHeight()/2-cy+0.5)
        self.posLbl:SetText("x="..ox.."  y="..oy)
        if self.previewOverlay and self.previewOverlay:IsShown() then
            self.previewOverlay:ClearAllPoints(); self.previewOverlay:SetPoint("CENTER",UIParent,"CENTER",ox,oy) end
        if self.liveIconTarget then
            local icon=_G[self.liveIconTarget]
            if icon then icon:ClearAllPoints(); icon:SetPoint("CENTER",UIParent,"CENTER",ox,oy) end end
        if self.liveFrameRef and self.liveFrameRef.ClearAllPoints then
            self.liveFrameRef:ClearAllPoints(); self.liveFrameRef:SetPoint("CENTER",UIParent,"CENTER",ox,oy) end
        if self.saveCallback then self.saveCallback(ox,oy) end
    end)
    h:SetScript("OnUpdate",function(self)
        if not self.isDragging then return end
        local cx=UIParent:GetWidth()/2; local cy=UIParent:GetHeight()/2
        local ox=self:GetLeft()+self:GetWidth()/2-cx; local oy=self:GetBottom()+self:GetHeight()/2-cy
        if self.previewOverlay and self.previewOverlay:IsShown() then
            self.previewOverlay:ClearAllPoints(); self.previewOverlay:SetPoint("CENTER",UIParent,"CENTER",ox,oy) end
        if self.liveIconTarget then
            local icon=_G[self.liveIconTarget]
            if icon then icon:ClearAllPoints(); icon:SetPoint("CENTER",UIParent,"CENTER",ox,oy) end end
        if self.liveFrameRef and self.liveFrameRef.ClearAllPoints then
            self.liveFrameRef:ClearAllPoints(); self.liveFrameRef:SetPoint("CENTER",UIParent,"CENTER",ox,oy) end
    end)
    layoutHandles[i]=h; return h
end

local function HideAllHandles()
    for _,h in ipairs(layoutHandles) do
        h.previewOverlay=nil; h.liveIconTarget=nil; h.liveFrameRef=nil; h:Hide() end
end

local function EnterLayoutMode()
    if layoutActive then return end
    layoutActive=true; layoutDimmer:Show(); layoutDoneBtn:Show()
    local handleIdx=0
    local function ShowHandle(label,iconTex,ox,oy,saveCallback)
        handleIdx=handleIdx+1; local h=GetOrCreateHandle(handleIdx)
        h:ClearAllPoints(); h:SetPoint("CENTER",UIParent,"CENTER",ox,oy)
        h.lbl:SetText(label); h.posLbl:SetText("x="..ox.."  y="..oy)
        h.saveCallback=saveCallback
        h.icon:SetTexture(iconTex or "Interface\\Icons\\INV_Misc_QuestionMark"); h.icon:Show(); h:Show()
        return h
    end
    for _,provider in ipairs(API._layoutProviders) do
        local ok,handles=pcall(provider)
        if ok and handles then
            for _,hd in ipairs(handles) do
                local h=ShowHandle(hd.label,hd.iconTex,hd.ox or 0,hd.oy or 0,hd.saveCallback)
                if hd.liveIconTarget then h.liveIconTarget=hd.liveIconTarget end
                if hd.liveFrameRef   then h.liveFrameRef=hd.liveFrameRef   end
                if hd.previewFunc    then
                    local ov=hd.previewFunc(); if ov then h.previewOverlay=ov end end
            end
        end
    end
    layoutDoneBtn:SetText(handleIdx<=0 and "[OK]  Done (add alerts with textures to position)" or "[OK]  Done Editing")
end

local function ExitLayoutMode()
    if not layoutActive then return end
    layoutActive=false; layoutDimmer:Hide(); layoutDoneBtn:Hide(); HideAllHandles()
    if API.HideAlertPreviews then API.HideAlertPreviews() end
    SaveSpecProfile()
end

layoutDoneBtn:SetScript("OnClick",ExitLayoutMode)
layoutModeBtn:SetScript("OnClick",EnterLayoutMode)
API.EnterLayoutMode=EnterLayoutMode; API.ExitLayoutMode=ExitLayoutMode

local function RegisterLayoutHandles(providerFunc)
    table.insert(API._layoutProviders,providerFunc)
end
API.RegisterLayoutHandles=RegisterLayoutHandles

-- ── Minimap button ─────────────────────────────────────────────────────────────
local minimapBtn=CreateFrame("Button","MidnightQoLMinimapBtn",Minimap)
minimapBtn:SetSize(32,32); minimapBtn:SetFrameStrata("MEDIUM"); minimapBtn:SetFrameLevel(8)
minimapBtn:SetClampedToScreen(true)
do
    local bg=minimapBtn:CreateTexture(nil,"BACKGROUND"); bg:SetSize(32,32)
    bg:SetPoint("CENTER",minimapBtn,"CENTER",0,0); bg:SetColorTexture(0,0,0,0.55)
    local ic=minimapBtn:CreateTexture(nil,"ARTWORK"); ic:SetSize(26,26)
    ic:SetPoint("CENTER",minimapBtn,"CENTER",0,0)
    ic:SetTexture("Interface/AddOns/MidnightQoL/Images/minimap_icon")
    ic:SetTexCoord(0.08,0.92,0.08,0.92)
    local hl=minimapBtn:CreateTexture(nil,"HIGHLIGHT"); hl:SetAllPoints(minimapBtn); hl:SetColorTexture(1,1,1,0.15)
end

local minimapDragging=false
local function UpdateMinimapPos(angle,radius)
    radius=math.max(60,math.min(110,radius or 80)); angle=angle or 225
    if BuffAlertDB then BuffAlertDB.minimapAngle=angle; BuffAlertDB.minimapRadius=radius end
    minimapBtn:ClearAllPoints()
    minimapBtn:SetPoint("CENTER",Minimap,"CENTER",
        math.cos(math.rad(angle))*radius, math.sin(math.rad(angle))*radius)
end

minimapBtn:SetScript("OnClick",function(self,button)
    if button=="RightButton" then EnterLayoutMode()
    else
        if mainFrame:IsShown() then mainFrame:Hide()
        else
            mainFrame:Show()
            if tabButtons[1] then ActivateTabByIndex(1) end
        end
    end
end)
minimapBtn:SetScript("OnEnter",function(self)
    GameTooltip:SetOwner(self,"ANCHOR_LEFT")
    GameTooltip:AddLine("Midnight QoL",1,1,0)
    GameTooltip:AddLine("|cFFAAAAFF Left-click|r  Open settings",0.8,0.8,0.8)
    GameTooltip:AddLine("|cFFAAAAFF Right-click|r  Edit Layout",0.8,0.8,0.8)
    GameTooltip:AddLine("|cFFAAAAFF Drag|r  Reposition",0.8,0.8,0.8)
    GameTooltip:Show()
end)
minimapBtn:SetScript("OnLeave",function() GameTooltip:Hide() end)
minimapBtn:EnableMouse(true)
minimapBtn:SetScript("OnMouseDown",function(self,button)
    if button=="LeftButton" then
        minimapDragging=true
        self:SetScript("OnUpdate",function()
            if not minimapDragging then self:SetScript("OnUpdate",nil); return end
            local mx,my=Minimap:GetCenter(); local cx,cy=GetCursorPosition()
            local scale=UIParent:GetEffectiveScale(); cx,cy=cx/scale,cy/scale
            UpdateMinimapPos(math.deg(math.atan2(cy-my,cx-mx)),math.sqrt((cx-mx)^2+(cy-my)^2))
        end)
    end
end)
minimapBtn:SetScript("OnMouseUp",function(self,button)
    if button=="LeftButton" then minimapDragging=false; self:SetScript("OnUpdate",nil) end
end)

-- Hidden state checkboxes (exist for HookScript compatibility)
local buffAlertEnabledCheckbox=CreateFrame("CheckButton","MidnightQoLBuffAlertEnabledCheckbox",mainFrame,"UICheckButtonTemplate")
buffAlertEnabledCheckbox:SetChecked(true); buffAlertEnabledCheckbox:Hide()
local whisperIndicatorEnabledCheckbox=CreateFrame("CheckButton","MidnightQoLWhisperIndicatorEnabledCheckbox",mainFrame,"UICheckButtonTemplate")
whisperIndicatorEnabledCheckbox:SetChecked(true); whisperIndicatorEnabledCheckbox:Hide()
local minimapBtnCheckbox=CreateFrame("CheckButton","MidnightQoLMinimapBtnCheckbox",mainFrame,"UICheckButtonTemplate")
minimapBtnCheckbox:SetChecked(true); minimapBtnCheckbox:Hide()
minimapBtnCheckbox:SetScript("OnClick",function(self)
    local show=self:GetChecked()
    if BuffAlertDB then BuffAlertDB.minimapBtnShown=show end
    if show then minimapBtn:Show() else minimapBtn:Hide() end
end)
local resourceBarsEnabledCheckbox=CreateFrame("CheckButton","MidnightQoLResourceBarsEnabledCheckbox",mainFrame,"UICheckButtonTemplate")
resourceBarsEnabledCheckbox:SetChecked(true); resourceBarsEnabledCheckbox:Hide()
API.buffAlertEnabledCheckbox        = buffAlertEnabledCheckbox
API.whisperIndicatorEnabledCheckbox = whisperIndicatorEnabledCheckbox
API.minimapBtnCheckbox              = minimapBtnCheckbox
API.resourceBarsEnabledCheckbox     = resourceBarsEnabledCheckbox

mainFrame:HookScript("OnHide",function()
    if setupPanel then setupPanel:Hide() end
    if layoutActive then ExitLayoutMode() end
end)
mainFrame:HookScript("OnShow",function()
    if layoutActive then ExitLayoutMode() end
end)

-- ── Profiles tab ──────────────────────────────────────────────────────────────
-- Lets you copy layout/alert settings from any saved character spec into the
-- current spec profile, or into any other spec profile.
local profilesFrame = CreateFrame("Frame","MidnightQoLProfilesFrame",UIParent)
profilesFrame:SetSize(660,500); profilesFrame:Hide()

do
    local LABEL_COLOR   = "|cFFFFD700"
    local WARNING_COLOR = "|cFFFF8800"

    -- ── Header ──
    local hdr = profilesFrame:CreateFontString(nil,"OVERLAY","GameFontNormalLarge")
    hdr:SetPoint("TOPLEFT",0,-4)
    hdr:SetText(LABEL_COLOR.."Profile Copy Tool|r")

    local desc = profilesFrame:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    desc:SetPoint("TOPLEFT",0,-28); desc:SetWidth(640)
    desc:SetJustifyH("LEFT"); desc:SetWordWrap(true)
    desc:SetTextColor(0.8,0.8,0.8,1)
    desc:SetText(
        "Copy alert settings, positions, sounds, and resource bar configuration from any saved "..
        "spec profile into another. Useful for setting up a new character or spec using the same layout as an existing one.\n"..
        WARNING_COLOR.."Warning: copying overwrites the destination — this cannot be undone.|r"
    )

    -- ── Source picker ──
    local srcLabel = profilesFrame:CreateFontString(nil,"OVERLAY","GameFontNormal")
    srcLabel:SetPoint("TOPLEFT",0,-84); srcLabel:SetText("Copy FROM:")

    local srcDropBtn = CreateFrame("Button","CSProfileSrcDrop",profilesFrame,"GameMenuButtonTemplate")
    srcDropBtn:SetSize(280,24); srcDropBtn:SetPoint("TOPLEFT",0,-106)
    srcDropBtn:SetText("(select source profile)")
    srcDropBtn.selectedKey = nil

    -- ── Destination picker ──
    local dstLabel = profilesFrame:CreateFontString(nil,"OVERLAY","GameFontNormal")
    dstLabel:SetPoint("TOPLEFT",0,-142); dstLabel:SetText("Copy INTO:")

    local dstDropBtn = CreateFrame("Button","CSProfileDstDrop",profilesFrame,"GameMenuButtonTemplate")
    dstDropBtn:SetSize(280,24); dstDropBtn:SetPoint("TOPLEFT",0,-164)
    dstDropBtn:SetText("Current spec (active)")
    dstDropBtn.selectedKey = nil   -- nil = current spec

    -- ── What to copy ──
    local optLabel = profilesFrame:CreateFontString(nil,"OVERLAY","GameFontNormal")
    optLabel:SetPoint("TOPLEFT",0,-204); optLabel:SetText("What to copy:")

    local function MakeCheck(name, parent, text, anchorTo, yOff)
        local cb = CreateFrame("CheckButton","CSProfileCopy"..name,parent,"UICheckButtonTemplate")
        cb:SetSize(22,22); cb:SetPoint("TOPLEFT",anchorTo,"BOTTOMLEFT",0,yOff)
        cb:SetChecked(true)
        local lbl = _G["CSProfileCopy"..name.."Text"]; if lbl then lbl:SetText(text) end
        return cb
    end

    local alertsCb    = CreateFrame("CheckButton","CSProfileCopyAlerts",profilesFrame,"UICheckButtonTemplate")
    alertsCb:SetSize(22,22); alertsCb:SetPoint("TOPLEFT",0,-226); alertsCb:SetChecked(true)
    local alertsLbl=_G["CSProfileCopyAlertsText"]; if alertsLbl then alertsLbl:SetText("Buff / Debuff alerts") end

    local positionsCb = CreateFrame("CheckButton","CSProfileCopyPositions",profilesFrame,"UICheckButtonTemplate")
    positionsCb:SetSize(22,22); positionsCb:SetPoint("TOPLEFT",alertsCb,"BOTTOMLEFT",0,-2); positionsCb:SetChecked(true)
    local posLbl=_G["CSProfileCopyPositionsText"]; if posLbl then posLbl:SetText("Alert & overlay positions (X/Y)") end

    local soundsCb = CreateFrame("CheckButton","CSProfileCopySounds",profilesFrame,"UICheckButtonTemplate")
    soundsCb:SetSize(22,22); soundsCb:SetPoint("TOPLEFT",positionsCb,"BOTTOMLEFT",0,-2); soundsCb:SetChecked(true)
    local sndLbl=_G["CSProfileCopySoundsText"]; if sndLbl then sndLbl:SetText("Sounds") end

    local resourcesCb = CreateFrame("CheckButton","CSProfileCopyResources",profilesFrame,"UICheckButtonTemplate")
    resourcesCb:SetSize(22,22); resourcesCb:SetPoint("TOPLEFT",soundsCb,"BOTTOMLEFT",0,-2); resourcesCb:SetChecked(true)
    local resLbl=_G["CSProfileCopyResourcesText"]; if resLbl then resLbl:SetText("Resource bar layout & colors") end

    local whispersCb = CreateFrame("CheckButton","CSProfileCopyWhispers",profilesFrame,"UICheckButtonTemplate")
    whispersCb:SetSize(22,22); whispersCb:SetPoint("TOPLEFT",resourcesCb,"BOTTOMLEFT",0,-2); whispersCb:SetChecked(false)
    local wLbl=_G["CSProfileCopyWhispersText"]; if wLbl then wLbl:SetText("Whisper list (personal — disabled by default)") end

    -- ── Status label ──
    local statusLabel = profilesFrame:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    statusLabel:SetPoint("TOPLEFT",whispersCb,"BOTTOMLEFT",0,-18); statusLabel:SetWidth(500)
    statusLabel:SetJustifyH("LEFT"); statusLabel:SetWordWrap(true)
    statusLabel:SetText("")

    -- ── Copy button ──
    local copyBtn = CreateFrame("Button","CSProfileCopyBtn",profilesFrame,"GameMenuButtonTemplate")
    copyBtn:SetSize(160,26); copyBtn:SetPoint("TOPLEFT",statusLabel,"BOTTOMLEFT",0,-14)
    copyBtn:SetText("Copy Profile →")

    -- ── Dropdown popup (shared for src and dst) ──────────────────────────────
    local dropPopup = CreateFrame("Frame","CSProfileDropPopup",UIParent,"BackdropTemplate")
    dropPopup:SetSize(300,300); dropPopup:SetFrameStrata("TOOLTIP")
    dropPopup:SetBackdrop({bgFile="Interface/DialogFrame/UI-DialogBox-Background",
        edgeFile="Interface/DialogFrame/UI-DialogBox-Border",
        tile=true,tileSize=16,edgeSize=16,insets={left=4,right=4,top=4,bottom=4}})
    dropPopup:SetBackdropColor(0.08,0.08,0.12,0.98); dropPopup:Hide()
    dropPopup.targetBtn = nil

    local dropScroll=CreateFrame("ScrollFrame","CSProfileDropScroll",dropPopup,"UIPanelScrollFrameTemplate")
    dropScroll:SetPoint("TOPLEFT",8,-8); dropScroll:SetPoint("BOTTOMRIGHT",-28,8)
    local dropContent=CreateFrame("Frame","CSProfileDropContent",dropScroll)
    dropContent:SetSize(260,1); dropScroll:SetScrollChild(dropContent)

    local function BuildDropList(forBtn, includeCurrentSpec)
        -- Clear old rows
        for _,c in ipairs({dropContent:GetChildren()}) do c:Hide() end
        local rows = {}
        -- "Current spec" option for dst only
        if includeCurrentSpec then
            table.insert(rows,{key=nil, label="|cFF00FF00Current spec (active)|r"})
        end
        -- All saved profiles
        if BuffAlertDB and BuffAlertDB.specProfiles then
            local sortedKeys = {}
            for k in pairs(BuffAlertDB.specProfiles) do table.insert(sortedKeys,k) end
            table.sort(sortedKeys)
            for _,k in ipairs(sortedKeys) do
                -- Make a friendly display: e.g. "WARRIOR_1" → "Warrior – Arms"
                local class, specID = k:match("^(.-)_(%d+)$")
                local display = k
                if class and specID then
                    local specNum = tonumber(specID)
                    local classNice = class:sub(1,1):upper() .. class:sub(2):lower()
                    display = classNice .. "  |cFFAAAAAA(" .. k .. ")|r"
                end
                table.insert(rows,{key=k, label=display})
            end
        end
        -- Render
        local ROW_H = 24
        for i, row in ipairs(rows) do
            local btn=CreateFrame("Button",nil,dropContent)
            btn:SetSize(255,ROW_H); btn:SetPoint("TOPLEFT",0,-(i-1)*ROW_H)
            local hl=btn:CreateTexture(nil,"HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1,1,1,0.12)
            local lbl=btn:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
            lbl:SetPoint("LEFT",4,0); lbl:SetJustifyH("LEFT"); lbl:SetText(row.label)
            local capRow=row; local capBtn=forBtn
            btn:SetScript("OnClick",function()
                capBtn.selectedKey = capRow.key
                if capRow.key == nil then
                    capBtn:SetText("|cFF00FF00Current spec (active)|r")
                else
                    capBtn:SetText(capRow.key)
                end
                dropPopup:Hide()
            end)
        end
        dropContent:SetHeight(math.max(1,#rows*ROW_H))
    end

    local function OpenDropFor(btn, includeCurrentSpec)
        if dropPopup:IsShown() and dropPopup.targetBtn==btn then dropPopup:Hide(); return end
        dropPopup.targetBtn=btn
        BuildDropList(btn, includeCurrentSpec)
        dropPopup:ClearAllPoints(); dropPopup:SetPoint("TOPLEFT",btn,"BOTTOMLEFT",0,-4)
        dropPopup:Show()
    end

    srcDropBtn:SetScript("OnClick",function(self) OpenDropFor(self,false) end)
    dstDropBtn:SetScript("OnClick",function(self) OpenDropFor(self,true) end)

    -- ── Deep-copy helpers ────────────────────────────────────────────────────
    local function CopyAlertList(srcList)
        local out={}
        for _,aura in ipairs(srcList) do
            local copy={}
            for k,v in pairs(aura) do copy[k]=v end
            table.insert(out,copy)
        end
        return out
    end

    local function StripPositions(list)
        for _,aura in ipairs(list) do
            aura.alertX=nil; aura.alertY=nil
        end
    end

    copyBtn:SetScript("OnClick",function()
        local srcKey = srcDropBtn.selectedKey
        if not srcKey then
            statusLabel:SetText("|cFFFF4444Please select a source profile.|r"); return
        end
        if not BuffAlertDB or not BuffAlertDB.specProfiles then
            statusLabel:SetText("|cFFFF4444No saved profiles found.|r"); return
        end
        local srcProfile = BuffAlertDB.specProfiles[srcKey]
        if not srcProfile then
            statusLabel:SetText("|cFFFF4444Source profile not found.|r"); return
        end

        local dstKey = dstDropBtn.selectedKey   -- nil = current spec
        local dstProfile
        if dstKey then
            dstProfile = GetOrCreateSpecProfile(dstKey)
        else
            dstProfile = GetOrCreateSpecProfile()
            dstKey     = GetSpecProfileKey()
        end
        if not dstProfile then
            statusLabel:SetText("|cFFFF4444Could not create destination profile.|r"); return
        end

        local copied = {}

        if alertsCb:GetChecked() then
            local copyPositions = positionsCb:GetChecked()
            dstProfile.trackedBuffs     = CopyAlertList(srcProfile.trackedBuffs     or {})
            dstProfile.trackedDebuffs   = CopyAlertList(srcProfile.trackedDebuffs   or {})
            dstProfile.trackedExternals = CopyAlertList(srcProfile.trackedExternals or {})
            if not copyPositions then
                StripPositions(dstProfile.trackedBuffs)
                StripPositions(dstProfile.trackedDebuffs)
                StripPositions(dstProfile.trackedExternals)
            end
            table.insert(copied,"alerts")
        end

        if soundsCb:GetChecked() then
            dstProfile.generalWhisperSound    = srcProfile.generalWhisperSound
            dstProfile.generalWhisperSoundIsID = srcProfile.generalWhisperSoundIsID
            dstProfile.petReminderSound       = srcProfile.petReminderSound
            dstProfile.petReminderSoundIsID   = srcProfile.petReminderSoundIsID
            table.insert(copied,"sounds")
        end

        if resourcesCb:GetChecked() then
            dstProfile.resourceBars = DeepCopy(srcProfile.resourceBars)
            table.insert(copied,"resource bars")
        end

        if whispersCb:GetChecked() then
            dstProfile.whisperList     = DeepCopy(srcProfile.whisperList or {})
            dstProfile.whisperEnabled  = srcProfile.whisperEnabled
            table.insert(copied,"whispers")
        end

        -- If we copied into the active spec, reload immediately
        local activeKey = GetSpecProfileKey()
        if dstKey == activeKey then
            LoadSpecProfile()
            if API.RefreshAuraListUI    then API.RefreshAuraListUI() end
            if API.RefreshWhisperListUI then API.RefreshWhisperListUI() end
            C_Timer.After(0.1, function()
                if API.RebuildNameMap then API.RebuildNameMap() end
            end)
        end

        if #copied == 0 then
            statusLabel:SetText("|cFFFF8800Nothing was selected to copy.|r")
        else
            statusLabel:SetText(
                "|cFF00FF00Copied "..table.concat(copied,", ").." from |r"..srcKey..
                " |cFF00FF00into|r "..(dstKey=="active" and "current spec" or dstKey)..
                "|cFF00FF00.|r")
        end
    end)

    -- Register the Profiles tab (added last so it sits on the right)
    API._profilesFrameReady = true
    API._profilesFrame      = profilesFrame
end

-- ── Event handler ─────────────────────────────────────────────────────────────
local coreEvents = CreateFrame("Frame")
coreEvents:RegisterEvent("PLAYER_LOGIN")
coreEvents:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")

coreEvents:SetScript("OnEvent",function(self,event,...)
    if event=="PLAYER_LOGIN" then
        if not BuffAlertDB then
            BuffAlertDB={
                specProfiles={}, minimapAngle=225, minimapRadius=80,
                minimapBtnShown=true, mainFramePos=nil,
                whisperList={}, whisperEnabled=false, ignoreOutgoingWhispers=true,
                generalWhisperSound=nil, generalWhisperSoundIsID=false,
                breakBarR=0.2,breakBarG=0.6,breakBarB=1.0,breakBarX=nil,breakBarY=nil,
                petReminderEnabled=false,petReminderSize=18,
                petReminderR=1,petReminderG=0.4,petReminderB=0,petReminderX=0,petReminderY=80,
                buffDebuffAlertsEnabled=true,whisperIndicatorEnabled=true,resourceBarsEnabled=true,
                pullTimerEnabled=true,breakTimerEnabled=true,cdMismatchSuppressed=false,
            }
        else
            if not BuffAlertDB.specProfiles then BuffAlertDB.specProfiles={} end
        end

        API.playerClass   = select(2,UnitClass("player")) or "UNKNOWN"
        API.currentSpecID = GetSpecializationInfo(GetSpecialization()) or 0

        buffAlertEnabledCheckbox:SetChecked(BuffAlertDB.buffDebuffAlertsEnabled~=false)
        whisperIndicatorEnabledCheckbox:SetChecked(BuffAlertDB.whisperIndicatorEnabled~=false)
        minimapBtnCheckbox:SetChecked(BuffAlertDB.minimapBtnShown~=false)
        resourceBarsEnabledCheckbox:SetChecked(BuffAlertDB.resourceBarsEnabled~=false)
        UpdateMinimapPos(BuffAlertDB.minimapAngle or 225,BuffAlertDB.minimapRadius or 80)
        if BuffAlertDB.minimapBtnShown==false then minimapBtn:Hide() end
        if BuffAlertDB.mainFramePos then
            local p=BuffAlertDB.mainFramePos; mainFrame:ClearAllPoints()
            mainFrame:SetPoint(p.point or "CENTER",UIParent,p.relPoint or "CENTER",p.x or 0,p.y or -50)
        end

        local specIndex=GetSpecialization and GetSpecialization()
        local specName=specIndex and select(2,GetSpecializationInfo(specIndex)) or "Unknown"
        specInfoLabel:SetText("Active Spec: |cFFFFD700"..(API.playerClass or "?").." – "..tostring(specName).."|r")

        LoadSpecProfile()

        -- Register Profiles tab after all sub-addons have loaded
        if API._profilesFrameReady then
            RegisterTab("Profiles", API._profilesFrame, nil, 90, nil, 5)
        end

    elseif event=="PLAYER_SPECIALIZATION_CHANGED" then
        local newSpecID=GetSpecializationInfo(GetSpecialization()) or 0
        if newSpecID~=API.currentSpecID then
            API.currentSpecID=newSpecID
            LoadSpecProfile()
            local si=GetSpecialization and GetSpecialization()
            local sn=si and select(2,GetSpecializationInfo(si)) or "Unknown"
            specInfoLabel:SetText("Active Spec: |cFFFFD700"..(API.playerClass or "?").." – "..tostring(sn).."|r")
            print("|cFF00FF00[MidnightQoL]|r Switched to spec profile: "..GetSpecProfileKey())
        end
    end
end)

-- ── Slash commands ─────────────────────────────────────────────────────────────
SLASH_CUSTOMSOUNDS1="/customsounds"; SLASH_CUSTOMSOUNDS2="/cs"
SlashCmdList["CUSTOMSOUNDS"]=function()
    if mainFrame:IsShown() then mainFrame:Hide()
    else mainFrame:Show(); if tabButtons[1] then ActivateTabByIndex(1) end end
end

SLASH_UNREADWHISPERS1="/clearwhispers"
SlashCmdList["UNREADWHISPERS"]=function()
    if API.ClearUnreadWhispers then API.ClearUnreadWhispers() end
    print("|cFF00FF00[MidnightQoL]|r Unread whispers cleared.")
end

SLASH_CUSTOMSOUNDTEST1="/soundtest"
SlashCmdList["CUSTOMSOUNDTEST"]=function() PlayCustomSound(12743,true) end