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
-- Shared Widget Builders
----------------------------------------------------------------------

local function CreateQualityValues()
	local values = {}
	for i = 0, 6 do
		values[i] = JustJunk.QUALITY_NAMES and JustJunk.QUALITY_NAMES[i + 1] or ("Quality " .. i)
	end
	return values
end

-- The three per-category sell knobs (enable / quality cap / keep-above).
-- Shared by the generated category groups and the bespoke Gear group.
local function CategoryArgs(config)
	return {
		[config.enableKey] = {
			type = "toggle",
			name = "Enable",
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
		},
	}
end

-- One inline group per category, skipping Gear (built bespoke with its
-- protection controls). Ordered after the Gear group.
local function GenerateCategoryOptions(configs)
	local args = {}
	local order = 30

	for _, config in ipairs(configs) do
		if config.key ~= "Gear" then
			args[config.key:lower()] = {
				type = "group",
				name = config.name or config.key,
				inline = true,
				order = order,
				args = CategoryArgs(config),
			}
			order = order + 1
		end
	end

	return args
end

-- Gear merges its sell knobs with the item-level / Pawn / equipment-set
-- protections so the whole "how do I handle gear" story lives in one box.
local function CreateGearOptions(config)
	local args = CategoryArgs(config)

	args.gearSafetyPercent = {
		type = "range",
		name = "Gear Safety Margin (%)",
		desc = "Keep gear within this percent of the item level you have equipped in that slot (or your average item level when the slot is empty).",
		min = 0, max = 30, step = 1,
		order = 4,
		hidden = JustJunk.IS_FOREVER,
		get = function() return Get("merchant", "gearSafetyPercent") end,
		set = Set("merchant", "gearSafetyPercent"),
	}
	args.usePawnUpgradeCheck = {
		type = "toggle",
		name = "Sell Non-upgrades (Pawn)",
		desc = "When Pawn is installed with an active scale, also sell gear inside the item-level safety margin that Pawn says is not an upgrade for anything you have equipped, even at a higher item level. Gear worth more than your keep-above threshold on the auction house is still protected. Has no effect without Pawn. (Armor of a type your class can't use is sold regardless of this setting.)",
		width = "full",
		order = 5,
		hidden = JustJunk.IS_FOREVER,
		disabled = function() return not rawget(_G, "PawnIsInitialized") end,
		get = function() return Get("merchant", "usePawnUpgradeCheck") ~= false end,
		set = Set("merchant", "usePawnUpgradeCheck"),
	}
	args.foreverScoring = {
		type = "description",
		name = "Gear uses the shared class/role stat score, not item level. Set your role in the gear advisor. "
			.. "Any positive gain is kept, even below the advisor's prompt threshold. "
			.. "Without a scoring provider, or for unknown stats/effects, non-grey gear is kept. "
			.. "Confirmed non-upgrades still pass auction, alt, trade-window and manual-keep protections.",
		order = 4,
		hidden = not JustJunk.IS_FOREVER,
	}
	args.protectEquipmentSets = {
		type = "toggle",
		name = "Keep Equipment Set Items",
		desc = "Keep any item assigned to a saved equipment set, at any quality. Turn this off if your sets are situational swaps you don't need protected: set items are then judged by the normal gear and auction-value rules. Manual keeps still apply. On by default.",
		width = "full",
		order = 7,
		get = function() return Get("merchant", "protectEquipmentSets") ~= false end,
		set = Set("merchant", "protectEquipmentSets"),
	}

	return {
		type = "group",
		name = config.name or "Gear",
		inline = true,
		order = 20,
		args = args,
	}
end

local function CountOverrides(key)
	return JustJunk.Utils.CountKeys(JustJunk.ConfigModule.Get("merchant", key))
end

