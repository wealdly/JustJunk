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

----------------------------------------------------------------------
-- Configuration Management Functions
----------------------------------------------------------------------

function JustJunk.ConfigModule.Get(module, key)
	if not database or not database.profile then 
		local defaults = GetDefaults()
		if module and defaults.profile and defaults.profile[module] then
			return defaults.profile[module][key]
		else
			return defaults.profile and defaults.profile[key]
		end
	end
	
	if module then
		local moduleConfig = database.profile[module]
		local value = moduleConfig and moduleConfig[key]
		if value ~= nil then
			return value
		end
		
		local defaults = GetDefaults()
		if defaults.profile and defaults.profile[module] then
			return defaults.profile[module][key]
		end
		return nil
	else
		local value = database.profile[key]
		if value ~= nil then
			return value
		end
		
		local defaults = GetDefaults()
		return defaults.profile and defaults.profile[key]
	end
end

function JustJunk.ConfigModule.GetAll(module)
	if not database or not database.profile then return {} end
	return database.profile[module] or {}
end

function JustJunk.ConfigModule.Set(module, key, value)
	if not database or not database.profile then return end
	
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
			overview = {
				type = "group",
				name = "Overview", 
				order = 1,
				args = JustJunk.ConfigUI.CreateGeneralOptions().args
			},
			merchant = {
				type = "group",
				name = "Merchant & Selling",
				order = 2,
				disabled = function()
					return not JustJunk.ConfigModule.Get("merchant", "enabled")
				end,
				args = JustJunk.ConfigUI.CreateMerchantOptions()
			},
			advanced = {
				type = "group",
				name = "Advanced",
				order = 3,
				args = JustJunk.ConfigUI.CreateAdvancedOptions().args
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

function HandleSlashCommand(msg)
	local args = msg:match("^%s*(.-)%s*$") or ""
	local cmd, params = args:match("^(%S*)%s*(.*)$")
	cmd = (cmd or ""):lower()
	params = params or ""
	
	if cmd == "" or cmd == "toggle" then
		local enabled = not JustJunk.ConfigModule.Get(nil, "enabled")
		JustJunk.ConfigModule.Set(nil, "enabled", enabled)
		local statusText = enabled and "|cff00ff00ON|r" or "|cffff6666OFF|r"
		print("|cff00ccffJustJunk:|r " .. statusText)
	elseif cmd == "config" then
		JustJunk.ConfigModule.ShowConfig()
	elseif cmd == "status" then
		print("|cff00ccffJustJunk Status:|r")
		local enabledStatus = JustJunk.ConfigModule.Get(nil, "enabled") and "|cff00ff00ON|r" or "|cffff6666OFF|r"
		local merchantStatus = JustJunk.ConfigModule.Get("merchant", "enabled") and "|cff00ff00ON|r" or "|cffff6666OFF|r"
		print("  Enabled: " .. enabledStatus)
		print("  Merchant: " .. merchantStatus)
		
		-- Show market addon status
		local status = JustJunk.MarketEngine and JustJunk.MarketEngine.GetSourceStatus()
		if status then
			print("  Market Sources: " .. status.activeCount .. " available")
			for sourceID, sourceInfo in pairs(status.sources) do
				if sourceInfo.available then
					print("    " .. sourceInfo.name .. ": Available")
				end
			end
		end
	elseif cmd == "help" then
		print("|cff00ccffJustJunk v1.0.0 Commands:|r")
		print("  /jj [toggle] - Enable/disable addon")
		print("  /jj config - Open options panel")
		print("  /jj status - Show current status")
		print("  /jj help - Show this help")
	else
		print("|cffff6666Unknown command:|r " .. cmd)
		print("Use '/jj help' for available commands")
	end
end