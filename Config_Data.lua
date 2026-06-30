----------------------------------------------------------------------
-- Config_Data.lua - Configuration Tables and Defaults
-- Author: wealdly | Version: 1.0.0
----------------------------------------------------------------------

local addonName, JustJunk = ...
JustJunk.ConfigData = JustJunk.ConfigData or {}

----------------------------------------------------------------------
-- Essential Constants
----------------------------------------------------------------------

local CONSTANTS = {
    -- Core system settings
    REPAIR_GUILD = true,
    AUTO_REPAIR = true,
    IGNORE_SET_ITEMS = true,
    ENABLE_ITEM_LEVEL_CHECK = true,

    -- Currency conversion
    COPPER_PER_GOLD = 10000,
    COPPER_PER_SILVER = 100,
}

JustJunk.ConfigData.CONSTANTS = CONSTANTS

----------------------------------------------------------------------
-- Selling Categories (UI metadata only; default values live in
-- defaults.profile below, which is the single source of truth)
----------------------------------------------------------------------

JustJunk.ConfigData.CATEGORY_CONFIGS = {
	selling = {
		{
			key = "Gear",
			enableKey = "enableGear",
			qualityKey = "maxGearQuality",
			thresholdKey = "gearKeepAbove",
			desc = "Sell low-value gear, protected by item level.",
			thresholdDesc = "Keep gear worth more than this on the auction house.",
		},
		{
			key = "Consumables",
			enableKey = "enableConsumables",
			qualityKey = "maxConsumableQuality",
			thresholdKey = "consumableKeepAbove",
			desc = "Sell low-value consumables and related items.",
			thresholdDesc = "Keep consumables worth more than this on the auction house.",
		},
		{
			key = "TradeGoods",
			enableKey = "enableTradeGoods",
			qualityKey = "maxTradeGoodQuality",
			thresholdKey = "tradeGoodKeepAbove",
			desc = "Sell low-value trade goods and reagents.",
			thresholdDesc = "Keep trade goods worth more than this on the auction house.",
		},
		{
			key = "Recipes",
			enableKey = "enableRecipes",
			qualityKey = "maxRecipeQuality",
			thresholdKey = "recipeKeepAbove",
			desc = "Sell recipes you already know.",
			thresholdDesc = "Keep recipes worth more than this on the auction house.",
		},
	}
}

----------------------------------------------------------------------
-- Default Configuration Values (single source of truth)
----------------------------------------------------------------------

JustJunk.ConfigData.defaults = {
	profile = {
		enabled = true,
		debugMode = false,
		autoSortBags = false,

		merchant = {
			enabled = true,
			merchantDelay = 0.3,
			preferredPricingSource = "auto",
			sellGreyJunk = true,
			showSellMarkers = true,
			sellMarkerStyle = "coin",
			forceKeepItems = {},
			forceSellItems = {},

			-- Gear item-level protection (single knob): keep gear within this
			-- percent of the equipped slot item, or your average item level when
			-- the slot is empty.
			gearSafetyPercent = 10,

			-- Per category: enable, highest quality eligible to sell, and the
			-- auction-house value above which the item is kept (in copper).
			enableGear = true,
			maxGearQuality = 4,
			gearKeepAbove = 5000000, -- 500g

			enableConsumables = true,
			maxConsumableQuality = 1,
			consumableKeepAbove = 200000, -- 20g

			enableTradeGoods = true,
			maxTradeGoodQuality = 2,
			tradeGoodKeepAbove = 500000, -- 50g

			enableRecipes = true,
			maxRecipeQuality = 2,
			recipeKeepAbove = 5000000, -- 500g
		}
	}
}
