-- ============================================================
-- MidnightQoL_ResourceBars / ResourceBarsUI.lua
-- Config tab for resource bars: add/remove, power type picker,
-- colour picker, size/position controls, pip settings.
-- ============================================================

local API = MidnightQoLAPI

local MAX_BARS    = 6
local function GetBarConfigs() return API.barConfigs end

-- ── Content frame ─────────────────────────────────────────────────────────────
local contentFrame = CreateFrame("Frame","MidnightQoLResourceBarsFrame",UIParent)
contentFrame:SetSize(640,500); contentFrame:Hide()

-- ── Header ────────────────────────────────────────────────────────────────────
local headerLbl = contentFrame:CreateFontString(nil,"OVERLAY","GameFontNormalLarge")
headerLbl:SetPoint("TOPLEFT",0,-4)
headerLbl:SetText("|cFFFFD700Resource Bars|r")

local descLbl = contentFrame:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
descLbl:SetPoint("TOPLEFT",0,-28); descLbl:SetWidth(630); descLbl:SetJustifyH("LEFT"); descLbl:SetWordWrap(true)
descLbl:SetTextColor(0.75,0.75,0.75,1)
descLbl:SetText(
    "Configure up to "..MAX_BARS.." live resource bars per spec. Bars auto-populate with your spec's primary and "..
    "secondary resources. Use Edit Layout to drag them to position."
)

-- ── Row widget pool ───────────────────────────────────────────────────────────
local rowWidgets = {}   -- [i] = widget table for bar slot i

-- Power type entries for the dropdown
local POWER_ENTRIES = {
    {name="Health",            type=99},  -- player/pet/target health bar
    {name="Mana",          type=0},
    {name="Rage",          type=1},
    {name="Focus",         type=2},
    {name="Energy",        type=3},
    {name="Combo Points",  type=4},
    {name="Runes",         type=5},
    {name="Runic Power",   type=6},
    {name="Soul Shards",   type=7},
    {name="Lunar Power",   type=8},
    {name="Holy Power",    type=9},
    {name="Maelstrom",     type=11},
    {name="Chi",           type=12},
    {name="Insanity",      type=13},
    {name="Arcane Charges",type=16},
    {name="Fury",          type=17},
    {name="Pain",          type=18},
    {name="Essence",       type=19},
    {name="Stagger",            type=20},
    {name="Maelstrom Weapon",   type=21},  -- Enhancement Shaman buff (spell 53817)
    {name="Icicles",            type=23},  -- Frost Mage stacking buff (spell 205473)
    {name="Tip of the Spear",  type=24},  -- Survival Hunter stacking buff (spell 260286)
    {name="Renewing Mist",     type=25},  -- Mistweaver Monk: active RM count (spell 119611)
}

local function PowerTypeName(pt)
    for _,e in ipairs(POWER_ENTRIES) do
        if e.type == pt then return e.name end
    end
    return "Power("..tostring(pt)..")"
end

-- Simple colour box helper
local function CreateColourSwatch(parent, name, r, g, b, onChange)
    local btn = CreateFrame("Button", name, parent)
    btn:SetSize(22,16)
    local tex = btn:CreateTexture(nil,"ARTWORK"); tex:SetAllPoints(btn)
    tex:SetColorTexture(r,g,b,1); btn.tex=tex; btn.r=r; btn.g=g; btn.b=b
    local border = btn:CreateTexture(nil,"BORDER"); border:SetAllPoints(btn)
    border:SetColorTexture(0.6,0.6,0.6,1); btn:SetFrameLevel(btn:GetFrameLevel()+1)
    btn:HookScript("OnClick",function(self)
        ColorPickerFrame:SetupColorPickerAndShow({
            r=self.r, g=self.g, b=self.b, opacity=1,
            swatchFunc=function()
                self.r,self.g,self.b=ColorPickerFrame:GetColorRGB()
                self.tex:SetColorTexture(self.r,self.g,self.b,1)
                if onChange then onChange(self.r,self.g,self.b) end
            end,
            cancelFunc=function(prevValues)
                self.r,self.g,self.b=prevValues.r,prevValues.g,prevValues.b
                self.tex:SetColorTexture(self.r,self.g,self.b,1)
            end,
        })
    end)
    return btn
end

-- Power type dropdown popup (shared, one at a time)
local powerDropPopup = CreateFrame("Frame","CSResPowerDrop",UIParent,"BackdropTemplate")
powerDropPopup:SetSize(180,250); powerDropPopup:SetFrameStrata("TOOLTIP")
powerDropPopup:SetBackdrop({bgFile="Interface/DialogFrame/UI-DialogBox-Background",
    edgeFile="Interface/DialogFrame/UI-DialogBox-Border",
    tile=true,tileSize=16,edgeSize=16,insets={left=4,right=4,top=4,bottom=4}})
powerDropPopup:SetBackdropColor(0.08,0.08,0.12,0.98); powerDropPopup:Hide()

local pdScroll=CreateFrame("ScrollFrame","CSResPowerDropScroll",powerDropPopup,"UIPanelScrollFrameTemplate")
pdScroll:SetPoint("TOPLEFT",8,-8); pdScroll:SetPoint("BOTTOMRIGHT",-28,8)
local pdContent=CreateFrame("Frame","CSResPowerDropContent",pdScroll)
pdContent:SetSize(140,1); pdScroll:SetScrollChild(pdContent)

-- Returns only power types valid for a given unit token by checking UnitPowerMax.
-- Stagger (type 20) is a special case — it's not queryable via UnitPowerMax so we
-- check UnitStagger instead and only include it for the player (monks only).
-- Returns true if the unit is a party member or role token (not player/target/focus).
-- WoW only exposes Mana over the network for these units — all other resources
-- (Energy, Rage, Focus etc) return nil and cannot be tracked.
local function IsPartyUnit(unit)
    if not unit then return false end
    if unit:sub(1,5) == "party" then return true end
    if unit:sub(1,5) == "role:" then return true end
    return false
