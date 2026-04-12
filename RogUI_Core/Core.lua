-- ============================================================
-- RogUI / Core.lua
-- Unified core engine with centralized event handling,
-- module management, main window, tab system, minimap button,
-- layout mode, spec profile save/load, sound engine, and
-- Setup Guide.  Merged from RogUI.lua (v2.x) + Core.lua
-- (v3.0 event system).
-- ============================================================

local API = RogUIAPI
if not API then return end

-- ── DB initialisation + MidnightQoL migration ───────────────────────────────
-- The MidnightQoL bridge addon (if present) loads the old SavedVariables file
-- into globals: BuffAlertDB, CastbarDB, MidnightQoLAccountDB.
-- We copy them into the new RogUI names then nil the old globals so WoW
-- doesn't write them back under the old addon name on logout.
-- On a fresh install with no bridge, the RogUI globals are simply created empty.
local function InitialiseDatabases()
    -- Debug: report the state of every expected global at load time
    print("|cFFFFAA00[RogUI Migration]|r BuffAlertDB = "       .. tostring(BuffAlertDB))
    print("|cFFFFAA00[RogUI Migration]|r CastbarDB = "         .. tostring(CastbarDB))
    print("|cFFFFAA00[RogUI Migration]|r MidnightQoLAccountDB = " .. tostring(MidnightQoLAccountDB))
    print("|cFFFFAA00[RogUI Migration]|r RogUIDB (pre) = "     .. tostring(RogUIDB))
    print("|cFFFFAA00[RogUI Migration]|r RogUICastbarDB (pre) = " .. tostring(RogUICastbarDB))
    print("|cFFFFAA00[RogUI Migration]|r RogUIAccountDB (pre) = " .. tostring(RogUIAccountDB))

    -- Migrate from various old addon database names
    if BuffAlertDB or CastbarDB or MidnightQoLAccountDB then
        print("|cFF00FF00[RogUI]|r Found legacy addon data, migrating...")

        -- BuffAlertDB -> RogUIDB (main settings database)
        if BuffAlertDB then
            print("|cFFFFAA00[RogUI Migration]|r Copying BuffAlertDB into RogUIDB...")
            RogUIDB = RogUIDB or {}
            local count = 0
            for k, v in pairs(BuffAlertDB) do
                RogUIDB[k] = v  -- OVERWRITE all keys from old data
                count = count + 1
            end
            print("|cFFFFAA00[RogUI Migration]|r Copied " .. count .. " keys into RogUIDB from BuffAlertDB")
            -- Only nil the source AFTER confirming destination has data
            if count > 0 or next(RogUIDB) then BuffAlertDB = nil end
        else
            print("|cFFFFAA00[RogUI Migration]|r BuffAlertDB is nil, skipping")
        end

        -- CastbarDB -> RogUICastbarDB
        if CastbarDB then
            print("|cFFFFAA00[RogUI Migration]|r Copying CastbarDB into RogUICastbarDB...")
            RogUICastbarDB = RogUICastbarDB or {}
            local count = 0
            for k, v in pairs(CastbarDB) do
                RogUICastbarDB[k] = v  -- OVERWRITE all keys from old data
                count = count + 1
            end
            print("|cFFFFAA00[RogUI Migration]|r Copied " .. count .. " keys into RogUICastbarDB from CastbarDB")
            if count > 0 or next(RogUICastbarDB) then CastbarDB = nil end
        else
            print("|cFFFFAA00[RogUI Migration]|r CastbarDB is nil, skipping")
        end

        -- MidnightQoLAccountDB -> RogUIAccountDB
        if MidnightQoLAccountDB then
            print("|cFFFFAA00[RogUI Migration]|r Copying MidnightQoLAccountDB into RogUIAccountDB...")
            RogUIAccountDB = RogUIAccountDB or {}
            local count = 0
            for k, v in pairs(MidnightQoLAccountDB) do
                RogUIAccountDB[k] = v  -- OVERWRITE all keys from old data
                count = count + 1
            end
            print("|cFFFFAA00[RogUI Migration]|r Copied " .. count .. " keys into RogUIAccountDB from MidnightQoLAccountDB")
            if count > 0 or next(RogUIAccountDB) then MidnightQoLAccountDB = nil end
        else
            print("|cFFFFAA00[RogUI Migration]|r MidnightQoLAccountDB is nil, skipping")
        end

        print("|cFF00FF00[RogUI]|r Migration complete! Legacy addon data has been transferred.")
    else
        print("|cFFFFAA00[RogUI Migration]|r No legacy addon globals found — fresh install or already migrated.")
    end

    -- Ensure all DBs exist even on a completely fresh install
    RogUIDB        = RogUIDB        or {}
    RogUICastbarDB = RogUICastbarDB or {}
    RogUIAccountDB = RogUIAccountDB or {}

    print("|cFFFFAA00[RogUI Migration]|r RogUIDB (post) = "      .. tostring(RogUIDB))
    print("|cFFFFAA00[RogUI Migration]|r RogUICastbarDB (post) = " .. tostring(RogUICastbarDB))
    print("|cFFFFAA00[RogUI Migration]|r RogUIAccountDB (post) = " .. tostring(RogUIAccountDB))
end

-- InitialiseDatabases must run AFTER WoW has loaded SavedVariables from disk.
-- WoW populates SV globals only once ADDON_LOADED fires for this addon.
-- Calling it at file-load time always sees nil — SV not ready yet.
local _dbInitFrame = CreateFrame("Frame")
_dbInitFrame:RegisterEvent("ADDON_LOADED")
_dbInitFrame:SetScript("OnEvent", function(self, event, addonName)
    if addonName == "RogUI_Core" then
        self:UnregisterEvent("ADDON_LOADED")
        InitialiseDatabases()
        -- Keep _G in sync so any code that looks up by string finds the same tables
        _G.RogUIDB        = RogUIDB
        _G.RogUICastbarDB = RogUICastbarDB
        _G.RogUIAccountDB = RogUIAccountDB
    end
end)


function API.IsModuleEnabled(modName)
    local mod = modulesByName[modName]
    return mod and mod.enabled or false
end

-- ════════════════════════════════════════════════════════════
-- UNIFIED EVENT SYSTEM
-- Single frame with all events registered at top-level load
-- time. API.RegisterEvent only adds to the routing table —
-- Frame:RegisterEvent is never called after load time.
-- ════════════════════════════════════════════════════════════

local eventHandlers  = {} -- { eventName = { { handler, modName }, ... } }
local auraCache      = {} -- cache for UNIT_AURA polling
local activeModules  = {} -- { modName = true } for registered modules
local modulesByName  = {} -- { modName = moduleObject }

-- ── Single event frame, all events pre-registered at load time ────────────────
local eventFrame = CreateFrame("Frame")

