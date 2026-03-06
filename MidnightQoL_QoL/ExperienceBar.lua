-- ============================================================
-- MidnightQoL_QoL / ExperienceBar.lua
-- Slim, styled experience / reputation / artifact bar that
-- replaces the default Blizzard XP bar.
-- • 10% tick marks
-- • Pending fill rendered with solid colour (no empty-box glitch)
-- • Drag only works while Edit Layout is active
-- ============================================================

local API = MidnightQoLAPI

-- ── Default settings ──────────────────────────────────────────────────────────
local DEFAULTS = {
    expBarEnabled    = true,
    expBarWidth      = 600,
    expBarHeight     = 10,
    expBarX          = 0,
    expBarY          = -310,
    expBarShowText   = true,
    expBarShowRested = true,
    expBarColorR     = 0.0,
    expBarColorG     = 0.6,
    expBarColorB     = 1.0,
    expBarRestedR    = 0.3,
    expBarRestedG    = 0.0,
    expBarRestedB    = 0.8,
    expBarBgR        = 0.0,
    expBarBgG        = 0.0,
    expBarBgB        = 0.0,
    expBarBgA        = 0.55,
    expBarRepR       = 0.8,
    expBarRepG       = 0.2,
    expBarRepB       = 1.0,
    expBarMouseover  = true,
    expBarHideAtMax  = true,
    expBarShowRep    = true,
    expBarShowTTL    = true,
    expBarPendingR   = 1.0,
    expBarPendingG   = 0.85,
    expBarPendingB   = 0.0,
}

-- ── Frame construction ────────────────────────────────────────────────────────
local expBar = CreateFrame("Frame", "MidnightQoLExpBar", UIParent)
expBar:SetFrameStrata("MEDIUM")
expBar:SetFrameLevel(10)
expBar:SetClampedToScreen(true)

-- Background
local bg = expBar:CreateTexture(nil, "BACKGROUND")
bg:SetAllPoints()
bg:SetColorTexture(0, 0, 0, 0.55)

-- Rested XP fill (behind main fill)
local restedFill = expBar:CreateTexture(nil, "BORDER")
restedFill:SetPoint("TOPLEFT")
restedFill:SetPoint("BOTTOMLEFT")
restedFill:SetColorTexture(0.3, 0.0, 0.8, 0.55)
restedFill:SetWidth(1)
restedFill:Hide()

-- Pending quest XP fill – solid colour, never zero-width while shown
local pendingFill = expBar:CreateTexture(nil, "BORDER", nil, 1)
pendingFill:SetPoint("TOPLEFT")
pendingFill:SetPoint("BOTTOMLEFT")
pendingFill:SetColorTexture(1.0, 0.85, 0.0, 0.55)
pendingFill:SetWidth(1)
pendingFill:Hide()

-- Main XP fill
local fill = expBar:CreateTexture(nil, "ARTWORK")
fill:SetPoint("TOPLEFT")
fill:SetPoint("BOTTOMLEFT")
fill:SetColorTexture(0.0, 0.6, 1.0, 1)
fill:SetWidth(1)

-- Shine / gloss overlay
local gloss = expBar:CreateTexture(nil, "OVERLAY")
gloss:SetAllPoints()
gloss:SetColorTexture(1, 1, 1, 0.04)

-- Thin top-edge highlight line
local edgeLine = expBar:CreateTexture(nil, "OVERLAY")
edgeLine:SetPoint("TOPLEFT",  expBar, "TOPLEFT",  0, 0)
edgeLine:SetPoint("TOPRIGHT", expBar, "TOPRIGHT", 0, 0)
edgeLine:SetHeight(1)
edgeLine:SetColorTexture(1, 1, 1, 0.18)

-- Rested indicator — small tinted glow shown when rested XP is active
local restedGlow = expBar:CreateTexture(nil, "OVERLAY")
restedGlow:SetAllPoints()
restedGlow:SetColorTexture(0.3, 0.0, 0.8, 0.08)
restedGlow:Hide()

-- ── 10% Tick marks ────────────────────────────────────────────────────────────
local NUM_TICKS = 9
local expTicks = {}
for i = 1, NUM_TICKS do
    local tick = expBar:CreateTexture(nil, "OVERLAY")
    tick:SetWidth(1)
    tick:SetColorTexture(1, 1, 1, 0.35)
    expTicks[i] = tick
