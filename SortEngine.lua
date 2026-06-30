----------------------------------------------------------------------
-- SortEngine.lua - Lightweight inventory sort (bag open + after auto-sale)
-- Author: wealdly | Version: 1.0.0
----------------------------------------------------------------------

local addonName, JustJunk = ...
JustJunk.SortEngine = {}

local C_Container = C_Container
local InCombatLockdown = InCombatLockdown
local SORT_DEBOUNCE = 0.1
local POST_SALE_DELAY = 0.2

-- A bank/guild-bank context means opening it also opened the inventory bags, but
-- the player isn't asking to sort their backpack - skip those.
local function InBankingContext()
	if BankFrame and BankFrame:IsShown() then return true end
	if GuildBankFrame and GuildBankFrame:IsShown() then return true end
	return false
end

-- Safety guards shared by both sort paths. C_Container.SortBags() only ever sorts
-- the inventory (backpack + equipped bags), never the bank/warband, so scope is
-- correct by construction.
local function SafeToSort()
	if not JustJunk.ConfigModule then return false end
	if JustJunk.ConfigModule.Get(nil, "enabled") == false then return false end
	if not (C_Container and C_Container.SortBags) then return false end
	if InCombatLockdown() then return false end
	if InBankingContext() then return false end
	return true
end

-- Quick tidy right after the addon's own auto-sale, to compact the emptied slots.
-- Part of the auto-sell flow, so it always runs (safety guards aside) and is NOT
-- gated by the Auto-sort Bags toggle - that toggle only controls the on-open
-- sort. Its own debounce key keeps an open-triggered sort from cancelling it.
function JustJunk.SortEngine.SortAfterSale()
	JustJunk.Utils.ScheduleOnce("jj_sort_after_sale", POST_SALE_DELAY, function()
		if SafeToSort() then pcall(C_Container.SortBags) end
	end)
end

-- Open-triggered sort: opt-in via the Auto-sort Bags toggle (off by default), and
-- never while a merchant is open (the sell pass may be running or imminent and
-- SortBags() is async, which would race the scan).
function JustJunk.SortEngine.SortInventory()
	if not SafeToSort() then return end
	if JustJunk.ConfigModule.Get(nil, "autoSortBags") ~= true then return end
	if MerchantFrame and MerchantFrame:IsShown() then return end
	pcall(C_Container.SortBags)
end

local function QueueSort()
	JustJunk.Utils.ScheduleOnce("jj_sort_open", SORT_DEBOUNCE, function()
		JustJunk.SortEngine.SortInventory()
	end)
end

function JustJunk.SortEngine.Initialize()
	local eventRegistry = rawget(_G, "EventRegistry")
	if eventRegistry then
		eventRegistry:RegisterCallback("ContainerFrame.OpenBag", QueueSort, JustJunk.SortEngine)
	end
	JustJunk.Utils.Debug("Sort", "Sort engine initialized")
end
