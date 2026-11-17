-- Run from the addon directory with a Lua 5.1 interpreter. Not loaded by WoW.
local function NewEnvironment(forever)
	local env = setmetatable({}, { __index = _G })
	env._G = env
	env.Enum = { ItemClass = {}, TooltipDataLineType = { TradeTimeRemaining = 1 } }
	env.NUM_TOTAL_EQUIPPED_BAG_SLOTS = 1
	env.CANCEL = "Cancel"
	env.ERR_INV_FULL = "Inventory full"
	env.ERR_BAG_FULL = "Bag full"
	env.ERR_LOOT_BAG_FULL = "Loot bag full"
	env.bags, env.sizes, env.families = { [0] = {}, [1] = {} }, { [0] = 0, [1] = 0 }, {}
	env.items, env.prices, env.keptBags, env.setItems = {}, {}, {}, {}
	env.frames, env.timers, env.messages, env.loot = {}, {}, {}, {}
	env.now, env.deleted, env.lootAttempts = 10, 0, 0
	env.GetTime = function() return env.now end
	env.print = function(message) env.messages[#env.messages + 1] = message end
	env.IsShiftKeyDown = function() return env.modifier end
	env.IsControlKeyDown = function() return false end
	env.IsAltKeyDown = function() return false end
	env.UnitIsDeadOrGhost = function() return false end
	env.InCombatLockdown = function() return env.combat end
	env.GetProfessions = function() end
	env.UnitClass = function() return "Mage", "MAGE" end
	env.GetAverageItemLevel = function() return 100 end
	env.GetInventoryItemLink = function() end
	env.ItemLocation = {
		CreateFromBagAndSlot = function(_, bag, slot)
			return { bag = bag, slot = slot, IsValid = function() return true end }
		end,
	}
	env.C_EquipmentSet = {
		GetEquipmentSetIDs = function() return { 1 } end,
		GetItemIDs = function() return env.setItems end,
	}
	env.TooltipUtil = {
		FindLinesFromGetter = function(_, _, bag, slot)
			return env.bags[bag][slot].tradeTimer and { {} } or {}
		end,
	}
	env.C_Container = {
		GetContainerNumSlots = function(bag) return env.sizes[bag] or 0 end,
		GetContainerItemInfo = function(bag, slot) return env.bags[bag][slot] end,
		GetBagSlotFlag = function(bag) return env.keptBags[bag] end,
		GetContainerNumFreeSlots = function(bag)
			local free = 0
			for slot = 1, env.sizes[bag] or 0 do
				if not env.bags[bag][slot] then free = free + 1 end
			end
			return free, env.families[bag] or 0
		end,
		GetContainerItemQuestInfo = function(bag, slot)
			return { isQuestItem = env.bags[bag][slot].quest }
		end,
		GetContainerItemPurchaseInfo = function(bag, slot)
			if env.bags[bag][slot].refund then return { refundSeconds = 120, money = 1 } end
		end,
		PickupContainerItem = function(bag, slot)
			env.cursor = env.bags[bag][slot]
			env.cursorBag, env.cursorSlot = bag, slot
			env.bags[bag][slot] = nil
		end,
	}
	env.C_Item = {
		GetItemInfo = function(link)
			if type(link) == "number" then link = "item:" .. link end
			local item = env.items[link]
			if item and not item.uncached then
				return "Item " .. item.id, link, item.quality, 1, 1, "", "",
					item.maxStack, item.equipSlot or "", 0, item.vendor, item.classID,
					0, item.bindType or 0
			end
		end,
		IsBound = function(location) return env.bags[location.bag][location.slot].bound end,
		GetCurrentItemLevel = function(location)
			return env.items[env.bags[location.bag][location.slot].hyperlink].level or 1
		end,
	}
	env.Auctionator = { API = { v1 = {
		GetAuctionPriceByItemLink = function(caller, link)
			assert(caller == "JustJunk")
			return env.prices[link]
		end,
		GetAuctionPriceByItemID = function() end,
	} } }
	env.C_Timer = { NewTimer = function(delay, callback)
		local timer = { delay = delay, callback = callback }
		timer.Cancel = function() timer.cancelled = true end
		env.timers[#env.timers + 1] = timer
		return timer
	end }
	env.CreateFrame = function()
		local frame = { events = {}, scripts = {} }
		frame.RegisterEvent = function(self, event) self.events[event] = true end
		frame.UnregisterEvent = function(self, event) self.events[event] = nil end
		frame.UnregisterAllEvents = function(self) self.events = {} end
		frame.SetScript = function(self, name, callback) self.scripts[name] = callback end
		env.frames[#env.frames + 1] = frame
		return frame
	end
	env.GetCursorInfo = function()
		if env.cursor then return "item", env.cursor.itemID, env.cursor.hyperlink end
	end
	env.CursorHasItem = function() return env.cursor ~= nil end
	env.ClearCursor = function()
		if env.cursor then env.bags[env.cursorBag][env.cursorSlot] = env.cursor end
		env.cursor = nil
	end
	env.DeleteCursorItem = function()
		assert(env.hardware, "deletion requires a hardware event")
		if env.deleteFailure then return end
		env.deleted = env.deleted + 1
		env.cursor = nil
	end
	env.GetLootSlotLink = function(slot) return env.loot[slot] and env.loot[slot].link end
	env.GetLootSlotInfo = function(slot)
		local loot = env.loot[slot]
		if loot then return 0, "Loot", loot.count, nil, loot.quality or 2, loot.locked end
	end
	env.GetNumLootItems = function()
		local count = 0
		for _ in pairs(env.loot) do count = count + 1 end
		return count
	end
	env.LootSlot = function(slot)
		env.lootAttempts = env.lootAttempts + 1
		if env.errorDuringLoot then env.Fire("UI_ERROR_MESSAGE", 1, env.ERR_INV_FULL) end
		env.lastLootedSlot = slot
	end
	env.BuybackItem = function() end
	env.hooksecurefunc = function(target, name, hook)
		if type(target) == "string" then hook, name, target = name, target, env end
		local original = target[name]
		target[name] = function(...)
			original(...)
			hook(...)
		end
	end
	env.StaticPopupDialogs = {}
	env.StaticPopup_Show = function(which, text1, text2, data)
		if env.popupFailure then return nil end
		local text = string.format(env.StaticPopupDialogs[which].text, text1, text2)
		env.popup = { which = which, data = data, text = text }
		return env.popup
	end
	env.StaticPopup_Hide = function(which)
		if env.popup and env.popup.which == which then env.popup = nil end
	end
	local jj = {}
	local function Load(name)
		local chunk = assert(loadfile(name .. ".lua"))
		setfenv(chunk, env)
		chunk("JustJunk", jj)
	end
	env.Load = Load
	Load("Config_Data")
	jj.IS_FOREVER = forever
	local profile = jj.ConfigData.defaults.profile
	jj.ConfigModule = {
		Get = function(module, key) return (module and profile[module] or profile)[key] end,
		IsDebugMode = function() return false end,
	}
	env.settings = profile.merchant
	Load("Utils")
	Load("MarketEngine")
	Load("ItemEngine")
	Load("Core")
	jj.SetupEvents()
	env.jj = jj
	env.Fire = function(event, ...)
		for _, frame in ipairs(env.frames) do
			if frame.events[event] then frame.scripts.OnEvent(frame, event, ...) end
		end
	end
	env.Tick = function(maxDelay)
		local timers = env.timers
		env.timers = {}
		for _, timer in ipairs(timers) do
			if not timer.cancelled then
				if timer.delay <= (maxDelay or 0) then timer.callback()
				else env.timers[#env.timers + 1] = timer end
			end
		end
	end
	env.Accept = function()
		local popup = assert(env.popup, "expected confirmation")
		env.popup = nil
		env.hardware = true
		env.StaticPopupDialogs[popup.which].OnAccept({}, popup.data)
		env.hardware = false
	end
	env.Put = function(bag, slot, id, vendor, count, quality, maxStack, price)
		local link = "item:" .. id
		env.items[link] = {
			id = id, vendor = vendor, quality = quality or 0,
			maxStack = maxStack or 1, classID = 15,
		}
		env.prices[link] = price
		env.bags[bag][slot] = {
			itemID = id, hyperlink = link, stackCount = count or 1, quality = quality or 0,
			hasNoValue = vendor == 0,
		}
		env.sizes[bag] = math.max(env.sizes[bag], slot)
		return env.bags[bag][slot], env.items[link]
	end
	env.AddLoot = function(id, vendor, count, price)
		local link = "item:" .. id
		env.items[link] = { id = id, vendor = vendor, quality = 2, maxStack = 20, classID = 15 }
		env.prices[link] = price
		env.loot[1] = { link = link, count = count or 1 }
		return link
	end
	return env
end

local tests = {}
tests["Auctionator values whole stacks and uses one consistent value scale"] = function()
	local e = NewEnvironment()
	local _, first = e.Put(0, 1, 1, 10, 10, 1, 20, 100)
	local _, second = e.Put(0, 2, 2, 50, 1, 1, 1, 200)
	first.classID, second.classID = 0, 0
	local link = e.AddLoot(3, 100, 1, 500)
	local junk = assert(e.jj.ItemEngine.FindLowestValueJunkForLoot(link, 1))
	assert(junk.itemID == 2 and junk.value == 200 and junk.lootValue == 500)
end
tests["grey AH listings cannot inflate the value of trash being discarded"] = function()
	local e = NewEnvironment()
	e.Put(0, 1, 1, 1, 10, 0, 20, 100)
	e.Put(0, 2, 2, 50)
	local link = e.AddLoot(3, 100)
	local junk = assert(e.jj.ItemEngine.FindLowestValueJunkForLoot(link, 1))
	assert(junk.itemID == 1 and junk.value == 10)
end
tests["grey incoming loot uses vendor value even with an inflated AH listing"] = function()
	local e = NewEnvironment()
	e.Put(0, 1, 1, 50)
	local link = e.AddLoot(2, 1, 1, 100000)
	e.items[link].quality = 0
	assert(not e.jj.ItemEngine.FindLowestValueJunkForLoot(link, 1))
	e.items[link].vendor = 100
	local junk = assert(e.jj.ItemEngine.FindLowestValueJunkForLoot(link, 1))
	assert(junk.lootValue == 100)
end
tests["cleanup ignores grey AH listings for candidates and the inventory average"] = function()
	local e = NewEnvironment()
	e.Put(0, 1, 1, 1, 1, 0, 1, 100000)
	e.Put(0, 2, 2, 1000, 1, 0, 20, 1000000)
	local junk, report = e.jj.ItemEngine.FindLowestValueJunkForCleanup()
	assert(junk and junk.itemID == 1 and junk.value == 1)
	assert(report.average == 500.5 and report.cutoff == 25.025)
end
tests["strictly greater loot value, bound valuation and unknown prices"] = function()
	local e = NewEnvironment()
	e.Put(0, 1, 1, 100)
	local link = e.AddLoot(2, 100)
	assert(not e.jj.ItemEngine.FindLowestValueJunkForLoot(link, 1))
	local slot, item = e.Put(0, 1, 1, 20, 1, 1)
	item.classID = 0
	assert(not e.jj.ItemEngine.FindLowestValueJunkForLoot(link, 1))
	slot.bound = true
	local junk = assert(e.jj.ItemEngine.FindLowestValueJunkForLoot(link, 1))
	assert(junk.value == 20)
	e.items[link].bindType = 1
	e.prices[link] = 10000
	e.jj.MarketEngine.ClearCache()
	assert(e.jj.ItemEngine.FindLowestValueJunkForLoot(link, 1).lootValue == 100)
end
tests["worthless greys are eligible without changing merchant markers"] = function()
	local e = NewEnvironment()
	e.Put(0, 1, 1, 0)
	local link = e.AddLoot(2, 100)
	assert(e.jj.ItemEngine.FindLowestValueJunkForLoot(link, 1).value == 0)
	assert(not e.jj.ItemEngine.ShouldSellBagSlot(0, 1))
end
tests["item protections and unusable bag slots prevent destruction"] = function()
	for _, protection in ipairs({ "locked", "keep", "bag", "quest", "refund", "trade", "set", "account", "specialty" }) do
		local e = NewEnvironment()
		local slot, item = e.Put(0, 1, 1, 0)
		local link = e.AddLoot(2, 100)
		if protection == "locked" then slot.isLocked = true
		elseif protection == "keep" then e.settings.forceKeepItems[1] = true
		elseif protection == "bag" then e.keptBags[0] = true
		elseif protection == "quest" then slot.quest = true
		elseif protection == "refund" then slot.refund = true
		elseif protection == "trade" then slot.tradeTimer = true
		elseif protection == "set" then e.setItems[1] = 1; e.settings.forceSellItems[1] = true
		elseif protection == "account" then item.bindType = 5
		elseif protection == "specialty" then e.families[0] = 32 end
		assert(not e.jj.ItemEngine.FindLowestValueJunkForLoot(link, 1), protection)
	end
	local e = NewEnvironment()
	e.Put(0, 1, 1, 1)
	e.sizes[0] = 2
	local link = e.AddLoot(2, 100)
	assert(not e.jj.ItemEngine.FindLowestValueJunkForLoot(link, 1))
	e.sizes[0] = 1
	assert(not e.jj.ItemEngine.FindLowestValueJunkForLoot(link, 21))
end
tests["5% and 10% cleanup thresholds exclude stackables and respect strict boundaries"] = function()
	local e = NewEnvironment()
	e.Put(0, 1, 1, 40)
	e.Put(0, 2, 2, 50)
	e.Put(0, 3, 3, 80)
	e.Put(0, 4, 4, 100)
	e.Put(0, 5, 5, 4730, 1, 0, 20)
	local junk, report = e.jj.ItemEngine.FindLowestValueJunkForCleanup()
	assert(junk.itemID == 1 and report.average == 1000 and report.cutoff == 50 and report.count == 1)
	e.settings.cleanupValuePercent = 10
	junk, report = e.jj.ItemEngine.FindLowestValueJunkForCleanup()
	assert(report.cutoff == 100 and report.count == 3)
	e.bags[0][1] = nil
	junk, report = e.jj.ItemEngine.FindLowestValueJunkForCleanup(50)
	assert(not junk and report.cutoff == 50)
end
tests["gear scoring and stackability protect cleanup items on both clients"] = function()
	for _, forever in ipairs({ false, true }) do
		local e = NewEnvironment(forever)
		local slot, item = e.Put(0, 1, 1, 1, 1, 2)
		item.classID, item.equipSlot, slot.bound = 4, "INVTYPE_HEAD", true
		item.level = 100
		e.Put(0, 2, 2, 10000, 1, 0, 20)
		if forever then
			e.JustQuest = { GearScoring = { version = 1, EvaluateItem = function()
				return { status = "upgrade", isUpgrade = true }
			end } }
		end
		assert(not e.jj.ItemEngine.FindLowestValueJunkForCleanup())
	end
end
tests["full bag errors defer until the loot hook and delete only on confirmation"] = function()
	local e = NewEnvironment()
	e.Put(0, 1, 1, 1)
	e.AddLoot(2, 100)
	e.errorDuringLoot = true
	e.LootSlot(1)
	e.Tick()
	assert(not e.popup and e.deleted == 0)
	e.settings.replaceJunkWhenFull = true
	e.LootSlot(1)
	e.Tick()
	assert(e.popup and e.popup.text:find("item:2") and e.deleted == 0)
	e.errorDuringLoot = false
	e.Accept()
	assert(e.deleted == 1 and e.lootAttempts == 2)
	e.Fire("BAG_UPDATE_DELAYED")
	assert(e.lootAttempts == 3 and e.lastLootedSlot == 1)
	e.Fire("BAG_UPDATE_DELAYED")
	assert(e.lootAttempts == 3)
end
tests["stale loot confirmations, cursor conflicts, combat and disabled settings abort"] = function()
	for _, change in ipairs({ "loot", "quantity", "junk", "price", "cursor", "combat", "disabled", "keep" }) do
		local e = NewEnvironment()
		e.Put(0, 1, 1, 1)
		e.AddLoot(2, 100)
		e.settings.replaceJunkWhenFull = true
		e.Fire("UI_ERROR_MESSAGE", 1, e.ERR_INV_FULL)
		e.Tick()
		assert(e.popup)
		if change == "loot" then e.loot[1] = nil
		elseif change == "quantity" then e.loot[1].count = 2
		elseif change == "junk" then e.Put(0, 1, 3, 1)
		elseif change == "price" then e.prices["item:2"] = 200; e.jj.MarketEngine.ClearCache()
		elseif change == "cursor" then e.cursor = e.bags[0][1]
		elseif change == "combat" then e.combat = true
		elseif change == "disabled" then e.settings.replaceJunkWhenFull = false
		elseif change == "keep" then e.settings.forceKeepItems[1] = true end
		e.Accept()
		assert(e.deleted == 0 and e.lootAttempts == 0, change)
	end
end
tests["cleanup confirms one item per click, rescans and never deletes stackables"] = function()
	local e = NewEnvironment()
	e.Put(0, 1, 1, 0)
	e.Put(0, 2, 2, 1)
	e.Put(0, 3, 3, 10000, 1, 0, 20)
	e.jj.StartJunkCleanup()
	assert(e.popup and e.deleted == 0)
	e.Accept()
	assert(e.deleted == 1)
	e.Fire("BAG_UPDATE_DELAYED")
	e.Tick()
	assert(e.popup and e.deleted == 1)
	e.Accept()
	e.Fire("BAG_UPDATE_DELAYED")
	e.Tick()
	assert(e.deleted == 2 and not e.popup and e.bags[0][3])
end
tests["failed deletion restores junk and stops retrying"] = function()
	local e = NewEnvironment()
	e.Put(0, 1, 1, 0)
	e.Put(0, 2, 2, 10000, 1, 0, 20)
	e.deleteFailure = true
	e.jj.StartJunkCleanup()
	e.Accept()
	e.Fire("BAG_UPDATE_DELAYED")
	e.Tick(3)
	assert(e.deleted == 0 and e.bags[0][1] and not e.cursor and not e.popup)
	assert(e.messages[#e.messages]:find("deletion failed"))
end
tests["native auto-loot can make room when multiple loot items remain"] = function()
	local e = NewEnvironment()
	e.Put(0, 1, 1, 1)
	e.AddLoot(2, 100)
	e.items["item:3"] = { id = 3, vendor = 200, quality = 2, maxStack = 1, classID = 15 }
	e.loot[2] = { link = "item:3", count = 1 }
	e.settings.replaceJunkWhenFull = true
	e.Fire("UI_ERROR_MESSAGE", 1, e.ERR_LOOT_BAG_FULL)
	e.Tick()
	assert(e.popup and e.popup.data.lootSlot == 2 and e.deleted == 0)
	e.Accept()
	e.Fire("BAG_UPDATE_DELAYED")
	assert(e.deleted == 1 and e.lastLootedSlot == 2)
end
tests["locked loot never triggers a destructive offer"] = function()
	local e = NewEnvironment()
	e.Put(0, 1, 1, 1)
	e.AddLoot(2, 100)
	e.settings.replaceJunkWhenFull = true
	e.loot[1].locked = true
	e.Fire("UI_ERROR_MESSAGE", 1, e.ERR_BAG_FULL)
	e.Tick()
	assert(not e.popup and e.deleted == 0)
end
tests["loot window opening detects full bags without an error event or hooked LootSlot call"] = function()
	local e = NewEnvironment()
	e.Put(0, 1, 1, 1)
	e.AddLoot(2, 100)
	e.settings.replaceJunkWhenFull = true
	e.Fire("LOOT_OPENED")
	e.Tick(0.25)
	assert(e.popup and e.deleted == 0 and e.lootAttempts == 0)
end
tests["deferred loot window checks do not survive closing the loot window"] = function()
	local e = NewEnvironment()
	e.Put(0, 1, 1, 1)
	e.AddLoot(2, 100)
	e.settings.replaceJunkWhenFull = true
	e.Fire("LOOT_OPENED")
	e.Fire("LOOT_CLOSED")
	e.Tick(0.25)
	assert(not e.popup and e.deleted == 0)
end
tests["loot slot renumbering keeps the selected item confirmation valid"] = function()
	local e = NewEnvironment()
	e.Put(0, 1, 1, 1)
	e.AddLoot(2, 100)
	e.items["item:3"] = { id = 3, vendor = 200, quality = 2, maxStack = 1, classID = 15 }
	e.loot[2] = { link = "item:3", count = 1 }
	e.settings.replaceJunkWhenFull = true
	e.Fire("UI_ERROR_MESSAGE", 1, e.ERR_INV_FULL)
	e.Tick()
	assert(e.popup and e.popup.data.lootSlot == 2)
	e.loot[1], e.loot[2] = e.loot[2], nil
	e.Fire("LOOT_SLOT_CLEARED", 2)
	assert(e.popup and e.popup.data.lootSlot == 1 and e.deleted == 0)
	e.Accept()
	e.Fire("BAG_UPDATE_DELAYED")
	assert(e.deleted == 1 and e.lastLootedSlot == 1)
end
tests["confirmation rechecks item identity if the selected loot moves without a clear event"] = function()
	local e = NewEnvironment()
	e.Put(0, 1, 1, 1)
	e.AddLoot(2, 100)
	e.settings.replaceJunkWhenFull = true
	e.Fire("UI_ERROR_MESSAGE", 1, e.ERR_INV_FULL)
	e.Tick()
	e.loot[2], e.loot[1] = e.loot[1], { link = "item:3", count = 1 }
	e.Accept()
	e.Fire("BAG_UPDATE_DELAYED")
	assert(e.deleted == 1 and e.lastLootedSlot == 2)
end
tests["transiently locked loot is retried without deleting while it is locked"] = function()
	local e = NewEnvironment()
	e.Put(0, 1, 1, 1)
	e.AddLoot(2, 100)
	e.settings.replaceJunkWhenFull = true
	e.loot[1].locked = true
	e.Fire("UI_ERROR_MESSAGE", 1, e.ERR_INV_FULL)
	e.Tick()
	assert(not e.popup and e.deleted == 0)
	e.loot[1].locked = false
	e.Tick(0.1)
	assert(e.popup and e.deleted == 0)
end
tests["permanently unreadable loot stops retrying and logs the actual slot state"] = function()
	local e = NewEnvironment()
	e.Put(0, 1, 1, 1)
	e.AddLoot(2, 100)
	e.settings.replaceJunkWhenFull = true
	e.jj.ConfigModule.IsDebugMode = function() return true end
	e.loot[1].locked = true
	e.Fire("UI_ERROR_MESSAGE", 1, e.ERR_INV_FULL)
	e.Tick()
	for _ = 1, 5 do e.Tick(0.1) end
	assert(not e.popup and e.deleted == 0 and #e.timers == 0)
	assert(e.messages[#e.messages]:find("locked=true"))
end
tests["externally hidden confirmations cannot leave Make Room stuck waiting forever"] = function()
	local e = NewEnvironment()
	e.Put(0, 1, 1, 1)
	e.AddLoot(2, 100)
	e.settings.replaceJunkWhenFull = true
	e.Fire("UI_ERROR_MESSAGE", 1, e.ERR_INV_FULL)
	e.Tick()
	local popup = assert(e.popup)
	e.StaticPopupDialogs[popup.which].OnHide()
	e.popup = nil
	e.Fire("UI_ERROR_MESSAGE", 1, e.ERR_INV_FULL)
	e.Tick()
	assert(e.popup and e.deleted == 0)
end
local function LoadJustLoot(e)
	e.PlaySound = function() end
	e.PlaySoundFile = function() end
	e.MuteSoundFile = function(id) e.mutedSounds[id] = true end
	e.UnmuteSoundFile = function(id) e.mutedSounds[id] = nil end
	e.IsModifiedClick = function() return false end
	e.SlashCmdList = {}
	e.JustLootSettings = { enabled = true }
	e.mutedSounds = {}
	e.UIErrorsFrame = {
		RegisterEvent = function() e.errorsVisible = true end,
		UnregisterEvent = function() e.errorsVisible = false end,
		AddMessage = function() end,
	}
	e.LootFrame = {
		Show = function() e.lootFrameVisible = true end,
		Hide = function()
			e.lootFrameVisible = false
			if e.closeOnHide then e.CloseLoot() end
		end,
		IsShown = function() return e.lootFrameVisible end,
	}
	e.CloseLoot = function()
		e.closedLoot = (e.closedLoot or 0) + 1
		e.loot = {}
		e.Fire("LOOT_CLOSED")
	end
	local chunk = assert(loadfile("..\\JustLoot\\JustLoot.lua"))
	setfenv(chunk, e)
	chunk()
	return e.frames[#e.frames]
end
tests["JustLoot hands off full bags after stopping and restoring the loot UI"] = function()
	local e = NewEnvironment()
	e.Put(0, 1, 1, 1)
	e.AddLoot(2, 100)
	e.items["item:3"] = { id = 3, vendor = 200, quality = 2, maxStack = 1, classID = 15 }
	e.loot[2] = { link = "item:3", count = 1 }
	e.settings.replaceJunkWhenFull = true
	local justLoot = LoadJustLoot(e)
	e.Fire("LOOT_READY")
	assert(justLoot.scripts.OnUpdate and not e.errorsVisible and e.lootAttempts == 2)
	e.Fire("UI_ERROR_MESSAGE", 1, e.ERR_INV_FULL)
	assert(not justLoot.scripts.OnUpdate and e.errorsVisible and e.lootFrameVisible)
	assert(not next(e.mutedSounds))
	e.Tick()
	assert(e.popup and e.popup.data.lootSlot == 2 and e.deleted == 0)
	e.Accept()
	e.Fire("BAG_UPDATE_DELAYED")
	assert(e.deleted == 1 and e.lastLootedSlot == 2 and e.lootAttempts == 3)
end
tests["JustLoot stalled timeout hands off even without a bags-full error event"] = function()
	local e = NewEnvironment()
	e.Put(0, 1, 1, 1)
	e.AddLoot(2, 100)
	e.settings.replaceJunkWhenFull = true
	local justLoot = LoadJustLoot(e)
	e.Fire("LOOT_READY")
	justLoot.scripts.OnUpdate(justLoot, 0.6)
	assert(not justLoot.scripts.OnUpdate and e.errorsVisible and e.lootFrameVisible)
	e.Tick()
	assert(e.popup and e.deleted == 0)
end
tests["Make Room waits for JustLoot to stop before offering to free a slot"] = function()
	local e = NewEnvironment()
	e.Put(0, 1, 1, 1)
	e.AddLoot(2, 100)
	e.settings.replaceJunkWhenFull = true
	local justLoot = LoadJustLoot(e)
	e.Fire("LOOT_OPENED")
	e.Tick(0.25)
	assert(justLoot.scripts.OnUpdate and not e.popup and e.deleted == 0)
	justLoot.scripts.OnUpdate(justLoot, 0.6)
	e.Tick()
	assert(e.popup and e.deleted == 0)
end
tests["JustLoot never hides an already visible loot frame and closes the session under Make Room"] = function()
	local e = NewEnvironment()
	e.Put(0, 1, 1, 1)
	e.AddLoot(2, 100)
	e.settings.replaceJunkWhenFull = true
	local justLoot = LoadJustLoot(e)
	e.closeOnHide, e.lootFrameVisible = true, true
	e.Fire("LOOT_OPENED")
	assert(not e.closedLoot and e.GetNumLootItems() == 1 and e.lootFrameVisible)
	justLoot.scripts.OnUpdate(justLoot, 0.6)
	e.Tick()
	assert(e.popup and not e.closedLoot and e.deleted == 0)
end
tests["repeated loot-open events cannot restart JustLoot while Make Room waits for confirmation"] = function()
	local e = NewEnvironment()
	e.Put(0, 1, 1, 1)
	e.AddLoot(2, 100)
	e.settings.replaceJunkWhenFull = true
	local justLoot = LoadJustLoot(e)
	e.closeOnHide = true
	e.Fire("LOOT_READY")
	justLoot.scripts.OnUpdate(justLoot, 0.6)
	e.Tick()
	assert(e.popup and not justLoot.scripts.OnUpdate)
	local attempts = e.lootAttempts
	e.Fire("LOOT_OPENED")
	e.Fire("LOOT_READY")
	e.Tick(0.25)
	assert(e.popup and not e.closedLoot and not justLoot.scripts.OnUpdate and e.lootAttempts == attempts)
	e.Accept()
	e.Fire("BAG_UPDATE_DELAYED")
	assert(e.deleted == 1 and e.lastLootedSlot == 1)
end
tests["an immediate full-bag failure cannot restart JustLoot after its handoff"] = function()
	local e = NewEnvironment()
	e.Put(0, 1, 1, 1)
	e.AddLoot(2, 100)
	e.settings.replaceJunkWhenFull = true
	e.JustLootSettings = { enabled = true, muteSounds = true }
	local justLoot = LoadJustLoot(e)
	e.JustLootSettings.muteSounds = true
	e.errorDuringLoot = true
	e.Fire("LOOT_READY")
	assert(not justLoot.scripts.OnUpdate and e.errorsVisible and not next(e.mutedSounds))
	e.Tick()
	assert(e.popup and e.deleted == 0)
end
tests["JustLoot handoff stays optional and does not offer deletion with free bag space"] = function()
	local e = NewEnvironment()
	e.Put(0, 1, 1, 1)
	e.AddLoot(2, 100)
	e.sizes[0] = 2
	e.settings.replaceJunkWhenFull = true
	local justLoot = LoadJustLoot(e)
	e.Fire("LOOT_READY")
	justLoot.scripts.OnUpdate(justLoot, 0.6)
	e.Tick()
	assert(not e.popup and e.deleted == 0)
	e.JustJunk = nil
	e.Fire("LOOT_CLOSED")
	e.Fire("LOOT_READY")
	justLoot.scripts.OnUpdate(justLoot, 0.6)
	assert(e.errorsVisible and e.lootFrameVisible)
end
tests["loot data arriving after the stalled check can produce the replacement prompt"] = function()
	local e = NewEnvironment()
	e.Put(0, 1, 1, 1)
	local link = e.AddLoot(2, 100)
	e.items[link].uncached = true
	e.settings.replaceJunkWhenFull = true
	e.Fire("LOOT_OPENED")
	e.Tick(0.25)
	assert(not e.popup)
	e.items[link].uncached = false
	e.Fire("GET_ITEM_INFO_RECEIVED", 2, true)
	e.Tick(0.1)
	assert(e.popup and e.deleted == 0)
end
tests["auto-loot batches prioritize valuable attempted loot instead of the last cheap item"] = function()
	local e = NewEnvironment()
	e.Put(0, 1, 1, 50)
	e.AddLoot(2, 100)
	e.items["item:3"] = { id = 3, vendor = 10, quality = 2, maxStack = 1, classID = 15 }
	e.loot[2] = { link = "item:3", count = 1 }
	e.settings.replaceJunkWhenFull = true
	e.errorDuringLoot = true
	e.LootSlot(1)
	e.LootSlot(2)
	e.Tick()
	assert(e.popup and e.popup.data.lootSlot == 1 and e.deleted == 0)
end
tests["cancel, loot closure and addon disable cancel pending destruction"] = function()
	for _, action in ipairs({ "cancel", "close", "disable" }) do
		local e = NewEnvironment()
		e.Put(0, 1, 1, 0)
		e.AddLoot(2, 100)
		e.settings.replaceJunkWhenFull = true
		e.Fire("UI_ERROR_MESSAGE", 1, e.ERR_INV_FULL)
		e.Tick()
		local popup = assert(e.popup)
		if action == "cancel" then
			e.StaticPopupDialogs[popup.which].OnCancel({}, popup.data)
		elseif action == "close" then
			e.Fire("LOOT_CLOSED")
		else
			e.jj.ConfigData.defaults.profile.enabled = false
			e.jj.SetupEvents()
		end
		e.hardware = true
		e.StaticPopupDialogs[popup.which].OnAccept({}, popup.data)
		e.hardware = false
		e.Tick(3)
		assert(e.deleted == 0 and not e.popup, action)
	end
end
tests["uncached inventory and unknown stack size prevent cleanup"] = function()
	for _, state in ipairs({ "uncached", "stackUnknown" }) do
		local e = NewEnvironment()
		local _, item = e.Put(0, 1, 1, 0)
		e.Put(0, 2, 2, 10000, 1, 0, 20)
		if state == "uncached" then item.uncached = true else item.maxStack = nil end
		e.jj.StartJunkCleanup()
		assert(not e.popup and e.deleted == 0 and e.messages[#e.messages]:find("still loading"))
	end
end
tests["cleanup settings persist and the slash command starts the review"] = function()
	local e = NewEnvironment()
	e.SlashCmdList = {}
	e.Load("Config_UI")
	e.Load("Config_Core")
	e.jj.ConfigModule.Initialize()
	local behavior = e.jj.ConfigUI.CreateSellingOptions().args.behavior.args
	assert(behavior.cleanupValuePercent.get() == 5)
	behavior.cleanupValuePercent.set({}, 10)
	assert(e.JustJunkDB.merchant.cleanupValuePercent == 10)
	e.Put(0, 1, 1, 0)
	e.Put(0, 2, 2, 10000, 1, 0, 20)
	e.SlashCmdList.JUSTJUNK("cleanup")
	assert(e.popup and e.deleted == 0)
	e.jj.ConfigModule.Set(nil, "enabled", false)
	assert(not e.popup and e.deleted == 0)
end

local function LoadRealConfig(e)
	e.SlashCmdList = {}
	e.Load("Config_UI")
	e.Load("Config_Core")
	e.jj.ConfigModule.Initialize()
	e.settings = e.jj.ConfigModule.GetAll("merchant")
end

tests["repair funding handles unlimited guild allowances, balances and failures"] = function()
	for _, case in ipairs({
		{ allowance = -1, guildMoney = 500, money = 0, expected = true },
		{ allowance = 50, guildMoney = 500, money = 500, expected = false },
		{ allowance = 500, guildMoney = 50, money = 500, expected = false },
		{ allowance = 0, guildMoney = 0, money = 50, noRepair = true },
		{ allowance = -1, guildMoney = 500, money = 500, failGuild = true, expected = false, attempts = 2 },
		{ allowance = -1, guildMoney = 500, money = 0, canRepair = false, noRepair = true },
	}) do
		local e = NewEnvironment()
		local cost, calls = 100, {}
		e.MerchantFrame = { IsShown = function() return true end }
		e.CanMerchantRepair = function() return true end
		e.GetRepairAllCost = function() return cost, case.canRepair ~= false end
		e.CanGuildBankRepair = function() return true end
		e.GetGuildBankWithdrawMoney = function() return case.allowance end
		e.GetGuildBankMoney = function() return case.guildMoney end
		e.GetMoney = function() return case.money end
		e.RepairAllItems = function(guild)
			calls[#calls + 1] = guild
			if guild and case.failGuild then error("guild repair denied") end
			cost = 0
		end
		e.Fire("MERCHANT_SHOW")
		if case.noRepair then assert(#calls == 0)
		else assert(#calls == (case.attempts or 1) and calls[#calls] == case.expected) end
	end
end

tests["buyback pauses pending and active selling until merchant closure"] = function()
	for _, startFirst in ipairs({ false, true }) do
		local e = NewEnvironment()
		local calls, native = 0, 0
		e.MerchantFrame = { IsShown = function() return true end }
		e.jj.ItemEngine.SellNextItem = function() calls = calls + 1; return true end
		e.jj.ItemEngine.SellGreyJunkNatively = function() native = native + 1 end
		e.Fire("MERCHANT_SHOW")
		if startFirst then e.Tick(1) end
		local before = native
		e.BuybackItem(1)
		e.Tick(1); e.Tick(1)
		assert(calls == 0 and native == before)
		e.Fire("MERCHANT_SHOW")
		e.Tick(1)
		assert(calls == 0 and native == before, "repeated merchant events must not resume selling")
		e.Fire("MERCHANT_CLOSED")
		e.Fire("MERCHANT_SHOW")
		e.Tick(1); e.Tick(1)
		assert(calls == 1 and native == before + 1)
	end
end

tests["manual overrides switch lists and reject unreadable or invalid items"] = function()
	local e = NewEnvironment()
	LoadRealConfig(e)
	assert(e.jj.ConfigModule.SetItemOverride("keep", "item:101"))
	assert(e.settings.forceKeepItems[101] and not e.settings.forceSellItems[101])
	assert(e.jj.ConfigModule.SetItemOverride("junk", "item:101"))
	assert(e.settings.forceSellItems[101] and not e.settings.forceKeepItems[101])
	assert(e.jj.ConfigModule.SetItemOverride("clear", "item:101"))
	assert(not e.settings.forceSellItems[101] and not e.settings.forceKeepItems[101])
	e.secret = {}
	e.issecretvalue = function(value) return value == e.secret end
	assert(not e.jj.ConfigModule.SetItemOverride("junk", e.secret))
	assert(not e.settings.forceSellItems[101])
	assert(not e.jj.ConfigModule.SetItemOverride("junk", "-1"))
	assert(not e.jj.ConfigModule.SetItemOverride("junk", "1.5"))
	assert(not e.jj.ConfigModule.SetItemOverride("junk", {}))
	assert(not e.jj.ConfigModule.SetItemOverride("junk", math.huge))
end

tests["decision tooltips show actual stack values, update and preserve unknowns"] = function()
	for _, forever in ipairs({ false, true }) do
		local e = NewEnvironment(forever)
		LoadRealConfig(e)
		e.Load("ItemControls")
		e.Put(0, 1, 101, 10, 3, 0, 20, 100)
		local tip = { lines = {}, scripts = {} }
		function tip:IsForbidden() return e.forbidden end
		function tip:AddLine(text) self.lines[#self.lines + 1] = text end
		function tip:AddDoubleLine(left, right) self.lines[#self.lines + 1] = left .. ": " .. right end
		function tip:Show() end
		function tip:HookScript(name, fn) self.scripts[name] = fn end
		function tip:SetBagItem()
			self.lines = {}
			self.scripts.OnTooltipCleared(self)
		end
		e.GameTooltip = tip
		e.jj.ItemControls.Initialize()
		tip:SetBagItem(0, 1)
		assert(tip.lines[1] == "JustJunk: Sell candidate")
		assert(tip.lines[3] == "Vendor (this stack): 30c")
		assert(tip.lines[4] == "AH (this stack): 3s 0c")
		e.jj.ItemControls.AppendDecisionTooltip(tip, 0, 1)
		assert(#tip.lines == 4, "no duplicate tooltip lines")
		e.jj.ConfigModule.SetItemOverride("keep", "101")
		tip:SetBagItem(0, 1)
		assert(tip.lines[1] == "JustJunk: Keep" and tip.lines[2] == "manually kept")
		e.jj.MarketEngine.GetPrice = function() return nil end
		tip:SetBagItem(0, 1)
		assert(tip.lines[4] == "AH (this stack): No price data")
		local tooltipOption = e.jj.ConfigUI.CreateGeneralOptions().args.interface.args.showDecisionTooltips
		tooltipOption.set({}, false)
		assert(tooltipOption and tooltipOption.get() == false, "the toggle is a visible sibling of bag markers")
		tip:SetBagItem(0, 1)
		assert(#tip.lines == 0)
		tooltipOption.set({}, true)
		tip:SetBagItem(0, 1)
		assert(tooltipOption.get() and tip.lines[1] == "JustJunk: Keep")
		e.forbidden = true
		tip:SetBagItem(0, 1)
		assert(#tip.lines == 0)
	end
end

tests["individual override management removes only the selected item"] = function()
	local e = NewEnvironment()
	LoadRealConfig(e)
	e.Put(0, 1, 101, 10)
	e.jj.ConfigModule.SetItemOverride("keep", "101")
	e.jj.ConfigModule.SetItemOverride("keep", "102")
	e.jj.ConfigModule.SetItemOverride("junk", "103")
	local options = e.jj.ConfigUI.CreateSellingOptions().args.overrides.args
	assert(options.keepItems.values()[101] == "Item 101 (101)")
	assert(options.keepItems.values()[102] == "Item (102)", "uncached overrides remain visible")
	options.keepItems.set({}, 101)
	assert(not options.removeKeep.disabled())
	options.removeKeep.func()
	assert(not e.settings.forceKeepItems[101] and e.settings.forceKeepItems[102])
	assert(options.removeKeep.disabled())
	assert(options.vendorItems.values()[103])
	options.vendorItems.set({}, 103)
	options.removeVendor.func()
	assert(not e.settings.forceSellItems[103] and e.settings.forceKeepItems[102])
	options.keepItems.set({}, 102)
	e.jj.ConfigModule.Set("merchant", "forceKeepItems", {})
	assert(options.keepItems.get() == nil and options.removeKeep.disabled(), "external removals reset stale selections")
end

tests["bindings manifest remains readable without registering shortcuts"] = function()
	local file = assert(io.open("Bindings.xml", "r"))
	local xml = file:read("*a")
	file:close()
	assert(not xml:match("<Binding[%s>]"), "JustJunk must not register keybinding actions")
end

local passed = 0
for name, test in pairs(tests) do
	local ok, err = pcall(test)
	assert(ok, name .. ": " .. tostring(err))
	passed = passed + 1
	print("PASS " .. name)
end
print(passed .. " junk disposal tests passed")
