-- ============================================================
-- RogUI / Modules / Bags / BagUpgrade.lua
-- MIGRATED: Unified event system
-- Overlays a green ilvl badge on bag items that are an upgrade
-- over the currently equipped item in that slot.
-- Hook approach based on Pawn's PawnBags.lua.
-- ============================================================

local API = RogUIAPI

local overlays  = {}
local scanTimer = nil
local NUM_BAG_FRAMES = NUM_TOTAL_BAG_FRAMES or NUM_CONTAINER_FRAMES or 13

-- ── DB helper ─────────────────────────────────────────────────────────────────
local function IsEnabled()
    if not RogUIDB then return false end
    if RogUIDB.bagUpgradeEnabled == nil then return false end
    return RogUIDB.bagUpgradeEnabled
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

-- ── Primary stat detection ────────────────────────────────────────────────────
-- Maps specID → primary stat ITEM_MOD key.
-- Trinkets, necks, cloaks, and rings are stat-agnostic and always pass.
local AGILITY_SPECS = {
    -- Druid: Feral/Guardian
    [103]=true,[104]=true,
    -- Hunter: all
    [253]=true,[254]=true,[255]=true,
    -- Monk: Brewmaster/Windwalker
    [268]=true,[269]=true,
    -- Rogue: all
    [259]=true,[260]=true,[261]=true,
    -- Demon Hunter: all
    [577]=true,[581]=true,
    -- Shaman: Enhancement
    [263]=true,
}
local INTELLECT_SPECS = {
    -- Death Knight: none
    -- Druid: Balance/Resto
    [102]=true,[105]=true,
    -- Evoker: all
    [1467]=true,[1468]=true,[1473]=true,
    -- Mage: all
    [62]=true,[63]=true,[64]=true,
    -- Monk: Mistweaver
    [270]=true,
    -- Paladin: Holy
    [65]=true,
    -- Priest: all
    [256]=true,[257]=true,[258]=true,
    -- Shaman: Elemental/Resto
    [262]=true,[264]=true,
    -- Warlock: all
    [265]=true,[266]=true,[267]=true,
}
-- Everything else (Warriors, DKs, Ret/Prot Paladin, BM/Prot DH) → Strength

-- Slots that don't have a primary stat and should always be considered
local STAT_AGNOSTIC_INVTYPES = {
    INVTYPE_NECK    = true,
    INVTYPE_FINGER  = true,
    INVTYPE_TRINKET = true,
    INVTYPE_CLOAK   = true,
}

local function GetPlayerPrimaryStatKey()
    local specIndex = GetSpecialization and GetSpecialization()
    if not specIndex then return nil end
    local specID = select(1, GetSpecializationInfo(specIndex))
    if not specID then return nil end
    -- C_Item.GetItemStats keys are the VALUES of the ITEM_MOD_*_SHORT globals
    -- (e.g. "Agility", "Strength", "Intellect" in English), not the variable names.
    if AGILITY_SPECS[specID]   then return ITEM_MOD_AGILITY_SHORT   end
    if INTELLECT_SPECS[specID] then return ITEM_MOD_INTELLECT_SHORT  end
    return ITEM_MOD_STRENGTH_SHORT
end

