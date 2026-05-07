
--[[
TODO:
* Add dev and debug 
* If you are not opted-in to inter-guild stuff do not respond to whisper requests
* if you have the addon installed, open the GUI with a pre-filled search instead of querying others
* add addon sync indicator in UI (partially done)
* ^prevent addon functions during sync

BUGS:
bank characters can accidentally override their bank info from another player if their first char does something, then gets synced externally,
login to character B and receive the sync

multiple item requests gets confused

long lined description in wishlist item should have new lines

bug when hovering in a crafting recipe tooltip in atlas loot

v0.6.0
* Redo UI using ACD

-- Next phase (v0.7.0)
* guild wishlist that can be synced across players
* guild wishlist items have an itemIdWithSuffix + custom descrition + phase + tbc viable item
* for players with the addon, highlight guild wishlist items + show descriptions & tbc viability
* add IPC message versioning
* items without quality should still be catalogued

By AQ:
* Configure auto-send for items to specific bank character 
* War effort mats
* Consolidate multiple mailboxes in a single tab for bank
* add item age data (how long ago you received it, how long ago you sent any)
]]

--[[------------------------------------------------------------------------------------
    INIT
]]--------------------------------------------------------------------------------------
--inv_scarab_clay

local superdev = UnitNameUnmodified('player') == 'Kuronie'
local addonName = ...
local addon = BeanBank
local version = addon.version
local aceCommPrefixes = addon.COMM.prefixes
local aceCommMessages = addon.COMM.messages
local playerGuid = addon.playerGuid
local containerSlots = addon.CONSTANTS.containerSlots
local rarities = addon.CONSTANTS.rarities
local ACD = addon.LIBS.aceCD
local AceGUI = addon.LIBS.aceGUI
local openedFrames = addon.openFrames


--- Called by Ace3 when addon is loaded.
function addon:OnInitialize()
    self:Print(ChatFrame1, "Initializing...")
    if superdev then self:Print(ChatFrame1, "Superdev activated!") end
    self:RegisterDB()
    if not superdev then
        self:PerformUpgrades()
        self:RegisterComms()
    end
    self:RegisterCallbacks()
    self:RegisterEvents()
    self:RegisterOptions()
    addon:RegisterChatCommand("bb", "RunMenu")
    local bypassRank = 1000
    if UnitNameUnmodified("player") == 'Kuronie' then
        bypassRank = 2
    end
    addon.debug = self.db.profile.debug
    addon.debugOptions = self.db.profile.debugOptions
    addon.syncResponses = {
            message = '',
            requester = ''
        }
    addon.wishlist = {
            table = {},
        }
    addon.tooltip = self.db.profile.tooltip
    addon.guildRank = bypassRank
    addon.loaded = false
end

--- Called by Ace3 when addon is enabled.
function addon:OnEnabled()
end

--- Called by Ace3 when addon is disabled.
function addon:OnDisable()
    
end

function addon:PerformUpgrades()
    -- If we are already up-to-date, no need to perform any upgrades
    if self:CompareVersion(self.db.global.version, addon.version) == 0 then
        return
    end

    -- Find which version step we are on
    local stepIndex = 0
    local lowestVersionFound = false
    local versionSteps = addon.CONSTANTS.versionSteps
    for i =1, #versionSteps, 1 do
        local addonVersionStep = versionSteps[i]
        if not lowestVersionFound and self:CompareVersion(self.db.global.version, addonVersionStep) == -1 then
            stepIndex = i
            lowestVersionFound = true
        end
    end
    if stepIndex > 0 then
        for i = stepIndex, #versionSteps, 1 do
            if i == 1 then self:UpgradeTo_0_5_2() end
            if i == 2 then self:UpgradeTo_0_6_0() end
            if i == 3 then self:UpgradeTo_0_7_0() end
            if i == 4 then self:UpgradeTo_0_8_11() end
        end
    end
    self.db.global.version = self.version
    addon.version = self.version
    version = self.version
end

function addon:RegisterCallbacks()
    self:RegisterMessage(aceCommMessages.processPlayers, 'ProcessSyncResponses')
    self:RegisterMessage(aceCommMessages.processGuildReplies, 'ProcessGuildReplies')
    self:RegisterMessage(aceCommMessages.tooltipOptionsChanged, 'UpdateTooltip')
end

function addon:RegisterComms()
    self:RegisterComm(addonName, "OnCommReceived")
    self:RegisterComm(aceCommPrefixes.sync, "OnSyncDataReceived")
    self:RegisterComm(aceCommPrefixes.syncRequest, "OnSyncRequestReceived")
    self:RegisterComm(aceCommPrefixes.syncResponse, "OnSyncResponseReceived")
    self:RegisterComm(aceCommPrefixes.chosenForSync, "OnSyncAcceptedReceived")

    self:RegisterComm(aceCommPrefixes.getBestTimestamp, "OnBestTimestampReceived")
    self:RegisterComm(aceCommPrefixes.chosenForGuildReply, "OnChosenForGuildReply")
    self:RegisterComm(aceCommPrefixes.getBestTimestampReceived, "OnBestTimestampRequested")

    self:RegisterComm(aceCommPrefixes.wishlistSync, "OnWishlistSyncReceived")
    self:RegisterComm(aceCommPrefixes.wishlistSyncResponse, "OnWishlistSyncResponseReceived")
    self:RegisterComm(aceCommPrefixes.wishlistChosenForSync, "OnWishlistSyncAcceptedReceived")
end

function addon:RegisterDB()
    local defaults = {
        factionrealm = {
            banks = {},
            versionCheck = version,
            personalWishlist = {},
            wishlistGuildToPersonalMigrated = false
        },
        char = {
            personal = {
                shareBags = false,
                shareBank = true
            },
            sync = {
                lastAutoSync = 0
            },
            banking = {
                bags = false,
                bank = false,
                money = false
            }
        },
        profile = {
            showAsItemView = true,
            showCombinedBagsBank = true,
            qualityFilters = {
                bankingQuality = -1, -- -1=all, 0..5 strict match
                personalQuality = -1,
            },
            itemRarities = {
                poor = true,
                common = true,
                uncommon = true,
                rare = true,
                epic = true,
                legendary = true
            },
            blacklist = {},
            whitelist = {},
            debug = superdev,
            debugOptions = {
                enableSync = true
            },
            debugItems = {},
            minimap = {
                hide = false
            },
            tooltip = {
                show = true,
                showBorder = true,
                colour = {
                    r = 0,
                    g = 150,
                    b = 150,
                    a = 0.5
                }
            },
            loaded = true
        },
        global = {
            version = nil
        }
    }
    self.db = LibStub("AceDB-3.0"):New(addonName.."DB", defaults, true)
    -- Migration: older versions stored banking toggles in profile; move to per-character storage.
    self.db.char.banking = self.db.char.banking or {}
    if self.db.char.banking.bags == nil and self.db.profile.bags ~= nil then
        self.db.char.banking.bags = self.db.profile.bags
    end
    if self.db.char.banking.bank == nil and self.db.profile.bank ~= nil then
        self.db.char.banking.bank = self.db.profile.bank
    end
    if self.db.char.banking.money == nil and self.db.profile.money ~= nil then
        self.db.char.banking.money = self.db.profile.money
    end

    setmetatable(self.db.factionrealm.banks,
    {
        __index = function (table, key)
            if key == nil then
                return nil
            end
            local bankTbl = { players = {}, wishlist = {} }
            setmetatable(bankTbl.wishlist, {
                __index = function ()
                    return nil
                end
            })
            table[key] = bankTbl
            return bankTbl
        end
    });
    if not self.db.global.version then self.db.global.version = addon.version end
    addon.profile = self.db.profile
end

function addon:RegisterEvents()
    GameTooltip:HookScript("OnTooltipSetItem", function(self)
         addon:ShowWishlistInfoTooltip()
         addon:UpdateTooltip()
    end)
    self:RegisterEvent("BANKFRAME_OPENED")
    self:RegisterEvent("CHAT_MSG_WHISPER")
    self:RegisterEvent("MAIL_INBOX_UPDATE")
    self:RegisterEvent("MAIL_SEND_SUCCESS")
    self:RegisterEvent("BAG_UPDATE_DELAYED")
    self:RegisterEvent("CHAT_MSG_GUILD")
    self:RegisterEvent("GET_ITEM_INFO_RECEIVED")
end

--- Succès tardif après RequestLoadItemDataByID ou cache client (wishlist bloquée sur "loading").
function addon:GET_ITEM_INFO_RECEIVED(event, itemID, success)
    if success == false then return end
    local id = tonumber(itemID)
    if not id then return end
    local p = self._wishlistPendingAdd
    if not p or p.baseId ~= id then return end
    self._wishlistPendingAdd = nil
    local nextRetry = (p.attempts or 0) + 1
    if nextRetry > 5 then return end
    self:WishlistSubmitEnteredText(p.rawText, p.rowsContainer, nextRetry)
end

function addon:WishlistQueueRetryAfterLoad(baseId, value, rowsContainer, retryDepth)
    retryDepth = retryDepth or 0
    if retryDepth >= 5 then return false end
    self._wishlistPendingAdd = {
        baseId = baseId,
        rawText = value,
        rowsContainer = rowsContainer,
        attempts = retryDepth,
    }
    if C_Item and C_Item.RequestLoadItemDataByID then
        C_Item.RequestLoadItemDataByID(baseId)
    end
    return true
end

