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
					name = "Enable " .. config.key,
					desc = config.desc,
					order = 1,
					get = function() return Get("merchant", config.enableKey) end,
					set = Set("merchant", config.enableKey),
				},
				[config.qualityKey] = {
					type = "select",
					name = "Max Quality",
					desc = "Highest quality allowed for selling.",
					order = 2,
					values = CreateQualityValues(),
					get = function() return Get("merchant", config.qualityKey) end,
					set = Set("merchant", config.qualityKey),
				},
				[config.thresholdKey] = {
					type = "range",
					name = "Keep if AH Value Above (Gold)",
					desc = config.thresholdDesc,
					order = 3,
					min = 0, max = 1000, step = 1,
					get = function()
						return math.floor((Get("merchant", config.thresholdKey) or 0) / 10000)
					end,
					set = function(info, value)
						JustJunk.ConfigModule.Set("merchant", config.thresholdKey, value * 10000)
					end,
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
		name = "Gear Protection",
		inline = true,
		order = 4,
		args = {
			levelInfo = {
				type = "description",
				name = "|cff888888Protects gear close to what you have equipped.|r",
				order = 1,
				fontSize = "small",
			},
			gearSafetyPercent = {
				type = "range",
				name = "Gear Safety Margin (%)",
				desc = "Keep gear within this percent of the item level you have equipped in that slot (or your average item level when the slot is empty).",
				min = 0, max = 30, step = 1,
				order = 2,
				get = function() return Get("merchant", "gearSafetyPercent") end,
				set = Set("merchant", "gearSafetyPercent"),
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
				name = "JustJunk",
				order = 1,
			},
			summary = {
				type = "group",
				name = "Overview",
				inline = true,
				order = 2,
				args = {
					description = {
						type = "description",
						name = "|cffffcc00Automates vendor cleanup with market-aware safety checks.|r\n\n" ..
						     "|cff888888Sells junk first, protects valuable items, and can auto-repair.|r",
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
						desc = "Sell and repair automatically when opening a merchant.",
						order = 2,
						get = function() return Get("merchant", "enabled") end,
						set = Set("merchant", "enabled"),
					},
					autoSortBags = {
						type = "toggle",
						name = "Auto-sort Bags",
						desc = "Sort your inventory with WoW's own sort whenever you open your bags (never bank or warband). Off by default. A quick sort already runs automatically right after the addon sells at a merchant, regardless of this setting.",
						order = 3,
						get = function() return Get(nil, "autoSortBags") == true end,
						set = Set(nil, "autoSortBags"),
					},
				}
			},
			developerSection = {
				type = "group",
				name = "Developer & Debug",
				inline = true,
				order = 4,
				args = {
					debugMode = {
						type = "toggle",
						name = "Debug Mode",
						desc = "Show debug messages in chat.",
						order = 1,
						get = function() return Get(nil, "debugMode") end,
						set = function(info, value)
							JustJunk.ConfigModule.Set(nil, "debugMode", value)
						end,
					},
				},
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
			name = "|cff888888Timing, pricing source order, and sell protections.|r",
			order = 1.5,
			fontSize = "small",
		},
		selling = {
			type = "group",
			name = "Selling",
			inline = true,
			order = 1.7,
			args = {
				sellGreyJunk = {
					type = "toggle",
					name = "Auto-sell Grey Junk",
					desc = "Automatically sell all Poor (grey) quality items when visiting a merchant. On by default.",
					order = 1,
					get = function() return Get("merchant", "sellGreyJunk") ~= false end,
					set = Set("merchant", "sellGreyJunk"),
				},
			}
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
					desc = "Delay before selling starts after merchant opens.",
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
					desc = "Price lookup order used for sell decisions.",
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
		markers = {
			type = "group",
			name = "Bag Markers",
			inline = true,
			order = 4,
			args = {
				sellMarkerStyle = {
					type = "select",
					name = "Marker Display",
					desc = "Visual style for merchant sell markers.",
					order = 1,
					values = {
						off = "Don't Show",
						coin = "Coin",
						coinGlow = "Coin + Glow",
						coinDim = "Coin + Dim",
					},
					get = function()
						local style = Get("merchant", "sellMarkerStyle")
						local enabled = Get("merchant", "showSellMarkers")
						if enabled == false then
							return "off"
						end
						if style == "coinGlow" then
							return "coinGlow"
						end
						if style == "coinDim" then
							return "coinDim"
						end
						return "coin"
					end,
					set = function(info, value)
						if value == "off" then
							JustJunk.ConfigModule.Set("merchant", "showSellMarkers", false)
							JustJunk.ConfigModule.Set("merchant", "sellMarkerStyle", "coin")
							return
						end
						JustJunk.ConfigModule.Set("merchant", "showSellMarkers", true)
						JustJunk.ConfigModule.Set("merchant", "sellMarkerStyle", value)
					end,
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