end

local function UpdateTicks()
    local barW = expBar:GetWidth()
    for i = 1, NUM_TICKS do
        expTicks[i]:ClearAllPoints()
        local xPos = barW * (i / 10)
        expTicks[i]:SetPoint("TOP",    expBar, "TOPLEFT",    xPos, 0)
        expTicks[i]:SetPoint("BOTTOM", expBar, "BOTTOMLEFT", xPos, 0)
    end
end

-- Text lives on a child frame at a higher frame level
local textFrame = CreateFrame("Frame", nil, UIParent)
textFrame:SetAllPoints(expBar)
textFrame:SetFrameStrata("HIGH")
textFrame:SetFrameLevel(100)

local barText = textFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
barText:SetPoint("CENTER", textFrame, "CENTER", 0, 0)
barText:SetJustifyH("CENTER")
barText:SetTextColor(1, 1, 1, 1)
barText:SetFont(barText:GetFont(), 9, "OUTLINE")

-- ── XP rate / time-to-level tracking ─────────────────────────────────────────
local xpSamples  = {}
local SAMPLE_CAP = 1800

local function RecordXPSample(curXP)
    local now = GetTime()
    table.insert(xpSamples, { t = now, xp = curXP })
    while #xpSamples > 1 and (now - xpSamples[1].t) > SAMPLE_CAP do
        table.remove(xpSamples, 1)
    end
end

