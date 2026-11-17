----------------------------------------------------------------------
-- ItemControls.lua - Item decision tooltips
----------------------------------------------------------------------

local addonName, JustJunk = ...
JustJunk.ItemControls = {}

local function IsSecret(value)
	return issecretvalue and issecretvalue(value)
end

function JustJunk.ItemControls.AppendDecisionTooltip(tooltip, bag, slot)
	if tooltip:IsForbidden() or IsSecret(bag) or IsSecret(slot)
		or type(bag) ~= "number" or type(slot) ~= "number"
		or bag < 0 or bag > JustJunk.BAG_CONSTANTS.MAX_BAGS
		or JustJunk.ConfigModule.Get(nil, "enabled") ~= true
		or JustJunk.ConfigModule.Get("merchant", "showDecisionTooltips") == false
		or tooltip.justJunkDecisionShown then return end
	local ok, shouldSell, reason, _, data = pcall(JustJunk.ItemEngine.GetBagSlotDecision, bag, slot)
	if not ok then
		JustJunk.Utils.Debug("Tooltip", "Decision failed: " .. tostring(shouldSell))
		return
	end
	if IsSecret(reason) or type(reason) ~= "string" or reason == "empty slot" then return end
	tooltip:AddLine("JustJunk: " .. (shouldSell and "Sell candidate" or "Keep"), 0.2, 0.8, 1)
	tooltip:AddLine(reason, 1, 1, 1, true)
	if data and not IsSecret(data.vendorPrice) and not IsSecret(data.stackCount)
		and type(data.vendorPrice) == "number" and type(data.stackCount) == "number" then
		tooltip:AddDoubleLine("Vendor (this stack)", JustJunk.Utils.FormatMoney(data.vendorPrice * data.stackCount))
		if not IsSecret(data.isSoulbound) and not IsSecret(data.bindType)
			and not data.isSoulbound and (data.bindType == JustJunk.BIND_TYPE.NONE
			or data.bindType == JustJunk.BIND_TYPE.EQUIP or data.bindType == JustJunk.BIND_TYPE.USE) then
			local priceOK, price = pcall(JustJunk.MarketEngine.GetPrice, data.itemLink,
				JustJunk.ConfigModule.Get("merchant", "preferredPricingSource"))
			if not priceOK then
				JustJunk.Utils.Debug("Tooltip", "Price lookup failed: " .. tostring(price))
			elseif not IsSecret(price) and type(price) == "number" and price > 0 then
				tooltip:AddDoubleLine("AH (this stack)", JustJunk.Utils.FormatMoney(price * data.stackCount))
			else
				tooltip:AddDoubleLine("AH (this stack)", "No price data")
			end
		end
	end
	tooltip.justJunkDecisionShown = true
	tooltip:Show()
end

function JustJunk.ItemControls.Initialize()
	if GameTooltip and GameTooltip.SetBagItem and type(hooksecurefunc) == "function" then
		GameTooltip:HookScript("OnTooltipCleared", function(tooltip) tooltip.justJunkDecisionShown = nil end)
		hooksecurefunc(GameTooltip, "SetBagItem", JustJunk.ItemControls.AppendDecisionTooltip)
	end
end
