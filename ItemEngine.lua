----------------------------------------------------------------------
-- ItemEngine.lua - Simplified Item Evaluation Pipeline
-- Author: wealdly | Version: 1.0.0
----------------------------------------------------------------------

local addonName, JustJunk = ...
JustJunk.ItemEngine = {}

local C_Container = C_Container
local C_Item = C_Item
local C_CurrencyInfo = C_CurrencyInfo
local C_SpellBook = C_SpellBook
local C_ToyBox = C_ToyBox
local Enum = Enum
local GetAverageItemLevel = GetAverageItemLevel
local GetInventoryItemLink = GetInventoryItemLink
local ItemLocation = ItemLocation
local CursorHasItem = CursorHasItem
local ClearCursor = ClearCursor
local pcall = pcall
local ipairs = ipairs

----------------------------------------------------------------------
-- Equipment Slot Mapping
----------------------------------------------------------------------

local EQUIPMENT_SLOT_MAP = {
	["INVTYPE_HEAD"] = JustJunk.INVENTORY_SLOTS.HEAD,
	["INVTYPE_NECK"] = JustJunk.INVENTORY_SLOTS.NECK,
	["INVTYPE_SHOULDER"] = JustJunk.INVENTORY_SLOTS.SHOULDER,
	["INVTYPE_BODY"] = JustJunk.INVENTORY_SLOTS.BODY,
	["INVTYPE_CHEST"] = JustJunk.INVENTORY_SLOTS.CHEST,
	["INVTYPE_ROBE"] = JustJunk.INVENTORY_SLOTS.CHEST,
	["INVTYPE_WAIST"] = JustJunk.INVENTORY_SLOTS.WAIST,
	["INVTYPE_LEGS"] = JustJunk.INVENTORY_SLOTS.LEGS,
	["INVTYPE_FEET"] = JustJunk.INVENTORY_SLOTS.FEET,
	["INVTYPE_WRIST"] = JustJunk.INVENTORY_SLOTS.WRIST,
	["INVTYPE_HAND"] = JustJunk.INVENTORY_SLOTS.HAND,
	["INVTYPE_FINGER"] = {JustJunk.INVENTORY_SLOTS.FINGER1, JustJunk.INVENTORY_SLOTS.FINGER2},
	["INVTYPE_TRINKET"] = {JustJunk.INVENTORY_SLOTS.TRINKET1, JustJunk.INVENTORY_SLOTS.TRINKET2},
	["INVTYPE_CLOAK"] = JustJunk.INVENTORY_SLOTS.BACK,
	["INVTYPE_WEAPON"] = JustJunk.INVENTORY_SLOTS.MAINHAND,
	["INVTYPE_2HWEAPON"] = JustJunk.INVENTORY_SLOTS.MAINHAND,
	["INVTYPE_WEAPONMAINHAND"] = JustJunk.INVENTORY_SLOTS.MAINHAND,
	["INVTYPE_WEAPONOFFHAND"] = JustJunk.INVENTORY_SLOTS.OFFHAND,
	["INVTYPE_SHIELD"] = JustJunk.INVENTORY_SLOTS.OFFHAND,
	["INVTYPE_HOLDABLE"] = JustJunk.INVENTORY_SLOTS.OFFHAND,
	["INVTYPE_RANGED"] = JustJunk.INVENTORY_SLOTS.RANGED,
}

----------------------------------------------------------------------
-- State Management
----------------------------------------------------------------------

local averageItemLevel = nil
local soldThisSession = {}
local sellRetryCounts = {}
local sessionSettings = nil
local sessionSlots = nil
local sessionScanIndex = 1
local sessionProtectedBags = nil
local sessionReport = nil
local MAX_UNCONFIRMED_SELL_RETRIES = 2

local function GetSessionSlotKey(bag, slot)
	-- bag * 1000 leaves headroom for large bags without colliding across bags.
	return (bag * 1000) + slot
end