local function GetXPPerHour()
    if #xpSamples < 2 then return nil end
    local newest = xpSamples[#xpSamples]
    local oldest = xpSamples[1]
    local dt  = newest.t  - oldest.t
    if dt < 5 then return nil end
    local dxp = newest.xp - oldest.xp
    if dxp <= 0 then return nil end
    return (dxp / dt) * 3600
end

local function FormatTimeToLevel(seconds)
    if seconds <= 0 then return nil end
    local h = math.floor(seconds / 3600)
    local m = math.floor((seconds % 3600) / 60)
    local s = math.floor(seconds % 60)
    if h > 0 then return string.format("%dh %dm", h, m)
    elseif m > 0 then return string.format("%dm %ds", m, s)
    else return string.format("%ds", s) end
end

-- ── Pending quest XP ──────────────────────────────────────────────────────────
-- ── Session XP tracking ──────────────────────────────────────────────────────
-- Persisted in saved vars so it survives /reload but resets on level-up.
local sessionStartXP  = nil   -- XP at start of session
local sessionStartTime= nil   -- time() at start of session
local sessionLevel    = nil   -- level when session started

local function InitSession()
    local db = GetDB()
    local curXP = UnitXP("player")
    local level = UnitLevel("player")
    -- Reset if levelled up since last session
    if db.sessionLevel and db.sessionLevel ~= level then
        db.sessionXP      = nil
        db.sessionTime    = nil
        db.sessionLevel   = nil
    end
    if not db.sessionXP then
        db.sessionXP    = curXP
        db.sessionTime  = time()
        db.sessionLevel = level
    end
    sessionStartXP   = db.sessionXP
    sessionStartTime = db.sessionTime
    sessionLevel     = db.sessionLevel
end

local function GetSessionXP()
    local curXP = UnitXP("player")
    local start = sessionStartXP or curXP
    return math.max(0, curXP - start)
end

local function GetSessionDuration()
    if not sessionStartTime then return 0 end
    return math.max(1, time() - sessionStartTime)
end

-- GetPendingQuestXP: exact port of EasyExperienceBar:UpdateQuestXP().
-- Critical order: SetSelectedQuest(i) → GetQuestIDForLogIndex(i) →
-- GetQuestLogRewardXP(questID) → THEN check IsComplete/ReadyForTurnIn.
-- Getting XP first (unconditionally) is what makes it work — gating behind
-- the completion check first causes GetQuestLogRewardXP to return 0.
--
-- Taint note: C_QuestLog.SetSelectedQuest modifies Blizzard's quest selection
-- state. If the QuestMapFrame (quest log UI) is open when we call it, WoW flags
-- our addon as the taint source and subsequent quest log interactions by the
-- player throw "action forbidden" errors. We skip the scan entirely while the
-- quest log is visible to avoid this.
local function GetPendingQuestXP()
    if not C_QuestLog then return 0, 0 end

    -- Bail out if the player has the quest log open — SetSelectedQuest taints it
    if QuestMapFrame and QuestMapFrame:IsShown() then return 0, 0 end
    if QuestLogFrame  and QuestLogFrame:IsShown()  then return 0, 0 end

    local numEntries = (C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetNumQuestLogEntries()) or 0
    if numEntries == 0 then return 0, 0 end

    local prevSelected = C_QuestLog.GetSelectedQuest and C_QuestLog.GetSelectedQuest()

    local totalXP, numQuests = 0, 0

    for i = 1, numEntries do
        if C_QuestLog.SetSelectedQuest then
            local ok = pcall(C_QuestLog.SetSelectedQuest, i)
            if not ok then break end  -- taint crept in mid-loop; abort cleanly
        end

        local questID = (C_QuestLog.GetQuestIDForLogIndex and C_QuestLog.GetQuestIDForLogIndex(i)) or 0
        if questID > 0 then
            -- Get XP first unconditionally — this is what EasyExperienceBar does
            local xp = (GetQuestLogRewardXP and GetQuestLogRewardXP(questID)) or 0
            if xp > 0 then
                -- Now check if complete
                local isComplete = (C_QuestLog.IsComplete    and C_QuestLog.IsComplete(questID))
                                or (C_QuestLog.ReadyForTurnIn and C_QuestLog.ReadyForTurnIn(questID))
                if isComplete then
                    totalXP   = totalXP + xp
                    numQuests = numQuests + 1
                end
            end
        end
    end

    if prevSelected and prevSelected > 0 and C_QuestLog.SetSelectedQuest then
        pcall(C_QuestLog.SetSelectedQuest, prevSelected)
    end

    return totalXP, numQuests
end

-- ── DB helper ─────────────────────────────────────────────────────────────────
local function GetDB()
    if not BuffAlertDB then return DEFAULTS end
    for k, v in pairs(DEFAULTS) do
        if BuffAlertDB[k] == nil then BuffAlertDB[k] = v end
    end
    return BuffAlertDB
end


-- ── Reputation API compatibility shim ─────────────────────────────────────────
local function GetWatchedFaction()
    if C_Reputation and C_Reputation.GetWatchedFactionData then
        local data = C_Reputation.GetWatchedFactionData()
        if data and data.name then
            local lo  = data.currentReactionThreshold or 0
            local hi  = data.nextReactionThreshold    or 0
            local val = data.currentStanding          or 0
            return data.name, lo, hi, val
        end
        return nil
    end
    if GetWatchedFactionInfo then
        local name, _, _, _, _, repMin, repMax, repValue = GetWatchedFactionInfo()
        if name then return name, repMin, repMax, repValue end
    end
    return nil
end

-- ── Apply current DB settings ─────────────────────────────────────────────────
local function ApplySettings()
    local db = GetDB()
    expBar:SetSize(db.expBarWidth, db.expBarHeight)
    expBar:ClearAllPoints()
    expBar:SetPoint("CENTER", UIParent, "CENTER", db.expBarX, db.expBarY)
    fill:SetColorTexture(db.expBarColorR, db.expBarColorG, db.expBarColorB, 1)
    restedFill:SetColorTexture(db.expBarRestedR, db.expBarRestedG, db.expBarRestedB, 0.55)
    pendingFill:SetColorTexture(db.expBarPendingR, db.expBarPendingG, db.expBarPendingB, 0.55)
    bg:SetColorTexture(db.expBarBgR, db.expBarBgG, db.expBarBgB, db.expBarBgA)
    UpdateTicks()
end

-- ── Core update logic ─────────────────────────────────────────────────────────
local function UpdateBar()
    local db = GetDB()
    if not db.expBarEnabled then expBar:Hide(); return end

    local level    = UnitLevel("player")
    local maxLevel = GetMaxPlayerLevel and GetMaxPlayerLevel() or 80

    -- At max level
    if level >= maxLevel then
        if db.expBarHideAtMax then
            expBar:Hide(); return
        end
        if db.expBarShowRep then
            local name, repMin, repMax, repValue = GetWatchedFaction()
            if name then
                expBar:Show()
                ApplySettings()
                local range = repMax - repMin
                local cur   = repValue - repMin
                local pct   = (range > 0) and (cur / range) or 0
                fill:SetWidth(math.max(1, expBar:GetWidth() * pct))
                fill:SetColorTexture(db.expBarRepR, db.expBarRepG, db.expBarRepB, 1)
                restedFill:SetWidth(1); restedFill:Hide()
                pendingFill:SetWidth(1); pendingFill:Hide()
                if db.expBarShowText then
                    barText:SetText(name .. ": " .. cur .. " / " .. range)
                    barText:Show()
                else
                    barText:Hide()
                end
                return
            end
        end
        expBar:Hide(); return
    end

    -- Normal XP
    local curXP  = UnitXP("player")
    local maxXP  = UnitXPMax("player")
    local rested = GetXPExhaustion() or 0

    if maxXP == 0 then expBar:Hide(); return end

    expBar:Show()
    ApplySettings()

    RecordXPSample(curXP)

    local barW  = expBar:GetWidth()
    local xpPct = curXP / maxXP
    fill:SetWidth(math.max(1, barW * xpPct))

    -- Rested overlay
    if db.expBarShowRested and rested > 0 then
        local restedPct = math.min(1, (curXP + rested) / maxXP)
        restedFill:SetWidth(math.max(1, barW * restedPct))
        restedFill:Show()
    else
        restedFill:SetWidth(1)
        restedFill:Hide()
    end

    -- Pending quest XP overlay
    local pendingXP, pendingCount = GetPendingQuestXP()
    if pendingXP > 0 then
        local pendingPct = math.min(1, (curXP + pendingXP) / maxXP)
        pendingFill:SetWidth(math.max(1, barW * pendingPct))
        pendingFill:Show()
    else
        pendingFill:SetWidth(1)
        pendingFill:Hide()
    end

    -- Text
    if db.expBarShowText then
        local pctDisplay = math.floor(xpPct * 100 + 0.5)
        local remaining  = maxXP - curXP
        local parts      = { pctDisplay .. "%" }

        if db.expBarShowTTL then
            local xphr = GetXPPerHour()
            if xphr and xphr > 0 then
                local secsLeft = (remaining / xphr) * 3600
                local ttl = FormatTimeToLevel(secsLeft)
                if ttl then table.insert(parts, ttl .. " to level") end
            else
                table.insert(parts, remaining .. " xp to level")
            end
        else
            table.insert(parts, remaining .. " xp to level")
        end

        if pendingXP > 0 then
            table.insert(parts, "|cFFFFD700+" .. pendingXP .. " pending (" .. pendingCount .. "q)|r")
        end

        barText:SetText(table.concat(parts, "  ·  "))
        barText:Show()
    else
        barText:Hide()
    end
end

-- ── Tooltip ───────────────────────────────────────────────────────────────────
expBar:SetScript("OnEnter", function(self)
    local db = GetDB()
    if not db.expBarMouseover then return end

    local level    = UnitLevel("player")
    local maxLevel = GetMaxPlayerLevel and GetMaxPlayerLevel() or 80

    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:ClearLines()

    if level >= maxLevel then
        local name, repMin, repMax, repValue = GetWatchedFaction()
        if name then
            GameTooltip:AddLine(name, 0.8, 0.2, 1.0)
            GameTooltip:AddLine((repValue - repMin) .. " / " .. (repMax - repMin) .. " reputation", 1, 1, 1)
        else
            GameTooltip:AddLine("Max Level", 1, 1, 0)
            GameTooltip:AddLine("Track a reputation to display it here.", 0.8, 0.8, 0.8)
        end
    else
        local curXP  = UnitXP("player")
        local maxXP  = UnitXPMax("player")
        local rested = GetXPExhaustion() or 0
        local pct    = (maxXP > 0) and math.floor(curXP / maxXP * 1000 + 0.5) / 10 or 0

        GameTooltip:AddLine("Experience", 0.0, 0.6, 1.0)
        GameTooltip:AddLine(curXP .. " / " .. maxXP .. "  (" .. pct .. "%)", 1, 1, 1)
        GameTooltip:AddLine((maxXP - curXP) .. " XP until level " .. (level + 1), 0.8, 0.8, 0.8)
        local xphr = GetXPPerHour()
        if xphr and xphr > 0 then
            local secsLeft = ((maxXP - curXP) / xphr) * 3600
            local ttl = FormatTimeToLevel(secsLeft)
            if ttl then
                GameTooltip:AddLine("Time to level: " .. ttl, 0.4, 1.0, 0.4)
                GameTooltip:AddLine(string.format("%.0f XP/hour", xphr), 0.6, 0.6, 0.8)
            end
        end
        local pendingXP, pendingCount = GetPendingQuestXP()
        if pendingXP > 0 then
            GameTooltip:AddLine(" ", 1, 1, 1)
            GameTooltip:AddLine("Completed quests ready to turn in:", 1, 0.85, 0)
            GameTooltip:AddLine(pendingCount .. " quest" .. (pendingCount == 1 and "" or "s") ..
                "  →  +" .. pendingXP .. " XP", 1, 1, 0.6)
            local afterXP = curXP + pendingXP
            if afterXP >= maxXP then
                GameTooltip:AddLine("Turning in would |cFF00FF00level you up!|r", 0.9, 0.9, 0.9)
            else
                local afterPct = math.floor(afterXP / maxXP * 100 + 0.5)
                GameTooltip:AddLine("Would bring you to " .. afterPct .. "% into the level", 0.75, 0.75, 0.75)
            end
        end
        if rested > 0 then
            GameTooltip:AddLine(" ", 1, 1, 1)
            GameTooltip:AddLine("Rested: +" .. rested .. " XP  (2x XP gain active)", 0.5, 0.3, 1.0)
        end
    end
    GameTooltip:Show()
end)
expBar:SetScript("OnLeave", function() GameTooltip:Hide() end)
expBar:EnableMouse(true)

-- ── Draggable repositioning (layout mode only) ────────────────────────────────
expBar:SetMovable(true)
expBar:RegisterForDrag("LeftButton")
expBar:SetScript("OnDragStart", function(self)
    if not (API.IsLayoutMode and API.IsLayoutMode()) then return end
    self:StartMoving()
end)
expBar:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local db = GetDB()
    local cx = UIParent:GetWidth()  / 2
    local cy = UIParent:GetHeight() / 2
    local fx = self:GetLeft() + self:GetWidth()  / 2
    local fy = self:GetBottom() + self:GetHeight() / 2
    db.expBarX = math.floor(fx - cx + 0.5)
    db.expBarY = math.floor(fy - cy + 0.5)
    self:ClearAllPoints()
    self:SetPoint("CENTER", UIParent, "CENTER", db.expBarX, db.expBarY)
end)

