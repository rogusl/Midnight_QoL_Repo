-- ============================================================
-- MidnightQoL_BuffAlerts / BuffAlerts.lua
-- CooldownViewer hook, visual alert pool, glow system,
-- spec-profile save/load for tracked buffs/debuffs/externals.
-- ============================================================

local API = MidnightQoLAPI

-- ── State ─────────────────────────────────────────────────────────────────────
local trackedBuffs     = {}
--[[ DEBUFFS/EXTERNALS DISABLED — for future development
local trackedDebuffs   = {}
local trackedExternals = {}
--]]

local activeAlerts     = {}
-- Alerts triggered by the buff-viewer OnShow/OnHide hook.
-- Only OnBuffViewerFrameHide may dismiss these.
local buffViewerAlerts = {}

-- Expose on API so BuffAlertsUI and Layout mode can access them
API.trackedBuffs     = trackedBuffs
--[[ DEBUFFS/EXTERNALS DISABLED — for future development
API.trackedDebuffs   = trackedDebuffs
API.trackedExternals = trackedExternals
--]]


local buffDebuffAlertsEnabled = true

-- Declared here (used by buff hook section below)
local buffHookedFrames = {}

-- Stack tracking removed: buffs are tracked purely via CooldownViewer/BuffTracker
-- frame show/hide. No C_UnitAuras stack reads, no count cache.

-- ── Spell list helpers (used by spell picker) ─────────────────────────────────
local function GetClassSpellList(listType)
    local map = {
        WARRIOR    = WarriorSpells,    PALADIN  = PaladinSpells,
        HUNTER     = HunterSpells,     ROGUE    = RogueSpells,
        PRIEST     = PriestSpells,     DRUID    = DruidSpells,
        SHAMAN     = ShamanSpells,     MAGE     = MageSpells,
        WARLOCK    = WarlockSpells,    DEATHKNIGHT = DeathKnightSpells,
        DEMONHUNTER = DemonHunterSpells, MONK   = MonkSpells,
        EVOKER     = EvokerSpells,
    }
    local t = map[API.playerClass or ""]
    -- Spell files use plural keys ("buffs"/"debuffs"); auraType is singular ("buff"/"debuff")
    local key = (listType == "buff") and "buffs" or (listType == "debuff") and "debuffs" or listType
    return (t and t[key]) or {}
end

local function GetAvailableSpells(listType)
    local available = {}
    if listType == "external" then
        if ExternalBuffSpells then
            for _, spell in ipairs(ExternalBuffSpells) do
                if spell.ids then table.insert(available, {id=spell.ids[1], ids=spell.ids, name=spell.name})
                else table.insert(available, {id=spell.id, name=spell.name}) end
            end
        end
    else
        -- Universal presets shown for all classes at the top of the buff list
        if listType == "buff" then
            table.insert(available, {
                id            = 57723,
                name          = "Lust / Sated (all variants)",
                isLustTracker = true,
            })
        end
        for _, spell in ipairs(GetClassSpellList(listType)) do
            table.insert(available, {id=spell.id, name=spell.name})
        end
    end
    return available
end
API.GetAvailableSpells = GetAvailableSpells

-- ── Spec profile callbacks ─────────────────────────────────────────────────────
local function OnSaveProfile(profile)
    profile.trackedBuffs     = trackedBuffs
--[[ DEBUFFS/EXTERNALS DISABLED — for future development
    profile.trackedDebuffs   = trackedDebuffs
    profile.trackedExternals = trackedExternals
--]]

    profile.buffDebuffAlertsEnabled = buffDebuffAlertsEnabled
    -- Keep legacy flat keys for backward compat
    if BuffAlertDB then
        BuffAlertDB.trackedBuffs     = trackedBuffs
--[[ DEBUFFS/EXTERNALS DISABLED — for future development
        BuffAlertDB.trackedDebuffs   = trackedDebuffs
        BuffAlertDB.trackedExternals = trackedExternals
--]]

        BuffAlertDB.buffDebuffAlertsEnabled = buffDebuffAlertsEnabled
    end
end

local function OnLoadProfile(profile)
    -- Wipe and repopulate the SAME table objects so all upvalue references stay valid
    for k in pairs(trackedBuffs)     do trackedBuffs[k]     = nil end
--[[ DEBUFFS/EXTERNALS DISABLED — for future development
    for k in pairs(trackedDebuffs)   do trackedDebuffs[k]   = nil end
    for k in pairs(trackedExternals) do trackedExternals[k] = nil end
--]]


    for _, v in ipairs(profile.trackedBuffs     or {}) do table.insert(trackedBuffs,     v) end
--[[ DEBUFFS/EXTERNALS DISABLED — for future development
    for _, v in ipairs(profile.trackedDebuffs   or {}) do table.insert(trackedDebuffs,   v) end
    for _, v in ipairs(profile.trackedExternals or {}) do table.insert(trackedExternals, v) end
--]]


    -- Migrate: old default alertDuration of 3 was saved before "0 = stay forever" behaviour.
    -- Clear it to 0 so buff-viewer-owned alerts stay up until the buff actually falls off.
    local function stripOldDuration(list)
        for _, aura in ipairs(list) do
            if aura.alertDuration == 3 then aura.alertDuration = 0 end
        end
    end
    stripOldDuration(trackedBuffs)
--[[ DEBUFFS/EXTERNALS DISABLED — for future development
    stripOldDuration(trackedDebuffs)
    stripOldDuration(trackedExternals)
--]]


    local savedEnabled = profile.buffDebuffAlertsEnabled
    if savedEnabled == nil then
        savedEnabled = BuffAlertDB and BuffAlertDB.buffDebuffAlertsEnabled
    end
    buffDebuffAlertsEnabled = (savedEnabled == true)
    if API.buffAlertEnabledCheckbox then
        API.buffAlertEnabledCheckbox:SetChecked(buffDebuffAlertsEnabled)
    end
    -- Refresh UI if open
    if API.RefreshAuraListUI then API.RefreshAuraListUI() end
    -- Rebuild spell→CooldownID map for new profile data
    C_Timer.After(0.1, function() if API.RebuildNameMap then API.RebuildNameMap() end end)
end

API.RegisterProfileCallbacks(OnSaveProfile, OnLoadProfile)

-- Also watch the feature toggle checkbox
local function SyncFeatureToggle()
    if not API.buffAlertEnabledCheckbox then return end
    buffDebuffAlertsEnabled = API.buffAlertEnabledCheckbox:GetChecked()
    if BuffAlertDB then BuffAlertDB.buffDebuffAlertsEnabled = buffDebuffAlertsEnabled end
end
-- Hook fires after Core's checkbox exists (it's created before sub-addons load via TOC order)
if API.buffAlertEnabledCheckbox then
    API.buffAlertEnabledCheckbox:HookScript("OnClick", SyncFeatureToggle)
end

-- ── Visual alert overlay pool ─────────────────────────────────────────────────
local ALERT_POOL_SIZE = 8
local alertPool       = {}
local activeOverlays  = {}

local function CreateAlertOverlayFrame(i)
    local f = CreateFrame("Frame","MidnightQoLAlertOverlay"..i, UIParent)
    f:SetFrameStrata("FULLSCREEN_DIALOG"); f:SetFrameLevel(100)
    f:SetSize(64,64); f:SetPoint("CENTER",UIParent,"CENTER",0,0); f:Hide()
    local tex = f:CreateTexture(nil,"ARTWORK",nil,7); tex:SetAllPoints(f)
    tex:SetTexCoord(0.08,0.92,0.08,0.92); f.tex = tex
    local cd = CreateFrame("Cooldown",nil,f,"CooldownFrameTemplate")
    cd:SetAllPoints(f); cd:SetDrawEdge(false); cd:SetHideCountdownNumbers(false); f.cooldown = cd
    f:SetScript("OnShow", function(self) self:SetAlpha(0); UIFrameFadeIn(self,0.15,0,1) end)
    f.sourceFrame = nil
    return f
end

-- ── Progress bar alert pool ───────────────────────────────────────────────────
local BAR_POOL_SIZE = 8
local barAlertPool  = {}

