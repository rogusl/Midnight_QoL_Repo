-- ============================================================
-- RogUI / Modules / SmartSwap / SmartSwap.lua
-- MIGRATED: Unified event system
--
-- "Layouts" tab — four sections:
--
--  1. Default layout   — Edit Mode layout used when no talent-based
--                        layout rule matches the active loadout.
--
--  2. Activity talents — per-spec x per-activity -> talent loadout.
--                        Fires ONLY on zone-entry or group-join.
--                        If you manually swap talents after entry,
--                        that activity slot is considered "done"
--                        and won't fire again until the next entry.
--
--  3. Layout by talents — for each Edit Mode layout, select which
--                         loadouts should activate it.
--                         Fires on ANY loadout change (manual or auto).
--
--  4. Equip set by talents — for each equipment set, select which
--                            loadouts should activate it.
--                            Fires on ANY loadout change (manual or auto).
-- ============================================================

local API = RogUIAPI

-- ── Local state ────────────────────────────────────────────────────────────────
local _wasInGroupState = false
-- Try C_PvP.IsWarModeDesired() or fall back to false
local _lastWarMode = (C_PvP and C_PvP.IsWarModeDesired and C_PvP.IsWarModeDesired()) or false

-- ── DB schema ─────────────────────────────────────────────────────────────────
-- alsEnabled         bool
-- alsDefaultLayout   { layoutIndex=N, layoutName=S } | nil
--
-- alsActivityRules   [specID_str][activity] = { loadoutID, loadoutName }
--
-- alsLoadoutLayout   [loadoutID_str] = { layoutIndex=N, layoutName=S } | nil
--
-- alsLoadoutEquip    [loadoutID_str] = { equipSetID=N, equipSetName=S } | nil
--
-- Per-session only (not saved): activity slots already handled this zone entry,
-- tracked in alsHandledActivities[specID_str][activity] = true

local ACTIVITIES = { "raid", "dungeon", "battleground", "arena", "openworld", "warmode" }
local ACT_LABEL  = { raid="Raid", dungeon="Dungeon", battleground="BG", arena="Arena",
                     openworld="Open World", warmode="War Mode" }
local ACT_COLOR  = { raid="|cFFFF6060", dungeon="|cFF60CCFF",
                     battleground="|cFFFFCC00", arena="|cFFFF88FF",
                     openworld="|cFF88FF88", warmode="|cFFFF4400" }

local DEFAULTS = {
    alsEnabled       = false,
    alsActivityRules = {},
    alsLoadoutLayout = {},
    alsLoadoutEquip  = {},
}

local function GetDB()
    if not RogUIDB then return DEFAULTS end
    for k, v in pairs(DEFAULTS) do
        if RogUIDB[k] == nil then RogUIDB[k] = v end
    end
    return RogUIDB
end

-- Per-session: which activity slots we've already auto-fired this zone entry.
-- Cleared on PLAYER_ENTERING_WORLD / GROUP_ROSTER_UPDATE (first join).
-- When the player manually swaps, we mark that slot as handled so the
-- auto-fire won't re-override them if they re-enter the same zone.
local handledActivities = {}  -- [specID_str][activity] = true

local function MarkActivityHandled(specID, activity)
    local key = tostring(specID)
    handledActivities[key] = handledActivities[key] or {}
    handledActivities[key][activity] = true
end
local function IsActivityHandled(specID, activity)
    local s = handledActivities[tostring(specID)]
    return s and s[activity]
end
local function ClearHandledActivities()
    handledActivities = {}
end

-- ── Activity rules ────────────────────────────────────────────────────────────
local function GetActivityRules()
    local db = GetDB(); db.alsActivityRules = db.alsActivityRules or {}
    return db.alsActivityRules
end
local function GetActivityRule(specID, activity)
    local sr = GetActivityRules()[tostring(specID)]
    return sr and sr[activity]
end
local function SaveActivityRule(specID, activity, loadoutID, loadoutName)
    local rules = GetActivityRules(); local key = tostring(specID)
    rules[key] = rules[key] or {}
    rules[key][activity] = loadoutID
        and {loadoutID=loadoutID, loadoutName=loadoutName} or nil
end

-- ── Loadout → layout (one-to-one) ────────────────────────────────────────────
local function GetLoadoutLayouts()
    local db = GetDB(); db.alsLoadoutLayout = db.alsLoadoutLayout or {}
    return db.alsLoadoutLayout
end
local function GetLoadoutLayout(loadoutID)
    if not loadoutID then return nil end
    return GetLoadoutLayouts()[tostring(loadoutID)]
end
local function SaveLoadoutLayout(loadoutID, layoutIndex, layoutName)
    if not loadoutID then return end
    GetLoadoutLayouts()[tostring(loadoutID)] = layoutIndex
        and {layoutIndex=layoutIndex, layoutName=layoutName} or nil
end
local function FindLayoutForLoadout(loadoutID)
    local r = GetLoadoutLayout(loadoutID)
    return r and r.layoutIndex or nil
end

-- ── Loadout → equip set (one-to-one) ─────────────────────────────────────────
local function GetLoadoutEquips()
    local db = GetDB(); db.alsLoadoutEquip = db.alsLoadoutEquip or {}
    return db.alsLoadoutEquip
end
local function GetLoadoutEquip(loadoutID)
    if not loadoutID then return nil end
    return GetLoadoutEquips()[tostring(loadoutID)]
end
local function SaveLoadoutEquip(loadoutID, equipSetID, equipSetName)
    if not loadoutID then return end
    GetLoadoutEquips()[tostring(loadoutID)] = equipSetID
        and {equipSetID=equipSetID, equipSetName=equipSetName} or nil
end
local function FindEquipForLoadout(loadoutID)
    local r = GetLoadoutEquip(loadoutID)
    if not r then return nil, nil end
    return r.equipSetID, r.equipSetName
end

-- ── Default layout ────────────────────────────────────────────────────────────
local function GetDefaultLayout()  return GetDB().alsDefaultLayout end
local function SaveDefaultLayout(layoutIndex, layoutName)
    GetDB().alsDefaultLayout = layoutIndex
        and {layoutIndex=layoutIndex, layoutName=layoutName} or nil
