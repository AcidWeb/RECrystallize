local _G = _G
local _, RE = ...
local GUI = LibStub("AceGUI-3.0")
_G.RECrystallize = RE

local time, wipe, collectgarbage, hooksecurefunc, strsplit, next, select, string, tostring, pairs, tonumber, floor, print = _G.time, _G.wipe, _G.collectgarbage, _G.hooksecurefunc, _G.strsplit, _G.next, _G.select, _G.string, _G.tostring, _G.pairs, _G.tonumber, _G.floor, _G.print
local IsLinkType = _G.LinkUtil.IsLinkType
local ExtractLink = _G.LinkUtil.ExtractLink
local Round = _G.Round
local PlaySound = _G.PlaySound
local GetRealmName = _G.GetRealmName
local SecondsToTime = _G.SecondsToTime
local IsShiftKeyDown = _G.IsShiftKeyDown
local SendChatMessage = _G.SendChatMessage
local FormatLargeNumber = _G.FormatLargeNumber
local GetItemCount = _G.GetItemCount
local GetMoneyString = _G.GetMoneyString
local ReplicateItems = _G.C_AuctionHouse.ReplicateItems
local GetNumReplicateItems = _G.C_AuctionHouse.GetNumReplicateItems
local GetReplicateItemInfo = _G.C_AuctionHouse.GetReplicateItemInfo
local GetReplicateItemLink = _G.C_AuctionHouse.GetReplicateItemLink
local ElvUI = _G.ElvUI

RE.DefaultConfig = {["LastScan"] = 0, ["GuildChatPC"] = false, ["DatabaseCleanup"] = 432000, ["DatabaseVersion"] = 1}
RE.GUIInitialized = false
RE.TooltipLink = ""
RE.TooltipItemVariant = ""
RE.TooltipItemID = 0
RE.TooltipCount = 0
RE.PetCageItemID = 82800

local function ElvUISwag(sender)
	if sender == "Livarax-BurningLegion" then
		return [[|TInterface\PvPRankBadges\PvPRank09:0|t ]]
	end
	return nil
end

function RE:OnLoad(self)
	self:RegisterEvent("ADDON_LOADED")
	self:RegisterEvent("AUCTION_HOUSE_SHOW")
	self:RegisterEvent("AUCTION_HOUSE_CLOSED")
end

