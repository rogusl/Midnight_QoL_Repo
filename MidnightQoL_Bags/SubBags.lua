-- ============================================================
-- MidnightQoL_QoL / SubBags.lua
--
-- Custom bag panel with collapsible named sections.
-- Layout approach mirrors Baganator's CategoryViews:
--   • Each filter = a collapsible section header + item row(s)
--   • An "Other" section catches everything that doesn't match
--   • Items use the "ItemButton" frame type (no XML template)
--   • Live bag data, updates on BAG_UPDATE_DELAYED
--
-- /mqb  or  /mqbags  — toggle the panel
-- Settings tab in MidnightQoL panel → Bags
-- ============================================================

local API = MidnightQoLAPI

-- ── DB ────────────────────────────────────────────────────────────────────────
local function DB()
    if not BuffAlertDB then return nil end
    if BuffAlertDB.subBags             == nil then BuffAlertDB.subBags             = {} end
    if BuffAlertDB.subBagIlvlEnabled   == nil then BuffAlertDB.subBagIlvlEnabled   = true end
    if BuffAlertDB.subBagIconSize      == nil then BuffAlertDB.subBagIconSize      = 37 end
    if BuffAlertDB.subBagCollapsed     == nil then BuffAlertDB.subBagCollapsed     = {} end
    if BuffAlertDB.subBagHideSoulbound == nil then BuffAlertDB.subBagHideSoulbound = false end
    if BuffAlertDB.subBagHideWarbound   == nil then BuffAlertDB.subBagHideWarbound   = false end
    if BuffAlertDB.subBagShowBoundOnly  == nil then BuffAlertDB.subBagShowBoundOnly  = false end
    if BuffAlertDB.bagUpgradeEnabled   == nil then BuffAlertDB.bagUpgradeEnabled   = true end
    return BuffAlertDB
end

local function NewID()
    return "sb_"..math.floor(GetTime()*1000).."_"..math.random(1000,9999)
end

-- ── Bag IDs ───────────────────────────────────────────────────────────────────
local function GetAllBagIDs()
    local t={0,1,2,3,4}
    if Enum and Enum.BagIndex and Enum.BagIndex.ReagentBag then
        table.insert(t,Enum.BagIndex.ReagentBag)
    end
    return t
end

-- ── Quality colours ────────────────────────────────────────────────────────────
local QCOLOR={
    [0]={0.62,0.62,0.62},[1]={1,1,1},
    [2]={0.12,0.70,0.00},[3]={0.00,0.44,0.87},
    [4]={0.64,0.21,0.93},[5]={0.88,0.38,0.00},
    [6]={0.90,0.80,0.50},[7]={0.31,0.77,0.88},
}