local KNOWN_EVENTS = {
    "PLAYER_LOGIN", "PLAYER_LOGOUT", "PLAYER_ENTERING_WORLD",
    "PLAYER_SPECIALIZATION_CHANGED", "ACTIVE_PLAYER_SPECIALIZATION_CHANGED",
    "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED",
    "UNIT_HEALTH", "UNIT_POWER_UPDATE", "UNIT_MAXPOWER",
    "UNIT_PET", "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP",
    "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_FAILED_QUIET",
    "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_DELAYED",
    "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_STOP", "UNIT_SPELLCAST_CHANNEL_UPDATE",
    "UNIT_SPELLCAST_EMPOWER_START", "UNIT_SPELLCAST_EMPOWER_STOP",
    "GROUP_ROSTER_UPDATE", "RAID_BOSS_EMOTE", "ENCOUNTER_START", "ENCOUNTER_END", "ENCOUNTER_WARNING",
    "READY_CHECK", "ZONE_CHANGED_NEW_AREA",
    "CHALLENGE_MODE_START", "CHALLENGE_MODE_RESET", "CHALLENGE_MODE_COMPLETED",
    "CHALLENGE_MODE_MAPS_UPDATE", "CHALLENGE_MODE_DEATH_COUNT_UPDATED",
    "SCENARIO_CRITERIA_UPDATE",
    "CHAT_MSG_WHISPER", "CHAT_MSG_WHISPER_INFORM",
    "CHAT_MSG_BN_WHISPER", "CHAT_MSG_BN_WHISPER_INFORM",
    "CHAT_MSG_ADDON",
    "BAG_UPDATE_DELAYED", "ITEM_LOCK_CHANGED",
    "PLAYER_EQUIPMENT_CHANGED", "PLAYER_FLAGS_CHANGED",
    "ACTIONBAR_SLOT_CHANGED", "UPDATE_BINDINGS",
    "ADDON_LOADED", "TRAIT_CONFIG_UPDATED",
    "UNIT_AURA",
}

for _, ev in ipairs(KNOWN_EVENTS) do
    eventFrame:RegisterEvent(ev)
end

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if eventHandlers[event] then
        for _, handlerInfo in ipairs(eventHandlers[event]) do
            local handler, modName = handlerInfo[1], handlerInfo[2]
            if activeModules[modName] and handler then
                pcall(handler, ...)
            end
        end
    end
end)

-- Bridge EditMode callbacks into our unified event system
if EventRegistry then
    EventRegistry:RegisterCallback("EditMode.Enter", function()
        if eventHandlers["EDIT_MODE_ENTER"] then
            for _, handlerInfo in ipairs(eventHandlers["EDIT_MODE_ENTER"]) do
                pcall(handlerInfo[1])
            end
        end
    end)

    EventRegistry:RegisterCallback("EditMode.Exit", function()
        if eventHandlers["EDIT_MODE_EXIT"] then
            for _, handlerInfo in ipairs(eventHandlers["EDIT_MODE_EXIT"]) do
                pcall(handlerInfo[1])
            end
        end
    end)
end

-- ── UNIT_AURA polling ticker ──────────────────────────────────────────────────
C_Timer.NewTicker(0.15, function()
    if UnitExists("player") then
        local auraCount = 0
        while C_UnitAuras.GetAuraDataByIndex("player", auraCount + 1, "HELPFUL") do
            auraCount = auraCount + 1
        end
        if (auraCache.player or 0) ~= auraCount then
            auraCache.player = auraCount
            if eventHandlers["UNIT_AURA"] then
                for _, handlerInfo in ipairs(eventHandlers["UNIT_AURA"]) do
                    local handler, modName = handlerInfo[1], handlerInfo[2]
                    if activeModules[modName] and handler then
                        pcall(handler, "player")
                    end
                end
            end
        end
    end

    for i = 1, 40 do
        local units = {}
        if i <= 4 then table.insert(units, "party" .. i) end
        table.insert(units, "raid" .. i)
        if i <= 4 then table.insert(units, "boss" .. i) end

        for _, unit in ipairs(units) do
            if UnitExists(unit) then
                local auraCount = 0
                while C_UnitAuras.GetAuraDataByIndex(unit, auraCount + 1, "HELPFUL") do
                    auraCount = auraCount + 1
                end
                if (auraCache[unit] or 0) ~= auraCount then
                    auraCache[unit] = auraCount
                    if eventHandlers["UNIT_AURA"] then
                        for _, handlerInfo in ipairs(eventHandlers["UNIT_AURA"]) do
                            local handler, modName = handlerInfo[1], handlerInfo[2]
                            if activeModules[modName] and handler then
                                pcall(handler, unit)
                            end
                        end
                    end
                end
            end
        end
    end
end)

-- ── Event registration API ────────────────────────────────────────────────────
local function RegisterEventHandler(eventName, handler, modName)
    if not eventHandlers[eventName] then
        eventHandlers[eventName] = {}
    end
    table.insert(eventHandlers[eventName], {handler, modName})
    if modName and not activeModules[modName] then
        activeModules[modName] = true
    end
end

local function UnregisterEventHandler(eventName, modName)
    if not eventHandlers[eventName] then return end
    for i = #eventHandlers[eventName], 1, -1 do
        if eventHandlers[eventName][i][2] == modName then
            table.remove(eventHandlers[eventName], i)
        end
    end
    if #eventHandlers[eventName] == 0 then
        eventHandlers[eventName] = nil
    end
end

function API.RegisterEvent(modName, eventName, handler)
    RegisterEventHandler(eventName, handler, modName)
end

function API.UnregisterEvent(modName, eventName)
    UnregisterEventHandler(eventName, modName)
end

function API.UnregisterAllEvents(modName)
    for eventName in pairs(eventHandlers) do
        UnregisterEventHandler(eventName, modName)
    end
end

-- ════════════════════════════════════════════════════════════
-- SHARED UTILITY FUNCTIONS
-- ════════════════════════════════════════════════════════════

local _errorLog = {}  -- shared between Debug() and the error handler

