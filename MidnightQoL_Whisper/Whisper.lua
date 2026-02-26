-- ============================================================
-- MidnightQoL_Whisper / Whisper.lua
-- Whisper event handling, unread indicator, sound triggers.
-- Settings are ACCOUNT-WIDE (stored at BuffAlertDB root, not per-spec).
-- ============================================================

local API = MidnightQoLAPI

-- ── State (account-wide, loaded from BuffAlertDB root) ────────────────────────
local whisperList            = {}
local unreadWhispers         = {}
local whisperEnabled         = false
local ignoreOutgoingWhispers = true
local whisperIndicatorEnabled= true

-- Expose for WhisperUI to read/write
API.whisperList             = whisperList
API.unreadWhispers          = unreadWhispers
API.GetWhisperState         = function()
    return whisperEnabled, ignoreOutgoingWhispers, whisperIndicatorEnabled
end
API.SetWhisperEnabled       = function(v) whisperEnabled = v end
API.SetIgnoreOutgoing       = function(v) ignoreOutgoingWhispers = v end
API.SetWhisperIndicator     = function(v)
    whisperIndicatorEnabled = v
    if not v then
        local icon = _G["MidnightQoLUnreadMailIcon"]
        if icon then icon:Hide() end
    end
    if BuffAlertDB then BuffAlertDB.whisperIndicatorEnabled = v end
end

-- ── Load / Save from BuffAlertDB root (account-wide) ─────────────────────────
local function LoadWhisperSettings()
    if not BuffAlertDB then return end
    -- Wipe and repopulate whisperList in-place so UI references stay valid
    for k in pairs(whisperList) do whisperList[k] = nil end
    for _, v in ipairs(BuffAlertDB.whisperList or {}) do table.insert(whisperList, v) end
    whisperEnabled          = BuffAlertDB.whisperEnabled          or false
    ignoreOutgoingWhispers  = (BuffAlertDB.ignoreOutgoingWhispers ~= false)
    whisperIndicatorEnabled = (BuffAlertDB.whisperIndicatorEnabled ~= false)
    -- Sync UI if open
    if API.SyncWhisperUI then API.SyncWhisperUI() end
end

local function SaveWhisperSettings()
    if not BuffAlertDB then return end
    BuffAlertDB.whisperList            = whisperList
    BuffAlertDB.whisperEnabled         = whisperEnabled
    BuffAlertDB.ignoreOutgoingWhispers = ignoreOutgoingWhispers
    BuffAlertDB.whisperIndicatorEnabled= whisperIndicatorEnabled
    -- general sound stored separately by WhisperUI
end

API.LoadWhisperSettings = LoadWhisperSettings
API.SaveWhisperSettings = SaveWhisperSettings

-- ── Unread mail icon ───────────────────────────────────────────────────────────
local unreadMailIcon = CreateFrame("Frame", "MidnightQoLUnreadMailIcon", UIParent)
unreadMailIcon:SetSize(48,48); unreadMailIcon:SetPoint("TOPRIGHT",-20,-20)
unreadMailIcon:SetMovable(true); unreadMailIcon:EnableMouse(true)
unreadMailIcon:RegisterForDrag("LeftButton"); unreadMailIcon:Hide()

unreadMailIcon:SetScript("OnDragStart", function(self) self:StartMoving() end)
unreadMailIcon:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    if BuffAlertDB then
        local cx=UIParent:GetWidth()/2; local cy=UIParent:GetHeight()/2
        local ix=self:GetLeft()+self:GetWidth()/2; local iy=self:GetBottom()+self:GetHeight()/2
        BuffAlertDB.unreadMailIconPos = {point="CENTER", x=math.floor(ix-cx+0.5), y=math.floor(iy-cy+0.5)}
    end
end)

local mailIconTexture = unreadMailIcon:CreateTexture(nil,"BACKGROUND")
mailIconTexture:SetAllPoints(unreadMailIcon); mailIconTexture:SetTexture("Interface\\Icons\\INV_Letter_15"); mailIconTexture:SetSize(48,48)

