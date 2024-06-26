local _, RE = ...
local L = LibStub("AceLocale-3.0"):GetLocale("RECrystallize")
local GUI = LibStub("AceGUI-3.0")
RECrystallize = RE

local sMatch, sFormat = string.match, string.format
local tConcat = table.concat
local Item = Item
local Round = Round
local PlaySound = PlaySound
local GetCVar = GetCVar
local NewTicker = C_Timer.NewTicker
local GetItemInfo = C_Item.GetItemInfo
local GetItemCount = C_Item.GetItemCount
local GetRealmName = GetRealmName
local SecondsToTime = SecondsToTime
local IsShiftKeyDown = IsShiftKeyDown
local SendChatMessage = SendChatMessage
local SetTooltipMoney = SetTooltipMoney
local FormatLargeNumber = FormatLargeNumber
local IsLinkType = LinkUtil.IsLinkType
local ExtractLink = LinkUtil.ExtractLink
local ReplicateItems = C_AuctionHouse.ReplicateItems
local GetNumReplicateItems = C_AuctionHouse.GetNumReplicateItems
local GetReplicateItemInfo = C_AuctionHouse.GetReplicateItemInfo
local GetReplicateItemLink = C_AuctionHouse.GetReplicateItemLink
local GetItemMaxStackSizeByID = C_Item.GetItemMaxStackSizeByID
local TransmogGetItemInfo = C_TransmogCollection.GetItemInfo
local AddTooltipPostCall = TooltipDataProcessor.AddTooltipPostCall
local ElvUI = ElvUI

local PETCAGEID = 82800

RE.DefaultConfig = {["LastScan"] = 0, ["GuildChatPC"] = false, ["DatabaseCleanup"] = 432000, ["AlwaysShowAll"] = false, ["DatabaseVersion"] = 2}
RE.GUIInitialized = false
RE.RecipeLock = false
RE.ScanFinished = false
RE.BlockTooltip = 0
RE.TooltipLink = ""
RE.TooltipItemVariant = ""
RE.TooltipIcon = ""
RE.TooltipItemID = 0
RE.TooltipCount = 0
RE.TooltipCustomCount = -1
RE.TooltipRecipe = {}
RE.CurrentRecord = {}
RE.BonusIDCache = {}

local function tCount(table)
	local count = 0
	for _ in pairs(table) do
		count = count + 1
	end
	return count
end

local function GetPetMoneyString(money, size)
	local goldString, silverString
	local gold = floor(money / (COPPER_PER_SILVER * SILVER_PER_GOLD))
	local silver = floor((money - (gold * COPPER_PER_SILVER * SILVER_PER_GOLD)) / COPPER_PER_SILVER)

    goldString = GOLD_AMOUNT_TEXTURE_STRING:format(FormatLargeNumber(gold), size, size)
    silverString = SILVER_AMOUNT_TEXTURE:format(silver, size, size)

	local moneyString = ""
	local separator = ""
	if gold > 0 then
		moneyString = goldString
		separator = " "
	end
	if silver > 0 then
		moneyString = moneyString..separator..silverString
	end

	return moneyString
end

function RE:OnLoad(self)
	self:RegisterEvent("ADDON_LOADED")
	self:RegisterEvent("AUCTION_HOUSE_SHOW")
	self:RegisterEvent("AUCTION_HOUSE_CLOSED")
end