end

-- ── Edit Mode helpers ─────────────────────────────────────────────────────────
local function GetLayoutsRaw()
    if EditModeManagerFrame and EditModeManagerFrame.GetLayouts then
        return EditModeManagerFrame:GetLayouts() or {}
    end
    return {}
end
local function GetActiveLayoutIndex()
    if not EditModeManagerFrame then return nil end
    local info = EditModeManagerFrame.GetActiveLayoutInfo
              and EditModeManagerFrame:GetActiveLayoutInfo()
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
        C_EditMode.SetActiveLayout(layoutIndex); return true
    end
    return false
end

-- ── Talent / loadout helpers ──────────────────────────────────────────────────
local function GetActiveLoadoutID()
    if not (C_ClassTalents and C_ClassTalents.GetLastSelectedSavedConfigID) then return nil end
    local specIndex = GetSpecialization and GetSpecialization()
    if not specIndex then return nil end
    local specID = select(1, GetSpecializationInfo(specIndex))
    if not specID then return nil end
    local id = C_ClassTalents.GetLastSelectedSavedConfigID(specID)
    return (id and id ~= 0) and id or nil
end
local function GetLoadoutDisplayName(loadoutID)
    if C_Traits and C_Traits.GetConfigInfo then
        local info = C_Traits.GetConfigInfo(loadoutID)
        return info and info.name
    end
    return nil
