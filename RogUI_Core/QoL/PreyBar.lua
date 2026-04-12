-- ============================================================
-- RogUI_QoL / PreyBar.lua
-- Prey Hunt progress bar.
--
-- Data sourced the same way as the Preydator addon:
--   1. C_UIWidgetManager.GetPreyHuntProgressWidgetVisualizationInfo()
--      — primary source; gives progressState (1-3) and a percent
--        we extract from the widget's numeric fields / tooltip.
--   2. C_QuestLog.GetQuestObjectives() + GetQuestProgressBarPercent()
--      — fallback when the widget isn't visible yet.
--
-- Stage mapping (from Preydator source):
--   progressState nil / 0  → stage 1  (Scent)
--   progressState 1        → stage 2  (Blood)
--   progressState 2        → stage 3  (Echoes)
--   progressState 3        → stage 4  (Feast / complete)
--
-- Visibility: shown only while a prey quest is active and enabled.
-- Alpha: dimmed 50% out of combat via RegisterStateDriver (taint-free).
-- Position: draggable in Layout Mode; saved to RogUIDB.preyBarX/Y.
-- ============================================================

local API = RogUIAPI

-- ── Constants ────────────────────────────────────────────────────────────────
local PREY_WIDGET_TYPE  = 31   -- Enum.UIWidgetVisualizationType.PreyHuntProgress
local WIDGET_SHOWN      = 1    -- Enum.WidgetShownState.Shown
local POLL_INTERVAL     = 0.5  -- seconds between OnUpdate polls
local FILL_INSET        = 2

local STAGE_LABELS = {
    [1] = "Scent in the Wind",
    [2] = "Blood in the Shadows",
    [3] = "Echoes of the Kill",
    [4] = "Feast of the Fang",
}
-- progressState value → stage index
local STATE_TO_STAGE = { [0]=1, [1]=2, [2]=3, [3]=4 }

-- Tick positions as fractions of bar width (thirds, matching Preydator default)
local TICK_PCTS = { 0.333, 0.667 }

-- ── DB helpers ───────────────────────────────────────────────────────────────
local function GetDB()
    if not RogUIDB then return {} end
    if RogUIDB.preyBarEnabled == nil then RogUIDB.preyBarEnabled = false end
    return RogUIDB
end

-- ── Frame construction ───────────────────────────────────────────────────────
-- Plain frame — no SecureHandlerStateTemplate so Show/Hide/SetPoint are never
-- combat-protected. Alpha dimming is handled via PLAYER_REGEN events instead.
local preyBar = CreateFrame("Frame", "RogUIPreyBar", UIParent)
preyBar:SetSize(220, 22)
preyBar:SetFrameStrata("MEDIUM")
preyBar:SetClampedToScreen(true)
preyBar:SetMovable(true)
preyBar:EnableMouse(true)
preyBar:RegisterForDrag("LeftButton")
preyBar:SetScript("OnDragStart", function(self)
    if API.IsLayoutMode and API.IsLayoutMode() and not InCombatLockdown() then
        self:StartMoving()
    end
end)
preyBar:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    if RogUIDB then
        RogUIDB.preyBarX = math.floor(self:GetLeft() + self:GetWidth()/2  - UIParent:GetWidth()/2  + 0.5)
        RogUIDB.preyBarY = math.floor(self:GetTop()  - self:GetHeight()/2 - UIParent:GetHeight()/2 + 0.5)
    end
end)
preyBar:Hide()

-- Background
local preyBg = preyBar:CreateTexture(nil, "BACKGROUND")
preyBg:SetPoint("TOPLEFT",     preyBar, "TOPLEFT",     FILL_INSET, -FILL_INSET)
preyBg:SetPoint("BOTTOMRIGHT", preyBar, "BOTTOMRIGHT", -FILL_INSET, FILL_INSET)
preyBg:SetColorTexture(0, 0, 0, 0.65)

-- Fill bar
local preyFill = preyBar:CreateTexture(nil, "ARTWORK")
preyFill:SetPoint("TOPLEFT",    preyBar, "TOPLEFT",    FILL_INSET, -FILL_INSET)
preyFill:SetPoint("BOTTOMLEFT", preyBar, "BOTTOMLEFT", FILL_INSET,  FILL_INSET)
preyFill:SetTexture("Interface\\TargetingFrame\\UI-StatusBar")
preyFill:SetVertexColor(0.85, 0.2, 0.2, 0.95)
preyFill:SetWidth(1)

