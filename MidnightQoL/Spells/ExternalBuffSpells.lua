-- ExternalBuffSpells.lua
-- Buffs that other players can cast on you, available to all classes.
-- Used by the "Externals" tab in MidnightQoL.
--
-- Entries with an "ids" table (instead of "id") are GROUPS: selecting them tracks
-- ALL spell IDs in the group and fires the alert for any of them.
-- This keeps Bloodlust/Heroism as one clean dropdown entry.

ExternalBuffSpells = {
    -- ==================
    -- BLOODLUST / HEROISM (all variants grouped)
    -- ==================
    {
        ids  = { 2825, 32182, 80353, 90355, 160452, 264667, 272678, 381301, 390386 },
        name = "Bloodlust / Heroism (all variants)",
    },

    -- ==================
    -- POWER INFUSION
    -- ==================
    { id = 10060,  name = "Power Infusion (Priest)" },

    -- ==================
    -- AUGMENTATION EVOKER
    -- ==================
    { id = 395152, name = "Ebon Might (Augmentation Evoker)" },
    { id = 410089, name = "Prescience (Augmentation Evoker)" },
    { id = 373861, name = "Breath of Eons (Augmentation Evoker)" },
    { id = 374227, name = "Zephyr (Evoker)" },
    { id = 363534, name = "Rewind (Evoker)" },

    -- ==================
    -- PALADIN EXTERNALS
    -- ==================
    { id = 6940,   name = "Blessing of Sacrifice (Paladin)" },
    { id = 1022,   name = "Blessing of Protection (Paladin)" },
    { id = 204018, name = "Blessing of Spellwarding (Paladin)" },
    { id = 1044,   name = "Blessing of Freedom (Paladin)" },
    { id = 379043, name = "Blessing of Summer (Paladin)" },
    { id = 388007, name = "Blessing of Autumn (Paladin)" },
    { id = 388011, name = "Blessing of Winter (Paladin)" },
    { id = 388013, name = "Blessing of Spring (Paladin)" },

    -- ==================
    -- PRIEST EXTERNALS
    -- ==================
    { id = 33206,  name = "Pain Suppression (Priest)" },
    { id = 47788,  name = "Guardian Spirit (Priest)" },
    { id = 271466, name = "Luminous Barrier (Priest)" },
    { id = 64843,  name = "Divine Hymn (Priest)" },
    { id = 62618,  name = "Power Word: Barrier (Priest)" },

    -- ==================
    -- DRUID EXTERNALS
    -- ==================
    { id = 29166,  name = "Innervate (Druid)" },
    { id = 102342, name = "Ironbark (Druid)" },

    -- ==================
    -- MONK EXTERNALS
    -- ==================
    { id = 116849, name = "Life Cocoon (Monk)" },
    { id = 325197, name = "Invoke Chi-Ji (Monk)" },

    -- ==================
    -- SHAMAN EXTERNALS
    -- ==================
    { id = 98008,  name = "Spirit Link Totem (Shaman)" },
    { id = 207399, name = "Ancestral Protection Totem (Shaman)" },

    -- ==================
    -- WARRIOR EXTERNALS
    -- ==================
    { id = 386029, name = "Rallying Cry (Warrior)" },

    -- ==================
    -- DEATH KNIGHT EXTERNALS
    -- ==================
    { id = 374251, name = "Abomination Limb (Death Knight)" },

    -- ==================
    -- DEMON HUNTER EXTERNALS
    -- ==================
    { id = 196718, name = "Darkness (Demon Hunter)" },
}