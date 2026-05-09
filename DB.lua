-- The addon global is created in `Core.lua` as `GuildBank`.
-- Older versions used `BeanBank`; keep a small compatibility fallback.
local addon = GuildBank or BeanBank
assert(addon, "GuildBank addon table not initialized")

function addon:GetBank(bank)
    if not bank then return nil end
    if not (self.db and self.db.factionrealm) then return nil end
    self.db.factionrealm.banks = self.db.factionrealm.banks or {}

    local bankElement = self.db.factionrealm.banks[bank]
    if not bankElement then
        bankElement = { players = {}, wishlist = {} }
        self.db.factionrealm.banks[bank] = bankElement
    end
    bankElement.players = bankElement.players or {}
    bankElement.wishlist = bankElement.wishlist or {}
    return bankElement
end

function addon:GetBankPlayer(bank, player)
    local dbBank = self:GetBank(bank)
    if not dbBank or not dbBank.players then return nil end
    return dbBank.players[player]
end

function addon:GetBankPlayers(bank)
    local dbBank = self:GetBank(bank)
    if not dbBank then return nil end
    return dbBank.players
end

function addon:GetItemByPlayer(bankName, player, item)
    local playerBank = self:GetBankPlayer(bankName, player)

    local inventory, bank = playerBank.bags, playerBank.bank
    inventory = inventory or {}
    bank = bank or {}

    return inventory[item], bank[item]
end

function addon:GetItemByBank(bankName, item)
    local dbBank = self:GetBank(bankName)
    if not dbBank then return nil end

    local _return = {
        total = 0,
        players = {}
    }
    for player, _ in pairs(dbBank.players) do
        local inventory, bank = self:GetItemByPlayer(bankName, player, item)
        if inventory then
            _return.total = _return.total + inventory.stackCount
            _return.players[player] = {
                inventory = inventory
            }
        end
        if bank then
            _return.total = _return.total + bank.stackCount
            _return.players[player] = {
                bank = bank
            }
        end
    end

    if _return.total == 0 then
        return nil
    else
        return _return
    end
end

function addon:GetItemsByBank(bankName)
    local dbBank = self:GetBank(bankName)


end

function addon:GetPlayerRank(player)
    local index = 1
    local nextPlayer = true
    local gRank, gIndex = nil, nil

    while nextPlayer and not gRank do
        local name, rank, rankIndex = GetGuildRosterInfo(index)
        if name then
            name = strsplit('-', name)
            nextPlayer = true
            index = index + 1
            if name == player then
                gRank = rank
                gIndex = rankIndex
            end
        else
            nextPlayer = false
        end
    end

    if gRank then
        return gRank, gIndex
    else
        return nil
    end
end

function addon:GetMostRecentSync(bankName)
    local bank = self:GetBank(bankName)
    if not bank then
        return nil
    end

    local lastSyncs = {}
    for _, bankInfo in pairs(bank.players) do
        tinsert(lastSyncs, bankInfo.lastSync or 0)
    end

    -- No player data or no real sync timestamp: 0 was mistaken for "Unix epoch" in the UI (huge "hours ago").
    if #lastSyncs == 0 then
        return nil
    end

    local newest = max(unpack(lastSyncs))
    if not newest or newest <= 0 then
        return nil
    end

    return newest
end

--- Personal wishlist (shared across characters on faction+realm via SavedVariables).
function addon:GetPersonalWishlistRoot()
    if not (self.db and self.db.factionrealm) then return nil end
    self.db.factionrealm.personalWishlist = self.db.factionrealm.personalWishlist or {}
    return self.db.factionrealm.personalWishlist
end

function addon:GetPersonalWishlistItem(key)
    local root = self:GetPersonalWishlistRoot()
    if not root then return nil end
    return root[tostring(key)]
end

function addon:SetPersonalWishlistItem(key, item)
    local root = self:GetPersonalWishlistRoot()
    if not root then return end
    root[tostring(key)] = item
end

function addon:RemovePersonalWishlistItem(key)
    local root = self:GetPersonalWishlistRoot()
    if not root then return end
    root[tostring(key)] = nil
end

--- Legacy guild-wide wishlist (no longer synced; kept for SavedVariables compat).
function addon:GetWishlistItem(bankName, key)
    local dbBank = self:GetBank(bankName)
    if not dbBank then return nil end
    return dbBank.wishlist[key]
end

function addon:SetWishlistItem(bankName, key, item)
    local dbBank = self:GetBank(bankName)
    if not dbBank then return nil end

    dbBank.wishlist[key] = item
end

function addon:SetWishlist(bankName, data)
    local dbBank = self:GetBank(bankName)
    if not dbBank then return nil end

    dbBank.wishlist = data
end

function addon:SetBank(bankName, bankData)
    self.db.factionrealm.banks[bankName] = bankData or { players = {}, wishlist = {} }
    setmetatable(self.db.factionrealm.banks[bankName], { __index = function (table, key)
        table[key] = {
            players = {},
            wishlist = {}
        }
        return table[key]
    end})
    setmetatable(self.db.factionrealm.banks[bankName].players, {__index = function (table, key)
        table[key] = {
            bank = {},
            bags = {},
            money = 0,
            name = UnitName('player')
        }
        return table[key]
    end})
end

function addon:SetPlayerData(bankName, playerId, data)
    if not data.bags then data.bags = {} end
    if not data.bank then data.bank = {} end
    if not data.money then data.money = 0 end
    self.db.factionrealm.banks[bankName].players[playerId] = data
end

---
---@param bankName any
---@param playerName any
---@param itemLocation string|"bank"|"inventory"
---@param key string
---@param item any
function addon:SetItem(bankName, playerName, itemLocation, key, item)
    if itemLocation == 'bank' then
        self:Print("accessing bank "..bankName.." for player "..playerName.." bank at key "..key)
        self.db.factionrealm.banks[bankName].players[playerName].bank[key] = item
    else
        self.db.factionrealm.banks[bankName].players[playerName].bags[key] = item
    end
end