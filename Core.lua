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

local moduleList = {"MarketEngine", "ItemEngine", "BagMarkers", "ItemControls", "SortEngine", "BankEngine"}
local eventFrame = CreateFrame("FRAME")
local eventsRegistered = false
local sellingActive = false
local merchantSalePaused = false
local buybackHooked = false
local configReady = false
local saleSummaryPrinted = false
local pendingLootReplacement = nil
local lootGeneration = 0
local lootWindowOpen = false
local lootSkipMessagePrinted = false
local autoLootActive = false
local REPLACE_LOOT_POPUP = "JUSTJUNK_REPLACE_LOOT"
local CLEANUP_POPUP = "JUSTJUNK_CLEANUP_JUNK"
local pendingCleanup = nil
local CancelPendingLootReplacement
local CancelCleanup
local ShowNextCleanupItem

local function CanDestroyJunk()
	return JustJunk.ConfigModule.Get(nil, "enabled") == true
		and JustJunk.Utils.ShouldAutomate()
		and JustJunk.Utils.IsSafeForAutomation()
		and not GetCursorInfo()
		and not (MerchantFrame and MerchantFrame:IsShown())
end

local function CanReplaceLoot()
	return not autoLootActive and CanDestroyJunk()
		and JustJunk.ConfigModule.Get("merchant", "replaceJunkWhenFull") == true
end

local function LootStillAvailable(pending)
	local function Matches(slot)
		if GetLootSlotLink(slot) ~= pending.lootLink then return false end
		local _, _, count, _, _, locked = GetLootSlotInfo(slot)
		return not locked and count == pending.lootCount
	end
	if Matches(pending.lootSlot) then return true end
	for slot = 1, (GetNumLootItems and GetNumLootItems() or 0) do
		if Matches(slot) then
			pending.lootSlot = slot
			return true
		end
	end
	return false
end

local function SameJunkItem(current, previous)
	return current and current.bag == previous.bag and current.slot == previous.slot
		and current.itemID == previous.itemID and current.itemLink == previous.itemLink
		and current.stackCount == previous.stackCount and current.value == previous.value
end

local function DestroyJunkStack(junk)
	local okPickup, pickupError = pcall(C_Container.PickupContainerItem, junk.bag, junk.slot)
	local cursorType, cursorID, cursorLink = GetCursorInfo()
	if not okPickup or cursorType ~= "item" or cursorID ~= junk.itemID or cursorLink ~= junk.itemLink then
		if cursorType == "item" then ClearCursor() end
		JustJunk.Utils.Print("Could not safely pick up the selected junk; nothing was destroyed."
			.. (not okPickup and (" " .. tostring(pickupError)) or ""))
		return false
	end

	-- DeleteCursorItem is hardware-gated: never move it to a timer or event.
	local ok, err = pcall(DeleteCursorItem)
	if not ok or GetCursorInfo() then
		ClearCursor()
		JustJunk.Utils.Print("Junk deletion failed; try again manually."
			.. (not ok and (" " .. tostring(err)) or ""))
		return false
	end
	return true
end

-- Seconds between per-item sells. One server action per tick, so this is the
-- sustained sell rate (~7/sec) - kept below the server's action rate limit to
-- avoid a flood disconnect. Grey junk bypasses this via the native bulk sale.
local SELL_THROTTLE = 0.15

-- Forward declarations for merchant handlers used before definition
local OnMerchantShow
local OnMerchantClosed

