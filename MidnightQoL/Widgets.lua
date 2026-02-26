-- ============================================================
-- MidnightQoL Widgets.lua
-- Shared searchable picker panels and selector button factories.
-- Populates MidnightQoLAPI with widget factory functions.
-- ============================================================

local API = MidnightQoLAPI

-- ============================================================
-- Shared Searchable Image Picker
-- ============================================================
local imagePickerPanel = CreateFrame("Frame", "CustomImagePickerPanel", UIParent, "BackdropTemplate")
imagePickerPanel:SetSize(280, 320)
imagePickerPanel:SetFrameStrata("TOOLTIP")
imagePickerPanel:SetBackdrop({
    bgFile   = "Interface/DialogFrame/UI-DialogBox-Background",
    edgeFile = "Interface/DialogFrame/UI-DialogBox-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = {left = 4, right = 4, top = 4, bottom = 4}
})
imagePickerPanel:SetBackdropColor(0.08, 0.08, 0.12, 0.97)
imagePickerPanel:Hide()

local imagePickerSearch = CreateFrame("EditBox", "CustomImagePickerSearch", imagePickerPanel, "InputBoxTemplate")
imagePickerSearch:SetSize(250, 20)
imagePickerSearch:SetPoint("TOPLEFT", 15, -10)
imagePickerSearch:SetAutoFocus(false)
imagePickerSearch:SetMaxLetters(100)

local imagePickerScroll = CreateFrame("ScrollFrame", "CustomImagePickerScroll", imagePickerPanel, "UIPanelScrollFrameTemplate")
imagePickerScroll:SetPoint("TOPLEFT",  8, -38)
imagePickerScroll:SetPoint("BOTTOMRIGHT", -28, 8)

local imagePickerContent = CreateFrame("Frame", "CustomImagePickerContent", imagePickerScroll)
imagePickerContent:SetSize(248, 1)
imagePickerScroll:SetScrollChild(imagePickerContent)

local IMG_ROW_HEIGHT = 28
local MAX_IMG_ROWS   = 80
local imagePickerRows = {}

for i = 1, MAX_IMG_ROWS do
    local btn = CreateFrame("Button", "ImagePickerRow" .. i, imagePickerContent)
    btn:SetSize(248, IMG_ROW_HEIGHT)
    btn:SetPoint("TOPLEFT", 0, -(i - 1) * IMG_ROW_HEIGHT)
    btn:Hide()
    local hl = btn:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.12)
    local thumb = btn:CreateTexture(nil, "ARTWORK")
    thumb:SetSize(22, 22); thumb:SetPoint("LEFT", 2, 0)
    btn.thumb = thumb
    local lbl = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lbl:SetPoint("LEFT", 28, 0); lbl:SetJustifyH("LEFT"); lbl:SetWidth(215)
    btn.lbl = lbl
    imagePickerRows[i] = btn
end

imagePickerPanel.onSelect     = nil
imagePickerPanel.allImages    = {}
imagePickerPanel.anchorBtn    = nil
imagePickerPanel.spellIdRef   = nil

local function RefreshImagePickerRows(filter)
    filter = (filter or ""):lower()
    local count = 0
    for _, row in ipairs(imagePickerRows) do row:Hide() end

    -- This-spell's icon row
    if imagePickerPanel.spellIdRef then
        local sid = imagePickerPanel.spellIdRef()
        if sid and sid > 0 then
            local info = C_Spell.GetSpellInfo(sid)
            if info and info.iconID then
                count = count + 1
                local row = imagePickerRows[count]
                row.lbl:SetText("|cFF00FF00" .. info.name .. " (spell icon)|r")
                row.thumb:SetTexture(info.iconID)
                row.imgData = { name = info.name .. " (spell icon)", path = info.iconID, isThisSpellIcon = true }
                row:SetScript("OnClick", function(self)
                    if self.imgData and imagePickerPanel.onSelect then imagePickerPanel.onSelect(self.imgData) end
                    imagePickerPanel:Hide()
                end)
                row:Show()
            end
        end
    end

    -- Custom path entry
    count = count + 1
    local customRow = imagePickerRows[count]
    customRow.lbl:SetText("|cFFFFD700Custom path / spell:ID…|r")
    customRow.thumb:SetTexture(nil)
    customRow.imgData = {name = "Custom", path = nil, isCustom = true}
    customRow:SetScript("OnClick", function()
        imagePickerPanel:Hide()
        if imagePickerPanel.onManualEntry then imagePickerPanel.onManualEntry() end
    end)
    customRow:Show()

    for _, img in ipairs(imagePickerPanel.allImages) do
        if img.isSeparator then
            count = count + 1
            if count <= MAX_IMG_ROWS then
                local row = imagePickerRows[count]
                row.lbl:SetText(img.name); row.lbl:SetTextColor(0.6, 0.8, 1, 1)
                row.thumb:SetTexture(nil); row.imgData = nil
                row:SetScript("OnClick", function() end); row:Show()
            end
        elseif filter == "" or img.name:lower():find(filter, 1, true) then
            count = count + 1
            if count <= MAX_IMG_ROWS then
                local row = imagePickerRows[count]
                row.lbl:SetText(img.name); row.lbl:SetTextColor(1, 1, 1, 1)
                if img.path and not img.isSpellIcon then row.thumb:SetTexture(img.path)
                else row.thumb:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark") end
                row.imgData = img
                row:SetScript("OnClick", function(self)
                    if self.imgData and imagePickerPanel.onSelect then imagePickerPanel.onSelect(self.imgData) end
                    imagePickerPanel:Hide()
                end)
                row:Show()
            end
        end
    end
    imagePickerContent:SetHeight(math.max(1, count * IMG_ROW_HEIGHT))