-- ── Events ────────────────────────────────────────────────────────────────────
local expEvents = CreateFrame("Frame")
expEvents:RegisterEvent("PLAYER_LOGIN")
expEvents:RegisterEvent("PLAYER_XP_UPDATE")
expEvents:RegisterEvent("PLAYER_LEVEL_UP")
expEvents:RegisterEvent("UPDATE_EXHAUSTION")
expEvents:RegisterEvent("UNIT_EXITED_VEHICLE")
expEvents:RegisterEvent("UPDATE_FACTION")
expEvents:RegisterEvent("QUEST_LOG_UPDATE")

expEvents:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_LOGIN" then
        local db = GetDB()
        ApplySettings()
        if db.expBarEnabled then
            if MainMenuExpBar then MainMenuExpBar:SetAlpha(0) end
            if ReputationWatchBar then ReputationWatchBar:SetAlpha(0) end
            if StatusTrackingBarManager then StatusTrackingBarManager:SetAlpha(0) end
        end
        C_Timer.After(0.2, UpdateBar)
    elseif event == "PLAYER_LEVEL_UP" then
        xpSamples = {}
        UpdateBar()
    else
        UpdateBar()
    end
end)

-- ── Expose to API ─────────────────────────────────────────────────────────────
API.expBar              = expBar
API.UpdateExpBar        = UpdateBar
API.ApplyExpBarSettings = ApplySettings

