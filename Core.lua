----------------------------------------------------------------------
-- Core.lua - Event Dispatcher and Merchant Automation
-- Author: wealdly | Version: 1.0.0
----------------------------------------------------------------------

local addonName, JustJunk = ...
_G.JustJunk = JustJunk

----------------------------------------------------------------------
-- Event Handler Configuration
----------------------------------------------------------------------

local EVENT_HANDLERS = {
	-- Equipment events
	["PLAYER_EQUIPMENT_CHANGED"] = {"ItemEngine", "OnEquipmentChanged"}
}

----------------------------------------------------------------------
-- State Management
----------------------------------------------------------------------

local moduleList = {"MarketEngine", "ItemEngine", "BagMarkers", "SortEngine", "BankEngine"}
local eventFrame = CreateFrame("FRAME")
local eventsRegistered = false
local sellingActive = false
local configReady = false
local saleSummaryPrinted = false

-- Seconds between per-item sells. One server action per tick, so this is the
-- sustained sell rate (~7/sec) - kept below the server's action rate limit to
-- avoid a flood disconnect. Grey junk bypasses this via the native bulk sale.
local SELL_THROTTLE = 0.15

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

-- Once-only sale summary, shared by the sell-loop completion and merchant close.
local function PrintSaleSummary()
	if saleSummaryPrinted then return end
	local report = JustJunk.ItemEngine and JustJunk.ItemEngine.GetSellSessionReport
		and JustJunk.ItemEngine.GetSellSessionReport()
	if report and report.soldCount and report.soldCount > 0 then
		JustJunk.Utils.Print("Sold " .. report.soldCount .. " item(s) for " .. JustJunk.Utils.FormatMoney(report.totalValue or 0))
		saleSummaryPrinted = true
	end
end

local function HandleAutoRepair()
	if not (CanMerchantRepair and GetRepairAllCost and RepairAllItems) then return end
	if not CanMerchantRepair() then return end

	local cost = GetRepairAllCost()
	if not cost or cost <= 0 then return end

	local useGuild = (CanGuildBankRepair and CanGuildBankRepair() and
				   GetGuildBankWithdrawMoney and cost <= (GetGuildBankWithdrawMoney() or 0)) or false

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
			JustJunk.Utils.ScheduleOnce('sell_items', SELL_THROTTLE, SellItems)
		else
			sellingActive = false
		end
	else
		sellingActive = false
		PrintSaleSummary()
		-- Quick tidy once the sell pass is done, to compact the emptied slots.
		if JustJunk.SortEngine and JustJunk.SortEngine.SortAfterSale then
			JustJunk.SortEngine.SortAfterSale()
		end
		JustJunk.Utils.Debug("Core", "Item selling completed")
	end
end

local function OnConfigChanged(module, key, value)
	if module == "merchant" then
		if key == "enabled" and value == false then
			sellingActive = false
		end

		if JustJunk.ItemEngine and JustJunk.ItemEngine.RefreshSessionSettings then
			JustJunk.ItemEngine.RefreshSessionSettings()
		end

		if key == "preferredPricingSource" and JustJunk.MarketEngine and JustJunk.MarketEngine.ClearCache then
			JustJunk.MarketEngine.ClearCache()
		end
		return
	end

	if not module and key == "enabled" and value == false then
		sellingActive = false
	end
end

OnMerchantShow = function()
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
	saleSummaryPrinted = false
	if JustJunk.MarketEngine then
		JustJunk.MarketEngine.ClearCache()
	end
	
	JustJunk.Utils.Debug("Core", "Merchant opened - starting selling process")
	
	-- Add a small delay before selling starts.
	local merchantDelay = JustJunk.ConfigModule.Get("merchant", "merchantDelay") or 0.3
	JustJunk.Utils.Debug("Core", "Using merchant delay: " .. tostring(merchantDelay) .. "s")
	JustJunk.Utils.ScheduleOnce('merchant_start', merchantDelay, function()
		if not GetConfig("enabled") or not JustJunk.ConfigModule.Get("merchant", "enabled") then 
			return 
		end
		
		if not MerchantFrame or not MerchantFrame:IsShown() then
			JustJunk.Utils.Debug("Core", "Merchant closed during delay")
			return
		end
		
		HandleAutoRepair()

		-- Avoid false negatives when there is no grey junk: IsSellAllJunkEnabled may be false in that case.
		if C_MerchantFrame and C_MerchantFrame.IsSellAllJunkEnabled and C_MerchantFrame.GetNumJunkItems then
			local hasJunkItems = (C_MerchantFrame.GetNumJunkItems() or 0) > 0
			if hasJunkItems and not C_MerchantFrame.IsSellAllJunkEnabled() then
				JustJunk.Utils.Debug("Core", "Vendor appears to be repair-only (cannot sell junk)")
				return
			end
		end

		-- Let WoW bulk-sell grey junk natively first (instant, respects the bag
		-- exclude-from-junk flag); the per-item loop then handles selective selling.
		if JustJunk.ItemEngine and JustJunk.ItemEngine.SellGreyJunkNatively then
			JustJunk.ItemEngine.SellGreyJunkNatively()
		end

		-- Start intelligent selling
		sellingActive = true
		JustJunk.Utils.ScheduleOnce('sell_items', SELL_THROTTLE, SellItems)
	end)
end

OnMerchantClosed = function()
	sellingActive = false
	PrintSaleSummary()
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
		eventFrame:RegisterEvent("MERCHANT_SHOW")
		eventFrame:RegisterEvent("MERCHANT_CLOSED")
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

eventFrame:SetScript("OnEvent", function(self, event, ...)
	-- Merchant events bypass the automation gate; CLOSED must always clean up.
	if event == "MERCHANT_SHOW" then
		if JustJunk.Utils.ShouldAutomate() then OnMerchantShow() end
		return
	elseif event == "MERCHANT_CLOSED" then
		OnMerchantClosed()
		return
	end

	-- Handle other events if automation is enabled
	if not GetConfig("enabled") or not JustJunk.Utils.ShouldAutomate() or not JustJunk.Utils.IsSafeForAutomation() then
		return
	end

	-- ponytail: one {module, method} pair per event; restore a pair-loop only if
	-- an event ever needs several handlers.
	local handlers = EVENT_HANDLERS[event]
	if handlers then
		DispatchToModule(handlers[1], handlers[2], ...)
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
			if JustJunk.ConfigModule.RegisterSettingListener then
				JustJunk.ConfigModule.RegisterSettingListener("Core", OnConfigChanged)
			end
			JustJunk.Utils.Debug("Core", "Config modules ready")
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