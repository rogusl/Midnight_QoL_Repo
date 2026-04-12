-- ============================================================
-- RogUI / Modules / ImprovedCDM / ImprovedCDMUI.lua
-- UNIFIED UI with Visual Drag-and-Drop Bar Manager
-- ============================================================

local API = RogUIAPI
if not API then return end

-- ════════════════════════════════════════════════════════════
-- MASTER FRAME + TAB BAR
-- ════════════════════════════════════════════════════════════

local masterFrame = CreateFrame("Frame", "CooldownManager_Master", UIParent)
masterFrame:SetSize(1400, 2000)
masterFrame:Hide()

local tabBar = CreateFrame("Frame", nil, masterFrame)
tabBar:SetHeight(35)
tabBar:SetPoint("TOPLEFT", masterFrame, "TOPLEFT", 0, -10)
tabBar:SetPoint("TOPRIGHT", masterFrame, "TOPRIGHT", 0, -10)

local contentFrame = CreateFrame("Frame", nil, masterFrame)
contentFrame:SetPoint("TOPLEFT", masterFrame, "TOPLEFT", 0, -50)
contentFrame:SetPoint("BOTTOMRIGHT", masterFrame, "BOTTOMRIGHT", 0, 0)

local tabs = {
    { name = "CDM Bars (Drag & Drop)", idx = 1 },
    { name = "Buff Alerts",            idx = 2 },
    { name = "Keybinds",               idx = 3 },
}

local activeTab = nil

for i, tab in ipairs(tabs) do
    local btn = CreateFrame("Button", nil, tabBar, "GameMenuButtonTemplate")
    btn:SetSize(190, 25)
    btn:SetPoint("TOPLEFT", tabBar, "TOPLEFT", (i-1) * 200, 0)
    btn:SetText(tab.name)

    local frame = CreateFrame("Frame", nil, contentFrame)
    frame:SetAllPoints(contentFrame)
    frame:Hide()
    tab.btn   = btn
    tab.frame = frame

    btn:SetScript("OnClick", function()
        if activeTab then
            activeTab.btn:UnlockHighlight()
            activeTab.frame:Hide()
            if activeTab.onDeactivate then activeTab.onDeactivate() end
        end
        btn:LockHighlight()
        activeTab = tab
        tab.frame:Show()
        if tab.onActivate then tab.onActivate() end
    end)
end

-- ════════════════════════════════════════════════════════════
-- TAB 1: CDM BARS (DRAG & DROP)
-- ════════════════════════════════════════════════════════════
do
    local cdmFrame = tabs[1].frame

    local header = cdmFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    header:SetPoint("TOPLEFT", 16, -10)
    header:SetText("Cooldown Bars Manager")

    local newBarBtn = CreateFrame("Button", nil, cdmFrame, "GameMenuButtonTemplate")
    newBarBtn:SetSize(120, 24)
    newBarBtn:SetPoint("LEFT", header, "RIGHT", 20, 0)
    newBarBtn:SetText("+ Create New Bar")
    newBarBtn:SetScript("OnClick", function()
        if API.SubBars_CreateNewBar then
            API.SubBars_CreateNewBar("New Custom Bar")
            if API._SubBarsPopulateUI then API._SubBarsPopulateUI() end
        end
    end)

    local helpText = cdmFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    helpText:SetPoint("LEFT", newBarBtn, "RIGHT", 15, 0)
    helpText:SetTextColor(0.6, 0.8, 1, 1)
    helpText:SetText("Drag icons from the unassigned pool on the left, and drop them into a Bar panel on the right.")