function RE:OnEvent(self, event, ...)
	if event == "REPLICATE_ITEM_LIST_UPDATE" then
		if RE.WarningTimer then
			RE.WarningTimer:Cancel()
		end
		self:UnregisterEvent("REPLICATE_ITEM_LIST_UPDATE")
		RE:Scan()
	elseif event == "CHAT_MSG_GUILD" then
		local msg = ...
		if sMatch(msg, "^!!!") then
			local itemID, itemVariant = nil, ""
			if IsLinkType(msg, "item") then
				itemID = tonumber(sMatch(msg, "item:(%d+)"))
				itemVariant = RE:GetItemString(msg)
			elseif IsLinkType(msg, "battlepet") then
				itemID = PETCAGEID
				itemVariant = RE:GetPetString(msg)
			end
			RE.CurrentRecord = RE:GetDBRecord(itemID)
			if RE.CurrentRecord ~= nil then
				local suffix = ""
				if RE.CurrentRecord[itemVariant] == nil then
					itemVariant = RE:GetCheapestVariant(RE.CurrentRecord)
					suffix = " - Partial match"
				end
				if RE.CurrentRecord[itemVariant] ~= nil then
					local pc = "[PC]"
					local price = RE.CurrentRecord[itemVariant].Price
					local scanTime = Round((time() - RE.CurrentRecord[itemVariant].LastSeen) / 60 / 60)
					local g = floor(price / 100 / 100)
					local s = floor((price / 100) % 100)
					if g > 0 then
						pc = pc.." "..FormatLargeNumber(g).."g"
					end
					if s > 0 then
						pc = pc.." "..s.."s"
					end
					if scanTime > 0 then
						pc = pc.." - Data is "..scanTime.."h old"
					else
						pc = pc.." - Data is <1h old"
					end
					SendChatMessage(pc..suffix, "GUILD")
				else
					SendChatMessage("[PC] Item not found in AH database.", "GUILD")
				end
			else
				SendChatMessage("[PC] Item not found in AH database.", "GUILD")
			end
		end
	elseif event == "AUCTION_HOUSE_SHOW" then
		if not RE.GUIInitialized then
			RE.GUIInitialized = true

			hooksecurefunc(AuctionHouseFrame, "SetDisplayMode", RE.HandleButton)
			local function HijackOnEnterCallback(owner, rowData)
				if rowData.itemKey then
					if rowData.itemKey.battlePetSpeciesID > 0 then
						RE.BlockTooltip = rowData.itemKey.battlePetSpeciesID
					else
						RE.BlockTooltip = rowData.itemKey.itemID
					end
				end
				AuctionHouseUtil.LineOnEnterCallback(owner, rowData)
			end
			AuctionHouseFrame.BrowseResultsFrame.ItemList:SetLineOnEnterCallback(HijackOnEnterCallback)

			RE.AHButton = GUI:Create("Button")
			RE.AHButton:SetWidth(139)
			RE.AHButton:SetCallback("OnClick", RE.StartScan)
			RE.AHButton.frame:SetParent(AuctionHouseFrame)
			RE.AHButton.frame:ClearAllPoints()
			if RE.IsSkinned then
				RE.AHButton.frame:SetPoint("TOPLEFT", AuctionHouseFrame, "TOPLEFT", 10, -37)
			else
				RE.AHButton.frame:SetPoint("TOPLEFT", AuctionHouseFrame, "TOPLEFT", 170, -511)
			end
			RE.AHButton.frame:Show()
		end
		if time() - RE.Config.LastScan > 1200 then
			RE.AHButton:SetText(L["Start scan"])
			RE.AHButton:SetDisabled(false)
		else
			RE.AHButton:SetText(L["Scan unavailable"])
			RE.AHButton:SetDisabled(true)
		end
	elseif event == "AUCTION_HOUSE_CLOSED" then
		RE.BlockTooltip = 0
		if RE.WarningTimer then
			RE.WarningTimer:Cancel()
		end
	elseif event == "ADDON_LOADED" and ... == "RECrystallize" then
		self:UnregisterEvent("ADDON_LOADED")
		ProfessionsFrame_LoadUI()

		if not RECrystallizeDatabase then
			RECrystallizeDatabase = {}
		end
		if not RECrystallizeSettings then
			RECrystallizeSettings = RE.DefaultConfig
		end
		RE.DB = RECrystallizeDatabase
		RE.Config = RECrystallizeSettings
		RE.RealmString = GetRealmName()
		RE.RegionString = GetCVar("portal")
		for key, value in pairs(RE.DefaultConfig) do
			if RE.Config[key] == nil then
				RE.Config[key] = value
			end
		end
		if RE.DefaultConfig.DatabaseVersion > RE.Config.DatabaseVersion then
			wipe(RE.DB)
			RE.Config.DatabaseVersion = RE.DefaultConfig.DatabaseVersion
		end
		if RE.DB[RE.RealmString] == nil then
			RE.DB[RE.RealmString] = {}
		end
		if RE.DB[RE.RegionString] == nil then
			RE.DB[RE.RegionString] = {}
		end

		local AceConfig = {
			type = "group",
			args = {
				minimap = {
					name = L["Always display the price of the entire stock"],
					desc = L["When enabled the functionality of the SHIFT button will be swapped."],
					type = "toggle",
					width = "full",
					order = 1,
					set = function(_, val) RE.Config.AlwaysShowAll = val end,
					get = function(_) return RE.Config.AlwaysShowAll end
				},
				dbcleanup = {
					name = L["Data freshness"],
					desc = L["The number of days after which old data will be deleted."],
					type = "range",
					width = "double",
					order = 2,
					min = 1,
					max = 14,
					step = 1,
					set = function(_, val) RE.Config.DatabaseCleanup = val * 86400 end,
					get = function(_) return RE.Config.DatabaseCleanup / 86400 end
				},
				dbpurgerealm = {
					name = L["Purge this server database"],
					desc = L["WARNING! This operation is not reversible!"],
					type = "execute",
					width = "double",
					order = 3,
					confirm = true,
					func = function() RE.DB[RE.RealmString] = {}; collectgarbage("collect") end
				},
				dbpurgeregion = {
					name = L["Purge this region database"],
					desc = L["WARNING! This operation is not reversible!"],
					type = "execute",
					width = "double",
					order = 4,
					confirm = true,
					func = function() RE.DB[RE.RegionString] = {}; collectgarbage("collect") end
				},
				separator = {
					type = "header",
					name = STATISTICS,
					order = 5
				},
				description = {
					type = "description",
					name = function(_)
						local timeLeft = 1200 - (time() - RE.Config.LastScan)
						local timeString = timeLeft > 0 and SecondsToTime(timeLeft) or L["Now"]
						local timeLast = RE.RegionString == "US" and date("%I:%M %p %m/%d/%y", RE.Config.LastScan) or date("%H:%M %d.%m.%y", RE.Config.LastScan)
						local s = L["Previous scan"]..": "..timeLast.."\n"..L["Next scan available in"]..": "..timeString.."\n\n"..L["Items in database"]..":\n"

						for server, data in pairs(RE.DB) do
							s = s..server.." - "..tCount(data).."\n"
						end

						return s
					end,
					order = 6
				}
			}
		}
		LibStub("AceConfigRegistry-3.0"):RegisterOptionsTable("RECrystallize", AceConfig)
		LibStub("AceConfigDialog-3.0"):AddToBlizOptions("RECrystallize", "RECrystallize")

		if RE.Config.GuildChatPC then
			self:RegisterEvent("CHAT_MSG_GUILD")
		end

		if RE.Config.LastScan > time() then
			RE.Config.LastScan = time()
		end

		AddTooltipPostCall(Enum.TooltipDataType.Item, function(tt, data) RE:TooltipAddPrice(tt, data); RE.TooltipCustomCount = -1 end)
		GameTooltip:HookScript("OnTooltipCleared", function(_) RE.RecipeLock = false end)

		hooksecurefunc("BattlePetToolTip_Show", function(speciesID, level, breedQuality, maxHealth, power, speed) RE:TooltipPetAddPrice(sFormat("|cffffffff|Hbattlepet:%s:%s:%s:%s:%s:%s:0000000000000000:0|h[XYZ]|h|r", speciesID, level, breedQuality, maxHealth, power, speed)) end)
		hooksecurefunc("FloatingBattlePet_Show", function(speciesID, level, breedQuality, maxHealth, power, speed) RE:TooltipPetAddPrice(sFormat("|cffffffff|Hbattlepet:%s:%s:%s:%s:%s:%s:0000000000000000:0|h[XYZ]|h|r", speciesID, level, breedQuality, maxHealth, power, speed)) end)
		hooksecurefunc(Professions, "FlyoutOnElementEnterImplementation", function(data, tt) RE:TooltipAddPrice(tt, data.item); RE.TooltipCustomCount = -1 end)

		if ElvUI then
			RE.IsSkinned = ElvUI[1].private.skins.blizzard.auctionhouse
		else
			RE.IsSkinned = false
		end
	end
