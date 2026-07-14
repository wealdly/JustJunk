----------------------------------------------------------------------
-- BagMarkers.lua - Bag icon markers for sell candidates
-- Author: wealdly | Version: 1.0.0
----------------------------------------------------------------------

local addonName, JustJunk = ...
JustJunk.BagMarkers = JustJunk.BagMarkers or {}

local frame = CreateFrame("Frame")
local merchantOpen = false
local hooksInstalled = false
local markersEnabled = true
local markerStyle = "coin"

-- Per-button overlay state (icon/glow/dim textures + cached border alpha).
-- Weak keys let pooled bag buttons be collected without leaking state.
local buttonState = setmetatable({}, { __mode = "k" })

local function GetState(button)
    local state = buttonState[button]
    if not state then
        state = {}
        buttonState[button] = state
    end
    return state
end

local function RefreshMarkerSettings()
    if not JustJunk.ConfigModule then
        markersEnabled = true
        markerStyle = "coin"
        return
    end

    local style = JustJunk.ConfigModule.Get("merchant", "sellMarkerStyle")
    local enabled = JustJunk.ConfigModule.Get("merchant", "showSellMarkers")
    local merchantEnabled = JustJunk.ConfigModule.Get("merchant", "enabled")

    if style == "off" then
        markersEnabled = false
        markerStyle = "coin"
        return
    end

    markersEnabled = (enabled ~= false) and (merchantEnabled ~= false)
    markerStyle = (style == "coinGlow" or style == "coinDim") and style or "coin"
end

-- The three overlays are always created together, so build them in one pass.
-- Glow keeps its colour/blend from creation (nothing mutates them later).
local function EnsureOverlays(button)
    local state = GetState(button)
    if state.icon then return state end

    local icon = button:CreateTexture(nil, "OVERLAY")
    icon:SetTexture("Interface/Buttons/UI-GroupLoot-Coin-Up")
    icon:SetPoint("TOPLEFT", 2, -2)
    icon:SetSize(14, 14)
    icon:Hide()
    state.icon = icon

    local glow = button:CreateTexture(nil, "OVERLAY")
    glow:SetTexture("Interface/Buttons/UI-ActionButton-Border")
    glow:SetVertexColor(1, 0.82, 0, 0.65)
    glow:SetBlendMode("ADD")
    glow:SetPoint("CENTER")
    glow:SetSize(60, 60)
    glow:Hide()
    state.glow = glow

    local dim = button:CreateTexture(nil, "OVERLAY")
    dim:SetTexture("Interface/Buttons/WHITE8X8")
    dim:SetPoint("TOPLEFT", 1, -1)
    dim:SetPoint("BOTTOMRIGHT", -1, 1)
    dim:SetVertexColor(0, 0, 0, 0.35)
    dim:SetBlendMode("BLEND")
    dim:Hide()
    state.dim = dim

    return state
end

local function IterateFrames(namePrefix, callback)
    local i = 1
    local current = _G[namePrefix .. i]
    while current do
        callback(current)
        i = i + 1
        current = _G[namePrefix .. i]
    end
end

local function ForEachContainerButton(containerFrame, callback)
    if not containerFrame or not callback then return end

    if containerFrame.EnumerateValidItems then
        for _, button in containerFrame:EnumerateValidItems() do
            callback(button)
        end
    elseif containerFrame.Items then
        for _, button in pairs(containerFrame.Items) do
            callback(button)
        end
    elseif containerFrame.GetName then
        local prefix = containerFrame:GetName() .. "Item"
        IterateFrames(prefix, callback)
    end
end

-- Walk the combined-bags frame plus each ContainerFrameN, applying cb to each.
local function ForEachContainer(cb)
    if ContainerFrameCombinedBags then cb(ContainerFrameCombinedBags) end
    IterateFrames("ContainerFrame", cb)
end

-- Hide every overlay on a button and restore its item-border alpha.
local function ResetButton(button, state)
    if state.icon then state.icon:Hide() end
    if state.glow then state.glow:Hide() end
    if state.dim then state.dim:Hide() end
    if button.IconBorder then
        button.IconBorder:SetAlpha(state.borderAlpha ~= nil and state.borderAlpha or 1)
    end
end

local function ResolveBagAndSlot(parentFrame, button)
    if not button then return nil, nil end

    -- Modern item buttons know their own bag and slot (authoritative; correct
    -- for combined bags, where every button shares the same parent frame).
    if button.GetSlotAndBagID then
        local slot, bag = button:GetSlotAndBagID()
        if bag and slot then return bag, slot end
    end

    local slot = button.GetID and button:GetID() or button.slotID or button.slotIndex
    local bag = button.bagID or (button.GetBagID and button:GetBagID())

    -- Legacy single-bag frames: the button belongs to the parent frame's bag.
    if not bag and parentFrame then
        if parentFrame.GetBagID then
            bag = parentFrame:GetBagID()
        elseif parentFrame.GetID then
            bag = parentFrame:GetID()
        end
    end

    return bag, slot
end

local function ShouldSellFromButton(parentFrame, button)
    if not JustJunk.ItemEngine or not JustJunk.ItemEngine.ShouldSellBagSlot then
        return false
    end

    local bag, slot = ResolveBagAndSlot(parentFrame, button)
    if not bag or not slot then return false end

    return JustJunk.ItemEngine.ShouldSellBagSlot(bag, slot)
end

