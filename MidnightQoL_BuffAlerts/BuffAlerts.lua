-- ============================================================
-- MidnightQoL_BuffAlerts / BuffAlerts.lua
-- CooldownViewer hook, visual alert pool, glow system,
-- spec-profile save/load for tracked buffs/debuffs/externals.
-- ============================================================

local API = MidnightQoLAPI

-- ── State ─────────────────────────────────────────────────────────────────────
local trackedBuffs     = {}
local trackedDebuffs   = {}
local trackedExternals = {}
local activeAlerts     = {}

-- Expose on API so BuffAlertsUI and Layout mode can access them
API.trackedBuffs     = trackedBuffs
API.trackedDebuffs   = trackedDebuffs
API.trackedExternals = trackedExternals

local buffDebuffAlertsEnabled = true

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
    return (t and t[listType]) or {}
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
    profile.trackedDebuffs   = trackedDebuffs
    profile.trackedExternals = trackedExternals
    profile.buffDebuffAlertsEnabled = buffDebuffAlertsEnabled
    -- Keep legacy flat keys for backward compat
    if BuffAlertDB then
        BuffAlertDB.trackedBuffs     = trackedBuffs
        BuffAlertDB.trackedDebuffs   = trackedDebuffs
        BuffAlertDB.trackedExternals = trackedExternals
        BuffAlertDB.buffDebuffAlertsEnabled = buffDebuffAlertsEnabled
    end
end

local function OnLoadProfile(profile)
    -- Wipe and repopulate the SAME table objects so all upvalue references stay valid
    for k in pairs(trackedBuffs)     do trackedBuffs[k]     = nil end
    for k in pairs(trackedDebuffs)   do trackedDebuffs[k]   = nil end
    for k in pairs(trackedExternals) do trackedExternals[k] = nil end

    for _, v in ipairs(profile.trackedBuffs     or {}) do table.insert(trackedBuffs,     v) end
    for _, v in ipairs(profile.trackedDebuffs   or {}) do table.insert(trackedDebuffs,   v) end
    for _, v in ipairs(profile.trackedExternals or {}) do table.insert(trackedExternals, v) end

    buffDebuffAlertsEnabled = (profile.buffDebuffAlertsEnabled ~= false)
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

for i = 1, ALERT_POOL_SIZE do alertPool[i] = CreateAlertOverlayFrame(i) end

local function GetFreeAlertFrame()
    for _, f in ipairs(alertPool) do if not f:IsShown() then return f end end
    alertPool[1]:Hide(); return alertPool[1]
end

local function ReleaseOverlay(alertKey)
    local f = activeOverlays[alertKey]; if not f then return end
    activeOverlays[alertKey] = nil
    if f.sourceFrame then f.sourceFrame:SetAlpha(1); f.sourceFrame = nil end
    f.cooldown:Clear()
    UIFrameFadeOut(f, 0.2, f:GetAlpha(), 0)
    C_Timer.After(0.2, function() if not f.sourceFrame then f:Hide() end end)
end

local function ShowAlertOverlay(aura, spellName, sourceFrame)
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
    local dur = tonumber(aura.alertDuration)
    if dur and dur > 0 and dur < 9999 and not f.boundToHandle then
        C_Timer.After(dur, function()
            if f:IsShown() and not f.boundToHandle then
                UIFrameFadeOut(f,0.4,f:GetAlpha(),0)
                C_Timer.After(0.4, function() if not f.boundToHandle then f:Hide() end end)
            end
        end)
    end
    return f
end

API.ShowAlertOverlay = ShowAlertOverlay
API.HideAlertPreviews = function()
    for _, f in ipairs(alertPool) do
        f.cooldown:Clear(); f.boundToHandle = nil; f:Hide(); f.sourceFrame = nil
    end
end

-- ── Glow system ────────────────────────────────────────────────────────────────
local spellGlowFrames = {}

