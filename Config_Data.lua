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
    USE_FALLBACK_THRESHOLD = true,
    
    -- Currency conversion
    COPPER_PER_GOLD = 10000,
    COPPER_PER_SILVER = 100,
}

JustJunk.ConfigData.CONSTANTS = CONSTANTS

----------------------------------------------------------------------
-- Selling Categories Configuration
----------------------------------------------------------------------

JustJunk.ConfigData.CATEGORY_CONFIGS = {
	selling = {
		{
			key = "Gear", 
			enableKey = "enableGear",
			qualityKey = "maxGearQuality", 
			thresholdKey = "minWorthwhileAH_Gear",
			multiplierKey = "gearMultiplier",
			defaultEnabled = true,
			defaultQuality = 4,
			defaultThreshold = 500,
			defaultMultiplier = 8,
			desc = "Automatically sell outdated gear (evaluated by item level vs. your average)",
			thresholdDesc = "Don't vendor gear worth more than this on the auction house"
		},
		{
			key = "Consumables",
			enableKey = "enableConsumables", 
			qualityKey = "maxConsumableQuality",
			thresholdKey = "minWorthwhileAH_Consumables",
			multiplierKey = "consumableMultiplier",
			defaultEnabled = true,
			defaultQuality = 2,
			defaultThreshold = 50,
			defaultMultiplier = 5,
			desc = "Automatically sell low-value consumables (food, potions, flasks, gems, containers)",
			thresholdDesc = "Don't vendor consumables worth more than this on the auction house"
		},
		{
			key = "TradeGoods",
			enableKey = "enableTradeGoods",
			qualityKey = "maxTradeGoodQuality", 
			thresholdKey = "minWorthwhileAH_TradeGoods",
			multiplierKey = "tradeGoodMultiplier",
			defaultEnabled = true,
			defaultQuality = 2,
			defaultThreshold = 50,
			defaultMultiplier = 5,
			desc = "Automatically sell low-value trade goods and reagents (crafting materials, battle pets)",
			thresholdDesc = "Don't vendor trade goods worth more than this on the auction house"
		},
		{
			key = "Recipes",
			enableKey = "enableRecipes",
			qualityKey = "maxRecipeQuality",
			thresholdKey = "minWorthwhileAH_Recipes", 
			multiplierKey = "recipeMultiplier",
			defaultEnabled = true,
			defaultQuality = 2,
			defaultThreshold = 500,
			defaultMultiplier = 10,
			desc = "Automatically sell recipes you already know (profession recipes, patterns, plans)",
			thresholdDesc = "Don't vendor recipes worth more than this on the auction house"
		}
	}
}

----------------------------------------------------------------------
-- Default Configuration Values
----------------------------------------------------------------------

JustJunk.ConfigData.defaults = {
	profile = {
		enabled = true,
		debugMode = false,
		
		merchant = {
			enabled = true,
			merchantDelay = 0.3,
			preferredPricingSource = "auto",
			
			-- Item level evaluation settings
			useSlotComparison = true,
			useAverageComparison = true,
			
			-- Individual item level controls
			gearLevelModifierPercent = 5,
			slotUpgradeThreshold = 5,
			fallbackItemLevelThreshold = 50,
			
			enableGear = true,
			maxGearQuality = 4,
			minWorthwhileAH_Gear = 5000000, -- 500g in copper
			gearMultiplier = 8,
			
			enableConsumables = true,
			maxConsumableQuality = 1,
			minWorthwhileAH_Consumables = 200000, -- 20g in copper
			consumableMultiplier = 3,
			
			enableTradeGoods = true,
			maxTradeGoodQuality = 2,
			minWorthwhileAH_TradeGoods = 500000, -- 50g in copper
			tradeGoodMultiplier = 4,
			fallbackTradePrice = 50000, -- 5g in copper
			
			enableRecipes = true,
			maxRecipeQuality = 2,
			minWorthwhileAH_Recipes = 5000000, -- 500g in copper
			recipeMultiplier = 10,
		}
	}
}