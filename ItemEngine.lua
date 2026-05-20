----------------------------------------------------------------------
-- ItemEngine.lua - Simplified Item Evaluation Pipeline
-- Author: wealdly | Version: 1.0.0
----------------------------------------------------------------------

local addonName, JustJunk = ...
JustJunk.ItemEngine = {}

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

local function CreateItemData(bag, slot)
	local containerInfo = C_Container.GetContainerItemInfo(bag, slot)
	if not containerInfo or not containerInfo.hyperlink then return nil end
	
	local itemInfo = {C_Item.GetItemInfo(containerInfo.hyperlink)}
	local name, _, quality, _, reqLevel, _, _, stackCount, _, _, vendorPrice, classID, subClassID, bindType = 
		itemInfo[1], itemInfo[2], itemInfo[3], itemInfo[4], itemInfo[5], itemInfo[6], itemInfo[7],
		itemInfo[8], itemInfo[9], itemInfo[10], itemInfo[11], itemInfo[12], itemInfo[13], itemInfo[14]
	
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
		stackCount = stackCount or 1,
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
	
	local useSlotComparison = JustJunk.ConfigModule.Get("merchant", "useSlotComparison")
	local useAverageComparison = JustJunk.ConfigModule.Get("merchant", "useAverageComparison")
	
	-- 1. Slot-based comparison (highest priority)
	if useSlotComparison then
		local equippedLevel = JustJunk.ItemEngine.GetEquippedItemLevelForSlot(itemData)
		if equippedLevel then
			local upgradeThreshold = JustJunk.ConfigModule.Get("merchant", "slotUpgradeThreshold") or 5
			if itemData.itemLevel > equippedLevel - upgradeThreshold then
				return false, string.format("potential slot upgrade (ilvl %d vs equipped %d)", itemData.itemLevel, equippedLevel)
			else
				return true, string.format("slot downgrade (ilvl %d vs equipped %d)", itemData.itemLevel, equippedLevel)
			end
		end
	end
	
	-- 2. Average-based comparison (second priority)
	if useAverageComparison then
		if not averageItemLevel then
			averageItemLevel = JustJunk.Utils.SafeCall(GetAverageItemLevel)
		end
		
		if averageItemLevel and averageItemLevel > 0 then
			local gearLevelModifierPercent = JustJunk.ConfigModule.Get("merchant", "gearLevelModifierPercent") or 5
			local threshold = math.floor(averageItemLevel * (1 - gearLevelModifierPercent / 100))
			
			if itemData.itemLevel <= threshold then
				return true, string.format("below average threshold (ilvl %d ≤ %d, avg: %d)", itemData.itemLevel, threshold, averageItemLevel)
			else
				return false, string.format("above average threshold (ilvl %d > %d, avg: %d)", itemData.itemLevel, threshold, averageItemLevel)
			end
		end
	end
	
	-- 3. Fallback threshold (lowest priority)
	if JustJunk.ConfigData.CONSTANTS.USE_FALLBACK_THRESHOLD then
		local fallbackThreshold = JustJunk.ConfigModule.Get("merchant", "fallbackItemLevelThreshold") or 50
		if itemData.itemLevel <= fallbackThreshold then
			return true, string.format("below fallback threshold (ilvl %d ≤ %d)", itemData.itemLevel, fallbackThreshold)
		else
			return false, string.format("above fallback threshold (ilvl %d > %d)", itemData.itemLevel, fallbackThreshold)
		end
	end
	
	return true, "no item level evaluation criteria active"
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

