-- ============================================================
-- MidnightQoL_QoL / SellConfirm.lua
-- Warns before selling an item that belongs to a Blizzard-
-- defined armor/tier set (e.g. class tier sets).
--
-- WoW does not allow addons to block protected functions like
-- UseContainerItem. Instead we hook MERCHANT_SELL_ITEM which
-- fires after the sale, detect set items, and immediately
-- offer to buy the item back via BuybackItem(1) if the player
-- cancels. This is the same pattern used by other "sell
-- protection" addons.
-- ============================================================

local API = MidnightQoLAPI

-- ── DB helper ─────────────────────────────────────────────────────────────────
local function IsEnabled()
    if not BuffAlertDB then return false end
    if BuffAlertDB.sellConfirmEnabled == nil then return false end
    return BuffAlertDB.sellConfirmEnabled
end

-- ── Set detection ─────────────────────────────────────────────────────────────
-- GetItemSetInfo(itemID) → setID, setName, numItems, numEquipped
-- Returns a set name if this item belongs to a Blizzard named armor set.
local function GetSetName(itemLink)
    if not itemLink then return nil end
    local itemID = tonumber(itemLink:match("item:(%d+)"))
    if not itemID then return nil end
    local ok, setID, setName = pcall(GetItemSetInfo, itemID)
    if ok and setID and setName and setName ~= "" then
        return setName
    end
    return nil
end

-- ── StaticPopup: "you just sold a set item, buy it back?" ────────────────────
StaticPopupDialogs["MQOL_SOLD_SET_ITEM"] = {
    text         = "You sold |cFFFFD700%s|r which is part of the |cFFFF6600%s|r set.\n\nBuy it back?",
    button1      = "Buy Back",
    button2      = "Keep Sold",
    OnAccept     = function(self, data)
        -- BuybackItem(index) — slot 1 is always the most recently sold item
        BuybackItem(1)
    end,
    OnCancel     = function() end,
    timeout      = 0,
    whileDead    = false,
    hideOnEscape = true,
    preferredIndex = 3,
}

-- ── Hook MERCHANT_SELL_ITEM event ─────────────────────────────────────────────
-- This fires after an item is sold. We check if it was a set piece and if so
-- immediately prompt the player to buy it back.
local sellFrame = CreateFrame("Frame")
sellFrame:RegisterEvent("MERCHANT_UPDATE")
sellFrame:SetScript("OnEvent", function(self, event)
    if not IsEnabled() then return end

    -- GetBuybackItemLink(index) — index 1 is the most recently sold item
    local numBuyback = GetNumBuybackItems and GetNumBuybackItems() or 0
    if numBuyback == 0 then return end
    local link = GetBuybackItemLink(1)
    if not link then return end

    local setName = GetSetName(link)
    if not setName then return end

    local itemName = GetItemInfo(link) or "this item"
    StaticPopup_Show("MQOL_SOLD_SET_ITEM", itemName, setName)
end)

API.Debug("[MidnightQoL] SellConfirm loaded.")