end

imagePickerSearch:SetScript("OnTextChanged", function(self) RefreshImagePickerRows(self:GetText()) end)
imagePickerPanel:SetScript("OnHide", function() imagePickerSearch:SetText(""); imagePickerSearch:ClearFocus() end)

local function OpenImagePicker(anchorFrame, onSelect, onManualEntry, spellIdRef)
    imagePickerPanel.allImages     = API.GetAvailableImages()
    imagePickerPanel.onSelect      = onSelect
    imagePickerPanel.onManualEntry = onManualEntry
    imagePickerPanel.anchorBtn     = anchorFrame
    imagePickerPanel.spellIdRef    = spellIdRef
    imagePickerPanel:ClearAllPoints()
    imagePickerPanel:SetPoint("TOPLEFT", anchorFrame, "BOTTOMLEFT", 0, -2)
    RefreshImagePickerRows("")
    imagePickerSearch:SetText("")
    imagePickerPanel:Show()
    imagePickerSearch:SetFocus()
end

local function CreateImageSelectorButton(parent, name, hiddenInputRef, spellIdRef)
    local btn = CreateFrame("Button", name, parent, "GameMenuButtonTemplate")
    btn:SetSize(140, 20)
    btn.selectedImage = nil
    btn.spellIdRef    = spellIdRef

    local thumb = btn:CreateTexture(nil, "OVERLAY")
    thumb:SetSize(16, 16); thumb:SetPoint("LEFT", btn, "LEFT", 4, 0)
    btn.thumb = thumb

    local function updateLabel(path)
        if type(path) == "number" then path = tostring(path) end
        btn.selectedImage = path
        if path and path ~= "" then
            local spellId = path:match("^spell:(%d+)$")
            if spellId then
                local info = C_Spell.GetSpellInfo(tonumber(spellId))
                thumb:SetTexture(info and info.iconID or "Interface\\Icons\\INV_Misc_QuestionMark")
            elseif tonumber(path) then
                thumb:SetTexture(tonumber(path))
            else
                thumb:SetTexture(path)
            end
            local display = path:match("([^\\//]+)$") or path
            if #display > 18 then display = display:sub(1, 16) .. "…" end
            btn:SetText("  " .. display)
        else
            thumb:SetTexture(nil); btn:SetText("No Image")
        end
        local fs = btn:GetFontString()
        if fs then fs:SetPoint("LEFT", btn, "LEFT", 24, 0) end
        if hiddenInputRef then hiddenInputRef:SetText(path or "") end
    end

    btn.SetSelectedImage = function(self, path) updateLabel(path) end

    btn:SetScript("OnClick", function(self)
        if imagePickerPanel:IsShown() and imagePickerPanel.anchorBtn == self then
            imagePickerPanel:Hide(); return
        end
        OpenImagePicker(self,
            function(imgData)
                if imgData.isThisSpellIcon then updateLabel(imgData.path)
                elseif imgData.isSpellIcon then updateLabel("spell_icon")
                else updateLabel(imgData.path) end
            end,
            function()
                local popup = CreateFrame("Frame", "CustomImageManualEntryPopup", UIParent, "BackdropTemplate")
                popup:SetSize(320, 80); popup:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
                popup:SetFrameStrata("DIALOG")
                popup:SetBackdrop({ bgFile="Interface/DialogFrame/UI-DialogBox-Background",
                    edgeFile="Interface/DialogFrame/UI-DialogBox-Border",
                    tile=true, tileSize=16, edgeSize=16, insets={left=4,right=4,top=4,bottom=4} })
                popup:SetBackdropColor(0.05, 0.05, 0.1, 0.98)

                local lbl = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                lbl:SetPoint("TOPLEFT", 12, -12)
                lbl:SetText("Enter texture path or  spell:ID  (e.g. spell:12345):")

                local eb = CreateFrame("EditBox", nil, popup, "InputBoxTemplate")
                eb:SetSize(260, 20); eb:SetPoint("TOPLEFT", 12, -30)
                eb:SetAutoFocus(true); eb:SetMaxLetters(200)
                eb:SetText(btn.selectedImage or ""); eb:HighlightText()

                local ok = CreateFrame("Button", nil, popup, "GameMenuButtonTemplate")
                ok:SetSize(60, 20); ok:SetPoint("BOTTOMRIGHT", -10, 8); ok:SetText("OK")
                ok:SetScript("OnClick", function()
                    local val = eb:GetText()
                    if val ~= "" then updateLabel(val) end
                    popup:Hide(); popup = nil
                end)
                eb:SetScript("OnEnterPressed", function() ok:Click() end)
                eb:SetScript("OnEscapePressed", function() popup:Hide(); popup = nil end)

                local cancel = CreateFrame("Button", nil, popup, "GameMenuButtonTemplate")
                cancel:SetSize(60, 20); cancel:SetPoint("RIGHT", ok, "LEFT", -4, 0); cancel:SetText("Cancel")
                cancel:SetScript("OnClick", function() popup:Hide(); popup = nil end)

                local clr = CreateFrame("Button", nil, popup, "GameMenuButtonTemplate")
                clr:SetSize(60, 20); clr:SetPoint("LEFT", popup, "BOTTOMLEFT", 10, 8); clr:SetText("Clear")
                clr:SetScript("OnClick", function() updateLabel(nil); popup:Hide(); popup = nil end)
            end,
            self.spellIdRef
        )
    end)

    updateLabel(nil)
    return btn
