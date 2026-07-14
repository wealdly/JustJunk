----------------------------------------------------------------------
-- MarketEngine.lua - Unified Pricing System
-- Author: wealdly | Version: 1.0.0
----------------------------------------------------------------------

local addonName, JustJunk = ...
JustJunk.MarketEngine = {}

local GetTime = GetTime
local pcall = pcall
local type = type
local rawget = rawget
local tonumber = tonumber
local tostring = tostring
local pairs = pairs
local ipairs = ipairs
local next = next
local string = string

local AUCTIONATOR_CALLER_ID = "JustJunk"
local TSM_SOURCE_PRIORITY = {"dbminbuyout", "dbmarket", "dbhistorical", "vendorsell"}

-- Simple cache with TTL
local priceCache = {}
local CACHE_TTL = 30
local NO_DATA_TTL = 5

-- Availability checks are throttled to avoid repeatedly probing external addon APIs.
local availabilityCache = {}
local AVAILABILITY_TTL = 5
local tsmSourcesCache = {
	sources = nil,
	timestamp = 0,
}

----------------------------------------------------------------------
-- Pricing Source Registry
----------------------------------------------------------------------

local PRICING_SOURCES = {
	tsm = {
		name = "TSM",
		checkFunc = "CheckTSM",
		priceFunc = "GetTSMPrice"
	},
	auctionator = {
		name = "Auctionator",
		checkFunc = "CheckAuctionator",
		priceFunc = "GetAuctionatorPrice"
	},
	oribos = {
		name = "Oribos Exchange",
		checkFunc = "CheckOribos",
		priceFunc = "GetOribosPrice"
	}
}

local SORTED_SOURCE_IDS = {"tsm", "auctionator", "oribos"}
local SOURCE_ORDERS = {
	auto = SORTED_SOURCE_IDS,
	tsm = SORTED_SOURCE_IDS,
	auctionator = {"auctionator", "tsm", "oribos"},
	oribos = {"oribos", "tsm", "auctionator"},
}

local function ResolveTSMApi()
	local tsmApiGlobal = rawget(_G, "TSM_API")
	if tsmApiGlobal and type(tsmApiGlobal.GetCustomPriceValue) == "function" then
		return tsmApiGlobal
	end

	local tsm = rawget(_G, "TSM")
	if tsm and tsm.API and type(tsm.API.GetCustomPriceValue) == "function" then
		return tsm.API
	end

	return nil
end

local function GetTSMItemString(tsmAPI, itemLink, itemID)
	if tsmAPI and type(tsmAPI.ToItemString) == "function" then
		local ok, itemString = pcall(tsmAPI.ToItemString, itemLink)
		if ok and type(itemString) == "string" and itemString ~= "" then
			return itemString
		end
	end

	return "i:" .. itemID
end

local function GetTSMSources(tsmAPI)
	if not tsmAPI then return TSM_SOURCE_PRIORITY end

	local now = GetTime()
	if tsmSourcesCache.sources and (now - tsmSourcesCache.timestamp) < AVAILABILITY_TTL then
		return tsmSourcesCache.sources
	end

	local orderedSources = {}
	local keySet = {}
	local hasSourceKeys = false

	if type(tsmAPI.GetPriceSourceKeys) == "function" then
		local result = {}
		local ok, keys = pcall(tsmAPI.GetPriceSourceKeys, result)
		if ok and type(keys) == "table" then
			for _, key in ipairs(keys) do
				if type(key) == "string" then
					keySet[string.lower(key)] = true
					hasSourceKeys = true
				end
			end
		end
	end

	for _, source in ipairs(TSM_SOURCE_PRIORITY) do
		if not hasSourceKeys or keySet[source] then
			table.insert(orderedSources, source)
		end
	end

	if #orderedSources == 0 then
		orderedSources = TSM_SOURCE_PRIORITY
	end

	tsmSourcesCache.sources = orderedSources
	tsmSourcesCache.timestamp = now
	return orderedSources
end

local function GetOrderedSourceIDs(preferred)
	return SOURCE_ORDERS[preferred or "auto"] or SORTED_SOURCE_IDS
end

----------------------------------------------------------------------
-- Source Detection
----------------------------------------------------------------------

local function CheckTSM()
	return ResolveTSMApi() ~= nil
end

local function CheckAuctionator()
	local auctionator = rawget(_G, "Auctionator")
	return auctionator and
		   auctionator.API and
		   auctionator.API.v1 and
		   type(auctionator.API.v1.GetAuctionPriceByItemLink) == "function" and
		   type(auctionator.API.v1.GetAuctionPriceByItemID) == "function"
end

local function CheckOribos()
	local oeMarketInfo = rawget(_G, "OEMarketInfo")
	if not (oeMarketInfo and type(oeMarketInfo) == "function") then
		return false
	end

	local ok, hasData = pcall(oeMarketInfo, 0)
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
	
	local tsmAPI = ResolveTSMApi()
	if not tsmAPI then return 0 end
	
	local itemString = GetTSMItemString(tsmAPI, itemLink, itemID)
	local sources = GetTSMSources(tsmAPI) or TSM_SOURCE_PRIORITY
	
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

	-- CheckAuctionator() above already validated the API.v1 chain (no yield since).
	local api = rawget(_G, "Auctionator").API.v1

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
	local oeMarketInfo = rawget(_G, "OEMarketInfo")
	if not oeMarketInfo then return 0 end
	
	local success, result = pcall(oeMarketInfo, itemLink, {})
	if not success or not result or result.input ~= itemLink then
		return 0
	end
	
	return result.market and result.market > 0 and result.market or
		   result.region and result.region > 0 and result.region or 0
end

local function GetPriceBySource(sourceID, itemLink)
	local config = PRICING_SOURCES[sourceID]
	if not config then return 0 end

	local priceFunc = JustJunk.MarketEngine[config.priceFunc]
	if not priceFunc then return 0 end

	return priceFunc(itemLink) or 0
end

----------------------------------------------------------------------
-- Cache Management
----------------------------------------------------------------------

local function GetFromCache(cacheKey)
	local entry = priceCache[cacheKey]
	if entry and entry.source == "no_data" and (GetTime() - entry.timestamp) < NO_DATA_TTL then
		return 0, "no_data"
	end
	if entry and (GetTime() - entry.timestamp) < CACHE_TTL then
		return entry.price, entry.source
	end
	return nil
end

local function SetCache(cacheKey, price, source)
	local n = tonumber(price)
	if not cacheKey or not n or n < 0 or not source then
		return
	end

	priceCache[cacheKey] = {
		price = n,
		source = tostring(source),
		timestamp = GetTime()
	}
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
	if cached ~= nil then return cached, source end
	
	local tryOrder = GetOrderedSourceIDs(preferredSource)
	
	-- Try sources in order
	for _, sourceID in ipairs(tryOrder) do
		if JustJunk.MarketEngine.IsSourceAvailable(sourceID) then
			local price = GetPriceBySource(sourceID, itemLink)
			if price > 0 then
				SetCache(cacheKey, price, sourceID)
				return price, sourceID
			end
		end
	end

	SetCache(cacheKey, 0, "no_data")
	
	return 0, "no_data"
end

function JustJunk.MarketEngine.ClearCache()
	priceCache = {}
	availabilityCache = {}
	tsmSourcesCache.sources = nil
	tsmSourcesCache.timestamp = 0
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