-- ── Register with Edit Layout ─────────────────────────────────────────────────
local expLayoutEvents = CreateFrame("Frame")
expLayoutEvents:RegisterEvent("PLAYER_LOGIN")
expLayoutEvents:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    C_Timer.After(0.3, function()
        if not API.RegisterLayoutHandles then return end
        API.RegisterLayoutHandles(function()
            local db = GetDB()
            if not db.expBarEnabled then return {} end
            return {
                {
                    label        = "Experience Bar",
                    iconTex      = "Interface\\Icons\\Spell_Nature_Astralrecal",
                    ox           = db.expBarX or 0,
                    oy           = db.expBarY or 38,
                    liveFrameRef = expBar,
                    saveCallback = function(nx, ny)
                        db.expBarX = nx
                        db.expBarY = ny
                        expBar:ClearAllPoints()
                        expBar:SetPoint("CENTER", UIParent, "CENTER", nx, ny)
                    end,
                    resizeCallback = function(nw, nh)
                        nw = math.max(100, math.floor(nw + 0.5))
                        nh = math.max(2,   math.floor(nh + 0.5))
                        db.expBarWidth  = nw
                        db.expBarHeight = nh
                        expBar:SetSize(nw, nh)
                        UpdateTicks()
                        if _G["CSExpBarWidthEdit"]  then _G["CSExpBarWidthEdit"]:SetText(tostring(nw))  end
                        if _G["CSExpBarHeightEdit"] then _G["CSExpBarHeightEdit"]:SetText(tostring(nh)) end
                    end,
                }
            }
        end)
    end)
