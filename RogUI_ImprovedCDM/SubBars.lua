-- ============================================================
-- RogUI / Modules / ImprovedCDM / SubBars.lua
-- ============================================================

local API = RogUIAPI
if not API then return end

-- ─── Constants ────────────────────────────────────────────────────────────────
local ICON_SIZE  = 36
local BAR_PREFIX = "RogUISubBar_"
local ICON_PAD   = 2
local BAR_PAD    = 4

local CDM_VIEWERS = {
    { name = "EssentialCooldownViewer",  cat = 0 },
    { name = "UtilityCooldownViewer",    cat = 1 },
    { name = "CDM_DefensivesContainer",  cat = nil },
    { name = "CDM_TrinketsContainer",    cat = nil },
    { name = "CDM_RacialsContainer",     cat = nil },
}

-- ─── State ────────────────────────────────────────────────────────────────────
local bars           = {}  
local trackedFrames  = {}  
local hookedFrames   = {}  
local hooksInstalled = false
local loginFired     = false
local reconcilePending = false

-- Icon drag/reorder state
local dragState = {
    isDragging = false,
    sourceIcon = nil,
    sourceBar = nil,
    sourceCDID = nil,
    ghostFrame = nil,
}

-- Forward Declarations
local LayoutBar, LayoutAllBars, Reconcile, ScheduleReconcile

-- ─── DB ───────────────────────────────────────────────────────────────────────
local function GetDB()
    if not RogUIDB then return nil end
    if not RogUIDB.subBars then
        RogUIDB.subBars = { positions = {}, barSettings = {} }
    end
    local db = RogUIDB.subBars
    if not db.positions    then db.positions    = {} end
    if not db.barSettings  then db.barSettings  = {} end
    if not db.customIcons  then db.customIcons  = {} end
    -- Migrate legacy customSpells table (flat spellID lists) into customIcons
    if db.customSpells then
        for barIndex, list in pairs(db.customSpells) do
            db.customIcons[barIndex] = db.customIcons[barIndex] or {}
            for _, sid in ipairs(list) do
                local exists = false
                for _, entry in ipairs(db.customIcons[barIndex]) do
                    if entry.type == "spell" and entry.id == sid then exists = true; break end
                end
                if not exists then
                    table.insert(db.customIcons[barIndex], { type = "spell", id = sid })
                end
            end
        end
        db.customSpells = nil
    end

    -- Only seed default bars for a brand new install; don't re-create deleted bars
    if #db.barSettings == 0 then
        for i = 1, 5 do
            db.barSettings[i] = {
                x = 0, y = 50 + (i-1) * 55,
                iconSize = ICON_SIZE, cols = 12,
                label = "Bar " .. i, enabled = true, vertical = false,
            }
        end
    end
    return db
end

-- ─── Drag & Drop Reordering ───────────────────────────────────────────────────

local function CreateDragGhost()
    if dragState.ghostFrame then return dragState.ghostFrame end
    local ghost = CreateFrame("Frame", "RogUI_IconDragGhost", UIParent)
    ghost:SetFrameStrata("TOOLTIP")
    ghost:SetFrameLevel(1000)
    ghost:SetSize(36, 36)
    ghost:Hide()
    local tex = ghost:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints()
    ghost.tex = tex
    dragState.ghostFrame = ghost
    return ghost
end

local function GetInsertionPoint(barIndex, cursorX, cursorY)
    local bar = bars[barIndex]
    if not bar or not bar.container or not bar.container:IsVisible() then return nil end
    local barLeft = bar.container:GetLeft()
    local barTop = bar.container:GetTop()
    if not barLeft or not barTop then return nil end
    local db = GetDB()
    local bdb = db and db.barSettings[barIndex]
    if not bdb then return nil end
    local iconSize = bdb.iconSize or 36
    local cols = bdb.cols or 12
    local relX = cursorX - barLeft
    local relY = barTop - cursorY
    local col = math.floor(relX / (iconSize + ICON_PAD))
    local row = math.floor(relY / (iconSize + ICON_PAD))
    if col < 0 or row < 0 then return nil end
    if bdb.vertical then
        -- vertical mode: icons flow down first then across; cols = max rows per column
        return col * cols + row + 1
    end
    return row * cols + col + 1
end