end

-- ============================================================
-- Shared Searchable Sound Picker
-- ============================================================
local soundPickerPanel = CreateFrame("Frame", "CustomSoundPickerPanel", UIParent, "BackdropTemplate")
soundPickerPanel:SetSize(220, 280)
soundPickerPanel:SetFrameStrata("TOOLTIP")
soundPickerPanel:SetBackdrop({
    bgFile = "Interface/DialogFrame/UI-DialogBox-Background",
    edgeFile = "Interface/DialogFrame/UI-DialogBox-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = {left = 4, right = 4, top = 4, bottom = 4}
})
soundPickerPanel:SetBackdropColor(0.1, 0.1, 0.1, 0.95)
soundPickerPanel:Hide()

local pickerSearch = CreateFrame("EditBox", "CustomSoundPickerSearch", soundPickerPanel, "InputBoxTemplate")
pickerSearch:SetSize(190, 20); pickerSearch:SetPoint("TOPLEFT", 15, -10)
pickerSearch:SetAutoFocus(false); pickerSearch:SetMaxLetters(50)

local pickerScroll = CreateFrame("ScrollFrame", "CustomSoundPickerScroll", soundPickerPanel, "UIPanelScrollFrameTemplate")
pickerScroll:SetPoint("TOPLEFT", 8, -38); pickerScroll:SetPoint("BOTTOMRIGHT", -28, 8)

local pickerContent = CreateFrame("Frame", "CustomSoundPickerContent", pickerScroll)
pickerContent:SetSize(190, 1); pickerScroll:SetScrollChild(pickerContent)

local pickerRows = {}
local ROW_HEIGHT = 22
local MAX_ROWS   = 200

for i = 1, MAX_ROWS do
    local btn = CreateFrame("Button", "SoundPickerRow" .. i, pickerContent)
    btn:SetSize(190, ROW_HEIGHT); btn:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_HEIGHT); btn:Hide()
    local hl = btn:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1,1,1,0.15)
    local label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("LEFT", 4, 0); label:SetJustifyH("LEFT")
    btn.label = label
    pickerRows[i] = btn
end

soundPickerPanel.onSelect  = nil
soundPickerPanel.allSounds = {}
soundPickerPanel.anchorBtn = nil

