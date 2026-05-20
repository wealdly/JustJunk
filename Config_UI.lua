----------------------------------------------------------------------
-- Config_UI.lua - Option Builders and UI Sections
-- Author: wealdly | Version: 1.0.0
----------------------------------------------------------------------

local addonName, JustJunk = ...
JustJunk.ConfigUI = JustJunk.ConfigUI or {}

----------------------------------------------------------------------
-- Local References
----------------------------------------------------------------------

local CF = JustJunk.ConfigData or {}
local CATEGORY_CONFIGS = CF.CATEGORY_CONFIGS or {}

-- Direct config access helpers
local function Get(module, key)
	return JustJunk.ConfigModule.Get(module, key)
end

local function Set(module, key)
	return function(info, value)
		JustJunk.ConfigModule.Set(module, key, value)
	end
end

----------------------------------------------------------------------
-- UI Builder Helpers
----------------------------------------------------------------------

local function CreateQualityValues()
	local values = {}
	for i = 0, 6 do
		values[i] = JustJunk.QUALITY_NAMES and JustJunk.QUALITY_NAMES[i + 1] or ("Quality " .. i)
	end
	return values
end

local function GenerateCategoryOptions(categoryName, configs)
	local args = {}
	local order = 10
	
	for _, config in ipairs(configs) do
		args[config.key:lower()] = {
			type = "group",
			name = config.key,
			inline = true,
			order = order,
			args = {
				[config.enableKey] = {
					type = "toggle",
					name = "Enable " .. config.key .. " Selling",
					desc = config.desc,
					order = 1,
					get = function() return Get("merchant", config.enableKey) end,
					set = Set("merchant", config.enableKey),
				},
				[config.qualityKey] = {
					type = "select",
					name = "Max Quality",
					desc = "Maximum quality of " .. config.key:lower() .. " to sell",
					order = 2,
					values = CreateQualityValues(),
					get = function() return Get("merchant", config.qualityKey) end,
					set = Set("merchant", config.qualityKey),
				},
				[config.thresholdKey] = {
					type = "range",
					name = "Min Auction Value (Gold)",
					desc = config.thresholdDesc,
					order = 3,
					min = 1, max = 1000, step = 1,
					get = function() 
						local copper = Get("merchant", config.thresholdKey) or (config.defaultThreshold * 10000)
						return math.floor(copper / 10000)
					end,
					set = function(info, value) 
						JustJunk.ConfigModule.Set("merchant", config.thresholdKey, value * 10000)
					end,
				},
				[config.multiplierKey] = {
					type = "range",
					name = "Safety Multiplier (x)",
					desc = "Vendor price must be this many times less than auction price",
					order = 4,
					min = 2, max = 20, step = 1,
					get = function() return Get("merchant", config.multiplierKey) end,
					set = Set("merchant", config.multiplierKey),
				}
			}
		}
		order = order + 1
	end
	
	return args
end

----------------------------------------------------------------------
-- Options Sections Builders
----------------------------------------------------------------------

local function CreateItemLevelOptions()
	return {
		type = "group",
		name = "Item Level Evaluation",
		inline = true,
		order = 4,
		args = {
			advancedHeader = {
				type = "header",
				name = "Fine-Tune Protection Levels",
				order = 1,
			},
			levelInfo = {
				type = "description",
				name = "|cff888888Configure item level comparison thresholds for gear protection.|r",
				order = 1.5,
				fontSize = "small",
			},
			slotUpgradeThreshold = {
				type = "range",
				name = "Slot Protection Range",
				desc = "Keep gear within this many item levels of what you have equipped in the same slot.\n\n" ..
				       "• Lower values (0-3): Strict protection, only keep very similar gear\n" ..
				       "• Higher values (8-15): Loose protection, keep more gear\n" ..
				       "• Example: With threshold 5, keep boots within 5 levels of equipped",
				min = 0, max = 80, step = 1,
				order = 2,
				get = function() return Get("merchant", "slotUpgradeThreshold") end,
				set = Set("merchant", "slotUpgradeThreshold"),
				disabled = function() return not Get("merchant", "useSlotComparison") end,
			},
			gearLevelModifierPercent = {
				type = "range",
				name = "Average Level Protection (%)",
				desc = "Sell gear this percentage below your overall average item level (fallback protection).\n\n" ..
				       "• Lower values (1-5%): Conservative, only sell much worse gear\n" ..
				       "• Higher values (10-20%): Aggressive, sell gear closer to average\n" ..
				       "• Only used when slot-specific comparison isn't available",
				min = 0, max = 20, step = 1,
				order = 3,
				get = function() return Get("merchant", "gearLevelModifierPercent") end,
				set = Set("merchant", "gearLevelModifierPercent"),
				disabled = function() return not Get("merchant", "useAverageComparison") end,
			},
			fallbackItemLevelThreshold = {
				type = "range",
				name = "Fallback Item Level Threshold",
				desc = "When slot and average comparisons aren't available, sell gear below this item level.\n\n" ..
				       "• Used as last resort when other methods fail\n" ..
				       "• Set conservatively to avoid selling valuable gear",
				min = 1, max = 200, step = 1,
				order = 4,
				get = function() return Get("merchant", "fallbackItemLevelThreshold") end,
				set = Set("merchant", "fallbackItemLevelThreshold"),
			},
			itemLevelSpacer = {
				type = "description",
				name = "",
				order = 5,
			},
		}
	}