local function ReorderIconsInBar(barIndex, sourceCDID, targetPosition)
    local db = GetDB()
    if not db or not db.positions then return end
    local icons = {}
    for cdID, pos in pairs(db.positions) do
        if pos.bar == barIndex then
            table.insert(icons, { cdID = cdID, col = pos.col or 999 })
        end
    end
    table.sort(icons, function(a, b) return a.col < b.col end)
    local sourceIndex = nil
    for i, entry in ipairs(icons) do
        if entry.cdID == sourceCDID then
            sourceIndex = i
            break
        end
    end
    if not sourceIndex then return end
    table.remove(icons, sourceIndex)
    targetPosition = math.max(1, math.min(targetPosition, #icons + 1))
    table.insert(icons, targetPosition, { cdID = sourceCDID, col = 0 })
    for i, entry in ipairs(icons) do
        if db.positions[entry.cdID] then
            db.positions[entry.cdID].col = i
        end
    end
    LayoutBar(barIndex)
end

local function OnIconDragStart(iconFrame)
    if not iconFrame.cooldownID or not iconFrame._mqBarIndex then return end
    dragState.isDragging = true
    dragState.sourceIcon = iconFrame
    dragState.sourceBar = iconFrame._mqBarIndex
    dragState.sourceCDID = iconFrame.cooldownID
    local ghost = CreateDragGhost()
    if iconFrame.icon then
        local tex = iconFrame.icon:GetTexture()
        if tex then ghost.tex:SetTexture(tex) end
    end
    ghost:Show()
    iconFrame:SetAlpha(0.4)
    iconFrame:SetScript("OnUpdate", function()
        local x, y = GetCursorPosition()
        local scale = UIParent:GetEffectiveScale()
        ghost:ClearAllPoints()
        ghost:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / scale, y / scale)
    end)
end

local function OnIconDragStop(iconFrame)
    if not dragState.isDragging then return end
    if dragState.ghostFrame then dragState.ghostFrame:Hide() end
    if dragState.sourceIcon then
        dragState.sourceIcon:SetAlpha(1.0)
        dragState.sourceIcon:SetScript("OnUpdate", nil)
    end
    local x, y = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale()
    x, y = x / scale, y / scale
    for barIndex = 1, 20 do
        local bar = bars[barIndex]
        if bar and bar.container and bar.container:IsVisible() then
            local left = bar.container:GetLeft()
            local right = bar.container:GetRight()
            local top = bar.container:GetTop()
            local bottom = bar.container:GetBottom()
            if left and right and top and bottom then
                if x >= left and x <= right and y >= bottom and y <= top then
                    local insertPos = GetInsertionPoint(barIndex, x, y)
                    if insertPos then
                        ReorderIconsInBar(dragState.sourceBar, dragState.sourceCDID, insertPos)
                    end
                    break
                end
            end
        end
    end
    dragState.isDragging = false
    dragState.sourceIcon = nil
    dragState.sourceBar = nil
    dragState.sourceCDID = nil
end

-- ─── Helpers ──────────────────────────────────────────────────────────────────
local function SafeGet(frame, key)
    local ok, v = pcall(function() return frame[key] end)
    return ok and v or nil
end

local function GetNameForCooldownID(cdID)
    if not cdID or not C_CooldownViewer then return tostring(cdID) end
    local ok, info = pcall(C_CooldownViewer.GetCooldownViewerCooldownInfo, cdID)
    if ok and info then
        local sid = info.overrideSpellID or info.spellID
        if sid and sid > 0 then
            local n = C_Spell.GetSpellName(sid)
            if n and n ~= "" then return n end
        end
        if info.itemID and info.itemID > 0 then
            local n = C_Item.GetItemNameByID(info.itemID)
            if n then return n end
        end
    end
    return tostring(cdID)
end

local function GetIconForCooldownID(cdID)
    if not cdID or not C_CooldownViewer then return 134400 end
    local ok, info = pcall(C_CooldownViewer.GetCooldownViewerCooldownInfo, cdID)
    if ok and info then
        local sid = info.overrideSpellID or info.spellID
        if sid and sid > 0 then
            local t = C_Spell.GetSpellTexture(sid)
            if t then return t end
        end
    end
    return 134400
end

-- ─── Layout Logic ─────────────────────────────────────────────────────────────

LayoutBar = function(barIndex)
    local bar = bars[barIndex]
    if not bar or not bar.container then return end
    local db  = GetDB()
    local bdb = db and db.barSettings[barIndex]
    if not bdb then return end

    local iSz = bdb.iconSize or 36
    local pad = ICON_PAD
    local cols = math.max(1, bdb.cols or 12)
    local vertical = bdb.vertical

    local sorted = {}
    for cdID, frame in pairs(bar.members) do
        local pos = db.positions[cdID]
        table.insert(sorted, { cdID = cdID, frame = frame, col = pos and pos.col or 999 })
    end
    table.sort(sorted, function(a, b) return a.col < b.col end)

    local n = #sorted
    if n == 0 then
        bar.container:SetSize(iSz + 8, iSz + 8)
        return
    end

    local barW, barH
    if vertical then
        -- cols = max rows per column; icons flow down then wrap right
        local usedRows = math.min(n, cols)
        local numCols  = math.ceil(n / cols)
        barW = numCols  * (iSz + pad) - pad + 10
        barH = usedRows * (iSz + pad) - pad + 10
    else
        local usedCols = math.min(n, cols)
        local rows     = math.ceil(n / cols)
        barW = usedCols * (iSz + pad) - pad + 10
        barH = rows    * (iSz + pad) - pad + 10
    end
    bar.container:SetSize(barW, barH)

    for i, entry in ipairs(sorted) do
        local frame = entry.frame
        if frame and frame.SetPoint then
            local c, r
            if vertical then
                r = (i - 1) % cols
                c = math.floor((i - 1) / cols)
            else
                c = (i - 1) % cols
                r = math.floor((i - 1) / cols)
            end
            local x = 5 + c * (iSz + pad)
            local y = -(5 + r * (iSz + pad))

            frame._mqBarIndex   = barIndex
            frame._mqSettingPos = true
            frame:ClearAllPoints()
            frame:SetPoint("TOPLEFT", bar.container, "TOPLEFT", x, y)
            frame:SetSize(iSz, iSz)
            frame:SetScale(1)
            frame:Show()
            frame._mqLastX      = x
            frame._mqLastY      = y
            frame._mqSettingPos = false
        end
    end
    
    -- NEW: Reapply alpha during layout (in case slider moved)
    local targetAlpha = 1.0
    if RogUIDB and RogUIDB.cdmAlpha then
        targetAlpha = RogUIDB.cdmAlpha
    elseif bdb.alpha then
        targetAlpha = bdb.alpha
    end
    if bar.container then
        bar.container:SetAlpha(targetAlpha)
    end
end

LayoutAllBars = function()
    for i in pairs(bars) do
        LayoutBar(i)
    end
end

-- ─── Apply Alpha to All Bars ──────────────────────────────────────────────────
-- Called when the global alpha slider in ImprovedCDMUI changes
-- This ensures SubBars bars respond to the same opacity slider as ImprovedCDM bars
function API.SubBars_ApplyGlobalAlpha()
    local targetAlpha = 1.0
    if RogUIDB and RogUIDB.cdmAlpha then
        targetAlpha = RogUIDB.cdmAlpha
    end
    
    for i in pairs(bars) do
        if bars[i] and bars[i].container then
            bars[i].container:SetAlpha(targetAlpha)
        end
    end
end

-- ─── Reconcile Logic ──────────────────────────────────────────────────────────

-- ─── Custom icon frame pool ───────────────────────────────────────────────────
-- We build our own lightweight icon frames for spell/aura/item IDs that the
-- CDM viewer doesn't know about.  Each frame gets a synthetic cooldownID of
-- the form  "custom:type:id"  so the rest of the bar machinery (positions,
-- drag, layout) works unchanged.

local customFramePool = {}   -- array of reusable frames
local activeCustomFrames = {} -- key -> frame (key = "custom:type:id")

local function GetCustomIconKey(iconType, id)
    return "custom:" .. iconType .. ":" .. tostring(id)
end

local function GetOrCreateCustomFrame(key)
    if activeCustomFrames[key] then return activeCustomFrames[key] end

    -- Reuse a pooled frame or create a new one
    local f = table.remove(customFramePool)
    if not f then
        f = CreateFrame("Button", nil, UIParent)
        f:SetSize(36, 36)
        f:EnableMouse(true)
        f:SetMovable(true)
        f:RegisterForDrag("LeftButton")

        local tex = f:CreateTexture(nil, "ARTWORK")
        tex:SetAllPoints(); tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        f.icon = tex

        -- Cooldown spiral
        local cd = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
        cd:SetAllPoints(); cd:SetDrawEdge(true); cd:SetHideCountdownNumbers(false)
        f.cooldownFrame = cd

        -- Stack / charge label
        local cnt = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        cnt:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)
        cnt:SetFont(cnt:GetFont(), 12, "OUTLINE")
        cnt:SetTextColor(1, 1, 1, 1); cnt:Hide()
        f.countLabel = cnt

        -- Drag hooks
        f:SetScript("OnDragStart", function(self) OnIconDragStart(self) end)
        f:SetScript("OnDragStop",  function(self) OnIconDragStop(self)  end)

        -- Right-click: open config modal
        f:SetScript("OnMouseDown", function(self, btn)
            if btn == "RightButton" and self._customID then
                GameTooltip:Hide()
                local id = self._customID
                local name, icon
                if self._customType == "item" then
                    name = C_Item.GetItemNameByID(id)
                    local _, _, _, _, _, _, _, _, _, tex = C_Item.GetItemInfo(id)
                    icon = tex
                else
                    name = C_Spell.GetSpellName(id)
                    icon = C_Spell.GetSpellTexture(id)
                end
                if API.OpenIconConfigModal then
                    API.OpenIconConfigModal(id, name, icon, nil)
                end
            end
        end)

        f:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if self._customType == "spell" or self._customType == "aura" then
                GameTooltip:SetSpellByID(self._customID)
            elseif self._customType == "item" then
                GameTooltip:SetItemByID(self._customID)
            end
            GameTooltip:AddLine("|cFF888888[Right-click] Configure|r")
            GameTooltip:Show()
        end)
        f:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end

    f._customKey  = key
    activeCustomFrames[key] = f
    return f