local function RefreshPickerRows(filter)
    filter = (filter or ""):lower()
    local count = 0
    for _, row in ipairs(pickerRows) do row:Hide() end
    for _, sound in ipairs(soundPickerPanel.allSounds) do
        if filter == "" or sound.name:lower():find(filter, 1, true) then
            count = count + 1
            if count <= MAX_ROWS then
                local row = pickerRows[count]
                row.label:SetText(sound.name)
                row.soundData = sound
                row:SetScript("OnClick", function(self)
                    local sd = self.soundData
                    C_Timer.After(0, function() API.PlayCustomSound(sd.path, sd.isID) end)
                    if soundPickerPanel.onSelect then soundPickerPanel.onSelect(self.soundData) end
                    soundPickerPanel:Hide()
                end)
                row:Show()
            end
        end
    end
    pickerContent:SetHeight(math.max(1, count * ROW_HEIGHT))
end

pickerSearch:SetScript("OnTextChanged", function(self) RefreshPickerRows(self:GetText()) end)
soundPickerPanel:SetScript("OnHide", function() pickerSearch:SetText(""); pickerSearch:ClearFocus() end)

local function OpenSoundPicker(anchorFrame, onSelect)
    soundPickerPanel.allSounds = API.GetAvailableSounds()
    soundPickerPanel.onSelect  = onSelect
    soundPickerPanel:ClearAllPoints()
    soundPickerPanel:SetPoint("TOPLEFT", anchorFrame, "BOTTOMLEFT", 0, -2)
    RefreshPickerRows("")
    pickerSearch:SetText("")
    soundPickerPanel:Show()
    pickerSearch:SetFocus()
end

local function CreateSoundSelectorButton(parent, name)
    local btn = CreateFrame("Button", name, parent, "GameMenuButtonTemplate")
    btn:SetSize(160, 22)
    btn.selectedSound     = nil
    btn.selectedSoundIsID = false
    btn.selectedSoundName = nil

    local function updateLabel()
        if btn.selectedSoundName then
            btn:SetText(btn.selectedSoundName)
        elseif btn.selectedSound then
            local sounds = API.GetAvailableSounds()
            for _, s in ipairs(sounds) do
                if s.path == btn.selectedSound then
                    btn.selectedSoundName = s.name; btn:SetText(s.name); return
                end
            end
            btn:SetText("Select Sound")
        else
            btn:SetText("Select Sound")
        end
    end

    btn:SetScript("OnClick", function(self)
        if soundPickerPanel:IsShown() and soundPickerPanel.anchorBtn == self then
            soundPickerPanel:Hide(); return
        end
        soundPickerPanel.anchorBtn = self
        OpenSoundPicker(self, function(sound)
            self.selectedSound     = sound.path
            self.selectedSoundIsID = sound.isID
            self.selectedSoundName = sound.name
            updateLabel()
        end)
    end)

    btn.SetSelectedSound = function(self, path, isID)
        self.selectedSound     = path
        self.selectedSoundIsID = isID
        self.selectedSoundName = nil
        updateLabel()
    end

    updateLabel()
    return btn
end

-- ============================================================
-- Shared Searchable Spell Picker
-- ============================================================
local spellPickerPanel = CreateFrame("Frame", "CustomSpellPickerPanel", UIParent, "BackdropTemplate")
spellPickerPanel:SetSize(240, 280)
spellPickerPanel:SetFrameStrata("TOOLTIP")
spellPickerPanel:SetBackdrop({
    bgFile = "Interface/DialogFrame/UI-DialogBox-Background",
    edgeFile = "Interface/DialogFrame/UI-DialogBox-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = {left = 4, right = 4, top = 4, bottom = 4}
})
spellPickerPanel:SetBackdropColor(0.1, 0.1, 0.1, 0.95)
spellPickerPanel:Hide()

local spellPickerSearch = CreateFrame("EditBox", "CustomSpellPickerSearch", spellPickerPanel, "InputBoxTemplate")
spellPickerSearch:SetSize(210, 20); spellPickerSearch:SetPoint("TOPLEFT", 15, -10)
spellPickerSearch:SetAutoFocus(false); spellPickerSearch:SetMaxLetters(50)

local spellPickerScroll = CreateFrame("ScrollFrame", "CustomSpellPickerScroll", spellPickerPanel, "UIPanelScrollFrameTemplate")
spellPickerScroll:SetPoint("TOPLEFT", 8, -38); spellPickerScroll:SetPoint("BOTTOMRIGHT", -28, 8)

