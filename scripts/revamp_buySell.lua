-- Direktkauf/-verkauf einzelner FillTypes über RevampBuyGoodsDialog, byte-nah portiert aus dem bereits
-- veröffentlichten FS25_ProductionSupplyTrader (productionSupplyTrader_buySell.lua).

---Kauft oder verkauft eine Menge eines FillTypes am Produktionspunkt - läuft serverseitig (siehe Revamp_EventBuySell:run),
---Menge wird dabei zusätzlich auf freie Lagerkapazität (Kauf) bzw. vorhandenen Bestand (Verkauf) sowie beim Kauf auf das verfügbare Farmgeld begrenzt.
---@param fillTypeIndex number FillType-Index
---@param amount number Angeforderte Menge in Litern
---@param buySell boolean true = kaufen, false = verkaufen
function ProductionPoint:ReceiveBuySellEvent(fillTypeIndex, amount, buySell)
	local fillType = g_fillTypeManager:getFillTypeByIndex(fillTypeIndex)
	local currentFillLevel = self.storage:getFillLevel(fillTypeIndex)

	if buySell == true then
		local maxStorage = self.storage:getFreeCapacity(fillTypeIndex)
		local pricePerLiter = fillType.pricePerLiter * 2 * EconomyManager.getPriceMultiplier()
		local currentMoney = g_currentMission:getMoney(self.ownerFarmId)

		if maxStorage < (currentFillLevel + amount) then
			amount = maxStorage
		end

		if currentMoney < (amount * pricePerLiter) then
			amount = math.round(currentMoney / pricePerLiter)
		end

		self.storage:setFillLevel(currentFillLevel + amount, fillTypeIndex)
		g_currentMission:addMoney(-(amount * pricePerLiter), self.ownerFarmId, MoneyType.PURCHASE_PALLETS, true)
	else
		local maxStorage = self.storage:getFillLevel(fillTypeIndex)
		local pricePerLiter = fillType.pricePerLiter * EconomyManager.getPriceMultiplier() * ProductionPoint.DIRECT_SELL_PRICE_FACTOR

		if maxStorage < amount then
			amount = maxStorage
		end

		self.storage:setFillLevel(currentFillLevel - amount, fillTypeIndex)
		g_currentMission:addMoney((amount * pricePerLiter), self.ownerFarmId, MoneyType.SOLD_PRODUCTS, true)
	end
end