end

local function ReleaseCustomFrame(key)
    local f = activeCustomFrames[key]
    if not f then return end
    f:Hide()
    f:SetParent(nil)
    f:ClearAllPoints()
    f._customKey  = nil
    f._customType = nil
    f._customID   = nil
    f._mqBarIndex = nil
    f.cooldownID  = nil
    if f.cooldownFrame then f.cooldownFrame:Clear() end
    if f.countLabel    then f.countLabel:Hide() end
    activeCustomFrames[key] = nil
    table.insert(customFramePool, f)
end

local function SetupCustomFrame(f, iconType, id, barIndex)
    f._customType = iconType
    f._customID   = id
    f._mqBarIndex = barIndex
    f.cooldownID  = f._customKey  -- synthetic ID used by drag machinery

    if iconType == "item" then
        -- Item icon + cooldown
        local ok, name, link, _, _, _, _, _, _, texture = pcall(C_Item.GetItemInfo, id)
        if ok and texture then
            f.icon:SetTexture(texture)
        else
            f.icon:SetTexture(134400)
            -- Queue a load
            local item = Item:CreateFromItemID(id)
            item:ContinueOnItemLoad(function()
                local _, _, _, _, _, _, _, _, _, tex = C_Item.GetItemInfo(id)
                if tex and f._customID == id then f.icon:SetTexture(tex) end
            end)
        end
        -- Hook cooldown: C_Item.GetItemCooldown
        f:SetScript("OnUpdate", function(self, dt)
            self._updateThrottle = (self._updateThrottle or 0) + dt
            if self._updateThrottle < 0.5 then return end
            self._updateThrottle = 0
            local start, duration = C_Item.GetItemCooldown(self._customID)
            if start and start > 0 and duration and duration > 0 then
                self.cooldownFrame:SetCooldown(start, duration)
            else
                self.cooldownFrame:Clear()
            end
        end)

    elseif iconType == "spell" then
        local tex = C_Spell.GetSpellTexture(id)
        f.icon:SetTexture(tex or 134400)
        -- Hook cooldown
        f:SetScript("OnUpdate", function(self, dt)
            self._updateThrottle = (self._updateThrottle or 0) + dt
            if self._updateThrottle < 0.5 then return end
            self._updateThrottle = 0
            local start, duration = GetSpellCooldown(self._customID)
            if start and start > 0 and duration and duration > 1.5 then
                self.cooldownFrame:SetCooldown(start, duration)
            else
                self.cooldownFrame:Clear()
            end
            -- Charges
            local cur, max = GetSpellCharges(self._customID)
            if max and max > 1 then
                self.countLabel:SetText(tostring(cur))
                self.countLabel:Show()
            else
                self.countLabel:Hide()
            end
        end)

    elseif iconType == "aura" then
        local tex = C_Spell.GetSpellTexture(id)
        f.icon:SetTexture(tex or 134400)
        -- Hook aura: show stack count + dim when inactive
        f:SetScript("OnUpdate", function(self, dt)
            self._updateThrottle = (self._updateThrottle or 0) + dt
            if self._updateThrottle < 0.25 then return end
            self._updateThrottle = 0
            local aura = C_UnitAuras.GetPlayerAuraBySpellID(self._customID)
            if aura then
                self:SetAlpha(1)
                if (aura.applications or 0) > 1 then
                    self.countLabel:SetText(tostring(aura.applications))
                    self.countLabel:Show()
                else
                    self.countLabel:Hide()
                end
                if aura.expirationTime and aura.expirationTime > 0 then
                    self.cooldownFrame:SetCooldown(
                        aura.expirationTime - aura.duration, aura.duration)
                end
            else
                self:SetAlpha(0.4)
                self.countLabel:Hide()
                self.cooldownFrame:Clear()
            end
        end)
    end