end

----------------------------------------------------------------------
-- Main Options Builders
----------------------------------------------------------------------

function JustJunk.ConfigUI.CreateGeneralOptions()
	return {
		type = "group",
		name = "General",
		order = 1,
		args = {
			header = {
				type = "header",
				name = "JustJunk - Intelligent Inventory Management",
				order = 1,
			},
			summary = {
				type = "group",
				name = "What JustJunk Does",
				inline = true,
				order = 2,
				args = {
					description = {
						type = "description",
						name = "|cffffcc00JustJunk automatically manages your inventory when visiting merchants:|r\n\n" ..
						     "• |cff00ff00Intelligent Selling:|r Sells junk items, outdated gear, and low-value items\n" ..
						     "• |cff00ff00Market Awareness:|r Uses TSM, Auctionator, or Oribos Exchange for price checking\n" ..
						     "• |cff00ff00Smart Protection:|r Never sells valuable items, equipment set pieces, or upgrades\n" ..
						     "• |cff00ff00Auto Repair:|r Repairs your gear using guild funds when possible\n\n" ..
						     "|cff888888Configure the settings below to customize your selling behavior.|r",
						order = 1,
						fontSize = "medium",
					},
				}
			},
			coreSettings = {
				type = "group",
				name = "Main Controls",
				inline = true,
				order = 3,
				args = {
					enabled = {
						type = "toggle",
						name = "Enable JustJunk",
						desc = "Enable or disable the entire addon", 
						order = 1,
						get = function() return Get(nil, "enabled") end,
						set = Set(nil, "enabled"),
					},
					merchantEnabled = {
						type = "toggle",
						name = "Merchant Automation",
						desc = "Automatically sell items and repair gear when talking to merchants.\n\n" ..
						       "|cffffff00What happens:|r Sells grey items first, then evaluates other items based on your settings below\n" ..
						       "|cffffff00Safety:|r Never sells BoP items, quest items, toys, pets, or valuable gear",
						order = 2,
						get = function() return Get("merchant", "enabled") end,
						set = Set("merchant", "enabled"),
					},
				}
			},
			spacer1 = {
				type = "description", 
				name = "\n",
				order = 4,
				fontSize = "small",
			},
		}
	}
end

function JustJunk.ConfigUI.CreateMerchantOptions()
	local merchantArgs = {
		merchantHeader = {
			type = "header",
			name = "Merchant Settings",
			order = 1,
		},
		merchantInfo = {
			type = "description",
			name = "|cffffcc00Configure how JustJunk interacts with merchants and evaluates items.|r\n",
			order = 1.5,
			fontSize = "medium",
		},
		timing = {
			type = "group",
			name = "Timing",
			inline = true,
			order = 2,
			args = {
				merchantDelay = {
					type = "range",
					name = "Merchant Interaction Delay",
					desc = "Time to wait after opening merchant window before starting to sell items.\n\n" ..
					       "|cffffff00Purpose:|r Allows merchant window to fully load and prevents server throttling\n" ..
					       "|cffff9999Note:|r Lower values = faster selling, but may cause errors on slow connections",
					min = 0.1, max = 2.0, step = 0.1,
					order = 1,
					get = function() return Get("merchant", "merchantDelay") end,
					set = Set("merchant", "merchantDelay"),
				},
			}
		},
		pricing = {
			type = "group",
			name = "Price Sources",
			inline = true,
			order = 3,
			args = {
				preferredPricingSource = {
					type = "select",
					name = "Preferred Pricing Source",
					desc = "Choose which addon to prioritize for auction house price data.\n\n" ..
					       "|cffffff00Auto:|r Tries TSM → Auctionator → Oribos Exchange in order\n" ..
					       "|cffffff00Manual:|r Forces use of specific addon if available",
					order = 1,
					values = {
						["auto"] = "Auto (Recommended)",
						["tsm"] = "TSM (TradeSkillMaster)",
						["auctionator"] = "Auctionator",
						["oribos"] = "Oribos Exchange"
					},
					get = function() return Get("merchant", "preferredPricingSource") end,
					set = Set("merchant", "preferredPricingSource"),
				},
			}
		},
		itemLevel = CreateItemLevelOptions()
	}
	
	-- Add generated category options
	local categoryOptions = GenerateCategoryOptions("selling", CATEGORY_CONFIGS.selling)
	for key, value in pairs(categoryOptions) do
		merchantArgs[key] = value
	end
	
	return merchantArgs
end

function JustJunk.ConfigUI.CreateAdvancedOptions()
	return {
		type = "group",
		name = "Advanced",
		order = 1,
		args = {
			header = {
				type = "header", 
				name = "Advanced Configuration",
				order = 1,
			},
			description = {
				type = "description",
				name = "|cffffcc00These settings control internal addon behavior.|r\n\n" ..
				     "|cffff6666[!] Warning:|r Only modify if you understand the implications.\n",
				order = 2,
				fontSize = "medium",
			},
			developerSection = {
				type = "group",
				name = "Developer & Debug",
				inline = true,
				order = 3,
				args = {
					debugMode = {
						type = "toggle",
						name = "Debug Mode", 
						desc = "Show debug messages in chat (for troubleshooting)",
						order = 1,
						get = function() return Get(nil, "debugMode") end,
						set = function(info, value) 
							JustJunk.ConfigModule.Set(nil, "debugMode", value)
						end,
					},
				}
			},
		}
	}
end