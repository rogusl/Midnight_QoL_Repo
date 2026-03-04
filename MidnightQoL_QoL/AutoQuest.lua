-- ============================================================
-- MidnightQoL_QoL / AutoQuest.lua
-- Automatically accepts and turns in quests when enabled.
-- Settings are toggled via the General tab in the UI.
-- ============================================================

local API = MidnightQoLAPI

local function GetDB()
    return BuffAlertDB
end

-- ── Quest Frame event hooks ───────────────────────────────────────────────────

-- Auto Accept: fires when a quest greeting/detail frame opens
local function OnQuestDetailShow()
    local db = GetDB()
    if not db or not db.autoQuestAccept then return end
    -- QuestDetailFrame = individual quest detail (Accept button)
    -- Only auto-accept if there's no item reward choice (or it's trivial)
    if QuestFrame and QuestFrameAcceptButton and QuestFrameAcceptButton:IsShown() then
        local numChoices = GetNumQuestChoices and GetNumQuestChoices() or 0
        if numChoices <= 1 then
            API.Debug("[AutoQuest] Auto-accepting quest.")
            AcceptQuest()
        else
            API.Debug("[AutoQuest] Skipping auto-accept: " .. numChoices .. " reward choices require player input.")
        end
    end
end

-- Auto Accept from NPC greeting (multi-quest list from one NPC)
local function OnQuestGreetingShow()
    local db = GetDB()
    if not db or not db.autoQuestAccept then return end
    -- Greeting lists available quests AND completable quests.
    -- We auto-select available (new) quests. Completable quests go to OnQuestProgressShow.
    local numActive    = GetNumActiveQuests()
    local numAvailable = GetNumAvailableQuests()
    API.Debug("[AutoQuest] Greeting: " .. numAvailable .. " available, " .. numActive .. " active.")
    -- If there's only one available quest and no active (turn-in) quests, auto-select it.
    if numAvailable == 1 and numActive == 0 then
        SelectAvailableQuest(1)
    end
end

-- Auto Turn In: fires when a quest progress/reward frame opens showing completion
local function OnQuestProgressShow()
    local db = GetDB()
    if not db or not db.autoQuestTurnIn then return end
    if IsQuestCompletable and IsQuestCompletable() then
        local numChoices = GetNumQuestChoices and GetNumQuestChoices() or 0
        if numChoices >= 2 then
            API.Debug("[AutoQuest] Skipping auto-complete: " .. numChoices .. " reward choices — player must choose.")
            return  -- Leave the frame open for the player to pick their reward
        end
        API.Debug("[AutoQuest] Auto-completing quest turn-in.")
        CompleteQuest()
    end
end

-- After CompleteQuest(), the reward frame shows. Auto-get the reward only if no choices.
local function OnQuestRewardShow()
    local db = GetDB()
    if not db or not db.autoQuestTurnIn then return end
    local numChoices = GetNumQuestChoices and GetNumQuestChoices() or 0
    if numChoices >= 2 then
        -- Multiple reward choices — leave the frame open, player must pick
        API.Debug("[AutoQuest] Reward frame open: " .. numChoices .. " choices require player input. Not auto-completing.")
        return
    end
    API.Debug("[AutoQuest] Auto-getting quest reward.")
    -- Small delay to let the frame fully render
    C_Timer.After(0.05, function()
        if QuestFrameCompleteQuestButton and QuestFrameCompleteQuestButton:IsShown() then
            QuestFrameCompleteQuestButton:Click()
        end
    end)
end

-- ── Hook into quest frames ────────────────────────────────────────────────────
local function SetupHooks()
    if QuestFrame then
        -- Classic / Retail quest frames
        QuestFrame:HookScript("OnShow", function()
            -- Determine which panel is active
            if QuestDetailFrame and QuestDetailFrame:IsShown() then
                OnQuestDetailShow()
            elseif QuestGreetingFrame and QuestGreetingFrame:IsShown() then
                OnQuestGreetingShow()
            elseif QuestProgressFrame and QuestProgressFrame:IsShown() then
                OnQuestProgressShow()
            elseif QuestRewardFrame and QuestRewardFrame:IsShown() then
                OnQuestRewardShow()
            end
        end)
    end

    -- Also hook individual sub-frames for reliability
    if QuestDetailFrame then
        QuestDetailFrame:HookScript("OnShow", OnQuestDetailShow)
    end
    if QuestGreetingFrame then
        QuestGreetingFrame:HookScript("OnShow", OnQuestGreetingShow)
    end
    if QuestProgressFrame then
        QuestProgressFrame:HookScript("OnShow", OnQuestProgressShow)
    end
    if QuestRewardFrame then
        QuestRewardFrame:HookScript("OnShow", OnQuestRewardShow)
    end
end

-- ── Gossip auto-progress ─────────────────────────────────────────────────────
-- Some quests use the gossip frame instead of QuestFrame.
-- Hook GOSSIP_SHOW to auto-select the only available option when appropriate.
local gossipEvents = CreateFrame("Frame")
gossipEvents:RegisterEvent("GOSSIP_SHOW")
gossipEvents:RegisterEvent("QUEST_DETAIL")
gossipEvents:RegisterEvent("QUEST_PROGRESS")
gossipEvents:RegisterEvent("QUEST_COMPLETE")

gossipEvents:SetScript("OnEvent", function(self, event)
    if event == "QUEST_DETAIL" then
        OnQuestDetailShow()
    elseif event == "QUEST_PROGRESS" then
        OnQuestProgressShow()
    elseif event == "QUEST_COMPLETE" then
        OnQuestRewardShow()
    elseif event == "GOSSIP_SHOW" then
        local db = GetDB()
        if not db or not db.autoQuestAccept then return end
        -- If the gossip frame only has one option and it's quest-related, auto-select
        -- (be conservative — only act if there's exactly one option total)
        local numOptions = C_GossipInfo and #(C_GossipInfo.GetOptions() or {}) or 0
        local numQuests  = C_GossipInfo and #(C_GossipInfo.GetAvailableQuests() or {}) or 0
        if numOptions == 0 and numQuests == 1 then
            local q = C_GossipInfo.GetAvailableQuests()[1]
            if q then
                API.Debug("[AutoQuest] Gossip auto-selecting single quest: " .. tostring(q.title))
                C_GossipInfo.SelectAvailableQuest(q.questID)
            end
        end
    end
end)

-- ── Initialise after PLAYER_LOGIN ────────────────────────────────────────────
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        C_Timer.After(0.5, SetupHooks)
        self:UnregisterEvent("PLAYER_LOGIN")
    end
end)

API.Debug("[MidnightQoL] AutoQuest loaded.")
