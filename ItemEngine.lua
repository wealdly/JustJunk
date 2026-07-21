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
local C_TransmogCollection = C_TransmogCollection
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
local lockedRescans = 0
local MAX_LOCKED_RESCANS = 20

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

local function NewSessionReport()
	return { soldCount = 0, totalValue = 0, qualities = {}, sources = {} }
end

local function EnsureSessionReport()
	if not sessionReport then
		sessionReport = NewSessionReport()
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

-- Items assigned to an equipment set are never sold: the player put them there
-- deliberately. Keyed by itemID so it holds in the bank and warband bank too (the
-- container-based set API only reports the player's bags), which also means a
-- spare copy of a set item is protected - the safe direction. Cached, cleared on
-- EQUIPMENT_SETS_CHANGED (see Initialize).
local equipmentSetItemIDs = nil

local function IsEquipmentSetItem(itemID)
	if not itemID then return false end

	if not equipmentSetItemIDs then
		local ids = {}
		if C_EquipmentSet and C_EquipmentSet.GetEquipmentSetIDs then
			local ok, setIDs = pcall(C_EquipmentSet.GetEquipmentSetIDs)
			for _, setID in ipairs((ok and setIDs) or {}) do
				local okItems, setItems = pcall(C_EquipmentSet.GetItemIDs, setID)
				for _, id in pairs((okItems and setItems) or {}) do
					if type(id) == "number" and id > 0 then ids[id] = true end
				end
			end
		end
		equipmentSetItemIDs = ids
	end

	return equipmentSetItemIDs[itemID] == true
end

-- Session-or-config boolean with default-true (~= false) keep semantics: reads
-- the sell-session snapshot when one is active, else live merchant config.
local function SessionBool(key)
	if sessionSettings then
		return sessionSettings[key] ~= false
	end
	return JustJunk.ConfigModule.Get("merchant", key) ~= false
end

-- Whether Poor (grey) items are auto-sold (gates the native bulk pass, the
-- per-item loop, and bag markers) and whether to keep items whose transmog
-- appearance is not collected yet.
local function ShouldSellGreys() return SessionBool("sellGreyJunk") end
local function IsTransmogProtectionEnabled() return SessionBool("protectTransmog") end

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
	local name, _, quality, _, _, _, _, maxStack, equipSlot, _, vendorPrice, classID, subClassID, bindType = C_Item.GetItemInfo(containerInfo.hyperlink)
	
	if not name or not classID or not vendorPrice or vendorPrice <= 0 then return nil end
	
	local location = JustJunk.Utils.CreateItemLocation(bag, slot)
	if not location then return nil end
	
	-- Check if item is actually soulbound (regardless of original bind type)
	local isSoulbound = C_Item.IsBound(location)
	
	return {
		itemID = containerInfo.itemID,
		itemLink = containerInfo.hyperlink,
		quality = quality or 0,
		itemLevel = C_Item.GetCurrentItemLevel(location) or 0,
		vendorPrice = vendorPrice or 0,
		classID = classID,
		subClassID = subClassID or 0,
		equipSlot = equipSlot,  -- GetItemInfo's equipLoc; reused by the gear checks
		bindType = bindType or 0,
		isSoulbound = isSoulbound,  -- Actual soulbound status
		stackCount = containerInfo.stackCount or 1,
		maxStackSize = (maxStack and maxStack > 0) and maxStack or 1,
		bag = bag,
		slot = slot,
	}
end

----------------------------------------------------------------------
-- Item Evaluation Functions
----------------------------------------------------------------------

-- Armor subclasses that carry a class restriction. Verified against
-- Enum.ItemArmorSubclass (Cloth 1 / Leather 2 / Mail 3 / Plate 4). Fall back to
-- the documented numbers if a field is renamed so we never build a nil table key.
local ARMOR_SUBCLASS = {
	CLOTH   = (Enum.ItemArmorSubclass and Enum.ItemArmorSubclass.Cloth)   or 1,
	LEATHER = (Enum.ItemArmorSubclass and Enum.ItemArmorSubclass.Leather) or 2,
	MAIL    = (Enum.ItemArmorSubclass and Enum.ItemArmorSubclass.Mail)    or 3,
	PLATE   = (Enum.ItemArmorSubclass and Enum.ItemArmorSubclass.Plate)   or 4,
}

-- The single armor type each class wears. Spec never changes armor type in
-- retail, so this is purely class-based: anything else can never be an upgrade.
local CLASS_ARMOR_SUBCLASS = {
	MAGE = ARMOR_SUBCLASS.CLOTH, PRIEST = ARMOR_SUBCLASS.CLOTH, WARLOCK = ARMOR_SUBCLASS.CLOTH,
	ROGUE = ARMOR_SUBCLASS.LEATHER, DRUID = ARMOR_SUBCLASS.LEATHER, MONK = ARMOR_SUBCLASS.LEATHER, DEMONHUNTER = ARMOR_SUBCLASS.LEATHER,
	HUNTER = ARMOR_SUBCLASS.MAIL, SHAMAN = ARMOR_SUBCLASS.MAIL, EVOKER = ARMOR_SUBCLASS.MAIL,
	WARRIOR = ARMOR_SUBCLASS.PLATE, PALADIN = ARMOR_SUBCLASS.PLATE, DEATHKNIGHT = ARMOR_SUBCLASS.PLATE,
}

local ARMOR_TYPE_SUBCLASS_SET = {
	[ARMOR_SUBCLASS.CLOTH] = true, [ARMOR_SUBCLASS.LEATHER] = true,
	[ARMOR_SUBCLASS.MAIL] = true, [ARMOR_SUBCLASS.PLATE] = true,
}

-- Only body slots carry an armor-type requirement. Cloaks, rings, necks,
-- trinkets, shields, off-hands and weapons never do (cloaks and jewelry are the
-- Generic subclass anyway), so gating on slot keeps them from ever being flagged.
local ARMOR_TYPE_SLOTS = {
	INVTYPE_HEAD = true, INVTYPE_SHOULDER = true, INVTYPE_CHEST = true,
	INVTYPE_ROBE = true, INVTYPE_WAIST = true, INVTYPE_LEGS = true,
	INVTYPE_FEET = true, INVTYPE_WRIST = true, INVTYPE_HAND = true,
}

-- True when the item is body armor of a type this character's class does not
-- wear (e.g. cloth on a rogue). Strict and level-independent: a rogue uses
-- leather, period. Such a piece can never be an upgrade, so it is safe to sell.
-- Non-armor and no-type slots (cloaks, rings, necks, trinkets, shields, weapons)
-- are never flagged. Needs no Pawn data.
-- The player's class -> armor subclass can't change in a session, so resolve it
-- once instead of calling UnitClass for every gear item (false = computed, none).
local playerArmorSubclass = nil
local function GetPlayerArmorSubclass()
	if playerArmorSubclass == nil then
		local _, class = UnitClass("player")
		if class then
			playerArmorSubclass = CLASS_ARMOR_SUBCLASS[class] or false
		end
	end
	return playerArmorSubclass or nil
end

local function IsWrongArmorTypeForClass(itemData)
	if itemData.classID ~= JustJunk.ITEM_CLASS.ARMOR then return false end
	if not ARMOR_TYPE_SUBCLASS_SET[itemData.subClassID] then return false end
	if not ARMOR_TYPE_SLOTS[itemData.equipSlot] then return false end

	local classType = GetPlayerArmorSubclass()
	if not classType then return false end

	return itemData.subClassID ~= classType
end

-- Trade Goods subclasses tie to the profession that gathers or crafts them. Enum
-- fields resolve to the live values; the documented numbers are fallbacks so a
-- renamed field never builds a nil table key. (Herb 9, Metal & Stone 7, Leather 6,
-- Cloth 5, Cooking 8, Enchanting 12, Jewelcrafting 4, Inscription 16.)
local TG_SUB = Enum.ItemTradegoodsSubclass or {}
local TRADEGOOD_SUBCLASS = {
	HERB          = TG_SUB.Herb          or 9,
	METAL_STONE   = TG_SUB.MetalAndStone or 7,
	LEATHER       = TG_SUB.Leather       or 6,
	CLOTH         = TG_SUB.Cloth         or 5,
	COOKING       = TG_SUB.Meat or TG_SUB.Cooking or 8,
	ENCHANTING    = TG_SUB.Enchanting    or 12,
	JEWELCRAFTING = TG_SUB.Jewelcrafting or 4,
	INSCRIPTION   = TG_SUB.Inscription   or 16,
}

-- Trade good subclass -> base profession skill-line ID (stable since Classic;
-- GetProfessionInfo's 7th return reports the base line, not the expansion variant).
local TRADEGOOD_PROFESSION = {
	[TRADEGOOD_SUBCLASS.HERB]          = 182, -- Herbalism
	[TRADEGOOD_SUBCLASS.METAL_STONE]   = 186, -- Mining
	[TRADEGOOD_SUBCLASS.LEATHER]       = 393, -- Skinning
	[TRADEGOOD_SUBCLASS.CLOTH]         = 197, -- Tailoring
	[TRADEGOOD_SUBCLASS.COOKING]       = 185, -- Cooking
	[TRADEGOOD_SUBCLASS.ENCHANTING]    = 333, -- Enchanting
	[TRADEGOOD_SUBCLASS.JEWELCRAFTING] = 755, -- Jewelcrafting
	[TRADEGOOD_SUBCLASS.INSCRIPTION]   = 773, -- Inscription
}

-- Miscellaneous subclasses that protect a collectible from being sold. Fallbacks
-- keep the guard working (fail closed) if a field is renamed. (CompanionPet 2,
-- Mount 5.)
local MISC_SUBCLASS = {
	MOUNT         = (Enum.ItemMiscellaneousSubclass and Enum.ItemMiscellaneousSubclass.Mount)        or 5,
	COMPANION_PET = (Enum.ItemMiscellaneousSubclass and Enum.ItemMiscellaneousSubclass.CompanionPet) or 2,
}

-- Player professions as a set of base skill-line IDs. Cached lazily and cleared on
-- SKILL_LINES_CHANGED (see Initialize) so learning or dropping one re-decides
-- trade-good valuation.
local playerProfessions = nil

local function GetPlayerProfessions()
	if playerProfessions then return playerProfessions end

	local professions = {}
	-- GetProfessions() returns sparse slots (interior nils), so iterate with pairs.
	for _, index in pairs({ GetProfessions() }) do
		local skillLine = select(7, GetProfessionInfo(index))
		if skillLine then professions[skillLine] = true end
	end

	playerProfessions = professions
	return professions
end

-- Units to value a stackable slot at. A trade good you can gather or craft refills
-- to a full stack through normal play, so a partial stack still earns its slot -
-- value it as a full stack. Everything else (a material tied to no profession you
-- have, or a consumable, which is used up rather than hoarded) is valued by what is
-- actually in the slot, so small one-off stacks get sold.
local function GetValuationStackCount(itemData)
	if itemData.classID == JustJunk.ITEM_CLASS.TRADEGOOD then
		local skillID = TRADEGOOD_PROFESSION[itemData.subClassID]
		if skillID and GetPlayerProfessions()[skillID] then
			return itemData.maxStackSize or 1
		end
	end
	return itemData.stackCount or 1
end

-- Cache of appearance-need results keyed by itemLink. Transmog collection only
-- ever grows, so a stale entry can at worst over-keep (never wrongly sell); it is
-- cleared on collection changes (see Initialize) to release over-kept items.
local appearanceNeedCache = {}

-- True when the item carries a transmog appearance this account has not collected
-- and could still learn. Such items are kept: wearing or using one collects the
-- look, so auto-selling it would lose it. Modeled on how the bag/search addons
-- probe collection state. Every uncertain path errs toward keeping - a dressable
-- item whose source or collection status we can't resolve returns true.
local function ComputeNeedsAppearance(itemData)
	local TC = C_TransmogCollection
	local link = itemData.itemLink
	if not (TC and TC.GetItemInfo and link) then return false end

	local isDressable = C_Item.IsDressableItemByID or rawget(_G, "IsDressableItem")
	if not (isDressable and isDressable(link)) then
		return false -- not an equippable/transmoggable item: no appearance to lose
	end

	local ok, _, sourceID = pcall(TC.GetItemInfo, link)
	if not ok or not sourceID then
		return true -- dressable but source unresolved: keep to be safe
	end

	-- An appearance this account can never collect (class/armor restrictions) is
	-- not worth keeping for transmog.
	if TC.AccountCanCollectSource then
		local okCan, hasData, canCollect = pcall(TC.AccountCanCollectSource, sourceID)
		if okCan and hasData and canCollect == false then
			return false
		end
	end

	if TC.PlayerHasTransmogByItemInfo then
		local okHas, hasIt = pcall(TC.PlayerHasTransmogByItemInfo, link)
		if okHas then
			return hasIt == false -- kept only when the look is not yet collected
		end
	end

	return true -- collectible source but status unconfirmed: keep to be safe
end

-- Cached wrapper: the appearance check runs several C_TransmogCollection lookups,
-- and the marker path re-evaluates the same items on every bag refresh.
local function PlayerNeedsAppearance(itemData)
	local link = itemData.itemLink
	if not link then return false end
	local cached = appearanceNeedCache[link]
	if cached ~= nil then return cached end
	local result = ComputeNeedsAppearance(itemData)
	appearanceNeedCache[link] = result
	return result
end

-- True only when Pawn is present with an active scale and reports the item is not
-- a stat upgrade for anything equipped. Every uncertain case (Pawn missing/off/not
-- ready, no scale, item not loaded, trinket/artifact, or an error) returns false so
-- the caller keeps the item. Fail closed: never relax the item-level margin on a
-- guess. This is the Pawn-dependent half only; wrong armor type is handled
-- separately by IsWrongArmorTypeForClass, which needs no Pawn data.
--
-- Verified against Pawn's source:
--   * PawnGetVisibleScaleCount gates the check - with no visible scale Pawn reports
--     "not an upgrade" for all items, which would sell all near-ilvl gear.
--   * We use PawnIsItemAnUpgrade's FIRST return (the stat-based upgrade table), not
--     PawnShouldItemLinkHaveUpgradeArrow. The arrow also flags raw item-level jumps
--     (ShowItemLevelUpgrades, on by default), so a higher-ilvl off-spec piece reads
--     as an "upgrade" and is wrongly kept. The stat table is nil for off-spec /
--     lower-score gear - exactly what we sell.
--   * Trinkets and artifacts (Rarity 6) carry procs/on-use effects Pawn can't
--     value, so a low stat score does not mean junk. They are never judged here.
local function PawnSaysNotAnUpgrade(itemData)
	if not itemData.itemLink then return false end

	local usePawn = sessionSettings and sessionSettings.usePawnUpgradeCheck
	if usePawn == nil then
		usePawn = JustJunk.ConfigModule.Get("merchant", "usePawnUpgradeCheck")
	end
	if usePawn == false then return false end

	if not rawget(_G, "PawnIsInitialized") then return false end
	local getItemData = rawget(_G, "PawnGetItemData")
	local isUpgrade = rawget(_G, "PawnIsItemAnUpgrade")
	local scaleCount = rawget(_G, "PawnGetVisibleScaleCount")
	if type(getItemData) ~= "function" or type(isUpgrade) ~= "function" or type(scaleCount) ~= "function" then
		return false
	end

	local okCount, count = pcall(scaleCount)
	if not okCount or type(count) ~= "number" or count < 1 then
		return false
	end

	-- A nil table or one without a resolved link means Pawn hasn't finished
	-- loading the item; treat as unknown and keep.
	local okData, item = pcall(getItemData, itemData.itemLink)
	if not okData or type(item) ~= "table" or item.Link == nil then
		return false
	end

	if item.InvType == "INVTYPE_TRINKET" or item.Rarity == 6 then
		return false
	end

	local okUp, upgradeTable = pcall(isUpgrade, item)
	return okUp and (upgradeTable == nil)
end

local function CheckItemLevel(itemData)
	-- Armor of a type this class never wears can never be an upgrade, so item level
	-- is irrelevant - sell it regardless. This is a strict class rule that needs no
	-- Pawn (works even with Pawn absent or without an active scale). The flag lets
	-- the later auction-value check sell it even with no market price. (Soulbound
	-- pieces sell there anyway; valuable BoE ones above your threshold are kept.)
	if IsWrongArmorTypeForClass(itemData) then
		return true, "wrong armor type for class"
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

	-- Within the item-level safety margin. Normally kept, but if Pawn is set up
	-- and says this piece isn't a stat upgrade for anything equipped, it's near-ilvl
	-- junk and safe to sell. The auction-value check still runs after this.
	if PawnSaysNotAnUpgrade(itemData) then
		return true, "within safety margin, not a Pawn upgrade"
	end

	return false, string.format("within safety margin (ilvl %d > %d)", itemData.itemLevel, threshold)
end

local function CheckAuctionValue(itemData, keepAbove, valuePerSlot)
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
		end
		-- Stackable commodities with no findable price aren't worth a bag slot.
		if valuePerSlot then
			return true, "no AH value, safe to sell", source or "no_data"
		end
		-- Non-grey gear with no market data is kept: it may carry transmog or
		-- auction value we can't see, so "keep when uncertain" applies. Off-type
		-- gear is still cleared when soulbound (returned above as bound) or when a
		-- known price is below the threshold; a tradeable piece of unknown worth is
		-- not vendored on a guess.
		return false, "non-grey item, unknown market value", source or "no_data"
	end

	-- Stackable commodities are judged by the value of the slot they occupy (see
	-- GetValuationStackCount); gear (stack of 1) is unaffected.
	local slotValue = auctionPrice
	if valuePerSlot then
		slotValue = auctionPrice * GetValuationStackCount(itemData)
	end

	if slotValue > (keepAbove or 0) then
		return false, string.format("worth more on AH (%s: %s%s)",
			source, JustJunk.Utils.FormatMoney(slotValue),
			valuePerSlot and "/stack" or ""), source
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

-- Per-category {enabled, maxQuality, keepAbove}; the single home for the default
-- quality (4) and threshold (0) values.
local function BuildCategorySettings(rule)
	return {
		enabled = GetMerchantSetting(rule.enableKey, true),
		maxQuality = GetMerchantSetting(rule.qualityKey, 4),
		keepAbove = GetMerchantSetting(rule.thresholdKey, 0),
	}
end

local CATEGORY_RULES

local function BuildSessionSettings()
	local settings = {
		preferredPricingSource = GetMerchantSetting("preferredPricingSource", "auto"),
		sellGreyJunk = GetMerchantSetting("sellGreyJunk", true),
		usePawnUpgradeCheck = GetMerchantSetting("usePawnUpgradeCheck", true),
		protectTransmog = GetMerchantSetting("protectTransmog", true),
		forceKeepItems = GetMerchantSetting("forceKeepItems", {}),
		forceSellItems = GetMerchantSetting("forceSellItems", {}),
		categories = {}
	}

	for categoryName, rule in pairs(CATEGORY_RULES) do
		settings.categories[categoryName] = BuildCategorySettings(rule)
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
		preChecks = {CheckItemLevel},
		passReason = "passed all gear checks",
	},
	consumable = {
		categoryName = "consumable",
		enableKey = "enableConsumables",
		disabledReason = "consumable selling disabled",
		qualityKey = "maxConsumableQuality",
		thresholdKey = "consumableKeepAbove",
		valuePerSlot = true,
		passReason = "passed all consumable checks",
	},
	tradeGood = {
		categoryName = "tradeGood",
		enableKey = "enableTradeGoods",
		disabledReason = "trade good selling disabled",
		qualityKey = "maxTradeGoodQuality",
		thresholdKey = "tradeGoodKeepAbove",
		valuePerSlot = true,
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
		categorySettings = BuildCategorySettings(rule)
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

	local shouldSell, reason, source = CheckAuctionValue(itemData, categorySettings.keepAbove, rule.valuePerSlot)
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
	if itemData.classID == JustJunk.ITEM_CLASS.QUESTITEM then
		return false, "quest item cannot be sold"
	end

	local overrideMode = GetOverrideMode(itemData.itemID)
	if overrideMode == "keep" then
		return false, "manually kept"
	elseif overrideMode == "sell" then
		return true, "manual sell override", "manual"
	end

	-- Checked before the grey rule: an item in an equipment set is deliberate, so
	-- it is kept whatever its quality (only an explicit manual vendor overrides it).
	if IsEquipmentSetItem(itemData.itemID) then
		return false, "equipment set item"
	end

	-- Grey (Poor) items are vendor trash by WoW's own definition: the native bulk
	-- junk sale and the bag markers both treat every grey as sellable, so decide
	-- them here, before the higher-quality protections below, to keep all three
	-- sell paths in agreement. Only a manual keep (checked above) or the disable
	-- toggle spares a grey. (No-vendor-value and quest greys already returned above.)
	if itemData.quality == 0 then
		if not ShouldSellGreys() then
			return false, "grey selling disabled"
		end
		return true, "grey junk", "grey"
	end

	-- Strongly protect BoA/BoW items - other characters may need them.
	if itemData.bindType == JustJunk.BIND_TYPE.ACCOUNT or itemData.bindType == JustJunk.BIND_TYPE.WARBAND then
		return false, "BoA/BoW item protected - other characters may need it"
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
	if itemData.classID == JustJunk.ITEM_CLASS.MISCELLANEOUS then
		if C_ToyBox and C_ToyBox.GetToyInfo and C_ToyBox.GetToyInfo(itemData.itemID) then
			return false, "toy collectible"
		end

		if C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfoFromLink then
			local success, currencyInfo = pcall(C_CurrencyInfo.GetCurrencyInfoFromLink, itemData.itemLink)
			if success and currencyInfo and currencyInfo.currencyID then
				return false, "currency item"
			end
		end

		if itemData.subClassID == MISC_SUBCLASS.MOUNT then
			return false, "mount item should not be sold"
		end
		if itemData.subClassID == MISC_SUBCLASS.COMPANION_PET then
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

	-- Keep items whose transmog appearance this account has not collected yet:
	-- wearing or using the item learns the look, so selling it outright loses it.
	if IsTransmogProtectionEnabled() and PlayerNeedsAppearance(itemData) then
		return false, "uncollected transmog appearance"
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

	local equipSlot = itemData.equipSlot or JustJunk.Utils.GetEquipSlotForItem(itemData.itemLink)
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

	-- Before the grey fast path, so a set item is never flagged as junk.
	if IsEquipmentSetItem(slotInfo.itemID) then
		return false, "equipment set item", nil, nil
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

local function AdvanceSessionSlot(sessionKey)
	soldThisSession[sessionKey] = true
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

		AdvanceSessionSlot(sessionKey)
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
			AdvanceSessionSlot(sessionKey)
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
		AdvanceSessionSlot(sessionKey)
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

	-- Locked slots (e.g. a sale still resolving) get a bounded number of full
	-- rescans so they can retry once unlocked, without busy-looping forever on a
	-- slot that never frees up.
	if hasLockedItems and lockedRescans < MAX_LOCKED_RESCANS then
		lockedRescans = lockedRescans + 1
		sessionScanIndex = 1
		return true
	end

	return false
end

function JustJunk.ItemEngine.ResetSellSession()
	soldThisSession = {}
	sellRetryCounts = {}
	lockedRescans = 0
	averageItemLevel = nil
	sessionSettings = BuildSessionSettings()
	sessionSlots = BuildSessionSlotList()
	sessionScanIndex = 1
	sessionProtectedBags = BuildSessionProtectedBags()
	sessionReport = NewSessionReport()
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
				-- A force-keep or equipment-set grey must bail the whole native sale,
				-- even when locked, or SellAllJunkItems would vendor it regardless.
				if GetOverrideMode(info.itemID) == "keep" or IsEquipmentSetItem(info.itemID) then
					return false
				end

				-- Defer locked greys (a sale still resolving) to the per-item loop,
				-- which retries locks; the native bulk sale can't confirm them here.
				if not info.isLocked then
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
	-- Invalidate cached lookups on the events that change their answers: a skill
	-- change re-decides trade-good valuation; collecting (or losing) a transmog
	-- appearance re-decides the uncollected-appearance protection.
	local invalidationFrame = CreateFrame("Frame")
	invalidationFrame:RegisterEvent("SKILL_LINES_CHANGED")
	invalidationFrame:RegisterEvent("EQUIPMENT_SETS_CHANGED")
	invalidationFrame:RegisterEvent("TRANSMOG_COLLECTION_SOURCE_ADDED")
	invalidationFrame:RegisterEvent("TRANSMOG_COLLECTION_SOURCE_REMOVED")
	invalidationFrame:RegisterEvent("TRANSMOG_COLLECTION_UPDATED")
	invalidationFrame:SetScript("OnEvent", function(_, event)
		if event == "SKILL_LINES_CHANGED" then
			playerProfessions = nil
		elseif event == "EQUIPMENT_SETS_CHANGED" then
			equipmentSetItemIDs = nil
		else
			appearanceNeedCache = {}
		end
	end)

	JustJunk.Utils.Debug("Item", "Item engine initialized")
end