end

function RE:TooltipAddPrice(self, data)
	if self:IsForbidden() then return end
	local link = self.GetItem and select(2, self:GetItem()) or (data.GetItemLink and data:GetItemLink() or data.hyperlink)
	if link and IsLinkType(link, "item") then
		local itemTypeId, itemSubTypeId = select(12, GetItemInfo(link))
		if not RE.RecipeLock and itemTypeId == LE_ITEM_CLASS_RECIPE and itemSubTypeId ~= LE_ITEM_RECIPE_BOOK then
			RE.RecipeLock = true
			return
		else
			RE.RecipeLock = false
		end
		if ProfessionsFrame:IsVisible() then
			local owner = self:GetOwner()
			if owner then
				owner = owner:GetParent()
				if owner and owner.reagentSlotSchematic and owner.reagentSlotSchematic.quantityRequired then
					RE.TooltipCustomCount = owner.reagentSlotSchematic.quantityRequired
					local slot = owner:GetSlotIndex()
					if #owner.transaction.allocationTbls[slot].allocs == 1 then
						link = gsub(link, "item:(%d+)", "item:"..owner.transaction.allocationTbls[slot].allocs[1].reagent.itemID)
					else
						return
					end
				end
			end
		end
		if link ~= RE.TooltipLink then
			RE.TooltipLink = link
			RE.TooltipItemID = tonumber(sMatch(link, "item:(%d+)"))
			RE.TooltipItemVariant = RE:GetItemString(link)
			RE.TooltipCount = GetItemCount(RE.TooltipItemID, true)
			RE.TooltipIcon = ""
		end
		if RE.BlockTooltip == RE.TooltipItemID then return end
		RE.CurrentRecord = RE:GetDBRecord(RE.TooltipItemID)
		if RE.CurrentRecord ~= nil then
			if RE.CurrentRecord[RE.TooltipItemVariant] == nil then
				RE.TooltipItemVariant = RE:GetCheapestVariant(RE.CurrentRecord)
				RE.TooltipIcon = " |TInterface\\AddOns\\RECrystallize\\Icons\\Warning:8|t"
			end
			if RE.CurrentRecord[RE.TooltipItemVariant] ~= nil then
				local shiftPressed = IsShiftKeyDown()
				if ((shiftPressed and not RE.Config.AlwaysShowAll) or (not shiftPressed and RE.Config.AlwaysShowAll)) and (RE.TooltipCount > 0 or RE.TooltipCustomCount > 0) then
					local count = RE.TooltipCustomCount > 0 and RE.TooltipCustomCount or RE.TooltipCount
					SetTooltipMoney(self, RE.CurrentRecord[RE.TooltipItemVariant].Price * count, nil, "|cFF74D06C"..BUTTON_LAG_AUCTIONHOUSE..":|r", " (x"..count..")"..RE.TooltipIcon)
				else
					SetTooltipMoney(self, RE.CurrentRecord[RE.TooltipItemVariant].Price, nil, "|cFF74D06C"..BUTTON_LAG_AUCTIONHOUSE..":|r", RE.TooltipIcon)
				end
			end
		end
	end