local function CreateAlertBarFrame(i)
    local f = CreateFrame("Frame","MidnightQoLAlertBar"..i, UIParent)
    f:SetFrameStrata("FULLSCREEN_DIALOG"); f:SetFrameLevel(100)
    f:SetSize(200, 26); f:SetPoint("CENTER",UIParent,"CENTER",0,0); f:Hide()

    -- Outer border (1px darker rim)
    local border = f:CreateTexture(nil,"BACKGROUND",nil,-1)
    border:SetAllPoints(f); border:SetColorTexture(0,0,0,0.9); f.border = border

    -- Dark background inset
    local bg = f:CreateTexture(nil,"BACKGROUND")
    bg:SetPoint("TOPLEFT",f,"TOPLEFT",1,-1)
    bg:SetPoint("BOTTOMRIGHT",f,"BOTTOMRIGHT",-1,1)
    bg:SetColorTexture(0.05,0.05,0.05,0.85); f.bg = bg

    -- Solid colour fill bar — uses a plain white texture so SetStatusBarColor
    -- gives a fully saturated, untextured solid fill with no fading atlas
    local bar = CreateFrame("StatusBar", nil, f)
    bar:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
    bar:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)
    local barTex = bar:CreateTexture(nil,"ARTWORK")
    barTex:SetColorTexture(1,1,1,1)
    bar:SetStatusBarTexture(barTex)
    bar:SetMinMaxValues(0, 1); bar:SetValue(1)
    bar:SetStatusBarColor(0.2, 0.8, 1, 1)
    f.bar = bar
    f.barTex = barTex

    -- Subtle gloss/shine strip across the top third
    local gloss = f:CreateTexture(nil,"OVERLAY")
    gloss:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
    gloss:SetPoint("TOPRIGHT", f, "TOPRIGHT", -1, 0)
    gloss:SetHeight(4)
    gloss:SetColorTexture(1,1,1,0.08); f.gloss = gloss

    -- Spell icon on the left (square, fills height)
    local iconBg = f:CreateTexture(nil,"ARTWORK")
    iconBg:SetPoint("TOPLEFT",f,"TOPLEFT",1,-1)
    iconBg:SetPoint("BOTTOMLEFT",f,"BOTTOMLEFT",1,1)
    iconBg:SetWidth(24); iconBg:SetColorTexture(0,0,0,0.5); f.iconBg = iconBg

    local icon = f:CreateTexture(nil,"ARTWORK",nil,1); icon:SetSize(22,22)
    icon:SetPoint("CENTER", iconBg, "CENTER", 0, 0)
    icon:SetTexCoord(0.08,0.92,0.08,0.92); f.icon = icon

    -- Thin separator between icon and bar
    local sep = f:CreateTexture(nil,"OVERLAY")
    sep:SetPoint("TOPLEFT",f,"TOPLEFT",25,-1)
    sep:SetPoint("BOTTOMLEFT",f,"BOTTOMLEFT",25,1)
    sep:SetWidth(1); sep:SetColorTexture(0,0,0,0.6); f.sep = sep

    -- Spell name label (left, after icon)
    local nameStr = f:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    nameStr:SetPoint("LEFT", f, "LEFT", 32, 0)
    nameStr:SetPoint("RIGHT", f, "RIGHT", -34, 0)
    nameStr:SetJustifyH("LEFT")
    nameStr:SetFont(nameStr:GetFont(), 11, "OUTLINE")
    nameStr:SetTextColor(1,1,1,1)
    f.nameStr = nameStr

    -- Stack count on the right
    local stackStr = f:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    stackStr:SetPoint("RIGHT", f, "RIGHT", -4, 0)
    stackStr:SetJustifyH("RIGHT")
    stackStr:SetFont(stackStr:GetFont(), 12, "OUTLINE")
    stackStr:SetTextColor(1,1,0,1)
    f.stackStr = stackStr

    -- Timer text (remaining seconds, shown when duration is known)
    local timerStr = f:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    timerStr:SetPoint("RIGHT", f, "RIGHT", -4, 0)
    timerStr:SetJustifyH("RIGHT")
    timerStr:SetFont(timerStr:GetFont(), 10, "OUTLINE")
    timerStr:SetTextColor(0.9,0.9,0.9,0.8)
    timerStr:Hide()
    f.timerStr = timerStr

    -- No fade-in: just appear immediately at full alpha
    f:SetAlpha(1)
    f.sourceFrame = nil
    f.progressTimer = nil
    return f
end

for i = 1, BAR_POOL_SIZE do barAlertPool[i] = CreateAlertBarFrame(i) end

local function GetFreeBarAlertFrame()
    for _, f in ipairs(barAlertPool) do if not f:IsShown() then return f end end
    barAlertPool[1]:Hide(); return barAlertPool[1]
end

for i = 1, ALERT_POOL_SIZE do alertPool[i] = CreateAlertOverlayFrame(i) end

local function GetFreeAlertFrame()
    for _, f in ipairs(alertPool) do if not f:IsShown() then return f end end
    alertPool[1]:Hide(); return alertPool[1]
end

local function ReleaseOverlay(alertKey)
    local f = activeOverlays[alertKey]; if not f then return end
    activeOverlays[alertKey] = nil
    if f.sourceFrame then f.sourceFrame:SetAlpha(1); f.sourceFrame = nil end
    -- Cancel all timers
    if f.durationTimer then f.durationTimer:Cancel(); f.durationTimer = nil end
    if f.progressTimer then f.progressTimer:Cancel(); f.progressTimer = nil end
    if f.cooldown then
        -- Icon mode: fade out smoothly
        f.cooldown:Clear()
        UIFrameFadeOut(f, 0.2, f:GetAlpha(), 0)
        C_Timer.After(0.2, function() f:Hide() end)
    else
        -- Bar mode: clear OnUpdate and snap off immediately
        f:SetScript("OnUpdate", nil)
        f.lastCount = nil
        f:Hide()
    end
end

local function ShowAlertOverlay(aura, spellName, sourceFrame)
    -- Bar mode
    if aura.alertMode == "bar" then
        local sz   = tonumber(aura.alertSize)     or 26
        local barW = tonumber(aura.alertBarWidth)  or 200
        local ox   = tonumber(aura.alertX)         or 0
        local oy   = tonumber(aura.alertY)         or 0
        local f    = GetFreeBarAlertFrame()
        f:SetSize(barW, sz); f:ClearAllPoints()
        f:SetPoint("CENTER", UIParent, "CENTER", ox, oy)
        f:SetAlpha(1)

        local br = tonumber(aura.barR) or 0.2
        local bg_ = tonumber(aura.barG) or 0.8
        local bb  = tonumber(aura.barB) or 1.0
        f.bar:SetStatusBarColor(br, bg_, bb, 1.0)

        local iconTex
        if aura.spellId and aura.spellId > 0 then
            local info = C_Spell.GetSpellInfo(aura.spellId)
            iconTex = info and info.iconID
        end
        f.icon:SetTexture(iconTex or "Interface\\Icons\\INV_Misc_QuestionMark")
        f.nameStr:SetText(spellName or "")
        f.stackStr:SetText(""); f.stackStr:Hide()
        f.sourceFrame = sourceFrame

        if f.durationTimer then f.durationTimer:Cancel(); f.durationTimer = nil end
        if f.progressTimer then f.progressTimer:Cancel(); f.progressTimer = nil end
        f:SetScript("OnUpdate", nil)
        f.lastCount = nil

        -- Duration drain: bar drains from full → 0 over the aura's lifetime.
        -- Read duration OOC only; in combat the bar stays full (we have no safe
        -- way to get expiration time without C_UnitAuras).
        local totalDur, remaining
        if aura.spellId and aura.spellId > 0 and not InCombatLockdown() then
            local ok, auraData = pcall(C_UnitAuras.GetPlayerAuraBySpellID, aura.spellId)
            if ok and auraData and auraData.duration and auraData.duration > 0 then
                totalDur  = auraData.duration
                remaining = auraData.expirationTime - GetTime()
            end
        end
        if totalDur and totalDur > 0 and remaining and remaining > 0 then
            f.bar:SetMinMaxValues(0, totalDur)
            f.bar:SetValue(remaining)
            f.progressTimer = C_Timer.NewTicker(0.1, function()
                if not f:IsShown() then f.progressTimer:Cancel(); f.progressTimer = nil; return end
                if InCombatLockdown() then return end
                local ok2, ad2 = pcall(C_UnitAuras.GetPlayerAuraBySpellID, aura.spellId)
                if ok2 and ad2 and ad2.expirationTime and ad2.expirationTime > 0 then
                    local timeLeft = ad2.expirationTime - GetTime()
                    f.bar:SetMinMaxValues(0, ad2.duration > 0 and ad2.duration or totalDur)
                    f.bar:SetValue(math.max(0, timeLeft))
                end
            end)
        else
            f.bar:SetMinMaxValues(0, 1); f.bar:SetValue(1)
        end

        f:Show()
        local dur = tonumber(aura.alertDuration)
        if dur and dur > 0 and dur < 9999 and not f.boundToHandle then
            f.durationTimer = C_Timer.NewTimer(dur, function()
                f.durationTimer = nil
                if f:IsShown() and not f.boundToHandle then f:Hide() end
            end)
        end
        return f
    end

    -- Icon mode (default)
    if not aura or not aura.alertTexture or aura.alertTexture == "" then return end
    local texVal = tostring(aura.alertTexture)
    if texVal == "spell_icon" then
        if aura.spellId and aura.spellId > 0 then
            local info = C_Spell.GetSpellInfo(aura.spellId)
            texVal = info and tostring(info.iconID) or "Interface\\Icons\\INV_Misc_QuestionMark"
        else texVal = "Interface\\Icons\\INV_Misc_QuestionMark" end
    else
        local shorthand = texVal:match("^spell:(%d+)$")
        if shorthand then
            local info = C_Spell.GetSpellInfo(tonumber(shorthand))
            texVal = info and tostring(info.iconID) or texVal
        end
    end
    local texArg = tonumber(texVal) or texVal
    local sz = tonumber(aura.alertSize) or 64
    local ox = tonumber(aura.alertX)   or 0
    local oy = tonumber(aura.alertY)   or 0
    local f  = GetFreeAlertFrame()
    f:SetSize(sz,sz); f:ClearAllPoints(); f:SetPoint("CENTER",UIParent,"CENTER",ox,oy)
    f.tex:SetTexture(texArg); f.sourceFrame = sourceFrame; f.cooldown:Clear(); f:Show()
    -- No stack text on icon overlays
    if f.stackText then f.stackText:SetText("") end
    if f.durationTimer then f.durationTimer:Cancel(); f.durationTimer = nil end
    local dur = tonumber(aura.alertDuration)
    if dur and dur > 0 and dur < 9999 and not f.boundToHandle then
        f.durationTimer = C_Timer.NewTimer(dur, function()
            f.durationTimer = nil
            if f:IsShown() and not f.boundToHandle then
                UIFrameFadeOut(f, 0.4, f:GetAlpha(), 0)
                C_Timer.After(0.4, function() if not f.boundToHandle then f:Hide() end end)
            end
        end)
    end
    return f
