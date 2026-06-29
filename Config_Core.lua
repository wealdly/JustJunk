----------------------------------------------------------------------
-- Config_Core.lua - Config Glue, Ace Init, and Slash Commands
-- Author: wealdly | Version: 1.0.0
----------------------------------------------------------------------

local addonName, JustJunk = ...
JustJunk.ConfigModule = JustJunk.ConfigModule or {}

----------------------------------------------------------------------
-- Local References
----------------------------------------------------------------------

local function GetDefaults()
	local CF = JustJunk.ConfigData or {}
	return CF.defaults or { profile = {} }
end

----------------------------------------------------------------------
-- State Management
----------------------------------------------------------------------

local database = {}
local debugMode = false
local settingListeners = {}

----------------------------------------------------------------------
-- Utilities
----------------------------------------------------------------------

local function Debug(msg)
	if debugMode then
		print("|cff00ccffJJ Config:|r " .. tostring(msg))
	end
end

local function GetLib(libName)
	if not _G.LibStub then return nil end

	local ok, lib = pcall(function()
		return _G.LibStub(libName, true)
	end)

	if ok then
		return lib
	end

	return nil
end

local function ResolveProfile()
	return database and database.profile or nil
end

local function ReadProfileValue(profile, module, key)
	if not profile then return nil end

	if module then
		local moduleConfig = profile[module]
		return moduleConfig and moduleConfig[key] or nil
	end

	return profile[key]
end

----------------------------------------------------------------------
-- Configuration Management Functions
----------------------------------------------------------------------

function JustJunk.ConfigModule.Get(module, key)
	local profile = ResolveProfile()
	local value = ReadProfileValue(profile, module, key)
	if value ~= nil then
		return value
	end

	local defaults = GetDefaults()
	local defaultProfile = defaults and defaults.profile or nil
	return ReadProfileValue(defaultProfile, module, key)
end

function JustJunk.ConfigModule.GetAll(module)
	if not database or not database.profile then return {} end
	return database.profile[module] or {}
end

function JustJunk.ConfigModule.Set(module, key, value)
	if not database or not database.profile then return end

	local oldValue = JustJunk.ConfigModule.Get(module, key)
	
	if module then
		database.profile[module] = database.profile[module] or {}
		database.profile[module][key] = value
	else
		database.profile[key] = value
		if key == "debugMode" then
			debugMode = value and true or false
		end
	end
	
	-- Handle special cases
	if not module and key == "enabled" and JustJunk.SetupEvents then
		JustJunk.SetupEvents()
	end
	
	-- Update debug mode immediately when changed
	if not module and key == "debugMode" then
		Debug("Debug mode " .. (value and "enabled" or "disabled"))
	end
	
	JustJunk.ConfigModule.Save()

	if oldValue ~= value then
		for _, callback in pairs(settingListeners) do
			pcall(callback, module, key, value, oldValue)
		end
	end
end

function JustJunk.ConfigModule.RegisterSettingListener(listenerKey, callback)
	if not listenerKey or type(callback) ~= "function" then
		return false
	end

	settingListeners[listenerKey] = callback
	return true
end

function JustJunk.ConfigModule.UnregisterSettingListener(listenerKey)
	if not listenerKey then return end
	settingListeners[listenerKey] = nil
end

function JustJunk.ConfigModule.Save()
	if not database or not database.profile then return end
	if not database.RegisterCallback then
		JustJunkDB = database.profile
	end
end

function JustJunk.ConfigModule.Debug(msg)
	Debug(msg)
end

function JustJunk.ConfigModule.IsDebugMode()
	return debugMode
end

----------------------------------------------------------------------
-- UI Options Table Builder
----------------------------------------------------------------------

