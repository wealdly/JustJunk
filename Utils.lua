----------------------------------------------------------------------
-- Utils.lua - Shared Utilities and Constants  
-- Author: wealdly | Version: 1.0.0
----------------------------------------------------------------------

local addonName, JustJunk = ...
JustJunk.Utils = {}

-- Essential constants
local COPPER_PER_GOLD = 10000
local COPPER_PER_SILVER = 100

----------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------

-- Item classes
JustJunk.ITEM_CLASS = {
	CONSUMABLE = Enum.ItemClass.Consumable or 0,
	CONTAINER = Enum.ItemClass.Container or 1,
	WEAPON = Enum.ItemClass.Weapon or 2,
	GEM = Enum.ItemClass.Gem or 3,
	ARMOR = Enum.ItemClass.Armor or 4,
	TRADEGOOD = Enum.ItemClass.Tradegoods or 7,
	RECIPE = Enum.ItemClass.Recipe or 9,
	BATTLEPET = Enum.ItemClass.Battlepet or 17
}

-- Bind types
JustJunk.BIND_TYPE = {
	NONE = 0,
	PICKUP = 1,
	EQUIP = 2,
	USE = 3,
	QUEST = 4,
	ACCOUNT = 5,
	WARBAND = 6
}

-- Inventory slots
JustJunk.INVENTORY_SLOTS = {
	HEAD = 1, NECK = 2, SHOULDER = 3, BODY = 4, CHEST = 5, WAIST = 6,
	LEGS = 7, FEET = 8, WRIST = 9, HAND = 10, FINGER1 = 11, FINGER2 = 12,
	TRINKET1 = 13, TRINKET2 = 14, BACK = 15, MAINHAND = 16, OFFHAND = 17, RANGED = 18
}

-- Quality names
JustJunk.QUALITY_NAMES = {"Poor", "Common", "Uncommon", "Rare", "Epic", "Legendary", "Artifact"}

-- Bag constants
JustJunk.BAG_CONSTANTS = {
	BACKPACK = 0,
	MAX_BAGS = 5,
	EXCLUDE_JUNK_SELL_FLAG = 64
}

----------------------------------------------------------------------
-- Debug and Messaging System
----------------------------------------------------------------------

function JustJunk.Utils.Debug(module, msg)
	if JustJunk.ConfigModule and JustJunk.ConfigModule.IsDebugMode() then
		print("|cff00ccffJJ " .. (module or "Core") .. ":|r " .. tostring(msg))
	end
end

function JustJunk.Utils.SafeCall(func, ...)
	if not func then return nil end
	local success, result = pcall(func, ...)
	if not success then
		JustJunk.Utils.Debug("Error", "SafeCall failed: " .. tostring(result))
		return nil
	end
	return result
end

----------------------------------------------------------------------
-- Gold and Currency
----------------------------------------------------------------------

function JustJunk.Utils.CopperToGold(copper)
	return math.floor((copper or 0) / COPPER_PER_GOLD)
end

function JustJunk.Utils.GoldToCopper(gold)
	return (gold or 0) * COPPER_PER_GOLD
end

function JustJunk.Utils.FormatMoney(copper)
	if not copper or copper == 0 then return "0c" end
	local gold = math.floor(copper / COPPER_PER_GOLD)
	local silver = math.floor((copper % COPPER_PER_GOLD) / COPPER_PER_SILVER)
	local copperRem = copper % COPPER_PER_SILVER
	
	if gold > 0 then
		return string.format("%dg %ds %dc", gold, silver, copperRem)
	elseif silver > 0 then
		return string.format("%ds %dc", silver, copperRem)
	else
		return string.format("%dc", copperRem)
	end
end

----------------------------------------------------------------------
-- Item Utilities
----------------------------------------------------------------------

function JustJunk.Utils.GetItemIDFromLink(itemLink)
	return itemLink and tonumber(itemLink:match("item:(%d+)"))
end

function JustJunk.Utils.GetQualityName(qualityIndex)
	return JustJunk.QUALITY_NAMES[(qualityIndex or 0) + 1] or "Unknown"
end

function JustJunk.Utils.CreateItemLocation(bag, slot)
	local location = ItemLocation:CreateFromBagAndSlot(bag, slot)
	return location and location:IsValid() and location or nil
end

function JustJunk.Utils.GetEquipSlotForItem(itemLink)
	if not itemLink then return nil end
	local _, _, _, _, _, _, _, _, equipSlot = GetItemInfo(itemLink)
	return equipSlot
end

----------------------------------------------------------------------
-- Bag Utilities
----------------------------------------------------------------------

function JustJunk.Utils.GetAllBagIDs()
	local ids = {}
	for bagID = JustJunk.BAG_CONSTANTS.BACKPACK, JustJunk.BAG_CONSTANTS.MAX_BAGS do
		local slots = C_Container.GetContainerNumSlots(bagID)
		if slots and slots > 0 then
			table.insert(ids, bagID)
		end
	end
	return #ids > 0 and ids or {JustJunk.BAG_CONSTANTS.BACKPACK}
end

function JustJunk.Utils.IsBagProtected(bagID)
	if C_Container and C_Container.GetBagSlotFlag then
		local success, isProtected = pcall(C_Container.GetBagSlotFlag, bagID, JustJunk.BAG_CONSTANTS.EXCLUDE_JUNK_SELL_FLAG)
		return success and isProtected
	end
	return false
end

function JustJunk.Utils.IterateBagSlots()
	local bagIDs = JustJunk.Utils.GetAllBagIDs()
	local bagIndex, slotIndex = 1, 0
	
	return function()
		while bagIndex <= #bagIDs do
			local bagID = bagIDs[bagIndex]
			local maxSlots = C_Container.GetContainerNumSlots(bagID)
			
			slotIndex = slotIndex + 1
			if slotIndex <= maxSlots then
				return bagID, slotIndex
			else
				bagIndex = bagIndex + 1
				slotIndex = 0
			end
		end
		return nil
	end
end

----------------------------------------------------------------------
-- Game State Functions
----------------------------------------------------------------------

function JustJunk.Utils.ShouldAutomate()
	return not (IsShiftKeyDown() or IsControlKeyDown() or IsAltKeyDown())
end

function JustJunk.Utils.IsSafeForAutomation()
	return not UnitIsDeadOrGhost("player") and not InCombatLockdown()
end

----------------------------------------------------------------------
-- Simple Scheduler
----------------------------------------------------------------------

function JustJunk.Utils.ScheduleOnce(key, delay, fn, ...)
	if not fn then return end
	local args = {...}
	C_Timer.NewTimer(delay or 0, function()
		local ok, err = pcall(fn, unpack(args))
		if not ok then
			JustJunk.Utils.Debug("Timer", "Error: " .. tostring(err))
		end
	end)
end