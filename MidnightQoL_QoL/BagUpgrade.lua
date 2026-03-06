-- ============================================================
-- MidnightQoL_QoL / BagUpgrade.lua
-- Overlays a green ilvl badge on bag items that are an upgrade
-- over the currently equipped item in that slot.
-- Hook approach based on Pawn's PawnBags.lua.
-- ============================================================

local API = MidnightQoLAPI

local overlays  = {}
local scanTimer = nil
local NUM_BAG_FRAMES = NUM_TOTAL_BAG_FRAMES or NUM_CONTAINER_FRAMES or 13

-- ── DB helper ─────────────────────────────────────────────────────────────────
local function IsEnabled()
    if not BuffAlertDB then return false end
    if BuffAlertDB.bagUpgradeEnabled == nil then return true end
    return BuffAlertDB.bagUpgradeEnabled
end

-- ── Equipped ilvl per inventory slot ─────────────────────────────────────────
local function GetEquippedIlvl(invSlotID)
    local link = GetInventoryItemLink("player", invSlotID)
    if not link then return 0 end
    local ok, ilvl = pcall(C_Item.GetDetailedItemLevelInfo, link)
    if ok and ilvl and ilvl > 0 then return ilvl end
    local _, _, _, itemLevel = GetItemInfo(link)
    return itemLevel or 0
end

-- Maps invType → inventory slot IDs the item could fill
local INVTYPE_TO_SLOTS = {
    INVTYPE_HEAD           = {1},
    INVTYPE_NECK           = {2},
    INVTYPE_SHOULDER       = {3},
    INVTYPE_CHEST          = {5},
    INVTYPE_WAIST          = {6},
    INVTYPE_LEGS           = {7},
    INVTYPE_FEET           = {8},
    INVTYPE_WRIST          = {9},
    INVTYPE_HAND           = {10},
    INVTYPE_FINGER         = {11, 12},
    INVTYPE_TRINKET        = {13, 14},
    INVTYPE_CLOAK          = {15},
    INVTYPE_WEAPON         = {16, 17},
    INVTYPE_SHIELD         = {17},
    INVTYPE_2HWEAPON       = {16},
    INVTYPE_WEAPONMAINHAND = {16},
    INVTYPE_WEAPONOFFHAND  = {17},
    INVTYPE_HOLDABLE       = {17},
    INVTYPE_RANGED         = {16},
    INVTYPE_RANGEDRIGHT    = {16},
    INVTYPE_ROBE           = {5},
}

-- ── Is this bag item an ilvl upgrade? ────────────────────────────────────────
local function IsUpgrade(link)
    if not link then return false, 0, 0 end
    local _, _, _, _, _, _, _, _, invType = GetItemInfo(link)
    if not invType or invType == "" or invType == "INVTYPE_NON_EQUIP" then return false, 0, 0 end
    local slots = INVTYPE_TO_SLOTS[invType]
    if not slots then return false, 0, 0 end

    local bagIlvl = 0
    local ok, detailed = pcall(C_Item.GetDetailedItemLevelInfo, link)
    if ok and detailed and detailed > 0 then
        bagIlvl = detailed
    else
        local _, _, _, il = GetItemInfo(link)
        bagIlvl = il or 0
    end
    if bagIlvl <= 0 then return false, 0, 0 end

    local bestEquipped = 0
    for _, slID in ipairs(slots) do
        local eq = GetEquippedIlvl(slID)
        if eq > bestEquipped then bestEquipped = eq end
    end

    if bestEquipped == 0 then return true, bagIlvl, 0 end
    return bagIlvl > bestEquipped, bagIlvl, bestEquipped
end

-- ── Overlay management ────────────────────────────────────────────────────────
local function GetOrCreateOverlay(button)
    if overlays[button] then return overlays[button] end
    local f = CreateFrame("Frame", nil, button)
    f:SetFrameLevel(button:GetFrameLevel() + 5)
    f:SetAllPoints(button)
    local arrow = f:CreateTexture(nil, "OVERLAY")
    arrow:SetSize(16, 16)
    arrow:SetPoint("TOPRIGHT", f, "TOPRIGHT", 2, 2)
    arrow:SetTexture("Interface\\Buttons\\UI-MicroStream-Green")
    arrow:SetVertexColor(0, 1, 0.2, 1)
    f.badge = arrow
    local lbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lbl:SetPoint("CENTER", arrow, "CENTER", 0, -3)
    lbl:SetFont(lbl:GetFont(), 8, "OUTLINE")
    lbl:SetTextColor(0, 1, 0.2, 1)
    f.lbl = lbl
    f:Hide()
    overlays[button] = f
    return f
