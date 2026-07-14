----------------------------------------------------------------------
-- BankEngine.lua - Bank/warband cleanup: pull sell-candidates into bags
-- Author: wealdly | Version: 1.0.0
----------------------------------------------------------------------

local addonName, JustJunk = ...
JustJunk.BankEngine = {}

local C_Container = C_Container
local C_Item = C_Item
local InCombatLockdown = InCombatLockdown

local PULL_SETTLE = 0.05 -- brief debounce after a move settles
local PULL_TIMEOUT = 0.5 -- advance anyway if no bag update arrives

local bankOpen = false
local pullActive = false
local pullQueue = nil
local pullIndex = 1
local pulledCount = 0
local pendingBag, pendingSlot, pendingID = nil, nil, nil
local pullFrame = CreateFrame("Frame")
local button = nil

----------------------------------------------------------------------
-- Bank container enumeration
----------------------------------------------------------------------

-- Collect the Enum.BagIndex tab IDs "<prefix>1".."<prefix>N" that exist on this
-- client (nil-guarded, so a client lacking one simply contributes nothing).
local function CollectTabIDs(prefix, count)
	local ids = {}
	local BI = Enum.BagIndex or {}
	for i = 1, count do
		local id = BI[prefix .. i]
		if id then ids[#ids + 1] = id end
	end
	return ids
end

-- Bank-side container IDs for this client, mirroring how the bank UI enumerates
-- them. Character tabs replaced the old numbered bank bags in current retail;
-- legacy Bank is only a fallback.
local function GetCharacterBankIDs()
	local ids = CollectTabIDs("CharacterBankTab_", 6)
	if #ids == 0 and Enum.BagIndex and Enum.BagIndex.Bank then
		ids[#ids + 1] = Enum.BagIndex.Bank
	end
	return ids
end

local function GetWarbandBankIDs()
	return CollectTabIDs("AccountBankTab_", 5)
end

-- The warband bank is deliberate account storage, so be stricter there than the
-- merchant logic, which only judges the current character. An item it would sell
-- can still be an alt's upgrade at another level, a transmog appearance, or a
-- container holding collectibles. So keep any equippable gear (Common or better,
-- whether or not its appearance is already collected - stronger than a transmog
-- check, and it also covers alt upgrades) and any container; still let trade
-- goods, consumables, and Poor-quality junk through. (Currencies and other
-- collectibles are already protected by the shared sell logic.)
local function IsWarbandProtected(bag, slot)
	local info = C_Container.GetContainerItemInfo(bag, slot)
	if not info or not info.itemID then return false end
	if (info.quality or 0) <= 0 then return false end -- Poor quality is always junk

	local classID = select(6, C_Item.GetItemInfoInstant(info.itemID))
	return classID == JustJunk.ITEM_CLASS.ARMOR
		or classID == JustJunk.ITEM_CLASS.WEAPON
		or classID == JustJunk.ITEM_CLASS.CONTAINER
end

local function GetFreeBagSlots()
	local free = 0
	for _, bag in ipairs(JustJunk.Utils.GetAllBagIDs()) do
		free = free + (C_Container.GetContainerNumFreeSlots(bag) or 0)
	end
	return free
end

-- A bank slot is a pull candidate when the merchant sell logic would sell it, so
-- the bank cleanup and the merchant sell agree on what counts as junk. Wrapped in
-- pcall so one odd slot can't abort the whole scan.
local function IsPullCandidate(bag, slot)
	if not (JustJunk.ItemEngine and JustJunk.ItemEngine.ShouldSellBagSlot) then
		return false
	end
	local ok, shouldSell = pcall(JustJunk.ItemEngine.ShouldSellBagSlot, bag, slot)
	return ok and shouldSell == true
end

----------------------------------------------------------------------
-- Scan and pull
----------------------------------------------------------------------

local function BuildJunkQueue()
	local queue = {}

	local function scan(bag, warband)
		local slots = C_Container.GetContainerNumSlots(bag) or 0
		for slot = 1, slots do
			if IsPullCandidate(bag, slot) and not (warband and IsWarbandProtected(bag, slot)) then
				queue[#queue + 1] = { bag = bag, slot = slot }
			end
		end
	end

	for _, bag in ipairs(GetCharacterBankIDs()) do scan(bag, false) end

	local includeWarband = not JustJunk.ConfigModule
		or JustJunk.ConfigModule.Get(nil, "bankPullWarband") ~= false
	if includeWarband then
		for _, bag in ipairs(GetWarbandBankIDs()) do scan(bag, true) end
	end

	return queue
end

local function FinishPull(reason)
	pullActive = false
	pullQueue = nil
	pendingBag, pendingSlot, pendingID = nil, nil, nil
	pullFrame:UnregisterEvent("BAG_UPDATE_DELAYED")
	if CursorHasItem and CursorHasItem() then ClearCursor() end
	if pulledCount > 0 then
		JustJunk.Utils.Print(string.format("Pulled %d item(s) from the bank into your bags%s.",
			pulledCount, reason == "bags full" and " (bags now full)" or ""))
	elseif reason == "bags full" then
		JustJunk.Utils.Print("Your bags are full - make room and try again.")
	end
	JustJunk.Utils.Debug("Bank", "Pull finished: " .. reason)
end

-- One item per bag-update settle. Firing the next UseContainerItem before the last
-- move resolves is what floods "item is locked" (and can leave an item stuck locked
-- until relog). We confirm the previous move emptied its slot, then issue the next
-- and wait again. A move that produces no bag update (e.g. a slot that could not
-- transfer) falls through the timeout and is not counted.
local function AdvancePull()
	pullFrame:UnregisterEvent("BAG_UPDATE_DELAYED")

	if pendingBag then
		local after = C_Container.GetContainerItemInfo(pendingBag, pendingSlot)
		if not after or after.itemID ~= pendingID then
			pulledCount = pulledCount + 1
		end
		pendingBag, pendingSlot, pendingID = nil, nil, nil
	end

	if not pullActive then return end
	if not bankOpen then return FinishPull("bank closed") end
	if InCombatLockdown() then return FinishPull("combat") end
	if CursorHasItem and CursorHasItem() then ClearCursor() end
	if GetFreeBagSlots() <= 0 then return FinishPull("bags full") end

	while pullQueue and pullIndex <= #pullQueue do
		local entry = pullQueue[pullIndex]
		pullIndex = pullIndex + 1

		-- Re-check the slot: the bank may have shifted since the scan, and a locked
		-- slot is mid-move. UseContainerItem with the bank open moves the item to the
		-- bags (it does not "use" it in that context).
		local info = C_Container.GetContainerItemInfo(entry.bag, entry.slot)
		if info and not info.isLocked and IsPullCandidate(entry.bag, entry.slot) then
			pendingBag, pendingSlot, pendingID = entry.bag, entry.slot, info.itemID
			pcall(C_Container.UseContainerItem, entry.bag, entry.slot)
			pullFrame:RegisterEvent("BAG_UPDATE_DELAYED")
			JustJunk.Utils.ScheduleOnce("jj_bank_pull", PULL_TIMEOUT, AdvancePull)
			return
		end
	end

	FinishPull("done")
end

pullFrame:SetScript("OnEvent", function()
	if pullActive and pendingBag then
		JustJunk.Utils.ScheduleOnce("jj_bank_pull", PULL_SETTLE, AdvancePull)
	end
end)

function JustJunk.BankEngine.ScanAndPull()
	if pullActive then return end
	if not bankOpen then
		JustJunk.Utils.Print("Open your bank to pull junk from it.")
		return
	end
	if InCombatLockdown() then return end
	if JustJunk.ConfigModule and JustJunk.ConfigModule.Get(nil, "enabled") == false then return end

	pullQueue = BuildJunkQueue()
	pullIndex = 1
	pulledCount = 0

	if #pullQueue == 0 then
		JustJunk.Utils.Print("No sellable junk found in the bank.")
		pullQueue = nil
		return
	end
	if GetFreeBagSlots() <= 0 then
		JustJunk.Utils.Print("Your bags are full - make room first.")
		pullQueue = nil
		return
	end

	pullActive = true
	pendingBag, pendingSlot, pendingID = nil, nil, nil
	JustJunk.Utils.Print(string.format("Found %d junk item(s) in the bank, moving to your bags...", #pullQueue))
	AdvancePull()
end

----------------------------------------------------------------------
-- Floating button (works with the default bank UI and custom bag addons,
-- which suppress the default frame - so anchor to the screen, not the frame)
----------------------------------------------------------------------

-- Bank frames to attach to, most specific first. Custom bag addons hide the
-- default frame and show their own, so anchor to whichever is up; if none is
-- found the button falls back to floating (still movable) near screen centre.
local BANK_FRAME_CANDIDATES = {
	"Baganator_SingleViewBankViewFrame1", "Baganator_CategoryViewBankViewFrame1",
	"Baganator_SingleViewBankViewFrame2", "Baganator_CategoryViewBankViewFrame2",
	"BankPanel", "BankFrame",
}

local function FindBankFrame()
	for _, name in ipairs(BANK_FRAME_CANDIDATES) do
		local f = rawget(_G, name)
		if f and f.IsShown and f:IsShown() then return f end
	end
	return nil
end

-- Anchor the button to the bank frame's top-right (saved offset, so a drag sticks
-- relative to the frame). Floating fallback when no bank frame is visible.
local function AnchorButton(b)
	b:ClearAllPoints()
	local frame = FindBankFrame()
	if frame then
		local pos = JustJunk.ConfigModule and JustJunk.ConfigModule.Get(nil, "bankButtonPos")
		local dx = (type(pos) == "table" and pos.dx) or -4
		local dy = (type(pos) == "table" and pos.dy) or 28
		b:SetParent(frame)
		b:SetFrameStrata(frame:GetFrameStrata())
		b:SetFrameLevel(frame:GetFrameLevel() + 20)
		b:SetPoint("TOPRIGHT", frame, "TOPRIGHT", dx, dy)
	else
		b:SetParent(UIParent)
		b:SetFrameStrata("DIALOG")
		b:SetPoint("CENTER", UIParent, "CENTER", 0, 160)
	end
end

local function SaveButtonOffset(b)
	local frame = b:GetParent()
	if not (frame and frame ~= UIParent and JustJunk.ConfigModule) then return end
	local dx = math.floor((b:GetRight() or 0) - (frame:GetRight() or 0) + 0.5)
	local dy = math.floor((b:GetTop() or 0) - (frame:GetTop() or 0) + 0.5)
	JustJunk.ConfigModule.Set(nil, "bankButtonPos", { dx = dx, dy = dy })
	b:ClearAllPoints()
	b:SetPoint("TOPRIGHT", frame, "TOPRIGHT", dx, dy)
end

local function EnsureButton()
	if button then return button end

	local b = CreateFrame("Button", "JustJunkBankPullButton", UIParent)
	b:SetSize(24, 24)

	local border = b:CreateTexture(nil, "BACKGROUND")
	border:SetPoint("TOPLEFT", -1, 1)
	border:SetPoint("BOTTOMRIGHT", 1, -1)
	border:SetColorTexture(0, 0, 0, 0.8)

	b:SetNormalTexture("Interface\\ICONS\\INV_Misc_Coin_01")
	local nt = b:GetNormalTexture()
	if nt then nt:SetTexCoord(0.08, 0.92, 0.08, 0.92) end

	local hl = b:CreateTexture(nil, "HIGHLIGHT")
	hl:SetAllPoints()
	hl:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
	hl:SetBlendMode("ADD")

	b:SetClampedToScreen(true)
	b:SetMovable(true)
	b:RegisterForDrag("LeftButton")
	b:SetScript("OnDragStart", b.StartMoving)
	b:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		SaveButtonOffset(self)
	end)
	b:SetScript("OnClick", function() JustJunk.BankEngine.ScanAndPull() end)
	b:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:SetText("JustJunk: Pull Junk")
		GameTooltip:AddLine("Move sell-worthy junk from your bank and warband bank into your bags, ready to vendor.", 1, 1, 1, true)
		GameTooltip:AddLine("Drag to reposition.", 0.6, 0.6, 0.6)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function() GameTooltip:Hide() end)
	b:Hide()

	button = b
	return b
end

local function UpdateButtonVisibility()
	local cfg = JustJunk.ConfigModule
	local show = bankOpen and (not cfg or
		(cfg.Get(nil, "enabled") ~= false and cfg.Get(nil, "showBankButton") ~= false))

	if not show then
		if button then button:Hide() end
		return
	end

	local b = EnsureButton()
	-- Defer a frame so a custom bag addon's bank frame is shown before we anchor.
	JustJunk.Utils.ScheduleOnce("jj_bank_anchor", 0, function()
		if not bankOpen then return end
		AnchorButton(b)
		b:Show()
	end)
end

----------------------------------------------------------------------
-- Minimap / data-broker launcher (a universal trigger under any bag addon)
----------------------------------------------------------------------

local function RegisterLauncher()
	local LibStub = rawget(_G, "LibStub")
	if not LibStub then return end
	local ldb = LibStub("LibDataBroker-1.1", true)
	local dbicon = LibStub("LibDBIcon-1.0", true)
	if not (ldb and dbicon) then return end

	local obj = ldb:GetDataObjectByName("JustJunk") or ldb:NewDataObject("JustJunk", {
		type = "launcher",
		icon = "Interface\\ICONS\\INV_Misc_Coin_01",
		label = "JustJunk",
		OnClick = function() JustJunk.BankEngine.ScanAndPull() end,
		OnTooltipShow = function(tooltip)
			tooltip:AddLine("JustJunk")
			tooltip:AddLine("Open your bank, then click to pull sell-worthy junk into your bags.", 1, 1, 1)
		end,
	})

	if not dbicon:IsRegistered("JustJunk") then
		local minimap = JustJunk.db and JustJunk.db.profile and JustJunk.db.profile.minimap
		pcall(dbicon.Register, dbicon, "JustJunk", obj, minimap or {})
	end
end

----------------------------------------------------------------------
-- Initialization
----------------------------------------------------------------------

function JustJunk.BankEngine.Initialize()
	RegisterLauncher()

	local frame = CreateFrame("Frame")
	frame:RegisterEvent("BANKFRAME_OPENED")
	frame:RegisterEvent("BANKFRAME_CLOSED")
	frame:SetScript("OnEvent", function(_, event)
		bankOpen = (event == "BANKFRAME_OPENED")
		if not bankOpen then
			pullActive = false
		end
		UpdateButtonVisibility()
	end)

	if JustJunk.ConfigModule and JustJunk.ConfigModule.RegisterSettingListener then
		JustJunk.ConfigModule.RegisterSettingListener("BankEngine", function(module, key)
			if not module and (key == "showBankButton" or key == "enabled") then
				UpdateButtonVisibility()
			end
		end)
	end

	JustJunk.Utils.Debug("Bank", "Bank engine initialized")
end