function addon:RegisterOptions()
    local icon = addon.LIBS.icon
    local options = {
        type = "group",
        args = {
            general = {
                type = 'group',
                name = 'General',
                args = {
                    showMinimapIcon = {
                        type = "toggle",
                        name = "Show minimap icon",
                        desc = "Toggle show/hide minimap icon",
                        get = function(info) return not self.db.profile.minimap.hide end,
                        set = function(info, val) 
                            self.db.profile.minimap.hide = not val;
                            if val then
                                icon:Show(addonName)
                            else
                                icon:Hide(addonName)
                            end
                        end,
                        order = 1
                    },
                    enableSync = {
                        type = "toggle",
                        name = "Receive guild bank data from other players",
                        desc = "Enable receiving updates to the guild bank from other logged-in guild members.",
                        order = 2,
                        width = "full",
                        get = function(info) return addon.debugOptions.enableSync end,
                        set = function(info, val)
                            addon.debugOptions.enableSync = val
                            self.db.profile.debugOptions.enableSync = val
                        end
                    },
                    tooltipTitle = {
                        type = "header",
                        name = "Tooltip",
                        order = 3,
                    },
                    showTooltip = {
                        type = 'toggle',
                        name = 'Show tooltip',
                        get = function(info)
                            return self.db.profile.tooltip.show
                        end,
                        set = function(info, value)
                            self.db.profile.tooltip.show = value
                        end,
                        order = 4
                    },
                    showItemBorder = {
                        type = 'toggle',
                        name = 'Highlight wishlisted items',
                        get = function(info)
                            return self.db.profile.tooltip.showBorder
                        end,
                        set = function(info, value)
                            self.db.profile.tooltip.showBorder = value
                        end,
                        order = 5
                    },
                    tooltipColour = {
                        type = 'color',
                        name = 'Item highlight colour',
                        hasAlpha = true,
                        get = function(info)
                            local colour = self.db.profile.tooltip.colour
                            return colour.r, colour.g, colour.b, colour.a
                        end,
                        set = function(info, r, g, b, a)
                            self.db.profile.tooltip.colour = {
                                r = r,
                                g = g,
                                b = b,
                                a = a
                            }
                            addon.tooltip.colour = {
                                r = r,
                                g = g,
                                b = b,
                                a = a
                            }
                        end,
                        order = 6
                    },
                    containerTitle = {
                        type = "header",
                        name = "Character containers to include in the bank",
                        order = 7
                    },
                    includeBags = {
                        type = "toggle",
                        name = "Bags",
                        desc = "Catalogue all items in your character's bags",
                        confirm = function() return self:DisplayConfirmationForBags() end,
                        get = function(info) return self.db.char.banking and self.db.char.banking.bags end,
                        set = function(info,val)
                            self.db.char.banking = self.db.char.banking or {}
                            self.db.char.banking.bags = val
                            if not val then
                                self:RemoveItemsFromBags()
                            end
                        end,
                        order = 8
                    },
                    includeBank = {
                        type = "toggle",
                        name = "Bank",
                        desc = "Catalogue all items in your character's bank",
                        confirm = function() return self:DisplayConfirmationForBank() end,
                        get = function(info) return self.db.char.banking and self.db.char.banking.bank end,
                        set = function(info,val)
                            self.db.char.banking = self.db.char.banking or {}
                            self.db.char.banking.bank = val
                            if not val then
                                self:RemoveItemsFromBank()
                            end
                        end,
                        order = 9
                    },
                    includeMoney = {
                        type = "toggle",
                        name = "Gold",
                        desc = "Include gold",
                        confirm = function() return self:DisplayConfirmationForMoney() end,
                        get = function(info) return self.db.char.banking and self.db.char.banking.money end,
                        set = function(info,val)
                            self.db.char.banking = self.db.char.banking or {}
                            self.db.char.banking.money = val
                            if val then
                                self:UpdateGold()
                            else
                                self:RemoveMoneyFromBank()
                            end
                        end,
                        order = 10
                    },
                    personalTitle = {
                        type = "header",
                        name = "Personal tab snapshot",
                        order = 11
                    },
                    personalShareBank = {
                        type = "toggle",
                        name = "Personal: Bank",
                        desc = "Include THIS character's bank contents in the Personal tab (account-wide view).",
                        get = function() return self.db.char.personal and self.db.char.personal.shareBank end,
                        set = function(_, v)
                            self.db.char.personal = self.db.char.personal or {}
                            self.db.char.personal.shareBank = v
                        end,
                        order = 12
                    },
                    personalShareBags = {
                        type = "toggle",
                        name = "Personal: Bags",
                        desc = "Include THIS character's bag contents in the Personal tab (account-wide view).",
                        get = function() return self.db.char.personal and self.db.char.personal.shareBags end,
                        set = function(_, v)
                            self.db.char.personal = self.db.char.personal or {}
                            self.db.char.personal.shareBags = v
                        end,
                        order = 13
                    }
                }
            },
            items= {
                name = "Items",
                type = "group",
                args = {
                    title = {
                        type = "header",
                        name = "Item rarities to include in the bank",
                        order = 1
                    },
                    includePoor = {
                        type = "toggle",
                        name = "|cff9d9d9dPoor|r",
                        desc = "Include |cff9d9d9dpoor|r quality items",
                        order = 2,
                        confirm = function() return self:DisplayConfirmationForQuality('poor') end,
                        get = function(info) return self.db.profile.itemRarities['poor'] end,
                        set = function(info, val)
                            self.db.profile.itemRarities['poor'] = val
                            if not val then
                                self:RemoveItemsByQuality(0)
                            end
                        end
                    },
                    includeCommon = {
                        type = "toggle",
                        name = "|cffffffffCommon|r",
                        desc = "Include |cffffffffcommon|r quality items",
                        order = 3,
                        confirm = function() return self:DisplayConfirmationForQuality('common') end,
                        get = function(info) return self.db.profile.itemRarities['common'] end,
                        set = function(info, val)
                            self.db.profile.itemRarities['common'] = val
                            if not val then
                                self:RemoveItemsByQuality(1)
                            end
                        end
                    },
                    includeUncommon = {
                        type = "toggle",
                        name = "|cff1eff00Uncommon|r",
                        desc = "Include |cff1eff00uncommon|r quality items",
                        order = 4,
                        confirm = function() return self:DisplayConfirmationForQuality('uncommon') end,
                        get = function(info) return self.db.profile.itemRarities['uncommon'] end,
                        set = function(info, val)
                            self.db.profile.itemRarities['uncommon'] = val
                            if not val then
                                self:RemoveItemsByQuality(2)
                            end
                        end
                    },
                    includeRare = {
                        type = "toggle",
                        name = "|cff0070ddRare|r",
                        desc = "Include |cff0070ddrare|r quality items",
                        order = 5,
                        confirm = function() return self:DisplayConfirmationForQuality('rare') end,
                        get = function(info) return self.db.profile.itemRarities['rare'] end,
                        set = function(info, val)
                            self.db.profile.itemRarities['rare'] = val
                            if not val then
                                self:RemoveItemsByQuality(3)
                            end
                        end
                    },
                    includeEpic = {
                        type = "toggle",
                        name = "|cffa335eeEpic|r",
                        desc     = "Include |cffa335eeepic|r quality items",
                        order = 6,
                        confirm = function() return self:DisplayConfirmationForQuality('epic') end,
                        get = function(info) return self.db.profile.itemRarities['epic'] end,
                        set = function(info, val)
                            self.db.profile.itemRarities['epic'] = val
                            if not val then
                                self:RemoveItemsByQuality(4)
                            end
                        end
                    },
                    includeLegendary = {
                        type = "toggle",
                        name = "|cffff8000Legendary|r",
                        desc = "Include |cffff8000legendary|r quality items",
                        order = 7,
                        confirm = function() return self:DisplayConfirmationForQuality('legendary') end,
                        get = function(info) return self.db.profile.itemRarities['legendary'] end,
                        set = function(info, val)
                            self.db.profile.itemRarities['legendary'] = val
                            if not val then
                                self:RemoveItemsByQuality(5)
                            end
                        end
                    },
                    allowListsTitle = {
                        type = "header",
                        name = "Whitelist | Blacklist",
                        order = 8
                    },
                    whitelistInput = {
                        type = "input",
                        name = "Add item to whitelist",
                        order = 9,
                        set = function(info, val) 
                            local itemIdWithSuffix = self:ConvertHyperLinkToItemId(val)
                            if not self.db.profile.whitelist[itemIdWithSuffix] and not self.db.profile.blacklist[itemIdWithSuffix] then
                                self.db.profile.whitelist[itemIdWithSuffix] = true
                            end
                        end
                    },
                    blacklistInput = {
                        type = "input",
                        name = "Add item to blacklist",
                        order = 11,
                        set = function(info, val) 
                            local itemIdWithSuffix = self:ConvertHyperLinkToItemId(val)
                            if not self.db.profile.whitelist[itemIdWithSuffix] and not self.db.profile.blacklist[itemIdWithSuffix] then
                                self.db.profile.blacklist[itemIdWithSuffix] = true
                                self:RemoveItemFromBank(itemIdWithSuffix)
                            end
                        end
                    },
                    whitelistList = {
                        type = "input",
                        name = "Whitelist",
                        order = 10,
                        multiline = 5,
                        width = "full",
                        get = function() 
                            local input = ""
                            for value, _ in pairs(self.db.profile.whitelist) do
                                if input == "" then
                                    input = value.."\n"
                                else
                                    input = input ..""..value .. "\n"
                                end
                            end
                            return input
                        end,
                        set = function(info, val)
                            local matches = {strsplit('\n', val)}
                            local emptyMatches = 0
                            for _, value in ipairs(matches) do
                                if value == "" then
                                    emptyMatches = emptyMatches + 1
                                else
                                    self.db.profile.whitelist[value] = true 
                                end
                            end
                            if emptyMatches == #matches then
                                self.db.profile.whitelist = {}
                            end
                        end
                    },
                    blacklistList = {
                        type = "input",
                        name = "Blacklist",
                        order = 12,
                        multiline = 5,
                        width = "full",
                        get = function() 
                            local input = ""
                            for value, _ in pairs(self.db.profile.blacklist) do
                                if input == "" then
                                    input = value .. "\n"
                                else
                                    input = input .. ""..value .. "\n"
                                end
                            end
                            return input
                        end,
                        set = function(info, val)
                            local matches = {strsplit('\n', val)}
                            local emptyMatches = 0
                            for _, value in ipairs(matches) do
                                if value == "" then
                                    emptyMatches = emptyMatches + 1
                                else
                                    self.db.profile.blacklist[value] = true
                                    self:RemoveItemFromBank(value)
                                end
                            end
                            if emptyMatches == #matches then
                                self.db.profile.blacklist = {}
                            end
                        end
                    }
                },
            },
            debugOptions = {
                name = "Debug",
                type = "group",
                args = {
                    debug = {
                        type = "toggle",
                        name = "Debug mode",
                        desc = "Enable debug messages",
                        order = 1,
                        get = function(info) return addon.debug end,
                        set = function(info, val) 
                            addon.debug = val
                            self.db.profile.debug = val 
                        end
                    }
                }
            }
        }
    }

    LibStub('AceConfig-3.0'):RegisterOptionsTable(addonName, options)
    ACD:AddToBlizOptions(addonName, addonName, nil, 'general')
    ACD:AddToBlizOptions(addonName, 'Items', addonName, 'items')
    ACD:AddToBlizOptions(addonName, 'Debug', addonName, 'debugOptions')
    icon:Register(addonName, addon.LIBS.libDB, self.db.profile.minimap)
end

function addon:OnCommReceived(prefix, message, distribution, sender)
    local playerName = UnitNameUnmodified("player")
    if sender == playerName then return end

    self:Print("Prefix: "..prefix.. " Message: "..message.." Distribution: "..distribution.." Sender: "..sender)
end

--- Called when this player receives a sync request from another player. Will respond with this player's last sync time for the requested bank.
function addon:OnSyncRequestReceived(prefix, message, distribution, sender)
    local playerName = UnitNameUnmodified("player")
    if not addon.loaded then
        self:TryLoadGuild()
    end
    if sender == playerName then return end
    
    local success, response = self:Deserialize(message)
    self:UpdateVersionsTable(sender, response.version)
    self:Debug("Received sync request from "..sender.." for "..response.version)

    if not response.version or not (tostring(response.version) == tostring(version)) then
        self:Debug(sender.. ' has an outdated version.')
        return
    end
    
    local bank = self:GetBank(response.data)
    if bank then
        local playerLastSyncs = {}
        for player, data in pairs(bank.players) do
            playerLastSyncs[player] = data.lastSync
        end
        local data = self:Serialize({
            version = version,
            data = playerLastSyncs
        })
        self:SendCommMessage(aceCommPrefixes.syncResponse, data, "WHISPER", sender)
    end
end

local syncEvents = {}
--- Called when another player responds to a sync request. Will respond with that player's last sync time for the requested bank.
function addon:OnSyncResponseReceived(prefix, message, distribution, sender)
    local playerName = UnitNameUnmodified("player")
    if not addon.loaded then
        self:TryLoadGuild()
    end
    if sender == playerName then return end

    self:Debug("Received lastSync response from "..sender)
    
    local success, response = self:Deserialize(message)
    self:UpdateVersionsTable(sender, response.version)

    if not response.version or not (tostring(response.version) == tostring(version)) then
        self:Debug(sender.. ' has an outdated version.')
        return
    end

    syncEvents[sender] = response.data
end