local function CheckAuctionValue(itemData, config)
	-- BoP, BoA, BoW items, and soulbound items can't be sold on AH
	if itemData.bindType == JustJunk.BIND_TYPE.PICKUP or 
	   itemData.bindType == JustJunk.BIND_TYPE.ACCOUNT or 
	   itemData.bindType == JustJunk.BIND_TYPE.WARBAND or
	   itemData.isSoulbound then
		return true, "soulbound item - auction value irrelevant"
	end
	
	local preferred = JustJunk.ConfigModule.Get("merchant", "preferredPricingSource")
	local auctionPrice, source = JustJunk.MarketEngine.GetPrice(itemData.itemLink, preferred)
	if auctionPrice == 0 then
		if itemData.quality == 0 then
			return true, "grey item, safe to sell"
		else
			return false, "non-grey item, unknown market value"
		end
	end
	
	local minThreshold = config.minThreshold
	local multiplier = config.multiplier
	local safeVendorPrice = itemData.vendorPrice * multiplier
	
	if auctionPrice > safeVendorPrice and auctionPrice > minThreshold then
		return false, string.format("worth more on AH (%s: %s vs vendor %s)", 
			source, JustJunk.Utils.FormatMoney(auctionPrice), JustJunk.Utils.FormatMoney(itemData.vendorPrice))
	end
	
	return true, string.format("low auction value (%s data)", source)
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

local function ShouldSellGear(itemData)
	if not JustJunk.ConfigModule.Get("merchant", "enableGear") then
		return false, "gear selling disabled"
	end
	
	local maxQuality = JustJunk.ConfigModule.Get("merchant", "maxGearQuality") or 4
	if itemData.quality > maxQuality then
		return false, string.format("quality too high (%s > %s)", 
			JustJunk.Utils.GetQualityName(itemData.quality), JustJunk.Utils.GetQualityName(maxQuality))
	end
	
	local shouldSell, reason = CheckItemLevel(itemData)
	if not shouldSell then return false, reason end
	
	shouldSell, reason = CheckEquipmentSet(itemData)
	if not shouldSell then return false, reason end
	
	local config = {
		minThreshold = JustJunk.ConfigModule.Get("merchant", "minWorthwhileAH_Gear") or 5000000,
		multiplier = JustJunk.ConfigModule.Get("merchant", "gearMultiplier") or 8
	}
	shouldSell, reason = CheckAuctionValue(itemData, config)
	if not shouldSell then return false, reason end
	
	return true, "passed all gear checks"
end

local function ShouldSellConsumable(itemData)
	if not JustJunk.ConfigModule.Get("merchant", "enableConsumables") then
		return false, "consumable selling disabled"
	end
	
	local maxQuality = JustJunk.ConfigModule.Get("merchant", "maxConsumableQuality") or 1
	if itemData.quality > maxQuality then
		return false, string.format("quality too high (%s > %s)", 
			JustJunk.Utils.GetQualityName(itemData.quality), JustJunk.Utils.GetQualityName(maxQuality))
	end
	
	local config = {
		minThreshold = JustJunk.ConfigModule.Get("merchant", "minWorthwhileAH_Consumables") or 200000,
		multiplier = JustJunk.ConfigModule.Get("merchant", "consumableMultiplier") or 3
	}
	local shouldSell, reason = CheckAuctionValue(itemData, config)
	if not shouldSell then return false, reason end
	
	return true, "passed all consumable checks"
end

local function ShouldSellTradeGood(itemData)
	if not JustJunk.ConfigModule.Get("merchant", "enableTradeGoods") then
		return false, "trade good selling disabled"
	end
	
	local maxQuality = JustJunk.ConfigModule.Get("merchant", "maxTradeGoodQuality") or 2
	if itemData.quality > maxQuality then
		return false, string.format("quality too high (%s > %s)", 
			JustJunk.Utils.GetQualityName(itemData.quality), JustJunk.Utils.GetQualityName(maxQuality))
	end
	
	local config = {
		minThreshold = JustJunk.ConfigModule.Get("merchant", "minWorthwhileAH_TradeGoods") or 500000,
		multiplier = JustJunk.ConfigModule.Get("merchant", "tradeGoodMultiplier") or 4
	}
	local shouldSell, reason = CheckAuctionValue(itemData, config)
	if not shouldSell then return false, reason end
	
	return true, "passed all trade good checks"
end

