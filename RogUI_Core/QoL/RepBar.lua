-- ============================================================
-- RogUI_QoL / RepBar.lua
-- Dedicated reputation bar styled to match the Experience bar.
-- Supports both Classic (GetWatchedFactionInfo) and
-- modern TWW/Dragonflight (C_Reputation.GetWatchedFactionData).
-- ============================================================

local API = RogUIAPI

-- ── Defaults ──────────────────────────────────────────────────────────────────
local DEFAULTS = {
    repBarEnabled   = false,
    repBarWidth     = 600,
    repBarHeight    = 10,
    repBarX         = 0,
    repBarY         = -322,
    repBarShowText  = true,
    repBarFillR     = 0.8, repBarFillG = 0.2, repBarFillB = 1.0,
    repBarBgR       = 0.0, repBarBgG   = 0.0, repBarBgB   = 0.0, repBarBgA = 0.55,
    repBarPendingR  = 1.0, repBarPendingG = 0.85, repBarPendingB = 0.0,
}

local function GetDB()
    if not RogUIDB then return DEFAULTS end
    for k, v in pairs(DEFAULTS) do
        if RogUIDB[k] == nil then RogUIDB[k] = v end
    end
    return RogUIDB
end

-- ── Reputation API compatibility shim ─────────────────────────────────────────
-- Returns: name, repMin, repMax, repValue, isRenown, renownLevel  OR  nil.
-- For standard factions: repMin/repMax are reaction thresholds, repValue is
-- current standing — the bar shows progress within the current rank.
-- For Renown (Major) factions: min=0, max=renownLevelThreshold,
-- value=renownReputationEarned (rep within current renown level).
local function GetWatchedFaction()
    -- Modern API (Dragonflight / TWW)
    if C_Reputation and C_Reputation.GetWatchedFactionData then
        local data = C_Reputation.GetWatchedFactionData()
        if data and data.name then
            -- Major/Renown factions (isMajorFaction == true) use a different data
            -- layout — currentReactionThreshold/nextReactionThreshold are both 0,
            -- and currentStanding is the raw cumulative rep, not rank-relative.
            -- Use C_MajorFactions to get per-level progress instead.
            if data.factionID and C_MajorFactions and C_MajorFactions.GetMajorFactionData then
                local ok, mf = pcall(C_MajorFactions.GetMajorFactionData, data.factionID)
                if ok and mf and mf.renownLevelThreshold and mf.renownLevelThreshold > 0 then
                    local lo  = 0
                    local hi  = mf.renownLevelThreshold
                    local val = mf.renownReputationEarned or 0
                    local lvl = mf.renownLevel or 0
                    return data.name, lo, hi, val, true, lvl
                end
            end
            -- Standard faction — use threshold-relative progress
            local lo  = data.currentReactionThreshold or 0
            local hi  = data.nextReactionThreshold    or 0
            local val = data.currentStanding          or 0
            -- Guard against degenerate data (hi == lo or hi == 0)
            if hi <= lo then
                -- Paragon or max-rank faction: treat as full
                return data.name, 0, 1, 1, false, nil
            end
            return data.name, lo, hi, val, false, nil
        end
        return nil
    end
    -- Classic / Wrath fallback
    if GetWatchedFactionInfo then
        local name, _, _, _, _, repMin, repMax, repValue = GetWatchedFactionInfo()
        if name then return name, repMin, repMax, repValue, false, nil end
    end
    return nil
end

-- ── Frame ─────────────────────────────────────────────────────────────────────
local repBar = CreateFrame("Frame", "RogUIRepBar", UIParent)
repBar:SetFrameStrata("MEDIUM")
repBar:SetFrameLevel(10)
repBar:SetClampedToScreen(true)

-- Background
local repBg = repBar:CreateTexture(nil, "BACKGROUND")
repBg:SetAllPoints()
repBg:SetColorTexture(0, 0, 0, 0.55)

-- Pending rep fill (gold, behind main fill)
local repPendingFill = repBar:CreateTexture(nil, "BORDER", nil, 1)
repPendingFill:SetPoint("TOPLEFT"); repPendingFill:SetPoint("BOTTOMLEFT")
repPendingFill:SetColorTexture(1.0, 0.85, 0.0, 0.55)
repPendingFill:SetWidth(1)
repPendingFill:Hide()