local function CreateGlowFrame(parent, r, g, b)
    local glow = CreateFrame("Frame", nil, parent)
    glow:SetFrameLevel(parent:GetFrameLevel()+5)
    glow:SetPoint("TOPLEFT",parent,"TOPLEFT",-4,4); glow:SetPoint("BOTTOMRIGHT",parent,"BOTTOMRIGHT",4,-4); glow:Hide()
    local function makeEdge(point,relPoint,w,h)
        local t = glow:CreateTexture(nil,"OVERLAY")
        t:SetTexture("Interface\\SpellActivationOverlay\\IconAlert")
        t:SetTexCoord(0,1,0,0.5); t:SetVertexColor(r,g,b,0.85); t:SetSize(w,h)
        t:SetPoint(point,glow,relPoint,0,0)
    end
    makeEdge("TOP","TOP",64,16); makeEdge("BOTTOM","BOTTOM",64,16)
    makeEdge("LEFT","LEFT",16,64); makeEdge("RIGHT","RIGHT",16,64)
    local ag = glow:CreateAnimationGroup(); ag:SetLooping("BOUNCE")
    local anim = ag:CreateAnimation("Alpha"); anim:SetFromAlpha(0.4); anim:SetToAlpha(1.0)
    anim:SetDuration(0.6); anim:SetSmoothing("IN_OUT"); glow.animGroup = ag
    function glow:ShowGlow() self:Show(); self.animGroup:Play() end
    function glow:HideGlow() self.animGroup:Stop(); self:Hide() end
    return glow
end

local function GetOrCreateGlowForAura(aura)
    local sid = aura.spellId; if not sid or sid <= 0 then return nil end
    if spellGlowFrames[sid] then return spellGlowFrames[sid] end
    local r,g,b = 1,0.8,0
    if aura.glowColor then r=aura.glowColor[1] or r; g=aura.glowColor[2] or g; b=aura.glowColor[3] or b end
    local gf = CreateGlowFrame(UIParent,r,g,b)
    gf:SetSize(64,64); gf:SetPoint("CENTER",UIParent,"CENTER",0,-100)
    spellGlowFrames[sid] = gf; return gf
end

-- ── CooldownViewer hook ────────────────────────────────────────────────────────
local cidToEntry         = {}
local sidToEntry         = {}
local trackedNameToEntry = {}
local hookedFrames       = {}
local pendingHide        = {}

