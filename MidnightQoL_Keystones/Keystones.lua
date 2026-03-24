-- ============================================================
-- MidnightQoL_Keystones / Keystones.lua
--
-- Features:
--   1. Auto-slot       — slots keystone into M+ font on open
--   2. Party panel     — party keystones injected into ChallengesFrame
--                        (LibOpenRaid-1.0 > AngryKeystones > AstralKeys > MQLKeys)
--   3. Season dungeons — best-level grid in ChallengesFrame
--   4. Wheel spinner   — /mqlwheel, randomises which key to run
--   5. Settings tab    — registered into MidnightQoL tab system
-- ============================================================

local API = MidnightQoLAPI

-- ── DB ────────────────────────────────────────────────────────────────────────
local DEFAULTS = {
    autoSlot       = true,
    announceWinner = true,
    wheelSpinTime  = 5,
}
local function GetDB()
    if not BuffAlertDB then return DEFAULTS end
    BuffAlertDB.keystones = BuffAlertDB.keystones or {}
    local db = BuffAlertDB.keystones
    for k, v in pairs(DEFAULTS) do
        if db[k] == nil then db[k] = v end
    end
    return db
end

-- ── Comm prefixes ─────────────────────────────────────────────────────────────
local COMM_PREFIX = "MQLKeys"
local COMM_AK     = "AngryKeystones"
local COMM_ASTRAL = "AstralKeys"
for _, p in ipairs({ COMM_PREFIX, COMM_AK, COMM_ASTRAL }) do
    C_ChatInfo.RegisterAddonMessagePrefix(p)
end

-- ── State ─────────────────────────────────────────────────────────────────────
local unitKeystones    = {}
local challengesHooked = false
local partyPanel, dungeonPanel, wheelFrame
local OpenWheel  -- forward declaration; defined after BuildWheelFrame

-- ── Helpers ───────────────────────────────────────────────────────────────────
local function ShortName(name)
    if not name then return "?" end
    return (name:gsub("^.-%: ", ""):gsub("^The ", ""))
end

local function GetKeystoneName(mapID, level)
    if not mapID or not level then return nil end
    local name = C_ChallengeMode.GetMapUIInfo(mapID)
    return name and string.format("+%d %s", level, ShortName(name))
end