-- Tick marks (2 lines at thirds)
local preyTicks = {}
for i = 1, 2 do
    local t = preyBar:CreateTexture(nil, "OVERLAY")
    t:SetSize(1, preyBar:GetHeight() - FILL_INSET * 2)
    t:SetColorTexture(1, 1, 1, 0.4)
    t:Hide()
    preyTicks[i] = t
end

-- Stage label (above bar)
local preyLabel = preyBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
preyLabel:SetPoint("BOTTOM", preyBar, "TOP", 0, 3)
preyLabel:SetTextColor(1, 0.82, 0, 1)
preyLabel:SetText("")

-- Percent text (centred inside bar)
local preyPct = preyBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
preyPct:SetPoint("CENTER", preyBar, "CENTER", 0, 0)
preyPct:SetFont(preyPct:GetFont(), 10, "OUTLINE")
preyPct:SetTextColor(1, 1, 1, 1)
preyPct:SetText("")

-- Thin border
local preyBorder = CreateFrame("Frame", nil, preyBar, "BackdropTemplate")
preyBorder:SetAllPoints()
preyBorder:SetBackdropBorderTexture("Interface/Buttons/WHITE8x8")
    preyBorder:SetBackdropBorderSizeZ(1)
preyBorder:SetBackdropBorderColor(0.6, 0.15, 0.15, 0.9)

-- Start dimmed; PLAYER_REGEN events will set full/dim alpha
preyBar:SetAlpha(0.5)

-- ── Data extraction helpers (from Preydator) ─────────────────────────────────
local function ClampPct(v)
    return math.max(0, math.min(100, v or 0))
end

local function GetPreyWidgetTypeID()
    if Enum and Enum.UIWidgetVisualizationType and Enum.UIWidgetVisualizationType.PreyHuntProgress then
        return Enum.UIWidgetVisualizationType.PreyHuntProgress
    end
    return PREY_WIDGET_TYPE
end

local function GetShownStateID()
    if Enum and Enum.WidgetShownState and Enum.WidgetShownState.Shown then
        return Enum.WidgetShownState.Shown
    end
    return WIDGET_SHOWN
end