function RE:OnEvent(self, event, ...)
	if event == "REPLICATE_ITEM_LIST_UPDATE" then
		if not RE.ItemCount then
			RE.ItemCount = GetNumReplicateItems()
		end
		RE.AHButton:SetText(RE.CurrentItem.." / "..RE.ItemCount)
		local price, _, _, _, _, _, _, itemID, status = select(10, GetReplicateItemInfo(RE.CurrentItem))
		if status then
			local link = GetReplicateItemLink(RE.CurrentItem)
			if link then
				local itemStr
				if IsLinkType(link, "battlepet") then
					itemStr = string.match(link, "battlepet:(%d*)")
				else
					itemStr = RE:GetItemString(link)
				end
				if RE.DBTemp[itemID] == nil then
					RE.DBTemp[itemID] = {}
				end
				if RE.DBTemp[itemID][itemStr] ~= nil then
					if price < RE.DBTemp[itemID][itemStr] then
						RE.DBTemp[itemID][itemStr] = price
					end
				else
					RE.DBTemp[itemID][itemStr] = price
				end
			end
			RE.CurrentItem = RE.CurrentItem + 1
			if RE.CurrentItem == RE.ItemCount then
				RE:EndScan()
				RE.AHButton:SetText("Scan finished!")
				PlaySound(_G.SOUNDKIT.AUCTION_WINDOW_CLOSE)
			else
				RE:OnEvent(self, "REPLICATE_ITEM_LIST_UPDATE")
			end
		end
	elseif event == "CHAT_MSG_GUILD" then
		local msg = ...
		if string.match(msg, "^!!!") then
			local itemID, itemStr = 0, ""
			if IsLinkType(msg, "item") then
				itemID = tonumber(string.match(msg, "item:(%d*)"))
				itemStr = RE:GetItemString(msg)
			elseif IsLinkType(msg, "battlepet") then
				itemID = RE.PetCageItemID
				itemStr = string.match(msg, "battlepet:(%d*)")
			end
			if RE.DB[RE.RealmString][itemID] ~= nil and RE.DB[RE.RealmString][itemID][itemStr] ~= nil then
				local pc = "[PC]"
				local price = RE.DB[RE.RealmString][itemID][itemStr].Price
				local scanTime = Round((time() - RE.DB[RE.RealmString][itemID][itemStr].LastSeen) / 60 / 60)
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
				SendChatMessage(pc, "GUILD")
			else
				SendChatMessage("[PC] Never seen it on AH.", "GUILD")
			end
		end
	elseif event == "AUCTION_HOUSE_SHOW" then
		if not RE.GUIInitialized then
			RE.GUIInitialized = true
			hooksecurefunc(_G.AuctionHouseFrame, "SetDisplayMode", RE.HandleButton)
			RE.AHButton = GUI:Create("Button")
			RE.AHButton:SetWidth(139)
			RE.AHButton:SetCallback("OnClick", RE.StartScan)
			RE.AHButton.frame:SetParent(_G.AuctionHouseFrame)
			if RE.IsSkinned then
				RE.AHButton.frame:SetPoint("TOPLEFT", _G.AuctionHouseFrame, "TOPLEFT", 10, -37)
			else
				RE.AHButton.frame:SetPoint("TOPLEFT", _G.AuctionHouseFrame, "TOPLEFT", 170, -511)
			end
			RE.AHButton.frame:Show()
		end
		if time() - RE.Config.LastScan > 1800 then
			RE.AHButton:SetText("Start scan")
			RE.AHButton:SetDisabled(false)
		else
			RE.AHButton:SetText("Scan unavailable")
			RE.AHButton:SetDisabled(true)
		end
	elseif event == "AUCTION_HOUSE_CLOSED" then
		if self:IsEventRegistered("REPLICATE_ITEM_LIST_UPDATE") then
			RE:EndScan()
		end
	elseif event == "ADDON_LOADED" and ... == "RECrystallize" then
		if not _G.RECrystallizeDatabase then
			_G.RECrystallizeDatabase = {}
		end
		if not _G.RECrystallizeSettings then
			_G.RECrystallizeSettings = RE.DefaultConfig
		end
		RE.DB = _G.RECrystallizeDatabase
		RE.Config = _G.RECrystallizeSettings
		RE.RealmString = GetRealmName()
		for key, value in pairs(RE.DefaultConfig) do
			if RE.Config[key] == nil then
				RE.Config[key] = value
			end
		end
		if RE.DB[RE.RealmString] == nil then
			RE.DB[RE.RealmString] = {}
		end

		if RE.Config.GuildChatPC then
			self:RegisterEvent("CHAT_MSG_GUILD")
		end

		_G.GameTooltip:HookScript("OnTooltipSetItem", function(self) RE:TooltipAddPrice(self) end)
		hooksecurefunc("BattlePetToolTip_Show", RE.TooltipPetAddPrice)

		if ElvUI then
			RE.IsSkinned = ElvUI[1].private.skins.blizzard.auctionhouse
			ElvUI[1]:GetModule("Chat"):AddPluginIcons(ElvUISwag)
		else
			RE.IsSkinned = false
		end

		self:UnregisterEvent("ADDON_LOADED")
	end
end

function RE:TooltipAddPrice(self)
	if self:IsForbidden() then return end
	local _, link = self:GetItem()
	if IsLinkType(link, "item") then
		if link ~= RE.TooltipLink then
			RE.TooltipLink = link
			RE.TooltipItemID = tonumber(string.match(link, "item:(%d*)"))
			RE.TooltipItemVariant = RE:GetItemString(link)
			RE.TooltipCount = GetItemCount(RE.TooltipItemID)
		end
		if RE.DB[RE.RealmString][RE.TooltipItemID] ~= nil and RE.DB[RE.RealmString][RE.TooltipItemID][RE.TooltipItemVariant] ~= nil then
			if IsShiftKeyDown() and RE.TooltipCount > 0 then
				self:AddLine("|cFF74D06CAuction House:|r    "..GetMoneyString(RE.DB[RE.RealmString][RE.TooltipItemID][RE.TooltipItemVariant].Price * RE.TooltipCount, true).." (x"..RE.TooltipCount..")", 1, 1, 1)
			else
				self:AddLine("|cFF74D06CAuction House:|r    "..GetMoneyString(RE.DB[RE.RealmString][RE.TooltipItemID][RE.TooltipItemVariant].Price, true), 1, 1, 1)
			end
		end
	end