end

API.ShowAlertOverlay = ShowAlertOverlay
API._hideAlertPreviewsBase = function()
    for _, f in ipairs(alertPool) do
        if f.durationTimer then f.durationTimer:Cancel(); f.durationTimer = nil end
        f.cooldown:Clear(); f.boundToHandle = nil; f:Hide(); f.sourceFrame = nil
    end
    for _, f in ipairs(barAlertPool) do
        if f.durationTimer then f.durationTimer:Cancel(); f.durationTimer = nil end
        if f.progressTimer then f.progressTimer:Cancel(); f.progressTimer = nil end
        f.boundToHandle = nil; f:Hide(); f.sourceFrame = nil
    end
end

-- ── Glow system ────────────────────────────────────────────────────────────────
local spellGlowFrames = {}

local function CreateGlowFrame(r, g, b)
    -- Parent to UIParent temporarily; will be re-anchored to the alert overlay at ShowGlow time.
    local glow = CreateFrame("Frame", nil, UIParent)
    glow:SetFrameStrata("FULLSCREEN_DIALOG")
    glow:SetFrameLevel(200)
    glow:SetSize(64, 64)
    glow:Hide()
    local function makeEdge(point, relPoint, w, h)
        local t = glow:CreateTexture(nil, "OVERLAY")
        t:SetTexture("Interface\\SpellActivationOverlay\\IconAlert")
        t:SetTexCoord(0, 1, 0, 0.5); t:SetVertexColor(r, g, b, 0.85); t:SetSize(w, h)
        t:SetPoint(point, glow, relPoint, 0, 0)
    end
    makeEdge("TOP","TOP",64,16); makeEdge("BOTTOM","BOTTOM",64,16)
    makeEdge("LEFT","LEFT",16,64); makeEdge("RIGHT","RIGHT",16,64)
    local ag = glow:CreateAnimationGroup(); ag:SetLooping("BOUNCE")
    local anim = ag:CreateAnimation("Alpha"); anim:SetFromAlpha(0.4); anim:SetToAlpha(1.0)
    anim:SetDuration(0.6); anim:SetSmoothing("IN_OUT"); glow.animGroup = ag
    function glow:ShowGlow(anchorFrame)
        -- Anchor to the alert overlay so the glow sits on top of it.
        -- Fall back to a sensible screen position if no anchor is given.
        self:ClearAllPoints()
        if anchorFrame and anchorFrame.IsShown and anchorFrame:IsShown() then
            self:SetParent(anchorFrame)
            self:SetAllPoints(anchorFrame)
        else
            self:SetParent(UIParent)
            self:SetPoint("CENTER", UIParent, "CENTER", 0, -100)
            self:SetSize(64, 64)
        end
        self:Show(); self.animGroup:Play()
    end
    function glow:HideGlow()
        self.animGroup:Stop()
        self:Hide()
    end
    return glow
end

local function GetOrCreateGlowForAura(aura)
    local sid = aura.spellId; if not sid or sid <= 0 then return nil end
    if spellGlowFrames[sid] then return spellGlowFrames[sid] end
    local r, g, b = 1, 0.8, 0
    if aura.glowColor then r=aura.glowColor[1] or r; g=aura.glowColor[2] or g; b=aura.glowColor[3] or b end
    local gf = CreateGlowFrame(r, g, b)
    spellGlowFrames[sid] = gf; return gf
end

-- ── CooldownViewer hook ────────────────────────────────────────────────────────
local HookBuffViewerPanels       -- forward declaration
local IsBuffViewerFrameShowing
local cidToEntry = {}
local sidToEntry = {}
local hookedFrames       = {}
local pendingHide        = {}

local function OnCooldownViewerFrameShow(self)
    if not buffDebuffAlertsEnabled then return end
    local cid = self.cooldownID; if not cid then return end
    local entry = cidToEntry[cid]
    if not entry then
        -- CID not in map yet — try to resolve by spell ID and cache for next time
        local spellID
        pcall(function()
            local ci = self.cooldownInfo
            if ci then spellID = ci.overrideSpellID or ci.spellID end
        end)
        if spellID and sidToEntry[spellID] then
            entry = sidToEntry[spellID]; cidToEntry[cid] = entry
        end
    end
    if not entry or entry.aura.enabled == false then return end
    local alertKey = entry.alertKey
    pendingHide[alertKey] = nil
    -- Don't hide buff-section frames — they show the active buff icon and
    -- should remain visible while the buff is up. Only hide pure cooldown frames.
    if not buffHookedFrames[self] then self:SetAlpha(0) end
    if activeAlerts[alertKey] then return end
    activeAlerts[alertKey] = true
    local spellName = ""
    local ok, sinfo = pcall(C_Spell.GetSpellInfo, entry.sid)
    if ok and sinfo then spellName = sinfo.name or "" end
    if entry.aura.sound then API.PlayCustomSound(entry.aura.sound, entry.aura.soundIsID) end
    local overlay = ShowAlertOverlay(entry.aura, spellName, self)
    if overlay then activeOverlays[alertKey] = overlay end
    if API.DEBUG then print(entry.color .. "[MidnightQoL]|r " .. entry.label .. ": " .. spellName) end
    if entry.aura.glowEnabled then
        local gf = GetOrCreateGlowForAura(entry.aura); if gf then gf:ShowGlow(overlay) end
    end
end

local function OnCooldownViewerFrameHide(self)
    local cid = self.cooldownID; if not cid then return end
    local entry = cidToEntry[cid]; if not entry then return end
    local alertKey = entry.alertKey
    if not activeAlerts[alertKey] then return end
    self:SetAlpha(1)
    pendingHide[alertKey] = true
    C_Timer.After(0.1, function()
        if not pendingHide[alertKey] then return end
        pendingHide[alertKey] = nil
        activeAlerts[alertKey] = nil
        ReleaseOverlay(alertKey)
        local gf = spellGlowFrames[alertKey]; if gf then gf:HideGlow() end
    end)
end

local function HookItemFrame(frame)
    if hookedFrames[frame] then return end
    if not frame.cooldownID then return end
    hookedFrames[frame] = true
    frame:HookScript("OnShow", OnCooldownViewerFrameShow)
    frame:HookScript("OnHide",  OnCooldownViewerFrameHide)
end