-- Glow border
local glowBorder = unreadMailIcon:CreateTexture(nil,"OVERLAY")
glowBorder:SetTexture("Interface\\Common\\ReforgingArrow"); glowBorder:SetBlendMode("ADD")
glowBorder:SetSize(72,72); glowBorder:SetPoint("CENTER",unreadMailIcon,"CENTER",0,0)
glowBorder:SetVertexColor(1,0.85,0.1,0); unreadMailIcon.glowBorder = glowBorder

local glowPulseTime=0; local glowPulseActive=false; local GLOW_PERIOD=1.6
local glowPulseFrame = CreateFrame("Frame")
glowPulseFrame:SetScript("OnUpdate",function(self,elapsed)
    if not glowPulseActive then return end
    glowPulseTime = glowPulseTime + elapsed
    local t = (glowPulseTime % GLOW_PERIOD) / GLOW_PERIOD
    glowBorder:SetAlpha(0.2 + 0.7*(0.5+0.5*math.sin(t*math.pi*2)))
end)

unreadMailIcon.StartGlowPulse = function()
    glowPulseActive=true; glowPulseTime=0; glowBorder:SetAlpha(0.9); glowBorder:Show()
end
unreadMailIcon.StopGlowPulse = function()
    glowPulseActive=false; glowBorder:SetAlpha(0); glowBorder:Hide()
end

-- Gold border lines
do
    local bc={1,0.8,0.1,1}
    local bT=unreadMailIcon:CreateTexture(nil,"OVERLAY"); bT:SetColorTexture(bc[1],bc[2],bc[3],bc[4])
    bT:SetPoint("TOPLEFT",unreadMailIcon,"TOPLEFT",0,0); bT:SetSize(48,3); bT:Hide()
    local bB=unreadMailIcon:CreateTexture(nil,"OVERLAY"); bB:SetColorTexture(bc[1],bc[2],bc[3],bc[4])
    bB:SetPoint("BOTTOMLEFT",unreadMailIcon,"BOTTOMLEFT",0,0); bB:SetSize(48,3); bB:Hide()
    local bL=unreadMailIcon:CreateTexture(nil,"OVERLAY"); bL:SetColorTexture(bc[1],bc[2],bc[3],bc[4])
    bL:SetPoint("TOPLEFT",unreadMailIcon,"TOPLEFT",0,0); bL:SetSize(3,48); bL:Hide()
    local bR=unreadMailIcon:CreateTexture(nil,"OVERLAY"); bR:SetColorTexture(bc[1],bc[2],bc[3],bc[4])
    bR:SetPoint("TOPRIGHT",unreadMailIcon,"TOPRIGHT",0,0); bR:SetSize(3,48); bR:Hide()
    unreadMailIcon.iconBorders = {bT,bB,bL,bR}
end

-- Count text with shadow
local countShadows = {}
for _,offset in ipairs({{-2,0},{2,0},{0,-2},{0,2},{-2,-2},{2,-2},{-2,2},{2,2}}) do
    local s = unreadMailIcon:CreateFontString(nil,"OVERLAY","GameFontNormalLarge")
    s:SetPoint("CENTER",unreadMailIcon,"CENTER",offset[1],offset[2])
    s:SetTextColor(0,0,0,1); s:SetText("0"); table.insert(countShadows,s)
end
unreadMailIcon.countShadows = countShadows

local unreadCount = unreadMailIcon:CreateFontString(nil,"OVERLAY","GameFontNormalLarge")
unreadCount:SetPoint("CENTER",unreadMailIcon,"CENTER",0,0); unreadCount:SetTextColor(1,1,0.2,1); unreadCount:SetText("0")

-- Tooltip on hover
local tooltip = CreateFrame("Frame","MidnightQoLUnreadTooltip",UIParent,"BackdropTemplate")
tooltip:SetSize(200,100)
tooltip:SetBackdrop({bgFile="Interface/Tooltips/UI-Tooltip-Background",
    edgeFile="Interface/Tooltips/UI-Tooltip-Border",tile=true,tileSize=16,edgeSize=16,
    insets={left=5,right=5,top=5,bottom=5}})
tooltip:SetBackdropColor(0.05,0.05,0.05,0.9); tooltip:SetBackdropBorderColor(0.5,0.5,0.5,0.8); tooltip:Hide()
local tooltipText = tooltip:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
tooltipText:SetPoint("TOPLEFT",10,-10); tooltipText:SetWidth(180); tooltipText:SetJustifyH("LEFT"); tooltipText:SetWordWrap(true)