-- Scan candidate widget sets for a PreyHuntProgress widget.
-- Returns progressState, percentOrNil.
local function FindPreyWidget()
    if not (C_UIWidgetManager
        and C_UIWidgetManager.GetAllWidgetsBySetID
        and C_UIWidgetManager.GetPreyHuntProgressWidgetVisualizationInfo) then
        return nil, nil
    end

    local preyType  = GetPreyWidgetTypeID()
    local shownID   = GetShownStateID()

    local setGetters = {
        C_UIWidgetManager.GetTopCenterWidgetSetID,
        C_UIWidgetManager.GetObjectiveTrackerWidgetSetID,
        C_UIWidgetManager.GetBelowMinimapWidgetSetID,
        C_UIWidgetManager.GetPowerBarWidgetSetID,
    }

    for _, getter in ipairs(setGetters) do
        if getter then
            local setID = getter()
            if setID then
                local widgets = C_UIWidgetManager.GetAllWidgetsBySetID(setID)
                if widgets then
                    for _, w in ipairs(widgets) do
                        if w and w.widgetType == preyType then
                            local info = C_UIWidgetManager.GetPreyHuntProgressWidgetVisualizationInfo(w.widgetID)
                            if info and info.shownState == shownID then
                                -- Extract percent from known field names (Preydator's approach)
                                local pct = nil
                                for _, field in ipairs({"progressPercentage","progressPercent",
                                        "fillPercentage","percentage","percent","progress"}) do
                                    local v = tonumber(info[field])
                                    if v and v >= 0 and v <= 100 then pct = ClampPct(v); break end
                                end
                                -- value/max fallback
                                if not pct then
                                    local cur = tonumber(info.barValue or info.value or info.currentValue)
                                    local max = tonumber(info.barMax  or info.maxValue or info.total or info.max)
                                    if cur and max and max > 0 then
                                        pct = ClampPct((cur / max) * 100)
                                    end
                                end
                                -- tooltip percent fallback
                                if not pct and type(info.tooltip) == "string" then
                                    local n = info.tooltip:match("(%d+)%s*%%")
                                    if n then pct = ClampPct(tonumber(n)) end
                                end
                                return info.progressState, pct
                            end
                        end
                    end
                end
            end
        end
    end
    return nil, nil
end

-- Fallback: read from quest objectives / quest bar percent
local function GetQuestObjectivePct(questID)
    if not questID then return nil end
    local barPct = GetQuestProgressBarPercent and tonumber(GetQuestProgressBarPercent(questID))
    if barPct then barPct = ClampPct(barPct) end

    if not (C_QuestLog and C_QuestLog.GetQuestObjectives) then return barPct end
    local objs = C_QuestLog.GetQuestObjectives(questID)
    if type(objs) ~= "table" or #objs == 0 then return barPct end

    local totalFul, totalReq = 0, 0
    for _, obj in ipairs(objs) do
        if type(obj) == "table" then
            local f = tonumber(obj.numFulfilled or obj.fulfilled)
            local r = tonumber(obj.numRequired  or obj.required)
            if f and r and r > 0 then
                totalFul = totalFul + math.max(0, f)
                totalReq = totalReq + math.max(0, r)
            else
                -- text pattern "X / Y"
                local text = obj.text
                if type(text) == "string" then
                    local cf, cr = text:match("(%d+)%s*/%s*(%d+)")
                    cf, cr = tonumber(cf), tonumber(cr)
                    if cf and cr and cr > 0 then
                        totalFul = totalFul + cf; totalReq = totalReq + cr
                    end
                end
            end
        end
    end

    local objPct = (totalReq > 0) and ClampPct((totalFul / totalReq) * 100) or nil
    if objPct and barPct then return math.max(objPct, barPct) end
    return objPct or barPct
end

-- ── Display update ────────────────────────────────────────────────────────────
local function UpdatePreyBar()
    local db = GetDB()
    if not db.preyBarEnabled then
        if not InCombatLockdown() then preyBar:Hide() end
        return
    end

    -- Require an active prey quest
    local questID = C_QuestLog and C_QuestLog.GetActivePreyQuest and C_QuestLog.GetActivePreyQuest()
    if not questID or questID == 0 then
        if not InCombatLockdown() then preyBar:Hide() end
        return
    end

    -- Position restore (OOC only — SetPoint is not protected but be safe)
    if not preyBar:IsShown() then
        if InCombatLockdown() then return end
        local cx = (db.preyBarX or 0)
        local cy = (db.preyBarY or 180)
        preyBar:ClearAllPoints()
        preyBar:SetPoint("CENTER", UIParent, "CENTER", cx, cy)
        preyBar:SetAlpha(0.5)
        preyBar:Show()
    end

    -- Gather data
    local progressState, pct = FindPreyWidget()

    -- If the widget gave us a progressState but no percent, derive from state.
    -- progressState 3 = PREY_PROGRESS_FINAL → always 100%.
    -- Never fall back to quest objectives when we have a widget state — objectives
    -- reflect the weekly hunt counter (e.g. 1/2 hunts) not the current hunt progress.
    if progressState == 3 then
        pct = 100
    elseif not pct then
        if progressState ~= nil then
            -- Widget is present but percent unknown — use stage-based fallback
            -- (0→0%, 1→33%, 2→66%) rather than the quest objective counter.
            local stagePcts = { [0]=0, [1]=33, [2]=66, [3]=100 }
            pct = stagePcts[progressState] or 0
        else
            -- No widget at all — only then use quest objective percent
            pct = GetQuestObjectivePct(questID) or 0
        end
    end

    -- Stage
    local stage = STATE_TO_STAGE[progressState] or STATE_TO_STAGE[0]
    if pct >= 100 then stage = 4 end

    -- Fill width
    local innerW = preyBar:GetWidth() - FILL_INSET * 2
    local fillW  = math.max(1, math.floor(innerW * (pct / 100) + 0.5))
    preyFill:SetWidth(fillW)

    -- Tick positions
    for i, frac in ipairs(TICK_PCTS) do
        local t = preyTicks[i]
        local tx = FILL_INSET + math.floor(innerW * frac + 0.5)
        t:SetHeight(preyBar:GetHeight() - FILL_INSET * 2)
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", preyBar, "TOPLEFT", tx, -FILL_INSET)
        t:Show()
    end

    -- Labels
    preyLabel:SetText(STAGE_LABELS[stage] or "")
    preyPct:SetText(string.format("%d%%", math.floor(pct + 0.5)))
end

-- ── Visibility (OOC only) ─────────────────────────────────────────────────────
local function UpdatePreyVisibility()
    if InCombatLockdown() then return end
    local db = GetDB()
    if not db.preyBarEnabled then preyBar:Hide(); return end
    local questID = C_QuestLog and C_QuestLog.GetActivePreyQuest and C_QuestLog.GetActivePreyQuest()
    if not questID or questID == 0 then preyBar:Hide(); return end
    preyBar:SetAlpha(0.5)  -- OOC = dimmed
    preyBar:Show()
    UpdatePreyBar()
end

-- ── Events ────────────────────────────────────────────────────────────────────
local preyEvents = CreateFrame("Frame")
preyEvents:RegisterEvent("PLAYER_ENTERING_WORLD")
preyEvents:RegisterEvent("PLAYER_REGEN_DISABLED")  -- entering combat → full alpha
preyEvents:RegisterEvent("PLAYER_REGEN_ENABLED")   -- leaving combat → dim + visibility check
preyEvents:RegisterEvent("QUEST_LOG_UPDATE")
preyEvents:RegisterEvent("UPDATE_ALL_UI_WIDGETS")
preyEvents:RegisterEvent("UPDATE_UI_WIDGET")
preyEvents:RegisterEvent("QUEST_TURNED_IN")
preyEvents:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_ENTERING_WORLD" then
        local db = GetDB()
        local w = db.preyBarW or 220
        local h = db.preyBarH or 22
        preyBar:SetSize(math.max(100, w), math.max(8, h))
        UpdatePreyVisibility()
    elseif event == "PLAYER_REGEN_DISABLED" then
        -- Entering combat: brighten to full alpha if shown
        if preyBar:IsShown() then preyBar:SetAlpha(1.0) end
    elseif event == "PLAYER_REGEN_ENABLED" then
        -- Leaving combat: run visibility check (safe now), then dim
        UpdatePreyVisibility()
        if preyBar:IsShown() then preyBar:SetAlpha(0.5) end
    else
        UpdatePreyBar()
    end
end)

