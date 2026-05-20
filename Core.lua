----------------------------------------------------------------------
-- Core.lua - Event Dispatcher and Merchant Automation
-- Author: wealdly | Version: 1.0.0
----------------------------------------------------------------------

local addonName, JustJunk = ...
_G.JustJunk = JustJunk

-- Local config cache with safe defaults
local CONFIG = {
	merchantDelay = 0.3,
}

-- Update config when modules are ready
local function UpdateConfig()
	if JustJunk.ConfigModule then
		CONFIG.merchantDelay = JustJunk.ConfigModule.Get("merchant", "merchantDelay") or 0.3
	end
end

----------------------------------------------------------------------
-- Event Handler Configuration
----------------------------------------------------------------------

local EVENT_HANDLERS = {
	-- Merchant events
	["MERCHANT_SHOW"] = {"Core", "OnMerchantShow"},
	["MERCHANT_CLOSED"] = {"Core", "OnMerchantClosed"},
	
	-- Equipment events
	["PLAYER_EQUIPMENT_CHANGED"] = {"ItemEngine", "OnEquipmentChanged"}
}

----------------------------------------------------------------------
-- State Management
----------------------------------------------------------------------

local moduleList = {"MarketEngine", "ItemEngine"}
local eventFrame = CreateFrame("FRAME")
local eventsRegistered = false
local sellingActive = false
local configReady = false
local merchantQueue = {}

-- Forward declarations for merchant handlers used before definition
local OnMerchantShow
local OnMerchantClosed

----------------------------------------------------------------------
-- Core Utilities
----------------------------------------------------------------------

local function GetConfig(key)
	return JustJunk.ConfigModule and JustJunk.ConfigModule.Get(nil, key)
end

local function DispatchToModule(moduleName, methodName, ...)
	local module = JustJunk[moduleName]
	if module and module[methodName] then
		return JustJunk.Utils.SafeCall(module[methodName], ...)
	end
	return nil
end

----------------------------------------------------------------------
-- Merchant Integration
----------------------------------------------------------------------

local function HandleAutoRepair()
	if not JustJunk.ConfigData.CONSTANTS.AUTO_REPAIR then return end
	if not (CanMerchantRepair and GetRepairAllCost and RepairAllItems) then return end
	if not CanMerchantRepair() then return end

	-- Check durability
	local cur, max = 0, 0
	for slot = 1, 18 do
		local c, m = GetInventoryItemDurability(slot)
		if c and m and m > 0 then cur = cur + c; max = max + m end
	end
	
	local cost = GetRepairAllCost()
	if not cost or cost <= 0 then return end

	local useGuild = false
	if JustJunk.ConfigData.CONSTANTS.REPAIR_GUILD then
		useGuild = (CanGuildBankRepair and CanGuildBankRepair() and 
				   GetGuildBankWithdrawMoney and cost <= (GetGuildBankWithdrawMoney() or 0)) or false
	end

	if not pcall(RepairAllItems, useGuild) and useGuild then
		pcall(RepairAllItems, false)
		useGuild = false
	end

	JustJunk.Utils.Debug("Core", "Repaired for " .. JustJunk.Utils.FormatMoney(cost) .. (useGuild and " (guild)" or ""))
end

local function SellItems()
	if not sellingActive or not MerchantFrame or not MerchantFrame:IsShown() then
		sellingActive = false
		return
	end
	
	if JustJunk.ItemEngine and JustJunk.ItemEngine.SellNextItem() then
		if MerchantFrame and MerchantFrame:IsShown() then
			JustJunk.Utils.ScheduleOnce('sell_items', 0.1, SellItems)
		else
			sellingActive = false
		end
	else
		sellingActive = false
		JustJunk.Utils.Debug("Core", "Item selling completed")
	end
end

local function ProcessMerchantQueue()
	if #merchantQueue > 0 and configReady then
		JustJunk.Utils.Debug("Core", "Processing queued merchant interactions")
		for _, queuedAction in ipairs(merchantQueue) do
			if queuedAction.type == "merchant_show" and MerchantFrame and MerchantFrame:IsShown() then
				OnMerchantShow()
				break
			end
		end
		merchantQueue = {}
	end
end

OnMerchantShow = function()
	-- Ensure essential modules are loaded before proceeding
	if not configReady then
		JustJunk.Utils.Debug("Core", "Config modules not ready, queuing merchant processing")
		table.insert(merchantQueue, {type = "merchant_show", time = GetTime()})
		return
	end
	
	if not GetConfig("enabled") or not JustJunk.ConfigModule.Get("merchant", "enabled") then 
		return 
	end
	
	if sellingActive then
		JustJunk.Utils.Debug("Core", "Merchant show: Already selling")
		return
	end
	
	-- Reset selling session
	if JustJunk.ItemEngine then
		JustJunk.ItemEngine.ResetSellSession()
	end
	
	JustJunk.Utils.Debug("Core", "Merchant opened - starting selling process")
	
	-- Update config and add delay
	UpdateConfig()
	JustJunk.Utils.Debug("Core", "Using merchant delay: " .. tostring(CONFIG.merchantDelay) .. "s")
	JustJunk.Utils.ScheduleOnce('merchant_start', CONFIG.merchantDelay, function()
		if not GetConfig("enabled") or not JustJunk.ConfigModule.Get("merchant", "enabled") then 
			return 
		end
		
		if not MerchantFrame or not MerchantFrame:IsShown() then
			JustJunk.Utils.Debug("Core", "Merchant closed during delay")
			return
		end
		
		HandleAutoRepair()
		
		-- Check if vendor buys items
		if not (C_MerchantFrame and C_MerchantFrame.IsSellAllJunkEnabled and C_MerchantFrame.IsSellAllJunkEnabled()) then
			JustJunk.Utils.Debug("Core", "Vendor doesn't buy items (repair-only)")
			return
		end
		
		-- Sell grey items first
		C_MerchantFrame.SellAllJunkItems()
		JustJunk.Utils.Debug("Core", "Sold all grey items")
		
		-- Start intelligent selling
		sellingActive = true
		JustJunk.Utils.ScheduleOnce('sell_items', 0.1, SellItems)
	end)