local function ShouldSellRecipe(itemData)
	if not JustJunk.ConfigModule.Get("merchant", "enableRecipes") then
		return false, "recipe selling disabled"
	end
	
	local maxQuality = JustJunk.ConfigModule.Get("merchant", "maxRecipeQuality") or 2
	if itemData.quality > maxQuality then
		return false, string.format("quality too high (%s > %s)", 
			JustJunk.Utils.GetQualityName(itemData.quality), JustJunk.Utils.GetQualityName(maxQuality))
	end
	
	local shouldSell, reason = CheckRecipeKnown(itemData)
	if not shouldSell then return false, reason end
	
	local config = {
		minThreshold = JustJunk.ConfigModule.Get("merchant", "minWorthwhileAH_Recipes") or 5000000,
		multiplier = JustJunk.ConfigModule.Get("merchant", "recipeMultiplier") or 10
	}
	shouldSell, reason = CheckAuctionValue(itemData, config)
	if not shouldSell then return false, reason end
	
	return true, "passed all recipe checks"
end

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

	-- Check for toys
	if C_ToyBox.GetToyInfo(itemData.itemID) then
		return false, "toy collectible"
	end

	-- Check for battle pets
	if itemData.classID == JustJunk.ITEM_CLASS.BATTLEPET then
		return false, "battle pet item"
	end
	
	-- Check for currency items
	local success, currencyInfo = pcall(C_CurrencyInfo.GetCurrencyInfoFromLink, itemData.itemLink)
	if success and currencyInfo and currencyInfo.currencyID then
		return false, "currency item"
	end
	
	-- Check for special miscellaneous items
	if itemData.classID == Enum.ItemClass.Miscellaneous then
		if itemData.subClassID == Enum.ItemMiscellaneousSubclass.Mount then
			return false, "mount item should not be sold"
		end
		if itemData.subClassID == Enum.ItemMiscellaneousSubclass.CompanionPet then
			return false, "pet item should not be sold"
		end
	end
	
	-- Check for BoP trade goods
	if itemData.classID == Enum.ItemClass.Tradegoods and itemData.bindType == 1 then
		return false, "BoP trade good should not be sold"
	end
	
	-- Direct item type evaluation
	if itemData.classID == JustJunk.ITEM_CLASS.ARMOR or itemData.classID == JustJunk.ITEM_CLASS.WEAPON then
		return ShouldSellGear(itemData)
	elseif itemData.classID == JustJunk.ITEM_CLASS.CONSUMABLE or 
		   itemData.classID == JustJunk.ITEM_CLASS.CONTAINER or 
		   itemData.classID == JustJunk.ITEM_CLASS.GEM then
		return ShouldSellConsumable(itemData)
	elseif itemData.classID == JustJunk.ITEM_CLASS.TRADEGOOD then
		return ShouldSellTradeGood(itemData)
	elseif itemData.classID == JustJunk.ITEM_CLASS.RECIPE then
		return ShouldSellRecipe(itemData)
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

function JustJunk.ItemEngine.SellNextItem()
	for bag, slot in JustJunk.Utils.IterateBagSlots() do
		if not JustJunk.Utils.IsBagProtected(bag) then
			local sessionKey = bag .. ":" .. slot
			if not soldThisSession[sessionKey] then
				local itemData = CreateItemData(bag, slot)
				if itemData then
					local shouldSell, reason = JustJunk.ItemEngine.EvaluateItemForSelling(itemData)
					if shouldSell then
						local preInfo = C_Container.GetContainerItemInfo(bag, slot)
						local preItemID = preInfo and preInfo.itemID

						local used = pcall(C_Container.UseContainerItem, bag, slot)
						if CursorHasItem and CursorHasItem() then ClearCursor() end

						if used then
							local postInfo = C_Container.GetContainerItemInfo(bag, slot)
							local postItemID = postInfo and postInfo.itemID

							if postItemID ~= preItemID then
								soldThisSession[sessionKey] = true
								JustJunk.Utils.Debug("Item", string.format("SOLD %s: %s", itemData.itemLink, reason))
								return true
							end
						end

						JustJunk.Utils.Debug("Item", string.format("RETRY %s: sell not confirmed", itemData.itemLink))
						return true
					else
						soldThisSession[sessionKey] = true
						if reason:find("AH") or reason:find("upgrade") or reason:find("set") or reason:find("known") then
							JustJunk.Utils.Debug("Item", string.format("KEEP %s: %s", itemData.itemLink, reason))
						end
					end
				end
			end
		end
	end
	return false
end

function JustJunk.ItemEngine.ResetSellSession()
	soldThisSession = {}
	averageItemLevel = nil
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