-- Main rep fill
local repFill = repBar:CreateTexture(nil, "ARTWORK")
repFill:SetPoint("TOPLEFT"); repFill:SetPoint("BOTTOMLEFT")
repFill:SetColorTexture(0.8, 0.2, 1.0, 1)
repFill:SetWidth(1)

-- Shine / gloss overlay
local repGloss = repBar:CreateTexture(nil, "OVERLAY")
repGloss:SetAllPoints()
repGloss:SetColorTexture(1, 1, 1, 0.04)

-- Thin top-edge highlight line
local repEdge = repBar:CreateTexture(nil, "OVERLAY")
repEdge:SetPoint("TOPLEFT",  repBar, "TOPLEFT",  0, 0)
repEdge:SetPoint("TOPRIGHT", repBar, "TOPRIGHT", 0, 0)
repEdge:SetHeight(1)
repEdge:SetColorTexture(1, 1, 1, 0.18)

-- ── 10% Tick marks ────────────────────────────────────────────────────────────
local NUM_TICKS = 9
local repTicks = {}
for i = 1, NUM_TICKS do
    local tick = repBar:CreateTexture(nil, "OVERLAY")
    tick:SetWidth(1)
    tick:SetColorTexture(1, 1, 1, 0.35)
    repTicks[i] = tick
end

local function UpdateTicks()
    local barW = repBar:GetWidth()
    for i = 1, NUM_TICKS do
        repTicks[i]:ClearAllPoints()
        local xPos = barW * (i / 10)
        repTicks[i]:SetPoint("TOP",    repBar, "TOPLEFT",    xPos, 0)
        repTicks[i]:SetPoint("BOTTOM", repBar, "BOTTOMLEFT", xPos, 0)
    end
end

-- ── Text frame (HIGH strata so it always draws over fills) ────────────────────
local repTextFrame = CreateFrame("Frame", nil, UIParent)
repTextFrame:SetAllPoints(repBar)
repTextFrame:SetFrameStrata("HIGH")
repTextFrame:SetFrameLevel(100)

local repText = repTextFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
repText:SetPoint("CENTER", repTextFrame, "CENTER", 0, 0)
repText:SetJustifyH("CENTER")
repText:SetTextColor(1, 1, 1, 1)
repText:SetFont(repText:GetFont(), 9, "OUTLINE")

-- ── Pending rep from completed quests ─────────────────────────────────────────
local function GetPendingRepXP()
    if not C_QuestLog then return 0, 0 end
    -- Bail if quest log is open — SetSelectedQuest taints it
    if QuestMapFrame and QuestMapFrame:IsShown() then return 0, 0 end
    if QuestLogFrame  and QuestLogFrame:IsShown()  then return 0, 0 end

    local watchedName, _, _, _, isRenown = GetWatchedFaction()
    if not watchedName or watchedName == "" then return 0, 0 end

    -- For renown/major factions, also grab the factionID for ID-based matching
    local watchedFactionID = nil
    if C_Reputation and C_Reputation.GetWatchedFactionData then
        local data = C_Reputation.GetWatchedFactionData()
        if data then watchedFactionID = data.factionID end
    end

    local totalRep, numQuests = 0, 0
    local numEntries = C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetNumQuestLogEntries() or 0

    for i = 1, numEntries do
        local info = C_QuestLog.GetInfo and C_QuestLog.GetInfo(i)
        if info and not info.isHeader and info.questID then
            local isComplete = C_QuestLog.IsComplete and C_QuestLog.IsComplete(info.questID)
            if isComplete then
                -- SetSelectedQuest is needed for GetNumQuestLogRewardFactions / GetQuestLogRewardFactionInfo
                local selectOk = true
                if C_QuestLog.SetSelectedQuest then
                    selectOk = pcall(C_QuestLog.SetSelectedQuest, i)
                end
                if selectOk then
                    local numFactions = GetNumQuestLogRewardFactions and GetNumQuestLogRewardFactions() or 0
                    for f = 1, numFactions do
                        local fname, rep, factionID = nil, 0, nil
                        -- Try modern signature first (returns factionID as 3rd value in TWW)
                        local ok, a, b, c = pcall(GetQuestLogRewardFactionInfo, f)
                        if ok then
                            fname    = a
                            rep      = b or 0
                            factionID = c  -- may be nil on older clients
                        end
                        if fname and rep and rep > 0 then
                            local matched = false
                            -- Prefer factionID match (works for renown where names may differ)
                            if factionID and watchedFactionID and factionID == watchedFactionID then
                                matched = true
                            elseif fname == watchedName then
                                matched = true
                            end
                            if matched then
                                totalRep  = totalRep + rep
                                numQuests = numQuests + 1
                                break
                            end
                        end
                    end
                end
            end
        end
    end

    -- Restore previous selection to avoid disrupting quest log state
    -- (we intentionally do NOT restore when quest log is open — we bailed at top)
    if C_QuestLog.SetSelectedQuest then
        pcall(C_QuestLog.SetSelectedQuest, 0)
    end

    return totalRep, numQuests