unreadMailIcon:SetScript("OnEnter",function(self)
    if #unreadWhispers > 0 then
        local text = "Unread Whispers:\n"
        for _,sender in ipairs(unreadWhispers) do text = text.."- "..sender.."\n" end
        tooltipText:SetText(text); tooltip:SetPoint("BOTTOMLEFT",self,"TOPLEFT",0,10); tooltip:Show()
    end
end)
unreadMailIcon:SetScript("OnLeave",function() tooltip:Hide() end)
unreadMailIcon:SetScript("OnMouseUp",function(self,button)
    if button=="LeftButton" then
        for i=#unreadWhispers,1,-1 do table.remove(unreadWhispers,i) end
        UpdateUnreadMailIcon()
    end
end)

function UpdateUnreadMailIcon()
    local count = #(unreadWhispers or {})
    if count > 0 then
        unreadMailIcon:Show()
        if BuffAlertDB and BuffAlertDB.unreadMailIconPos then
            unreadMailIcon:ClearAllPoints()
            unreadMailIcon:SetPoint("CENTER",UIParent,"CENTER",
                BuffAlertDB.unreadMailIconPos.x or 0, BuffAlertDB.unreadMailIconPos.y or 0)
        end
        unreadMailIcon:SetAlpha(1)
        for _,s in ipairs(unreadMailIcon.countShadows or {}) do s:SetText(count) end
        unreadCount:SetText(count)
        for _,border in ipairs(unreadMailIcon.iconBorders or {}) do border:Show() end
        unreadMailIcon.glowBorder:Show(); unreadMailIcon.StartGlowPulse()
    else
        unreadMailIcon:Hide()
        for _,s in ipairs(unreadMailIcon.countShadows or {}) do s:SetText("0") end
        unreadCount:SetText("0")
        for _,border in ipairs(unreadMailIcon.iconBorders or {}) do border:Hide() end
        unreadMailIcon.glowBorder:Hide(); unreadMailIcon.StopGlowPulse()
    end
end
API.UpdateUnreadMailIcon = UpdateUnreadMailIcon

API.ClearUnreadWhispers = function()
    for i=#unreadWhispers,1,-1 do table.remove(unreadWhispers,i) end
    UpdateUnreadMailIcon()
end

-- ── Chat tab click hook (clears unread for opened conversation) ───────────────
hooksecurefunc("FCF_Tab_OnClick", function(self)
    local frameID   = self:GetID()
    local chatFrame = _G["ChatFrame"..frameID]
    if chatFrame and chatFrame.chatTarget then
        local targetName = chatFrame.chatTarget
        if unreadWhispers and #unreadWhispers > 0 then
            local removed = false
            for i=#unreadWhispers,1,-1 do
                if API.NormalizeName(unreadWhispers[i]) == API.NormalizeName(targetName) then
                    table.remove(unreadWhispers,i); removed=true
                end
            end
            if removed then UpdateUnreadMailIcon() end
        end
    end
end)

-- ── General whisper sound dropdown (created here; WhisperUI puts it in the tab) ──
-- We store it on API so WhisperUI and the sound-picker OnClick can reference it.
local generalSoundDropdown = API.CreateSoundSelectorButton(UIParent, "CSWhisperGeneralSoundDropdown")
generalSoundDropdown:SetParent(UIParent)  -- reparented by WhisperUI into its tab
generalSoundDropdown:Hide()
API.generalSoundDropdown = generalSoundDropdown

-- ── Event handling ─────────────────────────────────────────────────────────────
local whisperEvents = CreateFrame("Frame")
whisperEvents:RegisterEvent("PLAYER_LOGIN")
whisperEvents:RegisterEvent("CHAT_MSG_WHISPER")
whisperEvents:RegisterEvent("CHAT_MSG_WHISPER_INFORM")
whisperEvents:RegisterEvent("CHAT_MSG_BN_WHISPER")
whisperEvents:RegisterEvent("CHAT_MSG_BN_WHISPER_INFORM")

