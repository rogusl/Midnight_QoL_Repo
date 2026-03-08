-- ============================================================
-- MidnightQoL_QoL / WoWSettings.lua
--
-- Saves a snapshot of Blizzard settings that silently reset
-- on new characters and re-applies them on every login.
--
-- ALL settings here are confirmed CVars from the Blizzard
-- game client (sourced from KethoDoc / BlizzardInterfaceResources).
--
-- Gameplay
--   autoLootDefault           (false=account, true=char)
--   interactOnLeftClick       (account)
--   INTERACTTARGET keybind
--
-- Gameplay Enhancements  (Options > Gameplay Enhancements)
--   cooldownViewerEnabled     (char)  — Cooldown Manager
--   damageMeterEnabled        (char)  — Damage Meter
--   NOTE: "External Defensives" is a Midnight (12.x) feature
--         and does not exist as a CVar in TWW.
--
-- Raid Frames
--   raidFrameShowPowerBar         (account)
--   raidFrameShowClassColor       (account)
--   raidFrameShowOnlyDispellableDebuffs (account)
--
-- Action Bars
--   multiBarBottomLeft/Right, multiBarRight/Left, multiBar5/6/7
--
-- Edit Mode
--   C_EditMode.GetLayouts() / SaveLayouts() — copies the active
--   layout to every character by saving and re-applying the
--   layout data on login.
-- ============================================================

local API = MidnightQoLAPI

-- ── DB ────────────────────────────────────────────────────────────────────────
local function GetDB()
    if not BuffAlertDB then return nil end
    BuffAlertDB.wowSettings = BuffAlertDB.wowSettings or {}
    return BuffAlertDB.wowSettings
end

-- ── CVar table ────────────────────────────────────────────────────────────────
-- { key=db key, cvar=CVar name, label=display label, section=section header }
local CVAR_DEFS = {
    -- Gameplay
    { key="autoLoot",           cvar="autoLootDefault",                        label="Auto Loot",                        section="Gameplay"              },
    { key="leftClickInteract",  cvar="interactOnLeftClick",                    label="Interact on Left Click",           section="Gameplay"              },
    -- Gameplay Enhancements
    { key="cooldownViewer",     cvar="cooldownViewerEnabled",                  label="Cooldown Manager",                 section="Gameplay Enhancements" },
    { key="damageMeter",        cvar="damageMeterEnabled",                     label="Damage Meter",                     section="Gameplay Enhancements" },
    -- Raid Frames
    { key="rfPowerBar",         cvar="raidFrameShowPowerBar",                  label="Display Power Bars",               section="Raid Frames"           },
    { key="rfClassColor",       cvar="raidFrameShowClassColor",                label="Use Class Colors",                  section="Raid Frames"           },
    { key="rfDispellable",      cvar="raidFrameShowOnlyDispellableDebuffs",    label="Only Dispellable Debuffs",          section="Raid Frames"           },
    -- Action Bars
    { key="bar2",  cvar="multiBarBottomLeft",   label="Bar 2 (Bottom Left)",   section="Action Bars" },
    { key="bar3",  cvar="multiBarBottomRight",  label="Bar 3 (Bottom Right)",  section="Action Bars" },
    { key="bar4",  cvar="multiBarRight",        label="Bar 4 (Right 1)",       section="Action Bars" },
    { key="bar5",  cvar="multiBarLeft",         label="Bar 5 (Right 2)",       section="Action Bars" },
    { key="bar6",  cvar="multiBar5",            label="Bar 6",                 section="Action Bars" },
    { key="bar7",  cvar="multiBar6",            label="Bar 7",                 section="Action Bars" },
    { key="bar8",  cvar="multiBar7",            label="Bar 8",                 section="Action Bars" },
}

local INTERACT_BINDING = "INTERACTTARGET"

-- ── Edit Mode helpers ─────────────────────────────────────────────────────────
-- We save a deep copy of the active layout's systems table from
-- C_EditMode.GetLayouts(), then restore it via C_EditMode.SaveLayouts()
-- on every login. This is character-specific per Blizzard's architecture but
-- SaveLayouts accepts a full layoutInfo table so we can push it on each char.

local function DeepCopy(t)
    if type(t) ~= "table" then return t end
    local copy = {}
    for k, v in pairs(t) do copy[k] = DeepCopy(v) end
    return copy
end

