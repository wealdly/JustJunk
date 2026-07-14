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
					name = config.perStack and "Keep if Stack Value Above (Gold)" or "Keep if AH Value Above (Gold)",
					desc = config.thresholdDesc,
					order = 3,
					min = 0, max = 10000, step = 1,
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
		order = 5,
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
			usePawnUpgradeCheck = {
				type = "toggle",
				name = "Sell Non-upgrades (Pawn)",
				desc = "When Pawn is installed with an active scale, also sell gear inside the item-level safety margin that Pawn says is not an upgrade for anything you have equipped, even at a higher item level. Gear worth more than your keep-above threshold on the auction house is still protected. Has no effect without Pawn. (Armor of a type your class can't use is sold regardless of this setting.)",
				width = "full",
				order = 3,
				disabled = function() return not rawget(_G, "PawnIsInitialized") end,
				get = function() return Get("merchant", "usePawnUpgradeCheck") ~= false end,
				set = Set("merchant", "usePawnUpgradeCheck"),
			},
			protectTransmog = {
				type = "toggle",
				name = "Keep Uncollected Transmog",
				desc = "Keep any item whose transmog appearance you haven't collected yet, so you can wear or use it to learn the look before selling. Applies to gear, weapons, and appearance-teaching items everywhere JustJunk sells (bags, bank, and warband bank). On by default.",
				width = "full",
				order = 4,
				get = function() return Get("merchant", "protectTransmog") ~= false end,
				set = Set("merchant", "protectTransmog"),
			},
		}
	}
end

local function CountOverrides(key)
	return JustJunk.Utils.CountKeys(JustJunk.ConfigModule.Get("merchant", key))
end

local function CreateOverrideOptions()
	return {
		type = "group",
		name = "Manual Overrides",
		inline = true,
		order = 6,
		args = {
			summary = {
				type = "description",
				order = 1,
				fontSize = "medium",
				name = function()
					return string.format(
						"Always keep: |cffffcc00%d|r item(s)\nAlways vendor: |cffffcc00%d|r item(s)\n\n" ..
						"|cff888888Add or remove individual items with /jj keep, /jj junk, /jj clear <item link or ID>.|r",
						CountOverrides("forceKeepItems"), CountOverrides("forceSellItems"))
				end,
			},
			clearKeep = {
				type = "execute",
				name = "Clear Keep List",
				desc = "Remove every item from the always-keep list.",
				order = 2,
				confirm = true,
				disabled = function() return CountOverrides("forceKeepItems") == 0 end,
				func = function() JustJunk.ConfigModule.Set("merchant", "forceKeepItems", {}) end,
			},
			clearSell = {
				type = "execute",
				name = "Clear Vendor List",
				desc = "Remove every item from the always-vendor list.",
				order = 3,
				confirm = true,
				disabled = function() return CountOverrides("forceSellItems") == 0 end,
				func = function() JustJunk.ConfigModule.Set("merchant", "forceSellItems", {}) end,
			},
		},
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
					showBankButton = {
						type = "toggle",
						name = "Bank Cleanup Button",
						desc = "Show a 'Pull Junk' button while your bank is open. It moves sell-worthy items out of your bank and warband bank into your bags, ready to vendor. Drag the button to reposition it.",
						order = 4,
						get = function() return Get(nil, "showBankButton") ~= false end,
						set = Set(nil, "showBankButton"),
					},
					bankPullWarband = {
						type = "toggle",
						name = "Include Warband Bank",
						desc = "When you use Pull Junk, also clean the warband (account) bank, not just this character's bank. Gear and containers there are always left alone; only trade goods, consumables, and grey junk are pulled. Turn this off if you keep another character's crafting materials or storage in the warband bank. On by default.",
						order = 5,
						disabled = function() return Get(nil, "showBankButton") == false end,
						get = function() return Get(nil, "bankPullWarband") ~= false end,
						set = Set(nil, "bankPullWarband"),
					},
					minimapButton = {
						type = "toggle",
						name = "Minimap Button",
						desc = "Show the JustJunk minimap button. Click it at the bank to pull junk into your bags. Works with any bag addon.",
						order = 6,
						get = function()
							local m = JustJunk.db and JustJunk.db.profile and JustJunk.db.profile.minimap
							return not (m and m.hide)
						end,
						set = function(_, value)
							local m = JustJunk.db and JustJunk.db.profile and JustJunk.db.profile.minimap
							if m then m.hide = not value end
							local dbicon = _G.LibStub and _G.LibStub("LibDBIcon-1.0", true)
							if dbicon then
								if value then dbicon:Show("JustJunk") else dbicon:Hide("JustJunk") end
							end
						end,
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
						set = Set(nil, "debugMode"),
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
						if style == "coinGlow" or style == "coinDim" then
							return style
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
		itemLevel = CreateItemLevelOptions(),
		overrides = CreateOverrideOptions(),
	}

	-- Add generated category options
	local categoryOptions = GenerateCategoryOptions("selling", CATEGORY_CONFIGS.selling)
	for key, value in pairs(categoryOptions) do
		merchantArgs[key] = value
	end
	
	return merchantArgs
end
