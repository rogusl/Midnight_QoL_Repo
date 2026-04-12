-- ============================================================
-- RogUI / Modules / ModuleLoader.lua
-- Centralized module loading and initialization system
-- ============================================================

local API = RogUIAPI

-- ════════════════════════════════════════════════════════════
-- MODULE INITIALIZATION WRAPPER
-- All modules use this pattern to avoid duplicate function definitions
-- ════════════════════════════════════════════════════════════

local function CreateModuleInitializer(moduleName)
    return {
        name = moduleName,
        enabled = true,
        
        -- Standard defaults that all modules can use
        defaults = {},
        
        -- Get module's database
        GetDB = function(self, defaults)
            if not self.defaults then self.defaults = {} end
            
            local dbName = "RogUI" .. moduleName .. "DB"
            if not _G[dbName] then
                _G[dbName] = {}
            end
            
            local db = _G[dbName]
            if defaults then
                for k, v in pairs(defaults) do
                    if db[k] == nil then db[k] = v end
                end
            end
            
            self.db = db
            return db
        end,
        
        -- Register event handler via centralized system
        RegisterEvent = function(self, eventName, handler)
            API.RegisterEvent(moduleName, eventName, handler)
        end,
        
        -- Unregister event handler
        UnregisterEvent = function(self, eventName)
            API.UnregisterEvent(moduleName, eventName)
        end,
        
        -- Unregister all module events
        UnregisterAllEvents = function(self)
            API.UnregisterAllEvents(moduleName)
        end,
        
        -- Register profile callbacks (common pattern)
        RegisterProfileCallbacks = function(self, onSave, onLoad)
            API.RegisterProfileCallbacks(onSave, onLoad)
        end,
        
        -- Hook a frame for consistent behavior
        HookFrame = function(self, frame)
            API.HookFrame(frame)
        end,
        
        -- Enable/disable module
        SetEnabled = function(self, enabled)
            self.enabled = enabled
        end,
        
        IsEnabled = function(self)
            return self.enabled
        end,
    }
end

API.CreateModuleInitializer = CreateModuleInitializer

-- ════════════════════════════════════════════════════════════
-- SHARED HELPER FUNCTIONS (to reduce duplication)
-- ════════════════════════════════════════════════════════════

-- Shared GetDB pattern (simple version for backward compat)
local function GetDB(dbName, defaults)
    if not _G[dbName] then
        _G[dbName] = {}
    end
    
    local db = _G[dbName]
    if defaults then
        for k, v in pairs(defaults) do
            if db[k] == nil then db[k] = v end
        end
    end
    
    return db
end

API.GetDB = GetDB

-- Shared UpdateTicks for castbar and resource bar modules
function API.UpdateChannelTicks(frame, spellID, channelTicksMap, height)
    local ticks = channelTicksMap[spellID]
    if not ticks or ticks < 2 then
        for i = 1, 10 do
            if frame.ticks and frame.ticks[i] then
                frame.ticks[i]:Hide()
            end
        end
        return
    end
    
    for i = 1, 10 do
        if not frame.ticks or not frame.ticks[i] then break end
        if i >= ticks then
            frame.ticks[i]:Hide()
        else
            local ratio = i / ticks
            frame.ticks[i]:SetPoint("LEFT", frame.bar, "LEFT", frame.bar:GetWidth() * ratio, 0)
            frame.ticks[i]:Show()
        end
    end
end

-- ════════════════════════════════════════════════════════════
-- COMMON UNIT FRAME HELPER
-- Used by UnitFrames and RaidFrames modules
-- ════════════════════════════════════════════════════════════

function API.GetWatchedFaction()
    local watchedFactionIndex = GetWatchedFactionInfo()
    if not watchedFactionIndex then return nil end
    
    local name, standing, barMin, barMax, barValue = GetFactionInfoByID(watchedFactionIndex)
    return {
        name = name,
        standing = standing,
        barMin = barMin,
        barMax = barMax,
        barValue = barValue,
    }
end

function API.RebuildEqSetCache()
    -- Shared cache for SmartSwap module
    if not API.eqSetCache then API.eqSetCache = {} end
    
    wipe(API.eqSetCache)
    
    for i = 1, C_EquipmentSet.GetNumEquipmentSets() do
        local name = C_EquipmentSet.GetEquipmentSetInfo(i)
        if name then
            local items = C_EquipmentSet.GetItemsForEquipmentSet(name)
            API.eqSetCache[name] = items
        end
    end
    
    return API.eqSetCache
end

-- ════════════════════════════════════════════════════════════
-- TAB SYSTEM (used by UnitFrames, ResourceBars, BuffAlerts, etc.)
-- ════════════════════════════════════════════════════════════

-- Generic tab activation/deactivation callbacks used by multiple modules
function API.CreateTabCallbacks(modName, onActivate, onDeactivate)
    local function OnTabActivate()
        if onActivate then onActivate() end
    end
    
    local function OnTabDeactivate()
        if onDeactivate then onDeactivate() end
    end
    
    return OnTabActivate, OnTabDeactivate
end

-- ════════════════════════════════════════════════════════════
-- LAYOUT/EDIT MODE HELPERS
-- Shared by modules that support layout editing
-- ════════════════════════════════════════════════════════════

local layoutEditFrames = {}

function API.RegisterLayoutFrame(frame, modName)
    if not layoutEditFrames[modName] then
        layoutEditFrames[modName] = {}
    end
    table.insert(layoutEditFrames[modName], frame)
end

function API.GetLayoutFrames(modName)
    return layoutEditFrames[modName] or {}
end

-- ════════════════════════════════════════════════════════════
-- SPELL LOOKUP HELPER
-- Used by BuffAlerts, RaidFrames, and other modules
-- ════════════════════════════════════════════════════════════

function API.GetClassSpellList(listType)
    local map = {
        WARRIOR    = WarriorSpells,
        PALADIN    = PaladinSpells,
        HUNTER     = HunterSpells,
        ROGUE      = RogueSpells,
        PRIEST     = PriestSpells,
        DRUID      = DruidSpells,
        SHAMAN     = ShamanSpells,
        MAGE       = MageSpells,
        WARLOCK    = WarlockSpells,
        DEATHKNIGHT = DeathKnightSpells,
        DEMONHUNTER = DemonHunterSpells,
        MONK       = MonkSpells,
        EVOKER     = EvokerSpells,
    }
    
    local t = map[API.playerClass or ""]
    if not t then return {} end
    
    -- Spell files use plural keys ("buffs"/"debuffs")
    local key = (listType == "buff") and "buffs" or (listType == "debuff") and "debuffs" or listType
    return (t and t[key]) or {}
end

function API.GetExternalBuffSpells()
    if not ExternalBuffSpells then return {} end
    
    local available = {}
    for _, spell in ipairs(ExternalBuffSpells) do
        if spell.ids then
            table.insert(available, {id=spell.ids[1], ids=spell.ids, name=spell.name})
        else
            table.insert(available, {id=spell.id, name=spell.name})
        end
    end
    return available
end

print("|cFF00FF00[RogUI] Module loader system initialized|r")
