----------------------------------------------------------------------
-- MarketEngine.lua - Unified Pricing System
-- Author: wealdly | Version: 1.0.0
----------------------------------------------------------------------

local addonName, JustJunk = ...
JustJunk.MarketEngine = {}

local AUCTIONATOR_CALLER_ID = "JustJunk"

-- Simple cache with TTL
local priceCache = {}
local CACHE_TTL = 30

-- Availability checks are throttled to avoid repeatedly probing external addon APIs.
local availabilityCache = {}
local AVAILABILITY_TTL = 5

----------------------------------------------------------------------
-- Pricing Source Registry
----------------------------------------------------------------------

local PRICING_SOURCES = {
	tsm = {
		name = "TSM",
		priority = 1,
		checkFunc = "CheckTSM",
		priceFunc = "GetTSMPrice"
	},
	auctionator = {
		name = "Auctionator", 
		priority = 2,
		checkFunc = "CheckAuctionator",
		priceFunc = "GetAuctionatorPrice"
	},
	oribos = {
		name = "Oribos Exchange",
		priority = 3,
		checkFunc = "CheckOribos", 
		priceFunc = "GetOribosPrice"
	}
}

----------------------------------------------------------------------
-- Source Detection
----------------------------------------------------------------------

local function CheckTSM()
	-- Check for TSM API
	if _G.TSM_API and type(_G.TSM_API.GetCustomPriceValue) == "function" then
		local success, result = pcall(_G.TSM_API.GetCustomPriceValue, "vendorsell", "i:2589")
		return success and result ~= nil
	end
	
	-- Check for TSM.API
	if _G.TSM and _G.TSM.API and type(_G.TSM.API.GetCustomPriceValue) == "function" then
		local success, result = pcall(_G.TSM.API.GetCustomPriceValue, "vendorsell", "i:2589")
		return success and result ~= nil
	end
	
	return false
end

local function CheckAuctionator()
	return _G.Auctionator and
		   _G.Auctionator.API and
		   _G.Auctionator.API.v1 and
		   type(_G.Auctionator.API.v1.GetAuctionPriceByItemLink) == "function" and
		   type(_G.Auctionator.API.v1.GetAuctionPriceByItemID) == "function"
end

local function CheckOribos()
	if not (_G.OEMarketInfo and type(_G.OEMarketInfo) == "function") then
		return false
	end

	local ok, hasData = pcall(_G.OEMarketInfo, 0)
	return ok and hasData == true
end

local function GetCacheKey(itemLink)
	if type(itemLink) ~= "string" then return nil end

	-- Full item links preserve bonus/suffix/item-level variants and avoid cross-item pollution.
	if itemLink:find("^|c%x+|Hitem:") then
		return itemLink
	end

	local itemID = JustJunk.Utils.GetItemIDFromLink(itemLink)
	if itemID then
		return tostring(itemID)
	end

	return itemLink
end

----------------------------------------------------------------------
-- Price Retrieval Functions
----------------------------------------------------------------------

local function GetTSMPrice(itemLink)
	if not itemLink then return 0 end
	
	local itemID = JustJunk.Utils.GetItemIDFromLink(itemLink)
	if not itemID then return 0 end
	
	local tsmAPI = _G.TSM_API or (_G.TSM and _G.TSM.API)
	if not tsmAPI then return 0 end
	
	local itemString = "i:" .. itemID
	local sources = {"DBMarket", "DBMinBuyout", "DBHistorical", "vendorsell"}
	
	for _, source in ipairs(sources) do
		local success, price = pcall(tsmAPI.GetCustomPriceValue, source, itemString)
		if success and type(price) == "number" and price > 0 then
			return price
		end
	end
	
	return 0
end

local function GetAuctionatorPrice(itemLink)
	if not itemLink or not CheckAuctionator() then return 0 end
	
	local itemID = JustJunk.Utils.GetItemIDFromLink(itemLink)
	if not itemID then return 0 end
	
	local api = _G.Auctionator.API.v1
	
	-- Try by item link first
	local success, price = pcall(api.GetAuctionPriceByItemLink, AUCTIONATOR_CALLER_ID, itemLink)
	if success and type(price) == "number" and price > 0 then
		return price
	end
	
	-- Try by item ID
	success, price = pcall(api.GetAuctionPriceByItemID, AUCTIONATOR_CALLER_ID, itemID)
	if success and type(price) == "number" and price > 0 then
		return price
	end
	
	return 0
end

local function GetOribosPrice(itemLink)
	if not itemLink or not CheckOribos() then return 0 end
	
	local success, result = pcall(_G.OEMarketInfo, itemLink, {})
	if not success or not result or result.input ~= itemLink then
		return 0
	end
	
	return result.market and result.market > 0 and result.market or
		   result.region and result.region > 0 and result.region or 0
end

----------------------------------------------------------------------
-- Cache Management
----------------------------------------------------------------------

local function GetFromCache(cacheKey)
	local entry = priceCache[cacheKey]
	if entry and (GetTime() - entry.timestamp) < CACHE_TTL then
		return entry.price, entry.source
	end
	return nil