end)

-- ── Quest XP debug ────────────────────────────────────────────────────────────
SLASH_MQOLQUESTDEBUG1 = "/qolquestdebug"
SlashCmdList["MQOLQUESTDEBUG"] = function()
    print("|cFFFFD700[MidnightQoL QuestXP Debug]|r ========================")
    if not C_QuestLog then print("  C_QuestLog: NIL"); return end

    local numEntries = (C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetNumQuestLogEntries()) or 0
    print(string.format("  Entries: %d  |  SetSelectedQuest: %s  |  GetQuestIDForLogIndex: %s  |  IsComplete: %s  |  ReadyForTurnIn: %s  |  GetQuestLogRewardXP: %s",
        numEntries,
        tostring(C_QuestLog.SetSelectedQuest ~= nil),
        tostring(C_QuestLog.GetQuestIDForLogIndex ~= nil),
        tostring(C_QuestLog.IsComplete ~= nil),
        tostring(C_QuestLog.ReadyForTurnIn ~= nil),
        tostring(GetQuestLogRewardXP ~= nil)))

    local prevSelected = C_QuestLog.GetSelectedQuest and C_QuestLog.GetSelectedQuest()
    local totalXP, numComplete = 0, 0

    for i = 1, numEntries do
        if C_QuestLog.SetSelectedQuest then C_QuestLog.SetSelectedQuest(i) end
        local questID = (C_QuestLog.GetQuestIDForLogIndex and C_QuestLog.GetQuestIDForLogIndex(i)) or 0
        if questID > 0 then
            local info = C_QuestLog.GetInfo and C_QuestLog.GetInfo(i)
            local title = (info and info.title) or "?"
            local xp = (GetQuestLogRewardXP and GetQuestLogRewardXP(questID)) or 0
            local isComplete  = C_QuestLog.IsComplete    and C_QuestLog.IsComplete(questID)
            local readyForTurnIn = C_QuestLog.ReadyForTurnIn and C_QuestLog.ReadyForTurnIn(questID)
            local complete = isComplete or readyForTurnIn
            local tag = complete and "|cFF00FF00[DONE]|r" or "[    ]"
            print(string.format("  %s i=%-3d qid=%-8d xp=%-6d IsComplete=%s ReadyForTurnIn=%s  %s",
                tag, i, questID, xp, tostring(isComplete), tostring(readyForTurnIn), title))
            if complete and xp > 0 then
                totalXP = totalXP + xp
                numComplete = numComplete + 1
            end
        end
    end

    if prevSelected and prevSelected > 0 and C_QuestLog.SetSelectedQuest then
        C_QuestLog.SetSelectedQuest(prevSelected)
    end

    print(string.format("  |cFFFFD700Summary: %d complete quests → %d pending XP|r", numComplete, totalXP))
    print("|cFFFFD700[MidnightQoL QuestXP Debug]|r ======================== done")
end
API.Debug("[MidnightQoL] ExperienceBar loaded.")