--- Called when this player receives sync data from another player.
function addon:OnSyncDataReceived(prefix, message, distribution, sender)
    self:Debug("BEGIN streaming data from "..sender)
    local playerName = UnitNameUnmodified("player")
    if not addon.loaded then
        self:TryLoadGuild()
    end
    if sender == playerName then return end

    local success, response = self:Deserialize(message)
    self:UpdateVersionsTable(sender, response.version)

    if not response.version or not (tostring(response.version) == tostring(version)) then
        self:Debug(sender.. ' has an outdated version.')
        addon.syncInProgress = false
        return
    end
    if not success then
        self:Debug("Error receiving sync data from "..sender)
        addon.syncInProgress = false
        return
    end

    local bankName = self:GetBankName()
    local bank = self:GetBank(bankName)
    if not bank then
        bank = {
            players = {},
            lastSync = GetServerTime()
        }
    end
    for bankPlayerName, data in pairs(response.data) do
        self:SetPlayerData(bankName, bankPlayerName, data)
    end
    addon.syncInProgress = false
    self:Print("END streaming data. Bank data received from "..sender)
    self:RefreshWishlistTabBadge()
end

--- Called when this player's sync data is the most up-to-date of all players. Sends this player's data to the requesting player.
function addon:OnSyncAcceptedReceived(prefix, message, distribution, sender)
    local playerName = UnitNameUnmodified("player")
    if not addon.loaded then
        self:TryLoadGuild()
    end
    if sender == playerName then return end
    local bankName = self:GetBankName()
    if not bankName then return end

    self:Debug("Sending banking data to "..sender)
    
    local success, response = self:Deserialize(message)
    self:UpdateVersionsTable(sender, response.version)

    if not response.version or not (tostring(response.version) == tostring(version)) then
        self:Debug(sender.. ' has an outdated version.')
        return
    end
    local playerData = {}
    for _, playerId in pairs(response.data) do
        playerData[playerId] = self:GetBankPlayer(bankName, playerId)
    end
    local serializedData = self:Serialize({
        version = version,
        data = playerData
    })
    self:SendCommMessage(aceCommPrefixes.sync, serializedData, "WHISPER", sender)
end

local guildSyncEvents = {}
--- Called when a player is reqesting an item in guild chat.
function addon:OnBestTimestampReceived(prefix, message, distribution, sender)
    local playerName = UnitNameUnmodified("player")
    if not addon.loaded then
        self:TryLoadGuild()
    end
    if sender == playerName then return end

    self:Debug("Received GUILD lastSync response from "..sender)

    local success, response = self:Deserialize(message)
    self:UpdateVersionsTable(sender, response.version)

    if not response.version or not (tostring(response.version) == tostring(version)) then
        self:Debug(sender.. ' has an outdated version.')
        return
    else
        guildSyncEvents[sender] = response.data
    end

end

function addon:OnBestTimestampRequested(prefix, message, distribution, sender)
    local playerName = UnitNameUnmodified("player")
    if not addon.loaded then
        self:TryLoadGuild()
    end
    if sender == playerName then return end

    local success, response = self:Deserialize(message)
    self:UpdateVersionsTable(sender, response.version)

    if not response.version or not (tostring(response.version) == tostring(version)) then
        self:Debug(sender.. ' has an outdated version.')
        return
    end
    
    if addon.debug then self:Print("Received guild request from "..sender.." for "..response.data) end
    
    local bankDb = self:GetBank(response.data)
    if bankDb and bankDb.lastSync then
        local seri = self:Serialize({
            version = version,
            data = tostring(bankDb.lastSync)
        })
        self:SendCommMessage(aceCommPrefixes.getBestTimestampReceived, seri, "WHISPER", sender)
    else
        if addon.debug then self:Print("[WARNING] lastSync does not exist!") end
    end
end

function addon:OnChosenForGuildReply(prefix, message, distribution, sender)
    local playerName = UnitNameUnmodified("player")
    if not addon.loaded then
        self:TryLoadGuild()
    end
    if sender == playerName then return end

    local success, response = self:Deserialize(message)
    self:UpdateVersionsTable(sender, response.version)

    if not response.version or not (tostring(response.version) == tostring(version)) then
        self:Debug(sender.. ' has an outdated version.')
        return
    end

    self:AutoWhisperRequestedItemBankQty(addon.syncResponses.message, addon.syncResponses.requester, self.db.factionrealm.banks[response.data].lastSync)
end

function addon:OnWishlistSyncResponseReceived(prefix, message, distribution, sender)
    -- Wishlist is personal per-account; guild wishlist sync is deprecated.
end

function addon:OnWishlistSyncReceived(prefix, message, distribution, sender)
    -- Wishlist is personal per-account; ignore incoming guild wishlist payloads.
end

function addon:OnWishlistSyncAcceptedReceived(prefix, message, distribution, sender)
    local playerName = UnitNameUnmodified("player")
    if not addon.loaded then
        self:TryLoadGuild()
    end
    if sender == playerName then return end

    self:Debug("Wishlist sync request from "..sender.." — replying empty (personal wishlist)")
    local success, response = self:Deserialize(message)
    if not success or not response then return end
    if response.version and tostring(response.version) ~= tostring(version) then return end

    local serializedData = self:Serialize({
        version = version,
        data = { lastSync = GetServerTime() }
    })
    self:SendCommMessage(aceCommPrefixes.wishlistSync, serializedData, "WHISPER", sender)
end

function addon:BANKFRAME_OPENED()
    if not addon.loaded then return end
    self:UpdateAllContainers()
end

function addon:BAG_UPDATE_DELAYED()
    if not addon.loaded then return end
    self:UpdateBags()
    self:UpdateGold()
    self:HighlightBagItems()
end

function addon:MAIL_SEND_SUCCESS()
    if not addon.loaded then return end
    self:UpdateBags()
    self:UpdateGold()
end

function addon:MAIL_INBOX_UPDATE()
    if not addon.loaded then return end
    self:UpdateBags()
    self:UpdateGold()
end

function addon:CHAT_MSG_WHISPER(event, text, playerName, ...)
    if not addon.loaded then return end
    local bankName = self:GetBankName()
    if not bankName then return end
    self:AutoWhisperRequestedItemBankQty(text, playerName, self.db.factionrealm.banks[bankName].lastSync)
end

function addon:TryLoadGuild()
    self:UpgradeTo_0_8_13()
    local localPlayerName, localPlayerRealm = UnitFullName("player")
    local fullName = localPlayerName..'-'..localPlayerRealm
    addon.bank = self:GetBank(self:GetBankName())
    self:MigrateGuildWishlistToPersonalIfNeeded()
    self:Print(ChatFrame1, version.." loaded")
    addon.loaded = true
    if addon.debugOptions.enableSync and not superdev then
        local now = GetServerTime()
        local last = (self.db.char and self.db.char.sync and self.db.char.sync.lastAutoSync) or 0
        if type(last) ~= "number" then last = 0 end
        if (now - last) >= (15 * 60) then
            self:SyncWithPlayers(true)
        end
    end
    if self.db.profile.tooltip.showBorder then
        self:UpdateTooltip()
    end
    if addon.guildRank == 1000 then
        local rank = C_GuildInfo.GetGuildRankOrder(playerGuid)
        addon.guildRank = rank
    end
    self:RefreshWishlistTabBadge()
end

function addon:UpdateVersionsTable(key, playerVersion)
    if not self.db.factionrealm.versionCheck and self:CompareVersion(playerVersion, self.db.factionrealm.versionCheck) < 0 then
        self.db.factionrealm.versionCheck = version
        local frame = AceGUI:Create('Frame')
        frame:SetCallback("OnClose", function(widget) AceGUI:Release(widget) end)
        frame:SetWidth(400)
        frame:SetHeight(100)
        local text = AceGUI:Create('Label')
        text:SetText("Your addon is out of date.")
        frame:AddChild(text)
    else
        addon.versions.args[key] = {
            type = 'group',
            inline = true,
            name = '',
            args = {
                name = {
                    type = 'description',
                    name = key,
                    width = 1,
                    order = 1
                },
                version = {
                    type = 'description',
                    name = playerVersion,
                    width = 1,
                    order = 2
                }
            }
        }
    end
end

function addon:CHAT_MSG_GUILD(event, message, playerName)
    local localPlayerName, localPlayerRealm = UnitFullName("player")
    if not addon.loaded then
        self:TryLoadGuild()
    end
    if playerName == localPlayerName.."-"..localPlayerRealm then
        return
    end
    local bankName = self:GetBankName()
    if addon.playerSyncAttempted then
        if not bankName then
            addon.loaded = false
            self.db.profile.loaded = false
        else
            addon.playerSyncAttempted = false
            self.db.profile.loaded = true
            self:SyncWithPlayers()
        end
    end
    local queryChar = strsub(message, 1, 1)
    if queryChar ~= "$" then return end
    local myTimestamp = nil
    if self.db.factionrealm.banks[bankName] and self.db.factionrealm.banks[bankName].lastSync then
        if not self.db.factionrealm.banks[bankName].lastSync then return end

        myTimestamp = self.db.factionrealm.banks[bankName].lastSync
    else
        return 
    end
    addon.syncResponses.message = message
    addon.syncResponses.requester = playerName
    self:Debug("Received item request from "..playerName)
    
    local serializedData = self:Serialize({ version = version, data = { timestamp = myTimestamp, replyFor = playerName }})
    self:SendCommMessage(aceCommPrefixes.getBestTimestamp, serializedData, "GUILD")
    self:ScheduleTimer(function()
        self:SendMessage(aceCommMessages.processGuildReplies, playerName)
     end, 5)
end

function addon:ProcessGuildReplies(event, target)
    self:Debug("Processing guild reply response...")

    local bankName = self:GetBankName()
    local bestSync = 0
    
    if self.db.factionrealm.banks[bankName] and self.db.factionrealm.banks[bankName].lastSync then
        if self.db.factionrealm.banks[bankName].lastSync then
            bestSync = self.db.factionrealm.banks[bankName].lastSync
        end
    end

    for _, data in pairs(guildSyncEvents) do
        if data.replyFor == nil then return end
        if data.replyFor == target then
            if bestSync < data.timestamp then
                guildSyncEvents = {}
                return
            end
        end
    end

    self:Debug("Sending reply to "..target)
    self:AutoWhisperRequestedItemBankQty(addon.syncResponses.message, target, bestSync)
    guildSyncEvents = {}
end