end

-- ── Update a single item button ───────────────────────────────────────────────
local pendingButtons = {}
local retryTimer = nil

local function UpdateButton(button)
    if button.isExtended then return end
    if not IsEnabled() then
        if overlays[button] then overlays[button]:Hide() end
        return
    end

    local bagID = button.GetBagID and button:GetBagID() or button:GetParent():GetID()
    local slotID = button:GetID()
    local itemInfo = C_Container.GetContainerItemInfo(bagID, slotID)

    if not itemInfo or not itemInfo.stackCount or itemInfo.stackCount == 0 then
        if overlays[button] then overlays[button]:Hide() end
        return
    end

    local link = itemInfo.hyperlink
    if not link then
        -- Item not cached yet, retry shortly
        pendingButtons[button] = true
        if not retryTimer then
            retryTimer = C_Timer.NewTimer(0.2, function()
                retryTimer = nil
                local toRetry = pendingButtons
                pendingButtons = {}
                for btn in pairs(toRetry) do UpdateButton(btn) end
            end)
        end
        return
    end

    local upgrade, bagIlvl, equippedIlvl = IsUpgrade(link)
    if upgrade then
        local f = GetOrCreateOverlay(button)
        local delta = bagIlvl - equippedIlvl
        f.lbl:SetText(delta > 0 and ("+"..delta) or "NEW")
        f:Show()
    else
        if overlays[button] then overlays[button]:Hide() end
    end
end

-- ── Hook container frames via mixin (Pawn's approach) ────────────────────────
local function UpdateContainerFrame(self)
    if not IsEnabled() then return end
    for _, button in self:EnumerateValidItems() do
        UpdateButton(button)
    end
end

local function HideAllOverlays()
    for _, ov in pairs(overlays) do ov:Hide() end
end

-- ── Initialise hooks after frames exist ──────────────────────────────────────
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
initFrame:RegisterEvent("BAG_UPDATE_DELAYED")

initFrame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        self:UnregisterEvent("PLAYER_LOGIN")

        -- Hook the mixin — applies to all current and future ContainerFrame instances
        if ContainerFrameMixin then
            hooksecurefunc(ContainerFrameMixin, "UpdateItems", UpdateContainerFrame)
        end
        -- Hook the combined bags frame (TWW unified bag)
        if ContainerFrameCombinedBags then
            hooksecurefunc(ContainerFrameCombinedBags, "UpdateItems", UpdateContainerFrame)
        end
        -- Also hook each named frame retroactively (already-created frames don't get mixin hooks)
        for i = 1, NUM_BAG_FRAMES do
            local bag = _G["ContainerFrame"..i]
            if bag and bag.UpdateItems then
                hooksecurefunc(bag, "UpdateItems", UpdateContainerFrame)
            end
        end
        return
    end

    -- Equipment changed or bag updated: refresh all visible bags
    if not IsEnabled() then HideAllOverlays(); return end
    if scanTimer then scanTimer:Cancel() end
    scanTimer = C_Timer.NewTimer(0.3, function()
        scanTimer = nil
        if ContainerFrameCombinedBags and ContainerFrameCombinedBags:IsShown() then
            UpdateContainerFrame(ContainerFrameCombinedBags)
        end
        for i = 1, NUM_BAG_FRAMES do
            local bag = _G["ContainerFrame"..i]
            if bag and bag:IsShown() then UpdateContainerFrame(bag) end
        end
    end)
end)

API.BagUpgradeScan = function()
    if ContainerFrameCombinedBags and ContainerFrameCombinedBags:IsShown() then
        UpdateContainerFrame(ContainerFrameCombinedBags)
    end
    for i = 1, NUM_BAG_FRAMES do
        local bag = _G["ContainerFrame"..i]
        if bag and bag:IsShown() then UpdateContainerFrame(bag) end
    end
end

API.Debug("[MidnightQoL] BagUpgrade loaded.")
