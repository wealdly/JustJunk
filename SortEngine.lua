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

local function SortEnabled()
	if not JustJunk.ConfigModule then return false end
	if JustJunk.ConfigModule.Get(nil, "enabled") == false then return false end
	-- Opt-in: off unless the player explicitly enables it.
	return JustJunk.ConfigModule.Get(nil, "autoSortBags") == true
end

-- A bank/guild-bank context means opening it also opened the inventory bags, but
-- the player isn't asking to sort their backpack - skip those.
local function InBankingContext()
	if BankFrame and BankFrame:IsShown() then return true end
	if GuildBankFrame and GuildBankFrame:IsShown() then return true end
	return false
end

-- Shared guards. C_Container.SortBags() only ever sorts the inventory (backpack +
-- equipped bags), never the bank/warband, so scope is correct by construction.
local function CanSort()
	if not SortEnabled() then return false end
	if not (C_Container and C_Container.SortBags) then return false end
	if InCombatLockdown() then return false end
	if InBankingContext() then return false end
	return true
end

-- Open-triggered sort: skip while a merchant is open, because the sell pass may
-- be running or imminent and SortBags() is async (it would race the scan).
function JustJunk.SortEngine.SortInventory()
	if not CanSort() then return end
	if MerchantFrame and MerchantFrame:IsShown() then return end
	pcall(C_Container.SortBags)
end

-- Quick sort right after the merchant auto-sale finishes, to compact the emptied
-- slots. Runs even though the merchant is still open (selling is already done),
-- and uses its own debounce key so an open-triggered sort can't cancel it.
function JustJunk.SortEngine.SortAfterSale()
	JustJunk.Utils.ScheduleOnce("jj_sort_after_sale", POST_SALE_DELAY, function()
		if not CanSort() then return end
		pcall(C_Container.SortBags)
	end)
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