end

-- ─────────────────────────────────────────────────────────────────────────────

Reconcile = function()
    reconcilePending = false
    if not loginFired then return end
    local db = GetDB()
    if not db then return end

    -- Release custom frames that are no longer assigned to any bar
    local stillNeeded = {}
    for barIndex, list in pairs(db.customIcons or {}) do
        local saved_bar = tonumber(barIndex)
        for _, entry in ipairs(list) do
            local key = GetCustomIconKey(entry.type, entry.id)
            stillNeeded[key] = saved_bar
        end
    end
    for key in pairs(activeCustomFrames) do
        if not stillNeeded[key] then ReleaseCustomFrame(key) end
    end

    for i in pairs(bars) do
        if bars[i] then bars[i].members = {} end
    end
    for _, vInfo in ipairs(CDM_VIEWERS) do
        local viewer = _G[vInfo.name]
        if viewer and viewer.itemFramePool then
            for frame in viewer.itemFramePool:EnumerateActive() do
                local cdID = SafeGet(frame, "cooldownID")
                if cdID then
                    
                    -- 1. ALWAYS hook the frame for Right-Clicks, regardless of what bar it is on
                    if not InCombatLockdown() and not hookedFrames[frame] then
                        hookedFrames[frame] = true
                        
                        -- Ensure the frame can physically receive Right Clicks
                        if frame.RegisterForClicks then
                            frame:RegisterForClicks("AnyUp", "AnyDown")
                        end
                        
                        -- Hook for drag/reorder
                        frame:RegisterForDrag("LeftButton")
                        frame:HookScript("OnDragStart", OnIconDragStart)
                        frame:HookScript("OnDragStop", OnIconDragStop)
                        
                        -- Right-click for config modal (Use HookScript to preserve native CDM behavior)
                        frame:HookScript("OnMouseDown", function(self, button)
                            if button == "RightButton" then
                                GameTooltip:Hide()
                                local cdInfo = C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo(self.cooldownID)
                                if cdInfo then
                                    local spellID = cdInfo.overrideSpellID or cdInfo.spellID
                                    if spellID and spellID > 0 then
                                        local name = C_Spell.GetSpellName(spellID)
                                        local icon = C_Spell.GetSpellTexture(spellID)
                                        if API.OpenIconConfigModal then
                                            API.OpenIconConfigModal(spellID, name, icon, cdInfo)
                                        else
                                            print("|cFFFF4444[RogUI]|r API.OpenIconConfigModal is not defined yet!")
                                        end
                                    end
                                end
                            end
                        end)

                        -- Hook positioning lockdown
                        hooksecurefunc(frame, "ClearAllPoints", function(self)
                            if self._mqSettingPos then return end
                            local bi = self._mqBarIndex
                            if not bi or not bars[bi] then return end
                            local lx = self._mqLastX
                            local ly = self._mqLastY
                            if not lx then return end
                            self._mqSettingPos = true
                            self:ClearAllPoints()
                            self:SetPoint("TOPLEFT", bars[bi].container, "TOPLEFT", lx, ly)
                            self._mqSettingPos = false
                        end)
                    end

                    -- 2. NOW check if it belongs to a custom sub-bar for positioning logic
                    local saved = db.positions[cdID]
                    if saved and saved.bar and saved.bar > 0 then
                        local bar = bars[saved.bar]
                        if bar then
                            bar.members[cdID] = frame
                            trackedFrames[frame] = cdID
                            frame:SetParent(bar.container)
                            frame._mqBarIndex = saved.bar
                            frame:Show()
                        end
                    else
                        -- Not on a custom bar. Clear tracker so dragging from main CDM works contextually
                        frame._mqBarIndex = nil 
                    end
                end
            end
        end
    end
    -- ── Custom icons (spell / aura / item added manually by the user) ────────
    if not InCombatLockdown() then
        for barIndex, list in pairs(db.customIcons or {}) do
            barIndex = tonumber(barIndex)
            local bar = barIndex and bars[barIndex]
            if bar then
                for _, entry in ipairs(list) do
                    local key = GetCustomIconKey(entry.type, entry.id)
                    -- Ensure position entry exists so LayoutBar can sort it
                    if not db.positions[key] then
                        db.positions[key] = { bar = barIndex, col = 999 }
                    elseif db.positions[key].bar ~= barIndex then
                        db.positions[key].bar = barIndex
                    end
                    local f = GetOrCreateCustomFrame(key)
                    SetupCustomFrame(f, entry.type, entry.id, barIndex)
                    f:SetParent(bar.container)
                    f:Show()
                    bar.members[key] = f
                end
            end
        end
    end

    LayoutAllBars()