local function CreateOverrideOptions()
	local selectedKeep, selectedVendor
	local function OverrideValues(key)
		local values = {}
		for id, enabled in pairs(JustJunk.ConfigModule.Get("merchant", key) or {}) do
			if enabled then
				local ok, name = pcall(C_Item.GetItemInfo, id)
				if not ok then JustJunk.Utils.Debug("Config", "Could not load override item: " .. tostring(name)) end
				if not ok or (issecretvalue and issecretvalue(name)) or type(name) ~= "string" then
					name = "Item"
				end
				values[id] = name .. " (" .. tostring(id) .. ")"
			end
		end
		return values
	end
	return {
		type = "group",
		name = "Manual Overrides",
		inline = true,
		order = 90,
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
			keepItems = {
				type = "select", name = "Always Keep Items", order = 4, width = "double",
				values = function() return OverrideValues("forceKeepItems") end,
				get = function()
					if not (Get("merchant", "forceKeepItems") or {})[selectedKeep] then selectedKeep = nil end
					return selectedKeep
				end,
				set = function(_, id) selectedKeep = id end,
			},
			removeKeep = {
				type = "execute", name = "Remove Selected Keep", order = 5,
				disabled = function()
					return not selectedKeep or not (Get("merchant", "forceKeepItems") or {})[selectedKeep]
				end,
				func = function()
					if JustJunk.ConfigModule.SetItemOverride("clear", tostring(selectedKeep)) then selectedKeep = nil end
				end,
			},
			vendorItems = {
				type = "select", name = "Always Vendor Items", order = 6, width = "double",
				values = function() return OverrideValues("forceSellItems") end,
				get = function()
					if not (Get("merchant", "forceSellItems") or {})[selectedVendor] then selectedVendor = nil end
					return selectedVendor
				end,
				set = function(_, id) selectedVendor = id end,
			},
			removeVendor = {
				type = "execute", name = "Remove Selected Vendor", order = 7,
				disabled = function()
					return not selectedVendor or not (Get("merchant", "forceSellItems") or {})[selectedVendor]
				end,
				func = function()
					if JustJunk.ConfigModule.SetItemOverride("clear", tostring(selectedVendor)) then selectedVendor = nil end
				end,
			},
		},
	}
end

----------------------------------------------------------------------
-- Tab: General (switches + where the UI shows up)
----------------------------------------------------------------------

