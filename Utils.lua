----------------------------------------------------------------------
-- Utils.lua - Shared Utilities and Constants  
-- Author: wealdly | Version: 1.0.0
----------------------------------------------------------------------

local addonName, JustJunk = ...
JustJunk.Utils = {}

local activeTimers = {}
local C_Container = C_Container
local ItemLocation = ItemLocation
local NewTimer = C_Timer and C_Timer.NewTimer

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
	REAGENT = Enum.ItemClass.Reagent or 5,
	TRADEGOOD = Enum.ItemClass.Tradegoods or 7,
	ITEM_ENHANCEMENT = Enum.ItemClass.ItemEnhancement or 8,
	RECIPE = Enum.ItemClass.Recipe or 9,
	BATTLEPET = Enum.ItemClass.Battlepet or 17,
	HOUSING = Enum.ItemClass.Housing or 20
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
	MAX_BAGS = (rawget(_G, "NUM_TOTAL_EQUIPPED_BAG_SLOTS") or 5),
	EXCLUDE_JUNK_SELL_FLAG = (Enum and Enum.BagSlotFlags and Enum.BagSlotFlags.ExcludeJunkSell) or 64
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
	local _, _, _, _, _, _, _, _, equipSlot = C_Item.GetItemInfo(itemLink)
	return equipSlot
end

function JustJunk.Utils.TableMerge(target, defaults)
	if type(target) ~= "table" or type(defaults) ~= "table" then
		return target
	end

	for key, value in pairs(defaults) do
		if type(value) == "table" then
			if type(target[key]) ~= "table" then
				target[key] = {}
			end
			JustJunk.Utils.TableMerge(target[key], value)
		elseif target[key] == nil then
			target[key] = value
		end
	end

	return target
end

----------------------------------------------------------------------
-- Bag Utilities
----------------------------------------------------------------------

function JustJunk.Utils.GetAllBagIDs()
	local ids = {}
	for bagID = JustJunk.BAG_CONSTANTS.BACKPACK, JustJunk.BAG_CONSTANTS.MAX_BAGS do
		local slots = C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerNumSlots(bagID)
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
	local bagData = {}
	for i = 1, #bagIDs do
		local bagID = bagIDs[i]
		bagData[i] = {
			id = bagID,
			slots = C_Container.GetContainerNumSlots(bagID) or 0,
		}
	end

	local bagIndex, slotIndex = 1, 0
	
	return function()
		while bagIndex <= #bagData do
			local currentBag = bagData[bagIndex]
			local bagID = currentBag.id
			local maxSlots = currentBag.slots
			
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
	if not NewTimer then return end

	if key and activeTimers[key] then
		activeTimers[key]:Cancel()
		activeTimers[key] = nil
	end

	local args = {...}
	local timer
	timer = NewTimer(delay or 0, function()
		if key and activeTimers[key] == timer then
			activeTimers[key] = nil
		end

		local ok, err = pcall(fn, unpack(args))
		if not ok then
			JustJunk.Utils.Debug("Timer", "Error: " .. tostring(err))
		end
	end)

	if key then
		activeTimers[key] = timer
	end
end