if StaticPopupDialogs then
	StaticPopupDialogs[REPLACE_LOOT_POPUP] = {
		text = "Bags are full. Permanently destroy %s to make room for %s?",
		button1 = "Destroy and Loot",
		button2 = CANCEL,
		OnAccept = function(self, pending)
			if not pending or pending ~= pendingLootReplacement or pending.phase ~= "confirm_destroy" then return end
			if not CanReplaceLoot() or not LootStillAvailable(pending) then
				JustJunk.Utils.Print("Loot replacement is no longer safe; nothing was destroyed. Try looting again.")
				CancelPendingLootReplacement()
				return
			end

			local current = JustJunk.ItemEngine.FindLowestValueJunkForLoot(pending.lootLink, pending.lootCount)
			if not SameJunkItem(current, pending.junk) or current.lootValue ~= pending.junk.lootValue then
				JustJunk.Utils.Print("Your bags or prices changed; nothing was destroyed. Try looting again.")
				CancelPendingLootReplacement()
				return
			end

			pending.phase = "deleting"
			if not DestroyJunkStack(current) then
				CancelPendingLootReplacement()
				return
			end

			JustJunk.Utils.ScheduleOnce("loot_delete_timeout", 3, function()
				if pendingLootReplacement == pending and pending.phase == "deleting" then
					JustJunk.Utils.Print("Could not confirm a free bag slot; retry looting manually.")
					CancelPendingLootReplacement()
				end
			end)
		end,
		OnCancel = function(self, pending, reason)
			if pendingLootReplacement == pending then
				JustJunk.Utils.Debug("Core", "Make Room confirmation dismissed: " .. tostring(reason))
				CancelPendingLootReplacement()
			end
		end,
		OnHide = function()
			if pendingLootReplacement and pendingLootReplacement.phase == "confirm_destroy" then
				JustJunk.Utils.Debug("Core", "Make Room confirmation hidden before a deletion was confirmed")
				pendingLootReplacement = nil
			end
		end,
		showAlert = true,
		timeout = 0,
		whileDead = false,
		hideOnEscape = true,
		preferredIndex = 3,
	}

	StaticPopupDialogs[CLEANUP_POPUP] = {
		text = "Permanently destroy %s?\n\n%s",
		button1 = "Destroy",
		button2 = CANCEL,
		OnAccept = function(self, pending)
			if pending ~= pendingCleanup or not pending or pending.phase ~= "confirm_destroy" then return end
			if not CanDestroyJunk() or (GetNumLootItems and GetNumLootItems() > 0) then
				JustJunk.Utils.Print("Cleanup is no longer safe; nothing was destroyed.")
				CancelCleanup()
				return
			end

			local current = JustJunk.ItemEngine.FindLowestValueJunkForCleanup(pending.cutoff)
			if not SameJunkItem(current, pending.junk) then
				JustJunk.Utils.Print("Your bags, prices or item protections changed; restart cleanup.")
				CancelCleanup()
				return
			end

			pending.phase = "deleting"
			if not DestroyJunkStack(current) then
				CancelCleanup()
				return
			end
			JustJunk.Utils.ScheduleOnce("junk_cleanup_timeout", 3, function()
				if pendingCleanup == pending and pending.phase == "deleting" then
					JustJunk.Utils.Print("Could not confirm cleanup; restart it manually.")
					CancelCleanup()
				end
			end)
		end,
		OnCancel = function(self, pending)
			if pendingCleanup == pending then CancelCleanup() end
		end,
		showAlert = true,
		timeout = 0,
		whileDead = false,
		hideOnEscape = true,
		preferredIndex = 3,
	}
end

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
	local ok, cost, useGuild, personalFunds = pcall(function()
		if not CanMerchantRepair() then return 0, false, 0 end
		local repairCost, canRepair = GetRepairAllCost()
		if not canRepair or not repairCost or repairCost <= 0 then return 0, false, 0 end
		local guild = false
		if CanGuildBankRepair and GetGuildBankWithdrawMoney and GetGuildBankMoney and CanGuildBankRepair() then
			local allowance, balance = GetGuildBankWithdrawMoney(), GetGuildBankMoney()
			guild = type(allowance) == "number" and type(balance) == "number"
				and (allowance == -1 or allowance >= repairCost) and balance >= repairCost
		end
		return repairCost, guild, GetMoney and GetMoney()
	end)
	if not ok then
		JustJunk.Utils.Print("Could not check repair funding: " .. tostring(cost))
		return
	end
	if cost <= 0 then return end
	local canPayPersonally = type(personalFunds) == "number" and personalFunds >= cost
	if not useGuild and not canPayPersonally then
		JustJunk.Utils.Debug("Core", "Repair skipped: insufficient available funds")
		return
	end

	local repaired, err = pcall(RepairAllItems, useGuild)
	if not repaired and useGuild and canPayPersonally then
		JustJunk.Utils.Debug("Core", "Guild repair request failed; trying personal funds: " .. tostring(err))
		repaired, err = pcall(RepairAllItems, false)
		useGuild = false
	end
	if not repaired then
		JustJunk.Utils.Print("Repair request failed: " .. tostring(err))
		return
	end
	JustJunk.Utils.Debug("Core", "Requested repair for " .. JustJunk.Utils.FormatMoney(cost) .. (useGuild and " (guild)" or ""))