local function BuildSessionSlotList()
	local slots = {}
	for bag, slot in JustJunk.Utils.IterateBagSlots() do
		slots[#slots + 1] = { bag = bag, slot = slot }
	end
	return slots
end

local function BuildSessionProtectedBags()
	local protectedBags = {}
	for bagID = JustJunk.BAG_CONSTANTS.BACKPACK, JustJunk.BAG_CONSTANTS.MAX_BAGS do
		protectedBags[bagID] = JustJunk.Utils.IsBagProtected(bagID)
	end
	return protectedBags
end

local function EnsureSessionReport()
	if not sessionReport then
		sessionReport = {
			soldCount = 0,
			totalValue = 0,
			qualities = {},
			sources = {},
		}
	end
	return sessionReport
end

local function GetOverrideMode(itemID)
	if not itemID then return nil end

	local keepItems = sessionSettings and sessionSettings.forceKeepItems
	if not keepItems then
		keepItems = JustJunk.ConfigModule and JustJunk.ConfigModule.Get("merchant", "forceKeepItems")
	end
	if keepItems and keepItems[itemID] then
		return "keep"
	end

	local sellItems = sessionSettings and sessionSettings.forceSellItems
	if not sellItems then
		sellItems = JustJunk.ConfigModule and JustJunk.ConfigModule.Get("merchant", "forceSellItems")
	end
	if sellItems and sellItems[itemID] then
		return "sell"
	end

	return nil
end

-- Whether Poor (grey) items should be auto-sold. On by default; gates grey
-- selling across the native bulk pass, the per-item loop, and bag markers.
local function ShouldSellGreys()
	if sessionSettings then
		return sessionSettings.sellGreyJunk ~= false
	end
	return JustJunk.ConfigModule.Get("merchant", "sellGreyJunk") ~= false
end

local function AddSaleToReport(itemData, priceSource)
	if not itemData then return end

	local report = EnsureSessionReport()
	local stackCount = itemData.stackCount or 1
	local value = (itemData.vendorPrice or 0) * stackCount
	local quality = itemData.quality or 0
	local sourceKey = priceSource or "unknown"

	report.soldCount = report.soldCount + stackCount
	report.totalValue = report.totalValue + value
	report.qualities[quality] = (report.qualities[quality] or 0) + stackCount
	report.sources[sourceKey] = (report.sources[sourceKey] or 0) + stackCount
end

local function IsKnownSpell(spellID)
	if not spellID then return false end

	if C_SpellBook and C_SpellBook.IsSpellKnown then
		return C_SpellBook.IsSpellKnown(spellID)
	end

	return false
end

----------------------------------------------------------------------
-- Item Data Creation
----------------------------------------------------------------------

local function CreateItemData(bag, slot, containerInfo)
	containerInfo = containerInfo or C_Container.GetContainerItemInfo(bag, slot)
	if not containerInfo or not containerInfo.hyperlink then return nil end
	
	-- Note: GetItemInfo's 8th return is the item's MAX stack size, not the count
	-- in this slot. Use containerInfo.stackCount for the actual per-slot quantity.
	local name, _, quality, _, reqLevel, _, _, _, _, _, vendorPrice, classID, subClassID, bindType = C_Item.GetItemInfo(containerInfo.hyperlink)
	
	if not name or not classID or not vendorPrice or vendorPrice <= 0 then return nil end
	
	local location = JustJunk.Utils.CreateItemLocation(bag, slot)
	if not location then return nil end
	
	-- Check if item is actually soulbound (regardless of original bind type)
	local isSoulbound = C_Item.IsBound(location)
	
	return {
		itemID = containerInfo.itemID,
		itemName = name,
		itemLink = containerInfo.hyperlink,
		quality = quality or 0,
		itemLevel = C_Item.GetCurrentItemLevel(location) or 0,
		requiredLevel = reqLevel or 0,
		vendorPrice = vendorPrice or 0,
		classID = classID,
		subClassID = subClassID or 0,
		bindType = bindType or 0,
		isSoulbound = isSoulbound,  -- Actual soulbound status
		stackCount = containerInfo.stackCount or 1,
		bag = bag,
		slot = slot,
		location = location
	}
end

----------------------------------------------------------------------
-- Item Evaluation Functions
----------------------------------------------------------------------

local function CheckItemLevel(itemData)
	if not JustJunk.ConfigData.CONSTANTS.ENABLE_ITEM_LEVEL_CHECK then
		return true, "item level checking disabled"
	end

	local marginPercent = JustJunk.ConfigModule.Get("merchant", "gearSafetyPercent") or 10

	-- Prefer the item level equipped in this item's own slot; fall back to the
	-- player's average item level when that slot is empty.
	local reference = JustJunk.ItemEngine.GetEquippedItemLevelForSlot(itemData)
	if not reference then
		if not averageItemLevel then
			averageItemLevel = JustJunk.Utils.SafeCall(GetAverageItemLevel)
		end
		reference = averageItemLevel
	end

	if not reference or reference <= 0 then
		-- Nothing to compare against - keep the item to be safe.
		return false, "item level unknown, keeping"
	end

	local threshold = math.floor(reference * (1 - marginPercent / 100))
	if itemData.itemLevel <= threshold then
		return true, string.format("below safety threshold (ilvl %d <= %d)", itemData.itemLevel, threshold)
	end

	return false, string.format("within safety margin (ilvl %d > %d)", itemData.itemLevel, threshold)
end

local function CheckEquipmentSet(itemData)
	if JustJunk.ConfigData.CONSTANTS.IGNORE_SET_ITEMS and C_Container.GetContainerItemEquipmentSetInfo then
		local inSet = C_Container.GetContainerItemEquipmentSetInfo(itemData.bag, itemData.slot)
		if inSet then
			return false, "equipment set item"
		end
	end
	return true, "not in equipment set"
end

local function CheckAuctionValue(itemData, keepAbove)
	-- BoP, BoA, BoW items, and soulbound items can't be sold on AH
	if itemData.bindType == JustJunk.BIND_TYPE.PICKUP or
	   itemData.bindType == JustJunk.BIND_TYPE.ACCOUNT or
	   itemData.bindType == JustJunk.BIND_TYPE.WARBAND or
	   itemData.isSoulbound then
		return true, "soulbound item - auction value irrelevant", "bound"
	end

	local preferred = sessionSettings and sessionSettings.preferredPricingSource or JustJunk.ConfigModule.Get("merchant", "preferredPricingSource")
	local auctionPrice, source = JustJunk.MarketEngine.GetPrice(itemData.itemLink, preferred)
	if auctionPrice == 0 then
		if itemData.quality == 0 then
			return true, "grey item, safe to sell", source or "no_data"
		else
			return false, "non-grey item, unknown market value", source or "no_data"
		end
	end

	if auctionPrice > (keepAbove or 0) then
		return false, string.format("worth more on AH (%s: %s)",
			source, JustJunk.Utils.FormatMoney(auctionPrice)), source
	end

	return true, string.format("low auction value (%s data)", source), source
end

local function CheckRecipeKnown(itemData)
	local _, _, spellID = C_Item.GetItemSpell(itemData.itemLink)
	if spellID and IsKnownSpell(spellID) then
		return true, "recipe already known"
	end
	return false, "unknown recipe"
end

----------------------------------------------------------------------
-- Simplified Item Type Evaluation
----------------------------------------------------------------------

local function GetMerchantSetting(key, defaultValue)
	local value = JustJunk.ConfigModule.Get("merchant", key)
	if value == nil then return defaultValue end
	return value
end

local CATEGORY_RULES

local function BuildSessionSettings()
	local settings = {
		preferredPricingSource = GetMerchantSetting("preferredPricingSource", "auto"),
		sellGreyJunk = GetMerchantSetting("sellGreyJunk", true),
		forceKeepItems = GetMerchantSetting("forceKeepItems", {}),
		forceSellItems = GetMerchantSetting("forceSellItems", {}),
		categories = {}
	}

	for categoryName, rule in pairs(CATEGORY_RULES) do
		settings.categories[categoryName] = {
			enabled = GetMerchantSetting(rule.enableKey, true),
			maxQuality = GetMerchantSetting(rule.qualityKey, 4),
			keepAbove = GetMerchantSetting(rule.thresholdKey, 0),
		}
	end

	return settings
end

local function CheckMaxQuality(itemData, maxQuality)
	if itemData.quality > maxQuality then
		return false, string.format("quality too high (%s > %s)",
			JustJunk.Utils.GetQualityName(itemData.quality), JustJunk.Utils.GetQualityName(maxQuality))
	end
	return true
end

CATEGORY_RULES = {
	gear = {
		categoryName = "gear",
		enableKey = "enableGear",
		disabledReason = "gear selling disabled",
		qualityKey = "maxGearQuality",
		thresholdKey = "gearKeepAbove",
		preChecks = {CheckItemLevel, CheckEquipmentSet},
		passReason = "passed all gear checks",
	},
	consumable = {
		categoryName = "consumable",
		enableKey = "enableConsumables",
		disabledReason = "consumable selling disabled",
		qualityKey = "maxConsumableQuality",
		thresholdKey = "consumableKeepAbove",
		passReason = "passed all consumable checks",
	},
	tradeGood = {
		categoryName = "tradeGood",
		enableKey = "enableTradeGoods",
		disabledReason = "trade good selling disabled",
		qualityKey = "maxTradeGoodQuality",
		thresholdKey = "tradeGoodKeepAbove",
		passReason = "passed all trade good checks",
	},
	recipe = {
		categoryName = "recipe",
		enableKey = "enableRecipes",
		disabledReason = "recipe selling disabled",
		qualityKey = "maxRecipeQuality",
		thresholdKey = "recipeKeepAbove",
		preChecks = {CheckRecipeKnown},
		passReason = "passed all recipe checks",
	},
}

local function EvaluateCategory(itemData, rule)
	local categorySettings = sessionSettings and sessionSettings.categories and sessionSettings.categories[rule.categoryName]
	if not categorySettings then
		categorySettings = {
			enabled = GetMerchantSetting(rule.enableKey, true),
			maxQuality = GetMerchantSetting(rule.qualityKey, 4),
			keepAbove = GetMerchantSetting(rule.thresholdKey, 0),
		}
	end

	if not categorySettings.enabled then
		return false, rule.disabledReason
	end

	local qualityOk, qualityReason = CheckMaxQuality(itemData, categorySettings.maxQuality)
	if not qualityOk then return false, qualityReason end

	if rule.preChecks then
		for _, check in ipairs(rule.preChecks) do
			local passed, reason = check(itemData)
			if not passed then return false, reason end
		end
	end

	local shouldSell, reason, source = CheckAuctionValue(itemData, categorySettings.keepAbove)
	if not shouldSell then return false, reason end

	return true, rule.passReason, source
end

local CLASS_TO_CATEGORY = {
	[JustJunk.ITEM_CLASS.ARMOR] = "gear",
	[JustJunk.ITEM_CLASS.WEAPON] = "gear",
	[JustJunk.ITEM_CLASS.CONSUMABLE] = "consumable",
	[JustJunk.ITEM_CLASS.CONTAINER] = "consumable",
	[JustJunk.ITEM_CLASS.GEM] = "consumable",
	[JustJunk.ITEM_CLASS.TRADEGOOD] = "tradeGood",
	[JustJunk.ITEM_CLASS.REAGENT] = "tradeGood",
	[JustJunk.ITEM_CLASS.ITEM_ENHANCEMENT] = "tradeGood",
	[JustJunk.ITEM_CLASS.RECIPE] = "recipe",
}

----------------------------------------------------------------------
-- Core Evaluation Function
----------------------------------------------------------------------

function JustJunk.ItemEngine.EvaluateItemForSelling(itemData)
	if not itemData or not itemData.classID then
		return false, "invalid item data"
	end
	
	-- Check if item can be sold to vendor
	if not itemData.vendorPrice or itemData.vendorPrice <= 0 then
		return false, "item has no vendor value"
	end
	
	-- Check for quest items
	if itemData.classID == Enum.ItemClass.Questitem then
		return false, "quest item cannot be sold"
	end

	local overrideMode = GetOverrideMode(itemData.itemID)
	if overrideMode == "keep" then
		return false, "manually kept"
	elseif overrideMode == "sell" then
		return true, "manual sell override", "manual"
	end

	-- Grey (Poor) items are auto-sold unless the player turns it off.
	if itemData.quality == 0 and not ShouldSellGreys() then
		return false, "grey selling disabled"
	end

	-- Strongly protect BoA/BoW items - other characters may need them
	if itemData.bindType == JustJunk.BIND_TYPE.ACCOUNT or itemData.bindType == JustJunk.BIND_TYPE.WARBAND then
		-- Only allow selling BoA/BoW consumables if they're grey quality
		if (itemData.classID == JustJunk.ITEM_CLASS.CONSUMABLE or 
		    itemData.classID == JustJunk.ITEM_CLASS.TRADEGOOD) and 
		   itemData.quality == 0 then
			-- Allow selling grey BoA/BoW consumables/trade goods
		else
			return false, "BoA/BoW item protected - other characters may need it"
		end
	end

	-- Check for battle pets
	if itemData.classID == JustJunk.ITEM_CLASS.BATTLEPET then
		return false, "battle pet item"
	end

	-- Never sell housing decor
	if itemData.classID == JustJunk.ITEM_CLASS.HOUSING then
		return false, "housing item should not be sold"
	end

	-- Check for special miscellaneous items
	if itemData.classID == Enum.ItemClass.Miscellaneous then
		if C_ToyBox and C_ToyBox.GetToyInfo and C_ToyBox.GetToyInfo(itemData.itemID) then
			return false, "toy collectible"
		end

		if C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfoFromLink then
			local success, currencyInfo = pcall(C_CurrencyInfo.GetCurrencyInfoFromLink, itemData.itemLink)
			if success and currencyInfo and currencyInfo.currencyID then
				return false, "currency item"
			end
		end

		if itemData.subClassID == Enum.ItemMiscellaneousSubclass.Mount then
			return false, "mount item should not be sold"
		end
		if itemData.subClassID == Enum.ItemMiscellaneousSubclass.CompanionPet then
			return false, "pet item should not be sold"
		end
	end
	
	-- Protect soulbound crafting materials (trade goods, reagents, enhancements):
	-- these are typically character-bound mats you crafted/earned, not vendor junk.
	if itemData.bindType == JustJunk.BIND_TYPE.PICKUP and (
		itemData.classID == JustJunk.ITEM_CLASS.TRADEGOOD or
		itemData.classID == JustJunk.ITEM_CLASS.REAGENT or
		itemData.classID == JustJunk.ITEM_CLASS.ITEM_ENHANCEMENT) then
		return false, "BoP crafting material should not be sold"
	end

	-- Any Poor (grey) item that survived the protections above is junk - sell it
	-- regardless of category, matching the native bulk grey sell. (Grey selling is
	-- already gated by the ShouldSellGreys() check earlier.)
	if itemData.quality == 0 then
		return true, "grey junk", "grey"
	end

	-- Direct item type evaluation
	local categoryName = CLASS_TO_CATEGORY[itemData.classID]
	local categoryRule = categoryName and CATEGORY_RULES[categoryName]
	if categoryRule then
		return EvaluateCategory(itemData, categoryRule)
	end
	
	return false, "unsupported item class"
end

----------------------------------------------------------------------
-- Item Level Management
----------------------------------------------------------------------

function JustJunk.ItemEngine.GetEquippedItemLevelForSlot(itemData)
	if not itemData or not itemData.itemLink then return nil end
	
	local equipSlot = JustJunk.Utils.GetEquipSlotForItem(itemData.itemLink)
	if not equipSlot then return nil end
	
	local slots = EQUIPMENT_SLOT_MAP[equipSlot]
	if not slots then return nil end
	
	-- Handle single slots
	if type(slots) == "number" then
		local itemLink = GetInventoryItemLink("player", slots)
		if itemLink then
			local location = ItemLocation:CreateFromEquipmentSlot(slots)
			if location and location:IsValid() then
				return C_Item.GetCurrentItemLevel(location)
			end
		end
		return nil
	end
	
	-- Handle multiple slots (rings, trinkets) - return lowest level
	local lowestLevel = nil
	for _, slotID in ipairs(slots) do
		local itemLink = GetInventoryItemLink("player", slotID)
		if itemLink then
			local location = ItemLocation:CreateFromEquipmentSlot(slotID)
			if location and location:IsValid() then
				local level = C_Item.GetCurrentItemLevel(location)
				if level and (not lowestLevel or level < lowestLevel) then
					lowestLevel = level
				end
			end
		end
	end
	
	return lowestLevel
end

----------------------------------------------------------------------
-- Selling Operations
----------------------------------------------------------------------

-- Decision profiles keep marker overlays and sell-session scans explicit.
local SLOT_DECISION_PROFILES = {
	marker = {
		checkProtectedBag = true,
		greyFastPath = true,
		allowUncachedGreyFallback = true,
	},
	session = {
		checkProtectedBag = false,
		greyFastPath = false,
		allowUncachedGreyFallback = false,
	},
}

local function EvaluateBagSlotDecision(bag, slot, slotInfo, options)
	if not bag or not slot then return false, "invalid slot", nil, nil end

	options = options or {}
	if options.checkProtectedBag and JustJunk.Utils.IsBagProtected(bag) then
		return false, "protected bag", nil, nil
	end

	slotInfo = slotInfo or C_Container.GetContainerItemInfo(bag, slot)
	if not slotInfo then
		return false, "empty slot", nil, nil
	end

	if slotInfo.isLocked then
		return false, "locked slot", nil, nil
	end

	local overrideMode = GetOverrideMode(slotInfo.itemID)
	if overrideMode == "keep" then
		return false, "manually kept", nil, nil
	elseif overrideMode == "sell" then
		return true, "manual sell override", "manual", nil
	end

	if options.greyFastPath and ShouldSellGreys() and slotInfo.quality == 0 and not slotInfo.hasNoValue then
		return true, "grey item, safe to sell", "grey_fastpath", nil
	end

	local itemData = CreateItemData(bag, slot, slotInfo)
	if not itemData then
		if options.allowUncachedGreyFallback and ShouldSellGreys() and slotInfo.quality == 0 and not slotInfo.hasNoValue then
			return true, "grey fallback (uncached item info)", "grey_fallback", nil
		end
		return false, "item info unavailable", nil, nil
	end

	local shouldSell, reason, priceSource = JustJunk.ItemEngine.EvaluateItemForSelling(itemData)
	return shouldSell == true, reason, priceSource, itemData
end

local function ShouldLogKeepReason(reason)
	return reason and (reason:find("AH") or reason:find("upgrade") or reason:find("set") or reason:find("known") or reason:find("manual"))
end

local function AdvanceSessionSlot(sessionKey, markProcessed)
	if markProcessed then
		soldThisSession[sessionKey] = true
	end
	sessionScanIndex = sessionScanIndex + 1
end

local function ProcessSellSessionSlot(slotData)
	if not slotData then
		sessionScanIndex = sessionScanIndex + 1
		return false, false
	end

	local bag = slotData.bag
	local slot = slotData.slot
	if not bag or not slot then
		sessionScanIndex = sessionScanIndex + 1
		return false, false
	end

	if sessionProtectedBags and sessionProtectedBags[bag] then
		sessionScanIndex = sessionScanIndex + 1
		return false, false
	end

	local sessionKey = GetSessionSlotKey(bag, slot)
	if soldThisSession[sessionKey] then
		sessionScanIndex = sessionScanIndex + 1
		return false, false
	end

	local slotInfo = C_Container.GetContainerItemInfo(bag, slot)
	if slotInfo and slotInfo.isLocked then
		sessionScanIndex = sessionScanIndex + 1
		return false, true
	end

	local shouldSell, reason, priceSource, itemData = EvaluateBagSlotDecision(
		bag,
		slot,
		slotInfo,
		SLOT_DECISION_PROFILES.session
	)

	if not shouldSell then
		-- Uncached item-info paths should be revisited in future scans.
		if reason == "item info unavailable" then
			sessionScanIndex = sessionScanIndex + 1
			return false, false
		end

		AdvanceSessionSlot(sessionKey, true)
		if ShouldLogKeepReason(reason) and itemData and itemData.itemLink then
			JustJunk.Utils.Debug("Item", string.format("KEEP %s: %s", itemData.itemLink, reason))
		end
		return false, false
	end

	local preInfo = C_Container.GetContainerItemInfo(bag, slot)
	local preItemID = preInfo and preInfo.itemID

	local used = pcall(C_Container.UseContainerItem, bag, slot)
	if CursorHasItem and CursorHasItem() then ClearCursor() end

	if used then
		local postInfo = C_Container.GetContainerItemInfo(bag, slot)
		local postItemID = postInfo and postInfo.itemID

		if postItemID ~= preItemID then
			AdvanceSessionSlot(sessionKey, true)
			sellRetryCounts[sessionKey] = nil
			if itemData then
				AddSaleToReport(itemData, priceSource)
				JustJunk.Utils.Debug("Item", string.format("SOLD %s: %s", itemData.itemLink, reason))
			end
			return true, false
		end
	end

	sellRetryCounts[sessionKey] = (sellRetryCounts[sessionKey] or 0) + 1
	if sellRetryCounts[sessionKey] >= MAX_UNCONFIRMED_SELL_RETRIES then
		AdvanceSessionSlot(sessionKey, true)
		if itemData and itemData.itemLink then
			JustJunk.Utils.Debug("Item", string.format("SKIP %s: sell unconfirmed after retries", itemData.itemLink))
		else
			JustJunk.Utils.Debug("Item", string.format("SKIP bag %d slot %d: sell unconfirmed after retries", bag, slot))
		end
		return false, false
	end

	if itemData and itemData.itemLink then
		JustJunk.Utils.Debug("Item", string.format("RETRY %s: sell not confirmed", itemData.itemLink))
	else
		JustJunk.Utils.Debug("Item", string.format("RETRY bag %d slot %d: sell not confirmed", bag, slot))
	end
	return true, false
end

function JustJunk.ItemEngine.SellNextItem()
	local hasLockedItems = false

	if not sessionSlots then
		sessionSlots = BuildSessionSlotList()
	end
	if not sessionProtectedBags then
		sessionProtectedBags = BuildSessionProtectedBags()
	end

	while sessionScanIndex <= #sessionSlots do
		local slotData = sessionSlots[sessionScanIndex]
		local soldOrRetried, encounteredLocked = ProcessSellSessionSlot(slotData)
		if encounteredLocked then
			hasLockedItems = true
		end
		if soldOrRetried then
			return true
		end
	end

	-- If we encountered locked slots, restart scan next tick so they can be retried.
	if hasLockedItems then
		sessionScanIndex = 1
	end

	return hasLockedItems
end

function JustJunk.ItemEngine.ResetSellSession()
	soldThisSession = {}
	sellRetryCounts = {}
	averageItemLevel = nil
	sessionSettings = BuildSessionSettings()
	sessionSlots = BuildSessionSlotList()
	sessionScanIndex = 1
	sessionProtectedBags = BuildSessionProtectedBags()
	sessionReport = {
		soldCount = 0,
		totalValue = 0,
		qualities = {},
		sources = {},
	}
end

function JustJunk.ItemEngine.GetSellSessionReport()
	return sessionReport
end

-- Delegate grey (Poor) junk to WoW's native bulk sell, which is instant and
-- honors the bag exclude-from-junk flag. Returns false (so the per-item loop
-- handles greys instead) when a manually kept grey is present, so keep overrides
-- are never violated. Slots it sells are marked handled to avoid the per-item
-- loop double-selling/double-counting them (the native sale resolves async).
function JustJunk.ItemEngine.SellGreyJunkNatively()
	if not ShouldSellGreys() then
		return false
	end

	if not (C_MerchantFrame and C_MerchantFrame.SellAllJunkItems
			and C_MerchantFrame.IsSellAllJunkEnabled and C_MerchantFrame.IsSellAllJunkEnabled()) then
		return false
	end

	local greyKeys = {}
	local count, value = 0, 0

	for bag, slot in JustJunk.Utils.IterateBagSlots() do
		if not JustJunk.Utils.IsBagProtected(bag) then
			local info = C_Container.GetContainerItemInfo(bag, slot)
			if info and info.quality == 0 and not info.hasNoValue and info.itemID then
				if GetOverrideMode(info.itemID) == "keep" then
					return false
				end

				local stack = info.stackCount or 1
				local sellPrice = 0
				if info.hyperlink then
					local _, _, _, _, _, _, _, _, _, _, sp = C_Item.GetItemInfo(info.hyperlink)
					sellPrice = sp or 0
				end

				greyKeys[#greyKeys + 1] = GetSessionSlotKey(bag, slot)
				count = count + stack
				value = value + sellPrice * stack
			end
		end
	end

	if count == 0 then
		return false
	end

	if not pcall(C_MerchantFrame.SellAllJunkItems) then
		return false
	end

	for _, key in ipairs(greyKeys) do
		soldThisSession[key] = true
	end

	local report = EnsureSessionReport()
	report.soldCount = report.soldCount + count
	report.totalValue = report.totalValue + value
	report.qualities[0] = (report.qualities[0] or 0) + count
	report.sources["junk"] = (report.sources["junk"] or 0) + count

	JustJunk.Utils.Debug("Item", string.format("Native sell-all junk: %d item(s) for %s",
		count, JustJunk.Utils.FormatMoney(value)))
	return true
end

function JustJunk.ItemEngine.RefreshSessionSettings()
	sessionSettings = BuildSessionSettings()
	sessionProtectedBags = BuildSessionProtectedBags()
end

function JustJunk.ItemEngine.ShouldSellBagSlot(bag, slot)
	local shouldSell = EvaluateBagSlotDecision(bag, slot, nil, SLOT_DECISION_PROFILES.marker)
	return shouldSell == true
end

----------------------------------------------------------------------
-- Public API
----------------------------------------------------------------------

function JustJunk.ItemEngine.OnEquipmentChanged()
	averageItemLevel = nil
end

function JustJunk.ItemEngine.Initialize()
	JustJunk.Utils.Debug("Item", "Item engine initialized")
end