end
local function GetSpecs()
    local out = {}
    for i = 1, (GetNumSpecializations and GetNumSpecializations() or 0) do
        local id, name = GetSpecializationInfo(i)
        if id and name then out[#out+1] = {id=id, name=name, index=i} end
    end
    return out
end
local function GetCurrentSpecID()
    local idx = GetSpecialization and GetSpecialization()
    return idx and select(1, GetSpecializationInfo(idx)) or nil
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

-- ── Equipment set helpers ─────────────────────────────────────────────────────
local function GetAllEquipmentSets()
    local out = {}
    if not (C_EquipmentSet and C_EquipmentSet.GetEquipmentSetIDs) then return out end
    for _, setID in ipairs(C_EquipmentSet.GetEquipmentSetIDs()) do
        local name, _, id = C_EquipmentSet.GetEquipmentSetInfo(setID)
        if name then out[#out+1] = {id=id or setID, name=name} end
    end
    table.sort(out, function(a,b) return a.name < b.name end)
    return out
end
local function UseEquipmentSet(setID)
    if not setID or InCombatLockdown() then return end
    if C_EquipmentSet and C_EquipmentSet.UseEquipmentSet then
        C_EquipmentSet.UseEquipmentSet(setID)
    end
end

-- ── Zone / activity detection ─────────────────────────────────────────────────
local function IsInWarMode()
    -- IsWarModeActive can return false during zone entry while PvP state initializes.
    -- IsWarModeDesired reflects the player's toggle setting and is always reliable.
    -- We treat either as true so we never miss War Mode on login/zone-in.
    if C_PvP then
        if C_PvP.IsWarModeActive and C_PvP.IsWarModeActive() then return true end
        if C_PvP.IsWarModeDesired and C_PvP.IsWarModeDesired() then return true end
    end
    return false
end

local function GetCurrentActivity()
    local _, zoneType = GetInstanceInfo()
    if zoneType == "raid"  then return "raid"         end
    if zoneType == "party" then return "dungeon"      end  -- includes M+
    if zoneType == "pvp"   then return "battleground" end
    if zoneType == "arena" or zoneType == "ratedarena" then return "arena" end
    -- Open world: War Mode takes priority over plain open world.
    -- A player with War Mode on is NEVER in "openworld" — they are always "warmode".
    if zoneType == "none" or zoneType == "" or not zoneType then
        if IsInWarMode() then return "warmode" end
        return "openworld"
    end
    return nil
end

-- ── Core: apply layout + equip for a loadout (any loadout change) ─────────────
-- Called for BOTH auto-swaps and manual swaps.
local function ApplyLoadoutSideEffects(loadoutID, source)
    if not loadoutID or InCombatLockdown() then
        API.Debug(string.format("[ALS] ApplyLoadoutSideEffects skipped — loadoutID=%s combat=%s", tostring(loadoutID), tostring(InCombatLockdown())))
        return
    end
    API.Debug(string.format("[ALS] ApplyLoadoutSideEffects — source=%s loadoutID=%s", source, tostring(loadoutID)))

    -- Layout by loadout (one-to-one)
    local layRule   = GetLoadoutLayout(loadoutID)
    local layoutIdx = layRule and layRule.layoutIndex
    API.Debug(string.format("[ALS]   layRule=%s layoutIdx=%s activeIdx=%s", tostring(layRule ~= nil), tostring(layoutIdx), tostring(GetActiveLayoutIndex())))
    if layoutIdx then
        if layoutIdx ~= GetActiveLayoutIndex() then
            SetActiveLayout(layoutIdx)
            local lname = layRule.layoutName or ("Layout "..layoutIdx)
            API.Debug(string.format("[ALS] %s — layout '%s'", source, lname))
        end
    else
        local def = GetDefaultLayout()
        API.Debug(string.format("[ALS]   no loadout rule — defaultLayout=%s", tostring(def and def.layoutIndex)))
        if def and def.layoutIndex and def.layoutIndex ~= GetActiveLayoutIndex() then
            SetActiveLayout(def.layoutIndex)
            API.Debug(string.format("[ALS] %s — default layout '%s'", source, def.layoutName or ""))
        end
    end

    -- Equip set by loadout (one-to-one) — skip if the set is already equipped.
    local equipID, equipName = FindEquipForLoadout(loadoutID)
    API.Debug(string.format("[ALS]   equipID=%s", tostring(equipID)))
    if equipID then
        local _, _, _, isEquipped = C_EquipmentSet.GetEquipmentSetInfo(equipID)
        if not isEquipped then
            UseEquipmentSet(equipID)
            API.Debug(string.format("[ALS] %s — equipped '%s'", source, tostring(equipName)))
        else
            API.Debug(string.format("[ALS]   equip set '%s' already equipped — skipping", tostring(equipName)))
        end
    end
end

-- ── Core: activity-based talent auto-swap ─────────────────────────────────────
-- Only fires on zone entry / group join. Respects per-slot handled flag.
local deferredActivity = false

local function TryActivitySwap()
    local db = GetDB()
    if not db.alsEnabled then API.Debug("[ALS] TryActivitySwap: disabled"); return end
    if InCombatLockdown() then deferredActivity = true; API.Debug("[ALS] TryActivitySwap: combat lockdown, deferred"); return end

    local specID = GetCurrentSpecID()
    if not specID then API.Debug("[ALS] TryActivitySwap: no specID"); return end

    local activity = GetCurrentActivity()
    if not activity then API.Debug("[ALS] TryActivitySwap: no activity"); return end

    -- Belt-and-suspenders: if we resolved openworld but a warmode rule exists and
    -- War Mode is active, prefer warmode. Handles any edge case where IsWarModeActive
    -- was still false during zone entry but IsWarModeDesired wasn't available either.
    if activity == "openworld" and IsInWarMode() then
        local wmRule = GetActivityRule(specID, "warmode")
        if wmRule and wmRule.loadoutID then
            API.Debug("[ALS] TryActivitySwap: overriding openworld→warmode (warmode rule exists and War Mode is on)")
            activity = "warmode"
        end
    end

    API.Debug(string.format("[ALS] TryActivitySwap: activity=%s specID=%s", activity, tostring(specID)))

    if IsActivityHandled(specID, activity) then API.Debug("[ALS] TryActivitySwap: already handled"); return end

    local rule = GetActivityRule(specID, activity)
    API.Debug(string.format("[ALS] TryActivitySwap: rule=%s loadoutID=%s", tostring(rule ~= nil), tostring(rule and rule.loadoutID)))
    if not rule or not rule.loadoutID then return nil end  -- no rule matched

    local activeID = GetActiveLoadoutID()
    API.Debug(string.format("[ALS] TryActivitySwap: activeID=%s targetID=%s", tostring(activeID), tostring(rule.loadoutID)))
    if activeID == rule.loadoutID then
        -- Loadout already correct — mark handled, let caller apply side effects.
        MarkActivityHandled(specID, activity)
        return true  -- caller should apply side effects now
    end

    if C_ClassTalents and C_ClassTalents.LoadConfig then
        loadConfigPending = true
        C_ClassTalents.LoadConfig(rule.loadoutID, true)
        local lname = GetLoadoutDisplayName(rule.loadoutID) or rule.loadoutName or ""
        API.Debug(string.format("[ALS] TryActivitySwap: loaded loadout '%s' for activity '%s'", lname, activity))
    end
    MarkActivityHandled(specID, activity)
    C_Timer.After(0.3, function()
        loadConfigPending = false
        ApplyLoadoutSideEffects(rule.loadoutID, ACT_LABEL[activity])
    end)
    return false  -- swap triggered, side effects are deferred
end

-- ── Event handler ─────────────────────────────────────────────────────────────
-- Design notes:
--
--  * TRAIT_CONFIG_UPDATED fires whenever a talent loadout is committed —
--    on loadout switch, on spec change, and on individual talent changes.
--    GetLastSelectedSavedConfigID is not reliable in the same frame it fires,
--    so we poll with C_Timer.After until the ID is populated.
--
--  * We never try to distinguish "our" talent swaps from manual ones —
--    every loadout change triggers ApplyLoadoutSideEffects. Activity auto-swap
--    is suppressed by the handledActivities table.
--
--  * PLAYER_SPECIALIZATION_CHANGED fires before TRAIT_CONFIG_UPDATED.
--    We set specChangePending so the subsequent TRAIT_CONFIG_UPDATED events
--    don't double-apply. The spec change handler owns that flow.

-- alsEvents frame replaced by unified event system
-- Registrations at end of file after handlers defined

local specChangePending = false   -- suppress TRAIT_CONFIG_UPDATED during spec swap
local loadConfigPending = false   -- LoadConfig was just called; TRAIT_CONFIG_UPDATED will handle it

-- ── Catch-all event sniffer (remove once correct events are confirmed) ─────────
-- Usage: /alssniff  — then swap a loadout or spec and watch chat
local alsSniff = CreateFrame("Frame")
local sniffEvents = {
    "PLAYER_TALENT_UPDATE",
    "TRAIT_CONFIG_UPDATED",
    "TRAIT_CONFIG_LIST_UPDATED",
    "PLAYER_SPECIALIZATION_CHANGED",
    "ACTIVE_PLAYER_SPECIALIZATION_CHANGED",
    "CHARACTER_POINTS_CHANGED",
    "UNIT_AURA",
    "SPELLS_CHANGED",
    "PLAYER_ENTERING_WORLD",
    "ZONE_CHANGED_NEW_AREA",
    "ADDON_LOADED",
    "ACTIVE_TALENT_GROUP_CHANGED",
    "UPDATE_TALENT_UI",
    "TALENT_UPDATE",
    "LOADOUT_CHANGED",
    "LOADOUT_SELECTED",
    "CONFIG_CHANGED",
    "ACTIVE_LOADOUT_CHANGED",
    "TALENT_LOADOUT_CHANGED",
}
local sniffActive = false
SLASH_ALSSNIFF1 = "/alssniff"
SlashCmdList["ALSSNIFF"] = function()
    if sniffActive then
        for _, ev in ipairs(sniffEvents) do
            pcall(function() alsSniff:UnregisterEvent(ev) end)
        end
        alsSniff:SetScript("OnEvent", nil)
        sniffActive = false
        print("|cFF00CCFF[RogUI]|r ALS event sniffer |cFFAAAAAAdisabled|r")
    else
        if not API.DEBUG then
            API.DEBUG = true
            print("|cFF00CCFF[RogUI]|r Debug mode auto-enabled for sniffer")
        end
        alsSniff:SetScript("OnEvent", function(_, ev, ...) API.Debug("[ALS sniff] " .. ev) end)
        for _, ev in ipairs(sniffEvents) do
            pcall(function() alsSniff:RegisterEvent(ev) end)
        end
        sniffActive = true
        print("|cFF00CCFF[RogUI]|r ALS event sniffer |cFFFFFF00ON|r — swap a loadout or spec and watch chat")
    end
end

-- SmartSwap event handlers via unified system
local function OnAlsEvent(event)
    API.Debug("[ALS] OnEvent: " .. tostring(event))
    if event ~= "PLAYER_LOGIN" and API.IsTabEnabled and not API.IsTabEnabled("SmartSwap") then return end
    local db = GetDB()
    API.Debug("[ALS] OnEvent: " .. tostring(event))
    if event == "PLAYER_LOGIN" then
        if API.IsTabEnabled and not API.IsTabEnabled("SmartSwap") then return end
        C_Timer.After(1.5, function()
            local lo = GetActiveLoadoutID()
            if lo then ApplyLoadoutSideEffects(lo, "Login") end
            C_Timer.After(0.3, TryActivitySwap)
        end)

    elseif event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then
        ClearHandledActivities()
        -- Delay 3s — GetInstanceInfo() is reliable by then, and C_PvP.IsWarModeActive
        -- can lag behind by 1-2s on zone transitions so the extra second prevents
        -- War Mode being misdetected as Open World.
        C_Timer.After(3, function()
            API.Debug("[ALS] zone entry fired — activity=" .. tostring(GetCurrentActivity()))
            local result = TryActivitySwap()
            if result == true then
                -- Loadout already correct — apply layout/equip for it now
                local lo = GetActiveLoadoutID()
                if lo then ApplyLoadoutSideEffects(lo, "Zone entry") end
            elseif result == nil then
                -- No activity rule matched. If War Mode is on, don't apply defaults —
                -- PLAYER_FLAGS_CHANGED will fire shortly and handle the warmode rule.
                if not IsInWarMode() then
                    local lo = GetActiveLoadoutID()
                    if lo then ApplyLoadoutSideEffects(lo, "Zone entry") end
                end
            end
            -- result == false → LoadConfig was called, deferred ApplyLoadoutSideEffects
            -- is already scheduled inside TryActivitySwap; don't apply here or we'd
            -- equip the old loadout's gear over the top of the new one.
        end)

    elseif event == "CHALLENGE_MODE_START" then
        -- M+ key started — use shorter delay since we're already in the instance
        ClearHandledActivities()
        C_Timer.After(1, function()
            API.Debug("[ALS] CHALLENGE_MODE_START — activity=" .. tostring(GetCurrentActivity()))
            TryActivitySwap()
        end)

    elseif event == "GROUP_ROSTER_UPDATE" then
        -- Fire on every roster update — handledActivities prevents double-swaps
        -- within the same zone session, so this is safe to always call.
        local inGroup = IsInGroup() or IsInRaid()
        if inGroup then
            if not _wasInGroupState then
                ClearHandledActivities()
            end
            C_Timer.After(0.3, TryActivitySwap)
        end
        _wasInGroupState = inGroup

    elseif event == "PLAYER_SPECIALIZATION_CHANGED"
        or event == "ACTIVE_PLAYER_SPECIALIZATION_CHANGED" then
        ClearHandledActivities()
        specChangePending = true
        API.Debug(string.format("[ALS] %s fired — polling for loadout ID", event))
        local attempts = 0
        local expectedSpecID = GetCurrentSpecID()
        local function tryApply()
            attempts = attempts + 1
            local lo = GetActiveLoadoutID()
            local specID = GetCurrentSpecID()
            API.Debug(string.format("[ALS] SPEC_CHANGE poll #%d — specID=%s loadoutID=%s", attempts, tostring(specID), tostring(lo)))

            -- Spec changed again mid-poll — abort, the new event will handle it
            if specID ~= expectedSpecID then
                API.Debug("[ALS] SPEC_CHANGE aborted — spec changed mid-poll")
                specChangePending = false
                return
            end

            if lo then
                specChangePending = false
                TryActivitySwap()
                ApplyLoadoutSideEffects(lo, "Spec change")
            elseif attempts < 8 then
                -- 8 attempts * 0.2s = 1.6s max wait, enough for a slow login
                C_Timer.After(0.2, tryApply)
            else
                -- No loadout ID after 1.6s — this spec likely has no saved loadout.
                -- Still run TryActivitySwap so activity rules fire, and apply
                -- side effects for whatever the default layout is.
                API.Debug("[ALS] SPEC_CHANGE: no loadout ID found — spec may have no saved loadout")
                specChangePending = false
                TryActivitySwap()
                local defLayout = GetDefaultLayout()
                if defLayout and defLayout.layoutIndex then
                    ApplyLoadoutSideEffects(nil, "Spec change")
                end
            end
        end
        C_Timer.After(0.2, tryApply)

    elseif event == "TRAIT_CONFIG_UPDATED" then
        -- Fires whenever a loadout is committed (switched, saved, spec changed).
        -- Suppress during spec change — that handler owns the flow and clears
        -- the flag once the loadout ID is queryable.
        if specChangePending then
            API.Debug("[ALS] TRAIT_CONFIG_UPDATED suppressed — spec change pending")
            return
        end
        if loadConfigPending then
            API.Debug("[ALS] TRAIT_CONFIG_UPDATED suppressed — loadConfig pending")
            return
        end
        API.Debug("[ALS] TRAIT_CONFIG_UPDATED fired — polling for loadout ID")
        local attempts = 0
        local function tryApply()
            attempts = attempts + 1
            local lo = GetActiveLoadoutID()
            API.Debug(string.format("[ALS] TRAIT_CONFIG poll #%d — loadoutID=%s", attempts, tostring(lo)))
            if lo then
                local specID   = GetCurrentSpecID()
                local activity = GetCurrentActivity()
                if specID and activity then MarkActivityHandled(specID, activity) end
                ApplyLoadoutSideEffects(lo, "Loadout change")
            elseif attempts < 5 then
                C_Timer.After(0.2, tryApply)
            else
                API.Debug("[ALS] TRAIT_CONFIG gave up — no loadout ID after 1s")
            end
        end
        C_Timer.After(0, tryApply)

    elseif event == "PLAYER_FLAGS_CHANGED" then
        -- Fires when War Mode activates on zone entry (among other flag changes).
        -- Re-evaluate activity so the warmode rule is applied once the PvP state settles.
        local nowWarMode = (C_PvP and C_PvP.IsWarModeDesired and C_PvP.IsWarModeDesired()) or false
        if nowWarMode ~= _lastWarMode then
            _lastWarMode = nowWarMode
            API.Debug("[ALS] PLAYER_FLAGS_CHANGED — War Mode changed to " .. tostring(nowWarMode))
            ClearHandledActivities()
            C_Timer.After(0.5, function()
                local result = TryActivitySwap()
                -- Only apply side effects directly if the loadout was already correct;
                -- result==false means TryActivitySwap already deferred them internally.
                if result == true then
                    local lo = GetActiveLoadoutID()
                    if lo then ApplyLoadoutSideEffects(lo, nowWarMode and "War Mode" or "Open World") end
                end
            end)
        end

    elseif event == "PLAYER_REGEN_ENABLED" then
        if deferredActivity then
            deferredActivity = false
            TryActivitySwap()
        end

    end
end

-- ── UI ────────────────────────────────────────────────────────────────────────
local alsFrame = CreateFrame("Frame", "RogUISSFrame", UIParent)
alsFrame:SetSize(1320, 2000); alsFrame:Hide()

-- When registered as a tab, it will be re-parented and anchored properly by RegisterTab
-- But we need to make it fill the tab area correctly
alsFrame:SetScript("OnShow", function(self)
    if self:GetParent() ~= UIParent then
        -- We're in a tab — fill the parent
        self:SetAllPoints(self:GetParent())
    end
end)

-- Scroll frame so the tab content can grow
local alsScroll = CreateFrame("ScrollFrame", "RogUISSScroll", alsFrame, "UIPanelScrollFrameTemplate")
alsScroll:SetPoint("TOPLEFT", 0, 0); alsScroll:SetPoint("BOTTOMRIGHT", -20, 0)
local alsContent = CreateFrame("Frame", nil, alsScroll)
alsContent:SetSize(1300, 2000); alsScroll:SetScrollChild(alsContent)

-- Keep alsContent width in sync with alsFrame width
alsFrame:SetScript("OnSizeChanged", function(self, w, h)
    alsScroll:SetPoint("BOTTOMRIGHT", -20, 0)
    alsContent:SetWidth(w - 20)
end)

-- ── Shared popup helpers ──────────────────────────────────────────────────────
-- ── Popup system ─────────────────────────────────────────────────────────────
-- Each popup maintains a pool of button/header frames that are reused across
-- calls. We never create new child frames after the first population — we just
-- update text and swap OnClick handlers. This avoids stale-closure bugs where
-- old anonymous frames respond to clicks with outdated captures.

local function MakePopup(name, w)
    local p = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
    p:SetSize(w, 280); p:SetFrameStrata("TOOLTIP")
    p:SetBackdrop({bgFile="Interface/DialogFrame/UI-DialogBox-Background",
        edgeFile="Interface/DialogFrame/UI-DialogBox-Border",
        tile=true, tileSize=16, edgeSize=16, insets={left=4,right=4,top=4,bottom=4}})
    p:SetBackdropColor(0.08, 0.08, 0.12, 0.97); p:Hide()
    local sc = CreateFrame("ScrollFrame", nil, p, "UIPanelScrollFrameTemplate")
    sc:SetPoint("TOPLEFT", 8, -8); sc:SetPoint("BOTTOMRIGHT", -28, 8)
    local ct = CreateFrame("Frame", nil, sc)
    ct:SetWidth(w - 46); sc:SetScrollChild(ct)
    p.content = ct
    p.pool = {}   -- { frame, label, isHeader, onClickFn }
    return p
end

local loPopup = MakePopup("MidnightSSLoPopup", 230)
local eqPopup = MakePopup("MidnightSSEqPopup", 210)
local activePopup = nil

local _popupClosedThisFrame = false

local function ClosePopups()
    loPopup:Hide(); eqPopup:Hide()
    activePopup = nil
    _popupClosedThisFrame = true
    C_Timer.After(0, function() _popupClosedThisFrame = false end)
end

-- Show a popup anchored to anchorBtn, populated with a list of row descriptors.
-- row = { text=S, header=bool, indent=bool, muted=bool, onClick=fn }
-- Reuses pooled frames; grows pool as needed; hides excess.
local function ShowPopup(popup, anchorBtn, rows)
    if _popupClosedThisFrame then return end
    if activePopup == popup and popup._anchor == anchorBtn then
        ClosePopups(); return
    end
    ClosePopups()
    popup._anchor = anchorBtn
    activePopup   = popup

    local pool  = popup.pool
    local ct    = popup.content
    local ROW_H = 22
    local totalH = 0

    for i, row in ipairs(rows) do
        local slot = pool[i]
        if not slot then
            -- Allocate a new pooled frame (button or header)
            local f = CreateFrame("Button", nil, ct)
            f:SetSize(ct:GetWidth(), ROW_H)
            local hl = f:CreateTexture(nil, "HIGHLIGHT")
            hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.12)
            local lbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            lbl:SetPoint("LEFT", 4, 0)
            -- Route clicks through a stable dispatcher so we never re-SetScript
            f:SetScript("OnClick", function() if f._onClick then f._onClick() end end)
            slot = { frame=f, label=lbl }
            pool[i] = slot
        end

        local f   = slot.frame
        local lbl = slot.label

        if row.header then
            f._onClick = nil   -- headers are not clickable
            lbl:SetPoint("LEFT", 4, 0)
            lbl:SetTextColor(1, 0.8, 0, 1)
            lbl:SetText(row.text)
        else
            f._onClick = row.onClick
            lbl:SetPoint("LEFT", row.indent and 14 or 4, 0)
            lbl:SetTextColor(row.muted and 0.55 or 1,
                             row.muted and 0.55 or 1,
                             row.muted and 0.55 or 1, 1)
            lbl:SetText(row.text)
        end

        f:ClearAllPoints()
        f:SetPoint("TOPLEFT", 0, -totalH)
        f:Show()
        totalH = totalH + ROW_H
    end

    -- Hide excess pool slots
    for i = #rows + 1, #pool do
        pool[i].frame:Hide()
    end

    ct:SetHeight(math.max(1, totalH))
    popup:SetHeight(math.min(280, totalH + 16))
    popup:ClearAllPoints()
    popup:SetPoint("TOPLEFT", anchorBtn, "BOTTOMLEFT", 0, -4)
    popup:Show()
end

-- Single-select loadout picker
-- Pass specID to restrict list to that spec's loadouts only (e.g. activity grid).
-- Omit specID (or pass nil) to show all loadouts grouped by spec (e.g. loadout rules).
local function OpenLoadoutPicker(anchorBtn, onSelect, specID)
    local rows = {}
    rows[#rows+1] = { text="|cFFAAAAAA(none)|r", muted=true,
        onClick=function() onSelect(nil, nil); ClosePopups() end }
    if specID then
        -- Spec-filtered: flat list, no spec header needed
        for _, lo in ipairs(GetLoadoutsForSpec(specID)) do
            local capLo = lo
            rows[#rows+1] = { text=lo.name,
                onClick=function() onSelect(capLo.id, capLo.name); ClosePopups() end }
        end
    else
        -- All loadouts grouped by spec
        local lastSpec = nil
        for _, lo in ipairs(GetAllLoadouts()) do
            if lo.specName ~= lastSpec then
                rows[#rows+1] = { header=true, text=lo.specName }
                lastSpec = lo.specName
            end
            local capLo = lo
            rows[#rows+1] = { text=lo.name, indent=true,
                onClick=function() onSelect(capLo.id, capLo.name); ClosePopups() end }
        end
    end
    ShowPopup(loPopup, anchorBtn, rows)
end


-- ── Section header ────────────────────────────────────────────────────────────
local function SectionHeader(parent, text, yOff)
    local bg = parent:CreateTexture(nil, "BACKGROUND")
    bg:SetColorTexture(0.12, 0.12, 0.16, 0.95)
    bg:SetPoint("TOPLEFT", parent, "TOPLEFT", 4, yOff)
    bg:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -4, yOff)
    bg:SetHeight(22)
    local lbl = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lbl:SetPoint("TOPLEFT", parent, "TOPLEFT", 12, yOff - 3)
    lbl:SetText(text)
    return lbl, bg
end

-- ── RefreshPanel ──────────────────────────────────────────────────────────────
local sw = {}   -- static widget cache

local function RefreshPanel()
    local db          = GetDB()
    local layouts     = GetLayoutsRaw()
    local specs       = GetSpecs()
    local currentSpec = GetCurrentSpecID()
    local allLoadouts = GetAllLoadouts()
    local equipSets   = GetAllEquipmentSets()
    local y = -8

    -- ── Enable toggle ──────────────────────────────────────────────────────────
    if not sw.enCb then
        sw.enCb = CreateFrame("CheckButton", nil, alsContent, "UICheckButtonTemplate")
        sw.enCb:SetSize(24,24)
        sw.enCb:SetScript("OnClick", function(self) db.alsEnabled = self:GetChecked() end)
        sw.enLbl = alsContent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        sw.enLbl:SetPoint("LEFT", sw.enCb, "RIGHT", 4, 0)
        sw.enLbl:SetText("Enable automatic layout / talent / equip set switching")
    end
    sw.enCb:SetPoint("TOPLEFT", alsContent, "TOPLEFT", 8, y)
    sw.enCb:SetChecked(db.alsEnabled ~= false)
    y = y - 30

    -- ══════════════════════════════════════════════════════════════════════════
    -- 1. Default layout
    -- ══════════════════════════════════════════════════════════════════════════
    SectionHeader(alsContent, "Default Layout  |cFFAAAAAA(used when no talent rule matches)|r", y)
    y = y - 26

    if not sw.defBtn then
        sw.defBtn = CreateFrame("Button", "MidnightSSDefBtn", alsContent, "GameMenuButtonTemplate")
        sw.defBtn:SetSize(220, 22)
        sw.defBtn:SetScript("OnClick", function(self)
            -- reuse loPopup for layout picking
            local rows = {}
            rows[#rows+1] = { text="|cFFAAAAAA(none — keep current layout)|r", muted=true,
                onClick=function() SaveDefaultLayout(nil,nil); self:SetText("|cFFAAAAAA(none)|r"); ClosePopups() end }
            for i, li in ipairs(layouts) do
                local capI, capN = i, li.layoutName or ("Layout "..i)
                rows[#rows+1] = { text=capN,
                    onClick=function() SaveDefaultLayout(capI,capN); self:SetText(capN); ClosePopups() end }
            end
            ShowPopup(loPopup, self, rows)
        end)
    end
    sw.defBtn:SetPoint("TOPLEFT", alsContent, "TOPLEFT", 12, y)
    local def = GetDefaultLayout()
    sw.defBtn:SetText(def and (def.layoutName or ("Layout "..def.layoutIndex)) or "|cFFAAAAAA(none)|r")
    y = y - 30

    -- ══════════════════════════════════════════════════════════════════════════
    -- 2. Activity talents — per-spec x per-activity grid
    -- ══════════════════════════════════════════════════════════════════════════
    SectionHeader(alsContent,
        "Activity Talents  |cFFAAAAAA(auto-fires on zone entry / group join; manual swaps won't be overridden)|r", y)
    y = y - 24

    -- Column x positions: spec name (240px) | 6 activity columns (170px each)
    -- Total: 240 + 6*170 = 1260px — fits in the 1300px content width
    local SPEC_COL_W = 240
    local ACOL_W     = 170
    local ACOL = { 12 }  -- spec label at x=12
    for i = 1, #ACTIVITIES do
        ACOL[i+1] = SPEC_COL_W + (i-1) * ACOL_W
    end

    -- Rebuild headers whenever activity list changes (safe: just recreate)
    if sw.actHdrs then
        for _, fs in ipairs(sw.actHdrs) do fs:Hide() end
    end
    sw.actHdrs = {}
    local hdrs = { "|cFFFFD700Spec|r" }
    for _, act in ipairs(ACTIVITIES) do
        hdrs[#hdrs+1] = ACT_COLOR[act]..ACT_LABEL[act].."|r"
    end
    for i, h in ipairs(hdrs) do
        local fs = sw.actHdrs[i]
        if not fs then
            fs = alsContent:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
            sw.actHdrs[i] = fs
        end
        fs:SetText(h)
        fs:ClearAllPoints()
        if i == 1 then
            -- "Spec" label — left aligned at its column start
            fs:SetWidth(SPEC_COL_W)
            fs:SetJustifyH("LEFT")
            fs:SetPoint("TOPLEFT", alsContent, "TOPLEFT", ACOL[i], y)
        else
            -- Activity columns — centered over the button width
            fs:SetWidth(ACOL_W)
            fs:SetJustifyH("CENTER")
            fs:SetPoint("TOPLEFT", alsContent, "TOPLEFT", ACOL[i], y)
        end
        fs:Show()
    end
    y = y - 18

    sw.actRows = sw.actRows or {}
    for ri, spec in ipairs(specs) do
        local row = sw.actRows[ri]
        if not row then
            row = { btns = {} }
            row.lbl = alsContent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
            for _, act in ipairs(ACTIVITIES) do
                local btn = CreateFrame("Button", "MidnightSSAct"..ri.."_"..act,
                    alsContent, "GameMenuButtonTemplate")
                btn:SetSize(ACOL_W, 22); row.btns[act] = btn
            end
            sw.actRows[ri] = row
        end
        row.lbl:ClearAllPoints()
        row.lbl:SetPoint("TOPLEFT", alsContent, "TOPLEFT", ACOL[1], y)
        row.lbl:SetText(spec.name..(spec.id==currentSpec and " |cFF00FF00●|r" or ""))
        row.lbl:Show()

        for ai, act in ipairs(ACTIVITIES) do
            local btn = row.btns[act]
            btn:ClearAllPoints(); btn:SetPoint("TOPLEFT", alsContent, "TOPLEFT", ACOL[ai+1], y)
            local rule = GetActivityRule(spec.id, act)
            btn:SetText(rule and rule.loadoutName or "|cFFAAAAAA--|r")
            btn:Show()
            btn._specID  = spec.id
            btn._actKey  = act
            if not btn._scriptSet then
                btn._scriptSet = true
                btn:SetScript("OnClick", function(self)
                    local sid, akey = self._specID, self._actKey
                    OpenLoadoutPicker(self, function(loID, loName)
                        SaveActivityRule(sid, akey, loID, loName)
                        self:SetText(loName or "|cFFAAAAAA--|r")
                    end, sid)  -- pass sid to filter loadouts to this spec
                end)
            end
        end
        y = y - 26
    end
    for i = #specs+1, #sw.actRows do
        local row = sw.actRows[i]
        if row then row.lbl:Hide(); for _, b in pairs(row.btns) do b:Hide() end end
    end
    y = y - 8

    -- ══════════════════════════════════════════════════════════════════════════
    -- 3+4. Per-loadout: layout + equip set (one row per loadout, grouped by spec)
    -- ══════════════════════════════════════════════════════════════════════════
    SectionHeader(alsContent,
        "Loadout Rules  |cFFAAAAAA(one layout and one equip set per loadout)|r", y)
    y = y - 24

    if not sw.loRuleHdrs then
        sw.loRuleLoHdr  = alsContent:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
        sw.loRuleLoHdr:SetText("|cFFFFD700Talent Loadout|r")
        sw.loRuleLayHdr = alsContent:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
        sw.loRuleLayHdr:SetText("|cFFFFD700Layout|r")
        sw.loRuleEqHdr  = alsContent:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
        sw.loRuleEqHdr:SetText("|cFF88FFAAEquip Set|r")
        sw.loRuleHdrs = true
    end
    sw.loRuleLoHdr:ClearAllPoints();  sw.loRuleLoHdr:SetPoint("TOPLEFT",  alsContent, "TOPLEFT",  12, y)
    sw.loRuleLayHdr:ClearAllPoints(); sw.loRuleLayHdr:SetPoint("TOPLEFT", alsContent, "TOPLEFT", 280, y)
    sw.loRuleEqHdr:ClearAllPoints();  sw.loRuleEqHdr:SetPoint("TOPLEFT",  alsContent, "TOPLEFT", 530, y)
    y = y - 18

    sw.loRows = sw.loRows or {}
    local loRowIdx = 0
    local lastSpecName = nil

    for _, lo in ipairs(allLoadouts) do
        -- Spec group header
        if lo.specName ~= lastSpecName then
            local hkey = "loSpecHdr_"..lo.specName:gsub("%s","_")
            if not sw[hkey] then
                sw[hkey] = alsContent:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
                sw[hkey]:SetTextColor(1, 0.8, 0, 1)
                sw[hkey]:SetText(lo.specName)
            end
            sw[hkey]:ClearAllPoints()
            sw[hkey]:SetPoint("TOPLEFT", alsContent, "TOPLEFT", 12, y)
            sw[hkey]:Show()
            lastSpecName = lo.specName
            y = y - 17
        end

        loRowIdx = loRowIdx + 1
        local row = sw.loRows[loRowIdx]
        if not row then
            row = {}
            row.nameLbl = alsContent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
            row.layBtn  = CreateFrame("Button", "MidnightSSLoLay"..loRowIdx,  alsContent, "GameMenuButtonTemplate")
            row.eqBtn   = CreateFrame("Button", "MidnightSSLoEq"..loRowIdx,   alsContent, "GameMenuButtonTemplate")
            row.layBtn:SetSize(230, 22)
            row.eqBtn:SetSize(220, 22)
            sw.loRows[loRowIdx] = row
        end

        row.nameLbl:ClearAllPoints()
        row.nameLbl:SetPoint("TOPLEFT", alsContent, "TOPLEFT", 22, y)
        row.nameLbl:SetText(lo.name)
        row.nameLbl:Show()

        -- Layout button
        row.layBtn:ClearAllPoints()
        row.layBtn:SetPoint("TOPLEFT", alsContent, "TOPLEFT", 275, y)
        local layRule = GetLoadoutLayout(lo.id)
        row.layBtn:SetText(layRule and layRule.layoutName or "|cFFAAAAAA(none)|r")
        row.layBtn:Show()

        -- Store the loadout ID on the frame so the click handler always
        -- reads fresh data at click-time, never from a stale closure.
        row.layBtn._loID = lo.id
        row.eqBtn._loID  = lo.id

        if not row.layBtn._scriptSet then
            row.layBtn._scriptSet = true
            row.layBtn:SetScript("OnClick", function(self)
                local loID = self._loID
                local rows2 = {}
                rows2[#rows2+1] = { text="|cFFAAAAAA(none)|r", muted=true,
                    onClick=function()
                        SaveLoadoutLayout(loID, nil, nil)
                        self:SetText("|cFFAAAAAA(none)|r")
                        ClosePopups()
                    end }
                for li2, layInfo in ipairs(GetLayoutsRaw()) do
                    local capI = li2
                    local capN = layInfo.layoutName or ("Layout "..li2)
                    local capSelf = self
                    rows2[#rows2+1] = { text=capN,
                        onClick=function()
                            SaveLoadoutLayout(loID, capI, capN)
                            capSelf:SetText(capN)
                            ClosePopups()
                        end }
                end
                ShowPopup(loPopup, self, rows2)
            end)
        end

        -- Equip set button
        row.eqBtn:ClearAllPoints()
        row.eqBtn:SetPoint("TOPLEFT", alsContent, "TOPLEFT", 525, y)
        local eqRule = GetLoadoutEquip(lo.id)
        row.eqBtn:SetText(eqRule and eqRule.equipSetName or "|cFFAAAAAA(none)|r")
        row.eqBtn:Show()

        if not row.eqBtn._scriptSet then
            row.eqBtn._scriptSet = true
            row.eqBtn:SetScript("OnClick", function(self)
                local loID = self._loID
                local rows3 = {}
                rows3[#rows3+1] = { text="|cFFAAAAAA(none)|r", muted=true,
                    onClick=function()
                        SaveLoadoutEquip(loID, nil, nil)
                        self:SetText("|cFFAAAAAA(none)|r")
                        ClosePopups()
                    end }
                for _, es in ipairs(GetAllEquipmentSets()) do
                    local capEs = es
                    local capSelf = self
                    rows3[#rows3+1] = { text=es.name,
                        onClick=function()
                            SaveLoadoutEquip(loID, capEs.id, capEs.name)
                            capSelf:SetText(capEs.name)
                            ClosePopups()
                        end }
                end
                ShowPopup(eqPopup, self, rows3)
            end)
        end
        
        y = y - 24  -- Move down for next loadout row
    end
end

local function WrapAlsEvent(eventName)
    return function(...) OnAlsEvent(eventName) end
end

API.RegisterEvent("SmartSwap", "PLAYER_LOGIN",                         WrapAlsEvent("PLAYER_LOGIN"))
API.RegisterEvent("SmartSwap", "PLAYER_ENTERING_WORLD",                WrapAlsEvent("PLAYER_ENTERING_WORLD"))
API.RegisterEvent("SmartSwap", "ZONE_CHANGED_NEW_AREA",                WrapAlsEvent("ZONE_CHANGED_NEW_AREA"))
API.RegisterEvent("SmartSwap", "CHALLENGE_MODE_START",                 WrapAlsEvent("CHALLENGE_MODE_START"))
API.RegisterEvent("SmartSwap", "GROUP_ROSTER_UPDATE",                  WrapAlsEvent("GROUP_ROSTER_UPDATE"))
API.RegisterEvent("SmartSwap", "PLAYER_SPECIALIZATION_CHANGED",        WrapAlsEvent("PLAYER_SPECIALIZATION_CHANGED"))
API.RegisterEvent("SmartSwap", "ACTIVE_PLAYER_SPECIALIZATION_CHANGED", WrapAlsEvent("ACTIVE_PLAYER_SPECIALIZATION_CHANGED"))
API.RegisterEvent("SmartSwap", "PLAYER_REGEN_ENABLED",                 WrapAlsEvent("PLAYER_REGEN_ENABLED"))
API.RegisterEvent("SmartSwap", "TRAIT_CONFIG_UPDATED",                 WrapAlsEvent("TRAIT_CONFIG_UPDATED"))
API.RegisterEvent("SmartSwap", "PLAYER_FLAGS_CHANGED",                 WrapAlsEvent("PLAYER_FLAGS_CHANGED"))

-- Register tab via unified system (replaces alsTabEvents frame)
local alsTabLoginFired = false
API.RegisterEvent("SmartSwap", "PLAYER_LOGIN", function()
    if alsTabLoginFired then return end
    alsTabLoginFired = true
    if API.IsTabEnabled and not API.IsTabEnabled("SmartSwap") then return end
    C_Timer.After(0.1, function()
        if not API.RegisterTab then return end
        API.RegisterTab("SmartSwap", alsFrame, RefreshPanel, 70, nil, 7)
    end)
end)

API.ALSTryActivitySwap    = TryActivitySwap
API.ALSGetActiveLoadoutID = GetActiveLoadoutID

-- Re-apply rules when the user hits Save in the main window, so changes to
-- activity/loadout rules take effect immediately without a reload or zone change.
if API.RegisterPreSaveCallback then
    API.RegisterPreSaveCallback(function()
        ClearHandledActivities()
        C_Timer.After(0.1, function()
            local result = TryActivitySwap()
            if result ~= false then
                local lo = GetActiveLoadoutID()
                if lo then ApplyLoadoutSideEffects(lo, "Settings saved") end
            end
        end)
    end)
end

API.Debug("[RogUI] SmartSwap loaded.")