end

OnMerchantClosed = function()
	sellingActive = false
	if JustJunk.ItemEngine then
		JustJunk.ItemEngine.ResetSellSession()
	end
	if JustJunk.MarketEngine then
		JustJunk.MarketEngine.ClearCache()
	end
	if CursorHasItem and CursorHasItem() then ClearCursor() end
end

----------------------------------------------------------------------
-- Event System
----------------------------------------------------------------------

local function RegisterEvents()
	if not eventsRegistered then
		for event in pairs(EVENT_HANDLERS) do
			eventFrame:RegisterEvent(event)
		end
		eventsRegistered = true
		JustJunk.Utils.Debug("Core", "Events registered")
	end
end

local function UnregisterEvents()
	if eventsRegistered then
		eventFrame:UnregisterAllEvents()
		eventsRegistered = false
		
		for _, moduleName in ipairs(moduleList) do
			DispatchToModule(moduleName, "OnDisable")
		end
		
		JustJunk.Utils.Debug("Core", "Events unregistered")
	end
end

----------------------------------------------------------------------
-- Main Event Handler
----------------------------------------------------------------------

-- Immediate dispatch events (bypass safety checks)
local IMMEDIATE_DISPATCH_EVENTS = {
	["PLAYER_EQUIPMENT_CHANGED"] = {"ItemEngine", "OnEquipmentChanged"},
}

-- Merchant events
local MERCHANT_EVENTS = {
	["MERCHANT_SHOW"] = OnMerchantShow,
	["MERCHANT_CLOSED"] = OnMerchantClosed,
}

eventFrame:SetScript("OnEvent", function(self, event, ...)
	-- Immediate dispatch events
	local immediateHandler = IMMEDIATE_DISPATCH_EVENTS[event]
	if immediateHandler then
		DispatchToModule(immediateHandler[1], immediateHandler[2], ...)
		return
	end

	-- Merchant events
	local merchantHandler = MERCHANT_EVENTS[event]
	if merchantHandler then
		if event == "MERCHANT_SHOW" and JustJunk.Utils.ShouldAutomate() then
			merchantHandler()
		elseif event == "MERCHANT_CLOSED" then
			merchantHandler()
		end
		return
	end

	-- Handle other events if automation is enabled
	if not GetConfig("enabled") or not JustJunk.Utils.ShouldAutomate() or not JustJunk.Utils.IsSafeForAutomation() then 
		return 
	end

	local handlers = EVENT_HANDLERS[event]
	if handlers then
		for i = 1, #handlers, 2 do
			local moduleName = handlers[i]
			local methodName = handlers[i + 1]
			
			if moduleName == "Core" then
				if methodName == "OnMerchantShow" then
					OnMerchantShow()
				elseif methodName == "OnMerchantClosed" then
					OnMerchantClosed()
				end
			else
				DispatchToModule(moduleName, methodName, ...)
			end
		end
	end
end)

----------------------------------------------------------------------
-- Module API
----------------------------------------------------------------------

function JustJunk.SetupEvents()
	if GetConfig("enabled") then
		RegisterEvents()
	else
		UnregisterEvents()
	end
end

----------------------------------------------------------------------
-- Initialization
----------------------------------------------------------------------

local initFrame = CreateFrame("FRAME")
initFrame:RegisterEvent("ADDON_LOADED")
initFrame:SetScript("OnEvent", function(self, event, loadedAddonName)
	if loadedAddonName == addonName then
		-- Initialize config module first
		if JustJunk.ConfigModule and JustJunk.ConfigModule.Initialize then
			JustJunk.ConfigModule.Initialize()
			configReady = true
			JustJunk.Utils.Debug("Core", "Config modules ready")
			ProcessMerchantQueue()
		end
		
		-- Initialize other modules
		local loadedModules = {}
		for _, moduleName in ipairs(moduleList) do
			local module = JustJunk[moduleName]
			if module and module.Initialize then
				module.Initialize()
				loadedModules[#loadedModules + 1] = moduleName
			end
		end
		
		-- Setup events after module initialization
		JustJunk.Utils.ScheduleOnce('setup_events', 0, JustJunk.SetupEvents)
		self:UnregisterEvent("ADDON_LOADED")

		local loadMessage = "JustJunk v1.0.0 loaded"
		if #loadedModules > 0 then
			loadMessage = loadMessage .. " (" .. table.concat(loadedModules, ", ") .. ")"
		end
		
		if JustJunk.ConfigModule and JustJunk.ConfigModule.IsDebugMode and JustJunk.ConfigModule.IsDebugMode() then
			print("|cff00ccff" .. loadMessage .. "|r")
		end
	end
end)