local function CaptureEditModeLayout()
    if not C_EditMode or not C_EditMode.GetLayouts then return false end
    local db = GetDB(); if not db then return false end
    local info = C_EditMode.GetLayouts()
    if not info or not info.layouts then return false end
    local idx = info.activeLayout or 1
    local layout = info.layouts[idx]
    if not layout then return false end
    db.editModeLayout = DeepCopy(layout)
    db.editModeLayoutName = layout.layoutName or ("Layout " .. idx)
    return true
end

local function ApplyEditModeLayout(silent)
    local db = GetDB()
    if not db or not db.editModeLayout then return end
    if not C_EditMode or not C_EditMode.GetLayouts or not C_EditMode.SaveLayouts then return end

    -- Get current layouts, replace the Default (index 1) with our saved layout,
    -- then save. We always target index 1 (Default) so we don't trash custom layouts.
    local info = C_EditMode.GetLayouts()
    if not info or not info.layouts then return end

    -- Find or use the Default layout slot (index 1 is always Default)
    local saved = DeepCopy(db.editModeLayout)
    saved.layoutName = info.layouts[1] and info.layouts[1].layoutName or saved.layoutName

    info.layouts[1] = saved
    info.activeLayout = 1

    C_EditMode.SaveLayouts(info)
    C_EditMode.SetActiveLayout(1)

    if not silent then
        print("|cFF00CCFF[MidnightQoL]|r Edit Mode layout applied.")
    end
end

-- ── Capture ───────────────────────────────────────────────────────────────────
local function CaptureSettings()
    local db = GetDB()
    if not db then
        print("|cFFFF4444[MidnightQoL]|r Defaults: database not ready.")
        return
    end

    for _, def in ipairs(CVAR_DEFS) do
        db[def.key] = GetCVar(def.cvar)
    end

    db.interactKey = GetBindingKey(INTERACT_BINDING) or ""

    local editOk = CaptureEditModeLayout()

    db.savedAt = date("%Y-%m-%d %H:%M")
    local editMsg = editOk and "  |cFFAAAAAA(Edit Mode layout included)|r" or ""
    print("|cFF00CCFF[MidnightQoL]|r WoW settings snapshot saved  |cFFAAAAAA(" .. db.savedAt .. ")|r" .. editMsg)
end

API.CaptureWoWSettings = CaptureSettings

-- ── Apply ─────────────────────────────────────────────────────────────────────
local function ApplySettings(silent)
    local db = GetDB()
    if not db or not db.savedAt then return end

    local count = 0
    for _, def in ipairs(CVAR_DEFS) do
        if db[def.key] ~= nil then
            SetCVar(def.cvar, db[def.key])
            count = count + 1
        end
    end

    if db.interactKey and db.interactKey ~= "" then
        SetBinding(db.interactKey, INTERACT_BINDING)
        SaveBindings(GetCurrentBindingSet())
        count = count + 1
    end

    if CompactRaidFrameManager_UpdateShown then
        CompactRaidFrameManager_UpdateShown()
    end

    ApplyEditModeLayout(silent)

    if not silent then
        print(string.format("|cFF00CCFF[MidnightQoL]|r Applied %d saved WoW settings.", count))
    end
end

API.ApplyWoWSettings = ApplySettings

-- ── UI ────────────────────────────────────────────────────────────────────────
local wowSettingsFrame

