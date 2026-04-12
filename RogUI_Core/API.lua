-- ============================================================
-- RogUI API.lua
-- Shared global API table. All sub-addons read/write this.
-- Populated by RogUI.lua, Widgets.lua, and sub-addons.
-- ============================================================

RogUIAPI = {
    -- ── Sound engine (set by RogUI.lua) ──────────────────────────────
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

    -- ── Spec profile (set by RogUI.lua) ─────────────────────────────
    SaveSpecProfile          = nil,   -- function()
    LoadSpecProfile          = nil,   -- function()
    GetSpecProfileKey        = nil,   -- function() -> string
    GetOrCreateSpecProfile   = nil,   -- function(key) -> table
    RegisterProfileCallbacks = nil,   -- function(saveFunc, loadFunc)
    RegisterPreSaveCallback  = nil,   -- function(fn)
    _saveCallbacks           = {},
    _loadCallbacks           = {},
    _preSaveCallbacks        = {},

    -- ── Tab system (set by RogUI.lua) ───────────────────────────────
    RegisterTab        = nil,   -- function(label, frame, onActivate, widthOverride, onDeactivate, priority)
    ActivateTabByIndex = nil,   -- function(i)
    GetCurrentTabIndex = nil,   -- function() -> int
    GetTabRegistry     = nil,   -- function() -> table
    SetTabEnabled      = nil,   -- function(label, enabled)
    IsTabEnabled       = nil,   -- function(label) -> bool
    UpdateAddButtons   = nil,   -- function(tabIndex)  set by sub-addons

    -- ── Layout system (set by RogUI.lua) ────────────────────────────
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

    -- ── UI checkbox / label references (set by RogUI.lua) ──────────
    buffAlertEnabledCheckbox        = nil,
    whisperIndicatorEnabledCheckbox = nil,
    minimapBtnCheckbox              = nil,
    resourceBarsEnabledCheckbox     = nil,
    specInfoLabel                   = nil,

    -- ── Profile copy tool internals ────────────────────────────────────────
    _profilesFrame      = nil,
    _profilesFrameReady = false,

    -- ── Improved CDM module (set by ImprovedCDM.lua) ───────────────────────────
    icdm_iconSets            = nil,  -- runtime icon-set objects
    icdm_spellSounds         = nil,  -- per-spellID sound assignments

    -- SubBars public API (set by SubBars.lua)
    SubBars_GetBars          = nil,
    SubBars_GetAllCooldownIDs = nil,
    SubBars_SetBarForCooldown = nil,
    SubBars_SetBarSetting    = nil,
    SubBars_ReorderIcon      = nil,
    SubBars_CreateNewBar     = nil,
    SubBars_DeleteBar        = nil,
    SubBars_Refresh          = nil,
    _SubBarsPopulateUI       = nil,  -- set by ImprovedCDMUI after tab 1 is built

    -- TauntWatch (set by TauntWatch.lua)
    TauntWatch               = nil,
    ICDM_CreateSet           = nil,  -- function(setName) -> set
    ICDM_DeleteSet           = nil,  -- function(setName)
    ICDM_RefreshSet          = nil,  -- function(setName)
    ICDM_SetSpellSound       = nil,  -- function(spellID, eventKey, sound, soundIsID)
    ICDM_ClearSpellSound     = nil,  -- function(spellID, eventKey?)
    ICDM_ScanAndHookViewers  = nil,  -- function()
    ICDM_ApplyAllVisibility  = nil,  -- function()
    ICDM_GetRootDB           = nil,  -- function() -> DB table
    ICDM_RefreshTabUI        = nil,  -- function()  (set by ImprovedCDMUI.lua)
    ICDM_SET_DEFAULTS        = nil,
    ICDM_EVT_AVAILABLE       = nil,
    ICDM_EVT_PANDEMIC        = nil,
    ICDM_EVT_ON_COOLDOWN     = nil,
    ICDM_EVT_CHARGE_GAINED   = nil,

    -- ── Utility helpers ────────────────────────────────────────────────────
    NormalizeName      = nil,  -- function(name) -> lowercase, realm stripped
    NormalizeBNName    = nil,  -- function(name) -> lowercase, trimmed
    DeepCopy           = nil,  -- function(orig) -> deep copy
    GetAvailableSpells = nil,  -- function() -> list  (set by BuffAlerts)
    Debug              = nil,  -- function(msg)
    DEBUG              = false, -- toggled via /mqldebug
}

-- ════════════════════════════════════════════════════════════════════════════
-- WoW 10.0+ Backdrop API Compatibility Layer
-- ════════════════════════════════════════════════════════════════════════════
-- In WoW 10.0+, SetBackdrop() was removed. Frames with BackdropTemplate
-- now use backdropInfo table + ApplyBackdrop() or individual methods.
-- This compatibility layer re-implements SetBackdropBorderTexture and friends.

local function InstallBackdropCompatibility()
    local frameMetatable = getmetatable(CreateFrame("Frame")).__index
    if not frameMetatable then return end

    -- SetBackdrop - full backdrop table (removed in WoW 10.0+)
    if not frameMetatable.SetBackdrop then
        function frameMetatable.SetBackdrop(self, backdropTable)
            if not backdropTable then
                self.backdropInfo = nil
                if self.ApplyBackdrop then self:ApplyBackdrop() end
                return
            end
            self.backdropInfo = {
                bgFile   = backdropTable.bgFile,
                edgeFile = backdropTable.edgeFile,
                tile     = backdropTable.tile,
                tileSize = backdropTable.tileSize,
                edgeSize = backdropTable.edgeSize,
                insets   = backdropTable.insets,
            }
            if self.ApplyBackdrop then self:ApplyBackdrop() end
        end
    end

    -- SetBackdropTexture - sets background texture
    if not frameMetatable.SetBackdropTexture then
        function frameMetatable.SetBackdropTexture(self, path)
            if not self.backdropInfo then self.backdropInfo = {} end
            self.backdropInfo.bgFile = path
            if self.ApplyBackdrop then self:ApplyBackdrop() end
        end
    end
    
    -- SetBackdropBorderTexture - sets border/edge texture
    if not frameMetatable.SetBackdropBorderTexture then
        function frameMetatable.SetBackdropBorderTexture(self, path)
            if not self.backdropInfo then self.backdropInfo = {} end
            self.backdropInfo.edgeFile = path
            if self.ApplyBackdrop then self:ApplyBackdrop() end
        end
    end
    
    -- SetBackdropBorderSizeZ - sets border size
    if not frameMetatable.SetBackdropBorderSizeZ then
        function frameMetatable.SetBackdropBorderSizeZ(self, size)
            if not self.backdropInfo then self.backdropInfo = {} end
            self.backdropInfo.edgeSize = size
            if self.ApplyBackdrop then self:ApplyBackdrop() end
        end
    end
    
    -- SetBackdropInsets - sets edge insets/padding
    if not frameMetatable.SetBackdropInsets then
        function frameMetatable.SetBackdropInsets(self, left, right, top, bottom)
            if not self.backdropInfo then self.backdropInfo = {} end
            self.backdropInfo.insets = {left=left, right=right, top=top, bottom=bottom}
            if self.ApplyBackdrop then self:ApplyBackdrop() end
        end
    end
end

-- Install compatibility on addon load
InstallBackdropCompatibility()