end

local MANA_ONLY_ENTRIES = {{name="Mana", type=0}}

local function GetFilteredPowerEntries(unit)
    local isRole  = unit and unit:sub(1,5) == "role:"
    local isParty = unit and unit:sub(1,5) == "party"

    -- Pet: health + focus only
    if unit == "pet" then
        return {
            {name="Health", type=99},
            {name="Focus",  type=2},
        }
    end

    -- Target/focus: health only (power type unknown at config time)
    if unit == "target" or unit == "focus" then
        return {
            {name="Health", type=99},
        }
    end

    -- For party/role tokens we can't know the spec, show everything
    if isRole or isParty then
        return POWER_ENTRIES
    end

    -- For the player, filter to only the power types valid for their current spec
    if unit == "player" then
        local specID  = API.currentSpecID
        local allowed = specID and API.SPEC_POWERS and API.SPEC_POWERS[specID]

        if allowed then
            -- Build a set for O(1) lookup
            local allowedSet = {[99]=true}  -- Health always available
            for _, pt in ipairs(allowed) do allowedSet[pt] = true end

            local filtered = {}
            for _, entry in ipairs(POWER_ENTRIES) do
                if allowedSet[entry.type] then
                    filtered[#filtered+1] = entry
                end
            end
            if #filtered > 0 then return filtered end
        end

        -- Fallback if spec unknown: use UnitPowerMax heuristic
        local _, classFile = UnitClass("player")
        local filtered = {}
        for _, entry in ipairs(POWER_ENTRIES) do
            local valid = false
            if entry.type == 99 then  -- Health: always valid
                valid = true
            elseif entry.type == 20 then  -- Stagger: show for any Monk
                valid = (classFile == "MONK")
            elseif entry.type == 21 then  -- Maelstrom Weapon: Shaman only
                valid = (classFile == "SHAMAN")
            elseif entry.type == 22 then  -- Wild Imps: Demonology Warlock only
                valid = (classFile == "WARLOCK")
            elseif entry.type == 12 then  -- Chi: only if UnitPowerMax says it exists
                local maxVal = UnitPowerMax("player", entry.type)
                valid = maxVal and maxVal > 0
            elseif entry.type == 0 or entry.type == 3 then
                valid = true  -- always show Mana and Energy for spec-swap safety
            else
                local maxVal = UnitPowerMax("player", entry.type)
                valid = maxVal and maxVal > 0
            end
            if valid then filtered[#filtered+1] = entry end
        end
        if #filtered > 0 then return filtered end
    end

    -- Fallback for unknown units: show all
    return POWER_ENTRIES
end

local function OpenPowerDrop(anchorBtn, unit, onSelect)
    if powerDropPopup:IsShown() and powerDropPopup.anchor==anchorBtn then
        powerDropPopup:Hide(); return
    end
    powerDropPopup.anchor=anchorBtn
    -- Clear old rows
    for _,c in ipairs({pdContent:GetChildren()}) do c:Hide() end
    local entries = GetFilteredPowerEntries(unit or "player")
    local ROW_H=22
    for i,entry in ipairs(entries) do
        local btn=CreateFrame("Button",nil,pdContent)
        btn:SetSize(135,ROW_H); btn:SetPoint("TOPLEFT",0,-(i-1)*ROW_H)
        local hl=btn:CreateTexture(nil,"HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1,1,1,0.12)
        local lbl=btn:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
        lbl:SetPoint("LEFT",4,0); lbl:SetText(entry.name)
        local capE=entry
        btn:SetScript("OnClick",function()
            onSelect(capE.type, capE.name)
            powerDropPopup:Hide()
        end)
    end
    pdContent:SetHeight(#entries*ROW_H)
    -- Resize popup height to fit entries (capped at 250)
    powerDropPopup:SetHeight(math.min(250, #entries*ROW_H + 16))
    powerDropPopup:ClearAllPoints(); powerDropPopup:SetPoint("TOPLEFT",anchorBtn,"BOTTOMLEFT",0,-4)
    powerDropPopup:Show()
end

-- Power types that support threshold sounds
-- 20=Stagger (% of max health), 21=Maelstrom Weapon, 23=Icicles, 24=Tip of the Spear
local THRESHOLD_POWER_TYPES = { [20]=true, [21]=true, [23]=true, [24]=true }
local THRESHOLD_MAX  = { [21]=10, [23]=5, [24]=3 }  -- max stacks; Stagger uses % so no entry

-- ── Per-bar row factory ───────────────────────────────────────────────────────
-- Layout: each row is 175px tall with sub-rows:
--   Sub-row 1 (y=  0): [✓] Bar N: [Power▼]  ○Bar ○Pips
--   Sub-row 2 (y=-30): Unit: [Player▼]  W:[___] H:[___]  Pips:[_] PipSz:[_]  Fill:■ BG:■
--   Sub-row 3 (y=-62): Label:[__________]  ✓Show label  ✓Show value  Pip shape:[▼]
--   Sub-row 4 (y=-90): [✓] Sound at [_] stacks: [Sound▼]   (hidden unless stack-type power)
local ROW_H  = 200
local ROW_Y0 = -70   -- y of first row's sub-row 1 relative to contentFrame TOPLEFT

-- Base unit token list. Names are resolved dynamically at open-time using UnitName().
-- Role tokens (role:HEALER etc) are shown as a section at the top for convenience.
local ROLE_UNIT_TOKENS = {
    {unit="role:HEALER",  fallback="Group Healer",  isRole=true},
    {unit="role:TANK",    fallback="Group Tank",    isRole=true},
    {unit="role:DAMAGER", fallback="Group DPS",     isRole=true},
}
local UNIT_TOKENS = {
    {unit="player",  fallback="Player"},
    {unit="pet",     fallback="Pet"},
    {unit="target",  fallback="Target"},
    {unit="focus",   fallback="Focus"},
    {unit="party1",  fallback="Party 1"},
    {unit="party2",  fallback="Party 2"},
    {unit="party3",  fallback="Party 3"},
    {unit="party4",  fallback="Party 4"},
}

-- Returns the display label for a unit token, e.g. "Tiny (party3)"
-- Safely retrieve a unit name, returning nil if the value is tainted or empty.
-- UnitName can return a tainted string in combat; any comparison against it
-- outside a pcall will crash, so we isolate the call and comparisons here.
local function SafeUnitName(unit)
    local ok, name = pcall(function()
        local n = UnitName(unit)
        if n and n ~= "" and n ~= "Unknown" then return n end
        return nil
    end)
    return ok and name or nil
end

local function GetUnitLabel(token, fallback, isRole)
    if isRole then
        local slots = {"player","party1","party2","party3","party4"}
        local roleName = token:match("role:(.+)")
        for _, u in ipairs(slots) do
            local roleOk, role = pcall(UnitGroupRolesAssigned, u)
            if roleOk and UnitExists(u) and role == roleName then
                local name = SafeUnitName(u)
                if name then return fallback .. " (" .. name .. ")" end
            end
        end
        return fallback .. " (none)"
    end
    local name = SafeUnitName(token)
    if name then
        if token == "player" then return name end
        return name .. " (" .. token .. ")"
    end
    return fallback
end

-- Returns the saved display name for a unit token (used to refresh button text)
local function GetUnitDisplayName(unit)
    for _, e in ipairs(ROLE_UNIT_TOKENS) do
        if e.unit == unit then
            return GetUnitLabel(e.unit, e.fallback, true)
        end
    end
    for _, e in ipairs(UNIT_TOKENS) do
        if e.unit == unit then
            return GetUnitLabel(e.unit, e.fallback, false)
        end
    end
    return unit
end

-- Shared unit dropdown popup
local unitDropPopup = CreateFrame("Frame","CSResUnitDrop",UIParent,"BackdropTemplate")
unitDropPopup:SetSize(200,180); unitDropPopup:SetFrameStrata("TOOLTIP")
unitDropPopup:SetBackdrop({bgFile="Interface/DialogFrame/UI-DialogBox-Background",
    edgeFile="Interface/DialogFrame/UI-DialogBox-Border",
    tile=true,tileSize=16,edgeSize=16,insets={left=4,right=4,top=4,bottom=4}})
unitDropPopup:SetBackdropColor(0.08,0.08,0.12,0.98); unitDropPopup:Hide()

local udContent=CreateFrame("Frame","CSResUnitDropContent",unitDropPopup)
udContent:SetSize(180,1)
local udScroll=CreateFrame("ScrollFrame","CSResUnitDropScroll",unitDropPopup,"UIPanelScrollFrameTemplate")
udScroll:SetPoint("TOPLEFT",8,-8); udScroll:SetPoint("BOTTOMRIGHT",-28,8)
udScroll:SetScrollChild(udContent)

local function OpenUnitDrop(anchorBtn, onSelect)
    if unitDropPopup:IsShown() and unitDropPopup.anchor==anchorBtn then
        unitDropPopup:Hide(); return
    end
    unitDropPopup.anchor=anchorBtn
    for _,c in ipairs({udContent:GetChildren()}) do c:Hide() end
    local ROW=22
    -- Build list dynamically.
    -- Section 1: role-based tokens (shown whenever in a group)
    local entries = {}
    local inGroup = IsInGroup()
    if inGroup then
        for _, e in ipairs(ROLE_UNIT_TOKENS) do
            entries[#entries+1] = {
                unit    = e.unit,
                display = GetUnitLabel(e.unit, e.fallback, true),
            }
        end
        -- Separator entry (non-clickable divider label)
        entries[#entries+1] = {unit=nil, display="── Specific Unit ──", isSep=true}
    end
    -- Section 2: specific unit tokens; only include occupied party slots
    for _, e in ipairs(UNIT_TOKENS) do
        local isParty = e.unit:sub(1,5) == "party"
        if not isParty or UnitExists(e.unit) then
            entries[#entries+1] = {
                unit    = e.unit,
                display = GetUnitLabel(e.unit, e.fallback, false),
            }
        end
    end
    for idx, entry in ipairs(entries) do
        if entry.isSep then
            -- Non-clickable divider
            local sep = CreateFrame("Frame",nil,udContent)
            sep:SetSize(175,ROW); sep:SetPoint("TOPLEFT",0,-(idx-1)*ROW)
            local lbl=sep:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
            lbl:SetPoint("LEFT",4,0); lbl:SetTextColor(0.5,0.5,0.5,1); lbl:SetText(entry.display)
        else
            local btn=CreateFrame("Button",nil,udContent)
            btn:SetSize(175,ROW); btn:SetPoint("TOPLEFT",0,-(idx-1)*ROW)
            local hl=btn:CreateTexture(nil,"HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1,1,1,0.12)
            local lbl=btn:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
            lbl:SetPoint("LEFT",4,0)
            -- Role entries get a subtle gold tint to stand out
            if entry.unit and entry.unit:sub(1,5) == "role:" then
                lbl:SetTextColor(1, 0.85, 0.3, 1)
            end
            lbl:SetText(entry.display)
            local capE=entry
            btn:SetScript("OnClick",function()
                onSelect(capE.unit, capE.display)
                unitDropPopup:Hide()
            end)
        end
    end
    udContent:SetHeight(#entries*ROW)
    unitDropPopup:SetHeight(math.min(250, #entries*ROW + 16))
    unitDropPopup:ClearAllPoints()
    unitDropPopup:SetPoint("TOPLEFT",anchorBtn,"BOTTOMLEFT",0,-4)
    unitDropPopup:Show()
end

local function CreateBarRow(i)
    -- Y positions for each sub-row (relative to contentFrame TOPLEFT)
    local y1 = ROW_Y0 - (i-1)*ROW_H        -- sub-row 1: enable + power + type
    local y2 = y1 - 30                       -- sub-row 2: unit + size + colour
    local y3 = y1 - 62                       -- sub-row 3: label + toggles

    -- Separator line above each row
    local sep = contentFrame:CreateTexture(nil,"BACKGROUND")
    sep:SetColorTexture(0.3,0.3,0.3,0.4); sep:SetSize(630,1)
    sep:SetPoint("TOPLEFT",0,y1+8)

    -- ── Sub-row 1 ─────────────────────────────────────────────────────────────
    local enableCb = CreateFrame("CheckButton","CSBar"..i.."Enable",contentFrame,"UICheckButtonTemplate")
    enableCb:SetSize(22,22); enableCb:SetPoint("TOPLEFT",0,y1)

    local barLbl = contentFrame:CreateFontString(nil,"OVERLAY","GameFontNormal")
    barLbl:SetPoint("LEFT",enableCb,"RIGHT",2,0); barLbl:SetText("Bar "..i..":")

    local powerBtn = CreateFrame("Button","CSBar"..i.."Power",contentFrame,"GameMenuButtonTemplate")
    powerBtn:SetSize(130,22); powerBtn:SetPoint("LEFT",barLbl,"RIGHT",6,0)
    powerBtn:SetText("(select power)"); powerBtn.powerType=nil

    local barRadio = CreateFrame("CheckButton","CSBar"..i.."IsBar",contentFrame,"UICheckButtonTemplate")
    barRadio:SetSize(18,18); barRadio:SetPoint("LEFT",powerBtn,"RIGHT",14,0); barRadio:SetChecked(true)
    local barRadioLbl=contentFrame:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    barRadioLbl:SetPoint("LEFT",barRadio,"RIGHT",2,0); barRadioLbl:SetText("Bar")

    local pipRadio = CreateFrame("CheckButton","CSBar"..i.."IsPip",contentFrame,"UICheckButtonTemplate")
    pipRadio:SetSize(18,18); pipRadio:SetPoint("LEFT",barRadioLbl,"RIGHT",10,0)
    local pipRadioLbl=contentFrame:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    pipRadioLbl:SetPoint("LEFT",pipRadio,"RIGHT",2,0); pipRadioLbl:SetText("Pips")

    barRadio:SetScript("OnClick",function(self)
        if self:GetChecked() then pipRadio:SetChecked(false) else self:SetChecked(true) end
    end)
    pipRadio:SetScript("OnClick",function(self)
        if self:GetChecked() then barRadio:SetChecked(false) else self:SetChecked(true) end
    end)

    -- ── Sub-row 2 ─────────────────────────────────────────────────────────────
    local unitLbl = contentFrame:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    unitLbl:SetPoint("TOPLEFT",0,y2); unitLbl:SetText("Unit:")

    local unitBtn = CreateFrame("Button","CSBar"..i.."Unit",contentFrame,"GameMenuButtonTemplate")
    unitBtn:SetSize(110,20); unitBtn:SetPoint("LEFT",unitLbl,"RIGHT",4,0)
    unitBtn:SetText("Player"); unitBtn.unit="player"

    local wLbl = contentFrame:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    wLbl:SetPoint("LEFT",unitBtn,"RIGHT",14,0); wLbl:SetText("W:")
    local wEdit = CreateFrame("EditBox","CSBar"..i.."W",contentFrame,"InputBoxTemplate")
    wEdit:SetSize(40,18); wEdit:SetAutoFocus(false); wEdit:SetMaxLetters(5)
    wEdit:SetPoint("LEFT",wLbl,"RIGHT",2,0); wEdit:SetText("200")

    local hLbl = contentFrame:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    hLbl:SetPoint("LEFT",wEdit,"RIGHT",8,0); hLbl:SetText("H:")
    local hEdit = CreateFrame("EditBox","CSBar"..i.."H",contentFrame,"InputBoxTemplate")
    hEdit:SetSize(35,18); hEdit:SetAutoFocus(false); hEdit:SetMaxLetters(4)
    hEdit:SetPoint("LEFT",hLbl,"RIGHT",2,0); hEdit:SetText("20")

    local pipCntLbl = contentFrame:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    pipCntLbl:SetPoint("LEFT",hEdit,"RIGHT",8,0); pipCntLbl:SetText("Pips(0=auto):")
    local pipCountEdit = CreateFrame("EditBox","CSBar"..i.."PipCount",contentFrame,"InputBoxTemplate")
    pipCountEdit:SetSize(28,18); pipCountEdit:SetAutoFocus(false); pipCountEdit:SetMaxLetters(3)
    pipCountEdit:SetPoint("LEFT",pipCntLbl,"RIGHT",2,0); pipCountEdit:SetText("0")

    local pipSzLbl = contentFrame:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    pipSzLbl:SetPoint("LEFT",pipCountEdit,"RIGHT",8,0); pipSzLbl:SetText("Sz:")
    local pipSizeEdit = CreateFrame("EditBox","CSBar"..i.."PipSize",contentFrame,"InputBoxTemplate")
    pipSizeEdit:SetSize(28,18); pipSizeEdit:SetAutoFocus(false); pipSizeEdit:SetMaxLetters(3)
    pipSizeEdit:SetPoint("LEFT",pipSzLbl,"RIGHT",2,0); pipSizeEdit:SetText("18")

    local fillColLbl = contentFrame:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    fillColLbl:SetPoint("LEFT",pipSizeEdit,"RIGHT",12,0); fillColLbl:SetText("Fill:")
    local fillSwatch = CreateColourSwatch(contentFrame,"CSBar"..i.."FillCol",0.2,0.6,1,nil)
    fillSwatch:SetPoint("LEFT",fillColLbl,"RIGHT",4,0)

    local bgColLbl = contentFrame:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    bgColLbl:SetPoint("LEFT",fillSwatch,"RIGHT",10,0); bgColLbl:SetText("BG:")
    local bgSwatch = CreateColourSwatch(contentFrame,"CSBar"..i.."BgCol",0.1,0.1,0.1,nil)
    bgSwatch:SetPoint("LEFT",bgColLbl,"RIGHT",4,0)

    -- ── Sub-row 3 ─────────────────────────────────────────────────────────────
    local labelLbl = contentFrame:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    labelLbl:SetPoint("TOPLEFT",0,y3); labelLbl:SetText("Label:")
    local labelEdit = CreateFrame("EditBox","CSBar"..i.."Label",contentFrame,"InputBoxTemplate")
    labelEdit:SetSize(130,18); labelEdit:SetAutoFocus(false); labelEdit:SetMaxLetters(40)
    labelEdit:SetPoint("LEFT",labelLbl,"RIGHT",4,0)

    local showLabelCb = CreateFrame("CheckButton","CSBar"..i.."ShowLabel",contentFrame,"UICheckButtonTemplate")
    showLabelCb:SetSize(18,18); showLabelCb:SetPoint("LEFT",labelEdit,"RIGHT",14,0)
    local slLbl=contentFrame:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    slLbl:SetPoint("LEFT",showLabelCb,"RIGHT",2,0); slLbl:SetText("Show label")

    local showValueCb = CreateFrame("CheckButton","CSBar"..i.."ShowValue",contentFrame,"UICheckButtonTemplate")
    showValueCb:SetSize(18,18); showValueCb:SetPoint("LEFT",slLbl,"RIGHT",14,0)
    local svLbl=contentFrame:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    svLbl:SetPoint("LEFT",showValueCb,"RIGHT",2,0); svLbl:SetText("Show value")

    -- Shape dropdown sits on row 3 to avoid crowding row 2
    local pipShapeLbl = contentFrame:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    pipShapeLbl:SetPoint("LEFT",svLbl,"RIGHT",16,0); pipShapeLbl:SetText("Pip shape:")
    local pipShapeBtn = CreateFrame("Button","CSBar"..i.."PipShape",contentFrame,"UIPanelButtonTemplate")
    pipShapeBtn:SetSize(90,18); pipShapeBtn:SetPoint("LEFT",pipShapeLbl,"RIGHT",4,0)
    pipShapeBtn:SetText("Square"); pipShapeBtn.shapeKey = "square"

    local shapeDropItems = {}
    for _, s in ipairs(API.PIP_SHAPES or {}) do
        shapeDropItems[#shapeDropItems+1] = {label=s.label, value=s.key}
    end
    local shapeDrop = API.CreateSimpleDropdown(contentFrame, "CSPipShapeDrop"..i, shapeDropItems, 90)

    pipShapeBtn:SetScript("OnClick", function(self)
        shapeDrop:Open(self, shapeDropItems, function(item)
            self.shapeKey = item.value
            self:SetText(item.label)
        end)
    end)

    -- ── Sub-row 4: Threshold sound (only for stack-based power types) ────────
    local y4 = y1 - 92

    local threshCb = CreateFrame("CheckButton","CSBar"..i.."ThreshEnable",contentFrame,"UICheckButtonTemplate")
    threshCb:SetSize(18,18); threshCb:SetPoint("TOPLEFT",0,y4)

    local threshLbl = contentFrame:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    threshLbl:SetPoint("LEFT",threshCb,"RIGHT",2,0); threshLbl:SetText("Sound at")

    local threshEdit = CreateFrame("EditBox","CSBar"..i.."ThreshVal",contentFrame,"InputBoxTemplate")
    threshEdit:SetSize(28,18); threshEdit:SetAutoFocus(false); threshEdit:SetMaxLetters(2)
    threshEdit:SetPoint("LEFT",threshLbl,"RIGHT",4,0); threshEdit:SetText("5")

    local threshStackLbl = contentFrame:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    threshStackLbl:SetPoint("LEFT",threshEdit,"RIGHT",4,0); threshStackLbl:SetText("stacks:")

    -- Sound selector (reuses the same widget as buff alerts / whisper)
    local threshSoundDrop = API.CreateSoundSelectorButton and
        API.CreateSoundSelectorButton(contentFrame, "CSBar"..i.."ThreshSound") or nil

    if threshSoundDrop then
        threshSoundDrop:SetSize(160, 20)
        threshSoundDrop:SetPoint("LEFT", threshStackLbl, "RIGHT", 6, 0)
    end

    -- Helper: show/hide the threshold row based on whether the selected power type supports it
    local threshWidgets = {threshCb, threshLbl, threshEdit, threshStackLbl, threshSoundDrop}

    -- High-stagger color swatch (reuses threshValue % as the trigger point)
    local staggerHighColLbl = contentFrame:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    local staggerHighSwatch = CreateColourSwatch(contentFrame,"CSBar"..i.."StaggerHighCol",1,0.3,0,nil)
    if threshSoundDrop then
        staggerHighColLbl:SetPoint("LEFT", threshSoundDrop, "RIGHT", 10, 0)
    else
        staggerHighColLbl:SetPoint("LEFT", threshStackLbl, "RIGHT", 10, 0)
    end
    staggerHighColLbl:SetText("High color:")
    staggerHighSwatch:SetPoint("LEFT", staggerHighColLbl, "RIGHT", 4, 0)
    staggerHighColLbl:Hide(); staggerHighSwatch:Hide()

    local function UpdateThreshVisibility(pt)
        local show = THRESHOLD_POWER_TYPES[pt] == true
        if pt == 20 then  -- Stagger: percent-based
            threshStackLbl:SetText("% of max HP:")
            threshEdit:SetText(threshEdit:GetText() == "5" and "20" or threshEdit:GetText())
            staggerHighColLbl:Show(); staggerHighSwatch:Show()
        else
            if THRESHOLD_MAX[pt] then
                threshStackLbl:SetText("/ "..THRESHOLD_MAX[pt].." stacks:")
            else
                threshStackLbl:SetText("stacks:")
            end
            staggerHighColLbl:Hide(); staggerHighSwatch:Hide()
        end
        for _, w in ipairs(threshWidgets) do
            if w then if show then w:Show() else w:Hide() end end
        end
    end
    -- Start hidden until a power type is chosen
    UpdateThreshVisibility(nil)

    -- ── Dropdown wire-ups ─────────────────────────────────────────────────────
    powerBtn:SetScript("OnClick",function(self)
        local currentUnit = unitBtn.unit or "player"
        OpenPowerDrop(self, currentUnit, function(pt,ptName)
            self.powerType=pt; self:SetText(ptName)
            UpdateThreshVisibility(pt)
        end)
    end)
    unitBtn:SetScript("OnClick",function(self)
        OpenUnitDrop(self,function(unit, displayName)
            self.unit=unit; self:SetText(displayName)
            powerBtn.powerType=nil; powerBtn:SetText("(select power)")
            UpdateThreshVisibility(nil)
        end)
    end)

    return {
        enableCb=enableCb, powerBtn=powerBtn, unitBtn=unitBtn,
        barRadio=barRadio, pipRadio=pipRadio,
        wEdit=wEdit, hEdit=hEdit,
        pipCountEdit=pipCountEdit, pipSizeEdit=pipSizeEdit,
        pipShapeBtn=pipShapeBtn,
        fillSwatch=fillSwatch, bgSwatch=bgSwatch,
        staggerHighSwatch=staggerHighSwatch,
        labelEdit=labelEdit, showLabelCb=showLabelCb, showValueCb=showValueCb,
        threshCb=threshCb, threshEdit=threshEdit, threshSoundDrop=threshSoundDrop,
        updateThreshVisibility=UpdateThreshVisibility,
        _sep=sep,
        _fontStrings={barLbl, barRadioLbl, pipRadioLbl, unitLbl,
                      wLbl, hLbl, pipCntLbl, pipSzLbl, fillColLbl, bgColLbl, labelLbl,
                      pipShapeLbl, slLbl, svLbl, threshLbl, threshStackLbl},
    }
end

-- ── Build row widgets (hidden by default — shown only when added) ─────────────
local activeRows = 0   -- how many rows are currently shown

-- Pre-create all row widgets but hide them
for i = 1, MAX_BARS do
    rowWidgets[i] = CreateBarRow(i)
    -- Hide every element of this row by hiding its separator and enable checkbox
    -- We track visibility via a flag on the widget table
    rowWidgets[i]._visible = false
end

-- ── Row visibility helpers ────────────────────────────────────────────────────
local addBarBtn   -- forward declared, created below

local function SetRowVisible(i, visible)
    local w = rowWidgets[i]
    if not w then return end
    w._visible = visible
    -- Show/hide all child frames parented to contentFrame for this row.
    -- We use a simpler approach: each widget is already on contentFrame,
    -- so we show/hide the individual frames we have references to.
    local frames = {
        w.enableCb, w.powerBtn, w.unitBtn, w.barRadio, w.pipRadio,
        w.wEdit, w.hEdit, w.pipCountEdit, w.pipSizeEdit, w.pipShapeBtn,
        w.fillSwatch, w.bgSwatch, w.labelEdit, w.showLabelCb, w.showValueCb,
        w.threshCb, w.threshEdit, w.threshSoundDrop,
    }
    for _, f in ipairs(frames) do
        if f then
            if visible then f:Show() else f:Hide() end
        end
    end
    if w._fontStrings then
        for _, fs in ipairs(w._fontStrings) do
            if fs then fs:SetShown(visible) end
        end
    end
    if w._sep then w._sep:SetAlpha(visible and 0.4 or 0) end
    if w._removeBtn then
        if visible then w._removeBtn:Show() else w._removeBtn:Hide() end
    end
end

local function UpdateAddBarBtn()
    if addBarBtn then
        local y = ROW_Y0 - activeRows * ROW_H - 10
        addBarBtn:ClearAllPoints()
        addBarBtn:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 0, y)
        if activeRows < MAX_BARS then
            addBarBtn:Show()
        else
            addBarBtn:Hide()
        end
        contentFrame:SetHeight(math.max(200, -y + 40))
    end
end

local function ShowRow(i)
    SetRowVisible(i, true)
    activeRows = i  -- rows are always shown in order 1..activeRows
    UpdateAddBarBtn()
end

local function HideRow(i)
    -- Reset this row's data
    local w = rowWidgets[i]
    if w then
        w.enableCb:SetChecked(false)
        w.powerBtn:SetText("(none)"); w.powerBtn.powerType = nil
        w.unitBtn:SetText("Player"); w.unitBtn.unit = "player"
        w.barRadio:SetChecked(true); w.pipRadio:SetChecked(false)
        w.wEdit:SetText("200"); w.hEdit:SetText("20")
        w.pipCountEdit:SetText("0"); w.pipSizeEdit:SetText("18")
        w.labelEdit:SetText("")
        w.showLabelCb:SetChecked(true); w.showValueCb:SetChecked(true)
    end
    -- Also clear the barConfig so it won't show a live bar
    local barConfigs = GetBarConfigs()
    if barConfigs then barConfigs[i] = nil end
    SetRowVisible(i, false)
    activeRows = i - 1
    UpdateAddBarBtn()
end

-- Attach remove buttons to each row (done after helpers are defined)
for i = 1, MAX_BARS do
    local w = rowWidgets[i]
    local removeBtn = CreateFrame("Button", "CSBar"..i.."Remove", contentFrame, "UIPanelButtonTemplate")
    removeBtn:SetSize(22, 22); removeBtn:SetText("X"); removeBtn:Hide()
    -- Position at far right of sub-row 1
    local y1 = ROW_Y0 - (i-1)*ROW_H
    removeBtn:SetPoint("TOPRIGHT", contentFrame, "TOPRIGHT", -4, y1+2)
    removeBtn:SetScript("OnClick", function() HideRow(i) end)
    w._removeBtn = removeBtn
    -- Store sep reference for alpha toggling
    -- (sep was created inside CreateBarRow; we need to recreate or reference it)
    -- Simpler: we'll just accept the sep line stays (it's subtle at 0 alpha anyway)
end

-- ── + Add Bar button (lives on contentFrame, not mainFrame) ──────────────────
addBarBtn = CreateFrame("Button", "CSBarsAddBtn", contentFrame, "GameMenuButtonTemplate")
addBarBtn:SetSize(110, 24); addBarBtn:SetText("+ Add Bar")
addBarBtn:SetScript("OnClick", function()
    if activeRows < MAX_BARS then
        local next = activeRows + 1
        ShowRow(next)
    end
end)
UpdateAddBarBtn()

-- ── Refresh UI from barConfigs ────────────────────────────────────────────────
local function RefreshResourceBarUI()
    local barConfigs = GetBarConfigs()
    -- Count how many saved configs exist to know which rows to show
    local savedCount = 0
    for i = 1, MAX_BARS do
        if barConfigs and barConfigs[i] then savedCount = i end
    end

    -- Show/hide rows based on saved data
    activeRows = savedCount
    for i = 1, MAX_BARS do
        local cfg = barConfigs and barConfigs[i]
        if i <= savedCount then
            SetRowVisible(i, true)
        else
            SetRowVisible(i, false)
        end

        local w = rowWidgets[i]
        if w and cfg then
            w.enableCb:SetChecked(cfg.enabled ~= false)
            -- Ensure powerType is never nil so harvest doesn't silently save 0
            local pt = cfg.powerType or 0
            w.powerBtn:SetText(PowerTypeName(pt))
            w.powerBtn.powerType = pt
            w.unitBtn:SetText(GetUnitDisplayName(cfg.unit or "player")); w.unitBtn.unit = cfg.unit or "player"
            w.barRadio:SetChecked(not cfg.isPip)
            w.pipRadio:SetChecked(cfg.isPip == true)
            w.wEdit:SetText(tostring(cfg.w or 200))
            w.hEdit:SetText(tostring(cfg.h or 20))
            w.pipCountEdit:SetText(tostring(cfg.maxPips or 0))
            w.pipSizeEdit:SetText(tostring(cfg.pipSize or 18))
            if w.pipShapeBtn then
                local sk = cfg.pipShape or "square"
                local shapes = API.PIP_SHAPES or {}
                local lbl = "Square"
                for _, s in ipairs(shapes) do if s.key == sk then lbl = s.label; break end end
                w.pipShapeBtn:SetText(lbl); w.pipShapeBtn.shapeKey = sk
            end
            w.labelEdit:SetText(cfg.label or "")
            w.showLabelCb:SetChecked(cfg.showLabel ~= false)
            w.showValueCb:SetChecked(cfg.showValue ~= false)
            if w.fillSwatch then
                w.fillSwatch.r=cfg.r or 0.2; w.fillSwatch.g=cfg.g or 0.6; w.fillSwatch.b=cfg.b or 1
                w.fillSwatch.tex:SetColorTexture(w.fillSwatch.r,w.fillSwatch.g,w.fillSwatch.b,1)
            end
            if w.bgSwatch then
                w.bgSwatch.r=cfg.bgR or 0.1; w.bgSwatch.g=cfg.bgG or 0.1; w.bgSwatch.b=cfg.bgB or 0.1
                w.bgSwatch.tex:SetColorTexture(w.bgSwatch.r,w.bgSwatch.g,w.bgSwatch.b,1)
            end
            if w.staggerHighSwatch then
                w.staggerHighSwatch.r=cfg.staggerHighR or 1
                w.staggerHighSwatch.g=cfg.staggerHighG or 0.3
                w.staggerHighSwatch.b=cfg.staggerHighB or 0
                w.staggerHighSwatch.tex:SetColorTexture(w.staggerHighSwatch.r,w.staggerHighSwatch.g,w.staggerHighSwatch.b,1)
            end
            -- Threshold sound
            local pt = cfg.powerType or 0
            if w.updateThreshVisibility then w.updateThreshVisibility(pt) end
            if w.threshCb then w.threshCb:SetChecked(cfg.threshEnabled or false) end
            if w.threshEdit then w.threshEdit:SetText(tostring(cfg.threshValue or 5)) end
            if w.threshSoundDrop and cfg.threshSound then
                w.threshSoundDrop:SetSelectedSound(cfg.threshSound, cfg.threshSoundIsID)
            end
        elseif w and not cfg then
            w.enableCb:SetChecked(false)
            w.powerBtn:SetText("(none)"); w.powerBtn.powerType=nil
            w.unitBtn:SetText("Player"); w.unitBtn.unit="player"
            w.barRadio:SetChecked(true); w.pipRadio:SetChecked(false)
            w.wEdit:SetText("200"); w.hEdit:SetText("20")
            w.pipCountEdit:SetText("0"); w.pipSizeEdit:SetText("18")
            if w.pipShapeBtn then w.pipShapeBtn:SetText("Square"); w.pipShapeBtn.shapeKey = "square" end
            w.labelEdit:SetText("")
            w.showLabelCb:SetChecked(true); w.showValueCb:SetChecked(true)
        end
    end
    UpdateAddBarBtn()
end
API.RefreshResourceBarUI = RefreshResourceBarUI

-- ── Harvest UI → barConfigs (called by main Save button) ─────────────────────
-- Only writes to barConfigs if the Resources tab was actually opened this session
-- (uiDirty flag). If the user never opened the tab, barConfigs already holds the
-- correct loaded values — don't overwrite them with blank widget defaults.
local uiDirty = false   -- set true when the Resources tab is activated

local function HarvestResourceBarUI()
    -- Only skip if no rows have ever been shown (nothing to harvest)
    local hasVisible = false
    for i = 1, MAX_BARS do
        if rowWidgets[i] and rowWidgets[i]._visible then hasVisible = true; break end
    end
    if not hasVisible then return end
    local barConfigs = GetBarConfigs()
    if not barConfigs then return end
    -- Snapshot dragged positions BEFORE clearing so save doesn't snap bars to origin
    local savedPositions = {}
    for i = 1, MAX_BARS do
        if barConfigs[i] then
            savedPositions[i] = {
                x      = barConfigs[i].x,
                y      = barConfigs[i].y,
                pipGap = barConfigs[i].pipGap,
            }
        end
    end
    -- Clear all slots then re-harvest from all rows that are currently visible
    for i = 1, MAX_BARS do barConfigs[i] = nil end
    for i = 1, MAX_BARS do
        local w = rowWidgets[i]
        if w and w._visible then
            local pos = savedPositions[i]
            barConfigs[i] = {
                x      = pos and pos.x      or 0,
                y      = pos and pos.y      or (-200 - (i-1)*30),
                pipGap = pos and pos.pipGap or 4,
            }
            local cfg = barConfigs[i]
            cfg.enabled   = w.enableCb:GetChecked()
            cfg.unit      = w.unitBtn and w.unitBtn.unit or "player"
            cfg.powerType = w.powerBtn.powerType or 0
            cfg.isPip     = w.pipRadio:GetChecked()
            cfg.isBar     = not cfg.isPip
            cfg.maxPips   = tonumber(w.pipCountEdit:GetText()) or 0  -- 0 = auto from live max
            cfg.pipSize   = tonumber(w.pipSizeEdit:GetText()) or 18
            cfg.pipShape  = (w.pipShapeBtn and w.pipShapeBtn.shapeKey) or "square"
            cfg.w         = tonumber(w.wEdit:GetText()) or 200
            cfg.h         = tonumber(w.hEdit:GetText()) or 20
            cfg.label     = w.labelEdit:GetText()
            cfg.showLabel = w.showLabelCb:GetChecked()
            cfg.showValue = w.showValueCb:GetChecked()
            if w.fillSwatch then cfg.r=w.fillSwatch.r; cfg.g=w.fillSwatch.g; cfg.b=w.fillSwatch.b end
            if w.bgSwatch   then cfg.bgR=w.bgSwatch.r; cfg.bgG=w.bgSwatch.g; cfg.bgB=w.bgSwatch.b end
            if w.staggerHighSwatch then
                cfg.staggerHighR=w.staggerHighSwatch.r
                cfg.staggerHighG=w.staggerHighSwatch.g
                cfg.staggerHighB=w.staggerHighSwatch.b
            end
            -- Threshold sound (only meaningful for stack-based power types)
            if w.threshCb then cfg.threshEnabled = w.threshCb:GetChecked() end
            if w.threshEdit then cfg.threshValue = tonumber(w.threshEdit:GetText()) or 5 end
            if w.threshSoundDrop then
                cfg.threshSound    = w.threshSoundDrop.selectedSound
                cfg.threshSoundIsID = w.threshSoundDrop.selectedSoundIsID
            end
        end
    end
    if API.RebuildLiveBars then API.RebuildLiveBars() end

    -- Seed valueCache for any newly added bars so they show immediately
    if API.barConfigs and API.valueCache then
        for i = 1, MAX_BARS do
            local cfg = API.barConfigs[i]
            if cfg and cfg.enabled then
                local unit = cfg.unit or "player"
                local pt   = cfg.powerType
                if UnitExists(unit) then
                    local key = unit .. ":" .. pt
                    if pt == 20 then  -- POWER_STAGGER
                        API.valueCache[key] = { cur = UnitStagger and UnitStagger(unit) or 0, max = UnitHealthMax(unit) or 1 }
                    elseif pt == 21 then  -- MAELSTROM_WEAPON buff
                        local aura = C_UnitAuras.GetPlayerAuraBySpellID(53817)
                        API.valueCache[key] = { cur = aura and aura.applications or 0, max = 10 }
                    else
                        API.valueCache[key] = { cur = UnitPower(unit, pt) or 0, max = UnitPowerMax(unit, pt) or 1 }
                    end
                end
            end
        end
    end
end
API.HarvestResourceBarUI = HarvestResourceBarUI

-- Register as a pre-save callback so harvest runs before OnSaveProfile writes to disk
-- API.RegisterPreSaveCallback fires before SaveSpecProfile's save callbacks
if API.RegisterPreSaveCallback then
    API.RegisterPreSaveCallback(HarvestResourceBarUI)
else
    -- Fallback: hook the save button (runs after SetScript but before profile write
    -- if we use a pre-hook approach)
    local saveBtn = _G["MidnightQoLSaveBtn"]
    if saveBtn then
        -- Use a pre-click hook by replacing the script
        local orig = saveBtn:GetScript("OnClick")
        saveBtn:SetScript("OnClick", function(self)
            HarvestResourceBarUI()
            if orig then orig(self) end
        end)
    end
end

-- ── Tab registration ──────────────────────────────────────────────────────────
local function OnResourcesTabActivate()
    uiDirty = true
    RefreshResourceBarUI()
end
local function OnResourcesTabDeactivate()
    -- nothing to hide — no floating buttons
end

API.RegisterTab("Resources", contentFrame, OnResourcesTabActivate, 90, OnResourcesTabDeactivate, 6)