-- OnUpdate poll (matches Preydator's 0.5s interval)
local elapsed = 0
preyEvents:SetScript("OnUpdate", function(_, dt)
    elapsed = elapsed + dt
    if elapsed < POLL_INTERVAL then return end
    elapsed = 0
    UpdatePreyBar()
end)

-- ── API surface ───────────────────────────────────────────────────────────────
API.UpdatePreyBar = UpdatePreyBar

-- ── Layout handle ─────────────────────────────────────────────────────────────
API.RegisterLayoutHandles(function()
    local db = GetDB()
    if not db.preyBarEnabled then return {} end

    -- Force visible with preview data
    preyBar:ClearAllPoints()
    local cx = db.preyBarX or 0
    local cy = db.preyBarY or 180
    preyBar:SetPoint("CENTER", UIParent, "CENTER", cx, cy)
    preyBar:Show()
    preyLabel:SetText(STAGE_LABELS[2])
    preyPct:SetText("45%")
    preyFill:SetWidth(math.floor((preyBar:GetWidth() - FILL_INSET*2) * 0.45 + 0.5))
    for i, frac in ipairs(TICK_PCTS) do
        local t = preyTicks[i]
        local tx = FILL_INSET + math.floor((preyBar:GetWidth() - FILL_INSET*2) * frac + 0.5)
        t:SetHeight(preyBar:GetHeight() - FILL_INSET*2)
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", preyBar, "TOPLEFT", tx, -FILL_INSET)
        t:Show()
    end

    return {{
        label        = "Prey Bar",
        iconTex      = "Interface\\Icons\\Achievement_Zone_Ardenweald_01",
        ox           = cx, oy = cy,
        liveFrameRef = preyBar,
        saveCallback = function(nx, ny)
            if RogUIDB then RogUIDB.preyBarX = nx; RogUIDB.preyBarY = ny end
            preyBar:ClearAllPoints()
            preyBar:SetPoint("CENTER", UIParent, "CENTER", nx, ny)
        end,
        resizeCallback = function(nw, nh)
            nw = math.max(100, math.floor(nw + 0.5))
            nh = math.max(8,   math.floor(nh + 0.5))
            preyBar:SetSize(nw, nh)
            if RogUIDB then RogUIDB.preyBarW = nw; RogUIDB.preyBarH = nh end
        end,
    }}
end)

API.Debug("[RogUI] PreyBar loaded.")
