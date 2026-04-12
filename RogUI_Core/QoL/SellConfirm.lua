-- ============================================================
-- RogUI_QoL / SellConfirm.lua
-- Warns before selling OR deleting an item that:
--   • Belongs to a Blizzard armor/tier set  (GetItemSetInfo)
--   • Belongs to a player equipment set     (C_EquipmentSet)
--   • Is an ilvl upgrade over equipped gear (API.IsUpgrade,
--     provided by RogUI_Bags — gracefully skipped if
--     that addon is not loaded)
--
-- StaticPopup_Show(name, text1, text2, data):
--   text1 → first  %s in the popup text
--   text2 → second %s in the popup text
--   data  → passed as first arg to OnAccept / OnCancel
-- We pre-format all variable parts into text1 (item name +
-- reason line) and use a single generic sell/delete popup each.
-- ============================================================

local API = RogUIAPI

-- ── DB helper ─────────────────────────────────────────────────────────────────
local function IsEnabled()
    if not RogUIDB then return false end
    if RogUIDB.sellConfirmEnabled == nil then return false end
    return RogUIDB.sellConfirmEnabled
end

-- ── Equipment-set cache (player-defined gear sets) ────────────────────────────
local eqSetCache = {}
local eqSetDirty = true

local function RebuildEqSetCache()
    wipe(eqSetCache)
    eqSetDirty = false
    if not C_EquipmentSet then return end
    for _, setID in ipairs(C_EquipmentSet.GetEquipmentSetIDs()) do
        local setName = C_EquipmentSet.GetEquipmentSetInfo(setID)
        if setName then
            for _, locationID in pairs(C_EquipmentSet.GetItemLocations(setID) or {}) do
                if locationID ~= -1 and locationID ~= 0 and locationID ~= 1 then
                    local player, bank, bags, slot, bag
                    if EquipmentManager_GetLocationData then
                        local d = EquipmentManager_GetLocationData(locationID)
                        player, bank, bags, slot, bag = d.isPlayer, d.isBank, d.isBags, d.slot, d.bag
                    else
                        player, bank, bags, _, slot, bag = EquipmentManager_UnpackLocation(locationID)
                    end
                    local location
                    if (player or bank) and bags then
                        location = ItemLocation:CreateFromBagAndSlot(bag, slot)
                    elseif player and not bags then
                        location = ItemLocation:CreateFromEquipmentSlot(slot)
                    end
                    if location and C_Item.DoesItemExist(location) then
                        local guid = C_Item.GetItemGUID(location)
                        if guid then
                            if not eqSetCache[guid] then eqSetCache[guid] = {} end
                            table.insert(eqSetCache[guid], setName)
                        end
                    end
                end
            end
        end
    end
end

local cacheFrame = CreateFrame("Frame")
cacheFrame:RegisterEvent("PLAYER_LOGIN")
cacheFrame:RegisterEvent("EQUIPMENT_SETS_CHANGED")
cacheFrame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        self:UnregisterEvent("PLAYER_LOGIN")
        RebuildEqSetCache()
    else
        eqSetDirty = true
    end
end)

-- ── Set detection ─────────────────────────────────────────────────────────────
local function GetSetName(itemLink)
    if not itemLink then return nil end

    -- 1) Blizzard armor/tier set
    local itemID = tonumber(itemLink:match("item:(%d+)"))
    if itemID then
        local ok, setID, setName = pcall(GetItemSetInfo, itemID)
        if ok and setID and setName and setName ~= "" then
            return setName
        end
    end

    -- 2) Player equipment set — search bags for a GUID match
    if eqSetDirty then RebuildEqSetCache() end
    local NUM_BAGS = NUM_TOTAL_BAG_FRAMES or 5
    for bag = 0, NUM_BAGS - 1 do
        local numSlots = C_Container and C_Container.GetContainerNumSlots(bag)
                      or (GetContainerNumSlots and GetContainerNumSlots(bag)) or 0
        for slot = 1, numSlots do
            local info = C_Container and C_Container.GetContainerItemInfo(bag, slot)
            if info and info.hyperlink == itemLink then
                local location = ItemLocation:CreateFromBagAndSlot(bag, slot)
                if location and C_Item.DoesItemExist(location) then
                    local guid = C_Item.GetItemGUID(location)
                    if guid and eqSetCache[guid] and #eqSetCache[guid] > 0 then
                        return table.concat(eqSetCache[guid], ", ")
                    end
                end
            end
        end
    end

    return nil
end

-- ── Build reason lines for the warning popup ──────────────────────────────────
-- Returns a multi-line reason string, or nil if no warning is needed.
local function BuildReasonLines(itemLink)
    local lines = {}

    local setName = GetSetName(itemLink)
    if setName then
        table.insert(lines, "|cFFFF6600Set piece:|r " .. setName)
    end

    if API.IsUpgrade then
        local isUpgrade, itemIlvl, equippedIlvl = API.IsUpgrade(itemLink)
        if isUpgrade then
            local delta = itemIlvl - equippedIlvl
            if delta > 0 then
                table.insert(lines, "|cFF00FF00ilvl upgrade:|r +" .. delta
                    .. " (" .. equippedIlvl .. " → " .. itemIlvl .. ")")
            else
                table.insert(lines, "|cFF00FF00ilvl upgrade:|r replaces unequipped slot")
            end
        end
    end

    if #lines == 0 then return nil end
    return table.concat(lines, "\n")
