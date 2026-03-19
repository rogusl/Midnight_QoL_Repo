-- ============================================================
-- MidnightQoL_Whisper / WhisperUI.lua
-- Whisper tab: general sound, per-person entries.
-- Saves to BuffAlertDB root (account-wide, not per-spec).
-- ============================================================

local API = MidnightQoLAPI

-- ── Content frame ─────────────────────────────────────────────────────────────
local whisperFrame = CreateFrame("Frame", "MidnightQoLWhisperFrame", UIParent)
whisperFrame:SetSize(600, 1); whisperFrame:Hide()

-- ── General section ────────────────────────────────────────────────────────────
local generalLabel = whisperFrame:CreateFontString(nil,"OVERLAY","GameFontNormalLarge")
generalLabel:SetPoint("TOPLEFT",0,-10); generalLabel:SetText("General Whisper Alert")

local generalEnableCheckbox = CreateFrame("CheckButton","BuffAlertGeneralWhisperEnableCheckbox",whisperFrame,"UICheckButtonTemplate")
generalEnableCheckbox:SetPoint("TOPLEFT",0,-35)

local generalEnableLabel = generalEnableCheckbox:CreateFontString(nil,"OVERLAY","GameFontNormal")
generalEnableLabel:SetPoint("LEFT",generalEnableCheckbox,"RIGHT",5,0)
generalEnableLabel:SetText("Enable general whisper alerts")

local ignoreOutgoingCheckbox = CreateFrame("CheckButton","BuffAlertIgnoreOutgoingCheckbox",whisperFrame,"UICheckButtonTemplate")
ignoreOutgoingCheckbox:SetPoint("TOPLEFT",0,-55)

local ignoreOutgoingLabel = ignoreOutgoingCheckbox:CreateFontString(nil,"OVERLAY","GameFontNormal")
ignoreOutgoingLabel:SetPoint("LEFT",ignoreOutgoingCheckbox,"RIGHT",5,0)
ignoreOutgoingLabel:SetText("Ignore outgoing whispers (ones you send)")

local generalSoundLabel = whisperFrame:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
generalSoundLabel:SetPoint("TOPLEFT",0,-80); generalSoundLabel:SetText("Sound:")

-- Re-parent the general sound dropdown (created in Whisper.lua) into this tab frame
local generalSoundDropdown = API.generalSoundDropdown
generalSoundDropdown:SetParent(whisperFrame)
generalSoundDropdown:ClearAllPoints()
generalSoundDropdown:SetPoint("TOPLEFT",60,-83)
generalSoundDropdown:Show()

local generalTestBtn = CreateFrame("Button","BuffAlertGeneralWhisperTestBtn",whisperFrame,"GameMenuButtonTemplate")
generalTestBtn:SetSize(50,22); generalTestBtn:SetPoint("TOPLEFT",280,-77); generalTestBtn:SetText("Test")
generalTestBtn:SetScript("OnClick",function()
    if generalSoundDropdown.selectedSound then
        API.PlayCustomSound(generalSoundDropdown.selectedSound, generalSoundDropdown.selectedSoundIsID)
    end
end)

local sep1 = whisperFrame:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
sep1:SetPoint("TOPLEFT",0,-110)
sep1:SetText("_________________________________________________________________")

local perPersonLabel = whisperFrame:CreateFontString(nil,"OVERLAY","GameFontNormalLarge")
perPersonLabel:SetPoint("TOPLEFT",0,-130); perPersonLabel:SetText("Per-Person Whisper Sounds")

-- ── Per-person entries ─────────────────────────────────────────────────────────
local whisperList = API.whisperList  -- same table reference

local function CreateWhisperEntry(parentFrame, index)
    local yOffset = -170 - ((index-1)*50)
    local ef = CreateFrame("Frame","BuffAlertWhisperEntry"..index,parentFrame)
    ef:SetSize(600,45); ef:SetPoint("TOPLEFT",parentFrame,"TOPLEFT",0,yOffset)

    local nameLabel = ef:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    nameLabel:SetPoint("TOPLEFT",0,0); nameLabel:SetText("Name:")

    local nameInput = CreateFrame("EditBox","BuffAlertWhisperNameInput"..index,ef,"InputBoxTemplate")
    nameInput:SetSize(120,20); nameInput:SetPoint("TOPLEFT",45,-2)
    nameInput:SetAutoFocus(false); nameInput.index = index

    local soundLabel = ef:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    soundLabel:SetPoint("TOPLEFT",180,0); soundLabel:SetText("Sound:")

    local soundDropdown = API.CreateSoundSelectorButton(ef,"BuffAlertWhisperSoundDropdown"..index)
    soundDropdown:SetPoint("TOPLEFT",230,0); soundDropdown.index = index

    local testBtn = CreateFrame("Button","BuffAlertWhisperTestBtn"..index,ef,"GameMenuButtonTemplate")
    testBtn:SetSize(50,22); testBtn:SetPoint("TOPRIGHT",-70,-2); testBtn:SetText("Test")
    testBtn:SetScript("OnClick",function()
        if soundDropdown.selectedSound then
            API.PlayCustomSound(soundDropdown.selectedSound, soundDropdown.selectedSoundIsID)
        end
    end)

    local removeBtn = CreateFrame("Button","BuffAlertWhisperRemoveBtn"..index,ef,"GameMenuButtonTemplate")
    removeBtn:SetSize(50,22); removeBtn:SetPoint("TOPRIGHT",-10,-2); removeBtn:SetText("Remove")
    removeBtn.index = index
    removeBtn:SetScript("OnClick",function(self)
        table.remove(whisperList,self.index); RefreshWhisperListUI()
    end)

    return {frame=ef, nameInput=nameInput, soundDropdown=soundDropdown}
