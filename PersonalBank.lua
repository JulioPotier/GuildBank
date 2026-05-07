local addon = BeanBank

local function ensurePersonalDB()
    if not addon.db then return end
    addon.db.factionrealm.personalBank = addon.db.factionrealm.personalBank or {}
    local pb = addon.db.factionrealm.personalBank
    -- Multi-character store (account-wide within factionrealm).
    pb.characters = pb.characters or {}
    pb.lastCapture = pb.lastCapture or 0
    pb.lastCharacter = pb.lastCharacter or nil

    -- Migration from older single-character schema.
    if pb.items then
        local legacyChar = pb.character or (UnitNameUnmodified and UnitNameUnmodified("player") or UnitName("player")) or "Unknown"
        pb.characters[legacyChar] = pb.characters[legacyChar] or {}
        -- Old schema had a single merged table; keep it as bankItems so nothing is lost.
        pb.characters[legacyChar].bankItems = pb.characters[legacyChar].bankItems or pb.items
        pb.characters[legacyChar].bagItems = pb.characters[legacyChar].bagItems or {}
        pb.characters[legacyChar].settings = pb.characters[legacyChar].settings or { shareBank = true, shareBags = false }
        pb.characters[legacyChar].lastCapture = pb.lastCapture or pb.characters[legacyChar].lastCapture or 0
        pb.items = nil
        pb.character = nil
    end

    -- Migration from earlier multi-character schemas:
    -- - characters[char].items (merged) -> bankItems (can't reliably split bank vs bags)
    -- - missing settings/bankItems/bagItems -> initialize
    for _, charData in pairs(pb.characters) do
        if charData then
            if charData.items and not charData.bankItems then
                charData.bankItems = charData.items
            elseif charData.items and charData.bankItems then
                -- Prefer existing bankItems; keep any missing entries from items
                for k, v in pairs(charData.items) do
                    if charData.bankItems[k] == nil then
                        charData.bankItems[k] = v
                    end
                end
            end
            charData.items = nil

            charData.bankItems = charData.bankItems or {}
            charData.bagItems = charData.bagItems or {}
            charData.settings = charData.settings or { shareBank = true, shareBags = false }
            if charData.settings.shareBank == nil then charData.settings.shareBank = true end
            if charData.settings.shareBags == nil then charData.settings.shareBags = false end
        end
    end
end

function addon:ResetPersonal(characterName)
    ensurePersonalDB()
    if not (self.db and self.db.factionrealm and self.db.factionrealm.personalBank) then return end
    local pb = self.db.factionrealm.personalBank
    if not pb.characters then pb.characters = {} end

    local char = characterName
    if not char or char == "" then
        char = UnitNameUnmodified and UnitNameUnmodified("player") or UnitName("player") or "Unknown"
    end

    if pb.characters[char] then
        pb.characters[char] = nil
    end

    -- Recompute lastCapture/lastCharacter to a sane value.
    local bestChar, bestTs = nil, 0
    for name, data in pairs(pb.characters) do
        local ts = data and data.lastCapture or 0
        if ts and ts > bestTs then
            bestTs = ts
            bestChar = name
        end
    end
    pb.lastCapture = bestTs
    pb.lastCharacter = bestChar
end

function addon:CapturePersonalBankSnapshot()
    ensurePersonalDB()
    if not self.db then
        return
    end
    if not self.db.factionrealm or not self.db.factionrealm.personalBank then
        return
    end

    -- Per-character preferences live in db.char, but we store them with the snapshot in the shared DB.
    local share = (self.db.char and self.db.char.personal) or {}
    local shareBank = share.shareBank == true
    local shareBags = share.shareBags == true
    if not shareBank and not shareBags then
        return
    end

    local pb = self.db.factionrealm.personalBank
    local char = UnitNameUnmodified and UnitNameUnmodified("player") or UnitName("player") or "Unknown"
    pb.characters[char] = pb.characters[char] or {}
    pb.characters[char].bankItems = pb.characters[char].bankItems or {}
    pb.characters[char].bagItems = pb.characters[char].bagItems or {}
    pb.characters[char].settings = pb.characters[char].settings or {}
    pb.characters[char].settings.shareBank = shareBank
    pb.characters[char].settings.shareBags = shareBags
    pb.characters[char].lastCapture = GetServerTime()
    pb.lastCapture = pb.characters[char].lastCapture
    pb.lastCharacter = char

    -- Reset only the sources we are capturing now.
    if shareBank then pb.characters[char].bankItems = {} end
    if shareBags then pb.characters[char].bagItems = {} end

    local function recordItem(dest, item)
        if not dest or not (item and item.hyperlink and item.stackCount) then return end
        local suffixID = select(8, strsplit(':', item.hyperlink))
        local itemIdWithSuffix = item.itemID
        if suffixID and suffixID ~= "" then
            itemIdWithSuffix = tostring(itemIdWithSuffix) .. ":" .. suffixID
        else
            itemIdWithSuffix = tostring(itemIdWithSuffix)
        end
        local entry = dest[itemIdWithSuffix]
        if entry then
            entry.stackCount = (entry.stackCount or 0) + item.stackCount
        else
            dest[itemIdWithSuffix] = {
                itemID = item.itemID,
                hyperlink = item.hyperlink,
                iconFileID = item.iconFileID,
                quality = item.quality,
                stackCount = item.stackCount,
            }
        end
    end

    local scannedSlots, foundStacks, uniqueItems = 0, 0, 0
    local function scanBagsInto(dest, fromBag, toBag, bankMode)
        for bag = fromBag, toBag do
            if not bankMode and (bag < 0 or bag > 4) then
                -- non-bag
            elseif bankMode and (bag >= 0 and bag <= 4) then
                -- skip player bags
            else
                local slots = C_Container.GetContainerNumSlots(bag)
                if slots and slots > 0 then
                    for slotNumber = 1, slots do
                        scannedSlots = scannedSlots + 1
                        local item = C_Container.GetContainerItemInfo(bag, slotNumber)
                        if item and item.hyperlink and item.stackCount then
                            local before = dest[tostring(item.itemID)] ~= nil
                            recordItem(dest, item)
                            foundStacks = foundStacks + item.stackCount
                            if not before then uniqueItems = uniqueItems + 1 end
                        end
                    end
                end
            end
        end
    end

    if shareBags then
        scanBagsInto(pb.characters[char].bagItems, 0, 4, false)
    end

    if shareBank then
        -- Detect bank containers dynamically, fallback to common indices.
        local anyBankSlots = false
        for bag = -1, 11 do
            if bag < 0 or bag > 4 then
                local slots = C_Container.GetContainerNumSlots(bag)
                if slots and slots > 0 then
                    anyBankSlots = true
                    break
                end
            end
        end
        if anyBankSlots then
            scanBagsInto(pb.characters[char].bankItems, -1, 11, true)
        else
            for _, bag in ipairs({ -1, 5, 6, 7, 8, 9, 10, 11 }) do
                local slots = C_Container.GetContainerNumSlots(bag)
                if slots and slots > 0 then
                    for slotNumber = 1, slots do
                        scannedSlots = scannedSlots + 1
                        local item = C_Container.GetContainerItemInfo(bag, slotNumber)
                        if item and item.hyperlink and item.stackCount then
                            local before = pb.characters[char].bankItems[tostring(item.itemID)] ~= nil
                            recordItem(pb.characters[char].bankItems, item)
                            foundStacks = foundStacks + item.stackCount
                            if not before then uniqueItems = uniqueItems + 1 end
                        end
                    end
                end
            end
        end
    end
end

function addon:CreatePersonalFrame()
    ensurePersonalDB()
    local pb = self.db and self.db.factionrealm and self.db.factionrealm.personalBank
    local charCount = 0
    local totalUniqueItems = 0
    if pb and pb.characters then
        for _, c in pairs(pb.characters) do
            charCount = charCount + 1
            if c.items then
                for _ in pairs(c.items) do totalUniqueItems = totalUniqueItems + 1 end
            end
        end
    end
    local parentContainer = self.LIBS.aceGUI:Create('SimpleGroup')
    parentContainer:SetLayout("Flow")

    local header = self.LIBS.aceGUI:Create('Label')
    if not pb or not pb.characters or not pb.lastCapture or pb.lastCapture == 0 then
        header:SetText("No personal snapshot yet. Open your bank once on each character.")
    else
        local lastChar = pb.lastCharacter or "?"
        header:SetText("Snapshots: "..tostring(charCount).." characters — latest: "..lastChar.." ("..SecondsToTime(GetServerTime() - pb.lastCapture).." ago)")
    end
    parentContainer:AddChild(header)

    -- Quality filter (strict match).
    self.db.profile.qualityFilters = self.db.profile.qualityFilters or {}
    -- Backwards compat for earlier "min quality" implementation.
    if self.db.profile.qualityFilters.personalQuality == nil and type(self.db.profile.qualityFilters.personalMinQuality) == "number" then
        self.db.profile.qualityFilters.personalQuality = self.db.profile.qualityFilters.personalMinQuality
    end
    if type(self.db.profile.qualityFilters.personalQuality) ~= "number" then
        self.db.profile.qualityFilters.personalQuality = -1
    end
    local function getQualityFilter()
        return self.db.profile.qualityFilters.personalQuality or -1
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
    local qualityDropdown = self.LIBS.aceGUI:Create("Dropdown")
    qualityDropdown:SetLabel("Quality filter")
    qualityDropdown:SetList(qualityLabels)
    local searchBar = self.LIBS.aceGUI:Create("EditBox")
    searchBar:DisableButton(true)
    -- Put dropdown + search on the same row.
    local filterRow = self.LIBS.aceGUI:Create('SimpleGroup')
    filterRow:SetLayout("Flow")
    filterRow:SetFullWidth(true)
    qualityDropdown:SetValue(getQualityFilter())
    qualityDropdown:SetWidth(160)
    searchBar:SetWidth(340)
    filterRow:AddChild(qualityDropdown)
    filterRow:AddChild(searchBar)
    parentContainer:AddChild(filterRow)

    local tree = self.LIBS.aceGUI:Create("TreeGroup")
    tree.treeframe:SetWidth(500)
    tree:SetLayout("Fill")
    tree:SetFullHeight(true)
    tree:EnableButtonTooltips(true)
    tree:SetFullWidth(true)
    parentContainer:AddChild(tree)

    local function hideTooltip()
        if GameTooltip and GameTooltip:IsShown() then
            GameTooltip:Hide()
        end
    end

    local function maybeShowItemTooltip(anchorFrame, itemKey)
        if not (self.db and self.db.profile and self.db.profile.tooltip and self.db.profile.tooltip.show) then
            return
        end
        if not (pb and pb._aggregated and itemKey and pb._aggregated[itemKey]) then
            return
        end
        local item = pb._aggregated[itemKey]
        if not item or (not item.hyperlink and not item.itemID) then return end
        if not (GameTooltip and GameTooltip.SetOwner and GameTooltip.SetHyperlink) then return end

        GameTooltip:SetOwner(anchorFrame or UIParent, "ANCHOR_RIGHT")
        local function setTooltipNow()
            if item.hyperlink then
                GameTooltip:SetHyperlink(item.hyperlink)
            elseif item.itemID then
                -- Fallback if hyperlink is missing
                GameTooltip:SetItemByID(item.itemID)
            end
            GameTooltip:Show()
        end

        -- If item data isn't cached yet, the tooltip can show only the title line.
        -- Request item data then refresh once it's loaded.
        if Item and (item.hyperlink or item.itemID) then
            local it = item.hyperlink and Item:CreateFromItemLink(item.hyperlink) or Item:CreateFromItemID(item.itemID)
            if it and it.ContinueOnItemLoad then
                it:ContinueOnItemLoad(function()
                    -- Refresh tooltip if still visible (and user didn't switch away)
                    if GameTooltip and GameTooltip:IsShown() then
                        setTooltipNow()
                    end
                end)
            end
        elseif C_Item and C_Item.RequestLoadItemDataByID and item.itemID then
            C_Item.RequestLoadItemDataByID(item.itemID)
        end

        setTooltipNow()
    end

    local function rebuildAggregated()
        if not pb or not pb.characters then
            pb._aggregated = {}
            return
        end
        local agg = {}
        for charName, charData in pairs(pb.characters) do
            if charData then
                local settings = charData.settings or { shareBank = true, shareBags = false }
                local function addFromSource(items)
                    if not items then return end
                    for itemKey, item in pairs(items) do
                        local a = agg[itemKey]
                        if not a then
                            agg[itemKey] = {
                                itemID = item.itemID,
                                hyperlink = item.hyperlink,
                                iconFileID = item.iconFileID,
                                quality = item.quality,
                                stackCount = item.stackCount or 0,
                                characters = { [charName] = (item.stackCount or 0) },
                            }
                        else
                            a.stackCount = (a.stackCount or 0) + (item.stackCount or 0)
                            a.characters = a.characters or {}
                            a.characters[charName] = (a.characters[charName] or 0) + (item.stackCount or 0)
                        end
                    end
                end

                if settings.shareBank then
                    addFromSource(charData.bankItems)
                end
                if settings.shareBags then
                    addFromSource(charData.bagItems)
                end
            end
        end
        pb._aggregated = agg
    end

    local function buildTree(filterText)
        local t = {}
        local cpt = 1
        if not pb or not pb.characters then
            tree:SetTree({})
            return
        end
        rebuildAggregated()
        filterText = filterText and string.lower(filterText) or ""
        local filterQ = getQualityFilter()
        for itemKey, item in pairs(pb._aggregated or {}) do
            local q = item and item.quality
            local passQuality = true
            if filterQ ~= -1 then
                passQuality = type(q) == "number" and q == filterQ
            end
            local name = item.hyperlink or tostring(itemKey)
            if passQuality and (filterText == "" or string.find(string.lower(name), filterText, 1, true)) then
                t[cpt] = {
                    value = itemKey,
                    text = tostring(item.stackCount or 0) .. " " .. name,
                    icon = item.iconFileID,
                    sortValue = name,
                    children = {},
                }
                local childIdx = 1
                if item.characters then
                    for charName, cnt in pairs(item.characters) do
                        t[cpt].children[childIdx] = {
                            value = itemKey, -- keep itemKey so tooltip still works
                            text = charName .. " : " .. tostring(cnt or 0),
                        }
                        childIdx = childIdx + 1
                    end
                end
                cpt = cpt + 1
            end
        end
        tree:SetTree(self:SortTreeViewItems(t))
    end

    searchBar:SetCallback('OnTextChanged', function(_, _, text)
        buildTree(text)
    end)

    qualityDropdown:SetCallback("OnValueChanged", function(_, _, v)
        if type(v) ~= "number" then v = tonumber(v) end
        if type(v) ~= "number" then v = -1 end
        self.db.profile.qualityFilters.personalQuality = v
        buildTree(searchBar:GetText() or "")
    end)

    -- Show tooltip when selecting an item in the tree.
    tree:SetCallback("OnGroupSelected", function(widget, _, value)
        hideTooltip()
        -- 'value' is the selected node value (we set it to itemKey)
        local anchor = widget and widget.frame or UIParent
        maybeShowItemTooltip(anchor, value)
    end)

    -- Hide tooltip when frame is released/closed.
    parentContainer.frame:HookScript("OnHide", hideTooltip)

    buildTree("")

    return parentContainer
end

-- Capture automatically when bank opens (no guild rank gating).
if hooksecurefunc then
    hooksecurefunc(addon, "BANKFRAME_OPENED", function()
        addon:CapturePersonalBankSnapshot()
    end)
end