end

-- ── Apply settings ────────────────────────────────────────────────────────────
local function ApplyRepBarSettings()
    local db = GetDB()
    repBar:SetSize(db.repBarWidth, db.repBarHeight)
    repBar:ClearAllPoints()
    repBar:SetPoint("CENTER", UIParent, "CENTER", db.repBarX, db.repBarY)
    repFill:SetColorTexture(db.repBarFillR, db.repBarFillG, db.repBarFillB, 1)
    repBg:SetColorTexture(db.repBarBgR, db.repBarBgG, db.repBarBgB, db.repBarBgA)
    repPendingFill:SetColorTexture(db.repBarPendingR, db.repBarPendingG, db.repBarPendingB, 0.55)
    UpdateTicks()
end

-- ── Native bar suppression ────────────────────────────────────────────────────
local function HideNativeRepBar()
    if ReputationWatchBar        then ReputationWatchBar:SetAlpha(0) end
    if StatusTrackingBarManager  then StatusTrackingBarManager:SetAlpha(0) end
    for _, n in ipairs({ "ReputationWatchBar", "MainMenuBarRepFrame", "ReputationBar", "FactionWatchBar" }) do
        local f = _G[n]
        if f and f.SetAlpha then f:SetAlpha(0) end
    end
end

-- ── Core update ───────────────────────────────────────────────────────────────
local function UpdateRepBar()
    local db = GetDB()
    HideNativeRepBar()
    if not db.repBarEnabled then repBar:Hide(); return end

    local name, repMin, repMax, repValue, isRenown, renownLevel = GetWatchedFaction()
    if not name then repBar:Hide(); return end

    repBar:Show()
    ApplyRepBarSettings()

    local range = repMax - repMin
    local cur   = repValue - repMin
    local pct   = (range > 0) and (cur / range) or 0
    local barW  = repBar:GetWidth()

    repFill:SetWidth(math.max(1, barW * pct))

    local pendingRep, pendingCount = GetPendingRepXP()
    if pendingRep > 0 then
        local pendingPct = math.min(1, (cur + pendingRep) / range)
        repPendingFill:SetWidth(math.max(1, barW * pendingPct))
        repPendingFill:Show()
    else
        repPendingFill:SetWidth(1)
        repPendingFill:Hide()
    end

    if db.repBarShowText then
        local pctDisplay = math.floor(pct * 100 + 0.5)
        local displayName = isRenown and (name .. " (Renown " .. (renownLevel or 0) .. ")") or name
        local parts = { displayName .. "  " .. pctDisplay .. "%" }
        parts[#parts+1] = cur .. " / " .. range
        if pendingRep > 0 then
            local pendingLabel = isRenown and "renown" or "rep"
            parts[#parts+1] = "|cFFFFD700+" .. pendingRep .. " pending " .. pendingLabel .. " (" .. pendingCount .. "q)|r"
        end
        repText:SetText(table.concat(parts, "  ·  "))
        repText:Show()
    else
        repText:Hide()
    end
end

-- ── Tooltip ───────────────────────────────────────────────────────────────────
repBar:EnableMouse(true)
repBar:SetScript("OnEnter", function()
    local name, repMin, repMax, repValue, isRenown, renownLevel = GetWatchedFaction()
    if not name then return end
    local range  = repMax - repMin
    local cur    = repValue - repMin
    local pct    = (range > 0) and math.floor(cur / range * 1000 + 0.5) / 10 or 0
    local needed = range - cur

    GameTooltip:SetOwner(repBar, "ANCHOR_TOP")
    GameTooltip:ClearLines()
    local displayName = isRenown and (name .. " — Renown " .. (renownLevel or 0)) or name
    GameTooltip:AddLine(displayName, 0.8, 0.2, 1.0)
    GameTooltip:AddLine(cur .. " / " .. range .. "  (" .. pct .. "%)", 1, 1, 1)
    if isRenown then
        GameTooltip:AddLine(needed .. " rep to Renown " .. ((renownLevel or 0) + 1), 0.8, 0.8, 0.8)
    else
        GameTooltip:AddLine(needed .. " rep to next rank", 0.8, 0.8, 0.8)
    end

    local pendingRep, pendingCount = GetPendingRepXP()
    if pendingRep > 0 then
        local pendingLabel = isRenown and "renown" or "rep"
        local rankUpMsg    = isRenown and "Turning in would |cFF00FF00increase your Renown!|r" or "Turning in would |cFF00FF00rank you up!|r"
        GameTooltip:AddLine(" ", 1, 1, 1)
        GameTooltip:AddLine("Completed quests ready to turn in:", 1, 0.85, 0)
        GameTooltip:AddLine(pendingCount .. " quest" .. (pendingCount==1 and "" or "s") ..
            "  →  +" .. pendingRep .. " " .. pendingLabel, 1, 1, 0.6)
        if (cur + pendingRep) >= range then
            GameTooltip:AddLine(rankUpMsg, 0.9, 0.9, 0.9)
        end
    end
    GameTooltip:Show()
end)
repBar:SetScript("OnLeave", function() GameTooltip:Hide() end)

-- ── Drag (layout mode only) ───────────────────────────────────────────────────
repBar:SetMovable(true)
repBar:RegisterForDrag("LeftButton")
repBar:SetScript("OnDragStart", function(self)
    if not (API.IsLayoutMode and API.IsLayoutMode()) then return end
    self:StartMoving()
end)
repBar:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local db = GetDB()
    local cx = UIParent:GetWidth()  / 2
    local cy = UIParent:GetHeight() / 2
    local fx = self:GetLeft() + self:GetWidth()  / 2
    local fy = self:GetBottom() + self:GetHeight() / 2
    db.repBarX = math.floor(fx - cx + 0.5)
    db.repBarY = math.floor(fy - cy + 0.5)
    self:ClearAllPoints()
    self:SetPoint("CENTER", UIParent, "CENTER", db.repBarX, db.repBarY)
end)

-- ── Events ────────────────────────────────────────────────────────────────────
local repEvents = CreateFrame("Frame")
repEvents:RegisterEvent("PLAYER_LOGIN")
repEvents:RegisterEvent("UPDATE_FACTION")
repEvents:RegisterEvent("QUEST_LOG_UPDATE")
repEvents:RegisterEvent("CHAT_MSG_COMBAT_FACTION_CHANGE")

repEvents:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        C_Timer.After(0.5, function()
            HideNativeRepBar()
            UpdateRepBar()
        end)
    else
        UpdateRepBar()
    end
end)