local function RebuildNameMap()
    cidToEntry = {}; sidToEntry = {}

    -- Register a spell ID strictly by SID and CID — no name fallback.
    -- Name-based matching caused cross-spell collisions (e.g. Celestial Brew
    -- triggering a Fortifying Brew alert because both share "Brew" in their
    -- cooldown bucket name). Exact ID matching only.
    -- CID deduplication: if two tracked spells share a cooldown ID (same bucket),
    -- the first registration wins and the second is skipped for CID mapping.
    -- Both still exist in sidToEntry (debuff/external tracking disabled for now)
    local function addByID(sid, aura, label, color, alertKey)
        if not sid or sid <= 0 then return end
        if sidToEntry[sid] then return end  -- already registered
        local entry = {aura=aura, label=label, color=color, alertKey=alertKey, sid=sid}
        sidToEntry[sid] = entry
        local ok, cid = pcall(C_Spell.GetSpellCooldownID, sid)
        if ok and cid and cid > 0 then
            if not cidToEntry[cid] then cidToEntry[cid] = entry end
        end
    end

    for _, buff in ipairs(trackedBuffs) do
        if buff.enabled ~= false and buff.spellId and buff.spellId > 0 then
            addByID(buff.spellId, buff, "Gained", "|cFF00FF00", buff.spellId)
        end
    end
    --[[ DEBUFFS/EXTERNALS DISABLED — for future development
    for _, debuff in ipairs(trackedDebuffs) do
        if debuff.enabled ~= false and debuff.spellId and debuff.spellId > 0 then
            addByID(debuff.spellId, debuff, "Debuff", "|cFFFF0000", debuff.spellId)
        end
    end
    for _, ext in ipairs(trackedExternals) do
        if ext.enabled ~= false then
            local watchIds = (ext.spellIds and #ext.spellIds > 0) and ext.spellIds or {tonumber(ext.spellId)}
            local alertKey = tonumber(watchIds[1]) or 0
            for _, wid in ipairs(watchIds) do
                if wid and wid > 0 then
                    addByID(wid, ext, "External", "|cFF00CCFF", alertKey)
                end
            end
        end
    end
    --]]

    local panelNames = {
        "EssentialCooldownViewer","UtilityCooldownViewer","BuffIconCooldownViewer",
        "CooldownViewerSystem","CooldownViewerFrame","BuffAndEssentialCooldownViewer",
    }
    local hookCount = 0

    -- Map a frame CID to an entry using only exact spell-ID lookup.
    -- No name fallback — names are not unique enough to be safe.
    local function tryMapFrame(child)
        local cid = child.cooldownID
        if not cid then return end
        if cidToEntry[cid] then return end  -- already mapped
        local frameSpellID = child.rangeCheckSpellID
        if not frameSpellID then
            pcall(function()
                if child.cooldownInfo then
                    frameSpellID = child.cooldownInfo.overrideSpellID or child.cooldownInfo.spellID
                end
            end)
        end
        if frameSpellID and sidToEntry[frameSpellID] then
            cidToEntry[cid] = sidToEntry[frameSpellID]
        end
    end

    local function walkFrame(parent, depth)
        if not parent or depth > 4 then return end
        local ok, children = pcall(function() return {parent:GetChildren()} end)
        if not ok then return end
        for _, child in ipairs(children) do
            if child.cooldownID ~= nil then
                if not buffHookedFrames[child] then
                    HookItemFrame(child); hookCount = hookCount + 1
                    tryMapFrame(child)
                end
            else walkFrame(child, depth+1) end
        end
    end
    for _, name in ipairs(panelNames) do walkFrame(_G[name], 0) end
    if hookCount == 0 then
        for fname, fval in pairs(_G) do
            if type(fname)=="string" and fname:find("CooldownViewer")
               and type(fval)=="table" and type(fval.GetChildren)=="function" then
                walkFrame(fval, 0)
            end
        end
    end

    -- Restore CID mappings for frames hooked in previous calls
    -- (cidToEntry is wiped at the top of this function on every rebuild).
    for frame in pairs(hookedFrames) do
        local cid = frame.cooldownID
        if cid and not cidToEntry[cid] then
            tryMapFrame(frame)
        end
    end

    local cidCount = 0; for _ in pairs(cidToEntry) do cidCount = cidCount + 1 end
    API.Debug("RebuildNameMap: " .. cidCount .. " CIDs mapped, hookCount=" .. hookCount)
    lastHookCount = hookCount
    HookBuffViewerPanels()
end
API.RebuildNameMap = RebuildNameMap

-- ── Buff viewer panel hooks ────────────────────────────────────────────────────
-- These resolve the forward declarations at the top of the CooldownViewer section.

IsBuffViewerFrameShowing = function(sid)
    for frame in pairs(buffHookedFrames) do
        local fsid = frame.buffSpellID or frame.spellID
        if fsid == sid and frame:IsShown() then return true end
    end
    return false
end

local function OnBuffViewerFrameShow(self)
    if not buffDebuffAlertsEnabled then return end
    local sid = self.buffSpellID or self.spellID
    if not sid or sid <= 0 then return end
    -- Buff viewer frames: only process tracked buffs (not debuffs)
    local entry
    for _, aura in ipairs(trackedBuffs) do
        if aura.enabled ~= false and tonumber(aura.spellId) == sid then
            entry = aura; break
        end
    end
    if not entry then return end
    local alertKey = sid
    pendingHide[alertKey] = nil
    if activeAlerts[alertKey] then return end
    activeAlerts[alertKey] = true
    buffViewerAlerts[alertKey] = true
    local spellName = ""
    local ok, sinfo = pcall(C_Spell.GetSpellInfo, sid)
    if ok and sinfo then spellName = sinfo.name or "" end
    if entry.sound then API.PlayCustomSound(entry.sound, entry.soundIsID) end
    local overlay = ShowAlertOverlay(entry, spellName, self)
    if overlay then
        activeOverlays[alertKey] = overlay
        if overlay.durationTimer then overlay.durationTimer:Cancel(); overlay.durationTimer = nil end
    end
    if API.DEBUG then print("|cFF00FF00[MidnightQoL]|r Gained: " .. spellName) end
    if entry.glowEnabled then
        local gf = GetOrCreateGlowForAura(entry); if gf then gf:ShowGlow(overlay) end
    end
end

local function OnBuffViewerFrameHide(self)
    local sid = self.buffSpellID or self.spellID
    if not sid or sid <= 0 then return end
    local alertKey = sid
    if not activeAlerts[alertKey] then return end
    pendingHide[alertKey] = true
    C_Timer.After(0.3, function()
        if not pendingHide[alertKey] then return end
        pendingHide[alertKey] = nil
        activeAlerts[alertKey] = nil
        buffViewerAlerts[alertKey] = nil
        ReleaseOverlay(alertKey)
        local gf = spellGlowFrames[alertKey]; if gf then gf:HideGlow() end
    end)
end

local function HookBuffFrame(frame)
    if buffHookedFrames[frame] then return end
    buffHookedFrames[frame] = true
    frame:HookScript("OnShow", OnBuffViewerFrameShow)
    frame:HookScript("OnHide",  OnBuffViewerFrameHide)
end

local function resolveBuffSpellID(child)
    if child.buffSpellID and child.buffSpellID > 0 then return child.buffSpellID end
    if child.spellID and child.spellID > 0 then return child.spellID end
    local sid
    pcall(function()
        if child.cooldownInfo then
            sid = child.cooldownInfo.overrideSpellID or child.cooldownInfo.spellID
        end
    end)
    if sid and sid > 0 then return sid end
    if child.rangeCheckSpellID and child.rangeCheckSpellID > 0 then
        return child.rangeCheckSpellID
    end
    return nil
end

local hookedBuffPanels = {}

local function walkAndHookBuffPanel(parent, depth)
    if not parent or depth > 5 then return end
    local ok, children = pcall(function() return {parent:GetChildren()} end)
    if not ok then return end
    for _, child in ipairs(children) do
        local sid = resolveBuffSpellID(child)
        if sid then
            if not child.buffSpellID or child.buffSpellID == 0 then
                child.buffSpellID = sid
            end
            HookBuffFrame(child)
        else
            walkAndHookBuffPanel(child, depth + 1)
        end
    end
end

HookBuffViewerPanels = function()
    local panelNames = {
        "BuffIconCooldownViewer",
        "BuffAndEssentialCooldownViewer",
        "MidnightBuffViewer",
        "MidnightQoLBuffViewer",
    }
    for fname, fval in pairs(_G) do
        if type(fname) == "string" and fname:find("Buff") and fname:find("Viewer")
           and type(fval) == "table" and type(fval.GetChildren) == "function" then
            table.insert(panelNames, fname)
        end
    end

    for _, name in ipairs(panelNames) do
        local panel = _G[name]
        if panel then
            walkAndHookBuffPanel(panel, 0)
            -- Hook the panel's OnShow so new child frames created after startup
            -- (e.g. first time a buff appears) get hooked immediately
            if not hookedBuffPanels[name] then
                hookedBuffPanels[name] = true
                if panel.HookScript then
                    panel:HookScript("OnShow", function()
                        walkAndHookBuffPanel(panel, 0)
                    end)
                    -- Also hook each child's OnShow at the panel level via a ticker
                    -- fired once per second to catch newly materialised children
                end
            end
        end
    end
end
API.HookBuffViewerPanels = HookBuffViewerPanels
-- ── Buff lookup (CooldownViewer path only) ───────────────────────────────────
-- Buffs are tracked EXCLUSIVELY via CooldownViewer frame OnShow/OnHide hooks
-- and the PollBuffFrames in-combat ticker. No C_UnitAuras scanning for buffs.

local function FindTrackedEntry(sid)
    for _, aura in ipairs(trackedBuffs) do
        if aura.enabled ~= false and tonumber(aura.spellId) == sid then
            return aura, "Gained", "|cFF00FF00"
        end
    end
    return nil
end

--[[ FUTURE: Debuff tracking via UNIT_AURA + instanceID removal
-- Debuffs are whitelist-only: only spellIDs explicitly in trackedDebuffs fire alerts.

-- instanceID → spellId map so we can match removals back to a spell
local activeInstanceToSpell = {}

local function FindTrackedDebuff(sid)
    for _, aura in ipairs(trackedDebuffs) do
        if aura.enabled ~= false and tonumber(aura.spellId) == sid then
            return aura, "Debuff", "|cFFFF0000"
        end
    end
    return nil
end

local function BuildInstanceMap()
    if InCombatLockdown() then return end
    for _, aura in ipairs(trackedDebuffs) do
        if aura.enabled ~= false then
            local sid = tonumber(aura.spellId)
            if sid and sid > 0 then
                local ok, auraData = pcall(C_UnitAuras.GetPlayerAuraBySpellID, sid)
                if ok and auraData and auraData.auraInstanceID then
                    activeInstanceToSpell[auraData.auraInstanceID] = sid
                end
            end
        end
    end
end

local function ScanTrackedDebuffs()
    if InCombatLockdown() then return end
    for _, aura in ipairs(trackedDebuffs) do
        if aura.enabled ~= false then
            local sid = tonumber(aura.spellId)
            if sid and sid > 0 then
                local ok, auraData = pcall(C_UnitAuras.GetPlayerAuraBySpellID, sid)
                if ok and auraData then
                    if auraData.auraInstanceID then
                        activeInstanceToSpell[auraData.auraInstanceID] = sid
                    end
                    if not activeAlerts[sid] then FireAuraGained(sid) end
                else
                    FireAuraLost(sid)
                end
            end
        end
    end
end

local function FireAuraGained(sid)
    if not buffDebuffAlertsEnabled then return end
    local entry, label, color = FindTrackedDebuff(sid)
    if not entry then return end
    local alertKey = sid
    if activeAlerts[alertKey] then return end
    activeAlerts[alertKey] = true
    local spellName = ""
    local ok, sinfo = pcall(C_Spell.GetSpellInfo, sid)
    if ok and sinfo then spellName = sinfo.name or "" end
    if entry.sound then API.PlayCustomSound(entry.sound, entry.soundIsID) end
    local overlay = ShowAlertOverlay(entry, spellName, nil)
    if overlay then activeOverlays[alertKey] = overlay end
    if API.DEBUG then print(color .. "[MidnightQoL]|r " .. label .. ": " .. spellName) end
    if entry.glowEnabled then
        local gf = GetOrCreateGlowForAura(entry); if gf then gf:ShowGlow(overlay) end
    end
end

local function FireAuraLost(sid)
    local alertKey = sid
    if not activeAlerts[alertKey] then return end
    activeAlerts[alertKey] = nil
    buffViewerAlerts[alertKey] = nil
    ReleaseOverlay(alertKey)
    local gf = spellGlowFrames[alertKey]; if gf then gf:HideGlow() end
end
--]]

--[[ FUTURE: External defensive tracking via C_UnitAuras
-- A persistent HUD frame that tracks externals (buffs cast on the player by others).
-- Polls C_UnitAuras every 0.2s via a ticker that runs in and out of combat.

local function FindTrackedExternal(sid)
    for _, aura in ipairs(trackedExternals) do
        if aura.enabled ~= false then
            local wids = (aura.spellIds and #aura.spellIds > 0) and aura.spellIds or {tonumber(aura.spellId)}
            for _, wid in ipairs(wids) do
                if wid == sid then return aura, "External", "|cFF00CCFF" end
            end
        end
    end
    return nil
end

local function RefreshExternalFrame()
    local now = GetTime()
    for _, aura in ipairs(trackedExternals) do
        if aura.enabled ~= false then
            local wids = (aura.spellIds and #aura.spellIds > 0) and aura.spellIds or {tonumber(aura.spellId)}
            for _, sid in ipairs(wids) do
                if sid and sid > 0 then
                    local ok, auraData = pcall(C_UnitAuras.GetPlayerAuraBySpellID, sid)
                    if ok and auraData and auraData.expirationTime then
                        local remaining = auraData.expirationTime == 0 and math.huge or (auraData.expirationTime - now)
                        if remaining > 0 and not activeAlerts[sid] then
                            activeAlerts[sid] = true
                            if aura.sound then API.PlayCustomSound(aura.sound, aura.soundIsID) end
                            if API.DEBUG then
                                local dispName = aura.name or ("ID " .. sid)
                                print("|cFF00CCFF[MidnightQoL]|r External: " .. dispName)
                            end
                            if aura.glowEnabled then
                                local gf = GetOrCreateGlowForAura(aura); if gf then gf:ShowGlow() end
                            end
                        end
                    else
                        if activeAlerts[sid] then
                            activeAlerts[sid] = nil
                            local gf = spellGlowFrames[sid]; if gf then gf:HideGlow() end
                        end
                    end
                end
            end
        end
    end
end
--]]

local buffLossDebounce = {}  -- kept for PLAYER_REGEN_ENABLED cleanup loop

-- Stubs so call sites outside the block comments compile without error
local function BuildInstanceMap() end
local function ScanTrackedDebuffs() end
local function FireAuraGained(sid) end
local function FireAuraLost(sid) end
local function StartExternalTicker() end
local function ApplyExtFramePosition() end

-- ── In-combat buff visibility poller ─────────────────────────────────────────
-- Polls hooked buff-viewer frames every 0.1s in combat.
-- Buffs ONLY — debuffs are handled via UNIT_AURA OOC + instanceID removal in combat.
local combatPollTicker = nil
local buffFrameLastSeen = {}
local pollPendingHideTimers = {}

-- PollBuffFrames: polls buff-viewer frame visibility every 0.1s in combat.
-- OnShow/OnHide hooks are the primary trigger; this poll catches any frames that
-- change visibility between hook fires. Loss uses a 0.5s debounce so transient
-- hide/re-show cycles (absorb updates, stack refreshes) don't flicker.
local buffPollLossTimers = {}
local buffPollLastSeen   = {}

local function PollBuffFrames()
    if not buffDebuffAlertsEnabled then return end
    for frame in pairs(buffHookedFrames) do
        local sid = tonumber(frame.buffSpellID or frame.spellID)
        if sid and sid > 0 then
            local isBuff = false
            for _, aura in ipairs(trackedBuffs) do
                if aura.enabled ~= false and tonumber(aura.spellId) == sid then
                    isBuff = true; break
                end
            end
            if isBuff then
                local shown = frame:IsShown()
                if shown then
                    -- Cancel any pending loss
                    if buffPollLossTimers[sid] then
                        buffPollLossTimers[sid]:Cancel()
                        buffPollLossTimers[sid] = nil
                    end
                    pendingHide[sid] = nil
                    if not activeAlerts[sid] then
                        -- Inline gain — same logic as OnBuffViewerFrameShow
                        local entry
                        for _, a in ipairs(trackedBuffs) do
                            if a.enabled ~= false and tonumber(a.spellId) == sid then
                                entry = a; break
                            end
                        end
                        if entry then
                            activeAlerts[sid]     = true
                            buffViewerAlerts[sid] = true
                            local spellName = ""
                            local ok, sinfo = pcall(C_Spell.GetSpellInfo, sid)
                            if ok and sinfo then spellName = sinfo.name or "" end
                            if entry.sound then API.PlayCustomSound(entry.sound, entry.soundIsID) end
                            local overlay = ShowAlertOverlay(entry, spellName, frame)
                            if overlay then
                                activeOverlays[sid] = overlay
                                if overlay.durationTimer then overlay.durationTimer:Cancel(); overlay.durationTimer = nil end
                            end
                            if API.DEBUG then print("|cFF00FF00[MidnightQoL]|r Gained: " .. spellName) end
                            if entry.glowEnabled then
                                local gf = GetOrCreateGlowForAura(entry); if gf then gf:ShowGlow() end
                            end
                        end
                    end
                    buffPollLastSeen[frame] = true
                else
                    if buffPollLastSeen[frame] and not buffPollLossTimers[sid] then
                        -- Debounce loss: wait 0.5s then confirm still hidden
                        buffPollLossTimers[sid] = C_Timer.NewTimer(0.5, function()
                            buffPollLossTimers[sid] = nil
                            -- Only dismiss if no hooked frame for this sid is shown
                            local anyShown = false
                            for fr in pairs(buffHookedFrames) do
                                if (tonumber(fr.buffSpellID or fr.spellID) == sid) and fr:IsShown() then
                                    anyShown = true; break
                                end
                            end
                            if not anyShown and activeAlerts[sid] then
                                pendingHide[sid] = nil
                                activeAlerts[sid] = nil
                                buffViewerAlerts[sid] = nil
                                ReleaseOverlay(sid)
                                local gf = spellGlowFrames[sid]; if gf then gf:HideGlow() end
                            end
                        end)
                    end
                    buffPollLastSeen[frame] = false
                end
            end
        end
    end
end

local combatPollTick = 0

local function StartCombatPoll()
    if combatPollTicker then return end
    combatPollTick = 0
    for frame in pairs(buffHookedFrames) do
        buffFrameLastSeen[frame]   = frame:IsShown()
        buffPollLastSeen[frame]    = frame:IsShown()
    end
    combatPollTicker = C_Timer.NewTicker(0.1, function()
        combatPollTick = combatPollTick + 1
        -- Re-walk panels every 2s (every 20 ticks) to hook frames that
        -- appeared mid-combat (e.g. first cast of a buff while in combat)
        if combatPollTick % 20 == 0 then
            HookBuffViewerPanels()
            -- Seed any newly discovered frames
            for frame in pairs(buffHookedFrames) do
                if buffPollLastSeen[frame] == nil then
                    buffPollLastSeen[frame] = frame:IsShown()
                end
            end
        end
        PollBuffFrames()
    end)
end

local function StopCombatPoll()
    if combatPollTicker then combatPollTicker:Cancel(); combatPollTicker = nil end
    for key, timer in pairs(pollPendingHideTimers) do
        timer:Cancel(); pollPendingHideTimers[key] = nil
    end
end

local buffEvents = CreateFrame("Frame")
buffEvents:RegisterEvent("PLAYER_REGEN_DISABLED")
buffEvents:RegisterEvent("PLAYER_REGEN_ENABLED")
buffEvents:RegisterEvent("PLAYER_LOGIN")
buffEvents:RegisterEvent("UNIT_AURA")

-- Sated debuff IDs that signal lust was used. These are non-secret (debuffs, not buffs).
-- A buff entry with isLustTracker=true uses this table instead of a buff-viewer hook.
local SATED_DEBUFF_IDS = {
    [57723]=true, [57724]=true, [80354]=true,
    [95809]=true, [160455]=true, [264689]=true, [390435]=true,
}
local LUST_ALERT_KEY = 57723  -- canonical alert key for all sated variants
local lustDebuffActive = false

local function CheckLustDebuff()
    if not buffDebuffAlertsEnabled then return end
    -- Find a lust entry in trackedBuffs
    local lustEntry = nil
    for _, aura in ipairs(trackedBuffs) do
        if aura.isLustTracker and aura.enabled ~= false then
            lustEntry = aura; break
        end
    end
    if not lustEntry then return end

    -- Scan debuffs using C_UnitAuras (UnitDebuff removed in TWW)
    local foundSID = nil
    for spellId in pairs(SATED_DEBUFF_IDS) do
        local ok, auraData = pcall(C_UnitAuras.GetPlayerAuraBySpellID, spellId)
        if ok and auraData then foundSID = spellId; break end
    end

    if foundSID and not lustDebuffActive then
        lustDebuffActive = true
        activeAlerts[LUST_ALERT_KEY] = true
        local ok, sinfo = pcall(C_Spell.GetSpellInfo, foundSID)
        local spellName = (ok and sinfo and sinfo.name) or "Lust"
        if lustEntry.sound then API.PlayCustomSound(lustEntry.sound, lustEntry.soundIsID) end
        local overlay = ShowAlertOverlay(lustEntry, spellName, nil)
        if overlay then activeOverlays[LUST_ALERT_KEY] = overlay end
        if lustEntry.glowEnabled then
            local gf = GetOrCreateGlowForAura(lustEntry); if gf then gf:ShowGlow() end
        end
        if API.DEBUG then print("|cFFFF6600[MidnightQoL]|r Lust: " .. spellName) end
    elseif not foundSID and lustDebuffActive then
        lustDebuffActive = false
        activeAlerts[LUST_ALERT_KEY] = nil
        ReleaseOverlay(LUST_ALERT_KEY)
        local gf = spellGlowFrames[LUST_ALERT_KEY]; if gf then gf:HideGlow() end
    end
end
API.CheckLustDebuff  = CheckLustDebuff
API.LUST_ALERT_KEY   = LUST_ALERT_KEY
API.SATED_DEBUFF_IDS = SATED_DEBUFF_IDS

buffEvents:SetScript("OnEvent", function(self, event, unit, updateInfo)
    if event == "UNIT_AURA" then
        if unit == "player" then CheckLustDebuff() end
        return
    end
    if event == "PLAYER_LOGIN" then
        C_Timer.After(1, function()
            RebuildNameMap()
            HookBuffViewerPanels()
            C_Timer.After(0.5, function()
                if API.CheckCDMismatch then API.CheckCDMismatch() end
            end)
            C_Timer.After(2, function()
                RebuildNameMap()
                HookBuffViewerPanels()
            end)
        end)
    elseif event == "PLAYER_REGEN_DISABLED" then
        -- Re-walk buff panels before starting poll so any frames that appeared
        -- since login (e.g. first cast of a buff) are hooked before combat begins
        HookBuffViewerPanels()
        StartCombatPoll()
    elseif event == "PLAYER_REGEN_ENABLED" then
        StopCombatPoll()
        -- Cancel all pending poll loss timers
        for sid, timer in pairs(buffPollLossTimers) do
            timer:Cancel(); buffPollLossTimers[sid] = nil
        end
        HookBuffViewerPanels()
        -- Re-warm cooldown-viewer CID map
        local panelNames = {"EssentialCooldownViewer","UtilityCooldownViewer","BuffIconCooldownViewer",
            "CooldownViewerSystem","CooldownViewerFrame","BuffAndEssentialCooldownViewer"}
        local function warmFrame(parent, depth)
            if not parent or depth > 2 then return end
            local ok, children = pcall(function() return {parent:GetChildren()} end)
            if not ok then return end
            for _, child in ipairs(children) do
                if child.cooldownID ~= nil then
                    local cid = child.cooldownID
                    if not cidToEntry[cid] and child.cooldownInfo then
                        local spellID = child.cooldownInfo.overrideSpellID or child.cooldownInfo.spellID
                        if spellID and sidToEntry[spellID] then cidToEntry[cid] = sidToEntry[spellID] end
                    end
                else warmFrame(child, depth+1) end
            end
        end
        for _, name in ipairs(panelNames) do warmFrame(_G[name], 0) end
    end
end)

-- ── Also rebuild on spec change ────────────────────────────────────────────────
-- OnLoadProfile already schedules RebuildNameMap after 0.1s, no extra event needed.

-- ── CD Mismatch popup ─────────────────────────────────────────────────────────
local cdMismatchPopup = CreateFrame("Frame","CSCDMismatchPopup",UIParent,"BackdropTemplate")
cdMismatchPopup:SetSize(440,260); cdMismatchPopup:SetPoint("CENTER",UIParent,"CENTER",0,60)
cdMismatchPopup:SetFrameStrata("DIALOG")
cdMismatchPopup:SetBackdrop({bgFile="Interface/DialogFrame/UI-DialogBox-Background",
    edgeFile="Interface/DialogFrame/UI-DialogBox-Border",
    tile=true,tileSize=16,edgeSize=16,insets={left=8,right=8,top=8,bottom=8}})
cdMismatchPopup:SetBackdropColor(0.05,0.05,0.1,0.97)
cdMismatchPopup:SetMovable(true); cdMismatchPopup:EnableMouse(true)
cdMismatchPopup:RegisterForDrag("LeftButton")
cdMismatchPopup:SetScript("OnDragStart",function(self) if API.IsLayoutMode and API.IsLayoutMode() then self:StartMoving() end end)
cdMismatchPopup:SetScript("OnDragStop",function(self) self:StopMovingOrSizing() end)
cdMismatchPopup:Hide()

local cdMismatchText, cdMismatchContent
do
    local icon = cdMismatchPopup:CreateTexture(nil,"ARTWORK"); icon:SetSize(32,32)
    icon:SetPoint("TOPLEFT",14,-14); icon:SetTexture("Interface\\DialogFrame\\UI-Dialog-Icon-AlertOther")
    local titleStr = cdMismatchPopup:CreateFontString(nil,"OVERLAY","GameFontNormalLarge")
    titleStr:SetPoint("TOPLEFT",icon,"TOPRIGHT",8,0); titleStr:SetText("|cFFFFD700MidnightQoL — Action Required|r")
    local subtitle = cdMismatchPopup:CreateFontString(nil,"OVERLAY","GameFontNormal")
    subtitle:SetPoint("TOPLEFT",titleStr,"BOTTOMLEFT",0,-4); subtitle:SetTextColor(1,0.6,0.2,1)
    subtitle:SetText("Some tracked spells are missing from the Cooldown Manager and Buff Tracker")
    local scroll = CreateFrame("ScrollFrame","CSCDMismatchScroll",cdMismatchPopup,"UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT",12,-68); scroll:SetPoint("BOTTOMRIGHT",-30,40)
    cdMismatchContent = CreateFrame("Frame","CSCDMismatchContent",scroll)
    cdMismatchContent:SetSize(390,1); scroll:SetScrollChild(cdMismatchContent)
    cdMismatchText = cdMismatchContent:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    cdMismatchText:SetPoint("TOPLEFT",4,-4); cdMismatchText:SetWidth(382)
    cdMismatchText:SetJustifyH("LEFT"); cdMismatchText:SetJustifyV("TOP"); cdMismatchText:SetWordWrap(true)
    local dismissBtn = CreateFrame("Button",nil,cdMismatchPopup,"GameMenuButtonTemplate")
    dismissBtn:SetSize(100,24); dismissBtn:SetPoint("BOTTOMRIGHT",cdMismatchPopup,"BOTTOMRIGHT",-10,8)
    dismissBtn:SetText("Dismiss"); dismissBtn:SetScript("OnClick",function() cdMismatchPopup:Hide() end)
    local neverBtn = CreateFrame("Button",nil,cdMismatchPopup,"GameMenuButtonTemplate")
    neverBtn:SetSize(130,24); neverBtn:SetPoint("RIGHT",dismissBtn,"LEFT",-6,0); neverBtn:SetText("Don't show again")
    neverBtn:SetScript("OnClick",function()
        cdMismatchPopup:Hide()
        if BuffAlertDB then
            BuffAlertDB.cdMismatchSuppressed = true
            -- Save the current spell fingerprint so we re-show if the list changes
            local ids = {}
            local function collect(list)
                for _, a in ipairs(list) do
                    if a.enabled ~= false then
                        local sid = tonumber(a.spellId) or (a.spellIds and tonumber(a.spellIds[1]))
                        if sid and sid > 0 then table.insert(ids, sid) end
                    end
                end
            end
            collect(trackedBuffs)
            table.sort(ids)
            BuffAlertDB.cdMismatchFingerprint = table.concat(ids, ",")
        end
    end)
    local openBtn = CreateFrame("Button",nil,cdMismatchPopup,"GameMenuButtonTemplate")
    openBtn:SetSize(180,24); openBtn:SetPoint("BOTTOMLEFT",cdMismatchPopup,"BOTTOMLEFT",10,8)
    openBtn:SetText("[+] Open Cooldown Manager")
    openBtn:SetScript("OnClick",function()
        local opened = false
        if Settings and Settings.OpenToCategory then
            pcall(function() Settings.OpenToCategory("ActionBars"); opened=true end)
        end
        if not opened and InterfaceOptionsFrame_OpenToCategory then
            pcall(function() InterfaceOptionsFrame_OpenToCategory("ActionBars") end)
        elseif not opened and SettingsPanel then SettingsPanel:Show() end
        print("|cFFFFD700[MidnightQoL]|r Open the |cFF00CCFFCooldown Manager|r → click |cFF00CCFF+|r → add each missing spell.")
    end)
end

-- Track whether RebuildNameMap found any CooldownViewer frames
local lastHookCount = 0

local function CheckCDMismatch()
    -- Only run if we actually found CooldownViewer frames to hook into.
    -- If hookCount is 0, we can't distinguish "not in Cooldown Manager" from
    -- "Cooldown Manager frames not loaded yet" — so skip to avoid false positives.
    if lastHookCount == 0 then return end

    -- Build the fingerprint of currently-tracked spell IDs so we can detect
    -- if the spell list changed since the user clicked "Don't show again".
    local function makeFingerprint()
        local ids = {}
        local function collect(list)
            for _, a in ipairs(list) do
                if a.enabled ~= false then
                    local sid = tonumber(a.spellId) or (a.spellIds and tonumber(a.spellIds[1]))
                    if sid and sid > 0 then table.insert(ids, sid) end
                end
            end
        end
        collect(trackedBuffs)
        table.sort(ids)
        return table.concat(ids, ",")
    end

    local fp = makeFingerprint()
    if fp == "" then return end  -- nothing tracked

    -- If suppressed, only skip if the spell list hasn't changed since suppression
    if BuffAlertDB and BuffAlertDB.cdMismatchSuppressed then
        if BuffAlertDB.cdMismatchFingerprint == fp then return end
        -- Spell list changed — clear suppression and re-check
        BuffAlertDB.cdMismatchSuppressed = false
        BuffAlertDB.cdMismatchFingerprint = nil
    end

    -- Build a set of spell IDs that ARE covered by either the cooldown bar (sidToEntry)
    -- or the buff section poll (buffHookedFrames). Either one provides in-combat detection.
    local coveredSids = {}
    for sid in pairs(sidToEntry) do coveredSids[sid] = true end
    for frame in pairs(buffHookedFrames) do
        local fsid = frame.buffSpellID or frame.spellID
        if fsid then coveredSids[fsid] = true end
    end

    local missing = {}
    local function checkEntry(aura, category)
        if aura.enabled == false then return end
        local wids = (aura.spellIds and #aura.spellIds > 0) and aura.spellIds or {tonumber(aura.spellId)}
        -- An entry is covered if ANY of its watch IDs is in a tracked frame
        for _, sid in ipairs(wids) do
            if sid and sid > 0 and coveredSids[sid] then return end
        end
        -- None of the IDs are covered — report the primary one
        local sid = wids[1]; if not sid or sid <= 0 then return end
        local name = ""; local ok,info = pcall(C_Spell.GetSpellInfo, sid)
        if ok and info then name = info.name or ("Spell "..sid) end
        table.insert(missing, {sid=sid, name=name, category=category})
    end
    for _,b in ipairs(trackedBuffs)     do checkEntry(b,"Buff")     end
    if #missing == 0 then return end

    local lines = {
        "|cFFFF4444Warning:|r The following spells are not tracked in either the",
        "|cFF00CCFFCooldown Manager|r or the |cFF00CCFFBuff Tracker|r.\n",
        "This means they |cFFFF4444will not appear during combat|r — WoW restricts",
        "aura data to addons while fighting. Out-of-combat alerts will still work.\n",
        "|cFFFFD700How to fix:|r Open the Cooldown Manager (button below), click |cFF00CCFF+|r,",
        "and add each spell either as a |cFF00CCFFCooldown|r or a |cFF00CCFFBuff|r.\n",
    }
    for _,m in ipairs(missing) do
        table.insert(lines, string.format(
            "  |cFFFF8800[%s]|r  %s  |cFF999999(ID: %d)|r",
            m.category, m.name, m.sid))
    end
    cdMismatchText:SetText(table.concat(lines,"\n"))
    cdMismatchContent:SetHeight(math.max(180, cdMismatchText:GetStringHeight()+16))
    cdMismatchPopup:Show()
end
API.CheckCDMismatch = CheckCDMismatch

-- ── Layout handle provider ─────────────────────────────────────────────────────
API.RegisterLayoutHandles(function()
    local handles = {}
    local function addAuraHandles(list, typeLabel)
        for idx, aura in ipairs(list) do
            if aura.alertTexture and aura.alertTexture ~= "" then
                local ox = aura.alertX or 0; local oy = aura.alertY or 0
                local iconTex = aura.alertTexture
                if iconTex == "spell_icon" and aura.spellId and aura.spellId > 0 then
                    local info = C_Spell.GetSpellInfo(aura.spellId)
                    iconTex = info and info.iconID or "Interface\\Icons\\INV_Misc_QuestionMark"
                elseif iconTex:match("^spell:(%d+)$") then
                    local sid = tonumber(iconTex:match("^spell:(%d+)$"))
                    local info = sid and C_Spell.GetSpellInfo(sid)
                    iconTex = info and info.iconID or "Interface\\Icons\\INV_Misc_QuestionMark"
                end
                local spellName = "Unknown"
                if aura.spellId and aura.spellId > 0 then
                    local info = C_Spell.GetSpellInfo(aura.spellId)
                    spellName = info and info.name or ("ID "..aura.spellId)
                end
                local capturedAura = aura; local capturedIdx = idx; local capturedType = typeLabel:lower()
                local isBar = (aura.alertMode == "bar")
                -- liveFrameRef: the currently-showing overlay for this aura, if any.
                -- alertKey for both bar and icon mode is the spellId.
                local alertKey = tonumber(aura.spellId) or 0
                local liveFrame = (alertKey > 0) and activeOverlays[alertKey] or nil
                table.insert(handles, {
                    label        = typeLabel..": "..spellName,
                    iconTex      = iconTex,
                    ox           = ox, oy = oy,
                    liveFrameRef = liveFrame,
                    saveCallback = function(nx,ny)
                        capturedAura.alertX = nx; capturedAura.alertY = ny
                        local xBox = _G["BuffAlertTexX"..capturedType..capturedIdx]
                        local yBox = _G["BuffAlertTexY"..capturedType..capturedIdx]
                        if xBox then xBox:SetText(tostring(nx)) end
                        if yBox then yBox:SetText(tostring(ny)) end
                        if BuffAlertDB then API.SaveSpecProfile() end
                    end,
                    resizeCallback = function(nw, nh)
                        nw = math.max(40,  math.floor(nw + 0.5))
                        nh = math.max(8,   math.floor(nh + 0.5))
                        if isBar then
                            capturedAura.alertBarWidth = nw
                            capturedAura.alertSize     = nh
                            local wBox = _G["BuffAlertBarWidth"..capturedType..capturedIdx]
                            local hBox = _G["BuffAlertTexSize"..capturedType..capturedIdx]
                            if wBox then wBox:SetText(tostring(nw)) end
                            if hBox then hBox:SetText(tostring(nh)) end
                        else
                            -- Icon mode: keep square
                            local sz = math.max(nw, nh)
                            capturedAura.alertSize = sz
                            local szBox = _G["BuffAlertTexSize"..capturedType..capturedIdx]
                            if szBox then szBox:SetText(tostring(sz)) end
                        end
                        if BuffAlertDB then API.SaveSpecProfile() end
                    end,
                    previewFunc  = function()
                        return ShowAlertOverlay({
                            alertTexture=aura.alertTexture, spellId=aura.spellId,
                            alertMode=aura.alertMode, alertBarWidth=aura.alertBarWidth,
                            alertSize=aura.alertSize, alertDuration=9999,
                            alertX=aura.alertX or 0, alertY=aura.alertY or 0,
                        }, spellName)
                    end,
                })
            end
        end
    end
    addAuraHandles(trackedBuffs,    "Buff")
    return handles
end)

-- ── Slash commands ─────────────────────────────────────────────────────────────
SLASH_CUSTOMSOUNDSDEBUG1 = "/qoldebug"
SlashCmdList["CUSTOMSOUNDSDEBUG"] = function()
    print("|cFFFFFF00[MidnightQoL DEBUG]|r =============================")
    print("buffDebuffAlertsEnabled: "..tostring(buffDebuffAlertsEnabled))
    print("Tracked: buffs="..#trackedBuffs.."  (debuffs/externals disabled)")
    local cidCount=0; for _ in pairs(cidToEntry) do cidCount=cidCount+1 end
    print("CID map entries: "..cidCount)
    RebuildNameMap()
    print("|cFFFFFF00[MidnightQoL DEBUG]|r ============================= done")
end

SLASH_CSTRACK1 = "/qoltrack"
SlashCmdList["CSTRACK"] = function()
    print("|cFFFFFF00[MidnightQoL]|r Scanning visible CooldownViewer frames...")
    local found = {}
    local panelNames = {"EssentialCooldownViewer","UtilityCooldownViewer","BuffIconCooldownViewer",
        "CooldownViewerSystem","CooldownViewerFrame","BuffAndEssentialCooldownViewer"}
    local function scanFrame(parent, depth)
        if not parent or depth > 4 then return end
        local ok, children = pcall(function() return {parent:GetChildren()} end)
        if not ok then return end
        for _, child in ipairs(children) do
            if child.cooldownID ~= nil and child:IsShown() then
                local cid = child.cooldownID
                local frameSpellID = child.rangeCheckSpellID
                local ciSpellID; pcall(function()
                    if child.cooldownInfo then ciSpellID = child.cooldownInfo.overrideSpellID or child.cooldownInfo.spellID end
                end)
                local resolvedID = frameSpellID or ciSpellID
                local spellName = "?"
                if resolvedID then local nok,ninfo = pcall(C_Spell.GetSpellInfo,resolvedID)
                    if nok and ninfo then spellName = ninfo.name or "?" end end
                local mapped = cidToEntry[cid]
                    and ("|cFF00FF00MAPPED -> sid="..cidToEntry[cid].sid.."|r")
                    or  "|cFFFF4444NOT MAPPED|r"
                table.insert(found, string.format("  cid=%-6d  spellID=%-8s  name='%s'  %s",
                    cid, tostring(resolvedID), spellName, mapped))
            else scanFrame(child, depth+1) end
        end
    end
    for _, name in ipairs(panelNames) do scanFrame(_G[name], 0) end
    if #found == 0 then print("  (none visible)")
    else for _,line in ipairs(found) do print(line) end end
    print("|cFFFFFF00[MidnightQoL]|r Done.")
end

SLASH_CSFRAMES1 = "/qolframes"
SlashCmdList["CSFRAMES"] = function()
    print("|cFFFFFF00[MidnightQoL]|r Scanning for CooldownViewer frames...")
    local found = {}
    for fname, fval in pairs(_G) do
        if type(fname)=="string" and fname:find("Cooldown") and type(fval)=="table" then
            local ok, hasGC = pcall(function() return type(fval.GetChildren)=="function" end)
            if ok and hasGC then
                local childCount=0; local cdChildren=0
                local ok2,children = pcall(function() return {fval:GetChildren()} end)
                if ok2 then childCount=#children
                    for _,c in ipairs(children) do if c.cooldownID~=nil then cdChildren=cdChildren+1 end end
                end
                table.insert(found,{name=fname,children=childCount,cdChildren=cdChildren})
            end
        end
    end
    table.sort(found,function(a,b) return a.name<b.name end)
    if #found==0 then print("  (none found)")
    else for _,f in ipairs(found) do
        print(string.format("  %-45s  children=%-3d  cd-children=%d",f.name,f.children,f.cdChildren))
    end end
    print("|cFFFFFF00[MidnightQoL]|r Done.")
end

-- ══════════════════════════════════════════════════════════════════════════════
-- Boss Warning Sound System
-- Hooks OnShow on Blizzard's boss warning popup frame and plays a custom sound.
-- Use /mqlbosssniff while in an encounter to identify the correct frame name.
-- ══════════════════════════════════════════════════════════════════════════════

local BOSS_WARNING_FRAMES = {
    "BossWarningMinor",
    "BossWarningMedium",
    "BossWarningCritical",
}

local bossSniffActive = false
local bossFramesHooked = {}

local function HookBossWarningFrame(frameName)
    local f = _G[frameName]
    if not f or not f.HookScript then return false end
    f:HookScript("OnShow", function()
        local db = BuffAlertDB and BuffAlertDB.bossWarnSound
        if db and db.sound then
            API.PlayCustomSound(db.sound, db.soundIsID)
        end
    end)
    bossFramesHooked[#bossFramesHooked+1] = frameName
    API.bossFrameHooked = table.concat(bossFramesHooked, ", ")
    API.Debug("[BossSounds] Hooked OnShow on " .. frameName)
    return true
end

-- Try to hook on login once frames exist
local bossHookFrame = CreateFrame("Frame")
bossHookFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
bossHookFrame:SetScript("OnEvent", function(self, event)
    local anyHooked = false
    for _, name in ipairs(BOSS_WARNING_FRAMES) do
        if HookBossWarningFrame(name) then anyHooked = true end
    end
    if anyHooked then self:UnregisterAllEvents() end
end)

-- ── Sniffer: /mqlbosssniff ────────────────────────────────────────────────────
-- Watches every global frame's OnShow for ~30s and prints names.
-- Use this in an encounter to find the boss warning frame name.
SLASH_MQLBOSSSNIFF1 = "/mqlbosssniff"
SlashCmdList["MQLBOSSSNIFF"] = function()
    if bossSniffActive then
        bossSniffActive = false
        print("|cFF00CCFF[MidnightQoL]|r Boss frame sniffer |cFFAAAAAAdisabled|r")
        return
    end
    bossSniffActive = true
    print("|cFF00CCFF[MidnightQoL]|r Boss frame sniffer |cFFFFFF00ON|r — trigger a boss warning and watch chat (type again to stop)")

    -- Walk all current globals and hook OnShow on anything frame-like
    local hooked = {}
    for name, val in pairs(_G) do
        if type(name) == "string" and type(val) == "table" then
            local ok, hasHook = pcall(function() return type(val.HookScript) == "function" end)
            if ok and hasHook then
                pcall(function()
                    val:HookScript("OnShow", function()
                        if bossSniffActive then
                            print("|cFFFF8800[BossSniff]|r OnShow: " .. name)
                        end
                    end)
                    hooked[#hooked+1] = name
                end)
            end
        end
    end
    API.Debug("[BossSounds] Sniffer hooked " .. #hooked .. " frames")
end

-- Expose DB key so BuffAlertsUI can wire up the sound picker
-- BuffAlertDB.bossWarnSound = { sound = ..., soundIsID = ... }