-- ── Section accent colours ────────────────────────────────────────────────────
local ACCENT={
    {1.00,0.40,0.33},{0.33,0.67,1.00},{0.33,0.87,0.33},
    {1.00,0.80,0.27},{0.80,0.33,1.00},{0.27,0.87,0.80},
    {1.00,0.53,0.20},{0.67,0.67,1.00},
}
local function Accent(i) local c=ACCENT[((i-1)%#ACCENT)+1]; return c[1],c[2],c[3] end

-- ════════════════════════════════════════════════════════════════════════════════
-- FILTER ENGINE  (same as before)
-- ════════════════════════════════════════════════════════════════════════════════
local ITEM_CLASS_IDS={
    armor        = Enum.ItemClass.Armor,
    weapon       = Enum.ItemClass.Weapon,
    consumable   = Enum.ItemClass.Consumable,
    -- Reagent covers raw crafting mats (Midnight/TWW)
    reagent      = Enum.ItemClass.Reagent,
    -- Tradeskill / Tradegoods are both used depending on expansion
    tradeskill   = Enum.ItemClass.Tradeskill,
    tradegood    = Enum.ItemClass.Tradegoods or Enum.ItemClass.Tradeskill,
    tradegoods   = Enum.ItemClass.Tradegoods or Enum.ItemClass.Tradeskill,
    container    = Enum.ItemClass.Container,
    questitem    = Enum.ItemClass.Questitem,
    recipe       = Enum.ItemClass.Recipe,
    miscellaneous= Enum.ItemClass.Miscellaneous,
    gem          = Enum.ItemClass.Gem,
    enhancement  = Enum.ItemClass.ItemEnhancement,
    profession   = Enum.ItemClass.Profession,
}

-- For #reagent we want to catch ALL crafting-material classes at once
local REAGENT_CLASSES = {}
do
    local function add(c) if c then REAGENT_CLASSES[c]=true end end
    add(Enum.ItemClass.Reagent)
    add(Enum.ItemClass.Tradeskill)
    add(Enum.ItemClass.Tradegoods)
    add(Enum.ItemClass.ItemEnhancement)
    add(Enum.ItemClass.Gem)
end

local function IsGear(link)
    if not link then return false end
    local ok,c=pcall(function() return select(6,C_Item.GetItemInfoInstant(link)) end)
    return ok and(c==Enum.ItemClass.Armor or c==Enum.ItemClass.Weapon or c==Enum.ItemClass.Profession)
end

local function GetIlvl(link)
    local ok,v=pcall(C_Item.GetDetailedItemLevelInfo,link)
    if ok and v and v>0 then return v end
    local _,_,_,il=GetItemInfo(link); return il or 0
end

local function TokenMatches(token,link,name,quality)
    if token:sub(1,1)=="#" then
        local kw=token:sub(2):lower()
        -- #reagent catches all crafting-material item classes
        if kw=="reagent" or kw=="reagents" then
            local ok,c=pcall(function() return select(6,C_Item.GetItemInfoInstant(link)) end)
            return ok and REAGENT_CLASSES[c]==true
        end
        local wc=ITEM_CLASS_IDS[kw]
        if wc then
            local ok,c=pcall(function() return select(6,C_Item.GetItemInfoInstant(link)) end)
            return ok and c==wc
        end
        -- fallback: subclass name match
        local _,_,_,_,_,_,sub=GetItemInfo(link)
        return sub and sub:lower():find(kw,1,true)~=nil
    elseif token:sub(1,1)=="^" then
        local f=token:sub(2):lower()
        if f=="junk"     then return quality==0 end
        if f=="epic"     then return quality==4 end
        if f=="rare"     then return quality==3 end
        if f=="uncommon" then return quality==2 end
        if f=="common"   then return quality==1 end
        if f=="boe"      then return IsGear(link) and quality and quality>=2 end
        if f=="gear"     then return IsGear(link) end
        if f=="inset" or f=="equipset" or f=="gearset" then
            -- This will be handled in PassesFilter with setNames
            return false
        end
        return false
    elseif token:find("^ilvl[<>=!]+%d+$") then
        local op,vs=token:match("^ilvl([<>=!]+)(%d+)$")
        local thr=tonumber(vs); if not thr then return false end
        local il=GetIlvl(link)
        if op==">"  then return il> thr end
        if op==">=" then return il>=thr end
        if op=="<"  then return il< thr end
        if op=="<=" then return il<=thr end
        if op=="="  then return il==thr end
        return false
    else
        return name and name:lower():find(token,1,true)~=nil
    end
end

local function PassesFilter(link,name,quality,filterStr,setNames,isBound)
    if not filterStr or filterStr=="" then return true end
    for seg in (filterStr:lower().."|"):gmatch("([^|]*)|") do
        seg=seg:match("^%s*(.-)%s*$")
        if seg~="" then
            local ok=true
            for tok in (seg.."&"):gmatch("([^&]*)&") do
                tok=tok:match("^%s*(.-)%s*$")
                if tok~="" then
                    -- Special handling for gear set filter
                    if tok=="^inset" or tok=="^equipset" or tok=="^gearset" then
                        if not (setNames and #setNames>0) then ok=false; break end
                    elseif not TokenMatches(tok,link,name,quality) then
                        ok=false; break
                    end
                end
            end
            if ok then return true end
        end
    end
    return false
end

-- ════════════════════════════════════════════════════════════════════════════════
-- EQUIPMENT SET CACHE
-- Maps item GUID -> array of set names the item belongs to.
-- Rebuilt on EQUIPMENT_SETS_CHANGED and PLAYER_LOGIN.
-- ════════════════════════════════════════════════════════════════════════════════
local eqSetCache = {}   -- [guid] = {setName, ...}
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

-- ════════════════════════════════════════════════════════════════════════════════
-- ITEM CACHE
-- ════════════════════════════════════════════════════════════════════════════════
-- Upgrade cache - pre-calculated outside protected contexts
local upgradeCache = {}

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
}

local function GetEquippedIlvl(invSlotID)
    local link = GetInventoryItemLink("player", invSlotID)
    if not link then return 0 end
    local ok, ilvl = pcall(C_Item.GetDetailedItemLevelInfo, link)
    if ok and ilvl and ilvl > 0 then return ilvl end
    local _, _, _, itemLevel = GetItemInfo(link)
    return itemLevel or 0
end

local function CalculateUpgrade(link)
    if not link then return false, 0 end
    local _, _, _, _, _, _, _, _, invType = GetItemInfo(link)
    if not invType or invType == "" or invType == "INVTYPE_NON_EQUIP" then
        return false, 0
    end
    local slots = INVTYPE_TO_SLOTS[invType]
    if not slots then return false, 0 end

    local bagIlvl = GetIlvl(link)
    if bagIlvl <= 0 then return false, 0 end

    -- Find the lowest ilvl in the slots this item could fill.
    -- If nothing is equipped we treat it as an upgrade (delta = bagIlvl).
    local lowestEquipped = math.huge
    local anyEquipped = false
    for _, slID in ipairs(slots) do
        local eq = GetEquippedIlvl(slID)
        if eq > 0 then
            anyEquipped = true
            lowestEquipped = math.min(lowestEquipped, eq)
        end
    end

    if not anyEquipped then
        -- Nothing equipped in this slot — always an upgrade
        return true, bagIlvl
    end

    local delta = bagIlvl - lowestEquipped
    return delta > 0, delta
end

local itemCache={}

-- ── Warbound detection via tooltip scan ───────────────────────────────────────
-- WoW Midnight does not expose warbound status through any bag/item API field.
-- The only reliable method is scanning the item tooltip for the "Warband" bind line,
-- which is the same approach used by other bag addons (Baggins, ArkInventory, etc.)
-- We use a hidden off-screen tooltip so there's no visual flicker.
local warboundScanner
local function GetWarboundScanner()
    if warboundScanner then return warboundScanner end
    warboundScanner = CreateFrame("GameTooltip", "MQBWarboundScanner", nil, "GameTooltipTemplate")
    warboundScanner:SetOwner(WorldFrame, "ANCHOR_NONE")
    return warboundScanner
end

-- Returns true if the item at bagID,slotID is warbound.
-- Scans tooltip lines 1-4 (bind type is always in the first few lines).
local function IsWarboundItem(bagID, slotID)
    local scanner = GetWarboundScanner()
    scanner:ClearLines()
    scanner:SetBagItem(bagID, slotID)
    for i = 1, math.min(4, scanner:NumLines()) do
        local line = _G["MQBWarboundScannerTextLeft"..i]
        if line then
            local t = line:GetText()
            if t and (t:find("Warband") or t:find("warband") or t:find("Account")) then
                return true
            end
        end
    end
    return false
end


local function RebuildItemCache()
    wipe(itemCache)
    if eqSetDirty then RebuildEqSetCache() end
    for _,bagID in ipairs(GetAllBagIDs()) do
        local n=C_Container.GetContainerNumSlots(bagID)
        for slotID=1,n do
            local info=C_Container.GetContainerItemInfo(bagID,slotID)
            if info and info.hyperlink then
                local name=GetItemInfo(info.hyperlink) or ""
                -- equipment set membership
                local loc=ItemLocation:CreateFromBagAndSlot(bagID,slotID)
                local setNames=nil
                if loc and C_Item.DoesItemExist(loc) then
                    local guid=C_Item.GetItemGUID(loc)
                    setNames=guid and eqSetCache[guid] or nil
                end

                -- Calculate upgrade status NOW (safe time, not during layout)
                local isUpgrade, delta = false, 0
                if DB() and DB().bagUpgradeEnabled and IsGear(info.hyperlink) then
                    isUpgrade, delta = CalculateUpgrade(info.hyperlink)
                end

                -- Bound status: isBound covers soulbound items reliably.
                -- Warbound has no API field in this version of WoW — scan the tooltip instead.
                local isBound    = info.isBound or false
                local isWarbound = false
                if isBound then
                    -- Warbound items report isBound=true but show a "Warband" line in the tooltip.
                    -- If detected as warbound, flip isBound off so soulbound filter doesn't match it.
                    isWarbound = IsWarboundItem(bagID, slotID)
                    if isWarbound then isBound = false end
                end

                table.insert(itemCache,{
                    bagID=bagID, slotID=slotID, link=info.hyperlink,
                    name=name, quality=info.quality or 1,
                    icon=info.iconFileID, count=info.stackCount or 1,
                    setNames=setNames, isBound=isBound,
                    isWarbound=isWarbound,
                    isUpgrade=isUpgrade, upgradeDelta=delta,
                    isNew=info.isNew or false,
                })
            end
        end
    end
end

-- ════════════════════════════════════════════════════════════════════════════════
-- PANEL
-- ════════════════════════════════════════════════════════════════════════════════
local panel
local ICON_SZ  = 37
local ICON_PAD = 3
local HEADER_H = 20
local HEADER_PAD = 4   -- gap between header and icons below it
local SECTION_GAP = 10 -- gap between sections

-- ItemButton pool — one flat pool, sections just position them
local btnPool   = {}
local btnPoolSz = 0

local liveSearch = ""

local function GetOrCreateBtn()
    btnPoolSz = btnPoolSz+1
    if btnPool[btnPoolSz] then return btnPool[btnPoolSz] end

    -- Templates.xml inherits ContainerFrameItemButtonTemplate, which carries
    -- Blizzard's SECURE click handler.  We must never set OnClick, OnDoubleClick,
    -- or RegisterForClicks ourselves — doing so taints the frame and causes
    -- ADDON_ACTION_FORBIDDEN.
    --
    -- The secure handler resolves bag+slot by reading:
    --   btn:GetID()            → slotID
    --   btn:GetParent():GetID() → bagID
    -- So each button MUST be parented to a frame whose GetID() returns the
    -- correct bagID, and btn:SetID(slotID) must be set before any click.
    -- See LayoutPanel below where we enforce this contract.
    local btn = CreateFrame("ItemButton", nil, panel.canvas, "MidnightQoLItemButtonTemplate")

    -- Nil the template's OnEvent and OnShow — these are what re-trigger
    -- NewItemTexture on every bag event/show, causing everything to glow.
    btn:SetScript("OnEvent", nil)
    btn:SetScript("OnShow", nil)
    if btn.NewItemTexture then btn.NewItemTexture:Hide() end
    if btn.newitemglowAnim then btn.newitemglowAnim:Stop() end
    if btn.BattlepayItemTexture then btn.BattlepayItemTexture:Hide() end

    -- Slot background overlay (custom styling)
    local bg = btn:CreateTexture(nil, "BACKGROUND", nil, -1)
    bg:SetAllPoints(btn.icon or btn)
    bg:SetAtlas("bags-item-slot64")
    btn.SlotBg = bg

    -- ilvl label (bottom-left)
    local ilvlTxt = btn:CreateFontString(nil, "OVERLAY")
    ilvlTxt:SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE")
    ilvlTxt:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 2, 2)
    btn.ilvlTxt = ilvlTxt

    -- Tooltip: HookScript so we append set names without replacing the
    -- secure template's own OnEnter (which handles the native item tooltip).
    btn:HookScript("OnEnter", function(self)
        if self.setNames and #self.setNames > 0 then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Equipment Sets:", 0.4, 0.8, 1)
            for _, sn in ipairs(self.setNames) do
                GameTooltip:AddLine("  " .. sn, 1, 0.82, 0)
            end
            GameTooltip:Show()
        end
    end)

    -- Gear set badge (top-right corner shield icon)
    local setBadge=btn:CreateTexture(nil,"OVERLAY")
    setBadge:SetSize(14,14)
    setBadge:SetPoint("TOPRIGHT",btn,"TOPRIGHT",-1,-1)
    setBadge:SetTexture("Interface\\EquipmentManager\\UI-EquipmentManager-Icon")
    setBadge:SetTexCoord(0,0.5,0,0.5)
    setBadge:Hide()
    btn.setBadge=setBadge

    -- Upgrade badge: lives in its own child Frame at a frame level above ALL of
    -- ContainerFrameItemButtonTemplate's children (cooldown, border, glow etc.)
    -- so nothing the template renders can cover it.
    -- Upgrade indicator: simple green arrow, no frame child needed
    local upgradeArrow = btn:CreateTexture(nil, "OVERLAY", nil, 7)
    upgradeArrow:SetSize(14, 14)
    upgradeArrow:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 2, 2)
    upgradeArrow:SetTexture("Interface\\Buttons\\UI-MicroStream-Green")
    upgradeArrow:SetVertexColor(0.2, 1, 0.3, 1)
    upgradeArrow:SetRotation(math.pi)  -- rotate 180deg so it points up
    upgradeArrow:Hide()
    btn.upgradeArrow = upgradeArrow



    btnPool[btnPoolSz]=btn; return btn