function JustJunk.BagMarkers.UpdateButton(parentFrame, button)
    if not button then return end

    local state = EnsureOverlays(button)
    local icon, glow, dim = state.icon, state.glow, state.dim

    if not markersEnabled or not button:IsShown() then
        ResetButton(button, state)
        return
    end

    local shouldSell = ShouldSellFromButton(parentFrame, button)

    icon:SetShown(shouldSell)
    local showGlow = shouldSell and markerStyle == "coinGlow"
    local showDim = shouldSell and markerStyle == "coinDim"
    glow:SetShown(showGlow)
    dim:SetShown(showDim)

    if button.IconBorder then
        if state.borderAlpha == nil then
            state.borderAlpha = button.IconBorder:GetAlpha()
        end
        button.IconBorder:SetAlpha((showGlow or showDim) and 0 or state.borderAlpha)
    end
end

function JustJunk.BagMarkers.UpdateContainer(containerFrame)
    if not containerFrame then return end

    ForEachContainerButton(containerFrame, function(button)
        JustJunk.BagMarkers.UpdateButton(containerFrame, button)
    end)
end

function JustJunk.BagMarkers.UpdateAll()
    RefreshMarkerSettings()
    ForEachContainer(JustJunk.BagMarkers.UpdateContainer)
end

function JustJunk.BagMarkers.HideAll()
    for button, state in pairs(buttonState) do
        ResetButton(button, state)
    end
end

function JustJunk.BagMarkers.GetDebugSnapshot()
    RefreshMarkerSettings()

    local snapshot = {
        markersEnabled = markersEnabled,
        markerStyle = markerStyle,
        merchantOpen = merchantOpen,
        visibleButtons = 0,
        resolvedButtons = 0,
        shouldSellButtons = 0,
        totalSellableSlots = 0,
    }

    local function ScanContainer(containerFrame)
        if not containerFrame then return end

        local function ScanButton(button)
            if not button or not button.IsShown or not button:IsShown() then return end
            snapshot.visibleButtons = snapshot.visibleButtons + 1

            local bag, slot = ResolveBagAndSlot(containerFrame, button)
            if bag and slot then
                snapshot.resolvedButtons = snapshot.resolvedButtons + 1
            end

            if ShouldSellFromButton(containerFrame, button) then
                snapshot.shouldSellButtons = snapshot.shouldSellButtons + 1
            end
        end

        ForEachContainerButton(containerFrame, ScanButton)
    end

    ForEachContainer(ScanContainer)

    if JustJunk.Utils and JustJunk.Utils.IterateBagSlots and JustJunk.ItemEngine and JustJunk.ItemEngine.ShouldSellBagSlot then
        for bag, slot in JustJunk.Utils.IterateBagSlots() do
            if JustJunk.ItemEngine.ShouldSellBagSlot(bag, slot) then
                snapshot.totalSellableSlots = snapshot.totalSellableSlots + 1
            end
        end
    end

    return snapshot
end

-- Repaint markers off Blizzard's own item-button refresh cycle, so they stay
-- in sync with bag changes, sorting, and selling without polling or debouncing.
local function InstallHooks()
    if hooksInstalled then return end
    hooksInstalled = true

    local function HookContainer(containerFrame)
        if not containerFrame or not containerFrame.UpdateItems then return end
        hooksecurefunc(containerFrame, "UpdateItems", function(self)
            JustJunk.BagMarkers.UpdateContainer(self)
        end)
    end

    local numBagFrames = rawget(_G, "NUM_TOTAL_BAG_FRAMES") or 13
    for i = 1, numBagFrames + 1 do
        HookContainer(rawget(_G, "ContainerFrame" .. i))
    end
    HookContainer(rawget(_G, "ContainerFrameCombinedBags"))

    local eventRegistry = rawget(_G, "EventRegistry")
    if eventRegistry then
        eventRegistry:RegisterCallback("ContainerFrame.OpenBag", function(_, openedFrame)
            if openedFrame then
                JustJunk.BagMarkers.UpdateContainer(openedFrame)
            end
        end, frame)
    end
end

function JustJunk.BagMarkers.Initialize()
    RefreshMarkerSettings()
    InstallHooks()

    if JustJunk.ConfigModule and JustJunk.ConfigModule.RegisterSettingListener then
        -- Every merchant setting except these affects which items are sell
        -- candidates, so repaint markers immediately when one changes. The skipped
        -- keys are sliders that fire rapidly while dragging (and merchantDelay,
        -- which never affects markers); their effect still shows on the next bag
        -- update, avoiding a repaint storm mid-drag.
        local SKIP_MARKER_REFRESH = {
            merchantDelay = true,
            gearSafetyPercent = true,
            gearKeepAbove = true,
            consumableKeepAbove = true,
            tradeGoodKeepAbove = true,
            recipeKeepAbove = true,
        }
        JustJunk.ConfigModule.RegisterSettingListener("BagMarkers", function(module, key)
            if module ~= "merchant" then return end
            if SKIP_MARKER_REFRESH[key] then return end

            RefreshMarkerSettings()

            if markersEnabled then
                JustJunk.BagMarkers.UpdateAll()
            else
                JustJunk.BagMarkers.HideAll()
            end
        end)
    end

    frame:RegisterEvent("MERCHANT_SHOW")
    frame:RegisterEvent("MERCHANT_CLOSED")

    frame:SetScript("OnEvent", function(_, event)
        if event == "MERCHANT_SHOW" then
            merchantOpen = true
        elseif event == "MERCHANT_CLOSED" then
            merchantOpen = false
        end
        JustJunk.BagMarkers.UpdateAll()
    end)

    JustJunk.BagMarkers.UpdateAll()
end