local spellPickerContent = CreateFrame("Frame", "CustomSpellPickerContent", spellPickerScroll)
spellPickerContent:SetSize(210, 1); spellPickerScroll:SetScrollChild(spellPickerContent)

local spellPickerRows = {}
local SPELL_ROW_HEIGHT = 22
local MAX_SPELL_ROWS   = 100

for i = 1, MAX_SPELL_ROWS do
    local btn = CreateFrame("Button", "SpellPickerRow" .. i, spellPickerContent)
    btn:SetSize(210, SPELL_ROW_HEIGHT); btn:SetPoint("TOPLEFT", 0, -(i-1)*SPELL_ROW_HEIGHT); btn:Hide()
    local hl = btn:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1,1,1,0.15)
    local label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("LEFT", 4, 0); label:SetJustifyH("LEFT")
    btn.label = label
    spellPickerRows[i] = btn
end

spellPickerPanel.onSelect  = nil
spellPickerPanel.allSpells = {}
spellPickerPanel.anchorBtn = nil

local function RefreshSpellPickerRows(filter)
    filter = (filter or ""):lower()
    local count = 0
    for _, row in ipairs(spellPickerRows) do row:Hide() end

    local function applyRow(row, spellData, displayText, color)
        row.label:SetText(color and (color .. displayText .. "|r") or displayText)
        row.spellData = spellData
        row:SetScript("OnClick", function(self)
            if spellPickerPanel.onSelect and self.spellData then spellPickerPanel.onSelect(self.spellData) end
            spellPickerPanel:Hide()
        end)
        row:Show()
    end

    count = count + 1
    applyRow(spellPickerRows[count], {id=nil, name="Custom", ids=nil}, "Custom (manual ID)", "|cFFFFD700")

    for _, spell in ipairs(spellPickerPanel.allSpells) do
        local displayName = spell.ids and spell.name or (spell.name .. " (" .. spell.id .. ")")
        if filter == "" or displayName:lower():find(filter, 1, true) then
            count = count + 1
            if count <= MAX_SPELL_ROWS then applyRow(spellPickerRows[count], spell, displayName) end
        end
    end
    spellPickerContent:SetHeight(math.max(1, count * SPELL_ROW_HEIGHT))
end

spellPickerSearch:SetScript("OnTextChanged", function(self) RefreshSpellPickerRows(self:GetText()) end)
spellPickerPanel:SetScript("OnHide", function() spellPickerSearch:SetText(""); spellPickerSearch:ClearFocus() end)

local function OpenSpellPicker(anchorFrame, onSelect)
    spellPickerPanel.onSelect = onSelect
    spellPickerPanel:ClearAllPoints()
    spellPickerPanel:SetPoint("TOPLEFT", anchorFrame, "BOTTOMLEFT", 0, -2)
    RefreshSpellPickerRows("")
    spellPickerSearch:SetText("")
    spellPickerPanel:Show()
    spellPickerSearch:SetFocus()
end

local function CreateSpellSelectorButton(parent, name, auraType, idInputRef)
    local btn = CreateFrame("Button", name, parent, "GameMenuButtonTemplate")
    btn:SetSize(160, 22)
    btn.auraType   = auraType
    btn.idInputRef = idInputRef

    btn:SetScript("OnClick", function(self)
        if spellPickerPanel:IsShown() and spellPickerPanel.anchorBtn == self then
            spellPickerPanel:Hide(); return
        end
        spellPickerPanel.anchorBtn = self
        -- GetAvailableSpells is provided by BuffAlerts sub-addon and stored on API
        spellPickerPanel.allSpells = API.GetAvailableSpells and API.GetAvailableSpells(self.auraType) or {}
        OpenSpellPicker(self, function(spell)
            if spell.id == nil then btn:SetText("Custom"); return end
            btn:SetText(spell.name)
            btn.selectedSpell    = spell.id
            btn.selectedSpellIds = spell.ids
            if btn.idInputRef then
                if spell.ids then btn.idInputRef:SetText(table.concat(spell.ids, ","))
                else btn.idInputRef:SetText(tostring(spell.id)) end
            end
        end)
    end)

    btn:SetText("Select Spell")
    return btn
end

-- ── Publish to API ─────────────────────────────────────────────────────────────
API.CreateSoundSelectorButton = CreateSoundSelectorButton
API.CreateImageSelectorButton = CreateImageSelectorButton
API.CreateSpellSelectorButton = CreateSpellSelectorButton
API.OpenSoundPicker           = OpenSoundPicker
API.OpenImagePicker           = OpenImagePicker
API.OpenSpellPicker           = OpenSpellPicker