end

function RefreshWhisperListUI()
    for i=1,20 do
        if _G["BuffAlertWhisperEntry"..i] then _G["BuffAlertWhisperEntry"..i]:Hide() end
    end
    for index,person in ipairs(whisperList) do
        local entry = CreateWhisperEntry(whisperFrame,index)
        entry.nameInput:SetText(person.name or "")
        entry.soundDropdown:SetSelectedSound(person.sound, person.soundIsID)
    end
    whisperFrame:SetHeight(math.max(300, 170+(#whisperList*50)))
end
API.RefreshWhisperListUI = RefreshWhisperListUI

-- ── Sync UI from current settings ─────────────────────────────────────────────
local function SyncWhisperUI()
    local wEnabled, ignoreOutgoing, indicatorEnabled = API.GetWhisperState()
    generalEnableCheckbox:SetChecked(wEnabled)
    ignoreOutgoingCheckbox:SetChecked(ignoreOutgoing)
    if BuffAlertDB and BuffAlertDB.generalWhisperSound then
        generalSoundDropdown:SetSelectedSound(BuffAlertDB.generalWhisperSound, BuffAlertDB.generalWhisperSoundIsID)
    end
    RefreshWhisperListUI()
end
API.SyncWhisperUI = SyncWhisperUI

-- ── Save UI values back (called from Save button hook) ─────────────────────────
local function HarvestWhisperUIValues()
    API.SetWhisperEnabled(generalEnableCheckbox:GetChecked())
    API.SetIgnoreOutgoing(ignoreOutgoingCheckbox:GetChecked())
    if BuffAlertDB then
        BuffAlertDB.generalWhisperSound     = generalSoundDropdown.selectedSound
        BuffAlertDB.generalWhisperSoundIsID = generalSoundDropdown.selectedSoundIsID
    end
    local DEFAULT_SOUND_ID = 12743
    for index,person in ipairs(whisperList) do
        local input = _G["BuffAlertWhisperNameInput"..index]
        if input then person.name = input:GetText() end
        local sd = _G["BuffAlertWhisperSoundDropdown"..index]
        if sd then
            person.sound     = sd.selectedSound or DEFAULT_SOUND_ID
            person.soundIsID = (sd.selectedSound~=nil) and sd.selectedSoundIsID or true
        end
    end
    API.SaveWhisperSettings()
end

-- Hook Core's Save button
local saveBtn = _G["MidnightQoLSaveBtn"]
if saveBtn then saveBtn:HookScript("OnClick", HarvestWhisperUIValues) end

-- ── Add Person button ─────────────────────────────────────────────────────────
local mainFrame = _G["MidnightQoLMainFrame"]
local addWhisperBtn = CreateFrame("Button","MidnightQoLAddWhisperBtn",mainFrame,"GameMenuButtonTemplate")
addWhisperBtn:SetSize(110,25); addWhisperBtn:SetPoint("BOTTOMLEFT",20,50)
addWhisperBtn:SetText("+ Add Person"); addWhisperBtn:Hide()
addWhisperBtn:SetScript("OnClick",function()
    table.insert(whisperList,{name="",sound=nil}); RefreshWhisperListUI()
end)

-- ── Tab registration ───────────────────────────────────────────────────────────
API.RegisterTab("Whisper", whisperFrame, function()
    SyncWhisperUI()
    addWhisperBtn:Show()
end, 80, nil, 4)

-- Hide add button when leaving tab
local _origUpdateAddButtons = API.UpdateAddButtons
API.UpdateAddButtons = function(tabIndex)
    addWhisperBtn:Hide()
    if _origUpdateAddButtons then _origUpdateAddButtons(tabIndex) end
end

-- ── Feature toggle checkbox wiring (whisper indicator on/off) ─────────────────
local wicb = API.whisperIndicatorEnabledCheckbox
if wicb then
    wicb:HookScript("OnClick", function(self)
        API.SetWhisperIndicator(self:GetChecked())
    end)
end