-- ── Expose ────────────────────────────────────────────────────────────────────
API.repBar               = repBar
API.UpdateRepBar         = UpdateRepBar
API.ApplyRepBarSettings  = ApplyRepBarSettings

-- ── Register with Edit Layout ─────────────────────────────────────────────────
local repLayoutEvents = CreateFrame("Frame")
repLayoutEvents:RegisterEvent("PLAYER_LOGIN")
repLayoutEvents:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    C_Timer.After(0.6, function()
        if not API.RegisterLayoutHandles then return end
        API.RegisterLayoutHandles(function()
            local db = GetDB()
            if not db.repBarEnabled then return {} end
            return {
                {
                    label        = "Reputation Bar",
                    iconTex      = "Interface\\Icons\\Achievement_Reputation_01",
                    ox           = db.repBarX or 0,
                    oy           = db.repBarY or -322,
                    liveFrameRef = repBar,
                    saveCallback = function(nx, ny)
                        db.repBarX = nx; db.repBarY = ny
                        repBar:ClearAllPoints()
                        repBar:SetPoint("CENTER", UIParent, "CENTER", nx, ny)
                    end,
                    resizeCallback = function(nw, nh)
                        nw = math.max(100, math.floor(nw+0.5))
                        nh = math.max(2,   math.floor(nh+0.5))
                        db.repBarWidth = nw; db.repBarHeight = nh
                        repBar:SetSize(nw, nh)
                        UpdateTicks()
                        if _G["CSRepBarWidthEdit"]  then _G["CSRepBarWidthEdit"]:SetText(tostring(nw))  end
                        if _G["CSRepBarHeightEdit"] then _G["CSRepBarHeightEdit"]:SetText(tostring(nh)) end
                    end,
                }
            }
        end)
    end)
end)

API.Debug("[RogUI] RepBar loaded.")
