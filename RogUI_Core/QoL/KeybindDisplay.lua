-- ============================================================
-- RogUI / Modules / QoL / KeybindDisplay.lua
--
-- Display keybinds on action bar buttons and cooldown frames
-- Integrates with CooldownManagerKeybinds addon if available
-- ============================================================

local API = RogUIAPI

local function GetDB()
    -- Use RogUIDB which is the shared QoL database
    return RogUIDB
end

local function RefreshKeybindDisplay()
    local db = GetDB()
    if not db or not db.showKeybinds then return end
    
    -- Try to get CooldownManagerKeybinds addon
    local cmkbAddon = _G.CooldownManagerKeybinds
    if cmkbAddon and cmkbAddon.IsEnabled then
        -- If CooldownManagerKeybinds is loaded and enabled, use its system
        if cmkbAddon.RefreshAllKeybinds then
            cmkbAddon.RefreshAllKeybinds()
        end
    else
        -- Fallback: simple keybind display using Blizzard API
        local buttons = {}
        
        -- Scan all action buttons (Blizzard bar)
        for i = 1, 120 do
            local btn = _G["ActionButton"..i] or _G["MultiBarBottomLeftButton"..i] or _G["MultiBarBottomRightButton"..i] 
                or _G["MultiBarLeftButton"..i] or _G["MultiBarRightButton"..i]
            if btn then
                table.insert(buttons, btn)
            end
        end
        
        -- Display keybind on each button
        for _, btn in ipairs(buttons) do
            if btn.HotKey then
                local key = GetBindingKey(btn:GetName())
                if key then
                    btn.HotKey:SetText(key)
                    btn.HotKey:Show()
                else
                    btn.HotKey:SetText("")
                end
            end
        end
    end
end

-- ── Initialization ────────────────────────────────────────────────────────────
local function OnKeybindEvent(eventName, ...)
    if eventName == "PLAYER_LOGIN" then
        C_Timer.After(1, RefreshKeybindDisplay)
    elseif eventName == "ACTIONBAR_SLOT_CHANGED" or eventName == "ACTIONBAR_HIDEGRID" or eventName == "ACTIONBAR_SHOWGRID" then
        RefreshKeybindDisplay()
    elseif eventName == "UPDATE_BINDINGS" then
        RefreshKeybindDisplay()
    end
end

API.RegisterEvent("QoL", "PLAYER_LOGIN", function(...) OnKeybindEvent("PLAYER_LOGIN", ...) end)
API.RegisterEvent("QoL", "ACTIONBAR_SLOT_CHANGED", function(...) OnKeybindEvent("ACTIONBAR_SLOT_CHANGED", ...) end)
API.RegisterEvent("QoL", "UPDATE_BINDINGS", function(...) OnKeybindEvent("UPDATE_BINDINGS", ...) end)

-- ── Public API ────────────────────────────────────────────────────────────────
API.KeybindDisplay = {
    Refresh = RefreshKeybindDisplay,
    IsEnabled = function() return (GetDB() and GetDB().showKeybinds) or false end,
}

API.Debug("[RogUI] KeybindDisplay module loaded.")