end

local function SellItems()
	if merchantSalePaused or not sellingActive or not MerchantFrame or not MerchantFrame:IsShown() then
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

		if key == "replaceJunkWhenFull" and value ~= true then
			CancelPendingLootReplacement()
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

	-- Repair the instant the merchant opens, before the sell delay and the
	-- frame/junk re-checks below. A transient merchant (e.g. some delve vendors)
	-- can close or fail those re-checks before the delayed sell pass runs;
	-- repair must not be lost with it. Cheap to call twice - it no-ops at 0 cost.
	HandleAutoRepair()

	if merchantSalePaused then return end
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
		if merchantSalePaused then return end
		if not GetConfig("enabled") or not JustJunk.ConfigModule.Get("merchant", "enabled") then 
			return 
		end
		
		if not MerchantFrame or not MerchantFrame:IsShown() then
			JustJunk.Utils.Debug("Core", "Merchant closed during delay")
			return
		end
		
		-- Vendor capability, not bag contents: this is what gates the Sell All Junk
		-- button's visibility, while the button's enabled state tracks the junk count
		-- separately. A vendor that fails it buys nothing, so skipping the sell pass
		-- avoids an error per item.
		if C_MerchantFrame and C_MerchantFrame.IsSellAllJunkEnabled and not C_MerchantFrame.IsSellAllJunkEnabled() then
			JustJunk.Utils.Debug("Core", "Vendor does not buy items")
			return
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
	merchantSalePaused = false
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

local function GetLootSlotCount(slot)
	local _, _, count, _, _, isLocked = GetLootSlotInfo(slot)
	if isLocked or not count or count < 1 then return nil end
	return count
end