local function BuildUI()
    if wowSettingsFrame then return end

    local f = CreateFrame("Frame", "MidnightQoLWoWSettingsFrame", UIParent)
    f:SetSize(760, 600); f:Hide()
    wowSettingsFrame = f

    local y = -10

    local function Header(txt)
        local t = f:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
        t:SetText(txt); t:SetPoint("TOPLEFT", 12, y); y = y - 26
    end
    local function Divider()
        local d = f:CreateTexture(nil, "ARTWORK")
        d:SetSize(736, 1); d:SetPoint("TOPLEFT", 12, y)
        d:SetColorTexture(0.3, 0.3, 0.3, 0.8); y = y - 10
    end
    local function Note(txt, indent)
        local t = f:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
        t:SetPoint("TOPLEFT", indent or 14, y)
        t:SetWidth(736 - (indent or 14)); t:SetJustifyH("LEFT"); t:SetWordWrap(true)
        t:SetTextColor(0.6, 0.6, 0.6, 1); t:SetText(txt)
        y = y - t:GetStringHeight() - 8
    end
    local function Row(txt)
        local t = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        t:SetPoint("TOPLEFT", 14, y); t:SetWidth(720); t:SetJustifyH("LEFT"); t:SetText(txt)
        y = y - 18
    end
    local function Bool(cvar)
        return GetCVar(cvar) == "1" and "|cFF00FF00ON|r" or "|cFFAAAAAA OFF|r"
    end

    -- Title
    Header("|cFFFFD700Defaults|r")
    Divider()
    Note("Saves your current interface settings and re-applies them on every login, keeping them the same across all characters. Set up your UI first, then click Save.", 14)
    y = y - 4

    -- Buttons
    local saveBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    saveBtn:SetSize(190, 28); saveBtn:SetPoint("TOPLEFT", 12, y); saveBtn:SetText("Save Current Settings")

    local applyBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    applyBtn:SetSize(110, 28); applyBtn:SetPoint("LEFT", saveBtn, "RIGHT", 8, 0); applyBtn:SetText("Apply Now")
    applyBtn:SetScript("OnClick", function() ApplySettings(false) end)

    y = y - 36

    local statusLbl = f:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    statusLbl:SetPoint("TOPLEFT", 14, y); statusLbl:SetWidth(730); statusLbl:SetJustifyH("LEFT")
    statusLbl:SetTextColor(0.7, 0.7, 0.7, 1)
    f.statusLbl = statusLbl
    y = y - 22

    saveBtn:SetScript("OnClick", function()
        CaptureSettings()
        local db = GetDB()
        if f.statusLbl then
            f.statusLbl:SetText(db and db.savedAt
                and ("|cFF88FF88Snapshot saved: " .. db.savedAt .. "|r")
                or  "|cFFFF4444Save failed — try again.|r")
        end
        SyncUI()
    end)

    -- Gameplay
    y = y - 4
    Header("|cFFFFD700Gameplay|r")
    Divider()
    Note("Options > Interface > Controls", 14)
    local function MakeDynRow()
        local t = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        t:SetPoint("TOPLEFT", 14, y); t:SetWidth(720); t:SetJustifyH("LEFT")
        y = y - 18
        return t
    end
    f.rowAutoLoot     = MakeDynRow()
    f.rowInteract     = MakeDynRow()
    f.rowInteractKey  = MakeDynRow()

    -- Gameplay Enhancements
    y = y - 6
    Header("|cFF88FFFFGameplay Enhancements|r")
    Divider()
    Note("Options > Gameplay Enhancements", 14)
    f.rowCooldownMgr  = MakeDynRow()
    f.rowDamageMeter  = MakeDynRow()

    -- Raid Frames
    y = y - 6
    Header("|cFFFF80FFRaid Frames|r")
    Divider()
    Note("Edit Raid Profiles > General Options", 14)
    f.rowPowerBar     = MakeDynRow()
    f.rowClassColor   = MakeDynRow()
    f.rowDispellable  = MakeDynRow()

    -- Action Bars
    y = y - 6
    Header("|cFFFFD700Action Bars|r")
    Divider()
    Note("Which bars 2–8 are currently shown.", 14)
    local barLabels = {"Bar 2","Bar 3","Bar 4","Bar 5","Bar 6","Bar 7","Bar 8"}
    f.barRows = {}
    local col, ry = 0, y
    for i = 1, #barLabels do
        local lbl = f:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
        lbl:SetPoint("TOPLEFT", col == 0 and 14 or 310, ry)
        f.barRows[i] = lbl
        col = col + 1
        if col >= 2 then col = 0; ry = ry - 16 end
    end
    y = ry - 20

    -- Edit Mode
    y = y - 4
    Header("|cFFAAFFAAEdit Mode Layout|r")
    Divider()
    local hasAPI = C_EditMode and C_EditMode.GetLayouts and C_EditMode.SaveLayouts
    Note("Saves your active Edit Mode layout and copies it to the Default layout slot on every character on every login.", 14)
    f.rowActiveLayout = MakeDynRow()
    f.rowSavedLayout  = MakeDynRow()

    -- How to use
    y = y - 8
    Note("|cFFFFD700How to use:|r  Set up your UI exactly how you want it. Click Save. On every subsequent login MidnightQoL silently re-applies your snapshot — including on alts. Apply Now forces an immediate re-apply.", 12)

    -- Tab registration + sync
    local barCVars = {
        "multiBarBottomLeft","multiBarBottomRight",
        "multiBarRight","multiBarLeft",
        "multiBar5","multiBar6","multiBar7",
    }
    local barLabelsSync = {"Bar 2","Bar 3","Bar 4","Bar 5","Bar 6","Bar 7","Bar 8"}

    local function SyncUI()
        local dbNow = GetDB()
        if f.statusLbl then
            f.statusLbl:SetText(dbNow and dbNow.savedAt
                and ("|cFFAAAAFFLast saved: " .. dbNow.savedAt .. "|r")
                or  "|cFFFF4444No snapshot saved yet. Configure your settings then click Save.|r")
        end

        -- Helper: read live CVar and show ON/OFF
        local function B(cvar)
            return GetCVar(cvar) == "1" and "|cFF00FF00ON|r" or "|cFFAAAAAA OFF|r"
        end

        if f.rowAutoLoot    then f.rowAutoLoot:SetText("  Auto Loot:  " .. B("autoLootDefault")) end
        if f.rowInteract    then f.rowInteract:SetText("  Interact on Left Click:  " .. B("interactOnLeftClick")) end
        if f.rowInteractKey then
            local iKey = GetBindingKey(INTERACT_BINDING)
            f.rowInteractKey:SetText(string.format("  Interact Key:  %s  |cFFAAAAAA(Key Bindings > Targeting > Interact with Target)|r",
                iKey and ("|cFFFFD700" .. iKey .. "|r") or "|cFFAAAAAA(unbound)|r"))
        end
        if f.rowCooldownMgr  then f.rowCooldownMgr:SetText("  Cooldown Manager:  "  .. B("cooldownViewerEnabled") .. "  |cFFAAAAAA(cooldownViewerEnabled)|r") end
        if f.rowDamageMeter  then f.rowDamageMeter:SetText("  Damage Meter:  "      .. B("damageMeterEnabled")    .. "  |cFFAAAAAA(damageMeterEnabled)|r") end
        if f.rowPowerBar     then f.rowPowerBar:SetText(   "  Display Power Bars:  " .. B("raidFrameShowPowerBar")) end
        if f.rowClassColor   then f.rowClassColor:SetText( "  Use Class Colors:  "   .. B("raidFrameShowClassColor")) end
        if f.rowDispellable  then f.rowDispellable:SetText("  Only Dispellable Debuffs:  " .. B("raidFrameShowOnlyDispellableDebuffs")) end

        if f.barRows then
            for i, lbl in ipairs(f.barRows) do
                lbl:SetText(string.format("%s:  %s", barLabelsSync[i], B(barCVars[i])))
            end
        end

        if f.rowActiveLayout then
            local hasEM = C_EditMode and C_EditMode.GetLayouts
            if hasEM then
                local info = C_EditMode.GetLayouts()
                local activeIdx = info and info.activeLayout or 1
                local layoutName = info and info.layouts and info.layouts[activeIdx] and info.layouts[activeIdx].layoutName or "Unknown"
                f.rowActiveLayout:SetText(string.format("  Current active layout: |cFFFFD700%s|r  (index %d)", layoutName, activeIdx))
            else
                f.rowActiveLayout:SetText("  |cFFAAAAAA C_EditMode API not available.|r")
            end
        end
        if f.rowSavedLayout then
            local dbNow2 = GetDB()
            if dbNow2 and dbNow2.editModeLayoutName then
                f.rowSavedLayout:SetText(string.format("  Saved layout: |cFF88FF88%s|r", dbNow2.editModeLayoutName))
            else
                f.rowSavedLayout:SetText("  No layout saved yet. Click |cFFFFD700Save Current Settings|r to capture it.")
            end
        end
    end

    if API.RegisterTab then
        API.RegisterTab("Defaults", f, SyncUI, 75, nil, 5)
    end
    SyncUI()
end

-- ── Events ────────────────────────────────────────────────────────────────────
local wsEvents = CreateFrame("Frame")
wsEvents:RegisterEvent("PLAYER_LOGIN")
wsEvents:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        C_Timer.After(0, BuildUI)
        -- 2s delay: wait for Blizzard to finish loading the character's own CVars
        C_Timer.After(2, function()
            local db = GetDB()
            if db and db.savedAt then
                ApplySettings(true)
                API.Debug("[WoWSettings] auto-applied saved snapshot")
            end
        end)
    end
end)

API.Debug("[MidnightQoL] WoWSettings loaded")