local function Debug(msg)
    if API.DEBUG then
        local line = date("%H:%M:%S") .. " [DEBUG] " .. tostring(msg)
        print("|cFF00FF00[RogUI DEBUG]|r " .. tostring(msg))
        if _errorLog then
            _errorLog[#_errorLog + 1] = line
        end
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

-- ════════════════════════════════════════════════════════════
-- MODULE SYSTEM
-- ════════════════════════════════════════════════════════════

local modules = {}  -- ordered list of all registered module tables

function API.RegisterModule(moduleName, modTable)
    if modulesByName[moduleName] then
        print("|cFFFF0000[RogUI] Module '" .. moduleName .. "' already registered!|r")
        return
    end
    modules[#modules + 1]     = modTable
    modulesByName[moduleName] = modTable
    modTable.name    = moduleName
    modTable.enabled = true
    return modTable
end

function API.GetModule(moduleName)
    return modulesByName[moduleName]
end

function API.GetModuleDB(modName, defaults)
    if not defaults then return {} end
    local dbName = "RogUI" .. modName .. "DB"
    if not _G[dbName] then _G[dbName] = {} end
    local db = _G[dbName]
    for k, v in pairs(defaults) do
        if db[k] == nil then db[k] = v end
    end
    return db
end

function API.GetEquippedIlvl(invSlotID)
    local itemLink = GetInventoryItemLink("player", invSlotID)
    if not itemLink then return 0 end
    local itemLevel = select(4, GetItemInfo(itemLink))
    return itemLevel or 0
end

function API.GetWatchedFaction()
    local watchedFactionIndex = GetWatchedFactionInfo()
    if not watchedFactionIndex then return nil end
    local name, standing, barMin, barMax, barValue = GetFactionInfoByID(watchedFactionIndex)
    return { name=name, standing=standing, barMin=barMin, barMax=barMax, barValue=barValue }
end

local hookedFrames = {}
function API.HookFrame(frame, name)
    if hookedFrames[frame] then return end
    hookedFrames[frame] = true
    frame:HookScript("OnEnter", function(self)
        if self.tooltipTitle then
            GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
            GameTooltip:AddLine(self.tooltipTitle, 1, 1, 1)
            if self.tooltipText then
                GameTooltip:AddLine(self.tooltipText, 0.7, 0.7, 0.7, true)
            end
            GameTooltip:Show()
        end
    end)
    frame:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

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
        local soundPath = "Interface/AddOns/RogUI_Core/Sounds/" .. filename .. ".ogg"
        table.insert(sounds, {name = displayName, path = soundPath, isID = false})
    end
    return sounds
end

local customImageFiles = (type(ImagesList) == "table") and ImagesList or {}

local function GetAvailableImages()
    local images = {
        {name = "Spell Icon (auto)",      path = "spell_icon",         isSpellIcon = true},
        {name = "── Common Icons ──",     path = nil,                  isSeparator = true},
        {name = "Warning Diamond",        path = "Interface\\DialogFrame\\UI-Dialog-Icon-AlertOther"},
        {name = "Skull",                  path = "Interface\\TargetingFrame\\UI-TargetingFrame-Skull"},
        {name = "Raid Target - Star",     path = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_1"},
        {name = "Raid Target - Circle",   path = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_2"},
        {name = "Raid Target - Diamond",  path = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_3"},
        {name = "Raid Target - Triangle", path = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_4"},
        {name = "Raid Target - Moon",     path = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_5"},
        {name = "Raid Target - Square",   path = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_6"},
        {name = "Raid Target - Cross",    path = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_7"},
        {name = "Raid Target - Skull",    path = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8"},
        {name = "Interrupt (red X)",      path = "Interface\\Icons\\Ability_Kick"},
        {name = "Defensive CD",           path = "Interface\\Icons\\Spell_Shadow_NetherProtection"},
        {name = "Heal",                   path = "Interface\\Icons\\Spell_Holy_FlashHeal"},
        {name = "Lightning",              path = "Interface\\Icons\\Spell_Nature_Lightning"},
        {name = "Fire",                   path = "Interface\\Icons\\Spell_Fire_Fireball02"},
        {name = "Frost",                  path = "Interface\\Icons\\Spell_Frost_FrostBolt02"},
        {name = "Shadow",                 path = "Interface\\Icons\\Spell_Shadow_ShadowBolt"},
        {name = "Arcane",                 path = "Interface\\Icons\\Spell_Holy_MagicalSentry"},
        {name = "Nature",                 path = "Interface\\Icons\\Spell_Nature_Starfall"},
        {name = "Bloodlust / Heroism",    path = "Interface\\Icons\\Spell_Nature_Bloodlust"},
        {name = "Power Infusion",         path = "Interface\\Icons\\Spell_Holy_PowerInfusion"},
        {name = "── Addon Images ──",     path = nil,                  isSeparator = true},
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
            path = "Interface/AddOns/RogUI_Core/Images/" .. path
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
    if not RogUIDB then return nil end
    if not RogUIDB.specProfiles then RogUIDB.specProfiles = {} end
    local k = key or GetSpecProfileKey()
    if not RogUIDB.specProfiles[k] then
        RogUIDB.specProfiles[k] = {}
    end
    return RogUIDB.specProfiles[k]
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
API.RegisterProfileCallbacks = RegisterProfileCallbacks
API.RegisterPreSaveCallback  = function(fn)
    table.insert(API._preSaveCallbacks, fn)
end

function API.TriggerProfileSave(profile)
    for _, cb in ipairs(API._saveCallbacks) do pcall(cb, profile) end
end
function API.TriggerProfileLoad(profile)
    for _, cb in ipairs(API._loadCallbacks) do pcall(cb, profile) end
end

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
local mainFrame = CreateFrame("Frame", "RogUIMainFrame", UIParent, "BackdropTemplate")
local FRAME_INSET = 60
local function UpdateMainFrameSize()
    mainFrame:ClearAllPoints()
    mainFrame:SetPoint("TOPLEFT",     UIParent, "TOPLEFT",     FRAME_INSET,  -FRAME_INSET)
    mainFrame:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -FRAME_INSET,  FRAME_INSET)
end
UpdateMainFrameSize()
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
    if RogUIDB then
        local point, _, relPoint, x, y = self:GetPoint()
        RogUIDB.mainFramePos = {point=point, relPoint=relPoint, x=x, y=y}
    end
end)
mainFrame:Hide()

local title = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
title:SetPoint("TOPLEFT", 20, -20); title:SetText("Midnight QoL Configuration")

local closeBtn = CreateFrame("Button", nil, mainFrame, "UIPanelCloseButton")
closeBtn:SetPoint("TOPRIGHT", mainFrame, "TOPRIGHT", -5, -5)

local scrollFrame = CreateFrame("ScrollFrame", "RogUIScrollFrame", mainFrame, "UIPanelScrollFrameTemplate")
scrollFrame:SetPoint("TOPLEFT", 20, -90)
scrollFrame:SetPoint("BOTTOMRIGHT", -35, 50)

-- ── Tab system ─────────────────────────────────────────────────────────────────
local tabRegistry     = {}
local tabButtons      = {}
local currentTabIndex = 1

local function ActivateTabByIndex(i)
    if tabRegistry[currentTabIndex] and tabRegistry[currentTabIndex].onDeactivate then
        tabRegistry[currentTabIndex].onDeactivate()
    end
    for _, entry in ipairs(tabRegistry) do
        if entry.frame then entry.frame:Hide() end
    end
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
    entry.frame:ClearAllPoints()
    entry.frame:SetPoint("TOPLEFT", 0, 0)
    local sw = scrollFrame:GetWidth()
    if sw and sw > 100 then
        local _, fh = entry.frame:GetSize()
        entry.frame:SetSize(sw, fh or 2000)
    end
    scrollFrame:SetScrollChild(entry.frame)
    entry.frame:Show()
    if entry.onActivate then entry.onActivate() end
    if API.UpdateAddButtons then API.UpdateAddButtons(i) end
end

local function RebuildTabBar()
    if tabRegistry[currentTabIndex] and tabRegistry[currentTabIndex].onDeactivate then
        tabRegistry[currentTabIndex].onDeactivate()
    end
    for _, btn in ipairs(tabButtons) do btn:Hide(); btn:SetParent(nil) end
    tabButtons = {}
    local TAB_GAP = 8
    local nextX   = 20
    for i, entry in ipairs(tabRegistry) do
        local w   = entry.width or 80
        local btn = CreateFrame("Button", "RogUITab" .. i, mainFrame, "GameMenuButtonTemplate")
        btn:SetSize(w, 25)
        btn:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", nextX, -50)
        btn:SetText(entry.label)
        btn.tabIndex = i
        btn:SetScript("OnClick", function(self)
            ActivateTabByIndex(self.tabIndex)
        end)
        tabButtons[i] = btn
        if entry.hidden then btn:Hide() else nextX = nextX + w + TAB_GAP end
    end
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
        hidden       = (RogUIDB and RogUIDB.tabsEnabled and RogUIDB.tabsEnabled[label] == false) or false,
    })
    table.sort(tabRegistry, function(a, b) return (a.priority or 50) < (b.priority or 50) end)
    RebuildTabBar()
    if #tabRegistry == 1 then
        ActivateTabByIndex(1)
    end
end

API.RegisterTab        = RegisterTab
API.ActivateTabByIndex = ActivateTabByIndex
API.GetCurrentTabIndex = function() return currentTabIndex end
API.GetTabRegistry     = function() return tabRegistry end

function API.SetTabEnabled(label, enabled)
    for i, entry in ipairs(tabRegistry) do
        if entry.label == label then
            entry.hidden = not enabled
            if tabButtons[i] then
                if enabled then tabButtons[i]:Show() else tabButtons[i]:Hide() end
            end
            if not enabled and currentTabIndex == i then
                ActivateTabByIndex(1)
            end
            if RogUIDB then
                RogUIDB.tabsEnabled = RogUIDB.tabsEnabled or {}
                RogUIDB.tabsEnabled[label] = enabled
            end
            return
        end
    end
end

function API.IsTabEnabled(label)
    if RogUIDB and RogUIDB.tabsEnabled and RogUIDB.tabsEnabled[label] ~= nil then
        return RogUIDB.tabsEnabled[label]
    end
    return true
end

-- ── Bottom bar ─────────────────────────────────────────────────────────────────
local saveBtn = CreateFrame("Button", "RogUISaveBtn", mainFrame, "GameMenuButtonTemplate")
saveBtn:SetSize(100, 25)
saveBtn:SetPoint("BOTTOMRIGHT", mainFrame, "BOTTOMRIGHT", -20, 15)
saveBtn:SetText("Save")
saveBtn:SetScript("OnClick", function()
    for _, cb in ipairs(API._preSaveCallbacks) do pcall(cb) end
    SaveSpecProfile()
    mainFrame:Hide()
end)

local setupLinkBtn = CreateFrame("Button", "RogUISetupLinkBtn", mainFrame, "GameMenuButtonTemplate")
setupLinkBtn:SetSize(120, 25)
setupLinkBtn:SetPoint("BOTTOMLEFT", mainFrame, "BOTTOMLEFT", 20, 15)
setupLinkBtn:SetText("Setup Guide")

local layoutModeBtn = CreateFrame("Button", "RogUILayoutModeBtn", mainFrame, "GameMenuButtonTemplate")
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
local setupPanel = CreateFrame("Frame", "RogUISetupPanel", UIParent, "BackdropTemplate")
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
    local scr = CreateFrame("ScrollFrame","RogUISetupScroll",setupPanel,"UIPanelScrollFrameTemplate")
    scr:SetPoint("TOPLEFT",12,-36); scr:SetPoint("BOTTOMRIGHT",-30,12)
    local con = CreateFrame("Frame","RogUISetupContent",scr)
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
local layoutActive   = false
local layoutWasOpen  = false
local nativeEditMode = false

-- ── Grid snapping ──────────────────────────────────────────────────────────────
local gridSnapEnabled = true
local gridSize        = 10   -- pixels; snaps ox/oy to multiples of this

local function SnapToGrid(v)
    if not gridSnapEnabled or gridSize < 1 then return math.floor(v + 0.5) end
    return math.floor(v / gridSize + 0.5) * gridSize
end

-- Compute snapped centre-relative offset from a handle frame.
-- GetLeft()/GetBottom() return screen pixels; divide by effective scale
-- to get virtual (UIParent-space) coordinates.
local function HandleOffset(h)
    local sc = UIParent:GetEffectiveScale()
    local cx = UIParent:GetWidth()  / 2
    local cy = UIParent:GetHeight() / 2
    local rawOx = (h:GetLeft()   * (h:GetEffectiveScale() / sc)) + h:GetWidth()  / 2 - cx
    local rawOy = (h:GetBottom() * (h:GetEffectiveScale() / sc)) + h:GetHeight() / 2 - cy
    return rawOx, rawOy
end

-- Visual grid overlay — must be HIGH so it sits above the MEDIUM dimmer
local gridOverlay = CreateFrame("Frame", "RogUILayoutGrid", UIParent)
gridOverlay:SetAllPoints(UIParent); gridOverlay:SetFrameStrata("HIGH")
gridOverlay:SetFrameLevel(1)   -- below handles (FULLSCREEN_DIALOG) but above dimmer (MEDIUM)
gridOverlay:EnableMouse(false); gridOverlay:Hide()

local gridLines = {}  -- pool of textures reused on rebuild

local function BuildGridLines()
    -- Hide all existing lines first
    for _, t in ipairs(gridLines) do t:Hide() end

    if not gridSnapEnabled or gridSize < 4 then return end

    -- UIParent virtual dimensions (what SetPoint coordinates use)
    local sw = UIParent:GetWidth()
    local sh = UIParent:GetHeight()
    local cx = sw / 2
    local cy = sh / 2

    local lineIdx = 0
    local function GetLine()
        lineIdx = lineIdx + 1
        if not gridLines[lineIdx] then
            gridLines[lineIdx] = gridOverlay:CreateTexture(nil, "ARTWORK")
        end
        local t = gridLines[lineIdx]
        t:Show(); return t
    end

    -- Vertical lines: walk from left edge in gridSize steps
    -- We want lines at every multiple of gridSize in virtual coords,
    -- which means lines at x = k*gridSize for k = 0,1,2,...
    -- Offset from TOPLEFT of the overlay.
    local x = 0
    while x <= sw do
        local t = GetLine()
        t:SetWidth(1); t:SetHeight(sh)
        t:SetPoint("TOPLEFT", gridOverlay, "TOPLEFT", x, 0)
        local isCentre = math.abs(x - cx) < 1
        t:SetColorTexture(0.5, 0.7, 1, isCentre and 0.45 or 0.15)
        x = x + gridSize
    end

    -- Horizontal lines: walk from bottom edge in gridSize steps
    local y = 0
    while y <= sh do
        local t = GetLine()
        t:SetWidth(sw); t:SetHeight(1)
        t:SetPoint("BOTTOMLEFT", gridOverlay, "BOTTOMLEFT", 0, y)
        local isCentre = math.abs(y - cy) < 1
        t:SetColorTexture(0.5, 0.7, 1, isCentre and 0.45 or 0.15)
        y = y + gridSize
    end
end

local layoutDimmer = CreateFrame("Frame", "RogUILayoutDimmer", UIParent)
layoutDimmer:SetAllPoints(UIParent); layoutDimmer:SetFrameStrata("MEDIUM")
layoutDimmer:EnableMouse(false); layoutDimmer:Hide()
local dimTex = layoutDimmer:CreateTexture(nil,"BACKGROUND")
dimTex:SetAllPoints(); dimTex:SetColorTexture(0,0,0,0.45)

local layoutDoneBtn = CreateFrame("Button","RogUILayoutDoneBtn",UIParent,"GameMenuButtonTemplate")
layoutDoneBtn:SetSize(120,30); layoutDoneBtn:SetPoint("TOP",UIParent,"TOP",0,-10)
layoutDoneBtn:SetFrameStrata("FULLSCREEN_DIALOG"); layoutDoneBtn:SetText("[OK]  Done Editing"); layoutDoneBtn:Hide()

-- ── Grid snap controls (shown only in layout mode) ─────────────────────────────
local snapBar = CreateFrame("Frame","RogUISnapBar",UIParent,"BackdropTemplate")
snapBar:SetSize(320, 32); snapBar:SetPoint("TOP",UIParent,"TOP",0,-48)
snapBar:SetFrameStrata("FULLSCREEN_DIALOG")
snapBar:SetBackdrop({ bgFile="Interface\\Buttons\\WHITE8x8",
                      edgeFile="Interface\\Buttons\\WHITE8x8", edgeSize=1 })
snapBar:SetBackdropColor(0.04, 0.06, 0.12, 0.90)
snapBar:SetBackdropBorderColor(0.35, 0.55, 0.8, 1)
snapBar:Hide()

local snapToggle = CreateFrame("Button",nil,snapBar,"GameMenuButtonTemplate")
snapToggle:SetSize(100,22); snapToggle:SetPoint("LEFT",snapBar,"LEFT",6,0)
local function RefreshSnapToggle()
    snapToggle:SetText(gridSnapEnabled and "|cFF88FF88Snap: ON|r" or "|cFFFF8888Snap: OFF|r")
    if gridSnapEnabled then
        gridOverlay:Show(); BuildGridLines()
    else
        gridOverlay:Hide()
    end
end
snapToggle:SetScript("OnClick", function()
    gridSnapEnabled = not gridSnapEnabled
    RefreshSnapToggle()
end)

local snapLbl = snapBar:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
snapLbl:SetPoint("LEFT",snapToggle,"RIGHT",8,0); snapLbl:SetText("Grid:")
snapLbl:SetTextColor(0.7,0.85,1,1)

-- Decrease grid size
local snapDec = CreateFrame("Button",nil,snapBar,"GameMenuButtonTemplate")
snapDec:SetSize(22,22); snapDec:SetPoint("LEFT",snapLbl,"RIGHT",4,0); snapDec:SetText("-")
snapDec:SetScript("OnClick", function()
    local steps = {2,4,5,8,10,16,20,25,32,50}
    for i = #steps, 1, -1 do
        if steps[i] < gridSize then gridSize = steps[i]; break end
    end
    if gridSnapEnabled then BuildGridLines() end
    snapSizeDisplay:SetText(tostring(gridSize).."px")
end)

local snapSizeDisplay = snapBar:CreateFontString(nil,"OVERLAY","GameFontNormal")
snapSizeDisplay:SetPoint("LEFT",snapDec,"RIGHT",4,0); snapSizeDisplay:SetWidth(36)
snapSizeDisplay:SetJustifyH("CENTER"); snapSizeDisplay:SetTextColor(1,1,0.6,1)
snapSizeDisplay:SetText(tostring(gridSize).."px")

-- Increase grid size
local snapInc = CreateFrame("Button",nil,snapBar,"GameMenuButtonTemplate")
snapInc:SetSize(22,22); snapInc:SetPoint("LEFT",snapSizeDisplay,"RIGHT",4,0); snapInc:SetText("+")
snapInc:SetScript("OnClick", function()
    local steps = {2,4,5,8,10,16,20,25,32,50}
    for i = 1, #steps do
        if steps[i] > gridSize then gridSize = steps[i]; break end
    end
    if gridSnapEnabled then BuildGridLines() end
    snapSizeDisplay:SetText(tostring(gridSize).."px")
end)

local snapHint = snapBar:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
snapHint:SetPoint("LEFT",snapInc,"RIGHT",10,0)
snapHint:SetTextColor(0.5,0.55,0.6,1); snapHint:SetText("Hold Shift to bypass snap")

local function GetOrCreateHandle(i)
    if layoutHandles[i] then return layoutHandles[i] end
    local h = CreateFrame("Frame","RogUILayoutHandle"..i,UIParent,"BackdropTemplate")
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
        local rawOx, rawOy = HandleOffset(self)
        -- Apply grid snap (bypass with Shift held)
        local shiftHeld = IsShiftKeyDown and IsShiftKeyDown()
        local ox = shiftHeld and math.floor(rawOx+0.5) or SnapToGrid(rawOx)
        local oy = shiftHeld and math.floor(rawOy+0.5) or SnapToGrid(rawOy)
        -- Re-anchor handle to the snapped position
        self:ClearAllPoints(); self:SetPoint("CENTER",UIParent,"CENTER",ox,oy)
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

    local resizeGrip = CreateFrame("Button",nil,h)
    resizeGrip:SetSize(14,14); resizeGrip:SetPoint("BOTTOMRIGHT",h,"BOTTOMRIGHT",0,0)
    resizeGrip:SetFrameLevel(h:GetFrameLevel()+2)
    local resizeTex = resizeGrip:CreateTexture(nil,"OVERLAY")
    resizeTex:SetAllPoints(resizeGrip); resizeTex:SetColorTexture(0.8,0.9,1,0.7)
    resizeGrip:SetScript("OnEnter",function(self)
        GameTooltip:SetOwner(self,"ANCHOR_TOPLEFT")
        GameTooltip:AddLine("Drag to resize",0.8,0.9,1); GameTooltip:Show()
    end)
    resizeGrip:SetScript("OnLeave",function() GameTooltip:Hide() end)
    resizeGrip:SetScript("OnMouseDown",function(self)
        resizeGrip._resizing=true
        resizeGrip._startX, resizeGrip._startY = GetCursorPosition()
        local sc = UIParent:GetEffectiveScale()
        resizeGrip._startX = resizeGrip._startX / sc
        resizeGrip._startY = resizeGrip._startY / sc
        local lf = h.liveFrameRef
        resizeGrip._origW = lf and lf:GetWidth()  or nil
        resizeGrip._origH = lf and lf:GetHeight() or nil
    end)
    resizeGrip:SetScript("OnMouseUp",function(self)
        if not resizeGrip._resizing then return end
        resizeGrip._resizing=false
        local lf = h.liveFrameRef
        if lf and h.resizeCallback then
            h.resizeCallback(lf:GetWidth(), lf:GetHeight())
        end
    end)
    resizeGrip:SetScript("OnUpdate",function(self)
        if not resizeGrip._resizing then return end
        local sc = UIParent:GetEffectiveScale()
        local cx, cy = GetCursorPosition()
        cx, cy = cx/sc, cy/sc
        local dx = cx - resizeGrip._startX
        local dy = resizeGrip._startY - cy
        local newW = math.max(20, (resizeGrip._origW or 200) + dx)
        local newH = math.max(8,  (resizeGrip._origH or 20)  + dy)
        local lf = h.liveFrameRef
        if lf then lf:SetSize(newW, newH) end
        h.posLbl:SetText(string.format("%.0fx%.0f", newW, newH))
    end)
    h.resizeGrip = resizeGrip
    h:SetScript("OnUpdate",function(self)
        if not self.isDragging then return end
        local rawOx, rawOy = HandleOffset(self)
        local shiftHeld = IsShiftKeyDown and IsShiftKeyDown()
        local ox = shiftHeld and rawOx or SnapToGrid(rawOx)
        local oy = shiftHeld and rawOy or SnapToGrid(rawOy)
        self.posLbl:SetText("x="..math.floor(ox+0.5).."  y="..math.floor(oy+0.5))
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
        h.previewOverlay=nil; h.liveIconTarget=nil; h.liveFrameRef=nil; h.resizeCallback=nil
        if h.resizeGrip then h.resizeGrip._resizing=false end
        h:Hide() end
end

local function EnterLayoutMode(fromNative)
    if layoutActive then return end
    layoutActive = true
    nativeEditMode = fromNative and true or false
    layoutWasOpen = mainFrame:IsShown()
    if layoutWasOpen then mainFrame:Hide() end
    
    -- Only show our UI chrome if not driven by WoW native Edit Mode
    if not nativeEditMode then
        layoutDimmer:Show()
        layoutDoneBtn:Show()
    end
    
    snapBar:Show(); snapSizeDisplay:SetText(tostring(gridSize).."px"); RefreshSnapToggle()
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
                if hd.resizeCallback then h.resizeCallback=hd.resizeCallback end
                if hd.previewFunc    then
                    local ov=hd.previewFunc()
                    if ov then
                        h.previewOverlay=ov
                        if not h.liveFrameRef then h.liveFrameRef=ov end
                    end
                end
            end
        end
    end
    
    -- Only update done button text if using our own UI
    if not nativeEditMode then
        layoutDoneBtn:SetText(handleIdx<=0 and "[OK]  Done (add alerts with textures to position)" or "[OK]  Done Editing")
    end
end

local function ExitLayoutMode()
    -- Always force exit, even if layoutActive wasn't set
    layoutActive = false
    nativeEditMode = false
    layoutDimmer:Hide(); layoutDoneBtn:Hide(); HideAllHandles()
    snapBar:Hide(); gridOverlay:Hide()
    if API.HideAlertPreviews then API.HideAlertPreviews() end
    SaveSpecProfile()
    if layoutWasOpen then mainFrame:Show(); layoutWasOpen = false end
end

layoutDoneBtn:SetScript("OnClick", function(self)
    ExitLayoutMode()
    -- Double-check we exited
    C_Timer.After(0.1, function()
        if layoutDimmer:IsShown() then
            layoutDimmer:Hide()
            layoutDoneBtn:Hide()
            HideAllHandles()
        end
    end)
end)
layoutModeBtn:SetScript("OnClick",function() EnterLayoutMode(false) end)

-- Register for WoW native Edit Mode events
API.RegisterEvent("Core", "EDIT_MODE_ENTER", function()
    EnterLayoutMode(true)
end)

API.RegisterEvent("Core", "EDIT_MODE_EXIT", function()
    ExitLayoutMode()
end)

API.EnterLayoutMode=EnterLayoutMode; API.ExitLayoutMode=ExitLayoutMode
API.IsLayoutMode=function() return layoutActive end

local function RegisterLayoutHandles(providerFunc)
    table.insert(API._layoutProviders,providerFunc)
end
API.RegisterLayoutHandles=RegisterLayoutHandles

-- ── Minimap button ─────────────────────────────────────────────────────────────
local minimapBtn=CreateFrame("Button","RogUIMinimapBtn",Minimap)
minimapBtn:SetSize(32,32); minimapBtn:SetFrameStrata("MEDIUM"); minimapBtn:SetFrameLevel(8)
minimapBtn:SetClampedToScreen(true)
do
    local bg=minimapBtn:CreateTexture(nil,"BACKGROUND"); bg:SetSize(32,32)
    bg:SetPoint("CENTER",minimapBtn,"CENTER",0,0); bg:SetColorTexture(0,0,0,0.55)
    local ic=minimapBtn:CreateTexture(nil,"ARTWORK"); ic:SetSize(26,26)
    ic:SetPoint("CENTER",minimapBtn,"CENTER",0,0)
    ic:SetTexture("Interface/AddOns/RogUI_Core/Images/minimap_icon")
    ic:SetTexCoord(0.08,0.92,0.08,0.92)
    local hl=minimapBtn:CreateTexture(nil,"HIGHLIGHT"); hl:SetAllPoints(minimapBtn); hl:SetColorTexture(1,1,1,0.15)
end

local minimapDragging=false
local function UpdateMinimapPos(angle,radius)
    radius=math.max(60,math.min(110,radius or 80)); angle=angle or 225
    if RogUIDB then RogUIDB.minimapAngle=angle; RogUIDB.minimapRadius=radius end
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
        minimapDragging=false
        local startX, startY = GetCursorPosition()
        self:SetScript("OnUpdate",function()
            local cx,cy=GetCursorPosition()
            local scale=UIParent:GetEffectiveScale()
            if not minimapDragging then
                local dist = math.sqrt((cx-startX)^2+(cy-startY)^2)
                if dist < 4 then return end
                minimapDragging = true
            end
            local mx,my=Minimap:GetCenter()
            cx,cy=cx/scale,cy/scale
            UpdateMinimapPos(math.deg(math.atan2(cy-my,cx-mx)),math.sqrt((cx-mx)^2+(cy-my)^2))
        end)
    end
end)
minimapBtn:SetScript("OnMouseUp",function(self,button)
    if button=="LeftButton" then minimapDragging=false; self:SetScript("OnUpdate",nil) end
end)

local buffAlertEnabledCheckbox=CreateFrame("CheckButton","RogUIBuffAlertEnabledCheckbox",mainFrame,"UICheckButtonTemplate")
buffAlertEnabledCheckbox:SetChecked(false); buffAlertEnabledCheckbox:Hide()
local whisperIndicatorEnabledCheckbox=CreateFrame("CheckButton","RogUIWhisperIndicatorEnabledCheckbox",mainFrame,"UICheckButtonTemplate")
whisperIndicatorEnabledCheckbox:SetChecked(false); whisperIndicatorEnabledCheckbox:Hide()
local minimapBtnCheckbox=CreateFrame("CheckButton","RogUIMinimapBtnCheckbox",mainFrame,"UICheckButtonTemplate")
minimapBtnCheckbox:SetChecked(true); minimapBtnCheckbox:Hide()
minimapBtnCheckbox:SetScript("OnClick",function(self)
    local show=self:GetChecked()
    if RogUIDB then RogUIDB.minimapBtnShown=show end
    if show then minimapBtn:Show() else minimapBtn:Hide() end
end)
local resourceBarsEnabledCheckbox=CreateFrame("CheckButton","RogUIResourceBarsEnabledCheckbox",mainFrame,"UICheckButtonTemplate")
resourceBarsEnabledCheckbox:SetChecked(false); resourceBarsEnabledCheckbox:Hide()
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
local profilesFrame = CreateFrame("Frame","RogUIProfilesFrame",UIParent)
profilesFrame:SetSize(880,500); profilesFrame:Hide()

do
    local LABEL_COLOR   = "|cFFFFD700"
    local WARNING_COLOR = "|cFFFF8800"

    local hdr = profilesFrame:CreateFontString(nil,"OVERLAY","GameFontNormalLarge")
    hdr:SetPoint("TOPLEFT",0,-4)
    hdr:SetText(LABEL_COLOR.."Profile Copy Tool|r")

    local desc = profilesFrame:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    desc:SetPoint("TOPLEFT",0,-28); desc:SetWidth(860)
    desc:SetJustifyH("LEFT"); desc:SetWordWrap(true)
    desc:SetTextColor(0.8,0.8,0.8,1)
    desc:SetText(
        "Copy alert settings, positions, sounds, and resource bar configuration from any saved "..
        "spec profile into another. Useful for setting up a new character or spec using the same layout as an existing one.\n"..
        WARNING_COLOR.."Warning: copying overwrites the destination — this cannot be undone.|r"
    )

    local srcLabel = profilesFrame:CreateFontString(nil,"OVERLAY","GameFontNormal")
    srcLabel:SetPoint("TOPLEFT",0,-84); srcLabel:SetText("Copy FROM:")

    local srcDropBtn = CreateFrame("Button","CSProfileSrcDrop",profilesFrame,"GameMenuButtonTemplate")
    srcDropBtn:SetSize(280,24); srcDropBtn:SetPoint("TOPLEFT",0,-106)
    srcDropBtn:SetText("(select source profile)")
    srcDropBtn.selectedKey = nil

    local dstLabel = profilesFrame:CreateFontString(nil,"OVERLAY","GameFontNormal")
    dstLabel:SetPoint("TOPLEFT",0,-142); dstLabel:SetText("Copy INTO:")

    local dstDropBtn = CreateFrame("Button","CSProfileDstDrop",profilesFrame,"GameMenuButtonTemplate")
    dstDropBtn:SetSize(280,24); dstDropBtn:SetPoint("TOPLEFT",0,-164)
    dstDropBtn:SetText("Current spec (active)")
    dstDropBtn.selectedKey = nil

    local optLabel = profilesFrame:CreateFontString(nil,"OVERLAY","GameFontNormal")
    optLabel:SetPoint("TOPLEFT",0,-204); optLabel:SetText("What to copy:")

    local alertsCb = CreateFrame("CheckButton","CSProfileCopyAlerts",profilesFrame,"UICheckButtonTemplate")
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

    local statusLabel = profilesFrame:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    statusLabel:SetPoint("TOPLEFT",whispersCb,"BOTTOMLEFT",0,-18); statusLabel:SetWidth(500)
    statusLabel:SetJustifyH("LEFT"); statusLabel:SetWordWrap(true)
    statusLabel:SetText("")

    local copyBtn = CreateFrame("Button","CSProfileCopyBtn",profilesFrame,"GameMenuButtonTemplate")
    copyBtn:SetSize(160,26); copyBtn:SetPoint("TOPLEFT",statusLabel,"BOTTOMLEFT",0,-14)
    copyBtn:SetText("Copy Profile →")

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
        for _,c in ipairs({dropContent:GetChildren()}) do c:Hide() end
        local rows = {}
        if includeCurrentSpec then
            table.insert(rows,{key=nil, label="|cFF00FF00Current spec (active)|r"})
        end
        if RogUIDB and RogUIDB.specProfiles then
            local sortedKeys = {}
            for k in pairs(RogUIDB.specProfiles) do table.insert(sortedKeys,k) end
            table.sort(sortedKeys)
            for _,k in ipairs(sortedKeys) do
                local class, specID = k:match("^(.-)_(%d+)$")
                local display = k
                if class and specID then
                    local classNice = class:sub(1,1):upper() .. class:sub(2):lower()
                    display = classNice .. "  |cFFAAAAAA(" .. k .. ")|r"
                end
                table.insert(rows,{key=k, label=display})
            end
        end
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
        if not RogUIDB or not RogUIDB.specProfiles then
            statusLabel:SetText("|cFFFF4444No saved profiles found.|r"); return
        end
        local srcProfile = RogUIDB.specProfiles[srcKey]
        if not srcProfile then
            statusLabel:SetText("|cFFFF4444Source profile not found.|r"); return
        end

        local dstKey = dstDropBtn.selectedKey
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
            dstProfile.whisperList    = DeepCopy(srcProfile.whisperList or {})
            dstProfile.whisperEnabled = srcProfile.whisperEnabled
            table.insert(copied,"whispers")
        end

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

    API._profilesFrameReady = true
    API._profilesFrame      = profilesFrame
end

API.RegisterEvent("Core", "PLAYER_LOGIN", function()
    UpdateMainFrameSize()
    local CURRENT_VERSION = (C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata)("RogUI_Core", "Version") or "3.0"
    -- isFirstRun: RogUIDB exists (InitialiseDatabases ensures that) but has no dbVersion
    -- meaning it was just created empty this session with no saved data
    local isFirstRun  = (RogUIDB == nil) or (RogUIDB.dbVersion == nil and next(RogUIDB) == nil)
    -- isUpdate: has data but version stamp differs - only fill in MISSING keys, never overwrite
    local isUpdate    = (not isFirstRun) and (RogUIDB.dbVersion ~= CURRENT_VERSION)

    if isFirstRun then
        RogUIDB = {
            dbVersion=CURRENT_VERSION,
            specProfiles={}, minimapAngle=225, minimapRadius=80,
            minimapBtnShown=true, mainFramePos=nil,
            whisperList={}, whisperEnabled=false, ignoreOutgoingWhispers=true,
            generalWhisperSound=nil, generalWhisperSoundIsID=false,
            breakBarR=0.2,breakBarG=0.6,breakBarB=1.0,breakBarX=nil,breakBarY=nil,
            petReminderEnabled=false,petReminderSize=18,
            petReminderR=1,petReminderG=0.4,petReminderB=0,petReminderX=0,petReminderY=80,
            buffDebuffAlertsEnabled=false,
            whisperIndicatorEnabled=false,
            resourceBarsEnabled=false,
            pullTimerEnabled=false,
            breakTimerEnabled=false,
            poisonAlertEnabled=false,
            raidbuffCheckEnabled=false,
            battlerezEnabled=false,
            bagUpgradeEnabled=false,
            sellConfirmEnabled=false,
            expBarEnabled=false,
            repBarEnabled=false,
            alsEnabled=false,
            wowSettings={},
            cdMismatchSuppressed=false,
            uiFadeNameplates=100,uiFadeMinimap=100,uiFadeActionBars=100,
        }
        RogUICastbarDB = RogUICastbarDB or {}
        RogUICastbarDB.enabled = false
    else
        if not RogUIDB.specProfiles then RogUIDB.specProfiles={} end
        if isUpdate then
            local newKeys = {
                bagUpgradeEnabled=false,
                sellConfirmEnabled=false,
                expBarEnabled=false,
                repBarEnabled=false,
                alsEnabled=false,
                expBarHideAtMax=true,
                uiFadeActionBars=100,
                hideActionBars=false,
            }
            for k,v in pairs(newKeys) do
                if RogUIDB[k] == nil then RogUIDB[k] = v end
            end
            RogUICastbarDB = RogUICastbarDB or {}
            if RogUICastbarDB.enabled == nil then RogUICastbarDB.enabled = false end
            RogUIDB.dbVersion = CURRENT_VERSION
        end
    end

    API.playerClass   = select(2,UnitClass("player")) or "UNKNOWN"
    API.currentSpecID = GetSpecializationInfo(GetSpecialization()) or 0

    buffAlertEnabledCheckbox:SetChecked(RogUIDB.buffDebuffAlertsEnabled==true)
    whisperIndicatorEnabledCheckbox:SetChecked(RogUIDB.whisperIndicatorEnabled==true)
    minimapBtnCheckbox:SetChecked(RogUIDB.minimapBtnShown~=false)
    resourceBarsEnabledCheckbox:SetChecked(RogUIDB.resourceBarsEnabled==true)
    UpdateMinimapPos(RogUIDB.minimapAngle or 225, RogUIDB.minimapRadius or 80)
    if RogUIDB.minimapBtnShown==false then minimapBtn:Hide() end
    UpdateMainFrameSize()

    local specIndex=GetSpecialization and GetSpecialization()
    local specName=specIndex and select(2,GetSpecializationInfo(specIndex)) or "Unknown"
    specInfoLabel:SetText("Active Spec: |cFFFFD700"..(API.playerClass or "?").." – "..tostring(specName).."|r")

    LoadSpecProfile()

    if RogUIDB.debugEnabled ~= nil then
        API.DEBUG = RogUIDB.debugEnabled
    end

    if API._profilesFrameReady then
        RegisterTab("Profiles", API._profilesFrame, nil, 90, nil, 10)
    end

    local function AllModulesOff()
        local db = RogUIDB
        if not db then return true end
        return not db.buffDebuffAlertsEnabled
           and not db.whisperIndicatorEnabled
           and not db.resourceBarsEnabled
           and not db.pullTimerEnabled
           and not db.breakTimerEnabled
           and not db.poisonAlertEnabled
           and not db.raidbuffCheckEnabled
           and not db.battlerezEnabled
           and not db.bagUpgradeEnabled
           and not db.sellConfirmEnabled
           and not db.expBarEnabled
           and not db.repBarEnabled
           and not db.alsEnabled
           and (not RogUICastbarDB or not RogUICastbarDB.enabled)
    end

    if isFirstRun or isUpdate or AllModulesOff() then
        C_Timer.After(1, function()
            local verb = isFirstRun and "installed"
                      or isUpdate   and ("updated to v"..CURRENT_VERSION)
                      or "ready"
            print("|cFF00CCFF[RogUI]|r "..verb.." — all modules are |cFFFFD700off|r. Open the Setup Guide to enable what you need.")
            if setupPanel then
                setupPanel:Show()
                mainFrame:Show()
                if tabButtons[1] then ActivateTabByIndex(1) end
            end
        end)
    end

    Debug("[RogUI] Core PLAYER_LOGIN complete — " .. #modules .. " modules registered")
end)

API.RegisterEvent("Core", "PLAYER_SPECIALIZATION_CHANGED", function()
    local newSpecID = GetSpecializationInfo(GetSpecialization()) or 0
    if newSpecID ~= API.currentSpecID then
        SaveSpecProfile()
        API.currentSpecID = newSpecID
        LoadSpecProfile()
        local si = GetSpecialization and GetSpecialization()
        local sn = si and select(2,GetSpecializationInfo(si)) or "Unknown"
        specInfoLabel:SetText("Active Spec: |cFFFFD700"..(API.playerClass or "?").." – "..tostring(sn).."|r")
        Debug("[RogUI] Spec changed to "..tostring(sn).." — loaded spec profile.")
    end
end)

SLASH_CUSTOMSOUNDS1="/qol"; SLASH_CUSTOMSOUNDS2="/rogui"
SlashCmdList["CUSTOMSOUNDS"]=function()
    if mainFrame:IsShown() then mainFrame:Hide()
    else mainFrame:Show(); if tabButtons[1] then ActivateTabByIndex(1) end end
end

SLASH_UNREADWHISPERS1="/clearwhispers"
SlashCmdList["UNREADWHISPERS"]=function()
    if API.ClearUnreadWhispers then API.ClearUnreadWhispers() end
    print("|cFF00FF00[RogUI]|r Unread whispers cleared.")
end

SLASH_CUSTOMSOUNDTEST1="/soundtest"
SlashCmdList["CUSTOMSOUNDTEST"]=function() PlayCustomSound(12743,true) end

SLASH_MQLDEBUG1="/mqldebug"
SlashCmdList["MQLDEBUG"]=function()
    API.DEBUG = not API.DEBUG
    if RogUIDB then RogUIDB.debugEnabled = API.DEBUG end
    if API.DEBUG then
        if API.EnableErrorLog then API.EnableErrorLog() end
        print("|cFF00FF00[RogUI]|r Debug mode |cFFFFFF00ENABLED|r — errors will be saved to SavedVariables on logout")
    else
        if API.DisableErrorLog then API.DisableErrorLog() end
        print("|cFF00FF00[RogUI]|r Debug mode |cFFAAAAAAdisabled|r")
    end
    if _G["CSGenDebugCheck"] then _G["CSGenDebugCheck"]:SetChecked(API.DEBUG) end
end

SLASH_MQLAURAS1="/mqlauras"
SlashCmdList["MQLAURAS"]=function()
    print("|cFF00CCFF[RogUI Aura Dump]|r ----------")
    local i = 1
    while true do
        local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
        if not ok or not aura then break end
        local name = aura.name or "?"
        local sid  = aura.spellId or 0
        print(string.format("  [%d] %s  sid=%d  stacks=%s  dur=%.1f",
            i, name, sid,
            tostring(aura.applications or 0),
            aura.duration or 0))
        i = i + 1
    end
    print("  -- Tracked buff IDs currently active: --")
    if API and API.trackedBuffs then
        for _, buff in ipairs(API.trackedBuffs) do
            if buff.enabled ~= false and buff.spellId then
                local ok2, aura2 = pcall(C_UnitAuras.GetPlayerAuraBySpellID, buff.spellId)
                local active = ok2 and aura2 and "ACTIVE" or "absent"
                local ok3, info = pcall(C_Spell.GetSpellInfo, buff.spellId)
                local sname = ok3 and info and info.name or "?"
                print(string.format("  sid=%d (%s): %s", buff.spellId, sname, active))
            end
        end
    end
    print("|cFF00CCFF[RogUI Aura Dump]|r ----------")
end

SLASH_MQOLCORE1 = "/mqolcore"
SlashCmdList.MQOLCORE = function(msg)
    local cmd = strsplit(" ", msg, 1)
    if cmd == "modules" then
        print("|cFFFFFF00[RogUI] Registered Modules:|r")
        for name, mod in pairs(modulesByName) do
            local status = mod.enabled and "|cFF00FF00ON|r" or "|cFFFF0000OFF|r"
            print(format("  %s: %s", name, status))
        end
    elseif cmd == "events" then
        print("|cFFFFFF00[RogUI] Registered Events:|r")
        for eventName, handlers in pairs(eventHandlers) do
            print(format("  %s: %d handlers", eventName, #handlers))
        end
    else
        print("|cFFFFFF00RogUI Debug Commands:|r")
        print("  /mqolcore modules   - List all modules")
        print("  /mqolcore events    - List all events")
    end
end

local _origErrHandler = geterrorhandler()

local function MQLErrorHandler(err)
    if API.DEBUG then
        local entry = date("%H:%M:%S") .. " " .. tostring(err)
        _errorLog[#_errorLog + 1] = entry
    end
    if _origErrHandler then _origErrHandler(err) end
end

local function EnableErrorLog()
    for i = #_errorLog, 1, -1 do _errorLog[i] = nil end
    _errorLog[1] = date("%Y-%m-%d %H:%M:%S") .. " ===== Debug session started ====="
    seterrorhandler(MQLErrorHandler)
    Debug("[RogUI] Error logging to SavedVariables enabled")
end

local function DisableErrorLog()
    seterrorhandler(_origErrHandler)
    Debug("[RogUI] Error logging disabled")
end

API.EnableErrorLog  = EnableErrorLog
API.DisableErrorLog = DisableErrorLog

API.RegisterEvent("Core", "PLAYER_LOGOUT", function()
    if RogUIDB then
        RogUIDB.errorLog = (#_errorLog > 0) and _errorLog or nil
    end
end)

API.RegisterEvent("Core", "PLAYER_LOGIN", function()
    if API.DEBUG then
        EnableErrorLog()
    end
end)