local function FindPendingLootSlots()
	local candidates = {}
	-- Native auto-loot and addons with cached LootSlot references bypass Lua hooks.
	for slot = 1, (GetNumLootItems and GetNumLootItems() or 0) do
		local link = GetLootSlotLink(slot)
		if link then
			local count = GetLootSlotCount(slot)
			if count then
				candidates[#candidates + 1] = { slot = slot, link = link, count = count }
			end
		end
	end
	return candidates
end

local function HandleFullBags(notify, retries)
	if pendingLootReplacement or pendingCleanup or not CanReplaceLoot()
		or not (StaticPopup_Show and StaticPopupDialogs and GetLootSlotLink and GetLootSlotInfo
			and LootSlot and DeleteCursorItem and C_Container.PickupContainerItem) then
		return
	end

	local candidates = FindPendingLootSlots()
	if #candidates == 0 then
		if (retries or 0) < 5 then
			local generation = lootGeneration
			JustJunk.Utils.ScheduleOnce("loot_state_retry", 0.1, function()
				if lootGeneration == generation then HandleFullBags(notify, (retries or 0) + 1) end
			end)
			return
		end
		local slots = GetNumLootItems and GetNumLootItems() or 0
		JustJunk.Utils.Debug("Core", "Make Room: no readable unlocked loot after retries; slots=" .. slots)
		for slot = 1, slots do
			local _, name, count, currency, quality, locked = GetLootSlotInfo(slot)
			JustJunk.Utils.Debug("Core", "Loot slot " .. slot .. ": link=" .. tostring(GetLootSlotLink(slot))
				.. ", name=" .. tostring(name) .. ", count=" .. tostring(count)
				.. ", currency=" .. tostring(currency) .. ", quality=" .. tostring(quality)
				.. ", locked=" .. tostring(locked))
		end
		return
	end

	local selectedLoot, junk, skipReason
	for _, candidate in ipairs(candidates) do
		local candidateJunk, reason = JustJunk.ItemEngine.FindLowestValueJunkForLoot(candidate.link, candidate.count)
		if candidateJunk then
			if not junk or candidateJunk.lootValue > junk.lootValue then
				selectedLoot, junk = candidate, candidateJunk
			end
		else
			skipReason = reason
			JustJunk.Utils.Debug("Core", "Loot replacement skipped: " .. reason)
		end
	end
	if not junk then
		if notify and not lootSkipMessagePrinted then
			JustJunk.Utils.Print("Make Room: " .. skipReason .. ". No items were destroyed.")
			lootSkipMessagePrinted = true
		end
		return
	end

	pendingLootReplacement = {
		phase = "confirm_destroy",
		lootSlot = selectedLoot.slot,
		lootLink = selectedLoot.link,
		lootCount = selectedLoot.count,
		junk = junk,
	}
	local dialog = StaticPopup_Show(
		REPLACE_LOOT_POPUP,
		junk.itemLink .. " x" .. junk.stackCount .. " (" .. JustJunk.Utils.FormatMoney(junk.value) .. ")",
		selectedLoot.link .. " x" .. selectedLoot.count .. " (" .. JustJunk.Utils.FormatMoney(junk.lootValue) .. ")",
		pendingLootReplacement
	)
	if not dialog then
		JustJunk.Utils.Print("Could not show the loot replacement confirmation; nothing was destroyed.")
		CancelPendingLootReplacement()
	end
end

local function ScheduleLootReplacementCheck(delay, notify)
	local generation = lootGeneration
	JustJunk.Utils.ScheduleOnce(notify and "loot_bags_full" or "loot_window_check", delay, function()
		if lootGeneration == generation then HandleFullBags(notify) end
	end)
end

function JustJunk.OnLootStalled()
	if not GetNumLootItems or GetNumLootItems() == 0 then return end
	ScheduleLootReplacementCheck(0, true)
end

function JustJunk.SetAutoLootActive(active)
	autoLootActive = active == true
end

local function HandleBagUpdate()
	if pendingCleanup and pendingCleanup.phase == "deleting" then
		local cleanup = pendingCleanup
		if not C_Container.GetContainerItemInfo(cleanup.junk.bag, cleanup.junk.slot) then
			cleanup.destroyed = cleanup.destroyed + 1
			JustJunk.Utils.Print("Destroyed " .. cleanup.junk.itemLink .. ".")
			cleanup.phase = "scanning"
			JustJunk.Utils.ScheduleOnce("junk_cleanup_next", 0, function()
				if pendingCleanup == cleanup then ShowNextCleanupItem() end
			end)
		end
	end

	local pending = pendingLootReplacement
	if not pending or pending.phase ~= "deleting" then return end

	local current = C_Container.GetContainerItemInfo(pending.junk.bag, pending.junk.slot)
	if current then return end

	if not CanReplaceLoot() or not LootStillAvailable(pending) then
		JustJunk.Utils.Print("Junk was destroyed, but the loot cannot be retried safely. Loot manually.")
		CancelPendingLootReplacement()
		return
	end

	pendingLootReplacement = nil
	JustJunk.Utils.Print("Destroyed " .. pending.junk.itemLink .. " x" .. pending.junk.stackCount
		.. " to make room for " .. pending.lootLink .. ".")
	LootSlot(pending.lootSlot)
end

CancelPendingLootReplacement = function()
	pendingLootReplacement = nil
	lootGeneration = lootGeneration + 1
	lootSkipMessagePrinted = false
	if StaticPopup_Hide then
		StaticPopup_Hide(REPLACE_LOOT_POPUP)
	end
end

CancelCleanup = function()
	pendingCleanup = nil
	if StaticPopup_Hide then StaticPopup_Hide(CLEANUP_POPUP) end
end

ShowNextCleanupItem = function()
	local cleanup = pendingCleanup
	if not cleanup then return end
	if not CanDestroyJunk() or (GetNumLootItems and GetNumLootItems() > 0) then
		JustJunk.Utils.Print("Cleanup stopped; clear your cursor and leave combat or the loot window before restarting.")
		CancelCleanup()
		return
	end

	local junk, report, reason = JustJunk.ItemEngine.FindLowestValueJunkForCleanup(cleanup.cutoff)
	if not report then
		JustJunk.Utils.Print("Cleanup stopped: " .. reason .. ".")
		CancelCleanup()
		return
	end
	if not junk then
		JustJunk.Utils.Print("Cleanup finished: " .. cleanup.destroyed
			.. " item(s) destroyed; no more eligible non-stackable junk below the cleanup threshold.")
		CancelCleanup()
		return
	end

	cleanup.cutoff = report.cutoff
	cleanup.junk = junk
	cleanup.phase = "confirm_destroy"
	local dialog = StaticPopup_Show(CLEANUP_POPUP,
		junk.itemLink .. " (" .. JustJunk.Utils.FormatMoney(junk.value) .. ")",
		report.count .. " eligible item(s), worth " .. JustJunk.Utils.FormatMoney(report.totalValue)
			.. " in total. Average occupied bag slot: " .. JustJunk.Utils.FormatMoney(report.average)
			.. ".\nNon-stackable junk must be below " .. report.percent
			.. "% of that average, capped at " .. JustJunk.Utils.FormatMoney(report.cutoff)
			.. " for this pass. One item is deleted per click.",
		cleanup)
	if not dialog then
		JustJunk.Utils.Print("Could not show the cleanup confirmation; nothing was destroyed.")
		CancelCleanup()
	end
end

function JustJunk.StartJunkCleanup()
	if pendingLootReplacement or pendingCleanup then
		JustJunk.Utils.Print("Finish or cancel the current junk confirmation first.")
		return
	end
	if not (StaticPopupDialogs and StaticPopup_Show and DeleteCursorItem and C_Container.PickupContainerItem) then
		JustJunk.Utils.Print("Item cleanup is not supported by this client.")
		return
	end
	pendingCleanup = { phase = "scanning", destroyed = 0 }
	ShowNextCleanupItem()
end

local function RegisterEvents()
	if not eventsRegistered then
		if not buybackHooked and type(hooksecurefunc) == "function" and type(BuybackItem) == "function" then
			hooksecurefunc("BuybackItem", function()
				if merchantSalePaused or not GetConfig("enabled")
					or not JustJunk.ConfigModule.Get("merchant", "enabled")
					or not MerchantFrame or not MerchantFrame:IsShown() then return end
				merchantSalePaused = true
				sellingActive = false
				PrintSaleSummary()
				JustJunk.Utils.Print("Auto-selling paused for this merchant visit after buyback.")
			end)
			buybackHooked = true
		end
		eventFrame:RegisterEvent("MERCHANT_SHOW")
		eventFrame:RegisterEvent("MERCHANT_CLOSED")
		eventFrame:RegisterEvent("UI_ERROR_MESSAGE")
		eventFrame:RegisterEvent("BAG_UPDATE_DELAYED")
		eventFrame:RegisterEvent("LOOT_SLOT_CLEARED")
		eventFrame:RegisterEvent("LOOT_CLOSED")
		eventFrame:RegisterEvent("LOOT_OPENED")
		eventFrame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
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
		lootWindowOpen = false
		CancelPendingLootReplacement()
		CancelCleanup()
		
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
	elseif event == "UI_ERROR_MESSAGE" then
		local errorType, message = ...
		if (ERR_INV_FULL and (errorType == ERR_INV_FULL or message == ERR_INV_FULL))
			or (ERR_BAG_FULL and message == ERR_BAG_FULL)
			or (ERR_LOOT_BAG_FULL and message == ERR_LOOT_BAG_FULL) then
			ScheduleLootReplacementCheck(0, true)
		end
		return
	elseif event == "BAG_UPDATE_DELAYED" then
		HandleBagUpdate()
		return
	elseif event == "LOOT_CLOSED" then
		if pendingLootReplacement then
			JustJunk.Utils.Debug("Core", "Make Room cancelled: LOOT_CLOSED")
		end
		lootWindowOpen = false
		autoLootActive = false
		CancelPendingLootReplacement()
		return
	elseif event == "LOOT_OPENED" then
		lootWindowOpen = true
		CancelCleanup()
		-- Let normal looting settle before checking what remains in full bags.
		ScheduleLootReplacementCheck(0.2, false)
		return
	elseif event == "GET_ITEM_INFO_RECEIVED" then
		local _, success = ...
		if lootWindowOpen and success and CanReplaceLoot() then
			ScheduleLootReplacementCheck(0.1, false)
		end
		return
	elseif event == "LOOT_SLOT_CLEARED" then
		local slot = ...
		if pendingLootReplacement and slot == pendingLootReplacement.lootSlot then
			if not LootStillAvailable(pendingLootReplacement) then
				JustJunk.Utils.Debug("Core", "Make Room cancelled: selected loot disappeared after LOOT_SLOT_CLEARED " .. tostring(slot))
				CancelPendingLootReplacement()
			end
		end
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