end

function RE:TooltipPetAddPrice(link)
	local tt
	if BattlePetTooltip:IsShown() then
		tt = BattlePetTooltip
	elseif FloatingBattlePetTooltip:IsShown() then
		tt = FloatingBattlePetTooltip
	end
	if tt then
		if RE.BlockTooltip == tt.speciesID then return end
		if tt:IsForbidden() then return end
		if link ~= RE.TooltipLink then
			RE.TooltipLink = link
			RE.TooltipItemVariant = RE:GetPetString(link)
		end
		RE.CurrentRecord = RE:GetDBRecord(PETCAGEID)
		if RE.CurrentRecord ~= nil and RE.CurrentRecord[RE.TooltipItemVariant] ~= nil then
			tt:AddLine("|cFF74D06C"..BUTTON_LAG_AUCTIONHOUSE..":|r    |cFFFFFFFF"..GetPetMoneyString(RE.CurrentRecord[RE.TooltipItemVariant].Price, tt.Name:GetStringHeight() * 0.65).."|r")
			tt:SetHeight((select(2, tt.Level:GetFont()) + 4.5) * ((tt.Owned:GetText() ~= nil and 7 or 6) + (tt == FloatingBattlePetTooltip and 1.15 or 0) + tt.linePool:GetNumActive()))
		end
	end
end

function RE:HandleButton(mode)
	if mode == AuctionHouseFrameDisplayMode.Buy or mode == AuctionHouseFrameDisplayMode.ItemBuy or mode == AuctionHouseFrameDisplayMode.CommoditiesBuy then
		RE.AHButton.frame:Show()
	else
		RE.AHButton.frame:Hide()
	end
end

