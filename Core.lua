local addonName = ...
local GetAddOnMetadata = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
GuildBank = LibStub("AceAddon-3.0"):NewAddon(addonName, "AceConsole-3.0", "AceEvent-3.0", "AceComm-3.0", "AceSerializer-3.0", "AceTimer-3.0")
local addon = GuildBank
addon.version = GetAddOnMetadata(addonName, "Version")
addon.playerGuid = UnitGUID("player") or ''

addon.CONSTANTS = {
    versionSteps = {
        '0.5.2',
        '0.6.0',
        '0.7.0',
        '0.8.11'
    },
    rarities = {
        'poor',
        'common',
        'uncommon',
        'rare',
        'epic',
        'legendary'
    },
    containerSlots = {
        bags = {0, 1, 2, 3, 4},
        bank = {-1, 6, 7, 8, 9, 10, 11}
    }
}

addon.COMM = {
    prefixes = {
        sync = "bb_sync",
        syncRequest = "bb_syncrequest",
        syncResponse = "bb_syncresponse",
        chosenForSync = "bb_syncaccepted",
        getBestTimestamp = "bb_bestts",
        getBestTimestampReceived = "bb_bestrec",
        chosenForGuildReply = "bb_guildaccpt",
        wishlistSync = "bb_wlsync",
        wishlistSyncResponse = "bb_wlresponse",
        wishlistChosenForSync = "bb_wlaccepted"
    },
    messages = {
        processPlayers = "bb_processPlayers",
        processGuildReplies = "bb_processGuildReplies",
        tooltipOptionsChanged = "bb_tooltipOptionsChanged"
    }
}

addon.LIBS = {
    icon = LibStub('LibDBIcon-1.0'),
    aceGUI = LibStub("AceGUI-3.0"),
    aceCD = LibStub('AceConfigDialog-3.0'),
    libDB = LibStub('LibDataBroker-1.1'):NewDataObject(addonName, {
        type = 'data source',
        text = 'Beans!',
        icon = "Interface\\Icons\\inv_enchant_shardnexuslarge",
        OnClick = function() addon:ShowUI() end
    })
}

addon.openFrames = 0

addon.versions = {
        type = 'group',
        name = '',
        args = {}
    }


-- `addon:Debug()` is implemented in GuildBank.lua (loads after Core) and also feeds the Debug tab console.