end

-- ReorderSection must be defined before GetOrCreateHeader so the settings
-- row buttons (added in RebuildSubBagRows) can reference it directly.
local function ReorderSection(sectionIndex, direction)
    if not DB() or not DB().subBags then return end
    local sections = DB().subBags
    local newIndex = sectionIndex + direction
    if newIndex >= 1 and newIndex <= #sections then
        sections[sectionIndex], sections[newIndex] = sections[newIndex], sections[sectionIndex]
        RebuildItemCache()
        LayoutPanel()
    end
end

-- ── Section header pool ───────────────────────────────────────────────────────
local hdrPool   = {}
local hdrPoolSz = 0

local function GetOrCreateHeader()
    hdrPoolSz=hdrPoolSz+1
    if hdrPool[hdrPoolSz] then return hdrPool[hdrPoolSz] end

    local hdr=CreateFrame("Button",nil,panel.canvas,"BackdropTemplate")
    hdr:SetHeight(HEADER_H)
    hdr:RegisterForClicks("AnyUp")

    -- Collapse arrow (same atlas Baganator uses)
    local arrow=hdr:CreateTexture(nil,"ARTWORK")
    arrow:SetSize(12,12); arrow:SetAtlas("bag-arrow")
    arrow:SetPoint("LEFT",hdr,"LEFT",2,0)
    hdr.arrow=arrow

    -- Colour bar on left edge
    local bar=hdr:CreateTexture(nil,"BACKGROUND")
    bar:SetWidth(3); bar:SetPoint("TOPLEFT",0,0); bar:SetPoint("BOTTOMLEFT",0,0)
    hdr.bar=bar

    -- Count badge (right side)
    local cnt=hdr:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    cnt:SetPoint("RIGHT",hdr,"RIGHT",-4,0)
    cnt:SetTextColor(0.6,0.7,0.9)
    hdr.cnt=cnt

    -- Label (stretches between arrow and count badge)
    local lbl=hdr:CreateFontString(nil,"OVERLAY","GameFontNormalMed2")
    lbl:SetPoint("LEFT",arrow,"RIGHT",4,0)
    lbl:SetPoint("RIGHT",cnt,"LEFT",-4,0)
    lbl:SetJustifyH("LEFT")
    hdr.lbl=lbl

    -- Subtle background
    hdr:SetBackdrop({bgFile="Interface/Tooltips/UI-Tooltip-Background"})
    hdr:SetBackdropColor(0.10,0.10,0.16,0.7)

    hdr:SetScript("OnClick",function(self)
        local db=DB(); if not db then return end
        if self.mergedKeys then
            -- Toggle all component keys together
            -- If any are uncollapsed, collapse all; otherwise expand all
            local anyOpen = false
            for _, k in ipairs(self.mergedKeys) do
                if not db.subBagCollapsed[k] then anyOpen = true; break end
            end
            for _, k in ipairs(self.mergedKeys) do
                db.subBagCollapsed[k] = anyOpen
            end
            self.arrow:SetRotation(anyOpen and -math.pi or math.pi/2)
        else
            local key=self.sectionKey
            db.subBagCollapsed[key]=not db.subBagCollapsed[key]
            self.arrow:SetRotation(db.subBagCollapsed[key] and -math.pi or math.pi/2)
        end
        LayoutPanel()
    end)
    hdr:SetScript("OnEnter",function(self)
        self:SetBackdropColor(0.18,0.18,0.28,0.8)
    end)
    hdr:SetScript("OnLeave",function(self)
        self:SetBackdropColor(0.10,0.10,0.16,0.7)
    end)

    hdrPool[hdrPoolSz]=hdr; return hdr
end

-- ── Core layout ───────────────────────────────────────────────────────────────
-- Mirrors Baganator's Pack logic:
--   • For each section: draw header, then flow items into rows of COLS
--   • Collapsed sections: hide items, show count in header
--   • An implicit "Other" section at the end for unmatched items

local COLS -- computed from panel width and icon size

-- Forward declaration — defined after BuildPanel which creates the label refs
local UpdateBottomBar