local function BuildOptionsTable()
	local optionsTable = {
		type = "group",
		name = "JustJunk",
		handler = JustJunk.ConfigModule,
		childGroups = "tab",
		args = {
			general = {
				type = "group",
				name = "General",
				order = 1,
				args = JustJunk.ConfigUI.CreateGeneralOptions().args
			},
			merchant = {
				type = "group",
				name = "Merchant",
				order = 2,
				disabled = function()
					return not JustJunk.ConfigModule.Get("merchant", "enabled")
				end,
				args = JustJunk.ConfigUI.CreateMerchantOptions()
			}
		}
	}
	
	-- Add profiles tab if database is available
	if JustJunk.db and _G.LibStub then
		local AceDBOptions = GetLib("AceDBOptions-3.0")
		if AceDBOptions then
			optionsTable.args.profiles = AceDBOptions:GetOptionsTable(JustJunk.db)
			optionsTable.args.profiles.order = 99
		end
	end
	
	return optionsTable
end

function JustJunk.ConfigModule.ShowConfig()
	local AceConfigDialog = GetLib("AceConfigDialog-3.0")
	if AceConfigDialog then
		if AceConfigDialog.OpenFrames and AceConfigDialog.OpenFrames["JustJunk"] then
			AceConfigDialog:Close("JustJunk")
		else
			AceConfigDialog:Open("JustJunk")
		end
		return
	end
	
	JustJunk.Utils.Debug("Config", "Options panel not available - use slash commands: /jj help")
end

function JustJunk.ConfigModule.Initialize()
	-- Try to setup AceDB
	local AceDB = GetLib("AceDB-3.0")
	
	local defaults = GetDefaults()
	if AceDB then
		database = AceDB:New("JustJunkDB", defaults, true)
		JustJunk.db = database
	else
		if not JustJunkDB then JustJunkDB = {} end
		database = { profile = JustJunkDB }
		JustJunk.Utils.TableMerge(database.profile, defaults.profile)
		JustJunk.db = database
	end
	
	debugMode = database.profile.debugMode or false
	Debug("Configuration initialized with debug mode: " .. tostring(debugMode))
	
	-- Setup AceConfig if available
	if _G.LibStub then
		local AceConfigRegistry = GetLib("AceConfigRegistry-3.0")
		local AceConfigDialog = GetLib("AceConfigDialog-3.0")
		if AceConfigRegistry and AceConfigDialog then
			local options = BuildOptionsTable()
			AceConfigRegistry:RegisterOptionsTable("JustJunk", options)
			AceConfigDialog:AddToBlizOptions("JustJunk", "JustJunk")
		end
	end
	
	-- Register slash command
	SLASH_JUSTJUNK1 = "/jj"
	SLASH_JUSTJUNK2 = "/justjunk"
	SlashCmdList["JUSTJUNK"] = HandleSlashCommand
	
	Debug("Config module initialized")
end

----------------------------------------------------------------------
-- Slash Command Handler
----------------------------------------------------------------------

local function PrintSlash(msg)
	print("|cff00ccffJustJunk:|r " .. tostring(msg))
end

local function ShowStatus()
	local enabledStatus = JustJunk.ConfigModule.Get(nil, "enabled") and "|cff00ff00ON|r" or "|cffff6666OFF|r"
	local merchantStatus = JustJunk.ConfigModule.Get("merchant", "enabled") and "|cff00ff00ON|r" or "|cffff6666OFF|r"
	local debugStatus = JustJunk.ConfigModule.Get(nil, "debugMode") and "|cff00ff00ON|r" or "|cffff6666OFF|r"

	PrintSlash("Status")
	print("  Enabled: " .. enabledStatus)
	print("  Merchant: " .. merchantStatus)
	print("  Debug: " .. debugStatus)

	local status = JustJunk.MarketEngine and JustJunk.MarketEngine.GetSourceStatus()
	if status then
		print("  Market Sources: " .. status.activeCount .. " available")
		for _, sourceID in ipairs({"tsm", "auctionator", "oribos"}) do
			local sourceInfo = status.sources and status.sources[sourceID]
			if sourceInfo then
				print("    " .. sourceInfo.name .. ": " .. (sourceInfo.available and "Available" or "Unavailable"))
			end
		end
	end
end

local function ParseQueryAsItemLink(query)
	if not query or query == "" then return nil end

	if query:find("|Hitem:") then
		return query
	end

	local itemID = tonumber(query)
	if itemID then
		local itemLink = C_Item.GetItemLinkByID(itemID)
		if itemLink then return itemLink end
		return "item:" .. itemID
	end

	return query