end

local function SetCache(cacheKey, price, source)
	if not cacheKey or not tonumber(price) or tonumber(price) < 0 or not source then
		return false
	end
	
	priceCache[cacheKey] = {
		price = tonumber(price),
		source = tostring(source),
		timestamp = GetTime()
	}
	return true
end

----------------------------------------------------------------------
-- Public API
----------------------------------------------------------------------

function JustJunk.MarketEngine.IsSourceAvailable(sourceID)
	local config = PRICING_SOURCES[sourceID]
	if not config then return false end

	local now = GetTime()
	local cached = availabilityCache[sourceID]
	if cached and (now - cached.timestamp) < AVAILABILITY_TTL then
		return cached.available
	end
	
	local checkFunc = JustJunk.MarketEngine[config.checkFunc]
	local available = checkFunc and checkFunc() or false
	availabilityCache[sourceID] = {
		available = available,
		timestamp = now,
	}

	return available
end

function JustJunk.MarketEngine.GetSourceStatus()
	local status = {
		activeCount = 0,
		sources = {}
	}
	
	for sourceID, config in pairs(PRICING_SOURCES) do
		local available = JustJunk.MarketEngine.IsSourceAvailable(sourceID)
		status.sources[sourceID] = {
			name = config.name,
			available = available,
			priority = config.priority
		}
		if available then
			status.activeCount = status.activeCount + 1
		end
	end
	
	return status
end

function JustJunk.MarketEngine.GetPrice(itemLink, preferredSource)
	if not itemLink then return 0, "no_link" end

	local cacheKey = GetCacheKey(itemLink)
	if not cacheKey then return 0, "no_item_id" end
	
	-- Check cache first
	local cached, source = GetFromCache(cacheKey)
	if cached then return cached, source end
	
	-- Build priority list based on preference
	local tryOrder = {}
	local preferred = preferredSource or "auto"
	
	if preferred ~= "auto" and PRICING_SOURCES[preferred] then
		table.insert(tryOrder, preferred)
	end
	
	-- Add remaining sources by priority
	local remainingSources = {}
	for sourceID, config in pairs(PRICING_SOURCES) do
		if sourceID ~= preferred then
			table.insert(remainingSources, {id = sourceID, priority = config.priority})
		end
	end
	table.sort(remainingSources, function(a, b) return a.priority < b.priority end)
	
	for _, sourceData in ipairs(remainingSources) do
		table.insert(tryOrder, sourceData.id)
	end
	
	-- Try sources in order
	for _, sourceID in ipairs(tryOrder) do
		if JustJunk.MarketEngine.IsSourceAvailable(sourceID) then
			local config = PRICING_SOURCES[sourceID]
			local priceFunc = JustJunk.MarketEngine[config.priceFunc]
			
			if priceFunc then
				local price = priceFunc(itemLink)
				if price and price > 0 then
					SetCache(cacheKey, price, sourceID)
					return price, sourceID
				end
			end
		end
	end
	
	return 0, "no_data"
end

function JustJunk.MarketEngine.GetFallbackPrice(itemType)
	if itemType == "trade" then
		return JustJunk.ConfigModule.Get("merchant", "fallbackTradePrice") or 50000 -- 5g in copper
	end
	return 0
end

function JustJunk.MarketEngine.ClearCache()
	priceCache = {}
	availabilityCache = {}
end

function JustJunk.MarketEngine.DebugPricing(itemLink)
	if not itemLink then return end
	
	JustJunk.Utils.Debug("Market", "Testing pricing for: " .. itemLink)
	
	for sourceID, config in pairs(PRICING_SOURCES) do
		local available = JustJunk.MarketEngine.IsSourceAvailable(sourceID)
		if available then
			local priceFunc = JustJunk.MarketEngine[config.priceFunc]
			local price = priceFunc and priceFunc(itemLink) or 0
			JustJunk.Utils.Debug("Market", string.format("  %s: %s", config.name, 
				price > 0 and JustJunk.Utils.FormatMoney(price) or "No data"))
		else
			JustJunk.Utils.Debug("Market", string.format("  %s: Not available", config.name))
		end
	end
	
	local finalPrice, source = JustJunk.MarketEngine.GetPrice(itemLink)
	JustJunk.Utils.Debug("Market", string.format("Final result: %s (%s)", 
		finalPrice > 0 and JustJunk.Utils.FormatMoney(finalPrice) or "No data", source))
end

----------------------------------------------------------------------
-- Expose source functions for direct access
----------------------------------------------------------------------

JustJunk.MarketEngine.CheckTSM = CheckTSM
JustJunk.MarketEngine.CheckAuctionator = CheckAuctionator  
JustJunk.MarketEngine.CheckOribos = CheckOribos
JustJunk.MarketEngine.GetTSMPrice = GetTSMPrice
JustJunk.MarketEngine.GetAuctionatorPrice = GetAuctionatorPrice
JustJunk.MarketEngine.GetOribosPrice = GetOribosPrice

function JustJunk.MarketEngine.Initialize()
	JustJunk.Utils.Debug("Market", "Market engine initialized")
end