function RE:StartScan()
	RE.DBScan = {}
	RE.DBTemp = {}
	RE.ScanStats = {0, 0, 0}
	RE.Config.LastScan = time()
	RE.AHButton:SetText(L["Waiting..."])
	RE.AHButton:SetDisabled(true)
	RECrystallizeFrame:RegisterEvent("REPLICATE_ITEM_LIST_UPDATE")
	RE.WarningTimer = NewTicker(30, function() print("|cFF9D9D9D[|r|cFF74D06CRE|rCrystallize|cFF9D9D9D]|r "..L["Access to AH data takes longer than usual. This may be caused by server overload."]) end)
	ReplicateItems()
end

function RE:Scan()
	RE.ScanFinished = false
	local num = GetNumReplicateItems()
	local progress = 0
	local inProgress = {}

	for i = 0, num - 1 do
		local link
		local count, quality, _, _, _, _, _, price, _, _, _, _, _, _, itemID, status = select(3, GetReplicateItemInfo(i))
		local stackable = GetItemMaxStackSizeByID(itemID)
		if status and stackable ~= nil and count and price and itemID and type(quality) == "number" and count > 0 and price > 0 and itemID > 0 then
			link = GetReplicateItemLink(i)
			if link then
				progress = progress + 1
				RE.AHButton:SetText(progress.." / "..num)
				RE.DBScan[i] = {["Price"] = price / count, ["ItemID"] = itemID, ["ItemLink"] = link, ["Quality"] = quality, ["Commodity"] = stackable > 1}
			end
		else
			local item = Item:CreateFromItemID(itemID)
			if not item:IsItemEmpty() then
				inProgress[item] = item:ContinueWithCancelOnItemLoad(function()
					count, quality, _, _, _, _, _, price, _, _, _, _, _, _, itemID, status = select(3, GetReplicateItemInfo(i))
					inProgress[item] = nil
					if status and count and price and itemID and type(quality) == "number" and count > 0 and price > 0 and itemID > 0 then
						link = GetReplicateItemLink(i)
						if link then
							progress = progress + 1
							RE.AHButton:SetText(progress.." / "..num)
							RE.DBScan[i] = {["Price"] = price / count, ["ItemID"] = itemID, ["ItemLink"] = link, ["Quality"] = quality, ["Commodity"] = item:IsStackable()}
						end
					end
					if not next(inProgress) then
						inProgress = {}
						RE:EndScan()
					end
				end)
			end
		end
	end

	if not next(inProgress) then
		RE:EndScan()
	else
		RE.TimeoutTimer = NewTicker(15, function()
			for _, v in pairs(inProgress) do
				v()
			end
			inProgress = {}
			RE:EndScan()
		end, 1)
	end
end

function RE:EndScan()
	if RE.ScanFinished then return end
	RE.ScanFinished = true

	if RE.TimeoutTimer then
		RE.TimeoutTimer:Cancel()
		RE.TimeoutTimer = nil
	end

	RE:ParseDatabase()
	RE:SyncDatabase()
	RE:CleanDatabase(RE.RealmString)
	RE:CleanDatabase(RE.RegionString)
	RE.DBScan = {}
	RE.DBTemp = {}
	collectgarbage("collect")

	RE.AHButton:SetText(L["Scan finished!"])
	PlaySound(SOUNDKIT.AUCTION_WINDOW_CLOSE)
	print("|cFF9D9D9D---|r |cFF74D06CRE|rCrystallize "..LANDING_PAGE_REPORT.." |cFF9D9D9D---|r")
	print("|cFF74D06C"..L["Scan time"]..":|r "..SecondsToTime(time() - RE.Config.LastScan))
	print("|cFF74D06C"..L["New items"]..":|r "..RE.ScanStats[1])
	print("|cFF74D06C"..L["Updated items"]..":|r "..RE.ScanStats[2])
	print("|cFF74D06C"..L["Removed items"]..":|r "..RE.ScanStats[3])
end

function RE:ParseDatabase()
	for _, offer in pairs(RE.DBScan) do
		if offer.Quality > 0 or TransmogGetItemInfo(offer.ItemID) then
			local itemStr
			if IsLinkType(offer.ItemLink, "battlepet") then
				itemStr = RE:GetPetString(offer.ItemLink)
			else
				itemStr = RE:GetItemString(offer.ItemLink)
			end
			if RE.DBTemp[offer.ItemID] == nil then
				RE.DBTemp[offer.ItemID] = {["Commodity"] = offer.Commodity}
			end
			if RE.DBTemp[offer.ItemID][itemStr] ~= nil then
				if offer.Price < RE.DBTemp[offer.ItemID][itemStr] then
					RE.DBTemp[offer.ItemID][itemStr] = offer.Price
				end
			else
				RE.DBTemp[offer.ItemID][itemStr] = offer.Price
			end
		end
	end