-- ── LibOpenRaid ───────────────────────────────────────────────────────────────
local function GetKeystonesViaLibOpenRaid()
    local lib = LibStub and LibStub("LibOpenRaid-1.0", true)
    if not lib or not lib.GetAllKeystonesInfo then return nil end
    local data = lib.GetAllKeystonesInfo()
    if not data then return nil end
    local out = {}
    for unitName, info in pairs(data) do
        if (UnitInParty(unitName) or unitName == UnitName("player"))
           and info.level and info.level > 0 then
            local mapName = C_ChallengeMode.GetMapUIInfo(info.challengeMapID) or "?"
            out[#out+1] = {
                name    = (unitName:match("^([^%-]+)") or unitName),
                mapID   = info.challengeMapID,
                level   = info.level,
                mapName = ShortName(mapName),
            }
        end
    end
    table.sort(out, function(a, b) return a.level > b.level end)
    return (#out > 0) and out or nil
end

local function SyncFromLibOpenRaid()
    local data = GetKeystonesViaLibOpenRaid()
    if not data then return false end
    local realm = select(2, UnitFullName("player")) or ""
    for _, e in ipairs(data) do
        unitKeystones[e.name .. "-" .. realm] = { e.mapID, e.level }
    end
    return true
end

-- ── Auto-slot ─────────────────────────────────────────────────────────────────
local function SlotKeystone()
    for bag = BACKPACK_CONTAINER, NUM_BAG_SLOTS do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local link = C_Container.GetContainerItemLink(bag, slot)
            if link and link:match("|Hkeystone:") then
                C_Container.PickupContainerItem(bag, slot)
                if CursorHasItem() then C_ChallengeMode.SlotKeystone() end
                return
            end
        end
    end
end

-- ── Comm ──────────────────────────────────────────────────────────────────────
local function SendKeystone()
    local mID = C_MythicPlus.GetOwnedKeystoneChallengeMapID()
    local lv  = C_MythicPlus.GetOwnedKeystoneLevel()
    local msg = (mID and lv) and string.format("%d:%d", mID, lv) or "0"
    if IsInGroup(LE_PARTY_CATEGORY_HOME)     then C_ChatInfo.SendAddonMessage(COMM_PREFIX, msg, "PARTY") end
    if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then C_ChatInfo.SendAddonMessage(COMM_PREFIX, msg, "INSTANCE_CHAT") end
end

local function RequestPartyKeystones()
    if IsInGroup(LE_PARTY_CATEGORY_HOME)     then C_ChatInfo.SendAddonMessage(COMM_PREFIX, "req", "PARTY") end
    if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then C_ChatInfo.SendAddonMessage(COMM_PREFIX, "req", "INSTANCE_CHAT") end
end

-- ── Collect all party keystones ───────────────────────────────────────────────
local function GetAllPartyKeystones()
    local libData = GetKeystonesViaLibOpenRaid()
    if libData then return libData end

    local out   = {}
    local realm = select(2, UnitFullName("player")) or ""

    local selfMap = C_MythicPlus.GetOwnedKeystoneChallengeMapID()
    local selfLv  = C_MythicPlus.GetOwnedKeystoneLevel()
    if selfMap and selfLv and selfLv > 0 then
        out[#out+1] = { name=UnitName("player"), mapID=selfMap, level=selfLv,
                        mapName=ShortName(C_ChallengeMode.GetMapUIInfo(selfMap) or "?") }
    end
    for i = 1, 4 do
        local name, r = UnitName("party"..i)
        if name then
            local full = name.."-"..((not r or r=="") and realm or r)
            local ks   = unitKeystones[full]
            if ks and ks ~= 0 and ks[2] > 0 then
                out[#out+1] = { name=name, mapID=ks[1], level=ks[2],
                                mapName=ShortName(C_ChallengeMode.GetMapUIInfo(ks[1]) or "?") }
            end
        end
    end
    table.sort(out, function(a,b) return a.level > b.level end)
    return out
end

-- ── Party panel ───────────────────────────────────────────────────────────────
local function RefreshPartyPanel()
    if not partyPanel then return end
    local keys = GetAllPartyKeystones()
    local e = 1
    for _, entry in ipairs(keys) do
        local row = partyPanel.entries[e]; if not row then break end
        local _, class
        for i = 0, 4 do
            local unit = i==0 and "player" or ("party"..i)
            if UnitName(unit) == entry.name then _, class = UnitClass(unit); break end
        end
        local col = class and RAID_CLASS_COLORS[class]
        row.nameStr:SetText(entry.name)
        if col then row.nameStr:SetTextColor(col.r, col.g, col.b) else row.nameStr:SetTextColor(1,1,1) end
        row.keyStr:SetText(string.format("|cFFFFD700+%d|r |cFFFFFFFF%s|r", entry.level, entry.mapName))
        row:Show(); e = e + 1
    end
    for i = e, 5 do if partyPanel.entries[i] then partyPanel.entries[i]:Hide() end end
    partyPanel:SetHeight(30 + math.max(0, e-1) * 20)
    partyPanel:SetShown(e > 1)
end

local function RefreshDungeonPanel()
    if not dungeonPanel then return end
    local maps = C_ChallengeMode.GetMapTable()
    if not maps or #maps == 0 then dungeonPanel:Hide(); return end

    -- Build mapID -> key entry lookup from party keystones
    local partyKeys = GetAllPartyKeystones()
    local keyLookup = {}
    for _, entry in ipairs(partyKeys) do
        keyLookup[entry.mapID] = entry
    end

    for i, mapID in ipairs(maps) do
        local row = dungeonPanel.rows[i]; if not row then break end
        local name, _, _, tex = C_ChallengeMode.GetMapUIInfo(mapID)
        if name then
            local best   = C_MythicPlus.GetSeasonBestForMap(mapID)
            local lv     = best and (best.level or 0) or 0
            local partyKey = keyLookup[mapID]

            row.icon:SetTexture(tex)
            row.nameStr:SetText(ShortName(name))

            if partyKey then
                -- Glowing row — party has this key
                row.glow:Show(); row.accent:Show()
                row.nameStr:SetTextColor(1, 0.95, 0.6)
                row.levelStr:SetText(string.format("|cFFFFD700+%d|r", partyKey.level))
                row.holderStr:SetText(string.format("|cFFAAAAAA%s|r", partyKey.name))
                row.holderStr:Show()
            else
                -- Normal row
                row.glow:Hide(); row.accent:Hide()
                row.nameStr:SetTextColor(0.7, 0.7, 0.7)
                row.levelStr:SetText(lv > 0 and ("|cFFAAAAAA+"..lv.."|r") or "|cFF555555-|r")
                row.holderStr:Hide()
            end
            row:Show()
        else
            row:Hide()
        end
    end
    for i = #maps+1, 8 do if dungeonPanel.rows[i] then dungeonPanel.rows[i]:Hide() end end
    dungeonPanel:Show()
end

-- ── Build ChallengesFrame panels ─────────────────────────────────────────────
local function BuildChallengesFramePanels()
    if challengesHooked then return end
    challengesHooked = true
    local cf = ChallengesFrame; if not cf then return end

    -- Right-side sidebar anchored just outside ChallengesFrame so nothing overlaps
    local sidebar = CreateFrame("Frame", nil, cf)
    sidebar:SetSize(270, 500)
    sidebar:SetPoint("TOPLEFT", cf, "TOPRIGHT", 4, 0)

    local ownLabel = sidebar:CreateFontString(nil, "ARTWORK", "GameFontNormalMed2")
    ownLabel:SetPoint("TOPLEFT", sidebar, "TOPLEFT", 8, -10)
    ownLabel:SetWidth(254); ownLabel:SetJustifyH("LEFT")

    -- Party panel
    local pp = CreateFrame("Frame", nil, sidebar, "BackdropTemplate")
    pp:SetSize(260, 110)
    pp:SetPoint("TOPLEFT", ownLabel, "BOTTOMLEFT", 0, -6)
    pp:SetBackdrop({ bgFile="Interface\\DialogFrame\\UI-DialogBox-Background",
                     edgeFile="Interface\\DialogFrame\\UI-DialogBox-Border",
                     edgeSize=12, insets={left=3,right=3,top=3,bottom=3} })
    pp:SetBackdropColor(0.05, 0.05, 0.1, 0.85)
    pp:SetBackdropBorderColor(0.4, 0.6, 1, 0.7)
    do
        local h = pp:CreateFontString(nil,"ARTWORK","GameFontNormalMed2"); h:SetText("Party Keystones"); h:SetPoint("TOPLEFT",8,-6)
        local d = pp:CreateTexture(nil,"ARTWORK"); d:SetSize(244,1); d:SetPoint("TOP",0,-18); d:SetColorTexture(0.4,0.6,1,0.5)
        local entries = {}
        for i = 1, 5 do
            local row = CreateFrame("Frame",nil,pp); row:SetSize(244,18)
            row:SetPoint("TOP", i==1 and d or entries[i-1], "BOTTOM", 0, i==1 and -3 or 0)
            local ns = row:CreateFontString(nil,"ARTWORK","GameFontNormal"); ns:SetWidth(122); ns:SetJustifyH("LEFT"); ns:SetPoint("LEFT",4,0); row.nameStr=ns
            local ks = row:CreateFontString(nil,"ARTWORK","GameFontHighlight"); ks:SetWidth(122); ks:SetJustifyH("RIGHT"); ks:SetPoint("RIGHT",-4,0); row.keyStr=ks
            row:Hide(); entries[i]=row
        end
        pp.entries=entries
    end
    pp:Hide(); partyPanel=pp

    -- Dungeon panel
    local dp = CreateFrame("Frame", nil, sidebar, "BackdropTemplate")
    dp:SetSize(260, 240)
    dp:SetPoint("TOPLEFT", pp, "BOTTOMLEFT", 0, -6)
    dp:SetBackdrop({ bgFile="Interface\\DialogFrame\\UI-DialogBox-Background",
                     edgeFile="Interface\\DialogFrame\\UI-DialogBox-Border",
                     edgeSize=12, insets={left=3,right=3,top=3,bottom=3} })
    dp:SetBackdropColor(0.05, 0.05, 0.1, 0.85)
    dp:SetBackdropBorderColor(0.4, 0.6, 1, 0.7)
    do
        local h = dp:CreateFontString(nil,"ARTWORK","GameFontNormalMed2"); h:SetText("Season Dungeons"); h:SetPoint("TOPLEFT",8,-6)
        local d = dp:CreateTexture(nil,"ARTWORK"); d:SetSize(244,1); d:SetPoint("TOP",0,-18); d:SetColorTexture(0.4,0.6,1,0.5)
        local rows = {}
        for i = 1, 8 do
            local row = CreateFrame("Frame",nil,dp); row:SetSize(120,22)
            local col = (i-1)%2
            if i==1 then row:SetPoint("TOPLEFT",d,"BOTTOMLEFT",col*128+4,-4)
            elseif col==0 then row:SetPoint("TOPLEFT",rows[i-2],"BOTTOMLEFT",0,-2)
            else row:SetPoint("TOPLEFT",rows[i-1],"TOPRIGHT",8,0) end
            local glow = row:CreateTexture(nil,"BACKGROUND"); glow:SetAllPoints(); glow:SetColorTexture(1,0.84,0,0.18); glow:Hide(); row.glow=glow
            local accent = row:CreateTexture(nil,"BORDER"); accent:SetSize(2,22); accent:SetPoint("LEFT"); accent:SetColorTexture(1,0.84,0,0.9); accent:Hide(); row.accent=accent
            local ico = row:CreateTexture(nil,"ARTWORK"); ico:SetSize(16,16); ico:SetPoint("LEFT",4,0); row.icon=ico
            local ns = row:CreateFontString(nil,"ARTWORK","GameFontNormal"); ns:SetWidth(60); ns:SetJustifyH("LEFT"); ns:SetPoint("LEFT",ico,"RIGHT",3,0); ns:SetWordWrap(false); row.nameStr=ns
            local ls = row:CreateFontString(nil,"ARTWORK","GameFontHighlight"); ls:SetWidth(28); ls:SetJustifyH("RIGHT"); ls:SetPoint("RIGHT",-2,0); row.levelStr=ls
            local hs = row:CreateFontString(nil,"ARTWORK","GameFontNormalSmall"); hs:SetWidth(120); hs:SetJustifyH("CENTER"); hs:SetPoint("TOP",row,"BOTTOM",0,-1); hs:Hide(); row.holderStr=hs
            row:Hide(); rows[i]=row
        end
        dp.rows=rows
    end
    dp:Hide(); dungeonPanel=dp

    -- Wheel button below the dungeon panel
    local wheelBtn = CreateFrame("Button", nil, sidebar, "UIPanelButtonTemplate")
    wheelBtn:SetSize(180, 26)
    wheelBtn:SetPoint("TOPLEFT", dp, "BOTTOMLEFT", 0, -8)
    wheelBtn:SetText("Keystone Wheel")
    wheelBtn:SetScript("OnClick", OpenWheel)

    hooksecurefunc(cf,"Update",function()
        local oMap=C_MythicPlus.GetOwnedKeystoneChallengeMapID(); local oLv=C_MythicPlus.GetOwnedKeystoneLevel()
        local oName=GetKeystoneName(oMap,oLv)
        ownLabel:SetText(oName and ("|cFFFFD700Your keystone:|r "..oName) or "|cFFAAAAAA(no keystone)|r")
        RefreshPartyPanel(); RefreshDungeonPanel()
    end)
    cf:HookScript("OnShow",function()
        SyncFromLibOpenRaid(); RequestPartyKeystones(); RefreshPartyPanel(); RefreshDungeonPanel()
    end)
end

-- ── Wheel ─────────────────────────────────────────────────────────────────────
local function BuildWheelFrame()
    if wheelFrame then return end

    local f = CreateFrame("Frame","MQLKeystoneWheel",UIParent,"BackdropTemplate")
    f:SetSize(300,360); f:SetPoint("CENTER"); f:SetFrameStrata("HIGH")
    f:SetBackdrop({ bgFile="Interface\\DialogFrame\\UI-DialogBox-Background",
                    edgeFile="Interface\\DialogFrame\\UI-DialogBox-Border",
                    edgeSize=16, insets={left=4,right=4,top=4,bottom=4} })
    f:SetMovable(true); f:EnableMouse(true)
    f:SetScript("OnMouseDown",function(self,b) if b=="LeftButton" then self:StartMoving() end end)
    f:SetScript("OnMouseUp",function(self) self:StopMovingOrSizing() end)
    f:Hide(); wheelFrame=f

    local title = f:CreateFontString(nil,"OVERLAY","GameFontNormalLarge")
    title:SetText("|cFFFFD700Keystone Wheel|r"); title:SetPoint("TOP",0,-12)

    local closeBtn = CreateFrame("Button",nil,f,"UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT",-2,-2)
    closeBtn:SetScript("OnClick",function() f:Hide() end)

    -- Wheel canvas
    local RADIUS    = 95
    local ICON_SIZE = 38
    local canvas    = CreateFrame("Frame",nil,f)
    canvas:SetSize(RADIUS*2+ICON_SIZE+20, RADIUS*2+ICON_SIZE+20)
    canvas:SetPoint("TOP",title,"BOTTOM",0,-6)
    f.canvas = canvas; f.icons = {}
    f.angle  = 0; f.spinning = false; f.keys = {}; f.winner = nil

    -- Pointer arrow at top of wheel
    local pointer = canvas:CreateTexture(nil,"OVERLAY")
    pointer:SetSize(20,20); pointer:SetPoint("TOP",canvas,"TOP",0,-2)
    pointer:SetAtlas("Waypoint-MapPin-Tracked")

    -- Status / result text
    local statusStr = f:CreateFontString(nil,"OVERLAY","GameFontNormal")
    statusStr:SetPoint("TOP",canvas,"BOTTOM",0,-6); statusStr:SetWidth(280)
    statusStr:SetJustifyH("CENTER"); statusStr:SetWordWrap(true)
    f.statusStr = statusStr

    -- Buttons row
    local spinBtn = CreateFrame("Button",nil,f,"UIPanelButtonTemplate")
    spinBtn:SetSize(90,24); spinBtn:SetPoint("TOPLEFT",f,"TOPLEFT",16,-f:GetHeight()+50)
    spinBtn:SetText("Spin!")
    -- We'll anchor properly after all buttons are known
    spinBtn:SetPoint("TOP",statusStr,"BOTTOM",0,-8)

    local refreshBtn = CreateFrame("Button",nil,f,"UIPanelButtonTemplate")
    refreshBtn:SetSize(90,24); refreshBtn:SetPoint("LEFT",spinBtn,"RIGHT",4,0)
    refreshBtn:SetText("Refresh")

    local announceBtn = CreateFrame("Button",nil,f,"UIPanelButtonTemplate")
    announceBtn:SetSize(120,24); announceBtn:SetPoint("TOP",spinBtn,"BOTTOM",0,-4)
    announceBtn:SetText("Announce to Party"); announceBtn:Hide()
    f.announceBtn = announceBtn

    -- Position icons
    local function PositionIcons()
        local keys = f.keys; local n = #keys
        for j, ico in ipairs(f.icons) do ico:Hide() end
        for j = 1, n do
            local ico = f.icons[j]
            if not ico then
                ico = CreateFrame("Frame",nil,canvas); ico:SetSize(ICON_SIZE,ICON_SIZE)
                local tex = ico:CreateTexture(nil,"ARTWORK"); tex:SetAllPoints(); ico.tex=tex
                local ring = ico:CreateTexture(nil,"OVERLAY"); ring:SetAllPoints(); ring:SetAtlas("ChallengeMode-AffixRing-Sm"); ico.ring=ring
                local nlbl = ico:CreateFontString(nil,"OVERLAY"); nlbl:SetFont("Fonts\\FRIZQT__.TTF",8,"OUTLINE")
                nlbl:SetPoint("TOP",ico,"BOTTOM",0,-1); nlbl:SetWidth(50); nlbl:SetJustifyH("CENTER"); ico.nameStr=nlbl
                local llbl = ico:CreateFontString(nil,"OVERLAY"); llbl:SetFont("Fonts\\FRIZQT__.TTF",11,"OUTLINE")
                llbl:SetPoint("CENTER"); ico.lvlStr=llbl
                f.icons[j]=ico
            end
            local key = keys[j]
            local _,_,_,tex = C_ChallengeMode.GetMapUIInfo(key.mapID)
            ico.tex:SetTexture(tex or 525134)
            ico.nameStr:SetText(key.name)
            ico.lvlStr:SetText("|cFFFFD700+"..key.level.."|r")
            ico:Show()
        end
    end

    local function UpdatePositions()
        local keys = f.keys; local n = #keys; if n == 0 then return end
        local cx = canvas:GetWidth()/2; local cy = canvas:GetHeight()/2
        for j = 1, n do
            local ico = f.icons[j]; if not ico then break end
            local a = (2*math.pi/n)*(j-1) + f.angle + math.pi/2
            local x = cx + RADIUS*math.cos(a) - ICON_SIZE/2
            local y = cy + RADIUS*math.sin(a) - ICON_SIZE/2
            ico:ClearAllPoints(); ico:SetPoint("BOTTOMLEFT",canvas,"BOTTOMLEFT",x,y)
            ico.ring:SetVertexColor(f.winner==j and 1 or 1, f.winner==j and 0.84 or 1, f.winner==j and 0 or 1)
        end
    end
    f.UpdatePositions = UpdatePositions

    local spinTimer
    spinBtn:SetScript("OnClick",function()
        if f.spinning then return end
        local keys = GetAllPartyKeystones()
        if #keys == 0 then f.statusStr:SetText("|cFFFF4444No party keystones found.|r"); return end
        f.keys=keys; f.winner=nil; f.announceBtn:Hide()
        PositionIcons(); UpdatePositions()
        f.spinning=true; f.statusStr:SetText("|cFFFFD700Spinning...|r"); spinBtn:SetEnabled(false)

        local duration = GetDB().wheelSpinTime or 5
        local winnerIdx = math.random(1, #keys)
        local elapsed = 0
        if spinTimer then spinTimer:Cancel() end
        spinTimer = C_Timer.NewTicker(0.016,function(t)
            elapsed = elapsed + 0.016
            local progress = elapsed / duration
            if progress >= 1 then
                t:Cancel()
                f.spinning=false; f.winner=winnerIdx
                UpdatePositions(); spinBtn:SetEnabled(true)
                local w = f.keys[winnerIdx]
                f.statusStr:SetText(string.format("|cFF00FF00Winner:|r |cFFFFFFFF%s|r |cFFFFD700+%d %s|r", w.name, w.level, w.mapName))
                if GetDB().announceWinner then f.announceBtn:Show() end
                return
            end
            local speed = (1 - progress*0.8) * 4 + 0.3
            f.angle = f.angle + speed * 0.016 * math.pi * 2
            UpdatePositions()
        end)
    end)

    refreshBtn:SetScript("OnClick",function()
        SyncFromLibOpenRaid(); RequestPartyKeystones()
        f.keys=GetAllPartyKeystones(); f.winner=nil; f.announceBtn:Hide()
        PositionIcons(); UpdatePositions()
        local n=#f.keys
        f.statusStr:SetText(n>0 and string.format("|cFFAAAAFF%d keystone%s loaded.|r",n,n==1 and "" or "s") or "|cFFFF4444No keystones found.|r")
        spinBtn:SetEnabled(n>0)
    end)

    announceBtn:SetScript("OnClick",function()
        local w = f.keys and f.winner and f.keys[f.winner]; if not w then return end
        local msg = string.format("[Keystone Wheel] %s wins! +%d %s", w.name, w.level, w.mapName)
        if IsInGroup(LE_PARTY_CATEGORY_HOME) then SendChatMessage(msg,"PARTY")
        elseif IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then SendChatMessage(msg,"INSTANCE_CHAT")
        else print("|cFF00CCFF[MidnightQoL]|r "..msg) end
    end)

    f:SetScript("OnShow",function()
        f.angle=0; f.winner=nil; f.spinning=false; f.announceBtn:Hide()
        SyncFromLibOpenRaid(); f.keys=GetAllPartyKeystones()
        PositionIcons(); UpdatePositions()
        local n=#f.keys
        f.statusStr:SetText(n>0 and string.format("|cFFAAAAFF%d keystone%s loaded. Click Spin!|r",n,n==1 and "" or "s") or "|cFFFF4444No keystones in party.|r")
        spinBtn:SetEnabled(n>0)
    end)
end

OpenWheel = function()
    BuildWheelFrame()
    if wheelFrame:IsShown() then wheelFrame:Hide() else wheelFrame:Show() end
end

-- ── Settings tab ──────────────────────────────────────────────────────────────
local function BuildSettingsTab()
    if not API.RegisterTab then return end
    local f = CreateFrame("Frame","MidnightQoLKeystonesFrame",UIParent)
    f:SetSize(620, 600); f:Hide()
    local y = -10

    local function Header(txt)
        local t=f:CreateFontString(nil,"ARTWORK","GameFontNormalLarge"); t:SetText(txt); t:SetPoint("TOPLEFT",12,y); y=y-24
    end
    local function Divider()
        local d=f:CreateTexture(nil,"ARTWORK"); d:SetSize(580,1); d:SetPoint("TOPLEFT",12,y); d:SetColorTexture(0.3,0.3,0.3,0.8); y=y-8
    end
    local checkCount = 0
    local function Check(label, dbKey)
        checkCount = checkCount + 1
        local c=CreateFrame("CheckButton","MQLKeysCheck"..checkCount,f,"UICheckButtonTemplate")
        c:SetSize(24,24); c:SetPoint("TOPLEFT",12,y)
        _G["MQLKeysCheck"..checkCount.."Text"]:SetText(label)
        c:SetChecked(GetDB()[dbKey])
        c:SetScript("OnClick",function(self) GetDB()[dbKey]=self:GetChecked() end); y=y-26; return c
    end
    local sliderCount = 0
    local function Slider(label, dbKey, lo, hi, step)
        sliderCount = sliderCount + 1
        local lbl=f:CreateFontString(nil,"ARTWORK","GameFontNormal"); lbl:SetText(label); lbl:SetPoint("TOPLEFT",12,y); y=y-18
        local s=CreateFrame("Slider","MQLKeysSlider"..sliderCount,f,"OptionsSliderTemplate"); s:SetSize(260,16); s:SetPoint("TOPLEFT",20,y)
        s:SetMinMaxValues(lo,hi); s:SetValueStep(step); s:SetValue(GetDB()[dbKey] or lo)
        _G["MQLKeysSlider"..sliderCount.."Low"]:SetText(lo)
        _G["MQLKeysSlider"..sliderCount.."High"]:SetText(hi)
        _G["MQLKeysSlider"..sliderCount.."Text"]:SetText((GetDB()[dbKey] or lo).."s")
        s:SetScript("OnValueChanged",function(self,v) v=math.floor(v+0.5); GetDB()[dbKey]=v; _G[self:GetName().."Text"]:SetText(v.."s") end)
        y=y-28
    end

    Header("|cFFFFD700Keystones|r")
    Divider()
    Check("Auto-slot keystone when M+ UI opens", "autoSlot")

    y=y-6
    Header("|cFFFFD700Wheel|r")
    Divider()
    Check("Announce winner to party chat", "announceWinner")
    Slider("Spin duration (seconds)", "wheelSpinTime", 2, 15, 1)

    local openBtn=CreateFrame("Button",nil,f,"UIPanelButtonTemplate")
    openBtn:SetSize(160,26); openBtn:SetPoint("TOPLEFT",12,y); openBtn:SetText("Open Keystone Wheel")
    openBtn:SetScript("OnClick",OpenWheel); y=y-34

    y=y-6
    Header("|cFFAAAAAAData Sources|r")
    Divider()

    local info=f:CreateFontString(nil,"ARTWORK","GameFontNormal")
    info:SetPoint("TOPLEFT",12,y); info:SetWidth(580); info:SetJustifyH("LEFT"); info:SetWordWrap(true)
    info:SetText("Party keystones are collected from (priority order):\n 1. LibOpenRaid-1.0  |cFFAAAAAA(fed by Details, RaiderIO, and others)|r\n 2. AngryKeystones addon comm\n 3. AstralKeys addon comm\n 4. MidnightQoL own comm (MQLKeys)\nOnly one source is needed.")
    y=y-90

    local statusLbl=f:CreateFontString(nil,"ARTWORK","GameFontNormal")
    statusLbl:SetPoint("TOPLEFT",12,y); statusLbl:SetWidth(580)

    f:SetScript("OnShow",function()
        local libOK   = LibStub and LibStub("LibOpenRaid-1.0",true) ~= nil
        local akOK    = C_AddOns.IsAddOnLoaded("AngryKeystones")
        local astralOK= C_AddOns.IsAddOnLoaded("AstralKeys")
        statusLbl:SetText(string.format(
            "LibOpenRaid: %s    AngryKeystones: %s    AstralKeys: %s",
            libOK    and "|cFF00FF00active|r" or "|cFFAAAAAAnot found|r",
            akOK     and "|cFF00FF00loaded|r" or "|cFFAAAAAAnot loaded|r",
            astralOK and "|cFF00FF00loaded|r" or "|cFFAAAAAAnot loaded|r"))
    end)

    API.RegisterTab("Keystones", f, function() if f:IsShown() then f:GetScript("OnShow")(f) end end, 72, nil, 5)
end

-- ── Slash ─────────────────────────────────────────────────────────────────────
SLASH_MQLWHEEL1 = "/mqlwheel"
SlashCmdList["MQLWHEEL"] = OpenWheel

-- ── Comm receive helper ───────────────────────────────────────────────────────
local function UpdateComm(sender, mapID, level)
    local isNone = not mapID or mapID == 0
    local prev   = unitKeystones[sender]
    if isNone then
        if prev ~= 0 then unitKeystones[sender]=0; RefreshPartyPanel() end
    else
        if not prev or prev==0 or prev[1]~=mapID or prev[2]~=level then
            unitKeystones[sender]={mapID,level}; RefreshPartyPanel()
        end
    end
end

-- ── Events ────────────────────────────────────────────────────────────────────
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("CHAT_MSG_ADDON")
ev:RegisterEvent("GROUP_ROSTER_UPDATE")
ev:RegisterEvent("BAG_UPDATE_DELAYED")
ev:RegisterEvent("CHALLENGE_MODE_START")
ev:RegisterEvent("CHALLENGE_MODE_COMPLETED")
ev:RegisterEvent("CHALLENGE_MODE_MAPS_UPDATE")

ev:SetScript("OnEvent",function(self,event,...)
    if event=="PLAYER_LOGIN" then
        C_Timer.After(3,function()
            SendKeystone(); RequestPartyKeystones()

            -- Register LibOpenRaid KeystoneUpdate callback so the party panel and
            -- dungeon panel refresh immediately whenever any group member's key is
            -- received — no need to wait for a manual sync or a roster event.
            local lib = LibStub and LibStub("LibOpenRaid-1.0", true)
            if lib then
                local MQLKeystoneCallbacks = {}
                function MQLKeystoneCallbacks.OnKeystoneUpdate(unitName, keystoneInfo)
                    -- Fold the received info into our local cache so GetAllPartyKeystones()
                    -- stays consistent with the LibOpenRaid data path.
                    if keystoneInfo and keystoneInfo.level and keystoneInfo.level > 0 then
                        local realm = select(2, UnitFullName("player")) or ""
                        local shortName = unitName:match("^([^%-]+)") or unitName
                        -- Derive the sender key the same way UpdateComm / SyncFromLibOpenRaid do.
                        local senderKey = shortName .. "-" .. realm
                        unitKeystones[senderKey] = { keystoneInfo.challengeMapID, keystoneInfo.level }
                    end
                    -- Refresh live panels if ChallengesFrame is open.
                    if ChallengesFrame and ChallengesFrame:IsShown() then
                        RefreshPartyPanel(); RefreshDungeonPanel()
                    end
                    -- Also refresh the wheel if it's open.
                    if wheelFrame and wheelFrame:IsShown() then
                        wheelFrame:GetScript("OnShow")(wheelFrame)
                    end
                end
                function MQLKeystoneCallbacks.OnKeystoneWipe()
                    wipe(unitKeystones)
                    if ChallengesFrame and ChallengesFrame:IsShown() then
                        RefreshPartyPanel(); RefreshDungeonPanel()
                    end
                end
                lib.RegisterCallback(MQLKeystoneCallbacks, "KeystoneUpdate", "OnKeystoneUpdate")
                lib.RegisterCallback(MQLKeystoneCallbacks, "KeystoneWipe",   "OnKeystoneWipe")
            end
        end)
        C_Timer.After(0, BuildSettingsTab)

    elseif event=="ADDON_LOADED" then
        local name=...
        if name=="Blizzard_ChallengesUI" then
            if ChallengesKeystoneFrame then
                ChallengesKeystoneFrame:HookScript("OnShow",function()
                    if GetDB().autoSlot then SlotKeystone() end
                end)
            end
            BuildChallengesFramePanels()
            C_Timer.After(0.5,function() SyncFromLibOpenRaid(); RequestPartyKeystones(); RefreshDungeonPanel() end)
        end

    elseif event=="CHAT_MSG_ADDON" then
        local prefix,msg,_,sender=...
        if prefix==COMM_PREFIX then
            if msg=="req" then SendKeystone()
            elseif msg=="0" then UpdateComm(sender,0,0)
            else
                local m,l=msg:match("^(%d+):(%d+)$")
                if m then UpdateComm(sender,tonumber(m),tonumber(l)) end
            end
        elseif prefix==COMM_AK then
            local p=msg:match("^Schedule|(.+)$")
            if p and p~="req" then
                if p=="0" then UpdateComm(sender,0,0)
                else local m,l=p:match("^(%d+):(%d+)$"); if m then UpdateComm(sender,tonumber(m),tonumber(l)) end end
            end
        elseif prefix==COMM_ASTRAL then
            local p=msg:match("^keystonePush (.+)$")
            if p then local m,l=p:match("^(%d+):(%d+)"); if m then UpdateComm(sender,tonumber(m),tonumber(l)) end end
        end

    elseif event=="GROUP_ROSTER_UPDATE" then
        wipe(unitKeystones)
        C_Timer.After(1,function() SyncFromLibOpenRaid(); RequestPartyKeystones(); SendKeystone(); RefreshPartyPanel() end)

    elseif event=="BAG_UPDATE_DELAYED" then
        C_Timer.After(0.5,function()
            SendKeystone()
            if ChallengesFrame and ChallengesFrame:IsShown() and ChallengesFrame.Update then ChallengesFrame:Update() end
        end)

    elseif event=="CHALLENGE_MODE_START" or event=="CHALLENGE_MODE_COMPLETED" or event=="CHALLENGE_MODE_MAPS_UPDATE" then
        C_Timer.After(1,function()
            SendKeystone(); SyncFromLibOpenRaid(); RefreshDungeonPanel(); RefreshPartyPanel()
            if ChallengesFrame and ChallengesFrame:IsShown() and ChallengesFrame.Update then ChallengesFrame:Update() end
        end)
    end
end)

if C_AddOns.IsAddOnLoaded("Blizzard_ChallengesUI") then
    C_Timer.After(0,function()
        if ChallengesKeystoneFrame then
            ChallengesKeystoneFrame:HookScript("OnShow",function() if GetDB().autoSlot then SlotKeystone() end end)
        end
        BuildChallengesFramePanels(); SyncFromLibOpenRaid(); RequestPartyKeystones(); RefreshDungeonPanel()
    end)
end

API.Debug("[MidnightQoL Keystones] loaded  /mqlwheel to spin")
