----------------------------------------------------------------------
-- Config_Data.lua - Configuration Tables and Defaults
-- Author: wealdly | Version: 1.0.0
----------------------------------------------------------------------

local addonName, JustJunk = ...
JustJunk.ConfigData = JustJunk.ConfigData or {}

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
			desc = "Sell low-value gear (protected by item level), and armor of a type your class can't use.",
			thresholdDesc = "Keep gear worth more than this on the auction house.",
		},
		{
			key = "Consumables",
			enableKey = "enableConsumables",
			qualityKey = "maxConsumableQuality",
			thresholdKey = "consumableKeepAbove",
			perStack = true,
			desc = "Sell low-value consumables and related items.",
			thresholdDesc = "Keep consumables whose stack is worth more than this on the auction house. Unpriced consumables are sold.",
		},
		{
			key = "TradeGoods",
			enableKey = "enableTradeGoods",
			qualityKey = "maxTradeGoodQuality",
			thresholdKey = "tradeGoodKeepAbove",
			perStack = true,
			desc = "Sell low-value trade goods and reagents.",
			thresholdDesc = "Keep trade goods worth more than this on the auction house. Materials you can gather or craft count as a full stack (they build back up); others count only the units you carry. Unpriced trade goods are sold.",
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
		showBankButton = true,
		bankPullWarband = true,
		minimap = { hide = false },

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

			-- When Pawn is installed and has an active scale, sell gear inside the
			-- safety margin that Pawn says is not an upgrade for anything equipped.
			-- Only takes effect with Pawn present; no effect otherwise.
			usePawnUpgradeCheck = true,

			-- Keep any item whose transmog appearance is not collected yet, so it
			-- can be worn/used to learn the look before selling.
			protectTransmog = true,

			-- Per category: enable, highest quality eligible to sell, and the
			-- auction-house value above which the item is kept (in copper).
			enableGear = true,
			maxGearQuality = 4,
			gearKeepAbove = 7500000, -- 750g

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
