-- ============================================================
-- MidnightQoL API.lua
-- Shared global API table. All sub-addons read/write this.
-- Populated by MidnightQoL.lua, Widgets.lua, and sub-addons.
-- ============================================================

MidnightQoLAPI = {
    -- ── Sound engine (set by MidnightQoL.lua) ──────────────────────────────
    PlayCustomSound      = nil,   -- function(path, isID)
    GetAvailableSounds   = nil,   -- function() -> list
    GetAvailableImages   = nil,   -- function() -> list

    -- ── UI widget factories (set by Widgets.lua) ───────────────────────────
    CreateSoundSelectorButton = nil,  -- function(parent, name) -> btn
    CreateImageSelectorButton = nil,  -- function(parent, name, hiddenInput, spellIdRef) -> btn
    CreateSpellSelectorButton = nil,  -- function(parent, name, auraType, idInputRef) -> btn
    CreateSimpleDropdown      = nil,  -- function(parent, items, onSelect) -> frame
    OpenSoundPicker      = nil,
    OpenImagePicker      = nil,
    OpenSpellPicker      = nil,

    -- ── Spec profile (set by MidnightQoL.lua) ─────────────────────────────
    SaveSpecProfile          = nil,   -- function()
    LoadSpecProfile          = nil,   -- function()
    GetSpecProfileKey        = nil,   -- function() -> string
    GetOrCreateSpecProfile   = nil,   -- function(key) -> table
    RegisterProfileCallbacks = nil,   -- function(saveFunc, loadFunc)
    RegisterPreSaveCallback  = nil,   -- function(fn)
    _saveCallbacks           = {},
    _loadCallbacks           = {},
    _preSaveCallbacks        = {},

    -- ── Tab system (set by MidnightQoL.lua) ───────────────────────────────
    RegisterTab        = nil,   -- function(label, frame, onActivate, widthOverride, onDeactivate, priority)
    ActivateTabByIndex = nil,   -- function(i)
    GetCurrentTabIndex = nil,   -- function() -> int
    GetTabRegistry     = nil,   -- function() -> table
    SetTabEnabled      = nil,   -- function(label, enabled)
    IsTabEnabled       = nil,   -- function(label) -> bool
    UpdateAddButtons   = nil,   -- function(tabIndex)  set by sub-addons

    -- ── Layout system (set by MidnightQoL.lua) ────────────────────────────
    RegisterLayoutHandles = nil,  -- function(providerFunc)
    EnterLayoutMode       = nil,
    ExitLayoutMode        = nil,
    IsLayoutMode          = nil,  -- function() -> bool
    HideAlertPreviews         = nil,  -- function()  final chained version set by Utility.lua
    _hideAlertPreviewsBase    = nil,  -- function()  set by BuffAlerts.lua, chained into above
    _layoutProviders      = {},

    -- ── Player info ────────────────────────────────────────────────────────
    playerClass   = nil,   -- "WARRIOR", "HUNTER", etc.
    currentSpecID = 0,

    -- ── Buff/debuff alert state (set by BuffAlerts.lua) ────────────────────
    trackedBuffs             = nil,
    trackedDebuffs           = nil,
    trackedExternals         = nil,
    ShowAlertOverlay         = nil,
    RefreshAuraListUI        = nil,
    RebuildNameMap           = nil,
    HookBuffViewerPanels     = nil,
    HarvestBuffAlertUIValues = nil,
    CheckCDMismatch          = nil,
    CheckLustDebuff          = nil,
    LUST_ALERT_KEY           = nil,
    SATED_DEBUFF_IDS         = nil,

    -- ── Castbar (set by Castbar.lua) ───────────────────────────────────────
    castbarFrame         = nil,
    ApplyCastbarPosition = nil,

    -- ── Resource bars (set by ResourceBars.lua) ────────────────────────────
    barConfigs           = nil,
    valueCache           = nil,
    breakFill            = nil,
    SPEC_POWERS          = nil,
    PIP_SHAPES           = nil,
    PipDimensions        = nil,
    ApplyPipShape        = nil,
    ColorPip             = nil,
    RebuildLiveBars      = nil,
    RefreshResourceBarUI = nil,
    HarvestResourceBarUI = nil,
    _barsGeneralSync     = nil,

    -- ── Tracked resource spell IDs (set by ResourceBars spells) ───────────
    ICICLES                       = nil,
    TIP_OF_SPEAR                  = nil,
    MAELSTROM_WEAPON              = nil,
    MAELSTROM_WEAPON_SPELL_ID     = nil,
    MAELSTROM_WEAPON_SPELL_ID_OLD = nil,
    RENEWING_MIST                 = nil,

    -- ── XP / Rep bars (set by ExperienceBar.lua / RepBar.lua) ─────────────
    expBar              = nil,
    repBar              = nil,
    UpdateExpBar        = nil,
    ApplyExpBarSettings = nil,
    UpdateRepBar        = nil,
    ApplyRepBarSettings = nil,

    -- ── Whisper module (set by Whisper.lua) ────────────────────────────────
    whisperList          = nil,
    unreadWhispers       = nil,
    GetWhisperState      = nil,
    SetWhisperEnabled    = nil,
    SetWhisperIndicator  = nil,
    SetIgnoreOutgoing    = nil,
    ClearUnreadWhispers  = nil,
    RefreshWhisperListUI = nil,
    SyncWhisperUI        = nil,
    SaveWhisperSettings  = nil,
    LoadWhisperSettings  = nil,
    UpdateUnreadMailIcon = nil,

    -- ── Auto Layout Switcher (set by AutoLayoutSwitcher.lua) ───────────────
    ALSGetActiveLoadoutID = nil,
    ALSTrySwitchLayout    = nil,

    -- ── QoL module (set by QoL.lua / misc) ────────────────────────────────
    BagUpgradeScan       = nil,
    CheckPetReminder     = nil,
    UpdateBrezFrame      = nil,
    StartBreakBar        = nil,
    SyncFadeSliders      = nil,
    generalSoundDropdown = nil,

    -- ── UI checkbox / label references (set by MidnightQoL.lua) ──────────
    buffAlertEnabledCheckbox        = nil,
    whisperIndicatorEnabledCheckbox = nil,
    minimapBtnCheckbox              = nil,
    resourceBarsEnabledCheckbox     = nil,
    specInfoLabel                   = nil,

    -- ── Profile copy tool internals ────────────────────────────────────────
    _profilesFrame      = nil,
    _profilesFrameReady = false,

    -- ── Utility helpers ────────────────────────────────────────────────────
    NormalizeName      = nil,  -- function(name) -> lowercase, realm stripped
    NormalizeBNName    = nil,  -- function(name) -> lowercase, trimmed
    DeepCopy           = nil,  -- function(orig) -> deep copy
    GetAvailableSpells = nil,  -- function() -> list  (set by BuffAlerts)
    Debug              = nil,  -- function(msg)
    DEBUG              = false, -- toggled via /mqldebug
}