--- Processes the list of received syncesponses
function addon:ProcessSyncResponses()
    
    local bankName = self:GetBankName()
    if not bankName then
        syncEvents = {}
        return
    end
    
    local bank = self:GetBank(bankName)
    if not bank then
        syncEvents = {}
        return
    end

    addon.syncInProgress = true
    local bestSyncs = {}
    setmetatable(bestSyncs, {
        __index = function()
            return nil
        end
    })

    for syncPlayer, data in pairs(syncEvents) do
        self:Debug("Computing diff for "..syncPlayer)
        for syncLocalPlayer, lastSync in pairs(data) do
            if type(lastSync) == 'number' then
                local bestPlayerSync = bestSyncs[syncLocalPlayer]
                local bestRequesterPlayer = bank.players[syncLocalPlayer]
                if bestPlayerSync then
                    if not bestRequesterPlayer or bestPlayerSync.info > bestRequesterPlayer.lastSync then
                        bestSyncs[syncLocalPlayer] = {
                            sender = syncPlayer,
                            info = lastSync
                        }
                    end
                else
                    -- If we've not seen a best sync for this player, check if this one is better than us. If yes, add it to the table
                    if not bestRequesterPlayer or (bestRequesterPlayer and not bestRequesterPlayer[lastSync]) or bestRequesterPlayer.lastSync < lastSync then
                        bestSyncs[syncLocalPlayer] = {
                            sender = syncPlayer,
                            info = lastSync
                        }
                    end
                end
            end
        end
    end

    -- Tell the most recent synced character to send over their data
    local playersBySender = {}
    for playerId, syncInfo in pairs(bestSyncs) do
        self:Debug("Processing ".. syncInfo.sender)
        if not playersBySender[syncInfo.sender] then
            playersBySender[syncInfo.sender] = { playerId }
        else
            tinsert(playersBySender[syncInfo.sender], playerId)
        end
    end

    if #playersBySender == 0 then
        addon.syncInProgress = false
    end
    for sender, data in pairs(playersBySender) do
        self:Debug("Requesting data from "..sender.." for ".. #data.." local players")
        local playerNames = self:Serialize({ version = version, data = data })
        self:SendCommMessage(aceCommPrefixes.chosenForSync, playerNames, "WHISPER", sender)
    end
    syncEvents = {}
end

function addon:UpdateTooltip()

    self:HighlightBagItems()
    self:HighlightBankItems()
end

function addon:RemoveItemsFromBags()
    local bankName = self:GetBankName()
    if not self.db.factionrealm.banks[bankName] then return end
    if not self.db.factionrealm.banks[bankName].players[playerGuid] then return end
    local debugCnt = #self.db.factionrealm.banks[bankName].players[playerGuid].bags
    self.db.factionrealm.banks[bankName].players[playerGuid].bags = {}
    self.db.factionrealm.banks[bankName].players[playerGuid].lastSync = GetServerTime()
    self:Debug("Removed "..debugCnt.." items!")
end

function addon:RemoveItemsFromBank()
    local bankName = self:GetBankName()
    if not self.db.factionrealm.banks[bankName] then return end
    if not self.db.factionrealm.banks[bankName].players[playerGuid] then return end
    local debugCnt = #self.db.factionrealm.banks[bankName].players[playerGuid].bank
    self:Debug("Removed "..debugCnt.." items!")
    self.db.factionrealm.banks[bankName].players[playerGuid].bank = {}
    self.db.factionrealm.banks[bankName].players[playerGuid].lastSync = GetServerTime()
end

function addon:RemoveItemFromBank(itemId)
    local itemIdAsNumber = tonumber(itemId)
    if itemIdAsNumber then itemId = itemIdAsNumber end
    local bankName = self:GetBankName()
    if not self.db.factionrealm.banks[bankName] then return end
    self.db.factionrealm.banks[bankName].players[playerGuid].bank[itemId] = nil
    self.db.factionrealm.banks[bankName].players[playerGuid].bags[itemId] = nil
    self:Debug("Removed "..itemId.."!")
end

function addon:RemoveMoneyFromBank()
    local bankName = self:GetBankName()
    if not self.db.factionrealm.banks[bankName] then return end
    if not self.db.factionrealm.banks[bankName].players[playerGuid] then return end
    local debugCnt = self.db.factionrealm.banks[bankName].players[playerGuid].money or 0
    self.db.factionrealm.banks[bankName].players[playerGuid].money = 0
    self:Debug("Removed "..GetMoneyString(debugCnt).." from the bank!")
    self.db.factionrealm.banks[bankName].players[playerGuid].lastSync = GetServerTime()
end

--- Removes all the items from the database that match the quality enum.
function addon:RemoveItemsByQuality(quality)
    local bankName = self:GetBankName()
    local debugCnt = 0
    if not self.db.factionrealm.banks[bankName] then return end

    self:Debug("Removing all "..rarities[quality+1].." items...")
    local playerBank = self.db.factionrealm.banks[bankName].players[playerGuid]
    for itemId, item in pairs(playerBank.bags or {}) do
        if item.quality and item.quality == quality then
            self.db.factionrealm.banks[bankName].players[playerGuid].bags[itemId] = nil
            debugCnt = debugCnt + 1
        end
    end
    for itemId, item in pairs(playerBank.bank or {}) do
        if item.quality and item.quality == quality then
            self.db.factionrealm.banks[bankName].players[playerGuid].bank[itemId] = nil
            debugCnt = debugCnt + 1
        end
    end

    self:Debug("Removed "..debugCnt.." items!")
    self.db.factionrealm.banks[bankName].players[playerGuid].lastSync = GetServerTime()
end


--[[------------------------------------------------------------------------------------
    TESTING
]]--------------------------------------------------------------------------------------

function addon:TestWhisper(...)
    local bankName = "AdvCoBank Test"
    local key = 4625
    self:SetBank(bankName)
    self:SetItem(bankName, playerGuid, 'bank', 'test', C_Container.GetContainerItemInfo(addon.CONSTANTS.containerSlots.bags[1], 1))
    local inventory, bank = self:GetItemByPlayer(bankName, playerGuid, 'test')
end

--- Updates the local player's bank DB with the contents of the bank.
function addon:UpdateBank()
    if not (self.db.char and self.db.char.banking and self.db.char.banking.bank) then return end
    if not addon.loaded then
        self:Print("Guild data not yet available. Wait before trying again.")
        return
    end
    local playerName = UnitNameUnmodified("player")
    local bankName = self:GetBankName()
    if not bankName then return end
    self:EnsureBankExists(bankName)

    if not self.db.factionrealm.banks[bankName].players[playerGuid] then
        self.db.factionrealm.banks[bankName].players[playerGuid] = {
            name = playerName
        }
    end

    -- Loop through the bank available slots and catalogue every tradeable item
    local bankContents = self:GenerateBankContentsTable()
    self.db.factionrealm.banks[bankName].players[playerGuid].bank = bankContents
    self.db.factionrealm.banks[bankName].players[playerGuid].lastSync = GetServerTime()
    self:Debug("Bank contents updated")
end

function addon:UpdateGold()
    if not (self.db.char and self.db.char.banking and self.db.char.banking.money) then return end
    if not addon.loaded then
        self:Print("Guild data not yet available. Wait before trying again.")
        return
    end
    local playerName = UnitNameUnmodified("player")
    local bankName = self:GetBankName()
    if not bankName then return end
    self:EnsureBankExists(bankName)

    if not self.db.factionrealm.banks[bankName].players[playerGuid] then
        self.db.factionrealm.banks[bankName].players[playerGuid] = {
            name = playerName
        }
    end

    local money = GetMoney()
    self.db.factionrealm.banks[bankName].players[playerGuid].money = money
    self.db.factionrealm.banks[bankName].players[playerGuid].lastSync = GetServerTime()
    self:Debug("Gold updated")
end

--- Updates the local player's bank DB with the contents of the bags.
function addon:UpdateBags()
    if not (self.db.char and self.db.char.banking and self.db.char.banking.bags) then return end
    if not addon.loaded then
        self:Print("Guild data not yet available. Wait before trying again.")
        return
    end
    local playerName = UnitNameUnmodified("player")
    local bankName = self:GetBankName()
    if not bankName then return end
    self:EnsureBankExists(bankName)

    if not self.db.factionrealm.banks[bankName].players[playerGuid] then
        self.db.factionrealm.banks[bankName].players[playerGuid] = {
            name = playerName
        }
    end

    -- Loop through the bag available slots and catalogue every tradeable item
    local bagContents = self:GenerateBagContentsTable()
    self.db.factionrealm.banks[bankName].players[playerGuid].bags = bagContents
    self.db.factionrealm.banks[bankName].players[playerGuid].lastSync = GetServerTime()
    self:Debug("Bag contents updated")
end

--- Updates the local player's bank DB with the contents of the bank and bags.
function addon:UpdateAllContainers()
    self:UpdateBags()
    self:UpdateBank()
    self:UpdateGold()
end

--- Whispers the specified playerName the quantity of the items they linked in a whisper prefixed with '$'
function addon:AutoWhisperRequestedItemBankQty(text, playerName, lastSync)
    local queryChar = strsub(text, 1, 1)
    local message = strsub(text, 2)
    if queryChar ~= "$" then return end
    local pattern = "|c[%a%d]+|Hitem[%d%a:]+|h%[[%a%s%'%-:]+%]|h|r"
    local matches = {}

    for capture in string.gmatch(message, pattern) do
        table.insert(matches, capture)
    end

    if #matches == 0 then return end

    local bankname = self:GetBankName()
    local bankItems = {}
    for i=1,#matches do
        local bankItem = self:HasItem(bankname, matches[i])
        if bankItem then
            table.insert(bankItems, bankItem)
        else
            table.insert(bankItems, { hyperlink = matches[i], stackCount = 0 })
        end
    end
    if #bankItems > 0 then
        local response = ""
        for i=1,#bankItems do
            local bitem = bankItems[i]
            if response == "" then
                response = bitem.hyperlink .. ": " .. bitem.stackCount
            else
                response = response.."  "..bitem.hyperlink..": "..bitem.stackCount
            end
        end
        local epoch = GetServerTime()
        local deltaSeconds = epoch - lastSync
        local lastSyncMessage = ''
        if deltaSeconds > 60 * 60 * 24 then
            lastSyncMessage = '(More than a day ago)'
        elseif deltaSeconds / 60 / 60 > 0 and deltaSeconds / 60 / 60 < 1 then
            lastSyncMessage = '(An hour ago)'
        else
            lastSyncMessage = '(More than an hour ago)'
        end
        if lastSync then
            SendChatMessage("----------- ITEMS IN "..bankname.." "..lastSyncMessage.." ------------", "WHISPER", nil, playerName)
        else
            SendChatMessage("----------- ITEMS IN "..bankname.." ------------", "WHISPER", nil, playerName)
        end        
        SendChatMessage(response, "WHISPER", nil, playerName)
    else
        SendChatMessage(bankname.." has none of your linked items.", "WHISPER", nil, playerName)
    end
end

--- Sync banking data with other players using inter-addon communication.
function addon:SyncWithPlayers(isAuto)
    self:Debug("Attempting to sync with players...")
    local bankName = self:GetBankName()
    if not bankName then
       addon.playerSyncAttempted = true
       return
    end
    if self.db and self.db.char then
        self.db.char.sync = self.db.char.sync or {}
        self.db.char.sync.lastAutoSync = GetServerTime()
    end
    local seri = self:Serialize({ version = version, data = bankName })
    self:SendCommMessage(aceCommPrefixes.syncRequest, seri, "GUILD")
    -- The OnSyncResponseReceived will listen to sync responses to determine which player with the most recent
    -- sync will share their data
    self:ScheduleTimer(function()
        self:Debug("Parsing sync data...")
        self:SendMessage(aceCommMessages.processPlayers)
     end, 10)
end

--[[------------------------------------------------------------------------------------
    CORE
]]--------------------------------------------------------------------------------------



--- Generates the bank's contents table
function addon:GenerateBankContentsTable()
    local function isBound(containerIndex, slotNumber, itemInfo)
        if itemInfo and itemInfo.isBound ~= nil then
            return itemInfo.isBound == true
        end
        -- Classic Era can omit isBound; fall back to C_Item.IsBound(ItemLocation)
        if C_Item and C_Item.IsBound and ItemLocation and ItemLocation.CreateFromBagAndSlot then
            local loc = ItemLocation:CreateFromBagAndSlot(containerIndex, slotNumber)
            if loc and loc.IsValid and loc:IsValid() then
                return C_Item.IsBound(loc) == true
            end
        end
        return false
    end

    local bankContents = {}
    for _, containerIndex in ipairs(containerSlots.bank) do
        for slotNumber = 1, C_Container.GetContainerNumSlots(containerIndex) do
            local item = C_Container.GetContainerItemInfo(containerIndex, slotNumber)
            if item then
                local suffixID = select(8, strsplit(':', item.hyperlink))
                local itemIdWithSuffix = item.itemID
                if suffixID ~= "" then
                    itemIdWithSuffix =  itemIdWithSuffix..":"..suffixID
                end
                local itemExistsAndIsTradeable = item and not isBound(containerIndex, slotNumber, item)
                local itemIsWhitelisted = self.db.profile.whitelist[itemIdWithSuffix]
                local itemIsBlacklisted = self.db.profile.blacklist[itemIdWithSuffix]
                if item.quality then
                    itemIsWhitelisted = itemIsWhitelisted or self.db.profile.itemRarities[rarities[item.quality + 1]]
                    itemIsBlacklisted = itemIsBlacklisted or not self.db.profile.itemRarities[rarities[item.quality + 1]]
                end
                if itemExistsAndIsTradeable and (itemIsWhitelisted or not itemIsBlacklisted) then
                    if not bankContents[itemIdWithSuffix] then bankContents[itemIdWithSuffix] = item
                    else bankContents[itemIdWithSuffix].stackCount = bankContents[itemIdWithSuffix].stackCount + item.stackCount end
                end
            end
        end
    end

    return bankContents
end

--- Generates the bag contents table
function addon:GenerateBagContentsTable()
    local function isBound(containerIndex, slotNumber, itemInfo)
        if itemInfo and itemInfo.isBound ~= nil then
            return itemInfo.isBound == true
        end
        if C_Item and C_Item.IsBound and ItemLocation and ItemLocation.CreateFromBagAndSlot then
            local loc = ItemLocation:CreateFromBagAndSlot(containerIndex, slotNumber)
            if loc and loc.IsValid and loc:IsValid() then
                return C_Item.IsBound(loc) == true
            end
        end
        return false
    end

    local bagContents = {}
    for _, containerIndex in ipairs(containerSlots.bags) do
        for slotNumber = 1, C_Container.GetContainerNumSlots(containerIndex) do
            local item = C_Container.GetContainerItemInfo(containerIndex, slotNumber)
            if item then
                local suffixID = select(8, strsplit(':', item.hyperlink))
                local itemIdWithSuffix = item.itemID
                if suffixID ~= "" then
                    itemIdWithSuffix =  itemIdWithSuffix..":"..suffixID
                end
                local itemExistsAndIsTradeable = item and not isBound(containerIndex, slotNumber, item)
                local itemIsWhitelisted = self.db.profile.whitelist[itemIdWithSuffix]
                local itemIsBlacklisted = self.db.profile.blacklist[itemIdWithSuffix]
                if item.quality then
                    itemIsWhitelisted = itemIsWhitelisted or self.db.profile.itemRarities[rarities[item.quality + 1]]
                    itemIsBlacklisted = itemIsBlacklisted or not self.db.profile.itemRarities[rarities[item.quality + 1]]
                end
                if itemExistsAndIsTradeable and (itemIsWhitelisted or not itemIsBlacklisted) then
                    if not bagContents[itemIdWithSuffix] then bagContents[itemIdWithSuffix] = item
                    else bagContents[itemIdWithSuffix].stackCount = bagContents[itemIdWithSuffix].stackCount + item.stackCount end
                end
            end
        end
    end

    return bagContents
end

function addon:GetAllContent()
    local itemsCharactersList = {}
    local money = 0
    -- Add bank items to tree view
    local playerBanks = addon.bank.players
    if not playerBanks then return itemsCharactersList, money end
    for playerId,entry in pairs(playerBanks) do
        money = (entry.money or 0) + money
        -- For each itemId: item in the bank
        for itemId, item in pairs(entry.bank or {}) do
            -- If we already saw this item before
            if itemsCharactersList[itemId] then
                local listItem = itemsCharactersList[itemId]
                listItem.stackCount = listItem.stackCount + item.stackCount
                listItem.characters[playerId] = { name = entry.name, stackCountBank = item.stackCount}
                listItem.itemMetadata = item
                itemsCharactersList[itemId] = listItem

            -- We haven't seen this item
            else
                local listItem = { characters = {}}
                listItem.stackCount =item.stackCount
                listItem.characters[playerId] = { name = entry.name, stackCountBank = item.stackCount, stackCountBag = 0}
                listItem.itemMetadata = item
                itemsCharactersList[itemId] = listItem
            end
        end

        -- For each itemId: Item in bags
        for itemId, item in pairs(entry.bags or {}) do
            -- If we've seen this item before
            if itemsCharactersList[itemId] then
                local listItem = itemsCharactersList[itemId]
                listItem.stackCount = listItem.stackCount + item.stackCount
                if listItem.characters[playerId] then
                    if not listItem.characters[playerId].stackCountBag then
                        listItem.characters[playerId].stackCountBag = 0
                    end
                    listItem.characters[playerId].stackCountBag = listItem.characters[playerId].stackCountBag + item.stackCount
                    listItem.characters[playerId].name = entry.name
                else
                    listItem.characters[playerId] = { name = entry.name, stackCountBag = item.stackCount }
                end
                listItem.itemMetadata = item
                itemsCharactersList[itemId] = listItem

            -- We haven't seen this item before
            else
                local listItem = { characters = {} }
                listItem.stackCount =item.stackCount
                listItem.characters[playerId] = { name = entry.name, stackCountBag = item.stackCount, stackCountBank = 0 }
                listItem.itemMetadata = item
                itemsCharactersList[itemId] = listItem
            end
        end
    end

    return itemsCharactersList, money
end

--[[------------------------------------------------------------------------------------
    SLASH COMMANDS
]]--------------------------------------------------------------------------------------

--- Shows the various slash commands in chat.
function addon:RunMenu(input)
    local command, extraArgs = strsplit(" ", input, 2)
    if input == "" or input == "help" then 
        self:Print(ChatFrame1, "help: Shows this help menu")
        self:Print(ChatFrame1, "show: Opens the items UI")
        self:Print(ChatFrame1, "resetdb: resets the SavedVariables database.")
        self:Print(ChatFrame1, "resetperso: resets Personal data for current character.")
        self:Print(ChatFrame1, "reset <CharacterName>: resets Personal data for specified character.")
        self:Print(ChatFrame1, "enable: manually reenables the addon.")
    elseif input == "show" then self:ShowUI()
    elseif input == "resetdb" then self:ResetDB()
    elseif input == "resetperso" then
        if self.ResetPersonal then
            self:ResetPersonal()
            self:Print(ChatFrame1, "Personal data reset for current character.")
        end
    elseif command == "reset" and extraArgs and extraArgs ~= "" then
        if self.ResetPersonal then
            self:ResetPersonal(extraArgs)
            self:Print(ChatFrame1, "Personal data reset for "..extraArgs..".")
        end
    elseif input == 'enable' then self:ReEnableAddon()
    elseif input == 'sync' then self:SyncWithPlayers(false)
    elseif addon.debug and command == "tl" then self:TestWhisper(extraArgs)
    end
end

function addon:ReEnableAddon()
    self.db.profile.loaded = true
    self:Print("Addon re-enabled! Perform a /reload to initialize.")
end

--- Resets the player's savedVariables database.
function addon:ResetDB()
    self.db:ResetDB()
    self:Debug("DB Reset!")
end

function addon:ShowUI()
    if not addon.loaded then
        self:TryLoadGuild()
    end
    local parent = AceGUI:Create("Frame")
    local function onTabChanged(container, event, group, parentFrame)
        container:ReleaseChildren()
        local bankName = self:GetBankName()
        if group == 'versions' then
            parentFrame:SetStatusText('Your version: '..addon.version)
        elseif group == 'personal' then
            parentFrame:SetStatusText('Personal snapshot')
        else
            local epoch = self:GetMostRecentSync(bankName)
            local hours, minutes = 0, 0
            if (not epoch or epoch == -1) then
                parentFrame:SetStatusText("Never")
            else
                local delta = GetServerTime() - epoch
                hours = floor(delta / 3600)
                minutes = floor(delta / 60)
            end
            if addon.syncInProgress then
                parentFrame:SetStatusText("SYNC IN PROGRESS...")
            elseif (hours < 1) then
                local plural = ''
                if minutes > 1 then plural = 's' end
                parentFrame:SetStatusText("Last synced ".. minutes.. " minute"..plural.." ago")
            else
                minutes = minutes - 60 * hours
                parentFrame:SetStatusText("Last synced "..hours.."h"..minutes.."m ago")
            end
        end
        if group == "banking" then
            if (self.db.profile.showAsItemView) then
                container:AddChild(self:CreateTreeview(bankName))
            else
                container:AddChild(self:CreateUIFrame(bankName))
            end
        elseif group == "personal" then
            if self.CreatePersonalFrame then
                container:AddChild(self:CreatePersonalFrame())
            else
                local label = AceGUI:Create('Label')
                label:SetText("Personal tab is unavailable.")
                container:AddChild(label)
            end
        elseif group == "export" then
            container:AddChild(self:CreateExportFrame())
        elseif group == 'wishlist' then
            self:RefreshWishlistTabBadge()
            container:AddChild(self:CreateWishlistFrame())
        elseif group == 'versions' then
            ACD:Open('BeanBank_Versions', container)
        end
    end
    addon.wishlistInputBuffer = addon.wishlistInputBuffer or ""
    LibStub('AceConfig-3.0'):RegisterOptionsTable('BeanBank_Versions', addon.versions)

    parent:SetLayout("Fill")
    parent:SetWidth(600)
    parent:SetTitle("AdvCoBank")
    parent:SetCallback("OnClose", function(widget)
        addon._advCoBankTabWidget = nil
        AceGUI:Release(widget)
    end)
    local frame = AceGUI:Create("TabGroup")
    frame:SetLayout("Fill")
    frame:SetCallback("OnGroupSelected", function(widget, name, group) onTabChanged(widget, name, group, parent) end)
    local bypass = UnitNameUnmodified("player") == "Kuronie" and addon.debug
    if bypass or addon.guildRank <= 2 then
        frame:SetTabs({
            { text = "Banking", value="banking" },
            { text = "Personal", value="personal" },
            { text = "Export", value="export" },
            { text = "Wishlist", value='wishlist' },
            { text = "Versions", value='versions'}
        })
    else
        frame:SetTabs({
            { text = "Banking", value="banking" },
            { text = "Personal", value="personal" },
            { text = "Wishlist", value="wishlist" },
            { text = "Versions", value='versions'}
        })
    end
    frame:SelectTab("banking")
    addon._advCoBankTabWidget = frame
    self:RegisterSpecialFrame(parent)
    parent:AddChild(frame)
    self:RefreshWishlistTabBadge()

    do return end
end

--[[------------------------------------------------------------------------------------
    UTILS
]]--------------------------------------------------------------------------------------

--- Base numeric item id from a wishlist/storage key ("123" or "123:suffix").
function addon:GetItemNumericId(key)
    if key == nil then return nil end
    local s = tostring(key)
    local fid = tonumber((strsplit(":", s)))
    return fid
end

function addon:GetItemBindTypeForWishlist(itemID)
    if not itemID then return nil end
    if GetItemInfoInstant then
        local bt = select(14, GetItemInfoInstant(itemID))
        if bt ~= nil then return bt end
    end
    return select(14, GetItemInfo(itemID))
end

--- Allows only bindings that remain tradeable (no BoP/BoU/quest/account).
function addon:IsItemBindAllowedOnPersonalWishlist(itemID)
    local baseId = self:GetItemNumericId(itemID)
    if not baseId then
        return false, "Invalid item."
    end
    if not GetItemInfo(baseId) and C_Item and C_Item.RequestLoadItemDataByID then
        C_Item.RequestLoadItemDataByID(baseId)
    end
    local bt = self:GetItemBindTypeForWishlist(baseId)
    if bt == nil and not GetItemInfo(baseId) then
        return false, "Item data not loaded yet. Try again in a moment."
    end
    if bt == nil then
        return false, "Could not determine item binding."
    end
    if bt == 0 or bt == 2 then
        return true
    end
    return false, "Only tradeable items can be wishlisted (excludes BoP / BoU / quest / account-bound)."
end

--- ClassID 12 = quest items (cannot be traded like normal goods).
local LE_ITEM_CLASS_QUEST = 12

--- First colored item hyperlink found in pasted text (used if GetItemInfo omits link while name exists).
function addon:ExtractItemLinkFromWishlistInput(raw)
    if type(raw) ~= "string" then return nil end
    raw = raw:gsub("^%s+", ""):gsub("%s+$", "")
    if raw == "" then return nil end
    -- Aligné sur ConvertHyperLinkToItemId (noms [, ], ', :, espaces dans les crochets).
    local link = raw:match("|c[%a%d]+|Hitem[%d%a:]+|h%[[^%]]+%]|h|r")
    if link then return link end
    return raw:match("|Hitem[%d%a:]+|h%[[^%]]+%]|h|r")
end

--- Extrait l'ID numérique d'une URL WoWHead *Classic* (/classic/item=X ou .../classic/item=X/nom).
--- Ex. https://www.wowhead.com/classic/item=7723/mograines-might → 7723
function addon:ExtractWowheadClassicItemIdFromUrl(text)
    if type(text) ~= "string" then return nil end
    local id = tonumber(text:match("classic/item=(%d+)"))
    return id
end

--- @param rawInput string|nil original editbox text (for link extraction fallback)
function addon:ValidateWishlistAddition(itemKeyStr, baseId, rawInput)
    if not itemKeyStr or itemKeyStr == "" then
        return false, "|cffff4444Invalid item.|r"
    end
    if not baseId then
        return false, "|cffff4444Invalid item ID or link.|r"
    end
    local name, link = GetItemInfo(baseId)
    if (not link or link == "") and rawInput then
        link = self:ExtractItemLinkFromWishlistInput(rawInput)
    end
    if not name or not link or link == "" then
        if C_Item and C_Item.RequestLoadItemDataByID then
            C_Item.RequestLoadItemDataByID(baseId)
        end
        return false, "|cffffff88Item data loading — try again in a second.|r"
    end
    if self.db.profile.blacklist and self.db.profile.blacklist[itemKeyStr] then
        return false, "|cffff4444This item is blacklisted (Settings → Items).|r"
    end
    local classID = select(12, GetItemInfo(baseId))
    if type(classID) == "number" and classID == LE_ITEM_CLASS_QUEST then
        return false, "|cffff4444Quest items cannot be wishlisted.|r"
    end
    local bindOk, bindErr = self:IsItemBindAllowedOnPersonalWishlist(baseId)
    if not bindOk then
        return false, "|cffff4444" .. (bindErr or "Cannot wishlist this item.") .. "|r"
    end
    return true
end

function addon:GetHyperlinkFromGameTooltip()
    local vals = { GameTooltip:GetItem() }
    for _, v in ipairs(vals) do
        if type(v) == "string" then
            if strfind(v, "|Hitem:", 1, true) or strfind(v, "|h%[", 1) then
                return v
            end
        end
    end
    return nil
end

function addon:SetWishlistAddFeedback(text)
    addon._wishlistAddFeedback = text or "|cff8899aaPaste an item link, wowhead.com/classic/item=… URL, or numeric ID.|r"
    if addon._wishlistFeedbackLabelAce and addon._wishlistFeedbackLabelAce.SetText then
        addon._wishlistFeedbackLabelAce:SetText(addon._wishlistAddFeedback)
    end
end

function addon:WishlistSubmitEnteredText(rawText, rowsContainer, retryDepth)
    retryDepth = retryDepth or 0
    if retryDepth == 0 then
        self._wishlistPendingAdd = nil
    end
    local value = ""
    local w = addon._wishlistEditBoxAce
    if w and w.GetText then
        value = (w:GetText() or ""):gsub("^%s+", ""):gsub("%s+$", "")
    end
    if value == "" then
        value = (rawText or ""):gsub("^%s+", ""):gsub("%s+$", "")
    end
    if value == "" then
        value = (addon.wishlistInputBuffer or ""):gsub("^%s+", ""):gsub("%s+$", "")
    end
    addon.wishlistInputBuffer = value
    if value == "" then
        self:SetWishlistAddFeedback("|cff8899aaPaste an item link, wowhead.com/classic/item=… URL, or numeric ID.|r")
        return
    end
    local itemKey = self:ConvertHyperLinkToItemId(value)
    if not itemKey then
        local whId = self:ExtractWowheadClassicItemIdFromUrl(value)
        if whId then itemKey = tostring(whId) end
    end
    if not itemKey then
        local n = tonumber(value)
        if n then itemKey = tostring(n) end
    end
    if not itemKey then
        self:SetWishlistAddFeedback("|cffff4444Could not read an item link or ID.|r")
        return
    end
    itemKey = tostring(itemKey)
    local baseId = self:GetItemNumericId(itemKey)
    if not baseId then
        self:SetWishlistAddFeedback("|cffff4444Invalid item ID.|r")
        return
    end
    if self:GetPersonalWishlistItem(itemKey) then
        self:SetWishlistAddFeedback("|cffeeee55Already on your wishlist.|r")
        return
    end
    local ok, errMsg = self:ValidateWishlistAddition(itemKey, baseId, value)
    if not ok then
        if errMsg and strfind(errMsg, "Item data loading", 1, true) and self:WishlistQueueRetryAfterLoad(baseId, value, rowsContainer, retryDepth) then
            self:SetWishlistAddFeedback("|cffffff88Item data loading — try again in a second.|r")
            return
        end
        self:SetWishlistAddFeedback(errMsg or "|cffff4444Cannot add this item.|r")
        return
    end
    -- Capturer explicitement les retours (évite tout piège avec { GetItemInfo(id) } / indices).
    local itemName, itemLink, itemQuality, itemLevel, itemMinLevel,
        itemClass, itemSubClass, itemStackMax, invSlot, tex = GetItemInfo(baseId)
    if (not itemLink or itemLink == "") then
        itemLink = self:ExtractItemLinkFromWishlistInput(value)
    end
    if not itemName or not itemLink or itemLink == "" then
        if self:WishlistQueueRetryAfterLoad(baseId, value, rowsContainer, retryDepth) then
            self:SetWishlistAddFeedback("|cffffff88Item data loading — try again in a second.|r")
            return
        end
        self:SetWishlistAddFeedback("|cffffff88Item data loading — try again in a second.|r")
        return
    end
    local itemTuple = {
        itemName, itemLink, itemQuality, itemLevel, itemMinLevel,
        itemClass, itemSubClass, itemStackMax, invSlot, tex,
    }
    local entry = { key = itemKey, item = itemTuple }
    self._wishlistPendingAdd = nil
    self:SetPersonalWishlistItem(itemKey, entry)
    if addon._wishlistEditBoxAce and addon._wishlistEditBoxAce.SetText then
        addon._wishlistEditBoxAce:SetText("")
    end
    addon.wishlistInputBuffer = ""
    self:SetWishlistAddFeedback("|cffaaffaaAdded to wishlist.|r")
    self:RefreshWishlistAceRowList(rowsContainer)
    self:RefreshWishlistTabBadge()
end

--- Rebuilds wishlist rows in the AceGUI wishlist scroll (supports item tooltips).
function addon:RefreshWishlistAceRowList(rowsContainer)
    if not rowsContainer then return end
    rowsContainer:ReleaseChildren()
    local root = self:GetPersonalWishlistRoot()
    if not root then return end

    local list = {}
    for k, entry in pairs(root) do
        if type(entry) == "table" and entry.item then
            table.insert(list, { ks = tostring(k), entry = entry })
        end
    end
    table.sort(list, function(a, b)
        local na = a.entry.item and a.entry.item[1] or ""
        local nb = b.entry.item and b.entry.item[1] or ""
        return tostring(na):lower() < tostring(nb):lower()
    end)

    for _, rowItem in ipairs(list) do
        local ks = rowItem.ks
        local tuple = rowItem.entry.item or {}
        local link = tuple[2]
        local tex = tuple[10]
        local disp = link or ("|cffffffff[" .. (tuple[1] or "?") .. "]|r")

        local row = AceGUI:Create("SimpleGroup")
        row:SetLayout("Flow")
        row:SetFullWidth(true)

        local il = AceGUI:Create("InteractiveLabel")
        il:SetWidth(448)
        if tex then il:SetImage(tex) end
        il:SetImageSize(36, 36)
        il:SetText(disp)

        local baseId = self:GetItemNumericId(ks)
        il:SetCallback("OnEnter", function(w)
            if not (GameTooltip and GameTooltip.SetOwner) then return end
            GameTooltip:SetOwner(w.frame, "ANCHOR_RIGHT")
            local lk = link
            if (not lk or lk == "") and baseId then
                lk = select(2, GetItemInfo(baseId))
            end
            if lk and lk ~= "" and GameTooltip.SetHyperlink then
                GameTooltip:SetHyperlink(lk)
            elseif baseId and GameTooltip.SetItemByID then
                GameTooltip:SetItemByID(baseId)
            end
            GameTooltip:AddLine("|cFFA15C0EAdvCoBank|r")
            GameTooltip:AddLine("|cffd4c4a0Personal wishlist|r")
            GameTooltip:Show()
        end)
        il:SetCallback("OnLeave", function()
            if GameTooltip then GameTooltip:Hide() end
        end)

        local rm = AceGUI:Create("Button")
        -- UIPanelButtonTemplate réserve ~15px de padding de chaque côté du texte : une largeur trop
        -- faible coupe le libellé et affiche ".." sans erreur Lua.
        rm:SetAutoWidth(true)
        rm:SetCallback("OnClick", function()
            self:RemovePersonalWishlistItem(ks)
            self:RefreshWishlistTabBadge()
            self:SetWishlistAddFeedback("|cffaaaaaaRemoved from wishlist.|r")
            self:RefreshWishlistAceRowList(rowsContainer)
        end)

        row:AddChild(il)
        row:AddChild(rm)
        rm:SetText("X")
        rowsContainer:AddChild(row)
    end
end

function addon:CreateWishlistFrame()
    local outer = AceGUI:Create("SimpleGroup")
    outer:SetLayout("Flow")
    outer:SetFullWidth(true)

    local edit = AceGUI:Create("EditBox")
    edit:SetLabel("Item link, Wowhead Classic URL, or item ID")
    edit:SetFullWidth(true)
    edit:DisableButton(true)
    edit:SetMaxLetters(0) -- défaut AceGUI EditBox = 256 ; les hyperliens d'items Classic peuvent dépasser
    edit:SetText(addon.wishlistInputBuffer or "")
    addon._wishlistEditBoxAce = edit

    local hint = AceGUI:Create("Label")
    hint:SetFullWidth(true)
    hint:SetText("Adds when you press Enter. Paste a game item link, a numeric ID, or a wowhead.com/classic/item=… URL. Tradeable items only (no BoP/BoU, quest, blacklist). Drag an item here.")

    local fb = AceGUI:Create("Label")
    fb:SetFullWidth(true)
    addon._wishlistFeedbackLabelAce = fb

    local heading = AceGUI:Create("Heading")
    heading:SetFullWidth(true)
    heading:SetText("Personal wishlist")

    local scroll = AceGUI:Create("ScrollFrame")
    scroll:SetLayout("Flow")
    scroll:SetFullWidth(true)
    scroll:SetHeight(360)

    local rows = AceGUI:Create("SimpleGroup")
    rows:SetLayout("Flow")
    rows:SetFullWidth(true)
    scroll:AddChild(rows)

    edit:SetCallback("OnTextChanged", function(_, _, txt)
        addon.wishlistInputBuffer = txt or ""
    end)
    edit:SetCallback("OnEnterPressed", function(_, _, val)
        self:WishlistSubmitEnteredText(val, rows)
    end)

    outer:AddChild(edit)
    outer:AddChild(hint)
    outer:AddChild(fb)
    outer:AddChild(heading)
    outer:AddChild(scroll)

    self:SetWishlistAddFeedback(addon._wishlistAddFeedback or "|cff8899aaPaste an item link, wowhead.com/classic/item=… URL, or numeric ID.|r")
    self:RefreshWishlistAceRowList(rows)

    return outer
end

function addon:MigrateGuildWishlistToPersonalIfNeeded()
    if not (self.db and self.db.factionrealm) then return end
    if self.db.factionrealm.wishlistGuildToPersonalMigrated then return end
    local root = self:GetPersonalWishlistRoot()
    if not root then return end
    local bankName = self:GetBankName()
    local old = bankName and self.db.factionrealm.banks[bankName] and self.db.factionrealm.banks[bankName].wishlist
    if old then
        for id, entry in pairs(old) do
            if id ~= "lastSync" and type(entry) == "table" and entry.item then
                local k = tostring(id)
                if root[k] == nil then
                    root[k] = entry
                end
            end
        end
    end
    self.db.factionrealm.wishlistGuildToPersonalMigrated = true
end

function addon:_wishlistContainerHasStacks(container, itemKeyStr)
    if not container or not itemKeyStr then return false end
    local it = container[itemKeyStr]
    if it and type(it.stackCount) == "number" and it.stackCount > 0 then return true end
    local n = tonumber(itemKeyStr)
    if n then
        it = container[n]
        if it and type(it.stackCount) == "number" and it.stackCount > 0 then return true end
    end
    return false
end

function addon:_playerDataContainsWishlistItem(pdata, itemKeyStr)
    if self:_wishlistContainerHasStacks(pdata.bank, itemKeyStr) then return true end
    if self:_wishlistContainerHasStacks(pdata.bags, itemKeyStr) then return true end
    return false
end

--- How many wishlist entries appear in synced bank/bag data from other guild members only.
function addon:CountPersonalWishlistMatchesInOtherPlayersData()
    if not addon.loaded then return 0 end
    local wl = self:GetPersonalWishlistRoot()
    if not wl then return 0 end
    local bankName = self:GetBankName()
    if not bankName then return 0 end
    local bank = self:GetBank(bankName)
    if not (bank and bank.players) then return 0 end

    local n = 0
    for wlKey, entry in pairs(wl) do
        if type(entry) == "table" and entry.item then
            local ks = tostring(wlKey)
            local found = false
            for guid, pdata in pairs(bank.players) do
                if guid ~= playerGuid and self:_playerDataContainsWishlistItem(pdata, ks) then
                    found = true
                    break
                end
            end
            if found then n = n + 1 end
        end
    end
    return n
end

--- Updates the Wishlist tab label on the main window (e.g. "Wishlist (2)").
function addon:RefreshWishlistTabBadge()
    local wg = addon._advCoBankTabWidget
    if not (wg and wg.tablist and wg.BuildTabs) then return end
    local count = self:CountPersonalWishlistMatchesInOtherPlayersData()
    for _, tab in ipairs(wg.tablist) do
        if tab.value == "wishlist" then
            tab.text = count > 0 and ("Wishlist (" .. count .. ")") or "Wishlist"
            break
        end
    end
    wg:BuildTabs()
end

function addon:IsAddonEnabled(otherAddon)
    return select(2, C_AddOns.IsAddOnLoaded(otherAddon))
end

function addon:ShowWishlistInfoTooltip()
    local hoveredItemLink = self:GetHyperlinkFromGameTooltip()
    local itemKey = hoveredItemLink and self:ConvertHyperLinkToItemId(hoveredItemLink)
    local wlRoot = self:GetPersonalWishlistRoot()
    if not wlRoot or not itemKey then
        return
    end
    local ks = tostring(itemKey)
    local wishlistItem = wlRoot[ks]
    if not wishlistItem then
        local baseId = self:GetItemNumericId(ks)
        if baseId then wishlistItem = wlRoot[tostring(baseId)] end
    end
    if not wishlistItem or type(wishlistItem) ~= "table" then return end
    GameTooltip:AddLine("|cFFA15C0EAdvCoBank|r")
    GameTooltip:AddLine("|cffd4c4a0Personal wishlist|r")
    GameTooltip:AddLine()
end

function addon:HighlightBagItems()
    local wlRoot = self:GetPersonalWishlistRoot()
    if not wlRoot then return end
    local idSet = {}
    for k, v in pairs(wlRoot) do
        if type(v) == "table" and v.item then
            idSet[tostring(k)] = true
            local n = self:GetItemNumericId(k)
            if n then idSet[tostring(n)] = true end
        end
    end
    if self:IsAddonEnabled('AdiBags') then
        self:HighlightAdiBagItem(idSet)
    elseif self:IsAddonEnabled('Baganator') then
    elseif self:IsAddonEnabled('Bagnon') then
    else
        self:HighlightDefaultUIItem(idSet)
    end
end

function addon:HighlightBankItems()

end

function addon:HighlightDefaultUIItem(wishlist)
    if not wishlist then return end
    for bag = 0, NUM_BAG_SLOTS do
        local bagId = IsBagOpen(bag)
        if bagId then
            local nbSlots = C_Container.GetContainerNumSlots(bag)
            for slot = 1, nbSlots do
                local slotId = nbSlots + 1 - slot
                local slotFrameName = 'ContainerFrame' .. bagId .. "Item" .. slotId
                local item = _G[slotFrameName]
                if item then
                    local itemInfo = C_Container.GetContainerItemInfo(bag, slot)
                    if itemInfo then
                        if wishlist[tostring(itemInfo.itemID)] or wishlist[itemInfo.itemID] then
                            if not item.qborder then
                            local border = item:CreateTexture(slotFrameName .. 'Quality', 'OVERLAY');
                            local colour = addon.tooltip.colour
                            border:SetTexture("Interface\\Buttons\\UI-ActionButton-Border");
                            border:SetBlendMode('ADD');
                            border:SetAlpha(colour.a);
                            border:SetVertexColor(colour.r, colour.g, colour.b);
                            border:SetHeight(68);
                            border:SetWidth(68);
                            border:SetPoint('CENTER', item, 'CENTER', 0, 0);
                            border:Show()
                            item.qborder = border
                            end
                        end
                    end
                end
            end
        end
    end
end

function addon:HighlightAdiBagItem(wishlist)
    if not wishlist then return end
    local adiContainer = _G['AdiBagsContainer1']
    if not adiContainer then return end
    local lookupTb = {}
    for _, button in pairs(adiContainer.buttons) do
        if button.itemId then
            if not lookupTb[tostring(button.itemId)] then
                lookupTb[tostring(button.itemId)] = {button}
            else
                tinsert(lookupTb[tostring(button.itemId)], button)
            end
        end
    end
    for key, _ in pairs(wishlist) do
        local buttons = lookupTb[tostring(key)]
        if buttons then
            for _, button in ipairs(buttons) do
                local border = button.IconOverlay
                border:SetTexture("Interface\\Buttons\\UI-ActionButton-Border");
                border:SetBlendMode('ADD');
                local colour = addon.tooltip.colour
                border:SetAlpha(colour.a);
                border:SetVertexColor(colour.r, colour.g, colour.b);
                border:SetHeight(68);
                border:SetWidth(68);
                border:SetPoint('CENTER', button, 'CENTER', 0, 0);
                border:Show()
            end
        end
    end
end

function addon:DisplayConfirmationForBags()
    if not (self.db.char and self.db.char.banking and self.db.char.banking.bags) then return false end

    return "Exluding your bags will remove all bag items from the database!"
end

function addon:DisplayConfirmationForBank()
    if not (self.db.char and self.db.char.banking and self.db.char.banking.bank) then return false end

    return "Exluding your bank will remove all bank items from the database!"
end

function addon:DisplayConfirmationForQuality(name)
    if not self.db.profile.itemRarities[name] then return false end

    return "Exluding "..name.." items will remove them from the database!"
end

function addon:DisplayConfirmationForMoney()
    if not (self.db.char and self.db.char.banking and self.db.char.banking.money) then return false end

    return "Exluding money will remove it the database!"
end

--- Creates the csv row for the given item.
function addon:CreateCSVRow(item)
    return item.itemMetadata.itemName .. "," .. item.itemMetadata.itemID .. "," .. item.stackCount .. "," .. (item.itemMetadata.quality or '') .. "\n"
end

--- Creates the export UI frame.
function addon:CreateExportFrame()
    local items = self:GetAllContent()
    local text = ""
    for _, item in pairs(items) do
        text = text .. self:CreateCSVRow(item)
    end
    local textFrame = AceGUI:Create('MultiLineEditBox')
    textFrame:SetLabel("Export CSV")
    textFrame:SetFocus()
    textFrame:SetText(text)
    textFrame:SetNumLines(20)
    
    return textFrame
end

--- Creates the main bank UI treeview frames.
function addon:CreateTreeview(bankName)
    local itemsCharactersList, money = self:GetAllContent()
    local parentContainer = AceGUI:Create('SimpleGroup')
    parentContainer:SetLayout("Flow")
    local label = AceGUI:Create('Label')
    if not money then
        money = 0
    end
    label:SetText(GetMoneyString(money))
    parentContainer:AddChild(label)

    -- Quality filter (strict match).
    self.db.profile.qualityFilters = self.db.profile.qualityFilters or {}
    -- Backwards compat for earlier "min quality" implementation.
    if self.db.profile.qualityFilters.bankingQuality == nil and type(self.db.profile.qualityFilters.bankingMinQuality) == "number" then
        self.db.profile.qualityFilters.bankingQuality = self.db.profile.qualityFilters.bankingMinQuality
    end
    if type(self.db.profile.qualityFilters.bankingQuality) ~= "number" then
        self.db.profile.qualityFilters.bankingQuality = -1
    end
    local function getQualityFilter()
        return self.db.profile.qualityFilters.bankingQuality or -1
    end
    local qualityLabels = {
        [-1] = "All qualities",
        [0] = "|cff9d9d9dPoor|r",
        [1] = "|cffffffffCommon|r",
        [2] = "|cff1eff00Uncommon|r",
        [3] = "|cff0070ddRare|r",
        [4] = "|cffa335eeEpic|r",
        [5] = "|cffff8000Legendary|r",
    }
    local qualityDropdown = AceGUI:Create("Dropdown")
    qualityDropdown:SetLabel("Quality filter")
    qualityDropdown:SetList(qualityLabels)
    local searchBar = AceGUI:Create("EditBox")
    searchBar:DisableButton(true)
    -- Put dropdown + search on the same row.
    local filterRow = AceGUI:Create('SimpleGroup')
    filterRow:SetLayout("Flow")
    filterRow:SetFullWidth(true)
    qualityDropdown:SetValue(getQualityFilter())
    qualityDropdown:SetWidth(160)
    searchBar:SetWidth(340)
    filterRow:AddChild(qualityDropdown)
    filterRow:AddChild(searchBar)
    parentContainer:AddChild(filterRow)
    local table = AceGUI:Create("TreeGroup")

    local function hideTooltip()
        if GameTooltip and GameTooltip:IsShown() then
            GameTooltip:Hide()
        end
    end

    local function showItemTooltip(anchorFrame, itemKey)
        if not (self.db and self.db.profile and self.db.profile.tooltip and self.db.profile.tooltip.show) then
            return
        end
        if not itemKey then return end
        local row = itemsCharactersList[itemKey]
        local itemMeta = row and row.itemMetadata
        local link = itemMeta and itemMeta.hyperlink
        local itemID = itemMeta and itemMeta.itemID
        if not link and not itemID then return end
        if not (GameTooltip and GameTooltip.SetOwner) then return end

        GameTooltip:SetOwner(anchorFrame or UIParent, "ANCHOR_RIGHT")

        local function setTooltipNow()
            if link and GameTooltip.SetHyperlink then
                GameTooltip:SetHyperlink(link)
            elseif itemID and GameTooltip.SetItemByID then
                GameTooltip:SetItemByID(itemID)
            end
            GameTooltip:Show()
        end

        if Item and (link or itemID) then
            local it = link and Item:CreateFromItemLink(link) or Item:CreateFromItemID(itemID)
            if it and it.ContinueOnItemLoad then
                it:ContinueOnItemLoad(function()
                    if GameTooltip and GameTooltip:IsShown() then
                        setTooltipNow()
                    end
                end)
            end
        elseif C_Item and C_Item.RequestLoadItemDataByID and itemID then
            C_Item.RequestLoadItemDataByID(itemID)
        end

        setTooltipNow()
    end

    local function passesQualityFilter(itemMeta)
        local q = itemMeta and itemMeta.quality
        local filterQ = getQualityFilter()
        if filterQ == -1 then
            return true
        end
        if type(q) ~= "number" then return false end
        return q == filterQ
    end

    local function rebuildTree(filterText)
        local treeview = {}
        local cpt = 1
        local filterQ = getQualityFilter()
        local needle = filterText and string.lower(filterText) or ""
        for itemId, item in pairs(itemsCharactersList) do
            local meta = item and item.itemMetadata
            local itemName = meta and meta.itemName or ""
            if itemName ~= "" and passesQualityFilter(meta) then
                if needle == "" or strfind(string.lower(itemName), needle, 1, true) then
                    local treeviewTitle = ""..item.stackCount.." "..(meta.hyperlink or itemName)
                    if addon.debug then
                        treeviewTitle = treeviewTitle.." ("..itemId..")"
                    end
                    local treeviewItem = {
                        value = itemId,
                        text = treeviewTitle,
                        children = {},
                        visible = true,
                        icon = meta.iconFileID,
                        sortValue = itemName
                    }
                    local t = 1
                    for playerId,char in pairs(item.characters) do
                        treeviewItem.children[t] = {
                            value = playerId,
                            text = char.name.." (Bank: "..(char.stackCountBank or 0).." | Bags: "..(char.stackCountBag or 0)..")"
                        }
                        t = t + 1
                    end
                    treeview[cpt] = treeviewItem
                    cpt = cpt + 1
                end
            end
        end
        local sorted = self:SortTreeViewItems(treeview)
        table:SetTree(sorted)
        if addon.debug then
            self:Debug("Banking quality filter="..tostring(filterQ).." items="..tostring(#sorted))
        end
    end

    searchBar:SetCallback('OnTextChanged', function(_, _, text)
        rebuildTree(text)
    end)
    qualityDropdown:SetCallback("OnValueChanged", function(_, _, v)
        if type(v) ~= "number" then v = tonumber(v) end
        if type(v) ~= "number" then v = -1 end
        self.db.profile.qualityFilters.bankingQuality = v
        rebuildTree(searchBar:GetText() or "")
    end)
    table:SetCallback("OnGroupSelected", function(widget, _, value)
        hideTooltip()
        local anchor = widget and widget.frame or UIParent
        showItemTooltip(anchor, value)
    end)
    table.treeframe:SetWidth(500)
    table:SetLayout("Fill")
    table:SetFullHeight(true)
    table:EnableButtonTooltips(false)
    table:SetFullWidth(true)
    self:EnsureBankExists(bankName)
    parentContainer:AddChild(table)

    parentContainer.frame:HookScript("OnHide", hideTooltip)

    rebuildTree("")

    return parentContainer
end

function addon:ConvertHyperLinkToItemId(hyperlink)
    local pattern = "|c[%a%d]+|Hitem[%d%a:]+|h%[[%a%s%'%-:]+%]|h|r"
    local itemIdWithSuffix

    local capture = string.match(hyperlink, pattern)
    if capture then
        local suffixID = select(8, strsplit(':', capture))
        itemIdWithSuffix = select(2, strsplit(':', capture))
        if suffixID ~= "" then
            itemIdWithSuffix =  itemIdWithSuffix..":"..suffixID
        end
    else
        local itemId, itemSuffix = strsplit(':', hyperlink)
        if tonumber(itemId) then
            if tonumber(itemSuffix) then
                itemIdWithSuffix = itemId .. ":"..itemSuffix
            else
                itemIdWithSuffix = tostring(itemId)
            end
        end
    end

    return itemIdWithSuffix
end

--- Tries to lookup the item via its hyperlink in the specified bankName bank.
--- If the item exists, it returns the total amount as a single instance.
--- If the item doesn't exist, returns nil.
function addon:HasItem(bankName, hyperlink)
    if not self.db.factionrealm.banks[bankName] then return nil end
    local itemIdWithSuffix = self:ConvertHyperLinkToItemId(hyperlink)
    local foundItem = nil
    for _, entry in pairs(self.db.factionrealm.banks[bankName].players) do
        if entry.bank then
            for itemId, item in pairs(entry.bank) do
                if tostring(itemId) == itemIdWithSuffix then
                    if foundItem then
                        foundItem.stackCount = foundItem.stackCount + item.stackCount
                    else
                        foundItem = item
                    end
                end
            end
        end
        if entry.bags then
            for itemId, item in pairs(entry.bags) do
                if tostring(itemId) == itemIdWithSuffix then
                    if foundItem then
                        foundItem.stackCount = foundItem.stackCount + item.stackCount
                    else
                        foundItem = item
                    end
                end
            end
        end
    end

    return foundItem
end

--- Generates a guild name for a banking key. If the player is unguilded, the player's name is returned.
function addon:GetBankName()
    if superdev then
        return 'AdvCoBank Test'
    else
        local guildName = GetGuildInfo("player")
        if guildName then
            return guildName
        end
        local playerName = GetUnitName and GetUnitName("player", false) or UnitName("player")
        return playerName
    end
end

--- Registers a given frame to the global frames. This allows the frame to be closed when using the ESC key.
function addon:RegisterSpecialFrame(frame)
    local name = "BeanBankFrame"..openedFrames
    openedFrames = openedFrames + 1
    _G[name] = frame.frame
    tinsert(UISpecialFrames, name)
end

--- Will create an empty bank for the specified bankName if the entry does not exist in the banks array
function addon:EnsureBankExists(bankName)
    if not bankName then
        bankName = self:GetBankName()
        if not bankName then return end
    end
    if not self.db.factionrealm.banks[bankName] then
        self.db.factionrealm.banks[bankName] = {
            players = {},
            wishlist = {}
        }
    end
end

function addon:SortTreeViewItems(tbl)
    table.sort(tbl , function(a, b)
        return a.sortValue < b.sortValue
    end)

    return tbl
end

function addon:CompareVersion(currentVersion, targetVersion)
    local c_major_s, c_minor_s, c_patch_s = strsplit('.', currentVersion, 3)
    local t_major_s, t_minor_s, t_patch_s = strsplit('.', targetVersion, 3)
    local c_major, c_minor, c_patch = tonumber(c_major_s), tonumber(c_minor_s), tonumber(c_patch_s)
    local t_major, t_minor, t_patch = tonumber(t_major_s), tonumber(t_minor_s), tonumber(t_patch_s)

    if c_major < t_major then
        return -1
    elseif c_major == t_major then
        if c_minor < t_minor then
            return -1
        elseif c_minor == t_minor then
            if c_major == 0 then
            if c_patch < t_patch then
                    return -1
                elseif c_patch == t_patch then
                    return 0
                else
                    return 1
                end
            else
                return 0
            end
        else
            return 1
        end
    else
        return 1
    end
end


--[[------------------------------------------------------------------------------------
    UPGRADES
]]--------------------------------------------------------------------------------------

function addon:UpgradeTo_0_5_2()
    self:Print("Upgrading from "..self.db.global.version.." to 0.5.2")
    self:ResetDB()
    self.db.global.version = '0.5.2'
    self:SyncWithPlayers()
end

function addon:UpgradeTo_0_6_0()
    self:Print("Upgrading from "..self.db.global.version.." to 0.6.0")
    self.db.profile.loaded = true
    self.db.profile.tooltip = {
        show = true,
        showBorder = true,
        colour = {
            r = 0,
            g = 150,
            b = 150,
            a = 0.5
        }
    }
    addon.wishlist = {
        table = {},
        tooltip = self.db.profile.tooltip,
        guildRank = 1000,
        loaded = true
    }
    self.db.global.version = '0.6.0'
end

function addon:UpgradeTo_0_7_0()
    self:Print("Upgrading from "..self.db.global.version.." to 0.7.0")

    for _, bankInfo in pairs(self.db.factionrealm.banks) do
        for _, bank in pairs(bankInfo.players) do
            if not bank.lastSync or bank.lastSync == "Never" then
                bank.lastSync = GetServerTime()
            end
        end
    end

    self.db.global.version = '0.7.0'
end

function addon:UpgradeTo_0_8_11()
    self:Print("Upgrading from "..self.db.global.version.." to 0.8.11")
    for _, bankInfo in pairs(self.db.factionrealm.banks) do
        for _, bank in pairs(bankInfo.players) do
            if bankInfo.lastSync then
                bankInfo.lastSync = nil
            end
            if not bank.lastSync or bank.lastSync == "Never" then
                bank.lastSync = 0
            end
        end
    end
    self.db.global.version = '0.8.11'
    self:SyncWithPlayers()
end

function addon:UpgradeTo_0_8_13()
    local charDb = self.db.char or {}
    if not charDb.migrations then charDb.migrations = {} end
    local thisMigration = charDb.migrations['0.8.13']
    local _, playerRank = self:GetPlayerRank(UnitNameUnmodified('player'))
    if not playerRank then
        self:Debug("Could not obtain player rank. Quitting upgrade process")
        return
    end
    if (not thisMigration or not thisMigration.playerDataCleaned) and playerRank > 1 then
        self:Print("This character has corrupted data. Cleaning corrupted data...")
        self:RemoveItemsFromBags()
        self:RemoveItemsFromBank()
        self:RemoveMoneyFromBank()
        charDb.migrations['0.8.13'] = {
            playerDataCleaned = true
        }
        self:Print("Data cleaned!")
    end
end