end

-- ── Generic sell warning popup ────────────────────────────────────────────────
-- text1 = item name (coloured link), text2 = reason lines
StaticPopupDialogs["MQOL_SOLD_WARN"] = {
    text         = "You sold |cFFFFD700%s|r\n\n%s\n\nBuy it back?",
    button1      = "Buy Back",
    button2      = "Keep Sold",
    OnAccept     = function() BuybackItem(1) end,
    OnCancel     = function() end,
    timeout      = 0,
    whileDead    = false,
    hideOnEscape = true,
    preferredIndex = 3,
}

-- ── Generic delete warning popup ─────────────────────────────────────────────
-- text1 = item name, text2 = reason lines
-- data  = { bagID, slotID } to re-fire the delete on confirm
StaticPopupDialogs["MQOL_DELETE_WARN"] = {
    text         = "|cFFFF4444Warning — about to delete:|r |cFFFFD700%s|r\n\n%s\n\nDelete it anyway?",
    button1      = "Delete",
    button2      = "Cancel",
    OnAccept     = function(self, data)
        if data and data.bagID and data.slotID then
            C_Container.PickupContainerItem(data.bagID, data.slotID)
            DeleteCursorItem()
        end
    end,
    OnCancel     = function() end,
    timeout      = 0,
    whileDead    = false,
    hideOnEscape = true,
    preferredIndex = 3,
}

-- ── Sell protection ───────────────────────────────────────────────────────────
local sellFrame = CreateFrame("Frame")
sellFrame:RegisterEvent("MERCHANT_UPDATE")
sellFrame:SetScript("OnEvent", function()
    if not IsEnabled() then return end

    local numBuyback = GetNumBuybackItems and GetNumBuybackItems() or 0
    if numBuyback == 0 then return end
    local link = GetBuybackItemLink(1)
    if not link then return end

    local reasons = BuildReasonLines(link)
    if not reasons then return end

    local itemName = GetItemInfo(link) or "this item"
    StaticPopup_Show("MQOL_SOLD_WARN", itemName, reasons)
end)

-- ── Delete protection ─────────────────────────────────────────────────────────
local pendingDeleteBag, pendingDeleteSlot, pendingDeleteLink

local pickupFrame = CreateFrame("Frame")
pickupFrame:RegisterEvent("CURSOR_CHANGED")
pickupFrame:SetScript("OnEvent", function()
    -- GetCursorInfo() returns:
    --   "bag_item", bagID, slotID  — when holding an item from a bag slot
    --   "item", itemID, itemLink   — when holding an item from elsewhere (equip flyout, etc.)
    -- We only care about bag items because those are the ones that can be deleted.
    local infoType, bagID, slotID = GetCursorInfo()
    if infoType == "bag_item" and type(bagID) == "number" and type(slotID) == "number" then
        pendingDeleteBag  = bagID
        pendingDeleteSlot = slotID
        local info = C_Container and C_Container.GetContainerItemInfo(bagID, slotID)
        pendingDeleteLink = info and info.hyperlink or nil
    else
        pendingDeleteBag  = nil
        pendingDeleteSlot = nil
        pendingDeleteLink = nil
    end
end)

local function HookDeletePopup(popupName)
    local orig = StaticPopupDialogs[popupName]
    if not orig then return end

    local origOnAccept = orig.OnAccept
    orig.OnAccept = function(self, data, data2)
        if not IsEnabled() then
            if origOnAccept then origOnAccept(self, data, data2) end
            return
        end

        local link = pendingDeleteLink or self.itemLink or nil
        local reasons = link and BuildReasonLines(link)

        if not reasons then
            if origOnAccept then origOnAccept(self, data, data2) end
            return
        end

        StaticPopup_Hide(popupName)

        local itemName = (link and GetItemInfo(link)) or "this item"
        local deleteData = { bagID = pendingDeleteBag, slotID = pendingDeleteSlot }

        pendingDeleteBag  = nil
        pendingDeleteSlot = nil
        pendingDeleteLink = nil

        StaticPopup_Show("MQOL_DELETE_WARN", itemName, reasons, deleteData)
    end
end

local hookFrame = CreateFrame("Frame")
hookFrame:RegisterEvent("ADDON_LOADED")
hookFrame:SetScript("OnEvent", function(self, event, addonName)
    if addonName ~= "RogUI_Core" then return end
    self:UnregisterEvent("ADDON_LOADED")
    HookDeletePopup("DELETE_ITEM")
    HookDeletePopup("DELETE_GOOD_ITEM")
end)

API.Debug("[RogUI] SellConfirm loaded.")