end

function RE:TooltipPetAddPrice()
	if _G.BattlePetTooltip:IsForbidden() then return end
	local speciesID = tostring(_G.BattlePetTooltip.speciesID)
	if RE.DB[RE.RealmString][RE.PetCageItemID] ~= nil and RE.DB[RE.RealmString][RE.PetCageItemID][speciesID] ~= nil then
		local text = _G.BattlePetTooltip.Owned:GetText()
		if text == nil then
			text = ""
		else
			text = text.."    "
		end
		_G.BattlePetTooltip.Owned:SetText(text.."|cFF74D06CAH:|r |cFFFFFFFF"..GetMoneyString(RE.DB[RE.RealmString][RE.PetCageItemID][speciesID].Price, true).."|r")
		_G.BattlePetTooltip:SetSize(260, 145)
	end
end

function RE:HandleButton(mode)
	if mode == _G.AuctionHouseFrameDisplayMode.Buy then
		RE.AHButton.frame:Show()
	else
		RE.AHButton.frame:Hide()
	end
end

function RE:StartScan()
	RE.DBTemp = {}
	RE.ScanStats = {0, 0, 0}
	RE.CurrentItem = 0
	RE.ItemCount = nil
	RE.Config.LastScan = time()
	RE.AHButton:SetText("Waiting...")
	RE.AHButton:SetDisabled(true)
	_G.RECrystallizeFrame:RegisterEvent("REPLICATE_ITEM_LIST_UPDATE")
	ReplicateItems()
end

function RE:EndScan()
	_G.RECrystallizeFrame:UnregisterEvent("REPLICATE_ITEM_LIST_UPDATE")
	RE:SyncDatabase()
	RE:CleanDatabase()
	print("--- |cFF74D06CRE|rCrystallize Report ---\nScan time: "..SecondsToTime(time() - RE.Config.LastScan).."\nNew items: "..RE.ScanStats[1].."\nUpdated items: "..RE.ScanStats[2].."\nRemoved items: "..RE.ScanStats[3])
	wipe(RE.DBTemp)
	collectgarbage("collect")
end

function RE:SyncDatabase()
	for itemID, _ in pairs(RE.DBTemp) do
		if RE.DB[RE.RealmString][itemID] == nil then
			RE.DB[RE.RealmString][itemID] = {}
		end
		for variant, _ in pairs(RE.DBTemp[itemID]) do
			if RE.DB[RE.RealmString][itemID][variant] ~= nil then
					if RE.DBTemp[itemID][variant] ~= RE.DB[RE.RealmString][itemID][variant].Price then
						RE.ScanStats[2] = RE.ScanStats[2] + 1
					end
			else
				RE.ScanStats[1] = RE.ScanStats[1] + 1
			end
			RE.DB[RE.RealmString][itemID][variant] = {["Price"] = RE.DBTemp[itemID][variant], ["LastSeen"] = RE.Config.LastScan}
		end
	end
end

function RE:CleanDatabase()
	for itemID, _ in pairs(RE.DB[RE.RealmString]) do
		for variant, data in pairs(RE.DB[RE.RealmString][itemID]) do
			if RE.Config.LastScan - data.LastSeen > RE.Config.DatabaseCleanup then
				RE.DB[RE.RealmString][itemID][variant] = nil
				RE.ScanStats[3] = RE.ScanStats[3] + 1
			end
		end
		if next(RE.DB[RE.RealmString][itemID]) == nil then
			RE.DB[RE.RealmString][itemID] = nil
		end
	end
end

function RE:GetItemString(link)
	local raw = select(2, ExtractLink(link))
	return select(11, strsplit(":", raw, 11))
end