-- ============================================================
    -- NEW: Full Alpha Sliders for Settings UI
    -- ============================================================
    local cdmAlphaSlider = CreateFrame("Slider", "ICDM_AlphaSlider", cdmFrame, "OptionsSliderTemplate")
    cdmAlphaSlider:SetPoint("TOPRIGHT", cdmFrame, "TOPRIGHT", -30, -10)
    cdmAlphaSlider:SetMinMaxValues(0.1, 1.0)
    cdmAlphaSlider:SetValueStep(0.05)
    cdmAlphaSlider:SetObeyStepOnDrag(true)
    cdmAlphaSlider:SetValue((RogUIDB and RogUIDB.cdmAlpha) or 1.0)
    _G[cdmAlphaSlider:GetName() .. "Low"]:SetText("10%")
    _G[cdmAlphaSlider:GetName() .. "High"]:SetText("100%")
    
    local currentAlpha = (RogUIDB and RogUIDB.cdmAlpha) or 1.0
    _G[cdmAlphaSlider:GetName() .. "Text"]:SetText("CDM Bar Opacity: " .. math.floor(currentAlpha * 100) .. "%")

    cdmAlphaSlider:SetScript("OnValueChanged", function(self, value)
        -- Snap the value to the nearest 5% step
        value = math.floor(value * 20 + 0.5) / 20
        
        if RogUIDB then 
            RogUIDB.cdmAlpha = value 
        end
        
        -- Update the text label dynamically as the slider moves
        _G[self:GetName() .. "Text"]:SetText("CDM Bar Opacity: " .. math.floor(value * 100) .. "%")

        -- 1. Push live update to Main CDM Bars
        if RogUIImprovedCDMDB and RogUIImprovedCDMDB.viewers then
            for setName, _ in pairs(RogUIImprovedCDMDB.viewers) do
                local frame = _G["ICDM_" .. setName]
                if frame then frame:SetAlpha(value) end
            end
        end

        -- 2. NEW: Apply alpha to SubBars using the new API function
        local API = RogUIAPI
        if API and API.SubBars_ApplyGlobalAlpha then
            API.SubBars_ApplyGlobalAlpha()
        end
    end)
    -- Left Panel: Unassigned Icons
    local leftPanel = CreateFrame("Frame", nil, cdmFrame, "BackdropTemplate")
    leftPanel:SetWidth(400)
    leftPanel:SetPoint("TOPLEFT", 16, -45)
    leftPanel:SetPoint("BOTTOMLEFT", 16, 8)
    leftPanel:SetBackdrop({bgFile="Interface/DialogFrame/UI-DialogBox-Background", edgeFile="Interface/Tooltips/UI-Tooltip-Border", tile=true, tileSize=8, edgeSize=8, insets={left=2,right=2,top=2,bottom=2}})
    
    local leftHdr = leftPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    leftHdr:SetPoint("TOPLEFT", 12, -10)
    leftHdr:SetText("|cFFFFD700Unassigned Icons|r")

    local unassignedScroll = CreateFrame("ScrollFrame", nil, leftPanel, "UIPanelScrollFrameTemplate")
    unassignedScroll:SetPoint("TOPLEFT", leftPanel, "TOPLEFT", 10, -40)
    unassignedScroll:SetPoint("BOTTOMRIGHT", leftPanel, "BOTTOMRIGHT", -10, 8)
    local unassignedContent = CreateFrame("Frame", nil, unassignedScroll)
    unassignedContent:SetSize(360, 1000)
    unassignedScroll:SetScrollChild(unassignedContent)

    -- Right Panel: Bars (fills all space to the right of leftPanel)
    local rightScroll = CreateFrame("ScrollFrame", nil, cdmFrame, "UIPanelScrollFrameTemplate")
    rightScroll:SetPoint("TOPLEFT", leftPanel, "TOPRIGHT", 16, 0)
    rightScroll:SetPoint("BOTTOMRIGHT", cdmFrame, "BOTTOMRIGHT", -8, 8)
    local rightContent = CreateFrame("Frame", nil, rightScroll)
    rightContent:SetSize(880, 1000)
    rightScroll:SetScrollChild(rightContent)

    -- Drag and Drop Engine
    local dragGhost = CreateFrame("Frame", "RogUI_UI_DragGhost", UIParent)
    dragGhost:SetSize(36, 36); dragGhost:SetFrameStrata("TOOLTIP"); dragGhost:Hide()
    local dragGhostTex = dragGhost:CreateTexture(nil, "ARTWORK"); dragGhostTex:SetAllPoints()
    local currentDrag = nil 

    local iconBtnPool = {}
    local barPanelPool = {}
    local activeDropZones = {}

    local function GetIconBtn(index)
        if not iconBtnPool[index] then
            local btn = CreateFrame("Button", nil, UIParent)
            btn:SetSize(36, 36)
            local tex = btn:CreateTexture(nil, "ARTWORK")
            tex:SetAllPoints()
            btn.tex = tex
            btn:EnableMouse(true)
            btn:RegisterForDrag("LeftButton")

            btn:SetScript("OnEnter", function(self)
                if self.iconData then
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetText("|cFFFFD700" .. tostring(self.iconData.name) .. "|r")
                    GameTooltip:Show()
                end
            end)
            btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

            btn:SetScript("OnDragStart", function(self)
                currentDrag = self.iconData
                dragGhostTex:SetTexture(self.iconData.icon)
                dragGhost:Show()
                self:SetAlpha(0.3)
                self:SetScript("OnUpdate", function()
                    local x, y = GetCursorPosition()
                    local s = UIParent:GetEffectiveScale()
                    dragGhost:ClearAllPoints()
                    dragGhost:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x/s, y/s)
                end)
            end)

            btn:SetScript("OnDragStop", function(self)
                self:SetScript("OnUpdate", nil)
                dragGhost:Hide()
                self:SetAlpha(1.0)
                if not currentDrag then return end

                local droppedBar = nil
                local cx, cy = GetCursorPosition()
                local scale = UIParent:GetEffectiveScale()
                cx, cy = cx / scale, cy / scale
                for barIndex, barPanel in pairs(activeDropZones) do
                    local l, r = barPanel:GetLeft(), barPanel:GetRight()
                    local b2, t = barPanel:GetBottom(), barPanel:GetTop()
                    if l and r and b2 and t and cx >= l and cx <= r and cy >= b2 and cy <= t then
                        droppedBar = barIndex; break
                    end
                end

                if not droppedBar and leftPanel:IsMouseOver() then
                    droppedBar = 0
                end

                if droppedBar ~= nil then
                    if droppedBar > 0 and droppedBar == currentDrag.barIndex then
                        -- Reorder within same bar.
                        -- Collect buttons for this bar sorted by current col.
                        -- Use GetCenter() for screen-space X since these buttons
                        -- live inside a ScrollFrame — GetLeft() is not screen-space.
                        local barBtns = {}
                        for _, b in ipairs(iconBtnPool) do
                            if b:IsShown() and b.iconData
                                and b.iconData.barIndex == currentDrag.barIndex
                                and b.iconData.cdID ~= currentDrag.cdID then
                                table.insert(barBtns, b)
                            end
                        end
                        table.sort(barBtns, function(a, b)
                            return (a.iconData.col or 999) < (b.iconData.col or 999)
                        end)
                        -- Find the slot the cursor is to the left of
                        local insertPos = #barBtns + 1
                        for i, b2 in ipairs(barBtns) do
                            local bx = b2:GetCenter()
                            if bx and cx < bx then
                                insertPos = i; break
                            end
                        end
                        if API.SubBars_ReorderIcon then
                            API.SubBars_ReorderIcon(currentDrag.cdID, insertPos)
                        end
                    else
                        if API.SubBars_SetBarForCooldown then
                            API.SubBars_SetBarForCooldown(currentDrag.cdID, droppedBar)
                        end
                    end
                    if API._SubBarsPopulateUI then API._SubBarsPopulateUI() end
                end
                currentDrag = nil
            end)
            iconBtnPool[index] = btn
        end
        return iconBtnPool[index]
    end

    local function GetBarPanel(index)
        if not barPanelPool[index] then
            local bp = CreateFrame("Frame", nil, rightContent, "BackdropTemplate")
            bp:SetHeight(100)
            bp:SetPoint("LEFT", rightContent, "LEFT", 0, 0)
            bp:SetPoint("RIGHT", rightContent, "RIGHT", -20, 0)
            bp:SetBackdrop({bgFile="Interface/Buttons/WHITE8x8", edgeFile="Interface/Tooltips/UI-Tooltip-Border", edgeSize=8, insets={left=2,right=2,top=2,bottom=2}})
            bp:SetBackdropColor(0.08, 0.08, 0.12, 0.9)

            local lbl = bp:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            lbl:SetPoint("TOPLEFT", 12, -12)
            lbl:SetText("Bar Name:")
            
            local nameBox = CreateFrame("EditBox", nil, bp, "InputBoxTemplate")
            nameBox:SetSize(150, 20); nameBox:SetPoint("LEFT", lbl, "RIGHT", 10, 0)
            nameBox:SetAutoFocus(false); nameBox:SetMaxLetters(24)
            nameBox:SetScript("OnEnterPressed", function(self)
                self:ClearFocus()
                if API.SubBars_SetBarSetting then API.SubBars_SetBarSetting(bp.barIndex, "label", self:GetText()) end
            end)
            bp.nameBox = nameBox

            local colsLbl = bp:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            colsLbl:SetPoint("LEFT", nameBox, "RIGHT", 20, 0); colsLbl:SetText("Cols:")
            local colsBox = CreateFrame("EditBox", nil, bp, "InputBoxTemplate")
            colsBox:SetSize(30, 20); colsBox:SetPoint("LEFT", colsLbl, "RIGHT", 10, 0)
            colsBox:SetAutoFocus(false); colsBox:SetNumeric(true)
            colsBox:SetScript("OnEnterPressed", function(self)
                self:ClearFocus()
                local v = tonumber(self:GetText())
                if v and v > 0 and API.SubBars_SetBarSetting then API.SubBars_SetBarSetting(bp.barIndex, "cols", v) end
            end)
            bp.colsBox = colsBox

            local szLbl = bp:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            szLbl:SetPoint("LEFT", colsBox, "RIGHT", 20, 0); szLbl:SetText("Icon Size:")
            local szBox = CreateFrame("EditBox", nil, bp, "InputBoxTemplate")
            szBox:SetSize(30, 20); szBox:SetPoint("LEFT", szLbl, "RIGHT", 10, 0)
            szBox:SetAutoFocus(false); szBox:SetNumeric(true)
            szBox:SetScript("OnEnterPressed", function(self)
                self:ClearFocus()
                local v = tonumber(self:GetText())
                if v and v >= 16 and v <= 80 and API.SubBars_SetBarSetting then API.SubBars_SetBarSetting(bp.barIndex, "iconSize", v) end
            end)
            bp.szBox = szBox

            local vertChk = CreateFrame("CheckButton", nil, bp, "UICheckButtonTemplate")
            vertChk:SetSize(22, 22)
            vertChk:SetPoint("LEFT", szBox, "RIGHT", 16, 0)
            vertChk.text:SetText("Vertical")
            vertChk:SetScript("OnClick", function(self)
                if API.SubBars_SetBarSetting then
                    API.SubBars_SetBarSetting(bp.barIndex, "vertical", self:GetChecked())
                end
            end)
            bp.vertChk = vertChk

            -- Per-bar alpha slider
            -- Child label widgets from OptionsSliderTemplate are not in _G at creation time,
            -- so we set their text inside OnShow (fires after the template fully initialises).
            local alphaSliderName = "RogUI_SubBarAlphaSlider_" .. index
            local alphaSlider = CreateFrame("Slider", alphaSliderName, bp, "OptionsSliderTemplate")
            alphaSlider:SetSize(160, 16)
            alphaSlider:SetPoint("LEFT", vertChk, "RIGHT", 20, 0)
            alphaSlider:SetMinMaxValues(0.1, 1.0)
            alphaSlider:SetValueStep(0.05)
            alphaSlider:SetObeyStepOnDrag(true)
            alphaSlider:SetScript("OnShow", function(self)
                local low  = _G[alphaSliderName .. "Low"]
                local high = _G[alphaSliderName .. "High"]
                local txt  = _G[alphaSliderName .. "Text"]
                if low  then low:SetText("10%") end
                if high then high:SetText("100%") end
                if txt  then
                    txt:SetText(string.format("Opacity: %d%%", math.floor(self:GetValue() * 100 + 0.5)))
                end
            end)
            alphaSlider:SetScript("OnValueChanged", function(self, value)
                if API.SubBars_SetBarSetting then
                    API.SubBars_SetBarSetting(bp.barIndex, "alpha", value)
                end
                local txt = _G[alphaSliderName .. "Text"]
                if txt then
                    txt:SetText(string.format("Opacity: %d%%", math.floor(value * 100 + 0.5)))
                end
            end)
            bp.alphaSlider = alphaSlider
            bp.alphaSliderName = alphaSliderName

            local delBtn = CreateFrame("Button", nil, bp, "GameMenuButtonTemplate")
            delBtn:SetSize(80, 22)
            delBtn:SetPoint("TOPRIGHT", bp, "TOPRIGHT", -12, -10)
            delBtn:SetText("Delete Bar")
            delBtn:SetScript("OnClick", function()
                if API.SubBars_DeleteBar then 
                    API.SubBars_DeleteBar(bp.barIndex)
                    if API._SubBarsPopulateUI then API._SubBarsPopulateUI() end
                end
            end)

            local addIconBtn = CreateFrame("Button", nil, bp, "GameMenuButtonTemplate")
            addIconBtn:SetSize(90, 22)
            addIconBtn:SetPoint("TOPRIGHT", delBtn, "TOPLEFT", -6, 0)
            addIconBtn:SetText("+ Add Icon")
            addIconBtn:SetScript("OnClick", function()
                if API._SubBars_OpenAddIconPopup then
                    API._SubBars_OpenAddIconPopup(bp.barIndex, addIconBtn)
                end
            end)

            local dropZoneBg = bp:CreateTexture(nil, "BACKGROUND")
            dropZoneBg:SetPoint("TOPLEFT", bp, "TOPLEFT", 10, -40)
            dropZoneBg:SetPoint("BOTTOMRIGHT", bp, "BOTTOMRIGHT", -10, 10)
            dropZoneBg:SetColorTexture(0, 0, 0, 0.4)

            barPanelPool[index] = bp
        end
        return barPanelPool[index]
    end

    local function PopulateSubBarsUI()
        for _, btn in ipairs(iconBtnPool) do btn:Hide(); btn:SetParent(nil) end
        for _, panel in ipairs(barPanelPool) do panel:Hide(); panel:SetParent(nil) end
        activeDropZones = {}

        local icons = API.SubBars_GetAllCooldownIDs() or {}
        local bars = API.SubBars_GetBars() or {}
        local iconCounter = 1

        -- 1. Render Bars (Right Side)
        local bY = 0
        for i, barInfo in ipairs(bars) do
            local bp = GetBarPanel(i)
            bp:SetParent(rightContent)
            bp:SetPoint("TOPLEFT", rightContent, "TOPLEFT", 0, bY)
            bp.barIndex = barInfo.index
            bp.nameBox:SetText(barInfo.label)
            bp.colsBox:SetText(tostring(barInfo.cols))
            bp.szBox:SetText(tostring(barInfo.iconSize))
            bp.vertChk:SetChecked(barInfo.vertical or false)
            local alphaVal = barInfo.alpha or 1.0
            bp.alphaSlider:SetValue(alphaVal)
            local alphaLbl = _G[bp.alphaSliderName .. "Text"]
            if alphaLbl then
                alphaLbl:SetText(string.format("Opacity: %d%%", math.floor(alphaVal * 100 + 0.5)))
            end
            activeDropZones[barInfo.index] = bp

            local bIcons = {}
            for _, ic in ipairs(icons) do if ic.barIndex == barInfo.index then table.insert(bIcons, ic) end end
            table.sort(bIcons, function(a, b) return (a.col or 999) < (b.col or 999) end)

            local rowCount = math.ceil(math.max(1, #bIcons) / 20)
            local bpHeight = 55 + (rowCount * 40)
            bp:SetHeight(bpHeight)
            bY = bY - bpHeight - 15

            for j, ic in ipairs(bIcons) do
                local btn = GetIconBtn(iconCounter)
                iconCounter = iconCounter + 1
                btn.iconData = ic
                btn.tex:SetTexture(ic.icon)
                btn:SetParent(bp)
                local col = (j-1) % 20
                local row = math.floor((j-1) / 20)
                btn:SetPoint("TOPLEFT", bp, "TOPLEFT", 15 + col*40, -45 - row*40)
                btn:Show()
            end
            bp:Show()
        end
        rightContent:SetHeight(math.abs(bY))

        -- 2. Render Unassigned Pool (Left Side)
        local uIcons = {}
        for _, ic in ipairs(icons) do if ic.barIndex == 0 then table.insert(uIcons, ic) end end
        
        for j, ic in ipairs(uIcons) do
            local btn = GetIconBtn(iconCounter)
            iconCounter = iconCounter + 1
            btn.iconData = ic
            btn.tex:SetTexture(ic.icon)
            btn:SetParent(unassignedContent)
            local col = (j-1) % 8
            local row = math.floor((j-1) / 8)
            btn:SetPoint("TOPLEFT", unassignedContent, "TOPLEFT", 5 + col*42, -5 - row*42)
            btn:Show()
        end
        
        local uRowCount = math.ceil(math.max(1, #uIcons) / 8)
        unassignedContent:SetHeight(uRowCount * 42 + 20)
    end

    API._SubBarsPopulateUI = PopulateSubBarsUI
    tabs[1].onActivate = PopulateSubBarsUI

    -- ── Add Icon popup ────────────────────────────────────────────────────────
    -- Built once, reused for every bar's "+ Add Icon" button.
    local addIconPopup = nil

    local function BuildAddIconPopup()
        if addIconPopup then return addIconPopup end

        local p = CreateFrame("Frame", "RogUIAddIconPopup", UIParent, "BackdropTemplate")
        p:SetSize(300, 200)
        p:SetFrameStrata("DIALOG")
        p:SetFrameLevel(300)
        p:SetBackdrop({ bgFile="Interface\\Buttons\\WHITE8x8",
                        edgeFile="Interface\\Buttons\\WHITE8x8", edgeSize=1 })
        p:SetBackdropColor(0.07, 0.07, 0.13, 0.97)
        p:SetBackdropBorderColor(0.4, 0.4, 0.7, 1)
        p:SetMovable(true); p:EnableMouse(true)
        p:RegisterForDrag("LeftButton")
        p:SetScript("OnDragStart", p.StartMoving)
        p:SetScript("OnDragStop",  p.StopMovingOrSizing)
        p:Hide()

        local title = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        title:SetPoint("TOPLEFT", p, "TOPLEFT", 10, -10)
        title:SetTextColor(1, 0.85, 0.2, 1)
        title:SetText("Add Icon to Bar")
        p.title = title

        local close = CreateFrame("Button", nil, p, "UIPanelCloseButton")
        close:SetSize(22, 22); close:SetPoint("TOPRIGHT", p, "TOPRIGHT", -2, -2)
        close:SetScript("OnClick", function() p:Hide() end)

        -- Type selector
        local typeLbl = p:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        typeLbl:SetPoint("TOPLEFT", p, "TOPLEFT", 10, -36)
        typeLbl:SetText("Type:")

        local typeButtons = {}
        local selectedType = "spell"
        local typeOptions = {
            { key="spell", label="Spell / Ability" },
            { key="aura",  label="Aura / Buff"     },
            { key="item",  label="Usable Item"     },
        }

        local function SelectType(key)
            selectedType = key
            for _, tb in ipairs(typeButtons) do
                if tb.key == key then
                    tb:SetBackdropColor(0.2, 0.4, 0.8, 0.9)
                else
                    tb:SetBackdropColor(0.12, 0.12, 0.18, 0.9)
                end
            end
            -- Update hint text
            local hints = {
                spell = "Spell ID — tracks cooldown & charges",
                aura  = "Aura / buff spell ID — tracks stacks & duration",
                item  = "Item ID — tracks use cooldown",
            }
            p.hintLbl:SetText("|cFF888888" .. (hints[key] or "") .. "|r")
        end

        local prevTypeBtn = nil
        for i, opt in ipairs(typeOptions) do
            local tb = CreateFrame("Button", nil, p, "BackdropTemplate")
            tb:SetSize(86, 22)
            tb:SetBackdrop({ bgFile="Interface\\Buttons\\WHITE8x8",
                             edgeFile="Interface\\Buttons\\WHITE8x8", edgeSize=1 })
            tb:SetBackdropBorderColor(0.35, 0.35, 0.55, 1)
            tb:SetBackdropColor(0.12, 0.12, 0.18, 0.9)
            tb.key = opt.key
            if prevTypeBtn then
                tb:SetPoint("LEFT", prevTypeBtn, "RIGHT", 4, 0)
            else
                tb:SetPoint("LEFT", typeLbl, "RIGHT", 8, 0)
            end
            prevTypeBtn = tb
            local lbl = tb:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            lbl:SetAllPoints(tb); lbl:SetJustifyH("CENTER"); lbl:SetText(opt.label)
            tb:SetScript("OnClick", function() SelectType(opt.key) end)
            table.insert(typeButtons, tb)
        end

        -- Hint text
        local hintLbl = p:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        hintLbl:SetPoint("TOPLEFT", p, "TOPLEFT", 10, -66)
        hintLbl:SetPoint("TOPRIGHT", p, "TOPRIGHT", -10, -66)
        hintLbl:SetJustifyH("LEFT")
        p.hintLbl = hintLbl

        -- ID input
        local idLbl = p:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        idLbl:SetPoint("TOPLEFT", p, "TOPLEFT", 10, -86)
        idLbl:SetText("ID:")

        local idBox = CreateFrame("EditBox", nil, p, "InputBoxTemplate")
        idBox:SetSize(100, 20)
        idBox:SetPoint("LEFT", idLbl, "RIGHT", 8, 0)
        idBox:SetAutoFocus(false); idBox:SetNumeric(true); idBox:SetMaxLetters(10)
        p.idBox = idBox

        -- Preview: icon + name shown after valid ID entered
        local previewIcon = p:CreateTexture(nil, "ARTWORK")
        previewIcon:SetSize(32, 32)
        previewIcon:SetPoint("TOPLEFT", p, "TOPLEFT", 10, -112)
        previewIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        previewIcon:Hide()
        p.previewIcon = previewIcon

        local previewName = p:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        previewName:SetPoint("LEFT", previewIcon, "RIGHT", 6, 0)
        previewName:SetPoint("RIGHT", p, "RIGHT", -10, 0)
        previewName:SetJustifyH("LEFT")
        previewName:SetTextColor(1, 1, 0.6, 1)
        previewName:Hide()
        p.previewName = previewName

        local errorLbl = p:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        errorLbl:SetPoint("TOPLEFT", p, "TOPLEFT", 10, -116)
        errorLbl:SetTextColor(1, 0.3, 0.3, 1)
        errorLbl:Hide()
        p.errorLbl = errorLbl

        local function ValidateAndPreview()
            local id = tonumber(idBox:GetText())
            previewIcon:Hide(); previewName:Hide(); errorLbl:Hide()
            if not id or id <= 0 then return end

            if selectedType == "item" then
                local name, _, _, _, _, _, _, _, _, tex = C_Item.GetItemInfo(id)
                if name and tex then
                    previewIcon:SetTexture(tex); previewIcon:Show()
                    previewName:SetText(name); previewName:Show()
                else
                    errorLbl:SetText("Item ID not found or not yet cached"); errorLbl:Show()
                end
            else
                local tex = C_Spell.GetSpellTexture(id)
                local name = C_Spell.GetSpellName(id)
                if name and tex then
                    previewIcon:SetTexture(tex); previewIcon:Show()
                    previewName:SetText(name); previewName:Show()
                else
                    errorLbl:SetText("Spell ID not found"); errorLbl:Show()
                end
            end
        end

        idBox:SetScript("OnTextChanged", ValidateAndPreview)
        idBox:SetScript("OnEnterPressed", function(self)
            self:ClearFocus(); ValidateAndPreview()
        end)

        -- Add button
        local addBtn = CreateFrame("Button", nil, p, "GameMenuButtonTemplate")
        addBtn:SetSize(100, 24)
        addBtn:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", -10, 10)
        addBtn:SetText("Add to Bar")
        addBtn:SetScript("OnClick", function()
            local id = tonumber(idBox:GetText())
            if not id or id <= 0 then
                errorLbl:SetText("Enter a valid ID first"); errorLbl:Show()
                return
            end
            -- Quick validation
            local valid = false
            if selectedType == "item" then
                valid = C_Item.GetItemInfo(id) ~= nil
            else
                valid = C_Spell.GetSpellName(id) ~= nil
            end
            if not valid then
                errorLbl:SetText("ID not recognised — check and retry"); errorLbl:Show()
                return
            end
            if API.SubBars_AddCustomIcon then
                API.SubBars_AddCustomIcon(id, selectedType, p._targetBar)
            end
            -- Refresh the UI list after a short delay so Reconcile can run
            C_Timer.After(0.2, function()
                if API._SubBarsPopulateUI then API._SubBarsPopulateUI() end
            end)
            idBox:SetText("")
            previewIcon:Hide(); previewName:Hide(); errorLbl:Hide()
            p:Hide()
        end)

        local cancelBtn = CreateFrame("Button", nil, p, "GameMenuButtonTemplate")
        cancelBtn:SetSize(70, 24)
        cancelBtn:SetPoint("RIGHT", addBtn, "LEFT", -6, 0)
        cancelBtn:SetText("Cancel")
        cancelBtn:SetScript("OnClick", function() p:Hide() end)

        -- Initialise type selection visuals
        SelectType("spell")

        addIconPopup = p
        return p
    end

    API._SubBars_OpenAddIconPopup = function(barIndex, anchorBtn)
        local p = BuildAddIconPopup()
        p._targetBar = barIndex
        p.title:SetText("Add Icon → Bar " .. tostring(barIndex))
        p.idBox:SetText("")
        p.previewIcon:Hide(); p.previewName:Hide(); p.errorLbl:Hide()
        p:ClearAllPoints()
        if anchorBtn then
            p:SetPoint("TOPRIGHT", anchorBtn, "BOTTOMRIGHT", 0, -4)
        else
            p:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
        end
        p:Show()
        p.idBox:SetFocus()
    end
end -- TAB 1

-- ════════════════════════════════════════════════════════════
-- ICON CONFIG MODAL
-- Right-click any CDM bar icon to open.
-- Settings stored in RogUIDB.iconSettings[spellID].
-- ════════════════════════════════════════════════════════════
do
    local popup = nil
    local currentSpellID = nil
    local currentCdInfo  = nil

    local function GetIconDB(spellID)
        if not RogUIDB then return {} end
        RogUIDB.iconSettings = RogUIDB.iconSettings or {}
        RogUIDB.iconSettings[spellID] = RogUIDB.iconSettings[spellID] or {}
        return RogUIDB.iconSettings[spellID]
    end

    local function BuildPopup()
        if popup then return popup end

        local p = CreateFrame("Frame", "RogUIIconConfigModal", UIParent, "BackdropTemplate")
        p:SetSize(320, 310)
        p:SetFrameStrata("DIALOG")
        p:SetFrameLevel(300)
        p:SetBackdrop({
            bgFile   = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1,
        })
        p:SetBackdropColor(0.06, 0.06, 0.12, 0.97)
        p:SetBackdropBorderColor(0.4, 0.5, 0.8, 1)
        p:SetMovable(true); p:EnableMouse(true)
        p:RegisterForDrag("LeftButton")
        p:SetScript("OnDragStart", p.StartMoving)
        p:SetScript("OnDragStop",  p.StopMovingOrSizing)
        p:Hide()

        -- Close button
        local closeBtn = CreateFrame("Button", nil, p, "UIPanelCloseButton")
        closeBtn:SetSize(22, 22); closeBtn:SetPoint("TOPRIGHT", p, "TOPRIGHT", -2, -2)
        closeBtn:SetScript("OnClick", function() p:Hide() end)

        -- Icon display
        local iconBg = p:CreateTexture(nil, "BACKGROUND")
        iconBg:SetSize(64, 64); iconBg:SetPoint("TOPLEFT", 12, -12)
        iconBg:SetColorTexture(0, 0, 0, 0.6); p.iconBg = iconBg

        local iconTex = p:CreateTexture(nil, "ARTWORK")
        iconTex:SetSize(60, 60); iconTex:SetPoint("CENTER", iconBg, "CENTER", 0, 0)
        iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92); p.iconTex = iconTex

        -- Spell name + ID
        local nameLabel = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        nameLabel:SetPoint("TOPLEFT", iconBg, "TOPRIGHT", 10, -4)
        nameLabel:SetPoint("TOPRIGHT", p, "TOPRIGHT", -30, -4)
        nameLabel:SetJustifyH("LEFT"); nameLabel:SetTextColor(1, 0.85, 0.2, 1)
        p.nameLabel = nameLabel

        local idLabel = p:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        idLabel:SetPoint("TOPLEFT", iconBg, "TOPRIGHT", 10, -22)
        idLabel:SetTextColor(0.6, 0.6, 0.6, 1); p.idLabel = idLabel

        local typeLabel = p:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        typeLabel:SetPoint("TOPLEFT", iconBg, "TOPRIGHT", 10, -38)
        typeLabel:SetTextColor(0.5, 0.8, 1, 1); p.typeLabel = typeLabel

        local function MakeCheckRow(yOff, labelText)
            local cb = CreateFrame("CheckButton", nil, p, "UICheckButtonTemplate")
            cb:SetSize(22, 22); cb:SetPoint("TOPLEFT", p, "TOPLEFT", 12, yOff)
            local lbl = p:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            lbl:SetPoint("LEFT", cb, "RIGHT", 4, 0); lbl:SetText(labelText)
            return cb, lbl
        end

        -- Row: Glow on trigger
        local glowCb, glowLbl = MakeCheckRow(-92, "Glow on trigger")
        p.glowCb = glowCb

        -- Row: Sound on trigger + dropdown
        local soundCb, soundLbl = MakeCheckRow(-118, "Sound on trigger")
        p.soundCb = soundCb

        local soundDropdown = API.CreateSoundSelectorButton(p, "RogUIIconCfg_SoundDD")
        soundDropdown:SetPoint("LEFT", soundLbl, "RIGHT", 8, 0)
        soundDropdown:SetWidth(130)
        p.soundDropdown = soundDropdown

        -- Row: Show always or only when triggered
        local triggerCb, triggerLbl = MakeCheckRow(-148, "Show only when triggered (hide otherwise)")
        p.triggerCb = triggerCb

        -- Row: Show Keybind
        local keybindCb, keybindLbl = MakeCheckRow(-174, "Show Keybind")
        p.keybindCb = keybindCb

        -- Row: Custom Keybind text
        local customKbCb, customKbLbl = MakeCheckRow(-200, "Custom Keybind text")
        p.customKbCb = customKbCb

        local customKbBox = CreateFrame("EditBox", nil, p, "InputBoxTemplate")
        customKbBox:SetSize(80, 20)
        customKbBox:SetPoint("LEFT", customKbLbl, "RIGHT", 8, 0)
        customKbBox:SetAutoFocus(false); customKbBox:SetMaxLetters(16)
        p.customKbBox = customKbBox

        -- Separator
        local sep = p:CreateTexture(nil, "BACKGROUND")
        sep:SetColorTexture(0.3, 0.3, 0.5, 0.5); sep:SetHeight(1)
        sep:SetPoint("TOPLEFT", p, "TOPLEFT", 10, -230)
        sep:SetPoint("TOPRIGHT", p, "TOPRIGHT", -10, -230)

        -- Save button
        local saveBtn = CreateFrame("Button", nil, p, "GameMenuButtonTemplate")
        saveBtn:SetSize(100, 26); saveBtn:SetPoint("BOTTOMLEFT", p, "BOTTOMLEFT", 12, 12)
        saveBtn:SetText("Save")
        saveBtn:SetScript("OnClick", function()
            if not currentSpellID then p:Hide(); return end
            local db = GetIconDB(currentSpellID)
            db.glowOnTrigger      = p.glowCb:GetChecked()
            db.soundOnTrigger     = p.soundCb:GetChecked()
            db.sound              = p.soundDropdown.selectedSound
            db.soundIsID          = p.soundDropdown.selectedSoundIsID
            db.showOnlyTriggered  = p.triggerCb:GetChecked()
            db.showKeybind        = p.keybindCb:GetChecked()
            db.customKeybind      = p.customKbCb:GetChecked()
            db.customKeybindText  = p.customKbBox:GetText()
            if API.SaveSpecProfile then API.SaveSpecProfile() end
            if API.CKBOnSettingChanged then API.CKBOnSettingChanged() end
            p:Hide()
        end)

        -- Cancel button
        local cancelBtn = CreateFrame("Button", nil, p, "GameMenuButtonTemplate")
        cancelBtn:SetSize(80, 26); cancelBtn:SetPoint("LEFT", saveBtn, "RIGHT", 8, 0)
        cancelBtn:SetText("Cancel")
        cancelBtn:SetScript("OnClick", function() p:Hide() end)

        popup = p
        return p
    end

    function API.OpenIconConfigModal(spellID, name, icon, cdInfo)
        local p = BuildPopup()
        currentSpellID = spellID
        currentCdInfo  = cdInfo

        -- Populate header
        p.iconTex:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
        p.nameLabel:SetText(name or "Unknown")
        p.idLabel:SetText("Spell ID: " .. tostring(spellID))
        local typeStr = "cooldown"
        if cdInfo and cdInfo.auraSpellID and cdInfo.auraSpellID > 0 then typeStr = "aura" end
        p.typeLabel:SetText(typeStr)

        -- Load saved settings
        local db = GetIconDB(spellID)
        p.glowCb:SetChecked(db.glowOnTrigger == true)
        p.soundCb:SetChecked(db.soundOnTrigger == true)
        if p.soundDropdown.SetSelectedSound then
            p.soundDropdown:SetSelectedSound(db.sound, db.soundIsID)
        end
        p.triggerCb:SetChecked(db.showOnlyTriggered == true)
        p.keybindCb:SetChecked(db.showKeybind ~= false)
        p.customKbCb:SetChecked(db.customKeybind == true)
        p.customKbBox:SetText(db.customKeybindText or "")

        -- Position near cursor
        p:ClearAllPoints()
        local cx, cy = GetCursorPosition()
        local scale = UIParent:GetEffectiveScale()
        cx, cy = cx / scale, cy / scale
        p:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", cx + 8, cy + 8)
        -- Nudge on-screen
        C_Timer.After(0, function()
            if not p:IsShown() then return end
            local right = p:GetRight() or 0
            local top   = p:GetTop()  or 0
            local sw    = GetScreenWidth()
            local sh    = GetScreenHeight()
            if right > sw then p:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMLEFT", cx - 8, cy + 8) end
            if top   > sh then p:SetPoint("TOPLEFT",     UIParent, "BOTTOMLEFT", cx + 8, cy - 8) end
        end)
        p:Show()
    end

    -- Expose getter so SubBars and CKB can read per-icon settings
    function API.GetIconSettings(spellID)
        if not spellID or not RogUIDB then return {} end
        RogUIDB.iconSettings = RogUIDB.iconSettings or {}
        return RogUIDB.iconSettings[spellID] or {}
    end
end

-- ════════════════════════════════════════════════════════════
-- TAB 2: BUFF ALERTS
-- Ported from BuffAlertsUI.lua — adapted to sub-tab frame
-- ════════════════════════════════════════════════════════════

do
    local buffFrame = tabs[2].frame

    -- Scroll frame so the aura list can grow
    local buffScroll = CreateFrame("ScrollFrame", nil, buffFrame, "UIPanelScrollFrameTemplate")
    buffScroll:SetSize(1096, 712)  -- Adjusted for 70% panel
    buffScroll:SetPoint("TOPLEFT", buffFrame, "TOPLEFT", 4, -4)

    local baContent = CreateFrame("Frame", "CM_BAContent", buffScroll)
    baContent:SetSize(1076, 200)
    buffScroll:SetScrollChild(baContent)

    -- References to shared lists (re-fetched on each activate)
    local trackedBuffs     = API.trackedBuffs or {}
    local trackedDebuffs   = API.trackedDebuffs or {}
    local trackedExternals = API.trackedExternals or {}

    -- Per-type entry pool
    local auraEntryPool = { buff={}, debuff={}, external={} }

    local function CreateAuraEntry(parentFrame, slotIndex, auraType)
        local ef = CreateFrame("Frame", "CM_BAEntry_"..auraType..slotIndex, parentFrame)
        ef:SetSize(1056, 115); ef:Hide()

        local sep = ef:CreateTexture(nil,"BACKGROUND")
        sep:SetColorTexture(0.3,0.3,0.3,0.4)
        sep:SetPoint("TOPLEFT",0,0); sep:SetSize(1056,1)

        local enableCb = CreateFrame("CheckButton","CM_BAEnable_"..auraType..slotIndex,ef,"UICheckButtonTemplate")
        enableCb:SetSize(20,20); enableCb:SetPoint("TOPLEFT",0,-2)

        local presetLabel = ef:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
        presetLabel:SetPoint("TOPLEFT",22,-2); presetLabel:SetText("Spell:")

        local idLabel = ef:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
        idLabel:SetPoint("TOPLEFT",222,-2); idLabel:SetText("ID:")

        local idInput = CreateFrame("EditBox","CM_BAIDInput_"..auraType..slotIndex,ef,"InputBoxTemplate")
        idInput:SetSize(60,20); idInput:SetPoint("TOPLEFT",240,-4)
        idInput:SetAutoFocus(false); idInput:SetMaxLetters(50)

        local spellDropdown = API.CreateSpellSelectorButton(ef,"CM_BASpellDD_"..auraType..slotIndex,auraType,idInput)
        spellDropdown:SetPoint("TOPLEFT",62,-4); spellDropdown.auraType = auraType

        local soundLabel = ef:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
        soundLabel:SetPoint("TOPLEFT",0,-28); soundLabel:SetText("Sound:")

        local soundDropdown = API.CreateSoundSelectorButton(ef,"CM_BASoundDD_"..auraType..slotIndex)
        soundDropdown:SetPoint("TOPLEFT",40,-28); soundDropdown.auraType = auraType

        local texLabel = ef:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
        texLabel:SetPoint("TOPLEFT",0,-54); texLabel:SetText("Alert Img:")

        local texInput = CreateFrame("EditBox","CM_BATexInput_"..auraType..slotIndex,ef)
        texInput:Hide(); texInput:SetAutoFocus(false); texInput:SetMaxLetters(200)

        local imgBtn = API.CreateImageSelectorButton(ef,"CM_BAImgBtn_"..auraType..slotIndex,texInput,
            function() return tonumber(idInput:GetText()) end)
        imgBtn:SetPoint("TOPLEFT",55,-56)

        local previewBtn = CreateFrame("Button",nil,ef,"GameMenuButtonTemplate")
        previewBtn:SetSize(50,18); previewBtn:SetPoint("TOPLEFT",200,-56); previewBtn:SetText("Preview")
        previewBtn:SetScript("OnClick",function()
            local img = imgBtn.selectedImage
            if img and img ~= "" then API.ShowAlertOverlay({alertTexture=img,alertSize=80,alertDuration=2},"preview") end
        end)

        local xLabel = ef:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
        xLabel:SetPoint("TOPLEFT",284,-54); xLabel:SetText("X:")
        local xInput = CreateFrame("EditBox","CM_BATexX_"..auraType..slotIndex,ef,"InputBoxTemplate")
        xInput:SetSize(38,18); xInput:SetPoint("TOPLEFT",296,-56); xInput:SetAutoFocus(false); xInput:SetMaxLetters(6)

        local yLabel = ef:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
        yLabel:SetPoint("TOPLEFT",338,-54); yLabel:SetText("Y:")
        local yInput = CreateFrame("EditBox","CM_BATexY_"..auraType..slotIndex,ef,"InputBoxTemplate")
        yInput:SetSize(38,18); yInput:SetPoint("TOPLEFT",350,-56); yInput:SetAutoFocus(false); yInput:SetMaxLetters(6)

        local szLabel = ef:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
        szLabel:SetPoint("TOPLEFT",392,-54); szLabel:SetText("H:")
        local szInput = CreateFrame("EditBox","CM_BATexSize_"..auraType..slotIndex,ef,"InputBoxTemplate")
        szInput:SetSize(30,18); szInput:SetPoint("TOPLEFT",405,-56); szInput:SetAutoFocus(false); szInput:SetMaxLetters(4)

        local barWLabel = ef:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
        barWLabel:SetPoint("TOPLEFT",438,-54); barWLabel:SetText("W:")
        local barWInput = CreateFrame("EditBox","CM_BABarWidth_"..auraType..slotIndex,ef,"InputBoxTemplate")
        barWInput:SetSize(38,18); barWInput:SetPoint("TOPLEFT",450,-56); barWInput:SetAutoFocus(false); barWInput:SetMaxLetters(5)

        local durLabel = ef:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
        durLabel:SetPoint("TOPLEFT",492,-54); durLabel:SetText("Dur:")
        local durInput = CreateFrame("EditBox","CM_BATexDur_"..auraType..slotIndex,ef,"InputBoxTemplate")
        durInput:SetSize(35,18); durInput:SetPoint("TOPLEFT",510,-56); durInput:SetAutoFocus(false); durInput:SetMaxLetters(4)
        local durHint = ef:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
        durHint:SetPoint("TOPLEFT",549,-54); durHint:SetTextColor(0.5,0.5,0.5,1); durHint:SetText("s (0=∞)")

        local glowCheck = CreateFrame("CheckButton","CM_BAGlow_"..auraType..slotIndex,ef,"UICheckButtonTemplate")
        glowCheck:SetSize(20,20); glowCheck:SetPoint("TOPLEFT",0,-78)
        local glowLabel = ef:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
        glowLabel:SetPoint("TOPLEFT",22,-78); glowLabel:SetText("Glow on icon")

        local hideNativeCheck = CreateFrame("CheckButton","CM_BAHideNative_"..auraType..slotIndex,ef,"UICheckButtonTemplate")
        hideNativeCheck:SetSize(20,20); hideNativeCheck:SetPoint("TOPLEFT",140,-78)
        local hideNativeLabel = ef:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
        hideNativeLabel:SetPoint("TOPLEFT",162,-78); hideNativeLabel:SetText("Hide native icon")

        local modeLabel = ef:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
        modeLabel:SetPoint("TOPLEFT",290,-78); modeLabel:SetText("Mode:")

        local iconModeBtn = CreateFrame("CheckButton","CM_BAModeIcon_"..auraType..slotIndex,ef,"UIRadioButtonTemplate")
        iconModeBtn:SetSize(20,20); iconModeBtn:SetPoint("TOPLEFT",328,-78)
        local iconModeLbl = ef:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
        iconModeLbl:SetPoint("LEFT",iconModeBtn,"RIGHT",2,0); iconModeLbl:SetText("Icon")

        local barModeBtn = CreateFrame("CheckButton","CM_BAModeBar_"..auraType..slotIndex,ef,"UIRadioButtonTemplate")
        barModeBtn:SetSize(20,20); barModeBtn:SetPoint("TOPLEFT",390,-78)
        local barModeLbl = ef:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
        barModeLbl:SetPoint("LEFT",barModeBtn,"RIGHT",2,0); barModeLbl:SetText("Bar")

        iconModeBtn:SetScript("OnClick",function() iconModeBtn:SetChecked(true); barModeBtn:SetChecked(false) end)
        barModeBtn:SetScript("OnClick",function() barModeBtn:SetChecked(true); iconModeBtn:SetChecked(false) end)
        iconModeBtn:SetChecked(true)

        local tagText = ef:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
        tagText:SetPoint("TOPRIGHT",-10,-5)

        local testBtn = CreateFrame("Button",nil,ef,"GameMenuButtonTemplate")
        testBtn:SetSize(50,20); testBtn:SetPoint("TOPRIGHT",-58,-4); testBtn:SetText("Test")
        testBtn:SetScript("OnClick",function()
            if soundDropdown.selectedSound then
                API.PlayCustomSound(soundDropdown.selectedSound, soundDropdown.selectedSoundIsID)
            end
        end)

        local removeBtn = CreateFrame("Button",nil,ef,"GameMenuButtonTemplate")
        removeBtn:SetSize(50,20); removeBtn:SetPoint("TOPRIGHT",-4,-4); removeBtn:SetText("Remove")
        removeBtn:SetScript("OnClick",function(self)
            if auraType=="buff"     then table.remove(trackedBuffs,    self.dataIndex)
            elseif auraType=="debuff" then table.remove(trackedDebuffs,  self.dataIndex)
            else                        table.remove(trackedExternals, self.dataIndex) end
            API.RefreshAuraListUI()
        end)

        return {
            frame=ef, enableCheckbox=enableCb, spellDropdown=spellDropdown, idInput=idInput,
            soundDropdown=soundDropdown, texInput=texInput, imgBtn=imgBtn,
            xInput=xInput, yInput=yInput, szInput=szInput, barWInput=barWInput, durInput=durInput,
            tagText=tagText, removeBtn=removeBtn, glowCheck=glowCheck, hideNativeCheck=hideNativeCheck,
            iconModeBtn=iconModeBtn, barModeBtn=barModeBtn,
        }
    end

    local function GetPooledEntry(auraType, slotIndex)
        local pool = auraEntryPool[auraType]
        if not pool[slotIndex] then pool[slotIndex] = CreateAuraEntry(baContent, slotIndex, auraType) end
        return pool[slotIndex]
    end

    local function RefreshAuraListUI()
        trackedBuffs     = API.trackedBuffs     or trackedBuffs     or {}
        trackedDebuffs   = API.trackedDebuffs   or trackedDebuffs   or {}
        trackedExternals = API.trackedExternals or trackedExternals or {}

        local rowCount = 0
        local function DrawSection(list, typeLabel, typeColor)
            if not list then return end
            local pool = auraEntryPool[typeLabel:lower()]
            for dataIndex, aura in ipairs(list) do
                rowCount = rowCount + 1
                local entry = GetPooledEntry(typeLabel:lower(), dataIndex)
                entry.frame:ClearAllPoints()
                entry.frame:SetPoint("TOPLEFT", baContent, "TOPLEFT", 0, -(rowCount-1)*120)
                entry.removeBtn.dataIndex = dataIndex
                entry.tagText:SetText(typeColor..typeLabel.."|r")
                entry.idInput:SetText(tostring(aura.spellId or 0))
                entry.spellDropdown.auraType   = typeLabel:lower()
                entry.spellDropdown.idInputRef = entry.idInput
                entry.soundDropdown:SetSelectedSound(aura.sound, aura.soundIsID)
                entry.enableCheckbox:SetChecked(aura.enabled ~= false)
                entry.imgBtn:SetSelectedImage(aura.alertTexture or nil)
                entry.texInput:SetText(aura.alertTexture and tostring(aura.alertTexture) or "")
                entry.xInput:SetText(aura.alertX   and tostring(aura.alertX)   or "")
                entry.yInput:SetText(aura.alertY   and tostring(aura.alertY)   or "")
                entry.szInput:SetText(aura.alertSize and tostring(aura.alertSize) or "")
                local barWIn = _G["CM_BABarWidth_"..typeLabel:lower()..dataIndex]
                if barWIn then barWIn:SetText(aura.alertBarWidth and tostring(aura.alertBarWidth) or "") end
                entry.durInput:SetText(tostring(aura.alertDuration or 0))
                if entry.glowCheck      then entry.glowCheck:SetChecked(aura.glowEnabled    == true) end
                if entry.hideNativeCheck then entry.hideNativeCheck:SetChecked(aura.hideNativeIcon == true) end
                local isBar = (aura.alertMode == "bar")
                entry.iconModeBtn:SetChecked(not isBar); entry.barModeBtn:SetChecked(isBar)
                local sname = (aura.spellId and aura.spellId>0)
                    and (C_Spell.GetSpellInfo(aura.spellId) and C_Spell.GetSpellInfo(aura.spellId).name)
                    or "Select Spell"
                entry.spellDropdown:SetText(aura.name or sname)
                entry.frame:Show()
            end
            for slotIndex = #list+1, #pool do pool[slotIndex].frame:Hide() end
        end

        DrawSection(trackedBuffs,     "BUFF",     "|cFF00FF00")
        --[[ DEBUFFS/EXTERNALS DISABLED — tracking not yet implemented
        DrawSection(trackedDebuffs,   "DEBUFF",   "|cFFFF0000")
        DrawSection(trackedExternals, "EXTERNAL", "|cFF00CCFF")
        --]]
        baContent:SetHeight(math.max(200, rowCount*120 + 120))
    end
    API.RefreshAuraListUI = RefreshAuraListUI

    -- Harvest (UI → data)
    local function HarvestBuffAlertUI()
        local DEFAULT_SOUND_ID = 12743
        local function harvestList(list, auraType)
            for index, aura in ipairs(list) do
                local t = auraType
                local input = _G["CM_BAIDInput_"..t..index]
                if input then
                    if t == "external" then
                        local raw = input:GetText()
                        if raw:find(",") then
                            aura.spellId=0; aura.spellIds={}
                            for idStr in raw:gmatch("[^,]+") do
                                local n=tonumber(idStr:match("^%s*(.-)%s*$"))
                                if n then table.insert(aura.spellIds,n) end
                            end
                        else aura.spellId=tonumber(raw) or 0; aura.spellIds=nil end
                    else aura.spellId=tonumber(input:GetText()) or 0 end
                end
                local enableCb=_G["CM_BAEnable_"..t..index]; if enableCb then aura.enabled=enableCb:GetChecked() end
                local spellDropRef=_G["CM_BASpellDD_BUFF"..index]
                if spellDropRef and spellDropRef.selectedSpellIsLust ~= nil then
                    aura.isLustTracker = spellDropRef.selectedSpellIsLust
                end
                local imgBtnRef=_G["CM_BAImgBtn_"..t..index]
                local rawImg=imgBtnRef and imgBtnRef.selectedImage
                aura.alertTexture=(rawImg and rawImg~="" and tostring(rawImg)) or nil
                local xIn=_G["CM_BATexX_"..t..index];    if xIn  then aura.alertX=tonumber(xIn:GetText()) or 0 end
                local yIn=_G["CM_BATexY_"..t..index];    if yIn  then aura.alertY=tonumber(yIn:GetText()) or 0 end
                local szIn=_G["CM_BATexSize_"..t..index];  if szIn then aura.alertSize=tonumber(szIn:GetText()) or 64 end
                local barWIn=_G["CM_BABarWidth_"..t..index]; if barWIn then aura.alertBarWidth=tonumber(barWIn:GetText()) or 200 end
                local durIn=_G["CM_BATexDur_"..t..index]; if durIn then aura.alertDuration=tonumber(durIn:GetText()) or 0 end
                local glowCb=_G["CM_BAGlow_"..t..index];       if glowCb  then aura.glowEnabled=glowCb:GetChecked() end
                local hideCb=_G["CM_BAHideNative_"..t..index]; if hideCb  then aura.hideNativeIcon=hideCb:GetChecked() end
                local barModeBtn=_G["CM_BAModeBar_"..t..index]
                if barModeBtn then aura.alertMode = barModeBtn:GetChecked() and "bar" or "icon" end
                local sd=_G["CM_BASoundDD_"..t..index]
                if sd then
                    aura.sound    = sd.selectedSound or DEFAULT_SOUND_ID
                    aura.soundIsID= (sd.selectedSound~=nil) and sd.selectedSoundIsID or true
                end
            end
        end
        harvestList(trackedBuffs, "buff")
        --[[ DEBUFFS/EXTERNALS DISABLED
        harvestList(trackedDebuffs,   "debuff")
        harvestList(trackedExternals, "external")
        --]]
    end
    API.HarvestBuffAlertUIValues = HarvestBuffAlertUI

    -- Hook core save button
    local saveBtn = _G["RogUISaveBtn"]
    if saveBtn then saveBtn:HookScript("OnClick", HarvestBuffAlertUI) end

    -- ── Feature enable checkbox ───────────────────────────────
    local baEnableCheck = CreateFrame("CheckButton", "CM_BAGlobalEnable", buffFrame, "UICheckButtonTemplate")
    baEnableCheck:SetSize(22,22); baEnableCheck:SetPoint("BOTTOMLEFT", buffFrame, "BOTTOMLEFT", 8, 8)
    local baEnableLbl = _G["CM_BAGlobalEnableText"]
    if baEnableLbl then baEnableLbl:SetText("Buff/Debuff Alerts Enabled") end
    baEnableCheck:SetChecked(true)
    baEnableCheck:SetScript("OnClick", function(self)
        if API.buffAlertEnabledCheckbox then
            API.buffAlertEnabledCheckbox:SetChecked(self:GetChecked())
        end
    end)
    API.buffAlertEnabledCheckbox = baEnableCheck

    -- ── Add Buff button ───────────────────────────────────────
    local addBuffBtn = CreateFrame("Button","CM_BAAddBuffBtn", masterFrame, "GameMenuButtonTemplate")
    addBuffBtn:SetSize(110,25); addBuffBtn:SetText("+ Add Buff"); addBuffBtn:Hide()
    addBuffBtn:SetPoint("BOTTOMLEFT", masterFrame, "BOTTOMLEFT", 20, 8)
    addBuffBtn:SetScript("OnClick",function()
        trackedBuffs = API.trackedBuffs
        table.insert(trackedBuffs,{spellId=0,sound=nil})
        RefreshAuraListUI()
    end)
    -- Lock: only show when this tab's content is visible
    hooksecurefunc(addBuffBtn,"Show",function(self)
        if baContent and not baContent:IsVisible() then self:Hide() end
    end)

    -- ── Boss Warning Sound section ────────────────────────────
    local bwSection = buffFrame:CreateFontString(nil,"ARTWORK","GameFontNormal")
    bwSection:SetPoint("BOTTOMLEFT", buffFrame, "BOTTOMLEFT", 8, 36)
    bwSection:SetText("|cFFFF8844Boss Warning Sound|r  |cFFAAAAAA(plays when Blizzard's boss popup appears)|r")

    local bwSoundDropdown = API.CreateSoundSelectorButton(buffFrame, "CM_BossWarnSoundBtn")
    bwSoundDropdown:SetPoint("BOTTOMLEFT", buffFrame, "BOTTOMLEFT", 8, 12)

    local bwTestBtn = CreateFrame("Button",nil,buffFrame,"GameMenuButtonTemplate")
    bwTestBtn:SetSize(60,22); bwTestBtn:SetPoint("LEFT",bwSoundDropdown,"RIGHT",8,0); bwTestBtn:SetText("Test")
    bwTestBtn:SetScript("OnClick",function()
        local db = RogUIDB
        if db and db.bossWarnSound and db.bossWarnSound.sound then
            API.PlayCustomSound(db.bossWarnSound.sound, db.bossWarnSound.soundIsID)
        end
    end)

    local function RefreshBossWarnUI()
        local db = RogUIDB
        if db and db.bossWarnSound then
            bwSoundDropdown:SetSelectedSound(db.bossWarnSound.sound, db.bossWarnSound.soundIsID)
        end
        bwSoundDropdown.onSoundSelected = function(sound, isID)
            RogUIDB.bossWarnSound = RogUIDB.bossWarnSound or {}
            RogUIDB.bossWarnSound.sound     = sound
            RogUIDB.bossWarnSound.soundIsID = isID
        end
    end

    tabs[2].onActivate = function()
        trackedBuffs = API.trackedBuffs
        RefreshAuraListUI()
        RefreshBossWarnUI()
        addBuffBtn:Show()
    end
    tabs[2].onDeactivate = function()
        addBuffBtn:Hide()
    end
end

-- ════════════════════════════════════════════════════════════
-- TAB 3: KEYBINDS
-- Ported from CooldownKeybindsOptions.lua — adapted to sub-tab
-- ════════════════════════════════════════════════════════════

do
    local kbFrame = tabs[3].frame

    local kbScroll = CreateFrame("ScrollFrame", nil, kbFrame, "UIPanelScrollFrameTemplate")
    kbScroll:SetSize(760, 465)
    kbScroll:SetPoint("TOPLEFT", kbFrame, "TOPLEFT", 4, -4)

    local kbContent = CreateFrame("Frame", nil, kbScroll)
    kbContent:SetSize(740, 200)
    kbScroll:SetScrollChild(kbContent)

    -- ── Data ─────────────────────────────────────────────────
    local VIEWER_ROWS = {
        { key="Essential",           label="Essential",                    always=true  },
        { key="Utility",             label="Utility",                      always=true  },
        { key="Defensives",          label="Defensives (Ayije_CDM)",       always=false, addon="Ayije_CDM" },
        { key="Trinkets",            label="Trinkets (Ayije_CDM)",         always=false, addon="Ayije_CDM" },
        { key="Racials",             label="Racials (Ayije_CDM)",          always=false, addon="Ayije_CDM" },
        { key="BCDMCustomSpells",    label="Custom Spells (BCDM)",         always=false, addon="BetterCooldownManager" },
        { key="BCDMCustomItemSpellBar",label="Custom Item Spell Bar (BCDM)", always=false, addon="BetterCooldownManager" },
        { key="BCDMCustomItems",     label="Custom Items (BCDM)",          always=false, addon="BetterCooldownManager" },
        { key="BCDMTrinkets",        label="Trinket Bar (BCDM)",           always=false, addon="BetterCooldownManager" },
    }

    local ANCHOR_LIST = {
        {"TOPRIGHT","Top Right"},{"TOPLEFT","Top Left"},{"TOP","Top"},
        {"BOTTOMRIGHT","Bottom Right"},{"BOTTOMLEFT","Bottom Left"},{"BOTTOM","Bottom"},
        {"RIGHT","Right"},{"LEFT","Left"},{"CENTER","Center"},
    }

    local FONT_FLAG_LIST = {
        {"OUTLINE","Outline"},{"THICKOUTLINE","Thick Outline"},
        {"MONOCHROME","Monochrome"},{"MONOCHROME,OUTLINE","Mono Outline"},
        {"MONOCHROME,THICKOUTLINE","Mono Thick"},{"","None"},
    }

    -- ── Widget helpers ────────────────────────────────────────
    local allKBPopups = {}

    local function KBDropdown(parent, items, getVal, setVal, w, pt, ref, ox, oy)
        local btn = CreateFrame("Button",nil,parent,"GameMenuButtonTemplate")
        btn:SetSize(w,22); btn:SetPoint(pt,ref,pt,ox,oy); btn:SetText(getVal() or "")
        local popup = CreateFrame("Frame",nil,UIParent,"BackdropTemplate")
        popup:SetSize(w,10); popup:SetFrameStrata("DIALOG")
        popup:SetBackdrop({bgFile="Interface/DialogFrame/UI-DialogBox-Background",edgeFile="Interface/Tooltips/UI-Tooltip-Border",tile=true,tileSize=8,edgeSize=8,insets={left=2,right=2,top=2,bottom=2}})
        popup:SetBackdropColor(0.1,0.1,0.1,0.97); popup:Hide()
        local function Rebuild()
            for _,ch in ipairs({popup:GetChildren()}) do ch:Hide() end
            local ROW=20; local cnt=0
            for _,item in ipairs(items) do
                cnt=cnt+1
                local row=CreateFrame("Button",nil,popup)
                row:SetSize(w-10,ROW); row:SetPoint("TOPLEFT",6,-(cnt-1)*ROW-4)
                local hl=row:CreateTexture(nil,"HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1,1,1,0.12)
                local lbl=row:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
                lbl:SetPoint("LEFT",4,0); lbl:SetJustifyH("LEFT"); lbl:SetText(item[2])
                local capItem=item
                row:SetScript("OnClick",function() setVal(capItem[1]); btn:SetText(capItem[2]); popup:Hide() end)
            end
            popup:SetHeight(cnt*ROW+8)
        end
        btn:SetScript("OnClick",function()
            if popup:IsShown() then popup:Hide(); return end
            local curV=getVal()
            for _,item in ipairs(items) do if item[1]==curV then btn:SetText(item[2]); break end end
            Rebuild(); popup:ClearAllPoints(); popup:SetPoint("TOPLEFT",btn,"BOTTOMLEFT",0,-2); popup:Show()
        end)
        allKBPopups[#allKBPopups+1]=popup
        return btn, popup
    end

    local function KBSlider(parent, minV, maxV, step, getVal, setVal, pt, ref, ox, oy, w)
        local s=CreateFrame("Slider",nil,parent,"OptionsSliderTemplate")
        s:SetSize(w or 120,16); s:SetPoint(pt,ref,pt,ox,oy)
        s:SetMinMaxValues(minV,maxV); s:SetValueStep(step); s:SetObeyStepOnDrag(true)
        s:SetValue(getVal())
        s:SetScript("OnValueChanged",function(self2) setVal(math.floor(self2:GetValue()+0.5)) end)
        return s
    end

    local function KBColorSwatch(parent, getColor, setColor, pt, ref, ox, oy)
        local sw=CreateFrame("Button",nil,parent,"BackdropTemplate")
        sw:SetSize(18,18); sw:SetPoint(pt,ref,pt,ox,oy)
        sw:SetBackdrop({bgFile="Interface/Buttons/WHITE8X8",edgeFile="Interface/Tooltips/UI-Tooltip-Border",edgeSize=8,insets={left=2,right=2,top=2,bottom=2}})
        local r,g,b,a=getColor(); sw:SetBackdropColor(r,g,b,a)
        local function Update() local r2,g2,b2,a2=getColor(); sw:SetBackdropColor(r2,g2,b2,a2) end
        sw:SetScript("OnClick",function()
            local cr,cg,cb,ca=getColor()
            ColorPickerFrame:SetupColorPickerAndShow({
                r=cr, g=cg, b=cb, opacity=1-(ca or 1), hasOpacity=true,
                swatchFunc=function()
                    local nr,ng,nb=ColorPickerFrame:GetColorRGB()
                    local na=1-OpacitySliderFrame:GetValue()
                    setColor(nr,ng,nb,na); Update()
                end,
                cancelFunc=function(prev)
                    setColor(prev.r,prev.g,prev.b,1-(prev.opacity or 0)); Update()
                end,
                previousValues={r=cr,g=cg,b=cb,opacity=1-(ca or 1)},
            })
        end)
        return sw, Update
    end

    local function IsAddonLoaded(addon)
        if not addon then return true end
        return C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded(addon)
    end

    local function BuildViewerSection(parent, row, yOff)
        local vk = row.key
        local v  = API.CKBGetViewerDB(vk)

        local hdr = parent:CreateFontString(nil,"OVERLAY","GameFontNormal")
        hdr:SetPoint("TOPLEFT",parent,"TOPLEFT",0,yOff)
        if row.addon and not IsAddonLoaded(row.addon) then
            hdr:SetText("|cFF888888"..row.label.." (not loaded)|r")
        else
            hdr:SetText("|cFFFFD700"..row.label.."|r")
        end
        yOff = yOff - 24

        -- Show keybinds checkbox
        local cbName = "CM_CKBShow_"..vk
        local cb = CreateFrame("CheckButton",cbName,parent,"UICheckButtonTemplate")
        cb:SetSize(22,22); cb:SetPoint("TOPLEFT",parent,"TOPLEFT",0,yOff)
        local lbl=_G[cbName.."Text"]; if lbl then lbl:SetText("Show keybinds") end
        cb:SetChecked(v.showKeybinds ~= false)
        cb:SetScript("OnClick",function(self)
            v.showKeybinds=self:GetChecked()
            if API.CKBOnSettingChanged then API.CKBOnSettingChanged() end
        end)
        yOff = yOff - 26

        -- Font size
        local fsLabel = parent:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
        fsLabel:SetPoint("TOPLEFT",parent,"TOPLEFT",0,yOff); fsLabel:SetText("Font size:")
        local fsVal = parent:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
        fsVal:SetPoint("LEFT",fsLabel,"RIGHT",60,0); fsVal:SetText(tostring(v.fontSize or 12))
        KBSlider(parent,8,24,1,
            function() return v.fontSize or 12 end,
            function(val) v.fontSize=val; fsVal:SetText(tostring(val)); if API.CKBOnSettingChanged then API.CKBOnSettingChanged() end end,
            "TOPLEFT",parent,100,yOff,120)
        yOff = yOff - 26

        -- Anchor
        local ancLabel = parent:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
        ancLabel:SetPoint("TOPLEFT",parent,"TOPLEFT",0,yOff); ancLabel:SetText("Anchor:")
        local curAncLabel="Top Right"
        for _,a in ipairs(ANCHOR_LIST) do if a[1]==(v.anchor or "TOPRIGHT") then curAncLabel=a[2]; break end end
        local ancBtn, _ = KBDropdown(parent,ANCHOR_LIST,
            function() return v.anchor or "TOPRIGHT" end,
            function(val) v.anchor=val; if API.CKBOnSettingChanged then API.CKBOnSettingChanged() end end,
            130,"TOPLEFT",parent,90,yOff)
        ancBtn:SetText(curAncLabel)
        yOff = yOff - 26

        -- Offset X/Y
        local oxLabel=parent:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
        oxLabel:SetPoint("TOPLEFT",parent,"TOPLEFT",0,yOff); oxLabel:SetText("Offset X/Y:")
        local oxVal=parent:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
        oxVal:SetPoint("LEFT",oxLabel,"RIGHT",66,0); oxVal:SetText(tostring(v.offsetX or -1))
        KBSlider(parent,-50,50,1,
            function() return v.offsetX or -1 end,
            function(val) v.offsetX=val; oxVal:SetText(tostring(val)); if API.CKBOnSettingChanged then API.CKBOnSettingChanged() end end,
            "TOPLEFT",parent,100,yOff,120)
        yOff = yOff - 22
        local oyVal=parent:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
        oyVal:SetPoint("TOPLEFT",parent,"TOPLEFT",100,yOff); oyVal:SetText(tostring(v.offsetY or -1))
        KBSlider(parent,-50,50,1,
            function() return v.offsetY or -1 end,
            function(val) v.offsetY=val; oyVal:SetText(tostring(val)); if API.CKBOnSettingChanged then API.CKBOnSettingChanged() end end,
            "TOPLEFT",parent,100,yOff,120)
        yOff = yOff - 26

        -- Font outline
        local ffLabel=parent:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
        ffLabel:SetPoint("TOPLEFT",parent,"TOPLEFT",0,yOff); ffLabel:SetText("Outline:")
        local curFFLabel="Outline"
        for _,a in ipairs(FONT_FLAG_LIST) do if a[1]==(v.fontFlags or "OUTLINE") then curFFLabel=a[2]; break end end
        local ffBtn, _ = KBDropdown(parent,FONT_FLAG_LIST,
            function() return v.fontFlags or "OUTLINE" end,
            function(val) v.fontFlags=val; if API.CKBOnSettingChanged then API.CKBOnSettingChanged() end end,
            130,"TOPLEFT",parent,90,yOff)
        ffBtn:SetText(curFFLabel)
        yOff = yOff - 26

        -- Colour
        local colLabel=parent:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
        colLabel:SetPoint("TOPLEFT",parent,"TOPLEFT",0,yOff); colLabel:SetText("Colour:")
        KBColorSwatch(parent,
            function() local c=v.color or {1,1,1,1}; return c[1],c[2],c[3],c[4] end,
            function(r,g,b,a) v.color={r,g,b,a}; if API.CKBOnSettingChanged then API.CKBOnSettingChanged() end end,
            "TOPLEFT",parent,90,yOff+2)
        yOff = yOff - 20

        -- Separator
        local sep=parent:CreateTexture(nil,"OVERLAY"); sep:SetColorTexture(0.3,0.3,0.3,0.5)
        sep:SetSize(680,1); sep:SetPoint("TOPLEFT",parent,"TOPLEFT",0,yOff)
        yOff = yOff - 14

        return yOff
    end

    local kbBuilt = false
    local function BuildKeybindsUI()
        if kbBuilt then return end; kbBuilt = true

        local yOff = -4

        -- Global enable
        local enCB=CreateFrame("CheckButton","CM_CKBGlobalEnable",kbContent,"UICheckButtonTemplate")
        enCB:SetSize(22,22); enCB:SetPoint("TOPLEFT",kbContent,"TOPLEFT",0,yOff)
        local enLbl=_G["CM_CKBGlobalEnableText"]; if enLbl then enLbl:SetText("Enable CDM Keybind Overlays") end
        local db0=API.CKBGetDB(); enCB:SetChecked(db0 and db0.enabled ~= false)
        enCB:SetScript("OnClick",function(self)
            local db=API.CKBGetDB(); if db then db.enabled=self:GetChecked() end
            if API.CKBOnSettingChanged then API.CKBOnSettingChanged() end
        end)
        yOff = yOff - 32

        local desc=kbContent:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
        desc:SetPoint("TOPLEFT",kbContent,"TOPLEFT",0,yOff)
        desc:SetWidth(680); desc:SetJustifyH("LEFT"); desc:SetWordWrap(true)
        desc:SetTextColor(0.75,0.75,0.75,1)
        desc:SetText("Displays your action bar keybinds on Blizzard Cooldown Manager, BetterCooldownManager, and Ayije_CDM icons. Settings save with your spec profile.")
        yOff = yOff - 40

        for _, row in ipairs(VIEWER_ROWS) do
            yOff = BuildViewerSection(kbContent, row, yOff)
        end

        -- Reset button
        yOff = yOff - 8
        local resetBtn=CreateFrame("Button","CM_CKBResetBtn",kbContent,"GameMenuButtonTemplate")
        resetBtn:SetSize(160,26); resetBtn:SetPoint("TOPLEFT",kbContent,"TOPLEFT",0,yOff); resetBtn:SetText("Reset all to defaults")
        resetBtn:SetScript("OnClick",function()
            StaticPopupDialogs["CM_CKB_RESET"]={
                text="Reset CDM Keybind settings to defaults?",
                button1="Yes", button2="No",
                OnAccept=function()
                    if API.CKBResetDefaults then API.CKBResetDefaults() end
                    kbBuilt=false
                    for _,ch in ipairs({kbContent:GetChildren()}) do ch:Hide() end
                    BuildKeybindsUI()
                end,
                timeout=0, whileDead=true, hideOnEscape=true,
            }
            StaticPopup_Show("CM_CKB_RESET")
        end)

        yOff = yOff - 36
        kbContent:SetHeight(math.abs(yOff)+20)
    end

    tabs[3].onActivate = function()
        BuildKeybindsUI()
        local db=API.CKBGetDB()
        if _G["CM_CKBGlobalEnable"] then _G["CM_CKBGlobalEnable"]:SetChecked(db and db.enabled ~= false) end
    end
end

-- ════════════════════════════════════════════════════════════
-- TAUNT WATCH SECTION (inside Tab 1, below bars)
-- Encounter-aware display control panel
-- ════════════════════════════════════════════════════════════
do
    local cdmFrame = tabs[1].frame

    -- Section header separator
    local sep = cdmFrame:CreateTexture(nil, "BACKGROUND")
    sep:SetColorTexture(0.3, 0.3, 0.5, 0.5)
    sep:SetHeight(1)
    sep:SetPoint("TOPLEFT",  cdmFrame, "TOPLEFT",  16, -740)
    sep:SetPoint("TOPRIGHT", cdmFrame, "TOPRIGHT", -16, -740)

    local twHeader = cdmFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    twHeader:SetPoint("TOPLEFT", 16, -760)
    twHeader:SetText("|cFF88AAFFTaunt Watch|r")

    -- Enable checkbox
    local twEnable = CreateFrame("CheckButton", nil, cdmFrame, "UICheckButtonTemplate")
    twEnable:SetSize(22, 22)
    twEnable:SetPoint("LEFT", twHeader, "RIGHT", 12, 0)
    if API.TauntWatch and type(API.TauntWatch.IsEnabled) == "function" then
        twEnable:SetChecked(API.TauntWatch.IsEnabled())
    end
    twEnable:SetScript("OnClick", function(self)
        if API.TauntWatch and type(API.TauntWatch.SetEnabled) == "function" then
            API.TauntWatch.SetEnabled(self:GetChecked())
        end
    end)
    local twEnableLbl = cdmFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    twEnableLbl:SetPoint("LEFT", twEnable, "RIGHT", 4, 0)
    twEnableLbl:SetText("Enable taunt watch overlays")

    -- Anchor position controls
    local anchorLbl = cdmFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    anchorLbl:SetPoint("TOPLEFT", 16, -784)
    anchorLbl:SetText("Overlay position  X:")

    local twAnchorX = CreateFrame("EditBox", nil, cdmFrame, "InputBoxTemplate")
    twAnchorX:SetSize(50, 20)
    twAnchorX:SetPoint("LEFT", anchorLbl, "RIGHT", 6, 0)
    twAnchorX:SetAutoFocus(false)
    twAnchorX:SetNumeric(false)

    local yLbl = cdmFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    yLbl:SetPoint("LEFT", twAnchorX, "RIGHT", 8, 0)
    yLbl:SetText("Y:")

    local twAnchorY = CreateFrame("EditBox", nil, cdmFrame, "InputBoxTemplate")
    twAnchorY:SetSize(50, 20)
    twAnchorY:SetPoint("LEFT", yLbl, "RIGHT", 6, 0)
    twAnchorY:SetAutoFocus(false)
    twAnchorY:SetNumeric(false)

    local applyBtn = CreateFrame("Button", nil, cdmFrame, "GameMenuButtonTemplate")
    applyBtn:SetSize(60, 20)
    applyBtn:SetPoint("LEFT", twAnchorY, "RIGHT", 8, 0)
    applyBtn:SetText("Apply")
    applyBtn:SetScript("OnClick", function()
        local x = tonumber(twAnchorX:GetText()) or -300
        local y = tonumber(twAnchorY:GetText()) or 200
        if API.TauntWatch and type(API.TauntWatch.SetAnchorPosition) == "function" then
            API.TauntWatch.SetAnchorPosition(x, y)
        end
    end)

    -- Encounter list with per-spell threshold display
    local encScroll = CreateFrame("ScrollFrame", nil, cdmFrame, "UIPanelScrollFrameTemplate")
           encScroll:SetPoint("TOPLEFT",    cdmFrame, "TOPLEFT",    16, -814)
           encScroll:SetSize(800, 180) -- FIX: Constrain height to prevent burying the section below
           local encContent = CreateFrame("Frame", nil, encScroll)
    encContent:SetSize(800, 400)
    encScroll:SetScrollChild(encContent)

    local function BuildEncounterList()
        -- Clear existing children
        for _, child in pairs({encContent:GetChildren()}) do child:Hide() end

        local y = 0
        local data = {}
        if API.TauntWatch and type(API.TauntWatch.GetEncounterData) == "function" then
            data = API.TauntWatch.GetEncounterData() or {}
        end
        for encID, enc in pairs(data) do
            -- Boss header
            local hdr = encContent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            hdr:SetPoint("TOPLEFT", 0, y)
            hdr:SetText("|cFFFFD700" .. enc.name .. "|r  |cFF888888[ID: " .. encID .. "]|r")
            y = y - 20

            for _, watch in ipairs(enc.watches or {}) do
                local row = CreateFrame("Frame", nil, encContent, "BackdropTemplate")
                row:SetSize(780, 28)
                row:SetPoint("TOPLEFT", 0, y)
                row:SetBackdrop({bgFile="Interface\Buttons\WHITE8x8", edgeFile="Interface\Buttons\WHITE8x8", edgeSize=1})
                row:SetBackdropColor(0.08, 0.08, 0.12, 0.6)
                row:SetBackdropBorderColor(0.25, 0.25, 0.4, 0.5)

                local icon = row:CreateTexture(nil, "ARTWORK")
                icon:SetSize(22, 22)
                icon:SetPoint("LEFT", 4, 0)
                icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                local tex = C_Spell.GetSpellTexture(watch.spellID)
                if tex then icon:SetTexture(tex) end

                local typeColor = watch.type == "debuff" and "|cFFFF6666" or
                                  watch.type == "buff"   and "|cFF66FF66" or "|cFFFFAA44"
                local nameLbl = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                nameLbl:SetPoint("LEFT", 30, 0)
                nameLbl:SetWidth(280)
                nameLbl:SetJustifyH("LEFT")
                nameLbl:SetText(typeColor .. "[" .. watch.type:upper() .. "]|r " .. watch.label)

                local idLbl = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                idLbl:SetPoint("LEFT", 316, 0)
                idLbl:SetText("|cFF888888ID: " .. watch.spellID .. "|r")

                if watch.type == "debuff" or watch.type == "buff" then
                    local threshLbl = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                    threshLbl:SetPoint("LEFT", 420, 0)
                    threshLbl:SetText("Threshold:")

                    local threshBox = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
                    threshBox:SetSize(35, 18)
                    threshBox:SetPoint("LEFT", threshLbl, "RIGHT", 4, 0)
                    threshBox:SetAutoFocus(false)
                    threshBox:SetNumeric(true)
                    local cur = watch.defaultStacks or 5
                    if API.TauntWatch and type(API.TauntWatch.GetThreshold) == "function" then
                        cur = API.TauntWatch.GetThreshold(watch.spellID, watch.defaultStacks) or cur
                    end
                    threshBox:SetText(tostring(cur))
                    threshBox:SetScript("OnEnterPressed", function(self)
                        local v = tonumber(self:GetText())
                        if v and v > 0 and API.TauntWatch and type(API.TauntWatch.SetThreshold) == "function" then
                            API.TauntWatch.SetThreshold(watch.spellID, v)
                        end
                        self:ClearFocus()
                    end)
                end

                y = y - 32
            end
            y = y - 8
        end
        encContent:SetHeight(math.max(400, math.abs(y) + 20))
    end

    -- Populate anchor fields and list when tab activates
    local origTab1Activate = tabs[1].onActivate
    tabs[1].onActivate = function()
        if origTab1Activate then origTab1Activate() end
        -- Refresh enable state
        if API.TauntWatch and type(API.TauntWatch.IsEnabled) == "function" then
            twEnable:SetChecked(API.TauntWatch.IsEnabled())
        end
        -- Populate anchor position
        local x, y = 0, -200
        if API.TauntWatch and type(API.TauntWatch.GetAnchorPosition) == "function" then
            x, y = API.TauntWatch.GetAnchorPosition()
        end
        twAnchorX:SetText(tostring(x))
        twAnchorY:SetText(tostring(y))
        BuildEncounterList()
    end
end

-- ════════════════════════════════════════════════════════════
-- TAUNT SWAP SETTINGS (Clickable list in Tab 1)
-- ════════════════════════════════════════════════════════════
do
    local cdmFrame = tabs[1].frame
    
    -- Create settings popup for TauntSwap debuffs
    local function BuildTauntSwapSettingsPopup()
        local f = CreateFrame("Frame", "RogUITauntSwapSettings", UIParent, "BackdropTemplate")
        f:SetSize(350, 250)
        f:SetFrameStrata("DIALOG")
        f:SetFrameLevel(200)
        f:SetBackdrop({ bgFile="Interface\\Buttons\\WHITE8x8",
                        edgeFile="Interface\\Buttons\\WHITE8x8", edgeSize=1 })
        f:SetBackdropColor(0.06, 0.06, 0.12, 0.96)
        f:SetBackdropBorderColor(0.4, 0.4, 0.7, 1)
        f:SetMovable(true); f:EnableMouse(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving)
        f:SetScript("OnDragStop",  f.StopMovingOrSizing)
        f:Hide()

        -- Title
        local title = f:CreateFontString(nil,"OVERLAY","GameFontNormal")
        title:SetPoint("TOPLEFT",f,"TOPLEFT",10,-10)
        title:SetPoint("TOPRIGHT",f,"TOPRIGHT",-30,-10)
        title:SetJustifyH("LEFT"); title:SetTextColor(1,0.85,0.2,1)
        f.title = title

        -- Close button
        local closeBtn = CreateFrame("Button",nil,f,"UIPanelCloseButton")
        closeBtn:SetSize(22,22); closeBtn:SetPoint("TOPRIGHT",f,"TOPRIGHT",-2,-2)
        closeBtn:SetScript("OnClick", function() f:Hide() end)

        -- Stack threshold
        local threshHeader = f:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
        threshHeader:SetPoint("TOPLEFT",f,"TOPLEFT",10,-40)
        threshHeader:SetTextColor(0.7,0.9,1,1)
        threshHeader:SetText("Stack Alert Threshold")

        local threshDesc = f:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
        threshDesc:SetPoint("TOPLEFT",threshHeader,"BOTTOMLEFT",0,-2)
        threshDesc:SetTextColor(0.55,0.55,0.55,1); threshDesc:SetText("Alert when stacks reach:")

        local decBtn = CreateFrame("Button",nil,f,"GameMenuButtonTemplate")
        decBtn:SetSize(26,22); decBtn:SetPoint("TOPLEFT",threshDesc,"BOTTOMLEFT",0,-4)
        decBtn:SetText("-"); f.decBtn = decBtn

        local threshDisplay = f:CreateFontString(nil,"OVERLAY","GameFontNormal")
        threshDisplay:SetPoint("LEFT",decBtn,"RIGHT",6,0)
        threshDisplay:SetWidth(30); threshDisplay:SetJustifyH("CENTER")
        f.threshDisplay = threshDisplay

        local incBtn = CreateFrame("Button",nil,f,"GameMenuButtonTemplate")
        incBtn:SetSize(26,22); incBtn:SetPoint("LEFT",threshDisplay,"RIGHT",6,0)
        incBtn:SetText("+"); f.incBtn = incBtn

        -- Alert mode
        local modeLabel = f:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
        modeLabel:SetPoint("TOPLEFT",decBtn,"BOTTOMLEFT",0,-12)
        modeLabel:SetTextColor(0.7,0.9,1,1); modeLabel:SetText("Alert Mode")

        local iconModeBtn = CreateFrame("CheckButton","TSIcon",f,"UIRadioButtonTemplate")
        iconModeBtn:SetSize(20,20); iconModeBtn:SetPoint("TOPLEFT",modeLabel,"BOTTOMLEFT",0,-4)
        local iconModeLbl = f:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
        iconModeLbl:SetPoint("LEFT",iconModeBtn,"RIGHT",2,0); iconModeLbl:SetText("Icon")
        f.iconMode = iconModeBtn

        local barModeBtn = CreateFrame("CheckButton","TSBar",f,"UIRadioButtonTemplate")
        barModeBtn:SetSize(20,20); barModeBtn:SetPoint("LEFT",iconModeLbl,"RIGHT",20,0)
        local barModeLbl = f:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
        barModeLbl:SetPoint("LEFT",barModeBtn,"RIGHT",2,0); barModeLbl:SetText("Bar")
        f.barMode = barModeBtn

        iconModeBtn:SetScript("OnClick",function() iconModeBtn:SetChecked(true); barModeBtn:SetChecked(false) end)
        barModeBtn:SetScript("OnClick",function() barModeBtn:SetChecked(true); iconModeBtn:SetChecked(false) end)

        local previewBtn = CreateFrame("Button",nil,f,"GameMenuButtonTemplate")
        previewBtn:SetSize(80,22); previewBtn:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -10, 10)
        previewBtn:SetText("Preview")
        f.previewBtn = previewBtn

        return f
    end
    
    local tsPopup = BuildTauntSwapSettingsPopup()
    
    -- Add clickable TauntSwap debuff list
    -- Section header (gives us an anchor and makes the section visible)
    local tswapHeader = cdmFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    tswapHeader:SetPoint("TOPLEFT", cdmFrame, "TOPLEFT", 16, -1020)
    tswapHeader:SetText("|cFFFFAAAATaunt Swap Tracker|r")

    local tswapDesc = cdmFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    tswapDesc:SetPoint("TOPLEFT", tswapHeader, "BOTTOMLEFT", 0, -4)
    tswapDesc:SetTextColor(0.6, 0.6, 0.6, 1)
    tswapDesc:SetText("Debuffs tracked for personal taunt-swap alerts. Configure stack threshold and alert mode.")

    local tswapScroll = CreateFrame("ScrollFrame", nil, cdmFrame, "UIPanelScrollFrameTemplate")
    tswapScroll:SetSize(1000, 200)
    tswapScroll:SetPoint("TOPLEFT", tswapDesc, "BOTTOMLEFT", 0, -8)
    
    local tswapContent = CreateFrame("Frame", nil, tswapScroll)
    tswapContent:SetSize(960, 200)
    tswapScroll:SetScrollChild(tswapContent)
    
    local function PopulateTauntSwapList()
        for _, child in ipairs({tswapContent:GetChildren()}) do child:Hide(); child:SetParent(nil) end

        -- Always read directly from the API table — never cache a local copy,
        -- because OnLoadProfile wipes and repopulates the same table object.
        local list = API.trackedTauntDebuffs or {}
        local y = 0

        for idx, debuff in ipairs(list) do
            if debuff.enabled ~= false and debuff.spellId and debuff.spellId > 0 then
                local btn = CreateFrame("Button", nil, tswapContent)
                btn:SetHeight(28)
                btn:SetWidth(960)
                btn:SetPoint("TOPLEFT", tswapContent, "TOPLEFT", 0, y)
                btn:EnableMouse(true)
                
                local spellInfo = C_Spell.GetSpellInfo(debuff.spellId)
                local spellName = spellInfo and spellInfo.name or ("Spell "..debuff.spellId)
                
                local nameStr = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                nameStr:SetPoint("LEFT", 10, 0)
                nameStr:SetText(spellName)
                
                local threshStr = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                threshStr:SetPoint("LEFT", 300, 0)
                threshStr:SetTextColor(1, 0.8, 0.2, 1)
                threshStr:SetText("Threshold: " .. (debuff.stackThreshold or 5))
                
                local modeStr = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                modeStr:SetPoint("RIGHT", -10, 0)
                modeStr:SetTextColor(0.7, 0.7, 0.7, 1)
                modeStr:SetText("[Click to configure]")
                
                btn:SetScript("OnClick", function()
                    tsPopup.title:SetText(spellName)
                    tsPopup.threshDisplay:SetText(tostring(debuff.stackThreshold or 5))
                    
                    tsPopup.decBtn:SetScript("OnClick", function()
                        local v = math.max(0, (debuff.stackThreshold or 5) - 1)
                        debuff.stackThreshold = v
                        tsPopup.threshDisplay:SetText(tostring(v))
                        if API.SaveSpecProfile then API.SaveSpecProfile() end
                    end)
                    
                    tsPopup.incBtn:SetScript("OnClick", function()
                        local v = math.min(99, (debuff.stackThreshold or 5) + 1)
                        debuff.stackThreshold = v
                        tsPopup.threshDisplay:SetText(tostring(v))
                        if API.SaveSpecProfile then API.SaveSpecProfile() end
                    end)
                    
                    if debuff.alertMode == "bar" then
                        tsPopup.barMode:SetChecked(true)
                        tsPopup.iconMode:SetChecked(false)
                    else
                        tsPopup.iconMode:SetChecked(true)
                        tsPopup.barMode:SetChecked(false)
                    end
                    
                    tsPopup.iconMode:SetScript("OnClick", function()
                        tsPopup.iconMode:SetChecked(true)
                        tsPopup.barMode:SetChecked(false)
                        debuff.alertMode = "icon"
                        if API.SaveSpecProfile then API.SaveSpecProfile() end
                    end)
                    
                    tsPopup.barMode:SetScript("OnClick", function()
                        tsPopup.barMode:SetChecked(true)
                        tsPopup.iconMode:SetChecked(false)
                        debuff.alertMode = "bar"
                        if API.SaveSpecProfile then API.SaveSpecProfile() end
                    end)
                    
                    if tsPopup.previewBtn then
                        tsPopup.previewBtn:SetScript("OnClick", function()
                            -- The 'true' flag explicitly bypasses the boss-fight-only check
                            if UpdateTauntVisibility then 
                                UpdateTauntVisibility(tauntOverlayFrame, true) 
                            elseif API.ShowAlertOverlay then
                                API.ShowAlertOverlay({
                                    alertTexture = C_Spell.GetSpellTexture(debuff.spellId) or "Interface\\Icons\\INV_Misc_QuestionMark", 
                                    spellId = debuff.spellId,
                                    alertMode = debuff.alertMode, 
                                    alertBarWidth = debuff.alertBarWidth,
                                    alertSize = debuff.alertSize or 64, 
                                    alertDuration = 5,
                                    alertX = debuff.alertX or 0, 
                                    alertY = debuff.alertY or 0,
                                }, spellName)
                            end
                        end)
                    end
                    
                    tsPopup:ClearAllPoints()
                    tsPopup:SetPoint("CENTER", UIParent, "CENTER", 0, 100)
                    tsPopup:Show()
                end)
                
                btn:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetText(spellName, 1, 1, 1)
                    GameTooltip:AddLine("Click to configure alert settings")
                    GameTooltip:Show()
                end)
                btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
                
                y = y - 28
            end
        end
        
        if #list == 0 then
            local noItemsStr = tswapContent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            noItemsStr:SetPoint("TOPLEFT", 10, 0)
            noItemsStr:SetTextColor(0.5, 0.5, 0.5, 1)
            noItemsStr:SetText("(No tracked taunt debuffs)")
            y = y - 20
        end
        
        tswapContent:SetHeight(math.max(200, math.abs(y) + 10))
    end
    
    -- Populate on tab activate
    local origTab1Activate = tabs[1].onActivate
    tabs[1].onActivate = function()
        if origTab1Activate then origTab1Activate() end
        PopulateTauntSwapList()
    end
end


-- ════════════════════════════════════════════════════════════
-- REGISTER WITH CORE TAB SYSTEM
-- ════════════════════════════════════════════════════════════

C_Timer.After(0, function()
    API.RegisterTab(
        "Cooldown Management",
        masterFrame,
        function()
            if tabs[1].btn then tabs[1].btn:Click() end
        end,
        nil,
        nil,
        32
    )
end)

print("|cFF00FF00[RogUI] Cooldown Management UI loaded|r")