function LayoutPanel()
    if not panel or not panel:IsShown() then return end
    if not DB() then return end

    local sz=DB().subBagIconSize or 37
    ICON_SZ=sz
    local panelInner=panel:GetWidth()-32  -- account for scroll bar + padding
    COLS=math.max(1,math.floor((panelInner+ICON_PAD)/(ICON_SZ+ICON_PAD)))

    -- Hide all pooled objects first (with nil checks for safety)
    for i=1,#btnPool do if btnPool[i] then btnPool[i]:Hide() end end
    for i=1,#hdrPool do if hdrPool[i] then hdrPool[i]:Hide() end end
    btnPoolSz=0; hdrPoolSz=0

    local subBags=DB().subBags or {}
    local collapsed=DB().subBagCollapsed or {}

    -- Partition itemCache into sections
    -- Items are matched to the FIRST section whose filter they pass.
    -- Remaining items go into "Other".
    local sections={}  -- array of {name, key, r,g,b, items={}}
    for i,sb in ipairs(subBags) do
        local r,g,b=Accent(i)
        table.insert(sections,{name=sb.name or "Filter "..i, key=sb.id or tostring(i),
            filter=sb.search, r=r,g=g,b=b, items={}})
    end
    local otherItems={}

    local showBoundOnly = DB() and DB().subBagShowBoundOnly
    for _,item in ipairs(itemCache) do
        local isBoundOrWarbound = item.isBound or item.isWarbound
        -- "Show only bound/warbound": skip unbound items
        if showBoundOnly and not isBoundOrWarbound then
            -- skip
        else
            -- "Hide soulbound" / "Hide warbound" (ignored when showBoundOnly is active)
            local hideSB = not showBoundOnly and DB() and DB().subBagHideSoulbound and item.isBound
            local hideWB = not showBoundOnly and DB() and DB().subBagHideWarbound  and item.isWarbound
            if not (hideSB or hideWB) then
                -- apply live search
                if liveSearch=="" or item.name:lower():find(liveSearch,1,true) then
                    local matched=false
                    for _,sec in ipairs(sections) do
                        if PassesFilter(item.link,item.name,item.quality,sec.filter,item.setNames,item.isBound) then
                            table.insert(sec.items,item); matched=true; break
                        end
                    end
                    if not matched then table.insert(otherItems,item) end
                end
            end
        end
    end

    -- Add implicit "Other" section only if it has items
    if #otherItems>0 then
        table.insert(sections,{name="Other",key="__other",
            filter=nil,r=0.5,g=0.5,b=0.5,items=otherItems})
    end

    -- Merge adjacent sections whose combined item count fits in one row.
    -- We do a greedy left-to-right pass: keep accumulating consecutive sections
    -- until adding the next one would exceed COLS items, then emit a group.
    -- "Other" is never merged with anything.
    do
        local merged = {}
        local group = nil  -- current accumulator {names, keys, items, r,g,b}

        local function flushGroup()
            if group then
                if #group.sources == 1 then
                    -- single section — emit as-is
                    table.insert(merged, group.sources[1])
                else
                    -- multiple sections — emit a combined pseudo-section
                    local names, items = {}, {}
                    for _, s in ipairs(group.sources) do
                        table.insert(names, s.name)
                        for _, item in ipairs(s.items) do
                            table.insert(items, item)
                        end
                    end
                    -- Combine collapsed state: merged section is collapsed only
                    -- if ALL component sections are collapsed.
                    local combinedKey = table.concat(group.keys, "|")
                    table.insert(merged, {
                        name     = table.concat(names, " · "),
                        key      = combinedKey,
                        keys     = group.keys,   -- for collapse toggle
                        r=group.r, g=group.g, b=group.b,
                        items    = items,
                        isMerged = true,
                    })
                end
                group = nil
            end
        end

        for _, sec in ipairs(sections) do
            if #sec.items == 0 and sec.key ~= "__other" then
                -- empty non-Other section: skip entirely
            elseif sec.key == "__other" then
                flushGroup()
                table.insert(merged, sec)
            else
                local wouldFit = (group == nil and #sec.items <= COLS)
                              or (group ~= nil and (#group.items + #sec.items) <= COLS)
                if wouldFit then
                    if not group then
                        group = {sources={}, keys={}, items={}, r=sec.r, g=sec.g, b=sec.b}
                    end
                    table.insert(group.sources, sec)
                    table.insert(group.keys, sec.key)
                    for _, item in ipairs(sec.items) do
                        table.insert(group.items, item)
                    end
                else
                    flushGroup()
                    if #sec.items <= COLS then
                        -- start a new group with this section
                        group = {sources={sec}, keys={sec.key}, items={}, r=sec.r, g=sec.g, b=sec.b}
                        for _, item in ipairs(sec.items) do
                            table.insert(group.items, item)
                        end
                    else
                        -- too large to merge — emit directly
                        table.insert(merged, sec)
                    end
                end
            end
        end
        flushGroup()
        sections = merged
    end

    -- Now place everything onto panel.canvas
    local offsetY=0  -- grows downward (negative)
    local showIlvl=DB().subBagIlvlEnabled

    for _,sec in ipairs(sections) do
        if #sec.items>0 or sec.key=="__other" then

        -- Header
        local hdr=GetOrCreateHeader()
        hdr:ClearAllPoints()
        hdr:SetPoint("TOPLEFT",panel.canvas,"TOPLEFT",0,offsetY)
        hdr:SetPoint("TOPRIGHT",panel.canvas,"TOPRIGHT",0,offsetY)
        hdr:SetHeight(HEADER_H)
        hdr.sectionKey=sec.key
        hdr.sectionIndex=_  -- Store section index for reordering
        hdr.bar:SetColorTexture(sec.r,sec.g,sec.b,0.9)
        hdr.cnt:SetText(#sec.items)

        -- For merged sections, collapsed = ALL component keys are collapsed
        local isCollapsed
        if sec.isMerged then
            isCollapsed = true
            for _, k in ipairs(sec.keys) do
                if not collapsed[k] then isCollapsed = false; break end
            end
        else
            isCollapsed = collapsed[sec.key]
        end

        -- Store keys on header for the OnClick handler
        hdr.mergedKeys = sec.isMerged and sec.keys or nil

        if isCollapsed then
            hdr.arrow:SetRotation(-math.pi)
            hdr.lbl:SetText(sec.name.."  |cFFAAAAAA("..#sec.items..")|r")
            hdr.cnt:Hide()
        else
            hdr.arrow:SetRotation(math.pi/2)
            hdr.lbl:SetText(sec.name)
            hdr.cnt:Show()
        end
        hdr:Show()
        offsetY=offsetY-HEADER_H-HEADER_PAD

        -- Items (hidden if collapsed)
        if not isCollapsed then
            local col,row=0,0
            
            -- indexFrame acts as the bag-ID carrier for the secure template.
            -- ContainerFrameItemButtonTemplate reads btn:GetParent():GetID() for
            -- the bagID, so we parent each button to a tiny per-item frame whose
            -- ID is set to that item's bagID.  Items in the same section can come
            -- from different bags, so we need one indexFrame per button.
            for _,item in ipairs(sec.items) do
                local indexFrame = CreateFrame("Frame", nil, panel.canvas)
                indexFrame:SetID(item.bagID)
                -- indexFrame sits exactly where this slot goes in the grid.
                indexFrame:SetPoint("TOPLEFT", panel.canvas, "TOPLEFT",
                    col*(ICON_SZ+ICON_PAD), offsetY - row*(ICON_SZ+ICON_PAD))
                indexFrame:SetSize(ICON_SZ, ICON_SZ)
                indexFrame:Show()

                local btn=GetOrCreateBtn()

                -- SECURE TEMPLATE CONTRACT:
                -- ContainerFrameItemButtonTemplate's click handler reads:
                --   btn:GetID()             → slotID
                --   btn:GetParent():GetID() → bagID
                -- We honour this exactly; no OnClick in Lua touches these.
                btn:SetParent(indexFrame)
                btn:SetID(item.slotID)
                btn:SetSize(ICON_SZ, ICON_SZ)
                btn:ClearAllPoints()
                -- btn fills its indexFrame directly — no extra col/row offset here.
                btn:SetPoint("TOPLEFT", indexFrame, "TOPLEFT", 0, 0)

                -- Store extras for tooltip/badges only (NOT for click routing)
                btn.link=item.link
                btn.setNames=item.setNames
                
                -- Update the button using Blizzard's functions
                SetItemButtonTexture(btn, item.icon)
                SetItemButtonCount(btn, item.count)
                SetItemButtonQuality(btn, item.quality, item.link)

                -- Drive new-item glow using WoW's own API
                if btn.NewItemTexture then
                    local isNew = item.isNew
                    if isNew then
                        local atlas = (NEW_ITEM_ATLAS_BY_QUALITY and NEW_ITEM_ATLAS_BY_QUALITY[item.quality])
                                      or 'bags-glow-white'
                        btn.NewItemTexture:SetAtlas(atlas)
                        btn.NewItemTexture:Show()
                        if btn.newitemglowAnim then btn.newitemglowAnim:Play() end
                        if btn.flashAnim then btn.flashAnim:Play() end
                    else
                        btn.NewItemTexture:Hide()
                        if btn.newitemglowAnim then btn.newitemglowAnim:Stop() end
                        if btn.flashAnim then btn.flashAnim:Stop() end
                    end
                end

                -- Gear set badge
                if item.setNames and #item.setNames>0 then
                    btn.setBadge:Show()
                else
                    btn.setBadge:Hide()
                end

                -- Upgrade badge (use pre-calculated data from cache)
                if item.isUpgrade then
                    btn.upgradeArrow:Show()
                else
                    btn.upgradeArrow:Hide()
                end



                if showIlvl and IsGear(item.link) then
                    local il=GetIlvl(item.link)
                    if il and il>0 then
                        local qc=QCOLOR[item.quality] or QCOLOR[1]
                        btn.ilvlTxt:SetTextColor(qc[1],qc[2],qc[3])
                        btn.ilvlTxt:SetText(il); btn.ilvlTxt:Show()
                    else btn.ilvlTxt:Hide() end
                else btn.ilvlTxt:Hide() end

                btn:Show()
                col=col+1
                if col>=COLS then col=0; row=row+1 end
            end
            local rows=math.ceil(#sec.items/COLS)
            offsetY=offsetY - rows*(ICON_SZ+ICON_PAD)
        end

        offsetY=offsetY-SECTION_GAP
        end -- if #sec.items>0
    end

    -- Update canvas height for scroll (no extra gap at bottom)
    panel.canvas:SetHeight(math.max(-offsetY, ICON_SZ+ICON_PAD))

    -- Bottom bar
    UpdateBottomBar()
end

-- ── Panel construction ────────────────────────────────────────────────────────
local PANEL_W=480
local PANEL_H=620

UpdateBottomBar = function()
    if not panel then return end
    local money=GetMoney()
    local g=math.floor(money/10000)
    local s=math.floor((money%10000)/100)
    local c=money%100
    if panel.goldLbl then
        panel.goldLbl:SetText(
            (g>0 and (g.."|cFFFFD700g|r ") or "")..
            (s>0 and (s.."|cFFCCCCCCs|r ") or "")..
            c.."|cFFCC9933c|r")
    end
    local free,total=0,0
    for _,bagID in ipairs(GetAllBagIDs()) do
        local n=C_Container.GetContainerNumSlots(bagID); total=total+n
        for slotID=1,n do
            if not C_Container.GetContainerItemInfo(bagID,slotID) then free=free+1 end
        end
    end
    if panel.slotLbl then panel.slotLbl:SetText(free.."/"..total.." free") end
    if panel.countLbl then
        local shown=0; for i=1,btnPoolSz do if btnPool[i]:IsShown() then shown=shown+1 end end
        panel.countLbl:SetText(shown.." items")
    end
end

local function BuildPanel()
    if panel then return end

    panel=CreateFrame("Frame","MidnightQoLBagPanel",UIParent,"BackdropTemplate")
    panel:SetSize(PANEL_W,PANEL_H)
    -- Don't set position here - let OpenPanel restore it
    panel:SetMovable(true); panel:EnableMouse(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart",panel.StartMoving)
    panel:SetScript("OnDragStop",function(self)
        self:StopMovingOrSizing()
        if DB() then
            -- Save position as offset from center
            local centerX = UIParent:GetWidth() / 2
            local centerY = UIParent:GetHeight() / 2
            local panelCenterX = self:GetLeft() + self:GetWidth() / 2
            local panelCenterY = self:GetTop() - self:GetHeight() / 2
            local offsetX = panelCenterX - centerX
            local offsetY = panelCenterY - centerY
            DB().bagPanelPos = {offsetX, offsetY}
            DB().bagPanelSize = {self:GetWidth(), self:GetHeight()}
        end
    end)
    
    -- Resize handle (bottom-right corner)
    panel:SetResizable(true)
    local resizeHandle=CreateFrame("Frame",nil,panel)
    resizeHandle:SetSize(20,20); resizeHandle:SetPoint("BOTTOMRIGHT",-2,2)
    resizeHandle:EnableMouse(true)
    local resizeTex=resizeHandle:CreateTexture(nil,"OVERLAY")
    resizeTex:SetAllPoints(); resizeTex:SetAtlas("UI-ResizeHandle")
    resizeTex:SetColorTexture(0.3,0.55,1.0,0.5)
    resizeHandle:SetScript("OnMouseDown",function()
        panel:StartSizing("BOTTOMRIGHT")
    end)
    resizeHandle:SetScript("OnMouseUp",function()
        panel:StopMovingOrSizing()
        if DB() then
            -- Save position as offset from center
            local centerX = UIParent:GetWidth() / 2
            local centerY = UIParent:GetHeight() / 2
            local panelCenterX = panel:GetLeft() + panel:GetWidth() / 2
            local panelCenterY = panel:GetTop() - panel:GetHeight() / 2
            local offsetX = panelCenterX - centerX
            local offsetY = panelCenterY - centerY
            DB().bagPanelPos = {offsetX, offsetY}
            DB().bagPanelSize = {panel:GetWidth(), panel:GetHeight()}
        end
        LayoutPanel()
    end)
    resizeHandle:SetScript("OnEnter",function(self)
        self:SetAlpha(1.0)
    end)
    resizeHandle:SetScript("OnLeave",function(self)
        self:SetAlpha(0.3)
    end)
    resizeHandle:SetAlpha(0.3)
    
    panel:SetFrameStrata("HIGH"); panel:SetFrameLevel(50)
    panel:SetBackdrop({
        bgFile="Interface/Tooltips/UI-Tooltip-Background",
        edgeFile="Interface/Tooltips/UI-Tooltip-Border",
        tile=true,tileSize=16,edgeSize=16,
        insets={left=4,right=4,top=4,bottom=4},
    })
    panel:SetBackdropColor(0.05,0.05,0.08,0.97)
    panel:SetBackdropBorderColor(0.4,0.55,1.0,0.9)

    -- Row 1: title, search, close, item count
    local title=panel:CreateFontString(nil,"OVERLAY","GameFontNormalLarge")
    title:SetPoint("TOPLEFT",14,-10); title:SetText("|cFF00CCFFMidnightQoL|r  Bags")

    local closeBtn=CreateFrame("Button",nil,panel,"UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT",-2,-2)
    closeBtn:SetScript("OnClick",function() panel:Hide() end)

    local searchBox=CreateFrame("EditBox","MidnightQoLBagSearch",panel,"SearchBoxTemplate")
    searchBox:SetSize(120,22); searchBox:SetPoint("TOPRIGHT",closeBtn,"TOPLEFT",-4,-4)
    searchBox:SetAutoFocus(false)
    searchBox:SetScript("OnTextChanged",function(self)
        liveSearch=self:GetText():lower():match("^%s*(.-)%s*$") or ""
        LayoutPanel()
    end)
    searchBox:SetScript("OnEscapePressed",function(self)
        self:SetText(""); liveSearch=""; LayoutPanel()
    end)
    panel.searchBox=searchBox

    local countLbl=panel:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    countLbl:SetPoint("LEFT",title,"RIGHT",8,0)
    countLbl:SetTextColor(0.6,0.7,0.9)
    panel.countLbl=countLbl

    -- Row 2: bound filter checkboxes, left-aligned so they never overlap search
    local hideBoundCheck=CreateFrame("CheckButton","MidnightQoLBagHideBound",panel,"UICheckButtonTemplate")
    hideBoundCheck:SetSize(24,24); hideBoundCheck:SetPoint("TOPLEFT",10,-32)
    local hideBoundText=_G["MidnightQoLBagHideBoundText"]
    if hideBoundText then
        hideBoundText:SetText("Hide SB")
        hideBoundText:SetFontObject("GameFontNormalSmall")
    end
    hideBoundCheck:SetScript("OnClick",function(self)
        if DB() then
            DB().subBagHideSoulbound=self:GetChecked()
            if self:GetChecked() then
                DB().subBagShowBoundOnly=false
                if panel.showBoundOnlyCheck then panel.showBoundOnlyCheck:SetChecked(false) end
            end
        end
        LayoutPanel()
    end)
    panel.hideBoundCheck=hideBoundCheck

    local hideWarboundCheck=CreateFrame("CheckButton","MidnightQoLBagHideWarbound",panel,"UICheckButtonTemplate")
    hideWarboundCheck:SetSize(24,24); hideWarboundCheck:SetPoint("LEFT",hideBoundCheck,"RIGHT",64,0)
    local hideWarboundText=_G["MidnightQoLBagHideWarboundText"]
    if hideWarboundText then
        hideWarboundText:SetText("Hide WB")
        hideWarboundText:SetFontObject("GameFontNormalSmall")
    end
    hideWarboundCheck:SetScript("OnClick",function(self)
        if DB() then
            DB().subBagHideWarbound=self:GetChecked()
            if self:GetChecked() then
                DB().subBagShowBoundOnly=false
                if panel.showBoundOnlyCheck then panel.showBoundOnlyCheck:SetChecked(false) end
            end
        end
        LayoutPanel()
    end)
    panel.hideWarboundCheck=hideWarboundCheck

    local showBoundOnlyCheck=CreateFrame("CheckButton","MidnightQoLBagShowBoundOnly",panel,"UICheckButtonTemplate")
    showBoundOnlyCheck:SetSize(24,24); showBoundOnlyCheck:SetPoint("LEFT",hideWarboundCheck,"RIGHT",64,0)
    local showBoundOnlyText=_G["MidnightQoLBagShowBoundOnlyText"]
    if showBoundOnlyText then
        showBoundOnlyText:SetText("Bound Only")
        showBoundOnlyText:SetFontObject("GameFontNormalSmall")
    end
    showBoundOnlyCheck:SetScript("OnClick",function(self)
        if DB() then
            DB().subBagShowBoundOnly=self:GetChecked()
            if self:GetChecked() then
                DB().subBagHideSoulbound=false
                DB().subBagHideWarbound=false
                if panel.hideBoundCheck    then panel.hideBoundCheck:SetChecked(false) end
                if panel.hideWarboundCheck then panel.hideWarboundCheck:SetChecked(false) end
            end
        end
        LayoutPanel()
    end)
    panel.showBoundOnlyCheck=showBoundOnlyCheck

    -- Divider below the two rows
    local div=panel:CreateTexture(nil,"ARTWORK")
    div:SetColorTexture(0.3,0.4,0.8,0.3)
    div:SetPoint("TOPLEFT",8,-58); div:SetPoint("TOPRIGHT",-8,-58); div:SetHeight(1)

    -- Scroll frame starts below the two header rows
    local scroll=CreateFrame("ScrollFrame",nil,panel,"UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT",8,-62)
    scroll:SetPoint("BOTTOMRIGHT",-26,36)
    panel.scroll=scroll

    -- Canvas (child of scroll)
    local canvas=CreateFrame("Frame",nil,scroll)
    canvas:SetWidth(PANEL_W-40)
    canvas:SetHeight(100)
    scroll:SetScrollChild(canvas)
    panel.canvas=canvas

    -- Bottom bar
    local goldLbl=panel:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    goldLbl:SetPoint("BOTTOMLEFT",12,14); goldLbl:SetTextColor(1,0.82,0)
    panel.goldLbl=goldLbl

    local slotLbl=panel:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    slotLbl:SetPoint("BOTTOMRIGHT",-12,14); slotLbl:SetTextColor(0.6,0.7,0.9)
    panel.slotLbl=slotLbl

    table.insert(UISpecialFrames,"MidnightQoLBagPanel")
end

local function OpenPanel()
    BuildPanel()
    if DB() then
        -- Restore window position and size
        if DB().bagPanelPos then
            local pos = DB().bagPanelPos
            panel:ClearAllPoints()
            panel:SetPoint("CENTER", UIParent, "CENTER", pos[1], pos[2])
        else
            panel:ClearAllPoints()
            panel:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        end
        if DB().bagPanelSize then
            local sz = DB().bagPanelSize
            panel:SetSize(sz[1] or PANEL_W, sz[2] or PANEL_H)
        end
        ICON_SZ = DB().subBagIconSize or 37
        -- Sync checkbox visual state from DB — without this it always shows
        -- unchecked on open regardless of the saved setting.
        if panel.hideBoundCheck then
            panel.hideBoundCheck:SetChecked(DB().subBagHideSoulbound == true)
        end
        if panel.hideWarboundCheck then
            panel.hideWarboundCheck:SetChecked(DB().subBagHideWarbound == true)
        end
        if panel.showBoundOnlyCheck then
            panel.showBoundOnlyCheck:SetChecked(DB().subBagShowBoundOnly == true)
        end
    else
        panel:ClearAllPoints()
        panel:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
    RebuildItemCache()
    LayoutPanel()
    panel:Show()
end

local function TogglePanel()
    if panel and panel:IsShown() then panel:Hide() else OpenPanel() end
end

API.ToggleBagPanel=TogglePanel
API.OpenBagPanel=OpenPanel

-- ── Intercept the default bag open/close ─────────────────────────────────────
-- We hook ToggleAllBags (keybind) and OpenAllBags (backpack button & macro)
-- so the MidnightQoL panel opens instead of the Blizzard combined bag.
local function HookBagFunctions()
    -- ToggleAllBags is called by the B/backpack keybind
    if ToggleAllBags then
        local orig=ToggleAllBags
        ToggleAllBags=function()
            if DB() and DB().subBagPanelEnabled then
                TogglePanel()
            else
                orig()
            end
        end
    end
    -- OpenAllBags is called by addon buttons and /script OpenAllBags()
    if OpenAllBags then
        local orig=OpenAllBags
        OpenAllBags=function()
            if DB() and DB().subBagPanelEnabled then
                OpenPanel()
            else
                orig()
            end
        end
    end
    -- CloseAllBags
    if CloseAllBags then
        local orig=CloseAllBags
        CloseAllBags=function()
            if panel and panel:IsShown() then panel:Hide() end
            orig()
        end
    end
end

-- ════════════════════════════════════════════════════════════════════════════════
-- SETTINGS TAB
-- ════════════════════════════════════════════════════════════════════════════════
local bagsTabFrame
local rowPool={}
local ROW_H=30
local subBagScrollChild

local PRESETS={
    {"|cFFFFD700Gear|r",       "#armor|#weapon"},
    {"|cFF3399FFConsumables|r","#consumable"},
    {"|cFF33FF99Reagents|r",   "#reagent"},
    {"|cFFFF9933Quest|r",      "#questitem"},
    {"|cFFFF4444Junk|r",       "^junk"},
    {"|cFFAA66FFRecipes|r",    "#recipe"},
    {"|cFF44FFFFHigh ilvl|r",  "ilvl>600"},
    {"|cFFFFAAAABoE Gear|r",   "^boe"},
}

local function GetOrCreateRow(n)
    if rowPool[n] then return rowPool[n] end
    local row=CreateFrame("Frame",nil,subBagScrollChild,"BackdropTemplate")
    row:SetHeight(ROW_H)
    row:SetBackdrop({bgFile="Interface/Tooltips/UI-Tooltip-Background",
        edgeFile="Interface/Tooltips/UI-Tooltip-Border",
        tile=true,tileSize=8,edgeSize=10,
        insets={left=2,right=2,top=2,bottom=2}})
    local sw=CreateFrame("Frame",nil,row); sw:SetSize(12,12); sw:SetPoint("LEFT",6,0)
    local st=sw:CreateTexture(nil,"ARTWORK"); st:SetAllPoints()
    row.sw=sw; row.st=st
    local ne=CreateFrame("EditBox",nil,row,"InputBoxTemplate")
    ne:SetSize(120,20); ne:SetPoint("LEFT",sw,"RIGHT",6,0)
    ne:SetAutoFocus(false); ne:SetMaxLetters(40); row.ne=ne
    local se=CreateFrame("EditBox",nil,row,"InputBoxTemplate")
    se:SetSize(210,20); se:SetPoint("LEFT",ne,"RIGHT",6,0)
    se:SetAutoFocus(false); se:SetMaxLetters(200); row.se=se
    local sb=CreateFrame("Button",nil,row,"UIPanelButtonTemplate")
    sb:SetSize(44,20); sb:SetPoint("LEFT",se,"RIGHT",4,0); sb:SetText("Save"); row.sb=sb
    local db=CreateFrame("Button",nil,row,"UIPanelButtonTemplate")
    db:SetSize(44,20); db:SetPoint("LEFT",sb,"RIGHT",2,0); db:SetText("|cFFFF4444Del|r"); row.db=db

    -- Up / Down reorder buttons (wired in RebuildSubBagRows where index is known)
    local upBtn=CreateFrame("Button",nil,row,"UIPanelButtonTemplate")
    upBtn:SetSize(24,20); upBtn:SetPoint("LEFT",db,"RIGHT",6,0); upBtn:SetText("▲"); row.upBtn=upBtn
    local dnBtn=CreateFrame("Button",nil,row,"UIPanelButtonTemplate")
    dnBtn:SetSize(24,20); dnBtn:SetPoint("LEFT",upBtn,"RIGHT",2,0); dnBtn:SetText("▼"); row.dnBtn=dnBtn

    rowPool[n]=row; return row
end

local function RebuildSubBagRows()
    if not subBagScrollChild then return end
    for _,r in ipairs(rowPool) do r:Hide() end
    local sbs=DB() and DB().subBags or {}
    subBagScrollChild:SetHeight(math.max(#sbs*(ROW_H+4),10))
    for i,entry in ipairs(sbs) do
        local row=GetOrCreateRow(i)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT",0,-(i-1)*(ROW_H+4))
        row:SetPoint("TOPRIGHT",0,-(i-1)*(ROW_H+4))
        row:SetHeight(ROW_H)
        if i%2==0 then row:SetBackdropColor(0.10,0.12,0.20,0.7)
        else row:SetBackdropColor(0.07,0.08,0.14,0.7) end
        row:SetBackdropBorderColor(0.25,0.35,0.60,0.5)
        local r,g,b=Accent(i); row.st:SetColorTexture(r,g,b,0.9)
        row.ne:SetText(entry.name or "")
        row.se:SetText(entry.search or "")
        local cap,capI=entry,i
        row.sb:SetScript("OnClick",function()
            local n=row.ne:GetText():match("^%s*(.-)%s*$")
            local s=row.se:GetText():match("^%s*(.-)%s*$")
            if n=="" then print("|cFF00CCFF[MidnightQoL Bags]|r Name cannot be empty."); return end
            cap.name=n; cap.search=s
            if panel and panel:IsShown() then LayoutPanel() end
            print("|cFF00CCFF[MidnightQoL Bags]|r Saved: |cFFFFD700"..n.."|r")
        end)
        row.db:SetScript("OnClick",function()
            table.remove(DB().subBags,capI)
            RebuildSubBagRows()
            if panel and panel:IsShown() then LayoutPanel() end
        end)
        -- Reorder buttons — capI is the index at the time this row was built
        row.upBtn:SetScript("OnClick",function()
            ReorderSection(capI, -1)
            RebuildSubBagRows()
        end)
        row.dnBtn:SetScript("OnClick",function()
            ReorderSection(capI, 1)
            RebuildSubBagRows()
        end)
        -- Grey out buttons at the boundaries
        row.upBtn:SetEnabled(capI > 1)
        row.dnBtn:SetEnabled(capI < #sbs)
        row:Show()
    end
end
API.RebuildSubBagRows=RebuildSubBagRows

local function BuildBagsTab()
    bagsTabFrame=CreateFrame("Frame","MidnightQoLBagsSettingsFrame",UIParent)
    bagsTabFrame:SetSize(620,580); bagsTabFrame:Hide()
    local y=-10

    local openBtn=CreateFrame("Button",nil,bagsTabFrame,"UIPanelButtonTemplate")
    openBtn:SetSize(180,28); openBtn:SetPoint("TOPLEFT",10,y)
    openBtn:SetText("Open Bag Panel  (/mqb)")
    openBtn:SetScript("OnClick",TogglePanel)
    y=y-38

    -- Replace default bag toggle
    local replaceCheck=CreateFrame("CheckButton","CSBagsReplaceCheck",bagsTabFrame,"UICheckButtonTemplate")
    replaceCheck:SetSize(24,24); replaceCheck:SetPoint("TOPLEFT",10,y)
    local rl=_G["CSBagsReplaceCheckText"]
    if rl then rl:SetText("Replace default bag with this panel  |cFFAAAAAA(B key / backpack button opens MidnightQoL Bags)|r") end
    replaceCheck:SetScript("OnClick",function(self)
        if DB() then DB().subBagPanelEnabled=self:GetChecked() end
    end)
    y=y-30

    -- ilvl toggle
    local ilvlCheck=CreateFrame("CheckButton","CSBagsIlvlCheck3",bagsTabFrame,"UICheckButtonTemplate")
    ilvlCheck:SetSize(24,24); ilvlCheck:SetPoint("TOPLEFT",10,y)
    local il=_G["CSBagsIlvlCheck3Text"]
    if il then il:SetText("Show item level on gear icons") end
    ilvlCheck:SetScript("OnClick",function(self)
        if DB() then DB().subBagIlvlEnabled=self:GetChecked() end
        if panel and panel:IsShown() then LayoutPanel() end
    end)
    y=y-30

    -- Upgrade badge toggle
    local upgrCheck=CreateFrame("CheckButton","CSBagsUpgrCheck3",bagsTabFrame,"UICheckButtonTemplate")
    upgrCheck:SetSize(24,24); upgrCheck:SetPoint("TOPLEFT",10,y)
    local ul=_G["CSBagsUpgrCheck3Text"]
    if ul then ul:SetText("Show upgrade badge on bag items  |cFFAAAAAA(green +delta badge)|r") end
    upgrCheck:SetScript("OnClick",function(self)
        if DB() then DB().bagUpgradeEnabled=self:GetChecked() end
        if API.BagUpgradeScan then API.BagUpgradeScan() end
    end)
    y=y-30

    -- Hide soulbound checkbox
    local sbCheck=CreateFrame("CheckButton","CSBagsHideSoulboundCheck",bagsTabFrame,"UICheckButtonTemplate")
    sbCheck:SetSize(24,24); sbCheck:SetPoint("TOPLEFT",10,y)
    local sbl=_G["CSBagsHideSoulboundCheckText"]
    if sbl then sbl:SetText("Hide soulbound items") end
    sbCheck:SetScript("OnClick",function(self)
        if DB() then
            DB().subBagHideSoulbound=self:GetChecked()
            if self:GetChecked() then
                DB().subBagShowBoundOnly=false
                if soCheck then soCheck:SetChecked(false) end
            end
        end
        if panel and panel:IsShown() then LayoutPanel() end
    end)
    y=y-30

    -- Hide warbound checkbox
    local wbCheck=CreateFrame("CheckButton","CSBagsHideWarboundCheck",bagsTabFrame,"UICheckButtonTemplate")
    wbCheck:SetSize(24,24); wbCheck:SetPoint("TOPLEFT",10,y)
    local wbl=_G["CSBagsHideWarboundCheckText"]
    if wbl then wbl:SetText("Hide warbound items") end
    wbCheck:SetScript("OnClick",function(self)
        if DB() then
            DB().subBagHideWarbound=self:GetChecked()
            if self:GetChecked() then
                DB().subBagShowBoundOnly=false
                if soCheck then soCheck:SetChecked(false) end
            end
        end
        if panel and panel:IsShown() then LayoutPanel() end
    end)
    y=y-30

    -- Show bound/warbound only checkbox
    local soCheck=CreateFrame("CheckButton","CSBagsShowBoundOnlyCheck",bagsTabFrame,"UICheckButtonTemplate")
    soCheck:SetSize(24,24); soCheck:SetPoint("TOPLEFT",10,y)
    local sol=_G["CSBagsShowBoundOnlyCheckText"]
    if sol then sol:SetText("Show only soulbound/warbound items") end
    soCheck:SetScript("OnClick",function(self)
        if DB() then
            DB().subBagShowBoundOnly=self:GetChecked()
            if self:GetChecked() then
                DB().subBagHideSoulbound=false
                DB().subBagHideWarbound=false
                if sbCheck then sbCheck:SetChecked(false) end
                if wbCheck then wbCheck:SetChecked(false) end
            end
        end
        if panel and panel:IsShown() then LayoutPanel() end
    end)
    y=y-30

    -- Icon size slider
    local szLbl=bagsTabFrame:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    szLbl:SetPoint("TOPLEFT",10,y); szLbl:SetText("Icon size:")
    local szSlider=CreateFrame("Slider",nil,bagsTabFrame,"UISliderTemplate")
    szSlider:SetSize(160,16); szSlider:SetPoint("LEFT",szLbl,"RIGHT",10,0)
    szSlider:SetMinMaxValues(24,52); szSlider:SetValueStep(2); szSlider:SetObeyStepOnDrag(true)
    local szVal=bagsTabFrame:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    szVal:SetPoint("LEFT",szSlider,"RIGHT",8,0)
    szSlider:SetScript("OnValueChanged",function(self,v)
        v=math.floor(v/2+0.5)*2; szVal:SetText(v.."px")
        if DB() then DB().subBagIconSize=v end
        ICON_SZ=v
        if panel and panel:IsShown() then LayoutPanel() end
    end)
    y=y-36

    local div=bagsTabFrame:CreateTexture(nil,"ARTWORK")
    div:SetColorTexture(0.3,0.4,0.6,0.3)
    div:SetPoint("TOPLEFT",8,y+6); div:SetPoint("TOPRIGHT",-8,y+6); div:SetHeight(1)
    y=y-8

    local sbHdr=bagsTabFrame:CreateFontString(nil,"OVERLAY","GameFontNormalLarge")
    sbHdr:SetPoint("TOPLEFT",10,y); sbHdr:SetText("|cFFFFD700Sections|r")
    y=y-22

    local sbDesc=bagsTabFrame:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    sbDesc:SetPoint("TOPLEFT",10,y)
    sbDesc:SetText("Each entry becomes a collapsible section in the bag panel. Items that match no section go into \"Other\".")
    sbDesc:SetTextColor(0.6,0.6,0.6); y=y-22

    -- New section input
    local ib=CreateFrame("Frame",nil,bagsTabFrame,"BackdropTemplate")
    ib:SetPoint("TOPLEFT",8,y); ib:SetPoint("TOPRIGHT",-8,y); ib:SetHeight(60)
    ib:SetBackdrop({bgFile="Interface/Tooltips/UI-Tooltip-Background",
        edgeFile="Interface/Tooltips/UI-Tooltip-Border",
        tile=true,tileSize=8,edgeSize=12,insets={left=3,right=3,top=3,bottom=3}})
    ib:SetBackdropColor(0.08,0.10,0.18,0.8)
    ib:SetBackdropBorderColor(0.3,0.45,0.8,0.7)

    local nl=ib:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    nl:SetPoint("TOPLEFT",8,-10); nl:SetText("Name:"); nl:SetTextColor(0.8,0.9,1.0)
    local nb=CreateFrame("EditBox",nil,ib,"InputBoxTemplate")
    nb:SetSize(120,20); nb:SetPoint("LEFT",nl,"RIGHT",4,0)
    nb:SetAutoFocus(false); nb:SetMaxLetters(40)

    local fl=ib:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    fl:SetPoint("LEFT",nb,"RIGHT",10,0); fl:SetText("Filter:"); fl:SetTextColor(0.8,0.9,1.0)
    local fb=CreateFrame("EditBox",nil,ib,"InputBoxTemplate")
    fb:SetSize(185,20); fb:SetPoint("LEFT",fl,"RIGHT",4,0)
    fb:SetAutoFocus(false); fb:SetMaxLetters(200)

    local hb=CreateFrame("Button",nil,ib); hb:SetSize(16,16); hb:SetPoint("LEFT",fb,"RIGHT",3,0)
    do local t=hb:CreateTexture(nil,"OVERLAY"); t:SetAllPoints(); t:SetAtlas("UI-HelpIcon-QuestionMark") end
    hb:SetScript("OnEnter",function(self)
        GameTooltip:SetOwner(self,"ANCHOR_RIGHT")
        GameTooltip:SetText("Filter Syntax",1,1,0)
        GameTooltip:AddLine("#armor  #weapon  #consumable",1,1,1,true)
        GameTooltip:AddLine("#reagent  (all crafting mats, gems, enhancements)",1,1,1,true)
        GameTooltip:AddLine("#questitem  #recipe  #tradegood",1,1,1,true)
        GameTooltip:AddLine("^gear  ^boe  ^junk  ^epic  ^rare",1,1,1,true)
        GameTooltip:AddLine("ilvl>400   ilvl>=600   ilvl<200",1,1,1,true)
        GameTooltip:AddLine("|  = OR      &  = AND",1,1,1,true)
        GameTooltip:AddLine("Plain text matches item name",0.6,0.8,1,true)
        GameTooltip:Show()
    end)
    hb:SetScript("OnLeave",function() GameTooltip:Hide() end)

    local ab=CreateFrame("Button",nil,ib,"UIPanelButtonTemplate")
    ab:SetSize(46,22); ab:SetPoint("RIGHT",ib,"RIGHT",-6,2); ab:SetText("Add")
    ab:SetScript("OnClick",function()
        local n=nb:GetText():match("^%s*(.-)%s*$")
        local s=fb:GetText():match("^%s*(.-)%s*$")
        if n=="" then print("|cFF00CCFF[MidnightQoL Bags]|r Enter a section name."); return end
        if not DB() then return end
        table.insert(DB().subBags,{name=n,search=s,id=NewID()})
        nb:SetText(""); fb:SetText("")
        RebuildSubBagRows()
        if panel and panel:IsShown() then LayoutPanel() end
    end)
    nb:SetScript("OnEnterPressed",function() ab:Click() end)
    fb:SetScript("OnEnterPressed",function() ab:Click() end)

    -- Presets
    local pl=ib:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    pl:SetPoint("BOTTOMLEFT",8,8); pl:SetText("Quick:"); pl:SetTextColor(0.6,0.7,0.9)
    local px=52
    for _,pr in ipairs(PRESETS) do
        local pb=CreateFrame("Button",nil,ib,"UIPanelButtonTemplate")
        pb:SetHeight(16); pb:SetText(pr[1]); pb:SetWidth(80)
        pb:SetPoint("BOTTOMLEFT",px,5)
        local cs=pr[2]
        pb:SetScript("OnClick",function() fb:SetText(cs) end)
        pb:SetScript("OnEnter",function(s)
            GameTooltip:SetOwner(s,"ANCHOR_TOP"); GameTooltip:SetText(cs,0.8,1,0.8); GameTooltip:Show()
        end)
        pb:SetScript("OnLeave",function() GameTooltip:Hide() end)
        C_Timer.After(0,function() pb:SetWidth(pb:GetFontString():GetStringWidth()+16) end)
        px=px+84; if px>520 then break end
    end
    y=y-68

    local hN=bagsTabFrame:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    hN:SetPoint("TOPLEFT",28,y); hN:SetText("Name"); hN:SetTextColor(0.6,0.8,1.0)
    local hF=bagsTabFrame:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    hF:SetPoint("TOPLEFT",160,y); hF:SetText("Filter"); hF:SetTextColor(0.6,0.8,1.0)
    y=y-16

    local cd=bagsTabFrame:CreateTexture(nil,"ARTWORK")
    cd:SetColorTexture(0.3,0.45,0.8,0.3)
    cd:SetPoint("TOPLEFT",8,y+4); cd:SetPoint("TOPRIGHT",-8,y+4); cd:SetHeight(1); y=y-2

    local sf=CreateFrame("ScrollFrame",nil,bagsTabFrame,"UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT",8,y); sf:SetPoint("BOTTOMRIGHT",-26,10)
    subBagScrollChild=CreateFrame("Frame",nil,sf)
    subBagScrollChild:SetSize(560,10); sf:SetScrollChild(subBagScrollChild)

    local function SyncBagsTab()
        if not DB() then return end
        replaceCheck:SetChecked(DB().subBagPanelEnabled==true)
        ilvlCheck:SetChecked(DB().subBagIlvlEnabled~=false)
        upgrCheck:SetChecked(DB().bagUpgradeEnabled==true)
        sbCheck:SetChecked(DB().subBagHideSoulbound==true)
        wbCheck:SetChecked(DB().subBagHideWarbound==true)
        soCheck:SetChecked(DB().subBagShowBoundOnly==true)
        szSlider:SetValue(DB().subBagIconSize or 37)
        RebuildSubBagRows()
    end
    API._bagsTabSync=SyncBagsTab
    API.RegisterTab("Bags",bagsTabFrame,SyncBagsTab,80,nil,3)
end

-- ════════════════════════════════════════════════════════════════════════════════
-- ILVL OVERLAY ON NATIVE BAGS (still works when panel is closed)
-- ════════════════════════════════════════════════════════════════════════════════
local ilvlOverlays={}
local ilvlRetry={}; local ilvlTimer

local function GetOrCreateIlvlOverlay(button)
    if ilvlOverlays[button] then return ilvlOverlays[button] end
    local f=CreateFrame("Frame",nil,button)
    f:SetFrameLevel(button:GetFrameLevel()+6); f:SetAllPoints(button)
    local txt=f:CreateFontString(nil,"OVERLAY")
    txt:SetFont("Fonts\\FRIZQT__.TTF",9,"OUTLINE")
    txt:SetPoint("BOTTOMLEFT",f,"BOTTOMLEFT",2,2)
    f.txt=txt; f:Hide(); ilvlOverlays[button]=f; return f
end

local function UpdateIlvlButton(button)
    if not(DB() and DB().subBagIlvlEnabled) then
        if ilvlOverlays[button] then ilvlOverlays[button]:Hide() end; return
    end
    local bagID=button.GetBagID and button:GetBagID() or button:GetParent():GetID()
    local slotID=button:GetID()
    local info=C_Container.GetContainerItemInfo(bagID,slotID)
    if not info or not info.hyperlink or not IsGear(info.hyperlink) then
        if ilvlOverlays[button] then ilvlOverlays[button]:Hide() end; return
    end
    local il=GetIlvl(info.hyperlink)
    if not il or il<=0 then
        ilvlRetry[button]=true
        if not ilvlTimer then
            ilvlTimer=C_Timer.NewTimer(0.4,function()
                ilvlTimer=nil; local p=ilvlRetry; ilvlRetry={}
                for b in pairs(p) do UpdateIlvlButton(b) end
            end)
        end; return
    end
    local ov=GetOrCreateIlvlOverlay(button)
    local qc=QCOLOR[info.quality] or QCOLOR[1]
    ov.txt:SetTextColor(qc[1],qc[2],qc[3]); ov.txt:SetText(il); ov:Show()
end

local function ScanIlvlFrame(frame)
    if not(DB() and DB().subBagIlvlEnabled) then return end
    if frame.EnumerateValidItems then
        for _,btn in frame:EnumerateValidItems() do UpdateIlvlButton(btn) end
    end
end

local hookedFrames={}
local function HookFrame(frame)
    if not frame or hookedFrames[frame] then return end
    hookedFrames[frame]=true
    if frame.UpdateItems then
        hooksecurefunc(frame,"UpdateItems",function(self) ScanIlvlFrame(self) end)
    end
end

-- ════════════════════════════════════════════════════════════════════════════════
-- EVENTS & INIT
-- ════════════════════════════════════════════════════════════════════════════════
local eventFrame=CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("BAG_UPDATE_DELAYED")
eventFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
eventFrame:RegisterEvent("ITEM_LOCK_CHANGED")

BuildBagsTab()

local bagScanTimer
eventFrame:SetScript("OnEvent",function(self,event)
    if event=="PLAYER_LOGIN" then
        self:UnregisterEvent("PLAYER_LOGIN")
        DB()
        HookBagFunctions()
        if ContainerFrameMixin then
            hooksecurefunc(ContainerFrameMixin,"UpdateItems",function(f) ScanIlvlFrame(f) end)
        end
        if ContainerFrameCombinedBags then HookFrame(ContainerFrameCombinedBags) end
        local N=NUM_TOTAL_BAG_FRAMES or NUM_CONTAINER_FRAMES or 13
        for i=1,N do HookFrame(_G["ContainerFrame"..i]) end
        C_Timer.After(0,function()
            if API._bagsTabSync then API._bagsTabSync() end
        end)
        return
    end
    if not DB() then return end
    if bagScanTimer then bagScanTimer:Cancel() end
    bagScanTimer=C_Timer.NewTimer(0.3,function()
        bagScanTimer=nil
        RebuildItemCache()
        if panel and panel:IsShown() then LayoutPanel() end
    end)
end)

SLASH_MQBAGS1="/mqb"; SLASH_MQBAGS2="/mqbags"
SlashCmdList["MQBAGS"]=function() TogglePanel() end

-- /mqbdebug: prints tooltip-detected warbound items directly to chat for verification
SLASH_MQBDEBUG1="/mqbdebug"
SlashCmdList["MQBDEBUG"] = function()
    print("|cFF00CCFF[MQB Debug]|r Warbound scan (tooltip method):")
    local NUM_BAGS = NUM_TOTAL_BAG_FRAMES or 5
    for bag = 0, NUM_BAGS - 1 do
        local n = C_Container.GetContainerNumSlots(bag)
        for slot = 1, n do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.hyperlink then
                local name = GetItemInfo(info.hyperlink) or "?"
                local wb = IsWarboundItem(bag, slot)
                if wb or info.isBound then
                    print(string.format("  [%d/%d] %s  isBound=%s  isWarbound=%s",
                        bag, slot, name, tostring(info.isBound), tostring(wb)))
                end
            end
        end
    end
    print("|cFF00CCFF[MQB Debug]|r Done.")
end



API.Debug("[MidnightQoL] SubBags loaded.")