local function OnCooldownViewerFrameShow(self)
    if not buffDebuffAlertsEnabled then return end
    local cid = self.cooldownID; if not cid then return end
    local entry = cidToEntry[cid]
    if not entry then
        local spellID
        pcall(function()
            local ci = self.cooldownInfo
            if ci then spellID = ci.overrideSpellID or ci.spellID end
        end)
        if spellID then
            if sidToEntry[spellID] then
                entry = sidToEntry[spellID]; cidToEntry[cid] = entry
            else
                local nameOk, nameInfo = pcall(C_Spell.GetSpellInfo, spellID)
                if nameOk and nameInfo and nameInfo.name then
                    local nameEntry = trackedNameToEntry[nameInfo.name:lower()]
                    if nameEntry then
                        entry = nameEntry; cidToEntry[cid] = entry; sidToEntry[spellID] = entry
                    end
                end
            end
        end
    end
    if not entry or entry.aura.enabled == false then return end
    local alertKey = entry.alertKey
    pendingHide[alertKey] = nil
    self:SetAlpha(0)
    if activeAlerts[alertKey] then return end
    activeAlerts[alertKey] = true
    local spellName = ""
    local ok, sinfo = pcall(C_Spell.GetSpellInfo, entry.sid)
    if ok and sinfo then spellName = sinfo.name or "" end
    if entry.aura.sound then API.PlayCustomSound(entry.aura.sound, entry.aura.soundIsID) end
    local overlay = ShowAlertOverlay(entry.aura, spellName, self)
    if overlay then activeOverlays[alertKey] = overlay end
    print(entry.color .. "[MidnightQoL]|r " .. entry.label .. ": " .. spellName)
    if entry.aura.glowEnabled then
        local gf = GetOrCreateGlowForAura(entry.aura); if gf then gf:ShowGlow() end
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
    cidToEntry = {}; sidToEntry = {}; trackedNameToEntry = {}

    local function addByID(sid, aura, label, color, alertKey)
        if not sid or sid <= 0 then return end
        local entry = {aura=aura, label=label, color=color, alertKey=alertKey, sid=sid}
        sidToEntry[sid] = entry
        local ok, cid = pcall(C_Spell.GetSpellCooldownID, sid)
        if ok and cid and cid > 0 then cidToEntry[cid] = entry end
        local ok2, info = pcall(C_Spell.GetSpellInfo, sid)
        if ok2 and info and info.name then trackedNameToEntry[info.name:lower()] = entry end
    end

    for _, buff in ipairs(trackedBuffs) do
        if buff.enabled ~= false and buff.spellId and buff.spellId > 0 then
            addByID(buff.spellId, buff, "Gained", "|cFF00FF00", buff.spellId)
        end
    end
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
                if wid and wid > 0 then addByID(wid, ext, "External", "|cFF00CCFF", alertKey) end
            end
        end
    end

    local panelNames = {
        "EssentialCooldownViewer","UtilityCooldownViewer","BuffIconCooldownViewer",
        "CooldownViewerSystem","CooldownViewerFrame","BuffAndEssentialCooldownViewer",
    }
    local hookCount = 0
    local function walkFrame(parent, depth)
        if not parent or depth > 4 then return end
        local ok, children = pcall(function() return {parent:GetChildren()} end)
        if not ok then return end
        for _, child in ipairs(children) do
            if child.cooldownID ~= nil then
                HookItemFrame(child); hookCount = hookCount + 1
                local cid = child.cooldownID
                if not cidToEntry[cid] then
                    local frameSpellID = child.rangeCheckSpellID
                    if not frameSpellID and child.cooldownInfo then
                        frameSpellID = child.cooldownInfo.overrideSpellID or child.cooldownInfo.spellID
                    end
                    if frameSpellID and sidToEntry[frameSpellID] then
                        cidToEntry[cid] = sidToEntry[frameSpellID]
                    end
                    if not cidToEntry[cid] and frameSpellID then
                        local nameOk, nameInfo = pcall(C_Spell.GetSpellInfo, frameSpellID)
                        if nameOk and nameInfo and nameInfo.name then
                            local e = trackedNameToEntry[nameInfo.name:lower()]
                            if e then cidToEntry[cid] = e; sidToEntry[frameSpellID] = e end
                        end
                    end
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
    API.Debug("RebuildNameMap: " .. (function() local c=0 for _ in pairs(cidToEntry) do c=c+1 end return c end)() .. " CIDs mapped")
end
API.RebuildNameMap = RebuildNameMap

-- ── Post-combat map warm-up ───────────────────────────────────────────────────
local buffEvents = CreateFrame("Frame")
buffEvents:RegisterEvent("PLAYER_REGEN_ENABLED")
buffEvents:RegisterEvent("PLAYER_LOGIN")
buffEvents:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        C_Timer.After(1, function() RebuildNameMap(); C_Timer.After(0.5, function()
            if API.CheckCDMismatch then API.CheckCDMismatch() end
        end) end)
    elseif event == "PLAYER_REGEN_ENABLED" then
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

-- ── Also rebuild on spec change (Core fires LoadSpecProfile which calls OnLoadProfile) ──
-- OnLoadProfile already schedules a RebuildNameMap after 0.1s, so no extra event needed.

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
cdMismatchPopup:SetScript("OnDragStart",function(self) self:StartMoving() end)
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
    subtitle:SetText("Some tracked spells are not in the WoW Cooldown Manager")
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
        if BuffAlertDB then BuffAlertDB.cdMismatchSuppressed = true end
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