end

ScheduleReconcile = function(delay)
    if reconcilePending then return end
    reconcilePending = true
    C_Timer.After(delay or 0.15, Reconcile)
end

-- ─── CDM hook installation ────────────────────────────────────────────────────
local function InstallCDMHooks()
    if hooksInstalled then return end

    if CooldownViewerSettings and CooldownViewerSettings.GetLayoutManager then
        local layoutMgr = CooldownViewerSettings:GetLayoutManager()
        if layoutMgr and layoutMgr.NotifyListeners then
            hooksecurefunc(layoutMgr, "NotifyListeners", function()
                ScheduleReconcile(0.15)
            end)
        end
    end

    if CooldownViewerMixin and CooldownViewerMixin.OnAcquireItemFrame then
        hooksecurefunc(CooldownViewerMixin, "OnAcquireItemFrame", function()
            ScheduleReconcile(0.15)
        end)
    end

    hooksInstalled = true
end

-- ─── Bar container build ──────────────────────────────────────────────────────
local function BuildBarContainer(barIndex)
    local db  = GetDB()
    local bdb = db and db.barSettings[barIndex]
    if not bdb then return nil end

    local name = BAR_PREFIX .. barIndex
    local c = _G[name] or CreateFrame("Frame", name, UIParent, "BackdropTemplate")
    
    c._isRogUIBar = true
    c:SetMovable(true)
    c:EnableMouse(true)
    c:SetClampedToScreen(true)
    c:RegisterForDrag("LeftButton")
    c:SetScript("OnDragStart", function(self)
        if not (API.IsLayoutMode and API.IsLayoutMode()) then return end
        self:StartMoving()
    end)
    c:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local cx, cy = self:GetCenter()
        local ux, uy = UIParent:GetCenter()
        local db2 = GetDB()
        if db2 and db2.barSettings[barIndex] and cx and ux then
            db2.barSettings[barIndex].x = cx - ux
            db2.barSettings[barIndex].y = cy - uy
        end
    end)

    if not c.lbl then
        local lbl = c:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        lbl:SetPoint("BOTTOMLEFT", c, "TOPLEFT", 2, 2)
        lbl:SetTextColor(0.6, 0.8, 1, 0.9)
        c.lbl = lbl
    end

    c:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1,
    })
    c:SetBackdropColor(0.05, 0.05, 0.08, 0.75)
    c:SetBackdropBorderColor(0.25, 0.25, 0.4, 0.85)
    c.lbl:SetText(bdb.label or ("Bar " .. barIndex))
    c:SetSize(bdb.iconSize + BAR_PAD*2, bdb.iconSize + BAR_PAD*2)
    c:ClearAllPoints()
    c:SetPoint("CENTER", UIParent, "CENTER", bdb.x or 0, bdb.y or (50 + (barIndex-1)*55))

    -- NEW: Apply the global alpha setting (matches ImprovedCDM behavior)
    -- (Prioritizes global RogUIDB.cdmAlpha, fallback to bdb.alpha or 1.0)
    local targetAlpha = 1.0
    if RogUIDB and RogUIDB.cdmAlpha then
        targetAlpha = RogUIDB.cdmAlpha
    elseif bdb.alpha then
        targetAlpha = bdb.alpha
    end
    c:SetAlpha(targetAlpha)

    if bdb.enabled == false then c:Hide() else c:Show() end
    return c