whisperEvents:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_LOGIN" then
        LoadWhisperSettings()
        -- Restore icon position
        if BuffAlertDB and BuffAlertDB.unreadMailIconPos then
            unreadMailIcon:ClearAllPoints()
            unreadMailIcon:SetPoint("CENTER",UIParent,"CENTER",
                BuffAlertDB.unreadMailIconPos.x or 0, BuffAlertDB.unreadMailIconPos.y or 0)
        end
        if not whisperIndicatorEnabled then unreadMailIcon:Hide() end
        -- Restore general sound selection
        if BuffAlertDB and BuffAlertDB.generalWhisperSound then
            generalSoundDropdown:SetSelectedSound(BuffAlertDB.generalWhisperSound, BuffAlertDB.generalWhisperSoundIsID)
        end

    elseif event == "CHAT_MSG_WHISPER" and whisperIndicatorEnabled then
        -- Helper: force a fully detainted copy of a string.
        -- string.format("%s", ...) alone does not strip taint in all WoW builds;
        -- rebuilding char-by-char forces a new, clean string allocation.
        local function Detaint(s)
            if not s or s == "" then return "" end
            local chars = {}
            for i = 1, #s do chars[i] = string.sub(s, i, i) end
            return table.concat(chars)
        end

        local message  = Detaint(tostring((...) or ""))
        local sender   = Detaint(tostring(select(2,...) or ""))
        local guid     = Detaint(tostring(select(3,...) or ""))
        local unknown1 = Detaint(tostring(select(4,...) or ""))
        local unknown2 = Detaint(tostring(select(5,...) or ""))

        local senderName = sender
        if senderName=="" then senderName=unknown1 end
        if senderName=="" then senderName=unknown2 end
        if senderName=="" then senderName=guid end
        senderName = senderName:match("^%s*(.-)%s*$")
        if not senderName or senderName=="" then return end

        local isAlreadyFocused = false
        local currentChatFrame = SELECTED_CHAT_FRAME
        local ok, focused = pcall(function()
            return currentChatFrame and currentChatFrame.chatTarget
                   and API.NormalizeName(currentChatFrame.chatTarget)==API.NormalizeName(senderName)
        end)
        if ok and focused then isAlreadyFocused = true end

        if not isAlreadyFocused then
            local isAlreadyUnread = false
            for _,name in ipairs(unreadWhispers) do
                local okCmp, match = pcall(function()
                    return name and API.NormalizeName(name)==API.NormalizeName(senderName)
                end)
                if okCmp and match then isAlreadyUnread=true; break end
            end
            if not isAlreadyUnread then table.insert(unreadWhispers, senderName) end
            UpdateUnreadMailIcon()
        end

        -- Sound: per-person first, then general
        local customSound, customSoundIsID
        for _,person in ipairs(whisperList) do
            local okCmp, match = pcall(function()
                return person.name and API.NormalizeName(person.name)==API.NormalizeName(senderName)
            end)
            if okCmp and match then
                customSound=person.sound; customSoundIsID=person.soundIsID; break
            end
        end
        if customSound then
            API.PlayCustomSound(customSound, customSoundIsID)
        elseif whisperEnabled then
            if generalSoundDropdown.selectedSound then
                API.PlayCustomSound(generalSoundDropdown.selectedSound, generalSoundDropdown.selectedSoundIsID)
            else API.PlayCustomSound(12743, true) end
        end

    elseif event == "CHAT_MSG_WHISPER_INFORM" then
        local message  = string.format("%s", tostring((...) or ""))
        local receiver = string.format("%s", tostring(select(2,...) or ""))
        if receiver~="" and unreadWhispers and #unreadWhispers>0 then
            local normReceiver = API.NormalizeName(receiver)
            for i=#unreadWhispers,1,-1 do
                if unreadWhispers[i] and API.NormalizeName(unreadWhispers[i])==normReceiver then
                    table.remove(unreadWhispers,i)
                end
            end
            UpdateUnreadMailIcon()
        end
        if not ignoreOutgoingWhispers and (whisperEnabled or #whisperList>0) and receiver~="" then
            local customSound
            for _,person in ipairs(whisperList) do
                if person.name and API.NormalizeName(person.name)==API.NormalizeName(receiver) then
                    customSound=person.sound; break
                end
            end
            if customSound then API.PlayCustomSound(customSound, false)
            elseif whisperEnabled and generalSoundDropdown.selectedSound then
                API.PlayCustomSound(generalSoundDropdown.selectedSound, generalSoundDropdown.selectedSoundIsID)
            end
        end

    elseif event == "CHAT_MSG_BN_WHISPER" and whisperIndicatorEnabled then
        local message = string.format("%s", tostring((...) or ""))
        local sender  = string.format("%s", tostring(select(2,...) or ""))
        if sender~="" then
            local isAlreadyUnread = false
            for _,name in ipairs(unreadWhispers) do
                if API.NormalizeBNName(name)==API.NormalizeBNName(sender) then isAlreadyUnread=true; break end
            end
            if not isAlreadyUnread then table.insert(unreadWhispers, sender) end
            UpdateUnreadMailIcon()
            local customSound, customSoundIsID
            for _,person in ipairs(whisperList) do
                if person.name and API.NormalizeBNName(person.name)==API.NormalizeBNName(sender) then
                    customSound=person.sound; customSoundIsID=person.soundIsID or false; break
                end
            end
            if customSound then API.PlayCustomSound(customSound, customSoundIsID)
            elseif whisperEnabled then
                if generalSoundDropdown.selectedSound then
                    API.PlayCustomSound(generalSoundDropdown.selectedSound, generalSoundDropdown.selectedSoundIsID)
                else API.PlayCustomSound(12743,true) end
            end
        end

    elseif event == "CHAT_MSG_BN_WHISPER_INFORM" then
        local message  = string.format("%s", tostring((...) or ""))
        local receiver = string.format("%s", tostring(select(2,...) or ""))
        if receiver~="" and unreadWhispers and #unreadWhispers>0 then
            for i=#unreadWhispers,1,-1 do
                if unreadWhispers[i] and API.NormalizeBNName(unreadWhispers[i])==API.NormalizeBNName(receiver) then
                    table.remove(unreadWhispers,i)
                end
            end
            UpdateUnreadMailIcon()
        end
        if not ignoreOutgoingWhispers and (whisperEnabled or #whisperList>0) then
            local customSound
            for _,person in ipairs(whisperList) do
                if person.name and API.NormalizeBNName(person.name)==API.NormalizeBNName(receiver) then
                    customSound=person.sound; break
                end
            end
            if customSound then API.PlayCustomSound(customSound,false)
            elseif whisperEnabled and generalSoundDropdown.selectedSound then
                API.PlayCustomSound(generalSoundDropdown.selectedSound, generalSoundDropdown.selectedSoundIsID)
            end
        end
    end
end)

-- ── Layout handle provider for the unread icon ────────────────────────────────
API.RegisterLayoutHandles(function()
    local ox, oy = 0, 0
    if BuffAlertDB and BuffAlertDB.unreadMailIconPos then
        ox = BuffAlertDB.unreadMailIconPos.x or 0
        oy = BuffAlertDB.unreadMailIconPos.y or 0
    else
        ox = math.floor(UIParent:GetWidth()/2 - 44)
        oy = math.floor(UIParent:GetHeight()/2 - 44)
    end
    return {{
        label          = "Unread Whisper Icon",
        iconTex        = "Interface\\Icons\\INV_Letter_15",
        ox             = ox, oy = oy,
        liveIconTarget = "MidnightQoLUnreadMailIcon",
        saveCallback   = function(nx,ny)
            local icon = _G["MidnightQoLUnreadMailIcon"]
            if icon then icon:ClearAllPoints(); icon:SetPoint("CENTER",UIParent,"CENTER",nx,ny) end
            if BuffAlertDB then BuffAlertDB.unreadMailIconPos = {point="CENTER",x=nx,y=ny} end
        end,
    }}
end)

-- ── Slash command ─────────────────────────────────────────────────────────────
SLASH_CUSTOMWHISPERTEST1 = "/whispertest"
SlashCmdList["CUSTOMWHISPERTEST"] = function()
    table.insert(unreadWhispers, "TestPlayer")
    UpdateUnreadMailIcon()
    print("|cFF00FF00[MidnightQoL]|r Added test whisper. Count: "..#unreadWhispers)
end