function JustJunk.ConfigUI.CreateGeneralOptions()
	return {
		type = "group",
		name = "General",
		order = 1,
		args = {
			main = {
				type = "group",
				name = "Main Controls",
				inline = true,
				order = 1,
				args = {
					enabled = {
						type = "toggle",
						name = "Enable JustJunk",
						desc = "Enable or disable the entire addon.",
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
					merchantDelay = {
						type = "range",
						name = "Merchant Interaction Delay",
						desc = "Delay before selling starts after a merchant opens.",
						min = 0.1, max = 2.0, step = 0.1,
						order = 3,
						get = function() return Get("merchant", "merchantDelay") end,
						set = Set("merchant", "merchantDelay"),
					},
				},
			},
			interface = {
				type = "group",
				name = "Interface",
				inline = true,
				order = 2,
				args = {
					minimapButton = {
						type = "toggle",
						name = "Minimap Button",
						desc = "Show the JustJunk minimap button. Click it at the bank to pull junk into your bags. Works with any bag addon.",
						order = 1,
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
					showBankButton = {
						type = "toggle",
						name = "Bank Cleanup Button",
						desc = "Show a 'Pull Junk' button while your bank is open. It moves sell-worthy items out of your bank and warband bank into your bags, ready to vendor. Drag the button to reposition it.",
						order = 2,
						get = function() return Get(nil, "showBankButton") ~= false end,
						set = Set(nil, "showBankButton"),
					},
					bankPullWarband = {
						type = "toggle",
						name = "Include Warband Bank",
						desc = "When you use Pull Junk, also clean the warband (account) bank, not just this character's bank. Gear and containers there are always left alone; only trade goods, consumables, and grey junk are pulled. Turn this off if you keep another character's crafting materials or storage in the warband bank. On by default.",
						order = 3,
						disabled = function() return Get(nil, "showBankButton") == false end,
						get = function() return Get(nil, "bankPullWarband") ~= false end,
						set = Set(nil, "bankPullWarband"),
					},
					autoSortBags = {
						type = "toggle",
						name = "Auto-sort Bags",
						desc = "Sort your inventory with WoW's own sort whenever you open your bags (never bank or warband). Off by default. A quick sort already runs automatically right after the addon sells at a merchant, regardless of this setting.",
						order = 4,
						get = function() return Get(nil, "autoSortBags") == true end,
						set = Set(nil, "autoSortBags"),
					},
					sellMarkerStyle = {
						type = "select",
						name = "Bag Markers",
						desc = "Overlay on bag items that JustJunk would sell.",
						order = 5,
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
					showDecisionTooltips = {
						type = "toggle", name = "Item Decision Tooltips", order = 6,
						desc = "Show the keep/sell decision for a bag item, its reason, vendor value and any available auction value.",
						get = function() return Get("merchant", "showDecisionTooltips") ~= false end,
						set = Set("merchant", "showDecisionTooltips"),
					},
				},
			},
			debug = {
				type = "group",
				name = "Developer & Debug",
				inline = true,
				order = 3,
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
		},
	}
end

----------------------------------------------------------------------
-- Tab: Selling Rules (what gets sold, and what is protected)
----------------------------------------------------------------------

function JustJunk.ConfigUI.CreateSellingOptions()
	local gearConfig
	for _, config in ipairs(CATEGORY_CONFIGS.selling or {}) do
		if config.key == "Gear" then
			gearConfig = config
			break
		end
	end

	local args = {
		behavior = {
			type = "group",
			name = "Behavior",
			inline = true,
			order = 1,
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
						["oribos"] = "Oribos Exchange",
					},
					get = function() return Get("merchant", "preferredPricingSource") end,
					set = Set("merchant", "preferredPricingSource"),
				},
				sellGreyJunk = {
					type = "toggle",
					name = "Auto-sell Grey Junk",
					desc = "Automatically sell all Poor (grey) quality items when visiting a merchant. On by default.",
					order = 2,
					get = function() return Get("merchant", "sellGreyJunk") ~= false end,
					set = Set("merchant", "sellGreyJunk"),
				},
				replaceJunkWhenFull = {
					type = "toggle",
					name = "Make Room for Valuable Loot",
					desc = "When looting stalls with full bags, offer to destroy the cheapest junk stack in a general-purpose bag for more valuable remaining loot, then retry that loot once the slot is free. Works with native auto-loot and accepts an optional handoff from JustLoot after its retry loop stops. Uses the higher of vendor value and the configured market price (including Auctionator), multiplied by the actual quantity. Grey and bound items use vendor value only; grey AH listings are ignored for carried items and incoming loot. Unpriced non-grey junk is kept. Zero-value grey trash is eligible. Requires a confirmation click to destroy one stack. Keep lists, protected bags, equipment sets, quests, refund and group-trade windows remain protected. Off by default.",
					width = "full",
					order = 3,
					get = function() return Get("merchant", "replaceJunkWhenFull") == true end,
					set = Set("merchant", "replaceJunkWhenFull"),
				},
				cleanupJunk = {
					type = "execute",
					name = "Clean Up Worthless Non-stackables",
					desc = "Scan inventory for non-stackable junk below the cleanup percentage of the average occupied bag-slot value. Uses the same market pricing and item protections as loot replacement, including zero-value grey trash. Shows each item and the remaining total before deletion; one confirmation click per item. The initial cutoff cannot increase during a pass. Never deletes automatically. Also available with /jj cleanup.",
					width = "full",
					order = 4,
					disabled = function() return Get(nil, "enabled") ~= true end,
					func = function() JustJunk.StartJunkCleanup() end,
				},
				cleanupValuePercent = {
					type = "range",
					name = "Cleanup Value Cutoff (%)",
					desc = "Non-stackable junk must be worth less than this percentage of the average occupied bag-slot value. 5% is conservative; 10% is more aggressive. Items JustJunk would keep remain protected.",
					min = 1, max = 10, step = 1,
					order = 5,
					get = function() return Get("merchant", "cleanupValuePercent") end,
					set = Set("merchant", "cleanupValuePercent"),
				},
			},
		},
		overrides = CreateOverrideOptions(),
	}

	if gearConfig then
		args.gear = CreateGearOptions(gearConfig)
	end

	-- Consumables / Trade Goods / Recipes
	local categoryOptions = GenerateCategoryOptions(CATEGORY_CONFIGS.selling)
	for key, value in pairs(categoryOptions) do
		args[key] = value
	end

	return {
		type = "group",
		name = "Selling Rules",
		order = 2,
		args = args,
	}
end