end

-- ─── Public API ───────────────────────────────────────────────────────────────

function API.SubBars_GetBars()
    local db = GetDB()
    if not db then return {} end
    local out = {}
    for i, entry in ipairs(db.barSettings) do
        local copy = {}
        for k, v in pairs(entry) do copy[k] = v end
        copy.index = i
        out[i] = copy
    end
    return out
end

function API.SubBars_GetAllCooldownIDs()
    if not C_CooldownViewer then return {} end
    local db  = GetDB()
    local out = {}
    local seenCdID    = {}
    local seenSpellID = {}

    for cat = 0, 3 do
        local ok, ids = pcall(C_CooldownViewer.GetCooldownViewerCategorySet, cat, false)
        if ok and ids then
            for _, cdID in ipairs(ids) do
                if not seenCdID[cdID] then
                    seenCdID[cdID] = true
                    local ok2, info = pcall(C_CooldownViewer.GetCooldownViewerCooldownInfo, cdID)
                    local resolvedID = ok2 and info and (info.overrideSpellID or info.spellID)
                    if not resolvedID or not seenSpellID[resolvedID] then
                        if resolvedID then seenSpellID[resolvedID] = true end
                        local saved = db and db.positions[cdID]
                        table.insert(out, {
                            cdID     = cdID,
                            name     = GetNameForCooldownID(cdID),
                            icon     = GetIconForCooldownID(cdID),
                            barIndex = saved and saved.bar or 0,
                            col      = saved and saved.col or 999,
                            cat      = cat,
                        })
                    end
                end
            end
        end
    end

    table.sort(out, function(a, b)
        if a.barIndex ~= b.barIndex then return a.barIndex < b.barIndex end
        if (a.col or 999) ~= (b.col or 999) then return (a.col or 999) < (b.col or 999) end
        return (a.name or "") < (b.name or "")
    end)
    
    return out
