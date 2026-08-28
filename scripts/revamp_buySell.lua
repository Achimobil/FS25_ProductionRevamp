-- Direktkauf/-verkauf einzelner FillTypes über RevampBuyGoodsDialog, byte-nah portiert aus dem bereits
-- veröffentlichten FS25_ProductionSupplyTrader (productionSupplyTrader_buySell.lua).
--
-- Die Erlaubnis-Prüfung (allowBuying/allowSelling) ist eine Revamp-Ergänzung gegenüber PST: der Modder kann einzelne
-- Fülltypen einer Produktionsstätte vom Kaufen bzw. Verkaufen ausnehmen.

---Liest die Kauf-/Verkaufserlaubnis der Lager-Fülltypen eines Produktionspunktes.
---Ein Fülltyp mit eigener <capacity>-Zeile bringt seine Erlaubnis dort selbst mit, alle übrigen Fülltypen des Lagers stehen nur über <storage>#fillTypeCategories darin und werden deshalb gemeinsam über <storage>#allowBuyingForCategories/#allowSellingForCategories gesteuert.
---@param productionPoint table ProductionPoint-Instanz
---@param xmlFile table XMLFile der Placeable-XML
---@param key string XML-Basispfad des ProductionPoint-Elements
function Revamp.loadBuySellPermissions(productionPoint, xmlFile, key)
	productionPoint.allowFillTypeIdsBuying = {}
	productionPoint.allowFillTypeIdsSelling = {}

	local storage = productionPoint.storage
	if storage == nil then
		return
	end

	local ownCapacityFillTypes = {}
	xmlFile:iterate(key .. ".storage.capacity", function(_, storageKey)
		local fillType = g_fillTypeManager:getFillTypeIndexByName(xmlFile:getValue(storageKey .. "#fillType"))
		if fillType == nil then
			return -- von Vanilla schon abgelehnt/geloggt
		end

		ownCapacityFillTypes[fillType] = true
		productionPoint.allowFillTypeIdsBuying[fillType] = xmlFile:getBool(storageKey .. "#allowBuying", true)
		productionPoint.allowFillTypeIdsSelling[fillType] = xmlFile:getBool(storageKey .. "#allowSelling", true)
	end)

	-- Vanillas Storage:load wertet #fillTypeCategories und #fillTypes exklusiv aus: steht eine Namensliste da, sind die Kategorien wirkungslos - dann gibt es hier auch nichts kategorieweit zu steuern.
	if xmlFile:getValue(key .. ".storage#fillTypeCategories") ~= nil and xmlFile:getValue(key .. ".storage#fillTypes") == nil then
		local allowBuying = xmlFile:getBool(key .. ".storage#allowBuyingForCategories", true)
		local allowSelling = xmlFile:getBool(key .. ".storage#allowSellingForCategories", true)
		-- Bewusst über die <capacity>-Zeilen der XML unterschieden statt über storage.capacities: Revamp.applyCategoryStorageCapacities trägt den Kategorie-Fülltypen selbst eine Kapazität nach, danach sind die beiden Herkünfte dort nicht mehr auseinanderzuhalten.
		for fillType in pairs(storage.fillTypes) do
			if not ownCapacityFillTypes[fillType] then
				productionPoint.allowFillTypeIdsBuying[fillType] = allowBuying
				productionPoint.allowFillTypeIdsSelling[fillType] = allowSelling
			end
		end
	end

	-- Ausgegeben werden nur die tatsächlichen Sperren, erlaubt ist der Normalfall und wäre für jeden Fülltyp des Lagers eine eigene Zeile im Log.
	for fillType, allowed in pairs(productionPoint.allowFillTypeIdsBuying) do
		if not allowed then
			Revamp.DebugText("loadBuySellPermissions(): %s darf nicht gekauft werden", g_fillTypeManager:getFillTypeNameByIndex(fillType))
		end
	end
	for fillType, allowed in pairs(productionPoint.allowFillTypeIdsSelling) do
		if not allowed then
			Revamp.DebugText("loadBuySellPermissions(): %s darf nicht verkauft werden", g_fillTypeManager:getFillTypeNameByIndex(fillType))
		end
	end
end

---Prüft, ob ein Fülltyp an diesem Produktionspunkt gekauft werden darf.
---@param productionPoint table ProductionPoint-Instanz
---@param fillTypeIndex number FillType-Index
---@return boolean allowed true, wenn gekauft werden darf
function Revamp.isBuyingAllowed(productionPoint, fillTypeIndex)
	-- Ein Fülltyp ohne Eintrag gehört gar nicht zum Lager dieses Punktes und wird deshalb nicht zusätzlich gesperrt - kaufen lässt er sich mangels Lagerplatz ohnehin nicht.
	return productionPoint.allowFillTypeIdsBuying == nil or productionPoint.allowFillTypeIdsBuying[fillTypeIndex] ~= false
end

---Prüft, ob ein Fülltyp an diesem Produktionspunkt verkauft werden darf.
---@param productionPoint table ProductionPoint-Instanz
---@param fillTypeIndex number FillType-Index
---@return boolean allowed true, wenn verkauft werden darf
function Revamp.isSellingAllowed(productionPoint, fillTypeIndex)
	return productionPoint.allowFillTypeIdsSelling == nil or productionPoint.allowFillTypeIdsSelling[fillTypeIndex] ~= false
end

---Kauft oder verkauft eine Menge eines FillTypes am Produktionspunkt - läuft serverseitig (siehe Revamp_EventBuySell:run),
---Menge wird dabei zusätzlich auf freie Lagerkapazität (Kauf) bzw. vorhandenen Bestand (Verkauf) sowie beim Kauf auf das verfügbare Farmgeld begrenzt.
---@param fillTypeIndex number FillType-Index
---@param amount number Angeforderte Menge in Litern
---@param buySell boolean true = kaufen, false = verkaufen
---@param connection? table Netzwerkverbindung des auslösenden Spielers, nil wenn der Handel vom eigenen Rechner kommt
function ProductionPoint:ReceiveBuySellEvent(fillTypeIndex, amount, buySell, connection)
	-- Die eigentliche Sperre, nicht nur das Ausblenden der Buttons im Dialog: das Event kommt im Mehrspieler vom Client, geprüft wird deshalb hier auf dem Server.
	if not Revamp.isTradeAllowedForUser(self, connection) then
		return
	end
	if buySell == true and (not Revamp.settings.buyingActive or not Revamp.isBuyingAllowed(self, fillTypeIndex)) then
		return
	end
	if buySell ~= true and (not Revamp.settings.sellingActive or not Revamp.isSellingAllowed(self, fillTypeIndex)) then
		return
	end

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
		local pricePerLiter = fillType.pricePerLiter * EconomyManager.getPriceMultiplier() * Revamp.settings.directSellingPriceFactor

		if maxStorage < amount then
			amount = maxStorage
		end

		self.storage:setFillLevel(currentFillLevel - amount, fillTypeIndex)
		g_currentMission:addMoney((amount * pricePerLiter), self.ownerFarmId, MoneyType.SOLD_PRODUCTS, true)
	end
end