local function CheckCDMismatch()
    if BuffAlertDB and BuffAlertDB.cdMismatchSuppressed then return end
    local missing = {}
    local function checkEntry(aura, category)
        if aura.enabled == false then return end
        local sid = tonumber(aura.spellId) or (aura.spellIds and tonumber(aura.spellIds[1]))
        if not sid or sid <= 0 then return end
        if not sidToEntry[sid] then
            local name = ""; local ok,info = pcall(C_Spell.GetSpellInfo,sid)
            if ok and info then name = info.name or ("Spell "..sid) end
            table.insert(missing,{sid=sid,name=name,category=category})
        end
    end
    for _,b in ipairs(trackedBuffs)     do checkEntry(b,"Buff")     end
    for _,d in ipairs(trackedDebuffs)   do checkEntry(d,"Debuff")   end
    for _,e in ipairs(trackedExternals) do checkEntry(e,"External") end
    if #missing == 0 then return end
    local lines = {
        "The following spells are tracked by MidnightQoL but were |cFFFF4444not found|r in",
        "your WoW Cooldown Manager. Their alerts will |cFFFF4444not fire|r until you add them.\n",
        "|cFFFFD700How to fix:|r  Click |cFF00CCFF[+] Open Cooldown Manager|r below.\n",
    }
    for _,m in ipairs(missing) do
        table.insert(lines, string.format("  |cFFFF8800[%s]|r  %s  |cFF999999(ID: %d)|r",m.category,m.name,m.sid))
    end
    cdMismatchText:SetText(table.concat(lines,"\n"))
    cdMismatchContent:SetHeight(math.max(150, cdMismatchText:GetStringHeight()+16))
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
                table.insert(handles, {
                    label        = typeLabel..": "..spellName,
                    iconTex      = iconTex,
                    ox           = ox, oy = oy,
                    saveCallback = function(nx,ny)
                        capturedAura.alertX = nx; capturedAura.alertY = ny
                        local xBox = _G["BuffAlertTexX"..capturedType..capturedIdx]
                        local yBox = _G["BuffAlertTexY"..capturedType..capturedIdx]
                        if xBox then xBox:SetText(tostring(nx)) end
                        if yBox then yBox:SetText(tostring(ny)) end
                        if BuffAlertDB then API.SaveSpecProfile() end
                    end,
                    previewFunc  = function()
                        return ShowAlertOverlay({
                            alertTexture=aura.alertTexture, spellId=aura.spellId,
                            alertSize=aura.alertSize, alertDuration=9999,
                            alertX=aura.alertX or 0, alertY=aura.alertY or 0,
                        }, spellName)
                    end,
                })
            end
        end
    end
    addAuraHandles(trackedBuffs,    "Buff")
    addAuraHandles(trackedDebuffs,  "Debuff")
    addAuraHandles(trackedExternals,"External")
    return handles
end)

-- ── Slash commands ─────────────────────────────────────────────────────────────
SLASH_CUSTOMSOUNDSDEBUG1 = "/csdebug"
SlashCmdList["CUSTOMSOUNDSDEBUG"] = function()
    print("|cFFFFFF00[MidnightQoL DEBUG]|r =============================")
    print("buffDebuffAlertsEnabled: "..tostring(buffDebuffAlertsEnabled))
    print("Tracked: buffs="..#trackedBuffs.." debuffs="..#trackedDebuffs.." externals="..#trackedExternals)
    local cidCount=0; for _ in pairs(cidToEntry) do cidCount=cidCount+1 end
    print("CID map entries: "..cidCount)
    RebuildNameMap()
    print("|cFFFFFF00[MidnightQoL DEBUG]|r ============================= done")
end

SLASH_CSTRACK1 = "/cstrack"
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

SLASH_CSFRAMES1 = "/csframes"
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
