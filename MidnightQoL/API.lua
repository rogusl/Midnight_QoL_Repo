-- ============================================================
-- MidnightQoL API.lua
-- Shared global API table. All sub-addons read/write this.
-- Populated by MidnightQoL.lua, Widgets.lua, and sub-addons.
-- ============================================================

MidnightQoLAPI = {
    -- ── Sound engine (set by MidnightQoL.lua) ──────────────────────────────
    PlayCustomSound      = nil,   -- function(path, isID)
    GetAvailableSounds   = nil,   -- function() → list
    GetAvailableImages   = nil,   -- function() → list

    -- ── UI widget factories (set by Widgets.lua) ───────────────────────────
    CreateSoundSelectorButton = nil,  -- function(parent, name) → btn
    CreateImageSelectorButton = nil,  -- function(parent, name, hiddenInput, spellIdRef) → btn
    CreateSpellSelectorButton = nil,  -- function(parent, name, auraType, idInputRef) → btn
    OpenSoundPicker      = nil,
    OpenImagePicker      = nil,
    OpenSpellPicker      = nil,

    -- ── Spec profile (set by MidnightQoL.lua) ─────────────────────────────
    -- Sub-addons register callbacks so Core can aggregate their data.
    SaveSpecProfile      = nil,   -- function()  — calls all SaveCallbacks then writes DB
    LoadSpecProfile      = nil,   -- function()  — reads DB then calls all LoadCallbacks
    GetSpecProfileKey    = nil,   -- function() → string  e.g. "WARRIOR_72"

    -- Profile callback registration (called during PLAYER_LOGIN init)
    RegisterProfileCallbacks = nil, -- function(saveFunc, loadFunc)
    _saveCallbacks     = {},
    _loadCallbacks     = {},
    _preSaveCallbacks  = {},

    -- ── Tab registration (set by MidnightQoL.lua) ─────────────────────────
    -- Sub-addons call this during/after ADDON_LOADED to add their tab.
    RegisterTab = nil, -- function(label, contentFrame, onActivateFunc, widthOverride)

    -- ── Layout handle registration (set by MidnightQoL.lua) ───────────────
    -- Sub-addons register handles so Edit Layout shows them.
    RegisterLayoutHandles = nil,  -- function(providerFunc)
    -- providerFunc() → array of { label, iconTex, ox, oy, saveCallback,
    --                              liveIconTarget, liveFrameRef, previewFunc }
    _layoutProviders = {},

    -- ── Player info (populated at PLAYER_LOGIN before any sub-addon callback)
    playerClass   = nil,   -- "WARRIOR", "HUNTER", etc.
    currentSpecID = 0,

    -- ── Utility helpers ────────────────────────────────────────────────────
    NormalizeName   = nil,  -- function(name) → lowercase, realm stripped
    NormalizeBNName = nil,  -- function(name) → lowercase, trimmed
    Debug           = nil,  -- function(msg)
    DEBUG           = true,
}