end

local function ParseQueryAsItemID(query)
	if not query or query == "" then return nil end

	local itemID = tonumber(query)
	if itemID then return itemID end

	local linkID = tonumber(query:match("item:(%d+)"))
	if linkID then return linkID end

	local itemLink = ParseQueryAsItemLink(query)
	if not itemLink then return nil end

	return JustJunk.Utils.GetItemIDFromLink(itemLink)
end

local function CloneBoolMap(source)
	local out = {}
	for id, enabled in pairs(source or {}) do
		out[id] = enabled
	end
	return out
end

local function SetManualOverride(mode, query)
	local itemID = ParseQueryAsItemID(query)
	if not itemID then
		PrintSlash("Usage: /jj " .. mode .. " <itemLink|itemID>")
		return
	end

	local merchantConfig = JustJunk.ConfigModule.GetAll("merchant")
	local keepItems = CloneBoolMap(merchantConfig.forceKeepItems)
	local sellItems = CloneBoolMap(merchantConfig.forceSellItems)

	if mode == "keep" then
		keepItems[itemID] = true
		sellItems[itemID] = nil
		PrintSlash("Manual keep set for itemID " .. itemID)
	elseif mode == "junk" then
		sellItems[itemID] = true
		keepItems[itemID] = nil
		PrintSlash("Manual vendor set for itemID " .. itemID)
	elseif mode == "clear" then
		keepItems[itemID] = nil
		sellItems[itemID] = nil
		PrintSlash("Manual override cleared for itemID " .. itemID)
	end

	JustJunk.ConfigModule.Set("merchant", "forceKeepItems", keepItems)
	JustJunk.ConfigModule.Set("merchant", "forceSellItems", sellItems)
end

local function ShowOverrides()
	local merchantConfig = JustJunk.ConfigModule.GetAll("merchant")
	local keepItems = merchantConfig.forceKeepItems or {}
	local sellItems = merchantConfig.forceSellItems or {}

	local keepCount = 0
	for _ in pairs(keepItems) do keepCount = keepCount + 1 end

	local sellCount = 0
	for _ in pairs(sellItems) do sellCount = sellCount + 1 end

	PrintSlash("Manual Overrides")
	print("  Keep list: " .. keepCount .. " item(s)")
	print("  Vendor list: " .. sellCount .. " item(s)")
	if keepCount == 0 and sellCount == 0 then
		print("  No overrides set")
	end
end

local function InspectPricing(arg)
	if not arg or arg == "" then
		PrintSlash("Usage: /jj inspect pricing <itemLink|itemID>")
		return
	end

	local itemLink = ParseQueryAsItemLink(arg)
	if not itemLink then
		PrintSlash("Unable to resolve item input: " .. tostring(arg))
		return
	end

	local sourceOrder = {
		{ id = "tsm", name = "TSM", check = "CheckTSM", price = "GetTSMPrice" },
		{ id = "auctionator", name = "Auctionator", check = "CheckAuctionator", price = "GetAuctionatorPrice" },
		{ id = "oribos", name = "Oribos Exchange", check = "CheckOribos", price = "GetOribosPrice" },
	}

	PrintSlash("Pricing inspect for " .. tostring(itemLink))
	for _, source in ipairs(sourceOrder) do
		local checkFunc = JustJunk.MarketEngine and JustJunk.MarketEngine[source.check]
		local priceFunc = JustJunk.MarketEngine and JustJunk.MarketEngine[source.price]
		local available = checkFunc and checkFunc() or false
		local price = (available and priceFunc) and (priceFunc(itemLink) or 0) or 0
		print(string.format("  %s: %s (%s)", source.name, price > 0 and JustJunk.Utils.FormatMoney(price) or "No data", available and "available" or "unavailable"))
	end

	local finalPrice, finalSource = JustJunk.MarketEngine.GetPrice(itemLink)
	print(string.format("  Final: %s (%s)", finalPrice > 0 and JustJunk.Utils.FormatMoney(finalPrice) or "No data", finalSource or "none"))