end

function API.SubBars_SetBarForCooldown(cdID, barIndex)
    local db = GetDB()
    if not db then return end
    if not db.positions[cdID] then db.positions[cdID] = { col = 99 } end
    db.positions[cdID].bar = barIndex
    ScheduleReconcile(0.1)
end

function API.SubBars_SetBarSetting(barIndex, key, value)
    local db = GetDB()
    if not db or not db.barSettings[barIndex] then return end
    db.barSettings[barIndex][key] = value
    LayoutBar(barIndex)
end

function API.SubBars_ReorderIcon(cdID, insertPos)
    local db = GetDB()
    if not db then return end
    local pos = db.positions[cdID]
    if not pos or not pos.bar or pos.bar == 0 then return end
    local barIndex = pos.bar

    -- Build sorted list of all icons in this bar
    local bar = {}
    for id, p in pairs(db.positions) do
        if p.bar == barIndex then
            table.insert(bar, { cdID = id, col = p.col or 999 })
        end
    end
    table.sort(bar, function(a, b) return a.col < b.col end)

    -- Remove the dragged item from the list
    for i = #bar, 1, -1 do
        if bar[i].cdID == cdID then
            table.remove(bar, i)
            break
        end
    end

    -- insertPos is already relative to the list-without-dragged-item,
    -- so clamp and insert directly
    insertPos = math.max(1, math.min(insertPos, #bar + 1))
    table.insert(bar, insertPos, { cdID = cdID, col = 0 })

    -- Write sequential col values back
    for i, entry in ipairs(bar) do
        if db.positions[entry.cdID] then
            db.positions[entry.cdID].col = i
        end
    end
    LayoutBar(barIndex)
end

function API.SubBars_CreateNewBar(label)
    local db = GetDB()
    if not db then return end
    local newIndex = #db.barSettings + 1
    db.barSettings[newIndex] = {
        x = 0, y = 50 + (newIndex - 1) * 55,
        iconSize = ICON_SIZE, cols = 12,
        label = label or ("Bar " .. newIndex), enabled = true, vertical = false,
    }
    local container = BuildBarContainer(newIndex)
    if container then
        bars[newIndex] = { container = container, members = {} }
        container:Show()
    end
    ScheduleReconcile(0.1)
end

function API.SubBars_DeleteBar(barIndex)
    local db = GetDB()
    if not db or not barIndex or barIndex < 1 or barIndex > #db.barSettings then return end

    if bars[barIndex] and bars[barIndex].container then
        local c = bars[barIndex].container
        c:Hide()
        c:ClearAllPoints()
        c:SetParent(nil)
        local name = BAR_PREFIX .. barIndex
        if _G[name] == c then _G[name] = nil end
    end

    for cdID, pos in pairs(db.positions) do
        if pos.bar == barIndex then
            pos.bar = 0
        elseif pos.bar and pos.bar > barIndex then
            pos.bar = pos.bar - 1
        end
    end

    for i = barIndex, #bars - 1 do
        bars[i] = bars[i + 1]
        if bars[i] and bars[i].container then
            local oldName = BAR_PREFIX .. (i + 1)
            local newName = BAR_PREFIX .. i
            if _G[oldName] == bars[i].container then
                _G[oldName] = nil
                _G[newName] = bars[i].container
            end
        end
    end
    bars[#bars] = nil

    table.remove(db.barSettings, barIndex)
    ScheduleReconcile(0.1)
end

function API.SubBars_Refresh()
    ScheduleReconcile(0)
end

function API.SubBars_GetBar(barIndex)
    return bars[barIndex]
end

function API.SubBars_GetAllBars()
    return bars
end

function API.SubBars_GetDB()
    return GetDB()
end

function API.SubBars_LayoutBar(barIndex)
    LayoutBar(barIndex)
end

-- iconType: "spell" | "aura" | "item"
-- id: numeric spell/aura/item ID
-- barIndex: which bar to place it on (1-based)
function API.SubBars_AddCustomIcon(id, iconType, barIndex)
    local db = GetDB()
    if not db or not id or not iconType or not barIndex then return end
    id = tonumber(id)
    barIndex = tonumber(barIndex)
    if not id or id <= 0 or not barIndex or barIndex <= 0 then return end
    if not bars[barIndex] then return end

    db.customIcons[barIndex] = db.customIcons[barIndex] or {}
    -- Deduplicate
    for _, entry in ipairs(db.customIcons[barIndex]) do
        if entry.type == iconType and entry.id == id then return end
    end
    table.insert(db.customIcons[barIndex], { type = iconType, id = id })
    ScheduleReconcile(0.1)
end

function API.SubBars_RemoveCustomIcon(id, iconType, barIndex)
    local db = GetDB()
    if not db or not id or not iconType then return end
    id = tonumber(id)
    if not id then return end

    local function removeFrom(list)
        for i = #list, 1, -1 do
            if list[i].type == iconType and list[i].id == id then
                table.remove(list, i)
            end
        end
    end

    if barIndex then
        barIndex = tonumber(barIndex)
        if db.customIcons[barIndex] then
            removeFrom(db.customIcons[barIndex])
        end
    else
        for _, list in pairs(db.customIcons) do removeFrom(list) end
    end

    -- Release the live frame immediately
    local key = GetCustomIconKey(iconType, id)
    ReleaseCustomFrame(key)
    db.positions[key] = nil
    ScheduleReconcile(0.1)
end

-- Legacy shim (kept so any external callers don't crash)
function API.SubBars_AddCustomSpell(spellID, barIndex)
    API.SubBars_AddCustomIcon(spellID, "spell", barIndex)
end

-- ─── Initialisation ───────────────────────────────────────────────────────────
local function Init()
    if loginFired then return end
    loginFired = true

    local db = GetDB()
    if db then
        for i = 1, #db.barSettings do
            local container = BuildBarContainer(i)
            bars[i] = { container = container, members = {} }
        end
    end

    InstallCDMHooks()
    for _, delay in ipairs({ 1, 3, 7 }) do
        C_Timer.After(delay, Reconcile)
    end

    -- Register SubBar containers as layout mode handles so they can be
    -- repositioned via the Edit Layout screen alongside CDM sets.
    API.RegisterLayoutHandles(function()
        local db2 = GetDB()
        if not db2 then return {} end
        local handles = {}
        for i, bdb in ipairs(db2.barSettings) do
            local bar = bars[i]
            if bar and bar.container and bdb.enabled ~= false then
                local cx, cy = bar.container:GetCenter()
                local ux, uy = UIParent:GetCenter()
                local ox = cx and ux and (cx - ux) or (bdb.x or 0)
                local oy = cy and uy and (cy - uy) or (bdb.y or 0)
                local capturedIndex = i
                table.insert(handles, {
                    label        = "SubBar: " .. (bdb.label or ("Bar " .. i)),
                    iconTex      = "Interface\\Icons\\Ability_Cooldown",
                    ox           = ox,
                    oy           = oy,
                    liveFrameRef = bar.container,
                    saveCallback = function(nx, ny)
                        local db3 = GetDB()
                        if db3 and db3.barSettings[capturedIndex] then
                            db3.barSettings[capturedIndex].x = nx
                            db3.barSettings[capturedIndex].y = ny
                        end
                    end,
                })
            end
        end
        return handles
    end)
end

API.RegisterEvent("SubBars", "PLAYER_LOGIN", Init)
API.RegisterEvent("SubBars", "PLAYER_ENTERING_WORLD", function()
    if loginFired then ScheduleReconcile(2) end
end)