-- ============================================================
-- RogUI / Modules / Keystones / MythicTimer.lua
-- M+ Dungeon Timer - Tracks time, deaths, splits, and forces
-- Integrated WarpDeplete-style logic for Midnight expansion
-- ============================================================

local API = RogUIAPI
if not API then return end

-- ── DB & Defaults ─────────────────────────────────────────────────────────────
local TIMER_DEFAULTS = {
    enabled = true,
    posX    = 0,
    posY    = 200,
    scale   = 1.0,
    opacity = 0.7,
    showSplits = true,
    showDeathLog = true,
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

-- ── State Management ──────────────────────────────────────────────────────────
local timerState = {
    isActive = false,
    elapsedTime = 0,
    timeLimit = 0,
    thresholds = { plus2 = 0, plus3 = 0 },
    
    deathCount = 0,
    deathTimeLost = 0,
    
    currentForces = 0,
    maxForces = 0,
    
    mapID = 0,
    keystoneLevel = 0,
    objectives = {}, -- { name, time, bestTime, isCompleted }
    
    -- Pull tracking
    currentPull = {}, -- guid -> count
    pullCount   = 0,
}

-- ── Utilities ─────────────────────────────────────────────────────────────────
local function FormatTime(seconds)
    if not seconds or seconds < 0 then return "0:00" end
    local m = math.floor(seconds / 60)
    local s = math.floor(seconds % 60)
    return string.format("%d:%02d", m, s)
end

local function GetNPCForces(npcID)
    if not MDT or not npcID then return nil end
    local count = MDT:GetEnemyForces(npcID)
    local _, max = C_Scenario.GetStepInfo()
    return count, max
end

-- ── Split Tracking (WarpDeplete Emulation) ────────────────────────────────────
local function GetBestSplit(mapID, level, index)
    if not RogUIDB.keystoneSplits then return nil end
    local key = string.format("%d_%d", mapID, level)
    if RogUIDB.keystoneSplits[key] then
        return RogUIDB.keystoneSplits[key][index]
    end
    return nil
end

local function SaveSplit(mapID, level, index, time)
    RogUIDB.keystoneSplits = RogUIDB.keystoneSplits or {}
    local key = string.format("%d_%d", mapID, level)
    RogUIDB.keystoneSplits[key] = RogUIDB.keystoneSplits[key] or {}
    
    local currentBest = RogUIDB.keystoneSplits[key][index]
    if not currentBest or time < currentBest then
        RogUIDB.keystoneSplits[key][index] = time
    end
end

-- ── Logic Handlers ────────────────────────────────────────────────────────────
local function UpdateObjectives()
    local _, _, numObjectives = C_Scenario.GetStepInfo()
    for i = 1, numObjectives do
        local description, _, completed, _, _, _, _, _, _, _, _, _, _ = C_Scenario.GetCriteriaInfo(i)
        
        if not timerState.objectives[i] then
            timerState.objectives[i] = { name = description, isCompleted = false }
        end
        
        if completed and not timerState.objectives[i].isCompleted then
            timerState.objectives[i].isCompleted = true
            timerState.objectives[i].time = timerState.elapsedTime
            SaveSplit(timerState.mapID, timerState.keystoneLevel, i, timerState.elapsedTime)
        end
        
        timerState.objectives[i].bestTime = GetBestSplit(timerState.mapID, timerState.keystoneLevel, i)
    end
end

local function OnChallengeStart()
    local mapID, _, timeLimit = C_ChallengeMode.GetActiveKeystoneInfo()
    if not mapID or mapID == 0 then return end

    timerState.isActive = true
    timerState.mapID = mapID
    timerState.timeLimit = timeLimit / 1000
    timerState.keystoneLevel = select(2, C_ChallengeMode.GetActiveKeystoneInfo())
    
    -- Calculate WarpDeplete-style thresholds (+2 = 80%, +3 = 60%)
    timerState.thresholds.plus2 = timerState.timeLimit * 0.8
    timerState.thresholds.plus3 = timerState.timeLimit * 0.6
    
    timerState.deathCount, timerState.deathTimeLost = C_ChallengeMode.GetDeathCount()
    timerState.objectives = {}
    UpdateObjectives()
end

local function OnDeathUpdate()
    if not timerState.isActive then return end
    local count, timeLost = C_ChallengeMode.GetDeathCount()
    timerState.deathCount = count
    timerState.deathTimeLost = timeLost
end

local function OnChallengeComplete()
    timerState.isActive = false
    -- Final split check
    UpdateObjectives()
end

-- ── UI Update Loop ──────────────────────────────────────────────────────────
local function OnUpdate(self, elapsed)
    if not timerState.isActive then return end
    
    -- Sync with world timer for precision
    local _, worldTime = GetWorldElapsedTime(1)
    timerState.elapsedTime = worldTime
    
    -- Update force percentages
    local _, _, _, current, max = C_Scenario.GetStepInfo()
    timerState.currentForces = current or 0
    timerState.maxForces = max or 0
    
    -- Render call (assumes your MythicTimerUI.lua handles the display)
    if API.UpdateMythicTimerUI then
        API.UpdateMythicTimerUI(timerState)
    end
end

-- ── Tooltip Hook (MDT Integration) ──────────────────────────────────────────
if TooltipDataProcessor then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tt, data)
        if tt ~= GameTooltip or not timerState.isActive or not data or not data.guid then return end

        -- GUIDs from secure tooltip callbacks are secret values in Midnight.
        -- issecretvalue() detects them; any string operation on a secret value taints.
        local guid = data.guid
        if not guid then return end
        if issecretvalue and issecretvalue(guid) then return end
        if type(guid) ~= "string" then return end

        -- Extract NPC ID from GUID safely. Format: "Creature-0-X-X-X-NPCID-X"
        -- pcall guards against any edge-case string content.
        local npcID
        local ok, result = pcall(function()
            local seg = guid:match("^%a+%-%d+%-%d+%-%d+%-%d+%-(%d+)%-")
            return seg and tonumber(seg)
        end)
        if not ok or not result then return end
        npcID = result
        
        local count, max = GetNPCForces(npcID)
        
        if count and max and count > 0 then
            local pct = (count / max) * 100
            local pullPct = (timerState.pullCount / max) * 100
            
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(string.format("Forces: |cFFFFFFFF%.2f%%|r  (%d/%d)", pct, count, max))
            if timerState.pullCount > 0 then
                GameTooltip:AddLine(string.format("Current Pull: |cFF00FF00+%.2f%%|r", pullPct))
            end
            GameTooltip:Show()
        end
    end)
end

-- ── Events ────────────────────────────────────────────────────────────────────
API.RegisterEvent("Keystones", "CHALLENGE_MODE_START",         OnChallengeStart)
API.RegisterEvent("Keystones", "CHALLENGE_MODE_COMPLETED",     OnChallengeComplete)
API.RegisterEvent("Keystones", "CHALLENGE_MODE_RESET",         OnChallengeComplete)
API.RegisterEvent("Keystones", "CHALLENGE_MODE_DEATH_COUNT_UPDATED", OnDeathUpdate)
API.RegisterEvent("Keystones", "SCENARIO_CRITERIA_UPDATE",     UpdateObjectives)

-- Initialize OnUpdate frame
local updater = CreateFrame("Frame")
updater:SetScript("OnUpdate", OnUpdate)