end

local function InspectMarkers()
	if not JustJunk.BagMarkers or not JustJunk.BagMarkers.GetDebugSnapshot then
		PrintSlash("Marker inspector unavailable")
		return
	end

	local snapshot = JustJunk.BagMarkers.GetDebugSnapshot()
	if not snapshot then
		PrintSlash("Marker inspector returned no data")
		return
	end

	PrintSlash("Marker inspect")
	print("  Markers enabled: " .. tostring(snapshot.markersEnabled))
	print("  Marker style: " .. tostring(snapshot.markerStyle))
	print("  Merchant open: " .. tostring(snapshot.merchantOpen))
	print("  Visible bag buttons: " .. tostring(snapshot.visibleButtons))
	print("  Resolved bag/slot buttons: " .. tostring(snapshot.resolvedButtons))
	print("  Visible sell-candidate buttons: " .. tostring(snapshot.shouldSellButtons))
	print("  Total sellable bag slots: " .. tostring(snapshot.totalSellableSlots))
end

local function ShowSlashHelp()
	PrintSlash("Commands")
	print("  /jj - Open options panel")
	print("  /jj toggle - Enable/disable addon")
	print("  /jj debug - Toggle debug mode")
	print("  /jj keep <itemLink|itemID> - Always keep item")
	print("  /jj junk <itemLink|itemID> - Always vendor item")
	print("  /jj clear <itemLink|itemID> - Remove manual override")
	print("  /jj overrides - Show override list counts")
	print("  /jj inspect modules - Show addon/module/source status")
	print("  /jj inspect pricing <itemLink|itemID> - Show per-source pricing diagnostics")
	print("  /jj inspect markers - Show marker settings/mapping diagnostics")
	print("  /jj help - Show this help")
end

function HandleSlashCommand(msg)
	local input = msg and msg:match("^%s*(.-)%s*$") or ""
	if input == "" then
		JustJunk.ConfigModule.ShowConfig()
		return
	end

	local command, arg = input:match("^(%S+)%s*(.-)%s*$")
	if not command then return end
	command = command:lower()
	if arg == "" then arg = nil end

	if command == "toggle" then
		local enabled = not JustJunk.ConfigModule.Get(nil, "enabled")
		JustJunk.ConfigModule.Set(nil, "enabled", enabled)
		PrintSlash(enabled and "|cff00ff00Enabled|r" or "|cffff6666Disabled|r")

	elseif command == "debug" then
		local debugEnabled = not JustJunk.ConfigModule.Get(nil, "debugMode")
		JustJunk.ConfigModule.Set(nil, "debugMode", debugEnabled)
		PrintSlash("Debug mode: " .. (debugEnabled and "ON" or "OFF"))

	elseif command == "config" or command == "options" then
		JustJunk.ConfigModule.ShowConfig()

	elseif command == "status" then
		ShowStatus()

	elseif command == "keep" then
		SetManualOverride("keep", arg)

	elseif command == "junk" or command == "sell" then
		SetManualOverride("junk", arg)

	elseif command == "clear" then
		SetManualOverride("clear", arg)

	elseif command == "overrides" then
		ShowOverrides()

	elseif command == "inspect" then
		if not arg then
			PrintSlash("Usage: /jj inspect <topic>")
			PrintSlash("Topics: modules, pricing <itemLink|itemID>, markers")
			return
		end

		local topic, topicArg = arg:match("^(%S+)%s*(.-)%s*$")
		topic = topic and topic:lower() or nil
		if topicArg == "" then topicArg = nil end

		if topic == "modules" then
			ShowStatus()
		elseif topic == "pricing" then
			InspectPricing(topicArg)
		elseif topic == "markers" then
			InspectMarkers()
		else
			PrintSlash("Unknown inspect topic: '" .. tostring(topic) .. "'")
			PrintSlash("Topics: modules, pricing <itemLink|itemID>, markers")
		end

	elseif command == "help" then
		ShowSlashHelp()

	else
		PrintSlash("Unknown command. Type '/jj help' for available commands.")
	end
end