local function ItemHasPlayerPrimaryStat(link, invType)
    -- Stat-agnostic slots: always pass
    if STAT_AGNOSTIC_INVTYPES[invType] then return true end
    -- Weapons: always pass (they don't carry primary stats directly)
    if (invType and invType:find("WEAPON")) or invType == "INVTYPE_RANGED"
        or invType == "INVTYPE_RANGEDRIGHT" or invType == "INVTYPE_SHIELD"
        or invType == "INVTYPE_HOLDABLE" then
        return true
    end

    local primaryKey = GetPlayerPrimaryStatKey()
    if not primaryKey then return true end  -- can't determine spec, let it through

    local ok, stats = pcall(C_Item.GetItemStats, link)
    if not ok or type(stats) ~= "table" then return true end  -- no stat data, let it through

    return (stats[primaryKey] or 0) > 0
end


local function IsUpgrade(link)
    if not link then return false, 0, 0 end
    local _, _, _, _, _, _, _, _, invType = GetItemInfo(link)
    if not invType or invType == "" or invType == "INVTYPE_NON_EQUIP" then return false, 0, 0 end
    local slots = INVTYPE_TO_SLOTS[invType]
    if not slots then return false, 0, 0 end

    -- Skip items that don't have the player's primary stat
    if not ItemHasPlayerPrimaryStat(link, invType) then return false, 0, 0 end

    local bagIlvl = 0
    local ok, detailed = pcall(C_Item.GetDetailedItemLevelInfo, link)
    if ok and detailed and detailed > 0 then
        bagIlvl = detailed
    else
        local _, _, _, il = GetItemInfo(link)
        bagIlvl = il or 0
    end
    if bagIlvl <= 0 then return false, 0, 0 end

    -- For slots that can hold two items (rings, trinkets, 1H weapons), compare
    -- against the LOWER ilvl slot — that's the one we'd actually replace.
    -- For single-slot items the min and max are the same so this is still correct.
    local lowestEquipped = math.huge
    local anyEquipped    = false
    for _, slID in ipairs(slots) do
        local eq = GetEquippedIlvl(slID)
        if eq > 0 then
            anyEquipped = true
            if eq < lowestEquipped then lowestEquipped = eq end
        end
    end

    if not anyEquipped then return true, bagIlvl, 0 end
    return bagIlvl > lowestEquipped, bagIlvl, lowestEquipped
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

-- ── Group loot roll overlays ──────────────────────────────────────────────────
-- Hook GroupLootFrame1-4 OnShow (same approach as Pawn).
-- Each frame has a .rollID and an .IconFrame child; we overlay the badge on
-- IconFrame so it sits on top of the item icon.

local lootOverlays = {}

local function GetOrCreateLootOverlay(iconFrame)
    if lootOverlays[iconFrame] then return lootOverlays[iconFrame] end
    local f = CreateFrame("Frame", nil, iconFrame)
    f:SetFrameLevel(iconFrame:GetFrameLevel() + 5)
    f:SetAllPoints(iconFrame)
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
    lootOverlays[iconFrame] = f
    return f
end

local function UpdateGroupLootFrame(self)
    local iconFrame = self.IconFrame
    if not iconFrame then return end

    if not IsEnabled() then
        if lootOverlays[iconFrame] then lootOverlays[iconFrame]:Hide() end
        return
    end

    local link = self.rollID and GetLootRollItemLink(self.rollID)
    if not link then
        if lootOverlays[iconFrame] then lootOverlays[iconFrame]:Hide() end
        return
    end

    local upgrade, bagIlvl, equippedIlvl = IsUpgrade(link)
    if upgrade then
        local f = GetOrCreateLootOverlay(iconFrame)
        local delta = bagIlvl - equippedIlvl
        f.lbl:SetText(delta > 0 and ("+"..delta) or "NEW")
        f:Show()
    else
        if lootOverlays[iconFrame] then lootOverlays[iconFrame]:Hide() end
    end
end


local function ScanAllVisibleBags()
    if ContainerFrameCombinedBags and ContainerFrameCombinedBags:IsShown() then
        UpdateContainerFrame(ContainerFrameCombinedBags)
    end
    for i = 1, NUM_BAG_FRAMES do
        local bag = _G["ContainerFrame"..i]
        if bag and bag:IsShown() then UpdateContainerFrame(bag) end
    end
end

-- Schedule a scan after `delay` seconds, cancelling any pending scan first.
-- If `andAgain` is true, schedule a second pass 1s later to catch items whose
-- data wasn't cached yet on the first pass (common after rapid gear swaps).
local lateTimer = nil
local function ScheduleScan(delay, andAgain)
    if not IsEnabled() then HideAllOverlays(); return end
    if scanTimer then scanTimer:Cancel() end
    scanTimer = C_Timer.NewTimer(delay, function()
        scanTimer = nil
        ScanAllVisibleBags()
        if andAgain then
            if lateTimer then lateTimer:Cancel() end
            lateTimer = C_Timer.NewTimer(1.0, function()
                lateTimer = nil
                if IsEnabled() then ScanAllVisibleBags() end
            end)
        end
    end)
end

-- ── Events (unified system) ──────────────────────────────────────────────────
local bagUpgradeLoginFired = false
local function OnBagUpgradeEvent(event, arg1)
    if event == "PLAYER_LOGIN" then
        if bagUpgradeLoginFired then return end
        bagUpgradeLoginFired = true

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
        -- Hook group loot roll frames (GroupLootFrame1-4)
        for i = 1, 4 do
            local glf = _G["GroupLootFrame"..i]
            if glf then
                glf:HookScript("OnShow", UpdateGroupLootFrame)
            end
        end
        return
    end

    -- UNIT_INVENTORY_CHANGED fires for all units; only care about the player
    if event == "UNIT_INVENTORY_CHANGED" and arg1 ~= "player" then return end

    local isGearEvent = (event == "PLAYER_EQUIPMENT_CHANGED" or event == "UNIT_INVENTORY_CHANGED")
    ScheduleScan(0.3, isGearEvent)
end

API.RegisterEvent("BagUpgrade", "PLAYER_LOGIN",             function(...) OnBagUpgradeEvent("PLAYER_LOGIN", ...) end)
API.RegisterEvent("BagUpgrade", "PLAYER_EQUIPMENT_CHANGED", function(...) OnBagUpgradeEvent("PLAYER_EQUIPMENT_CHANGED", ...) end)
API.RegisterEvent("BagUpgrade", "UNIT_INVENTORY_CHANGED",   function(...) OnBagUpgradeEvent("UNIT_INVENTORY_CHANGED", ...) end)
API.RegisterEvent("BagUpgrade", "BAG_UPDATE_DELAYED",       function(...) OnBagUpgradeEvent("BAG_UPDATE_DELAYED", ...) end)

-- Expose IsUpgrade for other modules (e.g. SellConfirm delete/sell warnings)
API.IsUpgrade = IsUpgrade

API.BagUpgradeScan = function()
    ScanAllVisibleBags()
end

API.Debug("[RogUI] BagUpgrade loaded.")