end

function RE:SyncDatabase()
	for itemID, data in pairs(RE.DBTemp) do
		local targetDB = RE.RealmString
		if data.Commodity then
			targetDB = RE.RegionString
		end
		if RE.DB[targetDB][itemID] == nil then
			RE.DB[targetDB][itemID] = {}
		end
		for variant, _ in pairs(RE.DBTemp[itemID]) do
			if variant ~= "Commodity" then
				if RE.DB[targetDB][itemID][variant] ~= nil then
					if RE.DBTemp[itemID][variant] ~= RE.DB[targetDB][itemID][variant].Price then
						RE.ScanStats[2] = RE.ScanStats[2] + 1
					end
				else
					RE.ScanStats[1] = RE.ScanStats[1] + 1
				end
				RE.DB[targetDB][itemID][variant] = {["Price"] = RE.DBTemp[itemID][variant], ["LastSeen"] = RE.Config.LastScan}
			end
		end
	end
end

function RE:CleanDatabase(targetDB)
	for itemID, _ in pairs(RE.DB[targetDB]) do
		for variant, data in pairs(RE.DB[targetDB][itemID]) do
			if RE.Config.LastScan - data.LastSeen > RE.Config.DatabaseCleanup then
				RE.DB[targetDB][itemID][variant] = nil
				RE.ScanStats[3] = RE.ScanStats[3] + 1
			end
		end
		if next(RE.DB[targetDB][itemID]) == nil then
			RE.DB[targetDB][itemID] = nil
		end
	end
end

function RE:GetDBRecord(itemID)
	if itemID == nil then
		return
	elseif RE.DB[RE.RealmString][itemID] ~= nil then
		return RE.DB[RE.RealmString][itemID]
	elseif RE.DB[RE.RegionString][itemID] ~= nil then
		return RE.DB[RE.RegionString][itemID]
	else
		return
	end
end

function RE:GetItemString(link)
	local raw = select(2, ExtractLink(link))
	RE.BonusIDCache = strsplittable(":", raw)
	local bonusIDNum = RE.BonusIDCache[13]
	if bonusIDNum ~= "" then
		local totalBonusID = 0
		for i=14, 13 + bonusIDNum do
			totalBonusID = totalBonusID + tonumber(RE.BonusIDCache[i])
		end
		return totalBonusID
	end
	return "0"
end

function RE:GetPetString(link)
	local raw = select(2, ExtractLink(link))
	return tConcat({sMatch(raw, "^(%d+):(%d+):(%d+):(%d+):(%d+):(%d+)")}, ":")
end

function RE:GetCheapestVariant(items)
	local target, lowest
	for variant, data in pairs(items) do
		if not lowest or data.Price < lowest then
			lowest = data.Price
			target = variant
		end
	end
	return target
end

-- API

function RECrystallize_PriceCheck(link)
	if link then
		local itemID
		local variant
		local partial = false

		if IsLinkType(link, "item") then
			itemID = tonumber(sMatch(link, "item:(%d+)"))
			variant = RE:GetItemString(link)
		elseif IsLinkType(link, "battlepet") then
			itemID = PETCAGEID
			variant = RE:GetPetString(link)
		else
			return
		end

		RE.CurrentRecord = RE:GetDBRecord(itemID)
		if RE.CurrentRecord ~= nil then
			if itemID ~= PETCAGEID and RE.CurrentRecord[variant] == nil then
				variant = RE:GetCheapestVariant(RE.CurrentRecord)
				partial = true
			end
			if RE.CurrentRecord[variant] ~= nil then
				return RE.CurrentRecord[variant].Price, RE.CurrentRecord[variant].LastSeen, partial
			end
		end
	end
end

function RECrystallize_PriceCheckItemID(itemID)
	if type(itemID) == "number" then
		RE.CurrentRecord = RE:GetDBRecord(itemID)
		if RE.CurrentRecord ~= nil then
			local variant = RE:GetCheapestVariant(RE.CurrentRecord)
			if RE.CurrentRecord[variant] ~= nil then
				return RE.CurrentRecord[variant].Price, RE.CurrentRecord[variant].LastSeen
			end
		end
	end
end